--!strict
--[[
	LightingService
	Aplica a iluminação de festival (Config/Lighting) uma vez no arranque.
	Os efeitos criados chamam-se FE_<Classe> e só esses são substituídos; nada mais no
	Lighting é apagado. Lighting.KeepLighting = true (atributo) desliga este serviço.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LightingConfig = require(ReplicatedStorage.Shared.Config.Lighting)

local LightingService = {}

local function ensure(className: string): Instance
	local name = "FE_" .. className
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = Lighting
	return created
end

-- Copia as chaves de `values` para a instância (cada uma em pcall: uma propriedade inválida não pára as outras)
local function apply(target: Instance, values: { [string]: unknown })
	for key, value in values do
		local ok, err = pcall(function()
			(target :: any)[key] = value -- `any`: atribuição dinâmica de propriedades por nome
		end)
		if not ok then
			warn(string.format("[LightingService] %s.%s: %s", target.Name, key, tostring(err)))
		end
	end
end

function LightingService.Init()
	if not LightingConfig.Enabled or Lighting:GetAttribute("KeepLighting") == true then
		return
	end
	apply(Lighting, (LightingConfig.Properties :: unknown) :: { [string]: unknown })
	apply(ensure("Atmosphere"), (LightingConfig.Atmosphere :: unknown) :: { [string]: unknown })
	apply(ensure("BloomEffect"), (LightingConfig.Bloom :: unknown) :: { [string]: unknown })
	apply(ensure("ColorCorrectionEffect"), (LightingConfig.ColorCorrection :: unknown) :: { [string]: unknown })
	apply(ensure("SunRaysEffect"), (LightingConfig.SunRays :: unknown) :: { [string]: unknown })
end

return LightingService
