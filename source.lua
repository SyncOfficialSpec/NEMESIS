--[[
	NEMESIS UI Library  (v2.0)
	A Roblox/Luau UI library for script executors — desktop cheat-menu layout.

	Load:
		local NEMESIS = loadstring(game:HttpGet("https://raw.githubusercontent.com/DiabloPaidProjects/NEMESIS/main/source.lua"))()

	v2.0 redesign (desktop-first; still scales down on touch):
		- Centered segmented top tab bar (active = flush filled segment + dividers, smooth)
		- Grouped left sidebar of sub-tabs with boxed, collapsible group headers
		- Breadcrumb in the content header
		- Collapsible content Sections holding inline rows (label left / control right)
		- One-pager column grid for panels; recolorable brand logo

	API (dot-style, hierarchy Window -> Tab -> Group -> Page -> Section -> controls):
		local Win     = NEMESIS.Window({ title = "NEMESIS" })
		local Combat  = Win.Tab("Combat")
		local Aimbot  = Combat.Group("AIMBOT")
		local General = Aimbot.Page("General", { icon = "crosshair" })
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
-- versioned path: bump the filename (URL + on-disk cache) whenever the logo
-- changes, so neither the GitHub CDN nor the executor serves a stale image
-- grayscale logo so ImageColor3 can tint it to any hue at runtime
local LOGO_URL = "https://raw.githubusercontent.com/DiabloPaidProjects/NEMESIS/main/assets/nemesis_logo_v4.png"
local LOGO_FILE = "nemesis_logo_v4.png"
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
				-- a Font object (e.g. Inter) goes on FontFace, not the Font enum prop
				if k == "Font" and typeof(v) == "Font" then
					inst.FontFace = v
				else
					inst[k] = v
				end
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

-- Inter font family (medium-weight base, per request)
local INTER = "rbxasset://fonts/families/Inter.json"
local FONT = Font.new(INTER, Enum.FontWeight.Medium)
local FONT_MED = Font.new(INTER, Enum.FontWeight.Medium)
local FONT_BOLD = Font.new(INTER, Enum.FontWeight.Bold)

-- Inline-row layout metrics (scaled by the window's UIScale at runtime)
local ROW_H = 38          -- height of a setting row (compact)
local ROW_PAD = 14        -- horizontal inset inside a row / section
-- Right-side control widths are a FRACTION of the row, so they fit any column
-- count (1 / 2 / 3) and resize. Label takes the complementary fraction.
local FIELD_FRAC = 0.5    -- dropdown / keybind / input field width fraction
local SLIDER_FRAC = 0.55  -- slider (value + track) cluster width fraction

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
-- smooth & snappy easing set: short Quint/Quad Out glides that read as fluid
-- but stay responsive (hover is fast; no sluggish 0.6s curves anywhere)
local TI = {
	EXP = TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),       -- fills, flashes
	FAST = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),     -- toggle, arrows, sub-tab
	TAB = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),      -- minimize, tab switch, page slide
	EXPAND = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),   -- dropdown / panels / collapse
	POP = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),       -- slider / toggle knob pop
	SCROLL = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),    -- smooth wheel scroll
}
TI.OPEN = TI.TAB
TI.HOVER = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)      -- responsive hover
TI.SLIDE = TI.EXPAND
TI.NOTIFY = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)    -- notification glide

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

-- Smooth, eased mouse-wheel scrolling for a ScrollingFrame (desktop). Native
-- scrolling stays on for touch; here we drive CanvasPosition with a tween.
local SCROLL_STEP = 90
local function smoothScroll(sf)
	if IS_MOBILE then return end
	sf.ScrollingEnabled = false -- we own the wheel; avoids fighting native steps
	local goal = 0
	sf.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			local maxY = 0
			pcall(function() maxY = math.max(0, sf.AbsoluteCanvasSize.Y - sf.AbsoluteWindowSize.Y) end)
			goal = math.clamp(goal - input.Position.Z * SCROLL_STEP, 0, maxY)
			tween(sf, { CanvasPosition = Vector2.new(0, goal) }, TI.SCROLL)
		end
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
		TextSize = 16,
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
		TextSize = 15,
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
-- Rows live inside a Section's body, separated by spacing only (no divider lines).
local function newRow(parent, height)
	return Create("Frame", {
		BackgroundColor3 = THEME.Group,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height or ROW_H),
		Parent = parent,
	}, { padXY(ROW_PAD, 0) })
end

-- Left-hand label (single line by default; optional muted description line).
-- reserveScale + reservePx clear room on the right for the control:
-- label width = (1 - reserveScale) scale, minus reservePx pixels.
local function rowText(parent, text, desc, reserveScale, reservePx)
	reserveScale = reserveScale or 0
	reservePx = reservePx or 48
	local lblSize = UDim2.new(1 - reserveScale, -reservePx, 1, 0)
	tagSearch(parent, (desc and desc ~= "") and (tostring(text) .. " " .. tostring(desc)) or text)
	if desc and desc ~= "" then
		local col = Create("Frame", {
			BackgroundTransparency = 1,
			Size = lblSize,
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
			Size = UDim2.new(1, 0, 0, 15),
			Font = FONT_MED,
			Text = tostring(text or ""),
			TextColor3 = THEME.Text,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = col,
		})
		Create("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 12),
			Font = FONT,
			Text = tostring(desc),
			TextColor3 = THEME.SubText,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = col,
		})
		return col
	end
	return Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = lblSize,
		Font = FONT_MED,
		Text = tostring(text or ""),
		TextColor3 = THEME.Text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = parent,
	})
end

-- A right-aligned rounded field box (width = fraction of the row).
local function fieldBox(row, frac)
	return Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(frac or FIELD_FRAC, 0, 0, 28),
		BackgroundColor3 = THEME.Element,
		Parent = row,
	}, { corner(8), stroke(THEME.ElementStroke, 1, 0.2) })
end

-- Make any TextBox grow its (offset-width) field to fit the typed text, between
-- minW..maxW, then clip so the front scrolls off instead of spilling outside.
-- Sizes from the real text only (an empty box stays at minW; placeholder ignored).
local function growBox(field, box, minW, maxW, pad)
	field.ClipsDescendants = true
	local function fit()
		local tb = 0
		if box.Text ~= "" then pcall(function() tb = box.TextBounds.X end) end
		local y = field.Size.Y
		field.Size = UDim2.new(0, math.clamp(tb + pad, minW, maxW), y.Scale, y.Offset)
	end
	box:GetPropertyChangedSignal("Text"):Connect(fit)
	box:GetPropertyChangedSignal("TextBounds"):Connect(fit)
	fit()
	return fit
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
		TextSize = 15,
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
		Create("UIPadding", {
			PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16),
			PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 24),
		}),
		Create("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }),
		Create("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 18),
			Font = FONT_BOLD,
			Text = tostring(opts.title or "Title"),
			TextColor3 = THEME.Text,
			TextSize = 16,
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
			TextSize = 15,
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
	rowText(row, opts.text, opts.desc, 0, 90)
	local chip = Create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 70, 0, 28),
		BackgroundColor3 = THEME.Element,
		Font = FONT_MED,
		Text = tostring(opts.button or "Run"),
		TextColor3 = accent,
		TextSize = 15,
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
	local row = newRow(parent, opts.desc and 50 or ROW_H)
	rowText(row, opts.text, opts.desc, 0, 32)

	-- neverlose-style checkbox: a dark rounded box whose accent-gradient fill
	-- grows in with a Back ease + a checkmark, and scales up on hover
	local box = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 20, 0, 20),
		BackgroundColor3 = THEME.Element,
		Parent = row,
	}, { corner(6), stroke(THEME.ElementStroke, 1, 0.35) })
	-- fill matches the box corner and never exceeds it, so its corners stay
	-- curved all through the grow animation (no square clipping)
	local fill = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = box,
	}, {
		corner(6),
		Create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(accent, accent:Lerp(Color3.fromRGB(255, 255, 255), 0.35)),
		}),
	})
	local check
	local checkSpec = resolveIcon("check")
	if checkSpec then
		check = Create("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0, 12, 0, 12),
			BackgroundTransparency = 1,
			ImageColor3 = Color3.fromRGB(255, 255, 255),
			ImageTransparency = 1,
			Parent = box,
		})
		applyIcon(check, checkSpec)
	end
	local click = Create("TextButton", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, ROW_PAD * 2, 1, 0),
		Position = UDim2.new(0, -ROW_PAD, 0, 0),
		Text = "",
		Parent = row,
	})

	local control = {}
	local function render(animate)
		local fillInfo = animate and TI.POP or TweenInfo.new(0)
		local checkInfo = animate and TI.FAST or TweenInfo.new(0)
		tween(fill, {
			Size = state and UDim2.new(1, 0, 1, 0) or UDim2.new(0, 0, 0, 0),
			BackgroundTransparency = state and 0 or 1,
		}, fillInfo)
		if check then
			tween(check, { ImageTransparency = state and 0 or 1 }, checkInfo)
		end
	end
	click.MouseEnter:Connect(function() tween(box, { Size = UDim2.new(0, 22, 0, 22) }, TI.HOVER) end)
	click.MouseLeave:Connect(function() tween(box, { Size = UDim2.new(0, 20, 0, 20) }, TI.HOVER) end)
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
	rowText(row, opts.text, opts.desc, SLIDER_FRAC, 12)

	local cluster = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(SLIDER_FRAC, 0, 1, 0),
		BackgroundTransparency = 1,
		Parent = row,
	})
	-- editable: click the number to type an exact value
	local valueLabel = Create("TextBox", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.new(0, 52, 0, 18),
		Font = FONT_MED,
		Text = fmt(value),
		TextColor3 = THEME.Text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
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
	}, {
		corner(3),
		Create("UIGradient", {
			Color = ColorSequence.new(accent, accent:Lerp(Color3.fromRGB(255, 255, 255), 0.35)),
		}),
	})
	local handle = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new((value - min) / (max - min), 0, 0.5, 0),
		Size = UDim2.new(0, 14, 0, 14),
		BackgroundColor3 = accent,
		ZIndex = 2,
		Parent = bar,
	}, { corner(7), stroke(THEME.Background, 2, 0) })
	-- tall invisible grab strip so the thin bar is easy to drag anywhere
	local hit = Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(1, -56, 0, 24),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 3,
		Parent = cluster,
	})

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

	bindBarDrag(hit, function(rel) setFromAlpha(rel, true, true) end)
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			tween(handle, { Size = UDim2.new(0, 17, 0, 17) }, TI.POP)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			tween(handle, { Size = UDim2.new(0, 14, 0, 14) }, TI.POP)
		end
	end)
	-- type an exact value into the number box
	valueLabel.FocusLost:Connect(function()
		local num = tonumber((valueLabel.Text:gsub("[^%d%.%-]", "")))
		if num then control.Set(num) else valueLabel.Text = fmt(value) end
	end)

	if opts.flag then NEMESIS.Flags[opts.flag] = value end
	return control
end

-- ===== shared dropdown overlay (neverlose-style floating panels) =====
local _ddCurrent = nil   -- handle of the currently open dropdown (one at a time)
local function closeOpenDropdown()
	if _ddCurrent then _ddCurrent.close() end
end
local _ddLayers = setmetatable({}, { __mode = "k" })  -- ScreenGui -> overlay frame
local function dropdownLayer(field)
	local sg = field:FindFirstAncestorWhichIsA("ScreenGui")
	if not sg then return nil end
	local layer = _ddLayers[sg]
	if not layer or not layer.Parent then
		layer = Create("Frame", {
			Name = "NemesisDropdownLayer",
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 50000,
			Parent = sg,
		})
		_ddLayers[sg] = layer
	end
	return layer
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
	rowText(row, opts.text, opts.desc, FIELD_FRAC, 16)
	local field = fieldBox(row)

	local current = Create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 0),
		Size = UDim2.new(1, -32, 1, 0),
		Font = FONT,
		Text = "...",
		TextColor3 = THEME.Text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = field,
	})
	-- arrow only (no liner / divider before it)
	local arrowIsImage = false
	local arrow
	local chevSpec = resolveIcon("chevron-down")
	if chevSpec then
		arrowIsImage = true
		arrow = Create("ImageLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -9, 0.5, 0),
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
			TextSize = 14,
			Parent = field,
		})
	end
	local arrowColorProp = arrowIsImage and "ImageColor3" or "TextColor3"

	-- floating panel (neverlose style): a separate overlay that fades in below
	-- the field and tracks its position; it does NOT push surrounding content
	local PANEL_MAXH = 200   -- logical max height before the list scrolls
	local OPT_H = 28         -- logical option row height
	local panelScale = Create("UIScale", { Scale = 1 })
	local panelStroke = stroke(THEME.ElementStroke, 1, 1)
	local panel = Create("Frame", {
		Name = "NemesisDropdown",
		BackgroundColor3 = THEME.Element,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 50001,
	}, {
		corner(8),
		panelStroke,
		panelScale,
	})
	local holder = Create("ScrollingFrame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.new(1, -12, 1, -12),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = accent,
		ScrollBarImageTransparency = 1,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 50002,
		Parent = panel,
	}, {
		Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) }),
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

	local FADE = TweenInfo.new(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

	-- option rows (neverlose style: accent dot on the left + the text slides
	-- right when selected; dimmed text when not)
	local optionButtons = {}
	local function rebuildOptions()
		for _, rec in ipairs(optionButtons) do rec.btn:Destroy() end
		optionButtons = {}
		for _, v in ipairs(options) do
			local ob = Create("TextButton", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, OPT_H),
				AutoButtonColor = false,
				Text = "",
				ZIndex = 50003,
				Parent = holder,
			})
			local dot = Create("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 8, 0.5, 0),
				Size = UDim2.new(0, 6, 0, 6),
				BackgroundColor3 = accent,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 50004,
				Parent = ob,
			}, {
				corner(3),
				Create("UIGradient", {
					Rotation = 90,
					Color = ColorSequence.new(accent, accent:Lerp(Color3.fromRGB(255, 255, 255), 0.35)),
				}),
			})
			local olabel = Create("TextLabel", {
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 8, 0.5, 0),
				Size = UDim2.new(1, -16, 0, 17),
				Font = FONT,
				Text = tostring(v),
				TextColor3 = THEME.Text,
				TextTransparency = 1,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 50004,
				Parent = ob,
			})
			local function apply(animate, visible)
				local on = multi and selected[v] or (single == v)
				local info = animate and FADE or TweenInfo.new(0)
				tween(dot, { BackgroundTransparency = (visible and on) and 0 or 1 }, info)
				tween(olabel, {
					TextTransparency = visible and (on and 0 or 0.35) or 1,
					Position = on and UDim2.new(0, 18, 0.5, 0) or UDim2.new(0, 8, 0.5, 0),
				}, info)
			end
			apply(false, false)
			ob.MouseEnter:Connect(function()
				local on = multi and selected[v] or (single == v)
				if open and not on then tween(olabel, { TextTransparency = 0.1 }, TI.HOVER) end
			end)
			ob.MouseLeave:Connect(function()
				local on = multi and selected[v] or (single == v)
				if open and not on then tween(olabel, { TextTransparency = 0.35 }, TI.HOVER) end
			end)
			ob.MouseButton1Click:Connect(function()
				if multi then selected[v] = not selected[v] else single = v end
				for _, rec in ipairs(optionButtons) do rec.apply(true, true) end
				refreshLabel()
				fire()
				if not multi then control.Toggle(false) end
			end)
			-- keep the apply fn in a plain Lua record (cannot store fields on Instances)
			table.insert(optionButtons, { btn = ob, apply = apply })
		end
	end

	-- open / close (fades the floating panel; tracks the field each frame)
	local trackConn
	local function fadePanel(opening)
		tween(panel, { BackgroundTransparency = opening and 0 or 1 }, FADE)
		tween(panelStroke, { Transparency = opening and 0.15 or 1 }, FADE)
		tween(holder, { ScrollBarImageTransparency = opening and 0.25 or 1 }, FADE)
		for _, rec in ipairs(optionButtons) do rec.apply(true, opening) end
	end
	local function track()
		local fp, fs = field.AbsolutePosition, field.AbsoluteSize
		local s = fs.Y / 28
		if s <= 0 then s = 1 end
		panelScale.Scale = s
		local logicalH = math.clamp(#options * (OPT_H + 3) + 9, OPT_H + 12, PANEL_MAXH)
		panel.Size = UDim2.fromOffset(fs.X / s, logicalH)
		panel.Position = UDim2.fromOffset(fp.X, fp.Y + fs.Y + 6)
	end
	local ddHandle = {}
	local function setOpen(b)
		if b == open then return end
		open = b
		tween(arrow, { Rotation = open and 180 or 0, [arrowColorProp] = open and accent or THEME.SubText }, TI.FAST)
		tween(field, { BackgroundColor3 = open and THEME.ElementHover or THEME.Element }, TI.FAST)
		if open then
			if _ddCurrent and _ddCurrent ~= ddHandle then _ddCurrent.close() end
			_ddCurrent = ddHandle
			local layer = dropdownLayer(field)
			if layer then panel.Parent = layer end
			panel.Visible = true
			track()
			if trackConn then trackConn:Disconnect() end
			trackConn = RunService.RenderStepped:Connect(track)
			fadePanel(true)
		else
			if _ddCurrent == ddHandle then _ddCurrent = nil end
			if trackConn then trackConn:Disconnect(); trackConn = nil end
			fadePanel(false)
			task.delay(0.18, function() if not open then panel.Visible = false end end)
		end
	end
	ddHandle.close = function() setOpen(false) end

	function control.Toggle(force)
		setOpen((force == nil) and (not open) or force)
	end
	function control.Set(v)
		if multi then
			selected = {}
			if type(v) == "table" then for _, x in ipairs(v) do selected[x] = true end end
		else
			single = v
		end
		for _, rec in ipairs(optionButtons) do rec.apply(open, open) end
		refreshLabel(); fire()
	end
	function control.Get() return multi and listValues() or single end
	function control.SetOptions(newOptions)
		options = newOptions or {}
		rebuildOptions(); refreshLabel()
		if open then track() end
	end

	local click = Create("TextButton", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, ROW_PAD * 2, 1, 0),
		Position = UDim2.new(0, -ROW_PAD, 0, 0),
		Text = "",
		Parent = row,
	})
	click.MouseButton1Click:Connect(function() control.Toggle() end)
	click.MouseEnter:Connect(function()
		if not open then tween(arrow, { [arrowColorProp] = THEME.Text }, TI.HOVER) end
	end)
	click.MouseLeave:Connect(function()
		if not open then tween(arrow, { [arrowColorProp] = THEME.SubText }, TI.HOVER) end
	end)

	rebuildOptions(); refreshLabel()
	if opts.flag then NEMESIS.Flags[opts.flag] = control.Get() end
	return control
end
function Elements.Input(parent, accent, opts)
	opts = opts or {}
	local row = newRow(parent, ROW_H)
	rowText(row, opts.text, opts.desc, FIELD_FRAC, 16)
	-- Rayfield-style: starts small, grows with the text up to a cap, then clips
	-- (past the cap the front scrolls off instead of spilling outside the field)
	local MIN_W, MAX_W = 84, 220
	local field = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, MIN_W, 0, 28),
		BackgroundColor3 = THEME.Element,
		ClipsDescendants = true,
		Parent = row,
	}, { corner(8), stroke(THEME.ElementStroke, 1, 0.2) })
	local fieldStroke = field:FindFirstChildOfClass("UIStroke")
	-- inner clip rect == the bordered field, so the TextBox can never paint past it
	local clip = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		ClipsDescendants = true,
		Parent = field,
	})
	local box = Create("TextBox", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 0),
		Size = UDim2.new(1, -20, 1, 0),
		Font = FONT,
		PlaceholderText = tostring(opts.placeholder or "..."),
		Text = tostring(opts.default or ""),
		TextColor3 = THEME.Text,
		PlaceholderColor3 = THEME.SubText,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = opts.clearOnFocus and true or false,
		Parent = clip,
	})
	growBox(field, box, MIN_W, MAX_W, 22)

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
	rowText(row, opts.text, opts.desc, FIELD_FRAC, 16)
	local field = fieldBox(row)
	local fieldStroke = field:FindFirstChildOfClass("UIStroke")
	local btn = Create("TextButton", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Font = FONT_MED,
		Text = keyDisplay(key),
		TextColor3 = THEME.Text,
		TextSize = 15,
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
	-- two colour slots: slot 1 is the colour (single mode) / first gradient colour,
	-- slot 2 is the second gradient colour. each holds h,s,v + alpha.
	local function slotFrom(color, a)
		local hh, ss, vv = (color or Color3.fromRGB(255, 255, 255)):ToHSV()
		return { h = hh, s = ss, v = vv, alpha = tonumber(a) or 0 }
	end
	local slots = {
		slotFrom(opts.default, opts.transparency),
		slotFrom(opts.gradientDefault or Color3.fromRGB(0, 0, 0), opts.transparency2 or opts.transparency),
	}
	local isGradient = opts.gradient and true or false
	local active = 1
	local saved = {}
	local function cur() return slots[active] end
	local function slotColor(i) return Color3.fromHSV(slots[i].h, slots[i].s, slots[i].v) end

	local row = newRow(parent, ROW_H)
	rowText(row, opts.text, opts.desc, 0, 76)

	local sw1 = Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 40, 0, 22), BackgroundColor3 = slotColor(1),
		Text = "", AutoButtonColor = false, Parent = row,
	}, { corner(6), stroke(THEME.Stroke, 1, 0.2) })
	local sw2 = Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -26, 0.5, 0),
		Size = UDim2.new(0, 22, 0, 22), BackgroundColor3 = slotColor(2),
		Text = "", AutoButtonColor = false, Visible = false, Parent = row,
	}, { corner(6), stroke(THEME.Stroke, 1, 0.2) })
	local function layoutSwatches()
		if isGradient then
			sw2.Visible = true
			sw1.Size = UDim2.new(0, 22, 0, 22)
			sw2.Position = UDim2.new(1, -26, 0.5, 0)
		else
			sw2.Visible = false
			sw1.Size = UDim2.new(0, 40, 0, 22)
		end
	end
	layoutSwatches()

	local control = {}
	local panel, svBase, svDot, hueDot, alphaBar, alphaDot, hexBox, pctLabel
	local headSwatch, headHex, slotRow, setModeVisual, setSlotVisual, rebuildSaved
	local cpScale
	local backdrop, openPanel
	local cpHandle = {}
	local opened = false

	local function commit()
		sw1.BackgroundColor3 = slotColor(1)
		sw2.BackgroundColor3 = slotColor(2)
		local value = isGradient and { slotColor(1), slotColor(2) } or slotColor(1)
		local al = isGradient and { slots[1].alpha, slots[2].alpha } or slots[1].alpha
		if opts.flag then NEMESIS.Flags[opts.flag] = value end
		if type(opts.callback) == "function" then pcall(opts.callback, value, al) end
	end
	local function syncUI()
		local c = cur()
		local col = Color3.fromHSV(c.h, c.s, c.v)
		if active == 1 then sw1.BackgroundColor3 = col else sw2.BackgroundColor3 = col end
		if svBase then svBase.BackgroundColor3 = Color3.fromHSV(c.h, 1, 1) end
		if svDot then svDot.Position = UDim2.new(c.s, 0, 1 - c.v, 0) end
		if hueDot then hueDot.Position = UDim2.new(c.h, 0, 0.5, 0) end
		if alphaBar then alphaBar.BackgroundColor3 = col end
		if alphaDot then alphaDot.Position = UDim2.new(1 - c.alpha, 0, 0.5, 0) end
		if hexBox then hexBox.Text = "#" .. hexOf(col) end
		if headSwatch then headSwatch.BackgroundColor3 = col end
		if headHex then headHex.Text = "#" .. hexOf(col) end
		if pctLabel then pctLabel.Text = tostring(math.floor((1 - c.alpha) * 100 + 0.5)) .. "%" end
	end
	local function setColor(col)
		local c = cur()
		c.h, c.s, c.v = col:ToHSV()
		syncUI(); commit()
	end

	-- a small two-option segmented control (returns paint fn)
	local function segmented(width, lOpt, rOpt, onPick)
		local frame = Create("Frame", {
			Size = UDim2.new(0, width, 0, 22), BackgroundColor3 = THEME.Element,
			Parent = nil,
		}, { corner(7), stroke(THEME.ElementStroke, 1, 0.4) })
		local sel = 1
		local btns = {}
		for i, label in ipairs({ lOpt, rOpt }) do
			local b = Create("TextButton", {
				Size = UDim2.new(0.5, -3, 1, -6), Position = UDim2.new((i - 1) * 0.5, i == 1 and 3 or 0, 0, 3),
				BackgroundColor3 = accent, BackgroundTransparency = 1, AutoButtonColor = false,
				Font = FONT_MED, Text = label, TextColor3 = THEME.SubText, TextSize = 13,
				Parent = frame,
			}, { corner(5) })
			btns[i] = b
			b.MouseButton1Click:Connect(function() sel = i; onPick(i) end)
		end
		local function paint()
			for i, b in ipairs(btns) do
				local on = (i == sel)
				tween(b, { BackgroundTransparency = on and 0.1 or 1 }, TI.FAST)
				tween(b, { TextColor3 = on and Color3.new(1, 1, 1) or THEME.SubText }, TI.FAST)
			end
		end
		paint()
		return frame, function(i) sel = i; paint() end
	end

	local function buildPanel()
		backdrop = Create("TextButton", {
			Name = "ColorBackdrop", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
			AutoButtonColor = false, Text = "", Visible = false, ZIndex = 50000, Parent = screenGui,
		})
		backdrop.MouseButton1Click:Connect(function() openPanel(false) end)
		local panelScale = Create("UIScale", { Scale = 1 })
		panel = Create("CanvasGroup", {
			Name = "ColorPanel", Size = UDim2.new(0, 300, 0, 432), BackgroundColor3 = THEME.Group,
			GroupTransparency = 1, Visible = false, ZIndex = 50001, Parent = screenGui,
		}, {
			corner(14), stroke(THEME.ElementStroke, 1, 0.35), panelScale,
		})
		cpScale = panelScale
		-- absorb taps on empty panel areas so they don't fall through to the backdrop
		Create("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, AutoButtonColor = false, Text = "", ZIndex = 1, Parent = panel })
		local content = Create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, ZIndex = 2, Parent = panel }, {
			padding(10),
			Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		})

		-- header: live swatch + hex + mode toggle
		local head = Create("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, LayoutOrder = 1, Parent = content })
		headSwatch = Create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(0, 22, 0, 22),
			BackgroundColor3 = slotColor(active), Parent = head,
		}, { corner(6), stroke(THEME.Stroke, 1, 0.3) })
		headHex = Create("TextLabel", {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 30, 0.5, 0), Size = UDim2.new(0, 90, 1, 0),
			BackgroundTransparency = 1, Font = FONT_BOLD, Text = "#FFFFFF", TextColor3 = THEME.Text, TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left, Parent = head,
		})
		local modeSeg
		modeSeg, setModeVisual = segmented(120, "Single", "Gradient", function(i)
			isGradient = (i == 2)
			setModeVisual(i)
			if not isGradient then active = 1 end
			slotRow.Visible = isGradient
			slotRow.Size = UDim2.new(1, 0, 0, isGradient and 22 or 0)
			layoutSwatches()
			syncUI(); commit()
		end)
		modeSeg.AnchorPoint = Vector2.new(1, 0.5)
		modeSeg.Position = UDim2.new(1, 0, 0.5, 0)
		modeSeg.Parent = head
		setModeVisual(isGradient and 2 or 1)

		-- slot selector (gradient only): First / Second
		local slotSeg
		slotSeg, setSlotVisual = segmented(160, "First", "Second", function(i)
			active = i; setSlotVisual(i); syncUI()
		end)
		slotRow = Create("Frame", { Size = UDim2.new(1, 0, 0, isGradient and 22 or 0), BackgroundTransparency = 1, LayoutOrder = 2, Visible = isGradient, Parent = content })
		slotSeg.AnchorPoint = Vector2.new(0.5, 0.5)
		slotSeg.Position = UDim2.new(0.5, 0, 0.5, 0)
		slotSeg.Parent = slotRow

		-- SV square (matched 8px corners on every layer + a clean boundary stroke)
		local sv = Create("Frame", { Size = UDim2.new(1, 0, 0, 150), BackgroundColor3 = Color3.fromHSV(cur().h, 1, 1), LayoutOrder = 3, Parent = content }, { corner(8), stroke(THEME.ElementStroke, 1, 0.4) })
		svBase = sv
		Create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), Parent = sv }, { corner(8), Create("UIGradient", { Transparency = numSeq(0, 1) }) })
		Create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), Parent = sv }, { corner(8), Create("UIGradient", { Rotation = 90, Transparency = numSeq(1, 0) }) })
		-- neverlose-style: transparent centre (shows the picked colour) + white ring
		svDot = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(cur().s, 0, 1 - cur().v, 0), Size = UDim2.new(0, 13, 0, 13),
			BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, ZIndex = 52, Parent = sv,
		}, { corner(7), stroke(Color3.new(1, 1, 1), 2, 0) })
		local svHit = Create("TextButton", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Text = "", ZIndex = 53, Parent = sv })
		do
			local dragging = false
			local function upd(input)
				local rx = math.clamp((input.Position.X - sv.AbsolutePosition.X) / sv.AbsoluteSize.X, 0, 1)
				local ry = math.clamp((input.Position.Y - sv.AbsolutePosition.Y) / sv.AbsoluteSize.Y, 0, 1)
				cur().s = rx; cur().v = 1 - ry
				syncUI(); commit()
			end
			svHit.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = true; upd(input) end
			end)
			UserInputService.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
			end)
			UserInputService.InputChanged:Connect(function(input)
				if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then upd(input) end
			end)
		end

		local hue = Create("Frame", { Size = UDim2.new(1, 0, 0, 8), LayoutOrder = 4, Parent = content }, { corner(4), Create("UIGradient", { Color = hueSequence() }) })
		hueDot = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(cur().h, 0, 0.5, 0), Size = UDim2.new(0, 12, 0, 12), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 52, Parent = hue }, { corner(6), stroke(Color3.new(0, 0, 0), 1, 0.35) })
		bindBarDrag(hue, function(rel) cur().h = rel; syncUI(); commit() end)

		alphaBar = Create("Frame", { Size = UDim2.new(1, 0, 0, 8), BackgroundColor3 = slotColor(active), LayoutOrder = 5, Parent = content }, { corner(4), Create("UIGradient", { Transparency = numSeq(0, 1) }) })
		alphaDot = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1 - cur().alpha, 0, 0.5, 0), Size = UDim2.new(0, 12, 0, 12), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 52, Parent = alphaBar }, { corner(6), stroke(Color3.new(0, 0, 0), 1, 0.35) })
		bindBarDrag(alphaBar, function(rel) cur().alpha = 1 - rel; syncUI(); commit() end)

		-- preset palette + saved colours (one grid; presets first, then saved, then +)
		local PRESETS = {
			Color3.fromRGB(255, 71, 71), Color3.fromRGB(255, 138, 61), Color3.fromRGB(255, 210, 40),
			Color3.fromRGB(90, 255, 120), Color3.fromRGB(60, 220, 255), Color3.fromRGB(90, 140, 255),
			Color3.fromRGB(150, 85, 255), Color3.fromRGB(255, 90, 200), Color3.fromRGB(255, 255, 255),
			Color3.fromRGB(160, 160, 170), Color3.fromRGB(60, 60, 70), Color3.fromRGB(15, 15, 20),
		}
		-- scrollable so presets + any number of saved colours fit (right-click a
		-- saved colour to remove it)
		local gridWrap = Create("ScrollingFrame", {
			Size = UDim2.new(1, 0, 0, 102), BackgroundTransparency = 1, BorderSizePixel = 0,
			ScrollBarThickness = 3, ScrollBarImageColor3 = accent, ScrollBarImageTransparency = 0.3,
			CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y, LayoutOrder = 6, Parent = content,
		})
		local grid = Create("Frame", { Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = gridWrap }, {
			Create("UIGridLayout", { CellSize = UDim2.new(0, 40, 0, 30), CellPadding = UDim2.new(0, 6, 0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local function swatchTile(color, order, kind, savedIdx)
			local t = Create("TextButton", {
				BackgroundColor3 = (kind == "add") and THEME.Element or color, AutoButtonColor = false,
				Text = (kind == "add") and "+" or "", Font = FONT_BOLD, TextColor3 = THEME.SubText, TextSize = 18,
				LayoutOrder = order, Parent = grid,
			}, { corner(6), stroke(THEME.ElementStroke, 1, 0.4) })
			t.MouseButton1Click:Connect(function()
				if kind == "add" then
					table.insert(saved, slotColor(active)); rebuildSaved()
				else
					setColor(color)
				end
			end)
			if kind == "saved" then
				t.MouseButton2Click:Connect(function() table.remove(saved, savedIdx); rebuildSaved() end)
			end
			return t
		end
		rebuildSaved = function()
			for _, c in ipairs(grid:GetChildren()) do
				if c:IsA("TextButton") then c:Destroy() end
			end
			local order = 0
			for _, c in ipairs(PRESETS) do order = order + 1; swatchTile(c, order, "preset") end
			for i, c in ipairs(saved) do order = order + 1; swatchTile(c, order, "saved", i) end
			order = order + 1; swatchTile(nil, order, "add")
		end
		rebuildSaved()

		-- Custom hex
		local hexRow = Create("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = 7, Parent = content })
		Create("TextLabel", {
			BackgroundTransparency = 1, Size = UDim2.new(0, 60, 1, 0), Font = FONT_BOLD, Text = "Custom:",
			TextColor3 = THEME.SubText, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Parent = hexRow,
		})
		hexBox = Create("TextBox", {
			Position = UDim2.new(0, 64, 0, 0), Size = UDim2.new(1, -110, 1, 0), BackgroundColor3 = THEME.Element,
			Font = FONT, Text = "#FFFFFF", TextColor3 = THEME.Text, TextSize = 15, ClipsDescendants = true,
			TextTruncate = Enum.TextTruncate.AtEnd, Parent = hexRow,
		}, { corner(6), stroke(THEME.Stroke, 1, 0.3), padding(6) })
		pctLabel = Create("TextLabel", {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 40, 1, 0),
			BackgroundTransparency = 1, Font = FONT_MED, Text = "100%", TextColor3 = THEME.SubText, TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Right, Parent = hexRow,
		})
		hexBox.FocusLost:Connect(function()
			local hex = string.gsub(hexBox.Text, "#", "")
			if #hex == 6 then
				local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
				if r and g and b then setColor(Color3.fromRGB(r, g, b)); return end
			end
			syncUI()
		end)

		syncUI()
	end

	openPanel = function(state, slot)
		if not panel then buildPanel() end
		if slot then active = slot; if setSlotVisual then setSlotVisual(slot) end; syncUI() end
		local want = (state == nil) and (not opened) or state
		if want == opened then return end
		opened = want
		if opened then
			if _ddCurrent and _ddCurrent ~= cpHandle then _ddCurrent.close() end
			_ddCurrent = cpHandle
			local tx, ty = 0.5 * 1920 - 150, 0.5 * 1080 - 216
			pcall(function()
				local p = sw1.AbsolutePosition
				tx, ty = p.X - 258, p.Y + 30
			end)
			local CP_OPEN = TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			backdrop.Visible = true
			panel.Visible = true
			panel.GroupTransparency = 1
			panel.Position = UDim2.fromOffset(tx, ty + 14)
			if cpScale then cpScale.Scale = 0.94 end
			tween(panel, { GroupTransparency = 0, Position = UDim2.fromOffset(tx, ty) }, CP_OPEN)
			if cpScale then tween(cpScale, { Scale = 1 }, CP_OPEN) end
		else
			if _ddCurrent == cpHandle then _ddCurrent = nil end
			local CP_CLOSE = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			backdrop.Visible = false
			tween(panel, { GroupTransparency = 1 }, CP_CLOSE)
			if cpScale then tween(cpScale, { Scale = 0.94 }, CP_CLOSE) end
			task.delay(0.22, function() if not opened and panel then panel.Visible = false end end)
		end
	end
	cpHandle.close = function() openPanel(false) end

	sw1.MouseButton1Click:Connect(function() openPanel(nil, 1) end)
	sw2.MouseButton1Click:Connect(function() openPanel(nil, 2) end)
	sw1.MouseButton2Click:Connect(function()
		local hex = "#" .. hexOf(slotColor(1))
		if setClipboard(hex) then NEMESIS.Notify({ title = "Copied", content = hex, duration = 2 }) end
	end)

	function control.Set(c, a)
		slots[1].h, slots[1].s, slots[1].v = c:ToHSV()
		if a ~= nil then slots[1].alpha = a end
		if panel then syncUI() end
		commit()
	end
	function control.SetGradient(c1, c2)
		isGradient = true
		slots[1].h, slots[1].s, slots[1].v = (c1 or slotColor(1)):ToHSV()
		slots[2].h, slots[2].s, slots[2].v = (c2 or slotColor(2)):ToHSV()
		if slotRow then slotRow.Visible = true; slotRow.Size = UDim2.new(1, 0, 0, 22) end
		if setModeVisual then setModeVisual(2) end
		layoutSwatches(); if panel then syncUI() end; commit()
	end
	function control.Get() return isGradient and { slotColor(1), slotColor(2) } or slotColor(1) end
	function control.GetAlpha() return isGradient and { slots[1].alpha, slots[2].alpha } or slots[1].alpha end

	commit()
	return control
end

----------------------------------------------------------------------
-- Collapsible content section ("GENERAL", "HITBOX", …)
----------------------------------------------------------------------
local function makeSection(host, accent, title)
	local card = Create("Frame", {
		BackgroundColor3 = THEME.Group,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = host,
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
		Create("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 16) }),
	})

	if title and title ~= "" then
		local header = Create("TextButton", {
			Size = UDim2.new(1, 0, 0, 34),
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
			TextSize = 13,
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
				TextSize = 16,
				Parent = header,
			})
		end
		local open = true
		header.MouseButton1Click:Connect(function()
			open = not open
			tween(chev, { Rotation = open and 0 or 180 }, TI.FAST)
			if open then
				local target = 0
				pcall(function() target = body.AbsoluteSize.Y end)
				bodyWrap.AutomaticSize = Enum.AutomaticSize.None
				tween(bodyWrap, { Size = UDim2.new(1, 0, 0, target) }, TI.EXPAND)
				task.delay(0.28, function() if open then bodyWrap.AutomaticSize = Enum.AutomaticSize.Y end end)
			else
				local cur = 0
				pcall(function() cur = bodyWrap.AbsoluteSize.Y end)
				bodyWrap.AutomaticSize = Enum.AutomaticSize.None
				bodyWrap.Size = UDim2.new(1, 0, 0, cur)
				tween(bodyWrap, { Size = UDim2.new(1, 0, 0, 0) }, TI.EXPAND)
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
	local logoColor = opts.logoColor or Color3.fromRGB(150, 85, 255) -- tint for the built-in N logo (purple)
	local windowColumns = opts.columns or (IS_MOBILE and 1 or 2) -- default panel columns per page
	ensureRoot()

	local scale = computeScale()
	local W = opts.width or (IS_MOBILE and 600 or 900)
	local H = opts.height or (IS_MOBILE and 440 or 600)
	local TOPBAR_H = 60
	local SIDEBAR_W = IS_MOBILE and 158 or 194
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
	makeDraggable(root, topbar)

	-- logo: the real NEMESIS brand image (downloaded + loaded via getcustomasset,
	-- no Roblox upload). Falls back to a gradient "N" tile on executors without
	-- custom-asset support. opts.logo = <assetId> forces an uploaded image.
	local logoSpec = (opts.logo ~= nil) and resolveIcon(opts.logo) or nil
	local brandAsset = (opts.logo == nil) and loadBrandLogo() or nil

	local logoImage -- ImageLabel of the logo mark, if any (used by Win.SetLogoColor)
	if brandAsset then
		-- square N mark (grayscale, tinted by logoColor)
		logoImage = Create("ImageLabel", {
			Position = UDim2.new(0, 14, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.new(0, 42, 0, 42),
			BackgroundTransparency = 1,
			Image = brandAsset,
			ImageColor3 = logoColor,
			ScaleType = Enum.ScaleType.Fit,
			Parent = topbar,
		})
	elseif logoSpec then
		logoImage = Create("ImageLabel", {
			Position = UDim2.new(0, 16, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.new(0, 40, 0, 40),
			BackgroundTransparency = 1,
			Parent = topbar,
		})
		applyIcon(logoImage, logoSpec)
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
			TextSize = 21,
			Parent = tile,
		})
	end

	-- NEMESIS wordmark beside the logo
	Create("TextLabel", {
		Position = UDim2.new(0, 64, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.new(0, 140, 1, 0),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		Text = string.upper(tostring(opts.title or "NEMESIS")),
		TextColor3 = THEME.Text,
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = topbar,
	})

	-- centering frame between the logo and the search pill
	local tabArea = Create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 196, 0.5, 0),
		Size = UDim2.new(1, -(196 + 324), 1, 0),
		BackgroundTransparency = 1,
		Parent = topbar,
	}, {
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	-- segmented tab container: one rounded bordered bar; the active tab fills it
	-- flush (clipped to the bar's rounded corners), tabs split by hairline dividers
	local tabBar = Create("Frame", {
		Size = UDim2.new(0, 0, 0, 38),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = THEME.Background,
		BackgroundTransparency = 0.15,
		ClipsDescendants = true,
		Parent = tabArea,
	}, {
		corner(8),
		stroke(THEME.Stroke, 1, 0.2),
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 0),
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
			TextSize = 17,
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
	}, { corner(10), stroke(THEME.Stroke, 1, 0.3) })
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
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Parent = searchPill,
	})
	-- search pill grows left with the query (capped), then clips
	growBox(searchPill, searchBox, searchW, searchW + 130, hasSearchIcon and 48 or 26)

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

	-- sidebar as a floating rounded panel (card), inset from the window edges,
	-- with a visible border; no divider between it and the content
	local SB_MARGIN = 12
	local SB_GAP = 12
	local sidebarBG = Create("Frame", {
		Position = UDim2.new(0, SB_MARGIN, 0, SB_MARGIN),
		Size = UDim2.new(0, SIDEBAR_W, 1, -SB_MARGIN * 2),
		BackgroundColor3 = THEME.Sidebar,
		BorderSizePixel = 0,
		Parent = body,
	}, { corner(14), stroke(THEME.Stroke, 1, 0.15) })

	-- scroll region (tab sidebars stack here, one visible at a time)
	local sidebarScroll = Create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 2,
		Parent = sidebarBG,
	})

	local content = Create("Frame", {
		Position = UDim2.new(0, SB_MARGIN + SIDEBAR_W + SB_GAP, 0, 0),
		Size = UDim2.new(1, -(SB_MARGIN + SIDEBAR_W + SB_GAP), 1, 0),
		BackgroundTransparency = 1,
		Parent = body,
	})

	-- content header: breadcrumb only
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
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		RichText = true,
		Font = FONT_MED,
		Text = "",
		TextColor3 = THEME.SubText,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})

	-- pages host (each page body lives here; one visible at a time)
	local pagesHost = Create("Frame", {
		Position = UDim2.new(0, 0, 0, 58),
		Size = UDim2.new(1, 0, 1, -58),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = content,
	})
	-- top/bottom fade overlays: content gently fades into the background at the
	-- scroll edges (background-colored gradient, sitting above the page content).
	-- The bottom fade is taller and rounded so it also restores the window's
	-- rounded bottom-right corner (it would otherwise square it off).
	local TOP_FADE_H, BOT_FADE_H = 28, 58
	Create("Frame", {
		Size = UDim2.new(1, 0, 0, TOP_FADE_H),
		BackgroundColor3 = THEME.Background,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = pagesHost,
	}, { Create("UIGradient", { Rotation = 90, Transparency = numSeq(0, 1) }) })
	Create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, BOT_FADE_H),
		BackgroundColor3 = THEME.Background,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = pagesHost,
	}, { corner(RADIUS), Create("UIGradient", { Rotation = 90, Transparency = numSeq(1, 0) }) })

	-- open animation
	root.Size = UDim2.new(0, W, 0, 0)
	tween(root, { Size = UDim2.new(0, W, 0, H) }, TI.OPEN)

	--------------------------------------------------------------------
	-- Navigation state
	--------------------------------------------------------------------
	local Win = {}
	local tabs = {}
	local activeTab
	local tabBarOrder = 0   -- interleaves tab buttons + dividers in the top bar

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

	local SIDEBAR_PAGE_TEXT = Color3.fromRGB(206, 208, 221)  -- inactive sub-tab label
	local function applyPageVisual(tab, page, animate)
		for _, p in ipairs(tab.pages) do
			local on = (p == page)
			p.row.BackgroundColor3 = THEME.SidebarActive
			if animate then
				tween(p.row, { BackgroundTransparency = on and 0 or 1 }, TI.FAST)
				tween(p.label, { TextColor3 = on and accent or SIDEBAR_PAGE_TEXT }, TI.FAST)
			else
				p.row.BackgroundTransparency = on and 0 or 1
				p.label.TextColor3 = on and accent or SIDEBAR_PAGE_TEXT
			end
			p.active = on
		end
	end

	local function showPage(tab, page, animate)
		closeOpenDropdown()
		tab.activePage = page
		applyPageVisual(tab, page, animate ~= false)
		if tab ~= activeTab then return end
		for _, p in ipairs(tab.pages) do p.body.Visible = (p == page) end
		if animate ~= false then
			page.body.Position = UDim2.new(0, 12, 0, 0)
			tween(page.body, { Position = UDim2.new(0, 0, 0, 0) }, TI.TAB)
		end
		setCrumb(tab, page)
		runSearch(searchBox.Text)
	end

	-- paint a top-tab segment for its active/inactive state (smoothly when animate)
	local function paintTab(tab, active, animate)
		local info = animate and TI.FAST or TweenInfo.new(0)
		for _, p in ipairs(tab.hlParts) do
			tween(p, { BackgroundTransparency = active and 0 or 1 }, info)
		end
		tween(tab.label, { TextColor3 = active and THEME.Text or THEME.SubText }, info)
	end

	local function showTab(tab)
		closeOpenDropdown()
		activeTab = tab
		for i, t in ipairs(tabs) do
			t.sidebarFrame.Visible = (t == tab)
			paintTab(t, t == tab, true)
			-- a divider shows only if it borders the active segment
			if t.leftDivider then
				t.leftDivider.Visible = (t == tab) or (tabs[i - 1] == tab)
			end
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
	function Win.Tab(name, icon)
		local tab = { name = tostring(name or "Tab"), pages = {}, activePage = nil }

		-- a full-height hairline sits BETWEEN tabs (its own list item, so it never
		-- interferes with each button's AutomaticSize.X — that was clipping text).
		-- only the dividers touching the active segment are shown (like the mockup).
		if #tabs > 0 then
			tabBarOrder = tabBarOrder + 1
			tab.leftDivider = Create("Frame", {
				Size = UDim2.new(0, 1, 1, 0),
				BackgroundColor3 = Color3.fromRGB(58, 60, 74),
				BorderSizePixel = 0,
				Visible = (activeTab == tabs[#tabs]),
				LayoutOrder = tabBarOrder,
				Parent = tabBar,
			})
		end

		-- top-tab segment: a transparent button holds a rounded fill (behind) and a
		-- text label (in front). the executor doesn't clip children to the bar's
		-- rounded corners, so the fill rounds its own corner(8); the corner(s) that
		-- face a NEIGHBOUR tab are then squared off so only the bar's outer edges
		-- stay rounded (leftmost rounds left, rightmost rounds right, middle square).
		local TAB_FILL = Color3.fromRGB(40, 42, 53)
		local hasLeft = #tabs > 0

		tabBarOrder = tabBarOrder + 1
		local btn = Create("TextButton", {
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = tabBarOrder,
			Parent = tabBar,
		})
		local fill = Create("Frame", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundColor3 = TAB_FILL,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = btn,
		}, { corner(8) })
		local label = Create("TextLabel", {
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Font = FONT_MED,
			Text = tostring(name or "Tab"),
			TextColor3 = THEME.SubText,
			TextSize = 16,
			ZIndex = 2,
			Parent = btn,
		}, {
			Create("UIPadding", { PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22) }),
		})

		-- square off one inner corner: an 8px patch of the fill colour over the
		-- rounded corner on the side that faces a neighbour (sits in the padding
		-- margin, clear of the centred label, so it never covers text)
		local function squareOff(targetFill, side)
			return Create("Frame", {
				AnchorPoint = side == "R" and Vector2.new(1, 0.5) or Vector2.new(0, 0.5),
				Position = side == "R" and UDim2.new(1, 0, 0.5, 0) or UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.new(0, 8, 1, 0),
				BackgroundColor3 = TAB_FILL,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 1,
				Parent = targetFill,
			})
		end

		tab.fill = fill
		tab.hlParts = { fill }
		if hasLeft then
			-- this tab meets a tab on its left -> square its left corner
			tab.hlParts[#tab.hlParts + 1] = squareOff(fill, "L")
			-- and the previous tab now has a neighbour on ITS right -> square that
			local prev = tabs[#tabs]
			prev.hlParts[#prev.hlParts + 1] = squareOff(prev.fill, "R")
			paintTab(prev, activeTab == prev, false)  -- show the new cover if prev is active
		end

		tab.button = btn
		tab.label = label
		-- no hover highlight on top tabs (only the active tab shows a fill)
		btn.MouseButton1Click:Connect(function() showTab(tab) end)
		paintTab(tab, false, false)

		-- this tab's sidebar column
		-- explicit pixel width + offset (NOT scale) so children can't overflow the
		-- card the way scale-width children do inside a ScrollingFrame
		tab.sidebarFrame = Create("Frame", {
			Position = UDim2.new(0, 12, 0, 12),
			Size = UDim2.new(0, SIDEBAR_W - 24, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Visible = false,
			Parent = sidebarScroll,
		}, {
			Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) }),
		})

		local groupCount = 0
		local standaloneStarted = false

		local function makePage(pname, popts, groupName, parentFrame)
			popts = popts or {}
			-- sub-tab row: plain text, no icon / accent bar (matches the mockup)
			local row = Create("TextButton", {
				Size = UDim2.new(1, 0, 0, 34),
				BackgroundColor3 = THEME.SidebarActive,
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Text = "",
				Parent = parentFrame or tab.sidebarFrame,
			}, { corner(8) })
			local label = Create("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 14, 0, 0),
				Size = UDim2.new(1, -24, 1, 0),
				Font = FONT_MED,
				Text = tostring(pname or "Page"),
				TextColor3 = SIDEBAR_PAGE_TEXT,
				TextSize = 15,
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
				Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
				Create("UIPadding", {
					PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18),
					PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 16),
				}),
			})
			smoothScroll(pageBody)

			-- panels laid out across N columns (the one-pager grid)
			local ncols = math.clamp(math.floor(popts.columns or windowColumns), 1, 3)
			local COL_GAP = 10
			local colOff = math.floor(COL_GAP * (ncols - 1) / ncols + 0.5)
			local columnsHolder = Create("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Parent = pageBody,
			}, {
				Create("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, COL_GAP),
					SortOrder = Enum.SortOrder.LayoutOrder,
					VerticalAlignment = Enum.VerticalAlignment.Top,
				}),
			})
			local pageCols, colCount = {}, {}
			for i = 1, ncols do
				pageCols[i] = Create("Frame", {
					Size = UDim2.new(1 / ncols, -colOff, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					LayoutOrder = i,
					Parent = columnsHolder,
				}, {
					Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10) }),
				})
				colCount[i] = 0
			end
			-- pick a column: explicit (column/side) or auto = fewest sections, ties left
			local function pickColumn(sopts)
				local idx
				if sopts and type(sopts.column) == "number" then
					idx = math.clamp(math.floor(sopts.column), 1, ncols)
				elseif sopts and sopts.side == "left" then
					idx = 1
				elseif sopts and sopts.side == "right" then
					idx = math.min(2, ncols)
				else
					idx = 1
					for i = 2, ncols do if colCount[i] < colCount[idx] then idx = i end end
				end
				colCount[idx] = colCount[idx] + 1
				return pageCols[idx]
			end

			local page = {
				name = tostring(pname or "Page"),
				group = groupName,
				row = row, label = label,
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
				if not defaultHost then defaultHost = makeSection(pickColumn({ column = 1 }), accent, nil) end
				return defaultHost
			end
			function Page.Section(t, sopts) return makeSection(pickColumn(sopts), accent, t) end
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
			-- hairline separating this group from the previous one
			if groupCount > 1 then
				Create("Frame", {
					Size = UDim2.new(1, 0, 0, 17),
					BackgroundTransparency = 1,
					Parent = tab.sidebarFrame,
				}, {
					Create("Frame", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(0.5, 0, 0.5, 0),
						Size = UDim2.new(1, -8, 0, 1),
						BackgroundColor3 = THEME.RowDivider,
						BorderSizePixel = 0,
					}),
				})
			end
			local container = Create("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Parent = tab.sidebarFrame,
			}, {
				Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
				Create("UIPadding", { PaddingTop = UDim.new(0, 2) }),
			})
			-- purple-tinted clickable header bar
			local header = Create("TextButton", {
				Size = UDim2.new(1, 0, 0, 32),
				BackgroundColor3 = Color3.fromRGB(41, 32, 66),
				BackgroundTransparency = 0.1,
				AutoButtonColor = false,
				Text = "",
				Parent = container,
			}, { corner(8), stroke(Color3.fromRGB(78, 56, 140), 1, 0.35), padXY(12, 0) })
			Create("TextLabel", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.new(1, -22, 1, 0),
				BackgroundTransparency = 1,
				Font = FONT_BOLD,
				Text = string.upper(tostring(gname or "Group")),
				TextColor3 = accent,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = header,
			})
			local chev
			local chevSpec = resolveIcon("chevron-down")
			if chevSpec then
				chev = Create("ImageLabel", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 0, 0.5, 0),
					Size = UDim2.new(0, 14, 0, 14),
					BackgroundTransparency = 1,
					ImageColor3 = accent,
					Parent = header,
				})
				applyIcon(chev, chevSpec)
			else
				chev = Create("TextLabel", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 0, 0.5, 0),
					Size = UDim2.new(0, 16, 1, 0),
					BackgroundTransparency = 1,
					Font = FONT_BOLD,
					Text = "\u{25BE}",
					TextColor3 = accent,
					TextSize = 15,
					Parent = header,
				})
			end
			-- collapsible pages holder
			local clip = Create("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				Parent = container,
			})
			local holder = Create("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Parent = clip,
			}, {
				Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) }),
				Create("UIPadding", { PaddingTop = UDim.new(0, 6) }),
			})
			local open = true
			header.MouseButton1Click:Connect(function()
				open = not open
				tween(chev, { Rotation = open and 0 or 180 }, TI.FAST)
				if open then
					-- glide open to the measured content height, then hand back to
					-- AutomaticSize so it adapts to later content changes
					local target = 0
					pcall(function() target = holder.AbsoluteSize.Y end)
					clip.AutomaticSize = Enum.AutomaticSize.None
					tween(clip, { Size = UDim2.new(1, 0, 0, target) }, TI.EXPAND)
					task.delay(0.28, function() if open then clip.AutomaticSize = Enum.AutomaticSize.Y end end)
				else
					-- freeze current height, then glide closed to 0
					local cur = 0
					pcall(function() cur = clip.AbsoluteSize.Y end)
					clip.AutomaticSize = Enum.AutomaticSize.None
					clip.Size = UDim2.new(1, 0, 0, cur)
					tween(clip, { Size = UDim2.new(1, 0, 0, 0) }, TI.EXPAND)
				end
			end)
			local Group = {}
			function Group.Page(pname, popts) return makePage(pname, popts, gname, holder) end
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
	-- resize grip (bottom-right)
	--------------------------------------------------------------------
	local minW = IS_MOBILE and 420 or 640
	local minH = 380
	-- SIRIUS X resize handle: a large invisible hit area + the curved corner icon
	local resizeGrip = Create("ImageButton", {
		Name = "ResizeGrip",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -4, 1, -4),
		Size = UDim2.new(0, 54, 0, 54),
		BackgroundTransparency = 1,
		Image = "",
		AutoButtonColor = false,
		ZIndex = 7,
		Parent = root,
	})
	-- 9-sliced so the curved icon stretches cleanly toward the cursor
	local resizeIcon = Create("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.new(0, 18, 0, 18),
		BackgroundTransparency = 1,
		Image = "rbxassetid://86527207319523",
		ImageColor3 = Color3.fromRGB(90, 90, 98),
		ImageTransparency = 0,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(51, 52, 51, 52),
		SliceScale = 0.5,
		ZIndex = 8,
		Parent = resizeGrip,
	})
	do
		-- SIRIUS-style smooth resize: a RenderStepped loop where the visual size
		-- eases toward a cursor-driven target each frame (frame-rate independent
		-- exponential smoothing), so the window butter-glides to follow the cursor.
		local SMOOTH_K = 26          -- higher = tighter cursor-follow (SIRIUS ~28)
		local resizing = false
		local hovering = false
		local startPointer, startW, startH
		local targetW, targetH = W, H
		local visualW, visualH = W, H
		local loopConn

		local function getPointer(input)
			if input and input.UserInputType == Enum.UserInputType.Touch then
				return Vector2.new(input.Position.X, input.Position.Y)
			end
			return UserInputService:GetMouseLocation()
		end
		local function maxSize()
			local vp = viewportSize()
			return math.max(minW, vp.X / scale - 40), math.max(minH, vp.Y / scale - 40)
		end
		-- SIRIUS stretch: normalize the cursor's position inside the grip, then
		-- stretch the icon NON-uniformly toward it (wider/taller as you move in)
		local function normResize()
			local mouse = UserInputService:GetMouseLocation()
			local insetY = 0
			pcall(function() insetY = game:GetService("GuiService"):GetGuiInset().Y end)
			local pos, sz = resizeGrip.AbsolutePosition, resizeGrip.AbsoluteSize
			local relX = (mouse.X - pos.X) / math.max(sz.X, 1)
			local relY = ((mouse.Y - insetY) - pos.Y) / math.max(sz.Y, 1)
			return Vector2.new(1 - math.clamp(relX, 0, 1), 1 - math.clamp(relY, 0, 1))
		end
		local function stretchIcon(duration)
			local n = normResize()
			tween(resizeIcon, {
				Size = UDim2.new(0, 20 + n.X * 30, 0, 20 + n.Y * 30),
				ImageColor3 = Color3.fromRGB(125, 125, 135),
			}, TweenInfo.new(duration or 0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
		end
		local function pressIcon()
			tween(resizeIcon, {
				Size = UDim2.new(0, 30, 0, 30),
				ImageColor3 = Color3.fromRGB(150, 150, 160),
			}, TweenInfo.new(0.12, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
		end
		local function resetIcon()
			tween(resizeIcon, {
				Size = UDim2.new(0, 18, 0, 18),
				ImageColor3 = Color3.fromRGB(90, 90, 98),
			}, TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
		end
		local function stopLoop()
			if loopConn then loopConn:Disconnect(); loopConn = nil end
		end
		local function startLoop()
			stopLoop()
			visualW, visualH = W, H
			loopConn = RunService.RenderStepped:Connect(function(dt)
				local alpha = 1 - math.exp(-dt * SMOOTH_K)
				visualW = visualW + (targetW - visualW) * alpha
				visualH = visualH + (targetH - visualH) * alpha
				W, H = visualW, visualH
				root.Size = UDim2.new(0, visualW, 0, visualH)
				if not resizing
					and math.abs(visualW - targetW) <= 0.45
					and math.abs(visualH - targetH) <= 0.45 then
					W, H = targetW, targetH
					root.Size = UDim2.new(0, W, 0, H)
					stopLoop()
				end
			end)
		end

		resizeGrip.MouseEnter:Connect(function()
			hovering = true
			if not resizing then stretchIcon(0.18) end
		end)
		resizeGrip.MouseLeave:Connect(function()
			hovering = false
			if not resizing then resetIcon() end
		end)
		-- moving the cursor inside the grip restretches the icon toward it
		resizeGrip.InputChanged:Connect(function(input)
			if resizing then return end
			if input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch then
				stretchIcon(0.14)
			end
		end)
		resizeGrip.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				resizing = true
				startPointer = getPointer(input)
				startW, startH = W, H
				targetW, targetH = W, H
				pressIcon()
				startLoop()
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if not resizing then return end
			if input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch then
				local delta = getPointer(input) - startPointer
				local maxW, maxH = maxSize()
				-- *2: window is centre-anchored, so the corner tracks the cursor
				targetW = math.clamp(startW + (delta.X / scale) * 2, minW, maxW)
				targetH = math.clamp(startH + (delta.Y / scale) * 2, minH, maxH)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				if resizing then
					resizing = false
					if hovering then stretchIcon(0.18) else resetIcon() end
				end
			end
		end)
	end

	--------------------------------------------------------------------
	-- minimize / restore, close, hide-key, mobile reopen
	--------------------------------------------------------------------
	local minimized = false
	local function setMinimized(m)
		minimized = m
		closeOpenDropdown()
		if resizeGrip then resizeGrip.Visible = not m end
		if m then
			topbarFiller.Visible = false
			tween(root, { Size = UDim2.new(0, W, 0, TOPBAR_H) }, TI.OPEN)
			setMinIcon("plus", "\u{002B}")
		else
			topbarFiller.Visible = true
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
			TextSize = 21,
			Parent = screenGui,
		}, { corner(22), stroke(THEME.Stroke, 1, 0.4) })
		makeDraggable(fab, fab)
		fab.MouseButton1Click:Connect(function() setHidden(not hidden) end)
	end

	-- recolor the logo at runtime (any hue): Win.SetLogoColor(Color3.fromRGB(...))
	function Win.SetLogoColor(c)
		logoColor = c or logoColor
		if logoImage then logoImage.ImageColor3 = logoColor end
	end

	Win.Instance = root
	Win.Notify = NEMESIS.Notify
	return Win
end

----------------------------------------------------------------------
return NEMESIS
