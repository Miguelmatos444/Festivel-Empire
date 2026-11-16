--!strict
--[[
	Config/Retention
	Recompensa diária (7 dias) e missões (3 diárias + 2 semanais).
	"IncomeMinutes" = minutos do Hype/s passivo atual (sem boost), com um mínimo
	equivalente a MinIncomeClicksPerSecond batidas por segundo.
	Reinícios em UTC: diárias às 00:00, semanais à segunda-feira às 00:00.
]]

local Types = require(script.Parent.Parent.Types)

type RewardDef = Types.RewardDef
type MissionDef = Types.MissionDef

local HOUR = 3600

local DailyRewards: { RewardDef } = {
	{ IncomeMinutes = 10 },
	{ IncomeMinutes = 20 },
	{ IncomeMinutes = 30, FillEnergy = true },
	{ IncomeMinutes = 45 },
	{ IncomeMinutes = 60 },
	{ IncomeMinutes = 90, Discs = 2 },
	{ IncomeMinutes = 120, Crates = 1 },
}

-- stylua: ignore
local DailyMissions: { MissionDef } = {
	{ Id = "D_Clicks",    Name = "Ritmo constante",   Description = "Dá 1 500 batidas",               Metric = "Clicks",          Target = 1500, Reward = { IncomeMinutes = 20 } },
	{ Id = "D_Drops",     Name = "Mestre do Drop",    Description = "Faz 5 Bass Drops com sucesso",   Metric = "BassDrops",       Target = 5,    Reward = { IncomeMinutes = 20 } },
	{ Id = "D_Perfect",   Name = "Timing perfeito",   Description = "Consegue 2 drops PERFEITOS",     Metric = "PerfectDrops",    Target = 2,    Reward = { IncomeMinutes = 30 } },
	{ Id = "D_Equipment", Name = "Montar o som",      Description = "Compra 50 níveis de equipamento", Metric = "EquipmentLevels", Target = 50,   Reward = { IncomeMinutes = 15 } },
	{ Id = "D_Crates",    Name = "Caçador de vinis",  Description = "Abre 5 Vinyl Crates",            Metric = "CratesOpened",    Target = 5,    Reward = { IncomeMinutes = 20 } },
	{ Id = "D_Playtime",  Name = "Turno completo",    Description = "Joga 20 minutos",                Metric = "PlayMinutes",     Target = 20,   Reward = { IncomeMinutes = 15 } },
	{ Id = "D_Fuse",      Name = "Remisturador",      Description = "Faz 1 fusão de artistas",        Metric = "Fusions",         Target = 1,    Reward = { IncomeMinutes = 25 } },
}

-- stylua: ignore
local WeeklyMissions: { MissionDef } = {
	{ Id = "W_Drops",     Name = "Maratona de drops", Description = "Faz 40 Bass Drops com sucesso",  Metric = "BassDrops",       Target = 40,    Reward = { IncomeMinutes = 120, Crates = 3 } },
	{ Id = "W_Clicks",    Name = "Mãos de ferro",     Description = "Dá 25 000 batidas",              Metric = "Clicks",          Target = 25000, Reward = { IncomeMinutes = 120, Crates = 3 } },
	{ Id = "W_Stage",     Name = "Obras no recinto",  Description = "Compra 1 palco novo",            Metric = "StagesBought",    Target = 1,     Reward = { IncomeMinutes = 180 } },
	{ Id = "W_Crates",    Name = "Colecionador",      Description = "Abre 40 Vinyl Crates",           Metric = "CratesOpened",    Target = 40,    Reward = { Crates = 5 } },
	{ Id = "W_Perfect",   Name = "Perfecionista",     Description = "Consegue 10 drops PERFEITOS",    Metric = "PerfectDrops",    Target = 10,    Reward = { IncomeMinutes = 120, Crates = 3 } },
	{ Id = "W_Tour",      Name = "Em digressão",      Description = "Faz 1 World Tour",               Metric = "WorldTours",      Target = 1,     Reward = { Discs = 10 } },
}

local MissionById: { [string]: MissionDef } = {}
for _, list in { DailyMissions, WeeklyMissions } do
	for _, def in list do
		assert(MissionById[def.Id] == nil, "Config/Retention: missão duplicada " .. def.Id)
		MissionById[def.Id] = table.freeze(def)
	end
end
for _, reward in DailyRewards do
	table.freeze(reward)
end

return table.freeze({
	DailyRewards = table.freeze(DailyRewards),
	ClaimCooldown = 20 * HOUR,
	StreakWindow = 48 * HOUR,
	MinIncomeClicksPerSecond = 5,

	DailyMissions = table.freeze(DailyMissions),
	WeeklyMissions = table.freeze(WeeklyMissions),
	MissionById = table.freeze(MissionById),
	DailyMissionCount = 3,
	WeeklyMissionCount = 2,
})
