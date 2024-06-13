CREATE TABLE IF NOT EXISTS `eol_factions` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `name` LONGTEXT NOT NULL,
    `ownerid` VARCHAR(255) NOT NULL,
    `money` BIGINT(20) NULL DEFAULT 0,
    PRIMARY KEY (`id`)
)

CREATE TABLE IF NOT EXISTS `eol_factionusers` (
    `identifier` VARCHAR(255) NOT NULL,
    `factionid` INT(11) NOT NULL,
    `factionrank` INT(11) NULL DEFAULT 1,
    `power` BIGINT(20) NULL DEFAULT 0,
    PRIMARY KEY (`identifier`)
)

CREATE TABLE IF NOT EXISTS `eol_factionclaims` (
    `claimedby` INT(11) NULL,
    `grid` VARCHAR(255) NOT NULL,
    PRIMARY KEY (`grid`)
)