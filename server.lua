local QBCore = exports['qb-core']:GetCoreObject()

local sessions = {}
local busy = {}
local lastAction = {}
local pinAttempts = {}

local MAX_SAVINGS = 2000000000
local ACTION_INTERVAL = 300

local INCOMING = {
    deposit = true,
    transfer_in = true,
    savings_withdrawal = true,
    admin_deposit = true,
    admin_transfer_in = true
}

local OUTGOING = {
    withdrawal = true,
    transfer_out = true,
    fee = true,
    savings_deposit = true,
    admin_withdrawal = true,
    admin_transfer_out = true
}

local ATM_ACTIONS = {
    refresh = true,
    deposit = true,
    withdraw = true,
    transfer = true
}

local function text(key, ...)
    local value = Config.Text[key] or key
    if select('#', ...) > 0 then
        return value:format(...)
    end
    return value
end

local function formatMoney(amount)
    local formatted = tostring(math.floor(tonumber(amount) or 0))
    local count
    repeat
        formatted, count = formatted:gsub('^(-?%d+)(%d%d%d)', '%1.%2')
    until count == 0
    return (Config.Currency or '$') .. formatted
end

local function sanitizeAmount(value)
    local amount = tonumber(value)
    if not amount or amount ~= amount or amount == math.huge or amount == -math.huge then
        return nil
    end
    amount = math.floor(amount)
    if amount < 1 then
        return nil
    end
    return amount
end

local function sanitizeText(value, maxLength)
    if type(value) ~= 'string' then
        return ''
    end
    if not utf8.len(value) then
        return ''
    end
    value = value:gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    local length = utf8.len(value)
    if length and length > maxLength then
        value = value:sub(1, utf8.offset(value, maxLength + 1) - 1)
    end
    return value
end

local function sanitizePin(value)
    if type(value) == 'number' then
        value = tostring(math.floor(value))
    end
    if type(value) ~= 'string' or not value:match('^%d%d%d%d$') then
        return nil
    end
    return value
end

local function getName(player)
    local info = player.PlayerData.charinfo or {}
    local name = ((info.firstname or '') .. ' ' .. (info.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    return name
end

local function cardDigits(identifier)
    local hash = 7
    for i = 1, #identifier do
        hash = (hash * 31 + identifier:byte(i)) % 10000
    end
    return ('%04d'):format(hash)
end

local function getCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then
        return nil
    end
    return GetEntityCoords(ped)
end

local function findBank(coords)
    local range = (Config.Interaction.distance or 3.0) + 4.0
    for i = 1, #Config.BankLocations do
        local bank = Config.BankLocations[i].coords
        local bankCoords = vector3(bank.x, bank.y, bank.z)
        if #(coords - bankCoords) <= range then
            return bankCoords
        end
    end
    return nil
end

local function sessionValid(src)
    local session = sessions[src]
    if not session then
        return false
    end
    if session.mode == 'remote' then
        return true
    end
    local coords = getCoords(src)
    if not coords or #(coords - session.coords) > session.range then
        sessions[src] = nil
        return false
    end
    return true
end

local function logTransaction(identifier, kind, amount, description)
    if not Config.Banking.enableTransactionHistory then
        return
    end
    MySQL.insert('INSERT INTO banking_transactions (identifier, type, amount, description, date) VALUES (?, ?, ?, ?, NOW())', {
        identifier, kind, amount, description or ''
    })
end

local function sendDiscordLog(kind, title, colorKey, fields)
    local settings = Config.DiscordLogging
    if not settings or not settings.enabled or not settings.webhook or settings.webhook == '' then
        return
    end
    if not settings.logEvents[kind] then
        return
    end

    local embedFields = {}
    for i = 1, #fields do
        embedFields[i] = {
            name = fields[i][1],
            value = tostring(fields[i][2]):gsub('[@`]', ''),
            inline = true
        }
    end

    local payload = {
        username = settings.botName,
        embeds = {
            {
                title = title,
                type = 'rich',
                color = settings.color[colorKey] or settings.color.admin,
                fields = embedFields,
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
            }
        }
    }
    if settings.botAvatar and settings.botAvatar ~= '' then
        payload.avatar_url = settings.botAvatar
    end

    PerformHttpRequest(settings.webhook, function() end, 'POST', json.encode(payload), {
        ['Content-Type'] = 'application/json'
    })
end

local function playerField(player, src)
    return { 'Oyuncu', ('%s (%s) [%s]'):format(getName(player), src, player.PlayerData.citizenid) }
end

local function loadTransactions(identifier)
    if not Config.Banking.enableTransactionHistory then
        return {}
    end
    local limit = math.floor(tonumber(Config.Banking.maxHistoryEntries) or 50)
    limit = math.max(1, math.min(limit, 200))
    local rows = MySQL.query.await('SELECT id, type, amount, description, UNIX_TIMESTAMP(date) AS ts FROM banking_transactions WHERE identifier = ? ORDER BY date DESC, id DESC LIMIT ' .. limit, {
        identifier
    })
    return rows or {}
end

local function loadBalanceHistory(identifier, currentBalance)
    local rows = MySQL.query.await("SELECT type, amount, DATE_FORMAT(date, '%Y-%m-%d') AS day FROM banking_transactions WHERE identifier = ? AND date >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)", {
        identifier
    }) or {}

    local changeByDay = {}
    local income, expense = 0, 0
    for i = 1, #rows do
        local row = rows[i]
        local amount = tonumber(row.amount) or 0
        if INCOMING[row.type] then
            changeByDay[row.day] = (changeByDay[row.day] or 0) + amount
            income = income + amount
        elseif OUTGOING[row.type] then
            changeByDay[row.day] = (changeByDay[row.day] or 0) - amount
            expense = expense + amount
        end
    end

    local history = {}
    local balance = currentBalance
    local now = os.time()
    for offset = 0, 6 do
        local day = os.date('%Y-%m-%d', now - offset * 86400)
        table.insert(history, 1, { day = day, balance = balance })
        balance = balance - (changeByDay[day] or 0)
    end

    return history, { income = income, expense = expense }
end

local function buildSnapshot(player)
    local data = player.PlayerData
    local identifier = data.citizenid

    local savings = {
        enabled = Config.Banking.allowSavingsAccounts == true,
        active = false,
        balance = 0
    }
    if savings.enabled then
        local row = MySQL.single.await('SELECT balance, status FROM banking_savings WHERE identifier = ?', { identifier })
        if row and row.status == 'active' then
            savings.active = true
            savings.balance = tonumber(row.balance) or 0
        end
    end

    local hasPin = MySQL.scalar.await('SELECT 1 FROM banking_pins WHERE identifier = ?', { identifier }) ~= nil
    local bank = math.floor(tonumber(data.money.bank) or 0)
    local history, week = loadBalanceHistory(identifier, bank)

    return {
        name = getName(player),
        bank = bank,
        cash = math.floor(tonumber(data.money.cash) or 0),
        card = cardDigits(identifier),
        hasPin = hasPin,
        savings = savings,
        transactions = loadTransactions(identifier),
        history = history,
        week = week
    }
end

local function buildSettings()
    return {
        bankName = Config.BankName,
        currency = Config.Currency or '$',
        fee = tonumber(Config.Banking.transferFee) or 0,
        minTransfer = Config.Banking.minTransferAmount,
        maxAmount = Config.Banking.maxTransferAmount,
        quickAmounts = Config.Banking.quickAmounts or {},
        historyEnabled = Config.Banking.enableTransactionHistory == true
    }
end

local function getPinState(identifier)
    local state = pinAttempts[identifier]
    if not state then
        return 0, 0
    end
    local now = os.time()
    if state.lockedUntil and state.lockedUntil > now then
        return state.count, state.lockedUntil - now
    end
    if state.lockedUntil then
        pinAttempts[identifier] = nil
        return 0, 0
    end
    return state.count, 0
end

local handlers = {}

function handlers.refresh()
    return true
end

function handlers.deposit(src, player, payload)
    local amount = sanitizeAmount(payload.amount)
    if not amount then
        return false, text('invalid_amount')
    end
    if amount > Config.Banking.maxTransferAmount then
        return false, text('max_amount', formatMoney(Config.Banking.maxTransferAmount))
    end
    if (player.PlayerData.money.cash or 0) < amount then
        return false, text('no_cash')
    end
    if not player.Functions.RemoveMoney('cash', amount, 'bank-deposit') then
        return false, text('failed')
    end
    player.Functions.AddMoney('bank', amount, 'bank-deposit')

    logTransaction(player.PlayerData.citizenid, 'deposit', amount, '')
    sendDiscordLog('deposits', 'Para yatırma', 'deposit', {
        playerField(player, src),
        { 'Tutar', formatMoney(amount) },
        { 'Yeni bakiye', formatMoney(player.PlayerData.money.bank) }
    })
    return true, text('deposited', formatMoney(amount))
end

function handlers.withdraw(src, player, payload)
    local amount = sanitizeAmount(payload.amount)
    if not amount then
        return false, text('invalid_amount')
    end
    if amount > Config.Banking.maxTransferAmount then
        return false, text('max_amount', formatMoney(Config.Banking.maxTransferAmount))
    end
    if (player.PlayerData.money.bank or 0) < amount then
        return false, text('no_bank')
    end
    if not player.Functions.RemoveMoney('bank', amount, 'bank-withdraw') then
        return false, text('failed')
    end
    player.Functions.AddMoney('cash', amount, 'bank-withdraw')

    logTransaction(player.PlayerData.citizenid, 'withdrawal', amount, '')
    sendDiscordLog('withdrawals', 'Para çekme', 'withdrawal', {
        playerField(player, src),
        { 'Tutar', formatMoney(amount) },
        { 'Kalan bakiye', formatMoney(player.PlayerData.money.bank) }
    })
    return true, text('withdrawn', formatMoney(amount))
end

function handlers.transfer(src, player, payload)
    local targetNumber = tonumber(payload.target)
    local targetId = targetNumber and math.tointeger(targetNumber)
    if not targetId or targetId < 1 then
        return false, text('invalid_target')
    end
    if targetId == src then
        return false, text('self_transfer')
    end

    local amount = sanitizeAmount(payload.amount)
    if not amount then
        return false, text('invalid_amount')
    end
    if amount < Config.Banking.minTransferAmount then
        return false, text('min_amount', formatMoney(Config.Banking.minTransferAmount))
    end
    if amount > Config.Banking.maxTransferAmount then
        return false, text('max_amount', formatMoney(Config.Banking.maxTransferAmount))
    end

    local target = QBCore.Functions.GetPlayer(targetId)
    if not target then
        return false, text('player_not_found')
    end
    if target.PlayerData.citizenid == player.PlayerData.citizenid then
        return false, text('self_transfer')
    end

    local feeRate = math.max(0, tonumber(Config.Banking.transferFee) or 0)
    local fee = math.floor(amount * feeRate / 100)
    local total = amount + fee
    if (player.PlayerData.money.bank or 0) < total then
        return false, text(fee > 0 and 'no_bank_fee' or 'no_bank')
    end
    if not player.Functions.RemoveMoney('bank', total, 'bank-transfer') then
        return false, text('failed')
    end
    target.Functions.AddMoney('bank', amount, 'bank-transfer')

    local note = sanitizeText(payload.description, 60)
    local senderName = getName(player)
    local targetName = getName(target)
    local suffix = note ~= '' and (' · ' .. note) or ''

    logTransaction(player.PlayerData.citizenid, 'transfer_out', amount, targetName .. suffix)
    logTransaction(target.PlayerData.citizenid, 'transfer_in', amount, senderName .. suffix)
    if fee > 0 then
        logTransaction(player.PlayerData.citizenid, 'fee', fee, targetName)
    end

    TriggerClientEvent('QBCore:Notify', targetId, text('transfer_received', senderName, formatMoney(amount)), 'success', 5000)

    sendDiscordLog('transfers', 'Transfer', 'transfer', {
        { 'Gönderen', ('%s (%s) [%s]'):format(senderName, src, player.PlayerData.citizenid) },
        { 'Alan', ('%s (%s) [%s]'):format(targetName, targetId, target.PlayerData.citizenid) },
        { 'Tutar', formatMoney(amount) },
        { 'Komisyon', formatMoney(fee) },
        { 'Açıklama', note ~= '' and note or '-' }
    })
    return true, text('transfer_sent', targetName, formatMoney(amount))
end

function handlers.savingsOpen(src, player)
    if not Config.Banking.allowSavingsAccounts then
        return false, text('savings_disabled')
    end
    local identifier = player.PlayerData.citizenid
    local status = MySQL.scalar.await('SELECT status FROM banking_savings WHERE identifier = ?', { identifier })
    if status == 'active' then
        return false, text('savings_exists')
    end
    MySQL.update.await("INSERT INTO banking_savings (identifier, balance, status) VALUES (?, 0, 'active') ON DUPLICATE KEY UPDATE status = 'active'", { identifier })

    logTransaction(identifier, 'savings_opened', 0, '')
    sendDiscordLog('accountOperations', 'Birikim hesabı açıldı', 'savings', { playerField(player, src) })
    return true, text('savings_opened')
end

function handlers.savingsDeposit(src, player, payload)
    if not Config.Banking.allowSavingsAccounts then
        return false, text('savings_disabled')
    end
    local amount = sanitizeAmount(payload.amount)
    if not amount then
        return false, text('invalid_amount')
    end
    if amount > Config.Banking.maxTransferAmount then
        return false, text('max_amount', formatMoney(Config.Banking.maxTransferAmount))
    end
    if (player.PlayerData.money.bank or 0) < amount then
        return false, text('no_bank')
    end

    local identifier = player.PlayerData.citizenid
    local status = MySQL.scalar.await('SELECT status FROM banking_savings WHERE identifier = ?', { identifier })
    if status ~= 'active' then
        return false, text('savings_missing')
    end

    local changed = MySQL.update.await("UPDATE banking_savings SET balance = balance + ? WHERE identifier = ? AND status = 'active' AND balance + ? <= ?", {
        amount, identifier, amount, MAX_SAVINGS
    })
    if changed ~= 1 then
        return false, text('savings_limit')
    end

    local current = QBCore.Functions.GetPlayer(src)
    if not current or current.PlayerData.citizenid ~= identifier or not current.Functions.RemoveMoney('bank', amount, 'bank-savings') then
        MySQL.update.await('UPDATE banking_savings SET balance = balance - ? WHERE identifier = ? AND balance >= ?', { amount, identifier, amount })
        return false, text('failed')
    end

    logTransaction(identifier, 'savings_deposit', amount, '')
    sendDiscordLog('savingsOperations', 'Birikime aktarım', 'savings', {
        playerField(player, src),
        { 'Tutar', formatMoney(amount) }
    })
    return true, text('savings_in', formatMoney(amount))
end

function handlers.savingsWithdraw(src, player, payload)
    if not Config.Banking.allowSavingsAccounts then
        return false, text('savings_disabled')
    end
    local amount = sanitizeAmount(payload.amount)
    if not amount then
        return false, text('invalid_amount')
    end
    if amount > Config.Banking.maxTransferAmount then
        return false, text('max_amount', formatMoney(Config.Banking.maxTransferAmount))
    end

    local identifier = player.PlayerData.citizenid
    local changed = MySQL.update.await("UPDATE banking_savings SET balance = balance - ? WHERE identifier = ? AND status = 'active' AND balance >= ?", {
        amount, identifier, amount
    })
    if changed ~= 1 then
        local status = MySQL.scalar.await('SELECT status FROM banking_savings WHERE identifier = ?', { identifier })
        return false, text(status == 'active' and 'savings_low' or 'savings_missing')
    end

    local current = QBCore.Functions.GetPlayer(src)
    if not current or current.PlayerData.citizenid ~= identifier then
        MySQL.update.await('UPDATE banking_savings SET balance = balance + ? WHERE identifier = ?', { amount, identifier })
        return false, text('failed')
    end
    current.Functions.AddMoney('bank', amount, 'bank-savings')

    logTransaction(identifier, 'savings_withdrawal', amount, '')
    sendDiscordLog('savingsOperations', 'Birikimden aktarım', 'savings', {
        playerField(player, src),
        { 'Tutar', formatMoney(amount) }
    })
    return true, text('savings_out', formatMoney(amount))
end

function handlers.savingsClose(src, player)
    if not Config.Banking.allowSavingsAccounts then
        return false, text('savings_disabled')
    end
    local identifier = player.PlayerData.citizenid
    local row = MySQL.single.await('SELECT balance, status FROM banking_savings WHERE identifier = ?', { identifier })
    if not row or row.status ~= 'active' then
        return false, text('savings_missing')
    end

    local balance = math.floor(tonumber(row.balance) or 0)
    local changed = MySQL.update.await("UPDATE banking_savings SET status = 'inactive', balance = 0 WHERE identifier = ? AND status = 'active' AND balance = ?", {
        identifier, balance
    })
    if changed ~= 1 then
        return false, text('failed')
    end

    if balance > 0 then
        local current = QBCore.Functions.GetPlayer(src)
        if not current or current.PlayerData.citizenid ~= identifier then
            MySQL.update.await("UPDATE banking_savings SET status = 'active', balance = ? WHERE identifier = ?", { balance, identifier })
            return false, text('failed')
        end
        current.Functions.AddMoney('bank', balance, 'bank-savings')
        logTransaction(identifier, 'savings_withdrawal', balance, '')
    end

    logTransaction(identifier, 'savings_closed', 0, '')
    sendDiscordLog('accountOperations', 'Birikim hesabı kapatıldı', 'savings', {
        playerField(player, src),
        { 'Aktarılan', formatMoney(balance) }
    })
    return true, text('savings_closed')
end

function handlers.setPin(src, player, payload)
    local pin = sanitizePin(payload.pin)
    if not pin then
        return false, text('pin_invalid')
    end
    local identifier = player.PlayerData.citizenid
    MySQL.update.await('INSERT INTO banking_pins (identifier, pin) VALUES (?, ?) ON DUPLICATE KEY UPDATE pin = VALUES(pin)', { identifier, pin })
    pinAttempts[identifier] = nil

    sendDiscordLog('pinOperations', 'PIN değiştirildi', 'admin', { playerField(player, src) })
    return true, text('pin_saved')
end

function handlers.clearHistory(src, player)
    local identifier = player.PlayerData.citizenid
    local removed = MySQL.update.await('DELETE FROM banking_transactions WHERE identifier = ?', { identifier })
    if not removed or removed < 1 then
        return false, text('history_empty')
    end
    sendDiscordLog('historyClearing', 'İşlem geçmişi temizlendi', 'admin', {
        playerField(player, src),
        { 'Silinen kayıt', removed }
    })
    return true, text('history_cleared')
end

QBCore.Functions.CreateCallback('neon-banking:open', function(source, cb, mode)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    if not player then
        return cb({ ok = false })
    end

    if mode == 'remote' then
        local session = sessions[src]
        if not session or session.mode ~= 'remote' then
            return cb({ ok = false, message = text('not_allowed') })
        end
    else
        local coords = getCoords(src)
        local bankCoords = coords and findBank(coords)
        if not bankCoords then
            return cb({ ok = false, message = text('not_near_bank') })
        end
        sessions[src] = {
            mode = 'bank',
            coords = bankCoords,
            range = (Config.Interaction.distance or 3.0) + 10.0
        }
    end

    cb({ ok = true, mode = 'bank', data = buildSnapshot(player), settings = buildSettings() })
end)

QBCore.Functions.CreateCallback('neon-banking:atmStart', function(source, cb)
    local player = QBCore.Functions.GetPlayer(source)
    if not player then
        return cb({ ok = false })
    end
    if not Config.ATM.enabled then
        return cb({ ok = false, message = text('atm_disabled') })
    end

    local identifier = player.PlayerData.citizenid
    local hasPin = MySQL.scalar.await('SELECT 1 FROM banking_pins WHERE identifier = ?', { identifier }) ~= nil
    if not hasPin then
        return cb({ ok = false, message = text('pin_missing') })
    end

    local _, locked = getPinState(identifier)
    if locked > 0 then
        return cb({ ok = false, message = text('pin_locked', locked) })
    end
    cb({ ok = true })
end)

QBCore.Functions.CreateCallback('neon-banking:atmVerify', function(source, cb, enteredPin)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    if not player then
        return cb({ ok = false })
    end
    if not Config.ATM.enabled then
        return cb({ ok = false, message = text('atm_disabled'), closed = true })
    end
    if busy[src] then
        return cb({ ok = false, message = text('too_fast') })
    end

    local identifier = player.PlayerData.citizenid
    local count, locked = getPinState(identifier)
    if locked > 0 then
        return cb({ ok = false, message = text('pin_locked', locked), closed = true })
    end

    local pin = sanitizePin(enteredPin)
    if not pin then
        return cb({ ok = false, message = text('pin_invalid') })
    end

    busy[src] = true
    local success, result = pcall(function()
        local stored = MySQL.scalar.await('SELECT pin FROM banking_pins WHERE identifier = ?', { identifier })
        if not stored then
            return { ok = false, message = text('pin_missing'), closed = true }
        end

        if tostring(stored) ~= pin then
            local maxAttempts = math.max(1, math.floor(tonumber(Config.Pin.maxAttempts) or 5))
            count = count + 1
            if count >= maxAttempts then
                local lockSeconds = math.max(10, math.floor(tonumber(Config.Pin.lockSeconds) or 300))
                pinAttempts[identifier] = { count = count, lockedUntil = os.time() + lockSeconds }
                return { ok = false, message = text('pin_locked', lockSeconds), closed = true }
            end
            pinAttempts[identifier] = { count = count }
            return { ok = false, message = text('pin_wrong', maxAttempts - count) }
        end

        local coords = getCoords(src)
        if not coords then
            return { ok = false, message = text('failed'), closed = true }
        end

        pinAttempts[identifier] = nil
        sessions[src] = { mode = 'atm', coords = coords, range = 8.0 }
        return { ok = true, mode = 'atm', data = buildSnapshot(player), settings = buildSettings() }
    end)
    busy[src] = nil

    if not success then
        print(('[neon-banking] atmVerify: %s'):format(result))
        return cb({ ok = false, message = text('failed') })
    end
    cb(result)
end)

QBCore.Functions.CreateCallback('neon-banking:action', function(source, cb, name, payload)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    if not player then
        return cb({ ok = false })
    end

    if not sessionValid(src) then
        return cb({ ok = false, message = text('session_expired'), closed = true })
    end

    local handler = type(name) == 'string' and handlers[name]
    if not handler then
        return cb({ ok = false, message = text('not_allowed') })
    end
    if sessions[src].mode == 'atm' and not ATM_ACTIONS[name] then
        return cb({ ok = false, message = text('not_allowed') })
    end

    local now = GetGameTimer()
    if busy[src] or (lastAction[src] and now - lastAction[src] < ACTION_INTERVAL) then
        return cb({ ok = false, message = text('too_fast') })
    end

    busy[src] = true
    lastAction[src] = now
    if type(payload) ~= 'table' then
        payload = {}
    end

    local success, ok, message = pcall(handler, src, player, payload)
    busy[src] = nil

    if not success then
        print(('[neon-banking] %s: %s'):format(name, ok))
        return cb({ ok = false, message = text('failed') })
    end

    local current = QBCore.Functions.GetPlayer(src)
    if not current then
        return cb({ ok = false })
    end
    cb({ ok = ok == true, message = message, data = buildSnapshot(current) })
end)

RegisterNetEvent('neon-banking:close', function()
    sessions[source] = nil
end)

AddEventHandler('playerDropped', function()
    local src = source
    sessions[src] = nil
    busy[src] = nil
    lastAction[src] = nil
end)

local function openRemote(src)
    src = tonumber(src)
    if not src or src < 1 or not QBCore.Functions.GetPlayer(src) then
        return false
    end
    sessions[src] = { mode = 'remote' }
    TriggerClientEvent('neon-banking:openUI', src)
    return true
end

if Config.Command and Config.Command.enabled then
    QBCore.Commands.Add(Config.Command.name or 'bank', text('command_help'), {}, false, function(source)
        openRemote(source)
    end, Config.Command.permission or 'admin')
end

MySQL.ready(function()
    MySQL.query([[CREATE TABLE IF NOT EXISTS `banking_transactions` (
        `id` int(11) NOT NULL AUTO_INCREMENT,
        `identifier` varchar(50) NOT NULL,
        `type` varchar(50) NOT NULL,
        `amount` int(11) NOT NULL,
        `description` text,
        `date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `identifier` (`identifier`),
        KEY `type` (`type`),
        KEY `date` (`date`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

    MySQL.query([[CREATE TABLE IF NOT EXISTS `banking_savings` (
        `id` int(11) NOT NULL AUTO_INCREMENT,
        `identifier` varchar(50) NOT NULL,
        `balance` int(11) NOT NULL DEFAULT 0,
        `status` varchar(20) NOT NULL DEFAULT 'active',
        `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        UNIQUE KEY `identifier` (`identifier`),
        KEY `status` (`status`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

    MySQL.query([[CREATE TABLE IF NOT EXISTS `banking_pins` (
        `id` int(11) NOT NULL AUTO_INCREMENT,
        `identifier` varchar(50) NOT NULL,
        `pin` varchar(4) NOT NULL,
        `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        UNIQUE KEY `identifier` (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
end)

local function exportPlayer(name, src)
    local player = src and QBCore.Functions.GetPlayer(tonumber(src))
    if not player then
        print(('[neon-banking] %s: oyuncu bulunamadı'):format(name))
        return nil
    end
    return player
end

local function exportAmount(name, value)
    local amount = sanitizeAmount(value)
    if not amount then
        print(('[neon-banking] %s: geçersiz tutar'):format(name))
        return nil
    end
    return amount
end

local function adminLog(title, player, src, amount, description)
    sendDiscordLog('adminActions', title, 'admin', {
        playerField(player, src),
        { 'Tutar', formatMoney(amount) },
        { 'Açıklama', description ~= '' and description or '-' }
    })
end

exports('AddBankMoney', function(src, value, description)
    local player = exportPlayer('AddBankMoney', src)
    local amount = player and exportAmount('AddBankMoney', value)
    if not amount then
        return false
    end
    description = sanitizeText(description, 120)
    player.Functions.AddMoney('bank', amount, 'bank-export')
    logTransaction(player.PlayerData.citizenid, 'admin_deposit', amount, description)
    adminLog('Banka hesabına para eklendi', player, src, amount, description)
    return true
end)

exports('RemoveBankMoney', function(src, value, description)
    local player = exportPlayer('RemoveBankMoney', src)
    local amount = player and exportAmount('RemoveBankMoney', value)
    if not amount then
        return false
    end
    if (player.PlayerData.money.bank or 0) < amount then
        return false
    end
    if not player.Functions.RemoveMoney('bank', amount, 'bank-export') then
        return false
    end
    description = sanitizeText(description, 120)
    logTransaction(player.PlayerData.citizenid, 'admin_withdrawal', amount, description)
    adminLog('Banka hesabından para alındı', player, src, amount, description)
    return true
end)

exports('AddCashMoney', function(src, value, description)
    local player = exportPlayer('AddCashMoney', src)
    local amount = player and exportAmount('AddCashMoney', value)
    if not amount then
        return false
    end
    description = sanitizeText(description, 120)
    player.Functions.AddMoney('cash', amount, 'bank-export')
    logTransaction(player.PlayerData.citizenid, 'admin_cash_grant', amount, description)
    adminLog('Nakit eklendi', player, src, amount, description)
    return true
end)

exports('RemoveCashMoney', function(src, value, description)
    local player = exportPlayer('RemoveCashMoney', src)
    local amount = player and exportAmount('RemoveCashMoney', value)
    if not amount then
        return false
    end
    if (player.PlayerData.money.cash or 0) < amount then
        return false
    end
    if not player.Functions.RemoveMoney('cash', amount, 'bank-export') then
        return false
    end
    description = sanitizeText(description, 120)
    logTransaction(player.PlayerData.citizenid, 'admin_cash_removal', amount, description)
    adminLog('Nakit alındı', player, src, amount, description)
    return true
end)

exports('GetPlayerAccount', function(src)
    local player = exportPlayer('GetPlayerAccount', src)
    if not player then
        return nil
    end
    local identifier = player.PlayerData.citizenid
    return {
        source = src,
        name = getName(player),
        identifier = identifier,
        bankBalance = player.PlayerData.money.bank,
        cashBalance = player.PlayerData.money.cash,
        accountNumber = '****-****-' .. cardDigits(identifier)
    }
end)

exports('GetBankBalance', function(src)
    local player = exportPlayer('GetBankBalance', src)
    return player and player.PlayerData.money.bank or 0
end)

exports('GetCashBalance', function(src)
    local player = exportPlayer('GetCashBalance', src)
    return player and player.PlayerData.money.cash or 0
end)

exports('HasEnoughBank', function(src, value)
    local player = exportPlayer('HasEnoughBank', src)
    local amount = player and exportAmount('HasEnoughBank', value)
    return amount ~= nil and (player.PlayerData.money.bank or 0) >= amount
end)

exports('HasEnoughCash', function(src, value)
    local player = exportPlayer('HasEnoughCash', src)
    local amount = player and exportAmount('HasEnoughCash', value)
    return amount ~= nil and (player.PlayerData.money.cash or 0) >= amount
end)

exports('TransferMoney', function(fromSrc, toSrc, value, description)
    local sender = exportPlayer('TransferMoney', fromSrc)
    local target = sender and exportPlayer('TransferMoney', toSrc)
    local amount = target and exportAmount('TransferMoney', value)
    if not amount then
        return false
    end
    if sender.PlayerData.citizenid == target.PlayerData.citizenid then
        return false
    end
    if (sender.PlayerData.money.bank or 0) < amount then
        return false
    end
    if not sender.Functions.RemoveMoney('bank', amount, 'bank-export') then
        return false
    end
    target.Functions.AddMoney('bank', amount, 'bank-export')

    description = sanitizeText(description, 120)
    local suffix = description ~= '' and (' · ' .. description) or ''
    logTransaction(sender.PlayerData.citizenid, 'admin_transfer_out', amount, getName(target) .. suffix)
    logTransaction(target.PlayerData.citizenid, 'admin_transfer_in', amount, getName(sender) .. suffix)
    adminLog('Oyuncular arası aktarım', sender, fromSrc, amount, getName(target) .. suffix)
    return true
end)

exports('GetSavingsAccount', function(src, callback)
    local player = Config.Banking.allowSavingsAccounts and exportPlayer('GetSavingsAccount', src)
    if not player then
        if callback then callback(nil) end
        return
    end
    local identifier = player.PlayerData.citizenid
    MySQL.single('SELECT balance, status FROM banking_savings WHERE identifier = ?', { identifier }, function(row)
        if not callback then
            return
        end
        if not row then
            return callback(nil)
        end
        callback({
            balance = row.balance or 0,
            status = row.status,
            accountNumber = '****-****-' .. cardDigits(identifier):reverse(),
            active = row.status == 'active'
        })
    end)
end)

exports('AddSavingsMoney', function(src, value, description)
    if not Config.Banking.allowSavingsAccounts then
        return false
    end
    local player = exportPlayer('AddSavingsMoney', src)
    local amount = player and exportAmount('AddSavingsMoney', value)
    if not amount then
        return false
    end
    local identifier = player.PlayerData.citizenid
    description = sanitizeText(description, 120)
    MySQL.update("UPDATE banking_savings SET balance = balance + ? WHERE identifier = ? AND status = 'active' AND balance + ? <= ?", {
        amount, identifier, amount, MAX_SAVINGS
    }, function(changed)
        if changed == 1 then
            logTransaction(identifier, 'admin_savings_deposit', amount, description)
            adminLog('Birikim hesabına para eklendi', player, src, amount, description)
        end
    end)
    return true
end)

exports('LogCustomTransaction', function(src, kind, value, description)
    local player = exportPlayer('LogCustomTransaction', src)
    local amount = tonumber(value)
    if not player or type(kind) ~= 'string' or not amount then
        return false
    end
    logTransaction(player.PlayerData.citizenid, kind:sub(1, 50), math.floor(amount), sanitizeText(description, 120))
    return true
end)

exports('OpenBankingUI', function(src)
    return openRemote(src)
end)
