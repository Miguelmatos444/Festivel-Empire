--!strict
--[[
	CrowdController
	Público dinâmico em cada terreno ocupado (só no cliente: nada replica).
	  - Tamanho pelo tier do palco (Config/Ambience.Crowd.ByTier): completo no próprio
	    terreno, reduzido nos outros.
	  - Reage à música (AudioController.GetIntensity / pulso de BPM), agita-se no
	    build-up e "explode" nos Bass Drops (salto + braços no ar + confetes; no
	    próprio terreno, glowsticks durante o boost). Força pela nota do drop.
	  - LOD (Config/Lod.Crowd) para os outros terrenos: animado (só saltos, a
	    OtherUpdateRate Hz) até AnimatedDistance, parado até StaticDistance,
	    escondido além. O próprio terreno é sempre completo.
	Cada pessoa tem 5 peças ancoradas, movidas em lote com Workspace:BulkMoveTo.
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
local MapCalc = require(ReplicatedStorage.Shared.Calc.MapCalc)
local AudioController = require(script.Parent.AudioController)
local BassDropController = require(script.Parent.BassDropController)

type DropResolved = Types.DropResolved

type CrowdMode = "Full" | "Animated" | "Static" | "Hidden"

type Person = {
	Base: CFrame, -- pés no chão, virado para o palco
	Phase: number,
	Energy: number, -- 0.6..1.2 (uns saltam mais do que outros)
	ArmStyle: number, -- 0..1
	Arms: { BasePart },
	ArmColor: Color3,
}

type Crowd = {
	PlotIndex: number,
	OwnerUserId: number,
	IsMine: boolean,
	Count: number,
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
}

local PARTS_PER_PERSON = 5
local LEGS_OFFSET = CFrame.new(0, 1, 0)
local TORSO_OFFSET = CFrame.new(0, 3, 0)
local HEAD_OFFSET = CFrame.new(0, 4.7, 0)
local LEFT_SHOULDER = CFrame.new(-1.3, 3.8, 0)
local RIGHT_SHOULDER = CFrame.new(1.3, 3.8, 0)
local ARM_HANG = CFrame.new(0, -0.95, 0)
local ARMS_UP = 2.5 -- radianos (braços quase na vertical)
local BEAT_RATE = BassDropConfig.BPM / 60

local CrowdController = {}

local trove = Trove.new()
local crowds: { [number]: Crowd } = {}
local rootFolder: Folder? = nil
local lastLodCheck = 0
local rebuildQueued: { [number]: boolean } = {}

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

local function getCount(tier: number, isMine: boolean): number
	local count = 0
	for _, entry in AmbienceConfig.Crowd.ByTier do
		if tier >= entry.MinTier then
			count = if isMine then entry.Own else entry.Other
		end
	end
	return count
end

-- Posições aleatórias (determinísticas por terreno) com distância mínima; mais gente perto do palco
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
		crowd.Folder:Destroy()
	end
end

local function buildCrowd(index: number, ownerUserId: number, count: number): Crowd
	local config = AmbienceConfig.Crowd
	local plots = MapConfig.Plots
	local isMine = ownerUserId == Players.LocalPlayer.UserId
	local folder = Instance.new("Folder")
	folder.Name = "Crowd_" .. index

	local plotCFrame = MapCalc.GetPlotCFrame(index)
	local rng = Random.new(index * 104729 + count)
	local people: { Person } = {}
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}

	for _, position in generatePositions(index, count) do
		local base = plotCFrame
			* CFrame.new(position.X, plots.BaseThickness, -plots.Depth / 2 + position.Y)
			* CFrame.Angles(0, math.pi + math.rad(rng:NextNumber(-12, 12)), 0)
		local shirt = config.ShirtColors[rng:NextInteger(1, #config.ShirtColors)]
		local skin = config.SkinColors[rng:NextInteger(1, #config.SkinColors)]
		local pants = Color3.fromRGB(35, 35, 50):Lerp(Color3.fromRGB(70, 90, 140), rng:NextNumber())

		local legs = newPart("Legs", Vector3.new(1.6, 2, 0.8), pants, folder)
		local torso = newPart("Torso", Vector3.new(2, 2, 1), shirt, folder)
		local head = newPart("Head", Vector3.new(1.2, 1.2, 1.2), skin, folder)
		head.Shape = Enum.PartType.Ball
		local leftArm = newPart("LeftArm", Vector3.new(0.6, 1.9, 0.6), skin, folder)
		local rightArm = newPart("RightArm", Vector3.new(0.6, 1.9, 0.6), skin, folder)

		for _, part in { legs, torso, head, leftArm, rightArm } do
			table.insert(parts, part)
			table.insert(cframes, base)
		end
		table.insert(people, {
			Base = base,
			Phase = rng:NextNumber(0, math.pi * 2),
			Energy = rng:NextNumber(0.6, 1.2),
			ArmStyle = rng:NextNumber(),
			Arms = { leftArm, rightArm },
			ArmColor = skin,
		})
	end

	local crowd: Crowd = {
		PlotIndex = index,
		OwnerUserId = ownerUserId,
		IsMine = isMine,
		Count = count,
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
	}
	addConfetti(crowd)
	return crowd
end

-- Pose ------------------------------------------------------------------------------

local function writePose(crowd: Crowd, personIndex: number, body: CFrame, armAngle: number)
	local offset = (personIndex - 1) * PARTS_PER_PERSON
	local cframes = crowd.CFrames
	cframes[offset + 1] = body * LEGS_OFFSET
	cframes[offset + 2] = body * TORSO_OFFSET
	cframes[offset + 3] = body * HEAD_OFFSET
	cframes[offset + 4] = body * LEFT_SHOULDER * CFrame.Angles(0, 0, -armAngle) * ARM_HANG
	cframes[offset + 5] = body * RIGHT_SHOULDER * CFrame.Angles(0, 0, armAngle) * ARM_HANG
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

local function applyStatic(crowd: Crowd)
	for index, person in crowd.People do
		writePose(crowd, index, person.Base, 0.12)
	end
	Workspace:BulkMoveTo(crowd.Parts, crowd.CFrames, Enum.BulkMoveMode.FireCFrameChanged)
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
	local jumpDuration = config.DropJumpDuration
	local jumping = jumpElapsed >= 0 and jumpElapsed < jumpDuration
	local armsUpWindow = jumpElapsed >= 0 and jumpElapsed < jumpDuration * 2

	for index, person in crowd.People do
		local lift: number
		if buildUp then
			lift = config.BuildUpBounce * person.Energy * math.abs(math.sin(now * math.pi * BEAT_RATE * 2 + person.Phase))
		else
			lift = config.BounceHeight * person.Energy * pulse * (0.4 + 0.6 * intensity)
		end
		if jumping then
			local progress = jumpElapsed / jumpDuration
			lift += config.DropJumpHeight
				* crowd.JumpStrength
				* person.Energy
				* math.abs(math.sin(progress * math.pi * 2 + person.Phase * 0.15))
				* (1 - progress * 0.4)
		end

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
		writePose(crowd, index, body, armAngle)
	end
	Workspace:BulkMoveTo(crowd.Parts, crowd.CFrames, Enum.BulkMoveMode.FireCFrameChanged)

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

local function getPlotTier(plot: Instance): number
	local stage = plot:FindFirstChild("Stage")
	local tier = if stage then stage:GetAttribute("Tier") else nil
	return if type(tier) == "number" then tier else 1
end

local function refreshPlot(plot: Instance)
	local index = plot:GetAttribute("PlotId")
	if type(index) ~= "number" then
		return
	end
	local owner = plot:GetAttribute("OwnerUserId")
	local ownerUserId = if type(owner) == "number" then owner else 0
	if ownerUserId <= 0 then
		destroyCrowd(index)
		return
	end
	local isMine = ownerUserId == Players.LocalPlayer.UserId
	local count = getCount(getPlotTier(plot), isMine)
	local existing = crowds[index]
	if existing and existing.OwnerUserId == ownerUserId and existing.Count == count then
		return
	end
	destroyCrowd(index)
	if count <= 0 then
		return
	end
	local crowd = buildCrowd(index, ownerUserId, count)
	crowds[index] = crowd
	crowd.Mode = "Hidden"
	lastLodCheck = 0 -- decide o modo já no próximo frame
end

-- Agrupa várias alterações (troca de palco = remove + adiciona) num só rebuild
local function queueRefresh(plot: Instance)
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
	-- O servidor grava o atributo Tier antes de pôr o palco no terreno
	trove:Connect(plot.ChildAdded, function(child: Instance)
		if child.Name == "Stage" then
			queueRefresh(plot)
		end
	end)
end

function CrowdController.Init()
	trove:Connect(RunService.RenderStepped, update)
	trove:Add(BassDropController.Resolved:Connect(onResolved))
end

function CrowdController.Start()
	trove:Add(task.spawn(function()
		local map = Workspace:WaitForChild("Map")
		local plots = map:WaitForChild("Plots")
		for _, plot in plots:GetChildren() do
			watchPlot(plot)
		end
		trove:Connect(plots.ChildAdded, watchPlot)
	end))
end

return CrowdController
