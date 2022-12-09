fx_version 'cerulean'
game 'gta5'

name 'eol_factions'
author 'Vampire#8144 & BerkieB'
description 'Factions for FiveM like Minecraft'
version '1.0.0'
license 'GNU GPL v3'
repository 'https://github.com/BerkieBb/eol_factions'

lua54 'yes'
use_experimental_fxv2_oal 'yes'

shared_scripts {
	'@ox_lib/init.lua',
	'config.lua'
}

client_scripts {
	'client.lua',
}

server_scripts {
	'@oxmysql/lib/MySQL.lua',
	'server.lua',
}

dependencies {
	'/server:5848',
	'/onesync',
	'oxmysql',
	'qb-core',
	'qb-management',
	'ox_lib'
}