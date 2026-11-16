--!strict
--[[
	Config/DanceFloor
	Pista de dança de azulejos à frente do palco de cada terreno.
	O servidor (MapService) cria os azulejos; o cliente (DanceFloorController) anima as cores:
	  - fora do drop: néon suave, com uma onda de cor a cada batida
	  - build-up/janela: xadrez a piscar ao ritmo
	  - boost do Bass Drop: néon com uma onda que sai do palco para o público
	Cores pela era do palco do dono.
]]

local Types = require(script.Parent.Parent.Types)

local PALETTES: { [Types.EraName]: { Color3 } } = {
	Underground = {
		Color3.fromRGB(255, 170, 40),
		Color3.fromRGB(255, 110, 30),
		Color3.fromRGB(255, 205, 100),
	},
	["Ascensão"] = {
		Color3.fromRGB(255, 60, 172),
		Color3.fromRGB(150, 80, 255),
		Color3.fromRGB(255, 130, 220),
	},
	Estrelato = {
		Color3.fromRGB(255, 200, 60),
		Color3.fromRGB(255, 60, 70),
		Color3.fromRGB(255, 140, 50),
	},
	Lenda = {
		Color3.fromRGB(60, 230, 255),
		Color3.fromRGB(235, 245, 255),
		Color3.fromRGB(110, 170, 255),
	},
}

for _, palette in PALETTES do
	table.freeze(palette)
end

local DanceFloor = table.freeze({
	Enabled = true,

	-- Geometria (espaço do terreno; profundidade a partir da frente do terreno)
	Columns = 13,
	Rows = 6, -- linha 1 = encostada ao palco
	TileSize = 5, -- studs
	Gap = 0.15, -- junta entre azulejos
	Height = 0.2, -- espessura (o público sobe esta altura)
	StageGap = 0, -- distância entre a última linha e a frente do palco (Map.Plots.StageFront)
	BaseColor = Color3.fromRGB(18, 14, 28), -- base escura por baixo dos azulejos

	Palettes = table.freeze(PALETTES),

	-- Os azulejos são sempre Neon (têm luz própria; em plástico ficavam pretos ao fim da tarde).
	-- Brilho: Dim = quanto a cor escurece (0 = cor total, 1 = preto). Neon escuro quase não brilha.
	IdleDim = 0.45,
	IdlePulse = 0.2, -- quanto aclara com o pulso da batida
	BuildUpOnDim = 0.1,
	BuildUpOffDim = 0.7,
	BoostOnDim = 0,
	BoostOffDim = 0.4,
	BoostWaveLength = 3, -- linhas entre ondas no boost
	OtherBoostSeconds = 12, -- duração assumida do boost dos outros jogadores
})

return DanceFloor
