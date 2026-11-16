--!strict
--[[
	StageDressingService
	Mantém os adereços do Blender no palco de cada jogador (World/Dressing):
	colunas de som da era, mesa de DJ e as máquinas de pirotecnia já desbloqueadas.
	Refaz quando o palco é colocado/trocado e quando muda o conjunto de máquinas
	(o PyroService.Changed também dispara com cooldowns — só refaz se as máquinas mudarem).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PyroConfig = require(ReplicatedStorage.Shared.Config.Pyro)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local Dressing = require(script.Parent.Parent.World.Dressing)
local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)
local PlotService = require(script.Parent.PlotService)
local StageService = require(script.Parent.StageService)
local PyroService = require(script.Parent.PyroService)

local StageDressingService = {}

local trove = Trove.new()
local ownedKeys: { [Player]: string } = {}

local function getOwnedKey(owned: { [string]: boolean }): string
	local parts: { string } = {}
	for _, def in PyroConfig.List do
		if owned[def.Id] then
			table.insert(parts, def.Id)
		end
	end
	return table.concat(parts, ",")
end

function StageDressingService.Refresh(player: Player)
	local index = PlotService.GetPlotId(player)
	local data = DataService.GetProfile(player)
	local plot = if index then MapService.GetPlotModel(index) else nil
	local stage = if plot then plot:FindFirstChild("Stage") else nil
	if not data or not stage or not stage:IsA("Model") then
		return
	end
	local owned = PyroService.GetOwned(player)
	ownedKeys[player] = getOwnedKey(owned)
	local ok, err = pcall(Dressing.DressStage, stage, data.StageTier, owned)
	if not ok then
		warn("[StageDressing] Falha a decorar o palco de " .. player.Name .. ": " .. tostring(err))
	end
end

function StageDressingService.Init()
	trove:Add(StageService.StagePlaced:Connect(function(player: Player)
		StageDressingService.Refresh(player)
	end))
	trove:Add(PyroService.Changed:Connect(function(player: Player)
		if ownedKeys[player] ~= getOwnedKey(PyroService.GetOwned(player)) then
			StageDressingService.Refresh(player)
		end
	end))
	trove:Connect(Players.PlayerRemoving, function(player: Player)
		ownedKeys[player] = nil
	end)
end

function StageDressingService.Start() end

return StageDressingService
