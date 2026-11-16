--!strict
--[[
	CheckAssets.luau — correr no Command Bar do Roblox Studio (modo Edit, com o rojo serve ligado).
	Só lê: não move nem altera nada. Verifica ServerStorage/Assets e escreve no Output:
	  ✓ modelos do Blender no sítio certo
	  ~ ainda é o placeholder
	  ✗ em falta / mal preparado (sem Root, HeadAnchor, KitOrigin, Attachments…)
	No fim mostra um resumo e os modelos que ainda estão soltos no Workspace.
	Copia o Output e envia-o ao Claude se quiseres que ele analise.
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

local ok, placeholder, missing = 0, 0, 0
local lines: { string } = {}

local function report(symbol: string, path: string, note: string?)
	if symbol == "✓" then
		ok += 1
	elseif symbol == "~" then
		placeholder += 1
	else
		missing += 1
	end
	table.insert(lines, string.format("%s %s%s", symbol, path, if note then "  — " .. note else ""))
end

local function find(path: { string }): Instance?
	local current: Instance? = ServerStorage:FindFirstChild("Assets")
	for _, name in path do
		if not current then
			return nil
		end
		current = current:FindFirstChild(name)
	end
	return current
end

local function isPlaceholder(model: Instance): boolean
	if model:GetAttribute("Placeholder") == true then
		return true
	end
	-- Placeholders do código têm Parts simples e nenhuma MeshPart
	return model:FindFirstChildWhichIsA("MeshPart", true) == nil
end

local function hasPart(model: Instance, name: string): boolean
	local part = model:FindFirstChild(name, true)
	return part ~= nil and part:IsA("BasePart")
end

-- Verifica um modelo; `extra` devolve um problema (string) ou nil
local function check(path: { string }, extra: ((Model) -> string?)?)
	local label = "Assets/" .. table.concat(path, "/")
	local instance = find(path)
	if not instance then
		report("✗", label, "em falta")
		return
	end
	if not instance:IsA("Model") then
		report("✗", label, "não é um Model (é " .. instance.ClassName .. ")")
		return
	end
	if isPlaceholder(instance) then
		report("~", label, "ainda é o placeholder")
		return
	end
	local problem = if extra then extra(instance) else nil
	if problem then
		report("✗", label, problem)
	else
		report("✓", label)
	end
end

local function needsRoot(model: Model): string?
	if not hasPart(model, "Root") then
		return "sem peça 'Root'"
	end
	if model.PrimaryPart == nil then
		return "sem PrimaryPart (corre Models/StudioSetup.luau)"
	end
	return nil
end

local STAGE_ATTACHMENTS = { "StageOrigin", "DJBooth", "Artist_1", "Artist_7", "Pyro_ColdSparks_1", "Speaker_L", "CameraFocus" }

table.insert(lines, "=== Palcos ===")
for tier = 1, 12 do
	check({ "Stages", string.format("Tier_%02d", tier) }, function(model: Model): string?
		local problem = needsRoot(model)
		if problem then
			return problem
		end
		local root = model:FindFirstChild("Root", true) :: Instance
		local absent: { string } = {}
		for _, name in STAGE_ATTACHMENTS do
			if not root:FindFirstChild(name) then
				table.insert(absent, name)
			end
		end
		return if #absent > 0 then "Attachments em falta: " .. table.concat(absent, ", ") .. " (corre StudioSetup)" else nil
	end)
end

table.insert(lines, "=== Mundo ===")
check({ "Plaza" }, function(model: Model): string?
	local problem = needsRoot(model)
	if problem then
		return problem
	end
	local root = model:FindFirstChild("Root", true) :: Instance
	return if root:FindFirstChild("CrateStation_1") then nil else "sem Attachments CrateStation_* (corre StudioSetup)"
end)
check({ "PlotSign" }, function(model: Model): string?
	return needsRoot(model) or (if hasPart(model, "Board") then nil else "sem peça 'Board'")
end)
for _, era in { "Underground", "Ascensão", "Estrelato", "Lenda" } do
	check({ "Decor", era }, needsRoot)
end
check({ "Prestige", "Arch" }, function(model: Model): string?
	return needsRoot(model) or (if hasPart(model, "Beam") then nil else "sem peça 'Beam'")
end)

table.insert(lines, "=== Artistas ===")
for _, def in ArtistsConfig.List do
	check({ "Artists", def.Id }, function(model: Model): string?
		if not hasPart(model, "HumanoidRootPart") then
			return "sem 'HumanoidRootPart'"
		end
		if not hasPart(model, "HeadAnchor") then
			return "sem 'HeadAnchor' (os kits de raridade vão para a cabeça do placeholder)"
		end
		return nil
	end)
end

table.insert(lines, "=== Kits de raridade ===")
for _, def in RaritiesConfig.List do
	if def.Id ~= "Common" and def.Id ~= "Uncommon" and def.Id ~= "Notable" then
		check({ "RarityKits", def.Id }, function(model: Model): string?
			return if hasPart(model, "KitOrigin") then nil else "sem peça 'KitOrigin'"
		end)
	end
end

table.insert(lines, "=== Adereços (Props) ===")
local propNames: { string } = {}
for _, pyro in PyroConfig.List do
	table.insert(propNames, pyro.Id)
end
for _, name in DressingConfig.Stage.SpeakerByEra do
	table.insert(propNames, name)
end
table.sort(propNames)
table.insert(propNames, DressingConfig.Stage.DJBooth.Name)
for _, entry in { "VinylCrate", "FoodTruck", "EntranceArch", "FerrisWheel" } do
	table.insert(propNames, DressingConfig.Plaza[entry].Name)
end
for _, name in propNames do
	check({ "Props", name })
end

-- Modelos ainda soltos no Workspace
local loose: { string } = {}
for _, child in Workspace:GetChildren() do
	if child:IsA("Model") and child:FindFirstChildWhichIsA("MeshPart", true) then
		table.insert(loose, child.Name)
	end
end

print(table.concat(lines, "\n"))
print(string.format(
	"[CheckAssets] ✓ %d prontos · ~ %d ainda placeholder · ✗ %d em falta/com problemas",
	ok,
	placeholder,
	missing
))
if #loose > 0 then
	warn("[CheckAssets] Modelos soltos no Workspace (corre SortImports): " .. table.concat(loose, ", "))
end
