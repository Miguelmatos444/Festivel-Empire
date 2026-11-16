--!strict
--[[
	Config/Artists
	Vinyl Crates, os 25 artistas (5 por crate), estrelas, limites das habilidades,
	slots e regras da coleção.

	Sorteio de uma crate:
	  - Raridade: cada crate tem uma janela de #SlotOdds raridades seguidas a começar em
	    MinRarity (Underground 1–6, Ascensão 5–10, Estrelato 9–14, Lenda 13–18,
	    Orbital 17–22). A probabilidade depende só da posição na janela (SlotOdds).
	  - Artista: um dos 5 artistas da crate, com igual probabilidade. A raridade é a
	    "versão" desse artista.
	A Family de cada artista mantém-se para o Dueto (parceiro "Legendary" da crate).
]]

local Types = require(script.Parent.Parent.Types)
local RaritiesConfig = require(script.Parent.Rarities)

type CrateDef = Types.CrateDef
type ArtistDef = Types.ArtistDef

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- stylua: ignore
local Crates: { CrateDef } = {
	{ Id = "Underground", Name = "Crate Underground",      Era = "Underground", RequiredTier = 1,  Cost = 1e3,   EraFactor = 1,  MinRarity = "Common",    Color = rgb(255, 120, 70) },
	{ Id = "Ascensao",    Name = "Crate Ascensão",         Era = "Ascensão",    RequiredTier = 4,  Cost = 250e6, EraFactor = 2,  MinRarity = "Brilliant", Color = rgb(43, 210, 255) },
	{ Id = "Estrelato",   Name = "Crate Estrelato",        Era = "Estrelato",   RequiredTier = 7,  Cost = 10e12, EraFactor = 4,  MinRarity = "Supreme",   Color = rgb(255, 209, 102) },
	{ Id = "Lenda",       Name = "Crate Lenda",            Era = "Lenda",       RequiredTier = 10, Cost = 1e15,  EraFactor = 8,  MinRarity = "Mythic",    Color = rgb(160, 120, 255) },
	{ Id = "Orbital",     Name = "Crate Especial Orbital", Era = "Lenda",       RequiredTier = 12, Cost = 25e15, EraFactor = 15, MinRarity = "Cosmic",    Color = rgb(255, 60, 172) },
}

-- Probabilidade por posição na janela de raridades da crate (1ª = mais comum). Soma 1.
local SlotOdds: { number } = { 0.50, 0.25, 0.13, 0.07, 0.04, 0.01 }

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

do
	local total = 0
	for _, chance in SlotOdds do
		assert(chance > 0, "Config/Artists: SlotOdds só aceita valores > 0")
		total += chance
	end
	assert(math.abs(total - 1) < 1e-9, "Config/Artists: SlotOdds tem de somar 1 (soma " .. total .. ")")
end

local CratesById: { [string]: CrateDef } = {}
local CrateIds: { string } = {}
for _, crate in Crates do
	assert(CratesById[crate.Id] == nil, "Config/Artists: crate duplicada " .. crate.Id)
	local first = RaritiesConfig.IndexById[crate.MinRarity]
	assert(first, "Config/Artists: MinRarity desconhecida em " .. crate.Id)
	assert(first + #SlotOdds - 1 <= RaritiesConfig.Count, "Config/Artists: janela de raridades fora da lista em " .. crate.Id)
	CratesById[crate.Id] = table.freeze(crate)
	table.insert(CrateIds, crate.Id)
end

local ById: { [string]: ArtistDef } = {}
local ByCrateFamily: { [string]: ArtistDef } = {} -- "Crate|Family" -> artista (Dueto)
local ByCrate: { [string]: { ArtistDef } } = {} -- crate -> artistas sorteáveis
for _, def in List do
	assert(ById[def.Id] == nil, "Config/Artists: artista duplicado " .. def.Id)
	assert(CratesById[def.Crate], "Config/Artists: crate desconhecida em " .. def.Id)
	local key = def.Crate .. "|" .. def.Family
	assert(ByCrateFamily[key] == nil, "Config/Artists: duas famílias iguais na crate " .. key)
	ById[def.Id] = table.freeze(def)
	ByCrateFamily[key] = def
	local crateList = ByCrate[def.Crate] or {}
	table.insert(crateList, def)
	ByCrate[def.Crate] = crateList
end
for _, crate in Crates do
	for _, family in { "Common", "Rare", "Epic", "Legendary", "Mythic" } do
		assert(ByCrateFamily[crate.Id .. "|" .. family], "Config/Artists: falta a família " .. family .. " em " .. crate.Id)
	end
	table.freeze(ByCrate[crate.Id])
end

return table.freeze({
	Crates = table.freeze(Crates),
	CratesById = table.freeze(CratesById),
	CrateIds = table.freeze(CrateIds),
	List = table.freeze(List),
	ById = table.freeze(ById),
	ByCrateFamily = table.freeze(ByCrateFamily),
	ByCrate = table.freeze(ByCrate),

	-- Sorteio
	SlotOdds = table.freeze(SlotOdds),
	AnnounceFromSlot = 5, -- anunciar a todos as 2 raridades mais raras de cada crate

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
