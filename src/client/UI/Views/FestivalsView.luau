--!strict
--[[
	FestivalsView
	Painel "FESTIVAIS" (menu lateral, ordem 7, tecla G):
	  - os bónus sociais atuais (amigos, grupo, Likes, Headliner) e o multiplicador total
	  - estado do evento Headliner (ao vivo / contagem até ao próximo)
	  - lista dos festivais do servidor com tier, World Tours, Likes e VISITAR
	Todos os números vêm do servidor (SocialSync e atributos FE_*) ou de SocialCalc.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local SocialConfig = require(ReplicatedStorage.Shared.Config.Social)
local MapConfig = require(ReplicatedStorage.Shared.Config.Map)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local MapCalc = require(ReplicatedStorage.Shared.Calc.MapCalc)
local SocialCalc = require(ReplicatedStorage.Shared.Calc.SocialCalc)

local Client = script.Parent.Parent.Parent
local SocialController = require(Client.Controllers.SocialController)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local ModalManager = require(script.Parent.Parent.ModalManager)
local SideMenu = require(script.Parent.Parent.SideMenu)

type Row = {
	Frame: Frame,
	Name: TextLabel,
	Info: TextLabel,
	Button: TextButton,
	PlotIndex: number,
}

local PANEL_SIZE = Vector2.new(720, 560)
local ROW_HEIGHT = 62
local TOGGLE_KEY = Enum.KeyCode.G

local FestivalsView = {}

local activeTrove: Trove.Trove? = nil
local isOpen = false
local setOpenImpl: ((boolean) -> ())? = nil

local function percent(value: number): string
	return string.format("+%d%%", math.floor(value * 100 + 0.5))
end

local function formatCountdown(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local hours = s // 3600
	local minutes = (s % 3600) // 60
	if hours > 0 then
		return string.format("%dh %02dm", hours, minutes)
	end
	return string.format("%d:%02d", minutes, s % 60)
end

local function textButton(name: string, text: string, color: Color3, size: UDim2): TextButton
	local button = Components.makeButton(name, color)
	button.Size = size
	button.Font = Theme.Fonts.Display
	button.TextColor3 = Theme.Colors.Text
	button.TextScaled = true
	button.Text = text
	Components.addCorner(button, UDim.new(0, 10))
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 18
	constraint.Parent = button
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = button
	return button
end

function FestivalsView.Mount()
	if activeTrove then
		return
	end
	local trove = Trove.new()
	activeTrove = trove

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Botão no menu lateral -------------------------------------------------
	local toggleGui = trove:Add(Instance.new("ScreenGui"))
	toggleGui.Name = "FestivalsToggleGui"
	toggleGui.ResetOnSpawn = false
	toggleGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets

	local toggleHolder = trove:Add(Components.makeFrame("FestivalsToggle"))
	local toggleScale = Instance.new("UIScale")
	toggleScale.Parent = toggleHolder

	local toggleButton = Components.makeButton("Button", Theme.Colors.Panel)
	toggleButton.Size = UDim2.fromScale(1, 1)
	Components.addCorner(toggleButton, UDim.new(0, 22))
	Components.addStroke(toggleButton, Theme.Colors.Accent, 3)
	toggleButton.Parent = toggleHolder

	local toggleLabel = Components.makeLabel("Label", Theme.Fonts.Display, Theme.Colors.Text, 20)
	toggleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	toggleLabel.Position = UDim2.fromScale(0.5, 0.42)
	toggleLabel.Size = UDim2.new(0.92, 0, 0, 26)
	toggleLabel.Text = "FESTIVAIS"
	Components.addStroke(toggleLabel, Theme.Colors.Background, 2)
	toggleLabel.Parent = toggleButton

	local toggleHint = Components.makeLabel("Hint", Theme.Fonts.Body, Theme.Colors.TextMuted, 16)
	toggleHint.AnchorPoint = Vector2.new(0.5, 0.5)
	toggleHint.Position = UDim2.fromScale(0.5, 0.76)
	toggleHint.Size = UDim2.new(0.8, 0, 0, 18)
	toggleHint.Text = "[G]"
	toggleHint.Visible = UserInputService.KeyboardEnabled
	toggleHint.Parent = toggleButton

	SideMenu.Attach(toggleHolder, 7)

	-- Painel ---------------------------------------------------------------
	local panelGui = trove:Add(Instance.new("ScreenGui"))
	panelGui.Name = "FestivalsPanelGui"
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
	Components.addStroke(panel, Theme.Colors.Accent, 3)
	panel.Parent = panelHolder
	local popScale = Instance.new("UIScale")
	popScale.Parent = panel

	local title = Components.makeLabel("Title", Theme.Fonts.Display, Theme.Colors.Gold, 30)
	title.Position = UDim2.fromOffset(20, 14)
	title.Size = UDim2.new(1, -100, 0, 36)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "FESTIVAIS DO SERVIDOR"
	title.Parent = panel

	local closeButton = textButton("Close", "X", Theme.Colors.Danger, UDim2.fromOffset(46, 46))
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -16, 0, 12)
	closeButton.Parent = panel

	-- Bónus sociais
	local bonusBox = Instance.new("Frame")
	bonusBox.Name = "Bonus"
	bonusBox.Position = UDim2.fromOffset(16, 62)
	bonusBox.Size = UDim2.new(1, -32, 0, 92)
	bonusBox.BackgroundColor3 = Theme.Colors.Background
	bonusBox.BorderSizePixel = 0
	Components.addCorner(bonusBox, UDim.new(0, 14))
	bonusBox.Parent = panel

	local bonusLabel = Components.makeLabel("Breakdown", Theme.Fonts.Body, Theme.Colors.Text, 17)
	bonusLabel.Position = UDim2.fromOffset(14, 8)
	bonusLabel.Size = UDim2.new(1, -28, 0, 22)
	bonusLabel.TextXAlignment = Enum.TextXAlignment.Left
	bonusLabel.Parent = bonusBox

	local totalLabel = Components.makeLabel("Total", Theme.Fonts.Display, Theme.Colors.Success, 22)
	totalLabel.Position = UDim2.fromOffset(14, 32)
	totalLabel.Size = UDim2.new(1, -28, 0, 26)
	totalLabel.TextXAlignment = Enum.TextXAlignment.Left
	totalLabel.Parent = bonusBox

	local headlinerLabel = Components.makeLabel("Headliner", Theme.Fonts.Body, Theme.Colors.Gold, 16)
	headlinerLabel.Position = UDim2.fromOffset(14, 62)
	headlinerLabel.Size = UDim2.new(1, -28, 0, 22)
	headlinerLabel.TextXAlignment = Enum.TextXAlignment.Left
	headlinerLabel.Parent = bonusBox

	-- Lista
	local list = Components.makeFrame("List")
	list.Position = UDim2.fromOffset(16, 166)
	list.Size = UDim2.new(1, -32, 1, -214)
	list.Parent = panel
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	local footer = Components.makeLabel("Footer", Theme.Fonts.Body, Theme.Colors.TextMuted, 14)
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.new(0, 20, 1, -14)
	footer.Size = UDim2.new(1, -40, 0, 20)
	footer.TextXAlignment = Enum.TextXAlignment.Left
	footer.Parent = panel

	local rows: { Row } = {}
	for slot = 1, MapConfig.Plots.Count do
		local frame = Instance.new("Frame")
		frame.Name = "Row" .. slot
		frame.LayoutOrder = slot
		frame.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		frame.BackgroundColor3 = Theme.Colors.Background
		frame.BorderSizePixel = 0
		frame.Visible = false
		Components.addCorner(frame, UDim.new(0, 12))
		frame.Parent = list

		local nameLabel = Components.makeLabel("Name", Theme.Fonts.Display, Theme.Colors.Text, 19)
		nameLabel.Position = UDim2.fromOffset(14, 6)
		nameLabel.Size = UDim2.new(1, -200, 0, 24)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = frame

		local infoLabel = Components.makeLabel("Info", Theme.Fonts.Body, Theme.Colors.TextMuted, 15)
		infoLabel.Position = UDim2.fromOffset(14, 34)
		infoLabel.Size = UDim2.new(1, -200, 0, 20)
		infoLabel.TextXAlignment = Enum.TextXAlignment.Left
		infoLabel.Parent = frame

		local button = textButton("Visit", "VISITAR", Theme.Colors.Success, UDim2.fromOffset(160, 46))
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -10, 0.5, 0)
		button.Parent = frame

		local row: Row = { Frame = frame, Name = nameLabel, Info = infoLabel, Button = button, PlotIndex = 0 }
		table.insert(rows, row)
		trove:Connect(button.Activated, function()
			if row.PlotIndex > 0 and SocialController.Visit(row.PlotIndex) then
				FestivalsView.Close()
			end
		end)
	end

	-- Atualização --------------------------------------------------------------
	local function refresh()
		if not isOpen then
			return
		end
		local sync = SocialController.Get()
		local headliner = SocialController.GetHeadliner()
		local now = Workspace:GetServerTimeNow()

		if sync then
			local friendsBonus = SocialCalc.GetFriendsBonus(sync.Friends)
			local groupText = if SocialConfig.Group.GroupId <= 0
				then "Grupo: —"
				elseif sync.InGroup then "Grupo: " .. percent(SocialCalc.GetGroupBonus(true))
				else "Grupo: entra no grupo (" .. percent(SocialConfig.Group.Bonus) .. ")"
			bonusLabel.Text = string.format(
				"Amigos aqui: %d (%s)   ·   %s   ·   ❤ Likes: %d (%s)",
				sync.Friends,
				percent(friendsBonus),
				groupText,
				sync.LikesReceived,
				percent(SocialCalc.GetLikesBonus(sync.LikesReceived))
			)
			totalLabel.Text = string.format("Bónus social total: ×%.2f de Hype", sync.Multiplier)
			footer.Text = string.format(
				"Likes dados hoje: %d/%d · 1 por festival por dia · Ganhas %d min de rendimento por Like",
				sync.GivenToday,
				SocialConfig.Likes.MaxGivenPerDay,
				SocialConfig.Likes.LikerReward.IncomeMinutes or 0
			)
		else
			bonusLabel.Text = "A carregar…"
			totalLabel.Text = ""
			footer.Text = ""
		end

		local headlinerConfig = SocialConfig.Headliner
		headlinerLabel.Text = if headliner.Active
			then string.format(
				"🎤 HEADLINER AO VIVO — Hype ×%g e energia ×%g · termina em %s",
				headlinerConfig.HypeMultiplier,
				headlinerConfig.EnergyMultiplier,
				formatCountdown(headliner.EndsAt - now)
			)
			else string.format(
				"🎤 Próximo Headliner em %s (Hype ×%g durante %d min)",
				formatCountdown(headliner.StartsAt - now),
				headlinerConfig.HypeMultiplier,
				headlinerConfig.Duration // 60
			)

		local festivals = SocialController.GetFestivals()
		for slot, row in rows do
			local festival = festivals[slot]
			row.Frame.Visible = festival ~= nil
			if festival then
				row.PlotIndex = festival.PlotIndex
				local def = MapCalc.GetStageDef(festival.StageTier)
				row.Name.Text = if festival.IsMine
					then "O teu festival"
					else "Festival de " .. festival.Player.DisplayName
				row.Info.Text = string.format(
					"Tier %d · %s · Era %s%s · ❤ %d%s",
					def.Tier,
					def.Name,
					def.Era,
					if festival.WorldTours > 0 then " · World Tour " .. festival.WorldTours else "",
					festival.Likes,
					if festival.LikedToday then " (já deste Like hoje)" else ""
				)
				row.Frame.BackgroundColor3 = if festival.IsMine then Theme.Colors.AccentDark else Theme.Colors.Background
				row.Button.Text = if festival.IsMine then "IR PARA O MEU" else "VISITAR"
				row.Button.BackgroundColor3 = if festival.IsMine then Theme.Colors.Highlight else Theme.Colors.Success
			end
		end
	end

	-- Abrir / fechar --------------------------------------------------------------
	local refreshThread: thread? = nil

	local function setOpen(open: boolean)
		if isOpen == open then
			return
		end
		isOpen = open
		if open then
			ModalManager.NotifyOpened("Festivals")
			overlay.Visible = true
			panelHolder.Visible = true
			popScale.Scale = 0.85
			TweenService:Create(popScale, Theme.Tween.Toast, { Scale = 1 }):Play()
			TweenService:Create(overlay, Theme.Tween.Fast, { BackgroundTransparency = Theme.Shop.OverlayTransparency }):Play()
			refresh()
			refreshThread = task.spawn(function()
				while isOpen do
					task.wait(1)
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
	ModalManager.Register("Festivals", function()
		setOpen(false)
	end)
	trove:Add(function()
		ModalManager.Unregister("Festivals")
		setOpenImpl = nil
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
		if not gameProcessed and input.KeyCode == TOGGLE_KEY then
			setOpen(not isOpen)
		end
	end)
	trove:Add(SocialController.Changed:Connect(function()
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
end


function FestivalsView.Open()
	local setOpen = setOpenImpl
	if setOpen then
		setOpen(true)
	end
end

function FestivalsView.Close()
	local setOpen = setOpenImpl
	if setOpen then
		setOpen(false)
	end
end

function FestivalsView.Unmount()
	local trove = activeTrove
	if trove then
		activeTrove = nil
		isOpen = false
		trove:Destroy()
	end
end

return FestivalsView
