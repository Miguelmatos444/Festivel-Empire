--!strict
--[[
	ModelPaint
	Dá cor aos modelos importados do Blender. O importador do Roblox não traz a cor
	dos materiais sem textura (as peças ficam cinzentas), mas cada FBX tem uma peça
	por material com o nome do material (Wood, Body, Neon_Cyan, Skin1…).
	Aqui cada peça recebe a cor original (World/ModelPalette, gerada dos FBX) e um
	material Roblox a condizer com o nome.

	- Pinta o modelo-fonte em ServerStorage/Assets uma vez (só em memória, nada é gravado
	  no place); todos os clones herdam as cores.
	- Peças com textura (TextureID ou SurfaceAppearance) não são tocadas.
	- Modelo com o atributo KeepColors = true fica como está (pintura feita à mão no Studio).
	- Luzes (Neon_*, Led*, LEDScreen) dos palcos/praça/decoração recebem a tag FE_StageLight:
	  o cliente (StageLightController) baixa-lhes o brilho e acende-as no Bass Drop.
]]

local CollectionService = game:GetService("CollectionService")

local ModelPalette = require(script.Parent.ModelPalette)

type MaterialRule = {
	Prefix: string,
	Material: Enum.Material,
	Transparency: number?,
	Light: boolean?, -- luz de palco (tag FE_StageLight)
}

-- Avaliadas por ordem (prefixo, sem distinguir maiúsculas)
local MATERIAL_RULES: { MaterialRule } = {
	{ Prefix = "neon_", Material = Enum.Material.Neon, Light = true },
	{ Prefix = "pulse_", Material = Enum.Material.Neon },
	{ Prefix = "float_spin_pulse_", Material = Enum.Material.Neon },
	{ Prefix = "ledscreen", Material = Enum.Material.Neon, Light = true },
	{ Prefix = "led", Material = Enum.Material.Neon, Light = true },
	{ Prefix = "holo", Material = Enum.Material.Neon, Transparency = 0.35 },
	{ Prefix = "wood", Material = Enum.Material.Wood },
	{ Prefix = "metal", Material = Enum.Material.Metal },
	{ Prefix = "silver", Material = Enum.Material.Metal },
	{ Prefix = "copper", Material = Enum.Material.Metal },
	{ Prefix = "gold", Material = Enum.Material.Metal },
	{ Prefix = "grille", Material = Enum.Material.DiamondPlate },
	{ Prefix = "stone", Material = Enum.Material.Slate },
	{ Prefix = "pave", Material = Enum.Material.Pavement },
	{ Prefix = "path", Material = Enum.Material.Pavement },
	{ Prefix = "seat", Material = Enum.Material.Fabric },
	{ Prefix = "tape", Material = Enum.Material.Fabric },
}

local PAINTED_ATTRIBUTE = "FE_Painted"
local LIGHT_TAG = "FE_StageLight"

local ModelPaint = {}

local function toColor(rgb: ModelPalette.RGB): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function hasTexture(part: BasePart): boolean
	if part:FindFirstChildOfClass("SurfaceAppearance") then
		return true
	end
	return part:IsA("MeshPart") and part.TextureID ~= ""
end

local function findRule(name: string): MaterialRule?
	local lower = string.lower(name)
	for _, rule in MATERIAL_RULES do
		if string.sub(lower, 1, #rule.Prefix) == rule.Prefix then
			return rule
		end
	end
	return nil
end

-- Cor para uma peça: primeiro a do próprio modelo (kits), depois a global; aceita sufixos
-- que o Studio acrescenta a nomes repetidos (ex.: "Wood.001", "Wood1")
local function findColor(modelName: string, partName: string): ModelPalette.RGB?
	local own = ModelPalette.ByModel[modelName]
	local candidates = { partName, (string.gsub(partName, "%.%d+$", "")) }
	for _, candidate in candidates do
		local color = (own and own[candidate]) or ModelPalette.Global[candidate]
		if color then
			return color
		end
	end
	return nil
end

-- Pinta todas as peças do modelo pelo nome. Devolve o nº de peças pintadas.
-- tagLights: marca as luzes (não usar em artistas/kits, que têm efeitos próprios).
function ModelPaint.Paint(model: Model, tagLights: boolean): number
	if model:GetAttribute(PAINTED_ATTRIBUTE) or model:GetAttribute("KeepColors") == true then
		return 0
	end
	model:SetAttribute(PAINTED_ATTRIBUTE, true)
	local painted = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 and not hasTexture(descendant) then
			local color = findColor(model.Name, descendant.Name)
			if color then
				descendant.Color = toColor(color)
				painted += 1
			end
			local rule = findRule(descendant.Name)
			if rule then
				descendant.Material = rule.Material
				local transparency = rule.Transparency
				if transparency then
					descendant.Transparency = math.max(descendant.Transparency, transparency)
				end
				if tagLights and rule.Light then
					CollectionService:AddTag(descendant, LIGHT_TAG)
				end
			end
		end
	end
	return painted
end

return table.freeze(ModelPaint)
