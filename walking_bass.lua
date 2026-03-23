-- walking_bass
-- v5: jazz walking bass
--
-- jazz walking bass generator
-- for drum practice.
--
-- MollyThePoly engine,
-- grid progression builder,
-- tempo trainer, MIDI out.
--
-- E1 = page (PLAY/FORM/SOUND)
-- K2 = start/stop (4-beat count-in)
-- K3 = reset + play
--
-- grid:
--   rows 1-6 = chord slots (x=bar, y=root)
--   row 7    = quality toggle per bar
--   row 8    = transport + page

-------------------------------------------------
-- Engine (must be at file top level)
-------------------------------------------------
engine.name = "MollyThePoly"

local MollyThePoly = require "molly_the_poly/lib/molly_the_poly_engine"
local MusicUtil = require "musicutil"

-------------------------------------------------
-- constants
-------------------------------------------------
local NUM_BARS_MAX = 16

local BRIGHT = {
  OFF    = 0,
  GHOST  = 2,
  DIM    = 4,
  MID    = 8,
  BRIGHT = 12,
  FULL   = 15,
}

-------------------------------------------------
-- JAZZ STYLES
-------------------------------------------------
local STYLES = {
  -- Historical jazz eras
  { name = "SWING ERA",       -- 1930s-40s: Count Basie, Duke Ellington
    bpm = 145, swing = 0.22, ghost_pct = 0.15, organ_pct = 0.70,
    oct_pct = 0.08, rest_pct = 0.03, eighth_pct = 0.08,
    cutoff_base = 900, release_base = 1.0 },
  { name = "BEBOP",           -- 1940s-50s: Charlie Parker, Dizzy, Mingus
    bpm = 190, swing = 0.08, ghost_pct = 0.35, organ_pct = 0.35,
    oct_pct = 0.22, rest_pct = 0.10, eighth_pct = 0.35,
    cutoff_base = 2200, release_base = 0.3 },
  { name = "COOL JAZZ",       -- 1950s: Miles (Birth of Cool), Chet Baker, Bill Evans
    bpm = 108, swing = 0.12, ghost_pct = 0.18, organ_pct = 0.60,
    oct_pct = 0.10, rest_pct = 0.08, eighth_pct = 0.10,
    cutoff_base = 1000, release_base = 1.1 },
  { name = "HARD BOP",        -- 1955-65: Art Blakey, Horace Silver, Cannonball
    bpm = 155, swing = 0.18, ghost_pct = 0.28, organ_pct = 0.55,
    oct_pct = 0.15, rest_pct = 0.05, eighth_pct = 0.20,
    cutoff_base = 1500, release_base = 0.6 },
  { name = "MODAL",           -- 1959-65: Miles (Kind of Blue), Coltrane
    bpm = 120, swing = 0.14, ghost_pct = 0.20, organ_pct = 0.65,
    oct_pct = 0.12, rest_pct = 0.06, eighth_pct = 0.12,
    cutoff_base = 1100, release_base = 0.9 },
  { name = "FREE",            -- 1960s: Ornette Coleman, Cecil Taylor, late Coltrane
    bpm = 95, swing = 0.04, ghost_pct = 0.42, organ_pct = 0.70,
    oct_pct = 0.30, rest_pct = 0.18, eighth_pct = 0.30,
    cutoff_base = 2000, release_base = 0.5 },
  { name = "FUSION",          -- 1970s: Weather Report, Herbie, Return to Forever
    bpm = 130, swing = 0.06, ghost_pct = 0.30, organ_pct = 0.45,
    oct_pct = 0.20, rest_pct = 0.06, eighth_pct = 0.25,
    cutoff_base = 2500, release_base = 0.4 },
  { name = "SOUL JAZZ",       -- Jimmy Smith, Grant Green, Wes Montgomery
    bpm = 92, swing = 0.25, ghost_pct = 0.18, organ_pct = 0.85,
    oct_pct = 0.08, rest_pct = 0.04, eighth_pct = 0.06,
    cutoff_base = 800, release_base = 1.3 },
  { name = "LATIN",           -- Afro-Cuban, bossa: Jobim, Cal Tjader
    bpm = 128, swing = 0.03, ghost_pct = 0.28, organ_pct = 0.50,
    oct_pct = 0.18, rest_pct = 0.03, eighth_pct = 0.22,
    cutoff_base = 1400, release_base = 0.5 },
  { name = "BALLAD",          -- slow standards: My Funny Valentine, In a Sentimental Mood
    bpm = 68, swing = 0.20, ghost_pct = 0.12, organ_pct = 0.80,
    oct_pct = 0.06, rest_pct = 0.02, eighth_pct = 0.04,
    cutoff_base = 700, release_base = 1.8 },
  { name = "NEO SOUL",        -- D'Angelo, Erykah Badu, Robert Glasper
    bpm = 82, swing = 0.28, ghost_pct = 0.22, organ_pct = 0.75,
    oct_pct = 0.10, rest_pct = 0.06, eighth_pct = 0.08,
    cutoff_base = 850, release_base = 1.4 },
  { name = "MORPHING",        -- auto-evolves between all styles
    bpm = 120, swing = 0.15, ghost_pct = 0.25, organ_pct = 0.6,
    oct_pct = 0.15, rest_pct = 0.08, eighth_pct = 0.15,
    cutoff_base = 1200, release_base = 0.8 },
}
local current_style = 1
local morph_clock_id = nil
local morph_target = {}
local morph_progress = 0

local function get_style()
  return STYLES[current_style]
end

local function apply_style(s)
  -- immediate tempo change
  clock.tempo = s.bpm
  -- immediate sound change
  state.brightness_base = s.cutoff_base
  params:set("lp_filter_cutoff", s.cutoff_base)
  params:set("env_2_release", s.release_base)
  -- update swing
  swing_amount = s.swing
end

local function start_morphing()
  if morph_clock_id then return end
  morph_clock_id = clock.run(function()
    while true do
      clock.sleep(rrange(12, 30))  -- morph every 12-30 seconds
      -- pick random target style (not MORPHING itself)
      local target_idx = math.random(1, #STYLES - 1)
      local target = STYLES[target_idx]
      local source = get_style()
      -- gradually interpolate over 4 seconds
      for step = 1, 20 do
        local t = step / 20
        STYLES[#STYLES].bpm = math.floor(source.bpm + (target.bpm - source.bpm) * t)
        STYLES[#STYLES].swing = source.swing + (target.swing - source.swing) * t
        STYLES[#STYLES].ghost_pct = source.ghost_pct + (target.ghost_pct - source.ghost_pct) * t
        STYLES[#STYLES].organ_pct = source.organ_pct + (target.organ_pct - source.organ_pct) * t
        STYLES[#STYLES].oct_pct = source.oct_pct + (target.oct_pct - source.oct_pct) * t
        STYLES[#STYLES].rest_pct = source.rest_pct + (target.rest_pct - source.rest_pct) * t
        STYLES[#STYLES].eighth_pct = source.eighth_pct + (target.eighth_pct - source.eighth_pct) * t
        STYLES[#STYLES].cutoff_base = source.cutoff_base + (target.cutoff_base - source.cutoff_base) * t
        STYLES[#STYLES].release_base = source.release_base + (target.release_base - source.release_base) * t
        STYLES[#STYLES].name = ">" .. target.name:sub(1, 6)
        apply_style(STYLES[#STYLES])
        clock.sleep(0.2)
      end
      -- snap to target
      for k, v in pairs(target) do STYLES[#STYLES][k] = v end
      STYLES[#STYLES].name = ">" .. target.name:sub(1, 6)
    end
  end)
end

local function stop_morphing()
  if morph_clock_id then
    clock.cancel(morph_clock_id)
    morph_clock_id = nil
  end
end

local QUALITY_LIST = {
  "ionian", "dorian", "mixolydian", "aeolian",
  "melodic_minor", "phrygian", "locrian", "lydian"
}
local QUALITY_SHORT = {
  "ion", "dor", "mix", "aeo", "mel", "phr", "loc", "lyd"
}
local QUALITY_CHORD_NAME = {
  ionian        = "maj7",
  dorian        = "m7",
  mixolydian    = "7",
  aeolian       = "m7",
  melodic_minor = "mM7",
  phrygian      = "m7",
  locrian       = "m7b5",
  lydian        = "maj7",
}

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

local NOTE_NAMES = {"C","C#","D","Eb","E","F","F#","G","Ab","A","Bb","B"}

-------------------------------------------------
-- sound presets
-------------------------------------------------
local PRESETS = {
  {
    name = "Upright",
    osc_wave_shape = 0.1, lp_filter_cutoff = 1200,
    lp_filter_resonance = 0.1,
    env_2_attack = 0.008, env_2_decay = 0.5,
    env_2_sustain = 0.3, env_2_release = 0.8,
    sub_osc_level = 0.2, noise_level = 0.02,
  },
  {
    name = "Electric",
    osc_wave_shape = 0.4, lp_filter_cutoff = 2400,
    lp_filter_resonance = 0.2,
    env_2_attack = 0.003, env_2_decay = 0.3,
    env_2_sustain = 0.5, env_2_release = 0.4,
    sub_osc_level = 0.1, noise_level = 0.01,
  },
  {
    name = "Synth",
    osc_wave_shape = 0.7, lp_filter_cutoff = 3000,
    lp_filter_resonance = 0.3,
    env_2_attack = 0.001, env_2_decay = 0.2,
    env_2_sustain = 0.6, env_2_release = 0.3,
    sub_osc_level = 0.05, noise_level = 0.0,
  },
  {
    name = "Sub",
    osc_wave_shape = 0.05, lp_filter_cutoff = 600,
    lp_filter_resonance = 0.05,
    env_2_attack = 0.01, env_2_decay = 0.8,
    env_2_sustain = 0.5, env_2_release = 1.5,
    sub_osc_level = 0.5, noise_level = 0.0,
  },
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
  direction = 1,
  -- phrase memory
  phrase_memory = {},
  motif = {},
  motif_age = 0,
  -- feel
  density = 0.85,
  rest_streak = 0,
  -- screen
  page = 1,
  pages = {"PLAY", "FORM", "SOUND", "STYLE"},
  -- sound
  preset_idx = 1,
  brightness_base = 1200,
  body_release = 0.8,
  -- tempo trainer
  ramp_active = false,
  ramp_choruses_done = 0,
  clean_bars = 0,
  last_rest_occurred = false,
}

-------------------------------------------------
-- note history for melodic contour
-------------------------------------------------
local note_history = {}
local MAX_HISTORY = 16

-------------------------------------------------
-- progression data
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

-------------------------------------------------
-- grid state
-------------------------------------------------
local g = grid.connect()
local grid_page = 1
local grid_dirty = true

local custom_chart = {}

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
local opxy_channel = 2

-------------------------------------------------
-- voice / clock tracking
-------------------------------------------------
local next_voice_id = 1
local transport_clock_id = nil
local redraw_metro = nil
local screen_dirty = true

-------------------------------------------------
-- swing param (0.0 - 0.3)
-------------------------------------------------
local swing_amount = 0.15

-------------------------------------------------
-- utilities
-------------------------------------------------
local function clamp(x, lo, hi)
  return math.max(lo, math.min(hi, x))
end

local function chance(p)
  return math.random() < p
end

local function rrange(a, b)
  return a + math.random() * (b - a)
end

local function sign(x)
  if x < 0 then return -1 elseif x > 0 then return 1 else return 0 end
end

local function round(x)
  return math.floor(x + 0.5)
end

local function note_name(n)
  return NOTE_NAMES[(n % 12) + 1]
end

local function note_name_oct(n)
  local oct = math.floor(n / 12) - 1
  return note_name(n) .. oct
end

local function chord_display_name(chord)
  local name = note_name(chord.root)
  local suffix = QUALITY_CHORD_NAME[chord.quality] or ""
  return name .. suffix
end

local function truncate(str, max_len)
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
  if total_bars < 1 then return 1 end
  return ((state.bar - 1) % total_bars) + 1
end

local function get_current_chord()
  return progression_bar_map[current_bar_in_form()]
    or {root = 36, quality = "ionian", dur = 1}
end

local function get_next_chord()
  local next_bar = (current_bar_in_form() % total_bars) + 1
  return progression_bar_map[next_bar]
    or {root = 36, quality = "ionian", dur = 1}
end

local function get_scale_for_chord(chord)
  local scale_name = quality_to_scale[chord.quality] or "Major"
  return MusicUtil.generate_scale_of_length(chord.root, scale_name, 16)
end

local function note_in_range(note)
  local lo = params:get("low_note")
  local hi = params:get("high_note")
  while note < lo do note = note + 12 end
  while note > hi do note = note - 12 end
  if note < lo then note = lo end
  if note > hi then note = hi end
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
  table.insert(note_history, 1, {note = note, approach = is_approach or false})
  while #note_history > MAX_HISTORY do
    table.remove(note_history)
  end
end

-------------------------------------------------
-- custom chart <-> progression
-------------------------------------------------
local function build_custom_from_grid()
  if #custom_chart == 0 then return end
  local chords = {}
  local i = 1
  while i <= #custom_chart do
    local c = custom_chart[i]
    local dur = 1
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
-- OP-XY helpers
-------------------------------------------------
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

local function opxy_all_notes_off()
  if opxy_out and opxy_enabled then
    opxy_out:cc(123, 0, opxy_channel)
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
-- sound preset application
-------------------------------------------------
local function apply_preset(idx)
  local p = PRESETS[idx]
  if not p then return end
  state.preset_idx = idx
  params:set("osc_wave_shape", p.osc_wave_shape)
  params:set("lp_filter_cutoff", p.lp_filter_cutoff)
  params:set("lp_filter_resonance", p.lp_filter_resonance)
  params:set("env_2_attack", p.env_2_attack)
  params:set("env_2_decay", p.env_2_decay)
  params:set("env_2_sustain", p.env_2_sustain)
  params:set("env_2_release", p.env_2_release)
  params:set("sub_osc_level", p.sub_osc_level)
  params:set("noise_level", p.noise_level)
  state.brightness_base = p.lp_filter_cutoff
  state.body_release = p.env_2_release
end

-------------------------------------------------
-- per-note filter shaping
-------------------------------------------------
-- lightweight filter shape (no params:set per note)
local last_filter_set = 0
local function shape_note_filter(note)
  local now = os.clock()
  if now - last_filter_set < 0.2 then return end  -- throttle to 5hz max
  last_filter_set = now
  local lo = 36
  local hi = 72
  local pos = clamp((note - lo) / (hi - lo), 0, 1)
  local cutoff = clamp(state.brightness_base * (0.5 + pos * 1.5), 400, 5000)
  params:set("lp_filter_cutoff", cutoff)
end

-------------------------------------------------
-- voice management (12-voice rotation)
-------------------------------------------------
local function get_voice_id()
  local vid = next_voice_id
  next_voice_id = (next_voice_id % 8) + 1
  return vid
end

-------------------------------------------------
-- note trigger (engine + MIDI + OP-XY)
-------------------------------------------------
local function perform_note(note, vel_float, duration_sec)
  local freq = MusicUtil.note_num_to_freq(note)
  local vel = clamp(vel_float, 0.05, 1.0)

  -- shape filter per note register
  shape_note_filter(note)

  -- ALL LAYERS IN ONE COROUTINE (saves CPU)
  local sty = get_style()
  local step_in_bar = ((state.beat - 1) % 4) + 1
  local do_ghost = chance(sty.ghost_pct)
  local do_oct = chance(sty.oct_pct)
  local do_organ = chance(sty.organ_pct) and (step_in_bar == 1 or step_in_bar == 3)

  -- LAYER 1: Root walker (immediate)
  local vid = get_voice_id()
  engine.noteOn(vid, freq, vel)

  -- LAYER 2: Ghost (immediate, no delay)
  local ghost_vid = nil
  if do_ghost then
    local gi = ({-1, 1, -2, 2, 7})[math.random(5)]
    ghost_vid = get_voice_id()
    engine.noteOn(ghost_vid, MusicUtil.note_num_to_freq(note + gi), vel * 0.2)
  end

  -- LAYER 3: Octave pop (immediate)
  local oct_vid = nil
  if do_oct then
    local oct_note = note + ({-12, 12, 19})[math.random(3)]
    if oct_note >= 24 and oct_note <= 96 then
      oct_vid = get_voice_id()
      engine.noteOn(oct_vid, MusicUtil.note_num_to_freq(oct_note), vel * 0.15)
    end
  end

  -- LAYER 4: Organ (immediate, 2 notes)
  local organ_vids = {}
  local organ_notes = {}
  if do_organ then
    local chord = get_current_chord()
    if chord then
      local root = chord.root or note
      local voicings = {{3,10},{4,11},{4,10},{3,14},{7,10},{4,7}}
      local v = voicings[math.random(#voicings)]
      local chord_base = 60 + (root % 12)
      for _, interval in ipairs(v) do
        local cn = chord_base + interval
        if cn <= 84 then
          local cvid = get_voice_id()
          engine.noteOn(cvid, MusicUtil.note_num_to_freq(cn), vel * 0.12)
          table.insert(organ_vids, cvid)
          table.insert(organ_notes, cn)
          -- MIDI organ
          if midi_out then midi_out:note_on(cn, math.floor(vel * 15), math.min(16, midi_channel + 1)) end
          if opxy_out then opxy_out:note_on(cn, math.floor(vel * 15), math.min(8, params:get("opxy_channel") + 1)) end
        end
      end
    end
  end

  -- SINGLE coroutine for ALL note-offs
  clock.run(function()
    -- ghost off first (short)
    if ghost_vid then
      clock.sleep(0.08)
      engine.noteOff(ghost_vid)
    end
    -- octave off (very short)
    if oct_vid then
      clock.sleep(0.03)
      engine.noteOff(oct_vid)
    end
    -- main note off
    clock.sleep(math.max(0.05, duration_sec * 0.7))
    engine.noteOff(vid)
    -- organ off (longest)
    if #organ_vids > 0 then
      clock.sleep(0.3)
      for i, cvid in ipairs(organ_vids) do
        engine.noteOff(cvid)
        if midi_out then midi_out:note_off(organ_notes[i], 0, math.min(16, midi_channel + 1)) end
        if opxy_out then opxy_out:note_off(organ_notes[i], 0, math.min(8, params:get("opxy_channel") + 1)) end
      end
    end
  end)

  -- MIDI out
  midi_note_off()
  midi_note_on(note, math.floor(vel * 127))

  -- OP-XY out
  if state.last_opxy_note then
    opxy_note_off(state.last_opxy_note)
  end
  opxy_note_on(note, math.floor(vel * 127))
  state.last_opxy_note = note

  -- schedule MIDI/OPXY note-off
  if params:get("midi_enabled") == 2 or opxy_enabled then
    local off_note = note
    clock.run(function()
      clock.sleep(duration_sec * 0.9)
      midi_note_off()
      opxy_note_off(off_note)
    end)
  end
end

-------------------------------------------------
-- phrase memory / motif system
-------------------------------------------------
local function remember_interval(interval)
  table.insert(state.phrase_memory, interval)
  while #state.phrase_memory > 16 do
    table.remove(state.phrase_memory, 1)
  end
end

local function maybe_refresh_motif()
  if #state.phrase_memory < 4 then return end
  if #state.motif == 0 or state.motif_age > 12 or chance(0.12) then
    local len = math.random(3, 4)
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
  if not chance(0.20) then return nil end
  state.motif_age = state.motif_age + 1
  local ix = ((state.beat - 1) % #state.motif) + 1
  local interval = state.motif[ix]
  -- slight transposition variation
  if chance(0.2) then
    interval = interval + (chance(0.5) and 1 or -1)
  end
  return interval
end

-------------------------------------------------
-- note selection (the heart -- JAZZY)
-------------------------------------------------
local function choose_closest_chord_tone(next_chord)
  local tones = chord_tones(next_chord)
  local best = tones[1]
  local best_dist = 999
  for _, tone in ipairs(tones) do
    for _, offset in ipairs({-12, 0, 12}) do
      local c = tone + offset
      local d = math.abs(c - state.last_note)
      if d < best_dist then
        best = c
        best_dist = d
      end
    end
  end
  return note_in_range(best)
end

local function chromatic_approach(target)
  -- half step above then below, or vice versa
  if chance(0.5) then
    return target + 1, target - 1
  else
    return target - 1, target + 1
  end
end

local function build_walk_note(step_in_bar, chord, next_chord)
  local scale = get_scale_for_chord(chord)
  local tones = chord_tones(chord)
  local candidates = {}

  local function add(n, w)
    n = note_in_range(n)
    local leap = math.abs(n - state.last_note)
    -- penalize big leaps
    if leap > 10 then w = w * 0.15 end
    -- penalize repeated notes
    if leap == 0 then w = w * 0.2 end
    -- favor continuing direction
    if sign(n - state.last_note) == state.direction and leap > 0 then
      w = w * 1.1
    end
    table.insert(candidates, {n = n, w = w})
  end

  -- BEAT 1: Root priority (90%)
  if step_in_bar == 1 then
    add(chord.root, 9.0)
    add(chord.root + 12, 1.0)
    add(tones[3], 0.8)  -- fifth as alternative

  -- BEAT 2: Scale passing tones
  elseif step_in_bar == 2 then
    for _, n in ipairs(scale) do
      if n >= chord.root - 5 and n <= chord.root + 17 then
        add(n, 1.0)
      end
    end
    add(tones[2], 1.5)  -- third
    add(tones[4], 1.2)  -- seventh

  -- BEAT 3: Fifth priority (60%)
  elseif step_in_bar == 3 then
    add(tones[3], 4.0)  -- fifth
    add(tones[2], 2.0)  -- third
    add(tones[4], 1.5)  -- seventh
    add(chord.root, 1.0)
    for _, n in ipairs(scale) do
      if n >= chord.root - 3 and n <= chord.root + 14 then
        add(n, 0.6)
      end
    end

  -- BEAT 4: Approach patterns to next chord
  elseif step_in_bar == 4 and next_chord then
    local target = choose_closest_chord_tone(next_chord)

    -- scale-tone approach (step above or below target)
    add(target - 1, 3.5)  -- half step below
    add(target + 1, 3.0)  -- half step above
    add(target - 2, 2.5)  -- whole step below
    add(target + 2, 2.0)  -- whole step above

    -- dominant approach (fifth of next chord)
    add(next_chord.root + 7, 1.5)

    -- chromatic approach
    add(target - 1, 2.0)
    add(target + 1, 1.8)

    -- also allow scale tones
    for _, n in ipairs(scale) do
      if n >= chord.root - 3 and n <= chord.root + 14 then
        add(n, 0.4)
      end
    end
  end

  -- motif callback (20% chance to replay transposed phrase fragment)
  local hint = motif_hint()
  if hint then
    add(state.last_note + hint, 2.0)
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

  local interval = chosen - state.last_note
  -- update direction tendency
  if math.abs(interval) >= 5 and chance(0.6) then
    state.direction = -sign(interval)
  elseif interval ~= 0 then
    state.direction = sign(interval)
  end

  return chosen, interval
end

-------------------------------------------------
-- rhythm / velocity / feel
-------------------------------------------------
local function should_rest(step_in_bar)
  local base_p = (1.0 - state.density) * 0.2
  -- never rest on beat 1
  if step_in_bar == 1 then return false end
  -- 8% rest on beat 3
  if step_in_bar == 3 then base_p = base_p + 0.08 end
  -- don't rest twice in a row often
  if state.rest_streak > 0 then base_p = base_p * 0.2 end
  local rest = chance(base_p)
  if rest then
    state.rest_streak = state.rest_streak + 1
  else
    state.rest_streak = 0
  end
  return rest
end

local function beat_velocity(step_in_bar)
  -- beat 1 strongest, beat 3 medium, beats 2&4 softer
  local accents = {1.0, 0.75, 0.88, 0.72}
  local base = 0.7 * accents[step_in_bar]
  -- random variation +/- 10%
  base = base + rrange(-0.07, 0.07)
  return clamp(base, 0.2, 1.0)
end

local function beat_duration()
  -- quarter note duration from clock tempo
  local tempo = clock.get_tempo()
  if tempo <= 0 then tempo = 120 end
  return 60.0 / tempo
end

local function swing_delay(step_in_bar)
  -- apply swing on even beats (2 and 4)
  if step_in_bar % 2 == 0 then
    return swing_amount * beat_duration()
  end
  return 0
end

local function human_delay()
  -- 10-30ms random timing offset
  return rrange(0.01, 0.03)
end

-------------------------------------------------
-- chromatic enclosure (bebop approach)
-------------------------------------------------
local function do_chromatic_enclosure(target, vel)
  -- on beat 4 approaching chord change:
  -- half-step-above then half-step-below target root
  local above = target + 1
  local below = target - 1
  local dur = beat_duration() * 0.45

  local freq_a = MusicUtil.note_num_to_freq(above)
  local freq_b = MusicUtil.note_num_to_freq(below)
  local enc_vel = clamp(vel * 0.6, 0.1, 0.6)

  local vid_a = get_voice_id()
  engine.noteOn(vid_a, freq_a, enc_vel)
  clock.run(function()
    clock.sleep(dur * 0.4)
    engine.noteOff(vid_a)
  end)

  clock.run(function()
    clock.sleep(dur * 0.5)
    local vid_b = get_voice_id()
    engine.noteOn(vid_b, freq_b, enc_vel)
    clock.sleep(dur * 0.4)
    engine.noteOff(vid_b)
  end)

  remember_note(above, true)
  remember_note(below, true)
end

-------------------------------------------------
-- 8th note pickup
-------------------------------------------------
local function do_eighth_pickup(note1, note2, vel)
  local dur = beat_duration() * 0.48
  perform_note(note1, vel * 0.8, dur)
  clock.run(function()
    clock.sync(0.5)
    perform_note(note2, vel * 0.9, dur)
  end)
end

-------------------------------------------------
-- tempo trainer
-------------------------------------------------
local function tempo_trainer_check()
  if not state.ramp_active then return end

  if not state.last_rest_occurred then
    state.clean_bars = state.clean_bars + 1
  else
    state.clean_bars = 0
  end
  state.last_rest_occurred = false

  if state.clean_bars >= 8 then
    state.clean_bars = 0
    local increment = params:get("trainer_increment")
    local max_tempo = params:get("trainer_max_tempo")
    local cur = clock.get_tempo()
    local new_tempo = math.min(cur + increment, max_tempo)
    params:set("clock_tempo", new_tempo)
    if new_tempo >= max_tempo then
      state.ramp_active = false
    end
    state.ramp_choruses_done = state.ramp_choruses_done + 1
  end
end

-------------------------------------------------
-- count-in (4 beats with clicks)
-------------------------------------------------
local function engine_click(freq, amp)
  local vid = get_voice_id()
  engine.noteOn(vid, freq, clamp(amp, 0.1, 1.0))
  clock.run(function()
    clock.sleep(0.04)
    engine.noteOff(vid)
  end)
end

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
-- play step (the main beat callback)
-------------------------------------------------
local function play_step()
  local chord = get_current_chord()
  local next_chord = get_next_chord()
  local step_in_bar = ((state.beat - 1) % 4) + 1

  -- rest logic
  if should_rest(step_in_bar) then
    state.last_rest_occurred = true
    screen_dirty = true
    grid_dirty = true
    return
  end

  -- check for chord change on next bar (beat 4)
  local is_approaching_change = (step_in_bar == 4)
    and (next_chord.root ~= chord.root or next_chord.quality ~= chord.quality)

  -- chromatic enclosure: beat 4, approaching chord change, ~20% chance
  if is_approaching_change and chance(0.20) then
    local target = choose_closest_chord_tone(next_chord)
    local vel = beat_velocity(step_in_bar)
    do_chromatic_enclosure(target, vel)
    state.last_note = target
    remember_interval(target - state.last_note)
    screen_dirty = true
    grid_dirty = true
    return
  end

  -- 8th note pickup: ~15% on beat 4
  if step_in_bar == 4 and chance(0.15) then
    local note1, int1 = build_walk_note(step_in_bar, chord, next_chord)
    local note2
    if next_chord then
      note2 = choose_closest_chord_tone(next_chord)
    else
      note2 = note1 + (chance(0.5) and 1 or -1)
    end
    note2 = note_in_range(note2)
    local vel = beat_velocity(step_in_bar)
    do_eighth_pickup(note1, note2, vel)
    state.last_note = note2
    remember_interval(int1)
    remember_interval(note2 - note1)
    remember_note(note1, false)
    remember_note(note2, false)
    screen_dirty = true
    grid_dirty = true
    return
  end

  -- normal walk note
  local note, interval = build_walk_note(step_in_bar, chord, next_chord)
  local vel = beat_velocity(step_in_bar)
  local dur = beat_duration() * 0.85

  -- apply swing delay on even beats
  local sw = swing_delay(step_in_bar)
  local hd = human_delay()

  state.last_note = note
  remember_interval(interval)
  remember_note(note, false)

  clock.run(function()
    if sw + hd > 0.001 then
      clock.sleep(sw + hd)
    end
    perform_note(note, vel, dur)
  end)

  screen_dirty = true
  grid_dirty = true
end

-------------------------------------------------
-- form advancement
-------------------------------------------------
local function advance_form()
  if state.beat % 4 == 0 then
    state.bar = state.bar + 1
    if current_bar_in_form() == 1 then
      state.chorus = state.chorus + 1
      tempo_trainer_check()
    end
    maybe_refresh_motif()
  end
end

-------------------------------------------------
-- transport loop
-------------------------------------------------
local function transport_loop()
  while true do
    clock.sync(1)
    if state.playing then
      state.beat = state.beat + 1
      play_step()
      advance_form()
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
  state.direction = 1
  state.phrase_memory = {}
  state.motif = {}
  state.motif_age = 0
  state.density = 0.85
  state.rest_streak = 0
  state.ramp_choruses_done = 0
  state.clean_bars = 0
  state.last_rest_occurred = false
  note_history = {}
end

local function set_progression(ix)
  progression = progression_presets[ix]
  rebuild_progression_map()
  reset_player()
end

-------------------------------------------------
-- randomize progression order
-------------------------------------------------
local function randomize_progression()
  local chords = progression.chords
  if #chords < 2 then return end
  -- fisher-yates shuffle
  for i = #chords, 2, -1 do
    local j = math.random(1, i)
    chords[i], chords[j] = chords[j], chords[i]
  end
  rebuild_progression_map()
end

-------------------------------------------------
-- GRID: drawing
-------------------------------------------------
local function grid_redraw()
  if not g.device then return end
  g:all(0)

  if grid_page == 1 then
    -- FORM VIEW
    local form_bar = current_bar_in_form()
    local bars_to_show = math.min(total_bars, 16)

    for col = 1, bars_to_show do
      local chord = progression_bar_map[col]
      if chord then
        local root_mod = chord.root % 12
        local row = clamp(6 - math.floor(root_mod / 2), 1, 6)
        local bright = BRIGHT.MID
        if state.playing and col == form_bar then
          bright = BRIGHT.FULL
        end
        g:led(col, row, bright)

        -- quality indicator on row 7
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
      for col = 1, bars_to_show do
        if col == form_bar then
          g:led(col, 8, BRIGHT.BRIGHT)
        else
          g:led(col, 8, BRIGHT.GHOST)
        end
      end
    end

  elseif grid_page == 2 then
    -- CUSTOM CHART EDITOR
    local root_midi = {36, 38, 40, 41, 43, 45}

    for col = 1, math.min(#custom_chart, 16) do
      local c = custom_chart[col]
      for row = 1, 6 do
        local midi_val = root_midi[7 - row]
        if c.root % 12 == midi_val % 12 then
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

    -- row 8: chart length
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
        midi_note_off()
        opxy_all_notes_off()
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
    local root_midi = {36, 38, 40, 41, 43, 45}

    -- row 8 col 16 = back to form
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
    -- row 8 col 14 = remove bar
    if y == 8 and x == 14 then
      if #custom_chart > 1 then
        table.remove(custom_chart)
        build_custom_from_grid()
        grid_dirty = true
        screen_dirty = true
      end
      return
    end
    -- rows 1-6: set root
    if y >= 1 and y <= 6 and x <= #custom_chart then
      custom_chart[x].root = root_midi[7 - y]
      build_custom_from_grid()
      grid_dirty = true
      screen_dirty = true
      return
    end
    -- row 7: cycle quality
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
-- melodic contour visualization
-------------------------------------------------
local function draw_contour()
  if #note_history == 0 then return end

  local start_x = 4
  local end_x = 124
  local width = end_x - start_x
  local top_y = 22
  local bot_y = 48
  local height = bot_y - top_y

  -- find note range in history
  local lo = 999
  local hi = 0
  for _, entry in ipairs(note_history) do
    if entry.note < lo then lo = entry.note end
    if entry.note > hi then hi = entry.note end
  end
  local range = hi - lo
  if range < 6 then
    lo = lo - 3
    hi = hi + 3
    range = hi - lo
  end

  -- draw connecting lines then dots
  for i = 1, #note_history do
    local entry = note_history[i]
    local x = end_x - ((i - 1) / (MAX_HISTORY - 1)) * width
    local y = bot_y - ((entry.note - lo) / range) * height

    -- line to next
    if i < #note_history then
      local nx = end_x - (i / (MAX_HISTORY - 1)) * width
      local ny = bot_y - ((note_history[i + 1].note - lo) / range) * height
      local line_lv = clamp(15 - i, 2, 10)
      screen.level(line_lv)
      screen.move(x, y)
      screen.line(nx, ny)
      screen.stroke()
    end

    -- dot
    local dot_lv = clamp(15 - i, 3, 15)
    screen.level(dot_lv)
    local sz = entry.approach and 1 or 2
    if i == 1 then sz = 3 end
    screen.circle(x, y, sz)
    screen.fill()
  end
end

-------------------------------------------------
-- SCREEN: PLAY page
-------------------------------------------------
local function draw_play()
  local chord = get_current_chord()
  local next_ch = get_next_chord()

  -- top: current chord LARGE
  screen.level(15)
  screen.font_face(1)
  screen.font_size(16)
  screen.move(4, 16)
  screen.text(chord_display_name(chord))

  -- next chord small to the right
  screen.font_size(8)
  screen.level(6)
  screen.move(90, 10)
  screen.text(chord_display_name(next_ch))

  -- arrow
  screen.level(4)
  screen.move(82, 8)
  screen.text(">")

  -- middle: contour
  screen.font_size(8)
  draw_contour()

  -- bottom bar
  screen.level(8)
  screen.move(4, 60)
  screen.text(current_bar_in_form() .. "/" .. total_bars)

  screen.level(6)
  screen.move(32, 60)
  screen.text(math.floor(clock.get_tempo()) .. "bpm")

  screen.level(5)
  screen.move(68, 60)
  screen.text("sw " .. math.floor(swing_amount * 100) .. "%")

  -- play/stop indicator
  screen.level(state.playing and 15 or 4)
  screen.move(104, 60)
  screen.text(state.playing and "PLAY" or "STOP")

  -- count-in indicator
  if state.counting_in then
    screen.level(15)
    screen.font_size(24)
    screen.move(60, 40)
    screen.text_center(tostring(state.count_in_beats_left + 1))
    screen.font_size(8)
  end
end

-------------------------------------------------
-- SCREEN: FORM page
-------------------------------------------------
local function draw_form()
  -- top: progression name
  screen.level(15)
  screen.font_size(12)
  screen.move(4, 14)
  screen.text(progression.name)
  screen.font_size(8)

  -- middle: chord chart as boxes
  local form_bar = current_bar_in_form()
  local bars = math.min(total_bars, 16)
  local box_w = math.floor(120 / math.max(bars, 1))
  if box_w > 20 then box_w = 20 end
  local box_h = 18
  local start_y = 22
  local start_x = 4

  for i = 1, bars do
    local ch = progression_bar_map[i]
    if ch then
      local x = start_x + (i - 1) * box_w
      local y = start_y

      -- wrap to second row if needed
      if i > 8 then
        x = start_x + (i - 9) * box_w
        y = start_y + box_h + 2
      end

      -- highlight current bar
      if state.playing and i == form_bar then
        screen.level(15)
        screen.rect(x, y, box_w - 1, box_h)
        screen.fill()
        screen.level(0)
      else
        screen.level(4)
        screen.rect(x, y, box_w - 1, box_h)
        screen.stroke()
        screen.level(10)
      end

      -- chord name inside box
      screen.move(x + 2, y + 12)
      screen.text(truncate(chord_display_name(ch), 5))
    end
  end

  -- bottom: root note, chorus count
  screen.level(7)
  screen.move(4, 60)
  screen.text("root: " .. note_name_oct(params:get("root")))

  screen.level(5)
  screen.move(64, 60)
  screen.text("chorus " .. state.chorus)

  -- trainer status
  if state.ramp_active then
    screen.level(12)
    screen.move(100, 60)
    screen.text("TRN")
  end
end

-------------------------------------------------
-- SCREEN: SOUND page
-------------------------------------------------
local function draw_sound()
  local preset = PRESETS[state.preset_idx]

  -- top: preset name large
  screen.level(15)
  screen.font_size(14)
  screen.move(4, 16)
  screen.text(preset.name)
  screen.font_size(8)

  -- brightness bar
  screen.level(6)
  screen.move(4, 30)
  screen.text("bright")
  screen.level(10)
  local brt_w = clamp((state.brightness_base - 400) / 3600 * 80, 2, 80)
  screen.rect(46, 24, brt_w, 6)
  screen.fill()
  screen.level(3)
  screen.rect(46, 24, 80, 6)
  screen.stroke()

  -- release bar
  screen.level(6)
  screen.move(4, 42)
  screen.text("body")
  screen.level(10)
  local rel_w = clamp(state.body_release / 2.0 * 80, 2, 80)
  screen.rect(46, 36, rel_w, 6)
  screen.fill()
  screen.level(3)
  screen.rect(46, 36, 80, 6)
  screen.stroke()

  -- layer indicators
  screen.level(8)
  screen.move(4, 56)
  screen.text("root")
  screen.level(5)
  screen.move(32, 56)
  screen.text("ghost")
  screen.level(4)
  screen.move(62, 56)
  screen.text("breath")

  -- page dots at bottom
  for i = 1, #state.pages do
    if i == state.page then screen.level(15) else screen.level(3) end
    screen.rect(54 + (i - 1) * 8, 62, 4, 2)
    screen.fill()
  end
end

-------------------------------------------------
-- SCREEN: STYLE page
-------------------------------------------------
local function draw_style()
  local s = get_style()
  screen.font_size(8)

  -- Header
  screen.level(15)
  screen.move(2, 7)
  screen.text("STYLE")
  screen.level(state.playing and 15 or 4)
  screen.move(108, 7)
  screen.text(state.playing and ">" or ".")
  -- morph indicator
  if current_style == #STYLES then
    screen.level(math.floor(math.sin(os.clock() * 3) * 5) + 10)
    screen.move(116, 7)
    screen.text("M")
  end
  screen.level(2)
  screen.move(0, 9)
  screen.line(128, 9)
  screen.stroke()

  -- Style list (show 5 styles centered on current)
  for i = -2, 2 do
    local idx = current_style + i
    if idx >= 1 and idx <= #STYLES then
      local y = 30 + i * 9
      if i == 0 then
        -- current style: highlighted
        screen.level(1)
        screen.rect(0, y - 6, 128, 9)
        screen.fill()
        screen.level(15)
        screen.move(4, y)
        screen.text(STYLES[idx].name)
        screen.level(8)
        screen.move(100, y)
        screen.text(STYLES[idx].bpm)
      else
        screen.level(4)
        screen.move(8, y)
        screen.text(STYLES[idx].name)
      end
    end
  end

  -- Bottom bar
  screen.level(2)
  screen.move(0, 55)
  screen.line(128, 55)
  screen.stroke()

  screen.level(6)
  screen.move(2, 63)
  screen.text("E2:style  E3:bpm")
  screen.level(current_style == #STYLES and 15 or 5)
  screen.move(88, 63)
  screen.text("K3:morph")

  -- page dots
  for i = 1, #state.pages do
    screen.level(i == state.page and 15 or 3)
    screen.rect(54 + (i - 1) * 8, 58, 4, 2)
    screen.fill()
  end
end

-------------------------------------------------
-- redraw (GLOBAL)
-------------------------------------------------
function redraw()
  screen.clear()
  screen.aa(0)
  screen.font_face(1)
  screen.font_size(8)

  if state.page == 1 then
    draw_play()
  elseif state.page == 2 then
    draw_form()
  elseif state.page == 3 then
    draw_sound()
  elseif state.page == 4 then
    draw_style()
  end

  screen.update()
end

-------------------------------------------------
-- input: keys + encoders
-------------------------------------------------
function key(n, z)
  if z == 0 then return end

  if n == 2 then
    -- K2: play/stop on all pages
    if state.playing then
      state.playing = false
      midi_note_off()
      opxy_all_notes_off()
      engine.noteKillAll()
    else
      if params:get("trainer_enabled") == 2 then
        state.ramp_active = true
        state.clean_bars = 0
        state.last_rest_occurred = false
      end
      start_count_in()
    end

  elseif n == 3 then
    if state.page == 4 then
      -- K3 on STYLE page: toggle morphing
      if current_style == #STYLES then
        stop_morphing()
        current_style = 1
        apply_style(get_style())
      else
        current_style = #STYLES
        apply_style(get_style())
        start_morphing()
      end
    else
      -- K3 on other pages: cycle pages
      state.page = (state.page % #state.pages) + 1
    end
  end

  screen_dirty = true
end

function enc(n, d)
  if n == 1 then
    -- E1: page-specific action
    if state.page == 1 then
      swing_amount = clamp(swing_amount + d * 0.01, 0, 0.3)
    elseif state.page == 2 then
      params:delta("progression", d)
    elseif state.page == 3 then
      state.preset_idx = clamp(state.preset_idx + d, 1, #PRESETS)
      apply_preset(state.preset_idx)
    elseif state.page == 4 then
      stop_morphing()
      current_style = clamp(current_style + d, 1, #STYLES)
      apply_style(get_style())
      if current_style == #STYLES then start_morphing() end
    end

  elseif n == 2 then
    if state.page == 1 then
      -- PLAY: swing amount
      swing_amount = clamp(swing_amount + d * 0.01, 0, 0.3)
    elseif state.page == 2 then
      -- FORM: select progression
      params:delta("progression", d)
    elseif state.page == 3 then
      -- SOUND: brightness
      state.brightness_base = clamp(state.brightness_base + d * 50, 400, 4000)
    elseif state.page == 4 then
      -- STYLE: select style
      stop_morphing()
      current_style = clamp(current_style + d, 1, #STYLES)
      apply_style(get_style())
      if current_style == #STYLES then start_morphing() end
    end

  elseif n == 3 then
    if state.page == 1 then
      -- PLAY: density (rest probability)
      state.density = clamp(state.density + d * 0.02, 0.5, 1.0)
    elseif state.page == 2 then
      -- FORM: root note
      params:delta("root", d)
    elseif state.page == 3 then
      -- SOUND: body (release)
      state.body_release = clamp(state.body_release + d * 0.05, 0.1, 2.0)
      params:set("env_2_release", state.body_release)
    elseif state.page == 4 then
      -- STYLE: fine-tune BPM within style
      local s = get_style()
      s.bpm = clamp(s.bpm + d, 50, 240)
      apply_style(s)
    end
  end

  screen_dirty = true
end

-------------------------------------------------
-- init
-------------------------------------------------
function init()
  math.randomseed(os.time())

  -- engine params
  MollyThePoly.add_params()

  -- MIDI setup
  midi_out = midi.connect(1)

  ----- PARAMS -----
  params:add_separator("WALKING BASS")

  params:add_option("progression", "progression",
    {"ii-V-I", "minor swing", "blues-ish", "custom"}, 1)
  params:set_action("progression", function(ix)
    set_progression(ix)
  end)

  params:add_number("root", "root note", 28, 52, 36,
    function(param) return note_name_oct(param:get()) end)
  params:set_action("root", function(x)
    apply_root_offset(x)
    rebuild_progression_map()
    reset_player()
  end)

  params:add_number("low_note", "lowest note", 24, 48, 28,
    function(param) return note_name_oct(param:get()) end)
  params:add_number("high_note", "highest note", 34, 60, 48,
    function(param) return note_name_oct(param:get()) end)

  ----- TEMPO TRAINER -----
  params:add_separator("TEMPO TRAINER")

  params:add_option("trainer_enabled", "tempo trainer", {"off", "on"}, 1)
  params:set_action("trainer_enabled", function(x)
    state.ramp_active = (x == 2)
    if state.ramp_active then
      state.clean_bars = 0
      state.last_rest_occurred = false
    end
  end)
  params:add_number("trainer_increment", "bpm per 8 bars", 1, 10, 3)
  params:add_number("trainer_max_tempo", "max tempo", 80, 300, 200)

  ----- MIDI -----
  params:add_separator("MIDI OUT")

  params:add_option("midi_enabled", "midi out", {"off", "on"}, 1)
  params:add_number("midi_channel", "midi channel", 1, 16, 1)
  params:set_action("midi_channel", function(x) midi_channel = x end)

  ----- OP-XY -----
  params:add_separator("OP-XY")

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
  reset_player()

  -- start transport clock
  transport_clock_id = clock.run(transport_loop)

  -- apply initial preset with delay for SC load
  clock.run(function()
    clock.sleep(0.5)
    apply_preset(1)
    -- test note
    local vid = get_voice_id()
    engine.noteOn(vid, 110, 0.5)
    clock.sleep(0.2)
    engine.noteOff(vid)
  end)

  -- screen metro (10fps)
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
-- cleanup
-------------------------------------------------
function cleanup()
  -- cancel tracked clock
  if transport_clock_id then
    clock.cancel(transport_clock_id)
  end
  -- stop metro
  if redraw_metro then
    redraw_metro:stop()
  end
  -- kill all engine voices
  engine.noteKillAll()
  -- MIDI cleanup
  midi_note_off()
  if midi_out then
    midi_out:cc(123, 0, 1)
  end
  -- OP-XY cleanup
  opxy_all_notes_off()
  -- grid clear
  if g.device then
    g:all(0)
    g:refresh()
  end
end
