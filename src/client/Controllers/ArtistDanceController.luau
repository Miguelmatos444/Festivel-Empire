--!strict
--[[
	ArtistDanceController
	Faz os artistas de TODOS os palcos dançar ao ritmo do relógio partilhado (BPM).
	  - Estilo procedimental pela família da raridade (Config/Ambience.Dance.ByFamily):
	    Sway (balanço), Jump (saltos), Headbang (cabeça/tronco à frente), Spin (rodar).
	  - Se Config/Ambience.ArtistAnimations[ArtistId] tiver um AnimationId e o modelo
	    tiver Humanoid, toca essa animação em loop em vez da procedimental.
	  - Num Bass Drop bem-sucedido do dono, os artistas desse palco dão um salto extra.
	  - Kits de raridade (Config/RarityCosmetics): no mesmo ciclo da dança, anima as peças
	    pelo prefixo do nome (Spin_, Orbit_, Float_, Flap_, Pulse_) a partir dos atributos
	    KitOffset/KitCenter gravados pelo servidor, e cria as partículas dos FXPoint_<Efeito>.
	Só mexe em CFrames/efeitos locais (nada replica). LOD: artistas a mais de
	LodConfig.StageAnimation.MaxDistance ficam parados e sem partículas; teto de
	emissores ativos (o próprio palco tem prioridade).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local LodConfig = require(ReplicatedStorage.Shared.Config.Lod)
local AmbienceConfig = require(ReplicatedStorage.Shared.Config.Ambience)
local RaritiesConfig = require(ReplicatedStorage.Shared.Config.Rarities)
local RarityCosmetics = require(ReplicatedStorage.Shared.Config.RarityCosmetics)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local AudioController = require(script.Parent.AudioController)
local BassDropController = require(script.Parent.BassDropController)

type DanceStyle = Types.DanceStyle
type KitStyle = RarityCosmetics.KitStyle
type EffectPreset = RarityCosmetics.EffectPreset

type KitPart = {
	Part: BasePart,
	Offset: CFrame, -- relativo ao BaseCFrame do rig
	Center: CFrame, -- centro da cabeça (KitOrigin), relativo ao BaseCFrame
	Scale: number,
	Spin: boolean,
	Orbit: boolean,
	Float: boolean,
	Flap: boolean,
	Pulse: boolean,
	Phase: number,
	Side: number, -- -1 esquerda, 1 direita (asas)
	BaseTransparency: number,
}

type Effect = {
	Instance: ParticleEmitter | PointLight | Beam,
}

type Dancer = {
	Model: Model,
	Base: CFrame, -- pivot colocado pelo servidor
	Facing: CFrame, -- rotação "virada para o público" (só yaw): os movimentos são feitos neste referencial
	Phase: number, -- desfasamento entre artistas
	Near: boolean,
	Style: DanceStyle,
	OwnerUserId: number,
	IsMine: boolean,
	JumpStart: number,
	Track: AnimationTrack?,
	Kit: KitStyle?,
	KitParts: { KitPart },
	KitMoving: { BasePart }, -- peças com movimento (para BulkMoveTo)
	KitCFrames: { CFrame },
	Effects: { Effect },
	EffectsOn: boolean,
}

local BOUNCE_HEIGHT = 0.6
local SWAY_DEGREES = 6
local LOD_CHECK_INTERVAL = 1
local KIT_PREFIX_LENGTH = 32

local ArtistDanceController = {}

local trove = Trove.new()
local dancers: { [Model]: Dancer } = {}
local lastLodCheck = 0

local function getStyle(model: Model): DanceStyle
	local rarity = model:GetAttribute("Rarity")
	local def = if type(rarity) == "string" then RaritiesConfig.ById[rarity] else nil
	local style = if def then AmbienceConfig.Dance.ByFamily[def.Family] else nil
	return style or "Sway"
end

-- Animação própria do artista (rig do Blender), se configurada
local function tryPlayAnimation(model: Model): AnimationTrack?
	local artistId = model:GetAttribute("ArtistId")
	local animationId = if type(artistId) == "string" then AmbienceConfig.ArtistAnimations[artistId] else nil
	if not animationId or animationId <= 0 then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(animationId)
	local ok, track = pcall(function(): AnimationTrack
		return (animator :: Animator):LoadAnimation(animation)
	end)
	if not ok then
		warn("[ArtistDance] Falha a carregar a animação de " .. tostring(artistId) .. ": " .. tostring(track))
		return nil
	end
	track.Looped = true
	track:Play()
	return track
end

-- Kits de raridade ------------------------------------------------------------------

local function findKit(part: Instance): Instance?
	local current = part.Parent
	while current do
		if current:GetAttribute("KitCenter") ~= nil then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function createEffect(part: BasePart, preset: EffectPreset, rateScale: number, kitScale: number): Effect?
	local colors = preset.Color
	if preset.Kind == "Light" then
		local light = Instance.new("PointLight")
		light.Color = colors[1]
		light.Range = (preset.Range or 8) * kitScale
		light.Brightness = 1.5
		light.Shadows = false
		light.Enabled = false
		light.Parent = part
		return { Instance = light }
	elseif preset.Kind == "Beam" then
		local a0 = Instance.new("Attachment")
		a0.Name = "BeamStart"
		a0.Parent = part
		local a1 = Instance.new("Attachment")
		a1.Name = "BeamEnd"
		a1.Position = Vector3.new(0, (preset.Range or 8) * kitScale, 0)
		a1.Parent = part
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Width0 = preset.Size * kitScale
		beam.Width1 = 0
		beam.FaceCamera = true
		beam.LightEmission = preset.LightEmission
		beam.Transparency = NumberSequence.new(0.3, 1)
		beam.Color = ColorSequence.new(colors[1], colors[#colors])
		beam.Enabled = false
		beam.Parent = part
		return { Instance = beam }
	end
	local emitter = Instance.new("ParticleEmitter")
	local keypoints: { ColorSequenceKeypoint } = {}
	for index, color in colors do
		table.insert(keypoints, ColorSequenceKeypoint.new(if #colors > 1 then (index - 1) / (#colors - 1) else 0, color))
	end
	if #keypoints == 1 then
		table.insert(keypoints, ColorSequenceKeypoint.new(1, colors[1]))
	end
	emitter.Color = ColorSequence.new(keypoints)
	local texture = preset.Texture
	if texture then
		emitter.Texture = texture
	end
	emitter.Rate = preset.Rate * rateScale
	emitter.Lifetime = preset.Lifetime
	emitter.Speed = NumberRange.new(preset.Speed.Min * kitScale, preset.Speed.Max * kitScale)
	emitter.Size = NumberSequence.new(preset.Size * kitScale, 0)
	emitter.SpreadAngle = Vector2.new(preset.SpreadAngle, preset.SpreadAngle)
	emitter.Acceleration = preset.Acceleration * kitScale
	emitter.LightEmission = preset.LightEmission
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Enabled = false
	emitter.Parent = part
	return { Instance = emitter }
end

local function addKitPart(dancer: Dancer, part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local offset = part:GetAttribute("KitOffset")
	if typeof(offset) ~= "CFrame" then
		return
	end
	local kit = findKit(part)
	local center = if kit then kit:GetAttribute("KitCenter") else nil
	local scaleValue = if kit then kit:GetAttribute("KitScale") else nil
	local centerCFrame: CFrame = if typeof(center) == "CFrame" then center else offset
	local scale = if type(scaleValue) == "number" then scaleValue else 1
	local name = string.sub(part.Name, 1, KIT_PREFIX_LENGTH)

	local effectName = string.match(part.Name, "FXPoint_(%a+)")
	if effectName then
		local preset = RarityCosmetics.Effects[effectName]
		local style = dancer.Kit
		if preset and style then
			local rateScale = style.ParticleScale * (if dancer.IsMine then 1 else RarityCosmetics.OtherPlotParticleScale)
			local effect = createEffect(part, preset, rateScale, scale)
			if effect then
				table.insert(dancer.Effects, effect)
			end
		end
		return
	end

	local localOffset = centerCFrame:PointToObjectSpace((offset :: CFrame).Position)
	local entry: KitPart = {
		Part = part,
		Offset = offset :: CFrame,
		Center = centerCFrame,
		Scale = scale,
		Spin = string.find(name, "Spin_", 1, true) ~= nil,
		Orbit = string.find(name, "Orbit_", 1, true) ~= nil,
		Float = string.find(name, "Float_", 1, true) ~= nil,
		Flap = string.find(name, "Flap_", 1, true) ~= nil,
		Pulse = string.find(name, "Pulse_", 1, true) ~= nil,
		Phase = (tonumber(string.match(part.Name, "(%d+)$")) or 0) * 0.9,
		Side = if localOffset.X < 0 then -1 else 1,
		BaseTransparency = part.Transparency,
	}
	table.insert(dancer.KitParts, entry)
	if entry.Spin or entry.Orbit or entry.Float or entry.Flap then
		table.insert(dancer.KitMoving, part)
		table.insert(dancer.KitCFrames, part.CFrame)
	end
end

local function setEffects(dancer: Dancer, on: boolean)
	if dancer.EffectsOn == on then
		return
	end
	dancer.EffectsOn = on
	for _, effect in dancer.Effects do
		effect.Instance.Enabled = on
	end
end

-- Dançarinos -----------------------------------------------------------------------

--[[
	A posição de referência vem do atributo "BaseCFrame" que o servidor grava no rig.
	(Ler o pivot no ChildAdded não é seguro: as peças do modelo podem ainda não ter
	replicado e o pivot viria errado, levando o artista para longe do palco.)
]]
local function addDancer(model: Instance)
	if not model:IsA("Model") or dancers[model] then
		return
	end
	local base = model:GetAttribute("BaseCFrame")
	if typeof(base) ~= "CFrame" then
		local connection: RBXScriptConnection
		connection = model:GetAttributeChangedSignal("BaseCFrame"):Connect(function()
			connection:Disconnect()
			addDancer(model)
		end)
		trove:Add(connection)
		return
	end
	local owner = model:GetAttribute("OwnerUserId")
	local ownerUserId = if type(owner) == "number" then owner else 0
	local rarity = model:GetAttribute("Rarity")
	local dancer: Dancer = {
		Model = model,
		Base = base :: CFrame,
		Facing = if typeof(model:GetAttribute("Facing")) == "CFrame"
			then (model:GetAttribute("Facing") :: CFrame).Rotation
			else (base :: CFrame).Rotation,
		Phase = (tonumber(string.match(model.Name, "%d+")) or 1) * 0.37,
		Near = true,
		Style = getStyle(model),
		OwnerUserId = ownerUserId,
		IsMine = ownerUserId == Players.LocalPlayer.UserId,
		JumpStart = -math.huge,
		Track = tryPlayAnimation(model),
		Kit = if type(rarity) == "string" then RarityCosmetics.ByRarity[rarity] else nil,
		KitParts = {},
		KitMoving = {},
		KitCFrames = {},
		Effects = {},
		EffectsOn = false,
	}
	dancers[model] = dancer
	for _, descendant in model:GetDescendants() do
		addKitPart(dancer, descendant)
	end
	trove:Connect(model.DescendantAdded, function(descendant: Instance)
		if dancers[model] == dancer then
			addKitPart(dancer, descendant)
		end
	end)
	lastLodCheck = 0
end

local function watchArtistsFolder(folder: Instance)
	for _, child in folder:GetChildren() do
		addDancer(child)
	end
	trove:Connect(folder.ChildAdded, addDancer)
end

local function watchPlot(plot: Instance)
	local existing = plot:FindFirstChild("Artists")
	if existing then
		watchArtistsFolder(existing)
	end
	trove:Connect(plot.ChildAdded, function(child: Instance)
		if child.Name == "Artists" then
			watchArtistsFolder(child)
		end
	end)
end

local function updateLod()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local origin = camera.CFrame.Position
	local maxDistance = LodConfig.StageAnimation.MaxDistance
	for _, dancer in dancers do
		dancer.Near = (dancer.Base.Position - origin).Magnitude <= maxDistance
	end
	-- Teto de emissores: primeiro o próprio palco, depois os outros
	local budget = RarityCosmetics.MaxActiveEmitters
	for pass = 1, 2 do
		for _, dancer in dancers do
			if dancer.IsMine == (pass == 1) then
				local wanted = dancer.Near and #dancer.Effects > 0 and #dancer.Effects <= budget
				if wanted then
					budget -= #dancer.Effects
				end
				setEffects(dancer, wanted)
			end
		end
	end
end

local function getPose(dancer: Dancer, now: number, pulse: number, intensity: number, beat: number): CFrame
	local side = if (beat + math.floor(dancer.Phase * 10)) % 2 == 0 then 1 else -1
	local energy = 0.6 + 0.4 * intensity
	local style = dancer.Style
	local pose: CFrame
	if style == "Jump" then
		pose = CFrame.new(0, BOUNCE_HEIGHT * 2.2 * pulse * energy, 0)
	elseif style == "Headbang" then
		pose = CFrame.new(0, BOUNCE_HEIGHT * 0.5 * pulse * energy, 0) * CFrame.Angles(-math.rad(16) * pulse * energy, 0, 0)
	elseif style == "Spin" then
		local yaw = math.rad(35) * math.sin(now * 2.2 + dancer.Phase)
		pose = CFrame.new(0, BOUNCE_HEIGHT * pulse * energy, 0) * CFrame.Angles(0, yaw, 0)
	else
		local sway = math.rad(SWAY_DEGREES) * side * (0.5 + 0.5 * pulse)
		pose = CFrame.new(0, BOUNCE_HEIGHT * pulse * energy, 0) * CFrame.Angles(0, 0, sway)
	end
	return pose
end

local function getJumpLift(dancer: Dancer, now: number): number
	local dance = AmbienceConfig.Dance
	local elapsed = now - dancer.JumpStart
	if elapsed >= 0 and elapsed < dance.DropJumpDuration then
		return dance.DropJumpHeight * math.sin(elapsed / dance.DropJumpDuration * math.pi)
	end
	return 0
end

-- Posição de uma peça do kit (no espaço do BaseCFrame) no instante `now`
local function animateKitPart(entry: KitPart, style: KitStyle, now: number): CFrame
	local cf = entry.Offset
	if entry.Orbit then
		local relative = entry.Center:ToObjectSpace(cf)
		cf = entry.Center * CFrame.Angles(0, now * style.OrbitSpeed, 0) * relative
	end
	if entry.Flap then
		local shoulder = entry.Center * CFrame.new(entry.Side * 0.9 * entry.Scale, -1.3 * entry.Scale, 0)
		local relative = shoulder:ToObjectSpace(cf)
		local angle = entry.Side * math.rad(style.FlapAngle) * math.sin(now * style.FlapSpeed)
		cf = shoulder * CFrame.Angles(0, angle, 0) * relative
	end
	if entry.Spin then
		cf = CFrame.new(cf.Position) * CFrame.Angles(0, now * style.SpinSpeed + entry.Phase, 0) * cf.Rotation
	end
	if entry.Float then
		cf = CFrame.new(0, style.FloatAmplitude * entry.Scale * math.sin(now * style.FloatSpeed + entry.Phase), 0) * cf
	end
	return cf
end

local function updateKit(dancer: Dancer, pivot: CFrame, now: number, pulse: number)
	local style = dancer.Kit
	if not style or #dancer.KitParts == 0 then
		return
	end
	local moving = 0
	for _, entry in dancer.KitParts do
		if entry.Spin or entry.Orbit or entry.Float or entry.Flap then
			moving += 1
			dancer.KitCFrames[moving] = pivot * animateKitPart(entry, style, now)
		end
		if entry.Pulse then
			entry.Part.Transparency =
				math.clamp(entry.BaseTransparency + style.PulseStrength * (1 - pulse) * 0.8, 0, 0.95)
		end
	end
	if moving > 0 then
		Workspace:BulkMoveTo(dancer.KitMoving, dancer.KitCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function update()
	local now = os.clock()
	if now - lastLodCheck >= LOD_CHECK_INTERVAL then
		lastLodCheck = now
		updateLod()
	end

	local pulse = AudioController.GetBeatPulse()
	local intensity = AudioController.GetIntensity()
	local beat = AudioController.GetBeatIndex()

	for model, dancer in dancers do
		if model.Parent == nil then
			dancers[model] = nil
			local track = dancer.Track
			if track then
				track:Stop()
			end
		elseif dancer.Near and model.PrimaryPart then
			local lift = CFrame.new(0, getJumpLift(dancer, now), 0)
			-- Pose no referencial do público (Y = cima do mundo), aplicada à volta do pivot:
			-- funciona mesmo que o PrimaryPart do FBX venha com outra orientação
			local pose = if dancer.Track
				then lift -- animação própria: só o salto do drop mexe no pivot
				else lift * getPose(dancer, now, pulse, intensity, beat)
			local facing = dancer.Facing
			local pivot = CFrame.new(dancer.Base.Position) * facing * pose * facing:Inverse() * dancer.Base.Rotation
			model:PivotTo(pivot)
			updateKit(dancer, pivot, now, pulse)
		end
	end
end

local function onResolved(result: Types.DropResolved)
	if not result.Success then
		return
	end
	local now = os.clock()
	for _, dancer in dancers do
		if dancer.OwnerUserId == result.UserId then
			dancer.JumpStart = now + dancer.Phase * 0.05
		end
	end
end

function ArtistDanceController.Init()
	trove:Connect(RunService.RenderStepped, update)
	trove:Add(BassDropController.Resolved:Connect(onResolved))
end

function ArtistDanceController.Start()
	trove:Add(task.spawn(function()
		local map = Workspace:WaitForChild("Map")
		local plots = map:WaitForChild("Plots")
		for _, plot in plots:GetChildren() do
			watchPlot(plot)
		end
		trove:Connect(plots.ChildAdded, watchPlot)
	end))
end

return ArtistDanceController
