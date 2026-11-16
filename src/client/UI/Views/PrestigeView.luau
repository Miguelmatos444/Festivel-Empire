--!strict
--[[
	PrestigeView
	Painel "WORLD TOUR" com dois separadores:
	  WORLD TOUR — Discos a ganhar (mesma fórmula do servidor), requisitos, o que reinicia
	               e o que fica, Fama atual → seguinte, e botão "manter premido" (2 s)
	  ÁRVORE     — 4 ramos em colunas; cada nó com nível, efeito atual → seguinte, custo,
	               cadeado com o requisito e botão MELHORAR
	Botão no menu lateral (brilha quando já podes partir em Tour), tecla T.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local PrestigeConfig = require(ReplicatedStorage.Shared.Config.Prestige)
local SkillTreeConfig = require(ReplicatedStorage.Shared.Config.SkillTree)
local BigNum = require(ReplicatedStorage.Shared.Util.BigNum)
local NumberFormatter = require(ReplicatedStorage.Shared.Util.NumberFormatter)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local PrestigeCalc = require(ReplicatedStorage.Shared.Calc.PrestigeCalc)
local StageCalc = require(ReplicatedStorage.Shared.Calc.StageCalc)

local Client = script.Parent.Parent.Parent
local StateController = require(Client.Controllers.StateController)
local PrestigeController = require(Client.Controllers.PrestigeController)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local ModalManager = require(script.Parent.Parent.ModalManager)
local SideMenu = require(script.Parent.Parent.SideMenu)

type Snapshot = Types.PlayerStateSnapshot
type SkillNodeDef = Types.SkillNodeDef

export type Tab = "Tour" | "Tree"

type NodeCard = {
	Def: SkillNodeDef,
	Frame: Frame,
	Stroke: UIStroke,
	Level: TextLabel,
	Effect: TextLabel,
	Button: TextButton,
}

local PANEL_SIZE = Vector2.new(880, 620)
local HEADER = 64
local TOGGLE_KEY = Enum.KeyCode.T
local DISC = "◉"

local PrestigeView = {}

local activeTrove: Trove.Trove? = nil
local setOpenImpl: ((boolean) -> ())? = nil
local isOpen = false

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
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = button
	return button
end

local function wrapLabel(name: string, font: Enum.Font, color: Color3, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextColor3 = color
	label.TextSize = size
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = ""
	return label
end

function PrestigeView.Mount()
	if activeTrove then
		return
	end
	local trove = Trove.new()
	activeTrove = trove

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Botão no menu lateral -------------------------------------------------
	local toggleGui = trove:Add(Instance.new("ScreenGui"))
	toggleGui.Name = "PrestigeToggleGui"
	toggleGui.ResetOnSpawn = false
	toggleGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets

	local toggleHolder = trove:Add(Components.makeFrame("PrestigeToggle"))
	toggleHolder.Size = UDim2.fromOffset(112, 100)
	local toggleScale = Instance.new("UIScale")
	toggleScale.Parent = toggleHolder

	local toggleButton = Components.makeButton("Button", Theme.Colors.Panel)
	toggleButton.Size = UDim2.fromScale(1, 1)
	Components.addCorner(toggleButton, UDim.new(0, 22))
	local toggleStroke = Components.addStroke(toggleButton, Theme.Colors.TextMuted, 3)
	toggleButton.Parent = toggleHolder

	local toggleLabel = Components.makeLabel("Label", Theme.Fonts.Display, Theme.Colors.Text, 20)
	toggleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	toggleLabel.Position = UDim2.fromScale(0.5, 0.4)
	toggleLabel.Size = UDim2.new(0.92, 0, 0, 44)
	toggleLabel.TextWrapped = true
	toggleLabel.Text = "WORLD\nTOUR"
	Components.addStroke(toggleLabel, Theme.Colors.Background, 2)
	toggleLabel.Parent = toggleButton

	local toggleHint = Components.makeLabel("Hint", Theme.Fonts.Body, Theme.Colors.TextMuted, 16)
	toggleHint.AnchorPoint = Vector2.new(0.5, 0.5)
	toggleHint.Position = UDim2.fromScale(0.5, 0.8)
	toggleHint.Size = UDim2.new(0.8, 0, 0, 18)
	toggleHint.Text = "[T]"
	toggleHint.Visible = UserInputService.KeyboardEnabled
	toggleHint.Parent = toggleButton

	SideMenu.Attach(toggleHolder, 5)

	-- Painel ---------------------------------------------------------------
	local panelGui = trove:Add(Instance.new("ScreenGui"))
	panelGui.Name = "PrestigePanelGui"
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
	panelHolder.Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y)
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
	Components.addStroke(panel, Color3.fromRGB(180, 235, 255), 3)
	panel.Parent = panelHolder

	local popScale = Instance.new("UIScale")
	popScale.Parent = panel

	local closeButton = textButton("Close", "X", Theme.Colors.Danger, UDim2.fromOffset(46, 46))
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -16, 0, 12)
	closeButton.Parent = panel

	local discsLabel = Components.makeLabel("Discs", Theme.Fonts.Display, Color3.fromRGB(180, 235, 255), 22)
	discsLabel.AnchorPoint = Vector2.new(1, 0)
	discsLabel.Position = UDim2.new(1, -72, 0, 16)
	discsLabel.Size = UDim2.fromOffset(300, 38)
	discsLabel.TextXAlignment = Enum.TextXAlignment.Right
	discsLabel.Parent = panel

	local tabBar = Components.makeFrame("Tabs")
	tabBar.Position = UDim2.fromOffset(20, 12)
	tabBar.Size = UDim2.fromOffset(440, 46)
	tabBar.Parent = panel
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabBar

	local tabButtons: { [Tab]: TextButton } = {
		Tour = textButton("Tour", "WORLD TOUR", Theme.Colors.Background, UDim2.new(0.5, -4, 1, 0)),
		Tree = textButton("Tree", "ÁRVORE", Theme.Colors.Background, UDim2.new(0.5, -4, 1, 0)),
	}
	tabButtons.Tour.LayoutOrder = 1
	tabButtons.Tree.LayoutOrder = 2
	tabButtons.Tour.Parent = tabBar
	tabButtons.Tree.Parent = tabBar

	local function makePage(name: string): Frame
		local page = Components.makeFrame(name)
		page.Position = UDim2.fromOffset(0, HEADER)
		page.Size = UDim2.new(1, 0, 1, -HEADER)
		page.Visible = false
		page.Parent = panel
		return page
	end
	local tourPage = makePage("TourPage")
	local treePage = makePage("TreePage")

	-- ======================= WORLD TOUR =======================
	local gainLabel = Components.makeLabel("Gain", Theme.Fonts.Display, Theme.Colors.Gold, 44)
	gainLabel.Position = UDim2.fromOffset(24, 6)
	gainLabel.Size = UDim2.new(1, -48, 0, 52)
	Components.addStroke(gainLabel, Theme.Colors.Background, 2)
	gainLabel.Parent = tourPage

	local formulaLabel = Components.makeLabel("Formula", Theme.Fonts.Body, Theme.Colors.TextMuted, 16)
	formulaLabel.Position = UDim2.fromOffset(24, 60)
	formulaLabel.Size = UDim2.new(1, -48, 0, 20)
	formulaLabel.Parent = tourPage

	local requirementsLabel = wrapLabel("Requirements", Theme.Fonts.Body, Theme.Colors.Text, 17)
	requirementsLabel.Position = UDim2.fromOffset(24, 92)
	requirementsLabel.Size = UDim2.new(1, -48, 0, 50)
	requirementsLabel.Parent = tourPage

	local function infoBox(name: string, title: string, color: Color3, x: number): TextLabel
		local box = Instance.new("Frame")
		box.Name = name
		box.Position = UDim2.new(x, if x == 0 then 24 else 8, 0, 150)
		box.Size = UDim2.new(0.5, -32, 0, 210)
		box.BackgroundColor3 = Theme.Colors.Background
		box.BorderSizePixel = 0
		Components.addCorner(box, UDim.new(0, 14))
		Components.addStroke(box, color, 1.5).Transparency = 0.3
		box.Parent = tourPage

		local heading = Components.makeLabel("Title", Theme.Fonts.Display, color, 22)
		heading.Position = UDim2.fromOffset(14, 8)
		heading.Size = UDim2.new(1, -28, 0, 26)
		heading.TextXAlignment = Enum.TextXAlignment.Left
		heading.Text = title
		heading.Parent = box

		local body = wrapLabel("Body", Theme.Fonts.Body, Theme.Colors.Text, 16)
		body.Position = UDim2.fromOffset(14, 40)
		body.Size = UDim2.new(1, -28, 1, -48)
		body.Parent = box
		return body
	end
	local resetsBody = infoBox("Resets", "REINICIA", Theme.Colors.Danger, 0)
	local keepsBody = infoBox("Keeps", "MANTÉM", Theme.Colors.Success, 0.5)

	local fameLabel = Components.makeLabel("Fame", Theme.Fonts.Display, Theme.Colors.Highlight, 20)
	fameLabel.Position = UDim2.fromOffset(24, 372)
	fameLabel.Size = UDim2.new(1, -48, 0, 26)
	fameLabel.Parent = tourPage

	local holdButton = Components.makeButton("Hold", Theme.Colors.Disabled)
	holdButton.AnchorPoint = Vector2.new(0.5, 1)
	holdButton.Position = UDim2.new(0.5, 0, 1, -18)
	holdButton.Size = UDim2.fromOffset(420, 72)
	holdButton.ClipsDescendants = true
	Components.addCorner(holdButton, UDim.new(0, 16))
	Components.addStroke(holdButton, Theme.Colors.Text, 2).Transparency = 0.4
	holdButton.Parent = tourPage

	local holdFill = Instance.new("Frame")
	holdFill.Name = "Fill"
	holdFill.Size = UDim2.fromScale(0, 1)
	holdFill.BackgroundColor3 = Theme.Colors.Gold
	holdFill.BorderSizePixel = 0
	holdFill.Parent = holdButton

	local holdLabel = Components.makeLabel("Label", Theme.Fonts.Display, Theme.Colors.Text, 24)
	holdLabel.Size = UDim2.new(1, -20, 1, -12)
	holdLabel.Position = UDim2.fromOffset(10, 6)
	holdLabel.ZIndex = 2
	Components.addStroke(holdLabel, Theme.Colors.Background, 2)
	holdLabel.Parent = holdButton

	-- ======================= ÁRVORE =======================
	local nodeCards: { NodeCard } = {}
	local columnWidth = 1 / #SkillTreeConfig.Branches
	for branchIndex, branch in SkillTreeConfig.Branches do
		local column = Components.makeFrame(branch.Id)
		column.Position = UDim2.new(columnWidth * (branchIndex - 1), 10, 0, 4)
		column.Size = UDim2.new(columnWidth, -20, 1, -16)
		column.Parent = treePage

		local heading = Components.makeLabel("Heading", Theme.Fonts.Display, branch.Color, 20)
		heading.Size = UDim2.new(1, 0, 0, 26)
		heading.Text = branch.Name
		heading.Parent = column

		-- Linha que liga os nós do ramo
		local spine = Instance.new("Frame")
		spine.Name = "Spine"
		spine.AnchorPoint = Vector2.new(0.5, 0)
		spine.Position = UDim2.new(0.5, 0, 0, 40)
		spine.Size = UDim2.new(0, 4, 1, -60)
		spine.BackgroundColor3 = branch.Color
		spine.BackgroundTransparency = 0.6
		spine.BorderSizePixel = 0
		spine.Parent = column

		for _, def in SkillTreeConfig.List do
			if def.Branch == branch.Id then
				local frame = Instance.new("Frame")
				frame.Name = def.Id
				frame.Position = UDim2.new(0, 0, 0, 34 + (def.Row - 1) * 128)
				frame.Size = UDim2.new(1, 0, 0, 118)
				frame.BackgroundColor3 = Theme.Colors.Background
				frame.BorderSizePixel = 0
				Components.addCorner(frame, UDim.new(0, 12))
				local stroke = Components.addStroke(frame, branch.Color, 1.5)
				frame.Parent = column

				local nameLabel = Components.makeLabel("Name", Theme.Fonts.Display, Theme.Colors.Text, 17)
				nameLabel.Position = UDim2.fromOffset(8, 6)
				nameLabel.Size = UDim2.new(1, -16, 0, 22)
				nameLabel.TextXAlignment = Enum.TextXAlignment.Left
				nameLabel.Text = def.Name
				nameLabel.Parent = frame

				local levelLabel = Components.makeLabel("Level", Theme.Fonts.Body, branch.Color, 14)
				levelLabel.Position = UDim2.fromOffset(8, 28)
				levelLabel.Size = UDim2.new(1, -16, 0, 16)
				levelLabel.TextXAlignment = Enum.TextXAlignment.Left
				levelLabel.Parent = frame

				local effectLabel = wrapLabel("Effect", Theme.Fonts.Body, Theme.Colors.TextMuted, 13)
				effectLabel.Position = UDim2.fromOffset(8, 46)
				effectLabel.Size = UDim2.new(1, -16, 0, 34)
				effectLabel.Parent = frame

				local button = textButton("Buy", "", Theme.Colors.Disabled, UDim2.new(1, -16, 0, 28), 15)
				button.Position = UDim2.new(0, 8, 1, -34)
				button.Parent = frame

				local card: NodeCard = { Def = def, Frame = frame, Stroke = stroke, Level = levelLabel, Effect = effectLabel, Button = button }
				table.insert(nodeCards, card)

				trove:Connect(button.Activated, function()
					local snapshot = StateController.Get()
					if not snapshot then
						return
					end
					if
						PrestigeCalc.GetNodeStatus(snapshot.SkillTree, def.Id, snapshot.PlatinumDiscs) ~= "Available"
						or not PrestigeController.BuyNode(def.Id)
					then
						button.Rotation = 5
						TweenService:Create(button, TweenInfo.new(0.35, Enum.EasingStyle.Elastic), { Rotation = 0 }):Play()
					end
				end)
			end
		end
	end

	-- Atualização --------------------------------------------------------------
	local currentTab: Tab = "Tour"
	local eligible = false

	local function refresh()
		local snapshot = StateController.Get()
		if not snapshot then
			return
		end
		local runHype = BigNum.deserialize(snapshot.RunHypeEarned)
		local discs = PrestigeCalc.GetDiscsPreview(runHype, snapshot.StageTier, snapshot.SkillTree)
		local can, reason = PrestigeCalc.CanWorldTour(snapshot.StageTier, discs)
		eligible = can

		-- Botão do menu brilha quando já se pode partir
		toggleStroke.Color = if can then Theme.Colors.Gold else Theme.Colors.TextMuted
		toggleStroke.Thickness = if can then 4 else 3

		discsLabel.Text = string.format("%s %s Discos de Platina", DISC, NumberFormatter.formatInteger(snapshot.PlatinumDiscs))

		if not isOpen then
			return
		end

		if currentTab == "Tour" then
			local skills = PrestigeCalc.GetSkillEffects(snapshot.SkillTree)
			gainLabel.Text = string.format("+%s %s Discos de Platina", DISC, NumberFormatter.formatInteger(discs))
			formulaLabel.Text = string.format(
				"Hype desta run: %s · Tier final %d (+%d%%) · Contrato +%d%%",
				NumberFormatter.format(runHype),
				snapshot.StageTier,
				math.floor(PrestigeConfig.TierBonus * math.max(snapshot.StageTier - PrestigeConfig.MinTier, 0) * 100 + 0.5),
				math.floor(skills.DiscBonus * 100 + 0.5)
			)
			local tierOk = snapshot.StageTier >= PrestigeConfig.MinTier
			requirementsLabel.Text = string.format(
				"%s Tier %d ou superior (atual: Tier %d)\n%s Pelo menos 1 Disco de Platina%s",
				if tierOk then "✓" else "✗",
				PrestigeConfig.MinTier,
				snapshot.StageTier,
				if discs >= 1 then "✓" else "✗",
				if not can and reason then "  —  " .. reason else ""
			)
			requirementsLabel.TextColor3 = if can then Theme.Colors.Success else Theme.Colors.Text

			local startTier = PrestigeCalc.GetStartTier(snapshot.SkillTree, snapshot.WorldTours + 1)
			resetsBody.Text = table.concat({
				"• Hype → " .. NumberFormatter.format(skills.StartingHype),
				"• Equipamento"
					.. (if skills.StartingGenerators > 0 then string.format(" (4 primeiros no nível %d)", skills.StartingGenerators) else ""),
				string.format("• Palco → Tier %d (%s)", startTier, StageCalc.GetDef(startTier).Name),
				"• Energia, boost e cooldowns do Bass Drop",
			}, "\n")
			keepsBody.Text = table.concat({
				"• Artistas e toda a coleção",
				"• Árvore de habilidades",
				"• Discos de Platina por gastar",
				"• Pirotecnia desbloqueada",
				"• +1 World Tour (Fama, slots de artistas, palcos)",
			}, "\n")
			fameLabel.Text = string.format(
				"Fama do Tour: Hype ×%s → ×%s  ·  próximo: World Tour #%d",
				NumberFormatter.format(PrestigeCalc.GetFameMultiplier(snapshot.WorldTours)),
				NumberFormatter.format(PrestigeCalc.GetFameMultiplier(snapshot.WorldTours + 1)),
				snapshot.WorldTours + 1
			)
			holdButton.BackgroundColor3 = if can then Theme.Colors.Accent else Theme.Colors.Disabled
			holdLabel.Text = if can then "MANTÉM PREMIDO PARA PARTIR EM TOUR" else "AINDA NÃO PODES PARTIR"
		else
			for _, card in nodeCards do
				local def = card.Def
				local level = PrestigeCalc.GetLevel(snapshot.SkillTree, def.Id)
				local status = PrestigeCalc.GetNodeStatus(snapshot.SkillTree, def.Id, snapshot.PlatinumDiscs)
				card.Level.Text = string.format("Nv. %d/%d", level, def.MaxLevel)
				if level >= def.MaxLevel then
					card.Effect.Text = PrestigeCalc.DescribeEffect(def, level)
				else
					card.Effect.Text = (if level > 0 then PrestigeCalc.DescribeEffect(def, level) .. "\n→ " else "→ ")
						.. PrestigeCalc.DescribeEffect(def, level + 1)
				end
				card.Stroke.Transparency = if status == "Locked" then 0.7 else 0
				if status == "Maxed" then
					card.Button.Text = "MÁXIMO"
					card.Button.BackgroundColor3 = Theme.Colors.AccentDark
				elseif status == "Locked" then
					local requirement = def.Requires
					local requiredDef = if requirement then SkillTreeConfig.ById[requirement] else nil
					card.Button.Text = string.format("🔒 %s nv %d", if requiredDef then requiredDef.Name else "?", def.RequiresLevel or 1)
					card.Button.BackgroundColor3 = Theme.Colors.Disabled
				else
					card.Button.Text = string.format("MELHORAR  %s %s", DISC, NumberFormatter.formatInteger(PrestigeCalc.GetNextCost(def, level)))
					card.Button.BackgroundColor3 = if status == "Available" then Theme.Colors.Success else Theme.Colors.Disabled
				end
			end
		end
	end

	-- Manter premido ------------------------------------------------------------
	local holdStart: number? = nil
	local holdConnection: RBXScriptConnection? = nil

	local function stopHold()
		holdStart = nil
		local connection = holdConnection
		if connection then
			connection:Disconnect()
			holdConnection = nil
		end
		holdFill.Size = UDim2.fromScale(0, 1)
	end

	local setOpen: (boolean) -> ()

	local function startHold()
		if not eligible or holdStart then
			return
		end
		holdStart = os.clock()
		holdConnection = RunService.RenderStepped:Connect(function()
			local started = holdStart
			if not started then
				return
			end
			local progress = math.clamp((os.clock() - started) / PrestigeConfig.ConfirmHoldSeconds, 0, 1)
			holdFill.Size = UDim2.fromScale(progress, 1)
			if progress >= 1 then
				stopHold()
				if PrestigeController.DoWorldTour() then
					setOpen(false)
				end
			end
		end)
	end

	trove:Connect(holdButton.MouseButton1Down, startHold)
	trove:Connect(holdButton.MouseButton1Up, stopHold)
	trove:Connect(holdButton.MouseLeave, stopHold)
	trove:Add(stopHold)

	-- Abrir / fechar --------------------------------------------------------------
	local function setTab(tab: Tab)
		currentTab = tab
		tourPage.Visible = tab == "Tour"
		treePage.Visible = tab == "Tree"
		for name, button in tabButtons do
			button.BackgroundColor3 = if name == tab then Theme.Colors.Accent else Theme.Colors.Background
		end
		stopHold()
		refresh()
	end

	setOpen = function(open: boolean)
		if isOpen == open then
			return
		end
		isOpen = open
		stopHold()
		if open then
			ModalManager.NotifyOpened("Prestige")
			overlay.Visible = true
			panelHolder.Visible = true
			popScale.Scale = 0.85
			TweenService:Create(popScale, Theme.Tween.Toast, { Scale = 1 }):Play()
			TweenService:Create(overlay, Theme.Tween.Fast, { BackgroundTransparency = Theme.Shop.OverlayTransparency }):Play()
			setTab(currentTab)
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
	ModalManager.Register("Prestige", function()
		setOpen(false)
	end)
	trove:Add(function()
		ModalManager.Unregister("Prestige")
	end)

	for name, button in tabButtons do
		trove:Connect(button.Activated, function()
			setTab(name)
		end)
	end
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
	trove:Add(StateController.Changed:Connect(function(_snapshot: Snapshot)
		refresh()
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
	setTab("Tour")
end

function PrestigeView.Open()
	local setOpen = setOpenImpl
	if setOpen then
		setOpen(true)
	end
end

return PrestigeView
