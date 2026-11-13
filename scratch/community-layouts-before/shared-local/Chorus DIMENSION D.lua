-- Chorus DIMENSION-D (Arturia): mode keys, stereo switch, level meter, power, oscillator shape keys, Dynamic Color / Width / Mix knobs.
local SFX = require('src.Functions.Stock FX UI')
local D = SFX.Begin({ Title = 'Chorus DIMENSION-D', W = 500, Accent = SFX.ACCENT.Time,
  Params = { pwr = { 'On/Off', idx = 0 }, stereo = { 'Stereo Mode', idx = 1 }, mode = { 'Dimension Mode', idx = 2 }, m4 = { 'Dimension Mode 4', idx = 3 }, mix = { 'Output Mix', idx = 4 }, lfo = { 'LFO Shape', idx = 5 }, color = { 'Dynamic Color', idx = 6 }, width = { 'Width', idx = 7 } } })
if not D then return end
local A = SFX.A
local DL = D.DL
local OR, TX, RED, CREAM = 0xE9843CFF, 0xE4E0D8FF, 0xD8412CFF, 0xEDE6CFFF
local DIM = 0x9A978FFF
D:Rect(0, 0, 500, 216, 0x14110FFF, 0, true)
D:Rect(0, 0, 500, 18, 0x0D0D0FFF, 0, true)
D:Rect(4, 20, 492, 85, 0x1F1F21FF, 3, true)
D:Rect(4, 20, 492, 85, 0x3A3A3DFF, 3, false, 1)
D:Rect(4, 108, 492, 106, 0x1F1F21FF, 3, true)
D:Rect(4, 108, 492, 106, 0x3A3A3DFF, 3, false, 1)
im.DrawList_AddCircle(DL, D.X + 14, D.Y + 9, 6, OR, 0, 1.5)
D:Text(13, 5, OR, 'A', 8, nil, true)
D:Text(26, 4, OR, 'CHORUS', 10)
D:Text(26 + SFX.TextW('CHORUS ', 10), 4, RED, 'DIMENSION-D', 10, nil, true)
im.SetCursorScreenPos(ctx, D.X + 300, D.Y + 1)
Presets.Button(120, 16)
local LN = A(0xE8E4DCFF, 0.55)
for _, x in ipairs({ 90, 323, 395 }) do D:Line(x, 24, x, 102, LN, 1) end
for _, x in ipairs({ 90, 237, 323, 395 }) do D:Line(x, 112, x, 211, LN, 1) end
local function key(id, x, y, w, h, sel, selClr, offClr)
  local clk = D:Btn(id, x, y, w, h)
  local dy = sel and 1 or 0
  D:Rect(x, y, w, h, 0x050505FF, 2, true)
  D:Rect(x + 1, y + 1 + dy * 2, w - 2, h - 3 - dy * 2, sel and selClr or offClr, 2, true)
  return clk
end
-- MODE
D:Text(47, 26, TX, 'MODE', 9, 'c')
D:Text(47, 38, TX, 'MONO', 8, 'c')
D:Text(47, 48, TX, 'STEREO', 8, 'c')
local mono = D:Get('stereo') > 0.5
if D:Btn('stsw', 33, 62, 28, 20) then D:Set('stereo', mono and 0 or 1) end
D:Rect(33, 62, 28, 20, 0x0A0A0BFF, 2, true)
D:Rect(33, 62, 28, 20, 0x55555AFF, 2, false, 1)
D:Rect(36, mono and 64 or 73, 22, 6, 0x3A3A3EFF, 1, true)
-- DIMENSION MODE
D:Text(205, 26, TX, 'DIMENSION MODE', 9, 'c')
local m = math.floor(D:Get('mode') * 3 + 0.5)
for i = 0, 3 do
  D:Text(141 + i * 32, 47, TX, tostring(i), 8, 'c')
  if key('dm' .. i, 127 + i * 32, 58, 28, 26, m == i, RED, CREAM) then D:Set('mode', i / 3) end
end
local on4 = D:Get('m4') > 0.5
D:Text(269, 47, TX, '4', 8, 'c')
if key('dm4', 255, 58, 28, 26, on4, RED, 0x9C9A92FF) then D:Set('m4', on4 and 0 or 1) end
-- OUTPUT LEVEL
D:Text(359, 26, TX, 'OUTPUT LEVEL', 9, 'c')
local pk = 0
pcall(function()
  local a = r.Track_GetPeakInfo(LT_Track, 0)
  local b = r.Track_GetPeakInfo(LT_Track, 1)
  pk = math.max(a or 0, b or 0)
end)
local db = pk > 0.00003 and 20 * math.log(pk, 10) or -90
local f = SFX.Clamp((db + 30) / 35, 0, 1)
local S = D.S
S.lv = math.max(f, (S.lv or 0) - 0.02)
D:Rect(346, 42, 13, 54, 0x2A0C0AFF, 1, true)
D:Rect(346, 42, 13, 54, 0x55302CFF, 1, false, 1)
for i = 1, 18 do
  local lit = (i / 18) <= S.lv
  D:Rect(348, 96 - i * 3, 9, 2, lit and 0xE0392BFF or 0x4A1512FF, 0, true)
end
for _, t in ipairs({ { '+5', 5 }, { '0dB', 0 }, { '-10', -10 }, { '-20', -20 }, { '-30', -30 } }) do
  D:Text(364, 96 - (t[2] + 30) * 54 / 35 - 4, TX, t[1], 8)
end
-- POWER
im.DrawList_AddCircle(DL, D.X + 445, D.Y + 33, 7, TX, 0, 1.2)
D:Text(445, 29, TX, 'A', 8, 'c', true)
D:Text(445, 43, RED, 'Chorus DIMENSION-D', 8, 'c', true)
D:Text(445, 52, DIM, 'made in Grenoble', 8, 'c')
local active = D:Get('pwr') < 0.5
im.DrawList_AddCircleFilled(DL, D.X + 445, D.Y + 66, 3, active and 0xFF2A1CFF or 0x4A1512FF)
D:Text(445, 72, TX, 'POWER', 9, 'c')
if D:Btn('pwrb', 433, 84, 24, 16) then D:Set('pwr', active and 1 or 0) end
D:Rect(433, 84, 24, 16, 0x0A0A0BFF, 2, true)
D:Rect(433, 84, 24, 16, 0x55555AFF, 2, false, 1)
-- ADVANCED
D:Text(47, 146, TX, 'DIMENSION', 8, 'c')
D:Text(47, 157, RED, 'ADVANCED', 8, 'c')
D:Text(47, 168, TX, 'CONTROLS', 8, 'c')
D:Text(163, 113, TX, 'OSCILLATOR SHAPE', 9, 'c')
local lf = math.floor(D:Get('lfo') * 4 + 0.5)
local icons = {
  {},
  { { -7, 0 }, { -5, -2 }, { -3, -3 }, { -1, -2 }, { 0, 0 }, { 1, 2 }, { 3, 3 }, { 5, 2 }, { 7, 0 } },
  { { -6, 3 }, { 4, -3 }, { 4, 3 } },
  { { -7, 2 }, { -4, 2 }, { -4, -3 }, { 0, -3 }, { 0, 1 }, { 3, 1 }, { 3, -3 }, { 7, -3 } },
  { { -7, 0 }, { -4, -3 }, { -1, -3 }, { 1, 2 }, { 4, 2 }, { 7, -1 } },
}
for i = 0, 4 do
  local x = 98 + i * 27
  local cx = x + 12
  if i == 0 then
    D:Text(cx, 136, TX, 'DEFAULT', 8, 'c')
  else
    local p = icons[i + 1]
    for k = 1, #p - 1 do D:Line(cx + p[k][1], 141 + p[k][2], cx + p[k + 1][1], 141 + p[k + 1][2], TX, 1) end
  end
  if key('lfo' .. i, x, 150, 24, 24, lf == i, 0x8E8B84FF, CREAM) then D:Set('lfo', i / 4) end
end
-- DYNAMIC COLOR
D:Text(280, 113, TX, 'DYNAMIC COLOR', 9, 'c')
local names = { 'LF SAT 2', 'LF SAT 1', 'DEFAULT', 'SMOOTH' }
for i, n in ipairs(names) do
  local y = 128 + (i - 1) * 13
  D:Text(272, y, TX, n, 8, 'r')
  D:Line(274, y + 4, 282, 165 - (2.5 - i) * 3, TX, 1)
end
D:Knob('color', 296, 165, 'M', '', { accent = OR })
-- WIDTH
D:Text(359, 113, TX, 'WIDTH', 9, 'c')
D:Text(359, 126, TX, 'STEREO', 8, 'c')
D:Text(334, 170, TX, 'M', 8, 'c')
D:Text(384, 170, TX, 'S', 8, 'c')
D:Knob('width', 359, 165, 'M', '', { accent = OR })
-- MIX
D:Text(445, 113, TX, 'MIX', 9, 'c')
D:Text(412, 170, TX, 'DRY', 8, 'c')
D:Text(478, 170, TX, 'WET', 8, 'c')
D:Knob('mix', 445, 165, 'M', '', { accent = OR })
D:End()