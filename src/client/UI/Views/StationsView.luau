--!strict
--[[
	StationsView
	Lado do cliente dos postos à entrada de cada terreno (criados pelo World/Stations):
	  - ProximityPrompt "Abrir" → abre o painel correspondente (Melhorias, Artistas/Crates,
	    Palcos, World Tour, Missões, Loja VIP);
	  - só os prompts do próprio terreno ficam ativos (os outros escondidos localmente);
	  - subtítulos vivos no próprio terreno: WORLD TOUR "Pronto!" (dourado) e MISSÕES
	    "N por reclamar";
	  - títulos a balançar suavemente.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local StationsConfig = require(ReplicatedStorage.Shared.Config.Stations)
local MonetizationConfig = require(ReplicatedStorage.Shared.Config.Monetization)
local BigNum = require(ReplicatedStorage.Shared.Util.BigNum)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local PrestigeCalc = require(ReplicatedStorage.Shared.Calc.PrestigeCalc)

local Client = script.Parent.Parent.Parent
local StateController = require(Client.Controllers.StateController)
local RetentionController = require(Client.Controllers.RetentionController)
local ShopView = require(script.Parent.ShopView)
local ArtistsView = require(script.Parent.ArtistsView)
local StagesView = require(script.Parent.StagesView)
local PrestigeView = require(script.Parent.PrestigeView)
local MissionsView = require(script.Parent.MissionsView)

local HINT_REFRESH_SECONDS = 1
local GOLD = Color3.fromRGB(255, 209, 102)

local StationsView = {}

local activeTrove: Trove.Trove? = nil

local OPENERS: { [string]: () -> () } = {
	Upgrades = function()
		ShopView.Open()
	end,
	Artists = function()
		ArtistsView.Open("Crates")
	end,
	Stages = function()
		StagesView.Open()
	end,
	WorldTour = function()
		PrestigeView.Open()
	end,
	Missions = function()
		MissionsView.Open()
	end,
	Vip = function()
		ShopView.Open("Vip")
	end,
}

local function getPlotOf(instance: Instance): Instance?
	local current: Instance? = instance.Parent
	while current do
		if type(current:GetAttribute("PlotId")) == "number" then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function isMine(plot: Instance?): boolean
	return plot ~= nil and plot:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId
end

function StationsView.Mount()
	if activeTrove or not StationsConfig.Enabled then
		return
	end
	local trove = Trove.new()
	activeTrove = trove

	local prompts: { [ProximityPrompt]: Instance? } = {} -- prompt -> terreno
	local titles: { [string]: { BillboardGui } } = {} -- StationId -> títulos (todos os terrenos)

	local function refreshPrompt(prompt: ProximityPrompt)
		prompt.Enabled = isMine(prompts[prompt])
	end

	local function addInstance(instance: Instance)
		if instance:IsA("ProximityPrompt") and instance.Name == StationsConfig.PromptName then
			prompts[instance] = getPlotOf(instance)
			refreshPrompt(instance)
		elseif instance:IsA("BillboardGui") and instance.Name == "Title" then
			local station = instance:FindFirstAncestorWhichIsA("Model")
			while station and station:GetAttribute("StationId") == nil do
				station = station:FindFirstAncestorWhichIsA("Model")
			end
			local id = if station then station:GetAttribute("StationId") else nil
			if type(id) == "string" then
				local list = titles[id] or {}
				titles[id] = list
				table.insert(list, instance)
				local tween = TweenService:Create(
					instance,
					TweenInfo.new(StationsConfig.BobSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ StudsOffset = Vector3.new(0, StationsConfig.BobHeight, 0) }
				)
				tween:Play()
				trove:Add(function()
					tween:Cancel()
				end)
			end
		end
	end

	-- Subtítulo (e cor do contorno) dos títulos do próprio terreno
	local function setHint(id: string, text: string?, highlight: boolean)
		local def = StationsConfig.ById[id]
		for _, billboard in titles[id] or {} do
			if billboard.Parent and isMine(getPlotOf(billboard)) then
				local hint = billboard:FindFirstChild("HintLabel")
				if hint and hint:IsA("TextLabel") then
					local value = text or def.Hint
					if hint.Text ~= value then
						hint.Text = value
					end
					hint.TextColor3 = if highlight then GOLD else def.Color:Lerp(Color3.new(1, 1, 1), 0.55)
				end
				local title = billboard:FindFirstChild("TitleLabel")
				local stroke = if title then title:FindFirstChildOfClass("UIStroke") else nil
				if stroke then
					stroke.Color = if highlight then GOLD else def.Color
				end
			end
		end
	end

	local function refreshHints()
		local snapshot = StateController.Get()
		if snapshot then
			local agentBonus = if RetentionController.Owns("TourAgent") then MonetizationConfig.TourAgentDiscBonus else 0
			local discs = PrestigeCalc.GetDiscsPreview(
				BigNum.deserialize(snapshot.RunHypeEarned),
				snapshot.StageTier,
				snapshot.SkillTree,
				agentBonus
			)
			local can = PrestigeCalc.CanWorldTour(snapshot.StageTier, discs)
			setHint("WorldTour", if can then "PRONTO! ✈" else nil, can)
		end
		local sync = RetentionController.Get()
		if sync then
			local claimable = MissionsView.CountClaimable(sync)
			setHint("Missions", if claimable > 0 then string.format("%d por reclamar!", claimable) else nil, claimable > 0)
		end
	end

	-- Ligação ao mapa (também apanha o que chega mais tarde com StreamingEnabled)
	trove:Add(task.spawn(function()
		local map = Workspace:WaitForChild("Map")
		for _, descendant in map:GetDescendants() do
			addInstance(descendant)
		end
		trove:Connect(map.DescendantAdded, addInstance)
		local plots = map:WaitForChild("Plots")
		local function watchPlot(plot: Instance)
			trove:Connect(plot:GetAttributeChangedSignal("OwnerUserId"), function()
				for prompt, promptPlot in prompts do
					if promptPlot == plot then
						refreshPrompt(prompt)
					end
				end
				refreshHints()
			end)
		end
		for _, plot in plots:GetChildren() do
			watchPlot(plot)
		end
		trove:Connect(plots.ChildAdded, watchPlot)
		while true do
			refreshHints()
			task.wait(HINT_REFRESH_SECONDS)
		end
	end))

	trove:Connect(ProximityPromptService.PromptTriggered, function(prompt: ProximityPrompt, player: Player)
		if player ~= Players.LocalPlayer or prompt.Name ~= StationsConfig.PromptName then
			return
		end
		local id = prompt:GetAttribute("StationId")
		local open = if type(id) == "string" then OPENERS[id] else nil
		if open and isMine(prompts[prompt] or getPlotOf(prompt)) then
			open()
		end
	end)
end

function StationsView.Unmount()
	local trove = activeTrove
	if trove then
		activeTrove = nil
		trove:Destroy()
	end
end

return StationsView
