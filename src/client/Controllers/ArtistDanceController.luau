--!strict
--[[
	ArtistDanceController
	Faz os artistas de TODOS os palcos dançar ao ritmo do relógio partilhado (BPM):
	pequeno salto + balanço em cada batida, mais forte com a intensidade da música.
	Só mexe em CFrames locais (nada replica). LOD: artistas a mais de
	LodConfig.StageAnimation.MaxDistance ficam parados.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LodConfig = require(ReplicatedStorage.Shared.Config.Lod)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local AudioController = require(script.Parent.AudioController)

type Dancer = {
	Model: Model,
	Base: CFrame, -- pivot colocado pelo servidor
	Phase: number, -- desfasamento entre artistas
	Near: boolean,
}

local BOUNCE_HEIGHT = 0.6
local SWAY_DEGREES = 6
local LOD_CHECK_INTERVAL = 1

local ArtistDanceController = {}

local trove = Trove.new()
local dancers: { [Model]: Dancer } = {}
local lastLodCheck = 0

--[[
	A posição de referência vem do atributo "BaseCFrame" que o servidor grava no rig.
	(Ler o pivot no ChildAdded não é seguro: as peças do modelo podem ainda não ter
	replicado e o pivot viria errado, levando o artista para longe do palco.)
]]
local function addDancer(model: Instance)
	if not model:IsA("Model") or dancers[model] then
		return
	end
	local base = model:GetAttribute("BaseCFrame")
	if typeof(base) ~= "CFrame" then
		local connection: RBXScriptConnection
		connection = model:GetAttributeChangedSignal("BaseCFrame"):Connect(function()
			connection:Disconnect()
			addDancer(model)
		end)
		trove:Add(connection)
		return
	end
	dancers[model] = {
		Model = model,
		Base = base :: CFrame,
		Phase = (tonumber(string.match(model.Name, "%d+")) or 1) * 0.37,
		Near = true,
	}
end

local function watchArtistsFolder(folder: Instance)
	for _, child in folder:GetChildren() do
		addDancer(child)
	end
	trove:Connect(folder.ChildAdded, addDancer)
end

local function watchPlot(plot: Instance)
	local existing = plot:FindFirstChild("Artists")
	if existing then
		watchArtistsFolder(existing)
	end
	trove:Connect(plot.ChildAdded, function(child: Instance)
		if child.Name == "Artists" then
			watchArtistsFolder(child)
		end
	end)
end

local function updateLod()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local origin = camera.CFrame.Position
	for _, dancer in dancers do
		dancer.Near = (dancer.Base.Position - origin).Magnitude <= LodConfig.StageAnimation.MaxDistance
	end
end

local function update()
	local now = os.clock()
	if now - lastLodCheck >= LOD_CHECK_INTERVAL then
		lastLodCheck = now
		updateLod()
	end

	local pulse = AudioController.GetBeatPulse()
	local intensity = AudioController.GetIntensity()
	local beat = AudioController.GetBeatIndex()

	for model, dancer in dancers do
		if model.Parent == nil then
			dancers[model] = nil
		elseif dancer.Near and model.PrimaryPart then
			local side = if (beat + math.floor(dancer.Phase * 10)) % 2 == 0 then 1 else -1
			local lift = BOUNCE_HEIGHT * pulse * (0.6 + 0.4 * intensity)
			local sway = math.rad(SWAY_DEGREES) * side * (0.5 + 0.5 * pulse)
			model:PivotTo(dancer.Base * CFrame.new(0, lift, 0) * CFrame.Angles(0, 0, sway))
		end
	end
end

function ArtistDanceController.Init()
	trove:Connect(RunService.RenderStepped, update)
end

function ArtistDanceController.Start()
	trove:Add(task.spawn(function()
		local map = Workspace:WaitForChild("Map")
		local plots = map:WaitForChild("Plots")
		for _, plot in plots:GetChildren() do
			watchPlot(plot)
		end
		trove:Connect(plots.ChildAdded, watchPlot)
	end))
end

return ArtistDanceController
