# PERDITION (formerly NEMESIS)

A UI library for Roblox script executors. It gives you a desktop style window with
tabs, a sidebar, collapsible sections, and the usual set of controls (toggles,
sliders, dropdowns, color pickers, and so on). The API is small and consistent, so
building a menu is mostly a matter of calling the element you want on a section.

**v4 "GLYPH"**: industrial monochrome hardware. One alarm-red accent on an
ink-and-paper scale, square LED toggles, RobotoMono part codes on every
section and element (`cfg–01`, `tgl–02`), raw-data readouts, a dot-matrix
boot sequence, and instant 0ms states. Same API as v3 — old scripts drop in.
Design spec: `docs/GLYPH.md`.

MIT licensed. Works with any executor that supports `loadstring` and `game:HttpGet`.

## Loading

```lua
local NEMESIS = loadstring(game:HttpGet("https://raw.githubusercontent.com/SyncOfficialSpec/NEMESIS/main/source.lua"))()
```

## Quick start

```lua
local NEMESIS = loadstring(game:HttpGet("https://raw.githubusercontent.com/SyncOfficialSpec/NEMESIS/main/source.lua"))()

local Window = NEMESIS.Window({
    title = "My Script",
    accent = Color3.fromRGB(140, 90, 255),
    toggleKey = Enum.KeyCode.RightShift,
})

local Tab = Window.Tab("Main", "crosshair")
local Section = Tab.Page("Aimbot").Section("SETTINGS")

Section.Toggle({
    text = "Enabled",
    default = false,
    flag = "aim_enabled",
    callback = function(value)
        print("Aimbot:", value)
    end,
})

Section.Slider({
    text = "FOV",
    min = 0, max = 360, default = 120, suffix = "deg",
    flag = "aim_fov",
})

NEMESIS.Notify({ title = "Loaded", content = "Press RightShift to toggle the menu." })
```

## Structure

A menu is built from the top down:

```
Window
  Tab                     Window.Tab(name, icon)
    Group                 Tab.Group(name)            optional, groups sub-tabs
      Page                Group.Page(name, opts)
    Page                  Tab.Page(name, opts)       a standalone sub-tab
      Section             Page.Section(title, opts)
        elements          Section.Toggle{...}, etc.
```

Pages also expose the element methods directly. Calling `Page.Toggle{...}` creates
an unnamed section for you, which is handy for short pages.

## Window

```lua
local Window = NEMESIS.Window({
    title = "My Script",                          -- top bar title
    accent = Color3.fromRGB(140, 90, 255),        -- main accent color
    toggleKey = Enum.KeyCode.RightShift,          -- key to hide/show the menu
    columns = 2,                                  -- panels per page, default 2
    width = 900, height = 600,                    -- starting size
    logoColor = Color3.fromRGB(150, 85, 255),     -- tint for the built-in logo
    logoGradient = { color1, color2 },            -- a gradient on the logo
    logo = 0,                                     -- a Roblox image id to replace the logo
    theme = "Midnight",                           -- preset name, or a table of overrides
    game = "Arsenal",                             -- sidebar footer, first line
    status = "Undetected",                        -- sidebar footer, second line
    configs = { "Legit", "Rage" },                -- preset config names for the header
    folder = "Nemesis/MyScript",                  -- config folder, defaults to Nemesis/<title>
    key = { key = "hello123" },                   -- key system, see below
})
```

Everything is optional, but you usually want a `title` and an `accent`.

### Window methods

```lua
Window.Tab(name, icon)              -- add a tab, returns the Tab
Window.SetAccent(color)             -- recolor the whole menu at runtime
Window.SetTheme("Light")            -- switch theme at runtime (name or table)
Window.SetTitle(text)               -- change the top bar title
Window.SetGame(text)                -- change the footer game line
Window.SetStatus(text)              -- change the footer status line
Window.SetLogoColor(color)          -- set a solid logo tint
Window.SetLogoGradient(c1, c2)      -- set a gradient on the logo
Window.Toggle(force)                -- minimize or restore, force is optional
Window.Destroy()                    -- remove the menu (Window.Unload works too)

Window.SaveConfig(name)             -- write every flagged element to disk
Window.LoadConfig(name)             -- read a config back and apply it
Window.ListConfigs()                -- saved configs + your preset names
Window.DeleteConfig(name)           -- remove a config file
Window.SetAutoload(name)            -- this config loads on every start (nil clears)
Window.GetAutoload()                -- current autoload name or nil
```

Built in shortcuts: `RightShift` (or your `toggleKey`) hides and shows the menu,
`Ctrl + K` focuses the search box, and the bottom right corner can be dragged to
resize the window.

The sidebar has a footer with a status dot, your `game` and `status` lines, and a
live FPS counter. The content header has a config pill and a save button next to
the breadcrumb.

## Tabs, groups, pages, sections

```lua
local Tab = Window.Tab("Combat", "crosshair")

-- grouped sub-tabs (a labelled group in the sidebar)
local Group = Tab.Group("AIMBOT")
local Page  = Group.Page("General", { icon = "crosshair" })

-- a standalone sub-tab with no group header
local Misc  = Tab.Page("Misc", { icon = "settings" })

-- sections hold the elements
local Section = Page.Section("GENERAL")
local Right   = Page.Section("VISUALS", { side = "right" })  -- or { column = 2 }
```

Icons accept a Lucide name (for example `"crosshair"`, `"eye"`, `"settings"`) or a
Roblox image id. Pages can set their own column count with `{ columns = 2 }`.

The full Lucide set (about 2000 icons) ships with this repo as spritesheets under
`assets/icons`, so icon loading has no third-party dependency. Sheets download
once and cache on disk through `getcustomasset`; executors without that function
fall back to text glyphs. Regenerate the atlas with the scripts in `tools/iconsgen`
(node for rasterizing, python for packing).

## Elements

Every element takes a single table of options. Most return a control object with
`Set` and `Get`. The common options are:

- `text` the label shown on the left
- `desc` an optional second line of muted text
- `flag` stores the value in `NEMESIS.Flags[flag]`
- `callback` runs with the new value whenever it changes

### Button

```lua
local Btn = Section.Button({
    text = "Run",
    button = "Go",
    callback = function() print("clicked") end,
})
Btn.Fire()          -- trigger it from code
Btn.SetText("Redo") -- rename the chip
```

### Toggle

```lua
local t = Section.Toggle({ text = "Enabled", default = false, flag = "x", callback = function(v) end })
t.Set(true)
print(t.Get())
```

### Slider

```lua
local s = Section.Slider({
    text = "FOV", min = 0, max = 360, default = 120,
    increment = 1, suffix = "deg", flag = "fov",
    callback = function(v) end,
})
s.Set(200)
```

The value can be clicked and typed in for an exact number.

### Dropdown

```lua
-- single select
Section.Dropdown({
    text = "Target", options = { "Closest", "Health", "Distance" },
    default = "Closest", flag = "target", callback = function(v) end,
})

-- multi select, the value is a table
Section.Dropdown({
    text = "Hitboxes", options = { "Head", "Chest", "Stomach" },
    multi = true, default = { "Head" }, callback = function(list) end,
})
```

Methods: `Set(value)`, `Get()`, `SetOptions(newList)`.

### Input

```lua
Section.Input({
    text = "Name", placeholder = "type here", default = "",
    clearOnFocus = false, flag = "name", callback = function(text) end,
})
```

The field grows as you type and clips long text so it never overflows.

### Keybind

```lua
Section.Keybind({
    text = "Toggle key", default = Enum.KeyCode.E, mode = "Toggle",
    flag = "key", callback = function(state) end,
})
```

`mode` is `"Toggle"`, `"Hold"`, or `"Always"`. `default` takes an `Enum.KeyCode` or
a mouse string such as `"MOUSE5"`.

### Color picker

```lua
-- single color
local c = Section.ColorPicker({
    text = "ESP color", default = Color3.fromRGB(0, 255, 0), transparency = 0,
    flag = "esp_color", callback = function(color, alpha) end,
})

-- gradient, two colors
Section.ColorPicker({
    text = "Gradient", gradient = true,
    default = Color3.fromRGB(255, 0, 0), gradientDefault = Color3.fromRGB(0, 0, 255),
    callback = function(colors) end,  -- colors is { color1, color2 }
})
```

Methods: `Set(color, alpha)`, `Get()`, `GetAlpha()`, `SetGradient(c1, c2)`. The
picker has a palette, hue and alpha sliders, preset swatches, a save button (right
click a saved swatch to remove it), and a hex field.

### Listbox

An always open list of selectable items.

```lua
Section.Listbox({
    text = "Mode", options = { "A", "B", "C" }, default = "A",
    rows = 4, flag = "mode", callback = function(v) end,
})
```

Pass `multi = true` for multiple selection. Methods: `Set`, `Get`, `SetOptions`.

### Label, Paragraph, Divider

```lua
Section.Label("Some short text.")
local Par = Section.Paragraph({ title = "Notes", content = "A longer block of wrapping text." })
Par.Set("New body text.")
Par.SetTitle("Changed")
Section.Divider({ text = "ADVANCED" })   -- text is optional
```

## Notifications

```lua
NEMESIS.Notify({
    title = "Saved",
    content = "Your config was saved.",
    duration = 4,          -- seconds, optional
    icon = "check",        -- optional Lucide name or image id
})
```

Notifications appear in the top right and dismiss themselves after `duration`.

## Flags

Any element with a `flag` stores its current value in `NEMESIS.Flags`.

```lua
Section.Toggle({ text = "Enabled", flag = "enabled" })
-- later
if NEMESIS.Flags.enabled then ... end
```

## Configs

Every element with a `flag` is saved and restored automatically, including
colors, gradients and keybinds. Configs are json files in your `folder`
(default `Nemesis/<title>`).

```lua
Window.SaveConfig("legit")     -- write current values
Window.LoadConfig("legit")     -- apply them back (callbacks fire)
Window.SetAutoload("legit")    -- load this one on every start
```

The header has the same thing as UI: the pill shows the active config and opens
a panel with every saved config plus New / Save / Del actions. Right click a
config in the panel to make it the autoload (marked with a star). Pass
`configs = { "Legit", "Rage" }` to pre-seed names, and `onSave` / `onConfig`
callbacks if your script wants to react.

On executors without a file API the config UI hides itself and the methods
return false.

## Key system

Gate the menu behind a key. Nothing is built until the key checks out.

```lua
local Window = NEMESIS.Window({
    title = "My Script",
    key = {
        keys = { "hello123", "vip-key" },  -- any of these unlocks (key = "..." works too)
        note = "Get the key from our discord.",
        saveKey = true,                    -- remember it (Nemesis/key.txt), default true
    },
})
```

With `saveKey` on, a returning user with a valid saved key never sees the
prompt. Closing the prompt raises an error, so the rest of the script does not
run without a key.

## Theming

The default identity is `Glyph` (ink monochrome + alarm red). The v3 presets
still ship: `Paper`, `Dark`, `Midnight` and `Abyss`. Pick one at creation or
switch live, the whole menu recolors in place:

```lua
PERDITION.Window({ theme = "Dark" })
-- or at runtime, for example from a dropdown callback:
Window.SetTheme("Paper")
```

v4 also generates palettes from three knobs (base / accent / contrast), so a
whole coherent theme comes from one accent colour:

```lua
Window.SetTheme({ base = "ink", accent = Color3.fromRGB(255, 170, 0), contrast = 0.6 })
-- base: "ink" (dark) or "paper" (light); contrast: 0..1

-- preview a generated palette without applying it:
local pal = PERDITION.GenerateTheme("paper", Color3.fromRGB(255, 45, 45), 0.5)
```

You can also override individual keys per window, or pass a full table to
`SetTheme`:

```lua
PERDITION.Window({
    accent = Color3.fromRGB(0, 200, 120),
    theme = {
        Background = Color3.fromRGB(10, 10, 12),
        Element    = Color3.fromRGB(20, 20, 24),
        Text       = Color3.fromRGB(240, 240, 245),
    },
})
```

You can also recolor the accent at runtime with `Window.SetAccent(color)`, for
example from a color picker callback.

## Examples

`showcase.lua` shows every element and option in one place:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/SyncOfficialSpec/NEMESIS/main/showcase.lua"))()
```

## License

MIT. See `LICENSE`.
