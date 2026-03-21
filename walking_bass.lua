-- walking_bass
-- v4: bandleader edition
--
-- infinite upright walking bass
-- for drum practice.
--
-- custom physical-modeled engine,
-- grid progression builder,
-- tempo trainer, MIDI out.
--
-- K2 = start/stop
-- K3 = reset + play
-- E1 = page (screen)
-- E2 = tempo / grid root
-- E3 = progression / grid quality
--
-- grid:
--   rows 1-6 = chord slots (x=bar, y=root)
--   row 7    = quality toggle per bar
--   row 8    = transport + page

-------------------------------------------------
-- Engine selection (persisted)
-------------------------------------------------
local ENGINE_OPTIONS = {"UprightBass", "AcidTest"}
local engine_file = _path.data .. "walking_bass/engine_choice.txt"

local function read_engine_choice()
  local f = io.open(engine_file, "r")
  if f then
    local choice = f:read("*l")
    f:close()
    for _, name in ipairs(ENGINE_OPTIONS) do
      if name == choice then return name end
    end
  end
  return "UprightBass"
end

local function save_engine_choice(name)
  util.make_dir(_path.data .. "walking_bass/")
  local f = io.open(engine_file, "w")
  if f then f:write(name); f:close() end
end

local current_engine = read_engine_choice()
engine.name = current_engine

local MusicUtil = require "musicutil"

-------------------------------------------------
-- constants
-------------------------------------------------
local NUM_BARS_MAX = 16
local NUM_ROOTS = 6
local GRID_PAGES = {"form", "mix"}

local BRIGHT = {
  OFF    = 0,
  GHOST  = 2,
  DIM    = 4,
  MID    = 8,
  BRIGHT = 12,
  FULL   = 15,
}

local ARTICULATION = {
  normal   = 0,
  ghost    = 1,
  dig      = 2,
  staccato = 3,
  sing     = 4,
}

-- quality options for grid chord editing
local QUALITY_LIST = {"ionian", "dorian", "mixolydian", "aeolian", "melodic_minor", "phrygian", "locrian", "lydian"}
local QUALITY_SHORT = {"ion", "dor", "mix", "aeo", "mel", "phr", "loc", "lyd"}

local quality_to_scale = {
  ionian        = "Major",
  dorian        = "Dorian",
  phrygian      = "Phrygian",
  lydian        = "Lydian",
  mixolydian    = "Mixolydian",
  aeolian       = "Natural Minor",
  melodic_minor = "Melodic Minor",
  locrian       = "Locrian",
}

-------------------------------------------------
-- state
-------------------------------------------------
local state = {
  playing = false,
  counting_in = false,
  count_in_beats_left = 0,
  beat = 0,
  bar = 1,
  chorus = 1,
  last_note = 36,
  last_midi_note = nil,
  last_opxy_note = nil,
  last_interval = 0,
  target_note = 36,
  direction = 1,
  register_bias = 0,
  phrase_memory = {},
  motif = {},
  motif_age = 0,
  contour = 0,
  density = 0.93,
  energy = 0.42,
  pocket = 0.0,
  section = "support",
  section_bars_left = 8,
  solo_mode = false,
  last_articulation = "normal",
  last_velocity = 72,
  rest_streak = 0,
  anticipation_bias = -0.002,
  drag_bias = 0.001,
  turnaround_flash = false,
  -- turnaround variation
  turnaround_type = 1,
  -- tempo trainer
  ramp_active = false,
  ramp_start_tempo = 120,
  ramp_choruses_done = 0,
  clean_bars = 0,
  last_rest_occurred = false,
  -- screen
  screen_page = 1,
  screen_pages = {"play", "tone", "trainer"},
  -- beat phase tracking (0..1 within beat)
  beat_phase = 0.0,
}

-------------------------------------------------
-- note history for melodic contour visualization
-------------------------------------------------
local note_history = {}  -- {note, age_in_frames}
local max_history = 16

-------------------------------------------------
-- progression data (user-editable)
-------------------------------------------------
local progression_presets = {
  {
    name = "ii-V-I",
    chords = {
      {root = 38, quality = "dorian",     dur = 2},
      {root = 43, quality = "mixolydian", dur = 2},
      {root = 36, quality = "ionian",     dur = 4},
    }
  },
  {
    name = "minor swing",
    chords = {
      {root = 36, quality = "dorian",     dur = 4},
      {root = 41, quality = "mixolydian", dur = 2},
      {root = 43, quality = "mixolydian", dur = 2},
    }
  },
  {
    name = "blues-ish",
    chords = {
      {root = 36, quality = "mixolydian", dur = 4},
      {root = 41, quality = "mixolydian", dur = 2},
      {root = 36, quality = "mixolydian", dur = 2},
      {root = 43, quality = "mixolydian", dur = 2},
      {root = 41, quality = "mixolydian", dur = 2},
      {root = 36, quality = "mixolydian", dur = 4},
    }
  },
  {
    name = "custom",
    chords = {
      {root = 36, quality = "ionian", dur = 4},
    }
  },
}

local progression = progression_presets[1]
local progression_bar_map = {}
local total_bars = 0

-- turnaround patterns (intervals from chord root for last 2 bars)
local turnaround_patterns = {
  {name = "classic",    intervals = {{0, 4, 7, 10}, {0, 3, 7, 11}}},
  {name = "tritone_sub", intervals = {{0, 6, 7, 1},  {-1, 0, 5, 7}}},
  {name = "coltrane",    intervals = {{0, -1, -5, -7}, {0, 4, 7, 10}}},
  {name = "backdoor",    intervals = {{-2, -1, 0, 2}, {-4, -2, 0, 2}}},
}

-------------------------------------------------
-- grid state
-------------------------------------------------
local g = grid.connect()
local grid_page = 1  -- 1=form, 2=mix
local grid_dirty = true

-- custom chord chart (for grid editing)
-- each entry: {root=midi_note, quality=string, dur=1}
-- up to NUM_BARS_MAX bars, each 1 bar long
local custom_chart = {}
local grid_cursor_x = 1  -- selected bar on grid

-------------------------------------------------
-- MIDI
-------------------------------------------------
local midi_out
local midi_channel = 1

-------------------------------------------------
-- OP-XY MIDI
-------------------------------------------------
local opxy_out = nil
local opxy_enabled = false
local opxy_device = 1
local opxy_channel = 2  -- OP-XY default bass channel

local function opxy_note_on(note, vel)
  if opxy_out and opxy_enabled then
    opxy_out:note_on(note, vel, opxy_channel)
  end
end

local function opxy_note_off(note)
  if opxy_out and opxy_enabled then
    opxy_out:note_off(note, 0, opxy_channel)
  end
end

local function opxy_cc(cc_num, val)
  if opxy_out and opxy_enabled then
    opxy_out:cc(cc_num, math.floor(util.clamp(val, 0, 127)), opxy_channel)
  end
end

local function opxy_all_notes_off()
  if opxy_out and opxy_enabled then
    opxy_out:cc(123, 0, opxy_channel)
  end
end

-------------------------------------------------
-- metros / clocks
-------------------------------------------------
local redraw_metro
local transport_clock_id = nil
local screen_dirty = true

-------------------------------------------------
-- utilities
-------------------------------------------------
local function clamp(x, lo, hi)
  return math.max(lo, math.min(hi, x))
end

local function chance(p)
  return math.random() < p
end

local function sign(x)
  if x < 0 then return -1 elseif x > 0 then return 1 else return 0 end
end

local function rrange(a, b)
  return a + math.random() * (b - a)
end

local function round(x)
  return math.floor(x + 0.5)
end

local function note_name(n)
  return MusicUtil.note_num_to_name(n, true)
end

local function note_name_short(n)
  return MusicUtil.note_num_to_name(n, false)
end

local function fmt_ms(param)
  return param:get() .. " ms"
end

local function fmt_note(param)
  return note_name(param:get())
end

local function truncate_text(str, max_len)
  if string.len(str) > max_len then
    return string.sub(str, 1, max_len - 1) .. "~"
  end
  return str
end

-------------------------------------------------
-- progression map
-------------------------------------------------
local function rebuild_progression_map()
  progression_bar_map = {}
  total_bars = 0
  for _, chord in ipairs(progression.chords) do
    for _ = 1, chord.dur do
      total_bars = total_bars + 1
      progression_bar_map[total_bars] = chord
    end
  end
  if total_bars < 1 then
    total_bars = 1
    progression_bar_map[1] = {root = 36, quality = "ionian", dur = 1}
  end
end

local function current_bar_in_form()
  return ((state.bar - 1) % total_bars) + 1
end

local function get_current_chord()
  local chord_map = progression_bar_map[current_bar_in_form()]
  if not chord_map then
    return progression.chords[1] or {root = 36, quality = "ionian", dur = 1}
  end
  return chord_map
end

local function get_next_chord()
  local next_bar = (current_bar_in_form() % total_bars) + 1
  local chord_map = progression_bar_map[next_bar]
  if not chord_map then
    return progression.chords[1] or {root = 36, quality = "ionian", dur = 1}
  end
  return chord_map
end

local function get_scale_for_chord(chord)
  local scale_name = quality_to_scale[chord.quality] or "Major"
  return MusicUtil.generate_scale_of_length(chord.root, scale_name, 16)
end

local function note_in_range(note)
  local lo = params:get("low_note")
  local hi = params:get("high_note")
  if lo >= hi then return clamp(note, 28, 52) end
  while note < lo do note = note + 12 end
  while note > hi do note = note - 12 end
  if note < lo or note > hi then note = clamp(note, lo, hi) end
  return note
end

local function chord_tones(chord)
  local third = 4
  local q = chord.quality
  if q == "dorian" or q == "aeolian" or q == "melodic_minor"
    or q == "phrygian" or q == "locrian" then
    third = 3
  end
  return {
    chord.root,
    chord.root + third,
    chord.root + 7,
    chord.root + 10,
  }
end

-------------------------------------------------
-- note history tracking
-------------------------------------------------
local function remember_note(note, is_approach)
  table.insert(note_history, 1, {note = note, is_approach = is_approach or false})
  while #note_history > max_history do
    table.remove(note_history)
  end
end

-------------------------------------------------
-- custom chart <-> progression
-------------------------------------------------
local function build_custom_from_grid()
  -- build progression.chords from custom_chart
  if #custom_chart == 0 then return end
  local chords = {}
  local i = 1
  while i <= #custom_chart do
    local c = custom_chart[i]
    local dur = 1
    -- merge consecutive identical chords
    while i + dur <= #custom_chart do
      local nx = custom_chart[i + dur]
      if nx.root == c.root and nx.quality == c.quality then
        dur = dur + 1
      else
        break
      end
    end
    table.insert(chords, {root = c.root, quality = c.quality, dur = dur})
    i = i + dur
  end
  progression_presets[4].chords = chords
  if params:get("progression") == 4 then
    progression = progression_presets[4]
    rebuild_progression_map()
  end
end

local function init_custom_chart()
  custom_chart = {}
  for i = 1, 8 do
    table.insert(custom_chart, {root = 36, quality = "ionian"})
  end
  build_custom_from_grid()
end

-------------------------------------------------
-- engine interface
-------------------------------------------------
local function engine_note(freq, amp, decay, articulation_name)
  if eng.note_on then
    eng.note_on(freq, amp, decay, articulation_name)
  else
    -- Fallback for during initialization
    local artic = ARTICULATION[articulation_name] or 0
    engine.note(freq, amp, decay, artic)
  end
end

local function engine_click(freq, amp)
  if current_engine == "UprightBass" then
    engine.click(freq, amp)
  end
  -- AcidTest doesn't have click
end

local function setup_engine_defaults()
  if current_engine == "UprightBass" then
    engine.body_tone(params:get("body_tone"))
    engine.body_mix(params:get("body_mix"))
    engine.finger_amt(params:get("finger_noise"))
    engine.sympathetic_amt(params:get("resonance"))
    engine.drift_amt(params:get("pitch_drift"))
    engine.brightness_amt(params:get("brightness"))
    engine.reverb_mix(params:get("reverb_mix"))
    engine.reverb_room(params:get("reverb_room"))
  elseif current_engine == "AcidTest" then
    -- Initialize AcidTest delay if configured
    if pcall(function() params:get("acid_delay_feedback") end) then
      engine.acidTest_delay(60 / clock.get_tempo(), params:get("acid_delay_beats"), params:get("acid_delay_feedback"))
    end
  end
end

-------------------------------------------------
-- Engine abstraction layer
-------------------------------------------------
local eng = {}

local function setup_engine_abstraction()
  if current_engine == "UprightBass" then
    eng.note_on = function(freq, amp, decay, articulation)
      local artic = ARTICULATION[articulation] or 0
      engine.note(freq, amp, decay, artic)
    end
    eng.note_off = function(voice_id)
      engine.noteOff(voice_id)
    end
    eng.kill_all = function()
      for i = 0, 5 do engine.noteOff(i) end
    end

  elseif current_engine == "AcidTest" then
    local acid_portamento = 0.05

    eng.note_on = function(freq, amp, decay, articulation)
      -- Convert freq to MIDI note
      local note = math.floor(69 + 12 * math.log(freq / 440) / math.log(2) + 0.5)
      -- Map articulation to portamento
      local port = acid_portamento
      if articulation == "sing" then port = 0.2 end     -- sing = long portamento
      if articulation == "staccato" then port = 0 end    -- staccato = no portamento
      if articulation == "ghost" then port = 0.01 end    -- ghost = quick

      engine.acidTest_bass_gate(1)
      engine.acidTest_bass(amp, note,
        params:get("acid_delay_send"),
        params:get("acid_reverb_send"),
        port)
    end
    eng.note_off = function(voice_id)
      engine.acidTest_bass_gate(0)
    end
    eng.kill_all = function()
      engine.acidTest_bass_gate(0)
      engine.acidTest_lead_gate(0)
    end
  end
end

-------------------------------------------------
-- MIDI output
-------------------------------------------------
local function midi_note_on(note, velocity)
  if midi_out and params:get("midi_enabled") == 2 then
    midi_out:note_on(note, velocity, midi_channel)
    state.last_midi_note = note
  end
end

local function midi_note_off()
  if midi_out and state.last_midi_note then
    midi_out:note_off(state.last_midi_note, 0, midi_channel)
    state.last_midi_note = nil
  end
end

-------------------------------------------------
-- sound shaping helpers
-------------------------------------------------
local function vel_to_amp(velocity)
  return clamp(((velocity / 127) ^ 1.7) * params:get("master_amp"), 0.02, 1.4)
end

local function register_tone(note)
  local lo = params:get("low_note")
  local hi = params:get("high_note")
  local pos = 0.5
  if hi > lo then pos = util.linlin(lo, hi, 0, 1, note) end
  return clamp(params:get("body_tone") + pos * 190 + rrange(-35, 35), 260, 2400)
end

local function note_decay(note, articulation)
  local lo = params:get("low_note")
  local hi = params:get("high_note")
  local base = 0.5
  if hi > lo then base = util.linlin(lo, hi, 0.58, 0.22, note) end
  if articulation == "ghost"    then base = base * 0.45 end
  if articulation == "dig"      then base = base * 1.08 end
  if articulation == "lead_in"  then base = base * 0.72 end
  if articulation == "sing"     then base = base * 1.2  end
  if articulation == "staccato" then base = base * 0.42 end
  return clamp(base * params:get("decay_shape"), 0.04, 4.0)
end

-------------------------------------------------
-- note trigger (unified: engine + MIDI + OP-XY)
-------------------------------------------------
local function perform_note(note, velocity, gate_beats, articulation)
  local freq = MusicUtil.note_num_to_freq(note)
  local amp = vel_to_amp(velocity)
  local decay = note_decay(note, articulation) * gate_beats * 1.8

  engine_note(freq, amp, decay, articulation)
  midi_note_off()
  midi_note_on(note, math.floor(velocity))
  if state.last_opxy_note then
    opxy_note_off(state.last_opxy_note)
  end
  opxy_note_on(note, math.floor(velocity))
  state.last_opxy_note = note

  -- schedule MIDI note-off
  if params:get("midi_enabled") == 2 or opxy_enabled then
    local scheduled_opxy_note = note
    clock.run(function()
      clock.sleep(gate_beats * (60 / clock.tempo) * 0.9)
      midi_note_off()
      opxy_note_off(scheduled_opxy_note)
    end)
  end
end

-------------------------------------------------
-- phrase memory / motif
-------------------------------------------------
local function remember_interval(interval)
  table.insert(state.phrase_memory, interval)
  while #state.phrase_memory > 16 do table.remove(state.phrase_memory, 1) end
end

local function maybe_refresh_motif()
  if #state.phrase_memory < 4 then return end
  if #state.motif == 0 or state.motif_age > 12 or chance(0.12) then
    local len = math.random(3, 5)
    state.motif = {}
    local start_i = math.max(1, #state.phrase_memory - len + 1)
    for i = start_i, #state.phrase_memory do
      table.insert(state.motif, state.phrase_memory[i])
    end
    state.motif_age = 0
  end
end

local function motif_hint()
  if #state.motif < 2 then return nil end
  if not chance(0.32) then return nil end
  state.motif_age = state.motif_age + 1
  local ix = ((state.beat - 1) % #state.motif) + 1
  local interval = state.motif[ix]
  if chance(0.2) then interval = interval + (chance(0.5) and 1 or -1) end
  return interval
end

-------------------------------------------------
-- turnaround variation system
-------------------------------------------------
local function is_turnaround_bar()
  local bar_in_form = current_bar_in_form()
  return bar_in_form >= (total_bars - 1)
end

local function get_turnaround_note(step_in_bar, chord)
  if not is_turnaround_bar() then return nil end
  if not chance(params:get("turnaround_intensity")) then return nil end

  local bar_in_form = current_bar_in_form()
  local turnaround_bar = bar_in_form - (total_bars - 2) -- 0 or 1
  if turnaround_bar < 0 then turnaround_bar = 0 end
  if turnaround_bar > 1 then turnaround_bar = 1 end

  local pattern = turnaround_patterns[state.turnaround_type]
  if not pattern then return nil end

  local intervals = pattern.intervals[turnaround_bar + 1]
  if not intervals or not intervals[step_in_bar] then return nil end

  return note_in_range(chord.root + intervals[step_in_bar])
end

-------------------------------------------------
-- note selection (the brain)
-------------------------------------------------
local function choose_target_note(next_chord)
  local tones = chord_tones(next_chord)
  local best = tones[1]
  local best_dist = 999
  for _, tone in ipairs(tones) do
    for _, c in ipairs({tone - 12, tone, tone + 12}) do
      local d = math.abs(c - state.last_note)
      if d < best_dist then
        best = c
        best_dist = d
      end
    end
  end
  return note_in_range(best)
end

local function approach_note(target)
  local opts = {
    target - 1, target + 1,
    target - 2, target + 2,
    target - 3, target + 3,
  }
  if chance(0.2) then
    opts[#opts + 1] = target - 5
    opts[#opts + 1] = target + 5
  end
  return opts[math.random(#opts)]
end

local function section_bias_weight(tag)
  if state.section == "support" then
    if tag == "root"     then return 1.25 end
    if tag == "approach" then return 1.1  end
    if tag == "jump"     then return 0.7  end
  elseif state.section == "push" then
    if tag == "approach" then return 1.18 end
    if tag == "jump"     then return 1.1  end
  elseif state.section == "layback" then
    if tag == "root" then return 1.12 end
    if tag == "step" then return 1.08 end
    if tag == "jump" then return 0.6  end
  elseif state.section == "solo" then
    if tag == "jump"  then return 1.2  end
    if tag == "color" then return 1.15 end
  elseif state.section == "trade" then
    if tag == "rest" then return 1.3  end
    if tag == "jump" then return 1.12 end
  end
  return 1.0
end

local function build_walk_note(step_in_bar, chord, next_chord)
  -- check turnaround variation first
  local turn_note = get_turnaround_note(step_in_bar, chord)
  if turn_note then
    local interval = turn_note - state.last_note
    return turn_note, interval
  end

  local scale = get_scale_for_chord(chord)
  local tones = chord_tones(chord)
  local candidates = {}

  local function add_candidate(n, w, tag)
    n = note_in_range(n)
    local leap = math.abs(n - state.last_note)
    if leap > 10 then w = w * 0.22 end
    if leap == 0  then w = w * 0.28 end
    if sign(n - state.last_note) == state.direction and leap > 0 then
      w = w * 1.08
    end
    if math.abs(n - params:get("low_note"))  < 1 then w = w * 0.82 end
    if math.abs(n - params:get("high_note")) < 1 then w = w * 0.78 end
    w = w * section_bias_weight(tag)
    table.insert(candidates, {n = n, w = w})
  end

  -- beat 1: chord root strongly weighted
  if step_in_bar == 1 then
    add_candidate(chord.root,      7.0, "root")
    add_candidate(chord.root + 12, 1.3, "root")
    add_candidate(tones[3],        1.5, "color")
  -- beat 3: colour tones
  elseif step_in_bar == 3 then
    add_candidate(tones[2], 2.1, "color")
    add_candidate(tones[3], 2.4, "color")
    add_candidate(tones[4], 1.6, "color")
  end

  -- scale tones as stepwise candidates
  for _, n in ipairs(scale) do
    if n >= chord.root - 5 and n <= chord.root + 17 then
      add_candidate(n, 0.74, "step")
    end
  end

  -- beat 4: approach the next chord root
  if next_chord and step_in_bar == 4 then
    state.target_note = choose_target_note(next_chord)
    add_candidate(approach_note(state.target_note), 5.4, "approach")
    add_candidate(state.target_note, 1.0, "root")
  end

  -- motivic callback
  local hint = motif_hint()
  if hint then add_candidate(state.last_note + hint, 1.55, "jump") end

  -- solo / adventurous intervals
  if state.solo_mode or state.section == "solo" then
    add_candidate(state.last_note + (chance(0.5) and  2 or -2), 1.60, "jump")
    add_candidate(state.last_note + (chance(0.5) and  3 or -3), 1.25, "jump")
    add_candidate(state.last_note + (chance(0.5) and  5 or -5), 0.95, "jump")
    add_candidate(state.last_note + (chance(0.5) and  7 or -7), 0.45, "jump")
  end

  -- weighted random selection
  local total_w = 0
  for _, c in ipairs(candidates) do total_w = total_w + c.w end
  if total_w <= 0 then return state.last_note, 0 end
  local r = math.random() * total_w
  local acc = 0
  local chosen = state.last_note
  for _, c in ipairs(candidates) do
    acc = acc + c.w
    if r <= acc then chosen = c.n; break end
  end

  chosen = note_in_range(chosen + round(state.register_bias))
  local interval = chosen - state.last_note

  if math.abs(interval) >= 5 and chance(0.62) then
    state.direction = -sign(interval)
  elseif interval ~= 0 then
    state.direction = sign(interval)
  end

  return chosen, interval
end

-------------------------------------------------
-- rhythm / articulation / feel
-------------------------------------------------
local function should_rest(step_in_bar)
  local p = (1 - state.density) * 0.08
  if step_in_bar == 1  then p = p * 0.18 end
  if state.section == "trade" then
    if step_in_bar >= 3 then p = p + 0.08 end
  end
  if state.solo_mode   then p = p + 0.03  end
  if state.rest_streak > 0 then p = p * 0.4 end
  local rest = chance(p)
  if rest then
    state.rest_streak = state.rest_streak + 1
  else
    state.rest_streak = 0
  end
  return rest
end

local function classify_articulation(step_in_bar, interval, velocity)
  if state.section == "layback" and chance(0.18) then return "staccato" end
  if step_in_bar == 4 and math.abs(interval) <= 2 and chance(0.36) then return "lead_in" end
  if math.abs(interval) >= 7 and chance(0.5) then return "dig" end
  if velocity < 58 and chance(0.35)            then return "ghost" end
  if (state.section == "solo" or state.solo_mode) and chance(0.32) then return "sing" end
  return "normal"
end

local function step_velocity(step_in_bar)
  local base = params:get("base_velocity")
  local accents = {1.12, 0.93, 1.02, 0.98}
  local v = base * accents[step_in_bar]
  v = v + state.energy * 18
  v = v + state.contour * 4
  if state.section == "push"    then v = v + 4 end
  if state.section == "layback" then v = v - 3 end
  if state.section == "solo"    then v = v + 7 end
  v = v + rrange(-8, 8)
  return clamp(v, 20, 127)
end

local function step_gate(step_in_bar)
  local swing = params:get("swing")
  local g_val = 0.43
  if step_in_bar == 1    then g_val = g_val + 0.05 end
  if step_in_bar % 2 == 0 then
    g_val = g_val + swing * 0.11
  else
    g_val = g_val - swing * 0.04
  end
  if state.section == "layback" then g_val = g_val * 0.9  end
  if state.section == "solo"    then g_val = g_val * 1.05 end
  return clamp(g_val * rrange(0.92, 1.08), 0.08, 0.98)
end

local function human_delay(step_in_bar)
  local ms = params:get("humanity_ms")
  local pocket_ms = state.pocket * params:get("pocket_depth")
  local bias = 0
  if step_in_bar == 4 and chance(0.4) then
    bias = bias + state.anticipation_bias * 1000
  end
  if step_in_bar == 2 and chance(0.25) then
    bias = bias + state.drag_bias * 1000
  end
  return (rrange(-ms, ms) + pocket_ms + bias) / 1000
end

-------------------------------------------------
-- section / evolution (the "bandleader")
-------------------------------------------------
local function maybe_change_section()
  state.section_bars_left = state.section_bars_left - 1
  if state.section_bars_left > 0 then return end

  local options = {
    {name = "support",  w = 4.0},
    {name = "push",     w = 1.6},
    {name = "layback",  w = 1.2},
    {name = "solo",     w = params:get("solo_probability") * 22},
    {name = "trade",    w = params:get("trade_probability") * 18},
  }
  local total_w = 0
  for _, o in ipairs(options) do total_w = total_w + o.w end
  local r = math.random() * total_w
  local acc = 0
  local choice = "support"
  for _, o in ipairs(options) do
    acc = acc + o.w
    if r <= acc then choice = o.name; break end
  end

  state.section = choice
  state.solo_mode = (choice == "solo")
  state.section_bars_left = math.random(4, 10)
  if choice == "solo"  then state.section_bars_left = math.random(2, 4) end
  if choice == "trade" then state.section_bars_left = math.random(2, 4) end
end

local function evolve_bandmind()
  if chance(0.14) then state.energy   = clamp(state.energy   + rrange(-0.06, 0.08), 0.22, 0.96) end
  if chance(0.11) then state.density  = clamp(state.density  + rrange(-0.05, 0.04), 0.72, 1.0)  end
  if chance(0.11) then state.register_bias = clamp(state.register_bias + rrange(-1.0, 1.0), -4, 5) end
  if chance(0.10) then state.contour  = clamp(state.contour  + rrange(-0.4, 0.4), -1.2, 1.2) end
  if chance(0.13) then state.pocket   = clamp(state.pocket   + rrange(-0.2, 0.2), -1.0, 1.0) end
  if chance(0.09) then
    state.anticipation_bias = clamp(state.anticipation_bias + rrange(-0.003, 0.003), -0.01, 0.0)
  end
  if chance(0.09) then
    state.drag_bias = clamp(state.drag_bias + rrange(-0.001, 0.003), 0.0, 0.012)
  end

  -- cycle turnaround type every few choruses
  if chance(0.15) then
    state.turnaround_type = math.random(1, #turnaround_patterns)
  end

  maybe_refresh_motif()
  maybe_change_section()

  local form_bar = current_bar_in_form()
  state.turnaround_flash = (form_bar == total_bars)
  if state.turnaround_flash then
    state.energy = clamp(state.energy + 0.05, 0.22, 0.96)
  end
end

-------------------------------------------------
-- tempo trainer
-------------------------------------------------
local function tempo_trainer_check()
  if not state.ramp_active then return end
  
  -- track clean bars (bars with no rests)
  if not state.last_rest_occurred then
    state.clean_bars = state.clean_bars + 1
  else
    state.clean_bars = 0
  end
  state.last_rest_occurred = false
  
  -- after 8 clean bars, increase tempo
  if state.clean_bars >= 8 then
    state.clean_bars = 0
    local increment = params:get("trainer_bpm_increment")
    local max_tempo = params:get("trainer_max_tempo")
    local new_tempo = math.min(params:get("tempo") + increment, max_tempo)
    params:set("tempo", new_tempo)
    if new_tempo >= max_tempo then
      state.ramp_active = false
    end
    state.ramp_choruses_done = state.ramp_choruses_done + 1
  end
end

-------------------------------------------------
-- count-in
-------------------------------------------------
local function start_count_in()
  state.counting_in = true
  state.count_in_beats_left = 4
  clock.run(function()
    for i = 1, 4 do
      local freq = (i == 1) and 1400 or 1100
      local amp = (i == 1) and 0.5 or 0.35
      engine_click(freq, amp)
      state.count_in_beats_left = 4 - i
      screen_dirty = true
      if i < 4 then
        clock.sync(1)
      end
    end
    clock.sync(1)
    state.counting_in = false
    state.playing = true
    screen_dirty = true
  end)
end

-------------------------------------------------
-- transport
-------------------------------------------------
local function play_step()
  local chord = get_current_chord()
  local next_chord = get_next_chord()
  local step_in_bar = ((state.beat - 1) % 4) + 1

  if should_rest(step_in_bar) then
    state.last_rest_occurred = true
    screen_dirty = true
    grid_dirty = true
    return
  end

  local note, interval = build_walk_note(step_in_bar, chord, next_chord)
  local velocity    = step_velocity(step_in_bar)
  local gate        = step_gate(step_in_bar)
  local articulation = classify_articulation(step_in_bar, interval, velocity)
  local delay       = human_delay(step_in_bar)

  state.last_note        = note
  state.last_interval    = interval
  state.last_velocity    = velocity
  state.last_articulation = articulation
  remember_interval(interval)
  
  -- track note for melodic contour visualization
  local is_approach = (articulation == "lead_in")
  remember_note(note, is_approach)

  clock.run(function()
    if delay > 0 then clock.sleep(delay) end
    perform_note(note, velocity, gate, articulation)
  end)

  -- Update OP-XY filter/tone CCs
  opxy_cc(32, util.linlin(260, 2400, 0, 127, register_tone(note)))
  opxy_cc(46, util.linlin(0, 1, 0, 127, params:get("body_tone") / 2200))

  screen_dirty = true
  grid_dirty = true
end

local function advance_form_if_needed()
  if state.beat % 4 == 0 then
    state.bar = state.bar + 1
    if current_bar_in_form() == 1 then
      state.chorus = state.chorus + 1
      tempo_trainer_check()
    end
    evolve_bandmind()
  end
end

local function transport_loop()
  while true do
    clock.sync(1)
    if state.playing then
      state.beat = state.beat + 1
      -- update beat phase
      state.beat_phase = ((state.beat - 1) % 4) / 4
      play_step()
      advance_form_if_needed()
    end
  end
end

-------------------------------------------------
-- root transposition
-------------------------------------------------
local function apply_root_offset(root_note)
  local delta = root_note - 36
  for _, preset in ipairs(progression_presets) do
    if preset.name ~= "custom" then
      local base_roots
      if preset.name == "ii-V-I" then
        base_roots = {38, 43, 36}
      elseif preset.name == "minor swing" then
        base_roots = {36, 41, 43}
      elseif preset.name == "blues-ish" then
        base_roots = {36, 41, 36, 43, 41, 36}
      end
      if base_roots then
        for i, chord in ipairs(preset.chords) do
          if base_roots[i] then
            chord.root = base_roots[i] + delta
          end
        end
      end
    end
  end
end

-------------------------------------------------
-- reset
-------------------------------------------------
local function reset_player()
  midi_note_off()
  opxy_all_notes_off()
  state.beat = 0
  state.bar = 1
  state.chorus = 1
  state.last_note = params:get("root")
  state.last_midi_note = nil
  state.last_opxy_note = nil
  state.last_interval = 0
  state.target_note = state.last_note
  state.direction = 1
  state.register_bias = 0
  state.phrase_memory = {}
  state.motif = {}
  state.motif_age = 0
  state.contour = 0
  state.density = 0.93
  state.energy = 0.42
  state.pocket = 0.0
  state.section = "support"
  state.section_bars_left = 8
  state.solo_mode = false
  state.last_articulation = "normal"
  state.last_velocity = params:get("base_velocity")
  state.rest_streak = 0
  state.anticipation_bias = -0.002
  state.drag_bias = 0.001
  state.turnaround_flash = false
  state.turnaround_type = 1
  state.ramp_choruses_done = 0
  state.clean_bars = 0
  state.last_rest_occurred = false
  note_history = {}
  if state.ramp_active then
    -- start at 60% of target tempo
    local target = params:get("trainer_start_tempo")
    local start_tempo = math.floor(target * 0.6)
    params:set("tempo", start_tempo)
  end
end

local function set_progression(ix)
  progression = progression_presets[ix]
  rebuild_progression_map()
  reset_player()
end

-------------------------------------------------
-- GRID: drawing
-------------------------------------------------
local function grid_redraw()
  if not g.device then return end
  g:all(0)

  if grid_page == 1 then
    -- PAGE 1: FORM VIEW
    -- rows 1-6: pitch grid (shows chord roots)
    -- row 7: quality indicator
    -- row 8: transport

    local form_bar = current_bar_in_form()
    local bars_to_show = math.min(total_bars, 16)

    for col = 1, bars_to_show do
      local chord = progression_bar_map[col]
      if chord then
        -- map root to row (1=high, 6=low)
        local root_mod = chord.root % 12
        local row = clamp(6 - math.floor(root_mod / 2), 1, 6)

        -- brightness: playing bar is bright, others mid
        local bright = BRIGHT.MID
        if state.playing and col == form_bar then
          bright = BRIGHT.FULL
        end
        g:led(col, row, bright)

        -- quality indicator on row 7 (bright = major-ish, dim = minor-ish)
        local q = chord.quality
        local q_bright = BRIGHT.DIM
        if q == "ionian" or q == "mixolydian" or q == "lydian" then
          q_bright = BRIGHT.BRIGHT
        elseif q == "dorian" or q == "aeolian" or q == "melodic_minor" then
          q_bright = BRIGHT.MID
        end
        g:led(col, 7, q_bright)
      end
    end

    -- playhead on row 8
    if state.playing then
      local step_in_bar = ((state.beat - 1) % 4) + 1
      for col = 1, bars_to_show do
        if col == form_bar then
          g:led(col, 8, BRIGHT.BRIGHT)
        else
          g:led(col, 8, BRIGHT.GHOST)
        end
      end
    end

  elseif grid_page == 2 then
    -- PAGE 2: CUSTOM CHART EDITOR
    -- rows 1-6: root note selection per bar (y=pitch)
    -- row 7: quality cycle
    -- row 8: bar length / page

    local root_names = {"C", "D", "E", "F", "G", "A"}
    local root_midi  = {36, 38, 40, 41, 43, 45}

    for col = 1, math.min(#custom_chart, 16) do
      local c = custom_chart[col]
      -- find which row this root maps to
      for row = 1, 6 do
        local midi = root_midi[7 - row]  -- row 1=A, row 6=C
        if c.root % 12 == midi % 12 then
          g:led(col, row, BRIGHT.BRIGHT)
        else
          g:led(col, row, BRIGHT.GHOST)
        end
      end
      -- quality on row 7
      local qi = 1
      for k, v in ipairs(QUALITY_LIST) do
        if v == c.quality then qi = k; break end
      end
      g:led(col, 7, clamp(qi * 2, 2, 15))
    end

    -- row 8: chart length indicators
    for col = 1, 16 do
      if col <= #custom_chart then
        g:led(col, 8, BRIGHT.DIM)
      end
    end
  end

  g:refresh()
  grid_dirty = false
end

-------------------------------------------------
-- GRID: input
-------------------------------------------------
g.key = function(x, y, z)
  if z == 0 then return end

  if grid_page == 1 then
    -- form view: mostly display-only
    -- row 8 col 16 = toggle grid page
    if y == 8 and x == 16 then
      grid_page = 2
      grid_dirty = true
      return
    end
    -- row 8 col 1 = start/stop
    if y == 8 and x == 1 then
      if state.playing then
        state.playing = false
      else
        start_count_in()
      end
      screen_dirty = true
      grid_dirty = true
      return
    end
    -- row 8 col 2 = reset + play
    if y == 8 and x == 2 then
      reset_player()
      start_count_in()
      screen_dirty = true
      grid_dirty = true
      return
    end

  elseif grid_page == 2 then
    -- custom chart editor
    local root_midi = {36, 38, 40, 41, 43, 45}

    -- row 8 col 16 = back to form view
    if y == 8 and x == 16 then
      grid_page = 1
      grid_dirty = true
      return
    end

    -- row 8 col 15 = add bar
    if y == 8 and x == 15 then
      if #custom_chart < NUM_BARS_MAX then
        table.insert(custom_chart, {root = 36, quality = "ionian"})
        build_custom_from_grid()
        grid_dirty = true
        screen_dirty = true
      end
      return
    end

    -- row 8 col 14 = remove last bar
    if y == 8 and x == 14 then
      if #custom_chart > 1 then
        table.remove(custom_chart)
        build_custom_from_grid()
        grid_dirty = true
        screen_dirty = true
      end
      return
    end

    -- rows 1-6: set root for bar x
    if y >= 1 and y <= 6 and x <= #custom_chart then
      local midi = root_midi[7 - y]
      custom_chart[x].root = midi
      build_custom_from_grid()
      grid_dirty = true
      screen_dirty = true
      return
    end

    -- row 7: cycle quality for bar x
    if y == 7 and x <= #custom_chart then
      local c = custom_chart[x]
      local qi = 1
      for k, v in ipairs(QUALITY_LIST) do
        if v == c.quality then qi = k; break end
      end
      qi = (qi % #QUALITY_LIST) + 1
      c.quality = QUALITY_LIST[qi]
      build_custom_from_grid()
      grid_dirty = true
      screen_dirty = true
      return
    end
  end
end

-------------------------------------------------
-- MELODIC CONTOUR VISUALIZATION HELPER
-------------------------------------------------
local function draw_melodic_contour()
  if #note_history == 0 then return end
  
  screen.aa(1)  -- anti-alias for smooth contour
  local start_x = 10
  local end_x = 118
  local width = end_x - start_x
  local lo = params:get("low_note")
  local hi = params:get("high_note")
  local note_range = hi - lo
  
  if note_range <= 0 then return end
  
  for i = 1, #note_history do
    local note_entry = note_history[i]
    local note = note_entry.note
    local x = end_x - ((i - 1) / (max_history - 1)) * width
    local y = 52 - ((note - lo) / note_range) * 40
    
    local brightness = 12
    if i <= #note_history / 2 then
      brightness = 4 + (i / (#note_history / 2)) * 8
    else
      brightness = 12 - ((i - #note_history / 2) / (#note_history / 2)) * 8
    end
    
    -- smaller dot for approach notes
    local size = note_entry.is_approach and 0.5 or 1.0
    if i < #note_history then
      local next_entry = note_history[i + 1]
      local next_x = end_x - (i / (max_history - 1)) * width
      local next_y = 52 - ((next_entry.note - lo) / note_range) * 40
      
      screen.level(clamp(math.floor(brightness / 1.5), 1, 15))
      screen.move(x, y)
      screen.line(next_x, next_y)
      screen.stroke()
    end
    
    screen.level(clamp(math.floor(brightness), 1, 15))
    screen.circle(x, y, size)
    screen.fill()
  end
end

-------------------------------------------------
-- init
-------------------------------------------------
function init()
  math.randomseed(os.time())

  -- MIDI setup
  midi_out = midi.connect(1)

  ----- PARAMS -----
  params:add_group("TRANSPORT", 5)

  params:add_number("tempo", "tempo", 60, 300, 138)
  params:set_action("tempo", function(x) clock.tempo = x end)

  params:add_option("progression", "progression",
    {"ii-V-I", "minor swing", "blues-ish", "custom"}, 1)
  params:set_action("progression", function(ix) set_progression(ix) end)

  params:add_number("root", "root note", 28, 52, 36, fmt_note)
  params:set_action("root", function(x)
    apply_root_offset(x)
    rebuild_progression_map()
    reset_player()
  end)

  params:add_number("low_note", "lowest note", 24, 48, 28, fmt_note)
  params:add_number("high_note", "highest note", 34, 60, 45, fmt_note)

  ----- FEEL -----
  params:add_group("FEEL", 5)

  params:add_number("base_velocity", "touch", 20, 120, 72)
  params:add_number("humanity_ms", "humanity ms", 0, 45, 12, fmt_ms)
  params:add_control("pocket_depth", "pocket depth ms",
    controlspec.new(0, 18, 'lin', 0, 6, 'ms'))
  params:add_control("swing", "swing",
    controlspec.new(0, 0.4, 'lin', 0, 0.085, ''))
  params:add_control("turnaround_intensity", "turnaround",
    controlspec.new(0, 1, 'lin', 0, 0.4, ''))

  ----- ENGINE -----
  params:add_separator("ENGINE")
  local eng_idx = 1
  for i, name in ipairs(ENGINE_OPTIONS) do
    if name == current_engine then eng_idx = i end
  end
  params:add_option("engine_select", "sound engine", ENGINE_OPTIONS, eng_idx)
  params:set_action("engine_select", function(val)
    local new_engine = ENGINE_OPTIONS[val]
    if new_engine ~= current_engine then
      save_engine_choice(new_engine)
      norns.script.load(norns.state.script)
    end
  end)

  ----- TONE -----
  params:add_group("TONE", 10)

  params:add_control("master_amp", "body amp",
    controlspec.new(0.1, 1.5, 'lin', 0, 0.96, ''))
  params:add_number("body_tone", "body tone", 240, 2200, 760)
  params:set_action("body_tone", function(x) engine.body_tone(x) end)
  params:add_control("body_mix", "body mix",
    controlspec.new(0, 1, 'lin', 0, 0.35, ''))
  params:set_action("body_mix", function(x) engine.body_mix(x) end)
  params:add_control("brightness", "brightness",
    controlspec.new(0, 1, 'lin', 0, 0.4, ''))
  params:set_action("brightness", function(x) engine.brightness_amt(x) end)
  params:add_control("decay_shape", "decay shape",
    controlspec.new(0.5, 1.8, 'lin', 0, 1.02, ''))
  params:add_control("finger_noise", "finger noise",
    controlspec.new(0.0, 0.35, 'lin', 0, 0.13, ''))
  params:set_action("finger_noise", function(x) engine.finger_amt(x) end)
  params:add_control("resonance", "sympathetic",
    controlspec.new(0.0, 0.5, 'lin', 0, 0.17, ''))
  params:set_action("resonance", function(x) engine.sympathetic_amt(x) end)
  params:add_control("pitch_drift", "pitch drift cents",
    controlspec.new(0.0, 12.0, 'lin', 0, 2.6, 'c'))
  params:set_action("pitch_drift", function(x) engine.drift_amt(x) end)
  params:add_control("reverb_mix", "reverb mix",
    controlspec.new(0, 0.6, 'lin', 0, 0.18, ''))
  params:set_action("reverb_mix", function(x) engine.reverb_mix(x) end)
  params:add_control("reverb_room", "reverb room",
    controlspec.new(0.1, 1, 'lin', 0, 0.55, ''))
  params:set_action("reverb_room", function(x) engine.reverb_room(x) end)

  -- AcidTest-specific tone params
  if current_engine == "AcidTest" then
    params:add_separator("ACID TONE")
    params:add_control("acid_delay_send", "delay send", controlspec.new(0, 1, "lin", 0.01, 0.2))
    params:add_control("acid_reverb_send", "reverb send", controlspec.new(0, 1, "lin", 0.01, 0.3))
    params:add_control("acid_delay_feedback", "delay feedback", controlspec.new(0, 0.95, "lin", 0.01, 0.4))
    params:add_control("acid_delay_beats", "delay beats", controlspec.new(0.25, 4, "lin", 0.25, 1))

    params:set_action("acid_delay_feedback", function(val)
      engine.acidTest_delay(60 / clock.get_tempo(), params:get("acid_delay_beats"), val)
    end)
    params:set_action("acid_delay_beats", function(val)
      engine.acidTest_delay(60 / clock.get_tempo(), val, params:get("acid_delay_feedback"))
    end)
  else
    -- UprightBass-specific params already added above
  end

  ----- PERSONALITY -----
  params:add_group("PERSONALITY", 2)

  params:add_control("solo_probability", "solo chance",
    controlspec.new(0.0, 0.3, 'lin', 0, 0.07, ''))
  params:add_control("trade_probability", "trade chance",
    controlspec.new(0.0, 0.3, 'lin', 0, 0.05, ''))

  ----- TEMPO TRAINER -----
  params:add_group("TEMPO TRAINER", 4)

  params:add_option("trainer_enabled", "tempo trainer", {"off", "on"}, 1)
  params:set_action("trainer_enabled", function(x)
    state.ramp_active = (x == 2)
    if state.ramp_active then
      state.clean_bars = 0
      state.last_rest_occurred = false
    end
  end)
  params:add_number("trainer_start_tempo", "start tempo", 60, 180, 120)
  params:add_number("trainer_bpm_increment", "bpm per 8 bars", 1, 10, 3)
  params:add_number("trainer_max_tempo", "max tempo", 80, 300, 200)

  ----- MIDI -----
  params:add_group("MIDI OUT", 2)

  params:add_option("midi_enabled", "midi out", {"off", "on"}, 1)
  params:add_number("midi_channel", "midi channel", 1, 16, 1)
  params:set_action("midi_channel", function(x) midi_channel = x end)

  ----- OP-XY -----
  params:add_group("OP-XY", 3)

  params:add_option("opxy_enabled", "OP-XY output", {"off", "on"}, 1)
  params:set_action("opxy_enabled", function(x) 
    opxy_enabled = (x == 2)
    if opxy_out == nil then
      opxy_out = midi.connect(params:get("opxy_device"))
    end
  end)
  params:add_number("opxy_device", "OP-XY MIDI device", 1, 4, 1)
  params:set_action("opxy_device", function(val)
    opxy_out = midi.connect(val)
  end)
  params:add_number("opxy_channel", "OP-XY channel", 1, 8, 2)
  params:set_action("opxy_channel", function(x) opxy_channel = x end)

  ----- INIT -----
  init_custom_chart()
  apply_root_offset(params:get("root"))
  rebuild_progression_map()

  clock.tempo = params:get("tempo")
  reset_player()
  transport_clock_id = clock.run(transport_loop)

  -- setup engine abstraction layer
  setup_engine_abstraction()

  -- defer engine setup so SC has time to load
  clock.run(function()
    clock.sleep(0.5)
    setup_engine_defaults()
  end)

  -- screen metro (10fps as specified)
  redraw_metro = metro.init(function()
    if screen_dirty then
      redraw()
      screen_dirty = false
    end
    if grid_dirty then
      grid_redraw()
    end
  end, 1 / 10)
  redraw_metro:start()
end

-------------------------------------------------
-- input (keys + encoders)
-------------------------------------------------
function key(n, z)
  if z == 0 then return end
  if n == 2 then
    if state.playing then
      state.playing = false
      midi_note_off()
      opxy_all_notes_off()
    else
      if params:get("trainer_enabled") == 2 then
        state.ramp_active = true
        state.clean_bars = 0
        state.last_rest_occurred = false
      end
      start_count_in()
    end
  elseif n == 3 then
    reset_player()
    if params:get("trainer_enabled") == 2 then
      state.ramp_active = true
      state.clean_bars = 0
      state.last_rest_occurred = false
    end
    start_count_in()
  end
  screen_dirty = true
end

function enc(n, d)
  if n == 1 then
    state.screen_page = clamp(state.screen_page + (d > 0 and 1 or -1), 1, #state.screen_pages)
  elseif n == 2 then
    params:delta("tempo", d)
  elseif n == 3 then
    params:delta("progression", d)
  end
  screen_dirty = true
end

-------------------------------------------------
-- screen drawing
-------------------------------------------------
local function draw_page_play()
  -- ==================
  -- STATUS STRIP (y 0-8): "WALKING" at level 4 left
  -- ==================
  screen.level(4)
  screen.move(2, 6)
  screen.text("WALKING")

  -- Current chord name at level 12 center
  local chord = get_current_chord()
  screen.level(12)
  screen.move(64, 6)
  screen.text_center(truncate_text(note_name_short(chord.root) .. " " .. chord.quality, 18))

  -- Beat pulse dot at x=124
  local beat_pulse_brightness = math.floor(state.beat_phase * 15)
  if beat_pulse_brightness > 2 then
    screen.level(beat_pulse_brightness)
    screen.circle(124, 4, 1)
    screen.fill()
  end

  -- Engine indicator at top-right
  local engine_label = current_engine == "UprightBass" and "UB" or "AT"
  screen.level(5)
  screen.move(126, 6)
  screen.text_right(engine_label)

  -- ==================
  -- LIVE ZONE (y 9-52): Melodic contour
  -- ==================
  draw_melodic_contour()

  -- ==================
  -- CONTEXT BAR (y 53-58)
  -- ==================
  -- Chord at level 8
  screen.level(8)
  screen.move(8, 55)
  screen.text(truncate_text(note_name(chord.root), 4))

  -- Approach mode at level 5
  screen.level(5)
  screen.move(45, 55)
  screen.text(truncate_text(state.section, 8))

  -- BPM at level 8 (bright when trainer active)
  local tempo_level = state.ramp_active and 15 or 8
  screen.level(tempo_level)
  screen.move(70, 55)
  screen.text(params:get("tempo") .. " bpm")

  -- Turnaround type at level 5
  screen.level(5)
  screen.move(105, 55)
  screen.text(truncate_text(turnaround_patterns[state.turnaround_type].name, 9))

  -- ==================
  -- TEMPO TRAINER INFO (right side)
  -- ==================
  if state.ramp_active then
    screen.level(4)
    screen.move(8, 20)
    screen.text("trainer: on")

    screen.move(8, 28)
    screen.text("target: " .. params:get("trainer_max_tempo"))

    screen.level(6)
    screen.move(8, 36)
    screen.text("clean: " .. state.clean_bars .. "/8")
  else
    -- Show basic play status
    screen.level(state.playing and 15 or 4)
    screen.move(8, 20)
    screen.text(state.playing and "PLAYING" or "STOPPED")

    screen.level(6)
    screen.move(8, 28)
    screen.text("bar " .. current_bar_in_form() .. "/" .. total_bars)

    screen.move(8, 36)
    screen.text("chorus " .. state.chorus)
  end

  -- Turnaround flash indicator
  if state.turnaround_flash and state.playing then
    screen.level(12)
    screen.rect(120, 20, 5, 5)
    screen.fill()
  end
end

local function draw_page_tone()
  screen.level(15)
  screen.move(4, 10)
  screen.text("TONE")

  local items = {
    {"body",    string.format("%.0f hz", params:get("body_tone"))},
    {"bright",  string.format("%.2f", params:get("brightness"))},
    {"finger",  string.format("%.2f", params:get("finger_noise"))},
    {"symp",    string.format("%.2f", params:get("resonance"))},
    {"drift",   string.format("%.1fc", params:get("pitch_drift"))},
    {"reverb",  string.format("%.2f", params:get("reverb_mix"))},
  }

  for i, item in ipairs(items) do
    screen.level(6)
    screen.move(4, 10 + i * 9)
    screen.text(truncate_text(item[1], 6))
    screen.level(12)
    screen.move(50, 10 + i * 9)
    screen.text(truncate_text(item[2], 10))
  end

  -- page dots
  for i = 1, #state.screen_pages do
    if i == state.screen_page then screen.level(15) else screen.level(4) end
    screen.rect(56 + (i - 1) * 6, 62, 3, 2)
    screen.fill()
  end
end

local function draw_page_trainer()
  screen.level(15)
  screen.move(4, 10)
  screen.text("TEMPO TRAINER")

  screen.level(8)
  screen.move(4, 22)
  screen.text("trainer: " .. (state.ramp_active and "ON" or "off"))

  screen.move(4, 33)
  screen.text("start: " .. params:get("trainer_start_tempo") .. " bpm")

  screen.move(4, 44)
  screen.text("+" .. params:get("trainer_bpm_increment") .. " per 8 bars")

  screen.move(4, 55)
  screen.text("max: " .. params:get("trainer_max_tempo") .. " bpm")

  if state.ramp_active then
    screen.level(12)
    screen.move(82, 22)
    screen.text("current: " .. params:get("tempo"))
    screen.level(6)
    screen.move(82, 33)
    screen.text("clean: " .. state.clean_bars .. "/8")
    screen.move(82, 44)
    screen.text("chorus " .. state.ramp_choruses_done)
  end

  -- midi status
  screen.level(6)
  screen.move(82, 55)
  screen.text("midi " .. (params:get("midi_enabled") == 2 and "on" or "off"))

  -- page dots
  for i = 1, #state.screen_pages do
    if i == state.screen_page then screen.level(15) else screen.level(4) end
    screen.rect(56 + (i - 1) * 6, 62, 3, 2)
    screen.fill()
  end
end

function redraw()
  screen.clear()
  if state.screen_page == 1 then
    draw_page_play()
  elseif state.screen_page == 2 then
    draw_page_tone()
  elseif state.screen_page == 3 then
    draw_page_trainer()
  end
  screen.update()
end

-------------------------------------------------
-- cleanup
-------------------------------------------------
function cleanup()
  if transport_clock_id then clock.cancel(transport_clock_id) end
  state.playing = false
  midi_note_off()
  opxy_all_notes_off()
  if eng.kill_all then eng.kill_all() end
  if midi_out then for ch=1,16 do midi_out:cc(123,0,ch) end end
  if redraw_metro then
    redraw_metro:stop()
  end
end

-------------------------------------------------
-- external transport (Link / MIDI clock)
-------------------------------------------------
function clock.transport.start()
  start_count_in()
  screen_dirty = true
end

function clock.transport.stop()
  state.playing = false
  midi_note_off()
  opxy_all_notes_off()
  screen_dirty = true
end