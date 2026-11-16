--!strict
--[[
	SideMenu
	Coluna única de botões à esquerda (VOLTAR · LOJA · PALCOS · ARTISTAS), empilhada
	com UIListLayout para nunca se sobrepor à barra de drop nem entre si.
	Cada View cria o seu botão e chama SideMenu.Attach(holder, ordem).
	Botões invisíveis (ex.: VOLTAR perto do terreno) deixam de ocupar espaço.
]]

local Players = game:GetService("Players")

local SideMenu = {}

local container: Frame? = nil

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
	layout.Padding = UDim.new(0, 10)
	layout.Parent = frame

	screenGui.Parent = playerGui
	container = frame
	return frame
end

-- Move o botão (holder com o seu UIScale) para a coluna, na posição `order`
local BUTTON_SIZE = UDim2.fromOffset(112, 88) -- 6 botões cabem num ecrã de telemóvel

function SideMenu.Attach(holder: GuiObject, order: number)
	holder.AnchorPoint = Vector2.zero
	holder.Position = UDim2.new()
	holder.Size = BUTTON_SIZE
	holder.LayoutOrder = order
	holder.Parent = getContainer()
end

return table.freeze(SideMenu)
