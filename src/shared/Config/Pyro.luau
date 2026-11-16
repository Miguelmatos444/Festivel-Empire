--!strict
--[[
	Config/Pyro
	Máquinas de pirotecnia e sinergias do Bass Drop.
	Multiplicador = clamp(Soma das bases × Produto das sinergias × Fator de timing, Min, Max)
	RequiredTier = tier de palco exigido para DESBLOQUEAR a máquina (CO₂ 2, Lasers 4, Lança-chamas 8).
	Depois de desbloqueada, a máquina continua utilizável mesmo que um World Tour baixe o tier.
]]

local Types = require(script.Parent.Parent.Types)

type PyroDef = Types.PyroDef
type SynergyDef = Types.SynergyDef

local List: { PyroDef } = {
	{
		Id = "ColdSparks",
		Name = "Faíscas Frias",
		ShortName = "FAÍSCAS",
		Description = "Fontes de faíscas seguras junto ao palco.",
		Bit = 1,
		UnlockCost = 0,
		BaseMultiplier = 5,
		Cooldown = 0,
		RequiredTier = 1,
	},
	{
		Id = "CO2Cannon",
		Name = "Canhões de CO₂",
		ShortName = "CO₂",
		Description = "Jatos de nevoeiro gelado em cada drop.",
		Bit = 2,
		UnlockCost = 50e3,
		BaseMultiplier = 7,
		Cooldown = 45,
		RequiredTier = 2,
	},
	{
		Id = "Lasers",
		Name = "Lasers",
		ShortName = "LASERS",
		Description = "Feixes que varrem o céu ao ritmo da música.",
		Bit = 4,
		UnlockCost = 5e6,
		BaseMultiplier = 10,
		Cooldown = 75,
		RequiredTier = 4,
	},
	{
		Id = "Flamethrower",
		Name = "Lança-chamas",
		ShortName = "CHAMAS",
		Description = "Colunas de fogo que se sentem na última fila.",
		Bit = 8,
		UnlockCost = 500e6,
		BaseMultiplier = 14,
		Cooldown = 120,
		RequiredTier = 8,
	},
}

local Synergies: { SynergyDef } = {
	{
		Id = "IceAndFire",
		Name = "Gelo e Fogo",
		Requires = { "ColdSparks", "Flamethrower" },
		Multiplier = 1.15,
	},
	{
		Id = "LightFog",
		Name = "Nevoeiro de Luz",
		Requires = { "CO2Cannon", "Lasers" },
		Multiplier = 1.20,
	},
	{
		Id = "FullShow",
		Name = "Espetáculo Total",
		Requires = { "ColdSparks", "CO2Cannon", "Lasers", "Flamethrower" },
		Multiplier = 1.15,
	},
}

local ById: { [string]: PyroDef } = {}
local Ids: { string } = {}
local FullMask = 0

for _, def in List do
	assert(ById[def.Id] == nil, "Config/Pyro: id duplicado " .. def.Id)
	assert(def.Bit > 0 and bit32.band(def.Bit, def.Bit - 1) == 0, "Config/Pyro: Bit tem de ser potência de 2")
	assert(bit32.band(FullMask, def.Bit) == 0, "Config/Pyro: Bit repetido em " .. def.Id)
	FullMask = bit32.bor(FullMask, def.Bit)
	ById[def.Id] = table.freeze(def)
	table.insert(Ids, def.Id)
end

for _, synergy in Synergies do
	for _, required in synergy.Requires do
		assert(ById[required], "Config/Pyro: sinergia " .. synergy.Id .. " requer id desconhecido " .. required)
	end
	table.freeze(synergy.Requires)
	table.freeze(synergy)
end

return table.freeze({
	List = table.freeze(List),
	ById = table.freeze(ById),
	Ids = table.freeze(Ids),
	Synergies = table.freeze(Synergies),
	FullMask = FullMask,
})
