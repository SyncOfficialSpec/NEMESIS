--[[
	Smoke test for PERDITION. Run from the repo root:
		lua  test/smoke.lua
		luau test/smoke.lua   (luau may lack dofile; lua is preferred)

	Loads source.lua under the Roblox stub and asserts the full v2 API surface
	(Window -> Tab -> Group -> Page -> Section -> controls) can be constructed
	and that controls' .Set/.Get behave.
]]

dofile("test/stub.lua")

local PERDITION = dofile("source.lua")

local function check(cond, msg)
	if not cond then
		error("FAIL: " .. msg, 2)
	end
	print("  ok: " .. msg)
end

print("PERDITION smoke test")
check(type(PERDITION) == "table", "module returns a table")
check(type(PERDITION.Window) == "function", "PERDITION.Window exists")
check(type(PERDITION.Notify) == "function", "PERDITION.Notify exists")
check(type(PERDITION.Flags) == "table", "PERDITION.Flags table exists")

local Win = PERDITION.Window({
	title = "PERDITION",
	accent = Color3.fromRGB(140, 90, 255),
	game = "CS2",
	status = "Connected",
	configs = { "HvH", "Legit", "Rage" },
	toggleKey = Enum.KeyCode.RightShift,
})
check(type(Win) == "table", "Window returns a table")
check(type(Win.Tab) == "function", "Win.Tab exists")
check(type(Win.Toggle) == "function", "Win.Toggle (minimize) exists")
check(type(Win.Destroy) == "function", "Win.Destroy exists")

-- top tabs (with pill icons)
local Combat = Win.Tab("Combat", "crosshair")
local Visuals = Win.Tab("Visuals", "eye")
check(type(Combat) == "table" and type(Combat.Group) == "function", "Tab.Group exists")
check(type(Combat.Page) == "function", "Tab.Page exists")

-- sidebar group + grouped pages (icons: name degrades to text under stub, asset id resolves)
local Aimbot = Combat.Group("AIMBOT")
check(type(Aimbot.Page) == "function", "Group.Page exists")
local General = Aimbot.Page("General", { icon = "crosshair", dot = true })
local Targeting = Aimbot.Page("Targeting", { icon = 4483362458 })
check(type(General) == "table" and type(General.Section) == "function", "Page.Section exists")

-- standalone page (no group header)
local Misc = Combat.Page("Misc", { icon = "sliders-horizontal" })
check(type(Misc.Toggle) == "function", "standalone Page exposes element creators")

-- collapsible section + every control
local gen = General.Section("GENERAL")
check(type(gen) == "table" and type(gen.Toggle) == "function", "Section exposes element creators")

local btn = gen.Button({ text = "Execute", button = "Run", callback = function() end })
check(type(btn) == "table", "Button created")

local tog = gen.Toggle({ text = "Enable", default = true, flag = "aim_enable", callback = function() end })
check(tog.Get() == true, "Toggle default true")
tog.Set(false)
check(tog.Get() == false, "Toggle Set(false)")
check(PERDITION.Flags.aim_enable == false, "Toggle flag synced to Flags")

local sld = gen.Slider({ text = "Point Scale", min = 0, max = 1, default = 0.65, increment = 0.01, flag = "scale" })
check(sld.Get() == 0.65, "Slider default 0.65")
sld.Set(0.5)
check(math.abs(sld.Get() - 0.5) < 1e-6, "Slider Set(0.5)")
check(PERDITION.Flags.scale ~= nil, "Slider flag synced")

local dd = gen.Dropdown({ text = "Weapon Group", options = { "Rifles", "Pistols", "Snipers" }, default = "Rifles", flag = "wg" })
check(dd.Get() == "Rifles", "Dropdown default")
dd.Set("Pistols")
check(dd.Get() == "Pistols", "Dropdown Set")
dd.SetOptions({ "X", "Y", "Z" })
check(type(dd.Get) == "function", "Dropdown SetOptions ok")

local mdd = gen.Dropdown({ text = "Targets", options = { "x", "y", "z" }, multi = true, default = { "x" }, flag = "tg" })
local got = mdd.Get()
check(type(got) == "table" and got[1] == "x", "Multi dropdown default")

local inp = gen.Input({ text = "Webhook", default = "hello", placeholder = "type", flag = "wh" })
check(inp.Get() == "hello", "Input default")
inp.Set("world")
check(inp.Get() == "world", "Input Set")

-- keybind: keyboard KeyCode and mouse-button string
local kb = gen.Keybind({ text = "Keybind", default = "MOUSE5", mode = "Hold", flag = "kb", callback = function() end })
check(type(kb.Get) == "function", "Keybind (mouse string) created")
kb.Set(Enum.KeyCode.E)
check(type(kb.Get()) ~= "nil", "Keybind Set to KeyCode")

local cp = gen.ColorPicker({ text = "ESP Color", default = Color3.fromRGB(255, 0, 0), transparency = 0.2, flag = "col", callback = function() end })
cp.Set(Color3.fromRGB(0, 255, 0), 0.5)
check(type(cp.Get()) == "table", "ColorPicker Set/Get")
check(type(cp.GetAlpha) == "function" and cp.GetAlpha() == 0.5, "ColorPicker alpha Set/GetAlpha")

local lbl = gen.Label("a label")
lbl.Set("updated")
check(lbl.Get() == "updated", "Label Set/Get")

local para = gen.Paragraph({ title = "Notes", content = "some body text" })
check(type(para) == "table", "Paragraph created")

-- new parity elements: construct each and exercise its methods
gen.Spacer({ height = 8 })
local prog = gen.ProgressBar({ text = "Load", value = 40, max = 100, suffix = "%" })
check(prog.Get() == 40, "ProgressBar Get"); prog.Set(75); check(prog.Get() == 75, "ProgressBar Set")
local stat = gen.Stat({ text = "Kills", value = 12 }); stat.Set(99); check(stat.Get() == "99", "Stat Set/Get")
local cbx = gen.Checkbox({ text = "Box", default = false, flag = "cbx" }); cbx.Set(true)
check(cbx.Get() == true and PERDITION.Flags.cbx == true, "Checkbox Set + flag")
local cpy = gen.CopyButton({ text = "Copy id", copy = "abc" }); check(type(cpy) == "table", "CopyButton created")
check(type(gen.BarChart({ text = "Bars", points = { 3, 7, 2, 9 } }).Push) == "function", "BarChart created")
check(type(gen.Chart({ text = "Line", points = { 1, 4, 2, 6, 3 } }).Push) == "function", "Chart created")
check(type(gen.StackedChart({ text = "Stack", series = { "A", "B" }, rows = { { Name = "R1", Values = { 3, 2 } } } }).Set) == "function", "StackedChart created")
check(type(gen.RippleButton({ text = "Ripple", callback = function() end }).Fire) == "function", "RippleButton created")
check(type(gen.HoldButton({ text = "Hold", duration = 1, callback = function() end })) == "table", "HoldButton created")
check(type(gen.ShimmerLabel({ text = "Shine" }).Set) == "function", "ShimmerLabel created")
check(type(gen.ScrollHint({ text = "More" }).Set) == "function", "ScrollHint created")
check(type(gen.CursorTag({ text = "Tag", hint = "hover" }).Set) == "function", "CursorTag created")
-- containers that host nested elements
local colsec = gen.CollapsibleSection({ text = "More", open = true })
check(type(colsec.Toggle) == "function", "CollapsibleSection hosts elements")
colsec.Toggle({ text = "Nested", default = true, flag = "nested_t" })
check(PERDITION.Flags.nested_t == true, "nested element inside CollapsibleSection works")
local faq = gen.FAQ({ items = { { question = "Q1?", answer = "A1" }, { question = "Q2?", answer = "A2" } } })
check(type(faq.Items) == "table" and #faq.Items == 2 and type(faq.Items[1].Open) == "function", "FAQ accordion")
check(type(gen.Changelog({ title = "Notes", version = "2.0", entries = { { Tag = "Added", Text = "new" }, "plain" } })) == "table", "Changelog created")
local seg = gen.SegmentedPicker({ text = "Mode", options = { "Low", "Mid", "High" }, default = "Mid", flag = "seg" })
check(seg.Get() == "Mid" and PERDITION.Flags.seg == "Mid", "SegmentedPicker default + flag"); seg.Set("High"); check(seg.Get() == "High", "SegmentedPicker Set")
check(type(gen.GradientPicker({ text = "Grad", colors = { Color3.new(1,0,0), Color3.new(0,0,1) } }).Get) == "function", "GradientPicker created")
local pl = gen.PinnedList({ title = "Items", items = { { Name = "One" }, { Name = "Two", Pinned = true } } })
check(type(pl.Pin) == "function" and type(pl.GetPinned) == "function", "PinnedList Pin/GetPinned")
pl.Pin("One", true); check(#pl.GetPinned() == 2, "PinnedList programmatic pin")
check(type(gen.EnhancedView({ title = "Model" }).SetModel) == "function", "EnhancedView created")
-- global modal + toast
check(type(PERDITION.Modal) == "function", "PERDITION.Modal exists")
PERDITION.Modal({ title = "Confirm", content = "Do it?", onConfirm = function() end, onCancel = function() end })
check(type(PERDITION.Toast) == "function", "PERDITION.Toast exists")
PERDITION.Toast({ content = "Saved", duration = 1, icon = "check" })
print("  ok: Modal + Toast ran")

-- second collapsible section on the same page
local hb = General.Section("HITBOX")
hb.Toggle({ text = "Multi-Point", default = true, flag = "mp" })
check(PERDITION.Flags.mp == true, "second Section control works")

-- page-level direct control (lazy default section)
local direct = Misc.Toggle({ text = "Clean Screen", default = false, flag = "clean" })
check(direct.Get() == false, "page-level direct control works")

-- other top tab gets content too
local vEsp = Visuals.Group("ESP").Page("Players", { icon = "eye" })
vEsp.Section("BOXES").Toggle({ text = "Enabled", default = true, flag = "v_box" })
check(PERDITION.Flags.v_box == true, "second tab content works")

-- columns: a page with an explicit column count + manual section placement
local Grid = Combat.Group("LAYOUT").Page("Grid", { icon = "grid-2x2", columns = 2 })
Grid.Section("LEFT").Toggle({ text = "A", default = true, flag = "grid_a" }) -- auto column 1
Grid.Section("RIGHT", { column = 2 }).Toggle({ text = "B", default = false, flag = "grid_b" })
check(PERDITION.Flags.grid_a == true and PERDITION.Flags.grid_b == false, "columns page + { column = 2 } Section works")

PERDITION.Notify({ title = "Loaded", content = "PERDITION ready", duration = 2 })
print("  ok: Notify ran without error")

-- icon atlas pipeline: the topbar icons (x/minus/search) resolve through the
-- bundled index + spritesheets, so somewhere under the window there must be an
-- image pointing at a stub-cached sheet with a 48x48 sprite rect
local function findAtlasImage(inst)
	local img = inst._props and inst._props.Image
	if type(img) == "string" and img:find("rbxasset://stub/nemesis_icons_", 1, true) == 1 then
		local rect = inst._props.ImageRectSize
		if rect and rect.X == 48 and rect.Y == 48 then
			return inst
		end
	end
	for _, c in ipairs(rawget(inst, "_children") or {}) do
		local hit = findAtlasImage(c)
		if hit then return hit end
	end
	return nil
end
check(findAtlasImage(Win.Instance) ~= nil, "icon atlas resolves from bundled spritesheets")

-- configs: save, list, mutate everything, load, verify the roundtrip
tog.Set(true); sld.Set(0.25); dd.Set("Snipers"); mdd.Set({ "y", "z" })
inp.Set("abc123"); kb.Set("MOUSE2"); cp.Set(Color3.fromRGB(10, 200, 30), 0.5)
check(Win.SaveConfig("smoketest") == true, "SaveConfig writes a config")

local names = Win.ListConfigs()
local sawSaved, sawPreset = false, false
for _, n in ipairs(names) do
	if n == "smoketest" then sawSaved = true end
	if n == "HvH" then sawPreset = true end
end
check(sawSaved, "ListConfigs sees the saved config")
check(sawPreset, "ListConfigs sees preset names from opts.configs")

tog.Set(false); sld.Set(0.9); dd.Set("Pistols"); mdd.Set({ "x" })
inp.Set("overwritten"); kb.Set("MOUSE3"); cp.Set(Color3.fromRGB(1, 2, 3), 0)
check(Win.LoadConfig("smoketest") == true, "LoadConfig reads it back")
check(PERDITION.Flags.aim_enable == true, "toggle restored from config")
check(math.abs(PERDITION.Flags.scale - 0.25) < 1e-6, "slider restored from config")
check(PERDITION.Flags.wg == "Snipers", "dropdown restored from config")
check(type(PERDITION.Flags.tg) == "table" and #PERDITION.Flags.tg == 2, "multi dropdown restored from config")
check(PERDITION.Flags.wh == "abc123", "input restored from config")
check(PERDITION.Flags.kb == "MOUSE2", "keybind restored from config")
local rc = cp.Get()
check(math.abs(rc.R * 255 - 10) < 1.01 and math.abs(rc.G * 255 - 200) < 1.01, "colorpicker colour restored from config")
check(math.abs(cp.GetAlpha() - 0.5) < 1e-6, "colorpicker alpha restored from config")

Win.SetAutoload("smoketest")
check(Win.GetAutoload() == "smoketest", "autoload marker set")
Win.DeleteConfig("smoketest")
check(Win.GetAutoload() == nil, "deleting the autoload config clears the marker")

-- theme switching: window recolours live, palette merges into future builds
check(Win.SetTheme("Midnight") == true, "SetTheme accepts a preset name")
local midnight = PERDITION.Themes.Midnight
check(math.abs(Win.Instance.BackgroundColor3.R - midnight.Background.R) < 1e-6, "window recoloured to the Midnight palette")
check(Win.SetTheme("Dark") == true, "SetTheme back to Dark")

-- GLYPH v4: 3-knob theme generation + token engine
check(type(PERDITION.GenerateTheme) == "function", "GenerateTheme exists")
local glyphInk = PERDITION.GenerateTheme("ink", Color3.fromRGB(255, 45, 45), 0.5)
local nCount = 0 for i = 0, 9 do if glyphInk.N[i] then nCount = nCount + 1 end end
check(type(glyphInk) == "table" and nCount == 10, "GenerateTheme returns a 10-step N scale")
check(glyphInk.PAPER.R > glyphInk.Background.R, "ink base: paper pole is lighter than ground")
local glyphPaper = PERDITION.GenerateTheme("paper", nil, 0.5)
check(glyphPaper.PAPER.R < glyphPaper.Background.R, "paper base: poles inverted")
check(glyphInk.ACC_DIM and glyphInk.ACC_DIM.R ~= nil and glyphInk.ACC_DIM.G ~= nil, "ACC_DIM derived from accent")
check(Win.SetTheme({ base = "ink", accent = Color3.fromRGB(255, 45, 45), contrast = 0.6 }) == true, "SetTheme accepts GLYPH knob form")
check(Win.SetTheme("Paper") == true, "SetTheme back to a literal preset after knob form")

-- key system: a saved key file unlocks with no prompt (and no blocking)
STUB_DISK["Nemesis/key.txt"] = "SMOKE-KEY"
local KWin = PERDITION.Window({ title = "KEYTEST", key = { key = "SMOKE-KEY" } })
check(type(KWin) == "table", "key system: saved key unlocks without prompting")
KWin.Destroy()

-- button control surface
local fired = false
local btn = gen.Button({ text = "Do", callback = function() fired = true end })
btn.Fire()
check(fired, "Button.Fire runs the callback")

-- footer + title live setters
Win.SetGame("SmokeGame")
Win.SetStatus("Testing")
Win.SetTitle("Renamed")
print("  ok: SetGame / SetStatus / SetTitle ran")

-- Syde-style look setters (must exist and run without error)
check(type(Win.SetScale) == "function", "SetScale exists")
check(type(Win.SetBlur) == "function", "SetBlur exists")
check(type(Win.SetLockToScreen) == "function", "SetLockToScreen exists")
check(type(Win.SetGlow) == "function", "SetGlow exists")
Win.SetScale(0.8); Win.SetScale(1.3); Win.SetScale(1)
Win.SetBlur(true); Win.SetBlur(false)
Win.SetLockToScreen(true); Win.SetLockToScreen(false)
Win.SetGlow(true); Win.SetGlow(false)
-- Syde parity setters (must exist and run without error)
for _, n in ipairs({ "SetShadowDensity", "SetShadowColor", "SetRotateGradient", "SetDragSmoothness", "SetHitbox" }) do
	check(type(Win[n]) == "function", n .. " exists")
end
Win.SetShadowDensity(0.4); Win.SetShadowDensity(1)
Win.SetShadowColor(Color3.fromRGB(20, 20, 40))
Win.SetRotateGradient(true); Win.SetRotateGradient(false)
Win.SetDragSmoothness(0.5); Win.SetDragSmoothness(0)
Win.SetHitbox(Color3.fromRGB(0, 200, 255)); Win.SetHitbox(nil)
print("  ok: shadow density/color, rotate gradient, drag smoothness, hitbox ran")
-- slider with min == max must not NaN/crash (regression guard)
local degenerate = gen.Slider({ text = "Degenerate", min = 5, max = 5, default = 5, flag = "degen" })
check(type(degenerate.Get) == "function" and degenerate.Get() == 5, "slider min==max does not crash")
-- background image: URL parsing + pan/zoom/fit
check(type(Win.SetBackgroundFit) == "function", "SetBackgroundFit exists")
check(type(Win.SetBackgroundZoom) == "function", "SetBackgroundZoom exists")
check(type(Win.SetBackgroundOffset) == "function", "SetBackgroundOffset exists")
Win.SetBackgroundImage("https://create.roblox.com/store/asset/11176073582/silly-cat", 0.6)
Win.SetBackgroundImage("13094912294", 0.5)
Win.SetBackgroundFit("Stretch"); Win.SetBackgroundFit("Crop")
Win.SetBackgroundZoom(1.5); Win.SetBackgroundZoom(1)
Win.SetBackgroundOffset(0.2, -0.3); Win.SetBackgroundOffset(0, 0)
Win.SetBackgroundImage(nil)
print("  ok: background image URL parse + fit/zoom/move ran")
Win.ResetLook()
print("  ok: SetScale / SetBlur / SetLockToScreen / ResetLook ran")

print("\nALL CHECKS PASSED")
