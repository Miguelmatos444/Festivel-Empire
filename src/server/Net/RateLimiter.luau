--!strict
--[[
	RateLimiter
	Token bucket por (jogador, chave). Cada pedido consome 1 token;
	os tokens repõem-se a `perSecond` até ao máximo `burst`.
]]

type Bucket = {
	Tokens: number,
	Last: number,
}

local RateLimiter = {}

local buckets: { [Player]: { [string]: Bucket } } = {}

function RateLimiter.Consume(player: Player, key: string, perSecond: number, burst: number): boolean
	local now = os.clock()

	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end

	local bucket = playerBuckets[key]
	if not bucket then
		bucket = { Tokens = burst, Last = now }
		playerBuckets[key] = bucket
	end

	bucket.Tokens = math.min(burst, bucket.Tokens + (now - bucket.Last) * perSecond)
	bucket.Last = now

	if bucket.Tokens < 1 then
		return false
	end
	bucket.Tokens -= 1
	return true
end

function RateLimiter.Clear(player: Player)
	buckets[player] = nil
end

return table.freeze(RateLimiter)
