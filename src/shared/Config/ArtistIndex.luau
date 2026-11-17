--!strict
--[[
	Config/ArtistIndex
	Prémios do Índice de Artistas (Fase 10). Completar todas as combinações
	artista × raridade de uma raridade dá o prémio dessa raridade (reclamação única).
	Completar o Índice inteiro dá o prémio final.
	Crates = aberturas grátis da melhor crate desbloqueada (RewardService).
]]

local Types = require(script.Parent.Parent.Types)

type IndexReward = Types.IndexReward

-- stylua: ignore
local Rewards: { [string]: IndexReward } = {
	Common       = { Crates = 2,  Discs = 0 },
	Uncommon     = { Crates = 3,  Discs = 0 },
	Notable      = { Crates = 4,  Discs = 0 },
	Rare         = { Crates = 5,  Discs = 2 },
	Brilliant    = { Crates = 6,  Discs = 3 },
	Precious     = { Crates = 10, Discs = 10 },
	Epic         = { Crates = 6,  Discs = 5 },
	Heroic       = { Crates = 8,  Discs = 8 },
	Supreme      = { Crates = 10, Discs = 12 },
	Legendary    = { Crates = 15, Discs = 30 },
	Ancestral    = { Crates = 12, Discs = 25 },
	Immortal     = { Crates = 15, Discs = 35 },
	Mythic       = { Crates = 18, Discs = 50 },
	Divine       = { Crates = 25, Discs = 100 },
	Celestial    = { Crates = 20, Discs = 80 },
	Astral       = { Crates = 25, Discs = 110 },
	Cosmic       = { Crates = 30, Discs = 150 },
	Ethereal     = { Crates = 40, Discs = 250 },
	Primordial   = { Crates = 35, Discs = 220 },
	Infinite     = { Crates = 40, Discs = 300 },
	Transcendent = { Crates = 50, Discs = 400 },
	Omega        = { Crates = 75, Discs = 750 },
}

return table.freeze({
	Rewards = table.freeze(Rewards),
	FinalKey = "Final", -- chave do prémio final em Index.Claimed e no remote ClaimIndexReward
	Final = table.freeze({
		Discs = 1500,
		SlotBonus = 1, -- slot de artista permanente
		Title = "Lenda do Índice", -- mostrado na placa do terreno
	}),
	SyncInterval = 0.5, -- s entre sincronizações do Índice (agrupa várias descobertas)
})
