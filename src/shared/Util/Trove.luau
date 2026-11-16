--!strict
--[[
	Trove
	Agrupa recursos para limpeza conjunta: RBXScriptConnection, Instance,
	funções de limpeza, threads e tabelas com :Destroy() ou :Disconnect().
	A limpeza é feita por ordem inversa de adição (LIFO).
]]

local Trove = {}
Trove.__index = Trove

type TroveData = {
	_objects: { unknown },
	_cleaning: boolean,
}

export type Trove = typeof(setmetatable({} :: TroveData, Trove))

local function isCleanable(object: unknown): boolean
	local kind = typeof(object)
	if kind == "RBXScriptConnection" or kind == "Instance" or kind == "function" or kind == "thread" then
		return true
	end
	if kind == "table" then
		local t = object :: { [string]: unknown }
		return type(t.Destroy) == "function" or type(t.Disconnect) == "function"
	end
	return false
end

local function cleanObject(object: unknown)
	local kind = typeof(object)
	if kind == "RBXScriptConnection" then
		(object :: RBXScriptConnection):Disconnect()
	elseif kind == "Instance" then
		(object :: Instance):Destroy()
	elseif kind == "function" then
		(object :: () -> ())()
	elseif kind == "thread" then
		local thread = object :: thread
		if coroutine.running() ~= thread then
			pcall(task.cancel, thread)
		end
	elseif kind == "table" then
		local t = object :: { [string]: unknown }
		local method = if type(t.Destroy) == "function" then t.Destroy else t.Disconnect
		if type(method) == "function" then
			(method :: (unknown) -> ())(t)
		end
	end
end

function Trove.new(): Trove
	local data: TroveData = {
		_objects = {},
		_cleaning = false,
	}
	return setmetatable(data, Trove)
end

-- Adiciona um recurso e devolve-o (permite `local x = trove:Add(Instance.new(...))`)
function Trove.Add<T>(self: Trove, object: T): T
	assert(not self._cleaning, "Trove: não é possível adicionar durante a limpeza")
	assert(isCleanable(object), "Trove: tipo de objeto não suportado: " .. typeof(object))
	table.insert(self._objects, object)
	return object
end

function Trove.Connect(self: Trove, signal: RBXScriptSignal, callback: (...any) -> ()): RBXScriptConnection
	return self:Add(signal:Connect(callback))
end

-- Cria uma Trove filha que é limpa juntamente com esta
function Trove.Extend(self: Trove): Trove
	return self:Add(Trove.new())
end

-- Remove e limpa imediatamente um objeto específico
function Trove.Remove(self: Trove, object: unknown): boolean
	local index = table.find(self._objects, object)
	if not index then
		return false
	end
	table.remove(self._objects, index)
	cleanObject(object)
	return true
end

function Trove.Clean(self: Trove)
	if self._cleaning then
		return
	end
	self._cleaning = true
	local objects = self._objects
	self._objects = {}
	for index = #objects, 1, -1 do
		cleanObject(objects[index])
	end
	self._cleaning = false
end

function Trove.Destroy(self: Trove)
	self:Clean()
end

return Trove
