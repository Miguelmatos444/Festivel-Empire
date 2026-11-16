--!strict
--[[
	Config/Rarities
	As 22 raridades, por ordem crescente.
	Weight (em %) é a referência global por família (Comum 55% · Raro 28% · Épico 12% ·
	Lendário 4.5% · Mítico+ 0.5%). As crates JÁ NÃO sorteiam com estes pesos: cada crate
	tem uma janela de 6 raridades com probabilidades por posição (Config/Artists.SlotOdds).
]]

local Types = require(script.Parent.Parent.Types)

type RarityDef = Types.RarityDef
type PityLevel = Types.PityLevel

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- stylua: ignore
local List: { RarityDef } = {
	-- Família Comum (55%) — sem habilidade
	{ Id = "Common",       Name = "Comum",         Family = "Common",    Weight = 30,     Bonus = 0.10, AbilityScale = 1,    Duet = false, Aura = 0,    OmegaSave = false, Color = rgb(160, 160, 170), Effect = "None" },
	{ Id = "Uncommon",     Name = "Incomum",       Family = "Common",    Weight = 17,     Bonus = 0.15, AbilityScale = 1,    Duet = false, Aura = 0,    OmegaSave = false, Color = rgb(190, 198, 210), Effect = "None" },
	{ Id = "Notable",      Name = "Notável",       Family = "Common",    Weight = 8,      Bonus = 0.20, AbilityScale = 1,    Duet = false, Aura = 0,    OmegaSave = false, Color = rgb(225, 232, 242), Effect = "None" },
	-- Família Raro (28%)
	{ Id = "Rare",         Name = "Raro",          Family = "Rare",      Weight = 16,     Bonus = 0.25, AbilityScale = 1,    Duet = false, Aura = 0,    OmegaSave = false, Color = rgb(70, 140, 255),  Effect = "None" },
	{ Id = "Brilliant",    Name = "Brilhante",     Family = "Rare",      Weight = 8,      Bonus = 0.35, AbilityScale = 1.25, Duet = false, Aura = 0,    OmegaSave = false, Color = rgb(95, 170, 255),  Effect = "None" },
	{ Id = "Precious",     Name = "Precioso",      Family = "Rare",      Weight = 4,      Bonus = 0.45, AbilityScale = 1.5,  Duet = false, Aura = 0,    OmegaSave = false, Color = rgb(125, 205, 255), Effect = "None" },
	-- Família Épico (12%)
	{ Id = "Epic",         Name = "Épico",         Family = "Epic",      Weight = 7,      Bonus = 0.60, AbilityScale = 1,    Duet = false, Aura = 0,    OmegaSave = false, Color = rgb(150, 80, 255),  Effect = "None" },
	{ Id = "Heroic",       Name = "Heroico",       Family = "Epic",      Weight = 3.5,    Bonus = 0.80, AbilityScale = 1.25, Duet = false, Aura = 0,    OmegaSave = false, Color = rgb(178, 98, 255),  Effect = "None" },
	{ Id = "Supreme",      Name = "Supremo",       Family = "Epic",      Weight = 1.5,    Bonus = 1.00, AbilityScale = 1.5,  Duet = false, Aura = 0,    OmegaSave = false, Color = rgb(208, 122, 255), Effect = "None" },
	-- Família Lendário (4.5%)
	{ Id = "Legendary",    Name = "Lendário",      Family = "Legendary", Weight = 2.7,    Bonus = 1.50, AbilityScale = 1,    Duet = false, Aura = 0,    OmegaSave = false, Color = rgb(255, 195, 50),  Effect = "None" },
	{ Id = "Ancestral",    Name = "Ancestral",     Family = "Legendary", Weight = 1.2,    Bonus = 2.00, AbilityScale = 1.25, Duet = false, Aura = 0,    OmegaSave = false, Color = rgb(255, 160, 40),  Effect = "None" },
	{ Id = "Immortal",     Name = "Imortal",       Family = "Legendary", Weight = 0.6,    Bonus = 2.75, AbilityScale = 1.5,  Duet = false, Aura = 0,    OmegaSave = false, Color = rgb(255, 120, 30),  Effect = "None" },
	-- Família Mítico+ (0.5%)
	{ Id = "Mythic",       Name = "Mítico",        Family = "Mythic",    Weight = 0.25,   Bonus = 4,    AbilityScale = 1,    Duet = false, Aura = 0,    OmegaSave = false, Color = rgb(255, 60, 80),   Effect = "None" },
	{ Id = "Divine",       Name = "Divino",        Family = "Mythic",    Weight = 0.12,   Bonus = 10,   AbilityScale = 1,    Duet = true,  Aura = 0,    OmegaSave = false, Color = rgb(255, 240, 190), Effect = "Glow" },
	{ Id = "Celestial",    Name = "Celestial",     Family = "Mythic",    Weight = 0.06,   Bonus = 15,   AbilityScale = 1,    Duet = true,  Aura = 0.10, OmegaSave = false, Color = rgb(120, 240, 255), Effect = "Glow" },
	{ Id = "Astral",       Name = "Astral",        Family = "Mythic",    Weight = 0.035,  Bonus = 25,   AbilityScale = 1,    Duet = true,  Aura = 0.15, OmegaSave = false, Color = rgb(180, 160, 255), Effect = "Glow" },
	{ Id = "Cosmic",       Name = "Cósmico",       Family = "Mythic",    Weight = 0.018,  Bonus = 40,   AbilityScale = 1,    Duet = true,  Aura = 0.20, OmegaSave = false, Color = rgb(150, 100, 255), Effect = "Gradient" },
	{ Id = "Ethereal",     Name = "Etéreo",        Family = "Mythic",    Weight = 0.009,  Bonus = 60,   AbilityScale = 1,    Duet = true,  Aura = 0.25, OmegaSave = false, Color = rgb(200, 255, 240), Effect = "Gradient" },
	{ Id = "Primordial",   Name = "Primordial",    Family = "Mythic",    Weight = 0.0045, Bonus = 90,   AbilityScale = 1,    Duet = true,  Aura = 0.30, OmegaSave = false, Color = rgb(255, 140, 90),  Effect = "Gradient" },
	{ Id = "Infinite",     Name = "Infinito",      Family = "Mythic",    Weight = 0.002,  Bonus = 140,  AbilityScale = 1,    Duet = true,  Aura = 0.40, OmegaSave = false, Color = rgb(255, 255, 255), Effect = "Gradient" },
	{ Id = "Transcendent", Name = "Transcendente", Family = "Mythic",    Weight = 0.001,  Bonus = 200,  AbilityScale = 1,    Duet = true,  Aura = 0.50, OmegaSave = false, Color = rgb(255, 215, 120), Effect = "Gradient" },
	{ Id = "Omega",        Name = "Ómega",         Family = "Mythic",    Weight = 0.0005, Bonus = 300,  AbilityScale = 1,    Duet = true,  Aura = 0.75, OmegaSave = true,  Color = rgb(255, 0, 180),   Effect = "Rainbow" },
}

-- Escada de pity: ao chegar a Threshold aberturas sem uma raridade >= MinRarity, essa
-- raridade (ou melhor) é garantida. Obter uma raridade reinicia este patamar e os de baixo.
local PityLadder: { PityLevel } = {
	{ Key = "Legendary", Threshold = 50, MinRarity = "Legendary", Label = "Lendário+" },
	{ Key = "Mythic", Threshold = 250, MinRarity = "Mythic", Label = "Mítico+" },
	{ Key = "Divine", Threshold = 1000, MinRarity = "Divine", Label = "Divino+" },
	{ Key = "Cosmic", Threshold = 5000, MinRarity = "Cosmic", Label = "Cósmico+" },
}

local FAMILY_TOTALS: { [string]: number } = {
	Common = 55,
	Rare = 28,
	Epic = 12,
	Legendary = 4.5,
	Mythic = 0.5,
}

local ById: { [string]: RarityDef } = {}
local IndexById: { [string]: number } = {}

-- Validação: soma 100%, famílias certas, pity aponta para raridades existentes
do
	local total = 0
	local families: { [string]: number } = {}
	for index, def in List do
		assert(ById[def.Id] == nil, "Config/Rarities: id duplicado " .. def.Id)
		ById[def.Id] = table.freeze(def)
		IndexById[def.Id] = index
		total += def.Weight
		families[def.Family] = (families[def.Family] or 0) + def.Weight
	end
	assert(math.abs(total - 100) < 1e-9, "Config/Rarities: os pesos têm de somar 100 (somam " .. total .. ")")
	for family, expected in FAMILY_TOTALS do
		assert(
			math.abs((families[family] or 0) - expected) < 1e-9,
			string.format("Config/Rarities: família %s soma %s em vez de %s", family, tostring(families[family]), tostring(expected))
		)
	end
	for _, level in PityLadder do
		assert(IndexById[level.MinRarity], "Config/Rarities: pity aponta para raridade desconhecida " .. level.MinRarity)
		table.freeze(level)
	end
end

return table.freeze({
	List = table.freeze(List),
	ById = table.freeze(ById),
	IndexById = table.freeze(IndexById),
	Count = #List,
	PityLadder = table.freeze(PityLadder),
})
