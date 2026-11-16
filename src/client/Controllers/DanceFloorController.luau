--!strict
--[[
	DanceFloorController
	Anima as cores da pista de dança de cada terreno (Plot_N/DanceFloor, criada pelo
	MapService com azulejos "Tile" com atributos Col/Row; linha 1 = junto ao palco).
	  - Fora do drop: néon suave, onda de cor a cada batida.
	  - Build-up/janela do dono: xadrez a piscar ao ritmo.
	  - Boost do Bass Drop do dono: Neon com uma onda que sai do palco para o público.
	Cores pela era do palco do dono (atributo Tier do modelo Stage do terreno).
	LOD (Config/Lod.Crowd): a do próprio jogador anima a cada frame; as outras só a cada
	batida e até AnimatedDistance; mais longe ficam paradas.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local DanceFloorConfig = require(ReplicatedStorage.Shared.Config.DanceFloor)
local LodConfig = require(ReplicatedStorage.Shared.Config.Lod)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
local StageCalc = require(ReplicatedStorage.Shared.Calc.StageCalc)
local AudioController = require(script.Parent.AudioController)
local BassDropController = require(script.Parent.BassDropController)

type DropResolved = Types.DropResolved
type FloorState = "Idle" | "BuildUp" | "Boost"

type Tile = {
	Part: BasePart,
	Col: number,
	Row: number,
}

type Floor = {
	Plot: Instance,
	Model: Instance,
	Tiles: { Tile },
	Center: Vector3,
	Material: Enum.Material?,
	LastBeat: number,
}

local BLACK = Color3.new(0, 0, 0)

local DanceFloorController = {}

local trove = Trove.new()
local floors: { [Instance]: Floor } = {}
local otherBoostUntil: { [number]: number } = {}

local function numberAttribute(instance: Instance?, name: string): number
	local value = if instance then instance:GetAttribute(name) else nil
	return if type(value) == "number" then value else 0
end

local function getPalette(plot: Instance): { Color3 }
	local stage = plot:FindFirstChild("Stage")
	local tier = math.max(1, numberAttribute(stage, "Tier"))
	return DanceFloorConfig.Palettes[StageCalc.GetDef(tier).Era]
end

local function getState(plot: Instance, now: number): FloorState
	local owner = numberAttribute(plot, "OwnerUserId")
	if owner <= 0 then
		return "Idle"
	end
	if owner == Players.LocalPlayer.UserId then
		local state = BassDropController.Get()
		local phase = if state then state.Phase else nil
		if phase == "Boost" and BassDropController.GetBoostMultiplier() > 1 then
			return "Boost"
		elseif phase == "BuildUp" or phase == "Window" then
			return "BuildUp"
		end
		return "Idle"
	end
	return if (otherBoostUntil[owner] or 0) > now then "Boost" else "Idle"
end

local function paint(floor: Floor, state: FloorState, beat: number, pulse: number)
	local config = DanceFloorConfig
	local palette = getPalette(floor.Plot)
	local material = Enum.Material.Neon -- luz própria: visível ao fim da tarde
	local setMaterial = floor.Material ~= material
	floor.Material = material
	for _, tile in floor.Tiles do
		local color = palette[(tile.Col + tile.Row + beat) % #palette + 1]
		local dim: number
		if state == "Boost" then
			local lit = (beat - tile.Row) % config.BoostWaveLength == 0
			dim = if lit then config.BoostOnDim else config.BoostOffDim
		elseif state == "BuildUp" then
			local lit = (tile.Col + tile.Row + beat) % 2 == 0
			dim = if lit then config.BuildUpOnDim else config.BuildUpOffDim
		else
			color = palette[(tile.Col + beat) % #palette + 1]
			dim = config.IdleDim - config.IdlePulse * pulse
		end
		local target = color:Lerp(BLACK, math.clamp(dim, 0, 1))
		local part = tile.Part
		if part.Color ~= target then
			part.Color = target
		end
		if setMaterial then
			part.Material = material
		end
	end
end

local function update()
	local now = os.clock()
	local beat = AudioController.GetBeatIndex()
	local pulse = AudioController.GetBeatPulse()
	local camera = Workspace.CurrentCamera
	local origin = if camera then camera.CFrame.Position else Vector3.zero
	local myUserId = Players.LocalPlayer.UserId
	for _, floor in floors do
		if floor.Model.Parent == nil or #floor.Tiles == 0 then
			continue
		end
		local isMine = numberAttribute(floor.Plot, "OwnerUserId") == myUserId
		if isMine then
			paint(floor, getState(floor.Plot, now), beat, pulse)
		elseif beat ~= floor.LastBeat and (floor.Center - origin).Magnitude <= LodConfig.Crowd.AnimatedDistance then
			floor.LastBeat = beat
			paint(floor, getState(floor.Plot, now), beat, 0)
		end
	end
end

-- Os azulejos podem chegar aos poucos (StreamingEnabled): cada um entra na pista quando aparece
local function addTile(floor: Floor, child: Instance)
	local col = child:GetAttribute("Col")
	local row = child:GetAttribute("Row")
	if not child:IsA("BasePart") or type(col) ~= "number" or type(row) ~= "number" then
		return
	end
	for _, tile in floor.Tiles do
		if tile.Part == child then
			return
		end
	end
	child.Material = Enum.Material.Neon
	table.insert(floor.Tiles, { Part = child, Col = col, Row = row })
	local sum = Vector3.zero
	for _, tile in floor.Tiles do
		sum += tile.Part.Position
	end
	floor.Center = sum / #floor.Tiles
	floor.LastBeat = -1 -- repinta já
end

local function addFloor(plot: Instance, model: Instance)
	if floors[model] then
		return
	end
	local floor: Floor = {
		Plot = plot,
		Model = model,
		Tiles = {},
		Center = Vector3.zero,
		Material = Enum.Material.Neon,
		LastBeat = -1,
	}
	floors[model] = floor
	for _, child in model:GetChildren() do
		addTile(floor, child)
	end
	trove:Connect(model.ChildAdded, function(child: Instance)
		addTile(floor, child)
	end)
	trove:Connect(model.ChildRemoved, function(child: Instance)
		for index, tile in floor.Tiles do
			if tile.Part == child then
				table.remove(floor.Tiles, index)
				break
			end
		end
	end)
	trove:Connect(model.AncestryChanged, function()
		if not model:IsDescendantOf(Workspace) then
			floors[model] = nil
		end
	end)
	if #floor.Tiles > 0 then
		paint(floor, "Idle", 0, 0)
	end
	Diag.Log("DanceFloor", string.format("pista de %s ligada (%d azulejos já recebidos)", plot.Name, #floor.Tiles))
end

local function watchPlot(plot: Instance)
	local existing = plot:FindFirstChild("DanceFloor")
	if existing then
		addFloor(plot, existing)
	end
	-- Com StreamingEnabled a pista pode chegar (ou voltar) mais tarde
	trove:Connect(plot.ChildAdded, function(child: Instance)
		if child.Name == "DanceFloor" then
			addFloor(plot, child)
		end
	end)
end

local function onResolved(result: DropResolved)
	if result.Success and result.UserId ~= Players.LocalPlayer.UserId then
		otherBoostUntil[result.UserId] = os.clock() + DanceFloorConfig.OtherBoostSeconds
	end
end

function DanceFloorController.Init()
	trove:Add(BassDropController.Resolved:Connect(onResolved))
	trove:Connect(RunService.Heartbeat, update)
end

function DanceFloorController.Start()
	if not DanceFloorConfig.Enabled then
		return
	end
	trove:Add(task.spawn(function()
		local map = Workspace:WaitForChild("Map")
		local plots = map:WaitForChild("Plots")
		for _, plot in plots:GetChildren() do
			task.spawn(watchPlot, plot)
		end
		trove:Connect(plots.ChildAdded, function(plot: Instance)
			task.spawn(watchPlot, plot)
		end)
	end))
end

return DanceFloorController
