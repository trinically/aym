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
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local CONFIG = {
	ACTIVE = true,
	TARGET_DISTANCE = 5,
	DETECTION_DISTANCE = 1000,
	MAX_VERTICAL_DISTANCE = 20,
	AIM_ACCURACY = 100,
	AIM_SPEED = 8,
	ZIGZAG_FREQUENCY = 7,
	ZIGZAG_AMPLITUDE = 3,
	RETARGET_INTERVAL = 5,
	TOGGLE_KEY = Enum.KeyCode.F,
	CPS = 20,
	CPS_VARIATION = 2
}

local LocalPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera
local target = nil
local lastRetarget = 0
local lastClick = 0

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

	if distance < 0.1 then
		return
	end

	local forwardDir = toTarget.Unit
	local upVector = Vector3.new(0, 1, 0)
	local rightDir = forwardDir:Cross(upVector).Unit

	local timeNow = tick()
	local sinOffset = math.sin(timeNow * CONFIG.ZIGZAG_FREQUENCY) * CONFIG.ZIGZAG_AMPLITUDE
	local strafeVector = rightDir * sinOffset

	local moveVector = forwardDir + strafeVector
	moveVector = moveVector.Unit

	if distance < CONFIG.TARGET_DISTANCE * 2 then
		local scale = distance / (CONFIG.TARGET_DISTANCE * 2)
		moveVector = moveVector * scale
	end

	humanoid:MoveTo(targetPos)
end

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

local function clickLogic()
	local now = tick()
	local actualCPS = CONFIG.CPS + math.random(-CONFIG.CPS_VARIATION, CONFIG.CPS_VARIATION)
	local clickInterval = 1 / actualCPS
	if now - lastClick >= clickInterval then
		mouse1click()
		lastClick = now
	end
end

local function toggleTargeting(_, state)
	if state == Enum.UserInputState.Begin then
		CONFIG.ACTIVE = not CONFIG.ACTIVE
		if not CONFIG.ACTIVE and LocalPlayer.Character then
			local humanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:Move(Vector3.new(0,0,0), false)
			end
		end
		print(CONFIG.ACTIVE and "Targeting enabled" or "Targeting disabled")
	end
end

ContextActionService:BindAction("ToggleTargeting", toggleTargeting, true, CONFIG.TOGGLE_KEY)

local function createMobileButton()
	ContextActionService:SetTitle("ToggleTargeting", "Target")
	ContextActionService:SetPosition("ToggleTargeting", UDim2.new(0.9, 0, 0.8, 0))
end

createMobileButton()

RunService.Heartbeat:Connect(function(deltaTime)
	if not CONFIG.ACTIVE then
		return
	end

	if not LocalPlayer.Character or not LocalPlayer.Character.PrimaryPart then
		return
	end

	local currentTime = tick()
	if not target or not target.Parent or currentTime - lastRetarget > CONFIG.RETARGET_INTERVAL then
		target = acquireTarget()
		lastRetarget = currentTime
	end

	if target then
		humanizedMoveToTarget(target)
		aimLock()

		if (LocalPlayer.Character.PrimaryPart.Position - target.PrimaryPart.Position).Magnitude <= 20 then
			--clickLogic()
		end
	else
		local humanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:Move(Vector3.new(0,0,0), false)
		end
	end
end)

print("Running aym")
