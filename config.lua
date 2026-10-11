Config = {}

Config.BankName = 'Neon Bank'
Config.Currency = '$'

Config.Command = {
    enabled = true,
    name = 'bank',
    permission = 'admin'
}

Config.Blips = {
    enabled = true,
    sprite = 108,
    color = 2,
    scale = 0.8,
    shortRange = true,
    display = 4
}

Config.BankerPed = {
    enabled = true,
    model = 'cs_bankman',
    scenario = 'WORLD_HUMAN_CLIPBOARD',
    invincible = true,
    freeze = true,
    blockEvents = true
}

Config.Interaction = {
    distance = 3.0,
    key = 38
}

Config.Banking = {
    enableBankerPed = true,
    allowSavingsAccounts = false,
    maxTransferAmount = 1000000,
    minTransferAmount = 1,
    transferFee = 0,
    enableTransactionHistory = true,
    maxHistoryEntries = 50,
    quickAmounts = { 500, 1000, 5000, 10000 }
}

Config.Pin = {
    maxAttempts = 5,
    lockSeconds = 300
}

Config.ATM = {
    enabled = true,
    models = {
        `prop_fleeca_atm`,
        `prop_atm_01`,
        `prop_atm_02`,
        `prop_atm_03`
    },
    interactionDistance = 2.0
}

Config.DiscordLogging = {
    enabled = true,
    webhook = '',
    botName = 'Banka',
    botAvatar = '',
    color = {
        deposit = 3066993,
        withdrawal = 15158332,
        transfer = 3447003,
        savings = 10181046,
        admin = 15844367
    },
    logEvents = {
        deposits = true,
        withdrawals = true,
        transfers = true,
        savingsOperations = true,
        accountOperations = true,
        historyClearing = true,
        pinOperations = true,
        adminActions = true
    }
}

Config.BankLocations = {
    { coords = vector4(149.4113, -1042.0449, 29.3680, 342.9182) },
    { coords = vector4(-1211.8585, -331.9854, 37.7809, 28.5983) },
    { coords = vector4(-2961.0720, 483.1107, 15.6970, 88.1986) },
    { coords = vector4(-112.2223, 6471.1128, 31.6267, 132.7517) },
    { coords = vector4(313.8176, -280.5338, 54.1647, 339.1609) },
    { coords = vector4(-351.3247, -51.3466, 49.0365, 339.3305) },
    { coords = vector4(1174.9718, 2708.2034, 38.0879, 178.2974) },
    { coords = vector4(247.0348, 225.1851, 106.2875, 158.7528) }
}

Config.Text = {
    press_bank = '[E] Banka',
    press_atm = '[E] ATM',
    command_help = 'Banka arayüzünü aç',
    not_near_bank = 'Bankaya yeterince yakın değilsin',
    session_expired = 'Banka oturumu kapandı',
    too_fast = 'Çok hızlı işlem yapıyorsun',
    not_allowed = 'Bu işlem burada yapılamaz',
    invalid_amount = 'Geçersiz tutar',
    min_amount = 'En az %s gönderebilirsin',
    max_amount = 'Tek seferde en fazla %s',
    no_cash = 'Üzerinde yeterli nakit yok',
    no_bank = 'Banka bakiyen yetersiz',
    no_bank_fee = 'Bakiyen komisyon dahil yetersiz',
    failed = 'İşlem tamamlanamadı',
    deposited = '%s hesabına yatırıldı',
    withdrawn = '%s hesabından çekildi',
    invalid_target = 'Geçersiz oyuncu ID',
    self_transfer = 'Kendine transfer yapamazsın',
    player_not_found = 'Oyuncu bulunamadı',
    transfer_sent = '%s gönderildi: %s',
    transfer_received = '%s tarafından %s gönderildi',
    savings_disabled = 'Birikim hesapları kapalı',
    savings_exists = 'Zaten bir birikim hesabın var',
    savings_opened = 'Birikim hesabın açıldı',
    savings_missing = 'Önce birikim hesabı açmalısın',
    savings_limit = 'Birikim hesabı bu tutarı alamaz',
    savings_low = 'Birikim bakiyen yetersiz',
    savings_in = '%s birikime aktarıldı',
    savings_out = '%s vadesiz hesaba aktarıldı',
    savings_closed = 'Birikim hesabın kapatıldı',
    pin_invalid = 'PIN 4 haneli olmalı',
    pin_saved = 'PIN kaydedildi',
    pin_missing = 'ATM için önce bankadan PIN oluşturmalısın',
    pin_wrong = 'PIN hatalı, kalan deneme: %s',
    pin_locked = 'Kart kilitlendi, %s saniye sonra tekrar dene',
    history_cleared = 'İşlem geçmişi temizlendi',
    history_empty = 'Temizlenecek işlem yok',
    atm_disabled = 'ATM kullanım dışı'
}
