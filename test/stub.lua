--[[
	Minimal Roblox-environment stub for offline smoke-testing NEMESIS with
	plain `lua` / `luau`. It installs just enough globals for source.lua to
	LOAD and CONSTRUCT its UI table without a real Roblox runtime.

	It does NOT emulate rendering, input, or tweening - event callbacks and
	tweens are no-ops. It verifies the library parses, builds every element,
	and that .Set/.Get behave. Visual behaviour is validated in-executor.

	dofile this before dofile("source.lua").
]]

----------------------------------------------------------------------
-- math.clamp (Luau/Roblox extension, absent in standard Lua)
----------------------------------------------------------------------
if not math.clamp then
	function math.clamp(x, a, b)
		if x < a then return a elseif x > b then return b else return x end
	end
end

----------------------------------------------------------------------
-- Instance mock
----------------------------------------------------------------------
local EVENT_KEYS = {
	InputBegan = true, InputChanged = true, InputEnded = true,
	MouseButton1Click = true, MouseButton2Click = true, MouseButton1Down = true,
	MouseButton1Up = true, MouseEnter = true, MouseLeave = true, MouseMoved = true,
	FocusLost = true, Focused = true, Changed = true, Activated = true,
	ChildAdded = true, ChildRemoved = true,
	-- RunService frame signals (used by the live FPS counter)
	Heartbeat = true, RenderStepped = true, Stepped = true,
}

local METHODS
local instMeta = {}

local function newInstance(className)
	local self = setmetatable({}, instMeta)
	rawset(self, "_props", { ClassName = className, Name = className })
	rawset(self, "_children", {})
	rawset(self, "_signals", {})
	rawset(self, "_attrs", {})
	return self
end

local function signal()
	local conns = {}
	local s
	s = {
		Connect = function(_, fn)
			conns[fn] = true
			return { Disconnect = function() conns[fn] = nil end, Connected = true }
		end,
		Once = function(_, fn) conns[fn] = true; return { Disconnect = function() conns[fn] = nil end } end,
		Wait = function() end,
		Fire = function(_, ...)
			for fn in pairs(conns) do pcall(fn, ...) end
		end,
	}
	return s
end

METHODS = {
	Destroy = function(self) self._props.Parent = nil end,
	GetChildren = function(self)
		local t = {}
		for i, c in ipairs(self._children) do t[i] = c end
		return t
	end,
	GetDescendants = function() return {} end,
	IsA = function(self, cn) return self._props.ClassName == cn end,
	FindFirstChild = function(self, name)
		for _, c in ipairs(self._children) do
			if c._props.Name == name then return c end
		end
		return nil
	end,
	FindFirstChildOfClass = function(self, cn)
		for _, c in ipairs(self._children) do
			if c._props.ClassName == cn then return c end
		end
		return nil
	end,
	FindFirstAncestorWhichIsA = function(self, cn)
		local p = self._props.Parent
		while type(p) == "table" and rawget(p, "_props") do
			if p._props.ClassName == cn then return p end
			p = p._props.Parent
		end
		return nil
	end,
	WaitForChild = function(self, name)
		return METHODS.FindFirstChild(self, name) or newInstance(name)
	end,
	GetPropertyChangedSignal = function() return signal() end,
	Clone = function(self) return newInstance(self._props.ClassName) end,
	TweenSize = function() end,
	SetAttribute = function(self, k, v) self._attrs[k] = v end,
	GetAttribute = function(self, k) return self._attrs[k] end,
}

instMeta.__index = function(self, k)
	if EVENT_KEYS[k] then
		local s = self._signals[k]
		if not s then
			s = signal()
			self._signals[k] = s
		end
		return s
	end
	if METHODS[k] then return METHODS[k] end
	if self._props[k] == nil then
		if k == "AbsolutePosition" then return Vector2.new(0, 0) end
		if k == "AbsoluteSize" then return Vector2.new(120, 28) end
		if k == "TextBounds" then return Vector2.new(0, 0) end
	end
	return self._props[k]
end

instMeta.__newindex = function(self, k, v)
	-- Roblox Instances reject custom fields; underscore-prefixed keys are a
	-- common mistake (store such state in plain Lua tables, not on Instances)
	if type(k) == "string" and k:sub(1, 1) == "_" then
		error("cannot set custom field '" .. k .. "' on a Roblox Instance", 2)
	end
	if k == "Parent" then
		self._props.Parent = v
		if type(v) == "table" and rawget(v, "_children") then
			table.insert(v._children, self)
		end
	else
		self._props[k] = v
	end
end

Instance = { new = function(cn) return newInstance(cn) end }

----------------------------------------------------------------------
-- Datatypes
----------------------------------------------------------------------
local function color3(r, g, b)
	return {
		R = r, G = g, B = b,
		ToHSV = function() return 0, 0, 0 end,
		Lerp = function(self) return self end,
	}
end
Color3 = {
	new = function(r, g, b) return color3(r or 0, g or 0, b or 0) end,
	fromRGB = function(r, g, b) return color3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end,
	fromHSV = function(h, s, v) return color3(h or 0, s or 0, v or 0) end,
}

Vector2 = {
	new = function(x, y) return { X = x or 0, Y = y or 0 } end,
}

UDim = {
	new = function(s, o) return { Scale = s or 0, Offset = o or 0 } end,
}
UDim2 = {
	new = function(xs, xo, ys, yo)
		return { X = { Scale = xs or 0, Offset = xo or 0 }, Y = { Scale = ys or 0, Offset = yo or 0 } }
	end,
	fromOffset = function(xo, yo)
		return { X = { Scale = 0, Offset = xo or 0 }, Y = { Scale = 0, Offset = yo or 0 } }
	end,
}

TweenInfo = { new = function() return {} end }

ColorSequenceKeypoint = { new = function(t, c) return { Time = t, Value = c } end }
ColorSequence = { new = function(kp) return { Keypoints = kp } end }
NumberSequenceKeypoint = { new = function(t, v) return { Time = t, Value = v } end }
NumberSequence = { new = function(a) return { Keypoints = a } end }

----------------------------------------------------------------------
-- Enum (permissive - any chain returns a harmless sentinel)
----------------------------------------------------------------------
local enumMeta
enumMeta = {
	__index = function() return setmetatable({ Name = "EnumItem", Value = 0 }, enumMeta) end,
}
Enum = setmetatable({}, enumMeta)

-- Font / typeof so FontFace (Font.new) assignment works under the stub
Font = {
	new = function(family, weight, style)
		return { _isFont = true, Family = family, Weight = weight, Style = style }
	end,
	fromName = function(name, weight, style)
		return { _isFont = true, Family = name, Weight = weight, Style = style }
	end,
}
function typeof(v)
	if type(v) == "table" and getmetatable(v) == nil and v._isFont then return "Font" end
	return type(v)
end

Rect = { new = function(x0, y0, x1, y1) return { Min = { X = x0, Y = y0 }, Max = { X = x1, Y = y1 } } end }

----------------------------------------------------------------------
-- Services + game
----------------------------------------------------------------------
local function makeServiceInstance(name, props)
	local inst = newInstance(name)
	if props then
		for k, v in pairs(props) do inst[k] = v end
	end
	return inst
end

local TweenServiceStub = {
	Create = function(_, _, _, _)
		return { Play = function() end, Cancel = function() end, Completed = signal() }
	end,
}

local services = {
	TweenService = TweenServiceStub,
	UserInputService = makeServiceInstance("UserInputService", {
		TouchEnabled = false, KeyboardEnabled = true, MouseEnabled = true, GamepadEnabled = false,
	}),
	RunService = makeServiceInstance("RunService"),
	CoreGui = makeServiceInstance("CoreGui"),
	HttpService = makeServiceInstance("HttpService"),
	GuiService = makeServiceInstance("GuiService"),
}
local playerGui = newInstance("PlayerGui")
local localPlayer = makeServiceInstance("Player", { Name = "TestPlayer" })
localPlayer.PlayerGui = playerGui
table.insert(localPlayer._children, playerGui)
services.Players = makeServiceInstance("Players", { LocalPlayer = localPlayer })

-- fake executor file API + HttpGet that serves this repo's own raw URLs from
-- disk, so the icon atlas pipeline (index -> sheet -> getcustomasset) runs
-- for real during the smoke test
if not loadstring then loadstring = load end

local RAW_BASE = "https://raw.githubusercontent.com/SyncOfficialSpec/NEMESIS/main/"
local fakeDisk = {}
writefile = function(path, data) fakeDisk[path] = data end
isfile = function(path) return fakeDisk[path] ~= nil end
readfile = function(path) return fakeDisk[path] end
getcustomasset = function(path)
	assert(fakeDisk[path], "getcustomasset on missing file: " .. tostring(path))
	return "rbxasset://stub/" .. path
end

game = {
	GetService = function(_, name)
		if not services[name] then
			services[name] = makeServiceInstance(name)
		end
		return services[name]
	end,
	HttpGet = function(_, url)
		if type(url) == "string" and url:sub(1, #RAW_BASE) == RAW_BASE then
			local rel = url:sub(#RAW_BASE + 1):gsub("%?.*$", "")
			local f = io.open(rel, "rb")
			if f then
				local data = f:read("*a")
				f:close()
				return data
			end
		end
		error("HttpGet unavailable in stub: " .. tostring(url))
	end,
}
setmetatable(game, { __index = function(_, k) return services[k] end })

----------------------------------------------------------------------
-- workspace (CurrentCamera.ViewportSize)
----------------------------------------------------------------------
workspace = newInstance("Workspace")
local camera = newInstance("Camera")
camera.ViewportSize = Vector2.new(1280, 720)
workspace.CurrentCamera = camera

----------------------------------------------------------------------
-- task scheduler (no-op: do not run deferred callbacks during smoke test)
----------------------------------------------------------------------
task = {
	spawn = function(fn, ...) if type(fn) == "function" then pcall(fn, ...) end end,
	delay = function() end,
	wait = function() return 0 end,
	defer = function() end,
}
if not wait then wait = function() return 0 end end
