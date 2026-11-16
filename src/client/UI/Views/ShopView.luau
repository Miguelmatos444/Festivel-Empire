--!strict
--[[
	ShopView
	Loja num painel central (modal) com fundo escurecido e dois separadores:
	  - EQUIPAMENTO: seletor x1 / x10 / x100 / MAX e cartões de equipamento
	  - PIROTECNIA: desbloqueio das máquinas e lista de sinergias
	Abre com o botão "MELHORIAS" à esquerda, tecla B ou botão Y do comando.
	Os preços usam EquipmentCalc (iguais aos do servidor) e só são
	recalculados com o painel aberto.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local BigNum = require(ReplicatedStorage.Shared.Util.BigNum)
local NumberFormatter = require(ReplicatedStorage.Shared.Util.NumberFormatter)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.Economy)
local EquipmentConfig = require(ReplicatedStorage.Shared.Config.Equipment)
local PyroConfig = require(ReplicatedStorage.Shared.Config.Pyro)
local EquipmentCalc = require(ReplicatedStorage.Shared.Calc.EquipmentCalc)

local Client = script.Parent.Parent.Parent
local StateController = require(Client.Controllers.StateController)
local EquipmentController = require(Client.Controllers.EquipmentController)
local BassDropController = require(Client.Controllers.BassDropController)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local ModalManager = require(script.Parent.Parent.ModalManager)
local SideMenu = require(script.Parent.Parent.SideMenu)
local VipPage = require(script.Parent.VipPage)

type BigNum = BigNum.BigNum
type BuyMode = Types.BuyMode
type EquipmentDef = Types.EquipmentDef
type EquipmentCategory = Types.EquipmentCategory
type PyroDef = Types.PyroDef
type PurchaseResult = Types.PurchaseResult
type Snapshot = Types.PlayerStateSnapshot
type DropState = Types.DropState

export type Tab = "Equipment" | "Pyro" | "Vip"

type Card = {
	Id: string,
	Frame: Frame,
	NameLabel: TextLabel,
	InfoLabel: TextLabel,
	DetailLabel: TextLabel,
	BuyButton: TextButton,
	AmountLabel: TextLabel,
	CostLabel: TextLabel,
}

local MODES: { BuyMode } = { "x1", "x10", "x100", "Max" }
local TAB_HEADER_HEIGHT = 64

local ShopView = {}

local activeTrove: Trove.Trove? = nil
local setOpenImpl: ((boolean) -> ())? = nil
local setTabImpl: ((Tab) -> ())? = nil
local isOpen = false

local function categoryColor(category: EquipmentCategory): Color3
	local colors = Theme.CategoryColors
	if category == "Colunas" then
		return colors.Colunas
	elseif category == "Mesas" then
		return colors.Mesas
	elseif category == "DJs" then
		return colors.DJs
	end
	return colors.Palco
end

local function modeLabel(mode: BuyMode): string
	return if mode == "Max" then "MAX" else mode
end

-- Construção de um cartão ----------------------------------------------------

local function buildCard(id: string, order: number, parent: Instance, accent: Color3): Card
	local frame = Instance.new("Frame")
	frame.Name = id
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, Theme.Shop.CardHeight)
	frame.BackgroundColor3 = Theme.Colors.Background
	frame.BorderSizePixel = 0
	Components.addCorner(frame, UDim.new(0, 14))
	Components.addStroke(frame, accent, 1.5).Transparency = 0.4

	local stripe = Instance.new("Frame")
	stripe.Name = "Stripe"
	stripe.Position = UDim2.new(0, 10, 0, 12)
	stripe.Size = UDim2.new(0, 6, 1, -24)
	stripe.BackgroundColor3 = accent
	stripe.BorderSizePixel = 0
	Components.addCorner(stripe, UDim.new(1, 0))
	stripe.Parent = frame

	local nameLabel = Components.makeLabel("Name", Theme.Fonts.Display, Theme.Colors.Text, 24)
	nameLabel.Position = UDim2.new(0, 28, 0, 10)
	nameLabel.Size = UDim2.new(1, -210, 0, 26)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = frame

	local infoLabel = Components.makeLabel("Info", Theme.Fonts.Body, accent, 18)
	infoLabel.Position = UDim2.new(0, 28, 0, 38)
	infoLabel.Size = UDim2.new(1, -210, 0, 20)
	infoLabel.TextXAlignment = Enum.TextXAlignment.Left
	infoLabel.Parent = frame

	local detailLabel = Components.makeLabel("Detail", Theme.Fonts.Body, Theme.Colors.TextMuted, 16)
	detailLabel.Position = UDim2.new(0, 28, 0, 62)
	detailLabel.Size = UDim2.new(1, -210, 0, 18)
	detailLabel.TextXAlignment = Enum.TextXAlignment.Left
	detailLabel.Parent = frame

	local buyButton = Components.makeButton("Buy", Theme.Colors.Disabled)
	buyButton.AnchorPoint = Vector2.new(1, 0.5)
	buyButton.Position = UDim2.new(1, -12, 0.5, 0)
	buyButton.Size = UDim2.fromOffset(164, 68)
	Components.addCorner(buyButton, UDim.new(0, 12))
	Components.addStroke(buyButton, Theme.Colors.Text, 2).Transparency = 0.6
	buyButton.Parent = frame

	local amountLabel = Components.makeLabel("Amount", Theme.Fonts.Body, Theme.Colors.Text, 17)
	amountLabel.AnchorPoint = Vector2.new(0.5, 0)
	amountLabel.Position = UDim2.new(0.5, 0, 0, 8)
	amountLabel.Size = UDim2.new(1, -14, 0, 20)
	amountLabel.Parent = buyButton

	local costLabel = Components.makeLabel("Cost", Theme.Fonts.Display, Theme.Colors.Text, 26)
	costLabel.AnchorPoint = Vector2.new(0.5, 1)
	costLabel.Position = UDim2.new(0.5, 0, 1, -8)
	costLabel.Size = UDim2.new(1, -14, 0, 28)
	Components.addStroke(costLabel, Theme.Colors.Background, 1.5)
	costLabel.Parent = buyButton

	frame.Parent = parent

	return {
		Id = id,
		Frame = frame,
		NameLabel = nameLabel,
		InfoLabel = infoLabel,
		DetailLabel = detailLabel,
		BuyButton = buyButton,
		AmountLabel = amountLabel,
		CostLabel = costLabel,
	}
end

local function makeScrollList(name: string, parent: Instance): ScrollingFrame
	local list = Instance.new("ScrollingFrame")
	list.Name = name
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Theme.Colors.Accent
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = parent

	local padding = Instance.new("UIPadding")
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 2)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = list

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = list

	return list
end

-- Atualização dos cartões ----------------------------------------------------------

local function refreshEquipmentCard(card: Card, def: EquipmentDef, snapshot: Snapshot, mode: BuyMode, budget: BigNum)
	local levels = snapshot.Equipment
	local level = EquipmentCalc.GetLevel(levels, def.Id)
	local unlock = EquipmentCalc.GetUnlockState(def, levels, snapshot.StageTier)

	if unlock ~= "Unlocked" then
		card.NameLabel.Text = "???"
		if unlock == "TierTooLow" then
			card.InfoLabel.Text = string.format("Requer palco tier %d", def.RequiredTier)
		else
			local requirement = def.UnlockAfter
			local requiredDef = if requirement then EquipmentCalc.GetDef(requirement) else nil
			card.InfoLabel.Text = "Compra " .. (if requiredDef then requiredDef.Name else "o anterior") .. " para desbloquear"
		end
		card.DetailLabel.Text = "Custo inicial: " .. NumberFormatter.format(def.BaseCost)
		card.BuyButton.Visible = false
		return
	end

	local unit = if def.Kind == "Click" then " / acerto" else " / s"
	card.NameLabel.Text = def.Name
	card.InfoLabel.Text = string.format(
		"Nv. %s  ·  +%s%s",
		NumberFormatter.formatInteger(level),
		NumberFormatter.format(EquipmentCalc.GetOutput(def, level)),
		unit
	)
	card.DetailLabel.Text = string.format(
		"Próximo marco: Nv. %s (×%d)",
		NumberFormatter.formatInteger(EquipmentCalc.GetNextMilestone(level)),
		EconomyConfig.Milestones.Multiplier
	)

	local count, cost, affordable = EquipmentCalc.Quote(def, level, mode, budget)
	card.BuyButton.Visible = true
	card.BuyButton.BackgroundColor3 = if affordable then Theme.Colors.Success else Theme.Colors.Disabled
	card.AmountLabel.Text = "+" .. NumberFormatter.formatInteger(count) .. (if count == 1 then " nível" else " níveis")
	card.CostLabel.Text = NumberFormatter.format(cost)
	card.CostLabel.TextColor3 = if affordable then Theme.Colors.Text else Theme.Colors.TextMuted
end

local function refreshPyroCard(card: Card, def: PyroDef, snapshot: Snapshot, dropState: DropState?, budget: BigNum)
	local owned = dropState ~= nil and dropState.Owned[def.Id] == true
	card.NameLabel.Text = def.Name
	card.InfoLabel.Text = string.format(
		"+%d no multiplicador  ·  %s",
		def.BaseMultiplier,
		if def.Cooldown > 0 then string.format("cooldown %ds", def.Cooldown) else "sem cooldown"
	)
	card.DetailLabel.Text = def.Description
	card.BuyButton.Visible = true

	if owned then
		card.BuyButton.BackgroundColor3 = Theme.Colors.Disabled
		card.AmountLabel.Text = "DESBLOQUEADA"
		card.CostLabel.Text = "✓"
		card.CostLabel.TextColor3 = Theme.Colors.Success
	elseif snapshot.StageTier < def.RequiredTier then
		card.BuyButton.BackgroundColor3 = Theme.Colors.Disabled
		card.AmountLabel.Text = "REQUER TIER"
		card.CostLabel.Text = tostring(def.RequiredTier)
		card.CostLabel.TextColor3 = Theme.Colors.TextMuted
	else
		local affordable = BigNum.gte(budget, BigNum.fromNumber(def.UnlockCost))
		card.BuyButton.BackgroundColor3 = if affordable then Theme.Colors.Success else Theme.Colors.Disabled
		card.AmountLabel.Text = "DESBLOQUEAR"
		card.CostLabel.Text = NumberFormatter.format(def.UnlockCost)
		card.CostLabel.TextColor3 = if affordable then Theme.Colors.Text else Theme.Colors.TextMuted
	end
end

local function synergyText(): string
	local lines = { "SINERGIAS (arma as máquinas juntas no mesmo drop)" }
	for _, synergy in PyroConfig.Synergies do
		local names: { string } = {}
		for _, id in synergy.Requires do
			local def = PyroConfig.ById[id]
			table.insert(names, if def then def.Name else id)
		end
		table.insert(lines, string.format("• %s — %s: ×%.2f", synergy.Name, table.concat(names, " + "), synergy.Multiplier))
	end
	return table.concat(lines, "\n")
end

-- Montagem -------------------------------------------------------------------

function ShopView.Mount()
	if activeTrove then
		return
	end
	local trove = Trove.new()
	activeTrove = trove

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Botão MELHORIAS (respeita a safe area) ------------------------------------
	local toggleGui = trove:Add(Instance.new("ScreenGui"))
	toggleGui.Name = "ShopToggleGui"
	toggleGui.ResetOnSpawn = false
	toggleGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	toggleGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	toggleGui.DisplayOrder = 1

	local toggleHolder = Components.makeFrame("ShopToggle")
	toggleHolder.AnchorPoint = Vector2.new(0, 0.5)
	toggleHolder.Position = UDim2.new(0, 16, 0.5, 0)
	toggleHolder.Size = UDim2.fromOffset(112, 112)
	toggleHolder.Size = UDim2.fromOffset(112, 100)
	SideMenu.Attach(toggleHolder, 2)

	local toggleScale = Instance.new("UIScale")
	toggleScale.Parent = toggleHolder

	local toggleButton = Components.makeButton("Button", Theme.Colors.Panel)
	toggleButton.Size = UDim2.fromScale(1, 1)
	Components.addCorner(toggleButton, UDim.new(0, 24))
	Components.addStroke(toggleButton, Theme.Colors.Highlight, 3)
	toggleButton.Parent = toggleHolder

	local toggleLabel = Components.makeLabel("Label", Theme.Fonts.Display, Theme.Colors.Text, 30)
	toggleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	toggleLabel.Position = UDim2.fromScale(0.5, 0.42)
	toggleLabel.Size = UDim2.new(0.85, 0, 0, 34)
	toggleLabel.Text = "MELHORIAS"
	Components.addStroke(toggleLabel, Theme.Colors.Background, 2)
	toggleLabel.Parent = toggleButton

	local toggleHint = Components.makeLabel("Hint", Theme.Fonts.Body, Theme.Colors.TextMuted, 16)
	toggleHint.AnchorPoint = Vector2.new(0.5, 0.5)
	toggleHint.Position = UDim2.fromScale(0.5, 0.72)
	toggleHint.Size = UDim2.new(0.8, 0, 0, 18)
	toggleHint.Text = "[B]"
	toggleHint.Visible = UserInputService.KeyboardEnabled
	toggleHint.Parent = toggleButton

	-- Painel central (ecrã inteiro, por cima de tudo) ------------------------
	local panelGui = trove:Add(Instance.new("ScreenGui"))
	panelGui.Name = "ShopPanelGui"
	panelGui.ResetOnSpawn = false
	panelGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	panelGui.ScreenInsets = Enum.ScreenInsets.None
	panelGui.DisplayOrder = 10

	local overlay = Components.makeButton("Overlay", Theme.Colors.Overlay)
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundTransparency = 1
	overlay.Visible = false
	overlay.Parent = panelGui

	local panelHolder = Components.makeFrame("PanelHolder")
	panelHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	panelHolder.Position = UDim2.fromScale(0.5, 0.5)
	panelHolder.Size = UDim2.fromOffset(Theme.Shop.PanelSize.X, Theme.Shop.PanelSize.Y)
	panelHolder.Visible = false
	panelHolder.Parent = panelGui

	local fitScale = Instance.new("UIScale")
	fitScale.Parent = panelHolder

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.BorderSizePixel = 0
	panel.Active = true -- impede cliques de atravessarem para o overlay
	Components.addCorner(panel, UDim.new(0, 20))
	Components.addStroke(panel, Theme.Colors.Accent, 3)
	panel.Parent = panelHolder

	local popScale = Instance.new("UIScale")
	popScale.Parent = panel

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

	-- Separadores
	local tabBar = Components.makeFrame("Tabs")
	tabBar.Position = UDim2.new(0, 20, 0, 14)
	tabBar.Size = UDim2.new(1, -100, 0, 46)
	tabBar.Parent = panel

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.Parent = tabBar

	local tabButtons: { [Tab]: TextButton } = {}
	local tabPages: { [Tab]: Frame } = {}
	local tabOrder: { Tab } = { "Equipment", "Pyro", "Vip" }
	local tabTitles: { [Tab]: string } = { Equipment = "EQUIPAMENTO", Pyro = "PIROTECNIA", Vip = "VIP" }

	for index, tab in tabOrder do
		local button = Components.makeButton(tab, Theme.Colors.Background)
		button.LayoutOrder = index
		button.Size = UDim2.new(1 / #tabOrder, -6, 1, 0)
		button.Font = Theme.Fonts.Display
		button.TextColor3 = Theme.Colors.Text
		button.TextScaled = true
		button.Text = tabTitles[tab]
		Components.addCorner(button, UDim.new(0, 12))
		Components.addStroke(button, Theme.Colors.AccentDark, 2)
		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MaxTextSize = 24
		constraint.Parent = button
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 6)
		padding.PaddingBottom = UDim.new(0, 6)
		padding.Parent = button
		button.Parent = tabBar
		tabButtons[tab] = button

		local page = Components.makeFrame(tab .. "Page")
		page.Position = UDim2.new(0, 0, 0, TAB_HEADER_HEIGHT)
		page.Size = UDim2.new(1, 0, 1, -TAB_HEADER_HEIGHT)
		page.Visible = false
		page.Parent = panel
		tabPages[tab] = page
	end

	-- Página de equipamento: seletor de modo + lista
	local equipmentPage = tabPages.Equipment
	local modeBar = Components.makeFrame("ModeBar")
	modeBar.Position = UDim2.new(0, 20, 0, 6)
	modeBar.Size = UDim2.new(1, -40, 0, 44)
	modeBar.Parent = equipmentPage

	local modeLayout = Instance.new("UIListLayout")
	modeLayout.FillDirection = Enum.FillDirection.Horizontal
	modeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	modeLayout.SortOrder = Enum.SortOrder.LayoutOrder
	modeLayout.Padding = UDim.new(0, 8)
	modeLayout.Parent = modeBar

	local modeButtons: { [BuyMode]: TextButton } = {}
	for index, mode in MODES do
		local button = Components.makeButton(mode, Theme.Colors.Background)
		button.LayoutOrder = index
		button.Size = UDim2.new(0.25, -6, 1, 0)
		button.Font = Theme.Fonts.Display
		button.TextColor3 = Theme.Colors.Text
		button.TextSize = 22
		button.Text = modeLabel(mode)
		Components.addCorner(button, UDim.new(0, 10))
		Components.addStroke(button, Theme.Colors.AccentDark, 2)
		button.Parent = modeBar
		modeButtons[mode] = button
		trove:Connect(button.Activated, function()
			EquipmentController.SetMode(mode)
		end)
	end

	local equipmentList = makeScrollList("List", equipmentPage)
	equipmentList.Position = UDim2.new(0, 16, 0, 62)
	equipmentList.Size = UDim2.new(1, -32, 1, -78)

	local equipmentCards: { [string]: Card } = {}
	for index, def in EquipmentConfig.List do
		equipmentCards[def.Id] = buildCard(def.Id, index, equipmentList, categoryColor(def.Category))
	end

	-- Página de pirotecnia: máquinas + sinergias
	local pyroPage = tabPages.Pyro
	local pyroList = makeScrollList("List", pyroPage)
	pyroList.Position = UDim2.new(0, 16, 0, 6)
	pyroList.Size = UDim2.new(1, -32, 1, -22)

	local pyroCards: { [string]: Card } = {}
	for index, def in PyroConfig.List do
		pyroCards[def.Id] = buildCard(def.Id, index, pyroList, Theme.Colors.Danger)
	end

	local synergyLabel = Instance.new("TextLabel")
	synergyLabel.Name = "Synergies"
	synergyLabel.LayoutOrder = #PyroConfig.List + 1
	synergyLabel.Size = UDim2.new(1, 0, 0, 0)
	synergyLabel.AutomaticSize = Enum.AutomaticSize.Y
	synergyLabel.BackgroundColor3 = Theme.Colors.Background
	synergyLabel.BorderSizePixel = 0
	synergyLabel.Font = Theme.Fonts.Body
	synergyLabel.TextColor3 = Theme.Colors.Gold
	synergyLabel.TextSize = 16
	synergyLabel.TextWrapped = true
	synergyLabel.TextXAlignment = Enum.TextXAlignment.Left
	synergyLabel.Text = synergyText()
	Components.addCorner(synergyLabel, UDim.new(0, 14))
	local synergyPadding = Instance.new("UIPadding")
	synergyPadding.PaddingTop = UDim.new(0, 10)
	synergyPadding.PaddingBottom = UDim.new(0, 10)
	synergyPadding.PaddingLeft = UDim.new(0, 14)
	synergyPadding.PaddingRight = UDim.new(0, 14)
	synergyPadding.Parent = synergyLabel
	synergyLabel.Parent = pyroList

	-- Página VIP: Gamepasses e Developer Products (Robux)
	local refreshVip = VipPage.Build(tabPages.Vip, trove)

	-- Atualização --------------------------------------------------------------
	local dirty = true
	local currentTab: Tab = "Equipment"

	local function refreshModeButtons()
		local current = EquipmentController.GetMode()
		for mode, button in modeButtons do
			button.BackgroundColor3 = if mode == current then Theme.Colors.Accent else Theme.Colors.Background
		end
	end

	local function refreshAll()
		if not isOpen then
			dirty = true
			return
		end
		local snapshot = StateController.Get()
		if not snapshot then
			return
		end
		dirty = false
		local budget = BigNum.deserialize(snapshot.Hype)
		if currentTab == "Equipment" then
			local mode = EquipmentController.GetMode()
			for _, def in EquipmentConfig.List do
				refreshEquipmentCard(equipmentCards[def.Id], def, snapshot, mode, budget)
			end
		elseif currentTab == "Vip" then
			task.spawn(refreshVip) -- os preços podem precisar de um pedido ao Roblox
		else
			local dropState = BassDropController.Get()
			for _, def in PyroConfig.List do
				refreshPyroCard(pyroCards[def.Id], def, snapshot, dropState, budget)
			end
		end
	end

	local function setTab(tab: Tab)
		currentTab = tab
		for name, page in tabPages do
			page.Visible = name == tab
		end
		for name, button in tabButtons do
			button.BackgroundColor3 = if name == tab then Theme.Colors.Accent else Theme.Colors.Background
		end
		dirty = true
		refreshAll()
	end
	setTabImpl = setTab

	for tab, button in tabButtons do
		trove:Connect(button.Activated, function()
			setTab(tab)
		end)
	end

	-- Feedback de compra -------------------------------------------------------
	local function flash(card: Card, color: Color3)
		card.Frame.BackgroundColor3 = color
		TweenService:Create(card.Frame, Theme.Tween.Ring, { BackgroundColor3 = Theme.Colors.Background }):Play()
	end

	local function shake(button: GuiObject)
		button.Rotation = 6
		TweenService:Create(
			button,
			TweenInfo.new(0.35, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
			{ Rotation = 0 }
		):Play()
	end

	for _, def in EquipmentConfig.List do
		local card = equipmentCards[def.Id]
		trove:Connect(card.BuyButton.Activated, function()
			local snapshot = StateController.Get()
			if not snapshot then
				return
			end
			local level = EquipmentCalc.GetLevel(snapshot.Equipment, def.Id)
			local _, _, affordable =
				EquipmentCalc.Quote(def, level, EquipmentController.GetMode(), BigNum.deserialize(snapshot.Hype))
			if not affordable then
				shake(card.BuyButton)
				return
			end
			EquipmentController.RequestPurchase(def.Id)
		end)
	end

	for _, def in PyroConfig.List do
		local card = pyroCards[def.Id]
		trove:Connect(card.BuyButton.Activated, function()
			local snapshot = StateController.Get()
			local dropState = BassDropController.Get()
			if not snapshot or not dropState or dropState.Owned[def.Id] then
				return
			end
			if BigNum.lt(BigNum.deserialize(snapshot.Hype), BigNum.fromNumber(def.UnlockCost)) then
				shake(card.BuyButton)
				return
			end
			BassDropController.BuyPyro(def.Id)
		end)
	end

	trove:Add(EquipmentController.PurchaseCompleted:Connect(function(result: PurchaseResult)
		local card = equipmentCards[result.EquipmentId]
		if not card then
			return
		end
		if result.Success then
			flash(card, Theme.Colors.Success)
		else
			shake(card.BuyButton)
		end
	end))

	local previousOwned: { [string]: boolean } = {}
	trove:Add(BassDropController.Changed:Connect(function(dropState: DropState)
		for id in dropState.Owned do
			local card = pyroCards[id]
			if card and not previousOwned[id] and next(previousOwned) ~= nil then
				flash(card, Theme.Colors.Success)
			end
		end
		previousOwned = table.clone(dropState.Owned)
		refreshAll()
	end))

	-- Abrir / fechar -----------------------------------------------------------
	local function setOpen(open: boolean)
		if isOpen == open then
			return
		end
		isOpen = open
		if open then
			ModalManager.NotifyOpened("Shop")
			overlay.Visible = true
			panelHolder.Visible = true
			popScale.Scale = 0.85
			TweenService:Create(popScale, Theme.Tween.Toast, { Scale = 1 }):Play()
			TweenService:Create(overlay, Theme.Tween.Fast, { BackgroundTransparency = Theme.Shop.OverlayTransparency }):Play()
			if dirty then
				refreshAll()
			end
		else
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
	ModalManager.Register("Shop", function()
		setOpen(false)
	end)
	trove:Add(function()
		ModalManager.Unregister("Shop")
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
		if input.KeyCode == Theme.Shop.ToggleKey or input.KeyCode == Theme.Shop.ToggleGamepadButton then
			setOpen(not isOpen)
		end
	end)

	-- Escalas ------------------------------------------------------------------
	local function updateScales()
		fitScale.Scale = Components.fitScale(panelGui.AbsoluteSize, Theme.Shop.PanelSize, Theme.Shop.ScreenFill)
		toggleScale.Scale = Components.computeScale(toggleGui.AbsoluteSize)
	end
	trove:Connect(panelGui:GetPropertyChangedSignal("AbsoluteSize"), updateScales)
	trove:Connect(toggleGui:GetPropertyChangedSignal("AbsoluteSize"), updateScales)

	trove:Add(StateController.Changed:Connect(function(_snapshot: Snapshot)
		refreshAll()
	end))
	trove:Add(EquipmentController.ModeChanged:Connect(function(_mode: BuyMode)
		refreshModeButtons()
		refreshAll()
	end))

	toggleGui.Parent = playerGui
	panelGui.Parent = playerGui
	updateScales()
	refreshModeButtons()
	setTab("Equipment")
end

-- Abre a loja (opcionalmente num separador específico)
function ShopView.Open(tab: Tab?)
	local setTab = setTabImpl
	if tab and setTab then
		setTab(tab)
	end
	local setOpen = setOpenImpl
	if setOpen then
		setOpen(true)
	end
end

function ShopView.Close()
	local setOpen = setOpenImpl
	if setOpen then
		setOpen(false)
	end
end

function ShopView.IsOpen(): boolean
	return isOpen
end

function ShopView.Unmount()
	local trove = activeTrove
	if trove then
		activeTrove = nil
		setOpenImpl = nil
		setTabImpl = nil
		isOpen = false
		trove:Destroy()
	end
end

return ShopView
