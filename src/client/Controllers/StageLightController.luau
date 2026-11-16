--!strict
--[[
	StageLightController
	Brilho das luzes dos palcos (só no cliente):
	  - Peças com a tag FE_StageLight (Neon_*, Led*, LEDScreen dos modelos do Blender,
	    marcadas pelo World/ModelPaint) ficam com a cor escurecida fora do drop: o néon
	    brilha muito menos.
	  - No build-up/janela do dono do terreno piscam a cada batida; no boost do Bass Drop
	    acendem com brilho total (e pulsam com a música).
	  - O Bloom do Lighting (FE_BloomEffect) é suave e só sobe no drop do próprio jogador.
	Luzes fora de qualquer terreno (ex.: praça) seguem o drop do próprio jogador.
	Valores em Config/Lighting (StageLights, Bloom, DropBloom).
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Types = require(ReplicatedStorage.Shared.Types)
local LightingConfig = require(ReplicatedStorage.Shared.Config.Lighting)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local AudioController = require(script.Parent.AudioController)
local BassDropController = require(script.Parent.BassDropController)

type DropResolved = Types.DropResolved
type LightState = "Idle" | "BuildUp" | "Boost"

type Light = {
	Part: BasePart,
	Color: Color3, -- cor original (brilho total)
	OwnerKey: number, -- UserId do dono do terreno (0 = segue o próprio jogador)
}

local LIGHT_TAG = "FE_StageLight"
local BLACK = Color3.new(0, 0, 0)

local StageLightController = {}

local trove = Trove.new()
local lights: { [BasePart]: Light } = {}
local otherBoostUntil: { [number]: number } = {} -- UserId -> os.clock() do fim do boost visto de fora
local lastBloomState: LightState? = nil

local function getOwnerKey(part: BasePart): number
	local current: Instance? = part.Parent
	while current do
		local plotId = current:GetAttribute("PlotId")
		if type(plotId) == "number" then
			local owner = current:GetAttribute("OwnerUserId")
			return if type(owner) == "number" then owner else 0
		end
		current = current.Parent
	end
	return 0
end

local function addLight(instance: Instance)
	if not instance:IsA("BasePart") or lights[instance] then
		return
	end
	local light: Light = { Part = instance, Color = instance.Color, OwnerKey = getOwnerKey(instance) }
	lights[instance] = light
	instance.Color = light.Color:Lerp(BLACK, LightingConfig.StageLights.IdleDim)
end

local function removeLight(instance: Instance)
	if instance:IsA("BasePart") then
		lights[instance] = nil
	end
end

local function getOwnState(): LightState
	local state = BassDropController.Get()
	local phase = if state then state.Phase else nil
	if phase == "Boost" and BassDropController.GetBoostMultiplier() > 1 then
		return "Boost"
	elseif phase == "BuildUp" or phase == "Window" then
		return "BuildUp"
	end
	return "Idle"
end

local function setBloom(state: LightState)
	if state == lastBloomState then
		return
	end
	lastBloomState = state
	local bloom = Lighting:FindFirstChild("FE_BloomEffect")
	if not bloom or not bloom:IsA("BloomEffect") then
		return
	end
	local target = if state == "Boost" then LightingConfig.DropBloom else LightingConfig.Bloom
	TweenService:Create(bloom, TweenInfo.new(LightingConfig.StageLights.TweenSeconds), {
		Intensity = target.Intensity,
		Size = target.Size,
		Threshold = target.Threshold,
	}):Play()
end

local function update()
	local config = LightingConfig.StageLights
	local now = os.clock()
	local pulse = AudioController.GetBeatPulse()
	local myUserId = Players.LocalPlayer.UserId
	local ownState = getOwnState()
	setBloom(ownState)

	-- Escurecimento por estado (calculado uma vez por dono)
	local dimByOwner: { [number]: number } = {}
	local function dimFor(ownerKey: number): number
		local cached = dimByOwner[ownerKey]
		if cached then
			return cached
		end
		local state: LightState
		if ownerKey == 0 or ownerKey == myUserId then
			state = ownState
		else
			state = if (otherBoostUntil[ownerKey] or 0) > now then "Boost" else "Idle"
		end
		local dim: number
		if state == "Boost" then
			dim = config.BoostDim + config.BeatFlash * (1 - pulse)
		elseif state == "BuildUp" then
			dim = config.BuildUpDim + config.BeatFlash * (1 - pulse)
		else
			dim = config.IdleDim
		end
		dim = math.clamp(dim, 0, 1)
		dimByOwner[ownerKey] = dim
		return dim
	end

	for part, light in lights do
		if part.Parent == nil then
			lights[part] = nil
		else
			local color = light.Color:Lerp(BLACK, dimFor(light.OwnerKey))
			if part.Color ~= color then
				part.Color = color
			end
		end
	end
end

local function onResolved(result: DropResolved)
	if result.Success and result.UserId ~= Players.LocalPlayer.UserId then
		otherBoostUntil[result.UserId] = os.clock() + LightingConfig.StageLights.OtherBoostSeconds
	end
end

function StageLightController.Init()
	trove:Connect(CollectionService:GetInstanceAddedSignal(LIGHT_TAG), addLight)
	trove:Connect(CollectionService:GetInstanceRemovedSignal(LIGHT_TAG), removeLight)
	for _, instance in CollectionService:GetTagged(LIGHT_TAG) do
		addLight(instance)
	end
	trove:Add(BassDropController.Resolved:Connect(onResolved))
	trove:Connect(RunService.Heartbeat, update)
end

return StageLightController
