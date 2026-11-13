-- NFuse (Kiive Audio): input/output, N/F switchable Saturation, EQ, Compressor and Stereo Imager (L channel), Mix, Delta, presets, power, output meter.
local SFX = require('src.Functions.Stock FX UI')
local D = SFX.Begin({ Title = 'NFuse', W = 940, Accent = SFX.ACCENT.Dynamics, Params = { inN = { 'N Input L', idx = 0 }, outN = { 'N Output L', idx = 1 }, hpfN = { 'N HPF L', idx = 2 }, inF = { 'F Input L', idx = 6 }, outF = { 'F Output L', idx = 7 }, hpfF = { 'F HPF L', idx = 8 }, nThr = { 'N Thresh L', idx = 12 }, nMix = { 'N Mix L', idx = 13 }, nRel = { 'N Release L', idx = 14 }, nMk = { 'N Makeup L', idx = 15 }, nSc = { 'N SC L', idx = 16 }, nRat = { 'N Ratio L', idx = 17 }, fThr = { 'F Thresh L', idx = 24 }, fAtk = { 'F Attack L', idx = 25 }, fRel = { 'F Release L', idx = 26 }, fRat = { 'F Ratio L', idx = 27 }, fMk = { 'F Makeup L', idx = 28 }, fSc = { 'F SC L', idx = 29 }, fHfT = { 'F HF Thresh L', idx = 30 }, compnf = { 'COMP NF', idx = 42 }, nLg = { 'N Low Gain L', idx = 43 }, nHg = { 'N High Gain L', idx = 44 }, nLf = { 'N Low Freq L', idx = 45 }, nHf = { 'N High Freq L', idx = 46 }, fLg = { 'F Low Gain L', idx = 51 }, fHg = { 'F High Gain L', idx = 52 }, fLf = { 'F Low Freq L', idx = 53 }, fHf = { 'F High Freq L', idx = 54 }, eqnf = { 'EQ NF', idx = 59 }, main = { 'Main NF switch', idx = 60 }, dark = { 'N Dark Sat L', idx = 61 }, red = { 'N Red Sat L', idx = 62 }, harm = { 'N Harmonics L', idx = 63 }, znr = { 'zz znr', idx = 64 }, fDrive = { 'F Drive L', idx = 69 }, fDens = { 'F Density L', idx = 70 }, nW = { 'N Width', idx = 73 }, nWh = { 'N Width HPF', idx = 74 }, fW = { 'F Width', idx = 75 }, fSp = { 'F Space', idx = 76 }, satpw = { 'Sat Power', idx = 77 }, eqpw = { 'EQ Power', idx = 78 }, cpw = { 'Comp Power', idx = 79 }, wpw = { 'Width Power', idx = 80 }, satnf = { 'SAT NF', idx = 81 }, wnf = { 'WIDTH NF', idx = 82 }, phase = { 'Phase Flip', idx = 83 }, byp = { 'zz bypass', idx = 84 }, wet = { 'Wet', idx = 86 }, delta = { 'Delta', idx = 87 } } })
if not D then return end
local C, A, DL = SFX.C, SFX.A, D.DL
local TEAL, YEL, GREY, GRN, PUR, MAG, ORG, BLU, LED = 0x1E9C8EFF, 0xEBD43CFF, 0xD2D2D2FF, 0x2E9A48FF, 0x7A34C8FF, 0xB848C8FF, 0xC8582FFF, 0x2A86C8FF, 0xF2D86AFF
D:Rect(0, 0, 940, 216, 0x171718FF, 6, true)
D:Rect(0, 0, 940, 24, 0x0D1114FF, 6, true)
D:Rect(4, 26, 932, 188, 0x1E1E20FF, 6, true)
for _, p in ipairs({ { 16, 38 }, { 16, 202 }, { 924, 38 }, { 924, 202 } }) do im.DrawList_AddCircleFilled(DL, D.X + p[1], D.Y + p[2], 6, 0x3A3A3CFF); im.DrawList_AddLine(DL, D.X + p[1] - 4, D.Y + p[2] - 2, D.X + p[1] + 4, D.Y + p[2] + 2, 0x151515FF, 1.5) end
for _, x in ipairs({ 164, 279, 406, 611, 756 }) do D:Line(x, 32, x, 208, C.Grid, 1) end
D:Bar('wet', 12, 6, 150, 12, 'Mix', { accent = TEAL })
D:Toggle('delta', 180, 3, 66, 'Delta', { accent = TEAL })
im.SetCursorScreenPos(ctx, D.X + 265, D.Y + 3)
Presets.Button(170, 18)
local function T(cx, txt) D:Text(cx, 31, C.Text, txt, 9, 'c', true) end
local function K(key, cx, cy, label, clr, bip) D:Knob(key, cx, cy, 'M', label, { accent = clr, bipolar = bip }) end
local function NF(key, cx, y)
  local f = D:Get(key) > 0.5
  local x = cx - 13
  D:Text(cx - 26, y + 2, C.TextDim, 'N', 9, 'c')
  D:Text(cx + 26, y + 2, C.TextDim, 'F', 9, 'c')
  D:Rect(x, y + 2, 26, 10, 0x0B0B0CFF, 5, true)
  D:Rect(x, y + 2, 26, 10, C.PanelEdge, 5, false, 1)
  im.DrawList_AddCircleFilled(DL, D.X + (f and x + 20 or x + 6), D.Y + y + 7, 5, 0x8A8A8EFF)
  if D:Btn('nf' .. key, x - 2, y, 30, 14) then D:Set(key, f and 0 or 1) end
end
local function IN(cx, key) D:Toggle(key, cx - 20, 194, 40, 'IN', { accent = LED }) end
local fm = D:Get('main') > 0.5
D:Text(25, 84, C.Text, 'N', 11, 'c', true)
D:Text(25, 146, C.Text, 'F', 11, 'c', true)
D:Rect(19, 100, 12, 40, 0x0B0B0CFF, 5, true)
D:Rect(19, 100, 12, 40, C.PanelEdge, 5, false, 1)
im.DrawList_AddCircleFilled(DL, D.X + 25, D.Y + (fm and 132 or 108), 6, 0x8A8A8EFF)
if D:Btn('mainnf', 14, 96, 22, 48) then D:Set('main', fm and 0 or 1) end
T(100, 'INPUT')
D:Knob(fm and 'inF' or 'inN', 100, 100, 24, '', { bipolar = true, accent = fm and 0x6E6E72FF or GREY })
D:Knob(fm and 'hpfF' or 'hpfN', 140, 168, 'S', 'HPF', { accent = fm and 0x6E6E72FF or GREY })
D:Toggle('phase', 56, 176, 46, 'Phase', { accent = 0xBBBBBBFF })
T(216, 'SATURATION')
NF('satnf', 216, 40)
if D:Get('satnf') > 0.5 then
  K('fDrive', 188, 92, 'DRIVE', GRN)
  K('fDens', 244, 92, 'DENSITY', GRN)
else
  K('dark', 188, 92, 'DARK', TEAL)
  K('red', 244, 92, 'SHINE', YEL)
  D:Knob('harm', 188, 160, 'S', 'HARMONICS', { accent = GREY })
  D:Toggle('znr', 226, 152, 60, 'Grit Mode', { accent = LED })
end
IN(216, 'satpw')
T(342, 'EQUALIZER')
NF('eqnf', 342, 40)
local fe = D:Get('eqnf') > 0.5
K(fe and 'fLf' or 'nLf', 312, 92, 'LF', fe and PUR or TEAL)
K(fe and 'fHf' or 'nHf', 372, 92, 'HF', fe and MAG or YEL)
K(fe and 'fLg' or 'nLg', 312, 158, 'LFG', fe and PUR or TEAL, true)
K(fe and 'fHg' or 'nHg', 372, 158, 'HFG', fe and MAG or YEL, true)
IN(342, 'eqpw')
T(505, 'COMPRESSOR')
NF('compnf', 505, 40)
if D:Get('compnf') > 0.5 then
  K('fThr', 440, 92, 'THR', ORG, true)
  K('fMk', 570, 92, 'MKP', ORG, true)
  K('fRat', 505, 106, 'RAT', ORG)
  K('fAtk', 440, 158, 'ATK', ORG)
  K('fRel', 570, 158, 'REL', ORG)
  D:Bar('fSc', 475, 152, 60, 12, 'S/C')
  D:Bar('fHfT', 475, 170, 60, 12, 'HF')
else
  K('nThr', 440, 92, 'THR', TEAL)
  K('nRel', 570, 92, 'REL', YEL)
  K('nMk', 505, 106, 'MKP', GREY, true)
  K('nMix', 440, 158, 'BLEND', TEAL)
  K('nSc', 570, 158, 'S/C HPF', YEL)
  D:Toggle('nRat', 478, 160, 54, 'HI RAT', { accent = 0xFF4040FF })
end
IN(505, 'cpw')
T(682, 'STEREO IMAGER')
NF('wnf', 682, 40)
if D:Get('wnf') > 0.5 then
  K('fW', 652, 92, 'WIDTH', BLU, true)
  K('fSp', 712, 92, 'SPACE', BLU, true)
else
  K('nW', 652, 92, 'WIDTH', TEAL)
  K('nWh', 712, 92, 'HPF', YEL)
end
IN(682, 'wpw')
T(800, 'OUTPUT')
D:Knob(fm and 'outF' or 'outN', 800, 100, 24, '', { bipolar = true, accent = fm and 0x6E6E72FF or GREY })
D:Toggle('byp', 768, 172, 64, 'POWER', { on = D:Get('byp') < 0.5, accent = 0xE8645AFF, onClick = function() D:Set('byp', D:Get('byp') > 0.5 and 0 or 1) end })
local function lv(ch)
  local p = r.Track_GetPeakInfo(LT_Track, ch) or 0
  local db = 20 * math.log(math.max(p, 0.00001)) / 2.302585
  return SFX.Clamp((db + 48) / 48, 0, 1)
end
D:Text(869, 44, C.TextDim, 'METER', 8, 'c')
D:Meter(862, 56, 8, 120, lv(0), 0x3CD14AFF)
D:Meter(876, 56, 8, 120, lv(1), 0x3CD14AFF)
D:Text(866, 180, C.TextDim, 'L', 8, 'c')
D:Text(880, 180, C.TextDim, 'R', 8, 'c')
for i, ch in ipairs({ 'N', 'F', 'U', 'S', 'E' }) do D:Text(920, 60 + (i - 1) * 17, C.Text, ch, 14, 'c', true) end
D:End()