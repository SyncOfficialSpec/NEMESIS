--[[
	PERDITION demo: two tabs stuffed with elements so you can test the scroll and
	the resizing (grab the bottom-right corner) - drag it narrow and the panels
	switch columns, wide and they spread back out, all animated.

	Tip: right-click any tab or sidebar page icon to open a searchable picker
	over every Lucide icon and swap it live.

	Run this in your executor. It pulls the latest library from GitHub.
]]

local PERDITION = loadstring(game:HttpGet("https://raw.githubusercontent.com/SyncOfficialSpec/NEMESIS/main/source.lua?_=" .. tostring(os.time())))()

local function notify(title, body, dur)
	PERDITION.Notify({ title = title, content = body, duration = dur or 2, icon = "check" })
end

local Win = PERDITION.Window({
	title = "PERDITION",
	accent = Color3.fromRGB(255, 59, 91),
	game = "Demo",
	status = "Connected",
	configs = { "Default", "Legit", "Rage" },
	toggleKey = Enum.KeyCode.RightShift,
})

------------------------------------------------------------------ TAB 1: COMBAT
local Combat = Win.Tab("Combat", "crosshair")

-- a two-column page so you can watch the columns reflow while resizing
local Aim = Combat.Page("Aimbot", { icon = "target", columns = 2 })

local s_general = Aim.Section("GENERAL")
s_general.Toggle({ text = "Enabled", default = true, flag = "aim_on", callback = function(v) notify("Aimbot", v and "on" or "off", 1) end })
s_general.Toggle({ text = "Silent aim", default = false, desc = "No visible snap." })
s_general.Slider({ text = "FOV", min = 0, max = 360, default = 120, suffix = "deg", flag = "aim_fov" })
s_general.Slider({ text = "Smoothness", min = 0, max = 100, default = 35, suffix = "%" })
s_general.Dropdown({ text = "Target part", options = { "Head", "Neck", "Chest", "Stomach" }, default = "Head" })
s_general.Dropdown({ text = "Priority", options = { "Distance", "Health", "Crosshair", "Threat" }, multi = true, default = { "Distance" } })
s_general.Keybind({ text = "Aim key", default = "MOUSE2", mode = "Hold" })

local s_target = Aim.Section("TARGETING")
s_target.Toggle({ text = "Visibility check", default = true })
s_target.Toggle({ text = "Auto wall", default = false })
s_target.Slider({ text = "Max distance", min = 0, max = 1000, default = 400, suffix = "m" })
s_target.SegmentedPicker({ text = "Hitbox", options = { "Head", "Torso", "Nearest" }, default = "Nearest" })
s_target.Checkbox({ text = "Ignore teammates", default = true })
s_target.Input({ text = "Blacklist", placeholder = "usernames, comma-separated" })

local s_pred = Aim.Section("PREDICTION")
s_pred.Slider({ text = "Hit chance", min = 0, max = 100, default = 80, suffix = "%" })
s_pred.Slider({ text = "Air resistance", min = 0, max = 5, default = 1.2, increment = 0.1 })
s_pred.Toggle({ text = "Resolver", default = true })
s_pred.ColorPicker({ text = "FOV color", default = Color3.fromRGB(255, 59, 91) })
s_pred.Paragraph({ title = "Note", content = "Prediction only matters for projectile weapons. Hit-scan ignores these values entirely." })

local s_extra = Aim.Section("EXTRA")
for i = 1, 6 do
	s_extra.Toggle({ text = "Toggle option " .. i, default = i % 2 == 0 })
end
s_extra.ProgressBar({ text = "Config load", value = 72, max = 100, suffix = "%" })
s_extra.Stat({ text = "Targets hit", value = "1,284", icon = "activity" })
s_extra.HoldButton({ text = "Hold to reset", duration = 1.5, callback = function() notify("Reset", "done", 1) end })
s_extra.RippleButton({ text = "Ripple action", callback = function() notify("Action", "fired", 1) end })

------------------------------------------------------------------ TAB 2: VISUALS
local Visuals = Win.Tab("Visuals", "eye")
local Esp = Visuals.Page("ESP", { icon = "scan-eye", columns = 2 })

local s_box = Esp.Section("BOXES")
s_box.Toggle({ text = "Enabled", default = true })
s_box.Dropdown({ text = "Box type", options = { "2D", "Corner", "3D", "Filled" }, default = "Corner" })
s_box.Slider({ text = "Thickness", min = 1, max = 5, default = 2 })
s_box.ColorPicker({ text = "Box color", default = Color3.fromRGB(90, 200, 255) })
s_box.ColorPicker({ text = "Gradient", colors = { Color3.fromRGB(255, 60, 120), Color3.fromRGB(90, 120, 255) } })

local s_name = Esp.Section("NAMES & INFO")
s_name.Toggle({ text = "Names", default = true })
s_name.Toggle({ text = "Distance", default = true })
s_name.Toggle({ text = "Health bar", default = true })
s_name.Toggle({ text = "Weapon", default = false })
s_name.Slider({ text = "Text size", min = 8, max = 24, default = 13 })
s_name.SegmentedPicker({ text = "Health style", options = { "Bar", "Number", "Both" }, default = "Bar" })

local s_charts = Esp.Section("PERFORMANCE")
s_charts.Stat({ text = "FPS", value = "144", icon = "activity" })
s_charts.BarChart({ text = "Frame time (ms)", points = { { Value = 6, Label = "Mon" }, { Value = 7, Label = "Tue" }, { Value = 5, Label = "Wed" }, { Value = 8, Label = "Thu" }, { Value = 6, Label = "Fri" } } })
s_charts.Chart({ text = "FPS history", points = { 120, 138, 129, 144, 141, 150, 147 } })

local s_world = Esp.Section("WORLD")
s_world.Toggle({ text = "Tracers", default = false })
s_world.Toggle({ text = "Chams", default = false })
s_world.Toggle({ text = "Skeleton", default = false })
s_world.Toggle({ text = "Head dot", default = true })
s_world.Slider({ text = "Render distance", min = 0, max = 2000, default = 500, suffix = "m" })
s_world.FAQ({ items = {
	{ question = "Why is ESP not showing?", answer = "Make sure the toggle is on and your render distance covers the targets." },
	{ question = "Does chams affect FPS?", answer = "Slightly, on lower-end machines. Turn it off if you dip below 60." },
} })
s_world.Divider()
s_world.Label("Scroll the page to see every panel; grab the bottom-right corner to resize.")

notify("Loaded", "Two tabs ready. Right-click an icon to change it.", 3)
