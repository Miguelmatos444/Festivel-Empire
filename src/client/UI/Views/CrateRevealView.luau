--!strict
--[[
	CrateRevealView
	Painel de ecrã inteiro da abertura das Vinyl Crates (registado no ModalManager):
	  x1   roleta horizontal: a faixa passa da direita para a esquerda e abranda até parar
	       com a carta ganha debaixo do marcador ("tick" a cada carta)
	  x10  grelha de 10 cartas reveladas em sequência, da menos rara para a mais rara
	Carta mistério: silhueta preta + "???" vermelho a pulsar; 1 s depois corre a cinemática
	(CrateCinematicController). No fim: retrato 3D do melhor artista, "Continuar" e
	"Abrir de novo".
	Também é dona da camada da cinemática (fade, flash, título, "Saltar").

	Desempenho: 40 cartas da roleta + 10 da grelha + confetti criados uma vez no Mount;
	o RenderStepped só existe com o painel aberto e não cria instâncias nem tabelas.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Types = require(ReplicatedStorage.Shared.Types)
local CrateAnimConfig = require(ReplicatedStorage.Shared.Config.CrateAnimation)
local RaritiesConfig = require(ReplicatedStorage.Shared.Config.Rarities)
local ArtistCalc = require(ReplicatedStorage.Shared.Calc.ArtistCalc)
local CrateAnimCalc = require(ReplicatedStorage.Shared.Calc.CrateAnimCalc)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)

local Client = script.Parent.Parent.Parent
local CrateAnimController = require(Client.Controllers.CrateAnimController)
local CrateCinematicController = require(Client.Controllers.CrateCinematicController)
local ArtistController = require(Client.Controllers.ArtistController)
local CinematicAssets = require(Client.Controllers.CinematicAssets)
local CrateSfx = require(Client.Controllers.CrateSfx)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local ModalManager = require(script.Parent.Parent.ModalManager)
local ArtistsView = require(script.Parent.ArtistsView)

type CrateDef = Types.CrateDef
type CrateItem = Types.CrateItem
type CrateResult = Types.CrateResult
type RarityDef = Types.RarityDef
type CrateStopEffect = Types.CrateStopEffect
type RevealEffect = CrateStopEffect | "Mystery"

type CardRefs = {
	Outer: Frame,
	Inner: Frame,
	Scale: UIScale,
	Face: Frame,
	Back: TextLabel,
	Stroke: UIStroke,
	Glow: Frame,
	Head: Frame,
	Body: Frame,
	Name: TextLabel,
	Rarity: TextLabel,
	Chance: TextLabel,
}

type Spin = {
	Active: boolean,
	Start: number,
	Duration: number,
	FromX: number,
	ToX: number,
	LastIndex: number,
	OnDone: (() -> ())?,
}

local MODAL_NAME = "CrateReveal" -- o ArtistsView usa o mesmo nome para não abrir por cima
local DESIGN_SIZE = Vector2.new(980, 640)
local ROULETTE_WIDTH = 920
local GRID_CARD = Vector2.new(150, 190)
local VIEWPORT_SIZE = 150
local RED = Color3.fromRGB(255, 50, 60)
local BLACK = Color3.new(0, 0, 0)
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 200, 40)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(60, 255, 120)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(40, 200, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 200)),
})

local CrateRevealView = {}

local activeTrove: Trove.Trove? = nil

-- Helpers --------------------------------------------------------------------

local function formatChance(chance: number): string
	local value = chance * 100
	if value >= 1 and math.abs(value - math.floor(value + 0.5)) < 1e-6 then
		return string.format("%d%%", math.floor(value + 0.5))
	end
	return string.format("%.2f%%", value)
end

local function textButton(name: string, text: string, color: Color3, size: UDim2): TextButton
	local button = Components.makeButton(name, color)
	button.Size = size
	button.Font = Theme.Fonts.Display
	button.TextColor3 = Theme.Colors.Text
	button.TextScaled = true
	button.Text = text
	Components.addCorner(button, UDim.new(0, 12))
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 22
	constraint.Parent = button
	return button
end

local function setGradient(target: GuiObject, rarity: RarityDef?)
	local existing = target:FindFirstChildOfClass("UIGradient")
	if existing then
		existing:Destroy()
	end
	if rarity and (rarity.Effect == "Gradient" or rarity.Effect == "Rainbow") then
		local gradient = Instance.new("UIGradient")
		gradient.Color = if rarity.Effect == "Rainbow" then RAINBOW else ColorSequence.new(rarity.Color, Color3.new(1, 1, 1))
		gradient.Parent = target
	end
end

local function makeCard(parent: Instance, size: Vector2, layoutOrder: number): CardRefs
	local outer = Components.makeFrame("Card" .. layoutOrder)
	outer.Size = UDim2.fromOffset(size.X, size.Y)
	outer.LayoutOrder = layoutOrder
	outer.Parent = parent

	local inner = Instance.new("Frame")
	inner.Name = "Inner"
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.fromScale(1, 1)
	inner.BackgroundColor3 = Theme.Colors.Background
	inner.BorderSizePixel = 0
	inner.ClipsDescendants = true
	Components.addCorner(inner, UDim.new(0, 12))
	local stroke = Components.addStroke(inner, Theme.Colors.Gold, 3)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	inner.Parent = outer
	local scale = Instance.new("UIScale")
	scale.Parent = inner

	local face = Components.makeFrame("Face")
	face.Size = UDim2.fromScale(1, 1)
	face.Parent = inner

	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.Size = UDim2.fromScale(1, 1)
	glow.BorderSizePixel = 0
	glow.BackgroundTransparency = 0.55
	local glowGradient = Instance.new("UIGradient")
	glowGradient.Rotation = -90
	glowGradient.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	glowGradient.Parent = glow
	glow.Parent = face

	local unit = size.X / 130
	local head = Instance.new("Frame")
	head.Name = "Head"
	head.AnchorPoint = Vector2.new(0.5, 0)
	head.Position = UDim2.new(0.5, 0, 0, 14 * unit)
	head.Size = UDim2.fromOffset(36 * unit, 36 * unit)
	head.BorderSizePixel = 0
	Components.addCorner(head, UDim.new(1, 0))
	head.Parent = face

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.AnchorPoint = Vector2.new(0.5, 0)
	body.Position = UDim2.new(0.5, 0, 0, 54 * unit)
	body.Size = UDim2.fromOffset(62 * unit, 48 * unit)
	body.BorderSizePixel = 0
	Components.addCorner(body, UDim.new(0, 18 * unit))
	body.Parent = face

	local nameLabel = Components.makeLabel("Name", Theme.Fonts.Display, Theme.Colors.Text, 18)
	nameLabel.Position = UDim2.new(0, 6, 0, 106 * unit)
	nameLabel.Size = UDim2.new(1, -12, 0, 32 * unit)
	nameLabel.TextWrapped = true
	Components.addStroke(nameLabel, Theme.Colors.Background, 1.5)
	nameLabel.Parent = face

	local rarityLabel = Components.makeLabel("Rarity", Theme.Fonts.Body, Theme.Colors.Text, 14)
	rarityLabel.Position = UDim2.new(0, 6, 0, 138 * unit)
	rarityLabel.Size = UDim2.new(1, -12, 0, 16 * unit)
	rarityLabel.Parent = face

	local chanceLabel = Components.makeLabel("Chance", Theme.Fonts.Display, Theme.Colors.Gold, 16)
	chanceLabel.Position = UDim2.new(0, 6, 1, -22 * unit)
	chanceLabel.Size = UDim2.new(1, -12, 0, 18 * unit)
	Components.addStroke(chanceLabel, Theme.Colors.Background, 1.5)
	chanceLabel.Parent = face

	local back = Components.makeLabel("Back", Theme.Fonts.Display, Theme.Colors.Text, 64)
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundTransparency = 0
	back.Text = "?"
	back.Visible = false
	back.Parent = inner

	return {
		Outer = outer,
		Inner = inner,
		Scale = scale,
		Face = face,
		Back = back,
		Stroke = stroke,
		Glow = glow,
		Head = head,
		Body = body,
		Name = nameLabel,
		Rarity = rarityLabel,
		Chance = chanceLabel,
	}
end

-- Preenche a carta (fora do RenderStepped)
local function setCardContent(card: CardRefs, crate: CrateDef?, artistId: string, rarityId: string, mystery: boolean)
	local rarity = RaritiesConfig.ById[rarityId] or RaritiesConfig.List[1]
	local def = ArtistCalc.GetArtist(artistId)
	card.Back.Visible = false
	card.Face.Visible = true
	card.Scale.Scale = 1
	card.Stroke.Thickness = 3
	card.Chance.TextTransparency = 0
	if mystery then
		card.Stroke.Color = RED
		card.Glow.BackgroundColor3 = RED
		card.Head.BackgroundColor3 = BLACK
		card.Body.BackgroundColor3 = BLACK
		card.Name.Text = ""
		card.Rarity.Text = ""
		card.Chance.Text = "???"
		card.Chance.TextColor3 = RED
		setGradient(card.Rarity, nil)
	else
		card.Stroke.Color = rarity.Color
		card.Glow.BackgroundColor3 = rarity.Color
		card.Head.BackgroundColor3 = rarity.Color
		card.Body.BackgroundColor3 = rarity.Color
		card.Name.Text = if def then def.Name else artistId
		card.Rarity.Text = rarity.Name
		card.Rarity.TextColor3 = if rarity.Effect == "Gradient" or rarity.Effect == "Rainbow" then Color3.new(1, 1, 1) else rarity.Color
		setGradient(card.Rarity, rarity)
		card.Chance.Text = if crate then formatChance(CrateAnimCalc.GetChance(crate, rarityId)) else ""
		card.Chance.TextColor3 = Theme.Colors.Gold
	end
end

local function setCardBack(card: CardRefs, crate: CrateDef?)
	card.Face.Visible = false
	card.Back.Visible = true
	card.Back.BackgroundColor3 = if crate then crate.Color else Theme.Colors.Panel
	card.Stroke.Color = Theme.Colors.Gold
	card.Stroke.Thickness = 3
	card.Scale.Scale = 1
end

-- Montagem -------------------------------------------------------------------

function CrateRevealView.Mount()
	if activeTrove then
		return
	end
	local trove = Trove.new()
	activeTrove = trove
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local rouletteCfg = CrateAnimConfig.Roulette
	local pitch = rouletteCfg.CardWidth + rouletteCfg.CardGap

	-- Painel -----------------------------------------------------------------------
	local gui = trove:Add(Instance.new("ScreenGui"))
	gui.Name = "CrateRevealGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 15

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.Overlay
	backdrop.BackgroundTransparency = 0.3
	backdrop.BorderSizePixel = 0
	backdrop.Active = true
	backdrop.Visible = false
	backdrop.Parent = gui

	local holder = Components.makeFrame("Holder")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(DESIGN_SIZE.X, DESIGN_SIZE.Y)
	holder.Parent = backdrop
	local fitScale = Instance.new("UIScale")
	fitScale.Parent = holder

	local title = Components.makeLabel("Title", Theme.Fonts.Display, Theme.Colors.Gold, 36)
	title.Position = UDim2.fromOffset(0, 0)
	title.Size = UDim2.new(1, 0, 0, 44)
	Components.addStroke(title, Theme.Colors.Background, 2)
	title.Parent = holder

	-- Roleta
	local roulette = Instance.new("Frame")
	roulette.Name = "Roulette"
	roulette.AnchorPoint = Vector2.new(0.5, 0)
	roulette.Position = UDim2.new(0.5, 0, 0, 60)
	roulette.Size = UDim2.fromOffset(ROULETTE_WIDTH, rouletteCfg.CardHeight + 24)
	roulette.BackgroundColor3 = Theme.Colors.Panel
	roulette.BorderSizePixel = 0
	roulette.ClipsDescendants = true
	roulette.Visible = false
	Components.addCorner(roulette, UDim.new(0, 16))
	Components.addStroke(roulette, Theme.Colors.Gold, 3)
	roulette.Parent = holder

	local strip = Components.makeFrame("Strip")
	strip.Position = UDim2.fromOffset(0, 12)
	strip.Size = UDim2.fromOffset(rouletteCfg.CardCount * pitch, rouletteCfg.CardHeight)
	strip.Parent = roulette

	local stripCards: { CardRefs } = {}
	for index = 1, rouletteCfg.CardCount do
		local card = makeCard(strip, Vector2.new(rouletteCfg.CardWidth, rouletteCfg.CardHeight), index)
		card.Outer.Position = UDim2.fromOffset((index - 1) * pitch, 0)
		table.insert(stripCards, card)
	end

	local marker = Instance.new("Frame")
	marker.Name = "Marker"
	marker.AnchorPoint = Vector2.new(0.5, 0)
	marker.Position = UDim2.fromScale(0.5, 0)
	marker.Size = UDim2.new(0, 4, 1, 0)
	marker.BackgroundColor3 = Theme.Colors.Gold
	marker.BorderSizePixel = 0
	marker.ZIndex = 5
	marker.Parent = roulette
	for _, top in { true, false } do
		local arrow = Instance.new("Frame")
		arrow.Name = if top then "ArrowTop" else "ArrowBottom"
		arrow.AnchorPoint = Vector2.new(0.5, 0.5)
		arrow.Position = if top then UDim2.fromScale(0.5, 0) else UDim2.fromScale(0.5, 1)
		arrow.Size = UDim2.fromOffset(22, 22)
		arrow.Rotation = 45
		arrow.BackgroundColor3 = Theme.Colors.Gold
		arrow.BorderSizePixel = 0
		arrow.ZIndex = 6
		arrow.Parent = roulette
	end

	-- Grelha x10
	local grid = Components.makeFrame("Grid")
	grid.AnchorPoint = Vector2.new(0.5, 0)
	grid.Position = UDim2.new(0.5, 0, 0, 52)
	grid.Size = UDim2.fromOffset(5 * GRID_CARD.X + 4 * 12, 2 * GRID_CARD.Y + 12)
	grid.Visible = false
	grid.Parent = holder
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(GRID_CARD.X, GRID_CARD.Y)
	gridLayout.CellPadding = UDim2.fromOffset(12, 12)
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	local gridCards: { CardRefs } = {}
	for index = 1, 10 do
		table.insert(gridCards, makeCard(grid, GRID_CARD, index))
	end

	-- Resultado (retrato 3D + texto) e botões
	local resultPanel = Instance.new("Frame")
	resultPanel.Name = "Result"
	resultPanel.AnchorPoint = Vector2.new(0.5, 1)
	resultPanel.Position = UDim2.new(0.5, 0, 1, -76)
	resultPanel.Size = UDim2.fromOffset(560, VIEWPORT_SIZE + 16)
	resultPanel.BackgroundColor3 = Theme.Colors.Panel
	resultPanel.BorderSizePixel = 0
	resultPanel.Visible = false
	Components.addCorner(resultPanel, UDim.new(0, 16))
	local resultStroke = Components.addStroke(resultPanel, Theme.Colors.Gold, 2)
	resultPanel.Parent = holder

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Portrait"
	viewport.Position = UDim2.fromOffset(8, 8)
	viewport.Size = UDim2.fromOffset(VIEWPORT_SIZE, VIEWPORT_SIZE)
	viewport.BackgroundColor3 = Theme.Colors.Background
	viewport.Ambient = Color3.fromRGB(200, 200, 210)
	viewport.LightColor = Color3.new(1, 1, 1)
	Components.addCorner(viewport, UDim.new(0, 12))
	viewport.Parent = resultPanel
	local viewportCamera = Instance.new("Camera")
	viewportCamera.FieldOfView = 40
	viewportCamera.Parent = viewport
	viewport.CurrentCamera = viewportCamera

	local resultName = Components.makeLabel("Name", Theme.Fonts.Display, Theme.Colors.Text, 34)
	resultName.Position = UDim2.fromOffset(VIEWPORT_SIZE + 24, 14)
	resultName.Size = UDim2.new(1, -(VIEWPORT_SIZE + 40), 0, 42)
	resultName.TextXAlignment = Enum.TextXAlignment.Left
	resultName.Parent = resultPanel

	local resultRarity = Components.makeLabel("Rarity", Theme.Fonts.Display, Theme.Colors.Gold, 26)
	resultRarity.Position = UDim2.fromOffset(VIEWPORT_SIZE + 24, 60)
	resultRarity.Size = UDim2.new(1, -(VIEWPORT_SIZE + 40), 0, 32)
	resultRarity.TextXAlignment = Enum.TextXAlignment.Left
	resultRarity.Parent = resultPanel

	local resultInfo = Components.makeLabel("Info", Theme.Fonts.Body, Theme.Colors.TextMuted, 18)
	resultInfo.Position = UDim2.fromOffset(VIEWPORT_SIZE + 24, 100)
	resultInfo.Size = UDim2.new(1, -(VIEWPORT_SIZE + 40), 0, 44)
	resultInfo.TextWrapped = true
	resultInfo.TextXAlignment = Enum.TextXAlignment.Left
	resultInfo.TextYAlignment = Enum.TextYAlignment.Top
	resultInfo.Parent = resultPanel

	local buttons = Components.makeFrame("Buttons")
	buttons.AnchorPoint = Vector2.new(0.5, 1)
	buttons.Position = UDim2.new(0.5, 0, 1, -12)
	buttons.Size = UDim2.fromOffset(520, 54)
	buttons.Visible = false
	buttons.Parent = holder
	local buttonsLayout = Instance.new("UIListLayout")
	buttonsLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	buttonsLayout.Padding = UDim.new(0, 16)
	buttonsLayout.Parent = buttons
	local continueButton = textButton("Continue", "CONTINUAR", Theme.Colors.Accent, UDim2.fromOffset(240, 54))
	continueButton.LayoutOrder = 1
	continueButton.Parent = buttons
	local againButton = textButton("Again", "ABRIR DE NOVO", Theme.Colors.Success, UDim2.fromOffset(240, 54))
	againButton.LayoutOrder = 2
	againButton.Parent = buttons

	-- Flash e confetti (por cima de tudo no painel)
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 50
	flash.Parent = backdrop

	local confettiFrames: { Frame } = {}
	local confettiX: { number } = {}
	local confettiY: { number } = {}
	local confettiVX: { number } = {}
	local confettiVY: { number } = {}
	for index = 1, CrateAnimConfig.ConfettiCount do
		local piece = Instance.new("Frame")
		piece.Name = "Confetti" .. index
		piece.Size = UDim2.fromOffset(10, 16)
		piece.BorderSizePixel = 0
		piece.Visible = false
		piece.ZIndex = 40
		piece.Parent = holder
		table.insert(confettiFrames, piece)
		table.insert(confettiX, 0)
		table.insert(confettiY, 0)
		table.insert(confettiVX, 0)
		table.insert(confettiVY, 0)
	end

	-- Camada da cinemática ---------------------------------------------------------
	local cinematicGui = trove:Add(Instance.new("ScreenGui"))
	cinematicGui.Name = "CrateCinematicGui"
	cinematicGui.ResetOnSpawn = false
	cinematicGui.IgnoreGuiInset = true
	cinematicGui.DisplayOrder = 40

	local fade = Instance.new("Frame")
	fade.Name = "Fade"
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = BLACK
	fade.BackgroundTransparency = 1
	fade.BorderSizePixel = 0
	fade.Parent = cinematicGui

	local cinematicFlash = Instance.new("Frame")
	cinematicFlash.Name = "Flash"
	cinematicFlash.Size = UDim2.fromScale(1, 1)
	cinematicFlash.BackgroundColor3 = Color3.new(1, 1, 1)
	cinematicFlash.BackgroundTransparency = 1
	cinematicFlash.BorderSizePixel = 0
	cinematicFlash.ZIndex = 2
	cinematicFlash.Parent = cinematicGui

	local titleHolder = Components.makeFrame("Title")
	titleHolder.AnchorPoint = Vector2.new(0.5, 1)
	titleHolder.Position = UDim2.new(0.5, 0, 0.92, 0)
	titleHolder.Size = UDim2.new(0.9, 0, 0, 150)
	titleHolder.Visible = false
	titleHolder.ZIndex = 3
	titleHolder.Parent = cinematicGui
	local titleScale = Instance.new("UIScale")
	titleScale.Parent = titleHolder
	local bigName = Components.makeLabel("Name", Theme.Fonts.Display, Theme.Colors.Text, 72)
	bigName.Size = UDim2.new(1, 0, 0, 84)
	bigName.ZIndex = 3
	Components.addStroke(bigName, BLACK, 3)
	bigName.Parent = titleHolder
	local bigRarity = Components.makeLabel("Rarity", Theme.Fonts.Display, Theme.Colors.Gold, 48)
	bigRarity.Position = UDim2.fromOffset(0, 88)
	bigRarity.Size = UDim2.new(1, 0, 0, 56)
	bigRarity.ZIndex = 3
	Components.addStroke(bigRarity, BLACK, 3)
	bigRarity.Parent = titleHolder

	local skipButton = textButton("Skip", "SALTAR ▶", Theme.Colors.Panel, UDim2.fromOffset(170, 52))
	skipButton.AnchorPoint = Vector2.new(1, 0)
	skipButton.Position = UDim2.new(1, -24, 0, 24)
	skipButton.Visible = false
	skipButton.ZIndex = 4
	Components.addStroke(skipButton, Theme.Colors.Gold, 2)
	skipButton.Parent = cinematicGui
	trove:Connect(skipButton.Activated, function()
		CrateCinematicController.Skip()
	end)

	CrateCinematicController.SetOverlay({
		Gui = cinematicGui,
		SetFade = function(alpha: number, time: number)
			TweenService:Create(fade, TweenInfo.new(math.max(time, 0.01)), { BackgroundTransparency = 1 - alpha }):Play()
		end,
		Flash = function(strength: number)
			cinematicFlash.BackgroundTransparency = 1 - math.clamp(strength, 0, 1) * 0.9
			TweenService:Create(cinematicFlash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		end,
		ShowTitle = function(artistName: string, rarity: RarityDef)
			bigName.Text = artistName
			bigRarity.Text = rarity.Name
			bigRarity.TextColor3 = if rarity.Effect == "Gradient" or rarity.Effect == "Rainbow" then Color3.new(1, 1, 1) else rarity.Color
			setGradient(bigRarity, rarity)
			titleHolder.Visible = true
			titleScale.Scale = 0.6
			TweenService:Create(titleScale, Theme.Tween.Toast, { Scale = 1 }):Play()
		end,
		HideTitle = function()
			titleHolder.Visible = false
		end,
		SetSkipVisible = function(visible: boolean)
			skipButton.Visible = visible
		end,
	})
	trove:Add(function()
		CrateCinematicController.SetOverlay(nil)
	end)

	-- Estado ---------------------------------------------------------------------------
	local isOpen = false
	local busy = false
	local playToken = 0
	local currentResult: CrateResult? = nil
	local renderConnection: RBXScriptConnection? = nil
	local spin: Spin = { Active = false, Start = 0, Duration = 1, FromX = 0, ToX = 0, LastIndex = 0, OnDone = nil }
	local pulseLabel: TextLabel? = nil
	local pulseStroke: UIStroke? = nil
	local confettiTime = 0
	local confettiActive = 0
	local portraitRig: Model? = nil
	local portraitAngle = 0
	local rng = Random.new()

	local function playFlash()
		flash.BackgroundTransparency = 0.25
		TweenService:Create(flash, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
	end

	local function startConfetti(color: Color3)
		confettiActive = if CrateAnimController.IsLowVfx() then CrateAnimConfig.ConfettiCountLow else CrateAnimConfig.ConfettiCount
		confettiTime = 1.8
		local palette = { color, Theme.Colors.Gold, Color3.new(1, 1, 1), Theme.Colors.Accent }
		for index, piece in confettiFrames do
			if index <= confettiActive then
				confettiX[index] = DESIGN_SIZE.X / 2 + rng:NextNumber(-120, 120)
				confettiY[index] = DESIGN_SIZE.Y * 0.3
				confettiVX[index] = rng:NextNumber(-420, 420)
				confettiVY[index] = rng:NextNumber(-620, -260)
				piece.BackgroundColor3 = palette[rng:NextInteger(1, #palette)]
				piece.Visible = true
			else
				piece.Visible = false
			end
		end
	end

	local function clearPortrait()
		local rig = portraitRig
		if rig then
			rig:Destroy()
			portraitRig = nil
		end
	end

	local function setPortrait(item: CrateItem, rarity: RarityDef)
		clearPortrait()
		local rig = CinematicAssets.GetArtistRig(item.ArtistId, rarity.Color)
		rig:PivotTo(CFrame.new())
		local boxCFrame, size = rig:GetBoundingBox()
		local center = boxCFrame.Position
		local distance = math.max(size.Y, size.X) * 1.9 + 2
		viewportCamera.CFrame = CFrame.lookAt(center + Vector3.new(0, size.Y * 0.1, distance), center)
		rig.Parent = viewport
		portraitRig = rig
		portraitAngle = 0
	end

	local function applyStopEffect(card: CardRefs, effect: RevealEffect, rarity: RarityDef)
		card.Scale.Scale = 1.12
		TweenService:Create(card.Scale, Theme.Tween.Toast, { Scale = 1 }):Play()
		if effect == "Mystery" then
			pulseLabel = card.Chance
			pulseStroke = card.Stroke
			CrateSfx.Play("MysteryPulse")
		elseif effect == "Flash" then
			playFlash()
			startConfetti(rarity.Color)
			pulseStroke = card.Stroke
			CrateSfx.Play("CrateLegendary")
		elseif effect == "Glow" then
			pulseStroke = card.Stroke
			CrateSfx.Play("CrateRare")
		else
			CrateSfx.Play("CrateStop")
		end
	end

	local function effectFor(item: CrateItem): RevealEffect
		if item.Mystery then
			return "Mystery"
		end
		local rarity = RaritiesConfig.ById[item.Rarity] or RaritiesConfig.List[1]
		return CrateAnimCalc.GetStopEffect(rarity)
	end

	-- Render ---------------------------------------------------------------------------
	local function onRender(dt: number)
		local now = os.clock()
		if spin.Active then
			local t = math.clamp((now - spin.Start) / spin.Duration, 0, 1)
			local eased = 1 - (1 - t) ^ rouletteCfg.EasingPower
			local x = spin.FromX + (spin.ToX - spin.FromX) * eased
			strip.Position = UDim2.fromOffset(x, 12)
			local index = math.floor((ROULETTE_WIDTH / 2 - x) / pitch)
			if index ~= spin.LastIndex then
				spin.LastIndex = index
				CrateSfx.Play("CrateTick")
			end
			if t >= 1 then
				spin.Active = false
				local callback = spin.OnDone
				spin.OnDone = nil
				if callback then
					callback()
				end
			end
		end
		local pulse = (math.sin(now * 8) + 1) / 2
		local label = pulseLabel
		if label then
			label.TextTransparency = 0.45 * pulse
		end
		local stroke = pulseStroke
		if stroke then
			stroke.Thickness = 3 + 3 * pulse
		end
		if confettiTime > 0 then
			confettiTime -= dt
			for index = 1, confettiActive do
				confettiVY[index] += 900 * dt
				confettiX[index] += confettiVX[index] * dt
				confettiY[index] += confettiVY[index] * dt
				local piece = confettiFrames[index]
				piece.Position = UDim2.fromOffset(confettiX[index], confettiY[index])
				piece.Rotation += 400 * dt
			end
			if confettiTime <= 0 then
				for _, piece in confettiFrames do
					piece.Visible = false
				end
			end
		end
		local rig = portraitRig
		if rig then
			portraitAngle += dt * 0.8
			rig:PivotTo(CFrame.Angles(0, portraitAngle, 0))
		end
	end

	-- Abrir / fechar -------------------------------------------------------------------
	local playNext: () -> ()

	local function close(forced: boolean)
		if not isOpen then
			return
		end
		isOpen = false
		busy = false
		playToken += 1
		spin.Active = false
		spin.OnDone = nil
		pulseLabel = nil
		pulseStroke = nil
		backdrop.Visible = false
		local connection = renderConnection
		if connection then
			connection:Disconnect()
			renderConnection = nil
		end
		if CrateCinematicController.IsPlaying() then
			CrateAnimController.CancelCinematic()
		end
		clearPortrait()
		ModalManager.NotifyClosed(MODAL_NAME)
		if forced then
			CrateAnimController.ClearQueue()
		end
	end

	local function open()
		if isOpen then
			return
		end
		isOpen = true
		ModalManager.NotifyOpened(MODAL_NAME)
		backdrop.Visible = true
		renderConnection = RunService.RenderStepped:Connect(onRender)
	end

	ModalManager.Register(MODAL_NAME, function()
		close(true)
	end)
	trove:Add(function()
		ModalManager.Unregister(MODAL_NAME)
		close(true)
	end)

	local function later(token: number, seconds: number, callback: () -> ())
		task.delay(seconds, function()
			if token == playToken then
				callback()
			end
		end)
	end

	local function showResult(result: CrateResult)
		local bestIndex = 1
		local bestRarity = -1
		local counts = { New = 0, Fused = 0, Deleted = 0 }
		for index, item in result.Items do
			local rarityIndex = RaritiesConfig.IndexById[item.Rarity] or 0
			if rarityIndex > bestRarity then
				bestRarity = rarityIndex
				bestIndex = index
			end
			if item.Outcome == "New" then
				counts.New += 1
			elseif item.Outcome == "Fused" then
				counts.Fused += 1
			elseif item.Outcome == "Deleted" then
				counts.Deleted += 1
			end
		end
		local item = result.Items[bestIndex]
		local rarity = RaritiesConfig.ById[item.Rarity] or RaritiesConfig.List[1]
		local def = ArtistCalc.GetArtist(item.ArtistId)
		resultName.Text = if def then def.Name else item.ArtistId
		resultRarity.Text = rarity.Name
		resultRarity.TextColor3 = if rarity.Effect == "Gradient" or rarity.Effect == "Rainbow" then Color3.new(1, 1, 1) else rarity.Color
		setGradient(resultRarity, rarity)
		resultStroke.Color = rarity.Color
		if result.Preview then
			resultInfo.Text = "Pré-visualização: nada foi gasto nem entregue."
		elseif #result.Items == 1 then
			resultInfo.Text = if item.Outcome == "Deleted"
				then "Apagado pelo Auto-Delete."
				elseif item.Outcome == "Fused" then "Fundido automaticamente ★"
				else "Novo na tua coleção!"
		else
			resultInfo.Text = string.format("Melhor de %d · Novos %d · Fundidos %d · Apagados %d", #result.Items, counts.New, counts.Fused, counts.Deleted)
		end
		setPortrait(item, rarity)
		resultPanel.Visible = true
		buttons.Visible = true
		againButton.Visible = not result.Preview
		againButton.Text = "ABRIR DE NOVO x" .. #result.Items
	end

	local function finishPlay(token: number, result: CrateResult)
		if token ~= playToken then
			return
		end
		showResult(result)
		busy = false
		if CrateAnimController.HasQueued() then
			later(token, 0.8, playNext)
		end
	end

	-- Corre a cinemática para `item`; `after` quando acabar (ou for cancelada por morte)
	local function runMystery(token: number, result: CrateResult, item: CrateItem, after: () -> ())
		backdrop.Visible = false
		CrateAnimController.RunCinematic(item, result.CanSkip == true, function(_completed: boolean)
			if token ~= playToken or not isOpen then
				return
			end
			backdrop.Visible = true
			pulseLabel = nil
			pulseStroke = nil
			after()
		end)
	end

	local function playRoulette(token: number, result: CrateResult)
		local item = result.Items[1]
		local crate = ArtistCalc.GetCrate(result.CrateId)
		local rarity = RaritiesConfig.ById[item.Rarity] or RaritiesConfig.List[1]
		local cards = CrateAnimController.BuildRoulette(result.CrateId, item)
		for index, card in cards do
			setCardContent(stripCards[index], crate, card.ArtistId, card.Rarity, card.Mystery)
		end
		roulette.Visible = true

		local function centerOf(index: number): number
			return (index - 1) * pitch + rouletteCfg.CardWidth / 2
		end
		local fast = CrateAnimController.IsFast()
		local effect: RevealEffect = effectFor(item)
		local duration = if fast then rouletteCfg.FastDuration else rouletteCfg.Duration
		if effect == "Flash" and not fast then
			duration += rouletteCfg.SlowMotionExtra
		end
		local jitter = rng:NextNumber(-rouletteCfg.StopJitter, rouletteCfg.StopJitter) * rouletteCfg.CardWidth
		spin.FromX = ROULETTE_WIDTH / 2 - centerOf(rouletteCfg.StartIndex)
		spin.ToX = ROULETTE_WIDTH / 2 - (centerOf(rouletteCfg.WinnerIndex) + jitter)
		spin.Duration = duration
		spin.Start = os.clock()
		spin.LastIndex = rouletteCfg.StartIndex - 1
		strip.Position = UDim2.fromOffset(spin.FromX, 12)

		local winner = stripCards[rouletteCfg.WinnerIndex]
		spin.OnDone = function()
			if token ~= playToken then
				return
			end
			applyStopEffect(winner, effect, rarity)
			if item.Mystery then
				later(token, CrateAnimConfig.MysteryPause, function()
					runMystery(token, result, item, function()
						setCardContent(winner, crate, item.ArtistId, item.Rarity, false)
						applyStopEffect(winner, "Flash", rarity)
						finishPlay(token, result)
					end)
				end)
			else
				finishPlay(token, result)
			end
		end
		spin.Active = true
	end

	local function flipCard(card: CardRefs, swap: () -> ())
		local half = CrateAnimConfig.Grid.FlipTime / 2
		local shrink = TweenService:Create(card.Inner, TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.fromScale(0, 1) })
		shrink.Completed:Once(function()
			swap()
			TweenService:Create(card.Inner, TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 1) }):Play()
		end)
		shrink:Play()
	end

	local function playGrid(token: number, result: CrateResult)
		local crate = ArtistCalc.GetCrate(result.CrateId)
		local order = CrateAnimCalc.GetRevealOrder(result.Items)
		for index, card in gridCards do
			card.Outer.Visible = index <= #order
			card.Inner.Size = UDim2.fromScale(1, 1)
			setCardBack(card, crate)
		end
		grid.Visible = true
		local gridCfg = CrateAnimConfig.Grid
		local step = if CrateAnimController.IsFast() then gridCfg.FastRevealStep else gridCfg.RevealStep
		for slot, itemIndex in order do
			local item = result.Items[itemIndex]
			local card = gridCards[slot]
			later(token, gridCfg.StartDelay + (slot - 1) * step, function()
				flipCard(card, function()
					if token ~= playToken then
						return
					end
					setCardContent(card, crate, item.ArtistId, item.Rarity, item.Mystery == true)
					local effect: RevealEffect = effectFor(item)
					local rarity = RaritiesConfig.ById[item.Rarity] or RaritiesConfig.List[1]
					if effect == "Simple" then
						CrateSfx.Play("CrateTick")
					else
						applyStopEffect(card, effect, rarity)
					end
				end)
			end)
		end
		later(token, gridCfg.StartDelay + #order * step + gridCfg.FlipTime, function()
			local best = CrateAnimCalc.GetBestMystery(result.Items)
			if not best then
				finishPlay(token, result)
				return
			end
			later(token, CrateAnimConfig.MysteryPause, function()
				runMystery(token, result, result.Items[best], function()
					for slot, itemIndex in order do
						local item = result.Items[itemIndex]
						if item.Mystery then
							setCardContent(gridCards[slot], crate, item.ArtistId, item.Rarity, false)
							local rarity = RaritiesConfig.ById[item.Rarity] or RaritiesConfig.List[1]
							applyStopEffect(gridCards[slot], "Flash", rarity)
						end
					end
					finishPlay(token, result)
				end)
			end)
		end)
	end

	playNext = function()
		if busy then
			return
		end
		local result = CrateAnimController.PopNext()
		if not result then
			return
		end
		busy = true
		currentResult = result
		open()
		playToken += 1
		local token = playToken
		roulette.Visible = false
		grid.Visible = false
		resultPanel.Visible = false
		buttons.Visible = false
		pulseLabel = nil
		pulseStroke = nil
		clearPortrait()
		local crate = ArtistCalc.GetCrate(result.CrateId)
		title.Text = if crate then crate.Name else "Vinyl Crate"
		title.TextColor3 = if crate then crate.Color else Theme.Colors.Gold

		if result.CinematicOnly then
			local index = CrateAnimCalc.GetBestMystery(result.Items) or #result.Items
			runMystery(token, result, result.Items[index], function()
				finishPlay(token, result)
			end)
		elseif #result.Items <= 1 then
			playRoulette(token, result)
		else
			playGrid(token, result)
		end
	end

	-- Ligações -------------------------------------------------------------------------
	trove:Add(CrateAnimController.ResultQueued:Connect(function()
		playNext()
	end))
	trove:Connect(continueButton.Activated, function()
		close(false)
		ArtistsView.Open("Crates")
	end)
	trove:Connect(againButton.Activated, function()
		local result = currentResult
		if busy or not result or result.Preview then
			return
		end
		if ArtistController.OpenCrate(result.CrateId, #result.Items) then
			againButton.Visible = false
		else
			againButton.Rotation = 4
			TweenService:Create(againButton, TweenInfo.new(0.3, Enum.EasingStyle.Elastic), { Rotation = 0 }):Play()
		end
	end)

	local function updateScale()
		fitScale.Scale = Components.fitScale(gui.AbsoluteSize, DESIGN_SIZE, Theme.Shop.ScreenFill)
	end
	trove:Connect(gui:GetPropertyChangedSignal("AbsoluteSize"), updateScale)

	gui.Parent = playerGui
	cinematicGui.Parent = playerGui
	updateScale()
end

return CrateRevealView
