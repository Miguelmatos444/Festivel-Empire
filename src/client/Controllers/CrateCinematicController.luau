--!strict
--[[
	CrateCinematicController
	Cinemática do ultra-raro (carta mistério), só apresentação e sempre local:

	  Play(params, onDone)  versão completa para quem abriu: câmara Scriptable por cima do
	                        próprio terreno, timeline de Config/CrateAnimation (Fade → Storm →
	                        SkyOpen → Rift → Leap → Impact → Reveal → End)
	  PlayLight(summon)     versão leve para os outros jogadores, por cima do terreno de quem
	                        abriu, sem tocar na câmara nem na iluminação, com LOD por distância

	O céu:
	  - Storm:   Terrain.Clouds a 100% (só neste cliente) + teto de nuvens 3D em anéis que
	             cobre tudo o que a câmara vê; relâmpagos grossos com ramificações, a cair
	             até ao chão ou a atravessar o teto, cada um com duplo clarão
	  - SkyOpen: as nuvens afastam-se do centro e aparece uma "janela" de céu luminosa
	  - Rift:    rachas na cor da raridade crescem pela janela até à borda; o céu estilhaça
	             em pedaços que voam e o artista cai pelo buraco

	Regras:
	  - Lighting/Terrain.Clouds: só efeitos criados aqui + propriedades guardadas e repostas
	    EXATAMENTE no fim
	  - Mapa: cratera, rachas e detritos são peças locais numa pasta própria, removidas no fim
	  - Personagem parada (WalkSpeed/Jump a 0) e reposta no fim; o servidor dá o ForceField
	  - Morrer, fazer reset ou outra UI abrir a meio -> Cancel() repõe tudo de imediato
	  - Um único RenderStepped por sessão; as peças são criadas na entrada de cada fase,
	    nunca por frame
	A UI (fade, flash, título, botão "Saltar") é da CrateRevealView, ligada via SetOverlay.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local CrateAnimConfig = require(ReplicatedStorage.Shared.Config.CrateAnimation)
local LodConfig = require(ReplicatedStorage.Shared.Config.Lod)
local ArtistCalc = require(ReplicatedStorage.Shared.Calc.ArtistCalc)
local CrateAnimCalc = require(ReplicatedStorage.Shared.Calc.CrateAnimCalc)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local CinematicAssets = require(script.Parent.CinematicAssets)
local CrateSfx = require(script.Parent.CrateSfx)
local AudioController = require(script.Parent.AudioController)
local PlotController = require(script.Parent.PlotController)

type RarityDef = Types.RarityDef
type CinematicPhase = Types.CinematicPhase
type CrateSummon = Types.CrateSummon

export type CinematicParams = {
	ArtistId: string,
	Rarity: string,
	CanSkip: boolean,
	Fast: boolean,
	LowVfx: boolean,
}

export type CinematicOverlay = {
	SetFade: (alpha: number, time: number) -> (),
	Flash: (strength: number) -> (),
	ShowTitle: (artistName: string, rarity: RarityDef) -> (),
	HideTitle: () -> (),
	SetSkipVisible: (visible: boolean) -> (),
}

type Geometry = {
	Landing: Vector3, -- chão, centro da zona do público
	Sky: Vector3, -- centro do teto de nuvens
	CamBase: Vector3,
	Forward: Vector3, -- da câmara para o palco (horizontal)
	Right: Vector3,
}

type Silhouette = {
	Rig: Model,
	Parts: { BasePart },
	Colors: { Color3 },
	Materials: { Enum.Material },
	FootOffset: number,
}

type Deck = {
	Models: { Model },
	Angles: { number },
	Radii: { number },
	Heights: { number },
	Spin: number,
	Open: number, -- 0 = fechado, 1 = aberto
}

type Bolt = {
	Segments: { BasePart },
	Light: PointLight,
	StrikeTime: number,
	Visible: boolean,
}

type SkyCrack = {
	Pane: BasePart,
	Center: Vector3,
	Radius: number,
	Burst: PointLight,
	Segments: { BasePart },
	Starts: { Vector3 },
	Ends: { Vector3 },
	From: { number },
	To: { number },
	Shattered: boolean,
	Shards: { Model },
	ShardParts: { BasePart },
	ShardCF: { CFrame },
	ShardVel: { Vector3 },
	ShardSpin: { number },
	ShardAge: number,
}

type SavedState = {
	Lighting: { [string]: unknown },
	Atmosphere: Atmosphere,
	AtmosphereCreated: boolean,
	AtmosphereProps: { [string]: unknown },
	Clouds: Clouds,
	CloudsCreated: boolean,
	CloudsProps: { [string]: unknown },
	CameraType: Enum.CameraType,
	CameraSubject: Instance?,
	FieldOfView: number,
	Humanoid: Humanoid?,
	WalkSpeed: number,
	JumpPower: number,
	JumpHeight: number,
}

type Session = {
	Trove: Trove.Trove,
	Params: CinematicParams,
	Rarity: RarityDef,
	ArtistName: string,
	Phases: { CinematicPhase },
	PhaseIndex: number,
	PhaseStart: number,
	Start: number,
	OnDone: (completed: boolean) -> (),
	Done: boolean,
	Geo: Geometry,
	Folder: Folder,
	Saved: SavedState,
	Restored: boolean,
	HasControl: boolean,
	Effects: { Instance },
	Tweens: { Tween },
	Grading: ColorCorrectionEffect?,
	Deck: Deck?,
	Bolts: { Bolt },
	NextBolt: number,
	Strikes: { boolean },
	Rays: { BasePart },
	Crack: SkyCrack?,
	PanePos: Vector3,
	Rain: BasePart?,
	Sil: Silhouette?,
	Shockwave: BasePart?,
	ColorStart: number?,
	ShakeUntil: number,
	ShakeMagnitude: number,
	ShakeDuration: number,
	EndSwapped: boolean,
	OrbitBase: number,
}

local CrateCinematicController = {}

local CIN = CrateAnimConfig.Cinematic
local LIGHT = CrateAnimConfig.Light
local FOLDER_NAME = "FE_Cinematic"
local MAX_LIGHT_SESSIONS = 2
local PANE_COLOR = Color3.fromRGB(255, 236, 200)
local BOLT_SEGMENTS = 6
local BRANCH_SEGMENTS = 3

local current: Session? = nil
local overlay: CinematicOverlay? = nil
local lightSessions = 0
local rng = Random.new()

-- Utilitários -------------------------------------------------------------------

local function easeOutCubic(t: number): number
	return 1 - (1 - t) ^ 3
end

local function easeInQuad(t: number): number
	return t * t
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function withOverlay(callback: (CinematicOverlay) -> ())
	local active = overlay
	if active then
		callback(active)
	end
end

local function newEmitter(parent: Instance, color: Color3): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Rate = 0
	emitter.Parent = parent
	return emitter
end

-- Peça fina entre dois pontos (relâmpagos e rachas)
local function placeSegment(part: BasePart, from: Vector3, to: Vector3, width: number, thickness: number)
	local length = math.max((to - from).Magnitude, 0.05)
	part.Size = Vector3.new(width, thickness, length)
	part.CFrame = CFrame.lookAt((from + to) / 2, to)
end

-- Geometria a partir do terreno (atributos/Attachments gravados pelo servidor)
local function computeGeometry(userId: number, skyHeight: number): Geometry?
	local plot = PlotController.GetPlotModel(userId)
	local base = if plot then plot.PrimaryPart else nil
	if not base then
		return nil
	end
	local groundY = base.Position.Y + base.Size.Y / 2
	local crowd = base:FindFirstChild("CrowdArea")
	local spawn = base:FindFirstChild("Spawn")
	local landing = if crowd and crowd:IsA("Attachment")
		then Vector3.new(crowd.WorldPosition.X, groundY, crowd.WorldPosition.Z)
		else Vector3.new(base.Position.X, groundY, base.Position.Z)
	local spawnPos = if spawn and spawn:IsA("Attachment") then spawn.WorldPosition else landing - base.CFrame.LookVector * 28
	local flat = Vector3.new(landing.X - spawnPos.X, 0, landing.Z - spawnPos.Z)
	local forward = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	return {
		Landing = landing,
		Sky = landing + Vector3.new(0, skyHeight, 0),
		CamBase = Vector3.new(spawnPos.X, groundY + CIN.CameraHeight, spawnPos.Z),
		Forward = forward,
		Right = forward:Cross(Vector3.yAxis).Unit,
	}
end

-- Teto de nuvens ---------------------------------------------------------------------

local function spawnDeck(folder: Instance, ringCount: number, withMist: boolean): Deck
	local deck: Deck = { Models = {}, Angles = {}, Radii = {}, Heights = {}, Spin = 0, Open = 0 }
	for ringIndex = 1, math.min(ringCount, #CIN.CloudRings) do
		local ring = CIN.CloudRings[ringIndex]
		for index = 1, ring.Count do
			local cloud = CinematicAssets.Get("Cloud")
			cloud.Parent = folder
			table.insert(deck.Models, cloud)
			table.insert(deck.Angles, (index / ring.Count) * math.pi * 2 + ringIndex * 0.37 + rng:NextNumber(-0.1, 0.1))
			table.insert(deck.Radii, ring.Radius + rng:NextNumber(-4, 4))
			-- Os anéis de fora descem um pouco: o teto curva até ao horizonte
			table.insert(deck.Heights, -ringIndex * 4 + rng:NextNumber(-4, 4))
			if withMist and #deck.Models % CIN.CloudMistEvery == 0 then
				local mist = cloud:FindFirstChild("Mist", true)
				if mist and mist:IsA("ParticleEmitter") then
					mist.Rate = 1.2
					mist:Emit(3)
				end
			end
		end
	end
	return deck
end

local function updateDeck(deck: Deck, center: Vector3, dt: number)
	deck.Spin += CIN.CloudSpin * dt
	local open = easeOutCubic(math.clamp(deck.Open, 0, 1))
	for index, cloud in deck.Models do
		local angle = deck.Angles[index] + deck.Spin
		local radius = deck.Radii[index] + CIN.CloudOpenDistance * open
		local height = deck.Heights[index] + 8 * open
		cloud:PivotTo(CFrame.new(center + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)) * CFrame.Angles(0, -angle, 0))
	end
end

local function fadeDeck(deck: Deck, alpha: number)
	for _, cloud in deck.Models do
		for _, descendant in cloud:GetDescendants() do
			if descendant:IsA("BasePart") and descendant.Name ~= "Root" then
				descendant.Transparency = math.max(descendant.Transparency, alpha)
			elseif descendant:IsA("ParticleEmitter") then
				descendant.Rate = 0
			end
		end
	end
end

local function destroyDeck(deck: Deck)
	for _, cloud in deck.Models do
		cloud:Destroy()
	end
	table.clear(deck.Models)
end

-- Relâmpagos -----------------------------------------------------------------------

local function makeBolt(folder: Instance): Bolt
	local segments: { BasePart } = {}
	for index = 1, BOLT_SEGMENTS + CIN.BoltBranches * BRANCH_SEGMENTS do
		local segment = CinematicAssets.NewPart("Bolt" .. index, Vector3.one, CFrame.new(), Color3.fromRGB(225, 232, 255), Enum.Material.Neon, folder)
		segment.Transparency = 1
		table.insert(segments, segment)
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(200, 215, 255)
	light.Range = 60
	light.Brightness = 0
	light.Parent = segments[1]
	return { Segments = segments, Light = light, StrikeTime = -math.huge, Visible = false }
end

-- Relâmpago em ziguezague de `from` até `to`, com ramificações
local function strike(bolt: Bolt, from: Vector3, to: Vector3)
	local direction = to - from
	local length = direction.Magnitude
	local side = direction:Cross(Vector3.yAxis)
	if side.Magnitude < 0.01 then
		side = Vector3.xAxis
	end
	side = side.Unit
	local up = side:Cross(direction.Unit)
	local jitter = length * 0.07

	local vertices: { Vector3 } = { from }
	for index = 1, BOLT_SEGMENTS do
		local point = from + direction * (index / BOLT_SEGMENTS)
		if index < BOLT_SEGMENTS then
			point += side * rng:NextNumber(-jitter, jitter) + up * rng:NextNumber(-jitter, jitter)
		end
		table.insert(vertices, point)
		placeSegment(bolt.Segments[index], vertices[index], point, CIN.BoltWidth, CIN.BoltWidth)
	end

	local slot = BOLT_SEGMENTS
	for branch = 1, CIN.BoltBranches do
		local root = vertices[math.clamp(branch * 2, 2, BOLT_SEGMENTS)]
		local branchDir = (direction.Unit + side * (if branch % 2 == 0 then 0.9 else -0.9)).Unit
		local previous = root
		for index = 1, BRANCH_SEGMENTS do
			local point = previous + branchDir * (length * 0.09) + side * rng:NextNumber(-jitter, jitter) * 0.5
			slot += 1
			placeSegment(bolt.Segments[slot], previous, point, CIN.BoltWidth * 0.55, CIN.BoltWidth * 0.55)
			previous = point
		end
	end
	bolt.Light.Parent = bolt.Segments[3]
	bolt.StrikeTime = os.clock()
end

-- Duplo clarão: 0–0.07 s aceso, 0.07–0.11 apagado, 0.11–0.21 aceso
local function updateBolt(bolt: Bolt, now: number)
	local age = now - bolt.StrikeTime
	local visible = age < 0.07 or (age > 0.11 and age < 0.21)
	if visible == bolt.Visible then
		return
	end
	bolt.Visible = visible
	bolt.Light.Brightness = if visible then 12 else 0
	for _, segment in bolt.Segments do
		segment.Transparency = if visible then 0 else 1
	end
end

-- Pontos de um relâmpago dentro do campo de visão (alterna chão / através do teto)
local function strikePoints(geo: Geometry, index: number, skyHeight: number): (Vector3, Vector3)
	local offset = geo.Right * rng:NextNumber(-55, 55) + geo.Forward * rng:NextNumber(-5, 55)
	local top = geo.Sky + offset - Vector3.new(0, 4, 0)
	if index % 2 == 1 then
		local bottom = Vector3.new(top.X + rng:NextNumber(-15, 15), geo.Landing.Y + skyHeight * 0.1, top.Z + rng:NextNumber(-15, 15))
		return top, bottom
	end
	local across = (geo.Right * rng:NextNumber(-1, 1) + geo.Forward * rng:NextNumber(-0.3, 1))
	local dir = if across.Magnitude > 0.01 then across.Unit else geo.Right
	return top - dir * 45, top + dir * 45 - Vector3.new(0, rng:NextNumber(0, 8), 0)
end

-- Céu a rachar -----------------------------------------------------------------------

local function makeSkyCrack(folder: Instance, center: Vector3, radius: number, lines: number, rarity: RarityDef): SkyCrack
	local pane = CinematicAssets.NewPart(
		"SkyPane",
		Vector3.new(0.6, radius * 2, radius * 2),
		CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)),
		PANE_COLOR,
		Enum.Material.Neon,
		folder
	)
	pane.Shape = Enum.PartType.Cylinder
	pane.Transparency = 1
	local burst = Instance.new("PointLight")
	burst.Color = rarity.Color
	burst.Range = 60
	burst.Brightness = 0
	burst.Parent = pane

	local crack: SkyCrack = {
		Pane = pane,
		Center = center,
		Radius = radius,
		Burst = burst,
		Segments = {},
		Starts = {},
		Ends = {},
		From = {},
		To = {},
		Shattered = false,
		Shards = {},
		ShardParts = {},
		ShardCF = {},
		ShardVel = {},
		ShardSpin = {},
		ShardAge = 0,
	}
	local segmentsPerLine = CIN.CrackSegments
	local mainEnd = 0.85 -- as linhas principais chegam à borda a 85% do crescimento
	local below = center - Vector3.new(0, 0.45, 0) -- por baixo da janela (vê-se do chão)

	local function addSegment(from: Vector3, to: Vector3, startAt: number, endAt: number)
		local part = CinematicAssets.NewPart("Crack", Vector3.one, CFrame.new(from), rarity.Color, Enum.Material.Neon, folder)
		part.Transparency = 1
		table.insert(crack.Segments, part)
		table.insert(crack.Starts, from)
		table.insert(crack.Ends, to)
		table.insert(crack.From, startAt)
		table.insert(crack.To, endAt)
	end

	for line = 1, lines do
		local angle = (line / lines) * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		local point = below
		for step = 1, segmentsPerLine do
			angle += rng:NextNumber(-0.35, 0.35)
			local length = radius / segmentsPerLine * rng:NextNumber(0.85, 1.15)
			local nextPoint = point + Vector3.new(math.cos(angle) * length, 0, math.sin(angle) * length)
			addSegment(point, nextPoint, (step - 1) / segmentsPerLine * mainEnd, step / segmentsPerLine * mainEnd)
			if step == 2 then
				local branchAngle = angle + (if line % 2 == 0 then 0.9 else -0.9)
				local branchStart = step / segmentsPerLine * mainEnd
				local branchPoint = nextPoint
				for branchStep = 1, 2 do
					local branchNext = branchPoint + Vector3.new(math.cos(branchAngle), 0, math.sin(branchAngle)) * (length * 0.8)
					addSegment(branchPoint, branchNext, branchStart + (branchStep - 1) * 0.12, branchStart + branchStep * 0.12)
					branchPoint = branchNext
					branchAngle += rng:NextNumber(-0.3, 0.3)
				end
			end
			point = nextPoint
		end
	end
	return crack
end

-- Crescimento das rachas (0..1)
local function growCrack(crack: SkyCrack, progress: number)
	for index, part in crack.Segments do
		local span = crack.To[index] - crack.From[index]
		local partial = math.clamp((progress - crack.From[index]) / math.max(span, 0.001), 0, 1)
		if partial <= 0 then
			part.Transparency = 1
		else
			local from = crack.Starts[index]
			local to = from:Lerp(crack.Ends[index], partial)
			placeSegment(part, from, to, 0.9, 0.3)
			part.Transparency = 0
		end
	end
	crack.Burst.Brightness = progress * 4
end

local function shatterCrack(crack: SkyCrack, folder: Instance, shardCount: number)
	if crack.Shattered then
		return
	end
	crack.Shattered = true
	crack.Pane.Transparency = 1
	for _, part in crack.Segments do
		part.Transparency = 1
	end
	crack.Burst.Brightness = 12
	for _ = 1, shardCount do
		local shard = CinematicAssets.Get("SkyShard")
		local distance = math.sqrt(rng:NextNumber()) * crack.Radius
		local angle = rng:NextNumber(0, math.pi * 2)
		local position = crack.Center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local cframe = CFrame.new(position) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6), rng:NextNumber(-0.3, 0.3))
		shard:ScaleTo(rng:NextNumber(0.6, 1.5))
		shard:PivotTo(cframe)
		shard.Parent = folder
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		table.insert(crack.Shards, shard)
		local visual: BasePart? = nil
		for _, descendant in shard:GetDescendants() do
			if descendant:IsA("BasePart") and descendant ~= shard.PrimaryPart then
				visual = descendant
				break
			end
		end
		table.insert(crack.ShardParts, visual or (shard.PrimaryPart :: BasePart))
		table.insert(crack.ShardCF, cframe)
		table.insert(crack.ShardVel, outward * CIN.ShardSpeed * rng:NextNumber(0.4, 1) - Vector3.new(0, rng:NextNumber(5, 25), 0))
		table.insert(crack.ShardSpin, rng:NextNumber(-5, 5))
	end
end

local function updateShards(crack: SkyCrack, dt: number)
	if not crack.Shattered then
		return
	end
	crack.ShardAge += dt
	crack.Burst.Brightness = math.max(0, crack.Burst.Brightness - dt * 10)
	local fade = math.clamp(crack.ShardAge / 2.5, 0, 1)
	for index, shard in crack.Shards do
		local velocity = crack.ShardVel[index] - Vector3.new(0, 50 * dt, 0)
		crack.ShardVel[index] = velocity
		local spin = crack.ShardSpin[index] * dt
		local cframe = (crack.ShardCF[index] + velocity * dt) * CFrame.Angles(spin, spin * 0.7, 0)
		crack.ShardCF[index] = cframe
		shard:PivotTo(cframe)
		crack.ShardParts[index].Transparency = 0.2 + 0.8 * fade
	end
end

local function destroyCrack(crack: SkyCrack)
	crack.Pane:Destroy()
	for _, part in crack.Segments do
		part:Destroy()
	end
	for _, shard in crack.Shards do
		shard:Destroy()
	end
	table.clear(crack.Segments)
	table.clear(crack.Shards)
end

-- Artista ------------------------------------------------------------------------

local function makeSilhouette(folder: Instance, artistId: string, rarity: RarityDef): Silhouette
	local rig = CinematicAssets.GetArtistRig(artistId, rarity.Color)
	local silhouette: Silhouette = { Rig = rig, Parts = {}, Colors = {}, Materials = {}, FootOffset = 0 }
	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= rig.PrimaryPart then
			table.insert(silhouette.Parts, descendant)
			table.insert(silhouette.Colors, descendant.Color)
			table.insert(silhouette.Materials, descendant.Material)
			descendant.Color = Color3.new(0, 0, 0)
			descendant.Material = Enum.Material.SmoothPlastic
		elseif descendant:IsA("Decal") then
			descendant.Transparency = 1 -- Texture herda de Decal
		end
	end
	silhouette.FootOffset = CinematicAssets.GetFootOffset(rig)
	local root = rig.PrimaryPart
	if root then
		local top = Instance.new("Attachment")
		top.Position = Vector3.new(0, 1.5, 0)
		top.Parent = root
		local bottom = Instance.new("Attachment")
		bottom.Position = Vector3.new(0, -1.5, 0)
		bottom.Parent = root
		local trail = Instance.new("Trail")
		trail.Attachment0 = top
		trail.Attachment1 = bottom
		trail.Color = ColorSequence.new(rarity.Color, Color3.new(1, 1, 1))
		trail.LightEmission = 1
		trail.Lifetime = 0.4
		trail.Transparency = NumberSequence.new(0, 1)
		trail.Parent = root
	end
	rig.Parent = folder
	return silhouette
end

-- Silhueta preta -> cores reais (0..1)
local function colorSilhouette(silhouette: Silhouette, t: number)
	local black = Color3.new(0, 0, 0)
	for index, part in silhouette.Parts do
		part.Color = black:Lerp(silhouette.Colors[index], t)
		if t >= 1 then
			part.Material = silhouette.Materials[index]
		end
	end
end

local function addAura(silhouette: Silhouette, rarity: RarityDef, lowVfx: boolean)
	local root = silhouette.Rig.PrimaryPart
	if not root then
		return
	end
	local aura = newEmitter(root, rarity.Color)
	aura.Rate = if lowVfx then 10 else 30
	aura.Lifetime = NumberRange.new(0.8, 1.4)
	aura.Speed = NumberRange.new(2, 4)
	aura.SpreadAngle = Vector2.new(180, 180)
	aura.Size = NumberSequence.new(0.8, 0)
	aura.Acceleration = Vector3.new(0, 4, 0)
	local light = Instance.new("PointLight")
	light.Color = rarity.Color
	light.Range = 16
	light.Brightness = 3
	light.Parent = root
end

local function placeRig(silhouette: Silhouette, position: Vector3, lookAt: Vector3)
	local base = position + Vector3.new(0, silhouette.FootOffset, 0)
	silhouette.Rig:PivotTo(CFrame.lookAt(base, Vector3.new(lookAt.X, base.Y, lookAt.Z)))
end

-- Onda de choque, cratera, rachas no chão, detritos e pó
local function spawnImpact(folder: Instance, landing: Vector3, rarity: RarityDef, lowVfx: boolean, full: boolean): BasePart
	local shockwave = CinematicAssets.NewPart(
		"Shockwave",
		Vector3.new(0.4, 2, 2),
		CFrame.new(landing + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.new(1, 1, 1),
		Enum.Material.Neon,
		folder
	)
	shockwave.Shape = Enum.PartType.Cylinder

	local dustAnchor = CinematicAssets.NewPart("Dust", Vector3.new(1, 1, 1), CFrame.new(landing + Vector3.new(0, 1, 0)), Color3.new(), Enum.Material.SmoothPlastic, folder)
	dustAnchor.Transparency = 1
	local dust = newEmitter(dustAnchor, Color3.fromRGB(140, 125, 110))
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.LightEmission = 0
	dust.Lifetime = NumberRange.new(1.5, 2.5)
	dust.Speed = NumberRange.new(10, 25)
	dust.SpreadAngle = Vector2.new(180, 30)
	dust.Drag = 3
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 9) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	dust:Emit(if lowVfx then CIN.DustBurstLow else CIN.DustBurst)

	if not full then
		return shockwave
	end

	local crater = CinematicAssets.Get("Crater")
	crater:PivotTo(CFrame.new(landing))
	crater.Parent = folder

	for index = 1, CIN.CrackCount do
		local angle = (index / CIN.CrackCount) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local length = rng:NextNumber(8, 16)
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local mid = landing + direction * (CIN.CraterRadius * 0.6 + length / 2) + Vector3.new(0, 0.08, 0)
		local crack = CinematicAssets.NewPart("GroundCrack" .. index, Vector3.new(0.5, 0.1, length), CFrame.lookAt(mid, mid + direction), rarity.Color, Enum.Material.Neon, folder)
		crack.Transparency = 0.2
	end

	local debrisCount = if lowVfx then CIN.DebrisCountLow else CIN.DebrisCount
	for _ = 1, debrisCount do
		local debris = CinematicAssets.Get("Debris")
		local start = landing + Vector3.new(rng:NextNumber(-3, 3), 1.5, rng:NextNumber(-3, 3))
		debris:PivotTo(CFrame.new(start) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0))
		local root = debris.PrimaryPart
		-- Peças soldadas ao Root para voarem juntas; só a geometria colide
		for _, descendant in debris:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = false
				descendant.CanCollide = descendant ~= root
				if root and descendant ~= root then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = root
					weld.Part1 = descendant
					weld.Parent = descendant
				end
			end
		end
		debris.Parent = folder
		if root then
			root.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-30, 30), rng:NextNumber(25, 50), rng:NextNumber(-30, 30))
			root.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8))
		end
	end
	return shockwave
end

local function updateShockwave(shockwave: BasePart, t: number, maxDiameter: number)
	local diameter = lerp(2, maxDiameter, easeOutCubic(t))
	shockwave.Size = Vector3.new(0.4, diameter, diameter)
	shockwave.Transparency = t
end

-- Estado: guardar / repor --------------------------------------------------------------

local LIGHTING_PROPS = { "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "ExposureCompensation", "FogStart", "FogEnd", "FogColor" }
local ATMOSPHERE_PROPS = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" }
local CLOUDS_PROPS = { "Cover", "Density", "Color", "Enabled" }

local function readProps(instance: Instance, names: { string }): { [string]: unknown }
	local values: { [string]: unknown } = {}
	local raw = (instance :: unknown) :: { [string]: unknown }
	for _, name in names do
		values[name] = raw[name]
	end
	return values
end

local function writeProps(instance: Instance, values: { [string]: unknown })
	local raw = (instance :: unknown) :: { [string]: unknown }
	for name, value in values do
		raw[name] = value
	end
end

local function saveState(): SavedState
	local camera = Workspace.CurrentCamera
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local atmosphereCreated = atmosphere == nil
	local atmo: Atmosphere = atmosphere or Instance.new("Atmosphere")
	if atmosphereCreated then
		atmo.Name = FOLDER_NAME .. "_Atmosphere"
		atmo.Density = 0
		atmo.Haze = 0
		atmo.Glare = 0
		atmo.Parent = Lighting
	end
	local terrain = Workspace.Terrain
	local existingClouds = terrain:FindFirstChildOfClass("Clouds")
	local cloudsCreated = existingClouds == nil
	local clouds: Clouds = existingClouds or Instance.new("Clouds")
	if cloudsCreated then
		clouds.Name = FOLDER_NAME .. "_Clouds"
		clouds.Cover = 0
		clouds.Density = 0
		clouds.Parent = terrain
	end
	local character = Players.LocalPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	return {
		Lighting = readProps(Lighting, LIGHTING_PROPS),
		Atmosphere = atmo,
		AtmosphereCreated = atmosphereCreated,
		AtmosphereProps = readProps(atmo, ATMOSPHERE_PROPS),
		Clouds = clouds,
		CloudsCreated = cloudsCreated,
		CloudsProps = readProps(clouds, CLOUDS_PROPS),
		CameraType = camera.CameraType,
		CameraSubject = camera.CameraSubject,
		FieldOfView = camera.FieldOfView,
		Humanoid = humanoid,
		WalkSpeed = if humanoid then humanoid.WalkSpeed else 16,
		JumpPower = if humanoid then humanoid.JumpPower else 50,
		JumpHeight = if humanoid then humanoid.JumpHeight else 7.2,
	}
end

local function tweenTo(session: Session, instance: Instance, time: number, goals: { [string]: any })
	local tween = TweenService:Create(instance, TweenInfo.new(time, Enum.EasingStyle.Sine), goals)
	table.insert(session.Tweens, tween)
	tween:Play()
end

local function goalsFrom(values: { [string]: unknown }): { [string]: any }
	local goals: { [string]: any } = {}
	for name, value in values do
		if name ~= "Enabled" then
			goals[name] = value
		end
	end
	return goals
end

local function restore(session: Session)
	if session.Restored then
		return
	end
	session.Restored = true
	for _, tween in session.Tweens do
		tween:Cancel()
	end
	table.clear(session.Tweens)
	local saved = session.Saved
	writeProps(Lighting, saved.Lighting)
	if saved.AtmosphereCreated then
		saved.Atmosphere:Destroy()
	elseif saved.Atmosphere.Parent then
		writeProps(saved.Atmosphere, saved.AtmosphereProps)
	end
	if saved.CloudsCreated then
		saved.Clouds:Destroy()
	elseif saved.Clouds.Parent then
		writeProps(saved.Clouds, saved.CloudsProps)
	end
	for _, effect in session.Effects do
		effect:Destroy()
	end
	table.clear(session.Effects)
	session.Grading = nil

	local camera = Workspace.CurrentCamera
	camera.CameraType = saved.CameraType
	local character = Players.LocalPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	camera.CameraSubject = if humanoid then humanoid else saved.CameraSubject
	camera.FieldOfView = saved.FieldOfView

	local frozen = saved.Humanoid
	if frozen and frozen.Parent then
		frozen.WalkSpeed = saved.WalkSpeed
		frozen.JumpPower = saved.JumpPower
		frozen.JumpHeight = saved.JumpHeight
	end
	AudioController.SetMusicMuted(false)
end

local function finish(session: Session, completed: boolean)
	if session.Done then
		return
	end
	session.Done = true
	restore(session)
	withOverlay(function(o)
		o.HideTitle()
		o.SetSkipVisible(false)
		o.SetFade(0, 0.25)
	end)
	session.Trove:Destroy()
	if current == session then
		current = nil
	end
	session.OnDone(completed)
end

-- Câmara -----------------------------------------------------------------------------

local function shakeOffset(session: Session): Vector3
	local now = os.clock()
	if now >= session.ShakeUntil then
		return Vector3.zero
	end
	local remaining = (session.ShakeUntil - now) / math.max(session.ShakeDuration, 0.01)
	local magnitude = session.ShakeMagnitude * remaining
	return Vector3.new(math.noise(now * 25, 1) * magnitude, math.noise(now * 25, 2) * magnitude, math.noise(now * 25, 3) * magnitude)
end

local function shake(session: Session, magnitude: number, duration: number)
	session.ShakeMagnitude = magnitude
	session.ShakeDuration = duration
	session.ShakeUntil = os.clock() + duration
end

local function setCamera(session: Session, position: Vector3, lookAt: Vector3, fov: number)
	local camera = Workspace.CurrentCamera
	local offset = shakeOffset(session)
	camera.CFrame = CFrame.lookAt(position + offset, lookAt + offset * 0.5)
	camera.FieldOfView = fov
end

-- Clarão de relâmpago/estilhaço: ilumina a imagem toda (ColorCorrection) + flash leve
local function lightningFlash(session: Session, strength: number)
	local grading = session.Grading
	if grading then
		grading.Brightness = 0.35 * strength
		tweenTo(session, grading, 0.25, { Brightness = 0 })
	end
	withOverlay(function(o)
		o.Flash(0.35 * strength)
	end)
end

-- Assume o controlo da câmara (idempotente) e tira o ecrã do preto
local function takeControl(session: Session)
	if session.HasControl then
		return
	end
	session.HasControl = true
	Workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
	withOverlay(function(o)
		o.SetFade(0, 0.4)
		o.SetSkipVisible(session.Params.CanSkip)
	end)
end

local function ensureSilhouette(session: Session): Silhouette
	local existing = session.Sil
	if existing then
		return existing
	end
	local silhouette = makeSilhouette(session.Folder, session.Params.ArtistId, session.Rarity)
	placeRig(silhouette, session.Geo.Landing, session.Geo.CamBase)
	session.Sil = silhouette
	return silhouette
end

local function ensureCrack(session: Session): SkyCrack
	local existing = session.Crack
	if existing then
		return existing
	end
	local lines = if session.Params.LowVfx then CIN.CrackLinesLow else CIN.CrackLines
	local crack = makeSkyCrack(session.Folder, session.PanePos, CIN.PaneRadius, lines, session.Rarity)
	session.Crack = crack
	return crack
end

-- Remove tempestade, céu e rachas (Saltar / fim da revelação)
local function clearSky(session: Session)
	local deck = session.Deck
	if deck then
		destroyDeck(deck)
		session.Deck = nil
	end
	for _, ray in session.Rays do
		ray:Destroy()
	end
	table.clear(session.Rays)
	local crack = session.Crack
	if crack then
		destroyCrack(crack)
		session.Crack = nil
	end
	local rain = session.Rain
	if rain then
		rain:Destroy()
		session.Rain = nil
	end
	for _, bolt in session.Bolts do
		for _, segment in bolt.Segments do
			segment:Destroy()
		end
	end
	table.clear(session.Bolts)
end

-- Efeito de pós-processamento criado por nós em Lighting (destruído na reposição)
local function trackEffect(session: Session, effect: Instance)
	effect.Name = FOLDER_NAME .. "_" .. effect.ClassName
	effect.Parent = Lighting
	table.insert(session.Effects, effect)
end

-- Fases (entrada) --------------------------------------------------------------------

local ENTER: { [string]: (Session) -> () } = {}
local UPDATE: { [string]: (Session, number, number, number) -> () } = {}

ENTER.Fade = function(session: Session)
	withOverlay(function(o)
		o.SetFade(1, session.Phases[1].Duration * 0.9)
	end)
	AudioController.SetMusicMuted(true)
	local humanoid = session.Saved.Humanoid
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	end
end

ENTER.Storm = function(session: Session)
	takeControl(session)
	local low = session.Params.LowVfx
	session.Deck = spawnDeck(session.Folder, if low then CIN.CloudRingsLow else #CIN.CloudRings, not low)
	for _ = 1, CIN.BoltPool do
		table.insert(session.Bolts, makeBolt(session.Folder))
	end

	local rain = CinematicAssets.NewPart("Rain", Vector3.new(120, 1, 120), CFrame.new(session.Geo.CamBase + Vector3.new(0, 40, 0)), Color3.new(), Enum.Material.SmoothPlastic, session.Folder)
	rain.Transparency = 1
	local drops = newEmitter(rain, Color3.fromRGB(170, 185, 210))
	drops.LightEmission = 0.2
	drops.EmissionDirection = Enum.NormalId.Bottom
	drops.Rate = if low then CIN.RainRateLow else CIN.RainRate
	drops.Lifetime = NumberRange.new(0.6, 0.9)
	drops.Speed = NumberRange.new(90, 110)
	drops.Size = NumberSequence.new(0.12)
	drops.Squash = NumberSequence.new(-2.5)
	drops.Orientation = Enum.ParticleOrientation.VelocityParallel
	drops.Transparency = NumberSequence.new(0.35)
	session.Rain = rain

	local saved = session.Saved
	tweenTo(session, Lighting, 1.2, {
		ClockTime = 0.5,
		Brightness = 0.6,
		Ambient = Color3.fromRGB(25, 25, 40),
		OutdoorAmbient = Color3.fromRGB(35, 35, 55),
		ExposureCompensation = -0.4,
	})
	tweenTo(session, saved.Atmosphere, 1.2, { Density = 0.45, Haze = 3, Color = Color3.fromRGB(60, 62, 75), Glare = 0 })
	saved.Clouds.Enabled = true
	tweenTo(session, saved.Clouds, 1, {
		Cover = CIN.TerrainClouds.Cover,
		Density = CIN.TerrainClouds.Density,
		Color = CIN.TerrainClouds.Color,
	})
	local grading = Instance.new("ColorCorrectionEffect")
	trackEffect(session, grading)
	session.Grading = grading
	tweenTo(session, grading, 1.2, { Saturation = -0.55, Contrast = 0.2, TintColor = Color3.fromRGB(200, 210, 255) })
end

ENTER.SkyOpen = function(session: Session)
	takeControl(session)
	local count = if session.Params.LowVfx then 3 else 6
	for index = 1, count do
		local angle = (index / count) * math.pi * 2
		local bottom = session.Geo.Landing + Vector3.new(math.cos(angle) * 14, 0, math.sin(angle) * 14)
		local top = session.PanePos + Vector3.new(math.cos(angle) * 6, 0, math.sin(angle) * 6)
		local length = (top - bottom).Magnitude
		local ray = CinematicAssets.NewPart("SunRay" .. index, Vector3.new(4, 4, length), CFrame.lookAt((top + bottom) / 2, bottom), Color3.fromRGB(255, 214, 120), Enum.Material.Neon, session.Folder)
		ray.Transparency = 1
		table.insert(session.Rays, ray)
		tweenTo(session, ray, 1.2, { Transparency = 0.65 })
	end
	local sunRays = Instance.new("SunRaysEffect")
	sunRays.Intensity = 0
	sunRays.Spread = 0.6
	trackEffect(session, sunRays)
	tweenTo(session, sunRays, 1.2, { Intensity = 0.25 })
	local bloom = Instance.new("BloomEffect")
	trackEffect(session, bloom)
	bloom.Intensity = 0
	bloom.Size = 30
	bloom.Threshold = 0.85
	tweenTo(session, bloom, 1.2, { Intensity = 1 })
	local grading = session.Grading
	if grading then
		tweenTo(session, grading, 1.4, { TintColor = Color3.fromRGB(255, 235, 200), Saturation = -0.2 })
	end
	-- A "janela" de céu luminosa aparece no buraco das nuvens
	local crack = ensureCrack(session)
	tweenTo(session, crack.Pane, 1.4, { Transparency = 0.45 })
end

ENTER.Rift = function(session: Session)
	takeControl(session)
	local crack = ensureCrack(session)
	crack.Pane.Transparency = math.min(crack.Pane.Transparency, 0.45)
	CrateSfx.Play("RiftOpen")
end

ENTER.Leap = function(session: Session)
	takeControl(session)
	local crack = session.Crack
	if crack and not crack.Shattered then
		shatterCrack(crack, session.Folder, if session.Params.LowVfx then CIN.ShardCountLow else CIN.ShardCount)
	end
	local silhouette = ensureSilhouette(session)
	placeRig(silhouette, session.PanePos, session.Geo.CamBase)
end

ENTER.Impact = function(session: Session)
	takeControl(session)
	local silhouette = ensureSilhouette(session)
	placeRig(silhouette, session.Geo.Landing, session.Geo.CamBase)
	session.Shockwave = spawnImpact(session.Folder, session.Geo.Landing, session.Rarity, session.Params.LowVfx, true)
	shake(session, CIN.ShakeImpact, CIN.ShakeImpactTime)
	CrateSfx.Play("Impact")
	withOverlay(function(o)
		o.Flash(1)
	end)
end

ENTER.Reveal = function(session: Session)
	takeControl(session)
	local silhouette = ensureSilhouette(session)
	placeRig(silhouette, session.Geo.Landing, session.Geo.CamBase)
	session.ColorStart = os.clock()
	addAura(silhouette, session.Rarity, session.Params.LowVfx)
	CrateSfx.Play("RevealSting")
	local toCamera = session.Geo.CamBase - session.Geo.Landing
	session.OrbitBase = math.atan2(toCamera.Z, toCamera.X)
	withOverlay(function(o)
		o.ShowTitle(session.ArtistName, session.Rarity)
		o.SetSkipVisible(false)
	end)
	-- O céu limpa e a iluminação volta ao normal durante a revelação
	local deck = session.Deck
	if deck then
		fadeDeck(deck, 0.5)
	end
	local saved = session.Saved
	tweenTo(session, Lighting, 1.8, goalsFrom(saved.Lighting))
	tweenTo(session, saved.Atmosphere, 1.8, goalsFrom(saved.AtmosphereProps))
	tweenTo(session, saved.Clouds, 1.8, goalsFrom(saved.CloudsProps))
end

ENTER.End = function(session: Session)
	withOverlay(function(o)
		local phase = session.Phases[session.PhaseIndex]
		o.SetFade(1, (if phase then phase.Duration else 0.8) * 0.45)
		o.SetSkipVisible(false)
	end)
end

-- Fases (por frame) ------------------------------------------------------------------

UPDATE.Fade = function(_session: Session, _t: number, _alpha: number, _dt: number) end

UPDATE.Storm = function(session: Session, t: number, _alpha: number, _dt: number)
	local geo = session.Geo
	for index, time in CIN.LightningTimes do
		if not session.Strikes[index] and t >= time then
			session.Strikes[index] = true
			local bolt = session.Bolts[session.NextBolt]
			session.NextBolt = session.NextBolt % math.max(#session.Bolts, 1) + 1
			if bolt then
				local from, to = strikePoints(geo, index, CIN.SkyHeight)
				strike(bolt, from, to)
			end
			lightningFlash(session, 1)
			task.delay(CIN.ThunderDelay, function()
				if not session.Done then
					CrateSfx.Play("Thunder")
				end
			end)
		end
	end
	local sway = geo.Right * math.sin(t * 0.4) * 2
	setCamera(session, geo.CamBase + sway, geo.Sky, CIN.FovStart)
end

UPDATE.SkyOpen = function(session: Session, _t: number, alpha: number, _dt: number)
	local geo = session.Geo
	local deck = session.Deck
	if deck then
		deck.Open = alpha
	end
	local push = geo.Forward * 6 * easeOutCubic(alpha) + Vector3.new(0, 4 * alpha, 0)
	setCamera(session, geo.CamBase + push, session.PanePos, CIN.FovStart)
end

UPDATE.Rift = function(session: Session, t: number, _alpha: number, _dt: number)
	local geo = session.Geo
	local crack = ensureCrack(session)
	local growTime = CIN.CrackGrowTime
	if t < growTime then
		local progress = t / growTime
		growCrack(crack, progress)
		crack.Pane.Transparency = lerp(0.45, 0.15, progress)
		if session.ShakeUntil < os.clock() then
			shake(session, CIN.ShakeRift * (1 + progress * 2), 0.25)
		end
	elseif not crack.Shattered then
		shatterCrack(crack, session.Folder, if session.Params.LowVfx then CIN.ShardCountLow else CIN.ShardCount)
		CrateSfx.Play("SkyShatter")
		lightningFlash(session, 1.6)
		shake(session, CIN.ShakeImpact * 0.5, 0.4)
	end
	setCamera(session, geo.CamBase + geo.Forward * 6 + Vector3.new(0, 4, 0), session.PanePos, CIN.FovStart)
end

UPDATE.Leap = function(session: Session, _t: number, alpha: number, _dt: number)
	local geo = session.Geo
	local silhouette = session.Sil
	local position = session.PanePos:Lerp(geo.Landing, easeInQuad(alpha))
	if silhouette then
		placeRig(silhouette, position, geo.CamBase)
	end
	local cameraPos = geo.CamBase + geo.Forward * 6 + Vector3.new(0, lerp(4, 1, alpha), 0)
	setCamera(session, cameraPos, position + Vector3.new(0, 2, 0), lerp(CIN.FovStart, CIN.FovLeap, alpha))
end

UPDATE.Impact = function(session: Session, _t: number, alpha: number, _dt: number)
	local geo = session.Geo
	local shockwave = session.Shockwave
	if shockwave then
		updateShockwave(shockwave, alpha, CIN.CraterRadius * 6)
	end
	local cameraPos = geo.CamBase + geo.Forward * 6 + Vector3.new(0, 1, 0)
	setCamera(session, cameraPos, geo.Landing + Vector3.new(0, 2, 0), lerp(CIN.FovLeap, CIN.FovReveal, alpha))
end

UPDATE.Reveal = function(session: Session, t: number, _alpha: number, _dt: number)
	local geo = session.Geo
	local silhouette = session.Sil
	local colorStart = session.ColorStart
	if silhouette and colorStart then
		local progress = math.clamp((os.clock() - colorStart) / CIN.ColorTweenTime, 0, 1)
		colorSilhouette(silhouette, progress)
		if progress >= 1 then
			session.ColorStart = nil
		end
	end
	local angle = session.OrbitBase + t * CIN.OrbitSpeed
	local cameraPos = geo.Landing + Vector3.new(math.cos(angle) * CIN.OrbitRadius, 4, math.sin(angle) * CIN.OrbitRadius)
	setCamera(session, cameraPos, geo.Landing + Vector3.new(0, 3, 0), CIN.FovReveal)
end

UPDATE.End = function(session: Session, t: number, alpha: number, dt: number)
	-- A meio do fade (ecrã a preto) repõe câmara e iluminação; depois tira o preto
	if not session.EndSwapped and alpha >= 0.5 then
		session.EndSwapped = true
		local silhouette = session.Sil
		if silhouette then
			colorSilhouette(silhouette, 1)
		end
		clearSky(session)
		restore(session)
		withOverlay(function(o)
			o.HideTitle()
			o.SetFade(0, 0.35)
		end)
	elseif not session.EndSwapped then
		UPDATE.Reveal(session, t + 2.4, alpha, dt)
	end
end

-- Motor da timeline ---------------------------------------------------------------------

local function enter(session: Session, name: string)
	local callback = ENTER[name]
	if callback then
		callback(session)
	end
end

local function step(session: Session, dt: number)
	if session.Done then
		return
	end
	local elapsed = os.clock() - session.Start
	while true do
		local phase = session.Phases[session.PhaseIndex]
		if not phase then
			finish(session, true)
			return
		end
		if elapsed < session.PhaseStart + phase.Duration then
			break
		end
		session.PhaseStart += phase.Duration
		session.PhaseIndex += 1
		local nextPhase = session.Phases[session.PhaseIndex]
		if nextPhase then
			enter(session, nextPhase.Name)
		end
		if session.Done then
			return
		end
	end

	local now = os.clock()
	local deck = session.Deck
	if deck then
		updateDeck(deck, session.Geo.Sky, dt)
	end
	for _, bolt in session.Bolts do
		updateBolt(bolt, now)
	end
	local crack = session.Crack
	if crack then
		updateShards(crack, dt)
	end
	local rain = session.Rain
	if rain then
		rain.CFrame = CFrame.new(Workspace.CurrentCamera.CFrame.Position + Vector3.new(0, 40, 0))
	end

	local phase = session.Phases[session.PhaseIndex]
	local localT = elapsed - session.PhaseStart
	local alpha = math.clamp(localT / phase.Duration, 0, 1)
	local update = UPDATE[phase.Name]
	if update then
		update(session, localT, alpha, dt)
	end
end

-- API --------------------------------------------------------------------------------

function CrateCinematicController.SetOverlay(newOverlay: CinematicOverlay?)
	overlay = newOverlay
end

function CrateCinematicController.IsPlaying(): boolean
	return current ~= nil
end

--[[
	Corre a cinemática completa. onDone(completed) é sempre chamado uma vez:
	completed = false se foi cancelada (morte, reset, outra UI) — o artista já está
	entregue pelo servidor, isto é só apresentação.
]]
function CrateCinematicController.Play(params: CinematicParams, onDone: (completed: boolean) -> ())
	if current then
		CrateCinematicController.Cancel()
	end
	local rarity = ArtistCalc.GetRarity(params.Rarity)
	local def = ArtistCalc.GetArtist(params.ArtistId)
	local geo = computeGeometry(Players.LocalPlayer.UserId, CIN.SkyHeight)
	if not rarity or not geo then
		warn("[CrateCinematic] Sem terreno/raridade: cinemática ignorada")
		onDone(false)
		return
	end

	local trove = Trove.new()
	local folder = trove:Add(Instance.new("Folder"))
	folder.Name = FOLDER_NAME
	folder.Parent = Workspace

	local phases = CrateAnimCalc.GetPhases(params.Fast)
	local session: Session = {
		Trove = trove,
		Params = params,
		Rarity = rarity,
		ArtistName = if def then def.Name else params.ArtistId,
		Phases = phases,
		PhaseIndex = 1,
		PhaseStart = 0,
		Start = os.clock(),
		OnDone = onDone,
		Done = false,
		Geo = geo,
		Folder = folder,
		Saved = saveState(),
		Restored = false,
		HasControl = false,
		Effects = {},
		Tweens = {},
		Grading = nil,
		Deck = nil,
		Bolts = {},
		NextBolt = 1,
		Strikes = {},
		Rays = {},
		Crack = nil,
		PanePos = geo.Sky + Vector3.new(0, CIN.PaneLift, 0),
		Rain = nil,
		Sil = nil,
		Shockwave = nil,
		ColorStart = nil,
		ShakeUntil = 0,
		ShakeMagnitude = 0,
		ShakeDuration = 0,
		EndSwapped = false,
		OrbitBase = 0,
	}
	current = session

	-- Morrer / reset / sair da personagem a meio: repõe tudo
	local humanoid = session.Saved.Humanoid
	if humanoid then
		trove:Connect(humanoid.Died, function()
			CrateCinematicController.Cancel()
		end)
	end
	trove:Connect(Players.LocalPlayer.CharacterRemoving, function()
		CrateCinematicController.Cancel()
	end)
	trove:Connect(RunService.RenderStepped, function(dt: number)
		step(session, dt)
	end)

	enter(session, phases[1].Name)
end

-- "Saltar": vai direto à revelação (só se o servidor disse que pode)
function CrateCinematicController.Skip()
	local session = current
	if not session or not session.Params.CanSkip then
		return
	end
	local targetName = CrateAnimConfig.SkipToPhase
	local target = CrateAnimCalc.GetPhaseStart(session.Phases, targetName)
	local targetIndex = 0
	for index, phase in session.Phases do
		if phase.Name == targetName then
			targetIndex = index
		end
	end
	if not target or targetIndex == 0 or session.PhaseIndex >= targetIndex then
		return
	end
	clearSky(session)
	session.Shockwave = nil
	withOverlay(function(o)
		o.Flash(0.8)
	end)
	session.PhaseIndex = targetIndex
	session.PhaseStart = target
	session.Start = os.clock() - target
	enter(session, targetName)
end

-- Cancela e repõe câmara, iluminação, música e personagem de imediato
function CrateCinematicController.Cancel()
	local session = current
	if session then
		finish(session, false)
	end
end

-- Versão leve (outros jogadores) ----------------------------------------------------------

local function lightBeam(trove: Trove.Trove, folder: Instance, geo: Geometry, rarity: RarityDef, start: number)
	local beam = CinematicAssets.NewPart(
		"Beam",
		Vector3.new(LIGHT.SkyHeight, 6, 6),
		CFrame.new(geo.Landing + Vector3.new(0, LIGHT.SkyHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		rarity.Color,
		Enum.Material.Neon,
		folder
	)
	beam.Shape = Enum.PartType.Cylinder
	beam.Transparency = 1
	local light = Instance.new("PointLight")
	light.Color = rarity.Color
	light.Range = 60
	light.Brightness = 0
	light.Parent = beam
	local impactAt = LIGHT.LeapStart + LIGHT.LeapDuration
	local total = impactAt + LIGHT.RevealHold
	trove:Connect(RunService.RenderStepped, function()
		local t = Workspace:GetServerTimeNow() - start
		if t < 0 then
			return
		end
		if t >= total then
			trove:Destroy()
			return
		end
		beam.Transparency = if t < impactAt then lerp(1, 0.4, math.clamp(t / impactAt, 0, 1)) else lerp(0.4, 1, (t - impactAt) / LIGHT.RevealHold)
		light.Brightness = if t >= impactAt and t < impactAt + 0.3 then 12 else 0
	end)
end

local function lightFull(trove: Trove.Trove, folder: Instance, geo: Geometry, summon: CrateSummon, rarity: RarityDef, lowVfx: boolean)
	local deck: Deck? = nil
	local bolt: Bolt? = nil
	local crack: SkyCrack? = nil
	local silhouette: Silhouette? = nil
	local shockwave: BasePart? = nil
	local strikes: { boolean } = {}
	local panePos = geo.Sky + Vector3.new(0, CIN.PaneLift * 0.5, 0)
	local openStart = LIGHT.LeapStart - 1.6
	local crackStart = LIGHT.LeapStart - 1.0
	local shatterAt = LIGHT.LeapStart - 0.1
	local impactAt = LIGHT.LeapStart + LIGHT.LeapDuration
	local total = impactAt + LIGHT.RevealHold
	local impacted = false
	local lastClock = os.clock()

	trove:Connect(RunService.RenderStepped, function()
		local now = os.clock()
		local dt = now - lastClock
		lastClock = now
		local t = Workspace:GetServerTimeNow() - summon.StartTime
		if t < 0 then
			return
		end
		if t >= total then
			trove:Destroy()
			return
		end
		if not deck then
			deck = spawnDeck(folder, LIGHT.CloudRings, false)
			bolt = makeBolt(folder)
		end
		local currentDeck = deck
		if currentDeck then
			currentDeck.Open = math.clamp((t - openStart) / 1.2, 0, 1)
			updateDeck(currentDeck, geo.Sky, dt)
			if t >= impactAt and currentDeck.Open >= 1 then
				fadeDeck(currentDeck, math.clamp((t - impactAt) / LIGHT.RevealHold, 0, 1))
			end
		end
		local currentBolt = bolt
		if currentBolt then
			for index, time in CIN.LightningTimes do
				if not strikes[index] and t >= time and t < openStart then
					strikes[index] = true
					local from, to = strikePoints(geo, index, LIGHT.SkyHeight)
					strike(currentBolt, from, to)
					task.delay(CIN.ThunderDelay, function()
						CrateSfx.PlayAt("Thunder", geo.Landing)
					end)
				end
			end
			updateBolt(currentBolt, now)
		end
		if t >= openStart and not crack then
			crack = makeSkyCrack(folder, panePos, CIN.PaneRadius * 0.5, if lowVfx then 3 else 4, rarity)
		end
		local currentCrack = crack
		if currentCrack then
			if not currentCrack.Shattered then
				currentCrack.Pane.Transparency = lerp(1, 0.3, math.clamp((t - openStart) / 0.6, 0, 1))
				if t >= crackStart then
					growCrack(currentCrack, math.clamp((t - crackStart) / (shatterAt - crackStart), 0, 1))
				end
				if t >= shatterAt then
					shatterCrack(currentCrack, folder, if lowVfx then 4 else 8)
					CrateSfx.PlayAt("SkyShatter", geo.Landing)
				end
			end
			updateShards(currentCrack, dt)
		end
		if t >= LIGHT.LeapStart then
			if not silhouette then
				silhouette = makeSilhouette(folder, summon.ArtistId, rarity)
			end
			local currentSil = silhouette
			if currentSil then
				local alpha = math.clamp((t - LIGHT.LeapStart) / LIGHT.LeapDuration, 0, 1)
				placeRig(currentSil, panePos:Lerp(geo.Landing, easeInQuad(alpha)), geo.CamBase)
				if t >= impactAt then
					colorSilhouette(currentSil, math.clamp((t - impactAt) / CIN.ColorTweenTime, 0, 1))
				end
			end
		end
		if t >= impactAt and not impacted then
			impacted = true
			shockwave = spawnImpact(folder, geo.Landing, rarity, lowVfx, false)
			CrateSfx.PlayAt("Impact", geo.Landing)
			local currentSil = silhouette
			if currentSil then
				addAura(currentSil, rarity, true)
			end
		end
		local currentShock = shockwave
		if currentShock then
			updateShockwave(currentShock, math.clamp((t - impactAt) / 1, 0, 1), CIN.CraterRadius * 4)
		end
	end)
end

function CrateCinematicController.PlayLight(summon: CrateSummon, lowVfx: boolean)
	if summon.UserId == Players.LocalPlayer.UserId or lightSessions >= MAX_LIGHT_SESSIONS then
		return
	end
	local rarity = ArtistCalc.GetRarity(summon.Rarity)
	local geo = computeGeometry(summon.UserId, LIGHT.SkyHeight)
	local camera = Workspace.CurrentCamera
	if not rarity or not geo or not camera then
		return
	end
	local distance = (camera.CFrame.Position - geo.Landing).Magnitude
	if distance > LodConfig.Cinematic.BeamDistance then
		return
	end

	lightSessions += 1
	local trove = Trove.new()
	trove:Add(function()
		lightSessions -= 1
	end)
	local folder = trove:Add(Instance.new("Folder"))
	folder.Name = FOLDER_NAME .. "_Light"
	folder.Parent = Workspace

	if distance > LodConfig.Cinematic.FullDistance then
		lightBeam(trove, folder, geo, rarity, summon.StartTime)
	else
		lightFull(trove, folder, geo, summon, rarity, lowVfx)
	end
end

return CrateCinematicController
