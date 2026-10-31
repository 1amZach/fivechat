-- Character names, jobs and money from whichever framework is running.

Framework = {}

local function started(name) return GetResourceState(name) == 'started' end

local qbCore, esx

local function qbPlayer(src)
    if started('qbx_core') then return exports.qbx_core:GetPlayer(src) end
    if started('qb-core') then
        qbCore = qbCore or exports['qb-core']:GetCoreObject()
        return qbCore.Functions.GetPlayer(src)
    end
end

local function esxPlayer(src)
    if not started('es_extended') then return end
    esx = esx or exports.es_extended:getSharedObject()
    return esx.GetPlayerFromId(src)
end

function Framework.name(src)
    local p = qbPlayer(src)
    if p then
        local info = p.PlayerData and p.PlayerData.charinfo
        if info and info.firstname then
            return (('%s %s'):format(info.firstname, info.lastname or ''):gsub('%s+$', ''))
        end
        return
    end
    local x = esxPlayer(src)
    if x then return x.getName() end
end

-- job name, on duty
function Framework.job(src)
    local p = qbPlayer(src)
    if p then
        local job = p.PlayerData and p.PlayerData.job or {}
        return job.name, job.onduty ~= false
    end
    local x = esxPlayer(src)
    if x then
        local job = x.getJob() or {}
        return job.name, job.onDuty ~= false
    end
end

-- true when paid, false when they can't afford it, nil without a framework
function Framework.charge(src, amount, account, reason)
    local p = qbPlayer(src)
    if p then return p.Functions.RemoveMoney(account, amount, reason) == true end
    local x = esxPlayer(src)
    if x then
        if account == 'cash' then account = 'money' end
        local a = x.getAccount(account)
        if not a or a.money < amount then return false end
        x.removeAccountMoney(account, amount, reason)
        return true
    end
end
