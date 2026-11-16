--!strict
--[[
	RemoteDefs
	Fonte única de verdade para todos os Remotes do jogo.
	O servidor cria as instâncias a partir daqui; o cliente espera por elas.
	Args/RateLimit só se aplicam a remotes ClientToServer (validados no servidor).
]]

local Types = require(script.Parent.Parent.Types)
local EconomyConfig = require(script.Parent.Parent.Config.Economy)
local EquipmentConfig = require(script.Parent.Parent.Config.Equipment)
local PyroConfig = require(script.Parent.Parent.Config.Pyro)

type RemoteDef = Types.RemoteDef

export type Registry = {
	Click: RemoteDef,
	ClientReady: RemoteDef,
	BuyEquipment: RemoteDef,
	TriggerDrop: RemoteDef,
	BuyPyro: RemoteDef,
	ReturnToPlot: RemoteDef,
	StateSnapshot: RemoteDef,
	StateDelta: RemoteDef,
	Notify: RemoteDef,
	PurchaseResult: RemoteDef,
	DropState: RemoteDef,
	DropResolved: RemoteDef,
}

local BUY_MODES: { string } = { "x1", "x10", "x100", "Max" }

local Defs: Registry = {
	-- Cliente -> Servidor ----------------------------------------------------
	Click = {
		Name = "Click",
		Direction = "ClientToServer",
		RateLimit = { PerSecond = EconomyConfig.Click.MaxCPS, Burst = EconomyConfig.Click.Burst },
		Args = {},
	},
	ClientReady = {
		Name = "ClientReady",
		Direction = "ClientToServer",
		RateLimit = { PerSecond = 0.1, Burst = 2 },
		Args = {},
	},
	BuyEquipment = { -- (equipmentId: string, mode: BuyMode)
		Name = "BuyEquipment",
		Direction = "ClientToServer",
		RateLimit = {
			PerSecond = EconomyConfig.Purchase.RequestsPerSecond,
			Burst = EconomyConfig.Purchase.RequestBurst,
		},
		Args = {
			{ Kind = "enum", Values = EquipmentConfig.Ids },
			{ Kind = "enum", Values = BUY_MODES },
		},
	},
	TriggerDrop = { -- (armedMask: inteiro com um bit por máquina armada)
		Name = "TriggerDrop",
		Direction = "ClientToServer",
		RateLimit = { PerSecond = 2, Burst = 3 },
		Args = {
			{ Kind = "number", Integer = true, Min = 0, Max = PyroConfig.FullMask },
		},
	},
	BuyPyro = { -- (pyroId: string)
		Name = "BuyPyro",
		Direction = "ClientToServer",
		RateLimit = { PerSecond = 4, Burst = 6 },
		Args = {
			{ Kind = "enum", Values = PyroConfig.Ids },
		},
	},
	ReturnToPlot = { -- sem argumentos; o servidor teleporta para o spawn do próprio terreno
		Name = "ReturnToPlot",
		Direction = "ClientToServer",
		RateLimit = { PerSecond = 1 / 3, Burst = 1 },
		Args = {},
	},

	-- Servidor -> Cliente ----------------------------------------------------
	StateSnapshot = { -- payload: Types.PlayerStateSnapshot
		Name = "StateSnapshot",
		Direction = "ServerToClient",
		Args = {},
	},
	StateDelta = { -- payload: Types.StateDelta
		Name = "StateDelta",
		Direction = "ServerToClient",
		Args = {},
	},
	Notify = { -- payload: Types.Notice
		Name = "Notify",
		Direction = "ServerToClient",
		Args = {},
	},
	PurchaseResult = { -- payload: Types.PurchaseResult
		Name = "PurchaseResult",
		Direction = "ServerToClient",
		Args = {},
	},
	DropState = { -- payload: Types.DropState (só o próprio jogador)
		Name = "DropState",
		Direction = "ServerToClient",
		Args = {},
	},
	DropResolved = { -- payload: Types.DropResolved (todos, para VFX com LOD)
		Name = "DropResolved",
		Direction = "ServerToClient",
		Args = {},
	},
}

local All: { RemoteDef } = {
	Defs.Click,
	Defs.ClientReady,
	Defs.BuyEquipment,
	Defs.TriggerDrop,
	Defs.BuyPyro,
	Defs.ReturnToPlot,
	Defs.StateSnapshot,
	Defs.StateDelta,
	Defs.Notify,
	Defs.PurchaseResult,
	Defs.DropState,
	Defs.DropResolved,
}

return table.freeze({
	FolderName = "Remotes",
	Defs = Defs,
	All = All,
	BuyModes = table.freeze(BUY_MODES),
})
