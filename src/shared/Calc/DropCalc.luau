--!strict
--[[
	DropCalc
	Cálculos puros do Bass Drop, partilhados por servidor e cliente:
	ritmo, avaliação do timing, máscara de máquinas, sinergias e multiplicador.
]]

local Types = require(script.Parent.Parent.Types)
local BassDropConfig = require(script.Parent.Parent.Config.BassDrop)
local PyroConfig = require(script.Parent.Parent.Config.Pyro)

type GradeDef = Types.GradeDef
type DropGrade = Types.DropGrade
type SynergyDef = Types.SynergyDef

local DropCalc = {}

function DropCalc.GetBeatInterval(): number
	return 60 / BassDropConfig.BPM
end

function DropCalc.GetBuildUpDuration(): number
	return BassDropConfig.BuildUpBeats * DropCalc.GetBeatInterval()
end

-- Avalia a diferença (s) entre o clique e o instante do drop. nil = fora da janela.
function DropCalc.GradeOffset(offset: number): GradeDef?
	if offset < -BassDropConfig.WindowBefore or offset > BassDropConfig.WindowAfter then
		return nil
	end
	local distance = math.abs(offset)
	for _, grade in BassDropConfig.Grades do
		if distance <= grade.MaxOffset then
			return grade
		end
	end
	return nil
end

function DropCalc.GetGradeDef(grade: DropGrade): GradeDef?
	for _, def in BassDropConfig.Grades do
		if def.Grade == grade then
			return def
		end
	end
	return nil
end

-- Máscara <-> lista de ids (ordem da Config)
function DropCalc.MaskToIds(mask: number): { string }
	local ids: { string } = {}
	for _, def in PyroConfig.List do
		if bit32.band(mask, def.Bit) ~= 0 then
			table.insert(ids, def.Id)
		end
	end
	return ids
end

function DropCalc.IdsToMask(ids: { string }): number
	local mask = 0
	for _, id in ids do
		local def = PyroConfig.ById[id]
		if def then
			mask = bit32.bor(mask, def.Bit)
		end
	end
	return mask
end

function DropCalc.GetSynergies(ids: { string }): { SynergyDef }
	local present: { [string]: boolean } = {}
	for _, id in ids do
		present[id] = true
	end
	local active: { SynergyDef } = {}
	for _, synergy in PyroConfig.Synergies do
		local complete = true
		for _, required in synergy.Requires do
			if not present[required] then
				complete = false
				break
			end
		end
		if complete then
			table.insert(active, synergy)
		end
	end
	return active
end

-- Devolve (multiplicador final arredondado a 0.1, sinergias ativas)
function DropCalc.ComputeMultiplier(ids: { string }, factor: number): (number, { SynergyDef })
	if #ids == 0 then
		return BassDropConfig.MinMultiplier, {}
	end
	local sum = 0
	for _, id in ids do
		local def = PyroConfig.ById[id]
		if def then
			sum += def.BaseMultiplier
		end
	end
	local synergies = DropCalc.GetSynergies(ids)
	local synergyProduct = 1
	for _, synergy in synergies do
		synergyProduct *= synergy.Multiplier
	end
	local value = math.clamp(sum * synergyProduct * factor, BassDropConfig.MinMultiplier, BassDropConfig.MaxMultiplier)
	return math.floor(value * 10 + 0.5) / 10, synergies
end

return table.freeze(DropCalc)
