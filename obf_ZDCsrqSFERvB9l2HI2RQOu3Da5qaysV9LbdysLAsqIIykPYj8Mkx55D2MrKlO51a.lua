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
	ZigFreq = 7,
	ZigAmp = 3,
	FlankInt = 2,
	FlankAmp = 3,
	RetargetInt = 5,
	ChaseThresh = 7,
	ToggleKey = Enum.KeyCode.F,
	ClimbRate = 8
}
local player = Players.LocalPlayer
local cam = workspace.CurrentCamera
local target = nil
local lastRetarget = 0
local lastFlankSwitch = tick()
local currentFlankDir = 1
local function getTarget()
	if not player.Character or not player.Character.PrimaryPart then return nil end
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
local function moveTarget(dt)
	if not target or not target.PrimaryPart or not player.Character or not player.Character.PrimaryPart then return end
	local char = player.Character
	local hrp = char.PrimaryPart
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local curPos = hrp.Position
	local tarPos = target.PrimaryPart.Position
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {char}
	rayParams.FilterType = Enum.RaycastFilterType.Blacklist
	local groundCheck = workspace:Raycast(curPos, Vector3.new(0, -10, 0), rayParams)
	local hipHeight = hum.HipHeight or 2
	local groundY = groundCheck and (groundCheck.Position.Y + hipHeight) or curPos.Y
	local diff = tarPos - curPos
	local horiz = Vector3.new(diff.X, 0, diff.Z)
	local horizDist = horiz.Magnitude
	local moveDir
	if horizDist < CONFIG.ChaseThresh then
		moveDir = diff.Unit
	else
		local forward = horiz.Unit
		local right = forward:Cross(Vector3.new(0, 1, 0)).Unit
		local timeNow = tick()
		if timeNow - lastFlankSwitch > CONFIG.FlankInt then
			currentFlankDir = (math.random(0,1) == 0) and -1 or 1
			lastFlankSwitch = timeNow
		end
		local zigzag = math.sin(timeNow * CONFIG.ZigFreq) * CONFIG.ZigAmp
		local flank = currentFlankDir * CONFIG.FlankAmp
		local lateral = right * (zigzag + flank)
		local horizontalDir = (forward + lateral).Unit
		local verticalFactor = diff.Y / math.max(horizDist, 1)
		moveDir = Vector3.new(horizontalDir.X, verticalFactor, horizontalDir.Z).Unit
	end
	local targetY = tarPos.Y
	local newY
	if targetY > groundY + 15 then
		newY = math.clamp(curPos.Y + CONFIG.ClimbRate * dt, curPos.Y, targetY)
	else
		newY = groundY
	end
	local horizontalStep = Vector3.new(moveDir.X, 0, moveDir.Z) * hum.WalkSpeed * dt
	local newPos = curPos + horizontalStep
	newPos = Vector3.new(newPos.X, newY, newPos.Z)
	local lookDir = Vector3.new(moveDir.X, 0, moveDir.Z)
	if lookDir.Magnitude > 0 then lookDir = lookDir.Unit end
	hrp.CFrame = CFrame.new(newPos, newPos + lookDir)
end
local function aimLock()
	if not CONFIG.Active or not target or not target.PrimaryPart then return end
	local aimPart = target:FindFirstChild("Head") or target:FindFirstChild("Torso") or target.PrimaryPart
	local tarPos = aimPart.Position
	local inacc = (100 - CONFIG.AimAcc) / 100
	local randOff = Vector3.new(math.random(-10,10) * inacc / 100, math.random(-10,10) * inacc / 100, math.random(-10,10) * inacc / 100)
	local desired = CFrame.new(cam.CFrame.Position, tarPos + randOff)
	cam.CFrame = cam.CFrame:Lerp(desired, CONFIG.AimSpd / 10)
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
		if not CONFIG.Active and player.Character then
			local hum = player.Character:FindFirstChildOfClass("Humanoid")
			if hum then hum:Move(Vector3.new(0,0,0), false) end
		end
	end
end
ContextActionService:BindAction("ToggleTarget", toggleTarget, true, CONFIG.ToggleKey)
ContextActionService:SetTitle("ToggleTarget", "Target")
ContextActionService:SetPosition("ToggleTarget", UDim2.new(0.5, 0, 0.5, 0))
local function onToolAdded(child)
	if child:IsA("Tool") then pcall(function() child:Activate() end) end
end
if player.Character then
	player.Character.ChildAdded:Connect(onToolAdded)
end
player.CharacterAdded:Connect(function(char)
	char.ChildAdded:Connect(onToolAdded)
end)
RunService.Heartbeat:Connect(function(dt)
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
	activateTool()
end)
