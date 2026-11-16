--!strict
--[[
	SortImports.luau — correr no Command Bar do Roblox Studio (modo Edit, com o rojo serve ligado)
	DEPOIS de importar os FBX para o Workspace (Import 3D aceita vários ficheiros de uma vez).

	Move cada modelo importado (nome = nome do ficheiro FBX) para a pasta certa de
	ServerStorage/Assets. Se já existir um modelo com o mesmo nome no destino (ex.: um
	placeholder), o antigo NÃO é apagado: vai para ServerStorage/Assets_Antigos.
	Modelos com nomes desconhecidos ficam no Workspace e aparecem na lista no Output.

	A seguir: correr Models/StudioSetup.luau e gravar o place.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 5)
assert(Shared, "Falta ReplicatedStorage.Shared — liga o rojo serve primeiro")
local Config = Shared:WaitForChild("Config")
local ArtistsConfig = require(Config:WaitForChild("Artists")) :: any
local RaritiesConfig = require(Config:WaitForChild("Rarities")) :: any
local PyroConfig = require(Config:WaitForChild("Pyro")) :: any
local DressingConfig = require(Config:WaitForChild("Dressing")) :: any

local function folder(parent: Instance, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	return created
end

local assets = folder(ServerStorage, "Assets")

-- nome do modelo -> pasta de destino
local destinations: { [string]: Instance } = {}

for tier = 1, 12 do
	destinations[string.format("Tier_%02d", tier)] = folder(assets, "Stages")
end
destinations.Plaza = assets
destinations.PlotSign = assets
destinations.PlazaDecor = assets
for _, era in { "Underground", "Ascensão", "Estrelato", "Lenda" } do
	destinations[era] = folder(assets, "Decor")
end
destinations.Arch = folder(assets, "Prestige")
for _, def in ArtistsConfig.List do
	destinations[def.Id] = folder(assets, "Artists")
end
for _, def in RaritiesConfig.List do
	destinations[def.Id] = folder(assets, "RarityKits")
end

local props = folder(assets, "Props")
for _, def in PyroConfig.List do
	destinations[def.Id] = props
end
for _, name in DressingConfig.Stage.SpeakerByEra do
	destinations[name] = props
end
destinations[DressingConfig.Stage.DJBooth.Name] = props
for _, entry in { "FoodTruck", "EntranceArch", "FerrisWheel", "VinylCrate" } do
	destinations[DressingConfig.Plaza[entry].Name] = props
end

local moved, replaced = 0, 0
local unknown: { string } = {}
local backup: Instance? = nil

for _, child in Workspace:GetChildren() do
	if child:IsA("Model") and child.Name ~= "Map" then
		local target = destinations[child.Name]
		if target then
			local previous = target:FindFirstChild(child.Name)
			if previous then
				local backupFolder = backup or folder(ServerStorage, "Assets_Antigos")
				backup = backupFolder
				previous.Parent = folder(backupFolder, target.Name)
				replaced += 1
			end
			child.Parent = target
			moved += 1
			print(string.format("[SortImports] %s -> %s", child.Name, target:GetFullName()))
		elseif child:FindFirstChildWhichIsA("MeshPart", true) then
			table.insert(unknown, child.Name)
		end
	end
end

print(string.format("[SortImports] %d modelos arrumados (%d antigos guardados em ServerStorage/Assets_Antigos).", moved, replaced))
if #unknown > 0 then
	warn("[SortImports] Nomes desconhecidos (ficaram no Workspace): " .. table.concat(unknown, ", "))
end
print("[SortImports] Agora corre Models/StudioSetup.luau e grava o place.")
