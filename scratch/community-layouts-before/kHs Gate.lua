-- kHs Gate (Kilohearts): bypass checkbox + title, two-column knob grid, dB meter with the threshold/tolerance band,
-- Look-ahead / Flip checkboxes and the Sidechain drop-down, laid out as in the plugin window.
-- Drawn at the plugin's own proportions (233 x 412) scaled by S to fit FXD's fixed device height.
local SFX = require('src.Functions.Stock FX UI')
local S = 0.51 
local SX = S
local W, H = math.floor(233 * SX), 216
local D = SFX.Begin({
    Title = 'Gate', W = W, H = H, Accent = SFX.ACCENT.Dynamics,
    Params = {
        attack = { 'Attack', idx = 0 }, hold = { 'Hold', idx = 1 }, release = { 'Release', idx = 2 },
        thr = { 'Threshold', idx = 3 }, tol = { 'Tolerance', idx = 4 }, range = { 'Range', idx = 5 },
        look = { 'Look-ahead', idx = 6 }, flip = { 'Flip', idx = 7 }, byp = { 'Bypass', idx = 8 },
    },
})
if not D then return end
local DL = D.DL
local BG = 0x353A45FF
local BLUE = 0x6FA8FFFF
local OFFBOX = 0x4A4E57FF
local DARK = 0x2A2D35FF
local LBL = 0xE6E8ECFF
local RED = 0xD03A3AFF
local function f(sz) return math.max(6, math.floor(sz * S + 0.5)) end

D:Rect(0, 0, W, H, BG, 0, true)
D:Rect(0, 0, W, 2, 0xA09A3CFF, 0, true)

-- bypass checkbox (filled = effect active = Bypass off) + title
local active = D:Get('byp') < 0.5
local bs = 19 * S
local clicked, hov = D:Btn('khs_byp', 7 * SX, 11 * S, bs, bs)
if clicked then D:Set('byp', active and 1 or 0) end
D:Rect(7 * SX, 11 * S, bs, bs, active and BLUE or OFFBOX, 2, true)
if hov then D:Rect(7 * SX, 11 * S, bs, bs, 0xFFFFFF22, 2, true) end
D:Text(34 * SX, 10 * S, LBL, 'Gate', f(18))

-- knobs: label above, no value text (the plugin shows none)
local C1, C2 = 46 * SX, 133 * SX
local function knob(key, cx, cy, label)
    D:Text(cx, (cy - 39) * S, LBL, label, f(15), 'c')
    D:Knob(key, cx, cy * S, 6.5, nil, { value = ' ', accent = BLUE })
end
knob('thr', C1, 96, 'Threshold')
knob('range', C2, 96, 'Range')
knob('tol', C1, 185, 'Tolerance')
knob('hold', C2, 185, 'Hold')
knob('attack', C1, 274, 'Attack')
knob('release', C2, 274, 'Release')

-- dB meter: 0 dB at y 71, 3.6 px per dB (plugin pixels)
local MX, MY, MW, MH = 176 * SX, 46 * S, 15 * SX, 250 * S
D:Rect(MX, MY, MW, MH, 0x272A31FF, 0, true)
local function dbY(db) return (71 - db * 3.6) * S end
for _, t in ipairs({ { 0, '- 0 dB' }, { -20, '- 20' }, { -40, '- 40' }, { -60, '- 60' } }) do
    D:Text(194 * SX, dbY(t[1]) - 4, LBL, t[2], f(14))
end
if D.P.thr and D.P.tol then
    local thr = -60 + 66 * D:Get('thr')
    local tol = 20 * D:Get('tol')
    local y1, y2 = dbY(thr), dbY(thr - tol)
    D:Rect(MX, y1, MW, y2 - y1, SFX.A(RED, 0.25), 0, true)
    D:Line(MX, y1, MX + MW, y1, RED, 1)
    D:Line(MX, y2, MX + MW, y2, RED, 1)
end

-- Look-ahead / Flip checkboxes
local function check(id, key, x, y, label)
    local on = D:On(key)
    local sz = 20 * S
    local c, h = D:Btn(id, x * SX, y * S, sz, sz)
    if c then D:Set(key, on and 0 or 1) end
    D:Rect(x * SX, y * S, sz, sz, on and BLUE or OFFBOX, 2, true)
    if h then D:Rect(x * SX, y * S, sz, sz, 0xFFFFFF22, 2, true) end
    D:Text((x + 27) * SX, y * S + 1, LBL, label, f(15))
end
check('khs_look', 'look', 20, 319, 'Look-ahead')
check('khs_flip', 'flip', 157, 319, 'Flip')

-- Sidechain drop-down (not a plugin parameter: drawn only)
D:Text(16 * SX, 355 * S, LBL, 'Sidechain', f(15))
D:Rect(6 * SX, 379 * S, 221 * SX, 23 * S, DARK, 0, true)
D:Text(13 * SX, 383 * S + 1, LBL, 'OFF', f(14))
local cx, cy = D.X + 215 * SX, D.Y + 391 * S
im.DrawList_AddTriangleFilled(DL, cx - 3, cy - 2, cx + 3, cy - 2, cx, cy + 2.5, LBL)

D:End()
