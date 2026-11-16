--!strict
--[[
	SocialCalc
	Cálculos puros partilhados (servidor cobra, cliente mostra):
	  - bónus de amigos, grupo e Likes
	  - estado do evento global Headliner a partir da hora do servidor (Unix UTC),
	    igual em todos os servidores; os overrides de debug vêm de atributos
	    replicados em ReplicatedStorage (HeadlinerOverrideEndsAt / HeadlinerSuppressUntil)
]]

local SocialConfig = require(script.Parent.Parent.Config.Social)
local Types = require(script.Parent.Parent.Types)

type HeadlinerState = Types.HeadlinerState

local SocialCalc = {}

SocialCalc.OverrideAttribute = "HeadlinerOverrideEndsAt"
SocialCalc.SuppressAttribute = "HeadlinerSuppressUntil"

function SocialCalc.GetFriendsBonus(friends: number): number
	local config = SocialConfig.Friends
	return math.clamp(math.floor(friends), 0, config.MaxFriends) * config.BonusPerFriend
end

function SocialCalc.GetGroupBonus(inGroup: boolean): number
	return if inGroup and SocialConfig.Group.GroupId > 0 then SocialConfig.Group.Bonus else 0
end

function SocialCalc.GetLikesBonus(likes: number): number
	local config = SocialConfig.Likes
	local steps = math.floor(math.max(likes, 0) / config.LikesPerStep)
	return math.min(config.MaxBonus, steps * config.BonusPerStep)
end

-- Multiplicador Social completo = (1 + amigos) × (1 + grupo) × (1 + Likes) × Headliner
function SocialCalc.GetMultiplier(friends: number, inGroup: boolean, likes: number, headlinerActive: boolean): number
	return (1 + SocialCalc.GetFriendsBonus(friends))
		* (1 + SocialCalc.GetGroupBonus(inGroup))
		* (1 + SocialCalc.GetLikesBonus(likes))
		* (if headlinerActive then SocialConfig.Headliner.HypeMultiplier else 1)
end

--[[
	Estado do Headliner no instante `now` (hora do servidor, segundos Unix).
	overrideEndsAt: /fe headliner start (ativo até essa hora)
	suppressUntil: /fe headliner stop (inativo até essa hora)
]]
function SocialCalc.GetHeadliner(now: number, overrideEndsAt: number?, suppressUntil: number?): HeadlinerState
	local config = SocialConfig.Headliner
	if overrideEndsAt and now < overrideEndsAt then
		return { Active = true, StartsAt = overrideEndsAt - config.Duration, EndsAt = overrideEndsAt }
	end
	local cycleStart = math.floor((now - config.Offset) / config.Interval) * config.Interval + config.Offset
	local active = now < cycleStart + config.Duration
	if active and suppressUntil and now < suppressUntil then
		active = false
	end
	local startsAt = if active then cycleStart else cycleStart + config.Interval
	-- Sem override: o próximo evento nunca começa antes do fim de um "stop"
	if not active and now < cycleStart + config.Duration then
		startsAt = cycleStart + config.Interval
	end
	return { Active = active, StartsAt = startsAt, EndsAt = startsAt + config.Duration }
end

-- Lê os overrides de debug de uma instância (ReplicatedStorage) e devolve o estado
function SocialCalc.ReadHeadliner(now: number, holder: Instance): HeadlinerState
	local override = holder:GetAttribute(SocialCalc.OverrideAttribute)
	local suppress = holder:GetAttribute(SocialCalc.SuppressAttribute)
	return SocialCalc.GetHeadliner(
		now,
		if type(override) == "number" then override else nil,
		if type(suppress) == "number" then suppress else nil
	)
end

return table.freeze(SocialCalc)
