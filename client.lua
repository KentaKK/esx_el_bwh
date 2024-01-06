local pos_before_assist, assisting, last_assist, IsFirstSpawn = nil, false, nil, true

RegisterNUICallback("ban", function(data,cb)
	if not data.target or not data.reason then return end
	ESX.TriggerServerCallback("el_bwh:ban",function(success,reason)
		if success then ESX.ShowNotification("~g~Játékos sikeresen kibannolva!") else ESX.ShowNotification(reason) end -- dont ask why i did it this way, im a bit retarded
	end, data.target, data.reason, data.length, data.offline)
end)

RegisterNUICallback("warn", function(data,cb)
	if not data.target or not data.message then return end
	ESX.TriggerServerCallback("el_bwh:warn",function(success)
		if success then ESX.ShowNotification("~g~Játékos sikeresen figyelmeztetve!") else ESX.ShowNotification("~r~Valami nem stimmel!") end
	end, data.target, data.message, data.anon)
end)

RegisterNUICallback("unban", function(data,cb)
	if not data.id then return end
	ESX.TriggerServerCallback("el_bwh:unban",function(success)
		if success then ESX.ShowNotification("~g~Játékos sikeresen feloldva!") else ESX.ShowNotification("~r~Valami nem stimmel!") end
	end, data.id)
end)

RegisterNUICallback("getListData", function(data,cb)
	if not data.list or not data.page then cb(nil); return end
	ESX.TriggerServerCallback("el_bwh:getListData",function(data)
		cb(data)
	end, data.list, data.page)
end)

RegisterNUICallback("hidecursor", function(data,cb)
	SetNuiFocus(false, false)
end)

AddEventHandler("playerSpawned", function(spawn)
    if IsFirstSpawn and Config.backup_kick_method then
        TriggerServerEvent("el_bwh:backupcheck")
        IsFirstSpawn = false
    end
end)

RegisterNetEvent("el_bwh:gotBanned")
AddEventHandler("el_bwh:gotBanned",function(rsn)
	CreateThread(function()
		local scaleform = RequestScaleformMovie("mp_big_message_freemode")
		while not HasScaleformMovieLoaded(scaleform) do Wait(0) end
		BeginScaleformMovieMethod(scaleform, "SHOW_SHARD_WASTED_MP_MESSAGE")
		ScaleformMovieMethodAddParamTextureNameString("~r~BANNED")
		ScaleformMovieMethodAddParamTextureNameString(rsn)
		ScaleformMovieMethodAddParamInt(5)
		EndScaleformMovieMethod()
		PlaySoundFrontend(-1, "LOSER", "HUD_AWARDS")
		ClearDrawOrigin()
		while true do
			Wait(0)
			DisableAllControlActions(0)
			DisableFrontendThisFrame()
			local ped = PlayerPedId()
			ESX.UI.Menu.CloseAll()
			SetEntityCoords(ped, 0, 0, 0, false, false, false, false)
			FreezeEntityPosition(ped, true)
			DrawRect(0.0,0.0,2.0,2.0,0,0,0,255)
			DrawScaleformMovieFullscreen(scaleform, 255, 255, 255, 255)
		end
	end)
end)

RegisterNetEvent("el_bwh:receiveWarn")
AddEventHandler("el_bwh:receiveWarn",function(sender,message)
	TriggerEvent("chat:addMessage",{color={255,255,0},multiline=true,args={"ADMIN-SYSTEM |"," Kaptál egy figyelmeztetést"..(sender~="" and " töle "..sender or "").."!\n-> "..message}})
	CreateThread(function()
		local scaleform = RequestScaleformMovie("mp_big_message_freemode")
		while not HasScaleformMovieLoaded(scaleform) do Wait(0) end
		BeginScaleformMovieMethod(scaleform, "SHOW_SHARD_WASTED_MP_MESSAGE")
		ScaleformMovieMethodAddParamTextureNameString("~y~WARNING")
		ScaleformMovieMethodAddParamTextureNameString(message)
		ScaleformMovieMethodAddParamInt(5)
		EndScaleformMovieMethod()
		PlaySoundFrontend(-1, "LOSER", "HUD_AWARDS")
		local drawing = true
		SetTimeout(Config.warning_screentime * 1000,function() drawing = false end)
		while drawing do
			Wait(0)
			DrawScaleformMovieFullscreen(scaleform, 255, 255, 255, 255)
		end
		SetScaleformMovieAsNoLongerNeeded(scaleform)
	end)
end)

RegisterNetEvent("el_bwh:requestedAssist")
AddEventHandler("el_bwh:requestedAssist",function(tn,t)
	SendNUIMessage({show=true,window="assistreq",template=Config.popassistformat,data={tn,t}})
	last_assist=t
end)

RegisterNetEvent("el_bwh:acceptedAssist")
AddEventHandler("el_bwh:acceptedAssist",function(co, t)
    print("Player",t)
    print(co)
	if assisting then return end
	local target = GetPlayerFromServerId(t)
	if target then
		local ped = PlayerPedId()
		pos_before_assist = GetEntityCoords(ped)
		assisting = true
		ESX.Game.Teleport(ped, co + vector3(0.0, 0.5, 0.0))
	end
end)

RegisterNetEvent("el_bwh:assistDone")
AddEventHandler("el_bwh:assistDone",function()
	if assisting then
		assisting = false
		if pos_before_assist then ESX.Game.Teleport(PlayerPedId(), pos_before_assist + vector3(0,0.5,0)); pos_before_assist = nil end
	end
end)

RegisterNetEvent("el_bwh:hideAssistPopup")
AddEventHandler("el_bwh:hideAssistPopup",function(t)
	SendNUIMessage({hide=true})
	last_assist=nil
end)

RegisterNetEvent("el_bwh:showWindow")
AddEventHandler("el_bwh:showWindow",function(win)
	if win=="ban" or win=="warn" then
        ESX.TriggerServerCallback("el_bwh:getIndexedPlayerList",function(indexedPList)
			SendNUIMessage({show=true,window=win,players=indexedPList})
		end)
	elseif win == "banlist" or win == "warnlist" then
		SendNUIMessage({loading=true,window=win})
		ESX.TriggerServerCallback(win=="banlist" and "el_bwh:getBanList" or "el_bwh:getWarnList",function(list,pages)
			SendNUIMessage({show=true,window=win,list=list,pages=pages})
		end)
	end
	SetNuiFocus(true, true)
end)

if Config.assist_key then
	CreateThread(function()
		while true do
			Wait(0)
			if IsControlJustPressed(0, Config.assist_keys.accept) then
				if not last_assist then
					ESX.ShowNotification("~r~Még senki sem kért segitséget.")
				elseif not NetworkIsPlayerActive(GetPlayerFromServerId(last_assist)) then
					ESX.ShowNotification("~r~A Segitséget kérö játékos már nem elérhetö.")
					last_assist=nil
				else
					TriggerServerEvent("el_bwh:acceptAssistKey",last_assist)
				end
			end
			if IsControlJustPressed(0, Config.assist_keys.decline) then
				TriggerEvent("el_bwh:hideAssistPopup")
			end
		end
	end)
end

CreateThread(function()
TriggerEvent('chat:addSuggestion', '/rdec', 'Segitségkérés elutasitása.',{})
TriggerEvent('chat:addSuggestion', '/report', 'Segitségkérés egy admintol.',{{name="Indok", help="Miért kell segitség?"}})
TriggerEvent('chat:addSuggestion', '/creport', 'Segitségkérés visszavonása.',{})
TriggerEvent('chat:addSuggestion', '/rend', 'Segitségkérés vége.',{})
TriggerEvent('chat:addSuggestion', '/r', 'Segitségkérés elfogadása', {{name="Játékos ID", help="Segitségkérö ID-je"}})
end)
