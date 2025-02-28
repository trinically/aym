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
	ClimbRate = 8
}

local GROUND_OFFSET = 3
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
	local newPos = curPos + moveDir * hum.WalkSpeed * dt
	local newY
	if tarPos.Y - curPos.Y >= 15 then
		newY = math.min(curPos.Y + CONFIG.ClimbRate * dt, tarPos.Y + GROUND_OFFSET)
	else
		newY = math.max(curPos.Y, GROUND_OFFSET)
	end
	newPos = Vector3.new(newPos.X, newY, newPos.Z)
	local lookDir = (tarPos - curPos)
	lookDir = Vector3.new(lookDir.X, 0, lookDir.Z).Unit
	hrp.CFrame = CFrame.new(newPos, newPos + lookDir)
end

local function aimLock()
	if not CONFIG.Active or not target or not target.PrimaryPart then
		return
	end
	local aimPart = target:FindFirstChild("Head") or target:FindFirstChild("Torso") or target.PrimaryPart
	local tarPos = aimPart.Position
	local inacc = (100 - CONFIG.AimAcc) / 100
	local randOff = Vector3.new(math.random(-10, 10) * inacc / 100, math.random(-10, 10) * inacc / 100, math.random(-10, 10) * inacc / 100)
	local desired = CFrame.new(cam.CFrame.Position, tarPos + randOff)
	cam.CFrame = cam.CFrame:Lerp(desired, CONFIG.AimSpd / 10)
end

local function activateTool()
	if player.Character then
		local tool = player.Character:FindFirstChildWhichIsA("Tool")
		if tool then
			pcall(function() tool:Activate() end)
		end
	end
end

local function toggleTarget(_, state)
	if state == Enum.UserInputState.Begin then
		CONFIG.Active = not CONFIG.Active
	end
end

ContextActionService:BindAction("ToggleTarget", toggleTarget, true, CONFIG.ToggleKey)
ContextActionService:SetTitle("ToggleTarget", "Target")
ContextActionService:SetPosition("ToggleTarget", UDim2.new(0.5, 0, 0.5, 0))

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
		if hum then
			hum:Move(Vector3.new(0, 0, 0), false)
		end
	end
	activateTool()
end)
