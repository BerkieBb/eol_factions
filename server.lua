---@type table<number, Faction>
local factions = {}
---@type table<string, Grid>
local grids = {}

---@class Grid
---@field grid string
---@field claimedby number?

---@class Faction
---@field name string
---@field ownerid string?
---@field user Member? Only used for getting the faction internally
---@field id number
---@field money number
---@field members table<string, Member>

---@class Member
---@field identifier string
---@field factionid number
---@field factionrank number
---@field power number

--#region Input Layouts

local factNameInput = {
	{
		type = 'input', -- type of the input
		label = 'Faction Name', -- text you want to display above the input field
		placeholder = 'Santa Claus', -- text you want to be displayed as a place holder
	},
}

local playerIdInput = {
	{
		type = 'number', -- type of the input
		label = 'Player ID', -- text you want to be displayed as a place holder
		default = 1, -- the default number to show
	},
}

local moneyInput = {
	{
		type = 'number', -- type of the input
		label = 'Amount Of Money', -- text you want to be displayed as a place holder
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

---@param src number
---@return string
local function getPlayerIdentifier(src)
    return GetPlayerIdentifierByType(src --[[@as string]], 'license2') or GetPlayerIdentifierByType(src --[[@as string]], 'license')
end

---@param identifier string
---@return number?
local function getSourceFromIdentifier(identifier)
    local players = GetPlayers()
    for i = 1, #players do
        local src = tonumber(players[i]) --[[@as number]]
        local id = getPlayerIdentifier(src)
        if id == identifier then
            return src
        end
    end
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
	return vec2(makeGridValue(coords.x), makeGridValue(coords.y))
end

exports('getCurrentGrid', getCurrentGrid)

--- Get the owner of a grid
---@param coords vector2 | vector3 | vector4
---@return number?
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
---@param id number
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
---@param id number
---@return vector2[]?
local function getOwnedGrids(id)
	local claimed = {}
	for _, v in pairs(grids) do
		if id == v.claimedby then
			local grid = {}
			for i in string.gmatch(v.grid, '([^:]+)') do
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
local function canOverclaim(overtakingFactionId, otherFactionId)
	local overtakingPower = getFactionPower(overtakingFactionId)
	local otherPower = getFactionPower(otherFactionId)

	local overtakingTurfCount = getFactionClaims(overtakingFactionId)
	local otherTurfCount = getFactionClaims(otherFactionId)

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
---@param src number
---@return Faction?
local function factionStatus(src)
	local identifier = getPlayerIdentifier(src)
	for _, v in pairs(factions) do
		if v.members[identifier] then
			v.user = v.members[identifier]

			return v
		end
	end
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
---@param src number
---@return table?
local function buildMenu(src)
	local identifier = getPlayerIdentifier(src)
	local faction = factionStatus(src)
	local ped = GetPlayerPed(src)
	local coords = GetEntityCoords(ped)
	local gridOwner = getGridOwner(coords)
	if not identifier or not faction then return end

	local claims = getFactionClaims(faction.id)
	local power = getFactionPower(faction.id)
	local totalPower = totalFactionPower(faction.id)

	local gridOwnerHeader = 'Territory Not Yours'
	if gridOwner == faction.id then
		gridOwnerHeader = 'Territory Owned By You'
	end

	local menu = {
		id = 'eol_factions_manage_faction_server',
		title = ('%s | Rank: %s | Claims: %s | Power: %s | Max Power: %s | Balance: %s | %s'):format(faction.name, faction.user.factionrank, claims, power, totalPower, faction.money, gridOwnerHeader),
		options = {}
	}

	if hasMenuPermission('invite', faction.user.factionrank) then
		menu.options[#menu.options + 1] = {
			title = 'Invite Member',
			description = 'Invite a member to the faction',
			serverEvent = 'eol_factions:server:inviteMember'
		}
	end

	if hasMenuPermission('kick', faction.user.factionrank) then
		menu.options[#menu.options + 1] = {
			title = 'Kick Member',
			description = 'Kick a member from the faction',
			serverEvent = 'eol_factions:server:kickMember'
		}
	end

	if hasMenuPermission('promote', faction.user.factionrank) then
		menu.options[#menu.options + 1] = {
			title = 'Promote Member',
			description = 'Promote a faction member',
			serverEvent = 'eol_factions:server:promoteMember'
		}
	end

	if hasMenuPermission('demote', faction.user.factionrank) then
		menu.options[#menu.options + 1] = {
			title = 'Demote Member',
			description = 'Demote a faction member',
			serverEvent = 'eol_factions:server:demoteMember'
		}
	end

	if hasMenuPermission('deposit', faction.user.factionrank) then
		menu.options[#menu.options + 1] = {
			title = 'Deposit Money',
			description = 'Deposit money for the faction to use',
			serverEvent = 'eol_factions:server:depositMoney'
		}
	end

	if hasMenuPermission('withdraw', faction.user.factionrank) then
		menu.options[#menu.options + 1] = {
			title = 'Withdraw Money',
			description = 'Withdraw money from the faction',
			serverEvent = 'eol_factions:server:withdrawMoney'
		}
	end

	if gridOwner ~= faction.id and hasMenuPermission('claim', faction.user.factionrank) then
		menu.options[#menu.options + 1] = {
			title = 'Claim Territory',
			description = 'Claim the territory you are in',
			serverEvent = 'eol_factions:server:claimGrid'
		}
	elseif gridOwner == faction.id and hasMenuPermission('unclaim', faction.user.factionrank) then
		menu.options[#menu.options + 1] = {
			title = 'Unclaim Territory',
			description = 'Unclaim the territory you are in',
			serverEvent = 'eol_factions:server:unclaimGrid'
		}
	end

	if faction.ownerid == identifier then
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
---@param src number
---@param identifier string
---@param factionName string
local function createFaction(src, identifier, factionName)
	if not identifier or not factionName then return end

	for _, v in pairs(factions) do
		if v.name == factionName then
			TriggerClientEvent('ox_lib:notify', src, {description = ('A faction with name %s already exists, choose a different name'):format(factionName), type = 'error'})
			return
		end
	end

	local id = MySQL.insert.await('INSERT INTO `eol_factions` (`name`, `ownerid`) VALUES (?, ?) ', {factionName, identifier})
	if not id then return end

	local plyrFact = MySQL.insert.await('INSERT INTO `eol_factionusers` (`identifier`, `factionid`, `power`) VALUES (?, ?, ?) ', {identifier, id, StartingPower})
	if not plyrFact then return end

	factions[id] = {
		name = factionName,
		ownerid = identifier,
		id = id,
		money = 0,
		members = {
			[identifier] = {
				identifier = identifier,
				factionid = id,
				factionrank = 1,
				power = StartingPower
			}
		}
	}

	-- success, reopen player menu

	TriggerClientEvent('ox_lib:notify', src, {description = 'You created a faction!', type = 'success'})
	TriggerEvent('eol_factions:server:factionCreated', id, src, identifier)

	local menu = buildMenu(src)
	if not menu then return end

	TriggerClientEvent('eol_factions:client:openMenu', src, menu)
end

--- Process member invite
---@param src number
---@param identifier string
---@param invitingMemberId number
local function inviteMember(src, identifier, invitingMemberId)
	if not src or not identifier or not invitingMemberId then return end

	if src == invitingMemberId then
		TriggerClientEvent('ox_lib:notify', src, {description = 'You can\'t invite yourself!', type = 'error'})
		return
	end

	local playerPed = GetPlayerPed(src)
	local invitingPed = GetPlayerPed(invitingMemberId)
	if invitingPed == 0 then
		TriggerClientEvent('ox_lib:notify', src, {description = 'Invalid Person!', type = 'error'})
		return
	end

	local playerCoords = GetEntityCoords(playerPed)
	local invitingCoords = GetEntityCoords(invitingPed)

	if #(playerCoords - invitingCoords) > 20 then
		TriggerClientEvent('ox_lib:notify', src, {description = 'You\'re too far from this person!', type = 'error'})
		return
	end

	local playerFaction = factionStatus(src)
	local invitingFaction = factionStatus(invitingMemberId)
	if not playerFaction or not hasMenuPermission('invite', playerFaction.user.factionrank) then return end

	if playerFaction and not invitingFaction then
		local invitingIdentifier = getPlayerIdentifier(invitingMemberId)
		local result = MySQL.insert.await('INSERT INTO `eol_factionusers` (`identifier`, `factionid`, `factionrank`, `power`) VALUES (?, ?, ?, ?) ', {invitingIdentifier, playerFaction.id, playerFaction.user.factionrank + 1, StartingPower})
		if result then
			factions[id].members[invitingIdentifier] = {
				identifier = invitingIdentifier,
				factionid = playerFaction.id,
				factionrank = playerFaction.user.factionrank + 1,
				power = StartingPower
			}
			TriggerClientEvent('ox_lib:notify', src, {description = 'Person joined your faction!', type = 'success'})
			TriggerClientEvent('ox_lib:notify', invitingMemberId, {description = 'You joined the '..playerFaction.name..' faction!', type = 'success'})
			TriggerEvent('eol_factions:server:joinedFaction', id, invitingMemberId, invitingIdentifier)
		end
	else
		TriggerClientEvent('ox_lib:notify', src, {description = 'Person is already in a faction!', type = 'error'})
	end
end

--- Process member kick
---@param src number
---@param identifier string
---@param kickingMemberId number
local function kickMember(src, identifier, kickingMemberId)
	if not src or not identifier or not kickingMemberId then return end

	if src == kickingMemberId then
		TriggerClientEvent('ox_lib:notify', src, {description = 'You can\'t kick yourself!', type = 'error'})
		return
	end

	local kickingIdentifier = getPlayerIdentifier(kickingMemberId)
	if not kickingIdentifier or kickingIdentifier == '' then
		TriggerClientEvent('ox_lib:notify', src, {description = 'This member appears to be asleep.', type = 'error'})
		return
	end

	local playerFaction = factionStatus(src)
	local kickingFaction = factionStatus(kickingMemberId)
	if not playerFaction or not kickingFaction then
		TriggerClientEvent('ox_lib:notify', src, {description = ('%s not in a faction!'):format(not playerFaction and 'You are' or 'This person is'), type = 'error'})
		return
	end

	if not hasMenuPermission('kick', playerFaction.user.factionrank) then return end

	if playerFaction.user.factionid ~= kickingFaction.user.factionid then
		TriggerClientEvent('ox_lib:notify', src, {description = 'This person isn\'t in your faction!', type = 'error'})
		return
	end

	if playerFaction.ownerid == identifier then
		-- kick anyone
		MySQL.query('DELETE FROM `eol_factionusers` WHERE `identifier` = ?', {kickingIdentifier})
		factions[kickingFaction.user.factionid].members[kickingIdentifier] = nil
		TriggerEvent('eol_factions:server:kickedFromFaction', kickingFaction.user.factionid, kickingMemberId, kickingIdentifier)
	else
		-- kick lesser
		if playerFaction.user.factionrank < kickingFaction.user.factionrank then
			MySQL.query('DELETE FROM `eol_factionusers` WHERE `identifier` = ?', {kickingIdentifier})
			factions[kickingFaction.user.factionid].members[kickingIdentifier] = nil
			TriggerEvent('eol_factions:server:kickedFromFaction', kickingFaction.user.factionid, kickingMemberId, kickingIdentifier)
		else
			TriggerClientEvent('ox_lib:notify', src, {description = 'You are not a higher rank than this member!', type = 'error'})
		end
	end
end

--- Process member promote
---@param src number
---@param identifier string
---@param promotingMemberId number
local function promoteMember(src, identifier, promotingMemberId)
	if not src or not identifier or not promotingMemberId then return end

	if src == promotingMemberId then
		TriggerClientEvent('ox_lib:notify', src, {description = 'You can\'t promote yourself silly.', type = 'error'})
		return
	end

	local promotingIdentifier = getPlayerIdentifier(promotingMemberId)
	if not promotingIdentifier or promotingIdentifier == '' then
		TriggerClientEvent('ox_lib:notify', src, {description = 'This member appears to be asleep.', type = 'error'})
		return
	end

	local playerFaction = factionStatus(src)
	local promotingFaction = factionStatus(promotingMemberId)
	if not playerFaction or not promotingFaction then
		TriggerClientEvent('ox_lib:notify', src, {description = ('%s not in a faction!'):format(not playerFaction and 'You are' or 'This person is'), type = 'error'})
		return
	end

	if not hasMenuPermission('promote', playerFaction.user.factionrank) then return end

	if playerFaction.user.factionid ~= promotingFaction.user.factionid then
		TriggerClientEvent('ox_lib:notify', src, {description = 'This person isn\'t in your faction!', type = 'error'})
		return
	end

	if promotingFaction.user.factionrank - 1 < 2 then
		TriggerClientEvent('ox_lib:notify', src, {description = 'This person already has the highest rank!', type = 'error'})
		return
	end

	if playerFaction.ownerid == identifier then
		factions[promotingFaction.user.factionid].members[promotingIdentifier].factionrank -= 1
		TriggerClientEvent('ox_lib:notify', src, {description = 'Promoted member to Rank '..factions[promotingFaction.user.factionid].members[promotingIdentifier].factionrank, type = 'success'})
		TriggerEvent('eol_factions:server:promotedInFaction', promotingFaction.user.factionid, promotingMemberId, promotingIdentifier)
	else
		if playerFaction.user.factionrank < promotingFaction.user.factionrank then
			factions[promotingFaction.user.factionid].members[promotingIdentifier].factionrank -= 1
			TriggerClientEvent('ox_lib:notify', src, {description = 'Promoted member to Rank '..factions[promotingFaction.user.factionid].members[promotingIdentifier].factionrank, type = 'success'})
			TriggerEvent('eol_factions:server:promotedInFaction', promotingFaction.user.factionid, promotingMemberId, promotingIdentifier)
		else
			TriggerClientEvent('ox_lib:notify', src, {description = 'You are not a higher rank than this member!', type = 'error'})
		end
	end
end

--- Process member demote
---@param src number
---@param identifier string
---@param demotingMemberId number
local function demoteMember(src, identifier, demotingMemberId)
	if not src or not identifier or not demotingMemberId then return end

	if src == demotingMemberId then
		TriggerClientEvent('ox_lib:notify', src, {description = 'You can\'t demote yourself silly.', type = 'error'})
		return
	end

	local demotingIdentifier = getPlayerIdentifier(demotingMemberId)
	if not demotingIdentifier or demotingIdentifier == '' then
		TriggerClientEvent('ox_lib:notify', src, {description = 'This member appears to be asleep.', type = 'error'})
		return
	end

	local playerFaction = factionStatus(src)
	local demotingFaction = factionStatus(demotingMemberId)
	if not playerFaction or not demotingFaction then
		TriggerClientEvent('ox_lib:notify', src, {description = ('%s not in a faction!'):format(not playerFaction and 'You are' or 'This person is'), type = 'error'})
		return
	end

	if not hasMenuPermission('demote', playerFaction.user.factionrank) then return end

	if playerFaction.user.factionid ~= demotingFaction.user.factionid then
		TriggerClientEvent('ox_lib:notify', src, {description = 'This person isn\'t in your faction!', type = 'error'})
		return
	end

	if playerFaction.ownerid == identifier then
		factions[demotingFaction.user.factionid].members[demotingIdentifier].factionrank += 1
		TriggerClientEvent('ox_lib:notify', src, {description = 'Promoted member to Rank '..factions[demotingFaction.user.factionid].members[demotingIdentifier].factionrank, type = 'success'})
		TriggerEvent('eol_factions:server:demotedInFaction', demotingFaction.user.factionid, demotingMemberId, demotingIdentifier)
	else
		if playerFaction.user.factionrank < demotingFaction.user.factionrank then
			factions[demotingFaction.user.factionid].members[demotingIdentifier].factionrank += 1
			TriggerClientEvent('ox_lib:notify', src, {description = 'Demoted member to Rank '..factions[demotingFaction.user.factionid].members[demotingIdentifier].factionrank, type = 'success'})
			TriggerEvent('eol_factions:server:demotedInFaction', demotingFaction.user.factionid, demotingMemberId, demotingIdentifier)
		else
			TriggerClientEvent('ox_lib:notify', src, {description = 'You aren\'t a higher rank than this member!', type = 'error'})
		end
	end
end

--- Process money deposit
---@param src number
---@param identifier string
---@param amount number
local function depositMoney(src, identifier, amount)
	if not src or not identifier or not amount then return end

	local faction = factionStatus(src)
	if not faction then
		TriggerClientEvent('ox_lib:notify', src, {description = 'You are not in a faction!', type = 'error'})
		return
	end

	if not hasMenuPermission('deposit', faction.user.factionrank) then return end

	if faction.ownerid ~= identifier then
		TriggerClientEvent('ox_lib:notify', src, {description = 'You aren\'t the owner of your faction', type = 'error'})
		return
	end

	if GetPlayerMoney(src) < amount then
		TriggerClientEvent('ox_lib:notify', src, {description = 'You don\'t have enough money to deposit to the faction', type = 'error'})
		return
	end

	RemovePlayerMoney(src, amount)
	factions[faction.id].money += amount
	TriggerClientEvent('ox_lib:notify', src, {description = ('Deposited %s money to the faction!'):format(amount), type = 'success'})
	TriggerEvent('eol_factions:server:depositedMoney', faction.id, src, identifier, amount)
end

--- Process money withdrawal
---@param src number
---@param identifier string
---@param amount number
local function withdrawMoney(src, identifier, amount)
	if not src or not identifier or not amount then return end

	local faction = factionStatus(src)
	if not faction then
		TriggerClientEvent('ox_lib:notify', src, {description = 'You are not in a faction!', type = 'error'})
		return
	end

	if not hasMenuPermission('withdraw', faction.user.factionrank) then return end

	if faction.ownerid ~= identifier then
		TriggerClientEvent('ox_lib:notify', src, {description = 'You aren\'t the owner of your faction', type = 'error'})
		return
	end

	if faction.money < amount then
		TriggerClientEvent('ox_lib:notify', src, {description = 'The faction doesn\'t have enough money to withdraw money', type = 'error'})
		return
	end

	factions[faction.id].money -= amount
	AddPlayerMoney(src, amount)
	TriggerClientEvent('ox_lib:notify', src, {description = ('Withdrawn %s money from the faction!'):format(amount), type = 'success'})
	TriggerEvent('eol_factions:server:withdrawnMoney', faction.id, src, identifier, amount)
end

--- Process faction claim
---@param src number
---@param faction Faction
---@param gridOwner number?
local function claimGrid(src, faction, gridOwner)
	if gridOwner and gridOwner == faction.id then return end

	local coords = GetEntityCoords(GetPlayerPed(src))
	local grid = getCurrentGrid(coords)
	if gridOwner then
		-- claimed
		if canOverclaim(faction.id, gridOwner) then
			setGridOwner(faction.id, grid)
		else
			TriggerClientEvent('ox_lib:notify', src, {description = 'Cannot overclaim this territory.', type = 'error'})
		end
	else
		-- unclaimed
		setGridOwner(faction.id, grid)
	end
end

exports('claimGrid', claimGrid)

--- Transfer ownership of a faction
---@param src number
---@param identifier string
---@param transferringId number
local function transferOwner(src, identifier, transferringId)
	if not src or not identifier or not transferringId then return end

	if src == transferringId then
		TriggerClientEvent('ox_lib:notify', src, {description = 'You already own this faction!', type = 'error'})
		return
	end

	local transferringIdentifier = getPlayerIdentifier(transferringId)
	if not transferringIdentifier or transferringIdentifier == '' then
		TriggerClientEvent('ox_lib:notify', src, {description = 'This member appears to be asleep.', type = 'error'})
		return
	end

	local playerFaction = factionStatus(src)
	local transferingFaction = factionStatus(transferringId)
	if not playerFaction or not transferingFaction then
		TriggerClientEvent('ox_lib:notify', src, {description = ('%s not in a faction!'):format(not playerFaction and 'You are' or 'This person is'), type = 'error'})
		return
	end

	if playerFaction.ownerid ~= identifier then return end

	if playerFaction.id ~= transferingFaction.id then
		TriggerClientEvent('ox_lib:notify', src, {description = 'This person is not in your faction!', type = 'error'})
		return
	end

	-- first change ranks
	factions[transferingFaction.user.factionid].members[transferringIdentifier].factionrank = 1
	factions[playerFaction.user.factionid].members[identifier].factionrank = 2
	-- then change faction ownership
	factions[playerFaction.id].ownerid = transferringIdentifier

	TriggerClientEvent('ox_lib:notify', src, {description = 'You have transferred ownership of the faction!', type = 'success'})
	TriggerClientEvent('ox_lib:notify', transferringId, {description = 'You are now the owner of '..playerFaction.name..'!', type = 'success'})
	TriggerEvent('eol_factions:server:ownerTransfer', playerFaction.id, transferringIdentifier, identifier)
end

exports('transferOwner', transferOwner)

---@param src number
---@param identifier string
---@param faction Faction
local function leaveFaction(src, identifier, faction)
	if not src or not identifier or not faction then return end

	if faction.ownerid == identifier then
		TriggerClientEvent('ox_lib:notify', src, {description = 'You cannot leave a faction you own!', type = 'error'})
		return
	end

	MySQL.query.await('DELETE FROM `eol_factionusers` WHERE `identifier` = ?', {identifier})
	factions[faction.user.factionid].members[identifier] = nil
	TriggerClientEvent('ox_lib:notify', src, {description = 'You have left the faction.', type = 'success'})
	TriggerEvent('eol_factions:server:leftFaction', faction.user.factionid, src, identifier)
end

--#endregion Functions

--#region Events

RegisterNetEvent('eol_factions:server:procInputFeedback', function(dialog, title, amount)
	-- catch return from input
	local src = source
	local identifier = getPlayerIdentifier(src)
	if not dialog then return end

	for i = 1, amount do
		if dialog[i] then
			if title == 'Name Your Faction' then
				createFaction(src, identifier, cleanString(dialog[i], true))
			elseif title == 'Invite Member' then
				dialog[i] = tonumber(dialog[i])
				if dialog[i] then
					inviteMember(src, identifier, dialog[i])
				end
			elseif title == 'Kick Member' then
				dialog[i] = tonumber(dialog[i])
				if dialog[i] then
					kickMember(src, identifier, dialog[i])
				end
			elseif title == 'Promote Member' then
				dialog[i] = tonumber(dialog[i])
				if dialog[i] then
					promoteMember(src, identifier, dialog[i])
				end
			elseif title == 'Demote Member' then
				dialog[i] = tonumber(dialog[i])
				if dialog[i] then
					demoteMember(src, identifier, dialog[i])
				end
			elseif title == 'Deposit Money' then
				dialog[i] = tonumber(dialog[i])
				if dialog[i] then
					depositMoney(src, identifier, dialog[i])
				end
			elseif title == 'Withdraw Money' then
				dialog[i] = tonumber(dialog[i])
				if dialog[i] then
					withdrawMoney(src, identifier, dialog[i])
				end
			elseif title == 'Transfer Faction Ownership' then
				dialog[i] = tonumber(dialog[i])
				if dialog[i] then
					transferOwner(src, identifier, dialog[i])
				end
			end
		end
	end
end)

RegisterNetEvent('eol_factions:server:createFaction', function()
	-- catch client request to create faction
	local src = source
	-- make sure player is not in a faction and send qb-input dialog
	local faction = factionStatus(src)
	if not faction then
		-- player is not in faction
		TriggerClientEvent('eol_factions:client:openInput', src, 'Name Your Faction', factNameInput)
	else
		-- player is in faction
		TriggerClientEvent('ox_lib:notify', src, {description = 'You are already in a faction!', type = 'error'})
	end
end)

RegisterNetEvent('eol_factions:server:inviteMember', function()
	-- player wants to invite member to their faction
	local src = source
	local faction = factionStatus(src)
	if faction then
		TriggerClientEvent('eol_factions:client:openInput', src, 'Invite Member', playerIdInput)
	else
		TriggerClientEvent('ox_lib:notify', src, {description = 'You are not in a faction!', type = 'error'})
	end
end)

RegisterNetEvent('eol_factions:server:kickMember', function()
	-- player wants to kick member from their faction
	local src = source
	local faction = factionStatus(src)
	if faction then
		TriggerClientEvent('eol_factions:client:openInput', src, 'Kick Member', playerIdInput)
	else
		TriggerClientEvent('ox_lib:notify', src, {description = 'You are not in a faction!', type = 'error'})
	end
end)

RegisterNetEvent('eol_factions:server:promoteMember', function()
	-- player wants to promote a member
	local src = source
	local faction = factionStatus(src)
	if faction then
		TriggerClientEvent('eol_factions:client:openInput', src, 'Promote Member', playerIdInput)
	else
		TriggerClientEvent('ox_lib:notify', src, {description = 'You are not in a faction!', type = 'error'})
	end
end)

RegisterNetEvent('eol_factions:server:demoteMember', function()
	-- player wants to demote a member
	local src = source
	local faction = factionStatus(src)
	if faction then
		TriggerClientEvent('eol_factions:client:openInput', src, 'Demote Member', playerIdInput)
	else
		TriggerClientEvent('ox_lib:notify', src, {description = 'You are not in a faction!', type = 'error'})
	end
end)

RegisterNetEvent('eol_factions:server:depositMoney', function()
	-- player wants to deposit money
	local src = source
	local faction = factionStatus(src)
	if faction then
		TriggerClientEvent('eol_factions:client:openInput', src, 'Deposit Money', moneyInput)
	else
		TriggerClientEvent('ox_lib:notify', src, {description = 'You are not in a faction!', type = 'error'})
	end
end)

RegisterNetEvent('eol_factions:server:withdrawMoney', function()
	-- player wants to withdraw money
	local src = source
	local faction = factionStatus(src)
	if faction then
		TriggerClientEvent('eol_factions:client:openInput', src, 'Withdraw Money', moneyInput)
	else
		TriggerClientEvent('ox_lib:notify', src, {description = 'You are not in a faction!', type = 'error'})
	end
end)

RegisterNetEvent('eol_factions:server:claimGrid', function()
	-- player wants to claim current grid
	local src = source
	local faction = factionStatus(src)
	if not faction then
		TriggerClientEvent('ox_lib:notify', src, {description = 'You are not in a faction!', type = 'error'})
		return
	end

	if not hasMenuPermission('claim', faction.user.factionrank) then return end

	local ped = GetPlayerPed(src)
	local coords = GetEntityCoords(ped)
	local gridOwner = getGridOwner(coords)

	if gridOwner and gridOwner == faction.id then
		TriggerClientEvent('ox_lib:notify', src, {description = 'Your faction already owns this territory!', type = 'error'})
		return
	end

	claimGrid(src, faction, gridOwner)
	TriggerClientEvent('ox_lib:notify', src, {description = 'Territory Claimed!', type = 'success'})
end)

RegisterNetEvent('eol_factions:server:unclaimGrid', function()
	-- player wants to unclaim current grid
	local src = source
	local faction = factionStatus(src)
	if not faction then
		TriggerClientEvent('ox_lib:notify', src, {description = 'You are not in a faction!', type = 'error'})
		return
	end

	if not hasMenuPermission('unclaim', faction.user.factionrank) then return end

	local ped = GetPlayerPed(src)
	local coords = GetEntityCoords(ped)
	local gridOwner = getGridOwner(coords)
	local grid = getCurrentGrid(coords)

	if faction.id ~= gridOwner then
		TriggerClientEvent('ox_lib:notify', src, {description = 'Your faction doesn\'t own this territory!', type = 'error'})
	else
		clearGridOwner(grid)
		TriggerClientEvent('ox_lib:notify', src, {description = 'Territory Unclaimed!', type = 'success'})
	end
end)

RegisterNetEvent('eol_factions:server:transferFaction', function()
	-- user wants to transfer their faction to another member
	local src = source
	local faction = factionStatus(src)
	if faction then
		TriggerClientEvent('eol_factions:client:openInput', src, 'Transfer Faction Ownership', playerIdInput)
	else
		TriggerClientEvent('ox_lib:notify', src, {description = 'You are not in a faction!', type = 'error'})
	end
end)

RegisterNetEvent('eol_factions:server:leaveFaction', function()
	-- user wants to leave their faction
	local src = source
	local identifier = getPlayerIdentifier(src)
	local faction = factionStatus(src)
	if faction then
		leaveFaction(src, identifier, faction)
	else
		TriggerClientEvent('ox_lib:notify', src, {description = 'You are not in a faction!', type = 'error'})
	end
end)

--#endregion Events

--#region Callbacks

lib.callback.register('eol_factions:server:areTheyInAFaction', function(src, other)
	return factionStatus(src) and factionStatus(other)
end)

lib.callback.register('eol_factions:server:deductPowerOnDeath', function(src)
	local playerFaction = factionStatus(src)
	if not playerFaction then return end

	factions[playerFaction.user.factionid].members[playerFaction.user.identifier].power -= PowerLossOnDeath
	TriggerEvent('eol_factions:server:lostPower', playerFaction.user.factionid, src, playerFaction.user.identifier, PowerLossOnDeath, factions[playerFaction.user.factionid].members[playerFaction.user.identifier].power, playerFaction.user.power)

	return true
end)

lib.callback.register('eol_factions:server:getGrids', function(src)
	local faction = factionStatus(src)
	if not faction then return end

	return getOwnedGrids(faction.id)
end)

--#endregion Callbacks

--#region Commands

RegisterCommand('faction', function(src)
	-- add faction menu
	local faction = factionStatus(src)
	if faction then
		-- in faction
		local menu = buildMenu(src)
		if not menu then return end

		TriggerClientEvent('eol_factions:client:openMenu', src, menu)
	else
		-- no faction
		TriggerClientEvent('eol_factions:client:openFactionlessMenu', src)
	end
end, false)

--#endregion Commands

--#region Threads

CreateThread(function()
	local success, result = pcall(MySQL.query.await, 'SELECT * FROM `eol_factions`')
	if not success then
		error('Couldn\'t fetch from eol_factions table, are you sure this table has been created?')
		StopResource(GetCurrentResourceName())
		return
	else
		for i = 1, #result do
			factions[result[i].id] = result[i]
			factions[result[i].id].members = {}
		end
	end

	success, result = pcall(MySQL.query.await, 'SELECT * FROM `eol_factionusers`')
	if not success then
		error('Couldn\'t fetch from eol_factionusers table, are you sure this table has been created?')
		StopResource(GetCurrentResourceName())
		return
	else
		for i = 1, #result do
			factions[result[i].factionid].members[result[i].identifier] = result[i]
		end
	end

	success, result = pcall(MySQL.query.await, 'SELECT * FROM `eol_factionclaims`')
	if not success then
		error('Couldn\'t fetch from eol_factionclaims table, are you sure this table has been created?')
		StopResource(GetCurrentResourceName())
		return
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
			error('Saving failed, shutting down loop which saves everything until you fix it and restart the resource')
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
				local src = getSourceFromIdentifier(k)
				if src and factions[i].members[k].power < MaxPowerPerPlayer then
					local curStatus = factionStatus(src)
					if curStatus then
						factions[i].members[k].power += PlayingTimePower
						TriggerEvent('eol_factions:server:gainedPower', i, src, k, PlayingTimePower, factions[i].members[k].power, curStatus.user.power)
					end
				end
			end
		end
	end
end)

--#endregion Threads