--!strict
--[[
	ArrowController
	Lado do cliente do minijogo de setas (Fase 9): guarda as bolinhas que o servidor
	gerou, traduz teclas/D-pad/toques em pedidos "acertei na bolinha X com a seta Y"
	e toca a animação de atuar no próprio boneco (replicada pelo Roblox).

	O cliente nunca decide notas, combo nem Hype: tudo chega no ArrowEvent do servidor.
	Seta no PC/comando: acerta na bolinha visível MAIS ANTIGA com essa seta; se não
	houver nenhuma com essa seta, envia-a contra a mais antiga (o servidor conta como
	seta errada e reinicia o combo).
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local ArrowGameConfig = require(ReplicatedStorage.Shared.Config.ArrowGame)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local TokenBucket = require(ReplicatedStorage.Shared.Util.TokenBucket)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
local NetController = require(script.Parent.NetController)

type ArrowDirection = Types.ArrowDirection
type ArrowEvent = Types.ArrowEvent

export type ClientArrow = {
	Id: number,
	Dir: ArrowDirection,
	SpawnAt: number,
	Lifetime: number,
	Consumed: boolean, -- já enviada como acerto (ou expirada localmente)
}

export type RemovedReason = "Hit" | "Expired" | "Cleared"

local ACTION_NAME = "FE_ArrowGame"
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value + 50
local SAFETY_FACTOR = 0.9
local MOVE_THRESHOLD = 0.1

local KEY_TO_DIRECTION: { [Enum.KeyCode]: ArrowDirection } = {
	[Enum.KeyCode.Up] = "Up",
	[Enum.KeyCode.Down] = "Down",
	[Enum.KeyCode.Left] = "Left",
	[Enum.KeyCode.Right] = "Right",
	[Enum.KeyCode.DPadUp] = "Up",
	[Enum.KeyCode.DPadDown] = "Down",
	[Enum.KeyCode.DPadLeft] = "Left",
	[Enum.KeyCode.DPadRight] = "Right",
}

local ArrowController = {}

local activeChanged: Signal.Signal<boolean> = Signal.new()
local pausedChanged: Signal.Signal<boolean> = Signal.new()
local removed: Signal.Signal<number, RemovedReason> = Signal.new()
local result: Signal.Signal<ArrowEvent> = Signal.new()

-- (ativo) — entrou/saiu do minijogo
ArrowController.ActiveChanged = activeChanged
-- (em pausa) — build-up/janela do Bass Drop
ArrowController.PausedChanged = pausedChanged
-- (id, motivo) — a bolinha deixou de estar no ecrã
ArrowController.Removed = removed
-- Eventos "Hit"/"Miss" do servidor (notas, combo, Hype ganho)
ArrowController.Result = result

local trove = Trove.new()
local active = false
local paused = false
local arrows: { ClientArrow } = {} -- por ordem de nascimento
local combo = 0
local comboMultiplier = 1
local bucket: TokenBucket.TokenBucket? = nil
local sounds: { [string]: Sound } = {}

-- Animação de atuar
local animTrack: AnimationTrack? = nil
local animCharacter: Model? = nil

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

-- Consultas ------------------------------------------------------------------

function ArrowController.IsActive(): boolean
	return active
end

function ArrowController.IsPaused(): boolean
	return paused
end

-- Bolinhas guardadas (inclui as que ainda não nasceram); só leitura
function ArrowController.GetArrows(): { ClientArrow }
	return arrows
end

function ArrowController.GetCombo(): (number, number)
	return combo, comboMultiplier
end

-- true se a bolinha está no ecrã agora (nasceu, não expirou, não foi usada)
function ArrowController.IsVisible(arrow: ClientArrow, now: number): boolean
	return not arrow.Consumed and now >= arrow.SpawnAt and now < arrow.SpawnAt + arrow.Lifetime
end

-- Som ------------------------------------------------------------------------

local function addSound(name: string, id: number, volume: number)
	if id <= 0 then
		return
	end
	local sound = trove:Add(Instance.new("Sound"))
	sound.Name = "Arrow" .. name
	sound.SoundId = "rbxassetid://" .. tostring(id)
	sound.Volume = volume
	sound.Parent = SoundService
	sounds[name] = sound
end

local function playSound(name: string)
	local sound = sounds[name]
	if sound then
		sound.TimePosition = 0
		sound:Play()
	end
end

-- Lista de bolinhas ------------------------------------------------------------

local function removeAt(index: number, reason: RemovedReason)
	local arrow = table.remove(arrows, index)
	if arrow then
		removed:Fire(arrow.Id, reason)
	end
end

local function findIndex(id: number): number?
	for index, arrow in arrows do
		if arrow.Id == id then
			return index
		end
	end
	return nil
end

local function clearArrows()
	for index = #arrows, 1, -1 do
		removeAt(index, "Cleared")
	end
end

-- Remove as que já passaram do tempo de vida (sem avisar o servidor: ele trata das falhas)
local function expireLocal(now: number)
	for index = #arrows, 1, -1 do
		local arrow = arrows[index]
		if now >= arrow.SpawnAt + arrow.Lifetime then
			removeAt(index, if arrow.Consumed then "Hit" else "Expired")
		end
	end
end

-- Envio de acertos ---------------------------------------------------------------

local function send(arrow: ClientArrow, direction: ArrowDirection): boolean
	local current = bucket
	if not current or not current:TryConsume() then
		return false
	end
	NetController.Fire(RemoteDefs.Defs.ArrowHit, arrow.Id, direction)
	return true
end

local function consume(arrow: ClientArrow)
	arrow.Consumed = true
	local index = findIndex(arrow.Id)
	if index then
		removeAt(index, "Hit")
	end
	playSound("Hit")
end

-- Seta carregada (teclado / comando)
function ArrowController.PressDirection(direction: ArrowDirection)
	if not active or paused then
		return
	end
	local now = serverNow()
	local oldestAny: ClientArrow? = nil
	for _, arrow in arrows do -- já estão por ordem de nascimento
		if ArrowController.IsVisible(arrow, now) then
			if arrow.Dir == direction then
				if send(arrow, direction) then
					consume(arrow)
				end
				return
			end
			if not oldestAny then
				oldestAny = arrow
			end
		end
	end
	local target = oldestAny
	if target then
		send(target, direction) -- seta errada: o servidor reinicia o combo; a bolinha fica
	end
end

-- Toque numa bolinha (telemóvel / rato)
function ArrowController.TapArrow(id: number)
	if not active or paused then
		return
	end
	local index = findIndex(id)
	local arrow = if index then arrows[index] else nil
	if arrow and ArrowController.IsVisible(arrow, serverNow()) and send(arrow, arrow.Dir) then
		consume(arrow)
	end
end

-- Entrada --------------------------------------------------------------------

local function onAction(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local direction = KEY_TO_DIRECTION[input.KeyCode]
	if direction and state == Enum.UserInputState.Begin then
		ArrowController.PressDirection(direction)
	end
	-- Afunda sempre as setas: não rodam a câmara nem mexem o boneco durante o minijogo
	return Enum.ContextActionResult.Sink
end

local function bindInput()
	local keys: { Enum.KeyCode } = {}
	for keyCode in KEY_TO_DIRECTION do
		table.insert(keys, keyCode)
	end
	ContextActionService:BindActionAtPriority(ACTION_NAME, onAction, false, ACTION_PRIORITY, table.unpack(keys))
end

local function unbindInput()
	ContextActionService:UnbindAction(ACTION_NAME)
end

-- Animação de atuar (no próprio boneco; o Roblox replica-a aos outros) ------------------

local function stopAnimation()
	local track = animTrack
	animTrack = nil
	animCharacter = nil
	if track then
		track:Stop(0.3)
		track:Destroy()
	end
end

local function loadAnimation(character: Model): AnimationTrack?
	local animationId = ArrowGameConfig.Client.PerformAnimationId
	if animationId <= 0 then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	if not animator then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(animationId)
	local ok, track = pcall(function(): AnimationTrack
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok then
		Diag.Log("Arrows", "animação de atuar indisponível: " .. tostring(track))
		return nil
	end
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Action
	return track
end

-- Dança parado; ao andar no palco a animação pára (volta quando parar)
local function updateAnimation()
	if not active then
		return
	end
	local character = Players.LocalPlayer.Character
	if not character then
		return
	end
	if character ~= animCharacter then
		stopAnimation()
		animCharacter = character
		animTrack = loadAnimation(character)
	end
	local track = animTrack
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not track or not humanoid then
		return
	end
	local moving = humanoid.MoveDirection.Magnitude > MOVE_THRESHOLD
	if moving and track.IsPlaying then
		track:Stop(0.2)
	elseif not moving and not track.IsPlaying then
		track:Play(0.3)
	end
end

-- Estado ---------------------------------------------------------------------

local function setActive(value: boolean)
	if active == value then
		return
	end
	active = value
	combo = 0
	comboMultiplier = 1
	if value then
		bindInput()
	else
		unbindInput()
		clearArrows()
		stopAnimation()
		if paused then
			paused = false
			pausedChanged:Fire(false)
		end
	end
	activeChanged:Fire(value)
end

local function setPaused(value: boolean)
	if paused == value then
		return
	end
	paused = value
	if value then
		clearArrows()
	end
	pausedChanged:Fire(value)
end

local function onEvent(eventArg: unknown)
	if type(eventArg) ~= "table" then
		return
	end
	local event = (eventArg :: unknown) :: ArrowEvent
	if event.Kind == "Start" then
		setActive(true)
		setPaused(false)
	elseif event.Kind == "Stop" then
		setActive(false)
	elseif event.Kind == "Pause" then
		setPaused(true)
	elseif event.Kind == "Spawn" then
		if not active or paused then
			return
		end
		for _, spawn in event.Arrows do
			if not findIndex(spawn.Id) then
				table.insert(arrows, {
					Id = spawn.Id,
					Dir = spawn.Dir,
					SpawnAt = spawn.SpawnAt,
					Lifetime = spawn.Lifetime,
					Consumed = false,
				})
			end
		end
	elseif event.Kind == "Hit" then
		if not event.Auto then
			combo = event.Combo
			comboMultiplier = event.ComboMultiplier
		end
		result:Fire(event)
	elseif event.Kind == "Miss" then
		combo = 0
		comboMultiplier = 1
		playSound("Miss")
		result:Fire(event)
	end
end

-- Ciclo de vida --------------------------------------------------------------

function ArrowController.Init()
	local limit = RemoteDefs.Defs.ArrowHit.RateLimit
	assert(limit, "RemoteDefs.ArrowHit precisa de RateLimit")
	bucket = TokenBucket.new(limit.PerSecond * SAFETY_FACTOR, math.max(1, math.floor(limit.Burst * SAFETY_FACTOR)))

	local client = ArrowGameConfig.Client
	addSound("Hit", client.HitSoundId, client.HitVolume)
	addSound("Miss", client.MissSoundId, client.MissVolume)

	trove:Add(NetController.On(RemoteDefs.Defs.ArrowEvent, onEvent))
	trove:Connect(RunService.Heartbeat, function()
		if active then
			expireLocal(serverNow())
			updateAnimation()
		end
	end)
	trove:Add(function()
		unbindInput()
		stopAnimation()
	end)
end

return ArrowController
