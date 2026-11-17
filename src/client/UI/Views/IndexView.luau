--!strict
--[[
	IndexView
	Painel "ÍNDICE DE ARTISTAS" (Fase 10), registado no ModalManager:
	  - fila com as 22 raridades (cor, progresso "3/5", ponto vermelho se há prémio)
	  - grelha das combinações artista × raridade da raridade escolhida: descobertas a
	    cores, as que faltam em silhueta com "???"
	  - detalhe com o modelo 3D (um único ViewportFrame) e o prémio da raridade (RECLAMAR)
	  - prémio final (Índice completo) e modo da vitrine
	Botão ÍNDICE no menu lateral (posição 7), tecla I. Indicador quando há prémios.
	Tudo o que mostra vem de IndexCalc (o servidor valida com as mesmas regras).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local RaritiesConfig = require(ReplicatedStorage.Shared.Config.Rarities)
local ArtistIndexConfig = require(ReplicatedStorage.Shared.Config.ArtistIndex)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local ArtistCalc = require(ReplicatedStorage.Shared.Calc.ArtistCalc)
local IndexCalc = require(ReplicatedStorage.Shared.Calc.IndexCalc)
local VariantCalc = require(ReplicatedStorage.Shared.Calc.VariantCalc)
local VariantsConfig = require(ReplicatedStorage.Shared.Config.Variants)

local Client = script.Parent.Parent.Parent
local IndexController = require(Client.Controllers.IndexController)
local CinematicAssets = require(Client.Controllers.CinematicAssets)
local VariantVisuals = require(Client.Controllers.VariantVisuals)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local ModalManager = require(script.Parent.Parent.ModalManager)
local SideMenu = require(script.Parent.Parent.SideMenu)

type IndexSync = Types.IndexSync
type RarityDef = Types.RarityDef

type Chip = {
	Button: TextButton,
	Progress: TextLabel,
	Dot: Frame,
	Stroke: UIStroke,
}

type Card = {
	Button: TextButton,
	Head: Frame,
	Body: Frame,
	Name: TextLabel,
	Crate: TextLabel,
	Stroke: UIStroke,
}

local MODAL_NAME = "Index"
local PANEL_SIZE = Vector2.new(860, 620)
local TOGGLE_KEY = Enum.KeyCode.I
local MAX_CARDS = 25 -- 10 por raridade; 25 artistas por variante
local BLACK = Color3.new(0, 0, 0)
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 200, 40)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(60, 255, 120)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(40, 200, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 200)),
})

local IndexView = {}

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

local function rewardText(key: string): string
	if key == ArtistIndexConfig.FinalKey then
		local final = ArtistIndexConfig.Final
		return string.format("+%d slot de artista · %d Discos · título \"%s\"", final.SlotBonus, final.Discs, final.Title)
	end
	local reward = IndexCalc.GetReward(key)
	if not reward then
		return ""
	end
	local parts: { string } = {}
	if (reward.Crates or 0) > 0 then
		table.insert(parts, (reward.Crates :: number) .. " crates grátis")
	end
	if (reward.Discs or 0) > 0 then
		table.insert(parts, (reward.Discs :: number) .. " Discos")
	end
	return table.concat(parts, " + ")
end

function IndexView.Mount()
	if activeTrove then
		return
	end
	local trove = Trove.new()
	activeTrove = trove
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Botão ÍNDICE (menu lateral) ----------------------------------------------------
	local toggleGui = trove:Add(Instance.new("ScreenGui"))
	toggleGui.Name = "IndexToggleGui"
	toggleGui.ResetOnSpawn = false
	toggleGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets

	local toggleHolder = Components.makeFrame("IndexToggle")
	toggleHolder.Size = UDim2.fromOffset(112, 100)
	trove:Add(toggleHolder)
	local toggleScale = Instance.new("UIScale")
	toggleScale.Parent = toggleHolder

	local toggleButton = Components.makeButton("Button", Theme.Colors.Panel)
	toggleButton.Size = UDim2.fromScale(1, 1)
	Components.addCorner(toggleButton, UDim.new(0, 22))
	Components.addStroke(toggleButton, Theme.Colors.Highlight, 3)
	toggleButton.Parent = toggleHolder

	local toggleLabel = Components.makeLabel("Label", Theme.Fonts.Display, Theme.Colors.Text, 22)
	toggleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	toggleLabel.Position = UDim2.fromScale(0.5, 0.42)
	toggleLabel.Size = UDim2.new(0.9, 0, 0, 28)
	toggleLabel.Text = "ÍNDICE"
	Components.addStroke(toggleLabel, Theme.Colors.Background, 2)
	toggleLabel.Parent = toggleButton

	local toggleHint = Components.makeLabel("Hint", Theme.Fonts.Body, Theme.Colors.TextMuted, 16)
	toggleHint.AnchorPoint = Vector2.new(0.5, 0.5)
	toggleHint.Position = UDim2.fromScale(0.5, 0.74)
	toggleHint.Size = UDim2.new(0.8, 0, 0, 18)
	toggleHint.Text = "[I]"
	toggleHint.Visible = UserInputService.KeyboardEnabled
	toggleHint.Parent = toggleButton

	local badge = Components.makeLabel("Badge", Theme.Fonts.Display, Theme.Colors.Text, 16)
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.new(1, -8, 0, 8)
	badge.Size = UDim2.fromOffset(26, 26)
	badge.BackgroundTransparency = 0
	badge.BackgroundColor3 = Theme.Colors.Danger
	badge.Visible = false
	badge.ZIndex = 3
	Components.addCorner(badge, UDim.new(1, 0))
	badge.Parent = toggleButton

	SideMenu.Attach(toggleHolder, 7)

	-- Painel -------------------------------------------------------------------------
	local panelGui = trove:Add(Instance.new("ScreenGui"))
	panelGui.Name = "IndexPanelGui"
	panelGui.ResetOnSpawn = false
	panelGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	panelGui.ScreenInsets = Enum.ScreenInsets.None
	panelGui.DisplayOrder = 10

	local overlay = Components.makeButton("Overlay", Theme.Colors.Overlay)
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundTransparency = 1
	overlay.Visible = false
	overlay.Parent = panelGui

	local holder = Components.makeFrame("PanelHolder")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y)
	holder.Visible = false
	holder.Parent = panelGui
	local fitScale = Instance.new("UIScale")
	fitScale.Parent = holder

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.BorderSizePixel = 0
	panel.Active = true
	Components.addCorner(panel, UDim.new(0, 20))
	Components.addStroke(panel, Theme.Colors.Highlight, 3)
	panel.Parent = holder
	local popScale = Instance.new("UIScale")
	popScale.Parent = panel

	local title = Components.makeLabel("Title", Theme.Fonts.Display, Theme.Colors.Highlight, 30)
	title.Position = UDim2.fromOffset(22, 12)
	title.Size = UDim2.new(0, 290, 0, 36)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "ÍNDICE DE ARTISTAS"
	title.Parent = panel

	local totalLabel = Components.makeLabel("Total", Theme.Fonts.Display, Theme.Colors.Gold, 24)
	totalLabel.Position = UDim2.fromOffset(318, 14)
	totalLabel.Size = UDim2.fromOffset(110, 32)
	totalLabel.TextXAlignment = Enum.TextXAlignment.Left
	totalLabel.Parent = panel

	-- Raridades | Variantes Brilhantes
	local modeButton = textButton("Mode", "★ VARIANTES", Theme.Colors.Background, UDim2.fromOffset(146, 38), 16)
	modeButton.Position = UDim2.fromOffset(432, 12)
	modeButton.Parent = panel

	local showcaseButton = textButton("Showcase", "VITRINE: AUTO", Theme.Colors.Background, UDim2.fromOffset(200, 38), 16)
	showcaseButton.AnchorPoint = Vector2.new(1, 0)
	showcaseButton.Position = UDim2.new(1, -76, 0, 12)
	showcaseButton.Parent = panel

	local closeButton = textButton("Close", "X", Theme.Colors.Danger, UDim2.fromOffset(46, 46), 22)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -16, 0, 8)
	closeButton.Parent = panel

	-- Prémio final
	local finalBar = Instance.new("Frame")
	finalBar.Name = "Final"
	finalBar.Position = UDim2.fromOffset(16, 60)
	finalBar.Size = UDim2.new(1, -32, 0, 44)
	finalBar.BackgroundColor3 = Theme.Colors.Background
	finalBar.BorderSizePixel = 0
	Components.addCorner(finalBar, UDim.new(0, 12))
	local finalStroke = Components.addStroke(finalBar, Theme.Colors.Gold, 1.5)
	finalBar.Parent = panel

	local finalLabel = Components.makeLabel("Text", Theme.Fonts.Body, Theme.Colors.Text, 15)
	finalLabel.Position = UDim2.fromOffset(14, 0)
	finalLabel.Size = UDim2.new(1, -190, 1, 0)
	finalLabel.TextXAlignment = Enum.TextXAlignment.Left
	finalLabel.TextWrapped = true
	finalLabel.Parent = finalBar

	local finalButton = textButton("Claim", "RECLAMAR", Theme.Colors.Success, UDim2.fromOffset(160, 34), 16)
	finalButton.AnchorPoint = Vector2.new(1, 0.5)
	finalButton.Position = UDim2.new(1, -6, 0.5, 0)
	finalButton.Parent = finalBar

	-- Fila das raridades
	local chipRow = Instance.new("ScrollingFrame")
	chipRow.Name = "Rarities"
	chipRow.Position = UDim2.fromOffset(16, 112)
	chipRow.Size = UDim2.new(1, -32, 0, 70)
	chipRow.BackgroundTransparency = 1
	chipRow.BorderSizePixel = 0
	chipRow.ScrollBarThickness = 5
	chipRow.ScrollBarImageColor3 = Theme.Colors.Highlight
	chipRow.ScrollingDirection = Enum.ScrollingDirection.X
	chipRow.CanvasSize = UDim2.new()
	chipRow.AutomaticCanvasSize = Enum.AutomaticSize.X
	chipRow.Parent = panel
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.Padding = UDim.new(0, 6)
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Parent = chipRow

	local chips: { [string]: Chip } = {}
	for index, rarity in RaritiesConfig.List do
		local button = Components.makeButton(rarity.Id, rarity.Color)
		button.LayoutOrder = index
		button.Size = UDim2.fromOffset(104, 58)
		button.Text = ""
		Components.addCorner(button, UDim.new(0, 10))
		local stroke = Components.addStroke(button, Theme.Colors.Background, 2)
		setGradient(button, rarity)
		button.Parent = chipRow

		local name = Components.makeLabel("Name", Theme.Fonts.Display, Theme.Colors.Text, 15)
		name.Position = UDim2.fromOffset(4, 4)
		name.Size = UDim2.new(1, -8, 0, 24)
		name.Text = rarity.Name
		Components.addStroke(name, Theme.Colors.Background, 1.5)
		name.Parent = button

		local progress = Components.makeLabel("Progress", Theme.Fonts.Body, Theme.Colors.Text, 14)
		progress.Position = UDim2.fromOffset(4, 30)
		progress.Size = UDim2.new(1, -8, 0, 20)
		Components.addStroke(progress, Theme.Colors.Background, 1.5)
		progress.Parent = button

		local dot = Instance.new("Frame")
		dot.Name = "Dot"
		dot.AnchorPoint = Vector2.new(1, 0)
		dot.Position = UDim2.new(1, -4, 0, 4)
		dot.Size = UDim2.fromOffset(12, 12)
		dot.BackgroundColor3 = Theme.Colors.Danger
		dot.BorderSizePixel = 0
		dot.Visible = false
		Components.addCorner(dot, UDim.new(1, 0))
		dot.Parent = button

		chips[rarity.Id] = { Button = button, Progress = progress, Dot = dot, Stroke = stroke }
	end

	-- Chips das variantes (separador VARIANTES)
	local variantChips: { [string]: Chip } = {}
	for index, variant in VariantsConfig.List do
		local button = Components.makeButton(variant.Id, variant.Color)
		button.LayoutOrder = 100 + index
		button.Size = UDim2.fromOffset(120, 58)
		button.Text = ""
		button.Visible = false
		Components.addCorner(button, UDim.new(0, 10))
		local stroke = Components.addStroke(button, Theme.Colors.Background, 2)
		button.Parent = chipRow
		local name = Components.makeLabel("Name", Theme.Fonts.Display, Theme.Colors.Text, 15)
		name.Position = UDim2.fromOffset(4, 4)
		name.Size = UDim2.new(1, -8, 0, 24)
		name.Text = "★ " .. variant.Name
		Components.addStroke(name, Theme.Colors.Background, 1.5)
		name.Parent = button
		local progress = Components.makeLabel("Progress", Theme.Fonts.Body, Theme.Colors.Text, 14)
		progress.Position = UDim2.fromOffset(4, 30)
		progress.Size = UDim2.new(1, -8, 0, 20)
		Components.addStroke(progress, Theme.Colors.Background, 1.5)
		progress.Parent = button
		local dot = Instance.new("Frame")
		dot.Visible = false
		dot.Parent = button
		variantChips[variant.Id] = { Button = button, Progress = progress, Dot = dot, Stroke = stroke }
	end

	-- Grelha das combinações
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Position = UDim2.fromOffset(16, 192)
	grid.Size = UDim2.new(1, -300, 1, -208)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.ScrollBarImageColor3 = Theme.Colors.Highlight
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.Parent = panel
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(104, 132)
	gridLayout.CellPadding = UDim2.fromOffset(8, 8)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	local cards: { Card } = {}
	for index = 1, MAX_CARDS do
		local button = Components.makeButton("Card" .. index, Theme.Colors.Background)
		button.LayoutOrder = index
		button.Text = ""
		Components.addCorner(button, UDim.new(0, 12))
		local stroke = Components.addStroke(button, Theme.Colors.Gold, 2.5)
		button.Parent = grid

		local head = Instance.new("Frame")
		head.Name = "Head"
		head.AnchorPoint = Vector2.new(0.5, 0)
		head.Position = UDim2.new(0.5, 0, 0, 10)
		head.Size = UDim2.fromOffset(30, 30)
		head.BorderSizePixel = 0
		Components.addCorner(head, UDim.new(1, 0))
		head.Parent = button

		local body = Instance.new("Frame")
		body.Name = "Body"
		body.AnchorPoint = Vector2.new(0.5, 0)
		body.Position = UDim2.new(0.5, 0, 0, 44)
		body.Size = UDim2.fromOffset(50, 38)
		body.BorderSizePixel = 0
		Components.addCorner(body, UDim.new(0, 14))
		body.Parent = button

		local name = Components.makeLabel("Name", Theme.Fonts.Display, Theme.Colors.Text, 15)
		name.Position = UDim2.fromOffset(4, 86)
		name.Size = UDim2.new(1, -8, 0, 26)
		name.TextWrapped = true
		Components.addStroke(name, Theme.Colors.Background, 1.5)
		name.Parent = button

		local crate = Components.makeLabel("Crate", Theme.Fonts.Body, Theme.Colors.TextMuted, 12)
		crate.Position = UDim2.new(0, 4, 1, -20)
		crate.Size = UDim2.new(1, -8, 0, 16)
		crate.Parent = button

		table.insert(cards, { Button = button, Head = head, Body = body, Name = name, Crate = crate, Stroke = stroke })
	end

	-- Detalhe (direita)
	local detail = Instance.new("Frame")
	detail.Name = "Detail"
	detail.AnchorPoint = Vector2.new(1, 0)
	detail.Position = UDim2.new(1, -16, 0, 192)
	detail.Size = UDim2.new(0, 268, 1, -208)
	detail.BackgroundColor3 = Theme.Colors.Background
	detail.BorderSizePixel = 0
	Components.addCorner(detail, UDim.new(0, 14))
	local detailStroke = Components.addStroke(detail, Theme.Colors.Highlight, 1.5)
	detail.Parent = panel

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Portrait"
	viewport.AnchorPoint = Vector2.new(0.5, 0)
	viewport.Position = UDim2.new(0.5, 0, 0, 10)
	viewport.Size = UDim2.fromOffset(170, 170)
	viewport.BackgroundColor3 = Theme.Colors.Panel
	viewport.Ambient = Color3.fromRGB(200, 200, 210)
	viewport.LightColor = Color3.new(1, 1, 1)
	Components.addCorner(viewport, UDim.new(0, 12))
	viewport.Parent = detail
	local viewportCamera = Instance.new("Camera")
	viewportCamera.FieldOfView = 40
	viewportCamera.Parent = viewport
	viewport.CurrentCamera = viewportCamera

	local unknownLabel = Components.makeLabel("Unknown", Theme.Fonts.Display, Theme.Colors.Danger, 48)
	unknownLabel.Size = UDim2.fromScale(1, 1)
	unknownLabel.Text = "???"
	unknownLabel.Visible = false
	unknownLabel.ZIndex = 3
	unknownLabel.Parent = viewport

	local detailName = Components.makeLabel("Name", Theme.Fonts.Display, Theme.Colors.Text, 22)
	detailName.Position = UDim2.fromOffset(10, 186)
	detailName.Size = UDim2.new(1, -20, 0, 26)
	detailName.Parent = detail

	local detailInfo = Components.makeLabel("Info", Theme.Fonts.Body, Theme.Colors.TextMuted, 14)
	detailInfo.Position = UDim2.fromOffset(10, 214)
	detailInfo.Size = UDim2.new(1, -20, 0, 38)
	detailInfo.TextWrapped = true
	detailInfo.Parent = detail

	local rewardLabel = Components.makeLabel("Reward", Theme.Fonts.Body, Theme.Colors.Gold, 14)
	rewardLabel.AnchorPoint = Vector2.new(0, 1)
	rewardLabel.Position = UDim2.new(0, 10, 1, -58)
	rewardLabel.Size = UDim2.new(1, -20, 0, 44)
	rewardLabel.TextWrapped = true
	rewardLabel.Parent = detail

	local claimButton = textButton("Claim", "RECLAMAR", Theme.Colors.Success, UDim2.new(1, -20, 0, 40), 18)
	claimButton.AnchorPoint = Vector2.new(0.5, 1)
	claimButton.Position = UDim2.new(0.5, 0, 1, -10)
	claimButton.Parent = detail

	-- Estado ---------------------------------------------------------------------------
	-- Dois modos: "Rarity" (artista × raridade, com prémios) e "Variant" (artista × variante)
	type Entry = {
		ArtistId: string,
		CrateId: string,
		Rarity: string?, -- modo raridade
		Variant: string?, -- modo variante
		Known: boolean,
	}

	local isOpen = false
	local mode: "Rarity" | "Variant" = "Rarity"
	local selectedRarity = RaritiesConfig.List[1].Id
	local selectedVariant = VariantsConfig.List[1].Id
	local selectedIndex = 1
	local portraitRig: Model? = nil
	local portraitAngle = 0
	local renderConnection: RBXScriptConnection? = nil

	local function getSync(): IndexSync
		return IndexController.Get()
			or { Discovered = {}, Claimed = {}, Variants = {}, Showcase = { Mode = "Auto", Uid = "" }, ShowcaseUid = "" }
	end

	-- Entradas da grelha conforme o modo
	local function getEntries(sync: IndexSync): { Entry }
		local entries: { Entry } = {}
		if mode == "Rarity" then
			for _, combo in IndexCalc.GetCombos(selectedRarity) do
				table.insert(entries, {
					ArtistId = combo.ArtistId,
					CrateId = combo.CrateId,
					Rarity = combo.Rarity,
					Variant = nil,
					Known = sync.Discovered[combo.Key] == true,
				})
			end
		else
			for _, artist in IndexCalc.GetVariantArtists() do
				table.insert(entries, {
					ArtistId = artist.Id,
					CrateId = artist.Crate,
					Rarity = nil,
					Variant = selectedVariant,
					Known = (sync.Variants or {})[IndexCalc.VariantKey(artist.Id, selectedVariant)] == true,
				})
			end
		end
		return entries
	end

	local function clearPortrait()
		local rig = portraitRig
		if rig then
			rig:Destroy()
			portraitRig = nil
		end
	end

	local function showPortrait(entry: Entry?)
		clearPortrait()
		unknownLabel.Visible = false
		if not entry then
			return
		end
		local rarity = if entry.Rarity then ArtistCalc.GetRarity(entry.Rarity) else nil
		local rig = CinematicAssets.GetArtistRig(entry.ArtistId, if rarity then rarity.Color else Color3.fromRGB(200, 200, 210))
		if not entry.Known then
			-- Silhueta: tudo preto
			for _, descendant in rig:GetDescendants() do
				if descendant:IsA("BasePart") and descendant ~= rig.PrimaryPart then
					descendant.Color = BLACK
					descendant.Material = Enum.Material.SmoothPlastic
				elseif descendant:IsA("Decal") then
					descendant.Transparency = 1
				end
			end
			unknownLabel.Visible = true
		elseif entry.Variant then
			VariantVisuals.Apply(rig, entry.Variant)
		end
		rig:PivotTo(CFrame.new())
		local boxCFrame, size = rig:GetBoundingBox()
		local center = boxCFrame.Position
		local distance = math.max(size.Y, size.X) * 1.9 + 2
		viewportCamera.CFrame = CFrame.lookAt(center + Vector3.new(0, size.Y * 0.1, distance), center)
		rig.Parent = viewport
		portraitRig = rig
		portraitAngle = 0
	end

	local function refreshDetail()
		local sync = getSync()
		local entry = getEntries(sync)[selectedIndex]
		if mode == "Variant" then
			local variant = VariantCalc.Get(selectedVariant) or VariantsConfig.List[1]
			detailStroke.Color = variant.Color
			if entry then
				local def = ArtistCalc.GetArtist(entry.ArtistId)
				local crate = ArtistCalc.GetCrate(entry.CrateId)
				detailName.Text = if entry.Known and def then def.Name else "???"
				detailInfo.Text = string.format(
					"★ %s (+%d%%) · %s\n%s",
					variant.Name,
					math.floor(variant.Bonus * 100 + 0.5),
					if crate then crate.Name else entry.CrateId,
					if entry.Known then "Descoberto" else string.format("Por descobrir (1 em %d aberturas)", variant.Chance)
				)
			end
			local have, total = IndexCalc.GetVariantProgress(sync.Variants or {}, selectedVariant)
			rewardLabel.Text = string.format("Variante %s: %d/%d artistas descobertos.", variant.Name, have, total)
			claimButton.Visible = false
			return
		end

		claimButton.Visible = true
		local rarity = ArtistCalc.GetRarity(selectedRarity) or RaritiesConfig.List[1]
		detailStroke.Color = rarity.Color
		if entry then
			local def = ArtistCalc.GetArtist(entry.ArtistId)
			local crate = ArtistCalc.GetCrate(entry.CrateId)
			detailName.Text = if entry.Known and def then def.Name else "???"
			detailInfo.Text = string.format(
				"%s · %s\n%s",
				rarity.Name,
				if crate then crate.Name else entry.CrateId,
				if entry.Known then "Descoberto" else "Por descobrir"
			)
		else
			detailName.Text = rarity.Name
			detailInfo.Text = "Escolhe um artista da grelha."
		end
		local have, total = IndexCalc.GetProgress(sync.Discovered, selectedRarity)
		local claimed = sync.Claimed[selectedRarity] == true
		rewardLabel.Text = string.format("Prémio %s (%d/%d):\n%s", rarity.Name, have, total, rewardText(selectedRarity))
		local canClaim = IndexCalc.CanClaim(sync.Discovered, sync.Claimed, selectedRarity)
		claimButton.Text = if claimed then "✓ RECLAMADO" elseif canClaim then "RECLAMAR" else string.format("FALTAM %d", total - have)
		claimButton.BackgroundColor3 = if canClaim then Theme.Colors.Success else Theme.Colors.Disabled
		claimButton.AutoButtonColor = canClaim
	end

	local function refreshGrid()
		local sync = getSync()
		local entries = getEntries(sync)
		local color = if mode == "Variant"
			then (VariantCalc.Get(selectedVariant) or VariantsConfig.List[1]).Color
			else (ArtistCalc.GetRarity(selectedRarity) or RaritiesConfig.List[1]).Color
		for index, card in cards do
			local entry = entries[index]
			card.Button.Visible = entry ~= nil
			if entry then
				local def = ArtistCalc.GetArtist(entry.ArtistId)
				local crate = ArtistCalc.GetCrate(entry.CrateId)
				local fill = if entry.Known then color else BLACK
				card.Head.BackgroundColor3 = fill
				card.Body.BackgroundColor3 = fill
				card.Stroke.Color = if entry.Known then color else Theme.Colors.Disabled
				card.Name.Text = if entry.Known and def then def.Name else "???"
				card.Name.TextColor3 = if entry.Known then Theme.Colors.Text else Theme.Colors.Danger
				card.Crate.Text = if crate then crate.Name else entry.CrateId
				card.Stroke.Thickness = if index == selectedIndex then 4 else 2.5
			end
		end
	end

	local function refreshAll()
		local sync = getSync()
		local have, total = IndexCalc.GetTotalProgress(sync.Discovered)
		local variants = sync.Variants or {}
		if mode == "Variant" then
			local vHave, vTotal = IndexCalc.GetVariantTotalProgress(variants)
			totalLabel.Text = string.format("★ %d/%d", vHave, vTotal)
		else
			totalLabel.Text = string.format("%d/%d", have, total)
		end
		modeButton.Text = if mode == "Variant" then "RARIDADES" else "★ VARIANTES"
		modeButton.BackgroundColor3 = if mode == "Variant" then Theme.Colors.Accent else Theme.Colors.Background
		for _, rarity in RaritiesConfig.List do
			local chip = chips[rarity.Id]
			chip.Button.Visible = mode == "Rarity"
			local rHave, rTotal = IndexCalc.GetProgress(sync.Discovered, rarity.Id)
			local claimed = sync.Claimed[rarity.Id] == true
			chip.Progress.Text = if claimed then string.format("✓ %d/%d", rHave, rTotal) else string.format("%d/%d", rHave, rTotal)
			chip.Dot.Visible = IndexCalc.CanClaim(sync.Discovered, sync.Claimed, rarity.Id)
			chip.Stroke.Color = if rarity.Id == selectedRarity then Theme.Colors.Text else Theme.Colors.Background
			chip.Stroke.Thickness = if rarity.Id == selectedRarity then 3 else 2
		end
		for _, variant in VariantsConfig.List do
			local chip = variantChips[variant.Id]
			chip.Button.Visible = mode == "Variant"
			local vHave, vTotal = IndexCalc.GetVariantProgress(variants, variant.Id)
			chip.Progress.Text = string.format("%d/%d", vHave, vTotal)
			chip.Stroke.Color = if variant.Id == selectedVariant then Theme.Colors.Text else Theme.Colors.Background
			chip.Stroke.Thickness = if variant.Id == selectedVariant then 3 else 2
		end
		local finalKey = ArtistIndexConfig.FinalKey
		local finalClaimed = sync.Claimed[finalKey] == true
		local canFinal = IndexCalc.CanClaim(sync.Discovered, sync.Claimed, finalKey)
		finalLabel.Text = string.format("Índice completo (%d/%d): %s", have, total, rewardText(finalKey))
		finalButton.Text = if finalClaimed then "✓ RECLAMADO" elseif canFinal then "RECLAMAR" else "BLOQUEADO"
		finalButton.BackgroundColor3 = if canFinal then Theme.Colors.Success else Theme.Colors.Disabled
		finalButton.AutoButtonColor = canFinal
		finalStroke.Color = if canFinal then Theme.Colors.Success else Theme.Colors.Gold
		local manual = sync.Showcase.Mode == "Manual"
		showcaseButton.Text = if manual then "VITRINE: MANUAL" else "VITRINE: AUTO"
		showcaseButton.BackgroundColor3 = if manual then Theme.Colors.Accent else Theme.Colors.Background
		refreshGrid()
		refreshDetail()
	end

	local function refreshBadge()
		local sync = getSync()
		local count = IndexCalc.GetClaimableCount(sync.Discovered, sync.Claimed)
		badge.Visible = count > 0
		badge.Text = tostring(count)
	end

	local function selectEntry(index: number)
		selectedIndex = index
		showPortrait(getEntries(getSync())[index])
	end

	local function selectRarity(rarityId: string)
		selectedRarity = rarityId
		selectEntry(1)
		refreshAll()
	end

	local function selectVariant(variantId: string)
		selectedVariant = variantId
		selectEntry(1)
		refreshAll()
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
			selectEntry(selectedIndex)
			refreshAll()
			renderConnection = RunService.RenderStepped:Connect(function(dt: number)
				local rig = portraitRig
				if rig then
					portraitAngle += dt * 0.8
					rig:PivotTo(CFrame.Angles(0, portraitAngle, 0))
				end
			end)
		else
			ModalManager.NotifyClosed(MODAL_NAME)
			local connection = renderConnection
			if connection then
				connection:Disconnect()
				renderConnection = nil
			end
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
	for rarityId, chip in chips do
		trove:Connect(chip.Button.Activated, function()
			selectRarity(rarityId)
		end)
	end
	for variantId, chip in variantChips do
		trove:Connect(chip.Button.Activated, function()
			selectVariant(variantId)
		end)
	end
	trove:Connect(modeButton.Activated, function()
		mode = if mode == "Rarity" then "Variant" else "Rarity"
		selectEntry(1)
		refreshAll()
	end)
	for index, card in cards do
		trove:Connect(card.Button.Activated, function()
			if not getEntries(getSync())[index] then
				return
			end
			selectEntry(index)
			refreshGrid()
			refreshDetail()
		end)
	end
	trove:Connect(claimButton.Activated, function()
		local sync = getSync()
		if IndexCalc.CanClaim(sync.Discovered, sync.Claimed, selectedRarity) then
			IndexController.Claim(selectedRarity)
		end
	end)
	trove:Connect(finalButton.Activated, function()
		local sync = getSync()
		if IndexCalc.CanClaim(sync.Discovered, sync.Claimed, ArtistIndexConfig.FinalKey) then
			IndexController.Claim(ArtistIndexConfig.FinalKey)
		end
	end)
	trove:Connect(showcaseButton.Activated, function()
		local sync = getSync()
		if sync.Showcase.Mode == "Manual" then
			IndexController.SetShowcase("Auto")
		else
			showcaseButton.Text = "ESCOLHE NA COLEÇÃO"
		end
	end)
	trove:Connect(toggleButton.Activated, function()
		setOpen(not isOpen)
	end)
	trove:Connect(closeButton.Activated, function()
		setOpen(false)
	end)
	trove:Connect(overlay.Activated, function()
		setOpen(false)
	end)
	trove:Connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if not gameProcessed and input.KeyCode == TOGGLE_KEY then
			setOpen(not isOpen)
		end
	end)
	trove:Add(IndexController.Changed:Connect(function(_sync: IndexSync)
		refreshBadge()
		if isOpen then
			selectEntry(selectedIndex)
			refreshAll()
		end
	end))

	local function updateScales()
		fitScale.Scale = Components.fitScale(panelGui.AbsoluteSize, PANEL_SIZE, Theme.Shop.ScreenFill)
		toggleScale.Scale = Components.computeScale(toggleGui.AbsoluteSize)
	end
	trove:Connect(panelGui:GetPropertyChangedSignal("AbsoluteSize"), updateScales)
	trove:Connect(toggleGui:GetPropertyChangedSignal("AbsoluteSize"), updateScales)

	toggleGui.Parent = playerGui
	panelGui.Parent = playerGui
	updateScales()
	refreshBadge()
end

return IndexView
