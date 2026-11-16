--!strict
--[[
	MissionsView
	Painel "MISSÕES" com três separadores:
	  DIÁRIO   — os 7 dias da sequência (reclamado / hoje / futuro), estado e botão
	  MISSÕES  — 3 diárias + 2 semanais com barra de progresso, recompensa e RECLAMAR
	  CÓDIGOS  — caixa de texto + RESGATAR
	Botão no menu lateral (tecla M) com contador de recompensas por reclamar.
	Abre sozinho no DIÁRIO na primeira vez que há uma diária disponível na sessão.
	Os tempos usam Workspace:GetServerTimeNow() (o mesmo relógio Unix do servidor).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local RetentionConfig = require(ReplicatedStorage.Shared.Config.Retention)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local NumberFormatter = require(ReplicatedStorage.Shared.Util.NumberFormatter)
local RetentionCalc = require(ReplicatedStorage.Shared.Calc.RetentionCalc)

local Client = script.Parent.Parent.Parent
local RetentionController = require(Client.Controllers.RetentionController)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local ModalManager = require(script.Parent.Parent.ModalManager)
local SideMenu = require(script.Parent.Parent.SideMenu)

type RetentionSync = Types.RetentionSync
type MissionData = Types.MissionData

export type Tab = "Daily" | "Missions" | "Codes"

type DayCard = { Frame: Frame, Stroke: UIStroke, State: TextLabel }
type MissionCard = {
	Slot: string,
	Frame: Frame,
	Name: TextLabel,
	Description: TextLabel,
	Fill: Frame,
	Progress: TextLabel,
	Reward: TextLabel,
	Button: TextButton,
}

local PANEL_SIZE = Vector2.new(780, 560)
local HEADER = 64
local TOGGLE_KEY = Enum.KeyCode.M

local MissionsView = {}

local activeTrove: Trove.Trove? = nil
local setOpenImpl: ((boolean) -> ())? = nil
local setTabImpl: ((Tab) -> ())? = nil
local isOpen = false

local function serverNow(): number
	return Workspace:GetServerTimeNow()
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

local function formatDuration(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local days = s // 86400
	local hours = (s % 86400) // 3600
	local minutes = (s % 3600) // 60
	if days > 0 then
		return string.format("%dd %dh", days, hours)
	end
	return string.format("%dh %02dm", hours, minutes)
end

-- Recompensas por reclamar (diário + missões completas)
local function countClaimable(sync: RetentionSync): number
	local count = if RetentionCalc.GetDailyStatus(sync.Daily, serverNow()).CanClaim then 1 else 0
	for _, list in { sync.Missions.Daily, sync.Missions.Weekly } do
		for _, mission in list do
			local def = RetentionConfig.MissionById[mission.Id]
			if def and not mission.Claimed and mission.Progress >= def.Target then
				count += 1
			end
		end
	end
	return count
end

-- Usado pelo posto MISSÕES no terreno (subtítulo "N por reclamar")
MissionsView.CountClaimable = countClaimable

function MissionsView.Mount()
	if activeTrove then
		return
	end
	local trove = Trove.new()
	activeTrove = trove

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Botão no menu lateral -------------------------------------------------
	local toggleGui = trove:Add(Instance.new("ScreenGui"))
	toggleGui.Name = "MissionsToggleGui"
	toggleGui.ResetOnSpawn = false
	toggleGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets

	local toggleHolder = trove:Add(Components.makeFrame("MissionsToggle"))
	local toggleScale = Instance.new("UIScale")
	toggleScale.Parent = toggleHolder

	local toggleButton = Components.makeButton("Button", Theme.Colors.Panel)
	toggleButton.Size = UDim2.fromScale(1, 1)
	Components.addCorner(toggleButton, UDim.new(0, 22))
	Components.addStroke(toggleButton, Theme.Colors.Success, 3)
	toggleButton.Parent = toggleHolder

	local toggleLabel = Components.makeLabel("Label", Theme.Fonts.Display, Theme.Colors.Text, 22)
	toggleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	toggleLabel.Position = UDim2.fromScale(0.5, 0.42)
	toggleLabel.Size = UDim2.new(0.9, 0, 0, 28)
	toggleLabel.Text = "MISSÕES"
	Components.addStroke(toggleLabel, Theme.Colors.Background, 2)
	toggleLabel.Parent = toggleButton

	local toggleHint = Components.makeLabel("Hint", Theme.Fonts.Body, Theme.Colors.TextMuted, 16)
	toggleHint.AnchorPoint = Vector2.new(0.5, 0.5)
	toggleHint.Position = UDim2.fromScale(0.5, 0.76)
	toggleHint.Size = UDim2.new(0.8, 0, 0, 18)
	toggleHint.Text = "[M]"
	toggleHint.Visible = UserInputService.KeyboardEnabled
	toggleHint.Parent = toggleButton

	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.new(1, -8, 0, 8)
	badge.Size = UDim2.fromOffset(30, 30)
	badge.BackgroundColor3 = Theme.Colors.Danger
	badge.Font = Theme.Fonts.Display
	badge.TextColor3 = Theme.Colors.Text
	badge.TextScaled = true
	badge.Visible = false
	badge.ZIndex = 3
	Components.addCorner(badge, UDim.new(1, 0))
	badge.Parent = toggleHolder

	SideMenu.Attach(toggleHolder, 6)

	-- Painel ---------------------------------------------------------------
	local panelGui = trove:Add(Instance.new("ScreenGui"))
	panelGui.Name = "MissionsPanelGui"
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
	Components.addStroke(panel, Theme.Colors.Success, 3)
	panel.Parent = panelHolder

	local popScale = Instance.new("UIScale")
	popScale.Parent = panel

	local closeButton = textButton("Close", "X", Theme.Colors.Danger, UDim2.fromOffset(46, 46))
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -16, 0, 12)
	closeButton.Parent = panel

	local tabBar = Components.makeFrame("Tabs")
	tabBar.Position = UDim2.fromOffset(20, 12)
	tabBar.Size = UDim2.new(1, -100, 0, 46)
	tabBar.Parent = panel
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabBar

	local tabButtons: { [Tab]: TextButton } = {
		Daily = textButton("Daily", "DIÁRIO", Theme.Colors.Background, UDim2.new(1 / 3, -6, 1, 0)),
		Missions = textButton("Missions", "MISSÕES", Theme.Colors.Background, UDim2.new(1 / 3, -6, 1, 0)),
		Codes = textButton("Codes", "CÓDIGOS", Theme.Colors.Background, UDim2.new(1 / 3, -6, 1, 0)),
	}
	tabButtons.Daily.LayoutOrder = 1
	tabButtons.Missions.LayoutOrder = 2
	tabButtons.Codes.LayoutOrder = 3
	for _, button in tabButtons do
		button.Parent = tabBar
	end

	local function makePage(name: string): Frame
		local page = Components.makeFrame(name)
		page.Position = UDim2.fromOffset(0, HEADER)
		page.Size = UDim2.new(1, 0, 1, -HEADER)
		page.Visible = false
		page.Parent = panel
		return page
	end
	local dailyPage = makePage("DailyPage")
	local missionsPage = makePage("MissionsPage")
	local codesPage = makePage("CodesPage")

	-- ======================= DIÁRIO =======================
	local dailyTitle = Components.makeLabel("Title", Theme.Fonts.Display, Theme.Colors.Gold, 26)
	dailyTitle.Position = UDim2.fromOffset(20, 6)
	dailyTitle.Size = UDim2.new(1, -40, 0, 32)
	dailyTitle.Text = "RECOMPENSA DIÁRIA — 7 DIAS"
	dailyTitle.Parent = dailyPage

	local dayRow = Components.makeFrame("Days")
	dayRow.Position = UDim2.fromOffset(16, 48)
	dayRow.Size = UDim2.new(1, -32, 0, 210)
	dayRow.Parent = dailyPage
	local dayLayout = Instance.new("UIListLayout")
	dayLayout.FillDirection = Enum.FillDirection.Horizontal
	dayLayout.Padding = UDim.new(0, 8)
	dayLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dayLayout.SortOrder = Enum.SortOrder.LayoutOrder
	dayLayout.Parent = dayRow

	local dayCards: { DayCard } = {}
	for day, reward in RetentionConfig.DailyRewards do
		local frame = Instance.new("Frame")
		frame.Name = "Day" .. day
		frame.LayoutOrder = day
		frame.Size = UDim2.fromOffset(98, 210)
		frame.BackgroundColor3 = Theme.Colors.Background
		frame.BorderSizePixel = 0
		Components.addCorner(frame, UDim.new(0, 12))
		local stroke = Components.addStroke(frame, if day == 7 then Theme.Colors.Gold else Theme.Colors.AccentDark, 2)
		frame.Parent = dayRow

		local dayLabel = Components.makeLabel("Day", Theme.Fonts.Display, if day == 7 then Theme.Colors.Gold else Theme.Colors.Text, 22)
		dayLabel.Position = UDim2.fromOffset(4, 8)
		dayLabel.Size = UDim2.new(1, -8, 0, 26)
		dayLabel.Text = "DIA " .. day
		dayLabel.Parent = frame

		local rewardLabel = wrapLabel("Reward", Theme.Fonts.Body, Theme.Colors.TextMuted, 13)
		rewardLabel.TextXAlignment = Enum.TextXAlignment.Center
		rewardLabel.Position = UDim2.fromOffset(6, 40)
		rewardLabel.Size = UDim2.new(1, -12, 0, 120)
		rewardLabel.Text = RetentionCalc.DescribeReward(reward)
		rewardLabel.Parent = frame

		local stateLabel = Components.makeLabel("State", Theme.Fonts.Display, Theme.Colors.TextMuted, 18)
		stateLabel.Position = UDim2.new(0, 4, 1, -34)
		stateLabel.Size = UDim2.new(1, -8, 0, 26)
		stateLabel.Parent = frame

		table.insert(dayCards, { Frame = frame, Stroke = stroke, State = stateLabel })
	end

	local dailyStatus = Components.makeLabel("Status", Theme.Fonts.Body, Theme.Colors.Text, 18)
	dailyStatus.Position = UDim2.fromOffset(20, 272)
	dailyStatus.Size = UDim2.new(1, -40, 0, 24)
	dailyStatus.Parent = dailyPage

	local dailyRules = Components.makeLabel("Rules", Theme.Fonts.Body, Theme.Colors.TextMuted, 14)
	dailyRules.Position = UDim2.fromOffset(20, 300)
	dailyRules.Size = UDim2.new(1, -40, 0, 20)
	dailyRules.Text = "Reclama de 20 em 20 h. Se passares mais de 48 h sem reclamar, a sequência volta ao dia 1."
	dailyRules.Parent = dailyPage

	local claimDailyButton = textButton("ClaimDaily", "RECLAMAR", Theme.Colors.Success, UDim2.fromOffset(320, 64))
	claimDailyButton.AnchorPoint = Vector2.new(0.5, 1)
	claimDailyButton.Position = UDim2.new(0.5, 0, 1, -24)
	claimDailyButton.Parent = dailyPage

	-- ======================= MISSÕES =======================
	local missionsList = Components.makeFrame("List")
	missionsList.Position = UDim2.fromOffset(16, 4)
	missionsList.Size = UDim2.new(1, -32, 1, -12)
	missionsList.Parent = missionsPage
	local missionsLayout = Instance.new("UIListLayout")
	missionsLayout.Padding = UDim.new(0, 6)
	missionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	missionsLayout.Parent = missionsList

	local dailyHeader = Components.makeLabel("DailyHeader", Theme.Fonts.Display, Theme.Colors.Highlight, 18)
	dailyHeader.LayoutOrder = 0
	dailyHeader.Size = UDim2.new(1, 0, 0, 22)
	dailyHeader.TextXAlignment = Enum.TextXAlignment.Left
	dailyHeader.Parent = missionsList

	local weeklyHeader = Components.makeLabel("WeeklyHeader", Theme.Fonts.Display, Theme.Colors.Gold, 18)
	weeklyHeader.LayoutOrder = 10
	weeklyHeader.Size = UDim2.new(1, 0, 0, 22)
	weeklyHeader.TextXAlignment = Enum.TextXAlignment.Left
	weeklyHeader.Parent = missionsList

	local missionCards: { MissionCard } = {}
	local function buildMissionCard(slot: string, order: number)
		local frame = Instance.new("Frame")
		frame.Name = slot
		frame.LayoutOrder = order
		frame.Size = UDim2.new(1, 0, 0, 72)
		frame.BackgroundColor3 = Theme.Colors.Background
		frame.BorderSizePixel = 0
		Components.addCorner(frame, UDim.new(0, 12))
		frame.Parent = missionsList

		local nameLabel = Components.makeLabel("Name", Theme.Fonts.Display, Theme.Colors.Text, 17)
		nameLabel.Position = UDim2.fromOffset(12, 6)
		nameLabel.Size = UDim2.new(0.42, 0, 0, 20)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = frame

		local description = Components.makeLabel("Description", Theme.Fonts.Body, Theme.Colors.TextMuted, 14)
		description.Position = UDim2.fromOffset(12, 28)
		description.Size = UDim2.new(0.42, 0, 0, 16)
		description.TextXAlignment = Enum.TextXAlignment.Left
		description.Parent = frame

		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.Position = UDim2.fromOffset(12, 50)
		bar.Size = UDim2.new(0.42, 0, 0, 12)
		bar.BackgroundColor3 = Theme.Colors.Panel
		bar.BorderSizePixel = 0
		bar.ClipsDescendants = true
		Components.addCorner(bar, UDim.new(1, 0))
		bar.Parent = frame

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = Theme.Colors.Success
		fill.BorderSizePixel = 0
		Components.addCorner(fill, UDim.new(1, 0))
		fill.Parent = bar

		local progress = Components.makeLabel("Progress", Theme.Fonts.Body, Theme.Colors.Text, 14)
		progress.Position = UDim2.new(0.42, 20, 0, 6)
		progress.Size = UDim2.new(0.18, 0, 0, 20)
		progress.Parent = frame

		local reward = wrapLabel("Reward", Theme.Fonts.Body, Theme.Colors.Gold, 13)
		reward.Position = UDim2.new(0.42, 20, 0, 28)
		reward.Size = UDim2.new(0.58, -190, 0, 40)
		reward.Parent = frame

		local button = textButton("Claim", "RECLAMAR", Theme.Colors.Disabled, UDim2.fromOffset(150, 48))
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -10, 0.5, 0)
		button.Parent = frame

		trove:Connect(button.Activated, function()
			if button.BackgroundColor3 == Theme.Colors.Success then
				RetentionController.ClaimMission(slot)
			end
		end)

		table.insert(missionCards, {
			Slot = slot,
			Frame = frame,
			Name = nameLabel,
			Description = description,
			Fill = fill,
			Progress = progress,
			Reward = reward,
			Button = button,
		})
	end
	for index = 1, RetentionConfig.DailyMissionCount do
		buildMissionCard("D" .. index, index)
	end
	for index = 1, RetentionConfig.WeeklyMissionCount do
		buildMissionCard("W" .. index, 10 + index)
	end

	-- ======================= CÓDIGOS =======================
	local codesTitle = Components.makeLabel("Title", Theme.Fonts.Display, Theme.Colors.Gold, 26)
	codesTitle.Position = UDim2.fromOffset(20, 30)
	codesTitle.Size = UDim2.new(1, -40, 0, 32)
	codesTitle.Text = "TENS UM CÓDIGO?"
	codesTitle.Parent = codesPage

	local codeBox = Instance.new("TextBox")
	codeBox.Name = "CodeBox"
	codeBox.AnchorPoint = Vector2.new(0.5, 0)
	codeBox.Position = UDim2.new(0.5, 0, 0, 90)
	codeBox.Size = UDim2.fromOffset(420, 60)
	codeBox.BackgroundColor3 = Theme.Colors.Background
	codeBox.Font = Theme.Fonts.Display
	codeBox.TextColor3 = Theme.Colors.Text
	codeBox.PlaceholderText = "ESCREVE O CÓDIGO"
	codeBox.PlaceholderColor3 = Theme.Colors.TextMuted
	codeBox.TextScaled = true
	codeBox.ClearTextOnFocus = false
	codeBox.Text = ""
	Components.addCorner(codeBox, UDim.new(0, 12))
	Components.addStroke(codeBox, Theme.Colors.Gold, 2)
	local boxPadding = Instance.new("UIPadding")
	boxPadding.PaddingLeft = UDim.new(0, 12)
	boxPadding.PaddingRight = UDim.new(0, 12)
	boxPadding.PaddingTop = UDim.new(0, 10)
	boxPadding.PaddingBottom = UDim.new(0, 10)
	boxPadding.Parent = codeBox
	codeBox.Parent = codesPage

	local redeemButton = textButton("Redeem", "RESGATAR", Theme.Colors.Success, UDim2.fromOffset(260, 60))
	redeemButton.AnchorPoint = Vector2.new(0.5, 0)
	redeemButton.Position = UDim2.new(0.5, 0, 0, 168)
	redeemButton.Parent = codesPage

	local codesHint = Components.makeLabel("Hint", Theme.Fonts.Body, Theme.Colors.TextMuted, 15)
	codesHint.Position = UDim2.fromOffset(20, 246)
	codesHint.Size = UDim2.new(1, -40, 0, 20)
	codesHint.Text = "Cada código só pode ser usado uma vez. O resultado aparece no ecrã."
	codesHint.Parent = codesPage

	trove:Connect(redeemButton.Activated, function()
		if RetentionController.RedeemCode(codeBox.Text) then
			codeBox.Text = ""
		else
			redeemButton.Rotation = 5
			TweenService:Create(redeemButton, TweenInfo.new(0.35, Enum.EasingStyle.Elastic), { Rotation = 0 }):Play()
		end
	end)

	-- Atualização --------------------------------------------------------------
	local currentTab: Tab = "Daily"

	local function refresh()
		local sync = RetentionController.Get()
		if not sync then
			return
		end
		local claimable = countClaimable(sync)
		badge.Visible = claimable > 0
		badge.Text = tostring(claimable)
		if not isOpen then
			return
		end
		local now = serverNow()

		if currentTab == "Daily" then
			local status = RetentionCalc.GetDailyStatus(sync.Daily, now)
			local claimedUpTo = if status.NextDay == 1 then 0 else status.NextDay - 1
			if not status.CanClaim then
				claimedUpTo = sync.Daily.Streak
			end
			for day, card in dayCards do
				if day <= claimedUpTo then
					card.State.Text = "✓"
					card.State.TextColor3 = Theme.Colors.Success
					card.Frame.BackgroundColor3 = Theme.Colors.Panel
				elseif day == status.NextDay and status.CanClaim then
					card.State.Text = "HOJE"
					card.State.TextColor3 = Theme.Colors.Gold
					card.Frame.BackgroundColor3 = Theme.Colors.AccentDark
				else
					card.State.Text = "—"
					card.State.TextColor3 = Theme.Colors.TextMuted
					card.Frame.BackgroundColor3 = Theme.Colors.Background
				end
			end
			if status.CanClaim then
				dailyStatus.Text = (if status.StreakLost then "A sequência foi perdida — recomeça no dia 1. " else "")
					.. "Dia " .. status.NextDay .. " pronto a reclamar!"
				claimDailyButton.BackgroundColor3 = Theme.Colors.Success
				claimDailyButton.Text = "RECLAMAR DIA " .. status.NextDay
			else
				dailyStatus.Text = "Próxima recompensa em " .. formatDuration(status.SecondsUntilClaim)
				claimDailyButton.BackgroundColor3 = Theme.Colors.Disabled
				claimDailyButton.Text = "VOLTA MAIS TARDE"
			end
		elseif currentTab == "Missions" then
			dailyHeader.Text = "DIÁRIAS · reiniciam em " .. formatDuration(RetentionCalc.SecondsUntilDailyReset(now))
			weeklyHeader.Text = "SEMANAIS · reiniciam em " .. formatDuration(RetentionCalc.SecondsUntilWeeklyReset(now))
			for _, card in missionCards do
				local kind = string.sub(card.Slot, 1, 1)
				local index = tonumber(string.sub(card.Slot, 2)) or 0
				local list: { MissionData } = if kind == "D" then sync.Missions.Daily else sync.Missions.Weekly
				local mission = list[index]
				local def = if mission then RetentionConfig.MissionById[mission.Id] else nil
				card.Frame.Visible = def ~= nil
				if mission and def then
					local ratio = math.clamp(mission.Progress / def.Target, 0, 1)
					card.Name.Text = def.Name
					card.Description.Text = def.Description
					card.Fill.Size = UDim2.fromScale(ratio, 1)
					card.Progress.Text = string.format(
						"%s / %s",
						NumberFormatter.formatInteger(mission.Progress),
						NumberFormatter.formatInteger(def.Target)
					)
					card.Reward.Text = "Recompensa: " .. RetentionCalc.DescribeReward(def.Reward)
					if mission.Claimed then
						card.Button.Text = "✓ RECLAMADA"
						card.Button.BackgroundColor3 = Theme.Colors.AccentDark
					elseif ratio >= 1 then
						card.Button.Text = "RECLAMAR"
						card.Button.BackgroundColor3 = Theme.Colors.Success
					else
						card.Button.Text = "EM CURSO"
						card.Button.BackgroundColor3 = Theme.Colors.Disabled
					end
				end
			end
		end
	end

	trove:Connect(claimDailyButton.Activated, function()
		if claimDailyButton.BackgroundColor3 == Theme.Colors.Success then
			RetentionController.ClaimDaily()
		end
	end)

	-- Abrir / fechar --------------------------------------------------------------
	local refreshThread: thread? = nil

	local function setTab(tab: Tab)
		currentTab = tab
		dailyPage.Visible = tab == "Daily"
		missionsPage.Visible = tab == "Missions"
		codesPage.Visible = tab == "Codes"
		for name, button in tabButtons do
			button.BackgroundColor3 = if name == tab then Theme.Colors.Accent else Theme.Colors.Background
		end
		refresh()
	end
	setTabImpl = setTab

	local function setOpen(open: boolean)
		if isOpen == open then
			return
		end
		isOpen = open
		if open then
			ModalManager.NotifyOpened("Missions")
			overlay.Visible = true
			panelHolder.Visible = true
			popScale.Scale = 0.85
			TweenService:Create(popScale, Theme.Tween.Toast, { Scale = 1 }):Play()
			TweenService:Create(overlay, Theme.Tween.Fast, { BackgroundTransparency = Theme.Shop.OverlayTransparency }):Play()
			setTab(currentTab)
			-- Contagens decrescentes enquanto aberto
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
	ModalManager.Register("Missions", function()
		setOpen(false)
	end)
	trove:Add(function()
		ModalManager.Unregister("Missions")
		local thread = refreshThread
		if thread and coroutine.status(thread) == "suspended" then
			task.cancel(thread)
		end
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

	local autoOpened = false
	trove:Add(RetentionController.Changed:Connect(function(sync: RetentionSync)
		refresh()
		-- Primeira sincronização da sessão com diária disponível: abre no DIÁRIO
		if not autoOpened then
			autoOpened = true
			if RetentionCalc.GetDailyStatus(sync.Daily, serverNow()).CanClaim then
				task.delay(2, function()
					if not isOpen then
						setTab("Daily")
						setOpen(true)
					end
				end)
			end
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
	setTab("Daily")
end

function MissionsView.Open(tab: Tab?)
	local setTab = setTabImpl
	if tab and setTab then
		setTab(tab)
	end
	local setOpen = setOpenImpl
	if setOpen then
		setOpen(true)
	end
end

return MissionsView
