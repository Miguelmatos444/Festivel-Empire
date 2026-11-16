--!strict
--[[
	BassDropController
	Estado local (só de leitura) do Bass Drop do jogador, máquinas armadas
	e envio do TriggerDrop. Todos os tempos usam Workspace:GetServerTimeNow(),
	o mesmo relógio que o servidor usa nos DropState.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local BassDropConfig = require(ReplicatedStorage.Shared.Config.BassDrop)
local PyroConfig = require(ReplicatedStorage.Shared.Config.Pyro)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
local NetController = require(script.Parent.NetController)

type DropState = Types.DropState
type DropResolved = Types.DropResolved

local TRIGGER_RETRY_DELAY = 0.25 -- evita spam; o servidor ignora repetições

local BassDropController = {}

local changed: Signal.Signal<DropState> = Signal.new()
local resolved: Signal.Signal<DropResolved> = Signal.new()
local armedChanged: Signal.Signal<string, boolean> = Signal.new()

-- Novo estado do próprio drop
BassDropController.Changed = changed
-- Resultado de um drop de QUALQUER jogador (falhas só chegam ao próprio)
BassDropController.Resolved = resolved
-- (id, armada)
BassDropController.ArmedChanged = armedChanged

local trove = Trove.new()
local state: DropState? = nil
local armed: { [string]: boolean } = { ColdSparks = true }
local lastTriggerAt = -math.huge

function BassDropController.GetServerTime(): number
	return Workspace:GetServerTimeNow()
end

function BassDropController.Get(): DropState?
	return state
end

function BassDropController.GetBoostMultiplier(): number
	local current = state
	if current and current.Phase == "Boost" and BassDropController.GetServerTime() < current.PhaseEnd then
		return current.BoostMultiplier
	end
	return 1
end

-- Armar ----------------------------------------------------------------------

function BassDropController.IsArmed(id: string): boolean
	return armed[id] == true
end

function BassDropController.ToggleArm(id: string)
	local current = state
	if not current or not current.Owned[id] then
		return
	end
	local nowArmed = not armed[id]
	armed[id] = if nowArmed then true else nil
	armedChanged:Fire(id, nowArmed)
end

-- Máscara das máquinas armadas que o jogador possui
function BassDropController.GetArmedMask(): number
	local current = state
	local mask = 0
	if not current then
		return mask
	end
	for _, def in PyroConfig.List do
		if armed[def.Id] and current.Owned[def.Id] then
			mask = bit32.bor(mask, def.Bit)
		end
	end
	return mask
end

-- Janela ---------------------------------------------------------------------

function BassDropController.IsWindowOpen(): boolean
	local current = state
	if not current or (current.Phase ~= "BuildUp" and current.Phase ~= "Window") then
		return false
	end
	local now = BassDropController.GetServerTime()
	local bonus = current.WindowBonus or 0 -- habilidade "Ouvido Fino" dos artistas
	return now >= current.DropTime - (BassDropConfig.WindowBefore + bonus)
		and now <= current.DropTime + BassDropConfig.WindowAfter + bonus
end

-- Devolve true se o pedido foi enviado
function BassDropController.TriggerDrop(): boolean
	if not BassDropController.IsWindowOpen() then
		return false
	end
	local now = os.clock()
	if now - lastTriggerAt < TRIGGER_RETRY_DELAY then
		return false
	end
	lastTriggerAt = now
	NetController.Fire(RemoteDefs.Defs.TriggerDrop, BassDropController.GetArmedMask())
	return true
end

function BassDropController.BuyPyro(id: string)
	NetController.Fire(RemoteDefs.Defs.BuyPyro, id)
end

-- Ciclo de vida --------------------------------------------------------------

function BassDropController.Init()
	trove:Add(NetController.On(RemoteDefs.Defs.DropState, function(payload: unknown)
		local newState = payload :: DropState
		state = newState
		Diag.LogSampled(
			"Drop",
			"state",
			string.format("barra aplicada: fase %s, energia %.1f/%d", newState.Phase, newState.Energy, newState.MaxEnergy)
		)
		changed:Fire(newState)
	end))
	trove:Add(NetController.On(RemoteDefs.Defs.DropResolved, function(payload: unknown)
		resolved:Fire(payload :: DropResolved)
	end))
end

return BassDropController
