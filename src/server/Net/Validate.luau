--!strict
--[[
	Validate
	Validação de argumentos vindos do cliente, a partir dos ArgSpec de RemoteDefs.
	Nunca confiar em nada que o cliente envia: tipos, NaN/inf, limites, tamanhos.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

type ArgSpec = Types.ArgSpec

local Validate = {}

function Validate.IsFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Validate.Arg(spec: ArgSpec, value: unknown): boolean
	if spec.Kind == "number" then
		if not Validate.IsFiniteNumber(value) then
			return false
		end
		local n = value :: number
		if spec.Integer and n % 1 ~= 0 then
			return false
		end
		local min = spec.Min
		if min and n < min then
			return false
		end
		local max = spec.Max
		if max and n > max then
			return false
		end
		return true
	elseif spec.Kind == "string" then
		if type(value) ~= "string" then
			return false
		end
		if #value > spec.MaxLength or utf8.len(value) == nil then
			return false
		end
		local pattern = spec.Pattern
		if pattern and string.match(value, pattern) == nil then
			return false
		end
		return true
	elseif spec.Kind == "boolean" then
		return type(value) == "boolean"
	elseif spec.Kind == "enum" then
		return type(value) == "string" and table.find(spec.Values, value) ~= nil
	end
	return false
end

-- Exige exatamente #specs argumentos (argumentos extra são rejeitados)
function Validate.Args(specs: { ArgSpec }, count: number, args: { unknown }): boolean
	if count ~= #specs then
		return false
	end
	for index, spec in specs do
		if not Validate.Arg(spec, args[index]) then
			return false
		end
	end
	return true
end

return table.freeze(Validate)
