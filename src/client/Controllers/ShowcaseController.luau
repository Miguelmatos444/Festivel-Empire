--!strict
--[[
	ShowcaseController
	Anima os artistas das vitrines (Workspace/Map/Plots/<Plot>/Showcase/Artist): rodam
	devagar e flutuam à volta da posição base gravada pelo servidor (atributo BaseCFrame).
	LOD: só anima até Config/Lod.Showcase.AnimateDistance da câmara; além disso fica parado
	na posição base. Máximo 6 vitrines, verificadas a 2 Hz (sem procurar por frame).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ShowcaseConfig = require(ReplicatedStorage.Shared.Config.Showcase)
local LodConfig = require(ReplicatedStorage.Shared.Config.Lod)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)

local RESCAN_INTERVAL = 0.5

local ShowcaseController = {}

local trove = Trove.new()
local rigs: { Model } = {}
local bases: { CFrame } = {}
local animating: { boolean } = {}
local lastScan = -math.huge

local function rescan()
	table.clear(rigs)
	table.clear(bases)
	local map = Workspace:FindFirstChild("Map")
	local plots = if map then map:FindFirstChild("Plots") else nil
	if not plots then
		return
	end
	local camera = Workspace.CurrentCamera
	local cameraPos = if camera then camera.CFrame.Position else Vector3.zero
	for _, plot in plots:GetChildren() do
		local folder = plot:FindFirstChild("Showcase")
		local rig = if folder then folder:FindFirstChild("Artist") else nil
		local base = if rig then rig:GetAttribute("BaseCFrame") else nil
		if rig and rig:IsA("Model") and typeof(base) == "CFrame" then
			local index = #rigs + 1
			rigs[index] = rig
			bases[index] = base
			local near = (base.Position - cameraPos).Magnitude <= LodConfig.Showcase.AnimateDistance
			if not near and animating[index] then
				rig:PivotTo(base) -- longe: volta à posição base e fica parado
			end
			animating[index] = near
		end
	end
end

local function onRender()
	local now = os.clock()
	if now - lastScan >= RESCAN_INTERVAL then
		lastScan = now
		rescan()
	end
	local spin = now * ShowcaseConfig.SpinSpeed
	local bob = math.sin(now * ShowcaseConfig.BobSpeed) * ShowcaseConfig.BobHeight
	for index, rig in rigs do
		if animating[index] and rig.Parent then
			rig:PivotTo(bases[index] * CFrame.new(0, bob + ShowcaseConfig.BobHeight, 0) * CFrame.Angles(0, spin, 0))
		end
	end
end

function ShowcaseController.Init()
	trove:Connect(RunService.RenderStepped, onRender)
end

return ShowcaseController
