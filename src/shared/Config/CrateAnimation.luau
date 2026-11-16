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
	{ Name = "Storm",   Duration = 3.6 }, -- as nuvens fecham o céu; chuva e relâmpagos
	{ Name = "SkyOpen", Duration = 3.0 }, -- as nuvens abrem em redemoinho e volta o céu azul (sem sol)
	{ Name = "Rift",    Duration = 3.8 }, -- pancadas partem o céu e abre-se "outro mundo"
	{ Name = "Leap",    Duration = 1.4 }, -- a silhueta salta do rift até ao chão
	{ Name = "Impact",  Duration = 1.0 }, -- onda de choque, cratera, detritos, tremor
	{ Name = "Reveal",  Duration = 2.4 }, -- a silhueta ganha cor, nome e raridade
	{ Name = "End",     Duration = 0.8 }, -- fade e reposição da câmara/iluminação
}

-- Anéis do teto de nuvens: raio (studs) e nº de nuvens. O 1.º anel fecha o centro.
-- stylua: ignore
local CloudRings: { { Radius: number, Count: number } } = {
	{ Radius = 10,  Count = 4 },
	{ Radius = 36,  Count = 8 },
	{ Radius = 66,  Count = 12 },
	{ Radius = 100, Count = 16 },
	{ Radius = 138, Count = 20 },
	{ Radius = 178, Count = 24 },
	{ Radius = 222, Count = 28 }, -- até ao horizonte
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
	-- (Model com Root + Visual). Nomes: Cloud, Crater, Debris
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
		CloudColor = Color3.fromRGB(125, 125, 135), -- cinzento de tempestade (mais claro que preto)
		CloudCloseTime = 1.4, -- s, no início da Storm, para as nuvens fecharem o céu
		CloudCloseDistance = 170, -- de onde vêm as nuvens (studs para fora da posição final)
		-- Abertura: as nuvens de dentro vão para a borda de um círculo exato (buraco redondo
		-- e limpo, só com nuvens à volta); as de fora não mexem
		CloudOpenRadius = 72, -- raio do círculo de céu azul
		CloudRimLayer = 4, -- cada anel que chega à borda fica este nº de studs mais para fora
		CloudOpenRingDelay = 0.07, -- fração da abertura de atraso por anel (os de dentro abrem primeiro)
		CloudOpenSwirl = 2.5, -- o redemoinho acelera até (1 + isto)× a meio da abertura
		CeilingFadeTime = 0.6, -- s, no início da abertura, para o teto cinzento desaparecer
		CloudSpin = 0.12, -- rad/s
		CloudMistEvery = 2, -- 1 em cada N nuvens tem névoa de partículas (sem LowVfx)
		CloudScale = table.freeze({ Min = 1.3, Max = 1.9 }), -- tamanho de cada nuvem (aleatório)
		-- Teto contínuo por cima das nuvens (tapa os buracos entre elas): placas radiais
		-- que se afastam do centro com as nuvens
		Ceiling = table.freeze({
			Plates = 12,
			Length = 380,
			Width = 180,
			Thickness = 3,
			Lift = 12, -- acima do centro do teto de nuvens
			Color = Color3.fromRGB(110, 110, 120),
		}),
		-- Nuvens do próprio Roblox (Terrain.Clouds), só no cliente, repostas no fim
		TerrainClouds = table.freeze({ Cover = 1, Density = 0.8, Color = Color3.fromRGB(150, 150, 160) }),
		HideSun = true, -- Sky.CelestialBodiesShown = false durante toda a cinemática
		CameraHeight = 6, -- câmara acima do spawn do terreno
		-- Transição suave (s) para o plano de cada fase; 0 = corte seco
		CameraBlend = table.freeze({ Storm = 0, SkyOpen = 0.5, Rift = 0.8, Leap = 0.4, Impact = 0, Reveal = 0.7 }),
		HitZoom = 8, -- graus de FOV a menos em cada pancada (volta logo)
		OrbitRadius = 12, -- órbita na revelação
		OrbitSpeed = 0.35, -- rad/s
		-- Relâmpagos (s desde o início da fase Storm); alternam entre cair até ao chão e
		-- atravessar o teto de nuvens. Cada um pisca duas vezes.
		LightningTimes = table.freeze({ 1.5, 1.8, 2.15, 2.4, 2.75, 3.05, 3.35 }), -- depois de o céu fechar
		BoltPool = 4, -- relâmpagos que podem estar visíveis ao mesmo tempo
		BoltWidth = 0.9, -- núcleo branco
		BoltGlow = 3.5, -- brilho azulado à volta (múltiplo da largura do núcleo)
		BoltSegments = 10,
		BoltBranches = 3,
		BranchSegments = 4,
		BoltDrawTime = 0.08, -- s a "desenhar-se" de cima para baixo
		ThunderDelay = 0.35, -- trovão depois do flash
		RainRate = 400,
		RainRateLow = 120,
		-- Céu a partir (fase Rift): alguém do outro lado dá pancadas no céu. Cada pancada
		-- abre uma teia de rachas e arranca um pedaço: os fragmentos azuis caem e fica um
		-- buraco preto com "outro mundo" (estrelas + nebulosa). O buraco cresce a cada
		-- pancada; a última abre o centro, de onde sai o artista.
		Breach = table.freeze({
			Lift = 8, -- acima do centro do teto de nuvens
			Spread = 30, -- X/Y das pancadas multiplicam por isto (studs)
			-- Pancadas (s desde o início do Rift). X/Y: posição (-1..1), Size: tamanho.
			-- As primeiras são espaçadas (alguém a testar o céu) e o ritmo acelera até à última.
			Hits = table.freeze({
				table.freeze({ Time = 0.4, X = -0.35, Y = 0.2, Size = 0.5 }),
				table.freeze({ Time = 1.2, X = 0.4, Y = -0.1, Size = 0.55 }),
				table.freeze({ Time = 1.8, X = 0.05, Y = 0.45, Size = 0.6 }),
				table.freeze({ Time = 2.25, X = -0.2, Y = -0.4, Size = 0.65 }),
				table.freeze({ Time = 2.6, X = 0.5, Y = 0.3, Size = 0.7 }),
				table.freeze({ Time = 2.9, X = -0.55, Y = -0.05, Size = 0.75 }),
				table.freeze({ Time = 3.3, X = 0, Y = 0, Size = 1.3 }), -- a maior, no centro
			}),
			-- O céu da brecha é uma malha de triângulos irregulares (como vidro): as rachas
			-- seguem as arestas e cada triângulo que cai deixa o outro mundo no seu lugar
			GridRadius = 46, -- raio da zona que pode partir
			GridSpacing = 6.5, -- tamanho dos fragmentos
			GridSpacingLow = 9, -- com LowVfx (menos fragmentos)
			Jagged = 0.5, -- irregularidade da borda do buraco (0 = redondo)
			PatchRadius = 10, -- raio do que cai em cada pancada (× Size)
			PatchOpenTime = 0.35, -- s para os fragmentos caírem, do centro da pancada para fora
			CrackRadius = 18, -- até onde as rachas se espalham em cada pancada (× Size)
			CrackGrowTime = 0.2, -- s para as rachas se espalharem
			CrackColor = Color3.fromRGB(235, 245, 255),
			-- "Outro mundo": cada triângulo aberto tem uma destas cores (quase preto, roxo/azul)
			VoidColors = table.freeze({
				Color3.fromRGB(12, 4, 28),
				Color3.fromRGB(6, 6, 24),
				Color3.fromRGB(20, 6, 34),
				Color3.fromRGB(4, 2, 12),
			}),
			StarsEvery = 5, -- 1 em cada N triângulos abertos tem estrelas
			NebulaEvery = 14, -- 1 em cada N triângulos abertos tem nebulosa
			ShardSpeed = 30,
			ShardLifetime = 2.2,
			ShardColor = Color3.fromRGB(150, 190, 235), -- pedaços de céu azul
			-- Iluminação: cada pancada tem a sua luz e o seu feixe, no sítio onde o céu partiu
			HitLightFlare = 10, -- brilho quando os fragmentos caem
			HitLightGlow = 2.5, -- brilho que fica depois (+ um pouco por cada fragmento aberto)
			HitLightRange = 45,
			Beams = 7, -- feixes de luz a descer dos buracos (máx.)
			BeamLength = 110,
			WorldTint = Color3.fromRGB(110, 70, 170), -- a cena puxa para este tom enquanto o céu parte
		}),
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
		-- Os tempos (fecho, relâmpagos, olho, salto) vêm da Timeline acima: o artista salta
		-- ao mesmo tempo no ecrã do dono e no dos outros
		RevealHold = 3, -- s com o artista em cores antes de limpar
	}),
})

return CrateAnimation
