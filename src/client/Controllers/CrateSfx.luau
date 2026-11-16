--!strict
--[[
	CrateSfx
	Sons da abertura das crates e da cinemática (Config/Audio.Crate).
	Id 0 -> usa o som de fallback de Config/Audio.CrateFallbacks (ficheiros do cliente
	Roblox), por isso há sempre som mesmo sem ids próprios.
	Play: som 2D. PlayAt: som 3D num ponto do mundo (versão leve vista pelos outros).
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local AudioConfig = require(ReplicatedStorage.Shared.Config.Audio)
local LodConfig = require(ReplicatedStorage.Shared.Config.Lod)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)

local POSITIONAL_LIFETIME = 6
local MIN_REPLAY_INTERVAL = 0.03 -- evita sobrepor dezenas de "ticks" no mesmo frame

local CrateSfx = {}

local trove = Trove.new()
local sounds: { [string]: Sound } = {}
local lastPlayed: { [string]: number } = {}

function CrateSfx.Init()
	if next(sounds) ~= nil then
		return
	end
	for name, id in AudioConfig.Crate do
		local fallback = AudioConfig.CrateFallbacks[name]
		local sound = trove:Add(Instance.new("Sound"))
		sound.Name = "Crate_" .. name
		if id > 0 then
			sound.SoundId = "rbxassetid://" .. tostring(id)
			sound.Volume = AudioConfig.CrateVolume
		elseif fallback then
			sound.SoundId = fallback.Path
			sound.PlaybackSpeed = fallback.Speed
			sound.Volume = AudioConfig.CrateVolume * fallback.Volume
		end
		sound.Parent = SoundService
		sounds[name] = sound
	end
end

function CrateSfx.Play(name: string)
	local sound = sounds[name]
	if not sound or sound.SoundId == "" then
		return
	end
	local now = os.clock()
	if now - (lastPlayed[name] or 0) < MIN_REPLAY_INTERVAL then
		return
	end
	lastPlayed[name] = now
	sound.TimePosition = 0
	sound:Play()
end

-- Som 3D num ponto (com o alcance do LOD de áudio)
function CrateSfx.PlayAt(name: string, position: Vector3)
	local template = sounds[name]
	if not template or template.SoundId == "" then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "CrateSfx"
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain
	local sound = template:Clone()
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 15
	sound.RollOffMaxDistance = LodConfig.Cinematic.FullDistance
	sound.Volume = template.Volume * LodConfig.Audio.VolumeScale
	sound.Parent = attachment
	sound:Play()
	Debris:AddItem(attachment, POSITIONAL_LIFETIME)
end

return CrateSfx
