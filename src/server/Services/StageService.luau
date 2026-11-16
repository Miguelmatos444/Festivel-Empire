--!strict
--[[
	StageService
	Coloca no terreno de cada jogador o palco do seu tier (ProfileData.StageTier),
	alinhado ao Attachment "StageOrigin" do PlotBase. O modelo vem de
	ServerStorage/Assets/Stages/Tier_XX ou do placeholder com as medidas exatas.
	(A animação de troca de palco fica para a fase da progressão de palcos.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StagesConfig = require(ReplicatedStorage.Shared.Config.Stages)
local MapCalc = require(ReplicatedStorage.Shared.Calc.MapCalc)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local Assets = require(script.Parent.Parent.World.Assets)
local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)
local PlotService = require(script.Parent.PlotService)
local PlayerStateService = require(script.Parent.PlayerStateService)

local StageService = {}

local trove = Trove.new()

local function clearStage(index: number)
	local model = MapService.GetPlotModel(index)
	local stage = if model then model:FindFirstChild("Stage") else nil
	if stage then
		stage:Destroy()
	end
end

-- Coloca (ou substitui) o palco do jogador. Devolve false se ainda faltar terreno ou perfil.
function StageService.PlaceStage(player: Player): boolean
	local index = PlotService.GetPlotId(player)
	local data = DataService.GetProfile(player)
	if not index or not data then
		return false
	end
	local model = MapService.GetPlotModel(index)
	local base = if model then model.PrimaryPart else nil
	local origin = if base then base:FindFirstChild("StageOrigin") else nil
	if not model or not origin or not origin:IsA("Attachment") then
		return false
	end

	clearStage(index)

	local def = MapCalc.GetStageDef(data.StageTier)
	local stage = Assets.GetStageTemplate(def.Tier):Clone()
	local root = Assets.GetRoot(stage)
	if not root then
		stage:Destroy()
		return false
	end
	stage.Name = "Stage"
	stage:SetAttribute("Tier", def.Tier)
	stage:SetAttribute("OwnerUserId", player.UserId)
	-- Root com a face da frente na linha StageOrigin, assente no chão, a crescer para trás
	Assets.PivotRoot(stage, origin.WorldCFrame * CFrame.new(0, root.Size.Y / 2, root.Size.Z / 2))
	stage.Parent = model

	PlotService.RefreshSign(index)
	return true
end

-- Debug: muda o tier sem requisitos (a progressão real vem numa fase seguinte)
function StageService.SetTier(player: Player, tier: number): boolean
	local data = DataService.GetProfile(player)
	if not data or tier < 1 or tier > StagesConfig.MaxTier or tier % 1 ~= 0 then
		return false
	end
	data.StageTier = tier
	PlayerStateService.MarkDirty(player)
	return StageService.PlaceStage(player)
end

function StageService.Init()
	trove:Add(DataService.ProfileLoaded:Connect(function(player: Player)
		StageService.PlaceStage(player)
	end))
	trove:Add(PlotService.PlotAssigned:Connect(function(player: Player)
		StageService.PlaceStage(player)
	end))
	trove:Add(PlotService.PlotReleased:Connect(function(_player: Player, index: number)
		clearStage(index)
	end))
end

function StageService.Start() end

return StageService
