--!strict
--[[
	Signal
	Eventos tipados em Luau puro (sem BindableEvent).
	Cada listener corre na sua própria thread (task.spawn), para que um erro
	num listener não impeça os restantes.
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
	Destroy: (self: Signal<T...>) -> (),
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local listeners: { [Connection]: (T...) -> () } = {}

	local function connect(callback: (T...) -> ()): Connection
		local connection: Connection = {
			Connected = true,
			Disconnect = function(self: Connection)
				if not self.Connected then
					return
				end
				self.Connected = false
				listeners[self] = nil
			end,
		}
		listeners[connection] = callback
		return connection
	end

	local function disconnectAll()
		for connection in listeners do
			connection.Connected = false
		end
		table.clear(listeners)
	end

	local signal: Signal<T...> = {
		Connect = function(_self: Signal<T...>, callback: (T...) -> ()): Connection
			return connect(callback)
		end,

		Once = function(_self: Signal<T...>, callback: (T...) -> ()): Connection
			local connection: Connection
			connection = connect(function(...: T...)
				connection:Disconnect()
				callback(...)
			end)
			return connection
		end,

		Fire = function(_self: Signal<T...>, ...: T...)
			for connection, callback in table.clone(listeners) do
				if connection.Connected then
					task.spawn(callback, ...)
				end
			end
		end,

		DisconnectAll = function(_self: Signal<T...>)
			disconnectAll()
		end,

		Destroy = function(_self: Signal<T...>)
			disconnectAll()
		end,
	}

	return signal
end

return table.freeze(Signal)
