--!strict
--[[
	PrestigeCalc
	Regras do World Tour e da árvore, partilhadas por servidor e UI:
	Discos de Platina, Fama, custo/estado dos nós, efeitos agregados e tier inicial
	(sempre dentro dos bloqueios de World Tour dos palcos).
]]

local Types = require(script.Parent.Parent.Types)
local BigNum = require(script.Parent.Parent.Util.BigNum)
local NumberFormatter = require(script.Parent.Parent.Util.NumberFormatter)
local PrestigeConfig = require(script.Parent.Parent.Config.Prestige)
local SkillTreeConfig = require(script.Parent.Parent.Config.SkillTree)
local StageCalc = require(script.Parent.StageCalc)

type BigNum = BigNum.BigNum
type SkillEffects = Types.SkillEffects
type SkillNodeDef = Types.SkillNodeDef
type SkillNodeStatus = Types.SkillNodeStatus
type Tree = { [string]: number }

local PrestigeCalc = {}

-- Árvore -----------------------------------------------------------------------

function PrestigeCalc.GetLevel(tree: Tree, nodeId: string): number
	local level = tree[nodeId]
	if type(level) ~= "number" or level ~= level or level < 0 then
		return 0
	end
	local def = SkillTreeConfig.ById[nodeId]
	return math.min(math.floor(level), if def then def.MaxLevel else 0)
end

-- Custo (Discos) do próximo nível do nó
function PrestigeCalc.GetNextCost(def: SkillNodeDef, currentLevel: number): number
	return math.ceil(def.BaseCost * def.CostGrowth ^ currentLevel)
end

function PrestigeCalc.GetNodeStatus(tree: Tree, nodeId: string, discs: number): SkillNodeStatus
	local def = SkillTreeConfig.ById[nodeId]
	if not def then
		return "Locked"
	end
	local level = PrestigeCalc.GetLevel(tree, nodeId)
	if level >= def.MaxLevel then
		return "Maxed"
	end
	local requirement = def.Requires
	if requirement and PrestigeCalc.GetLevel(tree, requirement) < (def.RequiresLevel or 1) then
		return "Locked"
	end
	if discs < PrestigeCalc.GetNextCost(def, level) then
		return "TooExpensive"
	end
	return "Available"
end

function PrestigeCalc.GetSkillEffects(tree: Tree): SkillEffects
	local totals: { [string]: number } = {}
	for _, def in SkillTreeConfig.List do
		local level = PrestigeCalc.GetLevel(tree, def.Id)
		if level > 0 then
			totals[def.Effect] = (totals[def.Effect] or 0) + def.PerLevel * level
		end
	end
	local function total(key: string): number
		return totals[key] or 0
	end
	local roadie = total("StartingHype")
	return {
		HypeMultiplier = 1 + total("HypeMultiplier"),
		ClickMultiplier = 1 + total("ClickMultiplier"),
		OfflineEfficiency = total("OfflineEfficiency"),
		ArtistBonus = total("ArtistBonus"),
		StartingHype = if roadie > 0 then 1000 * 10 ^ (roadie - 1) else 0,
		StartingGenerators = total("StartingGenerators"),
		StartTier = total("StartTier"),
		StageCostCut = total("StageCostCut"),
		StartEnergy = total("StartEnergy"),
		BoostBonus = total("BoostBonus"),
		WindowBonus = total("WindowBonus"),
		CooldownCut = total("CooldownCut"),
		DiscBonus = total("DiscBonus"),
		CrateCostCut = total("CrateCostCut"),
		PityReduction = total("PityReduction"),
	}
end

-- Descreve o efeito de um nó num dado nível (para a UI)
function PrestigeCalc.DescribeEffect(def: SkillNodeDef, level: number): string
	local value = def.PerLevel * level
	local effect = def.Effect
	local function percent(v: number): string
		return string.format("%d%%", math.floor(v * 100 + 0.5))
	end
	if effect == "HypeMultiplier" then
		return "+" .. percent(value) .. " Hype global"
	elseif effect == "ClickMultiplier" then
		return "+" .. percent(value) .. " Hype por batida"
	elseif effect == "OfflineEfficiency" then
		return "+" .. percent(value) .. " eficiência offline"
	elseif effect == "ArtistBonus" then
		return "+" .. percent(value) .. " no bónus dos artistas"
	elseif effect == "StartingHype" then
		return if level > 0 then "Começa com " .. NumberFormatter.format(1000 * 10 ^ (level - 1)) .. " Hype" else "Começa com 0 Hype"
	elseif effect == "StartingGenerators" then
		return string.format("4 primeiros geradores no nível %d", value)
	elseif effect == "StartTier" then
		return string.format("Começa no Tier %d", math.min(1 + value, PrestigeConfig.MaxStartTier))
	elseif effect == "StageCostCut" then
		return "−" .. percent(value) .. " custo dos palcos"
	elseif effect == "StartEnergy" then
		return string.format("Carga começa com +%d energia", value)
	elseif effect == "BoostBonus" then
		return string.format("Boost +%d s", value)
	elseif effect == "WindowBonus" then
		return string.format("Janela +%.2f s", value)
	elseif effect == "CooldownCut" then
		return "−" .. percent(value) .. " cooldowns"
	elseif effect == "DiscBonus" then
		return "+" .. percent(value) .. " Discos por World Tour"
	elseif effect == "CrateCostCut" then
		return "−" .. percent(value) .. " custo das crates"
	elseif effect == "PityReduction" then
		return string.format("Pity Lendário+ %d aberturas mais cedo", value)
	end
	return ""
end

-- World Tour -------------------------------------------------------------------

function PrestigeCalc.GetFameMultiplier(worldTours: number): number
	return PrestigeConfig.FamePerWorldTour ^ math.max(worldTours, 0)
end

-- Discos que um World Tour daria agora. extraBonus: ex.: Gamepass "Agente de Tour" (+0.25)
function PrestigeCalc.GetDiscsPreview(runHype: BigNum, stageTier: number, tree: Tree, extraBonus: number?): number
	if runHype.m <= 0 then
		return 0
	end
	local ratioLog = BigNum.log10(runHype) - math.log10(PrestigeConfig.HypeReference)
	local root = 10 ^ (ratioLog / 2)
	local tierFactor = 1 + PrestigeConfig.TierBonus * math.max(stageTier - PrestigeConfig.MinTier, 0)
	local discFactor = 1 + PrestigeCalc.GetSkillEffects(tree).DiscBonus + (extraBonus or 0)
	local discs = PrestigeConfig.DiscBase * root * tierFactor * discFactor
	if discs ~= discs or discs == math.huge then
		return 0
	end
	return math.floor(discs)
end

-- (pode, motivo) — o servidor valida o mesmo
function PrestigeCalc.CanWorldTour(stageTier: number, discsPreview: number): (boolean, string?)
	if stageTier < PrestigeConfig.MinTier then
		return false, string.format("Precisas do Tier %d (%s).", PrestigeConfig.MinTier, StageCalc.GetDef(PrestigeConfig.MinTier).Name)
	end
	if discsPreview < 1 then
		return false, "Ainda não ganharias nenhum Disco de Platina."
	end
	return true, nil
end

-- Tier inicial após o reset: nó "Palco Pré-montado", limitado a MaxStartTier e aos
-- World Tours exigidos por cada palco (nunca ultrapassa um bloqueio)
function PrestigeCalc.GetStartTier(tree: Tree, worldTours: number): number
	local wanted = math.min(1 + PrestigeCalc.GetSkillEffects(tree).StartTier, PrestigeConfig.MaxStartTier)
	local tier = 1
	for candidate = 2, wanted do
		if StageCalc.GetDef(candidate).RequiredWorldTours <= worldTours then
			tier = candidate
		else
			break
		end
	end
	return tier
end

return table.freeze(PrestigeCalc)
