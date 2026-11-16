--!strict
--[[
	BassDropService
	Máquina de estados autoritativa do Bass Drop, por jogador:

	  Charging --(energia cheia)--> BuildUp --> Window --(TriggerDrop)--> Boost --> Charging
	                                              \--(janela fecha)--> Charging (energia = MissEnergyReset)

	- Energia: passiva no tick de 1 Hz + EnergyPerClick por batida aceite.
	- Transições agendadas com task.delay e protegidas por token (sem loops por frame).
	- Timing validado com os.clock() na chegada do pedido menos o ping do jogador
	  (limitado a MaxLatencyCompensation).
	- O cliente recebe os tempos em Workspace:GetServerTimeNow() para sincronizar a UI.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local BassDropConfig = require(ReplicatedStorage.Shared.Config.BassDrop)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local DropCalc = require(ReplicatedStorage.Shared.Calc.DropCalc)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local PyroService = require(script.Parent.PyroService)

type DropPhase = Types.DropPhase
type DropState = Types.DropState
type DropResolved = Types.DropResolved

type Session = {
	Phase: DropPhase,
	Energy: number,
	Token: number, -- invalida transições agendadas antigas
	DropClock: number, -- instante do drop em os.clock()
	DropServerTime: number, -- o mesmo instante em hora do servidor
	PhaseStart: number,
	PhaseEnd: number,
	BoostMultiplier: number,
	Triggered: boolean,
	Dirty: boolean,
}

local BassDropService = {}

local trove = Trove.new()
local sessions: { [Player]: Session } = {}

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function newSession(): Session
	return {
		Phase = "Charging",
		Energy = 0,
		Token = 0,
		DropClock = 0,
		DropServerTime = 0,
		PhaseStart = serverNow(),
		PhaseEnd = 0,
		BoostMultiplier = 1,
		Triggered = false,
		Dirty = true,
	}
end

-- Estado / envio ---------------------------------------------------------------

local function buildState(player: Player, session: Session): DropState
	return {
		Phase = session.Phase,
		Energy = session.Energy,
		MaxEnergy = BassDropConfig.MaxEnergy,
		PhaseStart = session.PhaseStart,
		PhaseEnd = session.PhaseEnd,
		DropTime = session.DropServerTime,
		BoostMultiplier = session.BoostMultiplier,
		Owned = PyroService.GetOwned(player),
		Cooldowns = PyroService.GetCooldownsServerTime(player),
	}
end

local function sendState(player: Player, session: Session)
	if not PlayerStateService.IsClientReady(player) then
		session.Dirty = true -- envia quando o cliente estiver pronto
		return
	end
	session.Dirty = false
	ServerNet.FireClient(RemoteDefs.Defs.DropState, player, buildState(player, session))
end

local function isCurrent(player: Player, session: Session, token: number): boolean
	return sessions[player] == session and session.Token == token
end

local function enterPhase(session: Session, phase: DropPhase, phaseEnd: number)
	session.Token += 1
	session.Phase = phase
	session.PhaseStart = serverNow()
	session.PhaseEnd = phaseEnd
end

local function schedule(player: Player, session: Session, delaySeconds: number, callback: () -> ())
	local token = session.Token
	task.delay(math.max(0, delaySeconds), function()
		if isCurrent(player, session, token) then
			callback()
		end
	end)
end

-- Transições -----------------------------------------------------------------

local startBuildUp: (player: Player, session: Session) -> ()

local function startCharging(player: Player, session: Session, energy: number)
	enterPhase(session, "Charging", 0)
	session.Energy = math.clamp(energy, 0, BassDropConfig.MaxEnergy)
	session.BoostMultiplier = 1
	session.Triggered = false
	EconomyService.SetBoost(player, 1, 0)
	sendState(player, session)
end

local function onWindowClosed(player: Player, session: Session)
	if session.Triggered then
		return
	end
	startCharging(player, session, BassDropConfig.MissEnergyReset)
	local result: DropResolved = {
		UserId = player.UserId,
		Success = false,
		Mask = 0,
		Grade = nil,
		Multiplier = 1,
		Synergies = {},
		ServerTime = serverNow(),
	}
	ServerNet.FireClient(RemoteDefs.Defs.DropResolved, player, result)
end

local function openWindow(player: Player, session: Session)
	enterPhase(session, "Window", session.DropServerTime + BassDropConfig.WindowAfter)
	sendState(player, session)
	schedule(player, session, session.DropClock + BassDropConfig.WindowAfter - os.clock(), function()
		onWindowClosed(player, session)
	end)
end

startBuildUp = function(player: Player, session: Session)
	local duration = DropCalc.GetBuildUpDuration()
	session.DropClock = os.clock() + duration
	session.DropServerTime = serverNow() + duration
	session.Triggered = false
	session.Energy = BassDropConfig.MaxEnergy
	enterPhase(session, "BuildUp", session.DropServerTime - BassDropConfig.WindowBefore)
	sendState(player, session)
	schedule(player, session, duration - BassDropConfig.WindowBefore, function()
		openWindow(player, session)
	end)
end

local function addEnergy(player: Player, amount: number)
	local session = sessions[player]
	if not session or session.Phase ~= "Charging" or amount <= 0 then
		return
	end
	session.Energy = math.min(BassDropConfig.MaxEnergy, session.Energy + amount)
	session.Dirty = true
	if session.Energy >= BassDropConfig.MaxEnergy then
		startBuildUp(player, session)
	end
end

-- Ativação -------------------------------------------------------------------

local function getLatencyCompensation(player: Player): number
	local ok, ping = pcall(function(): number
		return player:GetNetworkPing()
	end)
	if not ok then
		return 0
	end
	return math.clamp(ping, 0, BassDropConfig.MaxLatencyCompensation)
end

local function onTriggerDrop(player: Player, maskArg: unknown)
	local session = sessions[player]
	if not session or session.Phase ~= "Window" or session.Triggered then
		return -- antes da janela, depois do fecho, ou repetido: ignorado
	end

	-- Momento estimado em que o jogador carregou (chegada - latência), nunca antes da janela
	local pressedAt = os.clock() - getLatencyCompensation(player)
	local offset = math.max(pressedAt - session.DropClock, -BassDropConfig.WindowBefore)
	local grade = DropCalc.GradeOffset(offset)
	if not grade then
		return -- chegou depois da janela; o fecho trata o falhanço
	end

	session.Triggered = true

	local ids = PyroService.GetUsable(player, maskArg :: number)
	local multiplier, synergies = DropCalc.ComputeMultiplier(ids, grade.Factor)
	PyroService.StartCooldowns(player, ids)

	local data = DataService.GetProfile(player)
	if data then
		data.Stats.BassDrops += 1
	end

	local duration = BassDropConfig.BoostDuration
	enterPhase(session, "Boost", serverNow() + duration)
	session.BoostMultiplier = multiplier
	EconomyService.SetBoost(player, multiplier, os.clock() + duration)
	sendState(player, session)
	schedule(player, session, duration, function()
		startCharging(player, session, 0)
	end)

	local synergyIds: { string } = {}
	for _, synergy in synergies do
		table.insert(synergyIds, synergy.Id)
	end
	local result: DropResolved = {
		UserId = player.UserId,
		Success = true,
		Mask = DropCalc.IdsToMask(ids),
		Grade = grade.Grade,
		Multiplier = multiplier,
		Synergies = synergyIds,
		ServerTime = serverNow(),
	}
	ServerNet.FireAllClients(RemoteDefs.Defs.DropResolved, result)
end

-- Loops ----------------------------------------------------------------------

local function energyLoop()
	local last = os.clock()
	while true do
		task.wait(1)
		local now = os.clock()
		local deltaTime = math.min(now - last, 5)
		last = now
		for player in sessions do
			addEnergy(player, BassDropConfig.PassiveEnergyPerSecond * deltaTime)
		end
	end
end

local function syncLoop()
	while true do
		task.wait(BassDropConfig.SyncInterval)
		for player, session in sessions do
			if session.Dirty then
				sendState(player, session)
			end
		end
	end
end

-- API (debug) ----------------------------------------------------------------

function BassDropService.GetPhase(player: Player): DropPhase?
	local session = sessions[player]
	return if session then session.Phase else nil
end

-- Define a energia (só em Charging). Energia cheia inicia o build-up.
function BassDropService.SetEnergy(player: Player, energy: number): boolean
	local session = sessions[player]
	if not session or session.Phase ~= "Charging" then
		return false
	end
	session.Energy = 0
	addEnergy(player, math.clamp(energy, 0, BassDropConfig.MaxEnergy))
	session.Dirty = true
	return true
end

-- Força o build-up imediatamente
function BassDropService.ForceDrop(player: Player): boolean
	return BassDropService.SetEnergy(player, BassDropConfig.MaxEnergy)
end

-- Ciclo de vida --------------------------------------------------------------

function BassDropService.Init()
	ServerNet.Connect(RemoteDefs.Defs.TriggerDrop, onTriggerDrop)

	trove:Add(DataService.ProfileLoaded:Connect(function(player: Player)
		if player.Parent ~= Players then
			return
		end
		sessions[player] = newSession() -- substitui (e invalida) a sessão anterior
		EconomyService.SetBoost(player, 1, 0)
	end))

	trove:Add(EconomyService.Clicked:Connect(function(player: Player)
		addEnergy(player, BassDropConfig.EnergyPerClick)
	end))

	trove:Add(PyroService.Changed:Connect(function(player: Player)
		local session = sessions[player]
		if session then
			session.Dirty = true
		end
	end))

	trove:Add(PlayerStateService.ClientReady:Connect(function(player: Player)
		local session = sessions[player]
		if session then
			sendState(player, session)
		end
	end))

	trove:Connect(Players.PlayerRemoving, function(player: Player)
		sessions[player] = nil
	end)
end

function BassDropService.Start()
	trove:Add(task.spawn(energyLoop))
	trove:Add(task.spawn(syncLoop))
end

return BassDropService
