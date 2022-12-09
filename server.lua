local QBCore = exports['qb-core']:GetCoreObject()
local factions = {}
local grids = {}

--#region Input Layouts

local factNameInput = {
	{
		type = "input", -- type of the input
		label = "Faction Name", -- text you want to display above the input field
		placeholder = "Santa Claus", -- text you want to be displayed as a place holder
	},
}

local playerIdInput = {
	{
		type = "number", -- type of the input
		label = "Player ID", -- text you want to be displayed as a place holder
		default = 1, -- the default number to show
	},
}

local moneyInput = {
	{
		type = "number", -- type of the input
		label = "Amount Of Money", -- text you want to be displayed as a place holder
		default = 1, -- the default number to show
	}
}

--#endregion Input Layouts

--#region Functions

--- Clean a string
---@param str string The string to clean
---@param saveWhitespace boolean True to keep white space, otherwise it will remove it
---@return string, integer
local function cleanString(str, saveWhitespace)
	return string.gsub(tostring(str), saveWhitespace and '[^%w%s_]' or '[^%w_]', '')
end

--- Turn the value into a number snapped to the grid
---@param value string | number
---@return number
local function makeGridValue(value)
	return tonumber(string.sub(string.format('%.2f', value), 1, -3)) --[[@as number]]
end

exports('makeGridValue', makeGridValue)

--- Turn the coords into a snapped position on the grid
---@param coords vector2 | vector3 | vector4
---@return vector2
local function getCurrentGrid(coords)
	return vector2(makeGridValue(coords.x), makeGridValue(coords.y))
end

exports('getCurrentGrid', getCurrentGrid)

--- Get the owner of a grid
---@param coords vector2 | vector3 | vector4
---@return number | nil
local function getGridOwner(coords)
	if not coords then return end

	local grid = getCurrentGrid(coords)
	local gridString = string.format('%s:%s', grid.x, grid.y)

	return grids[gridString] and grids[gridString].claimedby or nil
end

exports('getGridOwner', getGridOwner)

--- Set the owner of a grid
---@param factionId number
---@param grid vector2
local function setGridOwner(factionId, grid)
	if not grid or not factionId then return end

	local gridString = string.format('%s:%s', tostring(grid.x), tostring(grid.y))
	if not grids[gridString] then
		local result = MySQL.insert.await('INSERT INTO `eol_factionclaims` (`claimedby`, `grid`) VALUES (?, ?)', {factionId, gridString})
		if not result then return end
		grids[gridString] = {
			grid = gridString,
			claimedby = factionId
		}
		TriggerEvent('eol_factions:server:gridOwnerChanged', gridString, factionId, false)
	else
		grids[gridString].claimedby = factionId
		TriggerEvent('eol_factions:server:gridOwnerChanged', gridString, factionId, true)
	end
end

exports('setGridOwner', setGridOwner)

--- Clear the owner of a grid
---@param grid vector2
local function clearGridOwner(grid)
	if not grid then return end

	local gridString = string.format('%s:%s', tostring(grid.x), tostring(grid.y))
	if not grids[gridString] then return end

	grids[gridString].claimedby = nil
	TriggerEvent('eol_factions:server:gridOwnerChanged', gridString)
end

exports('clearGridOwner', clearGridOwner)

--- Returns the power of the faction from the power of all the members
---@param id number
---@return integer
local function getFactionPower(id)
	local members = factions[id] and factions[id].members or nil
	local power = 0

	if members then
		for _, v in pairs(members) do
			power += v.power
		end
	end

	return power
end

exports('getFactionPower', getFactionPower)

--- Returns the amount of claims a person has made
---@param id string
---@return integer
local function getFactionClaims(id)
	local count = 0
	for _, v in pairs(grids) do
		if id == v.claimedby then
			count += 1
		end
	end

	return count
end

exports('getFactionClaims', getFactionClaims)

--- Returns the amount of claims a person has made
---@param id string
---@return table | nil
local function getOwnedGrids(id)
	local claimed = {}
	for _, v in pairs(grids) do
		if id == v.claimedby then
			local grid = {}
			for i in string.gmatch(v.grid, "([^:]+)") do
				grid[#grid + 1] = tonumber(i)
			end
			if grid and table.type(grid) ~= 'empty' then
				claimed[#claimed + 1] = vec2(grid[1], grid[2])
			end
		end
	end

	if table.type(claimed) == 'empty' then return end

	return claimed
end

exports('getOwnedGrids', getOwnedGrids)

--- Check if faction can be claimed by someone else
---@param overtakingFactionId number
---@param otherFactionId number
---@return boolean
local function canOverclaim(overtakingFactionId, otherFactionId, overtakingUserId, otherUserId)
	local overtakingPower = getFactionPower(overtakingFactionId)
	local otherPower = getFactionPower(otherFactionId)

	local overtakingTurfCount = getFactionClaims(overtakingUserId)
	local otherTurfCount = getFactionClaims(otherUserId)

	if overtakingTurfCount >= overtakingPower then return false end -- not enough power
	if otherPower >= otherTurfCount then return false end -- target too strong
	if overtakingPower > overtakingTurfCount and otherPower < otherTurfCount then return true end

	return false
end

exports('canOverclaim', canOverclaim)

--- Get the total power of the faction
---@param id number
---@return integer
local function totalFactionPower(id)
	local count = 0
	if factions[id] then
		for _ in pairs(factions[id].members) do
			count += 1
		end
	end
	return count * MaxPowerPerPlayer
end

exports('getTotalFactionPower', totalFactionPower)

--- Get the faction status of the player
---@param source number
---@return table | nil
local function factionStatus(source)
	local Player = QBCore.Functions.GetPlayer(source)

	if not Player then return nil end

	for _, v in pairs(factions) do
		if v.members[Player.PlayerData.citizenid] then
			local factionInfo = {}
			factionInfo.user = v.members[Player.PlayerData.citizenid]
			factionInfo.faction = v
			return factionInfo
		end
	end

	return nil
end

exports('getFactionStatus', factionStatus)

--- Checks if the rank has access to a menu component
---@param permission string
---@param rank number
---@return boolean
local function hasMenuPermission(permission, rank)
	local perm = MenuPermissions[permission]
	if not perm then return true end

	local permType = type(perm)

	if permType == 'number' then
		return perm <= rank
	elseif permType == 'table' then
		for i = 1, #perm do
			if perm[i] == rank then
				return true
			end
		end
	elseif permType == 'string' and string.lower(perm) == 'owner' and rank == 1 then
		return true
	end

	return false
end

--- Build faction menu based on the player
---@param source number
---@return table | nil
local function buildMenu(source)
	local Player = QBCore.Functions.GetPlayer(source)
	local fact = factionStatus(source)
	local ped = GetPlayerPed(source)
	local coords = GetEntityCoords(ped)
	local gridOwner = getGridOwner(coords)

	if not Player or not fact then return end

	local claims = getFactionClaims(fact.faction.id)
	local power = getFactionPower(fact.faction.id)
	local totalPower = totalFactionPower(fact.faction.id)

	local gridOwnerHeader = 'Territory Not Yours'
	if gridOwner == fact.faction.id then
		gridOwnerHeader = 'Territory Owned By You'
	end

	local menu = {
		id = 'eol_factions_manage_faction_server',
		title = ('%s | Rank: %s | Claims: %s | Power: %s | Max Power: %s | Balance: %s | %s'):format(fact.faction.name, fact.user.factionrank, claims, power, totalPower, exports['qb-management']:GetGangAccount(fact.faction.name), gridOwnerHeader),
		options = {}
	}

	if hasMenuPermission('invite', fact.user.factionrank) then
		menu.options[#menu.options + 1] = {
			title = 'Invite Member',
			description = 'Invite a member to the faction',
			serverEvent = 'eol_factions:server:inviteMember'
		}
	end

	if hasMenuPermission('kick', fact.user.factionrank) then
		menu.options[#menu.options + 1] = {
			title = 'Kick Member',
			description = 'Kick a member from the faction',
			serverEvent = 'eol_factions:server:kickMember'
		}
	end

	if hasMenuPermission('promote', fact.user.factionrank) then
		menu.options[#menu.options + 1] = {
			title = 'Promote Member',
			description = 'Promote a faction member',
			serverEvent = 'eol_factions:server:promoteMember'
		}
	end

	if hasMenuPermission('demote', fact.user.factionrank) then
		menu.options[#menu.options + 1] = {
			title = 'Demote Member',
			description = 'Demote a faction member',
			serverEvent = 'eol_factions:server:demoteMember'
		}
	end

	if hasMenuPermission('deposit', fact.user.factionrank) then
		menu.options[#menu.options + 1] = {
			title = 'Deposit Money',
			description = 'Deposit money for the faction to use',
			serverEvent = 'eol_factions:server:depositMoney'
		}
	end

	if hasMenuPermission('withdraw', fact.user.factionrank) then
		menu.options[#menu.options + 1] = {
			title = 'Withdraw Money',
			description = 'Withdraw money from the faction',
			serverEvent = 'eol_factions:server:withdrawMoney'
		}
	end

	if gridOwner ~= fact.faction.id and hasMenuPermission('claim', fact.user.factionrank) then
		menu.options[#menu.options + 1] = {
			title = 'Claim Territory',
			description = 'Claim the territory you are in',
			serverEvent = 'eol_factions:server:claimGrid'
		}
	elseif gridOwner == fact.faction.id and hasMenuPermission('unclaim', fact.user.factionrank) then
		menu.options[#menu.options + 1] = {
			title = 'Unclaim Territory',
			description = 'Unclaim the territory you are in',
			serverEvent = 'eol_factions:server:unclaimGrid'
		}
	end

	menu.options[#menu.options + 1] = {
		title = 'Toggle Claimed Territories',
		description = 'Toggle the visibility of all claimed territories on the map',
		event = 'eol_factions:client:toggleBlips'
	}

	if fact.faction.ownerid == Player.PlayerData.citizenid then
		-- owner of the faction
		menu.options[#menu.options + 1] = {
			title = 'Transfer Ownership',
			description = 'Give faction ownership to another member',
			serverEvent = 'eol_factions:server:transferFaction'
		}
	else
		-- member of the faction
		menu.options[#menu.options + 1] = {
			title = 'Leave Faction',
			description = 'Leave this faction',
			serverEvent = 'eol_factions:server:leaveFaction'
		}
	end

	return menu
end

--- Create a faction and set the provided player as the owner
---@param source number
---@param player table
---@param factionName string
local function createFaction(source, player, factionName)
	if not player or not factionName then return end

	for _, v in pairs(factions) do
		if v.name == factionName then
			TriggerClientEvent('ox_lib:notify', source, {description = ("A faction with name %s already exists, choose a different name"):format(factionName), type = "error"})
			return
		end
	end

	local id = MySQL.insert.await('INSERT INTO `eol_factions` (`name`, `ownerid`) VALUES (?, ?) ', {factionName, player.PlayerData.citizenid})
	if not id then return end

	local plyrFact = MySQL.insert.await('INSERT INTO `eol_factionusers` (`identifier`, `factionid`, `power`) VALUES (?, ?, ?) ', {player.PlayerData.citizenid, id, StartingPower})
	if not plyrFact then return end

	factions[id] = {
		name = factionName,
		ownerid = player.PlayerData.citizenid,
		id = id,
		members = {
			[player.PlayerData.citizenid] = {
				identifier = player.PlayerData.citizenid,
				factionid = id,
				factionrank = 1,
				power = StartingPower
			}
		}
	}

	local success = MySQL.insert.await('INSERT INTO `management_funds` (`job_name`, `amount`, `type`) VALUES (?, ?, ?)', {factionName, 0, 'gang'})
	if not success then return end

	-- success, reopen player menu

	TriggerClientEvent('ox_lib:notify', source, {description = "You created a faction!", type = "success"})
	TriggerEvent('eol_factions:server:factionCreated', id, source, player.PlayerData.citizenid)

	local menu = buildMenu(source)
	if not menu then return end
	TriggerClientEvent('eol_factions:client:openMenu', source, menu)
end

--- Process member invite
---@param source number
---@param player table
---@param invitingMemberId number
local function inviteMember(source, player, invitingMemberId)
	if not source or not player or not invitingMemberId then return end

	if source == invitingMemberId then
		TriggerClientEvent('ox_lib:notify', source, {description = "You can't invite yourself!", type = "error"})
		return
	end

	local playerPed = GetPlayerPed(source)
	local invitingPed = GetPlayerPed(invitingMemberId)
	if invitingPed == 0 then
		TriggerClientEvent('ox_lib:notify', source, {description = "Invalid Person!", type = "error"})
		return
	end

	local playerCoords = GetEntityCoords(playerPed)
	local invitingCoords = GetEntityCoords(invitingPed)

	if #(playerCoords - invitingCoords) > 20 then
		TriggerClientEvent('ox_lib:notify', source, {description = "You're too far from this person!", type = "error"})
		return
	end

	local playerFaction = factionStatus(source)
	local invitingFaction = factionStatus(invitingMemberId)

	if not playerFaction or not hasMenuPermission('invite', playerFaction.user.factionrank) then return end

	if playerFaction and not invitingFaction then
		local invitingPlayer = QBCore.Functions.GetPlayer(invitingMemberId)
		local result = MySQL.insert.await('INSERT INTO `eol_factionusers` (`identifier`, `factionid`, `factionrank`, `power`) VALUES (?, ?, ?, ?) ', {invitingPlayer.PlayerData.citizenid, playerFaction.faction.id, playerFaction.user.factionrank + 1, StartingPower})
		if result then
			factions[id].members[invitingPlayer.PlayerData.citizenid] = {
				identifier = invitingPlayer.PlayerData.citizenid,
				factionid = playerFaction.faction.id,
				factionrank = playerFaction.user.factionrank + 1,
				power = StartingPower
			}
			TriggerClientEvent('ox_lib:notify', source, {description = "Person joined your faction!", type = "success"})
			TriggerClientEvent('ox_lib:notify', invitingMemberId, {description = "You joined the "..playerFaction.faction.name.." faction!", type = "success"})
			TriggerEvent('eol_factions:server:joinedFaction', id, invitingMemberId, invitingPlayer.PlayerData.citizenid)
		end
	else
		TriggerClientEvent('ox_lib:notify', source, {description = "Person is already in a faction!", type = "error"})
	end
end

--- Process member kick
---@param source number
---@param player table
---@param kickingMemberId number
local function kickMember(source, player, kickingMemberId)
	if not source or not player or not kickingMemberId then return end

	if source == kickingMemberId then
		TriggerClientEvent('ox_lib:notify', source, {description = "You can't kick yourself!", type = "error"})
		return
	end

	local kickingPlayer = QBCore.Functions.GetPlayer(kickingMemberId)
	if not kickingPlayer then
		TriggerClientEvent('ox_lib:notify', source, {description = "This member appears to be asleep.", type = "error"})
		return
	end

	local playerFaction = factionStatus(source)
	local kickingFaction = factionStatus(kickingMemberId)

	if not playerFaction or not kickingFaction then
		TriggerClientEvent('ox_lib:notify', source, {description = ("%s not in a faction!"):format(not playerFaction and "You are" or "This person is"), type = "error"})
		return
	end

	if not hasMenuPermission('kick', playerFaction.user.factionrank) then return end

	if playerFaction.user.factionid ~= kickingFaction.user.factionid then
		TriggerClientEvent('ox_lib:notify', source, {description = "This person isn't in your faction!", type = "error"})
		return
	end

	if playerFaction.faction.ownerid == player.PlayerData.citizenid then
		-- kick anyone
		MySQL.query('DELETE FROM `eol_factionusers` WHERE `identifier` = ?', {kickingPlayer.PlayerData.citizenid})
		factions[kickingFaction.user.factionid].members[kickingPlayer.PlayerData.citizenid] = nil
		TriggerEvent('eol_factions:server:kickedFromFaction', kickingFaction.user.factionid, kickingMemberId, kickingPlayer.PlayerData.citizenid)
	else
		-- kick lesser
		if playerFaction.user.factionrank < kickingFaction.user.factionrank then
			MySQL.query('DELETE FROM `eol_factionusers` WHERE `identifier` = ?', {kickingPlayer.PlayerData.citizenid})
			factions[kickingFaction.user.factionid].members[kickingPlayer.PlayerData.citizenid] = nil
			TriggerEvent('eol_factions:server:kickedFromFaction', kickingFaction.user.factionid, kickingMemberId, kickingPlayer.PlayerData.citizenid)
		else
			TriggerClientEvent('ox_lib:notify', source, {description = "You are not a higher rank than this member!", type = "error"})
		end
	end
end

--- Process member promote
---@param source number
---@param player table
---@param promotingMemberId number
local function promoteMember(source, player, promotingMemberId)
	if not source or not player or not promotingMemberId then return end

	if source == promotingMemberId then
		TriggerClientEvent('ox_lib:notify', source, {description = "You can't promote yourself silly.", type = "error"})
		return
	end

	local promotingPlayer = QBCore.Functions.GetPlayer(promotingMemberId)
	if not promotingPlayer then
		TriggerClientEvent('ox_lib:notify', source, {description = "This member appears to be asleep.", type = "error"})
		return
	end

	local playerFaction = factionStatus(source)
	local promotingFaction = factionStatus(promotingMemberId)

	if not playerFaction or not promotingFaction then
		TriggerClientEvent('ox_lib:notify', source, {description = ("%s not in a faction!"):format(not playerFaction and "You are" or "This person is"), type = "error"})
		return
	end

	if not hasMenuPermission('promote', playerFaction.user.factionrank) then return end

	if playerFaction.user.factionid ~= promotingFaction.user.factionid then
		TriggerClientEvent('ox_lib:notify', source, {description = "This person isn't in your faction!", type = "error"})
		return
	end

	if promotingFaction.user.factionrank - 1 < 2 then
		TriggerClientEvent('ox_lib:notify', source, {description = "This person already has the highest rank!", type = "error"})
		return
	end

	if playerFaction.faction.ownerid == player.PlayerData.citizenid then
		factions[promotingFaction.user.factionid].members[promotingPlayer.PlayerData.citizenid].factionrank -= 1
		TriggerClientEvent('ox_lib:notify', source, {description = "Promoted member to Rank "..factions[promotingFaction.user.factionid].members[promotingPlayer.PlayerData.citizenid].factionrank, type = "success"})
		TriggerEvent('eol_factions:server:promotedInFaction', promotingFaction.user.factionid, promotingMemberId, promotingPlayer.PlayerData.citizenid)
	else
		if playerFaction.user.factionrank < promotingFaction.user.factionrank then
			factions[promotingFaction.user.factionid].members[promotingPlayer.PlayerData.citizenid].factionrank -= 1
			TriggerClientEvent('ox_lib:notify', source, {description = "Promoted member to Rank "..factions[promotingFaction.user.factionid].members[promotingPlayer.PlayerData.citizenid].factionrank, type = "success"})
			TriggerEvent('eol_factions:server:promotedInFaction', promotingFaction.user.factionid, promotingMemberId, promotingPlayer.PlayerData.citizenid)
		else
			TriggerClientEvent('ox_lib:notify', source, {description = "You are not a higher rank than this member!", type = "error"})
		end
	end
end

--- Process member demote
---@param source number
---@param player table
---@param demotingMemberId number
local function demoteMember(source, player, demotingMemberId)
	if not source or not player or not demotingMemberId then return end

	if source == demotingMemberId then
		TriggerClientEvent('ox_lib:notify', source, {description = "You can't demote yourself silly.", type = "error"})
		return
	end

	local demotingPlayer = QBCore.Functions.GetPlayer(demotingMemberId)
	if not demotingPlayer then
		TriggerClientEvent('ox_lib:notify', source, {description = "This member appears to be asleep.", type = "error"})
		return
	end

	local playerFaction = factionStatus(source)
	local demotingFaction = factionStatus(demotingMemberId)

	if not playerFaction or not demotingFaction then
		TriggerClientEvent('ox_lib:notify', source, {description = ("%s not in a faction!"):format(not playerFaction and "You are" or "This person is"), type = "error"})
		return
	end

	if not hasMenuPermission('demote', playerFaction.user.factionrank) then return end

	if playerFaction.user.factionid ~= demotingFaction.user.factionid then
		TriggerClientEvent('ox_lib:notify', source, {description = "This person isn't in your faction!", type = "error"})
		return
	end

	if playerFaction.faction.ownerid == player.PlayerData.citizenid then
		factions[demotingFaction.user.factionid].members[demotingPlayer.PlayerData.citizenid].factionrank += 1
		TriggerClientEvent('ox_lib:notify', source, {description = "Promoted member to Rank "..factions[demotingFaction.user.factionid].members[demotingPlayer.PlayerData.citizenid].factionrank, type = "success"})
		TriggerEvent('eol_factions:server:demotedInFaction', demotingFaction.user.factionid, demotingMemberId, demotingPlayer.PlayerData.citizenid)
	else
		if playerFaction.user.factionrank < demotingFaction.user.factionrank then
			factions[demotingFaction.user.factionid].members[demotingPlayer.PlayerData.citizenid].factionrank += 1
			TriggerClientEvent('ox_lib:notify', source, {description = "Demoted member to Rank "..factions[demotingFaction.user.factionid].members[demotingPlayer.PlayerData.citizenid].factionrank, type = "success"})
			TriggerEvent('eol_factions:server:demotedInFaction', demotingFaction.user.factionid, demotingMemberId, demotingPlayer.PlayerData.citizenid)
		else
			TriggerClientEvent('ox_lib:notify', source, {description = "You aren't a higher rank than this member!", type = "error"})
		end
	end
end

--- Process money deposit
---@param source number
---@param player table
---@param amount number
local function depositMoney(source, player, amount)
	if not source or not player or not amount then return end

	local fact = factionStatus(source)
	if not fact then
		TriggerClientEvent('ox_lib:notify', source, {description = "You are not in a faction!", type = "error"})
		return
	end

	if not hasMenuPermission('deposit', fact.user.factionrank) then return end

	if fact.faction.ownerid ~= player.PlayerData.citizenid then
		TriggerClientEvent('ox_lib:notify', source, {description = "You aren't the owner of your faction", type = "error"})
		return
	end

	exports['qb-management']:AddGangMoney(fact.faction.name, amount)
	TriggerClientEvent('ox_lib:notify', source, {description = ("Deposited %s money to the faction!"):format(amount), type = "success"})
	TriggerEvent('eol_factions:server:depositedMoney', fact.faction.id, source, player.PlayerData.citizenid, amount)
end

--- Process money withdrawal
---@param source number
---@param player table
---@param amount number
local function withdrawMoney(source, player, amount)
	if not source or not player or not amount then return end

	local fact = factionStatus(source)
	if not fact then
		TriggerClientEvent('ox_lib:notify', source, {description = "You are not in a faction!", type = "error"})
		return
	end

	if not hasMenuPermission('withdraw', fact.user.factionrank) then return end

	if fact.faction.ownerid ~= player.PlayerData.citizenid then
		TriggerClientEvent('ox_lib:notify', source, {description = "You aren't the owner of your faction", type = "error"})
		return
	end

	exports['qb-management']:RemoveGangMoney(fact.faction.name, amount)
	TriggerClientEvent('ox_lib:notify', source, {description = ("Withdrawn %s money from the faction!"):format(amount), type = "success"})
	TriggerEvent('eol_factions:server:withdrawnMoney', fact.faction.id, source, player.PlayerData.citizenid, amount)
end

--- Process faction claim
---@param source number
---@param fact table
---@param gridOwner number | nil
local function claimGrid(source, fact, gridOwner)
	if gridOwner and gridOwner == fact.faction.id then return end

	local coords = GetEntityCoords(GetPlayerPed(source))
	local grid = getCurrentGrid(coords)

	if gridOwner then
		-- claimed
		if canOverclaim(fact.faction.id, gridOwner) then
			setGridOwner(fact.faction.id, grid)
		else
			TriggerClientEvent('ox_lib:notify', source, {description = "Cannot overclaim this territory.", type = "error"})
		end
	else
		-- unclaimed
		setGridOwner(fact.faction.id, grid)
	end
end

exports('claimGrid', claimGrid)

--- Transfer ownership of a faction
---@param source number
---@param player any
---@param transferringId any
local function transferOwner(source, player, transferringId)
	if not source or not player or not transferringId then return end

	if source == transferringId then
		TriggerClientEvent('ox_lib:notify', source, {description = "You already own this faction!", type = "error"})
		return
	end

	local transferringPlayer = QBCore.Functions.GetPlayer(transferringId)
	if not transferringPlayer then
		TriggerClientEvent('ox_lib:notify', source, {description = "This member appears to be asleep.", type = "error"})
		return
	end

	local playerFaction = factionStatus(source)
	local transferingFaction = factionStatus(transferringId)

	if not playerFaction or not transferingFaction then
		TriggerClientEvent('ox_lib:notify', source, {description = ("%s not in a faction!"):format(not playerFaction and "You are" or "This person is"), type = "error"})
		return
	end

	if playerFaction.faction.ownerid ~= player.PlayerData.citizenid then return end

	if playerFaction.faction.id ~= transferingFaction.faction.id then
		TriggerClientEvent('ox_lib:notify', source, {description = "This person is not in your faction!", type = "error"})
		return
	end

	-- first change ranks
	factions[transferingFaction.user.factionid].members[transferringPlayer.PlayerData.citizenid].factionrank = 1
	factions[playerFaction.user.factionid].members[player.PlayerData.citizenid].factionrank = 2
	-- then change faction ownership
	factions[playerFaction.faction.id].ownerid = transferringPlayer.PlayerData.citizenid

	TriggerClientEvent('ox_lib:notify', source, {description = "You have transferred ownership of the faction!", type = "success"})
	TriggerClientEvent('ox_lib:notify', transferringId, {description = "You are now the owner of "..playerFaction.faction.name.."!", type = "success"})
	TriggerEvent('eol_factions:server:ownerTransfer', playerFaction.faction.id, transferringPlayer.PlayerData.citizenid, player.PlayerData.citizenid)
end

exports('transferOwner', transferOwner)

local function leaveFaction(source, player, faction)
	if not source or not player or not faction then return end

	if faction.faction.ownerid == player.PlayerData.citizenid then
		TriggerClientEvent('ox_lib:notify', source, {description = "You cannot leave a faction you own!", type = "error"})
		return
	end

	MySQL.query('DELETE FROM `eol_factionusers` WHERE `identifier` = ?', {player.PlayerData.citizenid})
	factions[faction.user.factionid].members[player.PlayerData.citizenid] = nil
	TriggerClientEvent('ox_lib:notify', source, {description = "You have left the faction.", type = "success"})
	TriggerEvent('eol_factions:server:leftFaction', faction.user.factionid, player.PlayerData.source, player.PlayerData.citizenid)
end

--#endregion Functions

--#region Events

RegisterNetEvent('eol_factions:server:procInputFeedback', function(dialog, title, amount)
	-- catch return from qb-input
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)

	if not Player or not dialog then return end

	for i = 1, amount do
		if dialog[i] then
			if title == "Name Your Faction" then
				createFaction(src, Player, cleanString(dialog[i], true))
			elseif title == "Invite Member" then
				dialog[i] = tonumber(dialog[i])
				if dialog[i] then
					inviteMember(src, Player, dialog[i])
				end
			elseif title == "Kick Member" then
				dialog[i] = tonumber(dialog[i])
				if dialog[i] then
					kickMember(src, Player, dialog[i])
				end
			elseif title == "Promote Member" then
				dialog[i] = tonumber(dialog[i])
				if dialog[i] then
					promoteMember(src, Player, dialog[i])
				end
			elseif title == "Demote Member" then
				dialog[i] = tonumber(dialog[i])
				if dialog[i] then
					demoteMember(src, Player, dialog[i])
				end
			elseif title == "Deposit Money" then
				dialog[i] = tonumber(dialog[i])
				if dialog[i] then
					depositMoney(src, Player, dialog[i])
				end
			elseif title == "Withdraw Money" then
				dialog[i] = tonumber(dialog[i])
				if dialog[i] then
					withdrawMoney(src, Player, dialog[i])
				end
			elseif title == "Transfer Faction Ownership" then
				dialog[i] = tonumber(dialog[i])
				if dialog[i] then
					transferOwner(src, Player, dialog[i])
				end
			end
		end
	end
end)

RegisterNetEvent('eol_factions:server:createFaction', function()
	-- catch client request to create faction
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)

	if not Player then return end

	-- make sure player is not in a faction and send qb-input dialog
	local faction = factionStatus(src)
	if not faction then
		-- player is not in faction
		TriggerClientEvent('eol_factions:client:openInput', src, "Name Your Faction", factNameInput)
	else
		-- player is in faction
		TriggerClientEvent('ox_lib:notify', src, {description = "You are already in a faction!", type = "error"})
	end
end)

RegisterNetEvent('eol_factions:server:inviteMember', function()
	-- player wants to invite member to their faction
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)

	if not Player then return end

	local faction = factionStatus(src)
	if faction then
		TriggerClientEvent('eol_factions:client:openInput', src, "Invite Member", playerIdInput)
	else
		TriggerClientEvent('ox_lib:notify', src, {description = "You are not in a faction!", type = "error"})
	end
end)

RegisterNetEvent('eol_factions:server:kickMember', function()
	-- player wants to kick member from their faction
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)

	if not Player then return end

	local faction = factionStatus(src)
	if faction then
		TriggerClientEvent('eol_factions:client:openInput', src, "Kick Member", playerIdInput)
	else
		TriggerClientEvent('ox_lib:notify', src, {description = "You are not in a faction!", type = "error"})
	end
end)

RegisterNetEvent('eol_factions:server:promoteMember', function()
	-- player wants to promote a member
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)

	if not Player then return end

	local faction = factionStatus(src)
	if faction then
		TriggerClientEvent('eol_factions:client:openInput', src, "Promote Member", playerIdInput)
	else
		TriggerClientEvent('ox_lib:notify', src, {description = "You are not in a faction!", type = "error"})
	end
end)

RegisterNetEvent('eol_factions:server:demoteMember', function()
	-- player wants to demote a member
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)

	if not Player then return end

	local faction = factionStatus(src)
	if faction then
		TriggerClientEvent('eol_factions:client:openInput', src, "Demote Member", playerIdInput)
	else
		TriggerClientEvent('ox_lib:notify', src, {description = "You are not in a faction!", type = "error"})
	end
end)

RegisterNetEvent('eol_factions:server:depositMoney', function()
	-- player wants to deposit money
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)

	if not Player then return end

	local faction = factionStatus(src)
	if faction then
		TriggerClientEvent('eol_factions:client:openInput', src, "Deposit Money", moneyInput)
	else
		TriggerClientEvent('ox_lib:notify', src, {description = "You are not in a faction!", type = "error"})
	end
end)

RegisterNetEvent('eol_factions:server:withdrawMoney', function()
	-- player wants to withdraw money
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)

	if not Player then return end

	local faction = factionStatus(src)
	if faction then
		TriggerClientEvent('eol_factions:client:openInput', src, "Withdraw Money", moneyInput)
	else
		TriggerClientEvent('ox_lib:notify', src, {description = "You are not in a faction!", type = "error"})
	end
end)

RegisterNetEvent('eol_factions:server:claimGrid', function()
	-- player wants to claim current grid
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)

	if not Player then return end

	local faction = factionStatus(src)
	if not faction then
		TriggerClientEvent('ox_lib:notify', src, {description = "You are not in a faction!", type = "error"})
		return
	end

	if not hasMenuPermission('claim', faction.user.factionrank) then return end

	local ped = GetPlayerPed(src)
	local coords = GetEntityCoords(ped)
	local gridOwner = getGridOwner(coords)

	if gridOwner and gridOwner == faction.faction.id then
		TriggerClientEvent('ox_lib:notify', src, {description = "Your faction already owns this territory!", type = "error"})
		return
	end

	claimGrid(src, faction, gridOwner)
	TriggerClientEvent('ox_lib:notify', src, {description = "Territory Claimed!", type = "success"})
end)

RegisterNetEvent('eol_factions:server:unclaimGrid', function()
	-- player wants to unclaim current grid
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)

	if not Player then return end

	local faction = factionStatus(src)
	if not faction then
		TriggerClientEvent('ox_lib:notify', src, {description = "You are not in a faction!", type = "error"})
		return
	end

	if not hasMenuPermission('unclaim', faction.user.factionrank) then return end

	local ped = GetPlayerPed(src)
	local coords = GetEntityCoords(ped)
	local gridOwner = getGridOwner(coords)
	local grid = getCurrentGrid(coords)

	if faction.faction.id ~= gridOwner then
		TriggerClientEvent('ox_lib:notify', src, {description = "Your faction doesn't own this territory!", type = "error"})
	else
		clearGridOwner(grid)
		TriggerClientEvent('ox_lib:notify', src, {description = "Territory Unclaimed!", type = "success"})
	end
end)

RegisterNetEvent('eol_factions:server:transferFaction', function()
	-- user wants to transfer their faction to another member
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)

	if not Player then return end

	local faction = factionStatus(src)
	if faction then
		TriggerClientEvent('eol_factions:client:openInput', src, "Transfer Faction Ownership", playerIdInput)
	else
		TriggerClientEvent('ox_lib:notify', src, {description = "You are not in a faction!", type = "error"})
	end
end)

RegisterNetEvent('eol_factions:server:leaveFaction', function()
	-- user wants to leave their faction
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)

	if not Player then return end

	local faction = factionStatus(src)
	if faction then
		leaveFaction(src, Player, faction)
	else
		TriggerClientEvent('ox_lib:notify', src, {description = "You are not in a faction!", type = "error"})
	end
end)

--#endregion Events

--#region Callbacks

lib.callback.register('eol_factions:server:areTheyInAFaction', function(source, other)
	return factionStatus(source) and factionStatus(other)
end)

lib.callback.register('eol_factions:server:deductPowerOnDeath', function(source)
	local playerFaction = factionStatus(source)
	if not playerFaction then return end

	factions[playerFaction.user.factionid].members[playerFaction.user.identifier].power -= PowerLossOnDeath
	TriggerEvent('eol_factions:server:lostPower', playerFaction.user.factionid, source, playerFaction.user.identifier, PowerLossOnDeath, factions[playerFaction.user.factionid].members[playerFaction.user.identifier].power, playerFaction.user.power)
	return true
end)

lib.callback.register('eol_factions:server:getGrids', function(source)
	local factStatus = factionStatus(source)
	if not factStatus then return end
	return getOwnedGrids(factStatus.faction.id)
end)

--#endregion Callbacks

--#region Commands

RegisterCommand('faction', function(source)
	-- add faction menu
	local Player = QBCore.Functions.GetPlayer(source)
	if not Player then return end

	for i = 1, #FactionJobBlacklist do
		if Player.PlayerData.job.name == FactionJobBlacklist[i] then
			TriggerClientEvent('ox_lib:notify', source, {description = "You're too professional to access this.", type = "error"})
			return
		end
	end

	local faction = factionStatus(source)
	if faction then
		-- in faction
		local menu = buildMenu(source)
		if not menu then return end
		TriggerClientEvent('eol_factions:client:openMenu', source, menu)
	else
		-- no faction
		TriggerClientEvent('eol_factions:client:openFactionlessMenu', source)
	end
end, false)

--#endregion Commands

--#region Threads

CreateThread(function()
	local success, result = pcall(MySQL.query.await, 'SELECT * FROM `eol_factions`')

	if not success then
		MySQL.query([[CREATE TABLE `eol_factions` (
			`id` INT(11) NOT NULL AUTO_INCREMENT,
			`name` LONGTEXT NOT NULL,
			`ownerid` VARCHAR(60) NOT NULL,
			PRIMARY KEY (`id`)
		)]])
	else
		for i = 1, #result do
			factions[result[i].id] = result[i]
			factions[result[i].id].members = {}
		end
	end

	success, result = pcall(MySQL.query.await, 'SELECT * FROM `eol_factionusers`')

	if not success then
		MySQL.query([[CREATE TABLE `eol_factionusers` (
			`identifier` VARCHAR(60) NULL DEFAULT NULL,
			`factionid` INT(11) NOT NULL,
			`factionrank` INT(11) NULL DEFAULT '1',
			`power` BIGINT(20) NULL DEFAULT '0',
			PRIMARY KEY (`identifier`)
		)]])
	else
		for i = 1, #result do
			factions[result[i].factionid].members[result[i].identifier] = result[i]
		end
	end

	success, result = pcall(MySQL.query.await, 'SELECT * FROM `eol_factionclaims`')

	if not success then
		MySQL.query([[CREATE TABLE `eol_factionclaims` (
			`claimedby` INT(11) DEFAULT NULL,
			`grid` VARCHAR(60) NOT NULL,
			PRIMARY KEY (`grid`)
		)]])
	else
		for i = 1, #result do
			grids[result[i].grid] = result[i]
		end
	end

	local factionQueries = {}
	local userQueries = {}
	local gridQueries = {}
	local waitingTime = SavingTime * 60000
	while true do
		Wait(waitingTime)

		for k, v in pairs(factions) do
			factionQueries[#factionQueries + 1] = {
				query = 'UPDATE `eol_factions` SET `name` = ?, `ownerid` = ? WHERE `id` = ?',
				values = {v.name, v.ownerid, k}
			}

			for k2, v2 in pairs(v.members) do
				userQueries[#userQueries + 1] = {
					query = 'UPDATE `eol_factionusers` SET `factionid` = ?, `factionrank` = ?, `power` = ? WHERE `identifier` = ?',
					values = {v2.factionid, v2.factionrank, v2.power, k2}
				}
			end
		end

		for k, v in pairs(grids) do
			gridQueries[#gridQueries + 1] = {
				query = 'UPDATE `eol_factionclaims` SET `claimedby` = ? WHERE `grid` = ?',
				values = {v.claimedby, k}
			}
		end

		local factionSuccess = MySQL.transaction.await(factionQueries)
		local userSuccess = MySQL.transaction.await(userQueries)
		local gridSuccess = MySQL.transaction.await(gridQueries)

		factionQueries = {}
		userQueries = {}
		gridQueries = {}

		if not factionSuccess or not userSuccess or not gridSuccess then
			error('Saving failed, shutting down loop which saves things until you fix it and restart the resource')
			return
		end
	end
end)

CreateThread(function()
	local waitingTime = TimeToGetPower * 60000
	while true do
		Wait(waitingTime)

		for i, data in pairs(factions) do
			for k in pairs(data.members) do
				local ply = QBCore.Functions.GetPlayerByCitizenId(k)
				if ply and factions[i].members[k].power < MaxPowerPerPlayer then
					local curStatus = factionStatus(ply.source)
					if curStatus then
						factions[i].members[k].power += PlayingTimePower
						TriggerEvent('eol_factions:server:gainedPower', i, ply.source, k, PlayingTimePower, factions[i].members[k].power, curStatus.user.power)
					end
				end
			end
		end
	end
end)

--#endregion Threads