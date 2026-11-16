--!strict
--[[
	Config/Map
	Geometria do mapa único (studs). Centro do mapa na origem, chão a Y = 0.
	Cada terreno tem a frente (lado da praça) virada para o centro.
	Profundidades ("Depth") medem-se a partir da frente do terreno.
]]

local Map = table.freeze({
	Ground = table.freeze({
		Size = 600, -- 600 x 600, de -300 a +300
		Thickness = 4,
		Color = Color3.fromRGB(58, 92, 52),
	}),

	Boundary = table.freeze({
		Height = 60,
		Thickness = 2,
	}),

	Plaza = table.freeze({
		Radius = 100,
		RingOuterRadius = 120, -- anel de passeio entre a praça e os terrenos
		PathWidth = 12, -- marcação do caminho até cada terreno
		MonumentRadius = 12,
		CrateStationRadius = 55,
		CrateStationAngles = table.freeze({ 30, 150, 270 }), -- graus, entre os caminhos
		LeaderboardRadius = 80,
		LeaderboardAngles = table.freeze({ 90, 210 }),
	}),

	Plots = table.freeze({
		Count = 6,
		RingRadius = 180, -- distância do centro do mapa ao centro de cada terreno
		Width = 120,
		Depth = 120,
		BaseThickness = 0.5,
		CurbHeight = 1.5,
		CurbThickness = 1,
		EntranceWidth = 24,

		-- Zonas (profundidade a partir da frente)
		SignDepth = 4,
		SpawnDepth = 14,
		CrowdStart = 20,
		CrowdEnd = 64,
		StageFront = 68,
		StageBack = 116,

		-- Envelope máximo de um palco (Tier 12 ocupa-o exatamente)
		StageZone = table.freeze({ Width = 90, Depth = 48, Height = 100 }),
		WingWidth = 15,

		Colors = table.freeze({
			Color3.fromRGB(255, 60, 172),
			Color3.fromRGB(43, 210, 255),
			Color3.fromRGB(255, 209, 102),
			Color3.fromRGB(57, 217, 138),
			Color3.fromRGB(160, 120, 255),
			Color3.fromRGB(255, 120, 70),
		}),
	}),

	-- Botão "Voltar ao meu festival"
	ReturnButtonDistance = 90, -- aparece acima desta distância ao centro do terreno
	ReturnCooldown = 3, -- segundos entre teleportes (validado no servidor)
})

return Map
