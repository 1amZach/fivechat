Config = {}

-- Opens the chat. Players can change it in their FiveM settings.
Config.key = 'T'

-- Plain messages only reach players nearby. false sends them to everyone, like the default chat.
Config.localChat = true

-- How far each kind of message carries, in meters. Messages from the far half show faded.
Config.range = {
    say = 20.0,
    me = 20.0,
    ['do'] = 20.0,
    looc = 20.0,
}

-- Command names. false turns one off.
Config.commands = {
    me = 'me',
    ['do'] = 'do',
    ooc = 'ooc',
    looc = 'looc',
    twt = 'twt',
    ad = 'ad',
    call = '911',
    staff = 'sc', -- only used without fivecord, which has its own staff chat
    mute = 'mute',
    unmute = 'unmute',
    clear = 'clear',
}

-- Which name each kind of message shows:
--   'character'  the character name from Qbox, QBCore or ESX, or the FiveM name without one
--   'player'     the FiveM name
Config.names = {
    say = 'character',
    me = 'character',
    ['do'] = 'character',
    looc = 'player',
    ooc = 'player',
    twt = 'character',
    ad = 'character',
    call = 'character',
    staff = 'player',
}

-- Server ids next to names.
Config.showIds = true

-- /me and /do also float over the player's head for a few seconds.
Config.overhead = {
    me = true,
    ['do'] = true,
    seconds = 6,
    range = 20.0,
}

-- Adverts cost money from the framework account. 0 makes them free.
Config.ads = {
    cost = 0,
    account = 'bank',
}

-- /911 goes to everyone on these jobs, with a blip where the call came from.
Config.calls = {
    jobs = { 'police', 'lspd', 'bcso', 'sasp', 'sheriff', 'ambulance', 'ems', 'doctor' },
    onDutyOnly = true,
    blipSeconds = 120,
    blip = { sprite = 161, color = 1, scale = 1.2 },
}

-- Without fivecord, staff are players with this ace. With fivecord its staff roles are used.
Config.staffAce = 'fivechat.staff'

Config.maxLength = 256

-- At most `messages` every `seconds`, and the same message no more than `repeats` times in a row.
Config.spam = {
    messages = 5,
    seconds = 6,
    repeats = 2,
}

-- Seconds without a new message before the closed chat fades out.
Config.fadeAfter = 10
