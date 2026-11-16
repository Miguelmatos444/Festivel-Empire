--!strict
--[[
	SideMenu
	Coluna única de botões à esquerda (VOLTAR · MELHORIAS · PALCOS · ARTISTAS · WORLD TOUR ·
	MISSÕES · FESTIVAIS), empilhada com UIListLayout para nunca se sobrepor à barra de
	drop nem entre si. Cada View cria o seu botão e chama SideMenu.Attach(holder, ordem).
	Botões invisíveis (ex.: VOLTAR perto do terreno) deixam de ocupar espaço.
	A coluna encolhe (UIScale) quando os botões não cabem na altura do ecrã (telemóvel).
	Estilo comum (Theme.SideButtons por ordem): cor própria com gradiente, ícone em cima,
	nome em baixo e tecla de atalho no canto. Aplicado depois de a View montar o botão
	(filhos "Button" > "Label"/"Hint").
]]

local Players = game:GetService("Players")

local Theme = require(script.Parent.Theme)

local SideMenu = {}

local BUTTON_SIZE = UDim2.fromOffset(112, 88)
local BUTTON_HEIGHT = 88
local PADDING = 10
local SCREEN_MARGIN = 24
local MIN_SCALE = 0.5

local container: Frame? = nil
local columnScale: UIScale? = nil
local screen: ScreenGui? = nil

-- Altura da coluna sem escala (calculada pelos botões visíveis, para evitar ciclos com o UIScale)
local function updateScale()
	local frame, scale, gui = container, columnScale, screen
	if not frame or not scale or not gui then
		return
	end
	local visible = 0
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") and child.Visible then
			visible += 1
		end
	end
	local height = visible * BUTTON_HEIGHT + math.max(visible - 1, 0) * PADDING
	local available = gui.AbsoluteSize.Y - SCREEN_MARGIN * 2
	if height <= 0 or available <= 0 then
		scale.Scale = 1
		return
	end
	scale.Scale = math.clamp(available / height, MIN_SCALE, 1)
end

local function getContainer(): Frame
	local existing = container
	if existing then
		return existing
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SideMenuGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	screenGui.DisplayOrder = 3 -- acima da barra de drop

	local frame = Instance.new("Frame")
	frame.Name = "Column"
	frame.AnchorPoint = Vector2.new(0, 0.5)
	frame.Position = UDim2.new(0, 16, 0.5, 0)
	frame.Size = UDim2.fromOffset(130, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, PADDING)
	layout.Parent = frame

	local scale = Instance.new("UIScale")
	scale.Parent = frame

	screenGui.Parent = playerGui
	container = frame
	columnScale = scale
	screen = screenGui
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScale)
	return frame
end

local function findChild(parent: Instance, name: string, className: string): Instance?
	local child = parent:FindFirstChild(name)
	if child and child:IsA(className) then
		return child
	end
	return nil
end

-- Cor, gradiente, ícone e disposição comuns a todos os botões laterais
local function decorate(holder: GuiObject, order: number)
	local style = Theme.SideButtons[order]
	local button = findChild(holder, "Button", "GuiButton") :: GuiButton?
	if not style or not button or button:FindFirstChild("Icon") then
		return
	end
	button.BackgroundColor3 = style.Color
	button.BackgroundTransparency = 0
	button:SetAttribute("BaseColor", style.Color)

	-- O gradiente multiplica a cor: mais claro em cima, mais escuro em baixo (funciona com qualquer cor/flash)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 165))
	gradient.Rotation = 90
	gradient.Parent = button

	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Transparency = 0.15
		stroke.Thickness = 3
	end

	local icon: GuiObject
	if style.ImageId > 0 then
		local image = Instance.new("ImageLabel")
		image.Image = "rbxassetid://" .. tostring(style.ImageId)
		image.ScaleType = Enum.ScaleType.Fit
		icon = image
	else
		local text = Instance.new("TextLabel")
		text.Font = Theme.Fonts.Display
		text.TextScaled = true
		text.TextColor3 = Color3.new(1, 1, 1)
		text.Text = style.Icon
		icon = text
	end
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.38)
	icon.Size = UDim2.fromScale(0.62, 0.52)
	icon.ZIndex = button.ZIndex + 1
	icon.Parent = button

	local label = findChild(button, "Label", "TextLabel") :: TextLabel?
	if label then
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.82)
		label.Size = UDim2.fromScale(0.92, 0.24)
		label.TextWrapped = false
		label.Text = (string.gsub(label.Text, "\n", " "))
		label.ZIndex = button.ZIndex + 1
		local constraint = label:FindFirstChildOfClass("UITextSizeConstraint")
		if constraint then
			constraint.MaxTextSize = 17
		end
	end

	local hint = findChild(button, "Hint", "TextLabel") :: TextLabel?
	if hint then
		hint.AnchorPoint = Vector2.new(1, 0)
		hint.Position = UDim2.new(1, -4, 0, 4)
		hint.Size = UDim2.fromScale(0.34, 0.2)
		hint.TextColor3 = Color3.new(1, 1, 1)
		hint.TextTransparency = 0.25
		hint.ZIndex = button.ZIndex + 1
	end
end

-- Move o botão (holder com o seu UIScale) para a coluna, na posição `order`
function SideMenu.Attach(holder: GuiObject, order: number)
	local style = Theme.SideButtons[order]
	if style and style.Hidden then
		return -- substituído por um posto no terreno: o botão nunca entra na coluna
	end
	holder.AnchorPoint = Vector2.zero
	holder.Position = UDim2.new()
	holder.Size = BUTTON_SIZE
	holder.LayoutOrder = order
	holder.Parent = getContainer()
	holder:GetPropertyChangedSignal("Visible"):Connect(updateScale)
	holder.Destroying:Once(function()
		task.defer(updateScale)
	end)
	updateScale()
	-- Algumas Views chamam Attach antes de criarem o botão: o estilo aplica-se no fim do Mount
	task.defer(decorate, holder, order)
end

return table.freeze(SideMenu)
