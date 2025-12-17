
Search

Get Paid to Paste!
Rogue Demon 01.10.25

Bottom of paste
-- No Dash Cooldown Script for Knit Framework
-- Removes dash cooldowns and enables unlimited dashing

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local LocalPlayer = Players.LocalPlayer

-- Configuration
local noCooldownEnabled = true
local enhancedDash = true
local spamDashMode = false
local dashSpamRate = 0.05
local forceBreathCharge = true -- Always use enhanced dash effects

-- Storage
local connections = {}
local lastDashTime = 0
local dashService = nil
local knitControllers = {}

print("No Dash Cooldown Script (Knit Framework) Loading...")

-- Function to find and hook Knit services
local function findKnitServices()
    pcall(function()
        local Knit = require(ReplicatedStorage.Knit.Packages.Knit)
        
        -- Try to get the DashService
        dashService = Knit.GetService("DashService")
        
        -- Try to get useful controllers
        knitControllers.DustController = Knit.GetController("DustController")
        knitControllers.InvisibilityController = Knit.GetController("InvisibilityController") 
        knitControllers.CombatParticleController = Knit.GetController("CombatParticleController")
        
        if dashService then
            print("Found DashService!")
        end
    end)
end

-- Function to create custom dash effects based on decompiled code
local function createDashEffects(character, hasBreathCharge)
    if not character then return end
    
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoidRootPart or not humanoid then return end
    
    -- Enhanced dash effects if breath charge is available or forced
    if hasBreathCharge or forceBreathCharge then
        -- Shadow clone effect
        pcall(function()
            if knitControllers.InvisibilityController then
                knitControllers.InvisibilityController:HideCharacter(character)
            end
            
            local Shadow = ReplicatedStorage.Utils.Shadow
            if Shadow then
                local shadowClone = Shadow:Clone()
                shadowClone.Parent = workspace.Debris
                Debris:AddItem(shadowClone, 1)
                
                -- Set collision group for shadow parts
                for _, part in pairs(shadowClone:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CollisionGroup = "NonCollidable"
                    end
                end
                
                -- Position shadow
                local shadowRoot = shadowClone:FindFirstChild("HumanoidRootPart")
                if shadowRoot then
                    shadowRoot.Anchored = true
                    shadowRoot.CFrame = humanoidRootPart.CFrame
                    
                    -- Fade out shadow
                    for _, part in pairs(shadowClone:GetChildren()) do
                        if part:IsA("BasePart") then
                            TweenService:Create(part, TweenInfo.new(0.3), {
                                Transparency = 1
                            }):Play()
                        end
                    end
                end
            end
            
            -- Unhide character after brief delay
            task.delay(0.2, function()
                if knitControllers.InvisibilityController then
                    knitControllers.InvisibilityController:UnhideCharacter(character)
                end
            end)
        end)
    end
    
    -- Combat particle effects
    pcall(function()
        if knitControllers.CombatParticleController then
            knitControllers.CombatParticleController:EmitPreset(character, "Dash")
        end
    end)
    
    -- Swoosh sound effect
    pcall(function()
        local Swoosh = ReplicatedStorage.Sounds.ThunderBreathing.Sixfold.Swoosh
        if Swoosh then
            local swooshClone = Swoosh:Clone()
            swooshClone.Parent = humanoidRootPart
            swooshClone:Play()
            Debris:AddItem(swooshClone, swooshClone.TimeLength)
        end
    end)
    
    -- Dust trail effect
    pcall(function()
        if knitControllers.DustController then
            knitControllers.DustController:EnableTrail(character, 0.2)
        end
    end)
    
    print("Dash effects applied with breath charge:", hasBreathCharge or forceBreathCharge)
end

-- Function to perform custom dash
local function performCustomDash()
    local character = LocalPlayer.Character
    if not character then return end
    
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoidRootPart or not humanoid then return end
    
    -- Check breath charge
    local breathCharge = character:FindFirstChild("BreathCharge")
    local hasBreathCharge = breathCharge and breathCharge.Value >= 1
    
    -- Force breath charge if enabled
    if forceBreathCharge and breathCharge then
        breathCharge.Value = math.max(breathCharge.Value, 1)
        hasBreathCharge = true
    end
    
    -- Create dash effects
    createDashEffects(character, hasBreathCharge)
    
    -- Create movement
    local moveDirection = humanoid.MoveDirection
    if moveDirection.Magnitude == 0 then
        moveDirection = humanoidRootPart.CFrame.LookVector
    end
    
    local bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.Parent = humanoidRootPart
    bodyVelocity.MaxForce = Vector3.new(40000, 0, 40000)
    bodyVelocity.P = 40000
    
    -- Set velocity based on breath charge
    local speed = hasBreathCharge and 90 or 50
    if enhancedDash then
        speed = speed * 1.5 -- Enhance speed
    end
    
    bodyVelocity.Velocity = moveDirection * speed
    Debris:AddItem(bodyVelocity, 0.2)
    
    -- Fire dash service if available
    if dashService and dashService.Dash then
        pcall(function()
            dashService.Dash:Fire()
        end)
    end
    
    lastDashTime = tick()
    print("Custom dash executed with speed:", speed)
end

-- Function to hook dash inputs
local function hookDashInputs()
    connections.inputHook = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        -- Q key for dash (original key)
        if input.KeyCode == Enum.KeyCode.Q and noCooldownEnabled then
            -- Check for gamepad conflicts (from original code)
            if not UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonL1) and
               not UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonR1) then
                performCustomDash()
            end
        end
        
        -- Additional keybinds
        if input.KeyCode == Enum.KeyCode.F9 then
            noCooldownEnabled = not noCooldownEnabled
            print("No Dash Cooldown:", noCooldownEnabled and "ON" or "OFF")
        end
        
        if input.KeyCode == Enum.KeyCode.F10 then
            spamDashMode = not spamDashMode
            print("Spam Dash Mode:", spamDashMode and "ON" or "OFF")
        end
        
        if input.KeyCode == Enum.KeyCode.F11 then
            enhancedDash = not enhancedDash
            print("Enhanced Dash:", enhancedDash and "ON" or "OFF")
        end
        
        if input.KeyCode == Enum.KeyCode.F12 then
            forceBreathCharge = not forceBreathCharge
            print("Force Breath Charge:", forceBreathCharge and "ON" or "OFF")
        end
    end)
end

-- Function to maintain breath charge
local function maintainBreathCharge()
    connections.breathMaintainer = RunService.Heartbeat:Connect(function()
        if not forceBreathCharge then return end
        
        local character = LocalPlayer.Character
        if character then
            local breathCharge = character:FindFirstChild("BreathCharge")
            if breathCharge and breathCharge.Value < 1 then
                breathCharge.Value = 100 -- Set high value
            end
        end
    end)
end

-- Spam dash functionality
local function startSpamDash()
    connections.spamDash = RunService.Heartbeat:Connect(function()
        if not spamDashMode or not noCooldownEnabled then return end
        
        if tick() - lastDashTime >= dashSpamRate then
            performCustomDash()
        end
    end)
end

-- Create GUI
local function createGUI()
    local gui = Instance.new("ScreenGui")
    gui.Name = "KnitDashGUI"
    gui.ResetOnSpawn = false
    gui.Parent = LocalPlayer.PlayerGui
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 250, 0, 140)
    frame.Position = UDim2.new(0, 10, 0, 400)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 50)
    frame.BorderSizePixel = 0
    frame.Parent = gui
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame
    
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0.2, 0)
    title.BackgroundTransparency = 1
    title.Text = "Knit Dash Exploit"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextScaled = true
    title.Font = Enum.Font.SourceSansBold
    title.Parent = frame
    
    local cooldownLabel = Instance.new("TextLabel")
    cooldownLabel.Size = UDim2.new(1, 0, 0.2, 0)
    cooldownLabel.Position = UDim2.new(0, 0, 0.2, 0)
    cooldownLabel.BackgroundTransparency = 1
    cooldownLabel.Text = "No Cooldown: ON"
    cooldownLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
    cooldownLabel.TextScaled = true
    cooldownLabel.Font = Enum.Font.SourceSans
    cooldownLabel.Parent = frame
    
    local enhancedLabel = Instance.new("TextLabel")
    enhancedLabel.Size = UDim2.new(1, 0, 0.2, 0)
    enhancedLabel.Position = UDim2.new(0, 0, 0.4, 0)
    enhancedLabel.BackgroundTransparency = 1
    enhancedLabel.Text = "Enhanced: ON"
    enhancedLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
    enhancedLabel.TextScaled = true
    enhancedLabel.Font = Enum.Font.SourceSans
    enhancedLabel.Parent = frame
    
    local spamLabel = Instance.new("TextLabel")
    spamLabel.Size = UDim2.new(1, 0, 0.2, 0)
    spamLabel.Position = UDim2.new(0, 0, 0.6, 0)
    spamLabel.BackgroundTransparency = 1
    spamLabel.Text = "Spam Mode: OFF"
    spamLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
    spamLabel.TextScaled = true
    spamLabel.Font = Enum.Font.SourceSans
    spamLabel.Parent = frame
    
    local breathLabel = Instance.new("TextLabel")
    breathLabel.Size = UDim2.new(1, 0, 0.2, 0)
    breathLabel.Position = UDim2.new(0, 0, 0.8, 0)
    breathLabel.BackgroundTransparency = 1
    breathLabel.Text = "Force Breath: ON"
    breathLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
    breathLabel.TextScaled = true
    breathLabel.Font = Enum.Font.SourceSans
    breathLabel.Parent = frame
    
    local function updateGUI()
        cooldownLabel.Text = "No Cooldown: " .. (noCooldownEnabled and "ON" or "OFF")
        cooldownLabel.TextColor3 = noCooldownEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
        
        enhancedLabel.Text = "Enhanced: " .. (enhancedDash and "ON" or "OFF")
        enhancedLabel.TextColor3 = enhancedDash and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
        
        spamLabel.Text = "Spam Mode: " .. (spamDashMode and "ON" or "OFF")
        spamLabel.TextColor3 = spamDashMode and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
        
        breathLabel.Text = "Force Breath: " .. (forceBreathCharge and "ON" or "OFF")
        breathLabel.TextColor3 = forceBreathCharge and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
    end
    
    return updateGUI
end

-- Initialize everything
local function initialize()
    findKnitServices()
    hookDashInputs()
    maintainBreathCharge()
    startSpamDash()
    
    local updateGUI = createGUI()
    if updateGUI then
        task.spawn(function()
            while task.wait(0.5) do
                pcall(updateGUI)
            end
        end)
    end
    
    print("Knit Dash Exploit initialized!")
end

-- Global functions
getgenv().ToggleNoCooldown = function()
    noCooldownEnabled = not noCooldownEnabled
    print("No Cooldown:", noCooldownEnabled)
end

getgenv().ToggleSpamDash = function()
    spamDashMode = not spamDashMode
    print("Spam Dash:", spamDashMode)
end

getgenv().ToggleEnhancedDash = function()
    enhancedDash = not enhancedDash
    print("Enhanced Dash:", enhancedDash)
end

getgenv().ToggleForceBreath = function()
    forceBreathCharge = not forceBreathCharge
    print("Force Breath Charge:", forceBreathCharge)
end

getgenv().CustomDash = function()
    performCustomDash()
end

-- Character handling
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(2)
    findKnitServices()
end)

-- Start the script
if LocalPlayer.Character then
    initialize()
else
    LocalPlayer.CharacterAdded:Connect(initialize)
end

print("No Dash Cooldown Script (Knit Framework) Loaded!")
print("Controls:")
print("- Q: Instant dash (original key)")
print("- F9: Toggle no cooldown")
print("- F10: Toggle spam dash mode")
print("- F11: Toggle enhanced dash")
print("- F12: Toggle force breath charge")
print("Functions:")
print("- getgenv().ToggleNoCooldown()")
print("- getgenv().ToggleSpamDash()")
print("- getgenv().ToggleEnhancedDash()")
print("- getgenv().ToggleForceBreath()")
print("- getgenv().CustomDash()")
