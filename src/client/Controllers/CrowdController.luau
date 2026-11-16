--!strict
--[[
	CrowdController
	Público dinâmico em cada terreno ocupado (só no cliente: nada replica).
	  - Tamanho pelo Hype ganho na run do dono (atributo FE_CrowdLevel, publicado pelo
	    servidor) + World Tours (FE_WorldTours), via CrowdCalc: completo no próprio
	    terreno, reduzido nos outros.
	  - À frente (mais perto do palco) ficam os AVATARES REAIS dos amigos do dono
	    (GetFriendsAsync + CreateHumanoidModelFromDescription), a dançar com emotes do
	    Roblox e com o nome por cima; os que estão no servidor vêm primeiro. Quando os
	    amigos acabam, os lugares de avatar seguintes são bonecos-padrão R15 do Roblox
	    com cores aleatórias. O resto do público são bonecos simples (pernas, cara,
	    cabelo/boné/gorro, alturas variadas).
	  - Reage à música (AudioController.GetIntensity / pulso de BPM), agita-se no
	    build-up e "explode" nos Bass Drops (salto + braços no ar + confetes; no
	    próprio terreno, glowsticks durante o boost). Força pela nota do drop.
	  - LOD (Config/Lod.Crowd) para os outros terrenos: animado (só saltos, a
	    OtherUpdateRate Hz) até AnimatedDistance, parado até StaticDistance,
	    escondido além. O próprio terreno é sempre completo.
	Bonecos: 7 peças ancoradas por pessoa, movidas em lote com Workspace:BulkMoveTo.
	Avatares: no máximo Config/Ambience.Crowd.Friends.MaxOwn/MaxOther por terreno, criados
	um de cada vez (fila) e guardados em cache por UserId.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local AmbienceConfig = require(ReplicatedStorage.Shared.Config.Ambience)
local LodConfig = require(ReplicatedStorage.Shared.Config.Lod)
local MapConfig = require(ReplicatedStorage.Shared.Config.Map)
local BassDropConfig = require(ReplicatedStorage.Shared.Config.BassDrop)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
local MapCalc = require(ReplicatedStorage.Shared.Calc.MapCalc)
local CrowdCalc = require(ReplicatedStorage.Shared.Calc.CrowdCalc)
local DanceFloorConfig = require(ReplicatedStorage.Shared.Config.DanceFloor)
local AudioController = require(script.Parent.AudioController)
local BassDropController = require(script.Parent.BassDropController)

type DropResolved = Types.DropResolved

type CrowdMode = "Full" | "Animated" | "Static" | "Hidden"

type Offsets = {
	LegL: CFrame,
	LegR: CFrame,
	Torso: CFrame,
	Head: CFrame,
	Hat: CFrame,
	ShoulderL: CFrame,
	ShoulderR: CFrame,
	ArmHang: CFrame,
}

type Person = {
	Base: CFrame, -- pés no chão, virado para o palco
	Phase: number,
	Energy: number, -- 0.6..1.2 (uns saltam mais do que outros)
	ArmStyle: number, -- 0..1
	Arms: { BasePart },
	ArmColor: Color3,
	Offsets: Offsets,
}

type FriendAvatar = {
	UserId: number,
	Model: Model,
	Root: BasePart,
	RootBase: CFrame, -- CFrame do HumanoidRootPart em repouso
	Track: AnimationTrack?,
	Phase: number,
	Energy: number,
}

type Crowd = {
	PlotIndex: number,
	OwnerUserId: number,
	IsMine: boolean,
	Count: number,
	FriendSlots: number, -- lugares de avatar (amigos + bonecos-padrão)
	ListLoaded: boolean, -- a lista de amigos do dono já estava carregada ao construir
	FriendBases: { CFrame }, -- lugares dos avatares (filas da frente)
	Friends: { FriendAvatar },
	Folder: Folder,
	People: { Person },
	Parts: { BasePart },
	CFrames: { CFrame },
	Center: Vector3,
	Mode: CrowdMode,
	LastUpdate: number,
	JumpStart: number,
	JumpStrength: number,
	Glow: boolean,
	Confetti: ParticleEmitter?,
	LoadToken: number,
}

type FriendEntry = {
	UserId: number,
	DisplayName: string,
}

type HatStyle = { Size: Vector3, Offset: Vector3 }

local PARTS_PER_PERSON = 7
local ARMS_UP = 2.5 -- radianos (braços quase na vertical)
local BEAT_RATE = BassDropConfig.BPM / 60

-- Cabelo, boné, gorro (tamanho e posição relativos aos pés, escala 1)
local HAT_STYLES: { HatStyle } = {
	{ Size = Vector3.new(1.4, 0.55, 1.4), Offset = Vector3.new(0, 5.15, 0.08) },
	{ Size = Vector3.new(1.45, 0.4, 1.45), Offset = Vector3.new(0, 5.32, 0) },
	{ Size = Vector3.new(1.35, 0.75, 1.35), Offset = Vector3.new(0, 5.22, 0) },
}

local CrowdController = {}

local trove = Trove.new()
local crowds: { [number]: Crowd } = {}
local rootFolder: Folder? = nil
local lastLodCheck = 0
local rebuildQueued: { [number]: boolean } = {}
local ownerConnections: { [number]: { RBXScriptConnection } } = {}

-- Amigos (cache por UserId do dono) e modelos-fonte dos avatares (cache por UserId do amigo)
local friendLists: { [number]: { FriendEntry } } = {}
local friendListLoading: { [number]: boolean } = {}
local avatarTemplates: { [number]: Model | false } = {} -- false = falhou (não voltar a tentar)
local defaultTemplate: Model | false | nil = nil -- rig R15 base dos bonecos-padrão
local loadQueue: { () -> () } = {}
local loaderRunning = false

-- Construção ---------------------------------------------------------------------

local function getRootFolder(): Folder
	local existing = rootFolder
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "ClientCrowds"
	folder.Parent = Workspace
	trove:Add(folder)
	rootFolder = folder
	return folder
end

local function newPart(name: string, size: Vector3, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
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

-- Posições aleatórias (determinísticas por terreno) com distância mínima; mais gente perto do palco.
-- Devolvidas da mais próxima do palco para a mais afastada.
local function generatePositions(plotIndex: number, count: number): { Vector2 }
	local config = AmbienceConfig.Crowd
	local plots = MapConfig.Plots
	local rng = Random.new(plotIndex * 7919 + count)
	local minDepth = plots.CrowdStart + config.DepthMargin
	local maxDepth = plots.CrowdEnd - config.DepthMargin
	local spacingSquared = config.MinSpacing * config.MinSpacing
	local positions: { Vector2 } = {}
	local attempts = 0
	while #positions < count and attempts < count * 40 do
		attempts += 1
		local x = rng:NextNumber(-config.AreaHalfWidth, config.AreaHalfWidth)
		local depth = maxDepth - (maxDepth - minDepth) * rng:NextNumber() ^ 1.6
		local candidate = Vector2.new(x, depth)
		local free = true
		for _, other in positions do
			local delta = other - candidate
			if delta.X * delta.X + delta.Y * delta.Y < spacingSquared then
				free = false
				break
			end
		end
		if free then
			table.insert(positions, candidate)
		end
	end
	table.sort(positions, function(a: Vector2, b: Vector2): boolean
		return a.Y > b.Y -- maior profundidade = mais perto do palco
	end)
	return positions
end

local function addConfetti(crowd: Crowd)
	local attachment = Instance.new("Attachment")
	attachment.Name = "Confetti"
	attachment.WorldPosition = crowd.Center + Vector3.new(0, 14, 0)
	attachment.Parent = Workspace.Terrain
	crowd.Folder.Destroying:Once(function()
		attachment:Destroy()
	end)

	local colors = AmbienceConfig.Crowd.GlowstickColors
	local keypoints: { ColorSequenceKeypoint } = {}
	for index, color in colors do
		table.insert(keypoints, ColorSequenceKeypoint.new((index - 1) / math.max(#colors - 1, 1), color))
	end

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Confetti"
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(2, 3.5)
	emitter.Speed = NumberRange.new(18, 32)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.Acceleration = Vector3.new(0, -16, 0)
	emitter.Drag = 1.2
	emitter.Size = NumberSequence.new(0.45)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-240, 240)
	emitter.LightEmission = 0.4
	emitter.Color = ColorSequence.new(keypoints)
	emitter.Parent = attachment
	crowd.Confetti = emitter
end

local function destroyCrowd(index: number)
	local crowd = crowds[index]
	if crowd then
		crowds[index] = nil
		crowd.LoadToken += 1 -- cancela avatares ainda na fila
		crowd.Folder:Destroy()
	end
end

local function makeOffsets(scale: number, hat: HatStyle): Offsets
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(x * scale, y * scale, z * scale)
	end
	return {
		LegL = at(-0.48, 1, 0),
		LegR = at(0.48, 1, 0),
		Torso = at(0, 3, 0),
		Head = at(0, 4.65, 0),
		Hat = CFrame.new(hat.Offset * scale),
		ShoulderL = at(-1.3, 3.8, 0),
		ShoulderR = at(1.3, 3.8, 0),
		ArmHang = at(0, -0.95, 0),
	}
end

local function buildPerson(folder: Folder, rng: Random, base: CFrame): (Person, { BasePart })
	local config = AmbienceConfig.Crowd
	local shirt = config.ShirtColors[rng:NextInteger(1, #config.ShirtColors)]
	local skin = config.SkinColors[rng:NextInteger(1, #config.SkinColors)]
	local hair = config.HairColors[rng:NextInteger(1, #config.HairColors)]
	local pants = Color3.fromRGB(35, 35, 50):Lerp(Color3.fromRGB(70, 90, 140), rng:NextNumber())
	local scale = rng:NextNumber(config.HeightRange[1], config.HeightRange[2])
	local hatIndex = rng:NextInteger(1, #HAT_STYLES)
	local hat = HAT_STYLES[hatIndex]

	local legL = newPart("LegL", Vector3.new(0.9, 2, 0.9) * scale, pants, folder)
	local legR = newPart("LegR", Vector3.new(0.9, 2, 0.9) * scale, pants, folder)
	local torso = newPart("Torso", Vector3.new(2, 2, 1) * scale, shirt, folder)
	local head = newPart("Head", Vector3.new(1.3, 1.3, 1.3) * scale, skin, folder)
	head.Shape = Enum.PartType.Ball
	local face = Instance.new("Decal")
	face.Texture = config.FaceTexture
	face.Face = Enum.NormalId.Front
	face.Parent = head
	-- Boné com a cor da t-shirt; cabelo e gorro com cor de cabelo
	local hatPart = newPart("Hat", hat.Size * scale, if hatIndex == 2 then shirt else hair, folder)
	local leftArm = newPart("LeftArm", Vector3.new(0.6, 1.9, 0.6) * scale, skin, folder)
	local rightArm = newPart("RightArm", Vector3.new(0.6, 1.9, 0.6) * scale, skin, folder)

	local person: Person = {
		Base = base,
		Phase = rng:NextNumber(0, math.pi * 2),
		Energy = rng:NextNumber(0.6, 1.2),
		ArmStyle = rng:NextNumber(),
		Arms = { leftArm, rightArm },
		ArmColor = skin,
		Offsets = makeOffsets(scale, hat),
	}
	-- A ordem tem de bater com writePose
	return person, { legL, legR, torso, head, hatPart, leftArm, rightArm }
end

local function toBase(plotCFrame: CFrame, position: Vector2, yaw: number): CFrame
	local plots = MapConfig.Plots
	-- Em cima da pista de dança (o resto do público fica 0.2 acima do chão, impercetível)
	local floor = if DanceFloorConfig.Enabled then DanceFloorConfig.Height else 0
	return plotCFrame
		* CFrame.new(position.X, plots.BaseThickness + floor, -plots.Depth / 2 + position.Y)
		* CFrame.Angles(0, math.pi + yaw, 0)
end

local function buildCrowd(index: number, ownerUserId: number, count: number, friendSlots: number): Crowd
	local plots = MapConfig.Plots
	local isMine = ownerUserId == Players.LocalPlayer.UserId
	local folder = Instance.new("Folder")
	folder.Name = "Crowd_" .. index

	local plotCFrame = MapCalc.GetPlotCFrame(index)
	local rng = Random.new(index * 104729 + count)
	local people: { Person } = {}
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	local friendBases: { CFrame } = {}

	for positionIndex, position in generatePositions(index, count) do
		local base = toBase(plotCFrame, position, math.rad(rng:NextNumber(-12, 12)))
		if positionIndex <= friendSlots then
			table.insert(friendBases, base)
		else
			local person, personParts = buildPerson(folder, rng, base)
			table.insert(people, person)
			for _, part in personParts do
				table.insert(parts, part)
				table.insert(cframes, base)
			end
		end
	end

	local crowd: Crowd = {
		PlotIndex = index,
		OwnerUserId = ownerUserId,
		IsMine = isMine,
		Count = count,
		FriendSlots = friendSlots,
		ListLoaded = friendLists[ownerUserId] ~= nil,
		FriendBases = friendBases,
		Friends = {},
		Folder = folder,
		People = people,
		Parts = parts,
		CFrames = cframes,
		Center = (plotCFrame * CFrame.new(0, plots.BaseThickness, -plots.Depth / 2 + (plots.CrowdStart + plots.CrowdEnd) / 2)).Position,
		Mode = "Static",
		LastUpdate = 0,
		JumpStart = -math.huge,
		JumpStrength = 1,
		Glow = false,
		Confetti = nil,
		LoadToken = 0,
	}
	addConfetti(crowd)
	return crowd
end

-- Avatares dos amigos ----------------------------------------------------------------

local function runLoader()
	if loaderRunning then
		return
	end
	loaderRunning = true
	task.spawn(function()
		while #loadQueue > 0 do
			local job = table.remove(loadQueue, 1)
			if job then
				local ok, err = pcall(job)
				if not ok then
					Diag.Log("Crowd", "falha a carregar avatar: " .. tostring(err))
				end
			end
		end
		loaderRunning = false
	end)
end

local function enqueue(job: () -> ())
	table.insert(loadQueue, job)
	runLoader()
end

-- Lê a lista de amigos do dono (uma vez por dono); os que estão neste servidor vêm primeiro
local function fetchFriendList(ownerUserId: number, onDone: () -> ())
	if friendLists[ownerUserId] or friendListLoading[ownerUserId] then
		return
	end
	friendListLoading[ownerUserId] = true
	task.spawn(function()
		local limit = AmbienceConfig.Crowd.Friends.FetchLimit
		local here: { FriendEntry } = {}
		local others: { FriendEntry } = {}
		local ok, err = pcall(function()
			local pages = Players:GetFriendsAsync(ownerUserId)
			while true do
				for _, raw in pages:GetCurrentPage() do
					local entry = raw :: { [string]: unknown }
					local id = entry.Id
					if type(id) == "number" then
						local display = entry.DisplayName
						local username = entry.Username
						local friend: FriendEntry = {
							UserId = id,
							DisplayName = if type(display) == "string" then display
								elseif type(username) == "string" then username
								else tostring(id),
						}
						table.insert(if Players:GetPlayerByUserId(id) then here else others, friend)
					end
				end
				if pages.IsFinished or #here + #others >= limit then
					break
				end
				pages:AdvanceToNextPageAsync()
			end
		end)
		if not ok then
			Diag.Log("Crowd", string.format("lista de amigos de %d indisponível: %s", ownerUserId, tostring(err)))
		end
		-- Ordem estável por dono (os mesmos amigos à frente sempre que se volta)
		local rng = Random.new(ownerUserId % 2147483647)
		for i = #others, 2, -1 do
			local j = rng:NextInteger(1, i)
			others[i], others[j] = others[j], others[i]
		end
		local list: { FriendEntry } = here
		for _, friend in others do
			table.insert(list, friend)
		end
		friendLists[ownerUserId] = list
		friendListLoading[ownerUserId] = nil
		onDone()
	end)
end

local function prepareAvatar(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			descendant.Massless = true
			descendant.Anchored = false
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy() -- "Animate" e afins: a animação é tocada por aqui
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		pcall(function()
			humanoid.EvaluateStateMachine = false -- parado e ancorado: sem física de Humanoid
		end)
		if not humanoid:FindFirstChildOfClass("Animator") then
			Instance.new("Animator").Parent = humanoid
		end
	end
end

-- Modelo-fonte do avatar (cache). Corre dentro da fila (chamadas web bloqueantes).
local function getAvatarTemplate(userId: number): Model?
	local cached = avatarTemplates[userId]
	if cached ~= nil then
		return if cached then cached else nil
	end
	local ok, result = pcall(function(): Model
		local description = Players:GetHumanoidDescriptionFromUserId(userId)
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok then
		Diag.Log("Crowd", string.format("avatar de %d indisponível: %s", userId, tostring(result)))
		avatarTemplates[userId] = false
		return nil
	end
	prepareAvatar(result)
	avatarTemplates[userId] = result
	return result
end

local function addNameTag(model: Model, text: string)
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "FriendTag"
	billboard.Size = UDim2.fromOffset(150, 26)
	billboard.StudsOffset = Vector3.new(0, 2.1, 0)
	billboard.MaxDistance = AmbienceConfig.Crowd.Friends.NameDistance
	billboard.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = billboard
	billboard.Parent = head
end

local function playDance(model: Model, rng: Random): AnimationTrack?
	local ids = AmbienceConfig.Crowd.Friends.Animations
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	if not animator or #ids == 0 then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(ids[rng:NextInteger(1, #ids)])
	local ok, track = pcall(function(): AnimationTrack
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok then
		return nil
	end
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Action
	track:Play(0.2, 1, rng:NextNumber(0.9, 1.1))
	pcall(function()
		track.TimePosition = rng:NextNumber(0, math.max(track.Length - 0.1, 0))
	end)
	return track
end

-- Coloca o avatar no lugar `slot` do público (pés no chão, virado para o palco)
local function placeAvatar(crowd: Crowd, userId: number, displayName: string?, template: Model, slot: number)
	local base = crowd.FriendBases[slot]
	if not base then
		return
	end
	local model = template:Clone()
	local root = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") then
		model:Destroy()
		return
	end
	root.Anchored = true
	model.PrimaryPart = root
	local hipHeight = if humanoid then humanoid.HipHeight else 2
	local rootBase = base * CFrame.new(0, hipHeight + root.Size.Y / 2, 0)
	model:PivotTo(rootBase)
	if displayName then
		addNameTag(model, displayName)
	end
	model.Name = if displayName then "Friend_" .. userId else "Fan_" .. slot
	model.Parent = crowd.Folder

	local rng = Random.new(userId % 2147483647 + slot)
	table.insert(crowd.Friends, {
		UserId = userId,
		Model = model,
		Root = root,
		RootBase = rootBase,
		Track = playDance(model, rng),
		Phase = rng:NextNumber(0, math.pi * 2),
		Energy = rng:NextNumber(0.7, 1.1),
	})
end

-- Rig R15 base dos bonecos-padrão (descrição vazia = boneco clássico do Roblox), criado uma vez
local function getDefaultTemplate(): Model?
	if defaultTemplate ~= nil then
		return if defaultTemplate then defaultTemplate else nil
	end
	local ok, result = pcall(function(): Model
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	if not ok then
		Diag.Log("Crowd", "boneco-padrão indisponível: " .. tostring(result))
		defaultTemplate = false
		return nil
	end
	prepareAvatar(result)
	-- As cores passam a vir das peças (o BodyColors sobrepõe-se-lhes)
	for _, descendant in result:GetDescendants() do
		if descendant:IsA("BodyColors") then
			descendant:Destroy()
		end
	end
	defaultTemplate = result
	return result
end

local SKIN_PARTS = { "Head", "LeftHand", "RightHand", "LeftLowerArm", "RightLowerArm" }
local SHIRT_PARTS = { "UpperTorso", "LeftUpperArm", "RightUpperArm" }
local PANTS_PARTS = { "LowerTorso", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }
local SHOE_PARTS = { "LeftFoot", "RightFoot" }

local function paintParts(model: Model, names: { string }, color: Color3)
	for _, name in names do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.Color = color
		end
	end
end

-- Clone do rig base com pele/t-shirt/calças/sapatos e cabelo, boné ou gorro aleatórios
local function makeDefaultAvatar(seed: number): Model?
	local template = getDefaultTemplate()
	if not template then
		return nil
	end
	local config = AmbienceConfig.Crowd
	local rng = Random.new(seed)
	local model = template:Clone()
	local skin = config.SkinColors[rng:NextInteger(1, #config.SkinColors)]
	local shirt = config.ShirtColors[rng:NextInteger(1, #config.ShirtColors)]
	local pants = Color3.fromRGB(35, 35, 50):Lerp(Color3.fromRGB(70, 90, 140), rng:NextNumber())
	paintParts(model, SKIN_PARTS, skin)
	paintParts(model, SHIRT_PARTS, shirt)
	paintParts(model, PANTS_PARTS, pants)
	paintParts(model, SHOE_PARTS, Color3.fromRGB(30, 30, 34))

	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local hatIndex = rng:NextInteger(1, #HAT_STYLES)
		local style = HAT_STYLES[hatIndex]
		local headScale = head.Size.Y / 1.3
		local hat = Instance.new("Part")
		hat.Name = "Hat"
		hat.Size = style.Size * headScale
		hat.Color = if hatIndex == 2 then shirt else config.HairColors[rng:NextInteger(1, #config.HairColors)]
		hat.Material = Enum.Material.SmoothPlastic
		hat.CanCollide = false
		hat.CanQuery = false
		hat.CanTouch = false
		hat.CastShadow = false
		hat.Massless = true
		-- Topo da cabeça (estilos medidos a partir dos pés do boneco simples, cabeça a 4.65)
		hat.CFrame = head.CFrame * CFrame.new(0, (style.Offset.Y - 4.65) * headScale, style.Offset.Z)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = hat
		weld.Parent = hat
		hat.Parent = model
	end
	return model
end

-- Enche os lugares de avatar: primeiro amigos do dono, depois bonecos-padrão (um por vez, pela fila)
local function loadFriendAvatars(crowd: Crowd)
	if crowd.FriendSlots <= 0 then
		return
	end
	local friendsConfig = AmbienceConfig.Crowd.Friends
	local list = friendLists[crowd.OwnerUserId] or {}
	local friendCap = if friendsConfig.Enabled
		then (if crowd.IsMine then friendsConfig.MaxOwn else friendsConfig.MaxOther)
		else 0
	local token = crowd.LoadToken
	local nextFriend = 1
	local friendsPlaced = 0
	local function step()
		if crowds[crowd.PlotIndex] ~= crowd or crowd.LoadToken ~= token then
			return -- público reconstruído entretanto
		end
		while #crowd.Friends < crowd.FriendSlots do
			local slot = #crowd.Friends + 1
			if friendsPlaced < friendCap and nextFriend <= #list then
				local friend = list[nextFriend]
				nextFriend += 1
				local template = getAvatarTemplate(friend.UserId)
				if crowds[crowd.PlotIndex] ~= crowd or crowd.LoadToken ~= token then
					return
				end
				if template then
					friendsPlaced += 1
					placeAvatar(crowd, friend.UserId, friend.DisplayName, template, slot)
					break
				end
			else
				local model = makeDefaultAvatar(crowd.PlotIndex * 1000 + slot)
				if not model then
					return -- sem rig base: esses lugares ficam vazios
				end
				if crowds[crowd.PlotIndex] ~= crowd or crowd.LoadToken ~= token then
					model:Destroy()
					return
				end
				placeAvatar(crowd, crowd.PlotIndex * 1000 + slot, nil, model, slot)
				model:Destroy() -- placeAvatar clona; este era só a fonte pintada
				break
			end
		end
		if #crowd.Friends < crowd.FriendSlots then
			enqueue(step) -- dá a vez aos outros terrenos
		end
	end
	enqueue(step)
end

-- Pose ------------------------------------------------------------------------------

local function writePose(crowd: Crowd, personIndex: number, person: Person, body: CFrame, armAngle: number)
	local offset = (personIndex - 1) * PARTS_PER_PERSON
	local cframes = crowd.CFrames
	local o = person.Offsets
	cframes[offset + 1] = body * o.LegL
	cframes[offset + 2] = body * o.LegR
	cframes[offset + 3] = body * o.Torso
	cframes[offset + 4] = body * o.Head
	cframes[offset + 5] = body * o.Hat
	cframes[offset + 6] = body * o.ShoulderL * CFrame.Angles(0, 0, -armAngle) * o.ArmHang
	cframes[offset + 7] = body * o.ShoulderR * CFrame.Angles(0, 0, armAngle) * o.ArmHang
end

local function setGlow(crowd: Crowd, glow: boolean)
	if crowd.Glow == glow then
		return
	end
	crowd.Glow = glow
	local colors = AmbienceConfig.Crowd.GlowstickColors
	for index, person in crowd.People do
		for _, arm in person.Arms do
			if glow then
				arm.Material = Enum.Material.Neon
				arm.Color = colors[(index - 1) % #colors + 1]
			else
				arm.Material = Enum.Material.SmoothPlastic
				arm.Color = person.ArmColor
			end
		end
	end
end

local function setFriendsMoving(crowd: Crowd, moving: boolean)
	for _, friend in crowd.Friends do
		local track = friend.Track
		if track then
			track:AdjustSpeed(if moving then 1 else 0)
		end
		if not moving then
			friend.Root.CFrame = friend.RootBase
		end
	end
end

local function applyStatic(crowd: Crowd)
	for index, person in crowd.People do
		writePose(crowd, index, person, person.Base, 0.12)
	end
	Workspace:BulkMoveTo(crowd.Parts, crowd.CFrames, Enum.BulkMoveMode.FireCFrameChanged)
	setFriendsMoving(crowd, false)
end

local function getJumpLift(crowd: Crowd, now: number, energy: number, phase: number): number
	local config = AmbienceConfig.Crowd
	local jumpElapsed = now - crowd.JumpStart
	local jumpDuration = config.DropJumpDuration
	if jumpElapsed < 0 or jumpElapsed >= jumpDuration then
		return 0
	end
	local progress = jumpElapsed / jumpDuration
	return config.DropJumpHeight
		* crowd.JumpStrength
		* energy
		* math.abs(math.sin(progress * math.pi * 2 + phase * 0.15))
		* (1 - progress * 0.4)
end

local function animate(crowd: Crowd, now: number, full: boolean)
	local config = AmbienceConfig.Crowd
	local pulse = AudioController.GetBeatPulse()
	local intensity = AudioController.GetIntensity()

	local phase: Types.DropPhase? = nil
	if crowd.IsMine then
		local dropState = BassDropController.Get()
		phase = if dropState then dropState.Phase else nil
	end
	local buildUp = phase == "BuildUp" or phase == "Window"
	local boost = phase == "Boost"

	local jumpElapsed = now - crowd.JumpStart
	local armsUpWindow = jumpElapsed >= 0 and jumpElapsed < config.DropJumpDuration * 2

	for index, person in crowd.People do
		local lift: number
		if buildUp then
			lift = config.BuildUpBounce * person.Energy * math.abs(math.sin(now * math.pi * BEAT_RATE * 2 + person.Phase))
		else
			lift = config.BounceHeight * person.Energy * pulse * (0.4 + 0.6 * intensity)
		end
		lift += getJumpLift(crowd, now, person.Energy, person.Phase)

		local armAngle: number
		if boost or armsUpWindow then
			armAngle = ARMS_UP + 0.3 * math.sin(now * 8 + person.Phase)
		elseif not full then
			armAngle = 0.12
		elseif buildUp then
			armAngle = 0.9 + 0.6 * math.sin(now * 6 + person.Phase)
		else
			armAngle = 0.12 + 0.6 * pulse * intensity * person.ArmStyle
		end

		local body = person.Base * CFrame.new(0, lift, 0)
		if full then
			body *= CFrame.Angles(0, math.rad(8) * math.sin(now * 1.7 + person.Phase), 0)
		end
		writePose(crowd, index, person, body, armAngle)
	end
	Workspace:BulkMoveTo(crowd.Parts, crowd.CFrames, Enum.BulkMoveMode.FireCFrameChanged)

	-- Amigos: a dança é a animação; aqui só os saltos (build-up e Bass Drop)
	for _, friend in crowd.Friends do
		local lift = getJumpLift(crowd, now, friend.Energy, friend.Phase)
		if buildUp and full then
			lift += 0.6 * config.BuildUpBounce * math.abs(math.sin(now * math.pi * BEAT_RATE * 2 + friend.Phase))
		end
		friend.Root.CFrame = friend.RootBase * CFrame.new(0, lift, 0)
	end

	if crowd.IsMine then
		setGlow(crowd, boost)
	end
end

-- LOD ---------------------------------------------------------------------------------

local function setMode(crowd: Crowd, mode: CrowdMode)
	if crowd.Mode == mode then
		return
	end
	local previous = crowd.Mode
	crowd.Mode = mode
	crowd.Folder.Parent = if mode == "Hidden" then nil else getRootFolder()
	if mode == "Static" or previous == "Hidden" then
		applyStatic(crowd)
	end
	if mode == "Full" or mode == "Animated" then
		setFriendsMoving(crowd, true)
	end
end

local function updateLod()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local origin = camera.CFrame.Position
	local lod = LodConfig.Crowd
	for _, crowd in crowds do
		local distance = (crowd.Center - origin).Magnitude
		local mode: CrowdMode
		if crowd.IsMine then
			mode = if distance <= lod.StaticDistance then "Full" else "Static"
		elseif distance <= lod.AnimatedDistance then
			mode = "Animated"
		elseif distance <= lod.StaticDistance then
			mode = "Static"
		else
			mode = "Hidden"
		end
		setMode(crowd, mode)
	end
end

local function update()
	local now = os.clock()
	if now - lastLodCheck >= LodConfig.Crowd.CheckInterval then
		lastLodCheck = now
		updateLod()
	end
	local otherInterval = 1 / LodConfig.Crowd.OtherUpdateRate
	for _, crowd in crowds do
		if crowd.Mode == "Full" then
			animate(crowd, now, true)
		elseif crowd.Mode == "Animated" and now - crowd.LastUpdate >= otherInterval then
			crowd.LastUpdate = now
			animate(crowd, now, false)
		end
	end
end

-- Bass Drop ----------------------------------------------------------------------------

local function confettiScale(crowd: Crowd): number
	if crowd.IsMine then
		return 1
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return 0
	end
	local distance = (crowd.Center - camera.CFrame.Position).Magnitude
	local vfx = LodConfig.Vfx
	if distance <= vfx.LightDistance then
		return vfx.Scale.Light
	elseif distance <= vfx.HideDistance then
		return vfx.Scale.Minimal
	end
	return 0
end

local function onResolved(result: DropResolved)
	if not result.Success then
		return
	end
	for _, crowd in crowds do
		if crowd.OwnerUserId == result.UserId then
			local strengths = (AmbienceConfig.Crowd.GradeStrength :: unknown) :: { [string]: number }
			local strength = if result.Grade then strengths[result.Grade] or 1 else 1
			crowd.JumpStart = os.clock()
			crowd.JumpStrength = strength
			local emitter = crowd.Confetti
			local amount = math.floor(AmbienceConfig.Crowd.ConfettiBase * strength * confettiScale(crowd))
			if emitter and amount > 0 then
				emitter:Emit(amount)
			end
		end
	end
end

-- Terrenos ---------------------------------------------------------------------------

local function numberAttribute(instance: Instance?, name: string): number
	local value = if instance then instance:GetAttribute(name) else nil
	return if type(value) == "number" then value else 0
end

local refreshPlot: (plot: Instance) -> ()
local queueRefresh: (plot: Instance) -> ()

-- Liga-se aos atributos públicos do dono (nível do público e World Tours)
local function watchOwner(index: number, plot: Instance, owner: Player?)
	local previous = ownerConnections[index]
	if previous then
		for _, connection in previous do
			connection:Disconnect()
		end
		ownerConnections[index] = nil
	end
	if not owner then
		return
	end
	local connections: { RBXScriptConnection } = {}
	for _, name in { "FE_CrowdLevel", "FE_WorldTours" } do
		table.insert(
			connections,
			owner:GetAttributeChangedSignal(name):Connect(function()
				queueRefresh(plot)
			end)
		)
	end
	ownerConnections[index] = connections
end

-- Lugares de avatar: amigos (até ao limite e ao tamanho da lista) + bonecos-padrão até ao total
local function getFriendSlots(ownerUserId: number, isMine: boolean, count: number): number
	local crowdConfig = AmbienceConfig.Crowd
	local friends = crowdConfig.Friends
	local defaults = crowdConfig.DefaultAvatars
	local list = friendLists[ownerUserId]
	local friendCount = if friends.Enabled and list
		then math.min(if isMine then friends.MaxOwn else friends.MaxOther, #list)
		else 0
	local total = if defaults.Enabled
		then math.max(friendCount, if isMine then defaults.MaxOwn else defaults.MaxOther)
		else friendCount
	return math.min(total, count)
end

refreshPlot = function(plot: Instance)
	local index = plot:GetAttribute("PlotId")
	if type(index) ~= "number" then
		return
	end
	local ownerAttribute = plot:GetAttribute("OwnerUserId")
	local ownerUserId = if type(ownerAttribute) == "number" then ownerAttribute else 0
	if ownerUserId <= 0 then
		watchOwner(index, plot, nil)
		destroyCrowd(index)
		return
	end
	local owner = Players:GetPlayerByUserId(ownerUserId)
	local existing = crowds[index]
	if not existing or existing.OwnerUserId ~= ownerUserId then
		watchOwner(index, plot, owner)
	end

	if AmbienceConfig.Crowd.Friends.Enabled and not friendLists[ownerUserId] then
		fetchFriendList(ownerUserId, function()
			if plot.Parent then
				queueRefresh(plot)
			end
		end)
	end

	local isMine = ownerUserId == Players.LocalPlayer.UserId
	local level = math.max(1, numberAttribute(owner, "FE_CrowdLevel"))
	local count = CrowdCalc.GetCount(level, numberAttribute(owner, "FE_WorldTours"), isMine)
	local friendSlots = getFriendSlots(ownerUserId, isMine, count)
	if
		existing
		and existing.OwnerUserId == ownerUserId
		and existing.Count == count
		and existing.FriendSlots == friendSlots
		and existing.ListLoaded == (friendLists[ownerUserId] ~= nil)
	then
		return
	end
	destroyCrowd(index)
	if count <= 0 then
		return
	end
	local crowd = buildCrowd(index, ownerUserId, count, friendSlots)
	crowds[index] = crowd
	crowd.Mode = "Hidden"
	lastLodCheck = 0 -- decide o modo já no próximo frame
	loadFriendAvatars(crowd)
end

-- Agrupa várias alterações (troca de dono + atributos) num só rebuild
queueRefresh = function(plot: Instance)
	local index = plot:GetAttribute("PlotId")
	if type(index) ~= "number" or rebuildQueued[index] then
		return
	end
	rebuildQueued[index] = true
	task.delay(0.2, function()
		rebuildQueued[index] = nil
		if plot.Parent then
			refreshPlot(plot)
		end
	end)
end

local function watchPlot(plot: Instance)
	queueRefresh(plot)
	trove:Connect(plot:GetAttributeChangedSignal("OwnerUserId"), function()
		queueRefresh(plot)
	end)
end

function CrowdController.Init()
	trove:Connect(RunService.RenderStepped, update)
	trove:Add(BassDropController.Resolved:Connect(onResolved))
	trove:Add(function()
		for _, connections in ownerConnections do
			for _, connection in connections do
				connection:Disconnect()
			end
		end
		table.clear(ownerConnections)
		for _, template in avatarTemplates do
			if template then
				template:Destroy()
			end
		end
		local base = defaultTemplate
		if base then
			base:Destroy()
		end
	end)
end

function CrowdController.Start()
	trove:Add(task.spawn(function()
		local map = Workspace:WaitForChild("Map")
		local plots = map:WaitForChild("Plots")
		for _, plot in plots:GetChildren() do
			watchPlot(plot)
		end
		trove:Connect(plots.ChildAdded, watchPlot)
		-- O dono pode entrar depois de o terreno lhe ser atribuído: volta a ligar os atributos
		trove:Connect(Players.PlayerAdded, function(player: Player)
			for _, plot in plots:GetChildren() do
				if plot:GetAttribute("OwnerUserId") == player.UserId then
					local index = plot:GetAttribute("PlotId")
					if type(index) == "number" then
						watchOwner(index, plot, player)
					end
					queueRefresh(plot)
				end
			end
		end)
	end))
end

return CrowdController
