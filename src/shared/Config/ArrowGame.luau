--!strict
--[[
	Config/ArrowGame
	Minijogo de setas no palco (Fase 9). Só balanceamento; a lógica está em
	ArrowCalc (partilhado) e ArrowGameService (servidor).

	Hype por acerto = Hype base por acerto (Microfone de Palco × Batida Forte × Batida de Ouro × global)
	                  × HitValue do tier × Factor da nota × multiplicador do combo
	                  × boost do Bass Drop
]]

local Types = require(script.Parent.Parent.Types)

type ArrowTierDef = Types.ArrowTierDef
type ArrowGradeDef = Types.ArrowGradeDef

-- stylua: ignore
local TIERS: { ArrowTierDef } = {
	{ Tier = 1,  SpawnInterval = 1.00, Lifetime = 2.2, MaxActive = 2, HitValue = 3.00 },
	{ Tier = 2,  SpawnInterval = 0.95, Lifetime = 2.1, MaxActive = 2, HitValue = 3.15 },
	{ Tier = 3,  SpawnInterval = 0.90, Lifetime = 2.0, MaxActive = 2, HitValue = 3.30 },
	{ Tier = 4,  SpawnInterval = 0.80, Lifetime = 1.9, MaxActive = 3, HitValue = 3.50 },
	{ Tier = 5,  SpawnInterval = 0.75, Lifetime = 1.8, MaxActive = 3, HitValue = 3.65 },
	{ Tier = 6,  SpawnInterval = 0.70, Lifetime = 1.7, MaxActive = 3, HitValue = 3.80 },
	{ Tier = 7,  SpawnInterval = 0.62, Lifetime = 1.6, MaxActive = 4, HitValue = 4.00 },
	{ Tier = 8,  SpawnInterval = 0.58, Lifetime = 1.5, MaxActive = 4, HitValue = 4.10 },
	{ Tier = 9,  SpawnInterval = 0.55, Lifetime = 1.4, MaxActive = 4, HitValue = 4.20 },
	{ Tier = 10, SpawnInterval = 0.50, Lifetime = 1.3, MaxActive = 5, HitValue = 4.30 },
	{ Tier = 11, SpawnInterval = 0.47, Lifetime = 1.2, MaxActive = 5, HitValue = 4.40 },
	{ Tier = 12, SpawnInterval = 0.45, Lifetime = 1.1, MaxActive = 5, HitValue = 4.50 },
}

-- Avaliadas por ordem: a primeira cujo MaxProgress cobre o progresso ganha.
-- Energia: com jogo perfeito ≈ 2 de energia/s em qualquer tier (2 × intervalo por acerto).
local GRADES: { ArrowGradeDef } = {
	{ Grade = "Perfect", Label = "PERFEITO!", MaxProgress = 0.6, Factor = 1.5, EnergyPerInterval = 2.0 },
	{ Grade = "Good", Label = "BOM", MaxProgress = 1.0, Factor = 1.0, EnergyPerInterval = 1.2 },
}

local DIRECTIONS: { Types.ArrowDirection } = { "Up", "Down", "Left", "Right" }

for index, def in TIERS do
	assert(def.Tier == index, "Config/ArrowGame: tiers têm de estar por ordem")
	assert(def.Lifetime > def.SpawnInterval, "Config/ArrowGame: Lifetime tem de ser maior que SpawnInterval")
	table.freeze(def)
end
for _, def in GRADES do
	table.freeze(def)
end

local ArrowGame = table.freeze({
	Tiers = table.freeze(TIERS),
	Grades = table.freeze(GRADES),
	Directions = table.freeze(DIRECTIONS),

	Combo = table.freeze({
		PerHit = 0.05, -- +5% por acerto seguido
		MaxMultiplier = 3, -- teto (atingido aos 40 acertos)
		MissionTarget = 40, -- missão "Faz um combo de 40"
	}),

	-- Servidor
	ScheduleInterval = 0.5, -- loop leve (agenda bolinhas + confirma a posição no palco)
	ScheduleAhead = 1.25, -- segundos de bolinhas agendadas de antemão (um envio por ciclo)
	SpawnLead = 0.3, -- 1.ª bolinha de um lote nunca nasce antes de agora + isto (latência)
	StartDelay = 1.0, -- pausa ao entrar no palco / depois do Bass Drop
	LatencyTolerance = 0.25, -- desconto máximo de ping no instante do acerto (s)
	EarlyTolerance = 0.15, -- acertos até isto antes do nascimento (desvio de relógio)
	PausedPhases = table.freeze({ "BuildUp", "Window" }), -- fases do Bass Drop sem setas

	-- Zona do palco (vista de cima, em studs, à volta da pegada do tier atual)
	StageMargin = 1.5, -- dos lados e atrás
	StageMinHeight = 4.5, -- altura mínima do HumanoidRootPart acima do chão do terreno (em pé no chão ≈ 3.5)
	StageMaxHeightExtra = 12, -- altura máxima acima do topo do palco (saltos)

	-- Gamepass Auto-Play (só no palco)
	AutoPlay = table.freeze({
		HitChance = 0.7,
		Grade = "Good" :: Types.ArrowGrade,
		ComboMultiplier = 1.5, -- fixo; não mexe no combo manual
	}),

	-- Cliente (apresentação)
	Client = table.freeze({
		BallSize = 104, -- píxeis de desenho (escalados pelo UIScale)
		MinBallScale = 0.25, -- tamanho no fim da vida
		SafeMargins = table.freeze({ Left = 150, Right = 240, Top = 170, Bottom = 40 }), -- sem tapar HUD/SideMenu/DropBar
		PoolSize = 8,
		PlacementAttempts = 8,
		PerformAnimationId = 507771019, -- dança R15 por defeito do Roblox (0 = sem animação)
		HitSoundId = 0,
		MissSoundId = 0,
		HitVolume = 0.6,
		MissVolume = 0.5,
	}),
})

return ArrowGame
