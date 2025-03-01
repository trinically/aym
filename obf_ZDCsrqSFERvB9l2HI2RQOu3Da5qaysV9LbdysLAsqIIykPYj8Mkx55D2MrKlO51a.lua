--!nocheck
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local CONFIG = {
	Active = true,
	TargetDist = 5,
	DetectDist = 1000,
	MaxVert = 20,
	AimAcc = 100,
	AimSpd = 8,
	RetargetInt = 5,
	ToggleKey = Enum.KeyCode.F,
	ClimbRate = 8,
	ClimbThreshold = 15,
	FootOffsetAdd = 0
}

local player = Players.LocalPlayer
local cam = workspace.CurrentCamera
local target = nil
local lastRetarget = 0

local function getTarget()
	if not player.Character or not player.Character.PrimaryPart then
		return nil
	end
	local bestTarg, bestDist = nil, CONFIG.DetectDist
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

-- Updated noclip handler:
-- • If an obstruction is detected from either the head or torso,
--   we compute its horizontal distance relative to the character’s HRP.
-- • If that distance is less than 2 studs and the hit is below, we treat it as a platform (keep collision true).
-- • Otherwise, for obstructions ahead or above, we disable collision (and hide it) and adjust the target Y
--   so that your character’s HRP is teleported above the obstacle.
local function updateNoclip(newPos, moveDir)
	local char = player.Character
	if not char then return newPos end
	local hrp = char.PrimaryPart
	local hum = char:FindFirstChildOfClass("Humanoid")
	local footOffset = (hum and hum.HipHeight or 2.8) + CONFIG.FootOffsetAdd
	
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {char}
	rayParams.FilterType = Enum.RaycastFilterType.Blacklist
	
	-- Check from key points (head and torso)
	local checkPoints = {}
	local head = char:FindFirstChild("Head")
	local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
	if head then table.insert(checkPoints, head.Position) end
	if torso then table.insert(checkPoints, torso.Position) end

	for _, point in ipairs(checkPoints) do
		local ray = workspace:Raycast(point, moveDir * 2, rayParams)
		if ray and ray.Instance and not ray.Instance:IsDescendantOf(char) then
			local hitPart = ray.Instance
			local hitPos = ray.Position
			-- Calculate horizontal (XZ) distance between HRP and the hit point.
			local horizontalDist = Vector3.new(hitPos.X - hrp.Position.X, 0, hitPos.Z - hrp.Position.Z).Magnitude
			-- If the hit is directly below (within 2 studs horizontally and below HRP), treat as platform.
			if horizontalDist < 2 and (hrp.Position.Y - hitPos.Y) > 0 then
				hitPart.CanCollide = true
			else
				-- For obstructions ahead or above, disable collision and hide the part.
				hitPart.CanCollide = false
				hitPart.Transparency = 1
				-- Adjust newPos so your character is teleported above the obstacle.
				-- We assume the obstacle’s top is at hitPart.Position.Y plus half its size.
				local partTop = hitPart.Position.Y + (hitPart.Size.Y / 2)
				newPos = Vector3.new(newPos.X, partTop + footOffset, newPos.Z)
			end
		end
	end

	return newPos
end

local function moveTarget(dt)
	if not target or not target.PrimaryPart or not player.Character or not player.Character.PrimaryPart then
		return
	end
	local char = player.Character
	local hrp = char.PrimaryPart
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	local curPos = hrp.Position
	local tarPos = target.PrimaryPart.Position
	local diff = tarPos - curPos
	local moveDir = diff.Unit
	local speed = hum.WalkSpeed
	local newPos = curPos + moveDir * speed * dt

	-- Determine ground level using a downward raycast from above current position.
	local checkPos = curPos + Vector3.new(0, 5, 0)
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {char}
	rayParams.FilterType = Enum.RaycastFilterType.Blacklist
	local ray = workspace:Raycast(checkPos, Vector3.new(0, -50, 0), rayParams)
	local footOffset = (hum.HipHeight or 2.8) + CONFIG.FootOffsetAdd
	local groundY = ray and (ray.Position.Y + footOffset) or curPos.Y

	local newY
	if tarPos.Y - curPos.Y >= CONFIG.ClimbThreshold then
		newY = math.min(curPos.Y + CONFIG.ClimbRate * dt, tarPos.Y)
	else
		newY = groundY
	end
	newPos = Vector3.new(newPos.X, newY, newPos.Z)
	
	-- Adjust newPos based on potential obstructions.
	newPos = updateNoclip(newPos, moveDir)
	
	local lookDir = (tarPos - curPos)
	lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
	lookDir = lookDir.Magnitude > 0 and lookDir.Unit or Vector3.new(0, 0, 1)
	hrp.CFrame = CFrame.new(newPos, newPos + lookDir)
end

local function aimLock()
	if not CONFIG.Active or not target or not target.PrimaryPart then
		return
	end
	local aimPart = target:FindFirstChild("Head") or target:FindFirstChild("Torso") or target.PrimaryPart
	local tarPos = aimPart.Position
	local inacc = (100 - CONFIG.AimAcc) / 100
	local randOff = Vector3.new(math.random(-10,10)*inacc/100, math.random(-10,10)*inacc/100, math.random(-10,10)*inacc/100)
	local desired = CFrame.new(cam.CFrame.Position, tarPos + randOff)
	cam.CFrame = cam.CFrame:Lerp(desired, CONFIG.AimSpd/10)
end

local function activateTool()
	if player.Character then
		local tool = player.Character:FindFirstChildWhichIsA("Tool")
		if tool then pcall(function() tool:Activate() end) end
	end
end

local function toggleTarget(_, state)
	if state == Enum.UserInputState.Begin then
		CONFIG.Active = not CONFIG.Active
	end
end

ContextActionService:BindAction("ToggleTarget", toggleTarget, true, CONFIG.ToggleKey)
ContextActionService:SetTitle("ToggleTarget", "Target")
ContextActionService:SetPosition("ToggleTarget", UDim2.new(0.5,0,0.5,0))

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

RunService.Heartbeat:Connect(function(dt)
	activateTool()
	if not CONFIG.Active then return end
	if not player.Character or not player.Character.PrimaryPart then return end
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
		if hum then hum:Move(Vector3.new(0,0,0), false) end
	end
end)
