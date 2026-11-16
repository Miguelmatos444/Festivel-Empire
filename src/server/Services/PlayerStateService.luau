--!strict
--[[
	PlayerStateService
	Replica o estado económico de cada jogador para o seu cliente:
	  - snapshot completo quando o cliente está pronto e o perfil carregado
	  - deltas (só campos alterados) a cada ReplicationInterval para jogadores "sujos"
	  - notificações (offline, info) com fila até o cliente estar pronto
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.Economy)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local BigNum = require(ReplicatedStorage.Shared.Util.BigNum)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

type BigNum = BigNum.BigNum
type Snapshot = Types.PlayerStateSnapshot
type StateDelta = Types.StateDelta
type Notice = Types.Notice
type ProfileData = Types.ProfileData

type ClientState = {
	Ready: boolean,
	Dirty: boolean,
	LastSent: Snapshot?,
	Pending: { Notice },
}

local MAX_PENDING_NOTICES = 10

local PlayerStateService = {}

local clientReady: Signal.Signal<Player> = Signal.new()

-- Disparado uma vez por sessão, quando o cliente envia ClientReady.
PlayerStateService.ClientReady = clientReady

local trove = Trove.new()
local clients: { [Player]: ClientState } = {}

local function getClient(player: Player): ClientState
	local client = clients[player]
	if not client then
		client = { Ready = false, Dirty = false, LastSent = nil, Pending = {} }
		clients[player] = client
	end
	return client
end

local function buildSnapshot(player: Player, data: ProfileData): Snapshot
	return {
		Hype = BigNum.serialize(data.Hype),
		TotalHypeEarned = BigNum.serialize(data.TotalHypeEarned),
		HypePerClick = BigNum.serialize(EconomyService.GetHypePerClick(player)),
		HypePerSecond = BigNum.serialize(EconomyService.GetHypePerSecond(player)),
		PlatinumDiscs = data.PlatinumDiscs,
		WorldTours = data.WorldTours,
		StageTier = data.StageTier,
		Clicks = data.Stats.Clicks,
		Equipment = table.clone(data.Equipment),
	}
end

local function buildDelta(previous: Snapshot, current: Snapshot): (StateDelta, boolean)
	local delta: StateDelta = {}
	local changed = false

	if not BigNum.eq(previous.Hype, current.Hype) then
		delta.Hype = current.Hype
		changed = true
	end
	if not BigNum.eq(previous.TotalHypeEarned, current.TotalHypeEarned) then
		delta.TotalHypeEarned = current.TotalHypeEarned
		changed = true
	end
	if not BigNum.eq(previous.HypePerClick, current.HypePerClick) then
		delta.HypePerClick = current.HypePerClick
		changed = true
	end
	if not BigNum.eq(previous.HypePerSecond, current.HypePerSecond) then
		delta.HypePerSecond = current.HypePerSecond
		changed = true
	end
	if previous.PlatinumDiscs ~= current.PlatinumDiscs then
		delta.PlatinumDiscs = current.PlatinumDiscs
		changed = true
	end
	if previous.WorldTours ~= current.WorldTours then
		delta.WorldTours = current.WorldTours
		changed = true
	end
	if previous.StageTier ~= current.StageTier then
		delta.StageTier = current.StageTier
		changed = true
	end
	if previous.Clicks ~= current.Clicks then
		delta.Clicks = current.Clicks
		changed = true
	end

	local equipmentChanges: { [string]: number } = {}
	local equipmentChanged = false
	for id, level in current.Equipment do
		if previous.Equipment[id] ~= level then
			equipmentChanges[id] = level
			equipmentChanged = true
		end
	end
	if equipmentChanged then
		delta.Equipment = equipmentChanges
		changed = true
	end

	return delta, changed
end

local function flushNotices(player: Player, client: ClientState)
	for _, notice in client.Pending do
		ServerNet.FireClient(RemoteDefs.Defs.Notify, player, notice)
	end
	table.clear(client.Pending)
end

local function flush()
	for player, client in clients do
		if client.Dirty and client.Ready then
			local data = DataService.GetProfile(player)
			local previous = client.LastSent
			if data and previous then
				client.Dirty = false
				local current = buildSnapshot(player, data)
				local delta, changed = buildDelta(previous, current)
				if changed then
					client.LastSent = current
					ServerNet.FireClient(RemoteDefs.Defs.StateDelta, player, delta)
				end
			end
		end
	end
end

local function flushLoop()
	while true do
		task.wait(EconomyConfig.ReplicationInterval)
		flush()
	end
end

-- API pública ----------------------------------------------------------------

function PlayerStateService.SendSnapshot(player: Player)
	local client = clients[player]
	local data = DataService.GetProfile(player)
	if not client or not client.Ready or not data then
		return
	end
	local snapshot = buildSnapshot(player, data)
	client.LastSent = snapshot
	client.Dirty = false
	ServerNet.FireClient(RemoteDefs.Defs.StateSnapshot, player, snapshot)
	flushNotices(player, client)
end

function PlayerStateService.IsClientReady(player: Player): boolean
	local client = clients[player]
	return client ~= nil and client.Ready
end

function PlayerStateService.MarkDirty(player: Player)
	local client = clients[player]
	if client then
		client.Dirty = true
	end
end

function PlayerStateService.Notify(player: Player, notice: Notice)
	if player.Parent ~= Players then
		return
	end
	local client = getClient(player)
	if client.Ready and client.LastSent then
		ServerNet.FireClient(RemoteDefs.Defs.Notify, player, notice)
	elseif #client.Pending < MAX_PENDING_NOTICES then
		table.insert(client.Pending, notice)
	end
end

-- Ciclo de vida --------------------------------------------------------------

function PlayerStateService.Init()
	ServerNet.Connect(RemoteDefs.Defs.ClientReady, function(player: Player)
		local client = getClient(player)
		if client.Ready then
			return
		end
		client.Ready = true
		PlayerStateService.SendSnapshot(player)
		clientReady:Fire(player)
	end)

	trove:Add(DataService.ProfileLoaded:Connect(function(player: Player, _data: ProfileData)
		if player.Parent ~= Players then
			return
		end
		getClient(player)
		PlayerStateService.SendSnapshot(player)
	end))

	trove:Add(EconomyService.HypeChanged:Connect(PlayerStateService.MarkDirty))

	trove:Add(EconomyService.OfflineEarned:Connect(function(player: Player, amount: BigNum, seconds: number)
		local notice: Notice = {
			Kind = "OfflineEarnings",
			Amount = BigNum.serialize(amount),
			Seconds = seconds,
		}
		PlayerStateService.Notify(player, notice)
	end))

	trove:Connect(Players.PlayerRemoving, function(player: Player)
		clients[player] = nil
	end)
end

function PlayerStateService.Start()
	trove:Add(task.spawn(flushLoop))
end

return PlayerStateService
