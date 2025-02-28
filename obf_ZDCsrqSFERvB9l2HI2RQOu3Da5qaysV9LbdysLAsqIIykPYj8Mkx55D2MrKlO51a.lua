--!nocheck
-- Fully redone Minecraft PvP bot walker with flanking and tool activation

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local CONFIG = {
	Active      = true,
	TargetDist  = 5,
	DetectDist  = 1000,
	MaxVert     = 20,
	AimAcc      = 100,
	AimSpd      = 8,
	ZigFreq     = 7,
	ZigAmp      = 3,
	FlankInt    = 2,   -- seconds between flanking direction changes
	FlankAmp    = 3,   -- additional lateral offset for flanking
	RetargetInt = 5,
	AvoidDist   = 4,   -- raycast length for obstacle detection
	ToggleKey   = Enum.KeyCode.F
}

local player      = Players.LocalPlayer
local cam         = workspace.CurrentCamera
local target      = nil
local lastRetarget = 0

-- Flanking state
local lastFlankSwitch = tick()
local currentFlankDir = 1  -- 1 for right, -1 for left

-- Scans the workspace for the nearest valid target.
local function getTarget()
	if not player.Character or not player.Character.PrimaryPart then
		return nil
	end
	
	local bestTarg = nil
	local bestDist = CONFIG.DetectDist
	local pos = player.Character.PrimaryPart.Position

	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("Model") and obj ~= player.Character then
			local hum = obj:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				local prim = obj.PrimaryPart or obj:FindFirstChild("HumanoidRootPart")
				if prim then
					local diff = prim.Position - pos
					local d = diff.Magnitude
					if d < bestDist and math.abs(diff.Y) <= CONFIG.MaxVert then
						bestDist = d
						bestTarg = obj
					end
				end
			end
		end
	end
	return bestTarg
end

-- Moves the character toward the target using CFrame, incorporating zigzag and flanking,
-- and uses raycasts to avoid obstacles.
local function moveTarget(dt)
	if not target or not target.PrimaryPart or not player.Character or not player.Character.PrimaryPart then
		return
	end
	
	local char = player.Character
	local hrp  = char.PrimaryPart
	local hum  = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	
	local curPos = hrp.Position
	local tarPos = target.PrimaryPart.Position
	
	-- Compute horizontal vector to target.
	local diff = Vector3.new(tarPos.X - curPos.X, 0, tarPos.Z - curPos.Z)
	local dist = diff.Magnitude
	if dist < 0.1 then return end
	
	local forward = diff.Unit
	local right   = forward:Cross(Vector3.new(0, 1, 0)).Unit
	
	local timeNow = tick()
	-- Update flanking direction every FlankInt seconds.
	if timeNow - lastFlankSwitch > CONFIG.FlankInt then
		currentFlankDir = math.random(0, 1) == 0 and -1 or 1
		lastFlankSwitch = timeNow
	end
	
	-- Combine zigzag and flanking offsets.
	local zigzag = math.sin(timeNow * CONFIG.ZigFreq) * CONFIG.ZigAmp
	local flank  = currentFlankDir * CONFIG.FlankAmp
	local lateral = right * (zigzag + flank)
	local moveDir = (forward + lateral).Unit
	
	-- Obstacle avoidance via raycasts.
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {player.Character}
	rayParams.FilterType = Enum.RaycastFilterType.Blacklist
	
	local forwardHit = workspace:Raycast(curPos, moveDir * CONFIG.AvoidDist, rayParams)
	if forwardHit then
		local candLeft = (moveDir + right * 0.5).Unit
		local leftHit  = workspace:Raycast(curPos, candLeft * CONFIG.AvoidDist, rayParams)
		local candRight = (moveDir - right * 0.5).Unit
		local rightHit  = workspace:Raycast(curPos, candRight * CONFIG.AvoidDist, rayParams)
		if not leftHit then
			moveDir = candLeft
		elseif not rightHit then
			moveDir = candRight
		end
	end
	
	-- Slow down near target.
	local scale = 1
	if dist < CONFIG.TargetDist * 2 then
		scale = dist / (CONFIG.TargetDist * 2)
	end
	
	local speed = hum.WalkSpeed * scale
	local step  = moveDir * speed * dt
	
	-- Update position with constant Y.
	local newPos = curPos + Vector3.new(step.X, 0, step.Z)
	hrp.CFrame = CFrame.new(newPos, newPos + moveDir)
end

-- Adjusts the camera to aim at the target with slight inaccuracy.
local function aimLock()
	if not CONFIG.Active or not target or not target.PrimaryPart then
		return
	end
	
	local aimPart = target:FindFirstChild("Head") or target:FindFirstChild("Torso") or target.PrimaryPart
	local tarPos  = aimPart.Position
	local inacc   = (100 - CONFIG.AimAcc) / 100
	local randOff = Vector3.new(
		math.random(-10, 10) * inacc / 100,
		math.random(-10, 10) * inacc / 100,
		math.random(-10, 10) * inacc / 100
	)
	local desired = CFrame.new(cam.CFrame.Position, tarPos + randOff)
	cam.CFrame = cam.CFrame:Lerp(desired, CONFIG.AimSpd / 10)
end

-- Activates any held tool on every heartbeat.
local function activateTool()
	if player.Character then
		local tool = player.Character:FindFirstChildWhichIsA("Tool")
		if tool then
			pcall(function() tool:Activate() end)
		end
	end
end

-- Toggle the system on/off.
local function toggleTarget(_, state)
	if state == Enum.UserInputState.Begin then
		CONFIG.Active = not CONFIG.Active
		if not CONFIG.Active and player.Character then
			local hum = player.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum:Move(Vector3.new(0, 0, 0), false)
			end
		end
		print(CONFIG.Active and "Targeting enabled" or "Targeting disabled")
	end
end

ContextActionService:BindAction("ToggleTarget", toggleTarget, true, CONFIG.ToggleKey)
ContextActionService:SetTitle("ToggleTarget", "Target")
ContextActionService:SetPosition("ToggleTarget", UDim2.new(0.5, 0, 0.5, 0))

-- When a tool is added, activate it.
local function onToolAdded(child)
	if child:IsA("Tool") then
		pcall(function() child:Activate() end)
	end
end

if player.Character then
	player.Character.ChildAdded:Connect(onToolAdded)
end
player.CharacterAdded:Connect(function(char)
	char.ChildAdded:Connect(onToolAdded)
end)

-- Main update loop.
RunService.Heartbeat:Connect(function(dt)
	if not CONFIG.Active then
		return
	end
	if not player.Character or not player.Character.PrimaryPart then
		return
	end
	
	local now = tick()
	if not target or not target.Parent or now - lastRetarget > CONFIG.RetargetInt then
		target = getTarget()
		lastRetarget = now
	end
	
	if target then
		moveTarget(dt)
		aimLock()
	else
		local hum = player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum:Move(Vector3.new(0, 0, 0), false)
		end
	end

	keypress(0x57)
	keyrelease(0x57)
	activateTool()
end)

print("Running targeting system")
