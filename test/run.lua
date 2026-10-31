-- lua5.4 test/run.lua
-- Runs the server side of fivechat against a fake FiveM server.

local passed, failed = 0, 0
local function check(name, cond)
    if cond then passed = passed + 1 else failed = failed + 1; io.write('FAIL ' .. name .. '\n') end
end

-- Events, timers ----------------------------------------------------------------

local handlers = {}
function AddEventHandler(name, fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end

-- cancelling works on the event being handled, WasEventCanceled reads the last one fired
local cancels, lastCanceled = {}, false
function CancelEvent() cancels[#cancels] = true end
function WasEventCanceled() return lastCanceled end
local function dispatch(name, ...)
    cancels[#cancels + 1] = false
    for _, fn in ipairs(handlers[name] or {}) do fn(...) end
    lastCanceled = table.remove(cancels)
end

local triggered = {}
function TriggerEvent(name, ...)
    triggered[#triggered + 1] = { name = name, args = { ... } }
    dispatch(name, ...)
end
local function fire(name, src, ...)
    source = src
    dispatch(name, ...)
end
local function lastEvent(name)
    for i = #triggered, 1, -1 do if triggered[i].name == name then return triggered[i] end end
end

local timers = {}
function SetTimeout(_, fn) timers[#timers + 1] = fn end
function CreateThread() end
function Wait() end
local clock = 100000
function GetGameTimer() return clock end

local toClient = {}
function TriggerClientEvent(name, target, ...) toClient[#toClient + 1] = { name = name, target = target, args = { ... } } end

local stored, n = {}, 0
json = {
    encode = function(t) n = n + 1; local k = 'json#' .. n; stored[k] = t; return k end,
    decode = function(s) return assert(stored[s], 'bad json') end,
}

local kvp = {}
function SetResourceKvp(k, v) kvp[k] = v end
function GetResourceKvpString(k) return kvp[k] end
function DeleteResourceKvp(k) kvp[k] = nil end

-- Players -------------------------------------------------------------------------

local vec = {}
vec.__index = vec
vec.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vec) end
vec.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
local function v3(x, y, z) return setmetatable({ x = x, y = y, z = z or 0 }, vec) end

local players = {}
local started = { fivechat = 'started' }

local function addPlayer(src, name, x, opts)
    opts = opts or {}
    players[src] = { name = name, pos = v3(x or 0, 0, 0), bucket = opts.bucket or 0, job = opts.job, duty = opts.duty ~= false, char = opts.char, aces = opts.aces or {}, staff = opts.staff }
end

function GetPlayers()
    local out = {}
    for src in pairs(players) do out[#out + 1] = tostring(src) end
    table.sort(out, function(a, b) return tonumber(a) < tonumber(b) end)
    return out
end
function GetPlayerName(src) local p = players[tonumber(src)]; return p and p.name end
function GetPlayerPed(src) return players[tonumber(src)] and tonumber(src) + 1000 or 0 end
function GetEntityCoords(e) return players[e - 1000].pos end
function GetPlayerRoutingBucket(src) return players[tonumber(src)].bucket end
function GetPlayerIdentifierByType(src, kind) local p = players[tonumber(src)]; return p and ('%s:%s'):format(kind, p.name:lower()) end
function IsPlayerAceAllowed(src, ace)
    local p = players[tonumber(src)]
    return p ~= nil and (p.aces[ace] == true or ace:find('^command%.') ~= nil)
end
function GetResourceState(name) return started[name] or 'missing' end
function GetCurrentResourceName() return 'fivechat' end

local commands = {}
function RegisterCommand(name, fn) commands[name] = fn end
function GetRegisteredCommands()
    local out = { { name = 'car' } }
    for name in pairs(commands) do out[#out + 1] = { name = name } end
    return out
end
local function run(src, raw)
    local args = {}
    for a in raw:gmatch('%S+') do args[#args + 1] = a end
    local name = table.remove(args, 1)
    assert(commands[name], 'no command ' .. name)(src, args, raw)
end

local registered, fivelogs, fivecordLogs, charged = {}, {}, {}, {}
exports = setmetatable({}, {
    __call = function(_, name, fn) registered[name] = fn end,
    __index = function(_, res)
        if res == 'fivecord' then
            return {
                isStaff = function(_, src) return players[src].staff == true end,
                log = function(_, kind, title, desc, color) fivecordLogs[#fivecordLogs + 1] = { kind = kind, title = title, desc = desc, color = color } end,
            }
        end
        if res == 'fivelog' then
            return { add = function(_, kind, src, text, data) fivelogs[#fivelogs + 1] = { kind = kind, src = src, text = text, data = data } end }
        end
        if res == 'qbx_core' then
            return {
                GetPlayer = function(_, src)
                    local p = players[src]
                    if not p or not p.char then return end
                    return {
                        PlayerData = { charinfo = { firstname = p.char[1], lastname = p.char[2] }, job = { name = p.job, onduty = p.duty } },
                        Functions = { RemoveMoney = function(account, amount) charged[#charged + 1] = { src, account, amount }; return p.money ~= false end },
                    }
                end,
            }
        end
    end,
})

local printed = {}
local realPrint = print
print = function(...) printed[#printed + 1] = table.concat({ ... }, ' ') end

local function load()
    commands, handlers = {}, {}
    for _, f in ipairs({ 'config.lua', 'server/framework.lua', 'server/main.lua' }) do dofile(f) end
end
load()

-- what each player got since `from`
local function inbox(src, from)
    local out = {}
    for i = from or 1, #toClient do
        local e = toClient[i]
        if e.name == 'fivechat:message' and (e.target == src or e.target == -1) then out[#out + 1] = e.args[1] end
    end
    return out
end
local function lastFor(src) local m = inbox(src); return m[#m] end
local function mark() return #toClient + 1 end
local function tick(ms) clock = clock + (ms or 10000) end

-- Tests ----------------------------------------------------------------------------

addPlayer(1, 'Bob', 0)
addPlayer(2, 'Al', 8)
addPlayer(3, 'Cy', 15)
addPlayer(4, 'Di', 60)
addPlayer(5, 'Ed', 2, { bucket = 4 })

do -- local chat goes to people close by, faded for the far half
    local m = mark()
    fire('fivechat:say', 1, 'anyone near legion?')
    check('sender sees it', #inbox(1, m) == 1 and inbox(1, m)[1].text == 'anyone near legion?')
    check('close player, not faded', #inbox(2, m) == 1 and not inbox(2, m)[1].far)
    check('far half faded', #inbox(3, m) == 1 and inbox(3, m)[1].far == true)
    check('out of range gets nothing', #inbox(4, m) == 0)
    check('other routing bucket gets nothing', #inbox(5, m) == 0)
    check('shape', inbox(2, m)[1].kind == 'say' and inbox(2, m)[1].channel == 'local' and inbox(2, m)[1].id == 1 and inbox(2, m)[1].author == 'Bob')
    check('sender copy not faded', not inbox(1, m)[1].far)
end

do -- chatMessage like the default chat, and cancelling it
    local e = lastEvent('chatMessage')
    check('chatMessage fired', e and e.args[1] == 1 and e.args[2] == 'Bob' and e.args[3] == 'anyone near legion?')

    AddEventHandler('chatMessage', function(_, _, text) if text:find('secret') then CancelEvent() end end)
    tick()
    local m = mark()
    fire('fivechat:say', 1, 'a secret thing')
    check('cancelled message not sent', #inbox(2, m) == 0 and #inbox(1, m) == 0)
    fire('fivechat:say', 1, 'not that one')
    check('next one still goes', #inbox(2, m) == 1)
end

do -- global when local chat is off
    Config.localChat = false
    tick()
    local m = mark()
    fire('fivechat:say', 1, 'hello everyone')
    check('global broadcast', toClient[m].target == -1 and toClient[m].args[1].channel == 'all')
    Config.localChat = true
end

do -- colour codes and control characters stripped, length capped
    tick()
    local m = mark()
    fire('fivechat:say', 1, '^1red ^^22green^7\nnext ^*bold')
    check('codes stripped', inbox(2, m)[1].text == 'red green next bold')
    tick()
    fire('fivechat:say', 1, ('x'):rep(400))
    check('length capped', #lastFor(2).text == Config.maxLength)
    tick()
    m = mark()
    fire('fivechat:say', 1, '   ^1^2  ')
    check('empty after cleaning is dropped', #inbox(1, m) == 0)
    check('utf8 cut on a character', Chat.clean(('é'):rep(300)) == ('é'):rep(Config.maxLength))
    addPlayer(9, '^1Red^7Name', 1)
    check('names stripped', Chat.name(9, 'say') == 'RedName')
    players[9] = nil
end

do -- rate limit and repeats
    tick()
    local m = mark()
    for i = 1, 8 do fire('fivechat:say', 2, 'line ' .. i) end
    local got = #inbox(1, m)
    check('rate limited to the burst', got == Config.spam.messages)
    check('told to slow down', lastFor(2).kind == 'system' and lastFor(2).text:find('too fast'))
    tick()
    m = mark()
    for _ = 1, 4 do fire('fivechat:say', 2, 'Same thing') end
    check('repeats limited', #inbox(1, m) == Config.spam.repeats)
    tick(40000)
    m = mark()
    fire('fivechat:say', 2, 'same thing')
    check('repeat allowed again later', #inbox(1, m) == 1)
end

do -- /me and /do: proximity, overhead flag, logged to fivelog
    started.fivelog = 'started'
    tick()
    local m = mark()
    run(1, 'me waves at Al')
    local got = inbox(2, m)[1]
    check('/me nearby', got and got.kind == 'me' and got.text == 'waves at Al' and got.overhead == true)
    check('/me not far away', #inbox(4, m) == 0)
    check('/me logged', fivelogs[#fivelogs].kind == 'chat' and fivelogs[#fivelogs].text == 'Bob /me waves at Al' and fivelogs[#fivelogs].data.channel == 'me')
    run(1, 'do the door is locked')
    check('/do', lastFor(2).kind == 'do' and lastFor(2).text == 'the door is locked')
    check('/do logged', fivelogs[#fivelogs].text == 'Bob /do the door is locked')
    local before = #fivelogs
    run(1, 'me')
    check('empty /me does nothing', #fivelogs == before)
end

do -- ooc and looc
    tick()
    local m = mark()
    run(2, 'ooc brb dinner')
    check('ooc global', toClient[m].target == -1 and toClient[m].args[1].channel == 'ooc')
    check('ooc logged', fivelogs[#fivelogs].text == 'Al /ooc brb dinner')
    m = mark()
    run(2, 'looc lag')
    check('looc local, ooc tab', #inbox(4, m) == 0 and inbox(1, m)[1].kind == 'looc' and inbox(1, m)[1].channel == 'ooc')
end

do -- names from the framework, per kind
    started.qbx_core = 'started'
    players[1].char = { 'Marcus', 'Vale' }
    tick()
    run(1, 'twt new car')
    local m = toClient[#toClient]
    check('tweet uses character name', m.target == -1 and m.args[1].author == 'Marcus Vale' and m.args[1].kind == 'twt')
    check('tweet logged', fivelogs[#fivelogs].text == 'Marcus Vale /twt new car')
    run(1, 'ooc hi')
    check('ooc uses the FiveM name', toClient[#toClient].args[1].author == 'Bob')
    check('chatMessage keeps the FiveM name', (function()
        fire('fivechat:say', 1, 'name check')
        return lastEvent('chatMessage').args[2] == 'Bob'
    end)())
end

do -- adverts, free and paid
    tick()
    run(1, 'ad selling a sultan')
    check('free advert', toClient[#toClient].args[1].kind == 'ad' and #charged == 0)
    check('advert logged', fivelogs[#fivelogs].data.channel == 'ad')
    Config.ads.cost = 500
    tick()
    run(1, 'ad paid one')
    check('charged', charged[1] and charged[1][2] == 'bank' and charged[1][3] == 500 and toClient[#toClient].args[1].text == 'paid one')
    players[1].money = false
    tick()
    local m = mark()
    run(1, 'ad cannot pay')
    check('no money, no advert', #inbox(2, m) == 0 and lastFor(1).kind == 'system' and lastFor(1).text:find('%$500'))
    Config.ads.cost, players[1].money = 0, nil
end

do -- 911 to emergency jobs with a blip
    addPlayer(6, 'Cop', 500, { job = 'police', char = { 'Officer', 'Hale' } })
    addPlayer(7, 'Medic', 900, { job = 'ambulance', char = { 'Nina', 'Park' } })
    addPlayer(8, 'OffDuty', 900, { job = 'police', duty = false, char = { 'Off', 'Duty' } })
    tick()
    local m = mark()
    run(3, '911 shots fired near the bank')
    check('cop gets the call', #inbox(6, m) == 1 and inbox(6, m)[1].kind == 'call' and inbox(6, m)[1].channel == 'call')
    check('medic gets the call', #inbox(7, m) == 1)
    check('off duty does not', #inbox(8, m) == 0)
    check('random player does not', #inbox(2, m) == 0)
    check('caller sees their call', #inbox(3, m) == 1 and inbox(3, m)[1].text == 'shots fired near the bank')
    check('position sent', inbox(6, m)[1].pos.x == 15)
    local blips = 0
    for i = m, #toClient do
        local e = toClient[i]
        if e.name == 'fivechat:call' then
            blips = blips + 1
            check('blip at caller', e.args[1].x == 15 and e.args[1].id == 3)
        end
    end
    check('one blip each', blips == 2)
    check('911 logged', fivelogs[#fivelogs].text == 'Cy /911 shots fired near the bank')

    Config.calls.onDutyOnly = false
    tick()
    m = mark()
    run(3, '911 again')
    check('off duty counts when allowed', #inbox(8, m) == 1)
    Config.calls.onDutyOnly = true

    local saved = { players[6], players[7], players[8] }
    players[6], players[7], players[8] = nil, nil, nil
    tick()
    run(3, '911 anyone?')
    check('told nobody is there', lastFor(3).kind == 'system' and lastFor(3).text:find('Nobody'))
    players[6], players[7], players[8] = saved[1], saved[2], saved[3]
end

do -- mutes
    players[1].aces['fivechat.staff'] = true
    tick()
    local m = mark()
    run(2, 'mute 3 10 spamming')
    check('non staff cannot mute', lastFor(2).text:find('staff only') and not Chat.muted(3))

    run(1, 'mute 3 10 spamming')
    check('muted', Chat.muted(3) ~= nil and Chat.muted(3).reason == 'spamming')
    check('kept in kvp', kvp['mute:license:cy'] ~= nil)
    check('target told', inbox(3, m)[#inbox(3, m)].text:find('muted for 10m more: spamming'))
    check('staff told', lastFor(1).text == 'Muted Cy for 10m.')
    local act = lastEvent('fivepanel:activity')
    check('panel activity', act and act.args[1] == 'Bob (in game)' and act.args[2] == 'muted Cy for 10m: spamming')
    check('no fivecord log without fivecord', #fivecordLogs == 0)

    tick()
    m = mark()
    fire('fivechat:say', 3, 'let me talk')
    run(3, 'me tries')
    run(3, 'ooc hello')
    run(3, 'twt hi')
    check('muted player reaches nobody', #inbox(2, m) == 0)
    check('muted player told why', lastFor(3).text:find('muted'))
    run(3, '911 help')
    check('muted player can still call 911', lastFor(6).kind == 'call')

    run(1, 'mute 3')
    check('usage', lastFor(1).text:find('^Use /mute'))
    run(1, 'mute 99 5')
    check('unknown player', lastFor(1).text:find('^Use /mute'))

    run(1, 'unmute 3')
    check('unmuted', not Chat.muted(3) and kvp['mute:license:cy'] == nil and lastFor(1).text == 'Unmuted Cy.')
    check('unmute activity', lastEvent('fivepanel:activity').args[2] == 'unmuted Cy')
    run(1, 'unmute 3')
    check('not muted', lastFor(1).text == 'Cy is not muted.')

    run(1, 'mute 3 1')
    local realTime = os.time
    os.time = function() return realTime() + 120 end
    check('mute runs out', Chat.muted(3) == nil)
    os.time = realTime

    run(1, 'mute 3 90')
    check('hours', lastFor(1).text == 'Muted Cy for 1h 30m.')
    run(1, 'unmute 3')

    check('export mute', registered.mute(3, 5, 'x') == true and registered.isMuted(3) == true)
    check('export unmute', registered.unmute(3) == true and registered.isMuted(3) == false)
    check('export mute bad args', registered.mute(99, 5) == false and registered.mute(3, 0) == false)
end

do -- mutes survive a restart through kvp
    run(1, 'mute 2 30 cooling off')
    load()
    check('still muted after reload', Chat.muted(2) ~= nil and Chat.muted(2).reason == 'cooling off')
    run(1, 'unmute 2')
end

do -- staff chat without fivecord
    check('owns /sc without fivecord', commands.sc ~= nil)
    tick()
    local m = mark()
    run(1, 'sc anyone free for a report?')
    check('staff gets staff chat', #inbox(1, m) == 1 and inbox(1, m)[1].channel == 'staff')
    check('players do not', #inbox(2, m) == 0)
    run(2, 'sc let me in')
    check('non staff refused', lastFor(2).text:find('staff only') and #inbox(1, m) == 1)
    m = mark()
    fire('fivechat:say', 1, 'from the tab', 'staff')
    check('staff tab sends staff chat', #inbox(1, m) == 1 and inbox(1, m)[1].kind == 'staff' and #inbox(2, m) == 0)
end

do -- with fivecord: its staff, its /sc, its logs
    started.fivecord = 'started'
    load()
    check('leaves /sc to fivecord', commands.sc == nil)
    check('ace ignored when fivecord answers', Chat.isStaff(1) == false)
    players[2].staff = true
    check('fivecord staff', Chat.isStaff(2) == true)
    tick()
    local m = mark()
    fire('fivechat:say', 2, 'from the tab', 'staff')
    check('staff tab ignored, fivecord has it', #inbox(2, m) == 0)

    run(2, 'mute 4 15 language')
    local l = fivecordLogs[#fivecordLogs]
    check('fivecord staff log', l and l.kind == 'staff' and l.desc:find('%*%*Al%*%* muted %*%*Di%*%* for 15m') and l.desc:find('language'))
    run(1, 'mute 4 15')
    check('ace staff not staff with fivecord', lastFor(1).text:find('staff only'))
    run(2, 'unmute 4')
    check('fivecord unmute log', fivecordLogs[#fivecordLogs].title == 'Chat unmute')
    players[2].staff = nil
    started.fivecord = nil
    load()
end

do -- unknown commands
    tick()
    local m = mark()
    source = 1
    handlers['__cfx_internal:commandFallback'][1]('nothere 1 2')
    check('only the player hears about it', #inbox(2, m) == 0 and lastFor(1).text == 'Unknown command /nothere')
    check('chatMessage gets the command', lastEvent('chatMessage').args[3] == '/nothere 1 2')

    AddEventHandler('chatMessage', function(_, _, text) if text == '/legacy' then CancelEvent() end end)
    m = mark()
    fire('__cfx_internal:commandFallback', 1, 'legacy')
    check('handled by an old resource, no notice', #inbox(1, m) == 0)
end

do -- suggestions and state on chat:init
    players[1].char = { 'Marcus', 'Vale' }
    local m = mark()
    fire('chat:init', 1)
    local list, state
    for i = m, #toClient do
        if toClient[i].name == 'chat:addSuggestions' then list = toClient[i].args[1] end
        if toClient[i].name == 'fivechat:state' then state = toClient[i].args[1] end
    end
    local names = {}
    for _, s in ipairs(list) do names[s.name] = s end
    check('own commands with help', names['/me'] and names['/me'].help ~= '' and names['/911'])
    check('other commands listed', names['/car'] and names['/car'].help == '')
    check('staff commands for staff', names['/mute'] and names['/sc'])
    check('state', state.id == 1 and state.staff == true and state.names[1] == 'Bob' and state.names[2] == 'Marcus Vale' and state.ownStaff == true)

    m = mark()
    fire('chat:init', 2)
    for i = m, #toClient do if toClient[i].name == 'chat:addSuggestions' then list = toClient[i].args[1] end end
    names = {}
    for _, s in ipairs(list) do names[s.name] = true end
    check('no staff commands for players', not names['/mute'] and not names['/sc'] and names['/me'])

    m = mark()
    fire('chat:init', 6)
    for i = m, #toClient do if toClient[i].name == 'fivechat:state' then state = toClient[i].args[1] end end
    check('emergency in state', state.emergency == true)
end

do -- state requests are throttled
    tick()
    local m = mark()
    fire('fivechat:state', 2)
    fire('fivechat:state', 2)
    local count = 0
    for i = m, #toClient do if toClient[i].name == 'fivechat:state' then count = count + 1 end end
    check('throttled', count == 1)
end

do -- console
    local m = mark()
    run(0, 'ooc server restart in 5')
    check('console ooc', toClient[m].args[1].author == 'Console' and toClient[m].args[1].id == nil)
    run(0, 'mute 2 5')
    check('console can mute', Chat.muted(2) ~= nil and lastEvent('fivepanel:activity').args[1] == 'Console')
    check('console told by print', printed[#printed] == 'Muted Al for 5m.')
    run(0, 'unmute 2')
end

do -- addMessage export and the old client event
    registered.addMessage(2, { args = { 'Server', 'hi' } })
    check('addMessage export', toClient[#toClient].name == 'chat:addMessage' and toClient[#toClient].target == 2)
    tick()
    local m = mark()
    fire('_chat:messageEntered', 1, 'Bob', { 255, 255, 255 }, 'old client')
    check('old event still says', #inbox(2, m) == 1)
end

print = realPrint
io.write(('%d passed, %d failed\n'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
