Chat = {}

local C = Config
local cmd = C.commands

local function started(name) return GetResourceState(name) == 'started' end

-- fivecord has its own staff chat on the same command, so only take it when fivecord isn't here
local ownStaff = not started('fivecord')

local function strip(s)
    s = tostring(s or '')
    local n
    repeat s, n = s:gsub('%^[%d%*_~=r]', '') until n == 0
    return s
end

local function trim(s) return s:match('^%s*(.-)%s*$') end

-- Player text: no colour codes or control characters, trimmed, cut to Config.maxLength.
function Chat.clean(text)
    text = trim(strip(text):gsub('%c', ' '))
    if not utf8.len(text) then text = text:gsub('[\128-\255]', '') end
    if utf8.len(text) > C.maxLength then text = trim(text:sub(1, utf8.offset(text, C.maxLength + 1) - 1)) end
    return text
end

function Chat.name(src, kind)
    if src == 0 then return 'Console' end
    local name = C.names[kind] ~= 'player' and Framework.name(src) or nil
    name = trim(strip(name or GetPlayerName(src)))
    return name ~= '' and name or ('Player %d'):format(src)
end

function Chat.isStaff(src)
    if src == 0 then return true end
    if started('fivecord') then
        local ok, staff = pcall(function() return exports.fivecord:isStaff(src) end)
        if ok then return staff == true end
    end
    return IsPlayerAceAllowed(src, C.staffAce) == true
end

local callJobs = {}
for _, job in ipairs(C.calls.jobs) do callJobs[job] = true end

function Chat.emergency(src)
    local job, duty = Framework.job(src)
    return job ~= nil and callJobs[job] == true and (duty or not C.calls.onDutyOnly)
end

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local function send(target, m) TriggerClientEvent('fivechat:message', target, m) end

function Chat.notify(src, text)
    if src == 0 then return print(text) end
    send(src, { kind = 'system', channel = 'all', text = text })
end

local function message(src, kind, text, channel)
    return { kind = kind, channel = channel, id = src > 0 and src or nil, author = Chat.name(src, kind), text = text }
end

-- Everyone within range in the same routing bucket, and how far away they are.
function Chat.nearby(src, range)
    local out = { [src] = 0.0 }
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return out end
    local here, bucket = GetEntityCoords(ped), GetPlayerRoutingBucket(src)
    for _, id in ipairs(GetPlayers()) do
        local p = tonumber(id)
        local other = GetPlayerPed(p)
        if p ~= src and other ~= 0 and GetPlayerRoutingBucket(p) == bucket then
            local d = #(GetEntityCoords(other) - here)
            if d <= range then out[p] = d end
        end
    end
    return out
end

local function around(src, range, m)
    local far
    for p, d in pairs(Chat.nearby(src, range)) do
        if d > range * 0.5 then
            if not far then far = copy(m); far.far = true end
            send(p, far)
        else
            send(p, m)
        end
    end
end

local function log(src, kind, author, text)
    if not started('fivelog') then return end
    pcall(function()
        exports.fivelog:add('chat', src, ('%s /%s %s'):format(author, cmd[kind], text), { channel = kind, text = text })
    end)
end

-- ----------------------------------------------------------------------- mutes

local mutes = {}

local function key(src) return GetPlayerIdentifierByType(src, 'license') or ('player:%d'):format(src) end

local function duration(minutes)
    minutes = math.floor(minutes + 0.5)
    if minutes < 60 then return ('%dm'):format(minutes) end
    local h, m = minutes // 60, minutes % 60
    return m > 0 and ('%dh %dm'):format(h, m) or ('%dh'):format(h)
end

function Chat.muted(src)
    local k = key(src)
    local m = mutes[k]
    if m == nil then
        local raw = GetResourceKvpString('mute:' .. k)
        m = raw and json.decode(raw) or false
        mutes[k] = m
    end
    if m and m.untilAt <= os.time() then
        mutes[k] = false
        DeleteResourceKvp('mute:' .. k)
        return
    end
    return m or nil
end

local function mutedText(m)
    local left = math.max(1, (m.untilAt - os.time()) / 60)
    local text = ('You are muted for %s more'):format(duration(left))
    return m.reason ~= '' and ('%s: %s'):format(text, m.reason) or text .. '.'
end

local function md(s) return (s:gsub('[\\%*_~`|>]', '\\%0')) end

local function audit(by, panel, title, desc, color)
    local name = by == 0 and 'Console' or ('%s (in game)'):format(GetPlayerName(by))
    TriggerEvent('fivepanel:activity', name, panel)
    if started('fivecord') then
        pcall(function() exports.fivecord:log('staff', title, desc, color) end)
    end
end

function Chat.mute(by, target, minutes, reason)
    reason = trim(strip(reason or ''))
    local k = key(target)
    local m = { untilAt = os.time() + math.floor(minutes * 60), reason = reason }
    mutes[k] = m
    SetResourceKvp('mute:' .. k, json.encode(m))
    Chat.notify(target, mutedText(m))

    local name, staff = strip(GetPlayerName(target)), by == 0 and 'Console' or strip(GetPlayerName(by))
    local len = duration(minutes)
    audit(by, ('muted %s for %s%s'):format(name, len, reason ~= '' and ': ' .. reason or ''), 'Chat mute',
        ('**%s** muted **%s** for %s%s'):format(md(staff), md(name), len, reason ~= '' and '\n' .. md(reason) or ''), 0xf5a524)
end

function Chat.unmute(by, target)
    local k = key(target)
    if not Chat.muted(target) then return false end
    mutes[k] = false
    DeleteResourceKvp('mute:' .. k)
    Chat.notify(target, 'You can talk again.')

    local name, staff = strip(GetPlayerName(target)), by == 0 and 'Console' or strip(GetPlayerName(by))
    audit(by, ('unmuted %s'):format(name), 'Chat unmute', ('**%s** unmuted **%s**'):format(md(staff), md(name)), 0x3dd68c)
    return true
end

-- ------------------------------------------------------------------------ spam

local recent = {}

local function flood(src, text)
    local r = recent[src]
    if not r then
        r = { times = {}, repeats = 0, lastAt = 0 }
        recent[src] = r
    end
    local now, t = GetGameTimer(), r.times
    while t[1] and now - t[1] > C.spam.seconds * 1000 do table.remove(t, 1) end
    if #t >= C.spam.messages then return 'Slow down, you are sending messages too fast.' end

    local same = text:lower()
    if same == r.last and now - r.lastAt < 30000 then
        r.repeats = r.repeats + 1
    else
        r.last, r.repeats = same, 1
    end
    r.lastAt = now
    if r.repeats > C.spam.repeats then return 'You already said that.' end
    t[#t + 1] = now
end

-- The cleaned text, or nothing when it shouldn't go out.
local function accept(src, text, public)
    text = Chat.clean(text)
    if text == '' then return end
    if src == 0 then return text end
    if public then
        local m = Chat.muted(src)
        if m then return Chat.notify(src, mutedText(m)) end
    end
    local why = flood(src, text)
    if why then return Chat.notify(src, why) end
    return text
end

-- -------------------------------------------------------------------- channels

function Chat.say(src, text)
    text = accept(src, text, true)
    if not text then return end
    -- same as the default chat, so anything listening can log it or cancel it
    TriggerEvent('chatMessage', src, GetPlayerName(src), text)
    if WasEventCanceled() then return end

    if C.localChat then
        around(src, C.range.say, message(src, 'say', text, 'local'))
    else
        send(-1, message(src, 'say', text, 'all'))
    end
end

local function emote(kind)
    return function(src, text)
        if src == 0 then return end
        text = accept(src, text, true)
        if not text then return end
        local m = message(src, kind, text, 'local')
        m.overhead = C.overhead[kind] or nil
        around(src, C.range[kind], m)
        log(src, kind, m.author, text)
    end
end

Chat.me = emote('me')
Chat['do'] = emote('do')

function Chat.ooc(src, text)
    text = accept(src, text, true)
    if not text then return end
    local m = message(src, 'ooc', text, 'ooc')
    send(-1, m)
    if src > 0 then log(src, 'ooc', m.author, text) end
end

function Chat.looc(src, text)
    if src == 0 then return end
    text = accept(src, text, true)
    if not text then return end
    around(src, C.range.looc, message(src, 'looc', text, 'ooc'))
end

function Chat.twt(src, text)
    if src == 0 then return end
    text = accept(src, text, true)
    if not text then return end
    local m = message(src, 'twt', text, 'all')
    send(-1, m)
    log(src, 'twt', m.author, text)
end

function Chat.ad(src, text)
    if src == 0 then return end
    text = accept(src, text, true)
    if not text then return end
    if C.ads.cost > 0 and Framework.charge(src, C.ads.cost, C.ads.account, 'Advert') == false then
        return Chat.notify(src, ('An advert costs $%d.'):format(C.ads.cost))
    end
    local m = message(src, 'ad', text, 'all')
    send(-1, m)
    log(src, 'ad', m.author, text)
end

function Chat.call(src, text)
    if src == 0 then return end
    text = accept(src, text, false)
    if not text then return end

    local m = message(src, 'call', text, 'call')
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then
        local pos = GetEntityCoords(ped)
        m.pos = { x = pos.x, y = pos.y, z = pos.z }
    end

    local count = 0
    for _, id in ipairs(GetPlayers()) do
        local p = tonumber(id)
        if Chat.emergency(p) then
            count = count + 1
            send(p, m)
            if m.pos and p ~= src then TriggerClientEvent('fivechat:call', p, { x = m.pos.x, y = m.pos.y, z = m.pos.z, from = m.author, id = src }) end
        end
    end
    if not Chat.emergency(src) then send(src, m) end
    if count == 0 then Chat.notify(src, 'Nobody is available to answer 911 right now.') end
    log(src, 'call', m.author, text)
end

function Chat.staff(src, text)
    if not ownStaff then return end
    if not Chat.isStaff(src) then return Chat.notify(src, 'That is for staff only.') end
    text = accept(src, text, false)
    if not text then return end
    local m = message(src, 'staff', text, 'staff')
    for _, id in ipairs(GetPlayers()) do
        local p = tonumber(id)
        if Chat.isStaff(p) then send(p, m) end
    end
end

-- -------------------------------------------------------------------- commands

local function command(name, fn)
    if not name then return end
    RegisterCommand(name, function(src, args, raw)
        fn(tonumber(src) or 0, raw:match('^%S+%s*(.-)%s*$') or '', args)
    end, false)
end

for _, kind in ipairs({ 'me', 'do', 'ooc', 'looc', 'twt', 'ad', 'call' }) do command(cmd[kind], Chat[kind]) end
if ownStaff then command(cmd.staff, Chat.staff) end

command(cmd.mute, function(src, _, args)
    if not Chat.isStaff(src) then return Chat.notify(src, 'That is for staff only.') end
    local target, minutes = tonumber(args[1]), tonumber(args[2])
    if not target or not GetPlayerName(target) or not minutes or minutes <= 0 then
        return Chat.notify(src, ('Use /%s <id> <minutes> [reason]'):format(cmd.mute))
    end
    Chat.mute(src, target, minutes, table.concat(args, ' ', 3))
    Chat.notify(src, ('Muted %s for %s.'):format(strip(GetPlayerName(target)), duration(minutes)))
end)

command(cmd.unmute, function(src, _, args)
    if not Chat.isStaff(src) then return Chat.notify(src, 'That is for staff only.') end
    local target = tonumber(args[1])
    if not target or not GetPlayerName(target) then return Chat.notify(src, ('Use /%s <id>'):format(cmd.unmute)) end
    local name = strip(GetPlayerName(target))
    Chat.notify(src, Chat.unmute(src, target) and ('Unmuted %s.'):format(name) or ('%s is not muted.'):format(name))
end)

-- Commands nobody registered. The default chat posts them as a message; here old
-- resources that read commands from chatMessage still get them, and otherwise
-- only the player hears about it.
AddEventHandler('__cfx_internal:commandFallback', function(command)
    local src = tonumber(source)
    if src and src > 0 then
        TriggerEvent('chatMessage', src, GetPlayerName(src), '/' .. command)
        if not WasEventCanceled() then
            Chat.notify(src, ('Unknown command /%s'):format(strip(command:match('^%S*'))))
        end
    end
    CancelEvent()
end)

-- ----------------------------------------------------------------- suggestions

local mine = {}
for _, name in pairs(cmd) do if name then mine[name] = true end end

local function suggestion(list, name, help, params)
    if name then list[#list + 1] = { name = '/' .. name, help = help, params = params } end
end

function Chat.suggestions(src)
    local list = {}
    for _, c in ipairs(GetRegisteredCommands and GetRegisteredCommands() or {}) do
        if not mine[c.name] and IsPlayerAceAllowed(src, ('command.%s'):format(c.name)) then
            list[#list + 1] = { name = '/' .. c.name, help = '' }
        end
    end

    local text = { { name = 'message' } }
    suggestion(list, cmd.me, 'Something your character does', { { name = 'action', help = 'what you do' } })
    suggestion(list, cmd['do'], 'What others can see happening', { { name = 'description' } })
    suggestion(list, cmd.ooc, 'Out of character, to everyone', text)
    suggestion(list, cmd.looc, 'Out of character, to people nearby', text)
    suggestion(list, cmd.twt, 'Post a tweet', text)
    suggestion(list, cmd.ad, C.ads.cost > 0 and ('Post an advert for $%d'):format(C.ads.cost) or 'Post an advert', text)
    suggestion(list, cmd.call, 'Call the police and EMS', { { name = 'message', help = 'what happened and where' } })

    if Chat.isStaff(src) then
        if ownStaff then suggestion(list, cmd.staff, 'Talk to staff', text) end
        suggestion(list, cmd.mute, 'Stop a player from talking in chat', {
            { name = 'id', help = 'server id' }, { name = 'minutes' }, { name = 'reason', help = 'optional' },
        })
        suggestion(list, cmd.unmute, 'Let a muted player talk again', { { name = 'id', help = 'server id' } })
    end
    return list
end

function Chat.state(src)
    return {
        id = src,
        names = { trim(strip(GetPlayerName(src))), Framework.name(src) },
        staff = Chat.isStaff(src),
        emergency = Chat.emergency(src),
        ownStaff = ownStaff,
    }
end

AddEventHandler('chat:init', function()
    local src = tonumber(source)
    TriggerClientEvent('chat:addSuggestions', src, Chat.suggestions(src))
    TriggerClientEvent('fivechat:state', src, Chat.state(src))
end)

AddEventHandler('onServerResourceStart', function()
    SetTimeout(500, function()
        for _, id in ipairs(GetPlayers()) do
            TriggerClientEvent('chat:addSuggestions', id, Chat.suggestions(tonumber(id)))
        end
    end)
end)

-- --------------------------------------------------------------------- events

RegisterNetEvent('chat:init')

RegisterNetEvent('fivechat:say', function(text, mode)
    local src = tonumber(source)
    if type(text) ~= 'string' then return end
    if mode == 'ooc' then
        Chat.ooc(src, text)
    elseif mode == 'staff' then
        Chat.staff(src, text)
    else
        Chat.say(src, text)
    end
end)

-- what the default chat's client sends, in case something else sends it too
RegisterNetEvent('_chat:messageEntered', function(_, _, text)
    if type(text) == 'string' then Chat.say(tonumber(source), text) end
end)

local asked = {}
RegisterNetEvent('fivechat:state', function()
    local src = tonumber(source)
    local now = GetGameTimer()
    if asked[src] and now - asked[src] < 3000 then return end
    asked[src] = now
    TriggerClientEvent('fivechat:state', src, Chat.state(src))
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    recent[src], asked[src] = nil, nil
end)

-- -------------------------------------------------------------------- exports

-- same as the default chat's export
exports('addMessage', function(target, m)
    TriggerClientEvent('chat:addMessage', target, m)
end)

exports('isMuted', function(src) return Chat.muted(tonumber(src)) ~= nil end)

exports('mute', function(src, minutes, reason)
    src, minutes = tonumber(src), tonumber(minutes)
    if not src or not GetPlayerName(src) or not minutes or minutes <= 0 then return false end
    Chat.mute(0, src, minutes, reason)
    return true
end)

exports('unmute', function(src)
    src = tonumber(src)
    return src ~= nil and GetPlayerName(src) ~= nil and Chat.unmute(0, src)
end)
