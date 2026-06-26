--[[
	NEMESIS - full showcase
	Loadstring this in your executor to see every element, every mode, and the
	programmatic API in one window.

	Controls:
	  RightShift            hide / show the menu
	  Ctrl + K              focus the search box
	  drag bottom-right     smooth resize
	  minus / x             minimize / close
]]

-- ?_=os.time() busts the GitHub / executor cache so you always pull the latest
local NEMESIS = loadstring(game:HttpGet("https://raw.githubusercontent.com/DiabloPaidProjects/x93adw231fwad2/main/source.lua?_=" .. tostring(os.time())))()

local function notify(title, content, duration)
	NEMESIS.Notify({ title = title, content = content, duration = duration or 3 })
end

local Win = NEMESIS.Window({
	title = "NEMESIS",
	accent = Color3.fromRGB(140, 90, 255),   -- purple accent
	columns = 2,                              -- panels per page (desktop)
	toggleKey = Enum.KeyCode.RightShift,
	-- logoColor = Color3.fromRGB(150, 85, 255), -- optional: recolor the N logo
})

-- TAB 1 : ELEMENTS  (one of every control, with its options)
local Elements = Win.Tab("Elements", "layout-grid")
local Basics = Elements.Group("BASICS")

-- Page: Buttons and Toggles -------------------------------------------
local BT = Basics.Page("Buttons", { icon = "mouse-pointer-click" })
local s_btn = BT.Section("BUTTONS")
s_btn.Button({ text = "Plain Button", button = "Run", callback = function()
	notify("Button", "You clicked the button.", 2)
end })
s_btn.Button({ text = "Button with description", desc = "Buttons can carry a second line.", button = "Go",
	callback = function() notify("Button", "Second button fired.", 2) end })
s_btn.Label("This is a Label. Small muted text inside a section.")
s_btn.Paragraph({ title = "Paragraph", content = "A Paragraph has a title plus a longer wrapping body of text, useful for notes, credits, or instructions." })

local s_tog = BT.Section("TOGGLES")
s_tog.Toggle({ text = "Toggle (off by default)", default = false, flag = "sc_t_off",
	callback = function(v) notify("Toggle", "off-default is now " .. tostring(v), 1.5) end })
s_tog.Toggle({ text = "Toggle (on by default)", default = true, flag = "sc_t_on" })
s_tog.Toggle({ text = "Toggle with description", desc = "A checkbox-style toggle.", default = false, flag = "sc_t_desc" })

-- Page: Sliders -------------------------------------------------------
local SL = Basics.Page("Sliders", { icon = "sliders-horizontal" })
local s_sl = SL.Section("SLIDERS")
s_sl.Slider({ text = "Integer 0 to 250", min = 0, max = 250, default = 100, increment = 1, flag = "sc_s_int" })
s_sl.Slider({ text = "Percent", min = 0, max = 100, default = 50, increment = 5, suffix = "%", flag = "sc_s_pct" })
s_sl.Slider({ text = "Degrees", min = 0, max = 360, default = 90, increment = 15, suffix = "deg", flag = "sc_s_deg" })
s_sl.Slider({ text = "Decimal", min = 0, max = 1, default = 0.65, increment = 0.01, flag = "sc_s_dec" })
s_sl.Slider({ text = "With description", desc = "Drag the handle or click the track.", min = 0, max = 10, default = 3, increment = 1, flag = "sc_s_desc" })

-- Page: Dropdowns -----------------------------------------------------
local DD = Basics.Page("Dropdowns", { icon = "list" })
local s_single = DD.Section("SINGLE SELECT")
s_single.Dropdown({ text = "Quality", options = { "Low", "Medium", "High", "Ultra" }, default = "Medium", flag = "sc_dd_single",
	callback = function(v) notify("Dropdown", "Chose " .. tostring(v), 1.5) end })
s_single.Dropdown({ text = "No default", options = { "First", "Second", "Third" }, flag = "sc_dd_nodef" })

local s_multi = DD.Section("MULTI SELECT")
s_multi.Dropdown({ text = "Hitboxes", options = { "Head", "Neck", "Chest", "Stomach", "Pelvis", "Arms", "Legs" },
	multi = true, default = { "Head", "Chest" }, flag = "sc_dd_multi",
	callback = function(list) notify("Multi", table.concat(list, ", "), 2) end })

-- Page: Text and Keys -------------------------------------------------
local IN = Basics.Page("Text and Keys", { icon = "keyboard" })
local s_in = IN.Section("INPUTS")
s_in.Input({ text = "Name", placeholder = "type here...", default = "", clearOnFocus = false, flag = "sc_in_name",
	callback = function(t) notify("Input", "You typed: " .. t, 2) end })
s_in.Input({ text = "Clears on focus", placeholder = "click me", clearOnFocus = true, flag = "sc_in_clear" })

local s_kb = IN.Section("KEYBINDS")
s_kb.Keybind({ text = "Toggle mode (E)", default = Enum.KeyCode.E, mode = "Toggle", flag = "sc_kb_toggle",
	callback = function(state) notify("Keybind / Toggle", "state = " .. tostring(state), 1.5) end })
s_kb.Keybind({ text = "Hold mode (F)", default = Enum.KeyCode.F, mode = "Hold", flag = "sc_kb_hold",
	callback = function(down) notify("Keybind / Hold", down and "DOWN" or "up", 1) end })
s_kb.Keybind({ text = "Always mode (G)", default = Enum.KeyCode.G, mode = "Always", flag = "sc_kb_always",
	callback = function() notify("Keybind / Always", "fired", 1) end })
s_kb.Keybind({ text = "Mouse button", default = "MOUSE5", mode = "Hold", flag = "sc_kb_mouse" })

-- Page: Colors --------------------------------------------------------
local CO = Basics.Page("Colors", { icon = "palette" })
local s_co = CO.Section("COLOR PICKERS")
s_co.ColorPicker({ text = "Solid color", default = Color3.fromRGB(255, 0, 80), transparency = 0, flag = "sc_c_solid",
	callback = function(color, alpha) notify("Color", "alpha = " .. tostring(alpha), 1.5) end })
s_co.ColorPicker({ text = "With transparency", default = Color3.fromRGB(0, 200, 255), transparency = 0.3, flag = "sc_c_alpha" })
s_co.ColorPicker({ text = "Gradient color", gradient = true, default = Color3.fromRGB(255, 0, 0), gradientDefault = Color3.fromRGB(0, 0, 255), flag = "sc_c_grad" })
s_co.Label("Right-click a swatch to copy its hex. In gradient mode you get two swatches; right-click a saved swatch to remove it.")
s_co.Divider({ text = "MENU THEME" })
s_co.ColorPicker({ text = "Menu accent (live)", default = Color3.fromRGB(140, 90, 255), flag = "sc_accent",
	callback = function(color) Win.SetAccent(color) end })

-- Page: Lists (Divider + Listbox)
local LB = Basics.Page("Lists", { icon = "list-checks" })
local s_lb = LB.Section("LISTBOX")
s_lb.Listbox({ text = "Single select", options = { "Aimbot", "Triggerbot", "Backtrack", "Anti-Aim", "Fakelag" }, default = "Aimbot", rows = 4,
	callback = function(v) notify("Listbox", "chose " .. tostring(v), 1.5) end })
s_lb.Divider()
s_lb.Listbox({ text = "Multi select", options = { "Head", "Neck", "Chest", "Stomach", "Pelvis", "Arms", "Legs" }, multi = true, default = { "Head", "Chest" }, rows = 4,
	callback = function(list) notify("Listbox", table.concat(list, ", "), 2) end })

-- Standalone page (renders below the group, no group header) -----------
local Info = Elements.Page("Info", { icon = "info" })
local s_info = Info.Section("ABOUT")
s_info.Paragraph({ title = "Standalone pages", content = "Pages added with Tab.Page (instead of Group.Page) render below the groups, like this one." })
s_info.Label("Every flag value lives in NEMESIS.Flags, keyed by its flag name.")

-- TAB 2 : LAYOUT  (groups, dividers, and the two-column grid)
local Layout = Win.Tab("Layout", "columns-2")

local Combat = Layout.Group("COMBAT")
local Aim = Combat.Page("Aimbot", { icon = "crosshair" })
local s_aim = Aim.Section("AIMBOT")
s_aim.Toggle({ text = "Enable", default = true, flag = "sc_aim" })
s_aim.Slider({ text = "FOV", min = 0, max = 180, default = 120, suffix = "deg", flag = "sc_fov" })
s_aim.Dropdown({ text = "Target", options = { "Closest", "Health", "Distance" }, default = "Closest", flag = "sc_target" })

local Visuals = Layout.Group("VISUALS")
local Esp = Visuals.Page("ESP", { icon = "eye" })
local s_esp = Esp.Section("ESP")
s_esp.Toggle({ text = "Enabled", default = true, flag = "sc_esp" })
s_esp.ColorPicker({ text = "Box color", default = Color3.fromRGB(120, 255, 120), flag = "sc_esp_col" })
s_esp.Keybind({ text = "Toggle ESP", default = Enum.KeyCode.V, mode = "Toggle", flag = "sc_esp_key" })

-- Standalone item under the Layout tab
local Extra = Layout.Page("Extra", { icon = "more-horizontal" })
local s_extra = Extra.Section("MISC")
s_extra.Toggle({ text = "Lazy-section toggle", default = false, flag = "sc_lazy" })

-- Explicit two-column page with manual section placement
local Grid = Layout.Page("Grid", { icon = "grid-2x2", columns = 2 })
local gridL = Grid.Section("LEFT COLUMN")               -- auto-placed (column 1)
gridL.Toggle({ text = "Auto column 1", default = true, flag = "sc_grid_a" })
gridL.Slider({ text = "Value", min = 0, max = 100, default = 40, flag = "sc_grid_v" })
local gridR = Grid.Section("RIGHT COLUMN", { column = 2 }) -- forced into column 2
gridR.Toggle({ text = "Manual column 2", default = false, flag = "sc_grid_b" })
gridR.Dropdown({ text = "Mode", options = { "A", "B", "C" }, default = "A", flag = "sc_grid_m" })

-- TAB 3 : CONTROL  (programmatic Set / Get and SetOptions)
local Control = Win.Tab("Control", "settings-2")
local Live = Control.Page("Live", { icon = "activity" })

local s_driven = Live.Section("DRIVEN BY BUTTONS")
local liveToggle = s_driven.Toggle({ text = "Controlled toggle", default = false, flag = "sc_ctl_toggle" })
local liveSlider = s_driven.Slider({ text = "Controlled slider", min = 0, max = 100, default = 0, flag = "sc_ctl_slider" })
local liveDrop   = s_driven.Dropdown({ text = "Controlled dropdown", options = { "A", "B", "C" }, default = "A", flag = "sc_ctl_drop" })

local s_actions = Live.Section("ACTIONS")
s_actions.Button({ text = "Toggle ON", button = "On", callback = function() liveToggle.Set(true) end })
s_actions.Button({ text = "Toggle OFF", button = "Off", callback = function() liveToggle.Set(false) end })
s_actions.Button({ text = "Slider = 75", button = "75", callback = function() liveSlider.Set(75) end })
s_actions.Button({ text = "Dropdown = C", button = "C", callback = function() liveDrop.Set("C") end })
s_actions.Button({ text = "Swap dropdown options", button = "Swap", callback = function()
	liveDrop.SetOptions({ "X", "Y", "Z", "W" })
	notify("SetOptions", "Dropdown options replaced.", 2)
end })
s_actions.Button({ text = "Read all values", button = "Read", callback = function()
	notify("Get()",
		"toggle=" .. tostring(liveToggle.Get())
		.. "  slider=" .. tostring(liveSlider.Get())
		.. "  drop=" .. tostring(liveDrop.Get()), 4)
end })

-- TAB 4 : CONFIG  (logo recolor, accent presets, notifications)
local Config = Win.Tab("Config", "settings")
local Cfg = Config.Page("Interface", { icon = "palette" })

local s_logo = Cfg.Section("LOGO")
s_logo.ColorPicker({ text = "Logo color", default = Color3.fromRGB(150, 85, 255), transparency = 0, flag = "sc_logo",
	callback = function(color) Win.SetLogoColor(color) end })
s_logo.Dropdown({ text = "Logo preset", options = { "Purple", "Red", "Pink", "Green", "Cyan", "White" }, default = "Purple", flag = "sc_logo_preset",
	callback = function(v)
		local map = {
			Purple = Color3.fromRGB(150, 85, 255), Red = Color3.fromRGB(255, 45, 45),
			Pink = Color3.fromRGB(255, 90, 200), Green = Color3.fromRGB(90, 255, 120),
			Cyan = Color3.fromRGB(60, 220, 255), White = Color3.fromRGB(245, 245, 250),
		}
		Win.SetLogoColor(map[v])
	end })
s_logo.ColorPicker({ text = "Logo gradient", gradient = true, default = Color3.fromRGB(170, 100, 255), gradientDefault = Color3.fromRGB(255, 70, 160), flag = "sc_logo_grad",
	callback = function(colors) if type(colors) == "table" then Win.SetLogoGradient(colors[1], colors[2]) end end })
s_logo.Button({ text = "Reset logo to solid", button = "Reset", callback = function() Win.SetLogoColor(Color3.fromRGB(150, 85, 255)) end })

local s_note = Cfg.Section("NOTIFICATIONS")
s_note.Button({ text = "Short notification", button = "2s", callback = function() notify("Heads up", "This one lasts two seconds.", 2) end })
s_note.Button({ text = "Long notification", button = "6s", callback = function() notify("Reminder", "This one sticks around for six seconds.", 6) end })
s_note.Input({ text = "Custom message", placeholder = "type then press Send", flag = "sc_note_msg" })
s_note.Button({ text = "Send custom", button = "Send", callback = function()
	local msg = NEMESIS.Flags.sc_note_msg
	notify("Custom", (msg ~= nil and msg ~= "" and msg) or "Type something in the box above.", 3)
end })

local s_credits = Cfg.Section("ABOUT")
s_credits.Paragraph({ title = "NEMESIS", content = "idk" })

NEMESIS.Notify({ title = "NEMESIS", content = "Showcase loaded. Explore every tab.", duration = 5 })
