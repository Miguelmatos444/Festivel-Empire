--!strict
--[[
	ReturnView
	Botão "VOLTAR AO MEU FESTIVAL" por cima do botão LOJA.
	Só aparece quando a personagem está a mais de Config/Map.ReturnButtonDistance
	do centro do próprio terreno (verificado 2x por segundo, não a cada frame).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MapConfig = require(ReplicatedStorage.Shared.Config.Map)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)

local Client = script.Parent.Parent.Parent
local PlotController = require(Client.Controllers.PlotController)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)

local CHECK_INTERVAL = 0.5

local ReturnView = {}

local activeTrove: Trove.Trove? = nil

function ReturnView.Mount()
	if activeTrove then
		return
	end
	local trove = Trove.new()
	activeTrove = trove

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screenGui = trove:Add(Instance.new("ScreenGui"))
	screenGui.Name = "ReturnGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	screenGui.DisplayOrder = 1

	local holder = Components.makeFrame("ReturnHolder")
	holder.AnchorPoint = Vector2.new(0, 0.5)
	holder.Position = UDim2.new(0, 16, 0.5, -128)
	holder.Size = UDim2.fromOffset(112, 100)
	holder.Visible = false
	holder.Parent = screenGui

	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local button = Components.makeButton("Button", Theme.Colors.Panel)
	button.Size = UDim2.fromScale(1, 1)
	Components.addCorner(button, UDim.new(0, 20))
	Components.addStroke(button, Theme.Colors.Gold, 3)
	button.Parent = holder

	local label = Components.makeLabel("Label", Theme.Fonts.Display, Theme.Colors.Text, 20)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.new(1, -14, 1, -14)
	label.TextWrapped = true
	label.Text = "VOLTAR AO MEU FESTIVAL"
	Components.addStroke(label, Theme.Colors.Background, 1.5)
	label.Parent = button

	trove:Connect(button.Activated, function()
		if PlotController.RequestReturn() then
			button.BackgroundColor3 = Theme.Colors.Gold
			TweenService:Create(button, Theme.Tween.Ring, { BackgroundColor3 = Theme.Colors.Panel }):Play()
		end
	end)

	local function updateScale()
		scale.Scale = Components.computeScale(screenGui.AbsoluteSize)
	end
	trove:Connect(screenGui:GetPropertyChangedSignal("AbsoluteSize"), updateScale)

	trove:Add(task.spawn(function()
		while true do
			local distance = PlotController.GetDistanceFromMyPlot()
			holder.Visible = distance ~= nil and distance > MapConfig.ReturnButtonDistance
			task.wait(CHECK_INTERVAL)
		end
	end))

	screenGui.Parent = playerGui
	updateScale()
end

function ReturnView.Unmount()
	local trove = activeTrove
	if trove then
		activeTrove = nil
		trove:Destroy()
	end
end

return ReturnView
