--!strict
--[[
	Config/Economy
	Balanceamento base da economia. Nenhuma lógica aqui.
]]

local Economy = table.freeze({
	-- Intervalo do tick económico do servidor (segundos). 1 Hz por regra do projeto.
	TickInterval = 1,

	-- Intervalo de envio de deltas de estado para clientes "sujos" (segundos).
	ReplicationInterval = 0.2,

	-- Valores iniciais / base
	StartingHype = 0,
	BaseHypePerClick = 1,
	BasePassiveHypePerSecond = 0, -- sobe com equipamento/DJs/artistas nas fases seguintes

	-- Rendimento offline
	Offline = table.freeze({
		MaxSeconds = 8 * 60 * 60, -- teto de 8 horas
		Efficiency = 0.5, -- 50% do rendimento passivo
		MinSecondsToReport = 60, -- ausências mais curtas são ignoradas
	}),

	-- Limites permitidos para GrowthRate em BaseCost * GrowthRate ^ Level
	GrowthRate = table.freeze({
		Min = 1.07,
		Max = 1.15,
	}),

	-- Anti-autoclicker: batidas acima disto são descartadas no servidor
	Click = table.freeze({
		MaxCPS = 15, -- batidas por segundo sustentadas
		Burst = 20, -- tolerância para rajadas curtas / latência
	}),

	-- Compras de equipamento
	Purchase = table.freeze({
		MaxLevelsPerPurchase = 10000,
		RequestsPerSecond = 8,
		RequestBurst = 12,
	}),

	-- Marcos: produção do equipamento x Multiplier em cada marco atingido
	Milestones = table.freeze({
		Levels = table.freeze({ 10, 25, 50, 100, 150, 200 }),
		RepeatEvery = 100, -- depois do último: 300, 400, 500...
		Multiplier = 2,
	}),
})

return Economy
