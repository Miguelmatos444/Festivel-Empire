--!strict
--[[
	EquipmentCalc
	Cálculos puros de equipamento, partilhados por servidor e cliente:
	o preço que a loja mostra é exatamente o que o servidor cobra.
	Sem estado e sem efeitos secundários.
]]

local Types = require(script.Parent.Parent.Types)
local BigNum = require(script.Parent.Parent.Util.BigNum)
local EconomyConfig = require(script.Parent.Parent.Config.Economy)
local EquipmentConfig = require(script.Parent.Parent.Config.Equipment)

type BigNum = BigNum.BigNum
type EquipmentDef = Types.EquipmentDef
type BuyMode = Types.BuyMode
type UnlockState = Types.UnlockState
type Levels = { [string]: number }

local EquipmentCalc = {}

-- Validação da Config no arranque (falha cedo se o balanceamento for inválido)
do
	local bounds = EconomyConfig.GrowthRate
	for _, def in EquipmentConfig.List do
		assert(
			def.GrowthRate >= bounds.Min and def.GrowthRate <= bounds.Max,
			string.format("Equipment '%s': GrowthRate %.3f fora de [%.2f, %.2f]", def.Id, def.GrowthRate, bounds.Min, bounds.Max)
		)
		assert(def.BaseCost > 0 and def.BaseOutput > 0, "Equipment '" .. def.Id .. "': BaseCost/BaseOutput inválidos")
		local requirement = def.UnlockAfter
		if requirement then
			assert(EquipmentConfig.ById[requirement], "Equipment '" .. def.Id .. "': UnlockAfter desconhecido")
		end
	end
end

local function fixedAmount(mode: BuyMode): number
	if mode == "x10" then
		return 10
	elseif mode == "x100" then
		return 100
	end
	return 1
end

function EquipmentCalc.GetDef(id: string): EquipmentDef?
	return EquipmentConfig.ById[id]
end

-- Nível seguro (dados podem vir corrompidos)
function EquipmentCalc.GetLevel(levels: Levels, id: string): number
	local level = levels[id]
	if type(level) ~= "number" or level ~= level or level < 0 then
		return 0
	end
	return math.floor(level)
end

-- Marcos -------------------------------------------------------------------

function EquipmentCalc.GetMilestoneCount(level: number): number
	local milestones = EconomyConfig.Milestones
	local count = 0
	for _, threshold in milestones.Levels do
		if level >= threshold then
			count += 1
		end
	end
	local last = milestones.Levels[#milestones.Levels]
	if level > last then
		count += (level - last) // milestones.RepeatEvery
	end
	return count
end

function EquipmentCalc.GetNextMilestone(level: number): number
	local milestones = EconomyConfig.Milestones
	for _, threshold in milestones.Levels do
		if level < threshold then
			return threshold
		end
	end
	local last = milestones.Levels[#milestones.Levels]
	return last + ((level - last) // milestones.RepeatEvery + 1) * milestones.RepeatEvery
end

function EquipmentCalc.GetMilestoneMultiplier(level: number): BigNum
	return BigNum.powNumber(EconomyConfig.Milestones.Multiplier, EquipmentCalc.GetMilestoneCount(level))
end

-- Produção -----------------------------------------------------------------

-- Produção total de um equipamento no nível indicado (Hype/s ou Hype/batida)
function EquipmentCalc.GetOutput(def: EquipmentDef, level: number): BigNum
	if level <= 0 then
		return BigNum.ZERO
	end
	return BigNum.mul(BigNum.fromNumber(def.BaseOutput * level), EquipmentCalc.GetMilestoneMultiplier(level))
end

function EquipmentCalc.GetPassivePerSecond(levels: Levels): BigNum
	local total = BigNum.fromNumber(EconomyConfig.BasePassiveHypePerSecond)
	for _, def in EquipmentConfig.List do
		if def.Kind == "Generator" then
			total = BigNum.add(total, EquipmentCalc.GetOutput(def, EquipmentCalc.GetLevel(levels, def.Id)))
		end
	end
	return total
end

function EquipmentCalc.GetHypePerClick(levels: Levels): BigNum
	local total = BigNum.fromNumber(EconomyConfig.BaseHypePerClick)
	for _, def in EquipmentConfig.List do
		if def.Kind == "Click" then
			total = BigNum.add(total, EquipmentCalc.GetOutput(def, EquipmentCalc.GetLevel(levels, def.Id)))
		end
	end
	return total
end

-- Desbloqueio --------------------------------------------------------------

function EquipmentCalc.GetUnlockState(def: EquipmentDef, levels: Levels, stageTier: number): UnlockState
	local requirement = def.UnlockAfter
	if requirement and EquipmentCalc.GetLevel(levels, requirement) < 1 then
		return "Locked"
	end
	if stageTier < def.RequiredTier then
		return "TierTooLow"
	end
	return "Unlocked"
end

-- Compra -------------------------------------------------------------------

-- Devolve (níveis, custo total, tem saldo). Em "Max" sem saldo, cota 1 nível.
function EquipmentCalc.Quote(def: EquipmentDef, level: number, mode: BuyMode, budget: BigNum): (number, BigNum, boolean)
	if mode == "Max" then
		local count = math.min(
			BigNum.maxAffordable(def.BaseCost, def.GrowthRate, level, budget),
			EconomyConfig.Purchase.MaxLevelsPerPurchase
		)
		if count <= 0 then
			return 1, BigNum.geometricCost(def.BaseCost, def.GrowthRate, level, 1), false
		end
		return count, BigNum.geometricCost(def.BaseCost, def.GrowthRate, level, count), true
	end

	local count = fixedAmount(mode)
	local cost = BigNum.geometricCost(def.BaseCost, def.GrowthRate, level, count)
	return count, cost, BigNum.gte(budget, cost)
end

return table.freeze(EquipmentCalc)
