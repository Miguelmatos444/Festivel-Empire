--!strict
--[[
	StageCalc
	Regras dos palcos partilhadas por servidor e UI: multiplicador, estado de
	compra de cada tier, troca de era e lista de desbloqueios.
]]

local Types = require(script.Parent.Parent.Types)
local StagesConfig = require(script.Parent.Parent.Config.Stages)
local EquipmentConfig = require(script.Parent.Parent.Config.Equipment)
local PyroConfig = require(script.Parent.Parent.Config.Pyro)
local PrestigeConfig = require(script.Parent.Parent.Config.Prestige)

type StageDef = Types.StageDef
type StageStatus = Types.StageStatus
type TransitionTiming = Types.TransitionTiming

local StageCalc = {}

function StageCalc.GetDef(tier: number): StageDef
	local clamped = math.clamp(math.floor(tier), 1, StagesConfig.MaxTier)
	return StagesConfig.List[clamped]
end

-- Multiplicador global de Hype do tier (cumulativo)
function StageCalc.GetMultiplier(tier: number): number
	local clamped = math.clamp(math.floor(tier), 1, StagesConfig.MaxTier)
	return StagesConfig.MultiplierPerTier ^ (clamped - 1)
end

function StageCalc.IsEraChange(fromTier: number, toTier: number): boolean
	return StageCalc.GetDef(fromTier).Era ~= StageCalc.GetDef(toTier).Era
end

function StageCalc.GetTransitionTiming(fromTier: number, toTier: number): TransitionTiming
	if StageCalc.IsEraChange(fromTier, toTier) then
		return StagesConfig.Transition.Era
	end
	return StagesConfig.Transition.Normal
end

-- Tempos de uma transição conforme o tipo ("Prestige" = reset do World Tour)
function StageCalc.GetTimingForKind(kind: string?, fromTier: number, toTier: number): TransitionTiming
	if kind == "Prestige" then
		return PrestigeConfig.Transition
	end
	return StageCalc.GetTransitionTiming(fromTier, toTier)
end

function StageCalc.GetTransitionDuration(timing: TransitionTiming): number
	return timing.Dismantle + timing.Pause + timing.Build
end

-- Estado do tier para um jogador no tier `currentTier` com `worldTours` World Tours.
-- (O saldo de Hype é verificado à parte: "Available" significa só "é o próximo e os requisitos estão cumpridos".)
function StageCalc.GetStatus(tier: number, currentTier: number, worldTours: number): StageStatus
	if tier == currentTier then
		return "Current"
	elseif tier < currentTier then
		return "Owned"
	elseif tier > currentTier + 1 then
		return "NeedPrevious"
	elseif worldTours < StageCalc.GetDef(tier).RequiredWorldTours then
		return "NeedWorldTours"
	end
	return "Available"
end

-- Textos do que o tier desbloqueia (equipamentos, pirotecnia, Vinyl Crates)
function StageCalc.GetUnlocks(tier: number): { string }
	local unlocks: { string } = {}
	for _, def in EquipmentConfig.List do
		if def.RequiredTier == tier then
			table.insert(unlocks, def.Name)
		end
	end
	for _, def in PyroConfig.List do
		if def.RequiredTier == tier then
			table.insert(unlocks, def.Name)
		end
	end
	if tier == StagesConfig.SpecialCrateTier then
		table.insert(unlocks, "Vinyl Crate especial")
	elseif table.find(StagesConfig.CrateTiers, tier) then
		table.insert(unlocks, "Vinyl Crate")
	end
	return unlocks
end

return table.freeze(StageCalc)
