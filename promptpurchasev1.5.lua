if _G.sniperlib then
    if _G.SniperLib then
        pcall(function() _G.SniperLib:Destroy() end)
    end
    if _G.SniperConns then
        for _, c in ipairs(_G.SniperConns) do
            pcall(function() c:Disconnect() end)
        end
    end

    if game.CoreGui:FindFirstChild("LibraryGui") then
        for i, v in ipairs(game.CoreGui:GetChildren()) do
            if string.find(v.Name, "LibraryGui") then
                v:Destroy()
            end
        end
    end
end
_G.sniperlib = true

_G.SniperConns = {}
_G.SniperRunId = (_G.SniperRunId or 0) + 1
local myRunId = _G.SniperRunId

cloneref = cloneref or function(v) return v end

CoreGui             = cloneref(game:GetService("CoreGui"))
VirtualInputManager = cloneref(game:GetService("VirtualInputManager"))
GuiService          = cloneref(game:GetService("GuiService"))
MarketplaceService  = cloneref(game:GetService("MarketplaceService"))
RunService          = cloneref(game:GetService("RunService"))
Workspace           = cloneref(game:GetService("Workspace"))
Players             = cloneref(game:GetService("Players"))
StarterGui          = cloneref(game:GetService("StarterGui"))
TeleportService     = cloneref(game:GetService("TeleportService"))
HttpService         = cloneref(game:GetService("HttpService"))
LocalPlayer         = Players.LocalPlayer

startTime = os.clock()

local Request = http_request or request or (syn and syn.request) or (fluxus and fluxus.request) or (http and http.request)

local SETTINGS_FOLDER = "pnka"
local SETTINGS_FILE   = "pnka/setting.json"

local function hasFileApi()
    return isfolder and makefolder and isfile and readfile and writefile
end

local function loadConfigFile()
    if not hasFileApi() or not isfile(SETTINGS_FILE) then return nil end

    local okRead, raw = pcall(readfile, SETTINGS_FILE)
    if not okRead then return nil end

    local okDecode, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if okDecode and type(data) == "table" then return data end
    return nil
end

function SaveConfig()
    if not hasFileApi() then return end
    pcall(function()
        if not isfolder(SETTINGS_FOLDER) then makefolder(SETTINGS_FOLDER) end
        writefile(SETTINGS_FILE, HttpService:JSONEncode(_G.Config))
    end)
end

_G.Config = loadConfigFile() or _G.Config or {}

local function mergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            mergeDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

mergeDefaults(_G.Config, {
    Misc = {
        ["Close Error"]         = false,
        ["Copy UGC Info"]       = false,
        ["Enable Notification"] = true,
        ["Hide Player"]         = false,
        ["ID Filter"]           = false,
        ["Target IDs"]          = "",
    },
    Discord = {
        ["Hide Copies"]  = false,
        ["Send Webhook"] = false,
        Webhook          = "",
        ["Ping User"]    = "",
    },
})

local Config = _G.Config

function ParseIds(str)
    local set = {}
    str = str or ""

    for id in string.gmatch(str, "/item/(%d+)") do
        set[tonumber(id)] = true
    end
    for id in string.gmatch(str, "/catalog/(%d+)") do
        set[tonumber(id)] = true
    end
    for id in string.gmatch(str, "/bundles/(%d+)") do
        set[tonumber(id)] = true
    end

    local stripped = string.gsub(str, "https?://[^%s,]+", " ")
    for id in string.gmatch(stripped, "%d+") do
        set[tonumber(id)] = true
    end

    return set
end

TargetIds = ParseIds(Config.Misc["Target IDs"])

function IdsToText(set)
    local list = {}
    for id in pairs(set) do
        table.insert(list, id)
    end
    table.sort(list)
    local parts = {}
    for _, id in ipairs(list) do
        table.insert(parts, tostring(id))
    end
    return table.concat(parts, ", ")
end

function IsAllowed(assetId)
    if not Config.Misc["ID Filter"] then return true end
    if next(TargetIds) == nil then return true end
    return TargetIds[tonumber(assetId)] == true
end

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/emaankiki/my-Ui-Library/refs/heads/main/wallylib.lua"))()
_G.SniperLib = Library

local NotifierOk, Notifier = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/emaankiki/my-Ui-Library/refs/heads/main/Notification.lua"))()
end)

local function ThumbUrl(assetId)
    return "rbxthumb://type=Asset&id=" .. tostring(assetId) .. "&w=420&h=420"
end

local function Notify(title, desc, assetId)
    if not Config.Misc["Enable Notification"] then return end

    if NotifierOk and Notifier then
        local ok = pcall(function()
            local hasImage = assetId ~= nil
            Notifier:Notify(
                { Title = title, Description = desc },
                {
                    Type         = hasImage and "Image" or "Default",
                    Time         = 5,
                    OutlineColor = Color3.fromRGB(0, 170, 255)
                },
                hasImage and {
                    Image      = ThumbUrl(assetId),
                    ImageColor = Color3.fromRGB(255, 255, 255)
                } or {}
            )
        end)
        if ok then return end
    end

    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title    = title,
            Text     = desc,
            Duration = 5,
            Icon     = assetId and ThumbUrl(assetId) or nil,
        })
    end)
end

local okGame, gameInfo = pcall(function()
    return MarketplaceService:GetProductInfo(game.PlaceId)
end)
GameName = (okGame and gameInfo and gameInfo.Name) or "Unknown"

function GetItemThumbnail(assetId)
    if not Request then return nil end
    local ok, res = pcall(Request, {
        Method = "GET",
        Url = string.format("https://thumbnails.roblox.com/v1/assets?assetIds=%s&size=420x420&format=Png&isCircular=false", tostring(assetId)),
    })
    if not ok or not res or type(res.Body) ~= "string" then return nil end
    local okJson, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
    if okJson and data and data.data and data.data[1] then
        return data.data[1].imageUrl
    end
    return nil
end

LastPurchase = nil

function SendPurchaseWebhook(purchase)
    local discord = Config.Discord
    if not discord["Send Webhook"] or discord.Webhook == "" or not Request then return end

    task.spawn(function()
        local ping    = discord["Ping User"]
        local mention = ping ~= "" and ("<@" .. ping .. ">") or ""

        local serialLine = discord["Hide Copies"] and "?" or tostring(purchase.Serial)
        local stockLine  = discord["Hide Copies"] and "?" or tostring(purchase.Stock)

        local payload = HttpService:JSONEncode({
            content = mention,
            embeds = {{
                type = "rich",
                description = "### **[" .. tostring(purchase.Name) .. "](https://www.roblox.com/catalog/" .. tostring(purchase.AssetId) .. ")**\n"
                    .. "**Game:** [" .. GameName .. "](https://www.roblox.com/games/" .. tostring(game.PlaceId) .. ")\n"
                    .. "**Serial:** `" .. serialLine .. "`\n"
                    .. "**Stock Left:** `" .. stockLine .. "`\n"
                    .. "**Source:** `Prompt Purchase`",
                color = 524543,
                thumbnail = { url = GetItemThumbnail(purchase.AssetId) },
                footer = { text = "Sniper v1.5" },
            }}
        })

        pcall(Request, {
            Url     = discord.Webhook,
            Method  = "POST",
            Headers = { ["content-type"] = "application/json" },
            Body    = payload,
        })
    end)
end

local win = Library:CreateWindow("Sniper v1.5", {
    underlinecolor = "rainbow",
    topcolor       = Color3.fromRGB(20, 20, 40),
    bgcolor        = Color3.fromRGB(30, 30, 45),
    fontsize       = 16,
})

win:Section("time | fps | ms")
win:Section("Rejoin in: off")
win:Section("Last Bought: none")

PurchaseEnabled = false
RejoinMinutes   = 0
RejoinAt        = nil

win:Toggle("Enabled Purchase", { flag = "enabled", default = false }, function(on)
    PurchaseEnabled = on
end)

win:Toggle("Close Error", { flag = "closeerror", default = Config.Misc["Close Error"] }, function(on)
    Config.Misc["Close Error"] = on
    SaveConfig()
end)

win:Toggle("Copy UGC Info", { flag = "copyugc", default = Config.Misc["Copy UGC Info"] }, function(on)
    Config.Misc["Copy UGC Info"] = on
    SaveConfig()
end)

win:Toggle("Enable Notification", { flag = "notify", default = Config.Misc["Enable Notification"] }, function(on)
    Config.Misc["Enable Notification"] = on
    SaveConfig()
end)

win:Toggle("Hide Player", { flag = "hideplayer", default = Config.Misc["Hide Player"] }, function(on)
    Config.Misc["Hide Player"] = on
    SaveConfig()
end)

win:Toggle("ID Filter", { flag = "idfilter", default = Config.Misc["ID Filter"] }, function(on)
    Config.Misc["ID Filter"] = on
    SaveConfig()
end)

win:Section("Target: none")
local idBox
idBox = win:Box("Target IDs", { flag = "targetids", type = "text" }, function(value)
    Config.Misc["Target IDs"] = tostring(value or "")
    TargetIds = ParseIds(Config.Misc["Target IDs"])
    SaveConfig()
    if idBox then
        idBox.Text = IdsToText(TargetIds)
    end
    UpdateTargetSection()
end)
idBox.Text = IdsToText(TargetIds)

win:Box("Rejoin (min)", { flag = "rejoin", type = "number", default = 0, min = 0 }, function(value)
    RejoinMinutes = tonumber(value) or 0
    if RejoinMinutes > 0 then
        RejoinAt = os.clock() + RejoinMinutes * 60
    else
        RejoinAt = nil
    end
end)

statsLabel = nil
rejoinLabel = nil
lastBoughtLabel = nil

function FindSectionLabel(text)
    for _, d in ipairs(CoreGui:GetDescendants()) do
        if d.Name == "section_lbl" and d:IsA("TextLabel") and string.find(d.Text, text, 1, true) then
            return d
        end
    end
    return nil
end

function UpdateTargetSection()
    local lbl = FindSectionLabel("Target:")
    if not lbl then return end
    local text = IdsToText(TargetIds)
    lbl.Text = "Target: " .. (text ~= "" and text or "none")
end

function SetLastBought(name)
    if not lastBoughtLabel or not lastBoughtLabel:IsDescendantOf(CoreGui) then
        lastBoughtLabel = FindSectionLabel("Last Bought:")
    end
    if lastBoughtLabel then
        lastBoughtLabel.Text = "Last Bought: " .. name
    end
end

task.spawn(function()
    task.wait(0.5)
    UpdateTargetSection()
end)

task.spawn(function()
    for _ = 1, 50 do
        statsLabel = FindSectionLabel("time | fps | ms")
        rejoinLabel = FindSectionLabel("Rejoin in:")
        if statsLabel and rejoinLabel then break end
        task.wait(0.1)
    end
end)

table.insert(_G.SniperConns, RunService.RenderStepped:Connect(function()
    if not statsLabel or not statsLabel:IsDescendantOf(CoreGui) then
        statsLabel = FindSectionLabel("time | fps | ms")
        return
    end

    local elapsed = math.floor(os.clock() - startTime)
    local h = elapsed // 3600
    local m = (elapsed % 3600) // 60
    local s = elapsed % 60

    statsLabel.Text = string.format("%02d:%02d:%02d | %d fps | %d ms",
        h, m, s,
        math.round(Workspace:GetRealPhysicsFPS()),
        math.round(LocalPlayer:GetNetworkPing() * 1000))
end))

function SetPlayersHidden(hide)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            for _, part in ipairs(player.Character:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.LocalTransparencyModifier = hide and 1 or 0
                end
            end
        end
    end
end

task.spawn(function()
    while _G.SniperRunId == myRunId and not Library.destroyed do
        if Config.Misc["Hide Player"] then
            SetPlayersHidden(true)
        end
        task.wait(1)
    end
end)

function UpdateRejoin()
    if not rejoinLabel or not rejoinLabel:IsDescendantOf(CoreGui) then
        rejoinLabel = FindSectionLabel("Rejoin in:")
        if not rejoinLabel then return end
    end

    if not RejoinAt then
        rejoinLabel.Text = "Rejoin in: off"
        return
    end

    local remaining = math.max(0, math.floor(RejoinAt - os.clock()))

    if remaining <= 0 then
        RejoinAt = nil
        rejoinLabel.Text = "Rejoin in: rejoining..."
        pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end)
        return
    end

    rejoinLabel.Text = string.format("Rejoin in: %02d:%02d:%02d",
        remaining // 3600,
        (remaining % 3600) // 60,
        remaining % 60)
end

task.spawn(function()
    while _G.SniperRunId == myRunId and not Library.destroyed do
        pcall(UpdateRejoin)
        task.wait(1)
    end
end)

function CheckKick(prompt)
    if prompt.Name ~= "ErrorPrompt" then return end

    local titleFrame = prompt:WaitForChild("TitleFrame", 2)
    local errorTitle = titleFrame and titleFrame:FindFirstChild("ErrorTitle")
    local title = errorTitle and errorTitle.Text or ""

    if title == "Teleport Failed" then
        pcall(function()
            TeleportService:TeleportReconnect()
        end)
        return
    end

    local messageArea = prompt:WaitForChild("MessageArea", 2)
    local errorFrame  = messageArea and messageArea:FindFirstChild("ErrorFrame")
    local errorMsg    = errorFrame and errorFrame:FindFirstChild("ErrorMessage")
    local text        = errorMsg and errorMsg.Text or ""

    if text == "" then return end

    if string.find(text, "Unable to join game", 1, true) then
        task.wait(2)
        pcall(function()
            TeleportService:TeleportReconnect()
        end)
        return
    end

    if not string.find(text, "Teleport", 1, true) then
        pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end)
    end
end

task.spawn(function()
    local promptGui = CoreGui:WaitForChild("RobloxPromptGui", 10)
    local overlay   = promptGui and promptGui:WaitForChild("promptOverlay", 10)

    if overlay then
        table.insert(_G.SniperConns, overlay.ChildAdded:Connect(function(child)
            if _G.SniperRunId ~= myRunId then return end
            task.spawn(CheckKick, child)
        end))
    end
end)

ProductNames = {}
CurrentAssetId = nil

MessageTexts = {
    Error = {
        "You already own this item. Your account has not been charged.",
        "This item is not currently for sale. Your account has not been changed.",
        {
            Prefix = "Your purchase of ",
            Suffix = " failed because something went wrong. Your account has not been charged. Please try again later."
        }
    },
    Success = {
        { Prefix = "You have successfully bought ", Suffix = "." }
    }
}

function FastClick(Button)
    if not Button or not Button:IsDescendantOf(CoreGui) then return end
    if Button.AbsoluteSize.X <= 0 or Button.AbsoluteSize.Y <= 0 then return end

    local InsetY = GuiService:GetGuiInset().Y
    local PosX = Button.AbsolutePosition.X + Button.AbsoluteSize.X * 0.5
    local PosY = Button.AbsolutePosition.Y + Button.AbsoluteSize.Y * 0.5 + InsetY

    VirtualInputManager:SendMouseButtonEvent(PosX, PosY, 0, true, game, 1)
    VirtualInputManager:SendMouseButtonEvent(PosX, PosY, 0, false, game, 1)
end

function ClickButton(btn)
    if not btn then return end
    pcall(FastClick, btn)
end

function GetContent()
    local Overlay   = CoreGui:FindFirstChild("FoundationOverlay")
    local SafeArea  = Overlay and Overlay:FindFirstChild("SafeAreaFrame")
    local Portal    = SafeArea and SafeArea:FindFirstChild("OverlayPortal")
    local Container = Portal and Portal:FindFirstChild("SheetContainer")
    local Frame     = Container and Container:FindFirstChild("Frame")
    local Sheet     = Frame and Frame:FindFirstChild("Sheet")

    return Sheet and Sheet:FindFirstChild("Content")
end

function GetSheetCloseButton()
    local Content  = GetContent()
    local Header   = Content and Content:FindFirstChild("Header")
    local HContent = Header and Header:FindFirstChild("Content")
    local Button   = HContent and HContent:FindFirstChild("CloseAffordance")

    if not Button or not Button:IsA("GuiButton") or not Button.Visible then
        return nil
    end

    return Button
end

function SkipFilteredPrompt(assetId)
    task.spawn(function()
        local deadline = os.clock() + 3
        while os.clock() < deadline and _G.SniperRunId == myRunId do
            if CurrentAssetId ~= assetId then return end

            local button = GetSheetCloseButton()
            if button then
                ClickCloseAuto(button)
                return
            end
            task.wait(0.1)
        end
    end)
end

function ResolveMessage(Message)
    local productName = ProductNames[CurrentAssetId]

    for MsgType, Entries in pairs(MessageTexts) do
        for _, Entry in ipairs(Entries) do
            if type(Entry) == "string" then
                if Message == Entry then
                    return MsgType, Entry
                end
            elseif type(Entry) == "table" then
                local prefix = Entry.Prefix or ""
                local suffix = Entry.Suffix or ""

                if #Message >= #prefix + #suffix
                    and Message:sub(1, #prefix) == prefix
                    and Message:sub(#Message - #suffix + 1) == suffix then

                    local name = Message:sub(#prefix + 1, #Message - #suffix)
                    if not productName or name == productName then
                        return MsgType, Message
                    end
                end
            end
        end
    end

    return nil
end

function Buy()
    local Content  = GetContent()
    local Actions  = Content and Content:FindFirstChild("Actions")
    local Item     = Actions and Actions:FindFirstChild("1")
    local Button   = Item and Item:FindFirstChild("BuyButton")
    local Gradient = Button and Button:FindFirstChild("Gradient")

    if not Button or not Gradient then return end

    repeat task.wait()
    until not PurchaseEnabled or not Gradient:IsDescendantOf(CoreGui)

    while PurchaseEnabled
        and IsAllowed(CurrentAssetId)
        and Button:IsDescendantOf(CoreGui)
        and Button.Visible
        and not Button:FindFirstChild("Gradient") do

        pcall(FastClick, Button)
        task.wait(0.3)
    end
end

function FindOkLabel()
    for _, d in ipairs(CoreGui:GetDescendants()) do
        if d:IsA("TextLabel") and d.Visible and d.Text == "OK" and d.AbsoluteSize.X > 0 then
            return d
        end
    end
    return nil
end

function GetClickTarget(label)
    local node = label
    while node and node ~= CoreGui do
        if node:IsA("GuiButton") then return node end
        node = node.Parent
    end
    return label.Parent or label
end

function ReadPopup()
    local okLabel = FindOkLabel()
    if not okLabel then return nil end

    local root = okLabel
    for _ = 1, 8 do
        if not root.Parent or root.Parent == CoreGui then break end
        root = root.Parent

        for _, t in ipairs(root:GetDescendants()) do
            if t:IsA("TextLabel") and t.Visible and t.Text ~= "" and t.Text ~= "OK" then
                local msgType, canonical = ResolveMessage(t.Text)
                if msgType then
                    return {
                        Target  = okLabel,
                        Message = canonical,
                        MsgType = msgType,
                    }
                end
            end
        end
    end

    return nil
end

lastNotifiedMessage = nil

function NotifyPopup()
    local popup = ReadPopup()
    if not popup then
        lastNotifiedMessage = nil
        return
    end

    if popup.Message ~= lastNotifiedMessage then
        lastNotifiedMessage = popup.Message
        Notify(popup.MsgType, popup.Message, CurrentAssetId)

        if popup.MsgType == "Success" and LastPurchase then
            SendPurchaseWebhook(LastPurchase)
        end
    end
end

function ClickByCoords(btn)
    FastClick(btn)
end

function ClickByCoordsNoInset(btn)
    if not btn or not btn:IsDescendantOf(CoreGui) or btn.AbsoluteSize.X <= 0 then return end
    local x = btn.AbsolutePosition.X + btn.AbsoluteSize.X * 0.5
    local y = btn.AbsolutePosition.Y + btn.AbsoluteSize.Y * 0.5
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
end

function ClickByTouch(btn)
    if not btn or btn.AbsoluteSize.X <= 0 then return end
    local x = btn.AbsolutePosition.X + btn.AbsoluteSize.X * 0.5
    local y = btn.AbsolutePosition.Y + btn.AbsoluteSize.Y * 0.5
    VirtualInputManager:SendTouchEvent(1, 0, x, y)
    task.wait()
    VirtualInputManager:SendTouchEvent(1, 2, x, y)
end

function ClickBySignal(btn)
    if getconnections then
        for _, name in ipairs({ "Activated", "MouseButton1Click" }) do
            local okC, conns = pcall(getconnections, btn[name])
            if okC and type(conns) == "table" then
                for _, c in ipairs(conns) do
                    pcall(function()
                        if c.Fire then c:Fire() elseif c.Function then c.Function() end
                    end)
                end
            end
        end
    end
end

function ClickBySelection(btn)
    local previous = GuiService.SelectedObject
    GuiService.SelectedObject = btn
    task.wait()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
    task.wait()
    GuiService.SelectedObject = previous
end

CLICK_METHODS = { ClickByCoords, ClickByCoordsNoInset, ClickByTouch, ClickBySignal, ClickBySelection }

Calibrating      = false
CalibrateRetryAt = 0

ClickMethodPref = 1

function ClickCloseAuto(btn)
    if not btn or Calibrating or os.clock() < CalibrateRetryAt then return end
    Calibrating = true

    task.spawn(function()
        local n       = #CLICK_METHODS
        local pref    = ClickMethodPref
        local solved  = false

        for i = 0, n - 1 do
            if _G.SniperRunId ~= myRunId or not IsPurchaseSheetOpen() then break end

            local idx    = (pref - 1 + i) % n + 1
            local target = GetSheetCloseButton()
            if not target then break end

            pcall(CLICK_METHODS[idx], target)
            task.wait(0.4)

            if not IsPurchaseSheetOpen() or not GetSheetCloseButton() then
                solved = true
                if ClickMethodPref ~= idx then
                    ClickMethodPref = idx
                end
                break
            end
        end

        if not solved then
            CalibrateRetryAt = os.clock() + 5
        end
        Calibrating = false
    end)
end

function IsPurchaseSheetOpen()
    local Content = GetContent()
    local Actions = Content and Content:FindFirstChild("Actions")
    local Item    = Actions and Actions:FindFirstChild("1")
    local Buy     = Item and Item:FindFirstChild("BuyButton")
    return Buy ~= nil
end

function Skip()
    if IsPurchaseSheetOpen() then
        if PurchaseEnabled and IsAllowed(CurrentAssetId) then return end

        local closeBtn = GetSheetCloseButton()
        if closeBtn then
            ClickCloseAuto(closeBtn)
        end
        return
    end

    local popup = ReadPopup()
    if not popup then
        lastNotifiedMessage = nil
        return
    end

    if popup.Message ~= lastNotifiedMessage then
        lastNotifiedMessage = popup.Message
        Notify(popup.MsgType, popup.Message, CurrentAssetId)

        if popup.MsgType == "Success" and LastPurchase then
            SendPurchaseWebhook(LastPurchase)
        end
    end

    pcall(FastClick, popup.Target)
end

table.insert(_G.SniperConns, MarketplaceService.PromptPurchaseRequestedV2:Connect(function(_, AssetId)
    if _G.SniperRunId ~= myRunId then return end
    CurrentAssetId = AssetId

    if not IsAllowed(AssetId) then
        Notify("Skipped", "ID " .. tostring(AssetId) .. " is not in the ID filter", AssetId)
        SkipFilteredPrompt(AssetId)
        return
    end

    local copied = false
    if Config.Misc["Copy UGC Info"] and setclipboard then
        setclipboard("https://www.roblox.com/catalog/" .. tostring(AssetId))
        copied = true
    end

    task.spawn(function()
        local Success, Info = pcall(function()
            return MarketplaceService:GetProductInfo(AssetId, Enum.InfoType.Asset)
        end)

        if Success and Info then
            ProductNames[AssetId] = Info.Name
            SetLastBought(Info.Name)

            local INFINITY = utf8.char(8734)

            local details   = Info.CollectibleItemDetails
            local total     = details and tonumber(details.TotalQuantity)
            local remaining = tonumber(Info.Remaining)
            local isLimited = Info.IsLimited == true or Info.IsLimitedUnique == true or total ~= nil

            local stockText, serialText
            if isLimited then
                stockText = tostring(remaining or "?")

                local serial = nil
                if total and remaining and remaining >= 1 and remaining <= total then
                    serial = total - remaining + 1
                end
                serialText = serial and ("#" .. tostring(serial)) or "?"
            else
                stockText  = INFINITY
                serialText = "-"
            end

            LastPurchase = {
                AssetId = AssetId,
                Name    = Info.Name,
                Serial  = serialText,
                Stock   = stockText,
            }

            local desc = "Stock Remaining: " .. stockText
                .. "\nSerial: " .. serialText

            if copied then
                desc = desc .. "\nUGC link copied"
            end

            Notify(Info.Name, desc, AssetId)
        else
            Notify("Info Failed", tostring(Info), AssetId)
        end
    end)
end))

task.spawn(function()
    while _G.SniperRunId == myRunId and not Library.destroyed do
        pcall(NotifyPopup)
        task.wait(0.2)
    end
end)

task.spawn(function()
    while _G.SniperRunId == myRunId and not Library.destroyed do
        if Config.Misc["Close Error"] then
            pcall(Skip)
        end
        task.wait(0.1)
    end
end)

while _G.SniperRunId == myRunId and not Library.destroyed do
    local Content   = GetContent()
    local Actions   = Content and Content:FindFirstChild("Actions")
    local Item      = Actions and Actions:FindFirstChild("1")
    local BuyButton = Item and Item:FindFirstChild("BuyButton")
    local Gradient  = BuyButton and BuyButton:FindFirstChild("Gradient")

    if PurchaseEnabled and BuyButton and Gradient then
        pcall(Buy)
    end

    task.wait(0.05)
end
