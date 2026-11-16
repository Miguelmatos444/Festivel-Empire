--!strict
--[[
	WelcomeBackView
	Painel "BEM-VINDO DE VOLTA" com o tempo fora e o Hype ganho offline
	(o cálculo é feito no servidor; aqui só se mostra o aviso OfflineEarnings).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Types = require(ReplicatedStorage.Shared.Types)
local BigNum = require(ReplicatedStorage.Shared.Util.BigNum)
local NumberFormatter = require(ReplicatedStorage.Shared.Util.NumberFormatter)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)

local Client = script.Parent.Parent.Parent
local StateController = require(Client.Controllers.StateController)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)

local PANEL_SIZE = Vector2.new(460, 280)

local WelcomeBackView = {}

local activeTrove: Trove.Trove? = nil

function WelcomeBackView.Mount()
	if activeTrove then
		return
	end
	local trove = Trove.new()
	activeTrove = trove

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = trove:Add(Instance.new("ScreenGui"))
	gui.Name = "WelcomeBackGui"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.DisplayOrder = 15
	gui.Enabled = false

	local overlay = Components.makeButton("Overlay", Theme.Colors.Overlay)
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundTransparency = 0.5
	overlay.Parent = gui

	local holder = Components.makeFrame("Holder")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y)
	holder.Parent = gui
	local fitScale = Instance.new("UIScale")
	fitScale.Parent = holder

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.BorderSizePixel = 0
	panel.Active = true
	Components.addCorner(panel, UDim.new(0, 20))
	Components.addStroke(panel, Theme.Colors.Gold, 3)
	panel.Parent = holder
	local popScale = Instance.new("UIScale")
	popScale.Parent = panel

	local title = Components.makeLabel("Title", Theme.Fonts.Display, Theme.Colors.Gold, 32)
	title.Position = UDim2.fromOffset(20, 18)
	title.Size = UDim2.new(1, -40, 0, 38)
	title.Text = "BEM-VINDO DE VOLTA!"
	Components.addStroke(title, Theme.Colors.Background, 2)
	title.Parent = panel

	local timeLabel = Components.makeLabel("Time", Theme.Fonts.Body, Theme.Colors.TextMuted, 18)
	timeLabel.Position = UDim2.fromOffset(20, 64)
	timeLabel.Size = UDim2.new(1, -40, 0, 22)
	timeLabel.Parent = panel

	local amountLabel = Components.makeLabel("Amount", Theme.Fonts.Display, Theme.Colors.Text, 44)
	amountLabel.Position = UDim2.fromOffset(20, 96)
	amountLabel.Size = UDim2.new(1, -40, 0, 56)
	Components.addStroke(amountLabel, Theme.Colors.Background, 2)
	amountLabel.Parent = panel

	local okButton = Components.makeButton("Ok", Theme.Colors.Success)
	okButton.AnchorPoint = Vector2.new(0.5, 1)
	okButton.Position = UDim2.new(0.5, 0, 1, -20)
	okButton.Size = UDim2.fromOffset(220, 56)
	okButton.Font = Theme.Fonts.Display
	okButton.TextColor3 = Theme.Colors.Text
	okButton.TextSize = 26
	okButton.Text = "BOA!"
	Components.addCorner(okButton, UDim.new(0, 14))
	okButton.Parent = panel

	local function close()
		gui.Enabled = false
	end
	trove:Connect(okButton.Activated, close)
	trove:Connect(overlay.Activated, close)

	trove:Add(StateController.NoticeReceived:Connect(function(notice: Types.Notice)
		if notice.Kind ~= "OfflineEarnings" then
			return
		end
		timeLabel.Text = "O teu festival continuou a tocar durante " .. NumberFormatter.formatTime(notice.Seconds)
		amountLabel.Text = "+" .. NumberFormatter.format(BigNum.deserialize(notice.Amount)) .. " Hype"
		gui.Enabled = true
		popScale.Scale = 0.6
		TweenService:Create(popScale, Theme.Tween.Toast, { Scale = 1 }):Play()
	end))

	local function updateScale()
		fitScale.Scale = Components.fitScale(gui.AbsoluteSize, PANEL_SIZE, 0.9)
	end
	trove:Connect(gui:GetPropertyChangedSignal("AbsoluteSize"), updateScale)

	gui.Parent = playerGui
	updateScale()
end

return WelcomeBackView
