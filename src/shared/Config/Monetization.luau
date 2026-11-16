--!strict
--[[
	Config/Monetization
	Gamepasses e Developer Products. Os IDs ficam a 0 até serem criados no site do
	Roblox (com 0 o item aparece como "Em breve" e nunca é vendido).
	Os preços em Robux NÃO estão aqui: são lidos do Roblox (GetProductInfo).
	Nenhum item altera as probabilidades do gacha.
]]

local Types = require(script.Parent.Parent.Types)
local ArtistsConfig = require(script.Parent.Artists)

type GamepassDef = Types.GamepassDef
type ProductDef = Types.ProductDef

local Gamepasses: { GamepassDef } = {
	{
		Key = "VipStage",
		Name = "Palco VIP",
		Description = "+2 slots de artistas no palco (até 7).",
		Id = ArtistsConfig.VipGamepassId,
	},
	{
		Key = "AutoClicker",
		Name = "Auto-Play",
		Description = "No palco, acerta 70% das setas por ti (liga/desliga no botão AUTO).",
		Id = 0,
	},
	{
		Key = "DoubleHype",
		Name = "Hype ×2",
		Description = "Todo o teu Hype a dobrar, para sempre.",
		Id = 0,
	},
	{
		Key = "TourAgent",
		Name = "Agente de Tour",
		Description = "+25% de Discos de Platina em cada World Tour.",
		Id = 0,
	},
}

local Products: { ProductDef } = {
	{ Key = "HypeSmall", Name = "Pacote de Hype S", Description = "30 min do teu rendimento.", Id = 0, Reward = { IncomeMinutes = 30 } },
	{ Key = "HypeMedium", Name = "Pacote de Hype M", Description = "4 h do teu rendimento.", Id = 0, Reward = { IncomeMinutes = 240 } },
	{ Key = "HypeLarge", Name = "Pacote de Hype L", Description = "24 h do teu rendimento.", Id = 0, Reward = { IncomeMinutes = 1440 } },
	{ Key = "EnergyFill", Name = "Energia Cheia", Description = "Enche a barra do Bass Drop.", Id = 0, Reward = { FillEnergy = true } },
	{ Key = "CrateTen", Name = "Caixote x10", Description = "10 aberturas da melhor crate desbloqueada.", Id = 0, Reward = { Crates = 10 } },
	-- Caixas da sorte (Config/PaidCrates). Random = true: mostram probabilidades e escondem-se onde o Roblox proíbe
	{ Key = "StarCrate", Name = "🌟 Caixa Estrela", Description = "Melhor crate desbloqueada com sorte ×3 de Épico para cima.", Id = 0, Random = true, Reward = { PaidCrate = { Kind = "Star", Count = 1 } } },
	{ Key = "StarCrateTen", Name = "🌟 Caixa Estrela ×10", Description = "10 Caixas Estrela de uma vez.", Id = 0, Random = true, Reward = { PaidCrate = { Kind = "Star", Count = 10 } } },
	{ Key = "LegendaryCrate", Name = "👑 Caixa Lendária", Description = "Garante um artista Lendário ou melhor.", Id = 0, Random = true, Reward = { PaidCrate = { Kind = "Legendary", Count = 1 } } },
	{ Key = "MythicCrate", Name = "🔮 Caixa Mítica", Description = "Garante um artista Mítico ou melhor.", Id = 0, Random = true, Reward = { PaidCrate = { Kind = "Mythic", Count = 1 } } },
	{ Key = "LuckPotion", Name = "🍀 Poção da Sorte", Description = "30 min de sorte ×2 em todas as crates. Soma ao tempo que tiveres.", Id = 0, Random = true, Reward = { LuckMinutes = 30 } },
}
-- Preços sugeridos (definir no site do Roblox): Estrela 49 R$ · Estrela ×10 399 R$ ·
-- Lendária 199 R$ · Mítica 799 R$ · Poção da Sorte 99 R$

local GamepassByKey: { [string]: GamepassDef } = {}
for _, def in Gamepasses do
	GamepassByKey[def.Key] = table.freeze(def)
end
local ProductById: { [number]: ProductDef } = {}
for _, def in Products do
	if def.Id > 0 then
		assert(ProductById[def.Id] == nil, "Config/Monetization: id de produto repetido " .. def.Id)
		ProductById[def.Id] = def
	end
	table.freeze(def.Reward)
	table.freeze(def)
end

return table.freeze({
	Gamepasses = table.freeze(Gamepasses),
	GamepassByKey = table.freeze(GamepassByKey),
	Products = table.freeze(Products),
	ProductById = table.freeze(ProductById),

	DoubleHypeMultiplier = 2,
	TourAgentDiscBonus = 0.25,
	MaxStoredReceipts = 100,
})
