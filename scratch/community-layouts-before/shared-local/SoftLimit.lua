-- SoftLimit (Apogee): purple faceplate, LED ladders, Drive / Threshold / Output knobs, IN, OVR-SMPLE and AUTO MAKEUP buttons.
local SFX = require('src.Functions.Stock FX UI')
local D = SFX.Begin({ Title = 'SoftLimit', W = 400, Accent = SFX.ACCENT.Dynamics, Params = { sl = { 'Soft Limit', idx = 2 }, input = { 'Input', idx = 3 }, thr = { 'Threshold', idx = 4 }, out = { 'Output', idx = 5 }, am = { 'Auto Makeup', idx = 6 }, ovs = { 'Oversampling', idx = 7 } } })
if not D then return end
local DL, S = D.DL, D.S
local KA = 0xB58AD6FF
D:Rect(0, 0, 400, 216, 0xB48CD2FF, 5, true)
D:Rect(0, 0, 400, 216, 0x8A64A8FF, 5, false, 1)
D:Text(200, 3, 0xF4ECFAFF, 'A   P   O   G   E   E', 12, 'c', false)
D:Text(200, 17, 0xF4ECFAFF, 'S  O  F  T     L  I  M  I  T', 8, 'c', false)
D:Rect(10, 28, 380, 176, 0x3A3D43FF, 3, true)
D:Rect(10, 28, 380, 176, 0x1E2024FF, 3, false, 1)
D:Text(200, 206, 0x6A4A88FF, 'APOGEE ELECTRONICS CORPORATION - SANTA MONICA - CALIFORNIA', 8, 'c', false)
local function db(v) return 20 * math.log(math.max(v, 1e-5), 10) end
local drive = -18 + 36 * D:Get('input')
local thr = -32 + 32 * D:Get('thr')
local inDb = -60
local w = D:InputWave(3)
if w and #w > 0 then
  local m = 0
  for i = math.max(1, #w - 2), #w do if w[i] > m then m = w[i] end end
  inDb = db(m) + drive
end
local pk = math.max(r.Track_GetPeakInfo(LT_Track, 0), r.Track_GetPeakInfo(LT_Track, 1))
local oDb = db(pk)
S.i = math.max(inDb, (S.i or -60) - 1.2)
S.o = math.max(oDb, (S.o or -60) - 1.2)
S.g = math.max(math.max(0, inDb - thr), (S.g or 0) - 0.8)
if pk >= 1 and not S.was then S.over = (S.over or 0) + 1 end
S.was = pk >= 1
if S.i >= 0 then S.ciT = D.NOW end
if S.o >= 0 then S.coT = D.NOW end
local ciLit = D.NOW - (S.ciT or -9) < 1
local coLit = D.NOW - (S.coT or -9) < 1
local MX, MW, N = 66, 260, 40
local SW = MW / N
D:Line(MX, 41, MX + MW, 41, 0x9A9AA0FF, 1)
for k = 0, 6 do
  local x = MX + MW * k / 6
  D:Line(x, 41, x, 45, 0x9A9AA0FF, 1)
  local t = tostring(-36 + 6 * k)
  if k == 6 then t = '0 dBFS' end
  D:Text(x, 30, 0xB4B4BCFF, t, 8, 'c', false)
end
local function ladder(y, v, rev)
  D:Rect(MX - 4, y - 2, MW + 8, 12, 0x7C6C4EFF, 2, true)
  D:Rect(MX - 1, y - 1, MW + 2, 10, 0x241C16FF, 1, true)
  for i = 0, N - 1 do
    local d = -36 + 36 * i / N
    local col, lit = 0x3A2E24FF, false
    if rev then
      lit = (N - 1 - i) < v * N / 36
      if lit then col = 0xC07CF0FF end
    else
      lit = d < v
      if lit then
        if d < -6 then col = 0x8CEB1EFF elseif d < -2 then col = 0xE8D020FF else col = 0xF08A18FF end
      end
    end
    im.DrawList_AddRectFilled(DL, D.X + MX + i * SW, D.Y + y, D.X + MX + (i + 1) * SW - 1, D.Y + y + 8, col)
  end
end
ladder(46, S.i, false)
ladder(59, S.g, true)
ladder(72, S.o, false)
D:Text(58, 46, 0xB0B0B8FF, 'INPUT', 8, 'r', false)
D:Text(58, 59, 0xB0B0B8FF, 'SOFT LIMIT', 8, 'r', false)
D:Text(58, 72, 0xB0B0B8FF, 'OUTPUT', 8, 'r', false)
local function clip(y, lit)
  local c = lit and 0xFF2A2AFF or 0x5A1414FF
  D:Rect(332, y, 8, 5, c, 1, true)
  D:Rect(332, y + 7, 8, 5, c, 1, true)
end
clip(47, ciLit)
clip(73, coLit)
D:Text(358, 63, 0xB0B0B8FF, 'OVER', 8, 'c', false)
local cnt = S.over or 0
local t1, t2 = '-', '-'
if cnt <= 9 then t1, t2 = '0', tostring(cnt) end
D:Rect(347, 74, 17, 18, 0x101214FF, 2, true)
D:Rect(367, 74, 17, 18, 0x101214FF, 2, true)
D:Text(355.5, 76, 0x7CFF5AFF, t1, 14, 'c', true)
D:Text(375.5, 76, 0x7CFF5AFF, t2, 14, 'c', true)
D:Text(355, 94, 0xB0B0B8FF, 'L', 8, 'c', false)
D:Text(375, 94, 0xB0B0B8FF, 'R', 8, 'c', false)
local rc = D:Btn('overReset', 347, 74, 37, 18)
if rc then S.over = 0 end
local function sq(id, x, y, bw, bh, l1, l2, col)
  D:Rect(x, y, bw, bh, 0x0E0E10FF, 2, true)
  D:Rect(x + 2, y + 2, bw - 4, bh - 4, 0x8E8E94FF, 3, true)
  D:Rect(x + 4, y + 4, bw - 8, bh - 8, 0x26282BFF, 2, true)
  local cx = x + bw / 2
  if l2 then
    D:Text(cx, y + bh / 2 - 9, col, l1, 8, 'c', true)
    D:Text(cx, y + bh / 2 + 1, col, l2, 8, 'c', true)
  else
    D:Text(cx, y + bh / 2 - 4, col, l1, 8, 'c', true)
  end
  local clicked = D:Btn(id, x, y, bw, bh)
  return clicked
end
local slOn = D:Get('sl') > 0.5
if sq('btnIn', 36, 96, 36, 32, 'IN', nil, slOn and 0x9CFF50FF or 0x4A5A3AFF) then
  D:Set('sl', slOn and 0 or 1)
end
local ovT = D:Fmt('ovs') or ''
local ovOn = ovT ~= 'None' and ovT ~= 'Off'
if sq('btnOvs', 36, 138, 36, 32, 'OVR-', 'SMPLE', ovOn and 0xF0D030FF or 0x6A5E20FF) then
  local ch = D:Choices('ovs')
  if ch and #ch > 0 then
    local cur, bi, bd = D:Get('ovs'), 1, 9
    for i, c in ipairs(ch) do
      local dd = math.abs(c[2] - cur)
      if dd < bd then bi, bd = i, dd end
    end
    D:Set('ovs', ch[bi % #ch + 1][2])
  end
end
local ol = { { '4x', 140 }, { '8x', 150 }, { '16x', 160 } }
for _, o in ipairs(ol) do
  D:Text(33, o[2], ovT == o[1] and 0xE8A838FF or 0xA0A0A8FF, o[1], 8, 'r', false)
end
D:Knob('input', 112, 146, 'M', 'DRIVE', { unit = 'dB', bipolar = true, accent = KA })
D:Knob('thr', 200, 146, 26, 'SOFT LIMIT THRESHOLD', { unit = 'dB', accent = KA })
D:Knob('out', 290, 146, 'M', 'OUTPUT', { unit = 'dB', bipolar = true, accent = KA })
D:Text(346, 104, 0xB0B0B8FF, 'AUTO MAKEUP', 8, 'c', false)
local amOn = D:Get('am') > 0.5
if sq('btnAm', 328, 116, 36, 32, 'ON', nil, amOn and 0xE8C030FF or 0x6A5A20FF) then
  D:Set('am', amOn and 0 or 1)
end
D:End()