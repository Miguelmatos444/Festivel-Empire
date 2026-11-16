--!strict
--[[
	StageAnimController
	Anima localmente a troca de palco de QUALQUER terreno, a partir dos atributos que o
	StageService replica no Plot (TransitionId/Start/From/To/Era):

	  Desmontar  -> o "StageOld" afunda peça a peça (de cima para baixo) e desaparece
	  Pausa      -> só nas trocas de era: espetáculo de pirotecnia + impacto
	  Montar     -> o "Stage" novo sobe do chão peça a peça (de baixo para cima)

	O servidor coloca os modelos já na posição final; aqui só se mexe em CFrame/Transparency
	locais (nada replica). Tudo segue o relógio do servidor, por isso quem entra a meio vê a
	animação no ponto certo.

	LOD (Config/Lod.StageAnimation):
	  - terreno próprio ou a <= FullDistance: animação + efeitos + som (estes com o seu próprio LOD)
	  - até MaxDistance: só a animação
	  - além disso: salta direto para o resultado final
	Casos limite: o dono sai a meio (o servidor apaga os modelos) -> a animação termina sozinha;
	nova troca a meio de outra -> a anterior é concluída de imediato e a nova começa.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local LodConfig = require(ReplicatedStorage.Shared.Config.Lod)
local PyroConfig = require(ReplicatedStorage.Shared.Config.Pyro)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
local StageCalc = require(ReplicatedStorage.Shared.Calc.StageCalc)
local PyroVfxController = require(script.Parent.PyroVfxController)
local AudioController = require(script.Parent.AudioController)

type TransitionTiming = Types.TransitionTiming

type PartState = {
	Part: BasePart,
	Final: CFrame,
	Transparency: number,
	Delay: number, -- 0..STAGGER_SHARE: atraso relativo dentro da fase
	Offset: number, -- distância a afundar/subir
}

type Animation = {
	Plot: Model,
	Start: number,
	Timing: TransitionTiming,
	IsEra: boolean,
	Owner: Player?,
	WithEffects: boolean,
	Old: { PartState },
	New: { PartState },
	ShowPlayed: boolean,
	Banner: string?, -- texto em ecrã na pausa (World Tour)
}

local STAGGER_SHARE = 0.6 -- fração de cada fase usada para escalonar as peças
local MAX_STAGGERED_PARTS = 400 -- acima disto as restantes peças movem-se em bloco
local FIRST_DELAY_BUCKET = 0

local StageAnimController = {}

local trove = Trove.new()
local active: { [Model]: Animation } = {}

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function easeOutCubic(t: number): number
	return 1 - (1 - t) ^ 3
end

local function easeInCubic(t: number): number
	return t * t * t
end

local function collectParts(model: Instance?, buildingUp: boolean): { PartState }
	local result: { PartState } = {}
	if not model or not model:IsA("Model") then
		return result
	end
	local root = model:FindFirstChild("Root")
	local height = if root and root:IsA("BasePart") then root.Size.Y else 10

	local parts: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= root then
			table.insert(parts, descendant)
		end
	end
	-- Montar de baixo para cima; desmontar de cima para baixo
	table.sort(parts, function(a: BasePart, b: BasePart): boolean
		if buildingUp then
			return a.Position.Y < b.Position.Y
		end
		return a.Position.Y > b.Position.Y
	end)

	local staggered = math.min(#parts, MAX_STAGGERED_PARTS)
	for index, part in parts do
		local order = math.min(index, staggered)
		local delay = if staggered > 1 then (order - 1) / (staggered - 1) * STAGGER_SHARE else FIRST_DELAY_BUCKET
		table.insert(result, {
			Part = part,
			Final = part.CFrame,
			Transparency = part.Transparency,
			Delay = delay,
			Offset = height + 4,
		})
	end
	return result
end

local function partProgress(state: PartState, phaseProgress: number): number
	return math.clamp((phaseProgress - state.Delay) / (1 - STAGGER_SHARE), 0, 1)
end

local function applyOld(animation: Animation, phaseProgress: number)
	for _, state in animation.Old do
		local part = state.Part
		if part.Parent then
			local progress = partProgress(state, phaseProgress)
			part.CFrame = state.Final - Vector3.new(0, state.Offset * easeInCubic(progress), 0)
			part.Transparency = if progress >= 1 then 1 else state.Transparency
		end
	end
end

local function applyNew(animation: Animation, phaseProgress: number)
	for _, state in animation.New do
		local part = state.Part
		if part.Parent then
			local progress = partProgress(state, phaseProgress)
			if progress <= 0 then
				part.CFrame = state.Final - Vector3.new(0, state.Offset, 0)
				part.Transparency = 1
			else
				part.CFrame = state.Final - Vector3.new(0, state.Offset * (1 - easeOutCubic(progress)), 0)
				part.Transparency = state.Transparency
			end
		end
	end
end

-- Coloca tudo no estado final (palco novo no sítio, antigo escondido)
local function finish(animation: Animation)
	active[animation.Plot] = nil
	for _, state in animation.Old do
		if state.Part.Parent then
			state.Part.Transparency = 1
		end
	end
	for _, state in animation.New do
		if state.Part.Parent then
			state.Part.CFrame = state.Final
			state.Part.Transparency = state.Transparency
		end
	end
end

-- Faixa grande no ecrã (World Tour), visível para o dono e para quem está perto
local function showBanner(text: string)
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "WorldTourBanner"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.33)
	label.Size = UDim2.fromScale(0.8, 0.12)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 209, 102)
	label.TextStrokeTransparency = 0
	label.Text = text
	label.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = label
	gui.Parent = playerGui

	TweenService:Create(scale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(2.5, function()
		local fade = TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 })
		fade.Completed:Once(function()
			gui:Destroy()
		end)
		fade:Play()
	end)
end

local function playCelebration(animation: Animation, mask: number)
	if animation.ShowPlayed or not animation.WithEffects then
		return
	end
	animation.ShowPlayed = true
	local owner = animation.Owner
	if owner then
		PyroVfxController.PlayShow(owner, mask)
		AudioController.PlayForPlayer("Impact", owner)
	end
	local banner = animation.Banner
	if banner then
		showBanner(banner)
	end
end

local function step(animation: Animation): boolean
	local plot = animation.Plot
	if plot.Parent == nil then
		return false
	end
	local timing = animation.Timing
	local elapsed = serverNow() - animation.Start
	local buildStart = timing.Dismantle + timing.Pause
	local total = buildStart + timing.Build

	if elapsed < timing.Dismantle then
		applyOld(animation, elapsed / timing.Dismantle)
		applyNew(animation, 0)
	elseif elapsed < buildStart then
		applyOld(animation, 1)
		applyNew(animation, 0)
		if animation.IsEra then
			playCelebration(animation, PyroConfig.FullMask) -- troca de era: espetáculo completo
		end
	elseif elapsed < total then
		applyOld(animation, 1)
		applyNew(animation, (elapsed - buildStart) / timing.Build)
	else
		if not animation.IsEra then
			playCelebration(animation, 1) -- troca normal: faíscas no palco novo
		end
		return false
	end
	return true
end

local function update()
	for _, animation in active do
		if not step(animation) then
			finish(animation)
		end
	end
end

-- Arranque de uma transição ------------------------------------------------------

local function distanceToPlot(plot: Model): number
	local camera = Workspace.CurrentCamera
	local base = plot.PrimaryPart
	if not camera or not base then
		return math.huge
	end
	return (camera.CFrame.Position - base.Position).Magnitude
end

local function startTransition(plot: Model)
	local start = plot:GetAttribute("TransitionStart")
	local fromTier = plot:GetAttribute("TransitionFrom")
	local toTier = plot:GetAttribute("TransitionTo")
	if type(start) ~= "number" or type(fromTier) ~= "number" or type(toTier) ~= "number" then
		return
	end

	local previous = active[plot]
	if previous then
		finish(previous) -- nova troca a meio de outra: conclui a anterior
	end

	local kindAttribute = plot:GetAttribute("TransitionKind")
	local kind = if type(kindAttribute) == "string" then kindAttribute else nil
	local isPrestige = kind == "Prestige"
	local timing = StageCalc.GetTimingForKind(kind, fromTier, toTier)
	if serverNow() > start + StageCalc.GetTransitionDuration(timing) then
		return -- já terminou (ex.: entrou depois do fim)
	end

	local ownerId = plot:GetAttribute("OwnerUserId")
	local owner = if type(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
	local isOwn = owner == Players.LocalPlayer
	local distance = distanceToPlot(plot)
	local lod = LodConfig.StageAnimation

	local stage = plot:FindFirstChild("Stage") or plot:WaitForChild("Stage", 2)
	local old = plot:FindFirstChild("StageOld")

	if not isOwn and distance > lod.MaxDistance then
		-- Longe: sem animação — só garante que o palco antigo não aparece
		local oldParts = collectParts(old, false)
		for _, state in oldParts do
			state.Part.Transparency = 1
		end
		Diag.Log("StageAnim", string.format("%s: Tier %d→%d sem animação (LOD, %.0f studs)", plot.Name, fromTier, toTier, distance))
		return
	end

	local animation: Animation = {
		Plot = plot,
		Start = start,
		Timing = timing,
		IsEra = isPrestige or StageCalc.IsEraChange(fromTier, toTier), -- World Tour: espetáculo na pausa
		Owner = owner,
		WithEffects = isOwn or distance <= lod.FullDistance,
		Old = collectParts(old, false),
		New = collectParts(stage, true),
		ShowPlayed = false,
		Banner = nil,
	}
	if isPrestige then
		local tours = plot:GetAttribute("TransitionWorldTour")
		animation.Banner = string.format(
			"%sWORLD TOUR #%s",
			if owner and not isOwn then owner.DisplayName .. " · " else "",
			tostring(tours or "?")
		)
	end
	active[plot] = animation
	step(animation) -- aplica já o estado atual (evita um frame com o palco novo visível)
	Diag.Log(
		"StageAnim",
		string.format(
			"%s: Tier %d→%d%s (%d peças antigas, %d novas, efeitos=%s)",
			plot.Name,
			fromTier,
			toTier,
			if animation.IsEra then " [troca de era]" else "",
			#animation.Old,
			#animation.New,
			tostring(animation.WithEffects)
		)
	)
end

local function watchPlot(plot: Instance)
	if not plot:IsA("Model") then
		return
	end
	trove:Connect(plot:GetAttributeChangedSignal("TransitionId"), function()
		startTransition(plot)
	end)
	-- Entrou a meio de uma transição já em curso
	if plot:GetAttribute("TransitionStart") ~= nil then
		startTransition(plot)
	end
end

-- Ciclo de vida --------------------------------------------------------------

function StageAnimController.Init()
	trove:Connect(RunService.RenderStepped, update)
end

function StageAnimController.Start()
	trove:Add(task.spawn(function()
		local map = Workspace:WaitForChild("Map")
		local plots = map:WaitForChild("Plots")
		for _, plot in plots:GetChildren() do
			watchPlot(plot)
		end
		trove:Connect(plots.ChildAdded, watchPlot)
	end))
end

return StageAnimController
