fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'fivechat'
description 'Chat with local, OOC, staff and 911 channels, /me and /do, tabs and mutes. Replaces the default chat'
version '1.0.0'
author 'IamZach'
discord 'https://discord.gg/agn'
repository 'https://github.com/1amZach/fivechat'

-- anything that depends on 'chat' or uses its events keeps working
provide 'chat'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

shared_script 'config.lua'
server_scripts {
    'server/framework.lua',
    'server/main.lua',
}
client_script 'client/main.lua'
