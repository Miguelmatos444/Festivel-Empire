--!strict
--[[
	TraitCalc
	Cálculos puros dos Traços e do Remix (Fase 13B), partilhados servidor/cliente:
	sorteio (Random do servidor), valor, descrição, comparação (fusão fica com o melhor),
	custo do Remix e Cristais por fusão.
]]

local Types = require(script.Parent.Parent.Types)
local TraitsConfig = require(script.Parent.Parent.Config.Traits)
local CrystalsConfig = require(script.Parent.Parent.Config.Crystals)

type TraitDef = Types.TraitDef
type TraitTierDef = Types.TraitTierDef

local TraitCalc = {}

function TraitCalc.Get(id: string?): TraitDef?
	if not id or id == "" then
		return nil
	end
	return TraitsConfig.ById[id]
end

function TraitCalc.GetTier(id: string?): TraitTierDef?
	if not id or id == "" then
		return nil
	end
	return TraitsConfig.TiersById[id]
end

function TraitCalc.GetTierIndex(id: string?): number
	return if id then TraitsConfig.TierIndex[id] or 0 else 0
end

-- Válido: os dois vazios (sem traço) ou os dois existentes
function TraitCalc.IsValid(traitId: string, tierId: string): boolean
	if traitId == "" and tierId == "" then
		return true
	end
	return TraitsConfig.ById[traitId] ~= nil and TraitsConfig.TiersById[tierId] ~= nil
end

function TraitCalc.GetValue(traitId: string?, tierId: string?): number
	local def = TraitCalc.Get(traitId)
	local index = TraitCalc.GetTierIndex(tierId)
	if not def or index == 0 then
		return 0
	end
	return def.Values[index] or 0
end

-- Sorteia a raridade do traço (pesos) e depois o traço (igual probabilidade)
function TraitCalc.Roll(rng: Random): (string, string)
	local roll = rng:NextNumber() * 100
	local tierId = TraitsConfig.Tiers[1].Id
	for _, tier in TraitsConfig.Tiers do
		roll -= tier.Weight
		if roll < 0 then
			tierId = tier.Id
			break
		end
	end
	local list = TraitsConfig.List
	return list[rng:NextInteger(1, #list)].Id, tierId
end

local function percent(value: number): string
	return string.format("%d%%", math.floor(value * 100 + 0.5))
end

-- Efeito do traço em texto (ex.: "+20% Hype deste artista")
function TraitCalc.DescribeEffect(traitId: string?, tierId: string?): string
	local def = TraitCalc.Get(traitId)
	if not def then
		return "Sem traço"
	end
	local value = TraitCalc.GetValue(traitId, tierId)
	local kind = def.Kind
	if kind == "ArtistHype" then
		return "+" .. percent(value) .. " Hype deste artista"
	elseif kind == "ClickPower" then
		return "+" .. percent(value) .. " Hype por batida"
	elseif kind == "Energy" then
		return "+" .. percent(value) .. " energia do Bass Drop"
	elseif kind == "BoostExtend" then
		return string.format("+%.1f s de boost do Bass Drop", value)
	elseif kind == "MachineCooldown" then
		return "−" .. percent(value) .. " recarga do lança-chamas"
	elseif kind == "PassiveHype" then
		return "+" .. percent(value) .. " Hype passivo global"
	end
	return ""
end

-- "Voz Potente (Raro): +20% Hype deste artista"
function TraitCalc.Describe(traitId: string?, tierId: string?): string
	local def = TraitCalc.Get(traitId)
	local tier = TraitCalc.GetTier(tierId)
	if not def or not tier then
		return "Sem traço"
	end
	return string.format("%s (%s): %s", def.Name, tier.Name, TraitCalc.DescribeEffect(traitId, tierId))
end

-- O traço A é melhor que o B? (raridade do traço, depois valor)
function TraitCalc.IsBetter(aTrait: string, aTier: string, bTrait: string, bTier: string): boolean
	local aIndex, bIndex = TraitCalc.GetTierIndex(aTier), TraitCalc.GetTierIndex(bTier)
	if aIndex ~= bIndex then
		return aIndex > bIndex
	end
	return TraitCalc.GetValue(aTrait, aTier) > TraitCalc.GetValue(bTrait, bTier)
end

-- Custo do Remix pela família da raridade do artista
function TraitCalc.GetRemixCost(family: string): number
	return CrystalsConfig.RemixCost[family] or CrystalsConfig.RemixCost.Common
end

-- Cristais ganhos numa fusão que leva o artista a `newStars`
function TraitCalc.GetFusionCrystals(family: string, newStars: number): number
	local byFamily = CrystalsConfig.Fusion[family]
	return if byFamily then byFamily[newStars] or 0 else 0
end

return TraitCalc
