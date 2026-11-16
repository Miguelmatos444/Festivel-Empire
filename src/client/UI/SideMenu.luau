--!strict
--[[
	SideMenu
	Coluna única de botões à esquerda (VOLTAR · LOJA · PALCOS · ARTISTAS · WORLD TOUR ·
	MISSÕES · FESTIVAIS), empilhada com UIListLayout para nunca se sobrepor à barra de
	drop nem entre si. Cada View cria o seu botão e chama SideMenu.Attach(holder, ordem).
	Botões invisíveis (ex.: VOLTAR perto do terreno) deixam de ocupar espaço.
	A coluna encolhe (UIScale) quando os botões não cabem na altura do ecrã (telemóvel).
]]

local Players = game:GetService("Players")

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

-- Move o botão (holder com o seu UIScale) para a coluna, na posição `order`
function SideMenu.Attach(holder: GuiObject, order: number)
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
end

return table.freeze(SideMenu)
