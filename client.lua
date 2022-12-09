--#region Context Menu Registration

lib.registerContext({
	id = 'eol_factions_manage_faction',
	title = 'Manage Faction',
	options = {
		{
			title = 'Create Faction',
			description = 'A faction is necessary to claim territory',
			serverEvent = 'eol_factions:server:createFaction'
		}
	}
})

--#endregion Context Menu Registration

--#region Events

RegisterNetEvent('eol_factions:client:openFactionlessMenu', function()
	-- make sure this can only be triggered from the server
	if GetInvokingResource() then return end

	lib.showContext('eol_factions_manage_faction')
end)

RegisterNetEvent('eol_factions:client:openMenu', function(menu)
	-- catch incoming server context menu request and make sure it's coming from the server
	if GetInvokingResource() or not menu then return end

	lib.registerContext(menu)
	lib.showContext(menu.id)
end)

RegisterNetEvent('eol_factions:client:openInput', function(title, input)
	-- catch incoming server input dialog request and make sure it's coming from the server
	if GetInvokingResource() or not input then return end

	local dialog = lib.inputDialog(title, input)

	if not dialog then return end

	TriggerServerEvent('eol_factions:server:procInputFeedback', dialog, title, #input)
end)

AddEventHandler('gameEventTriggered', function (name, args)
	if name ~= 'CEventNetworkEntityDamage' then return end

	local victim, attacker, victimDied = args[1], args[2], args[4]
	if victim ~= cache.ped or not victimDied or not IsEntityDead(cache.ped) or not IsPedAPlayer(attacker) then return end

	local canContinue = lib.callback.await('eol_factions:server:areTheyInAFaction', false, GetPlayerServerId(NetworkGetPlayerIndexFromPed(attacker)))
	if not canContinue then return end

	local success = lib.callback.await('eol_factions:server:deductPowerOnDeath', false)
	if success then return end

	error('Something went wrong deducting power on your death')
end)

--#endregion Events