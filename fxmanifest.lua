fx_version 'cerulean'
game 'gta5'

author 'Neon'
description 'Neon Banking'
version '2.1.0'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/script.js'
}

dependencies {
    '/onesync',
    'qb-core',
    'oxmysql'
}

lua54 'yes'
