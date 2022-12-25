local obj = Framework == 'ESX' and exports.es_extended:getSharedObject() or Framework == 'QB' and exports['qb-core']:GetCoreObject() or {}

function GetPlayer(source)
    if Framework == 'ESX' then
        return obj.GetPlayerFromId(source)
    elseif Framework == 'QB' then
        local player = obj.Functions.GetPlayer(source)
        player.identifier = player.PlayerData.citizenid
        player.source = player.PlayerData.source
        player.job = {
            name = player.PlayerData.job.name,
            grade = player.PlayerData.job.grade.level
        }
        return player
    end

    -- Make this your own implementation if you want to use a different identifier when not using the frameworks above
    local identifiers = GetPlayerIdentifiers(source)
    for i = 1, #identifiers do
        local identifier = identifiers[i]
        if identifier:find('license') then
            return {identifier = identifier, source = tonumber(source), job = ''}
        end
    end
end

function GetPlayerFromIdentifier(identifier)
    if Framework == 'ESX' then
        return obj.GetPlayerFromIdentifier(identifier)
    elseif Framework == 'QB' then
        local player = obj.Functions.GetPlayerByCitizenId(source)
        player.identifier = player.PlayerData.citizenid
        player.source = player.PlayerData.source
        return player
    end

    -- Make this your own implementation if you want to use a different way when not using the frameworks above
    local players = GetPlayers()
    for i = 1, #players do
        local source = players[i]
        local identifiers = GetPlayerIdentifiers(source)
        for i2 = 1, #identifiers do
            local curIdentifier = identifiers[i2]
            if curIdentifier:find('license') and curIdentifier == identifier then
                return {identifier = curIdentifier, source = tonumber(source)}
            end
        end
    end
end

function GetFactionBalance(faction)
    if Framework == 'QB' then
        return exports['qb-management']:GetGangAccount(faction)
    elseif Framework == 'ESX' then
        local result = promise.new()
        TriggerEvent('esx_addonaccount:getSharedAccount', faction, function(account)
            result:resolve(account?.money)
        end)
        return Citizen.Await(result)
    end

    -- For standalone, nothing implemented yet
    return 0
end

function AddFactionMoney(faction, amount)
    if Framework == 'QB' then
        return exports['qb-management']:AddGangMoney(faction, amount)
    elseif Framework == 'ESX' then
        return
    end

    -- For standalone, nothing implemented yet
    return
end

function RemoveFactionMoney(faction, amount)
    if Framework == 'QB' then
        return exports['qb-management']:RemoveGangMoney(faction, amount)
    elseif Framework == 'ESX' then
        return
    end

    -- For standalone, nothing implemented yet
    return
end