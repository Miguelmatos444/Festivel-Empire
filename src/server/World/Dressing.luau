--!strict
--[[
	Dressing
	Coloca os adereços do Blender (ServerStorage/Assets/Props) à volta dos palcos e na
	praça, escalados pelo Config/Dressing. Sem um modelo, esse adereço não aparece.
	  - Palco: colunas de som no chão de cada lado da frente (modelo da era), mesa de DJ
	    no Attachment DJBooth e as máquinas de pirotecnia desbloqueadas nos Attachments
	    Pyro_<Id>_<n>. Tudo dentro de um Model "Dressing" filho do palco (sai com ele).
	  - Praça: roulottes, arcos de entrada, roda gigante e crates de vinil nos postos.
	Os modelos ficam assentes pela base (ou pendurados pelo topo) no ponto pedido,
	com a frente (-Z do FBX) virada para o público / para o centro da praça.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DressingConfig = require(ReplicatedStorage.Shared.Config.Dressing)
local MapConfig = require(ReplicatedStorage.Shared.Config.Map)
local PyroConfig = require(ReplicatedStorage.Shared.Config.Pyro)
local MapCalc = require(ReplicatedStorage.Shared.Calc.MapCalc)
local StageCalc = require(ReplicatedStorage.Shared.Calc.StageCalc)
local Assets = require(script.Parent.Assets)

local DRESSING_NAME = "Dressing"

local Dressing = {}

-- Põe a base (ou o topo, se hang) do modelo no ponto de `target`, de pé, rodado pela orientação de `target`
local function placeAt(model: Model, target: CFrame, hang: boolean?)
	Assets.PlaceUpright(model, target.Position, target, hang)
end

local function setDecorative(model: Model, collide: boolean)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = collide and descendant.Transparency < 1
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
end

local function spawnProp(name: string, axis: Assets.FitAxis, size: number, target: CFrame, parent: Instance, collide: boolean, hang: boolean?): Model?
	local template = Assets.GetProp(name, axis, size)
	if not template then
		return nil
	end
	local model = template:Clone()
	setDecorative(model, collide)
	placeAt(model, target, hang)
	model.Parent = parent
	return model
end

-- Palco -------------------------------------------------------------------------------

function Dressing.DressStage(stage: Model, tier: number, ownedPyro: { [string]: boolean })
	local previous = stage:FindFirstChild(DRESSING_NAME)
	if previous then
		previous:Destroy()
	end
	local config = DressingConfig.Stage
	local root = Assets.GetRoot(stage)
	if not config.Enabled or not root then
		return
	end
	local def = StageCalc.GetDef(tier)
	local folder = Instance.new("Model")
	folder.Name = DRESSING_NAME

	-- Frente-centro-chão do palco, virada para o público, tirada do terreno (imune a um Root rodado no FBX)
	local origin = Assets.GetPlotFacing(stage.Parent)
		or root.CFrame * CFrame.new(0, -root.Size.Y / 2, -root.Size.Z / 2)
	local groundY = origin.Position.Y
	-- Ponto no espaço do palco (x lateral, z para dentro do palco) assente no estrado real
	local function onDeck(x: number, z: number): CFrame
		local point = (origin * CFrame.new(x, 0, z)).Position
		local y = Assets.FindStageSurfaceY(stage, point, groundY, def.Height, groundY)
		return CFrame.new(point.X, y, point.Z) * origin.Rotation
	end

	-- Colunas de som no chão, a flanquear a frente do palco
	local speakerName = config.SpeakerByEra[def.Era]
	if speakerName then
		local height = math.clamp(def.Height * config.SpeakerHeightRatio, config.SpeakerMinHeight, config.SpeakerMaxHeight)
		local template = Assets.GetProp(speakerName, "Y", height)
		if template then
			local _, extents = template:GetBoundingBox()
			for _, side in { -1, 1 } do
				local x = side * (def.Width / 2 + extents.X / 2 + config.SpeakerGap)
				local speaker = template:Clone()
				speaker.Name = "Speaker_" .. (if side < 0 then "L" else "R")
				setDecorative(speaker, true)
				placeAt(speaker, origin * CFrame.new(x, 0, config.SpeakerDepth))
				speaker.Parent = folder
			end
		end
	end

	-- Mesa de DJ (a 60% da profundidade, ao centro)
	local width, depth = def.Width, def.Depth
	spawnProp(config.DJBooth.Name, "Y", config.DJBooth.Height, onDeck(0, 0.6 * depth), folder, false)

	-- Máquinas de pirotecnia desbloqueadas, nos mesmos pontos do contrato (Pyro_<Id>_1/2)
	local pyroPoints: { [string]: (side: number) -> CFrame } = {
		ColdSparks = function(side: number): CFrame
			return onDeck(side * (width / 2 - 1), 1)
		end,
		CO2Cannon = function(side: number): CFrame
			return onDeck(side * 0.3 * width, 1.5)
		end,
		Flamethrower = function(side: number): CFrame
			return onDeck(side * (width / 2 - 1), depth / 2)
		end,
		Lasers = function(side: number): CFrame
			return origin * CFrame.new(side * 0.25 * width, def.Height - 1, depth - 2)
		end,
	}
	for _, pyro in PyroConfig.List do
		local height = config.PyroHeights[pyro.Id]
		local pointAt = pyroPoints[pyro.Id]
		if ownedPyro[pyro.Id] and height and pointAt then
			for _, side in { -1, 1 } do
				spawnProp(pyro.Id, "Y", height, pointAt(side), folder, false, config.HangFromAbove[pyro.Id] == true)
			end
		end
	end

	if #folder:GetChildren() == 0 then
		folder:Destroy()
		return
	end
	folder.Parent = stage
end

-- Praça -------------------------------------------------------------------------------

function Dressing.DressPlaza(plaza: Model)
	local config = DressingConfig.Plaza
	if not config.Enabled then
		return
	end
	local decor = MapConfig.Plaza.Decor
	local folder = Instance.new("Model")
	folder.Name = "PlazaProps"

	for _, angle in decor.FoodTruckAngles do
		-- PlazaPoint olha para o centro: a frente (-Z) da roulotte fica virada para a praça
		spawnProp(config.FoodTruck.Name, "X", config.FoodTruck.Length, MapCalc.PlazaPoint(angle, decor.FoodTruckRadius, 0), folder, true)
	end

	for index = 1, MapConfig.Plots.Count do
		local angle = (index - 1) * 360 / MapConfig.Plots.Count
		local arch = spawnProp(config.EntranceArch.Name, "X", config.EntranceArch.Width, MapCalc.PlazaPoint(angle, MapConfig.Plaza.Radius + 1, 0), folder, false)
		if arch then
			for _, descendant in arch:GetDescendants() do
				if descendant:IsA("BasePart") and string.sub(descendant.Name, 1, 5) == "Neon_" then
					descendant:SetAttribute("RhythmLight", true)
				end
			end
		end
	end

	local wheel = config.FerrisWheel
	spawnProp(wheel.Name, "Y", wheel.Height, MapCalc.PlazaPoint(wheel.Angle, wheel.Radius, 0), folder, true)

	local root = Assets.GetRoot(plaza)
	if root then
		for _, child in root:GetChildren() do
			if child:IsA("Attachment") and string.match(child.Name, "^CrateStation_") then
				local facing = CFrame.lookAt(child.WorldPosition, Vector3.new(0, child.WorldPosition.Y, 0))
				spawnProp(config.VinylCrate.Name, "Y", config.VinylCrate.Height, facing, folder, false)
			end
		end
	end

	if #folder:GetChildren() == 0 then
		folder:Destroy()
		return
	end
	folder.Parent = plaza
end

return table.freeze(Dressing)
