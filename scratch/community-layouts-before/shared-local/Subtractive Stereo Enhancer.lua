-- Subtractive Stereo Enhancer (Cockos JSFX): toolbar toggles and Wet, title bar, Effect and Make-Up Gain slider rows.
local SFX = require('src.Functions.Stock FX UI')
local D = SFX.Begin({
    Title = 'Subtractive Stereo Enhancer', W = 440, Accent = SFX.ACCENT.Utility,
    Params = {
        effect = { 'Effect (%)', 'Effect', idx = 0 },
        gain = { 'Make-Up Gain (dB)', 'Make-Up Gain', idx = 1 },
        bypass = { 'Bypass', idx = 2 },
        wet = { 'Wet', idx = 3 },
        delta = { 'Delta', idx = 4 },
    },
})
if not D then return end
local C, A = SFX.C, SFX.A
local BG = 0x333333FF
local ACC = 0x8FA3B8FF
D:Rect(0, 0, D.W, 216, BG, 0, true)

-- top strip
D:Toggle('bypass', 8, 12, 78, 'Bypass', { on = D:Get('bypass') > 0.5, accent = ACC })
D:Toggle('delta', 94, 12, 78, 'Delta', { on = D:Get('delta') > 0.5, accent = ACC })
D:Bar('wet', 184, 12, 248, 16, 'Wet', { unit = '%', accent = ACC })

-- title bar
local L, T, R, B = D:Panel(8, 56, 424, 28)
D:Text(220, 63, C.Text, 'Subtractive Stereo Enhancer', 12, 'c', false)

-- slider rows
local function row(key, label, y)
    local h = 22
    local x0, w = 160, 200
    D:Text(150, y + 5, C.Text, label, 12, 'r', false)
    D:Rect(x0, y, w, h, 0x2A2A2AFF, 2, true)
    D:Rect(x0, y, w, h, 0x1A1A1AFF, 2, false, 1)
    local v = D:Get(key)
    local hx = x0 + v * (w - 12)
    D:Rect(hx, y + 1, 12, h - 2, 0x9A9A9AFF, 2, true)
    D:Rect(hx + 5, y + 4, 2, h - 8, 0x3A3A3AFF, 0, true)
    local clicked, hovered, active = D:Btn('sl_' .. key, x0, y, w, h)
    if active then
        local mx = im.GetMousePos(ctx)
        D:Set(key, SFX.Clamp((mx - D.X - x0 - 6) / (w - 12), 0, 1))
    end
    D:Rect(370, y, 62, h, 0x111111FF, 2, true)
    D:Rect(370, y, 62, h, 0x666666FF, 2, false, 1)
    D:Text(376, y + 5, 0xFFFFFFFF, D:Fmt(key), 12, nil, false)
end
row('effect', 'Effect (%)', 104)
row('gain', 'Make-Up Gain (dB)', 140)
D:End()