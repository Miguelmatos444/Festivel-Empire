--!strict
--[[
	Config/Stages
	Os 12 palcos (4 eras): custo, requisitos de World Tour e envelope máximo do modelo.
	Width/Depth/Height são o envelope: o modelo (placeholder ou .fbx) tem de caber nestas medidas.
	Todos os palcos começam na mesma linha da frente e crescem para trás e para cima.
	Custos afinados por simulação (ver a tabela aprovada da Fase 5).
]]

local Types = require(script.Parent.Parent.Types)
local MapConfig = require(script.Parent.Map)

type StageDef = Types.StageDef
type TransitionTiming = Types.TransitionTiming

-- stylua: ignore
local List: { StageDef } = {
	{ Tier = 1,  Name = "Palco de paletes",     Era = "Underground", Cost = 0,      Width = 20, Depth = 12, Height = 8,   RequiredWorldTours = 0 },
	{ Tier = 2,  Name = "Palco de bairro",      Era = "Underground", Cost = 40e3,   Width = 28, Depth = 16, Height = 12,  RequiredWorldTours = 0 },
	{ Tier = 3,  Name = "Palco de praia",       Era = "Underground", Cost = 1.5e6,  Width = 36, Depth = 20, Height = 16,  RequiredWorldTours = 0 },
	{ Tier = 4,  Name = "Palco clube",          Era = "Ascensão",    Cost = 100e6,  Width = 44, Depth = 24, Height = 22,  RequiredWorldTours = 0 },
	{ Tier = 5,  Name = "Palco médio LED",      Era = "Ascensão",    Cost = 10e9,   Width = 52, Depth = 28, Height = 28,  RequiredWorldTours = 0 },
	{ Tier = 6,  Name = "Palco coberto arena",  Era = "Ascensão",    Cost = 1.5e12, Width = 60, Depth = 32, Height = 36,  RequiredWorldTours = 0 },
	{ Tier = 7,  Name = "Palco principal",      Era = "Estrelato",   Cost = 40e12,  Width = 68, Depth = 36, Height = 46,  RequiredWorldTours = 1 },
	{ Tier = 8,  Name = "Palco pirotécnico",    Era = "Estrelato",   Cost = 400e12, Width = 74, Depth = 40, Height = 56,  RequiredWorldTours = 1 },
	{ Tier = 9,  Name = "Mega palco",           Era = "Estrelato",   Cost = 4e15,   Width = 80, Depth = 44, Height = 66,  RequiredWorldTours = 2 },
	{ Tier = 10, Name = "Palco holográfico",    Era = "Lenda",       Cost = 30e15,  Width = 84, Depth = 46, Height = 76,  RequiredWorldTours = 3 },
	{ Tier = 11, Name = "Palco estratosférico", Era = "Lenda",       Cost = 200e15, Width = 88, Depth = 48, Height = 88,  RequiredWorldTours = 4 },
	{ Tier = 12, Name = "Palco orbital",        Era = "Lenda",       Cost = 1.5e18, Width = 90, Depth = 48, Height = 100, RequiredWorldTours = 5 },
}

-- Attachments que cada palco expõe no seu Root (usados por VFX, artistas e câmara)
local ATTACHMENT_NAMES: { string } = {
	"StageOrigin",
	"DJBooth",
	"Artist_1",
	"Artist_2",
	"Artist_3",
	"Artist_4",
	"Artist_5",
	"Artist_6",
	"Artist_7",
	"Pyro_ColdSparks_1",
	"Pyro_ColdSparks_2",
	"Pyro_CO2Cannon_1",
	"Pyro_CO2Cannon_2",
	"Pyro_Lasers_1",
	"Pyro_Lasers_2",
	"Pyro_Flamethrower_1",
	"Pyro_Flamethrower_2",
	"Speaker_L",
	"Speaker_R",
	"CameraFocus",
}

-- Animação de troca de palco (replicada; maior nas trocas de era)
local NORMAL_TRANSITION: TransitionTiming = { Dismantle = 1.0, Pause = 0, Build = 2.0 }
local ERA_TRANSITION: TransitionTiming = { Dismantle = 2.0, Pause = 0.8, Build = 3.5 }

-- Validação: palcos por ordem, custos crescentes e todos dentro da zona do palco do terreno
do
	local zone = MapConfig.Plots.StageZone
	local previousCost = -1
	for index, def in List do
		assert(def.Tier == index, "Config/Stages: tiers têm de estar por ordem")
		assert(def.Cost > previousCost, string.format("Config/Stages: custo do Tier %d tem de ser maior que o anterior", def.Tier))
		assert(
			def.Width <= zone.Width and def.Depth <= zone.Depth and def.Height <= zone.Height,
			string.format("Config/Stages: Tier %d excede a zona do palco", def.Tier)
		)
		previousCost = def.Cost
		table.freeze(def)
	end
end

return table.freeze({
	List = table.freeze(List),
	MaxTier = #List,
	AttachmentNames = table.freeze(ATTACHMENT_NAMES),

	-- Multiplicador global de Hype por tier (cumulativo): Tier t = PerTier ^ (t - 1)
	MultiplierPerTier = 1.6,

	-- Vinyl Crates (fase do gacha)
	CrateTiers = table.freeze({ 1, 4, 7, 10 }),
	SpecialCrateTier = 12,

	Transition = table.freeze({
		Normal = table.freeze(NORMAL_TRANSITION),
		Era = table.freeze(ERA_TRANSITION),
	}),
})
