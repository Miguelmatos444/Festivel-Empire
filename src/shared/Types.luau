--!strict
--[[
	Types
	Definições de tipo partilhadas entre servidor e cliente.
	Este módulo não contém lógica — apenas `export type`.
]]

-- Números grandes ----------------------------------------------------------

export type BigNumData = {
	m: number, -- mantissa normalizada: 1 <= |m| < 10 (ou 0)
	e: number, -- expoente inteiro (base 10)
}

-- Perfil persistido --------------------------------------------------------

export type ArtistData = {
	Id: string, -- id do artista em Config (fase do gacha)
	Stars: number, -- 1★ base, 2★ Remix, 3★ Platinum
	Locked: boolean, -- protegido contra Auto-Delete / fusão
}

export type PityData = {
	Legendary: number, -- aberturas desde o último Lendário
	Mythic: number, -- aberturas desde o último Mítico
}

export type StatsData = {
	Clicks: number,
	PlayTime: number, -- segundos
	BassDrops: number,
}

export type SettingsData = {
	MusicVolume: number,
	SfxVolume: number,
	LowVfx: boolean,
}

export type ProfileData = {
	DataVersion: number,
	Hype: BigNumData,
	TotalHypeEarned: BigNumData,
	PlatinumDiscs: number,
	WorldTours: number,
	StageTier: number,
	Equipment: { [string]: number }, -- id do equipamento -> nível
	Artists: { [string]: ArtistData }, -- uid -> artista
	EquippedArtists: { string }, -- uids nos slots do palco
	Pity: PityData,
	SkillTree: { [string]: number }, -- id do nó -> nível
	Stats: StatsData,
	Settings: SettingsData,
	Pyro: { [string]: boolean }, -- máquinas de pirotecnia desbloqueadas
	LastOnline: number, -- os.time() do último save
}

-- Equipamento ----------------------------------------------------------------

export type EquipmentKind = "Generator" | "Click"
export type EquipmentCategory = "Colunas" | "Mesas" | "DJs" | "Batidas"

export type EquipmentDef = {
	Id: string,
	Name: string,
	Description: string,
	Category: EquipmentCategory,
	Kind: EquipmentKind, -- Generator: Hype/s | Click: Hype por batida
	BaseCost: number,
	GrowthRate: number, -- entre Economy.GrowthRate.Min e Max
	BaseOutput: number, -- produção por nível (antes de marcos)
	RequiredTier: number, -- tier mínimo do palco
	UnlockAfter: string?, -- id que tem de ter nível >= 1 para desbloquear
}

export type BuyMode = "x1" | "x10" | "x100" | "Max"
export type UnlockState = "Unlocked" | "Locked" | "TierTooLow"
export type PurchaseFailReason = "NotLoaded" | "Unknown" | "Locked" | "TierTooLow" | "NotEnoughHype"

export type PurchaseResult = {
	EquipmentId: string,
	Success: boolean,
	Reason: PurchaseFailReason?,
	Levels: number, -- níveis comprados
	NewLevel: number,
}

-- Bass Drop / Pirotecnia --------------------------------------------------

export type DropPhase = "Charging" | "BuildUp" | "Window" | "Boost"
export type DropGrade = "Perfect" | "Great" | "Good" | "Late"

export type GradeDef = {
	Grade: DropGrade,
	Label: string,
	MaxOffset: number, -- distância máxima (s) ao instante do drop
	Factor: number, -- fator aplicado ao multiplicador
}

export type PyroDef = {
	Id: string,
	Name: string,
	ShortName: string, -- texto dos botões da barra de drop
	Description: string,
	Bit: number, -- potência de 2, para a máscara de máquinas armadas
	UnlockCost: number, -- Hype (0 = desbloqueada desde o início)
	BaseMultiplier: number,
	Cooldown: number, -- segundos
	RequiredTier: number,
}

export type SynergyDef = {
	Id: string,
	Name: string,
	Requires: { string },
	Multiplier: number,
}

-- Estado do drop do próprio jogador (tempos em Workspace:GetServerTimeNow())
export type DropState = {
	Phase: DropPhase,
	Energy: number,
	MaxEnergy: number,
	PhaseStart: number,
	PhaseEnd: number, -- 0 quando a fase não tem fim fixo (Charging)
	DropTime: number, -- instante do drop (BuildUp/Window)
	BoostMultiplier: number,
	Owned: { [string]: boolean },
	Cooldowns: { [string]: number }, -- id -> instante em que fica pronta
}

-- Resultado de um drop (enviado a todos para VFX; falhas só ao próprio)
export type DropResolved = {
	UserId: number,
	Success: boolean,
	Mask: number,
	Grade: DropGrade?,
	Multiplier: number,
	Synergies: { string }, -- ids das sinergias ativas
	ServerTime: number,
}

-- Replicação servidor -> cliente ------------------------------------------

export type PlayerStateSnapshot = {
	Hype: BigNumData,
	TotalHypeEarned: BigNumData,
	HypePerClick: BigNumData,
	HypePerSecond: BigNumData,
	PlatinumDiscs: number,
	WorldTours: number,
	StageTier: number,
	Clicks: number,
	Equipment: { [string]: number },
}

export type StateDelta = {
	Hype: BigNumData?,
	TotalHypeEarned: BigNumData?,
	HypePerClick: BigNumData?,
	HypePerSecond: BigNumData?,
	PlatinumDiscs: number?,
	WorldTours: number?,
	StageTier: number?,
	Clicks: number?,
	Equipment: { [string]: number }?, -- apenas as entradas alteradas
}

export type Notice = { Kind: "OfflineEarnings", Amount: BigNumData, Seconds: number } | { Kind: "Info", Text: string }

-- Rede ---------------------------------------------------------------------

export type ArgSpec =
	{ Kind: "number", Min: number?, Max: number?, Integer: boolean? }
	| { Kind: "string", MaxLength: number, Pattern: string? }
	| { Kind: "boolean" }
	| { Kind: "enum", Values: { string } }

export type RateLimitSpec = {
	PerSecond: number, -- reposição de tokens por segundo
	Burst: number, -- capacidade máxima do bucket
}

export type RemoteDirection = "ClientToServer" | "ServerToClient"

export type RemoteDef = {
	Name: string,
	Direction: RemoteDirection,
	RateLimit: RateLimitSpec?, -- obrigatório na prática para ClientToServer
	Args: { ArgSpec }, -- validados no servidor (apenas ClientToServer)
}

return table.freeze({})
