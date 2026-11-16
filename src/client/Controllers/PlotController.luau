--!strict
--[[
	PlotController
	Encontra os terrenos replicados (Workspace/Map/Plots, atributo OwnerUserId),
	pede o teleporte "Voltar ao meu festival" e liga a pirotecnia aos
	Attachments Pyro_<Id>_<n> do palco de cada jogador.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local MapConfig = require(ReplicatedStorage.Shared.Config.Map)
local NetController = require(script.Parent.NetController)
local PyroVfxController = require(script.Parent.PyroVfxController)
local AudioController = require(script.Parent.AudioController)

local MAX_EMITTERS_PER_MACHINE = 8

local PlotController = {}

local lastReturnRequest = -math.huge

function PlotController.GetPlotModel(userId: number): Model?
	local map = Workspace:FindFirstChild("Map")
	local plots = if map then map:FindFirstChild("Plots") else nil
	if not plots then
		return nil
	end
	for _, child in plots:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("OwnerUserId") == userId then
			return child
		end
	end
	return nil
end

function PlotController.GetMyPlot(): Model?
	return PlotController.GetPlotModel(Players.LocalPlayer.UserId)
end

-- Distância horizontal da personagem ao centro do próprio terreno (nil se indisponível)
function PlotController.GetDistanceFromMyPlot(): number?
	local plot = PlotController.GetMyPlot()
	local base = if plot then plot.PrimaryPart else nil
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not base or not root or not root:IsA("BasePart") then
		return nil
	end
	local offset = root.Position - base.Position
	return Vector3.new(offset.X, 0, offset.Z).Magnitude
end

function PlotController.CanReturn(): boolean
	return os.clock() - lastReturnRequest >= MapConfig.ReturnCooldown
end

-- Devolve true se o pedido foi enviado (o servidor valida e teleporta)
function PlotController.RequestReturn(): boolean
	if not PlotController.CanReturn() then
		return false
	end
	lastReturnRequest = os.clock()
	NetController.Fire(RemoteDefs.Defs.ReturnToPlot)
	return true
end

-- Pirotecnia a partir dos Attachments do palco; sem palco, usa o resolver por defeito
local function stageResolver(player: Player, machineId: string): { CFrame }
	local plot = PlotController.GetPlotModel(player.UserId)
	local stage = if plot then plot:FindFirstChild("Stage") else nil
	local root = if stage then stage:FindFirstChild("Root") else nil
	local result: { CFrame } = {}
	if root then
		for index = 1, MAX_EMITTERS_PER_MACHINE do
			local attachment = root:FindFirstChild("Pyro_" .. machineId .. "_" .. index)
			if not attachment or not attachment:IsA("Attachment") then
				break
			end
			table.insert(result, attachment.WorldCFrame)
		end
	end
	if #result == 0 then
		return PyroVfxController.DefaultResolver(player, machineId)
	end
	return result
end

-- Ponto de onde soam os sons de um jogador: o foco da câmara do palco, ou o centro do terreno
function PlotController.GetSoundPosition(player: Player): Vector3?
	local plot = PlotController.GetPlotModel(player.UserId)
	if not plot then
		return nil
	end
	local stage = plot:FindFirstChild("Stage")
	local root = if stage then stage:FindFirstChild("Root") else nil
	local focus = if root then root:FindFirstChild("CameraFocus") else nil
	if focus and focus:IsA("Attachment") then
		return focus.WorldPosition
	end
	local base = plot.PrimaryPart
	return if base then base.Position else nil
end

function PlotController.Init()
	PyroVfxController.SetEmitterResolver(stageResolver)
	AudioController.SetPositionResolver(PlotController.GetSoundPosition)
end

return PlotController
