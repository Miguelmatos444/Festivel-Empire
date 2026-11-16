--!strict
--[[
	Config/CrateAnimation
	Apresentação da abertura das Vinyl Crates (Fase 12). Só visual: o resultado é
	sempre sorteado e entregue pelo servidor ANTES de qualquer animação começar.

	  - Roleta (x1): faixa de cartas que para no artista ganho debaixo do marcador
	  - Grelha (x10): 10 cartas reveladas em sequência, as mais raras no fim
	  - Carta mistério: raridades com probabilidade na crate <= MysteryThreshold e
	    índice >= MysteryMinRarity aparecem como silhueta + "???" e disparam a cinemática
	  - Cinemática do ultra-raro: timeline em fases (tempos em segundos)
]]

local Types = require(script.Parent.Parent.Types)

type CinematicPhase = Types.CinematicPhase

-- Timeline completa da cinemática (ordem = ordem de execução)
-- stylua: ignore
local Timeline: { CinematicPhase } = {
	{ Name = "Fade",    Duration = 0.6 }, -- ecrã a preto, a música corta
	{ Name = "Storm",   Duration = 3.0 }, -- céu todo coberto, chuva, relâmpagos bem à vista
	{ Name = "SkyOpen", Duration = 1.6 }, -- as nuvens abrem em círculo, raios dourados
	{ Name = "Rift",    Duration = 2.0 }, -- o céu racha (rachas a crescer) e estilhaça
	{ Name = "Leap",    Duration = 1.4 }, -- a silhueta salta do rift até ao chão
	{ Name = "Impact",  Duration = 1.0 }, -- onda de choque, cratera, detritos, tremor
	{ Name = "Reveal",  Duration = 2.4 }, -- a silhueta ganha cor, nome e raridade
	{ Name = "End",     Duration = 0.8 }, -- fade e reposição da câmara/iluminação
}

-- Anéis do teto de nuvens: raio (studs) e nº de nuvens. O 1.º anel fecha o centro.
-- stylua: ignore
local CloudRings: { { Radius: number, Count: number } } = {
	{ Radius = 10,  Count = 3 },
	{ Radius = 34,  Count = 7 },
	{ Radius = 60,  Count = 11 },
	{ Radius = 90,  Count = 15 },
	{ Radius = 122, Count = 19 },
	{ Radius = 156, Count = 23 },
}

-- Efeito ao parar a roleta / revelar a carta, por família da raridade
local StopEffects: { [string]: Types.CrateStopEffect } = {
	Common = "Simple",
	Rare = "Glow",
	Epic = "Glow",
	Legendary = "Flash",
	Mythic = "Flash",
}

local CrateAnimation = table.freeze({
	-- Carta mistério --------------------------------------------------------------
	MysteryThreshold = 0.01, -- probabilidade NA CRATE (0..1) igual ou inferior a isto…
	MysteryMinRarity = "Divine", -- …e raridade igual ou acima desta (Divino, Etéreo, Ómega)
	MysteryPause = 1, -- s com o "???" a pulsar antes da cinemática

	-- Pasta em ReplicatedStorage com os modelos dos artistas (copiados pelo GachaService)
	ArtistRigsFolder = "ArtistRigs",
	-- Overrides opcionais dos efeitos: ReplicatedStorage/Assets/Cinematics/<Nome>
	-- (Model com Root + Visual). Nomes: Cloud, SkyShard, Crater, Debris
	CinematicAssetsPath = table.freeze({ "Assets", "Cinematics" }),

	-- Roleta (x1) -----------------------------------------------------------------
	Roulette = table.freeze({
		CardCount = 40, -- cartas na faixa (pool fixa)
		WinnerIndex = 34, -- posição da carta ganha na faixa
		StartIndex = 3, -- carta debaixo do marcador quando começa
		CardWidth = 130,
		CardHeight = 176,
		CardGap = 10,
		Duration = 5, -- s até parar
		FastDuration = 1.5, -- com "Animação rápida"
		SlowMotionExtra = 1.5, -- s extra de abrandamento quando para num Lendário/Mítico
		StopJitter = 0.3, -- desvio aleatório do ponto de paragem (fração da largura da carta)
		EasingPower = 5, -- 1 - (1 - t)^p  (5 = Quint Out)
	}),

	-- Grelha (x10) -----------------------------------------------------------------
	Grid = table.freeze({
		StartDelay = 0.3,
		RevealStep = 0.25, -- s entre cartas
		FastRevealStep = 0.08,
		FlipTime = 0.18,
	}),

	-- Efeitos ao parar, por família da raridade
	StopEffects = table.freeze(StopEffects),
	ConfettiCount = 36,
	ConfettiCountLow = 12,

	-- Cinemática ---------------------------------------------------------------------
	Timeline = table.freeze(Timeline),
	FastPhases = table.freeze({ "Fade", "Impact", "Reveal", "End" }), -- "Animação rápida"
	SkipToPhase = "Reveal", -- o botão "Saltar" vai direto para aqui
	SkipFromView = 2, -- "Saltar" disponível a partir da 2.ª cinemática do jogador
	ProtectionMargin = 2, -- s extra de ForceField depois da duração prevista

	Cinematic = table.freeze({
		SkyHeight = 120, -- altura do teto de nuvens acima do ponto de aterragem
		-- Teto de nuvens em anéis à volta do centro do céu (cobre tudo o que a câmara vê)
		CloudRings = table.freeze(CloudRings),
		CloudRingsLow = 4, -- com LowVfx só os primeiros N anéis
		CloudOpenDistance = 75, -- quanto cada nuvem se afasta do centro quando o céu abre
		CloudSpin = 0.12, -- rad/s
		CloudMistEvery = 3, -- 1 em cada N nuvens tem névoa de partículas (sem LowVfx)
		CloudInnerRadius = 18, -- versão leve (outros jogadores): anel fechado…
		CloudOpenRadius = 110, -- …e aberto
		-- Nuvens do próprio Roblox (Terrain.Clouds), só no cliente, repostas no fim
		TerrainClouds = table.freeze({ Cover = 1, Density = 0.85, Color = Color3.fromRGB(45, 45, 56) }),
		CameraHeight = 6, -- câmara acima do spawn do terreno
		OrbitRadius = 12, -- órbita na revelação
		OrbitSpeed = 0.35, -- rad/s
		-- Relâmpagos (s desde o início da fase Storm); alternam entre cair até ao chão e
		-- atravessar o teto de nuvens. Cada um pisca duas vezes.
		LightningTimes = table.freeze({ 0.25, 0.7, 1.15, 1.6, 2.05, 2.5 }),
		BoltPool = 3, -- relâmpagos que podem estar visíveis ao mesmo tempo
		BoltWidth = 1.4,
		BoltBranches = 2,
		ThunderDelay = 0.35, -- trovão depois do flash
		RainRate = 400,
		RainRateLow = 120,
		-- Céu a rachar (fase Rift)
		PaneRadius = 40, -- "janela" de céu que racha, por cima do buraco nas nuvens
		PaneLift = 8, -- acima do teto de nuvens
		CrackLines = 7,
		CrackLinesLow = 4,
		CrackSegments = 5,
		CrackGrowTime = 1.3, -- s até as rachas chegarem à borda; depois estilhaça
		ShardCount = 18,
		ShardCountLow = 8,
		ShardSpeed = 55,
		ShakeRift = 0.15, -- studs
		ShakeImpact = 1.2,
		ShakeImpactTime = 0.5,
		FovStart = 70,
		FovLeap = 50,
		FovReveal = 60,
		DebrisCount = 12,
		DebrisCountLow = 4,
		CrackCount = 6,
		CraterRadius = 9,
		DustBurst = 80,
		DustBurstLow = 25,
		ColorTweenTime = 1.2, -- silhueta -> cores reais
	}),

	-- Versão leve vista pelos outros jogadores (sem câmara nem iluminação)
	Light = table.freeze({
		SkyHeight = 80,
		CloudRings = 3, -- primeiros N anéis do teto de nuvens
		-- Igual à versão completa (Fade + Storm + SkyOpen + Rift): o artista salta ao mesmo
		-- tempo no ecrã do dono e no dos outros
		LeapStart = 7.2, -- s desde o início até a silhueta saltar
		LeapDuration = 1.4,
		RevealHold = 3, -- s com o artista em cores antes de limpar
	}),
})

return CrateAnimation
