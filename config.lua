Config = {
    admin_groups = {"admin","superadmin"}, -- groups that can use admin commands
    banformat = "KITILTVA!\nIndok: %s\nÉrvényesség: %s\nBannolt: %s (Ban ID: #%s)", -- message shown when banned (1st %s = reason, 2nd %s = expire, 3rd %s = banner, 4th %s = ban id)
    popassistformat = "Játékos %s segitséget kért!\nIrd be <span class='text-success'>/racc %s</span> az elfogadáshoz vagy <span class='text-danger'>/rdec</span> az elutasitához <span class='text-danger'>/rend</span> az ügy végéhez", -- popup assist message format
    chatassistformat = "Játékos %s segitséget kért!\nIrd be ^2/r %s^7 az elfogadáshoz vagy ^1/rdec^7 az elutasitáshoz.\n^4Indok^7: %s", -- chat assist message format
    assist_key = false,
    assist_keys = {accept=208, decline=207}, -- keys for accepting/declining assist messages (default = page up, page down) - https://docs.fivem.net/game-references/controls/
    warning_screentime = 7.5, -- warning display length (in seconds)
    backup_kick_method = false, -- set this to true if banned players don't get kicked when banned or they can re-connect after being banned.
    kick_without_steam = true, -- prevent a player from joining your server without a steam identifier.
    page_element_limit = 950,
    ip_ban = false -- set to true to use ip in bans
}
