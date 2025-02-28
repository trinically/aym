--!nocheck
-- Fully redone Minecraft PvP bot walker with ground adherence and climbing

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
	FlankInt    = 2,   -- seconds between flanking switches
	FlankAmp    = 3,   -- extra lateral offset when flanking
	RetargetInt = 5,
	ChaseThresh = 7,   -- if horizontal distance is below this, disable flanking
	ToggleKey   = Enum.KeyCode.F,
	ClimbRate   = 8    -- rate at which bot climbs when target is high
}

local player      = Players.LocalPlayer
local cam         = workspace.CurrentCamera
local target      = nil
local lastRetarget = 0

-- Flanking state
local lastFlankSwitch = tick()
local currentFlankDir = 1  -- 1 for right, -1 for left

-- Finds the nearest valid humanoid target.
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

-- Moves the character toward the target.
-- Normal behavior: the bot stays on ground by setting its Y from a downward raycast.
-- If the target is more than 15 studs above ground level, the bot starts climbing to match the target's level.
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
	
	-- Determine ground level via a downward raycast.
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {player.Character}
	rayParams.FilterType = Enum.RaycastFilterType.Blacklist
	local ray = workspace:Raycast(curPos, Vector3.new(0, -1000, 0), rayParams)
	local groundY = ray and ray.Position.Y or curPos.Y
	
	-- Compute horizontal difference.
	local diff = tarPos - curPos
	local horiz = Vector3.new(diff.X, 0, diff.Z)
	local horizDist = horiz.Magnitude
	
	local moveDir
	if horizDist < CONFIG.ChaseThresh then
		-- Direct chase when close: use full diff (vertical will be overridden later if not climbing).
		moveDir = diff.Unit
	else
		-- Flanking movement with zigzag and lateral offset.
		local forward = horiz.Unit
		local right = forward:Cross(Vector3.new(0, 1, 0)).Unit
		
		local timeNow = tick()
		-- Switch flanking direction periodically.
		if timeNow - lastFlankSwitch > CONFIG.FlankInt then
			currentFlankDir = (math.random(0,1) == 0) and -1 or 1
			lastFlankSwitch = timeNow
		end
		
		local zigzag = math.sin(timeNow * CONFIG.ZigFreq) * CONFIG.ZigAmp
		local flank = currentFlankDir * CONFIG.FlankAmp
		local lateral = right * (zigzag + flank)
		local horizontalDir = (forward + lateral).Unit
		
		-- Incorporate vertical difference into the movement direction.
		local verticalFactor = diff.Y / math.max(horizDist, 0.001)
		moveDir = Vector3.new(horizontalDir.X, verticalFactor, horizontalDir.Z).Unit
	end
	
	-- Determine new Y position.
	local targetY = tarPos.Y
	local newY
	if targetY > groundY + 15 then
		-- Climb gradually: interpolate current Y toward targetY.
		newY = curPos.Y + (targetY - curPos.Y) * (CONFIG.ClimbRate * dt)
	else
		-- Stay on ground.
		newY = groundY
	end
	
	-- Calculate horizontal step (vertical is handled separately).
	local horizontalStep = Vector3.new(moveDir.X, 0, moveDir.Z) * hum.WalkSpeed * dt
	local newPos = curPos + horizontalStep
	newPos = Vector3.new(newPos.X, newY, newPos.Z)
	
	-- Adjust look direction.
	local lookDir = moveDir
	if targetY <= groundY + 15 then
		-- When not climbing, look purely horizontally.
		lookDir = Vector3.new(moveDir.X, 0, moveDir.Z)
		if lookDir.Magnitude > 0 then
			lookDir = lookDir.Unit
		end
	end
	
	hrp.CFrame = CFrame.new(newPos, newPos + lookDir)
end

-- Smoothly adjusts the camera to aim at the target with slight inaccuracy.
local function aimLock()
	if not CONFIG.Active or not target or not target.PrimaryPart then
		return
	end
	
	local aimPart = target:FindFirstChild("Head") or target:FindFirstChild("Torso") or target.PrimaryPart
	local tarPos = aimPart.Position
	local inacc = (100 - CONFIG.AimAcc) / 100
	local randOff = Vector3.new(
		math.random(-10, 10) * inacc / 100,
		math.random(-10, 10) * inacc / 100,
		math.random(-10, 10) * inacc / 100
	)
	local desired = CFrame.new(cam.CFrame.Position, tarPos + randOff)
	cam.CFrame = cam.CFrame:Lerp(desired, CONFIG.AimSpd / 10)
end

-- Activates any held tool every heartbeat.
local function activateTool()
	if player.Character then
		local tool = player.Character:FindFirstChildWhichIsA("Tool")
		if tool then
			pcall(function() tool:Activate() end)
		end
	end
end

-- Toggles the system on/off.
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
	
	activateTool()
end)

print("Running targeting system")
