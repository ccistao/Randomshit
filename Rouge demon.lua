    
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local LocalPlayer = Players.LocalPlayer

local noCooldownEnabled = true
local enhancedDash = true
local spamDashMode = false
local dashSpamRate = 0.05
local forceBreathCharge = true

local connections = {}
local lastDashTime = 0
local dashService = nil
local knitControllers = {}
local dashButton = nil

local function findKnitServices()
    pcall(function()
        local Knit = require(ReplicatedStorage.Knit.Packages.Knit)
        dashService = Knit.GetService("DashService")
        knitControllers.DustController = Knit.GetController("DustController")
        knitControllers.InvisibilityController = Knit.GetController("InvisibilityController") 
        knitControllers.CombatParticleController = Knit.GetController("CombatParticleController")
    end)
end

local function findDashButton()
    task.spawn(function()
        while task.wait(1) do
            pcall(function()
                local playerGui = LocalPlayer.PlayerGui
                for _, gui in pairs(playerGui:GetDescendants()) do
                    if gui:IsA("TextButton") or gui:IsA("ImageButton") then
                        if gui.Name:lower():find("dash") or 
                           (gui.Parent and gui.Parent.Name:lower():find("dash")) then
                            dashButton = gui
                            break
                        end
                    end
                end
            end)
        end
    end)
end

local function hookDashButton()
    task.spawn(function()
        while task.wait(0.5) do
            if dashButton and noCooldownEnabled then
                pcall(function()
                    if not dashButton.Active then
                        dashButton.Active = true
                    end
                    dashButton.Interactable = true
                    dashButton.Modal = false
                end)
            end
        end
    end)
end

local function hookDashCooldown()
    connections.cooldownHook = RunService.Heartbeat:Connect(function()
        if not noCooldownEnabled then return end
        
        pcall(function()
            local character = LocalPlayer.Character
            if character then
                local dashCooldown = character:FindFirstChild("DashCooldown")
                if dashCooldown and dashCooldown:IsA("NumberValue") then
                    dashCooldown.Value = 0
                end
                
                local cooldown = character:FindFirstChild("Cooldown")
                if cooldown and cooldown:IsA("NumberValue") then
                    cooldown.Value = 0
                end
            end
        end)
        
        if dashButton then
            pcall(function()
                dashButton.Active = true
                dashButton.Interactable = true
            end)
        end
    end)
end

local function createDashEffects(character, hasBreathCharge)
    if not character then return end
    
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoidRootPart or not humanoid then return end
    
    if hasBreathCharge or forceBreathCharge then
        pcall(function()
            if knitControllers.InvisibilityController then
                knitControllers.InvisibilityController:HideCharacter(character)
            end
            
            local Shadow = ReplicatedStorage.Utils.Shadow
            if Shadow then
                local shadowClone = Shadow:Clone()
                shadowClone.Parent = workspace.Debris
                Debris:AddItem(shadowClone, 1)
                
                for _, part in pairs(shadowClone:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CollisionGroup = "NonCollidable"
                    end
                end
                
                local shadowRoot = shadowClone:FindFirstChild("HumanoidRootPart")
                if shadowRoot then
                    shadowRoot.Anchored = true
                    shadowRoot.CFrame = humanoidRootPart.CFrame
                    
                    for _, part in pairs(shadowClone:GetChildren()) do
                        if part:IsA("BasePart") then
                            TweenService:Create(part, TweenInfo.new(0.3), {
                                Transparency = 1
                            }):Play()
                        end
                    end
                end
            end
            
            task.delay(0.2, function()
                if knitControllers.InvisibilityController then
                    knitControllers.InvisibilityController:UnhideCharacter(character)
                end
            end)
        end)
    end
    
    pcall(function()
        if knitControllers.CombatParticleController then
            knitControllers.CombatParticleController:EmitPreset(character, "Dash")
        end
    end)
    
    pcall(function()
        local Swoosh = ReplicatedStorage.Sounds.ThunderBreathing.Sixfold.Swoosh
        if Swoosh then
            local swooshClone = Swoosh:Clone()
            swooshClone.Parent = humanoidRootPart
            swooshClone:Play()
            Debris:AddItem(swooshClone, swooshClone.TimeLength)
        end
    end)
    
    pcall(function()
        if knitControllers.DustController then
            knitControllers.DustController:EnableTrail(character, 0.2)
        end
    end)
end

local function performCustomDash()
    local character = LocalPlayer.Character
    if not character then return end
    
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoidRootPart or not humanoid then return end
    
    local breathCharge = character:FindFirstChild("BreathCharge")
    local hasBreathCharge = breathCharge and breathCharge.Value >= 1
    
    if forceBreathCharge and breathCharge then
        breathCharge.Value = math.max(breathCharge.Value, 1)
        hasBreathCharge = true
    end
    
    createDashEffects(character, hasBreathCharge)
    
    local moveDirection = humanoid.MoveDirection
    if moveDirection.Magnitude == 0 then
        moveDirection = humanoidRootPart.CFrame.LookVector
    end
    
    local bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.Parent = humanoidRootPart
    bodyVelocity.MaxForce = Vector3.new(40000, 0, 40000)
    bodyVelocity.P = 40000
    
    local speed = hasBreathCharge and 90 or 50
    if enhancedDash then
        speed = speed * 1.5
    end
    
    bodyVelocity.Velocity = moveDirection * speed
    Debris:AddItem(bodyVelocity, 0.2)
    
    if dashService and dashService.Dash then
        pcall(function()
            dashService.Dash:Fire()
        end)
    end
    
    lastDashTime = tick()
end

local function hookDashInputs()
    connections.inputHook = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        if input.KeyCode == Enum.KeyCode.Q and noCooldownEnabled then
            if not UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonL1) and
               not UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonR1) then
                performCustomDash()
            end
        end
        
        if input.KeyCode == Enum.KeyCode.F9 then
            noCooldownEnabled = not noCooldownEnabled
        end
        
        if input.KeyCode == Enum.KeyCode.F10 then
            spamDashMode = not spamDashMode
        end
        
        if input.KeyCode == Enum.KeyCode.F11 then
            enhancedDash = not enhancedDash
        end
        
        if input.KeyCode == Enum.KeyCode.F12 then
            forceBreathCharge = not forceBreathCharge
        end
    end)
end

local function maintainBreathCharge()
    connections.breathMaintainer = RunService.Heartbeat:Connect(function()
        if not forceBreathCharge then return end
        
        local character = LocalPlayer.Character
        if character then
            local breathCharge = character:FindFirstChild("BreathCharge")
            if breathCharge and breathCharge.Value < 1 then
                breathCharge.Value = 100
            end
        end
    end)
end

local function startSpamDash()
    connections.spamDash = RunService.Heartbeat:Connect(function()
        if not spamDashMode or not noCooldownEnabled then return end
        
        if tick() - lastDashTime >= dashSpamRate then
            performCustomDash()
        end
    end)
end

local function makeDraggable(frame)
    local dragging = false
    local dragStart = nil
    local startPos = nil
    
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)
    
    frame.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)
end

local function createToggleButton(parent, position, callback)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(0, 65, 0, 35)
    button.Position = position
    button.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
    button.BorderSizePixel = 0
    button.Text = "ON"
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.TextSize = 18
    button.Font = Enum.Font.SourceSansBold
    button.Parent = parent
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = button
    
    button.MouseButton1Click:Connect(function()
        callback(button)
    end)
    
    return button
end

local function createGUI()
    local gui = Instance.new("ScreenGui")
    gui.Name = "KnitDashGUI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = LocalPlayer.PlayerGui
    
    local minimizedIcon = Instance.new("TextButton")
    minimizedIcon.Name = "MinimizedIcon"
    minimizedIcon.Size = UDim2.new(0, 55, 0, 55)
    minimizedIcon.Position = UDim2.new(1, -65, 0.5, -27)
    minimizedIcon.BackgroundColor3 = Color3.fromRGB(30, 30, 50)
    minimizedIcon.BackgroundTransparency = 0.4
    minimizedIcon.BorderSizePixel = 0
    minimizedIcon.Visible = false
    minimizedIcon.Text = "D"
    minimizedIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
    minimizedIcon.TextSize = 30
    minimizedIcon.Font = Enum.Font.SourceSansBold
    minimizedIcon.Parent = gui
    
    local iconCorner = Instance.new("UICorner")
    iconCorner.CornerRadius = UDim.new(1, 0)
    iconCorner.Parent = minimizedIcon
    
    makeDraggable(minimizedIcon)
    
    local frame = Instance.new("Frame")
    frame.Name = "MainFrame"
    frame.Size = UDim2.new(0, 360, 0, 250)
    frame.Position = UDim2.new(0.5, -180, 0.5, -125)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 50)
    frame.BorderSizePixel = 0
    frame.Parent = gui
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 15)
    corner.Parent = frame
    
    local topBar = Instance.new("Frame")
    topBar.Name = "TopBar"
    topBar.Size = UDim2.new(1, 0, 0, 50)
    topBar.BackgroundColor3 = Color3.fromRGB(40, 40, 65)
    topBar.BorderSizePixel = 0
    topBar.Parent = frame
    
    local topCorner = Instance.new("UICorner")
    topCorner.CornerRadius = UDim.new(0, 15)
    topCorner.Parent = topBar
    
    local bottomFix = Instance.new("Frame")
    bottomFix.Size = UDim2.new(1, 0, 0, 15)
    bottomFix.Position = UDim2.new(0, 0, 1, -15)
    bottomFix.BackgroundColor3 = Color3.fromRGB(40, 40, 65)
    bottomFix.BorderSizePixel = 0
    bottomFix.Parent = topBar
    
    makeDraggable(frame)
    
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -55, 1, 0)
    title.Position = UDim2.new(0, 18, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "Knit Dash"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 24
    title.Font = Enum.Font.SourceSansBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = topBar
    
    local minimizeBtn = Instance.new("TextButton")
    minimizeBtn.Name = "MinimizeButton"
    minimizeBtn.Size = UDim2.new(0, 40, 0, 40)
    minimizeBtn.Position = UDim2.new(1, -47, 0, 5)
    minimizeBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
    minimizeBtn.BorderSizePixel = 0
    minimizeBtn.Text = "_"
    minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    minimizeBtn.TextSize = 26
    minimizeBtn.Font = Enum.Font.SourceSansBold
    minimizeBtn.Parent = topBar
    
    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 10)
    btnCorner.Parent = minimizeBtn
    
    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Size = UDim2.new(1, -36, 1, -68)
    content.Position = UDim2.new(0, 18, 0, 58)
    content.BackgroundTransparency = 1
    content.Parent = frame
    
    local cooldownLabel = Instance.new("TextLabel")
    cooldownLabel.Size = UDim2.new(0.5, 0, 0.23, 0)
    cooldownLabel.Position = UDim2.new(0, 0, 0, 0)
    cooldownLabel.BackgroundTransparency = 1
    cooldownLabel.Text = "No Cooldown"
    cooldownLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    cooldownLabel.TextSize = 20
    cooldownLabel.Font = Enum.Font.SourceSansBold
    cooldownLabel.TextXAlignment = Enum.TextXAlignment.Left
    cooldownLabel.Parent = content
    
    local cooldownBtn = createToggleButton(content, UDim2.new(1, -70, 0, 3), function(btn)
        noCooldownEnabled = not noCooldownEnabled
        if noCooldownEnabled then
            btn.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
            btn.Text = "ON"
        else
            btn.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
            btn.Text = "OFF"
        end
    end)
    
    local enhancedLabel = Instance.new("TextLabel")
    enhancedLabel.Size = UDim2.new(0.5, 0, 0.23, 0)
    enhancedLabel.Position = UDim2.new(0, 0, 0.27, 0)
    enhancedLabel.BackgroundTransparency = 1
    enhancedLabel.Text = "Enhanced"
    enhancedLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    enhancedLabel.TextSize = 20
    enhancedLabel.Font = Enum.Font.SourceSansBold
    enhancedLabel.TextXAlignment = Enum.TextXAlignment.Left
    enhancedLabel.Parent = content
    
    local enhancedBtn = createToggleButton(content, UDim2.new(1, -70, 0.27, 3), function(btn)
        enhancedDash = not enhancedDash
        if enhancedDash then
            btn.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
            btn.Text = "ON"
        else
            btn.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
            btn.Text = "OFF"
        end
    end)
    
    local spamLabel = Instance.new("TextLabel")
    spamLabel.Size = UDim2.new(0.5, 0, 0.23, 0)
    spamLabel.Position = UDim2.new(0, 0, 0.54, 0)
    spamLabel.BackgroundTransparency = 1
    spamLabel.Text = "Spam Mode"
    spamLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    spamLabel.TextSize = 20
    spamLabel.Font = Enum.Font.SourceSansBold
    spamLabel.TextXAlignment = Enum.TextXAlignment.Left
    spamLabel.Parent = content
    
    local spamBtn = createToggleButton(content, UDim2.new(1, -70, 0.54, 3), function(btn)
        spamDashMode = not spamDashMode
        if spamDashMode then
            btn.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
            btn.Text = "ON"
        else
            btn.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
            btn.Text = "OFF"
        end
    end)
    spamBtn.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    spamBtn.Text = "OFF"
    
    local breathLabel = Instance.new("TextLabel")
    breathLabel.Size = UDim2.new(0.5, 0, 0.23, 0)
    breathLabel.Position = UDim2.new(0, 0, 0.81, 0)
    breathLabel.BackgroundTransparency = 1
    breathLabel.Text = "Force Breath"
    breathLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    breathLabel.TextSize = 20
    breathLabel.Font = Enum.Font.SourceSansBold
    breathLabel.TextXAlignment = Enum.TextXAlignment.Left
    breathLabel.Parent = content
    
    local breathBtn = createToggleButton(content, UDim2.new(1, -70, 0.81, 3), function(btn)
        forceBreathCharge = not forceBreathCharge
        if forceBreathCharge then
            btn.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
            btn.Text = "ON"
        else
            btn.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
            btn.Text = "OFF"
        end
    end)
    
    minimizeBtn.MouseButton1Click:Connect(function()
        frame.Visible = false
        minimizedIcon.Visible = true
    end)
    
    minimizedIcon.MouseButton1Click:Connect(function()
        minimizedIcon.Visible = false
        frame.Visible = true
    end)
end

local function initialize()
    findKnitServices()
    findDashButton()
    hookDashInputs()
    hookDashCooldown()
    hookDashButton()
    maintainBreathCharge()
    startSpamDash()
    createGUI()
end

getgenv().ToggleNoCooldown = function()
    noCooldownEnabled = not noCooldownEnabled
end

getgenv().ToggleSpamDash = function()
    spamDashMode = not spamDashMode
end

getgenv().ToggleEnhancedDash = function()
    enhancedDash = not enhancedDash
end

getgenv().ToggleForceBreath = function()
    forceBreathCharge = not forceBreathCharge
end

getgenv().CustomDash = function()
    performCustomDash()
end

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(2)
    findKnitServices()
    findDashButton()
end)

if LocalPlayer.Character then
    initialize()
else
    LocalPlayer.CharacterAdded:Connect(initialize)
end
