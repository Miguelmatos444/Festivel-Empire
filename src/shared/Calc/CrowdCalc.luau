--!strict
--[[
	CrowdCalc
	Tamanho do público de um festival (partilhado servidor/cliente):
	  - o servidor calcula o nível pelo Hype ganho na run e publica-o em FE_CrowdLevel;
	  - o cliente converte nível + World Tours no nº de pessoas a mostrar.
]]

local AmbienceConfig = require(script.Parent.Parent.Config.Ambience)
local Types = require(script.Parent.Parent.Types)

local CrowdCalc = {}

-- Nível (índice de Config/Ambience.Crowd.ByHype) para o Hype ganho na run
function CrowdCalc.GetLevel(runHype: Types.BigNumData): number
	local log = if runHype.m > 0 then runHype.e + math.log10(runHype.m) else -math.huge
	local level = 1
	for index, entry in AmbienceConfig.Crowd.ByHype do
		if entry.MinHype <= 0 or log >= math.log10(entry.MinHype) - 1e-9 then
			level = index
		end
	end
	return level
end

-- Nº de pessoas no público (próprio terreno ou visto de fora)
function CrowdCalc.GetCount(level: number, worldTours: number, isOwn: boolean): number
	local config = AmbienceConfig.Crowd
	local list = config.ByHype
	local entry = list[math.clamp(math.floor(level), 1, #list)]
	local tours = math.max(0, math.floor(worldTours))
	if isOwn then
		return math.min(entry.Own + tours * config.PerWorldTourOwn, config.MaxOwn)
	end
	return math.min(entry.Other + tours * config.PerWorldTourOther, config.MaxOther)
end

return table.freeze(CrowdCalc)
