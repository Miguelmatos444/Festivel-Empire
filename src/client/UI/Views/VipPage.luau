--!strict
--[[
	VipPage
	Conteúdo do separador "VIP" da loja: Gamepasses (ATIVO / comprar) e Developer
	Products. Preços em Robux lidos do Roblox (cache); IDs a 0 aparecem como "Em breve".
	A compra é feita pelo Roblox; o servidor entrega (ProcessReceipt / compra de Gamepass).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonetizationConfig = require(ReplicatedStorage.Shared.Config.Monetization)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)

local Client = script.Parent.Parent.Parent
local RetentionController = require(Client.Controllers.RetentionController)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)

type Row = {
	Key: string,
	Id: number,
	IsGamepass: boolean,
	Button: TextButton,
}

local CARD_HEIGHT = 78

local VipPage = {}

local function section(parent: Instance, text: string, order: number)
	local label = Components.makeLabel("Section", Theme.Fonts.Display, Theme.Colors.Gold, 20)
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, 26)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = parent
end

local function card(parent: Instance, order: number, name: string, description: string, accent: Color3): TextButton
	local frame = Instance.new("Frame")
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, CARD_HEIGHT)
	frame.BackgroundColor3 = Theme.Colors.Background
	frame.BorderSizePixel = 0
	Components.addCorner(frame, UDim.new(0, 14))
	Components.addStroke(frame, accent, 1.5).Transparency = 0.3
	frame.Parent = parent

	local nameLabel = Components.makeLabel("Name", Theme.Fonts.Display, Theme.Colors.Text, 20)
	nameLabel.Position = UDim2.fromOffset(16, 10)
	nameLabel.Size = UDim2.new(1, -210, 0, 24)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = name
	nameLabel.Parent = frame

	local descriptionLabel = Components.makeLabel("Description", Theme.Fonts.Body, Theme.Colors.TextMuted, 15)
	descriptionLabel.Position = UDim2.fromOffset(16, 38)
	descriptionLabel.Size = UDim2.new(1, -210, 0, 32)
	descriptionLabel.TextWrapped = true
	descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
	descriptionLabel.Text = description
	descriptionLabel.Parent = frame

	local button = Components.makeButton("Buy", Theme.Colors.Disabled)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -12, 0.5, 0)
	button.Size = UDim2.fromOffset(170, 54)
	button.Font = Theme.Fonts.Display
	button.TextColor3 = Theme.Colors.Text
	button.TextScaled = true
	Components.addCorner(button, UDim.new(0, 12))
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 20
	constraint.Parent = button
	button.Parent = frame
	return button
end

-- Constrói o separador dentro de `page` e devolve a função de atualização
function VipPage.Build(page: Instance, trove: Trove.Trove): () -> ()
	local list = Instance.new("ScrollingFrame")
	list.Name = "VipList"
	list.Position = UDim2.fromOffset(16, 6)
	list.Size = UDim2.new(1, -32, 1, -22)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Theme.Colors.Gold
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = page
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local padding = Instance.new("UIPadding")
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = list

	local rows: { Row } = {}
	section(list, "GAMEPASSES (permanentes)", 0)
	for index, def in MonetizationConfig.Gamepasses do
		local button = card(list, index, def.Name, def.Description, Theme.Colors.Gold)
		table.insert(rows, { Key = def.Key, Id = def.Id, IsGamepass = true, Button = button })
		trove:Connect(button.Activated, function()
			if not RetentionController.Owns(def.Key) then
				RetentionController.PromptGamepass(def.Id)
			end
		end)
	end
	section(list, "PACOTES", 100)
	for index, def in MonetizationConfig.Products do
		local button = card(list, 100 + index, def.Name, def.Description, Theme.Colors.Highlight)
		table.insert(rows, { Key = def.Key, Id = def.Id, IsGamepass = false, Button = button })
		trove:Connect(button.Activated, function()
			RetentionController.PromptProduct(def.Id)
		end)
	end

	local function refresh()
		for _, row in rows do
			if row.IsGamepass and RetentionController.Owns(row.Key) then
				row.Button.Text = "✓ ATIVO"
				row.Button.BackgroundColor3 = Theme.Colors.AccentDark
			else
				row.Button.Text = RetentionController.GetPriceText(row.Id, row.IsGamepass)
				row.Button.BackgroundColor3 = if row.Id > 0 then Theme.Colors.Success else Theme.Colors.Disabled
			end
		end
	end

	trove:Add(RetentionController.Changed:Connect(function()
		task.spawn(refresh)
	end))
	return refresh
end

return VipPage
