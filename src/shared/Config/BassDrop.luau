--!strict
--[[
	Config/BassDrop
	Energia, ritmo, janela de timing e boost do Bass Drop.
	Ciclo: Charging -> BuildUp -> Window -> Boost -> Charging
]]

local Types = require(script.Parent.Parent.Types)

-- Avaliadas por ordem: a primeira cujo MaxOffset cobre |diferença| ganha.
-- "Late" só é alcançável depois do instante (a janela abre apenas WindowBefore antes).
local GRADES: { Types.GradeDef } = {
	{ Grade = "Perfect", Label = "PERFEITO!", MaxOffset = 0.10, Factor = 1.0 },
	{ Grade = "Great", Label = "ÓTIMO!", MaxOffset = 0.25, Factor = 0.8 },
	{ Grade = "Good", Label = "BOM", MaxOffset = 0.50, Factor = 0.6 },
	{ Grade = "Late", Label = "TARDE", MaxOffset = 1.00, Factor = 0.4 },
}

local BassDrop = table.freeze({
	BPM = 128,

	-- Energia
	MaxEnergy = 100,
	PassiveEnergyPerSecond = 1,
	EnergyPerClick = 0.4,

	-- Build-up e janela (segundos relativos ao instante do drop)
	BuildUpBeats = 8,
	WindowBefore = 0.5,
	WindowAfter = 1.0,
	Grades = table.freeze(GRADES),

	-- Resultado
	BoostDuration = 12,
	MissEnergyReset = 25,
	MinMultiplier = 5,
	MaxMultiplier = 50,

	-- Rede
	MaxLatencyCompensation = 0.25, -- desconto máximo de ping (s)
	SyncInterval = 0.2, -- envio de estado "sujo" ao cliente
})

return BassDrop
