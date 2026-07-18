--[[
	NEMESIS UI Library (v1.0)
	A UI library for Roblox script executors.

	Load:
		local NEMESIS = loadstring(game:HttpGet("https://raw.githubusercontent.com/SyncOfficialSpec/NEMESIS/main/source.lua"))()

	Hierarchy: Window > Tab > Group > Page > Section > controls

		local Win     = NEMESIS.Window({ title = "NEMESIS" })
		local Combat  = Win.Tab("Combat")
		local Aimbot  = Combat.Group("AIMBOT")
		local General = Aimbot.Page("General", { icon = "crosshair" })
		local Misc    = Combat.Page("Misc", { icon = "sliders-horizontal" })  -- standalone sub-tab
		local gen     = General.Section("GENERAL")
		gen.Toggle({ text = "Enable", default = true, flag = "aim_enable" })
		gen.Dropdown({ text = "Weapon Group", options = { "Rifles", "Pistols" }, default = "Rifles" })
		gen.Keybind({ text = "Keybind", default = "MOUSE5", mode = "Hold" })

	See README.md for the full reference.
]]

local NEMESIS = {}
NEMESIS.Flags = {}
NEMESIS.Version = "2.0.0"

-- Services (cloneref-safe)
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

-- Executor compatibility
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

-- Brand logo (real image, no Roblox upload needed)
-- Downloads the PNG and exposes it via the executor's custom-asset API
-- (getcustomasset / getsynasset), cached on disk after the first load.
-- versioned path: bump the filename (URL + on-disk cache) whenever the logo
-- changes, so neither the GitHub CDN nor the executor serves a stale image
-- grayscale logo so ImageColor3 can tint it to any hue at runtime
local LOGO_URL = "https://raw.githubusercontent.com/SyncOfficialSpec/NEMESIS/main/assets/nemesis_wordmark_v1.png"
local LOGO_FILE = "nemesis_wordmark_v1.png"
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

-- Icons: NEMESIS ships its own Lucide atlas (white 48px sprites packed into
-- spritesheets under assets/icons, regenerate with tools/iconsgen). The index
-- maps a name to {sheet, x, y}; sheets download once, cache on disk, and load
-- through getcustomasset, same as the logo. Versioned filenames (v1) bust both
-- the GitHub CDN and the executor's asset cache whenever the atlas changes.
local ICONS_BASE = "https://raw.githubusercontent.com/SyncOfficialSpec/NEMESIS/main/assets/icons/"
local ICONS_VER = "v1"
local ICON_PX = 48

-- table = loaded. A single failed fetch used to be cached as a permanent
-- failure, which made EVERY icon fall back to a glyph for the whole session
-- after one HTTP hiccup - so instead we retry a bounded number of times.
local iconIndex = nil
local iconIndexTries = 0
local iconSheets = {}      -- sheet number -> rbxasset id string (once loaded)
local iconSheetTries = {}  -- sheet number -> attempts so far

local function loadIconIndex()
	if type(iconIndex) == "table" then return iconIndex end
	if iconIndexTries >= 8 then return nil end   -- give up only after real retries
	iconIndexTries = iconIndexTries + 1
	if type(loadstring) == "function" then
		pcall(function()
			local src = game:HttpGet(ICONS_BASE .. "index_" .. ICONS_VER .. ".lua")
			local fn = loadstring(src)
			if type(fn) == "function" then
				local ok, map = pcall(fn)
				if ok and type(map) == "table" then
					iconIndex = map
				end
			end
		end)
	end
	return type(iconIndex) == "table" and iconIndex or nil
end

local function loadIconSheet(n)
	if type(iconSheets[n]) == "string" then return iconSheets[n] end
	iconSheetTries[n] = iconSheetTries[n] or 0
	if iconSheetTries[n] >= 6 then return nil end
	iconSheetTries[n] = iconSheetTries[n] + 1
	local getAsset = customAssetFn()
	if not getAsset or type(writefile) ~= "function" then return nil end
	pcall(function()
		local file = "nemesis_icons_" .. ICONS_VER .. "_" .. n .. ".png"
		local have = type(isfile) == "function" and isfile(file)
		if not have then
			local data = game:HttpGet(ICONS_BASE .. "icons_" .. ICONS_VER .. "_" .. n .. ".png")
			if type(data) == "string" and #data > 500 then
				writefile(file, data)
				have = true
			end
		end
		if have then
			local id = getAsset(file)
			if type(id) == "string" and id ~= "" then iconSheets[n] = id end
		end
	end)
	return type(iconSheets[n]) == "string" and iconSheets[n] or nil
end

-- Baked art (shadows, glow filaments, checkerboard, cursor ring, grip ticks).
-- Same download-once/getcustomasset path as the icon sheets. Filenames carry
-- the cal1 revision so any art change busts both the CDN and the disk cache.
local ART_BASE = "https://raw.githubusercontent.com/SyncOfficialSpec/NEMESIS/main/assets/art/"
local artCache = {}

local function loadArt(name)
	if artCache[name] ~= nil then
		return artCache[name] or nil
	end
	artCache[name] = false
	local getAsset = customAssetFn()
	if not getAsset or type(writefile) ~= "function" then return nil end
	pcall(function()
		local file = "nemesis_art_" .. name
		local have = type(isfile) == "function" and isfile(file)
		if not have then
			local data = game:HttpGet(ART_BASE .. name)
			if type(data) == "string" and #data > 60 then
				writefile(file, data)
				have = true
			end
		end
		if have then
			local id = getAsset(file)
			if type(id) == "string" and id ~= "" then artCache[name] = id end
		end
	end)
	return artCache[name] or nil
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
		local idx = loadIconIndex()
		local entry = type(idx) == "table" and idx[string.lower(icon)]
		if entry then
			local sheet = loadIconSheet(entry[1])
			if sheet then
				return {
					Image = sheet,
					ImageRectSize = Vector2.new(ICON_PX, ICON_PX),
					ImageRectOffset = Vector2.new(entry[2], entry[3]),
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

-- Instance helpers
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

-- Make `fill` conform to whatever rounded shape `box` has, automatically.
-- Instead of hand-matching a radius, the fill mirrors the box's UICorner and
-- stays in sync with it, so no matter the box type -- a small fixed radius, a
-- scaled radius, or a full pill -- the fill's corners curve the same way and it
-- can never spill past the box's boundary. Scaled radii (UDim scale > 0) even
-- self-adjust as the fill grows/shrinks, so partial and animated fills stay
-- inside too. Returns the fill for chaining.
local function conformFill(fill, box)
	local fillCorner = fill:FindFirstChildOfClass("UICorner") or corner(0)
	fillCorner.Parent = fill

	local boxCorner = box:FindFirstChildOfClass("UICorner")
	local function sync()
		fillCorner.CornerRadius = boxCorner and boxCorner.CornerRadius or UDim.new(0, 0)
	end

	local radiusConn
	local function bind()
		if radiusConn then radiusConn:Disconnect() end
		if boxCorner then
			radiusConn = boxCorner:GetPropertyChangedSignal("CornerRadius"):Connect(sync)
		end
		sync()
	end
	bind()

	-- if the box's corner is added/swapped/removed later, re-mirror it
	box.ChildAdded:Connect(function(child)
		if child:IsA("UICorner") then boxCorner = child; bind() end
	end)
	box.ChildRemoved:Connect(function(child)
		if child == boxCorner then boxCorner = box:FindFirstChildOfClass("UICorner"); bind() end
	end)

	return fill
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

-- A chevron that ALWAYS renders as a real icon: the atlas "chevron-*" sprite when
-- it resolves, a clean drawn vector caret otherwise. Never a unicode/tofu glyph.
-- Returns the rotatable element; the caller sets AnchorPoint/Position.
local function iconChevron(parent, px, color, name)
	local spec = resolveIcon(name or "chevron-up")
	if spec then
		local img = Create("ImageLabel", { Size = UDim2.new(0, px, 0, px), BackgroundTransparency = 1, ImageColor3 = color, Parent = parent })
		applyIcon(img, spec)
		return img
	end
	local holder = Create("Frame", { Size = UDim2.new(0, px, 0, px), BackgroundTransparency = 1, Parent = parent })
	local arm = px * 0.42
	local th = math.max(1.5, px / 9)
	Create("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0.5, 1, 0.5, 1), Size = UDim2.new(0, arm, 0, th), BackgroundColor3 = color, BorderSizePixel = 0, Rotation = 45, Parent = holder }, { corner(99) })
	Create("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.5, -1, 0.5, 1), Size = UDim2.new(0, arm, 0, th), BackgroundColor3 = color, BorderSizePixel = 0, Rotation = -45, Parent = holder }, { corner(99) })
	return holder
end

-- An X that always renders: the atlas "x" sprite, or a drawn cross. Never a glyph.
local function iconX(parent, px, color)
	local spec = resolveIcon("x")
	if spec then
		local img = Create("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, px, 0, px), BackgroundTransparency = 1, ImageColor3 = color, Parent = parent })
		applyIcon(img, spec)
		return img
	end
	local holder = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, px, 0, px), BackgroundTransparency = 1, Parent = parent })
	local arm = px * 0.72
	local th = math.max(1.5, px / 8)
	Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, arm, 0, th), BackgroundColor3 = color, BorderSizePixel = 0, Rotation = 45, Parent = holder }, { corner(99) })
	Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, arm, 0, th), BackgroundColor3 = color, BorderSizePixel = 0, Rotation = -45, Parent = holder }, { corner(99) })
	return holder
end

local function tagSearch(frame, text)
	pcall(function()
		frame:SetAttribute("NemesisSearch", tostring(text or ""))
	end)
end

-- Theme
-- Named theme presets. Dark is the default; switch at runtime with
-- Win.SetTheme("Light") or pass partial overrides via Window({ theme = {...} }).
-- Accent is deliberately not part of a preset (Win.SetAccent handles it).
-- NOTE for new presets: Sidebar and Topbar must share one colour (the live
-- re-theme walk matches instances by current colour value, so keys that share
-- a value must share it in every preset).
NEMESIS.Themes = {
	Dark = {
		Background = Color3.fromRGB(10, 11, 13),      -- window / content well (darkest plate)
		Sidebar = Color3.fromRGB(14, 15, 18),         -- sidebar card
		Topbar = Color3.fromRGB(14, 15, 18),          -- top bar (must equal Sidebar)
		SidebarActive = Color3.fromRGB(27, 29, 33),   -- active page row plate
		SidebarHover = Color3.fromRGB(19, 20, 24),
		Group = Color3.fromRGB(15, 16, 19),           -- section card plate
		Element = Color3.fromRGB(21, 22, 26),         -- fields / chips / wells
		ElementHover = Color3.fromRGB(29, 31, 36),
		Stroke = Color3.fromRGB(36, 38, 44),          -- structural seams
		ElementStroke = Color3.fromRGB(46, 49, 56),   -- control seams
		RowDivider = Color3.fromRGB(25, 27, 32),      -- etched row ticks
		Text = Color3.fromRGB(232, 235, 236),
		SubText = Color3.fromRGB(130, 136, 143),
		Faint = Color3.fromRGB(85, 90, 98),
		ToggleOff = Color3.fromRGB(45, 48, 55),
		Knob = Color3.fromRGB(242, 244, 246),
		Good = Color3.fromRGB(92, 220, 138),
	},
	Midnight = {
		Background = Color3.fromRGB(9, 11, 18),
		Sidebar = Color3.fromRGB(13, 15, 24),
		Topbar = Color3.fromRGB(13, 15, 24),
		SidebarActive = Color3.fromRGB(25, 29, 44),
		SidebarHover = Color3.fromRGB(18, 21, 32),
		Group = Color3.fromRGB(14, 16, 25),
		Element = Color3.fromRGB(20, 22, 34),
		ElementHover = Color3.fromRGB(28, 31, 46),
		Stroke = Color3.fromRGB(34, 38, 54),
		ElementStroke = Color3.fromRGB(44, 48, 68),
		RowDivider = Color3.fromRGB(24, 27, 40),
		Text = Color3.fromRGB(230, 234, 244),
		SubText = Color3.fromRGB(128, 136, 156),
		Faint = Color3.fromRGB(84, 90, 112),
		ToggleOff = Color3.fromRGB(44, 48, 66),
		Knob = Color3.fromRGB(242, 244, 250),
		Good = Color3.fromRGB(92, 220, 138),
	},
	Abyss = {
		Background = Color3.fromRGB(7, 7, 8),
		Sidebar = Color3.fromRGB(11, 11, 13),
		Topbar = Color3.fromRGB(11, 11, 13),
		SidebarActive = Color3.fromRGB(24, 24, 28),
		SidebarHover = Color3.fromRGB(16, 16, 19),
		Group = Color3.fromRGB(12, 12, 14),
		Element = Color3.fromRGB(18, 18, 21),
		ElementHover = Color3.fromRGB(26, 26, 30),
		Stroke = Color3.fromRGB(33, 33, 38),
		ElementStroke = Color3.fromRGB(43, 43, 49),
		RowDivider = Color3.fromRGB(23, 23, 27),
		Text = Color3.fromRGB(235, 235, 238),
		SubText = Color3.fromRGB(134, 134, 144),
		Faint = Color3.fromRGB(88, 88, 98),
		ToggleOff = Color3.fromRGB(42, 42, 50),
		Knob = Color3.fromRGB(244, 244, 247),
		Good = Color3.fromRGB(92, 220, 138),
	},
}

local THEME = { Accent = Color3.fromRGB(140, 90, 255) }
for k, v in pairs(NEMESIS.Themes.Dark) do THEME[k] = v end

-- Type: Inter carries the words, Roboto Mono carries every numeric readout so
-- digits never shift width while a value slides. Mono falls back to Inter on
-- executors with stripped font sets.
local INTER = "rbxasset://fonts/families/Inter.json"
local FONT = Font.new(INTER, Enum.FontWeight.Medium)
local FONT_MED = Font.new(INTER, Enum.FontWeight.Medium)
local FONT_SEMI = Font.new(INTER, Enum.FontWeight.SemiBold)
local FONT_BOLD = Font.new(INTER, Enum.FontWeight.Bold)
local FONT_MONO
do
	local ok, f = pcall(Font.new, "rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Medium)
	FONT_MONO = ok and f or FONT_MED
end

-- Inline-row layout metrics (scaled by the window's UIScale at runtime)
local ROW_H = 36          -- height of a setting row (instrument grid)
local ROW_PAD = 12        -- horizontal inset inside a row / section
-- Right-side control widths are a FRACTION of the row, so they fit any column
-- count (1 / 2 / 3) and resize. Label takes the complementary fraction.
local FIELD_FRAC = 0.5    -- dropdown / keybind / input field width fraction
local SLIDER_FRAC = 0.55  -- slider (value + track) cluster width fraction

-- Fixed colors that stay identical across presets (like Good)
local DANGER = Color3.fromRGB(235, 84, 84)

-- text color for anything sitting ON a solid accent fill
local function accentTextColor(c)
	local lum = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
	return lum > 0.55 and Color3.fromRGB(12, 13, 15) or Color3.fromRGB(242, 244, 246)
end

local function hexOf(c)
	return string.format("%02X%02X%02X",
		math.floor((c.R or 0) * 255 + 0.5),
		math.floor((c.G or 0) * 255 + 0.5),
		math.floor((c.B or 0) * 255 + 0.5))
end

-- Gradient helpers
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

-- Tween helpers
-- mechanical easing set: everything eases Out and stops dead, nothing bounces.
-- Hover is asymmetric on purpose (fast in, gentle out) so surfaces feel like
-- they settle rather than blink.
local TI = {
	EXP = TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),          -- state commits, fills (size = Quint)
	FAST = TweenInfo.new(0.3, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),    -- small tints, arrows (Syde fades = Exp)
	TAB = TweenInfo.new(0.32, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),    -- tab/dock travel, page glide
	EXPAND = TweenInfo.new(0.32, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), -- overlays, collapse
	POP = TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),          -- knob feedback (size = Quint)
	SCROLL = TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),        -- smooth wheel scroll
	TICK = TweenInfo.new(0.2, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),    -- press-down, check draw
}
TI.OPEN = TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)           -- window morphs (size = Quint)
-- hover in/out on Syde's soft exponential (0.4s), not the old snappy Quad
TI.HOVER = TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)     -- hover in
TI.HOVEROFF = TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)  -- hover out (settle)
TI.SLIDE = TI.EXPAND
TI.NOTIFY = TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)    -- notification glide
-- Syde-matched motion: exponential for colour/opacity, quint for size/position,
-- long soft 0.4-0.7s durations. These carry the element animations 1:1.
TI.SYDE = TweenInfo.new(0.7, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)      -- toggle fill, button state
TI.SYDE_FADE = TweenInfo.new(0.57, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out) -- toggle gradient
TI.SYDE_SIZE = TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)      -- slider fill, keybind pill
TI.SYDE_REFLOW = TweenInfo.new(0.45, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out) -- element reflow / page reveal
TI.SYDE_OPT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)         -- dropdown option highlight
TI.SHADOW = TweenInfo.new(0.65, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)   -- shadow density

-- reduced-motion governor: when the menu itself measures a starved framerate
-- (see the footer FPS loop), tweens collapse to near-instant sets so state is
-- never trapped mid-animation on weak executors
local REDUCED_TI = TweenInfo.new(0.01, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local reducedMotion = false

local function tween(inst, props, info, exact)
	-- exact skips the reduced-motion governor: some tweens ARE the information
	-- (a notification drain bar) and must keep their real duration
	local t = TweenService:Create(inst, (reducedMotion and not exact) and REDUCED_TI or (info or TI.SLIDE), props)
	t:Play()
	return t
end

-- recolor an icon returned by iconChevron/iconX, whether it's an atlas ImageLabel
-- or a drawn-vector holder (recolours its line frames)
local function recolorIcon(el, c, info)
	if el:IsA("ImageLabel") then tween(el, { ImageColor3 = c }, info)
	elseif el:IsA("TextLabel") then tween(el, { TextColor3 = c }, info)
	else for _, ch in ipairs(el:GetChildren()) do if ch:IsA("Frame") then tween(ch, { BackgroundColor3 = c }, info) end end end
end

-- Minimal JSON (own encoder/decoder so configs work on any executor without
-- needing HttpService)
local jsonEncode, jsonDecode
do
	local esc = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
	local function isArray(t)
		local n = 0
		for k in pairs(t) do
			if type(k) ~= "number" then return false end
			n = n + 1
		end
		return n == #t
	end
	function jsonEncode(v)
		local tv = type(v)
		if v == nil then return "null" end
		if tv == "boolean" then return v and "true" or "false" end
		if tv == "number" then return string.format("%.14g", v) end
		if tv == "string" then return '"' .. v:gsub('[%z\1-\31"\\]', function(c) return esc[c] or string.format("\\u%04x", c:byte()) end) .. '"' end
		if tv == "table" then
			local out = {}
			if isArray(v) then
				for i = 1, #v do out[i] = jsonEncode(v[i]) end
				return "[" .. table.concat(out, ",") .. "]"
			end
			for k, x in pairs(v) do out[#out + 1] = jsonEncode(tostring(k)) .. ":" .. jsonEncode(x) end
			return "{" .. table.concat(out, ",") .. "}"
		end
		return "null"
	end

	local unesc = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", n = "\n", r = "\r", t = "\t", b = "\b", f = "\f" }
	function jsonDecode(s)
		local i = 1
		local function skip()
			while i <= #s and s:sub(i, i):match("%s") do i = i + 1 end
		end
		local parse
		local function parseString()
			i = i + 1
			local buf = {}
			while i <= #s do
				local c = s:sub(i, i)
				if c == '"' then i = i + 1; return table.concat(buf) end
				if c == "\\" then
					local e = s:sub(i + 1, i + 1)
					if e == "u" then
						buf[#buf + 1] = string.char(tonumber(s:sub(i + 2, i + 5), 16) % 256)
						i = i + 6
					else
						buf[#buf + 1] = unesc[e] or e
						i = i + 2
					end
				else
					buf[#buf + 1] = c
					i = i + 1
				end
			end
			error("unterminated string")
		end
		function parse()
			skip()
			local c = s:sub(i, i)
			if c == "{" then
				i = i + 1
				local t = {}
				skip()
				if s:sub(i, i) == "}" then i = i + 1; return t end
				while true do
					skip()
					local k = parseString()
					skip(); i = i + 1 -- ':'
					t[k] = parse()
					skip()
					local d = s:sub(i, i); i = i + 1
					if d == "}" then return t end
				end
			elseif c == "[" then
				i = i + 1
				local t = {}
				skip()
				if s:sub(i, i) == "]" then i = i + 1; return t end
				while true do
					t[#t + 1] = parse()
					skip()
					local d = s:sub(i, i); i = i + 1
					if d == "]" then return t end
				end
			elseif c == '"' then
				return parseString()
			elseif s:sub(i, i + 3) == "true" then i = i + 4; return true
			elseif s:sub(i, i + 4) == "false" then i = i + 5; return false
			elseif s:sub(i, i + 3) == "null" then i = i + 4; return nil
			else
				local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", i)
				if not num or num == "" then error("bad json at " .. i) end
				i = i + #num
				return tonumber(num)
			end
		end
		local ok, v = pcall(parse)
		return ok and v or nil
	end
end

-- Executor file API, guarded so everything degrades to no-ops in-Studio
local function hasFileApi()
	return type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
end
local function fsEnsureFolder(path)
	pcall(function()
		if type(makefolder) == "function" and type(isfolder) == "function" and not isfolder(path) then
			makefolder(path)
		end
	end)
end
local function fsRead(path)
	local data
	pcall(function()
		if isfile(path) then data = readfile(path) end
	end)
	return data
end
local function fsWrite(path, data)
	local ok = pcall(function() writefile(path, data) end)
	return ok
end
local function fsDelete(path)
	pcall(function()
		if type(delfile) == "function" and isfile(path) then delfile(path) end
	end)
end
local function fsList(folder)
	local out = {}
	pcall(function()
		if type(listfiles) == "function" then
			for _, p in ipairs(listfiles(folder)) do out[#out + 1] = p end
		end
	end)
	return out
end

-- Flag registry: every element created with { flag = "..." } registers its
-- control here so configs can read (Get) and push (Set) values by flag name
local flagged = {}
local function bindFlag(flag, control, kind)
	if flag then flagged[flag] = { control = control, kind = kind } end
end

-- config value <-> plain-json shapes (Color3s and KeyCodes need wrapping)
local function packValue(kind, rec)
	local v = rec.control.Get()
	if kind == "colorpicker" then
		local a = rec.control.GetAlpha()
		if typeof(v) == "ColorSequence" and rec.control._cpGetStops then
			return { __m = rec.control._cpGetStops() }
		end
		if typeof(v) == "table" then
			return { __g = { { math.floor(v[1].R * 255 + 0.5), math.floor(v[1].G * 255 + 0.5), math.floor(v[1].B * 255 + 0.5) },
				{ math.floor(v[2].R * 255 + 0.5), math.floor(v[2].G * 255 + 0.5), math.floor(v[2].B * 255 + 0.5) } }, a = a }
		end
		return { __c = { math.floor(v.R * 255 + 0.5), math.floor(v.G * 255 + 0.5), math.floor(v.B * 255 + 0.5) }, a = a }
	end
	if kind == "keybind" then
		if v == nil then return nil end
		if type(v) == "string" then return v end
		local ok, name = pcall(function() return v.Name end)
		return ok and { __kc = name } or nil
	end
	return v
end
local function unpackValue(kind, rec, v)
	local ctrl = rec.control
	if type(v) == "table" and v.__c then
		ctrl.Set(Color3.fromRGB(v.__c[1], v.__c[2], v.__c[3]), tonumber(v.a) or 0)
		return
	end
	if type(v) == "table" and v.__g then
		local a = type(v.a) == "table" and v.a or {}
		ctrl.SetGradient(
			Color3.fromRGB(v.__g[1][1], v.__g[1][2], v.__g[1][3]),
			Color3.fromRGB(v.__g[2][1], v.__g[2][2], v.__g[2][3]),
			tonumber(a[1]), tonumber(a[2]))
		return
	end
	if type(v) == "table" and v.__m and ctrl.SetMulti then
		local kps = {}
		for _, st in ipairs(v.__m) do
			kps[#kps + 1] = ColorSequenceKeypoint.new(math.clamp(tonumber(st.pos) or 0, 0, 1), Color3.fromRGB(st.r, st.g, st.b))
		end
		if #kps >= 2 then pcall(function() ctrl.SetMulti(ColorSequence.new(kps)) end) end
		return
	end
	if type(v) == "table" and v.__kc then
		pcall(function() ctrl.Set(Enum.KeyCode[v.__kc]) end)
		return
	end
	-- hydrate toggles instantly (no animation) but still fire their callback so the
	-- restored setting actually applies
	if kind == "toggle" then ctrl.Set(v, nil, true) else ctrl.Set(v) end
end

-- Accent registry: callbacks run on Win.SetAccent so the menu recolours live
local accentHooks = {}
local function onAccent(fn) accentHooks[#accentHooks + 1] = fn end
local function accentLight(c) return c:Lerp(Color3.fromRGB(255, 255, 255), 0.35) end
-- accent / hitbox can be a Color3 OR a ColorSequence (a Multi gradient). flat
-- consumers use the first stop; gradient consumers get the whole sequence.
local function seqPrimary(v)
	if typeof(v) == "ColorSequence" then
		local kp = v.Keypoints
		return (kp[1] and kp[1].Value) or Color3.new(1, 1, 1)
	end
	return v
end
local function accentGradColor(c)
	if typeof(c) == "ColorSequence" then return c end
	return ColorSequence.new(c, accentLight(c))
end
local function accentProp(inst, prop, accent)
	inst[prop] = seqPrimary(accent)
	onAccent(function(c) pcall(function() inst[prop] = seqPrimary(c) end) end)
	return inst
end
local function accentGrad(grad, accent)
	grad.Color = accentGradColor(accent)
	onAccent(function(c) pcall(function() grad.Color = accentGradColor(c) end) end)
	return grad
end

-- Hitbox registry: the fill/highlight colour of toggles and slider fills. It
-- tracks the accent until Win.SetHitbox sets an independent colour (Win.SetAccent
-- keeps driving it while it hasn't been overridden). Mirrors the accent helpers.
local hitboxHooks = {}
local hitboxOverride = false
local function onHitbox(fn) hitboxHooks[#hitboxHooks + 1] = fn end
local function fireHitbox(c) for _, fn in ipairs(hitboxHooks) do pcall(fn, c) end end
local function hitboxProp(inst, prop, initial)
	inst[prop] = seqPrimary(initial)
	onHitbox(function(c) pcall(function() inst[prop] = seqPrimary(c) end) end)
	return inst
end
local function hitboxGrad(grad, initial)
	grad.Color = accentGradColor(initial)
	onHitbox(function(c) pcall(function() grad.Color = accentGradColor(c) end) end)
	return grad
end

-- the classic Rayfield window shadow, vendored into this repo with the panel
-- region punched out so it can sit behind OR inside any panel without tinting
local RF_SHADOW = { name = "cal4_shadow.png", slice = Rect.new(91, 91, 187, 328), pad = 55 }
local function dropShadow(parent, transparency)
	local art = loadArt(RF_SHADOW.name)
	if not art then return nil end
	return Create("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, RF_SHADOW.pad * 2, 1, RF_SHADOW.pad * 2),
		BackgroundTransparency = 1,
		Image = art,
		-- the Rayfield shadow asset is white; tint it black so it reads as a shadow
		ImageColor3 = Color3.fromRGB(0, 0, 0),
		ImageTransparency = transparency or 0.4,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = RF_SHADOW.slice,
		ZIndex = 0,
		Parent = parent,
	})
end

-- Shadow as a SIBLING that mirrors the target: needed when the target clips
-- its children (CanvasGroup, ClipsDescendants) so a child shadow would vanish.
-- Call after the target is parented.
local function siblingShadow(target, transparency)
	if not target.Parent then return nil end
	local holder = Create("Frame", {
		Name = "Shadow",
		AnchorPoint = target.AnchorPoint,
		Position = target.Position,
		Size = target.Size,
		BackgroundTransparency = 1,
		Visible = target.Visible,
		ZIndex = math.max((target.ZIndex or 1) - 1, 0),
		Parent = target.Parent,
	})
	local img = dropShadow(holder, transparency)
	if not img then holder:Destroy(); return nil end
	pcall(function()
		for _, prop in ipairs({ "Position", "Size", "AnchorPoint", "Visible" }) do
			target:GetPropertyChangedSignal(prop):Connect(function()
				holder[prop] = target[prop]
			end)
		end
		target.AncestryChanged:Connect(function()
			if not target.Parent then holder:Destroy() end
		end)
	end)
	return holder
end

-- Mobile / scale
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

-- Unified mouse + touch drag. clampGetter()->bool keeps the frame on screen;
-- smoothGetter()->0..1 eases the frame toward the cursor (0 = instant follow).
local function makeDraggable(frame, handle, clampGetter, smoothGetter)
	handle = handle or frame
	local dragging = false
	local dragStart, startPos
	local targetX, targetY, followConn

	local function stopFollow()
		if followConn then pcall(function() followConn:Disconnect() end); followConn = nil end
	end
	-- while smoothing is on, ease the frame toward the target each frame instead of
	-- snapping (frame-rate independent; higher smoothness = softer glide)
	local function startFollow()
		stopFollow()
		followConn = RunService.RenderStepped:Connect(function(dt)
			local sm = smoothGetter and math.clamp(smoothGetter() or 0, 0, 1) or 0
			local k = 40 - 32 * sm            -- 40 (snappy) .. 8 (smooth)
			local a = 1 - math.exp(-dt * k)
			local cur = frame.Position
			local nx = cur.X.Offset + (targetX - cur.X.Offset) * a
			local ny = cur.Y.Offset + (targetY - cur.Y.Offset) * a
			frame.Position = UDim2.new(startPos.X.Scale, nx, startPos.Y.Scale, ny)
			if not dragging and math.abs(targetX - nx) < 0.4 and math.abs(targetY - ny) < 0.4 then
				frame.Position = UDim2.new(startPos.X.Scale, targetX, startPos.Y.Scale, targetY)
				stopFollow()
			end
		end)
	end

	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
			targetX, targetY = startPos.X.Offset, startPos.Y.Offset
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
			local ox = startPos.X.Offset + delta.X
			local oy = startPos.Y.Offset + delta.Y
			-- lock-to-screen: with a centered anchor/position the max travel each
			-- way is half the leftover space, so the window never leaves the view
			if clampGetter and clampGetter() and frame.Parent then
				local vp, sz = frame.Parent.AbsoluteSize, frame.AbsoluteSize
				local mx, my = math.max(0, (vp.X - sz.X) / 2), math.max(0, (vp.Y - sz.Y) / 2)
				ox = math.clamp(ox, -mx, mx)
				oy = math.clamp(oy, -my, my)
			end
			targetX, targetY = ox, oy
			local sm = smoothGetter and math.clamp(smoothGetter() or 0, 0, 1) or 0
			if sm > 0.01 then
				if not followConn then startFollow() end
			else
				frame.Position = UDim2.new(startPos.X.Scale, ox, startPos.Y.Scale, oy)
			end
		end
	end)
end

-- generic horizontal drag for sliders / channels (mouse + touch)
local function bindBarDrag(hit, onAlpha)
	local dragging = false
	local function upd(input)
		-- a destroyed element leaves these UIS connections dangling; bail if the
		-- bar is gone so an unloaded control never keeps firing callbacks
		if not hit.Parent then dragging = false; return end
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

-- Root ScreenGui + notifications
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
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 20),
		Size = UDim2.new(0, 300, 1, -40),
		BackgroundTransparency = 1,
		Parent = screenGui,
	}, {
		Create("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
	})
	return screenGui
end

-- Notifications
function NEMESIS.Notify(opts)
	opts = opts or {}
	ensureRoot()
	-- Rayfield Gen1 notification: a semi-transparent card grows its height in over
	-- 0.6s Exponential, then title / icon / description / stroke / shadow fade in
	-- staggered; on exit everything fades and the height shrinks out over 1s.
	task.spawn(function()
		local accent = opts.accent or THEME.Accent
		local iconSpec = resolveIcon(opts.icon)
		local EXP = function(t) return TweenInfo.new(t, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out) end

		local card = Create("Frame", {
			Name = "Notif",
			BackgroundColor3 = THEME.Background,
			Size = UDim2.new(1, 0, 0, 60),
			BackgroundTransparency = 1,
			Parent = notifyHolder,
		}, { corner(9), stroke(THEME.Text, 1, 1) })
		local notifStroke = card:FindFirstChildOfClass("UIStroke")
		local shadow = dropShadow(card, 1)

		local hasIcon = iconSpec ~= nil
		local textLeft = hasIcon and 60 or 18
		local img
		if hasIcon then
			img = Create("ImageLabel", {
				AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 20, 0.5, 0), Size = UDim2.new(0, 30, 0, 30),
				BackgroundTransparency = 1, ImageColor3 = THEME.Text, ImageTransparency = 1, Parent = card,
			})
			applyIcon(img, iconSpec)
		end
		local title = Create("TextLabel", {
			Name = "Title", Position = UDim2.new(0, textLeft, 0, 12), Size = UDim2.new(1, -textLeft - 16, 0, 16),
			BackgroundTransparency = 1, Font = FONT_SEMI, Text = tostring(opts.title or "Notification"),
			TextColor3 = THEME.Text, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
			TextTransparency = 1, Parent = card,
		})
		local desc = Create("TextLabel", {
			Name = "Content", Position = UDim2.new(0, textLeft, 0, 30), Size = UDim2.new(1, -textLeft - 16, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Font = FONT, Text = tostring(opts.content or ""),
			TextColor3 = THEME.Text, TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
			TextTransparency = 1, Parent = card,
		})

		-- measure text, size the card, then collapse to 0 and grow in
		task.wait()
		local tb, db = 16, 16
		pcall(function() tb = title.TextBounds.Y; db = desc.TextBounds.Y end)
		local fullH = math.max(tb + db + 31, 60)
		card.Size = UDim2.new(1, 0, 0, 0)

		tween(card, { Size = UDim2.new(1, 0, 0, fullH) }, EXP(0.6))
		task.wait(0.15)
		tween(card, { BackgroundTransparency = 0.45 }, EXP(0.4))
		tween(title, { TextTransparency = 0 }, EXP(0.3))
		task.wait(0.05)
		if img then tween(img, { ImageTransparency = 0 }, EXP(0.3)) end
		task.wait(0.05)
		tween(desc, { TextTransparency = 0.35 }, EXP(0.3))
		if notifStroke then tween(notifStroke, { Transparency = 0.95 }, EXP(0.4)) end
		if shadow then tween(shadow, { ImageTransparency = 0.82 }, EXP(0.3)) end

		local duration = tonumber(opts.duration) or math.min(math.max(#tostring(opts.content or "") * 0.1 + 2.5, 3), 10)
		task.wait(duration)

		if img then img.Visible = false end
		tween(card, { BackgroundTransparency = 1 }, EXP(0.4))
		if notifStroke then tween(notifStroke, { Transparency = 1 }, EXP(0.4)) end
		if shadow then tween(shadow, { ImageTransparency = 1 }, EXP(0.3)) end
		tween(title, { TextTransparency = 1 }, EXP(0.3))
		tween(desc, { TextTransparency = 1 }, EXP(0.3))
		tween(card, { Size = UDim2.new(1, 0, 0, 0) }, EXP(1))
		task.wait(1.05)
		if card then card:Destroy() end
	end)
end

-- NEMESIS.Modal({ title, content, confirmText, cancelText, onConfirm, onCancel }):
-- a centred confirm dialog over a dimming backdrop; grows + fades in.
function NEMESIS.Modal(opts)
	opts = opts or {}
	local gui = ensureRoot()
	local backdrop = Create("TextButton", {
		Name = "ModalBackdrop", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1, AutoButtonColor = false, Text = "", ZIndex = 60000, Parent = gui,
	})
	local scale = Create("UIScale", { Scale = 0.92 })
	local card = Create("CanvasGroup", {
		Name = "Modal", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 340, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = THEME.Group,
		GroupTransparency = 1, ZIndex = 60001, Parent = gui,
	}, {
		corner(14), stroke(THEME.Stroke, 1, 0.3), scale, padding(18),
		Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12) }),
	})
	siblingShadow(card)
	Create("TextLabel", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Font = FONT_SEMI, Text = tostring(opts.title or "Confirm"), TextColor3 = THEME.Text, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1, Parent = card })
	Create("TextLabel", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Font = FONT, Text = tostring(opts.content or opts.text or ""), TextColor3 = THEME.SubText, TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2, Parent = card })
	local btnRow = Create("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = 3, Parent = card })
	local closed = false
	local function close()
		if closed then return end; closed = true
		tween(backdrop, { BackgroundTransparency = 1 }, TI.FAST)
		tween(card, { GroupTransparency = 1 }, TI.FAST)
		tween(scale, { Scale = 0.94 }, TI.FAST)
		task.delay(0.22, function() if backdrop then backdrop:Destroy() end if card then card:Destroy() end end)
	end
	local function mkBtn(text, x, primary)
		local b = Create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(x, x == 1 and 0 or -6, 0.5, 0), Size = UDim2.new(0, 96, 0, 30),
			BackgroundColor3 = primary and THEME.Accent or THEME.Element, AutoButtonColor = false, Font = FONT_MED,
			Text = tostring(text), TextColor3 = primary and accentTextColor(THEME.Accent) or THEME.Text, TextSize = 13,
			TextTruncate = Enum.TextTruncate.AtEnd, Parent = btnRow,
		}, { corner(7), stroke(THEME.ElementStroke, 1, primary and 1 or 0.4) })
		return b
	end
	local cancel = mkBtn(opts.cancelText or "Cancel", 0.5, false)
	local confirm = mkBtn(opts.confirmText or "Confirm", 1, true)
	confirm.MouseButton1Click:Connect(function() if type(opts.onConfirm) == "function" then pcall(opts.onConfirm) end close() end)
	cancel.MouseButton1Click:Connect(function() if type(opts.onCancel) == "function" then pcall(opts.onCancel) end close() end)
	backdrop.MouseButton1Click:Connect(function() if type(opts.onCancel) == "function" then pcall(opts.onCancel) end close() end)
	tween(backdrop, { BackgroundTransparency = 0.45 }, TI.EXPAND)
	tween(card, { GroupTransparency = 0 }, TI.EXPAND)
	tween(scale, { Scale = 1 }, TI.EXPAND)
	return { Close = close }
end

-- NEMESIS.Toast({ content, duration, icon }): a small top-centre chip that slides
-- in and auto-dismisses. Lighter than Notify (which is the side card).
local toastHolder, toasts
function NEMESIS.Toast(opts)
	opts = opts or {}
	local gui = ensureRoot()
	if not (toastHolder and toastHolder.Parent) then
		toastHolder = Create("Frame", { Name = "Toasts", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.new(0, 300, 1, 0), BackgroundTransparency = 1, ZIndex = 59000, Parent = gui }, {
			Create("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Top, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		toasts = 0
	end
	toasts = (toasts or 0) + 1
	-- a plain Frame (NOT a CanvasGroup - those can white-out on executors), fading
	-- via its own + its children's transparency; no sibling shadow (which mirrors
	-- the Size property and, under AutomaticSize, renders as a stray white pill)
	local scale = Create("UIScale", { Scale = 0.9 })
	local chip = Create("Frame", {
		Size = UDim2.new(0, 0, 0, 32), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = THEME.Group,
		BackgroundTransparency = 1, LayoutOrder = -toasts, Parent = toastHolder,
	}, { corner(9), scale, padXY(12, 0), Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8) }) })
	local chipStroke = Create("UIStroke", { Color = THEME.Stroke, Thickness = 1, Transparency = 1, Parent = chip })
	local anim = { { chip, "BackgroundTransparency", 0.1 }, { chipStroke, "Transparency", 0.4 } }
	local spec = resolveIcon(opts.icon)
	if spec then local img = Create("ImageLabel", { Size = UDim2.new(0, 16, 0, 16), BackgroundTransparency = 1, ImageColor3 = THEME.Accent, ImageTransparency = 1, LayoutOrder = 1, Parent = chip }); applyIcon(img, spec); anim[#anim + 1] = { img, "ImageTransparency", 0 } end
	local txt = Create("TextLabel", { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Font = FONT_MED, Text = tostring(opts.content or opts.text or ""), TextColor3 = THEME.Text, TextTransparency = 1, TextSize = 13, LayoutOrder = 2, Parent = chip })
	anim[#anim + 1] = { txt, "TextTransparency", 0 }
	local function play(shown)
		local info = shown and TI.EXPAND or TI.FAST
		for _, a in ipairs(anim) do tween(a[1], { [a[2]] = shown and a[3] or 1 }, info) end
		tween(scale, { Scale = shown and 1 or 0.9 }, info)
	end
	play(true)
	task.delay(tonumber(opts.duration) or 2.5, function()
		if not chip.Parent then return end
		play(false)
		task.delay(0.25, function() if chip then chip:Destroy() end end)
	end)
end


-- Inline row scaffold (label on the left, control on the right)
-- Rows live inside a Section's body, separated by spacing only (no divider lines).
local function newRow(parent, height)
	local row = Create("Frame", {
		BackgroundColor3 = THEME.Group,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height or ROW_H),
		Parent = parent,
	}, { padXY(ROW_PAD, 0) })
	return row
end

-- Left-hand label (single line by default; optional muted description line).
-- reserveScale + reservePx clear room on the right for the control:
-- label width = (1 - reserveScale) scale, minus reservePx pixels.
local function rowText(parent, text, desc, reserveScale, reservePx, icon)
	reserveScale = reserveScale or 0
	reservePx = reservePx or 48
	local indent = 0
	local iconImg
	local iconSpec = resolveIcon(icon)
	if iconSpec then
		iconImg = Create("ImageLabel", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.new(0, 16, 0, 16),
			BackgroundTransparency = 1,
			ImageColor3 = THEME.SubText,
			Parent = parent,
		})
		applyIcon(iconImg, iconSpec)
		indent = 24
	end
	local lblSize = UDim2.new(1 - reserveScale, -reservePx - indent, 1, 0)
	tagSearch(parent, (desc and desc ~= "") and (tostring(text) .. " " .. tostring(desc)) or text)
	if desc and desc ~= "" then
		local col = Create("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, indent, 0, 0),
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
			Size = UDim2.new(1, 0, 0, 14),
			Font = FONT_MED,
			Text = tostring(text or ""),
			TextColor3 = THEME.Text,
			TextSize = 13,
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
		return col, iconImg
	end
	return Create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, indent, 0, 0),
		Size = lblSize,
		Font = FONT_MED,
		Text = tostring(text or ""),
		TextColor3 = THEME.Text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = parent,
	}), iconImg
end

-- Update the title of a rowText result (a plain TextLabel, or the title label
-- inside the two-line desc column).
local function setRowText(res, t)
	if not res then return end
	if res:IsA("TextLabel") then res.Text = tostring(t)
	else local tl = res:FindFirstChildWhichIsA("TextLabel"); if tl then tl.Text = tostring(t) end end
end

-- A right-aligned rounded field box (width = fraction of the row).
local function fieldBox(row, frac)
	return Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(frac or FIELD_FRAC, 0, 0, 26),
		BackgroundColor3 = THEME.Element,
		Parent = row,
	}, { corner(6), stroke(THEME.ElementStroke, 1, 0.4) })
end

-- Grows a TextBox field to fit the typed text (or the placeholder when empty),
-- between minW and maxW, then clips so long text scrolls instead of overflowing.
local function growBox(field, box, minW, maxW, pad)
	field.ClipsDescendants = true
	-- TextBounds of an empty box ignores the placeholder, so measure it separately
	local measure = Create("TextLabel", {
		BackgroundTransparency = 1, TextTransparency = 1, Visible = true,
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 0, 16),
		Position = UDim2.new(0, 0, 2, 0), Font = box.FontFace or FONT, Text = box.PlaceholderText or "",
		TextSize = box.TextSize, Parent = field,
	})
	local first = true
	local function fit()
		local tb = 0
		if box.Text ~= "" then
			pcall(function() tb = box.TextBounds.X end)
		else
			pcall(function() tb = measure.TextBounds.X end)
		end
		local y = field.Size.Y
		local target = UDim2.new(0, math.clamp(tb + pad, minW, maxW), y.Scale, y.Offset)
		-- Syde: the field grows to fit typed text over 0.7s Quint (snap the first
		-- sizing so it doesn't animate from zero on build)
		if first then field.Size = target; first = false
		else tween(field, { Size = target }, TweenInfo.new(0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)) end
	end
	box:GetPropertyChangedSignal("Text"):Connect(fit)
	box:GetPropertyChangedSignal("TextBounds"):Connect(fit)
	measure:GetPropertyChangedSignal("TextBounds"):Connect(fit)
	fit()
	return fit
end

-- Element factories: (parent, accent, opts) -> control { Set, Get }
local Elements = {}
local makeSection   -- forward declaration so nesting elements can host their own sections

function Elements.Label(parent, accent, text)
	-- text inside a subtle rounded card
	local holder = Create("Frame", {
		BackgroundColor3 = THEME.Element,
		BackgroundTransparency = 0.6,
		Size = UDim2.new(1, -ROW_PAD * 2, 0, 0),
		Position = UDim2.new(0, ROW_PAD, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, {
		corner(8),
		Create("UIPadding", {
			PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
			PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
		}),
	})
	local lbl = Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = FONT,
		Text = tostring((type(text) == "table" and text.text) or text or ""),
		TextColor3 = THEME.SubText,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = holder,
	})
	tagSearch(holder, lbl.Text)
	return {
		Set = function(v) lbl.Text = tostring(v) end,
		Get = function() return lbl.Text end,
	}
end

-- A thin horizontal divider, with an optional centred label
function Elements.Divider(parent, accent, opts)
	opts = opts or {}
	local label = (type(opts) == "table" and (opts.text or opts.title)) or nil
	-- tall row = clear breathing room above and below the line
	local row = Create("Frame", {
		Size = UDim2.new(1, -ROW_PAD * 2, 0, label and 34 or 24),
		Position = UDim2.new(0, ROW_PAD, 0, 0),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	if label then
		-- bold bright label centred between two line segments (line - text - line)
		local lbl = Create("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0, 0, 0, 15), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1, Font = FONT_SEMI, Text = string.upper(tostring(label)),
			TextColor3 = THEME.SubText, TextSize = 12, Parent = row,
		})
		local left = Create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(0, 0, 0, 1),
			BackgroundColor3 = THEME.RowDivider, BorderSizePixel = 0, Parent = row,
		})
		local right = Create("Frame", {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 0, 0, 1),
			BackgroundColor3 = THEME.RowDivider, BorderSizePixel = 0, Parent = row,
		})
		local function layout()
			local rw, tw = 0, 0
			pcall(function() rw = row.AbsoluteSize.X; tw = lbl.TextBounds.X end)
			local w = math.max(0, (rw - tw) / 2 - 12)
			left.Size = UDim2.new(0, w, 0, 1)
			right.Size = UDim2.new(0, w, 0, 1)
		end
		lbl:GetPropertyChangedSignal("TextBounds"):Connect(layout)
		row:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
		layout()
	else
		Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = THEME.RowDivider, BorderSizePixel = 0, Parent = row,
		})
	end
	return { Instance = row }
end

-- neverlose-style listbox: an always-open scrollable list of selectable items
-- (single or multi). options use the same accent-dot + slide style as dropdowns.
function Elements.Listbox(parent, accent, opts)
	opts = opts or {}
	onAccent(function(c) accent = c end)
	local options = opts.options or {}
	local multi = opts.multi and true or false
	local selected = {}
	if multi and type(opts.default) == "table" then
		for _, v in ipairs(opts.default) do selected[v] = true end
	elseif not multi and opts.default ~= nil then
		selected[opts.default] = true
	end
	local single = (not multi) and opts.default or nil
	local rows = tonumber(opts.rows) or 4

	-- wrap the caption + list box in one container so the section's list layout
	-- always renders the caption above the box, instead of leaving their order to a
	-- Name tie-break (which put the box on top)
	local wrap = Create("Frame", {
		Size = UDim2.new(1, -ROW_PAD * 2, 0, 0), Position = UDim2.new(0, ROW_PAD, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = parent,
	}, { Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }) })
	if opts.text then
		Create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1, Font = FONT_MED, Text = tostring(opts.text),
			TextColor3 = THEME.Text, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 1, Parent = wrap,
		})
	end

	local box = Create("Frame", {
		Size = UDim2.new(1, 0, 0, rows * 28 + 8), LayoutOrder = 2,
		BackgroundColor3 = THEME.Element, Parent = wrap,
	}, { corner(8), stroke(THEME.ElementStroke, 1, 0.5) })
	local holder = Create("ScrollingFrame", {
		Size = UDim2.new(1, -8, 1, -8), Position = UDim2.new(0, 4, 0, 4),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		ScrollBarImageColor3 = THEME.Faint, ScrollBarImageTransparency = 0.4,
		CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y, Parent = box,
	}, { Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }) })

	local control = {}
	local function listValues()
		local t = {}
		for _, v in ipairs(options) do if selected[v] then t[#t + 1] = v end end
		return t
	end
	local function fire()
		local val = multi and listValues() or single
		if opts.flag then NEMESIS.Flags[opts.flag] = val end
		if type(opts.callback) == "function" then pcall(opts.callback, val) end
	end

	local items = {}
	local function rebuild()
		for _, rec in ipairs(items) do rec.btn:Destroy() end
		items = {}
		for _, v in ipairs(options) do
			local ob = Create("TextButton", { Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = THEME.ElementHover, BackgroundTransparency = 1, AutoButtonColor = false, Text = "", Parent = holder }, { corner(6) })
			local dot = Create("Frame", {
				AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.new(0, 4, 0, 4),
				BackgroundColor3 = accent, BackgroundTransparency = 1, BorderSizePixel = 0, Parent = ob,
			}, { corner(1) })
			accentProp(dot, "BackgroundColor3", accent)
			local lbl = Create("TextLabel", {
				AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.new(1, -16, 0, 16),
				BackgroundTransparency = 1, Font = FONT, Text = tostring(v), TextColor3 = THEME.Text, TextTransparency = 0.35,
				TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = ob,
			})
			local function paint(animate)
				local on = selected[v] and true or false
				local info = animate and TI.SYDE_OPT or TweenInfo.new(0)
				tween(ob, { BackgroundTransparency = on and 0.55 or 1 }, info)
				tween(dot, { BackgroundTransparency = on and 0 or 1 }, info)
				tween(lbl, { TextTransparency = on and 0 or 0.35, Position = on and UDim2.new(0, 18, 0.5, 0) or UDim2.new(0, 8, 0.5, 0) }, info)
			end
			paint(false)
			ob.MouseEnter:Connect(function() if not selected[v] then tween(lbl, { TextTransparency = 0.1 }, TI.HOVER); tween(ob, { BackgroundTransparency = 0.8 }, TI.HOVER) end end)
			ob.MouseLeave:Connect(function() if not selected[v] then tween(lbl, { TextTransparency = 0.35 }, TI.HOVEROFF); tween(ob, { BackgroundTransparency = 1 }, TI.HOVEROFF) end end)
			ob.MouseButton1Click:Connect(function()
				if multi then
					selected[v] = not selected[v] or nil
				else
					selected = {}; selected[v] = true; single = v
				end
				for _, rec in ipairs(items) do rec.paint(true) end
				fire()
			end)
			items[#items + 1] = { btn = ob, paint = paint }
		end
	end
	rebuild()

	function control.Set(v)
		if multi then
			selected = {}
			if type(v) == "table" then for _, x in ipairs(v) do selected[x] = true end end
		else
			selected = {}; selected[v] = true; single = v
		end
		for _, rec in ipairs(items) do rec.paint(true) end
		fire()
	end
	function control.Get() return multi and listValues() or single end
	function control.SetOptions(newOpts) options = newOpts or {}; rebuild() end

	if opts.flag then NEMESIS.Flags[opts.flag] = control.Get() end
	bindFlag(opts.flag, control, "listbox")
	return control
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
		corner(8),
		stroke(THEME.ElementStroke, 1, 0.7),
		Create("UIPadding", {
			PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
			PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 12),
		}),
		Create("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
		Create("TextLabel", {
			Name = "Title",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 16),
			Font = FONT_SEMI,
			Text = tostring(opts.title or "Title"),
			TextColor3 = THEME.Text,
			TextSize = 13,
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
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})
	tagSearch(holder, (opts.title or "") .. " " .. (opts.content or ""))
	return {
		Set = function(v) holder:FindFirstChild("Body").Text = tostring(v) end,
		SetTitle = function(v) holder:FindFirstChild("Title").Text = tostring(v) end,
	}
end

function Elements.Button(parent, accent, opts)
	opts = opts or {}
	onAccent(function(c) accent = c end)
	local row = newRow(parent, opts.desc and 58 or ROW_H)
	local click = Create("TextButton", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, ROW_PAD * 2, 1, 0),
		Position = UDim2.new(0, -ROW_PAD, 0, 0),
		Text = "",
		Parent = row,
	})
	rowText(row, opts.text, opts.desc, 0, 90, opts.icon)
	local chipStroke = stroke(THEME.ElementStroke, 1, 0.35)
	local chip = Create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 70, 0, 22),
		BackgroundColor3 = THEME.Element,
		Font = FONT_SEMI,
		Text = tostring(opts.button or "Run"),
		TextColor3 = THEME.Text,
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	}, { corner(6), chipStroke })
	click.MouseEnter:Connect(function() tween(chip, { BackgroundColor3 = THEME.ElementHover }, TI.HOVER) end)
	click.MouseLeave:Connect(function() tween(chip, { BackgroundColor3 = THEME.Element }, TI.HOVEROFF) end)
	click.MouseButton1Down:Connect(function()
		tween(chip, { Position = UDim2.new(1, 0, 0.5, 1) }, TI.TICK)
	end)
	click.MouseButton1Up:Connect(function()
		tween(chip, { Position = UDim2.new(1, 0, 0.5, 0) }, TI.TICK)
	end)
	local control = { Instance = row }
	function control.Fire()
		-- confirmation blip: the seam flashes accent and decays
		chipStroke.Color = accent
		chipStroke.Transparency = 0
		tween(chipStroke, { Transparency = 0.35 }, TI.EXP)
		task.delay(0.16, function()
			pcall(function() chipStroke.Color = THEME.ElementStroke end)
		end)
		if type(opts.callback) == "function" then pcall(opts.callback) end
	end
	function control.SetText(t) chip.Text = tostring(t) end
	click.MouseButton1Click:Connect(control.Fire)
	return control
end

function Elements.Toggle(parent, accent, opts)
	opts = opts or {}
	onAccent(function(c) accent = c end)
	local hitbox = accent   -- fill/highlight colour; tracks accent unless overridden
	onHitbox(function(c) hitbox = c end)
	local state = opts.default and true or false
	local row = newRow(parent, opts.desc and 50 or ROW_H)
	local rowLabel, rowIconImg = rowText(row, opts.text, opts.desc, 0, 32, opts.icon)

	-- filled-icon effect: when ON, the row icon lights up (white) inside a filled
	-- accent rounded chip, the SF Symbols "filled badge" look
	local iconBg
	if rowIconImg then
		rowIconImg.ZIndex = 2
		iconBg = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 8, 0.5, 0),
			Size = UDim2.new(0, 24, 0, 24), BackgroundColor3 = hitbox, BackgroundTransparency = 1,
			BorderSizePixel = 0, ZIndex = 1, Parent = row,
		}, { corner(7) })
		hitboxProp(iconBg, "BackgroundColor3", hitbox)
	end

	-- machined checkbox: recessed off-state well, accent fill + check when on,
	-- with a soft lamp glow behind the lit box
	local lampArt = loadArt("cal1_glow_dot.png")
	local lamp
	local box = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 18, 0, 18),
		BackgroundColor3 = THEME.ToggleOff,
		Parent = row,
	}, { corner(5), stroke(THEME.ElementStroke, 1, 0.35) })
	if lampArt then
		lamp = Create("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0, 30, 0, 30),
			BackgroundTransparency = 1,
			Image = lampArt,
			ImageColor3 = accent,
			ImageTransparency = 1,
			ZIndex = 0,
			Parent = box,
		})
		onHitbox(function(c) pcall(function() lamp.ImageColor3 = c end) end)
	end
	-- Syde-style fill: a full-size accent overlay that FADES in/out (no grow),
	-- with a subtle gradient sheen. The box itself also tints to accent.
	local fillGrad = Create("UIGradient", { Rotation = 90 })
	local fill = Create("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = box,
	}, { corner(5), fillGrad })
	hitboxProp(fill, "BackgroundColor3", accent)
	hitboxGrad(fillGrad, accent)
	local check
	local checkSpec = resolveIcon("check")
	if checkSpec then
		check = Create("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0, 12, 0, 12),
			BackgroundTransparency = 1,
			ImageColor3 = accentTextColor(accent),
			ImageTransparency = 1,
			ZIndex = 2,
			Parent = box,
		})
		applyIcon(check, checkSpec)
		onHitbox(function(c) pcall(function() check.ImageColor3 = accentTextColor(c) end) end)
	end
	local click = Create("TextButton", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, ROW_PAD * 2, 1, 0),
		Position = UDim2.new(0, -ROW_PAD, 0, 0),
		Text = "",
		Parent = row,
	})

	local titleLabel = (rowLabel and rowLabel:IsA("TextLabel")) and rowLabel or nil
	local control = {}
	local function render(animate)
		-- Syde toggle: everything eases over 0.7s Exponential (fill fades, check
		-- fades, glow lamp fades, box tints, title brightens/dims)
		local info = animate and TI.SYDE or TweenInfo.new(0)
		local fadeInfo = animate and TI.SYDE_FADE or TweenInfo.new(0)
		tween(box, { BackgroundColor3 = state and hitbox or THEME.ToggleOff }, info)
		tween(fill, { BackgroundTransparency = state and 0 or 1 }, fadeInfo)
		if check then
			tween(check, { ImageTransparency = state and 0 or 1 }, info)
		end
		if lamp then
			tween(lamp, { ImageTransparency = state and 0.7 or 1 }, info)
		end
		if titleLabel then
			tween(titleLabel, { TextTransparency = state and 0 or 0.35 }, info)
		end
		if rowIconImg then
			tween(rowIconImg, { ImageColor3 = state and accentTextColor(hitbox) or THEME.SubText }, info)
		end
		if iconBg then
			tween(iconBg, { BackgroundTransparency = state and 0.1 or 1 }, fadeInfo)
		end
	end
	click.MouseEnter:Connect(function() if not state then tween(box, { BackgroundColor3 = THEME.ElementHover }, TI.HOVER) end end)
	click.MouseLeave:Connect(function() if not state then tween(box, { BackgroundColor3 = THEME.ToggleOff }, TI.HOVEROFF) end end)
	function control.Set(v, silent, instant)
		state = v and true or false
		if opts.flag then NEMESIS.Flags[opts.flag] = state end
		-- instant skips the 0.7s animation (config hydration paints the final state at
		-- once); silent skips the callback. they are independent.
		render(not instant)
		if not silent and type(opts.callback) == "function" then
			pcall(opts.callback, state)
		end
	end
	function control.Get() return state end

	click.MouseButton1Click:Connect(function() control.Set(not state) end)

	if opts.flag then NEMESIS.Flags[opts.flag] = state end
	bindFlag(opts.flag, control, "toggle")
	render(false)
	return control
end

function Elements.Slider(parent, accent, opts)
	opts = opts or {}
	onAccent(function(c) accent = c end)
	local min = tonumber(opts.min) or 0
	local max = tonumber(opts.max) or 100
	local increment = tonumber(opts.increment) or 1
	-- guard against min == max: a zero span would make every fraction 0/0 = NaN
	-- and feed NaN into UDim2 scales (invisible / broken fill on strict builds)
	local span = max - min
	if span == 0 then span = 1 end
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

	local row = newRow(parent, opts.desc and 50 or ROW_H)
	rowText(row, opts.text, opts.desc, SLIDER_FRAC, 12, opts.icon)

	local cluster = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(SLIDER_FRAC, 0, 1, 0),
		BackgroundTransparency = 1,
		Parent = row,
	})
	-- editable readout chip: mono digits so the value never jitters, click to type
	local valueStroke = stroke(THEME.ElementStroke, 1, 1)
	local valueLabel = Create("TextBox", {
		BackgroundColor3 = THEME.Element,
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.new(0, 46, 0, 20),
		Font = FONT_MONO,
		Text = fmt(value),
		TextColor3 = THEME.Text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Parent = cluster,
	}, { corner(6), valueStroke })
	valueLabel.Focused:Connect(function()
		tween(valueLabel, { BackgroundTransparency = 0 }, TI.HOVER)
		valueStroke.Color = accent
		tween(valueStroke, { Transparency = 0 }, TI.HOVER)
	end)
	local bar = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(1, -56, 0, 4),
		BackgroundColor3 = THEME.ToggleOff,
		Parent = cluster,
	}, { corner(2) })
	local fillGrad = Create("UIGradient", {})
	local fill = Create("Frame", {
		Size = UDim2.new((value - min) / span, 0, 1, 0),
		BackgroundColor3 = accent,
		Parent = bar,
	}, { fillGrad })
	conformFill(fill, bar)
	hitboxProp(fill, "BackgroundColor3", accent)
	hitboxGrad(fillGrad, accent)
	local handle = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new((value - min) / span, 0, 0.5, 0),
		Size = UDim2.new(0, 10, 0, 10),
		BackgroundColor3 = THEME.Knob,
		ZIndex = 2,
		Parent = bar,
	}, { corner(3) })
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
		local frac = (value - min) / span
		valueLabel.Text = fmt(value)
		-- the fill/handle always ease toward the target (Syde Quint catch-up), so even
		-- a drag reads as a smooth glide rather than a hard snap
		tween(fill, { Size = UDim2.new(frac, 0, 1, 0) }, TI.SYDE_SIZE)
		tween(handle, { Position = UDim2.new(frac, 0, 0.5, 0) }, TI.SYDE_SIZE)
		if opts.flag then NEMESIS.Flags[opts.flag] = value end
		if fire and type(opts.callback) == "function" then
			pcall(opts.callback, value)
		end
	end
	function control.Set(v) setFromAlpha(((tonumber(v) or min) - min) / span, true, false) end
	function control.Get() return value end

	bindBarDrag(hit, function(rel) setFromAlpha(rel, true, true) end)
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			tween(handle, { Size = UDim2.new(0, 12, 0, 12) }, TI.TICK)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			tween(handle, { Size = UDim2.new(0, 10, 0, 10) }, TI.TICK)
		end
	end)
	-- type an exact value into the number box
	valueLabel.FocusLost:Connect(function()
		tween(valueLabel, { BackgroundTransparency = 1 }, TI.HOVEROFF)
		pcall(function() valueStroke.Color = THEME.ElementStroke end)
		tween(valueStroke, { Transparency = 1 }, TI.HOVEROFF)
		local num = tonumber((valueLabel.Text:gsub("[^%d%.%-]", "")))
		if num then control.Set(num) else valueLabel.Text = fmt(value) end
	end)

	if opts.flag then NEMESIS.Flags[opts.flag] = value end
	bindFlag(opts.flag, control, "slider")
	return control
end

-- ===== shared dropdown overlay (neverlose-style floating panels) =====
local _ddCurrent = nil   -- handle of the currently open dropdown (one at a time)
local _overlayCurrent = nil  -- currently open top-level overlay (settings / AI)
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
	onAccent(function(c) accent = c end)
	local options = opts.options or {}
	-- optionFont: render each option's label in the font it names, so a font
	-- picker previews every choice in its own typeface. true = use Enum.Font[value];
	-- or pass a function(value) -> Font/Enum.Font for custom mapping.
	local optionFont = opts.optionFont
	local function fontForOption(v)
		if not optionFont then return nil end
		if type(optionFont) == "function" then
			local ok, f = pcall(optionFont, v); return ok and f or nil
		end
		local ok, f = pcall(function() return Enum.Font[tostring(v)] end)
		return ok and f or nil
	end
	local multi = opts.multi and true or false
	local selected = {}
	if multi and type(opts.default) == "table" then
		for _, v in ipairs(opts.default) do selected[v] = true end
	end
	local single = (not multi) and opts.default or nil

	local row = newRow(parent, ROW_H)
	rowText(row, opts.text, opts.desc, FIELD_FRAC, 16, opts.icon)
	local field = fieldBox(row)

	local current = Create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 0),
		Size = UDim2.new(1, -32, 1, 0),
		Font = FONT,
		Text = "...",
		TextColor3 = THEME.Text,
		TextSize = 13,
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
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.new(0, 13, 0, 13),
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
	local panelStroke = stroke(THEME.Stroke, 1, 1)
	local panel = Create("Frame", {
		Name = "NemesisDropdown",
		BackgroundColor3 = THEME.Group,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 50001,
	}, {
		corner(10),
		panelStroke,
		panelScale,
	})
	local panelShadow = dropShadow(panel, 1)
	local holder = Create("ScrollingFrame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.new(1, -12, 1, -12),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = THEME.Faint,
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
				BackgroundColor3 = THEME.ElementHover,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, OPT_H),
				AutoButtonColor = false,
				Text = "",
				ZIndex = 50003,
				Parent = holder,
			}, { corner(6) })
			local dot = Create("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 8, 0.5, 0),
				Size = UDim2.new(0, 4, 0, 4),
				BackgroundColor3 = accent,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 50004,
				Parent = ob,
			}, { corner(1) })
			accentProp(dot, "BackgroundColor3", accent)
			local olabel = Create("TextLabel", {
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 8, 0.5, 0),
				Size = UDim2.new(1, -16, 0, 16),
				Font = FONT,
				Text = tostring(v),
				TextColor3 = THEME.Text,
				TextTransparency = 1,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 50004,
				Parent = ob,
			})
			local of = fontForOption(v)
			if of then
				pcall(function() olabel.Font = of end)
				-- pin this label to its own font so a live menu-font swap can't
				-- overwrite the per-option preview
				pcall(function() olabel:SetAttribute("NemesisKeepFont", true) end)
			end
			local function apply(animate, visible)
				local on = multi and selected[v] or (single == v)
				local info = animate and TI.SYDE_OPT or TweenInfo.new(0)
				tween(ob, { BackgroundTransparency = (visible and on) and 0.55 or 1 }, info)
				tween(dot, { BackgroundTransparency = (visible and on) and 0 or 1 }, info)
				tween(olabel, {
					TextTransparency = visible and (on and 0 or 0.35) or 1,
					Position = on and UDim2.new(0, 18, 0.5, 0) or UDim2.new(0, 8, 0.5, 0),
				}, info)
			end
			apply(false, false)
			ob.MouseEnter:Connect(function()
				local on = multi and selected[v] or (single == v)
				if open and not on then
					tween(olabel, { TextTransparency = 0.1 }, TI.HOVER)
					tween(ob, { BackgroundTransparency = 0.8 }, TI.HOVER)
				end
			end)
			ob.MouseLeave:Connect(function()
				local on = multi and selected[v] or (single == v)
				if open and not on then
					tween(olabel, { TextTransparency = 0.35 }, TI.HOVER)
					tween(ob, { BackgroundTransparency = 1 }, TI.HOVER)
				end
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
	local trackConn, outsideConn
	local function fadePanel(opening)
		tween(panel, { BackgroundTransparency = opening and 0 or 1 }, FADE)
		tween(panelStroke, { Transparency = opening and 0.15 or 1 }, FADE)
		if panelShadow then tween(panelShadow, { ImageTransparency = opening and 0.35 or 1 }, FADE) end
		tween(holder, { ScrollBarImageTransparency = opening and 0.4 or 1 }, FADE)
		-- Syde-style cascade: options reveal top-down with a tiny incrementing
		-- delay so the list unfurls rather than popping all at once
		for i, rec in ipairs(optionButtons) do
			if opening then
				task.delay((i - 1) * 0.03, function() if open then rec.apply(true, true) end end)
			else
				rec.apply(true, false)
			end
		end
	end
	local function track()
		local fp, fs = field.AbsolutePosition, field.AbsoluteSize
		local s = fs.Y / 26
		if s <= 0 then s = 1 end
		panelScale.Scale = s
		local logicalH = math.clamp(#options * (OPT_H + 3) + 9, OPT_H + 12, PANEL_MAXH)
		panel.Size = UDim2.fromOffset(fs.X / s, logicalH)
		-- open below the field, but flip above when it would spill past the bottom,
		-- then clamp fully into the viewport so the option list is never cut off
		local renderedH = logicalH * s
		local vp = viewportSize()
		local px, py = fp.X, fp.Y + fs.Y + 6
		if py + renderedH > vp.Y - 8 then py = fp.Y - renderedH - 6 end
		px = math.clamp(px, 8, math.max(8, vp.X - fs.X - 8))
		py = math.clamp(py, 8, math.max(8, vp.Y - renderedH - 8))
		panel.Position = UDim2.fromOffset(px, py)
	end
	local ddHandle = {}
	local function setOpen(b)
		if b == open then return end
		open = b
		-- arrow flips over 0.35 Quint, exactly like Syde's dropdown chevron
		tween(arrow, { Rotation = open and 180 or 0 }, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
		tween(arrow, { [arrowColorProp] = open and accent or THEME.SubText }, TI.FAST)
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
			-- click anywhere outside the panel or the field closes the dropdown
			if outsideConn then outsideConn:Disconnect() end
			outsideConn = UserInputService.InputBegan:Connect(function(input)
				if not panel.Parent then if outsideConn then outsideConn:Disconnect(); outsideConn = nil end return end
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
				local p = input.Position
				local function inside(inst)
					local ap, as = inst.AbsolutePosition, inst.AbsoluteSize
					return p.X >= ap.X and p.X <= ap.X + as.X and p.Y >= ap.Y and p.Y <= ap.Y + as.Y
				end
				if not inside(panel) and not inside(field) then setOpen(false) end
			end)
			fadePanel(true)
		else
			if _ddCurrent == ddHandle then _ddCurrent = nil end
			if trackConn then trackConn:Disconnect(); trackConn = nil end
			if outsideConn then outsideConn:Disconnect(); outsideConn = nil end
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
	bindFlag(opts.flag, control, "dropdown")
	return control
end
function Elements.Input(parent, accent, opts)
	opts = opts or {}
	onAccent(function(c) accent = c end)
	local row = newRow(parent, ROW_H)
	rowText(row, opts.text, opts.desc, FIELD_FRAC, 16, opts.icon)
	-- starts small, grows with the text up to a cap, then clips
	-- (past the cap the front scrolls off instead of spilling outside the field)
	local MIN_W, MAX_W = 84, 220
	local field = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, MIN_W, 0, 26),
		BackgroundColor3 = THEME.Element,
		ClipsDescendants = true,
		Parent = row,
	}, { corner(6), stroke(THEME.ElementStroke, 1, 0.4) })
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
	function control.Set(v)
		box.Text = tostring(v)
		if opts.flag then NEMESIS.Flags[opts.flag] = box.Text end
		if type(opts.callback) == "function" then pcall(opts.callback, box.Text) end
	end
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
	bindFlag(opts.flag, control, "input")
	return control
end

-- Keybind (supports keyboard KeyCodes and mouse buttons via strings)
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
	onAccent(function(c) accent = c end)
	local mode = opts.mode or "Toggle"
	local key = opts.default
	local row = newRow(parent, ROW_H)
	rowText(row, opts.text, opts.desc, FIELD_FRAC, 16, opts.icon)
	-- Syde keybind: a pill that auto-sizes to fit the key text and thickens its
	-- stroke while listening
	local field = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 54, 0, 26),
		BackgroundColor3 = THEME.Element,
		Parent = row,
	}, { corner(6), stroke(THEME.ElementStroke, 1, 0.4) })
	local fieldStroke = field:FindFirstChildOfClass("UIStroke")
	local btn = Create("TextButton", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Font = FONT_MONO,
		Text = string.upper(keyDisplay(key)),
		TextColor3 = THEME.Text,
		TextSize = 12,
		AutoButtonColor = false,
		Parent = field,
	})
	local function fitPill()
		local tb = 40
		pcall(function() tb = btn.TextBounds.X end)
		tween(field, { Size = UDim2.new(0, math.clamp(tb + 24, 54, 160), 0, 26) }, TI.SYDE_SIZE)
	end
	btn:GetPropertyChangedSignal("TextBounds"):Connect(fitPill)
	task.defer(fitPill)

	local listening = false
	local toggled = false
	local prevKey = nil        -- restored if a rebind is cancelled
	local swallowClick = false -- eat the click that binds MOUSE1 so it doesn't re-arm
	local control = {}
	function control.Set(v)
		key = v
		btn.Text = string.upper(keyDisplay(key))
		btn.TextColor3 = THEME.Text
		if fieldStroke then tween(fieldStroke, { Color = THEME.ElementStroke, Thickness = 1 }, TI.EXP) end
		fitPill()
		if opts.flag then NEMESIS.Flags[opts.flag] = key end
	end
	function control.Get() return key end

	btn.MouseButton1Click:Connect(function()
		if swallowClick then swallowClick = false; return end
		prevKey = key
		listening = true
		btn.Text = "..."
		btn.TextColor3 = accent
		if fieldStroke then tween(fieldStroke, { Color = accent, Thickness = 1.6 }, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)) end
	end)
	-- right-click the pill to clear the bind (listening state uses right-click for MOUSE2)
	btn.MouseButton2Click:Connect(function()
		if not listening then control.Set(nil) end
	end)
	UserInputService.InputBegan:Connect(function(input, gpe)
		-- these UIS connections outlive the control; bail (and disarm) once the
		-- keybind is gone so a destroyed menu never keeps firing its callback
		if not btn.Parent then listening = false; return end
		if listening then
			if input.UserInputType == Enum.UserInputType.Keyboard then
				listening = false
				-- Escape backs out of the rebind without wiping the existing key
				if input.KeyCode == Enum.KeyCode.Escape then control.Set(prevKey) else control.Set(input.KeyCode) end
				return
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
				listening = false; control.Set("MOUSE2"); return
			elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
				listening = false; control.Set("MOUSE3"); return
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				listening = false
				-- clicking the pill itself binds left-click; a click anywhere else cancels
				local p, fp, fs = input.Position, field.AbsolutePosition, field.AbsoluteSize
				if p.X >= fp.X and p.X <= fp.X + fs.X and p.Y >= fp.Y and p.Y <= fp.Y + fs.Y then
					swallowClick = true; control.Set("MOUSE1")
				else
					control.Set(prevKey)
				end
				return
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
		if not btn.Parent then return end
		if mode == "Hold" and inputMatchesKey(input, key) then
			if type(opts.callback) == "function" then pcall(opts.callback, false) end
		end
	end)

	if opts.flag then NEMESIS.Flags[opts.flag] = key end
	bindFlag(opts.flag, control, "keybind")
	return control
end

-- Color picker (full pop-out panel: SV square, hue, alpha, HEX)
function Elements.ColorPicker(parent, accent, opts)
	opts = opts or {}
	onAccent(function(c) accent = c end)
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
	-- mode: Single (one colour), Double (two colours), Multi (many stops).
	-- "gradient = true" is the old name for Double; "multi = true" starts on Multi.
	-- two sections only: Single (one colour) and Multiple (a multi-stop gradient).
	-- legacy "Double" / opts.gradient collapses into Multiple.
	local mode = opts.mode or (opts.multi and "Multi") or (opts.gradient and "Multi") or "Single"
	if mode == "Double" then mode = "Multi" end
	local MODES = { Single = 1, Multi = 2 }
	local isGradient = false
	local active = 1        -- active slot index (Single/Double)
	local activeStop = 1    -- active stop index (Multi)
	local saved = {}

	-- Multi stops: each { pos, h, s, v }. Seed from opts.stops/colors or a default.
	local stops = {}
	local function addStopHSV(pos, color)
		local hh, ss, vv = color:ToHSV()
		stops[#stops + 1] = { pos = math.clamp(pos, 0, 1), h = hh, s = ss, v = vv }
	end
	if type(opts.stops) == "table" and #opts.stops >= 2 then
		for _, st in ipairs(opts.stops) do
			if typeof(st.color or st[2]) == "Color3" then addStopHSV(tonumber(st.pos or st[1]) or 0, st.color or st[2]) end
		end
	elseif type(opts.colors) == "table" and #opts.colors >= 2 then
		local n = #opts.colors
		for i, c in ipairs(opts.colors) do
			if typeof(c) == "Color3" then addStopHSV((i - 1) / (n - 1), c) end
		end
	end
	if #stops < 2 then
		stops = {}
		addStopHSV(0, slotFrom and Color3.fromHSV(slots[1].h, slots[1].s, slots[1].v) or Color3.fromRGB(150, 85, 255))
		addStopHSV(1, Color3.fromRGB(60, 140, 255))
	end

	local function slotColor(i) return Color3.fromHSV(slots[i].h, slots[i].s, slots[i].v) end
	local function stopColor(i) return Color3.fromHSV(stops[i].h, stops[i].s, stops[i].v) end
	-- the colour object the SV/hue/alpha editors point at, mode-aware
	local function cur()
		if mode == "Multi" then return stops[activeStop] end
		return slots[active]
	end
	local function sortedStops()
		local t = {}
		for _, st in ipairs(stops) do t[#t + 1] = st end
		table.sort(t, function(a, b) return a.pos < b.pos end)
		return t
	end
	local function multiSequence()
		local sorted = sortedStops()
		local n = #sorted
		if n < 2 then
			return ColorSequence.new(slotColor(1), slotColor(1))
		end
		-- Roblox requires the first keypoint at time=0 and the last at time=1,
		-- strictly increasing in between. Force the endpoints and keep the middle
		-- keypoints monotonic without ever reaching 1.
		local kps, lastT = {}, -1
		for i, st in ipairs(sorted) do
			local t
			if i == 1 then t = 0
			elseif i == n then t = 1
			else t = math.clamp(st.pos, 0, 1) end
			if t <= lastT then t = lastT + 0.001 end
			if i < n and t >= 1 then t = 1 - (n - i) * 0.001 end
			lastT = t
			kps[#kps + 1] = ColorSequenceKeypoint.new(math.clamp(t, 0, 1), Color3.fromHSV(st.h, st.s, st.v))
		end
		return ColorSequence.new(kps)
	end

	local row = newRow(parent, ROW_H)
	rowText(row, opts.text, opts.desc, 0, 76, opts.icon)

	-- soft colour glow behind the swatch (gen2 look); made before sw1 so it renders behind it
	local swGlowArt = loadArt("cal1_glow_dot.png")
	local sw1Glow = swGlowArt and Create("ImageLabel", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 3, 0.5, 0), Size = UDim2.new(0, 50, 0, 34),
		BackgroundTransparency = 1, Image = swGlowArt, ImageColor3 = slotColor(1), ImageTransparency = 0.5, Parent = row,
	}) or nil
	local sw1 = Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 36, 0, 20), BackgroundColor3 = slotColor(1),
		Text = "", AutoButtonColor = false, Parent = row,
	}, { corner(6), stroke(THEME.ElementStroke, 1, 0.25) })
	-- vertical gradient fill: lighter top -> colour bottom in Single, the full gradient in Multi
	local sw1Grad = Create("UIGradient", { Rotation = 90, Parent = sw1 })
	local sw2 = Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -24, 0.5, 0),
		Size = UDim2.new(0, 20, 0, 18), BackgroundColor3 = slotColor(2),
		Text = "", AutoButtonColor = false, Visible = false, Parent = row,
	}, { corner(3), stroke(THEME.ElementStroke, 1, 0.2) })
	local function layoutSwatches()
		sw2.Visible = false
		sw1.Size = UDim2.new(0, 36, 0, 20)
	end
	layoutSwatches()

	local control = {}
	local panel, svBase, svDot, hueDot, alphaBar, alphaDot, hexBox, pctLabel
	local headSwatch, headHex, slotRow, setModeVisual, setSlotVisual, rebuildSaved
	local cpScale, cpOpenPos
	local backdrop, openPanel
	local cpHandle = {}
	local opened = false
	local railDragIdx = nil

	local function paintSwatch()
		if mode == "Multi" then
			sw1Grad.Color = multiSequence()
			if sw1Glow then sw1Glow.ImageColor3 = stopColor(1) end
		else
			local c1 = slotColor(1)
			sw1Grad.Color = ColorSequence.new(accentLight(c1), c1)
			if sw1Glow then sw1Glow.ImageColor3 = c1 end
		end
	end
	local function commit()
		sw1.BackgroundColor3 = slotColor(1)
		sw2.BackgroundColor3 = slotColor(2)
		paintSwatch()
		local value, al
		if mode == "Multi" then
			value = multiSequence()
			al = nil
		elseif mode == "Double" then
			value = { slotColor(1), slotColor(2) }
			al = { slots[1].alpha, slots[2].alpha }
		else
			value = slotColor(1)
			al = slots[1].alpha
		end
		-- primary: a single Color3 that always tracks the colour being edited, so
		-- single-colour consumers keep updating live even in Double / Multi mode
		local c = cur()
		local primary = Color3.fromHSV(c.h, c.s, c.v)
		if opts.flag then NEMESIS.Flags[opts.flag] = value end
		if type(opts.callback) == "function" then pcall(opts.callback, value, al, primary) end
	end
	local refreshRailRef  -- set when the panel (and its rail) exist
	local function syncUI()
		local c = cur()
		local col = Color3.fromHSV(c.h, c.s, c.v)
		if mode == "Multi" then
			sw1.BackgroundColor3 = stopColor(1)
		elseif active == 1 then sw1.BackgroundColor3 = col else sw2.BackgroundColor3 = col end
		paintSwatch()
		if svBase then svBase.BackgroundColor3 = Color3.fromHSV(c.h, 1, 1) end
		if svDot then svDot.Position = UDim2.new(c.s, 0, 1 - c.v, 0) end
		if hueDot then hueDot.Position = UDim2.new(c.h, 0, 0.5, 0) end
		if alphaBar then alphaBar.BackgroundColor3 = col end
		if alphaDot then alphaDot.Position = UDim2.new(1 - (c.alpha or 0), 0, 0.5, 0) end
		if hexBox then hexBox.Text = "#" .. hexOf(col) end
		if headSwatch then headSwatch.BackgroundColor3 = col end
		if headHex then headHex.Text = "#" .. hexOf(col) end
		if pctLabel then pctLabel.Text = tostring(math.floor((1 - (c.alpha or 0)) * 100 + 0.5)) .. "%" end
		if refreshRailRef and mode == "Multi" then refreshRailRef() end
	end
	local function setColor(col)
		local c = cur()
		c.h, c.s, c.v = col:ToHSV()
		syncUI(); commit()
	end

	-- a segmented control over N options: a sliding accent thumb marks the active
	-- one and glides between them (returns the frame + a setter)
	local function segmented(width, options, onPick)
		local n = #options
		local frame = Create("Frame", {
			Size = UDim2.new(0, width, 0, 22), BackgroundColor3 = THEME.Element,
			Parent = nil,
		}, { corner(6), stroke(THEME.ElementStroke, 1, 0.4) })
		local thumb = Create("Frame", {
			Size = UDim2.new(1 / n, -6, 1, -6), Position = UDim2.new(0, 3, 0, 3),
			BackgroundColor3 = accent, BackgroundTransparency = 0.12, BorderSizePixel = 0,
			ZIndex = 1, Parent = frame,
		}, { corner(4) })
		accentProp(thumb, "BackgroundColor3", accent)
		local sel = 1
		local btns = {}
		local paint   -- forward-declared so the button clicks can drive the slide
		for i, label in ipairs(options) do
			local b = Create("TextButton", {
				Size = UDim2.new(1 / n, 0, 1, 0), Position = UDim2.new((i - 1) / n, 0, 0, 0),
				BackgroundTransparency = 1, AutoButtonColor = false,
				Font = FONT_MED, Text = label, TextColor3 = THEME.SubText, TextSize = 12,
				ZIndex = 2, Parent = frame,
			})
			btns[i] = b
			b.MouseButton1Click:Connect(function() sel = i; paint(true); onPick(i) end)
		end
		paint = function(animate)
			local info = animate == false and TweenInfo.new(0) or TI.SYDE_SIZE
			tween(thumb, { Position = UDim2.new((sel - 1) / n, 3, 0, 3) }, info)
			for i, b in ipairs(btns) do
				tween(b, { TextColor3 = i == sel and accentTextColor(accent) or THEME.SubText }, TI.FAST)
			end
		end
		paint(false)
		return frame, function(i) sel = i; paint(true) end
	end

	local function buildPanel()
		backdrop = Create("TextButton", {
			Name = "ColorBackdrop", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
			AutoButtonColor = false, Text = "", Visible = false, ZIndex = 50000, Parent = screenGui,
		})
		backdrop.MouseButton1Click:Connect(function() openPanel(false) end)
		local panelScale = Create("UIScale", { Scale = 1 })
		panel = Create("CanvasGroup", {
			Name = "ColorPanel", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 300, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = THEME.Group,
			GroupTransparency = 1, Visible = false, ZIndex = 50001, Parent = screenGui,
		}, {
			corner(12), stroke(THEME.Stroke, 1, 0.3), panelScale,
		})
		siblingShadow(panel)
		cpScale = panelScale
		-- absorb taps on empty panel areas so they don't fall through to the backdrop
		Create("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, AutoButtonColor = false, Text = "", ZIndex = 1, Parent = panel })
		local content = Create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 2, Parent = panel }, {
			padding(12),
			Create("UIListLayout", { Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder }),
		})

		-- header: live swatch + hex + mode toggle
		local head = Create("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, LayoutOrder = 1, Parent = content })
		headSwatch = Create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(0, 22, 0, 18),
			BackgroundColor3 = slotColor(active), Parent = head,
		}, { corner(3), stroke(THEME.ElementStroke, 1, 0.3) })
		headHex = Create("TextLabel", {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 30, 0.5, 0), Size = UDim2.new(0, 90, 1, 0),
			BackgroundTransparency = 1, Font = FONT_MONO, Text = "#FFFFFF", TextColor3 = THEME.Text, TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left, Parent = head,
		})
		local applyMode  -- forward decl, defined after the rail exists
		local modeSeg
		modeSeg, setModeVisual = segmented(148, { "Single", "Multiple" }, function(i)
			mode = (i == 2) and "Multi" or "Single"
			active = 1
			applyMode(true)
			syncUI(); commit()
		end)
		modeSeg.AnchorPoint = Vector2.new(1, 0.5)
		modeSeg.Position = UDim2.new(1, 0, 0.5, 0)
		modeSeg.Parent = head
		setModeVisual(MODES[mode] or 1)
		-- GradientPicker locks to Multi: hide the mode switch so it cannot collapse to a flat colour
		if opts.lockMode then modeSeg.Visible = false end

		-- slot selector (Double only): First / Second
		local slotSeg
		slotSeg, setSlotVisual = segmented(160, { "First", "Second" }, function(i)
			active = i; setSlotVisual(i); syncUI()
		end)
		slotRow = Create("Frame", { Size = UDim2.new(1, 0, 0, isGradient and 22 or 0), BackgroundTransparency = 1, LayoutOrder = 2, Visible = isGradient, Parent = content })
		slotSeg.AnchorPoint = Vector2.new(0.5, 0.5)
		slotSeg.Position = UDim2.new(0.5, 0, 0.5, 0)
		slotSeg.Parent = slotRow

		-- Multi rail: preview gradient + draggable stop handles (click empty to add,
		-- right-click a handle to remove). Visible only in Multi mode.
		local railRow = Create("Frame", { Size = UDim2.new(1, 0, 0, mode == "Multi" and 40 or 0), BackgroundTransparency = 1, Visible = mode == "Multi", LayoutOrder = 2, ClipsDescendants = true, Parent = content })
		-- inset both the preview and the handle rail by 7px so the end stops (pos 0
		-- and 1) sit fully inside the panel instead of being clipped at the edges
		local preview = Create("Frame", { Size = UDim2.new(1, -14, 0, 16), Position = UDim2.new(0, 7, 0, 0), BackgroundColor3 = Color3.new(1, 1, 1), Parent = railRow }, { corner(5), stroke(THEME.ElementStroke, 1, 0.5) })
		local previewGrad = Create("UIGradient", { Parent = preview })
		local rail = Create("TextButton", { Size = UDim2.new(1, -14, 0, 18), Position = UDim2.new(0, 7, 0, 20), BackgroundTransparency = 1, AutoButtonColor = false, Text = "", Parent = railRow })
		local handleFrames = {}
		local refreshRail
		local function stopHandleColor(i) return Color3.fromHSV(stops[i].h, stops[i].s, stops[i].v) end
		refreshRail = function()
			previewGrad.Color = multiSequence()
			for _, h in ipairs(handleFrames) do h:Destroy() end
			handleFrames = {}
			for i, st in ipairs(stops) do
				local h = Create("TextButton", {
					AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(st.pos, 0, 0.5, 0),
					Size = UDim2.new(0, 12, 0, 12), BackgroundColor3 = stopHandleColor(i), AutoButtonColor = false,
					Text = "", ZIndex = 3, Parent = rail,
				}, { corner(6), stroke(i == activeStop and accent or Color3.fromRGB(240, 240, 244), 2, 0) })
				handleFrames[i] = h
				h.MouseButton1Down:Connect(function()
					activeStop = i; refreshRail(); syncUI()
					railDragIdx = i
				end)
				h.MouseButton2Click:Connect(function()
					if #stops > 2 then
						table.remove(stops, i)
						activeStop = math.clamp(activeStop, 1, #stops)
						refreshRail(); syncUI(); commit()
					end
				end)
			end
		end
		rail.MouseButton1Click:Connect(function()
			if railDragIdx then railDragIdx = nil; return end
			if #stops >= 12 then return end
			local rel = 0.5
			pcall(function() rel = math.clamp((UserInputService:GetMouseLocation().X - rail.AbsolutePosition.X) / math.max(rail.AbsoluteSize.X, 1), 0, 1) end)
			addStopHSV(rel, Color3.fromHSV(cur().h, cur().s, cur().v))
			activeStop = #stops
			refreshRail(); syncUI(); commit()
		end)
		refreshRailRef = refreshRail
		refreshRail()
		-- drag a handle along the rail
		UserInputService.InputChanged:Connect(function(input)
			if not rail.Parent then railDragIdx = nil; return end
			if railDragIdx and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local rel = 0.5
				pcall(function() rel = math.clamp((input.Position.X - rail.AbsolutePosition.X) / math.max(rail.AbsoluteSize.X, 1), 0, 1) end)
				stops[railDragIdx].pos = rel
				refreshRail(); commit()
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				railDragIdx = nil
			end
		end)

		-- switch which editor rows are shown for the active mode; the rows grow /
		-- collapse (Syde reflow) instead of snapping so the switch reads smoothly
		function applyMode(animate)
			local info = animate and TI.SYDE_REFLOW or TweenInfo.new(0)
			local dW = (mode == "Double") and 22 or 0
			local dH = (mode == "Multi") and 40 or 0
			slotRow.ClipsDescendants = true; railRow.ClipsDescendants = true
			slotRow.Visible = true; railRow.Visible = true
			tween(slotRow, { Size = UDim2.new(1, 0, 0, dW) }, info)
			tween(railRow, { Size = UDim2.new(1, 0, 0, dH) }, info)
			layoutSwatches()
			if mode == "Multi" then refreshRail() end
		end
		applyMode()

		-- SV square (matched 8px corners on every layer + a clean boundary stroke)
		local sv = Create("Frame", { Size = UDim2.new(1, 0, 0, 148), BackgroundColor3 = Color3.fromHSV(cur().h, 1, 1), LayoutOrder = 3, Parent = content }, { corner(3), stroke(THEME.ElementStroke, 1, 0.4) })
		svBase = sv
		Create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), Parent = sv }, { corner(3), Create("UIGradient", { Transparency = numSeq(0, 1) }) })
		Create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), Parent = sv }, { corner(3), Create("UIGradient", { Rotation = 90, Transparency = numSeq(1, 0) }) })
		-- ring cursor: baked ring art when available, plain white ring otherwise
		local ringArt = loadArt("cal1_ring.png")
		if ringArt then
			svDot = Create("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(cur().s, 0, 1 - cur().v, 0), Size = UDim2.new(0, 14, 0, 14),
				BackgroundTransparency = 1, Image = ringArt, ZIndex = 52, Parent = sv,
			})
		else
			svDot = Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(cur().s, 0, 1 - cur().v, 0), Size = UDim2.new(0, 13, 0, 13),
				BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, ZIndex = 52, Parent = sv,
			}, { corner(7), stroke(Color3.new(1, 1, 1), 2, 0) })
		end
		local svHit = Create("TextButton", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Text = "", ZIndex = 53, Parent = sv })
		do
			local dragging = false
			local function upd(input)
				if not sv.Parent then dragging = false; return end
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

		local hue = Create("Frame", { Size = UDim2.new(1, 0, 0, 10), LayoutOrder = 4, Parent = content }, { corner(2), Create("UIGradient", { Color = hueSequence() }) })
		hueDot = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(cur().h, 0, 0.5, 0), Size = UDim2.new(0, 10, 0, 14), BackgroundColor3 = THEME.Knob, ZIndex = 52, Parent = hue }, { corner(3), stroke(Color3.fromRGB(10, 11, 14), 1, 0.35) })
		bindBarDrag(hue, function(rel) cur().h = rel; syncUI(); commit() end)

		local alphaWell = Create("Frame", { Size = UDim2.new(1, 0, 0, 10), BackgroundTransparency = 1, LayoutOrder = 5, Parent = content })
		local checkerArt = loadArt("cal1_checker.png")
		if checkerArt then
			Create("ImageLabel", {
				Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Image = checkerArt,
				ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.new(0, 10, 0, 10), Parent = alphaWell,
			}, { corner(2) })
		end
		alphaBar = Create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = slotColor(active), ZIndex = 51, Parent = alphaWell }, { corner(2), Create("UIGradient", { Transparency = numSeq(0, 1) }) })
		alphaDot = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1 - (cur().alpha or 0), 0, 0.5, 0), Size = UDim2.new(0, 10, 0, 14), BackgroundColor3 = THEME.Knob, ZIndex = 52, Parent = alphaBar }, { corner(3), stroke(Color3.fromRGB(10, 11, 14), 1, 0.35) })
		bindBarDrag(alphaBar, function(rel) if mode ~= "Multi" then cur().alpha = 1 - rel; syncUI(); commit() end end)

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
			Size = UDim2.new(1, 0, 0, 76), BackgroundTransparency = 1, BorderSizePixel = 0,
			ScrollBarThickness = 3, ScrollBarImageColor3 = THEME.Faint, ScrollBarImageTransparency = 0.4,
			CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y, LayoutOrder = 6, Parent = content,
		})
		local grid = Create("Frame", { Size = UDim2.new(1, -10, 0, 0), Position = UDim2.new(0, 2, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = gridWrap }, {
			Create("UIGridLayout", { CellSize = UDim2.new(0, 28, 0, 18), CellPadding = UDim2.new(0, 6, 0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local function swatchTile(color, order, kind, savedIdx)
			local t = Create("TextButton", {
				BackgroundColor3 = (kind == "add") and THEME.Element or color, AutoButtonColor = false,
				Text = (kind == "add") and "+" or "", Font = FONT_SEMI, TextColor3 = THEME.SubText, TextSize = 14,
				LayoutOrder = order, Parent = grid,
			}, { corner(2), stroke(THEME.ElementStroke, 1, 0.4) })
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
			BackgroundTransparency = 1, Size = UDim2.new(0, 60, 1, 0), Font = FONT_SEMI, Text = "CUSTOM",
			TextColor3 = THEME.SubText, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Parent = hexRow,
		})
		hexBox = Create("TextBox", {
			Position = UDim2.new(0, 64, 0, 0), Size = UDim2.new(1, -110, 1, 0), BackgroundColor3 = THEME.Element,
			Font = FONT_MONO, Text = "#FFFFFF", TextColor3 = THEME.Text, TextSize = 12, ClipsDescendants = true,
			TextTruncate = Enum.TextTruncate.AtEnd, Parent = hexRow,
		}, { corner(3), stroke(THEME.ElementStroke, 1, 0.3), padding(6) })
		pctLabel = Create("TextLabel", {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 40, 1, 0),
			BackgroundTransparency = 1, Font = FONT_MONO, Text = "100%", TextColor3 = THEME.SubText, TextSize = 12,
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
			-- anchor the panel just under the swatch, then clamp it fully inside
			-- the viewport with a margin so it is never off-screen or clipped
			local pw, ph = panel.AbsoluteSize.X, panel.AbsoluteSize.Y
			if pw <= 0 then pw = 300 end
			if ph <= 0 then ph = 400 end
			local vp = viewportSize()
			local sx, sy, sh = vp.X * 0.5 - pw / 2, vp.Y * 0.5 - ph / 2, 0
			pcall(function()
				local p, s = sw1.AbsolutePosition, sw1.AbsoluteSize
				sx = p.X + s.X - pw           -- right-align the panel to the swatch
				sy = p.Y + s.Y + 8            -- just below the swatch
				sh = s.Y
			end)
			-- flip above the swatch if it would spill off the bottom
			if sy + ph > vp.Y - 12 then sy = sy - ph - sh - 16 end
			sx = math.clamp(sx, 12, math.max(12, vp.X - pw - 12))
			sy = math.clamp(sy, 12, math.max(12, vp.Y - ph - 12))
			-- centre-anchored: convert the top-left target to a centre point
			local cx, cy = sx + pw / 2, sy + ph / 2
			cpOpenPos = Vector2.new(cx, cy)
			panel.Position = UDim2.fromOffset(cx, cy + 10)
			panel.GroupTransparency = 1
			if cpScale then cpScale.Scale = 0.92 end
			backdrop.Visible = true
			panel.Visible = true
			-- match Syde's settings panel: grow (0.92 -> 1) + fade + slide up, all on EXPAND
			tween(panel, { GroupTransparency = 0, Position = UDim2.fromOffset(cx, cy) }, TI.EXPAND)
			if cpScale then tween(cpScale, { Scale = 1 }, TI.EXPAND) end
		else
			if _ddCurrent == cpHandle then _ddCurrent = nil end
			tween(panel, { GroupTransparency = 1 }, TI.FAST)
			if cpScale then tween(cpScale, { Scale = 0.94 }, TI.FAST) end
			backdrop.Visible = false
			task.delay(0.18, function()
				if not opened then panel.Visible = false end
			end)
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
	-- Double mode was removed; a two-colour gradient is now a 2-stop Multiple
	function control.SetGradient(c1, c2)
		control.SetMulti({ c1 or slotColor(1), c2 or slotColor(2) })
	end
	-- SetMulti(seq_or_colorlist): switch to Multi mode with these stops
	function control.SetMulti(seqOrList)
		mode = "Multi"; isGradient = false
		stops = {}
		if typeof(seqOrList) == "ColorSequence" then
			for _, kp in ipairs(seqOrList.Keypoints) do addStopHSV(kp.Time, kp.Value) end
		elseif type(seqOrList) == "table" then
			local n = #seqOrList
			for i, c in ipairs(seqOrList) do
				if typeof(c) == "Color3" then addStopHSV(n > 1 and (i - 1) / (n - 1) or 0, c) end
			end
		end
		if #stops < 2 then addStopHSV(0, slotColor(1)); addStopHSV(1, Color3.fromRGB(60, 140, 255)) end
		activeStop = 1
		if setModeVisual then setModeVisual(3) end
		if applyMode then applyMode() end
		if panel then syncUI() end; commit()
	end
	function control.Get()
		if mode == "Multi" then return multiSequence() end
		if mode == "Double" then return { slotColor(1), slotColor(2) } end
		return slotColor(1)
	end
	function control.GetAlpha()
		if mode == "Double" then return { slots[1].alpha, slots[2].alpha } end
		return slots[1].alpha
	end
	function control.GetMode() return mode end
	-- config serialization access
	control._cpGetStops = function()
		local t = {}
		for _, st in ipairs(stops) do
			local c = Color3.fromHSV(st.h, st.s, st.v)
			t[#t + 1] = { pos = st.pos, r = math.floor(c.R * 255 + 0.5), g = math.floor(c.G * 255 + 0.5), b = math.floor(c.B * 255 + 0.5) }
		end
		return t
	end

	commit()
	bindFlag(opts.flag, control, "colorpicker")
	return control
end

-- ===== extra elements (chart / progress / decorative / container primitives) =====

-- Spacer: blank vertical gap for breathing room. opts.height (px) or a number.
function Elements.Spacer(parent, accent, opts)
	local h = (type(opts) == "number" and opts) or (type(opts) == "table" and tonumber(opts.height)) or 10
	local row = Create("Frame", { Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1, Parent = parent })
	return { Instance = row }
end

-- ProgressBar: a labelled bar that fills to a value. opts { text, value(0..1 or
-- 0..100), min, max, suffix, icon }. Returns Set(v)/Get(). Fill eases in.
function Elements.ProgressBar(parent, accent, opts)
	opts = opts or {}
	onAccent(function(c) accent = c end)
	local min = tonumber(opts.min) or 0
	local max = tonumber(opts.max) or (opts.value and opts.value > 1 and 100 or 1)
	local span = (max - min) == 0 and 1 or (max - min)
	local value = math.clamp(tonumber(opts.value) or min, min, max)
	local row = newRow(parent, opts.desc and 50 or ROW_H)
	rowText(row, opts.text or "Progress", opts.desc, 0.42, 44, opts.icon)
	local pct = Create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 44, 1, 0),
		BackgroundTransparency = 1, Font = FONT_MONO, Text = "0" .. (opts.suffix or "%"),
		TextColor3 = THEME.SubText, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, Parent = row,
	})
	local bar = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -52, 0.5, 0), Size = UDim2.new(0.42, 0, 0, 5),
		BackgroundColor3 = THEME.ToggleOff, Parent = row,
	}, { corner(3) })
	local fillGrad = Create("UIGradient", {})
	local fill = Create("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = accent, Parent = bar }, { corner(3), fillGrad })
	accentProp(fill, "BackgroundColor3", accent); accentGrad(fillGrad, accent)
	local control = {}
	function control.Set(v, animate)
		value = math.clamp(tonumber(v) or min, min, max)
		local frac = (value - min) / span
		pct.Text = (max <= 1 and tostring(math.floor(frac * 100 + 0.5)) or tostring(math.floor(value + 0.5))) .. (opts.suffix or "%")
		tween(fill, { Size = UDim2.new(frac, 0, 1, 0) }, animate == false and TweenInfo.new(0) or TI.SYDE_SIZE)
		if opts.flag then NEMESIS.Flags[opts.flag] = value end
	end
	function control.Get() return value end
	control.Set(value)
	return control
end

-- Stat: a compact metric readout, label on the left + a big accent value right.
-- opts { text/label, value, icon }. Returns Set(v).
function Elements.Stat(parent, accent, opts)
	opts = opts or {}
	onAccent(function(c) accent = c end)
	local row = newRow(parent, ROW_H)
	rowText(row, opts.text or opts.label or "Stat", opts.desc, 0.4, 12, opts.icon)
	local val = Create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0.5, 0, 1, 0),
		BackgroundTransparency = 1, Font = FONT_BOLD, Text = tostring(opts.value or "0"),
		TextColor3 = accent, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
	})
	accentProp(val, "TextColor3", accent)
	local control = {}
	function control.Set(v) val.Text = tostring(v) end
	function control.Get() return val.Text end
	return control
end

-- Checkbox: a left-aligned square check with the label to its right (a lighter
-- alternative to Toggle). opts { text, default, callback, flag }.
function Elements.Checkbox(parent, accent, opts)
	opts = opts or {}
	onAccent(function(c) accent = c end)
	local hitbox = accent
	onHitbox(function(c) hitbox = c end)
	local state = opts.default and true or false
	local row = newRow(parent, ROW_H)
	local box = Create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(0, 18, 0, 18),
		BackgroundColor3 = THEME.ToggleOff, Parent = row,
	}, { corner(5), stroke(THEME.ElementStroke, 1, 0.35) })
	local checkSpec = resolveIcon("check")
	local check = checkSpec and Create("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 12, 0, 12),
		BackgroundTransparency = 1, ImageColor3 = accentTextColor(accent), ImageTransparency = 1, ZIndex = 2, Parent = box,
	})
	if check then applyIcon(check, checkSpec); onHitbox(function(c) check.ImageColor3 = accentTextColor(c) end) end
	Create("TextLabel", {
		Position = UDim2.new(0, 28, 0, 0), Size = UDim2.new(1, -28, 1, 0), BackgroundTransparency = 1,
		Font = FONT_MED, Text = tostring(opts.text or "Checkbox"), TextColor3 = THEME.Text, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
	})
	tagSearch(row, opts.text)
	local control = {}
	local function render(animate)
		local info = animate and TI.SYDE or TweenInfo.new(0)
		tween(box, { BackgroundColor3 = state and hitbox or THEME.ToggleOff }, info)
		if check then tween(check, { ImageTransparency = state and 0 or 1 }, info) end
	end
	function control.Set(v, fire)
		state = v and true or false
		render(true)
		if opts.flag then NEMESIS.Flags[opts.flag] = state end
		if fire ~= false and type(opts.callback) == "function" then pcall(opts.callback, state) end
	end
	function control.Get() return state end
	local click = Create("TextButton", { Size = UDim2.new(1, ROW_PAD * 2, 1, 0), Position = UDim2.new(0, -ROW_PAD, 0, 0), BackgroundTransparency = 1, Text = "", Parent = row })
	click.MouseButton1Click:Connect(function() control.Set(not state) end)
	render(false)
	if opts.flag then NEMESIS.Flags[opts.flag] = state end
	bindFlag(opts.flag, control, "toggle")
	return control
end

-- CopyButton: a button that copies opts.copy to the clipboard on click and toasts.
-- opts { text, button, copy, icon }.
function Elements.CopyButton(parent, accent, opts)
	opts = opts or {}
	local text = opts.copy or opts.value or ""
	local b = Elements.Button(parent, accent, {
		text = opts.text or "Copy", button = opts.button or "Copy", icon = opts.icon or "copy", desc = opts.desc,
		callback = function()
			if setClipboard(tostring(text)) then
				NEMESIS.Notify({ title = "Copied", content = "Copied to clipboard.", duration = 2, icon = "copy" })
			end
		end,
	})
	b.SetCopy = function(v) text = tostring(v) end
	return b
end

-- Gen2-style chart palette + the accent charts default to (matches the green
-- family of the Gen2 fanmade charts). opts.color / opts.colors override it.
local CHART_ACCENT = Color3.fromRGB(23, 153, 110)
local CHART_PALETTE = {
	Color3.fromRGB(70, 168, 120), Color3.fromRGB(150, 222, 186), Color3.fromRGB(44, 108, 80),
	Color3.fromRGB(26, 62, 47), Color3.fromRGB(214, 240, 226),
}

-- shared card + header for the chart family, styled like the Gen2 element card:
-- 12px corners, a soft top-to-bottom sheen gradient, a 1px whisper stroke.
local function chartShell(parent, accent, opts, plotHeight)
	local card = Create("Frame", {
		Size = UDim2.new(1, -ROW_PAD * 2, 0, 44 + plotHeight),
		Position = UDim2.new(0, ROW_PAD, 0, 0),
		BackgroundColor3 = THEME.Element, ClipsDescendants = true, Parent = parent,
	}, {
		corner(12), stroke(THEME.ElementStroke, 1, 0.3), padding(12),
		Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(216, 216, 216)), Transparency = NumberSequence.new(0.9) }),
	})
	tagSearch(card, opts.text or opts.name or "Chart")
	local head = Create("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Parent = card })
	Create("TextLabel", {
		Size = UDim2.new(0.6, 0, 1, 0), BackgroundTransparency = 1, Font = FONT_BOLD,
		Text = tostring(opts.text or opts.name or "Chart"), TextColor3 = THEME.Text, TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = head,
	})
	local valLbl = Create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.4, 0, 1, 0),
		BackgroundTransparency = 1, Font = FONT_BOLD, Text = "", TextColor3 = CHART_ACCENT, TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Right, Parent = head,
	})
	local plot = Create("Frame", {
		Position = UDim2.new(0, 0, 0, 30), Size = UDim2.new(1, 0, 1, -30), BackgroundTransparency = 1, Parent = card,
	})
	return card, valLbl, plot
end

local function cleanNumbers(pts)
	local out = {}
	for _, v in ipairs(pts or {}) do local n = tonumber(type(v) == "table" and (v.Value or v.value or v[1]) or v); if n then out[#out + 1] = n end end
	if #out == 0 then out = { 0 } end
	return out
end

-- BarChart: vertical bars for a small series; bars spring up staggered.
function Elements.BarChart(parent, accent, opts)
	opts = opts or {}
	onAccent(function(c) accent = c end)
	local vals = cleanNumbers(opts.points or opts.values or opts.data)
	local labels = {}
	for i, v in ipairs(opts.points or {}) do if type(v) == "table" then labels[i] = v.Label or v.label end end
	local hasLabels = next(labels) ~= nil
	local card, valLbl, plot = chartShell(parent, accent, opts, hasLabels and 118 or 100)
	local barColor = opts.color or CHART_ACCENT
	local suffix, prefix = opts.suffix or "", opts.prefix or ""
	local bars = {}
	local function redraw(animate)
		for _, b in ipairs(bars) do b:Destroy() end; bars = {}
		local maxv = 0.0001; for _, v in ipairs(vals) do maxv = math.max(maxv, v) end
		local n = #vals; local pw = 0
		pcall(function() pw = plot.AbsoluteSize.X end); if pw <= 0 then pw = 300 end
		local slot = pw / n
		local bw = math.clamp(math.floor(slot * 0.66), 6, 44)
		local labelRoom = hasLabels and 16 or 0
		for i, v in ipairs(vals) do
			local h = math.max(3, v / maxv * (plot.AbsoluteSize.Y - 8 - labelRoom))
			local barGrad = Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(178, 178, 178)), Transparency = NumberSequence.new(0.85, 1) })
			local bar = Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new((i - 0.5) / n, 0, 1, -labelRoom),
				Size = UDim2.new(0, bw, 0, animate and 0 or h), BackgroundColor3 = barColor, ZIndex = 2, Parent = plot,
			}, { corner(6), barGrad })
			bars[#bars + 1] = bar
			if hasLabels then
				local lc = Create("TextLabel", {
					AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new((i - 0.5) / n, 0, 1, 0), Size = UDim2.new(0, slot, 0, 12),
					BackgroundTransparency = 1, Font = FONT, Text = tostring(labels[i] or ""), TextColor3 = THEME.SubText, TextSize = 10,
					TextTruncate = Enum.TextTruncate.AtEnd, Parent = plot,
				})
				bars[#bars + 1] = lc
			end
			if animate then task.delay(0.04 + (i - 1) * 0.05, function() if bar.Parent then tween(bar, { Size = UDim2.new(0, bw, 0, h) }, TI.SYDE_SIZE) end end) end
		end
		valLbl.Text = prefix .. tostring(vals[#vals] or 0) .. suffix
	end
	local chart = {}
	function chart.Set(s)
		if s and s.Points then
			vals = cleanNumbers(s.Points)
			labels = {}
			for i, v in ipairs(s.Points) do if type(v) == "table" then labels[i] = v.Label or v.label end end
			hasLabels = next(labels) ~= nil
		end
		redraw(true)
	end
	function chart.Push(v) vals[#vals + 1] = tonumber(v) or 0; if #vals > (opts.maxPoints or 16) then table.remove(vals, 1) end redraw(true) end
	function chart.Replay() redraw(true) end
	task.defer(function() redraw(true) end)
	plot:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() redraw(false) end)
	return chart
end

-- Catmull-Rom spline point (for the smooth line option)
local function catmull(p0, p1, p2, p3, t)
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end
local function commafy(s)
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return out
end
local TI_MORPH = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- Chart: line / area sparkline. Faithful port of the Gen2 chart: a green line
-- built from thin rotated segments, white dots, a 3px-column gradient area fill,
-- two faint gridlines + a hover hairline/scrub, and a wipe + dot-pop entrance.
function Elements.Chart(parent, accent, opts)
	opts = opts or {}
	local vals = cleanNumbers(opts.points or opts.values or opts.data)
	if #vals == 1 then vals[2] = vals[1] end
	local card, valLbl, plot = chartShell(parent, accent, opts, 100)
	local lineColor = opts.color or CHART_ACCENT
	local suffix, prefix, decimals = opts.suffix or "", opts.prefix or "", tonumber(opts.decimals) or 0
	local filled = opts.filled ~= false
	local smooth = opts.smooth == true
	local showDots = opts.dots == true or (opts.dots == nil and not smooth)
	local function fmt(n)
		local str = decimals > 0 and string.format("%." .. decimals .. "f", n) or tostring(math.floor(n + 0.5))
		return prefix .. commafy(str) .. suffix
	end
	-- gridlines (top-mid + bottom) and a hover hairline
	local function gridline(y) Create("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.93, BorderSizePixel = 0, Position = UDim2.new(0, 0, y, y == 1 and -1 or 0), Size = UDim2.new(1, 0, 0, 1), Parent = plot }) end
	gridline(0.5); gridline(1)
	local hairline = Create("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.82, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.new(0, 1, 1, 0), Visible = false, ZIndex = 2, Parent = plot })
	local fillHolder = Create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Parent = plot })
	local segHolder = Create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), ZIndex = 3, Parent = plot })
	local segCanvas = Create("Frame", { BackgroundTransparency = 1, Parent = segHolder })
	local dotHolder = Create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), ZIndex = 4, Parent = plot })
	local dots, segs, cols = {}, {}, {}
	local xs, ys = {}, {}
	local hoverIdx, animToken = nil, 0
	valLbl.Text = fmt(vals[#vals])

	local function redraw(animate)
		local w, h = 0, 0
		pcall(function() w = plot.AbsoluteSize.X; h = plot.AbsoluteSize.Y end)
		if w < 24 or h < 24 then w = math.max(w, 280); h = math.max(h, 80) end
		segCanvas.Size = UDim2.fromOffset(w, h)
		local n = #vals
		local lo, hi = vals[1], vals[1]
		for _, v in ipairs(vals) do lo = math.min(lo, v); hi = math.max(hi, v) end
		local range = hi - lo; if range == 0 then range = math.max(math.abs(hi), 1) end
		local edgePad = (smooth and 3 or 4) / 2 + 1.5
		for i = 1, n do
			xs[i] = edgePad + (n == 1 and 0 or (i - 1) / (n - 1)) * (w - edgePad * 2)
			ys[i] = math.floor(10 + (1 - (vals[i] - lo) / range) * (h - 22) + 0.5)
		end
		for i = #xs, n + 1, -1 do xs[i] = nil; ys[i] = nil end
		local rxs, rys = xs, ys
		if smooth and n >= 3 then
			rxs, rys = {}, {}
			for i = 1, n - 1 do
				local x0, y0 = xs[i > 1 and i - 1 or 1], ys[i > 1 and i - 1 or 1]
				local x1, y1, x2, y2 = xs[i], ys[i], xs[i + 1], ys[i + 1]
				local x3, y3 = xs[i + 2] or x2, ys[i + 2] or y2
				local sub = math.clamp(math.ceil((x2 - x1) / 3), 8, 36)
				for tstep = 0, sub - 1 do
					local a = tstep / sub
					rxs[#rxs + 1] = catmull(x0, x1, x2, x3, a)
					rys[#rys + 1] = math.clamp(catmull(y0, y1, y2, y3, a), 2, h - 2)
				end
			end
			rxs[#rxs + 1] = xs[n]; rys[#rys + 1] = ys[n]
		end
		local rn = #rxs
		for i = #dots, n + 1, -1 do dots[i]:Destroy(); dots[i] = nil end
		for i = #segs, rn, -1 do segs[i]:Destroy(); segs[i] = nil end
		-- dots (white, 10px)
		for i = 1, n do
			local d = dots[i]
			if not d then
				d = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = THEME.Knob, ZIndex = 4, Visible = showDots, Parent = dotHolder }, { corner(99) })
				dots[i] = d
			end
			d.Position = UDim2.fromOffset(xs[i], ys[i])
		end
		-- line segments (green, 3px rounded)
		for i = 1, rn - 1 do
			local s = segs[i]
			if not s then s = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, BackgroundColor3 = lineColor, ZIndex = 3, Parent = segCanvas }, { corner(99) }); segs[i] = s end
			local dx, dy = rxs[i + 1] - rxs[i], rys[i + 1] - rys[i]
			local len = math.max(math.sqrt(dx * dx + dy * dy), 0.001)
			local ov = smooth and 3 or 4
			s.Position = UDim2.new((rxs[i] + dx / 2) / w, 0, (rys[i] + dy / 2) / h, 0)
			s.Size = UDim2.fromOffset(math.ceil(len + (rn == 2 and 0 or ov)), 3)
			s.Rotation = math.deg(math.atan2(dy, dx))
		end
		-- gradient area fill (thin columns -> smooth top edge, no visible staircase)
		if filled then
			local colW, fillX = 1, rxs[1]
			local count = math.max(math.ceil((rxs[rn] - fillX) / colW), 1)
			for i = #cols, count + 1, -1 do cols[i]:Destroy(); cols[i] = nil end
			local seg = 1
			for c = 1, count do
				local f = cols[c]
				if not f then f = Create("Frame", { AnchorPoint = Vector2.new(0, 1), BorderSizePixel = 0, BackgroundColor3 = lineColor, BackgroundTransparency = 0.12, Parent = fillHolder }, { Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(lineColor, lineColor), Transparency = NumberSequence.new(0, 0.78) }) }); cols[c] = f end
				local left = fillX + (c - 1) * colW
				local cw = math.min(colW, rxs[rn] - left)
				local cx = left + cw / 2
				while seg < rn - 1 and rxs[seg + 1] < cx do seg = seg + 1 end
				local x1, x2 = rxs[seg], rxs[seg + 1]
				local a = math.clamp((cx - x1) / math.max(x2 - x1, 1), 0, 1)
				local y = rys[seg] + (rys[seg + 1] - rys[seg]) * a
				f.Position = UDim2.fromOffset(left, h - 1)
				f.Size = UDim2.fromOffset(math.max(cw, 1), math.max(h - 1 - y, 0))
			end
		end
		valLbl.Text = fmt(vals[#vals])
		if animate then
			animToken = animToken + 1; local my = animToken
			local D = 0.75
			-- reveal the line and the fill together with one left-to-right wipe
			for _, holder in ipairs({ segHolder, fillHolder }) do
				holder.ClipsDescendants = true; holder.Size = UDim2.new(0, 0, 1, 0)
				tween(holder, { Size = UDim2.new(1, 0, 1, 0) }, TweenInfo.new(D, Enum.EasingStyle.Quart, Enum.EasingDirection.Out))
			end
			task.delay(D + 0.1, function()
				if my == animToken then
					segHolder.ClipsDescendants = false; segHolder.Size = UDim2.new(1, 0, 1, 0)
					fillHolder.ClipsDescendants = false; fillHolder.Size = UDim2.new(1, 0, 1, 0)
				end
			end)
			for i, d in ipairs(dots) do
				local at = w > 0 and (xs[i] or 0) / w or 0
				d.Size = UDim2.fromOffset(0, 0)
				task.delay(at * D * 0.62, function() if my == animToken and d.Parent then tween(d, { Size = UDim2.fromOffset(10, 10) }, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out)) end end)
			end
		end
	end
	-- hover scrub: highlight the nearest point + hairline, read its value
	local function applyHover(i)
		if hoverIdx == i then return end
		if hoverIdx and dots[hoverIdx] then dots[hoverIdx].Size = UDim2.fromOffset(10, 10); dots[hoverIdx].BackgroundColor3 = THEME.Knob; dots[hoverIdx].Visible = showDots end
		hoverIdx = i
		local d = i and dots[i]
		if d then d.Size = UDim2.fromOffset(14, 14); d.BackgroundColor3 = lineColor; d.Visible = true; hairline.Position = UDim2.fromOffset(xs[i], 0); hairline.Visible = true; valLbl.Text = fmt(vals[i])
		else hairline.Visible = false; valLbl.Text = fmt(vals[#vals]) end
	end
	local function scrub(input)
		if #xs < 2 then return end
		local rx = input.Position.X - plot.AbsolutePosition.X
		local best, bd = nil, math.huge
		for i = 1, #vals do local dist = math.abs((xs[i] or 0) - rx); if dist < bd then best, bd = i, dist end end
		applyHover(best)
	end
	card.InputChanged:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then scrub(input) end end)
	card.MouseLeave:Connect(function() applyHover(nil) end)
	local chart = {}
	function chart.Set(s) if s and s.Points then vals = cleanNumbers(s.Points) end redraw(true) end
	function chart.Push(v) vals[#vals + 1] = tonumber(v) or 0; if #vals > (opts.maxPoints or math.max(#vals, 12)) then table.remove(vals, 1) end redraw(true) end
	function chart.Replay() redraw(true) end
	task.defer(function() redraw(true) end)
	plot:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() redraw(false) end)
	return chart
end

-- StackedChart: horizontal 100%-stacked rows with a legend. Rows fill in staggered.
function Elements.StackedChart(parent, accent, opts)
	opts = opts or {}
	onAccent(function(c) accent = c end)
	local series = opts.series or { "A", "B", "C" }
	local palette = opts.colors or CHART_PALETTE
	local rows = opts.rows or {}
	local card, valLbl, plot = chartShell(parent, accent, opts, 34 * math.max(#rows, 1) + 24)
	-- legend
	local legend = Create("Frame", { Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Parent = plot }, {
		Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12), VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	for i, s in ipairs(series) do
		local item = Create("Frame", { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, LayoutOrder = i, Parent = legend })
		Create("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(0, 9, 0, 9), BackgroundColor3 = palette[i] or accent, Parent = item }, { corner(3) })
		Create("TextLabel", { Position = UDim2.new(0, 14, 0, 0), Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Font = FONT, Text = tostring(s), TextColor3 = THEME.SubText, TextSize = 11, Parent = item })
	end
	local body = Create("Frame", { Position = UDim2.new(0, 0, 0, 22), Size = UDim2.new(1, 0, 1, -22), BackgroundTransparency = 1, Parent = plot })
	local function redraw(animate)
		-- grow / shrink the card to the current row count so rows added via Set are
		-- not silently clipped by the card's fixed construction-time height
		local wantH = 44 + 34 * math.max(#rows, 1) + 24
		tween(card, { Size = UDim2.new(1, -ROW_PAD * 2, 0, wantH) }, animate and TI.SYDE_REFLOW or TweenInfo.new(0))
		for _, c in ipairs(body:GetChildren()) do c:Destroy() end
		for ri, r in ipairs(rows) do
			local rowVals = r.Values or r.values or r
			local total = 0; for _, v in ipairs(rowVals) do total = total + (tonumber(v) or 0) end
			if total <= 0 then total = 1 end
			local rowFrame = Create("Frame", { Position = UDim2.new(0, 0, 0, (ri - 1) * 34), Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, Parent = body })
			Create("TextLabel", { Size = UDim2.new(0, 76, 1, 0), BackgroundTransparency = 1, Font = FONT, Text = tostring(r.Name or r.name or ("Row " .. ri)), TextColor3 = THEME.Text, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = rowFrame })
			local track = Create("Frame", { Position = UDim2.new(0, 84, 0.5, -8), Size = UDim2.new(1, -84, 0, 16), BackgroundColor3 = THEME.ToggleOff, ClipsDescendants = true, Parent = rowFrame }, { corner(4) })
			local stack = Create("Frame", { Size = UDim2.new(animate and 0 or 1, 0, 1, 0), BackgroundTransparency = 1, Parent = track }, {
				Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			for si, v in ipairs(rowVals) do
				Create("Frame", { Size = UDim2.new((tonumber(v) or 0) / total, 0, 1, 0), BackgroundColor3 = palette[si] or accent, BorderSizePixel = 0, LayoutOrder = si, Parent = stack })
			end
			if animate then task.delay(0.05 + (ri - 1) * 0.09, function() if stack.Parent then tween(stack, { Size = UDim2.new(1, 0, 1, 0) }, TI.SYDE_SIZE) end end) end
		end
	end
	local chart = {}
	function chart.Set(s) if s and s.Rows then rows = s.Rows end redraw(true) end
	function chart.Replay() redraw(true) end
	task.defer(function() redraw(true) end)
	plot:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() redraw(false) end)
	return chart
end

-- RippleButton: an action row that emits an expanding ripple from the click point.
function Elements.RippleButton(parent, accent, opts)
	opts = opts or {}
	onAccent(function(c) accent = c end)
	local row = newRow(parent, opts.desc and 50 or ROW_H)
	-- build the click surface first so the label/icon (added after) paint above the
	-- hover wash and ripple instead of being covered by them
	local surface = Create("TextButton", {
		Size = UDim2.new(1, ROW_PAD * 2, 1, 0), Position = UDim2.new(0, -ROW_PAD, 0, 0),
		BackgroundColor3 = THEME.Element, BackgroundTransparency = 1, AutoButtonColor = false, Text = "",
		ClipsDescendants = true, Parent = row,
	}, { corner(8) })
	local label = rowText(row, opts.text or "Action", opts.desc, 0, 0, opts.icon)
	surface.MouseEnter:Connect(function() tween(surface, { BackgroundTransparency = 0.85 }, TI.HOVER) end)
	surface.MouseLeave:Connect(function() tween(surface, { BackgroundTransparency = 1 }, TI.HOVEROFF) end)
	surface.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local lx = input.Position.X - surface.AbsolutePosition.X
		local ly = input.Position.Y - surface.AbsolutePosition.Y
		local ripple = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(lx, ly), Size = UDim2.fromOffset(0, 0),
			BackgroundColor3 = accent, BackgroundTransparency = 0.5, ZIndex = 5, Parent = surface,
		}, { corner(200) })
		local far = math.max(surface.AbsoluteSize.X, surface.AbsoluteSize.Y) * 2
		tween(ripple, { Size = UDim2.fromOffset(far, far), BackgroundTransparency = 1 }, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
		task.delay(0.6, function() if ripple then ripple:Destroy() end end)
	end)
	surface.MouseButton1Click:Connect(function() if type(opts.callback) == "function" then pcall(opts.callback) end end)
	local control = {}
	function control.SetText(t) setRowText(label, t) end
	function control.Fire() if type(opts.callback) == "function" then pcall(opts.callback) end end
	return control
end


-- HoldButton: press and hold for Duration seconds; a fill sweeps and fires on complete.
function Elements.HoldButton(parent, accent, opts)
	opts = opts or {}
	onAccent(function(c) accent = c end)
	local dur = math.clamp(tonumber(opts.duration) or 1.5, 0.2, 10)
	local row = newRow(parent, opts.desc and 50 or ROW_H)
	-- surface + progress fill built first so the label/icon (added after) stay above
	-- the sweeping fill instead of being covered by it
	local surface = Create("TextButton", {
		Size = UDim2.new(1, ROW_PAD * 2, 1, 0), Position = UDim2.new(0, -ROW_PAD, 0, 0),
		BackgroundColor3 = THEME.Element, BackgroundTransparency = 1, AutoButtonColor = false, Text = "",
		ClipsDescendants = true, Parent = row,
	}, { corner(8) })
	local fillGrad = Create("UIGradient", {})
	local fill = Create("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = accent, BackgroundTransparency = 0.6, ZIndex = 0, Parent = surface }, { fillGrad })
	accentProp(fill, "BackgroundColor3", accent); accentGrad(fillGrad, accent)
	local label = rowText(row, opts.text or "Hold to confirm", opts.desc, 0, 0, opts.icon)
	local holding, tw = false, nil
	local session = 0   -- invalidates a prior press's pending completion timer
	local function cancel()
		holding = false
		if tw then tw:Cancel() end
		tween(fill, { Size = UDim2.new(0, 0, 1, 0) }, TI.FAST)
	end
	surface.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
		holding = true
		session = session + 1
		local mine = session
		tw = tween(fill, { Size = UDim2.new(1, 0, 1, 0) }, TweenInfo.new(dur, Enum.EasingStyle.Linear))
		task.delay(dur, function()
			-- only complete if this exact press is still the one being held
			if holding and session == mine then
				holding = false
				if type(opts.callback) == "function" then pcall(opts.callback) end
				if opts.notify ~= false then NEMESIS.Notify({ title = opts.completionTitle or "Confirmed", content = opts.completionText or "Action confirmed.", duration = 2, icon = opts.completionIcon or "check" }) end
				tween(fill, { Size = UDim2.new(0, 0, 1, 0) }, TI.HOVEROFF)
			end
		end)
	end)
	surface.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then cancel() end
	end)
	surface.MouseLeave:Connect(cancel)
	local control = {}
	function control.SetText(t) setRowText(label, t) end
	return control
end

-- SlideButton: drag the knob across the track to confirm (slide-to-confirm).
-- opts { text, confirmText, callback, notify, completionTitle, completionText }
function Elements.SlideButton(parent, accent, opts)
	opts = opts or {}
	onAccent(function(c) accent = c end)
	local row = newRow(parent, 42)
	local track = Create("TextButton", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = THEME.Element, AutoButtonColor = false, Text = "", ClipsDescendants = true, Parent = row,
	}, { corner(10), stroke(THEME.ElementStroke, 1, 0.4) })
	local fillGrad = Create("UIGradient", {})
	local fill = Create("Frame", {
		Size = UDim2.new(0, 32, 1, 0), BackgroundColor3 = accent, BackgroundTransparency = 0.15, BorderSizePixel = 0, Parent = track,
	}, { corner(10), fillGrad })
	accentProp(fill, "BackgroundColor3", accent); accentGrad(fillGrad, accent)
	local prompt = Create("TextLabel", {
		Size = UDim2.new(1, -44, 1, 0), Position = UDim2.new(0, 40, 0, 0), BackgroundTransparency = 1,
		Font = FONT_MED, Text = opts.text or "Slide to confirm", TextColor3 = THEME.SubText, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center, Parent = track,
	})
	local knob = Create("TextButton", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, 0), Size = UDim2.new(0, 30, 0, 30),
		BackgroundColor3 = THEME.Knob, AutoButtonColor = false, Text = "", ZIndex = 4, Parent = track,
	}, { corner(8) })
	local darkGlyph = Color3.fromRGB(24, 25, 28)
	do
		local aspec = resolveIcon("chevrons-right") or resolveIcon("chevron-right")
		if aspec then
			local a = Create("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 16, 0, 16), BackgroundTransparency = 1, ImageColor3 = darkGlyph, ZIndex = 5, Parent = knob })
			applyIcon(a, aspec)
		else
			Create("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = FONT_BOLD, Text = ">", TextColor3 = darkGlyph, TextSize = 16, ZIndex = 5, Parent = knob })
		end
	end

	local knobW = 30
	local dragging, confirmed, curPx = false, false, 0
	local function maxX() return math.max(track.AbsoluteSize.X - knobW - 4, 1) end
	local function place(px, animate)
		px = math.clamp(px, 0, maxX())
		curPx = px
		if animate then
			tween(knob, { Position = UDim2.new(0, 2 + px, 0.5, 0) }, TI.EXPAND)
			tween(fill, { Size = UDim2.new(0, px + knobW + 2, 1, 0) }, TI.EXPAND)
		else
			knob.Position = UDim2.new(0, 2 + px, 0.5, 0)
			fill.Size = UDim2.new(0, px + knobW + 2, 1, 0)
		end
		prompt.TextTransparency = math.clamp(px / maxX(), 0, 1) * 0.85
	end
	local function reset(animate)
		confirmed = false
		prompt.Text = opts.text or "Slide to confirm"
		place(0, animate)
	end
	local function confirm()
		if confirmed then return end
		confirmed = true
		prompt.Text = opts.confirmText or "Confirmed"
		prompt.TextTransparency = 0
		place(maxX(), true)
		if type(opts.callback) == "function" then pcall(opts.callback) end
		if opts.notify ~= false then NEMESIS.Notify({ title = opts.completionTitle or "Confirmed", content = opts.completionText or "Action confirmed.", duration = 2, icon = opts.completionIcon or "check" }) end
		if not opts.stayConfirmed then task.delay(1.1, function() if confirmed then reset(true) end end) end
	end
	knob.InputBegan:Connect(function(input)
		if confirmed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = true end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if not track.Parent then dragging = false; return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			place(input.Position.X - track.AbsolutePosition.X - knobW / 2, false)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
			if curPx >= maxX() * 0.9 then confirm() else reset(true) end
		end
	end)
	local control = {}
	function control.Reset() reset(true) end
	function control.SetText(t) opts.text = tostring(t); if not confirmed then prompt.Text = opts.text end end
	task.defer(function() place(0, false) end)
	return control
end

-- ShimmerLabel: a heading whose text has a bright band that sweeps across it.
function Elements.ShimmerLabel(parent, accent, opts)
	opts = opts or {}
	if type(opts) == "string" then opts = { text = opts } end
	local row = Create("Frame", { Size = UDim2.new(1, -ROW_PAD * 2, 0, opts.height or 24), Position = UDim2.new(0, ROW_PAD, 0, 0), BackgroundTransparency = 1, Parent = parent })
	local lbl = Create("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = opts.bold and FONT_BOLD or FONT_SEMI,
		Text = tostring(opts.text or "Shimmer"), TextColor3 = THEME.SubText, TextSize = opts.textSize or 14,
		TextXAlignment = Enum.TextXAlignment.Left, Parent = row,
	})
	tagSearch(row, opts.text)
	local grad = Create("UIGradient", {
		Rotation = opts.rotation or 0, Parent = lbl,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, THEME.SubText), ColorSequenceKeypoint.new(0.45, THEME.SubText),
			ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(0.55, THEME.SubText),
			ColorSequenceKeypoint.new(1, THEME.SubText),
		}),
	})
	local speed = math.clamp(tonumber(opts.speed) or 1.6, 0.3, 6)
	-- a single self-repeating tween (repeatCount -1) drives the sweep; no polling
	-- loop, so it can't spin the CPU under a stub or a starved executor
	local shimTw
	local function startShimmer()
		if shimTw then pcall(function() shimTw:Cancel() end) end
		grad.Offset = Vector2.new(-1, 0)
		shimTw = tween(grad, { Offset = Vector2.new(1, 0) }, TweenInfo.new(speed, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, false, 0.5))
	end
	startShimmer()
	local control = {}
	function control.Set(t) lbl.Text = tostring(t); tagSearch(row, t) end
	function control.SetSpeed(s) speed = math.clamp(tonumber(s) or 1.6, 0.3, 6); startShimmer() end
	return control
end

-- ScrollHint: a centered "scroll for more" label beside a bouncing down-arrow.
function Elements.ScrollHint(parent, accent, opts)
	opts = opts or {}
	if type(opts) == "string" then opts = { text = opts } end
	local row = Create("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Parent = parent })
	local wrap = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Parent = row }, {
		Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	local lbl = Create("TextLabel", { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Font = FONT, Text = tostring(opts.text or "Scroll for more"), TextColor3 = THEME.SubText, TextSize = 12, LayoutOrder = 1, Parent = wrap })
	local arrowHolder = Create("Frame", { Size = UDim2.new(0, 14, 0, 14), BackgroundTransparency = 1, LayoutOrder = 2, Parent = wrap })
	local spec = resolveIcon(opts.icon or "chevron-down")
	local arrow = Create("ImageLabel", { Position = UDim2.new(0.5, 0, 0, 0), AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.new(0, 14, 0, 14), BackgroundTransparency = 1, ImageColor3 = THEME.SubText, Parent = arrowHolder })
	if spec then applyIcon(arrow, spec) end
	-- one reversing, infinitely-repeating tween: no polling loop
	tween(arrow, { Position = UDim2.new(0.5, 0, 0, 6) }, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true))
	local control = {}
	function control.Set(t) lbl.Text = tostring(t) end
	return control
end

-- CursorTag: a card that shows a small pill following the mouse while hovered.
function Elements.CursorTag(parent, accent, opts)
	opts = opts or {}
	local row = Create("Frame", { Size = UDim2.new(1, -ROW_PAD * 2, 0, opts.height or 46), Position = UDim2.new(0, ROW_PAD, 0, 0), BackgroundColor3 = THEME.Element, Parent = parent }, { corner(8), stroke(THEME.ElementStroke, 1, 0.4) })
	local area = Create("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, AutoButtonColor = false, Text = "", Parent = row })
	Create("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = FONT, Text = tostring(opts.hint or "Hover here"), TextColor3 = THEME.SubText, TextSize = 12, Parent = row })
	local screenGui = row:FindFirstAncestorWhichIsA("ScreenGui") or row:FindFirstAncestorWhichIsA("LayerCollector")
	local chip = Create("TextLabel", {
		AnchorPoint = Vector2.new(0, 1), Size = UDim2.new(0, 0, 0, 22), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, Font = FONT_MED, Text = tostring(opts.text or "Tag"),
		TextColor3 = Color3.fromRGB(20, 20, 24), TextTransparency = 1, TextSize = 12, Visible = false, ZIndex = 60000,
		Parent = screenGui or row,
	}, { corner(6), padding(8) })
	local enabled = opts.enabled ~= false
	local moveConn
	local function show() chip.Visible = true; tween(chip, { BackgroundTransparency = 0, TextTransparency = 0 }, TI.FAST) end
	local function hide() tween(chip, { BackgroundTransparency = 1, TextTransparency = 1 }, TI.FAST); task.delay(0.16, function() if chip.BackgroundTransparency >= 0.99 then chip.Visible = false end end) end
	area.MouseEnter:Connect(function()
		if not enabled then return end
		show()
		moveConn = RunService.RenderStepped:Connect(function()
			local m = UserInputService:GetMouseLocation()
			local vp = viewportSize()
			local cw, ch = chip.AbsoluteSize.X, chip.AbsoluteSize.Y
			-- chip anchor is bottom-left, so keep [x, x+w] and [y-h, y] inside the viewport
			local tx = math.clamp(m.X + (opts.offset and opts.offset.X or 12), 2, math.max(2, vp.X - cw - 2))
			local ty = math.clamp(m.Y + (opts.offset and opts.offset.Y or -6), ch + 2, math.max(ch + 2, vp.Y - 2))
			chip.Position = UDim2.fromOffset(tx, ty)
		end)
	end)
	area.MouseLeave:Connect(function() if moveConn then moveConn:Disconnect(); moveConn = nil end hide() end)
	local control = {}
	function control.Set(t) chip.Text = tostring(t) end
	function control.SetEnabled(s) enabled = s and true or false; if not enabled and moveConn then moveConn:Disconnect(); moveConn = nil; hide() end end
	return control
end

-- CollapsibleSection: a titled section that expands/collapses and hosts nested
-- elements. Returns the section host (.Toggle/.Slider/... + .SetOpen).
function Elements.CollapsibleSection(parent, accent, opts)
	opts = opts or {}
	if type(opts) == "string" then opts = { text = opts } end
	return makeSection(parent, accent, opts.text or opts.title or "Section", opts.open == false)
end


-- FAQ: an accordion of question/answer cards; opening one closes the others.
function Elements.FAQ(parent, accent, opts)
	opts = opts or {}
	local items = opts.items or opts.Items or {}
	local wrap = Create("Frame", { Size = UDim2.new(1, -ROW_PAD * 2, 0, 0), Position = UDim2.new(0, ROW_PAD, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = parent }, {
		Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
	})
	local api = { Items = {} }
	for idx, it in ipairs(items) do
		local q = it.question or it.Question or it[1] or "Question"
		local a = it.answer or it.Answer or it[2] or ""
		local card = Create("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = THEME.Element, ClipsDescendants = true, LayoutOrder = idx, Parent = wrap }, { corner(12), stroke(THEME.ElementStroke, 1, 0.3), Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(216, 216, 216)), Transparency = NumberSequence.new(0.9) }) })
		tagSearch(card, q .. " " .. a)
		local head = Create("TextButton", { Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, AutoButtonColor = false, Text = "", Parent = card }, { padXY(ROW_PAD, 0) })
		Create("TextLabel", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, -24, 0, 16), BackgroundTransparency = 1, Font = FONT_MED, Text = tostring(q), TextColor3 = THEME.Text, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = head })
		local chev = iconChevron(head, 14, THEME.SubText, "chevron-down")
		chev.AnchorPoint = Vector2.new(1, 0.5); chev.Position = UDim2.new(1, 0, 0.5, 0); chev.Rotation = 180
		local ans = Create("TextLabel", { Position = UDim2.new(0, ROW_PAD, 0, 38), Size = UDim2.new(1, -ROW_PAD * 2, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Font = FONT, Text = tostring(a), TextColor3 = THEME.SubText, TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
		local open = false
		local function setOpen(o)
			open = o
			tween(chev, { Rotation = open and 0 or 180 }, TI.FAST)
			local ah = 0; pcall(function() ah = ans.AbsoluteSize.Y end)
			tween(card, { Size = UDim2.new(1, 0, 0, open and (38 + ah + 12) or 38) }, TI.EXPAND)
		end
		local rec = { Open = function() setOpen(true) end, Close = function() setOpen(false) end }
		head.MouseButton1Click:Connect(function()
			if not open then for _, r in ipairs(api.Items) do if r ~= rec then r.Close() end end end
			setOpen(not open)
		end)
		api.Items[#api.Items + 1] = rec
	end
	return api
end

-- Changelog: a static titled card listing tagged change entries.
function Elements.Changelog(parent, accent, opts)
	opts = opts or {}
	local card = Create("Frame", { Size = UDim2.new(1, -ROW_PAD * 2, 0, 0), Position = UDim2.new(0, ROW_PAD, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = THEME.Element, Parent = parent }, {
		corner(10), stroke(THEME.ElementStroke, 1, 0.4), padding(12),
		Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
	})
	local head = Create("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = 1, Parent = card })
	Create("TextLabel", { Size = UDim2.new(0.6, 0, 1, 0), BackgroundTransparency = 1, Font = FONT_BOLD, Text = tostring(opts.title or "Changelog"), TextColor3 = THEME.Text, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Parent = head })
	Create("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.4, 0, 1, 0), BackgroundTransparency = 1, Font = FONT_MONO, Text = tostring((opts.version and ("v" .. opts.version) or "") .. (opts.date and ("  " .. opts.date) or "")), TextColor3 = THEME.SubText, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right, Parent = head })
	local tagColors = { added = Color3.fromRGB(90, 220, 140), fixed = Color3.fromRGB(90, 190, 255), changed = Color3.fromRGB(255, 190, 80), removed = Color3.fromRGB(255, 110, 110) }
	for i, e in ipairs(opts.entries or opts.Entries or {}) do
		local tag = (type(e) == "table" and (e.Type or e.Tag or e.type)) or nil
		local txt = (type(e) == "table" and (e.Text or e.text or e[1])) or tostring(e)
		local row = Create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = i + 1, Parent = card })
		local ix = 0
		if tag then
			local chip = Create("TextLabel", { Size = UDim2.new(0, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = tagColors[string.lower(tostring(tag))] or accent, Font = FONT_SEMI, Text = " " .. string.upper(tostring(tag)) .. " ", TextColor3 = Color3.fromRGB(15, 15, 18), TextSize = 10, Parent = row }, { corner(3) })
			ix = 6
			chip:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() end)
			ix = 60
		end
		Create("TextLabel", { Position = UDim2.new(0, tag and 66 or 0, 0, 0), Size = UDim2.new(1, tag and -66 or 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Font = FONT, Text = tostring(txt), TextColor3 = THEME.SubText, TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
	end
	return { Instance = card }
end

-- SegmentedPicker: an iOS-style segmented control picking one of N options.
function Elements.SegmentedPicker(parent, accent, opts)
	opts = opts or {}
	onAccent(function(c) accent = c end)
	local options = opts.options or opts.Options or { "A", "B" }
	local n = #options
	local row = newRow(parent, opts.desc and 50 or ROW_H)
	rowText(row, opts.text or opts.name or "Picker", opts.desc, 0.55, 10, opts.icon)
	local track = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0.55, 0, 0, 24),
		BackgroundColor3 = THEME.Element, ClipsDescendants = true, Parent = row,
	}, { corner(7), stroke(THEME.ElementStroke, 1, 0.4) })
	local thumb = Create("Frame", { Size = UDim2.new(1 / n, -6, 1, -6), Position = UDim2.new(0, 3, 0, 3), BackgroundColor3 = accent, BackgroundTransparency = 0.12, ZIndex = 1, Parent = track }, { corner(5) })
	accentProp(thumb, "BackgroundColor3", accent)
	local sel = 1
	for i, o in ipairs(options) do if o == (opts.default or opts.CurrentOption) then sel = i end end
	local btns = {}
	local control = {}
	local function paint(animate)
		local info = animate and TI.EXPAND or TweenInfo.new(0)
		control.CurrentOption = options[sel]
		tween(thumb, { Position = UDim2.new((sel - 1) / n, 3, 0, 3) }, info)
		for i, b in ipairs(btns) do tween(b, { TextColor3 = i == sel and accentTextColor(accent) or THEME.SubText }, TI.FAST) end
	end
	for i, o in ipairs(options) do
		local b = Create("TextButton", { Size = UDim2.new(1 / n, 0, 1, 0), Position = UDim2.new((i - 1) / n, 0, 0, 0), BackgroundTransparency = 1, AutoButtonColor = false, Font = FONT_MED, Text = tostring(o), TextColor3 = THEME.SubText, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 2, Parent = track })
		btns[i] = b
		b.MouseButton1Click:Connect(function() sel = i; paint(true); if opts.flag then NEMESIS.Flags[opts.flag] = options[sel] end if type(opts.callback) == "function" then pcall(opts.callback, options[sel]) end end)
	end
	function control.Set(v) for i, o in ipairs(options) do if o == v then sel = i end end paint(true) end
	function control.Get() return options[sel] end
	control.CurrentOption = options[sel]
	paint(false)
	if opts.flag then NEMESIS.Flags[opts.flag] = options[sel] end
	bindFlag(opts.flag, control, "segmented")
	return control
end

-- GradientPicker: a colour picker locked to gradient (Multi-stop) mode.
function Elements.GradientPicker(parent, accent, opts)
	opts = opts or {}
	opts.mode = "Multi"
	opts.lockMode = true
	-- seed the stops from a ColorSequence if the caller passed one as opts.color
	if opts.color and typeof(opts.color) == "ColorSequence" and not opts.stops then
		opts.stops = {}
		for _, kp in ipairs(opts.color.Keypoints) do
			opts.stops[#opts.stops + 1] = { pos = kp.Time, color = kp.Value }
		end
	end
	return Elements.ColorPicker(parent, accent, opts)
end

-- PinnedList: item cards each with a pin toggle; pinning floats an item to the
-- top and the whole list smoothly reflows to its new order (Gen2-style).
function Elements.PinnedList(parent, accent, opts)
	opts = opts or {}
	onAccent(function(c) accent = c end)
	Elements.Divider(parent, accent, { text = opts.title or "All Items" })
	local CARD_H, GAP = 40, 6
	local items = opts.items or {}
	local wrap = Create("Frame", { Size = UDim2.new(1, -ROW_PAD * 2, 0, #items * (CARD_H + GAP)), Position = UDim2.new(0, ROW_PAD, 0, 0), BackgroundTransparency = 1, Parent = parent })
	local records = {}
	local stamp = 0
	local function reflow(animate)
		table.sort(records, function(a, b)
			if a.pinned ~= b.pinned then return a.pinned end
			if a.pinned then return a.pinStamp < b.pinStamp end
			return a.idx < b.idx
		end)
		for i, r in ipairs(records) do
			local target = UDim2.new(1, 0, 0, (i - 1) * (CARD_H + GAP))
			if animate then tween(r.card, { Position = target }, TI.EXPAND) else r.card.Position = target end
		end
	end
	for i, it in ipairs(items) do
		local card = Create("Frame", {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, (i - 1) * (CARD_H + GAP)),
			Size = UDim2.new(1, 0, 0, CARD_H), BackgroundColor3 = THEME.Element, Parent = wrap,
		}, { corner(12), stroke(THEME.ElementStroke, 1, 0.3), padXY(ROW_PAD, 0), Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(216, 216, 216)), Transparency = NumberSequence.new(0.9) }) })
		tagSearch(card, (it.Name or it.name or "Item") .. " " .. (it.Description or it.desc or ""))
		local ix = 0
		if it.Icon or it.icon then local img = Create("ImageLabel", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(0, 16, 0, 16), BackgroundTransparency = 1, ImageColor3 = THEME.SubText, Parent = card }); local isp = resolveIcon(it.Icon or it.icon); if isp then applyIcon(img, isp); ix = 24 end end
		Create("TextLabel", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, ix, 0.5, 0), Size = UDim2.new(1, -34 - ix, 1, 0), BackgroundTransparency = 1, Font = FONT_MED, Text = tostring(it.Name or it.name or "Item"), TextColor3 = THEME.Text, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = card })
		local pin = Create("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 26, 0, 26), BackgroundTransparency = 1, AutoButtonColor = false, Text = "", Parent = card })
		local pinIcon = Create("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 15, 0, 15), BackgroundTransparency = 1, ImageColor3 = THEME.SubText, Parent = pin })
		local spec = resolveIcon("pin"); if spec then applyIcon(pinIcon, spec) end
		local rec = { card = card, idx = i, pinned = false, pinStamp = 0, name = it.Name or it.name, pin = pin, icon = pinIcon }
		local function paint() tween(pinIcon, { ImageColor3 = rec.pinned and accent or THEME.SubText, Rotation = rec.pinned and 45 or 0 }, TI.FAST) end
		rec.set = function(state)
			state = state and true or false
			if state == rec.pinned then return end
			rec.pinned = state
			if state then stamp = stamp + 1; rec.pinStamp = stamp end
			paint(); reflow(true)
			if type(opts.callback) == "function" then pcall(opts.callback, rec.name, rec.pinned) end
		end
		pin.MouseButton1Click:Connect(function() rec.set(not rec.pinned) end)
		if it.Pinned then rec.pinned = true; stamp = stamp + 1; rec.pinStamp = stamp; paint() end
		records[#records + 1] = rec
	end
	reflow(false)
	local control = {}
	function control.Pin(name, state) for _, r in ipairs(records) do if r.name == name then r.set(state ~= false) end end end
	function control.GetPinned() local t = {} for _, r in ipairs(records) do if r.pinned then t[#t + 1] = r.name end end return t end
	return control
end

-- EnhancedView: a card with a 3D ViewportFrame that shows and slowly spins a
-- model/object (Syde's "EnchancedView"). opts { title, model/object, height, rotate }.
function Elements.EnhancedView(parent, accent, opts)
	opts = opts or {}
	local h = tonumber(opts.height) or 170
	local card = Create("Frame", {
		Size = UDim2.new(1, -ROW_PAD * 2, 0, h), Position = UDim2.new(0, ROW_PAD, 0, 0),
		BackgroundColor3 = THEME.Element, ClipsDescendants = true, Parent = parent,
	}, {
		corner(12), stroke(THEME.ElementStroke, 1, 0.3), padding(12),
		Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(216, 216, 216)), Transparency = NumberSequence.new(0.9) }),
	})
	tagSearch(card, opts.title or "3D View")
	Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Font = FONT_BOLD, Text = tostring(opts.title or "3D View"),
		TextColor3 = THEME.Text, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Parent = card,
	})
	local stage = Create("Frame", { Position = UDim2.new(0, 0, 0, 26), Size = UDim2.new(1, 0, 1, -26), BackgroundTransparency = 1, Parent = card })
	local control, rotConn = {}, nil
	local function mount(obj)
		if rotConn then pcall(function() rotConn:Disconnect() end); rotConn = nil end
		for _, c in ipairs(stage:GetChildren()) do c:Destroy() end
		if not obj then
			Create("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = FONT, Text = "No model", TextColor3 = THEME.SubText, TextSize = 12, Parent = stage })
			return
		end
		pcall(function()
			local vpf = Create("ViewportFrame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Ambient = Color3.fromRGB(150, 150, 150), LightColor = Color3.fromRGB(255, 255, 255), Parent = stage })
			local cam = Instance.new("Camera"); cam.Parent = vpf; vpf.CurrentCamera = cam
			local world = Instance.new("Model"); world.Name = "View"; world.Parent = vpf
			local model = obj:Clone(); model.Parent = world
			-- frame the camera on the model's bounding box
			local ok, cf, size = pcall(function() return model:GetBoundingBox() end)
			if not ok then cf, size = CFrame.new(), Vector3.new(4, 4, 4) end
			local radius = math.max(size.X, size.Y, size.Z)
			local dist = radius * 2 + 2
			local center = cf.Position
			local angle = 0
			cam.CFrame = CFrame.new(center + Vector3.new(0, radius * 0.3, dist), center)
			if opts.rotate ~= false then
				rotConn = RunService.RenderStepped:Connect(function(dt)
					if not vpf.Parent then return end
					angle = (angle + dt * 0.6) % (math.pi * 2)
					cam.CFrame = CFrame.new(center + Vector3.new(math.sin(angle) * dist, radius * 0.3, math.cos(angle) * dist), center)
				end)
			end
		end)
	end
	mount(opts.model or opts.object)
	function control.SetModel(m) mount(m) end
	control.Instance = card
	return control
end

-- Collapsible content section ("GENERAL", "HITBOX", …)
function makeSection(host, accent, title, startClosed)
	local sectionSetOpen   -- set below when the section has a collapsible header
	local card = Create("Frame", {
		BackgroundColor3 = THEME.Group,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = host,
	}, {
		corner(10),
		stroke(THEME.Stroke, 1, 0.7),
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
			Padding = UDim.new(0, 6),
		}),
		Create("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 16) }),
	})

	if title and title ~= "" then
		local header = Create("TextButton", {
			Name = "SectionHeader",
			Size = UDim2.new(1, 0, 0, 30),
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
			Font = FONT_SEMI,
			Text = string.upper(tostring(title)),
			TextColor3 = THEME.SubText,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = header,
		})
		local chev = iconChevron(header, 15, THEME.SubText, "chevron-down")
		chev.AnchorPoint = Vector2.new(1, 0.5)
		chev.Position = UDim2.new(1, 0, 0.5, 0)
		local open = true
		local SEC_SLIDE = TweenInfo.new(0.36, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		sectionSetOpen = function(want, animate)
			open = want
			local info = animate == false and TweenInfo.new(0) or SEC_SLIDE
			tween(chev, { Rotation = open and 0 or 180 }, animate == false and TweenInfo.new(0) or TI.FAST)
			if open then
				bodyWrap.AutomaticSize = Enum.AutomaticSize.None
				local target = 0
				pcall(function() target = body.AbsoluteSize.Y end)
				if target <= 0 then
					bodyWrap.AutomaticSize = Enum.AutomaticSize.Y
					return
				end
				tween(bodyWrap, { Size = UDim2.new(1, 0, 0, target) }, info)
				-- slide the content down into place so it eases in instead of popping
				body.Position = UDim2.new(0, 0, 0, -10)
				tween(body, { Position = UDim2.new(0, 0, 0, 0) }, info)
				task.delay(info.Time + 0.03, function() if open then bodyWrap.AutomaticSize = Enum.AutomaticSize.Y end end)
			else
				local cur = 0
				pcall(function() cur = bodyWrap.AbsoluteSize.Y end)
				bodyWrap.AutomaticSize = Enum.AutomaticSize.None
				bodyWrap.Size = UDim2.new(1, 0, 0, cur)
				tween(bodyWrap, { Size = UDim2.new(1, 0, 0, 0) }, info)
			end
		end
		header.MouseButton1Click:Connect(function()
			-- a drag just happened on this panel: swallow the click so it doesn't collapse
			if card:GetAttribute("NemDidDrag") then return end
			sectionSetOpen(not open, true)
		end)
		if startClosed then task.defer(function() sectionSetOpen(false, false) end) end
	end

	local host = {}
	local function bind(elName)
		-- Tolerate method-style calls: Section:Button({...}) passes the section
		-- as the first arg, which would drop the user's options table.
		return function(a, b)
			if a == host then a = b end
			return Elements[elName](body, accent, a)
		end
	end
	host.Button = bind("Button")
	host.Toggle = bind("Toggle")
	host.Slider = bind("Slider")
	host.Dropdown = bind("Dropdown")
	host.Input = bind("Input")
	host.Keybind = bind("Keybind")
	host.ColorPicker = bind("ColorPicker")
	host.Paragraph = bind("Paragraph")
	host.Label = function(text, b)
		if text == host then text = b end -- tolerate Section:Label("X")
		return Elements.Label(body, accent, text)
	end
	host.Divider = bind("Divider")
	host.Listbox = bind("Listbox")
	-- extra elements
	host.Spacer = bind("Spacer")
	host.ProgressBar = bind("ProgressBar")
	host.Stat = bind("Stat")
	host.Checkbox = bind("Checkbox")
	host.CopyButton = bind("CopyButton")
	host.BarChart = bind("BarChart")
	host.Chart = bind("Chart")
	host.LineChart = bind("Chart")
	host.StackedChart = bind("StackedChart")
	host.RippleButton = bind("RippleButton")
	host.HoldButton = bind("HoldButton")
	host.SlideButton = bind("SlideButton")
	host.ShimmerLabel = bind("ShimmerLabel")
	host.ScrollHint = bind("ScrollHint")
	host.CursorTag = bind("CursorTag")
	host.CollapsibleSection = bind("CollapsibleSection")
	host.FAQ = bind("FAQ")
	host.Changelog = bind("Changelog")
	host.SegmentedPicker = bind("SegmentedPicker")
	host.GradientPicker = bind("GradientPicker")
	host.PinnedList = bind("PinnedList")
	host.EnhancedView = bind("EnhancedView")
	host.EnchancedView = bind("EnhancedView")   -- Syde-name alias
	host.SetOpen = function(o, animate) if sectionSetOpen then sectionSetOpen(o ~= false, animate) end end
	return host
end

-- Window
local function titleCase(str)
	str = tostring(str or "")
	return (string.gsub(string.lower(str), "(%a)([%w]*)", function(a, b)
		return string.upper(a) .. b
	end))
end

-- Key system. Window({ key = { keys = {"..."}, note = "...", saveKey = true } })
-- shows a small unlock card and blocks until a listed key is entered. A saved
-- key (Nemesis/key.txt by default) skips the prompt on later runs. Closing the
-- card raises an error so the caller's script stops instead of running keyless.
local function keyGate(kopts, windowTitle)
	local keys = {}
	if type(kopts.key) == "string" then keys[1] = kopts.key end
	if type(kopts.keys) == "table" then
		for _, k in ipairs(kopts.keys) do keys[#keys + 1] = k end
	end
	if #keys == 0 then return true end

	local function matches(text)
		text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
		for _, k in ipairs(keys) do
			if text == tostring(k) then return true end
		end
		return false
	end

	local saveKey = kopts.saveKey ~= false
	local keyFile = kopts.fileName or "Nemesis/key.txt"
	if saveKey and hasFileApi() then
		local saved = fsRead(keyFile)
		if saved and matches(saved) then return true end
	end

	ensureRoot()
	local result = nil

	local card = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 340, 0, 0),
		BackgroundColor3 = THEME.Group,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 60000,
		Parent = screenGui,
	}, { corner(12), stroke(THEME.Stroke, 1, 0.3), padXY(18, 16) })
	siblingShadow(card)
	makeDraggable(card, card)

	Create("TextLabel", {
		Size = UDim2.new(1, -28, 0, 20),
		BackgroundTransparency = 1,
		Font = FONT_SEMI,
		Text = tostring(kopts.title or ((windowTitle or "NEMESIS") .. "  |  key required")),
		TextColor3 = THEME.Text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 60001,
		Parent = card,
	})
	Create("TextLabel", {
		Position = UDim2.new(0, 0, 0, 24),
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = tostring(kopts.note or "Enter your key to continue."),
		TextColor3 = THEME.SubText,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 60001,
		Parent = card,
	})

	local field = Create("Frame", {
		Position = UDim2.new(0, 0, 0, 62),
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = THEME.Element,
		BorderSizePixel = 0,
		ZIndex = 60001,
		Parent = card,
	}, { corner(6) })
	local fieldStroke = stroke(THEME.ElementStroke, 1, 0.2)
	fieldStroke.Parent = field
	local box = Create("TextBox", {
		Size = UDim2.new(1, -24, 1, 0),
		Position = UDim2.new(0, 12, 0, 0),
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		Font = FONT_MONO,
		PlaceholderText = "key...",
		PlaceholderColor3 = THEME.Faint,
		Text = "",
		TextColor3 = THEME.Text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 60002,
		Parent = field,
	})

	local submit = Create("TextButton", {
		Position = UDim2.new(0, 0, 0, 102),
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = THEME.Accent,
		AutoButtonColor = false,
		Font = FONT_SEMI,
		Text = "UNLOCK",
		TextColor3 = accentTextColor(THEME.Accent),
		TextSize = 12,
		ZIndex = 60001,
		Parent = card,
	}, { corner(6) })

	local closeBtn = Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 4, 0, -2),
		Size = UDim2.new(0, 24, 0, 24),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 60002,
		Parent = card,
	})
	do local ci = iconX(closeBtn, 13, THEME.SubText); ci.ZIndex = 60003 end

	local function finish(ok)
		if result ~= nil then return end
		result = ok
		tween(card, { Size = UDim2.new(0, 340, 0, 0) }, TI.SLIDE)
		task.delay(0.22, function() card:Destroy() end)
	end

	local function trySubmit()
		if matches(box.Text) then
			if saveKey and hasFileApi() then
				fsEnsureFolder("Nemesis")
				fsWrite(keyFile, (box.Text:gsub("^%s+", ""):gsub("%s+$", "")))
			end
			finish(true)
		else
			tween(fieldStroke, { Color = DANGER, Transparency = 0 }, TI.FAST)
			local L = TweenInfo.new(0.045, Enum.EasingStyle.Linear)
			local base = card.Position
			local function at(dx)
				return UDim2.new(base.X.Scale, base.X.Offset + dx, base.Y.Scale, base.Y.Offset)
			end
			tween(card, { Position = at(4) }, L)
			task.delay(0.05, function() tween(card, { Position = at(-4) }, L) end)
			task.delay(0.10, function() tween(card, { Position = at(2) }, L) end)
			task.delay(0.15, function() tween(card, { Position = at(0) }, L) end)
			task.delay(0.5, function()
				tween(fieldStroke, { Color = THEME.ElementStroke, Transparency = 0.2 }, TI.EXP)
			end)
		end
	end
	submit.MouseButton1Click:Connect(trySubmit)
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then trySubmit() end
	end)
	closeBtn.MouseButton1Click:Connect(function() finish(false) end)

	tween(card, { Size = UDim2.new(0, 340, 0, 172) }, TI.OPEN)
	while result == nil do
		task.wait()
	end
	return result
end

function NEMESIS.Window(opts)
	opts = opts or {}
	-- opts.theme = { Background = Color3, Element = Color3, ... } overrides any
	-- THEME colour (see the Theme table near the top of this file for the keys)
	if type(opts.theme) == "table" then
		for key, value in pairs(opts.theme) do THEME[key] = value end
	elseif type(opts.theme) == "string" and NEMESIS.Themes[opts.theme] then
		-- a preset name works too: Window({ theme = "Light" })
		for key, value in pairs(NEMESIS.Themes[opts.theme]) do THEME[key] = value end
	end

	-- key system gate: nothing is built until the key checks out
	if type(opts.key) == "table" then
		if not keyGate(opts.key, opts.title) then
			error("NEMESIS: key required", 0)
		end
	end
	local accent = opts.accent or THEME.Accent
	local accentHex = hexOf(accent)
	local logoColor = opts.logoColor or THEME.Text -- neutral chrome tint; accent belongs to state
	local windowColumns = opts.columns or (IS_MOBILE and 1 or 2) -- default panel columns per page
	-- Canvas: draggable panel layout. autoArrange = reflow panels on window resize;
	-- drag = panels can be picked up by their header and rearranged. Read live by pages.
	local canvasAutoArrange = true
	local canvasDrag = false
	ensureRoot()

	local scale = computeScale()
	local W = opts.width or (IS_MOBILE and 600 or 960)
	local H = opts.height or (IS_MOBILE and 440 or 640)
	local TOPBAR_H = 52
	local SIDEBAR_W = IS_MOBILE and 148 or 176
	local FOOTER_H = 96
	local RADIUS = 12

	local root = Create("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, W, 0, H),
		BackgroundColor3 = THEME.Background,
		ClipsDescendants = true,
		Parent = screenGui,
	}, {
		corner(RADIUS),
		stroke(THEME.Stroke, 1, 0),
	})
	local rootScale = Create("UIScale", { Scale = scale, Parent = root })
	local lockToScreen = false   -- Settings > Lock to screen; read by the drag handler
	local dragSmooth = 0         -- Settings > Drag smoothness (0..1); read by the drag handler
	-- optional background image (set in Settings): sits above the window fill but
	-- below every panel, so cards read over it. Tinted + opacity adjustable.
	local bgImage = Create("ImageLabel", {
		Name = "BackgroundImage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Image = "",
		ImageTransparency = 1,
		ScaleType = Enum.ScaleType.Crop,
		Visible = false,
		ZIndex = 0,
		Parent = root,
	}, { corner(RADIUS) })
	-- the shadow lives outside the clipped window, as a sibling that follows it
	local rootShadowHolder = Create("Frame", {
		Name = "WindowShadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, W, 0, H),
		BackgroundTransparency = 1,
		ZIndex = 0,
		Parent = screenGui,
	}, { Create("UIScale", { Scale = scale }) })
	local rootShadowImg = dropShadow(rootShadowHolder, 0.35)   -- for shadow density/colour settings
	-- accent glow: the same soft shadow art, tinted to the accent and spread a bit
	-- wider, so the whole window casts a coloured halo (Syde "Glow"). Off by default;
	-- toggled from Settings. Recolours live with the accent.
	local glowImg, glowGrad
	do
		local art = loadArt(RF_SHADOW.name)
		if art then
			glowImg = Create("ImageLabel", {
				Name = "AccentGlow",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				Size = UDim2.new(1, RF_SHADOW.pad * 2 + 26, 1, RF_SHADOW.pad * 2 + 26),
				BackgroundTransparency = 1,
				Image = art,
				ImageColor3 = accent,
				ImageTransparency = 1,   -- hidden until SetGlow(true)
				ScaleType = Enum.ScaleType.Slice,
				SliceCenter = RF_SHADOW.slice,
				ZIndex = 0,
				Parent = rootShadowHolder,
			})
			accentProp(glowImg, "ImageColor3", accent)
			-- a two-stop accent gradient the "Rotate Gradient" setting can spin
			glowGrad = Create("UIGradient", {
				Color = ColorSequence.new(accent, accentLight(accent)), Rotation = 0, Parent = glowImg,
			})
			onAccent(function(c) pcall(function() glowGrad.Color = ColorSequence.new(c, accentLight(c)) end) end)
		end
	end
	pcall(function()
		root:GetPropertyChangedSignal("Position"):Connect(function() rootShadowHolder.Position = root.Position end)
		root:GetPropertyChangedSignal("Size"):Connect(function() rootShadowHolder.Size = root.Size end)
		root:GetPropertyChangedSignal("Visible"):Connect(function() rootShadowHolder.Visible = root.Visible end)
		root.AncestryChanged:Connect(function()
			if not root.Parent then rootShadowHolder:Destroy() end
		end)
	end)

	-- Top bar: logo + wordmark | top tabs | search + min/close
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
	makeDraggable(root, topbar, function() return lockToScreen end, function() return dragSmooth end)

	-- logo: the real NEMESIS brand image (downloaded + loaded via getcustomasset,
	-- no Roblox upload). Falls back to a gradient "N" tile on executors without
	-- custom-asset support. opts.logo = <assetId> forces an uploaded image.
	local logoSpec = (opts.logo ~= nil) and resolveIcon(opts.logo) or nil
	local brandAsset = (opts.logo == nil) and loadBrandLogo() or nil

	-- brand: the NEMESIS wordmark image (its own purple/white colours, so it is
	-- not tinted). Falls back to a bold "NEMESIS" text if the image cannot load.
	local WORDMARK_H, WORDMARK_W = 22, 148   -- 6.72:1 aspect
	local logoImage
	local wordmark  -- kept for Win.SetTitle compatibility (text fallback)
	if brandAsset or logoSpec then
		logoImage = Create("ImageLabel", {
			Position = UDim2.new(0, 16, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.new(0, WORDMARK_W, 0, WORDMARK_H),
			BackgroundTransparency = 1,
			Image = brandAsset or "",
			ImageColor3 = Color3.new(1, 1, 1),
			ScaleType = Enum.ScaleType.Fit,
			Parent = topbar,
		})
		if not brandAsset and logoSpec then applyIcon(logoImage, logoSpec) end
	else
		wordmark = Create("TextLabel", {
			Position = UDim2.new(0, 16, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.new(0, 120, 1, 0),
			BackgroundTransparency = 1,
			Font = FONT_BOLD,
			Text = string.upper(tostring(opts.title or "NEMESIS")),
			TextColor3 = THEME.Text,
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = topbar,
		})
	end
	local logoGrad  -- kept for Win.SetLogoGradient compatibility
	-- a machined tick separating the brand from the tabs
	Create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16 + WORDMARK_W + 14, 0.5, 0),
		Size = UDim2.new(0, 1, 0, 16),
		BackgroundColor3 = THEME.Stroke,
		BorderSizePixel = 0,
		Parent = topbar,
	})
	-- seam under the topbar
	Create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = THEME.Stroke,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = topbar,
	})

	-- centring frame between the logo/title and the right-side icons; the tabs
	-- inside it stay centred and reflow automatically as the window resizes
	local tabArea = Create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 190, 0.5, 0),
		Size = UDim2.new(1, -(190 + 176), 1, 0),
		BackgroundTransparency = 1,
		-- confine the tab dock between the logo and the right-side icons so a wide
		-- dock (many tabs / long names) clips instead of bleeding over them
		ClipsDescendants = true,
		Parent = topbar,
	}, {
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	-- navigation state (declared before the dock so its closures capture these)
	local Win = {}
	local tabs = {}
	local activeTab
	local tabBarOrder = 0

	-- tab dock: rounded track holding pill tabs; a sliding indicator pill marks
	-- the open tab and glides between pills
	local tabScale = Create("UIScale", { Scale = 1 })
	local tabBar = Create("CanvasGroup", {
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		GroupTransparency = 0,
		Parent = tabArea,
	}, {
		tabScale,
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local dockTrack = Create("Frame", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 0, 38),
		BackgroundColor3 = THEME.Element,
		BackgroundTransparency = 0.25,
		Parent = tabBar,
	}, { corner(19), stroke(THEME.Stroke, 1, 0.6) })
	local INDICATOR_TEXT = Color3.fromRGB(26, 27, 30)
	local dockIndicator = Create("Frame", {
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.fromOffset(0, 30),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = dockTrack,
	}, {
		corner(15),
		Create("UIGradient", {
			Rotation = 105,
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(226, 226, 228)),
		}),
	})
	local dockButtons = Create("Frame", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = dockTrack,
	}, {
		padXY(4, 4),
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 2),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local function moveIndicator(animate)
		local target = activeTab and activeTab.pill
		if not target then
			dockIndicator.BackgroundTransparency = 1
			return
		end
		local x, w = 4, 0
		pcall(function()
			x = target.AbsolutePosition.X - dockTrack.AbsolutePosition.X
			w = target.AbsoluteSize.X
		end)
		if w <= 0 then
			-- text layout not measured yet (throttled executors): no slide, the
			-- pill tints alone carry the state until a real measure arrives
			dockIndicator.BackgroundTransparency = 1
			return
		end
		local goalPos = UDim2.fromOffset(x, 4)
		local goalSize = UDim2.fromOffset(w, 30)
		if animate then
			tween(dockIndicator, { Position = goalPos, Size = goalSize, BackgroundTransparency = 0 }, TI.TAB)
		else
			dockIndicator.Position = goalPos
			dockIndicator.Size = goalSize
			dockIndicator.BackgroundTransparency = 0
		end
	end

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
	local function topbarIcon(iconName, fallback, xOffset, glyphSize, hoverColor)
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
		local function tint(c, info)
			if img and img.Visible then tween(img, { ImageColor3 = c }, info or TI.HOVER) else tween(b, { TextColor3 = c }, info or TI.HOVER) end
		end
		b.MouseEnter:Connect(function() tint(hoverColor or accent) end)
		b.MouseLeave:Connect(function() tint(THEME.SubText, TI.HOVEROFF) end)
		return b, setIcon
	end

	local closeBtn = topbarIcon("x", "\u{2715}", -16, 16, DANGER)
	local minBtn, setMinIcon = topbarIcon("minus", "\u{2013}", -48, 18)

	-- gear opens the settings panel, bot opens the AI panel (forward-declared
	-- open funcs are filled in once the panels are built)
	local openSettingsPanel, openAIPanel
	local gearBtn = topbarIcon("settings", "\u{2699}", -80, 16)
	local aiBtn = topbarIcon("bot", "\u{2728}", -112, 16)
	gearBtn.MouseButton1Click:Connect(function() if openSettingsPanel then openSettingsPanel() end end)
	aiBtn.MouseButton1Click:Connect(function() if openAIPanel then openAIPanel() end end)

	-- search is a small icon; clicking it opens the search bar over the tabs
	local searchBtn = topbarIcon("search", "\u{1F50E}", -144, 16)

	-- the search bar that animates in over the tab area
	local searchBar = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 7, 0.5, 0),
		Size = UDim2.new(0, 360, 0, 30),
		BackgroundColor3 = THEME.Element,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Visible = false,
		ZIndex = 6,
		Parent = topbar,
	}, { corner(15), stroke(THEME.ElementStroke, 1, 1) })
	local searchBarStroke = searchBar:FindFirstChildOfClass("UIStroke")
	local searchBarIcon = Create("ImageLabel", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.new(0, 16, 0, 16),
		BackgroundTransparency = 1,
		ImageColor3 = THEME.SubText,
		ImageTransparency = 1,
		ZIndex = 7,
		Parent = searchBar,
	})
	local hasSearchIcon = applyIcon(searchBarIcon, resolveIcon("search"))
	local searchBox = Create("TextBox", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, hasSearchIcon and 34 or 12, 0, 0),
		Size = UDim2.new(1, hasSearchIcon and -92 or -70, 1, 0),
		Font = FONT,
		PlaceholderText = "Search (Ctrl + K)",
		Text = "",
		TextColor3 = THEME.Text,
		PlaceholderColor3 = THEME.Faint,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		TextTransparency = 1,
		ZIndex = 7,
		Parent = searchBar,
	})
	-- match readout: "12/38" in mono, counting visible vs searchable rows
	local searchCount = Create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0, 48, 1, 0),
		BackgroundTransparency = 1,
		Font = FONT_MONO,
		Text = "",
		TextColor3 = THEME.SubText,
		TextSize = 12,
		TextTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 7,
		Parent = searchBar,
	})

	-- Body: sidebar (with footer) | content (header + pages)
	local body = Create("Frame", {
		Position = UDim2.new(0, 0, 0, TOPBAR_H),
		Size = UDim2.new(1, 0, 1, -TOPBAR_H),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = root,
	})

	-- sidebar as a floating rounded panel (card), inset from the window edges,
	-- with a visible border; no divider between it and the content
	local SB_MARGIN = 10
	local SB_GAP = 10
	local sidebarBG = Create("Frame", {
		Position = UDim2.new(0, SB_MARGIN, 0, SB_MARGIN),
		Size = UDim2.new(0, SIDEBAR_W, 1, -SB_MARGIN * 2),
		BackgroundColor3 = THEME.Sidebar,
		BorderSizePixel = 0,
		Parent = body,
	}, { corner(12), stroke(THEME.Stroke, 1, 0.5) })

	-- scroll region (tab sidebars stack here, one visible at a time), leaving
	-- room for the status footer pinned to the card's bottom
	local SB_FOOTER_H = 50
	local sidebarScroll = Create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -SB_FOOTER_H),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 2,
		Parent = sidebarBG,
	})

	-- footer: green status dot + game / status lines + live FPS
	local sbFooter = Create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, SB_FOOTER_H),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = sidebarBG,
	})
	Create("Frame", {
		Size = UDim2.new(1, -24, 0, 1),
		Position = UDim2.new(0, 12, 0, 0),
		BackgroundColor3 = THEME.RowDivider,
		BorderSizePixel = 0,
		Parent = sbFooter,
	})
	-- player profile: avatar headshot + display name + @username, with a small
	-- online dot on the avatar. SetGame / SetStatus still override the two lines.
	local lp = localPlayer()
	local profName, profUser, profId
	pcall(function()
		if lp then
			profName = lp.DisplayName or lp.Name
			profUser = "@" .. (lp.Name or "player")
			profId = lp.UserId
		end
	end)
	local avatar = Create("ImageLabel", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 1),
		Size = UDim2.new(0, 30, 0, 30),
		BackgroundColor3 = THEME.Element,
		Image = profId and ("rbxthumb://type=AvatarHeadShot&id=%d&w=60&h=60"):format(profId) or "",
		Parent = sbFooter,
	}, { corner(8), stroke(THEME.ElementStroke, 1, 0.4) })
	local statusDot = Create("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 1, 1, 1),
		Size = UDim2.new(0, 9, 0, 9),
		BackgroundColor3 = THEME.Good,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = avatar,
	}, { corner(5), stroke(THEME.Sidebar, 2, 0) })
	local gameLabel = Create("TextLabel", {
		Position = UDim2.new(0, 50, 0, 8),
		Size = UDim2.new(1, -110, 0, 16),
		BackgroundTransparency = 1,
		Font = FONT_SEMI,
		Text = tostring(profName or opts.game or "NEMESIS"),
		TextColor3 = THEME.Text,
		TextSize = 13,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = sbFooter,
	})
	local statusLabel = Create("TextLabel", {
		Position = UDim2.new(0, 50, 0, 25),
		Size = UDim2.new(1, -110, 0, 14),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = tostring(profUser or opts.status or ""),
		TextColor3 = THEME.SubText,
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = sbFooter,
	})
	local fpsChip = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 1),
		Size = UDim2.new(0, 52, 0, 18),
		BackgroundColor3 = THEME.Element,
		Parent = sbFooter,
	}, { corner(3) })
	local fpsLabel = Create("TextLabel", {
		Size = UDim2.new(1, -8, 1, 0),
		Position = UDim2.new(0, 4, 0, 0),
		BackgroundTransparency = 1,
		Font = FONT_MONO,
		Text = "",
		TextColor3 = THEME.SubText,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = fpsChip,
	})
	local fpsConn
	local sessConn   -- Settings SESSION heartbeat; torn down in Win.Destroy
	do
		-- live FPS readout only. Motion is user-controlled via the Settings
		-- "Animations" toggle; nothing auto-reduces animation on fps dips.
		local frames, acc = 0, 0
		local ok = pcall(function()
			fpsConn = RunService.Heartbeat:Connect(function(dt)
				frames = frames + 1
				acc = acc + (tonumber(dt) or 0)
				if acc >= 0.5 then
					local fps = math.floor(frames / acc + 0.5)
					fpsLabel.Text = tostring(fps) .. " fps"
					frames, acc = 0, 0
				end
			end)
		end)
		if not ok then fpsChip.Visible = false end
	end

	local content = Create("Frame", {
		Position = UDim2.new(0, SB_MARGIN + SIDEBAR_W + SB_GAP, 0, 0),
		Size = UDim2.new(1, -(SB_MARGIN + SIDEBAR_W + SB_GAP), 1, 0),
		BackgroundTransparency = 1,
		Parent = body,
	})

	-- content header: breadcrumb left, config controls right
	local CONTENT_PAD = 12
	local header = Create("Frame", {
		Position = UDim2.new(0, 0, 0, 10),
		Size = UDim2.new(1, 0, 0, 34),
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
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = header,
	})

	-- pages host (each page body lives here; one visible at a time)
	local pagesHost = Create("Frame", {
		Position = UDim2.new(0, 0, 0, 48),
		Size = UDim2.new(1, 0, 1, -48),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = content,
	})
	-- top/bottom fade overlays: content gently fades into the background at the
	-- scroll edges (background-colored gradient, sitting above the page content).
	-- The bottom fade is taller and rounded so it also restores the window's
	-- rounded bottom-right corner (it would otherwise square it off).
	local TOP_FADE_H, BOT_FADE_H = 28, 58
	local topFade = Create("Frame", {
		Size = UDim2.new(1, 0, 0, TOP_FADE_H),
		BackgroundColor3 = THEME.Background,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = pagesHost,
	}, { Create("UIGradient", { Rotation = 90, Transparency = numSeq(0, 1) }) })
	local botFade = Create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, BOT_FADE_H),
		BackgroundColor3 = THEME.Background,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = pagesHost,
	}, { corner(RADIUS), Create("UIGradient", { Rotation = 90, Transparency = numSeq(1, 0) }) })
	-- the fades only appear when there is actually content to scroll toward: top
	-- fade when scrolled down, bottom fade when more content sits below
	local fadeConns = {}
	local function updateFades(body)
		if not body then topFade.BackgroundTransparency = 1; botFade.BackgroundTransparency = 1; return end
		local pos, canvasY, viewY = 0, 0, 0
		pcall(function()
			pos = body.CanvasPosition.Y
			canvasY = body.AbsoluteCanvasSize.Y
			viewY = body.AbsoluteWindowSize and body.AbsoluteWindowSize.Y or body.AbsoluteSize.Y
		end)
		local maxScroll = math.max(0, canvasY - viewY)
		topFade.BackgroundTransparency = 1 - math.clamp(pos / 24, 0, 1)
		botFade.BackgroundTransparency = 1 - math.clamp((maxScroll - pos) / 24, 0, 1)
	end
	local function bindFades(body)
		for _, c in ipairs(fadeConns) do pcall(function() c:Disconnect() end) end
		fadeConns = {}
		if not body then updateFades(nil); return end
		pcall(function()
			fadeConns[#fadeConns + 1] = body:GetPropertyChangedSignal("CanvasPosition"):Connect(function() updateFades(body) end)
			fadeConns[#fadeConns + 1] = body:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function() updateFades(body) end)
			fadeConns[#fadeConns + 1] = body:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() updateFades(body) end)
		end)
		task.defer(function() updateFades(body) end)
	end

	-- open animation (Syde-style): the window unfolds from a smaller centred box
	-- to full size on a smooth Quint curve (the shadow holder mirrors the size)
	root.Size = UDim2.new(0, math.floor(W * 0.82), 0, math.floor(H * 0.82))
	tween(root, { Size = UDim2.new(0, W, 0, H) }, TI.OPEN)

	-- Navigation state

	local searchSetCount
	local function runSearch(text)
		local page = activeTab and activeTab.activePage
		if not page then return end
		text = string.lower(text or "")
		local total, hits = 0, 0
		for _, d in ipairs(page.body:GetDescendants()) do
			local ok, tag = pcall(function() return d:GetAttribute("NemesisSearch") end)
			if ok and tag ~= nil then
				total = total + 1
				local hit = (text == "") or (string.find(string.lower(tag), text, 1, true) ~= nil)
				d.Visible = hit
				if hit then hits = hits + 1 end
			end
		end
		if searchSetCount then
			searchSetCount(text ~= "" and (tostring(hits) .. "/" .. tostring(total)) or "")
		end
	end

	searchBox:GetPropertyChangedSignal("Text"):Connect(function() runSearch(searchBox.Text) end)

	-- search: the field deploys over the tab strip, tabs fade out underneath
	local searchOpen = false
	local function sQuint(t) return TweenInfo.new(t, Enum.EasingStyle.Quint, Enum.EasingDirection.Out) end
	-- the search bar centres over the tab area (+7 from topbar centre) and never
	-- grows wider than the tab area, so it can't cover the right-side icon cluster
	local function searchGeom() return math.clamp(tabArea.AbsoluteSize.X - 16, 120, 360) end
	searchSetCount = function(txt)
		searchCount.Text = txt
	end
	local function openSearch()
		if searchOpen then return end
		searchOpen = true
		tween(tabBar, { GroupTransparency = 1 }, sQuint(0.14))
		task.delay(0.15, function() if searchOpen then tabBar.Visible = false end end)
		local sw = searchGeom()
		searchBar.Visible = true
		searchBar.BackgroundTransparency = 1
		searchBar.Size = UDim2.new(0, sw, 0, 0)
		searchBar.Position = UDim2.new(0.5, 7, 0.5, 0)
		searchBox.TextTransparency = 1
		searchBarIcon.ImageTransparency = 1
		searchCount.TextTransparency = 1
		if searchBarStroke then searchBarStroke.Transparency = 1 end
		pcall(function() searchBox:CaptureFocus() end)
		tween(searchBar, { BackgroundTransparency = 0, Size = UDim2.new(0, sw, 0, 30) }, sQuint(0.22))
		tween(searchBox, { TextTransparency = 0 }, sQuint(0.22))
		tween(searchBarIcon, { ImageTransparency = 0.2 }, sQuint(0.22))
		tween(searchCount, { TextTransparency = 0.2 }, sQuint(0.22))
		if searchBarStroke then tween(searchBarStroke, { Transparency = 0.2 }, sQuint(0.22)) end
	end
	local function closeSearch()
		if not searchOpen then return end
		searchOpen = false
		tween(searchBar, { BackgroundTransparency = 1, Size = UDim2.new(0, searchGeom(), 0, 0) }, sQuint(0.14))
		tween(searchBox, { TextTransparency = 1 }, sQuint(0.12))
		tween(searchBarIcon, { ImageTransparency = 1 }, sQuint(0.12))
		tween(searchCount, { TextTransparency = 1 }, sQuint(0.12))
		if searchBarStroke then tween(searchBarStroke, { Transparency = 1 }, sQuint(0.12)) end
		searchBox.Text = ""
		runSearch("")
		tabBar.Visible = true
		tabBar.GroupTransparency = 1
		tween(tabBar, { GroupTransparency = 0 }, sQuint(0.2))
		task.delay(0.16, function()
			if not searchOpen then searchBar.Visible = false end
		end)
	end
	searchBtn.MouseButton1Click:Connect(openSearch)
	searchBox.FocusLost:Connect(closeSearch)

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

	local SIDEBAR_PAGE_TEXT = Color3.fromRGB(168, 173, 180)  -- inactive sub-tab label
	local function applyPageVisual(tab, page, animate)
		for _, p in ipairs(tab.pages) do
			local on = (p == page)
			p.row.BackgroundColor3 = THEME.SidebarActive
			if animate then
				tween(p.row, { BackgroundTransparency = on and 0 or 1 }, TI.EXP)
				tween(p.label, { TextColor3 = on and THEME.Text or SIDEBAR_PAGE_TEXT }, TI.EXP)
				if p.icon then tween(p.icon, { ImageColor3 = on and accent or THEME.SubText }, TI.EXP) end
			else
				p.row.BackgroundTransparency = on and 0 or 1
				p.label.TextColor3 = on and THEME.Text or SIDEBAR_PAGE_TEXT
				if p.icon then p.icon.ImageColor3 = on and accent or THEME.SubText end
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
		-- the content is shown at full size with no per-card scale/slide: resizing
		-- the cards on every tab switch read as a jarring "everything grows" jump.
		-- The sliding dock indicator carries the switch; any left-over UIScale from
		-- an earlier build is snapped back to 1 so nothing stays shrunk.
		page.body.Position = UDim2.new(0, 0, 0, 0)
		pcall(function()
			for _, card in ipairs(page.columnsHolder:GetChildren()) do
				local sc = card:IsA("Frame") and card:FindFirstChildOfClass("UIScale")
				if sc then sc.Scale = 1 end
			end
		end)
		bindFades(page.body)
		setCrumb(tab, page)
		runSearch(searchBox.Text)
	end

	-- paint a top-tab segment for its active/inactive state (smoothly when animate)
	local function paintTab(tab, active, animate)
		local info = animate and TI.FAST or TweenInfo.new(0)
		local idle = THEME.SubText
		tween(tab.label, { TextColor3 = active and INDICATOR_TEXT or idle }, info)
		if tab.icon then
			tween(tab.icon, { ImageColor3 = active and INDICATOR_TEXT or idle }, info)
		end
	end

	local function showTab(tab)
		closeOpenDropdown()
		activeTab = tab
		for i, t in ipairs(tabs) do
			t.sidebarFrame.Visible = (t == tab)
			paintTab(t, t == tab, true)
			for _, p in ipairs(t.pages) do p.body.Visible = false end
		end
		moveIndicator(true)
		local pg = tab.activePage or tab.pages[1]
		if pg then
			showPage(tab, pg, true)
		else
			setCrumb(tab, nil)
		end
	end

	-- ===== configs: every { flag = ... } element serialized to json on disk =====
	local cfgFolder = nil
	if hasFileApi() and opts.config ~= false then
		local safe = tostring(opts.title or "NEMESIS"):gsub("[^%w%-_ ]", ""):gsub("%s+", "_")
		cfgFolder = (type(opts.config) == "table" and opts.config.folder)
			or (type(opts.folder) == "string" and opts.folder)
			or ("Nemesis/" .. safe)
	end
	local autoloadFile = cfgFolder and (cfgFolder .. "/autoload.txt")

	local function sanitizeName(name)
		name = tostring(name or ""):gsub("[^%w%-_ ]", ""):gsub("%s+", "_")
		if name == "" or name == "autoload" then return nil end
		return name
	end
	local function cfgPath(name) return cfgFolder .. "/" .. name .. ".json" end

	function Win.SaveConfig(name)
		name = sanitizeName(name)
		if not (cfgFolder and name) then return false end
		fsEnsureFolder("Nemesis")
		fsEnsureFolder(cfgFolder)
		local out = {}
		for flag, rec in pairs(flagged) do
			local ok, v = pcall(packValue, rec.kind, rec)
			if ok and v ~= nil then out[flag] = v end
		end
		local ok = fsWrite(cfgPath(name), jsonEncode(out))
		if ok and type(opts.onSave) == "function" then pcall(opts.onSave, name) end
		return ok
	end

	function Win.LoadConfig(name)
		name = sanitizeName(name)
		if not (cfgFolder and name) then return false end
		local raw = fsRead(cfgPath(name))
		local data = raw and jsonDecode(raw)
		if type(data) ~= "table" then
			-- not on disk: still hand the name to the script's own handler so
			-- preset names passed via opts.configs keep working
			if type(opts.onConfig) == "function" then pcall(opts.onConfig, name) end
			return false
		end
		for flag, v in pairs(data) do
			local rec = flagged[flag]
			if rec then pcall(unpackValue, rec.kind, rec, v) end
		end
		if type(opts.onConfig) == "function" then pcall(opts.onConfig, name) end
		return true
	end

	function Win.ListConfigs()
		local names, seen = {}, {}
		if cfgFolder then
			for _, p in ipairs(fsList(cfgFolder)) do
				local n = p:match("([^/\\]+)%.json$")
				if n and not seen[n] then seen[n] = true; names[#names + 1] = n end
			end
		end
		if type(opts.configs) == "table" then
			for _, raw in ipairs(opts.configs) do
				local n = sanitizeName(raw)
				if n and not seen[n] then seen[n] = true; names[#names + 1] = n end
			end
		end
		table.sort(names)
		return names
	end

	function Win.DeleteConfig(name)
		name = sanitizeName(name)
		if not (cfgFolder and name) then return false end
		fsDelete(cfgPath(name))
		if Win.GetAutoload() == name then Win.SetAutoload(nil) end
		return true
	end

	function Win.SetAutoload(name)
		if not autoloadFile then return end
		if name == nil then
			fsDelete(autoloadFile)
		else
			fsWrite(autoloadFile, tostring(name))
		end
	end
	function Win.GetAutoload()
		local v = autoloadFile and fsRead(autoloadFile)
		if v then v = v:gsub("%s+$", "") end
		return v ~= "" and v or nil
	end

	-- header config controls: a pill showing the active config (click for the
	-- config panel) + a save icon. Right-click a config row to mark it autoload.
	local cfgCurrent = "default"
	local updatePill -- set when the header pill exists
	if cfgFolder or type(opts.configs) == "table" then
		breadcrumb.Size = UDim2.new(1, -216, 1, 0)

		local pill = Create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -32, 0.5, 0),
			Size = UDim2.new(0, 140, 0, 24),
			BackgroundColor3 = THEME.Element,
			AutoButtonColor = false,
			Text = "",
			Parent = header,
		}, { corner(12), stroke(THEME.ElementStroke, 1, 0.35) })
		local pillLabel = Create("TextLabel", {
			Position = UDim2.new(0, 10, 0, 0),
			Size = UDim2.new(1, -32, 1, 0),
			BackgroundTransparency = 1,
			Font = FONT_MED,
			Text = cfgCurrent,
			TextColor3 = THEME.Text,
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = pill,
		})
		local pillChev = Create("ImageLabel", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.new(0, 12, 0, 12),
			BackgroundTransparency = 1,
			ImageColor3 = THEME.SubText,
			Parent = pill,
		})
		local pillGlyph
		if not applyIcon(pillChev, resolveIcon("chevron-down")) then
			pillGlyph = Create("TextLabel", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.new(0, 14, 0, 14),
				BackgroundTransparency = 1,
				Font = FONT,
				Text = "\u{25BE}",
				TextColor3 = THEME.SubText,
				TextSize = 12,
				Parent = pill,
			})
		end

		local saveBtn = iconButton(header, "save", "\u{1F5AB}", 24, { bg = THEME.Element, iconSize = 13 })
		saveBtn.AnchorPoint = Vector2.new(1, 0.5)
		saveBtn.Position = UDim2.new(1, 0, 0.5, 0)
		local sbStroke = stroke(THEME.ElementStroke, 1, 0.35)
		sbStroke.Parent = saveBtn

		local function setCurrent(name)
			cfgCurrent = name
			pillLabel.Text = name
		end
		updatePill = setCurrent

		saveBtn.MouseButton1Click:Connect(function()
			if Win.SaveConfig(cfgCurrent) then
				NEMESIS.Notify({ title = "Config saved", content = cfgCurrent, duration = 2, icon = "save" })
			end
		end)

		local panel
		local outsideConn
		local function closePanel()
			if not panel then return end
			local p = panel
			panel = nil
			_ddCurrent = nil
			if outsideConn then outsideConn:Disconnect(); outsideConn = nil end
			tween(p, { Size = UDim2.new(0, 190, 0, 0) }, TI.FAST)
			task.delay(0.15, function() p:Destroy() end)
		end

		local function openPanel()
			if panel then closePanel(); return end
			closeOpenDropdown()
			local layer = dropdownLayer(header)
			if not layer then return end

			local names = Win.ListConfigs()
			if #names == 0 then names = { cfgCurrent } end
			local autoName = Win.GetAutoload()

			local ROWS_H = #names * 28
			local FOOT_H = 34
			local fullH = ROWS_H + FOOT_H + 12
			panel = Create("Frame", {
				Position = UDim2.new(0, pill.AbsolutePosition.X, 0, pill.AbsolutePosition.Y + pill.AbsoluteSize.Y + 6),
				Size = UDim2.new(0, 190, 0, 0),
				BackgroundColor3 = THEME.Group,
				BorderSizePixel = 0,
				ClipsDescendants = true,
				ZIndex = 50001,
				Parent = layer,
			}, { corner(10), stroke(THEME.Stroke, 1, 0.3), padXY(6, 6) })
			siblingShadow(panel)
			_ddCurrent = { close = closePanel }
			tween(panel, { Size = UDim2.new(0, 190, 0, fullH) }, TI.EXP)

			outsideConn = UserInputService.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
				if not panel then return end
				local p = input.Position
				local ap, as = panel.AbsolutePosition, panel.AbsoluteSize
				local bp, bs = pill.AbsolutePosition, pill.AbsoluteSize
				local inPanel = p.X >= ap.X and p.X <= ap.X + as.X and p.Y >= ap.Y and p.Y <= ap.Y + as.Y
				local inPill = p.X >= bp.X and p.X <= bp.X + bs.X and p.Y >= bp.Y and p.Y <= bp.Y + bs.Y
				if not inPanel and not inPill then closePanel() end
			end)

			for i, name in ipairs(names) do
				local isAuto = (name == autoName)
				local rowBtn = Create("TextButton", {
					Position = UDim2.new(0, 0, 0, (i - 1) * 28),
					Size = UDim2.new(1, 0, 0, 28),
					BackgroundColor3 = THEME.ElementHover,
					BackgroundTransparency = 1,
					AutoButtonColor = false,
					Font = (name == cfgCurrent) and FONT_SEMI or FONT,
					Text = (isAuto and "\u{2605} " or "") .. name,
					TextColor3 = (name == cfgCurrent) and THEME.Text or THEME.SubText,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 50002,
					Parent = panel,
				}, { corner(3), padXY(8, 0) })
				rowBtn.MouseEnter:Connect(function() tween(rowBtn, { BackgroundTransparency = 0 }, TI.HOVER) end)
				rowBtn.MouseLeave:Connect(function() tween(rowBtn, { BackgroundTransparency = 1 }, TI.HOVEROFF) end)
				rowBtn.MouseButton1Click:Connect(function()
					setCurrent(name)
					Win.LoadConfig(name)
					closePanel()
				end)
				rowBtn.MouseButton2Click:Connect(function()
					Win.SetAutoload(isAuto and nil or name)
					NEMESIS.Notify({
						title = "Autoload",
						content = isAuto and "cleared" or (name .. " loads on start"),
						duration = 2,
					})
					closePanel()
				end)
			end

			-- footer actions: new / save / delete (delete hovers danger)
			local function actionBtn(text, xFrac, hoverC, cb)
				local b = Create("TextButton", {
					Position = UDim2.new(xFrac, xFrac > 0 and 3 or 0, 1, -28),
					Size = UDim2.new(1 / 3, xFrac > 0 and -3 or -3, 0, 26),
					BackgroundColor3 = THEME.Element,
					AutoButtonColor = false,
					Font = FONT_SEMI,
					Text = text,
					TextColor3 = THEME.SubText,
					TextSize = 12,
					ZIndex = 50002,
					Parent = panel,
				}, { corner(3) })
				b.MouseEnter:Connect(function() tween(b, { TextColor3 = hoverC or THEME.Text }, TI.HOVER) end)
				b.MouseLeave:Connect(function() tween(b, { TextColor3 = THEME.SubText }, TI.HOVEROFF) end)
				b.MouseButton1Click:Connect(cb)
				return b
			end
			actionBtn("NEW", 0, nil, function()
				local n = 1
				local taken = {}
				for _, existing in ipairs(Win.ListConfigs()) do taken[existing] = true end
				while taken["config" .. n] do n = n + 1 end
				local name = "config" .. n
				if Win.SaveConfig(name) then
					setCurrent(name)
					NEMESIS.Notify({ title = "Config created", content = name, duration = 2 })
				end
				closePanel()
			end)
			actionBtn("SAVE", 1 / 3, nil, function()
				if Win.SaveConfig(cfgCurrent) then
					NEMESIS.Notify({ title = "Config saved", content = cfgCurrent, duration = 2 })
				end
				closePanel()
			end)
			actionBtn("DEL", 2 / 3, DANGER, function()
				Win.DeleteConfig(cfgCurrent)
				NEMESIS.Notify({ title = "Config deleted", content = cfgCurrent, duration = 2 })
				local left = Win.ListConfigs()
				setCurrent(left[1] or "default")
				closePanel()
			end)
		end

		pill.MouseButton1Click:Connect(openPanel)
		pill.MouseEnter:Connect(function() tween(pill, { BackgroundColor3 = THEME.ElementHover }, TI.HOVER) end)
		pill.MouseLeave:Connect(function() tween(pill, { BackgroundColor3 = THEME.Element }, TI.HOVER) end)
	end

	-- autoload: apply the marked config shortly after the script builds its UI
	if cfgFolder then
		task.delay(0.7, function()
			local name = Win.GetAutoload()
			if name then
				if updatePill then updatePill(name) else cfgCurrent = name end
				pcall(Win.LoadConfig, name)
			end
		end)
	end

	-- ===== runtime theme switching =====
	-- Win.SetTheme("Light") / Win.SetTheme({ Background = ... }) recolours the
	-- live UI by matching every gui object's colours against the outgoing
	-- palette, then updates THEME so anything built later uses the new one
	local THEME_COLOR_PROPS = { "BackgroundColor3", "TextColor3", "ImageColor3", "PlaceholderColor3", "ScrollBarImageColor3", "Color" }
	function Win.SetTheme(theme)
		local palette = (type(theme) == "string") and NEMESIS.Themes[theme] or theme
		if type(palette) ~= "table" then return false end

		local keys = {}
		for k in pairs(NEMESIS.Themes.Dark) do keys[#keys + 1] = k end
		table.sort(keys)
		local oldByHex = {}
		for _, k in ipairs(keys) do
			local c = THEME[k]
			if typeof(c) == "Color3" then
				local h = hexOf(c)
				if oldByHex[h] == nil then oldByHex[h] = k end
			end
		end

		for k, v in pairs(palette) do
			if k ~= "Accent" then THEME[k] = v end
		end

		local function recolor(inst)
			for _, prop in ipairs(THEME_COLOR_PROPS) do
				pcall(function()
					local cur = inst[prop]
					if typeof(cur) == "Color3" then
						local key = oldByHex[hexOf(cur)]
						if key and typeof(THEME[key]) == "Color3" then
							inst[prop] = THEME[key]
						end
					end
				end)
			end
		end
		pcall(function()
			for _, inst in ipairs(screenGui:GetDescendants()) do
				recolor(inst)
			end
		end)

		-- rebuild the colour-embedding rich text + active page tint
		if activeTab and activeTab.activePage then
			pcall(function() applyPageVisual(activeTab, activeTab.activePage, false) end)
			pcall(function() setCrumb(activeTab, activeTab.activePage) end)
		end
		return true
	end

	-- Win.SetFont(fontName or nil): swap the whole menu's font family live. Each
	-- text instance keeps its own weight/style; nil restores Inter.
	local fontBgOverride = nil
	function Win.SetFont(fontName)
		local family = INTER
		if type(fontName) == "string" and fontName ~= "" and fontName ~= "Auto" and fontName ~= "Inter" then
			local ok, enumFont = pcall(function() return Enum.Font[fontName] end)
			if ok and enumFont then
				local ok2, f = pcall(function() return Font.fromEnum(enumFont) end)
				if ok2 and f and f.Family then family = f.Family end
			end
		end
		fontBgOverride = family
		pcall(function()
			for _, inst in ipairs(screenGui:GetDescendants()) do
				if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
					-- labels that preview a specific font (the font picker rows) keep
					-- their own typeface so the swap never flattens the list
					local keep = false
					pcall(function() keep = inst:GetAttribute("NemesisKeepFont") == true end)
					if not keep then
						pcall(function()
							local cur = inst.FontFace
							local weight = cur and cur.Weight or Enum.FontWeight.Medium
							local style = cur and cur.Style or Enum.FontStyle.Normal
							inst.FontFace = Font.new(family, weight, style)
						end)
					end
				end
			end
		end)
		return true
	end

	-- background image state + helpers. The image is centre-anchored so it can be
	-- zoomed (Size scaled) and moved (Position offset) and cropped/stretched.
	local bgState = { zoom = 1, offX = 0, offY = 0, fit = Enum.ScaleType.Crop, opacity = 0.5 }
	-- accept a bare id, an rbxassetid/rbxthumb string, or any Roblox URL that carries
	-- the id (e.g. create.roblox.com/store/asset/123.../silly-cat). Most pasted links
	-- point at a Decal, and a plain rbxassetid:// will NOT render a decal on executors,
	-- so we resolve every id through rbxthumb, which renders decals AND images reliably.
	local function parseAsset(s)
		s = tostring(s or ""):gsub("%s+", "")
		if s == "" then return nil end
		if string.match(s, "^rbxthumb://") then return s end   -- already a thumb url
		local id = string.match(s, "/asset/(%d+)") or string.match(s, "/catalog/(%d+)")
			or string.match(s, "[?&]id=(%d+)") or string.match(s, "assetId=(%d+)")
			or string.match(s, "rbxassetid://(%d+)") or string.match(s, "^(%d+)$")
			or string.match(s, "(%d+)")
		if id then return "rbxthumb://type=Asset&id=" .. id .. "&w=420&h=420" end
		if string.match(s, "^http") then return s end   -- last-resort raw url
		return nil
	end
	local function applyBgTransform(animate)
		local info = animate and TI.EXPAND or TweenInfo.new(0)
		local z = bgState.zoom
		bgImage.ScaleType = bgState.fit
		tween(bgImage, {
			Size = UDim2.new(z, 0, z, 0),
			Position = UDim2.new(0.5 + bgState.offX, 0, 0.5 + bgState.offY, 0),
		}, info)
	end

	-- Win.SetBackgroundImage(id / url / rbxassetid / nil, opacity 0..1). Parses a
	-- create.roblox.com link or a bare number, and fades the image in smoothly.
	function Win.SetBackgroundImage(asset, opacity)
		if asset == nil or asset == "" or asset == 0 then
			tween(bgImage, { ImageTransparency = 1 }, TI.FAST)
			task.delay(0.25, function() if bgImage.ImageTransparency >= 0.99 then bgImage.Visible = false; bgImage.Image = "" end end)
			return
		end
		local img = parseAsset(asset)
		if not img then return end
		if opacity ~= nil then bgState.opacity = math.clamp(tonumber(opacity) or 0.5, 0, 1) end
		bgImage.Image = img
		bgImage.ImageTransparency = 1
		bgImage.Visible = true
		applyBgTransform(false)
		tween(bgImage, { ImageTransparency = 1 - bgState.opacity }, TI.EXPAND)
	end
	function Win.SetBackgroundOpacity(opacity)
		bgState.opacity = math.clamp(tonumber(opacity) or 0.5, 0, 1)
		tween(bgImage, { ImageTransparency = 1 - bgState.opacity }, TI.FAST)
	end
	-- Win.SetBackgroundFit("Crop"/"Stretch"/"Fit"/"Tile")
	function Win.SetBackgroundFit(mode)
		local m = mode
		if type(mode) == "string" then local ok, e = pcall(function() return Enum.ScaleType[mode] end); m = ok and e or nil end
		if m then bgState.fit = m; applyBgTransform(true) end
	end
	-- Win.SetBackgroundZoom(0.5..4): zoom the image in/out
	function Win.SetBackgroundZoom(z)
		bgState.zoom = math.clamp(tonumber(z) or 1, 0.5, 4)
		applyBgTransform(true)
	end
	-- Win.SetBackgroundOffset(x, y): move the image, each -1..1 of the window size
	function Win.SetBackgroundOffset(x, y)
		if x ~= nil then bgState.offX = math.clamp(tonumber(x) or 0, -1, 1) end
		if y ~= nil then bgState.offY = math.clamp(tonumber(y) or 0, -1, 1) end
		applyBgTransform(true)
	end

	-- Win.SetColor(themeKey, Color3): override any single palette colour live and
	-- keep it for future elements (used by the Settings colour pickers)
	function Win.SetColor(key, color)
		if type(key) ~= "string" or typeof(color) ~= "Color3" then return false end
		local old = THEME[key]
		if typeof(old) ~= "Color3" then return false end
		local oldHex = hexOf(old)
		THEME[key] = color
		pcall(function()
			for _, inst in ipairs(screenGui:GetDescendants()) do
				for _, prop in ipairs(THEME_COLOR_PROPS) do
					pcall(function()
						if typeof(inst[prop]) == "Color3" and hexOf(inst[prop]) == oldHex then
							inst[prop] = color
						end
					end)
				end
			end
		end)
		return true
	end

	-- Win.SetTransparency(0..0.9): see-through window (Syde "Window transparency")
	function Win.SetTransparency(v)
		v = math.clamp(tonumber(v) or 0, 0, 0.9)
		pcall(function() root.BackgroundTransparency = v end)
		pcall(function() sidebarBG.BackgroundTransparency = v * 0.85 end)
	end

	-- Win.SetAnimations(bool): master switch for all motion (Syde-style toggle)
	function Win.SetAnimations(on)
		reducedMotion = not on
	end

	-- Canvas: Win.SetAutoArrange(bool) reflow panels on resize; Win.SetPanelDrag(bool)
	-- lets the user drag panels by their header to rearrange them
	function Win.SetAutoArrange(on) canvasAutoArrange = on and true or false end
	function Win.SetPanelDrag(on) canvasDrag = on and true or false end

	-- Win.SetRainbow(bool): cycles the accent through the hue wheel (Syde rainbow)
	local rainbowConn
	function Win.SetRainbow(on)
		if rainbowConn then pcall(function() rainbowConn:Disconnect() end); rainbowConn = nil end
		if not on then return end
		pcall(function()
			local h = 0
			rainbowConn = RunService.Heartbeat:Connect(function(dt)
				h = (h + (tonumber(dt) or 0) * 0.12) % 1
				Win.SetAccent(Color3.fromHSV(h, 0.7, 1))
			end)
		end)
	end

	-- Win.SetWatermark(bool, text): a small draggable pill (Syde watermark)
	local watermark
	function Win.SetWatermark(on, text)
		if not on then
			if watermark then watermark.Visible = false end
			return
		end
		if not watermark then
			watermark = Create("TextLabel", {
				Name = "Watermark",
				AnchorPoint = Vector2.new(0, 0),
				Position = UDim2.new(0, 12, 0, 12),
				Size = UDim2.new(0, 160, 0, 26),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = THEME.Topbar,
				Font = FONT_MED,
				Text = "  " .. tostring(text or "NEMESIS") .. "  ",
				TextColor3 = THEME.Text,
				TextSize = 13,
				Parent = screenGui,
			}, { corner(8), accentProp(stroke(accent, 1, 0.4), "Color", accent) })
			makeDraggable(watermark, watermark)
		end
		watermark.Text = "  " .. tostring(text or "NEMESIS") .. "  "
		watermark.Visible = true
	end

	-- Win.SetBlur(bool): a BlurEffect in Lighting so the game behind the menu
	-- frosts (Syde "acrylic"). Removed when off.
	local blurFx
	function Win.SetBlur(on)
		if on then
			if not blurFx then
				pcall(function()
					blurFx = Instance.new("BlurEffect")
					blurFx.Name = "NemesisBlur"
					blurFx.Size = 0
					blurFx.Parent = game:GetService("Lighting")
				end)
			end
			if blurFx then tween(blurFx, { Size = 18 }, TI.EXPAND) end
		elseif blurFx then
			tween(blurFx, { Size = 0 }, TI.EXPAND)
			task.delay(0.4, function() if blurFx and (not on) then pcall(function() blurFx:Destroy() end); blurFx = nil end end)
		end
	end

	-- Win.SetScale(0.6..1.4): scale the whole window (Syde-style UI scale). Applied
	-- on top of the responsive base scale.
	local baseScale = scale
	function Win.SetScale(mult)
		mult = math.clamp(tonumber(mult) or 1, 0.6, 1.4)
		tween(rootScale, { Scale = baseScale * mult }, TI.EXPAND)
		pcall(function() rootShadowHolder:FindFirstChildOfClass("UIScale").Scale = baseScale * mult end)
	end

	-- Win.SetLockToScreen(bool): clamp the window fully inside the viewport while
	-- dragging (Syde LockToScreen). lockToScreen is declared up by the root so the
	-- drag handler can read it.
	function Win.SetLockToScreen(on) lockToScreen = on and true or false end

	-- Win.SetDragSmoothness(0..1): how much the window eases toward the cursor while
	-- dragging. 0 snaps instantly; higher values glide.
	function Win.SetDragSmoothness(v) dragSmooth = math.clamp(tonumber(v) or 0, 0, 1) end

	-- Win.SetGlow(bool): the accent-coloured halo around the whole window (Syde
	-- "Glow"). Fades in/out; recolours automatically with the accent.
	function Win.SetGlow(on)
		if not glowImg then return end
		tween(glowImg, { ImageTransparency = on and 0.15 or 1 }, TI.EXPAND)
	end

	-- Win.SetShadowDensity(0..1): how strong the window drop-shadow reads. 1 is a
	-- dense/opaque shadow, 0 fades it out. Animated on the Syde exponential curve.
	function Win.SetShadowDensity(v)
		if not rootShadowImg then return end
		v = math.clamp(tonumber(v) or 0.65, 0, 1)
		tween(rootShadowImg, { ImageTransparency = 1 - v }, TI.SHADOW)
	end
	-- Win.SetShadowColor(Color3): tint the window drop-shadow (default black)
	function Win.SetShadowColor(c)
		if rootShadowImg and typeof(c) == "Color3" then tween(rootShadowImg, { ImageColor3 = c }, TI.EXPAND) end
	end

	-- Win.SetRotateGradient(bool): slowly spins the accent glow's gradient so the
	-- halo's colour sweeps around the window (most visible with Glow on).
	local gradConn
	function Win.SetRotateGradient(on)
		if gradConn then pcall(function() gradConn:Disconnect() end); gradConn = nil end
		if on and glowGrad then
			local rot = glowGrad.Rotation
			gradConn = RunService.RenderStepped:Connect(function(dt)
				rot = (rot + dt * 60) % 360   -- ~60 deg/sec
				glowGrad.Rotation = rot
			end)
		elseif glowGrad then
			tween(glowGrad, { Rotation = 0 }, TI.EXPAND)
		end
	end

	-- Win.ResetLook(): restore the menu's original default appearance
	local origAccent = opts.accent or Color3.fromRGB(140, 90, 255)
	local origLogo = opts.logoColor or THEME.Text
	function Win.ResetLook()
		Win.SetRainbow(false)
		Win.SetTheme("Dark")
		Win.SetAccent(origAccent)
		Win.SetFont(nil)
		Win.SetTransparency(0)
		Win.SetBackgroundImage(nil)
		Win.SetBackgroundZoom(1)
		Win.SetBackgroundOffset(0, 0)
		Win.SetBackgroundFit("Crop")
		Win.SetLogoColor(origLogo)
		Win.SetWatermark(false)
		Win.SetBlur(false)
		Win.SetScale(1)
		Win.SetLockToScreen(false)
		Win.SetGlow(false)
		Win.SetShadowDensity(0.65)
		Win.SetShadowColor(Color3.fromRGB(0, 0, 0))
		Win.SetRotateGradient(false)
		Win.SetDragSmoothness(0)
		Win.SetHitbox(nil)
	end

	-- small live setters
	function Win.SetTitle(t) if wordmark then wordmark.Text = string.upper(tostring(t or "NEMESIS")) end end
	function Win.SetGame(t) gameLabel.Text = tostring(t or "") end
	function Win.SetStatus(t) statusLabel.Text = tostring(t or "") end

	-- Tab / Group / Page builders
	function Win.Tab(name, icon, ...)
		-- Tolerate method-style calls: Window:Tab("X") passes Window as the first
		-- arg, so shift it off (otherwise the name becomes the table).
		if name == Win then name, icon = icon, ... end
		local tab = { name = tostring(name or "Tab"), pages = {}, activePage = nil }

		tabBarOrder = tabBarOrder + 1
		local btn = Create("TextButton", {
			Size = UDim2.new(0, 0, 0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = tabBarOrder,
			ZIndex = 3,
			Parent = dockButtons,
		}, {
			corner(15),
			Create("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }),
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 7),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local tabIcon
		local iconSpec = resolveIcon(icon)
		if iconSpec then
			tabIcon = Create("ImageLabel", {
				Size = UDim2.new(0, 15, 0, 15),
				BackgroundTransparency = 1,
				ImageColor3 = THEME.SubText,
				LayoutOrder = 1,
				ZIndex = 4,
				Parent = btn,
			})
			applyIcon(tabIcon, iconSpec)
		end
		local label = Create("TextLabel", {
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Font = FONT_MED,
			Text = tostring(name or "Tab"),
			TextColor3 = THEME.SubText,
			TextSize = 13,
			LayoutOrder = 2,
			ZIndex = 4,
			Parent = btn,
		})

		tab.button = btn
		tab.pill = btn
		tab.label = label
		tab.icon = tabIcon
		btn.MouseEnter:Connect(function()
			if activeTab ~= tab then
				tween(label, { TextColor3 = THEME.Text }, TI.HOVER)
				if tabIcon then tween(tabIcon, { ImageColor3 = THEME.Text }, TI.HOVER) end
			end
		end)
		btn.MouseLeave:Connect(function()
			if activeTab ~= tab then
				tween(label, { TextColor3 = THEME.SubText }, TI.HOVEROFF)
				if tabIcon then tween(tabIcon, { ImageColor3 = THEME.SubText }, TI.HOVEROFF) end
			end
		end)
		btn.MouseButton1Click:Connect(function() showTab(tab) end)
		pcall(function()
			btn:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				if activeTab == tab then moveIndicator(false) end
			end)
			btn:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
				if activeTab == tab then moveIndicator(false) end
			end)
		end)
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
				Size = UDim2.new(1, 0, 0, 28),
				BackgroundColor3 = THEME.SidebarActive,
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Text = "",
				Parent = parentFrame or tab.sidebarFrame,
			}, { corner(8) })
			local rowIcon
			local rowIconSpec = resolveIcon(popts.icon)
			local labelX = 12
			if rowIconSpec then
				rowIcon = Create("ImageLabel", {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 10, 0.5, 0),
					Size = UDim2.new(0, 15, 0, 15),
					BackgroundTransparency = 1,
					ImageColor3 = THEME.SubText,
					Parent = row,
				})
				applyIcon(rowIcon, rowIconSpec)
				labelX = 32
			end
			local label = Create("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, labelX, 0, 0),
				Size = UDim2.new(1, -labelX - 10, 1, 0),
				Font = FONT_MED,
				Text = tostring(pname or "Page"),
				TextColor3 = SIDEBAR_PAGE_TEXT,
				TextSize = 13,
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

			-- Responsive masonry: panels are positioned manually so they can smoothly
			-- reflow (switch columns) when the window is resized. The column count
			-- adapts to the width; each panel eases to its new slot on every change.
			local GAP = 10
			local MINCOLW = 300   -- narrower than this and a column is dropped
			local maxCols = math.clamp(math.floor(popts.columns or windowColumns), 1, 3)
			local columnsHolder = Create("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				BackgroundTransparency = 1,
				Parent = pageBody,
			})
			local sections = {}   -- ordered panel cards
			local heights = {}    -- card -> cached local (pre-scale) height
			local relayoutQueued = false
			-- empty state: a friendly ghost shown when the page has no panels yet
			local emptyState = Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 44),
				Size = UDim2.new(1, -40, 0, 88), BackgroundTransparency = 1, Visible = false, Parent = pageBody,
			})
			do
				local gspec = resolveIcon("ghost")
				if gspec then
					local gi = Create("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0, 40, 0, 40), BackgroundTransparency = 1, ImageColor3 = THEME.SubText, ImageTransparency = 0.15, Parent = emptyState })
					applyIcon(gi, gspec)
				end
				Create("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 48), Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Font = FONT_SEMI, Text = "Nothing here yet", TextColor3 = THEME.Text, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, Parent = emptyState })
				Create("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 68), Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Font = FONT, Text = "Add some settings or enable a feature.", TextColor3 = THEME.SubText, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, Parent = emptyState })
			end
			local function refreshEmpty()
				local any = false
				for _, c in ipairs(sections) do if c.Parent then any = true break end end
				emptyState.Visible = not any
			end
			task.defer(refreshEmpty)
			local function uiScale() local s = 1; pcall(function() s = rootScale.Scale end); return (s and s > 0) and s or 1 end
			local function relayout(animate)
				local sc = uiScale()
				local localW = (columnsHolder.AbsoluteSize.X > 0 and columnsHolder.AbsoluteSize.X or 300) / sc
				local cols = math.clamp(math.min(math.max(1, math.floor(localW / MINCOLW)), maxCols), 1, maxCols)
				local colW = (localW - (cols - 1) * GAP) / cols
				local colH = {}
				for i = 1, cols do colH[i] = 0 end
				for _, card in ipairs(sections) do
					if card.Parent then
						local ci = 1
						for i = 2, cols do if colH[i] < colH[ci] then ci = i end end
						card.Size = UDim2.new(0, colW, 0, 0)
						local target = UDim2.fromOffset((ci - 1) * (colW + GAP), colH[ci])
						if animate then tween(card, { Position = target }, TI.SYDE_REFLOW) else card.Position = target end
						colH[ci] = colH[ci] + (heights[card] or (card.AbsoluteSize.Y / sc)) + GAP
					end
				end
				local maxH = 0
				for i = 1, cols do maxH = math.max(maxH, colH[i]) end
				columnsHolder.Size = UDim2.new(1, 0, 0, math.max(maxH - GAP, 0))
			end
			local function queueRelayout(animate)
				if relayoutQueued then return end
				relayoutQueued = true
				task.defer(function() relayoutQueued = false; if columnsHolder.Parent then pcall(relayout, animate) end end)
			end
			-- ===== Canvas: drag a panel by its header to rearrange it =====
			local dragCard, dropSlot, grabOff, lastTi, dragShadow = nil, nil, nil, nil, nil
			local armedCard, armStart, dragConn = nil, nil, nil
			local function indexOf(v) for i, x in ipairs(sections) do if x == v then return i end end end
			local function computeTi()
				-- stable: count REAL cards (not the drop slot) whose centre is above the
				-- dragged card's centre; insert there. independent of the drop slot, so no oscillation.
				if not dragCard then return #sections + 1 end
				local my = dragCard.AbsolutePosition.Y + dragCard.AbsoluteSize.Y / 2
				local above = 0
				for _, card in ipairs(sections) do
					if card ~= dropSlot then
						local cy = card.AbsolutePosition.Y + card.AbsoluteSize.Y / 2
						if cy < my then above = above + 1 end
					end
				end
				return math.clamp(above + 1, 1, #sections + 1)
			end
			local function stepDrag()
				if not dragCard or not columnsHolder.Parent then return end
				local sc = uiScale()
				local m = UserInputService:GetMouseLocation()
				local o = columnsHolder.AbsolutePosition
				dragCard.Position = UDim2.fromOffset((m.X - o.X) / sc - grabOff.X, (m.Y - o.Y) / sc - grabOff.Y)
				if dragShadow then
					local pad = RF_SHADOW.pad
					local cw, ch = dragCard.AbsoluteSize.X / sc, dragCard.AbsoluteSize.Y / sc
					dragShadow.Size = UDim2.fromOffset(cw + pad * 2, ch + pad * 2)
					dragShadow.Position = UDim2.fromOffset(dragCard.Position.X.Offset - pad, dragCard.Position.Y.Offset - pad + 8)
				end
				local ti = computeTi()
				if ti ~= lastTi and dropSlot then
					lastTi = ti
					local si = indexOf(dropSlot); if si then table.remove(sections, si) end
					table.insert(sections, math.clamp(ti, 1, #sections + 1), dropSlot)
					relayout(false)
				end
			end
			local function endDrag()
				if not dragCard then return end
				local card = dragCard
				local ti = #sections + 1
				if dropSlot then local si = indexOf(dropSlot); if si then ti = si; table.remove(sections, si) end; dropSlot:Destroy(); heights[dropSlot] = nil; dropSlot = nil end
				card.ZIndex = 1
				if dragShadow then dragShadow:Destroy(); dragShadow = nil end
				pcall(function() card:SetAttribute("NemDidDrag", true) end)
				task.delay(0.15, function() pcall(function() card:SetAttribute("NemDidDrag", false) end) end)
				tween(card, { Rotation = 0 }, TI.FAST)
				table.insert(sections, math.clamp(ti, 1, #sections + 1), card)
				dragCard, grabOff, lastTi = nil, nil, nil
				if dragConn then dragConn:Disconnect(); dragConn = nil end
				relayout(true)
			end
			local function beginDrag(card)
				if not canvasDrag or dragCard or not card.Parent then return end
				local idx = indexOf(card); if not idx then return end
				dragCard = card
				local sc = uiScale()
				local m = UserInputService:GetMouseLocation()
				grabOff = Vector2.new((m.X - card.AbsolutePosition.X) / sc, (m.Y - card.AbsolutePosition.Y) / sc)
				table.remove(sections, idx)
				dropSlot = Create("Frame", {
					BackgroundColor3 = accent, BackgroundTransparency = 0.86, BorderSizePixel = 0,
					AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(0, 0, 0, 0),
				}, { corner(10), stroke(accent, 1.5, 0.35),
					Create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, card.AbsoluteSize.Y / sc) }),
					Create("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = FONT_SEMI, Text = "Drop here", TextColor3 = accent, TextTransparency = 0.15, TextSize = 13 }),
				})
				dropSlot:SetAttribute("NemDropSlot", true)
				heights[dropSlot] = card.AbsoluteSize.Y / sc
				dropSlot.Parent = columnsHolder
				table.insert(sections, idx, dropSlot)
				lastTi = idx
				card.ZIndex = 60
				dragShadow = Create("ImageLabel", {
					BackgroundTransparency = 1, Image = loadArt(RF_SHADOW.name) or "",
					ImageColor3 = accent, ImageTransparency = 0.5,
					ScaleType = Enum.ScaleType.Slice, SliceCenter = RF_SHADOW.slice,
					ZIndex = 58, Parent = columnsHolder,
				})
				tween(card, { Rotation = 3 }, TI.FAST)
				relayout(true)
				if dragConn then dragConn:Disconnect() end
				dragConn = RunService.RenderStepped:Connect(stepDrag)
			end
			local function wireCard(card)
				-- also arm the drag from the header's own input (a real mouse fires GUI
				-- object events even where the global input is sunk by the GUI)
				local header = card:FindFirstChild("SectionHeader")
				if header then
					header.InputBegan:Connect(function(input)
						if not canvasDrag or dragCard or _ddCurrent or _overlayCurrent then return end
						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
							armedCard = card; armStart = UserInputService:GetMouseLocation()
						end
					end)
				end
			end
			-- arm a drag from a global mouse-down when the cursor is over a panel header
			-- (the screenGui has IgnoreGuiInset = true, so GetMouseLocation shares GUI space)
			UserInputService.InputBegan:Connect(function(input)
				-- don't arm a panel drag while a dropdown / colour picker / overlay is open
				if not canvasDrag or dragCard or not pageBody.Visible or _ddCurrent or _overlayCurrent then return end
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
				local m = UserInputService:GetMouseLocation()
				for _, card in ipairs(sections) do
					local hdr = card:FindFirstChild("SectionHeader")
					if hdr then
						local p, s = hdr.AbsolutePosition, hdr.AbsoluteSize
						if m.X >= p.X and m.X <= p.X + s.X and m.Y >= p.Y and m.Y <= p.Y + s.Y then
							armedCard = card; armStart = m; break
						end
					end
				end
			end)
			UserInputService.InputChanged:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
				if armedCard and not dragCard and (UserInputService:GetMouseLocation() - armStart).Magnitude > 6 then
					local c = armedCard; armedCard = nil; beginDrag(c)
				end
			end)
			UserInputService.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					armedCard = nil
					if dragCard then endDrag() end
				end
			end)

				columnsHolder:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() if canvasAutoArrange then queueRelayout(true) end end)
			columnsHolder.ChildAdded:Connect(function(c)
				if not c:IsA("Frame") then return end
				if c:GetAttribute("NemDropSlot") then return end
				c.AnchorPoint = Vector2.new(0, 0)
				c.AutomaticSize = Enum.AutomaticSize.Y
				sections[#sections + 1] = c
				heights[c] = c.AbsoluteSize.Y / uiScale()
				c:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
					local h = c.AbsoluteSize.Y / uiScale()
					if math.abs((heights[c] or 0) - h) > 0.5 then heights[c] = h; queueRelayout(false) end
				end)
				queueRelayout(false)
				refreshEmpty()
				wireCard(c)
			end)
			columnsHolder.ChildRemoved:Connect(function() task.defer(refreshEmpty) end)
			-- every panel now lands in one shared holder; the masonry places it
			local function pickColumn() return columnsHolder end

			local page = {
				name = tostring(pname or "Page"),
				group = groupName,
				row = row, label = label, icon = rowIcon,
				body = pageBody, columnsHolder = columnsHolder, active = false,
			}
			table.insert(tab.pages, page)

			row.MouseEnter:Connect(function()
				if not page.active then tween(row, { BackgroundColor3 = THEME.SidebarHover, BackgroundTransparency = 0 }, TI.HOVER) end
			end)
			row.MouseLeave:Connect(function()
				if not page.active then tween(row, { BackgroundTransparency = 1 }, TI.HOVEROFF) end
			end)
			row.MouseButton1Click:Connect(function() showPage(tab, page, true) end)

			-- page element API
			local Page = {}
			local defaultHost
			local function ensureDefault()
				if not defaultHost then defaultHost = makeSection(pickColumn({ column = 1 }), accent, nil) end
				return defaultHost
			end
			function Page.Section(t, sopts, ...)
				if t == Page then t, sopts = sopts, ... end -- tolerate Page:Section("X")
				return makeSection(pickColumn(sopts), accent, t)
			end
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
		function Tab.Group(gname, ...)
			if gname == Tab then gname = ... end -- tolerate Tab:Group("X")
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
			-- group header: quiet uppercase micro-label over a hairline underline
			local header = Create("TextButton", {
				Size = UDim2.new(1, 0, 0, 24),
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Text = "",
				Parent = container,
			}, { padXY(12, 0) })
			local headerLabel = Create("TextLabel", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.new(1, -22, 1, 0),
				BackgroundTransparency = 1,
				Font = FONT_SEMI,
				Text = string.upper(tostring(gname or "Group")),
				TextColor3 = THEME.SubText,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = header,
			})
			Create("Frame", {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 0, 1, 0),
				Size = UDim2.new(0, 12, 0, 1),
				BackgroundColor3 = THEME.RowDivider,
				BorderSizePixel = 0,
				Parent = header,
			})
			header.MouseEnter:Connect(function() tween(headerLabel, { TextColor3 = THEME.Text }, TI.HOVER) end)
			header.MouseLeave:Connect(function() tween(headerLabel, { TextColor3 = THEME.SubText }, TI.HOVEROFF) end)
			local chev
			local chevSpec = resolveIcon("chevron-down")
			if chevSpec then
				chev = Create("ImageLabel", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 0, 0.5, 0),
					Size = UDim2.new(0, 12, 0, 12),
					BackgroundTransparency = 1,
					ImageColor3 = THEME.Faint,
					Parent = header,
				})
				applyIcon(chev, chevSpec)
			else
				chev = Create("TextLabel", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 0, 0.5, 0),
					Size = UDim2.new(0, 14, 1, 0),
					BackgroundTransparency = 1,
					Font = FONT_SEMI,
					Text = "\u{25BE}",
					TextColor3 = THEME.Faint,
					TextSize = 13,
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
			function Group.Page(pname, popts, ...)
				if pname == Group then pname, popts = popts, ... end -- tolerate Group:Page("X")
				return makePage(pname, popts, gname, holder)
			end
			return Group
		end

		function Tab.Page(pname, popts, ...)
			if pname == Tab then pname, popts = popts, ... end -- tolerate Tab:Page("X")
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

	-- resize grip (bottom-right)
	-- minimum size keeps the whole top bar (logo, title, tabs, search, buttons)
	-- visible; below this the centred tabs would start to overlap
	local minW = IS_MOBILE and 480 or 820
	local minH = 380
	-- resize handle: a large invisible hit area + the curved corner icon
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
	-- the exact curved corner grip from the original NEMESIS (a Roblox-hosted
	-- asset, so it resolves on any executor), 9-sliced so it stretches cleanly
	local resizeIcon = Create("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.new(0, 22, 0, 22),
		BackgroundTransparency = 1,
		Image = "rbxassetid://86527207319523",
		ImageColor3 = Color3.fromRGB(228, 231, 240),
		ImageTransparency = 0.45,   -- idle: small + faded until hovered
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(51, 52, 51, 52),
		SliceScale = 0.5,
		ZIndex = 8,
		Parent = resizeGrip,
	})
	do
		-- smooth resize: a RenderStepped loop where the visual size
		-- eases toward a cursor-driven target each frame (frame-rate independent
		-- exponential smoothing), so the window butter-glides to follow the cursor.
		local SMOOTH_K = 26          -- higher = tighter cursor-follow
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
		-- grip stretch: normalize the cursor's position inside the grip, then
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
		-- hover: full size + full opacity, stretched toward the cursor
		local function stretchIcon(duration)
			local n = normResize()
			tween(resizeIcon, {
				Size = UDim2.new(0, 30 + n.X * 26, 0, 30 + n.Y * 26),
				ImageTransparency = 0,
				ImageColor3 = Color3.fromRGB(228, 231, 240),
			}, TweenInfo.new(duration or 0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
		end
		-- while dragging to resize: keep stretching toward the cursor, accent tint
		local function pressIcon(duration)
			local n = normResize()
			tween(resizeIcon, {
				Size = UDim2.new(0, 30 + n.X * 30, 0, 30 + n.Y * 30),
				ImageTransparency = 0,
				ImageColor3 = accent,
			}, TweenInfo.new(duration or 0.1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
		end
		-- idle: small and a little faded so it sits quietly until used
		local function resetIcon()
			tween(resizeIcon, {
				Size = UDim2.new(0, 22, 0, 22),
				ImageTransparency = 0.45,
				ImageColor3 = Color3.fromRGB(228, 231, 240),
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
				-- the grip stretches toward the cursor as you drag
				pressIcon()
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

	-- minimize / restore, close, hide-key, mobile reopen
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
		-- explicit branch: the `(a and b) or c` idiom silently breaks when b is
		-- false (a no-arg toggle could never restore a minimized window)
		if force == nil then setMinimized(not minimized) else setMinimized(not force) end
	end
	minBtn.MouseButton1Click:Connect(function() setMinimized(not minimized) end)

	function Win.Destroy()
		if fpsConn then pcall(function() fpsConn:Disconnect() end); fpsConn = nil end
		if sessConn then pcall(function() sessConn:Disconnect() end); sessConn = nil end
		-- these start their own RunService loops; tear them down or they run forever
		pcall(Win.SetRainbow, false)
		pcall(Win.SetRotateGradient, false)
		closeOpenDropdown()
		tween(root, { Size = UDim2.new(0, W, 0, 0) }, TI.SLIDE)
		task.delay(0.25, function() if root then root:Destroy() end end)
	end
	Win.Unload = Win.Destroy
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
	-- the "Toggle menu" keybind in Settings owns hide/show; this listener only keeps
	-- the Ctrl+K search and Escape shortcuts (no toggle branch, or it double-fires)
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == Enum.KeyCode.K then
			local ok, down = pcall(function()
				return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
					or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
			end)
			if ok and down then openSearch() end
		elseif input.KeyCode == Enum.KeyCode.Escape then
			closeSearch()
		end
	end)

	if IS_MOBILE then
		local fab = Create("TextButton", {
			Name = "Reopen",
			Position = UDim2.new(0, 12, 0, 12),
			Size = UDim2.new(0, 44, 0, 44),
			BackgroundColor3 = THEME.Topbar,
			Font = FONT_BOLD,
			Text = "N",
			TextColor3 = accent,
			TextSize = 19,
			Parent = screenGui,
		}, { corner(8), stroke(THEME.Stroke, 1, 0.15) })
		dropShadow(fab, 0.45)
		accentProp(fab, "TextColor3", accent)
		makeDraggable(fab, fab)
		fab.MouseButton1Click:Connect(function() setHidden(not hidden) end)
	end

	-- recolor the logo at runtime (any hue): Win.SetLogoColor(Color3.fromRGB(...))
	function Win.SetLogoColor(c)
		logoColor = c or logoColor
		if logoGrad then logoGrad.Enabled = false end
		if logoImage then logoImage.ImageColor3 = logoColor end
	end
	-- recolor the logo with a gradient: Win.SetLogoGradient(c1, c2)
	function Win.SetLogoGradient(c1, c2)
		if not (logoImage and logoGrad and c1 and c2) then return end
		logoGrad.Color = ColorSequence.new(c1, c2)
		logoGrad.Enabled = true
		logoImage.ImageColor3 = Color3.new(1, 1, 1)
	end

	-- live-recolor the whole menu's accent (Win.SetAccent(Color3))
	function Win.SetAccent(c)
		if not c then return end
		-- c may be a Color3 or a ColorSequence (Multi gradient). keep a flat colour for
		-- everything that needs one, but hand the hooks the original so gradients apply.
		local flat = seqPrimary(c)
		accent = flat
		THEME.Accent = flat
		for _, fn in ipairs(accentHooks) do pcall(fn, c) end
		-- the fill/highlight colour follows accent until the user overrides it
		if not hitboxOverride then fireHitbox(c) end
		-- re-apply the dynamic accent text (active sub-tab + breadcrumb)
		if activeTab and activeTab.activePage then
			pcall(function() applyPageVisual(activeTab, activeTab.activePage, false) end)
			pcall(function() setCrumb(activeTab, activeTab.activePage) end)
		end
	end

	-- Win.SetHitbox(Color3 or nil): the fill/highlight colour of toggles and slider
	-- fills, independent of the accent. Pass nil to fall back to tracking the accent.
	function Win.SetHitbox(c)
		if typeof(c) == "Color3" or typeof(c) == "ColorSequence" then
			hitboxOverride = true
			fireHitbox(c)
		else
			hitboxOverride = false
			fireHitbox(accent)
		end
	end

	-- A floating overlay panel (settings / AI): a centred card with a header and
	-- a scrolling body that hosts normal sections. Opens/closes with a Syde-style
	-- scale + fade. Returns { body (a section host factory), open, close, toggle }.
	local function makeOverlayPanel(titleText, headerIcon)
		local backdrop = Create("TextButton", {
			Name = "OverlayBackdrop", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 1, AutoButtonColor = false, Text = "", Visible = false, ZIndex = 40000, Parent = screenGui,
		})
		local pScale = Create("UIScale", { Scale = 1 })
		local card = Create("CanvasGroup", {
			Name = "OverlayPanel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0, 400, 0, 468), BackgroundColor3 = THEME.Group,
			GroupTransparency = 1, Visible = false, ZIndex = 40001, Parent = screenGui,
		}, { corner(14), stroke(THEME.Stroke, 1, 0.3), pScale })
		siblingShadow(card)
		-- absorb clicks on the panel's empty areas so they don't fall through to the
		-- backdrop and close it (only the backdrop outside the card, or the X, closes
		-- it). It sits under the header/body/controls (they get their clicks first) and
		-- doubles as the drag handle so the panel can still be moved by empty space.
		local absorb = Create("TextButton", {
			Name = "Absorb", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
			AutoButtonColor = false, Text = "", ZIndex = 1, Parent = card,
		})
		makeDraggable(card, absorb)

		local header = Create("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, ZIndex = 40002, Parent = card }, { padXY(16, 0) })
		local hx = 0
		local hspec = resolveIcon(headerIcon)
		if hspec then
			local img = Create("ImageLabel", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(0, 18, 0, 18), BackgroundTransparency = 1, ImageColor3 = accent, Parent = header })
			applyIcon(img, hspec); accentProp(img, "ImageColor3", accent); hx = 26
		end
		Create("TextLabel", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, hx, 0.5, 0), Size = UDim2.new(1, -hx - 30, 1, 0),
			BackgroundTransparency = 1, Font = FONT_SEMI, Text = titleText, TextColor3 = THEME.Text, TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left, Parent = header })
		local closeX = Create("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 24, 0, 24),
			BackgroundTransparency = 1, AutoButtonColor = false, Text = "", Parent = header })
		local closeIcon = iconX(closeX, 13, THEME.SubText)
		Create("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 0, 44), Size = UDim2.new(1, -24, 0, 1),
			BackgroundColor3 = THEME.Stroke, BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 40002, Parent = card })

		local body = Create("ScrollingFrame", {
			Position = UDim2.new(0, 0, 0, 46), Size = UDim2.new(1, 0, 1, -46), BackgroundTransparency = 1, BorderSizePixel = 0,
			ScrollBarThickness = 3, ScrollBarImageColor3 = THEME.Faint, ScrollBarImageTransparency = 0.4,
			CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 40002, Parent = card,
		}, {
			Create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
			Create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 14) }),
		})

		local ov = { opened = false }
		function ov.close()
			if not ov.opened then return end
			ov.opened = false
			if _overlayCurrent == ov then _overlayCurrent = nil end
			tween(card, { GroupTransparency = 1 }, TI.FAST)
			tween(pScale, { Scale = 0.94 }, TI.FAST)
			task.delay(0.18, function() if not ov.opened then card.Visible = false; backdrop.Visible = false end end)
		end
		function ov.open()
			if ov.opened then return end
			-- close any other top-level overlay (settings/AI) but NOT the inner
			-- dropdown/picker layer, so controls inside this panel still work
			if _overlayCurrent and _overlayCurrent ~= ov then _overlayCurrent.close() end
			closeOpenDropdown()
			_overlayCurrent = ov
			ov.opened = true
			card.Position = UDim2.new(0.5, 0, 0.5, 10)
			card.GroupTransparency = 1
			pScale.Scale = 0.92
			backdrop.BackgroundTransparency = 1
			backdrop.Visible = true
			card.Visible = true
			-- Syde open: grow+fade
			tween(card, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 0.5, 0) }, TI.EXPAND)
			tween(pScale, { Scale = 1 }, TI.EXPAND)
			backdrop.BackgroundTransparency = 1  -- never dull the screen; just click-to-close
		end
		function ov.toggle() if ov.opened then ov.close() else ov.open() end end
		backdrop.MouseButton1Click:Connect(ov.close)
		closeX.MouseButton1Click:Connect(ov.close)
		closeX.MouseEnter:Connect(function() recolorIcon(closeIcon, DANGER, TI.HOVER) end)
		closeX.MouseLeave:Connect(function() recolorIcon(closeIcon, THEME.SubText, TI.HOVEROFF) end)

		-- section factory over the scrolling body (reuses makeSection)
		function ov.Section(title) return makeSection(body, accent, title) end
		ov.card = card       -- for custom layouts (AI chat)
		ov.body = body
		ov.setSize = function(w, h)
			card.AutomaticSize = Enum.AutomaticSize.None
			card.Size = UDim2.new(0, w, 0, h)
		end
		return ov
	end

	-- Built-in Settings panel (gear icon). Reuses the element API so every control
	-- is a normal, saveable one. Skip with Window({ settings = false }).
	local function buildSettings()
		local S = makeOverlayPanel("Settings", "settings")
		openSettingsPanel = S.open

		-- colorpickers fire their callback once at construction to seed their value;
		-- ignore that startup call for the Icon picker so it does not lock the hitbox
		-- override on at boot (which would stop the accent from ever reaching the fills)
		local settingsReady = false
		task.defer(function() settingsReady = true end)

		local themeSec = S.Section("THEME")
		themeSec.Dropdown({ text = "Menu theme", icon = "sun-moon",
			options = { "Dark", "Midnight", "Abyss" }, default = "Dark",
			callback = function(v) Win.SetTheme(v) end })
		themeSec.ColorPicker({ text = "Accent color", icon = "droplet", default = accent,
			-- pass the full value: a Color3 in Single, a ColorSequence in Multi (so the
			-- accent fills across the menu become a real gradient)
			callback = function(v) Win.SetAccent(v) end })
		themeSec.ColorPicker({ text = "Icon color", icon = "square-check", default = accent,
			callback = function(v) if settingsReady then Win.SetHitbox(v) end end })
		local fontOptions = { "Inter" }
		pcall(function()
			for _, f in ipairs(Enum.Font:GetEnumItems()) do
				if f.Name ~= "Unknown" and f.Name ~= "Inter" then fontOptions[#fontOptions + 1] = f.Name end
			end
			table.sort(fontOptions)
		end)
		themeSec.Dropdown({ text = "Font", icon = "type", options = fontOptions, default = "Inter",
			optionFont = true,   -- show each font name rendered in its own typeface
			callback = function(v) Win.SetFont(v) end })
		themeSec.Toggle({ text = "Rainbow accent", icon = "sparkles", default = false, desc = "Cycle the accent through every hue.",
			callback = function(on) Win.SetRainbow(on) end })

		local layoutSec = S.Section("LAYOUT")
		layoutSec.Label("Rearrange your panels: turn on dragging, then grab a panel by its title.")
		layoutSec.Toggle({ text = "Auto arrange", icon = "layout-grid", default = true,
			desc = "Reflow panels to fit when the window is resized.",
			callback = function(on) Win.SetAutoArrange(on) end })
		layoutSec.Toggle({ text = "Rearrange panels", icon = "move", default = false,
			desc = "Drag a panel by its title to move it around.",
			callback = function(on) Win.SetPanelDrag(on) end })

		local feelSec = S.Section("FEEL")
		feelSec.Slider({ text = "Window transparency", icon = "square", min = 0, max = 90, default = 0, suffix = "%",
			callback = function(v) Win.SetTransparency(v / 100) end })
		feelSec.Toggle({ text = "Animations", icon = "zap", default = true, desc = "Turn off for instant, motion-free UI.",
			callback = function(on) Win.SetAnimations(on) end })
		feelSec.Toggle({ text = "Watermark", icon = "tag", default = false, desc = "A small draggable badge on screen.",
			callback = function(on) Win.SetWatermark(on, opts.title or "NEMESIS") end })
		feelSec.Slider({ text = "UI scale", icon = "maximize", min = 60, max = 140, default = 100, suffix = "%",
			desc = "Shrink or grow the whole menu.",
			callback = function(v) Win.SetScale(v / 100) end })
		feelSec.Toggle({ text = "Window glow", icon = "sparkles", default = false,
			desc = "Cast an accent-coloured halo around the menu.",
			callback = function(on) Win.SetGlow(on) end })
		feelSec.Toggle({ text = "Background blur", icon = "droplet", default = false,
			desc = "Frost the game behind the menu.",
			callback = function(on) Win.SetBlur(on) end })
		feelSec.Toggle({ text = "Lock to screen", icon = "move", default = false,
			desc = "Keep the window fully on screen when dragging.",
			callback = function(on) Win.SetLockToScreen(on) end })
		feelSec.Toggle({ text = "Rotate gradient", icon = "refresh-cw", default = false,
			desc = "Slowly spin the accent gradient (best with glow on).",
			callback = function(on) Win.SetRotateGradient(on) end })
		feelSec.Slider({ text = "Drag smoothness", icon = "move", min = 0, max = 100, default = 0, suffix = "%",
			desc = "How much the window glides toward the cursor when dragged.",
			callback = function(v) Win.SetDragSmoothness(v / 100) end })
		feelSec.Slider({ text = "Shadow density", icon = "layers", min = 0, max = 100, default = 65, suffix = "%",
			desc = "How strong the window drop-shadow reads.",
			callback = function(v) Win.SetShadowDensity(v / 100) end })

		local colorSec = S.Section("MENU COLORS")
		colorSec.Label("Recolor the menu surfaces. Each picker has Single / Double / Multi.")
		colorSec.ColorPicker({ text = "Background", icon = "square", default = THEME.Background,
			callback = function(_, _, c) Win.SetColor("Background", c) end })
		colorSec.ColorPicker({ text = "Elements", icon = "box", default = THEME.Element,
			callback = function(_, _, c) Win.SetColor("Element", c) end })
		colorSec.ColorPicker({ text = "Text", icon = "type", default = THEME.Text,
			callback = function(_, _, c) Win.SetColor("Text", c) end })
		colorSec.ColorPicker({ text = "Icons / subtext", icon = "image", default = THEME.SubText,
			callback = function(_, _, c) Win.SetColor("SubText", c) end })
		colorSec.ColorPicker({ text = "Shadow", icon = "layers", default = Color3.fromRGB(0, 0, 0),
			callback = function(_, _, c) Win.SetShadowColor(c) end })

		local logoSec = S.Section("LOGO")
		logoSec.ColorPicker({ text = "Logo color", icon = "pen-tool", default = logoColor,
			callback = function(_, _, c) Win.SetLogoColor(c) end })
		local logoIdInput = logoSec.Input({ text = "Logo image id", icon = "image", placeholder = "rbxassetid or number" })
		logoSec.Button({ text = "Apply logo image", button = "Apply", icon = "check", callback = function()
			local id = tostring(logoIdInput.Get() or ""):gsub("%s+", "")
			if id ~= "" and logoImage then
				local img = string.match(id, "^%d+$") and ("rbxassetid://" .. id) or id
				pcall(function() logoImage.Image = img end)
				NEMESIS.Notify({ title = "Logo", content = "Applied.", duration = 2, icon = "check" })
			end
		end })

		local bgSec = S.Section("BACKGROUND IMAGE")
		bgSec.Label("Paste an asset id or a Roblox link (e.g. create.roblox.com/store/asset/11176073582/silly-cat), apply it, then fit / zoom / move it to taste.")
		local bgInput = bgSec.Input({ text = "Image id or link", icon = "image", placeholder = "id or create.roblox.com/store/asset/..." })
		local bgOpacity = 0.55
		bgSec.Button({ text = "Apply background", button = "Apply", icon = "check", callback = function()
			local id = tostring(bgInput.Get() or ""):gsub("%s+", "")
			if id ~= "" then
				Win.SetBackgroundImage(id, bgOpacity)
				NEMESIS.Notify({ title = "Background", content = "Applied.", duration = 2, icon = "image" })
			end
		end })
		bgSec.Dropdown({ text = "Fit", icon = "maximize", options = { "Crop", "Stretch", "Fit", "Tile" }, default = "Crop",
			desc = "Crop fills and keeps aspect; Stretch fills exactly; Fit shows the whole image.",
			callback = function(v) Win.SetBackgroundFit(v) end })
		bgSec.Slider({ text = "Zoom", icon = "search", min = 50, max = 300, default = 100, suffix = "%",
			callback = function(v) Win.SetBackgroundZoom(v / 100) end })
		local bgX, bgY = 0, 0
		bgSec.Slider({ text = "Move X", icon = "move-horizontal", min = -100, max = 100, default = 0, suffix = "%",
			callback = function(v) bgX = v / 100; Win.SetBackgroundOffset(bgX, bgY) end })
		bgSec.Slider({ text = "Move Y", icon = "move-vertical", min = -100, max = 100, default = 0, suffix = "%",
			callback = function(v) bgY = v / 100; Win.SetBackgroundOffset(bgX, bgY) end })
		bgSec.Slider({ text = "Opacity", icon = "eye", min = 0, max = 100, default = 55, suffix = "%", flag = "nem_bg_opacity",
			callback = function(v) bgOpacity = v / 100; Win.SetBackgroundOpacity(bgOpacity) end })
		bgSec.Button({ text = "Clear background", button = "Clear", icon = "x", callback = function()
			Win.SetBackgroundImage(nil)
		end })

		local kSec = S.Section("CONTROLS")
		kSec.Keybind({ text = "Toggle menu", icon = "eye", default = toggleKey, desc = "Key that hides / shows the menu.",
			callback = function() setHidden(not hidden) end })
		local sessSec = S.Section("SESSION")
		sessSec.Label("Game  " .. tostring(game.PlaceId))
		local fpsRow = sessSec.Label("FPS  ...")
		local upRow = sessSec.Label("Uptime  0s")
		pcall(function()
			local frames, acc, uptime = 0, 0, 0
			sessConn = RunService.Heartbeat:Connect(function(dt)
				dt = tonumber(dt) or 0
				frames = frames + 1; acc = acc + dt; uptime = uptime + dt
				if acc >= 1 then
					fpsRow.Set("FPS  " .. tostring(math.floor(frames / acc + 0.5)))
					local secs = math.floor(uptime)
					upRow.Set("Uptime  " .. (secs >= 60 and (math.floor(secs / 60) .. "m " .. (secs % 60) .. "s") or (secs .. "s")))
					frames, acc = 0, 0
				end
			end)
		end)

		local resetSec = S.Section("RESET")
		resetSec.Label("Put the menu back to its default look (theme, accent, font, colours, transparency, background).")
		resetSec.Button({ text = "Reset to default", button = "Reset", icon = "rotate-ccw", callback = function()
			if Win.ResetLook then Win.ResetLook() end
			NEMESIS.Notify({ title = "Reset", content = "Menu restored to default.", duration = 2, icon = "rotate-ccw" })
		end })

		local aboutSec = S.Section("ABOUT")
		aboutSec.Paragraph({ title = "NEMESIS " .. NEMESIS.Version, content = "UI library for Roblox executors." })
		aboutSec.Button({ text = "Unload menu", button = "Unload", icon = "trash-2", callback = function() Win.Destroy() end })
	end

	-- AI assistant panel (bot icon). Free built-in AI; optional keys for smarter.
	-- AI Assistant: a real chat (Gen3 style) with a scrolling conversation, an
	-- input row, and a Google Gemini key. Uses the executor's own HTTP (syn.request
	-- / request) for keyed calls and falls back to the free pollinations AI when no
	-- key is set. Errors surface as an assistant bubble, never a popup.
	local function buildAI()
		local A = makeOverlayPanel("AI Assistant", "bot")
		openAIPanel = A.open
		A.setSize(400, 500)
		A.body.Visible = false   -- the AI panel uses a custom chat layout, not sections
		local card = A.card

		local httpReq = (syn and syn.request) or (type(request) == "function" and request) or (http and http.request) or (http_request)
		local HttpService = game:GetService("HttpService")
		local geminiKey = tostring(NEMESIS.AIKey or "")
		local geminiModel = "gemini-2.0-flash"
		local history = {}   -- Gemini format: { role="user"/"model", parts={{text=...}} }
		local busy = false

		-- top strip: a compact key field + model, above the messages
		local keyBox = Create("TextBox", {
			Position = UDim2.new(0, 12, 0, 52), Size = UDim2.new(1, -24, 0, 30),
			BackgroundColor3 = THEME.Element, ClearTextOnFocus = false,
			Font = FONT_MONO, PlaceholderText = "Paste your Google Gemini API key (optional)",
			PlaceholderColor3 = THEME.Faint, Text = geminiKey, TextColor3 = THEME.Text, TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left, ClipsDescendants = true, ZIndex = 40002, Parent = card,
		}, { corner(6), stroke(THEME.ElementStroke, 1, 0.4), padXY(10, 0) })
		keyBox.FocusLost:Connect(function()
			geminiKey = tostring(keyBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
			NEMESIS.AIKey = geminiKey
		end)

		-- messages (scrolling conversation)
		local messages = Create("ScrollingFrame", {
			Position = UDim2.new(0, 0, 0, 90), Size = UDim2.new(1, 0, 1, -142), BackgroundTransparency = 1, BorderSizePixel = 0,
			ScrollBarThickness = 3, ScrollBarImageColor3 = THEME.Faint, ScrollBarImageTransparency = 0.4,
			CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 40002, Parent = card,
		}, {
			Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }),
			Create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }),
		})
		local msgOrder = 0
		local function addBubble(who, text)
			msgOrder = msgOrder + 1
			local isUser = (who == "user")
			local wrap = Create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = msgOrder, ZIndex = 40002, Parent = messages })
			local bubble = Create("TextLabel", {
				AnchorPoint = Vector2.new(isUser and 1 or 0, 0),
				Position = UDim2.new(isUser and 1 or 0, 0, 0, 0),
				Size = UDim2.new(0, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundColor3 = isUser and accent or THEME.Element,
				Font = FONT, Text = tostring(text), TextColor3 = isUser and accentTextColor(accent) or THEME.Text,
				TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 40003, Parent = wrap,
			}, { corner(9), Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7) }), Create("UISizeConstraint", { MaxSize = Vector2.new(300, math.huge) }) })
			if isUser then accentProp(bubble, "BackgroundColor3", accent) end
			task.defer(function() pcall(function() messages.CanvasPosition = Vector2.new(0, messages.AbsoluteCanvasSize.Y) end) end)
			return bubble
		end
		addBubble("model", "Hi! I'm your assistant. Ask me anything. Add a Gemini key above for smarter replies, or leave it blank to use the free AI.")

		-- input row (textbox + send)
		local inputRow = Create("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -24, 0, 38), BackgroundTransparency = 1, ZIndex = 40002, Parent = card })
		local inField = Create("Frame", { Size = UDim2.new(1, -46, 1, 0), BackgroundColor3 = THEME.Element, ZIndex = 40002, Parent = inputRow }, { corner(9), stroke(THEME.ElementStroke, 1, 0.4) })
		local inBox = Create("TextBox", {
			Size = UDim2.new(1, -20, 1, 0), Position = UDim2.new(0, 12, 0, 0), BackgroundTransparency = 1, ClearTextOnFocus = false,
			Font = FONT, PlaceholderText = "Message...", PlaceholderColor3 = THEME.Faint, Text = "",
			TextColor3 = THEME.Text, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 40003, Parent = inField,
		})
		local sendBtn = Create("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 38, 0, 38), BackgroundColor3 = accent, AutoButtonColor = false, Text = "", ZIndex = 40002, Parent = inputRow }, { corner(9) })
		accentProp(sendBtn, "BackgroundColor3", accent)
		local sendIcon = Create("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 16, 0, 16), BackgroundTransparency = 1, ImageColor3 = accentTextColor(accent), ZIndex = 40003, Parent = sendBtn })
		applyIcon(sendIcon, resolveIcon("send"))

		-- the request: Gemini when a key is set, free pollinations otherwise
		local function askGemini(prompt)
			if not httpReq then return nil, "This executor has no HTTP request function." end
			local sys = "You are a concise, friendly assistant inside a Roblox script menu. Keep answers brief and helpful. Do not use markdown ** or *."
			local msgs = {}
			for _, m in ipairs(history) do msgs[#msgs + 1] = m end
			msgs[#msgs + 1] = { role = "user", parts = { { text = prompt } } }
			local body = HttpService:JSONEncode({ contents = msgs, systemInstruction = { parts = { { text = sys } } } })
			local url = "https://generativelanguage.googleapis.com/v1beta/models/" .. geminiModel .. ":generateContent?key=" .. geminiKey
			local ok, res = pcall(httpReq, { Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
			if not ok or not res then return nil, "Request failed. Check your connection." end
			if res.StatusCode == 429 then return nil, "Rate limited (429). Wait a moment and try again." end
			local dok, decoded = pcall(function() return HttpService:JSONDecode(res.Body) end)
			if dok and decoded and decoded.candidates and decoded.candidates[1] then
				-- a safety/recitation-blocked candidate has no .content, so this must
				-- be nil-safe or the whole send thread dies and the chat freezes
				local cand = decoded.candidates[1]
				local txt = cand.content and cand.content.parts and cand.content.parts[1] and cand.content.parts[1].text
				if not txt then
					return nil, (cand.finishReason == "SAFETY" and "That reply was blocked by Gemini's safety filter." or "The AI sent an empty reply. Try rephrasing.")
				end
				history[#history + 1] = { role = "user", parts = { { text = prompt } } }
				history[#history + 1] = { role = "model", parts = { { text = txt } } }
				if #history > 20 then table.remove(history, 1); table.remove(history, 1) end
				return (txt:gsub("^%s+", ""):gsub("%s+$", ""))
			elseif dok and decoded and decoded.error then
				return nil, "Gemini: " .. tostring(decoded.error.message)
			end
			return nil, "Could not read the AI's reply."
		end
		local function askFree(prompt)
			local reply
			local ok = pcall(function()
				local convo = {}
				for _, m in ipairs(history) do convo[#convo + 1] = (m.role == "user" and "User: " or "AI: ") .. m.parts[1].text end
				convo[#convo + 1] = "User: " .. prompt
				local url = "https://text.pollinations.ai/" .. HttpService:UrlEncode("You are a concise Roblox menu assistant. " .. table.concat(convo, "\n") .. "\nAI:") .. "?referrer=nemesis"
				reply = game:HttpGet(url)
			end)
			if ok and reply and #reply > 0 then
				history[#history + 1] = { role = "user", parts = { { text = prompt } } }
				history[#history + 1] = { role = "model", parts = { { text = reply } } }
				if #history > 20 then table.remove(history, 1); table.remove(history, 1) end
				return (reply:gsub("^%s+", ""):gsub("%s+$", ""))
			end
			return nil, "The free AI is busy. Try again, or add a Gemini key for reliable replies."
		end

		local function send()
			local q = tostring(inBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
			if q == "" or busy then return end
			inBox.Text = ""
			addBubble("user", q)
			busy = true
			local thinking = addBubble("model", "...")
			task.spawn(function()
				local reply, err
				-- never let a thrown request leave busy=true (that would wedge the chat
				-- so no further message could ever send)
				local ok = pcall(function()
					if geminiKey ~= "" then reply, err = askGemini(q) else reply, err = askFree(q) end
				end)
				if not ok then err = "Something went wrong. Try again." end
				busy = false
				if thinking then thinking.Text = reply or err or "Something went wrong." end
			end)
		end
		sendBtn.MouseButton1Click:Connect(send)
		inBox.FocusLost:Connect(function(enter) if enter then send() end end)
	end

	if opts.settings ~= false then
		pcall(buildSettings)
		pcall(buildAI)
	end

	Win.Instance = root
	Win.Notify = NEMESIS.Notify
	return Win
end

return NEMESIS
