--!strict
--[[
	AudioController
	Música do festival, riser do build-up, impacto do drop e sons de pirotecnia.
	Expõe GetIntensity() (0..1) para os efeitos visuais:
	  - com música configurada e carregada: Sound.PlaybackLoudness suavizado
	  - sem ids (Config/Audio = 0): pulso do relógio de BPM sincronizado com o servidor
	Sons com id 0 nunca são criados, por isso não há erros de asset na consola.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local AudioConfig = require(ReplicatedStorage.Shared.Config.Audio)
local LodConfig = require(ReplicatedStorage.Shared.Config.Lod)
local BassDropConfig = require(ReplicatedStorage.Shared.Config.BassDrop)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local DropCalc = require(ReplicatedStorage.Shared.Calc.DropCalc)
local StageCalc = require(ReplicatedStorage.Shared.Calc.StageCalc)
local BassDropController = require(script.Parent.BassDropController)
local StateController = require(script.Parent.StateController)

type DropState = Types.DropState
type DropResolved = Types.DropResolved

local POSITIONAL_SOUND_LIFETIME = 8

local AudioController = {}

local trove = Trove.new()
local music: Sound? = nil -- faixa atual (a que está a entrar no crossfade)
local musicTracks: { [number]: Sound } = {} -- soundId -> Sound (uma instância por faixa)
local currentEra: string? = nil
local musicStarted = false
local cues: { [string]: Sound } = {}
local intensity = 0
local lastPhase: Types.DropPhase? = nil

local function createSound(name: string, id: number, volume: number, looped: boolean): Sound?
	if id <= 0 then
		return nil
	end
	local sound = trove:Add(Instance.new("Sound"))
	sound.Name = name
	sound.SoundId = "rbxassetid://" .. tostring(id)
	sound.Volume = volume
	sound.Looped = looped
	sound.Parent = SoundService
	return sound
end

local function addCue(name: string, id: number, volume: number)
	local sound = createSound(name, id, volume, false)
	if sound then
		cues[name] = sound
	end
end

-- Pulso de 0..1 com ataque no início de cada batida (relógio partilhado pelo servidor)
function AudioController.GetBeatPulse(): number
	local beats = BassDropController.GetServerTime() * BassDropConfig.BPM / 60
	local phase = beats % 1
	return (1 - phase) ^ 4
end

-- Índice da batida atual (inteiro), igual em todos os clientes
function AudioController.GetBeatIndex(): number
	return math.floor(BassDropController.GetServerTime() / DropCalc.GetBeatInterval())
end

function AudioController.GetIntensity(): number
	return intensity
end

function AudioController.IsUsingMusic(): boolean
	local current = music
	return current ~= nil and current.IsLoaded and current.IsPlaying
end

function AudioController.Play(cueName: string)
	local sound = cues[cueName]
	if sound then
		sound.TimePosition = 0
		sound:Play()
	end
end

local function updateIntensity(deltaTime: number)
	local current = music
	if current and current.IsLoaded and current.IsPlaying then
		local target = math.clamp(current.PlaybackLoudness / AudioConfig.LoudnessReference, 0, 1)
		intensity += (target - intensity) * math.min(1, deltaTime * AudioConfig.IntensitySmoothing)
	else
		intensity = AudioController.GetBeatPulse()
	end
end

local function onDropState(newState: DropState)
	if newState.Phase == "BuildUp" and lastPhase ~= "BuildUp" then
		AudioController.Play("Riser")
	end
	lastPhase = newState.Phase
end

-- LOD de áudio ---------------------------------------------------------------------

export type PositionResolver = (player: Player) -> Vector3?

local positionResolver: PositionResolver? = nil

-- Onde soam os sons de cada jogador (definido pelo PlotController: o palco do terreno)
function AudioController.SetPositionResolver(resolver: PositionResolver?)
	positionResolver = resolver
end

local function playAt(cueName: string, position: Vector3)
	local template = cues[cueName]
	if not template then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "AudioLod"
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain

	local sound = template:Clone()
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 10
	sound.RollOffMaxDistance = LodConfig.Audio.MaxDistance
	sound.Volume = template.Volume * LodConfig.Audio.VolumeScale
	sound.Parent = attachment
	sound:Play()
	Debris:AddItem(attachment, POSITIONAL_SOUND_LIFETIME)
end

--[[
	Toca um som de um jogador com LOD:
	  - o próprio jogador: som 2D normal
	  - outros: som 3D no palco deles, só até LodConfig.Audio.MaxDistance; além disso, silêncio
]]
function AudioController.PlayForPlayer(cueName: string, player: Player)
	if player == Players.LocalPlayer then
		AudioController.Play(cueName)
		return
	end
	local resolver = positionResolver
	local position = if resolver then resolver(player) else nil
	local camera = Workspace.CurrentCamera
	if not position or not camera then
		return
	end
	if (camera.CFrame.Position - position).Magnitude > LodConfig.Audio.MaxDistance then
		return
	end
	playAt(cueName, position)
end

local function onResolved(result: DropResolved)
	if not result.Success then
		return
	end
	local player = Players:GetPlayerByUserId(result.UserId)
	if not player then
		return
	end
	AudioController.PlayForPlayer("Impact", player)
	for _, id in DropCalc.MaskToIds(result.Mask) do
		AudioController.PlayForPlayer(id, player)
	end
end

-- Música por era (crossfade) ------------------------------------------------------------

local function getEraSoundId(era: string): number
	local id = AudioConfig.EraMusic[era] or 0
	return if id > 0 then id else AudioConfig.MusicLoop
end

local function getTrack(soundId: number): Sound?
	if soundId <= 0 then
		return nil
	end
	local existing = musicTracks[soundId]
	if existing then
		return existing
	end
	local sound = createSound("FestivalMusic_" .. soundId, soundId, 0, true)
	if sound then
		musicTracks[soundId] = sound
	end
	return sound
end

-- Alinha a posição da música com o relógio do servidor (igual para todos) e toca
local function syncAndPlay(sound: Sound)
	local function start()
		if sound.TimeLength > 0 then
			sound.TimePosition = BassDropController.GetServerTime() % sound.TimeLength
		end
		sound:Play()
	end
	if sound.IsLoaded then
		start()
	else
		trove:Add(sound.Loaded:Once(start))
	end
end

local function crossfadeTo(target: Sound?)
	local previous = music
	if target == previous then
		return
	end
	music = target
	local fade = TweenInfo.new(AudioConfig.CrossfadeSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	if previous then
		local fadeOut = TweenService:Create(previous, fade, { Volume = 0 })
		fadeOut.Completed:Once(function()
			if music ~= previous then
				previous:Stop()
			end
		end)
		fadeOut:Play()
	end
	if target then
		target.Volume = 0
		syncAndPlay(target)
		TweenService:Create(target, fade, { Volume = AudioConfig.Volumes.Music }):Play()
	end
end

-- Define a era do festival do próprio jogador (troca de faixa com crossfade)
function AudioController.SetEra(era: string)
	if era == currentEra then
		return
	end
	currentEra = era
	if musicStarted then
		crossfadeTo(getTrack(getEraSoundId(era)))
	end
end

function AudioController.Init()
	local volumes = AudioConfig.Volumes
	addCue("Riser", AudioConfig.BuildUpRiser, volumes.Riser)
	addCue("Impact", AudioConfig.DropImpact, volumes.Impact)
	for id, soundId in AudioConfig.Pyro do
		addCue(id, soundId, volumes.Pyro)
	end

	trove:Connect(RunService.RenderStepped, updateIntensity)
	trove:Add(BassDropController.Changed:Connect(onDropState))
	trove:Add(BassDropController.Resolved:Connect(onResolved))
	trove:Add(StateController.Changed:Connect(function(snapshot: Types.PlayerStateSnapshot)
		AudioController.SetEra(StageCalc.GetDef(snapshot.StageTier).Era)
	end))
end

function AudioController.Start()
	musicStarted = true
	local snapshot = StateController.Get()
	local era = currentEra or (if snapshot then StageCalc.GetDef(snapshot.StageTier).Era else "Underground")
	currentEra = era
	crossfadeTo(getTrack(getEraSoundId(era)))
end

return AudioController
