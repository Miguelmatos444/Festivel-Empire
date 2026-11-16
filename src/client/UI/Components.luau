--!strict
--[[
	Components
	Construtores de UI reutilizáveis e cálculo de escala responsiva.
]]

local Theme = require(script.Parent.Theme)

local Components = {}

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
