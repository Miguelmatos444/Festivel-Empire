--!strict
--[[
	VipButtonView
	Botão dourado "★ VIP" sempre visível no canto superior direito (fora da coluna
	do SideMenu e acima da barra de drop). Abre a LOJA diretamente no separador VIP
	(Gamepasses + pacotes). Tecla V.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local ShopView = require(script.Parent.ShopView)
local Trove = require(game:GetService("ReplicatedStorage").Shared.Util.Trove)

local TOGGLE_KEY = Enum.KeyCode.V

local VipButtonView = {}

local activeTrove: Trove.Trove? = nil

function VipButtonView.Mount()
	if activeTrove then
		return
	end
	local trove = Trove.new()
	activeTrove = trove

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = trove:Add(Instance.new("ScreenGui"))
	gui.Name = "VipButtonGui"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = 3

	local holder = Components.makeFrame("Holder")
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.Position = UDim2.new(1, -16, 0, 12)
	holder.Size = UDim2.fromOffset(150, 64)
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local button = Components.makeButton("Vip", Theme.Colors.Gold)
	button.Size = UDim2.fromScale(1, 1)
	button.Font = Theme.Fonts.Display
	button.TextColor3 = Theme.Colors.Background
	button.TextSize = 30
	button.Text = "★ VIP"
	Components.addCorner(button, UDim.new(0, 16))
	Components.addStroke(button, Theme.Colors.Text, 3)
	button.Parent = holder

	-- Brilho a pulsar para chamar a atenção
	local pulse = Instance.new("UIScale")
	pulse.Parent = button
	local pulseTween = TweenService:Create(
		pulse,
		TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Scale = 1.06 }
	)
	pulseTween:Play()
	trove:Add(function()
		pulseTween:Cancel()
	end)

	local function open()
		if ShopView.IsOpen() then
			ShopView.Close()
		else
			ShopView.Open("Vip")
		end
	end
	trove:Connect(button.Activated, open)
	trove:Connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if not gameProcessed and input.KeyCode == TOGGLE_KEY then
			open()
		end
	end)

	local function updateScale()
		scale.Scale = Components.computeScale(gui.AbsoluteSize)
	end
	trove:Connect(gui:GetPropertyChangedSignal("AbsoluteSize"), updateScale)

	gui.Parent = playerGui
	updateScale()
end

function VipButtonView.Unmount()
	local trove = activeTrove
	if trove then
		activeTrove = nil
		trove:Destroy()
	end
end

return VipButtonView
