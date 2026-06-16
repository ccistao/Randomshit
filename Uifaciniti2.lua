local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")
local RunService       = game:GetService("RunService")
local Replicated       = game:GetService("ReplicatedStorage")
local StarterGui       = game:GetService("StarterGui")
local TextService      = game:GetService("TextService")

local lp = Players.LocalPlayer
repeat task.wait() until lp and lp:FindFirstChild("PlayerGui")
local pgui = lp:FindFirstChildOfClass("PlayerGui")

local DISCORD_LINK = "https://discord.gg/Ep8rjFC7DM"

local function CopyText(text)
     if setclipboard then pcall(function() setclipboard(text) end) return true end
     if writeclipboard then pcall(function() writeclipboard(text) end) return true end
     if toclipboard then pcall(function() toclipboard(text) end) return true end
     local ok = pcall(function() StarterGui:SetCore("Clipboard", text) end)
     return ok
end

local function TypeGlitch(lbl, text, speed)
    speed = speed or 0.015
    local g = {"!","@","#","$","%","&","*","0","1","X","Z"}
    lbl.Text = ""
    local charsPerStep = speed <= 0.005 and 3 or speed <= 0.01 and 2 or 1
    local i = 1
    while i <= #text do
        local currentEnd = math.min(i + charsPerStep - 1, #text)
        local pre = text:sub(1, currentEnd - 1)
        local nx = text:sub(currentEnd, currentEnd)
        if speed > 0.005 and nx ~= " " and nx ~= "\n" then
            lbl.Text = pre .. g[math.random(#g)]
            task.wait(speed * 0.4)
        end
        lbl.Text = text:sub(1, currentEnd)
        i = currentEnd + 1
        task.wait(speed)   
    end
end

local function isMobile()
    return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end
local function tw(obj, info, props)
    local t = TweenService:Create(obj, info, props); t:Play(); return t
end
local function corner(p, r)
    local c = Instance.new("UICorner", p); c.CornerRadius = UDim.new(0, r or 8); return c
end
local function stroke(p, col, thick, trans)
    local s = Instance.new("UIStroke", p)
    s.Color=col or Color3.new(1,1,1); s.Thickness=thick or 1; s.Transparency=trans or 0.88; return s
end
local function pad(p, t, b, l, r)
    local u = Instance.new("UIPadding", p)
    u.PaddingTop=UDim.new(0,t or 0); u.PaddingBottom=UDim.new(0,b or 0)
    u.PaddingLeft=UDim.new(0,l or 0); u.PaddingRight=UDim.new(0,r or 0)
end
local syncFns = {}

local WallhopView = {enabled=false, connections={}, cachedParts={}}
local RADIUS, SCAN_DELAY = 35, 0.5

local function GetHRP()
    local c = lp.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function IsCharacterPart(part)
    local m = part:FindFirstAncestorOfClass("Model")
    return m and Players:GetPlayerFromCharacter(m) ~= nil
end

local function AddOutline(part)
    if part:FindFirstChildOfClass("SelectionBox") then return end
    local s = Instance.new("SelectionBox")
    s.Adornee = part; s.LineThickness = 0.025
    s.Color3 = Color3.new(1,1,1); s.SurfaceTransparency = 1; s.Parent = part
end

local function RemoveOutline(part)
    local s = part:FindFirstChildOfClass("SelectionBox")
    if s then s:Destroy() end
end

function WallhopView.start()
    if WallhopView.enabled then return end
    WallhopView.enabled = true
    local op = OverlapParams.new()
    op.FilterType = Enum.RaycastFilterType.Exclude
    local t = task.spawn(function()
        while task.wait(SCAN_DELAY) do
            if not WallhopView.enabled then break end
            local hrp = GetHRP()
            if not hrp then continue end
            op.FilterDescendantsInstances = {lp.Character}
            local parts = workspace:GetPartBoundsInRadius(hrp.Position, RADIUS, op)
            local seen = {}
            for _, p in ipairs(parts) do
                if p:IsA("Part") and p.Shape == Enum.PartType.Block
                    and not IsCharacterPart(p) and p.Transparency < 0.95
                    and p.CanCollide and (p.Size.X*p.Size.Y*p.Size.Z) >= 30
                then
                    seen[p] = true
                    if not WallhopView.cachedParts[p] then AddOutline(p); WallhopView.cachedParts[p] = true end
                end
            end
            for p in pairs(WallhopView.cachedParts) do
                if not seen[p] or not p.Parent then RemoveOutline(p); WallhopView.cachedParts[p] = nil end
            end
        end
    end)
    table.insert(WallhopView.connections, t)
end

function WallhopView.stop()
    WallhopView.enabled = false
    for _, c in pairs(WallhopView.connections) do
        if typeof(c)=="thread" then task.cancel(c)
        elseif typeof(c)=="RBXScriptConnection" then c:Disconnect() end
    end
    WallhopView.connections = {}
    for p in pairs(WallhopView.cachedParts) do RemoveOutline(p) end
    WallhopView.cachedParts = {}
end

local Flashlight = {enabled=false, connections={}, originalSettings={}}

local function dofullbright()
    Lighting.Ambient = Color3.new(1,1,1)
    Lighting.ColorShift_Bottom = Color3.new(1,1,1)
    Lighting.ColorShift_Top = Color3.new(1,1,1)
end

function Flashlight.start()
    if Flashlight.enabled then return end
    Flashlight.enabled = true
    Flashlight.originalSettings = {
        Ambient = Lighting.Ambient,
        ColorShift_Bottom = Lighting.ColorShift_Bottom,
        ColorShift_Top = Lighting.ColorShift_Top
    }
    dofullbright()
    local c = Lighting.LightingChanged:Connect(function()
        if Flashlight.enabled then dofullbright() end
    end)
    table.insert(Flashlight.connections, c)
end

function Flashlight.stop()
    Flashlight.enabled = false
    for _, c in pairs(Flashlight.connections) do
        if typeof(c)=="RBXScriptConnection" then c:Disconnect() end
    end
    Flashlight.connections = {}
    if Flashlight.originalSettings.Ambient then
        Lighting.Ambient = Flashlight.originalSettings.Ambient
        Lighting.ColorShift_Bottom = Flashlight.originalSettings.ColorShift_Bottom
        Lighting.ColorShift_Top = Flashlight.originalSettings.ColorShift_Top
    end
end

local SelfMuting = {enabled=false, connections={}, muted={}, scanInterval=0.25}

local function isLocalCharacterAncestor(inst)
    local m = inst and inst:FindFirstAncestorOfClass("Model")
    if not m then return false end
    return Players:GetPlayerFromCharacter(m) == lp
end

local function cleanupMutedEntry(s)
    if not s then return end
    local e = SelfMuting.muted[s]
    if e then
        if e.c1 then pcall(function() e.c1:Disconnect() end) end
        if e.c2 then pcall(function() e.c2:Disconnect() end) end
        if e.c3 then pcall(function() e.c3:Disconnect() end) end
        if e.d  then pcall(function() e.d:Disconnect()  end) end
        SelfMuting.muted[s] = nil
    end
end

local function applyMuteToSound(s)
    if not s or not s:IsA("Sound") then return end
    if not isLocalCharacterAncestor(s) then return end
    if SelfMuting.muted[s] then return end
    local ok, vol = pcall(function() return s.Volume end)
    local orig = (ok and vol) and vol or 1
    pcall(function() s.Volume = 0; s:Stop() end)
    local e = {orig=orig}
    e.c1 = s:GetPropertyChangedSignal("Volume"):Connect(function()
        if not s or not s.Parent then cleanupMutedEntry(s) return end
        if SelfMuting.enabled and s.Volume ~= 0 then pcall(function() s.Volume = 0 end) end
    end)
    e.c2 = s:GetPropertyChangedSignal("Playing"):Connect(function()
        if not s or not s.Parent then cleanupMutedEntry(s) return end
        if SelfMuting.enabled and s.Playing then pcall(function() s:Stop() end) end
    end)
    e.c3 = s:GetPropertyChangedSignal("Parent"):Connect(function()
        if not s or not s.Parent then cleanupMutedEntry(s) return end
        if isLocalCharacterAncestor(s) then
            if SelfMuting.enabled then pcall(function() s.Volume=0; s:Stop() end) end
        else cleanupMutedEntry(s) end
    end)
    e.d = s.Destroying:Connect(function() cleanupMutedEntry(s) end)
    SelfMuting.muted[s] = e
end

local function scanCharacterSounds()
    local char = lp.Character
    if not char then return end
    for _, obj in ipairs(char:GetDescendants()) do
        if obj:IsA("Sound") and SelfMuting.enabled then applyMuteToSound(obj) end
    end
end

local function globalDescendantHandler(obj)
    if obj:IsA("Sound") then
        if SelfMuting.enabled and isLocalCharacterAncestor(obj) then applyMuteToSound(obj) end
        local c = obj:GetPropertyChangedSignal("Parent"):Connect(function()
            if SelfMuting.enabled and isLocalCharacterAncestor(obj) then applyMuteToSound(obj)
            else cleanupMutedEntry(obj) end
        end)
        table.insert(SelfMuting.connections, c)
    end
end

local function unmuteAll()
    for s, e in pairs(SelfMuting.muted) do
        if s and s.Parent then pcall(function() s.Volume = e.orig end) end
        cleanupMutedEntry(s)
    end
end

function SelfMuting.start()
    if SelfMuting.enabled then return end
    SelfMuting.enabled = true
    local c1 = lp.CharacterAdded:Connect(function()
        task.wait(0.05)
        if SelfMuting.enabled then scanCharacterSounds() end
    end)
    table.insert(SelfMuting.connections, c1)
    if lp.Character then task.spawn(function() task.wait(0.05); if SelfMuting.enabled then scanCharacterSounds() end end) end
    local c2 = game.DescendantAdded:Connect(globalDescendantHandler)
    table.insert(SelfMuting.connections, c2)
    local t = task.spawn(function()
        while true do
            if not SelfMuting.enabled then break end
            scanCharacterSounds()
            task.wait(SelfMuting.scanInterval)
        end
    end)
    table.insert(SelfMuting.connections, t)
end

function SelfMuting.stop()
    SelfMuting.enabled = false
    for _, c in pairs(SelfMuting.connections) do
        if typeof(c)=="RBXScriptConnection" then c:Disconnect()
        elseif typeof(c)=="thread" then task.cancel(c) end
    end
    SelfMuting.connections = {}
    unmuteAll()
end

local beastTrackerRunning = false
local beastConnections = {}
local SKILL_TIMES = {
    runner  = {use=3.5,  cooldown=22},
    stalker = {use=7,    cooldown=20},
    seer    = {use=9.5,  cooldown=28.5}
}
local skill = "Unknown"
local beast, foundBeast = nil, false
local labelCooldown = nil
local isUsingSkill, isCooldown = false, false
local cooldownTimeLeft, usingTimeLeft = 0, 0
local progressPercent, lastValue = nil, 0
local skillDetected, canDetectDrop = false, true
local seerEventConnection = nil
local _beastCheckAccum = 0
local BEAST_CHECK_INTERVAL = 0.1

local function getDisplaySkill()
    return (skill and skill ~= "Unknown") and skill:gsub("^%l", string.upper) or "Skill"
end

local function ensureCooldownUI()
    local existing = pgui:FindFirstChild("BeastCooldownUI")
    if existing then return existing:FindFirstChild("CooldownLabel") end
    local gui = Instance.new("ScreenGui")
    gui.Name = "BeastCooldownUI"; gui.Parent = pgui; gui.ResetOnSpawn = false
    local label = Instance.new("TextLabel")
    label.Name = "CooldownLabel"; label.Parent = gui
    label.Size = UDim2.new(0,200,0,43); label.AnchorPoint = Vector2.new(0.5,0.5)
    label.Position = UDim2.new(0.5,0,0.85,0)
    label.BackgroundColor3 = Color3.fromRGB(0,0,0); label.BackgroundTransparency = 0.3
    label.TextColor3 = Color3.new(1,1,1); label.TextScaled = true
    label.Font = Enum.Font.GothamBold; label.Text = "Finding beast..."
    label.TextStrokeTransparency = 0.5; label.Active = true
    if isMobile() then label.Position = UDim2.new(0.5,0,0.8,0) end
    local ci = Instance.new("UICorner"); ci.CornerRadius = UDim.new(0,12); ci.Parent = label
    local dragging, dragInput, dragStart, startPos
    label.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = input.Position; startPos = label.Position
            input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
        end
    end)
    label.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            label.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+delta.X, startPos.Y.Scale, startPos.Y.Offset+delta.Y)
        end
    end)
    return label
end

local function createRainbowBorder(frame)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,    Color3.fromRGB(255,0,0)),
        ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255,127,0)),
        ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255,255,0)),
        ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(0,255,0)),
        ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0,0,255)),
        ColorSequenceKeypoint.new(0.83, Color3.fromRGB(75,0,130)),
        ColorSequenceKeypoint.new(1,    Color3.fromRGB(148,0,211)),
    })
    g.Parent = frame
    local conn
    conn = RunService.RenderStepped:Connect(function()
        if g and g.Parent then g.Rotation = (g.Rotation+2)%360 else conn:Disconnect() end
    end)
end

local function showBanner(text, name)
    local existing = pgui:FindFirstChild(name)
    if existing then pcall(function() existing:Destroy() end) end
    local gui = Instance.new("ScreenGui")
    gui.Name = name; gui.Parent = pgui; gui.ResetOnSpawn = false
    local label = Instance.new("TextLabel")
    label.Parent = gui; label.Size = UDim2.new(0,250,0,40)
    label.Position = UDim2.new(1,10,0,10)
    label.BackgroundColor3 = Color3.fromRGB(30,30,30); label.TextColor3 = Color3.new(1,1,1)
    label.Font = Enum.Font.GothamBold; label.TextScaled = true; label.Text = text
    label.BorderSizePixel = 3; label.BorderColor3 = Color3.new(1,1,1)
    local p = Instance.new("UIPadding")
    p.PaddingLeft=UDim.new(0,10); p.PaddingRight=UDim.new(0,10)
    p.PaddingTop=UDim.new(0,5); p.PaddingBottom=UDim.new(0,5); p.Parent=label
    createRainbowBorder(label)
    local tweenIn  = TweenService:Create(label, TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out), {Position=UDim2.new(1,-260,0,10)})
    local tweenOut = TweenService:Create(label, TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.In),  {Position=UDim2.new(1,10,0,10)})
    tweenIn:Play(); tweenIn.Completed:Wait()
    task.delay(3.4, function() tweenOut:Play(); tweenOut.Completed:Wait(); pcall(function() gui:Destroy() end) end)
end

local function isGameActive()
    local val = Replicated:FindFirstChild("IsGameActive")
    return val and val.Value == true
end

local function areLightsOff(char)
    if not char then return false end
    local gem = char:FindFirstChild("BeastGem", true)
    local src = gem or char
    for _, v in ipairs(src:GetDescendants()) do
        if v:IsA("PointLight") or v:IsA("SurfaceLight") or v:IsA("SpotLight") then
            if not v.Enabled or v.Brightness == 0 then return true end
        end
    end
    return false
end

local function findProgressPercent()
    if beast and beast.Character then
        local bp = beast.Character:FindFirstChild("BeastPowers")
        if bp then
            progressPercent = bp:FindFirstChild("PowerProgressPercent")
            if progressPercent then lastValue = progressPercent.Value; skillDetected = false; return true end
        end
    end
    return false
end

local function triggerSkillUsed()
    if isUsingSkill or isCooldown then return end
    isUsingSkill = true; isCooldown = false; skillDetected = true
    local sd = SKILL_TIMES[skill] or {use=3.5, cooldown=22}
    usingTimeLeft = sd.use; cooldownTimeLeft = sd.cooldown
    showBanner("Beast used " .. getDisplaySkill() .. " !!!", "SkillUsedBanner")
    if labelCooldown then labelCooldown.Text = string.format("Using %s: %.1fs", getDisplaySkill(), usingTimeLeft) end
end

local function disconnectBeastTracker()
    if _G.BeastHeartbeat then _G.BeastHeartbeat:Disconnect(); _G.BeastHeartbeat = nil end
    for _, c in ipairs(beastConnections) do if typeof(c)=="RBXScriptConnection" then c:Disconnect() end end
    beastConnections = {}
end

local function setBeastTrackerVisible(state)
    local g = pgui:FindFirstChild("BeastCooldownUI")
    if g and g:IsA("ScreenGui") then g.Enabled = state end
end

local function setupSeerDetection()
    if seerEventConnection then seerEventConnection:Disconnect() end
    local we = Replicated:FindFirstChild("WarningEvent")
    if we and we:IsA("RemoteEvent") then
        seerEventConnection = we.OnClientEvent:Connect(function()
            if beastTrackerRunning and foundBeast and skill=="seer" and isGameActive() then triggerSkillUsed() end
        end)
        table.insert(beastConnections, seerEventConnection)
    end
end

local function getBeast()
    for _, p in ipairs(Players:GetPlayers()) do
        local s = p:FindFirstChild("TempPlayerStatsModule")
        if s and s:FindFirstChild("IsBeast") and s.IsBeast.Value then return p end
        if p.Character and p.Character:FindFirstChild("BeastPowers") then return p end
    end
end

local function startBeastTracker()
    if beastTrackerRunning then return end
    beastTrackerRunning = true
    _beastCheckAccum = 0
    labelCooldown = pgui:FindFirstChild("BeastCooldownUI") and pgui.BeastCooldownUI:FindFirstChild("CooldownLabel") or ensureCooldownUI()
    setBeastTrackerVisible(true)
    if labelCooldown then labelCooldown.Text = "Finding beast..." end
    beast, foundBeast, skill = nil, false, "Unknown"
    isUsingSkill = false; isCooldown = false
    progressPercent = nil; lastValue = 0; canDetectDrop = true

    task.spawn(function()
        local dots = 0
        while beastTrackerRunning do
            if not foundBeast then
                if labelCooldown and labelCooldown.Parent then
                    dots = (dots%3)+1
                    labelCooldown.Text = "Finding new beast" .. string.rep(".", dots)
                end
            else dots = 0 end
            task.wait(0.5)
        end
    end)

    task.spawn(function()
        while beastTrackerRunning do
            task.wait(0.2)
            if foundBeast then
                if not beast or not Players:FindFirstChild(beast.Name)
                    or not (beast:FindFirstChild("TempPlayerStatsModule")
                    and beast.TempPlayerStatsModule:FindFirstChild("IsBeast")
                    and beast.TempPlayerStatsModule.IsBeast.Value)
                then beast, foundBeast, skill = nil, false, "Unknown" end
            else
                for _, p in ipairs(Players:GetPlayers()) do
                    local s = p:FindFirstChild("TempPlayerStatsModule")
                    if s and s:FindFirstChild("IsBeast") and s.IsBeast.Value then
                        beast, foundBeast = p, true
                        showBanner(p.Name .. " is Beast!!!", "BeastBanner")
                        task.spawn(function()
                            local ga = Replicated:WaitForChild("IsGameActive", 10)
                            if not ga then return end
                            repeat task.wait(0.5) until ga.Value==true or not beastTrackerRunning
                            local power = Replicated:FindFirstChild("CurrentPower")
                            if power and foundBeast then
                                skill = tostring(power.Value):lower()
                                showBanner("Beast chose " .. getDisplaySkill(), "SkillChosenBanner")
                                table.insert(beastConnections, power:GetPropertyChangedSignal("Value"):Connect(function()
                                    if foundBeast then skill = tostring(power.Value):lower() end
                                end))
                            end
                        end)
                        setupSeerDetection()
                        if labelCooldown then labelCooldown.Text = "Found beast!!!" end
                        task.delay(2.5, function() if foundBeast and labelCooldown then labelCooldown.Text = getDisplaySkill().." Ready!!!" end end)
                        break
                    end
                end
            end
        end
    end)

    if _G.BeastHeartbeat then _G.BeastHeartbeat:Disconnect() end
    _G.BeastHeartbeat = RunService.Heartbeat:Connect(function(dt)
        if not foundBeast or not beast or not Players:FindFirstChild(beast.Name) then return end
        if not labelCooldown or not labelCooldown.Parent then return end
        if isUsingSkill then
            usingTimeLeft = usingTimeLeft - dt
            labelCooldown.Text = string.format("Using %s: %.1fs", getDisplaySkill(), math.max(0,usingTimeLeft))
            if usingTimeLeft <= 0 then isUsingSkill = false; isCooldown = true end
            if progressPercent then lastValue = progressPercent.Value end
            return
        end
        if isCooldown then
            cooldownTimeLeft = cooldownTimeLeft - dt
            labelCooldown.Text = string.format("Cooldown: %.1fs", math.max(0,cooldownTimeLeft))
            if cooldownTimeLeft <= 0 then
                isCooldown = false; skillDetected = false; canDetectDrop = true
                labelCooldown.Text = getDisplaySkill().." Ready!!!"
            end
            if progressPercent then lastValue = progressPercent.Value end
            return
        end
        _beastCheckAccum = _beastCheckAccum + dt
        if _beastCheckAccum < BEAST_CHECK_INTERVAL then return end
        _beastCheckAccum = 0
        if not isGameActive() then
            if progressPercent then lastValue = progressPercent.Value end
            return
        end
        local char = beast.Character
        local hum = char and char:FindFirstChild("Humanoid")
        if hum then
            if skill=="runner" and hum.WalkSpeed > 20 then triggerSkillUsed() end
            if skill=="stalker" and areLightsOff(char) then triggerSkillUsed() end
        end
        if skill=="seer" then
            if not progressPercent or not progressPercent.Parent then findProgressPercent() end
            if progressPercent then
                local cv = progressPercent.Value
                if not canDetectDrop then
                    if cv > 0.98 then canDetectDrop = true end
                else
                    if cv < 0.98 and lastValue > 0.95 and not skillDetected then triggerSkillUsed() end
                end
                if cv >= 0.98 and not isUsingSkill and not isCooldown then skillDetected = false; canDetectDrop = true end
                lastValue = cv
            end
        end
    end)
end

local function stopBeastTracker()
    beastTrackerRunning = false
    setBeastTrackerVisible(false)
    disconnectBeastTracker()
    isUsingSkill=false; isCooldown=false
    cooldownTimeLeft=0; usingTimeLeft=0
    progressPercent=nil; lastValue=0
    skillDetected=false; canDetectDrop=true
end

local SurvivorTracker = {enabled=false, connections={}, activeTimers={}}

local function shortenName(name)
    return #name > 8 and string.sub(name,1,8).."..." or name
end

local function createHeadTimer(char, name)
    local head = char:FindFirstChild("Head")
    if not head then return end
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0,100,0,50); bb.StudsOffset = Vector3.new(0,2.5,0)
    bb.AlwaysOnTop = (lp ~= getBeast()); bb.Parent = head
    local tl = Instance.new("TextLabel")
    tl.Size = UDim2.new(1,0,1,0); tl.BackgroundTransparency = 1
    tl.TextColor3 = Color3.fromRGB(255,0,0); tl.Font = Enum.Font.SourceSansBold
    tl.TextStrokeTransparency = 0; tl.TextStrokeColor3 = Color3.new(0,0,0)
    tl.TextWrapped = true; tl.TextYAlignment = Enum.TextYAlignment.Center
    tl.Text = shortenName(name).."\n28s"
    if UserInputService.TouchEnabled then tl.TextScaled = true else tl.TextScaled = false; tl.TextSize = 20 end
    tl.Parent = bb
    return bb, tl
end

local function stopTimer(player)
    if SurvivorTracker.activeTimers[player] then
        if SurvivorTracker.activeTimers[player].gui then SurvivorTracker.activeTimers[player].gui:Destroy() end
        SurvivorTracker.activeTimers[player] = nil
    end
end

local function hideTimerUI(player)
    if SurvivorTracker.activeTimers[player] then
        if SurvivorTracker.activeTimers[player].gui then
            SurvivorTracker.activeTimers[player].gui:Destroy()
            SurvivorTracker.activeTimers[player].gui = nil
            SurvivorTracker.activeTimers[player].label = nil
        end
    end
end

local function startTimer(player)
    local char = player.Character
    if not char then return end
    if not SurvivorTracker.activeTimers[player] then
        SurvivorTracker.activeTimers[player] = {startTime=os.clock(), gui=nil, label=nil}
    end
    if not SurvivorTracker.activeTimers[player].gui then
        local gui, label = createHeadTimer(char, player.Name)
        SurvivorTracker.activeTimers[player].gui = gui
        SurvivorTracker.activeTimers[player].label = label
    end
end

function SurvivorTracker.start()
    if SurvivorTracker.enabled then return end
    SurvivorTracker.enabled = true
    local t = task.spawn(function()
        while SurvivorTracker.enabled do
            task.wait(0.1)
            local bst = getBeast()
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= lp and plr ~= bst then
                    local char = plr.Character
                    local hum = char and char:FindFirstChild("Humanoid")
                    if hum then
                        if hum.PlatformStand or hum.JumpPower == 0 then startTimer(plr)
                        else stopTimer(plr) end
                    else stopTimer(plr) end
                end
            end
            for player, data in pairs(SurvivorTracker.activeTimers) do
                local elapsed = os.clock() - data.startTime
                local timeLeft = math.max(0, 28.050 - elapsed)
                if data.label then data.label.Text = shortenName(player.Name).."\n"..math.ceil(timeLeft).."s" end
                if timeLeft <= 0 then stopTimer(player) end
            end
        end
    end)
    table.insert(SurvivorTracker.connections, t)
    local c = Players.PlayerRemoving:Connect(function(player) stopTimer(player) end)
    table.insert(SurvivorTracker.connections, c)
end

function SurvivorTracker.stop()
    SurvivorTracker.enabled = false
    for _, c in pairs(SurvivorTracker.connections) do
        if typeof(c)=="RBXScriptConnection" then c:Disconnect() end
    end
    SurvivorTracker.connections = {}
    for player in pairs(SurvivorTracker.activeTimers) do hideTimerUI(player) end
end

local pcProgressRunning = false
local pcConnections = {}

local function disconnectPCProgress()
    for _, c in ipairs(pcConnections) do
        if typeof(c)=="RBXScriptConnection" then c:Disconnect() end
    end
    pcConnections = {}
end

local function stopPCProgress()
    pcProgressRunning = false
    disconnectPCProgress()
    for _, v in pairs(workspace:GetDescendants()) do
        if v:IsA("BillboardGui") and v.Name=="PCProgressBB" then v.Enabled = false end
    end
end

local function startPCProgress()
    if pcProgressRunning then return end
    pcProgressRunning = true
    for _, v in pairs(workspace:GetDescendants()) do
        if v:IsA("BillboardGui") and v.Name=="PCProgressBB" then v.Enabled = true end
    end
    local pcLabels, pcState, hookedPCs, lastPercent = {}, {}, {}, {}
    local pendingUpdate = {}
    local UPDATE_INTERVAL = 0.1

    local function findAttachPart(pc)
        if not pc or not pc.Parent then return nil end
        if pc:IsA("Model") then
            local scr = pc:FindFirstChild("Screen")
            if scr and scr:IsA("BasePart") then return scr end
            if pc.PrimaryPart then return pc.PrimaryPart end
            for _, d in ipairs(pc:GetDescendants()) do if d:IsA("BasePart") then return d end end
        elseif pc:IsA("BasePart") then return pc end
        return nil
    end

    local function createBillboard(pc)
        if not pc or not pc.Parent then return nil end
        if pcLabels[pc] then return pcLabels[pc] end
        local part = findAttachPart(pc)
        if not part then return nil end
        local bb = Instance.new("BillboardGui")
        bb.Name = "PCProgressBB"; bb.Size = UDim2.new(5,0,0,26)
        bb.StudsOffset = Vector3.new(0,3.8,0); bb.AlwaysOnTop = true
        bb.LightInfluence = 0; bb.MaxDistance = math.huge
        bb.DistanceLowerLimit = 15; bb.Adornee = part; bb.Parent = part
        local barBg = Instance.new("Frame")
        barBg.Size = UDim2.new(1,-8,0,14); barBg.Position = UDim2.new(0,4,0,6)
        barBg.BackgroundColor3 = Color3.fromRGB(255,255,255)
        barBg.BackgroundTransparency = 0.75; barBg.BorderSizePixel = 0; barBg.ZIndex = 1; barBg.Parent = bb
        local bgc = Instance.new("UICorner"); bgc.CornerRadius = UDim.new(0,6); bgc.Parent = barBg
        local bgs = Instance.new("UIStroke")
        bgs.Color = Color3.fromRGB(255,255,255); bgs.Thickness = 1; bgs.Transparency = 0.6; bgs.Parent = barBg
        local barFill = Instance.new("Frame")
        barFill.Size = UDim2.new(0,0,1,0); barFill.BackgroundColor3 = Color3.fromRGB(255,60,60)
        barFill.BorderSizePixel = 0; barFill.ZIndex = 2; barFill.Parent = barBg
        local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0,6); fc.Parent = barFill
        local tl = Instance.new("TextLabel")
        tl.Size = UDim2.new(1,0,1,0); tl.BackgroundTransparency = 1; tl.Text = "0%"
        tl.TextColor3 = Color3.new(1,1,1); tl.Font = Enum.Font.GothamBold; tl.TextSize = 11
        tl.TextStrokeTransparency = 0.3; tl.TextStrokeColor3 = Color3.new(0,0,0)
        tl.ZIndex = 5; tl.Parent = barBg
        pcLabels[pc] = {bb=bb, barFill=barFill, textLabel=tl, part=part}
        lastPercent[pc] = 0
        return pcLabels[pc]
    end

    local function queueProgress(pc, value)
        if not pc or not pc.Parent then return end
        local percent = math.clamp(math.floor(value*100+0.5), 0, 100)
        if percent ~= (lastPercent[pc] or -1) then lastPercent[pc] = percent; pendingUpdate[pc] = percent end
    end

    table.insert(pcConnections, task.spawn(function()
        while pcProgressRunning do
            for pc, percent in pairs(pendingUpdate) do
                if pc and pc.Parent then
                    local pack = pcLabels[pc] or createBillboard(pc)
                    if pack then lastPercent[pc] = percent end
                end
                pendingUpdate[pc] = nil
            end
            task.wait(UPDATE_INTERVAL)
        end
    end))

    local function nearestPC(pos, maxDist)
        local best, bd = nil, maxDist or 30
        for pc, data in pairs(pcLabels) do
            if pc and pc.Parent and data.part and data.part.Parent then
                local dist = (data.part.Position - pos).Magnitude
                if dist < bd then best, bd = pc, dist end
            end
        end
        return best
    end

    local function onActionProgress(plrInstance, value)
        if not plrInstance or not plrInstance.Parent then return end
        local tps = plrInstance:FindFirstChild("TempPlayerStatsModule")
        if not tps then return end
        local ca = tps:FindFirstChild("CurrentAnimation")
        if not ca or not ca:IsA("ValueBase") or ca.Value ~= "Typing" then return end
        local char = plrInstance.Character
        if not char or not char.Parent then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local pc = nearestPC(hrp.Position, 35)
        if pc then queueProgress(pc, value) end
    end

    local function hookPlayer(plrInstance)
        if not plrInstance then return end
        local function attach(c)
            if c.Name == "TempPlayerStatsModule" then
                local ap = c:WaitForChild("ActionProgress", 10)
                if ap and ap:IsA("NumberValue") then
                    table.insert(pcConnections, ap:GetPropertyChangedSignal("Value"):Connect(function()
                        onActionProgress(plrInstance, ap.Value)
                    end))
                end
            end
        end
        table.insert(pcConnections, plrInstance.ChildAdded:Connect(attach))
        local tps = plrInstance:FindFirstChild("TempPlayerStatsModule")
        if tps then attach(tps) end
    end

    for _, p in ipairs(Players:GetPlayers()) do hookPlayer(p) end
    table.insert(pcConnections, Players.PlayerAdded:Connect(hookPlayer))

    local function applyScreenState(pc, c)
        if not pc or not pc.Parent then return end
        local pack = pcLabels[pc] or createBillboard(pc)
        if not pack then return end
        if c.G > c.R+0.2 and c.G > c.B+0.2 then pcState[pc] = "DONE"
        elseif c.R > c.G+0.2 and c.R > c.B+0.2 then pcState[pc] = "ERROR"
        else pcState[pc] = nil end
    end

    local function watchPC(pc)
        if not pc or not pc.Parent or hookedPCs[pc] then return end
        hookedPCs[pc] = true
        local scr = pc:FindFirstChild("Screen")
        if scr and scr:IsA("BasePart") then
            applyScreenState(pc, scr.Color)
            table.insert(pcConnections, scr:GetPropertyChangedSignal("Color"):Connect(function()
                if scr and scr.Parent then applyScreenState(pc, scr.Color) end
            end))
        end
    end

    table.insert(pcConnections, task.spawn(function()
        while pcProgressRunning do
            local map = Replicated:FindFirstChild("CurrentMap") and Replicated.CurrentMap.Value
            if map and map.Parent then
                for _, d in ipairs(map:GetDescendants()) do
                    if d.Name == "ComputerTable" then createBillboard(d); watchPC(d) end
                end
            end
            task.wait(1.2)
        end
    end))

    table.insert(pcConnections, RunService.RenderStepped:Connect(function()
        for pc, pack in pairs(pcLabels) do
            if not pc or not pc.Parent then
                if pack.bb then pack.bb:Destroy() end
                pcLabels[pc]=nil; lastPercent[pc]=nil; pcState[pc]=nil; pendingUpdate[pc]=nil
                continue
            end
            local barFill = pack.barFill; local tl = pack.textLabel
            local percent = lastPercent[pc] or 0
            if barFill and barFill.Parent and tl and tl.Parent then
                barFill.Size = pcState[pc]=="DONE" and UDim2.new(1,0,1,0) or UDim2.new(percent/100,0,1,0)
                local r, g, b
                if pcState[pc]=="DONE" then r,g,b = 0,255,100
                elseif percent < 50 then r=255; g=math.floor(60+percent*3.9); b=60
                else r=math.floor(255-(percent-50)*3.9); g=255; b=60 end
                barFill.BackgroundColor3 = Color3.fromRGB(math.clamp(r,60,255), g, b)
                if pcState[pc]=="DONE" then tl.Text="100%"; tl.TextColor3=Color3.fromRGB(0,255,120)
                elseif pcState[pc]=="ERROR" then tl.Text=percent.."%"; tl.TextColor3=Color3.fromRGB(255,60,60)
                else tl.Text=percent.."%"; tl.TextColor3=Color3.new(1,1,1) end
            end
        end
    end))
end

local function getBestPC()
    local bst = getBeast()
    if not bst or not bst.Character then return {} end
    local pcs = {}
    local map = Replicated:FindFirstChild("CurrentMap") and Replicated.CurrentMap.Value
    if map then
        for _, obj in ipairs(map:GetChildren()) do
            if obj.Name == "ComputerTable" then
                local scr = obj:FindFirstChild("Screen")
                if scr and scr.BrickColor ~= BrickColor.new("Dark green") then
                    local hrp = bst.Character:FindFirstChild("HumanoidRootPart")
                    if hrp then table.insert(pcs, {magnitude=(scr.Position-hrp.Position).Magnitude, pc=obj}) end
                end
            end
        end
    end
    table.sort(pcs, function(a,b) return a.magnitude > b.magnitude end)
    return pcs
end

local espToggles = {player=false, pods=false, pc=false, exits=false}

local neverfailEnabled = false
task.spawn(function()
    local re = Replicated:WaitForChild("RemoteEvent", 10)
    if not re then return end
    while true do
        task.wait(0.5)
        if not neverfailEnabled then continue end
        pcall(function() re:FireServer("SetPlayerMinigameResult", true) end)
    end
end)

local ropeEnabled = false

local function isSelfBeast()
    local stats = lp:FindFirstChild("TempPlayerStatsModule")
    if not stats then return false end
    local flag = stats:FindFirstChild("IsBeast")
    return flag and flag.Value == true
end

local function getHammerEvent()
    local char = lp.Character
    local hammer = char and char:FindFirstChild("Hammer")
    return hammer and hammer:FindFirstChild("HammerEvent")
end

local function getNearestRagdoll()
    local char = lp.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local nearest, nearestDist = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp and p.Character then
            local hum = p.Character:FindFirstChild("Humanoid")
            local torso = p.Character:FindFirstChild("UpperTorso") or p.Character:FindFirstChild("Torso")
            if hum and torso and hum.PlatformStand then
                local dist = (root.Position - torso.Position).Magnitude
                if dist < nearestDist then nearest = p; nearestDist = dist end
            end
        end
    end
    return nearest
end

task.spawn(function()
    while true do
        task.wait(0.1)
        if not ropeEnabled or not isSelfBeast() then continue end
        local remote = getHammerEvent()
        if not remote then continue end
        local char = lp.Character
        if not char then continue end
        if char:FindFirstChild("RopeConstraint", true) then continue end
        local target = getNearestRagdoll()
        if not target or not target.Character then continue end
        local torso = target.Character:FindFirstChild("UpperTorso") or target.Character:FindFirstChild("Torso")
        if not torso then continue end
        local timer = 0
        while timer < 2 do
            remote:FireServer("HammerTieUp", torso, torso.Position)
            if lp.Character and lp.Character:FindFirstChild("RopeConstraint", true) then break end
            task.wait(0.15); timer = timer + 0.15
        end
    end
end)

local auraEnabled = false
local hitRadius = 10

local function getValidTargetPart()
    local char = lp.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end

    local bestPart = nil
    local nearestDist = hitRadius

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp and p.Character then
            local hum = p.Character:FindFirstChild("Humanoid")
            local torso = p.Character:FindFirstChild("UpperTorso") or p.Character:FindFirstChild("Torso")
            
            if hum and torso and not hum.PlatformStand and hum.Health > 0 then
                local dist = (root.Position - torso.Position).Magnitude
                if dist <= nearestDist then
                    bestPart = torso
                    nearestDist = dist
                end
            end
        end
    end
    return bestPart
end

task.spawn(function()
    while true do
        task.wait(0.1)
        if not auraEnabled or not isSelfBeast() then continue end
        
        local remote = getHammerEvent()
        if not remote then continue end
        
        local targetPart = getValidTargetPart()
        if targetPart then
            pcall(function()
                remote:FireServer("HammerClick", true)
                remote:FireServer("HammerHit", targetPart)
            end)
        end
    end
end)

local isPlasticOn = false
local cacheMaterials, cacheTextures = {}, {}

local function isProtectedMaterial(mat)
    return mat==Enum.Material.Neon or mat==Enum.Material.Glass or mat==Enum.Material.ForceField
end

local function isCharacter(obj)
    local m = obj:FindFirstAncestorOfClass("Model")
    return m and m:FindFirstChild("Humanoid") ~= nil
end

local function applyToObj(v)
    if isCharacter(v) then return end
    if v:IsA("BasePart") and not isProtectedMaterial(v.Material) then
        if not cacheMaterials[v] then cacheMaterials[v] = v.Material end
        v.Material = Enum.Material.SmoothPlastic
    elseif v:IsA("Texture") then
        if not cacheTextures[v] then cacheTextures[v] = v.Transparency end
        v.Transparency = 1
    end
end

local function scanMap()
    for _, v in pairs(workspace:GetDescendants()) do applyToObj(v) end
end

local function restoreMap()
    for part, mat in pairs(cacheMaterials) do if part and part.Parent then part.Material = mat end end
    for tex, trans in pairs(cacheTextures) do if tex and tex.Parent then tex.Transparency = trans end end
    cacheMaterials = {}; cacheTextures = {}
end

if Replicated:FindFirstChild("CurrentMap") then
    Replicated.CurrentMap.Changed:Connect(function()
        if isPlasticOn then task.spawn(function() task.wait(2); scanMap() end) end
    end)
end

local SAVE_FILE = "dakui_settings.json"
local currentKeybind = Enum.KeyCode.Tab

local function saveSettings()
    pcall(function()
        local data = {
            espPlayer       = espToggles.player,
            espPods         = espToggles.pods,
            espPc           = espToggles.pc,
            espExits        = espToggles.exits,
            neverfail       = neverfailEnabled,
            autoRope        = ropeEnabled,
            hitAura         = auraEnabled,
            pcProgress      = pcProgressRunning,
            beastTracker    = beastTrackerRunning,
            survivorTracker = SurvivorTracker.enabled,
            wallhop         = WallhopView.enabled,
            noTexture       = isPlasticOn,
            flashlight      = Flashlight.enabled,
            selfMuting      = SelfMuting.enabled,
            keybind         = tostring(currentKeybind):gsub("Enum%.KeyCode%.", ""),
        }
        writefile(SAVE_FILE, game:GetService("HttpService"):JSONEncode(data))
    end)
end

local _loadSettingsRef = {}

local function reloadESP()
    task.spawn(function()
        local map = Replicated:FindFirstChild("CurrentMap") and Replicated.CurrentMap.Value
        if map then
            for _, obj in ipairs(map:GetChildren()) do
                if obj.Name == "ComputerTable" then
                    local h = obj:FindFirstChildOfClass("Highlight")
                    if h and not espToggles.pc then h:Destroy()
                    elseif not h and espToggles.pc then
                        local a = Instance.new("Highlight", obj)
                        a.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        a.FillColor = Color3.fromRGB(13,105,172)
                        a.OutlineColor = Color3.fromRGB(20,165,255)
                        task.spawn(function()
                            while a and a.Parent do
                                local scr = obj:FindFirstChild("Screen")
                                if scr then
                                    a.FillColor = scr.Color
                                    a.OutlineColor = Color3.fromRGB(
                                        math.clamp(scr.Color.R*400,0,255),
                                        math.clamp(scr.Color.G*400,0,255),
                                        math.clamp(scr.Color.B*400,0,255))
                                end
                                task.wait(1)
                            end
                        end)
                    end
                end
                if obj.Name == "FreezePod" then
                    local h = obj:FindFirstChildOfClass("Highlight")
                    if h and not espToggles.pods then h:Destroy()
                    elseif not h and espToggles.pods then
                        local a = Instance.new("Highlight", obj)
                        a.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        a.FillColor = Color3.fromRGB(120,200,255)
                        a.OutlineColor = Color3.fromRGB(160,255,255)
                    end
                end
                if obj.Name == "ExitDoor" then
                    local h = obj:FindFirstChildOfClass("Highlight")
                    if h and not espToggles.exits then h:Destroy()
                    elseif not h and espToggles.exits then
                        local a = Instance.new("Highlight", obj)
                        a.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        a.FillColor = Color3.fromRGB(252,255,100)
                        a.OutlineColor = Color3.fromRGB(255,255,160)
                    end
                end
            end
        end
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= lp and p.Character then
                local char = p.Character
                local h = char:FindFirstChildOfClass("Highlight")
                if h and not espToggles.player then h:Destroy()
                elseif not h and espToggles.player then
                    local a = Instance.new("Highlight", char)
                    a.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    a.FillColor = Color3.fromRGB(0,255,0)
                    a.OutlineColor = Color3.fromRGB(127,255,127)
                    task.spawn(function()
                        while a and a.Parent do
                            task.wait(0.1)
                            if getBeast()==p then
                                a.FillColor = Color3.fromRGB(255,0,0)
                                a.OutlineColor = Color3.fromRGB(255,127,127)
                            else
                                a.FillColor = Color3.fromRGB(0,255,0)
                                a.OutlineColor = Color3.fromRGB(127,255,127)
                            end
                        end
                    end)
                end
            end
        end
    end)
end

local function loadSettings()
    pcall(function()
        if not isfile(SAVE_FILE) then return end
        local data = game:GetService("HttpService"):JSONDecode(readfile(SAVE_FILE))
        if data.espPlayer       ~= nil then espToggles.player      = data.espPlayer       end
        if data.espPods         ~= nil then espToggles.pods        = data.espPods         end
        if data.espPc           ~= nil then espToggles.pc          = data.espPc           end
        if data.espExits        ~= nil then espToggles.exits       = data.espExits        end
        if data.neverfail       ~= nil then neverfailEnabled       = data.neverfail       end
        if data.autoRope        ~= nil then ropeEnabled            = data.autoRope        end
        if data.hitAura         ~= nil then auraEnabled            = data.hitAura         end
        if data.pcProgress      ~= nil then pcProgressRunning      = data.pcProgress      end
        if data.beastTracker    ~= nil then beastTrackerRunning    = data.beastTracker    end
        if data.survivorTracker ~= nil then SurvivorTracker.enabled= data.survivorTracker end
        if data.wallhop         ~= nil then WallhopView.enabled    = data.wallhop         end
        if data.noTexture       ~= nil then isPlasticOn            = data.noTexture       end
        if data.flashlight      ~= nil then Flashlight.enabled     = data.flashlight      end
        if data.selfMuting      ~= nil then SelfMuting.enabled     = data.selfMuting      end
        if data.keybind ~= nil then
            local ok, kc = pcall(function() return Enum.KeyCode[data.keybind] end)
            if ok and kc then
                currentKeybind = kc
                if _loadSettingsRef.keyBox then _loadSettingsRef.keyBox.Text = data.keybind end
            end
        end
        reloadESP()
        task.defer(function()
            if syncFns.neverfail       then syncFns.neverfail(neverfailEnabled)            end
            if syncFns.espPlayer       then syncFns.espPlayer(espToggles.player)           end
            if syncFns.espPods         then syncFns.espPods(espToggles.pods)               end
            if syncFns.espPc           then syncFns.espPc(espToggles.pc)                   end
            if syncFns.espExits        then syncFns.espExits(espToggles.exits)             end
            if syncFns.autoRope        then syncFns.autoRope(ropeEnabled)                  end
            if syncFns.hitAura         then syncFns.hitAura(auraEnabled)                   end
            if syncFns.pcProgress      then syncFns.pcProgress(pcProgressRunning)          end
            if syncFns.beastTracker    then syncFns.beastTracker(beastTrackerRunning)      end
            if syncFns.survivorTracker then syncFns.survivorTracker(SurvivorTracker.enabled) end
            if syncFns.wallhop         then syncFns.wallhop(WallhopView.enabled)           end
            if syncFns.noTexture       then syncFns.noTexture(isPlasticOn)                 end
            if syncFns.flashlight      then syncFns.flashlight(Flashlight.enabled)         end
            if syncFns.selfMuting      then syncFns.selfMuting(SelfMuting.enabled)         end
            if pcProgressRunning       then stopPCProgress(); startPCProgress()     end
            if beastTrackerRunning     then stopBeastTracker(); startBeastTracker()   end
            if SurvivorTracker.enabled then SurvivorTracker.stop(); SurvivorTracker.start() end
            if WallhopView.enabled     then WallhopView.stop(); WallhopView.start()   end
            if isPlasticOn             then restoreMap(); scanMap()              end
            if Flashlight.enabled      then Flashlight.stop(); Flashlight.start()    end
            if SelfMuting.enabled      then SelfMuting.stop(); SelfMuting.start()    end
        end)
    end)
end

task.spawn(function()
    Replicated:WaitForChild("CurrentMap").Changed:Connect(function() task.wait(5); reloadESP() end)
end)
task.spawn(function()
    Replicated:WaitForChild("IsGameActive").Changed:Connect(function() reloadESP() end)
end)
task.spawn(function()
    Players.PlayerAdded:Connect(function(p)
        p.CharacterAdded:Connect(function() reloadESP() end)
        p.CharacterRemoving:Connect(function() reloadESP() end)
    end)
end)

local CFG = {
    Title    = "PANEL",
    SubTitle = "v1.0 · ready",
    W = 480, H = 320, SideW = 110,
    Tabs = {
        {name="Info",   icon="≡"},
        {name="Main",   icon="⌂"},
        {name="Auto",   icon="∞"},
        {name="ESP",    icon="◉"},
        {name="Misc",   icon="▣"},
        {name="Config", icon="⊙"},
    },
    Accent    = Color3.fromRGB(185,45,45),
    AccentDim = Color3.fromRGB(120,28,28),
    Bg        = Color3.fromRGB(18,17,17),
    Side      = Color3.fromRGB(14,13,13),
    Card      = Color3.fromRGB(24,23,23),
    CardHov   = Color3.fromRGB(30,28,28),
    Text      = Color3.fromRGB(225,218,218),
    TextMute  = Color3.fromRGB(95,88,88),
    Border    = Color3.fromRGB(255,255,255),
}

local fast = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

pcall(function() if pgui:FindFirstChild("DakUI") then pgui.DakUI:Destroy() end end)

local SG = Instance.new("ScreenGui")
SG.Name="DakUI"; SG.ResetOnSpawn=false; SG.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
SG.IgnoreGuiInset=true; SG.DisplayOrder=999
pcall(function() syn.protect_gui(SG) end)
SG.Parent = pgui

local function animateClose(panel, px, py, onDone)
    local cx, cy = px+CFG.W/2, py+CFG.H/2
    tw(panel, TweenInfo.new(0.1,Enum.EasingStyle.Quad,Enum.EasingDirection.Out), {
        Size=UDim2.new(0,CFG.W*1.07,0,CFG.H*1.07),
        Position=UDim2.new(0,px-CFG.W*0.035,0,py-CFG.H*0.035)
    })
    task.delay(0.11, function()
        tw(panel, TweenInfo.new(0.25,Enum.EasingStyle.Back,Enum.EasingDirection.In), {
            Size=UDim2.new(0,0,0,0), Position=UDim2.new(0,cx,0,cy)
        })
        task.delay(0.27, function()
            panel.Visible=false
            panel.Size=UDim2.new(0,CFG.W,0,CFG.H)
            panel.Position=UDim2.new(0,px,0,py)
            if onDone then onDone() end
        end)
    end)
end

local function animateOpen(panel, px, py)
    local cx, cy = px+CFG.W/2, py+CFG.H/2
    panel.Size=UDim2.new(0,0,0,0); panel.Position=UDim2.new(0,cx,0,cy)
    panel.Rotation=0; panel.Visible=true
    tw(panel, TweenInfo.new(0.25,Enum.EasingStyle.Back,Enum.EasingDirection.Out), {
        Size=UDim2.new(0,CFG.W*1.07,0,CFG.H*1.07),
        Position=UDim2.new(0,px-CFG.W*0.035,0,py-CFG.H*0.035)
    })
    task.delay(0.26, function()
        tw(panel, TweenInfo.new(0.12,Enum.EasingStyle.Quad,Enum.EasingDirection.Out), {
            Size=UDim2.new(0,CFG.W,0,CFG.H), Position=UDim2.new(0,px,0,py)
        })
    end)
end

local TBtn = Instance.new("ImageButton", SG)
TBtn.Size=UDim2.new(0,36,0,36); TBtn.Position=UDim2.new(1,-50,0,14)
TBtn.BackgroundColor3=CFG.Side; TBtn.BorderSizePixel=0; TBtn.ZIndex=30
corner(TBtn,10); stroke(TBtn,CFG.Border,1,0.84)

local function bar(parent, y, w)
    local f = Instance.new("Frame", parent)
    f.BackgroundColor3=Color3.fromRGB(200,185,185); f.BorderSizePixel=0
    f.Size=UDim2.new(0,w or 16,0,2); f.Position=UDim2.new(0.5,-(w or 16)/2,0,y)
    corner(f,2); return f
end
bar(TBtn,11,16); bar(TBtn,17,16)
local b3 = bar(TBtn,23,11)

TBtn.MouseEnter:Connect(function() tw(TBtn,fast,{BackgroundColor3=Color3.fromRGB(30,20,20)}) end)
TBtn.MouseLeave:Connect(function() tw(TBtn,fast,{BackgroundColor3=CFG.Side}) end)

local Panel = Instance.new("Frame", SG)
Panel.Name="Panel"; Panel.Size=UDim2.new(0,CFG.W,0,CFG.H); Panel.Visible=false
Panel.BackgroundColor3=CFG.Bg; Panel.BorderSizePixel=0
Panel.ClipsDescendants=true; Panel.ZIndex=10
corner(Panel,14); stroke(Panel,CFG.Border,1,0.88)

local TopLine = Instance.new("Frame", Panel)
TopLine.Size=UDim2.new(1,0,0,2); TopLine.BackgroundColor3=CFG.Accent
TopLine.BorderSizePixel=0; TopLine.ZIndex=11

local Header = Instance.new("Frame", Panel)
Header.Size=UDim2.new(1,0,0,44); Header.Position=UDim2.new(0,0,0,2)
Header.BackgroundTransparency=1; Header.ZIndex=11

local LogoBox = Instance.new("Frame", Header)
LogoBox.Size=UDim2.new(0,28,0,28); LogoBox.Position=UDim2.new(0,12,0.5,-14)
LogoBox.BackgroundColor3=CFG.Accent; LogoBox.BorderSizePixel=0; LogoBox.ZIndex=12
corner(LogoBox,8)
local LogoLbl = Instance.new("TextLabel", LogoBox)
LogoLbl.Size=UDim2.new(1,0,1,0); LogoLbl.BackgroundTransparency=1
LogoLbl.Text="◆"; LogoLbl.TextSize=13; LogoLbl.Font=Enum.Font.GothamBold; LogoLbl.ZIndex=13

local TitleL = Instance.new("TextLabel", Header)
TitleL.Size=UDim2.new(0,120,0,16); TitleL.Position=UDim2.new(0,48,0.5,-16)
TitleL.BackgroundTransparency=1; TitleL.Text=CFG.Title; TitleL.TextColor3=CFG.Text
TitleL.TextSize=13; TitleL.Font=Enum.Font.GothamBold
TitleL.TextXAlignment=Enum.TextXAlignment.Left; TitleL.ZIndex=12

local SubL = Instance.new("TextLabel", Header)
SubL.Size=UDim2.new(0,120,0,12); SubL.Position=UDim2.new(0,48,0.5,2)
SubL.BackgroundTransparency=1; SubL.Text=CFG.SubTitle; SubL.TextColor3=CFG.TextMute
SubL.TextSize=9; SubL.Font=Enum.Font.Code
SubL.TextXAlignment=Enum.TextXAlignment.Left; SubL.ZIndex=12

local CloseBtn = Instance.new("TextButton", Header)
CloseBtn.Size=UDim2.new(0,22,0,22); CloseBtn.Position=UDim2.new(1,-32,0.5,-11)
CloseBtn.BackgroundColor3=Color3.fromRGB(140,30,30); CloseBtn.BackgroundTransparency=0.5
CloseBtn.Text="X"; CloseBtn.TextColor3=Color3.fromRGB(255,60,60)
CloseBtn.TextSize=13; CloseBtn.Font=Enum.Font.GothamBold
CloseBtn.BorderSizePixel=0; CloseBtn.ZIndex=12; corner(CloseBtn,7)

local MinBtn = Instance.new("TextButton", Header)
MinBtn.Size=UDim2.new(0,22,0,22); MinBtn.Position=UDim2.new(1,-58,0.5,-11)
MinBtn.BackgroundColor3=Color3.fromRGB(60,60,60); MinBtn.BackgroundTransparency=0.5
MinBtn.Text="-"; MinBtn.TextColor3=Color3.fromRGB(255,255,255)
MinBtn.TextSize=18; MinBtn.Font=Enum.Font.GothamBold
MinBtn.BorderSizePixel=0; MinBtn.ZIndex=12; corner(MinBtn,7)

local HDivider = Instance.new("Frame", Panel)
HDivider.Size=UDim2.new(1,-20,0,1); HDivider.Position=UDim2.new(0,10,0,46)
HDivider.BackgroundColor3=CFG.Border; HDivider.BackgroundTransparency=0.9
HDivider.BorderSizePixel=0; HDivider.ZIndex=11

local Body = Instance.new("Frame", Panel)
Body.Size=UDim2.new(1,0,1,-48); Body.Position=UDim2.new(0,0,0,48)
Body.BackgroundTransparency=1; Body.ZIndex=11

local Sidebar = Instance.new("Frame", Body)
Sidebar.Size=UDim2.new(0,CFG.SideW,1,0); Sidebar.BackgroundColor3=CFG.Side
Sidebar.BorderSizePixel=0; Sidebar.ZIndex=12

local VDiv = Instance.new("Frame", Body)
VDiv.Size=UDim2.new(0,1,1,-16); VDiv.Position=UDim2.new(0,CFG.SideW,0,8)
VDiv.BackgroundColor3=CFG.Border; VDiv.BackgroundTransparency=0.9
VDiv.BorderSizePixel=0; VDiv.ZIndex=12

local TabList = Instance.new("Frame", Sidebar)
TabList.Size=UDim2.new(1,0,1,0); TabList.BackgroundTransparency=1; TabList.ZIndex=13
local TLayout = Instance.new("UIListLayout", TabList)
TLayout.SortOrder=Enum.SortOrder.LayoutOrder; TLayout.Padding=UDim.new(0,3)
pad(TabList,10,6,8,8)

local ContentFrame = Instance.new("Frame", Body)
ContentFrame.Size=UDim2.new(1,-CFG.SideW-1,1,0); ContentFrame.Position=UDim2.new(0,CFG.SideW+1,0,0)
ContentFrame.BackgroundTransparency=1; ContentFrame.ZIndex=12; ContentFrame.ClipsDescendants=true

local Panes = {}
for i = 1, #CFG.Tabs do
    local pane
    if i == 1 then
        pane = Instance.new("Frame", ContentFrame)
        pane.Size=UDim2.new(1,0,1,0); pane.BackgroundTransparency=1
        pane.BorderSizePixel=0; pane.Visible=true; pane.ZIndex=13
        local pl = Instance.new("UIListLayout", pane)
        pl.SortOrder=Enum.SortOrder.LayoutOrder; pl.Padding=UDim.new(0,5)
        local pp = Instance.new("UIPadding", pane)
        pp.PaddingTop=UDim.new(0,10); pp.PaddingBottom=UDim.new(0,10)
        pp.PaddingLeft=UDim.new(0,12); pp.PaddingRight=UDim.new(0,12)
    else
        pane = Instance.new("ScrollingFrame", ContentFrame)
        pane.Size=UDim2.new(1,0,1,0); pane.BackgroundTransparency=1
        pane.BorderSizePixel=0; pane.ClipsDescendants=true
        pane.CanvasSize=UDim2.new(0,0,0,0); pane.AutomaticCanvasSize=Enum.AutomaticSize.Y
        pane.ScrollBarThickness=0; pane.ScrollingDirection=Enum.ScrollingDirection.Y
        pane.ElasticBehavior=Enum.ElasticBehavior.Always; pane.Visible=false; pane.ZIndex=13
        local pl = Instance.new("UIListLayout", pane)
        pl.SortOrder=Enum.SortOrder.LayoutOrder; pl.Padding=UDim.new(0,5)
        local pp = Instance.new("UIPadding", pane)
        pp.PaddingTop=UDim.new(0,10); pp.PaddingBottom=UDim.new(0,10)
        pp.PaddingLeft=UDim.new(0,12); pp.PaddingRight=UDim.new(0,12)
    end
    pane.Name="Pane"..i; Panes[i] = pane
end

local function addSection(pane, text, order)
    local f = Instance.new("Frame", pane)
    f.Size=UDim2.new(1,0,0,20); f.BackgroundTransparency=1; f.ZIndex=15; f.LayoutOrder=order or 0
    local l = Instance.new("TextLabel", f)
    l.Size=UDim2.new(1,-2,1,0); l.BackgroundTransparency=1; l.Text=text:upper()
    l.TextColor3=CFG.TextMute; l.TextSize=9; l.Font=Enum.Font.Code
    l.TextXAlignment=Enum.TextXAlignment.Left; l.ZIndex=16
    local dash = Instance.new("Frame", f)
    dash.Size=UDim2.new(0,16,0,1); dash.Position=UDim2.new(0,0,1,-1)
    dash.BackgroundColor3=CFG.AccentDim; dash.BorderSizePixel=0; dash.ZIndex=16; corner(dash,1)
end

local function addToggle(pane, icon, name, desc, defaultOn, order, cb, key)
    local row = Instance.new("Frame", pane)
    row.Size=UDim2.new(1,0,0,42); row.BackgroundColor3=CFG.Card
    row.BorderSizePixel=0; row.ZIndex=15; row.LayoutOrder=order or 1
    corner(row,9); stroke(row,CFG.Border,1,0.91)

    local ib = Instance.new("Frame", row)
    ib.Size=UDim2.new(0,26,0,26); ib.Position=UDim2.new(0,8,0.5,-13)
    ib.BackgroundColor3=Color3.fromRGB(35,20,20); ib.BorderSizePixel=0; ib.ZIndex=16; corner(ib,7)
    local il = Instance.new("TextLabel", ib)
    il.Size=UDim2.new(1,0,1,0); il.BackgroundTransparency=1
    il.Text=icon; il.TextSize=12; il.Font=Enum.Font.GothamBold; il.ZIndex=17; il.TextColor3=CFG.Accent

    local nl = Instance.new("TextLabel", row)
    nl.Size=UDim2.new(0,130,0,15); nl.Position=UDim2.new(0,42,0,8)
    nl.BackgroundTransparency=1; nl.Text=name; nl.TextColor3=CFG.Text
    nl.TextSize=11; nl.Font=Enum.Font.GothamBold
    nl.TextXAlignment=Enum.TextXAlignment.Left; nl.ZIndex=16

    local dl = Instance.new("TextLabel", row)
    dl.Size=UDim2.new(0,130,0,12); dl.Position=UDim2.new(0,42,0,22)
    dl.BackgroundTransparency=1; dl.Text=desc; dl.TextColor3=CFG.TextMute
    dl.TextSize=9; dl.Font=Enum.Font.Code
    dl.TextXAlignment=Enum.TextXAlignment.Left; dl.ZIndex=16

    local pill = Instance.new("Frame", row)
    pill.Size=UDim2.new(0,32,0,18); pill.Position=UDim2.new(1,-40,0.5,-9)
    pill.BackgroundColor3=defaultOn and CFG.Accent or Color3.fromRGB(42,36,36)
    pill.BorderSizePixel=0; pill.ZIndex=16; corner(pill,9)

    local knob = Instance.new("Frame", pill)
    knob.Size=UDim2.new(0,12,0,12)
    knob.Position=defaultOn and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6)
    knob.BackgroundColor3=Color3.fromRGB(255,255,255); knob.BorderSizePixel=0; knob.ZIndex=17; corner(knob,6)

    local isOn = defaultOn or false
    local btn = Instance.new("TextButton", row)
    btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1; btn.Text=""; btn.ZIndex=18

    btn.MouseButton1Click:Connect(function()
        isOn = not isOn
        tw(pill,fast,{BackgroundColor3=isOn and CFG.Accent or Color3.fromRGB(42,36,36)})
        tw(knob,fast,{Position=isOn and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6)})
        tw(row, fast,{BackgroundColor3=isOn and Color3.fromRGB(28,20,20) or CFG.Card})
        if cb then cb(isOn) end
    end)
    btn.MouseEnter:Connect(function() tw(row,fast,{BackgroundColor3=CFG.CardHov}) end)
    btn.MouseLeave:Connect(function() tw(row,fast,{BackgroundColor3=isOn and Color3.fromRGB(28,20,20) or CFG.Card}) end)

    if key then
        syncFns[key] = function(val)
            isOn = val
            pill.BackgroundColor3 = val and CFG.Accent or Color3.fromRGB(42,36,36)
            knob.Position = val and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6)
            row.BackgroundColor3 = val and Color3.fromRGB(28,20,20) or CFG.Card
        end
    end
    return row
end

local function addButton(pane, icon, name, desc, order, cb)
    local row = Instance.new("Frame", pane)
    row.Size=UDim2.new(1,0,0,42); row.BackgroundColor3=CFG.Card
    row.BorderSizePixel=0; row.ZIndex=15; row.LayoutOrder=order or 1
    corner(row,9); stroke(row,CFG.Border,1,0.91)

    local ib = Instance.new("Frame", row)
    ib.Size=UDim2.new(0,26,0,26); ib.Position=UDim2.new(0,8,0.5,-13)
    ib.BackgroundColor3=Color3.fromRGB(35,20,20); ib.BorderSizePixel=0; ib.ZIndex=16; corner(ib,7)
    local il = Instance.new("TextLabel", ib)
    il.Size=UDim2.new(1,0,1,0); il.BackgroundTransparency=1
    il.Text=icon; il.TextSize=12; il.Font=Enum.Font.GothamBold; il.ZIndex=17; il.TextColor3=CFG.Accent

    local nl = Instance.new("TextLabel", row)
    nl.Size=UDim2.new(0,145,0,15); nl.Position=UDim2.new(0,42,0,8)
    nl.BackgroundTransparency=1; nl.Text=name; nl.TextColor3=CFG.Text
    nl.TextSize=11; nl.Font=Enum.Font.GothamBold
    nl.TextXAlignment=Enum.TextXAlignment.Left; nl.ZIndex=16

    local dl = Instance.new("TextLabel", row)
    dl.Size=UDim2.new(0,145,0,12); dl.Position=UDim2.new(0,42,0,22)
    dl.BackgroundTransparency=1; dl.Text=desc; dl.TextColor3=CFG.TextMute
    dl.TextSize=9; dl.Font=Enum.Font.Code
    dl.TextXAlignment=Enum.TextXAlignment.Left; dl.ZIndex=16

    local arr = Instance.new("TextLabel", row)
    arr.Size=UDim2.new(0,20,0,20); arr.Position=UDim2.new(1,-28,0.5,-10)
    arr.BackgroundTransparency=1; arr.Text=">"; arr.TextColor3=CFG.TextMute
    arr.TextSize=10; arr.Font=Enum.Font.GothamBold; arr.ZIndex=16

    local btn = Instance.new("TextButton", row)
    btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1; btn.Text=""; btn.ZIndex=18

    btn.MouseButton1Click:Connect(function()
        tw(row,fast,{BackgroundColor3=Color3.fromRGB(40,18,18)})
        tw(arr,fast,{TextColor3=CFG.Accent})
        task.delay(0.18, function()
            tw(row,fast,{BackgroundColor3=CFG.Card})
            tw(arr,fast,{TextColor3=CFG.TextMute})
        end)
        if cb then cb() end
    end)
    btn.MouseEnter:Connect(function() tw(row,fast,{BackgroundColor3=CFG.CardHov}) end)
    btn.MouseLeave:Connect(function() tw(row,fast,{BackgroundColor3=CFG.Card}) end)
    return row
end

local TabBtns = {}
local curTab = 1

local function switchTab(idx)
    for i, pane in ipairs(Panes) do
        pane.Visible = (i==idx)
        if pane:IsA("ScrollingFrame") then pane.CanvasPosition = Vector2.new(0,0) end
    end
    for i, tb in ipairs(TabBtns) do
        local act = (i==idx)
        tw(tb.bg,  fast, {BackgroundColor3=act and Color3.fromRGB(30,18,18) or CFG.Side, BackgroundTransparency=act and 0 or 1})
        tw(tb.lbl, fast, {TextColor3=act and CFG.Text or CFG.TextMute})
        tw(tb.bar, fast, {BackgroundTransparency=act and 0 or 1})
    end
    curTab = idx
end

for i, tab in ipairs(CFG.Tabs) do
    local bg = Instance.new("TextButton", TabList)
    bg.Size=UDim2.new(1,0,0,36)
    bg.BackgroundColor3=i==1 and Color3.fromRGB(30,18,18) or CFG.Side
    bg.BackgroundTransparency=i==1 and 0 or 1
    bg.BorderSizePixel=0; bg.Text=""; bg.ZIndex=14; bg.LayoutOrder=i; corner(bg,8)

    local lbar = Instance.new("Frame", bg)
    lbar.Size=UDim2.new(0,2,0.6,0); lbar.Position=UDim2.new(0,0,0.2,0)
    lbar.BackgroundColor3=CFG.Accent; lbar.BackgroundTransparency=i==1 and 0 or 1
    lbar.BorderSizePixel=0; lbar.ZIndex=15; corner(lbar,2)

    local ico = Instance.new("TextLabel", bg)
    ico.Size=UDim2.new(0,18,1,0); ico.Position=UDim2.new(0,10,0,0)
    ico.BackgroundTransparency=1; ico.Text=tab.icon; ico.TextSize=13
    ico.Font=Enum.Font.GothamBold; ico.ZIndex=15; ico.TextColor3=CFG.Accent

    local lbl = Instance.new("TextLabel", bg)
    lbl.Size=UDim2.new(1,-30,1,0); lbl.Position=UDim2.new(0,30,0,0)
    lbl.BackgroundTransparency=1; lbl.Text=tab.name
    lbl.TextColor3=i==1 and CFG.Text or CFG.TextMute
    lbl.TextSize=11; lbl.Font=Enum.Font.GothamBold
    lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.ZIndex=15

    bg.MouseButton1Click:Connect(function() switchTab(i) end)
    bg.MouseEnter:Connect(function()
        if curTab ~= i then tw(bg,fast,{BackgroundTransparency=0, BackgroundColor3=Color3.fromRGB(24,16,16)}) end
    end)
    bg.MouseLeave:Connect(function()
        if curTab ~= i then tw(bg,fast,{BackgroundTransparency=1}) end
    end)
    TabBtns[i] = {bg=bg, lbl=lbl, bar=lbar}
end

addSection(Panes[1], "Info", 0)
local InfoCard = Instance.new("Frame", Panes[1])
InfoCard.Size=UDim2.new(1,0,0,60); InfoCard.BackgroundColor3=CFG.Card
InfoCard.BorderSizePixel=0; InfoCard.ZIndex=15; InfoCard.LayoutOrder=1
corner(InfoCard,9); stroke(InfoCard,CFG.Border,1,0.91)

local success, errorMessage = pcall(function()
    -- [1] KIỂM TRA CÁC BIẾN VÀ HÀM TOÀN CỤC TRƯỚC KHI CHẠY
    local requiredGlobals = {
        {name = "CFG", value = CFG},
        {name = "lp", value = lp},
        {name = "corner", value = corner},
        {name = "stroke", value = stroke},
        {name = "addSection", value = addSection},
        {name = "Panes", value = Panes},
        {name = "InfoCard", value = InfoCard},
        {name = "TypeGlitch", value = TypeGlitch},
        {name = "DISCORD_LINK", value = DISCORD_LINK},
        {name = "CopyText", value = CopyText},
        {name = "TextService", value = game:GetService("TextService")}
    }

    for _, item in ipairs(requiredGlobals) do
        if item.value == nil then
            warn("⚠️ [Kiểm tra] Biến hoặc Hàm bị NIL: " .. item.name)
        end
    end

    -- [2] BẮT ĐẦU ĐOẠN CODE CHÍNH
    local TEXT_SPEED = 0.015
    local lineH = 11 * 1.18

    local Af = Instance.new("Frame", InfoCard)
    Af.Size=UDim2.new(0,74,0,74); Af.Position=UDim2.new(0,12,0,12)
    Af.BackgroundColor3=CFG.Accent; corner(Af,50)
    local Av = Instance.new("ImageLabel", Af)
    Av.Size=UDim2.new(1,-4,1,-4); Av.Position=UDim2.new(0,2,0,2)
    Av.BackgroundColor3=CFG.Card
    Av.Image = "rbxthumb://type=AvatarHeadShot&id="..lp.UserId.."&w=150&h=150"
    corner(Av,50)

    local function mk(y)
        local x = Instance.new("TextLabel", InfoCard)
        x.Size=UDim2.new(1,-110,0,16); x.Position=UDim2.new(0,105,0,y)
        x.BackgroundTransparency=1; x.TextColor3=CFG.Text
        x.TextSize=11; x.Font=Enum.Font.GothamBold; x.TextXAlignment="Left"
        return x
    end
    local Nm = mk(10)
    local Mn = mk(28)
    local Lv = mk(46)
    local Ty = mk(64)
    local Ex = mk(82)

    local Pb = Instance.new("Frame", InfoCard)
    Pb.Size=UDim2.new(0,80,0,14); Pb.BackgroundColor3=Color3.fromRGB(45,20,20)
    corner(Pb,4); stroke(Pb,CFG.Accent,1,.6)
    local Pt = Instance.new("TextLabel", Pb)
    Pt.Size=UDim2.new(1,0,1,0); Pt.BackgroundTransparency=1
    Pt.Text="PREMIUM USER"; Pt.TextColor3=CFG.Accent; Pt.TextSize=8; Pt.Font=Enum.Font.GothamBold
    Pb.Visible = false

    addSection(Panes[1], "Welcome", 2)
    local Wp = Instance.new("Frame", Panes[1])
    Wp.Size=UDim2.new(1,0,0,175); Wp.BackgroundColor3=CFG.Card
    Wp.BorderSizePixel=0; Wp.ZIndex=15; Wp.LayoutOrder=3
    corner(Wp,10); stroke(Wp,CFG.Border,1,.94)

    local Wt = Instance.new("TextLabel", Wp)
    Wt.Size=UDim2.new(1,-24,0,85); Wt.Position=UDim2.new(0,12,0,8)
    Wt.BackgroundTransparency=1; Wt.TextColor3=CFG.TextMute
    Wt.TextSize=11; Wt.Font=Enum.Font.Code; Wt.TextXAlignment="Left"; Wt.TextYAlignment="Top"
    Wt.TextWrapped=false; Wt.LineHeight=1.18

    local HereBtn = Instance.new("TextButton", Wp)
    HereBtn.Size = UDim2.new(0,40,0,lineH)
    HereBtn.BackgroundTransparency=1; HereBtn.TextColor3=CFG.Accent
    HereBtn.TextSize=11; HereBtn.Font=Enum.Font.Code; HereBtn.AutoButtonColor=false
    HereBtn.ZIndex=20; HereBtn.Visible=false

    local CL = Instance.new("TextLabel", Wp)
    CL.Size=UDim2.new(1,-24,0,14); CL.Position=UDim2.new(0,12,0,0)
    CL.BackgroundTransparency=1; CL.TextColor3=Color3.fromRGB(165,155,155)
    CL.TextSize=11; CL.Font=Enum.Font.GothamBold; CL.TextXAlignment="Left"

    local KB = Instance.new("TextLabel", Wp)
    KB.Size=UDim2.new(1,-24,0,14); KB.Position=UDim2.new(0,12,0,0)
    KB.BackgroundTransparency=1; KB.TextColor3=CFG.TextMute
    KB.TextSize=11; KB.Font=Enum.Font.Code; KB.TextXAlignment="Left"

    HereBtn.MouseButton1Click:Connect(function()
        local bSuccess, bError = pcall(function()
            CopyText(DISCORD_LINK)
            local old = HereBtn.TextColor3
            HereBtn.Text = "copied!"
            HereBtn.TextColor3 = Color3.fromRGB(60,220,90)
            task.delay(1.5, function() HereBtn.Text="here"; HereBtn.TextColor3=old end)
        end)
        if not bSuccess then warn("❌ Lỗi khi nhấn nút Sao chép:", bError) end
    end)

    -- [3] BỌC PCALL ĐÃ ĐƯỢC FIX LỖI CÚ PHÁP
    task.spawn(function()
        local s, e = pcall(function()
            local money, level = "0", "0" -- ĐÃ FIX: Chuyển dấu phẩy thành dạng gán đa biến chuẩn
            local m = lp:WaitForChild("SavedPlayerStatsModule",3)
            if m then
                local cr=m:FindFirstChild("Credits"); local lv=m:FindFirstChild("Level")
                if cr then money=tostring(cr.Value) end
                if lv then level=tostring(lv.Value) end
            end
            TypeGlitch(Nm, "---- Name: "..lp.Name, TEXT_SPEED)
            TypeGlitch(Mn, "---- Money: "..money, TEXT_SPEED)
            TypeGlitch(Lv, "---- Level: "..level, TEXT_SPEED)
            local tStr = "---- Type: "
            TypeGlitch(Ty, tStr, TEXT_SPEED)
            
            local TextService = game:GetService("TextService")
            local w = TextService:GetTextSize(tStr,11,Enum.Font.GothamBold,Vector2.new(999,16)).X
            Pb.Position=UDim2.new(0,105+w+4,0,74); Pb.Visible=true
            TypeGlitch(Ex, "---- Expires: ∞", TEXT_SPEED)

            task.wait(.01)
            local first="Welcome to ExFTF!"
            local rest="Thank you very much for trusting and using our script. We commit to being one of the best FTF scripts out there. If you find any bugs or issues, report to us on our Discord "
            local maxW=315; local lines={first}; local cur=""
            for wd in rest:gmatch("%S+") do
                local tst=cur=="" and wd or cur.." "..wd
                if TextService:GetTextSize(tst,11,Enum.Font.Code,Vector2.new(9999,16)).X<=maxW then cur=tst
                else table.insert(lines,cur); cur=wd end
            end
            if cur~="" then table.insert(lines,cur) end
            local FULL=table.concat(lines,"\n"); local nL=#lines
            TypeGlitch(Wt,FULL,TEXT_SPEED)
            local llw=TextService:GetTextSize(lines[nL].." ",11,Enum.Font.Code,Vector2.new(9999,16)).X
            HereBtn.Position=UDim2.new(0,12+llw,0,8+lineH*(nL-1)-1)
            HereBtn.Visible=true
            TypeGlitch(HereBtn,"here",TEXT_SPEED)
            local dy=8+(lineH*nL)+12
            CL.Position=UDim2.new(0,12,0,dy); KB.Position=UDim2.new(0,12,0,dy+16)
            TypeGlitch(CL,"- Change Logs -",TEXT_SPEED)
            TypeGlitch(KB,"+ kilo beo",TEXT_SPEED)
            Wp.Size=UDim2.new(1,0,0,dy+42)
        end)
        if not s then warn("❌ Lỗi trong luồng task.spawn (Hiển thị chữ/Glitch):", e) end
    end)

    task.spawn(function()
        local s, e = pcall(function()
            local m=lp:WaitForChild("SavedPlayerStatsModule",5) if not m then return end
            local cr=m:FindFirstChild("Credits"); local lv=m:FindFirstChild("Level")
            if cr then cr.Changed:Connect(function(v) Mn.Text="---- Money: "..v end) end
            if lv then lv.Changed:Connect(function(v) Lv.Text="---- Level: "..v end) end
        end)
        if not s then warn("❌ Lỗi trong luồng task.spawn (Cập nhật Stats):", e) end
    end)

end)

if not success then
    warn("🔴 CRASH LOG - Phát hiện lỗi nghiêm trọng trong script:")
    print(errorMessage)
end

addSection(Panes[2], "Main Features", 0)
addToggle(Panes[2], "⊙", "Beast tracker",    "Tracks beast selections and skill triggers", false, 2, function(s)
    if s then startBeastTracker() else stopBeastTracker() end; saveSettings()
end, "beastTracker")
addToggle(Panes[2], "∞", "Survivor tracker", "Renders overhead timer templates",           false, 3, function(s)
    if s then SurvivorTracker.start() else SurvivorTracker.stop() end; saveSettings()
end, "survivorTracker")
addToggle(Panes[2], "⊘", "Never Fail",       "Auto pass minigame result to server",        false, 5, function(s)
    neverfailEnabled = s; saveSettings()
end, "neverfail")

addSection(Panes[3], "Auto", 0)
addToggle(Panes[3], "⊕", "Auto Rope", "Beast: auto rope ragdoll survivors", false, 1, function(s)
    ropeEnabled = s; saveSettings()
end, "autoRope")
addToggle(Panes[3], "⊙", "Hit Aura", "Beast: Auto hit survivors trong 10 studs", false, 2, function(s)
    auraEnabled = s; saveSettings()
end, "hitAura")

addSection(Panes[4], "Visuals", 0)
do
    local ESP_OPTIONS = {
        {key="player", label="Player ESP", icon="◉", desc="survivors green / beast red", order=2},
        {key="pods",   label="Pods ESP",   icon="⊙", desc="highlight freeze pods",       order=3},
        {key="pc",     label="PC ESP",     icon="▣", desc="highlight computers",          order=4},
        {key="exits",  label="Exits ESP",  icon="⊘", desc="highlight exit doors",         order=5},
    }
    local groupOpen = false
    local headerRow = Instance.new("Frame", Panes[4])
    headerRow.Size=UDim2.new(1,0,0,42); headerRow.BackgroundColor3=CFG.Card
    headerRow.BorderSizePixel=0; headerRow.ZIndex=15; headerRow.LayoutOrder=1
    corner(headerRow,9); stroke(headerRow,CFG.Border,1,0.91)

    local hib = Instance.new("Frame", headerRow)
    hib.Size=UDim2.new(0,26,0,26); hib.Position=UDim2.new(0,8,0.5,-13)
    hib.BackgroundColor3=Color3.fromRGB(35,20,20); hib.BorderSizePixel=0; hib.ZIndex=16; corner(hib,7)
    local hil = Instance.new("TextLabel", hib)
    hil.Size=UDim2.new(1,0,1,0); hil.BackgroundTransparency=1
    hil.Text="◉"; hil.TextSize=12; hil.Font=Enum.Font.GothamBold; hil.ZIndex=17; hil.TextColor3=CFG.Accent

    local hnl = Instance.new("TextLabel", headerRow)
    hnl.Size=UDim2.new(0,130,0,15); hnl.Position=UDim2.new(0,42,0,8)
    hnl.BackgroundTransparency=1; hnl.Text="Normal ESP"; hnl.TextColor3=CFG.Text
    hnl.TextSize=11; hnl.Font=Enum.Font.GothamBold
    hnl.TextXAlignment=Enum.TextXAlignment.Left; hnl.ZIndex=16

    local hdl = Instance.new("TextLabel", headerRow)
    hdl.Size=UDim2.new(0,130,0,12); hdl.Position=UDim2.new(0,42,0,22)
    hdl.BackgroundTransparency=1; hdl.Text="4 esp options"; hdl.TextColor3=CFG.TextMute
    hdl.TextSize=9; hdl.Font=Enum.Font.Code
    hdl.TextXAlignment=Enum.TextXAlignment.Left; hdl.ZIndex=16

    local arrowLbl = Instance.new("TextLabel", headerRow)
    arrowLbl.Size=UDim2.new(0,20,0,20); arrowLbl.Position=UDim2.new(1,-28,0.5,-10)
    arrowLbl.BackgroundTransparency=1; arrowLbl.Text="↓"; arrowLbl.TextColor3=CFG.TextMute
    arrowLbl.TextSize=13; arrowLbl.Font=Enum.Font.GothamBold; arrowLbl.ZIndex=16

    local groupContent = Instance.new("Frame", Panes[4])
    groupContent.Size=UDim2.new(1,0,0,0); groupContent.BackgroundTransparency=1
    groupContent.BorderSizePixel=0; groupContent.ClipsDescendants=true
    groupContent.ZIndex=15; groupContent.LayoutOrder=2
    local gcl = Instance.new("UIListLayout", groupContent)
    gcl.SortOrder=Enum.SortOrder.LayoutOrder; gcl.Padding=UDim.new(0,5)
    local gcp = Instance.new("UIPadding", groupContent); gcp.PaddingTop=UDim.new(0,5)

    local ITEM_H, GAP = 42, 5
    local fullH = #ESP_OPTIONS*ITEM_H + (#ESP_OPTIONS-1)*GAP + 5
    local espCheckStates = {}

    for i, opt in ipairs(ESP_OPTIONS) do
        espCheckStates[opt.key] = false
        local row = Instance.new("Frame", groupContent)
        row.Size=UDim2.new(1,0,0,ITEM_H); row.BackgroundColor3=CFG.Card
        row.BorderSizePixel=0; row.ZIndex=15; row.LayoutOrder=i
        corner(row,9); stroke(row,CFG.Border,1,0.91)

        local ib = Instance.new("Frame", row)
        ib.Size=UDim2.new(0,26,0,26); ib.Position=UDim2.new(0,8,0.5,-13)
        ib.BackgroundColor3=Color3.fromRGB(35,20,20); ib.BorderSizePixel=0; ib.ZIndex=16; corner(ib,7)
        local il = Instance.new("TextLabel", ib)
        il.Size=UDim2.new(1,0,1,0); il.BackgroundTransparency=1
        il.Text=opt.icon; il.TextSize=12; il.Font=Enum.Font.GothamBold; il.ZIndex=17; il.TextColor3=CFG.Accent

        local nl = Instance.new("TextLabel", row)
        nl.Size=UDim2.new(0,130,0,15); nl.Position=UDim2.new(0,42,0,8)
        nl.BackgroundTransparency=1; nl.Text=opt.label; nl.TextColor3=CFG.Text
        nl.TextSize=11; nl.Font=Enum.Font.GothamBold
        nl.TextXAlignment=Enum.TextXAlignment.Left; nl.ZIndex=16

        local dl = Instance.new("TextLabel", row)
        dl.Size=UDim2.new(0,130,0,12); dl.Position=UDim2.new(0,42,0,22)
        dl.BackgroundTransparency=1; dl.Text=opt.desc; dl.TextColor3=CFG.TextMute
        dl.TextSize=9; dl.Font=Enum.Font.Code
        dl.TextXAlignment=Enum.TextXAlignment.Left; dl.ZIndex=16

        local pill = Instance.new("Frame", row)
        pill.Size=UDim2.new(0,32,0,18); pill.Position=UDim2.new(1,-40,0.5,-9)
        pill.BackgroundColor3=Color3.fromRGB(42,36,36); pill.BorderSizePixel=0; pill.ZIndex=16; corner(pill,9)
        local knob = Instance.new("Frame", pill)
        knob.Size=UDim2.new(0,12,0,12); knob.Position=UDim2.new(0,3,0.5,-6)
        knob.BackgroundColor3=Color3.fromRGB(255,255,255); knob.BorderSizePixel=0; knob.ZIndex=17; corner(knob,6)

        local btn = Instance.new("TextButton", row)
        btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1; btn.Text=""; btn.ZIndex=18

        local optKey = opt.key
        btn.MouseButton1Click:Connect(function()
            espCheckStates[optKey] = not espCheckStates[optKey]
            local on = espCheckStates[optKey]
            tw(pill,fast,{BackgroundColor3=on and CFG.Accent or Color3.fromRGB(42,36,36)})
            tw(knob,fast,{Position=on and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6)})
            tw(row, fast,{BackgroundColor3=on and Color3.fromRGB(28,20,20) or CFG.Card})
            espToggles[optKey] = on; reloadESP(); saveSettings()
        end)
        btn.MouseEnter:Connect(function() tw(row,fast,{BackgroundColor3=CFG.CardHov}) end)
        btn.MouseLeave:Connect(function()
            tw(row,fast,{BackgroundColor3=espCheckStates[optKey] and Color3.fromRGB(28,20,20) or CFG.Card})
        end)

        syncFns["esp"..optKey:sub(1,1):upper()..optKey:sub(2)] = function(val)
            espCheckStates[optKey] = val
            pill.BackgroundColor3 = val and CFG.Accent or Color3.fromRGB(42,36,36)
            knob.Position = val and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6)
            row.BackgroundColor3 = val and Color3.fromRGB(28,20,20) or CFG.Card
        end
    end

    local hBtn = Instance.new("TextButton", headerRow)
    hBtn.Size=UDim2.new(1,0,1,0); hBtn.BackgroundTransparency=1; hBtn.Text=""; hBtn.ZIndex=18
    hBtn.MouseButton1Click:Connect(function()
        groupOpen = not groupOpen
        tw(arrowLbl,fast,{TextColor3=groupOpen and CFG.Accent or CFG.TextMute})
        arrowLbl.Text = groupOpen and "↑" or "↓"
        tw(groupContent, TweenInfo.new(0.25,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
            {Size=UDim2.new(1,0,0,groupOpen and fullH or 0)})
    end)
    hBtn.MouseEnter:Connect(function() tw(headerRow,fast,{BackgroundColor3=CFG.CardHov}) end)
    hBtn.MouseLeave:Connect(function() tw(headerRow,fast,{BackgroundColor3=CFG.Card}) end)
end

addToggle(Panes[4], "∞", "PC Progress", "shows hacking progress bars above PCs", false, 6, function(s)
    if s then startPCProgress() else stopPCProgress() end; saveSettings()
end, "pcProgress")

addSection(Panes[5], "Misc Features", 0)
addToggle(Panes[5], "▣", "No Texture",  "Replaces world assets with solid plastic layers",  false, 1, function(s)
    isPlasticOn = s; if isPlasticOn then scanMap() else restoreMap() end; saveSettings()
end, "noTexture")
addToggle(Panes[5], "☼", "Flashlight",  "Forces light shifts into bright ambient modes",     false, 2, function(s)
    if s then Flashlight.start() else Flashlight.stop() end; saveSettings()
end, "flashlight")
addToggle(Panes[5], "⊗", "Self muting", "Silences local player character audio triggers",    false, 3, function(s)
    if s then SelfMuting.start() else SelfMuting.stop() end; saveSettings()
end, "selfMuting")
addToggle(Panes[5], "◆", "Wallhop view","Highlights walls around player",                    false, 4, function(s)
    if s then WallhopView.start() else WallhopView.stop() end; saveSettings()
end, "wallhop")

addButton(Panes[5], "⊕", "Join Server Pro", "Auto Join or Leave Pro Server", 5, function()
    local a = Players.LocalPlayer
    local b = a.Character or a.CharacterAdded:Wait()
    local c = b:WaitForChild("HumanoidRootPart")
    local d = workspace:FindFirstChild("FTFLobbySpring")
    local e = a:WaitForChild("PlayerGui"):WaitForChild("MenusScreenGui")
    local function cQJ()
        for _ = 1, 20 do
            for _, w in pairs(e:GetChildren()) do
                if w:IsA("Frame") and w.Visible then
                    local qj = w:FindFirstChild("QuickJoinButton", true)
                    if qj and qj:IsA("TextButton") then firesignal(qj.MouseButton1Click); return true end
                end
            end
            task.wait(0.3)
        end
        return false
    end
    local sg = d and d:FindFirstChild("Signs")
    if sg then
        local ts = sg:FindFirstChild("ProServerSign") or sg:FindFirstChild("LeaveProServerSign")
        if ts then
            local pr = ts:FindFirstChildWhichIsA("ProximityPrompt", true)
            local bd = ts:FindFirstChild("Board")
            if pr and bd then
                c.CFrame = bd.CFrame * CFrame.new(0,1,3); task.wait(0.5)
                if fireproximityprompt then fireproximityprompt(pr)
                else pr:InputHoldBegin(); task.wait(pr.HoldDuration); pr:InputHoldEnd() end
                cQJ()
            end
        end
    end
end)

addSection(Panes[6], "Keybind", 0)
local keybindRow = Instance.new("Frame", Panes[6])
keybindRow.Size=UDim2.new(1,0,0,42); keybindRow.BackgroundColor3=CFG.Card
keybindRow.BorderSizePixel=0; keybindRow.ZIndex=15; keybindRow.LayoutOrder=1
corner(keybindRow,9); stroke(keybindRow,CFG.Border,1,0.91)

local kib = Instance.new("Frame", keybindRow)
kib.Size=UDim2.new(0,26,0,26); kib.Position=UDim2.new(0,8,0.5,-13)
kib.BackgroundColor3=Color3.fromRGB(35,20,20); kib.BorderSizePixel=0; kib.ZIndex=16; corner(kib,7)
local kil = Instance.new("TextLabel", kib)
kil.Size=UDim2.new(1,0,1,0); kil.BackgroundTransparency=1
kil.Text="⌨"; kil.TextSize=12; kil.Font=Enum.Font.GothamBold; kil.ZIndex=17; kil.TextColor3=CFG.Accent

local knl = Instance.new("TextLabel", keybindRow)
knl.Size=UDim2.new(0,110,0,15); knl.Position=UDim2.new(0,42,0,8)
knl.BackgroundTransparency=1; knl.Text="Toggle UI Key"; knl.TextColor3=CFG.Text
knl.TextSize=11; knl.Font=Enum.Font.GothamBold
knl.TextXAlignment=Enum.TextXAlignment.Left; knl.ZIndex=16

local kdl = Instance.new("TextLabel", keybindRow)
kdl.Size=UDim2.new(0,110,0,12); kdl.Position=UDim2.new(0,42,0,22)
kdl.BackgroundTransparency=1; kdl.Text="type key then enter"; kdl.TextColor3=CFG.TextMute
kdl.TextSize=9; kdl.Font=Enum.Font.Code
kdl.TextXAlignment=Enum.TextXAlignment.Left; kdl.ZIndex=16

local keyBox = Instance.new("TextBox", keybindRow)
_loadSettingsRef.keyBox = keyBox
keyBox.Size=UDim2.new(0,36,0,24); keyBox.Position=UDim2.new(1,-44,0.5,-12)
keyBox.BackgroundColor3=Color3.fromRGB(30,18,18); keyBox.BorderSizePixel=0
keyBox.Text="Tab"; keyBox.PlaceholderText="key"
keyBox.TextColor3=CFG.Text; keyBox.PlaceholderColor3=CFG.TextMute
keyBox.TextSize=11; keyBox.Font=Enum.Font.GothamBold
keyBox.TextXAlignment=Enum.TextXAlignment.Center
keyBox.ClearTextOnFocus=true; keyBox.ZIndex=18
corner(keyBox,6); stroke(keyBox,CFG.Accent,1,0.6)

keyBox.FocusLost:Connect(function(enterPressed)
    if not enterPressed then
        keyBox.Text = tostring(currentKeybind):gsub("Enum.KeyCode.", ""); return
    end
    local raw = keyBox.Text:gsub("%s+","")
    if #raw == 0 then keyBox.Text = tostring(currentKeybind):gsub("Enum.KeyCode.",""); return end
    local ok, kc = pcall(function()
        return Enum.KeyCode[raw] or Enum.KeyCode[raw:sub(1,1):upper()..raw:sub(2):lower()]
    end)
    if ok and kc then
        currentKeybind = kc
        keyBox.Text = raw:sub(1,1):upper()..raw:sub(2):lower()
        saveSettings()
        tw(keyBox,fast,{BackgroundColor3=Color3.fromRGB(20,50,20)})
        task.delay(0.4, function() tw(keyBox,fast,{BackgroundColor3=Color3.fromRGB(30,18,18)}) end)
    else
        tw(keyBox,fast,{BackgroundColor3=Color3.fromRGB(60,20,20)})
        task.delay(0.4, function() tw(keyBox,fast,{BackgroundColor3=Color3.fromRGB(30,18,18)}) end)
        keyBox.Text = tostring(currentKeybind):gsub("Enum.KeyCode.","")
    end
end)

local savedPX = -CFG.W/2
local savedPY = -CFG.H/2
local isOpen  = true
local isBusy  = false

local ConfirmBg = Instance.new("Frame", SG)
ConfirmBg.Size=UDim2.new(1,0,1,0); ConfirmBg.BackgroundColor3=Color3.fromRGB(0,0,0)
ConfirmBg.BackgroundTransparency=0.5; ConfirmBg.ZIndex=200; ConfirmBg.Visible=false

local ConfirmBox = Instance.new("Frame", ConfirmBg)
ConfirmBox.Size=UDim2.new(0,260,0,110); ConfirmBox.Position=UDim2.new(0.5,-130,0.5,-55)
ConfirmBox.BackgroundColor3=CFG.Bg; ConfirmBox.BorderSizePixel=0; ConfirmBox.ZIndex=201
corner(ConfirmBox,12); stroke(ConfirmBox,CFG.Border,1,0.8)

local ConfirmTitle = Instance.new("TextLabel", ConfirmBox)
ConfirmTitle.Size=UDim2.new(1,0,0,40); ConfirmTitle.Position=UDim2.new(0,0,0,10)
ConfirmTitle.BackgroundTransparency=1; ConfirmTitle.Text="Do you really want to destroy?"
ConfirmTitle.TextColor3=CFG.Text; ConfirmTitle.TextSize=13; ConfirmTitle.Font=Enum.Font.GothamBold
ConfirmTitle.ZIndex=202

local BtnRow = Instance.new("Frame", ConfirmBox)
BtnRow.Size=UDim2.new(1,-24,0,36); BtnRow.Position=UDim2.new(0,12,1,-48)
BtnRow.BackgroundTransparency=1; BtnRow.ZIndex=202
local BtnLayout = Instance.new("UIListLayout", BtnRow)
BtnLayout.FillDirection=Enum.FillDirection.Horizontal
BtnLayout.SortOrder=Enum.SortOrder.LayoutOrder; BtnLayout.Padding=UDim.new(0,10)

local YesBtn = Instance.new("TextButton", BtnRow)
YesBtn.Size=UDim2.new(0.5,-5,1,0); YesBtn.BackgroundColor3=Color3.fromRGB(160,30,30)
YesBtn.BorderSizePixel=0; YesBtn.Text="Yes"; YesBtn.TextColor3=Color3.fromRGB(255,255,255)
YesBtn.TextSize=12; YesBtn.Font=Enum.Font.GothamBold; YesBtn.ZIndex=203; YesBtn.LayoutOrder=1; corner(YesBtn,8)

local NoBtn = Instance.new("TextButton", BtnRow)
NoBtn.Size=UDim2.new(0.5,-5,1,0); NoBtn.BackgroundColor3=Color3.fromRGB(40,40,40)
NoBtn.BorderSizePixel=0; NoBtn.Text="No"; NoBtn.TextColor3=Color3.fromRGB(200,200,200)
NoBtn.TextSize=12; NoBtn.Font=Enum.Font.GothamBold; NoBtn.ZIndex=203; NoBtn.LayoutOrder=2; corner(NoBtn,8)

CloseBtn.MouseButton1Click:Connect(function() ConfirmBg.Visible = true end)
YesBtn.MouseButton1Click:Connect(function() SG:Destroy() end)
NoBtn.MouseButton1Click:Connect(function() ConfirmBg.Visible = false end)

MinBtn.MouseButton1Click:Connect(function()
    if isBusy then return end
    isBusy = true
    savedPX = Panel.Position.X.Offset; savedPY = Panel.Position.Y.Offset
    isOpen = false
    tw(b3,fast,{Size=UDim2.new(0,11,0,2)})
    animateClose(Panel, savedPX, savedPY, function() isBusy=false; TBtn.Visible=true end)
end)

do
    local dragInput, dragStart, startPX, startPY = nil, nil, nil, nil
    Header.InputBegan:Connect(function(inp)
        if dragInput ~= nil or not isOpen then return end
        if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then
            dragInput=inp; dragStart=inp.Position; startPX=savedPX; startPY=savedPY
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if inp ~= dragInput then return end
        if inp.UserInputType==Enum.UserInputType.MouseMovement or inp.UserInputType==Enum.UserInputType.Touch then
            local delta = inp.Position - dragStart
            Panel.Position = UDim2.new(0, startPX+delta.X, 0, startPY+delta.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp == dragInput then
            if isOpen then savedPX=Panel.Position.X.Offset; savedPY=Panel.Position.Y.Offset end
            dragInput = nil
        end
    end)
end

TBtn.MouseButton1Click:Connect(function()
    if isBusy then return end; isBusy = true
    if isOpen then
        savedPX=Panel.Position.X.Offset; savedPY=Panel.Position.Y.Offset
        isOpen=false; tw(b3,fast,{Size=UDim2.new(0,11,0,2)})
        animateClose(Panel, savedPX, savedPY, function() isBusy=false; TBtn.Visible=true end)
    else
        isOpen=true; TBtn.Visible=false; tw(b3,fast,{Size=UDim2.new(0,16,0,2)})
        animateOpen(Panel, savedPX, savedPY)
        task.delay(0.42, function() isBusy=false end)
    end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == currentKeybind then
        if isBusy then return end; isBusy = true
        if isOpen then
            savedPX=Panel.Position.X.Offset; savedPY=Panel.Position.Y.Offset
            isOpen=false; tw(b3,fast,{Size=UDim2.new(0,11,0,2)})
            animateClose(Panel, savedPX, savedPY, function() isBusy=false; TBtn.Visible=true end)
        else
            isOpen=true; TBtn.Visible=false; tw(b3,fast,{Size=UDim2.new(0,16,0,2)})
            animateOpen(Panel, savedPX, savedPY)
            task.delay(0.42, function() isBusy=false end)
        end
    end
end)

task.defer(function()
    switchTab(1); task.wait(0.1)
    local vp = workspace.CurrentCamera.ViewportSize
    local px = math.floor((vp.X-CFG.W)/2)
    local py = math.floor((vp.Y-CFG.H)/2)
    Panel.Position=UDim2.new(0,px,0,py); savedPX=px; savedPY=py
    isOpen=true; isBusy=false; Panel.Visible=true; TBtn.Visible=false
    task.delay(0.6, loadSettings)
end)

print("[DakUI] OK")
