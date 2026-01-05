-- @description Sample Map Browser (Lua + ReaImGui)
-- @version 0.1.0
-- @author bryan
-- @about Scans user folders for audio files, derives simple metadata, and shows an interactive 2D map where each file is a dot. Click a dot to preview the file.
-- @requires ReaImGui

local r = reaper

-- Check for ReaImGui
if not r.APIExists('ImGui_GetVersion') then
  r.ShowMessageBox("ReaImGui is required for this script.", "Missing dependency", 0)
  return
end

-- Check for JS_ReaScriptAPI (optional but recommended for folder browsing)
if not r.APIExists("JS_Dialog_BrowseForFolder") then
  r.ShowMessageBox("JS_ReaScriptAPI extension is recommended for folder browsing.\n\nInstall via: Extensions > ReaPack > Browse Packages > Search 'js_ReaScriptAPI'\n\nYou can still use the script, but folder selection will be limited.", "Extension Recommended", 0)
end

-- --- Script state ------------------------------------------------------------
local SCRIPT_NAME = "Sample Map Browser"
local SCRIPT_DIR = r.GetResourcePath() .. "/Scripts/BRYAN's SCRIPTS"
local CONFIG_DIR = SCRIPT_DIR
local CONFIG_PATH = CONFIG_DIR .. "/SampleMapBrowser.json"
local DATA_PATH = SCRIPT_DIR .. "/SampleMapData.json"  -- Cached sample index

local AUDIO_EXTS = {
  [".wav"] = true, [".wave"] = true, [".aif"] = true, [".aiff"] = true,
  [".flac"] = true, [".mp3"] = true, [".ogg"] = true, [".m4a"] = true, [".wv"] = true
}

-- Common tag keywords (ordered by priority for tagging)
local TAG_KEYWORDS = {
  {tag = "kick",   keys = {"kick", "kck"}, weight = 100},
  {tag = "snare",  keys = {"snare", "snr"}, weight = 95},
  {tag = "clap",   keys = {"clap"}, weight = 92},
  {tag = "snap",   keys = {"snap", "finger", "finger snap", "finger snaps", "fingersnap", "fingersnaps"}, weight = 91},
  {tag = "rim",    keys = {"rim", "rimshot"}, weight = 90},
  {tag = "hat",    keys = {"hat", "hihat", "oh", "ch", "hh"}, weight = 88},
  {tag = "tom",    keys = {"tom"}, weight = 82},
  {tag = "ride",   keys = {"ride"}, weight = 80},
  {tag = "crash",  keys = {"crash", "cymbal"}, weight = 79},
  {tag = "perc",   keys = {"perc", "percussion", "shaker", "tamb", "cowbell"}, weight = 76},
  {tag = "fx",     keys = {"fx", "sfx", "impact", "whoosh", "sweep", "riser", "uplift", "downlift"}, weight = 74},
  {tag = "bass",   keys = {"bass", "sub"}, weight = 70},
  {tag = "808",    keys = {"808"}, weight = 69},
  {tag = "vocal",  keys = {"vocal", "vox", "voice"}, weight = 65},
  {tag = "drum",   keys = {"drum", "beat", "break"}, weight = 58},
  {tag = "pad",    keys = {"pad"}, weight = 55},
  {tag = "lead",   keys = {"lead"}, weight = 54},
  {tag = "pluck",  keys = {"pluck"}, weight = 53},
  {tag = "keys",   keys = {"keys", "piano"}, weight = 52},
  {tag = "guitar", keys = {"guitar"}, weight = 50},
}

local state = {
  folders = {},
  samples = {},
  scan_queue = {},
  scan_started = 0.0,
  scan_total = 0,
  scanned_paths = {},  -- Set of already-scanned file paths (for resuming)
  selected = nil,
  filter = "",
  active_tags = {},      -- Tag filters toggled by the user
  tag_list = {},         -- Cached sorted list of tags with counts
  tag_counts = {},       -- Map<tag,count>
  scan_logs = {},        -- Rolling buffer of scan/analyzer logs
  map_seed = 1337,
  zoom = 1.0,  -- Zoom level (1.0 = normal)
  pan_x = 0.0,  -- Pan offset X
  pan_y = 0.0,  -- Pan offset Y
  drag_start_x = nil,  -- Drag start position
  drag_start_y = nil,
  drag_start_pan_x = 0.0,
  drag_start_pan_y = 0.0,
  is_dragging = false,  -- Right mouse drag for panning
  is_left_dragging = false,  -- Left mouse drag for selecting samples
  last_dragged_sample_path = nil,  -- Track last sample previewed during drag
  pending_waveform_drop = nil,  -- Sample waiting to be dropped (global drag operation)
  last_mouse_time_pos = nil,  -- Last known mouse time position during drag
  last_mouse_track = nil,     -- Last known mouse track during drag
  external_disabled = false,  -- Stop trying analyzer after first hard failure
  analyzer_warned = false,
  folder_filter_path = nil,  -- Filter by folder path (nil = no filter)
  settings_open = false,  -- Settings window open/closed state
  played_history = {},  -- Array of played samples (history)
  history_index = 0,  -- Current position in history (0 = most recent, higher = older)
  hovered_tag = nil,  -- Currently hovered tag name
  tag_color_picker_open = false,  -- Whether color picker popup is open
  tag_color_picker_tag = nil,  -- Tag being edited in color picker
  current_preset_name = "Default",  -- Currently active preset name
  -- Dot customization settings
  dot_radius = 2.0,  -- Base dot radius
  dot_outline_size = 4.0,  -- Outline size for selected/playing sample
  dot_outline_thickness = 3.0,  -- Outline thickness
  dot_color = 0x44AA55,     -- Dot color (RRGGBB format, default: green)
  dot_outline_color = 0xFF00FF,   -- Outline color (RRGGBB format, default: magenta)
  dot_hover_color = 0xC84D,       -- Hover highlight color (RRGGBB format, default: yellow)
  dot_detection_multiplier = 16.0,  -- Detection radius multiplier (multiplies dot_radius)
  -- Tag colors (RRGGBB format - full opacity)
  tag_colors = {
    kick = 0x6B46C1,      -- Purple
    snare = 0xFF6B6B,     -- Red
    clap = 0x4ECDC4,      -- Teal
    rim = 0xFFBE0B,       -- Yellow
    hat = 0x8338EC,       -- Purple-blue
    tom = 0x3A86FF,       -- Blue
    ride = 0x06FFA5,      -- Green
    crash = 0xFF006E,     -- Pink
    perc = 0xFFB703,      -- Orange
    fx = 0x9B5DE5,        -- Light purple
    bass = 0x00F5FF,      -- Cyan
    ["808"] = 0xFFD60A,   -- Gold
    vocal = 0xFF9F43,     -- Orange
    loop = 0x0ABDE3,      -- Light blue
    drum = 0xFF3838,      -- Red
    pad = 0xA29BFE,       -- Light purple
    lead = 0xFD79A8,      -- Pink
    pluck = 0x00B894,     -- Green
    keys = 0xE17055,      -- Coral
    guitar = 0x6C5CE7,    -- Purple
  },
  -- Pop effect animation
  pop_start_time = nil,  -- When pop animation started (nil = no pop)
  pop_duration = 0.3,  -- Pop animation duration in seconds
  breathing_start_time = nil,  -- When breathing cycle started (resets on dot click)
  -- Parallel analyzer processing
  analyzer_queue = {},              -- Files waiting for analyzer processing
  analyzer_results = {},            -- Map: path -> analyzer_data (completed results)
  active_processes = {},            -- Table of active analyzer processes: {path, pipe, start_time}
  max_concurrent_analyzers = 2,     -- Number of parallel analyzer processes (reduced to prevent file handle exhaustion)
  last_save_time = 0.0,             -- Timestamp of last cache save
}

local ctx = nil
local font = nil
local running = true
local preview_proc = nil  -- preview handle/ID (integer ID for Xen_StartSourcePreview, or boolean for other APIs)
local preview_track = nil  -- dedicated preview track (for PlayTrackPreview2)
local PYTHON_BIN = "/usr/bin/python3"
local EXTERNAL_ANALYZER = SCRIPT_DIR .. "/SampleMapAnalyzer.py"  -- External analysis script path
local preview_source = nil  -- PCM_Source for preview
local preview_start_time = 0.0  -- When preview started
local preview_sample_obj = nil  -- Currently previewing sample object
local waveform_data = nil  -- Cached waveform data for current preview
local waveform_width = 800  -- Width of waveform display
local PREVIEW_TRACK_NAME = "__SampleMapPreview"
local cf_preview_obj = nil  -- CF_Preview object (light userdata) for seeking support


-- --- Helper functions ---------------------------------------------------------
local function log(msg)
  r.ShowConsoleMsg("[SampleMap] " .. tostring(msg) .. "\n")
end

local function add_scan_log(msg)
  local timestamp = os.date("%H:%M:%S")
  local line = string.format("[%s] %s", timestamp, tostring(msg))
  table.insert(state.scan_logs, line)
  if #state.scan_logs > 500 then
    table.remove(state.scan_logs, 1)
  end
end

local function get_scan_logs_text()
  return table.concat(state.scan_logs, "\n")
end


local function shell_escape(str)
  return '"' .. tostring(str):gsub('"', '\\"') .. '"'
end


-- Normalize path separators for macOS (ensure forward slashes)
local function normalize_path(path)
  if not path or path == "" then
    return path
  end
  -- Replace backslashes with forward slashes
  path = path:gsub("\\", "/")
  -- Remove trailing slash
  path = path:gsub("/+$", "")
  return path
end

-- Get filename without path
local function basename(path)
  if not path then return "" end
  local norm = normalize_path(path)
  return norm:match("([^/]+)$") or norm
end

-- Set media take name with logging (preferred) and fallback to item name
local function set_item_name(item, take, sample_path)
  if (not item and not take) or not sample_path then
    log("set_item_name: missing item/take or path")
    return
  end
  local name = basename(sample_path)
  local ok_take = nil
  if take then
    ok_take = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", name, true)
  end
  local ok_item = nil
  if item then
    ok_item = r.GetSetMediaItemInfo_String(item, "P_NAME", name, true)
  end
  log(string.format("Naming to '%s' take_result=%s item_result=%s", name, tostring(ok_take), tostring(ok_item)))
end


-- Build ARGB color from RGB components (0-255)
local function build_color(r, g, b, a)
  a = a or 255
  return 0xFF000000 | (math.floor(r) << 16) | (math.floor(g) << 8) | math.floor(b)
end

-- Extract RGB components from RRGGBBAA format color
local function extract_rgb_rrgbbaa(color)
  if not color then return 0, 0, 0 end
  local r = math.floor((color / 16777216) % 256)   -- Extract red (first byte)
  local g = math.floor((color / 65536) % 256)     -- Extract green
  local b = math.floor((color / 256) % 256)       -- Extract blue
  return r, g, b
end

-- Build RRGGBBAA color from RGB components (0-255) and alpha (0-255, default 255)
local function build_color_rrgbbaa(r, g, b, a)
  a = a or 255
  return (math.floor(r) * 16777216) + (math.floor(g) * 65536) + (math.floor(b) * 256) + math.floor(a)
end

-- Extract RGB from RRGGBB color (24-bit)
local function extract_rgb(color)
  if not color then return 0, 0, 0 end
  local r = math.floor((color / 65536) % 256)
  local g = math.floor((color / 256) % 256)
  local b = math.floor(color % 256)
  return r, g, b
end

-- Build RRGGBB color from RGB components (0-255)
local function build_rgb(r, g, b)
  return (math.floor(r) * 65536) + (math.floor(g) * 256) + math.floor(b)
end



local function pick_number(ret, default)
  default = default or 0.0
  if type(ret) == "number" then
    return ret
  elseif type(ret) == "table" then
    for _, v in ipairs(ret) do
      if type(v) == "number" then
        return v
      end
    end
  end
  return default
end


local function pick_bool(ret, default)
  default = default or false
  if type(ret) == "boolean" then
    return ret
  elseif type(ret) == "table" then
    for _, v in ipairs(ret) do
      if type(v) == "boolean" then
        return v
      end
    end
  end
  return default
end


-- Detect if sample is a loop or oneshot based on filename/path patterns
local function detect_loop_or_oneshot(path, folder)
  local path_lower = path:lower()
  local folder_lower = (folder or ""):lower()
  
  -- Check for oneshot first (explicit keywords)
  if path_lower:find("oneshot") or path_lower:find("one%-shot") or 
     folder_lower:find("oneshot") or folder_lower:find("one%-shot") then
    return "One shot"
  end
  
  -- Check for loop keywords in filename/path
  if path_lower:find("loop") or path_lower:find("looped") or 
     path_lower:find("lpd") or path_lower:find("repeat") or 
     path_lower:find("cycle") or path_lower:find("cycling") then
    return "loop"
  end
  
  -- Check for loop patterns: _loop, -loop, loop_, loop-
  if path_lower:find("[_%-]loop") or path_lower:find("loop[_%-]") then
    return "loop"
  end
  
  -- Check for BPM references (usually indicates loops)
  if path_lower:find("%d+bpm") or path_lower:find("%d+_bpm") or 
     path_lower:find("%d+%-bpm") then
    return "loop"
  end
  
  -- Check for musical keys (usually indicates loops)
  -- Pattern: Am, C#m, Fmaj, etc.
  if path_lower:find("[a-g][#b]?m?aj?") or path_lower:find("key") then
    return "loop"
  end
  
  -- Check for bar/measure references (usually indicates loops)
  if path_lower:find("%d+bar") or path_lower:find("%d+_bar") or 
     path_lower:find("%d+%-bar") then
    return "loop"
  end
  
  -- Check folder structure patterns for loops
  if folder_lower:find("loop") or folder_lower:find("looped") then
    return "loop"
  end
  
  -- Check for specific loop folder patterns
  if folder_lower:find("drum loop") or folder_lower:find("bass loop") or 
     folder_lower:find("melodic loop") or folder_lower:find("full loop") or
     folder_lower:find("construction kit") then
    return "loop"
  end
  
  -- Check for BPM folders (usually contain loops)
  if folder_lower:find("%d+%s+bpm") or folder_lower:find("%d+%-bpm") then
    return "loop"
  end
  
  return nil
end


-- Extract meaningful tags from filename and folder tokens
local function infer_tags_from_path(path, folder)
  local tokens = {}
  local function collect(str)
    if not str or str == "" then return end
    for token in tostring(str):lower():gmatch("%w+") do
      tokens[token] = true
    end
  end
  collect(path or "")
  collect(folder or "")

  local scored = {}
  for _, entry in ipairs(TAG_KEYWORDS) do
    for _, key in ipairs(entry.keys) do
      if tokens[key] then
        local current = scored[entry.tag] or 0
        if entry.weight > current then
          scored[entry.tag] = entry.weight
        end
        break
      end
    end
  end

  local sorted = {}
  for tag, weight in pairs(scored) do
    table.insert(sorted, {tag = tag, weight = weight})
  end
  table.sort(sorted, function(a, b)
    if a.weight == b.weight then
      return a.tag < b.tag
    end
    return a.weight > b.weight
  end)

  local tags = {}
  for _, entry in ipairs(sorted) do
    tags[#tags + 1] = entry.tag
    if #tags >= 6 then break end -- Keep cache lean
  end

  return tags
end


-- Build tag list and counts for UI
local function rebuild_tag_index()
  local counts = {}
  for _, s in ipairs(state.samples) do
    if s.tags and type(s.tags) == "table" then
      for _, tag in ipairs(s.tags) do
        counts[tag] = (counts[tag] or 0) + 1
      end
    end
  end

  state.tag_counts = counts
  state.tag_list = {}
  for tag, count in pairs(counts) do
    table.insert(state.tag_list, {tag = tag, count = count})
  end
  table.sort(state.tag_list, function(a, b)
    if a.count == b.count then
      return a.tag < b.tag
    end
    return a.count > b.count
  end)
end


local function shell_escape(str)
  return '"' .. tostring(str):gsub('"', '\\"') .. '"'
end


-- --- JSON helpers (improved) ----------------------------------------------------
local function json_encode_string(s)
  -- Escape special characters in strings
  s = s:gsub('\\', '\\\\')
  s = s:gsub('"', '\\"')
  s = s:gsub('\n', '\\n')
  s = s:gsub('\r', '\\r')
  s = s:gsub('\t', '\\t')
  return '"' .. s .. '"'
end

local function json_encode(val)
  if type(val) == "table" then
    local parts = {}
    local is_array = true
    local max_idx = 0
    for k, v in pairs(val) do
      if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
        is_array = false
        break
      end
      max_idx = math.max(max_idx, k)
    end
    
    if is_array then
      for i = 1, max_idx do
        table.insert(parts, json_encode(val[i]))
      end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      for k, v in pairs(val) do
        table.insert(parts, json_encode_string(tostring(k)) .. ":" .. json_encode(v))
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  elseif type(val) == "string" then
    return json_encode_string(val)
  elseif type(val) == "number" then
    return tostring(val)
  elseif type(val) == "boolean" then
    return val and "true" or "false"
  else
    return "null"
  end
end


local function json_decode(str)
  -- Improved JSON decoder that handles strings with commas and special chars
  str = str:match("%s*(.*)")
  if str:sub(1, 1) == "{" then
    local obj = {}
    str = str:sub(2, -2) -- remove {}
    
    -- Parse key-value pairs, handling quoted strings properly
    local pos = 1
    while pos <= #str do
      -- Skip whitespace
      while pos <= #str and str:sub(pos, pos):match("%s") do
        pos = pos + 1
      end
      if pos > #str then break end
      
      -- Find key (quoted string)
      if str:sub(pos, pos) ~= '"' then break end
      local key_start = pos + 1
      local key_end = key_start
      while key_end <= #str do
        if str:sub(key_end, key_end) == '"' and str:sub(key_end - 1, key_end - 1) ~= '\\' then
          break
        end
        key_end = key_end + 1
      end
      local key = str:sub(key_start, key_end - 1):gsub('\\"', '"'):gsub('\\\\', '\\')
      
      -- Skip to colon
      pos = key_end + 1
      while pos <= #str and str:sub(pos, pos) ~= ':' do pos = pos + 1 end
      pos = pos + 1
      
      -- Skip whitespace
      while pos <= #str and str:sub(pos, pos):match("%s") do pos = pos + 1 end
      
      -- Parse value
      if str:sub(pos, pos) == '"' then
        -- String value
        local val_start = pos + 1
        local val_end = val_start
        while val_end <= #str do
          if str:sub(val_end, val_end) == '"' and str:sub(val_end - 1, val_end - 1) ~= '\\' then
            break
          end
          val_end = val_end + 1
        end
        obj[key] = str:sub(val_start, val_end - 1):gsub('\\"', '"'):gsub('\\\\', '\\'):gsub('\\n', '\n'):gsub('\\r', '\r'):gsub('\\t', '\t')
        pos = val_end + 1
      elseif str:sub(pos, pos) == '[' then
        -- Array value - find matching bracket
        local depth = 1
        local arr_start = pos
        pos = pos + 1
        while pos <= #str and depth > 0 do
          if str:sub(pos, pos) == '[' then depth = depth + 1
          elseif str:sub(pos, pos) == ']' then depth = depth - 1 end
          pos = pos + 1
        end
        local arr_str = str:sub(arr_start, pos - 1)
        obj[key] = json_decode(arr_str)
      elseif str:sub(pos, pos) == '{' then
        -- Object value - find matching brace
        local depth = 1
        local obj_start = pos
        pos = pos + 1
        while pos <= #str and depth > 0 do
          if str:sub(pos, pos) == '{' then depth = depth + 1
          elseif str:sub(pos, pos) == '}' then depth = depth - 1 end
          pos = pos + 1
        end
        local obj_str = str:sub(obj_start, pos - 1)
        obj[key] = json_decode(obj_str)
      else
        -- Number or boolean
        local val_end = pos
        while val_end <= #str and str:sub(val_end, val_end) ~= ',' and str:sub(val_end, val_end) ~= '}' do
          val_end = val_end + 1
        end
        local val_str = str:sub(pos, val_end - 1):match("^%s*(.-)%s*$")
        if val_str == "true" then
          obj[key] = true
        elseif val_str == "false" then
          obj[key] = false
        elseif tonumber(val_str) then
          obj[key] = tonumber(val_str)
        end
        pos = val_end
      end
      
      -- Skip comma
      while pos <= #str and (str:sub(pos, pos) == ',' or str:sub(pos, pos):match("%s")) do
        pos = pos + 1
      end
    end
    return obj
  elseif str:sub(1, 1) == "[" then
    local arr = {}
    str = str:sub(2, -2) -- remove []
    
    -- Handle empty array
    if str:match("^%s*$") then
      return arr
    end
    
    -- Parse array items, handling strings with commas, nested objects, and nested arrays
    local pos = 1
    while pos <= #str do
      -- Skip whitespace
      while pos <= #str and str:sub(pos, pos):match("%s") do pos = pos + 1 end
      if pos > #str then break end
      
      if str:sub(pos, pos) == '"' then
        -- String item
        local item_start = pos + 1
        local item_end = item_start
        while item_end <= #str do
          if str:sub(item_end, item_end) == '"' and str:sub(item_end - 1, item_end - 1) ~= '\\' then
            break
          end
          item_end = item_end + 1
        end
        if item_end <= #str then
          local item_str = str:sub(item_start, item_end - 1)
          item_str = item_str:gsub('\\"', '"'):gsub('\\\\', '\\')
          table.insert(arr, item_str)
        end
        pos = item_end + 1
      elseif str:sub(pos, pos) == '{' then
        -- Nested object - find matching brace
        local depth = 1
        local obj_start = pos
        pos = pos + 1
        while pos <= #str and depth > 0 do
          if str:sub(pos, pos) == '{' then depth = depth + 1
          elseif str:sub(pos, pos) == '}' then depth = depth - 1 end
          pos = pos + 1
        end
        local obj_str = str:sub(obj_start, pos - 1)
        table.insert(arr, json_decode(obj_str))
      elseif str:sub(pos, pos) == '[' then
        -- Nested array - find matching bracket
        local depth = 1
        local arr_start = pos
        pos = pos + 1
        while pos <= #str and depth > 0 do
          if str:sub(pos, pos) == '[' then depth = depth + 1
          elseif str:sub(pos, pos) == ']' then depth = depth - 1 end
          pos = pos + 1
        end
        local arr_str = str:sub(arr_start, pos - 1)
        table.insert(arr, json_decode(arr_str))
      elseif tonumber(str:sub(pos, pos)) or str:sub(pos, pos) == '-' then
        -- Number item
        local item_end = pos
        while item_end <= #str and str:sub(item_end, item_end) ~= ',' and str:sub(item_end, item_end) ~= ']' do
          item_end = item_end + 1
        end
        local num_str = str:sub(pos, item_end - 1):match("^%s*(.-)%s*$")
        local num = tonumber(num_str)
        if num then 
          table.insert(arr, num) 
        end
        pos = item_end
      elseif str:sub(pos, pos) == 't' or str:sub(pos, pos) == 'f' then
        -- Boolean or null
        local item_end = pos
        while item_end <= #str and str:sub(item_end, item_end) ~= ',' and str:sub(item_end, item_end) ~= ']' do
          item_end = item_end + 1
        end
        local val_str = str:sub(pos, item_end - 1):match("^%s*(.-)%s*$")
        if val_str == "true" then
          table.insert(arr, true)
        elseif val_str == "false" then
          table.insert(arr, false)
        elseif val_str == "null" then
          table.insert(arr, nil)
        end
        pos = item_end
      else
        -- Skip unknown character (shouldn't happen in valid JSON)
        log("Warning: Unexpected character in array at position " .. pos .. ": " .. str:sub(pos, pos))
        pos = pos + 1
      end
      
      -- Skip comma
      while pos <= #str and (str:sub(pos, pos) == ',' or str:sub(pos, pos):match("%s")) do
        pos = pos + 1
      end
    end
    return arr
  end
  return nil
end


-- --- Preview helpers (track only) ----------------------------------------------
local function ensure_preview_track()
  if preview_track then
    if (r.ValidatePtr2 and r.ValidatePtr2(0, preview_track, "MediaTrack*")) or 
       (r.ValidatePtr and r.ValidatePtr(preview_track, "MediaTrack*")) then
      return preview_track
    end
  end

  -- Try to find existing preview track
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    local _, name = r.GetTrackName(tr, "")
    if name == PREVIEW_TRACK_NAME then
      preview_track = tr
      break
    end
  end

  -- Create if missing
  if not preview_track then
    r.InsertTrackAtIndex(r.CountTracks(0), true)
    preview_track = r.GetTrack(0, r.CountTracks(0) - 1)
    r.GetSetMediaTrackInfo_String(preview_track, "P_NAME", PREVIEW_TRACK_NAME, true)
    -- Hide from TCP/mixer to avoid clutter
    r.SetMediaTrackInfo_Value(preview_track, "B_SHOWINTCP", 0)
    r.SetMediaTrackInfo_Value(preview_track, "B_SHOWINMIXER", 0)
    -- Keep normal routing (main send on)
    r.SetMediaTrackInfo_Value(preview_track, "B_MAINSEND", 1)
  end

  return preview_track
end


-- --- Persistence -------------------------------------------------------------
local function load_config()
  local file = io.open(CONFIG_PATH, "r")
  if file then
    local content = file:read("*all")
    file:close()
    if content and content ~= "" then
      local success, cfg = pcall(json_decode, content)
      if success and cfg and type(cfg) == "table" then
        -- Ensure folders is an array of strings (normalized)
        if cfg.folders and type(cfg.folders) == "table" then
          state.folders = {}
          for i, folder in ipairs(cfg.folders) do
            if type(folder) == "string" then
              table.insert(state.folders, normalize_path(folder))
            end
          end
        else
          state.folders = {}
        end
        state.map_seed = cfg.map_seed or 1337
        -- Zoom and pan are not saved - always start at defaults
        -- Load dot customization settings
        state.dot_radius = cfg.dot_radius or 2.0
        state.dot_outline_size = cfg.dot_outline_size or 4.0
        state.dot_outline_thickness = cfg.dot_outline_thickness or 3.0
        -- Load colors (RGB format)
        if cfg.dot_color then
          state.dot_color = cfg.dot_color
        elseif cfg.dot_color_r then
          -- Convert old RGB component format to RGB color value
          state.dot_color = build_rgb(cfg.dot_color_r or 68, cfg.dot_color_g or 170, cfg.dot_color_b or 85)
        else
          state.dot_color = 0x44AA55
        end
        if cfg.dot_outline_color then
          state.dot_outline_color = cfg.dot_outline_color
        elseif cfg.dot_outline_color_r then
          state.dot_outline_color = build_rgb(cfg.dot_outline_color_r or 255, cfg.dot_outline_color_g or 0, cfg.dot_outline_color_b or 255)
        else
          state.dot_outline_color = 0xFF00FF
        end
        if cfg.dot_hover_color then
          state.dot_hover_color = cfg.dot_hover_color
        elseif cfg.dot_hover_color_r then
          state.dot_hover_color = build_rgb(cfg.dot_hover_color_r or 200, cfg.dot_hover_color_g or 76, cfg.dot_hover_color_b or 77)
        else
          state.dot_hover_color = 0xC84D
        end
        state.dot_detection_multiplier = cfg.dot_detection_multiplier or 16.0
        -- Load tag colors
        if cfg.tag_colors and type(cfg.tag_colors) == "table" then
          for tag, color in pairs(cfg.tag_colors) do
            if type(color) == "number" then
              state.tag_colors[tag] = color
            end
          end
        end
        log("Loaded config: " .. #state.folders .. " folder(s)")
        if #state.folders > 0 then
          for i, folder in ipairs(state.folders) do
            log("  Folder " .. i .. ": " .. folder)
          end
        end
      else
        log("Config file exists but couldn't parse it: " .. tostring(cfg))
      end
    end
  else
    log("No config file found, starting fresh")
  end
end


local function serialize_table(t, indent)
  indent = indent or ""
  local result = "{\n"
  for k, v in pairs(t) do
    result = result .. indent .. "  "
    if type(k) == "string" then
      result = result .. '["' .. k .. '"]'
    else
      result = result .. '[' .. tostring(k) .. ']'
    end
    result = result .. " = "
    if type(v) == "table" then
      result = result .. serialize_table(v, indent .. "  ")
    elseif type(v) == "string" then
      result = result .. '"' .. v .. '"'
    else
      result = result .. tostring(v)
    end
    result = result .. ",\n"
  end
  result = result .. indent .. "}"
  return result
end

local function save_config()
  local cfg = {
    folders = state.folders,
    map_seed = state.map_seed,
    -- Save dot customization settings
    dot_radius = state.dot_radius,
    dot_outline_size = state.dot_outline_size,
    dot_outline_thickness = state.dot_outline_thickness,
    dot_color = state.dot_color,
    dot_outline_color = state.dot_outline_color,
    dot_hover_color = state.dot_hover_color,
    dot_detection_multiplier = state.dot_detection_multiplier,
    tag_colors = state.tag_colors,
  }
  local file = io.open(CONFIG_PATH, "w")
  if file then
    local json_str = json_encode(cfg)
    file:write(json_str)
    file:close()
    log("Saved config with " .. #state.folders .. " folder(s)")
  else
    log("Failed to save config file")
  end
end


-- Run external Python analyzer to compute metadata (e.g., frequency/RMS)
-- Expected JSON output: { dominant_freq: number, rms_energy: number }
local function run_external_analyzer(path)
  local analyzer_start = r.time_precise()
  
  -- Validate analyzer script exists
  local t0 = r.time_precise()
  local fh = io.open(EXTERNAL_ANALYZER, "r")
  if not fh then
    return nil, "analyzer script missing"
  end
  fh:close()
  local check_time = (r.time_precise() - t0) * 1000

  local t1 = r.time_precise()
  local cmd = table.concat({
    shell_escape(PYTHON_BIN),
    shell_escape(EXTERNAL_ANALYZER),
    shell_escape(path)
  }, " ")

  -- Try to capture both stdout and stderr
  -- On macOS, we can redirect stderr to stdout with 2>&1
  local cmd_with_stderr = cmd .. " 2>&1"
  local pipe = io.popen(cmd_with_stderr, "r")
  if not pipe then
    return nil, "failed to start analyzer"
  end
  local spawn_time = (r.time_precise() - t1) * 1000

  local t2 = r.time_precise()
  local output = pipe:read("*all")
  local ok, why, code = pipe:close()
  local exec_time = (r.time_precise() - t2) * 1000
  
  if not ok then
    return nil, "analyzer process failed"
  end

  if not output or output == "" then
    return nil, "empty analyzer output"
  end

  local t3 = r.time_precise()
  local success, data = pcall(json_decode, output)
  local parse_time = (r.time_precise() - t3) * 1000
  
  local total_analyzer_time = (r.time_precise() - analyzer_start) * 1000
  
  if success and type(data) == "table" then
    -- Remove debug key before returning (don't store it in sample data)
    data._debug = nil
    
    -- Analyzer timing removed - use scan logs instead
    
    return data, nil
  end

  return nil, "invalid analyzer JSON"
end


-- Start an analyzer process for a file (non-blocking)
-- Returns true if process started successfully, false otherwise
local function start_analyzer_process(path)
  -- Check if analyzer script exists
  local fh = io.open(EXTERNAL_ANALYZER, "r")
  if not fh then
    return false
  end
  fh:close()
  
  -- Build command
  local cmd = table.concat({
    shell_escape(PYTHON_BIN),
    shell_escape(EXTERNAL_ANALYZER),
    shell_escape(path)
  }, " ")
  
  local cmd_with_stderr = cmd .. " 2>&1"
  local pipe = io.popen(cmd_with_stderr, "r")
  
  if pipe then
    table.insert(state.active_processes, {
      path = path,
      pipe = pipe,
      start_time = r.time_precise()
    })
    return true
  end
  
  return false
end


-- Check for completed analyzer processes and update analyzer_results
-- Only checks one process per call to avoid blocking (called each frame)
-- Returns true if a process was checked/completed, false if no processes to check
local function check_analyzer_processes()
  if #state.active_processes == 0 then
    return false
  end
  
  -- Check only the first process (oldest) to minimize blocking
  local proc = state.active_processes[1]
  local pipe = proc.pipe
  
  -- Check timeout first (non-blocking check)
  local elapsed = r.time_precise() - proc.start_time
  if elapsed > 30.0 then
    -- Timeout - close pipe and mark as failed
    local close_ok, close_err = pcall(function() return pipe:close() end)
    if not close_ok then
      add_scan_log(string.format("Warning: failed to close timed-out pipe for %s: %s", proc.path:match("([^/]+)$") or proc.path, tostring(close_err)))
    end
    state.analyzer_results[proc.path] = {data = nil, err = "analyzer timeout"}
    add_scan_log(string.format("Analyzer timeout on %s (continuing)", proc.path:match("([^/]+)$") or proc.path))
    table.remove(state.active_processes, 1)
    return true
  end
  
  -- Try to read from pipe (this may block briefly if process is still running)
  -- We only check one per frame to keep GUI responsive
  -- Use non-blocking check: try to read a line, but don't wait if process is still running
  local line = pipe:read("*line")
  
  if line then
    -- Process has output, read remaining
    local output = line
    local rest = pipe:read("*all")
    if rest then
      output = output .. "\n" .. rest
    end

    -- Always close the pipe after reading
    local ok, why, code = pcall(function() return pipe:close() end)
    if not ok then
      -- If close fails, log it but continue
      add_scan_log(string.format("Warning: failed to close pipe for %s: %s", proc.path:match("([^/]+)$") or proc.path, tostring(why)))
    end
    
    add_scan_log(string.format("Process closed: ok=%s, output_len=%d", tostring(ok), #output))

    if output and output ~= "" then
      local success, data = pcall(json_decode, output)
      if success and type(data) == "table" then
        data._debug = nil
        state.analyzer_results[proc.path] = {data = data, err = nil}

        -- Log success
        add_scan_log(string.format("Analyzer completed: %s (freq=%.1f, rms=%.3f)", proc.path:match("([^/]+)$") or proc.path, data.dominant_freq or 0, data.rms_energy or 0))
      else
        state.analyzer_results[proc.path] = {data = nil, err = "invalid analyzer JSON"}
        add_scan_log(string.format("Analyzer error on %s: invalid JSON: %s", proc.path:match("([^/]+)$") or proc.path, tostring(data)))
      end
    else
      state.analyzer_results[proc.path] = {data = nil, err = "analyzer process failed"}
      add_scan_log(string.format("Analyzer error on %s: process failed (ok=%s, why=%s, code=%s)", proc.path:match("([^/]+)$") or proc.path, tostring(ok), tostring(why), tostring(code)))
    end
  
    -- Remove from active processes
    table.remove(state.active_processes, 1)
    return true
  end
  
  -- Process still running, no output yet - pipe remains open (will be checked next frame)
  -- This is OK as long as we limit concurrent processes and handle timeouts
  return false
end


-- Manage the analyzer process pool: start new processes when slots available
local function process_analyzer_queue()
  if state.external_disabled then
    add_scan_log("Analyzer disabled, skipping queue processing")
    return
  end

  -- Check for completed processes (check one at a time to avoid blocking)
  local had_completed = check_analyzer_processes()
  if had_completed then
    add_scan_log("Completed analyzer process")
  end

  -- Start new processes if we have slots available and files in queue
  local started = 0
  while #state.active_processes < state.max_concurrent_analyzers and #state.analyzer_queue > 0 do
    local path = table.remove(state.analyzer_queue, 1)
    if start_analyzer_process(path) then
      started = started + 1
      add_scan_log(string.format("Started analyzer process for: %s", path:match("([^/]+)$") or path))
    else
      -- Failed to start - check if it's a critical error
      local fh = io.open(EXTERNAL_ANALYZER, "r")
      if not fh then
        state.external_disabled = true
        state.analyzer_warned = true
        add_scan_log("Analyzer critical error; disabled further runs: analyzer script missing")
        break
      end
      fh:close()

      -- Non-critical error, just log and continue
      state.analyzer_results[path] = {data = nil, err = "failed to start analyzer"}
      add_scan_log(string.format("Analyzer error on %s: failed to start (continuing)", path:match("([^/]+)$") or path))
    end
  end

  if started > 0 then
    add_scan_log(string.format("Started %d new analyzer processes", started))
  end
end


local function folders_match(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  if #a ~= #b then return false end
  for i = 1, #a do
    -- Normalize paths before comparison
    local norm_a = normalize_path(a[i] or "")
    local norm_b = normalize_path(b[i] or "")
    if norm_a ~= norm_b then return false end
  end
  return true
end


-- Layout samples on the 2D map based on their audio characteristics
local function layout_samples()
  if #state.samples == 0 then return end

  -- Use Lua calculation (Python analyzer doesn't support layout calculations)
  -- Coordinates are cached after calculation, so this only runs when needed

  -- Calculate positioning scores for all samples
  local len_scores = {}
  local freq_scores = {}
  local rms_scores = {}
  local size_scores = {}

  -- Lua doesn't have log10, so use log(x) / log(10)
  local log10 = math.log(10)
  for _, s in ipairs(state.samples) do
    table.insert(len_scores, math.log(math.max(s.duration, 0.01)) / log10)
    -- Use dominant frequency (log scale for better distribution)
    -- Clamp frequency to valid range (20Hz to 20kHz)
    local freq = math.max(20.0, math.min(20000.0, s.dominant_freq or 440.0))
    table.insert(freq_scores, math.log(freq) / log10)
    -- Store RMS energy (use log scale for better distribution)
    local rms = math.max(1e-6, s.rms_energy or 0.0)
    table.insert(rms_scores, math.log(rms) / log10)
    -- Store file size (use log scale for better distribution)
    local size = math.max(1, s.file_size or 1)
    table.insert(size_scores, math.log(size) / log10)
  end

  -- Check if frequencies are too similar (all defaulting to 440Hz)
  local freq_min = freq_scores[1]
  local freq_max = freq_scores[1]
  for _, v in ipairs(freq_scores) do
    freq_min = math.min(freq_min, v)
    freq_max = math.max(freq_max, v)
  end
  local freq_range = freq_max - freq_min

  -- Check if RMS is all zeros
  local rms_min = rms_scores[1]
  local rms_max = rms_scores[1]
  for _, v in ipairs(rms_scores) do
    rms_min = math.min(rms_min, v)
    rms_max = math.max(rms_max, v)
  end
  local rms_range = rms_max - rms_min
  local rms_all_zero = rms_range < 1e-6  -- RMS is essentially zero

  -- Decide what to use for Y axis
  local use_rms_for_y = false
  local use_size_for_y = false

  if freq_range < 0.01 then
    -- Frequency range too small
    if rms_all_zero then
      -- RMS is also zero, use file size
      use_size_for_y = true
    else
      use_rms_for_y = true
    end
  end

  math.randomseed(state.map_seed)

  -- Ensure we use the full range: find min/max for both axes
  local len_min, len_max = len_scores[1], len_scores[1]
  local y_min, y_max

  for _, v in ipairs(len_scores) do
    len_min = math.min(len_min, v)
    len_max = math.max(len_max, v)
  end

  -- Use RMS, file size, or frequency for Y axis
  if use_size_for_y then
    y_min, y_max = size_scores[1], size_scores[1]
    for _, v in ipairs(size_scores) do
      y_min = math.min(y_min, v)
      y_max = math.max(y_max, v)
    end
  elseif use_rms_for_y then
    y_min, y_max = rms_scores[1], rms_scores[1]
    for _, v in ipairs(rms_scores) do
      y_min = math.min(y_min, v)
      y_max = math.max(y_max, v)
    end
  else
    y_min, y_max = freq_scores[1], freq_scores[1]
    for _, v in ipairs(freq_scores) do
      y_min = math.min(y_min, v)
      y_max = math.max(y_max, v)
    end
  end

  -- Normalize function that ensures full range usage with padding for better spread
  local function normalize(value, min_val, max_val, padding)
    padding = padding or 0.1  -- 10% padding on each side
    if max_val - min_val < 1e-9 then
      return 0.5  -- All same value, center it
    end
    -- Normalize to 0-1 range
    local normalized = (value - min_val) / (max_val - min_val)
    -- Scale to use more of the available space (with padding)
    -- Maps 0-1 to padding to (1-padding)
    return padding + normalized * (1.0 - 2.0 * padding)
  end

  -- Position each sample
  for i, s in ipairs(state.samples) do
    -- Preserve existing tags before modifying sample (make a copy, not a reference)
    local preserved_tags = nil
    if s.tags and type(s.tags) == "table" then
      preserved_tags = {}
      for _, tag in ipairs(s.tags) do
        table.insert(preserved_tags, tag)
      end
    end

    -- X-axis: duration (left = short, right = long)
    local x = normalize(len_scores[i], len_min, len_max, 0.05)  -- 5% padding
    -- Y-axis: dominant frequency, RMS energy, or file size (top = high, bottom = low)
    -- Use full range (0.0 padding) to spread from top to bottom
    local y_value
    if use_size_for_y then
      y_value = size_scores[i]
    elseif use_rms_for_y then
      y_value = rms_scores[i]
    else
      y_value = freq_scores[i]
    end
    local y_normalized = normalize(y_value, y_min, y_max, 0.0)  -- No padding - use full range
    local y = 1.0 - y_normalized  -- Invert so highest value is at top
    -- Add jitter to avoid clustering
    local jx = (math.random() - 0.5) * 0.04
    local jy = (math.random() - 0.5) * 0.04
    s.x = math.max(0.0, math.min(1.0, x + jx))
    s.y = math.max(0.0, math.min(1.0, y + jy))
    -- Use customizable dot color, with slight variation for mono samples
    local base_color = state.dot_color or 0x44AA55FF  -- RRGGBBAA format
    local base_r, base_g, base_b = extract_rgb_rrgbbaa(base_color)
    local base_alpha = math.floor(base_color % 256)
    if s.channels == 1 then
      -- Mono: use lighter version (add 50% to each component, clamped to 255)
      local mono_r = math.min(255, math.floor(base_r * 1.5))
      local mono_g = math.min(255, math.floor(base_g * 1.5))
      local mono_b = math.min(255, math.floor(base_b * 1.5))
      s.color = build_color_rrgbbaa(mono_r, mono_g, mono_b, base_alpha)
    else
      -- Stereo: use base customizable color directly
      s.color = base_color
    end
    -- Use customizable hover color directly (RRGGBBAA format)
    s.hot_color = state.dot_hover_color or 0xFFC84DFF

    -- Restore preserved tags
    if preserved_tags then
      s.tags = preserved_tags
    end
  end

  -- Layout debug logs removed - happens during scanning
end


local function load_samples()
  log("Attempting to load cached samples from: " .. DATA_PATH)
  local file = io.open(DATA_PATH, "r")
  if not file then
    log("Cache file not found or cannot be opened")
    return false
  end
  local content = file:read("*all")
  file:close()
  if not content or content == "" then
    log("Cache file is empty")
    return false
  end
  log("Cache file size: " .. #content .. " bytes")
  local ok, data = pcall(json_decode, content)
  if not ok then
    log("Failed to decode JSON: " .. tostring(data))
    return false
  end
  if type(data) ~= "table" then
    log("Decoded data is not a table: " .. type(data))
    return false
  end
  log("Decoded JSON successfully")
  if data.folders then
    log("Cache has " .. #data.folders .. " folder(s)")
    if not folders_match(state.folders, data.folders) then
      log("Cached samples ignored: folder list changed")
      log("  Current folders: " .. #state.folders)
      log("  Cached folders: " .. #data.folders)
      return false
    end
    log("Folder list matches cache")
  else
    log("Cache has no folders field")
  end
  if data.samples and type(data.samples) == "table" then
    log("Cache has samples table with " .. #data.samples .. " entries")
    local cleaned = {}
    -- Use ipairs to properly iterate over array
    for i, s in ipairs(data.samples) do
      if type(s) == "table" then
        -- Verify sample has required fields
        if s.path and s.name then
          -- Normalize path immediately (critical for analyzer result merging)
          s.path = normalize_path(s.path)
          -- Ensure coordinates exist (set defaults if missing)
          if not s.x then s.x = 0.5 end
          if not s.y then s.y = 0.5 end
          -- Backfill tags for older cache entries
          if not s.tags or type(s.tags) ~= "table" then
            s.tags = infer_tags_from_path(s.path, s.folder or "")
          end
          -- Ensure sample_type is added to tags if it exists
          if s.sample_type and (s.sample_type == "Drum" or s.sample_type == "Swell") then
            local has_tag = false
            for _, tag in ipairs(s.tags) do
              if tag == s.sample_type then
                has_tag = true
                break
              end
            end
            if not has_tag then
              table.insert(s.tags, s.sample_type)
            end
          end
          -- Detect and add Loop or One shot tag if detected
          local sample_type_detected = detect_loop_or_oneshot(s.path, s.folder or "")
          if sample_type_detected then
            local has_tag = false
            for _, tag in ipairs(s.tags) do
              if tag == sample_type_detected then
                has_tag = true
                break
              end
            end
            if not has_tag then
              table.insert(s.tags, sample_type_detected)
            end
          end
          table.insert(cleaned, s)
        else
          log("Warning: sample " .. i .. " missing path or name")
        end
      else
        log("Warning: sample " .. i .. " is not a table: " .. type(s))
      end
    end
    state.samples = cleaned

    -- Re-hydrate runtime-only fields (hot_color, samplerate, file_size) that are not persisted
    local function hydrate_sample_runtime(sample)
      if not sample then return end
      if sample.hot_color == nil then
        sample.hot_color = state.dot_hover_color or 0xFFC84DFF
      end
      if sample.samplerate == nil and sample.sample_rate ~= nil then
        sample.samplerate = sample.sample_rate
      end
      if sample.samplerate == nil then
        sample.samplerate = 44100
      end
      if sample.file_size == nil then
        local dur = sample.duration or 0
        local bps = sample.bps or 0
        sample.file_size = math.max(0, math.floor(bps * dur + 0.5))
      end
    end

    for _, s in ipairs(state.samples) do
      hydrate_sample_runtime(s)
    end
    
    -- Restore scan state if available (for resuming interrupted scans)
    if data.scan_queue and type(data.scan_queue) == "table" and #data.scan_queue > 0 then
      state.scan_queue = data.scan_queue
      state.scan_total = data.scan_total or (#state.samples + #state.scan_queue)
      state.scan_started = data.scan_started or r.time_precise()
      log(string.format("Resuming interrupted scan: %d files remaining", #state.scan_queue))
    end

    -- Restore analyzer state: pending queue, results, and pending flag
    if data.analyzer_queue and type(data.analyzer_queue) == "table" and #data.analyzer_queue > 0 then
      state.analyzer_queue = data.analyzer_queue
    else
      state.analyzer_queue = {}
    end
    if data.analyzer_results and type(data.analyzer_results) == "table" then
      state.analyzer_results = data.analyzer_results
    else
      state.analyzer_results = {}
    end
    -- If analyzers were in flight when saved, re-queue unresolved samples
    if data.analyzer_pending then
      for _, sample in ipairs(state.samples) do
        if not sample.dominant_freq then
          table.insert(state.analyzer_queue, sample.path)
        end
      end
    end
    
    if #state.samples == 0 then
      return false
    end

    -- Check if we need to re-layout samples
    local needs_layout = false

    -- Check if any samples are missing coordinates
    for _, sample in ipairs(state.samples) do
      if not sample.x or not sample.y or
         sample.x < 0 or sample.x > 1 or
         sample.y < 0 or sample.y > 1 then
        needs_layout = true
        break
      end
    end

    -- Re-layout only if coordinates are missing or analyzer results were merged
    if needs_layout then
      layout_samples()
      log("Re-layouting samples (missing/invalid coordinates)")
    else
      log("Using cached coordinates (no layout needed)")
    end

    rebuild_tag_index()
    return true
  else
    log("Cache has no samples field or samples is not a table")
    if data.samples then
      log("  samples type: " .. type(data.samples))
    end
  end
  return false
end


local function save_samples()
  local save_start = r.time_precise()
  
  -- Normalize folder paths before saving
  local t0 = r.time_precise()
  local normalized_folders = {}
  for _, folder in ipairs(state.folders) do
    table.insert(normalized_folders, normalize_path(folder))
  end
  -- Strip runtime-only fields before writing cache
  local function sanitize_sample(sample)
    local out = {}
    for k, v in pairs(sample) do
      if k ~= "samplerate" and k ~= "sample_rate" and k ~= "file_size" and k ~= "hot_color" then
        out[k] = v
      end
    end
    return out
  end

  local sanitized_samples = {}
  for _, s in ipairs(state.samples) do
    sanitized_samples[#sanitized_samples + 1] = sanitize_sample(s)
  end

  local payload = {
    folders = normalized_folders,
    map_seed = state.map_seed,
    samples = sanitized_samples,
    -- Save scan state for resuming
    scan_queue = state.scan_queue,
    scan_total = state.scan_total,
    scan_started = state.scan_started,
    analyzer_queue = state.analyzer_queue,
    analyzer_pending = state.active_processes and #state.active_processes > 0,
    analyzer_results = state.analyzer_results,
  }
  local prep_time = (r.time_precise() - t0) * 1000
  
  -- Pretty-print samples with a newline between each entry for readability
  local function encode_samples_pretty(list)
    local out = {"["}
    for i, s in ipairs(list) do
      out[#out + 1] = json_encode(s)
      if i < #list then
        out[#out + 1] = ",\n"
      end
    end
    out[#out + 1] = "]"
    return table.concat(out)
  end

  local t1 = r.time_precise()
  local samples_str = encode_samples_pretty(payload.samples)
  local json_str = table.concat({
    "{",
    "\"folders\":", json_encode(payload.folders), ",",
    "\"map_seed\":", json_encode(payload.map_seed), ",",
    "\"samples\":", samples_str, ",",
    "\"scan_queue\":", json_encode(payload.scan_queue), ",",
    "\"scan_total\":", json_encode(payload.scan_total), ",",
    "\"scan_started\":", json_encode(payload.scan_started), ",",
    "\"analyzer_queue\":", json_encode(payload.analyzer_queue), ",",
    "\"analyzer_pending\":", json_encode(payload.analyzer_pending), ",",
    "\"analyzer_results\":", json_encode(payload.analyzer_results),
    "}"
  })
  local encode_time = (r.time_precise() - t1) * 1000
  
  local t2 = r.time_precise()
  local file = io.open(DATA_PATH, "w")
  if not file then
    return
  end
  file:write(json_str)
  file:close()
  local write_time = (r.time_precise() - t2) * 1000
  
  local total_save_time = (r.time_precise() - save_start) * 1000
  
  -- Update last save time
  state.last_save_time = r.time_precise()
  
  -- Save timing removed - happens during scanning
end


local function clear_sample_cache()
  os.remove(DATA_PATH)
end

local function filter_samples_by_folders()
  if #state.folders == 0 then
    -- If no folders, clear all samples
    state.samples = {}
    state.active_tags = {}
    state.tag_list = {}
    state.tag_counts = {}
    return
  end

  local filtered_samples = {}
  local removed_count = 0

  for _, sample in ipairs(state.samples) do
    if sample.path then
      local normalized_sample_path = normalize_path(sample.path)
      local keep_sample = false

      -- Check if sample belongs to any of the current folders
      for _, folder in ipairs(state.folders) do
        local normalized_folder = normalize_path(folder)
        if normalized_sample_path:sub(1, #normalized_folder) == normalized_folder then
          keep_sample = true
          break
        end
      end

      if keep_sample then
        table.insert(filtered_samples, sample)
      else
        removed_count = removed_count + 1
      end
    else
      -- Keep samples without path (shouldn't happen but safety check)
      table.insert(filtered_samples, sample)
    end
  end

  state.samples = filtered_samples

  -- Rebuild tag data since samples changed
  state.active_tags = {}
  state.tag_list = {}
  state.tag_counts = {}

  if removed_count > 0 then
    log("Removed " .. removed_count .. " samples from removed folder(s)")
  end
end


-- --- Scanning and analysis ---------------------------------------------------
local function enqueue_scan()
  state.debug_count = 0  -- Reset debug counter for new scan
  state.external_disabled = false
  state.analyzer_warned = false
  
  -- Build set of already-scanned paths for quick lookup (normalize paths to ensure matching)
  local scanned_set = {}
  for _, sample in ipairs(state.samples) do
    if sample.path then
      local normalized_path = normalize_path(sample.path)
      scanned_set[normalized_path] = true
      -- Also store original path mapping in case it's needed
      if normalized_path ~= sample.path then
        scanned_set[sample.path] = true
      end
    end
  end
  
  local paths = {}
  local skipped_count = 0
  
  for _, folder in ipairs(state.folders) do
    -- Normalize folder path
    folder = normalize_path(folder)
    local files_found = 0
    
    local function scan_dir(dir)
      -- Ensure dir path is normalized
      dir = normalize_path(dir)
      
      -- Scan all files in current directory
      local i = 0
      local file = r.EnumerateFiles(dir, i)
      while file do
        local ext = file:match("%.(.+)$")
        if ext then
          ext = "." .. ext:lower()
          if AUDIO_EXTS[ext] then
            -- Use forward slash for macOS
            local full_path = dir .. "/" .. file
            -- Normalize path before checking against scanned_set
            local normalized_full_path = normalize_path(full_path)
            -- Only add if not already scanned
            if not scanned_set[normalized_full_path] and not scanned_set[full_path] then
              table.insert(paths, normalized_full_path)
              files_found = files_found + 1
            else
              skipped_count = skipped_count + 1
            end
          end
        end
        i = i + 1
        file = r.EnumerateFiles(dir, i)
      end
      
      -- Recursively scan all subdirectories
      i = 0
      local subdir = r.EnumerateSubdirectories(dir, i)
      while subdir do
        -- Use forward slash for macOS
        scan_dir(dir .. "/" .. subdir)
        i = i + 1
        subdir = r.EnumerateSubdirectories(dir, i)
      end
    end
    
    -- Try to scan the folder
    local success, err = pcall(scan_dir, folder)
    if not success then
      -- Error scanning folder - silent during scan, errors visible in scan logs
    end
  end
  
  -- If we have existing samples, keep them; otherwise start fresh
  if #state.samples == 0 then
    state.samples = {}
  end
  
  state.scan_queue = paths
  state.scan_total = #paths + skipped_count  -- Total includes already-scanned
  state.scan_started = r.time_precise()
  state.last_save_time = r.time_precise()  -- Initialize save time for time-based saving
  state.active_tags = {}
  state.tag_list = {}
  state.tag_counts = {}
  
  -- Clear analyzer queues for new scan
  state.analyzer_queue = {}
  state.analyzer_results = {}
  state.active_processes = {}
  
  -- Scan start/resume messages removed - use scan logs instead
end


local function analyze_file(path)
  local file_start_time = r.time_precise()
  local timings = {}
  
  -- PCM_Source creation
  local t0 = r.time_precise()
  local src = r.PCM_Source_CreateFromFile(path)
  if not src then
    return nil
  end
  timings.pcm_create = (r.time_precise() - t0) * 1000  -- Convert to ms
  
  -- Get metadata from PCM_Source
  local t1 = r.time_precise()
  local length_ret = {r.GetMediaSourceLength(src)}
  local duration = pick_number(length_ret, 0.0)
  
  local sr_ret = {r.GetMediaSourceSampleRate(src)}
  local sr = pick_number(sr_ret, 44100.0)
  
  local ch_ret = {r.GetMediaSourceNumChannels(src)}
  local ch = math.floor(pick_number(ch_ret, 2))
  timings.pcm_metadata = (r.time_precise() - t1) * 1000

  -- Get file size from PCM_Source if possible (faster than opening file again)
  local t2 = r.time_precise()
  local size = 0
  local size_ret = {r.GetMediaSourceLength(src)}
  local length_in_samples = pick_number(size_ret, 0.0)
  if length_in_samples > 0 and sr > 0 then
    -- Estimate file size: samples * channels * bytes_per_sample
    -- Use average bitrate estimation
    local estimated_bytes = length_in_samples * ch * 2  -- Assume 16-bit (2 bytes)
    -- Try to get actual file size, but fall back to estimate
    local file = io.open(path, "rb")
    if file then
      file:seek("end")
      size = file:seek()
      file:close()
    else
      size = estimated_bytes
    end
  else
    -- Fallback: open file to get size
    local file = io.open(path, "rb")
    if file then
      file:seek("end")
      size = file:seek()
      file:close()
    end
  end
  timings.file_size = (r.time_precise() - t2) * 1000
  
  -- Queue analyzer request instead of blocking (analyzer data will be merged later)
  -- Normalize path before queuing
  local normalized_path = normalize_path(path)
  if not state.external_disabled then
    -- Add to analyzer queue for parallel processing
    table.insert(state.analyzer_queue, normalized_path)
    add_scan_log(string.format("Queued analyzer for: %s", path:match("([^/]+)$") or path))
  else
    add_scan_log(string.format("Analyzer disabled, skipping: %s", path:match("([^/]+)$") or path))
  end
  
  local t4 = r.time_precise()
  r.PCM_Source_Destroy(src)
  timings.pcm_destroy = (r.time_precise() - t4) * 1000
  
  local avg_bps = size / math.max(duration, 0.01)
  -- Normalize path to use forward slashes
  path = normalize_path(path)
  
  -- Get tags from path first
  local t5 = r.time_precise()
  local tags = infer_tags_from_path(path, path:match("(.+)/[^/]+$") or "")
  timings.tags = (r.time_precise() - t5) * 1000
  
  -- File timing logs removed - happens during scanning
  
  -- Note: Analyzer tags (Drum/Swell) will be added later when analyzer data is merged
  
  -- Detect Loop or One shot based on filename/path patterns
  local sample_type_detected = detect_loop_or_oneshot(path, path:match("(.+)/[^/]+$") or "")
  if sample_type_detected then
    -- Check if tag already exists (avoid duplicates)
    local has_tag = false
    for _, tag in ipairs(tags) do
      if tag == sample_type_detected then
        has_tag = true
        break
      end
    end
    if not has_tag then
      table.insert(tags, sample_type_detected)
    end
  end
  
  -- Return sample without analyzer data initially (will be merged later)
  return {
    path = normalized_path,
    name = normalized_path:match("([^/]+)$"),  -- macOS uses forward slashes only
    folder = normalized_path:match("(.+)/[^/]+$") or "",
    duration = duration,
    samplerate = sr,
    channels = ch,
    bps = avg_bps,
    file_size = size,  -- Store file size for Y axis fallback
    dominant_freq = nil,  -- Will be set when analyzer completes
    rms_energy = nil,     -- Will be set when analyzer completes
    sample_type = nil,    -- Will be set when analyzer completes
    snap_offset = nil,    -- Will be set when analyzer completes
    tags = tags
  }
end


local function process_scan_slice(max_ms)
  max_ms = max_ms or 15.0

  -- Manage analyzer process pool (start new processes, check for completed ones)
  process_analyzer_queue()

  -- Merge completed analyzer results into samples
  local merged_count = 0
  add_scan_log(string.format("Merging %d analyzer results", #state.analyzer_results))
  for path, result in pairs(state.analyzer_results) do
    -- Find matching sample by path
    local found_sample = false
    for _, sample in ipairs(state.samples) do
      if sample.path == path then
        -- Merge analyzer data into sample
        if result.data then
          -- Debug: log successful merge
          add_scan_log(string.format("Merged analyzer data for %s: freq=%.1f, rms=%.3f", path:match("([^/]+)$") or path, result.data.dominant_freq or 0, result.data.rms_energy or 0))
          sample.dominant_freq = result.data.dominant_freq
          sample.rms_energy = result.data.rms_energy
          sample.sample_type = result.data.sample_type
          sample.snap_offset = result.data.snap_offset

          -- Add Drum or Swell tag if detected by analyzer
          if result.data.sample_type and (result.data.sample_type == "Drum" or result.data.sample_type == "Swell") then
            local has_tag = false
            for _, tag in ipairs(sample.tags) do
              if tag == result.data.sample_type then
                has_tag = true
                break
              end
            end
            if not has_tag then
              table.insert(sample.tags, result.data.sample_type)
            end
          end
          merged_count = merged_count + 1
        elseif result.err then
          add_scan_log(string.format("Failed to merge analyzer data for %s: %s", path:match("([^/]+)$") or path, result.err))
        end
        found_sample = true
        break
      end
    end

    if not found_sample then
      add_scan_log(string.format("Could not find sample for analyzer result: %s", path))
    end

    -- Remove from results after merging
    state.analyzer_results[path] = nil
  end

  if merged_count > 0 then
    add_scan_log(string.format("Successfully merged %d analyzer results", merged_count))
  end

  -- If analyzer results were merged, re-layout samples since positions may have changed
  if merged_count > 0 then
    layout_samples()
  end
  
  -- DISABLED: Time-based saving during scan (only save at end)
  -- If analyzer results were merged, persist them on a timer so dominant_freq/rms
  -- don't remain nil in the cache (which would later default to 440 Hz on reload)
  -- local current_time = r.time_precise()
  -- local time_since_last_save = current_time - state.last_save_time
  -- if merged_count > 0 and time_since_last_save >= 2.0 then
  --   save_samples()
  --   state.last_save_time = current_time
  --   time_since_last_save = 0
  -- end
  
  -- Check if scan just completed (queue is empty but scan was started)
  -- This handles the case where rescan is clicked but there are no new files
  -- Also check if analyzer queue is empty and no active processes
  local scan_complete = (#state.scan_queue == 0 and state.scan_started > 0 and state.scan_total > 0)
  local analyzer_complete = (#state.analyzer_queue == 0 and #state.active_processes == 0)
  local finished_this_frame = false
  
  if scan_complete and analyzer_complete then
    -- Final save to ensure merged analyzer data is cached
    save_samples()
    state.last_save_time = r.time_precise()
    -- Scan completed (either just finished or was empty from start)
    -- Count samples with tags before rebuilding index
    local samples_with_tags = 0
    for _, s in ipairs(state.samples) do
      if s.tags and type(s.tags) == "table" and #s.tags > 0 then
        samples_with_tags = samples_with_tags + 1
      end
    end
    -- Scan completion log removed - use scan logs instead
    -- Rebuild tag index to ensure tags are preserved
    rebuild_tag_index()
    state.scan_started = 0  -- Reset to indicate scan is complete
    finished_this_frame = true  -- Continue to layout below
  end
  
  if #state.scan_queue == 0 then
    -- No more files to process; if analyzer still running, wait for completion
    if not analyzer_complete then
      return
    end
  end
  
  local deadline = r.time_precise() + (max_ms / 1000.0)
  math.randomseed(state.map_seed)
  
  local processed = 0
  local should_save = false
  local last_log_count = state.scan_total - #state.scan_queue
  local slice_start_time = r.time_precise()
  local total_analyze_time = 0
  local total_other_time = 0
  
  while #state.scan_queue > 0 and r.time_precise() < deadline do
    local path = table.remove(state.scan_queue)
    local file_start = r.time_precise()
    local sample = analyze_file(path)
    local file_time = (r.time_precise() - file_start) * 1000
    
    if sample then
      table.insert(state.samples, sample)
      processed = processed + 1
      should_save = true
      total_analyze_time = total_analyze_time + file_time
    else
      total_other_time = total_other_time + file_time
    end
  end
  
  -- Slice timing and progress logs removed - use scan logs instead
  
  -- DISABLED: Time-based cache saving during scan (only save at end)
  -- Time-based cache saving (every 2 seconds)
  -- current_time = r.time_precise()
  -- time_since_last_save = current_time - state.last_save_time
  -- if should_save and time_since_last_save >= 2.0 then
  --   save_samples()
  --   state.last_save_time = current_time
  -- end
  
  -- DISABLED: Incremental saving during scan (only save at end)
  -- Save progress incrementally (every 50 files or when queue is empty) - reduced frequency for speed
  -- if should_save and (processed >= 50 or #state.scan_queue == 0) then
  --   save_samples()
  --   state.last_save_time = current_time
  -- end
  
  if #state.scan_queue == 0 then
    -- Count samples with tags before layout
    local samples_with_tags_before = 0
    for _, s in ipairs(state.samples) do
      if s.tags and type(s.tags) == "table" and #s.tags > 0 then
        samples_with_tags_before = samples_with_tags_before + 1
      end
    end
    -- Scan complete log removed - use scan logs instead
    -- Layout samples
    layout_samples()
    -- Count samples with tags after layout
    local samples_with_tags_after = 0
    for _, s in ipairs(state.samples) do
      if s.tags and type(s.tags) == "table" and #s.tags > 0 then
        samples_with_tags_after = samples_with_tags_after + 1
      end
    end
    -- Analysis complete log removed - use scan logs instead
    rebuild_tag_index()
    save_samples()
  end
end


-- --- Frequency analysis for spectral waveform ----------------------------------
-- Estimate dominant frequency using autocorrelation with zero-crossing fallback
local function estimate_dominant_frequency(samples, sample_rate)
  if not samples or #samples < 16 then
    return nil  -- Need at least 16 samples for meaningful analysis
  end

  local n = #samples

  -- For large sample sets, downsample to improve performance while maintaining frequency resolution
  local analysis_samples = samples
  local analysis_sr = sample_rate
  if n > 512 then
    -- Downsample to ~512 samples to balance performance and accuracy
    local downsample_factor = math.floor(n / 512)
    analysis_samples = {}
    analysis_sr = sample_rate / downsample_factor

    for i = 1, n, downsample_factor do
      table.insert(analysis_samples, samples[i])
    end
    n = #analysis_samples
  end

  -- Normalize samples (center around zero and normalize amplitude)
  local sum = 0.0
  local max_amp = 0.0
  for i = 1, n do
    sum = sum + analysis_samples[i]
    max_amp = math.max(max_amp, math.abs(analysis_samples[i]))
  end

  if max_amp < 1e-6 then
    return nil  -- Silence
  end

  -- Remove DC offset and normalize
  local mean = sum / n
  local normalized = {}
  for i = 1, n do
    normalized[i] = (analysis_samples[i] - mean) / max_amp
  end

  -- Try autocorrelation first (more accurate for periodic signals)
  -- Focus on musical frequency range: 80Hz to 8000Hz (covers most instruments)
  local max_freq = 8000  -- Look for frequencies up to 8kHz
  local min_freq = 80    -- Minimum frequency to detect (below this, likely noise or rumble)
  local min_lag = math.floor(analysis_sr / max_freq)
  local max_lag = math.floor(analysis_sr / min_freq)

  min_lag = math.max(2, min_lag)
  max_lag = math.min(max_lag, math.floor(n / 2))

  if max_lag >= min_lag then
    -- Calculate autocorrelation at lag 0 for normalization
    local autocorr_0 = 0.0
    for i = 1, n do
      autocorr_0 = autocorr_0 + normalized[i] * normalized[i]
    end
    autocorr_0 = autocorr_0 / n

    if autocorr_0 > 1e-10 then
      -- Autocorrelation - look for the strongest peak in the musical range
      local max_corr = -math.huge
      local best_lag = nil

      for lag = min_lag, max_lag do
        local corr = 0.0
        local count = 0

        for i = 1, n - lag do
          corr = corr + normalized[i] * normalized[i + lag]
          count = count + 1
        end

        if count > 0 then
          -- Normalize autocorrelation
          corr = corr / count
          corr = corr / autocorr_0  -- Normalize by autocorrelation at lag 0

          if corr > max_corr then
            max_corr = corr
            best_lag = lag
          end
        end
      end

      -- Require a minimum correlation threshold to avoid noise
      if best_lag and best_lag > 0 and max_corr > 0.3 then  -- Higher threshold for better accuracy
        local freq = analysis_sr / best_lag
        -- Clamp to audible range (20Hz to 20kHz)
        freq = math.max(20, math.min(20000, freq))
        return freq
      end
    end
  end

  -- Fallback: Zero-crossing rate estimation (simpler but less accurate)
  -- Count zero crossings to estimate frequency
  local zero_crossings = 0
  for i = 2, n do
    if (normalized[i-1] >= 0 and normalized[i] < 0) or (normalized[i-1] < 0 and normalized[i] >= 0) then
      zero_crossings = zero_crossings + 1
    end
  end

  if zero_crossings > 2 then
    -- Each zero crossing represents half a cycle
    local cycles = zero_crossings / 2
    local duration = n / analysis_sr
    local freq = cycles / duration
    -- Clamp to audible range
    freq = math.max(20, math.min(20000, freq))
    return freq
  end

  return nil
end

-- Convert frequency to color (spectral mapping: low=red, mid=yellow/green, high=blue)
local function frequency_to_color(freq)
  if not freq then
    return 0x888888FF  -- Gray for no frequency data
  end
  
  -- Map frequency to hue (0-360 degrees)
  -- 20Hz = red (0°), 2000Hz = yellow (60°), 20000Hz = blue (240°)
  local hue
  if freq < 2000 then
    -- Low to mid: red to yellow (0° to 60°)
    local t = (freq - 20) / (2000 - 20)
    hue = t * 60
  elseif freq < 8000 then
    -- Mid to high-mid: yellow to cyan (60° to 180°)
    local t = (freq - 2000) / (8000 - 2000)
    hue = 60 + t * 120
  else
    -- High: cyan to blue (180° to 240°)
    local t = (freq - 8000) / (20000 - 8000)
    hue = 180 + t * 60
  end
  
  -- Convert HSV to RGB
  local c = 1.0  -- Chroma
  local x = c * (1 - math.abs((hue / 60) % 2 - 1))
  local m = 0.3  -- Lightness adjustment (make it darker for visibility)
  
  local r, g, b = 0, 0, 0
  if hue < 60 then
    r, g, b = c, x, 0
  elseif hue < 120 then
    r, g, b = x, c, 0
  elseif hue < 180 then
    r, g, b = 0, c, x
  elseif hue < 240 then
    r, g, b = 0, x, c
  else
    r, g, b = x, 0, c
  end
  
  -- Convert to 0-255 and apply lightness
  r = math.floor((r + m) * 255)
  g = math.floor((g + m) * 255)
  b = math.floor((b + m) * 255)
  
  -- Clamp values
  r = math.max(0, math.min(255, r))
  g = math.max(0, math.min(255, g))
  b = math.max(0, math.min(255, b))
  
  -- Return as ARGB (0xAARRGGBB format)
  return (0xFF << 24) | (r << 16) | (g << 8) | b
end

-- --- Waveform generation -----------------------------------------------------
local function generate_waveform(sample, width)
  width = width or waveform_width
  if not sample or not sample.path then
    return nil
  end
  
  -- Create a temporary track and item to access audio samples via AudioAccessor
  local temp_track = r.GetTrack(0, 0)  -- Try to use first track
  if not temp_track then
    temp_track = r.InsertTrackAtIndex(0, true)
  end
  
  if not temp_track then
    log("Failed to create/get track for waveform generation")
    return nil
  end
  
  -- Insert media item
  local item = r.AddMediaItemToTrack(temp_track)
  if not item then
    log("Failed to create media item for waveform")
    return nil
  end
  
  -- Set item position
  r.SetMediaItemPosition(item, 0, false)
  local src = r.PCM_Source_CreateFromFile(sample.path)
  if not src then
    r.DeleteTrackMediaItem(temp_track, item)
    log("Failed to create PCM source for waveform")
    return nil
  end
  
  local length_ret = {r.GetMediaSourceLength(src)}
  local duration = pick_number(length_ret, 0.0)
  if duration <= 0 then
    r.PCM_Source_Destroy(src)
    r.DeleteTrackMediaItem(temp_track, item)
    return nil
  end
  
  r.SetMediaItemLength(item, duration, false)
  
  -- Add take
  local take = r.AddTakeToMediaItem(item)
  if not take then
    r.PCM_Source_Destroy(src)
    r.DeleteTrackMediaItem(temp_track, item)
    log("Failed to create take for waveform")
    return nil
  end
  
  r.SetMediaItemTake_Source(take, src)
  r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", 0.0)
  
  -- Note: After SetMediaItemTake_Source, REAPER owns the src, so don't destroy it manually
  
  -- Create audio accessor (we'll create fresh ones for each pixel to avoid positioning issues)
  local accessor = r.CreateTakeAudioAccessor(take)
  if not accessor then
    -- Don't destroy src - it's owned by the take/item now
    r.DeleteTrackMediaItem(temp_track, item)
    log("Failed to create audio accessor")
    return nil
  end
  
  -- Check if GetAudioAccessorSamples API exists
  if not r.APIExists("GetAudioAccessorSamples") then
    log("GetAudioAccessorSamples API not available in this REAPER version")
    r.DestroyAudioAccessor(accessor)
    -- Note: Don't destroy src here - it's owned by the take/item
    r.DeleteTrackMediaItem(temp_track, item)
    return nil
  end
  
  local sr_ret = {r.GetMediaSourceSampleRate(src)}
  local sr = pick_number(sr_ret, 44100.0)
  
  local ch_ret = {r.GetMediaSourceNumChannels(src)}
  local channels = math.max(1, math.floor(pick_number(ch_ret, 2)))  -- Ensure at least 1 channel
  
  -- Calculate samples to read per pixel
  -- Ensure we read at least 128 samples per pixel for better frequency analysis
  local samples_per_pixel = math.max(128, math.floor((duration * sr) / width))
  
  -- Store waveform data per channel (for stereo: separate left/right)
  local waveform_channels = {}
  local frequency_channels = {}  -- Store frequency data per channel per pixel
  for c = 0, channels - 1 do
    waveform_channels[c] = {}
    frequency_channels[c] = {}
  end
  local max_val_per_channel = {}
  for c = 0, channels - 1 do
    max_val_per_channel[c] = 0.0
  end
  
  -- Read samples for each pixel
  local pixel_idx = 0
  
  while pixel_idx < width do
    
    -- Read samples (REAPER's PCM_Source API)
    -- Note: REAPER doesn't have a direct ReadSamples API in Lua
    -- We'll use a workaround: create a temporary take and read from it
    -- For now, let's use a simpler approach: sample at regular intervals
    
    -- Calculate RMS for this pixel's worth of samples
    -- Since we can't easily read raw samples, we'll use a simplified approach
    -- by sampling at regular time intervals
    local time_per_pixel = duration / width
    local time_at_pixel = pixel_idx * time_per_pixel
    
    -- Use REAPER's ability to get peak info at a specific time
    -- This is a simplified waveform - we'll use duration-based estimation
    -- For a more accurate waveform, we'd need to read actual samples
    
    -- For now, create a placeholder waveform based on file properties
    -- In a full implementation, you'd read actual sample data
    -- Calculate RMS for this pixel using AudioAccessor
    local time_start = (pixel_idx) * (duration / width)
    local time_end = (pixel_idx + 1) * (duration / width)
    local time_center = (time_start + time_end) * 0.5
    
    -- For frequency analysis, we need a longer time window to capture low frequencies
    -- Use a wider window: current pixel plus some surrounding context
    local analysis_window_start = math.max(0, time_start - 0.01)  -- 10ms before
    local analysis_window_end = math.min(duration, time_end + 0.01)  -- 10ms after
    local analysis_window_duration = analysis_window_end - analysis_window_start

    -- Read enough samples for frequency analysis (aim for 256-1024 samples for good analysis)
    local target_samples = math.max(256, math.floor(analysis_window_duration * sr))
    target_samples = math.min(target_samples, 1024)  -- Cap at 1024 to avoid excessive processing
    local max_samples_for_window = math.floor(analysis_window_duration * sr)
    local read_samples = math.min(target_samples, max_samples_for_window)
    read_samples = math.max(64, read_samples)  -- Minimum 64 samples for frequency analysis

    -- For very short windows, try to read more samples by extending the window
    if read_samples < 256 and analysis_window_start > 0.02 then
      -- Extend backward if possible
      analysis_window_start = math.max(0, analysis_window_start - 0.02)
      analysis_window_duration = analysis_window_end - analysis_window_start
      read_samples = math.min(1024, math.floor(analysis_window_duration * sr))
      read_samples = math.max(64, read_samples)
    elseif read_samples < 256 and analysis_window_end < duration - 0.02 then
      -- Extend forward if possible
      analysis_window_end = math.min(duration, analysis_window_end + 0.02)
      analysis_window_duration = analysis_window_end - analysis_window_start
      read_samples = math.min(1024, math.floor(analysis_window_duration * sr))
      read_samples = math.max(64, read_samples)
    end

    local buf_size = read_samples * channels
    local buf = r.new_array(buf_size)

    -- Debug logging for analysis window setup
    if pixel_idx < 3 then
      log(string.format("Pixel %d: analysis_window=%.3fs-%.3fs (%.1fms), target_samples=%d, read_samples=%d",
          pixel_idx + 1, analysis_window_start, analysis_window_end, analysis_window_duration * 1000, target_samples, read_samples))
    end
    
    -- Create a fresh accessor for each pixel to avoid positioning issues
    local pixel_accessor = r.CreateTakeAudioAccessor(take)
    if not pixel_accessor then
      log("Failed to create accessor for pixel " .. (pixel_idx + 1))
      if buf and buf.clear then
        buf.clear(buf)
      end
      for c = 0, channels - 1 do
        waveform_channels[c][pixel_idx + 1] = 0.1
        frequency_channels[c][pixel_idx + 1] = nil
      end
      pixel_idx = pixel_idx + 1
    elseif not r.GetAudioAccessorSamples then
      log("ERROR: GetAudioAccessorSamples not available - waveform generation will fail")
      r.DestroyAudioAccessor(pixel_accessor)
      if buf and buf.clear then
        buf.clear(buf)
      end
      for c = 0, channels - 1 do
        waveform_channels[c][pixel_idx + 1] = 0.1
        frequency_channels[c][pixel_idx + 1] = nil
      end
      pixel_idx = pixel_idx + 1
    else
      -- Read from analysis window to get samples for frequency analysis
      local samples_read = r.GetAudioAccessorSamples(pixel_accessor, sr, channels, analysis_window_start, read_samples, buf)

      -- Clean up the pixel accessor
      r.DestroyAudioAccessor(pixel_accessor)

      -- Debug logging for first few pixels
      if pixel_idx < 3 then
        log(string.format("Pixel %d: samples_read=%s, read_samples=%d, buf_size=%d, channels=%d, sr=%.0f, analysis_start=%.3f, analysis_end=%.3f", 
            pixel_idx + 1, tostring(samples_read), read_samples, buf_size, channels, sr, analysis_window_start, analysis_window_end))
      end
      
      if samples_read and samples_read > 0 and buf then
        -- GetAudioAccessorSamples returns the number of sample frames read (not total samples)
        -- Each frame contains one sample per channel
        local actual_frames = samples_read

        if pixel_idx < 3 then
          log(string.format("Pixel %d: Got %d sample frames (%d total samples across %d channels)",
              pixel_idx + 1, actual_frames, actual_frames * channels, channels))
        end
        
        -- Calculate RMS per channel for this pixel
        local sum_sq_per_channel = {}
        local count_per_channel = {}
        for c = 0, channels - 1 do
          sum_sq_per_channel[c] = 0.0
          count_per_channel[c] = 0
        end
        
        -- Debug: check first few buffer values for first pixel
        if pixel_idx < 1 and channels >= 2 then
          local debug_vals = {}
          -- REAPER arrays are 1-indexed, so we need to add 1 to the index
          for i = 0, math.min(5, buf_size - 1) do
            local buf_idx = i + 1  -- Convert to 1-based index
            local ok, val = pcall(function() return buf[buf_idx] end)
            if ok then
              debug_vals[i] = val
            else
              debug_vals[i] = "ERROR"
            end
          end
          -- Use %s to avoid errors if values are non-numeric
          log(string.format("Pixel %d buffer first 6 values: [0]=%s [1]=%s [2]=%s [3]=%s [4]=%s [5]=%s", 
              pixel_idx + 1, tostring(debug_vals[0] or 0), tostring(debug_vals[1] or 0), tostring(debug_vals[2] or 0), 
              tostring(debug_vals[3] or 0), tostring(debug_vals[4] or 0), tostring(debug_vals[5] or 0)))
        end
        
        -- Extract samples per channel for frequency analysis
        local channel_samples = {}
        for c = 0, channels - 1 do
          channel_samples[c] = {}
        end
        
        for j = 0, actual_frames - 1 do
          for c = 0, channels - 1 do
            -- REAPER arrays are 1-indexed, interleaved: [sample0_ch0, sample0_ch1, sample1_ch0, sample1_ch1, ...]
            -- Calculate 0-based index, then add 1 for 1-based array access
            local idx_0based = j * channels + c
            local buf_idx = idx_0based + 1  -- Convert to 1-based index for REAPER arrays
            if idx_0based >= 0 and idx_0based < buf_size then
              local ok, sample_val = pcall(function() return buf[buf_idx] end)
              if ok and sample_val ~= nil then
                sum_sq_per_channel[c] = sum_sq_per_channel[c] + (sample_val * sample_val)
                count_per_channel[c] = count_per_channel[c] + 1
                table.insert(channel_samples[c], sample_val)
              else
                if pixel_idx < 3 then
                  log(string.format("WARNING: Pixel %d, frame %d, ch %d: failed to read buf[%d] (1-based)", pixel_idx + 1, j, c, buf_idx))
                end
              end
            else
              if pixel_idx < 3 and c == 0 then
                log(string.format("WARNING: Pixel %d, frame %d, ch %d: idx %d out of bounds (buf_size=%d)", 
                    pixel_idx + 1, j, c, idx_0based, buf_size))
              end
            end
          end
        end
        
        -- Calculate RMS and frequency for each channel
        for c = 0, channels - 1 do
          if count_per_channel[c] > 0 then
            local rms = math.sqrt(sum_sq_per_channel[c] / count_per_channel[c])
            waveform_channels[c][pixel_idx + 1] = rms
            max_val_per_channel[c] = math.max(max_val_per_channel[c], rms)
            
            -- Estimate dominant frequency for this pixel/channel
            local freq = estimate_dominant_frequency(channel_samples[c], sr)
            frequency_channels[c][pixel_idx + 1] = freq
            
            -- Debug first few pixels for all channels
            if pixel_idx < 3 then
              local sample_count = channel_samples[c] and #channel_samples[c] or 0
              local first_sample = (channel_samples[c] and channel_samples[c][1]) or 0
              log(string.format("Pixel %d: time=%.3f, ch%d_rms=%.6f, ch%d_freq=%sHz, sample_count=%d, first_sample=%.6f", 
                  pixel_idx + 1, time_center, c, rms, c, freq and string.format("%.1f", freq) or "nil", sample_count, first_sample))
            end
          else
            waveform_channels[c][pixel_idx + 1] = 0.0
            frequency_channels[c][pixel_idx + 1] = nil
            if pixel_idx < 3 then
              log(string.format("WARNING: Pixel %d ch%d got 0 samples (buf_size=%d, read_samples=%d, actual_frames=%d, channels=%d)", 
                  pixel_idx + 1, c, buf_size, read_samples, actual_frames, channels))
            end
          end
        end
      else
        for c = 0, channels - 1 do
          waveform_channels[c][pixel_idx + 1] = 0.0
        end
        if pixel_idx < 3 then
          log(string.format("WARNING: GetAudioAccessorSamples failed for pixel %d: samples_read=%s, buf=%s", 
              pixel_idx + 1, tostring(samples_read), tostring(buf ~= nil)))
        end
      end
      
      if buf and buf.clear then
        buf.clear(buf)
      end
    end
    
    pixel_idx = pixel_idx + 1
  end
  
  -- Cleanup (accessors are destroyed per pixel now)
  -- Note: Don't destroy src - it's owned by the take/item, will be cleaned up when item is deleted
  r.DeleteTrackMediaItem(temp_track, item)
  
  -- Normalize waveforms per channel
  for c = 0, channels - 1 do
    local max_val = max_val_per_channel[c]
    log(string.format("Channel %d max_val before normalization: %.6f", c, max_val))
    if max_val > 0.001 then
      for i = 1, #waveform_channels[c] do
        waveform_channels[c][i] = waveform_channels[c][i] / max_val
      end
      log(string.format("Channel %d waveform normalized successfully", c))
    else
      -- If all values are very small, log warning and use a small value
      log("WARNING: Channel " .. c .. " max_val is very small (" .. string.format("%.6f", max_val) .. "), using placeholder")
      for i = 1, #waveform_channels[c] do
        waveform_channels[c][i] = 0.1
      end
    end
  end
  
  -- Log first few values for debugging (all channels)
  for c = 0, channels - 1 do
    if #waveform_channels[c] > 0 then
      local debug_str = string.format("First 5 waveform values (ch%d): ", c)
      for i = 1, math.min(5, #waveform_channels[c]) do
        debug_str = debug_str .. string.format("%.6f ", waveform_channels[c][i])
      end
      log(debug_str)
      
      -- Count non-zero values
      local non_zero_count = 0
      for i = 1, #waveform_channels[c] do
        if waveform_channels[c][i] and waveform_channels[c][i] > 0.0001 then
          non_zero_count = non_zero_count + 1
        end
      end
      log(string.format("Channel %d: %d total pixels, %d non-zero values", c, #waveform_channels[c], non_zero_count))
    else
      log(string.format("WARNING: Channel %d has no waveform data!", c))
    end
  end
  
  -- Return channel data: for mono, return single array; for stereo+, return table with channel arrays
  local waveform_data = {}
  local frequency_data = {}
  if channels == 1 then
    -- Mono: return single array for backward compatibility
    waveform_data.data = waveform_channels[0]
    frequency_data.data = frequency_channels[0]
    log("Returning mono waveform data")
  else
    -- Multi-channel: return table with channel arrays
    waveform_data.channel_data = {}
    frequency_data.channel_data = {}
    for c = 0, channels - 1 do
      waveform_data.channel_data[c] = waveform_channels[c]
      frequency_data.channel_data[c] = frequency_channels[c]
      log(string.format("Channel %d: %d pixels in channel_data", c, #waveform_channels[c]))
    end
    -- Also provide 'data' for backward compatibility (use first channel)
    waveform_data.data = waveform_channels[0]
    frequency_data.data = frequency_channels[0]
    local ch_data_count = 0
    if waveform_data.channel_data then
      for k, v in pairs(waveform_data.channel_data) do
        ch_data_count = ch_data_count + 1
      end
    end
    log(string.format("Multi-channel waveform: %d channels, channel_data has %d entries", 
        channels, ch_data_count))
  end
  
  local result = {
    data = waveform_data.data,  -- For backward compatibility
    channel_data = waveform_data.channel_data,  -- Per-channel data (nil for mono)
    frequency_data = frequency_data.data,  -- Frequency data for mono (backward compatibility)
    frequency_channel_data = frequency_data.channel_data,  -- Per-channel frequency data (nil for mono)
    duration = duration,
    sample_rate = sr,
    channels = channels
  }
  
  log(string.format("Waveform generation complete: channels=%d, data points=%d, channel_data=%s", 
      channels, result.data and #result.data or 0, result.channel_data and "present" or "nil"))
  
  return result
end


-- --- Preview handling --------------------------------------------------------
local function stop_preview()
  -- Stop CF_Preview instances first (uses objects, not IDs)
  if cf_preview_obj then
    if r.CF_Preview_StopAll then
      r.CF_Preview_StopAll()
    elseif r.CF_Preview_Stop then
      r.CF_Preview_Stop(cf_preview_obj)
    end
    cf_preview_obj = nil
  elseif r.CF_Preview_StopAll then
    -- Stop all CF_Preview instances even if we don't have a handle
    r.CF_Preview_StopAll()
  end
  
  -- Stop preview using Xen_StopSourcePreview if we have an integer preview ID
  -- (preview_proc should be a number/integer ID, not a CF_Preview object)
  if preview_proc and type(preview_proc) == "number" and r.Xen_StopSourcePreview then
    r.Xen_StopSourcePreview(preview_proc)
    preview_proc = nil
    -- Note: REAPER will automatically destroy the PCM_source when preview stops
    -- (as per API docs: "it will be deleted by the preview system when the preview is stopped")
    preview_source = nil
  elseif preview_proc and type(preview_proc) == "number" and r.StopSourcePreview then
    r.StopSourcePreview(preview_proc)
    preview_proc = nil
    preview_source = nil
  elseif preview_source then
    -- Fallback: try other stop methods
    if r.StopTrackPreview2 and preview_track then
      r.StopTrackPreview2(preview_source, preview_track)
    elseif r.StopTrackPreview then
      r.StopTrackPreview(preview_source)
    end
    -- For PlayMediaPreview, we may need to destroy the source ourselves
    -- But let's be safe and let REAPER handle it if possible
    if preview_proc == true then
      -- PlayMediaPreview was used (preview_proc is just a boolean flag)
      -- Try to stop it - but we don't have a handle, so we'll just clear
      preview_proc = nil
    end
    -- Don't destroy source here - let REAPER handle it or create fresh one next time
    preview_source = nil
  end
  
  preview_start_time = 0.0
  preview_sample_obj = nil
end


-- --- History navigation --------------------------------------------------------
local function preview_sample_from_history(sample)
  -- Preview a sample without adding it to history (used for navigation)
  local start_time = 0.0
  
  if not sample or not sample.path then
    return
  end
  
  -- Stop current preview before starting new one
  stop_preview()
  
  preview_sample_obj = sample
  preview_start_time = r.time_precise() - start_time
  -- Reset breathing cycle when navigating to a sample
  state.breathing_start_time = r.time_precise()
  
  -- Generate waveform if not already cached
  if not waveform_data or waveform_data.sample_path ~= sample.path then
    log("Generating waveform for: " .. sample.name)
    waveform_data = generate_waveform(sample)
    if waveform_data then
      waveform_data.sample_path = sample.path
      log("Waveform generated successfully: " .. #waveform_data.data .. " points")
    else
      log("WARNING: Waveform generation failed for: " .. sample.name)
      waveform_data = {
        data = {},
        duration = sample.duration or 1.0,
        sample_rate = sample.samplerate or 44100,
        channels = sample.channels or 2,
        sample_path = sample.path,
        frequency_data = {}  -- Empty frequency data (will show gray)
      }
      for i = 1, waveform_width do
        waveform_data.data[i] = 0.1
        waveform_data.frequency_data[i] = nil  -- No frequency data
      end
    end
  end
  
  -- Create PCM_source and start preview (same as preview_sample)
  preview_source = r.PCM_Source_CreateFromFile(sample.path)
  if not preview_source then
    log("Failed to create preview source for: " .. tostring(sample.path))
    return
  end

  -- Try CF_Preview API first
  if r.CF_CreatePreview and r.CF_Preview_SetValue and r.CF_Preview_Play then
    cf_preview_obj = r.CF_CreatePreview(preview_source)
    if cf_preview_obj then
      if start_time > 0 then
        r.CF_Preview_SetValue(cf_preview_obj, "D_POSITION", start_time)
      end
      local ret = r.CF_Preview_Play(cf_preview_obj)
      if ret then
        preview_proc = true
        preview_start_time = r.time_precise() - start_time
        state.pop_start_time = r.time_precise()  -- Trigger pop effect
      else
        cf_preview_obj = nil
      end
    end
  elseif r.PlayTrackPreview2 then
    local track = ensure_preview_track()
    if track then
      local preview = {
        src = preview_source,
        startpos = start_time,
        volume = 1.0,
        pan = 0.0,
        loop = false,
        length = -1.0,
        fadein = 0.0,
        fadeout = 0.0,
        pitch = 0.0,
        mode = 0,
      }
      local ret = r.PlayTrackPreview2(0, preview, track)
      if ret then
        preview_proc = true
        preview_start_time = r.time_precise() - start_time
        state.pop_start_time = r.time_precise()  -- Trigger pop effect
      end
    end
  elseif r.Xen_StartSourcePreview then
    local preview_id = r.Xen_StartSourcePreview(preview_source, 1.0, false)
    if preview_id and preview_id ~= 0 then
      preview_proc = preview_id
      preview_start_time = r.time_precise()
      state.pop_start_time = r.time_precise()  -- Trigger pop effect
    end
  end
end


local function navigate_history(direction)
  -- direction: -1 for back (up arrow), 1 for forward (down arrow)
  -- history_index: 0 = current sample, 1+ = index in played_history array
  
  local new_index = state.history_index + direction
  
  -- Clamp to valid range
  if new_index < 0 then
    return  -- Can't go back further than current
  elseif new_index > #state.played_history then
    return  -- Can't go forward past oldest
  end
  
  -- If going back from current (index 0) to history, need at least one item
  if new_index > 0 and #state.played_history == 0 then
    return
  end
  
  state.history_index = new_index
  
  local sample = nil
  if new_index == 0 then
    -- Back to current sample
    sample = preview_sample_obj
  else
    -- Navigate to history entry
    sample = state.played_history[new_index]  -- Lua arrays are 1-indexed
  end
  
  if sample and sample.path then
    preview_sample_from_history(sample)
  end
end


local function preview_sample(sample, start_time)
  start_time = math.max(0.0, start_time or 0.0)
  
  if not sample or not sample.path then
    return
  end
  
  -- Add current sample to history if it exists and is different from the new one
  if preview_sample_obj and preview_sample_obj.path and preview_sample_obj.path ~= sample.path then
    -- Insert at the beginning of history
    table.insert(state.played_history, 1, preview_sample_obj)
    -- Limit history size to 100 entries
    if #state.played_history > 100 then
      table.remove(state.played_history, #state.played_history)
    end
  end
  
  -- Reset history index when playing a new sample (not navigating history)
  state.history_index = 0
  
  -- Stop current preview before starting new one (as per example script pattern)
  stop_preview()

  preview_sample_obj = sample
  preview_start_time = r.time_precise() - start_time
  -- Reset breathing cycle when a new sample is clicked
  state.breathing_start_time = r.time_precise()
  
  -- Generate waveform if not already cached
  if not waveform_data or waveform_data.sample_path ~= sample.path then
    log("Generating waveform for: " .. sample.name)
    waveform_data = generate_waveform(sample)
    if waveform_data then
      waveform_data.sample_path = sample.path
      log("Waveform generated successfully: " .. #waveform_data.data .. " points")
    else
      log("WARNING: Waveform generation failed for: " .. sample.name)
      -- Create a placeholder waveform so something shows
      local channels = sample.channels or 2
      waveform_data = {
        data = {},
        duration = sample.duration or 1.0,
        sample_rate = sample.samplerate or 44100,
        channels = channels,
        sample_path = sample.path,
        frequency_data = {},  -- Empty frequency data (will show gray)
        frequency_channel_data = nil
      }
      -- Fill with placeholder data
      if channels > 1 then
        -- Multi-channel: create channel_data structure
        waveform_data.channel_data = {}
        waveform_data.frequency_channel_data = {}
        for c = 0, channels - 1 do
          waveform_data.channel_data[c] = {}
          waveform_data.frequency_channel_data[c] = {}
          for i = 1, waveform_width do
            waveform_data.channel_data[c][i] = 0.1
            waveform_data.frequency_channel_data[c][i] = nil  -- No frequency data
          end
        end
        -- Also set data for backward compatibility (use first channel)
        waveform_data.data = waveform_data.channel_data[0]
        waveform_data.frequency_data = waveform_data.frequency_channel_data[0]
      else
        -- Mono: just fill data array
        for i = 1, waveform_width do
          waveform_data.data[i] = 0.1
          waveform_data.frequency_data[i] = nil  -- No frequency data
        end
      end
    end
  end
  
  -- Always create a fresh PCM_source for each preview
  -- (REAPER will destroy it when preview stops, so we can't reuse it)
  if preview_source then
    -- Shouldn't happen since stop_preview() clears it, but be safe
    log("Warning: preview_source still exists, clearing it")
    preview_source = nil
  end
  
  preview_source = r.PCM_Source_CreateFromFile(sample.path)
  if not preview_source then
    log("Failed to create preview source for: " .. tostring(sample.path))
    return
  end

  log("Attempting to preview: " .. sample.path .. (start_time > 0 and (" at " .. string.format("%.2f", start_time) .. "s") or ""))
  log("  API check - CF_CreatePreview: " .. tostring(r.CF_CreatePreview ~= nil))
  log("  API check - CF_Preview_SetValue: " .. tostring(r.CF_Preview_SetValue ~= nil))
  log("  API check - CF_Preview_Play: " .. tostring(r.CF_Preview_Play ~= nil))
  log("  API check - PlayTrackPreview2: " .. tostring(r.PlayTrackPreview2 ~= nil))
  log("  API check - Xen_StartSourcePreview: " .. tostring(r.Xen_StartSourcePreview ~= nil))

  -- Try CF_Preview API first (supports seeking via CF_Preview_SetValue with "D_POSITION")
  if r.CF_CreatePreview and r.CF_Preview_SetValue and r.CF_Preview_Play then
    log("Using CF_Preview API for seeking support")
    -- Create CF_Preview object (correct function name is CF_CreatePreview)
    cf_preview_obj = r.CF_CreatePreview(preview_source)
    if cf_preview_obj then
      -- Set start position if needed using CF_Preview_SetValue with "D_POSITION"
      -- D_POSITION is in seconds (as per example script)
      if start_time > 0 then
        local set_ok = r.CF_Preview_SetValue(cf_preview_obj, "D_POSITION", start_time)
        if set_ok then
          log("Set CF_Preview start position to " .. string.format("%.2f", start_time) .. "s")
        else
          log("Warning: Could not set CF_Preview D_POSITION")
        end
      end
      -- Start playback
      local ret = r.CF_Preview_Play(cf_preview_obj)
      if ret then
        preview_proc = true  -- Flag that CF_Preview is active (don't store the object here)
        preview_start_time = r.time_precise() - start_time
        state.pop_start_time = r.time_precise()  -- Trigger pop effect
        log("CF_Preview_Play succeeded")
      else
        log("CF_Preview_Play returned false")
        cf_preview_obj = nil
      end
    else
      log("CF_CreatePreview returned nil")
    end
  -- Fallback to PlayTrackPreview2 (supports seeking via startpos in preview table)
  elseif r.PlayTrackPreview2 then
    log("Using PlayTrackPreview2 for seeking support")
    local track = ensure_preview_track()
    if track then
      local preview = {
        src = preview_source,
        startpos = start_time,
        volume = 1.0,
        pan = 0.0,
        loop = false,
        length = -1.0,
        fadein = 0.0,
        fadeout = 0.0,
        pitch = 0.0,
        mode = 0,
      }
      local ret = r.PlayTrackPreview2(0, preview, track)
      if ret then
        preview_proc = true
        preview_start_time = r.time_precise() - start_time
        state.pop_start_time = r.time_precise()  -- Trigger pop effect
        log("PlayTrackPreview2 succeeded with startpos=" .. string.format("%.2f", start_time))
      else
        log("PlayTrackPreview2 returned false")
      end
    else
      log("Failed to get preview track for PlayTrackPreview2")
    end
  -- Fallback to Xen_StartSourcePreview (no seeking support, always starts from beginning)
  elseif r.Xen_StartSourcePreview then
    log("Using Xen_StartSourcePreview fallback (no seek support)")
    -- Xen_StartSourcePreview(PCM_source source, number gain, boolean loop, optional integer outputchanindexIn)
    -- Returns integer preview handle ID
    local preview_id = r.Xen_StartSourcePreview(preview_source, 1.0, false)
    if preview_id and preview_id ~= 0 then
      preview_proc = preview_id
      preview_start_time = r.time_precise()
      state.pop_start_time = r.time_precise()  -- Trigger pop effect
      if start_time > 0 then
        log("Warning: Seek requested but Xen_StartSourcePreview doesn't support seeking; starting from 0")
      end
      log("Xen_StartSourcePreview succeeded, preview_id=" .. tostring(preview_id))
    else
      log("Xen_StartSourcePreview returned invalid ID: " .. tostring(preview_id))
    end
  else
    log("No preview APIs available; cannot play sample")
  end

  log("Preview start: " .. sample.name .. (start_time > 0 and (" at " .. string.format("%.2f", start_time) .. "s") or ""))
end


local function get_preview_position()
  if not preview_proc or not preview_sample_obj then
    return nil  -- Return nil to indicate preview is not active
  end
  
  -- Try to get actual position from CF_Preview if available
  if cf_preview_obj and r.CF_Preview_GetValue then
    local ret, pos = r.CF_Preview_GetValue(cf_preview_obj, "D_POSITION")
    if ret and pos then
      return pos
    end
  end
  
  -- Estimate position based on elapsed time (fallback)
  local elapsed = r.time_precise() - preview_start_time
  local duration = preview_sample_obj.duration or 0.0
  local pos = math.min(elapsed, duration)
  
  -- Check if preview has finished (elapsed >= duration)
  if elapsed >= duration then
    return nil  -- Preview finished, return nil
  end
  
  return pos
end


-- Helper function to change color alpha (set alpha value 0.0-1.0)
local function change_color_alpha(color, alpha_value)
  if not color then return color end
  local r, g, b = extract_rgb_rrgbbaa(color)
  local new_alpha = math.max(0, math.min(255, math.floor(alpha_value * 255)))
  return build_color_rrgbbaa(r, g, b, new_alpha)
end

-- Helper function to blend two colors
local function blend_colors(color1, color2, t)
  t = math.max(0.0, math.min(1.0, t))
  local r1, g1, b1 = extract_rgb_rrgbbaa(color1)
  local r2, g2, b2 = extract_rgb_rrgbbaa(color2)
  local r = math.floor(r1 * (1.0 - t) + r2 * t)
  local g = math.floor(g1 * (1.0 - t) + g2 * t)
  local b = math.floor(b1 * (1.0 - t) + b2 * t)
  local a1 = color1 % 256
  local a2 = color2 % 256
  local a = math.floor(a1 * (1.0 - t) + a2 * t)
  return build_color_rrgbbaa(r, g, b, a)
end

-- Helper function to brighten a color while preserving hue
-- brightness_factor: 0.0 = no change, 1.0 = maximum brightness (toward white but preserving hue)
local function brighten_color_preserve_hue(color, brightness_factor)
  brightness_factor = math.max(0.0, math.min(1.0, brightness_factor))
  local r, g, b = extract_rgb_rrgbbaa(color)
  
  -- Find the maximum component to determine the current brightness
  local max_component = math.max(r, g, b)
  if max_component == 0 then
    -- Black color - return a gray based on brightness
    local gray = math.floor(brightness_factor * 255)
    return build_color_rrgbbaa(gray, gray, gray, 255)
  end
  
  -- Calculate how much to scale each component toward 255 while preserving ratios
  -- This preserves hue while increasing brightness
  local scale_factor = 1.0 + brightness_factor * (255.0 / max_component - 1.0)
  
  local new_r = math.min(255, math.floor(r * scale_factor))
  local new_g = math.min(255, math.floor(g * scale_factor))
  local new_b = math.min(255, math.floor(b * scale_factor))
  
  return build_color_rrgbbaa(new_r, new_g, new_b, 255)
end

-- Draw glowing circle effect (adapted from provided pattern)
local function draw_glowing_circle(dl, x, y, glow_in, glow_out, solid_rad, clr, center_clr)
  -- Draw solid center circle if specified
  if solid_rad then
    local center_color = center_clr or clr
    r.ImGui_DrawList_AddCircleFilled(dl, x, y, solid_rad, center_color, 32)
  end
  
  -- Draw concentric circles for glow effect
  -- Use step size based on radius to balance quality and performance
  local step = math.max(0.5, (glow_out - glow_in) / 50.0)  -- Draw ~50 circles for smooth glow
  for i = glow_in, glow_out, step do
    local range = glow_out - glow_in
    if range > 0 then
      -- Calculate normalized position (1.0 at glow_in, 0.0 at glow_out)
      local n = (glow_out - i) / range
      
      -- Opacity decreases as we go outward
      local opacity = n
      
      -- Blend colors if center color is provided
      local circle_color = clr
      if center_clr then
        circle_color = blend_colors(clr, center_clr, n)
      end
      
      -- Apply opacity
      local final_color = change_color_alpha(circle_color, opacity)
      
      -- Draw circle outline (not filled for glow effect)
      r.ImGui_DrawList_AddCircle(dl, x, y, i, final_color, 32, 1.0)
    end
  end
end

-- --- UI helpers --------------------------------------------------------------
local function sample_passes_filters(sample)
  if not sample then return false end

  if state.filter ~= "" then
    local name = string.lower(sample.name or "")
    if not string.find(name, string.lower(state.filter), 1, true) then
      return false
    end
  end

  if state.active_tags and next(state.active_tags) ~= nil then
    local matched = false
    if sample.tags then
      for _, tag in ipairs(sample.tags) do
        if state.active_tags[tag] then
          matched = true
          break
        end
      end
    end
    if not matched then
      return false
    end
  end

  -- Check folder path filter
  if state.folder_filter_path and state.folder_filter_path ~= "" then
    local sample_path = normalize_path(sample.path or "")
    local filter_path = normalize_path(state.folder_filter_path)
    -- Check if sample path starts with filter path
    if not (sample_path:sub(1, #filter_path) == filter_path) then
      return false
    end
  end

  return true
end


-- Custom function to draw a nicer-looking tag button
local function draw_tag_button(ctx, label, active, tag, id_prefix)
  id_prefix = id_prefix or ""  -- Optional ID prefix to make buttons unique
  -- Get text size and frame padding for button sizing
  local text_size = {r.ImGui_CalcTextSize(ctx, label)}
  local frame_padding = {r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_FramePadding())}

  local button_width = text_size[1] + frame_padding[1] * 2
  local button_height = text_size[2] + frame_padding[2] * 2

  -- Get the tag's assigned color
  local tag_color = state.tag_colors[tag] or 0x336699 -- Default blue if not found

  -- Extract RGB components for color variations
  local base_r, base_g, base_b = extract_rgb(tag_color)

  -- Define colors based on active state using the tag's color
  local bg_color, border_color, text_color
  if active then
    -- Active: dim the tag color slightly for better text legibility
    local dim_factor = 0.75  -- Reduce brightness to 75% for active state
    bg_color = build_color_rrgbbaa(
      math.floor(base_r * dim_factor),
      math.floor(base_g * dim_factor),
      math.floor(base_b * dim_factor),
      255
    )
    -- Darken further for border
    border_color = build_color_rrgbbaa(
      math.max(0, math.floor(base_r * dim_factor * 0.7)),
      math.max(0, math.floor(base_g * dim_factor * 0.7)),
      math.max(0, math.floor(base_b * dim_factor * 0.7)),
      255
    )
    text_color = 0xFFFFFFFF   -- Active text: white
  else
    -- Inactive: brighter version of the tag color for better visibility
    local inactive_factor = 0.45  -- 45% brightness instead of 20%
    bg_color = build_color_rrgbbaa(
      math.floor(base_r * inactive_factor),
      math.floor(base_g * inactive_factor),
      math.floor(base_b * inactive_factor),
      255
    )
    border_color = build_color_rrgbbaa(
      math.floor(base_r * inactive_factor * 1.2),  -- Slightly brighter border
      math.floor(base_g * inactive_factor * 1.2),
      math.floor(base_b * inactive_factor * 1.2),
      255
    )
    text_color = 0xFFCCCCCC   -- Inactive text: light gray
  end

  -- Create an invisible button to handle input and layout
  local clicked = r.ImGui_InvisibleButton(ctx, "##" .. id_prefix .. "tag_" .. label, button_width, button_height)

  -- Get the button rect from ImGui
  local rect_min = {r.ImGui_GetItemRectMin(ctx)}
  local rect_max = {r.ImGui_GetItemRectMax(ctx)}

  -- Check if button is hovered
  local is_hovered = r.ImGui_IsItemHovered(ctx)
  
  -- Track hovered tag in state
  if is_hovered then
    state.hovered_tag = tag
  end

  -- Adjust colors for hover state
  if is_hovered and not active then
    -- Lighter version for inactive hover (between inactive and active brightness)
    local hover_factor = 0.6  -- 60% brightness for inactive hover
    bg_color = build_color_rrgbbaa(
      math.floor(base_r * hover_factor),
      math.floor(base_g * hover_factor),
      math.floor(base_b * hover_factor),
      255
    )
    border_color = build_color_rrgbbaa(
      math.floor(base_r * hover_factor * 1.3),  -- Slightly brighter border
      math.floor(base_g * hover_factor * 1.3),
      math.floor(base_b * hover_factor * 1.3),
      255
    )
    text_color = 0xFFE0E0E0    -- Hover text: brighter
  elseif is_hovered and active then
    -- Brighten the dimmed active color slightly for hover
    local hover_active_factor = 0.85  -- 85% brightness for active hover
    bg_color = build_color_rrgbbaa(
      math.floor(base_r * hover_active_factor),
      math.floor(base_g * hover_active_factor),
      math.floor(base_b * hover_active_factor),
      255
    )
    border_color = build_color_rrgbbaa(
      math.floor(base_r * hover_active_factor * 0.8),  -- Darker border for contrast
      math.floor(base_g * hover_active_factor * 0.8),
      math.floor(base_b * hover_active_factor * 0.8),
      255
    )
  end

  -- Get draw list and draw the custom button
  local draw_list = r.ImGui_GetWindowDrawList(ctx)

  -- Draw button background
  r.ImGui_DrawList_AddRectFilled(draw_list, rect_min[1], rect_min[2], rect_max[1], rect_max[2],
                                 bg_color, 4.0) -- 4.0 for rounded corners

  -- Draw border
  r.ImGui_DrawList_AddRect(draw_list, rect_min[1], rect_min[2], rect_max[1], rect_max[2],
                           border_color, 4.0, 0, 1.0)

  -- Draw text centered in the button
  local text_pos_x = rect_min[1] + frame_padding[1]
  local text_pos_y = rect_min[2] + frame_padding[2]

  -- Make active tags appear bold by drawing text with slight offset
  if active then
    -- Draw text multiple times with small offsets to create bold effect
    r.ImGui_DrawList_AddText(draw_list, text_pos_x, text_pos_y, text_color, label)
    r.ImGui_DrawList_AddText(draw_list, text_pos_x + 0.5, text_pos_y, text_color, label)
    r.ImGui_DrawList_AddText(draw_list, text_pos_x, text_pos_y + 0.5, text_color, label)
    r.ImGui_DrawList_AddText(draw_list, text_pos_x + 0.5, text_pos_y + 0.5, text_color, label)
  else
    r.ImGui_DrawList_AddText(draw_list, text_pos_x, text_pos_y, text_color, label)
  end

  return clicked
end

-- Function to save tag colors to current preset
local function save_tag_color_to_preset(tag, color)
  -- Load current presets
  local tag_presets = {}
  local function load_tag_presets()
    local preset_file = io.open(CONFIG_DIR .. "/tag_presets.lua", "r")
    if preset_file then
      local content = preset_file:read("*all")
      preset_file:close()
      local success, presets = pcall(load, content)
      if success and type(presets) == "function" then
        tag_presets = presets() or {}
      end
    end
  end
  load_tag_presets()
  
  -- Ensure current preset exists
  if not tag_presets[state.current_preset_name] then
    tag_presets[state.current_preset_name] = {}
  end
  
  -- Update the tag color in the preset
  tag_presets[state.current_preset_name][tag] = color
  
  -- Save presets back to file
  local preset_content = "return " .. serialize_table(tag_presets)
  local preset_file = io.open(CONFIG_DIR .. "/tag_presets.lua", "w")
  if preset_file then
    preset_file:write(preset_content)
    preset_file:close()
  end
end

-- Helper function to categorize tags
local function categorize_tags(tag)
  -- Normalize tag to lowercase for comparison (but preserve original for display)
  local tag_lower = string.lower(tag)
  
  -- Drum category tags (case-insensitive)
  local drum_tags = {
    kick = true, snare = true, clap = true, snap = true, rim = true, hat = true,
    tom = true, ride = true, crash = true, perc = true, fx = true,
    bass = true, ["808"] = true, drum = true
  }
  
  -- Melodic category tags (case-insensitive)
  local melodic_tags = {
    vocal = true, pluck = true, lead = true, pad = true,
    keys = true, guitar = true, swell = true  -- Swell is melodic
  }
  
  -- Loop/oneshot category tags (case-insensitive, handle both "One shot" and "oneshot")
  local loop_tags = {
    loop = true, ["one shot"] = true, oneshot = true
  }
  
  if drum_tags[tag_lower] then
    return "drum"
  elseif melodic_tags[tag_lower] then
    return "melodic"
  elseif loop_tags[tag_lower] then
    return "loop"
  end
  
  return nil
end

-- Helper function to draw a larger category tag
local function draw_category_tag(ctx, label, id_prefix)
  id_prefix = id_prefix or ""
  -- Get text size with larger font (we'll use a scale factor)
  local text_size = {r.ImGui_CalcTextSize(ctx, label)}
  local frame_padding = {r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_FramePadding())}
  
  -- Scale up the category tag (1.2x larger)
  local scale = 1.2
  local button_width = text_size[1] * scale + frame_padding[1] * 2
  local button_height = text_size[2] * scale + frame_padding[2] * 2
  
  -- Create invisible button for layout
  local clicked = r.ImGui_InvisibleButton(ctx, "##" .. id_prefix .. "cat_" .. label, button_width, button_height)
  
  -- Get button rect
  local rect_min = {r.ImGui_GetItemRectMin(ctx)}
  local rect_max = {r.ImGui_GetItemRectMax(ctx)}
  
  -- Category tags use a distinct style (darker, more prominent)
  local bg_color = 0xFF4A4A4A  -- Dark gray background
  local border_color = 0xFF666666  -- Lighter gray border
  local text_color = 0xFFFFFFFF   -- White text
  
  -- Check hover state
  local is_hovered = r.ImGui_IsItemHovered(ctx)
  if is_hovered then
    bg_color = 0xFF5A5A5A  -- Slightly lighter on hover
    border_color = 0xFF777777
  end
  
  -- Get draw list and draw the category tag
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  
  -- Draw button background
  r.ImGui_DrawList_AddRectFilled(draw_list, rect_min[1], rect_min[2], rect_max[1], rect_max[2],
                                 bg_color, 4.0)
  
  -- Draw border
  r.ImGui_DrawList_AddRect(draw_list, rect_min[1], rect_min[2], rect_max[1], rect_max[2],
                           border_color, 4.0, 0, 1.5)  -- Thicker border for category tags
  
  -- Draw text centered (scaled up)
  local text_pos_x = rect_min[1] + (button_width - text_size[1] * scale) * 0.5
  local text_pos_y = rect_min[2] + (button_height - text_size[2] * scale) * 0.5
  
  -- Draw text normally (no bold effect)
  r.ImGui_DrawList_AddText(draw_list, text_pos_x, text_pos_y, text_color, label)
  
  return clicked
end

local function render_tag_filters()
  if not state.tag_list or #state.tag_list == 0 then
    return
  end

  -- Reset hovered tag at start of frame
  state.hovered_tag = nil

  -- Categorize tags
  local drum_tags = {}
  local melodic_tags = {}
  local loop_tags = {}
  
  for _, entry in ipairs(state.tag_list) do
    local tag = entry.tag
    local category = categorize_tags(tag)
    if category == "drum" then
      table.insert(drum_tags, entry)
    elseif category == "melodic" then
      table.insert(melodic_tags, entry)
    elseif category == "loop" then
      table.insert(loop_tags, entry)
    end
  end

  -- Render Drum category (first line)
  if #drum_tags > 0 then
    -- Draw "Drum" category tag (larger)
    if draw_category_tag(ctx, "Drum", "cat_") then
      -- Toggle all drum tags when category tag is clicked
      local all_active = true
      for _, entry in ipairs(drum_tags) do
        if not state.active_tags[entry.tag] then
          all_active = false
          break
        end
      end
      -- Toggle all drum tags
      for _, entry in ipairs(drum_tags) do
        if all_active then
          state.active_tags[entry.tag] = nil
        else
          state.active_tags[entry.tag] = true
        end
      end
    end
    
    -- Draw colon
    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, ":")
    r.ImGui_SameLine(ctx)
    
    -- Draw drum tags
    for idx, entry in ipairs(drum_tags) do
      if idx > 1 then
        r.ImGui_SameLine(ctx)
      end
      local tag = entry.tag
      local active = state.active_tags[tag]
      local label = tag
      
      if draw_tag_button(ctx, label, active, tag) then
        if active then
          state.active_tags[tag] = nil
        else
          state.active_tags[tag] = true
        end
      end
    end
  end

  -- Render Melodic category (second line)
  if #melodic_tags > 0 then
    -- Start new line (don't call SameLine before first item)
    
    -- Draw "Melodic" category tag (larger)
    if draw_category_tag(ctx, "Melodic", "cat_") then
      -- Toggle all melodic tags when category tag is clicked
      local all_active = true
      for _, entry in ipairs(melodic_tags) do
        if not state.active_tags[entry.tag] then
          all_active = false
          break
        end
      end
      -- Toggle all melodic tags
      for _, entry in ipairs(melodic_tags) do
        if all_active then
          state.active_tags[entry.tag] = nil
        else
          state.active_tags[entry.tag] = true
        end
      end
    end
    
    -- Draw colon
    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, ":")
    r.ImGui_SameLine(ctx)
    
    -- Draw melodic tags
    for idx, entry in ipairs(melodic_tags) do
      if idx > 1 then
        r.ImGui_SameLine(ctx)
      end
      local tag = entry.tag
      local active = state.active_tags[tag]
      local label = tag
      
      if draw_tag_button(ctx, label, active, tag) then
        if active then
          state.active_tags[tag] = nil
        else
          state.active_tags[tag] = true
        end
      end
    end
  end

  -- Render Loop/Oneshot category (third line)
  if #loop_tags > 0 then
    -- Start new line (don't call SameLine before first item)
    
    -- Draw loop/oneshot tags (no category header, just the tags)
    for idx, entry in ipairs(loop_tags) do
      if idx > 1 then
        r.ImGui_SameLine(ctx)
      end
      local tag = entry.tag
      local active = state.active_tags[tag]
      local label = tag
      
      if draw_tag_button(ctx, label, active, tag) then
        if active then
          state.active_tags[tag] = nil
        else
          state.active_tags[tag] = true
        end
      end
    end
  end

  -- Check for C key press when hovering over a tag
  if state.hovered_tag and r.ImGui_IsKeyPressed and r.ImGui_Key_C then
    local c_pressed = r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_C(), false)
    if c_pressed then
      state.tag_color_picker_tag = state.hovered_tag
      r.ImGui_OpenPopup(ctx, "tag_color_picker")
    end
  end

  -- Color picker popup
  if r.ImGui_BeginPopup(ctx, "tag_color_picker") then
    if state.tag_color_picker_tag then
      r.ImGui_Text(ctx, "Edit color for: " .. state.tag_color_picker_tag)
      local tag_color = state.tag_colors[state.tag_color_picker_tag] or 0x336699
      local color_changed, new_color = r.ImGui_ColorEdit3(ctx, "Color", tag_color | 0xFF000000, 0)
      if color_changed then
        local rgb_color = new_color & 0xFFFFFF  -- Extract RGB part only
        state.tag_colors[state.tag_color_picker_tag] = rgb_color
        save_tag_color_to_preset(state.tag_color_picker_tag, rgb_color)
        save_config()  -- Also save to main config
      end
      
      r.ImGui_Spacing(ctx)
      if r.ImGui_Button(ctx, "Done") then
        r.ImGui_CloseCurrentPopup(ctx)
        state.tag_color_picker_tag = nil
      end
      
      -- Close popup if clicked outside (ImGui handles this automatically, but we can also check for escape)
      if r.ImGui_IsKeyPressed and r.ImGui_Key_Escape then
        local escape_pressed = r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false)
        if escape_pressed then
          r.ImGui_CloseCurrentPopup(ctx)
          state.tag_color_picker_tag = nil
        end
      end
    else
      -- Tag was cleared, close popup
      r.ImGui_CloseCurrentPopup(ctx)
    end
    r.ImGui_EndPopup(ctx)
  end

  -- Clear Tags button on a new line if any tags are active
  if next(state.active_tags) then
    -- Start new line (don't call SameLine before first item)
    if r.ImGui_SmallButton(ctx, "Clear Tags") then
      state.active_tags = {}
    end
  end

  r.ImGui_Separator(ctx)
end


local function begin_window()
  r.ImGui_SetNextWindowSize(ctx, 1024, 720, r.ImGui_Cond_FirstUseEver())
  -- Disable scrolling and set solid background
  -- Disable keyboard navigation so arrow keys can be used for history navigation
  local flags = r.ImGui_WindowFlags_NoCollapse() | 
                r.ImGui_WindowFlags_NoScrollbar() | 
                r.ImGui_WindowFlags_NoScrollWithMouse() |
                r.ImGui_WindowFlags_NoNav()
  
  -- Set solid black window background color
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x000000ff)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), 0x000000ff)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x000000ff)
  
  local visible, open = r.ImGui_Begin(ctx, SCRIPT_NAME, true, flags)
  
  return visible, open
end

-- Build peaks for a specific item while preserving user selection
local function rebuild_peaks_for_item(item)
  if not item then return end

  -- Save current selection
  local selected = {}
  local sel_count = r.CountSelectedMediaItems(0)
  for i = 0, sel_count - 1 do
    selected[#selected + 1] = r.GetSelectedMediaItem(0, i)
  end

  -- Select only the target item
  r.SelectAllMediaItems(0, false)
  r.SetMediaItemSelected(item, true)

  -- Rebuild peaks for selected items
  r.Main_OnCommand(40047, 0) -- Peaks: Rebuild peaks for selected items

  -- Restore previous selection
  r.SelectAllMediaItems(0, false)
  for _, it in ipairs(selected) do
    if r.ValidatePtr(it, "MediaItem*") then
      r.SetMediaItemSelected(it, true)
    end
  end
end

-- Insert a sample at the current cursor position in the arrange window
local function insert_sample_at_cursor(sample)
  if not sample or not sample.path then
    log("No sample to insert")
    return false
  end

  -- Check if file exists
  if not r.file_exists(sample.path) then
    log("Sample file does not exist: " .. sample.path)
    return false
  end

  -- Prevent UI refresh during operations
  r.PreventUIRefresh(1)

  -- Get cursor position
  local cursor_pos = r.GetCursorPosition()
  log("Cursor position: " .. string.format("%.3f", cursor_pos))

  -- Get selected track (or first track if none selected)
  local num_tracks = r.CountTracks(0)
  log("Total tracks in project: " .. num_tracks)

  local track = r.GetSelectedTrack(0, 0)
  if not track then
    log("No selected track, trying first track...")
    if num_tracks > 0 then
      track = r.GetTrack(0, 0)  -- Get first track (0-indexed)
    end
  end

  if not track then
    log("No track available for inserting sample (project has " .. num_tracks .. " tracks)")
    r.PreventUIRefresh(-1)
    return false
  end

  -- Get track info for debugging
  local _, track_name = r.GetTrackName(track)
  log("Using track: " .. (track_name or "unnamed"))

  -- Create media item
  local item = r.AddMediaItemToTrack(track)
  if not item then
    log("Failed to create media item")
    r.PreventUIRefresh(-1)
    return false
  end

  -- Set item position and length
  r.SetMediaItemPosition(item, cursor_pos, false)
  local duration = sample.duration or 1.0
  r.SetMediaItemLength(item, duration, false)
  log("Set item position to " .. string.format("%.3f", cursor_pos) .. " and length to " .. string.format("%.3f", duration))

  -- Create take and set source
  local take = r.AddTakeToMediaItem(item)
  if take then
    local src = r.PCM_Source_CreateFromFile(sample.path)
    if src then
      local retval = r.SetMediaItemTake_Source(take, src)
      log("SetMediaItemTake_Source result: " .. tostring(retval))

      -- Verify the source was set
      local take_src = r.GetMediaItemTake_Source(take)
      if take_src then
        log("Take source successfully set")
      else
        log("WARNING: Take source not set properly")
      end

      -- Name the item after the filename (with debug)
      set_item_name(item, take, sample.path)

      log("Inserted sample '" .. sample.name .. "' at position " .. string.format("%.3f", cursor_pos))

      -- Build peaks for the newly created item
      rebuild_peaks_for_item(item)

      -- Update arrange view and allow UI refresh
      r.UpdateArrange()
      r.PreventUIRefresh(-1)

      return true
    else
      log("Failed to create PCM source for: " .. sample.path)
      r.PreventUIRefresh(-1)
      return false
    end
  else
    log("Failed to create take for media item")
    r.PreventUIRefresh(-1)
    return false
  end
end

-- Get the drop position from mouse cursor context (using SWS extension)
local function get_drop_position()
  if not r.BR_GetMouseCursorContext then
    log("SWS functions not available; cannot get mouse position")
    return nil, nil
  end

  -- Refresh mouse context; returns window/segment/details strings
  local window, segment, details = r.BR_GetMouseCursorContext()

  -- Only proceed when mouse is over arrange view (window == "arrange")
  if window == "arrange" then
    local time_pos = r.BR_GetMouseCursorContext_Position()
    local track = r.BR_GetMouseCursorContext_Track()
    if time_pos then
      return time_pos, track
    end
  end

  -- No position available (mouse not over arrange)
  return nil, nil
end

-- Insert sample at specific position and track
local function insert_sample_at_position(sample, time_pos, target_track)
  if not sample or not sample.path then
    log("No sample to insert")
    return false
  end

  -- Check if file exists
  if not r.file_exists(sample.path) then
    log("Sample file does not exist: " .. sample.path)
    return false
  end

  -- Prevent UI refresh during operations
  r.PreventUIRefresh(1)

  -- Use target track if provided, otherwise fallback to selected/first track
  local track = target_track
  if not track then
    track = r.GetSelectedTrack(0, 0)
    if not track then
      local num_tracks = r.CountTracks(0)
      if num_tracks > 0 then
        track = r.GetTrack(0, 0)
      end
    end
  end

  if not track then
    log("No track available for inserting sample")
    r.PreventUIRefresh(-1)
    return false
  end

  -- Get track info for debugging
  local _, track_name = r.GetTrackName(track)
  log("Using track: " .. (track_name or "unnamed"))

  -- Create media item
  local item = r.AddMediaItemToTrack(track)
  if not item then
    log("Failed to create media item")
    r.PreventUIRefresh(-1)
    return false
  end

  -- Set item position and length
  r.SetMediaItemPosition(item, time_pos, false)
  local duration = sample.duration or 1.0
  r.SetMediaItemLength(item, duration, false)
  log("Set item position to " .. string.format("%.3f", time_pos) .. " and length to " .. string.format("%.3f", duration))

  -- Create take and set source
  local take = r.AddTakeToMediaItem(item)
  if take then
    local src = r.PCM_Source_CreateFromFile(sample.path)
    if src then
      local retval = r.SetMediaItemTake_Source(take, src)
      log("SetMediaItemTake_Source result: " .. tostring(retval))

      -- Verify the source was set
      local take_src = r.GetMediaItemTake_Source(take)
      if take_src then
        log("Take source successfully set")
      else
        log("WARNING: Take source not set properly")
      end

      -- Name the item after the filename (with debug)
      set_item_name(item, take, sample.path)

      log("Inserted sample '" .. sample.name .. "' at position " .. string.format("%.3f", time_pos))

      -- Build peaks for the newly created item
      rebuild_peaks_for_item(item)

      -- Update arrange view and allow UI refresh
      r.UpdateArrange()
      r.PreventUIRefresh(-1)

      return true
    else
      log("Failed to create PCM source for: " .. sample.path)
      r.PreventUIRefresh(-1)
      return false
    end
  else
    log("Failed to create take for media item")
    r.PreventUIRefresh(-1)
    return false
  end
end

local function render_waveform()
  -- Always show waveform area if a sample is selected/previewing
  if not preview_sample_obj then
    -- Show placeholder message when no sample is selected
    r.ImGui_Text(ctx, "(No sample selected)")
    r.ImGui_Separator(ctx)
    return
  end
  
  -- If waveform_data doesn't exist, try to generate it
  if not waveform_data or waveform_data.sample_path ~= preview_sample_obj.path then
    log("Waveform data missing, generating...")
    waveform_data = generate_waveform(preview_sample_obj)
    if waveform_data then
      waveform_data.sample_path = preview_sample_obj.path
    else
      -- Create placeholder if generation fails
      log("Creating placeholder waveform")
      local channels = preview_sample_obj.channels or 2
      waveform_data = {
        data = {},
        duration = preview_sample_obj.duration or 1.0,
        sample_rate = preview_sample_obj.samplerate or 44100,
        channels = channels,
        sample_path = preview_sample_obj.path,
        frequency_data = {},  -- Empty frequency data (will show gray)
        frequency_channel_data = nil
      }
      if channels > 1 then
        -- Multi-channel: create channel_data structure
        waveform_data.channel_data = {}
        waveform_data.frequency_channel_data = {}
        for c = 0, channels - 1 do
          waveform_data.channel_data[c] = {}
          waveform_data.frequency_channel_data[c] = {}
          for i = 1, waveform_width do
            waveform_data.channel_data[c][i] = 0.1
            waveform_data.frequency_channel_data[c][i] = nil  -- No frequency data
          end
        end
        -- Also set data for backward compatibility (use first channel)
        waveform_data.data = waveform_data.channel_data[0]
        waveform_data.frequency_data = waveform_data.frequency_channel_data[0]
      else
        -- Mono: just fill data array
        for i = 1, waveform_width do
          waveform_data.data[i] = 0.1
          waveform_data.frequency_data[i] = nil  -- No frequency data
        end
      end
    end
  end
  
  if not waveform_data then
    return
  end
  
  local avail_x = r.ImGui_GetContentRegionAvail(ctx)
  local width = avail_x
  local height = 80
  
  -- Render path as clickable folder buttons
  
  local full_path = preview_sample_obj.path or ""
  if full_path ~= "" then
    -- Find which scanned folder contains this sample
    local normalized_path = normalize_path(full_path)
    local scanned_root = nil
    
    -- Find the longest matching scanned folder (most specific match)
    for _, scanned_folder in ipairs(state.folders) do
      local norm_scanned = normalize_path(scanned_folder)
      -- Check if the sample path starts with this scanned folder
      if normalized_path:sub(1, #norm_scanned) == norm_scanned then
        if not scanned_root or #norm_scanned > #scanned_root then
          scanned_root = norm_scanned
        end
      end
    end
    
    -- Extract directory path (remove filename)
    local dir_path = normalized_path:match("(.+)/[^/]+$") or ""
    
    -- If we found a scanned root, only show path segments from that root onward
    local path_segments = {}
    if scanned_root and dir_path ~= "" then
      -- Always add the scanned root as the first segment
      local root_name = scanned_root:match("([^/]+)/?$") or scanned_root
      table.insert(path_segments, {name = root_name, path = scanned_root})
      
      -- Remove the scanned root from the path to get relative path
      local relative_path = dir_path
      if dir_path:sub(1, #scanned_root) == scanned_root then
        relative_path = dir_path:sub(#scanned_root + 1)
        -- Remove leading slash if present
        if relative_path:sub(1, 1) == "/" then
          relative_path = relative_path:sub(2)
        end
      end
      
      -- Build path segments for subfolders
      if relative_path ~= "" then
        local current_path = scanned_root
        for segment in relative_path:gmatch("([^/]+)") do
          current_path = current_path .. "/" .. segment
          table.insert(path_segments, {name = segment, path = current_path})
        end
      end
    elseif dir_path ~= "" then
      -- Fallback: show full path if no scanned root found (shouldn't happen normally)
      local is_absolute = dir_path:sub(1, 1) == "/"
      local current_path = is_absolute and "/" or ""
      for segment in dir_path:gmatch("([^/]+)") do
        if is_absolute then
          current_path = current_path .. segment
        else
          current_path = current_path .. (current_path == "" and "" or "/") .. segment
        end
        table.insert(path_segments, {name = segment, path = current_path})
        if is_absolute then
          current_path = current_path .. "/"
        end
      end
    end
    
    -- Render each segment as a button with improved styling
    for i, seg in ipairs(path_segments) do
      if i > 1 then
        r.ImGui_SameLine(ctx)
        -- Use a subtle separator (RRGGBBAA format)
        r.ImGui_TextColored(ctx, 0x666666FF, " / ")
        r.ImGui_SameLine(ctx)
      end
      
      -- Highlight if this path is currently filtered
      local is_filtered = state.folder_filter_path and normalize_path(state.folder_filter_path) == normalize_path(seg.path)
      
      -- Enhanced button styling with transparent fill and solid outline
      local button_bg_color, border_color
      if is_filtered then
        -- Active/filtered state: blue with less transparency (25% opacity = 0x40 alpha)
        button_bg_color = 0x2D5A8F40  -- Blue, 25% opacity
        border_color = 0x3D7ABFFF     -- Solid blue border
      else
        -- Default state: gray with 90% transparency (10% opacity = 0x1A alpha)
        button_bg_color = 0x2A2A2A1A  -- Gray, 10% opacity
        border_color = 0x666666FF     -- Solid gray border
      end
      
      -- Calculate button size
      local text_size = {r.ImGui_CalcTextSize(ctx, seg.name)}
      local frame_padding = 4.0
      local button_width = text_size[1] + frame_padding * 2
      local button_height = text_size[2] + 4.0
      
      -- Create invisible button for input handling
      local clicked = r.ImGui_InvisibleButton(ctx, "##path_btn_" .. seg.name, button_width, button_height)
      local is_hovered = r.ImGui_IsItemHovered(ctx)
      
      -- Adjust border color on hover
      if is_hovered then
        if is_filtered then
          border_color = 0x4D8ACFFF  -- Brighter blue border on hover
        else
          border_color = 0x888888FF  -- Brighter gray border on hover
        end
      end
      
      -- Get button rect
      local rect_min = {r.ImGui_GetItemRectMin(ctx)}
      local rect_max = {r.ImGui_GetItemRectMax(ctx)}
      
      -- Draw custom button background and border
      local dl = r.ImGui_GetWindowDrawList(ctx)
      r.ImGui_DrawList_AddRectFilled(dl, rect_min[1], rect_min[2], rect_max[1], rect_max[2], button_bg_color, 3.0)
      r.ImGui_DrawList_AddRect(dl, rect_min[1], rect_min[2], rect_max[1], rect_max[2], border_color, 3.0, 0, 1.5)
      
      -- Draw text centered in button (white color, bold when filtered)
      local text_pos_x = rect_min[1] + frame_padding
      local text_pos_y = rect_min[2] + (button_height - text_size[2]) * 0.5
      if is_filtered then
        -- Draw text multiple times with small offsets to create bold effect
        r.ImGui_DrawList_AddText(dl, text_pos_x, text_pos_y, 0xFFFFFFFF, seg.name)
        r.ImGui_DrawList_AddText(dl, text_pos_x + 0.5, text_pos_y, 0xFFFFFFFF, seg.name)
        r.ImGui_DrawList_AddText(dl, text_pos_x, text_pos_y + 0.5, 0xFFFFFFFF, seg.name)
        r.ImGui_DrawList_AddText(dl, text_pos_x + 0.5, text_pos_y + 0.5, 0xFFFFFFFF, seg.name)
      else
        r.ImGui_DrawList_AddText(dl, text_pos_x, text_pos_y, 0xFFFFFFFF, seg.name)
      end
      
      -- Handle click
      if clicked then
        -- Toggle filter: if already filtered, clear it; otherwise set it
        if is_filtered then
          state.folder_filter_path = nil
        else
          state.folder_filter_path = seg.path
        end
      end
    end
    
    -- Show filename (not clickable)
    if #path_segments > 0 then
      r.ImGui_SameLine(ctx)
      r.ImGui_Text(ctx, " / ")
      r.ImGui_SameLine(ctx)
    end
    r.ImGui_TextColored(ctx, 0xFFCCCCCC, preview_sample_obj.name or "Unknown")
    
    -- Add a clear filter button if filter is active
    if state.folder_filter_path and state.folder_filter_path ~= "" then
      r.ImGui_SameLine(ctx)
      if r.ImGui_SmallButton(ctx, "[Clear Folder Filter]") then
        state.folder_filter_path = nil
      end
    end
  else
    r.ImGui_Text(ctx, preview_sample_obj.name or "Unknown")
  end
  
  r.ImGui_Separator(ctx)
  
  local pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
  local x0, y0 = pos_x, pos_y
  
  -- Create invisible button for click detection
  r.ImGui_InvisibleButton(ctx, "waveform_area", width, height)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local left_down = r.ImGui_IsMouseDown(ctx, 0)
  local left_released = r.ImGui_IsMouseReleased(ctx, 0)
  local dl = r.ImGui_GetWindowDrawList(ctx)

  -- Handle waveform drag to arrange window and double-click to insert
  local double_clicked = r.ImGui_IsMouseDoubleClicked(ctx, 0)

  -- Double-click to insert sample immediately
  if hovered and double_clicked and preview_sample_obj then
    log("Double-clicked waveform, inserting sample...")
    local success = insert_sample_at_cursor(preview_sample_obj)
    if success then
      log("Successfully inserted sample via double-click")
    else
      log("Failed to insert sample via double-click")
    end
    return
  end

  -- Simple drag and drop: click to start, release anywhere to drop
  if hovered and clicked and preview_sample_obj then
    -- Start dragging immediately on click
    log("Starting drag operation for sample: " .. preview_sample_obj.name)
    -- Set a flag to indicate we're in a drag operation
    state.pending_waveform_drop = preview_sample_obj
    -- Don't return here - let the drag continue
  end

  -- Show drag cursor while dragging and track mouse position
  if state.pending_waveform_drop then
    if hovered then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
    end

    -- Continuously track mouse position during drag
    local time_pos, track = get_drop_position()
    if time_pos then
      state.last_mouse_time_pos = time_pos
      state.last_mouse_track = track
    end
  end
  
  -- Draw waveform background
  local bg_color = 0x1A1A1AFF
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + width, y0 + height, bg_color, 0)
  
  -- Draw waveform
  local waveform = waveform_data.data
  if not waveform or #waveform == 0 then
    -- Show message if no waveform data
    r.ImGui_DrawList_AddText(dl, x0 + width * 0.5 - 50, y0 + height * 0.5, 0xFFFFFFFF, "No waveform data")
    r.ImGui_Dummy(ctx, 0, height)
    r.ImGui_Separator(ctx)
    return
  end
  
  if waveform and #waveform > 0 then
    local channels = waveform_data.channels or 1
    local channel_data = waveform_data.channel_data
    local frequency_data = waveform_data.frequency_data
    local frequency_channel_data = waveform_data.frequency_channel_data
    
    -- For mono: draw centered waveform (backward compatible)
    -- For stereo+: draw separate waveforms per channel
    if channels == 1 or not channel_data then
      -- Mono waveform: centered display
      local center_y = y0 + height * 0.5
      local half_height = height * 0.4
      
      -- Draw center line
      r.ImGui_DrawList_AddLine(dl, x0, center_y, x0 + width, center_y, 0x444444FF, 1.0)
      
      -- Draw waveform
      local step = width / #waveform
      local prev_x = x0
      local prev_y_top = center_y
      local prev_y_bot = center_y
      local prev_color = nil
      
      for i = 1, #waveform do
        local x = x0 + (i - 1) * step
        local value = waveform[i] or 0.0
        local y_top = center_y - value * half_height
        local y_bot = center_y + value * half_height
        
        -- Get frequency-based color for this pixel
        local freq = frequency_data and frequency_data[i]
        local color = frequency_to_color(freq)
        
        -- Draw vertical line for this sample
        r.ImGui_DrawList_AddLine(dl, x, y_top, x, y_bot, color, 1.5)
        
        -- Draw connecting line to previous sample (use average color for smooth transition)
        if i > 1 then
          local prev_freq = frequency_data and frequency_data[i - 1]
          local prev_color_val = frequency_to_color(prev_freq)
          -- Blend colors for smooth transition
          local avg_color = color
          if prev_color_val ~= color then
            -- Simple average of RGB components
            local r1 = (color >> 16) & 0xFF
            local g1 = (color >> 8) & 0xFF
            local b1 = color & 0xFF
            local r2 = (prev_color_val >> 16) & 0xFF
            local g2 = (prev_color_val >> 8) & 0xFF
            local b2 = prev_color_val & 0xFF
            local r_avg = math.floor((r1 + r2) / 2)
            local g_avg = math.floor((g1 + g2) / 2)
            local b_avg = math.floor((b1 + b2) / 2)
            avg_color = (0xFF << 24) | (r_avg << 16) | (g_avg << 8) | b_avg
          end
          r.ImGui_DrawList_AddLine(dl, prev_x, prev_y_top, x, y_top, avg_color, 1.0)
          r.ImGui_DrawList_AddLine(dl, prev_x, prev_y_bot, x, y_bot, avg_color, 1.0)
        end
        
        prev_x = x
        prev_y_top = y_top
        prev_y_bot = y_bot
        prev_color = color
      end
    else
      -- Multi-channel waveform: draw separate waveforms per channel
      -- For stereo: left channel on top half, right channel on bottom half
      local channel_height = height / channels
      
      for ch = 0, channels - 1 do
        local ch_data = channel_data[ch]
        local ch_freq_data = frequency_channel_data and frequency_channel_data[ch]
        if ch_data and #ch_data > 0 then
          -- Calculate channel-specific parameters
          local ch_y0 = y0 + ch * channel_height
          local ch_y1 = y0 + (ch + 1) * channel_height
          local ch_center_y = (ch_y0 + ch_y1) * 0.5
          local ch_half_height = channel_height * 0.4
          
          -- Draw center line for this channel
          r.ImGui_DrawList_AddLine(dl, x0, ch_center_y, x0 + width, ch_center_y, 0x444444FF, 1.0)
          
          -- Draw channel label (use a neutral color for label)
          local label_color = 0xCCCCCCFF
          local label = (ch == 0 and "L") or (ch == 1 and "R") or ("Ch" .. (ch + 1))
          r.ImGui_DrawList_AddText(dl, x0 + 5, ch_y0 + 2, label_color, label)
          
          -- Draw waveform for this channel
          local step = width / #ch_data
          local prev_x = x0
          local prev_y_top = ch_center_y
          local prev_y_bot = ch_center_y
          
          for i = 1, #ch_data do
            local x = x0 + (i - 1) * step
            local value = ch_data[i] or 0.0
            local y_top = ch_center_y - value * ch_half_height
            local y_bot = ch_center_y + value * ch_half_height
            
            -- Get frequency-based color for this pixel/channel
            local freq = ch_freq_data and ch_freq_data[i]
            local color = frequency_to_color(freq)
            
            -- Draw vertical line for this sample
            r.ImGui_DrawList_AddLine(dl, x, y_top, x, y_bot, color, 1.5)
            
            -- Draw connecting line to previous sample (use average color for smooth transition)
            if i > 1 then
              local prev_freq = ch_freq_data and ch_freq_data[i - 1]
              local prev_color_val = frequency_to_color(prev_freq)
              -- Blend colors for smooth transition
              local avg_color = color
              if prev_color_val ~= color then
                -- Simple average of RGB components
                local r1 = (color >> 16) & 0xFF
                local g1 = (color >> 8) & 0xFF
                local b1 = color & 0xFF
                local r2 = (prev_color_val >> 16) & 0xFF
                local g2 = (prev_color_val >> 8) & 0xFF
                local b2 = prev_color_val & 0xFF
                local r_avg = math.floor((r1 + r2) / 2)
                local g_avg = math.floor((g1 + g2) / 2)
                local b_avg = math.floor((b1 + b2) / 2)
                avg_color = (0xFF << 24) | (r_avg << 16) | (g_avg << 8) | b_avg
              end
              r.ImGui_DrawList_AddLine(dl, prev_x, prev_y_top, x, y_top, avg_color, 1.0)
              r.ImGui_DrawList_AddLine(dl, prev_x, prev_y_bot, x, y_bot, avg_color, 1.0)
            end
            
            prev_x = x
            prev_y_top = y_top
            prev_y_bot = y_bot
          end
          
          -- Draw separator line between channels (except after last channel)
          if ch < channels - 1 then
            r.ImGui_DrawList_AddLine(dl, x0, ch_y1, x0 + width, ch_y1, 0x333333FF, 1.0)
          end
        end
      end
    end
    
    -- Draw snap offset marker if available
    if preview_sample_obj then
    end
    if preview_sample_obj and preview_sample_obj.snap_offset then
      local snap_time = preview_sample_obj.snap_offset
      local duration = waveform_data.duration or preview_sample_obj.duration or 1.0
      if duration > 0 and snap_time >= 0 and snap_time <= duration then
        local snap_x = x0 + (snap_time / duration) * width
        snap_x = math.max(x0, math.min(x0 + width, snap_x))
        
        -- Draw snap offset line (bright yellow/green, distinct from playhead)
        local snap_color = 0x00FFFFFF  -- Cyan (RRGGBBAA format)
        local snap_thickness = 2.5
        r.ImGui_DrawList_AddLine(dl, snap_x, y0, snap_x, y0 + height, snap_color, snap_thickness)
        
        -- Draw snap offset indicators at top and bottom (triangles pointing down/up)
        local triangle_size = 6.0
        -- Top triangle (pointing down)
        r.ImGui_DrawList_AddTriangleFilled(dl, 
          snap_x, y0, 
          snap_x - triangle_size, y0 + triangle_size, 
          snap_x + triangle_size, y0 + triangle_size, 
          snap_color)
        -- Bottom triangle (pointing up)
        r.ImGui_DrawList_AddTriangleFilled(dl, 
          snap_x, y0 + height, 
          snap_x - triangle_size, y0 + height - triangle_size, 
          snap_x + triangle_size, y0 + height - triangle_size, 
          snap_color)
      end
    end
    
    -- Draw playhead (only when preview is actively playing)
    local current_pos = get_preview_position()
    local duration = waveform_data.duration or 1.0
    if current_pos ~= nil and duration > 0 and current_pos >= 0 then
      local playhead_x = x0 + (current_pos / duration) * width
      playhead_x = math.max(x0, math.min(x0 + width, playhead_x))
      
      -- Draw playhead line (bright yellow, thicker for visibility)
      local playhead_color = 0xFFFF88FF  -- Yellow (RRGGBBAA format)
      local playhead_thickness = 2.0
      r.ImGui_DrawList_AddLine(dl, playhead_x, y0, playhead_x, y0 + height, playhead_color, playhead_thickness)
      
      -- Draw playhead indicators at top and bottom (filled circles for better visibility)
      local indicator_radius = 5.0
      r.ImGui_DrawList_AddCircleFilled(dl, playhead_x, y0, indicator_radius, playhead_color, 16)
    end
  end
  
  -- Handle click to seek
  if clicked then
    local mx, my = r.ImGui_GetMousePos(ctx)
    local rel_x = mx - x0
    local normalized_pos = math.max(0.0, math.min(1.0, rel_x / width))
    local duration = waveform_data.duration or preview_sample_obj.duration or 0.0
    local seek_time = normalized_pos * duration
    
    log(string.format("Waveform click: mx=%.1f, x0=%.1f, rel_x=%.1f, width=%.1f, normalized=%.3f, duration=%.2f, seek_time=%.2fs", 
        mx, x0, rel_x, width, normalized_pos, duration, seek_time))
    preview_sample(preview_sample_obj, seek_time)
  end
  
  r.ImGui_Separator(ctx)
  
  -- Display tags for the current sample below the waveform
  if preview_sample_obj and preview_sample_obj.tags and type(preview_sample_obj.tags) == "table" and #preview_sample_obj.tags > 0 then
    for idx, tag in ipairs(preview_sample_obj.tags) do
      if idx > 1 then
        r.ImGui_SameLine(ctx)
      end
      
      local active = state.active_tags[tag] or false
      
      -- Use the same tag button drawing function for consistency
      -- Use unique ID prefix "waveform_" to avoid conflicts with tag bar buttons
      if draw_tag_button(ctx, tag, active, tag, "waveform_") then
        -- Check if alt key is pressed (for deletion)
        local alt_pressed = false
        if r.ImGui_IsKeyDown and r.ImGui_Key_LeftAlt and r.ImGui_Key_RightAlt then
          alt_pressed = r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftAlt()) or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightAlt())
        end
        
        if alt_pressed then
          -- Alt-click: delete tag from sample
          log("Deleting tag '" .. tag .. "' from sample: " .. preview_sample_obj.name)
          
          -- Find and remove the tag from the sample's tags array
          local new_tags = {}
          for _, t in ipairs(preview_sample_obj.tags) do
            if t ~= tag then
              table.insert(new_tags, t)
            end
          end
          preview_sample_obj.tags = new_tags
          
          -- Update the sample in state.samples array
          for _, s in ipairs(state.samples) do
            if s.path == preview_sample_obj.path then
              s.tags = new_tags
              break
            end
          end
          
          -- Rebuild tag index and save
          rebuild_tag_index()
          save_samples()
          
          log("Tag deleted. Remaining tags: " .. table.concat(new_tags, ", "))
        else
          -- Left-click: toggle tag filter (same as tag bar behavior)
          if active then
            state.active_tags[tag] = nil
          else
            state.active_tags[tag] = true
          end
        end
      end
    end
  else
    -- Show message if no tags
    r.ImGui_TextColored(ctx, 0xFF888888, "No tags")
  end
end


local function render_header()
  -- Add settings button in top right
  -- Get available content region width to calculate button position
  local avail_x, avail_y = r.ImGui_GetContentRegionAvail(ctx)
  local button_width = 100
  local spacing = 10
  -- Calculate position: available width - button width - spacing
  -- (cursor starts at 0, so we use available width directly)
  local button_x = avail_x - button_width - spacing
  r.ImGui_SetCursorPosX(ctx, button_x)
  if r.ImGui_Button(ctx, "Settings") then
    state.settings_open = not state.settings_open
  end
  
  -- Reset cursor for main content (start of next line)
  r.ImGui_SetCursorPosX(ctx, 0)
  
  if r.ImGui_Button(ctx, "Rescan") then
    enqueue_scan()
    log("Manual rescan triggered")
  end
  
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Clear") then
    state.folders = {}
    filter_samples_by_folders()  -- This will clear samples and tag data
    state.scan_queue = {}
    clear_sample_cache()
    save_config()
    log("Cleared folders and samples")
  end
  
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Copy Scan Logs") then
    local logs_text = get_scan_logs_text()
    if logs_text and logs_text ~= "" then
      r.ImGui_SetClipboardText(ctx, logs_text)
      log("Scan logs copied to clipboard (" .. tostring(#state.scan_logs) .. " entries)")
    else
      log("No scan logs to copy")
    end
  end
  
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Debug Coords") then
    log("=== DEBUG: Sample Coordinates ===")
    log("Total samples: " .. #state.samples)
    if #state.samples > 0 then
      -- Find min/max for both axes
      local x_min, x_max = state.samples[1].x or 0.5, state.samples[1].x or 0.5
      local y_min, y_max = state.samples[1].y or 0.5, state.samples[1].y or 0.5
      local freq_min, freq_max = state.samples[1].dominant_freq or 440.0, state.samples[1].dominant_freq or 440.0
      
      local rms_min, rms_max = state.samples[1].rms_energy or 0.0, state.samples[1].rms_energy or 0.0
      local size_min, size_max = state.samples[1].file_size or 0, state.samples[1].file_size or 0
      for i, s in ipairs(state.samples) do
        local x = s.x or 0.5
        local y = s.y or 0.5
        local freq = s.dominant_freq or 440.0
        local rms = s.rms_energy or 0.0
        local size = s.file_size or 0
        log(string.format("Sample %d: name='%s', freq=%.1f Hz, rms=%.6f, size=%d bytes, x=%.6f, y=%.6f", 
            i, s.name or "unknown", freq, rms, size, x, y))
        x_min = math.min(x_min, x)
        x_max = math.max(x_max, x)
        y_min = math.min(y_min, y)
        y_max = math.max(y_max, y)
        freq_min = math.min(freq_min, freq)
        freq_max = math.max(freq_max, freq)
        rms_min = math.min(rms_min, rms)
        rms_max = math.max(rms_max, rms)
        size_min = math.min(size_min, size)
        size_max = math.max(size_max, size)
      end
      
      log("--- Summary ---")
      log(string.format("X range: %.6f to %.6f (span: %.6f)", x_min, x_max, x_max - x_min))
      log(string.format("Y range: %.6f to %.6f (span: %.6f)", y_min, y_max, y_max - y_min))
      log(string.format("Frequency range: %.1f Hz to %.1f Hz", freq_min, freq_max))
      log(string.format("RMS range: %.6f to %.6f", rms_min, rms_max))
      log(string.format("File size range: %d to %d bytes", size_min, size_max))
    else
      log("No samples to debug")
    end
    log("=== End Debug ===")
  end
  
  r.ImGui_SameLine(ctx)
  local ret, input = r.ImGui_InputText(ctx, "Filter", state.filter, 256)
  if ret then
    state.filter = input
  end
  
  render_tag_filters()
  
  r.ImGui_Separator(ctx)
end


local function render_settings()
  if not state.settings_open then
    return
  end
  
  r.ImGui_SetNextWindowSize(ctx, 600, 600, r.ImGui_Cond_FirstUseEver())
  local visible, open = r.ImGui_Begin(ctx, "Settings", true, r.ImGui_WindowFlags_None())
  
  if visible then
    r.ImGui_Text(ctx, "Scan Folders")
    r.ImGui_Separator(ctx)
    
    if r.ImGui_Button(ctx, "Add Folder") then
      local new_folder = ""
      
      -- Try JS_Dialog_BrowseForFolder first (from JS_ReaScriptAPI extension)
      if r.APIExists("JS_Dialog_BrowseForFolder") then
        -- JS_Dialog_BrowseForFolder returns (retval, selectedFolder)
        -- retval: 1 = OK, 0 = cancelled
        -- selectedFolder: the path string
        local retval, selectedFolder = r.JS_Dialog_BrowseForFolder("Choose folder to scan", "")
        if retval == 1 and selectedFolder and selectedFolder ~= "" then
          new_folder = selectedFolder
          log("JS_Dialog_BrowseForFolder returned: " .. tostring(selectedFolder))
        else
          log("JS_Dialog_BrowseForFolder cancelled or failed. retval=" .. tostring(retval))
        end
      else
        log("JS_Dialog_BrowseForFolder not available - JS_ReaScriptAPI extension may not be installed")
      end
      
      -- Only show fallback dialog if JS dialog didn't work
      if new_folder == "" and not r.APIExists("JS_Dialog_BrowseForFolder") then
        r.ShowMessageBox("JS_ReaScriptAPI extension is required for folder browsing.\n\nPlease install it via ReaPack:\nExtensions > ReaPack > Browse Packages > Search for 'js_ReaScriptAPI'", "Extension Required", 0)
      end
      
      -- Normalize and validate folder path before adding
      if new_folder and new_folder ~= "" then
        new_folder = normalize_path(new_folder)
        
        -- Check if it's a valid path (not just a number or single character)
        if string.len(new_folder) < 2 or new_folder:match("^%d+$") then
          r.ShowMessageBox("Invalid folder path: " .. new_folder .. "\n\nPlease select a valid folder.", "Error", 0)
          log("Rejected invalid folder path: " .. new_folder)
        else
          -- Check if folder already exists in list
          local exists = false
          for _, f in ipairs(state.folders) do
            if f == new_folder then
              exists = true
              break
            end
          end
          if not exists then
            table.insert(state.folders, new_folder)
            save_config()
            log("Added folder: " .. new_folder)
            log("Folder path length: " .. string.len(new_folder))
          else
            log("Folder already in list: " .. new_folder)
          end
        end
      end
    end
    
    r.ImGui_Separator(ctx)
    
    if #state.folders > 0 then
      r.ImGui_Text(ctx, "Folders:")
      -- Use ChildFlags_Border constant if available, otherwise use 0 (no border)
      -- In ReaImGui, child flags may be accessed differently, so we check if it exists
      local child_flags = 0
      if r.ImGui_ChildFlags_Border then
        child_flags = r.ImGui_ChildFlags_Border
      end
      if r.ImGui_BeginChild(ctx, "folder_list", 0, 0, child_flags) then
        for idx, folder in ipairs(state.folders) do
          r.ImGui_BulletText(ctx, folder)
          r.ImGui_SameLine(ctx)
          if r.ImGui_SmallButton(ctx, "Remove##" .. idx) then
            table.remove(state.folders, idx)
            filter_samples_by_folders()
            save_config()
            break
          end
        end
        r.ImGui_EndChild(ctx)
      end
    else
      r.ImGui_TextColored(ctx, 0xFF888888, "No folders yet. Click Add Folder to add scan folders.")
    end
    
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Dot Appearance")
    r.ImGui_Separator(ctx)
    
    -- Dot size
    local ret, dot_radius = r.ImGui_InputDouble(ctx, "Dot Radius", state.dot_radius, 0.1, 1.0, "%.1f")
    if ret then
      state.dot_radius = math.max(0.5, math.min(10.0, dot_radius))
      save_config()
    end
    
    -- Outline size
    local ret2, outline_size = r.ImGui_InputDouble(ctx, "Outline Size", state.dot_outline_size, 0.1, 1.0, "%.1f")
    if ret2 then
      state.dot_outline_size = math.max(0.0, math.min(20.0, outline_size))
      save_config()
    end
    
    -- Outline thickness
    local ret3, outline_thickness = r.ImGui_InputDouble(ctx, "Outline Thickness", state.dot_outline_thickness, 0.1, 1.0, "%.1f")
    if ret3 then
      state.dot_outline_thickness = math.max(0.5, math.min(10.0, outline_thickness))
      save_config()
    end
    
    -- Detection multiplier
    local ret4, detection_mult = r.ImGui_InputDouble(ctx, "Detection Size Multiplier", state.dot_detection_multiplier, 0.5, 2.0, "%.1f")
    if ret4 then
      state.dot_detection_multiplier = math.max(1.0, math.min(50.0, detection_mult))
      save_config()
    end
    
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Dot Color")
    
    -- Dot color using ColorEdit3 (RGB only)
    local dot_changed, dot_color_result = r.ImGui_ColorEdit3(ctx, "Dot Color", (state.dot_color or 0x44AA55) | 0xFF000000, 0)
    if dot_changed then
      state.dot_color = dot_color_result & 0xFFFFFF  -- Extract RGB part only
      save_config()
    end
    
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Outline Color")
    
    -- Outline color using ColorEdit3
    local outline_changed, outline_color_result = r.ImGui_ColorEdit3(ctx, "Outline Color", (state.dot_outline_color or 0xFF00FF) | 0xFF000000, 0)
    if outline_changed then
      state.dot_outline_color = outline_color_result & 0xFFFFFF  -- Extract RGB part only
      save_config()
    end
    
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Hover Color")
    
    -- Hover color using ColorEdit3
    local hover_changed, hover_color_result = r.ImGui_ColorEdit3(ctx, "Hover Color", (state.dot_hover_color or 0xC84D) | 0xFF000000, 0)
    if hover_changed then
      state.dot_hover_color = hover_color_result & 0xFFFFFF  -- Extract RGB part only
      save_config()
    end

    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Tag Colors")
    r.ImGui_Separator(ctx)

    -- Load tag presets
    local tag_presets = {}
    local function load_tag_presets()
      local preset_file = io.open(CONFIG_DIR .. "/tag_presets.lua", "r")
      if preset_file then
        local content = preset_file:read("*all")
        preset_file:close()
        local success, presets = pcall(load, content)
        if success and type(presets) == "function" then
          tag_presets = presets() or {}
        end
      end
    end
    load_tag_presets()

    -- Preset selector
    local preset_names = {}
    for name, _ in pairs(tag_presets) do
      table.insert(preset_names, name)
    end
    table.sort(preset_names)

    if #preset_names > 0 then
      r.ImGui_Text(ctx, "Presets:")
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Load Preset") then
        r.ImGui_OpenPopup(ctx, "select_tag_preset")
      end

      if r.ImGui_BeginPopup(ctx, "select_tag_preset") then
        for _, preset_name in ipairs(preset_names) do
          if r.ImGui_Selectable(ctx, preset_name) then
            local preset = tag_presets[preset_name]
            if preset then
              for tag, color in pairs(preset) do
                state.tag_colors[tag] = color
              end
              state.current_preset_name = preset_name  -- Track current preset
              save_config()
            end
          end
        end
        r.ImGui_EndPopup(ctx)
      end
      r.ImGui_SameLine(ctx)
      r.ImGui_Text(ctx, "|")
      r.ImGui_SameLine(ctx)
    end

    if r.ImGui_Button(ctx, "Save as Preset") then
      r.ImGui_OpenPopup(ctx, "save_tag_preset")
    end

    if r.ImGui_BeginPopup(ctx, "save_tag_preset") then
      r.ImGui_Text(ctx, "Preset Name:")
      local preset_name = ""
      local changed, new_name = r.ImGui_InputText(ctx, "##preset_name", preset_name, 0)
      if changed then
        preset_name = new_name
      end

      if r.ImGui_Button(ctx, "Save") and preset_name ~= "" then
        tag_presets[preset_name] = {}
        for tag, color in pairs(state.tag_colors) do
          tag_presets[preset_name][tag] = color
        end
        state.current_preset_name = preset_name  -- Track current preset

        -- Save presets back to file
        local preset_content = "return " .. serialize_table(tag_presets)
        local preset_file = io.open(CONFIG_DIR .. "/tag_presets.lua", "w")
        if preset_file then
          preset_file:write(preset_content)
          preset_file:close()
        end

        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_EndPopup(ctx)
    end

    r.ImGui_Separator(ctx)

    -- Create a sorted list of tags for consistent ordering
    local sorted_tags = {}
    for tag, _ in pairs(state.tag_colors) do
      table.insert(sorted_tags, tag)
    end
    table.sort(sorted_tags)

    -- Display color pickers for each tag
    for _, tag in ipairs(sorted_tags) do
      local tag_color = state.tag_colors[tag]
      local color_changed, new_color = r.ImGui_ColorEdit3(ctx, tag, tag_color | 0xFF000000, 0)
      if color_changed then
        state.tag_colors[tag] = new_color & 0xFFFFFF  -- Extract RGB part only
        save_config()
      end
    end
  end
  
  r.ImGui_End(ctx)
  
  -- Update settings_open state based on window open state
  if not open then
    state.settings_open = false
  end
end


local function render_map()
  local avail_x, avail_y = r.ImGui_GetContentRegionAvail(ctx)
  local width = math.max(640, avail_x)
  local height = math.max(320, avail_y)
  
  local pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
  local x0, y0 = pos_x, pos_y
  
  r.ImGui_InvisibleButton(ctx, "map_area", width, height)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  
  -- Handle mouse button states
  local mx, my = r.ImGui_GetMousePos(ctx)
  local right_clicked = r.ImGui_IsMouseClicked(ctx, 1)  -- Right mouse button
  local right_down = r.ImGui_IsMouseDown(ctx, 1)
  local right_released = r.ImGui_IsMouseReleased(ctx, 1)
  -- Note: left_clicked detection moved to sample selection logic to prevent double detection
  
  -- Handle right-click drag for panning
  if hovered and right_clicked then
    -- Start right drag
    state.is_dragging = true
    state.is_left_dragging = false  -- Cancel left drag if right drag starts
    state.drag_start_x = mx
    state.drag_start_y = my
    state.drag_start_pan_x = state.pan_x
    state.drag_start_pan_y = state.pan_y
  elseif state.is_dragging and right_down then
    -- Continue right drag
    local dx = mx - state.drag_start_x
    local dy = my - state.drag_start_y
    state.pan_x = state.drag_start_pan_x + dx
    state.pan_y = state.drag_start_pan_y + dy

    -- Clamp pan position to prevent excessive panning
    local max_pan = width * 0.5 * state.zoom  -- Allow panning up to half screen width at current zoom
    state.pan_x = math.max(-max_pan, math.min(max_pan, state.pan_x))
    
    -- Clamp pan_y to prevent going beyond frequency boundaries (Y axis: 0 = top/20kHz, 1 = bottom/20Hz)
    -- Top of screen (y0) should never show normalized Y < 0
    -- Bottom of screen (y0 + height) should never show normalized Y > 1
    -- Screen coordinate: py = center_y + (base_y - height * 0.5) * zoom
    -- Where center_y = y0 + height * 0.5 + pan_y and base_y = normalized_y * height
    -- For top boundary: y0 = center_y + (0 - height * 0.5) * zoom
    --   y0 = y0 + height * 0.5 + pan_y - height * 0.5 * zoom
    --   pan_y = height * 0.5 * (zoom - 1)  (most positive, allows panning down)
    -- For bottom boundary: y0 + height = center_y + (height - height * 0.5) * zoom
    --   y0 + height = y0 + height * 0.5 + pan_y + height * 0.5 * zoom
    --   pan_y = height * 0.5 * (1 - zoom)  (most negative, allows panning up)
    local min_pan_y = height * 0.5 * (1 - state.zoom)   -- Can't pan up beyond Y=0 (20kHz at top)
    local max_pan_y = height * 0.5 * (state.zoom - 1)   -- Can't pan down beyond Y=1 (20Hz at bottom)
    state.pan_y = math.max(min_pan_y, math.min(max_pan_y, state.pan_y))
    -- Don't save during drag - only save when drag ends
  elseif right_released then
    -- End right drag
    state.is_dragging = false
    state.drag_start_x = nil
    state.drag_start_y = nil
    -- Pan position not saved
  end
  
  -- Handle left-click drag for selecting samples
  local left_clicked = r.ImGui_IsMouseClicked(ctx, 0)  -- Left mouse button (detected here for drag logic)
  local left_down = r.ImGui_IsMouseDown(ctx, 0)
  local left_released = r.ImGui_IsMouseReleased(ctx, 0)

  if hovered and left_clicked and not state.is_dragging then
    -- Start left drag (only if not right-dragging)
    state.is_left_dragging = true
    state.last_dragged_sample_path = nil
  elseif left_released then
    -- End left drag
    state.is_left_dragging = false
    state.last_dragged_sample_path = nil
  end
  
  -- Handle mouse wheel zoom
  if hovered and not state.is_dragging then
    local wheel = r.ImGui_GetMouseWheel(ctx)
    if wheel ~= 0 then
      local zoom_speed = 0.1
      local old_zoom = state.zoom
      -- Clamp zoom to range: minimum 1.0 (normal zoom), maximum 3.0 (zoomed in)
      local new_zoom = math.max(1.0, math.min(3.0, state.zoom + wheel * zoom_speed))
      
      -- Calculate mouse position relative to map area center
      local mouse_rel_x = mx - (x0 + width * 0.5)
      local mouse_rel_y = my - (y0 + height * 0.5)
      
      -- Calculate what normalized map coordinate (0-1) the mouse is over
      -- Current transformation: px = center_x + (base_x - width/2) * zoom
      -- Where base_x = s.x * width (normalized coord * width)
      -- So: px = center_x + (s.x * width - width/2) * zoom
      --     px = center_x + width * (s.x - 0.5) * zoom
      -- Reverse: s.x = ((px - center_x) / (width * zoom)) + 0.5
      
      local center_x = x0 + width * 0.5 + state.pan_x
      local center_y = y0 + height * 0.5 + state.pan_y
      
      -- Find normalized map coordinate under mouse
      local map_norm_x = ((mx - center_x) / (width * old_zoom)) + 0.5
      local map_norm_y = ((my - center_y) / (height * old_zoom)) + 0.5
      
      -- Update zoom
      state.zoom = new_zoom
      
      -- Adjust pan so the same normalized map coordinate stays under the mouse
      -- After zoom: mx = new_center_x + width * (map_norm_x - 0.5) * new_zoom
      -- Solve: new_center_x = mx - width * (map_norm_x - 0.5) * new_zoom
      local new_center_x = mx - width * (map_norm_x - 0.5) * new_zoom
      local new_center_y = my - height * (map_norm_y - 0.5) * new_zoom
      
      -- Convert back to pan offset
      state.pan_x = new_center_x - (x0 + width * 0.5)
      state.pan_y = new_center_y - (y0 + height * 0.5)

      -- Clamp pan position to prevent excessive panning
      local max_pan = width * 0.5 * state.zoom  -- Allow panning up to half screen width at current zoom
      state.pan_x = math.max(-max_pan, math.min(max_pan, state.pan_x))
      
      -- Clamp pan_y to prevent going beyond frequency boundaries (Y axis: 0 = top/20kHz, 1 = bottom/20Hz)
      local min_pan_y = height * 0.5 * (1 - state.zoom)   -- Can't pan up beyond Y=0 (20kHz at top)
      local max_pan_y = height * 0.5 * (state.zoom - 1)   -- Can't pan down beyond Y=1 (20Hz at bottom)
      state.pan_y = math.max(min_pan_y, math.min(max_pan_y, state.pan_y))
      -- Don't save during zoom - config is saved on script exit and after drag ends
    end
  end
  
  local bg = 0x000000FF  -- Solid black background (RRGGBBAA format)
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + width, y0 + height, bg, 6)

  -- Padding for ruler text labels (left for frequency, top for time)
  local label_padding_left = 70  -- Space for frequency labels (e.g., "15.0kHz")
  local label_padding_top = 25   -- Space for time labels at top
  
  -- Calculate center point for zoom/pan (needed for grid and sample rendering)
  -- Use full area for grid, but padded area for samples
  local center_x = x0 + width * 0.5 + state.pan_x
  local center_y = y0 + height * 0.5 + state.pan_y
  
  -- Padded area for sample drawing (to avoid overlapping with labels)
  local padded_x0 = x0 + label_padding_left
  local padded_y0 = y0 + label_padding_top
  local padded_width = width - label_padding_left
  local padded_height = height - label_padding_top
  local padded_center_x = padded_x0 + padded_width * 0.5 + state.pan_x
  local padded_center_y = padded_y0 + padded_height * 0.5 + state.pan_y

  -- Draw grid lines for frequency (horizontal) and time (vertical)
  if #state.samples > 0 and state.samples[1].x then
    local log10 = math.log(10)
    
    -- Use theoretical frequency range (20Hz-20kHz) for consistent grid
    local freq_min_log = math.log(20.0) / log10
    local freq_max_log = math.log(20000.0) / log10
    
    -- Calculate duration range from samples for X-axis grid
    local len_min_log, len_max_log = nil, nil
    for _, s in ipairs(state.samples) do
      if s.duration then
        local len_log = math.log(math.max(s.duration, 0.01)) / log10
        if not len_min_log then
          len_min_log = len_log
          len_max_log = len_log
        else
          len_min_log = math.min(len_min_log, len_log)
          len_max_log = math.max(len_max_log, len_log)
        end
      end
    end
    
    -- Use reasonable defaults for duration if no samples
    if not len_min_log then
      len_min_log = math.log(0.01) / log10  -- 10ms
      len_max_log = math.log(60.0) / log10   -- 60 seconds
    end
    
    -- Subtle grid color (semi-transparent gray)
    local grid_color = 0x40404040  -- RRGGBBAA: gray with ~25% opacity
    local text_color = 0x80808080  -- RRGGBBAA: lighter gray with ~50% opacity for text
    
    -- Draw evenly spaced horizontal frequency grid lines
    -- Generate evenly spaced normalized Y positions (every 10% = 0.1)
    local num_freq_lines = 10  -- 10 evenly spaced lines
    for i = 0, num_freq_lines do
      local normalized_y = i / num_freq_lines  -- 0.0 to 1.0, evenly spaced
      
      -- Convert normalized Y back to frequency (inverse of layout transform)
      -- normalized_y = 1.0 - y_normalized, so y_normalized = 1.0 - normalized_y
      local y_normalized = 1.0 - normalized_y
      local freq_log = freq_min_log + y_normalized * (freq_max_log - freq_min_log)
      local freq_val = 10 ^ freq_log
      
      -- Convert normalized Y to screen coordinate (using padded area)
      local base_y = normalized_y * padded_height
      local py = padded_center_y + (base_y - padded_height * 0.5) * state.zoom
      
      -- Only draw if line is visible in viewport
      if py >= padded_y0 - 1 and py <= padded_y0 + padded_height + 1 then
        -- Draw line across padded area (from label padding to right edge)
        r.ImGui_DrawList_AddLine(dl, padded_x0, py, x0 + width, py, grid_color, 1.0)
        
        -- Round frequency to nice round number for display
        local function round_to_nice_freq(freq)
          if freq < 100.0 then
            -- Round to nearest 10 for frequencies below 100Hz
            return math.floor((freq + 5) / 10) * 10
          elseif freq < 500.0 then
            -- Round to nearest 20 for frequencies 100-500Hz
            return math.floor((freq + 10) / 20) * 20
          elseif freq < 1000.0 then
            -- Round to nearest 40 for frequencies 500-1000Hz
            return math.floor((freq + 20) / 40) * 40
          elseif freq < 5000.0 then
            -- Round to nearest 100 for frequencies 1-5kHz
            return math.floor((freq + 50) / 100) * 100
          else
            -- Round to nearest 200 for frequencies above 5kHz
            return math.floor((freq + 100) / 200) * 200
          end
        end
        
        local rounded_freq = round_to_nice_freq(freq_val)
        
        -- Add text label for frequency
        local freq_text
        if rounded_freq >= 1000.0 then
          freq_text = string.format("%.1fkHz", rounded_freq / 1000.0)
        else
          freq_text = string.format("%.0fHz", rounded_freq)
        end
        -- Draw text at left edge, slightly offset from line
        r.ImGui_DrawList_AddText(dl, x0 + 4, py - 7, text_color, freq_text)
      end
    end
    
    -- Draw vertical time/duration grid lines (seconds)
    -- Find reasonable time range from samples
    local duration_min, duration_max = nil, nil
    for _, s in ipairs(state.samples) do
      if s.duration then
        local dur = math.max(0.01, s.duration)
        if not duration_min then
          duration_min = dur
          duration_max = dur
        else
          duration_min = math.min(duration_min, dur)
          duration_max = math.max(duration_max, dur)
        end
      end
    end
    
    if duration_min and duration_max then
      -- Draw evenly spaced vertical time/duration grid lines
      -- Generate evenly spaced normalized X positions (every 10% = 0.1, accounting for 5% padding)
      local padding = 0.05
      local num_time_lines = 10  -- 10 evenly spaced lines
      for i = 0, num_time_lines do
        -- Map i from 0-num_time_lines to normalized_x accounting for padding
        local normalized_x = padding + (i / num_time_lines) * (1.0 - 2.0 * padding)
        
        -- Convert normalized X back to duration (inverse of layout transform)
        local len_log = len_min_log + ((normalized_x - padding) / (1.0 - 2.0 * padding)) * (len_max_log - len_min_log)
        local time_val = 10 ^ len_log
        
        -- Convert normalized X to screen coordinate (using padded area)
        local base_x = normalized_x * padded_width
        local px = padded_center_x + (base_x - padded_width * 0.5) * state.zoom
        
        -- Only draw if line is visible in viewport
        if px >= padded_x0 - 1 and px <= padded_x0 + padded_width + 1 then
          -- Draw line across padded area (from label padding to bottom edge)
          r.ImGui_DrawList_AddLine(dl, px, padded_y0, px, y0 + height, grid_color, 1.0)
          
          -- Add text label for time
          local time_text
          if time_val < 1.0 then
            time_text = string.format("%.1fs", time_val)
          elseif time_val < 10.0 then
            time_text = string.format("%.1fs", time_val)
          else
            time_text = string.format("%.0fs", time_val)
          end
          -- Draw text at top edge, slightly offset from line
          r.ImGui_DrawList_AddText(dl, px + 4, y0 + 4, text_color, time_text)
        end
      end
    end
  end

  -- Use customizable dot size
  local dot_radius = state.dot_radius or 2.0
  local clicked_sample = nil
  local hovered_samples = {}  -- Collect all hovered samples to handle overlaps
  local click_handled_this_frame = false  -- Prevent multiple preview triggers per frame
  
  -- Colors are in RGB format, convert to RRGGBBAA for rendering
  local dot_color = build_color_rrgbbaa(extract_rgb(state.dot_color or 0x44AA55))
  local outline_color = build_color_rrgbbaa(extract_rgb(state.dot_outline_color or 0xFF00FF))
  local hover_color = build_color_rrgbbaa(extract_rgb(state.dot_hover_color or 0xC84D))
  
  -- Debug: log sample count
  if #state.samples > 0 and not state.samples[1].x then
    log("WARNING: Samples found but not laid out yet. Count: " .. #state.samples)
  end
  
  for _, s in ipairs(state.samples) do
    if type(s) == "table" and sample_passes_filters(s) then
      -- Apply zoom and pan to coordinates (using padded area for sample drawing)
      -- Samples use normalized coordinates (0-1), map them to padded area to align with grid
      local base_x = (s.x or 0.5) * padded_width
      local base_y = (s.y or 0.5) * padded_height
      local px = padded_center_x + (base_x - padded_width * 0.5) * state.zoom
      local py = padded_center_y + (base_y - padded_height * 0.5) * state.zoom
      
      -- Only draw if visible
      local outline_size = state.dot_outline_size or 4.0
      local is_playing = preview_sample_obj and preview_sample_obj.path == s.path
      -- Account for selected dot being 5x larger plus glow effect
      local current_dot_radius = is_playing and (dot_radius * 5.0) or dot_radius
      local glow_expansion = is_playing and (current_dot_radius * 0.3) or 0.0  -- Max glow expansion
      local max_radius = math.max(current_dot_radius + glow_expansion, current_dot_radius + outline_size)
      -- Check visibility against padded area (samples are drawn in padded area to avoid label overlap)
      if px >= padded_x0 - max_radius and px <= padded_x0 + padded_width + max_radius and
         py >= padded_y0 - max_radius and py <= padded_y0 + padded_height + max_radius then
        -- Use tag-based color instead of global dot color
        local color = dot_color -- fallback color

        -- Find the primary tag for this sample (highest weight tag)
        if s.tags and type(s.tags) == "table" and #s.tags > 0 then
          local best_tag = nil
          local best_weight = 0
          for _, tag_name in ipairs(s.tags) do
            -- Find the weight for this tag from TAG_KEYWORDS
            for _, keyword_entry in ipairs(TAG_KEYWORDS) do
              if keyword_entry.tag == tag_name then
                if keyword_entry.weight > best_weight then
                  best_weight = keyword_entry.weight
                  best_tag = tag_name
                end
                break
              end
            end
          end

          -- Use the tag's color if found (convert RGB to RRGGBBAA)
          if best_tag and state.tag_colors[best_tag] then
            local tag_rgb = state.tag_colors[best_tag]
            local r, g, b = extract_rgb(tag_rgb)
            color = build_color_rrgbbaa(r, g, b, 255)
          end
        end

        -- Apply mono/stereo distinction to the tag color
        if s.channels == 1 then
          -- Mono: use lighter version (add 50% to each component, clamped to 255)
          local base_r, base_g, base_b = extract_rgb_rrgbbaa(color)
          local mono_r = math.min(255, math.floor(base_r * 1.5))
          local mono_g = math.min(255, math.floor(base_g * 1.5))
          local mono_b = math.min(255, math.floor(base_b * 1.5))
          -- Build color in RRGGBBAA format with full opacity
          color = build_color_rrgbbaa(mono_r, mono_g, mono_b, 255)
        end
        
        -- Draw outline for currently playing/chosen sample (bigger and more visible)
        if is_playing then
          -- Selected dot is 5x the normal size
          local selected_dot_radius = dot_radius * 2
          
          -- Continuous breathing glow effect - more prominent
          -- Reset breathing cycle when sample is clicked (breathing_start_time is set in preview_sample)
          if not state.breathing_start_time then
            state.breathing_start_time = r.time_precise()
          end
          local current_time = r.time_precise()
          -- Breathing cycle: 1.5 seconds per cycle (faster breathing)
          local breathing_speed = 1.5  -- seconds per full cycle
          local elapsed = current_time - state.breathing_start_time
          local breathing_phase = (elapsed % breathing_speed) / breathing_speed  -- 0 to 1
          
          -- More prominent breathing: larger amplitude (0.7 to 1.3 instead of 0.9 to 1.1)
          -- This creates a more noticeable pulsing effect
          local breathing_amplitude = 0.7 + 0.6 * (0.5 + 0.5 * math.sin(breathing_phase * 2.0 * math.pi))
          
          -- Add intensity spike when first clicked (decays over 0.4 seconds)
          local spike_duration = 0.4  -- seconds for spike to fade out
          local spike_factor = 0.0
          if elapsed < spike_duration then
            -- Exponential decay: starts at 1.0, fades to 0.0 over spike_duration
            local spike_progress = elapsed / spike_duration
            spike_factor = math.exp(-spike_progress * 4.0)  -- Fast exponential decay
            -- Scale spike intensity (adds up to 0.5x to the amplitude)
            spike_factor = spike_factor * 0.5
          end
          
          -- Combine breathing amplitude with spike
          local total_amplitude = breathing_amplitude + spike_factor
          
          -- Much larger glow radius: 4x the selected dot radius (was 30% expansion)
          local glow_inner = selected_dot_radius * 1.2  -- Start glow just outside the dot
          local glow_outer = selected_dot_radius * 4.0  -- Much larger outer radius
          
          -- Apply breathing + spike to glow size
          local breathing_glow_inner = glow_inner * total_amplitude
          local breathing_glow_outer = glow_outer * total_amplitude
          
          -- Brighten glow color (brighten dot's color while preserving hue)
          -- Use a brighter version of the dot's color for the outer glow
          local base_brightness = 0.3  -- Base brightness increase for normal glow
          local glow_color = brighten_color_preserve_hue(color, base_brightness)
          
          -- Further brighten during spike
          if spike_factor > 0.01 then
            -- Additional brightness during spike
            local spike_brightness = math.min(1.0, spike_factor * 2.0)  -- Scale spike_factor for brightness
            glow_color = brighten_color_preserve_hue(color, base_brightness + spike_brightness * 0.5)  -- Up to 80% total brightness
          end
          
          -- Draw glowing circle effect
          draw_glowing_circle(dl, px, py, breathing_glow_inner, breathing_glow_outer, 
                             selected_dot_radius, glow_color, color)
          
          -- Draw outline for selected dot (on top of glow)
          local outline_thickness = state.dot_outline_thickness or 3.0
          r.ImGui_DrawList_AddCircle(dl, px, py, selected_dot_radius + outline_size, outline_color, 32, outline_thickness)
        else
          -- Draw filled circle (dot) for non-playing samples
          r.ImGui_DrawList_AddCircleFilled(dl, px, py, dot_radius, color, 16)
        end
        
        if hovered then
          local dx = mx - px
          local dy = my - py
          local dist_sq = dx * dx + dy * dy
          -- Use customizable detection multiplier
          local detection_mult = state.dot_detection_multiplier or 16.0
          if dist_sq <= (dot_radius * dot_radius * detection_mult) then
            -- Store hovered sample with distance and dot color for later selection
            table.insert(hovered_samples, {
              sample = s,
              px = px,
              py = py,
              dist_sq = dist_sq,
              dot_color = color  -- Store the dot's tag-based color
            })
          end
        end
      end
    end
  end
  
  -- Handle hovered samples: select closest one to prevent overlapping dot issues
  if #hovered_samples > 0 then
    -- Sort by distance (closest first)
    table.sort(hovered_samples, function(a, b)
      return a.dist_sq < b.dist_sq
    end)
    
    -- Use the closest sample for hover effects and interaction
    local closest = hovered_samples[1]
    local s = closest.sample
    local px = closest.px
    local py = closest.py
    local dot_color_for_glow = closest.dot_color or dot_color  -- Use stored dot color
    
    -- Only add hover glow if this sample is not currently playing (avoid double glow)
    local is_currently_playing = preview_sample_obj and preview_sample_obj.path == s.path
    if not is_currently_playing then
      -- Subtle glow effect for hovered dots
      local hover_glow_inner = dot_radius * 1.1  -- Start glow just outside the dot
      local hover_glow_outer = dot_radius * 2.5   -- Smaller outer radius than selected dot
      
      -- Use the dot's tag color for glow (make it more subtle with lower opacity)
      local dot_r, dot_g, dot_b = extract_rgb_rrgbbaa(dot_color_for_glow)
      local subtle_hover_color = build_color_rrgbbaa(dot_r, dot_g, dot_b, 180)  -- ~70% opacity
      
      -- Draw subtle glowing circle effect for hover using dot's color
      draw_glowing_circle(dl, px, py, hover_glow_inner, hover_glow_outer, 
                         nil, subtle_hover_color, nil)  -- No solid center, just glow
    end
    
    -- Draw hover highlight ring for closest sample (colors already in RRGGBBAA format)
    local hot_color = s.hot_color or hover_color
    r.ImGui_DrawList_AddCircle(dl, px, py, dot_radius + 1.5, hot_color, 16, 1.5)
    
    -- Show tooltip for closest sample
    r.ImGui_BeginTooltip(ctx)
    r.ImGui_Text(ctx, s.name)
    r.ImGui_Text(ctx, string.format("%.2fs | %d Hz | ch:%d", s.duration, s.samplerate, s.channels))
    r.ImGui_Text(ctx, string.format("Dominant freq: %.1f Hz", s.dominant_freq or 440.0))
    r.ImGui_Text(ctx, string.format("RMS energy: %.6f", s.rms_energy or 0.0))
    if s.sample_type then
      r.ImGui_Text(ctx, string.format("Type: %s", s.sample_type))
    end
    if s.snap_offset then
      r.ImGui_Text(ctx, string.format("Snap offset: %.3fs", s.snap_offset))
    end
    if s.tags and #s.tags > 0 then
      r.ImGui_Text(ctx, "Tags: " .. table.concat(s.tags, ", "))
    end
    r.ImGui_EndTooltip(ctx)
    
    -- Handle click or drag selection (only for closest sample)
    if not click_handled_this_frame and r.ImGui_IsMouseClicked(ctx, 0) then
      clicked_sample = s
      click_handled_this_frame = true
      -- Start drag state so users can drag to preview different samples even if drag starts on a dot
      state.is_left_dragging = true
      state.last_dragged_sample_path = s.path
    elseif state.is_left_dragging and s.path ~= state.last_dragged_sample_path then
      -- While left-dragging, preview newly hovered samples
      clicked_sample = s
      state.last_dragged_sample_path = s.path
    end
  end
  
  if clicked_sample then
    preview_sample(clicked_sample)
  end
  
  -- Draw scanning progress overlay on the map (foreground drawing)
  if #state.scan_queue > 0 then
    local done = state.scan_total - #state.scan_queue
    local elapsed = r.time_precise() - state.scan_started
    local progress = state.scan_total > 0 and (done / state.scan_total) or 0.0
    
    -- Draw semi-transparent overlay background at the top of the map
    local overlay_height = 70.0
    local overlay_y = y0
    local overlay_bg_color = 0x000000CC  -- Semi-transparent black (RRGGBBAA format, last two digits are alpha)
    r.ImGui_DrawList_AddRectFilled(dl, x0, overlay_y, x0 + width, overlay_y + overlay_height, overlay_bg_color, 0, 0)
    
    -- Draw progress bar at the top of the map
    local bar_padding = 20.0
    local bar_y = overlay_y + 25.0
    local bar_width = width - (bar_padding * 2)
    local bar_height = 8.0
    
    -- Progress text (centered above bar)
    local text = string.format("Scanning: %.1f%% (%d/%d) - %.1fs", progress * 100.0, done, state.scan_total, elapsed)
    local text_size_x, text_size_y = r.ImGui_CalcTextSize(ctx, text)
    local text_x = x0 + (width - text_size_x) * 0.5
    local text_y = overlay_y + 8.0
    -- Draw text with shadow for better visibility
    r.ImGui_DrawList_AddText(dl, text_x + 1, text_y + 1, 0x000000FF, text)
    r.ImGui_DrawList_AddText(dl, text_x, text_y, 0xFFFFFFFF, text)
    
    -- Background bar (dark gray)
    local bar_bg_color = 0x2A2A2AFF
    r.ImGui_DrawList_AddRectFilled(dl, x0 + bar_padding, bar_y, x0 + bar_padding + bar_width, bar_y + bar_height, bar_bg_color, 4.0, 0)
    
    -- Progress fill (bright green)
    local fill_width = bar_width * math.max(0.0, math.min(1.0, progress))
    if fill_width > 2.0 then
      local fill_color = 0x00FF00FF
      r.ImGui_DrawList_AddRectFilled(dl, x0 + bar_padding + 2, bar_y + 2, x0 + bar_padding + fill_width - 2, bar_y + bar_height - 2, fill_color, 2.0, 0)
    end
    
    -- Border (white)
    local border_color = 0xFFFFFFFF
    r.ImGui_DrawList_AddRect(dl, x0 + bar_padding, bar_y, x0 + bar_padding + bar_width, bar_y + bar_height, border_color, 4.0, 0, 1.5)
    
    -- Estimate time remaining (below bar)
    if done > 0 and elapsed > 0.1 then
      local rate = done / elapsed  -- files per second
      local remaining = #state.scan_queue / rate
      if remaining > 0 then
        local remaining_text = string.format("Estimated time remaining: %.1fs", remaining)
        local remaining_size_x, remaining_size_y = r.ImGui_CalcTextSize(ctx, remaining_text)
        local remaining_x = x0 + (width - remaining_size_x) * 0.5
        local remaining_y = bar_y + bar_height + 8.0
        r.ImGui_DrawList_AddText(dl, remaining_x + 1, remaining_y + 1, 0x000000FF, remaining_text)
        r.ImGui_DrawList_AddText(dl, remaining_x, remaining_y, 0xCCCCCCFF, remaining_text)
      end
    end
  end
  
  r.ImGui_Dummy(ctx, width, 0.0)
  
  if #state.scan_queue == 0 then
    if #state.samples == 0 then
      r.ImGui_Text(ctx, "Press Rescan to populate the map.")
      if #state.folders > 0 then
        r.ImGui_Text(ctx, "Folders configured: " .. #state.folders)
      end
    else
      r.ImGui_Text(ctx, string.format("Showing %d samples on map (Zoom: %.1fx)", #state.samples, state.zoom))
      if state.selected then
        r.ImGui_Text(ctx, "Selected: " .. state.selected.name)
      end
    end
  end
end


-- --- Main loop ---------------------------------------------------------------
local function loop()
  if not running then
    return
  end
  
  if not r.ImGui_ValidatePtr(ctx, "ImGui_Context*") then
    log("ImGui context invalid; stopping loop")
    running = false
    return
  end
  
  process_scan_slice()
  
  local visible, open = begin_window()
  if visible then
    -- Handle keyboard input for history navigation (only when window is visible)
    if r.ImGui_IsKeyPressed and r.ImGui_Key_UpArrow and r.ImGui_Key_DownArrow then
      local up_pressed = r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_UpArrow(), false)
      local down_pressed = r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_DownArrow(), false)

      if up_pressed then
        navigate_history(1)   -- Go back in history to older samples (up arrow increases index)
      elseif down_pressed then
        navigate_history(-1)  -- Go forward in history to newer samples (down arrow decreases index)
      end
    end

    -- Handle global mouse release for waveform drag-and-drop
    if state.pending_waveform_drop and not r.ImGui_IsMouseDown(ctx, 0) then
      -- Mouse was released - complete the drag operation
      log("Mouse released globally, completing drag operation")

      -- Use the last tracked mouse position
      if state.last_mouse_time_pos then
        log("Dropping at tracked position: " .. string.format("%.3f", state.last_mouse_time_pos))
        local success = insert_sample_at_position(state.pending_waveform_drop, state.last_mouse_time_pos, state.last_mouse_track)
        if success then
          log("Successfully completed drag-and-drop")
        else
          log("Failed to complete drag-and-drop")
        end
      else
        -- Try to get position at release time (in case tracking missed it)
        local drop_time, drop_track = get_drop_position()
        if drop_time then
          log("Dropping at release position: " .. string.format("%.3f", drop_time))
          local success = insert_sample_at_position(state.pending_waveform_drop, drop_time, drop_track)
          if success then
            log("Successfully completed drag-and-drop at release position")
          else
            log("Failed to complete drag-and-drop at release position")
          end
        else
          -- Fallback to cursor position
          log("No tracked mouse position, using cursor position")
          local success = insert_sample_at_cursor(state.pending_waveform_drop)
          if success then
            log("Successfully completed drag-and-drop at cursor")
          else
            log("Failed to complete drag-and-drop")
          end
        end
      end

      -- Reset drag state
      state.pending_waveform_drop = nil
      state.last_mouse_time_pos = nil
      state.last_mouse_track = nil
    end

    render_header()
    render_waveform()
    render_map()
  end
  r.ImGui_End(ctx)
  
  -- Pop the style colors we pushed in begin_window (must match every push)
  r.ImGui_PopStyleColor(ctx, 3)  -- WindowBg, ChildBg, FrameBg
  
  -- Render settings window (separate window)
  render_settings()
  
  if open and running then
    r.defer(loop)
  else
    running = false
    stop_preview()
    
    -- Cleanup: Close all open analyzer pipes to prevent file handle leaks
    for i = #state.active_processes, 1, -1 do
      local proc = state.active_processes[i]
      if proc and proc.pipe then
        local close_ok, close_err = pcall(function() return proc.pipe:close() end)
        if not close_ok then
          log("Warning: failed to close pipe during cleanup: " .. tostring(close_err))
        end
      end
    end
    state.active_processes = {}
    
    -- Save samples before closing (to preserve scan progress)
    if #state.samples > 0 or #state.scan_queue > 0 then
      save_samples()
    end
    -- Try to destroy context if function exists
    if ctx and r.ImGui_ValidatePtr(ctx, "ImGui_Context*") then
      if r.APIExists("ImGui_DestroyContext") then
        r.ImGui_DestroyContext(ctx)
      end
    end
    ctx = nil
    save_config()
  end
end


-- --- Main entry point --------------------------------------------------------
local function main()
  log("Starting Sample Map Browser...")
  
  load_config()

  local cache_loaded = load_samples()

  ctx = r.ImGui_CreateContext(SCRIPT_NAME, r.ImGui_ConfigFlags_DockingEnable())
  font = r.ImGui_CreateFont("sans-serif", 16)
  if font then
    r.ImGui_Attach(ctx, font)
  end
  
  log("ImGui context created; beginning scan")
  if not cache_loaded then
    enqueue_scan()
  else
    state.scan_queue = {}
    state.scan_total = 0
    log("Using cached samples; skip initial scan")
  end
  loop()
end

main()



