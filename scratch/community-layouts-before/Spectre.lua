-- Spectre (Wavesfactory): five-band EQ with gradient curve, band-coloured nodes, band table on coloured columns with Color/Processing dropdowns; Input/Output/Mix knobs, Mode menu and De-Emphasis checkbox on the right. Double-click resets knobs and values.
local SFX = require('src.Functions.Stock FX UI')
local NAMES = { 'LowShelf', 'Peak 01', 'Peak 02', 'Peak 03', 'HighShelf' }
local SUF = { { 'f', 'Frequency' }, { 'g', 'Gain' }, { 'q', 'Q' }, { 's', 'Switch' }, { 'c', 'Color' }, { 'p', 'Processing' } }
local PRM = {
    inp = { 'Input', idx = 30 }, out = { 'Output', idx = 31 }, mix = { 'Dry Wet', idx = 32 },
    deemp = { 'De-Emphasis', idx = 35 }, mode = { 'Mode', idx = 36 },
}
for i = 1, 5 do
    for j, s in ipairs(SUF) do PRM['b' .. i .. s[1]] = { NAMES[i] .. ' ' .. s[2], idx = (i - 1) * 6 + j - 1 } end
end
local D = SFX.Begin({ Title = 'Spectre', W = 436, Accent = SFX.ACCENT.EQ, Params = PRM })
if not D then return end
local A = SFX.A
local DL = D.DL
local WHITE = 0xFFFFFFFF
local DEF_F = { 100, 250, 1000, 3500, 10000 }
local CL = { 0xD232E6FF, 0xA23CF0FF, 0x7C55F5FF, 0x5E78F2FF, 0x40A8EAFF }
local function grad(t, a)
    local cr = math.floor(0xD2 + (0x40 - 0xD2) * t)
    local cg = math.floor(0x32 + (0xA8 - 0x32) * t)
    local cb = math.floor(0xE6 + (0xEA - 0xE6) * t)
    return cr * 16777216 + cg * 65536 + cb * 256 + math.floor(a * 255)
end
local function hz(key)
    local t = D:Fmt(key) or ''
    local n = SFX.Num(t) or 1000
    if t:lower():find('k') then n = n * 1000 end
    return n
end
local function fit(txt, maxw, bold, sizes)
    for _, sz in ipairs(sizes) do
        if SFX.TextW(txt, sz, bold) <= maxw then return txt, sz end
    end
    local sz = sizes[#sizes]
    while #txt > 1 and SFX.TextW(txt, sz, bold) > maxw do txt = string.sub(txt, 1, #txt - 1) end
    return txt, sz
end
local function dbl(x, y, w, h)
    if not im.IsMouseDoubleClicked(ctx, 0) then return false end
    local mx, my = im.GetMousePos(ctx)
    return mx >= D.X + x and mx <= D.X + x + w and my >= D.Y + y and my <= D.Y + y + h
end
local function normOr(key, target, fb)
    local v = D:NormFor(key, target)
    if v then return SFX.Clamp(v, 0, 1) end
    return fb
end

-- background
D:Rect(0, 0, 444, 216, 0x0F1340FF, 0, true)
D:Rect(308, 0, 136, 216, 0x13112FFF, 0, true)
D:Line(308, 0, 308, 216, 0x2A2A60FF, 1)

-- graph
local gx, gw, base, hh = 4, 300, 112, 76
D:Rect(gx, 4, gw, 124, 0x0D1440FF, 2, true)
local function xf(f) return gx + gw * math.log(f / 20) / math.log(1000) end
local labs = { { 30, '30' }, { 100, '100' }, { 300, '300' }, { 1000, '1k' }, { 3000, '3k' }, { 10000, '10k' } }
for _, l in ipairs(labs) do
    local x = xf(l[1])
    D:Line(x, 4, x, 128, A(0x4050A0FF, 0.4), 1)
    D:Text(x + 3, 115, 0xE0E4FFFF, l[2], 10, nil, true)
end

local on, fc, gn, qq, cf = {}, {}, {}, {}, {}
local FS = 48000
for i = 1, 5 do
    local k = 'b' .. i
    on[i] = D:On(k .. 's')
    fc[i] = SFX.Clamp(hz(k .. 'f'), 20, 20000)
    gn[i] = D:Val(k .. 'g') or 0
    qq[i] = SFX.Clamp(D:Val(k .. 'q') or 0.7, 0.1, 10)
    if on[i] and gn[i] > 0.01 then
        local w0 = 2 * math.pi * fc[i] / FS
        local cw, sw = math.cos(w0), math.sin(w0)
        local al = sw / (2 * qq[i])
        local Aa = 10 ^ (gn[i] / 40)
        if i == 1 then
            local sa = 2 * math.sqrt(Aa) * al
            cf[i] = { Aa * ((Aa + 1) - (Aa - 1) * cw + sa), 2 * Aa * ((Aa - 1) - (Aa + 1) * cw), Aa * ((Aa + 1) - (Aa - 1) * cw - sa),
                (Aa + 1) + (Aa - 1) * cw + sa, -2 * ((Aa - 1) + (Aa + 1) * cw), (Aa + 1) + (Aa - 1) * cw - sa }
        elseif i == 5 then
            local sa = 2 * math.sqrt(Aa) * al
            cf[i] = { Aa * ((Aa + 1) + (Aa - 1) * cw + sa), -2 * Aa * ((Aa - 1) + (Aa + 1) * cw), Aa * ((Aa + 1) + (Aa - 1) * cw - sa),
                (Aa + 1) - (Aa - 1) * cw + sa, 2 * ((Aa - 1) - (Aa + 1) * cw), (Aa + 1) - (Aa - 1) * cw - sa }
        else
            cf[i] = { 1 + al * Aa, -2 * cw, 1 - al * Aa, 1 + al / Aa, -2 * cw, 1 - al / Aa }
        end
    end
end

-- one combined response curve, sampled every pixel
local hs = {}
for px = 0, gw - 1 do
    local t = px / (gw - 1)
    local f = 20 * 1000 ^ t
    local w = 2 * math.pi * f / FS
    local c1, s1, c2, s2 = math.cos(w), math.sin(w), math.cos(2 * w), math.sin(2 * w)
    local tot = 0
    for i = 1, 5 do
        local c = cf[i]
        if c then
            local br = c[1] + c[2] * c1 + c[3] * c2
            local bi = c[2] * s1 + c[3] * s2
            local ar = c[4] + c[5] * c1 + c[6] * c2
            local ai = c[5] * s1 + c[6] * s2
            tot = tot + 4.3429448 * math.log((br * br + bi * bi) / (ar * ar + ai * ai + 1e-12))
        end
    end
    tot = SFX.Clamp(tot, 0, 13.5)
    hs[px] = tot / 12 * hh
end
for px = 0, gw - 1 do
    local t = px / (gw - 1)
    local h = hs[px]
    local x = D.X + gx + px
    local y = D.Y + base - h
    if h > 0.3 then
        im.DrawList_AddRectFilledMultiColor(DL, x, y, x + 1, D.Y + base, grad(t, 0.5), grad(t, 0.5), grad(t, 0.04), grad(t, 0.04))
    end
end
for px = 1, gw - 1 do
    local t = px / (gw - 1)
    local h0, h1 = hs[px - 1], hs[px]
    if h0 > 0.3 or h1 > 0.3 then
        im.DrawList_AddLine(DL, D.X + gx + px - 1, D.Y + base - h0, D.X + gx + px, D.Y + base - h1, grad(t, 1), 2)
    end
end
D:Line(gx, base, gx + gw, base, grad(0.5, 0.5), 1)

-- band icons (switches) and nodes
local colW = gw / 5
local function cx(i) return gx + colW * (i - 0.5) end
for i = 1, 5 do
    local k = 'b' .. i
    local c = cx(i)
    local a = on[i] and 1 or 0.25
    for kk = -9, 9 do
        local y
        if i == 1 then y = 10 + 6 / (1 + math.exp(-kk / 2))
        elseif i == 5 then y = 16 - 6 / (1 + math.exp(-kk / 2))
        else y = 17 - 6 * math.exp(-(kk / 4) ^ 2) end
        im.DrawList_PathLineTo(DL, D.X + c + kk, D.Y + y)
    end
    im.DrawList_PathStroke(DL, A(CL[i], a), nil, 2)
    local ic = D:Btn('sw' .. i, c - 14, 6, 28, 14)
    if ic then D:Set(k .. 's', on[i] and 0 or 1) end
    local nx = SFX.Clamp(xf(fc[i]), gx + 5, gx + gw - 5)
    local ny = base - SFX.Clamp(gn[i] / 12, 0, 1) * hh
    if on[i] then
        im.DrawList_AddCircleFilled(DL, D.X + nx, D.Y + ny, 6, WHITE)
        im.DrawList_AddCircleFilled(DL, D.X + nx, D.Y + ny, 4.3, CL[i])
    else
        im.DrawList_AddCircleFilled(DL, D.X + nx, D.Y + ny, 4, A(CL[i], 0.35))
    end
    local _, _, act = D:Btn('nd' .. i, nx - 7, ny - 7, 14, 14)
    if act then
        local mx, my = im.GetMousePos(ctx)
        local f = 20 * 1000 ^ SFX.Clamp((mx - D.X - gx) / gw, 0, 1)
        D:Set(k .. 'f', D:NormFor(k .. 'f', f))
        D:Set(k .. 'g', SFX.Clamp((base - (my - D.Y)) / hh, 0, 1))
    end
end

-- dropdown chip (Color / Processing)
local function dropdown(key, c, y, a)
    local lbl = D:Fmt(key) or ''
    local tc = a >= 1 and WHITE or A(WHITE, 0.6)
    local clk, hov = D:Btn('dd' .. key, c - 28, y, 56, 14)
    D:Rect(c - 28, y, 56, 14, A(WHITE, hov and 0.3 or 0.16), 3, true)
    D:Rect(c - 28, y, 56, 14, A(WHITE, 0.5), 3, false, 1)
    local txt, sz = fit(lbl, 44, true, { 10, 9, 8 })
    D:Text(c - 4, y + 2, tc, txt, sz, 'c', true)
    local ax, ay = D.X + c + 19, D.Y + y + 5
    im.DrawList_AddTriangleFilled(DL, ax, ay, ax + 6, ay, ax + 3, ay + 4, tc)
    if clk then im.OpenPopup(ctx, 'pp' .. key) end
    if im.BeginPopup(ctx, 'pp' .. key) then
        local ch = D:Choices(key) or {}
        for _, it in ipairs(ch) do
            local lab = it[1] or it.label or ''
            if im.Selectable(ctx, lab, lab == lbl) then
                D:Set(key, it[2] or it.norm)
            end
        end
        im.EndPopup(ctx)
    end
end

-- table: band-coloured columns, white bold text; drag to change, double-click to reset
D:Rect(4, 132, 300, 80, 0x1A1A40FF, 3, true)
for i = 1, 5 do
    local k = 'b' .. i
    local c = cx(i)
    local a = on[i] and 1 or 0.45
    D:Rect(c - colW / 2 + 2, 134, colW - 4, 76, A(CL[i], on[i] and 0.6 or 0.2), 4, true)
    local tc = on[i] and WHITE or A(WHITE, 0.6)
    local fh = fc[i]
    local ft
    if fh >= 1000 then ft = string.format('%.2f kHz', fh / 1000) else ft = string.format('%.1f Hz', fh) end
    local rows = {
        { ft, k .. 'f' },
        { string.format('%.2f dB', gn[i]), k .. 'g' },
        { string.format('%.2f', qq[i]), k .. 'q' },
    }
    for ri, row in ipairs(rows) do
        local y = 135 + (ri - 1) * 15
        local _, hov, act = D:Btn('r' .. i .. ri, c - 28, y, 56, 14)
        if hov then D:Rect(c - 28, y, 56, 14, A(WHITE, 0.16), 3, true) end
        local txt, sz = fit(row[1], 54, true, { 11, 10, 9, 8 })
        D:Text(c, y + 1, tc, txt, sz, 'c', true)
        if act then
            local _, dy = im.GetMouseDelta(ctx)
            D:Set(row[2], SFX.Clamp(D:Get(row[2]) - dy * 0.004, 0, 1))
        end
        if hov and im.IsMouseDoubleClicked(ctx, 0) then
            if ri == 1 then D:Set(row[2], normOr(row[2], DEF_F[i], 0.5))
            elseif ri == 2 then D:Set(row[2], 0)
            else D:Set(row[2], normOr(row[2], 0.7, 0.07)) end
        end
    end
    dropdown(k .. 'c', c, 135 + 3 * 15, a)
    dropdown(k .. 'p', c, 135 + 4 * 15, a)
end

-- right column, centred vertically (content spans y = 38 to 177)
local function knob(key, x, y, label, o, def)
    D:Knob(key, x, y, 'L', label, o)
    if dbl(x - 19, y - 33, 38, 67) then D:Set(key, def) end
end
knob('inp', 338, 71, 'Input', { unit = 'dB', bipolar = true, accent = 0xD232E6FF }, normOr('inp', 0, 0.5))
knob('out', 378, 71, 'Output', { unit = 'dB', bipolar = true, accent = 0x7C55F5FF }, normOr('out', 0, 0.5))
knob('mix', 418, 71, 'Mix', { bipolar = true, accent = 0x40A8EAFF, value = string.format('%d%%', math.floor(D:Get('mix') * 100 + 0.5)) }, 1)
D:Line(318, 117, 434, 117, 0x2A2A60FF, 1)
D:Choice('mode', 316, 129, 120, { label = 'Mode', accent = 0x8C7BFFFF })
local de = D:On('deemp')
local dclk, dhov = D:Btn('de', 316, 159, 120, 18)
D:Rect(318, 160, 16, 16, dhov and 0x8C7BFFFF or 0x7A7AC8FF, 3, false, 1.5)
if de then
    D:Rect(320, 162, 12, 12, 0x8C7BFFFF, 2, true)
    D:Line(322, 168, 325, 171, 0x13112FFF, 2)
    D:Line(325, 171, 331, 164, 0x13112FFF, 2)
end
D:Text(342, 162, 0xE6E8FFFF, 'De-Emphasis', 11, nil, true)
if dclk then D:Set('deemp', de and 0 or 1) end
D:End()