--!strict
--[[
	CrateZoneController
	Deteta quando o jogador local entra/sai da Zona das Crates (círculo no centro da
	praça, Config/Map.Plaza.CrateZone) e emite Entered/Exited.
	Verifica a posição a CheckInterval (5 Hz), nunca por frame. Usa histerese
	(entra a TriggerRadius, sai a TriggerRadius + ExitMargin) para não oscilar na borda.
	Só apresentação: abrir o menu não dá nenhum privilégio no servidor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Shared.Config.Map)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)

local ZONE = MapConfig.Plaza.CrateZone
local CENTER = Vector3.new(0, ZONE.Height, 0) -- centro da praça = origem do mapa

local CrateZoneController = {}

local entered: Signal.Signal<()> = Signal.new()
local exited: Signal.Signal<()> = Signal.new()

CrateZoneController.Entered = entered
CrateZoneController.Exited = exited

local trove = Trove.new()
local inside = false
local running = false

function CrateZoneController.IsInside(): boolean
	return inside
end

local function isCharacterInZone(radius: number): boolean
	local character = Players.LocalPlayer.Character
	if not character then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return false
	end
	local offset = root.Position - CENTER
	if offset.Y < -2 or offset.Y > ZONE.TriggerHeight then
		return false
	end
	return Vector2.new(offset.X, offset.Z).Magnitude <= radius
end

local function check()
	local radius = if inside then ZONE.TriggerRadius + ZONE.ExitMargin else ZONE.TriggerRadius
	local now = isCharacterInZone(radius)
	if now == inside then
		return
	end
	inside = now
	if now then
		entered:Fire()
	else
		exited:Fire()
	end
end

function CrateZoneController.Init()
	if running then
		return
	end
	running = true
	trove:Add(function()
		running = false
	end)
	task.spawn(function()
		while running do
			check()
			task.wait(ZONE.CheckInterval)
		end
	end)
end

return CrateZoneController
