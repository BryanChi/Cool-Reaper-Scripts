-- Crystalline (BABY Audio): reflections, depth, gradient display, start/end, output, clean-up and shape
local SFX = require('src.Functions.Stock FX UI')
local D = SFX.Begin({
 Title = 'Crystalline', W = 580, Accent = SFX.ACCENT.Time,
 Params = {
  size = { 'Size', idx = 13 }, spark = { 'Sparkle', idx = 16 }, width = { 'Width', idx = 26 },
  res = { 'Resolution', idx = 5 }, mod = { 'Modulation', idx = 32 },
  shim = { 'Shimmer Power', idx = 23 }, shimF = { 'Shimmer Frequency', idx = 24 }, shimM = { 'Shimmer Multiplier', idx = 25 },
  dlo = { 'Damping Low', idx = 14 }, dhi = { 'Damping High', idx = 15 }, sides = { 'Sides', idx = 21 },
  gth = { 'Gate Threshold', idx = 17 }, grel = { 'Gate Release', idx = 18 },
  tone = { 'Tone', idx = 19 }, smooth = { 'Smoothing', idx = 22 }, warp = { 'Warp', idx = 20 },
  sSync = { 'Start Time Sync', idx = 6 }, sMs = { 'Start Time Ms', idx = 7 }, sMode = { 'Start Time Mode', idx = 8 },
  eSync = { 'End Time Sync', idx = 9 }, eMs = { 'End Time Ms', idx = 10 }, eMode = { 'End Time Mode', idx = 11 },
  duck = { 'Ducker', idx = 27 }, gentle = { 'Ducker Gentle Mode', idx = 28 }, rev = { 'Reverse', idx = 29 },
  frz = { 'Freeze', idx = 12 }, mix = { 'Dry Wet Mix', idx = 30 }, lock = { 'Wet Lock Mode', idx = 31 },
 },
})
if not D then return end
local C, A = SFX.C, SFX.A
local DL = D.DL
D:Rect(0, 0, 580, 216, 0x26272AFF, 0, true)
local function panel(x, y, w, h, title)
 D:Rect(x, y, w, h, 0x34353AFF, 8, true)
 D:Rect(x, y, w, h, 0x484950FF, 8, false, 1)
 D:Text(x + w / 2, y + 6, 0xDADADCFF, title, 9, 'c', true)
end
local RED, BLUE, ORG, GRN, MAG = 0xE03C3CFF, 0x3C8CE0FF, 0xF0A030FF, 0x3CBE78FF, 0xE8508CFF
-- left panel
panel(4, 4, 170, 100, 'REFLECTIONS')
panel(4, 110, 170, 102, 'DEPTH')
local cw = 170 / 3
local function cx(x0, i, n, w) return x0 + (w / n) * (i - 0.5) end
D:Knob('size', cx(4, 1, 3, 170), 64, 'M', 'SIZE', { accent = RED })
D:Knob('spark', cx(4, 2, 3, 170), 64, 'M', 'SPARKLE', { accent = RED })
D:Knob('width', cx(4, 3, 3, 170), 64, 'M', 'WIDTH', { accent = RED, bipolar = true })
D:Knob('res', cx(4, 1, 3, 170), 170, 'M', 'RESOLUTION', { accent = BLUE })
D:Knob('mod', cx(4, 2, 3, 170), 170, 'M', 'MODULATION', { accent = BLUE })
local sx = cx(4, 3, 3, 170)
D:Toggle('shim', sx - 27, 140, 54, 'SHIMMER', { accent = BLUE })
D:Choice('shimF', sx - 27, 160, 54, { h = 18 })
D:Choice('shimM', sx - 27, 182, 54, { h = 18 })
-- centre
D:Text(290, 5, 0xE8E8EAFF, 'crystalline', 14, 'c', false)
local L, T, R, B = D:Panel(180, 22, 220, 64)
local x1, y1, x2, y2 = L + 3, T + 3, R - 3, B - 3
local mx = (x1 + x2) / 2
im.DrawList_AddRectFilledMultiColor(DL, x1, y1, mx, y2, 0xF2B91DFF, 0xF0508CFF, 0xE8508CFF, 0xF2B91DFF)
im.DrawList_AddRectFilledMultiColor(DL, mx, y1, x2, y2, 0xE8508CFF, 0x5A6CF0FF, 0x5A6CF0FF, 0xE8508CFF)
local wv = D:InputWave(48)
local n = 48
local hmax = (y2 - y1) - 8
local colw = (x2 - x1 - 8) / n
if wv then
 for i = 1, n do
  local v = wv[i] or 0
  local db = 20 * math.log(math.max(v, 0.0001)) / math.log(10)
  local h = SFX.Clamp((db + 60) / 60, 0, 1) * hmax
  local x = x1 + 4 + (i - 0.5) * colw
  im.DrawList_AddLine(DL, x, y2 - 4, x, y2 - 4 - h, 0xFFFFFFD8, 1.4)
 end
else
 im.DrawList_AddLine(DL, x1 + 4, y2 - 4, x2 - 4, y2 - 4, 0xFFFFFFD8, 1.4)
end
-- start / end
D:Text(186, 90, 0xDADADCFF, 'START', 8, nil, true)
D:Text(296, 90, 0xDADADCFF, 'END', 8, nil, true)
local sk = D:On('sMode') and 'sSync' or 'sMs'
local ek = D:On('eMode') and 'eSync' or 'eMs'
D:Bar(sk, 186, 98, 100, 16, nil, { accent = MAG })
D:Bar(ek, 296, 98, 100, 16, nil, { accent = MAG })
D:Toggle('sMode', 186, 118, 60, 'SYNC', { accent = MAG })
D:Toggle('eMode', 296, 118, 60, 'SYNC', { accent = MAG })
-- output
panel(180, 140, 220, 72, 'OUTPUT')
D:Bar('duck', 188, 158, 100, 22, 'DUCKER', { accent = MAG })
D:Bar('mix', 292, 158, 100, 22, 'DRY/WET', { accent = MAG })
D:Toggle('gentle', 188, 190, 48, 'GENTLE', { accent = MAG })
D:Toggle('rev', 240, 190, 48, 'REV', { accent = MAG })
D:Toggle('frz', 292, 190, 48, 'FRZ', { accent = BLUE })
D:Toggle('lock', 344, 190, 48, 'LOCK', { accent = MAG })
-- right panel
panel(406, 4, 170, 100, 'CLEAN-UP')
panel(406, 110, 170, 102, 'SHAPE')
D:Knob('dlo', cx(406, 1, 5, 170), 64, 'S', 'LOW', { accent = ORG })
D:Knob('dhi', cx(406, 2, 5, 170), 64, 'S', 'HIGH', { accent = ORG })
D:Knob('sides', cx(406, 3, 5, 170), 64, 'S', 'SIDES', { accent = ORG })
D:Knob('gth', cx(406, 4, 5, 170), 64, 'S', 'GATE', { accent = ORG })
D:Knob('grel', cx(406, 5, 5, 170), 64, 'S', 'REL', { accent = ORG })
D:Knob('tone', cx(406, 1, 3, 170), 170, 'M', 'TONE', { accent = GRN, bipolar = true })
D:Knob('smooth', cx(406, 2, 3, 170), 170, 'M', 'SMOOTHING', { accent = GRN })
D:Knob('warp', cx(406, 3, 3, 170), 170, 'M', 'TRANSIENTS', { accent = GRN, bipolar = true })
D:End()