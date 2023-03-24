--[[Variables]]--

-- Services

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local UserInputService = game:GetService('UserInputService')
local TweenService = game:GetService('TweenService')
local PlayersService = game:GetService('Players')
local RunService = game:GetService('RunService')

-- Objects

local Data = ReplicatedStorage:WaitForChild('Data')
local Player = PlayersService.LocalPlayer
local Mouse = Player:GetMouse()

local PlayerGui = script.Parent.Parent.Parent
local ShipGuiFolder = script.Parent.Parent
local ShipGui = ShipGuiFolder:WaitForChild('ShipGui')
local ChatGui = PlayerGui:WaitForChild('Chat')
local ChatInstances = ChatGui:GetDescendants()
local ChatBar

for _, Gui in pairs(ChatInstances) do
	if Gui.Name ~= "ChatBar" then continue else
		ChatBar = Gui
		break
	end
end

local Remotes = ReplicatedStorage:WaitForChild('Remotes')
local ShipRemotes = Remotes:WaitForChild('Ship')

local UpdateSpeed = ShipRemotes:WaitForChild('UpdateSpeed')
local UpdatePitch = ShipRemotes:WaitForChild('UpdatePitch')
local UpdateYaw = ShipRemotes:WaitForChild('UpdateYaw')

local Modules = ReplicatedStorage:WaitForChild('Modules')
local InfoModules = Modules:WaitForChild('Info')

-- Data

local RenderPriority = require(InfoModules:WaitForChild('RenderPriority'))
local FormattedItems = require(InfoModules:WaitForChild('FormattedItems'))
local ShipControls = require(Data:WaitForChild('ShipControls'))

local KeyCodes = Enum.KeyCode

local CameraModule = require(ReplicatedStorage:WaitForChild('CameraModule'))

local MinimumZoom = 0.5
local MaximumZoom = 12.0

local PlayerModule = require(Player.PlayerScripts:WaitForChild("PlayerModule"))
local PlayerControls = PlayerModule:GetControls()

local Camera = workspace.CurrentCamera

local fullRad = math.pi

local Dividen = 2

local CameraOffset = ShipControls.CameraOffset
local CameraLockedValue = ShipControls.CameraLocked
local CameraZoomValue = ShipControls.CameraZoom
local ZoomLocked = ShipControls.ZoomLocked
local MovementDisabled = ShipControls.MovementDisabled
local StopShip = ShipControls.StopShip
local CameraMovementLocked = ShipControls.CameraMovementLocked
local CameraZoomLocked = ShipControls.CameraZoomLocked
local InWarp = ShipControls.InWarp
local IsCharging = ShipControls.IsCharging
local CurrentSpeed = ShipControls.CurrentSpeed
local WarpTime = ShipControls.WarpTime
local WarpTimeLeft = ShipControls.WarpTimeLeft

local EngineAttachments = {
	EndAttachment1 = 4.56,
	EndAttachment2 = 3.39,
	EndAttachment3 = 1.74,
	EndAttachment4 = 0.97,
	StartAttachment = 0
}

local Windth1 = 0.194

local EngineBeams = {
	Beam1 = 0.80,
	Beam2 = 0.61,
	Beam3 = 0.41,
	Beam4 = 0.22,
}

local EngineBeamsTransparency = {
	Beam1 = .5,
	Beam2 = .75,
	Beam3 = .7,
	Beam4 = .7,
}

local DefaultEngineColor = Color3.fromRGB(2, 33, 48)
local FullEngineColor = Color3.fromRGB(7, 110, 165)

local WarpEngineColor = Color3.fromRGB(255, 15, 159)

-- Functions

local function lerp(a, b, t)
	return a + (b - a) * t
end

local TInsert = table.insert

--[[Script]]--

RunService:BindToRenderStep("MouseLock",Enum.RenderPriority.Last.Value+1,function()
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
end)

ShipControls.IsMouseLocked:GetPropertyChangedSignal('Value'):Connect(function()
	if ShipControls.IsMouseLocked.Value >= 1 then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		RunService:UnbindFromRenderStep("MouseLock")
	else
		RunService:BindToRenderStep("MouseLock",Enum.RenderPriority.Last.Value+1,function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end)
	end
end)

local Pilot = {}

function Pilot.new(ShipModel:Model, NavigationStats, ShipType, ShipShield:Part)
	local DefaultShipModel:Model = FormattedItems[ShipType].Model

	PlayerControls:Disable()
	local Connections = {}
	local Running = true

	local SpeedRange = NavigationStats.Speed -- Range of Minimum & Maximum speed
	local AccelRange = NavigationStats.Accel -- Range for Negative & Positive speed accel (Min = Negative, Max = Positive)
	SpeedRange = NumberRange.new(SpeedRange.Min / Dividen, SpeedRange.Max / Dividen)
	AccelRange = NumberRange.new(AccelRange.Min / Dividen, AccelRange.Max / Dividen)

	local Primary = ShipModel.PrimaryPart -- Seat
	local CentreAttachment = Primary.CentreAttachment
	local Angular: AngularVelocity = Primary.Angular -- Angular Velocity
	local Linear: LinearVelocity = Primary.Linear -- Linear Velocity
	local Engines = ShipModel:WaitForChild('Structure'):WaitForChild('Engines')

	local _, ModelSize = DefaultShipModel:GetBoundingBox()

	local Controls = {
		["Strafe"] = {0, KeyCodes.T, KeyCodes.G},
		["Accel"] = {0, KeyCodes.R, KeyCodes.F},
		["Pitch"] = {0, KeyCodes.S, KeyCodes.W},
		["Roll"] = {0, KeyCodes.Q, KeyCodes.E},
		["Yaw"] = {0, KeyCodes.A, KeyCodes.D},
	} -- List of Positive and Negative controls - (Value, Positive, Negative)

	local Movement = {}

	local function CreateMovement(Name)
		local Val = Instance.new('NumberValue') -- Speed of Movement
		Val.Value = 0
		Val.Name = Name
		local BVal = Instance.new('BoolValue') -- True if tweening
		BVal.Value = false
		BVal.Name = "Tweening"
		local BEvent = Instance.new('BindableEvent') -- Event fired when players presses control
		BEvent.Name = "Controlled"
		Movement[Name] = {Val, BVal, BEvent}
	end

	CreateMovement("Speed")

	local DirectionalMovements = {"Pitch","Roll","Yaw","Strafe"} -- Names of secondary movements
	local DirectionalRanges = {} -- Number ranges of max & min for secondary movements

	for i, MovementType in pairs(DirectionalMovements) do
		CreateMovement(MovementType)
		DirectionalRanges[MovementType] = NavigationStats[MovementType]
	end

	local DefaultDistance = CameraModule.GetFitDistance(DefaultShipModel:GetPivot().Position, DefaultShipModel, Camera)

	local CameraOrientation = CFrame.fromEulerAnglesXYZ(0,0,0)
	local CameraAxis = Vector2.new(0,0)
	local CameraZoom = 2
	local CameraZoom_Current = Instance.new('NumberValue')
	CameraZoom_Current.Value = CameraZoom

	local ZoomTween = TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

	ShipShield.Transparency = 1

	local ShieldTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Linear)

	local TweeningDown = false
	local TweenedDown = false
	local TweeningUp = false
	local TweenedUp = false
	local ShieldUp = ShipShield.CanQuery

	local ShieldTweenZoom = 1.5

	local function Update()
		ShieldUp = ShipShield.CanQuery
		if ShieldUp == false then
			local ShieldTween = TweenService:Create(ShipShield, ShieldTweenInfo, {Transparency = 1})
			ShieldTween:Play()
			TweenedDown = false
			TweeningDown = false
			TweeningUp = false
			TweenedUp = true
		elseif ShieldUp then
			local Current = CameraZoom_Current.Value

			if (Current <= ShieldTweenZoom) and (not TweeningDown) and (not TweenedDown) then
				TweeningDown = true
				TweenedDown = true
				TweenedUp = false
				local ShieldTween = TweenService:Create(ShipShield, ShieldTweenInfo, {Transparency = 1})
				ShieldTween:Play()
				TInsert(Connections, ShieldTween.Completed:Once(function(PBS)
					TweeningDown = false
				end))
				return
			end

			if (Current > ShieldTweenZoom) and (not TweeningUp) and (not TweenedUp) then
				TweeningUp = true
				TweenedUp = true
				TweenedDown = false
				local ShieldTween = TweenService:Create(ShipShield, ShieldTweenInfo, {Transparency = 0.9})
				ShieldTween:Play()
				TInsert(Connections, ShieldTween.Completed:Once(function()
					TweeningUp = false
				end))
				return
			end
		end
	end

	TInsert(Connections, ShipShield:GetPropertyChangedSignal('Transparency'):Connect(function()
		if TweenedDown and not TweeningDown then
			ShipShield.Transparency = 1
			return
		end
		if TweenedUp and not TweeningUp then
			ShipShield.Transparency = 1
		end
	end))

	TInsert(Connections, CameraZoom_Current:GetPropertyChangedSignal('Value'):Connect(Update))

	local ZoomingIn = false
	local LookingBack = false
	local CameraLocked = false
	
	local function UpdateDistance(zoom) -- Tweens Camera Zoom Value
		if zoom < MinimumZoom or zoom > MaximumZoom or ZoomLocked.Value then return end
		CameraZoom = zoom
		if not ZoomingIn then
			local Tween = TweenService:Create(CameraZoom_Current, ZoomTween, {Value = CameraZoom})
			Tween:Play()
		end
	end

	local function ZoomCamera(start)
		
		if start then
			ZoomingIn = true
			local FOVTweenIn = TweenService:Create(Camera, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				FieldOfView = 50
			})
			local ZoomTweenIn = TweenService:Create(CameraZoom_Current, ZoomTween, {
				Value = 0.5
			})
			ZoomTweenIn:Play()
			FOVTweenIn:Play()
		else
			ZoomingIn = false
			local FOVTweenOut = TweenService:Create(Camera, TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
				FieldOfView = 70
			})
			local ZoomTweenOut = TweenService:Create(CameraZoom_Current, ZoomTween, {
				Value = CameraZoom
			})
			ZoomTweenOut:Play()
			FOVTweenOut:Play()
		end
		
	end
	
	TInsert(Connections, CameraLockedValue:GetPropertyChangedSignal("Value"):Connect(function()
		if CameraLockedValue.Value == true then
			CameraLocked = true
			CameraAxis = Vector2.new(0,0)
		else
			CameraLocked = false
		end
	end))
	
	TInsert(Connections, CameraZoomValue:GetPropertyChangedSignal("Value"):Connect(function()
		UpdateDistance(CameraZoomValue.Value)
	end))

	local CustomControls = {
		[KeyCodes.X] = function(start) 
			if start then
				local Tween = TweenService:Create(Movement['Speed'][1], TweenInfo.new(Movement['Speed'][1].Value/math.abs(AccelRange.Min), Enum.EasingStyle.Linear), {Value = 0})
				Tween:Play()
				TInsert(Connections, Movement['Speed'][3].Event:Once(function()
					Tween:Cancel()
				end))
				return Tween
			end
		end,
		[KeyCodes.C] = function(start)
			if (start) and CameraLockedValue.Value == false then
				CameraLocked = not CameraLocked
				if CameraLocked then
					CameraAxis = Vector2.new(0,0)
				end
			end
		end,
		[KeyCodes.B] = function(start)
			LookingBack = start
		end,
		[KeyCodes.LeftShift] = ZoomCamera,
		[KeyCodes.RightShift] = ZoomCamera,
	}
	
	StopShip.OnInvoke = function()
		return CustomControls[KeyCodes.X](true)
	end

	TInsert(Connections, Mouse.Move:Connect(function()
		if (CameraLocked == false) and (CameraMovementLocked.Value == false) then
			local Moved = UserInputService:GetMouseDelta()/(3 * (ZoomingIn and 3 or 1))
			local ResultX, ResultY = (Moved.X + CameraAxis.X) % 360, (Moved.Y + CameraAxis.Y) % 360
			CameraAxis = Vector2.new(ResultX, ResultY)
		end
	end))

	TInsert(Connections, Mouse.WheelForward:Connect(function()
		if CameraZoomLocked.Value then return end
		UpdateDistance(CameraZoom-0.5)
	end))

	TInsert(Connections, Mouse.WheelBackward:Connect(function()
		if CameraZoomLocked.Value then return end
		UpdateDistance(CameraZoom+0.5)
	end))

	TInsert(Connections, UserInputService.InputBegan:Connect(function(input, GPE)
		if GPE then return end
		local InputFunction = CustomControls[input.KeyCode]
		if InputFunction then
			InputFunction(true)
		end
	end))
	TInsert(Connections, UserInputService.InputEnded:Connect(function(input, GPE)
		if GPE then return end
		local InputFunction = CustomControls[input.KeyCode]
		if InputFunction then
			InputFunction(false)
		end
	end))

	Camera.CameraType = Enum.CameraType.Scriptable

	local function UpdateControls()
		if not ChatBar:IsFocused() then -- I REFUSE to use ContextActionService or InputBegan i'am an independent programmer that does NOT rely on funny roblox stuff
			for n, t in pairs(Controls) do
				local KeyStart = UserInputService:IsKeyDown(t[2]) and 1 or 0 -- Ok listen, listen. weird but it's done for a reason i care not explain.
				local KeyEnd = UserInputService:IsKeyDown(t[3]) and -1 or 0
				local v = KeyStart + KeyEnd
				Controls[n][1] = v
			end
		end
	end
	
	
	-- VFX Zone [START]
	
	for _, Engine in Engines:GetChildren() do
		local Neon: Part = Engine.Neon
		local SizeY = Neon.Size.Y

		Neon.Color = DefaultEngineColor
		
		local StartAttachment = Neon:FindFirstChild("StartAttachment")
		local Particle = StartAttachment:FindFirstChild("Emitter")
		Particle.Size = NumberSequence.new(SizeY/3,0)

		for _, Child in Neon:GetChildren() do
			if Child:IsA("Beam") then
				Child.Width0 = EngineBeams[Child.Name] * SizeY
				if Child.Name == "Beam4" then continue end
				Child.Width1 = Windth1 * SizeY
			end
		end
	end
	
	-- VFX Zone [END]
	
	local LastUpdate = 0
	
	local LastPitch = 0
	local LastYaw = 0
	
	local ShipAmbience = Primary:WaitForChild('ShipAmbience')

	local function UpdateMovement(DeltaTime)
		LastUpdate += DeltaTime
		
		CurrentSpeed.Value = Movement['Speed'][1].Value * Dividen
		
		local CPitch = Movement["Pitch"][1].Value
		local CYaw = Movement["Yaw"][1].Value
		
		local NewPitch = if CPitch > 0 then 1 elseif CPitch < 0 then -1 else 0
		local NewYaw = if CYaw > 0 then 1 elseif CYaw < 0 then -1 else 0
		
		if NewPitch ~= LastPitch then
			UpdatePitch:FireServer(NewPitch)
			LastPitch = NewPitch
		end
		if NewYaw ~= LastYaw then
			UpdateYaw:FireServer(NewYaw)
			LastYaw = NewYaw
		end
		
		if LastUpdate >= .5 then
			UpdateSpeed:FireServer(Movement['Speed'][1].Value)
			LastUpdate = 0
		end
		
		-- VFX Zone [START]
		
		if MovementDisabled.Value then 
			Angular.AngularVelocity = Vector3.new(Movement["Pitch"][1].Value, Movement["Yaw"][1].Value, Movement["Roll"][1].Value)
			Linear.VectorVelocity = Vector3.new(0, Movement['Strafe'][1].Value, -Movement['Speed'][1].Value)
			
			if IsCharging.Value then return end
			
			if InWarp.Value == true then
				
				local EngineV = 2
				
				if WarpTime.Value < 1 then
					EngineV = WarpTime.Value * 2
				elseif WarpTimeLeft.Value < 2 then
					EngineV = WarpTimeLeft.Value
				end

				for _, Engine in Engines:GetChildren() do
					local Neon: Part = Engine.Neon
					local SizeY = Neon.Size.Y

					Neon.Color = DefaultEngineColor:Lerp(WarpEngineColor, math.clamp(WarpTimeLeft.Value/2, 0, 1))

					local StartAttachment = Neon:FindFirstChild("StartAttachment")
					local Particle: ParticleEmitter = StartAttachment:FindFirstChild("Emitter")
					Particle.Lifetime = NumberRange.new(SizeY * EngineV / 4)
					Particle.Rate = 100
					Particle.Speed = NumberRange.new(EngineAttachments.EndAttachment1 * SizeY * 4)
					StartAttachment.CFrame = CFrame.lookAt(StartAttachment.Position, Neon.EndAttachment1.Position)

					for _, Child in Neon:GetChildren() do
						if Child:IsA("Attachment") then
							local Length = EngineAttachments[Child.Name]
							Child.Position = Vector3.new(Length * SizeY * EngineV * 1.5, Movement["Pitch"][1].Value * EngineV * Length/3, Movement["Yaw"][1].Value * EngineV * Length/3)
						elseif Child:IsA("Beam") then
							Child.LightEmission = EngineV
							Child.LightInfluence = EngineV
							Child.Transparency = NumberSequence.new(lerp(1, EngineBeamsTransparency[Child.Name], EngineV),1)
						end
					end
				end
			else
				local EngineV = Movement["Speed"][1].Value/SpeedRange.Max
				
				ShipAmbience.Volume = lerp(.25, 2, EngineV)
				ShipAmbience.PitchEffect.Octave = lerp(1,1.25, EngineV)

				for _, Engine in Engines:GetChildren() do
					local Neon: Part = Engine.Neon
					local SizeY = Neon.Size.Y

					Neon.Color = DefaultEngineColor:Lerp(FullEngineColor, EngineV)

					local StartAttachment = Neon:FindFirstChild("StartAttachment")
					local Particle: ParticleEmitter = StartAttachment:FindFirstChild("Emitter")
					Particle.Lifetime = NumberRange.new(SizeY * EngineV)
					Particle.Rate = 50 * (EngineV)
					Particle.Speed = NumberRange.new(EngineAttachments.EndAttachment1 * SizeY)
					StartAttachment.CFrame = CFrame.lookAt(StartAttachment.Position, Neon.EndAttachment1.Position)

					for _, Child in Neon:GetChildren() do
						if Child:IsA("Attachment") then
							local Length = EngineAttachments[Child.Name]
							Child.Position = Vector3.new(Length * SizeY * EngineV * 1.5, Movement["Pitch"][1].Value * EngineV * Length/3, Movement["Yaw"][1].Value * EngineV * Length/3)
						elseif Child:IsA("Beam") then
							Child.LightEmission = EngineV
							Child.LightInfluence = EngineV
							Child.Transparency = NumberSequence.new(lerp(1, EngineBeamsTransparency[Child.Name], EngineV),1)
						end
					end
				end
			end
			
			return
		end
		
		-- VFX Zone [END]
		
		-- Speed
		do
			local AccelHeld = Controls['Accel'][1]
			local SpeedValue = Movement['Speed'][1].Value
			local AccelV =  (if AccelHeld == 1 then AccelRange.Max elseif AccelHeld == -1 then (if SpeedValue > 0 then AccelRange.Min else AccelRange.Min/3) else 0)
			local NewAccel = AccelV * DeltaTime
			if NewAccel ~= 0 then
				Movement['Speed'][3]:Fire()
				local NewSpeed = SpeedValue + NewAccel
				if NewSpeed > SpeedRange.Max then NewSpeed = SpeedRange.Max end
				if NewSpeed < SpeedRange.Min then NewSpeed = SpeedRange.Min end
				Movement['Speed'][1].Value = NewSpeed

			elseif SpeedValue < 0 then
				local NewSpeed = SpeedValue + -(AccelRange.Min * DeltaTime)/3
				if NewSpeed > 0 then Movement['Speed'][1].Value = 0 else
					Movement['Speed'][1].Value = NewSpeed
				end
			end
		end

		-- Pitch, Roll, Yaw
		do
			for _, MovementType in pairs(DirectionalMovements) do
				local MovementHeld = Controls[MovementType][1]
				local MovementCur = Movement[MovementType]
				local MovementValueObject = MovementCur[1]
				local MovementValue = MovementValueObject.Value
				local MovementTweening = MovementCur[2]
				local MovementRange = DirectionalRanges[MovementType]
				local MovementV = (if MovementHeld == 1 then MovementRange.Max elseif MovementHeld == -1 then MovementRange.Min else 0)
				local NewMovement = (MovementV * DeltaTime) * 2
				if NewMovement ~= 0 then
					MovementTweening.Value = false
					MovementCur[3]:Fire()
					local NewSpeed = MovementValue + NewMovement
					if NewSpeed > MovementRange.Max then NewSpeed = MovementRange.Max end
					if NewSpeed < MovementRange.Min then NewSpeed = MovementRange.Min end
					MovementValueObject.Value = NewSpeed
				elseif MovementTweening.Value == false then
					MovementTweening.Value = true
					local Tween = TweenService:Create(MovementValueObject, TweenInfo.new(math.abs(MovementValue)/2, Enum.EasingStyle.Linear), {Value = 0})
					Tween:Play()
					TInsert(Connections, MovementCur[3].Event:Once(function()
						Tween:Cancel()
					end))
				end
			end
		end
		
		-- VFX Zone [START]
		
		local EngineV = Movement["Speed"][1].Value/SpeedRange.Max
		
		ShipAmbience.Volume = lerp(.25, 2, EngineV)
		ShipAmbience.PitchEffect.Octave = lerp(1,1.25, EngineV)

		for _, Engine in Engines:GetChildren() do
			local Neon: Part = Engine.Neon
			local SizeY = Neon.Size.Y

			Neon.Color = DefaultEngineColor:Lerp(FullEngineColor, EngineV)
			
			local StartAttachment = Neon:FindFirstChild("StartAttachment")
			local Particle: ParticleEmitter = StartAttachment:FindFirstChild("Emitter")
			Particle.Lifetime = NumberRange.new(SizeY * EngineV)
			Particle.Rate = 50 * (EngineV)
			Particle.Speed = NumberRange.new(EngineAttachments.EndAttachment1 * SizeY)
			StartAttachment.CFrame = CFrame.lookAt(StartAttachment.Position, Neon.EndAttachment1.Position)

			for _, Child in Neon:GetChildren() do
				if Child:IsA("Attachment") then
					local Length = EngineAttachments[Child.Name]
					Child.Position = Vector3.new(Length * SizeY * EngineV * 1.5, Movement["Pitch"][1].Value * EngineV * Length/3, Movement["Yaw"][1].Value * EngineV * Length/3)
				elseif Child:IsA("Beam") then
					Child.LightEmission = EngineV
					Child.LightInfluence = EngineV
					Child.Transparency = NumberSequence.new(lerp(1, EngineBeamsTransparency[Child.Name], EngineV),1)
				end
			end
		end
		
		-- VFX Zone [END]
		
		Angular.AngularVelocity = Vector3.new(Movement["Pitch"][1].Value, Movement["Yaw"][1].Value, Movement["Roll"][1].Value)
		Linear.VectorVelocity = Vector3.new(0, Movement['Strafe'][1].Value, -Movement['Speed'][1].Value)
	end

	local function UpdateCamera()
		local CameraOffsetVal = CameraOffset.Value
		if LookingBack then
			CameraOrientation = CFrame.fromEulerAnglesYXZ(-math.rad(CameraAxis.Y), fullRad-math.rad(CameraAxis.X), 0)
		else
			CameraOrientation = CFrame.fromEulerAnglesYXZ(-math.rad(CameraAxis.Y), -math.rad(CameraAxis.X), 0)
		end
		Camera.CFrame = CentreAttachment.WorldCFrame * CameraOrientation * CFrame.new(0 + CameraOffsetVal.X,ModelSize.Y + CameraOffsetVal.Y, DefaultDistance * CameraZoom_Current.Value + CameraOffsetVal.Z)
	end

	local function Destroy()
		Running = false
		for _, Connection in pairs(Connections) do
			Connection:Disconnect()
		end
		RunService:UnbindFromRenderStep("SHIP_CAMERA")
		RunService:UnbindFromRenderStep("SHIP_INPUT")
		RunService:UnbindFromRenderStep("SHIP_MOVEMENT")
		PlayerControls:Enable()
		Linear.VectorVelocity = Vector3.new(0,0,0)
		Angular.AngularVelocity = Vector3.new(0,0,0)
	end
	
	RunService:BindToRenderStep("SHIP_CAMERA", RenderPriority.SHIP_CAMERA, UpdateCamera)
	RunService:BindToRenderStep("SHIP_INPUT", RenderPriority.SHIP_INPUT, UpdateControls)
	RunService:BindToRenderStep("SHIP_MOVEMENT", RenderPriority.SHIP_MOVEMENT, UpdateMovement)

	return Destroy
end

return Pilot
