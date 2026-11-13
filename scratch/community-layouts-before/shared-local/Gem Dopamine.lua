-- Gem Dopamine (Overloud): compact two-rack layout (361 white, 180 black), the unselected model's rack is dimmed and disabled, with Dry/Wet/Comp/Level knobs, a compact A-Type display and an LED meter. 361/180 mapping to Model fixed.
local SFX = require('src.Functions.Stock FX UI')
local D = SFX.Begin({ Title = 'Gem Dopamine', W = 520, Accent = SFX.ACCENT.Dynamics, Params = { pwr = { 'Power', idx = 0 }, model = { 'Model', idx = 1 }, dry = { 'Dry', idx = 2 }, wet = { 'Wet', idx = 3 }, vm = { 'Vocal Mod', idx = 4 }, comp = { 'Compression', idx = 5 }, level = { 'Level', idx = 6 } } })
if not D then return end
local DL = D.DL
local W = 520
local RH = 93
local T1, T2 = 24, 120
local RL, RR = 26, 494

D:Rect(0, 0, W, 216, 0x0B0B0BFF, 0, true)

-- header: power + preset pill
local pOn = D:Get('pwr') > 0.5
if D:Btn('pwr', 0, 0, 22, 22) then D:Set('pwr', pOn and 0 or 1) end
local pbg = pOn and 0xE8523AFF or 0x2A2A2AFF
local pic = pOn and 0x2A0C08FF or 0x8A8A8AFF
D:Rect(0, 0, 22, 22, pbg, 0, true)
im.DrawList_AddCircle(DL, D.X + 11, D.Y + 11.5, 6, pic, 0, 1.8)
im.DrawList_AddRectFilled(DL, D.X + 9, D.Y + 3, D.X + 13, D.Y + 9, pbg)
im.DrawList_AddLine(DL, D.X + 11, D.Y + 4.5, D.X + 11, D.Y + 11.5, pic, 1.8)
if type(Presets) == 'table' then
    im.SetCursorScreenPos(ctx, D.X + 28, D.Y + 2)
    Presets.Button(240, 18)
end

-- racks
D:Rect(0, T1, W, RH, 0xB4B4B0FF, 0, true)
D:Rect(RL, T1, RR - RL, RH, 0xE6E6E2FF, 0, true)
D:Line(RL, T1, RL, T1 + RH, 0x80807CFF, 1)
D:Line(RR, T1, RR, T1 + RH, 0x80807CFF, 1)
D:Rect(0, T2, W, RH, 0x2A2827FF, 0, true)
D:Rect(RL, T2, RR - RL, RH, 0x1E1B1AFF, 0, true)
D:Line(RL, T2, RL, T2 + RH, 0x000000FF, 1)
D:Line(RR, T2, RR, T2 + RH, 0x000000FF, 1)

local function Screw(x, y, dark)
    local X, Y = D.X + x, D.Y + y
    im.DrawList_AddCircleFilled(DL, X, Y, 6, dark and 0x111010FF or 0x6E6E6AFF, 0)
    im.DrawList_AddCircle(DL, X, Y, 6, dark and 0x4A4745FF or 0x3A3A38FF, 0, 1)
    im.DrawList_AddCircleFilled(DL, X, Y, 3.5, dark and 0x2C2A28FF or 0x9A9A96FF, 0)
    im.DrawList_AddLine(DL, X - 2.5, Y - 2.5, X + 2.5, Y + 2.5, 0x0A0A0AFF, 1.4)
end
Screw(13, T1 + 18, false) Screw(13, T1 + RH - 18, false) Screw(507, T1 + 18, false) Screw(507, T1 + RH - 18, false)
Screw(13, T2 + 18, true) Screw(13, T2 + RH - 18, true) Screw(507, T2 + 18, true) Screw(507, T2 + RH - 18, true)

local function Knob(id, key, cx, cy, label, top, enabled)
    local kr = 16
    local x, y = D.X + cx, D.Y + cy
    local tick = top and 0x1A1A1AFF or 0xD8D8D4FF
    for i = 0, 10 do
        local a = math.rad(-135 + 27 * i)
        local s, c = math.sin(a), math.cos(a)
        local k2 = kr + ((i % 5 == 0) and 10 or 8)
        im.DrawList_AddLine(DL, x + s * (kr + 4), y - c * (kr + 4), x + s * k2, y - c * k2, tick, 1.2)
    end
    im.DrawList_AddCircleFilled(DL, x, y, kr + 1.5, top and 0x050505FF or 0x9A9A98FF, 0)
    im.DrawList_AddCircleFilled(DL, x, y, kr, top and 0x1C1C1CFF or 0xECECE8FF, 0)
    im.DrawList_AddCircleFilled(DL, x, y, kr - 4, top and 0x2C2C2CFF or 0xF8F8F6FF, 0)
    local v = D:Get(key)
    local a = math.rad(-135 + 270 * v)
    local s, c = math.sin(a), math.cos(a)
    im.DrawList_AddLine(DL, x + s * 5, y - c * 5, x + s * (kr - 2), y - c * (kr - 2), top and 0xD0D0D0FF or 0x1A1A1AFF, 2)
    local hovered, dragging = false, false
    if enabled then
        local _, hv, act = D:Btn(id, cx - kr - 6, cy - kr - 6, 2 * kr + 12, 2 * kr + 12)
        hovered, dragging = hv, act
        if act then
            local _, dy = im.GetMouseDelta(ctx)
            if dy and dy ~= 0 then D:Set(key, SFX.Clamp(D:Get(key) - dy / 160, 0, 1)) end
        end
    end
    local txt = (hovered or dragging) and D:Fmt(key) or label
    D:Text(cx, cy + kr + 12, top and 0x2A2A2AFF or 0xDADAD6FF, txt, 8, 'c', true)
end

local function ModelBtn(id, x, y, w, h, lit, on, off, target, enabled)
    if enabled then
        if D:Btn(id, x, y, w, h) then D:Set('model', target) end
    end
    D:Rect(x - 1, y - 1, w + 2, h + 2, 0x0C0C0CFF, 3, true)
    D:Rect(x + 2, y + 2, w - 4, h - 4, lit and on or off, 2, true)
    if lit then D:Rect(x + 3, y + 3, w - 6, (h - 6) / 2, 0xFFFFFF30, 2, true) end
end

-- Model 0 = 361, Model 1 = 180
local m361 = D:Get('model') < 0.5
local topOn = m361
local botOn = not m361

-- top (white) rack: 361
ModelBtn('m361a', 44, T1 + 17, 28, 27, m361, 0xF5B820FF, 0x7A5A10FF, 0, topOn)
ModelBtn('m180a', 44, T1 + 45, 28, 27, not m361, 0x2A55D0FF, 0x14245CFF, 1, topOn)
D:Text(80, T1 + 25, 0x333333FF, '361', 8, nil, true)
D:Text(80, T1 + 53, 0x333333FF, '180', 8, nil, true)
Knob('kd1', 'dry', 124, T1 + 44, 'DRY', true, topOn)
Knob('kw1', 'wet', 182, T1 + 44, 'WET', true, topOn)
Knob('kc1', 'comp', 240, T1 + 44, 'COMP', true, topOn)
Knob('kl1', 'level', 298, T1 + 44, 'LEVEL', true, topOn)

-- compact A-Type / Stressor display
local vm = D:Get('vm') > 0.5
local dx, dy = 334, T1 + 23
local dw = 154
local hv = false
if topOn then
    local c1, h1 = D:Btn('vmbtn', dx, dy, dw, 46)
    hv = h1
    if c1 then D:Set('vm', vm and 0 or 1) end
end
D:Rect(dx, dy, dw, 46, 0x121212FF, 8, true)
D:Rect(dx + 4, dy + 4, dw - 8, 38, hv and 0xDADAD6FF or 0xCFCFCCFF, 5, true)
D:Rect(dx + 8, dy + 10, 26, 20, 0x1A1A1AFF, 2, true)
D:Text(dx + 21, dy + 11, 0xF0F0F0FF, 'OVER', 8, 'c', true)
D:Text(dx + 21, dy + 20, 0xF0F0F0FF, 'LOUD', 8, 'c', true)
D:Rect(dx + 38, dy + 10, 20, 20, 0x1A1A1AFF, 3, true)
local gx, gy = D.X + dx + 48, D.Y + dy + 20
im.DrawList_AddLine(DL, gx, gy - 6, gx + 7, gy, 0xF0F0F0FF, 1.2)
im.DrawList_AddLine(DL, gx + 7, gy, gx, gy + 7, 0xF0F0F0FF, 1.2)
im.DrawList_AddLine(DL, gx, gy + 7, gx - 7, gy, 0xF0F0F0FF, 1.2)
im.DrawList_AddLine(DL, gx - 7, gy, gx, gy - 6, 0xF0F0F0FF, 1.2)
D:Text(dx + 64, dy + 6, 0x1A1A1AFF, vm and 'STRESSOR' or 'A-TYPE', 13, nil, true)
D:Text(dx + 64, dy + 22, 0x333333FF, vm and 'VOCAL' or 'NOISE REDUCTION', 8)
D:Text(dx + 64, dy + 31, 0x333333FF, 'MODULE', 8)

-- bottom (black) rack: 180
ModelBtn('m361b', 44, T2 + 17, 28, 27, m361, 0xE0642AFF, 0x7A3515FF, 0, botOn)
ModelBtn('m180b', 44, T2 + 45, 28, 27, not m361, 0x35B8F0FF, 0x1A5C78FF, 1, botOn)
D:Text(80, T2 + 25, 0xCCCCC8FF, '361', 8, nil, true)
D:Text(80, T2 + 53, 0xCCCCC8FF, '180', 8, nil, true)
Knob('kd2', 'dry', 134, T2 + 44, 'DRY', false, botOn)
Knob('kw2', 'wet', 200, T2 + 44, 'WET', false, botOn)
Knob('kl2', 'level', 266, T2 + 44, 'LEVEL', false, botOn)

D:Rect(334, T2 + 12, 28, 20, 0xE8E8E4FF, 2, false, 1.2)
D:Text(348, T2 + 13, 0xE8E8E4FF, 'OVER', 8, 'c', true)
D:Text(348, T2 + 22, 0xE8E8E4FF, 'LOUD', 8, 'c', true)
D:Rect(366, T2 + 12, 22, 20, 0xE8E8E4FF, 2, false, 1.2)
local hx, hy = D.X + 377, D.Y + T2 + 22
im.DrawList_AddQuadFilled(DL, hx, hy - 6, hx + 7, hy, hx, hy + 7, hx - 7, hy, 0xE8E8E4FF)

-- LED strip from the input level
local S = D.S
local n = 0
local okw, w = pcall(function() return D:InputWave(2) end)
if okw and type(w) == 'table' and #w > 0 then
    local v = w[#w]
    if type(v) == 'number' and v > 0 then n = SFX.Clamp((20 * math.log(v) / math.log(10) + 48) / 48, 0, 1) end
end
S.lvl = math.max(n, (S.lvl or 0) - 0.02)
local lit = math.floor(S.lvl * 36)
for i = 0, 35 do
    D:Rect(334 + i * 4, T2 + 52, 3, 7, i < lit and 0xFF4535FF or 0x6A1812FF, 0, true)
end

-- dim the rack of the model that is not selected
if not topOn then D:Rect(0, T1, W, RH, 0x000000B0, 0, true) end
if not botOn then D:Rect(0, T2, W, RH, 0x000000B0, 0, true) end
D:End()
