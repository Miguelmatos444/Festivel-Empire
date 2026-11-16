--!strict
--[[
	Config/Leaderboards
	Dois rankings globais (OrderedDataStore) mostrados nos painéis da praça.
	Hype guardado como floor(log10(Hype) * 1000) (o Hype ultrapassa os inteiros do DataStore).
	World Tours guardados como WorldTours * 1e9 + Discos totais (empate pelos Discos).
]]

return table.freeze({
	Boards = table.freeze({
		table.freeze({ Key = "Hype", Title = "HYPE DE SEMPRE", Store = "FestivalEmpire_LB_Hype", Slot = 1 }),
		table.freeze({ Key = "Tours", Title = "WORLD TOURS", Store = "FestivalEmpire_LB_Tours", Slot = 2 }),
	}),
	TopCount = 10,
	SubmitInterval = 120, -- segundos entre envios por jogador
	RefreshInterval = 60, -- segundos entre atualizações dos painéis
	HypeScale = 1000,
	DiscsCap = 999999999,
})
