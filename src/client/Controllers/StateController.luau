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
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
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
	Diag.LogSampled("State", "apply", string.format("estado aplicado ao HUD: Hype %.3fe%d", snapshot.Hype.m, snapshot.Hype.e))
	changed:Fire(snapshot)
end

local function applyDelta(delta: StateDelta)
	local current = state
	if not current then
		Diag.Log("State", "delta recebido antes do snapshot — ignorado (o snapshot traz o estado completo)")
		return
	end
	local nextState = table.clone(current)
	if delta.Hype then
		nextState.Hype = delta.Hype
	end
	if delta.TotalHypeEarned then
		nextState.TotalHypeEarned = delta.TotalHypeEarned
	end
	if delta.RunHypeEarned then
		nextState.RunHypeEarned = delta.RunHypeEarned
	end
	if delta.SkillTree then
		nextState.SkillTree = delta.SkillTree
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
local CLIENT_READY_RETRY_INTERVAL = 5
local CLIENT_READY_MAX_ATTEMPTS = 6

function StateController.Start()
	-- Envia ClientReady e repete até chegar o primeiro snapshot (o servidor reenvia o estado)
	trove:Add(task.spawn(function()
		for attempt = 1, CLIENT_READY_MAX_ATTEMPTS do
			NetController.Fire(RemoteDefs.Defs.ClientReady)
			Diag.Log("State", string.format("ClientReady enviado (tentativa %d) — à espera do snapshot", attempt))
			task.wait(CLIENT_READY_RETRY_INTERVAL)
			if state ~= nil then
				return
			end
		end
		warn(
			string.format(
				"[StateController] Nenhum snapshot recebido após %d tentativas de ClientReady. Ver no Output do servidor as linhas [Diag:S][Data]/[State].",
				CLIENT_READY_MAX_ATTEMPTS
			)
		)
	end))
end

return StateController
