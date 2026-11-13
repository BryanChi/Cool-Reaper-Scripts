-- fxd-kit 2
-- UAD Neve 33609 C: hardware look (slate faceplates with screws, grey Neve knobs with printed scales, red jewel In lamps,
-- bat Fast/Slow switches). Two channel strips with grouped limiter (Thld, Recovr) and compressor (Thld, Ratio, Recovr, Gain) knobs, Output in the free space, red In LEDs, Slow/Fast switches, centre link / HPF / mix / headroom / power, in a wood frame.
local SFX = require('src.Functions.Stock FX UI')
local P = {}
local base = { lt = 'Lim %d Thr', lr = 'Lim %d Rec', la = 'Lim %d Atk', li = 'Lim %d In', ct = 'Comp %d Thr', cr = 'Comp %d Rcv', cg = 'Comp %d Gain', cq = 'Comp %d Rat', ci = 'Comp %d In', ca = 'Comp %d Atk', out = 'Output %d' }
local order = { 'lt', 'lr', 'la', 'li', 'ct', 'cr', 'cg', 'cq', 'ci', 'ca', 'out' }
for ch = 1, 2 do
    for i, k in ipairs(order) do
        P[k .. ch] = { string.format(base[k], ch), idx = (ch - 1) * 11 + i - 1 }
    end
end
P.clink = { 'Ctrl Link', idx = 22 }
P.slink = { 'Ster Link', idx = 23 }
P.sc = { 'SC Filter', idx = 24 }
P.mix = { 'Mix', idx = 25 }
P.hr = { 'Headroom', idx = 26 }
P.pwr = { 'Power', idx = 27 }

local D = SFX.Begin({ Title = 'Neve 33609 C', W = 476, Accent = SFX.ACCENT.Dynamics, Params = P })
if not D then return end

local WOOD = 0x8B3A1BFF
local SLATE = 0x3A4452FF
local INK = 0xE8EBF0FF
local GREY = 0xA9AFB8FF
local RED = 0xB8232CFF

-- wood end cheeks around the unit
D:Rect(0, 0, 476, 216, WOOD, 4, true)
for i = 0, 5 do D:Line(2, 30 + i * 32, 474, 34 + i * 30, 0x00000014, 1) end
D:Rect(1, 1, 474, 214, 0x00000066, 4, false, 2)

local function knob(key, x, y, label, scale, cap, rad)
    D:Dial(key, x, y, rad or 11, { style = 'cap', cap = cap or GREY, body = 0x5C626Bff, label = label, labelClr = INK, labelSize = 7,
        scale = scale, ticks = 11, tickClr = INK, scaleSize = 6 })
end

-- red In lamp: lit = the section is In (param value 0); click toggles
local function lamp(key, cx, cy)
    local on = D:Get(key) < 0.5
    if D:Btn('led_' .. key, cx - 7, cy - 7, 14, 14) then D:Set(key, on and 1 or 0) end
    D:Lamp(cx, cy, 4, on, { clr = 0xFF3A3AFF })
    D:Engrave(cx, cy + 9, 'IN', { clr = INK, size = 7, align = 'c' })
end

local function channel(ch, px)
    D:Faceplate(px, 10, 189, 196, { clr = SLATE, screws = true, screwR = 2.6 })
    D:Inset(px + 4, 58, 84, 76, { style = 'line', line = 0xFFFFFF38 })
    D:Inset(px + 92, 58, 93, 136, { style = 'line', line = 0xFFFFFF38 })
    D:Engrave(px + 46, 16, 'LIMITER', { clr = INK, size = 8, align = 'c', bold = true })
    D:Engrave(px + 138, 16, 'COMPRESSOR', { clr = INK, size = 8, align = 'c', bold = true })
    local s = tostring(ch)
    lamp('li' .. s, px + 16, 36)
    D:Switch('la' .. s, px + 62, 38, { style = 'bat', len = 16, w = 9, horizontal = true, up = 'SLOW', down = 'FAST', labelClr = INK, labelSize = 6 })
    lamp('ci' .. s, px + 102, 36)
    D:Switch('ca' .. s, px + 152, 38, { style = 'bat', len = 16, w = 9, horizontal = true, up = 'SLOW', down = 'FAST', labelClr = INK, labelSize = 6 })
    local rowA, rowB = 100, 163
    knob('lt' .. s, px + 25, rowA, 'THLD', { '+4', '+15' })
    knob('lr' .. s, px + 67, rowA, 'RECOVR', { '100', 'A2' })
    knob('ct' .. s, px + 115, rowA, 'THLD', { '-20', '+10' })
    knob('cq' .. s, px + 162, rowA, 'RATIO', { '1.5', '6' })
    knob('cr' .. s, px + 115, rowB, 'RECOVR', { '100', 'A2' })
    knob('cg' .. s, px + 162, rowB, 'GAIN', { '0', '20' })
    knob('out' .. s, px + 46, rowB + 2, 'OUTPUT', { '-', '+' }, RED, 12)
end

channel(1, 16)
channel(2, 271)

-- centre panel: links, side-chain filter, mix, headroom, power
D:Faceplate(207, 10, 62, 196, { clr = 0x343C48FF, screws = true, screwR = 2.4 })
D:Switch('clink', 222, 44, { style = 'paddle', len = 16, w = 8, label = 'LINK', up = '', labelClr = INK, labelSize = 7 })
D:Switch('slink', 254, 44, { style = 'paddle', len = 16, w = 8, label = 'MONO', up = '', labelClr = INK, labelSize = 7 })
D:Dial('sc', 222, 98, 8, { style = 'skirt', label = 'HPF', labelClr = INK, labelSize = 7, ticks = 7, tickClr = INK })
D:Dial('mix', 254, 98, 8, { style = 'skirt', label = 'MIX', labelClr = INK, labelSize = 7, ticks = 7, tickClr = INK })
D:Bar('hr', 213, 128, 50, 12, 'HR', { accent = GREY })
D:Lamp(238, 158, 3.5, D:On('pwr'), { clr = 0xFF3A3AFF })
D:Switch('pwr', 238, 180, { style = 'bat', len = 16, w = 9, label = '', labelClr = INK })
D:End()
