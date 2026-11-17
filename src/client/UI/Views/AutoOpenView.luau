--!strict
--[[
	AutoOpenView
	Auto-Abrir (Fase 13C):
	  - painel das condições, aberto pelo botão AUTO de cada crate (ArtistsView):
	    quantidade x1/x10, "parar quando sair" uma das 6 raridades da janela da crate (ou
	    Nunca), artista NOVO, variante Brilhante, e COMEÇAR
	  - barra no topo do ecrã enquanto corre: crate, aberturas, melhor raridade e PARAR;
	    no fim mostra o motivo da paragem durante Config/Monetization.AutoOpen.ReasonTime
	  - abrir outra UI (que não a das crates/roleta) pára o Auto-Abrir
	Não é um modal (não fecha o menu das crates); só apresentação e intenções.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Types = require(ReplicatedStorage.Shared.Types)
local MonetizationConfig = require(ReplicatedStorage.Shared.Config.Monetization)
local RaritiesConfig = require(ReplicatedStorage.Shared.Config.Rarities)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local ArtistCalc = require(ReplicatedStorage.Shared.Calc.ArtistCalc)

local Client = script.Parent.Parent.Parent
local AutoOpenController = require(Client.Controllers.AutoOpenController)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local ModalManager = require(script.Parent.Parent.ModalManager)

type CrateDef = Types.CrateDef
type AutoOpenState = Types.AutoOpenState
type AutoOpenSettings = Types.AutoOpenSettings

local PANEL_SIZE = Vector2.new(540, 470)
local BAR_SIZE = Vector2.new(560, 58)
local ALLOWED_MODALS = { "Artists", "CrateReveal" } -- abrir qualquer outra UI pára o Auto-Abrir
local AUTO = MonetizationConfig.AutoOpen

local AutoOpenView = {}

local activeTrove: Trove.Trove? = nil
local openConfigImpl: ((crate: CrateDef) -> ())? = nil

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

local function sectionLabel(parent: Instance, text: string, y: number): TextLabel
	local label = Components.makeLabel("Section", Theme.Fonts.Display, Theme.Colors.Gold, 17)
	label.Position = UDim2.fromOffset(22, y)
	label.Size = UDim2.new(1, -44, 0, 22)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = parent
	return label
end

function AutoOpenView.Mount()
	if activeTrove then
		return
	end
	local trove = Trove.new()
	activeTrove = trove
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- ================= Painel das condições =================
	local gui = trove:Add(Instance.new("ScreenGui"))
	gui.Name = "AutoOpenGui"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.DisplayOrder = 20 -- por cima do menu das crates

	local overlay = Components.makeButton("Overlay", Theme.Colors.Overlay)
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundTransparency = 0.45
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
	Components.addCorner(panel, UDim.new(0, 18))
	Components.addStroke(panel, Theme.Colors.Gold, 3)
	panel.Parent = holder
	local popScale = Instance.new("UIScale")
	popScale.Parent = panel

	local title = Components.makeLabel("Title", Theme.Fonts.Display, Theme.Colors.Gold, 26)
	title.Position = UDim2.fromOffset(22, 12)
	title.Size = UDim2.new(1, -90, 0, 32)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	local closeButton = textButton("Close", "X", Theme.Colors.Danger, UDim2.fromOffset(42, 42), 20)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -14, 0, 10)
	closeButton.Parent = panel

	-- Quantidade
	sectionLabel(panel, "QUANTIDADE", 58)
	local countButtons: { [number]: TextButton } = {}
	for index, count in { 1, 10 } do
		local button = textButton("Count" .. count, "x" .. count, Theme.Colors.Background, UDim2.fromOffset(120, 40), 20)
		button.Position = UDim2.fromOffset(22 + (index - 1) * 132, 84)
		button.Parent = panel
		countButtons[count] = button
	end

	-- Parar na raridade
	sectionLabel(panel, "PARAR QUANDO SAIR (ou melhor)", 136)
	local chipGrid = Components.makeFrame("Chips")
	chipGrid.Position = UDim2.fromOffset(22, 162)
	chipGrid.Size = UDim2.new(1, -44, 0, 3 * 46)
	chipGrid.Parent = panel
	local chipLayout = Instance.new("UIGridLayout")
	chipLayout.CellSize = UDim2.new(1 / 3, -6, 0, 40)
	chipLayout.CellPadding = UDim2.fromOffset(8, 6)
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Parent = chipGrid

	-- Condições extra
	local newButton = textButton("StopNew", "", Theme.Colors.Background, UDim2.new(0.5, -28, 0, 40), 16)
	newButton.Position = UDim2.fromOffset(22, 312)
	newButton.Parent = panel
	local shinyButton = textButton("StopShiny", "", Theme.Colors.Background, UDim2.new(0.5, -28, 0, 40), 16)
	shinyButton.AnchorPoint = Vector2.new(1, 0)
	shinyButton.Position = UDim2.new(1, -22, 0, 312)
	shinyButton.Parent = panel

	local info = Components.makeLabel("Info", Theme.Fonts.Body, Theme.Colors.TextMuted, 13)
	info.Position = UDim2.fromOffset(22, 358)
	info.Size = UDim2.new(1, -44, 0, 36)
	info.TextWrapped = true
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.TextYAlignment = Enum.TextYAlignment.Top
	info.Text = string.format(
		"Pára sempre: carta mistério, Hype insuficiente, coleção cheia, morrer ou abrir outra janela. Máx. %d aberturas de cada vez. Usa sempre a animação rápida.",
		AUTO.MaxOpens
	)
	info.Parent = panel

	local startButton = textButton("Start", "COMEÇAR", Theme.Colors.Success, UDim2.new(0.5, -28, 0, 52), 22)
	startButton.AnchorPoint = Vector2.new(0, 1)
	startButton.Position = UDim2.new(0, 22, 1, -14)
	startButton.Parent = panel
	local cancelButton = textButton("Cancel", "CANCELAR", Theme.Colors.Background, UDim2.new(0.5, -28, 0, 52), 22)
	cancelButton.AnchorPoint = Vector2.new(1, 1)
	cancelButton.Position = UDim2.new(1, -22, 1, -14)
	cancelButton.Parent = panel

	-- ================= Barra de progresso =================
	local barGui = trove:Add(Instance.new("ScreenGui"))
	barGui.Name = "AutoOpenBar"
	barGui.ResetOnSpawn = false
	barGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	barGui.DisplayOrder = 30 -- por cima da roleta das crates

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 8)
	bar.Size = UDim2.fromOffset(BAR_SIZE.X, BAR_SIZE.Y)
	bar.BackgroundColor3 = Theme.Colors.Panel
	bar.BorderSizePixel = 0
	bar.Visible = false
	Components.addCorner(bar, UDim.new(0, 14))
	local barStroke = Components.addStroke(bar, Theme.Colors.Gold, 2.5)
	bar.Parent = barGui
	local barScale = Instance.new("UIScale")
	barScale.Parent = bar

	local barLabel = Components.makeLabel("Label", Theme.Fonts.Display, Theme.Colors.Text, 18)
	barLabel.Position = UDim2.fromOffset(16, 0)
	barLabel.Size = UDim2.new(1, -150, 1, 0)
	barLabel.TextXAlignment = Enum.TextXAlignment.Left
	barLabel.TextWrapped = true
	barLabel.Parent = bar

	local stopButton = textButton("Stop", "PARAR", Theme.Colors.Danger, UDim2.fromOffset(116, 42), 20)
	stopButton.AnchorPoint = Vector2.new(1, 0.5)
	stopButton.Position = UDim2.new(1, -8, 0.5, 0)
	stopButton.Parent = bar

	-- Estado ---------------------------------------------------------------------------
	local isOpen = false
	local configCrate: CrateDef? = nil
	local rules: AutoOpenSettings = AutoOpenController.GetRules()
	local chipTrove = trove:Extend()
	local hideToken = 0

	local function refreshConfig()
		local crate = configCrate
		if not crate then
			return
		end
		for count, button in countButtons do
			local selected = rules.Count == count
			button.BackgroundColor3 = if selected then Theme.Colors.Accent else Theme.Colors.Background
		end
		newButton.Text = "Artista NOVO: " .. (if rules.StopNew then "PARA" else "ignora")
		newButton.BackgroundColor3 = if rules.StopNew then Theme.Colors.Accent else Theme.Colors.Background
		shinyButton.Text = "Brilhante ★: " .. (if rules.StopShiny then "PARA" else "ignora")
		shinyButton.BackgroundColor3 = if rules.StopShiny then Theme.Colors.Accent else Theme.Colors.Background

		chipTrove:Clean()
		local entries: { { Slot: number, Name: string, Detail: string, Color: Color3 } } = {}
		for _, odd in ArtistCalc.GetCrateOdds(crate) do
			table.insert(entries, {
				Slot = odd.Slot,
				Name = odd.Rarity.Name,
				Detail = string.format("%g%%", math.floor(odd.Chance * 1000 + 0.5) / 10),
				Color = odd.Rarity.Color,
			})
		end
		table.insert(entries, { Slot = 0, Name = "Nunca", Detail = "só as outras regras", Color = Theme.Colors.Background })
		for order, entry in entries do
			local selected = rules.StopSlot == entry.Slot
			local chip = chipTrove:Add(Components.makeButton("Chip" .. entry.Slot, entry.Color))
			chip.LayoutOrder = order
			chip.Text = ""
			chip.BackgroundTransparency = if selected then 0 else 0.45
			Components.addCorner(chip, UDim.new(0, 10))
			Components.addStroke(chip, if selected then Theme.Colors.Text else entry.Color, if selected then 3 else 1)
			chip.Parent = chipGrid
			local name = Components.makeLabel("Name", Theme.Fonts.Display, Theme.Colors.Text, 15)
			name.Position = UDim2.fromOffset(6, 2)
			name.Size = UDim2.new(1, -12, 0, 20)
			name.Text = entry.Name
			Components.addStroke(name, Theme.Colors.Background, 1.5)
			name.Parent = chip
			local detail = Components.makeLabel("Detail", Theme.Fonts.Body, Theme.Colors.Text, 12)
			detail.Position = UDim2.fromOffset(6, 21)
			detail.Size = UDim2.new(1, -12, 0, 16)
			detail.Text = entry.Detail
			Components.addStroke(detail, Theme.Colors.Background, 1)
			detail.Parent = chip
			chipTrove:Connect(chip.Activated, function()
				rules.StopSlot = entry.Slot
				refreshConfig()
			end)
		end
	end

	local function setOpen(open: boolean)
		if isOpen == open then
			return
		end
		isOpen = open
		overlay.Visible = open
		holder.Visible = open
		if open then
			popScale.Scale = 0.85
			TweenService:Create(popScale, Theme.Tween.Toast, { Scale = 1 }):Play()
		end
	end

	openConfigImpl = function(crate: CrateDef)
		if not AutoOpenController.Owns() then
			return
		end
		configCrate = crate
		rules = AutoOpenController.GetRules()
		title.Text = "AUTO-ABRIR · " .. crate.Name
		title.TextColor3 = crate.Color
		refreshConfig()
		setOpen(true)
	end

	local function bestText(state: AutoOpenState): string
		local rarity = RaritiesConfig.ById[state.Best]
		return if rarity then rarity.Name else "—"
	end

	local function renderBar(state: AutoOpenState)
		local crate = ArtistCalc.GetCrate(state.CrateId)
		local best = RaritiesConfig.ById[state.Best]
		hideToken += 1
		if state.Running then
			bar.Visible = true
			stopButton.Visible = true
			barStroke.Color = if best then best.Color else Theme.Colors.Gold
			barLabel.Text = string.format(
				"AUTO-ABRIR · %s x%d · %d aberturas · melhor: %s",
				if crate then crate.Name else state.CrateId,
				state.Count,
				state.Opened,
				bestText(state)
			)
			return
		end
		-- Parou: motivo durante uns segundos
		bar.Visible = true
		stopButton.Visible = false
		barStroke.Color = Theme.Colors.Highlight
		barLabel.Text = string.format("Parou: %s (%d aberturas · melhor: %s)", state.Reason or "—", state.Opened, bestText(state))
		barScale.Scale = 1.12
		TweenService:Create(barScale, Theme.Tween.Toast, { Scale = 1 }):Play()
		local token = hideToken
		task.delay(AUTO.ReasonTime, function()
			if token == hideToken then
				bar.Visible = false
			end
		end)
	end

	-- Ligações -------------------------------------------------------------------------
	for count, button in countButtons do
		trove:Connect(button.Activated, function()
			rules.Count = count
			refreshConfig()
		end)
	end
	trove:Connect(newButton.Activated, function()
		rules.StopNew = not rules.StopNew
		refreshConfig()
	end)
	trove:Connect(shinyButton.Activated, function()
		rules.StopShiny = not rules.StopShiny
		refreshConfig()
	end)
	trove:Connect(startButton.Activated, function()
		local crate = configCrate
		if not crate then
			return
		end
		if AutoOpenController.Start(crate.Id, rules) then
			setOpen(false)
		else
			startButton.Rotation = 4
			TweenService:Create(startButton, TweenInfo.new(0.3, Enum.EasingStyle.Elastic), { Rotation = 0 }):Play()
		end
	end)
	for _, button in { cancelButton, closeButton } do
		trove:Connect(button.Activated, function()
			setOpen(false)
		end)
	end
	trove:Connect(overlay.Activated, function()
		setOpen(false)
	end)
	trove:Connect(stopButton.Activated, function()
		AutoOpenController.Stop()
	end)

	trove:Add(AutoOpenController.Changed:Connect(renderBar))
	-- Outra UI aberta: fecha o painel e pára o Auto-Abrir
	trove:Add(ModalManager.Listen(function(name: string)
		if table.find(ALLOWED_MODALS, name) then
			return
		end
		setOpen(false)
		AutoOpenController.Stop()
	end))

	local function updateScale()
		fitScale.Scale = Components.fitScale(gui.AbsoluteSize, PANEL_SIZE, Theme.Shop.ScreenFill)
		-- A barra cabe no telemóvel: no máximo 95% da largura do ecrã
		bar.Size = UDim2.new(0, math.min(BAR_SIZE.X, barGui.AbsoluteSize.X * 0.95), 0, BAR_SIZE.Y)
	end
	trove:Connect(gui:GetPropertyChangedSignal("AbsoluteSize"), updateScale)
	gui.Parent = playerGui
	barGui.Parent = playerGui
	updateScale()
	trove:Add(function()
		openConfigImpl = nil
	end)
end

-- Abre o painel das condições para `crate` (só com o Gamepass)
function AutoOpenView.OpenConfig(crate: CrateDef)
	local open = openConfigImpl
	if open then
		open(crate)
	end
end

return AutoOpenView
