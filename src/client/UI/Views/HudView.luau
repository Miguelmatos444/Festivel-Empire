--!strict
--[[
	HudView
	HUD principal: contador de Hype (topo), botão "BATIDA" (fundo) e toasts.
	Responsivo por UIScale calculado a partir do tamanho do ecrã (mobile/PC/consola).
	Toda a UI e ligações vivem numa Trove — Unmount() limpa tudo.
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
local ClickController = require(Client.Controllers.ClickController)
local BassDropController = require(Client.Controllers.BassDropController)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)

type BigNum = BigNum.BigNum
type Snapshot = Types.PlayerStateSnapshot
type Notice = Types.Notice

local COUNTER_TWEEN_LIMIT = 1e15 -- acima disto o contador muda sem animação

local HudView = {}

local activeTrove: Trove.Trove? = nil

-- Helpers de construção ------------------------------------------------------

local addCorner = Components.addCorner
local addStroke = Components.addStroke
local makeLabel = Components.makeLabel
local makeTransparentFrame = Components.makeFrame

-- Montagem -------------------------------------------------------------------

function HudView.Mount()
	if activeTrove then
		return
	end
	local trove = Trove.new()
	activeTrove = trove

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screenGui = trove:Add(Instance.new("ScreenGui"))
	screenGui.Name = "HudGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets

	-- Topo: painel de Hype + área de toasts ---------------------------------
	local top = makeTransparentFrame("Top")
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.Position = UDim2.new(0.5, 0, 0, 12)
	top.Size = UDim2.fromOffset(380, 340)
	top.Parent = screenGui

	local topScale = Instance.new("UIScale")
	topScale.Parent = top

	local topLayout = Instance.new("UIListLayout")
	topLayout.FillDirection = Enum.FillDirection.Vertical
	topLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	topLayout.SortOrder = Enum.SortOrder.LayoutOrder
	topLayout.Padding = UDim.new(0, 10)
	topLayout.Parent = top

	local hypePanel = Instance.new("Frame")
	hypePanel.Name = "HypePanel"
	hypePanel.LayoutOrder = 1
	hypePanel.Size = UDim2.fromOffset(380, 118)
	hypePanel.BackgroundColor3 = Theme.Colors.Panel
	hypePanel.BackgroundTransparency = 0.1
	hypePanel.BorderSizePixel = 0
	addCorner(hypePanel, UDim.new(0, Theme.Radius.Panel))
	addStroke(hypePanel, Theme.Colors.Accent, 2)
	hypePanel.Parent = top

	local panelGradient = Instance.new("UIGradient")
	panelGradient.Color = ColorSequence.new(Theme.Colors.Panel, Theme.Colors.Background)
	panelGradient.Rotation = 90
	panelGradient.Parent = hypePanel

	local panelLayout = Instance.new("UIListLayout")
	panelLayout.FillDirection = Enum.FillDirection.Vertical
	panelLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	panelLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
	panelLayout.Padding = UDim.new(0, 2)
	panelLayout.Parent = hypePanel

	local titleLabel = makeLabel("Title", Theme.Fonts.Body, Theme.Colors.Gold, 18)
	titleLabel.LayoutOrder = 1
	titleLabel.Size = UDim2.new(1, -24, 0, 20)
	titleLabel.Text = "HYPE"
	titleLabel.Parent = hypePanel

	local valueLabel = makeLabel("Value", Theme.Fonts.Display, Theme.Colors.Text, 52)
	valueLabel.LayoutOrder = 2
	valueLabel.Size = UDim2.new(1, -24, 0, 54)
	valueLabel.Text = "0"
	addStroke(valueLabel, Theme.Colors.Background, 2)
	valueLabel.Parent = hypePanel

	local rateLabel = makeLabel("Rate", Theme.Fonts.Body, Theme.Colors.Highlight, 18)
	rateLabel.LayoutOrder = 3
	rateLabel.Size = UDim2.new(1, -24, 0, 20)
	rateLabel.Text = "+0 / s"
	rateLabel.Parent = hypePanel

	local toastArea = makeTransparentFrame("Toasts")
	toastArea.LayoutOrder = 2
	toastArea.Size = UDim2.fromOffset(380, 210)
	toastArea.Parent = top

	local toastLayout = Instance.new("UIListLayout")
	toastLayout.FillDirection = Enum.FillDirection.Vertical
	toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
	toastLayout.Padding = UDim.new(0, 6)
	toastLayout.Parent = toastArea

	-- Fundo: botão BATIDA ----------------------------------------------------
	local bottom = makeTransparentFrame("Bottom")
	bottom.AnchorPoint = Vector2.new(0.5, 1)
	bottom.Position = UDim2.new(0.5, 0, 1, -24)
	bottom.Size = UDim2.fromOffset(220, 220)
	bottom.Parent = screenGui

	local bottomScale = Instance.new("UIScale")
	bottomScale.Parent = bottom

	local beatButton = Instance.new("TextButton")
	beatButton.Name = "BeatButton"
	beatButton.AnchorPoint = Vector2.new(0.5, 0.5)
	beatButton.Position = UDim2.fromScale(0.5, 0.5)
	beatButton.Size = UDim2.fromOffset(200, 200)
	beatButton.BackgroundColor3 = Theme.Colors.Text
	beatButton.AutoButtonColor = false
	beatButton.Text = ""
	beatButton.Selectable = true
	addCorner(beatButton, UDim.new(0.5, 0))
	addStroke(beatButton, Theme.Colors.Text, 4)
	beatButton.Parent = bottom

	local buttonGradient = Instance.new("UIGradient")
	buttonGradient.Color = ColorSequence.new(Theme.Colors.Accent, Theme.Colors.AccentDark)
	buttonGradient.Rotation = 90
	buttonGradient.Parent = beatButton

	local pulseScale = Instance.new("UIScale")
	pulseScale.Parent = beatButton

	local beatLabel = makeLabel("Label", Theme.Fonts.Display, Theme.Colors.Text, 40)
	beatLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	beatLabel.Position = UDim2.fromScale(0.5, 0.42)
	beatLabel.Size = UDim2.new(0.8, 0, 0, 44)
	beatLabel.Text = "BATIDA"
	addStroke(beatLabel, Theme.Colors.Background, 2)
	beatLabel.Parent = beatButton

	local perClickLabel = makeLabel("PerClick", Theme.Fonts.Body, Theme.Colors.Gold, 24)
	perClickLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	perClickLabel.Position = UDim2.fromScale(0.5, 0.64)
	perClickLabel.Size = UDim2.new(0.7, 0, 0, 26)
	perClickLabel.Text = "+1"
	addStroke(perClickLabel, Theme.Colors.Background, 1.5)
	perClickLabel.Parent = beatButton

	-- Escala responsiva --------------------------------------------------------
	local function updateScale()
		local scale = Components.computeScale(screenGui.AbsoluteSize)
		topScale.Scale = scale
		bottomScale.Scale = scale
	end
	trove:Connect(screenGui:GetPropertyChangedSignal("AbsoluteSize"), updateScale)

	-- Contador animado ---------------------------------------------------------
	local displayValue = trove:Add(Instance.new("NumberValue"))
	local counterTween: Tween? = nil
	local latestHype: BigNum = BigNum.ZERO

	trove:Connect(displayValue.Changed, function(value: number)
		if counterTween then
			valueLabel.Text = NumberFormatter.format(value)
		end
	end)

	local function setHype(hype: BigNum)
		latestHype = hype
		local previousTween = counterTween
		if previousTween then
			counterTween = nil
			previousTween:Cancel()
		end

		if hype.e < 15 and displayValue.Value < COUNTER_TWEEN_LIMIT then
			local tween = TweenService:Create(displayValue, Theme.Tween.Counter, { Value = BigNum.toNumber(hype) })
			counterTween = tween
			tween.Completed:Once(function(playbackState: Enum.PlaybackState)
				if playbackState == Enum.PlaybackState.Completed and counterTween == tween then
					counterTween = nil
					valueLabel.Text = NumberFormatter.format(latestHype)
				end
			end)
			tween:Play()
		else
			valueLabel.Text = NumberFormatter.format(hype)
			displayValue.Value = math.min(BigNum.toNumber(hype), COUNTER_TWEEN_LIMIT)
		end
	end

	-- Efeitos de clique -------------------------------------------------------
	local perClickValue: BigNum = BigNum.ONE
	local floatingCount = 0

	local function spawnFloatingText(text: string)
		if floatingCount >= Theme.MaxFloatingTexts then
			return
		end
		floatingCount += 1

		local label = makeLabel("Float", Theme.Fonts.Display, Theme.Colors.Gold, 34)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Size = UDim2.fromOffset(160, 40)
		label.Position = UDim2.new(0.5, math.random(-60, 60), 0, 10)
		label.Text = text
		label.ZIndex = 5
		local stroke = addStroke(label, Theme.Colors.Background, 2)
		label.Parent = bottom

		local tween = TweenService:Create(label, Theme.Tween.Float, {
			Position = label.Position - UDim2.fromOffset(0, 90),
			TextTransparency = 1,
		})
		TweenService:Create(stroke, Theme.Tween.Float, { Transparency = 1 }):Play()
		tween.Completed:Once(function()
			floatingCount -= 1
			label:Destroy()
		end)
		tween:Play()
	end

	local function spawnRing()
		local ring = makeTransparentFrame("Ring")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromScale(1, 1)
		addCorner(ring, UDim.new(0.5, 0))
		local stroke = addStroke(ring, Theme.Colors.Highlight, 4)
		ring.Parent = beatButton

		local tween = TweenService:Create(ring, Theme.Tween.Ring, { Size = UDim2.fromScale(1.45, 1.45) })
		TweenService:Create(stroke, Theme.Tween.Ring, { Transparency = 1 }):Play()
		tween.Completed:Once(function()
			ring:Destroy()
		end)
		tween:Play()
	end

	trove:Connect(beatButton.Activated, function()
		if not ClickController.RequestClick() then
			return
		end
		pulseScale.Scale = 0.9
		TweenService:Create(pulseScale, Theme.Tween.Fast, { Scale = 1 }):Play()
		spawnRing()
		-- Durante o boost do Bass Drop, o "+N" mostra o ganho multiplicado
		local gain = BigNum.mulNumber(perClickValue, BassDropController.GetBoostMultiplier())
		spawnFloatingText("+" .. NumberFormatter.format(gain))
	end)

	-- Toasts -------------------------------------------------------------------
	local toasts: { Frame } = {}
	local toastCounter = 0

	local function removeToast(toast: Frame)
		local index = table.find(toasts, toast)
		if index then
			table.remove(toasts, index)
		end
		toast:Destroy()
	end

	local function showToast(text: string, accent: Color3)
		while #toasts >= Theme.MaxToasts do
			removeToast(toasts[1])
		end

		toastCounter += 1
		local toast = Instance.new("Frame")
		toast.Name = "Toast"
		toast.LayoutOrder = toastCounter
		toast.Size = UDim2.fromOffset(360, 64)
		toast.BackgroundColor3 = Theme.Colors.Panel
		toast.BackgroundTransparency = 0.05
		toast.BorderSizePixel = 0
		addCorner(toast, UDim.new(0, Theme.Radius.Toast))
		local stroke = addStroke(toast, accent, 2)

		local label = makeLabel("Text", Theme.Fonts.Body, Theme.Colors.Text, 18)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.new(1, -20, 1, -12)
		label.TextWrapped = true
		label.Text = text
		label.Parent = toast

		local popScale = Instance.new("UIScale")
		popScale.Scale = 0.6
		popScale.Parent = toast

		toast.Parent = toastArea
		table.insert(toasts, toast)
		TweenService:Create(popScale, Theme.Tween.Toast, { Scale = 1 }):Play()

		task.delay(Theme.ToastDuration, function()
			if toast.Parent == nil then
				return
			end
			local fade = TweenService:Create(toast, Theme.Tween.FadeOut, { BackgroundTransparency = 1 })
			TweenService:Create(label, Theme.Tween.FadeOut, { TextTransparency = 1 }):Play()
			TweenService:Create(stroke, Theme.Tween.FadeOut, { Transparency = 1 }):Play()
			fade.Completed:Once(function()
				removeToast(toast)
			end)
			fade:Play()
		end)
	end

	-- Ligação ao estado ------------------------------------------------------
	local function render(snapshot: Snapshot)
		local hype = BigNum.deserialize(snapshot.Hype)
		if not BigNum.eq(hype, latestHype) or valueLabel.Text == "" then
			setHype(hype)
		end
		rateLabel.Text = "+" .. NumberFormatter.format(BigNum.deserialize(snapshot.HypePerSecond)) .. " / s"
		perClickValue = BigNum.deserialize(snapshot.HypePerClick)
		perClickLabel.Text = "+" .. NumberFormatter.format(perClickValue)
	end

	local function onNotice(notice: Notice)
		if notice.Kind == "OfflineEarnings" then
			showToast(
				string.format(
					"Enquanto estiveste fora (%s), o teu festival gerou +%s Hype!",
					NumberFormatter.formatTime(notice.Seconds),
					NumberFormatter.format(BigNum.deserialize(notice.Amount))
				),
				Theme.Colors.Gold
			)
		elseif notice.Kind == "Info" then
			showToast(notice.Text, Theme.Colors.Highlight)
		end
	end

	trove:Add(StateController.Changed:Connect(render))
	trove:Add(StateController.NoticeReceived:Connect(onNotice))

	screenGui.Parent = playerGui
	updateScale()

	local current = StateController.Get()
	if current then
		render(current)
	end
end

function HudView.Unmount()
	local trove = activeTrove
	if trove then
		activeTrove = nil
		trove:Destroy()
	end
end

return HudView
