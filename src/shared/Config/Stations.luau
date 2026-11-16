--!strict
--[[
	Config/Stations
	Postos à entrada de cada terreno (substituem os botões laterais): modelo, plataforma
	néon, título flutuante e ProximityPrompt que abre o painel correspondente.
	Só os postos do próprio terreno funcionam (o cliente esconde os prompts dos outros).
	Modelo: ServerStorage/Assets/Stations/<Id> (se existir) > adereço do Blender em
	Assets/Props/<Prop> > versão simples feita de peças.
]]

export type StationId = "Upgrades" | "Artists" | "Stages" | "WorldTour" | "Missions" | "Vip"

export type StationDef = {
	Id: StationId,
	Title: string,
	Icon: string,
	Hint: string, -- subtítulo por defeito
	Color: Color3,
	X: number, -- posição lateral no terreno (studs; negativo = esquerda de quem entra)
	Prop: string?, -- adereço do Blender (Assets/Props)
	PropHeight: number,
}

-- stylua: ignore
local LIST: { StationDef } = {
	{ Id = "Upgrades",  Title = "MELHORIAS",  Icon = "🛠️", Hint = "Melhora o teu som",      Color = Color3.fromRGB(255, 122, 48),  X = 22,  Prop = "Speaker_T2", PropHeight = 7 },
	{ Id = "Missions",  Title = "MISSÕES",    Icon = "📋", Hint = "Recompensas diárias",    Color = Color3.fromRGB(40, 190, 110),  X = 34,  Prop = nil,          PropHeight = 5 },
	{ Id = "WorldTour", Title = "WORLD TOUR", Icon = "🌍", Hint = "Discos de Platina",      Color = Color3.fromRGB(32, 160, 255),  X = 46,  Prop = nil,          PropHeight = 6 },
	{ Id = "Artists",   Title = "ARTISTAS",   Icon = "🎤", Hint = "Abre Vinyl Crates",      Color = Color3.fromRGB(140, 82, 255),  X = -22, Prop = "VinylCrate", PropHeight = 4 },
	{ Id = "Stages",    Title = "PALCOS",     Icon = "🎪", Hint = "Sobe de palco",          Color = Color3.fromRGB(240, 52, 150),  X = -34, Prop = "DJBooth",    PropHeight = 3.6 },
	{ Id = "Vip",       Title = "LOJA VIP",   Icon = "★",  Hint = "Robux",                  Color = Color3.fromRGB(255, 200, 60),  X = -46, Prop = nil,          PropHeight = 5 },
}

local ById: { [string]: StationDef } = {}
for _, def in LIST do
	table.freeze(def)
	ById[def.Id] = def
end

return table.freeze({
	Enabled = true,
	List = table.freeze(LIST),
	ById = table.freeze(ById),

	Depth = 12, -- profundidade a partir da frente do terreno (spawn a 14, público a partir de 20)
	PadSize = 9, -- diâmetro da plataforma néon
	TitleHeight = 4, -- studs acima do topo do modelo
	TitleSize = Vector2.new(11, 3.6), -- tamanho do título em studs
	TitleMaxDistance = 90,
	PromptDistance = 10,
	PromptName = "StationPrompt",
	BobHeight = 0.35, -- balanço do título (cliente)
	BobSeconds = 1.6,
})
