-- Auto-Tune Pro (Antares): Auto view with top selectors, 4 main knobs, cents dial, key display, keyboard strip.
local SFX = require('src.Functions.Stock FX UI')
local D = SFX.Begin({
    Title = 'Auto-Tune Pro', W = 476, Accent = SFX.ACCENT.Pitch,
    Params = {
        mode = { 'Correction Mode', idx = 0 }, scale = { 'Scale', idx = 1 }, key = { 'Key', idx = 2 },
        detune = { 'Detune', idx = 3 }, retune = { 'Retune Speed', idx = 4 }, track = { 'Tracking', idx = 9 },
        input = { 'Input Type', idx = 10 }, classic = { 'Use Classic Mode DSP', idx = 11 },
        learn = { 'Learn Scale from MIDI', idx = 36 }, adv = { 'Advanced View', idx = 33 },
        kedit = { 'Keyboard Edits', idx = 53 }, kmode = { 'Keyboard Mode', idx = 54 },
        human = { 'Humanize', idx = 61 }, vib = { 'Natural Vibrato', idx = 62 },
        throat = { 'Throat Length', idx = 71 }, trans = { 'Transpose', idx = 74 },
        flex = { 'Flex-Tune', idx = 89 }, mix = { 'Wet-Dry Mix', idx = 91 },
    },
})
if not D then return end
local C, A = SFX.C, SFX.A
local DL = D.DL
local W = 476
local BLUE = 0x4A9BFFFF
local ORANGE = 0xD9822BFF
local BG = 0x2A2D34FF

D:Rect(0, 0, W + 8, 216, BG, 0, true)
D:Rect(4, 46, W, 124, 0x23252BFF, 6, true)

local function radio(id, x, y, label, on, clr)
    local px, py = D.X + x + 5, D.Y + y + 7
    im.DrawList_AddCircle(DL, px, py, 5, clr, 0, 1.4)
    if on then im.DrawList_AddCircleFilled(DL, px, py, 3, clr) end
    D:Text(x + 14, y + 2, on and C.Text or C.TextDim, label, 9)
    local w = SFX.TextW(label, 9) + 16
    local clicked = D:Btn(id, x, y, w, 14)
    return clicked
end

-- top row
D:Choice('input', 6, 3, 96, { label = 'Input Type', h = 18 })
D:Choice('key', 108, 3, 52, { label = 'Key', h = 18 })
D:Choice('scale', 166, 3, 100, { label = 'Scale', h = 18 })
local sel = D:Get('mode') > 0.5 and 2 or 1
local nsel = D:Tabs('mode', 274, 3, { { 'Auto', BLUE }, { 'Graph', BLUE } }, sel)
if nsel and nsel ~= sel then D:Set('mode', nsel == 2 and 1 or 0) end
local cl = D:Get('classic') > 0.5
if radio('rmod', 374, 4, 'Modern', not cl, BLUE) then D:Set('classic', 0) end
if radio('rcla', 426, 4, 'Classic', cl, BLUE) then D:Set('classic', 1) end

-- second row
local bars = { { 'track', 'Tracking' }, { 'throat', 'Formant' }, { 'trans', 'Transpose' }, { 'detune', 'Detune' }, { 'mix', 'Mix' } }
for i, b in ipairs(bars) do
    D:Bar(b[1], 6 + (i - 1) * 94, 26, 88, 13, b[2], { accent = BLUE })
end

-- knobs
D:Knob('retune', 52, 100, 'L', 'Retune Speed', { accent = BLUE })
D:Knob('flex', 130, 118, 'M', 'Flex Tune', { accent = BLUE })
D:Knob('vib', 346, 118, 'M', 'Natural Vibrato', { accent = BLUE, bipolar = true })
D:Knob('human', 424, 100, 'L', 'Humanize', { accent = BLUE })

-- cents dial
local dcx, dcy, rad = 238, 108, 48
local cx, cy = D.X + dcx, D.Y + dcy
local a0, a1 = -math.pi / 2 - 2.18, -math.pi / 2 + 2.18
im.DrawList_PathArcTo(DL, cx, cy, rad, a0, a1)
im.DrawList_PathStroke(DL, A(C.TextMute, 0.7), nil, 1)
for i = 0, 40 do
    local a = a0 + (a1 - a0) * i / 40
    local ca, sa = math.cos(a), math.sin(a)
    im.DrawList_AddLine(DL, cx + ca * 35, cy + sa * 35, cx + ca * 45, cy + sa * 45, A(C.TextMute, 0.55), 2)
end
im.DrawList_AddCircle(DL, cx, cy, 30, A(C.TextMute, 0.7), 0, 1)
im.DrawList_AddLine(DL, cx, cy - 48, cx, cy - 34, BLUE, 2)
local labs = { { '-100', a0 }, { '-50', -math.pi / 2 - 1.09 }, { '0', -math.pi / 2 }, { '+50', -math.pi / 2 + 1.09 }, { '+100', a1 } }
for _, l in ipairs(labs) do
    local lx = dcx + (rad + 10) * math.cos(l[2])
    local ly = dcy + (rad + 10) * math.sin(l[2]) - 4
    if l[1] == '0' then ly = dcy - rad - 12 end
    D:Text(lx, ly, C.TextMute, l[1], 8, 'c')
end
local note = D:Fmt('key')
local tw = SFX.TextW(note, 16, false) * 28 / 16
im.DrawList_AddTextEx(DL, Font_SemiBold_16, 28, cx - tw / 2, cy - 17, 0xC8DCF5FF, note)

-- Advanced
local advOn = D:Get('adv') > 0.5
D:Text(238, 156, advOn and BLUE or C.Text, 'Advanced', 9, 'c', true)
if D:Btn('adv', 198, 154, 80, 14) then D:Set('adv', advOn and 0 or 1) end

-- bottom strip
local bypOn = D:Get('kedit') > 0.5
if radio('rbyp', 8, 174, 'Bypass', bypOn, ORANGE) then D:Set('kedit', 1) end
if radio('rrem', 70, 174, 'Remove', not bypOn, BLUE) then D:Set('kedit', 0) end
D:Toggle('learn', 160, 173, 76, 'Learn', { h = 15, accent = BLUE })
im.DrawList_AddLine(DL, D.X + 250, D.Y + 181, D.X + 400, D.Y + 181, A(C.TextMute, 0.6), 1)
local lat = D:Get('kmode') > 0.5
local lc = lat and BLUE or C.TextDim
D:Text(W - 52, 176, C.TextDim, 'Latch', 9)
D:Rect(W - 18, 179, 10, 8, lc, 2, true)
im.DrawList_PathArcTo(DL, D.X + W - 13, D.Y + 179, 3.5, math.pi, math.pi * 2)
im.DrawList_PathStroke(DL, lc, nil, 1.5)
if D:Btn('latch', W - 54, 174, 50, 14) then D:Set('kmode', lat and 0 or 1) end

-- keyboard
local kx, ky, kh = 4, 192, 22
local nW = 28
local kw = W / nW
local whites = { 0, 2, 4, 5, 7, 9, 11 }
local keyIdx = math.floor(D:Get('key') * 11 + 0.5)
for i = 0, nW - 1 do
    local semi = whites[(i % 7) + 1]
    D:Rect(kx + i * kw + 0.5, ky, kw - 1, kh, semi == keyIdx and A(BLUE, 0.9) or 0x45474DFF, 1, true)
end
for i = 0, nW - 2 do
    local w = i % 7
    if w ~= 2 and w ~= 6 then
        local semi = whites[w + 1] + 1
        D:Rect(kx + (i + 1) * kw - 5, ky, 10, 13, semi == keyIdx and BLUE or 0x2E3036FF, 1, true)
    end
end
D:End()