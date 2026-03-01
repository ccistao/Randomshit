-- ============================================================
--  AUTO TOWER V10
--  - Quét TẤT CẢ tháp trên base (kể cả không có trong hotbar)
--  - Tích chọn tháp nào muốn nâng
--  - Balanced: nâng đều tất cả đã tích
--  - Focus: nâng full 1 cái mới chuyển sang cái tiếp
--  Buy:     Hotbar:FireServer("buy", towerID, tilePart)
--  Upgrade: Upgrade:FireServer("upgrade", towerModel)
-- ============================================================

local Players  = game:GetService("Players")
local RS       = game:GetService("ReplicatedStorage")
local UIS      = game:GetService("UserInputService")
local LP       = Players.LocalPlayer

-- Xoá UI cũ
for _, g in ipairs({LP.PlayerGui, game.CoreGui}) do
    local o = g:FindFirstChild("TowerUI")
    if o then o:Destroy() end
end

local Remotes       = RS:WaitForChild("Remotes")
local BuildRemote   = Remotes:WaitForChild("Hotbar")
local UpgradeRemote = Remotes:WaitForChild("Upgrade")

-- Quét hotbar vạn năng: parent của Buy button = Frame tên TowerID
-- sibling TextLabel "Title" = tên hiển thị đẹp
local function scanHotbarTowers()
    local result = {}
    ID_TO_NAME = {} -- reset map

    local hud = LP.PlayerGui:FindFirstChild("Hud")
    if hud then
        for _, v in ipairs(hud:GetDescendants()) do
            if v:IsA("ImageButton") and v.Name == "Buy" then
                local slotFrame = v.Parent
                if slotFrame then
                    local towerId = slotFrame.Name
                    local titleLbl = slotFrame:FindFirstChild("Title")
                    if titleLbl and titleLbl:IsA("TextLabel") and titleLbl.Text ~= "" then

                        -- lưu vào map
                        ID_TO_NAME[towerId] = titleLbl.Text

                        -- scan cost
                        local cost = 0
                        local buyBtn = slotFrame:FindFirstChild("Buy")
                        if buyBtn then
                            local amt = buyBtn:FindFirstChild("Amount")
                            if amt then
                                local num = (amt.Text or ""):gsub(",",""):match("%d+")
                                if num then cost = tonumber(num) or 0 end
                            end
                        end

                        table.insert(result, { name = titleLbl.Text, id = towerId, cost = cost })
                    end
                end
            end
        end
    end

    return result
end

local BUY_TOWERS = scanHotbarTowers()

-- ============================================================
-- STATE
-- ============================================================
local AUTO_UPGRADE  = false
local MODE          = "Balanced"   -- "Balanced" hoặc "Focus"
local SELECTED      = {}           -- [modelName_tileIndex] = true
local UPGRADE_DELAY = 0.8
local checkboxBtns  = {}           -- ref để update UI
local towerCache = {}
-- ============================================================
-- HÀM TIỆN ÍCH
-- ============================================================
local function getMoney()
    -- Tiền lưu trong Player attribute "currency"
    return LP:GetAttribute("currency") or 0
end

-- Lấy level hiện tại của tháp
local function getTowerLevel(model)
    return model:GetAttribute("level") or model:GetAttribute("Level") or 0
end

-- Max level: Farm* = 5, còn lại (súng/tháp) = 10
local function getMaxLevel(model)
    local name = model.Name:lower()
    if name:find("farm") then return 5 end
    return 10
end

local function isMaxLevel(model)
    return getTowerLevel(model) >= getMaxLevel(model)
end

local function getTileUnderFoot()
    local char = LP.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char}
    params.FilterType = Enum.RaycastFilterType.Exclude
    local res = workspace:Raycast(char.HumanoidRootPart.Position, Vector3.new(0,-15,0), params)
    return res and res.Instance or nil
end

local function getMyBase()
    local char = LP.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end
    local bases = workspace:FindFirstChild("Bases")
    if not bases then return nil end
    local myId = tostring(LP.UserId)
    -- Dùng ownerId attribute trên tile (đã xác nhận hoạt động)
    for _, b in ipairs(bases:GetChildren()) do
        local tiles = b:FindFirstChild("Tiles")
        if tiles then
            local first = tiles:GetChildren()[1]
            if first and tostring(first:GetAttribute("ownerId") or "") == myId then
                return b
            end
        end
    end
    -- Fallback: base gần nhất
    local nearest, dist = nil, 80
    for _, b in ipairs(bases:GetChildren()) do
        local bp = b:FindFirstChild("Base") or b:FindFirstChildWhichIsA("BasePart")
        if bp then
            local d = (char.HumanoidRootPart.Position - bp.Position).Magnitude
            if d < dist then dist = d; nearest = b end
        end
    end
    return nearest
end

-- Lấy tên đẹp từ Upgrade UI Info.Title khi hover/đứng gần tháp
local DISPLAY_NAMES = {}  -- [modelName] = displayName

task.spawn(function()
    while true do
        task.wait(0.3)

        local activeObj = LP:GetAttribute("upgradeActiveObject")

        if activeObj and activeObj ~= "" then

            local ok, titleLbl = pcall(function()
                return LP.PlayerGui.Hud.Hud.Upgrade.Holder.Info.Title
            end)

            if ok and titleLbl and titleLbl.Text ~= "" then

                local myBase = getMyBase()
                if myBase then

                    for _, obj in ipairs(myBase:GetDescendants()) do
                        if obj:IsA("Model") and obj.Name == tostring(activeObj) then
                            
                            -- 🔥 Lưu theo DebugId (không trùng)
                            DISPLAY_NAMES[obj:GetDebugId()] = titleLbl.Text
                            
                            break
                        end
                    end

                end
            end
        end
    end
end)
local function getTowerDisplayName(model)

    if not model or not model.Name then
        return "Unknown"
    end

    -- Farm3 đổi cứng
    if model.Name == "Farm3" then
        return "Money Printer"
    end

    -- Nếu tồn tại trong hotbar
    if ID_TO_NAME and ID_TO_NAME[model.Name] then
        return ID_TO_NAME[model.Name]
    end

    -- Các object có sẵn như Door
    return model.Name
end
-- Trả về list {model, key} của tất cả tháp trên base
local function getAllTowers(base)
    local list = {}

    for _, obj in ipairs(base:GetDescendants()) do
        if obj:IsA("Model") then

            -- Bỏ qua model con không phải tower
            if obj.Parent and obj.Parent.Name == "Tiles" then
                continue
            end

            -- Loại mấy model linh tinh không có level
            if obj:GetAttribute("level") ~= nil 
            or obj:GetAttribute("Level") ~= nil then

                local key = obj:GetDebugId()

                local lv = obj:GetAttribute("level") or 1
                local maxLv = getMaxLevel(obj)
                local dname = getTowerDisplayName(obj)
                table.insert(list, {
                    model = obj,
                    key = key,
                    displayName = dname .. " lv" .. lv .. "/" .. maxLv
                })
            end
        end
    end

    return list
end
-- ============================================================
-- UI - LAYOUT NGANG (2 cột)
-- ============================================================
local sg = Instance.new("ScreenGui")
sg.Name = "TowerUI"; sg.ResetOnSpawn = false
sg.DisplayOrder = 999; sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent = LP.PlayerGui

-- Panel ngang: rộng 420, cao vừa đủ
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 420, 0, 310)
panel.Position = UDim2.new(0.5, -210, 1, -320)  -- bám đáy màn hình
panel.BackgroundColor3 = Color3.fromRGB(12,12,22)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0; panel.Parent = sg
Instance.new("UICorner", panel).CornerRadius = UDim.new(0,14)
local pStroke = Instance.new("UIStroke", panel)
pStroke.Color = Color3.fromRGB(99,102,241); pStroke.Thickness = 1.5; pStroke.Transparency = 0.4

-- Header (kéo được)
local header = Instance.new("Frame")
header.Size = UDim2.new(1,0,0,26)
header.BackgroundColor3 = Color3.fromRGB(99,102,241)
header.BorderSizePixel = 0; header.Parent = panel
Instance.new("UICorner", header).CornerRadius = UDim.new(0,14)
local hpatch = Instance.new("Frame")
hpatch.Size = UDim2.new(1,0,0,10); hpatch.Position = UDim2.new(0,0,1,-10)
hpatch.BackgroundColor3 = Color3.fromRGB(99,102,241); hpatch.BorderSizePixel = 0; hpatch.Parent = header

local hTitle = Instance.new("TextLabel")
hTitle.Size = UDim2.new(0,200,1,0); hTitle.Position = UDim2.new(0,8,0,0)
hTitle.BackgroundTransparency = 1; hTitle.Text = "AUTO TOWER V10"
hTitle.TextColor3 = Color3.fromRGB(255,255,255); hTitle.TextSize = 12
hTitle.Font = Enum.Font.GothamBold; hTitle.TextXAlignment = Enum.TextXAlignment.Left
hTitle.Parent = header

-- Nút thu nhỏ
local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0,22,0,20); minBtn.Position = UDim2.new(1,-26,0,3)
minBtn.BackgroundColor3 = Color3.fromRGB(60,60,90); minBtn.BorderSizePixel = 0
minBtn.Text = "—"; minBtn.TextColor3 = Color3.fromRGB(255,255,255)
minBtn.TextSize = 12; minBtn.Font = Enum.Font.GothamBold
minBtn.AutoButtonColor = false; minBtn.Parent = header
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0,5)

-- Icon nhỏ (hiện khi thu nhỏ)
local miniIcon = Instance.new("TextButton")
miniIcon.Size = UDim2.new(0,44,0,44)
miniIcon.Position = UDim2.new(0,10,0.5,-22)
miniIcon.BackgroundColor3 = Color3.fromRGB(99,102,241)
miniIcon.BorderSizePixel = 0; miniIcon.Text = "🏰"
miniIcon.TextSize = 22; miniIcon.Font = Enum.Font.GothamBold
miniIcon.AutoButtonColor = false; miniIcon.Visible = false; miniIcon.Parent = sg
Instance.new("UICorner", miniIcon).CornerRadius = UDim.new(0,12)
local miStroke = Instance.new("UIStroke", miniIcon)
miStroke.Color = Color3.fromRGB(255,255,255); miStroke.Thickness = 1.5; miStroke.Transparency = 0.5

-- Drag cho miniIcon
local miDragging = false
local miDragInput
local miDragStart
local miStartPos
local DRAG_THRESHOLD = 5

miniIcon.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch
	or input.UserInputType == Enum.UserInputType.MouseButton1 then
		
		miDragInput = input
		miDragStart = input.Position
		miStartPos = miniIcon.Position
		miDragging = false
		
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				miDragInput = nil
				miDragging = false
			end
		end)
	end
end)

UIS.InputChanged:Connect(function(input)
	if input == miDragInput 
	and miDragInput 
	and input.UserInputState == Enum.UserInputState.Change then
		
		local delta = input.Position - miDragStart
		
		if not miDragging then
			if delta.Magnitude > DRAG_THRESHOLD then
				miDragging = true
			else
				return
			end
		end
		
		local newX = miStartPos.X.Offset + delta.X
		local newY = miStartPos.Y.Offset + delta.Y
		
		local screenSize = workspace.CurrentCamera.ViewportSize
		
		newX = math.clamp(newX, 0, screenSize.X - miniIcon.AbsoluteSize.X)
		newY = math.clamp(newY, 0, screenSize.Y - miniIcon.AbsoluteSize.Y)
		
		miniIcon.Position = UDim2.new(0, newX, 0, newY)
	end
end)
-- Tiền ở header bên phải
local moneyLbl = Instance.new("TextLabel")
moneyLbl.Size = UDim2.new(0,140,1,0); moneyLbl.Position = UDim2.new(1,-148,0,0)
moneyLbl.BackgroundTransparency = 1; moneyLbl.Text = "💰 $---"
moneyLbl.TextColor3 = Color3.fromRGB(250,204,21); moneyLbl.TextSize = 12
moneyLbl.Font = Enum.Font.GothamBold; moneyLbl.TextXAlignment = Enum.TextXAlignment.Right
moneyLbl.Parent = header

task.spawn(function()
    while panel.Parent do
        moneyLbl.Text = "💰 $" .. tostring(getMoney())
        task.wait(0.3)
    end
end)

-- Drag
local dragging = false
local dragInput = nil
local dragStart
local startPos
local DRAG_THRESHOLD = 5

header.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch
	or input.UserInputType == Enum.UserInputType.MouseButton1 then
		
		dragInput = input
		dragStart = input.Position
		startPos = panel.Position
		dragging = false
		
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragInput = nil
				dragging = false
			end
		end)
	end
end)

UIS.InputChanged:Connect(function(input)
	if input == dragInput 
	and dragInput 
	and input.UserInputState == Enum.UserInputState.Change then
		
		local delta = input.Position - dragStart
		
		if not dragging then
			if delta.Magnitude > DRAG_THRESHOLD then
				dragging = true
			else
				return
			end
		end
		
		local newX = startPos.X.Offset + delta.X
		local newY = startPos.Y.Offset + delta.Y
		
		local screenSize = workspace.CurrentCamera.ViewportSize
		
		newX = math.clamp(newX, -panel.AbsoluteSize.X + 40, screenSize.X - 40)
		newY = math.clamp(newY, 0, screenSize.Y - 40)
		
		panel.Position = UDim2.new(0, newX, 0, newY)
	end
end)
-- Helper button
local function makeBtn(parent, text, color, x, y, w, h)
    h = h or 30; w = w or 120
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0,w,0,h); btn.Position = UDim2.new(0,x,0,y)
    btn.BackgroundColor3 = color; btn.BorderSizePixel = 0
    btn.Text = text; btn.TextColor3 = Color3.fromRGB(255,255,255)
    btn.TextSize = 10; btn.Font = Enum.Font.GothamBold
    btn.AutoButtonColor = false; btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,7)
    return btn
end

local function makeLbl(parent, text, x, y, w, h, color, size)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0,w,0,h or 14); l.Position = UDim2.new(0,x,0,y)
    l.BackgroundTransparency = 1; l.Text = text
    l.TextColor3 = color or Color3.fromRGB(148,163,184); l.TextSize = size or 10
    l.Font = Enum.Font.GothamBold; l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = parent
    return l
end

-- ============================================================
-- CỘT TRÁI: MUA THÁP (x=6, width=196)
-- ============================================================
makeLbl(panel, "MUA THÁP", 8, 30, 190, 14, Color3.fromRGB(148,163,184), 10)

local buyBtns = {}  -- ref các nút mua để xoá khi refresh

local function rebuildBuyButtons()
    -- Xoá nút cũ
    for _, b in ipairs(buyBtns) do
        if b and b.Parent then b:Destroy() end
    end
    buyBtns = {}

    BUY_TOWERS = scanHotbarTowers()
    local buyY = 46
    for _, t in ipairs(BUY_TOWERS) do
        local label = t.name .. (t.cost > 0 and ("  $"..t.cost) or "")
        local btn = makeBtn(panel, label, Color3.fromRGB(30,80,150), 8, buyY, 190, 28)
        table.insert(buyBtns, btn)
        local orig = label
        btn.MouseButton1Click:Connect(function()
            local tile = getTileUnderFoot()
            if tile then
                BuildRemote:FireServer("buy", t.id, tile)
                btn.Text = t.name .. " ✓"
            else
                btn.Text = "Khong thay tile!"
            end
            task.delay(1.2, function() btn.Text = orig end)
        end)
        buyY += 32
    end
end

rebuildBuyButtons()

-- Tự refresh nút mua mỗi 3s (khi hotbar game thay đổi)
task.spawn(function()
    while panel.Parent do
        task.wait(3)
        rebuildBuyButtons()
    end
end)

-- Separator dọc
local sepV = Instance.new("Frame")
sepV.Size = UDim2.new(0,1,1,-30); sepV.Position = UDim2.new(0,208,0,28)
sepV.BackgroundColor3 = Color3.fromRGB(60,60,80); sepV.BorderSizePixel = 0; sepV.Parent = panel

-- ============================================================
-- CỘT PHẢI: NÂNG CẤP (x=214, width=200)
-- ============================================================
makeLbl(panel, "THÁP NÂNG CẤP", 214, 30, 200, 14, Color3.fromRGB(148,163,184), 10)

-- ScrollingFrame checkbox
local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(0,196,0,120)
scrollFrame.Position = UDim2.new(0,214,0,46)
scrollFrame.BackgroundColor3 = Color3.fromRGB(6,6,16)
scrollFrame.BackgroundTransparency = 0.3
scrollFrame.BorderSizePixel = 0
scrollFrame.ScrollBarThickness = 3
scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(99,102,241)
scrollFrame.CanvasSize = UDim2.new(0,0,0,0)
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollFrame.Parent = panel
Instance.new("UICorner", scrollFrame).CornerRadius = UDim.new(0,6)
local scrollLayout = Instance.new("UIListLayout", scrollFrame)
scrollLayout.Padding = UDim.new(0,2)
Instance.new("UIPadding", scrollFrame).PaddingTop = UDim.new(0,3)

-- Row 1: Quét + Chọn tất cả
local scanBtn    = makeBtn(panel, "🔍 Da quet", Color3.fromRGB(79,70,229),  214, 170, 94, 26)
local selAllBtn  = makeBtn(panel, "Chọn tất cả",  Color3.fromRGB(55,65,81),   312, 170, 98, 26)

-- Row 2: Mode + Auto
local modeBtn = makeBtn(panel, "⚖ Balanced", Color3.fromRGB(14,116,144), 214, 200, 94, 26)
local autoBtn = makeBtn(panel, "▶ Auto: OFF", Color3.fromRGB(150,50,50),  312, 200, 98, 26)

-- Row 3: Nâng 1 lần + Status
local manualBtn = makeBtn(panel, "Nâng 1 lần", Color3.fromRGB(22,163,74), 214, 230, 94, 26)
local statusLbl = makeLbl(panel, "San sang", 312, 234, 100, 20, Color3.fromRGB(130,130,130), 10)

-- ============================================================
-- LOGIC TÍCH CHỌN
-- ============================================================
local function rebuildCheckboxes()

    for _, c in ipairs(scrollFrame:GetChildren()) do
        if c:IsA("Frame") then
            c:Destroy()
        end
    end
    checkboxBtns = {}

    local base = getMyBase()
    if not base then
        statusLbl.Text = "Khong thay base!"
        return
    end

    towerCache = getAllTowers(base) or {}

    if #towerCache == 0 then
        statusLbl.Text = "Base chua co thap nao"
        return
    end

    statusLbl.Text = #towerCache .. " thap"

    for _, info in ipairs(towerCache) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1,-4,0,28)
        row.BackgroundTransparency = 1
        row.BorderSizePixel = 0
        row.Parent = scrollFrame

        local cb = Instance.new("TextButton")
        cb.Size = UDim2.new(0,20,0,20)
        cb.Position = UDim2.new(0,4,0.5,-10)
        cb.BackgroundColor3 = SELECTED[info.key] and Color3.fromRGB(22,163,74) or Color3.fromRGB(50,50,70)
        cb.Text = SELECTED[info.key] and "✔" or ""
        cb.TextColor3 = Color3.fromRGB(255,255,255)
        cb.TextSize = 12
        cb.Font = Enum.Font.GothamBold
        cb.BorderSizePixel = 0
        cb.AutoButtonColor = false
        cb.Parent = row
        Instance.new("UICorner", cb).CornerRadius = UDim.new(0,5)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1,-30,1,0)
        lbl.Position = UDim2.new(0,28,0,0)
        lbl.BackgroundTransparency = 1
        lbl.Text = info.displayName
        lbl.TextColor3 = Color3.fromRGB(210,210,210)
        lbl.TextSize = 11
        lbl.Font = Enum.Font.Gotham
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        local key = info.key

        cb.MouseButton1Click:Connect(function()
            SELECTED[key] = not SELECTED[key]
            cb.Text = SELECTED[key] and "✔" or ""
            cb.BackgroundColor3 = SELECTED[key] and Color3.fromRGB(22,163,74) or Color3.fromRGB(50,50,70)
        end)

        table.insert(checkboxBtns, {cb = cb, key = key})
    end
end

-- Auto quét mỗi 2 giây
scanBtn.MouseButton1Click:Connect(rebuildCheckboxes)
task.spawn(function()
    while panel.Parent do
        task.wait(2)
        rebuildCheckboxes()
    end
end)

-- Chọn / bỏ chọn tất cả
local allSelected = false
selAllBtn.MouseButton1Click:Connect(function()
    allSelected = not allSelected
    selAllBtn.Text = allSelected and "Bỏ chọn tất cả" or "Chọn tất cả"
    for _, info in ipairs(towerCache) do
        SELECTED[info.key] = allSelected
    end
    for _, item in ipairs(checkboxBtns) do
        item.cb.Text = allSelected and "✔" or ""
        item.cb.BackgroundColor3 = allSelected and Color3.fromRGB(22,163,74) or Color3.fromRGB(50,50,70)
    end
end)

-- Mode toggle
modeBtn.MouseButton1Click:Connect(function()
    MODE = MODE == "Balanced" and "Focus" or "Balanced"
    if MODE == "Balanced" then
        modeBtn.Text = "⚖ BALANCED - Nâng đều"
        modeBtn.BackgroundColor3 = Color3.fromRGB(14,116,144)
    else
        modeBtn.Text = "🎯 FOCUS - Full 1 cái"
        modeBtn.BackgroundColor3 = Color3.fromRGB(124,58,237)
    end
end)

-- Auto toggle
autoBtn.MouseButton1Click:Connect(function()
    AUTO_UPGRADE = not AUTO_UPGRADE
    autoBtn.Text = "▶ AUTO UPGRADE: " .. (AUTO_UPGRADE and "ON" or "OFF")
    autoBtn.BackgroundColor3 = AUTO_UPGRADE and Color3.fromRGB(22,163,74) or Color3.fromRGB(150,50,50)
end)

-- ============================================================
-- HÀM NÂNG CẤP
-- ============================================================
local function getSelectedTowers()
    local base = getMyBase()
    if not base then return {} end
    local all = getAllTowers(base)
    local filtered = {}
    for _, info in ipairs(all) do
        if SELECTED[info.key] then
            table.insert(filtered, info.model)
        end
    end
    -- Nếu không tích gì → nâng tất cả
    if #filtered == 0 then
        for _, info in ipairs(all) do
            table.insert(filtered, info.model)
        end
    end
    return filtered
end

-- Đọc giá từ Hud.Upgrade.Holder.Stats.Cost.AmountHolder.Amount
-- Game tự set upgradeActiveObject khi đứng gần tháp (không cần click)
local COST_CACHE = {}  -- ["TenModel_lvX"] = cost

local function getUpgradeCostFromHud()
    local ok, amount = pcall(function()
        return LP.PlayerGui.Hud.Hud.Upgrade.Holder.Stats.Cost.AmountHolder.Amount
    end)
    if not ok or not amount then return nil end
    local num = (amount.Text or ""):match("%d+")
    return tonumber(num)
end

-- Background: cập nhật cache liên tục
task.spawn(function()
    while true do
        task.wait(0.2)
        local activeObj = LP:GetAttribute("upgradeActiveObject")
        local visible   = LP:GetAttribute("upgradeVisible")
        if visible and activeObj and activeObj ~= "" then
            local cost = getUpgradeCostFromHud()
            if cost and cost > 0 then
                -- Tìm model đang active để lấy level
                local myBase = getMyBase()
                if myBase then
                    for _, obj in ipairs(myBase:GetDescendants()) do
                        if obj:IsA("Model") and obj.Name == tostring(activeObj) then
                            local key = obj.Name .. "_lv" .. (getTowerLevel(obj))
                            COST_CACHE[key] = cost
                            break
                        end
                    end
                end
            end
        end
    end
end)

local LAST_FIRE = {}
local function canAfford(model)
    local id = model:GetDebugId()
    -- Tối thiểu 0.4s giữa 2 lần fire cùng tháp
    if (os.clock() - (LAST_FIRE[id] or 0)) < 0.4 then return false end
    local key = model.Name .. "_lv" .. getTowerLevel(model)
    local cost = COST_CACHE[key]
    if cost then
        return getMoney() >= cost
    end
    -- Chưa cache: thử 2s/lần (tránh spam)
    return (os.clock() - (LAST_FIRE[id] or 0)) >= 2
end

local function recordFire(model)
    LAST_FIRE[model:GetDebugId()] = os.clock()
end

local function doUpgradeBalanced(towers)
    local upgraded = 0
    local maxed = 0
    for _, tw in ipairs(towers) do
        if not tw or not tw.Parent then continue end
        if isMaxLevel(tw) then
            maxed += 1
            continue
        end
        if canAfford(tw) then
            UpgradeRemote:FireServer("upgrade", tw)
            recordFire(tw)
            upgraded += 1
        else
            statusLbl.Text = "Thieu tien: " .. tw.Name .. " (lv" .. getTowerLevel(tw) .. ")"
        end
        task.wait(0.15)
    end
    if maxed == #towers then
        statusLbl.Text = "Tat ca da MAX level!"
        AUTO_UPGRADE = false
        autoBtn.Text = "▶ AUTO UPGRADE: OFF"
        autoBtn.BackgroundColor3 = Color3.fromRGB(150,50,50)
    elseif upgraded > 0 then
        statusLbl.Text = "✓ Nang " .. upgraded .. " thap"
    else
        -- Tìm cost nhỏ nhất cần
        local minCost = nil
        for _, tw in ipairs(towers) do
            if tw and tw.Parent and not isMaxLevel(tw) then
                local key = tw.Name .. "_lv" .. getTowerLevel(tw)
                local c = COST_CACHE[key]
                if c and (not minCost or c < minCost) then minCost = c end
            end
        end
        if minCost then
            statusLbl.Text = "💰 Can $" .. minCost .. " | co $" .. getMoney()
        else
            statusLbl.Text = "⏳ Dang doc gia... ($" .. getMoney() .. ")"
        end
    end
end

local function doUpgradeFocus(towers)
    -- Focus: nâng 1 cái đến lv max rồi mới chuyển cái tiếp
    -- Farm max = lv5, súng/tháp max = lv10
    for _, tw in ipairs(towers) do
        if not tw or not tw.Parent then continue end

        local maxLv = getMaxLevel(tw)

        while AUTO_UPGRADE do
            if not tw or not tw.Parent then break end

            local curLv = getTowerLevel(tw)
            if curLv >= maxLv then
                statusLbl.Text = tw.Name .. " MAX (lv" .. curLv .. ") → next"
                task.wait(0.3)
                break
            end

            if not canAfford(tw) then
                statusLbl.Text = "Cho tien: " .. tw.Name .. " lv" .. curLv .. "/" .. maxLv
                task.wait(0.5)
                continue
            end

            UpgradeRemote:FireServer("upgrade", tw)
            recordFire(tw)
            statusLbl.Text = "Focus: " .. tw.Name .. " lv" .. curLv .. " → " .. maxLv
            task.wait(0.35)
        end
    end

    if AUTO_UPGRADE then
        statusLbl.Text = "Tat ca da MAX! Auto off"
        AUTO_UPGRADE = false
        autoBtn.Text = "▶ AUTO UPGRADE: OFF"
        autoBtn.BackgroundColor3 = Color3.fromRGB(150,50,50)
    end
end

-- Nút nâng 1 lần
manualBtn.MouseButton1Click:Connect(function()
    local towers = getSelectedTowers()
    if #towers == 0 then statusLbl.Text = "Khong co thap!"; return end
    doUpgradeBalanced(towers)
    statusLbl.Text = "Da nang " .. #towers .. " thap!"
end)

-- ============================================================
-- VÒNG LẶP AUTO UPGRADE
-- ============================================================
task.spawn(function()
    while true do
        task.wait(UPGRADE_DELAY)
        if not AUTO_UPGRADE then continue end

        local towers = getSelectedTowers()
        if #towers == 0 then
            statusLbl.Text = "Chua quet thap"
            continue
        end

        if MODE == "Balanced" then
            doUpgradeBalanced(towers)
            statusLbl.Text = "Balanced: " .. #towers .. " thap"
        else
            doUpgradeFocus(towers)
            statusLbl.Text = "Focus: " .. #towers .. " thap"
        end
    end
end)

-- Quét ngay lúc khởi động
task.delay(1, rebuildCheckboxes)
print("[TowerV10] Da chay!")
