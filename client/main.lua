local open, loaded = false, false
local queue = {}
local state = {}

local function nui(action, data)
    data = data or {}
    data.action = action
    if loaded then SendNUIMessage(data) else queue[#queue + 1] = data end
end

local function push(m) nui('message', { message = m }) end

-- --------------------------------------------------------------- open, send

local function close()
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    nui('close')
end

RegisterCommand('fivechat', function()
    if open or not loaded or IsPauseMenuActive() then return end
    open = true
    SetNuiFocus(true, true)
    nui('open')
    TriggerServerEvent('fivechat:state')
end, false)
RegisterKeyMapping('fivechat', 'Open chat', 'keyboard', Config.key)

RegisterNUICallback('send', function(data, cb)
    close()
    cb('ok')
    local text = type(data.text) == 'string' and data.text:gsub('^%s+', '') or ''
    if text == '' then return end
    if text:sub(1, 1) == '/' then
        ExecuteCommand(text:sub(2))
    elseif data.mode == 'staff' and not state.ownStaff then
        ExecuteCommand(('%s %s'):format(Config.commands.staff, text))
    else
        TriggerServerEvent('fivechat:say', text, data.mode)
    end
end)

RegisterNUICallback('close', function(_, cb)
    close()
    cb('ok')
end)

RegisterNUICallback('loaded', function(_, cb)
    cb('ok')
    if loaded then return end
    loaded = true
    SendNUIMessage({
        action = 'config',
        fadeAfter = Config.fadeAfter * 1000,
        maxLength = Config.maxLength,
        showIds = Config.showIds,
        localChat = Config.localChat,
    })
    for _, m in ipairs(queue) do SendNUIMessage(m) end
    queue = {}
    TriggerServerEvent('chat:init')
end)

if Config.commands.clear then
    RegisterCommand(Config.commands.clear, function() nui('clear') end, false)
end

-- ------------------------------------------------------- default chat events

RegisterNetEvent('chat:addMessage', function(m)
    if type(m) ~= 'table' then m = { args = { tostring(m) } } end
    push(m)
end)

RegisterNetEvent('chatMessage', function(author, color, text)
    local args = { text }
    if author and author ~= '' then args = { author, text } end
    push({ args = args, color = color, multiline = true })
end)

RegisterNetEvent('chat:addSuggestion', function(name, help, params)
    nui('suggestion', { suggestion = { name = name, help = help, params = params } })
end)

RegisterNetEvent('chat:addSuggestions', function(list)
    nui('suggestions', { list = list })
end)

RegisterNetEvent('chat:removeSuggestion', function(name)
    nui('removeSuggestion', { name = name })
end)

RegisterNetEvent('chat:addTemplate', function(id, html)
    nui('template', { id = id, html = html })
end)

RegisterNetEvent('chat:clear', function() nui('clear') end)

RegisterNetEvent('__cfx_internal:serverPrint', function(text)
    if type(text) == 'string' and text ~= '' then push({ templateId = 'print', multiline = true, args = { text } }) end
end)

-- commands registered on this side, the server sends its own
local function refreshCommands()
    local list = {}
    for _, c in ipairs(GetRegisteredCommands()) do
        if c.name ~= 'fivechat' and not c.name:find('^[+-]') and IsAceAllowed(('command.%s'):format(c.name)) then
            list[#list + 1] = { name = '/' .. c.name, help = '' }
        end
    end
    if Config.commands.clear then list[#list + 1] = { name = '/' .. Config.commands.clear, help = 'Clear your chat' } end
    nui('suggestions', { list = list })
end

AddEventHandler('onClientResourceStart', function() SetTimeout(500, refreshCommands) end)

-- ------------------------------------------------------------- own messages

local overhead = {}

local function draw3d(pos, text, r, g, b)
    SetDrawOrigin(pos.x, pos.y, pos.z, 0)
    SetTextScale(0.0, 0.34)
    SetTextFont(4)
    SetTextCentre(true)
    SetTextOutline()
    SetTextColour(r, g, b, 235)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function showOverhead(m)
    local text = m.text:gsub('~', '')
    if #text > 90 then text = text:sub(1, 87) .. '...' end
    overhead[#overhead + 1] = { id = m.id, text = '* ' .. text, kind = m.kind, untilAt = GetGameTimer() + Config.overhead.seconds * 1000 }
    if #overhead > 1 then return end

    CreateThread(function()
        while #overhead > 0 do
            local now, here = GetGameTimer(), GetEntityCoords(PlayerPedId())
            local stacked = {}
            for i = #overhead, 1, -1 do
                local o = overhead[i]
                if now > o.untilAt then
                    table.remove(overhead, i)
                else
                    local player = GetPlayerFromServerId(o.id)
                    local ped = player ~= -1 and GetPlayerPed(player) or 0
                    if ped ~= 0 then
                        local pos = GetEntityCoords(ped)
                        if #(pos - here) < Config.overhead.range then
                            local n = stacked[o.id] or 0
                            stacked[o.id] = n + 1
                            if o.kind == 'me' then
                                draw3d(pos + vec3(0.0, 0.0, 1.05 + n * 0.14), o.text, 214, 168, 255)
                            else
                                draw3d(pos + vec3(0.0, 0.0, 1.05 + n * 0.14), o.text, 120, 230, 170)
                            end
                        end
                    end
                end
            end
            Wait(0)
        end
    end)
end

RegisterNetEvent('fivechat:message', function(m)
    if m.pos then
        local a, b = GetStreetNameAtCoord(m.pos.x, m.pos.y, m.pos.z)
        local street = GetStreetNameFromHashKey(a)
        if b ~= 0 then street = ('%s / %s'):format(street, GetStreetNameFromHashKey(b)) end
        m.where, m.pos = street, nil
    end
    if m.overhead and m.id then showOverhead(m) end
    push(m)
end)

RegisterNetEvent('fivechat:state', function(s)
    state = s
    nui('state', { state = s })
end)

RegisterNetEvent('fivechat:call', function(c)
    local b = Config.calls.blip
    local blip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(blip, b.sprite)
    SetBlipColour(blip, b.color)
    SetBlipScale(blip, b.scale)
    SetBlipFlashes(blip, true)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(('911: %s'):format(c.from))
    EndTextCommandSetBlipName(blip)
    PlaySoundFrontend(-1, 'Event_Start_Text', 'GTAO_FM_Events_Soundset', false)
    SetTimeout(5000, function() SetBlipFlashes(blip, false) end)
    SetTimeout(Config.calls.blipSeconds * 1000, function() RemoveBlip(blip) end)
end)

-- ------------------------------------------------------------------ hiding

CreateThread(function()
    SetTextChatEnabled(false)
    local hidden = false
    while true do
        local hide = IsPauseMenuActive() or IsScreenFadedOut()
        if hide ~= hidden then
            hidden = hide
            nui('hidden', { value = hide })
            if hide then close() end
        end
        Wait(250)
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() and open then SetNuiFocus(false, false) end
end)
