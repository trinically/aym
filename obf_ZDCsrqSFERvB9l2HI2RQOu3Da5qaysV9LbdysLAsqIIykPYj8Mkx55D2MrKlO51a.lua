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
-- Humanized Targeting and Movement Script
-- This script finds the closest humanoid target and moves towards it using a natural, sine-based strafe.
-- It also gently aims the camera toward the target with a slight inaccuracy to simulate human behavior.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local CONFIG = {
	ACTIVE = true,                    -- Master switch for targeting/movement
	TARGET_DISTANCE = 5,              -- Desired distance to maintain from target
	DETECTION_DISTANCE = 1000,        -- Maximum range to consider targets
	MAX_VERTICAL_DISTANCE = 20,       -- Vertical tolerance for valid targets
	AIM_ACCURACY = 100,               -- 0-100% aiming accuracy (100 = perfect)
	AIM_SPEED = 8,                    -- Speed of camera interpolation when aiming
	ZIGZAG_FREQUENCY = 7,             -- Frequency (Hz) of the sine wave for strafing
	ZIGZAG_AMPLITUDE = 3,             -- Amplitude (studs) of the strafe
	RETARGET_INTERVAL = 5,            -- Seconds between re-acquiring targets
	TOGGLE_KEY = Enum.KeyCode.F       -- Key to toggle the targeting system on/off
}

local LocalPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera
local target = nil
local lastRetarget = 0

----------------------------------------------------------
-- Target Acquisition
----------------------------------------------------------
-- Scans the workspace for the nearest valid humanoid target.
local function acquireTarget()
	if not LocalPlayer.Character or not LocalPlayer.Character.PrimaryPart then
		return nil
	end

	local bestTarget = nil
	local bestDistance = CONFIG.DETECTION_DISTANCE
	local playerPos = LocalPlayer.Character.PrimaryPart.Position

	for _, model in ipairs(workspace:GetDescendants()) do
		if model:IsA("Model") and model ~= LocalPlayer.Character then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local primary = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
				if primary then
					local d = (primary.Position - playerPos).Magnitude
					local verticalDiff = math.abs(primary.Position.Y - playerPos.Y)
					if d < bestDistance and verticalDiff <= CONFIG.MAX_VERTICAL_DISTANCE then
						bestDistance = d
						bestTarget = model
					end
				end
			end
		end
	end
	return bestTarget
end

----------------------------------------------------------
-- Humanized Movement Toward Target
----------------------------------------------------------
-- Moves the character toward the target using humanoid:Move() with a sine-based lateral strafe.
local function humanizedMoveToTarget(target)
	if not target or not target.PrimaryPart or not LocalPlayer.Character or not LocalPlayer.Character.PrimaryPart then
		return
	end

	local character = LocalPlayer.Character
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local currentPos = character.PrimaryPart.Position
	local targetPos = target.PrimaryPart.Position
	local toTarget = targetPos - currentPos
	local distance = toTarget.Magnitude

	-- If already extremely close, do not move.
	if distance < 0.1 then
		return
	end

	-- Calculate the forward direction toward the target.
	local forwardDir = toTarget.Unit

	-- Determine the right vector (perpendicular to forward) using the world's up vector.
	local upVector = Vector3.new(0, 1, 0)
	local rightDir = forwardDir:Cross(upVector).Unit

	-- Create a sine-based offset to strafe left/right.
	local timeNow = tick()
	local sinOffset = math.sin(timeNow * CONFIG.ZIGZAG_FREQUENCY) * CONFIG.ZIGZAG_AMPLITUDE
	local strafeVector = rightDir * sinOffset

	-- Blend the forward direction with the strafing offset.
	local moveVector = forwardDir + strafeVector
	moveVector = moveVector.Unit

	-- Slow down as you near the target (optional human-like nuance).
	if distance < CONFIG.TARGET_DISTANCE * 2 then
		local scale = distance / (CONFIG.TARGET_DISTANCE * 2)
		moveVector = moveVector * scale
	end

	-- Use directional movement via humanoid:Move()
	humanoid:Move(moveVector, false)
end

----------------------------------------------------------
-- Aim Lock (Smooth Camera Aiming)
----------------------------------------------------------
-- Gradually rotates the camera to face the target with slight random inaccuracy.
local function aimLock()
	if CONFIG.ACTIVE and target and target.PrimaryPart then
		local aimPart = target:FindFirstChild("Head") or target:FindFirstChild("Torso") or target.PrimaryPart
		local targetPos = aimPart.Position
		local inaccuracyFactor = (100 - CONFIG.AIM_ACCURACY) / 100
		local randomOffset = Vector3.new(
			math.random(-10, 10) * inaccuracyFactor / 100,
			math.random(-10, 10) * inaccuracyFactor / 100,
			math.random(-10, 10) * inaccuracyFactor / 100
		)
		local desiredCF = CFrame.new(camera.CFrame.Position, targetPos + randomOffset)
		camera.CFrame = camera.CFrame:Lerp(desiredCF, CONFIG.AIM_SPEED / 10)
	end
end

----------------------------------------------------------
-- Toggle Targeting System
----------------------------------------------------------
local function toggleTargeting(_, state)
	if state == Enum.UserInputState.Begin then
		CONFIG.ACTIVE = not CONFIG.ACTIVE
		-- Stop movement if disabled.
		if not CONFIG.ACTIVE and LocalPlayer.Character then
			local humanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:Move(Vector3.new(0,0,0), false)
			end
		end
		print(CONFIG.ACTIVE and "Targeting enabled" or "Targeting disabled")
	end
end

ContextActionService:BindAction("ToggleTargeting", toggleTargeting, false, CONFIG.TOGGLE_KEY)

print("Running Humanized Targeting and Movement Script")

----------------------------------------------------------
-- Main Loop
----------------------------------------------------------
RunService.Heartbeat:Connect(function(deltaTime)
	if not CONFIG.ACTIVE then
		return
	end

	if not LocalPlayer.Character or not LocalPlayer.Character.PrimaryPart then
		return
	end

	local currentTime = tick()
	-- Reacquire target periodically or if the current target becomes invalid.
	if not target or not target.Parent or currentTime - lastRetarget > CONFIG.RETARGET_INTERVAL then
		target = acquireTarget()
		lastRetarget = currentTime
	end

	if target then
		-- Move toward target with human-like strafe.
		humanizedMoveToTarget(target)
		-- Smoothly aim at the target.
		aimLock()
	else
		-- No target: optionally halt movement.
		local humanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:Move(Vector3.new(0,0,0), false)
		end
	end
end)
