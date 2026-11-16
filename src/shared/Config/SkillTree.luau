--!strict
--[[
	Config/SkillTree
	Árvore permanente comprada com Discos de Platina (nunca reinicia).
	Custo do próximo nível = BaseCost × CostGrowth ^ (nível atual).
	PerLevel é o valor do efeito por nível (ver PrestigeCalc.GetSkillEffects).
]]

local Types = require(script.Parent.Parent.Types)

type SkillNodeDef = Types.SkillNodeDef

-- stylua: ignore
local List: { SkillNodeDef } = {
	-- Som
	{ Id = "Amplification", Name = "Amplificação",       Branch = "Sound",    Row = 1, Effect = "HypeMultiplier",     PerLevel = 0.25, MaxLevel = 50, BaseCost = 1,  CostGrowth = 1.25 },
	{ Id = "GoldenBeat",    Name = "Batida de Ouro",     Branch = "Sound",    Row = 2, Effect = "ClickMultiplier",    PerLevel = 0.50, MaxLevel = 25, BaseCost = 3,  CostGrowth = 1.3, Requires = "Amplification", RequiresLevel = 5 },
	{ Id = "InfiniteEcho",  Name = "Eco Infinito",       Branch = "Sound",    Row = 3, Effect = "OfflineEfficiency",  PerLevel = 0.10, MaxLevel = 5,  BaseCost = 10, CostGrowth = 1.5, Requires = "Amplification", RequiresLevel = 15 },
	{ Id = "CrowdAura",     Name = "Aura do Público",    Branch = "Sound",    Row = 4, Effect = "ArtistBonus",        PerLevel = 0.10, MaxLevel = 20, BaseCost = 25, CostGrowth = 1.3, Requires = "GoldenBeat", RequiresLevel = 10 },
	-- Recuperação (após o reset)
	{ Id = "Roadie",        Name = "Roadie Experiente",  Branch = "Recovery", Row = 1, Effect = "StartingHype",       PerLevel = 1,    MaxLevel = 8,  BaseCost = 2,  CostGrowth = 1.6 },
	{ Id = "StoredGear",    Name = "Material Guardado",  Branch = "Recovery", Row = 2, Effect = "StartingGenerators", PerLevel = 10,   MaxLevel = 5,  BaseCost = 5,  CostGrowth = 1.6, Requires = "Roadie", RequiresLevel = 2 },
	{ Id = "PrebuiltStage", Name = "Palco Pré-montado",  Branch = "Recovery", Row = 3, Effect = "StartTier",          PerLevel = 1,    MaxLevel = 3,  BaseCost = 20, CostGrowth = 2.5, Requires = "StoredGear", RequiresLevel = 2 },
	{ Id = "Negotiation",   Name = "Negociação",         Branch = "Recovery", Row = 4, Effect = "StageCostCut",       PerLevel = 0.08, MaxLevel = 5,  BaseCost = 8,  CostGrowth = 1.7, Requires = "Roadie", RequiresLevel = 3 },
	-- Pirotecnia
	{ Id = "Preheat",       Name = "Pré-aquecimento",    Branch = "Pyro",     Row = 1, Effect = "StartEnergy",        PerLevel = 10,   MaxLevel = 5,  BaseCost = 3,  CostGrowth = 1.5 },
	{ Id = "Encore",        Name = "Encore",             Branch = "Pyro",     Row = 2, Effect = "BoostBonus",         PerLevel = 1,    MaxLevel = 5,  BaseCost = 6,  CostGrowth = 1.5, Requires = "Preheat", RequiresLevel = 2 },
	{ Id = "PerfectPitch",  Name = "Ouvido Absoluto",    Branch = "Pyro",     Row = 3, Effect = "WindowBonus",        PerLevel = 0.02, MaxLevel = 3,  BaseCost = 15, CostGrowth = 2,   Requires = "Encore", RequiresLevel = 2 },
	{ Id = "TunedMachines", Name = "Máquinas Afinadas",  Branch = "Pyro",     Row = 4, Effect = "CooldownCut",        PerLevel = 0.05, MaxLevel = 4,  BaseCost = 12, CostGrowth = 1.8, Requires = "Preheat", RequiresLevel = 3 },
	-- Discos
	{ Id = "RecordDeal",    Name = "Contrato Discográfico", Branch = "Discs", Row = 1, Effect = "DiscBonus",          PerLevel = 0.10, MaxLevel = 20, BaseCost = 10, CostGrowth = 1.4 },
	{ Id = "TalentScout",   Name = "Caçador de Talentos",   Branch = "Discs", Row = 2, Effect = "CrateCostCut",       PerLevel = 0.05, MaxLevel = 6,  BaseCost = 15, CostGrowth = 1.5, Requires = "RecordDeal", RequiresLevel = 3 },
	{ Id = "BeginnersLuck", Name = "Sorte de Estreia",      Branch = "Discs", Row = 3, Effect = "PityReduction",      PerLevel = 5,    MaxLevel = 4,  BaseCost = 40, CostGrowth = 2,   Requires = "TalentScout", RequiresLevel = 2 },
}

local BRANCHES: { { Id: Types.SkillBranch, Name: string, Color: Color3 } } = {
	{ Id = "Sound", Name = "SOM", Color = Color3.fromRGB(255, 60, 172) },
	{ Id = "Recovery", Name = "RECUPERAÇÃO", Color = Color3.fromRGB(57, 217, 138) },
	{ Id = "Pyro", Name = "PIROTECNIA", Color = Color3.fromRGB(255, 140, 60) },
	{ Id = "Discs", Name = "DISCOS", Color = Color3.fromRGB(180, 235, 255) },
}

local ById: { [string]: SkillNodeDef } = {}
local Ids: { string } = {}

for _, def in List do
	assert(ById[def.Id] == nil, "Config/SkillTree: nó duplicado " .. def.Id)
	ById[def.Id] = table.freeze(def)
	table.insert(Ids, def.Id)
end
for _, def in List do
	local requirement = def.Requires
	if requirement then
		assert(ById[requirement], "Config/SkillTree: " .. def.Id .. " requer nó desconhecido " .. requirement)
		assert(def.RequiresLevel and def.RequiresLevel >= 1, "Config/SkillTree: " .. def.Id .. " sem RequiresLevel")
	end
end
for _, branch in BRANCHES do
	table.freeze(branch)
end

return table.freeze({
	List = table.freeze(List),
	ById = table.freeze(ById),
	Ids = table.freeze(Ids),
	Branches = table.freeze(BRANCHES),
})
