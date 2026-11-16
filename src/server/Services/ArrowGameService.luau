--!strict
--[[
	ArrowGameService
	Minijogo de setas no palco do próprio terreno (Fase 9). Servidor autoritativo:

	  - Entrada/saída automática: um loop leve (ScheduleInterval) confirma a posição da
	    personagem com ArrowCalc.IsOnStage no terreno do jogador. Sair do palco ou morrer
	    termina o modo; durante o build-up/janela do Bass Drop as setas param.
	  - O servidor gera cada bolinha (id, direção, nascimento, tempo de vida) em lotes
	    agendados de antemão e envia-as num único ArrowEvent por ciclo. A posição no
	    ecrã é só apresentação do cliente.
	  - Cada acerto (ArrowHit) é validado: modo ativo, bolinha existente e por usar,
	    nascida (tolerância de relógio), não expirada (desconto de ping limitado) e
	    direção certa. A nota vem do relógio do servidor. Cada bolinha só pode ser
	    usada uma vez -> nunca há mais acertos do que bolinhas geradas.
	  - Seta errada ou bolinha expirada reiniciam o combo.
	  - Auto-Play (Gamepass): bolinhas que expiram sem acerto manual são acertadas com
	    AutoPlay.HitChance, nota e combo fixos (não mexe no combo manual).
	  - Hype por EconomyService.GrantArrowHit; energia por BassDropService.AddEnergy.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local ArrowGameConfig = require(ReplicatedStorage.Shared.Config.ArrowGame)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local BigNum = require(ReplicatedStorage.Shared.Util.BigNum)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
local ArrowCalc = require(ReplicatedStorage.Shared.Calc.ArrowCalc)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local BassDropService = require(script.Parent.BassDropService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local PlotService = require(script.Parent.PlotService)
local MonetizationService = require(script.Parent.MonetizationService)

type ArrowDirection = Types.ArrowDirection
type ArrowGrade = Types.ArrowGrade
type ArrowEvent = Types.ArrowEvent
type ArrowSpawn = Types.ArrowSpawn

type Arrow = {
	Id: number,
	Dir: ArrowDirection,
	SpawnAt: number,
	Lifetime: number,
	Interval: number, -- intervalo do tier no momento em que nasceu (energia)
	Tier: number,
}

type Session = {
	Active: boolean,
	Paused: boolean,
	Arrows: { Arrow }, -- por ordem de nascimento
	NextId: number,
	NextSpawnAt: number,
	Combo: number,
	-- Estatísticas da sessão (debug)
	Hits: number,
	Perfects: number,
	Misses: number,
	AutoHits: number,
	StartedAt: number,
}

export type SessionStats = {
	Active: boolean,
	Paused: boolean,
	Tier: number,
	Combo: number,
	Hits: number,
	Perfects: number,
	Misses: number,
	AutoHits: number,
	Pending: number,
	Seconds: number,
}

local ArrowGameService = {}

local arrowHit: Signal.Signal<Player, ArrowGrade, number, boolean> = Signal.new()
local activeChanged: Signal.Signal<Player, boolean> = Signal.new()

-- (jogador, nota, combo atual, automático) — cada acerto aceite (missões, conquistas)
ArrowGameService.ArrowHit = arrowHit
-- (jogador, ativo) — entrou/saiu do minijogo
ArrowGameService.ActiveChanged = activeChanged

local trove = Trove.new()
local sessions: { [Player]: Session } = {}
local debugTier: { [Player]: number } = {} -- /fe arrows diff <tier>
local debugAuto: { [Player]: boolean } = {} -- /fe arrows auto on
local playerTroves: { [Player]: Trove.Trove } = {}
local rng = Random.new()

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function newSession(): Session
	return {
		Active = false,
		Paused = false,
		Arrows = {},
		NextId = 0,
		NextSpawnAt = 0,
		Combo = 0,
		Hits = 0,
		Perfects = 0,
		Misses = 0,
		AutoHits = 0,
		StartedAt = 0,
	}
end

local function getSession(player: Player): Session
	local session = sessions[player]
	if not session then
		session = newSession()
		sessions[player] = session
	end
	return session
end

local function send(player: Player, event: ArrowEvent)
	if PlayerStateService.IsClientReady(player) then
		ServerNet.FireClient(RemoteDefs.Defs.ArrowEvent, player, event)
	end
end

local function getTier(player: Player): number
	local override = debugTier[player]
	if override then
		return override
	end
	local data = DataService.GetProfile(player)
	return if data then data.StageTier else 1
end

local function isAutoPlay(player: Player): boolean
	return debugAuto[player] == true or MonetizationService.IsAutoPlayOn(player)
end

local function isPausedPhase(player: Player): boolean
	local phase = BassDropService.GetPhase(player)
	return phase ~= nil and table.find(ArrowGameConfig.PausedPhases, phase) ~= nil
end

-- Posição / estado da personagem ------------------------------------------------

local function isOnOwnStage(player: Player): boolean
	local plotIndex = PlotService.GetPlotId(player)
	local data = DataService.GetProfile(player)
	local character = player.Character
	if not plotIndex or not data or not character then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return false
	end
	return ArrowCalc.IsOnStage(plotIndex, data.StageTier, root.Position)
end

-- Combo / resultados ---------------------------------------------------------------

local function removeArrow(session: Session, arrow: Arrow)
	local index = table.find(session.Arrows, arrow)
	if index then
		table.remove(session.Arrows, index)
	end
end

local function breakCombo(player: Player, session: Session, arrowId: number, reason: "Expired" | "Wrong")
	session.Combo = 0
	session.Misses += 1
	send(player, { Kind = "Miss", Id = arrowId, Reason = reason })
end

local function grantHit(player: Player, session: Session, arrow: Arrow, grade: ArrowGrade, auto: boolean)
	local data = DataService.GetProfile(player)
	if not data then
		return
	end
	local factor: number
	local comboMultiplier: number
	if auto then
		factor = ArrowCalc.GetAutoHitFactor(arrow.Tier)
		comboMultiplier = ArrowGameConfig.AutoPlay.ComboMultiplier
		session.AutoHits += 1
	else
		session.Combo += 1
		comboMultiplier = ArrowCalc.GetComboMultiplier(session.Combo)
		factor = ArrowCalc.GetHitFactor(arrow.Tier, grade, session.Combo)
		session.Hits += 1
		if grade == "Perfect" then
			session.Perfects += 1
			data.Stats.ArrowPerfects += 1
		end
		if session.Combo > data.Stats.BestCombo then
			data.Stats.BestCombo = session.Combo
		end
	end
	data.Stats.ArrowHits += 1

	local gain = EconomyService.GrantArrowHit(player, factor)
	BassDropService.AddEnergy(player, ArrowCalc.GetEnergy(arrow.Interval, grade))
	send(player, {
		Kind = "Hit",
		Id = arrow.Id,
		Grade = grade,
		Combo = session.Combo,
		ComboMultiplier = comboMultiplier,
		Gain = BigNum.serialize(gain),
		Auto = auto,
	})
	arrowHit:Fire(player, grade, session.Combo, auto)
end

-- Bolinhas que já expiraram em `cutoff` (hora do servidor), exceto `keep`
local function sweepExpired(player: Player, session: Session, cutoff: number, keep: Arrow?)
	local index = 1
	while index <= #session.Arrows do
		local arrow = session.Arrows[index]
		if arrow ~= keep and arrow.SpawnAt + arrow.Lifetime < cutoff then
			table.remove(session.Arrows, index)
			if isAutoPlay(player) and rng:NextNumber() < ArrowGameConfig.AutoPlay.HitChance then
				grantHit(player, session, arrow, ArrowGameConfig.AutoPlay.Grade, true)
			else
				breakCombo(player, session, arrow.Id, "Expired")
			end
		else
			index += 1
		end
	end
end

-- Agendamento --------------------------------------------------------------------

-- Nº de bolinhas por usar vivas no instante `at`
local function aliveAt(session: Session, at: number): (number, number)
	local count = 0
	local earliestEnd = math.huge
	for _, arrow in session.Arrows do
		local endsAt = arrow.SpawnAt + arrow.Lifetime
		if arrow.SpawnAt <= at and at < endsAt then
			count += 1
			earliestEnd = math.min(earliestEnd, endsAt)
		end
	end
	return count, earliestEnd
end

local function scheduleArrows(player: Player, session: Session, now: number)
	local tier = getTier(player)
	local def = ArrowCalc.GetTierDef(tier)
	local horizon = now + ArrowGameConfig.ScheduleAhead
	local batch: { ArrowSpawn } = {}
	local directions = ArrowGameConfig.Directions

	session.NextSpawnAt = math.max(session.NextSpawnAt, now + ArrowGameConfig.SpawnLead)
	while session.NextSpawnAt <= horizon do
		local spawnAt = session.NextSpawnAt
		local alive, earliestEnd = aliveAt(session, spawnAt)
		if alive >= def.MaxActive then
			-- Ecrã cheio: nasce quando a mais antiga desaparecer
			session.NextSpawnAt = earliestEnd + 0.05
			continue
		end
		session.NextId += 1
		local arrow: Arrow = {
			Id = session.NextId,
			Dir = directions[rng:NextInteger(1, #directions)],
			SpawnAt = spawnAt,
			Lifetime = def.Lifetime,
			Interval = def.SpawnInterval,
			Tier = tier,
		}
		table.insert(session.Arrows, arrow)
		table.insert(batch, { Id = arrow.Id, Dir = arrow.Dir, SpawnAt = arrow.SpawnAt, Lifetime = arrow.Lifetime })
		session.NextSpawnAt = spawnAt + def.SpawnInterval
	end

	if #batch > 0 then
		send(player, { Kind = "Spawn", Arrows = batch })
	end
end

-- Entrar / sair / pausa --------------------------------------------------------------

local function start(player: Player, session: Session)
	session.Active = true
	session.Paused = false
	session.Combo = 0
	session.Arrows = {}
	session.StartedAt = os.clock()
	session.NextSpawnAt = serverNow() + ArrowGameConfig.StartDelay
	player:SetAttribute("FE_Performing", true)
	send(player, { Kind = "Start", Tier = getTier(player) })
	activeChanged:Fire(player, true)
	Diag.Log("Arrows", string.format("%s entrou no minijogo (tier %d)", player.Name, getTier(player)))
end

function ArrowGameService.Stop(player: Player)
	local session = sessions[player]
	if not session or not session.Active then
		return
	end
	session.Active = false
	session.Paused = false
	session.Combo = 0
	session.Arrows = {} -- bolinhas por resolver ao sair não contam como falha
	if player.Parent then
		player:SetAttribute("FE_Performing", nil)
	end
	send(player, { Kind = "Stop" })
	activeChanged:Fire(player, false)
end

local function pause(player: Player, session: Session)
	session.Paused = true
	session.Arrows = {}
	send(player, { Kind = "Pause" })
end

local function resume(player: Player, session: Session)
	session.Paused = false
	session.NextSpawnAt = serverNow() + ArrowGameConfig.StartDelay
	send(player, { Kind = "Start", Tier = getTier(player) })
end

local function update(player: Player, session: Session, now: number)
	local onStage = isOnOwnStage(player)
	if not session.Active then
		if onStage then
			start(player, session)
		else
			return
		end
	elseif not onStage then
		ArrowGameService.Stop(player)
		return
	end

	if isPausedPhase(player) then
		if not session.Paused then
			pause(player, session)
		end
		return
	elseif session.Paused then
		resume(player, session)
	end

	sweepExpired(player, session, now - ArrowGameConfig.LatencyTolerance, nil)
	scheduleArrows(player, session, now)
end

local function scheduleLoop()
	while true do
		task.wait(ArrowGameConfig.ScheduleInterval)
		local now = serverNow()
		for _, player in DataService.GetLoadedPlayers() do
			local ok, err = pcall(update, player, getSession(player), now)
			if not ok then
				warn(string.format("[ArrowGameService] erro no ciclo de %s: %s", player.Name, tostring(err)))
			end
		end
	end
end

-- Acertos ----------------------------------------------------------------------

local function getLatencyCompensation(player: Player): number
	local ok, ping = pcall(function(): number
		return player:GetNetworkPing()
	end)
	if not ok then
		return 0
	end
	return math.clamp(ping, 0, ArrowGameConfig.LatencyTolerance)
end

local function findArrow(session: Session, id: number): Arrow?
	for _, arrow in session.Arrows do
		if arrow.Id == id then
			return arrow
		end
	end
	return nil
end

local function onArrowHit(player: Player, idArg: unknown, dirArg: unknown)
	local session = sessions[player]
	if not session or not session.Active or session.Paused then
		return
	end
	if isPausedPhase(player) then
		return -- o ciclo seguinte limpa as setas
	end
	local arrow = findArrow(session, idArg :: number)
	if not arrow then
		return -- já usada, expirada e resolvida, ou inventada: ignorado
	end

	-- Instante estimado em que o jogador carregou (chegada - ping limitado)
	local pressedAt = serverNow() - getLatencyCompensation(player)
	local progress = ArrowCalc.GetProgress(pressedAt, arrow.SpawnAt, arrow.Lifetime)
	if pressedAt < arrow.SpawnAt - ArrowGameConfig.EarlyTolerance then
		Diag.LogSampled("Arrows", "early:" .. player.UserId, string.format("%s: acerto antes de a bolinha nascer", player.Name))
		return
	end

	-- Falhas mais antigas contam antes deste acerto (ordem certa do combo)
	sweepExpired(player, session, pressedAt, arrow)

	if (dirArg :: ArrowDirection) ~= arrow.Dir then
		breakCombo(player, session, arrow.Id, "Wrong") -- a bolinha continua no ecrã
		return
	end

	removeArrow(session, arrow)
	local grade = ArrowCalc.GradeProgress(progress)
	if not grade then
		breakCombo(player, session, arrow.Id, "Expired")
		return
	end
	grantHit(player, session, arrow, grade.Grade, false)
end

-- API (debug / outros serviços) -------------------------------------------------

function ArrowGameService.IsActive(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.Active
end

function ArrowGameService.GetStats(player: Player): SessionStats
	local session = getSession(player)
	return {
		Active = session.Active,
		Paused = session.Paused,
		Tier = getTier(player),
		Combo = session.Combo,
		Hits = session.Hits,
		Perfects = session.Perfects,
		Misses = session.Misses,
		AutoHits = session.AutoHits,
		Pending = #session.Arrows,
		Seconds = if session.Active then os.clock() - session.StartedAt else 0,
	}
end

-- Debug: força a dificuldade de um tier (nil = tier do palco)
function ArrowGameService.SetDebugTier(player: Player, tier: number?)
	debugTier[player] = if tier then math.clamp(math.floor(tier), 1, #ArrowGameConfig.Tiers) else nil
end

-- Debug: Auto-Play sem Gamepass nesta sessão
function ArrowGameService.SetDebugAuto(player: Player, enabled: boolean)
	debugAuto[player] = if enabled then true else nil
end

function ArrowGameService.ResetStats(player: Player)
	local session = getSession(player)
	session.Hits = 0
	session.Perfects = 0
	session.Misses = 0
	session.AutoHits = 0
end

-- Ciclo de vida --------------------------------------------------------------

local function watchCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Once(function()
			ArrowGameService.Stop(player)
		end)
	end
end

local function onPlayerAdded(player: Player)
	if playerTroves[player] then
		return
	end
	local playerTrove = trove:Extend()
	playerTroves[player] = playerTrove
	playerTrove:Connect(player.CharacterAdded, function(character: Model)
		ArrowGameService.Stop(player) -- personagem nova: começa fora do modo
		watchCharacter(player, character)
	end)
	local character = player.Character
	if character then
		task.spawn(watchCharacter, player, character)
	end
end

function ArrowGameService.Init()
	ServerNet.Connect(RemoteDefs.Defs.ArrowHit, onArrowHit)

	trove:Add(PlayerStateService.ClientReady:Connect(function(player: Player)
		-- Cliente (re)pronto a meio do modo: reenvia o início; as bolinhas seguintes chegam no ciclo
		local session = sessions[player]
		if session and session.Active and not session.Paused then
			send(player, { Kind = "Start", Tier = getTier(player) })
		end
	end))

	trove:Connect(Players.PlayerRemoving, function(player: Player)
		local playerTrove = playerTroves[player]
		if playerTrove then
			playerTroves[player] = nil
			trove:Remove(playerTrove)
		end
		sessions[player] = nil
		debugTier[player] = nil
		debugAuto[player] = nil
	end)
end

function ArrowGameService.Start()
	trove:Connect(Players.PlayerAdded, onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	trove:Add(task.spawn(scheduleLoop))
end

return ArrowGameService
