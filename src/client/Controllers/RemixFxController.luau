--!strict
--[[
	RemixFxController
	Disco holográfico do Estúdio de Remix (praça):
	  - roda e flutua devagar no cliente (posição base no atributo "BaseCFrame" do servidor)
	  - quando alguém tira um traço Lendário (RemixBurst), explode em luz: clarão, anel a
	    expandir e partículas. Visível a todos, com LOD (Config/Lod.Vfx.HideDistance).
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local CrystalsConfig = require(ReplicatedStorage.Shared.Config.Crystals)
local LodConfig = require(ReplicatedStorage.Shared.Config.Lod)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local NetController = require(script.Parent.NetController)
local CrateSfx = require(script.Parent.CrateSfx)

local GOLD = Color3.fromRGB(255, 200, 60)

local RemixFxController = {}

local trove = Trove.new()
local disc: BasePart? = nil
local discBase: CFrame? = nil
local lastSearch = -math.huge

local function findDisc(): BasePart?
	local map = Workspace:FindFirstChild("Map")
	local plaza = if map then map:FindFirstChild("Plaza") else nil
	local found = if plaza then plaza:FindFirstChild("RemixDisc", true) else nil
	if found and found:IsA("BasePart") then
		local base = found:GetAttribute("BaseCFrame")
		if typeof(base) == "CFrame" then
			discBase = base
			return found
		end
	end
	return nil
end

local function burst()
	local part = disc
	local base = discBase
	local camera = Workspace.CurrentCamera
	if not part or not base or not camera then
		return
	end
	if (camera.CFrame.Position - base.Position).Magnitude > LodConfig.Vfx.HideDistance then
		return
	end
	-- Anel de luz a expandir à volta do disco
	local ring = Instance.new("Part")
	ring.Name = "RemixBurst"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = GOLD
	ring.Size = Vector3.new(0.4, CrystalsConfig.Studio.DiscDiameter, CrystalsConfig.Studio.DiscDiameter)
	ring.CFrame = CFrame.new(base.Position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = Workspace
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 60
	light.Brightness = 14
	light.Parent = ring
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(GOLD, Color3.new(1, 1, 1))
	sparks.LightEmission = 1
	sparks.Speed = NumberRange.new(20, 45)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Lifetime = NumberRange.new(0.8, 1.4)
	sparks.Size = NumberSequence.new(1, 0)
	sparks.Rate = 0
	sparks.Parent = ring
	sparks:Emit(80)
	local size = CrystalsConfig.Studio.DiscDiameter * 4
	TweenService:Create(ring, TweenInfo.new(1.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.new(0.4, size, size), Transparency = 1 }):Play()
	TweenService:Create(light, TweenInfo.new(1.4), { Brightness = 0 }):Play()
	Debris:AddItem(ring, 2)
	CrateSfx.PlayAt("RevealSting", base.Position)
end

function RemixFxController.Init()
	trove:Add(NetController.On(RemoteDefs.Defs.RemixBurst, function(_userId: unknown)
		burst()
	end))
	trove:Connect(RunService.RenderStepped, function()
		local now = os.clock()
		if not disc or not disc.Parent then
			if now - lastSearch < 2 then
				return
			end
			lastSearch = now
			disc = findDisc()
			return
		end
		local base = discBase
		local part = disc
		if part and base then
			part.CFrame = base
				* CFrame.new(0, math.sin(now * 1.2) * 0.6, 0)
				* CFrame.Angles(now * CrystalsConfig.Studio.DiscSpin, 0, 0) -- o disco é um cilindro deitado (eixo X)
		end
	end)
end

return RemixFxController
