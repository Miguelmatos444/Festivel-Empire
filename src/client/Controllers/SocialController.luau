--!strict
--[[
	SocialController
	Cópia local (só de leitura) do estado social do próprio jogador (SocialSync),
	lista de festivais (a partir dos terrenos e dos atributos públicos FE_* que o
	servidor grava nos jogadores), estado do Headliner (calculado com a hora do
	servidor, igual ao servidor) e pedidos VISITAR / ❤ LIKE.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local MapConfig = require(ReplicatedStorage.Shared.Config.Map)
local SocialConfig = require(ReplicatedStorage.Shared.Config.Social)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local TokenBucket = require(ReplicatedStorage.Shared.Util.TokenBucket)
local MapCalc = require(ReplicatedStorage.Shared.Calc.MapCalc)
local SocialCalc = require(ReplicatedStorage.Shared.Calc.SocialCalc)
local NetController = require(script.Parent.NetController)

type SocialSync = Types.SocialSync
type HeadlinerState = Types.HeadlinerState

export type Festival = {
	PlotIndex: number,
	Player: Player,
	IsMine: boolean,
	StageTier: number,
	WorldTours: number,
	Likes: number,
	LikedToday: boolean,
}

local SocialController = {}

local changed: Signal.Signal<SocialSync> = Signal.new()

SocialController.Changed = changed

local trove = Trove.new()
local state: SocialSync? = nil
local bucket = TokenBucket.new(1, 2)

function SocialController.Get(): SocialSync?
	return state
end

function SocialController.GetHeadliner(): HeadlinerState
	return SocialCalc.ReadHeadliner(Workspace:GetServerTimeNow(), ReplicatedStorage)
end

local function numberAttribute(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function getPlotsFolder(): Instance?
	local map = Workspace:FindFirstChild("Map")
	return if map then map:FindFirstChild("Plots") else nil
end

-- Dono do terreno `index` (nil = livre)
function SocialController.GetPlotOwner(index: number): Player?
	local plots = getPlotsFolder()
	local plot = if plots then plots:FindFirstChild("Plot_" .. index) else nil
	local userId = if plot then plot:GetAttribute("OwnerUserId") else nil
	if type(userId) ~= "number" or userId <= 0 then
		return nil
	end
	return Players:GetPlayerByUserId(userId)
end

-- Festivais ocupados, o próprio primeiro e depois por tier
function SocialController.GetFestivals(): { Festival }
	local current = state
	local list: { Festival } = {}
	for index = 1, MapConfig.Plots.Count do
		local owner = SocialController.GetPlotOwner(index)
		if owner then
			table.insert(list, {
				PlotIndex = index,
				Player = owner,
				IsMine = owner == Players.LocalPlayer,
				StageTier = math.max(1, numberAttribute(owner, "FE_StageTier")),
				WorldTours = numberAttribute(owner, "FE_WorldTours"),
				Likes = numberAttribute(owner, "FE_Likes"),
				LikedToday = current ~= nil and current.LikedToday[tostring(owner.UserId)] == true,
			})
		end
	end
	table.sort(list, function(a: Festival, b: Festival): boolean
		if a.IsMine ~= b.IsMine then
			return a.IsMine
		end
		if a.WorldTours ~= b.WorldTours then
			return a.WorldTours > b.WorldTours
		end
		if a.StageTier ~= b.StageTier then
			return a.StageTier > b.StageTier
		end
		return a.PlotIndex < b.PlotIndex
	end)
	return list
end

-- Terreno onde a personagem local está (nil = praça)
function SocialController.GetCurrentPlotIndex(): number?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return nil
	end
	return MapCalc.GetPlotIndexAt(root.Position)
end

function SocialController.CanLike(owner: Player): (boolean, string?)
	if owner == Players.LocalPlayer then
		return false, nil
	end
	local current = state
	if not current then
		return false, nil
	end
	if current.LikedToday[tostring(owner.UserId)] then
		return false, "❤ JÁ DESTE LIKE HOJE"
	end
	if current.GivenToday >= SocialConfig.Likes.MaxGivenPerDay then
		return false, "SEM LIKES HOJE"
	end
	return true, nil
end

function SocialController.Visit(index: number): boolean
	if not bucket:TryConsume() then
		return false
	end
	NetController.Fire(RemoteDefs.Defs.VisitPlot, index)
	return true
end

function SocialController.GiveLike(index: number): boolean
	if not bucket:TryConsume() then
		return false
	end
	NetController.Fire(RemoteDefs.Defs.GiveLike, index)
	return true
end

function SocialController.Init()
	trove:Add(NetController.On(RemoteDefs.Defs.SocialSync, function(payload: unknown)
		local sync = payload :: SocialSync
		state = sync
		changed:Fire(sync)
	end))
end

return SocialController
