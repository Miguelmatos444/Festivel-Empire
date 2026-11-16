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
local StagesConfig = require(script.Parent.Parent.Config.Stages)
local ArtistsConfig = require(script.Parent.Parent.Config.Artists)
local SkillTreeConfig = require(script.Parent.Parent.Config.SkillTree)
local MapConfig = require(script.Parent.Parent.Config.Map)

type RemoteDef = Types.RemoteDef

export type Registry = {
	Click: RemoteDef,
	ClientReady: RemoteDef,
	BuyEquipment: RemoteDef,
	TriggerDrop: RemoteDef,
	BuyPyro: RemoteDef,
	ReturnToPlot: RemoteDef,
	BuyStage: RemoteDef,
	OpenCrate: RemoteDef,
	EquipArtist: RemoteDef,
	EquipBestArtists: RemoteDef,
	UnequipArtist: RemoteDef,
	SetArtistLock: RemoteDef,
	FuseArtists: RemoteDef,
	SetAutoFuse: RemoteDef,
	SetAutoDelete: RemoteDef,
	BuySkillNode: RemoteDef,
	DoWorldTour: RemoteDef,
	ClaimDaily: RemoteDef,
	ClaimMission: RemoteDef,
	RedeemCode: RemoteDef,
	SetAutoClick: RemoteDef,
	VisitPlot: RemoteDef,
	GiveLike: RemoteDef,
	StateSnapshot: RemoteDef,
	StateDelta: RemoteDef,
	Notify: RemoteDef,
	PurchaseResult: RemoteDef,
	DropState: RemoteDef,
	DropResolved: RemoteDef,
	ArtistsSync: RemoteDef,
	CrateResult: RemoteDef,
	RetentionSync: RemoteDef,
	SocialSync: RemoteDef,
}

local UID_ARG: Types.ArgSpec = { Kind = "string", MaxLength = 12, Pattern = "^%d+$" }

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
		RateLimit = { PerSecond = 0.25, Burst = 3 }, -- permite as repetições do cliente (a cada 5 s)
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
	BuyStage = { -- (targetTier: inteiro) — tem de ser exatamente o tier atual + 1
		Name = "BuyStage",
		Direction = "ClientToServer",
		RateLimit = { PerSecond = 1, Burst = 2 },
		Args = {
			{ Kind = "number", Integer = true, Min = 2, Max = StagesConfig.MaxTier },
		},
	},
	OpenCrate = { -- (crateId, count: 1 | 10)
		Name = "OpenCrate",
		Direction = "ClientToServer",
		RateLimit = { PerSecond = 2, Burst = 4 },
		Args = {
			{ Kind = "enum", Values = ArtistsConfig.CrateIds },
			{ Kind = "number", Integer = true, Min = 1, Max = 10 },
		},
	},
	EquipArtist = { -- (uid)
		Name = "EquipArtist",
		Direction = "ClientToServer",
		RateLimit = { PerSecond = 6, Burst = 10 },
		Args = { UID_ARG },
	},
	EquipBestArtists = { -- sem argumentos; o servidor escolhe a melhor combinação
		Name = "EquipBestArtists",
		Direction = "ClientToServer",
		RateLimit = { PerSecond = 1, Burst = 2 },
		Args = {},
	},
	UnequipArtist = { -- (uid)
		Name = "UnequipArtist",
		Direction = "ClientToServer",
		RateLimit = { PerSecond = 6, Burst = 10 },
		Args = { UID_ARG },
	},
	SetArtistLock = { -- (uid, locked)
		Name = "SetArtistLock",
		Direction = "ClientToServer",
		RateLimit = { PerSecond = 6, Burst = 10 },
		Args = { UID_ARG, { Kind = "boolean" } },
	},
	FuseArtists = { -- (uid | "all") — funde o grupo desse artista, ou todos os grupos
		Name = "FuseArtists",
		Direction = "ClientToServer",
		RateLimit = { PerSecond = 2, Burst = 4 },
		Args = { { Kind = "string", MaxLength = 12, Pattern = "^[%dal]+$" } },
	},
	SetAutoFuse = { -- (enabled)
		Name = "SetAutoFuse",
		Direction = "ClientToServer",
		RateLimit = { PerSecond = 2, Burst = 4 },
		Args = { { Kind = "boolean" } },
	},
	SetAutoDelete = { -- (upToIndex: 0 = desligado)
		Name = "SetAutoDelete",
		Direction = "ClientToServer",
		RateLimit = { PerSecond = 4, Burst = 6 },
		Args = { { Kind = "number", Integer = true, Min = 0, Max = ArtistsConfig.AutoDeleteMaxIndex } },
	},
	BuySkillNode = { -- (nodeId)
		Name = "BuySkillNode",
		Direction = "ClientToServer",
		RateLimit = { PerSecond = 4, Burst = 8 },
		Args = { { Kind = "enum", Values = SkillTreeConfig.Ids } },
	},
	DoWorldTour = { -- sem argumentos; o servidor valida requisitos e faz o reset
		Name = "DoWorldTour",
		Direction = "ClientToServer",
		RateLimit = { PerSecond = 0.2, Burst = 1 },
		Args = {},
	},
	ClaimDaily = { -- sem argumentos
		Name = "ClaimDaily",
		Direction = "ClientToServer",
		RateLimit = { PerSecond = 0.5, Burst = 2 },
		Args = {},
	},
	ClaimMission = { -- (slot: "D1".."D3" | "W1".."W2")
		Name = "ClaimMission",
		Direction = "ClientToServer",
		RateLimit = { PerSecond = 2, Burst = 5 },
		Args = { { Kind = "string", MaxLength = 3, Pattern = "^[DW]%d$" } },
	},
	RedeemCode = { -- (código: letras e números)
		Name = "RedeemCode",
		Direction = "ClientToServer",
		RateLimit = { PerSecond = 1, Burst = 1 },
		Args = { { Kind = "string", MaxLength = 24, Pattern = "^%w+$" } },
	},
	SetAutoClick = { -- (ligado)
		Name = "SetAutoClick",
		Direction = "ClientToServer",
		RateLimit = { PerSecond = 2, Burst = 4 },
		Args = { { Kind = "boolean" } },
	},
	VisitPlot = { -- (plotIndex) — teleporta para o spawn do festival desse terreno
		Name = "VisitPlot",
		Direction = "ClientToServer",
		RateLimit = { PerSecond = 1 / 3, Burst = 1 },
		Args = { { Kind = "number", Integer = true, Min = 1, Max = MapConfig.Plots.Count } },
	},
	GiveLike = { -- (plotIndex) — Like ao festival em que o jogador está
		Name = "GiveLike",
		Direction = "ClientToServer",
		RateLimit = { PerSecond = 1, Burst = 2 },
		Args = { { Kind = "number", Integer = true, Min = 1, Max = MapConfig.Plots.Count } },
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
	ArtistsSync = { -- payload: Types.ArtistsSync (coleção completa do próprio jogador)
		Name = "ArtistsSync",
		Direction = "ServerToClient",
		Args = {},
	},
	CrateResult = { -- payload: Types.CrateResult
		Name = "CrateResult",
		Direction = "ServerToClient",
		Args = {},
	},
	RetentionSync = { -- payload: Types.RetentionSync
		Name = "RetentionSync",
		Direction = "ServerToClient",
		Args = {},
	},
	SocialSync = { -- payload: Types.SocialSync (só o próprio jogador)
		Name = "SocialSync",
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
	Defs.BuyStage,
	Defs.OpenCrate,
	Defs.EquipArtist,
	Defs.EquipBestArtists,
	Defs.UnequipArtist,
	Defs.SetArtistLock,
	Defs.FuseArtists,
	Defs.SetAutoFuse,
	Defs.SetAutoDelete,
	Defs.BuySkillNode,
	Defs.DoWorldTour,
	Defs.ClaimDaily,
	Defs.ClaimMission,
	Defs.RedeemCode,
	Defs.SetAutoClick,
	Defs.VisitPlot,
	Defs.GiveLike,
	Defs.StateSnapshot,
	Defs.StateDelta,
	Defs.Notify,
	Defs.PurchaseResult,
	Defs.DropState,
	Defs.DropResolved,
	Defs.ArtistsSync,
	Defs.CrateResult,
	Defs.RetentionSync,
	Defs.SocialSync,
}

return table.freeze({
	FolderName = "Remotes",
	Defs = Defs,
	All = All,
	BuyModes = table.freeze(BUY_MODES),
})
