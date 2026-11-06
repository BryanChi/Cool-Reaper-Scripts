-- @description Audio to MIDI
-- @version 1.1
-- @author BRYAN
-- @about
--   Turns the selected audio items into MIDI on a new track under each one.
--   Piano uses Transkun, a piano-only model, for notes, velocities and sustain pedal (CC64).
--   Poly uses Basic Pitch (Spotify's note model, run with ONNX Runtime) for chords, piano,
--   guitar and mixes. Mono tracks the pitch with pYIN for bass, vocals and leads, and can
--   add pitch bends. Drums sorts hits into kick / snare / hat. Auto picks one.
--   Needs ReaImGui and a Python venv (.venv-midi) next to this script; the window offers to
--   set it up on first run.
-- @provides
--   [main] .
--   AudioToMidi.py

local r = reaper
local TITLE = "Audio to MIDI"
local EXT = "BRYAN_AUDIO_TO_MIDI"
local JOB = nil

local function script_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  src = src:gsub("\\", "/")
  return src:match("^(.*)/") or "."
end

local function join_path(a, b)
  if not a or a == "" then return b end
  if a:sub(-1) == "/" or a:sub(-1) == "\\" then
    return a .. b
  end
  return a .. "/" .. b
end

local function dirname(p)
  if not p or p == "" then return "" end
  return p:match("^(.*)[/\\][^/\\]-$") or ""
end

local function basename_no_ext(p)
  local name = p:match("([^/\\]+)$") or p
  return name:match("^(.*)%.[^%.]+$") or name
end

local function file_exists(path)
  if not path or path == "" then return false end
  if r.file_exists then
    return r.file_exists(path)
  end
  local fh = io.open(path, "r")
  if fh then
    fh:close()
    return true
  end
  return false
end

local function shell_quote(s)
  s = tostring(s or ""):gsub("'", "'\\''")
  return "'" .. s .. "'"
end


local function ext_get(key, default)
  local v = r.GetExtState(EXT, key)
  if not v or v == "" then
    return default
  end
  return v
end

local function ext_set(key, value)
  r.SetExtState(EXT, key, tostring(value or ""), true)
end

local function filename_from_source(src)
  local a, b = r.GetMediaSourceFileName(src, "")
  if type(b) == "string" and b ~= "" then return b end
  if type(a) == "string" and a ~= "" then return a end
  return nil
end

local function resolve_media_path(src)
  local depth = 0
  while src and depth < 64 do
    local fn = filename_from_source(src)
    if fn and fn ~= "" then
      return fn
    end
    if not r.GetMediaSourceParent then
      break
    end
    src = r.GetMediaSourceParent(src)
    depth = depth + 1
  end
  return nil
end

local function project_dir()
  local _, projfn = r.EnumProjects(-1, "")
  if projfn and projfn ~= "" then
    return dirname(projfn)
  end
  return ""
end

local function absolutize(path)
  if not path or path == "" then return nil end
  if path:sub(1, 1) == "/" then return path end
  if path:match("^%a:[/\\]") then return path end
  local pd = project_dir()
  if pd ~= "" then
    return join_path(pd, path)
  end
  return path
end

local function read_all(path)
  local f = path and io.open(path, "r")
  if not f then return "" end
  local s = f:read("*a") or ""
  f:close()
  return s
end

local function read_progress(path)
  local s = read_all(path)
  local pct, msg = s:match("^(%d+)%s*([^\r\n]*)")
  pct = tonumber(pct) or 0
  return math.max(0, math.min(100, pct)), msg or ""
end

local function read_done(path)
  local s = read_all(path)
  return tonumber(s:match("%-?%d+"))
end

local function fmt_time(sec)
  sec = math.max(0, math.floor((sec or 0) + 0.5))
  local h = sec // 3600
  local m = (sec % 3600) // 60
  local s = sec % 60
  if h > 0 then
    return string.format("%d:%02d:%02d", h, m, s)
  end
  return string.format("%d:%02d", m, s)
end

local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local function note_name(p)
  return NOTE_NAMES[p % 12 + 1] .. tostring(p // 12 - 1)
end

---------------------------------------------------------------------------------------------
-- items

local function collect_jobs()
  local n = r.CountSelectedMediaItems(0)
  if n < 1 then
    return nil, "none"
  end
  local jobs = {}
  for i = 0, n - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    local take = item and r.GetActiveTake(item)
    if item and take and not r.TakeIsMIDI(take) then
      local src = r.GetMediaItemTake_Source(take)
      local path = src and resolve_media_path(src)
      path = path and absolutize(path)
      if path and file_exists(path) then
        local _, take_name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
        local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1
        if rate <= 0 then rate = 1 end
        local len = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
        local offs = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0
        -- the stretch of the file the item plays (a looped item reads its first pass)
        local src_len = r.GetMediaSourceLength(src)
        local dur = len * rate
        if src_len and src_len > 0 then
          offs = offs % src_len
          dur = math.min(dur, src_len - offs)
        end
        -- semitones the take sounds away from the file: take pitch, plus the playrate when
        -- "preserve pitch" is off
        local shift = r.GetMediaItemTakeInfo_Value(take, "D_PITCH") or 0
        if (r.GetMediaItemTakeInfo_Value(take, "B_PPITCH") or 0) == 0 then
          shift = shift + 12 * math.log(rate, 2)
        end
        jobs[#jobs + 1] = {
          item = item,
          take = take,
          track = r.GetMediaItemTrack(item),
          path = path,
          name = (take_name and take_name ~= "" and take_name) or basename_no_ext(path),
          position = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0,
          length = len,
          startoffs = offs,
          dur = dur,
          playrate = rate,
          shift = math.floor(shift + 0.5),
        }
      end
    end
  end
  if #jobs < 1 then
    return nil, "nofile"
  end
  return jobs
end

local RUN_ID = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))

local function job_paths(job, i)
  local base = os.getenv("TMPDIR")
  if not base or base == "" then base = "/tmp" end
  local out_dir = join_path(base, "audio_to_midi/" .. RUN_ID .. "_" .. i)
  return {
    out_dir = out_dir,
    notes = join_path(out_dir, "notes.txt"),
    progress = join_path(out_dir, "_progress.txt"),
    done = join_path(out_dir, "_done.txt"),
    log = join_path(out_dir, "_run.log"),
    pid = join_path(out_dir, "_pid.txt"),
  }
end

local SENS = { fewer = 0.25, normal = 0.5, more = 0.8 }
local SHORT = { ["30"] = 30, ["60"] = 60, ["120"] = 120 }

local function python_cmd(py, sidecar, job, opts, paths)
  local parts = {
    shell_quote(py), "-u",
    shell_quote(sidecar),
    "--in", shell_quote(job.path),
    "--out", shell_quote(paths.notes),
    "--start", string.format("%.6f", job.startoffs or 0),
    "--dur", string.format("%.6f", job.dur or 0),
    "--mode", opts.mode,
    "--sens", string.format("%.2f", SENS[opts.sens] or 0.5),
    "--min-ms", tostring(SHORT[opts.short] or 60),
    "--progress", shell_quote(paths.progress),
    "--done", shell_quote(paths.done),
  }
  if opts.bends then
    parts[#parts + 1] = "--bends"
  end
  return table.concat(parts, " ") .. " > " .. shell_quote(paths.log) .. " 2>&1"
end

local function parse_notes(path)
  local f = io.open(path, "r")
  if not f then
    return nil, "No notes file was written."
  end
  local res = { mode = "?", notes = {}, bends = {}, pedals = {}, info = "" }
  for line in f:lines() do
    local tag = line:sub(1, 2)
    if tag == "N " then
      local st, en, p, v = line:match("^N (%S+) (%S+) (%S+) (%S+)")
      st, en, p, v = tonumber(st), tonumber(en), tonumber(p), tonumber(v)
      if st and en and p and v then
        res.notes[#res.notes + 1] = { st, en, math.floor(p), math.floor(v) }
      end
    elseif tag == "B " then
      local t, v = line:match("^B (%S+) (%S+)")
      t, v = tonumber(t), tonumber(v)
      if t and v then
        res.bends[#res.bends + 1] = { t, math.floor(v) }
      end
    elseif tag == "P " then
      local st, en, cc, v = line:match("^P (%S+) (%S+) (%S+) (%S+)")
      st, en, cc, v = tonumber(st), tonumber(en), tonumber(cc), tonumber(v)
      if st and en and cc and v then
        res.pedals[#res.pedals + 1] = { st, en, math.floor(cc), math.floor(v) }
      end
    elseif line:sub(1, 5) == "MODE " then
      res.mode = line:sub(6)
    elseif line:sub(1, 5) == "INFO " then
      res.info = line:sub(6)
    end
  end
  f:close()
  return res
end

-- grid step in quarter notes (project grid; swing ignored)
local function grid_qn()
  local _, div = r.GetSetProjectGrid(0, false)
  div = tonumber(div) or 0.25
  if div <= 0 then div = 0.25 end
  return div * 4
end

local function snap_time(t, step)
  local qn = r.TimeMap2_timeToQN(0, t)
  return r.TimeMap2_QNToTime(0, math.floor(qn / step + 0.5) * step)
end

local function track_index(tr)
  return math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") + 0.5) - 1
end

local function last_folder_descendant_index(tr)
  local idx = track_index(tr)
  local depth = r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") or 0
  if depth < 1 then
    return idx
  end
  local n = r.CountTracks(0)
  for i = idx + 1, n - 1 do
    depth = depth + (r.GetMediaTrackInfo_Value(r.GetTrack(0, i), "I_FOLDERDEPTH") or 0)
    if depth <= 0 then
      return i
    end
  end
  return n - 1
end

local MODE_NAME = { piano = "Piano", poly = "Poly", mono = "Mono", drums = "Drums" }

--- puts the notes on a new track under the item's track; returns ok, err
local function import_notes(job, opts, res)
  if not job.item or not r.ValidatePtr2(0, job.item, "MediaItem*") then
    return false, "The original item is gone."
  end
  local tr = job.track
  local depth = r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
  local after = last_folder_descendant_index(tr) -- a folder parent: below the whole folder
  r.InsertTrackAtIndex(after + 1, true)
  local nt = r.GetTrack(0, after + 1)
  if depth < 0 then
    -- the item's track closes a folder: the new track stays in it and closes it instead
    r.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", 0)
    r.SetMediaTrackInfo_Value(nt, "I_FOLDERDEPTH", depth)
  end
  r.GetSetMediaTrackInfo_String(nt, "P_NAME", job.name .. " MIDI", true)
  local clr = r.GetTrackColor(tr)
  if clr ~= 0 then r.SetTrackColor(nt, clr) end

  local pos, len = job.position, job.length
  local item = r.CreateNewMIDIItemInProj(nt, pos, pos + len, false)
  if not item then
    return false, "Could not create the MIDI item."
  end
  local take = r.GetActiveTake(item)
  r.GetSetMediaItemTakeInfo_String(take, "P_NAME", job.name .. " MIDI", true)
  local rate = job.playrate
  local step = opts.snap and grid_qn() or nil
  local item_end = pos + len
  local lo, hi = 127, 0
  local count = 0
  local preview = {}
  for _, n in ipairs(res.notes) do
    local st = pos + n[1] / rate
    local en = pos + n[2] / rate
    if step then
      local sst = snap_time(st, step)
      local sen = snap_time(en, step)
      if sen <= sst then
        sen = r.TimeMap2_QNToTime(0, r.TimeMap2_timeToQN(0, sst) + step)
      end
      st, en = sst, sen
    end
    en = math.min(en, item_end)
    local p = n[3] + job.shift
    if st < item_end and en > st and p >= 0 and p <= 127 then
      local sp = r.MIDI_GetPPQPosFromProjTime(take, st)
      local ep = r.MIDI_GetPPQPosFromProjTime(take, en)
      if ep <= sp then ep = sp + 1 end
      r.MIDI_InsertNote(take, false, false, sp, ep, 0, p, math.max(1, math.min(127, n[4])), true)
      count = count + 1
      if p < lo then lo = p end
      if p > hi then hi = p end
      preview[#preview + 1] = { st - pos, en - pos, p, n[4] }
    end
  end
  if opts.bends then
    for _, b in ipairs(res.bends) do
      local t = pos + b[1] / rate
      if t < item_end then
        local v = math.max(0, math.min(16383, b[2] + 8192))
        r.MIDI_InsertCC(take, false, false, r.MIDI_GetPPQPosFromProjTime(take, t), 0xE0, 0, v & 0x7F, v >> 7)
      end
    end
  end
  local n_ped = 0
  for _, pd in ipairs(res.pedals) do
    local st = pos + pd[1] / rate
    local en = math.min(pos + pd[2] / rate, item_end - 0.001)
    if st < item_end and en > st then
      r.MIDI_InsertCC(take, false, false, r.MIDI_GetPPQPosFromProjTime(take, st), 0xB0, 0, pd[3], math.max(64, pd[4]))
      r.MIDI_InsertCC(take, false, false, r.MIDI_GetPPQPosFromProjTime(take, en), 0xB0, 0, pd[3], 0)
      n_ped = n_ped + 1
    end
  end
  r.MIDI_Sort(take)

  if opts.synth and res.mode ~= "drums" then
    r.TrackFX_AddByName(nt, "ReaSynth", false, -1)
  end
  if opts.mute_original then
    r.SetMediaItemInfo_Value(job.item, "B_MUTE", 1)
  end
  r.UpdateItemInProject(item)
  job.result = {
    mode = res.mode,
    count = count,
    bends = opts.bends and #res.bends or 0,
    pedals = n_ped,
    lo = lo,
    hi = hi,
    info = res.info,
    preview = preview,
    length = len,
  }
  job.midi_track = nt
  return true
end

local P = {
  page = 0x000000FF,
  body = 0x0C0C0DFF,
  chip = 0x111112FF,
  acc = 0x49CC85FF,
  red = 0xE0604FFF,
  ink = 0xF2F2F2FF,
  ink2 = 0x9A9A9AFF,
  ink3 = 0x5F5F5FFF,
  line = 0xFFFFFF1F,
  line2 = 0xFFFFFF33,
  soft = 0xFFFFFF0F,
  tick = 0xFFFFFF59,
}

local function alpha(clr, a)
  return (clr & 0xFFFFFF00) | math.floor(math.max(0, math.min(1, a)) * 255 + 0.5)
end

local function spawn_detached(cmd, pidfile)
  -- `exec` so the pid written is Python's own (Cancel kills it); cmd carries its own log redirect
  local inner = cmd
  if pidfile then
    inner = "echo $$ > " .. shell_quote(pidfile) .. "; exec " .. cmd
  end
  local line = "/bin/sh -c " .. shell_quote(inner) .. " </dev/null >/dev/null 2>&1 &"
  local rc = os.execute(line)
  return rc == true or rc == 0 or rc == nil
end

local function kill_job(job)
  local pid = tonumber((read_all(job.paths and job.paths.pid):match("%d+")))
  if pid and pid > 1 then
    os.execute("kill " .. pid .. " >/dev/null 2>&1")
  end
end

---------------------------------------------------------------------------------------------
-- options (ExtState keys are shared with the installer and older versions)

---------------------------------------------------------------------------------------------
-- ReaImGui

if not r.ImGui_GetBuiltinPath then
  r.MB("This script needs ReaImGui.\n\nInstall it with Extensions > ReaPack > Browse packages > ReaImGui, then run the script again.", TITLE, 0)
  return
end
package.path = r.ImGui_GetBuiltinPath() .. "/?.lua;" .. package.path
local im = require("imgui")("0.9.3")

local ctx = im.CreateContext(TITLE)
local F = {}
do
  local rp = r.GetResourcePath()
  local dirs = {
    join_path(script_dir(), "Fonts"),
    rp .. "/FX Devices GITHUB/BryanChi-FX-Devices/BryanChi_FX_Devices/src/Fonts",
    rp .. "/Scripts/FX Devices/BryanChi_FX_Devices/src/Fonts",
    rp .. "/Scripts/BryanChi-FX-Devices/BryanChi_FX_Devices/src/Fonts",
    rp .. "/Scripts/BryanChi_FX_Devices/src/Fonts",
  }
  local function find(file)
    for _, d in ipairs(dirs) do
      local p = join_path(d, file)
      if file_exists(p) then return p end
    end
  end
  local reg = find("JetBrainsMono-Medium.ttf")
  local bold = find("JetBrainsMono-SemiBold.ttf") or reg
  for _, sz in ipairs({ 9, 10, 11, 12 }) do
    F[sz] = im.CreateFont(reg or "monospace", sz)
    im.Attach(ctx, F[sz])
  end
  for _, sz in ipairs({ 10, 11, 14 }) do
    F["b" .. sz] = im.CreateFont(bold or "monospace", sz, (not bold) and im.FontFlags_Bold or nil)
    im.Attach(ctx, F["b" .. sz])
  end
end

local function font(sz, bold)
  return (bold and F["b" .. sz]) or F[sz] or F[11]
end

local AdvCache = {}
local function text_w(fnt, s)
  local k = tostring(fnt) .. s
  local w = AdvCache[k]
  if not w then
    im.PushFont(ctx, fnt)
    w = im.CalcTextSize(ctx, s)
    im.PopFont(ctx)
    AdvCache[k] = w
  end
  return w
end

local function upper(s)
  return (tostring(s):gsub("[a-z]", string.upper))
end
local function chars(s)
  return tostring(s):gmatch("[\0-\x7F\xC2-\xF4][\x80-\xBF]*")
end

--- letter-spaced caps; returns the x after the text
local function caps(dl, x, y, clr, s, sz, bold, sp)
  local fnt = font(sz, bold)
  sp = sp or sz * 0.12
  for ch in chars(upper(s)) do
    im.DrawList_AddTextEx(dl, fnt, sz, x, y, clr, ch)
    x = x + text_w(fnt, ch) + sp
  end
  return x - sp
end

local function caps_w(s, sz, bold, sp)
  local fnt = font(sz, bold)
  sp = sp or sz * 0.12
  local w, n = 0, 0
  for ch in chars(upper(s)) do
    w = w + text_w(fnt, ch)
    n = n + 1
  end
  return w + math.max(0, n - 1) * sp
end

--- plain text (names as typed), clipped to max_w with a trailing '…'
local function txt(dl, x, y, clr, s, sz, max_w)
  local fnt = font(sz)
  s = tostring(s or "")
  if max_w and text_w(fnt, s) > max_w then
    local t = {}
    for ch in chars(s) do t[#t + 1] = ch end
    while #t > 1 and text_w(fnt, table.concat(t) .. "…") > max_w do t[#t] = nil end
    s = table.concat(t) .. "…"
  end
  im.DrawList_AddTextEx(dl, fnt, sz, x, y, clr, s)
end

local function corner_ticks(dl, L, T, R, B, len, clr)
  len, clr = len or 6, clr or P.tick
  im.DrawList_AddLine(dl, L, T, L + len, T, clr, 1) im.DrawList_AddLine(dl, L, T, L, T + len, clr, 1)
  im.DrawList_AddLine(dl, R - len, T, R, T, clr, 1) im.DrawList_AddLine(dl, R, T, R, T + len, clr, 1)
  im.DrawList_AddLine(dl, L, B, L + len, B, clr, 1) im.DrawList_AddLine(dl, L, B - len, L, B, clr, 1)
  im.DrawList_AddLine(dl, R - len, B, R, B, clr, 1) im.DrawList_AddLine(dl, R, B - len, R, B, clr, 1)
end

local function dashed_rect(dl, L, T, R, B, clr)
  local function seg(x1, y1, x2, y2)
    local len = math.max(math.abs(x2 - x1), math.abs(y2 - y1))
    local dx, dy = (x2 - x1) / math.max(len, 1), (y2 - y1) / math.max(len, 1)
    local p = 0
    while p < len do
      local q = math.min(len, p + 4)
      im.DrawList_AddLine(dl, x1 + dx * p, y1 + dy * p, x1 + dx * q, y1 + dy * q, clr, 1)
      p = q + 3
    end
  end
  seg(L, T, R, T) seg(R, T, R, B) seg(R, B, L, B) seg(L, B, L, T)
end

---------------------------------------------------------------------------------------------
-- widgets (each takes the full row width W and advances the cursor)

local W = 432

local function gap(h)
  im.Dummy(ctx, W, h)
end

--- a section label with a hairline to the right edge; right = optional text at the far right
local function section(label, right, right_clr)
  local dl = im.GetWindowDrawList(ctx)
  local x, y = im.GetCursorScreenPos(ctx)
  local x2 = caps(dl, x, y, P.ink3, label, 9, true, 1.6)
  local rx = x + W
  if right and right ~= "" then
    local rw = caps_w(right, 9, false, 1.2)
    caps(dl, rx - rw, y, right_clr or P.ink2, right, 9, false, 1.2)
    rx = rx - rw - 10
  end
  if rx > x2 + 10 then
    im.DrawList_AddLine(dl, x2 + 10, y + 6, rx, y + 6, P.line, 1)
  end
  im.Dummy(ctx, W, 13)
  gap(4)
end

--- a row of equal cells; returns the picked key (or the current one)
local function segmented(id, opts, cur, h, disabled)
  local dl = im.GetWindowDrawList(ctx)
  local x, y = im.GetCursorScreenPos(ctx)
  h = h or 30
  local n = #opts
  local cw = W / n
  local picked = cur
  for i, o in ipairs(opts) do
    local L = math.floor(x + (i - 1) * cw + 0.5)
    local R = math.floor(x + i * cw + 0.5)
    im.SetCursorScreenPos(ctx, L, y)
    if im.InvisibleButton(ctx, id .. i, R - L, h) and not disabled then
      picked = o.key
    end
    local hov = im.IsItemHovered(ctx) and not disabled
    local on = o.key == cur
    if on then
      im.DrawList_AddRectFilled(dl, L, y, R, y + h, alpha(P.acc, disabled and 0.05 or 0.12))
    elseif hov then
      im.DrawList_AddRectFilled(dl, L, y, R, y + h, P.soft)
    end
    local clr = disabled and P.ink3 or (on and P.ink or (hov and P.ink or P.ink2))
    local tw = caps_w(o.label, 10, on, 1.4)
    local ty = y + (o.sub and (h / 2 - 11) or (h / 2 - 6))
    caps(dl, math.floor((L + R - tw) / 2), ty, clr, o.label, 10, on, 1.4)
    if o.sub then
      local sw = caps_w(o.sub, 9, false, 1)
      caps(dl, math.floor((L + R - sw) / 2), ty + 14, (on and not disabled) and P.ink2 or P.ink3, o.sub, 9, false, 1)
    end
    if i > 1 then
      im.DrawList_AddLine(dl, L, y, L, y + h, P.line2, 1)
    end
  end
  im.DrawList_AddRect(dl, x, y, x + W, y + h, P.line2, 0, 0, 1)
  -- the picked cell's edge in the accent, drawn last so it sits on top
  for i, o in ipairs(opts) do
    if o.key == cur then
      local L = math.floor(x + (i - 1) * cw + 0.5)
      local R = math.floor(x + i * cw + 0.5)
      im.DrawList_AddRect(dl, L, y, R + 1, y + h, alpha(P.acc, disabled and 0.3 or 0.85), 0, 0, 1)
    end
  end
  im.SetCursorScreenPos(ctx, x, y)
  im.Dummy(ctx, W, h)
  return picked
end

--- a square check and a caps label; w = its width; returns the new value
local function toggle(id, label, on, w)
  local dl = im.GetWindowDrawList(ctx)
  local x, y = im.GetCursorScreenPos(ctx)
  local h = 22
  local clicked = im.InvisibleButton(ctx, id, w, h)
  local hov = im.IsItemHovered(ctx)
  if hov then
    im.DrawList_AddRectFilled(dl, x, y, x + w, y + h, P.soft)
  end
  local bx, by, bs = x + 6, y + 5, 12
  im.DrawList_AddRect(dl, bx, by, bx + bs, by + bs, on and P.acc or (hov and P.ink2 or P.line2), 0, 0, 1)
  if on then
    im.DrawList_AddRectFilled(dl, bx + 3, by + 3, bx + bs - 3, by + bs - 3, P.acc)
  end
  caps(dl, bx + bs + 9, y + 6, on and P.ink or (hov and P.ink or P.ink2), label, 10, false, 1.3)
  if clicked then
    return not on
  end
  return on
end

--- a square button; kind = "primary" | "plain" | "danger"; returns true on click
local function button(id, label, w, h, kind, disabled)
  local dl = im.GetWindowDrawList(ctx)
  local x, y = im.GetCursorScreenPos(ctx)
  local clicked = im.InvisibleButton(ctx, id, w, h) and not disabled
  local hov = im.IsItemHovered(ctx) and not disabled
  local act = im.IsItemActive(ctx) and not disabled
  local base = kind == "primary" and P.acc or (kind == "danger" and P.red or P.ink)
  local fill, edge, clr
  if disabled then
    fill, edge, clr = 0, P.line, P.ink3
  elseif act then
    fill, edge, clr = base, base, P.page
  elseif kind == "plain" then
    fill, edge, clr = hov and P.soft or 0, hov and P.ink2 or P.line2, hov and P.ink or P.ink2
  else
    fill, edge, clr = alpha(base, hov and 0.24 or 0.12), alpha(base, hov and 1 or 0.8), P.ink
  end
  if fill ~= 0 then
    im.DrawList_AddRectFilled(dl, x, y, x + w, y + h, fill)
  end
  im.DrawList_AddRect(dl, x, y, x + w, y + h, edge, 0, 0, 1)
  local big = h >= 34
  local sz = big and 11 or 10
  local sp = big and 2.4 or 1.4
  local tw = caps_w(label, sz, big, sp)
  caps(dl, math.floor(x + (w - tw) / 2), math.floor(y + (h - sz) / 2) - 1, clr, label, sz, big, sp)
  if kind == "primary" and not disabled then
    corner_ticks(dl, x - 3, y - 3, x + w + 3, y + h + 3, 5, alpha(P.acc, hov and 0.9 or 0.45))
  end
  return clicked
end

--- a thin progress bar with the percent at the right
local function progress_bar(x, y, w, pct, clr)
  local dl = im.GetWindowDrawList(ctx)
  im.DrawList_AddRectFilled(dl, x, y, x + w, y + 2, P.line)
  local fw = math.floor(w * math.max(0, math.min(100, pct)) / 100 + 0.5)
  if fw > 0 then
    im.DrawList_AddRectFilled(dl, x, y, x + fw, y + 2, clr or P.acc)
  end
end

---------------------------------------------------------------------------------------------
-- options

local function load_opts()
  local function pick(key, default, allowed)
    local v = ext_get(key, default)
    return allowed[v] and v or default
  end
  return {
    mode = pick("MODE", "auto", { auto = 1, piano = 1, poly = 1, mono = 1, drums = 1 }),
    sens = pick("SENS", "normal", { fewer = 1, normal = 1, more = 1 }),
    short = pick("SHORT", "60", { ["30"] = 1, ["60"] = 1, ["120"] = 1 }),
    bends = ext_get("BENDS", "n") == "y",
    snap = ext_get("SNAP", "n") == "y",
    synth = ext_get("SYNTH", "y") == "y",
    mute_original = ext_get("MUTE", "n") == "y",
  }
end

local function save_opts(o)
  ext_set("MODE", o.mode)
  ext_set("SENS", o.sens)
  ext_set("SHORT", o.short)
  ext_set("BENDS", o.bends and "y" or "n")
  ext_set("SNAP", o.snap and "y" or "n")
  ext_set("SYNTH", o.synth and "y" or "n")
  ext_set("MUTE", o.mute_original and "y" or "n")
end

---------------------------------------------------------------------------------------------
-- state

local UI = {
  phase = "setup", -- setup | running | done | install
  opts = load_opts(),
  open = true,
  shown = true,
  items = nil,
  items_err = nil,
  items_t = -1,
  env_err = nil,
  py = nil,
  sidecar = nil,
}

local VENV = ".venv-midi"

-- The venv next to this script, else one in any folder in Scripts
local function find_python(dir)
  local function venv(d) return join_path(d, VENV .. "/bin/python") end
  if file_exists(venv(dir)) then return venv(dir) end
  local scripts = r.GetResourcePath() .. "/Scripts"
  local dirs = { join_path(scripts, "Bryan's Scripts") }
  local k = 0
  while true do
    local sub = r.EnumerateSubdirectories(scripts, k)
    if not sub then break end
    dirs[#dirs + 1] = join_path(scripts, sub)
    k = k + 1
  end
  for _, d in ipairs(dirs) do
    if file_exists(venv(d)) then return venv(d) end
  end
  return venv(dir)
end

local function check_env()
  local dir = script_dir()
  UI.py = find_python(dir)
  UI.sidecar = join_path(dir, "AudioToMidi.py")
  if r.GetOS():match("Win") then
    UI.env_err = "This script runs on macOS and Linux for now."
  elseif not file_exists(UI.sidecar) then
    UI.env_err = "AudioToMidi.py not found next to this script:\n" .. UI.sidecar
  elseif not file_exists(UI.py) then
    UI.env_err = "venv"
  else
    UI.env_err = nil
  end
end

-- one-time setup: a venv next to this script with Basic Pitch (ONNX) + librosa
local INSTALL = {}
local function install_cmd(dir)
  local venv = join_path(dir, VENV)
  local sh = [[
set -e
PY=""
for c in /opt/homebrew/bin/python3.13 /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3.11 \
         /usr/local/bin/python3.13 /usr/local/bin/python3.12 /usr/local/bin/python3.11 \
         python3.13 python3.12 python3.11 python3; do
  if command -v "$c" >/dev/null 2>&1; then PY="$c"; break; fi
done
[ -n "$PY" ] || { echo "No python3 found. Install Python 3.11+ first."; exit 1; }
echo "Using $PY"
"$PY" -m venv "$VENV"
"$VENV/bin/pip" install -q --upgrade pip
"$VENV/bin/pip" install --no-deps basic-pitch==0.4.0
"$VENV/bin/pip" install onnxruntime librosa scipy resampy pretty_midi mir_eval scikit-learn soundfile
"$VENV/bin/pip" install transkun soxr moduleconf
"$VENV/bin/python" -c "import basic_pitch, onnxruntime, librosa, transkun; print('ok')"
]]
  return "VENV=" .. shell_quote(venv) .. "; export VENV; " .. sh
end

local function start_install()
  local base = os.getenv("TMPDIR")
  if not base or base == "" then base = "/tmp" end
  local d = join_path(base, "audio_to_midi/install_" .. RUN_ID)
  r.RecursiveCreateDirectory(d, 0)
  INSTALL = {
    log = join_path(d, "log.txt"),
    done = join_path(d, "done.txt"),
    pid = join_path(d, "pid.txt"),
    t0 = r.time_precise(),
  }
  local cmd = "/bin/sh -c " .. shell_quote(install_cmd(script_dir())) .. " > " .. shell_quote(INSTALL.log)
    .. " 2>&1; echo $? > " .. shell_quote(INSTALL.done)
  spawn_detached("/bin/sh -c " .. shell_quote(cmd), INSTALL.pid)
  UI.phase = "install"
end

local function refresh_items(force)
  local now = r.time_precise()
  if not force and now - UI.items_t < 0.3 then
    return
  end
  UI.items_t = now
  local jobs, err = collect_jobs()
  UI.items = jobs
  UI.items_err = (not jobs) and err or nil
end

local function opts_for_run()
  local o = UI.opts
  return {
    mode = o.mode,
    sens = o.sens,
    short = o.short,
    bends = o.bends and (o.mode == "mono" or o.mode == "auto"),
    snap = o.snap,
    synth = o.synth,
    mute_original = o.mute_original,
  }
end

local function pid_alive(job)
  local pid = tonumber((read_all(job.paths.pid):match("%d+")))
  if not pid then return true end -- not written yet
  local rc = os.execute("kill -0 " .. pid .. " >/dev/null 2>&1")
  return rc == true or rc == 0
end

local function start_job(j)
  local job = j.batch[j.cur]
  job.status = "running"
  job.pct = 0
  job.msg = "Starting…"
  job.t0 = r.time_precise()
  job.last_check = job.t0
  if not spawn_detached(job.cmd, job.paths.pid) then
    job.status = "failed"
    job.err = "Could not start AudioToMidi.py."
    return false
  end
  return true
end

local function start_run()
  refresh_items(true)
  if not UI.items or UI.env_err then
    return
  end
  save_opts(UI.opts)
  local opts = opts_for_run()
  for i, job in ipairs(UI.items) do
    job.paths = job_paths(job, i)
    r.RecursiveCreateDirectory(job.paths.out_dir, 0)
    job.cmd = python_cmd(UI.py, UI.sidecar, job, opts, job.paths)
    job.status = "queued"
    job.pct = 0
    job.msg = ""
  end
  JOB = { batch = UI.items, cur = 1, opts = opts, t0 = r.time_precise(), max_wait = 30 * 60 }
  UI.phase = "running"
  start_job(JOB)
end

local function finish_run()
  JOB.t1 = r.time_precise()
  UI.phase = "done"
  if not UI.shown then
    UI.shown = true
    UI.open = true
  end
end

local function next_job()
  local j = JOB
  while j.cur < #j.batch do
    j.cur = j.cur + 1
    if start_job(j) then
      return
    end
  end
  finish_run()
end

local function fail_job(job, msg)
  job.status = "failed"
  job.err = msg
  local log = read_all(job.paths.log)
  job.log = log ~= "" and log:sub(-2500) or nil
end

local function import_job(job, code)
  if code ~= 0 then
    local _, msg = read_progress(job.paths.progress)
    fail_job(job, (msg ~= "" and msg) or ("Transcription failed (exit " .. tostring(code) .. ")."))
    return
  end
  local res, err = parse_notes(job.paths.notes)
  if not res then
    fail_job(job, err)
    return
  end
  if #res.notes == 0 then
    fail_job(job, "No notes found. Try More notes, or another mode.")
    job.log = nil
    return
  end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local ok, msg = import_notes(job, JOB.opts, res)
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock("Audio to MIDI: " .. job.name, -1)
  if not ok then
    fail_job(job, msg)
    return
  end
  job.status = "done"
  job.pct = 100
end

local function tick()
  local j = JOB
  if not j or UI.phase ~= "running" then
    return
  end
  local job = j.batch[j.cur]
  if job.status == "importing" then
    import_job(job, job.code)
    job.t1 = r.time_precise()
    next_job()
    return
  end
  if job.status ~= "running" then
    next_job()
    return
  end
  local code = read_done(job.paths.done)
  if code == nil then
    local pct, msg = read_progress(job.paths.progress)
    job.pct = pct
    if msg ~= "" then job.msg = msg end
    local now = r.time_precise()
    if now - job.last_check > 1 then
      job.last_check = now
      if now - job.t0 > 3 and not pid_alive(job) and read_done(job.paths.done) == nil then
        fail_job(job, "The transcriber stopped without finishing.")
        job.t1 = now
        next_job()
        return
      end
    end
    if now - job.t0 > j.max_wait then
      kill_job(job)
      fail_job(job, "Timed out after " .. fmt_time(j.max_wait) .. ".")
      job.t1 = now
      next_job()
    end
    return
  end
  job.code = code
  job.status = "importing"
  job.pct = 100
  job.msg = (code == 0) and "Writing MIDI…" or "Failed"
end

local function cancel_run()
  local j = JOB
  if not j then return end
  for i = j.cur, #j.batch do
    local job = j.batch[i]
    if job.status == "running" then
      kill_job(job)
    end
    if job.status == "running" or job.status == "queued" or job.status == "importing" then
      job.status = "cancelled"
    end
  end
  finish_run()
end

---------------------------------------------------------------------------------------------
-- drawing

local function header()
  local dl = im.GetWindowDrawList(ctx)
  local x, y = im.GetCursorScreenPos(ctx)
  local x2 = caps(dl, x, y + 1, P.ink, "Audio to MIDI", 14, true, 3.2)
  im.DrawList_AddRectFilled(dl, x2 + 8, y + 6, x2 + 13, y + 11, P.acc)
  caps(dl, x2 + 20, y + 4, P.ink3, "Transkun · Basic Pitch", 9, false, 1.3)
  local cx = x + W - 18
  im.SetCursorScreenPos(ctx, cx, y - 2)
  if im.InvisibleButton(ctx, "##close", 18, 18) then
    UI.open = false
  end
  local hov = im.IsItemHovered(ctx)
  local c = hov and P.ink or P.ink3
  im.DrawList_AddLine(dl, cx + 5, y + 3, cx + 13, y + 11, c, 1.2)
  im.DrawList_AddLine(dl, cx + 13, y + 3, cx + 5, y + 11, c, 1.2)
  im.SetCursorScreenPos(ctx, x, y)
  im.Dummy(ctx, W, 18)
  gap(6)
  local x3, y3 = im.GetCursorScreenPos(ctx)
  im.DrawList_AddLine(dl, x3, y3, x3 + W, y3, P.line2, 1)
  gap(12)
end

local function item_row(job, right, right_clr, stripe)
  local dl = im.GetWindowDrawList(ctx)
  local x, y = im.GetCursorScreenPos(ctx)
  local h = 22
  im.DrawList_AddRectFilled(dl, x, y, x + W, y + h, P.body)
  im.DrawList_AddRectFilled(dl, x, y, x + 2, y + h, stripe or P.ink3)
  local rw = right and caps_w(right, 9, false, 1.1) or 0
  txt(dl, x + 12, y + 5, P.ink, job.name, 11, W - 30 - rw)
  if right then
    caps(dl, x + W - 10 - rw, y + 6, right_clr or P.ink2, right, 9, false, 1.1)
  end
  im.Dummy(ctx, W, h)
end

local function wrapped(text, clr)
  im.PushFont(ctx, font(11))
  im.PushStyleColor(ctx, im.Col_Text, clr or P.ink2)
  im.PushTextWrapPos(ctx, im.GetCursorPosX(ctx) + W)
  im.TextWrapped(ctx, text)
  im.PopTextWrapPos(ctx)
  im.PopStyleColor(ctx)
  im.PopFont(ctx)
end

local function log_box(id, text, h)
  im.PushFont(ctx, font(9))
  im.PushStyleColor(ctx, im.Col_FrameBg, P.body)
  im.PushStyleColor(ctx, im.Col_Text, P.ink2)
  im.InputTextMultiline(ctx, id, text, W, h or 96, im.InputTextFlags_ReadOnly)
  im.PopStyleColor(ctx, 2)
  im.PopFont(ctx)
end

local function draw_env_error()
  section("Setup")
  if UI.env_err == "venv" then
    wrapped("First run: this needs a Python environment (Basic Pitch, Transkun piano model, librosa; about 1 GB with PyTorch) in\n"
      .. join_path(script_dir(), VENV))
    gap(14)
    if button("##install", "Set up", W, 34, "primary") then
      start_install()
    end
  else
    wrapped(UI.env_err)
  end
  gap(10)
  if button("##close2", "Close", W, 28, "plain") then
    UI.open = false
  end
end

local function draw_install()
  local code = read_done(INSTALL.done)
  local log = read_all(INSTALL.log)
  local label = code == nil and "Setting up" or (code == 0 and "Ready" or "Setup failed")
  section(label, fmt_time(r.time_precise() - INSTALL.t0), code == nil and P.ink2 or (code == 0 and P.acc or P.red))
  log_box("##ilog", log:sub(-3000), 140)
  gap(14)
  if code == nil then
    if button("##icancel", "Cancel", W, 30, "danger") then
      local pid = tonumber((read_all(INSTALL.pid):match("%d+")))
      if pid then os.execute("kill " .. pid .. " >/dev/null 2>&1") end
      UI.phase = "setup"
    end
  elseif code == 0 then
    check_env()
    if button("##icont", "Continue", W, 34, "primary") then
      UI.phase = "setup"
    end
  else
    if button("##iclose", "Back", W, 30, "plain") then
      UI.phase = "setup"
    end
  end
end

local MODE_OPTS = {
  { key = "auto", label = "Auto", sub = "picks one" },
  { key = "piano", label = "Piano", sub = "+ pedal" },
  { key = "poly", label = "Poly", sub = "chords" },
  { key = "mono", label = "Mono", sub = "one line" },
  { key = "drums", label = "Drums", sub = "kit" },
}

local function draw_setup()
  refresh_items(false)
  local o = UI.opts
  local items = UI.items

  section("Source", items and (#items .. (#items == 1 and " item" or " items")) or nil)
  if items then
    local shown = math.min(#items, 4)
    for i = 1, shown do
      local job = items[i]
      item_row(job, fmt_time(job.length))
      if i < shown then gap(2) end
    end
    if #items > shown then
      gap(4)
      local dl = im.GetWindowDrawList(ctx)
      local x, y = im.GetCursorScreenPos(ctx)
      caps(dl, x + 12, y, P.ink3, "+" .. (#items - shown) .. " more", 9, false, 1.1)
      im.Dummy(ctx, W, 11)
    end
  else
    local dl = im.GetWindowDrawList(ctx)
    local x, y = im.GetCursorScreenPos(ctx)
    local h = 44
    dashed_rect(dl, x, y, x + W, y + h, P.line2)
    local msg = UI.items_err == "nofile" and "No audio file on disk. Glue the item first." or "Select audio items"
    local tw = caps_w(msg, 10, false, 1.4)
    caps(dl, math.floor(x + (W - tw) / 2), y + h / 2 - 6, P.ink2, msg, 10, false, 1.4)
    im.Dummy(ctx, W, h)
  end
  gap(16)

  section("Sound")
  o.mode = segmented("##mode", MODE_OPTS, o.mode, 38)
  gap(16)

  section("Notes")
  local x0, y0 = im.GetCursorScreenPos(ctx)
  local half = (W - 8) / 2
  local saveW = W
  W = half
  o.sens = segmented("##sens", {
    { key = "fewer", label = "Fewer" },
    { key = "normal", label = "Normal" },
    { key = "more", label = "More" },
  }, o.sens, 28)
  im.SetCursorScreenPos(ctx, x0 + half + 8, y0)
  o.short = segmented("##short", {
    { key = "30", label = "30 ms" },
    { key = "60", label = "60 ms" },
    { key = "120", label = "120 ms" },
  }, o.short, 28)
  W = saveW
  local dl = im.GetWindowDrawList(ctx)
  local y1 = y0 + 28 + 6
  caps(dl, x0, y1, P.ink3, "Amount", 9, false, 1.1)
  caps(dl, x0 + half + 8, y1, P.ink3, "Shortest note", 9, false, 1.1)
  im.SetCursorScreenPos(ctx, x0, y1)
  im.Dummy(ctx, W, 12)
  gap(14)

  section("Options")
  local x, y = im.GetCursorScreenPos(ctx)
  local bend_ok = o.mode == "mono" or o.mode == "auto"
  local b = toggle("##bends", bend_ok and "Pitch bends" or "Pitch bends (mono)", o.bends and bend_ok, W / 2 - 2)
  if bend_ok then o.bends = b end
  im.SetCursorScreenPos(ctx, x + W / 2 + 2, y)
  o.snap = toggle("##snap", "Snap to grid", o.snap, W / 2 - 2)
  x, y = im.GetCursorScreenPos(ctx)
  o.synth = toggle("##synth", "Add ReaSynth", o.synth, W / 2 - 2)
  im.SetCursorScreenPos(ctx, x + W / 2 + 2, y)
  o.mute_original = toggle("##mute", "Mute original", o.mute_original, W / 2 - 2)
  gap(20)

  local n = items and #items or 0
  local label = n > 1 and ("Convert " .. n .. " items") or "Convert"
  local go = button("##go", label, W, 38, "primary", n == 0)
  local enter = n > 0 and not im.IsAnyItemActive(ctx)
    and (im.IsKeyPressed(ctx, im.Key_Enter) or im.IsKeyPressed(ctx, im.Key_KeypadEnter))
  if go or enter then
    start_run()
  end
end

local function status_word(job)
  if job.status == "done" then
    return job.result.count .. " notes", P.acc
  elseif job.status == "failed" then
    return "Failed", P.red
  elseif job.status == "cancelled" then
    return "Cancelled", P.ink3
  elseif job.status == "running" or job.status == "importing" then
    return job.pct .. "%", P.ink
  end
  return "Queued", P.ink3
end

--- a small piano roll of the result
local function mini_roll(res)
  local dl = im.GetWindowDrawList(ctx)
  local x, y = im.GetCursorScreenPos(ctx)
  local h = 54
  im.DrawList_AddRectFilled(dl, x, y, x + W, y + h, P.body)
  im.DrawList_AddRect(dl, x, y, x + W, y + h, P.line, 0, 0, 1)
  local lo, hi = res.lo, res.hi
  if hi - lo < 11 then
    local mid = (lo + hi) / 2
    lo, hi = math.floor(mid - 6), math.floor(mid + 6)
  end
  local span = hi - lo + 1
  -- the pitch axis always fits the box: a wide range (a whole piano) gets
  -- rows thinner than a pixel; each note is still drawn at least 1 px tall
  local rh = math.min(4, (h - 6) / span)
  local nh = math.max(1, rh)
  local top = y + 3 + ((h - 6) - rh * span) / 2
  local len = math.max(0.001, res.length)
  local x0, x1 = x + 2, x + W - 2
  im.DrawList_PushClipRect(dl, x + 1, y + 1, x + W - 1, y + h - 1, true)
  for _, n in ipairs(res.preview) do
    local L = math.max(x0, x0 + (W - 4) * n[1] / len)
    local R = math.min(x1, math.max(L + 1, x0 + (W - 4) * math.min(n[2], len) / len))
    local T = top + (hi - n[3]) * rh
    if T + nh > y + h - 3 then T = y + h - 3 - nh end
    if T < y + 3 then T = y + 3 end
    if R > L then
      im.DrawList_AddRectFilled(dl, L, T, R, T + nh, alpha(P.acc, 0.35 + 0.65 * n[4] / 127))
    end
  end
  im.DrawList_PopClipRect(dl)
  im.Dummy(ctx, W, h)
end

local function draw_job_detail(job)
  local dl = im.GetWindowDrawList(ctx)
  if job.status == "running" or job.status == "importing" then
    gap(6)
    local x, y = im.GetCursorScreenPos(ctx)
    progress_bar(x, y, W, job.pct)
    im.Dummy(ctx, W, 2)
    gap(6)
    x, y = im.GetCursorScreenPos(ctx)
    txt(dl, x + 12, y, P.ink2, job.msg or "", 10, W - 12)
    im.Dummy(ctx, W, 12)
  elseif job.status == "done" then
    local res = job.result
    gap(4)
    mini_roll(res)
    gap(4)
    local x, y = im.GetCursorScreenPos(ctx)
    local line = (MODE_NAME[res.mode] or res.mode)
    if (res.info or ""):find("no piano found", 1, true) then
      line = "No piano found, used Poly"
    end
    if res.mode == "drums" then
      line = line .. "  ·  kick 36  snare 38  hat 42"
    else
      line = line .. "  ·  " .. note_name(res.lo) .. " – " .. note_name(res.hi)
      if res.bends > 0 then line = line .. "  ·  pitch bends" end
      if res.pedals > 0 then line = line .. "  ·  " .. res.pedals .. " pedal" .. (res.pedals == 1 and "" or "s") end
    end
    txt(dl, x + 12, y, P.ink2, line, 10, W - 12)
    im.Dummy(ctx, W, 12)
  elseif job.status == "failed" then
    gap(4)
    local x, y = im.GetCursorScreenPos(ctx)
    txt(dl, x + 12, y, P.red, job.err or "Failed", 10, W - 12)
    im.Dummy(ctx, W, 12)
    if job.log then
      gap(4)
      log_box("##log" .. tostring(job.item), job.log, 96)
    end
  end
end

local function draw_run()
  local j = JOB
  local done = UI.phase == "done"
  local n_ok, n_fail = 0, 0
  for _, job in ipairs(j.batch) do
    if job.status == "done" then n_ok = n_ok + 1 end
    if job.status == "failed" then n_fail = n_fail + 1 end
  end
  local total = fmt_time((j.t1 or r.time_precise()) - j.t0)
  local label
  if done then
    label = n_fail > 0 and (n_ok .. " / " .. #j.batch .. " converted") or "Done"
  else
    label = "Converting " .. j.cur .. " / " .. #j.batch
  end
  section(label, total, done and (n_fail > 0 and P.red or P.acc) or P.ink2)

  for i, job in ipairs(j.batch) do
    local word, clr = status_word(job)
    local stripe = (job.status == "done" and P.acc) or (job.status == "failed" and P.red)
      or ((job.status == "running" or job.status == "importing") and P.ink) or P.ink3
    item_row(job, word, clr, stripe)
    draw_job_detail(job)
    if i < #j.batch then gap(10) end
  end
  gap(18)

  if done then
    local bw = (W - 8) / 2
    if button("##again", "Back", bw, 32, "plain") then
      JOB = nil
      UI.phase = "setup"
      refresh_items(true)
    end
    im.SameLine(ctx, 0, 8)
    if button("##done", "Close", bw, 32, "primary") then
      UI.open = false
    end
  else
    if button("##cancel", "Cancel", W, 32, "danger") then
      cancel_run()
    end
  end
end

local function push_style()
  im.PushStyleVar(ctx, im.StyleVar_WindowRounding, 0)
  im.PushStyleVar(ctx, im.StyleVar_FrameRounding, 0)
  im.PushStyleVar(ctx, im.StyleVar_WindowBorderSize, 1)
  im.PushStyleVar(ctx, im.StyleVar_WindowPadding, 20, 18)
  im.PushStyleVar(ctx, im.StyleVar_ItemSpacing, 0, 0)
  im.PushStyleVar(ctx, im.StyleVar_ScrollbarRounding, 0)
  im.PushStyleColor(ctx, im.Col_WindowBg, P.page)
  im.PushStyleColor(ctx, im.Col_Border, P.line2)
  im.PushStyleColor(ctx, im.Col_Text, P.ink)
  im.PushStyleColor(ctx, im.Col_TextSelectedBg, alpha(P.acc, 0.35))
  im.PushStyleColor(ctx, im.Col_ScrollbarBg, P.page)
  im.PushStyleColor(ctx, im.Col_ScrollbarGrab, P.line2)
  return 6, 6
end

local function loop()
  if UI.phase == "running" then
    tick()
  end

  if UI.shown then
    local nv, nc = push_style()
    local flags = im.WindowFlags_NoTitleBar | im.WindowFlags_AlwaysAutoResize | im.WindowFlags_NoCollapse
      | im.WindowFlags_NoScrollbar | im.WindowFlags_NoDocking
    im.SetNextWindowPos(ctx, 220, 180, im.Cond_FirstUseEver)
    local visible, open = im.Begin(ctx, TITLE, true, flags)
    if visible then
      local dl = im.GetWindowDrawList(ctx)
      local wx, wy = im.GetWindowPos(ctx)
      local ww, wh = im.GetWindowSize(ctx)
      corner_ticks(dl, wx + 7, wy + 7, wx + ww - 7, wy + wh - 7, 7, P.tick)
      header()
      if UI.phase == "install" then
        draw_install()
      elseif UI.env_err then
        draw_env_error()
      elseif UI.phase == "setup" then
        draw_setup()
      else
        draw_run()
      end
      if im.IsWindowFocused(ctx, im.FocusedFlags_RootAndChildWindows) and im.IsKeyPressed(ctx, im.Key_Escape)
        and UI.phase ~= "running" and UI.phase ~= "install" then
        UI.open = false
      end
      im.End(ctx)
    end
    im.PopStyleColor(ctx, nc)
    im.PopStyleVar(ctx, nv)
    if open == false then
      UI.open = false
    end
  end

  if not UI.open then
    if UI.phase == "running" then
      -- keep going in the background; the window comes back with the results
      UI.shown = false
      UI.open = true
    else
      return
    end
  end
  r.defer(loop)
end

check_env()
refresh_items(true)
r.defer(loop)
