--!strict
--[[
	CrateCinematicController
	Cinemática do ultra-raro (carta mistério), só apresentação e sempre local:

	  Play(params, onDone)  versão completa para quem abriu: câmara Scriptable por cima do
	                        próprio terreno, timeline de Config/CrateAnimation (Fade → Storm →
	                        SkyOpen → Rift → Leap → Impact → Reveal → End)
	  PlayLight(summon)     versão leve para os outros jogadores, por cima do terreno de quem
	                        abriu, sem tocar na câmara nem na iluminação, com LOD por distância

	O céu (o sol fica escondido do início ao fim):
	  - Storm:   o céu azul fecha-se: as nuvens 3D vêm do horizonte até ao centro, com um teto
	             contínuo de placas por cima (sem buracos) e Terrain.Clouds a 100% (só neste
	             cliente); depois chuva e relâmpagos grossos com ramificações e duplo clarão
	  - SkyOpen: nuvens e teto afastam-se do centro e volta o céu azul normal
	  - SkyOpen: (abertura em redemoinho: anéis de dentro primeiro, nuvens a subir e a
	             inclinar, teto a sair depois, sopro de névoa)
	  - Rift:    alguém do outro lado dá pancadas no céu (BREACH.Hits): cada pancada abre uma
	             teia de rachas e arranca um pedaço — os fragmentos azuis caem e fica aberto
	             "outro mundo" (preto-roxo com estrelas e nebulosa, contorno na cor da
	             raridade). O buraco cresce a cada pancada; a última abre o centro e o
	             artista sai daí

	Regras:
	  - Lighting/Sky/Terrain.Clouds: só efeitos criados aqui + propriedades guardadas e
	    repostas EXATAMENTE no fim
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
local StarterGui = game:GetService("StarterGui")
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
	Gui: ScreenGui, -- fica visível quando a restante interface é escondida
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
	Rings: { number }, -- anel de cada nuvem (1 = centro)
	Yaws: { number }, -- rotação própria de cada nuvem (variedade)
	RingCount: number,
	-- Todas as peças das nuvens + placas, movidas com um único Workspace:BulkMoveTo
	Parts: { BasePart },
	Offsets: { CFrame }, -- peça relativa ao pivot da sua nuvem
	First: { number }, -- 1.ª peça de cada nuvem em Parts
	Last: { number },
	CFrames: { CFrame }, -- reutilizado a cada frame
	Plates: { BasePart },
	PlateAngles: { number },
	Spin: number,
	Offset: number, -- fecho: studs para fora da posição fechada (grande -> 0)
	Open: number, -- abertura 0..1 (anéis de dentro primeiro, em redemoinho)
}

type Bolt = {
	Core: { BasePart }, -- núcleo branco
	Glow: { BasePart }, -- brilho azulado à volta (mesma geometria, mais largo)
	Reveal: { number }, -- 0..1: quando cada segmento aparece enquanto o relâmpago se desenha
	Used: { boolean }, -- segmento faz parte do relâmpago atual
	Shown: { boolean },
	Lights: { PointLight },
	StrikeTime: number,
	Active: boolean,
}

-- A brecha no céu: malha de fragmentos (triângulos), rachas nas arestas, outro mundo
-- no lugar de cada fragmento que cai
type Breach = {
	Center: Vector3,
	Axis: Vector3, -- horizontal, perpendicular à câmara
	Side: Vector3, -- no plano do céu, na direção da câmara
	Scale: number,
	LowVfx: boolean,
	Rarity: RarityDef,
	Folder: Folder,
	Burst: ParticleEmitter,
	BurstAnchor: BasePart,
	-- Uma luz e um feixe por pancada, no sítio onde o céu partiu
	HitLights: { PointLight },
	HitBeams: { BasePart },
	HitStart: { number },
	HitOpened: { number }, -- fragmentos já caídos de cada pancada
	TriHit: { number }, -- pancada que fez cair cada triângulo (0 = nenhuma)
	Points: { [number]: Vector3 },
	-- Triângulos (índices dos vértices em Points)
	TriA: { number },
	TriB: { number },
	TriC: { number },
	TriCentroid: { Vector3 },
	TriJag: { number }, -- -1..1: irregularidade da borda
	TriOpenAt: { number }, -- os.clock() em que cai (math.huge = ainda não marcado)
	TriOpened: { boolean },
	TriEdges: { { number } },
	-- Arestas
	EdgeA: { number },
	EdgeB: { number },
	EdgeTris: { { number } },
	EdgeState: { number }, -- 0 nada, 1 racha, 2 contorno, 3 escondida
	EdgeShowAt: { number },
	EdgeParts: { [number]: BasePart },
	HitsDone: number,
	Opened: number,
	-- Fragmentos a cair (2 cunhas cada)
	ShardA: { BasePart },
	ShardB: { BasePart },
	OffsetA: { CFrame },
	OffsetB: { CFrame },
	ShardCF: { CFrame },
	ShardVel: { Vector3 },
	ShardSpin: { number },
	ShardBorn: { number },
	ShardAlive: { boolean },
}
type SavedState = {
	HiddenGuis: { ScreenGui }, -- interface do jogo escondida durante a cinemática
	CoreGuis: { [Enum.CoreGuiType]: boolean }, -- chat, lista de jogadores, etc.
	Lighting: { [string]: unknown },
	Atmosphere: Atmosphere,
	AtmosphereCreated: boolean,
	AtmosphereProps: { [string]: unknown },
	Clouds: Clouds,
	CloudsCreated: boolean,
	CloudsProps: { [string]: unknown },
	Sky: Sky,
	SkyCreated: boolean,
	SkyProps: { [string]: unknown },
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
	Breach: Breach?,
	BreachPos: Vector3,
	Rain: BasePart?,
	Sil: Silhouette?,
	Shockwave: BasePart?,
	ColorStart: number?,
	ShakeUntil: number,
	ShakeMagnitude: number,
	ShakeDuration: number,
	BlendFrom: CFrame?, -- plano anterior (transição suave entre fases)
	BlendStart: number,
	BlendTime: number,
	FovKick: number, -- "zoom" momentâneo das pancadas (graus)
	EndSwapped: boolean,
	OrbitBase: number,
}

local CrateCinematicController = {}

local CIN = CrateAnimConfig.Cinematic
local BREACH = CIN.Breach
local CEILING = CIN.Ceiling
local LIGHT = CrateAnimConfig.Light
local FOLDER_NAME = "FE_Cinematic"
local MAX_LIGHT_SESSIONS = 2
local BOLT_SEGMENTS = CIN.BoltSegments
local BRANCH_SEGMENTS = CIN.BranchSegments
local BLACK = Color3.new(0, 0, 0)

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

local function addEllipsoidMesh(part: BasePart)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
end

-- Início de uma fase na timeline completa (para sincronizar a versão leve)
local function phaseStart(name: string): number
	return CrateAnimCalc.GetPhaseStart(CrateAnimConfig.Timeline, name) or 0
end

local function phaseDuration(name: string): number
	for _, phase in CrateAnimConfig.Timeline do
		if phase.Name == name then
			return phase.Duration
		end
	end
	return 1
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

local function spawnDeck(folder: Instance, ringCount: number, withMist: boolean, withCeiling: boolean): Deck
	local deck: Deck = {
		Models = {},
		Angles = {},
		Radii = {},
		Heights = {},
		Rings = {},
		Yaws = {},
		RingCount = math.min(ringCount, #CIN.CloudRings),
		Parts = {},
		Offsets = {},
		First = {},
		Last = {},
		CFrames = {},
		Plates = {},
		PlateAngles = {},
		Spin = 0,
		Offset = CIN.CloudCloseDistance,
		Open = 0,
	}
	for ringIndex = 1, deck.RingCount do
		local ring = CIN.CloudRings[ringIndex]
		for index = 1, ring.Count do
			local cloud = CinematicAssets.Get("Cloud")
			cloud:ScaleTo(rng:NextNumber(CIN.CloudScale.Min, CIN.CloudScale.Max))
			-- Guarda cada peça relativa ao pivot (movidas em bloco no updateDeck)
			local pivotInverse = cloud:GetPivot():Inverse()
			table.insert(deck.First, #deck.Parts + 1)
			for _, descendant in cloud:GetDescendants() do
				if descendant:IsA("BasePart") then
					table.insert(deck.Parts, descendant)
					table.insert(deck.Offsets, pivotInverse * descendant.CFrame)
				end
			end
			table.insert(deck.Last, #deck.Parts)
			cloud.Parent = folder
			table.insert(deck.Models, cloud)
			table.insert(deck.Yaws, rng:NextNumber(0, math.pi * 2))
			table.insert(deck.Angles, (index / ring.Count) * math.pi * 2 + ringIndex * 0.37 + rng:NextNumber(-0.1, 0.1))
			table.insert(deck.Radii, ring.Radius + rng:NextNumber(-4, 4))
			-- Os anéis de fora descem só um pouco (sem nuvens a espetar para baixo)
			table.insert(deck.Heights, -ringIndex * 2 + rng:NextNumber(-2, 2))
			table.insert(deck.Rings, ringIndex)
			if withMist and #deck.Models % CIN.CloudMistEvery == 0 then
				local mist = cloud:FindFirstChild("Mist", true)
				if mist and mist:IsA("ParticleEmitter") then
					mist.Rate = 1.2
					mist:Emit(3)
				end
			end
		end
	end
	if withCeiling then
		for index = 1, CEILING.Plates do
			local plate = CinematicAssets.NewPart(
				"Ceiling" .. index,
				Vector3.new(CEILING.Width, CEILING.Thickness, CEILING.Length),
				CFrame.new(),
				CEILING.Color,
				Enum.Material.SmoothPlastic,
				folder
			)
			table.insert(deck.Plates, plate)
			table.insert(deck.PlateAngles, (index / CEILING.Plates) * math.pi * 2)
		end
	end
	return deck
end

local function easeInOutSine(t: number): number
	return -(math.cos(math.pi * t) - 1) / 2
end

-- Abertura de um anel (0..1): os de dentro começam primeiro
local function ringOpen(deck: Deck, ring: number): number
	local delay = CIN.CloudOpenRingDelay * (ring - 1)
	local span = 1 - CIN.CloudOpenRingDelay * (deck.RingCount - 1)
	return easeInOutSine(math.clamp((deck.Open - delay) / math.max(span, 0.1), 0, 1))
end

local function updateDeck(deck: Deck, center: Vector3, dt: number)
	-- Redemoinho: acelera a meio da abertura e volta a acalmar
	deck.Spin += CIN.CloudSpin * dt * (1 + CIN.CloudOpenSwirl * math.sin(math.pi * math.clamp(deck.Open, 0, 1)))
	local offset = deck.Offset
	local cframes = deck.CFrames
	for index in deck.Models do
		local ring = deck.Rings[index]
		local open = if deck.Open > 0 then ringOpen(deck, ring) else 0
		local angle = deck.Angles[index] + deck.Spin * (1 + 0.15 * (deck.RingCount - ring))
		local radius = deck.Radii[index] + offset
		local height = deck.Heights[index]
		-- As nuvens de dentro do círculo vão para a borda exata (buraco redondo e limpo)
		local rim = CIN.CloudOpenRadius + CIN.CloudRimLayer * (ring - 1)
		if open > 0 and radius < rim then
			radius = lerp(radius, rim, open)
			height = lerp(height, 0, open)
		end
		-- Sempre na horizontal (inclinadas pareciam espetadas)
		local pivot = CFrame.new(center + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius))
			* CFrame.Angles(0, deck.Yaws[index] - angle, 0)
		for part = deck.First[index], deck.Last[index] do
			cframes[part] = pivot * deck.Offsets[part]
		end
	end
	Workspace:BulkMoveTo(deck.Parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	-- O teto cinzento acompanha o fecho; na abertura não se mexe (desaparece: fadeCeiling)
	local ceilingCenter = center + Vector3.new(0, CEILING.Lift, 0)
	for index, plate in deck.Plates do
		local angle = deck.PlateAngles[index] + deck.Spin
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local position = ceilingCenter + direction * (offset + CEILING.Length / 2)
		plate.CFrame = CFrame.lookAt(position, position + direction)
	end
end

-- Teto cinzento: 0 = visível, 1 = desaparecido (na transição só se veem nuvens)
local function fadeCeiling(deck: Deck, alpha: number)
	for _, plate in deck.Plates do
		plate.Transparency = alpha
	end
end

-- Sopro de névoa das nuvens de dentro quando o céu começa a abrir
local function puffDeck(deck: Deck, rings: number)
	for index, cloud in deck.Models do
		if deck.Rings[index] <= rings then
			local mist = cloud:FindFirstChild("Mist", true)
			if mist and mist:IsA("ParticleEmitter") then
				mist:Emit(3)
			end
		end
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
	for _, plate in deck.Plates do
		plate.Transparency = math.max(plate.Transparency, alpha)
	end
end

local function destroyDeck(deck: Deck)
	for _, cloud in deck.Models do
		cloud:Destroy()
	end
	for _, plate in deck.Plates do
		plate:Destroy()
	end
	table.clear(deck.Models)
	table.clear(deck.Plates)
end

-- Relâmpagos -----------------------------------------------------------------------

local BOLT_GLOW_TRANSPARENCY = 0.55
local BOLT_LIFETIME = 0.42

local function makeBolt(folder: Instance): Bolt
	local bolt: Bolt = { Core = {}, Glow = {}, Reveal = {}, Used = {}, Shown = {}, Lights = {}, StrikeTime = -math.huge, Active = false }
	for index = 1, BOLT_SEGMENTS + CIN.BoltBranches * BRANCH_SEGMENTS do
		local core = CinematicAssets.NewPart("BoltCore" .. index, Vector3.one, CFrame.new(), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, folder)
		core.Transparency = 1
		local glow = CinematicAssets.NewPart("BoltGlow" .. index, Vector3.one, CFrame.new(), Color3.fromRGB(150, 175, 255), Enum.Material.Neon, folder)
		glow.Transparency = 1
		table.insert(bolt.Core, core)
		table.insert(bolt.Glow, glow)
		table.insert(bolt.Reveal, 0)
		table.insert(bolt.Used, false)
		table.insert(bolt.Shown, false)
	end
	for _ = 1, 2 do
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(200, 215, 255)
		light.Range = 60
		light.Brightness = 0
		light.Shadows = false
		light.Parent = bolt.Core[1]
		table.insert(bolt.Lights, light)
	end
	return bolt
end

local function setBoltSegment(bolt: Bolt, slot: number, from: Vector3, to: Vector3, width: number, reveal: number)
	placeSegment(bolt.Core[slot], from, to, width, width)
	placeSegment(bolt.Glow[slot], from, to, width * CIN.BoltGlow, width * CIN.BoltGlow)
	bolt.Reveal[slot] = reveal
	bolt.Used[slot] = true
end

-- Relâmpago de `from` até `to`: canal principal em ziguezague + ramificações que saem dele
local function strike(bolt: Bolt, from: Vector3, to: Vector3)
	local direction = to - from
	local length = direction.Magnitude
	local side = direction:Cross(Vector3.yAxis)
	if side.Magnitude < 0.01 then
		side = Vector3.xAxis
	end
	side = side.Unit
	local up = side:Cross(direction.Unit)
	local jitter = length * 0.05

	for slot in bolt.Used do
		bolt.Used[slot] = false
	end

	local vertices: { Vector3 } = { from }
	for index = 1, BOLT_SEGMENTS do
		local point = from + direction * (index / BOLT_SEGMENTS)
		if index < BOLT_SEGMENTS then
			point += side * rng:NextNumber(-jitter, jitter) + up * rng:NextNumber(-jitter, jitter)
		end
		table.insert(vertices, point)
		-- O canal afina ligeiramente para baixo
		local width = CIN.BoltWidth * lerp(1.2, 0.8, index / BOLT_SEGMENTS)
		setBoltSegment(bolt, index, vertices[index], point, width, (index - 1) / BOLT_SEGMENTS)
	end

	local slot = BOLT_SEGMENTS
	for branch = 1, CIN.BoltBranches do
		local rootIndex = rng:NextInteger(2, BOLT_SEGMENTS - 2)
		local root = vertices[rootIndex]
		local sign = if branch % 2 == 0 then 1 else -1
		local branchDir = (direction.Unit + side * sign * rng:NextNumber(0.6, 1.2) + up * rng:NextNumber(-0.4, 0.4)).Unit
		local branchLength = length * rng:NextNumber(0.2, 0.35)
		local previous = root
		for step = 1, BRANCH_SEGMENTS do
			local point = previous + branchDir * (branchLength / BRANCH_SEGMENTS) + side * rng:NextNumber(-jitter, jitter) * 0.5
			slot += 1
			local width = CIN.BoltWidth * lerp(0.6, 0.25, step / BRANCH_SEGMENTS)
			setBoltSegment(bolt, slot, previous, point, width, (rootIndex - 1 + step * 0.6) / BOLT_SEGMENTS)
			previous = point
		end
	end
	bolt.Lights[1].Parent = bolt.Core[1] -- topo: ilumina as nuvens
	bolt.Lights[2].Parent = bolt.Core[math.floor(BOLT_SEGMENTS * 0.6)]
	bolt.StrikeTime = os.clock()
	bolt.Active = true
end

-- Desenha-se de cima para baixo em BoltDrawTime; depois 3 clarões a enfraquecer
local function boltIntensity(age: number): number
	local draw = CIN.BoltDrawTime
	if age < draw + 0.12 then
		return 1
	elseif age < draw + 0.16 then
		return 0
	elseif age < draw + 0.26 then
		return 0.85
	elseif age < draw + 0.3 then
		return 0
	elseif age < BOLT_LIFETIME then
		return 0.45
	end
	return 0
end

local function updateBolt(bolt: Bolt, now: number)
	if not bolt.Active then
		return
	end
	local age = now - bolt.StrikeTime
	local intensity = boltIntensity(age)
	local drawn = math.clamp(age / CIN.BoltDrawTime, 0, 1)
	for slot, core in bolt.Core do
		local show = bolt.Used[slot] and intensity > 0 and drawn >= bolt.Reveal[slot]
		if show ~= bolt.Shown[slot] then
			bolt.Shown[slot] = show
			core.Transparency = if show then 0 else 1
		end
		if show then
			bolt.Glow[slot].Transparency = 1 - (1 - BOLT_GLOW_TRANSPARENCY) * intensity
		elseif bolt.Glow[slot].Transparency < 1 then
			bolt.Glow[slot].Transparency = 1
		end
	end
	for _, light in bolt.Lights do
		light.Brightness = 16 * intensity
	end
	if age >= BOLT_LIFETIME then
		bolt.Active = false
	end
end

local function destroyBolt(bolt: Bolt)
	for _, part in bolt.Core do
		part:Destroy()
	end
	for _, part in bolt.Glow do
		part:Destroy()
	end
	table.clear(bolt.Core)
	table.clear(bolt.Glow)
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

-- Céu a partir: malha de fragmentos, rachas nas arestas e "outro mundo" ----------------
--[[
	O céu da brecha é uma malha de triângulos irregulares (como vidro). Em cada pancada:
	  1) as arestas à volta acendem-se como rachas, a espalhar-se do ponto de impacto
	  2) os triângulos perto caem (do centro para fora); no lugar de cada um fica um
	     triângulo de "outro mundo" com a mesma forma -> buraco angular e partido
	  3) as arestas entre um triângulo aberto e um fechado brilham na cor da raridade
	     (contorno da brecha); as de dentro desaparecem
	Visto do chão: fragmentos (-0.9) > rachas/contorno (-0.6) > outro mundo (-0.4).
]]

local DROP_EDGE = 0.6
local DROP_VOID = 0.4
local DROP_SHARD = 0.9

local EDGE_NONE = 0
local EDGE_CRACK = 1
local EDGE_RIM = 2
local EDGE_HIDDEN = 3

-- Triângulo arbitrário com duas WedgeParts (espessura no eixo X das cunhas)
local function makeTriangle(a: Vector3, b: Vector3, c: Vector3, color: Color3, material: Enum.Material, parent: Instance): (WedgePart, WedgePart)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))

	local function wedge(): WedgePart
		local part = Instance.new("WedgePart")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Color = color
		part.Material = material
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = parent
		return part
	end
	local w1 = wedge()
	w1.Size = Vector3.new(0.2, math.max(height, 0.05), math.max(math.abs(ab:Dot(back)), 0.05))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	local w2 = wedge()
	w2.Size = Vector3.new(0.2, math.max(height, 0.05), math.max(math.abs(ac:Dot(back)), 0.05))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
	return w1, w2
end

-- `axis`: horizontal, perpendicular à câmara
local function makeBreach(folder: Instance, center: Vector3, axis: Vector3, scale: number, rarity: RarityDef, lowVfx: boolean): Breach
	local root = Instance.new("Folder")
	root.Name = "Breach"
	root.Parent = folder

	local burstAnchor = CinematicAssets.NewPart("BreachBurst", Vector3.one, CFrame.new(center), BLACK, Enum.Material.SmoothPlastic, root)
	burstAnchor.Transparency = 1
	-- Pó/estilhaços pequenos a saltar em cada pancada
	local burst = newEmitter(burstAnchor, Color3.new(1, 1, 1):Lerp(rarity.Color, 0.3))
	burst.Lifetime = NumberRange.new(0.5, 0.9)
	burst.Speed = NumberRange.new(12, 28)
	burst.SpreadAngle = Vector2.new(70, 70)
	burst.EmissionDirection = Enum.NormalId.Bottom
	burst.Acceleration = Vector3.new(0, -40, 0)
	burst.Size = NumberSequence.new(0.7 * scale + 0.2, 0)

	local side = axis:Cross(Vector3.yAxis).Unit
	local breach: Breach = {
		Center = center,
		Axis = axis,
		Side = side,
		Scale = scale,
		LowVfx = lowVfx,
		Rarity = rarity,
		Folder = root,
		Burst = burst,
		HitLights = {},
		HitBeams = {},
		HitStart = {},
		HitOpened = {},
		TriHit = {},
		BurstAnchor = burstAnchor,
		Points = {},
		TriA = {},
		TriB = {},
		TriC = {},
		TriCentroid = {},
		TriJag = {},
		TriOpenAt = {},
		TriOpened = {},
		TriEdges = {},
		EdgeA = {},
		EdgeB = {},
		EdgeTris = {},
		EdgeState = {},
		EdgeShowAt = {},
		EdgeParts = {},
		HitsDone = 0,
		Opened = 0,
		ShardA = {},
		ShardB = {},
		OffsetA = {},
		OffsetB = {},
		ShardCF = {},
		ShardVel = {},
		ShardSpin = {},
		ShardBorn = {},
		ShardAlive = {},
	}

	-- Malha: grelha com pontos desalinhados, cada célula dividida em 2 triângulos
	local spacing = (if lowVfx then BREACH.GridSpacingLow else BREACH.GridSpacing) * scale
	local radius = BREACH.GridRadius * scale
	local cells = math.ceil(radius / spacing)
	local width = cells * 2 + 1
	local function pointIndex(i: number, j: number): number
		return (i + cells) * width + (j + cells) + 1
	end
	for i = -cells, cells do
		for j = -cells, cells do
			local edge = math.abs(i) == cells or math.abs(j) == cells
			local u = i * spacing + (if edge then 0 else rng:NextNumber(-0.35, 0.35) * spacing)
			local v = j * spacing + (if edge then 0 else rng:NextNumber(-0.35, 0.35) * spacing)
			breach.Points[pointIndex(i, j)] = center + axis * u + side * v
		end
	end

	local edgeIndex: { [string]: number } = {}
	local function edgeOf(a: number, b: number, tri: number): number
		local low, high = math.min(a, b), math.max(a, b)
		local key = low .. "," .. high
		local index = edgeIndex[key]
		if not index then
			table.insert(breach.EdgeA, low)
			table.insert(breach.EdgeB, high)
			table.insert(breach.EdgeTris, {})
			table.insert(breach.EdgeState, EDGE_NONE)
			table.insert(breach.EdgeShowAt, math.huge)
			index = #breach.EdgeA
			edgeIndex[key] = index
		end
		table.insert(breach.EdgeTris[index], tri)
		return index
	end
	local function addTri(a: number, b: number, c: number)
		local centroid = (breach.Points[a] + breach.Points[b] + breach.Points[c]) / 3
		if (centroid - center).Magnitude > radius then
			return
		end
		table.insert(breach.TriA, a)
		table.insert(breach.TriB, b)
		table.insert(breach.TriC, c)
		table.insert(breach.TriCentroid, centroid)
		table.insert(breach.TriJag, rng:NextNumber(-1, 1))
		table.insert(breach.TriOpenAt, math.huge)
		table.insert(breach.TriOpened, false)
		table.insert(breach.TriHit, 0)
		local tri = #breach.TriA
		table.insert(breach.TriEdges, { edgeOf(a, b, tri), edgeOf(b, c, tri), edgeOf(c, a, tri) })
	end
	for i = -cells, cells - 1 do
		for j = -cells, cells - 1 do
			local p00, p10, p01, p11 = pointIndex(i, j), pointIndex(i + 1, j), pointIndex(i, j + 1), pointIndex(i + 1, j + 1)
			if rng:NextNumber() < 0.5 then
				addTri(p00, p10, p11)
				addTri(p00, p11, p01)
			else
				addTri(p00, p10, p01)
				addTri(p10, p11, p01)
			end
		end
	end
	return breach
end

local function edgeMidpoint(breach: Breach, edge: number): Vector3
	return (breach.Points[breach.EdgeA[edge]] + breach.Points[breach.EdgeB[edge]]) / 2
end

-- Cria/atualiza a peça de uma aresta conforme o estado (racha, contorno ou escondida)
local function setEdgeState(breach: Breach, edge: number, state: number)
	breach.EdgeState[edge] = state
	local part = breach.EdgeParts[edge]
	if state == EDGE_HIDDEN or state == EDGE_NONE then
		if part then
			part.Transparency = 1
		end
		return
	end
	local from = breach.Points[breach.EdgeA[edge]] - Vector3.new(0, DROP_EDGE, 0)
	local to = breach.Points[breach.EdgeB[edge]] - Vector3.new(0, DROP_EDGE, 0)
	local edgePart: BasePart = part or CinematicAssets.NewPart("BreachEdge", Vector3.one, CFrame.new(from), BREACH.CrackColor, Enum.Material.Neon, breach.Folder)
	breach.EdgeParts[edge] = edgePart
	if state == EDGE_RIM then
		placeSegment(edgePart, from, to, 0.6 * breach.Scale + 0.2, 0.25)
		edgePart.Color = breach.Rarity.Color
	else
		placeSegment(edgePart, from, to, 0.22 * breach.Scale + 0.08, 0.2)
		edgePart.Color = BREACH.CrackColor
	end
	edgePart.Transparency = 0
end

-- Depois de um triângulo abrir: as arestas com os dois lados abertos somem; as da borda brilham
local function refreshTriEdges(breach: Breach, tri: number)
	for _, edge in breach.TriEdges[tri] do
		local openSides = 0
		for _, other in breach.EdgeTris[edge] do
			if breach.TriOpened[other] then
				openSides += 1
			end
		end
		local closedSides = #breach.EdgeTris[edge] - openSides
		setEdgeState(breach, edge, if closedSides == 0 and #breach.EdgeTris[edge] > 1 then EDGE_HIDDEN else EDGE_RIM)
	end
end

-- "Outro mundo" num triângulo aberto: estrelas a cintilar e (às vezes) nebulosa a rodar
local function addOtherWorld(host: BasePart, rarity: RarityDef, withNebula: boolean, scale: number)
	local stars = Instance.new("ParticleEmitter")
	stars.Name = "Stars"
	stars.Shape = Enum.ParticleEmitterShape.Box
	stars.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 170, 255))
	stars.LightEmission = 1
	stars.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.4 * scale + 0.15), NumberSequenceKeypoint.new(1, 0) })
	stars.Lifetime = NumberRange.new(1, 2)
	stars.Speed = NumberRange.new(0, 0.2)
	stars.Rate = 6
	stars.Parent = host
	stars:Emit(3)
	if withNebula then
		local nebula = Instance.new("ParticleEmitter")
		nebula.Name = "Nebula"
		nebula.Shape = Enum.ParticleEmitterShape.Box
		nebula.Texture = "rbxasset://textures/particles/smoke_main.dds"
		nebula.Color = ColorSequence.new(rarity.Color, BREACH.WorldTint)
		nebula.LightEmission = 0.8
		nebula.Size = NumberSequence.new(6 * scale + 2, 10 * scale + 3)
		nebula.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.72), NumberSequenceKeypoint.new(1, 1) })
		nebula.Lifetime = NumberRange.new(2, 3)
		nebula.Speed = NumberRange.new(0.2, 0.6)
		nebula.RotSpeed = NumberRange.new(-30, 30)
		nebula.Rate = 2
		nebula.Parent = host
		nebula:Emit(1)
	end
end

-- Um triângulo cai: fica o outro mundo no lugar e o fragmento de céu cai a rodar
local function openTri(breach: Breach, tri: number, now: number)
	breach.TriOpened[tri] = true
	breach.Opened += 1
	local hit = breach.TriHit[tri]
	if hit > 0 then
		breach.HitOpened[hit] += 1
	end
	local a = breach.Points[breach.TriA[tri]]
	local b = breach.Points[breach.TriB[tri]]
	local c = breach.Points[breach.TriC[tri]]
	local voidDrop = Vector3.new(0, DROP_VOID, 0)
	local voidColor = BREACH.VoidColors[rng:NextInteger(1, #BREACH.VoidColors)]
	local v1, _v2 = makeTriangle(a - voidDrop, b - voidDrop, c - voidDrop, voidColor, Enum.Material.Neon, breach.Folder)
	if not breach.LowVfx and breach.Opened % BREACH.StarsEvery == 0 then
		addOtherWorld(v1, breach.Rarity, breach.Opened % BREACH.NebulaEvery == 0, breach.Scale)
	end

	-- Fragmento a cair (as duas cunhas movem-se juntas à volta do centro do triângulo)
	local shardDrop = Vector3.new(0, DROP_SHARD, 0)
	local s1, s2 = makeTriangle(a - shardDrop, b - shardDrop, c - shardDrop, BREACH.ShardColor, Enum.Material.SmoothPlastic, breach.Folder)
	local centroid = breach.TriCentroid[tri] - shardDrop
	local pivot = CFrame.new(centroid)
	local outward = centroid - breach.Center
	local flat = Vector3.new(outward.X, 0, outward.Z)
	local direction = if flat.Magnitude > 0.01 then flat.Unit else breach.Axis
	table.insert(breach.ShardA, s1)
	table.insert(breach.ShardB, s2)
	table.insert(breach.OffsetA, pivot:Inverse() * s1.CFrame)
	table.insert(breach.OffsetB, pivot:Inverse() * s2.CFrame)
	table.insert(breach.ShardCF, pivot)
	table.insert(breach.ShardVel, direction * BREACH.ShardSpeed * rng:NextNumber(0.15, 0.6) * breach.Scale - Vector3.new(0, rng:NextNumber(6, 18), 0))
	table.insert(breach.ShardSpin, rng:NextNumber(-5, 5))
	table.insert(breach.ShardBorn, now)
	table.insert(breach.ShardAlive, true)

	refreshTriEdges(breach, tri)
end

-- Luz e feixe da pancada `index`, no ponto onde o céu partiu (acendem quando caem os
-- primeiros fragmentos dessa pancada)
local function addHitLight(breach: Breach, index: number, point: Vector3, now: number)
	local anchor = CinematicAssets.NewPart("HitLight" .. index, Vector3.one, CFrame.new(point - Vector3.new(0, DROP_SHARD + 1, 0)), BLACK, Enum.Material.SmoothPlastic, breach.Folder)
	anchor.Transparency = 1
	local light = Instance.new("PointLight")
	light.Color = breach.Rarity.Color:Lerp(BREACH.WorldTint, 0.5)
	light.Range = BREACH.HitLightRange * math.max(breach.Scale, 0.6)
	light.Brightness = 0
	light.Shadows = false
	light.Parent = anchor
	breach.HitLights[index] = light
	breach.HitStart[index] = now
	breach.HitOpened[index] = 0
	if not breach.LowVfx and index <= BREACH.Beams then
		local top = point - Vector3.new(0, DROP_VOID + 0.2, 0)
		local bottom = top - Vector3.new(rng:NextNumber(-8, 8), BREACH.BeamLength * breach.Scale, rng:NextNumber(-8, 8))
		local beam = CinematicAssets.NewPart("HitBeam" .. index, Vector3.one, CFrame.new(top), breach.Rarity.Color:Lerp(BREACH.WorldTint, 0.4), Enum.Material.Neon, breach.Folder)
		local width = (3 + 3 * BREACH.Hits[index].Size) * breach.Scale
		placeSegment(beam, top, bottom, width, width)
		beam.Transparency = 1
		breach.HitBeams[index] = beam
	end
end

-- Dá a pancada `index` de BREACH.Hits: rachas nas arestas + fragmentos a cair
local function hitBreach(breach: Breach, index: number, now: number)
	local hit = BREACH.Hits[index]
	local spread = BREACH.Spread * breach.Scale
	local point = breach.Center + breach.Axis * (hit.X * spread) + breach.Side * (hit.Y * spread)
	local crackRadius = BREACH.CrackRadius * hit.Size * breach.Scale
	local patchRadius = BREACH.PatchRadius * hit.Size * breach.Scale

	for edge, state in breach.EdgeState do
		if state == EDGE_NONE then
			local distance = (edgeMidpoint(breach, edge) - point).Magnitude
			if distance <= crackRadius * rng:NextNumber(0.75, 1) then
				breach.EdgeShowAt[edge] = math.min(breach.EdgeShowAt[edge], now + distance / crackRadius * BREACH.CrackGrowTime)
			end
		end
	end
	for tri, opened in breach.TriOpened do
		if not opened then
			local distance = (breach.TriCentroid[tri] - point).Magnitude
			local reach = patchRadius * (1 + BREACH.Jagged * breach.TriJag[tri])
			if distance <= reach then
				local openAt = now + distance / math.max(reach, 0.1) * BREACH.PatchOpenTime
				if openAt < breach.TriOpenAt[tri] then
					breach.TriOpenAt[tri] = openAt
					breach.TriHit[tri] = index
				end
			end
		end
	end

	breach.BurstAnchor.CFrame = CFrame.new(point - Vector3.new(0, DROP_SHARD, 0))
	breach.Burst:Emit(if breach.LowVfx then 6 else math.floor(10 + 10 * hit.Size))
	addHitLight(breach, index, point, now)
	breach.HitsDone = index
end

-- Todas as pancadas que faltam, de uma vez (se a fase for saltada/encurtada)
local function finishBreach(breach: Breach, now: number)
	for index = breach.HitsDone + 1, #BREACH.Hits do
		hitBreach(breach, index, now - BREACH.PatchOpenTime)
	end
	for tri, openAt in breach.TriOpenAt do
		if not breach.TriOpened[tri] and openAt < math.huge then
			openTri(breach, tri, now)
		end
	end
end

local function updateBreach(breach: Breach, now: number, dt: number)
	-- Rachas a espalharem-se
	for edge, showAt in breach.EdgeShowAt do
		if showAt <= now then
			breach.EdgeShowAt[edge] = math.huge
			if breach.EdgeState[edge] == EDGE_NONE then
				setEdgeState(breach, edge, EDGE_CRACK)
			end
		end
	end
	-- Fragmentos a cair (do centro de cada pancada para fora)
	for tri, openAt in breach.TriOpenAt do
		if openAt <= now and not breach.TriOpened[tri] then
			breach.TriOpenAt[tri] = math.huge
			openTri(breach, tri, now)
		end
	end
	-- Luz de cada pancada: acende forte quando os seus fragmentos caem, depois fica a
	-- brilhar (mais quanto maior o buraco que abriu) e tremeluz
	for index, light in breach.HitLights do
		local opened = breach.HitOpened[index]
		local beam = breach.HitBeams[index]
		if opened > 0 then
			local age = now - breach.HitStart[index]
			local flareFactor = math.max(0, 1 - age / 0.7)
			local glow = math.min(BREACH.HitLightGlow + opened * 0.08, 6)
			local flicker = 0.8 + 0.2 * math.noise(now * 7, index * 3.1)
			light.Brightness = math.max(glow * flicker, BREACH.HitLightFlare * flareFactor)
			if beam then
				-- Mais forte no momento da quebra, depois fica suave a tremeluzir
				beam.Transparency = math.min(0.84 + 0.06 * math.noise(now * 2, index), 1 - 0.45 * flareFactor)
			end
		else
			light.Brightness = 0
			if beam then
				beam.Transparency = 1
			end
		end
	end
	for index, alive in breach.ShardAlive do
		if alive then
			local age = now - breach.ShardBorn[index]
			if age >= BREACH.ShardLifetime then
				breach.ShardAlive[index] = false
				breach.ShardA[index]:Destroy()
				breach.ShardB[index]:Destroy()
			else
				local velocity = breach.ShardVel[index] - Vector3.new(0, 45 * dt, 0)
				breach.ShardVel[index] = velocity
				local spin = breach.ShardSpin[index] * dt
				local cframe = (breach.ShardCF[index] + velocity * dt) * CFrame.Angles(spin, spin * 0.7, spin * 0.4)
				breach.ShardCF[index] = cframe
				local fade = age / BREACH.ShardLifetime
				local partA, partB = breach.ShardA[index], breach.ShardB[index]
				partA.CFrame = cframe * breach.OffsetA[index]
				partB.CFrame = cframe * breach.OffsetB[index]
				partA.Transparency = fade
				partB.Transparency = fade
			end
		end
	end
end

local function destroyBreach(breach: Breach)
	breach.Folder:Destroy()
	table.clear(breach.EdgeParts)
	table.clear(breach.ShardA)
	table.clear(breach.ShardB)
	table.clear(breach.HitLights)
	table.clear(breach.HitBeams)
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
			descendant.Color = BLACK
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
	for index, part in silhouette.Parts do
		part.Color = BLACK:Lerp(silhouette.Colors[index], t)
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
local SKY_PROPS = { "CelestialBodiesShown" }

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
	local existingSky = Lighting:FindFirstChildOfClass("Sky")
	local skyCreated = existingSky == nil
	local sky: Sky = existingSky or Instance.new("Sky")
	if skyCreated then
		sky.Name = FOLDER_NAME .. "_Sky"
		sky.Parent = Lighting
	end
	local character = Players.LocalPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local coreGuis: { [Enum.CoreGuiType]: boolean } = {}
	for _, item in Enum.CoreGuiType:GetEnumItems() do
		if item ~= Enum.CoreGuiType.All then
			local ok, enabled = pcall(function(): boolean
				return StarterGui:GetCoreGuiEnabled(item)
			end)
			if ok then
				coreGuis[item] = enabled
			end
		end
	end
	return {
		HiddenGuis = {},
		CoreGuis = coreGuis,
		Lighting = readProps(Lighting, LIGHTING_PROPS),
		Atmosphere = atmo,
		AtmosphereCreated = atmosphereCreated,
		AtmosphereProps = readProps(atmo, ATMOSPHERE_PROPS),
		Clouds = clouds,
		CloudsCreated = cloudsCreated,
		CloudsProps = readProps(clouds, CLOUDS_PROPS),
		Sky = sky,
		SkyCreated = skyCreated,
		SkyProps = readProps(sky, SKY_PROPS),
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
		if type(value) ~= "boolean" then
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
	if saved.SkyCreated then
		saved.Sky:Destroy()
	elseif saved.Sky.Parent then
		writeProps(saved.Sky, saved.SkyProps)
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

	-- Volta a interface do jogo
	for _, gui in saved.HiddenGuis do
		if gui.Parent then
			gui.Enabled = true
		end
	end
	table.clear(saved.HiddenGuis)
	for item, enabled in saved.CoreGuis do
		pcall(function()
			StarterGui:SetCoreGuiEnabled(item, enabled)
		end)
	end
end

-- Esconde toda a interface do jogo (menos a camada da cinemática)
local function hideInterface(session: Session)
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local keep = overlay and overlay.Gui
	if playerGui then
		for _, gui in playerGui:GetChildren() do
			if gui:IsA("ScreenGui") and gui.Enabled and gui ~= keep then
				gui.Enabled = false
				table.insert(session.Saved.HiddenGuis, gui)
			end
		end
	end
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	end)
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

-- Plano da câmara: posição num círculo à volta do ponto de aterragem.
-- angle 0 = lado direito, -π/2 = lado da praça (de onde o jogador chega), +π/2 = palco
local SHOT_FRONT = -math.pi / 2

local function shotPosition(geo: Geometry, angle: number, radius: number, height: number): Vector3
	return geo.Landing + (geo.Right * math.cos(angle) + geo.Forward * math.sin(angle)) * radius + Vector3.new(0, height, 0)
end

-- `roll`: inclinação lateral do plano (rad). Mistura suavemente a partir do plano anterior
-- durante CameraBlend[fase] s e aplica tremor e "zoom" das pancadas.
local function setCamera(session: Session, position: Vector3, lookAt: Vector3, fov: number, roll: number?)
	local camera = Workspace.CurrentCamera
	local offset = shakeOffset(session)
	local target = CFrame.lookAt(position + offset, lookAt + offset * 0.5)
	if roll then
		target *= CFrame.Angles(0, 0, roll)
	end
	local blendFrom = session.BlendFrom
	if blendFrom and session.BlendTime > 0 then
		local blend = math.clamp((os.clock() - session.BlendStart) / session.BlendTime, 0, 1)
		if blend < 1 then
			target = blendFrom:Lerp(target, easeInOutSine(blend))
		else
			session.BlendFrom = nil
		end
	end
	camera.CFrame = target
	camera.FieldOfView = fov - session.FovKick
end

-- Clarão de relâmpago/racha: ilumina a imagem toda (ColorCorrection) + flash leve
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

local function ensureBreach(session: Session): Breach
	local existing = session.Breach
	if existing then
		return existing
	end
	local breach = makeBreach(session.Folder, session.BreachPos, session.Geo.Right, 1, session.Rarity, session.Params.LowVfx)
	session.Breach = breach
	return breach
end

-- Remove tempestade, céu e racha (Saltar / fim da revelação)
local function clearSky(session: Session)
	local deck = session.Deck
	if deck then
		destroyDeck(deck)
		session.Deck = nil
	end
	local breach = session.Breach
	if breach then
		destroyBreach(breach)
		session.Breach = nil
	end
	local rain = session.Rain
	if rain then
		rain:Destroy()
		session.Rain = nil
	end
	for _, bolt in session.Bolts do
		destroyBolt(bolt)
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
	hideInterface(session)
	if CIN.HideSun then
		session.Saved.Sky.CelestialBodiesShown = false
	end
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
	local deck = spawnDeck(session.Folder, if low then CIN.CloudRingsLow else #CIN.CloudRings, not low, true)
	deck.Offset = CIN.CloudCloseDistance -- começam longe: o céu ainda está azul
	session.Deck = deck
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

	-- Tempestade cinzenta (não noite): a luz baixa um pouco enquanto as nuvens fecham
	local saved = session.Saved
	local closeTime = CIN.CloudCloseTime
	tweenTo(session, Lighting, closeTime, {
		Brightness = 1.2,
		Ambient = Color3.fromRGB(80, 80, 90),
		OutdoorAmbient = Color3.fromRGB(100, 100, 110),
		ExposureCompensation = -0.2,
	})
	tweenTo(session, saved.Atmosphere, closeTime, { Density = 0.35, Haze = 2, Color = Color3.fromRGB(150, 150, 160), Glare = 0 })
	saved.Clouds.Enabled = true
	tweenTo(session, saved.Clouds, closeTime, {
		Cover = CIN.TerrainClouds.Cover,
		Density = CIN.TerrainClouds.Density,
		Color = CIN.TerrainClouds.Color,
	})
	local grading = Instance.new("ColorCorrectionEffect")
	trackEffect(session, grading)
	session.Grading = grading
	tweenTo(session, grading, closeTime, { Saturation = -0.35, Contrast = 0.1, TintColor = Color3.fromRGB(225, 228, 240) })
end

ENTER.SkyOpen = function(session: Session)
	takeControl(session)
	-- Volta o céu azul normal (o sol continua escondido)
	local saved = session.Saved
	local time = phaseDuration("SkyOpen")
	tweenTo(session, Lighting, time, goalsFrom(saved.Lighting))
	tweenTo(session, saved.Atmosphere, time, goalsFrom(saved.AtmosphereProps))
	tweenTo(session, saved.Clouds, time, { Cover = 0, Density = 0 })
	local grading = session.Grading
	if grading then
		tweenTo(session, grading, time, { Saturation = 0, Contrast = 0, TintColor = Color3.new(1, 1, 1) })
	end
	local rain = session.Rain
	if rain then
		local drops = rain:FindFirstChildOfClass("ParticleEmitter")
		if drops then
			drops.Rate = 0
		end
	end
	local deck = session.Deck
	if deck then
		puffDeck(deck, 2)
	end
end

ENTER.Rift = function(session: Session)
	takeControl(session)
	ensureBreach(session)
	CrateSfx.Play("RiftOpen")
	-- A luz do outro mundo invade a cena enquanto o céu parte
	local time = phaseDuration("Rift")
	local tint = BREACH.WorldTint
	local grading = session.Grading
	if grading then
		tweenTo(session, grading, time, { TintColor = Color3.new(1, 1, 1):Lerp(tint, 0.3), Saturation = 0.1, Contrast = 0.15 })
	end
	tweenTo(session, Lighting, time, {
		Ambient = Color3.fromRGB(60, 50, 80):Lerp(tint, 0.3),
		OutdoorAmbient = Color3.fromRGB(90, 80, 110):Lerp(tint, 0.3),
		ExposureCompensation = -0.15,
	})
	tweenTo(session, session.Saved.Atmosphere, time, { Density = 0.25, Haze = 1.5, Color = Color3.fromRGB(150, 150, 170):Lerp(tint, 0.4) })
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0
	bloom.Size = 24
	bloom.Threshold = 0.9
	trackEffect(session, bloom)
	tweenTo(session, bloom, time, { Intensity = 0.7 })
	lightningFlash(session, 0.8)
end

ENTER.Leap = function(session: Session)
	takeControl(session)
	finishBreach(ensureBreach(session), os.clock()) -- pancadas que faltem (fase encurtada)
	local silhouette = ensureSilhouette(session)
	placeRig(silhouette, session.BreachPos, session.Geo.CamBase)
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
	session.OrbitBase = SHOT_FRONT + 1.1 -- continua do plano da aterragem
	withOverlay(function(o)
		o.ShowTitle(session.ArtistName, session.Rarity)
		o.SetSkipVisible(false)
	end)
	-- O céu limpa e a iluminação volta ao normal durante a revelação
	local deck = session.Deck
	if deck then
		fadeDeck(deck, 0.6)
	end
	local saved = session.Saved
	tweenTo(session, Lighting, 1.8, goalsFrom(saved.Lighting))
	tweenTo(session, saved.Atmosphere, 1.8, goalsFrom(saved.AtmosphereProps))
	tweenTo(session, saved.Clouds, 1.8, goalsFrom(saved.CloudsProps))
	local grading = session.Grading
	if grading then
		tweenTo(session, grading, 1.8, { TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0 })
	end
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
	-- As nuvens fecham o céu
	local deck = session.Deck
	if deck then
		deck.Offset = CIN.CloudCloseDistance * (1 - easeOutCubic(math.clamp(t / CIN.CloudCloseTime, 0, 1)))
	end
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
	-- Plano 1: grande plano baixo, a rodar devagar à volta do terreno a olhar para o céu
	local e = easeInOutSine(math.clamp(t / phaseDuration("Storm"), 0, 1))
	local position = shotPosition(geo, SHOT_FRONT - 0.5 + 0.3 * e, 32, 3 + 3 * e)
	setCamera(session, position, geo.Sky + geo.Forward * 10, CIN.FovStart + 5, 0.04 * math.sin(t * 0.7))
end

UPDATE.SkyOpen = function(session: Session, t: number, alpha: number, _dt: number)
	local geo = session.Geo
	local deck = session.Deck
	if deck then
		deck.Offset = 0
		deck.Open = alpha
		-- O teto cinzento sai logo no início: na transição só se veem nuvens
		fadeCeiling(deck, math.clamp(t / CIN.CeilingFadeTime, 0, 1))
	end
	-- Plano 2: a câmara sobe em grua enquanto o céu abre
	local e = easeInOutSine(alpha)
	local position = shotPosition(geo, SHOT_FRONT - 0.2 + 0.35 * e, 32 - 6 * e, 6 + 8 * e)
	setCamera(session, position, session.BreachPos, CIN.FovStart + 5 - 5 * e)
end

UPDATE.Rift = function(session: Session, t: number, _alpha: number, _dt: number)
	local geo = session.Geo
	local breach = ensureBreach(session)
	-- Pancadas do outro lado do céu: cada uma parte mais um pedaço; a última é a maior
	local nextIndex = breach.HitsDone + 1
	local nextHit = BREACH.Hits[nextIndex]
	if nextHit and t >= nextHit.Time then
		hitBreach(breach, nextIndex, os.clock())
		local last = nextIndex == #BREACH.Hits
		CrateSfx.Play(if last then "SkyShatter" else "SkyHit")
		lightningFlash(session, if last then 1.6 else 0.5 + 0.4 * nextHit.Size)
		shake(session, if last then CIN.ShakeImpact * 0.6 else CIN.ShakeRift * (2 + 4 * nextHit.Size), if last then 0.5 else 0.3)
		session.FovKick = CIN.HitZoom * (if last then 1.6 else 0.6 + 0.4 * nextHit.Size)
	end
	-- Plano 3: rasteiro e inclinado, quase por baixo da brecha (o céu a cair em cima)
	local drift = t / phaseDuration("Rift")
	local position = shotPosition(geo, SHOT_FRONT + 0.35 + 0.15 * drift, 18 - 3 * drift, 2)
	setCamera(session, position, session.BreachPos, CIN.FovStart, -0.06)
end

UPDATE.Leap = function(session: Session, _t: number, alpha: number, _dt: number)
	local geo = session.Geo
	local silhouette = session.Sil
	local position = session.BreachPos:Lerp(geo.Landing, easeInQuad(alpha))
	if silhouette then
		placeRig(silhouette, position, geo.CamBase)
	end
	-- Plano 4: lateral, a seguir o artista a cair
	local cameraPos = shotPosition(geo, SHOT_FRONT + 0.9, 28, lerp(10, 3, alpha))
	setCamera(session, cameraPos, position + Vector3.new(0, 2, 0), lerp(CIN.FovStart, CIN.FovLeap, alpha))
end

UPDATE.Impact = function(session: Session, _t: number, alpha: number, _dt: number)
	local geo = session.Geo
	local shockwave = session.Shockwave
	if shockwave then
		updateShockwave(shockwave, alpha, CIN.CraterRadius * 6)
	end
	-- Plano 5: corte seco ao nível do chão
	local cameraPos = shotPosition(geo, SHOT_FRONT + 1.1, 22, 1.2)
	setCamera(session, cameraPos, geo.Landing + Vector3.new(0, 2.5, 0), lerp(CIN.FovLeap, CIN.FovReveal, alpha))
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
	-- Plano 6: órbita com aproximação e subida ligeira
	local angle = session.OrbitBase + t * CIN.OrbitSpeed
	local approach = easeInOutSine(math.clamp(t / phaseDuration("Reveal"), 0, 1))
	local cameraPos = shotPosition(geo, angle, lerp(CIN.OrbitRadius + 6, CIN.OrbitRadius - 2, approach), lerp(2.5, 4.5, approach))
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
	-- Transição suave do plano anterior para o desta fase (0 = corte seco)
	session.BlendFrom = Workspace.CurrentCamera.CFrame
	session.BlendStart = os.clock()
	session.BlendTime = if session.HasControl then ((CIN.CameraBlend :: unknown) :: { [string]: number })[name] or 0 else 0
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
	session.FovKick = math.max(0, session.FovKick - dt * 30)
	local deck = session.Deck
	if deck then
		updateDeck(deck, session.Geo.Sky, dt)
	end
	for _, bolt in session.Bolts do
		updateBolt(bolt, now)
	end
	local breach = session.Breach
	if breach then
		updateBreach(breach, now, dt)
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
		Breach = nil,
		BreachPos = geo.Sky + Vector3.new(0, BREACH.Lift, 0),
		Rain = nil,
		Sil = nil,
		Shockwave = nil,
		ColorStart = nil,
		ShakeUntil = 0,
		ShakeMagnitude = 0,
		ShakeDuration = 0,
		BlendFrom = nil,
		BlendStart = 0,
		BlendTime = 0,
		FovKick = 0,
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
-- Usa os mesmos tempos da timeline completa: StartTime = início da cinemática do dono.

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
	local impactAt = phaseStart("Impact")
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
	local breach: Breach? = nil
	local silhouette: Silhouette? = nil
	local shockwave: BasePart? = nil
	local strikes: { boolean } = {}
	local breachPos = geo.Sky + Vector3.new(0, BREACH.Lift * 0.5, 0)
	local stormAt = phaseStart("Storm")
	local openAt = phaseStart("SkyOpen")
	local openTime = phaseDuration("SkyOpen")
	local riftAt = phaseStart("Rift")
	local leapAt = phaseStart("Leap")
	local leapTime = phaseDuration("Leap")
	local impactAt = leapAt + leapTime
	local total = impactAt + LIGHT.RevealHold
	local impacted = false
	local lastClock = os.clock()

	trove:Connect(RunService.RenderStepped, function()
		local now = os.clock()
		local dt = now - lastClock
		lastClock = now
		local t = Workspace:GetServerTimeNow() - summon.StartTime
		if t < stormAt then
			return
		end
		if t >= total then
			trove:Destroy()
			return
		end
		if not deck then
			deck = spawnDeck(folder, LIGHT.CloudRings, false, false)
			bolt = makeBolt(folder)
		end
		local currentDeck = deck
		if currentDeck then
			if t < openAt then
				currentDeck.Offset = CIN.CloudCloseDistance * (1 - easeOutCubic(math.clamp((t - stormAt) / CIN.CloudCloseTime, 0, 1)))
			else
				currentDeck.Offset = 0
				currentDeck.Open = math.clamp((t - openAt) / openTime, 0, 1)
			end
			updateDeck(currentDeck, geo.Sky, dt)
			if t >= impactAt then
				fadeDeck(currentDeck, math.clamp((t - impactAt) / LIGHT.RevealHold, 0, 1))
			end
		end
		local currentBolt = bolt
		if currentBolt then
			for index, time in CIN.LightningTimes do
				if not strikes[index] and t >= stormAt + time and t < openAt then
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
		if t >= riftAt and t < impactAt then
			if not breach then
				breach = makeBreach(folder, breachPos, geo.Right, 0.6, rarity, true)
			end
			local currentBreach = breach
			if currentBreach then
				local nextIndex = currentBreach.HitsDone + 1
				local nextHit = BREACH.Hits[nextIndex]
				if nextHit and t - riftAt >= nextHit.Time then
					hitBreach(currentBreach, nextIndex, now)
					CrateSfx.PlayAt(if nextIndex == #BREACH.Hits then "SkyShatter" else "SkyHit", geo.Landing)
				end
				updateBreach(currentBreach, now, dt)
			end
		end
		if t >= leapAt then
			if not silhouette then
				silhouette = makeSilhouette(folder, summon.ArtistId, rarity)
			end
			local currentSil = silhouette
			if currentSil then
				local alpha = math.clamp((t - leapAt) / leapTime, 0, 1)
				placeRig(currentSil, breachPos:Lerp(geo.Landing, easeInQuad(alpha)), geo.CamBase)
				if t >= impactAt then
					colorSilhouette(currentSil, math.clamp((t - impactAt) / CIN.ColorTweenTime, 0, 1))
				end
			end
		end
		if t >= impactAt and not impacted then
			impacted = true
			local currentBreach = breach
			if currentBreach then
				destroyBreach(currentBreach)
				breach = nil
			end
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
