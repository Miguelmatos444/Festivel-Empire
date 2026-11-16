--!strict
--[[
	Config/RarityCosmetics
	Kits de raridade (Models/FBX/RarityKits → ServerStorage/Assets/RarityKits/<RarityId>):
	fones, coroas, auréolas, asas… encaixados na cabeça dos artistas no palco.
	Comum, Incomum e Notável não têm kit. Animação por prefixo no nome da peça:
	  Spin_  roda sobre o próprio eixo vertical
	  Orbit_ anda à volta da cabeça
	  Float_ sobe e desce
	  Flap_  asas (rodam à volta do ombro mais próximo)
	  Pulse_ Neon a pulsar ao ritmo
	  FXPoint_<Efeito> origem de partículas (presets em Effects)
	As velocidades crescem com a raridade (Ómega no máximo). Ajusta Overrides para casos especiais.
]]

local Rarities = require(script.Parent.Rarities)

export type KitStyle = {
	Kit: string?, -- nome do modelo em RarityKits (nil = sem kit)
	SpinSpeed: number, -- rad/s
	OrbitSpeed: number, -- rad/s
	FloatAmplitude: number, -- studs (× escala do kit)
	FloatSpeed: number, -- rad/s
	FlapAngle: number, -- graus
	FlapSpeed: number, -- rad/s
	PulseStrength: number, -- 0..1 (variação de transparência)
	ParticleScale: number, -- multiplica a taxa de partículas
}

export type EffectKind = "Particles" | "Light" | "Beam"

export type EffectPreset = {
	Kind: EffectKind,
	Color: { Color3 },
	Texture: string?,
	Rate: number, -- partículas/s antes de ParticleScale
	Lifetime: NumberRange,
	Speed: NumberRange,
	Size: number,
	SpreadAngle: number,
	Acceleration: Vector3,
	LightEmission: number,
	Range: number?, -- luz / comprimento do feixe
}

local NO_KIT_FAMILY_IDS: { [string]: boolean } = { Common = true, Uncommon = true, Notable = true }
local FIRST_KIT = Rarities.IndexById.Rare
local LAST_KIT = Rarities.IndexById.Omega

local OVERRIDES: { [string]: { [string]: number } } = {}

local ByRarity: { [string]: KitStyle } = {}
for _, def in Rarities.List do
	local index = Rarities.IndexById[def.Id]
	local t = math.clamp((index - FIRST_KIT) / math.max(LAST_KIT - FIRST_KIT, 1), 0, 1)
	local style: KitStyle = {
		Kit = if NO_KIT_FAMILY_IDS[def.Id] then nil else def.Id,
		SpinSpeed = 0.6 + 2.4 * t,
		OrbitSpeed = 0.5 + 1.5 * t,
		FloatAmplitude = 0.12 + 0.3 * t,
		FloatSpeed = 1.5 + 1.5 * t,
		FlapAngle = 10 + 20 * t,
		FlapSpeed = 3 + 3 * t,
		PulseStrength = 0.3 + 0.45 * t,
		ParticleScale = 0.4 + 1.6 * t,
	}
	local override = OVERRIDES[def.Id]
	if override then
		local raw = (style :: unknown) :: { [string]: number }
		for key, value in override do
			raw[key] = value
		end
	end
	ByRarity[def.Id] = table.freeze(style)
end

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function particles(colors: { Color3 }, texture: string?, rate: number, size: number, speed: number, lifetime: number, rise: number, light: number): EffectPreset
	return {
		Kind = "Particles",
		Color = colors,
		Texture = texture,
		Rate = rate,
		Lifetime = NumberRange.new(lifetime * 0.7, lifetime),
		Speed = NumberRange.new(speed * 0.5, speed),
		Size = size,
		SpreadAngle = 180,
		Acceleration = Vector3.new(0, rise, 0),
		LightEmission = light,
		Range = nil,
	}
end

local rgb = Color3.fromRGB
-- stylua: ignore
local EFFECTS: { [string]: EffectPreset } = {
	Sparkle     = particles({ rgb(255, 255, 255), rgb(170, 220, 255) }, SPARKLE, 10, 0.35, 1.5, 1.2, 0.5, 1),
	Stars       = particles({ rgb(255, 250, 200), rgb(255, 255, 255) }, SPARKLE, 8, 0.5, 1, 1.6, 0.3, 1),
	GoldSparkle = particles({ rgb(255, 215, 90), rgb(255, 180, 40) }, SPARKLE, 12, 0.35, 1.5, 1.2, 0.5, 1),
	Fire        = particles({ rgb(255, 200, 60), rgb(255, 80, 20) }, FIRE, 14, 0.6, 2, 0.8, 4, 0.8),
	Embers      = particles({ rgb(255, 140, 40), rgb(255, 60, 20) }, SPARKLE, 10, 0.2, 2.5, 1.5, 3, 1),
	Feathers    = particles({ rgb(255, 255, 255), rgb(255, 235, 245) }, nil, 3, 0.35, 1, 2.5, -1.5, 0.2),
	Stardust    = particles({ rgb(200, 160, 255), rgb(120, 220, 255) }, SPARKLE, 14, 0.25, 1.2, 1.8, 0.2, 1),
	Galaxy      = particles({ rgb(150, 100, 255), rgb(255, 80, 200), rgb(80, 200, 255) }, SPARKLE, 16, 0.4, 0.8, 2.2, 0, 1),
	Mist        = particles({ rgb(220, 240, 255) }, SMOKE, 4, 1.4, 0.5, 2.5, 0.3, 0.2),
	Smoke       = particles({ rgb(90, 90, 110) }, SMOKE, 4, 1.2, 0.8, 2.5, 1, 0),
	Rainbow     = particles({ rgb(255, 60, 60), rgb(255, 200, 40), rgb(60, 255, 120), rgb(40, 200, 255), rgb(200, 80, 255) }, SPARKLE, 16, 0.35, 1.5, 1.5, 0.4, 1),
	Glow        = { Kind = "Light", Color = { rgb(255, 245, 210) }, Texture = nil, Rate = 0, Lifetime = NumberRange.new(0), Speed = NumberRange.new(0), Size = 0, SpreadAngle = 0, Acceleration = Vector3.zero, LightEmission = 0, Range = 10 },
	Beams       = { Kind = "Beam", Color = { rgb(255, 230, 150), rgb(255, 255, 255) }, Texture = nil, Rate = 0, Lifetime = NumberRange.new(0), Speed = NumberRange.new(0), Size = 0.6, SpreadAngle = 0, Acceleration = Vector3.zero, LightEmission = 1, Range = 8 },
}

local RarityCosmetics = table.freeze({
	ByRarity = table.freeze(ByRarity),
	Effects = table.freeze(EFFECTS),
	HeadAnchorReference = 1.26, -- tamanho X do HeadAnchor de uma cabeça normal (escala do kit = X / 1.26)
	PlaceholderHeadReference = 1.2, -- cabeça do boneco placeholder (escala = Head.Size.Y / 1.2)
	OtherPlotParticleScale = 0.4, -- partículas nos palcos dos outros jogadores
	MaxActiveEmitters = 60, -- teto de emissores ativos por cliente
})

return RarityCosmetics
