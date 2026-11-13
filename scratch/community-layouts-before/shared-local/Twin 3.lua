-- FabFilter Twin 3 ("VST3i: Twin 3 (FabFilter)", 1428 params; the VST and AU match by name).
-- The plugin's window at about 0.58 scale, in its own order: oscillators, the filter display with the
-- main EG under it, master tune / portamento, filter offsets, the six FX. Its bottom band shares the
-- centre: the switch at the EG shows the macros and modulation sources in its place, their editors and
-- the arpeggiator, voices and output open over the centre. Every source, slot, oscillator and filter
-- is a param, so all of it is wired here.
-- Drag a source dot onto a control to modulate it; click a dot for its slots.
local SFX = require('src.Functions.Stock FX UI')
local W, H = 684, 216
local D = SFX.Begin({ Title = 'Twin 3', W = W, H = H, Accent = 0xFFD23CFF, RegisterMapped = true,
    Params = { last = { idx = 786 } } })
if not D then return end
local S, DL, X, Y = D.S, D.DL, D.X, D.Y
local floor, min, max, abs, exp, log, pi = math.floor, math.min, math.max, math.abs, math.exp, math.log, math.pi
local A = SFX.A
local T = { Bg = 0x1B191FFF, Bg2 = 0x151317FF, Panel = 0x241F27FF, Tile = 0x221D21FF, TileHi = 0x2B262CFF, Knob = 0x332E35FF,
    KnobLo = 0x28232AFF, Rim = 0x45404AFF, Gold = 0xFFD23CFF, Dim = 0x736439FF, Txt = 0xBAB8BDFF, Hi = 0xF2F0F4FF,
    Mute = 0x6F6B73FF, Line = 0xFFFFFF14, Bar = 0x201C1DFF, Blue = 0x3090F4FF, Green = 0x16C06AFF, Grid = 0xFFFFFF0C }
local U = {}
local RX, RY, RW, RH = 160, 16, 348, 184 -- the panels over the centre

local function G(p) return D:Get(p) end
local function St(p, v) D:Set(p, v) end
local function On(p) return G(p) >= 0.5 end
local function I(p, n) return floor(G(p) * n + 0.5) end
local function Lin(x1, y1, x2, y2, c, th) D:Line(x1, y1, x2, y2, c, th) end
local function Circ(x, y, rad, c) im.DrawList_AddCircleFilled(DL, X + x, Y + y, rad, c, 24) end
local function Ring(x, y, rad, c, th) im.DrawList_AddCircle(DL, X + x, Y + y, rad, c, 24, th or 1) end
local function Mouse() local mx, my = im.GetMousePos(ctx) return mx - X, my - Y end

-- source kinds: count param, first block param, block size, slot-source offset, slot-target offset / params per block
local K = {
    xy = { n = 6, cnt = 149, base = 150, size = 4, clr = 0x2CC870FF, src0 = 0, pair = true, name = 'XY', fx = 0 },
    xlfo = { n = 6, cnt = 174, base = 175, size = 74, clr = 0x22D4DEFF, src0 = 12, tgt0 = 75, tn = 6, name = 'XLFO', fx = 0 },
    eg = { n = 6, cnt = 619, base = 620, size = 13, clr = 0x3090F4FF, src0 = 18, tgt0 = 111, tn = 11, name = 'EG', fx = 1 },
    ef = { n = 4, cnt = 698, base = 699, size = 4, clr = 0x6C58F4FF, src0 = 24, tgt0 = 177, tn = 3, name = 'EF', fx = 0 },
    midi = { n = 10, cnt = 715, base = 716, size = 5, clr = 0xA446E6FF, src0 = 28, tgt0 = 189, tn = 1, name = 'MIDI', fx = 0 },
}
local KORDER = { 'xy', 'xlfo', 'eg', 'ef', 'midi' }
local SLOT0, NSRC, NTGT = 788, 38, 299

function U.Cnt(kd) local q = K[kd] return I(q.cnt, q.n - q.fx) + q.fx end
function U.SetCnt(kd, c) local q = K[kd] St(q.cnt, (c - q.fx) / (q.n - q.fx)) end
function U.B(kd, k) return K[kd].base + K[kd].size * (k - 1) end

---------------------------------------------------------------------------------------------
-- tables built once: param -> slot target, value lists
if not S.P2T then
    S.P2T, S.Lists, S.Rects, S.Mods, S.BySrc, S.Names, S.Sel = {}, {}, {}, {}, {}, {}, {}
    S.ModT, S.NameT, S.Scroll, S.Step = 0, 0, 0, 1
    -- the plugin's own lists are written out here: the VST2 can't format a value it isn't set to
    local TL = { 'Master Tune', 'Portamento' }
    local function Add(pre, list) for _, q in ipairs(list) do TL[#TL + 1] = pre .. q end end
    for i = 1, 4 do Add('Osc ' .. i .. ' ', { 'Detune', 'Pulse Width', 'Sync', 'Level', 'Pan' }) end
    for i = 1, 4 do Add('Filter ' .. i .. ' ', { 'Freq', 'Pan', 'Peak' }) end
    Add('Filter ', { 'Freq Offset', 'Peak Offset' })
    Add('FX Reverb ', { 'Amount', 'Time', 'Brightness', 'Pre Delay' })
    Add('FX Delay ', { 'Amount', 'Time', 'Offset', 'Time Pan', 'Feedback' })
    for i = 1, 4 do Add('FX Delay Filter ' .. i .. ' ', { 'Freq', 'Pan', 'Peak' }) end
    Add('FX Chorus ', { 'Amount', 'Rate', 'Depth', 'Delay' })
    Add('FX Phaser ', { 'Amount', 'Rate', 'Depth', 'Feedback', 'Shift' })
    Add('FX ', { 'Drive Amount', 'Compress Amount', 'Compress Threshold', 'Compress Attack', 'Compress Release' })
    Add('', { 'Output Volume', 'Output Pan', 'Stereo', 'Unison Spread' })
    for i = 1, 6 do Add('XLFO ' .. i .. ' ', { 'Level', 'Freq', 'Freq Offset', 'Balance', 'Glide', 'Phase Offset' }) end
    for i = 1, 6 do Add('EG ' .. i .. ' ', { 'Level', 'Threshold', 'Delay', 'Attack', 'Attack Slope', 'Decay', 'Decay Slope', 'Sustain', 'Hold', 'Release', 'Release Slope' }) end
    for i = 1, 4 do Add('EF ' .. i .. ' ', { 'Level', 'Attack', 'Release' }) end
    for i = 1, 10 do TL[#TL + 1] = 'MS ' .. i .. ' Level' end
    for i = 1, 100 do TL[#TL + 1] = 'Slot ' .. i .. ' Level' end
    S.TName = TL
    local byName = {}
    for p = 0, 787 do byName[(D.Names[p] or ''):lower()] = p end
    for t = 1, NTGT do
        local n = TL[t]:gsub('^FX ', ''):gsub('Pre Delay', 'Predelay'):gsub('^(XLFO %d) Freq', '%1 Frequency')
            :gsub('^EG 1', 'EG Main'):gsub('^MS (%d+)', 'MIDI Source %1')
        local p = byName[n:lower()]
        if p then S.P2T[p] = t end
    end
end

-- value lists by the end of the param's name
U.LS = {
    { 'Master Scale', "32'", "16'", "8'", "4'" },
    { ' Scale', '-1 octaves', '0 octaves', '1 octave', '2 octaves', '3 octaves' },
    { 'Wave Form', 'Sawtooth', 'Square', 'Square Pure', 'Triangle', 'Triangle Pure', 'Sine', 'White Noise', 'Pink Noise' },
    { ' Style', 'Classic', 'Gentle', 'Raw', 'Tube', 'Metal', 'Easy Going', 'Smooth', 'Hard', 'Hollow', 'Extreme', 'Clean' },
    { ' Shape', 'Low Pass', 'High Pass', 'Band Pass', 'Bell', 'Low Shelf', 'High Shelf', 'Notch' },
    { ' Slope', '6 dB/oct', '12 dB/oct', '24 dB/oct', '48 dB/oct' },
    { 'Delay Filter Routing', 'Serial', 'Parallel', 'Per Delay' },
    { 'Filter Routing', 'Serial', 'Parallel', 'Per Oscillator' },
    { 'Ping Pong', 'Ping Pong Off', 'Ping Pong L-R', 'Ping Pong R-L' },
    { 'Chorus Mode', 'Single', 'Double' },
    { 'Phaser Mode', 'Phaser', 'Flanger' },
    { 'Sync Mode', 'Free', '16', '8', '4', '2', '1', '1/2', '1/4', '1/8', '1/16', '1/32', '1/64' },
    { ' Sync', 'Free', '1/2 Note', '1/4 Note', '1/8 Note', '1/16 Note' },
    { 'MIDI Trigger', 'Off', 'Retrigger', 'Legato' },
    { 'Glide function', 'Linear', 'Sqr', 'Sqrt', 'Sine' },
    { ' Triggering', 'Side Chain', 'MIDI' },
    { ' Input', 'Mod Wheel', 'Pitch Bend', 'Velocity', 'Aftertouch', 'KB Track', 'Controller' },
    { 'Response Curve', 'Linear', 'Exp', 'Log', 'Sqr', 'Sqrt', 'Sine' },
    { 'Transpose', 'Off', '1 Octave', '2 Octaves' },
    { 'Note Order', 'Up', 'Down', 'Up/Down', 'As Played', 'Random' },
    { 'Latch', 'Off', 'Held', 'Full' },
    { 'Polyphony', 'Mono', 'Poly', 'Per Oscillator' },
    { 'Mode', 'Envelope', 'Transient' },
}
function U.Items(p, n)
    local c = S.Lists[p]
    if c then return c end
    c = {}
    local nm, L = D.Names[p] or ''
    if nm:find('^XY') then
        L = nm:find('Mode$') and { 0, 'Slider', 'XY' } or { 0, 'Positive (0 ... 1)', 'Centered (-1 ... 1)' }
    elseif nm:find('^MIDI Source') and nm:find('Range$') then
        L = { 0, 'Negative (-1 ... 0)', 'Centered (-1 ... 1)', 'Positive (0 ... 1)' }
    else
        for _, q in ipairs(U.LS) do
            if nm:sub(-#q[1]) == q[1] or (q[1] == 'Ping Pong' and nm:find(q[1], 1, true)) then L = q break end
        end
    end
    for k = 0, n do c[#c + 1] = { L and L[k + 2] or tostring(k), k / n } end
    S.Lists[p] = c
    return c
end

-- the sources' names (a "CuSV" block in the plugin's state)
function U.ReadNames()
    local ok, b64 = r.TrackFX_GetNamedConfigParm(LT_Track, PluginScript.FX_Idx, 'vst_chunk')
    if not ok or not b64 then return end
    local map, out = {}, {}
    local abc = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    for i = 1, 64 do map[abc:byte(i)] = i - 1 end
    local acc, bits = 0, 0
    for i = 1, #b64 do
        local v = map[b64:byte(i)]
        if v then
            acc, bits = (acc << 6) | v, bits + 6
            if bits >= 8 then
                bits = bits - 8
                out[#out + 1] = string.char((acc >> bits) & 255)
                acc = acc & ((1 << bits) - 1)
            end
        end
    end
    local b = table.concat(out)
    local o = b:find('CuSV', 1, true)
    if not o then return end
    local names, pos = {}, o + 8
    local cnt = string.unpack('<I4', b, pos)
    pos = pos + 4
    for _ = 1, cnt do
        if pos + 4 > #b then break end
        local kl = string.unpack('<I4', b, pos)
        local key = b:sub(pos + 4, pos + 3 + kl)
        pos = pos + 4 + kl
        local vl = string.unpack('<I4', b, pos)
        names[key] = b:sub(pos + 4, pos + 3 + vl)
        pos = pos + 4 + vl
    end
    S.Names = names
end

function U.SrcKind(s)
    for i = #KORDER, 1, -1 do
        local q = K[KORDER[i]]
        if s > q.src0 then
            local k = s - q.src0
            if q.pair then k = (k + 1) // 2 end
            return KORDER[i], k
        end
    end
end
function U.SrcClr(s) local kd = U.SrcKind(s) return kd and K[kd].clr or T.Mute end
function U.XYPos(b, o) -- 0..1 on screen; a Positive (0 ... 1) controller uses the upper half of the param
    if On(b + 3) then return G(b + o) end
    return max(0, G(b + o) * 2 - 1)
end
function U.XYSet(b, o, u)
    u = max(0, min(1, u))
    St(b + o, On(b + 3) and u or (u + 1) / 2)
end
function U.SrcLabel(kd, k)
    local nm = S.Names[K[kd].name .. k]
    if nm and nm ~= '' then return (nm:gsub('%s%s+', '  ')) end
    if kd == 'eg' and k == 1 then return 'EG Main' end
    if kd == 'midi' then return D:Fmt(U.B('midi', k) + 1) end
    return K[kd].name .. ' ' .. k
end
function U.SrcName(s)
    local kd, k = U.SrcKind(s)
    if not kd then return '-' end
    local nm = U.SrcLabel(kd, k)
    if K[kd].pair and On(U.B('xy', k) + 2) then nm = nm .. ((s - 1) % 2 == 0 and ' X' or ' Y') end
    return nm
end

---------------------------------------------------------------------------------------------
-- slots
function U.NSlots() return I(787, 100) end
function U.Scan()
    S.Mods, S.BySrc = {}, {}
    for i = 0, U.NSlots() - 1 do
        local s, t = I(SLOT0 + 5 * i, NSRC), I(SLOT0 + 4 + 5 * i, NTGT)
        if s > 0 and t > 0 then
            S.Mods[t] = S.Mods[t] or {}
            table.insert(S.Mods[t], { i = i, s = s })
            S.BySrc[s] = S.BySrc[s] or {}
            table.insert(S.BySrc[s], { i = i, t = t })
        end
    end
end
function U.ReadSlots()
    local L = {}
    for i = 0, U.NSlots() - 1 do
        local b = SLOT0 + 5 * i
        L[#L + 1] = { s = I(b, NSRC), v = G(b + 1), byp = G(b + 2), inv = G(b + 3), t = I(b + 4, NTGT) }
    end
    return L
end
function U.WriteSlots(L)
    for i, q in ipairs(L) do
        local b = SLOT0 + 5 * (i - 1)
        St(b, q.s / NSRC); St(b + 1, q.v); St(b + 2, q.byp); St(b + 3, q.inv); St(b + 4, q.t / NTGT)
    end
    St(787, #L / 100)
    S.ModT = 0
end
function U.AddSlot(s, t)
    local n = U.NSlots()
    if n >= 100 or not t then return end
    local b = SLOT0 + 5 * n
    St(b, s / NSRC); St(b + 1, 0.5); St(b + 2, 0); St(b + 3, 0); St(b + 4, t / NTGT)
    St(787, (n + 1) / 100)
    S.ModT = 0
end
function U.DelSlot(i) -- i from 0; slots that modulate a later slot's level follow it
    local L, O = U.ReadSlots(), {}
    for n, q in ipairs(L) do
        if n - 1 ~= i then
            if q.t >= 200 then
                local tn = q.t - 200
                if tn > i then q.t = q.t - 1 end
                if tn ~= i then O[#O + 1] = q end
            else O[#O + 1] = q end
        end
    end
    U.WriteSlots(O)
end

function U.AddSource(kd)
    local c = U.Cnt(kd)
    if c >= K[kd].n then return end
    U.SetCnt(kd, c + 1)
    S.View = { kd, c + 1 }
end
function U.DelSource(kd, k)
    local q, c = K[kd], U.Cnt(kd)
    if c <= q.fx then return end
    for j = k + 1, c do
        local from, to = U.B(kd, j), U.B(kd, j - 1)
        for o = 0, q.size - 1 do St(to + o, G(from + o)) end
    end
    local sl, sh = q.src0, q.pair and 2 or 1
    local a0, a1 = sl + sh * (k - 1) + 1, sl + sh * k
    local O = {}
    for _, m in ipairs(U.ReadSlots()) do
        local keep = true
        if m.s >= a0 and m.s <= a1 then keep = false
        elseif m.s > a1 and m.s <= sl + sh * q.n then m.s = m.s - sh end
        if q.tgt0 and m.t > q.tgt0 + q.tn * (k - 1) and m.t <= q.tgt0 + q.tn * q.n then
            if m.t <= q.tgt0 + q.tn * k then keep = false else m.t = m.t - q.tn end
        end
        if keep then O[#O + 1] = m end
    end
    U.WriteSlots(O)
    U.SetCnt(kd, c - 1)
    S.View = nil
end

---------------------------------------------------------------------------------------------
-- drawing
local ANG0, ANG1 = pi * 0.75, pi * 2.25
function U.Arc(x, y, rad, a0, a1, c, th)
    if a1 - a0 < 0.01 then return end
    im.DrawList_PathArcTo(DL, X + x, Y + y, rad, a0, a1)
    im.DrawList_PathStroke(DL, c, nil, th)
end
function U.Tgt(p, x0, y0, x1, y1)
    local t = S.P2T[p]
    if t then S.Rects[#S.Rects + 1] = { t, x0, y0, x1, y1 } end
end
function U.Rd(p) S.RdP = p end
function U.Label(x, y, s, c, sz) D:Text(x, y, c or T.Txt, s, sz or 8, 'c', true) end

-- coloured dots of what modulates target t; a click lists the slots
function U.ModDots(t, x, y)
    local L = t and S.Mods[t]
    if not L then return end
    local n = min(#L, 4)
    local cl = D:Btn('md' .. t, x - 4, y - 4, n * 6 + 3, 8)
    for i = 1, n do Circ(x + (i - 1) * 6, y, 2.7, U.SrcClr(L[i].s)) end
    if cl then S.Pop = { t = t } end
end

function U.Knob(p, cx, cy, rad, o)
    o = o or {}
    local v, t = G(p), S.P2T[p]
    local mods = t and S.Mods[t]
    local c = o.clr or (mods and U.SrcClr(mods[1].s)) or T.Gold
    if o.dim then c = A(c, 0.35) end
    local rr, th = rad + 3.5, rad >= 14 and 3 or 2.4
    if not o.noArc then U.Arc(cx, cy, rr, ANG0, ANG1, 0xFFFFFF10, th) end
    local a = ANG0 + (ANG1 - ANG0) * v
    if o.noArc then
    elseif o.bi then
        local m = (ANG0 + ANG1) / 2
        U.Arc(cx, cy, rr, min(a, m) - 0.05, max(a, m) + 0.05, c, th)
    else U.Arc(cx, cy, rr, ANG0, a, c, th) end
    Circ(cx, cy + 1, rad + 0.5, 0x00000060)
    Circ(cx, cy, rad, D:Lit(p) and T.TileHi or T.KnobLo)
    Circ(cx, cy - 0.6, rad - 2, D:Lit(p) and 0x3D3840FF or T.Knob)
    Ring(cx, cy, rad - 0.4, T.Rim, 1)
    if not o.noPtr then
        local cs, sn = math.cos(a), math.sin(a)
        if o.dot then Circ(cx + cs * (rad - 4), cy + sn * (rad - 4), 2.2, 0xF2F0F4FF)
        else Lin(cx + cs * rad * 0.35, cy + sn * rad * 0.35, cx + cs * (rad - 2.5), cy + sn * (rad - 2.5), T.Hi, 1.6) end
    end
    if o.label then U.Label(cx, cy + rr + 3, o.label, D:Lit(p) and T.Hi or T.Txt) end
    D:PrmKnob(p, cx, cy, rad + 2, o.label or D.Names[p])
    U.Tgt(p, cx - rad - 3, cy - rad - 3, cx + rad + 3, cy + rad + 3)
    if D:Lit(p) then U.Rd(p) end
    if not o.noDots then U.ModDots(t, cx + rad * 0.55, cy + rad + 1) end
end

-- popups in the plugin's colours
function U.PopBegin(name)
    im.PushStyleColor(ctx, im.Col_PopupBg, 0x241F27F8)
    im.PushStyleColor(ctx, im.Col_Border, 0xFFFFFF22)
    im.PushStyleColor(ctx, im.Col_Header, 0xFFD23C30)
    im.PushStyleColor(ctx, im.Col_HeaderHovered, 0xFFFFFF18)
    im.PushStyleColor(ctx, im.Col_HeaderActive, 0xFFD23C50)
    im.PushStyleVar(ctx, im.StyleVar_PopupRounding, 7)
    im.PushStyleVar(ctx, im.StyleVar_WindowPadding, 7, 7)
    local op = im.BeginPopup(ctx, name)
    if not op then U.PopEnd(true) end
    return op
end
function U.PopEnd(closed)
    if not closed then im.EndPopup(ctx) end
    im.PopStyleVar(ctx, 2)
    im.PopStyleColor(ctx, 5)
end

function U.Menu(id, p, n, x, y, w, h, o)
    o = o or {}
    local c, hov = D:Btn(id, x, y, w, h)
    local cur = D:Fmt(p)
    if not o.bare then
        D:Rect(x, y, w, h, hov and T.TileHi or T.Tile, 3)
        D:Rect(x, y, w, h, T.Line, 3, false)
        D:Text(x + 5, y + (h - 9) / 2, T.Hi, o.value or cur, 8, nil, true)
        local cx, cy = X + x + w - 6, Y + y + h / 2
        im.DrawList_AddTriangleFilled(DL, cx - 2.5, cy - 1.5, cx + 2.5, cy - 1.5, cx, cy + 2, T.Mute)
    end
    if hov then U.Rd(p) end
    local pop = 'twM' .. id
    if c then im.OpenPopup(ctx, pop) end
    if U.PopBegin(pop) then
        for i, it in ipairs(U.Items(p, n)) do
            if im.Selectable(ctx, it[1] .. '##v' .. i, I(p, n) == i - 1) then St(p, it[2]) end
        end
        for i, e in ipairs(o.extra or {}) do
            if im.Selectable(ctx, e[1] .. '##x' .. i, false) then e[2]() end
        end
        U.PopEnd()
    end
    return hov
end

function U.TBtn(id, x, y, w, h, s, on, sz)
    local c, hov = D:Btn(id, x, y, w, h)
    D:Rect(x, y, w, h, on and A(T.Gold, 0.18) or (hov and T.TileHi or T.Tile), 3)
    D:Rect(x, y, w, h, on and A(T.Gold, 0.6) or T.Line, 3, false)
    D:Text(x + w / 2, y + (h - 9) / 2, on and T.Hi or T.Txt, s, sz or 8, 'c', true)
    return c
end
function U.Toggle(id, p, x, y, w, h, s)
    if U.TBtn(id, x, y, w, h, s, On(p)) then St(p, On(p) and 0 or 1) end
    U.Tgt(p, x, y, x + w, y + h)
end
function U.Power(id, p, cx, cy, rad)
    local c, hov = D:Btn(id, cx - rad - 1, cy - rad - 1, rad * 2 + 2, rad * 2 + 2)
    local on = On(p)
    if c then St(p, on and 0 or 1) end
    local col = on and T.Gold or (hov and T.Txt or T.Mute)
    U.Arc(cx, cy, rad - 1, -pi * 0.28, pi * 1.28, col, 1.3)
    Lin(cx, cy - rad + 0.5, cx, cy, col, 1.3)
end
-- a value dragged up / down
function U.Drag(id, p, x, y, w, h, scale, draw)
    local _, hov, act = D:Btn(id, x, y, w, h)
    if act then
        local _, dy = im.GetMouseDelta(ctx)
        if dy ~= 0 then St(p, G(p) - dy * (scale or 0.005)) end
    end
    if hov or act then U.Rd(p) end
    U.Tgt(p, x, y, x + w, y + h)
    if draw then draw(hov or act) end
    return hov or act
end
function U.Close(id, x, y)
    local c, hov = D:Btn(id, x, y, 11, 11)
    local col = hov and T.Hi or T.Mute
    Lin(x + 2, y + 2, x + 9, y + 9, col, 1.3); Lin(x + 9, y + 2, x + 2, y + 9, col, 1.3)
    return c
end
function U.Back(id, x, y, fwd)
    local c, hov = D:Btn(id, x, y, 13, 11)
    local col = hov and T.Hi or T.Mute
    local a, e = fwd and 1 or 5, fwd and 5 or 1
    for o = 0, 4, 4 do
        Lin(x + a + o, y + 1, x + e + o, y + 5.5, col, 1.5); Lin(x + e + o, y + 5.5, x + a + o, y + 10, col, 1.5)
    end
    return c
end

function U.Path(pts, c, th)
    for _, q in ipairs(pts) do im.DrawList_PathLineTo(DL, X + q[1], Y + q[2]) end
    im.DrawList_PathStroke(DL, c, nil, th or 1)
end
-- tuning fork
function U.Fork(x, y, c)
    Lin(x, y + 1, x, y + 7, c, 1.3)
    U.Path({ { x - 3, y - 6 }, { x - 3, y - 1 }, { x, y + 1.5 }, { x + 3, y - 1 }, { x + 3, y - 6 } }, c, 1.3)
end
-- oscillator sync
function U.Zig(x, y, c)
    U.Path({ { x - 7, y + 4 }, { x - 2, y - 4 }, { x - 2, y + 4 }, { x + 3, y - 4 }, { x + 3, y + 4 }, { x + 7, y - 2 } }, c, 1.2)
end
function U.Note(x, y, c)
    Circ(x - 2, y + 4, 2, c); Lin(x, y + 4, x, y - 4, c, 1.2)
    Lin(x, y - 4, x + 4, y - 2, c, 1.2)
end
function U.Dots(x, y, c)
    for i = -2, 2 do Circ(x + i * 2.8, y + abs(i) * 0.9, 0.95, c) end
end

-- oscillator wave shapes, t in 0..1 -> -1..1
function U.Wave(w, t)
    t = t % 1
    if w <= 0 then return 2 * t - 1 end
    if w <= 2 then return t < 0.5 and 1 or -1 end
    if w <= 4 then return t < 0.5 and 4 * t - 1 or 3 - 4 * t end
    if w == 5 then return math.sin(t * 2 * pi) end
    local n = t * 53.1
    return (math.sin(n * 2.3) + math.sin(n * 7.9 + 1) + math.sin(n * 13.3 + 2)) / 3
end

-- the oscillator's wave: a card per wave, drawn, with its name
function U.WaveMenu(i, b, extra)
    local pop = 'twWave' .. i
    local c, hov = D:Btn('owv' .. i, 4, 27 + 54 * (i - 1) - 17, 30, 16)
    if hov then U.Rd(b + 2) end
    if c then im.OpenPopup(ctx, pop) end
    if not U.PopBegin(pop) then return end
    local dl = im.GetWindowDrawList(ctx)
    local x0, y0 = im.GetCursorScreenPos(ctx)
    local cw, ch, cur = 114, 36, I(b + 2, 7)
    for k, it in ipairs(U.Items(b + 2, 7)) do
        local cx, cy = x0 + ((k - 1) % 2) * (cw + 4), y0 + ((k - 1) // 2) * (ch + 4)
        im.SetCursorScreenPos(ctx, cx, cy)
        local picked = im.InvisibleButton(ctx, '##wv' .. k, cw, ch)
        local on, lit = cur == k - 1, im.IsItemHovered(ctx)
        im.DrawList_AddRectFilled(dl, cx, cy, cx + cw, cy + ch, on and 0xFFD23C22 or (lit and 0xFFFFFF14 or 0xFFFFFF08), 5)
        if on then im.DrawList_AddRect(dl, cx, cy, cx + cw, cy + ch, 0xFFD23C90, 5) end
        local col = (on or lit) and T.Gold or 0xC8B47AFF
        for n = 0, 40 do
            local t = n / 40
            im.DrawList_PathLineTo(dl, cx + 8 + t * 32, cy + ch / 2 - U.Wave(k - 1, t * (k > 6 and 1 or 2)) * 9)
        end
        im.DrawList_PathStroke(dl, col, nil, 1.5)
        im.DrawList_AddTextEx(dl, Font_SemiBold_9 or Font_Andale_Mono_9, 9, cx + 46, cy + ch / 2 - 5, (on or lit) and T.Hi or T.Txt, it[1])
        if picked then St(b + 2, it[2]); im.CloseCurrentPopup(ctx) end
    end
    im.SetCursorScreenPos(ctx, x0, y0 + 4 * (ch + 4))
    if extra then
        if im.Selectable(ctx, 'Remove oscillator##rm', false, nil, cw * 2 + 4) then extra() end
    else im.Dummy(ctx, cw * 2 + 4, 1) end
    U.PopEnd()
end

---------------------------------------------------------------------------------------------
-- oscillators
function U.Osc(i)
    local b, cy = 2 + 10 * (i - 1), 27 + 54 * (i - 1)
    if not On(b + 9) then
        if S.PlusDone then return end
        S.PlusDone = true
        local c, hov = D:Btn('oadd' .. i, 66, cy - 9, 18, 18)
        local col = hov and T.Hi or T.Mute
        Lin(69, cy, 81, cy, col, 2); Lin(75, cy - 6, 75, cy + 6, col, 2)
        if c then St(b + 9, 1); St(b + 8, 1) end
        return
    end
    local en, w = On(b + 8), I(b + 2, 7)
    local amb = en and T.Gold or T.Dim
    -- the wave behind the row
    local pts = {}
    for n = 0, 60 do pts[#pts + 1] = { 6 + n * 1.72, cy - 9 - U.Wave(w, n / 60 * 3) * 15 } end
    U.Path(pts, 0xFFFFFF1E, 1.4)
    Lin(6, cy - 9, 118, cy - 9, 0xFFFFFF10, 1)
    -- wave icon: menu of the plugin's waves
    local ic = {}
    for n = 0, 24 do ic[#ic + 1] = { 7 + n, cy - 9 - U.Wave(w, n / 24) * 5 } end
    U.Path(ic, amb, 1.3)
    local used = 0
    for q = 0, 3 do if On(2 + 10 * q + 9) then used = used + 1 end end
    U.WaveMenu(i, b, used > 1 and function() St(b + 9, 0) end or nil)
    U.Power('oen' .. i, b + 8, 19, cy + 13, 5.5)
    local pw = w == 1 or w == 2
    local fx, sx = pw and 77 or 62, pw and 107 or 96
    local dim = not en
    if pw then
        U.Knob(b + 4, 46, cy - 9, 10, { noPtr = true, dim = dim })
        U.Path({ { 40, cy - 6 }, { 44, cy - 6 }, { 44, cy - 13 }, { 49, cy - 13 }, { 49, cy - 6 }, { 52, cy - 6 } }, amb, 1.1)
    end
    U.Knob(b, fx, cy - 9, 10, { noPtr = true, bi = true, dim = dim })
    U.Fork(fx, cy - 9, amb)
    U.Knob(b + 3, sx, cy - 9, 10, { noPtr = true, dim = dim })
    U.Zig(sx, cy - 9, amb)
    -- footage: the master scale's foot divided by the oscillator's octave
    local feet = 32 / 2 ^ (I(1, 3) + I(b + 1, 4) - 1)
    local ft = feet >= 1 and floor(feet) .. "'" or '1/' .. floor(1 / feet) .. "'"
    if U.Menu('oscl' .. i, b + 1, 4, fx - 13, cy + 7, 26, 12, { bare = true }) then U.Rd(b + 1) end
    D:Text(fx, cy + 8, amb, ft, 9, 'c', true)
    local ph = On(b + 7)
    local c = D:Btn('oph' .. i, sx - 9, cy + 7, 18, 10)
    if c then St(b + 7, ph and 0 or 1) end
    U.Dots(sx, cy + 11, ph and T.Gold or T.Mute)
    -- level, with the pan around it
    local lx, ly = 134, cy
    U.Knob(b + 5, lx, ly, 15, { dot = true, dim = dim, noDots = true, noArc = true })
    local pan = ANG0 + (ANG1 - ANG0) * G(b + 6)
    Ring(lx, ly, 20, 0xFFFFFF16, 1)
    Circ(lx + math.cos(pan) * 17.5, ly + math.sin(pan) * 17.5, 1.4, en and 0x8A8790FF or T.Mute)
    D:PrmKnob(b + 6, lx, ly, 21, 'Pan')
    U.Tgt(b + 6, lx - 21, ly - 21, lx + 21, ly - 15)
    if D:Lit(b + 6) then U.Rd(b + 6) end
    U.ModDots(S.P2T[b + 5], lx + 9, ly + 15)
    U.ModDots(S.P2T[b + 6], lx - 22, ly + 15)
end
function U.Rings()
    for n = 1, 2 do
        local p, cy = 41 + n, 54 * n
        local c, hov = D:Btn('ring' .. n, 127, cy - 7, 14, 14)
        local on, col = On(p), On(p) and T.Gold or (hov and T.Txt or A(T.Mute, 0.6))
        if c then St(p, on and 0 or 1) end
        for a = 0, 2 do
            local an = a * pi / 3
            local dx, dy = math.cos(an) * 4.5, math.sin(an) * 4.5
            Lin(134 - dx, cy - dy, 134 + dx, cy + dy, col, 1.4)
        end
        if hov then U.Rd(p) end
    end
end

---------------------------------------------------------------------------------------------
-- the filter display (the main filters and the delay's)
function U.Resp(q, x)
    local d, n, pk = (x - q.f) * 13.94, q.n, q.p
    local function LP(e) return -10 * e * log(1 + 2 ^ (2 * d), 10) end
    local function HP(e) return -10 * e * log(1 + 2 ^ (-2 * d), 10) end
    local bump = pk * 20 * exp(-(d / 0.4) ^ 2)
    if q.s == 0 then return LP(n) + bump end
    if q.s == 1 then return HP(n) + bump end
    if q.s == 2 then return LP(n / 2) + HP(n / 2) + bump end
    if q.s == 3 then return pk * 24 * exp(-(d / 0.8) ^ 2) end
    if q.s == 4 then return pk * 24 / (1 + 2 ^ (2.5 * d)) end
    if q.s == 5 then return pk * 24 / (1 + 2 ^ (-2.5 * d)) end
    return -36 * exp(-(d / (0.12 + 0.4 * (1 - abs(pk)))) ^ 2)
end

function U.FilterDisplay(id, base, rout, x, y, w, h)
    D:Rect(x, y, w, h, 0xFFFFFF05, 4)
    local yz, sc = y + h * 0.42, h * 0.42 / 26
    for o = 1, 12 do
        local gx = x + w * o / 13
        Lin(gx, y + 1, gx, y + h - 1, T.Grid, 1)
    end
    Lin(x, yz, x + w, yz, 0xFFD23C40, 1)
    local F = {}
    for i = 1, 4 do
        local b = base + 8 * (i - 1)
        if On(b + 7) then
            F[#F + 1] = { i = i, b = b, f = G(b), p = G(b + 2) * 2 - 1, s = I(b + 4, 6), n = 2 ^ I(b + 5, 3), en = On(b + 6) }
        end
    end
    local par = I(rout, 2) ~= 0
    local tot, prev = {}, nil
    for n = 0, 72 do tot[n] = 0 end
    for _, q in ipairs(F) do
        local pts = {}
        for n = 0, 72 do
            local db = q.en and U.Resp(q, n / 72) or 0
            if yz - db * sc < y + h then pts[#pts + 1] = { x + w * n / 72, max(y + 1, yz - db * sc) } end
            if par then tot[n] = tot[n] + 10 ^ (db / 10) / #F else tot[n] = tot[n] + db end
        end
        U.Path(pts, 0xFFD23C50, 1)
    end
    local pts = {}
    for n = 0, 72 do
        local db = par and #F > 0 and 10 * log(max(tot[n], 1e-9), 10) or tot[n]
        local px, py = x + w * n / 72, max(y + 1, yz - db * sc)
        if py < y + h then
            pts[#pts + 1] = { px, py }
            if prev and #F > 0 then
                im.DrawList_AddQuadFilled(DL, X + prev[1], Y + prev[2], X + px, Y + py, X + px, Y + y + h, X + prev[1], Y + y + h, 0xFFD23C10)
            end
            prev = { px, py }
        else prev = nil end
    end
    if #F > 0 then U.Path(pts, T.Gold, 2) end
    -- nodes: drawn here, hit below, so the value box sits on top
    for _, q in ipairs(F) do
        q.x, q.y = x + w * q.f, max(y + 7, min(y + h - 7, yz - q.p * h * 0.38))
        Lin(q.x, q.y, q.x, max(q.y, yz), 0xFFD23C60, 1)
        local on = S.Sel[id] == q.i
        if on then Circ(q.x, q.y, 8.5, T.Hi) end
        Circ(q.x, q.y, 6.5, q.en and T.Gold or T.Dim)
        D:Text(q.x, q.y - 5, 0x1A1A1AFF, tostring(q.i), 9, 'c', true)
    end
    local sel = S.Sel[id]
    if sel then
        local b = base + 8 * (sel - 1)
        if On(b + 7) then U.Bubble(id, b, sel, x, y, w) else S.Sel[id] = nil end
    end
    for _, q in ipairs(F) do
        local c, hov, act = D:Btn(id .. 'n' .. q.i, q.x - 7, q.y - 7, 14, 14)
        if act then
            local dx, dy = im.GetMouseDelta(ctx)
            if dx ~= 0 then St(q.b, q.f + dx / w) end
            if dy ~= 0 then St(q.b + 2, G(q.b + 2) - dy / (h * 1.52)) end
            S.Sel[id] = q.i
        end
        if c then S.Sel[id] = q.i end
        if hov or act then U.Rd(q.b) end
        U.Tgt(q.b, q.x - 7, q.y - 7, q.x + 7, q.y + 7)
        U.ModDots(S.P2T[q.b], q.x - 6, q.y + 11)
    end
    local c, hov = D:Btn(id .. 'bg', x, y, w, h)
    if c then S.Sel[id] = nil end
    if hov and im.IsMouseDoubleClicked(ctx, 0) then
        local mx, my = Mouse()
        for i = 1, 4 do
            local b = base + 8 * (i - 1)
            if not On(b + 7) then
                St(b + 7, 1); St(b + 6, 1); St(b, (mx - x) / w)
                St(b + 2, 0.5 + (yz - my) / (h * 0.76))
                S.Sel[id] = i
                break
            end
        end
    end
end

function U.Bubble(id, b, sel, x, y, w)
    local bw, bh = 122, 66
    local bx, by = x + w - bw - 3, y + 3
    D:Rect(bx, by, bw, bh, 0x2B262CF4, 5)
    D:Rect(bx, by, bw, bh, 0xFFFFFF20, 5, false)
    U.Power(id .. 'pw', b + 6, bx + 11, by + 11, 5.5)
    local function Fld(k, p, fy, s)
        U.Drag(id .. k, p, bx + 21, fy, 87, 11, 0.003, function(l) D:Text(bx + 23, fy + 1, l and T.Hi or T.Txt, s, 8, nil, true) end)
    end
    Fld('fq', b, by + 4, D:Fmt(b))
    Fld('pk', b + 2, by + 16, 'Peak ' .. D:Fmt(b + 2))
    Fld('pn', b + 1, by + 28, 'Pan ' .. D:Fmt(b + 1))
    U.Menu(id .. 'sh', b + 4, 6, bx + 3, by + 41, 62, 11)
    U.Menu(id .. 'sl', b + 5, 3, bx + 67, by + 41, 52, 11)
    U.Menu(id .. 'st', b + 3, 10, bx + 3, by + 53, 72, 11)
    if U.Close(id .. 'cl', bx + bw - 13, by + 2) then S.Sel[id] = nil end
    if U.TBtn(id .. 'rm', bx + 77, by + 53, 42, 11, 'Remove', false, 8) then St(b + 7, 0) end
end

---------------------------------------------------------------------------------------------
-- envelope: times as widths (as the plugin's own display), slopes as curves
local function Slope(t, s) return t ^ (2 ^ (-2 * s)) end
function U.EgShape(b)
    local ws = { G(b + 1) * 0.15, 0.005 + G(b + 5) * 0.54, 0.005 + G(b + 7) * 0.58, 0.06, 0.06 + G(b + 10) * 0.2, 0.005 + G(b + 11) * 0.8 }
    local sum = 0
    for _, q in ipairs(ws) do sum = sum + q end
    local kk = sum > 1 and 1 / sum or 1
    local xs, xp = { [0] = 0 }, 0
    for i, q in ipairs(ws) do xp = xp + q * kk; xs[i] = xp end
    return xs, G(b + 9), { G(b + 6) * 2 - 1, G(b + 8) * 2 - 1, G(b + 12) * 2 - 1 }, kk
end
function U.EgSegs(xs, sus, sl)
    return {
        { xs[0], xs[1], function() return 0 end },
        { xs[1], xs[2], function(t) return Slope(t, sl[1]) end },
        { xs[2], xs[3], function(t) return 1 - (1 - sus) * Slope(t, sl[2]) end },
        { xs[3], xs[4], function() return sus end },
        { xs[4], xs[5], function() return sus end },
        { xs[5], xs[6], function(t) return sus * (1 - Slope(t, sl[3])) end },
    }
end
function U.EgPath(b, gx, gy, gw, gh)
    local xs, sus, sl = U.EgShape(b)
    local pts = {}
    for _, g in ipairs(U.EgSegs(xs, sus, sl)) do
        for i = 0, 20 do
            local t = (i / 20) ^ 2 -- denser at the start, where the slopes bend most
            pts[#pts + 1] = { gx + (g[1] + (g[2] - g[1]) * t) * gw, gy + gh - g[3](t) * gh }
        end
    end
    return pts
end
function U.EG(id, b, x, y, w, h, letters)
    local clr = K.eg.clr
    local gx, gy, gw, gh = x + 14, y + 8, w - 28, h - 18
    Lin(gx, gy + gh, gx + gw, gy + gh, 0xFFFFFF18, 1)
    local xs, sus, sl, kk = U.EgShape(b)
    local segs = U.EgSegs(xs, sus, sl)
    local function PX(u) return gx + u * gw end
    local function PY(v) return gy + gh - v * gh end
    local pts = U.EgPath(b, gx, gy, gw, gh)
    for i = 2, #pts do
        local a, e = pts[i - 1], pts[i]
        im.DrawList_AddQuadFilled(DL, X + a[1], Y + a[2], X + e[1], Y + e[2], X + e[1], Y + gy + gh, X + a[1], Y + gy + gh, A(clr, 0.1))
    end
    U.Path(pts, clr, 2)
    Lin(PX(xs[4]), gy - 4, PX(xs[4]), gy + gh + 4, 0xFFFFFF18, 1)
    local function Pt(tag, ch, px, py, pxp, pyp, sx)
        local c1, hov, act = D:Btn(id .. tag, px - 6, py - 6, 12, 12)
        if act then
            local dx, dy = im.GetMouseDelta(ctx)
            if pxp and dx ~= 0 then St(pxp, G(pxp) + dx / (gw * sx * kk)) end
            if pyp and dy ~= 0 then St(pyp, G(pyp) - dy / gh) end
        end
        if hov or act then U.Rd(pxp or pyp) end
        if pxp then U.Tgt(pxp, px - 6, py - 6, px + 6, py + 6) elseif pyp then U.Tgt(pyp, px - 6, py - 6, px + 6, py + 6) end
        Circ(px, py, letters and 5.5 or 3.8, (hov or act) and 0x5A5E6AFF or 0x3A3D47FF)
        Ring(px, py, letters and 5.5 or 3.8, (hov or act) and T.Hi or 0xC8D4E8FF, 1)
        if letters then D:Text(px, py - 4.5, T.Hi, ch, 8, 'c', true) end
    end
    Pt('a', 'A', PX(xs[2]), PY(1), b + 5, nil, 0.54)
    Pt('d', 'D', PX(xs[3]), PY(sus), b + 7, b + 9, 0.58)
    Pt('s', 'S', PX((xs[3] + xs[5]) / 2), PY(sus), nil, b + 9, 0.08)
    Pt('h', 'H', PX(xs[5]), PY(sus), b + 10, nil, 0.2)
    Pt('r', 'R', PX(xs[6]), PY(0), b + 11, nil, 0.8)
    local function SD(tag, g, p)
        local q = segs[g]
        local dx, dy = PX((q[1] + q[2]) / 2), PY(q[3](0.5))
        local _, hov, act = D:Btn(id .. tag, dx - 4, dy - 4, 8, 8)
        if act then local _, my = im.GetMouseDelta(ctx) if my ~= 0 then St(p, G(p) - my / 60) end end
        if hov or act then U.Rd(p) end
        U.Tgt(p, dx - 4, dy - 4, dx + 4, dy + 4)
        Circ(dx, dy, 2.6, (hov or act) and T.Hi or T.Bg2)
        Ring(dx, dy, 2.6, clr, 1.2)
    end
    SD('s1', 2, b + 6); SD('s2', 3, b + 8); SD('s3', 6, b + 12)
end

-- a source's drag dot; the ring shows its level
function U.SrcDot(id, s, cx, cy, rad, lvl)
    local c, hov, act = D:Btn(id, cx - rad - 3, cy - rad - 3, rad * 2 + 6, rad * 2 + 6)
    local col = U.SrcClr(s)
    Circ(cx, cy, rad + 3, 0x0E0D10FF)
    if lvl then
        local v = min(abs(G(lvl) * 2 - 1), 1)
        U.Arc(cx, cy, rad + 2, -pi / 2, -pi / 2 + 2 * pi * v, col, 1.6)
    end
    Circ(cx, cy, rad, (hov or act) and col or A(col, 0.75))
    Circ(cx, cy, rad * 0.35, 0x0E0D10FF)
    if act then S.DotAct = true end
    if act and im.IsMouseDragging(ctx, 0, 3) then S.Drag = s end
    if c and not S.Drag then S.Pop = { s = s } end
end

---------------------------------------------------------------------------------------------
-- the FX
U.FXS = {
    Reverb = { en = 81, amt = 82, x = 589, y = 30, k = { { 83, 'TIME' }, { 84, 'BRIGHT' }, { 85, 'PREDELAY' } } },
    Delay = { en = 86, amt = 87, x = 651, y = 30, k = {} },
    Chorus = { en = 127, amt = 128, x = 589, y = 104, k = { { 130, 'RATE' }, { 131, 'DEPTH' }, { 132, 'DELAY' } }, m = { 129, 1 } },
    Phaser = { en = 133, amt = 134, x = 651, y = 104, k = { { 136, 'RATE' }, { 137, 'DEPTH' }, { 138, 'FEEDBACK', true }, { 139, 'SHIFT' } }, m = { 135, 1 } },
    Drive = { en = 140, amt = 141, x = 589, y = 178, k = {}, noPanel = true },
    Compress = { en = 143, amt = 144, x = 651, y = 178, k = { { 146, 'THRESHOLD' }, { 147, 'ATTACK' }, { 148, 'RELEASE' } } },
}
function U.FX(name, q)
    local cx, cy = q.x, q.y
    local on = On(q.en)
    local oc, oh
    if not q.noPanel then
        oc, oh = D:Btn('fxo' .. name, cx - 7, cy - 6, 14, 12)
        if oc then S.View = nil; S.Fx = S.Closed ~= name and name or nil end
    end
    U.Knob(q.amt, cx, cy, 17, { noPtr = true, dim = not on, noDots = true, clr = 0x8A5CF5FF })
    Circ(cx + 19, cy - 19, 9, 0x231E27FF)
    if not q.noPanel then
        for i = -1, 1 do Circ(cx + i * 3.6, cy, 1.1, on and (oh and T.Hi or T.Txt) or T.Mute) end
    end
    U.Power('fxp' .. name, q.en, cx + 19, cy - 19, 5.5)
    local tw = SFX.TextW(name:upper(), 8, true)
    local c, hov = D:Btn('fxl' .. name, cx - tw / 2 - 2, cy + 23, tw + 12, 11)
    D:Text(cx - 3, cy + 24, S.Fx == name and T.Hi or ((hov or on) and T.Txt or T.Mute), name:upper(), 8, 'c', true)
    if q.noPanel then
        local post = On(142)
        if c then St(142, post and 0 or 1) end
        for i = 0, 2 do Circ(cx + tw / 2 + 1 + i * 3, cy + 28.5, 1.1, (i == 2) == post and T.Gold or T.Mute) end
    else
        if c then S.View = nil; S.Fx = S.Closed ~= name and name or nil end
        local tx, ty = X + cx + tw / 2 + 6, Y + cy + 27
        im.DrawList_AddTriangleFilled(DL, tx - 2.5, ty - 1.5, tx + 2.5, ty - 1.5, tx, ty + 2, T.Mute)
    end
    U.ModDots(S.P2T[q.amt], cx + 10, cy + 18)
end
function U.FXPanel(name, q)
    local px, py, pw, ph = RX, RY, RW, RH
    D:Rect(px, py, pw, ph, T.Panel, 7)
    D:Rect(px, py, pw, ph, 0xFFFFFF18, 7, false)
    U.Power('fxpp', q.en, px + 13, py + 13, 6)
    D:Text(px + 25, py + 8, T.Hi, name:upper(), 9, nil, true)
    if U.Close('fxpc', px + pw - 16, py + 5) then S.Fx = nil return end
    if name == 'Delay' then
        U.FilterDisplay('dl', 95, 94, px + 8, py + 22, pw - 16, 88)
        U.Menu('dlr', 94, 2, px + 80, py + 7, 78, 13)
        U.Knob(88, px + 32, py + 138, 14, { label = 'TIME', dim = I(91, 4) ~= 0 })
        U.Knob(89, px + 84, py + 138, 14, { label = 'L / R', bi = true })
        U.Knob(90, px + 136, py + 138, 14, { label = 'OFFSET', bi = true })
        U.Knob(92, px + 188, py + 138, 14, { label = 'FEEDBACK' })
        U.Menu('dls', 91, 4, px + 238, py + 118, 100, 15)
        U.Menu('dlp', 93, 2, px + 238, py + 138, 100, 15)
        return
    end
    local step = (pw - 40) / #q.k
    for i, e in ipairs(q.k) do
        U.Knob(e[1], px + 20 + step * (i - 0.5), py + 86, 22, { label = e[2], bi = e[3] })
    end
    if q.m then U.Menu('fxm', q.m[1], q.m[2], px + 70, py + 7, 92, 14) end
    if name == 'Compress' then U.Toggle('fxag', 145, px + 90, py + 7, 72, 14, 'AUTO GAIN') end
end

---------------------------------------------------------------------------------------------
-- modulation strip
function U.Preview(kd, b, x, ty, w, th)
    local clr = K[kd].clr
    if kd == 'xlfo' then
        U.Path(U.XPts(b, x + 4, ty + th / 2, w - 8, th / 2 - 12, 40), clr, 1.6)
    elseif kd == 'eg' then
        U.Path(U.EgPath(b, x + 6, ty + 14, w - 12, th - 28), clr, 1.6)
    elseif kd == 'ef' then
        local my, am = ty + th / 2, th * 0.25
        U.Path({ { x + 8, my }, { x + 16, my - am }, { x + 24, my - am }, { x + w - 8, my } }, clr, 1.6)
        U.Path({ { x + 8, my }, { x + 16, my + am }, { x + 24, my + am }, { x + w - 8, my } }, clr, 1.6)
    else
        D:Text(x + w / 2, ty + th / 2 - 5, clr, D:Fmt(b + 1):sub(1, floor(w / 5)), 8, 'c', true)
    end
end
function U.Tile(kd, k, x, w, y0)
    local q, b = K[kd], U.B(kd, k)
    local ty, th = y0 + 13, 58
    local s0 = q.src0 + (q.pair and 2 * k - 1 or k)
    local c, hov, lit
    if kd == 'xy' then
        local xy = On(b + 2)
        D:Rect(x, ty, w, th, T.Tile, 7)
        D:Rect(x, ty, w, th, T.Line, 7, false)
        if xy then
            local _, h2, act = D:Btn('xyp' .. k, x, ty, w, th)
            if act then
                local mx, my = Mouse()
                U.XYSet(b, 0, (mx - x) / w); U.XYSet(b, 1, 1 - (my - ty) / th)
            end
            if h2 or act then U.Rd(b + 1) end
            U.Tgt(b + 1, x, ty, x + w, ty + th)
            local px, py = x + 5 + U.XYPos(b, 0) * (w - 10), ty + 5 + (1 - U.XYPos(b, 1)) * (th - 10)
            for i = 3, 1, -1 do Circ(px, py, i * 5, A(q.clr, 0.11)) end
            if On(b + 3) then
                Lin(x + 8, ty + th / 2, x + w - 8, ty + th / 2, 0xFFFFFF14, 1); Lin(x + w / 2, ty + 8, x + w / 2, ty + th - 8, 0xFFFFFF14, 1)
            else
                Lin(x + 5, ty + 8, x + 5, ty + th - 5, 0xFFFFFF18, 1); Lin(x + 5, ty + th - 5, x + w - 8, ty + th - 5, 0xFFFFFF18, 1)
            end
            Circ(px, py, 2, 0xC8FFE0FF)
            D:Text(x + w / 2 - 10, ty + 4, T.Mute, 'X', 8, 'c', true); D:Text(x + w / 2 + 10, ty + 4, T.Mute, 'Y', 8, 'c', true)
            U.SrcDot('xyx' .. k, s0, x + w / 2 - 10, y0 + 6, 4.5, nil)
            U.SrcDot('xyy' .. k, s0 + 1, x + w / 2 + 10, y0 + 6, 4.5, nil)
        else
            local fy = ty + th - 3 - (th - 6) * U.XYPos(b, 1)
            local ym = On(b + 3) and ty + th / 2 or ty + th - 3
            if On(b + 3) then Lin(x + 2, ym, x + w - 2, ym, A(q.clr, 0.5), 1) end
            local a1, a2 = fy < ym and 0.12 or 0.45, fy < ym and 0.45 or 0.12
            im.DrawList_AddRectFilledMultiColor(DL, X + x + 2, Y + min(fy, ym), X + x + w - 2, Y + max(fy, ym), A(q.clr, a1), A(q.clr, a1), A(q.clr, a2), A(q.clr, a2))
            Lin(x + 2, fy, x + w - 2, fy, A(q.clr, 0.8), 1)
            D:PrmSlider(b + 1, x, ty, w, th, U.SrcLabel(kd, k))
            U.Tgt(b + 1, x, ty, x + w, ty + th)
            if D:Lit(b + 1) then U.Rd(b + 1) end
            U.SrcDot('xyv' .. k, s0 + 1, x + w / 2, y0 + 6, 4.5, nil)
        end
        U.ModDots(S.P2T[b + 1], x + 5, ty + th - 6)
        local nm = U.SrcLabel(kd, k)
        c, hov = D:Btn('xyl' .. k, x - 2, ty + th + 1, w + 4, 10)
        D:Text(x + w / 2, ty + th + 2, hov and T.Hi or T.Txt, nm:sub(1, floor((w + 16) / 4.6)), 8, 'c', true)
        if c then U.ViewT({ kd, k }) end
        return
    end
    c, hov = D:Btn('tile' .. kd .. k, x, ty, w, th)
    lit = hov
    D:Rect(x, ty, w, th, lit and T.TileHi or T.Tile, 7)
    D:Rect(x, ty, w, th, T.Line, 7, false)
    U.Preview(kd, b, x, ty, w, th)
    U.SrcDot('src' .. kd .. k, s0, x + w / 2, y0 + 6, 4.5, b)
    local nm = U.SrcLabel(kd, k)
    D:Text(x + w / 2, ty + th + 2, T.Txt, nm:sub(1, 14), 8, 'c', true)
    if c then U.ViewT({ kd, k }) end
end
-- the modulators and macros in place of the main EG; a tile opens its editor over the centre
function U.Mods(x, y, w, h)
    local L, tot = {}, 0
    for _, kd in ipairs(KORDER) do
        for k = 1, U.Cnt(kd) do
            local tw = kd == 'xy' and (On(U.B(kd, k) + 2) and 108 or 28) or 64
            L[#L + 1] = { kd, k, tw }
            tot = tot + tw + 8
        end
    end
    tot = tot + 22
    local maxS = max(0, tot - w)
    if im.IsMouseHoveringRect(ctx, X + x, Y + y, X + x + w, Y + y + h) then
        local wv = im.GetMouseWheel(ctx)
        if wv and wv ~= 0 then S.Scroll = S.Scroll - wv * 30 end
    end
    S.Scroll = max(0, min(S.Scroll, maxS))
    im.PushClipRect(ctx, X + x, Y + y - 1, X + x + w, Y + y + h - 7, true)
    local tx = x - S.Scroll
    for _, e in ipairs(L) do
        if tx + e[3] > x - 8 and tx < x + w then U.Tile(e[1], e[2], tx, e[3], y) end
        tx = tx + e[3] + 8
    end
    local c, hov = D:Btn('srcadd', tx + 1, y + 34, 14, 14)
    local col = hov and T.Hi or T.Mute
    Lin(tx + 2, y + 41, tx + 14, y + 41, col, 2); Lin(tx + 8, y + 35, tx + 8, y + 47, col, 2)
    if c then im.OpenPopup(ctx, 'twAdd') end
    if U.PopBegin('twAdd') then
        for _, kd in ipairs(KORDER) do
            if im.Selectable(ctx, K[kd].name, false) then U.AddSource(kd) end
        end
        U.PopEnd()
    end
    im.PopClipRect(ctx)
    if maxS > 0 then
        local bw = w * w / tot
        local bx = x + S.Scroll / maxS * (w - bw)
        local _, sh, act = D:Btn('scr', x, y + h - 7, w, 7)
        if act then
            local dx = im.GetMouseDelta(ctx)
            S.Scroll = S.Scroll + dx / (w - bw) * maxS
        end
        D:Rect(x, y + h - 5, w, 3, 0xFFFFFF0C, 1.5)
        D:Rect(bx, y + h - 5, bw, 3, (sh or act) and 0xFFFFFF60 or 0xFFFFFF30, 1.5)
    end
end
-- envelope | modulators switch: the shown side is lit
function U.EgSwitch(x, y)
    local cw, h = 21, 14
    local c, hov = D:Btn('egmods', x, y, cw * 2, h)
    if c then S.EgMods = not S.EgMods end
    D:Rect(x, y, cw * 2, h, hov and 0x3A343DFF or T.Tile, 4)
    D:Rect(x, y, cw * 2, h, 0xFFFFFF24, 4, false)
    local ox = S.EgMods and x + cw or x
    D:Rect(ox + 1, y + 1, cw - 2, h - 2, A(T.Gold, 0.25), 3)
    local c1, c2 = S.EgMods and T.Mute or T.Gold, S.EgMods and T.Gold or T.Mute
    U.Path({ { x + 4, y + 11 }, { x + 7, y + 3 }, { x + 11, y + 7 }, { x + 14, y + 7 }, { x + 18, y + 11 } }, c1, 1.3)
    local pts = {}
    for n = 0, 14 do pts[#pts + 1] = { x + cw + 4 + n, y + 7 - math.sin(n / 14 * 2 * pi) * 4 } end
    U.Path(pts, c2, 1.3)
end
function U.ViewT(v)
    S.Fx = nil
    if S.ClosedV == v or S.View == v then S.View = nil else S.View = v end
end

---------------------------------------------------------------------------------------------
-- source editors (they take the place of the strip)
function U.Frame(kd, k, b, s0)
    D:Rect(RX, RY, RW, RH, T.Tile, 8)
    D:Rect(RX, RY, RW, RH, T.Line, 8, false)
    if U.Back('edb', RX + 6, RY + 6) then S.View = nil end
    if s0 then U.SrcDot('eds', s0, RX + 32, RY + 11, 5.5, kd ~= 'xy' and b or nil) end
    if kd then
        D:Text(RX + 44, RY + 6, T.Hi, U.SrcLabel(kd, k), 9, nil, true)
        if U.Cnt(kd) > K[kd].fx and k > K[kd].fx then
            if U.Close('edc', RX + RW - 15, RY + 5) then U.DelSource(kd, k) end
        end
    end
end
-- the XLFO's wave: each step holds, then glides to the next
function U.XPts(b, x, cy, w, amp, res)
    local n = I(b + 9, 15) + 1
    local pts = {}
    for i = 0, res do
        local u = i / res * n
        local st = min(floor(u), n - 1)
        local f = u - st
        local sb = b + 10 + 4 * st
        local nb = b + 10 + 4 * ((st + 1) % n)
        local v, nv = G(sb) * 2 - 1, G(nb) * 2 - 1
        local gl = max(G(sb + 1), 0.001)
        local e = max(0, (f - (1 - gl)) / gl)
        local fn = I(sb + 2, 3)
        if fn == 1 then e = e * e elseif fn == 2 then e = e ^ 0.5 elseif fn == 3 then e = 0.5 - 0.5 * math.cos(e * pi) end
        pts[#pts + 1] = { x + i / res * w, cy - (v + (nv - v) * e) * amp }
    end
    return pts
end
function U.EdXLFO(k)
    local b = U.B('xlfo', k)
    U.Frame('xlfo', k, b, K.xlfo.src0 + k)
    local clr = K.xlfo.clr
    local x0, y0 = RX, RY
    local c1, c2, c3 = x0 + 24, x0 + 66, x0 + 104
    U.Knob(b + 1, c1, y0 + 42, 12, { label = 'RATE', dim = I(b + 6, 11) ~= 0 })
    U.Knob(b + 2, c2, y0 + 42, 10, { label = 'OFFSET', bi = true })
    U.Knob(b + 3, c3, y0 + 42, 10, { label = 'BAL' })
    U.Knob(b + 4, c1, y0 + 96, 10, { label = 'PHASE' })
    U.Knob(b + 5, c2, y0 + 96, 10, { label = 'GLIDE', bi = true })
    U.Knob(b + 0, c3, y0 + 96, 10, { label = 'LEVEL', bi = true })
    U.Menu('xsy', b + 6, 11, x0 + 8, y0 + 130, 50, 14)
    U.Menu('xmt', b + 7, 2, x0 + 62, y0 + 130, 58, 14)
    U.Toggle('xsn', b + 8, x0 + 8, y0 + 150, 112, 14, 'SNAP')
    -- steps
    local gx, gy, gw, gh = x0 + 128, y0 + 22, 130, 154
    D:Rect(gx, gy, gw, gh, T.Bg2, 3)
    Lin(gx, gy + gh / 2, gx + gw, gy + gh / 2, 0xFFFFFF18, 1)
    local n = I(b + 9, 15) + 1
    local sw = gw / n
    S.Step = min(S.Step, n)
    for i = 1, n do
        local sb = b + 10 + 4 * (i - 1)
        local px = gx + sw * (i - 1)
        local vy = gy + gh / 2 - (G(sb) * 2 - 1) * (gh / 2 - 6)
        if i > 1 then Lin(px, gy, px, gy + gh, 0xFFFFFF10, 1) end
        local on = S.Step == i
        D:Rect(px + 1, vy - 5, sw - 2, 10, on and A(clr, 0.35) or 0xFFFFFF18, 2)
        if On(sb + 3) then D:Rect(px + 1, gy + 2, sw - 2, 3, A(clr, 0.6), 1) end
        if sw > 12 then D:Text(px + sw / 2, vy - 5, on and T.Hi or T.Txt, tostring(i), 8, 'c', true) end
        local c, hov, act = D:Btn('xst' .. i, px, gy, sw, gh)
        if act then
            S.Step = i
            local _, my = Mouse()
            St(sb, 0.5 + (gy + gh / 2 - my) / (gh - 12))
        end
        if c then S.Step = i end
        if hov or act then U.Rd(sb) end
    end
    U.Path(U.XPts(b, gx, gy + gh / 2, gw, gh / 2 - 6, 90), clr, 1.6)
    -- the selected step
    local sb = b + 10 + 4 * (S.Step - 1)
    local sx = x0 + 262
    D:Text(sx + 36, y0 + 6, T.Hi, 'Step ' .. S.Step, 9, 'c', true)
    U.Toggle('xrn', sb + 3, sx, y0 + 22, 40, 14, 'Random')
    U.Menu('xfn', sb + 2, 3, sx + 42, y0 + 22, 40, 14)
    U.Knob(sb, sx + 20, y0 + 64, 12, { label = 'VALUE', bi = true })
    U.Knob(sb + 1, sx + 62, y0 + 64, 12, { label = 'GLIDE' })
    if U.TBtn('xad', sx, y0 + 104, 40, 16, '+ STEP', false) then St(b + 9, min(n, 15) / 15) end
    if U.TBtn('xrm', sx + 42, y0 + 104, 40, 16, '- STEP', false) then St(b + 9, max(n - 2, 0) / 15) end
end
function U.EdEG(k)
    local b = U.B('eg', k)
    U.Frame('eg', k, b, K.eg.src0 + k)
    U.Menu('etr', b + 4, 1, RX + 8, RY + 24, 76, 14)
    U.Toggle('erg', b + 2, RX + 8, RY + 42, 76, 14, 'NEUTRAL SUS')
    U.Toggle('eau', 778, RX + 8, RY + 60, 76, 14, 'AUDITION')
    U.Knob(b + 3, RX + 26, RY + 100, 11, { label = 'THRESH', dim = On(b + 4) })
    U.Knob(b + 1, RX + 68, RY + 100, 11, { label = 'DELAY' })
    U.Knob(b, RX + 46, RY + 148, 11, { label = 'LEVEL', bi = true })
    D:Rect(RX + 94, RY + 22, RW - 102, RH - 30, T.Bg2, 4)
    U.EG('edeg', b, RX + 94, RY + 24, RW - 102, RH - 34, false)
end
function U.EdEF(k)
    local b = U.B('ef', k)
    U.Frame('ef', k, b, K.ef.src0 + k)
    local clr = K.ef.clr
    U.Menu('emo', b + 1, 1, RX + 8, RY + 24, 76, 14)
    U.Toggle('eaf', 778, RX + 8, RY + 42, 76, 14, 'AUDITION')
    U.Knob(b + 2, RX + 26, RY + 84, 11, { label = 'ATTACK' })
    U.Knob(b + 3, RX + 68, RY + 84, 11, { label = 'RELEASE' })
    U.Knob(b, RX + 46, RY + 134, 11, { label = 'LEVEL', bi = true })
    local gx, gy, gw, gh = RX + 94, RY + 22, RW - 102, RH - 30
    D:Rect(gx, gy, gw, gh, T.Bg2, 4)
    local my = gy + gh / 2
    local ax, rx = gx + 14 + G(b + 2) * 90, gx + gw - 18 - (1 - G(b + 3)) * 120
    local topY = my - gh * 0.42
    local tx = ax + 22
    for sn = -1, 1, 2 do
        U.Path({ { gx + 14, my }, { ax, my + sn * gh * 0.42 }, { tx, my + sn * gh * 0.42 }, { rx, my } }, clr, 2)
    end
    Lin(gx, my, gx + gw, my, 0xFFFFFF18, 1)
    local function Pt(id, px, py, p, sc)
        local _, hov, act = D:Btn(id, px - 6, py - 6, 12, 12)
        if act then local dx = im.GetMouseDelta(ctx) if dx ~= 0 then St(p, G(p) + dx / sc) end end
        if hov or act then U.Rd(p) end
        U.Tgt(p, px - 6, py - 6, px + 6, py + 6)
        Circ(px, py, 4, (hov or act) and T.Hi or 0xC8D4E8FF)
    end
    Pt('eaP', ax, topY, b + 2, 90)
    Pt('erP', rx, my, b + 3, 120)
end
function U.EdMIDI(k)
    local b = U.B('midi', k)
    U.Frame('midi', k, b, K.midi.src0 + k)
    local x, w = RX + 60, RW - 120
    U.Menu('min', b + 1, 5, x, RY + 34, w, 20)
    if I(b + 1, 5) == 5 then
        U.Drag('mcc', b + 2, x, RY + 60, w, 20, 0.004, function(l)
            D:Rect(x, RY + 60, w, 20, l and T.TileHi or T.Bg2, 3)
            D:Text(x + w / 2, RY + 65, T.Hi, 'CC ' .. D:Fmt(b + 2), 9, 'c', true)
        end)
    end
    U.Menu('mcu', b + 3, 5, x, RY + 86, w, 20)
    U.Menu('mrg', b + 4, 2, x, RY + 112, w, 20)
    U.Knob(b, RX + 30, RY + 90, 12, { label = 'LEVEL', bi = true })
end
function U.EdXY(k)
    local b = U.B('xy', k)
    U.Frame('xy', k, b, K.xy.src0 + 2 * k)
    U.Menu('xmo', b + 2, 1, RX + 8, RY + 26, 92, 16)
    U.Menu('xrg', b + 3, 1, RX + 8, RY + 46, 92, 16)
    U.Knob(b, RX + 28, RY + 100, 12, { label = 'HOR', dim = not On(b + 2), bi = true })
    U.Knob(b + 1, RX + 74, RY + 100, 12, { label = 'VER', bi = true })
    local gx, gy, gw, gh = RX + 112, RY + 24, RW - 122, RH - 34
    D:Rect(gx, gy, gw, gh, T.Bg2, 6)
    local _, _, act = D:Btn('xyb', gx, gy, gw, gh)
    if act then
        local mx, my = Mouse()
        if On(b + 2) then U.XYSet(b, 0, (mx - gx) / gw) end
        U.XYSet(b, 1, 1 - (my - gy) / gh)
    end
    local px, py = gx + (On(b + 2) and U.XYPos(b, 0) or 0.5) * gw, gy + (1 - U.XYPos(b, 1)) * gh
    for i = 3, 1, -1 do Circ(px, py, i * 11, A(K.xy.clr, 0.13)) end
    Circ(px, py, 2.5, 0xC8FFE0FF)
end

---------------------------------------------------------------------------------------------
-- arpeggiator, voices, output (the panels of the plugin's bottom bar)
function U.Arp()
    U.Frame()
    U.Power('arpe', 766, RX + 34, RY + 12, 6)
    D:Text(RX + 46, RY + 7, T.Hi, 'ARPEGGIATOR', 9, nil, true)
    U.Knob(I(767, 4) == 0 and 768 or 769, RX + 40, RY + 72, 20, { label = I(767, 4) == 0 and 'RATE' or 'OFFSET', bi = I(767, 4) ~= 0 })
    U.Menu('asy', 767, 4, RX + 12, RY + 116, 58, 14)
    U.Toggle('alo', 776, RX + 12, RY + 134, 58, 14, 'LOCK')
    U.Toggle('afo', 770, RX + 12, RY + 152, 58, 14, 'FOLLOW')
    U.Knob(771, RX + 108, RY + 72, 16, { label = 'GROOVE', bi = true })
    U.Knob(772, RX + 160, RY + 72, 16, { label = 'LEGATO' })
    for i, q in ipairs({ { 'Transpose:', 773, 2 }, { 'Note Order:', 774, 4 }, { 'Latch:', 775, 2 } }) do
        local y = RY + 26 + 30 * i
        D:Text(RX + 268, y + 2, T.Mute, q[1], 8, 'r', true)
        U.Menu('am' .. i, q[2], q[3], RX + 272, y, 70, 14)
    end
end
function U.Poly()
    U.Frame()
    D:Text(RX + 30, RY + 7, T.Hi, 'VOICES', 9, nil, true)
    U.Menu('ppo', 784, 2, RX + 30, RY + 30, 110, 16)
    local function Num(id, p, x, s)
        U.Drag(id, p, x, RY + 56, 50, 40, 0.004, function(l)
            D:Text(x + 25, RY + 60, l and T.Hi or T.Txt, D:Fmt(p), 10, 'c', true)
            D:Text(x + 25, RY + 80, T.Mute, s, 8, 'c', true)
        end)
    end
    Num('pvo', 782, RX + 30, 'VOICES')
    Num('pun', 783, RX + 90, 'UNISON')
    U.Knob(785, RX + 200, RY + 68, 20, { label = 'SPREAD' })
    U.Toggle('ptu', 786, RX + 30, RY + 120, 110, 16, 'TUNING')
end
function U.Out()
    U.Frame()
    D:Text(RX + 30, RY + 7, T.Hi, 'OUTPUT', 9, nil, true)
    U.Knob(781, RX + 70, RY + 88, 20, { label = 'WIDTH', bi = true })
    U.Knob(779, RX + 180, RY + 88, 24, { label = 'VOLUME', bi = true })
    U.Knob(780, RX + 290, RY + 88, 20, { label = 'PAN', bi = true })
end

---------------------------------------------------------------------------------------------
-- slot list popup
function U.SlotPopup()
    if S.Pop and not S.PopOpen then
        im.OpenPopup(ctx, 'twSlots')
        S.PopOpen = S.Pop
    end
    S.Pop = nil
    if not im.BeginPopup(ctx, 'twSlots') then S.PopOpen = nil return end
    local q = S.PopOpen or {}
    local L = q.t and S.Mods[q.t] or (q.s and S.BySrc[q.s]) or {}
    im.Text(ctx, q.t and S.TName[q.t] or U.SrcName(q.s or 0))
    im.Separator(ctx)
    local del
    for _, e in ipairs(L) do
        local b = SLOT0 + 5 * e.i
        local cl = U.SrcClr(q.t and e.s or q.s)
        im.PushID(ctx, e.i)
        im.TextColored(ctx, cl, q.t and U.SrcName(e.s) or (S.TName[e.t] or '-'))
        im.SameLine(ctx, 150)
        im.SetNextItemWidth(ctx, 110)
        local ch, v = im.SliderDouble(ctx, '##lv', G(b + 1), 0, 1, D:Fmt(b + 1))
        if ch then St(b + 1, v) end
        im.SameLine(ctx)
        local inv, byp = On(b + 3), On(b + 2)
        if im.SmallButton(ctx, inv and '-' or '+') then St(b + 3, inv and 0 or 1) end
        im.SameLine(ctx)
        if im.SmallButton(ctx, byp and 'off' or 'on') then St(b + 2, byp and 0 or 1) end
        im.SameLine(ctx)
        if im.SmallButton(ctx, 'x') then del = e.i end
        im.PopID(ctx)
    end
    im.EndPopup(ctx)
    if del then U.DelSlot(del) end
end

---------------------------------------------------------------------------------------------
-- frame
local now = D.NOW
if now - S.ModT > 0.3 then S.ModT = now; U.Scan() end
if now - S.NameT > 1.5 then S.NameT = now; U.ReadNames() end
S.Rects, S.RdP, S.PlusDone = {}, nil, nil

D:Rect(0, 0, W, H, T.Bg, 0, true)

U.Rings()
for i = 1, 4 do U.Osc(i) end

-- master tune, its octave, portamento
U.Menu('msc', 1, 3, 163, 109, 26, 12, { bare = true })
D:Text(176, 110, T.Gold, D:Fmt(1), 9, 'c', true)
U.Knob(0, 176, 134, 10, { noPtr = true, bi = true })
U.Fork(176, 134, T.Gold)
U.Knob(44, 176, 162, 10, { noPtr = true })
U.Note(176, 162, T.Gold)
do
    local leg = On(45)
    local c = D:Btn('leg', 168, 180, 16, 16)
    if c then St(45, leg and 0 or 1) end
    U.Note(173, 188, leg and T.Gold or T.Mute); U.Note(180, 187, leg and T.Gold or T.Mute)
end
local v = S.View
local fxq = S.Fx and U.FXS[S.Fx]
if v == 'arp' then U.Arp() elseif v == 'poly' then U.Poly() elseif v == 'out' then U.Out()
elseif v then
    local fn = ({ xlfo = U.EdXLFO, eg = U.EdEG, ef = U.EdEF, midi = U.EdMIDI, xy = U.EdXY })[v[1]]
    if v[2] > U.Cnt(v[1]) then S.View = nil else fn(v[2]) end
elseif fxq then U.FXPanel(S.Fx, fxq)
else
    U.FilterDisplay('fl', 46, 78, 160, 16, 344, 92)
    if S.EgMods then U.Mods(196, 110, 310, 90) else
        U.EG('meg', 620, 196, 110, 308, 90, true)
        U.SrcDot('egdot', 19, 205, 190, 6, 620)
    end
    U.EgSwitch(510, 124)
end

-- filter routing + offsets
local rt = I(78, 2)
if U.Menu('frt', 78, 2, 516, 2, 28, 20, { bare = true }) then U.Rd(78) end
local function Rd(y) Circ(524, y, 2, T.Gold); Circ(536, y, 2, T.Gold) end
if rt == 0 then Lin(520, 12, 540, 12, T.Gold, 1.2); Circ(526, 12, 2, T.Gold); Circ(534, 12, 2, T.Gold)
elseif rt == 1 then Lin(520, 12, 524, 12, T.Gold, 1.2); Lin(524, 8, 524, 16, T.Gold, 1.2); Lin(524, 8, 538, 8, T.Gold, 1.2); Lin(524, 16, 538, 16, T.Gold, 1.2); Circ(531, 8, 2, T.Gold); Circ(531, 16, 2, T.Gold)
else Rd(7); Rd(12); Rd(17) end
U.Knob(79, 530, 54, 16, { noPtr = true, bi = true, noDots = false })
U.Path({ { 520, 50 }, { 528, 50 }, { 538, 60 } }, 0xC8C6CCFF, 1.2)
U.Path({ { 520, 53 }, { 526, 53 }, { 532, 60 } }, 0xC8C6CC80, 1)
U.Knob(80, 530, 96, 12, { noPtr = true, bi = true })
U.Path({ { 522, 100 }, { 529, 90 }, { 531, 90 }, { 538, 100 } }, 0xC8C6CCFF, 1.2)

for _, nm in ipairs({ 'Reverb', 'Delay', 'Chorus', 'Phaser', 'Drive', 'Compress' }) do U.FX(nm, U.FXS[nm]) end

-- header: the logo, presets, the value being touched
D:Text(RX, 2, T.Gold, 'TWIN 3', 10, nil, true)
do
    local px, py, pw, ph = RX + 42, 1, 150, 13
    D:Rect(px, py, pw, ph, T.Bar, 3)
    local c1 = D:Btn('prp', px, py, ph, ph)
    local c2 = D:Btn('prn', px + pw - ph, py, ph, ph)
    local c3, hv = D:Btn('prm', px + ph, py, pw - ph * 2, ph)
    if c1 then Presets.Step(-1) end
    if c2 then Presets.Step(1) end
    if c3 then Presets.Open(X + px, Y + py + ph) end
    local lx, ly = X + px + 7, Y + py + 6.5
    im.DrawList_AddTriangleFilled(DL, lx + 2, ly - 3, lx + 2, ly + 3, lx - 2, ly, T.Txt)
    lx = X + px + pw - 7
    im.DrawList_AddTriangleFilled(DL, lx - 2, ly - 3, lx - 2, ly + 3, lx + 2, ly, T.Txt)
    local nm = Presets.Current() or ''
    D:Text(px + pw / 2, py + 2, hv and T.Hi or T.Txt, nm:sub(1, 24), 8, 'c', true)
    Presets.Draw()
end

-- bottom bar
do
    local y = 202
    D:Rect(RX, y, RW, 14, T.Bar, 3)
    local function B(id, x, w, s1, on, view)
        local c, hov = D:Btn(id, x, y, w, 14)
        if on then D:Rect(x + w * 0.3, y, w * 0.4, 1.5, T.Gold) end
        D:Text(x + w / 2, y + 2.5, (hov or S.View == view and view) and T.Hi or T.Txt, s1, 8, 'c', true)
        return c
    end
    if B('barp', RX, 70, 'Arpeggiator', On(766), 'arp') then U.ViewT('arp') end
    if B('bhq', RX + 72, 74, 'High Quality', On(777)) then St(777, On(777) and 0 or 1) end
    local ps = D:Fmt(784)
    if B('bpo', RX + 150, 92, (ps == 'Per Oscillator' and 'Per Osc' or ps) .. '  ' .. D:Fmt(782) .. ' / ' .. D:Fmt(783) .. '  ' .. D:Fmt(785):gsub(' ', ''),
        false, 'poly') then U.ViewT('poly') end
    if B('bou', RX + 244, 88, D:Fmt(781) .. '  ' .. D:Fmt(779), false, 'out') then U.ViewT('out') end
    if S.View ~= 'out' then U.ModDots(S.P2T[779], RX + 333, y + 7) end
end
if S.RdP then
    D:Text(RX + RW, 3, T.Hi, ((D.Names[S.RdP] or ''):sub(1, 16)) .. '  ' .. D:Fmt(S.RdP):sub(1, 12), 8, 'r', true)
end

-- a source dot being dragged onto a control
if S.Drag then
    local mx, my = Mouse()
    local hit
    for i = #S.Rects, 1, -1 do
        local q = S.Rects[i]
        if mx >= q[2] and mx <= q[4] and my >= q[3] and my <= q[5] then hit = q break end
    end
    local fg = im.GetForegroundDrawList(ctx)
    local col = U.SrcClr(S.Drag)
    im.DrawList_AddCircleFilled(fg, X + mx, Y + my, 6, A(col, 0.8), 16)
    if hit then
        im.DrawList_AddRect(fg, X + hit[2] - 2, Y + hit[3] - 2, X + hit[4] + 2, Y + hit[5] + 2, col, 4, nil, 1.5)
    end
    if im.IsMouseReleased(ctx, 0) then
        if hit then U.AddSlot(S.Drag, hit[1]) end
        S.Drag = nil
    end
end
U.SlotPopup()
-- a click outside an open panel closes it (not one on a menu it opened, nor a source dot being dragged in)
if (S.Fx or S.View) and im.IsMouseClicked(ctx, 0) and not S.DotAct and not Presets.IsOpen()
    and not im.IsPopupOpen(ctx, '', im.PopupFlags_AnyPopupId | im.PopupFlags_AnyPopupLevel) then
    local mx, my = Mouse()
    if mx < RX or mx > RX + RW or my < RY or my > RY + RH then
        S.Closed, S.ClosedV, S.Fx, S.View = S.Fx, S.View, nil, nil
    end
end
if (S.Closed or S.ClosedV) and im.IsMouseReleased(ctx, 0) and not S.ClosedPress then S.ClosedPress = true
elseif S.ClosedPress then S.Closed, S.ClosedV, S.ClosedPress = nil, nil, nil end
S.DotAct = nil
D:End()
