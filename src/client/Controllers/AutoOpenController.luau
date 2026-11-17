--!strict
--[[
	AutoOpenController
	Auto-Abrir (Fase 13C) no cliente: só intenções e cópia do estado.
	  - Start(crateId, regras) / Stop() -> remotes StartAutoOpen / StopAutoOpen
	  - estado do ciclo (AutoOpenState) vindo do servidor, com o sinal Changed
	  - Owns(): posse do Gamepass (RetentionController; /fe autoopen on em Studio)
	  - GetRules(): condições guardadas no perfil (snapshot do PlayerStateService)
	O ritmo, as aberturas e as paragens são decididos pelo servidor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local MonetizationConfig = require(ReplicatedStorage.Shared.Config.Monetization)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local TokenBucket = require(ReplicatedStorage.Shared.Util.TokenBucket)
local NetController = require(script.Parent.NetController)
local StateController = require(script.Parent.StateController)
local RetentionController = require(script.Parent.RetentionController)

type AutoOpenState = Types.AutoOpenState
type AutoOpenSettings = Types.AutoOpenSettings

local AutoOpenController = {}

local changed: Signal.Signal<AutoOpenState> = Signal.new()

-- Disparado a cada estado novo do servidor (a correr, progresso, paragem com motivo)
AutoOpenController.Changed = changed

local trove = Trove.new()
local state: AutoOpenState? = nil
local bucket = TokenBucket.new(1, 2)

function AutoOpenController.Get(): AutoOpenState?
	return state
end

function AutoOpenController.IsRunning(): boolean
	local current = state
	return current ~= nil and current.Running
end

function AutoOpenController.Owns(): boolean
	return RetentionController.Owns("AutoOpen")
end

function AutoOpenController.GetRules(): AutoOpenSettings
	local snapshot = StateController.Get()
	if snapshot and snapshot.AutoOpen then
		return table.clone(snapshot.AutoOpen)
	end
	return { Count = 1, StopSlot = MonetizationConfig.AutoOpen.DefaultStopSlot, StopNew = true, StopShiny = true }
end

function AutoOpenController.Start(crateId: string, rules: AutoOpenSettings): boolean
	if not bucket:TryConsume() then
		return false
	end
	NetController.Fire(RemoteDefs.Defs.StartAutoOpen, crateId, rules.Count, rules.StopSlot, rules.StopNew, rules.StopShiny)
	return true
end

function AutoOpenController.Stop()
	if not AutoOpenController.IsRunning() then
		return
	end
	-- Parar nunca é limitado pelo balde (tem de funcionar sempre)
	NetController.Fire(RemoteDefs.Defs.StopAutoOpen)
end

function AutoOpenController.Init()
	trove:Add(NetController.On(RemoteDefs.Defs.AutoOpenState, function(payload: unknown)
		local next = payload :: AutoOpenState
		state = next
		changed:Fire(next)
	end))
end

return AutoOpenController
