--!strict
--[[
	Placeholders
	Gera modelos provisórios com as medidas exatas de Config (palcos, praça, placa).
	Cada modelo segue o mesmo contrato que os modelos finais do Blender:

	  <Modelo> (Model, PrimaryPart = Root)
	  ├── Root    Part invisível e ancorada com o envelope do modelo + todos os Attachments
	  └── Visual  Model com a geometria (substitui só isto pelo .fbx importado)

	Exportar para ServerStorage/Assets (Studio, modo Edit, Command Bar):
	  require(game.ServerScriptService.Server.World.Placeholders).ExportAll()
	Depois troca o conteúdo de cada "Visual" pelo teu modelo e grava o place.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local MapConfig = require(ReplicatedStorage.Shared.Config.Map)
local StagesConfig = require(ReplicatedStorage.Shared.Config.Stages)
local MapCalc = require(ReplicatedStorage.Shared.Calc.MapCalc)

type StageDef = Types.StageDef
type EraName = Types.EraName

type EraStyle = {
	Deck: Color3,
	DeckMaterial: Enum.Material,
	Wall: Color3,
	WallMaterial: Enum.Material,
	Accent: Color3,
}

local Placeholders = {}

-- Helpers --------------------------------------------------------------------

function Placeholders.NewPart(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Cilindro vertical (eixo Y) com base em `bottomY`
function Placeholders.NewDisc(
	name: string,
	diameter: number,
	height: number,
	position: Vector3,
	color: Color3,
	material: Enum.Material,
	parent: Instance?
): Part
	local part = Placeholders.NewPart(
		name,
		Vector3.new(height, diameter, diameter),
		CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		material,
		parent
	)
	part.Shape = Enum.PartType.Cylinder
	return part
end

local function makeRoot(model: Model, size: Vector3, cframe: CFrame): Part
	local root = Placeholders.NewPart("Root", size, cframe, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, model)
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	model.PrimaryPart = root
	return root
end

local function addAttachment(root: BasePart, name: string, worldOffset: Vector3)
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Position = worldOffset - root.Position -- modelos são construídos sem rotação
	attachment.Parent = root
end

local function addLabel(part: BasePart, text: string, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "PlaceholderLabel"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
end

local function eraStyle(era: EraName): EraStyle
	if era == "Underground" then
		return {
			Deck = Color3.fromRGB(124, 92, 60),
			DeckMaterial = Enum.Material.WoodPlanks,
			Wall = Color3.fromRGB(60, 60, 64),
			WallMaterial = Enum.Material.Concrete,
			Accent = Color3.fromRGB(255, 150, 60),
		}
	elseif era == "Ascensão" then
		return {
			Deck = Color3.fromRGB(50, 40, 80),
			DeckMaterial = Enum.Material.SmoothPlastic,
			Wall = Color3.fromRGB(120, 75, 255),
			WallMaterial = Enum.Material.Neon,
			Accent = Color3.fromRGB(255, 60, 172),
		}
	elseif era == "Estrelato" then
		return {
			Deck = Color3.fromRGB(40, 40, 48),
			DeckMaterial = Enum.Material.Metal,
			Wall = Color3.fromRGB(255, 180, 70),
			WallMaterial = Enum.Material.Neon,
			Accent = Color3.fromRGB(255, 209, 102),
		}
	end
	return {
		Deck = Color3.fromRGB(30, 40, 60),
		DeckMaterial = Enum.Material.DiamondPlate,
		Wall = Color3.fromRGB(43, 210, 255),
		WallMaterial = Enum.Material.Neon,
		Accent = Color3.fromRGB(150, 240, 255),
	}
end

-- Palco ----------------------------------------------------------------------
--[[
	Espaço do palco: origem = frente do palco, ao centro, no chão.
	-Z aponta para o público; o palco ocupa Z de 0 a Depth.
	Root = caixa Width x Height x Depth (o envelope do tier).
]]
function Placeholders.BuildStage(def: StageDef): Model
	local width, height, depth = def.Width, def.Height, def.Depth
	local style = eraStyle(def.Era)

	local model = Instance.new("Model")
	model.Name = string.format("Tier_%02d", def.Tier)
	local root = makeRoot(model, Vector3.new(width, height, depth), CFrame.new(0, height / 2, depth / 2))

	local visual = Instance.new("Model")
	visual.Name = "Visual"
	visual.Parent = model

	local deckHeight = math.clamp(height * 0.15, 2, 8)
	Placeholders.NewPart(
		"Deck",
		Vector3.new(width, deckHeight, depth),
		CFrame.new(0, deckHeight / 2, depth / 2),
		style.Deck,
		style.DeckMaterial,
		visual
	)

	local wallHeight = height - deckHeight
	local wall = Placeholders.NewPart(
		"BackWall",
		Vector3.new(width, wallHeight, 1),
		CFrame.new(0, deckHeight + wallHeight / 2, depth - 0.5),
		style.Wall,
		style.WallMaterial,
		visual
	)
	addLabel(wall, string.format("TIER %d\n%s\n(placeholder)", def.Tier, def.Name), Color3.new(1, 1, 1))

	for _, side in { -1, 1 } do
		Placeholders.NewPart(
			"Tower",
			Vector3.new(2, wallHeight, 2),
			CFrame.new(side * (width / 2 - 1), deckHeight + wallHeight / 2, depth - 2),
			style.Accent,
			Enum.Material.Metal,
			visual
		)
	end

	if def.Tier >= 6 then
		Placeholders.NewPart(
			"Roof",
			Vector3.new(width, 1.5, depth * 0.6),
			CFrame.new(0, height - 0.75, depth * 0.7),
			style.Accent,
			Enum.Material.Metal,
			visual
		)
	end

	-- Attachments (posições no espaço do palco)
	local deckTop = deckHeight
	addAttachment(root, "StageOrigin", Vector3.new(0, 0, 0))
	addAttachment(root, "DJBooth", Vector3.new(0, deckTop, depth * 0.6))
	for index = 1, 7 do
		local x = -width * 0.35 + (index - 1) * (width * 0.7 / 6)
		addAttachment(root, "Artist_" .. index, Vector3.new(x, deckTop, depth * 0.3))
	end
	for index, side in { -1, 1 } do
		addAttachment(root, "Pyro_ColdSparks_" .. index, Vector3.new(side * (width / 2 - 1), deckTop, 1))
		addAttachment(root, "Pyro_CO2Cannon_" .. index, Vector3.new(side * width * 0.3, deckTop, 1.5))
		addAttachment(root, "Pyro_Lasers_" .. index, Vector3.new(side * width * 0.25, height - 1, depth - 2))
		addAttachment(root, "Pyro_Flamethrower_" .. index, Vector3.new(side * (width / 2 - 1), deckTop, depth * 0.5))
	end
	addAttachment(root, "Speaker_L", Vector3.new(-(width / 2 - 2), deckTop, 2))
	addAttachment(root, "Speaker_R", Vector3.new(width / 2 - 2, deckTop, 2))
	addAttachment(root, "CameraFocus", Vector3.new(0, deckTop + wallHeight * 0.4, depth * 0.4))

	return model
end

-- Praça ----------------------------------------------------------------------
-- Origem = centro do mapa, no chão. Root = disco do anel de passeio (caixa).
function Placeholders.BuildPlaza(): Model
	local plaza = MapConfig.Plaza
	local outer = plaza.RingOuterRadius

	local model = Instance.new("Model")
	model.Name = "Plaza"
	local root = makeRoot(model, Vector3.new(outer * 2, 1, outer * 2), CFrame.new(0, 0.5, 0))

	local visual = Instance.new("Model")
	visual.Name = "Visual"
	visual.Parent = model

	local stone = Color3.fromRGB(150, 145, 160)
	Placeholders.NewDisc("Ring", outer * 2, 0.2, Vector3.new(0, 0.1, 0), Color3.fromRGB(95, 90, 105), Enum.Material.Pavement, visual)
	Placeholders.NewDisc("Floor", plaza.Radius * 2, 0.4, Vector3.new(0, 0.2, 0), stone, Enum.Material.Slate, visual)

	for index = 1, MapConfig.Plots.Count do
		local angle = (index - 1) * 360 / MapConfig.Plots.Count
		local midRadius = (plaza.Radius + outer) / 2
		local strip = Placeholders.NewPart(
			"Path_" .. index,
			Vector3.new(plaza.PathWidth, 0.1, outer - plaza.Radius),
			MapCalc.PlazaPoint(angle, midRadius, 0.25),
			Color3.fromRGB(200, 195, 210),
			Enum.Material.Pavement,
			visual
		)
		strip.CanCollide = false
	end

	Placeholders.NewDisc("MonumentBase", plaza.MonumentRadius * 2, 3, Vector3.new(0, 1.5, 0), stone, Enum.Material.Marble, visual)
	Placeholders.NewPart(
		"MonumentColumn",
		Vector3.new(4, 30, 4),
		CFrame.new(0, 18, 0),
		Color3.fromRGB(255, 60, 172),
		Enum.Material.Neon,
		visual
	)
	addAttachment(root, "Monument", Vector3.new(0, 3, 0))

	for index, angle in plaza.CrateStationAngles do
		local cframe = MapCalc.PlazaPoint(angle, plaza.CrateStationRadius, 0.65)
		Placeholders.NewPart("CratePad_" .. index, Vector3.new(10, 0.5, 10), cframe, Color3.fromRGB(255, 209, 102), Enum.Material.Neon, visual)
		addAttachment(root, "CrateStation_" .. index, cframe.Position + Vector3.new(0, 0.25, 0))
	end

	for index, angle in plaza.LeaderboardAngles do
		local cframe = MapCalc.PlazaPoint(angle, plaza.LeaderboardRadius, 6.4)
		local board = Placeholders.NewPart("Leaderboard_" .. index, Vector3.new(16, 12, 1), cframe, Color3.fromRGB(34, 20, 70), Enum.Material.SmoothPlastic, visual)
		addLabel(board, "LEADERBOARD\n(placeholder)", Color3.fromRGB(43, 210, 255))
		addAttachment(root, "Leaderboard_" .. index, cframe.Position)
	end

	return model
end

-- Placa do dono ----------------------------------------------------------------
-- Origem = base da placa, ao centro, no chão; -Z aponta para a praça.
-- O PlotService escreve o texto numa SurfaceGui na face Front da parte "Board".
function Placeholders.BuildSign(): Model
	local model = Instance.new("Model")
	model.Name = "PlotSign"
	makeRoot(model, Vector3.new(18, 10, 1), CFrame.new(0, 5, 0))

	local visual = Instance.new("Model")
	visual.Name = "Visual"
	visual.Parent = model

	for _, side in { -1, 1 } do
		Placeholders.NewPart("Post", Vector3.new(1, 8, 1), CFrame.new(side * 7, 4, 0), Color3.fromRGB(60, 60, 64), Enum.Material.Metal, visual)
	end
	Placeholders.NewPart("Board", Vector3.new(16, 6, 0.5), CFrame.new(0, 7, 0), Color3.fromRGB(34, 20, 70), Enum.Material.SmoothPlastic, visual)
	return model
end

-- Decoração do terreno por era ------------------------------------------------------
--[[
	Origem = centro do terreno, no chão; -Z aponta para a praça (frente).
	Root = caixa 120 x 1 x 120 (o terreno). Só usa as alas laterais (x = ±45..±60,
	profundidade 68–116) e as margens da zona do público — nunca a zona do palco.
]]
local ERA_ORDER: { EraName } = { "Underground", "Ascensão", "Estrelato", "Lenda" }
Placeholders.EraOrder = table.freeze(ERA_ORDER)

function Placeholders.BuildDecor(era: EraName): Model
	local plots = MapConfig.Plots
	local style = eraStyle(era)
	local halfDepth = plots.Depth / 2
	local wingX = plots.StageZone.Width / 2 + plots.WingWidth / 2

	local model = Instance.new("Model")
	model.Name = "Decor_" .. era
	makeRoot(model, Vector3.new(plots.Width, 1, plots.Depth), CFrame.new(0, 0.5, 0))

	local visual = Instance.new("Model")
	visual.Name = "Visual"
	visual.Parent = model

	-- Peça assente no chão, em coordenadas do terreno (depth a partir da frente)
	local function prop(name: string, size: Vector3, x: number, depth: number, color: Color3, material: Enum.Material, lift: number?): Part
		return Placeholders.NewPart(
			name,
			size,
			CFrame.new(x, (lift or 0) + size.Y / 2, -halfDepth + depth),
			color,
			material,
			visual
		)
	end

	local wingDepths = { plots.StageFront + 10, plots.StageBack - 10 }
	for _, side in { -1, 1 } do
		for index, depth in wingDepths do
			local x = side * wingX
			if era == "Underground" then
				prop("Crate", Vector3.new(5, 5, 5), x, depth, Color3.fromRGB(124, 92, 60), Enum.Material.WoodPlanks)
				prop("Barrel", Vector3.new(3, 4, 3), x, depth + 8, Color3.fromRGB(90, 70, 50), Enum.Material.Wood)
			elseif era == "Ascensão" then
				prop("LightPole", Vector3.new(1, 18, 1), x, depth, Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
				prop("Lamp", Vector3.new(3, 1, 3), x, depth, style.Accent, Enum.Material.Neon, 18)
			elseif era == "Estrelato" then
				prop("Truss", Vector3.new(3, 30, 3), x, depth, Color3.fromRGB(70, 70, 78), Enum.Material.DiamondPlate)
				prop("TrussLight", Vector3.new(4, 1.5, 4), x, depth, style.Accent, Enum.Material.Neon, 30)
			else
				local pillar = prop("HoloPillar", Vector3.new(40, 3, 3), x, depth, style.Wall, Enum.Material.Neon)
				pillar.Shape = Enum.PartType.Cylinder
				pillar.CFrame = CFrame.new(x, 20, -halfDepth + depth) * CFrame.Angles(0, 0, math.rad(90))
				if index == 1 then
					prop("HoloBase", Vector3.new(6, 1, 6), x, depth, Color3.fromRGB(30, 40, 60), Enum.Material.Metal)
				end
			end
		end

		-- Margem lateral da zona do público
		local crowdMid = (plots.CrowdStart + plots.CrowdEnd) / 2
		local crowdX = side * (plots.Width / 2 - 4)
		if era == "Ascensão" then
			prop("Banner", Vector3.new(0.5, 8, 6), crowdX, crowdMid, style.Wall, Enum.Material.SmoothPlastic, 2)
		elseif era == "Estrelato" or era == "Lenda" then
			local screen = prop("SideScreen", Vector3.new(0.5, 12, 18), crowdX, crowdMid, style.Wall, Enum.Material.Neon, 4)
			screen.Transparency = 0.2
		end
	end

	if era == "Lenda" then
		local ring = Placeholders.NewPart(
			"HoloRing",
			Vector3.new(0.6, 24, 24),
			CFrame.new(0, 30, -halfDepth + (plots.CrowdStart + plots.CrowdEnd) / 2) * CFrame.Angles(0, 0, math.rad(90)),
			style.Accent,
			Enum.Material.Neon,
			visual
		)
		ring.Shape = Enum.PartType.Cylinder
		ring.Transparency = 0.4
		ring.CanCollide = false
	end

	for _, descendant in visual:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = descendant.Name ~= "HoloRing" and descendant.Size.Y < 25
		end
	end

	return model
end

-- Arco de Prestige (entrada do terreno) ------------------------------------------------
--[[
	Origem = base, ao centro, no chão; -Z aponta para a praça. Abraça a entrada (24 studs).
	A parte "Beam" recebe o texto "WORLD TOUR ×N"; as cores são aplicadas pelo
	PrestigeService (atributo Placeholder = true).
]]
function Placeholders.BuildPrestigeArch(): Model
	local model = Instance.new("Model")
	model.Name = "PrestigeArch"
	makeRoot(model, Vector3.new(30, 17, 2), CFrame.new(0, 8.5, 0))

	local visual = Instance.new("Model")
	visual.Name = "Visual"
	visual.Parent = model

	local gold = Color3.fromRGB(255, 200, 60)
	for _, side in { -1, 1 } do
		Placeholders.NewPart("Pillar", Vector3.new(2, 15, 2), CFrame.new(side * 13, 7.5, 0), gold, Enum.Material.Metal, visual)
	end
	Placeholders.NewPart("Beam", Vector3.new(30, 2, 2), CFrame.new(0, 16, 0), gold, Enum.Material.Metal, visual)
	model:SetAttribute("Placeholder", true)
	return model
end

-- Artista (boneco placeholder) ------------------------------------------------------
--[[
	Model com PrimaryPart = HumanoidRootPart, de pé, virado para -Z (o público).
	Tenta um R15 padrão (CreateHumanoidModelFromDescription); se falhar, usa uma figura de blocos.
	O StageArtistService pinta-o com a cor da raridade (atributo Placeholder = true).
]]
local function buildBlockFigure(): Model
	local model = Instance.new("Model")
	model.Name = "ArtistRig"
	local white = Color3.new(1, 1, 1)
	local root = Placeholders.NewPart("HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0), white, Enum.Material.SmoothPlastic, model)
	root.Transparency = 1
	model.PrimaryPart = root
	Placeholders.NewPart("Torso", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0), white, Enum.Material.SmoothPlastic, model)
	Placeholders.NewPart("Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 4.6, 0), white, Enum.Material.SmoothPlastic, model)
	Placeholders.NewPart("LeftArm", Vector3.new(1, 2, 1), CFrame.new(-1.5, 3, 0), white, Enum.Material.SmoothPlastic, model)
	Placeholders.NewPart("RightArm", Vector3.new(1, 2, 1), CFrame.new(1.5, 3, 0), white, Enum.Material.SmoothPlastic, model)
	Placeholders.NewPart("LeftLeg", Vector3.new(1, 2, 1), CFrame.new(-0.5, 1, 0), white, Enum.Material.SmoothPlastic, model)
	Placeholders.NewPart("RightLeg", Vector3.new(1, 2, 1), CFrame.new(0.5, 1, 0), white, Enum.Material.SmoothPlastic, model)
	return model
end

function Placeholders.BuildArtistRig(): Model
	local ok, result = pcall(function(): Model
		local description = Instance.new("HumanoidDescription")
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	local rig = if ok then result else buildBlockFigure()
	rig.Name = "ArtistRig"

	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("BodyColors") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	local root = rig:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		rig.PrimaryPart = root
		root.Anchored = true
	end
	rig:SetAttribute("Placeholder", true)
	return rig
end

-- Exportação para ServerStorage/Assets (correr no Command Bar em modo Edit) -----------

local function getOrCreateFolder(parent: Instance, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- Cria em ServerStorage/Assets os modelos em falta (nunca substitui existentes).
function Placeholders.ExportAll(): number
	local assets = getOrCreateFolder(ServerStorage, "Assets")
	local stages = getOrCreateFolder(assets, "Stages")
	local created = 0

	for _, def in StagesConfig.List do
		local name = string.format("Tier_%02d", def.Tier)
		if not stages:FindFirstChild(name) then
			Placeholders.BuildStage(def).Parent = stages
			created += 1
		end
	end
	if not assets:FindFirstChild("Plaza") then
		Placeholders.BuildPlaza().Parent = assets
		created += 1
	end
	if not assets:FindFirstChild("PlotSign") then
		Placeholders.BuildSign().Parent = assets
		created += 1
	end
	local prestige = getOrCreateFolder(assets, "Prestige")
	if not prestige:FindFirstChild("Arch") then
		local arch = Placeholders.BuildPrestigeArch()
		arch.Name = "Arch"
		arch.Parent = prestige
		created += 1
	end
	local decor = getOrCreateFolder(assets, "Decor")
	for _, era in ERA_ORDER do
		if not decor:FindFirstChild(era) then
			local model = Placeholders.BuildDecor(era)
			model.Name = era
			model.Parent = decor
			created += 1
		end
	end

	print(string.format("[Placeholders] %d modelos criados em ServerStorage/Assets. Grava o place para os manter.", created))
	return created
end

return table.freeze(Placeholders)
