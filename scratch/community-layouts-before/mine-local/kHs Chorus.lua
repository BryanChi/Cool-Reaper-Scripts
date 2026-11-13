-- kHs Chorus (Kilohearts): bypass checkbox + title, Delay/Spread/Taps and Depth/Rate/Mix grid as in the plugin window.
local SFX = require('src.Functions.Stock FX UI')
local W, H = 232, 216
local D = SFX.Begin({
    Title = 'Chorus', W = W, H = H, Accent = SFX.ACCENT.Time,
    Params = {
        byp = { 'Bypass', idx = 0 }, delay = { 'Delay', idx = 1 }, rate = { 'Rate', idx = 2 },
        depth = { 'Depth', idx = 3 }, spread = { 'Spread', idx = 4 }, mix = { 'Mix', idx = 5 },
        taps = { 'Taps', idx = 6 },
    },
})
if not D then return end
local DL = D.DL
local BG = 0x464442FF
local BLUE = 0x6FA0EEFF
local DARK = 0x262422FF
local LBL = 0xBEBCBAFF
local TITLE = 0xC8C6C4FF

-- background and top strip
D:Rect(0, 0, W, H, BG, 0, true)
D:Rect(0, 0, W, 3, 0x3355DDFF, 0, true)

-- bypass checkbox (filled = effect active = Bypass off)
local active = D:Get('byp') < 0.5
local clicked, hov = D:Btn('khs_byp', 7, 10, 19, 19)
if clicked then D:Set('byp', active and 1 or 0) end
if active then
    D:Rect(7, 10, 19, 19, BLUE, 3, true)
else
    D:Rect(7, 10, 19, 19, DARK, 3, true)
    D:Rect(7, 10, 19, 19, SFX.A(BLUE, 0.6), 3, false, 1.5)
end
if hov then D:Rect(7, 10, 19, 19, 0xFFFFFF22, 3, true) end
im.DrawList_AddTextEx(DL, Font_SemiBold_16, 19, D.X + 34, D.Y + 9, TITLE, 'Chorus')

-- grid
local C1, C2, C3 = 42, 116, 189
local R1L, R1K = 47, 90
local R2L, R2K = 133, 175
local RAD = 18
local function knob(key, cx, ly, ky, label, unit)
    D:Text(cx, ly, LBL, label, 15, 'c')
    D:Knob(key, cx, ky, RAD, '', { unit = unit, accent = BLUE })
end
knob('delay', C1, R1L, R1K, 'Delay', 'ms')
knob('spread', C2, R1L, R1K, 'Spread', '%')
knob('depth', C1, R2L, R2K, 'Depth', 'ms')
knob('rate', C2, R2L, R2K, 'Rate', 'Hz')
knob('mix', C3, R2L, R2K, 'Mix', '%')

-- Taps segmented selector
D:Text(C3, R1L, LBL, 'Taps', 15, 'c')
local tx, tw = 161, 56
local sel3 = D:Get('taps') >= 0.5
local segs = { { '2', 70, false }, { '3', 91, true } }
for i, s in ipairs(segs) do
    local y = s[2]
    local on = (sel3 == s[3])
    local c, h2 = D:Btn('khs_taps' .. i, tx, y, tw, 20)
    if c then D:Set('taps', s[3] and 1 or 0) end
    D:Rect(tx, y, tw, 20, on and BLUE or DARK, 0, true)
    if h2 and not on then D:Rect(tx, y, tw, 20, 0xFFFFFF14, 0, true) end
    D:Text(tx + tw / 2, y + 3, on and DARK or LBL, s[1], 14, 'c')
end

D:End()
