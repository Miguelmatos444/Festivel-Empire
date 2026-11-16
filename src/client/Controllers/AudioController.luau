--!strict
--[[
	AudioController
	Música do festival, riser do build-up, impacto do drop e sons de pirotecnia.
	Expõe GetIntensity() (0..1) para os efeitos visuais:
	  - com música configurada e carregada: Sound.PlaybackLoudness suavizado
	  - sem ids (Config/Audio = 0): pulso do relógio de BPM sincronizado com o servidor
	Sons com id 0 nunca são criados, por isso não há erros de asset na consola.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Types = require(ReplicatedStorage.Shared.Types)
local AudioConfig = require(ReplicatedStorage.Shared.Config.Audio)
local BassDropConfig = require(ReplicatedStorage.Shared.Config.BassDrop)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local DropCalc = require(ReplicatedStorage.Shared.Calc.DropCalc)
local BassDropController = require(script.Parent.BassDropController)

type DropState = Types.DropState
type DropResolved = Types.DropResolved

local AudioController = {}

local trove = Trove.new()
local music: Sound? = nil
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

local function onResolved(result: DropResolved)
	if result.UserId ~= Players.LocalPlayer.UserId or not result.Success then
		return
	end
	AudioController.Play("Impact")
	for _, id in DropCalc.MaskToIds(result.Mask) do
		AudioController.Play(id)
	end
end

function AudioController.Init()
	local volumes = AudioConfig.Volumes
	music = createSound("FestivalMusic", AudioConfig.MusicLoop, volumes.Music, true)
	addCue("Riser", AudioConfig.BuildUpRiser, volumes.Riser)
	addCue("Impact", AudioConfig.DropImpact, volumes.Impact)
	for id, soundId in AudioConfig.Pyro do
		addCue(id, soundId, volumes.Pyro)
	end

	trove:Connect(RunService.RenderStepped, updateIntensity)
	trove:Add(BassDropController.Changed:Connect(onDropState))
	trove:Add(BassDropController.Resolved:Connect(onResolved))
end

function AudioController.Start()
	local current = music
	if not current then
		return
	end
	-- Alinha a posição da música com o relógio do servidor (igual para todos)
	local function syncAndPlay()
		if current.TimeLength > 0 then
			current.TimePosition = BassDropController.GetServerTime() % current.TimeLength
		end
		current:Play()
	end
	if current.IsLoaded then
		syncAndPlay()
	else
		trove:Add(current.Loaded:Once(syncAndPlay))
	end
end

return AudioController
