# NEMESIS

A UI library for Roblox script executors. It gives you a desktop style window with
tabs, a sidebar, collapsible sections, and the usual set of controls (toggles,
sliders, dropdowns, color pickers, and so on). The API is small and consistent, so
building a menu is mostly a matter of calling the element you want on a section.

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
    theme = { Background = Color3.new(0, 0, 0) }, -- override any theme color
})
```

Everything is optional, but you usually want a `title` and an `accent`.

### Window methods

```lua
Window.Tab(name, icon)              -- add a tab, returns the Tab
Window.SetAccent(color)            -- recolor the whole menu at runtime
Window.SetLogoColor(color)         -- set a solid logo tint
Window.SetLogoGradient(c1, c2)     -- set a gradient on the logo
Window.Toggle(force)               -- minimize or restore, force is optional
Window.Destroy()                   -- remove the menu
```

Built in shortcuts: `RightShift` (or your `toggleKey`) hides and shows the menu,
`Ctrl + K` focuses the search box, and the bottom right corner can be dragged to
resize the window.

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

## Elements

Every element takes a single table of options. Most return a control object with
`Set` and `Get`. The common options are:

- `text` the label shown on the left
- `desc` an optional second line of muted text
- `flag` stores the value in `NEMESIS.Flags[flag]`
- `callback` runs with the new value whenever it changes

### Button

```lua
Section.Button({
    text = "Run",
    button = "Go",
    callback = function() print("clicked") end,
})
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
Section.Paragraph({ title = "Notes", content = "A longer block of wrapping text." })
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

## Theming

Colors come from a theme table. Override any of the keys per window:

```lua
NEMESIS.Window({
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
