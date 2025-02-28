--!nocheck
-- Fully redone Minecraft PvP bot walker with selective flanking and vertical movement

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
	ToggleKey   = Enum.KeyCode.F
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
-- If the horizontal distance is at least ChaseThresh, flanking (zigzag plus lateral offset) is applied.
-- Also, vertical movement is incorporated so that if the target is elevated the bot will climb.
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
	local diff   = tarPos - curPos
	local horiz  = Vector3.new(diff.X, 0, diff.Z)
	local horizDist = horiz.Magnitude
	
	local moveDir
	
	-- If very close horizontally, chase directly (including vertical movement)
	if horizDist < CONFIG.ChaseThresh then
		moveDir = diff.Unit
	else
		-- Compute horizontal direction and right vector.
		local forward = horiz.Unit
		local right   = forward:Cross(Vector3.new(0, 1, 0)).Unit
		
		local timeNow = tick()
		-- Switch flanking direction every FlankInt seconds.
		if timeNow - lastFlankSwitch > CONFIG.FlankInt then
			currentFlankDir = (math.random(0, 1) == 0) and -1 or 1
			lastFlankSwitch = timeNow
		end
		
		local zigzag = math.sin(timeNow * CONFIG.ZigFreq) * CONFIG.ZigAmp
		local flank  = currentFlankDir * CONFIG.FlankAmp
		local lateral = right * (zigzag + flank)
		local horizontalDir = (forward + lateral).Unit
		
		-- Combine horizontal direction with vertical adjustment.
		-- The vertical component is taken from the actual difference.
		local verticalFactor = diff.Y / math.max(horizDist, 0.001)
		moveDir = Vector3.new(horizontalDir.X, verticalFactor, horizontalDir.Z).Unit
	end
	
	-- Optionally slow down near target.
	local scale = 1
	if horizDist < CONFIG.TargetDist * 2 then
		scale = horizDist / (CONFIG.TargetDist * 2)
	end
	
	local speed = hum.WalkSpeed * scale
	local step  = moveDir * speed * dt
	local newPos = curPos + step
	
	hrp.CFrame = CFrame.new(newPos, newPos + moveDir)
end

-- Smoothly adjusts the camera to aim at the target with slight inaccuracy.
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
