local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/888033538283294721/mEtOmOu4xMr3ZGHVGpnKD3Y9oLOr_WE01FxFYcoMPQUSCXdN_sMj1o9rSbMRmQP3Mt20" -- paste your discord webhook between the quotes if you want to enable discord log.
local DISCORD_NAME = "Ban-log"
local STEAM_KEY = ""
local DISCORD_IMAGE = "https://i.imgur.com/nOwaI24.png"
local bancache,namecache = {},{}
local open_assists,active_assists = {},{}
local GetPlayerIdentifiers = GetPlayerIdentifiers
local GetPlayerName = GetPlayerName
local GetPlayerPed = GetPlayerPed
local GetEntityCoords = GetEntityCoords

local function logUnfairUse(xPlayer)
    if not xPlayer then return end
    print(("[^1"..GetCurrentResourceName().."^7] Játékos %s (%s) megprobált admin parancsokat használni"):format(xPlayer.getName(),xPlayer.identifier))
    sendToDiscord(("Játékos	%s (%s) megprobált admin parancsokat használni"):format(xPlayer.getName(),xPlayer.identifier))
end

local function sendToDiscord(name, message, color)
    local connect = {
          {
              ["color"] = color,
              ["title"] = "**".. name .."**",
              ["description"] = message,
              ["footer"] = {
                  ["text"] = "",
              },
          }
      }
    PerformHttpRequest(DISCORD_WEBHOOK, function(err, text, headers) end, 'POST', json.encode({username = DISCORD_NAME, embeds = connect, avatar_url = DISCORD_IMAGE}), { ['Content-Type'] = 'application/json' })
end

local function refreshNameCache()
    namecache={}
    for _,v in ipairs(MySQL.query.await('SELECT `steam`,`name` FROM `bwh_identifiers`')) do
        namecache[v.steam]=v.name
    end
end

local function refreshBanCache()
    bancache={}--SELECT `id`, `receiver`, `sender`, `length`, `reason`, `unbanned` FROM `bwh_bans`
    for _,v in ipairs(MySQL.query.await('SELECT `id`, `receiver`, `sender`, UNIX_TIMESTAMP(length) AS `length`, `reason`, `unbanned` FROM `bwh_bans`')) do
        table.insert(bancache,{id=v.id,sender=v.sender,sender_name=namecache[v.sender] and namecache[v.sender] or "N/A",receiver=json.decode(v.receiver),reason=v.reason,length=v.length,unbanned=v.unbanned==1})
    end
end

local function split(s, delimiter) result = {};for match in (s..delimiter):gmatch("(.-)"..delimiter) do table.insert(result, match) end return result end

local function isAdmin(xPlayer)
    for _,v in ipairs(Config.admin_groups) do
        if xPlayer.getGroup() == v then return true end
    end
    return false
end

local function logAdmin(msg)
    local a = ESX.GetExtendedPlayers('group', 'admin')
    for _,xPlayer in pairs(a) do
        TriggerClientEvent("chat:addMessage", xPlayer.source,{color={255,0,0},multiline=false,args={"ADMIN-SYSTEM", msg}})
    end
end

local function banPlayer(xPlayer,xTarget,reason,length,offline)
    local targetidentifiers,offlinename,timestring,data = {},nil,nil,nil
    if offline then
        data = MySQL.query.await('SELECT * FROM `bwh_identifiers` WHERE license = ?',{xTarget})
        if #data<1 then
            return false, "~r~A Játékos nincs az adatbázisban!"
        end
        offlinename = data[1].name
        for k,v in pairs(data[1]) do
            if k~="name" then table.insert(targetidentifiers,v) end
        end
    else
        targetidentifiers = GetPlayerIdentifiers(xTarget.source)
    end
    if length == "" then length = nil end
    MySQL.insert('INSERT INTO `bwh_bans` (receiver, sender, length, reason) VALUES(?, ?, ?, ?)',{json.encode(targetidentifiers), xPlayer.identifier, length, reason},function(_)
        local banid = MySQL.scalar.await('SELECT MAX(id) FROM bwh_bans')
        sendToDiscord(("Játékos %s (%s) ki lett tiltva a szerverröl! %s, Érvényesség: %s, Indok: '%s'"..(offline and " (OFFLINE BAN)" or "")):format(offline and offlinename or xTarget.getName(),offline and targetidentifiers[1] or xTarget.identifier,xPlayer.getName(),length~=nil and length or "Végleges",reason))
        logAdmin(("Játékos %s (%s) ki lett tiltva a szerverröl! %s, Érvényesség: %s, Indok: '%s'"..(offline and " (OFFLINE BAN)" or "")):format(offline and offlinename or xTarget.getName(),offline and targetidentifiers[1] or xTarget.identifier,xPlayer.getName(),length~=nil and length or "Végleges",reason))
        if length then
            timestring = length
            local year,month,day,hour,minute = string.match(length,"(%d+)/(%d+)/(%d+) (%d+):(%d+)")
            length = os.time({year=year,month=month,day=day,hour=hour,min=minute})
        end
        table.insert(bancache,{id=banid==nil and "1" or banid,sender=xPlayer.identifier,reason=reason,sender_name=xPlayer.getName(),receiver=targetidentifiers,length=length})
        if offline then xTarget = ESX.GetPlayerFromIdentifier(xTarget) end -- just in case the player is on the server, you never know
        if xTarget then
            TriggerClientEvent("el_bwh:gotBanned",xTarget.source, reason)
            SetTimeout(5000, function()
                DropPlayer(xTarget.source,Config.banformat:format(reason,length and timestring or "PERMANENT",xPlayer.getName(),banid==nil and "1" or banid))
            end)
        else return false, "~r~Ismeretlen Hiba (MySQL?)" end
        return true, ""
    end)
end

local function execOnAdmins(func)
    local ac = 0
    local xPlayers = ESX.GetExtendedPlayers()
    for _, xPlayer in pairs(xPlayers) do
        if isAdmin(xPlayer) then
            ac += 1
            func(xPlayer.source)
        end
    end
    return ac
end

local function warnPlayer(xPlayer,xTarget,message,anon)
    MySQL.prepare('INSERT INTO `bwh_warnings` (`receiver`, `sender`, `message`) VALUES(?, ?, ?)',{xTarget.identifier, xPlayer.identifier, message})
    TriggerClientEvent("el_bwh:receiveWarn",xTarget.source,anon and "" or xPlayer.getName(),message)
    sendToDiscord(("Admin ^1%s^7 figyelmeztette ^1%s^7 (%s) Játékost, Üzenet: '%s'"):format(xPlayer.getName(),xTarget.getName(),xTarget.identifier,message))
end

local function acceptAssist(xPlayer, target)
    if isAdmin(xPlayer) then
        local source = xPlayer.source
        for _,v in pairs(active_assists) do
            if v==source then
                TriggerClientEvent("chat:addMessage",source,{color={255,0,0},multiline=false,args={"ADMIN-SYSTEM |"," Te már segitesz valakinek!"}})
                return
            end
        end
        if open_assists[target] and not active_assists[target] then
            open_assists[target]=nil
            active_assists[target]=source
            local ped = GetPlayerPed(target)
            local coords = GetEntityCoords(ped)
            TriggerClientEvent("el_bwh:acceptedAssist", source, coords, target)
            TriggerClientEvent("el_bwh:hideAssistPopup", source)
            TriggerClientEvent("chat:addMessage",source,{color={0,255,0},multiline=false,args={"ADMIN-SYSTEM |"," Teleportálás a játékoshoz..."}})
        elseif not open_assists[target] and active_assists[target] and active_assists[target]~=source then
            TriggerClientEvent("chat:addMessage",source,{color={255,0,0},multiline=false,args={"ADMIN-SYSTEM |"," Már valaki segit ennek a játékosnak!"}})
        else
            TriggerClientEvent("chat:addMessage",source,{color={255,0,0},multiline=false,args={"ADMIN-SYSTEM |"," Ez a játékos nem kért segitséget!"}})
        end
    else
        TriggerClientEvent("chat:addMessage",source,{color={255,0,0},multiline=false,args={"ADMIN-SYSTEM |"," Nincs jogosultságod ehhez a parancshoz!"}})
    end
end

local function deleteBans()
    local ban = {}
    local t = os.time()
    for _,v in ipairs(MySQL.query.await('SELECT `id`, `receiver`, `sender`, UNIX_TIMESTAMP(length) AS `length`, `reason`, `unbanned` FROM `bwh_bans`')) do
        table.insert(ban,{id=v.id,sender=v.sender,sender_name=namecache[v.sender] and namecache[v.sender] or "N/A",receiver=json.decode(v.receiver),reason=v.reason,length=v.length,unbanned=v.unbanned==1})
    end
    for _,b in ipairs(bancache) do
        if not b.unbanned and b.length and b.length < t then
            MySQL.update('UPDATE `bwh_bans` SET `unbanned` = 1 WHERE `length` = ?',{os.date("%Y-%m-%d %H:%M",b.length)})
        end
    end
    MySQL.update('DELETE FROM `bwh_bans` WHERE `unbanned` = ?',{1},function(o)
        print("Deleted "..o.." bans")
    end)
end

local function isBanned(identifiers)
    local time = os.time()
    for _,ban in ipairs(bancache) do
        if not ban.unbanned and (not ban.length or ban.length > time) then
            for _,bid in ipairs(ban.receiver) do
                if Config.ip_ban and bid:find("ip:") then
                    for _,pid in ipairs(identifiers) do
                        if bid == pid then return true, ban end
                    end
                else
                    for _,pid in ipairs(identifiers) do
                        if bid == pid then return true, ban end
                    end
                end
            end
        end
    end
    return false, nil
end

CreateThread(function() -- startup

    MySQL.ready(function()
        refreshNameCache()
        refreshBanCache()
    end)

    sendToDiscord("Admin system log elinditva...")

    ESX.RegisterServerCallback("el_bwh:ban", function(source,cb,target,reason,length,offline)
        if not target or not reason then return end
        local xPlayer = ESX.GetPlayerFromId(source)
        local xTarget = ESX.GetPlayerFromId(target)
        if not xPlayer or (not xTarget and not offline) then cb(nil); return end
        if isAdmin(xPlayer) then
            local success, reason = banPlayer(xPlayer,offline and target or xTarget,reason,length,offline)
            cb(success, reason)
        else logUnfairUse(xPlayer); cb(false) end
    end)

    ESX.RegisterServerCallback("el_bwh:warn",function(source,cb,target,message,anon)
        if not target or not message then return end
        local xPlayer = ESX.GetPlayerFromId(source)
        local xTarget = ESX.GetPlayerFromId(target)
        if not xPlayer or not xTarget then cb(nil); return end
        if isAdmin(xPlayer) then
            warnPlayer(xPlayer,xTarget,message,anon)
            cb(true)
        else logUnfairUse(xPlayer); cb(false) end
    end)

    ESX.RegisterServerCallback("el_bwh:getWarnList",function(source,cb)
        local xPlayer = ESX.GetPlayerFromId(source)
        if isAdmin(xPlayer) then
            local warnlist = {}
            for _,v in ipairs(MySQL.query.await('SELECT * FROM `bwh_warnings` LIMIT ?',{Config.page_element_limit})) do
                v.receiver_name=namecache[v.receiver]
                v.sender_name=namecache[v.sender]
                table.insert(warnlist,v)
            end
            cb(json.encode(warnlist),MySQL.scalar('SELECT CEIL(COUNT(id)/?) FROM `bwh_warnings`',{Config.page_element_limit}))
        else logUnfairUse(xPlayer); cb(false) end
    end)

    ESX.RegisterServerCallback("el_bwh:getBanList",function(source,cb)
        local xPlayer = ESX.GetPlayerFromId(source)
        if isAdmin(xPlayer) then
            local data = MySQL.query.await('SELECT * FROM `bwh_bans` LIMIT ?',{Config.page_element_limit})
            local banlist = {}
            for _,v in ipairs(data) do
                v.receiver_name = namecache[json.decode(v.receiver)[1]]
                v.sender_name = namecache[v.sender]
                table.insert(banlist,v)
            end
            cb(json.encode(banlist),MySQL.scalar('SELECT CEIL(COUNT(id)/?) FROM `bwh_bans`',{Config.page_element_limit}))
        else logUnfairUse(xPlayer); cb(false) end
    end)

    ESX.RegisterServerCallback("el_bwh:getListData",function(source,cb,list,page)
        local xPlayer = ESX.GetPlayerFromId(source)
        if isAdmin(xPlayer) then
            if list=="banlist" then
                local banlist = {}
                for _,v in ipairs(MySQL.query.await('SELECT * FROM `bwh_bans` LIMIT ? OFFSET ?',{Config.page_element_limit, Config.page_element_limit*(page-1)})) do
                    v.receiver_name = namecache[json.decode(v.receiver)[1]]
                    v.sender_name = namecache[v.sender]
                    table.insert(banlist,v)
                end
                cb(json.encode(banlist))
            else
                local warnlist = {}
                for _,v in ipairs(MySQL.query.await('SELECT * FROM `bwh_warnings` LIMIT ? OFFSET ?',{Config.page_element_limit, Config.page_element_limit*(page-1)})) do
                    v.sender_name=namecache[v.sender]
                    v.receiver_name=namecache[v.receiver]
                    table.insert(warnlist,v)
                end
                cb(json.encode(warnlist))
            end
        else logUnfairUse(xPlayer); cb(nil) end
    end)

    ESX.RegisterServerCallback("el_bwh:unban",function(source,cb,id)
        local xPlayer = ESX.GetPlayerFromId(source)
        if isAdmin(xPlayer) then
            MySQL.update('UPDATE `bwh_bans` SET `unbanned` = ? WHERE `id` = ?',{1, id},function(rc)
                local bannedidentifier = "N/A"
                for k,v in ipairs(bancache) do
                    if v.id==id then
                        bannedidentifier = v.receiver[1]
                        bancache[k].unbanned = true
                        break
                    end
                end
                sendToDiscord(("Admin ^1%s^7 unbanned ^1%s^7 (%s)"):format(xPlayer.getName(),(bannedidentifier~="N/A" and namecache[bannedidentifier]) and namecache[bannedidentifier] or "N/A",bannedidentifier))
                logAdmin(("Admin ^1%s^7 unbanned ^1%s^7 (%s)"):format(xPlayer.getName(),(bannedidentifier~="N/A" and namecache[bannedidentifier]) and namecache[bannedidentifier] or "N/A",bannedidentifier))
                cb(rc>0)
            end)
        else logUnfairUse(xPlayer); cb(false) end
    end)

    ESX.RegisterServerCallback("el_bwh:getIndexedPlayerList",function(source, cb)
        local xPlayer = ESX.GetPlayerFromId(source)
        if isAdmin(xPlayer) then
        	local players = {}
                local xPlayers = ESX.GetExtendedPlayers() -- Returns all xPlayers
                for _, xPlayer in pairs(xPlayers) do
        		    players[tostring(xPlayer.source)] = GetPlayerName(xPlayer.source)..(xPlayer.source == source and " (self)" or "")
                end
        	cb(json.encode(players))
        else logUnfairUse(xPlayer); cb(false) end
    end)
end)

RegisterServerEvent('el_bwh:backupcheck')
AddEventHandler('el_bwh:backupcheck', function()
    local identifiers = GetPlayerIdentifiers(source)
    local banned = isBanned(identifiers)
    if banned then
        DropPlayer(source, "Ban bypass detected, don’t join back!")
    end
end)

AddEventHandler("playerConnecting",function(_, _, def)
    local source = source
    local identifiers = GetPlayerIdentifiers(source)
    if #identifiers > 0 and identifiers[1] then
        local banned, data = isBanned(identifiers)
        namecache[identifiers[1]] = GetPlayerName(source)
        if banned then
            if data then
                print(("[^1"..GetCurrentResourceName().."^7] Banned player %s (%s) tried to join, their ban expires on %s (Ban ID: #%s)"):format(GetPlayerName(source),data.receiver[1],data.length and os.date("%Y-%m-%d %H:%M",data.length) or "PERMANENT",data.id))
                local kickmsg = Config.banformat:format(data.reason,data.length and os.date("%Y-%m-%d %H:%M",data.length) or "PERMANENT",data.sender_name,data.id)
                if Config.backup_kick_method then DropPlayer(source, kickmsg) else def.done(kickmsg) end
            end
        else
            local playername = GetPlayerName(source)
            local saneplayername = "Adjusted Playername"
            if string.gsub(playername, "[^a-zA-Z0-9]", "") ~= "" then
                saneplayername = string.gsub(playername, "[^a-zA-Z0-9 ]", "")
            end
            local data = {["@name"]=saneplayername}
            for _,v in ipairs(identifiers) do
                data["@"..split(v,":")[1]]=v
            end
            if not data["@steam"] then
	            if Config.kick_without_steam then
		            print("[^1"..GetCurrentResourceName().."^7] Player connecting without steamid, removing player from server.")
		            def.done("You need to have steam open to play on this server.")
                else
                    print("[^1"..GetCurrentResourceName().."^7] Player connecting without steamid, skipping identifier storage.")
                end
            else
                MySQL.prepare('INSERT INTO `bwh_identifiers` (`steam`, `license`, `ip`, `name`, `xbl`, `live`, `discord`, `fivem`) VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE fivem = VALUES(fivem)', {data["@steam"], data["@license"], data["@ip"], data["@name"], data["@xbl"], data["@live"], data["@discord"], data["@fivem"]})
            end
        end
    else
        if Config.backup_kick_method then DropPlayer(source,"[BWH] No identifiers were found when connecting, please reconnect") else def.done("[BWH] No identifiers were found when connecting, please reconnect") end
    end
end)

AddEventHandler("playerDropped",function(_)
    if open_assists[source] then open_assists[source]=nil end
    for k,v in ipairs(active_assists) do
        if v == source then
            active_assists[k]=nil
            TriggerClientEvent("chat:addMessage",k,{color={255,0,0},multiline=false,args={"ADMIN-SYSTEM |"," Az admin, aki segitett lelépett a szerverröl!"}})
            return
        elseif k == source then
            TriggerClientEvent("el_bwh:assistDone",v)
            TriggerClientEvent("chat:addMessage",v,{color={255,0,0},multiline=false,args={"ADMIN-SYSTEM |"," A játékos, akinek segitettél lelépett a szerverröl, vissza teleportálás folyamatban..."}})
            active_assists[k]=nil
            return
        end
    end
end)

AddEventHandler("el_bwh:ban",function(sender,target,reason,length,offline)
    if source == "" then -- if it's from server only
        banPlayer(sender,target,reason,length,offline)
    end
end)

AddEventHandler("el_bwh:warn",function(sender,target,message,anon)
    if source == "" then -- if it's from server only
        warnPlayer(sender,target,message,anon)
    end
end)

RegisterCommand("report", function(source, args, _)
    local reason = table.concat(args," ")
    if reason == "" or not reason then TriggerClientEvent("chat:addMessage",source,{color={255,0,0},multiline=false,args={"ADMIN-SYSTEM |"," Kérlek, ird be az indokot."}}); return end
    if not open_assists[source] and not active_assists[source] then
        local ac = execOnAdmins(function(admin)
		TriggerClientEvent("chat:addMessage",admin,{color={0,255,255},multiline=Config.chatassistformat:find("\n")~=nil,args={"BWH",Config.chatassistformat:format(GetPlayerName(source),source,reason)}}) end)
        if ac > 0 then
            open_assists[source]=reason
            SetTimeout(300000,function()
                if open_assists[source] then open_assists[source]=nil end
                if GetPlayerName(source)~=nil then
                    TriggerClientEvent("chat:addMessage",source,{color={255,0,0},multiline=false,args={"ADMIN-SYSTEM |"," A segitségkérést visszavonták!"}})
                end
            end)
             TriggerClientEvent("chat:addMessage",source,{color={0,255,0},multiline=false,args={"ADMIN-SYSTEM |"," A Segitségkérésed el lett küldve! (5 percig érvényes), visszavonáshoz ^1/creport^7"}})
        else
            TriggerClientEvent("chat:addMessage",source,{color={255,0,0},multiline=false,args={"ADMIN-SYSTEM |"," Jelenleg nincs elérhetö admin a szerveren!"}})
        end
    else
        TriggerClientEvent("chat:addMessage",source,{color={255,0,0},multiline=false,args={"ADMIN-SYSTEM |"," Valaki már segit neked, vagy van egy függöben lévö segitségkérésed!"}})
    end
end, false)

RegisterCommand("creport", function(source, _, _)
    if open_assists[source] then
        open_assists[source]=nil
        TriggerClientEvent("chat:addMessage",source,{color={0,255,0},multiline=false,args={"ADMIN-SYSTEM |"," A Segitségkérésed törölve!"}})
        execOnAdmins(function(admin) TriggerClientEvent("el_bwh:hideAssistPopup",admin) end)
    else
        TriggerClientEvent("chat:addMessage",source,{color={255,0,0},multiline=false,args={"ADMIN-SYSTEM |","  Egy admin már elfogadta a segiségkérésedet, nem tudod visszavonni!"}})
    end
end, false)

RegisterCommand("rend", function(source, _, _)
    local xPlayer = ESX.GetPlayerFromId(source)
    if isAdmin(xPlayer) then
        local found = false
        for k,v in pairs(active_assists) do
            if v==source then
                found = true
                active_assists[k]=nil
                TriggerClientEvent("chat:addMessage",source,{color={0,255,0},multiline=false,args={"ADMIN-SYSTEM |"," Lezártad az ügyet, vissza teleportálás folyamatban..."}})
                TriggerClientEvent("el_bwh:assistDone",source)
            end
        end
        if not found then TriggerClientEvent("chat:addMessage",source,{color={255,0,0},multiline=false,args={"ADMIN-SYSTEM |"," Jelenleg nem segitesz senkinek!"}}) end
    else
        TriggerClientEvent("chat:addMessage",source,{color={255,0,0},multiline=false,args={"ADMIN-SYSTEM |"," Nincs jogosultságod ehhez a parancshoz!"}})
    end
end, false)

RegisterCommand("bwh", function(source, args, _)
    local xPlayer = ESX.GetPlayerFromId(source)
    if isAdmin(xPlayer) then
        if args[1]=="ban" or args[1]=="warn" or args[1]=="warnlist" or args[1]=="banlist" then
            TriggerClientEvent("el_bwh:showWindow",source,args[1])
        elseif args[1]=="refresh" then
            TriggerClientEvent("chat:addMessage",source,{color={0,255,0},multiline=false,args={"ADMIN-SYSTEM |","Adatbázis frissitése folyamatban..."}})
            refreshNameCache()
            refreshBanCache()
        elseif args[1]=="assists" then
            local openassistsmsg,activeassistsmsg = "",""
            for k,v in pairs(open_assists) do
                openassistsmsg=openassistsmsg.."^5ID "..k.." ("..GetPlayerName(k)..")^7 - "..v.."\n"
            end
            for k,v in pairs(active_assists) do
                activeassistsmsg=activeassistsmsg.."^5ID "..k.." ("..GetPlayerName(k)..")^7 - "..v.." ("..GetPlayerName(v)..")\n"
            end
            TriggerClientEvent("chat:addMessage",source,{color={0,255,0},multiline=true,args={"ADMIN-SYSTEM |"," Függöben lévö segitségkérések:\n"..(openassistsmsg~="" and openassistsmsg or "^1Nincs függöben lévö segitségkérés!")}})
            TriggerClientEvent("chat:addMessage",source,{color={0,255,0},multiline=true,args={"ADMIN-SYSTEM |"," Elérhetö segitségkérések:\n"..(activeassistsmsg~="" and activeassistsmsg or "^1Nincs elérhetö segitségkérés")}})
        elseif args[1]=="delete" then
            deleteBans()
        else
            TriggerClientEvent("chat:addMessage",source,{color={255,0,0},multiline=false,args={"ADMIN-SYSTEM |"," Érvénytelen parancs! Egészitsd ki: (^4ban^7,^4warn^7,^4banlist^7,^4warnlist^7,^4refresh^7,^4reports^7)"}})
        end
    else
        TriggerClientEvent("chat:addMessage",source,{color={255,0,0},multiline=false,args={"ADMIN-SYSTEM |"," Nincs jogosultságod ehhez a parancshoz!"}})
    end
end, false)

RegisterCommand("r", function(source, args, _)
    local xPlayer = ESX.GetPlayerFromId(source)
    local target = tonumber(args[1])
    acceptAssist(xPlayer,target)
end, false)

RegisterServerEvent("el_bwh:acceptAssistKey")
AddEventHandler("el_bwh:acceptAssistKey",function(target)
    if not target then return end
    local _source = source
    acceptAssist(ESX.GetPlayerFromId(_source),target)
end)
