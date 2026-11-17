--!strict
--[[
	BassDropService
	Máquina de estados autoritativa do Bass Drop, por jogador:

	  Charging --(energia cheia)--> BuildUp --> Window --(TriggerDrop)--> Boost --> Charging
	                                              \--(janela fecha)--> Salva-Drop? -> Boost
	                                                                  \-> Charging (energia = MissEnergyReset)

	- Energia: passiva no tick de 1 Hz + EnergyPerClick por batida aceite (+ bónus "Carga").
	- Transições agendadas com task.delay e protegidas por token (sem loops por frame).
	- Timing validado com os.clock() na chegada do pedido menos o ping do jogador
	  (limitado a MaxLatencyCompensation); "Ouvido Fino" alarga a janela e as notas.
	- Habilidades dos artistas (ArtistService.GetEffects): boost extra, cooldowns reduzidos,
	  máquinas automáticas (Auto-<máquina>/Espetáculo Total) e Salva-Drop.
	- O cliente recebe os tempos em Workspace:GetServerTimeNow() para sincronizar a UI.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local BassDropConfig = require(ReplicatedStorage.Shared.Config.BassDrop)
local PyroConfig = require(ReplicatedStorage.Shared.Config.Pyro)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local DropCalc = require(ReplicatedStorage.Shared.Calc.DropCalc)
local PrestigeCalc = require(ReplicatedStorage.Shared.Calc.PrestigeCalc)
local ArtistsConfig = require(ReplicatedStorage.Shared.Config.Artists)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local PyroService = require(script.Parent.PyroService)
local ArtistService = require(script.Parent.ArtistService)

type DropPhase = Types.DropPhase
type DropState = Types.DropState
type DropResolved = Types.DropResolved
type GradeDef = Types.GradeDef

type Session = {
	Phase: DropPhase,
	Energy: number,
	Token: number, -- invalida transições agendadas antigas
	DropClock: number, -- instante do drop em os.clock()
	DropServerTime: number, -- o mesmo instante em hora do servidor
	PhaseStart: number,
	PhaseEnd: number,
	BoostMultiplier: number,
	WindowBonus: number, -- fixado no início do build-up
	Triggered: boolean,
	Dirty: boolean,
}

local BassDropService = {}

local dropSucceeded: Signal.Signal<Player, Types.DropGrade> = Signal.new()

-- (jogador, nota) — cada drop bem-sucedido (missões e conquistas)
BassDropService.DropSucceeded = dropSucceeded

local trove = Trove.new()
local sessions: { [Player]: Session } = {}
local pendingFills: { [Player]: boolean } = {} -- "Energia Cheia" comprada fora da fase de carga
local saveDropReady: { [Player]: { [string]: number } } = {} -- uid do artista -> os.clock() em que fica pronto

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
		WindowBonus = 0,
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
		WindowBonus = session.WindowBonus,
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

-- Modificadores: artistas + árvore de Prestige, somados e limitados pelos mesmos tetos
type DropModifiers = {
	Window: number,
	Boost: number,
	CooldownCut: number,
	StartEnergy: number,
}

local function getModifiers(player: Player): DropModifiers
	local artist = ArtistService.GetEffects(player)
	local data = DataService.GetProfile(player)
	local skills = if data then PrestigeCalc.GetSkillEffects(data.SkillTree) else nil
	local caps = ArtistsConfig.Caps
	return {
		Window = math.min(artist.WindowBonus + (if skills then skills.WindowBonus else 0), caps.WindowBonus),
		Boost = math.min(artist.BoostBonus + (if skills then skills.BoostBonus else 0), caps.BoostBonus),
		CooldownCut = math.min(artist.CooldownCut + (if skills then skills.CooldownCut else 0), caps.CooldownCut),
		StartEnergy = if skills then skills.StartEnergy else 0,
	}
end

-- Resolução do drop ----------------------------------------------------------------

local startCharging: (player: Player, session: Session, energy: number) -> ()

-- Junta às máquinas disparadas as automáticas dos artistas (se desbloqueadas)
local function withAutoPyro(player: Player, ids: { string }): { string }
	local mask = ArtistService.GetEffects(player).AutoPyroMask
	if mask == 0 then
		return ids
	end
	local result = table.clone(ids)
	for _, def in PyroConfig.List do
		if bit32.band(mask, def.Bit) ~= 0 and PyroService.Owns(player, def.Id) and not table.find(result, def.Id) then
			table.insert(result, def.Id)
		end
	end
	return result
end

--[[
	Conclui um drop com sucesso.
	firedIds: máquinas que entram no multiplicador; cooldownIds: as que entram em cooldown
	(as automáticas dos artistas não consomem cooldown).
]]
local function resolveDrop(
	player: Player,
	session: Session,
	grade: GradeDef,
	firedIds: { string },
	cooldownIds: { string },
	savedBy: string?
)
	session.Triggered = true
	local modifiers = getModifiers(player)
	local multiplier, synergies = DropCalc.ComputeMultiplier(firedIds, grade.Factor)
	PyroService.StartCooldowns(player, cooldownIds, modifiers.CooldownCut, ArtistService.GetEffects(player).MachineCut, ArtistsConfig.Caps.CooldownCut)

	local data = DataService.GetProfile(player)
	if data then
		data.Stats.BassDrops += 1
	end

	local duration = BassDropConfig.BoostDuration + modifiers.Boost
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
		Mask = DropCalc.IdsToMask(firedIds),
		Grade = grade.Grade,
		Multiplier = multiplier,
		Synergies = synergyIds,
		ServerTime = serverNow(),
		SavedBy = savedBy,
	}
	ServerNet.FireAllClients(RemoteDefs.Defs.DropResolved, result)
	dropSucceeded:Fire(player, grade.Grade)
end

-- Salva-Drop: o primeiro artista pronto (melhor nota primeiro) faz o drop pelo jogador
local function trySaveDrop(player: Player, session: Session): boolean
	local saves = ArtistService.GetEffects(player).SaveDrops
	if #saves == 0 then
		return false
	end
	local ready = saveDropReady[player]
	if not ready then
		ready = {}
		saveDropReady[player] = ready
	end
	local now = os.clock()
	for _, save in saves do
		if (ready[save.Uid] or 0) <= now then
			local grade = DropCalc.GetGradeDef(save.Grade)
			if grade then
				ready[save.Uid] = now + save.Cooldown
				local usable = PyroService.GetUsable(player, PyroConfig.FullMask)
				resolveDrop(player, session, grade, withAutoPyro(player, usable), usable, save.Name)
				return true
			end
		end
	end
	return false
end

-- Transições -----------------------------------------------------------------

local startBuildUp: (player: Player, session: Session) -> ()

startCharging = function(player: Player, session: Session, energy: number)
	enterPhase(session, "Charging", 0)
	-- "Pré-aquecimento": cada carga começa com energia extra
	session.Energy = math.clamp(energy + getModifiers(player).StartEnergy, 0, BassDropConfig.MaxEnergy - 1)
	session.BoostMultiplier = 1
	session.Triggered = false
	EconomyService.SetBoost(player, 1, 0)
	sendState(player, session)
	if pendingFills[player] then
		pendingFills[player] = nil
		task.defer(BassDropService.FillEnergy, player)
	end
end

local function onWindowClosed(player: Player, session: Session)
	if session.Triggered then
		return
	end
	if trySaveDrop(player, session) then
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
		SavedBy = nil,
	}
	ServerNet.FireClient(RemoteDefs.Defs.DropResolved, player, result)
end

local function openWindow(player: Player, session: Session)
	local after = BassDropConfig.WindowAfter + session.WindowBonus
	enterPhase(session, "Window", session.DropServerTime + after)
	sendState(player, session)
	schedule(player, session, session.DropClock + after - os.clock(), function()
		onWindowClosed(player, session)
	end)
end

startBuildUp = function(player: Player, session: Session)
	local duration = DropCalc.GetBuildUpDuration()
	session.WindowBonus = getModifiers(player).Window
	local before = BassDropConfig.WindowBefore + session.WindowBonus
	session.DropClock = os.clock() + duration
	session.DropServerTime = serverNow() + duration
	session.Triggered = false
	session.Energy = BassDropConfig.MaxEnergy
	enterPhase(session, "BuildUp", session.DropServerTime - before)
	sendState(player, session)
	schedule(player, session, duration - before, function()
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

local function energyMultiplier(player: Player): number
	return 1 + ArtistService.GetEffects(player).EnergyBonus
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
	local bonus = session.WindowBonus
	local pressedAt = os.clock() - getLatencyCompensation(player)
	local offset = math.max(pressedAt - session.DropClock, -(BassDropConfig.WindowBefore + bonus))
	local grade = DropCalc.GradeOffset(offset, bonus)
	if not grade then
		return -- chegou depois da janela; o fecho trata (Salva-Drop ou falhanço)
	end

	local usable = PyroService.GetUsable(player, maskArg :: number)
	resolveDrop(player, session, grade, withAutoPyro(player, usable), usable, nil)
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
			addEnergy(player, BassDropConfig.PassiveEnergyPerSecond * deltaTime * energyMultiplier(player))
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

-- "Energia Cheia" (produto / recompensa): enche já se estiver a carregar; senão, na próxima carga
function BassDropService.FillEnergy(player: Player)
	local session = sessions[player]
	if session and session.Phase == "Charging" then
		addEnergy(player, BassDropConfig.MaxEnergy)
	else
		pendingFills[player] = true
	end
end

-- World Tour: nova sessão (cancela build-up/janela/boost em curso) e recarga do Salva-Drop
function BassDropService.ResetSession(player: Player)
	local session = newSession()
	sessions[player] = session
	saveDropReady[player] = nil
	startCharging(player, session, 0)
end

-- Ciclo de vida --------------------------------------------------------------

function BassDropService.Init()
	ServerNet.Connect(RemoteDefs.Defs.TriggerDrop, onTriggerDrop)

	trove:Add(DataService.ProfileLoaded:Connect(function(player: Player)
		if player.Parent ~= Players then
			return
		end
		local session = newSession() -- substitui (e invalida) a sessão anterior
		sessions[player] = session
		saveDropReady[player] = nil
		startCharging(player, session, 0)
	end))

	trove:Add(EconomyService.Clicked:Connect(function(player: Player, count: number)
		addEnergy(player, BassDropConfig.EnergyPerClick * count * energyMultiplier(player))
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
		saveDropReady[player] = nil
		pendingFills[player] = nil
	end)
end

function BassDropService.Start()
	trove:Add(task.spawn(energyLoop))
	trove:Add(task.spawn(syncLoop))
end

return BassDropService
