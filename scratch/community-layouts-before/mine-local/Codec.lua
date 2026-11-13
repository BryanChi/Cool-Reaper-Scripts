-- Codec (Lese): pixel level display with hover Crunch editor, loss mode buttons, Loss / Bitrate / Disorder and Bandwidth / Noise / Colour / Mix knobs.
local SFX = require('src.Functions.Stock FX UI')
local D = SFX.Begin({ Title = 'Codec', W = 290, Accent = SFX.ACCENT.Utility, Params = { bit = { 'Bitrate', idx = 0 }, loss = { 'Loss', idx = 1 }, mode = { 'Mode', idx = 2 }, bw = { 'Bandwidth', idx = 3 }, dis = { 'Packet Disorder', idx = 4 }, noise = { 'Noise Amount', idx = 5 }, col = { 'Noise Colour', idx = 6 }, cg = { 'Crunch Gain', idx = 7 }, cf = { 'Crunch Frequency', idx = 8 }, cw = { 'Crunch Width', idx = 9 }, mix = { 'Dry / Wet Mix', idx = 10 } } })
if not D then return end
local DL, W = D.DL, 290
local A = SFX.A
local BG, PAN, DARKBG = 0xCF929AFF, 0xDBA9AEFF, 0x2B0606FF
local INK, PINK, CREAM, MAR = 0x3A0A0EFF, 0xC4808AFF, 0xEBD3CCFF, 0x8A3347FF
D:Rect(0, 0, W, 216, BG, 6, true)
D:Rect(0, 0, W, 66, DARKBG, 8, true)
D:Text(W / 2, 5, CREAM, 'Cødec', 13, 'c', false)

-- pixel display of the input
local COLS, ROWS, STEP = 60, 9, 4
local wave = D:InputWave(COLS)
local x0, y0 = (W - COLS * STEP) / 2, 24
for c = 1, COLS do
  local lv = 0
  if wave and wave[c] and wave[c] > 0.0001 then
    lv = SFX.Clamp((8.685889 * math.log(wave[c]) + 60) / 60, 0, 1)
  end
  local k = math.floor(lv * 4.5)
  for rr = 0, ROWS - 1 do
    local px, py = D.X + x0 + (c - 1) * STEP, D.Y + y0 + rr * STEP
    if math.abs(rr - 4) <= k then
      im.DrawList_AddRectFilled(DL, px, py, px + 3, py + 3, CREAM)
    else
      im.DrawList_AddRectFilled(DL, px + 1, py + 1, px + 2, py + 2, A(CREAM, 0.18))
    end
  end
end

-- hover: Crunch editor
local hov = im.IsMouseHoveringRect(ctx, D.X, D.Y, D.X + W, D.Y + 66)
if hov then
  im.DrawList_AddRectFilled(DL, D.X, D.Y, D.X + W, D.Y + 66, A(DARKBG, 0.96), 8)
  local CL, CR = D.X + 14, D.X + W - 14
  local CT, CB = D.Y + 8, D.Y + 40
  local g, f, w = D:Get('cg') or 0, D:Get('cf') or 0, D:Get('cw') or 0
  local sg = 0.3 * (1 - w) + 0.05
  im.DrawList_AddLine(DL, CL, CB, CR, CB, A(CREAM, 0.3), 1)
  for i = 0, 48 do
    local t = i / 48
    local y = CB - g * (CB - CT - 4) * math.exp(-((t - f) ^ 2) / (2 * sg * sg))
    im.DrawList_PathLineTo(DL, CL + t * (CR - CL), y)
  end
  im.DrawList_PathStroke(DL, CREAM, nil, 1.8)
  im.DrawList_AddCircle(DL, CL + f * (CR - CL), CB - g * (CB - CT - 4), 4, CREAM, 0, 1.5)
  D:Bar('cg', 10, 47, 88, 12, 'Crunch', { accent = CREAM })
  D:Bar('cf', 101, 47, 88, 12, 'Frequency', { accent = CREAM })
  D:Bar('cw', 192, 47, 88, 12, 'Width', { accent = CREAM })
end

-- loss mode buttons
D:Rect(4, 72, 26, 66, PINK, 6, true)
local sel = math.floor((D:Get('mode') or 0) * 2 + 0.5)
for i = 0, 2 do
  local bx, by = 6, 75 + i * 21
  local clicked = D:Btn('mode' .. i, bx, by, 22, 19)
  if clicked then D:Set('mode', i / 2) end
  local on = (sel == i)
  D:Rect(bx, by, 22, 19, on and MAR or PAN, 4, true)
  local ic = on and CREAM or MAR
  local cx, cy = D.X + bx + 11, D.Y + by + 9.5
  if i == 0 then
    im.DrawList_PathLineTo(DL, cx - 7, cy)
    im.DrawList_PathLineTo(DL, cx - 3, cy)
    im.DrawList_PathLineTo(DL, cx - 1, cy - 6)
    im.DrawList_PathLineTo(DL, cx + 1, cy + 6)
    im.DrawList_PathLineTo(DL, cx + 3, cy)
    im.DrawList_PathLineTo(DL, cx + 7, cy)
    im.DrawList_PathStroke(DL, ic, nil, 1.5)
  elseif i == 1 then
    D:Text(bx + 11, by + 4, ic, 'x))', 10, 'c', true)
  else
    im.DrawList_PathArcTo(DL, cx, cy, 5, 0.5, 5.6)
    im.DrawList_PathStroke(DL, ic, nil, 1.5)
    im.DrawList_AddTriangleFilled(DL, cx + 1, cy - 8, cx + 1, cy - 2, cx + 6, cy - 5, ic)
  end
end

-- panels
D:Rect(34, 70, W - 38, 68, PAN, 8, true)
D:Rect(4, 142, 68, 62, PAN, 8, true)
D:Rect(76, 142, 136, 62, PAN, 8, true)
D:Rect(216, 142, 70, 62, PAN, 8, true)

local function Num(key) return SFX.Num(D:Fmt(key) or '') or 0 end
local function Rd(x) return math.floor(x + 0.5) end

local function Knob(key, cx, cy, rad, label, txt, bip, ring)
  local p = D:Idx(key)
  if p then D:PrmKnob(p, cx, cy, rad, '') end
  local v = D:Get(key) or 0
  local X, Y = D.X + cx, D.Y + cy
  local a0, a1 = math.pi * 0.75, math.pi * 2.25
  if ring then
    local n = 20
    local st = a0 - 0.1
    local span = math.pi * 2 * 0.85
    for i = 0, n - 1 do
      local s = st + span * i / n
      im.DrawList_PathArcTo(DL, X, Y, rad + 5, s, s + span / n * 0.55)
      im.DrawList_PathStroke(DL, (i / n <= v and v > 0.01) and INK or PINK, nil, 1.5)
    end
  end
  im.DrawList_PathArcTo(DL, X, Y, rad, a0, a1)
  im.DrawList_PathStroke(DL, PINK, nil, 2)
  local av = a0 + (a1 - a0) * v
  local am = bip and (a0 + a1) / 2 or a0
  local lo, hi = math.min(am, av), math.max(am, av)
  if hi - lo > 0.01 then
    im.DrawList_PathArcTo(DL, X, Y, rad, lo, hi)
    im.DrawList_PathStroke(DL, INK, nil, 2.8)
  end
  im.DrawList_AddCircleFilled(DL, X + rad * math.cos(av), Y + rad * math.sin(av), 2, INK)
  local sz = rad >= 23 and 12 or 10
  D:Text(cx, cy - sz / 2 - 1, INK, txt, sz, 'c', false)
  D:Text(cx, cy + rad * 0.78 + 1, INK, label, 9, 'c', false)
end

local bn = Num('bit')
local bt
if bn >= 10 then bt = string.format('%d', Rd(bn)) .. 'k' else bt = string.format('%.1f', bn) .. 'k' end
local bwt = (tostring(D:Fmt('bw') or ''):gsub('khz', 'k'))

Knob('loss', 90, 102, 26, 'Loss', Rd(Num('loss')) .. '%', false, true)
Knob('bit', 170, 102, 23, 'Bitrate', bt, false)
Knob('dis', 250, 102, 23, 'Disorder', Rd(Num('dis')) .. '%', false)
Knob('bw', 38, 170, 20, 'Bandwidth', bwt, false)
Knob('noise', 112, 170, 20, 'Noise', Rd(Num('noise')) .. '%', false)
Knob('col', 176, 170, 20, 'Colour', string.format('%.1f%%', Num('col')), true)
Knob('mix', 251, 170, 20, 'Mix', Rd(Num('mix')) .. '%', false)
D:End()
