--!strict
--[[
	VariantVisuals
	Visual das Variantes Brilhantes (Fase 13A), sempre no cliente:
	  Dourado     metal dourado com reflexos e brilhos
	  Neon        contorno neon a pulsar com a música (AudioController.GetIntensity)
	  Holográfico arco-íris a mudar de cor, material de campo de forças
	  Glitch      cores a "falhar" (ciano/magenta) e contorno a piscar
	  Galáctico   corpo escuro-roxo brilhante com estrelas e aura
	  Infernal    corpo em brasa, fogo, fumo e contorno vermelho

	Apply(model, variantId) aplica o visual a um modelo (palco, vitrine, retratos 3D).
	O controlador procura sozinho os artistas do palco e das vitrines (atributo "Variant"
	gravado pelo servidor) a 2 Hz, e anima os que estão perto da câmara a ~20 Hz
	(LOD: Config/Lod.Vfx.LightDistance). Os modelos são recriados pelo servidor, por isso
	não é preciso repor o aspeto original.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LodConfig = require(ReplicatedStorage.Shared.Config.Lod)
local VariantCalc = require(ReplicatedStorage.Shared.Calc.VariantCalc)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local AudioController = require(script.Parent.AudioController)

type Animated = {
	Model: Model,
	Variant: string,
	Parts: { BasePart },
	Highlight: Highlight?,
	Offset: number,
	NextGlitch: number,
}

local VariantVisuals = {}

local SCAN_INTERVAL = 0.5
local ANIMATE_INTERVAL = 0.05
local CYAN = Color3.fromRGB(40, 240, 255)
local MAGENTA = Color3.fromRGB(255, 40, 200)

local trove = Trove.new()
local animated: { Animated } = {}
local rng = Random.new()
local lastScan = -math.huge
local lastAnimate = -math.huge

local function visibleParts(model: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= model.PrimaryPart and descendant.Name ~= "HumanoidRootPart" and descendant.Transparency < 1 then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function addHighlight(model: Model, color: Color3, fill: number): Highlight
	local highlight = Instance.new("Highlight")
	highlight.Name = "VariantHighlight"
	highlight.OutlineColor = color
	highlight.FillColor = color
	highlight.FillTransparency = fill
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	return highlight
end

local function addEmitter(parent: Instance, color: Color3, rate: number, size: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "VariantParticles"
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Speed = NumberRange.new(0.5, 2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, size), NumberSequenceKeypoint.new(1, 0) })
	emitter.Parent = parent
	return emitter
end

local function addLight(parent: Instance, color: Color3, brightness: number)
	local light = Instance.new("PointLight")
	light.Name = "VariantLight"
	light.Color = color
	light.Range = 14
	light.Brightness = brightness
	light.Parent = parent
end

local function makeEntry(model: Model, variant: string, parts: { BasePart }, highlight: Highlight?, offset: number): Animated
	return { Model = model, Variant = variant, Parts = parts, Highlight = highlight, Offset = offset, NextGlitch = 0 }
end

-- Aplica o visual da variante ao modelo (idempotente por variante)
function VariantVisuals.Apply(model: Model, variantId: string?)
	local def = VariantCalc.Get(variantId)
	if not def or model:GetAttribute("VariantApplied") == def.Id then
		return
	end
	model:SetAttribute("VariantApplied", def.Id)
	local parts = visibleParts(model)
	local root = model.PrimaryPart or parts[1]
	local entry: Animated? = nil

	if def.Id == "Golden" then
		for _, part in parts do
			part.Color = def.Color
			part.Material = Enum.Material.Foil
			part.Reflectance = 0.25
		end
		if root then
			addEmitter(root, Color3.fromRGB(255, 240, 170), 6, 0.35)
			addLight(root, def.Color, 1.5)
		end
	elseif def.Id == "Neon" then
		for _, part in parts do
			part.Material = Enum.Material.SmoothPlastic
			part.Color = part.Color:Lerp(Color3.fromRGB(20, 20, 30), 0.6)
		end
		entry = makeEntry(model, def.Id, parts, addHighlight(model, def.Color, 0.9), 0)
	elseif def.Id == "Holographic" then
		for _, part in parts do
			part.Material = Enum.Material.ForceField
		end
		if root then
			addEmitter(root, Color3.fromRGB(255, 255, 255), 8, 0.4)
		end
		entry = makeEntry(model, def.Id, parts, nil, rng:NextNumber())
	elseif def.Id == "Glitch" then
		for _, part in parts do
			part.Material = Enum.Material.Neon
			part.Color = Color3.fromRGB(30, 30, 40)
		end
		entry = makeEntry(model, def.Id, parts, addHighlight(model, MAGENTA, 0.8), 0)
	elseif def.Id == "Galactic" then
		for _, part in parts do
			part.Material = Enum.Material.Neon
			part.Color = Color3.fromRGB(45, 20, 100)
		end
		if root then
			addEmitter(root, Color3.fromRGB(230, 220, 255), 14, 0.3)
			addEmitter(root, def.Color, 4, 1.2)
			addLight(root, def.Color, 2.5)
		end
		addHighlight(model, def.Color, 1)
	elseif def.Id == "Infernal" then
		for _, part in parts do
			part.Material = Enum.Material.Basalt
			part.Color = Color3.fromRGB(70, 14, 6)
		end
		if root then
			local fire = Instance.new("Fire")
			fire.Name = "VariantFire"
			fire.Color = Color3.fromRGB(255, 120, 20)
			fire.SecondaryColor = Color3.fromRGB(255, 40, 0)
			fire.Heat = 6
			fire.Size = 4
			fire.Parent = root
			local smoke = Instance.new("Smoke")
			smoke.Name = "VariantSmoke"
			smoke.Color = Color3.fromRGB(40, 30, 30)
			smoke.Opacity = 0.15
			smoke.RiseVelocity = 2
			smoke.Parent = root
			addLight(root, def.Color, 3)
		end
		local head = model:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			addLight(head, Color3.fromRGB(255, 30, 0), 4) -- olhos a brilhar
		end
		addHighlight(model, def.Color, 1)
	end

	if entry then
		table.insert(animated, entry)
	end
end

-- Procura os artistas do palco e das vitrines com variante (atributo do servidor)
local function scan()
	local map = Workspace:FindFirstChild("Map")
	local plots = if map then map:FindFirstChild("Plots") else nil
	if not plots then
		return
	end
	for _, plot in plots:GetChildren() do
		for _, folderName in { "Artists", "Showcase" } do
			local folder = plot:FindFirstChild(folderName)
			if folder then
				for _, child in folder:GetChildren() do
					if child:IsA("Model") then
						local variant = child:GetAttribute("Variant")
						if type(variant) == "string" and variant ~= "" and child:GetAttribute("VariantApplied") ~= variant then
							VariantVisuals.Apply(child, variant)
						end
					end
				end
			end
		end
	end
	-- Esquece os modelos que já não existem
	for index = #animated, 1, -1 do
		if not animated[index].Model.Parent then
			table.remove(animated, index)
		end
	end
end

local function animate(now: number)
	local camera = Workspace.CurrentCamera
	local cameraPos = if camera then camera.CFrame.Position else Vector3.zero
	local intensity = AudioController.GetIntensity()
	for _, entry in animated do
		local model = entry.Model
		local pivot = if model.Parent and model.PrimaryPart then model.PrimaryPart.Position else nil
		-- Retratos 3D (ViewportFrame) animam sempre; no mundo só perto da câmara
		local inViewport = model:FindFirstAncestorOfClass("ViewportFrame") ~= nil
		if model.Parent and (inViewport or (pivot and (pivot - cameraPos).Magnitude <= LodConfig.Vfx.LightDistance)) then
			if entry.Variant == "Neon" then
				local highlight = entry.Highlight
				if highlight then
					highlight.OutlineTransparency = 0.6 - 0.6 * intensity
					highlight.FillTransparency = 0.95 - 0.25 * intensity
				end
			elseif entry.Variant == "Holographic" then
				local hue = (now * 0.25 + entry.Offset) % 1
				local color = Color3.fromHSV(hue, 0.55, 1)
				for _, part in entry.Parts do
					part.Color = color
				end
			elseif entry.Variant == "Glitch" and now >= entry.NextGlitch then
				entry.NextGlitch = now + rng:NextNumber(0.08, 0.5)
				local flash = rng:NextNumber() < 0.5
				local color = if flash then (if rng:NextNumber() < 0.5 then CYAN else MAGENTA) else Color3.fromRGB(30, 30, 40)
				for _, part in entry.Parts do
					part.Color = color
				end
				local highlight = entry.Highlight
				if highlight then
					highlight.Enabled = rng:NextNumber() < 0.8
					highlight.OutlineColor = if rng:NextNumber() < 0.5 then CYAN else MAGENTA
				end
			end
		end
	end
end

function VariantVisuals.Init()
	trove:Connect(RunService.Heartbeat, function()
		local now = os.clock()
		if now - lastScan >= SCAN_INTERVAL then
			lastScan = now
			scan()
		end
		if now - lastAnimate >= ANIMATE_INTERVAL then
			lastAnimate = now
			animate(now)
		end
	end)
end

return VariantVisuals
