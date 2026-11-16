--!strict
--[[
	DropBarView
	HUD do Bass Drop:
	  - coluna à direita: barra de energia, fase, boost ativo e botões das máquinas
	    (tocar = armar/desarmar; máquina bloqueada abre a loja no separador PIROTECNIA)
	  - centro: botão gigante DROP! com anel de aproximação que fecha no instante do drop
	  - resultado: "PERFEITO! 34x" + sinergias
	Tecla F / R1 do comando também disparam o DROP!.
	Tudo pulsa com AudioController.GetIntensity() (música ou relógio de BPM).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local BassDropConfig = require(ReplicatedStorage.Shared.Config.BassDrop)
local PyroConfig = require(ReplicatedStorage.Shared.Config.Pyro)
local NumberFormatter = require(ReplicatedStorage.Shared.Util.NumberFormatter)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local DropCalc = require(ReplicatedStorage.Shared.Calc.DropCalc)

local Client = script.Parent.Parent.Parent
local BassDropController = require(Client.Controllers.BassDropController)
local AudioController = require(Client.Controllers.AudioController)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local ShopView = require(script.Parent.ShopView)

type DropState = Types.DropState
type DropResolved = Types.DropResolved
type DropGrade = Types.DropGrade
type PyroDef = Types.PyroDef

type PyroButton = {
	Def: PyroDef,
	Button: TextButton,
	Stroke: UIStroke,
	NameLabel: TextLabel,
	StatusLabel: TextLabel,
	Cooldown: Frame,
}

local BAR_HEIGHT = 300
local PRESS_FEEDBACK_TIME = 0.12

local DropBarView = {}

local activeTrove: Trove.Trove? = nil

local function setText(label: TextLabel, text: string)
	if label.Text ~= text then
		label.Text = text
	end
end

local function gradeColor(grade: DropGrade?): Color3
	if grade == "Perfect" then
		return Theme.Colors.Gold
	elseif grade == "Great" then
		return Theme.Colors.Highlight
	elseif grade == "Good" then
		return Theme.Colors.Text
	end
	return Theme.Colors.TextMuted
end

function DropBarView.Mount()
	if activeTrove then
		return
	end
	local trove = Trove.new()
	activeTrove = trove

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local dropSize = Theme.DropBar.DropButtonSize

	local screenGui = trove:Add(Instance.new("ScreenGui"))
	screenGui.Name = "DropGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	screenGui.DisplayOrder = 2

	-- Coluna direita ---------------------------------------------------------
	local column = Components.makeFrame("DropColumn")
	column.AnchorPoint = Vector2.new(1, 0.5)
	column.Position = UDim2.new(1, -16, 0.5, 0)
	column.Size = UDim2.fromOffset(Theme.DropBar.ColumnSize.X, Theme.DropBar.ColumnSize.Y)
	column.Parent = screenGui

	local columnScale = Instance.new("UIScale")
	columnScale.Parent = column

	local energyLabel = Components.makeLabel("Energy", Theme.Fonts.Display, Theme.Colors.Text, 24)
	energyLabel.AnchorPoint = Vector2.new(1, 0)
	energyLabel.Position = UDim2.new(1, 0, 0, 0)
	energyLabel.Size = UDim2.fromOffset(64, 30)
	energyLabel.Text = "0%"
	Components.addStroke(energyLabel, Theme.Colors.Background, 2)
	energyLabel.Parent = column

	local barBack = Instance.new("Frame")
	barBack.Name = "EnergyBar"
	barBack.AnchorPoint = Vector2.new(1, 0)
	barBack.Position = UDim2.new(1, -6, 0, 36)
	barBack.Size = UDim2.fromOffset(52, BAR_HEIGHT)
	barBack.BackgroundColor3 = Theme.Colors.Panel
	barBack.BorderSizePixel = 0
	barBack.ClipsDescendants = true
	Components.addCorner(barBack, UDim.new(0, 14))
	local barStroke = Components.addStroke(barBack, Theme.Colors.Highlight, 2)
	barBack.Parent = column

	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.AnchorPoint = Vector2.new(0, 1)
	barFill.Position = UDim2.fromScale(0, 1)
	barFill.Size = UDim2.fromScale(1, 0)
	barFill.BackgroundColor3 = Theme.Colors.Text
	barFill.BorderSizePixel = 0
	Components.addCorner(barFill, UDim.new(0, 14))
	local fillGradient = Instance.new("UIGradient")
	fillGradient.Color = ColorSequence.new(Theme.Colors.Highlight, Theme.Colors.Accent)
	fillGradient.Rotation = -90
	fillGradient.Parent = barFill
	barFill.Parent = barBack

	local phaseLabel = Components.makeLabel("Phase", Theme.Fonts.Body, Theme.Colors.TextMuted, 18)
	phaseLabel.AnchorPoint = Vector2.new(1, 0)
	phaseLabel.Position = UDim2.new(1, 0, 0, BAR_HEIGHT + 44)
	phaseLabel.Size = UDim2.fromOffset(Theme.DropBar.ColumnSize.X, 22)
	phaseLabel.TextXAlignment = Enum.TextXAlignment.Right
	phaseLabel.Parent = column

	local boostLabel = Components.makeLabel("Boost", Theme.Fonts.Display, Theme.Colors.Gold, 24)
	boostLabel.AnchorPoint = Vector2.new(1, 0)
	boostLabel.Position = UDim2.new(1, 0, 0, BAR_HEIGHT + 68)
	boostLabel.Size = UDim2.fromOffset(Theme.DropBar.ColumnSize.X, 28)
	boostLabel.TextXAlignment = Enum.TextXAlignment.Right
	boostLabel.Visible = false
	Components.addStroke(boostLabel, Theme.Colors.Background, 2)
	boostLabel.Parent = column

	-- Botões das máquinas
	local pyroButtons: { PyroButton } = {}
	for index, def in PyroConfig.List do
		local button = Components.makeButton(def.Id, Theme.Colors.Background)
		button.Position = UDim2.fromOffset(0, 36 + (index - 1) * 76)
		button.Size = UDim2.fromOffset(118, 68)
		button.ClipsDescendants = true
		Components.addCorner(button, UDim.new(0, 12))
		local stroke = Components.addStroke(button, Theme.Colors.AccentDark, 2)
		button.Parent = column

		local cooldown = Instance.new("Frame")
		cooldown.Name = "Cooldown"
		cooldown.AnchorPoint = Vector2.new(0, 1)
		cooldown.Position = UDim2.fromScale(0, 1)
		cooldown.Size = UDim2.fromScale(1, 0)
		cooldown.BackgroundColor3 = Theme.Colors.Overlay
		cooldown.BackgroundTransparency = 0.45
		cooldown.BorderSizePixel = 0
		cooldown.ZIndex = 2
		cooldown.Parent = button

		local nameLabel = Components.makeLabel("Name", Theme.Fonts.Display, Theme.Colors.Text, 20)
		nameLabel.AnchorPoint = Vector2.new(0.5, 0)
		nameLabel.Position = UDim2.new(0.5, 0, 0, 8)
		nameLabel.Size = UDim2.new(1, -12, 0, 24)
		nameLabel.ZIndex = 3
		nameLabel.Text = def.ShortName
		nameLabel.Parent = button

		local statusLabel = Components.makeLabel("Status", Theme.Fonts.Body, Theme.Colors.TextMuted, 15)
		statusLabel.AnchorPoint = Vector2.new(0.5, 1)
		statusLabel.Position = UDim2.new(0.5, 0, 1, -8)
		statusLabel.Size = UDim2.new(1, -12, 0, 18)
		statusLabel.ZIndex = 3
		statusLabel.Parent = button

		local entry: PyroButton = {
			Def = def,
			Button = button,
			Stroke = stroke,
			NameLabel = nameLabel,
			StatusLabel = statusLabel,
			Cooldown = cooldown,
		}
		table.insert(pyroButtons, entry)

		trove:Connect(button.Activated, function()
			local state = BassDropController.Get()
			if state and state.Owned[def.Id] then
				BassDropController.ToggleArm(def.Id)
			else
				ShopView.Open("Pyro")
			end
		end)
	end

	-- Botão DROP! central ----------------------------------------------------
	local dropHolder = Components.makeFrame("DropHolder")
	dropHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	dropHolder.Position = UDim2.fromScale(0.5, 0.42)
	dropHolder.Size = UDim2.fromOffset(dropSize, dropSize)
	dropHolder.Visible = false
	dropHolder.Parent = screenGui

	local dropScale = Instance.new("UIScale")
	dropScale.Parent = dropHolder

	local ring = Components.makeFrame("ApproachRing")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(dropSize, dropSize)
	Components.addCorner(ring, UDim.new(0.5, 0))
	local ringStroke = Components.addStroke(ring, Theme.Colors.Gold, 4)
	ring.Parent = dropHolder

	local dropButton = Components.makeButton("DropButton", Theme.Colors.Text)
	dropButton.AnchorPoint = Vector2.new(0.5, 0.5)
	dropButton.Position = UDim2.fromScale(0.5, 0.5)
	dropButton.Size = UDim2.fromOffset(dropSize, dropSize)
	Components.addCorner(dropButton, UDim.new(0.5, 0))
	Components.addStroke(dropButton, Theme.Colors.Text, 5)
	local dropGradient = Instance.new("UIGradient")
	dropGradient.Color = ColorSequence.new(Theme.Colors.Danger, Theme.Colors.Accent)
	dropGradient.Rotation = 90
	dropGradient.Parent = dropButton
	local pulseScale = Instance.new("UIScale")
	pulseScale.Parent = dropButton
	dropButton.Parent = dropHolder

	local dropLabel = Components.makeLabel("Label", Theme.Fonts.Display, Theme.Colors.Text, 60)
	dropLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	dropLabel.Position = UDim2.fromScale(0.5, 0.45)
	dropLabel.Size = UDim2.new(0.85, 0, 0, 66)
	Components.addStroke(dropLabel, Theme.Colors.Background, 3)
	dropLabel.Parent = dropButton

	local hintLabel = Components.makeLabel("Hint", Theme.Fonts.Body, Theme.Colors.Gold, 20)
	hintLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	hintLabel.Position = UDim2.fromScale(0.5, 0.74)
	hintLabel.Size = UDim2.new(0.8, 0, 0, 24)
	Components.addStroke(hintLabel, Theme.Colors.Background, 1.5)
	hintLabel.Parent = dropButton

	-- Resultado --------------------------------------------------------------
	local resultHolder = Components.makeFrame("Result")
	resultHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	resultHolder.Position = UDim2.fromScale(0.5, 0.24)
	resultHolder.Size = UDim2.fromOffset(560, 120)
	resultHolder.Visible = false
	resultHolder.Parent = screenGui

	local resultScale = Instance.new("UIScale")
	resultScale.Parent = resultHolder

	local resultInner = Components.makeFrame("Inner")
	resultInner.Size = UDim2.fromScale(1, 1)
	resultInner.Parent = resultHolder
	local resultPop = Instance.new("UIScale")
	resultPop.Parent = resultInner

	local resultLabel = Components.makeLabel("Grade", Theme.Fonts.Display, Theme.Colors.Gold, 64)
	resultLabel.Size = UDim2.new(1, 0, 0, 72)
	Components.addStroke(resultLabel, Theme.Colors.Background, 3)
	resultLabel.Parent = resultInner

	local synergyLabel = Components.makeLabel("Synergies", Theme.Fonts.Body, Theme.Colors.Highlight, 22)
	synergyLabel.Position = UDim2.fromOffset(0, 78)
	synergyLabel.Size = UDim2.new(1, 0, 0, 28)
	Components.addStroke(synergyLabel, Theme.Colors.Background, 1.5)
	synergyLabel.Parent = resultInner

	-- Estado / animação --------------------------------------------------------
	local current: DropState? = BassDropController.Get()
	local fillTween: Tween? = nil
	local pressedAt = -math.huge
	local resultToken = 0
	local buildUpDuration = DropCalc.GetBuildUpDuration()
	local beatInterval = DropCalc.GetBeatInterval()

	local function renderState(state: DropState)
		current = state
		local ratio = math.clamp(state.Energy / state.MaxEnergy, 0, 1)
		local previous = fillTween
		if previous then
			previous:Cancel()
		end
		local tween = TweenService:Create(barFill, Theme.Tween.Counter, { Size = UDim2.fromScale(1, ratio) })
		fillTween = tween
		tween:Play()
		setText(energyLabel, string.format("%d%%", math.floor(ratio * 100)))
	end

	local function trigger()
		if BassDropController.TriggerDrop() then
			pressedAt = os.clock()
		end
	end

	local function showResult(text: string, color: Color3, detail: string)
		resultToken += 1
		local token = resultToken
		resultLabel.Text = text
		resultLabel.TextColor3 = color
		synergyLabel.Text = detail
		resultHolder.Visible = true
		resultPop.Scale = 0.5
		TweenService:Create(resultPop, Theme.Tween.Toast, { Scale = 1 }):Play()
		task.delay(Theme.DropBar.ResultDuration, function()
			if resultToken == token then
				resultHolder.Visible = false
			end
		end)
	end

	local function onResolved(result: DropResolved)
		if result.UserId ~= Players.LocalPlayer.UserId then
			return
		end
		if not result.Success then
			showResult("FALHASTE O DROP", Theme.Colors.Danger, string.format("A energia volta a %d%%", BassDropConfig.MissEnergyReset))
			return
		end
		local grade = result.Grade
		local gradeDef = if grade then DropCalc.GetGradeDef(grade) else nil
		local names: { string } = {}
		for _, synergyId in result.Synergies do
			for _, synergy in PyroConfig.Synergies do
				if synergy.Id == synergyId then
					table.insert(names, synergy.Name)
				end
			end
		end
		local savedBy = result.SavedBy
		local detail = if #names > 0 then table.concat(names, "  +  ") else "Arma mais máquinas para sinergias"
		if savedBy then
			detail = "SALVO POR " .. string.upper(savedBy) .. "!" .. (if #names > 0 then "  ·  " .. table.concat(names, " + ") else "")
		end
		showResult(
			string.format("%s %sx", if gradeDef then gradeDef.Label else "DROP!", NumberFormatter.format(result.Multiplier)),
			gradeColor(grade),
			detail
		)
	end

	local function updatePyroButtons(state: DropState, now: number)
		for _, entry in pyroButtons do
			local def = entry.Def
			if not state.Owned[def.Id] then
				entry.Button.BackgroundColor3 = Theme.Colors.Disabled
				entry.Stroke.Color = Theme.Colors.Disabled
				entry.Stroke.Thickness = 2
				entry.NameLabel.TextColor3 = Theme.Colors.TextMuted
				entry.Cooldown.Size = UDim2.fromScale(1, 0)
				setText(entry.StatusLabel, "🔒 " .. NumberFormatter.format(def.UnlockCost))
			else
				local armed = BassDropController.IsArmed(def.Id)
				entry.Button.BackgroundColor3 = if armed then Theme.Colors.AccentDark else Theme.Colors.Background
				entry.Stroke.Color = if armed then Theme.Colors.Gold else Theme.Colors.AccentDark
				entry.Stroke.Thickness = if armed then 3 else 2
				entry.NameLabel.TextColor3 = Theme.Colors.Text
				local readyAt = state.Cooldowns[def.Id]
				local remaining = if readyAt then readyAt - now else 0
				if remaining > 0 and def.Cooldown > 0 then
					entry.Cooldown.Size = UDim2.fromScale(1, math.clamp(remaining / def.Cooldown, 0, 1))
					setText(entry.StatusLabel, string.format("%ds", math.ceil(remaining)))
				else
					entry.Cooldown.Size = UDim2.fromScale(1, 0)
					setText(entry.StatusLabel, if armed then "ARMADA" else "DESARMADA")
				end
			end
		end
	end

	local function update()
		local state = current
		local intensity = AudioController.GetIntensity()
		barStroke.Transparency = 0.7 - 0.7 * intensity
		if not state then
			return
		end
		local now = BassDropController.GetServerTime()

		-- Fase e boost
		if state.Phase == "Charging" then
			setText(phaseLabel, "ENERGIA DO DROP")
		elseif state.Phase == "BuildUp" then
			setText(phaseLabel, "PREPARA-TE…")
		elseif state.Phase == "Window" then
			setText(phaseLabel, "AGORA!")
		else
			setText(phaseLabel, "BOOST ATIVO")
		end
		local boosting = state.Phase == "Boost" and now < state.PhaseEnd
		boostLabel.Visible = boosting
		if boosting then
			setText(
				boostLabel,
				string.format("%sx · %ds", NumberFormatter.format(state.BoostMultiplier), math.ceil(state.PhaseEnd - now))
			)
		end

		updatePyroButtons(state, now)

		-- DROP!
		local inDrop = state.Phase == "BuildUp" or state.Phase == "Window"
		dropHolder.Visible = inDrop
		if not inDrop then
			return
		end
		local untilDrop = state.DropTime - now
		local open = BassDropController.IsWindowOpen()

		local ringSize = dropSize * (1 + 1.2 * math.clamp(untilDrop / buildUpDuration, 0, 1))
		ring.Size = UDim2.fromOffset(ringSize, ringSize)
		ring.Visible = untilDrop > -BassDropConfig.WindowAfter
		ringStroke.Transparency = if open then 0 else 0.3

		if open then
			setText(dropLabel, "DROP!")
			setText(hintLabel, if UserInputService.KeyboardEnabled then "[F]" else "")
			dropButton.BackgroundTransparency = 0
		else
			setText(dropLabel, tostring(math.max(1, math.ceil((untilDrop - BassDropConfig.WindowBefore) / beatInterval))))
			setText(hintLabel, "PREPARA-TE")
			dropButton.BackgroundTransparency = 0.35
		end

		local pressed = os.clock() - pressedAt < PRESS_FEEDBACK_TIME
		local pulse = if open then 0.08 * intensity else 0.03 * intensity
		pulseScale.Scale = (if pressed then 0.88 else 1) + pulse
	end

	-- Ligações -----------------------------------------------------------------
	trove:Connect(dropButton.Activated, trigger)
	trove:Connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == Theme.DropBar.TriggerKey or input.KeyCode == Theme.DropBar.TriggerGamepadButton then
			trigger()
		end
	end)

	trove:Add(BassDropController.Changed:Connect(renderState))
	trove:Add(BassDropController.Resolved:Connect(onResolved))
	trove:Connect(RunService.RenderStepped, update)

	local function updateScales()
		local scale = Components.computeScale(screenGui.AbsoluteSize)
		columnScale.Scale = scale
		dropScale.Scale = scale
		resultScale.Scale = scale
	end
	trove:Connect(screenGui:GetPropertyChangedSignal("AbsoluteSize"), updateScales)

	screenGui.Parent = playerGui
	updateScales()

	local initial = current
	if initial then
		renderState(initial)
	end
end

function DropBarView.Unmount()
	local trove = activeTrove
	if trove then
		activeTrove = nil
		trove:Destroy()
	end
end

return DropBarView
