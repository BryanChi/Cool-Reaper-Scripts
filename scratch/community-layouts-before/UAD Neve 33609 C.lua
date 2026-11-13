-- UAD Neve 33609 C: two channel strips with grouped limiter (Thld, Recovr) and compressor (Thld, Ratio, Recovr, Gain) knobs, Output in the free space, red In LEDs, Slow/Fast switches, centre link / HPF / mix / headroom / power, in a wood frame.
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
local A = SFX.A
local DL = D.DL

local WOOD, WOOD_D = 0x8B3A1BFF, 0x5A230FFF
local SLATE, SLATE_D = 0x2F3846FF, 0x1E242EFF
local GROUP, GROUP_E = 0x262D38FF, 0x4A5666FF
local WHITE = 0xE8EBF0FF
local KNOB = 0xD6DAE0FF
local RED = 0xC0222EFF
local RED_ON = 0xFF3A3AFF
local RED_OFF = 0x4A1418FF
local KR = 14

D:Rect(0, 0, 476, 216, WOOD, 4, true)
D:Rect(1, 1, 474, 214, WOOD_D, 4, false, 2)

local function screw(x, y)
    im.DrawList_AddCircleFilled(DL, D.X + x, D.Y + y, 2.5, 0x14171CFF)
end

-- red indicator LED; lit = the section is In (param value 0)
local function led(key, cx, cy)
    local on = D:Get(key) < 0.5
    local clicked, hovered = D:Btn('led_' .. key, cx - 9, cy - 9, 18, 18)
    if clicked then D:Set(key, on and 1 or 0) end
    local x, y = D.X + cx, D.Y + cy
    if on then
        im.DrawList_AddCircleFilled(DL, x, y, 9, A(RED_ON, 0.25))
        im.DrawList_AddCircleFilled(DL, x, y, 6, RED_ON)
        im.DrawList_AddCircleFilled(DL, x - 1.5, y - 1.5, 2, 0xFFB0B0FF)
    else
        im.DrawList_AddCircleFilled(DL, x, y, 6, RED_OFF)
    end
    im.DrawList_AddCircle(DL, x, y, 6.5, hovered and 0xE8EBF0FF or 0x14171CFF, 0, 1.2)
end

-- attack switch label shows the active mode: Fast or Slow
local function atk(key) return D:Get(key) > 0.5 and 'Fast' or 'Slow' end

local function channel(ch, px)
    D:Rect(px, 12, 189, 192, SLATE, 2, true)
    D:Rect(px, 12, 189, 192, SLATE_D, 2, false, 1)
    -- group boxes: limiter (2 knobs) and compressor (4 knobs)
    D:Rect(px + 4, 58, 84, 70, GROUP, 3, true)
    D:Rect(px + 4, 58, 84, 70, GROUP_E, 3, false, 1)
    D:Rect(px + 92, 58, 93, 134, GROUP, 3, true)
    D:Rect(px + 92, 58, 93, 134, GROUP_E, 3, false, 1)
    D:Text(px + 46, 17, WHITE, 'LIMITER', 8, 'c')
    D:Text(px + 138, 17, WHITE, 'COMPRESSOR', 8, 'c')
    screw(px + 7, 198)
    screw(px + 182, 198)
    local s = tostring(ch)
    -- limiter: In LED + attack switch
    led('li' .. s, px + 14, 37)
    D:Text(px + 14, 47, WHITE, 'IN', 8, 'c')
    D:Toggle('la' .. s, px + 26, 28, 58, atk('la' .. s), { accent = 0xE8E2D0FF })
    -- compressor: In LED + attack switch
    led('ci' .. s, px + 102, 37)
    D:Text(px + 102, 47, WHITE, 'IN', 8, 'c')
    D:Toggle('ca' .. s, px + 112, 28, 70, atk('ca' .. s), { accent = 0xE8E2D0FF })
    local rowA, rowB, rowO = 93, 156, 162
    -- limiter group
    D:Knob('lt' .. s, px + 25, rowA, KR, 'THLD', { accent = KNOB })
    D:Knob('lr' .. s, px + 67, rowA, KR, 'RECOVR', { accent = KNOB })
    -- compressor group (2 x 2)
    D:Knob('ct' .. s, px + 115, rowA, KR, 'THLD', { accent = KNOB })
    D:Knob('cq' .. s, px + 162, rowA, KR, 'RATIO', { accent = KNOB })
    D:Knob('cr' .. s, px + 115, rowB, KR, 'RECOVR', { accent = KNOB })
    D:Knob('cg' .. s, px + 162, rowB, KR, 'GAIN', { accent = KNOB })
    -- output in the free space under the limiter group, nudged down away from it
    D:Knob('out' .. s, px + 46, rowO, KR, 'OUTPUT', { accent = RED })
end

channel(1, 16)
channel(2, 271)

-- centre panel
D:Rect(207, 12, 62, 192, 0x2A323DFF, 2, true)
D:Rect(207, 12, 62, 192, SLATE_D, 2, false, 1)
screw(214, 197)
screw(262, 197)
D:Toggle('clink', 211, 22, 54, 'Link', { accent = RED })
D:Toggle('slink', 211, 44, 54, 'Mono', { accent = RED })
D:Knob('sc', 222, 98, 8, 'HPF', { accent = KNOB })
D:Knob('mix', 254, 98, 8, 'Mix', { accent = KNOB })
D:Bar('hr', 211, 146, 54, 12, 'HR', { accent = KNOB })
D:Toggle('pwr', 211, 172, 54, 'Power', { accent = 0xE8E2D0FF })
D:End()
