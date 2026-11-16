--!strict
--[[
	CinematicAssets
	Modelos da cinemática do ultra-raro, sempre LOCAIS (nunca alteram o mapa real).

	Cada efeito segue o contrato dos modelos do Blender:
	  <Modelo> (Model, PrimaryPart = Root)
	  ├── Root    Part invisível e ancorada (posição/rotação do efeito)
	  └── Visual  geometria
	Override opcional em ReplicatedStorage/Assets/Cinematics/<Nome> (Cloud, Crater,
	Debris). Sem override, usa os placeholders feitos por código abaixo.

	Os artistas vêm de ReplicatedStorage/ArtistRigs/<ArtistId> (copiados pelo servidor);
	sem rig usa um boneco simples de blocos.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CrateAnimConfig = require(ReplicatedStorage.Shared.Config.CrateAnimation)

local CinematicAssets = {}

local function newPart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end
CinematicAssets.NewPart = newPart

-- Prepara todas as peças de um modelo para efeito local (sem colisões nem sombras)
local function prepare(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
		elseif descendant:IsA("BaseScript") then
			descendant:Destroy()
		end
	end
end

local function makeModel(name: string, rootSize: Vector3): (Model, Part, Model)
	local model = Instance.new("Model")
	model.Name = name
	local root = newPart("Root", rootSize, CFrame.new(), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, model)
	root.Transparency = 1
	model.PrimaryPart = root
	local visual = Instance.new("Model")
	visual.Name = "Visual"
	visual.Parent = model
	return model, root, visual
end

local function findOverride(name: string): Model?
	local node: Instance? = ReplicatedStorage
	for _, segment in CrateAnimConfig.CinematicAssetsPath do
		node = if node then node:FindFirstChild(segment) else nil
	end
	local found = if node then node:FindFirstChild(name) else nil
	if found and found:IsA("Model") then
		local root = found:FindFirstChild("Root")
		if root and root:IsA("BasePart") then
			return found
		end
		warn("[CinematicAssets] " .. name .. " sem Root (Part): a usar o placeholder")
	end
	return nil
end

-- Placeholders -----------------------------------------------------------------

-- Nuvem de tempestade: 9 elipsoides (SpecialMesh Sphere) em 3 camadas — base larga e mais
-- escura (é o que se vê de baixo), meio na cor base e topo mais claro — dá volume.
-- Névoa opcional (ParticleEmitter "Mist" com Rate 0; a cinemática liga-o em parte das nuvens).
local function buildCloud(): Model
	local model, root, visual = makeModel("Cloud", Vector3.new(56, 22, 50))
	local color = CrateAnimConfig.Cinematic.CloudColor
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.18)
	local light = color:Lerp(Color3.new(1, 1, 1), 0.22)
	local offsets: { Vector3 } = {
		-- base (larga e achatada, mais escura)
		Vector3.new(0, -4, 0),
		Vector3.new(17, -4.5, 6),
		Vector3.new(-16, -4, -5),
		-- meio
		Vector3.new(8, 0, -10),
		Vector3.new(-9, 0.5, 11),
		Vector3.new(14, 1, 12),
		Vector3.new(-14, 0, -12),
		-- topo (mais claro)
		Vector3.new(2, 5, 2),
		Vector3.new(-6, 4, -4),
	}
	local sizes: { Vector3 } = {
		Vector3.new(40, 10, 34),
		Vector3.new(28, 8, 26),
		Vector3.new(30, 9, 28),
		Vector3.new(26, 12, 24),
		Vector3.new(24, 11, 22),
		Vector3.new(20, 10, 20),
		Vector3.new(22, 10, 20),
		Vector3.new(24, 13, 22),
		Vector3.new(18, 11, 18),
	}
	for index, offset in offsets do
		local tint = if index <= 3 then dark elseif index <= 7 then color else light
		local puff = newPart("Puff" .. index, sizes[index], CFrame.new(offset), tint, Enum.Material.SmoothPlastic, visual)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = puff
	end
	local mist = Instance.new("ParticleEmitter")
	mist.Name = "Mist"
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.15))
	mist.Size = NumberSequence.new(34, 48)
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.55), NumberSequenceKeypoint.new(1, 1) })
	mist.Lifetime = NumberRange.new(3, 4.5)
	mist.Speed = NumberRange.new(1, 3)
	mist.SpreadAngle = Vector2.new(180, 180)
	mist.LockedToPart = true
	mist.Rate = 0
	mist.Parent = root
	return model
end

local function buildCrater(): Model
	local radius = CrateAnimConfig.Cinematic.CraterRadius
	local model, _root, visual = makeModel("Crater", Vector3.new(radius * 2, 1, radius * 2))
	local floor = newPart(
		"Floor",
		Vector3.new(0.3, radius * 2, radius * 2),
		CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(28, 24, 22),
		Enum.Material.Slate,
		visual
	)
	floor.Shape = Enum.PartType.Cylinder
	local rocks = 10
	for index = 1, rocks do
		local angle = (index / rocks) * math.pi * 2
		local size = 2 + (index % 3)
		newPart(
			"Rim" .. index,
			Vector3.new(size * 1.4, size, size),
			CFrame.new(math.cos(angle) * radius, size * 0.3, math.sin(angle) * radius) * CFrame.Angles(index, angle, index * 0.5),
			Color3.fromRGB(70, 62, 56),
			Enum.Material.Slate,
			visual
		)
	end
	return model
end

local function buildDebris(): Model
	local model, root, visual = makeModel("Debris", Vector3.new(1.4, 1.4, 1.4))
	newPart("Rock", Vector3.new(1.4, 1.1, 1.2), CFrame.new(), Color3.fromRGB(80, 72, 64), Enum.Material.Slate, visual)
	root.Size = Vector3.new(1.4, 1.1, 1.2)
	return model
end

local BUILDERS: { [string]: () -> Model } = {
	Cloud = buildCloud,
	Crater = buildCrater,
	Debris = buildDebris,
}

local templates: { [string]: Model } = {}

-- Cópia nova de um efeito (override do place ou placeholder)
function CinematicAssets.Get(name: string): Model
	local cached = templates[name]
	if cached then
		return cached:Clone()
	end
	local override = findOverride(name)
	local builder = BUILDERS[name]
	local built: Model
	if override then
		built = override:Clone()
	elseif builder then
		built = builder()
	else
		local fallback = makeModel(name, Vector3.one)
		built = fallback
	end
	local root = built:FindFirstChild("Root")
	if root and root:IsA("BasePart") then
		built.PrimaryPart = root
		root.Transparency = 1
	end
	prepare(built)
	templates[name] = built
	return built:Clone()
end

-- Artistas -------------------------------------------------------------------------

local function buildBlockFigure(): Model
	local model = Instance.new("Model")
	model.Name = "ArtistRig"
	local white = Color3.new(1, 1, 1)
	local root = newPart("HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0), white, Enum.Material.SmoothPlastic, model)
	root.Transparency = 1
	model.PrimaryPart = root
	newPart("Torso", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0), white, Enum.Material.SmoothPlastic, model)
	newPart("Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 4.6, 0), white, Enum.Material.SmoothPlastic, model)
	newPart("LeftArm", Vector3.new(1, 2, 1), CFrame.new(-1.5, 3, 0), white, Enum.Material.SmoothPlastic, model)
	newPart("RightArm", Vector3.new(1, 2, 1), CFrame.new(1.5, 3, 0), white, Enum.Material.SmoothPlastic, model)
	newPart("LeftLeg", Vector3.new(1, 2, 1), CFrame.new(-0.5, 1, 0), white, Enum.Material.SmoothPlastic, model)
	newPart("RightLeg", Vector3.new(1, 2, 1), CFrame.new(0.5, 1, 0), white, Enum.Material.SmoothPlastic, model)
	model:SetAttribute("Placeholder", true)
	return model
end

-- Cópia local do modelo do artista (pintada com a cor da raridade se for placeholder)
function CinematicAssets.GetArtistRig(artistId: string, rarityColor: Color3): Model
	local folder = ReplicatedStorage:FindFirstChild(CrateAnimConfig.ArtistRigsFolder)
	local source = if folder then folder:FindFirstChild(artistId) else nil
	local rig = if source and source:IsA("Model") then source:Clone() else buildBlockFigure()
	prepare(rig)
	local root = rig.PrimaryPart or rig:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		rig.PrimaryPart = root
		root.Transparency = 1
	end
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	if rig:GetAttribute("Placeholder") == true then
		for _, descendant in rig:GetDescendants() do
			if descendant:IsA("BasePart") and descendant ~= rig.PrimaryPart then
				descendant.Color = rarityColor
				descendant.Material = Enum.Material.SmoothPlastic
			end
		end
	end
	return rig
end

-- Distância do pivot à base dos pés (para assentar no chão)
function CinematicAssets.GetFootOffset(rig: Model): number
	local boxCFrame, size = rig:GetBoundingBox()
	return rig:GetPivot().Position.Y - (boxCFrame.Position.Y - size.Y / 2)
end

return CinematicAssets
