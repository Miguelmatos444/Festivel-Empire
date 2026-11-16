--!strict
--[[
	PyroService
	Posse das máquinas de pirotecnia (persistida em ProfileData.Pyro),
	compra com Hype e cooldowns por sessão (os.clock()).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local PyroConfig = require(ReplicatedStorage.Shared.Config.Pyro)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local BigNum = require(ReplicatedStorage.Shared.Util.BigNum)
local NumberFormatter = require(ReplicatedStorage.Shared.Util.NumberFormatter)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local DropCalc = require(ReplicatedStorage.Shared.Calc.DropCalc)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PlayerStateService = require(script.Parent.PlayerStateService)

local PyroService = {}

local changed: Signal.Signal<Player> = Signal.new()

-- Disparado quando a posse ou os cooldowns de um jogador mudam.
PyroService.Changed = changed

local trove = Trove.new()
local cooldowns: { [Player]: { [string]: number } } = {} -- id -> os.clock() em que fica pronta

-- Posse ----------------------------------------------------------------------

function PyroService.Owns(player: Player, id: string): boolean
	local data = DataService.GetProfile(player)
	return data ~= nil and data.Pyro[id] == true
end

function PyroService.GetOwned(player: Player): { [string]: boolean }
	local owned: { [string]: boolean } = {}
	local data = DataService.GetProfile(player)
	if data then
		for _, def in PyroConfig.List do
			if data.Pyro[def.Id] == true then
				owned[def.Id] = true
			end
		end
	end
	return owned
end

-- Cooldowns ------------------------------------------------------------------

function PyroService.IsReady(player: Player, id: string): boolean
	local playerCooldowns = cooldowns[player]
	local readyAt = if playerCooldowns then playerCooldowns[id] else nil
	return readyAt == nil or os.clock() >= readyAt
end

-- Máquinas da máscara que o jogador possui e que não estão em cooldown
function PyroService.GetUsable(player: Player, mask: number): { string }
	local usable: { string } = {}
	for _, id in DropCalc.MaskToIds(mask) do
		if PyroService.Owns(player, id) and PyroService.IsReady(player, id) then
			table.insert(usable, id)
		end
	end
	return usable
end

-- cooldownCut: redução (0..1) vinda das habilidades dos artistas ("Montagem Rápida")
function PyroService.StartCooldowns(player: Player, ids: { string }, cooldownCut: number?)
	local playerCooldowns = cooldowns[player]
	if not playerCooldowns then
		playerCooldowns = {}
		cooldowns[player] = playerCooldowns
	end
	local now = os.clock()
	local factor = 1 - math.clamp(cooldownCut or 0, 0, 1)
	for _, id in ids do
		local def = PyroConfig.ById[id]
		if def and def.Cooldown > 0 then
			playerCooldowns[id] = now + def.Cooldown * factor
		end
	end
	changed:Fire(player)
end

-- Cooldowns ativos convertidos para hora do servidor (para o cliente)
function PyroService.GetCooldownsServerTime(player: Player): { [string]: number }
	local result: { [string]: number } = {}
	local playerCooldowns = cooldowns[player]
	if not playerCooldowns then
		return result
	end
	local now = os.clock()
	local serverNow = Workspace:GetServerTimeNow()
	for id, readyAt in playerCooldowns do
		if readyAt > now then
			result[id] = serverNow + (readyAt - now)
		end
	end
	return result
end

function PyroService.ResetCooldowns(player: Player)
	cooldowns[player] = nil
	changed:Fire(player)
end

-- Compra ---------------------------------------------------------------------

function PyroService.Purchase(player: Player, id: string): (boolean, string)
	local data = DataService.GetProfile(player)
	local def = PyroConfig.ById[id]
	if not data or not def then
		return false, "Compra indisponível."
	end
	if data.Pyro[id] == true then
		return false, def.Name .. " já está desbloqueado."
	end
	if data.StageTier < def.RequiredTier then
		return false, string.format("%s requer palco tier %d.", def.Name, def.RequiredTier)
	end
	local cost = BigNum.fromNumber(def.UnlockCost)
	if not EconomyService.TrySpendHype(player, cost) then
		return false, "Hype insuficiente para " .. def.Name .. " (" .. NumberFormatter.format(cost) .. ")."
	end
	data.Pyro[id] = true
	changed:Fire(player)
	return true, def.Name .. " desbloqueado! Arma-o na barra de drop."
end

-- Debug: desbloqueia todas as máquinas sem custo
function PyroService.UnlockAll(player: Player): boolean
	local data = DataService.GetProfile(player)
	if not data then
		return false
	end
	for _, def in PyroConfig.List do
		data.Pyro[def.Id] = true
	end
	changed:Fire(player)
	return true
end

-- Ciclo de vida --------------------------------------------------------------

function PyroService.Init()
	ServerNet.Connect(RemoteDefs.Defs.BuyPyro, function(player: Player, idArg: unknown)
		local _, message = PyroService.Purchase(player, idArg :: string)
		local notice: Types.Notice = { Kind = "Info", Text = message }
		PlayerStateService.Notify(player, notice)
	end)

	trove:Add(DataService.ProfileLoaded:Connect(function(player: Player)
		cooldowns[player] = nil -- perfil novo ou reiniciado
		changed:Fire(player)
	end))

	trove:Connect(Players.PlayerRemoving, function(player: Player)
		cooldowns[player] = nil
	end)
end

function PyroService.Start() end

return PyroService
