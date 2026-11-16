--!strict
--[[
	StagesView
	Painel central com os 12 palcos:
	  - pré-visualização: silhueta à escala real do envelope do tier (mesma escala para todos)
	    com as cores da era
	  - nome, era, multiplicador de Hype e o que desbloqueia
	  - estado: PALCO ATUAL · CONSTRUÍDO · COMPRAR (verde/cinzento conforme o Hype) ·
	    cadeado com o motivo (tier anterior ou World Tours)
	Abre com o botão "PALCOS" à esquerda, tecla P ou botão X do comando.
	A compra é só um pedido: o servidor valida tudo e responde com um aviso.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local StagesConfig = require(ReplicatedStorage.Shared.Config.Stages)
local BigNum = require(ReplicatedStorage.Shared.Util.BigNum)
local NumberFormatter = require(ReplicatedStorage.Shared.Util.NumberFormatter)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local StageCalc = require(ReplicatedStorage.Shared.Calc.StageCalc)
local PrestigeCalc = require(ReplicatedStorage.Shared.Calc.PrestigeCalc)

local Client = script.Parent.Parent.Parent
local StateController = require(Client.Controllers.StateController)
local StageController = require(Client.Controllers.StageController)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local ModalManager = require(script.Parent.Parent.ModalManager)
local SideMenu = require(script.Parent.Parent.SideMenu)

type StageDef = Types.StageDef
type Snapshot = Types.PlayerStateSnapshot

type Card = {
	Def: StageDef,
	Frame: Frame,
	Stroke: UIStroke,
	InfoLabel: TextLabel,
	BuyButton: TextButton,
	AmountLabel: TextLabel,
	CostLabel: TextLabel,
}

local ERA_COLORS: { [string]: Color3 } = {
	Underground = Color3.fromRGB(196, 140, 84),
	["Ascensão"] = Color3.fromRGB(150, 110, 255),
	Estrelato = Color3.fromRGB(255, 190, 80),
	Lenda = Color3.fromRGB(43, 210, 255),
}

local StagesView = {}

local activeTrove: Trove.Trove? = nil
local setOpenImpl: ((boolean) -> ())? = nil
local isOpen = false

local function eraColor(def: StageDef): Color3
	return ERA_COLORS[def.Era] or Theme.Colors.Text
end

-- Silhueta do palco à escala (estrado + estrutura), assente no "chão" da pré-visualização
local function buildPreview(def: StageDef, parent: Instance)
	local size = Theme.Stages.PreviewSize
	local scale = Theme.Stages.PreviewStudScale

	local preview = Instance.new("Frame")
	preview.Name = "Preview"
	preview.Position = UDim2.fromOffset(10, 10)
	preview.Size = UDim2.fromOffset(size.X, size.Y)
	preview.BackgroundColor3 = Color3.fromRGB(12, 7, 30)
	preview.BorderSizePixel = 0
	preview.ClipsDescendants = true
	Components.addCorner(preview, UDim.new(0, 10))
	preview.Parent = parent

	local groundY = size.Y - 8
	local ground = Instance.new("Frame")
	ground.Name = "Ground"
	ground.Position = UDim2.fromOffset(0, groundY)
	ground.Size = UDim2.new(1, 0, 0, 8)
	ground.BackgroundColor3 = Color3.fromRGB(40, 30, 70)
	ground.BorderSizePixel = 0
	ground.Parent = preview

	local width = def.Width * scale
	local height = def.Height * scale
	local deckHeight = math.clamp(def.Height * 0.15, 2, 8) * scale

	local structure = Instance.new("Frame")
	structure.Name = "Structure"
	structure.AnchorPoint = Vector2.new(0.5, 1)
	structure.Position = UDim2.fromOffset(size.X / 2, groundY)
	structure.Size = UDim2.fromOffset(width, height)
	structure.BackgroundColor3 = eraColor(def)
	structure.BackgroundTransparency = 0.35
	structure.BorderSizePixel = 0
	structure.Parent = preview

	local deck = Instance.new("Frame")
	deck.Name = "Deck"
	deck.AnchorPoint = Vector2.new(0.5, 1)
	deck.Position = UDim2.fromOffset(size.X / 2, groundY)
	deck.Size = UDim2.fromOffset(width, math.max(deckHeight, 2))
	deck.BackgroundColor3 = eraColor(def)
	deck.BorderSizePixel = 0
	deck.Parent = preview

	local label = Components.makeLabel("Size", Theme.Fonts.Body, Theme.Colors.TextMuted, 12)
	label.Position = UDim2.fromOffset(4, 2)
	label.Size = UDim2.new(1, -8, 0, 14)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = string.format("%d×%d×%d", def.Width, def.Depth, def.Height)
	label.Parent = preview
end

local function buildCard(def: StageDef, parent: Instance): Card
	local frame = Instance.new("Frame")
	frame.Name = "Tier_" .. def.Tier
	frame.LayoutOrder = def.Tier
	frame.Size = UDim2.new(1, 0, 0, Theme.Stages.CardHeight)
	frame.BackgroundColor3 = Theme.Colors.Background
	frame.BorderSizePixel = 0
	Components.addCorner(frame, UDim.new(0, 14))
	local stroke = Components.addStroke(frame, eraColor(def), 1.5)
	stroke.Transparency = 0.4

	buildPreview(def, frame)

	local textX = Theme.Stages.PreviewSize.X + 22
	local nameLabel = Components.makeLabel("Name", Theme.Fonts.Display, Theme.Colors.Text, 22)
	nameLabel.Position = UDim2.fromOffset(textX, 10)
	nameLabel.Size = UDim2.new(1, -(textX + 180), 0, 24)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = string.format("TIER %d · %s", def.Tier, def.Name)
	nameLabel.Parent = frame

	local infoLabel = Components.makeLabel("Info", Theme.Fonts.Body, eraColor(def), 16)
	infoLabel.Position = UDim2.fromOffset(textX, 38)
	infoLabel.Size = UDim2.new(1, -(textX + 180), 0, 18)
	infoLabel.TextXAlignment = Enum.TextXAlignment.Left
	infoLabel.Parent = frame

	local unlocks = StageCalc.GetUnlocks(def.Tier)
	local unlocksLabel = Instance.new("TextLabel")
	unlocksLabel.Name = "Unlocks"
	unlocksLabel.BackgroundTransparency = 1
	unlocksLabel.Position = UDim2.fromOffset(textX, 60)
	unlocksLabel.Size = UDim2.new(1, -(textX + 180), 0, 46)
	unlocksLabel.Font = Theme.Fonts.Body
	unlocksLabel.TextSize = 14
	unlocksLabel.TextWrapped = true
	unlocksLabel.TextXAlignment = Enum.TextXAlignment.Left
	unlocksLabel.TextYAlignment = Enum.TextYAlignment.Top
	unlocksLabel.TextColor3 = Theme.Colors.TextMuted
	unlocksLabel.Text = if #unlocks > 0 then "Desbloqueia: " .. table.concat(unlocks, ", ") else "Mais palco, mais Hype."
	unlocksLabel.Parent = frame

	local buyButton = Components.makeButton("Buy", Theme.Colors.Disabled)
	buyButton.AnchorPoint = Vector2.new(1, 0.5)
	buyButton.Position = UDim2.new(1, -12, 0.5, 0)
	buyButton.Size = UDim2.fromOffset(160, 72)
	Components.addCorner(buyButton, UDim.new(0, 12))
	Components.addStroke(buyButton, Theme.Colors.Text, 2).Transparency = 0.6
	buyButton.Parent = frame

	local amountLabel = Components.makeLabel("Amount", Theme.Fonts.Body, Theme.Colors.Text, 16)
	amountLabel.AnchorPoint = Vector2.new(0.5, 0)
	amountLabel.Position = UDim2.new(0.5, 0, 0, 8)
	amountLabel.Size = UDim2.new(1, -14, 0, 20)
	amountLabel.Parent = buyButton

	local costLabel = Components.makeLabel("Cost", Theme.Fonts.Display, Theme.Colors.Text, 24)
	costLabel.AnchorPoint = Vector2.new(0.5, 1)
	costLabel.Position = UDim2.new(0.5, 0, 1, -8)
	costLabel.Size = UDim2.new(1, -14, 0, 28)
	Components.addStroke(costLabel, Theme.Colors.Background, 1.5)
	costLabel.Parent = buyButton

	frame.Parent = parent

	return {
		Def = def,
		Frame = frame,
		Stroke = stroke,
		InfoLabel = infoLabel,
		BuyButton = buyButton,
		AmountLabel = amountLabel,
		CostLabel = costLabel,
	}
end

-- Custo com o desconto da "Negociação" (igual ao do servidor)
local function stageCost(def: StageDef, snapshot: Snapshot): number
	local cut = PrestigeCalc.GetSkillEffects(snapshot.SkillTree).StageCostCut
	return def.Cost * (1 - math.clamp(cut, 0, 0.9))
end

local function refreshCard(card: Card, snapshot: Snapshot, budget: BigNum.BigNum, busy: boolean)
	local def = card.Def
	local status = StageCalc.GetStatus(def.Tier, snapshot.StageTier, snapshot.WorldTours)
	card.InfoLabel.Text = string.format(
		"Era %s · Hype ×%s%s",
		def.Era,
		NumberFormatter.format(StageCalc.GetMultiplier(def.Tier)),
		if def.RequiredWorldTours > 0 then string.format(" · %d World Tour(s)", def.RequiredWorldTours) else ""
	)

	card.Stroke.Color = if status == "Current" then Theme.Colors.Gold else eraColor(def)
	card.Stroke.Thickness = if status == "Current" then 3 else 1.5
	card.Stroke.Transparency = if status == "Current" then 0 else 0.4
	card.CostLabel.TextColor3 = Theme.Colors.Text

	if status == "Current" then
		card.BuyButton.BackgroundColor3 = Theme.Colors.AccentDark
		card.AmountLabel.Text = "PALCO ATUAL"
		card.CostLabel.Text = "★"
	elseif status == "Owned" then
		card.BuyButton.BackgroundColor3 = Theme.Colors.Disabled
		card.AmountLabel.Text = "CONSTRUÍDO"
		card.CostLabel.Text = "✓"
		card.CostLabel.TextColor3 = Theme.Colors.Success
	elseif status == "NeedPrevious" then
		card.BuyButton.BackgroundColor3 = Theme.Colors.Disabled
		card.AmountLabel.Text = "🔒 BLOQUEADO"
		card.CostLabel.Text = "Tier " .. (def.Tier - 1) .. " antes"
		card.CostLabel.TextColor3 = Theme.Colors.TextMuted
	elseif status == "NeedWorldTours" then
		card.BuyButton.BackgroundColor3 = Theme.Colors.Disabled
		card.AmountLabel.Text = "🔒 REQUER"
		card.CostLabel.Text = string.format("%d World Tour%s", def.RequiredWorldTours, if def.RequiredWorldTours > 1 then "s" else "")
		card.CostLabel.TextColor3 = Theme.Colors.TextMuted
	else
		local cost = stageCost(def, snapshot)
		local affordable = BigNum.gte(budget, BigNum.fromNumber(cost))
		card.BuyButton.BackgroundColor3 = if affordable and not busy then Theme.Colors.Success else Theme.Colors.Disabled
		card.AmountLabel.Text = if busy then "A MONTAR…" else "CONSTRUIR"
		card.CostLabel.Text = NumberFormatter.format(cost)
		card.CostLabel.TextColor3 = if affordable then Theme.Colors.Text else Theme.Colors.TextMuted
	end
end

-- Montagem -------------------------------------------------------------------

function StagesView.Mount()
	if activeTrove then
		return
	end
	local trove = Trove.new()
	activeTrove = trove

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Botão PALCOS (por baixo da LOJA) -------------------------------------
	local toggleGui = trove:Add(Instance.new("ScreenGui"))
	toggleGui.Name = "StagesToggleGui"
	toggleGui.ResetOnSpawn = false
	toggleGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	toggleGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	toggleGui.DisplayOrder = 1

	local toggleHolder = Components.makeFrame("StagesToggle")
	toggleHolder.AnchorPoint = Vector2.new(0, 0.5)
	toggleHolder.Position = UDim2.new(0, 16, 0.5, 128)
	toggleHolder.Size = UDim2.fromOffset(112, 100)
	SideMenu.Attach(toggleHolder, 3)

	local toggleScale = Instance.new("UIScale")
	toggleScale.Parent = toggleHolder

	local toggleButton = Components.makeButton("Button", Theme.Colors.Panel)
	toggleButton.Size = UDim2.fromScale(1, 1)
	Components.addCorner(toggleButton, UDim.new(0, 22))
	Components.addStroke(toggleButton, Theme.Colors.Accent, 3)
	toggleButton.Parent = toggleHolder

	local toggleLabel = Components.makeLabel("Label", Theme.Fonts.Display, Theme.Colors.Text, 26)
	toggleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	toggleLabel.Position = UDim2.fromScale(0.5, 0.42)
	toggleLabel.Size = UDim2.new(0.88, 0, 0, 30)
	toggleLabel.Text = "PALCOS"
	Components.addStroke(toggleLabel, Theme.Colors.Background, 2)
	toggleLabel.Parent = toggleButton

	local toggleHint = Components.makeLabel("Hint", Theme.Fonts.Body, Theme.Colors.TextMuted, 16)
	toggleHint.AnchorPoint = Vector2.new(0.5, 0.5)
	toggleHint.Position = UDim2.fromScale(0.5, 0.74)
	toggleHint.Size = UDim2.new(0.8, 0, 0, 18)
	toggleHint.Text = "[P]"
	toggleHint.Visible = UserInputService.KeyboardEnabled
	toggleHint.Parent = toggleButton

	-- Painel ---------------------------------------------------------------
	local panelGui = trove:Add(Instance.new("ScreenGui"))
	panelGui.Name = "StagesPanelGui"
	panelGui.ResetOnSpawn = false
	panelGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	panelGui.ScreenInsets = Enum.ScreenInsets.None
	panelGui.DisplayOrder = 10

	local overlay = Components.makeButton("Overlay", Theme.Colors.Overlay)
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundTransparency = 1
	overlay.Visible = false
	overlay.Parent = panelGui

	local panelSize = Theme.Stages.PanelSize
	local panelHolder = Components.makeFrame("PanelHolder")
	panelHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	panelHolder.Position = UDim2.fromScale(0.5, 0.5)
	panelHolder.Size = UDim2.fromOffset(panelSize.X, panelSize.Y)
	panelHolder.Visible = false
	panelHolder.Parent = panelGui

	local fitScale = Instance.new("UIScale")
	fitScale.Parent = panelHolder

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.BorderSizePixel = 0
	panel.Active = true
	Components.addCorner(panel, UDim.new(0, 20))
	Components.addStroke(panel, Theme.Colors.Gold, 3)
	panel.Parent = panelHolder

	local popScale = Instance.new("UIScale")
	popScale.Parent = panel

	local title = Components.makeLabel("Title", Theme.Fonts.Display, Theme.Colors.Gold, 34)
	title.Position = UDim2.fromOffset(24, 14)
	title.Size = UDim2.new(1, -100, 0, 38)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "PALCOS"
	Components.addStroke(title, Theme.Colors.Background, 2)
	title.Parent = panel

	local subtitle = Components.makeLabel("Subtitle", Theme.Fonts.Body, Theme.Colors.TextMuted, 16)
	subtitle.Position = UDim2.fromOffset(24, 54)
	subtitle.Size = UDim2.new(1, -100, 0, 20)
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Parent = panel

	local closeButton = Components.makeButton("Close", Theme.Colors.Danger)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -16, 0, 14)
	closeButton.Size = UDim2.fromOffset(46, 46)
	closeButton.Font = Theme.Fonts.Display
	closeButton.TextColor3 = Theme.Colors.Text
	closeButton.TextSize = 26
	closeButton.Text = "X"
	Components.addCorner(closeButton, UDim.new(0, 12))
	closeButton.Parent = panel

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Position = UDim2.fromOffset(16, 86)
	list.Size = UDim2.new(1, -32, 1, -102)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Theme.Colors.Gold
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel

	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingRight = UDim.new(0, 12)
	listPadding.PaddingBottom = UDim.new(0, 8)
	listPadding.Parent = list

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = list

	local cards: { Card } = {}
	for _, def in StagesConfig.List do
		table.insert(cards, buildCard(def, list))
	end

	-- Atualização --------------------------------------------------------------
	local lastTier = 0

	local function refresh()
		local snapshot = StateController.Get()
		if not isOpen or not snapshot then
			return
		end
		local budget = BigNum.deserialize(snapshot.Hype)
		local busy = StageController.IsMyStageTransitioning()
		subtitle.Text = string.format(
			"Tier atual %d · Hype ×%s · World Tours %d",
			snapshot.StageTier,
			NumberFormatter.format(StageCalc.GetMultiplier(snapshot.StageTier)),
			snapshot.WorldTours
		)
		for _, card in cards do
			refreshCard(card, snapshot, budget, busy)
		end
		if snapshot.StageTier ~= lastTier and lastTier ~= 0 then
			local card = cards[snapshot.StageTier]
			if card then
				card.Frame.BackgroundColor3 = Theme.Colors.Success
				TweenService:Create(card.Frame, Theme.Tween.Ring, { BackgroundColor3 = Theme.Colors.Background }):Play()
			end
		end
		lastTier = snapshot.StageTier
	end

	local function shake(button: GuiObject)
		button.Rotation = 6
		TweenService:Create(button, TweenInfo.new(0.35, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
	end

	for _, card in cards do
		trove:Connect(card.BuyButton.Activated, function()
			local snapshot = StateController.Get()
			if not snapshot then
				return
			end
			local def = card.Def
			local status = StageCalc.GetStatus(def.Tier, snapshot.StageTier, snapshot.WorldTours)
			if status ~= "Available" then
				if status ~= "Current" and status ~= "Owned" then
					shake(card.BuyButton)
				end
				return
			end
			if
				BigNum.lt(BigNum.deserialize(snapshot.Hype), BigNum.fromNumber(stageCost(def, snapshot)))
				or not StageController.RequestPurchase(def.Tier)
			then
				shake(card.BuyButton)
			end
		end)
	end

	-- Abrir / fechar -----------------------------------------------------------
	local refreshThread: thread? = nil

	local function setOpen(open: boolean)
		if isOpen == open then
			return
		end
		isOpen = open
		if open then
			ModalManager.NotifyOpened("Stages")
			overlay.Visible = true
			panelHolder.Visible = true
			popScale.Scale = 0.85
			TweenService:Create(popScale, Theme.Tween.Toast, { Scale = 1 }):Play()
			TweenService:Create(overlay, Theme.Tween.Fast, { BackgroundTransparency = Theme.Shop.OverlayTransparency }):Play()
			refresh()
			local snapshot = StateController.Get()
			if snapshot then
				list.CanvasPosition = Vector2.new(0, math.max(0, snapshot.StageTier - 2) * (Theme.Stages.CardHeight + 8))
			end
			-- Atualização periódica enquanto aberto (montagem em curso, Hype a subir)
			refreshThread = task.spawn(function()
				while isOpen do
					task.wait(Theme.Stages.RefreshInterval)
					refresh()
				end
			end)
		else
			local thread = refreshThread
			refreshThread = nil
			if thread and coroutine.status(thread) == "suspended" then
				task.cancel(thread)
			end
			local closing = TweenService:Create(popScale, Theme.Tween.FadeOut, { Scale = 0.85 })
			TweenService:Create(overlay, Theme.Tween.FadeOut, { BackgroundTransparency = 1 }):Play()
			closing.Completed:Once(function()
				if not isOpen then
					overlay.Visible = false
					panelHolder.Visible = false
				end
			end)
			closing:Play()
		end
	end
	setOpenImpl = setOpen
	ModalManager.Register("Stages", function()
		setOpen(false)
	end)
	trove:Add(function()
		ModalManager.Unregister("Stages")
		local thread = refreshThread
		if thread and coroutine.status(thread) == "suspended" then
			task.cancel(thread)
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
		if gameProcessed then
			return
		end
		if input.KeyCode == Theme.Stages.ToggleKey or input.KeyCode == Theme.Stages.ToggleGamepadButton then
			setOpen(not isOpen)
		end
	end)
	trove:Add(StateController.Changed:Connect(function(_snapshot: Snapshot)
		refresh()
	end))

	-- Escalas ------------------------------------------------------------------
	local function updateScales()
		fitScale.Scale = Components.fitScale(panelGui.AbsoluteSize, panelSize, Theme.Shop.ScreenFill)
		toggleScale.Scale = Components.computeScale(toggleGui.AbsoluteSize)
	end
	trove:Connect(panelGui:GetPropertyChangedSignal("AbsoluteSize"), updateScales)
	trove:Connect(toggleGui:GetPropertyChangedSignal("AbsoluteSize"), updateScales)

	toggleGui.Parent = playerGui
	panelGui.Parent = playerGui
	updateScales()
end

function StagesView.Open()
	local setOpen = setOpenImpl
	if setOpen then
		setOpen(true)
	end
end

function StagesView.Close()
	local setOpen = setOpenImpl
	if setOpen then
		setOpen(false)
	end
end

function StagesView.Unmount()
	local trove = activeTrove
	if trove then
		activeTrove = nil
		setOpenImpl = nil
		isOpen = false
		trove:Destroy()
	end
end

return StagesView
