--[[
	NEMESIS UI Library  (v2.0)
	A Roblox/Luau UI library for script executors — desktop cheat-menu layout.

	Load:
		local NEMESIS = loadstring(game:HttpGet("https://raw.githubusercontent.com/DiabloPaidProjects/NEMESIS/main/source.lua"))()

	v2.0 redesign (desktop-first; still scales down on touch):
		- Horizontal top tab bar (Combat / Visuals / …) with an accent underline
		- Grouped left sidebar of sub-tabs (group headers + pages + standalone items)
		- Breadcrumb + config bar (config dropdown, save, 3-dot) in the content header
		- Collapsible content Sections holding inline rows (label left / control right)
		- Status footer (game name, connection state, live FPS) + config icon buttons

	API (dot-style, hierarchy Window -> Tab -> Group -> Page -> Section -> controls):
		local Win     = NEMESIS.Window({ title = "NEMESIS", game = "CS2" })
		local Combat  = Win.Tab("Combat")
		local Aimbot  = Combat.Group("AIMBOT")
		local General = Aimbot.Page("General", { icon = "crosshair", dot = true })
		local Misc    = Combat.Page("Misc", { icon = "sliders-horizontal" })  -- standalone
		local gen     = General.Section("GENERAL")
		gen.Toggle({ text = "Enable", default = true, flag = "aim_enable" })
		gen.Dropdown({ text = "Weapon Group", options = { "Rifles", "Pistols" }, default = "Rifles" })
		gen.Keybind({ text = "Keybind", default = "MOUSE5", mode = "Hold" })
]]

local NEMESIS = {}
NEMESIS.Flags = {}
NEMESIS.Version = "2.0.0"

----------------------------------------------------------------------
-- Services (cloneref-safe)
----------------------------------------------------------------------
local function getService(name)
	local ok, svc = pcall(function()
		return game:GetService(name)
	end)
	if ok and svc then
		if type(cloneref) == "function" then
			local ok2, c = pcall(cloneref, svc)
			if ok2 and c then
				return c
			end
		end
		return svc
	end
	return nil
end

local TweenService = getService("TweenService")
local UserInputService = getService("UserInputService")
local RunService = getService("RunService")
local Players = getService("Players")
local CoreGui = getService("CoreGui")

----------------------------------------------------------------------
-- Executor compatibility
----------------------------------------------------------------------
local function localPlayer()
	return Players and Players.LocalPlayer
end

local function getGuiParent()
	if type(gethui) == "function" then
		local ok, h = pcall(gethui)
		if ok and h then return h end
	end
	if type(get_hidden_gui) == "function" then
		local ok, h = pcall(get_hidden_gui)
		if ok and h then return h end
	end
	if CoreGui then
		return CoreGui
	end
	local lp = localPlayer()
	if lp then
		return lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
	end
	return nil
end

local function protectGui(gui)
	pcall(function()
		if syn and syn.protect_gui then
			syn.protect_gui(gui)
		elseif type(protectgui) == "function" then
			protectgui(gui)
		end
	end)
end

local function setClipboard(text)
	for _, fn in ipairs({ setclipboard, toclipboard, set_clipboard }) do
		if type(fn) == "function" then
			pcall(fn, text)
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- Brand logo (real image, no Roblox upload needed)
-- Downloads the PNG and exposes it via the executor's custom-asset API
-- (getcustomasset / getsynasset), cached on disk after the first load.
----------------------------------------------------------------------
local LOGO_URL = "https://raw.githubusercontent.com/DiabloPaidProjects/NEMESIS/main/assets/nemesis_logo.png"
local LOGO_FILE = "nemesis_logo_v2.png" -- bump when assets/nemesis_logo.png changes (busts on-disk cache)
local brandLogoCache = nil -- nil = untried, false = failed, string = rbxasset id

local function customAssetFn()
	if type(getcustomasset) == "function" then return getcustomasset end
	if type(getsynasset) == "function" then return getsynasset end
	if syn and type(syn.getcustomasset) == "function" then
		return function(p) return syn.getcustomasset(p) end
	end
	return nil
end

local function loadBrandLogo()
	if brandLogoCache ~= nil then return brandLogoCache or nil end
	brandLogoCache = false
	local getAsset = customAssetFn()
	if not getAsset or type(writefile) ~= "function" then return nil end
	pcall(function()
		local have = type(isfile) == "function" and isfile(LOGO_FILE)
		if not have then
			local data = game:HttpGet(LOGO_URL)
			if type(data) == "string" and #data > 500 then
				writefile(LOGO_FILE, data)
				have = true
			end
		end
		if have then
			local id = getAsset(LOGO_FILE)
			if type(id) == "string" and id ~= "" then brandLogoCache = id end
		end
	end)
	return brandLogoCache or nil
end

----------------------------------------------------------------------
-- Icons (Lucide names via Rayfield's icon map, or raw asset IDs)
----------------------------------------------------------------------
local ICON_URL = "https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/refs/heads/main/icons.lua"
local iconMap = nil -- nil = not tried, false = failed, table = loaded

local function loadIconMap()
	if iconMap ~= nil then
		return iconMap
	end
	iconMap = false
	if type(loadstring) == "function" then
		pcall(function()
			local src = game:HttpGet(ICON_URL)
			local fn = loadstring(src)
			if type(fn) == "function" then
				local ok, map = pcall(fn)
				if ok and type(map) == "table" then
					iconMap = map
				end
			end
		end)
	end
	return iconMap
end

local function resolveIcon(icon)
	if not icon or icon == 0 or icon == "" then
		return nil
	end
	if type(icon) == "number" then
		return { Image = "rbxassetid://" .. icon }
	end
	if type(icon) == "string" then
		if string.match(icon, "^%d+$") then
			return { Image = "rbxassetid://" .. icon }
		end
		if string.find(icon, "rbxassetid://") == 1 or string.sub(icon, 1, 4) == "http" then
			return { Image = icon }
		end
		local map = loadIconMap()
		if type(map) == "table" then
			local sized = map["48px"] or map
			local entry = sized and sized[string.lower(icon)]
			if entry then
				return {
					Image = "rbxassetid://" .. entry[1],
					ImageRectSize = Vector2.new(entry[2][1], entry[2][2]),
					ImageRectOffset = Vector2.new(entry[3][1], entry[3][2]),
				}
			end
		end
	end
	return nil
end

local function applyIcon(image, spec)
	if not spec or not spec.Image then
		image.Image = ""
		image.Visible = false
		return false
	end
	image.Image = spec.Image
	if spec.ImageRectSize then
		image.ImageRectSize = spec.ImageRectSize
	end
	if spec.ImageRectOffset then
		image.ImageRectOffset = spec.ImageRectOffset
	end
	image.Visible = true
	return true
end

----------------------------------------------------------------------
-- Instance helpers
----------------------------------------------------------------------
local function Create(class, props, children)
	local inst = Instance.new(class)
	if props then
		for k, v in pairs(props) do
			if k ~= "Parent" then
				inst[k] = v
			end
		end
	end
	if children then
		for _, c in ipairs(children) do
			c.Parent = inst
		end
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(rad)
	return Create("UICorner", { CornerRadius = UDim.new(0, rad or 8) })
end

local function stroke(color, thickness, transparency)
	return Create("UIStroke", {
		Color = color or Color3.fromRGB(45, 45, 58),
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function padding(all)
	return Create("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, all),
		PaddingRight = UDim.new(0, all),
	})
end

local function padXY(x, y)
	return Create("UIPadding", {
		PaddingLeft = UDim.new(0, x),
		PaddingRight = UDim.new(0, x),
		PaddingTop = UDim.new(0, y or 0),
		PaddingBottom = UDim.new(0, y or 0),
	})
end

local function tagSearch(frame, text)
	pcall(function()
		frame:SetAttribute("NemesisSearch", tostring(text or ""))
	end)
end

----------------------------------------------------------------------
-- Theme
----------------------------------------------------------------------
local THEME = {
	Background = Color3.fromRGB(13, 14, 20),      -- window / content background
	Sidebar = Color3.fromRGB(16, 17, 24),         -- left sidebar
	Topbar = Color3.fromRGB(16, 17, 24),          -- top bar
	SidebarActive = Color3.fromRGB(34, 28, 52),   -- active sidebar sub-tab tint
	SidebarHover = Color3.fromRGB(24, 25, 34),    -- sidebar row hover
	Group = Color3.fromRGB(20, 21, 29),           -- content section card
	Element = Color3.fromRGB(25, 26, 35),         -- dropdown / keybind / input field
	ElementHover = Color3.fromRGB(33, 34, 45),
	Stroke = Color3.fromRGB(38, 40, 51),          -- borders / dividers
	ElementStroke = Color3.fromRGB(46, 48, 61),
	RowDivider = Color3.fromRGB(30, 32, 42),      -- hairline between rows
	Text = Color3.fromRGB(236, 237, 243),
	SubText = Color3.fromRGB(138, 140, 156),
	Faint = Color3.fromRGB(92, 94, 110),          -- breadcrumb separators
	Accent = Color3.fromRGB(140, 90, 255),        -- primary accent (purple)
	ToggleOff = Color3.fromRGB(58, 60, 73),       -- toggle track when off
	Knob = Color3.fromRGB(244, 245, 250),         -- toggle / slider knob
	Good = Color3.fromRGB(80, 220, 130),          -- status dot
}

local FONT = Enum.Font.Gotham
local FONT_MED = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold

-- Inline-row layout metrics (scaled by the window's UIScale at runtime)
local ROW_H = 46          -- height of a setting row
local ROW_PAD = 16        -- horizontal inset inside a row / section
local FIELD_W = 230       -- dropdown / keybind / input field width
local SLIDER_W = 250      -- slider (value + track) cluster width

local function hexOf(c)
	return string.format("%02X%02X%02X",
		math.floor((c.R or 0) * 255 + 0.5),
		math.floor((c.G or 0) * 255 + 0.5),
		math.floor((c.B or 0) * 255 + 0.5))
end

----------------------------------------------------------------------
-- Gradient helpers
----------------------------------------------------------------------
local function numSeq(a, b)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, a),
		NumberSequenceKeypoint.new(1, b),
	})
end

local function hueSequence()
	local kp = {}
	for i = 0, 6 do
		table.insert(kp, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1)))
	end
	return ColorSequence.new(kp)
end

----------------------------------------------------------------------
-- Tween helpers
----------------------------------------------------------------------
local TI = {
	EXP = TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),    -- hover, fills, flashes
	FAST = TweenInfo.new(0.3, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),   -- toggle, arrows
	TAB = TweenInfo.new(0.7, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),    -- open, tab switch, page slide
	EXPAND = TweenInfo.new(0.45, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),-- dropdown / panels / collapse
	POP = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),          -- slider handle grab
}
TI.OPEN = TI.TAB
TI.HOVER = TI.EXP
TI.SLIDE = TI.EXPAND
TI.NOTIFY = TI.EXP

local function tween(inst, props, info)
	local t = TweenService:Create(inst, info or TI.SLIDE, props)
	t:Play()
	return t
end

----------------------------------------------------------------------
-- Mobile / scale
----------------------------------------------------------------------
local IS_MOBILE = false
pcall(function()
	IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end)

local function viewportSize()
	local ok, vp = pcall(function()
		return workspace.CurrentCamera.ViewportSize
	end)
	if ok and vp and vp.X and vp.X > 0 then
		return vp
	end
	return Vector2.new(1280, 720)
end

local function computeScale()
	local vp = viewportSize()
	local w = vp.X
	if IS_MOBILE then
		return math.clamp(w / 1000, 0.7, 1.1)
	end
	return math.clamp(w / 1560, 0.7, 1.0)
end

----------------------------------------------------------------------
-- Unified mouse + touch drag
----------------------------------------------------------------------
local function makeDraggable(frame, handle)
	handle = handle or frame
	local dragging = false
	local dragStart, startPos

	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
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

-- generic horizontal drag for sliders / channels (mouse + touch)
local function bindBarDrag(hit, onAlpha)
	local dragging = false
	local function upd(input)
		local rel = math.clamp((input.Position.X - hit.AbsolutePosition.X) / hit.AbsoluteSize.X, 0, 1)
		onAlpha(rel)
	end
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			upd(input)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			upd(input)
		end
	end)
end

local function bindHover(button, target, base, hover)
	button.MouseEnter:Connect(function()
		tween(target, { BackgroundColor3 = hover }, TI.HOVER)
	end)
	button.MouseLeave:Connect(function()
		tween(target, { BackgroundColor3 = base }, TI.HOVER)
	end)
end

----------------------------------------------------------------------
-- Root ScreenGui + notifications
----------------------------------------------------------------------
local screenGui
local notifyHolder

local function ensureRoot()
	if screenGui and screenGui.Parent then
		return screenGui
	end
	screenGui = Create("ScreenGui", {
		Name = "NEMESIS_" .. tostring(math.random(1000, 9999)),
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 9999,
		IgnoreGuiInset = true,
	})
	pcall(function()
		screenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	protectGui(screenGui)
	screenGui.Parent = getGuiParent()

	notifyHolder = Create("Frame", {
		Name = "Notifications",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -20),
		Size = UDim2.new(0, 290, 1, -40),
		BackgroundTransparency = 1,
		Parent = screenGui,
	}, {
		Create("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
	})
	return screenGui
end

----------------------------------------------------------------------
-- Notifications
----------------------------------------------------------------------
function NEMESIS.Notify(opts)
	opts = opts or {}
	ensureRoot()

	local accent = opts.accent or THEME.Accent
	local iconSpec = resolveIcon(opts.icon)
	local textInset = iconSpec and 34 or 0

	local card = Create("Frame", {
		Name = "Notif",
		BackgroundColor3 = THEME.Element,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Position = UDim2.new(1, 40, 0, 0),
		Parent = notifyHolder,
	}, {
		corner(10),
		stroke(THEME.ElementStroke, 1, 0.1),
		padding(12),
	})
	local notifStroke = card:FindFirstChildOfClass("UIStroke")

	if iconSpec then
		local img = Create("ImageLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 0, 0, 1),
			Size = UDim2.new(0, 22, 0, 22),
			ImageColor3 = accent,
			ImageTransparency = 1,
			Parent = card,
		})
		applyIcon(img, iconSpec)
	end

	local title = Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, textInset, 0, 0),
		Size = UDim2.new(1, -textInset, 0, 16),
		Font = FONT_BOLD,
		Text = tostring(opts.title or "Notification"),
		TextColor3 = accent,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 1,
		Parent = card,
	})
	local content = Create("TextLabel", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, textInset, 0, 20),
		Size = UDim2.new(1, -textInset, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = FONT,
		Text = tostring(opts.content or ""),
		TextColor3 = THEME.Text,
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 1,
		Parent = card,
	})

	tween(card, { Position = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 0 }, TI.EXP)
	tween(title, { TextTransparency = 0 }, TI.EXP)
	tween(content, { TextTransparency = 0 }, TI.EXP)
	for _, c in ipairs(card:GetChildren()) do
		if c:IsA("ImageLabel") then tween(c, { ImageTransparency = 0 }, TI.EXP) end
	end

	local duration = tonumber(opts.duration) or 4
	task.delay(duration, function()
		if not card or not card.Parent then return end
		tween(card, { Position = UDim2.new(1, 40, 0, 0), BackgroundTransparency = 1 }, TI.EXP)
		if notifStroke then tween(notifStroke, { Transparency = 1 }, TI.EXP) end
		tween(title, { TextTransparency = 1 }, TI.EXP)
		tween(content, { TextTransparency = 1 }, TI.EXP)
		for _, c in ipairs(card:GetChildren()) do
			if c:IsA("ImageLabel") then tween(c, { ImageTransparency = 1 }, TI.EXP) end
		end
		task.delay(0.5, function() if card then card:Destroy() end end)
	end)
end

----------------------------------------------------------------------
-- Inline row scaffold (label on the left, control on the right)
----------------------------------------------------------------------
-- Rows live inside a Section's body. A hairline separator is inserted above
-- every row except the first (tracked via the body's "hasRow" attribute).
local function newRow(parent, height)
	if parent:GetAttribute("hasRow") then
		Create("Frame", {
			Size = UDim2.new(1, -ROW_PAD * 2, 0, 1),
			BackgroundColor3 = THEME.RowDivider,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Parent = parent,
		})
	end
	parent:SetAttribute("hasRow", true)
	return Create("Frame", {
		BackgroundColor3 = THEME.Group,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height or ROW_H),
		Parent = parent,
	}, { padXY(ROW_PAD, 0) })
end

-- Left-hand label (single line by default; optional muted description line).
local function rowText(parent, text, desc, rightReserve)
	rightReserve = rightReserve or 48
	tagSearch(parent, (desc and desc ~= "") and (tostring(text) .. " " .. tostring(desc)) or text)
	if desc and desc ~= "" then
		local col = Create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -rightReserve, 1, 0),
			Parent = parent,
		}, {
			Create("UIListLayout", {
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 2),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		Create("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 16),
			Font = FONT_MED,
			Text = tostring(text or ""),
			TextColor3 = THEME.Text,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = col,
		})
		Create("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 13),
			Font = FONT,
			Text = tostring(desc),
			TextColor3 = THEME.SubText,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = col,
		})
		return col
	end
	return Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -rightReserve, 1, 0),
		Font = FONT_MED,
		Text = tostring(text or ""),
		TextColor3 = THEME.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = parent,
	})
end

-- A right-aligned rounded field box (used by dropdown / keybind / input).
local function fieldBox(row, w)
	return Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, w or FIELD_W, 0, 32),
		BackgroundColor3 = THEME.Element,
		Parent = row,
	}, { corner(8), stroke(THEME.ElementStroke, 1, 0.35) })
end

----------------------------------------------------------------------
-- Element factories: (parent, accent, opts) -> control { Set, Get }
----------------------------------------------------------------------
local Elements = {}

function Elements.Label(parent, accent, text)
	local lbl = Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -ROW_PAD * 2, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0, ROW_PAD, 0, 0),
		Font = FONT,
		Text = tostring((type(text) == "table" and text.text) or text or ""),
		TextColor3 = THEME.SubText,
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	})
	tagSearch(lbl, lbl.Text)
	return {
		Set = function(v) lbl.Text = tostring(v) end,
		Get = function() return lbl.Text end,
	}
end

function Elements.Paragraph(parent, accent, opts)
	opts = opts or {}
	local holder = Create("Frame", {
		BackgroundColor3 = THEME.Element,
		Size = UDim2.new(1, -ROW_PAD * 2, 0, 0),
		Position = UDim2.new(0, ROW_PAD, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, {
		corner(10),
		stroke(THEME.Stroke, 1, 0.4),
		padding(12),
		Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		Create("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 18),
			Font = FONT_BOLD,
			Text = tostring(opts.title or "Title"),
			TextColor3 = THEME.Text,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Create("TextLabel", {
			Name = "Body",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Font = FONT,
			Text = tostring(opts.content or ""),
			TextColor3 = THEME.SubText,
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})
	tagSearch(holder, (opts.title or "") .. " " .. (opts.content or ""))
	return {
		Set = function(v) holder:FindFirstChild("Body").Text = tostring(v) end,
	}
end

function Elements.Button(parent, accent, opts)
	opts = opts or {}
	local row = newRow(parent, opts.desc and 58 or ROW_H)
	local click = Create("TextButton", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, ROW_PAD * 2, 1, 0),
		Position = UDim2.new(0, -ROW_PAD, 0, 0),
		Text = "",
		Parent = row,
	})
	rowText(row, opts.text, opts.desc, 90)
	local chip = Create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 70, 0, 28),
		BackgroundColor3 = THEME.Element,
		Font = FONT_MED,
		Text = tostring(opts.button or "Run"),
		TextColor3 = accent,
		TextSize = 13,
		Parent = row,
	}, { corner(8), stroke(THEME.ElementStroke, 1, 0.35) })
	click.MouseEnter:Connect(function() tween(chip, { BackgroundColor3 = THEME.ElementHover }, TI.EXP) end)
	click.MouseLeave:Connect(function() tween(chip, { BackgroundColor3 = THEME.Element }, TI.EXP) end)
	click.MouseButton1Click:Connect(function()
		tween(chip, { BackgroundColor3 = accent }, TI.FAST)
		tween(chip, { TextColor3 = THEME.Text }, TI.FAST)
		task.delay(0.18, function()
			tween(chip, { BackgroundColor3 = THEME.Element }, TI.EXP)
			tween(chip, { TextColor3 = accent }, TI.EXP)
		end)
		if type(opts.callback) == "function" then pcall(opts.callback) end
	end)
	return { Instance = row }
end

function Elements.Toggle(parent, accent, opts)
	opts = opts or {}
	local state = opts.default and true or false
	local row = newRow(parent, opts.desc and 58 or ROW_H)
	rowText(row, opts.text, opts.desc, 64)

	local track = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 44, 0, 24),
		BackgroundColor3 = THEME.ToggleOff,
		Parent = row,
	}, { corner(12) })
	local knob = Create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.new(0, 18, 0, 18),
		BackgroundColor3 = THEME.Knob,
		Parent = track,
	}, { corner(9) })
	local click = Create("TextButton", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, ROW_PAD * 2, 1, 0),
		Position = UDim2.new(0, -ROW_PAD, 0, 0),
		Text = "",
		Parent = row,
	})

	local control = {}
	local function render(animate)
		local info = animate and TI.FAST or TweenInfo.new(0)
		tween(track, { BackgroundColor3 = state and accent or THEME.ToggleOff }, info)
		tween(knob, { Position = state and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) }, info)
	end
	function control.Set(v, silent)
		state = v and true or false
		if opts.flag then NEMESIS.Flags[opts.flag] = state end
		render(true)
		if not silent and type(opts.callback) == "function" then
			pcall(opts.callback, state)
		end
	end
	function control.Get() return state end

	click.MouseButton1Click:Connect(function() control.Set(not state) end)

	if opts.flag then NEMESIS.Flags[opts.flag] = state end
	render(false)
	return control
end

function Elements.Slider(parent, accent, opts)
	opts = opts or {}
	local min = tonumber(opts.min) or 0
	local max = tonumber(opts.max) or 100
	local increment = tonumber(opts.increment) or 1
	local value = math.clamp(tonumber(opts.default) or min, min, max)
	local suffix = opts.suffix or ""
	local decimals = opts.decimals
	if decimals == nil then decimals = (increment < 1) and 2 or 0 end

	local function fmt(v)
		if decimals > 0 then
			return string.format("%." .. decimals .. "f", v) .. suffix
		end
		return tostring(math.floor(v + 0.5)) .. suffix
	end

	local row = newRow(parent, ROW_H)
	rowText(row, opts.text, opts.desc, SLIDER_W + 16)

	local cluster = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, SLIDER_W, 1, 0),
		BackgroundTransparency = 1,
		Parent = row,
	})
	local valueLabel = Create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.new(0, 48, 0, 16),
		Font = FONT_MED,
		Text = fmt(value),
		TextColor3 = THEME.Text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = cluster,
	})
	local bar = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(1, -56, 0, 5),
		BackgroundColor3 = THEME.ElementStroke,
		Parent = cluster,
	}, { corner(3) })
	local fill = Create("Frame", {
		Size = UDim2.new((value - min) / (max - min), 0, 1, 0),
		BackgroundColor3 = accent,
		Parent = bar,
	}, { corner(3) })
	local handle = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new((value - min) / (max - min), 0, 0.5, 0),
		Size = UDim2.new(0, 13, 0, 13),
		BackgroundColor3 = accent,
		ZIndex = 2,
		Parent = bar,
	}, { corner(7), stroke(THEME.Background, 2, 0) })

	local control = {}
	local function setFromAlpha(alpha, fire, instant)
		alpha = math.clamp(alpha, 0, 1)
		local raw = min + (max - min) * alpha
		local stepped = min + math.floor((raw - min) / increment + 0.5) * increment
		value = math.clamp(stepped, min, max)
		local frac = (value - min) / (max - min)
		valueLabel.Text = fmt(value)
		if instant then
			fill.Size = UDim2.new(frac, 0, 1, 0)
			handle.Position = UDim2.new(frac, 0, 0.5, 0)
		else
			tween(fill, { Size = UDim2.new(frac, 0, 1, 0) }, TI.EXP)
			tween(handle, { Position = UDim2.new(frac, 0, 0.5, 0) }, TI.EXP)
		end
		if opts.flag then NEMESIS.Flags[opts.flag] = value end
		if fire and type(opts.callback) == "function" then
			pcall(opts.callback, value)
		end
	end
	function control.Set(v) setFromAlpha(((tonumber(v) or min) - min) / (max - min), true, false) end
	function control.Get() return value end

	bindBarDrag(bar, function(rel) setFromAlpha(rel, true, true) end)
	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			tween(handle, { Size = UDim2.new(0, 17, 0, 17) }, TI.POP)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			tween(handle, { Size = UDim2.new(0, 13, 0, 13) }, TI.POP)
		end
	end)

	if opts.flag then NEMESIS.Flags[opts.flag] = value end
	return control
end

function Elements.Dropdown(parent, accent, opts)
	opts = opts or {}
	local options = opts.options or {}
	local multi = opts.multi and true or false
	local selected = {}
	if multi and type(opts.default) == "table" then
		for _, v in ipairs(opts.default) do selected[v] = true end
	end
	local single = (not multi) and opts.default or nil

	local row = newRow(parent, ROW_H)
	rowText(row, opts.text, opts.desc, FIELD_W + 24)
	local field = fieldBox(row, FIELD_W)

	local current = Create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 0),
		Size = UDim2.new(1, -34, 1, 0),
		Font = FONT,
		Text = "...",
		TextColor3 = THEME.Text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = field,
	})
	local arrow
	local chevSpec = resolveIcon("chevron-down")
	if chevSpec then
		arrow = Create("ImageLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.new(0, 15, 0, 15),
			ImageColor3 = THEME.SubText,
			Parent = field,
		})
		applyIcon(arrow, chevSpec)
	else
		arrow = Create("TextLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.new(0, 14, 1, 0),
			Font = FONT_BOLD,
			Text = "\u{25BE}",
			TextColor3 = THEME.SubText,
			TextSize = 13,
			Parent = field,
		})
	end

	-- right-aligned droplist that pushes following content down
	local listHolder = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		ClipsDescendants = true,
		Parent = parent,
	})
	local listInner = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -ROW_PAD, 0, 2),
		Size = UDim2.new(0, FIELD_W, 1, -2),
		BackgroundColor3 = THEME.Element,
		Parent = listHolder,
	}, {
		corner(8),
		stroke(THEME.Stroke, 1, 0.3),
		Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
		padding(4),
	})

	local open = false
	local control = {}
	local function listValues()
		local list = {}
		for _, v in ipairs(options) do
			if selected[v] then table.insert(list, v) end
		end
		return list
	end
	local function refreshLabel()
		if multi then
			local parts = listValues()
			current.Text = #parts > 0 and table.concat(parts, ", ") or "None"
		else
			current.Text = single ~= nil and tostring(single) or "None"
		end
		current.TextColor3 = (multi and #listValues() > 0 or single ~= nil) and THEME.Text or THEME.SubText
	end
	local function fire()
		if opts.flag then NEMESIS.Flags[opts.flag] = multi and listValues() or single end
		if type(opts.callback) == "function" then
			pcall(opts.callback, multi and listValues() or single)
		end
	end

	local optionButtons = {}
	local function rebuildOptions()
		for _, b in ipairs(optionButtons) do b:Destroy() end
		optionButtons = {}
		for _, v in ipairs(options) do
			local ob = Create("TextButton", {
				BackgroundColor3 = THEME.Element,
				Size = UDim2.new(1, 0, 0, 28),
				Font = FONT,
				Text = tostring(v),
				TextColor3 = THEME.Text,
				TextSize = 13,
				AutoButtonColor = false,
				Parent = listInner,
			}, { corner(6) })
			local function paint()
				local on = multi and selected[v] or (single == v)
				ob.TextColor3 = on and accent or THEME.Text
				ob.BackgroundColor3 = on and THEME.ElementHover or THEME.Element
			end
			paint()
			ob.MouseEnter:Connect(function()
				local on = multi and selected[v] or (single == v)
				if not on then tween(ob, { BackgroundColor3 = THEME.ElementHover }, TI.EXP) end
			end)
			ob.MouseLeave:Connect(function()
				local on = multi and selected[v] or (single == v)
				if not on then tween(ob, { BackgroundColor3 = THEME.Element }, TI.EXP) end
			end)
			ob.MouseButton1Click:Connect(function()
				if multi then selected[v] = not selected[v] else single = v end
				for _, b in ipairs(optionButtons) do
					b.TextColor3 = THEME.Text
					b.BackgroundColor3 = THEME.Element
				end
				paint()
				refreshLabel()
				fire()
				if not multi then control.Toggle(false) end
			end)
			table.insert(optionButtons, ob)
		end
	end

	function control.Toggle(force)
		open = (force == nil) and (not open) or force
		local target = open and (math.min(#options, 6) * 30 + 10) or 0
		tween(listHolder, { Size = UDim2.new(1, 0, 0, target) }, TI.EXPAND)
		tween(arrow, { Rotation = open and 180 or 0 }, TI.FAST)
		tween(field, { BackgroundColor3 = open and THEME.ElementHover or THEME.Element }, TI.FAST)
	end
	function control.Set(v)
		if multi then
			selected = {}
			if type(v) == "table" then for _, x in ipairs(v) do selected[x] = true end end
		else
			single = v
		end
		rebuildOptions(); refreshLabel(); fire()
	end
	function control.Get() return multi and listValues() or single end
	function control.SetOptions(newOptions)
		options = newOptions or {}
		rebuildOptions(); refreshLabel()
	end

	local click = Create("TextButton", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, ROW_PAD * 2, 1, 0),
		Position = UDim2.new(0, -ROW_PAD, 0, 0),
		Text = "",
		Parent = row,
	})
	click.MouseButton1Click:Connect(function() control.Toggle() end)

	rebuildOptions(); refreshLabel()
	if opts.flag then NEMESIS.Flags[opts.flag] = control.Get() end
	return control
end

function Elements.Input(parent, accent, opts)
	opts = opts or {}
	local row = newRow(parent, ROW_H)
	rowText(row, opts.text, opts.desc, FIELD_W + 24)
	local field = fieldBox(row, FIELD_W)
	local fieldStroke = field:FindFirstChildOfClass("UIStroke")
	local box = Create("TextBox", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 0),
		Size = UDim2.new(1, -20, 1, 0),
		Font = FONT,
		PlaceholderText = tostring(opts.placeholder or "..."),
		Text = tostring(opts.default or ""),
		TextColor3 = THEME.Text,
		PlaceholderColor3 = THEME.SubText,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = opts.clearOnFocus and true or false,
		Parent = field,
	})

	local control = {}
	function control.Set(v) box.Text = tostring(v) end
	function control.Get() return box.Text end
	box.Focused:Connect(function()
		if fieldStroke then tween(fieldStroke, { Color = accent }, TI.EXP) end
	end)
	box.FocusLost:Connect(function()
		if fieldStroke then tween(fieldStroke, { Color = THEME.ElementStroke }, TI.EXP) end
		if opts.flag then NEMESIS.Flags[opts.flag] = box.Text end
		if type(opts.callback) == "function" then pcall(opts.callback, box.Text) end
	end)
	if opts.flag then NEMESIS.Flags[opts.flag] = box.Text end
	return control
end

----------------------------------------------------------------------
-- Keybind (supports keyboard KeyCodes and mouse buttons via strings)
----------------------------------------------------------------------
local MOUSE_TO_UIT = { MOUSE1 = "MouseButton1", MOUSE2 = "MouseButton2", MOUSE3 = "MouseButton3" }

local function keyDisplay(k)
	if k == nil then return "None" end
	if type(k) == "string" then return k end
	local ok, n = pcall(function() return k.Name end)
	return (ok and n) or tostring(k)
end

local function inputMatchesKey(input, k)
	if k == nil then return false end
	if type(k) == "string" then
		local uit = MOUSE_TO_UIT[k]
		if uit then
			local target = Enum.UserInputType[uit]
			return input.UserInputType == target
		end
		-- MOUSE4 / MOUSE5 (side buttons) are not reliably delivered; display only
		return false
	end
	return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == k
end

function Elements.Keybind(parent, accent, opts)
	opts = opts or {}
	local mode = opts.mode or "Toggle"
	local key = opts.default
	local row = newRow(parent, ROW_H)
	rowText(row, opts.text, opts.desc, FIELD_W + 24)
	local field = fieldBox(row, FIELD_W)
	local fieldStroke = field:FindFirstChildOfClass("UIStroke")
	local btn = Create("TextButton", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Font = FONT_MED,
		Text = keyDisplay(key),
		TextColor3 = THEME.Text,
		TextSize = 13,
		AutoButtonColor = false,
		Parent = field,
	})

	local listening = false
	local toggled = false
	local control = {}
	function control.Set(v)
		key = v
		btn.Text = keyDisplay(key)
		btn.TextColor3 = THEME.Text
		if fieldStroke then tween(fieldStroke, { Color = THEME.ElementStroke }, TI.EXP) end
		if opts.flag then NEMESIS.Flags[opts.flag] = key end
	end
	function control.Get() return key end

	btn.MouseButton1Click:Connect(function()
		listening = true
		btn.Text = "..."
		btn.TextColor3 = accent
		if fieldStroke then tween(fieldStroke, { Color = accent }, TI.EXP) end
	end)
	UserInputService.InputBegan:Connect(function(input, gpe)
		if listening then
			if input.UserInputType == Enum.UserInputType.Keyboard then
				listening = false
				if input.KeyCode == Enum.KeyCode.Escape then control.Set(nil) else control.Set(input.KeyCode) end
				return
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
				listening = false; control.Set("MOUSE2"); return
			elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
				listening = false; control.Set("MOUSE3"); return
			end
			return
		end
		if gpe then return end
		if inputMatchesKey(input, key) then
			if mode == "Toggle" then
				toggled = not toggled
				if type(opts.callback) == "function" then pcall(opts.callback, toggled) end
			elseif mode == "Hold" then
				if type(opts.callback) == "function" then pcall(opts.callback, true) end
			else
				if type(opts.callback) == "function" then pcall(opts.callback) end
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if mode == "Hold" and inputMatchesKey(input, key) then
			if type(opts.callback) == "function" then pcall(opts.callback, false) end
		end
	end)

	if opts.flag then NEMESIS.Flags[opts.flag] = key end
	return control
end

----------------------------------------------------------------------
-- Color picker (full pop-out panel: SV square, hue, alpha, HEX)
----------------------------------------------------------------------
function Elements.ColorPicker(parent, accent, opts)
	opts = opts or {}
	local value = opts.default or Color3.fromRGB(255, 255, 255)
	local alpha = tonumber(opts.transparency) or 0 -- 0 = opaque, 1 = clear
	local h, s, v = value:ToHSV()

	local row = newRow(parent, ROW_H)
	rowText(row, opts.text, opts.desc, 64)
	local swatch = Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 46, 0, 26),
		BackgroundColor3 = value,
		Text = "",
		AutoButtonColor = false,
		Parent = row,
	}, { corner(7), stroke(THEME.Stroke, 1, 0.2) })

	local control = {}
	local panel, svBase, svDot, hueDot, alphaBar, alphaDot, hexBox, pctLabel
	local opened = false

	local function colorNow() return Color3.fromHSV(h, s, v) end
	local function syncUI()
		value = colorNow()
		swatch.BackgroundColor3 = value
		if svBase then svBase.BackgroundColor3 = Color3.fromHSV(h, 1, 1) end
		if svDot then svDot.Position = UDim2.new(s, 0, 1 - v, 0) end
		if hueDot then hueDot.Position = UDim2.new(h, 0, 0.5, 0) end
		if alphaBar then alphaBar.BackgroundColor3 = value end
		if alphaDot then alphaDot.Position = UDim2.new(1 - alpha, 0, 0.5, 0) end
		if hexBox then hexBox.Text = "#" .. hexOf(value) end
		if pctLabel then pctLabel.Text = tostring(math.floor((1 - alpha) * 100 + 0.5)) .. "%" end
	end
	local function commit()
		if opts.flag then NEMESIS.Flags[opts.flag] = value end
		if type(opts.callback) == "function" then pcall(opts.callback, value, alpha) end
	end

	local function buildPanel()
		panel = Create("Frame", {
			Name = "ColorPanel",
			Size = UDim2.new(0, 230, 0, 250),
			BackgroundColor3 = THEME.Group,
			Visible = false,
			ZIndex = 50,
			Parent = screenGui,
		}, {
			corner(14),
			stroke(THEME.Stroke, 1, 0),
			padding(10),
			Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		})

		local sv = Create("Frame", {
			Size = UDim2.new(1, 0, 0, 130),
			BackgroundColor3 = Color3.fromHSV(h, 1, 1),
			Parent = panel,
		}, { corner(6) })
		svBase = sv
		Create("Frame", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = sv,
		}, { corner(6), Create("UIGradient", { Transparency = numSeq(0, 1) }) })
		Create("Frame", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			Parent = sv,
		}, { corner(6), Create("UIGradient", { Rotation = 90, Transparency = numSeq(1, 0) }) })
		svDot = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(s, 0, 1 - v, 0),
			Size = UDim2.new(0, 10, 0, 10),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 52,
			Parent = sv,
		}, { corner(5), stroke(Color3.new(0, 0, 0), 1, 0.3) })
		local svHit = Create("TextButton", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Text = "", ZIndex = 53, Parent = sv })
		do
			local dragging = false
			local function upd(input)
				local rx = math.clamp((input.Position.X - sv.AbsolutePosition.X) / sv.AbsoluteSize.X, 0, 1)
				local ry = math.clamp((input.Position.Y - sv.AbsolutePosition.Y) / sv.AbsoluteSize.Y, 0, 1)
				s = rx; v = 1 - ry
				syncUI(); commit()
			end
			svHit.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					dragging = true; upd(input)
				end
			end)
			UserInputService.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
			end)
			UserInputService.InputChanged:Connect(function(input)
				if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then upd(input) end
			end)
		end

		local hue = Create("Frame", { Size = UDim2.new(1, 0, 0, 14), Parent = panel }, {
			corner(7),
			Create("UIGradient", { Color = hueSequence() }),
		})
		hueDot = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(h, 0, 0.5, 0),
			Size = UDim2.new(0, 6, 1, 4),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 52,
			Parent = hue,
		}, { corner(3), stroke(Color3.new(0, 0, 0), 1, 0.3) })
		bindBarDrag(hue, function(rel) h = rel; syncUI(); commit() end)

		alphaBar = Create("Frame", { Size = UDim2.new(1, 0, 0, 14), BackgroundColor3 = value, Parent = panel }, {
			corner(7),
			Create("UIGradient", { Transparency = numSeq(0, 1) }),
		})
		alphaDot = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1 - alpha, 0, 0.5, 0),
			Size = UDim2.new(0, 6, 1, 4),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 52,
			Parent = alphaBar,
		}, { corner(3), stroke(Color3.new(0, 0, 0), 1, 0.3) })
		bindBarDrag(alphaBar, function(rel) alpha = 1 - rel; syncUI(); commit() end)

		local hexRow = Create("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Parent = panel })
		Create("TextLabel", {
			BackgroundTransparency = 1, Size = UDim2.new(0, 36, 1, 0),
			Font = FONT_BOLD, Text = "HEX", TextColor3 = THEME.SubText, TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left, Parent = hexRow,
		})
		hexBox = Create("TextBox", {
			Position = UDim2.new(0, 40, 0, 0), Size = UDim2.new(1, -90, 1, 0),
			BackgroundColor3 = THEME.Element, Font = FONT, Text = "#FFFFFF",
			TextColor3 = THEME.Text, TextSize = 13, Parent = hexRow,
		}, { corner(6), stroke(THEME.Stroke, 1, 0.3), padding(6) })
		pctLabel = Create("TextLabel", {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 44, 1, 0),
			BackgroundTransparency = 1, Font = FONT_MED, Text = "100%", TextColor3 = THEME.SubText, TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Right, Parent = hexRow,
		})
		hexBox.FocusLost:Connect(function()
			local hex = string.gsub(hexBox.Text, "#", "")
			if #hex == 6 then
				local r = tonumber(string.sub(hex, 1, 2), 16)
				local g = tonumber(string.sub(hex, 3, 4), 16)
				local b = tonumber(string.sub(hex, 5, 6), 16)
				if r and g and b then
					h, s, v = Color3.fromRGB(r, g, b):ToHSV()
					syncUI(); commit()
					return
				end
			end
			syncUI()
		end)

		syncUI()
	end

	local function openPanel(state)
		if not panel then buildPanel() end
		opened = (state == nil) and (not opened) or state
		if opened then
			local ok = pcall(function()
				local p = swatch.AbsolutePosition
				panel.Position = UDim2.fromOffset(p.X - 184, p.Y + 30)
			end)
			if not ok then panel.Position = UDim2.new(0.5, -115, 0.5, -125) end
			panel.Visible = true
			panel.Size = UDim2.new(0, 230, 0, 0)
			tween(panel, { Size = UDim2.new(0, 230, 0, 250) }, TI.EXPAND)
		else
			tween(panel, { Size = UDim2.new(0, 230, 0, 0) }, TI.SLIDE)
			task.delay(0.2, function() if not opened and panel then panel.Visible = false end end)
		end
	end

	swatch.MouseButton1Click:Connect(function() openPanel() end)
	swatch.MouseButton2Click:Connect(function()
		local hex = "#" .. hexOf(value)
		if setClipboard(hex) then NEMESIS.Notify({ title = "Copied", content = hex, duration = 2 }) end
	end)

	function control.Set(c, a)
		value = c
		h, s, v = c:ToHSV()
		if a ~= nil then alpha = a end
		swatch.BackgroundColor3 = c
		if panel then syncUI() end
		commit()
	end
	function control.Get() return value end
	function control.GetAlpha() return alpha end

	if opts.flag then NEMESIS.Flags[opts.flag] = value end
	return control
end

----------------------------------------------------------------------
-- Collapsible content section ("GENERAL", "HITBOX", …)
----------------------------------------------------------------------
local function makeSection(pageBody, accent, title)
	local card = Create("Frame", {
		BackgroundColor3 = THEME.Group,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = pageBody,
	}, {
		corner(14),
		stroke(THEME.Stroke, 1, 0.35),
		Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	local bodyWrap = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		LayoutOrder = 2,
		Parent = card,
	})
	local body = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = bodyWrap,
	}, {
		Create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
		Create("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8) }),
	})

	if title and title ~= "" then
		local header = Create("TextButton", {
			Size = UDim2.new(1, 0, 0, 42),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = 1,
			Parent = card,
		}, { padXY(ROW_PAD, 0) })
		Create("TextLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.new(1, -30, 1, 0),
			Font = FONT_BOLD,
			Text = string.upper(tostring(title)),
			TextColor3 = accent,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = header,
		})
		local chev
		local chevSpec = resolveIcon("chevron-up")
		if chevSpec then
			chev = Create("ImageLabel", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
				Size = UDim2.new(0, 16, 0, 16),
				ImageColor3 = THEME.SubText,
				Parent = header,
			})
			applyIcon(chev, chevSpec)
		else
			chev = Create("TextLabel", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
				Size = UDim2.new(0, 16, 1, 0),
				Font = FONT_BOLD,
				Text = "\u{25B4}",
				TextColor3 = THEME.SubText,
				TextSize = 14,
				Parent = header,
			})
		end
		-- header divider
		Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.new(1, -ROW_PAD * 2, 0, 1),
			BackgroundColor3 = THEME.RowDivider,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			Parent = header,
		})

		local open = true
		header.MouseButton1Click:Connect(function()
			open = not open
			tween(chev, { Rotation = open and 0 or 180 }, TI.FAST)
			if open then
				bodyWrap.Visible = true
				bodyWrap.AutomaticSize = Enum.AutomaticSize.Y
				bodyWrap.Size = UDim2.new(1, 0, 0, 0)
			else
				local hgt = 0
				pcall(function() hgt = bodyWrap.AbsoluteSize.Y end)
				bodyWrap.AutomaticSize = Enum.AutomaticSize.None
				bodyWrap.Size = UDim2.new(1, 0, 0, hgt)
				tween(bodyWrap, { Size = UDim2.new(1, 0, 0, 0) }, TI.EXPAND)
				task.delay(0.32, function() if not open then bodyWrap.Visible = false end end)
			end
		end)
	end

	local host = {}
	local function bind(elName)
		return function(a) return Elements[elName](body, accent, a) end
	end
	host.Button = bind("Button")
	host.Toggle = bind("Toggle")
	host.Slider = bind("Slider")
	host.Dropdown = bind("Dropdown")
	host.Input = bind("Input")
	host.Keybind = bind("Keybind")
	host.ColorPicker = bind("ColorPicker")
	host.Paragraph = bind("Paragraph")
	host.Label = function(text) return Elements.Label(body, accent, text) end
	return host
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
local function titleCase(str)
	str = tostring(str or "")
	return (string.gsub(string.lower(str), "(%a)([%w]*)", function(a, b)
		return string.upper(a) .. b
	end))
end

function NEMESIS.Window(opts)
	opts = opts or {}
	local accent = opts.accent or THEME.Accent
	local accentHex = hexOf(accent)
	ensureRoot()

	local scale = computeScale()
	local W = opts.width or (IS_MOBILE and 620 or 960)
	local H = opts.height or (IS_MOBILE and 460 or 640)
	local TOPBAR_H = 60
	local SIDEBAR_W = IS_MOBILE and 168 or 212
	local FOOTER_H = 96
	local RADIUS = 16

	local root = Create("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, W, 0, H),
		BackgroundColor3 = THEME.Background,
		ClipsDescendants = true,
		Parent = screenGui,
	}, {
		Create("UIScale", { Scale = scale }),
		corner(RADIUS),
		stroke(THEME.Stroke, 1.5, 0),
	})

	--------------------------------------------------------------------
	-- Top bar: logo + wordmark | top tabs | search + min/close
	--------------------------------------------------------------------
	local topbar = Create("Frame", {
		Size = UDim2.new(1, 0, 0, TOPBAR_H),
		BackgroundColor3 = THEME.Topbar,
		BorderSizePixel = 0,
		Parent = root,
	}, { corner(RADIUS) })
	-- bottom filler squares the topbar's lower corners so it meets the body;
	-- hidden while minimized so the bar shows its rounded bottom corners
	local topbarFiller = Create("Frame", {
		Position = UDim2.new(0, 0, 1, -RADIUS),
		Size = UDim2.new(1, 0, 0, RADIUS),
		BackgroundColor3 = THEME.Topbar,
		BorderSizePixel = 0,
		Parent = topbar,
	})
	local topbarDivider = Create("Frame", {
		Position = UDim2.new(0, 0, 1, -1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = THEME.Stroke,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = topbar,
	})
	makeDraggable(root, topbar)

	-- logo: the real NEMESIS brand image (downloaded + loaded via getcustomasset,
	-- no Roblox upload). Falls back to a gradient "N" tile + wordmark on executors
	-- without custom-asset support. opts.logo = <assetId> forces an uploaded image.
	local wordmarkText = string.upper(tostring(opts.title or "NEMESIS"))
	local logoSpec = (opts.logo ~= nil) and resolveIcon(opts.logo) or nil
	local brandAsset = (opts.logo == nil) and loadBrandLogo() or nil

	local function wordmark(x)
		return Create("TextLabel", {
			Position = UDim2.new(0, x, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.new(0, 160, 1, 0),
			BackgroundTransparency = 1,
			Font = FONT_BOLD,
			Text = wordmarkText,
			TextColor3 = Color3.fromRGB(232, 220, 255),
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = topbar,
		}, {
			stroke(Color3.fromRGB(150, 92, 255), 1, 0.45),
			Create("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(192, 152, 255)),
			}),
		})
	end

	if brandAsset then
		-- full N + NEMESIS brand image (aspect ~3.67); wordmark is part of it
		Create("ImageLabel", {
			Position = UDim2.new(0, 14, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.new(0, 162, 0, 44),
			BackgroundTransparency = 1,
			Image = brandAsset,
			ScaleType = Enum.ScaleType.Fit,
			Parent = topbar,
		})
	elseif logoSpec then
		local logoImg = Create("ImageLabel", {
			Position = UDim2.new(0, 16, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.new(0, 40, 0, 40),
			BackgroundTransparency = 1,
			Parent = topbar,
		})
		applyIcon(logoImg, logoSpec)
		wordmark(64)
	else
		local tile = Create("Frame", {
			Position = UDim2.new(0, 18, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.new(0, 34, 0, 34),
			BackgroundColor3 = accent,
			Parent = topbar,
		}, {
			corner(10),
			stroke(Color3.fromRGB(185, 155, 255), 1, 0.25),
			Create("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new(Color3.fromRGB(168, 124, 255), Color3.fromRGB(118, 70, 234)),
			}),
		})
		Create("TextLabel", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Font = FONT_BOLD,
			Text = "N",
			TextColor3 = THEME.Text,
			TextSize = 20,
			Parent = tile,
		})
		wordmark(62)
	end

	-- centered top-tab bar
	local tabBar = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = topbar,
	}, {
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	-- icon button factory (top bar / content header / footer)
	local function iconButton(parent, iconName, fallback, size, props)
		props = props or {}
		local b = Create("TextButton", {
			Size = UDim2.new(0, size or 28, 0, size or 28),
			BackgroundColor3 = props.bg or THEME.Element,
			BackgroundTransparency = props.bg and 0 or 1,
			Font = FONT_BOLD,
			Text = "",
			TextColor3 = props.tint or THEME.SubText,
			TextSize = 16,
			AutoButtonColor = false,
			Parent = parent,
		}, props.bg and { corner(8) } or nil)
		local spec = resolveIcon(iconName)
		if spec then
			local img = Create("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				Size = UDim2.new(0, props.iconSize or 16, 0, props.iconSize or 16),
				BackgroundTransparency = 1,
				ImageColor3 = props.tint or THEME.SubText,
				Parent = b,
			})
			applyIcon(img, spec)
			if not props.bg then
				b.MouseEnter:Connect(function() tween(img, { ImageColor3 = accent }, TI.HOVER) end)
				b.MouseLeave:Connect(function() tween(img, { ImageColor3 = props.tint or THEME.SubText }, TI.HOVER) end)
			end
		else
			b.Text = fallback
			b.TextColor3 = props.tint or THEME.SubText
			if not props.bg then
				b.MouseEnter:Connect(function() tween(b, { TextColor3 = accent }, TI.HOVER) end)
				b.MouseLeave:Connect(function() tween(b, { TextColor3 = props.tint or THEME.SubText }, TI.HOVER) end)
			end
		end
		return b
	end

	-- top-bar icon button: Lucide image with a glyph fallback + swappable icon
	local function topbarIcon(iconName, fallback, xOffset, glyphSize)
		local b = Create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, xOffset, 0.5, 0),
			Size = UDim2.new(0, 26, 0, 26),
			BackgroundTransparency = 1,
			Font = FONT_BOLD,
			Text = "",
			TextColor3 = THEME.SubText,
			TextSize = glyphSize or 16,
			AutoButtonColor = false,
			Parent = topbar,
		})
		local img
		local function setIcon(name, fb)
			local spec = resolveIcon(name)
			if spec then
				if not img then
					img = Create("ImageLabel", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(0.5, 0, 0.5, 0),
						Size = UDim2.new(0, 16, 0, 16),
						BackgroundTransparency = 1,
						ImageColor3 = THEME.SubText,
						Parent = b,
					})
				end
				applyIcon(img, spec)
				b.Text = ""
			else
				if img then img.Visible = false end
				b.Text = fb or ""
			end
		end
		setIcon(iconName, fallback)
		local function tint(c)
			if img and img.Visible then tween(img, { ImageColor3 = c }, TI.HOVER) else tween(b, { TextColor3 = c }, TI.HOVER) end
		end
		b.MouseEnter:Connect(function() tint(accent) end)
		b.MouseLeave:Connect(function() tint(THEME.SubText) end)
		return b, setIcon
	end

	local closeBtn = topbarIcon("x", "\u{2715}", -16, 16)
	local minBtn, setMinIcon = topbarIcon("minus", "\u{2013}", -48, 18)

	-- search pill
	local searchW = IS_MOBILE and 150 or 230
	local searchPill = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -82, 0.5, 0),
		Size = UDim2.new(0, searchW, 0, 34),
		BackgroundColor3 = THEME.Element,
		Parent = topbar,
	}, { corner(9), stroke(THEME.Stroke, 1, 0.3) })
	local searchPillStroke = searchPill:FindFirstChildOfClass("UIStroke")
	local searchIcon = Create("ImageLabel", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 11, 0.5, 0),
		Size = UDim2.new(0, 15, 0, 15),
		BackgroundTransparency = 1,
		ImageColor3 = THEME.SubText,
		Parent = searchPill,
	})
	local hasSearchIcon = applyIcon(searchIcon, resolveIcon("search"))
	local searchBox = Create("TextBox", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, hasSearchIcon and 34 or 12, 0, 0),
		Size = UDim2.new(1, hasSearchIcon and -44 or -22, 1, 0),
		Font = FONT,
		PlaceholderText = "Search (Ctrl + K)",
		Text = "",
		TextColor3 = THEME.Text,
		PlaceholderColor3 = THEME.SubText,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Parent = searchPill,
	})

	--------------------------------------------------------------------
	-- Body: sidebar (with footer) | content (header + pages)
	--------------------------------------------------------------------
	local body = Create("Frame", {
		Position = UDim2.new(0, 0, 0, TOPBAR_H),
		Size = UDim2.new(1, 0, 1, -TOPBAR_H),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = root,
	})

	local sidebarBG = Create("Frame", {
		Size = UDim2.new(0, SIDEBAR_W, 1, 0),
		BackgroundColor3 = THEME.Sidebar,
		BorderSizePixel = 0,
		Parent = body,
	}, { corner(RADIUS) })
	Create("Frame", {
		Size = UDim2.new(1, 0, 0, RADIUS),
		BackgroundColor3 = THEME.Sidebar,
		BorderSizePixel = 0,
		Parent = sidebarBG,
	})
	Create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, RADIUS, 1, 0),
		BackgroundColor3 = THEME.Sidebar,
		BorderSizePixel = 0,
		Parent = sidebarBG,
	})

	-- scroll region (tab sidebars stack here, one visible at a time)
	local sidebarScroll = Create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -FOOTER_H),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 2,
		Parent = sidebarBG,
	}, { padXY(12, 12) })

	-- sidebar footer (config buttons + status)
	local footer = Create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, FOOTER_H),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = sidebarBG,
	}, { padXY(14, 0) })
	Create("Frame", {
		Position = UDim2.new(0, 14, 0, 0),
		Size = UDim2.new(1, -28, 0, 1),
		BackgroundColor3 = THEME.Stroke,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Parent = footer,
	})
	-- config icon buttons (folder, save)
	local cfgRow = Create("Frame", {
		Position = UDim2.new(0, 0, 0, 14),
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		Parent = footer,
	}, {
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local folderBtn = iconButton(cfgRow, "folder", "\u{1F4C1}", 36, { bg = THEME.Element, iconSize = 17 })
	local saveBtnFooter = iconButton(cfgRow, "save", "\u{1F4BE}", 36, { bg = THEME.Element, iconSize = 17 })
	folderBtn.MouseButton1Click:Connect(function()
		if type(opts.onFolder) == "function" then pcall(opts.onFolder)
		else NEMESIS.Notify({ title = "Configs", content = "Config folder", duration = 2 }) end
	end)
	saveBtnFooter.MouseButton1Click:Connect(function()
		if type(opts.onSave) == "function" then pcall(opts.onSave)
		else NEMESIS.Notify({ title = "Config", content = "Saved", duration = 2 }) end
	end)

	-- status row: dot + name (+ optional sub-line) ........ FPS
	local statusName = opts.game or opts.title or "NEMESIS"
	local statusSub = opts.status
	local hasSub = statusSub ~= nil and tostring(statusSub) ~= ""
	local rowMid = hasSub and -22 or -20

	local statusDot = Create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 1, rowMid),
		Size = UDim2.new(0, 9, 0, 9),
		BackgroundColor3 = THEME.Good,
		Parent = footer,
	}, { corner(5) })
	Create("TextLabel", {
		AnchorPoint = Vector2.new(0, hasSub and 0 or 0.5),
		Position = UDim2.new(0, 18, 1, hasSub and -34 or rowMid),
		Size = UDim2.new(1, -70, 0, 16),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		Text = tostring(statusName),
		TextColor3 = THEME.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = footer,
	})
	if hasSub then
		Create("TextLabel", {
			Position = UDim2.new(0, 18, 1, -18),
			Size = UDim2.new(1, -70, 0, 14),
			BackgroundTransparency = 1,
			Font = FONT,
			Text = tostring(statusSub),
			TextColor3 = THEME.SubText,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = footer,
		})
	end
	local fpsLabel = Create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 1, rowMid),
		Size = UDim2.new(0, 64, 0, 16),
		BackgroundTransparency = 1,
		Font = FONT_MED,
		Text = "— FPS",
		TextColor3 = THEME.SubText,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = footer,
	})

	-- divider between sidebar and content
	Create("Frame", {
		Position = UDim2.new(0, SIDEBAR_W, 0, 0),
		Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = THEME.Stroke,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Parent = body,
	})

	local content = Create("Frame", {
		Position = UDim2.new(0, SIDEBAR_W + 1, 0, 0),
		Size = UDim2.new(1, -(SIDEBAR_W + 1), 1, 0),
		BackgroundTransparency = 1,
		Parent = body,
	})

	-- content header: breadcrumb | config dropdown + save + 3-dot
	local CONTENT_PAD = 20
	local header = Create("Frame", {
		Position = UDim2.new(0, 0, 0, 14),
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		Parent = content,
	}, { padXY(CONTENT_PAD, 0) })
	local breadcrumb = Create("TextLabel", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(1, -180, 1, 0),
		BackgroundTransparency = 1,
		RichText = true,
		Font = FONT_MED,
		Text = "",
		TextColor3 = THEME.SubText,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})

	-- right cluster
	local more = iconButton(header, "more-vertical", "\u{22EE}", 30, {})
	more.AnchorPoint = Vector2.new(1, 0.5)
	more.Position = UDim2.new(1, 0, 0.5, 0)
	more.MouseButton1Click:Connect(function()
		if type(opts.onMenu) == "function" then pcall(opts.onMenu)
		else NEMESIS.Notify({ title = "Menu", content = "More options", duration = 2 }) end
	end)
	local saveBtn = iconButton(header, "save", "\u{1F4BE}", 30, { bg = accent, tint = THEME.Text, iconSize = 16 })
	saveBtn.AnchorPoint = Vector2.new(1, 0.5)
	saveBtn.Position = UDim2.new(1, -38, 0.5, 0)
	saveBtn.MouseButton1Click:Connect(function()
		if type(opts.onSave) == "function" then pcall(opts.onSave)
		else NEMESIS.Notify({ title = "Config", content = "Saved", duration = 2 }) end
	end)

	-- compact config dropdown ("HvH")
	local configs = opts.configs or { "Default" }
	local cfgValue = configs[1]
	local cfgField = Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -76, 0.5, 0),
		Size = UDim2.new(0, 132, 0, 30),
		BackgroundColor3 = THEME.Element,
		Text = "",
		AutoButtonColor = false,
		Parent = header,
	}, { corner(8), stroke(THEME.ElementStroke, 1, 0.35) })
	Create("TextLabel", {
		Name = "Val",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 0),
		Size = UDim2.new(1, -30, 1, 0),
		Font = FONT_MED,
		Text = tostring(cfgValue or ""),
		TextColor3 = THEME.Text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = cfgField,
	})
	local cfgArrow = Create("ImageLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0, 15, 0, 15),
		ImageColor3 = THEME.SubText,
		Parent = cfgField,
	})
	if not applyIcon(cfgArrow, resolveIcon("chevron-down")) then
		cfgArrow:Destroy()
		Create("TextLabel", {
			BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 14, 1, 0),
			Font = FONT_BOLD, Text = "\u{25BE}", TextColor3 = THEME.SubText, TextSize = 13, Parent = cfgField,
		})
	end
	local cfgList = Create("Frame", {
		Size = UDim2.new(0, 132, 0, 0),
		BackgroundColor3 = THEME.Element,
		Visible = false,
		ClipsDescendants = true,
		ZIndex = 40,
		Parent = screenGui,
	}, {
		corner(8), stroke(THEME.Stroke, 1, 0.2),
		Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
		padding(4),
	})
	local cfgOpen = false
	local function setCfg(name)
		cfgValue = name
		cfgField:FindFirstChild("Val").Text = tostring(name)
		if type(opts.onConfig) == "function" then pcall(opts.onConfig, name) end
	end
	for _, name in ipairs(configs) do
		local ob = Create("TextButton", {
			BackgroundColor3 = THEME.Element,
			Size = UDim2.new(1, 0, 0, 26),
			Font = FONT,
			Text = tostring(name),
			TextColor3 = THEME.Text,
			TextSize = 13,
			AutoButtonColor = false,
			ZIndex = 41,
			Parent = cfgList,
		}, { corner(6) })
		ob.MouseEnter:Connect(function() tween(ob, { BackgroundColor3 = THEME.ElementHover }, TI.EXP) end)
		ob.MouseLeave:Connect(function() tween(ob, { BackgroundColor3 = THEME.Element }, TI.EXP) end)
		ob.MouseButton1Click:Connect(function()
			setCfg(name)
			cfgOpen = false
			cfgList.Visible = false
		end)
	end
	cfgField.MouseButton1Click:Connect(function()
		cfgOpen = not cfgOpen
		if cfgOpen then
			pcall(function()
				local p = cfgField.AbsolutePosition
				cfgList.Position = UDim2.fromOffset(p.X, p.Y + 34)
			end)
			cfgList.Size = UDim2.new(0, 132, 0, math.min(#configs, 6) * 28 + 8)
			cfgList.Visible = true
		else
			cfgList.Visible = false
		end
		tween(cfgField, { BackgroundColor3 = cfgOpen and THEME.ElementHover or THEME.Element }, TI.FAST)
	end)

	-- pages host (each page body lives here; one visible at a time)
	local pagesHost = Create("Frame", {
		Position = UDim2.new(0, 0, 0, 58),
		Size = UDim2.new(1, 0, 1, -58),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = content,
	})

	-- open animation
	root.Size = UDim2.new(0, W, 0, 0)
	tween(root, { Size = UDim2.new(0, W, 0, H) }, TI.OPEN)

	--------------------------------------------------------------------
	-- Navigation state
	--------------------------------------------------------------------
	local Win = {}
	local tabs = {}
	local activeTab

	local function runSearch(text)
		local page = activeTab and activeTab.activePage
		if not page then return end
		text = string.lower(text or "")
		for _, d in ipairs(page.body:GetDescendants()) do
			local ok, tag = pcall(function() return d:GetAttribute("NemesisSearch") end)
			if ok and tag ~= nil then
				d.Visible = (text == "") or (string.find(string.lower(tag), text, 1, true) ~= nil)
			end
		end
	end

	searchBox:GetPropertyChangedSignal("Text"):Connect(function() runSearch(searchBox.Text) end)
	searchBox.Focused:Connect(function()
		if searchPillStroke then tween(searchPillStroke, { Color = accent }, TI.EXP) end
	end)
	searchBox.FocusLost:Connect(function()
		if searchPillStroke then tween(searchPillStroke, { Color = THEME.Stroke }, TI.EXP) end
	end)

	local function setCrumb(tab, page)
		local segs = { tab.name }
		if page and page.group then table.insert(segs, titleCase(page.group)) end
		if page then table.insert(segs, page.name) end
		local parts = {}
		for i, sname in ipairs(segs) do
			if i == #segs then
				parts[i] = string.format('<font color="#%s">%s</font>', accentHex, sname)
			else
				parts[i] = string.format('<font color="#%s">%s</font>', hexOf(THEME.SubText), sname)
			end
		end
		breadcrumb.Text = table.concat(parts, string.format('  <font color="#%s">\u{203A}</font>  ', hexOf(THEME.Faint)))
	end

	local function applyPageVisual(tab, page)
		for _, p in ipairs(tab.pages) do
			local on = (p == page)
			p.row.BackgroundColor3 = THEME.SidebarActive
			p.row.BackgroundTransparency = on and 0 or 1
			p.accentBar.Visible = on
			p.label.TextColor3 = on and accent or THEME.SubText
			if p.iconImg then p.iconImg.ImageColor3 = on and accent or THEME.SubText end
			p.active = on
		end
	end

	local function showPage(tab, page, animate)
		tab.activePage = page
		applyPageVisual(tab, page)
		if tab ~= activeTab then return end
		for _, p in ipairs(tab.pages) do p.body.Visible = (p == page) end
		if animate ~= false then
			page.body.Position = UDim2.new(0, 12, 0, 0)
			tween(page.body, { Position = UDim2.new(0, 0, 0, 0) }, TI.TAB)
		end
		setCrumb(tab, page)
		runSearch(searchBox.Text)
	end

	local function showTab(tab)
		activeTab = tab
		for _, t in ipairs(tabs) do
			t.sidebarFrame.Visible = (t == tab)
			t.button.TextColor3 = (t == tab) and accent or THEME.SubText
			t.underline.Visible = (t == tab)
			for _, p in ipairs(t.pages) do p.body.Visible = false end
		end
		local pg = tab.activePage or tab.pages[1]
		if pg then
			showPage(tab, pg, true)
		else
			setCrumb(tab, nil)
		end
	end

	--------------------------------------------------------------------
	-- Tab / Group / Page builders
	--------------------------------------------------------------------
	function Win.Tab(name)
		local tab = { name = tostring(name or "Tab"), pages = {}, activePage = nil }

		-- top-tab button + underline
		local btn = Create("TextButton", {
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Font = FONT_MED,
			Text = tostring(name or "Tab"),
			TextColor3 = THEME.SubText,
			TextSize = 15,
			AutoButtonColor = false,
			Parent = tabBar,
		}, { padXY(6, 0) })
		local underline = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -6, 0, 2),
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			Visible = false,
			Parent = btn,
		}, { corner(1) })
		tab.button = btn
		tab.underline = underline
		btn.MouseEnter:Connect(function()
			if activeTab ~= tab then tween(btn, { TextColor3 = THEME.Text }, TI.HOVER) end
		end)
		btn.MouseLeave:Connect(function()
			if activeTab ~= tab then tween(btn, { TextColor3 = THEME.SubText }, TI.HOVER) end
		end)
		btn.MouseButton1Click:Connect(function() showTab(tab) end)

		-- this tab's sidebar column
		tab.sidebarFrame = Create("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Visible = false,
			Parent = sidebarScroll,
		}, {
			Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) }),
		})

		local groupCount = 0
		local standaloneStarted = false

		local function makePage(pname, popts, groupName)
			popts = popts or {}
			local row = Create("TextButton", {
				Size = UDim2.new(1, 0, 0, 36),
				BackgroundColor3 = THEME.SidebarActive,
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Text = "",
				Parent = tab.sidebarFrame,
			}, { corner(8) })
			local accentBar = Create("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.new(0, 3, 0, 18),
				BackgroundColor3 = accent,
				BorderSizePixel = 0,
				Visible = false,
				Parent = row,
			}, { corner(2) })
			local iconImg
			local hasIcon = false
			if popts.icon then
				iconImg = Create("ImageLabel", {
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 14, 0.5, 0),
					Size = UDim2.new(0, 18, 0, 18),
					ImageColor3 = THEME.SubText,
					Parent = row,
				})
				hasIcon = applyIcon(iconImg, resolveIcon(popts.icon))
			end
			local label = Create("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, hasIcon and 42 or 16, 0, 0),
				Size = UDim2.new(1, hasIcon and -54 or -28, 1, 0),
				Font = FONT_MED,
				Text = tostring(pname or "Page"),
				TextColor3 = THEME.SubText,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = row,
			})
			local pageBody = Create("ScrollingFrame", {
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 3,
				ScrollBarImageColor3 = THEME.Stroke,
				CanvasSize = UDim2.new(0, 0, 0, 0),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				Visible = false,
				Parent = pagesHost,
			}, {
				Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 14) }),
				Create("UIPadding", {
					PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20),
					PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 16),
				}),
			})

			local page = {
				name = tostring(pname or "Page"),
				group = groupName,
				row = row, accentBar = accentBar, label = label, iconImg = hasIcon and iconImg or nil,
				body = pageBody, active = false,
			}
			table.insert(tab.pages, page)

			row.MouseEnter:Connect(function()
				if not page.active then tween(row, { BackgroundColor3 = THEME.SidebarHover, BackgroundTransparency = 0 }, TI.HOVER) end
			end)
			row.MouseLeave:Connect(function()
				if not page.active then tween(row, { BackgroundTransparency = 1 }, TI.HOVER) end
			end)
			row.MouseButton1Click:Connect(function() showPage(tab, page, true) end)

			-- page element API
			local Page = {}
			local defaultHost
			local function ensureDefault()
				if not defaultHost then defaultHost = makeSection(pageBody, accent, nil) end
				return defaultHost
			end
			function Page.Section(t) return makeSection(pageBody, accent, t) end
			Page.Button = function(a) return ensureDefault().Button(a) end
			Page.Toggle = function(a) return ensureDefault().Toggle(a) end
			Page.Slider = function(a) return ensureDefault().Slider(a) end
			Page.Dropdown = function(a) return ensureDefault().Dropdown(a) end
			Page.Input = function(a) return ensureDefault().Input(a) end
			Page.Keybind = function(a) return ensureDefault().Keybind(a) end
			Page.ColorPicker = function(a) return ensureDefault().ColorPicker(a) end
			Page.Paragraph = function(a) return ensureDefault().Paragraph(a) end
			Page.Label = function(a) return ensureDefault().Label(a) end

			-- first page becomes the tab's default
			if not tab.activePage then
				tab.activePage = page
				applyPageVisual(tab, page)
				if activeTab == tab then showPage(tab, page, false) end
			end
			return Page
		end

		local Tab = {}
		function Tab.Group(gname)
			groupCount = groupCount + 1
			local gh = Create("Frame", {
				Size = UDim2.new(1, 0, 0, groupCount > 1 and 34 or 24),
				BackgroundTransparency = 1,
				Parent = tab.sidebarFrame,
			})
			if groupCount > 1 then
				Create("Frame", {
					Position = UDim2.new(0, 12, 0, 6),
					Size = UDim2.new(1, -24, 0, 1),
					BackgroundColor3 = THEME.Stroke,
					BackgroundTransparency = 0.4,
					BorderSizePixel = 0,
					Parent = gh,
				})
			end
			Create("TextLabel", {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 14, 1, -3),
				Size = UDim2.new(1, -24, 0, 14),
				BackgroundTransparency = 1,
				Font = FONT_BOLD,
				Text = string.upper(tostring(gname or "Group")),
				TextColor3 = accent,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = gh,
			})
			local Group = {}
			function Group.Page(pname, popts) return makePage(pname, popts, gname) end
			return Group
		end

		function Tab.Page(pname, popts)
			if not standaloneStarted and groupCount > 0 then
				standaloneStarted = true
				Create("Frame", { -- gap before standalone items
					Size = UDim2.new(1, 0, 0, 10),
					BackgroundTransparency = 1,
					Parent = tab.sidebarFrame,
				})
			end
			return makePage(pname, popts, nil)
		end

		table.insert(tabs, tab)
		if #tabs == 1 then showTab(tab) end
		return Tab
	end

	--------------------------------------------------------------------
	-- Live FPS counter
	--------------------------------------------------------------------
	if RunService then
		pcall(function()
			local acc, frames = 0, 0
			RunService.Heartbeat:Connect(function(dt)
				dt = tonumber(dt) or (1 / 60)
				acc = acc + dt
				frames = frames + 1
				if acc >= 0.5 then
					if fpsLabel then fpsLabel.Text = tostring(math.floor(frames / acc + 0.5)) .. " FPS" end
					acc = 0; frames = 0
				end
			end)
		end)
	end

	--------------------------------------------------------------------
	-- resize grip (bottom-right)
	--------------------------------------------------------------------
	local minW = IS_MOBILE and 420 or 640
	local minH = 380
	local resizeGrip = Create("Frame", {
		Name = "ResizeGrip",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -8, 1, -8),
		Size = UDim2.new(0, 20, 0, 20),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = root,
	})
	for _, off in ipairs({ { 0, 0 }, { 6, 0 }, { 0, 6 } }) do
		Create("Frame", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -off[1], 1, -off[2]),
			Size = UDim2.new(0, 3, 0, 3),
			BackgroundColor3 = THEME.SubText,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			ZIndex = 6,
			Parent = resizeGrip,
		}, { corner(2) })
	end
	do
		local resizing = false
		local startInput, startW, startH
		resizeGrip.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				resizing = true
				startInput = input.Position
				startW, startH = W, H
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then resizing = false end
				end)
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if not resizing then return end
			if input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch then
				local vp = viewportSize()
				local delta = input.Position - startInput
				local maxW = math.max(minW, vp.X / scale - 40)
				local maxH = math.max(minH, vp.Y / scale - 40)
				W = math.clamp(startW + delta.X / scale, minW, maxW)
				H = math.clamp(startH + delta.Y / scale, minH, maxH)
				root.Size = UDim2.new(0, W, 0, H)
			end
		end)
	end

	--------------------------------------------------------------------
	-- minimize / restore, close, hide-key, mobile reopen
	--------------------------------------------------------------------
	local minimized = false
	local function setMinimized(m)
		minimized = m
		if resizeGrip then resizeGrip.Visible = not m end
		if m then
			topbarFiller.Visible = false
			topbarDivider.Visible = false
			tween(root, { Size = UDim2.new(0, W, 0, TOPBAR_H) }, TI.OPEN)
			setMinIcon("plus", "\u{002B}")
		else
			topbarFiller.Visible = true
			topbarDivider.Visible = true
			tween(root, { Size = UDim2.new(0, W, 0, H) }, TI.OPEN)
			setMinIcon("minus", "\u{2013}")
		end
	end
	function Win.Toggle(force)
		setMinimized((force == nil) and (not minimized) or (not force))
	end
	minBtn.MouseButton1Click:Connect(function() setMinimized(not minimized) end)

	function Win.Destroy()
		tween(root, { Size = UDim2.new(0, W, 0, 0) }, TI.SLIDE)
		task.delay(0.25, function() if root then root:Destroy() end end)
	end
	closeBtn.MouseButton1Click:Connect(function() Win.Destroy() end)

	local hidden = false
	local function setHidden(hide)
		hidden = hide
		if hide then
			tween(root, { Size = UDim2.new(0, W, 0, 0) }, TI.SLIDE)
			task.delay(0.2, function() if hidden then root.Visible = false end end)
		else
			root.Visible = true
			minimized = false
			tween(root, { Size = UDim2.new(0, W, 0, H) }, TI.OPEN)
		end
	end
	local toggleKey = opts.toggleKey or Enum.KeyCode.RightShift
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == toggleKey then
			setHidden(not hidden)
		elseif input.KeyCode == Enum.KeyCode.K then
			local ok, down = pcall(function()
				return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
					or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
			end)
			if ok and down then pcall(function() searchBox:CaptureFocus() end) end
		end
	end)

	if IS_MOBILE then
		local fab = Create("TextButton", {
			Name = "Reopen",
			Position = UDim2.new(0, 12, 0, 12),
			Size = UDim2.new(0, 44, 0, 44),
			BackgroundColor3 = accent,
			Font = FONT_BOLD,
			Text = "N",
			TextColor3 = THEME.Text,
			TextSize = 20,
			Parent = screenGui,
		}, { corner(22), stroke(THEME.Stroke, 1, 0.4) })
		makeDraggable(fab, fab)
		fab.MouseButton1Click:Connect(function() setHidden(not hidden) end)
	end

	Win.Instance = root
	Win.Notify = NEMESIS.Notify
	return Win
end

----------------------------------------------------------------------
return NEMESIS
