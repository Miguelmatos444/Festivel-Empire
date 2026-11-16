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
	Id: string, -- id do artista (Config/Artists)
	Rarity: string, -- id da raridade (Config/Rarities)
	Stars: number, -- 1★ base, 2★ Remix, 3★ Platinum
	Locked: boolean, -- protegido contra fusão e Auto-Delete
}

-- Aberturas desde a última raridade >= ao patamar (Config/Rarities.PityLadder)
export type PityData = {
	Legendary: number,
	Mythic: number,
	Divine: number,
	Cosmic: number,
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
	AutoFuse: boolean,
	AutoDeleteUpTo: number, -- 0 = desligado; N = apaga as raridades 1..N ao saírem
}

export type ProfileData = {
	DataVersion: number,
	Hype: BigNumData,
	TotalHypeEarned: BigNumData, -- de sempre (estatística; nunca reinicia)
	RunHypeEarned: BigNumData, -- desde o último World Tour (base dos Discos de Platina)
	PlatinumDiscs: number, -- por gastar
	TotalDiscsEarned: number,
	WorldTours: number,
	StageTier: number,
	Equipment: { [string]: number }, -- id do equipamento -> nível
	Artists: { [string]: ArtistData }, -- uid -> artista
	EquippedArtists: { string }, -- uids nos slots do palco
	NextArtistUid: number,
	Pity: PityData,
	SkillTree: { [string]: number }, -- id do nó -> nível
	Stats: StatsData,
	Settings: SettingsData,
	Pyro: { [string]: boolean }, -- máquinas de pirotecnia desbloqueadas
	LastOnline: number, -- os.time() do último save
	-- Retenção / monetização
	Daily: DailyData,
	Missions: MissionsData,
	RedeemedCodes: { [string]: boolean },
	Badges: { [string]: boolean },
	Receipts: { string }, -- últimos PurchaseId processados (idempotência)
	AutoClick: boolean,
	-- Social
	Social: SocialData,
}

-- Social / Ambiente ------------------------------------------------------------------

export type SocialData = {
	LikesReceived: number, -- Likes recebidos de sempre (bónus de Hype)
	LikesGivenDay: number, -- dia UTC (RetentionCalc.GetDayIndex) a que LikedToday se refere
	LikedToday: { [string]: boolean }, -- UserId (string) dos festivais com Like dado hoje
}

export type SocialSync = {
	Friends: number, -- amigos no servidor (contam até Config/Social.Friends.MaxFriends)
	InGroup: boolean,
	LikesReceived: number,
	LikedToday: { [string]: boolean },
	GivenToday: number,
	Multiplier: number, -- multiplicador social atual (inclui o Headliner)
}

export type HeadlinerState = {
	Active: boolean,
	StartsAt: number, -- hora do servidor (Unix) do início do evento atual ou do próximo
	EndsAt: number,
}

export type DanceStyle = "Sway" | "Jump" | "Headbang" | "Spin"

-- Monetização / Retenção ---------------------------------------------------------

export type RewardDef = {
	IncomeMinutes: number?, -- minutos de rendimento passivo atual (com mínimo garantido)
	Discs: number?, -- Discos de Platina
	Crates: number?, -- aberturas grátis da melhor crate desbloqueada
	FillEnergy: boolean?, -- barra do Bass Drop cheia
}

export type DailyData = {
	Streak: number, -- último dia reclamado (0..7)
	LastClaim: number, -- os.time() da última reclamação (0 = nunca)
}

export type DailyStatus = {
	CanClaim: boolean,
	NextDay: number, -- dia (1..7) que a próxima reclamação dá
	SecondsUntilClaim: number,
	StreakLost: boolean,
}

export type MissionMetric =
	"Clicks"
	| "BassDrops"
	| "PerfectDrops"
	| "EquipmentLevels"
	| "CratesOpened"
	| "PlayMinutes"
	| "Fusions"
	| "StagesBought"
	| "WorldTours"

export type MissionDef = {
	Id: string,
	Name: string,
	Description: string,
	Metric: MissionMetric,
	Target: number,
	Reward: RewardDef,
}

export type MissionData = {
	Id: string,
	Progress: number,
	Claimed: boolean,
}

export type MissionsData = {
	DayIndex: number,
	WeekIndex: number,
	Daily: { MissionData },
	Weekly: { MissionData },
}

export type RetentionSync = {
	Daily: DailyData,
	Missions: MissionsData,
	Gamepasses: { [string]: boolean },
	AutoClick: boolean,
}

export type CodeDef = {
	Code: string,
	Reward: RewardDef,
	ExpiresAt: number?, -- os.time() UTC; nil = não expira
	MaxUses: number?, -- limite global; nil = ilimitado
	MinTier: number?,
}

export type GamepassDef = {
	Key: string,
	Name: string,
	Description: string,
	Id: number,
}

export type ProductDef = {
	Key: string,
	Name: string,
	Description: string,
	Id: number,
	Reward: RewardDef,
}

export type BadgeDef = {
	Key: string,
	Name: string,
	BadgeId: number,
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
	WindowBonus: number, -- segundos extra na janela (habilidades dos artistas)
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
	SavedBy: string?, -- nome do artista que fez o drop pelo jogador (Salva-Drop)
}

-- Artistas / Gacha ----------------------------------------------------------------

export type RarityFamily = "Common" | "Rare" | "Epic" | "Legendary" | "Mythic"
export type RarityEffect = "None" | "Glow" | "Gradient" | "Rainbow"

export type RarityDef = {
	Id: string,
	Name: string,
	Family: RarityFamily,
	Weight: number, -- probabilidade em % (todas somam 100)
	Bonus: number, -- bónus de Hype base a 1★ (0.10 = +10%)
	AbilityScale: number, -- força da habilidade do artista
	Duet: boolean, -- junta a habilidade do artista Lendário da mesma crate
	Aura: number, -- +X ao bónus de todos os OUTROS artistas equipados
	OmegaSave: boolean, -- Salva-Drop com nota PERFEITO
	Color: Color3,
	Effect: RarityEffect,
}

export type AbilityKind =
	"ClickPower"
	| "Energy"
	| "WindowWiden"
	| "BoostExtend"
	| "CooldownCut"
	| "AutoPyro"
	| "SaveDrop"
	| "FullShow"
	| "Aura"

export type AbilityDef = {
	Kind: AbilityKind,
	Value: number?, -- fração (ClickPower/Energy/CooldownCut/Aura) ou segundos (WindowWiden/BoostExtend)
	Machine: string?, -- AutoPyro
	Grade: DropGrade?, -- SaveDrop
	Cooldown: number?, -- SaveDrop (segundos)
}

export type ArtistDef = {
	Id: string,
	Name: string,
	Crate: string,
	Family: RarityFamily,
	Ability: AbilityDef?,
}

export type CrateDef = {
	Id: string,
	Name: string,
	Era: string,
	RequiredTier: number,
	Cost: number,
	EraFactor: number,
}

export type PityLevel = {
	Key: string, -- campo em PityData
	Threshold: number,
	MinRarity: string,
	Label: string,
}

export type SaveDropEffect = {
	Uid: string,
	Name: string,
	Grade: DropGrade,
	Cooldown: number,
}

-- Efeito agregado dos artistas equipados (já com limites aplicados)
export type ArtistEffects = {
	HypeMultiplier: number,
	ClickBonus: number,
	EnergyBonus: number,
	WindowBonus: number,
	BoostBonus: number,
	CooldownCut: number,
	AutoPyroMask: number,
	FullShow: boolean,
	SaveDrops: { SaveDropEffect },
}

export type ArtistsSync = {
	Artists: { [string]: ArtistData },
	Equipped: { string },
	Slots: number,
	Pity: PityData,
	AutoFuse: boolean,
	AutoDeleteUpTo: number,
	Effects: ArtistEffects,
}

export type CrateOutcome = "New" | "Deleted" | "Fused"

export type CrateItem = {
	ArtistId: string,
	Rarity: string,
	Uid: string?,
	Outcome: CrateOutcome,
}

export type CrateResult = {
	CrateId: string,
	Items: { CrateItem },
}

-- Mapa / Palcos ----------------------------------------------------------------

export type EraName = "Underground" | "Ascensão" | "Estrelato" | "Lenda"

export type StageDef = {
	Tier: number,
	Name: string,
	Era: EraName,
	Cost: number, -- Hype para comprar este tier (0 = inicial)
	Width: number, -- X (studs)
	Depth: number, -- Z, cresce para trás a partir da frente do palco
	Height: number, -- Y
	RequiredWorldTours: number,
}

-- Estado de um tier do ponto de vista do jogador
export type StageStatus = "Current" | "Owned" | "Available" | "NeedPrevious" | "NeedWorldTours"

export type TransitionTiming = {
	Dismantle: number, -- segundos a desmontar o palco antigo
	Pause: number, -- intervalo (troca de era: pirotecnia)
	Build: number, -- segundos a montar o palco novo
}

-- Replicação servidor -> cliente ------------------------------------------

export type PlayerStateSnapshot = {
	Hype: BigNumData,
	TotalHypeEarned: BigNumData,
	RunHypeEarned: BigNumData,
	HypePerClick: BigNumData,
	HypePerSecond: BigNumData,
	PlatinumDiscs: number,
	WorldTours: number,
	StageTier: number,
	Clicks: number,
	Equipment: { [string]: number },
	SkillTree: { [string]: number },
}

export type StateDelta = {
	Hype: BigNumData?,
	TotalHypeEarned: BigNumData?,
	RunHypeEarned: BigNumData?,
	HypePerClick: BigNumData?,
	HypePerSecond: BigNumData?,
	PlatinumDiscs: number?,
	WorldTours: number?,
	StageTier: number?,
	Clicks: number?,
	Equipment: { [string]: number }?, -- apenas as entradas alteradas
	SkillTree: { [string]: number }?, -- árvore completa quando muda
}

-- Prestige / World Tour --------------------------------------------------------

export type SkillBranch = "Sound" | "Recovery" | "Pyro" | "Discs"

export type SkillEffectKey =
	"HypeMultiplier"
	| "ClickMultiplier"
	| "OfflineEfficiency"
	| "ArtistBonus"
	| "StartingHype"
	| "StartingGenerators"
	| "StartTier"
	| "StageCostCut"
	| "StartEnergy"
	| "BoostBonus"
	| "WindowBonus"
	| "CooldownCut"
	| "DiscBonus"
	| "CrateCostCut"
	| "PityReduction"

export type SkillNodeDef = {
	Id: string,
	Name: string,
	Branch: SkillBranch,
	Row: number, -- posição no ramo (1 = topo)
	Effect: SkillEffectKey,
	PerLevel: number, -- valor do efeito por nível
	MaxLevel: number,
	BaseCost: number, -- Discos de Platina
	CostGrowth: number,
	Requires: string?, -- id do nó exigido
	RequiresLevel: number?,
}

-- Efeitos agregados da árvore (valores já multiplicados pelo nível)
export type SkillEffects = {
	HypeMultiplier: number,
	ClickMultiplier: number,
	OfflineEfficiency: number,
	ArtistBonus: number,
	StartingHype: number,
	StartingGenerators: number,
	StartTier: number,
	StageCostCut: number,
	StartEnergy: number,
	BoostBonus: number,
	WindowBonus: number,
	CooldownCut: number,
	DiscBonus: number,
	CrateCostCut: number,
	PityReduction: number,
}

export type SkillNodeStatus = "Maxed" | "Available" | "Locked" | "TooExpensive"

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
