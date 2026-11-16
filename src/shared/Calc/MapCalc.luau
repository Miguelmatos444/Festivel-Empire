--!strict
--[[
	MapCalc
	Posições do mapa a partir de Config/Map (puro, sem instâncias).
	Espaço local de um terreno: X lateral, -Z aponta para a praça (frente),
	profundidade "depth" medida a partir da frente do terreno.
]]

local MapConfig = require(script.Parent.Parent.Config.Map)
local StagesConfig = require(script.Parent.Parent.Config.Stages)
local Types = require(script.Parent.Parent.Types)

local MapCalc = {}

-- CFrame do centro do terreno ao nível do chão, com LookVector virado para a praça
function MapCalc.GetPlotCFrame(index: number): CFrame
	local plots = MapConfig.Plots
	local angle = math.rad((index - 1) * 360 / plots.Count)
	local position = Vector3.new(math.sin(angle) * plots.RingRadius, 0, math.cos(angle) * plots.RingRadius)
	return CFrame.lookAt(position, Vector3.zero)
end

-- Ponto no espaço local do terreno (x lateral, y altura, depth a partir da frente)
function MapCalc.PlotPoint(index: number, x: number, y: number, depth: number): CFrame
	return MapCalc.GetPlotCFrame(index) * CFrame.new(x, y, -MapConfig.Plots.Depth / 2 + depth)
end

-- Ponto no chão da praça a partir de um ângulo (graus) e raio
function MapCalc.PlazaPoint(angleDegrees: number, radius: number, y: number): CFrame
	local angle = math.rad(angleDegrees)
	local position = Vector3.new(math.sin(angle) * radius, y, math.cos(angle) * radius)
	return CFrame.lookAt(position, Vector3.new(0, y, 0))
end

-- true se a posição (mundo) está dentro dos limites do terreno `index` (vista de cima)
function MapCalc.IsInsidePlot(index: number, position: Vector3): boolean
	local plots = MapConfig.Plots
	local localPosition = MapCalc.GetPlotCFrame(index):PointToObjectSpace(position)
	return math.abs(localPosition.X) <= plots.Width / 2 and math.abs(localPosition.Z) <= plots.Depth / 2
end

-- Terreno em que a posição está (nil = praça / fora dos terrenos)
function MapCalc.GetPlotIndexAt(position: Vector3): number?
	for index = 1, MapConfig.Plots.Count do
		if MapCalc.IsInsidePlot(index, position) then
			return index
		end
	end
	return nil
end

function MapCalc.GetStageDef(tier: number): Types.StageDef
	local clamped = math.clamp(math.floor(tier), 1, StagesConfig.MaxTier)
	return StagesConfig.List[clamped]
end

return table.freeze(MapCalc)
