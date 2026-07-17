--[[
	Smoke test for NEMESIS. Run from the repo root:
		lua  test/smoke.lua
		luau test/smoke.lua   (luau may lack dofile; lua is preferred)

	Loads source.lua under the Roblox stub and asserts the full v2 API surface
	(Window -> Tab -> Group -> Page -> Section -> controls) can be constructed
	and that controls' .Set/.Get behave.
]]

dofile("test/stub.lua")

local NEMESIS = dofile("source.lua")

local function check(cond, msg)
	if not cond then
		error("FAIL: " .. msg, 2)
	end
	print("  ok: " .. msg)
end

print("NEMESIS smoke test")
check(type(NEMESIS) == "table", "module returns a table")
check(type(NEMESIS.Window) == "function", "NEMESIS.Window exists")
check(type(NEMESIS.Notify) == "function", "NEMESIS.Notify exists")
check(type(NEMESIS.Flags) == "table", "NEMESIS.Flags table exists")

local Win = NEMESIS.Window({
	title = "NEMESIS",
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
check(NEMESIS.Flags.aim_enable == false, "Toggle flag synced to Flags")

local sld = gen.Slider({ text = "Point Scale", min = 0, max = 1, default = 0.65, increment = 0.01, flag = "scale" })
check(sld.Get() == 0.65, "Slider default 0.65")
sld.Set(0.5)
check(math.abs(sld.Get() - 0.5) < 1e-6, "Slider Set(0.5)")
check(NEMESIS.Flags.scale ~= nil, "Slider flag synced")

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

-- second collapsible section on the same page
local hb = General.Section("HITBOX")
hb.Toggle({ text = "Multi-Point", default = true, flag = "mp" })
check(NEMESIS.Flags.mp == true, "second Section control works")

-- page-level direct control (lazy default section)
local direct = Misc.Toggle({ text = "Clean Screen", default = false, flag = "clean" })
check(direct.Get() == false, "page-level direct control works")

-- other top tab gets content too
local vEsp = Visuals.Group("ESP").Page("Players", { icon = "eye" })
vEsp.Section("BOXES").Toggle({ text = "Enabled", default = true, flag = "v_box" })
check(NEMESIS.Flags.v_box == true, "second tab content works")

-- columns: a page with an explicit column count + manual section placement
local Grid = Combat.Group("LAYOUT").Page("Grid", { icon = "grid-2x2", columns = 2 })
Grid.Section("LEFT").Toggle({ text = "A", default = true, flag = "grid_a" }) -- auto column 1
Grid.Section("RIGHT", { column = 2 }).Toggle({ text = "B", default = false, flag = "grid_b" })
check(NEMESIS.Flags.grid_a == true and NEMESIS.Flags.grid_b == false, "columns page + { column = 2 } Section works")

NEMESIS.Notify({ title = "Loaded", content = "NEMESIS ready", duration = 2 })
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
check(NEMESIS.Flags.aim_enable == true, "toggle restored from config")
check(math.abs(NEMESIS.Flags.scale - 0.25) < 1e-6, "slider restored from config")
check(NEMESIS.Flags.wg == "Snipers", "dropdown restored from config")
check(type(NEMESIS.Flags.tg) == "table" and #NEMESIS.Flags.tg == 2, "multi dropdown restored from config")
check(NEMESIS.Flags.wh == "abc123", "input restored from config")
check(NEMESIS.Flags.kb == "MOUSE2", "keybind restored from config")
local rc = cp.Get()
check(math.abs(rc.R * 255 - 10) < 1.01 and math.abs(rc.G * 255 - 200) < 1.01, "colorpicker colour restored from config")
check(math.abs(cp.GetAlpha() - 0.5) < 1e-6, "colorpicker alpha restored from config")

Win.SetAutoload("smoketest")
check(Win.GetAutoload() == "smoketest", "autoload marker set")
Win.DeleteConfig("smoketest")
check(Win.GetAutoload() == nil, "deleting the autoload config clears the marker")

-- theme switching: window recolours live, palette merges into future builds
check(Win.SetTheme("Midnight") == true, "SetTheme accepts a preset name")
local midnight = NEMESIS.Themes.Midnight
check(math.abs(Win.Instance.BackgroundColor3.R - midnight.Background.R) < 1e-6, "window recoloured to the Midnight palette")
check(Win.SetTheme("Dark") == true, "SetTheme back to Dark")

-- key system: a saved key file unlocks with no prompt (and no blocking)
STUB_DISK["Nemesis/key.txt"] = "SMOKE-KEY"
local KWin = NEMESIS.Window({ title = "KEYTEST", key = { key = "SMOKE-KEY" } })
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
Win.ResetLook()
print("  ok: SetScale / SetBlur / SetLockToScreen / ResetLook ran")

print("\nALL CHECKS PASSED")
