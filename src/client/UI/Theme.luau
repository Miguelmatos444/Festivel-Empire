--!strict
--[[
	Theme
	Paleta, fontes, tamanhos e animações partilhados por todas as Views.
]]

local Theme = table.freeze({
	Colors = table.freeze({
		Background = Color3.fromRGB(20, 11, 46),
		Panel = Color3.fromRGB(34, 20, 70),
		Accent = Color3.fromRGB(255, 60, 172),
		AccentDark = Color3.fromRGB(120, 75, 255),
		Highlight = Color3.fromRGB(43, 210, 255),
		Gold = Color3.fromRGB(255, 209, 102),
		Text = Color3.fromRGB(255, 255, 255),
		TextMuted = Color3.fromRGB(190, 180, 220),
		Success = Color3.fromRGB(57, 217, 138),
		Danger = Color3.fromRGB(255, 77, 109),
		Disabled = Color3.fromRGB(70, 62, 98),
		Overlay = Color3.fromRGB(0, 0, 0),
	}),

	-- Cor de destaque por categoria de equipamento
	CategoryColors = table.freeze({
		Colunas = Color3.fromRGB(43, 210, 255),
		Mesas = Color3.fromRGB(255, 60, 172),
		DJs = Color3.fromRGB(255, 209, 102),
		Batidas = Color3.fromRGB(160, 120, 255),
	}),

	DropBar = table.freeze({
		ColumnSize = Vector2.new(190, 400),
		DropButtonSize = 200,
		TriggerKey = Enum.KeyCode.F,
		TriggerGamepadButton = Enum.KeyCode.ButtonR1,
		ResultDuration = 1.6,
	}),

	Stages = table.freeze({
		PanelSize = Vector2.new(660, 560),
		CardHeight = 116,
		PreviewSize = Vector2.new(120, 96),
		PreviewStudScale = 0.85, -- píxeis por stud nas silhuetas (mesma escala em todos os tiers)
		ToggleKey = Enum.KeyCode.P,
		ToggleGamepadButton = Enum.KeyCode.ButtonX,
		RefreshInterval = 0.5,
	}),

	Shop = table.freeze({
		PanelSize = Vector2.new(600, 520), -- tamanho de desenho; escalado para caber no ecrã
		ScreenFill = 0.92,
		CardHeight = 92,
		OverlayTransparency = 0.45,
		ToggleKey = Enum.KeyCode.B,
		ToggleGamepadButton = Enum.KeyCode.ButtonY,
	}),

	Fonts = table.freeze({
		Display = Enum.Font.FredokaOne,
		Body = Enum.Font.GothamBold,
	}),

	Radius = table.freeze({
		Panel = 18,
		Toast = 14,
	}),

	Tween = table.freeze({
		Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Counter = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Float = TweenInfo.new(0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		Ring = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Toast = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		FadeOut = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	}),

	Layout = table.freeze({
		ReferenceSize = Vector2.new(1280, 720), -- resolução de desenho
		MinScale = 0.6, -- telemóveis
		MaxScale = 1.35, -- ecrãs grandes / consola
	}),

	MaxFloatingTexts = 12,
	MaxToasts = 3,
	ToastDuration = 5,
})

return Theme
