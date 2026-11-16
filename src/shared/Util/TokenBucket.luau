--!strict
--[[
	TokenBucket
	Limitador local simples: cada TryConsume gasta 1 token; os tokens
	repõem-se a `perSecond` até ao máximo `burst`.
	(O servidor usa RateLimiter, que guarda um bucket por jogador.)
]]

export type TokenBucket = {
	TryConsume: (self: TokenBucket) -> boolean,
}

local TokenBucket = {}

function TokenBucket.new(perSecond: number, burst: number): TokenBucket
	local tokens = burst
	local last = os.clock()

	local bucket: TokenBucket = {
		TryConsume = function(_self: TokenBucket): boolean
			local now = os.clock()
			tokens = math.min(burst, tokens + (now - last) * perSecond)
			last = now
			if tokens < 1 then
				return false
			end
			tokens -= 1
			return true
		end,
	}
	return bucket
end

return table.freeze(TokenBucket)
