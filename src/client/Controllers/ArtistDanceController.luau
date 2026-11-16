--!strict
--[[
	ArtistDanceController
	Faz os artistas de TODOS os palcos dançar ao ritmo do relógio partilhado (BPM).
	  - Estilo procedimental pela família da raridade (Config/Ambience.Dance.ByFamily):
	    Sway (balanço), Jump (saltos), Headbang (cabeça/tronco à frente), Spin (rodar).
	  - Se Config/Ambience.ArtistAnimations[ArtistId] tiver um AnimationId e o modelo
	    tiver Humanoid, toca essa animação em loop (rig do Blender) em vez da procedimental.
	  - Num Bass Drop bem-sucedido do dono, os artistas desse palco dão um salto extra.
	Só mexe em CFrames/animações locais (nada replica). LOD: artistas a mais de
	LodConfig.StageAnimation.MaxDistance ficam parados.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local LodConfig = require(ReplicatedStorage.Shared.Config.Lod)
local AmbienceConfig = require(ReplicatedStorage.Shared.Config.Ambience)
local RaritiesConfig = require(ReplicatedStorage.Shared.Config.Rarities)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local AudioController = require(script.Parent.AudioController)
local BassDropController = require(script.Parent.BassDropController)

type DanceStyle = Types.DanceStyle

type Dancer = {
	Model: Model,
	Base: CFrame, -- pivot colocado pelo servidor
	Phase: number, -- desfasamento entre artistas
	Near: boolean,
	Style: DanceStyle,
	OwnerUserId: number,
	JumpStart: number,
	Track: AnimationTrack?,
}

local BOUNCE_HEIGHT = 0.6
local SWAY_DEGREES = 6
local LOD_CHECK_INTERVAL = 1

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
	dancers[model] = {
		Model = model,
		Base = base :: CFrame,
		Phase = (tonumber(string.match(model.Name, "%d+")) or 1) * 0.37,
		Near = true,
		Style = getStyle(model),
		OwnerUserId = if type(owner) == "number" then owner else 0,
		JumpStart = -math.huge,
		Track = tryPlayAnimation(model),
	}
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
	for _, dancer in dancers do
		dancer.Near = (dancer.Base.Position - origin).Magnitude <= LodConfig.StageAnimation.MaxDistance
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

	local dance = AmbienceConfig.Dance
	local elapsed = now - dancer.JumpStart
	if elapsed >= 0 and elapsed < dance.DropJumpDuration then
		local progress = elapsed / dance.DropJumpDuration
		pose = CFrame.new(0, dance.DropJumpHeight * math.sin(progress * math.pi), 0) * pose
	end
	return pose
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
			if dancer.Track then
				-- Animação própria: só o salto do drop mexe no pivot
				local elapsed = now - dancer.JumpStart
				local dance = AmbienceConfig.Dance
				local lift = if elapsed >= 0 and elapsed < dance.DropJumpDuration
					then dance.DropJumpHeight * math.sin(elapsed / dance.DropJumpDuration * math.pi)
					else 0
				model:PivotTo(dancer.Base * CFrame.new(0, lift, 0))
			else
				model:PivotTo(dancer.Base * getPose(dancer, now, pulse, intensity, beat))
			end
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
