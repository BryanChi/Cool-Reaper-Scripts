-- soothe2 (oeksound): main, stereo, speed, quality, sidechain and output panels plus the band curve graph with draggable nodes
local SFX = require('src.Functions.Stock FX UI')
local P = { mode={'x',idx=3}, depth={'x',idx=4}, sharp={'x',idx=5}, sel={'x',idx=6}, att={'x',idx=7}, rel={'x',idx=8}, smode={'x',idx=43}, link={'x',idx=44}, bal={'x',idx=45}, ovs={'x',idx=48}, res={'x',idx=49}, mix={'x',idx=50}, trim={'x',idx=51}, delta={'x',idx=52}, sc={'x',idx=54}, scs={'x',idx=2}, lcOn={'x',idx=9}, lcF={'x',idx=11}, lcS={'x',idx=13}, hcOn={'x',idx=38}, hcF={'x',idx=40}, hcS={'x',idx=42}, byp={'x',idx=53} }
for b = 1, 4 do local o = 14 + (b-1)*6; local k = 'b'..b; P[k..'on']={'x',idx=o}; P[k..'f']={'x',idx=o+1}; P[k..'s']={'x',idx=o+2}; P[k..'q']={'x',idx=o+3}; P[k..'m']={'x',idx=o+5} end
local D = SFX.Begin({ Title = 'soothe2', W = 560, Accent = 0x6B879CFF, Params = P })
if not D then return end
local DL, X, Y = D.DL, D.X, D.Y
local DK, MU, WH, BOX = 0x3A4752FF, 0x7391A5FF, 0xFFFFFFFF, 0xD4E0E8FF
local PI = math.pi
local function grad(x1,y1,x2,y2,c1,c2) im.DrawList_AddRectFilledMultiColor(DL, X+x1, Y+y1, X+x2, Y+y2, c1, c1, c2, c2) end
local function vbox(cx, y, w, h, txt) D:Rect(cx-w/2, y, w, h, BOX, 2, true); D:Text(cx, y+(h-10)/2-1, DK, txt, 10, 'c') end
local function knob(key, cx, cy, rad, label, bip)
  local p = D:Idx(key)
  if p then D:PrmKnob(p, cx, cy, rad, label) end
  local v = D:Get(key)
  local px, py = X+cx, Y+cy
  local a0, a1 = 0.75*PI, 2.25*PI
  im.DrawList_PathArcTo(DL, px, py, rad+3, a0, a1); im.DrawList_PathStroke(DL, 0xA2B9C8FF, nil, 3)
  local s, e = a0, a0 + (a1-a0)*v
  if bip then s = 1.5*PI; if e < s then s, e = e, s end end
  if e - s > 0.02 then im.DrawList_PathArcTo(DL, px, py, rad+3, s, e); im.DrawList_PathStroke(DL, WH, nil, 3) end
  im.DrawList_AddCircleFilled(DL, px, py, rad, 0x3A3A3CFF)
  if label ~= '' then D:Text(cx, cy-rad-12, DK, label, 9, 'c') end
  vbox(cx, cy+rad+5, 42, 12, D:Fmt(key))
end
local function numbox(key, x, y, w, h, txt)
  vbox(x+w/2, y, w, h, txt)
  local p = D:Idx(key)
  if p then D:PrmSlider(p, x, y, w, h, '') end
end
local function radio(id, key, cx, cy, label)
  local on = D:On(key)
  if D:Btn(id, cx-8, cy-9, 62, 18) then D:Set(key, on and 0 or 1) end
  im.DrawList_AddCircle(DL, X+cx, Y+cy, 6, 0xEAF2F6FF, 0, 2)
  if on then im.DrawList_AddCircleFilled(DL, X+cx, Y+cy, 3.5, WH) end
  D:Text(cx+12, cy-6, DK, label, 11)
end
local function cycle(key, n) local i = math.floor(D:Get(key)*(n-1)+0.5); i = (i+1) % n; D:Set(key, i/(n-1)) end
local function pct(key) return string.format('%d %%', math.floor(D:Get(key)*100+0.5)) end

-- panels
grad(0, 0, 150, 216, 0xD0DFE7FF, 0xB1C8D6FF)
grad(150, 0, 292, 216, 0xBFD1DCFF, 0xB2C8D6FF)
D:Rect(222, 0, 70, 50, 0x9FB7C766, 0, true)
D:Line(220, 6, 220, 210, 0xFFFFFF40, 1)

-- main
D:Text(8, 3, DK, 'soothe', 16, nil, true)
D:Text(8 + SFX.TextW('soothe', 16, true) + 1, 3, 0xEAF4FAFF, '2', 16, nil, true)
do
  local x, y, w, h = 8, 22, 134, 16
  D:Rect(x, y, w, h, 0xA9C0CEFF, 3, true)
  local hard = D:Get('mode') > 0.5
  D:Rect(hard and x+w/2 or x, y, w/2, h, WH, 3, true)
  D:Text(x+w/4, y+2, DK, 'soft', 11, 'c')
  D:Text(x+3*w/4, y+2, DK, 'hard', 11, 'c')
  local c1 = D:Btn('mode_soft', x, y, w/2, h)
  local c2 = D:Btn('mode_hard', x+w/2, y, w/2, h)
  if c1 then D:Set('mode', 0) elseif c2 then D:Set('mode', 1) end
end
knob('depth', 44, 82, 22, 'depth')
knob('sharp', 112, 64, 11, 'sharpness')
knob('sel', 112, 114, 11, 'selectivity')

-- stereo
D:Text(8, 146, MU, 'STEREO', 8, nil, true)
D:Line(48, 150, 142, 150, 0x8FA9B9AA, 1)
D:Text(39, 158, DK, 'mode', 10, 'c')
D:Rect(8, 170, 62, 14, BOX, 2, true)
D:Text(39, 173, DK, D:Fmt('smode'), 9, 'c')
if D:Btn('smode_btn', 8, 170, 62, 14) then D:Set('smode', D:Get('smode') > 0.5 and 0 or 1) end
D:Text(39, 187, DK, 'link', 10, 'c')
numbox('link', 8, 198, 62, 14, pct('link'))
D:Text(112, 158, DK, 'balance', 10, 'c')
knob('bal', 112, 181, 9, '', true)

-- speed and quality
D:Text(156, 3, MU, 'SPEED', 8, nil, true)
knob('att', 187, 40, 11, 'attack')
knob('rel', 187, 100, 11, 'release')
D:Text(156, 146, MU, 'QUALITY', 8, nil, true)
D:Rect(156, 160, 62, 16, BOX, 2, true)
D:Text(171, 164, DK, D:Fmt('ovs'), 9, 'c')
D:Text(187, 164, MU, '|', 9, 'c')
D:Text(203, 164, DK, D:Fmt('res'), 9, 'c')
if D:Btn('q_ovs', 156, 160, 31, 16) then cycle('ovs', 3) end
if D:Btn('q_res', 187, 160, 31, 16) then cycle('res', 4) end

-- sidechain
D:Text(228, 3, MU, 'SIDECHAIN', 8, nil, true)
do
  local on1, on2 = D:On('sc'), D:On('scs')
  local c1 = on1 and WH or 0x9DB5C5FF
  local c2 = on2 and WH or 0x9DB5C5FF
  local px, py = X+240, Y+30
  im.DrawList_PathArcTo(DL, px, py, 7, -PI/2+0.65, 1.5*PI-0.65); im.DrawList_PathStroke(DL, c1, nil, 2)
  im.DrawList_AddLine(DL, px, py-9, px, py, c1, 2)
  if D:Btn('sc_btn', 228, 18, 24, 24) then D:Set('sc', on1 and 0 or 1) end
  local hx, hy = X+272, Y+31
  im.DrawList_PathArcTo(DL, hx, hy, 7, PI, 2*PI); im.DrawList_PathStroke(DL, c2, nil, 2)
  im.DrawList_AddRectFilled(DL, hx-9, hy-1, hx-5, hy+6, c2, 1)
  im.DrawList_AddRectFilled(DL, hx+5, hy-1, hx+9, hy+6, c2, 1)
  if D:Btn('scs_btn', 260, 18, 24, 24) then D:Set('scs', on2 and 0 or 1) end
end

-- output
D:Text(228, 58, MU, 'OUTPUT', 8, nil, true)
D:Text(256, 72, DK, 'mix', 10, 'c')
numbox('mix', 226, 84, 60, 15, pct('mix'))
D:Text(256, 108, DK, 'trim', 10, 'c')
numbox('trim', 226, 120, 60, 15, string.format('%.1f dB', D:Val('trim') or 0))
radio('delta_btn', 'delta', 236, 160, 'delta')
radio('byp_btn', 'byp', 236, 186, 'bypass')

-- graph
local GX, GW, Y0, PXD = 292, 268, 108, 4.8
local function fx(f) return GX + GW*math.log(f/46)/math.log(500) end
local function lg(f) return math.log(f)/2.302585 end
D:Rect(GX, 0, GW, 16, 0x6B879CFF, 0, true)
grad(GX, 16, GX+GW, Y0, 0xADBBC3FF, 0xC6C9CAFF)
grad(GX, Y0, GX+GW, 216, 0x6F9AB8FF, 0xA4BED0FF)
local fl = { {63,'63'}, {125,'125'}, {250,'250'}, {500,'500'}, {1000,'1k'}, {2000,'2k'}, {4000,'4k'}, {8000,'8k'}, {16000,'16k'} }
for _, t in ipairs(fl) do
  local x = fx(t[1])
  D:Line(x, 16, x, 216, 0xFFFFFF26, 1)
  D:Text(x, 19, 0xF3F7F9FF, t[2], 10, 'c')
end
for _, db in ipairs({12, 6, 0, -6, -12, -18}) do
  local y = Y0 - db*PXD
  D:Line(GX, y, GX+GW, y, db == 0 and 0xFFFFFF55 or 0xFFFFFF26, 1)
  D:Text(GX+GW-6, y-5, 0xEEF4F7FF, tostring(db), 9, 'r')
end

local bs = {}
for b = 1, 4 do
  local k = 'b'..b
  bs[b] = { on = D:On(k..'on'), l = lg(20*1000^D:Get(k..'f')), g = (D:Get(k..'s')*2-1)*12, q = 0.1*100^D:Get(k..'q'), m = math.floor(D:Get(k..'m')*5+0.5) }
end
local lc = { on = D:On('lcOn'), l = lg(20*1000^D:Get('lcF')), sl = 6 + 42*D:Get('lcS') }
local hc = { on = D:On('hcOn'), l = lg(20*1000^D:Get('hcF')), sl = 6 + 42*D:Get('hcS') }
local function val(l)
  local g = 0
  for b = 1, 4 do
    local t = bs[b]
    if t.on then
      local d = l - t.l
      if t.m == 0 then g = g + t.g/(1+math.exp(d/0.15))
      elseif t.m == 2 then g = g + t.g/(1+math.exp(-d/0.15))
      elseif t.m == 3 then g = g + t.g*(2/(1+math.exp(-d/0.4))-1)
      else local sg = 0.3/math.sqrt(t.q); g = g + t.g*math.exp(-(d*d)/(2*sg*sg)) end
    end
  end
  if lc.on then local o = (lc.l - l)/0.30103; if o > 0 then g = g - math.min(o*lc.sl, 80) end end
  if hc.on then local o = (l - hc.l)/0.30103; if o > 0 then g = g - math.min(o*hc.sl, 80) end end
  return g
end
im.DrawList_PushClipRect(DL, X+GX, Y+16, X+GX+GW, Y+216, true)
local l0, l1 = lg(46), lg(23000)
for n = 0, 64 do
  local x = GX + n/64*GW
  local y = SFX.Clamp(Y0 - val(l0 + (l1-l0)*n/64)*PXD, 17, 215)
  im.DrawList_PathLineTo(DL, X+x, Y+y)
end
im.DrawList_PathStroke(DL, WH, nil, 2)
im.DrawList_PopClipRect(DL)

local mx, my = im.GetMousePos(ctx)
local function node(id, onKey, fKey, sKey, clr, hollow)
  local on = D:On(onKey)
  local x = SFX.Clamp(fx(20*1000^D:Get(fKey)), GX+5, GX+GW-5)
  local y = Y0
  if sKey then y = SFX.Clamp(Y0 - ((D:Get(sKey)*2-1)*12)*PXD, 22, 200) end
  local cl, hov, act = D:Btn(id, x-7, y-7, 14, 14)
  if cl and not on then D:Set(onKey, 1) end
  if act and on and mx then
    local fr = SFX.Clamp((mx-X-GX)/GW, 0, 1)
    D:Set(fKey, SFX.Clamp(math.log(46*500^fr/20)/math.log(1000), 0, 1))
    if sKey then D:Set(sKey, SFX.Clamp(((Y0-(my-Y))/PXD/12+1)/2, 0, 1)) end
  end
  local c = SFX.A(clr, on and 1 or 0.4)
  if hollow then im.DrawList_AddCircle(DL, X+x, Y+y, 5, c, 0, 2) else im.DrawList_AddCircleFilled(DL, X+x, Y+y, 5, c) end
end
node('n_lc', 'lcOn', 'lcF', nil, 0x516B80FF, false)
node('n_b1', 'b1on', 'b1f', 'b1s', 0xFFE600FF, false)
node('n_b2', 'b2on', 'b2f', 'b2s', 0xF0A030FF, false)
node('n_b3', 'b3on', 'b3f', 'b3s', 0xE06060FF, false)
node('n_b4', 'b4on', 'b4f', 'b4s', 0x9B3FB5FF, false)
node('n_hc', 'hcOn', 'hcF', nil, 0xDDEFF8FF, true)

local tg = { {'lcOn','LC',0x516B80FF}, {'b1on','1',0xFFE600FF}, {'b2on','2',0xF0A030FF}, {'b3on','3',0xE06060FF}, {'b4on','4',0x9B3FB5FF}, {'hcOn','HC',0xDDEFF8FF} }
for i, t in ipairs(tg) do D:Toggle(t[1], GX+8+(i-1)*42, 196, 38, t[2], { on = D:On(t[1]), accent = t[3] }) end

im.SetCursorScreenPos(ctx, X+GX+6, Y+1)
Presets.Button(150, 14)
D:End()