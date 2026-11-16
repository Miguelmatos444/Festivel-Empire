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
		Name = "Auto-Batida",
		Description = "O servidor dá 5 batidas por segundo por ti (liga/desliga no botão AUTO).",
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
}

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

	AutoClicksPerSecond = 5, -- abaixo do limite de 15/s das batidas manuais
	DoubleHypeMultiplier = 2,
	TourAgentDiscBonus = 0.25,
	MaxStoredReceipts = 100,
})
