-- fxd-kit 2
-- Comp DIODE-609 (Arturia): blue 2-unit rack. Top: Compress L/R and Limit L/R rows of blue-cap knobs with printed
-- scales, two gain reduction VU meters, link switches, Mix, power lamp. Bottom: side chain, side-chain EQ, Input Drive.
local SFX = require('src.Functions.Stock FX UI')
local s = 216 / 470 -- the plugin window is 1436 x 470
-- the plugin's params: Ch.1 / Ch.2 pairs (L / R) from index 4 on
local P = { mix = { 'Dry/Wet Mix', idx = 26 }, ext = { 'Enable External Side Chain', idx = 27 }, la = { 'Look-ahead On/Off', idx = 28 },
    lat = { 'Look-ahead time', idx = 29 }, sce = { 'SC EQ On/Off', idx = 30 }, hpf = { 'SC EQ HPF Frequency', idx = 31 },
    mf = { 'SC EQ Mid Frequency', idx = 32 }, mg = { 'SC EQ Mid Gain', idx = 33 }, hs = { 'SC EQ Hi-Shelf Gain', idx = 34 },
    drive = { 'Input Drive', idx = 35 }, listen = { 'Sidechain Listen', idx = 36 }, gr = { 'Out Max Gain Reduction', idx = 37 },
    pwr = { 'Power On/Off', idx = 1 }, ms = { 'LR / MS Mode', idx = 2 }, st = { 'Stereo Mode', idx = 3 } }
for i, name in ipairs({ 'cin:Enable Comp:4', 'cth:Comp threshold:6', 'cat:Comp attack:8', 'crc:Comp recovery:10', 'crt:Comp ratio:12',
    'cmu:Comp make-up gain:14', 'lin:Enable Limiter:16', 'lfa:Enable Limiter Fast Attack:18', 'lth:Limiter threshold:20', 'lrc:Limiter recovery:22' }) do
    local k, n, base = name:match('^(%w+):(.-):(%d+)$')
    for ch = 1, 2 do P[k .. ch] = { 'Ch.' .. ch .. ': ' .. n, idx = tonumber(base) + ch - 1 } end
end
local D = SFX.Begin({ Title = 'Comp DIODE-609', W = math.floor(1436 * s), Accent = 0x2F5BD3ff, Params = P })
if not D then return end
local PANEL, LINE, INK = 0x3E4C86ff, 0x8E9BD2ff, 0xE9ECF6ff
local CAP = 0x2453C9ff
local function X(px) return px * s end -- a position in the picture -> the card

-- the two rack units
local fx, fy, fw = D:Faceplate(0, 0, D.W, X(318), { clr = PANEL, ears = true, earW = X(62) })
D:Faceplate(0, X(322), D.W, 216 - X(322), { clr = PANEL, ears = true, earW = X(62) })
for _, p in ipairs({ { 20, 18 }, { 1418, 18 }, { 20, 300 }, { 1418, 300 }, { 92, 338 }, { 1340, 338 }, { 92, 455 }, { 1340, 455 } }) do
    D:Screw(X(p[1]), X(p[2]), 3)
end

local function Knob(key, px, py, label, scale, o)
    o = o or {}
    D:Dial(key, X(px), X(py), 10, { style = 'cap', cap = CAP, label = label, labelClr = INK, labelSize = 7, scale = scale, minor = o.minor,
        tickClr = INK, scaleSize = 6, unit = o.unit, bipolar = o.bipolar })
end
local THR = { '-40', '-20', '0' }
local function CompRow(sfx, py, title)
    D:Inset(X(74), X(py - 70), X(546), X(140), { line = LINE, label = title, labelClr = INK })
    Knob('cth' .. sfx, 130, py, 'threshold', THR)
    Knob('cat' .. sfx, 222, py, 'attack ms', { 'fixed', '15', '75' })
    Knob('crc' .. sfx, 316, py, 'recovery ms', { '100', '800', 'a2' })
    Knob('cmu' .. sfx, 410, py, 'makeup gain', { '0', '8', '20' })
    Knob('crt' .. sfx, 505, py, 'ratio', { '1.5:1', '3:1', '6:1' })
    D:Switch('cin' .. sfx, X(582), X(py + 6), { style = 'paddle', len = 16, w = 8, label = 'in', labelClr = INK })
    D:Inset(X(624), X(py - 70), X(305), X(140), { line = LINE, label = (title:gsub('COMPRESS', 'LIMIT')), labelClr = INK })
    Knob('lth' .. sfx, 690, py, 'threshold', THR)
    Knob('lrc' .. sfx, 785, py, 'recovery ms', { '50', '200', 'a2' })
    D:Switch('lfa' .. sfx, X(862), X(py + 6), { style = 'paddle', len = 16, w = 8, up = 'fast', down = 'slow', labelClr = INK })
    D:Switch('lin' .. sfx, X(900), X(py + 6), { style = 'paddle', len = 16, w = 8, label = 'in', labelClr = INK })
end
CompRow('1', 92, 'COMPRESS L')
CompRow('2', 238, 'COMPRESS R')

-- gain reduction meters: this plugin reports its gain reduction as a param ('Out Max Gain Reduction'); for a plugin
-- that doesn't, estimate it from D:Level() and the threshold / ratio params
D:Inset(X(936), X(22), X(322), X(288), { line = LINE })
local GR_SCALE = { { 0, '20' }, { 0.3, '10' }, { 0.55, '5' }, { 0.75, '2' }, { 0.88, '1' }, { 1, '0' } }
for i, ch in ipairs({ 'L', 'R' }) do
    local mx = 952 + (i - 1) * 160
    D:Engrave(X(mx + 66), X(30), 'gain reduction ' .. ch, { clr = INK, size = 7, align = 'c' })
    D:VU(X(mx), X(50), X(132), X(116), 1 - D:Get('gr'), { face = 'black', scale = GR_SCALE, red = false, label = '' })
end
local SW = { style = 'paddle', len = 16, w = 8, labelClr = INK, labelSize = 6 }
D:Switch('st', X(1000), X(262), setmetatable({ up = 'dual mono', down = 'stereo' }, { __index = SW }))
D:Switch('ms', X(1070), X(262), setmetatable({ up = 'M/S', down = 'LR' }, { __index = SW }))
D:Dial('mix', X(1180), X(250), 12, { style = 'cap', cap = CAP, label = 'mix', labelClr = INK, ticks = 11, tickClr = INK,
    scale = { 'dry', 'wet' }, scaleSize = 6 })

-- power: lamp + bat toggle, then the name
D:Inset(X(1262), X(22), X(90), X(288), { line = LINE })
D:Lamp(X(1307), X(78), 5, D:On('pwr'), { clr = 0xFF4A2Eff })
D:Switch('pwr', X(1307), X(140), { style = 'bat', len = 18, w = 10, up = 'on', labelClr = INK })
D:Engrave(X(1307), X(205), 'Comp', { clr = INK, size = 9, align = 'c' })
D:Engrave(X(1307), X(228), 'DIODE-609', { clr = INK, size = 8, align = 'c' })

-- bottom unit: side chain + side-chain equalizer + input drive
D:Engrave(X(118), X(380), 'made in Grenoble', { clr = INK, size = 6, align = 'c' })
D:Inset(X(168), X(326), X(905), X(140), { line = LINE, label = 'SIDE-CHAIN EQUALIZER', labelClr = INK, labelSize = 7 })
D:Switch('ext', X(222), X(394), { style = 'paddle', len = 16, w = 8, up = 'external', down = 'internal', labelClr = INK, labelSize = 7 })
D:Dial('lat', X(318), X(394), 10, { style = 'cap', cap = CAP, label = 'look ahead', labelClr = INK, ticks = 7, tickClr = INK })
D:Switch('la', X(395), X(394), { style = 'paddle', len = 16, w = 8, label = 'in', labelClr = INK })
D:Line(X(440), X(338), X(440), X(440), LINE, 1)
Knob('hpf', 498, 394, 'high pass', { 'off', '80', '640' })
Knob('mf', 595, 394, 'mid freq', { '80', '1.2k', '10k' })
Knob('mg', 690, 394, 'mid gain', { '-10', '0', '+10' }, { bipolar = true })
Knob('hs', 785, 394, 'high shelf', { '-10', '0', '+10' }, { bipolar = true })
D:Switch('sce', X(860), X(394), { style = 'paddle', len = 16, w = 8, label = 'in', labelClr = INK })
D:Push('listen', X(978), X(381), X(46), X(24), { label = 'side chain listen', labelClr = INK })
D:Dial('drive', X(1185), X(394), 12, { style = 'cap', cap = CAP, label = 'input drive', labelClr = INK, ticks = 13, tickClr = INK,
    scale = { '0', '+12', '+24' }, scaleSize = 6 })
D:Engrave(X(1300), X(375), 'Processor', { clr = INK, size = 7, align = 'c' })
D:Engrave(X(1300), X(392), 'Advanced', { clr = INK, size = 7, align = 'c' })
D:Engrave(X(1300), X(409), 'Controls', { clr = INK, size = 7, align = 'c' })
D:End()
