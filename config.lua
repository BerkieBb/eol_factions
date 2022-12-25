SavingTime = 10 -- The amount of minutes it takes to save all factions, this loops

Framework = 'QB' -- 'ESX', 'QB', anything else will result in standalone being applied, which means you have to edit the framework.lua to adjust to get your desired identifier or leave it as is which is the license

FactionJobBlacklist = { -- The jobs that can't use the /faction command
    'police',
    'ambulance'
}

MaxPowerPerPlayer = 100 -- The maximum amount of power one player can acquire inside a faction
StartingPower = 0 -- The amount of power to start with when joining a faction
PowerLossOnDeath = 2 -- The amount of power to remove if you die
TimeToGetPower = 5 -- The amount of minutes it takes for someone to gain their playing time power
PlayingTimePower = 1 -- The amount of power to give to a player for their playing time

-- The accepted arguments for the permissions are:
-- a number (which means maximum rank to access the option)
-- a table (an array of numbers that define ranks which can specifically access the option), looks like {1, 2, 3},
-- the string 'owner' so the owner can only access it (rank 1)
MenuPermissions = {
    invite = 1, -- Rank 1 is the owner
    kick = 1,
    promote = 1,
    demote = 1,
    deposit = 1,
    withdraw = 1,
    claim = 1,
    unclaim = 1
}