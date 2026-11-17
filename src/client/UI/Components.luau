--!strict
--[[
	Components
	Construtores de UI reutilizáveis e cálculo de escala responsiva.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local Components = {}

local PRESS_IN = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

--[[
	Resposta tátil de um botão: cresce um pouco com o rato por cima, encolhe logo ao
	carregar (rato, toque ou comando) e volta com uma mola ao largar. Usa o UIScale do
	botão (cria um se não houver). As ligações morrem com o botão.
]]
function Components.addPressFeedback(button: GuiButton, hoverScale: number?): UIScale
	local existing = button:FindFirstChildOfClass("UIScale")
	local scale: UIScale
	if existing then
		scale = existing
	else
		scale = Instance.new("UIScale")
		scale.Parent = button
	end
	local hovered = false
	local pressed = false
	local function apply(info: TweenInfo)
		local target = if pressed then 0.9 elseif hovered then (hoverScale or 1.05) else 1
		TweenService:Create(scale, info, { Scale = target }):Play()
	end
	button.MouseEnter:Connect(function()
		hovered = true
		apply(HOVER)
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		pressed = false
		apply(HOVER)
	end)
	button.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.ButtonA then
			pressed = true
			apply(PRESS_IN)
		end
	end)
	button.InputEnded:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.ButtonA then
			pressed = false
			if kind == Enum.UserInputType.Touch then
				hovered = false
			end
			apply(RELEASE)
		end
	end)
	return scale
end

-- Pequeno "pulo" de escala (ex.: um número que mudou): sobe até `amount` e volta com mola
function Components.bump(scale: UIScale, amount: number?)
	scale.Scale = amount or 1.08
	TweenService:Create(scale, RELEASE, { Scale = 1 }):Play()
end

function Components.addCorner(parent: GuiObject, radius: UDim): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
	return corner
end

function Components.addStroke(parent: GuiObject, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = parent
	return stroke
end

function Components.makeLabel(name: string, font: Enum.Font, color: Color3, maxTextSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextColor3 = color
	label.TextScaled = true
	label.Text = ""
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxTextSize
	constraint.Parent = label
	return label
end

function Components.makeFrame(name: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	return frame
end

function Components.makeButton(name: string, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	return button
end

-- Escala do HUD relativa à resolução de desenho (com limites para mobile/ecrãs grandes)
function Components.computeScale(screenSize: Vector2): number
	local layout = Theme.Layout
	if screenSize.X <= 0 or screenSize.Y <= 0 then
		return 1
	end
	return math.clamp(
		math.min(screenSize.X / layout.ReferenceSize.X, screenSize.Y / layout.ReferenceSize.Y),
		layout.MinScale,
		layout.MaxScale
	)
end

-- Escala para um painel de tamanho fixo caber no ecrã (fill = fração do ecrã utilizável)
function Components.fitScale(screenSize: Vector2, designSize: Vector2, fill: number): number
	if screenSize.X <= 0 or screenSize.Y <= 0 then
		return 1
	end
	return math.clamp(
		math.min(screenSize.X * fill / designSize.X, screenSize.Y * fill / designSize.Y),
		0.4,
		Theme.Layout.MaxScale
	)
end

return table.freeze(Components)
