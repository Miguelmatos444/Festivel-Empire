--!strict
--[[
	Config/Crystals
	Cristais (Fase 13B): moeda ganha ao fundir (manual e Auto-Fuse), por família da
	raridade do artista e estrelas que o resultado ganha. Mantêm-se no World Tour.
	Servem para o Estúdio de Remix (voltar a sortear o traço de um artista).
]]

-- Cristais ganhos por fusão: família -> { [estrelas do resultado] = quantidade }
-- stylua: ignore
local Fusion: { [string]: { [number]: number } } = {
	Common    = { [2] = 1,   [3] = 3 },
	Rare      = { [2] = 3,   [3] = 9 },
	Epic      = { [2] = 10,  [3] = 30 },
	Legendary = { [2] = 40,  [3] = 120 },
	Mythic    = { [2] = 150, [3] = 450 },
}

-- Custo de um Remix, pela família da raridade do artista
-- stylua: ignore
local RemixCost: { [string]: number } = {
	Common    = 5,
	Rare      = 12,
	Epic      = 30,
	Legendary = 75,
	Mythic    = 200,
}

for family, table_ in Fusion do
	table.freeze(table_)
	assert(RemixCost[family], "Config/Crystals: falta o custo de Remix de " .. family)
end

return table.freeze({
	Fusion = table.freeze(Fusion),
	RemixCost = table.freeze(RemixCost),

	-- Estúdio de Remix na praça (onde estava uma das plataformas antigas das crates)
	Studio = table.freeze({
		Angle = 150, -- graus (MapCalc.PlazaPoint)
		Radius = 55,
		PlatformRadius = 8,
		DiscHeight = 14, -- altura do disco holográfico
		DiscDiameter = 18,
		DiscSpin = 0.6, -- rad/s (rotação no cliente)
		PromptDistance = 14,
		PromptName = "RemixStudioPrompt", -- ProximityPrompt criado pelo TraitService; abre a RemixView
	}),
	ConfirmTime = 4, -- s para confirmar o Remix depois do primeiro clique
})
