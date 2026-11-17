--!strict
--[[
	Config/Showcase
	Vitrine (Fase 10): pedestal à frente de cada terreno com um artista do dono.
	Posição relativa à frente do terreno (Config/Map.Plots), entre a placa e o spawn,
	afastada para o lado para não tapar a entrada. Distâncias de LOD em Config/Lod.
]]

return table.freeze({
	OffsetX = -26, -- studs para o lado (0 = centro da entrada)
	Depth = 9, -- profundidade a partir da frente do terreno
	PedestalHeight = 3, -- topo do pedestal (o artista fica em cima)
	SpinSpeed = 0.6, -- rad/s (rotação do artista no cliente)
	BobHeight = 0.35, -- studs de flutuação
	BobSpeed = 1.6, -- rad/s
	DefaultMode = "Auto",
})
