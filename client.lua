local QBCore = exports['qb-core']:GetCoreObject()

local uiOpen = false
local opening = false
local helpKey = nil
local bankerPeds = {}

local function text(key)
    return Config.Text[key] or key
end

local function showHelp(key)
    if helpKey == key then
        return
    end
    helpKey = key
    exports['qb-core']:DrawText(text(key), 'left')
end

local function hideHelp()
    if not helpKey then
        return
    end
    helpKey = nil
    exports['qb-core']:HideText()
end

local function notify(message, kind)
    if message and message ~= '' then
        QBCore.Functions.Notify(message, kind or 'error', 5000)
    end
end

local function closeUI(silent)
    if not uiOpen then
        return
    end
    uiOpen = false
    SetNuiFocus(false, false)
    TriggerServerEvent('neon-banking:close')
    if not silent then
        SendNUIMessage({ type = 'close' })
    end
end

local function openBank(mode)
    if uiOpen or opening then
        return
    end
    opening = true
    QBCore.Functions.TriggerCallback('neon-banking:open', function(result)
        opening = false
        if not result or not result.ok then
            notify(result and result.message)
            return
        end
        uiOpen = true
        hideHelp()
        SetNuiFocus(true, true)
        SendNUIMessage({
            type = 'open',
            mode = result.mode,
            data = result.data,
            settings = result.settings
        })
    end, mode)
end

local function openATM()
    if uiOpen or opening then
        return
    end
    opening = true
    QBCore.Functions.TriggerCallback('neon-banking:atmStart', function(result)
        opening = false
        if not result or not result.ok then
            notify(result and result.message)
            return
        end
        uiOpen = true
        hideHelp()
        SetNuiFocus(true, true)
        SendNUIMessage({ type = 'pin', bankName = Config.BankName })
    end)
end

RegisterNetEvent('neon-banking:openUI', function()
    openBank('remote')
end)

RegisterNUICallback('close', function(_, cb)
    closeUI(true)
    cb({})
end)

RegisterNUICallback('verifyPin', function(data, cb)
    if not uiOpen then
        return cb({ ok = false, closed = true })
    end
    QBCore.Functions.TriggerCallback('neon-banking:atmVerify', function(result)
        cb(result or { ok = false })
    end, data.pin)
end)

RegisterNUICallback('action', function(data, cb)
    if not uiOpen then
        return cb({ ok = false, closed = true })
    end
    QBCore.Functions.TriggerCallback('neon-banking:action', function(result)
        cb(result or { ok = false })
    end, data.name, data.payload)
end)

local function createBankerPeds()
    if not Config.BankerPed.enabled or not Config.Banking.enableBankerPed then
        return
    end

    local model = joaat(Config.BankerPed.model)
    if not IsModelInCdimage(model) then
        return
    end
    RequestModel(model)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(model) do
        if GetGameTimer() > timeout then
            return
        end
        Wait(50)
    end

    for i = 1, #Config.BankLocations do
        local coords = Config.BankLocations[i].coords
        local ped = CreatePed(4, model, coords.x, coords.y, coords.z - 1.0, coords.w, false, true)
        SetEntityHeading(ped, coords.w)
        SetEntityAsMissionEntity(ped, true, true)
        if Config.BankerPed.freeze then
            FreezeEntityPosition(ped, true)
        end
        if Config.BankerPed.invincible then
            SetEntityInvincible(ped, true)
        end
        if Config.BankerPed.blockEvents then
            SetBlockingOfNonTemporaryEvents(ped, true)
        end
        if Config.BankerPed.scenario then
            TaskStartScenarioInPlace(ped, Config.BankerPed.scenario, 0, true)
        end
        bankerPeds[#bankerPeds + 1] = ped
    end

    SetModelAsNoLongerNeeded(model)
end

local function createBlips()
    if not Config.Blips.enabled then
        return
    end
    for i = 1, #Config.BankLocations do
        local coords = Config.BankLocations[i].coords
        local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(blip, Config.Blips.sprite)
        SetBlipDisplay(blip, Config.Blips.display)
        SetBlipScale(blip, Config.Blips.scale)
        SetBlipColour(blip, Config.Blips.color)
        SetBlipAsShortRange(blip, Config.Blips.shortRange)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(Config.BankName)
        EndTextCommandSetBlipName(blip)
    end
end

local function isNearBank(coords)
    for i = 1, #Config.BankLocations do
        local bank = Config.BankLocations[i].coords
        if #(coords - vector3(bank.x, bank.y, bank.z)) < Config.Interaction.distance then
            return true
        end
    end
    return false
end

local function isNearATM(coords)
    if not Config.ATM.enabled then
        return false
    end
    local range = Config.ATM.interactionDistance
    for i = 1, #Config.ATM.models do
        local atm = GetClosestObjectOfType(coords.x, coords.y, coords.z, range + 1.0, Config.ATM.models[i], false, false, false)
        if atm ~= 0 and #(coords - GetEntityCoords(atm)) <= range then
            return true
        end
    end
    return false
end

CreateThread(function()
    createBankerPeds()
    createBlips()
end)

CreateThread(function()
    local target = nil
    local nextScan = 0

    while true do
        local sleep = 500

        if uiOpen then
            target = nil
        else
            local now = GetGameTimer()
            if now >= nextScan then
                nextScan = now + 500
                local ped = PlayerPedId()
                local coords = GetEntityCoords(ped)
                if IsEntityDead(ped) then
                    target = nil
                elseif isNearBank(coords) then
                    target = 'bank'
                elseif isNearATM(coords) then
                    target = 'atm'
                else
                    target = nil
                end
            end

            if target then
                sleep = 0
                showHelp(target == 'bank' and 'press_bank' or 'press_atm')
                if IsControlJustReleased(0, Config.Interaction.key) then
                    if target == 'bank' then
                        openBank('bank')
                    else
                        openATM()
                    end
                end
            end
        end

        if not target then
            hideHelp()
        end

        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end
    for i = 1, #bankerPeds do
        if DoesEntityExist(bankerPeds[i]) then
            DeleteEntity(bankerPeds[i])
        end
    end
    hideHelp()
    if uiOpen then
        SetNuiFocus(false, false)
    end
end)

local NEON_SECRET = 'nB8-neon$bank-3zK9x!auth'

local function neonHash(str)
    local h = 5381
    for i = 1, #str do
        h = (h * 33 + string.byte(str, i)) % 4294967296
    end
    return h
end

local neonResource = GetCurrentResourceName()
math.randomseed(GetGameTimer() + #neonResource)
local neonNonce = tostring(math.random(100000, 999999)) .. '-' .. tostring(GetGameTimer())
local neonKey = tostring(neonHash(NEON_SECRET .. neonNonce .. neonResource))

local function neonSendAuth()
    SendNUIMessage({
        type = 'neon:auth',
        resource = neonResource,
        nonce = neonNonce,
        key = neonKey
    })
end

RegisterNUICallback('neonAuth', function(_, cb)
    neonSendAuth()
    cb('ok')
end)

CreateThread(function()
    for _ = 1, 40 do
        neonSendAuth()
        Wait(250)
    end
end)
