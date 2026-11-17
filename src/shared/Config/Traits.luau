--!strict
--[[
	Config/Traits
	Traços (Fase 13B). Cada artista obtido recebe 1 traço sorteado no servidor: primeiro a
	raridade do traço (Weight), depois o traço (igual probabilidade). O valor cresce com a
	raridade do traço. Só contam os artistas no palco e respeitam os limites somados de
	Config/Artists.Caps. Voz Potente multiplica o bónus do próprio artista.
	"Ritmo Perfeito" (Fase 9) e "Sortudo" (Fase 11) entram quando essas fases existirem.
]]

local Types = require(script.Parent.Parent.Types)

type TraitTierDef = Types.TraitTierDef
type TraitDef = Types.TraitDef

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- stylua: ignore
local Tiers: { TraitTierDef } = {
	{ Id = "Common",    Name = "Comum",    Weight = 60, Color = rgb(190, 190, 200) },
	{ Id = "Rare",      Name = "Raro",     Weight = 28, Color = rgb(70, 140, 255) },
	{ Id = "Epic",      Name = "Épico",    Weight = 10, Color = rgb(170, 90, 255) },
	{ Id = "Legendary", Name = "Lendário", Weight = 2,  Color = rgb(255, 195, 50) },
}

-- Values: Comum, Raro, Épico, Lendário
-- stylua: ignore
local List: { TraitDef } = {
	{ Id = "StrongVoice", Name = "Voz Potente",  Kind = "ArtistHype",      Values = { 0.10, 0.20, 0.35, 0.60 } },
	{ Id = "FastHands",   Name = "Mãos Rápidas", Kind = "ClickPower",      Values = { 0.05, 0.10, 0.18, 0.30 } },
	{ Id = "Energetic",   Name = "Energético",   Kind = "Energy",          Values = { 0.05, 0.10, 0.15, 0.25 } },
	{ Id = "Showman",     Name = "Showman",      Kind = "BoostExtend",     Values = { 0.5, 1, 1.5, 2 } },
	{ Id = "Pyromaniac",  Name = "Pirómano",     Kind = "MachineCooldown", Values = { 0.10, 0.15, 0.20, 0.30 }, Machine = "Flamethrower" },
	{ Id = "CrowdSurfer", Name = "Crowd Surfer", Kind = "PassiveHype",     Values = { 0.01, 0.02, 0.03, 0.05 } },
}

local TiersById: { [string]: TraitTierDef } = {}
local TierIndex: { [string]: number } = {}
local totalWeight = 0
for index, tier in Tiers do
	TiersById[tier.Id] = table.freeze(tier)
	TierIndex[tier.Id] = index
	totalWeight += tier.Weight
end
assert(math.abs(totalWeight - 100) < 1e-9, "Config/Traits: os pesos das raridades têm de somar 100")

local ById: { [string]: TraitDef } = {}
local Ids: { string } = {}
for _, def in List do
	assert(ById[def.Id] == nil, "Config/Traits: traço duplicado " .. def.Id)
	assert(#def.Values == #Tiers, "Config/Traits: " .. def.Id .. " precisa de um valor por raridade")
	ById[def.Id] = table.freeze(def)
	table.insert(Ids, def.Id)
end

return table.freeze({
	Tiers = table.freeze(Tiers),
	TiersById = table.freeze(TiersById),
	TierIndex = table.freeze(TierIndex),
	List = table.freeze(List),
	ById = table.freeze(ById),
	Ids = table.freeze(Ids),
	AnnounceTier = "Legendary", -- traço desta raridade num Remix: explosão no disco + anúncio
})
