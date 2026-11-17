--!strict
--[[
	RemixView
	Painel "ESTÚDIO DE REMIX" (Fase 13B), aberto pelo ProximityPrompt do Estúdio na praça
	(Config/Crystals.Studio.PromptName). Registado no ModalManager. Três zonas:
	  - esquerda: a coleção do jogador (raridade, estrelas, traço atual)
	  - centro: a cara do artista selecionado (ViewportFrame focado na cabeça) e, por
	    baixo, a roleta VERTICAL de traços: uma janela onde se veem no máximo 3 traços
	    (o do meio inteiro, os das pontas cortados pela borda). Ao rodar, os traços descem
	    de cima para baixo, abrandam e param no traço sorteado pelo servidor. Botão RODAR
	    TRAÇO (pede confirmação só se o artista já tiver um traço)
	  - direita: probabilidades das raridades do traço e traços possíveis com os valores
	Os artistas nascem sem traço; o servidor valida posse, Cristais e sorteia.
	Desempenho: as cartas da roleta são uma pool fixa; o RenderStepped só existe com o
	painel aberto.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Types = require(ReplicatedStorage.Shared.Types)
local TraitsConfig = require(ReplicatedStorage.Shared.Config.Traits)
local CrystalsConfig = require(ReplicatedStorage.Shared.Config.Crystals)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local ArtistCalc = require(ReplicatedStorage.Shared.Calc.ArtistCalc)
local TraitCalc = require(ReplicatedStorage.Shared.Calc.TraitCalc)

local Client = script.Parent.Parent.Parent
local ArtistController = require(Client.Controllers.ArtistController)
local StateController = require(Client.Controllers.StateController)
local CinematicAssets = require(Client.Controllers.CinematicAssets)
local VariantVisuals = require(Client.Controllers.VariantVisuals)
local CrateSfx = require(Client.Controllers.CrateSfx)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local ModalManager = require(script.Parent.Parent.ModalManager)

type ArtistData = Types.ArtistData
type ArtistsSync = Types.ArtistsSync
type RemixResult = Types.RemixResult

type SlotItem = {
	Frame: Frame,
	Stroke: UIStroke,
	Name: TextLabel,
	Tier: TextLabel,
}

local MODAL_NAME = "Remix"
local PANEL_SIZE = Vector2.new(1010, 630)
local PURPLE = Color3.fromRGB(170, 90, 255)
local EMPTY_COLOR = Color3.fromRGB(70, 62, 98)

-- Roleta vertical
local SLOT_WIDTH = 270
local SLOT_HEIGHT = 156 -- janela: 1 traço inteiro ao meio + 2 cortados nas pontas
local ITEM_HEIGHT = 64
local ITEM_GAP = 6
local STRIP_COUNT = 32
local START_INDEX = STRIP_COUNT - 1 -- a faixa começa em baixo e desce: os traços vêm de cima
local RESULT_INDEX = 4
local SPIN_TIME = 2.6
local SPIN_POWER = 5 -- 1 - (1 - t)^5

-- O que cada tipo de traço melhora (os valores aparecem por baixo)
local KIND_TEXT: { [string]: string } = {
	ArtistHype = "Hype deste artista",
	ClickPower = "Hype por batida",
	Energy = "Energia do Bass Drop",
	BoostExtend = "Segundos extra de boost do Bass Drop",
	MachineCooldown = "Menos recarga do lança-chamas",
	PassiveHype = "Hype passivo global",
}

local RemixView = {}

local activeTrove: Trove.Trove? = nil

local function textButton(name: string, text: string, color: Color3, size: UDim2, maxText: number?): TextButton
	local button = Components.makeButton(name, color)
	button.Size = size
	button.Font = Theme.Fonts.Display
	button.TextColor3 = Theme.Colors.Text
	button.TextScaled = true
	button.Text = text
	Components.addCorner(button, UDim.new(0, 10))
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxText or 18
	constraint.Parent = button
	return button
end

local function percent(value: number): string
	return string.format("%d%%", math.floor(value * 100 + 0.5))
end

-- Valores de um traço por raridade, em texto curto (ex.: "10 / 20 / 35 / 60%")
local function valuesText(def: Types.TraitDef): string
	local parts: { string } = {}
	for _, value in def.Values do
		table.insert(parts, if def.Kind == "BoostExtend" then string.format("%.1fs", value) else percent(value))
	end
	return table.concat(parts, " / ")
end

-- Raridade do artista primeiro, depois raridade do traço
local function sortedUids(artists: { [string]: ArtistData }): { string }
	local uids: { string } = {}
	for uid in artists do
		table.insert(uids, uid)
	end
	table.sort(uids, function(a: string, b: string): boolean
		local artistA, artistB = artists[a], artists[b]
		local rarityA, rarityB = ArtistCalc.GetRarityIndex(artistA.Rarity), ArtistCalc.GetRarityIndex(artistB.Rarity)
		if rarityA ~= rarityB then
			return rarityA > rarityB
		end
		if artistA.Stars ~= artistB.Stars then
			return artistA.Stars > artistB.Stars
		end
		return (tonumber(a) or 0) < (tonumber(b) or 0)
	end)
	return uids
end

function RemixView.Mount()
	if activeTrove then
		return
	end
	local trove = Trove.new()
	activeTrove = trove
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local rng = Random.new()

	local gui = trove:Add(Instance.new("ScreenGui"))
	gui.Name = "RemixGui"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.DisplayOrder = 10

	local overlay = Components.makeButton("Overlay", Theme.Colors.Overlay)
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundTransparency = 1
	overlay.Visible = false
	overlay.Parent = gui

	local holder = Components.makeFrame("PanelHolder")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y)
	holder.Visible = false
	holder.Parent = gui
	local fitScale = Instance.new("UIScale")
	fitScale.Parent = holder

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.BorderSizePixel = 0
	panel.Active = true
	Components.addCorner(panel, UDim.new(0, 20))
	Components.addStroke(panel, PURPLE, 3)
	panel.Parent = holder
	local popScale = Instance.new("UIScale")
	popScale.Parent = panel

	local title = Components.makeLabel("Title", Theme.Fonts.Display, Color3.fromRGB(220, 180, 255), 30)
	title.Position = UDim2.fromOffset(22, 12)
	title.Size = UDim2.fromOffset(380, 36)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "ESTÚDIO DE REMIX"
	title.Parent = panel

	local crystalsLabel = Components.makeLabel("Crystals", Theme.Fonts.Display, Theme.Colors.Highlight, 24)
	crystalsLabel.AnchorPoint = Vector2.new(1, 0)
	crystalsLabel.Position = UDim2.new(1, -76, 0, 14)
	crystalsLabel.Size = UDim2.fromOffset(280, 32)
	crystalsLabel.TextXAlignment = Enum.TextXAlignment.Right
	crystalsLabel.Parent = panel

	local closeButton = textButton("Close", "X", Theme.Colors.Danger, UDim2.fromOffset(46, 46), 22)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -16, 0, 8)
	closeButton.Parent = panel

	local hint = Components.makeLabel("Hint", Theme.Fonts.Body, Theme.Colors.TextMuted, 14)
	hint.Position = UDim2.fromOffset(22, 50)
	hint.Size = UDim2.new(1, -44, 0, 18)
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Text = "Os artistas não têm traço: roda para lhe dar um (ou trocar o que tem). Ganhas Cristais ao fundir artistas."
	hint.Parent = panel

	-- ============ Esquerda: coleção ============
	local list = Instance.new("ScrollingFrame")
	list.Name = "Collection"
	list.Position = UDim2.fromOffset(16, 78)
	list.Size = UDim2.fromOffset(430, PANEL_SIZE.Y - 94)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = PURPLE
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel
	local listLayout = Instance.new("UIGridLayout")
	listLayout.CellSize = UDim2.fromOffset(134, 96)
	listLayout.CellPadding = UDim2.fromOffset(8, 8)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list
	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop = UDim.new(0, 4)
	listPadding.PaddingLeft = UDim.new(0, 4)
	listPadding.Parent = list

	local emptyLabel = Components.makeLabel("Empty", Theme.Fonts.Body, Theme.Colors.TextMuted, 18)
	emptyLabel.Position = UDim2.fromOffset(16, 120)
	emptyLabel.Size = UDim2.fromOffset(430, 40)
	emptyLabel.Text = "Ainda não tens artistas. Abre uma Vinyl Crate!"
	emptyLabel.Visible = false
	emptyLabel.Parent = panel

	-- ============ Centro: cara do artista + roleta vertical ============
	local center = Components.makeFrame("Center")
	center.Position = UDim2.fromOffset(458, 78)
	center.Size = UDim2.fromOffset(SLOT_WIDTH + 20, PANEL_SIZE.Y - 94)
	center.Parent = panel

	local portrait = Instance.new("ViewportFrame")
	portrait.Name = "Face"
	portrait.AnchorPoint = Vector2.new(0.5, 0)
	portrait.Position = UDim2.new(0.5, 0, 0, 0)
	portrait.Size = UDim2.fromOffset(SLOT_WIDTH, 176)
	portrait.BackgroundColor3 = Theme.Colors.Background
	portrait.Ambient = Color3.fromRGB(200, 200, 210)
	portrait.LightColor = Color3.new(1, 1, 1)
	Components.addCorner(portrait, UDim.new(0, 14))
	local portraitStroke = Components.addStroke(portrait, PURPLE, 2)
	portrait.Parent = center
	local portraitCamera = Instance.new("Camera")
	portraitCamera.FieldOfView = 32
	portraitCamera.Parent = portrait
	portrait.CurrentCamera = portraitCamera

	local artistName = Components.makeLabel("Name", Theme.Fonts.Display, Theme.Colors.Text, 22)
	artistName.Position = UDim2.fromOffset(10, 182)
	artistName.Size = UDim2.new(1, -20, 0, 26)
	artistName.Parent = center

	local artistRarity = Components.makeLabel("Rarity", Theme.Fonts.Body, Theme.Colors.TextMuted, 15)
	artistRarity.Position = UDim2.fromOffset(10, 208)
	artistRarity.Size = UDim2.new(1, -20, 0, 18)
	artistRarity.Parent = center

	-- Janela da roleta: só se vê uma parte da faixa (ClipsDescendants)
	local slot = Instance.new("Frame")
	slot.Name = "TraitSlot"
	slot.AnchorPoint = Vector2.new(0.5, 0)
	slot.Position = UDim2.new(0.5, 0, 0, 232)
	slot.Size = UDim2.fromOffset(SLOT_WIDTH, SLOT_HEIGHT)
	slot.BackgroundColor3 = Theme.Colors.Background
	slot.BorderSizePixel = 0
	slot.ClipsDescendants = true
	Components.addCorner(slot, UDim.new(0, 14))
	local slotStroke = Components.addStroke(slot, PURPLE, 3)
	slot.Parent = center

	local strip = Components.makeFrame("Strip")
	strip.Size = UDim2.fromOffset(SLOT_WIDTH, STRIP_COUNT * (ITEM_HEIGHT + ITEM_GAP))
	strip.Parent = slot

	local slotItems: { SlotItem } = {}
	for index = 1, STRIP_COUNT do
		local frame = Instance.new("Frame")
		frame.Name = "Trait" .. index
		frame.AnchorPoint = Vector2.new(0.5, 0)
		frame.Position = UDim2.new(0.5, 0, 0, (index - 1) * (ITEM_HEIGHT + ITEM_GAP))
		frame.Size = UDim2.fromOffset(SLOT_WIDTH - 24, ITEM_HEIGHT)
		frame.BorderSizePixel = 0
		Components.addCorner(frame, UDim.new(0, 12))
		local stroke = Components.addStroke(frame, EMPTY_COLOR, 2)
		frame.Parent = strip
		local name = Components.makeLabel("Name", Theme.Fonts.Display, Theme.Colors.Text, 20)
		name.Position = UDim2.fromOffset(8, 6)
		name.Size = UDim2.new(1, -16, 0, 30)
		Components.addStroke(name, Theme.Colors.Background, 1.5)
		name.Parent = frame
		local tier = Components.makeLabel("Tier", Theme.Fonts.Body, Theme.Colors.Text, 14)
		tier.Position = UDim2.fromOffset(8, 38)
		tier.Size = UDim2.new(1, -16, 0, 18)
		Components.addStroke(tier, Theme.Colors.Background, 1)
		tier.Parent = frame
		table.insert(slotItems, { Frame = frame, Stroke = stroke, Name = name, Tier = tier })
	end

	-- Marcadores laterais do traço do meio
	for _, side in { 0, 1 } do
		local arrow = Instance.new("Frame")
		arrow.Name = if side == 0 then "ArrowLeft" else "ArrowRight"
		arrow.AnchorPoint = Vector2.new(0.5, 0.5)
		arrow.Position = UDim2.fromScale(side, 0.5)
		arrow.Size = UDim2.fromOffset(18, 18)
		arrow.Rotation = 45
		arrow.BackgroundColor3 = Theme.Colors.Gold
		arrow.BorderSizePixel = 0
		arrow.ZIndex = 5
		arrow.Parent = slot
	end
	-- Sombras nas pontas: reforçam que só se vê uma parte da roleta
	for _, top in { true, false } do
		local shade = Instance.new("Frame")
		shade.Name = if top then "ShadeTop" else "ShadeBottom"
		shade.AnchorPoint = Vector2.new(0, if top then 0 else 1)
		shade.Position = UDim2.fromScale(0, if top then 0 else 1)
		shade.Size = UDim2.new(1, 0, 0, 40)
		shade.BackgroundColor3 = Theme.Colors.Background
		shade.BorderSizePixel = 0
		shade.ZIndex = 4
		local fade = Instance.new("UIGradient")
		fade.Rotation = if top then 90 else -90
		fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		fade.Parent = shade
		shade.Parent = slot
	end

	local effectLabel = Components.makeLabel("Effect", Theme.Fonts.Body, Theme.Colors.Text, 15)
	effectLabel.Position = UDim2.fromOffset(10, 232 + SLOT_HEIGHT + 6)
	effectLabel.Size = UDim2.new(1, -20, 0, 34)
	effectLabel.TextWrapped = true
	effectLabel.Parent = center

	local costLabel = Components.makeLabel("Cost", Theme.Fonts.Display, Theme.Colors.Highlight, 18)
	costLabel.Position = UDim2.fromOffset(10, 232 + SLOT_HEIGHT + 42)
	costLabel.Size = UDim2.new(1, -20, 0, 24)
	costLabel.Parent = center

	local spinButton = textButton("Spin", "RODAR TRAÇO", PURPLE, UDim2.new(1, -20, 0, 52), 22)
	spinButton.AnchorPoint = Vector2.new(0.5, 1)
	spinButton.Position = UDim2.new(0.5, 0, 1, 0)
	spinButton.Parent = center
	local spinScale = Instance.new("UIScale")
	spinScale.Parent = spinButton

	-- ============ Direita: probabilidades e traços possíveis ============
	local odds = Instance.new("Frame")
	odds.Name = "Odds"
	odds.AnchorPoint = Vector2.new(1, 0)
	odds.Position = UDim2.new(1, -16, 0, 78)
	odds.Size = UDim2.fromOffset(PANEL_SIZE.X - 458 - SLOT_WIDTH - 20 - 28, PANEL_SIZE.Y - 94)
	odds.BackgroundColor3 = Theme.Colors.Background
	odds.BorderSizePixel = 0
	Components.addCorner(odds, UDim.new(0, 14))
	Components.addStroke(odds, PURPLE, 1.5)
	odds.Parent = panel
	local oddsLayout = Instance.new("UIListLayout")
	oddsLayout.Padding = UDim.new(0, 6)
	oddsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	oddsLayout.Parent = odds
	local oddsPadding = Instance.new("UIPadding")
	oddsPadding.PaddingTop = UDim.new(0, 10)
	oddsPadding.PaddingLeft = UDim.new(0, 12)
	oddsPadding.PaddingRight = UDim.new(0, 12)
	oddsPadding.Parent = odds

	local order = 0
	local function oddsLabel(text: string, font: Enum.Font, size: number, color: Color3, height: number): TextLabel
		order += 1
		local label = Components.makeLabel("Line" .. order, font, color, size)
		label.LayoutOrder = order
		label.Size = UDim2.new(1, 0, 0, height)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextWrapped = true
		label.Text = text
		label.Parent = odds
		return label
	end
	oddsLabel("PROBABILIDADES", Theme.Fonts.Display, 18, Theme.Colors.Gold, 22)
	for _, tier in TraitsConfig.Tiers do
		order += 1
		local row = Instance.new("Frame")
		row.Name = tier.Id
		row.LayoutOrder = order
		row.Size = UDim2.new(1, 0, 0, 26)
		row.BackgroundColor3 = Theme.Colors.Panel
		row.BorderSizePixel = 0
		Components.addCorner(row, UDim.new(0, 8))
		row.Parent = odds
		local bar = Instance.new("Frame")
		bar.Size = UDim2.fromScale(math.max(tier.Weight / 100, 0.04), 1)
		bar.BackgroundColor3 = tier.Color
		bar.BackgroundTransparency = 0.35
		bar.BorderSizePixel = 0
		Components.addCorner(bar, UDim.new(0, 8))
		bar.Parent = row
		local label = Components.makeLabel("Label", Theme.Fonts.Display, Theme.Colors.Text, 15)
		label.Position = UDim2.fromOffset(8, 0)
		label.Size = UDim2.new(1, -16, 1, 0)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = string.format("%s · %d%%", tier.Name, tier.Weight)
		Components.addStroke(label, Theme.Colors.Background, 1.5)
		label.Parent = row
	end
	oddsLabel(" ", Theme.Fonts.Body, 6, Theme.Colors.Text, 6)
	oddsLabel(string.format("TRAÇOS POSSÍVEIS (%d, igual chance)", #TraitsConfig.List), Theme.Fonts.Display, 16, Theme.Colors.Gold, 22)
	oddsLabel("Valores: Comum / Raro / Épico / Lendário", Theme.Fonts.Body, 12, Theme.Colors.TextMuted, 16)
	for _, def in TraitsConfig.List do
		oddsLabel(def.Name, Theme.Fonts.Display, 15, Theme.Colors.Text, 18)
		oddsLabel((KIND_TEXT[def.Kind] or "") .. "\n" .. valuesText(def), Theme.Fonts.Body, 12, Theme.Colors.TextMuted, 32)
	end

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 20
	Components.addCorner(flash, UDim.new(0, 20))
	flash.Parent = panel

	-- Estado ---------------------------------------------------------------------------
	local isOpen = false
	local selectedUid: string? = nil
	local confirmUntil = 0
	local pendingUid: string? = nil -- pedido enviado, à espera do resultado
	local spinning = false
	local spinStart = 0
	local spinFrom = 0
	local spinTo = 0
	local lastTick = -1
	local landResult: RemixResult? = nil
	local portraitRig: Model? = nil
	local portraitBase = CFrame.new()
	local renderConnection: RBXScriptConnection? = nil
	local listTrove = trove:Extend()

	local function crystals(): number
		local snapshot = StateController.Get()
		return if snapshot then snapshot.Crystals or 0 else 0
	end

	-- Y da faixa para o traço `index` ficar ao centro da janela
	local function stripYFor(index: number): number
		return SLOT_HEIGHT / 2 - ITEM_HEIGHT / 2 - (index - 1) * (ITEM_HEIGHT + ITEM_GAP)
	end

	local function setItem(item: SlotItem, traitId: string, tierId: string)
		local trait = TraitCalc.Get(traitId)
		local tier = TraitCalc.GetTier(tierId)
		if trait and tier then
			item.Frame.BackgroundColor3 = Theme.Colors.Panel:Lerp(tier.Color, 0.35)
			item.Stroke.Color = tier.Color
			item.Name.Text = trait.Name
			item.Tier.Text = tier.Name
			item.Tier.TextColor3 = tier.Color
		else
			item.Frame.BackgroundColor3 = Theme.Colors.Panel
			item.Stroke.Color = EMPTY_COLOR
			item.Name.Text = "Sem traço"
			item.Tier.Text = "roda para ganhar um"
			item.Tier.TextColor3 = Theme.Colors.TextMuted
		end
	end

	-- Enche a faixa com traços aleatórios (pesos reais) e põe `traitId` no índice `centerIndex`
	local function fillStrip(centerIndex: number, traitId: string, tierId: string)
		for index, item in slotItems do
			if index == centerIndex then
				setItem(item, traitId, tierId)
			else
				local fillerTrait, fillerTier = TraitCalc.Roll(rng)
				setItem(item, fillerTrait, fillerTier)
			end
		end
	end

	-- Roleta parada a mostrar o traço atual do artista
	local function showIdle(artist: ArtistData?)
		spinning = false
		fillStrip(START_INDEX, if artist then artist.Trait else "", if artist then artist.TraitTier else "")
		strip.Position = UDim2.fromOffset(0, stripYFor(START_INDEX))
		local tier = if artist then TraitCalc.GetTier(artist.TraitTier) else nil
		slotStroke.Color = if tier then tier.Color else PURPLE
	end

	local function clearPortrait()
		local rig = portraitRig
		if rig then
			rig:Destroy()
			portraitRig = nil
		end
	end

	-- A cara do artista: câmara focada na cabeça
	local function showPortrait(artist: ArtistData?)
		clearPortrait()
		if not artist then
			return
		end
		local rarity = ArtistCalc.GetRarity(artist.Rarity)
		local rig = CinematicAssets.GetArtistRig(artist.Id, if rarity then rarity.Color else PURPLE)
		VariantVisuals.Apply(rig, artist.Variant)
		rig:PivotTo(CFrame.new())
		local head = rig:FindFirstChild("Head")
		local focus: Vector3
		local size: number
		if head and head:IsA("BasePart") then
			focus = head.Position + Vector3.new(0, -head.Size.Y * 0.35, 0)
			size = math.max(head.Size.X, head.Size.Y) * 2.6
		else
			local boxCFrame, boxSize = rig:GetBoundingBox()
			focus = boxCFrame.Position + Vector3.new(0, boxSize.Y * 0.3, 0)
			size = boxSize.Y * 0.6
		end
		portraitCamera.CFrame = CFrame.lookAt(focus + Vector3.new(0, size * 0.1, size * 2.4), focus)
		portraitBase = rig:GetPivot()
		rig.Parent = portrait
		portraitRig = rig
		portraitStroke.Color = if rarity then rarity.Color else PURPLE
		portrait.BackgroundColor3 = Theme.Colors.Background:Lerp(if rarity then rarity.Color else PURPLE, 0.2)
	end

	local function refreshDetail()
		local sync = ArtistController.Get()
		local uid = selectedUid
		local artist = if sync and uid then sync.Artists[uid] else nil
		crystalsLabel.Text = string.format("💎 %d Cristais", crystals())
		spinButton.Visible = artist ~= nil
		costLabel.Visible = artist ~= nil
		if not artist then
			artistName.Text = "Escolhe um artista"
			artistRarity.Text = "da tua coleção, à esquerda"
			effectLabel.Text = ""
			return
		end
		local def = ArtistCalc.GetArtist(artist.Id)
		local rarity = ArtistCalc.GetRarity(artist.Rarity)
		artistName.Text = if def then def.Name else artist.Id
		artistRarity.Text = string.format("%s %s", if rarity then rarity.Name else artist.Rarity, string.rep("★", artist.Stars))
		artistRarity.TextColor3 = if rarity then rarity.Color else Theme.Colors.TextMuted
		if not spinning then
			effectLabel.Text = if artist.Trait ~= "" then TraitCalc.DescribeEffect(artist.Trait, artist.TraitTier) else "Este artista ainda não tem traço."
		end
		local cost = TraitCalc.GetRemixCost(if rarity then rarity.Family else "Common")
		local affordable = crystals() >= cost
		costLabel.Text = string.format("Custo: 💎 %d", cost)
		costLabel.TextColor3 = if affordable then Theme.Colors.Highlight else Theme.Colors.Danger
		local confirming = os.clock() < confirmUntil
		spinButton.Text = if spinning or pendingUid then "A RODAR..." elseif confirming then "CONFIRMAR? (troca o traço)" else "RODAR TRAÇO"
		spinButton.BackgroundColor3 = if not affordable or spinning or pendingUid
			then Theme.Colors.Disabled
			elseif confirming then Theme.Colors.Danger
			else PURPLE
	end

	local function rebuildList()
		listTrove:Clean()
		local sync = ArtistController.Get()
		local artists = if sync then sync.Artists else {}
		local uids = sortedUids(artists)
		emptyLabel.Visible = #uids == 0
		if selectedUid and not artists[selectedUid] then
			selectedUid = nil
		end
		for index, uid in uids do
			local artist = artists[uid]
			local def = ArtistCalc.GetArtist(artist.Id)
			local rarity = ArtistCalc.GetRarity(artist.Rarity)
			local tier = TraitCalc.GetTier(artist.TraitTier)
			local trait = TraitCalc.Get(artist.Trait)

			local tile = listTrove:Add(Components.makeButton("Artist_" .. uid, Theme.Colors.Background))
			tile.LayoutOrder = index
			tile.Text = ""
			Components.addCorner(tile, UDim.new(0, 12))
			Components.addStroke(tile, if uid == selectedUid then Theme.Colors.Text else (if rarity then rarity.Color else PURPLE), if uid == selectedUid then 3 else 1.5)
			tile.Parent = list
			local hover = Instance.new("UIScale")
			hover.Parent = tile

			local band = Instance.new("Frame")
			band.Size = UDim2.new(1, 0, 0, 26)
			band.BackgroundColor3 = if rarity then rarity.Color else PURPLE
			band.BorderSizePixel = 0
			Components.addCorner(band, UDim.new(0, 12))
			band.Parent = tile
			local rarityLabel = Components.makeLabel("Rarity", Theme.Fonts.Display, Theme.Colors.Text, 14)
			rarityLabel.Position = UDim2.fromOffset(6, 2)
			rarityLabel.Size = UDim2.new(1, -12, 0, 22)
			rarityLabel.Text = string.format("%s %s", if rarity then rarity.Name else artist.Rarity, string.rep("★", artist.Stars))
			Components.addStroke(rarityLabel, Theme.Colors.Background, 1.5)
			rarityLabel.Parent = band

			local name = Components.makeLabel("Name", Theme.Fonts.Display, Theme.Colors.Text, 15)
			name.Position = UDim2.fromOffset(6, 30)
			name.Size = UDim2.new(1, -12, 0, 30)
			name.TextWrapped = true
			name.Text = if def then def.Name else artist.Id
			name.Parent = tile

			local traitLabel = Components.makeLabel("Trait", Theme.Fonts.Body, if tier then tier.Color else Theme.Colors.TextMuted, 12)
			traitLabel.Position = UDim2.fromOffset(6, 64)
			traitLabel.Size = UDim2.new(1, -12, 0, 26)
			traitLabel.TextWrapped = true
			traitLabel.Text = if trait and tier then string.format("%s (%s)", trait.Name, tier.Name) else "Sem traço"
			traitLabel.Parent = tile

			listTrove:Connect(tile.MouseEnter, function()
				TweenService:Create(hover, TweenInfo.new(0.12), { Scale = 1.05 }):Play()
			end)
			listTrove:Connect(tile.MouseLeave, function()
				TweenService:Create(hover, TweenInfo.new(0.12), { Scale = 1 }):Play()
			end)
			listTrove:Connect(tile.Activated, function()
				if spinning or pendingUid then
					return
				end
				selectedUid = uid
				confirmUntil = 0
				showPortrait(artist)
				showIdle(artist)
				rebuildList()
			end)
		end
		refreshDetail()
	end

	-- Começa a rodar até ao traço sorteado pelo servidor
	local function startSpin(result: RemixResult)
		fillStrip(RESULT_INDEX, result.Trait, result.Tier)
		-- O topo (traço atual) fica no índice de partida, para a roleta arrancar dele
		setItem(slotItems[START_INDEX], result.OldTrait, result.OldTier)
		spinFrom = stripYFor(START_INDEX)
		spinTo = stripYFor(RESULT_INDEX) + rng:NextNumber(-0.25, 0.25) * ITEM_HEIGHT
		spinStart = os.clock()
		lastTick = START_INDEX
		landResult = result
		spinning = true
		effectLabel.Text = ""
		slotStroke.Color = PURPLE
		refreshDetail()
	end

	local function land(result: RemixResult)
		spinning = false
		strip.Position = UDim2.fromOffset(0, stripYFor(RESULT_INDEX))
		local item = slotItems[RESULT_INDEX]
		local tier = TraitCalc.GetTier(result.Tier)
		slotStroke.Color = if tier then tier.Color else PURPLE
		local pop = Instance.new("UIScale")
		pop.Scale = 1.25
		pop.Parent = item.Frame
		TweenService:Create(pop, Theme.Tween.Toast, { Scale = 1 }):Play()
		task.delay(0.6, function()
			pop:Destroy()
		end)
		effectLabel.Text = "Novo traço! " .. TraitCalc.DescribeEffect(result.Trait, result.Tier)
		if result.Tier == TraitsConfig.AnnounceTier then
			flash.BackgroundTransparency = 0.2
			TweenService:Create(flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
			CrateSfx.Play("CrateLegendary")
		elseif TraitCalc.GetTierIndex(result.Tier) >= 2 then
			CrateSfx.Play("CrateRare")
		else
			CrateSfx.Play("CrateStop")
		end
		refreshDetail()
		rebuildList()
	end

	local function onRender(dt: number)
		if spinning then
			local t = math.clamp((os.clock() - spinStart) / SPIN_TIME, 0, 1)
			local eased = 1 - (1 - t) ^ SPIN_POWER
			local y = spinFrom + (spinTo - spinFrom) * eased
			strip.Position = UDim2.fromOffset(0, y)
			-- Traço no centro (para o "tick")
			local centerIndex = math.floor((SLOT_HEIGHT / 2 - y) / (ITEM_HEIGHT + ITEM_GAP)) + 1
			if centerIndex ~= lastTick then
				lastTick = centerIndex
				CrateSfx.Play("CrateTick")
			end
			if t >= 1 then
				local result = landResult
				landResult = nil
				if result then
					land(result)
				else
					spinning = false
				end
			end
		end
		local rig = portraitRig
		if rig then
			-- A cara balança um pouco para os lados
			rig:PivotTo(portraitBase * CFrame.Angles(0, math.sin(os.clock() * 0.8) * 0.35, 0))
		end
		local _ = dt
	end

	local function setOpen(open: boolean)
		if isOpen == open then
			return
		end
		isOpen = open
		if open then
			ModalManager.NotifyOpened(MODAL_NAME)
			overlay.Visible = true
			holder.Visible = true
			popScale.Scale = 0.85
			TweenService:Create(popScale, Theme.Tween.Toast, { Scale = 1 }):Play()
			TweenService:Create(overlay, Theme.Tween.Fast, { BackgroundTransparency = Theme.Shop.OverlayTransparency }):Play()
			confirmUntil = 0
			local sync = ArtistController.Get()
			local artist = if sync and selectedUid then sync.Artists[selectedUid] else nil
			showPortrait(artist)
			showIdle(artist)
			rebuildList()
			renderConnection = RunService.RenderStepped:Connect(onRender)
		else
			ModalManager.NotifyClosed(MODAL_NAME)
			local connection = renderConnection
			if connection then
				connection:Disconnect()
				renderConnection = nil
			end
			-- Fechar a meio da roleta não perde nada: o traço já foi entregue pelo servidor
			spinning = false
			landResult = nil
			pendingUid = nil
			clearPortrait()
			local closing = TweenService:Create(popScale, Theme.Tween.FadeOut, { Scale = 0.85 })
			TweenService:Create(overlay, Theme.Tween.FadeOut, { BackgroundTransparency = 1 }):Play()
			closing.Completed:Once(function()
				if not isOpen then
					overlay.Visible = false
					holder.Visible = false
				end
			end)
			closing:Play()
		end
	end
	ModalManager.Register(MODAL_NAME, function()
		setOpen(false)
	end)
	trove:Add(function()
		ModalManager.Unregister(MODAL_NAME)
	end)

	-- Ligações -------------------------------------------------------------------------
	trove:Connect(spinButton.Activated, function()
		local uid = selectedUid
		local sync = ArtistController.Get()
		local artist = if sync and uid then sync.Artists[uid] else nil
		if not uid or not artist or spinning or pendingUid then
			return
		end
		local rarity = ArtistCalc.GetRarity(artist.Rarity)
		if crystals() < TraitCalc.GetRemixCost(if rarity then rarity.Family else "Common") then
			spinButton.Rotation = 4
			TweenService:Create(spinButton, TweenInfo.new(0.3, Enum.EasingStyle.Elastic), { Rotation = 0 }):Play()
			return
		end
		-- Só pede confirmação se houver um traço a perder
		if artist.Trait ~= "" and os.clock() >= confirmUntil then
			confirmUntil = os.clock() + CrystalsConfig.ConfirmTime
			refreshDetail()
			task.delay(CrystalsConfig.ConfirmTime, function()
				if isOpen then
					refreshDetail()
				end
			end)
			return
		end
		confirmUntil = 0
		if ArtistController.Remix(uid) then
			pendingUid = uid
			spinScale.Scale = 0.9
			TweenService:Create(spinScale, Theme.Tween.Toast, { Scale = 1 }):Play()
		end
		refreshDetail()
	end)
	trove:Connect(spinButton.MouseEnter, function()
		TweenService:Create(spinScale, TweenInfo.new(0.12), { Scale = 1.04 }):Play()
	end)
	trove:Connect(spinButton.MouseLeave, function()
		TweenService:Create(spinScale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)

	trove:Add(ArtistController.Remixed:Connect(function(result: RemixResult)
		if not isOpen or result.Uid ~= pendingUid then
			pendingUid = nil
			return
		end
		pendingUid = nil
		startSpin(result)
	end))
	trove:Add(ArtistController.Changed:Connect(function(_sync: ArtistsSync)
		if isOpen and not spinning then
			rebuildList()
		end
	end))
	trove:Add(StateController.Changed:Connect(function()
		if isOpen then
			refreshDetail()
		end
	end))
	trove:Connect(ProximityPromptService.PromptTriggered, function(prompt: ProximityPrompt, player: Player)
		if prompt.Name == CrystalsConfig.Studio.PromptName and player == Players.LocalPlayer then
			setOpen(true)
		end
	end)
	trove:Connect(closeButton.Activated, function()
		setOpen(false)
	end)
	trove:Connect(overlay.Activated, function()
		setOpen(false)
	end)

	local function updateScale()
		fitScale.Scale = Components.fitScale(gui.AbsoluteSize, PANEL_SIZE, Theme.Shop.ScreenFill)
	end
	trove:Connect(gui:GetPropertyChangedSignal("AbsoluteSize"), updateScale)
	gui.Parent = playerGui
	updateScale()
end

return RemixView
