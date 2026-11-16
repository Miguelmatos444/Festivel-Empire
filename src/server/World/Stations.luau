--!strict
--[[
	Stations
	Constrói os postos à entrada de um terreno (Config/Stations): plataforma néon,
	modelo (override > adereço do Blender > versão simples), título flutuante
	(BillboardGui) e ProximityPrompt (nome Config/Stations.PromptName, atributo StationId).
	Chamado pelo MapService ao construir cada terreno. O cliente (StationsView) abre os
	painéis, esconde os prompts dos terrenos dos outros e atualiza os subtítulos.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local StationsConfig = require(ReplicatedStorage.Shared.Config.Stations)
local MapConfig = require(ReplicatedStorage.Shared.Config.Map)
local Assets = require(script.Parent.Assets)
local Placeholders = require(script.Parent.Placeholders)

type StationDef = StationsConfig.StationDef

local Stations = {}

local function setDecorative(model: Instance)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
end

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	return Placeholders.NewPart(name, size, cframe, color, material, parent)
end

-- Versões simples (sem modelo do Blender), com a origem no chão ao centro e a frente para -Z
local function buildFallback(def: StationDef, parent: Model)
	local color = def.Color
	local dark = Color3.fromRGB(40, 34, 60)
	local id = def.Id
	if id == "WorldTour" then
		part("Pedestal", Vector3.new(3, 2.5, 3), CFrame.new(0, 1.25, 0), dark, Enum.Material.Metal, parent)
		local globe = part("Globe", Vector3.new(4, 4, 4), CFrame.new(0, 4.6, 0), color, Enum.Material.SmoothPlastic, parent)
		globe.Shape = Enum.PartType.Ball
		local ring = part("Neon_Ring", Vector3.new(0.3, 5.4, 5.4), CFrame.new(0, 4.6, 0) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(math.rad(20), 0, 0), Color3.fromRGB(150, 240, 255), Enum.Material.Neon, parent)
		ring.Shape = Enum.PartType.Cylinder
	elseif id == "Missions" then
		part("Post", Vector3.new(0.6, 4, 0.6), CFrame.new(0, 2, 0.4), dark, Enum.Material.Metal, parent)
		part("Board", Vector3.new(4.5, 3.4, 0.4), CFrame.new(0, 4.6, 0), Color3.fromRGB(240, 235, 220), Enum.Material.SmoothPlastic, parent)
		part("Clip", Vector3.new(1.6, 0.5, 0.5), CFrame.new(0, 6.3, -0.05), Color3.fromRGB(190, 190, 200), Enum.Material.Metal, parent)
		for line = 1, 3 do
			part("Neon_Line", Vector3.new(3.2, 0.25, 0.1), CFrame.new(0, 5.6 - line * 0.75, -0.25), color, Enum.Material.Neon, parent)
		end
	elseif id == "Vip" then
		part("Chest", Vector3.new(4.5, 2.6, 3), CFrame.new(0, 1.3, 0), Color3.fromRGB(200, 150, 40), Enum.Material.Metal, parent)
		part("Lid", Vector3.new(4.7, 0.9, 3.2), CFrame.new(0, 3.05, 0), Color3.fromRGB(230, 180, 60), Enum.Material.Metal, parent)
		part("Neon_Band", Vector3.new(0.6, 3.6, 3.3), CFrame.new(0, 1.8, 0), Color3.fromRGB(255, 240, 150), Enum.Material.Neon, parent)
		local gem = part("Neon_Gem", Vector3.new(1.4, 1.4, 1.4), CFrame.new(0, 4.4, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), color, Enum.Material.Neon, parent)
		gem.Shape = Enum.PartType.Block
	elseif id == "Artists" then
		part("Crate", Vector3.new(4, 4, 4), CFrame.new(0, 2, 0), Color3.fromRGB(124, 92, 60), Enum.Material.WoodPlanks, parent)
		local disc = part("Neon_Vinyl", Vector3.new(0.3, 3.4, 3.4), CFrame.new(0, 2.4, -2.1) * CFrame.Angles(0, math.rad(90), 0), color, Enum.Material.Neon, parent)
		disc.Shape = Enum.PartType.Cylinder
	elseif id == "Stages" then
		part("Desk", Vector3.new(5, 3, 2.4), CFrame.new(0, 1.5, 0), dark, Enum.Material.Metal, parent)
		part("Neon_Front", Vector3.new(4.6, 0.4, 0.1), CFrame.new(0, 2.2, -1.25), color, Enum.Material.Neon, parent)
	else -- Upgrades
		part("Speaker", Vector3.new(3.4, 6, 3), CFrame.new(0, 3, 0), dark, Enum.Material.SmoothPlastic, parent)
		for index, y in { 4.4, 1.9 } do
			local cone = part("Neon_Cone" .. index, Vector3.new(0.3, 2.2, 2.2), CFrame.new(0, y, -1.55) * CFrame.Angles(0, math.rad(90), 0), color, Enum.Material.Neon, parent)
			cone.Shape = Enum.PartType.Cylinder
		end
	end
end

-- Modelo do posto: override em ServerStorage/Assets/Stations/<Id>, adereço do Blender ou versão simples
local function buildVisual(def: StationDef): Model
	local assets = ServerStorage:FindFirstChild("Assets")
	local folder = if assets then assets:FindFirstChild("Stations") else nil
	local custom = if folder then folder:FindFirstChild(def.Id) else nil
	if custom and custom:IsA("Model") then
		return custom:Clone()
	end
	local prop = def.Prop
	if prop then
		local template = Assets.GetProp(prop, "Y", def.PropHeight)
		if template then
			return template:Clone()
		end
	end
	local model = Instance.new("Model")
	buildFallback(def, model)
	return model
end

local function addTitle(def: StationDef, anchor: BasePart)
	local config = StationsConfig
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Title"
	billboard.Size = UDim2.new(config.TitleSize.X, 0, config.TitleSize.Y, 0)
	billboard.MaxDistance = config.TitleMaxDistance
	billboard.LightInfluence = 0
	billboard.AlwaysOnTop = false

	local title = Instance.new("TextLabel")
	title.Name = "TitleLabel"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.66)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = def.Icon .. " " .. def.Title
	local stroke = Instance.new("UIStroke")
	stroke.Color = def.Color
	stroke.Thickness = 3
	stroke.Parent = title
	title.Parent = billboard

	local hint = Instance.new("TextLabel")
	hint.Name = "HintLabel"
	hint.BackgroundTransparency = 1
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.fromScale(0.5, 0.66)
	hint.Size = UDim2.fromScale(0.8, 0.34)
	hint.Font = Enum.Font.GothamBold
	hint.TextScaled = true
	hint.TextColor3 = def.Color:Lerp(Color3.new(1, 1, 1), 0.55)
	hint.TextStrokeTransparency = 0.4
	hint.Text = def.Hint
	hint.Parent = billboard

	billboard.Parent = anchor
end

local function buildStation(def: StationDef, base: BasePart, parent: Instance)
	local config = StationsConfig
	local plots = MapConfig.Plots
	local top = base.Size.Y / 2
	local position = (base.CFrame * CFrame.new(def.X, top, -plots.Depth / 2 + config.Depth)).Position
	local spawnPoint = (base.CFrame * CFrame.new(0, top, -plots.Depth / 2 + plots.SpawnDepth)).Position
	-- Virado para o spawn (a frente do modelo é -Z)
	local facing = CFrame.lookAt(position, Vector3.new(spawnPoint.X, position.Y, spawnPoint.Z))

	local station = Instance.new("Model")
	station.Name = "Station_" .. def.Id
	station:SetAttribute("StationId", def.Id)

	local pad = part(
		"Pad",
		Vector3.new(0.3, config.PadSize, config.PadSize),
		facing * CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, math.rad(90)),
		def.Color,
		Enum.Material.Neon,
		station
	)
	pad.Shape = Enum.PartType.Cylinder
	pad.Transparency = 0.35
	pad.CanCollide = false
	pad.CanQuery = false
	pad.CanTouch = false

	local visual = buildVisual(def)
	visual.Name = "Visual"
	setDecorative(visual)
	Assets.PlaceUpright(visual, position + Vector3.new(0, 0.3, 0), facing)
	visual.Parent = station

	local _, maxV = Assets.GetWorldBounds(visual)
	local anchor = part(
		"TitleAnchor",
		Vector3.new(0.2, 0.2, 0.2),
		CFrame.new(position.X, maxV.Y + config.TitleHeight, position.Z),
		def.Color,
		Enum.Material.SmoothPlastic,
		station
	)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	addTitle(def, anchor)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = config.PromptName
	prompt:SetAttribute("StationId", def.Id)
	prompt.ActionText = "Abrir"
	prompt.ObjectText = def.Title
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = config.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad

	station.PrimaryPart = pad
	station.Parent = parent
end

-- Cria a pasta "Stations" com todos os postos no terreno (base = PlotBase)
function Stations.Build(plot: Model, base: BasePart)
	if not StationsConfig.Enabled then
		return
	end
	local folder = Instance.new("Model")
	folder.Name = "Stations"
	for _, def in StationsConfig.List do
		local ok, err = pcall(buildStation, def, base, folder)
		if not ok then
			warn(string.format("[Stations] %s/%s: %s", plot.Name, def.Id, tostring(err)))
		end
	end
	folder.Parent = plot
end

return table.freeze(Stations)
