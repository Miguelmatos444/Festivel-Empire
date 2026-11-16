--!strict
--[[
	MapService
	Constrói o mapa único em Workspace/Map a partir de Config/Map:

	  Workspace/Map
	  ├── Ground, Boundary
	  ├── Plaza                 (ServerStorage/Assets/Plaza ou placeholder)
	  └── Plots/Plot_1..Plot_6  (Model, PrimaryPart = PlotBase)
	      ├── PlotBase          Attachments: Spawn, Sign, StageOrigin, CrowdArea, Wing_L, Wing_R
	      ├── Curbs             limites com entrada virada para a praça
	      ├── Spawn             SpawnLocation do dono
	      ├── Sign              placa do dono (ServerStorage/Assets/PlotSign ou placeholder)
	      └── Stage             palco do tier atual (gerido pelo StageService)

	Atributos de cada Plot: PlotId, OwnerUserId (0 = livre).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MapConfig = require(ReplicatedStorage.Shared.Config.Map)
local DanceFloorConfig = require(ReplicatedStorage.Shared.Config.DanceFloor)
local MapCalc = require(ReplicatedStorage.Shared.Calc.MapCalc)
local Placeholders = require(script.Parent.Parent.World.Placeholders)
local Stations = require(script.Parent.Parent.World.Stations)
local Assets = require(script.Parent.Parent.World.Assets)
local Dressing = require(script.Parent.Parent.World.Dressing)

local MapService = {}

local mapFolder: Folder? = nil
local plotModels: { Model } = {}

local function addBaseAttachment(base: BasePart, name: string, x: number, depth: number, yaw: number)
	local plots = MapConfig.Plots
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.CFrame = CFrame.new(x, base.Size.Y / 2, -plots.Depth / 2 + depth) * CFrame.Angles(0, yaw, 0)
	attachment.Parent = base
end

local function buildBoundary(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Boundary"
	local half = MapConfig.Ground.Size / 2
	local boundary = MapConfig.Boundary
	local length = MapConfig.Ground.Size + boundary.Thickness * 2
	local placements = {
		{ Vector3.new(length, boundary.Height, boundary.Thickness), Vector3.new(0, boundary.Height / 2, half + boundary.Thickness / 2) },
		{ Vector3.new(length, boundary.Height, boundary.Thickness), Vector3.new(0, boundary.Height / 2, -half - boundary.Thickness / 2) },
		{ Vector3.new(boundary.Thickness, boundary.Height, length), Vector3.new(half + boundary.Thickness / 2, boundary.Height / 2, 0) },
		{ Vector3.new(boundary.Thickness, boundary.Height, length), Vector3.new(-half - boundary.Thickness / 2, boundary.Height / 2, 0) },
	}
	for index, placement in placements do
		local wall = Placeholders.NewPart(
			"Wall_" .. index,
			placement[1],
			CFrame.new(placement[2]),
			Color3.new(1, 1, 1),
			Enum.Material.SmoothPlastic,
			folder
		)
		wall.Transparency = 1
		wall.CanQuery = false
	end
	folder.Parent = parent
end

local function buildCurbs(model: Model, base: BasePart, color: Color3)
	local plots = MapConfig.Plots
	local folder = Instance.new("Folder")
	folder.Name = "Curbs"

	local height, thickness = plots.CurbHeight, plots.CurbThickness
	local y = base.Size.Y / 2 + height / 2
	local frontSegment = (plots.Width - plots.EntranceWidth) / 2
	local pieces = {
		{ "Back", Vector3.new(plots.Width, height, thickness), Vector3.new(0, y, plots.Depth / 2 - thickness / 2) },
		{ "Left", Vector3.new(thickness, height, plots.Depth), Vector3.new(-(plots.Width / 2 - thickness / 2), y, 0) },
		{ "Right", Vector3.new(thickness, height, plots.Depth), Vector3.new(plots.Width / 2 - thickness / 2, y, 0) },
		{
			"FrontLeft",
			Vector3.new(frontSegment, height, thickness),
			Vector3.new(-(plots.EntranceWidth / 2 + frontSegment / 2), y, -plots.Depth / 2 + thickness / 2),
		},
		{
			"FrontRight",
			Vector3.new(frontSegment, height, thickness),
			Vector3.new(plots.EntranceWidth / 2 + frontSegment / 2, y, -plots.Depth / 2 + thickness / 2),
		},
	}
	for _, piece in pieces do
		local name = piece[1] :: string
		local size = piece[2] :: Vector3
		local offset = piece[3] :: Vector3
		Placeholders.NewPart(name, size, base.CFrame * CFrame.new(offset), color, Enum.Material.Neon, folder)
	end
	folder.Parent = model
end

-- Pista de dança à frente do palco (Config/DanceFloor). Os azulejos têm Col/Row (linha 1 = junto
-- ao palco); as cores são animadas no cliente (DanceFloorController).
local function buildDanceFloor(model: Model, base: BasePart)
	local config = DanceFloorConfig
	if not config.Enabled then
		return
	end
	local plots = MapConfig.Plots
	local folder = Instance.new("Model")
	folder.Name = "DanceFloor"
	local size = config.TileSize
	local width = config.Columns * size
	local front = plots.StageFront - config.StageGap -- profundidade da linha 1 (lado do palco)
	local depth = config.Rows * size
	local top = plots.BaseThickness / 2 -- topo da base, no espaço da base

	local under = Placeholders.NewPart(
		"Base",
		Vector3.new(width + 1, config.Height * 0.5, depth + 1),
		base.CFrame * CFrame.new(0, top + config.Height * 0.25, -plots.Depth / 2 + front - depth / 2),
		config.BaseColor,
		Enum.Material.SmoothPlastic,
		folder
	)
	under.CanQuery = false

	-- Cor inicial já no servidor (Underground, néon suave): a pista nunca fica preta,
	-- mesmo antes de o cliente a animar
	local palette = config.Palettes.Underground
	for row = 1, config.Rows do
		for col = 1, config.Columns do
			local x = -width / 2 + (col - 0.5) * size
			local tileDepth = front - (row - 0.5) * size
			local tile = Placeholders.NewPart(
				"Tile",
				Vector3.new(size - config.Gap, config.Height, size - config.Gap),
				base.CFrame * CFrame.new(x, top + config.Height / 2, -plots.Depth / 2 + tileDepth),
				palette[(col + row) % #palette + 1]:Lerp(Color3.new(0, 0, 0), config.IdleDim),
				Enum.Material.Neon,
				folder
			)
			tile.CanQuery = false
			tile.CastShadow = false
			tile:SetAttribute("Col", col)
			tile:SetAttribute("Row", row)
		end
	end
	folder.Parent = model
end

local function buildPlot(index: number, parent: Instance): Model
	local plots = MapConfig.Plots
	local color = plots.Colors[index] or Color3.new(1, 1, 1)

	local model = Instance.new("Model")
	model.Name = "Plot_" .. index
	model:SetAttribute("PlotId", index)
	model:SetAttribute("OwnerUserId", 0)

	local base = Placeholders.NewPart(
		"PlotBase",
		Vector3.new(plots.Width, plots.BaseThickness, plots.Depth),
		MapCalc.GetPlotCFrame(index) * CFrame.new(0, plots.BaseThickness / 2, 0),
		Color3.fromRGB(70, 68, 80),
		Enum.Material.Concrete,
		model
	)
	model.PrimaryPart = base

	local zone = plots.StageZone
	local stageMid = (plots.StageFront + plots.StageBack) / 2
	local wingX = zone.Width / 2 + plots.WingWidth / 2
	addBaseAttachment(base, "Spawn", 0, plots.SpawnDepth, math.pi) -- virado para o palco
	addBaseAttachment(base, "Sign", 0, plots.SignDepth, 0) -- virado para a praça
	addBaseAttachment(base, "StageOrigin", 0, plots.StageFront, 0)
	addBaseAttachment(base, "CrowdArea", 0, (plots.CrowdStart + plots.CrowdEnd) / 2, math.pi)
	addBaseAttachment(base, "Wing_L", -wingX, stageMid, 0)
	addBaseAttachment(base, "Wing_R", wingX, stageMid, 0)

	buildCurbs(model, base, color)
	buildDanceFloor(model, base)
	Stations.Build(model, base) -- postos (Melhorias, Artistas, …) com título

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = base.CFrame
		* CFrame.new(0, plots.BaseThickness / 2 + 0.5, -plots.Depth / 2 + plots.SpawnDepth)
		* CFrame.Angles(0, math.pi, 0)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Duration = 0
	spawn.Color = color
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.4
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = model

	local sign = Assets.GetSignTemplate():Clone()
	sign.Name = "Sign"
	local signRoot = Assets.GetRoot(sign)
	local signAttachment = base:FindFirstChild("Sign")
	if signRoot and signAttachment and signAttachment:IsA("Attachment") then
		Assets.PivotRoot(sign, signAttachment.WorldCFrame * CFrame.new(0, signRoot.Size.Y / 2, 0))
	end
	sign.Parent = model

	model.Parent = parent
	return model
end

-- API pública ------------------------------------------------------------------

function MapService.GetPlotModel(index: number): Model?
	return plotModels[index]
end

function MapService.GetPlotCount(): number
	return #plotModels
end

function MapService.GetMapFolder(): Folder?
	return mapFolder
end

-- Ciclo de vida --------------------------------------------------------------

function MapService.Init()
	local previous = Workspace:FindFirstChild("Map")
	if previous then
		previous:Destroy()
	end
	-- O chão do mapa substitui o Baseplate do modelo base do Rojo
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "Map"

	local ground = MapConfig.Ground
	local groundPart = Placeholders.NewPart(
		"Ground",
		Vector3.new(ground.Size, ground.Thickness, ground.Size),
		CFrame.new(0, -ground.Thickness / 2, 0),
		ground.Color,
		Enum.Material.Grass,
		folder
	)
	groundPart.Locked = true

	buildBoundary(folder)

	local plaza = Assets.GetPlazaTemplate():Clone()
	plaza.Name = "Plaza"
	local plazaRoot = Assets.GetRoot(plaza)
	if plazaRoot then
		Assets.PivotRoot(plaza, CFrame.new(0, plazaRoot.Size.Y / 2, 0))
	end
	-- Decoração da praça (modelo à parte, para não depender de uma praça exportada antes da Fase 11)
	local decor = Assets.GetPlazaDecorTemplate():Clone()
	decor.Name = "PlazaDecor"
	local decorRoot = Assets.GetRoot(decor)
	if decorRoot then
		Assets.PivotRoot(decor, CFrame.new(0, decorRoot.Size.Y / 2, 0))
	end
	decor.Parent = plaza
	Dressing.DressPlaza(plaza) -- adereços do Blender (Props), se existirem
	plaza.Parent = folder

	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = folder
	for index = 1, MapConfig.Plots.Count do
		plotModels[index] = buildPlot(index, plotsFolder)
	end

	folder.Parent = Workspace
	mapFolder = folder
end

function MapService.Start() end

return MapService
