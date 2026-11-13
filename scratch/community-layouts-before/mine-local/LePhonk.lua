-- LePhonk (Xynth Audio): Zekete type/amount with transfer curve, Le Ottz and Le Fonz ring knobs, dry/wet and output rings, power button (fits the 216 px card: Le Ottz / Le Fonz in a right column).
local SFX = require('src.Functions.Stock FX UI')
local W, H = 290, 216
local D = SFX.Begin({ Title = 'LePhonk', W = W, H = H, Accent = SFX.ACCENT.Dynamics,
    Params = { ottz = { 'Le Ottz', idx = 0 }, fonz = { 'Le Fonz', idx = 1 }, zek = { 'Zekete', idx = 2 }, gain = { 'Output Gain', idx = 3 },
        en = { 'Enabled', idx = 4 }, zdw = { 'Zekete Dry/Wet', idx = 9 }, ztype = { 'Zekete Type', idx = 10 } } })
if not D then return end
local DL = D.DL
local X, Y = D.X, D.Y
local BLUE, PURP, TRK, BG = 0x8EC6F4FF, 0xA48FEFFF, 0x4A4D50FF, 0x202226FF

D:Rect(0, 0, W, H, BG, 0, true)
im.DrawList_AddRectFilledMultiColor(DL, X + 15, Y + 40, X + 275, Y + 126, 0x3A8399FF, 0x3A8399FF, 0x4A58A0FF, 0x4A58A0FF)
im.DrawList_AddRectFilledMultiColor(DL, X + 15, Y + 126, X + 275, Y + 212, 0x4A58A0FF, 0x4A58A0FF, 0x5A1A94FF, 0x5A1A94FF)

-- header
D:Text(14, 9, BLUE, 'Le Phonk', 16, nil, true)
D:Line(14, 31, 276, 31, BLUE, 1)

local A0 = 0.75 * math.pi
local function ring(key, cx, cy, rad, th, clr, inner)
    local v = D:Get(key) or 0
    local x, y = X + cx, Y + cy
    if inner then im.DrawList_AddCircleFilled(DL, x, y, rad - th * 0.5, inner) end
    im.DrawList_PathArcTo(DL, x, y, rad, A0, A0 + 1.5 * math.pi, 32)
    im.DrawList_PathStroke(DL, TRK, nil, th)
    if v > 0.005 then
        im.DrawList_PathArcTo(DL, x, y, rad, A0, A0 + 1.5 * math.pi * v, 32)
        im.DrawList_PathStroke(DL, clr, nil, th)
    end
end
local function knob(key, cx, cy, rad, th, clr, label)
    local p = D:Idx(key)
    if p then D:PrmKnob(p, cx, cy, rad, label) end
    ring(key, cx, cy, rad, th, clr, BG)
end

-- power + output ring
local on = D:On('en')
local clicked = D:Btn('pwr', 262, 9, 10, 13)
if clicked then D:Set('en', on and 0 or 1) end
D:Rect(262, 9, 10, 13, BLUE, 2, on, 1.2)
local gc = on and BG or BLUE
im.DrawList_AddCircle(DL, X + 267, Y + 16, 2.5, gc, 0, 1)
D:Line(267, 11.5, 267, 15, gc, 1)
knob('gain', 248, 15, 6, 2, BLUE, 'Output Gain')

-- Zekete section
D:Rect(29, 46, 142, 162, 0x10203055, 4, true)
knob('zdw', 48, 58, 6, 2, BLUE, 'Dry/Wet')
D:Text(100, 49, BLUE, 'Zekete', 16, 'c', true)
D:Line(44, 69, 156, 69, BLUE, 1)
D:Choice('ztype', 44, 78, 112, { h = 16, accent = BLUE })

-- amount slider
local zp = D:Idx('zek')
if zp then D:PrmSlider(zp, 43, 102, 114, 12, 'Zekete') end
local zv = D:Get('zek') or 0
D:Rect(43, 106.5, 114, 3, 0x1A1A1CFF, 1.5, true)
D:Rect(43, 106.5, 114 * zv, 3, BLUE, 1.5, true)
D:Rect(43 + 114 * zv - 1.5, 103, 3, 10, BLUE, 1, true)

-- transfer curve
local L, T, R, B = D:Panel(29, 122, 142, 84)
D:Rect(29, 122, 142, 84, BLUE, 4, false, 1)
local mx, my = (L + R) * 0.5, (T + B) * 0.5
im.DrawList_AddLine(DL, mx, T + 1, mx, B - 1, 0x3A3D40FF, 1)
im.DrawList_AddLine(DL, L + 1, my, R - 1, my, 0x3A3D40FF, 1)
local function tanh(x)
    if x > 10 then x = 10 elseif x < -10 then x = -10 end
    local e = math.exp(2 * x)
    return (e - 1) / (e + 1)
end
local function clamp(v) if v > 1 then return 1 elseif v < -1 then return -1 end return v end
local t = math.floor((D:Get('ztype') or 0) * 5 + 0.5) + 1
local a = zv
local k = 1 + 7 * a
local function f(x)
    if t == 1 then return tanh(x * k)
    elseif t == 2 then return clamp(x * k)
    elseif t == 3 then return clamp(0.6 * x + (0.15 + 0.25 * a) * math.sin(x * 14))
    elseif t == 4 then return math.sin(x * (1 + a * 5) * math.pi * 0.5)
    elseif t == 5 then return clamp((tanh(k * x + 0.5) - tanh(0.5)) / (1 - tanh(0.5)) * 0.8)
    else local n = 2 + math.floor(a * 6); return clamp(math.floor(x * n + 0.5) / n) end
end
local N = 48
for i = 0, N do
    local x = -1 + 2 * i / N
    im.DrawList_PathLineTo(DL, L + (R - L) * i / N, my - f(x) * (B - T) * 0.42)
end
im.DrawList_PathStroke(DL, BLUE, nil, 1.8)

-- Le Ottz / Le Fonz: right column, each knob in its own box
local function big(key, label, top, fill)
    D:Rect(183, top, 82, 78, fill, 4, true)
    D:Text(224, top + 5, PURP, label, 14, 'c', true)
    knob(key, 224, top + 48, 18, 3, PURP, label)
    D:Text(224, top + 42, PURP, string.format('%d', math.floor((D:Val(key) or 0) + 0.5)), 12, 'c')
end
big('ottz', 'Le Ottz', 46, 0x2E1C6A66)
big('fonz', 'Le Fonz', 130, 0x2A126066)

D:End()
