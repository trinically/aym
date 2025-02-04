--!nocheck

--[[ 
                  ___       ___           ___                       ___           ___           ___           ___           ___     
      ___        /\__\     /\__\         /\__\          ___        /\__\         /\  \         /\__\         /\  \         /\  \    
     /\  \      /:/  /    /:/  /        /::|  |        /\  \      /::|  |       /::\  \       /::|  |       /::\  \       /::\  \   
     \:\  \    /:/  /    /:/  /        /:|:|  |        \:\  \    /:|:|  |      /:/\:\  \     /:|:|  |      /:/\:\  \     /:/\:\  \  
     /::\__\  /:/  /    /:/  /  ___   /:/|:|__|__      /::\__\  /:/|:|  |__   /::\~\:\  \   /:/|:|  |__   /:/  \:\  \   /::\~\:\  \ 
  __/:/\/__/ /:/__/    /:/__/  /\__\ /:/ |::::\__\  __/:/\/__/ /:/ |:| /\__\ /:/\:\ \:\__\ /:/ |:| /\__\ /:/__/ \:\__\ /:/\:\ \:\__\
 /\/:/  /    \:\  \    \:\  \ /:/  / \/__/~~/:/  / /\/:/  /    \/__|:|/:/  / \/__\:\/:/  / \/__|:|/:/  / \:\  \  \/__/ \:\~\:\ \/__/
 \::/__/      \:\  \    \:\  /:/  /        /:/  /  \::/__/         |:/:/  /       \::/  /      |:/:/  /   \:\  \        \:\ \:\__\  
  \:\__\       \:\  \    \:\/:/  /        /:/  /    \:\__\         |::/  /        /:/  /       |::/  /     \:\  \        \:\ \/__/  
   \/__/        \:\__\    \::/  /        /:/  /      \/__/         /:/  /        /:/  /        /:/  /       \:\__\        \:\__\    
                 \/__/     \/__/         \/__/                     \/__/         \/__/         \/__/         \/__/         \/__/  
]]

-- Property of iluminance
-- Copyright © 2025

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CONFIG = {
	DETECTION_DISTANCE --[[=======]] = 1000,
	AIM_SPEED          --[[=======]] = 2,
	AIM_ACCURACY       --[[=======]] = 100,

	ACTIVE             --[[=======]] = true,
	TELEPORT_MODE      --[[=======]] = false, 
	WALL_DETECTION     --[[=======]] = true,
	EXCLUDE_NPCS       --[[=======]] = false,
	EXCLUDE_PLAYERS    --[[=======]] = false,
	EXCLUDE_TEAMMATES  --[[=======]] = false,

	TOGGLE_KEY         --[[=======]] = Enum.KeyCode.F,
	TELEPORT_TOGGLE_KEY--[[=======]] = Enum.KeyCode.Q,

	-- // Less important configurations, only touch if you know what you're doing. // --

	VERSION = "v1.1",
	ACTION_NAME = "ToggleAimston",

	RETARGET_INTERVAL = 5,

	ZIGZAG_FREQUENCY = 7,
	ZIGZAG_AMPLITUDE = 3,

	JUMP_COOLDOWN = 0.1,

	TARGET_DISTANCE = 5,

	MAX_VERTICAL_DISTANCE = 20,

	SIDESTEP_COOLDOWN = 0.5,

	ESCAPE_COOLDOWN = 2,

	CLICK_RANGE = 5,

	CPS = 15,

	CPS_VARIATION = 5,

	TELEPORT_ACTION_NAME = "ToggleTeleportMode",
	TELEPORT_PATTERN = {
		AWAY_DISTANCE = 100,
		RETURN_DISTANCE = 2,
		COOLDOWN = 0.2
	}
}

local LocalPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera
local target, lastJump, lastRetarget, lastMove, lastSidestep, lastEscape, lastTeleport = nil, 0, 0, 0, 0, 0, 0
local hitCount, lastHit, maneuvering, inCombo = 0, 0, false, false
local hitTimes = {}

local originalZigzagFrequency = CONFIG.ZIGZAG_FREQUENCY
local originalZigzagAmplitude = CONFIG.ZIGZAG_AMPLITUDE
local originalAimSpeed        = CONFIG.AIM_SPEED
local lastClick               = 0

local function isSitting(target)
	return target:FindFirstChildOfClass("Humanoid") and target:FindFirstChildOfClass("Humanoid").Sit
end

local function getWalkSpeed(target)
	return target:FindFirstChildOfClass("Humanoid") and target:FindFirstChildOfClass("Humanoid").WalkSpeed or 0
end

local function isVisible(target)
	if not target then
		warn("isVisible: Target is nil")
		return false 
	end

	if not LocalPlayer or not LocalPlayer.Character then
		warn("isVisible: LocalPlayer or Character is nil")
		return false
	end

	if not target.PrimaryPart then
		warn("isVisible: Target does not have a PrimaryPart")
		return false
	end

	local origin = LocalPlayer.Character.PrimaryPart.Position
	local destination = target.PrimaryPart.Position
	local direction = (destination - origin).Unit
	local distance = (destination - origin).Magnitude

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {LocalPlayer.Character}

	local result = workspace:Raycast(origin, direction * distance, params)

	if not result then
		return true
	end

	return result.Instance:IsDescendantOf(target) or result.Instance.Transparency > 0
end

local function getTarget()
	if not LocalPlayer or not LocalPlayer.Character or not LocalPlayer.Character.PrimaryPart then
		warn("getTarget: Invalid LocalPlayer or Character")
		return nil
	end

	local closest, dist = nil, CONFIG.DETECTION_DISTANCE or 100  -- Fallback distance if not set
	local playerPosition = LocalPlayer.Character.PrimaryPart.Position

	for _, model in pairs(workspace:GetDescendants()) do
		if not model:IsA("Model") or not model:FindFirstChildOfClass("Humanoid") or model == LocalPlayer.Character then
			continue
		end

		local part = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
		if not part then continue end

		local d = (part.Position - playerPosition).Magnitude
		local verticalDifference = math.abs(part.Position.Y - playerPosition.Y)

		if d > dist or verticalDifference > 20 then continue end

		local plr = Players:GetPlayerFromCharacter(model)

		local skipTarget = 
			(plr and CONFIG.EXCLUDE_PLAYERS) or 
			(not plr and CONFIG.EXCLUDE_NPCS) or 
			(plr and CONFIG.EXCLUDE_TEAMMATES and plr.Team == LocalPlayer.Team)

		if skipTarget then continue end

		local isValidTarget = 
			not CONFIG.WALL_DETECTION or 
			isVisible(model) or 
			d <= 20

		if isValidTarget and (not closest or d < dist) then
			closest, dist = model, d
		end
	end

	return closest
end


local function getAimPart(target)
	if not target or not target:FindFirstChild("Humanoid") then return nil end

	local parts = {
		Head = target:FindFirstChild("Head"),
		Torso = target:FindFirstChild("UpperTorso") or target:FindFirstChild("Torso"),
		Legs = target:FindFirstChild("LeftLeg") or target:FindFirstChild("RightLeg") or 
			target:FindFirstChild("LeftFoot") or target:FindFirstChild("RightFoot")
	}

	local heightDifference = camera.CFrame.Position.Y - target.PrimaryPart.Position.Y

	if heightDifference > 2 then
		return parts.Head or parts.Torso
	elseif heightDifference < -2 then
		return parts.Legs or parts.Torso
	else
		return parts.Torso or parts.Head or parts.Legs
	end
end


local function aimlock()
	if CONFIG.ACTIVE and target and target.PrimaryPart then
		local part = getAimPart(target)
		if part then
			local pos = (part.Position or part:GetPivot().Position)
			local inaccuracy = (100 - CONFIG.AIM_ACCURACY) / 100
			local offset = Vector3.new(
				math.random(-10, 10) * inaccuracy / 100,
				math.random(-10, 10) * inaccuracy / 100,
				math.random(-10, 10) * inaccuracy / 100
			)
			local cf = CFrame.new(camera.CFrame.Position, pos + offset)
			camera.CFrame = camera.CFrame:Lerp(cf, CONFIG.AIM_SPEED / 10)
		end
	end
end


local function isFirstPerson()
	return LocalPlayer.CameraMode == Enum.CameraMode.LockFirstPerson or 
		(LocalPlayer.Character and 
			LocalPlayer.Character:FindFirstChild("Head") and 
			(camera.CFrame.Position - LocalPlayer.Character.Head.Position).Magnitude <= 1)
end


local function sidestep(char, dir)
	if workspace.DistributedGameTime - lastSidestep < CONFIG.SIDESTEP_COOLDOWN then 
		return 
	end

	maneuvering             = true
	local sideDir           = Vector3.new(-dir.Z, 0, dir.X).Unit
	local pos               = char.PrimaryPart.Position + sideDir * CONFIG.SIDESTEP_DISTANCE

	char.Humanoid:MoveTo(pos)

	lastSidestep            = workspace.DistributedGameTime

	task.delay(CONFIG.SIDESTEP_DURATION, function()
		maneuvering         = false
	end)
end

local function escape(char)

	print("escaping")
	if workspace.DistributedGameTime - lastEscape < CONFIG.ESCAPE_COOLDOWN then 
		return 
	end

	maneuvering             = true
	local escapeDir         = -char.PrimaryPart.CFrame.LookVector
	local pos               = char.PrimaryPart.Position + escapeDir * CONFIG.ESCAPE_DISTANCE

	char.Humanoid:MoveTo(pos)
	char.Humanoid.Jump      = true

	lastEscape              = workspace.DistributedGameTime

	task.delay(CONFIG.ESCAPE_DURATION, function()
		maneuvering         = false
	end)
end

local function click()
	local now = workspace.DistributedGameTime
	local actualCPS = CONFIG.CPS + math.random(-CONFIG.CPS_VARIATION, CONFIG.CPS_VARIATION)
	local clickInterval = 1 / actualCPS
	if now - lastClick >= clickInterval then
		--script.Parent.cps.Clicked.Value = not script.Parent.cps.Clicked.Value
		mouse1click()
		lastClick = now
	end
end

local function TeleportTo(target)
	if not LocalPlayer.Character or 
		not LocalPlayer.Character.PrimaryPart or 
		not target or 
		not target.PrimaryPart then 
		return 
	end

	local connection
	connection = game:GetService("RunService").Heartbeat:Connect(function()
		if not CONFIG.TELEPORT_MODE then
			connection:Disconnect()
			return
		end

		local behindDirection = -target.PrimaryPart.CFrame.LookVector
		local behindPosition = target.PrimaryPart.Position + behindDirection * 4 -- 4 studs behind

		LocalPlayer.Character:SetPrimaryPartCFrame(CFrame.new(behindPosition, target.PrimaryPart.Position))
	end)

	return connection
end

local function MoveTo(target, guard)
	if not target or not target.PrimaryPart or not LocalPlayer.Character or 
		not LocalPlayer.Character:FindFirstChild("Humanoid") or 
		not LocalPlayer.Character.PrimaryPart then 
		return false  -- no valid target, just return
	end

	-- if we need to teleport or chill, just do it
	if CONFIG.TELEPORT_MODE or isSitting(target) or getWalkSpeed(target) >= 20 then
		TeleportTo(target)
		return true
	end

	local time                = workspace.DistributedGameTime
	local startPosition       = LocalPlayer.Character.PrimaryPart.Position
	local targetPosition      = target.PrimaryPart.Position
	local direction           = (targetPosition - startPosition).Unit
	local distance            = (targetPosition - startPosition).Magnitude
	local targetDistance      = inCombo and CONFIG.COMBO_DISTANCE or CONFIG.TARGET_DISTANCE

	local perpendicularDirection = Vector3.new(-direction.Z, 0, direction.X).Unit
	local targetVelocity      = target.PrimaryPart.Velocity
	local targetSpeed         = targetVelocity.Magnitude
	local targetDir           = targetVelocity.Unit

	-- calculate predicted position of the target
	local predictedPosition   = targetPosition + targetVelocity
	local dotProduct          = direction:Dot(targetDir)
	local angle               = math.acos(dotProduct)
	local cutAcross           = false

	if angle > math.pi/4 and angle < 3*math.pi/4 and targetSpeed > 5 then
		cutAcross = true
	end

	local desiredPosition

	if cutAcross then
		local timeToIntercept   = distance / (LocalPlayer.Character.Humanoid.WalkSpeed + targetSpeed)
		desiredPosition         = predictedPosition - targetDir * (targetDistance + timeToIntercept * targetSpeed)
	else
		local zigzagFrequency   = inCombo and CONFIG.COMBO_ZIGZAG_FREQUENCY or CONFIG.ZIGZAG_FREQUENCY
		local zigzagAmplitude    = inCombo and CONFIG.COMBO_ZIGZAG_AMPLITUDE or CONFIG.ZIGZAG_AMPLITUDE
		local zigzag            = perpendicularDirection * math.sin(time * zigzagFrequency) * zigzagAmplitude

		desiredPosition         = targetPosition - direction * targetDistance + zigzag
	end

	if distance <= targetDistance then
		desiredPosition         = startPosition + (startPosition - targetPosition).Unit * (targetDistance - distance + 0.5)
	end

	LocalPlayer.Character.Humanoid:MoveTo(desiredPosition)

	if distance <= targetDistance + 1 then
		local speed             = 16 * (distance / targetDistance)
		LocalPlayer.Character.Humanoid.WalkSpeed = math.max(1, math.min(16, speed))
	else
		LocalPlayer.Character.Humanoid.WalkSpeed = 16
	end

	if math.abs(distance - targetDistance) <= CONFIG.CLICK_RANGE then
		click()  -- click if we're close enough to the target
	end

	return true  -- everything went fine
end

local function toggle(_, state)
	if state ~= Enum.UserInputState.Begin then return end

	CONFIG.ACTIVE = not CONFIG.ACTIVE
	target = nil

	if not CONFIG.ACTIVE and LocalPlayer.Character then
		local humanoid = LocalPlayer.Character:FindFirstChild("Humanoid")
		if humanoid then
			humanoid:MoveTo(LocalPlayer.Character.PrimaryPart.Position)
		end
	end

	print(CONFIG.ACTIVE and "Aym enabled" or "Aym disabled")
end

local function toggleTeleportMode(_, state)
	if state ~= Enum.UserInputState.Begin then return end

	CONFIG.TELEPORT_MODE = not CONFIG.TELEPORT_MODE
	print(CONFIG.TELEPORT_MODE and "Teleport mode enabled" or "Teleport mode disabled")
end


ContextActionService:BindAction(CONFIG.ACTION_NAME, toggle, true, CONFIG.TOGGLE_KEY, Enum.KeyCode.ButtonR3)
ContextActionService:BindAction(CONFIG.TELEPORT_ACTION_NAME, toggleTeleportMode, true, CONFIG.TELEPORT_TOGGLE_KEY)

if UserInputService.TouchEnabled then
	ContextActionService:BindAction(CONFIG.ACTION_NAME, toggle, true)
	ContextActionService:SetPosition(CONFIG.ACTION_NAME, UDim2.new(1, -280, 0, 10))
	ContextActionService:SetTitle(CONFIG.ACTION_NAME, "Aym")

	ContextActionService:BindAction(CONFIG.TELEPORT_ACTION_NAME, toggleTeleportMode, true)
	ContextActionService:SetPosition(CONFIG.TELEPORT_ACTION_NAME, UDim2.new(1, -280, 0, 70))
	ContextActionService:SetTitle(CONFIG.TELEPORT_ACTION_NAME, "TP")
end

print(string.format("Running aym %s", CONFIG.VERSION))

RunService.Heartbeat:Connect(function()
	if not CONFIG.ACTIVE then return end

	local character = LocalPlayer.Character
	if not character or not character:FindFirstChild("Humanoid") then return end

	local now = workspace.DistributedGameTime

	local shouldRetarget = now - lastRetarget >= CONFIG.RETARGET_INTERVAL or
		not target or
		not target:IsA("Model") or
		not target:FindFirstChildOfClass("Humanoid") or
		not isVisible(target)

	if shouldRetarget then
		target = getTarget()
		lastRetarget = now
	end

	if target then
		if CONFIG.TELEPORT_MODE then
			TeleportTo(target)
		else
			MoveTo(target, false)
		end
	else
		aimlock()  -- aimlock will still run but won't attempt to move
	end

	character.Humanoid.Jump = true


	if isFirstPerson() then
		coroutine.wrap(aimlock)()
	else
		target = nil -- clear the target if not in first person.
	end
end)
