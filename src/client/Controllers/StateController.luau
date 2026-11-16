--!strict
--[[
	StateController
	Guarda a cópia local (só de leitura) do estado replicado pelo servidor.
	Aplica snapshots e deltas e notifica a UI via sinais.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local NetController = require(script.Parent.NetController)

type Snapshot = Types.PlayerStateSnapshot
type StateDelta = Types.StateDelta
type Notice = Types.Notice

local StateController = {}

local changed: Signal.Signal<Snapshot> = Signal.new()
local noticeReceived: Signal.Signal<Notice> = Signal.new()

StateController.Changed = changed
StateController.NoticeReceived = noticeReceived

local trove = Trove.new()
local state: Snapshot? = nil

function StateController.Get(): Snapshot?
	return state
end

local function applySnapshot(snapshot: Snapshot)
	state = snapshot
	changed:Fire(snapshot)
end

local function applyDelta(delta: StateDelta)
	local current = state
	if not current then
		return -- ainda sem snapshot; o snapshot trará o estado completo
	end
	local nextState = table.clone(current)
	if delta.Hype then
		nextState.Hype = delta.Hype
	end
	if delta.TotalHypeEarned then
		nextState.TotalHypeEarned = delta.TotalHypeEarned
	end
	if delta.HypePerClick then
		nextState.HypePerClick = delta.HypePerClick
	end
	if delta.HypePerSecond then
		nextState.HypePerSecond = delta.HypePerSecond
	end
	if delta.PlatinumDiscs then
		nextState.PlatinumDiscs = delta.PlatinumDiscs
	end
	if delta.WorldTours then
		nextState.WorldTours = delta.WorldTours
	end
	if delta.StageTier then
		nextState.StageTier = delta.StageTier
	end
	if delta.Clicks then
		nextState.Clicks = delta.Clicks
	end
	local equipmentDelta = delta.Equipment
	if equipmentDelta then
		local merged = table.clone(current.Equipment)
		for id, level in equipmentDelta do
			merged[id] = level
		end
		nextState.Equipment = merged
	end
	applySnapshot(nextState)
end

function StateController.Init()
	trove:Add(NetController.On(RemoteDefs.Defs.StateSnapshot, function(payload: unknown)
		applySnapshot(payload :: Snapshot)
	end))
	trove:Add(NetController.On(RemoteDefs.Defs.StateDelta, function(payload: unknown)
		applyDelta(payload :: StateDelta)
	end))
	trove:Add(NetController.On(RemoteDefs.Defs.Notify, function(payload: unknown)
		noticeReceived:Fire(payload :: Notice)
	end))
end

-- Avisa o servidor de que o cliente está pronto a receber estado
function StateController.Start()
	NetController.Fire(RemoteDefs.Defs.ClientReady)
end

return StateController
