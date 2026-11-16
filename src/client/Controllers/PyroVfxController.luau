--!strict
--[[
	PyroVfxController
	Efeitos 3D locais da pirotecnia para os drops de todos os jogadores, com LOD:
	  - drop do próprio jogador: Full (partículas completas + luzes)
	  - outros jogadores: Light até LightDistance, Minimal até HideDistance, nada além
	A intensidade (AudioController) modula as partículas a cada frame e as
	rajadas disparam em cada batida do relógio partilhado.

	Ponto de ancoragem: SetEmitterResolver(fn) recebe (jogador, idDaMáquina) e devolve
	a lista de CFrames onde essa máquina dispara. Por defeito usa posições à volta da
	personagem; na fase dos palcos aponta-se para os Attachments do palco.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local DropCalc = require(ReplicatedStorage.Shared.Calc.DropCalc)
local BassDropController = require(script.Parent.BassDropController)
local AudioController = require(script.Parent.AudioController)

type DropResolved = Types.DropResolved

export type LodLevel = "Full" | "Light" | "Minimal"
export type EmitterResolver = (player: Player, machineId: string) -> { CFrame }

type ActiveEffect = {
	Emitters: { ParticleEmitter },
	BaseRates: { number },
	BurstEmitters: { ParticleEmitter },
	BurstCount: number,
	Lights: { PointLight },
	Beams: { { Target: Attachment, Origin: Vector3, Phase: number } },
	EndsAt: number,
	Trove: Trove.Trove,
}

local VFX = {
	Duration = 4,
	LightDistance = 120,
	HideDistance = 250,
	Scale = { Full = 1, Light = 0.4, Minimal = 0.15 },
	Textures = {
		Spark = "rbxasset://textures/particles/sparkles_main.dds",
		Smoke = "rbxasset://textures/particles/smoke_main.dds",
		Fire = "rbxasset://textures/particles/fire_main.dds",
	},
	-- Posições relativas à personagem (x lateral, z para trás), usadas pelo resolver por defeito
	DefaultSlots = {
		ColdSparks = { Vector3.new(-6, 0, 2), Vector3.new(6, 0, 2) },
		CO2Cannon = { Vector3.new(-9, 0, 5), Vector3.new(9, 0, 5) },
		Lasers = { Vector3.new(-4, 0, 7), Vector3.new(4, 0, 7) },
		Flamethrower = { Vector3.new(-11, 0, 0), Vector3.new(11, 0, 0) },
	} :: { [string]: { Vector3 } },
}

local PyroVfxController = {}

local trove = Trove.new()
local effects: { ActiveEffect } = {}
local lowVfx = false
local lastBeat = -1

local function defaultResolver(player: Player, machineId: string): { CFrame }
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return {}
	end
	-- Base ao nível dos pés, orientada como a personagem, sempre na vertical
	local _, yaw, _ = root.CFrame:ToOrientation()
	local base = CFrame.new(root.Position - Vector3.new(0, 3, 0)) * CFrame.Angles(0, yaw, 0)
	local result: { CFrame } = {}
	for _, offset in VFX.DefaultSlots[machineId] or {} do
		table.insert(result, base * CFrame.new(offset))
	end
	return result
end

local resolver: EmitterResolver = defaultResolver

-- API pública --------------------------------------------------------------------

-- Resolver por defeito (à volta da personagem), útil como fallback de outros resolvers
PyroVfxController.DefaultResolver = defaultResolver

function PyroVfxController.SetEmitterResolver(newResolver: EmitterResolver?)
	resolver = newResolver or defaultResolver
end

function PyroVfxController.SetLowVfx(enabled: boolean)
	lowVfx = enabled
end

-- Construção -------------------------------------------------------------------

local function makeAttachment(effectTrove: Trove.Trove, worldCFrame: CFrame): Attachment
	local attachment = effectTrove:Add(Instance.new("Attachment"))
	attachment.Name = "PyroVfx"
	attachment.WorldCFrame = worldCFrame
	attachment.Parent = Workspace.Terrain
	return attachment
end

local function makeEmitter(attachment: Attachment, texture: string): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = texture
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.LockedToPart = false
	emitter.Rate = 0
	emitter.Parent = attachment
	return emitter
end

local function buildColdSparks(effect: ActiveEffect, attachment: Attachment, scale: number)
	local emitter = makeEmitter(attachment, VFX.Textures.Spark)
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 209, 102))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(25, 35)
	emitter.SpreadAngle = Vector2.new(8, 8)
	emitter.Acceleration = Vector3.new(0, -30, 0)
	table.insert(effect.Emitters, emitter)
	table.insert(effect.BaseRates, 140 * scale)
end

local function buildCO2(effect: ActiveEffect, attachment: Attachment, scale: number)
	local emitter = makeEmitter(attachment, VFX.Textures.Smoke)
	emitter.Color = ColorSequence.new(Color3.fromRGB(235, 245, 255))
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 7) })
	emitter.Lifetime = NumberRange.new(0.8, 1.3)
	emitter.Speed = NumberRange.new(45, 60)
	emitter.SpreadAngle = Vector2.new(6, 6)
	emitter.Drag = 3
	table.insert(effect.BurstEmitters, emitter)
	effect.BurstCount = math.max(effect.BurstCount, math.ceil(45 * scale))
end

local function buildFlames(effect: ActiveEffect, attachment: Attachment, scale: number, withLights: boolean)
	local emitter = makeEmitter(attachment, VFX.Textures.Fire)
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 190, 60), Color3.fromRGB(255, 60, 20))
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5) })
	emitter.Lifetime = NumberRange.new(0.5, 0.8)
	emitter.Speed = NumberRange.new(35, 45)
	emitter.SpreadAngle = Vector2.new(5, 5)
	table.insert(effect.BurstEmitters, emitter)
	effect.BurstCount = math.max(effect.BurstCount, math.ceil(60 * scale))

	if withLights then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 140, 40)
		light.Range = 22
		light.Brightness = 0
		light.Parent = attachment
		table.insert(effect.Lights, light)
	end
end

local function buildLasers(effect: ActiveEffect, effectTrove: Trove.Trove, attachment: Attachment, beamCount: number)
	local colors = { Color3.fromRGB(43, 210, 255), Color3.fromRGB(255, 60, 172) }
	for index = 1, beamCount do
		local origin = attachment.WorldPosition
		local target = makeAttachment(effectTrove, CFrame.new(origin + Vector3.new(0, 60, 0)))
		local beam = Instance.new("Beam")
		beam.Attachment0 = attachment
		beam.Attachment1 = target
		beam.Color = ColorSequence.new(colors[(index - 1) % #colors + 1])
		beam.LightEmission = 1
		beam.Width0 = 0.25
		beam.Width1 = 0.7
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Parent = attachment
		table.insert(effect.Beams, { Target = target, Origin = origin, Phase = index * math.pi / 2 })
	end
end

local function getLod(player: Player, firstCFrame: CFrame): LodLevel?
	if player == Players.LocalPlayer then
		return if lowVfx then "Light" else "Full"
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return "Minimal"
	end
	local distance = (camera.CFrame.Position - firstCFrame.Position).Magnitude
	if distance <= VFX.LightDistance then
		return "Light"
	elseif distance <= VFX.HideDistance then
		return "Minimal"
	end
	return nil
end

local function spawnShow(player: Player, mask: number)
	local machineIds = DropCalc.MaskToIds(mask)
	if #machineIds == 0 then
		return
	end

	for _, machineId in machineIds do
		local cframes = resolver(player, machineId)
		local first = cframes[1]
		local lod = if first then getLod(player, first) else nil
		if first and lod then
			local scale = if lod == "Full" then VFX.Scale.Full elseif lod == "Light" then VFX.Scale.Light else VFX.Scale.Minimal
			local effectTrove = trove:Extend()
			local effect: ActiveEffect = {
				Emitters = {},
				BaseRates = {},
				BurstEmitters = {},
				BurstCount = 0,
				Lights = {},
				Beams = {},
				EndsAt = os.clock() + VFX.Duration,
				Trove = effectTrove,
			}

			for _, cframe in cframes do
				local attachment = makeAttachment(effectTrove, cframe)
				if machineId == "ColdSparks" then
					buildColdSparks(effect, attachment, scale)
				elseif machineId == "CO2Cannon" then
					buildCO2(effect, attachment, scale)
				elseif machineId == "Flamethrower" then
					buildFlames(effect, attachment, scale, lod == "Full")
				elseif machineId == "Lasers" and lod ~= "Minimal" then
					buildLasers(effect, effectTrove, attachment, if lod == "Full" then 2 else 1)
				end
			end

			-- Rajada inicial no instante do drop
			for _, emitter in effect.BurstEmitters do
				emitter:Emit(effect.BurstCount)
			end
			table.insert(effects, effect)
		end
	end
end

-- Atualização por frame ------------------------------------------------------------

local function finishEffect(effect: ActiveEffect)
	for _, emitter in effect.Emitters do
		emitter.Enabled = false
	end
	for _, light in effect.Lights do
		light.Brightness = 0
	end
	-- Deixa as partículas já emitidas terminarem antes de limpar
	task.delay(1.5, function()
		trove:Remove(effect.Trove)
	end)
end

local function update()
	if #effects == 0 then
		return
	end
	local now = os.clock()
	local intensity = AudioController.GetIntensity()
	local beat = AudioController.GetBeatIndex()
	local newBeat = beat ~= lastBeat
	lastBeat = beat

	for index = #effects, 1, -1 do
		local effect = effects[index]
		if now >= effect.EndsAt then
			table.remove(effects, index)
			finishEffect(effect)
		else
			for emitterIndex, emitter in effect.Emitters do
				emitter.Rate = effect.BaseRates[emitterIndex] * (0.35 + 0.65 * intensity)
			end
			if newBeat then
				for _, emitter in effect.BurstEmitters do
					emitter:Emit(effect.BurstCount)
				end
			end
			for _, light in effect.Lights do
				light.Brightness = 1 + 4 * intensity
			end
			for _, beam in effect.Beams do
				local angle = now * 1.6 + beam.Phase
				beam.Target.WorldPosition = beam.Origin + Vector3.new(math.sin(angle) * 30, 60, math.cos(angle * 0.7) * 20)
			end
		end
	end
end

-- Ciclo de vida --------------------------------------------------------------

function PyroVfxController.Init()
	trove:Add(BassDropController.Resolved:Connect(function(result: DropResolved)
		if not result.Success then
			return
		end
		local player = Players:GetPlayerByUserId(result.UserId)
		if player then
			spawnShow(player, result.Mask)
		end
	end))
end

function PyroVfxController.Start()
	trove:Connect(RunService.RenderStepped, update)
end

return PyroVfxController
