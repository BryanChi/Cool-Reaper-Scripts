-- Cymatics Deja Vu: loop buttons, gradient waveform display with power, fade/smooth/mix knobs, mode buttons, band range
local SFX = require('src.Functions.Stock FX UI')
local D = SFX.Begin({ Title = 'Deja Vu', W = 411, H = 240, Accent = SFX.ACCENT.Time,
  Params = { smooth = { 'Smooth', idx = 0 }, mix = { 'Mix', idx = 1 }, loop = { 'Loop', idx = 2 }, mode = { 'Mode', idx = 3 },
    fin = { 'Fade In', idx = 4 }, fout = { 'Fade Out', idx = 5 }, lo = { 'Split Low', idx = 6 }, hi = { 'Split High', idx = 7 },
    solo = { 'Band - Solo', idx = 8 }, power = { 'Power', idx = 9 } } })
if not D then return end
local DL = D.DL
local S = 0.34
local function X(v) return (v - 355) * S end
local function Y(v) return (v - 190) * S end
local ACC, TXT, DIM, EDGE = 0xD4685CFF, 0x3C404CFF, 0x7C8294FF, 0x9AA1B1FF
local W, H = 411, 240
local PI = math.pi

D:Rect(0, 0, W, H, 0xBCC2CFFF, 0, true)
D:Rect(X(423), Y(237), 1076 * S, 627 * S, 0xA0A7B7FF, 8, false, 1)

-- loop buttons
local labs = { '1/16', '1/8T', '1/8', '1/4', '1/2', '1 Bar', '2 Bars', '4 Bars', '8 Bars' }
local bx, by, bw, bh = X(479), Y(279), (1443 - 479) * S / 9, (334 - 279) * S
D:Rect(bx, by, bw * 9, bh, 0xC4C9D5FF, 2, true)
local lv = D:Get('loop')
for i = 0, 8 do
  local x = bx + i * bw
  local on = math.abs(lv - i / 8) < 0.05
  if D:Btn('lp' .. i, x, by, bw, bh) then D:Set('loop', i / 8) end
  if on then D:Rect(x, by, bw, bh, ACC, 2, true) else D:Rect(x, by, bw, bh, EDGE, 0, false, 1) end
  D:Text(x + bw / 2, by + 6, on and 0x40201FFF or 0x8A90A2FF, labs[i + 1], 8, 'c')
end
D:Text(W / 2, Y(363) - 5, TXT, 'LOOP', 10, 'c')

-- display
local L, T, R, B = D.X + X(647), D.Y + Y(397), D.X + X(1275), D.Y + Y(634)
local mid = (T + B) / 2
im.DrawList_AddRectFilledMultiColor(DL, L, T, R, mid, 0x8C40E6FF, 0x8C40E6FF, 0xE862A8FF, 0xE862A8FF)
im.DrawList_AddRectFilledMultiColor(DL, L, mid, R, B, 0xE862A8FF, 0xE862A8FF, 0xEC8470FF, 0xEC8470FF)
-- the track's input (pre-FX) waveform from FXD Macros, 60 columns a second, newest on the right;
-- until it has one, the track's peak history (D.S is this FX's own)
local n = math.max(1, math.floor((R - L) / 2))
local function dB01(pk) return pk > 0 and SFX.Clamp((20 * math.log(pk, 10) + 60) / 60, 0, 1) or 0 end
local w = D:InputWave(n)
local wf = D.S.wf
if not wf or wf.n ~= n then
  wf = { n = n, head = 0, t = D.NOW }
  for i = 1, n do wf[i] = 0 end
  D.S.wf = wf
end
if not w then
  local steps = math.min(n, math.floor((D.NOW - wf.t) * 60))
  if steps > 0 then
    local h = dB01(math.max(r.Track_GetPeakInfo(LT_Track, 0) or 0, r.Track_GetPeakInfo(LT_Track, 1) or 0))
    for _ = 1, steps do
      wf.head = wf.head % n + 1
      wf[wf.head] = h
    end
    wf.t = wf.t + steps / 60
  end
end
if D.NOW - wf.t > 1 then wf.t = D.NOW end
local cy = mid
im.DrawList_PushClipRect(DL, L, T, R, B, true)
for i = 0, n - 1 do
  local x = L + i * 2 + 1
  local v = w and dB01(tonumber(w[i + 1]) or 0) or wf[(wf.head + i) % n + 1]
  local amp = math.max(0.5, (B - T) * 0.45 * v)
  im.DrawList_AddLine(DL, x, cy - amp, x, cy + amp, 0x9E3068A0, 1.6)
  if amp > 1 then
    im.DrawList_AddLine(DL, x, cy - amp, x, cy - amp + 1, 0x6A1A44FF, 1.6)
    im.DrawList_AddLine(DL, x, cy + amp - 1, x, cy + amp, 0x6A1A44FF, 1.6)
  end
end
im.DrawList_PopClipRect(DL)
im.DrawList_AddRect(DL, L, T, R, B, 0x8A7FA8FF, 2, 0, 1)

-- power
local pcx, pcy = X(957), Y(611)
local pon = D:Get('power') > 0.5
if D:Btn('pw', pcx - 9, pcy - 9, 18, 18) then D:Set('power', pon and 0 or 1) end
local pc = pon and 0xFFFFFFFF or 0xFFFFFF80
local px, py = D.X + pcx, D.Y + pcy
im.DrawList_PathArcTo(DL, px, py, 6, -PI / 2 + 0.7, PI * 1.5 - 0.7, 16)
im.DrawList_PathStroke(DL, pc, nil, 2)
im.DrawList_AddLine(DL, px, py - 7, px, py - 1, pc, 2)

-- knobs
local function Knob(key, cx, cy, rad, label)
  D:PrmKnob(D:Idx(key), cx, cy, rad + 2, label)
  local x, y = D.X + cx, D.Y + cy
  local v = SFX.Clamp(D:Get(key), 0, 1)
  im.DrawList_AddCircleFilled(DL, x + 1, y + rad * 0.28, rad * 1.06, 0x5A627A55, 0)
  im.DrawList_AddCircleFilled(DL, x, y, rad, 0xC8CDD8FF, 0)
  im.DrawList_AddCircle(DL, x, y, rad, 0xA3AABAFF, 0, 1)
  for i = 0, 6 do
    local a = PI * 0.75 + PI * 1.5 * i / 6
    im.DrawList_AddLine(DL, x + math.cos(a) * rad * 1.18, y + math.sin(a) * rad * 1.18, x + math.cos(a) * rad * 1.32, y + math.sin(a) * rad * 1.32, 0x8B91A0FF, 1)
  end
  local a = PI * 0.75 + PI * 1.5 * v
  im.DrawList_AddLine(DL, x + math.cos(a) * rad * 0.5, y + math.sin(a) * rad * 0.5, x + math.cos(a) * rad * 0.85, y + math.sin(a) * rad * 0.85, 0x2A2D36FF, 2.5)
end
local KR = 52 * S
Knob('fin', X(535), Y(502), KR, 'Fade In')
Knob('fout', X(1387), Y(502), KR, 'Fade Out')
Knob('smooth', X(605), Y(731), KR, 'Smooth')
Knob('mix', X(1317), Y(731), KR, 'Mix')

D:Text(X(535) - 22, Y(567) - 3, DIM, 'INST', 8, 'c')
D:Text(X(535) + 20, Y(567) - 3, DIM, '16 BARS', 8, 'c')
D:Text(X(534), Y(600) - 5, TXT, 'FADE IN', 10, 'c')
D:Text(X(1387) - 22, Y(567) - 3, DIM, 'INST', 8, 'c')
D:Text(X(1387) + 20, Y(567) - 3, DIM, '16 BARS', 8, 'c')
D:Text(X(1387), Y(600) - 5, TXT, 'FADE OUT', 10, 'c')
D:Text(X(604), Y(822) - 5, TXT, 'SMOOTH', 10, 'c')
D:Text(X(1317), Y(822) - 5, TXT, 'MIX', 10, 'c')

-- mode (values 1.5x / 2x / 4x, looked up from the plugin's own text)
local mx, my, mw, mh = X(755), Y(677), (1166 - 755) * S, (732 - 677) * S
local segW = mw / 3
local ml = { '1.5x', '2x', '4x' }
local mt = { 1.5, 2, 4 }
local mfb = { 0, 0.2, 1 }
local function modeNorm(i)
  local t = mt[i]
  local ch = D:Choices('mode')
  if ch then
    for _, c in ipairs(ch) do
      local lab = c[1] or c.label
      local nv = c[2] or c.norm
      local num = lab and SFX.Num(tostring(lab))
      if num and nv and math.abs(num - t) < 0.01 then return nv end
    end
  end
  local nn = D:NormFor('mode', t)
  if nn then return nn end
  return mfb[i]
end
local mv = D:Get('mode')
local mval = D:Val('mode')
D:Rect(mx, my, mw, mh, 0xC4C9D5FF, 2, true)
for i = 1, 3 do
  local x = mx + (i - 1) * segW
  local on
  if mval then on = math.abs(mval - mt[i]) < 0.01 else on = math.abs(mv - mfb[i]) < 0.1 end
  if D:Btn('md' .. i, x, my, segW, mh) then D:Set('mode', modeNorm(i)) end
  if on then D:Rect(x, my, segW, mh, ACC, 2, true) else D:Rect(x, my, segW, mh, EDGE, 0, false, 1) end
  D:Text(x + segW / 2, my + 6, on and 0x40201FFF or 0x8A90A2FF, ml[i], 8, 'c')
end
D:Text(W / 2, Y(760) - 5, TXT, 'MODE', 10, 'c')

-- band range
local x0, x1, yb = X(755), X(1166), Y(798)
local lo, hi = D:Get('lo'), D:Get('hi')
D:Rect(x0, yb - 2, x1 - x0, 5, 0xA8AEBDFF, 2, true)
D:Rect(x0 + (x1 - x0) * lo, yb - 2, (x1 - x0) * math.max(hi - lo, 0), 5, 0xF2F4F8FF, 2, true)
local _, _, actL = D:Btn('bl', x0 + (x1 - x0) * lo - 6, yb - 8, 12, 16)
if actL then
  local nv = SFX.Clamp((im.GetMousePos(ctx) - D.X - x0) / (x1 - x0), 0, 1)
  D:Set('lo', math.min(nv, hi))
end
local _, _, actH = D:Btn('bh', x0 + (x1 - x0) * hi - 6, yb - 8, 12, 16)
if actH then
  local nv = SFX.Clamp((im.GetMousePos(ctx) - D.X - x0) / (x1 - x0), 0, 1)
  D:Set('hi', math.max(nv, lo))
end
for _, v in ipairs({ lo, hi }) do
  local hx = x0 + (x1 - x0) * v
  D:Rect(hx - 3, yb - 6, 6, 12, 0xE6E9F0FF, 2, true)
  D:Rect(hx - 3, yb - 6, 6, 12, EDGE, 2, false, 1)
end
D:Text(X(793), Y(827) - 4, DIM, 'LOW CUT', 8, 'c')
D:Text(X(1118), Y(827) - 4, DIM, 'HIGH CUT', 8, 'c')
D:Text(X(960), Y(829) - 5, TXT, 'BAND', 10, 'c')

-- solo icon
local son = D:Get('solo') > 0.5
if D:Btn('solo', X(1002) - 8, Y(828) - 8, 16, 16) then D:Set('solo', son and 0 or 1) end
local sc = son and ACC or 0x8A90A2FF
local sx, sy = D.X + X(1002), D.Y + Y(828)
im.DrawList_AddCircle(DL, sx, sy, 4, sc, 0, 1.5)
im.DrawList_AddLine(DL, sx - 4, sy + 4, sx + 4, sy - 4, sc, 1.5)

D:End()
