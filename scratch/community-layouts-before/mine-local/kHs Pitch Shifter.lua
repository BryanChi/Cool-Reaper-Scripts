-- kHs Pitch Shifter (Kilohearts): Snapin header with power square, big Pitch number field, Correlate switch, Latency menu, Jitter / Grain Size / Mix knobs.
local SFX = require('src.Functions.Stock FX UI')
local D = SFX.Begin({
    Title = 'Pitch Shifter', W = 420, H = 170, Accent = SFX.ACCENT.Pitch,
    Params = {
        byp = { 'Bypass', idx = 0 }, pitch = { 'Pitch', idx = 1 }, jit = { 'Jitter', idx = 2 },
        grain = { 'Grain Size', idx = 3 }, mix = { 'Mix', idx = 4 }, algo = { 'Algorithm', idx = 5 },
        lat = { 'Latency Compensation', idx = 6 },
    },
})
if not D then return end
local C, A = SFX.C, SFX.A
local DL = D.DL
local BG, HDR, TXT, BLUE = 0x2A2C30FF, 0x1F2124FF, 0xCFCFCFFF, 0x3FA9F5FF

-- body and header strip
D:Rect(0, 0, 420, 170, BG, 4)
D:Rect(0, 0, 420, 24, HDR, 4)
D:Line(0, 24, 420, 24, 0x17181BFF, 1)

-- power checkbox (on = effect running, i.e. not bypassed)
local byp = D:Get('byp') > 0.5
if D:Btn('pwr', 8, 6, 12, 12) then D:Set('byp', byp and 0 or 1) end
D:Rect(8, 6, 12, 12, byp and A(BLUE, 0.15) or BLUE, 2)
D:Rect(8, 6, 12, 12, BLUE, 2, false, 1)
D:Text(28, 6, byp and C.TextDim or TXT, 'Pitch Shifter', 12, nil, true)

-- pitch number field
local L, T, R, B = D:Panel(10, 34, 130, 62)
local pv = D:Get('pitch')
local semis = -24 + 48 * pv
if math.abs(semis) < 0.005 then semis = 0 end
D:Text(75, 38, C.TextMute, 'PITCH', 8, 'c', true)
D:Text(75, 54, D.Acc, string.format('%+.2f', semis), 16, 'c', true)
local cx = (L + R) * 0.5
local by = B - 7
im.DrawList_AddLine(DL, L + 8, by, R - 8, by, C.Track, 2)
local px = L + 8 + (R - L - 16) * pv
im.DrawList_AddLine(DL, cx, by, px, by, D.Acc, 2)
im.DrawList_AddLine(DL, cx, by - 3, cx, by + 3, C.GridHi, 1)
if D:Lit('pitch') then
    im.DrawList_AddRect(DL, L, T, R, B, A(D.Acc, 0.6), 3, nil, 1)
end
if D.P.pitch then D:PrmSlider(D.P.pitch, 10, 34, 130, 62, nil) end

-- Correlate switch and latency menu
local corr = D:Get('algo') > 0.5
D:Toggle('algo', 10, 104, 130, 'CORRELATE', { on = corr })
D:Choice('lat', 10, 132, 130, { label = 'LATENCY', items = { { 'OFF', 0 }, { 'LOW', 0.5 }, { 'HIGH', 1 } } })

-- knobs
local gms = D:Val('grain') or (20 + 180 * D:Get('grain'))
D:Knob('jit', 205, 100, 'L', 'JITTER', { dim = corr, value = string.format('%.1f %%', D:Get('jit') * 100) })
D:Knob('grain', 285, 100, 'L', 'GRAIN SIZE', { value = string.format('%.1f ms', gms) })
D:Knob('mix', 365, 100, 'L', 'MIX', { value = string.format('%.0f %%', D:Get('mix') * 100) })

D:End()
