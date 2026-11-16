--!strict
--[[
	Config/Equipment
	Equipamentos compráveis. A ordem da lista é a ordem de apresentação na loja.
	Custo do próximo nível: BaseCost * GrowthRate ^ Nível
	Produção: BaseOutput * Nível * Multiplicador de marcos (Config/Economy.Milestones)
]]

local Types = require(script.Parent.Parent.Types)

type EquipmentDef = Types.EquipmentDef

local List: { EquipmentDef } = {
	-- Batidas (upgrade de clique) ------------------------------------------
	{
		Id = "BeatPad",
		Name = "Pad de Batidas",
		Description = "Cada nível dá +1 Hype por batida.",
		Category = "Batidas",
		Kind = "Click",
		BaseCost = 25,
		GrowthRate = 1.15,
		BaseOutput = 1,
		RequiredTier = 1,
	},

	-- Geradores passivos -----------------------------------------------------
	{
		Id = "GarageSpeaker",
		Name = "Coluna de Garagem",
		Description = "Som cru, mas a multidão começa a chegar.",
		Category = "Colunas",
		Kind = "Generator",
		BaseCost = 12,
		GrowthRate = 1.15,
		BaseOutput = 0.2,
		RequiredTier = 1,
	},
	{
		Id = "BassSpeaker",
		Name = "Coluna Bass Reflex",
		Description = "Graves que se sentem no peito.",
		Category = "Colunas",
		Kind = "Generator",
		BaseCost = 120,
		GrowthRate = 1.15,
		BaseOutput = 1.5,
		RequiredTier = 1,
		UnlockAfter = "GarageSpeaker",
	},
	{
		Id = "Mixer4",
		Name = "Mesa de Mistura 4 Canais",
		Description = "Primeiras transições limpas entre faixas.",
		Category = "Mesas",
		Kind = "Generator",
		BaseCost = 1500,
		GrowthRate = 1.14,
		BaseOutput = 12,
		RequiredTier = 1,
		UnlockAfter = "BassSpeaker",
	},
	{
		Id = "LineArray",
		Name = "Torre Line Array",
		Description = "Som que chega à última fila do recinto.",
		Category = "Colunas",
		Kind = "Generator",
		BaseCost = 18000,
		GrowthRate = 1.14,
		BaseOutput = 90,
		RequiredTier = 1,
		UnlockAfter = "Mixer4",
	},
	{
		Id = "Mixer32",
		Name = "Mesa Digital 32 Canais",
		Description = "Controlo total de cada instrumento em palco.",
		Category = "Mesas",
		Kind = "Generator",
		BaseCost = 250000,
		GrowthRate = 1.13,
		BaseOutput = 700,
		RequiredTier = 2,
		UnlockAfter = "LineArray",
	},
	{
		Id = "ResidentDJ",
		Name = "DJ Residente",
		Description = "Mantém a pista cheia a noite inteira.",
		Category = "DJs",
		Kind = "Generator",
		BaseCost = 3.5e6,
		GrowthRate = 1.12,
		BaseOutput = 5500,
		RequiredTier = 3,
		UnlockAfter = "Mixer32",
	},
	{
		Id = "FxRack",
		Name = "Rack de Efeitos e Sampler",
		Description = "Loops, ecos e drops preparados ao segundo.",
		Category = "Mesas",
		Kind = "Generator",
		BaseCost = 50e6,
		GrowthRate = 1.11,
		BaseOutput = 42000,
		RequiredTier = 4,
		UnlockAfter = "ResidentDJ",
	},
	{
		Id = "HeadlinerDJ",
		Name = "DJ Cabeça de Cartaz",
		Description = "O nome que enche o cartaz do festival.",
		Category = "DJs",
		Kind = "Generator",
		BaseCost = 750e6,
		GrowthRate = 1.10,
		BaseOutput = 320000,
		RequiredTier = 5,
		UnlockAfter = "FxRack",
	},
	{
		Id = "B2BCollective",
		Name = "Coletivo de DJs B2B",
		Description = "Vários DJs em sequência, energia sem pausas.",
		Category = "DJs",
		Kind = "Generator",
		BaseCost = 12e9,
		GrowthRate = 1.09,
		BaseOutput = 2.5e6,
		RequiredTier = 6,
		UnlockAfter = "HeadlinerDJ",
	},
}

local ById: { [string]: EquipmentDef } = {}
local Ids: { string } = {}

for _, def in List do
	assert(ById[def.Id] == nil, "Config/Equipment: id duplicado " .. def.Id)
	ById[def.Id] = table.freeze(def)
	table.insert(Ids, def.Id)
end

return table.freeze({
	List = table.freeze(List),
	ById = table.freeze(ById),
	Ids = table.freeze(Ids),
})
