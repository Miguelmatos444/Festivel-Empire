--!strict
--[[
	VariantCalc
	Cálculos puros das Variantes Brilhantes (Fase 13A), partilhados servidor/cliente:
	sorteio (Random do servidor), multiplicador do bónus, probabilidades para a UI.
]]

local Types = require(script.Parent.Parent.Types)
local VariantsConfig = require(script.Parent.Parent.Config.Variants)

type VariantDef = Types.VariantDef

local VariantCalc = {}

function VariantCalc.Get(id: string?): VariantDef?
	if not id or id == "" then
		return nil
	end
	return VariantsConfig.ById[id]
end

function VariantCalc.IsValid(id: string): boolean
	return id == "" or VariantsConfig.ById[id] ~= nil
end

-- Multiplicador do bónus do artista (1 = normal)
function VariantCalc.GetMultiplier(id: string?): number
	local def = VariantCalc.Get(id)
	return if def then 1 + def.Bonus else 1
end

--[[
	Sorteia a variante de um artista obtido: tenta da mais rara para a mais comum, cada
	uma com a sua chance (1/Chance). Devolve "" na grande maioria das vezes.
]]
function VariantCalc.Roll(rng: Random): string
	local list = VariantsConfig.List
	for index = #list, 1, -1 do
		local def = list[index]
		if rng:NextNumber() < 1 / def.Chance then
			return def.Id
		end
	end
	return ""
end

-- Probabilidade (0..1) de sair alguma variante numa abertura
function VariantCalc.GetAnyChance(): number
	local none = 1
	for _, def in VariantsConfig.List do
		none *= 1 - 1 / def.Chance
	end
	return 1 - none
end

return VariantCalc
