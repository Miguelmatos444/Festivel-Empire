--!strict
--[[
	AmbienceController
	Ambiente da praça (só no cliente):
	  - Partes com o atributo RhythmLight = true (torres de luz, arcos) mudam de cor a
	    cada batida e pulsam com a intensidade da música.
	  - Durante o evento Headliner: luzes douradas e um feixe de luz sobre o monumento.
	Funciona com os placeholders e com o modelo final da praça (basta o atributo).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AmbienceConfig = require(ReplicatedStorage.Shared.Config.Ambience)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local AudioController = require(script.Parent.AudioController)
local SocialController = require(script.Parent.SocialController)

type Light = {
	Part: BasePart,
	PointLight: PointLight?,
	Offset: number,
}

local HEADLINER_CHECK_INTERVAL = 1
local BEAM_HEIGHT = 220

local AmbienceController = {}

local trove = Trove.new()
local lights: { Light } = {}
local lastBeat = -1
local headlinerActive = false
local lastHeadlinerCheck = -math.huge
local beam: Part? = nil
local monumentPosition: Vector3? = nil

local function addLight(part: Instance)
	if not part:IsA("BasePart") or part:GetAttribute("RhythmLight") ~= true then
		return
	end
	local pointLight = part:FindFirstChildOfClass("PointLight")
	table.insert(lights, {
		Part = part,
		PointLight = pointLight,
		Offset = #lights * 0.17,
	})
end

local function setBeamVisible(visible: boolean)
	local current = beam
	if visible and not current then
		local position = monumentPosition
		if not position then
			return
		end
		local part = Instance.new("Part")
		part.Name = "HeadlinerBeam"
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(BEAM_HEIGHT, 10, 10)
		part.CFrame = CFrame.new(position + Vector3.new(0, BEAM_HEIGHT / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		part.Color = AmbienceConfig.PlazaLights.BeamColor
		part.Material = Enum.Material.Neon
		part.Transparency = 0.55
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = Workspace
		beam = part
		trove:Add(part)
	elseif not visible and current then
		beam = nil
		current:Destroy()
	end
end

local function update()
	local now = os.clock()
	if now - lastHeadlinerCheck >= HEADLINER_CHECK_INTERVAL then
		lastHeadlinerCheck = now
		local active = SocialController.GetHeadliner().Active
		if active ~= headlinerActive then
			headlinerActive = active
			lastBeat = -1 -- força a recoloração
			setBeamVisible(active)
		end
	end

	local pulse = AudioController.GetBeatPulse()
	local intensity = AudioController.GetIntensity()
	local beatIndex = AudioController.GetBeatIndex()
	local config = AmbienceConfig.PlazaLights

	if beatIndex ~= lastBeat then
		lastBeat = beatIndex
		for _, light in lights do
			local color = if headlinerActive
				then config.HeadlinerColor
				else Color3.fromHSV((beatIndex * config.HueStepPerBeat + light.Offset) % 1, config.Saturation, 1)
			light.Part.Color = color
			local pointLight = light.PointLight
			if pointLight then
				pointLight.Color = color
			end
		end
	end

	local brightness = 1 + 2.5 * pulse * (0.4 + 0.6 * intensity)
	for _, light in lights do
		local pointLight = light.PointLight
		if pointLight then
			pointLight.Brightness = brightness
		end
	end

	local currentBeam = beam
	if currentBeam then
		currentBeam.Transparency = 0.75 - 0.35 * pulse
	end
end

local function watchPlaza(plaza: Instance)
	for _, descendant in plaza:GetDescendants() do
		addLight(descendant)
	end
	trove:Connect(plaza.DescendantAdded, addLight)
	local root = plaza:FindFirstChild("Root")
	local monument = if root then root:FindFirstChild("Monument") else nil
	if monument and monument:IsA("Attachment") then
		monumentPosition = monument.WorldPosition
	else
		monumentPosition = Vector3.new(0, 3, 0)
	end
end

function AmbienceController.Init()
	trove:Connect(RunService.Heartbeat, update)
end

function AmbienceController.Start()
	trove:Add(task.spawn(function()
		local map = Workspace:WaitForChild("Map")
		watchPlaza(map:WaitForChild("Plaza"))
	end))
end

return AmbienceController
