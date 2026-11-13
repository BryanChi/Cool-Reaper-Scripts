-- Eventide H910 Harmonizer (UAD): rack panel knobs, delay buttons, pitch display, mixer, envelope follower, keyboard.
local SFX = require('src.Functions.Stock FX UI')
local D = SFX.Begin({ Title = 'H910 Harmonizer', W = 568, Accent = SFX.ACCENT.Pitch,
  Params = { inp = { 'Input Level', idx = 0 }, fb = { 'Feedback', idx = 1 }, man = { 'Manual', idx = 2 }, anti = { 'Anti-Feedback', idx = 3 }, dly = { 'Delay Only', idx = 4 }, mdt = { 'Main Delay Time', idx = 5 }, o2t = { 'Output2 Delay T', idx = 6 }, psel = { 'Pitch Control S', idx = 7 }, mix = { 'Mix', idx = 8 }, main = { 'Main Level', idx = 9 }, o2 = { 'Output2 Level', idx = 10 }, att = { 'Attack', idx = 11 }, rel = { 'Release', idx = 12 }, sens = { 'Sensitivity', idx = 13 }, hold = { 'Glide Hold', idx = 14 }, glide = { 'Glide Time', idx = 15 }, kb = { 'Keyboard', idx = 16 }, line = { 'Line', idx = 17 }, pwr = { 'Power', idx = 18 } } })
if not D then return end
local DL = D.DL
local W = 568
local WHITE, RED, REDOFF = 0xE6E6E6FF, 0xFF2A1AFF, 0x4A0F0CFF
local CREAM, CREAMLIT, KN = 0xBDB5A3FF, 0xFFF1CCFF, 0xDADADAFF

D:Rect(0, 0, W, 214, 0x1D1D1DFF, 0, true)
D:Rect(0, 0, W, 107, 0x2A2A2AFF, 0, true)
D:Rect(0, 106, W, 3, 0x0A0A0AFF, 0, true)
D:Rect(0, 109, 8, 105, 0x9C5C20FF, 0, true)
D:Rect(W - 8, 109, 8, 105, 0x9C5C20FF, 0, true)

local function Screw(x, y)
  im.DrawList_AddCircleFilled(DL, D.X + x, D.Y + y, 3.5, 0x111111FF)
  im.DrawList_AddCircle(DL, D.X + x, D.Y + y, 3.5, 0x666666FF, 0, 1)
  im.DrawList_AddLine(DL, D.X + x - 2, D.Y + y, D.X + x + 2, D.Y + y, 0x777777FF, 1)
end
Screw(32, 18) Screw(32, 82) Screw(536, 18) Screw(536, 82)

local function Led(x, y, rad, on)
  if on then im.DrawList_AddCircleFilled(DL, D.X + x, D.Y + y, rad + 2, SFX.A(RED, 0.25)) end
  im.DrawList_AddCircleFilled(DL, D.X + x, D.Y + y, rad, on and RED or REDOFF)
end
local function T(x, y, txt, al, bold) D:Text(x, y, WHITE, txt, 8, al, bold) end
local function Box(x, y, w, h) D:Rect(x, y, w, h, WHITE, 1, false, 1.5) end
local function PBtn(id, x, y, w, h, lit)
  local c, hv = D:Btn(id, x, y, w, h)
  D:Rect(x, y, w, h, lit and CREAMLIT or CREAM, 1.5, true)
  D:Rect(x, y, w, h, hv and WHITE or 0x00000066, 1.5, false, 1)
  return c
end

-- left and right branding
D:Text(37, 36, WHITE, 'MODEL', 12, 'c', true)
D:Text(37, 51, WHITE, 'H 910', 9, 'c', true)
D:Text(526, 36, WHITE, 'EVENTIDE', 10, 'c', true)
D:Text(526, 50, WHITE, 'CLOCKWORKS', 8, 'c', true)

-- knobs
Box(74, 7, 65, 63)
D:Knob('inp', 106, 38, 12, 'INPUT LEVEL', { unit = 'dB', accent = KN })
Box(160, 7, 65, 63)
D:Knob('fb', 192, 38, 12, 'FEEDBACK', { accent = KN })
Box(321, 7, 75, 63)
D:Knob('man', 358, 38, 12, 'MANUAL', { accent = KN })
T(326, 58, '.5')
T(391, 58, '2', 'r')
Box(416, 7, 73, 63)
D:Knob('anti', 452, 38, 12, 'ANTI-FEEDBACK', { accent = KN })

-- pitch ratio display
D:Rect(230, 8, 87, 61, 0x101010FF, 3, true)
D:Rect(230, 8, 87, 61, 0x666666FF, 3, false, 1.5)
D:Text(273, 12, WHITE, 'HARMONIZER', 9, 'c', true)
D:Rect(236, 26, 75, 28, 0x1E0606FF, 2, true)
local ps = math.floor(D:Get('psel') * 3 + 0.5)
local kbi = math.floor(D:Get('kb') * 25 + 0.5)
local rt = D:Val('man') or 1
if ps == 2 and kbi > 0 then rt = 0.5 * 2 ^ ((kbi - 1) / 12) end
local function Digits(cx, y, txt, clr)
  local tw = 0
  for i = 1, #txt do tw = tw + (string.sub(txt, i, i) == '.' and 7 or 17) end
  local x = cx - tw / 2
  for i = 1, #txt do
    local ch = string.sub(txt, i, i)
    im.DrawList_AddTextEx(DL, Font_SemiBold_16, 26, D.X + x + (ch == '.' and 1 or 0), D.Y + y, clr, ch)
    x = x + (ch == '.' and 7 or 17)
  end
end
Digits(273, 27, '8.88', 0x3A0A08FF)
Digits(273, 27, string.format('%.2f', rt), RED)
D:Text(273, 58, WHITE, 'PITCH RATIO', 8, 'c', true)

-- button row
T(50, 73, 'LINE', 'c', true)
local lineOn = D:Get('line') > 0.5
if PBtn('line', 40, 83, 20, 11, lineOn) then D:Set('line', lineOn and 0 or 1) end
Led(68, 88, 3, lineOn)
T(68, 97, 'IN', 'c', true)

local dOn = D:Get('dly') > 0.5
Led(97, 88, 2.5, dOn)
if PBtn('dly', 105, 83, 19, 11, dOn) then D:Set('dly', dOn and 0 or 1) end
T(113, 97, 'DELAY ONLY', 'c', true)

T(173, 73, [[ADD'L DELAY]], 'c', true)
local n = math.floor(D:Get('mdt') * 15 + 0.5)
local lab1 = { '7.5', '15', '30', '60' }
for i = 0, 3 do
  local bit = 2 ^ i
  local on = math.floor(n / bit) % 2 == 1
  local x = 134 + 20 * i
  if PBtn('md' .. i, x, 83, 18, 11, on) then
    n = on and (n - bit) or (n + bit)
    D:Set('mdt', n / 15)
  end
  T(x + 9, 97, lab1[i + 1], 'c', true)
end

T(273, 73, 'OUTPUT 2', 'c', true)
local vals = { 1, 2, 4, 4 }
local lab2 = { '7.5', '15', '30', '30' }
local function MaskSum(m)
  local s = 0
  for i = 0, 3 do if math.floor(m / 2 ^ i) % 2 == 1 then s = s + vals[i + 1] end end
  return s
end
local n2 = math.floor(D:Get('o2t') * 11 + 0.5)
if D.S.o2m == nil or MaskSum(D.S.o2m) ~= n2 then
  D.S.o2m = 0
  for m = 0, 15 do if MaskSum(m) == n2 then D.S.o2m = m break end end
end
for i = 0, 3 do
  local bit = 2 ^ i
  local on = math.floor(D.S.o2m / bit) % 2 == 1
  local x = 235 + 20 * i
  if PBtn('o2b' .. i, x, 83, 18, 11, on) then
    D.S.o2m = on and (D.S.o2m - bit) or (D.S.o2m + bit)
    D:Set('o2t', MaskSum(D.S.o2m) / 11)
  end
  T(x + 9, 97, lab2[i + 1], 'c', true)
end

Led(343, 88, 3, ps > 0)
local pl = { 'MAN', 'A-F', 'KYBD', 'ENV' }
for i = 0, 3 do
  local x = 351 + 22 * i
  if PBtn('ps' .. i, x, 83, 21, 11, ps == i) then D:Set('psel', i / 3) end
  D:Text(x + 10.5, 84, 0x222222FF, pl[i + 1], 8, 'c', true)
end
T(395, 97, 'PITCH CONTROL SELECT', 'c', true)

T(515, 73, 'POWER', 'c', true)
local pOn = D:Get('pwr') > 0.5
Led(498, 88, 3, pOn)
if PBtn('pwr', 506, 83, 20, 11, pOn) then D:Set('pwr', pOn and 0 or 1) end
T(498, 97, 'ON', 'c', true)

-- mixer
T(34, 119, 'MIX', 'c', true)
T(61, 119, 'MAIN', 'c', true)
T(89, 119, 'OUT 2', 'c', true)
D:Fader('mix', 34, 141, 54, '', { unit = '%', accent = KN })
D:Fader('main', 61, 141, 54, '', { unit = 'dB', accent = KN })
D:Fader('o2', 89, 141, 54, '', { unit = 'dB', accent = KN })

-- envelope follower
T(198, 119, 'ENVELOPE FOLLOWER', 'c', true)
Box(115, 133, 165, 61)
D:Knob('att', 141, 163, 11, 'ATTACK', { accent = KN })
D:Knob('rel', 193, 163, 11, 'RELEASE', { accent = KN })
D:Knob('sens', 245, 163, 11, 'SENSITIVITY', { accent = KN })
D:Text(198, 199, WHITE, 'EVENTIDE   HK 941', 9, 'c', true)

-- glide and hold
T(288, 119, 'GLIDE', nil, true)
D:Line(316, 123, 326, 123, WHITE, 1)
T(328, 119, 'HOLD', nil, true)
local hOn = D:Get('hold') > 0.5
if PBtn('hold', 352, 117, 18, 11, hOn) then D:Set('hold', hOn and 0 or 1) end
Led(380, 122, 2.5, hOn)
D:Fader('glide', 301, 141, 54, '', { accent = KN })

-- keyboard
local KX, KY, KW, KH = 318, 137, 224, 75
D:Rect(KX - 2, KY - 2, KW + 4, KH + 4, 0x0C0C0CFF, 1, true)
local ww = KW / 15
local semis = { 0, 2, 4, 5, 7, 9, 11 }
local function Pick(idx)
  D:Set('kb', (kbi == idx and 0 or idx) / 25)
end
for w = 0, 14 do
  local idx = math.floor(w / 7) * 12 + semis[w % 7 + 1] + 1
  local x = KX + w * ww
  local c, hv = D:Btn('wk' .. w, x, KY, ww, KH)
  if c then Pick(idx) end
  D:Rect(x, KY, ww, KH, kbi == idx and 0xF2B8A8FF or (hv and 0xFFFFF4FF or 0xF4F0E4FF), 0, true)
  D:Rect(x, KY, ww, KH, 0x3A3A3AFF, 0, false, 1)
end
local bw = ww * 0.62
for w = 0, 13 do
  local nt = w % 7
  if nt == 0 or nt == 1 or nt == 3 or nt == 4 or nt == 5 then
    local idx = math.floor(w / 7) * 12 + semis[nt + 1] + 2
    local x = KX + (w + 1) * ww - bw / 2
    local c, hv = D:Btn('bk' .. w, x, KY, bw, KH * 0.62)
    if c then Pick(idx) end
    D:Rect(x, KY, bw, KH * 0.62, kbi == idx and 0x8A2E22FF or (hv and 0x333333FF or 0x161616FF), 1, true)
    D:Rect(x, KY, bw, KH * 0.62, 0x000000FF, 1, false, 1)
  end
end
D:End()