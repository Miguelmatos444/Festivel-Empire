--!strict
--[[
	DataService
	Persistência de perfis com session locking sobre DataStore (UpdateAsync).

	Formato gravado por chave:
	  { Data = ProfileData, Lock = { JobId, Time }? }

	- Load: adquire o lock; se outro servidor ativo o tiver, espera e tenta de novo.
	- Auto-save a cada AutoSaveInterval (renova o lock).
	- PlayerRemoving / BindToClose: save final + libertação do lock.
	- Um lock sem renovação há mais de SessionLockTimeout é considerado abandonado.
	- Se outra sessão tomar o lock, este servidor nunca sobrescreve: expulsa o jogador.
	- Em Studio sem acesso à API, usa uma store em memória (aviso no Output).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Shared.Types)
local DataConfig = require(ReplicatedStorage.Shared.Config.Data)
local BigNum = require(ReplicatedStorage.Shared.Util.BigNum)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
local ProfileTemplate = require(script.Parent.Parent.Data.ProfileTemplate)
local Migrations = require(script.Parent.Parent.Data.Migrations)

type ProfileData = Types.ProfileData
type RawData = { [string]: unknown }
type Transform = (old: unknown) -> unknown -- devolver nil cancela a escrita

type Store = {
	Update: (key: string, transform: Transform) -> (),
}

type Lock = {
	JobId: string,
	Time: number,
}

type Session = {
	Player: Player,
	Key: string,
	Data: ProfileData,
	PlayTimeMark: number,
	Saving: boolean,
	Released: boolean,
}

type AcquireResult = "Loaded" | "Locked" | "Failed"

local KICK_LOAD_FAILED = "Não foi possível carregar os teus dados. Tenta entrar novamente."
local KICK_LOCKED = "A tua sessão ainda está aberta noutro servidor. Tenta novamente daqui a pouco."
local KICK_NEWER_DATA = "Os teus dados são de uma versão mais recente do jogo. Entra noutro servidor."
local KICK_STOLEN = "A tua sessão foi aberta noutro servidor."

local DataService = {}

local profileLoaded: Signal.Signal<Player, ProfileData> = Signal.new()
local profileReleasing: Signal.Signal<Player, ProfileData> = Signal.new()

-- Disparado quando um perfil fica disponível (também após ResetProfile).
DataService.ProfileLoaded = profileLoaded
-- Disparado imediatamente antes do save final de um jogador que sai.
DataService.ProfileReleasing = profileReleasing

local trove = Trove.new()
local store: Store
local usingMock = false
local sessions: { [Player]: Session } = {}
local loading: { [Player]: boolean } = {}
local pendingReleases = 0

-- Utilitários ----------------------------------------------------------------

local function deepCopy(value: unknown): unknown
	if type(value) ~= "table" then
		return value
	end
	local source = value :: { [unknown]: unknown }
	local copy: { [unknown]: unknown } = {}
	for key, child in source do
		copy[key] = deepCopy(child)
	end
	return copy
end

local function asRecord(value: unknown): RawData
	if type(value) == "table" then
		return value :: RawData
	end
	return {}
end

local function readLock(value: unknown): Lock?
	if type(value) ~= "table" then
		return nil
	end
	local t = value :: RawData
	local jobId, time = t.JobId, t.Time
	if type(jobId) == "string" and type(time) == "number" then
		return { JobId = jobId, Time = time }
	end
	return nil
end

local IGNORE_LOCKS = RunService:IsStudio() and DataConfig.IgnoreSessionLockInStudio

local function isLockedByOther(lock: Lock?): boolean
	if not lock or IGNORE_LOCKS then
		return false
	end
	return lock.JobId ~= game.JobId and os.time() - lock.Time < DataConfig.SessionLockTimeout
end

local function newLock(): Lock
	return { JobId = game.JobId, Time = os.time() }
end

-- Converte os campos BigNum para valores normalizados e congelados
local function hydrate(data: ProfileData)
	data.Hype = BigNum.deserialize(data.Hype)
	data.TotalHypeEarned = BigNum.deserialize(data.TotalHypeEarned)
	data.RunHypeEarned = BigNum.deserialize(data.RunHypeEarned)
end

local function withRetries(label: string, callback: () -> ()): (boolean, string?)
	local attempts = DataConfig.RequestRetryAttempts
	local lastError: string? = nil
	for attempt = 1, attempts do
		local ok, err = pcall(callback)
		if ok then
			return true, nil
		end
		lastError = tostring(err)
		warn(string.format("[DataService] %s falhou (%d/%d): %s", label, attempt, attempts, lastError))
		if attempt < attempts then
			task.wait(DataConfig.RequestRetryBaseDelay * 2 ^ (attempt - 1))
		end
	end
	return false, lastError
end

-- Stores ---------------------------------------------------------------------

local function createRealStore(): Store
	local dataStore = DataStoreService:GetDataStore(DataConfig.StoreName)
	return {
		Update = function(key: string, transform: Transform)
			dataStore:UpdateAsync(key, function(old: unknown)
				return transform(old)
			end)
		end,
	}
end

local function createMockStore(): Store
	local memory: { [string]: unknown } = {}
	return {
		Update = function(key: string, transform: Transform)
			local result = transform(deepCopy(memory[key]))
			if result ~= nil then
				memory[key] = deepCopy(result)
			end
		end,
	}
end

local function selectStore(): (Store, boolean)
	if not RunService:IsStudio() then
		return createRealStore(), false
	end
	local ok, result = pcall(function(): Store
		local realStore = createRealStore()
		-- Leitura de teste: falha se o Studio não tiver acesso às APIs
		DataStoreService:GetDataStore(DataConfig.StoreName):GetAsync("__studio_probe")
		return realStore
	end)
	if ok then
		return result, false
	end
	if not DataConfig.UseMockInStudioWithoutApi then
		error("[DataService] DataStore indisponível em Studio: " .. tostring(result))
	end
	warn("[DataService] Studio sem acesso à API de DataStore — a usar store EM MEMÓRIA (nada será gravado).")
	return createMockStore(), true
end

-- Lock / load ----------------------------------------------------------------

local function tryAcquire(key: string): (AcquireResult, RawData?)
	local lockedByOther = false
	local loaded: RawData? = nil

	local ok = withRetries("load " .. key, function()
		store.Update(key, function(old: unknown): unknown
			local record = asRecord(old)
			if isLockedByOther(readLock(record.Lock)) then
				lockedByOther = true
				loaded = nil
				return nil
			end
			lockedByOther = false

			local data: unknown = record.Data
			if type(data) ~= "table" then
				data = ProfileTemplate.Create()
				record.Data = data
			end
			record.Lock = newLock()
			loaded = data :: RawData
			return record
		end)
	end)

	if not ok then
		return "Failed", nil
	end
	if lockedByOther then
		return "Locked", nil
	end
	return "Loaded", loaded
end

local function releaseLockOnly(key: string)
	withRetries("release " .. key, function()
		store.Update(key, function(old: unknown): unknown
			local record = asRecord(old)
			local lock = readLock(record.Lock)
			if lock and lock.JobId == game.JobId then
				record.Lock = nil
				return record
			end
			return nil
		end)
	end)
end

local function loadProfile(player: Player)
	if loading[player] or sessions[player] then
		return
	end
	loading[player] = true

	local key = DataConfig.KeyPrefix .. player.UserId
	local raw: RawData? = nil
	local startedAt = os.clock()
	Diag.Log("Data", string.format("a carregar o perfil de %s (%s)", player.Name, if usingMock then "memória" else "DataStore"))

	for attempt = 1, DataConfig.LockRetryAttempts do
		if player.Parent ~= Players then
			loading[player] = nil
			return -- saiu antes de adquirirmos o lock
		end
		local result, data = tryAcquire(key)
		if result == "Loaded" then
			raw = data
			break
		elseif result == "Failed" then
			loading[player] = nil
			warn(string.format("[DataService] Falha ao carregar o perfil de %s; jogador expulso.", player.Name))
			player:Kick(KICK_LOAD_FAILED)
			return
		end
		warn(
			string.format(
				"[DataService] Perfil de %s bloqueado por outra sessão (tentativa %d/%d). Cliques e Bass Drop ficam parados até carregar.",
				player.Name,
				attempt,
				DataConfig.LockRetryAttempts
			)
		)
		if attempt < DataConfig.LockRetryAttempts then
			task.wait(DataConfig.LockRetryDelay)
		end
	end

	loading[player] = nil

	if not raw then
		player:Kick(KICK_LOCKED)
		return
	end

	if player.Parent ~= Players then
		releaseLockOnly(key) -- saiu durante o load: liberta sem alterar dados
		return
	end

	local migrated, reason = Migrations.Run(raw)
	if not migrated then
		warn(string.format("[DataService] Perfil de %s não utilizável: %s", player.Name, tostring(reason)))
		releaseLockOnly(key)
		player:Kick(KICK_NEWER_DATA)
		return
	end

	ProfileTemplate.Reconcile(raw)
	local data = (raw :: unknown) :: ProfileData
	hydrate(data)

	sessions[player] = {
		Player = player,
		Key = key,
		Data = data,
		PlayTimeMark = os.clock(),
		Saving = false,
		Released = false,
	}

	Diag.Log("Data", string.format("perfil de %s carregado em %.2f s", player.Name, os.clock() - startedAt))
	profileLoaded:Fire(player, data)
end

-- Save -----------------------------------------------------------------------

local function saveSession(session: Session, release: boolean): boolean
	while session.Saving do
		task.wait(0.1) -- no máximo um save em curso por sessão
	end
	if session.Released then
		return true
	end
	session.Saving = true

	local now = os.clock()
	session.Data.Stats.PlayTime += now - session.PlayTimeMark
	session.PlayTimeMark = now
	session.Data.LastOnline = os.time()

	local snapshot = deepCopy(session.Data)
	local stolen = false

	local ok = withRetries("save " .. session.Key, function()
		store.Update(session.Key, function(old: unknown): unknown
			local record = asRecord(old)
			if isLockedByOther(readLock(record.Lock)) then
				stolen = true
				return nil
			end
			stolen = false
			record.Data = snapshot
			record.Lock = if release then nil else newLock()
			return record
		end)
	end)

	session.Saving = false
	if release then
		session.Released = true
	end

	if stolen then
		session.Released = true
		if sessions[session.Player] == session then
			sessions[session.Player] = nil
		end
		warn(string.format("[DataService] Lock de %s tomado por outro servidor; save cancelado.", session.Player.Name))
		session.Player:Kick(KICK_STOLEN)
		return false
	end

	return ok
end

local function releaseSession(player: Player, session: Session)
	if sessions[player] == session then
		sessions[player] = nil
	end
	pendingReleases += 1
	profileReleasing:Fire(player, session.Data)
	saveSession(session, true)
	pendingReleases -= 1
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if session then
		releaseSession(player, session)
	end
end

local function onBindToClose()
	local toRelease: { Session } = {}
	for _, session in sessions do
		table.insert(toRelease, session)
	end
	for _, session in toRelease do
		task.spawn(releaseSession, session.Player, session)
	end

	if usingMock then
		return
	end
	local deadline = os.clock() + DataConfig.ShutdownTimeout
	while pendingReleases > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end

local function autoSaveLoop()
	while true do
		task.wait(DataConfig.AutoSaveInterval)
		for _, session in sessions do
			task.spawn(saveSession, session, false)
		end
	end
end

-- API pública ----------------------------------------------------------------

function DataService.GetProfile(player: Player): ProfileData?
	local session = sessions[player]
	return if session then session.Data else nil
end

function DataService.GetLoadedPlayers(): { Player }
	local list: { Player } = {}
	for player in sessions do
		table.insert(list, player)
	end
	return list
end

function DataService.IsUsingMock(): boolean
	return usingMock
end

-- Save imediato (bloqueia até terminar). Usado pelo DebugService.
function DataService.SaveNow(player: Player): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	return saveSession(session, false)
end

-- Substitui o perfil pelo template (debug). Dispara ProfileLoaded novamente.
function DataService.ResetProfile(player: Player): ProfileData?
	local session = sessions[player]
	if not session then
		return nil
	end
	local fresh = ProfileTemplate.Create()
	hydrate(fresh)
	session.Data = fresh
	session.PlayTimeMark = os.clock()
	profileLoaded:Fire(player, fresh)
	return fresh
end

-- Ciclo de vida --------------------------------------------------------------

function DataService.Init()
	store, usingMock = selectStore()
	game:BindToClose(onBindToClose)
end

function DataService.Start()
	trove:Connect(Players.PlayerAdded, function(player: Player)
		loadProfile(player)
	end)
	trove:Connect(Players.PlayerRemoving, onPlayerRemoving)

	for _, player in Players:GetPlayers() do
		task.spawn(loadProfile, player)
	end

	trove:Add(task.spawn(autoSaveLoop))
end

return DataService
