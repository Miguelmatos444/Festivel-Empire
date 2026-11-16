--!strict
--[[
	ArrowGameView
	Apresentação do minijogo de setas (Fase 9):
	  - bolinhas com seta em posições aleatórias de uma zona que não tapa o HUD,
	    o SideMenu nem a barra do drop; cada uma encolhe até desaparecer
	    (anel brilhante = ainda dá PERFEITO);
	  - toque/clique numa bolinha = acerto; setas/D-pad tratados no ArrowController;
	  - partículas no acerto, notas no estilo do Bass Drop, combo e Hype ganho;
	  - botão AUTO (Gamepass Auto-Play).
	Pool fixo de bolinhas: nada é criado nem destruído no RenderStepped.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local ArrowGameConfig = require(ReplicatedStorage.Shared.Config.ArrowGame)
local ArrowCalc = require(ReplicatedStorage.Shared.Calc.ArrowCalc)
local BigNum = require(ReplicatedStorage.Shared.Util.BigNum)
local NumberFormatter = require(ReplicatedStorage.Shared.Util.NumberFormatter)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)

local Client = script.Parent.Parent.Parent
local ArrowController = require(Client.Controllers.ArrowController)
local RetentionController = require(Client.Controllers.RetentionController)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)

type ArrowDirection = Types.ArrowDirection
type ArrowEvent = Types.ArrowEvent
type ClientArrow = ArrowController.ClientArrow

type Slot = {
	Button: TextButton,
	Scale: UIScale,
	Ring: UIStroke,
	Glyph: TextLabel,
	Id: number?,
	Stamp: number,
}

local MAX_EFFECTS = 48
local MAX_REMEMBERED_POSITIONS = 48
local SPARKS_PER_HIT = 6
local POPUP_TWEEN = TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SPARK_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local DIRECTION_ROTATION: { [ArrowDirection]: number } = {
	Up = 0,
	Right = 90,
	Down = 180,
	Left = -90,
}

local DIRECTION_COLOR: { [ArrowDirection]: Color3 } = {
	Up = Theme.Colors.Highlight,
	Right = Theme.Colors.Gold,
	Down = Theme.Colors.Success,
	Left = Theme.Colors.Accent,
}

local ArrowGameView = {}

local activeTrove: Trove.Trove? = nil

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function setText(label: TextLabel | TextButton, text: string)
	if label.Text ~= text then
		label.Text = text
	end
end

function ArrowGameView.Mount()
	if activeTrove then
		return
	end
	local trove = Trove.new()
	activeTrove = trove

	local clientConfig = ArrowGameConfig.Client
	local margins = clientConfig.SafeMargins
	local perfectMax = ArrowCalc.GetGradeDef("Perfect").MaxProgress
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screenGui = trove:Add(Instance.new("ScreenGui"))
	screenGui.Name = "ArrowGameGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	screenGui.DisplayOrder = 1 -- por baixo dos painéis (10), do SideMenu (3) e da barra do drop (2)
	screenGui.Enabled = false

	-- Zona das bolinhas (posicionada em píxeis em updateLayout)
	local zone = Components.makeFrame("Zone")
	zone.Parent = screenGui

	local effects = Components.makeFrame("Effects")
	effects.Size = UDim2.fromScale(1, 1)
	effects.ZIndex = 5
	effects.Parent = zone

	-- Topo: combo ----------------------------------------------------------------
	local comboLabel = Components.makeLabel("Combo", Theme.Fonts.Display, Theme.Colors.Gold, 34)
	comboLabel.AnchorPoint = Vector2.new(0.5, 1)
	comboLabel.Position = UDim2.new(0.5, 0, 0, -4)
	comboLabel.Size = UDim2.new(0.8, 0, 0, 38)
	comboLabel.Text = ""
	comboLabel.ZIndex = 6
	Components.addStroke(comboLabel, Theme.Colors.Background, 2)
	comboLabel.Parent = zone
	local comboScale = Instance.new("UIScale")
	comboScale.Parent = comboLabel

	-- Fundo: dica + AUTO -------------------------------------------------------------
	local hintLabel = Components.makeLabel("Hint", Theme.Fonts.Body, Theme.Colors.TextMuted, 18)
	hintLabel.AnchorPoint = Vector2.new(0.5, 0)
	hintLabel.Position = UDim2.new(0.5, 0, 1, 2)
	hintLabel.Size = UDim2.new(0.7, 0, 0, 22)
	hintLabel.ZIndex = 6
	Components.addStroke(hintLabel, Theme.Colors.Background, 1.5)
	hintLabel.Parent = zone

	local pausedLabel = Components.makeLabel("Paused", Theme.Fonts.Display, Theme.Colors.Highlight, 30)
	pausedLabel.AnchorPoint = Vector2.new(0.5, 0)
	pausedLabel.Position = UDim2.fromScale(0.5, 0.06)
	pausedLabel.Size = UDim2.new(0.8, 0, 0, 34)
	pausedLabel.Text = "BASS DROP! As setas voltam a seguir."
	pausedLabel.Visible = false
	pausedLabel.ZIndex = 6
	Components.addStroke(pausedLabel, Theme.Colors.Background, 2)
	pausedLabel.Parent = zone

	local autoButton = Components.makeButton("Auto", Theme.Colors.Panel)
	autoButton.AnchorPoint = Vector2.new(1, 0)
	autoButton.Position = UDim2.new(1, 0, 1, 0)
	autoButton.Size = UDim2.fromOffset(96, 40)
	autoButton.Font = Theme.Fonts.Display
	autoButton.TextColor3 = Theme.Colors.Text
	autoButton.TextSize = 20
	autoButton.Text = "AUTO"
	autoButton.Visible = false
	autoButton.ZIndex = 6
	Components.addCorner(autoButton, UDim.new(0, 12))
	local autoStroke = Components.addStroke(autoButton, Theme.Colors.TextMuted, 2)
	autoButton.Parent = zone
	local autoScale = Instance.new("UIScale")
	autoScale.Parent = autoButton

	local function renderAuto()
		local sync = RetentionController.Get()
		local owns = RetentionController.Owns("AutoClicker")
		local enabled = sync ~= nil and sync.AutoClick and owns
		autoButton.Visible = owns
		autoButton.BackgroundColor3 = if enabled then Theme.Colors.Success else Theme.Colors.Panel
		autoStroke.Color = if enabled then Theme.Colors.Gold else Theme.Colors.TextMuted
		autoButton.Text = if enabled then "AUTO ✓" else "AUTO"
	end
	trove:Connect(autoButton.Activated, function()
		local sync = RetentionController.Get()
		RetentionController.SetAutoClick(not (sync ~= nil and sync.AutoClick))
	end)
	trove:Add(RetentionController.Changed:Connect(renderAuto))

	local function renderHint()
		if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
			hintLabel.Text = "Usa o D-pad antes de as bolinhas desaparecerem"
		elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
			hintLabel.Text = "Toca nas bolinhas antes de desaparecerem"
		else
			hintLabel.Text = "Carrega nas setas ← ↑ → ↓ (ou clica nas bolinhas)"
		end
	end

	-- Pool de bolinhas ---------------------------------------------------------------
	local slots: { Slot } = {}
	local slotById: { [number]: Slot } = {}
	local positions: { [number]: Vector2 } = {} -- id -> posição (fração da zona), também após sair
	local positionOrder: { number } = {}
	local ballPixels = clientConfig.BallSize
	local stamp = 0

	for index = 1, clientConfig.PoolSize do
		local button = Instance.new("TextButton")
		button.Name = "Ball" .. index
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.BackgroundColor3 = Theme.Colors.Panel
		button.BackgroundTransparency = 0.05
		button.AutoButtonColor = false
		button.Text = ""
		button.Visible = false
		button.ZIndex = 3
		Components.addCorner(button, UDim.new(0.5, 0))
		local ring = Components.addStroke(button, Theme.Colors.Text, 5)
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		local scale = Instance.new("UIScale")
		scale.Parent = button

		local glyph = Components.makeLabel("Glyph", Theme.Fonts.Body, Theme.Colors.Text, 64)
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.5)
		glyph.Size = UDim2.fromScale(0.72, 0.72)
		glyph.Text = "↑"
		glyph.ZIndex = 4
		Components.addStroke(glyph, Theme.Colors.Background, 2)
		glyph.Parent = button

		button.Parent = zone
		local slot: Slot = { Button = button, Scale = scale, Ring = ring, Glyph = glyph, Id = nil, Stamp = 0 }
		table.insert(slots, slot)

		trove:Connect(button.Activated, function()
			local id = slot.Id
			if id then
				ArrowController.TapArrow(id)
			end
		end)
	end

	local function rememberPosition(id: number, position: Vector2)
		positions[id] = position
		table.insert(positionOrder, id)
		while #positionOrder > MAX_REMEMBERED_POSITIONS do
			positions[table.remove(positionOrder, 1) :: number] = nil
		end
	end

	-- Posição aleatória (estável por id) longe das outras bolinhas visíveis
	local function pickPosition(id: number): Vector2
		local size = zone.AbsoluteSize
		local radiusX = if size.X > 0 then math.min(0.45, ballPixels / 2 / size.X) else 0.1
		local radiusY = if size.Y > 0 then math.min(0.45, ballPixels / 2 / size.Y) else 0.1
		local random = Random.new(id)
		local best = Vector2.new(0.5, 0.5)
		local bestDistance = -1
		for _ = 1, clientConfig.PlacementAttempts do
			local candidate = Vector2.new(
				random:NextNumber(radiusX, 1 - radiusX),
				random:NextNumber(radiusY, 1 - radiusY)
			)
			local nearest = math.huge
			for otherId, slot in slotById do
				local other = positions[otherId]
				if other and slot.Id == otherId then
					local delta = (candidate - other) * size
					nearest = math.min(nearest, delta.Magnitude)
				end
			end
			if nearest > ballPixels * 1.1 then
				return candidate
			end
			if nearest > bestDistance then
				bestDistance = nearest
				best = candidate
			end
		end
		return best
	end

	local function acquire(arrow: ClientArrow): Slot?
		for _, slot in slots do
			if slot.Id == nil then
				local position = positions[arrow.Id] or pickPosition(arrow.Id)
				if not positions[arrow.Id] then
					rememberPosition(arrow.Id, position)
				end
				slot.Id = arrow.Id
				slotById[arrow.Id] = slot
				slot.Button.Position = UDim2.fromScale(position.X, position.Y)
				slot.Button.Size = UDim2.fromOffset(ballPixels, ballPixels)
				slot.Glyph.Rotation = DIRECTION_ROTATION[arrow.Dir]
				slot.Glyph.TextColor3 = DIRECTION_COLOR[arrow.Dir]
				slot.Button.Visible = true
				return slot
			end
		end
		return nil -- pool cheio (não acontece com MaxActive <= PoolSize)
	end

	local function release(slot: Slot)
		local id = slot.Id
		if id then
			slotById[id] = nil
		end
		slot.Id = nil
		slot.Button.Visible = false
	end

	-- Efeitos (criados nos eventos, nunca no RenderStepped) -------------------------------
	local effectCount = 0

	local function toPixels(position: Vector2): UDim2
		return UDim2.fromScale(position.X, position.Y)
	end

	local function spawnPopup(position: Vector2, text: string, color: Color3, textSize: number, rise: number)
		if effectCount >= MAX_EFFECTS then
			return
		end
		effectCount += 1
		local label = Components.makeLabel("Popup", Theme.Fonts.Display, color, textSize)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = toPixels(position)
		label.Size = UDim2.fromOffset(240, textSize + 6)
		label.Text = text
		label.ZIndex = 7
		local stroke = Components.addStroke(label, Theme.Colors.Background, 2)
		label.Parent = effects
		local tween = TweenService:Create(label, POPUP_TWEEN, {
			Position = label.Position - UDim2.fromOffset(0, rise),
			TextTransparency = 1,
		})
		TweenService:Create(stroke, POPUP_TWEEN, { Transparency = 1 }):Play()
		tween.Completed:Once(function()
			effectCount -= 1
			label:Destroy()
		end)
		tween:Play()
	end

	local function spawnSparks(position: Vector2, color: Color3)
		for index = 1, SPARKS_PER_HIT do
			if effectCount >= MAX_EFFECTS then
				return
			end
			effectCount += 1
			local spark = Instance.new("Frame")
			spark.Name = "Spark"
			spark.AnchorPoint = Vector2.new(0.5, 0.5)
			spark.Position = toPixels(position)
			spark.Size = UDim2.fromOffset(12, 12)
			spark.BackgroundColor3 = color
			spark.BorderSizePixel = 0
			spark.ZIndex = 6
			Components.addCorner(spark, UDim.new(0.5, 0))
			spark.Parent = effects
			local angle = (index / SPARKS_PER_HIT) * math.pi * 2 + math.random() * 0.5
			local distance = ballPixels * (0.6 + math.random() * 0.4)
			local tween = TweenService:Create(spark, SPARK_TWEEN, {
				Position = spark.Position + UDim2.fromOffset(math.cos(angle) * distance, math.sin(angle) * distance),
				Size = UDim2.fromOffset(3, 3),
				BackgroundTransparency = 1,
			})
			tween.Completed:Once(function()
				effectCount -= 1
				spark:Destroy()
			end)
			tween:Play()
		end
	end

	-- Ligação ao controller ------------------------------------------------------------
	trove:Add(ArrowController.Removed:Connect(function(id: number, reason: ArrowController.RemovedReason)
		local slot = slotById[id]
		local color = if slot then slot.Glyph.TextColor3 else Theme.Colors.Text
		if slot then
			release(slot)
		end
		local position = positions[id]
		if not position then
			return
		end
		if reason == "Hit" then
			spawnSparks(position, color)
		end
	end))

	local function renderCombo(combo: number, multiplier: number)
		if combo >= 2 then
			setText(comboLabel, string.format("COMBO %d · ×%.2f", combo, multiplier))
			comboScale.Scale = 1.15
			TweenService:Create(comboScale, Theme.Tween.Fast, { Scale = 1 }):Play()
		else
			setText(comboLabel, "")
		end
	end

	trove:Add(ArrowController.Result:Connect(function(event: ArrowEvent)
		if event.Kind == "Hit" then
			local position = positions[event.Id] or Vector2.new(0.5, 0.5)
			local gain = "+" .. NumberFormatter.format(BigNum.deserialize(event.Gain))
			if event.Auto then
				spawnPopup(position, "AUTO " .. gain, Theme.Colors.TextMuted, 26, 60)
			else
				local def = ArrowCalc.GetGradeDef(event.Grade)
				local color = if event.Grade == "Perfect" then Theme.Colors.Gold else Theme.Colors.Text
				spawnPopup(position, def.Label, color, 34, 50)
				spawnPopup(position + Vector2.new(0, 0.08), gain, Theme.Colors.Highlight, 24, 70)
				renderCombo(event.Combo, event.ComboMultiplier)
			end
		elseif event.Kind == "Miss" then
			local position = positions[event.Id] or Vector2.new(0.5, 0.5)
			spawnPopup(position, if event.Reason == "Wrong" then "ERRADO" else "FALHOU", Theme.Colors.Danger, 28, 40)
			renderCombo(0, 1)
			local slot = slotById[event.Id]
			if slot then
				-- abana a bolinha que continua no ecrã (seta errada)
				local base = slot.Button.Position
				slot.Button.Position = base + UDim2.fromOffset(8, 0)
				TweenService:Create(slot.Button, Theme.Tween.Fast, { Position = base }):Play()
			end
		end
	end))

	-- Atualização por frame (só propriedades; sem criar instâncias) ----------------------
	local function update()
		if not ArrowController.IsActive() then
			return
		end
		stamp += 1
		local now = serverNow()
		local minScale = clientConfig.MinBallScale
		for _, arrow in ArrowController.GetArrows() do
			if ArrowController.IsVisible(arrow, now) then
				local slot = slotById[arrow.Id] or acquire(arrow)
				if slot then
					slot.Stamp = stamp
					local progress = math.clamp(ArrowCalc.GetProgress(now, arrow.SpawnAt, arrow.Lifetime), 0, 1)
					slot.Scale.Scale = 1 - (1 - minScale) * progress
					local perfect = progress <= perfectMax
					slot.Ring.Color = if perfect then Theme.Colors.Text else Theme.Colors.TextMuted
					slot.Ring.Transparency = if perfect then 0 else 0.4
				end
			end
		end
		for _, slot in slots do
			if slot.Id ~= nil and slot.Stamp ~= stamp then
				release(slot)
			end
		end
	end
	trove:Connect(RunService.RenderStepped, update)

	-- Layout responsivo --------------------------------------------------------------
	local function updateLayout()
		local screenSize = screenGui.AbsoluteSize
		local scale = Components.computeScale(screenSize)
		local left, right = margins.Left * scale, margins.Right * scale
		local top, bottom = margins.Top * scale, margins.Bottom * scale
		zone.Position = UDim2.fromOffset(left, top)
		zone.Size = UDim2.new(1, -(left + right), 1, -(top + bottom))
		ballPixels = clientConfig.BallSize * scale
		comboLabel.TextSize = math.floor(34 * scale)
		autoScale.Scale = scale
		for _, slot in slots do
			slot.Button.Size = UDim2.fromOffset(ballPixels, ballPixels)
		end
	end
	trove:Connect(screenGui:GetPropertyChangedSignal("AbsoluteSize"), updateLayout)

	-- Estado --------------------------------------------------------------------
	local function renderActive(active: boolean)
		screenGui.Enabled = active
		if not active then
			for _, slot in slots do
				release(slot)
			end
			renderCombo(0, 1)
		else
			renderHint()
			renderAuto()
		end
	end

	trove:Add(ArrowController.ActiveChanged:Connect(renderActive))
	trove:Add(ArrowController.PausedChanged:Connect(function(paused: boolean)
		pausedLabel.Visible = paused
		hintLabel.Visible = not paused
	end))
	trove:Connect(UserInputService.LastInputTypeChanged, renderHint)

	screenGui.Parent = playerGui
	updateLayout()
	renderActive(ArrowController.IsActive())
end

function ArrowGameView.Unmount()
	local trove = activeTrove
	if trove then
		activeTrove = nil
		trove:Destroy()
	end
end

return ArrowGameView
