--!strict
--[[
	Config/Artists
	Vinyl Crates, os 25 artistas (5 por crate, 1 por família de raridade), estrelas,
	limites das habilidades, slots e regras da coleção.
	A raridade exata (22 possíveis) é sorteada à parte: é uma "versão" do artista da família.
]]

local Types = require(script.Parent.Parent.Types)

type CrateDef = Types.CrateDef
type ArtistDef = Types.ArtistDef

-- stylua: ignore
local Crates: { CrateDef } = {
	{ Id = "Underground", Name = "Crate Underground",       Era = "Underground", RequiredTier = 1,  Cost = 1e3,   EraFactor = 1 },
	{ Id = "Ascensao",    Name = "Crate Ascensão",          Era = "Ascensão",    RequiredTier = 4,  Cost = 250e6, EraFactor = 2 },
	{ Id = "Estrelato",   Name = "Crate Estrelato",         Era = "Estrelato",   RequiredTier = 7,  Cost = 10e12, EraFactor = 4 },
	{ Id = "Lenda",       Name = "Crate Lenda",             Era = "Lenda",       RequiredTier = 10, Cost = 1e15,  EraFactor = 8 },
	{ Id = "Orbital",     Name = "Crate Especial Orbital",  Era = "Lenda",       RequiredTier = 12, Cost = 25e15, EraFactor = 15 },
}

local List: { ArtistDef } = {
	-- Underground
	{ Id = "ZeColunas", Name = "Zé das Colunas", Crate = "Underground", Family = "Common" },
	{ Id = "LinaLoop", Name = "Lina Loop", Crate = "Underground", Family = "Rare", Ability = { Kind = "ClickPower", Value = 0.20 } },
	{ Id = "KikoKick", Name = "Kiko Kick", Crate = "Underground", Family = "Epic", Ability = { Kind = "WindowWiden", Value = 0.03 } },
	{ Id = "RatosCave", Name = "Os Ratos de Cave", Crate = "Underground", Family = "Legendary", Ability = { Kind = "CooldownCut", Value = 0.10 } },
	{ Id = "MadameFeedback", Name = "Madame Feedback", Crate = "Underground", Family = "Mythic", Ability = { Kind = "AutoPyro", Machine = "ColdSparks" } },
	-- Ascensão
	{ Id = "NeonNico", Name = "Neon Nico", Crate = "Ascensao", Family = "Common" },
	{ Id = "DuplaSintetiza", Name = "Dupla Sintetiza", Crate = "Ascensao", Family = "Rare", Ability = { Kind = "Energy", Value = 0.20 } },
	{ Id = "RitaReverb", Name = "Rita Reverb", Crate = "Ascensao", Family = "Epic", Ability = { Kind = "BoostExtend", Value = 2 } },
	{ Id = "CapitaoStrobe", Name = "Capitão Strobe", Crate = "Ascensao", Family = "Legendary", Ability = { Kind = "AutoPyro", Machine = "CO2Cannon" } },
	{ Id = "VeraVoltagem", Name = "Vera Voltagem", Crate = "Ascensao", Family = "Mythic", Ability = { Kind = "SaveDrop", Grade = "Good", Cooldown = 90 } },
	-- Estrelato
	{ Id = "BandaHolofote", Name = "Banda Holofote", Crate = "Estrelato", Family = "Common" },
	{ Id = "DuoDecibel", Name = "Duo Decibel", Crate = "Estrelato", Family = "Rare", Ability = { Kind = "ClickPower", Value = 0.40 } },
	{ Id = "LuaLaser", Name = "Lua Laser", Crate = "Estrelato", Family = "Epic", Ability = { Kind = "WindowWiden", Value = 0.05 } },
	{ Id = "TrovaoGrave", Name = "Trovão Grave", Crate = "Estrelato", Family = "Legendary", Ability = { Kind = "CooldownCut", Value = 0.15 } },
	{ Id = "OrquestraInfinita", Name = "A Orquestra Infinita", Crate = "Estrelato", Family = "Mythic", Ability = { Kind = "AutoPyro", Machine = "Lasers" } },
	-- Lenda
	{ Id = "HoloHugo", Name = "Holo Hugo", Crate = "Lenda", Family = "Common" },
	{ Id = "NebulaNina", Name = "Nébula Nina", Crate = "Lenda", Family = "Rare", Ability = { Kind = "Energy", Value = 0.35 } },
	{ Id = "CometaKai", Name = "Cometa Kai", Crate = "Lenda", Family = "Epic", Ability = { Kind = "BoostExtend", Value = 3 } },
	{ Id = "DamaPrisma", Name = "Dama Prisma", Crate = "Lenda", Family = "Legendary", Ability = { Kind = "AutoPyro", Machine = "Flamethrower" } },
	{ Id = "ArquitetoDrop", Name = "O Arquiteto do Drop", Crate = "Lenda", Family = "Mythic", Ability = { Kind = "SaveDrop", Grade = "Great", Cooldown = 60 } },
	-- Especial Orbital
	{ Id = "SateliteSam", Name = "Satélite Sam", Crate = "Orbital", Family = "Common" },
	{ Id = "GravidadeZero", Name = "Gravidade Zero", Crate = "Orbital", Family = "Rare", Ability = { Kind = "ClickPower", Value = 0.75 } },
	{ Id = "AuroraAustral", Name = "Aurora Austral", Crate = "Orbital", Family = "Epic", Ability = { Kind = "WindowWiden", Value = 0.08 } },
	{ Id = "Eclipse", Name = "Eclipse", Crate = "Orbital", Family = "Legendary", Ability = { Kind = "CooldownCut", Value = 0.25 } },
	{ Id = "Supernova", Name = "Supernova", Crate = "Orbital", Family = "Mythic", Ability = { Kind = "FullShow" } },
}

local CratesById: { [string]: CrateDef } = {}
local CrateIds: { string } = {}
for _, crate in Crates do
	assert(CratesById[crate.Id] == nil, "Config/Artists: crate duplicada " .. crate.Id)
	CratesById[crate.Id] = table.freeze(crate)
	table.insert(CrateIds, crate.Id)
end

local ById: { [string]: ArtistDef } = {}
local ByCrateFamily: { [string]: ArtistDef } = {} -- "Crate|Family" -> artista
for _, def in List do
	assert(ById[def.Id] == nil, "Config/Artists: artista duplicado " .. def.Id)
	assert(CratesById[def.Crate], "Config/Artists: crate desconhecida em " .. def.Id)
	local key = def.Crate .. "|" .. def.Family
	assert(ByCrateFamily[key] == nil, "Config/Artists: duas famílias iguais na crate " .. key)
	ById[def.Id] = table.freeze(def)
	ByCrateFamily[key] = def
end
for _, crate in Crates do
	for _, family in { "Common", "Rare", "Epic", "Legendary", "Mythic" } do
		assert(ByCrateFamily[crate.Id .. "|" .. family], "Config/Artists: falta a família " .. family .. " em " .. crate.Id)
	end
end

return table.freeze({
	Crates = table.freeze(Crates),
	CratesById = table.freeze(CratesById),
	CrateIds = table.freeze(CrateIds),
	List = table.freeze(List),
	ById = table.freeze(ById),
	ByCrateFamily = table.freeze(ByCrateFamily),

	-- Estrelas: bónus de Hype e força da habilidade (recarga do Salva-Drop é dividida)
	MaxStars = 3,
	StarBonus = table.freeze({ 1, 2.5, 6 }),
	StarAbility = table.freeze({ 1, 1.5, 2 }),
	FuseCount = 3,

	-- Habilidades especiais por raridade
	OmegaSaveCooldown = 30,

	-- Limites somando todos os artistas equipados
	Caps = table.freeze({
		WindowBonus = 0.15,
		CooldownCut = 0.5,
		BoostBonus = 8,
		EnergyBonus = 1.0,
	}),

	-- Slots no palco: base + 1 com 1 World Tour + 1 com 3 World Tours + 2 com o Gamepass
	BaseSlots = 3,
	WorldTourSlots = table.freeze({ 1, 3 }),
	GamepassSlots = 2,
	VipGamepassId = 0, -- id do Gamepass "Palco VIP" (0 = ainda não existe)
	MaxSlots = 7,

	-- Coleção
	InventoryCap = 300,
	AutoDeleteMaxIndex = 12, -- o Auto-Delete nunca apaga Mítico ou acima
	OpenCounts = table.freeze({ 1, 10 }),
})
