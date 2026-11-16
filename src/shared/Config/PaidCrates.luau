--!strict
--[[
	Config/PaidCrates
	Caixas pagas com Robux (Developer Products em Config/Monetization) e Poção da Sorte.
	Todas abrem a MELHOR crate desbloqueada (o artista vem da família sorteada dessa crate)
	e contam para o pity como uma abertura normal.
	  Luck: multiplica o peso das raridades a partir de LuckFrom (renormalizado)
	  MinRarity: só sorteia desta raridade para cima (pesos normais entre elas)
	As probabilidades exatas são mostradas na loja (ArtistCalc.GetOdds) — obrigatório
	pelas regras do Roblox para itens aleatórios pagos; jogadores em países onde são
	proibidos (PolicyService.ArePaidRandomItemsRestricted) não veem estes produtos.
]]

export type PaidCrateKind = "Star" | "Legendary" | "Mythic"

export type PaidCrateDef = {
	Kind: PaidCrateKind,
	Name: string,
	Luck: number, -- 1 = sem sorte extra
	LuckFrom: string, -- raridade a partir da qual a sorte multiplica
	MinRarity: string?, -- garantia mínima
}

local KINDS: { [PaidCrateKind]: PaidCrateDef } = {
	Star = { Kind = "Star", Name = "Caixa Estrela", Luck = 3, LuckFrom = "Epic", MinRarity = nil },
	Legendary = { Kind = "Legendary", Name = "Caixa Lendária", Luck = 1, LuckFrom = "Epic", MinRarity = "Legendary" },
	Mythic = { Kind = "Mythic", Name = "Caixa Mítica", Luck = 1, LuckFrom = "Epic", MinRarity = "Mythic" },
}

for _, def in KINDS do
	table.freeze(def)
end

return table.freeze({
	Kinds = table.freeze(KINDS),

	-- Poção da Sorte: sorte nas crates normais (Hype e grátis) enquanto estiver ativa
	LuckPotion = table.freeze({
		Multiplier = 2,
		LuckFrom = "Epic",
		MaxMinutes = 24 * 60, -- teto do tempo acumulado
	}),
})
