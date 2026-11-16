--!strict
--[[
	SocialHudView
	Coluna no canto superior direito, por baixo do botão "★ VIP":
	  - Faixa do Headliner: "HEADLINER EM m:ss" nos últimos minutos antes do evento e
	    "HEADLINER AO VIVO · ×2 · m:ss" durante o evento (hora do servidor).
	  - Botão "❤ LIKE" quando a personagem está dentro do festival de outro jogador
	    (o servidor volta a validar a posição, o dia e o limite diário).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local SocialConfig = require(ReplicatedStorage.Shared.Config.Social)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)

local Client = script.Parent.Parent.Parent
local SocialController = require(Client.Controllers.SocialController)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)

local UPDATE_INTERVAL = 0.25
local COLUMN_TOP = 86 -- logo abaixo do botão VIP (12 + 64 + margem)

local SocialHudView = {}

local activeTrove: Trove.Trove? = nil

local function formatCountdown(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

function SocialHudView.Mount()
	if activeTrove then
		return
	end
	local trove = Trove.new()
	activeTrove = trove

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = trove:Add(Instance.new("ScreenGui"))
	gui.Name = "SocialHudGui"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = 3

	local column = Components.makeFrame("Column")
	column.AnchorPoint = Vector2.new(1, 0)
	column.Position = UDim2.new(1, -16, 0, COLUMN_TOP)
	column.Size = UDim2.fromOffset(260, 150)
	column.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = column
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = column

	-- Faixa do Headliner
	local banner = Instance.new("Frame")
	banner.Name = "Headliner"
	banner.LayoutOrder = 1
	banner.Size = UDim2.fromOffset(260, 56)
	banner.BackgroundColor3 = Theme.Colors.Panel
	banner.BorderSizePixel = 0
	banner.Visible = false
	Components.addCorner(banner, UDim.new(0, 14))
	local bannerStroke = Components.addStroke(banner, Theme.Colors.Gold, 2)
	banner.Parent = column

	local bannerTitle = Components.makeLabel("Title", Theme.Fonts.Display, Theme.Colors.Gold, 20)
	bannerTitle.Position = UDim2.fromOffset(10, 4)
	bannerTitle.Size = UDim2.new(1, -20, 0, 26)
	bannerTitle.Parent = banner

	local bannerSubtitle = Components.makeLabel("Subtitle", Theme.Fonts.Body, Theme.Colors.Text, 15)
	bannerSubtitle.Position = UDim2.fromOffset(10, 31)
	bannerSubtitle.Size = UDim2.new(1, -20, 0, 20)
	bannerSubtitle.Parent = banner

	local bannerScale = Instance.new("UIScale")
	bannerScale.Parent = banner

	-- Botão de Like
	local likeButton = Components.makeButton("Like", Theme.Colors.Accent)
	likeButton.LayoutOrder = 2
	likeButton.Size = UDim2.fromOffset(220, 62)
	likeButton.Visible = false
	Components.addCorner(likeButton, UDim.new(0, 16))
	Components.addStroke(likeButton, Theme.Colors.Text, 2)
	likeButton.Parent = column

	local likeTitle = Components.makeLabel("Title", Theme.Fonts.Display, Theme.Colors.Text, 24)
	likeTitle.Position = UDim2.fromOffset(8, 4)
	likeTitle.Size = UDim2.new(1, -16, 0, 30)
	likeTitle.Parent = likeButton

	local likeSubtitle = Components.makeLabel("Subtitle", Theme.Fonts.Body, Theme.Colors.Text, 14)
	likeSubtitle.Position = UDim2.fromOffset(8, 36)
	likeSubtitle.Size = UDim2.new(1, -16, 0, 20)
	likeSubtitle.Parent = likeButton

	local currentPlot: number? = nil
	local canLike = false
	local wasActive = false

	local function update()
		-- Headliner
		local state = SocialController.GetHeadliner()
		local now = Workspace:GetServerTimeNow()
		local config = SocialConfig.Headliner
		if state.Active then
			banner.Visible = true
			banner.BackgroundColor3 = Theme.Colors.Gold
			bannerStroke.Color = Theme.Colors.Text
			bannerTitle.TextColor3 = Theme.Colors.Background
			bannerSubtitle.TextColor3 = Theme.Colors.Background
			bannerTitle.Text = "🎤 HEADLINER AO VIVO"
			bannerSubtitle.Text = string.format(
				"Hype ×%g · energia ×%g · %s",
				config.HypeMultiplier,
				config.EnergyMultiplier,
				formatCountdown(state.EndsAt - now)
			)
			if not wasActive then
				bannerScale.Scale = 1.3
				TweenService:Create(bannerScale, TweenInfo.new(0.6, Enum.EasingStyle.Elastic), { Scale = 1 }):Play()
			end
		elseif state.StartsAt - now <= config.WarningSeconds then
			banner.Visible = true
			banner.BackgroundColor3 = Theme.Colors.Panel
			bannerStroke.Color = Theme.Colors.Gold
			bannerTitle.TextColor3 = Theme.Colors.Gold
			bannerSubtitle.TextColor3 = Theme.Colors.Text
			bannerTitle.Text = "🎤 HEADLINER EM " .. formatCountdown(state.StartsAt - now)
			bannerSubtitle.Text = string.format("Hype ×%g durante %d min!", config.HypeMultiplier, config.Duration // 60)
		else
			banner.Visible = false
		end
		wasActive = state.Active

		-- Like
		local index = SocialController.GetCurrentPlotIndex()
		local owner = if index then SocialController.GetPlotOwner(index) else nil
		if not index or not owner or owner == Players.LocalPlayer then
			likeButton.Visible = false
			currentPlot = nil
			canLike = false
			return
		end
		currentPlot = index
		local allowed, reason = SocialController.CanLike(owner)
		canLike = allowed
		likeButton.Visible = true
		likeButton.BackgroundColor3 = if allowed then Theme.Colors.Accent else Theme.Colors.Disabled
		likeTitle.Text = if allowed then "❤ LIKE" else (reason or "❤ LIKE")
		likeSubtitle.Text = "Festival de " .. owner.DisplayName
	end

	trove:Connect(likeButton.Activated, function()
		local index = currentPlot
		if not index then
			return
		end
		if canLike and SocialController.GiveLike(index) then
			likeButton.Rotation = -6
			TweenService:Create(likeButton, TweenInfo.new(0.4, Enum.EasingStyle.Elastic), { Rotation = 0 }):Play()
		else
			likeButton.Rotation = 5
			TweenService:Create(likeButton, TweenInfo.new(0.35, Enum.EasingStyle.Elastic), { Rotation = 0 }):Play()
		end
	end)

	trove:Add(SocialController.Changed:Connect(function()
		update()
	end))
	trove:Add(task.spawn(function()
		while true do
			update()
			task.wait(UPDATE_INTERVAL)
		end
	end))

	local function updateScale()
		local value = Components.computeScale(gui.AbsoluteSize)
		scale.Scale = value
		-- Acompanha a escala do botão VIP (12 + 64 de altura) para nunca se sobrepor
		column.Position = UDim2.new(1, -16, 0, 12 + (COLUMN_TOP - 12) * value)
	end
	trove:Connect(gui:GetPropertyChangedSignal("AbsoluteSize"), updateScale)

	gui.Parent = playerGui
	updateScale()
end

function SocialHudView.Unmount()
	local trove = activeTrove
	if trove then
		activeTrove = nil
		trove:Destroy()
	end
end

return SocialHudView
