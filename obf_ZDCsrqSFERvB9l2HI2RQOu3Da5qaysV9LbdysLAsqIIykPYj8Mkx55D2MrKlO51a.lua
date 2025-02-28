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
-- Copyright Â© 2025

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CONFIG = {
	DETECTION_DISTANCE = 1000,
	AIM_SPEED = 8,
	AIM_ACCURACY = 100,

	ACTIVE = true,
	TELEPORT_MODE = false, 
	WALL_DETECTION = true,
	EXCLUDE_NPCS = false,
	EXCLUDE_PLAYERS = false,
	EXCLUDE_TEAMMATES = true,

	TOGGLE_KEY = Enum.KeyCode.F,
	TELEPORT_TOGGLE_KEY = Enum.KeyCode.Q,

	VERSION = "v1.2, teleport mode fixed [DEBUG]",
	ACTION_NAME = "ToggleAimston",

	RETARGET_INTERVAL = 5,

	ZIGZAG_FREQUENCY = 7,
	ZIGZAG_AMPLITUDE = 3,

	JUMP_COOLDOWN = 0.1,

	TARGET_DISTANCE = 5,

	MAX_VERTICAL_DISTANCE = 20,

	CLICK_RANGE = 32,

	CPS = 20,
	CPS_VARIATION = 2,

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
local originalAimSpeed = CONFIG.AIM_SPEED
local lastClick = 0

local function getTarget()
	if not LocalPlayer or not LocalPlayer.Character or not LocalPlayer.Character.PrimaryPart then
		warn("getTarget: Invalid LocalPlayer or Character")
		return nil
	end

	local closest, dist = nil, CONFIG.DETECTION_DISTANCE or 100
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

		local isValidTarget = true

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

local function click()
	local now = workspace.DistributedGameTime
	local actualCPS = CONFIG.CPS + math.random(-CONFIG.CPS_VARIATION, CONFIG.CPS_VARIATION)
	local clickInterval = 1 / actualCPS
	if now - lastClick >= clickInterval then
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

local function MoveTo(target)
	if not target or not target.PrimaryPart or not LocalPlayer.Character or 
		not LocalPlayer.Character:FindFirstChild("Humanoid") or 
		not LocalPlayer.Character.PrimaryPart then 
		return false
	end

	if CONFIG.TELEPORT_MODE then
		TeleportTo(target)
		return true
	end

	local time = workspace.DistributedGameTime
	local startPosition = LocalPlayer.Character.PrimaryPart.Position
	local targetPosition = target.PrimaryPart.Position
	local direction = (targetPosition - startPosition).Unit
	local distance = (targetPosition - startPosition).Magnitude

	if distance > CONFIG.TARGET_DISTANCE then
		LocalPlayer.Character.Humanoid:MoveTo(targetPosition)
		return true
	end
	return false
end

ContextActionService:BindActionAtPriority(CONFIG.ACTION_NAME, function(_, inputState, _)
	if inputState == Enum.UserInputState.Begin then
		CONFIG.ACTIVE = not CONFIG.ACTIVE
	end
end, false, Enum.ContextActionPriority.High.Value, CONFIG.TOGGLE_KEY)

ContextActionService:BindActionAtPriority(CONFIG.TELEPORT_ACTION_NAME, function(_, inputState, _)
	if inputState == Enum.UserInputState.Begin then
		CONFIG.TELEPORT_MODE = not CONFIG.TELEPORT_MODE
	end
end, false, Enum.ContextActionPriority.Low.Value, CONFIG.TELEPORT_TOGGLE_KEY)

RunService.Heartbeat:Connect(function()
	if CONFIG.ACTIVE then
		aimlock()
		if target and (LocalPlayer.Character.PrimaryPart.Position - target.PrimaryPart.Position).Magnitude < CONFIG.CLICK_RANGE then
			click()
		end
	end
end)
