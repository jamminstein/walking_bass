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

local MusicUtil = require \"musicutil\"

-------------------------------------------------
-- constants
-------------------------------------------------
local NUM_BARS_MAX = 16
local NUM_ROOTS = 6
local GRID_PAGES = {\"form\", \"mix\"}

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
local QUALITY_LIST = {\"ionian\", \"dorian\", \"mixolydian\", \"aeolian\", \"melodic_minor\", \"phrygian\", \"locrian\", \"lydian\"}
local QUALITY_SHORT = {\"ion\", \"dor\", \"mix\", \"aeo\", \"mel\", \"phr\", \"loc\", \"lyd\"}

local quality_to_scale = {
  ionian        = \"Major\",
  dorian        = \"Dorian\",
  mixolydian    = \"Mixolydian\",
  aeolian       = \"Natural Minor\",
  melodic_minor = \"Melodic Minor\",
  phrygian      = \"Phrygian\",
  locrian       = \"Locrian\",
  lydian        = \"Lydian\",
}

local ROOT_NAMES = {\"C\", \"D\", \"E\", \"F\", \"G\", \"A\"}

local NOTE_NAMES_FLAT = {\"C\", \"Db\", \"D\", \"Eb\", \"E\", \"F\", \"Gb\", \"G\", \"Ab\", \"A\", \"Bb\", \"B\"}

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
  section = \"support\",
  section_bars_left = 8,
  solo_mode = false,
  last_articulation = \"normal\",
  last_velocity = 72,
  rest_streak = 0,
  anticipation_bias = -0.002,
  drag_bias = 0.001,
  turnaround_flash = false,
  turnaround_type = 1,
  ramp_active = false,
  ramp_start_tempo = 120,
  ramp_choruses_done = 0,
  clean_bars = 0,
  last_rest_occurred = false,
  screen_page = 1,
  screen_pages = {\"play\", \"tone\", \"trainer\"},
  beat_phase = 0.0,
}

-------------------------------------------------
-- note history for melodic contour visualization
-------------------------------------------------
local note_history = {}
local max_history = 16

-------------------------------------------------
-- progression data
-------------------------------------------------
local progression_presets = {
  {
    name = \"ii-V-I\",
    chords = {
      {root = 38, quality = \"dorian\",     dur = 2},
      {root = 43, quality = \"mixolydian\", dur = 2},
      {root = 36, quality = \"ionian\",     dur = 4},
    }
  },
  {
    name = \"minor swing\",
    chords = {
      {root = 36, quality = \"dorian\",     dur = 4},
      {root = 41, quality = \"mixolydian\", dur = 2},
      {root = 43, quality = \"mixolydian\", dur = 2},
    }
  },
  {
    name = \"blues-ish\",
    chords = {
      {root = 36, quality = \"mixolydian\", dur = 4},
      {root = 41, quality = \"mixolydian\", dur = 2},
      {root = 36, quality = \"mixolydian\", dur = 2},
      {root = 43, quality = \"mixolydian\", dur = 2},
      {root = 41, quality = \"mixolydian\", dur = 2},
      {root = 36, quality = \"mixolydian\", dur = 4},
    }
  },
  {
    name = \"custom\",
    chords = {
      {root = 36, quality = \"ionian\", dur = 4},
    }
  },
}

local progression = progression_presets[1]
local progression_bar_map = {}
local total_bars = 0

local turnaround_patterns = {
  {name = \"classic\",    intervals = {{0, 4, 7, 10}, {0, 3, 7, 11}}},
  {name = \"tritone_sub\", intervals = {{0, 6, 7, 1},  {-1, 0, 5, 7}}},
  {name = \"coltrane\",    intervals = {{0, -1, -5, -7}, {0, 4, 7, 10}}},
  {name = \"backdoor\",    intervals = {{-2, -1, 0, 2}, {-4, -2, 0, 2}}},
}

-------------------------------------------------
-- grid state
-------------------------------------------------
local g = grid.connect()
local grid_page = 1
local grid_dirty = true
local custom_chart = {}
local grid_cursor_x = 1

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
local opxy_channel = 2

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
  return param:get() .. \" ms\"
end

local function fmt_note(param)
  return note_name(param:get())
end

local function truncate_text(str, max_len)
  if string.len(str) > max_len then
    return string.sub(str, 1, max_len - 1) .. \"~\"
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
    progression_bar_map[1] = {root = 36, quality = \"ionian\", dur = 1}
  end
end

local function current_bar_in_form()
  return ((state.bar - 1) % total_bars) + 1
end

local function get_current_chord()
  local chord_map = progression_bar_map[current_bar_in_form()]
  if not chord_map then
    return progression.chords[1] or {root = 36, quality = \"ionian\", dur = 1}
  end
  return chord_map
end

local function get_next_chord()
  local next_bar = (current_bar_in_form() % total_bars) + 1
  local chord_map = progression_bar_map[next_bar]
  if not chord_map then
    return progression.chords[1] or {root = 36, quality = \"ionian\", dur = 1}
  end
  return chord_map
end

local function get_scale_for_chord(chord)
  local scale_name = quality_to_scale[chord.quality] or \"Major\"
  return MusicUtil.generate_scale_of_length(chord.root, scale_name, 16)
end

local function note_in_range(note)
  local lo = params:get(\"low_note\")
  local hi = params:get(\"high_note\")
  if lo >= hi then return clamp(note, 28, 52) end
  while note < lo do note = note + 12 end
  while note > hi do note = note - 12 end
  if note < lo or note > hi then note = clamp(note, lo, hi) end
  return note
end

local function chord_tones(chord)
  local third = 4
  local q = chord.quality
  if q == \"dorian\" or q == \"aeolian\" or q == \"melodic_minor\"
    or q == \"phrygian\" or q == \"locrian\" then
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
-- custom chart
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
  if params:get(\"progression\") == 4 then
    progression = progression_presets[4]
    rebuild_progression_map()
  end
end

local function init_custom_chart()
  custom_chart = {}
  for i = 1, 8 do
    table.insert(custom_chart, {root = 36, quality = \"ionian\"})
  end
  build_custom_from_grid()
end

-------------------------------------------------
-- engine interface
-------------------------------------------------
local current_engine = read_engine_choice()
local eng = {}

local function engine_note(freq, amp, decay, articulation_name)
  if eng.note_on then
    eng.note_on(freq, amp, decay, articulation_name)
  else
    local artic = ARTICULATION[articulation_name] or 0
    engine.note(freq, amp, decay, artic)
  end
end

local function engine_click(freq, amp)
  if current_engine == \"UprightBass\" then
    engine.click(freq, amp)
  end
end

local function setup_engine_defaults()
  if current_engine == \"UprightBass\" then
    engine.body_tone(params:get(\"body_tone\"))
    engine.body_mix(params:get(\"body_mix\"))
    engine.finger_amt(params:get(\"finger_noise\"))
    engine.sympathetic_amt(params:get(\"resonance\"))
    engine.drift_amt(params:get(\"pitch_drift\"))
    engine.brightness_amt(params:get(\"brightness\"))
    engine.reverb_mix(params:get(\"reverb_mix\"))
    engine.reverb_room(params:get(\"reverb_room\"))
  elseif current_engine == \"AcidTest\" then
    if params:has(\"acid_delay_feedback\") then
      engine.acidTest_delay(60 / clock.get_tempo(), params:get(\"acid_delay_beats\"), params:get(\"acid_delay_feedback\"))
    end
  end
end

local function setup_engine_abstraction()
  if current_engine == \"UprightBass\" then
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

  elseif current_engine == \"AcidTest\" then
    local acid_portamento = 0.05

    eng.note_on = function(freq, amp, decay, articulation)
      local note = math.floor(69 + 12 * math.log(freq / 440) / math.log(2) + 0.5)
      local port = acid_portamento
      if articulation == \"sing\" then port = 0.2 end
      if articulation == \"staccato\" then port = 0 end
      if articulation == \"ghost\" then port = 0.01 end

      engine.acidTest_bass_gate(1)
      engine.acidTest_bass(amp, note,
        params:get(\"acid_delay_send\"),
        params:get(\"acid_reverb_send\"),
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
local function midi_note_on(note)
  if midi_out then
    midi_out:note_on(note, 100, midi_channel)
  end
end

local function midi_note_off()
  if midi_out then
    midi_out:all_notes_off(midi_channel)
  end
end

-------------------------------------------------
-- sequencer logic
-------------------------------------------------
local function start_count_in()
  state.counting_in = true
  state.count_in_beats_left = params:get(\"count_in\")
  state.beat = 0
end

local function stop_playing()
  state.playing = false
  state.counting_in = false
  engine_kill_all()
  midi_note_off()
end

local function engine_kill_all()
  if eng.kill_all then
    eng.kill_all()
  end
end

-------------------------------------------------
-- parameters & init
-------------------------------------------------
function params_setup()
  params:add_option(\"progression\", \"progression\", {\"ii-V-I\", \"minor swing\", \"blues\", \"custom\"})
  params:add_number(\"low_note\", \"low note\", 24, 72, 36)
  params:add_number(\"high_note\", \"high note\", 24, 72, 48)
  params:add_number(\"count_in\", \"count in\", 0, 8, 2)
  params:add_control(\"midi_enabled\", \"MIDI out\", controlspec.new(1, 2, \"lin\", 1, 2, \"\", {\"off\", \"on\"}))
  
  if current_engine == \"UprightBass\" then
    params:add_number(\"body_tone\", \"body tone\", 0, 1, 0.5)
    params:add_number(\"body_mix\", \"body mix\", 0, 1, 0.7)
    params:add_number(\"finger_noise\", \"finger noise\", 0, 1, 0.1)
    params:add_number(\"resonance\", \"resonance\", 0, 1, 0.3)
    params:add_number(\"pitch_drift\", \"pitch drift\", 0, 1, 0.1)
    params:add_number(\"brightness\", \"brightness\", 0, 1, 0.5)
    params:add_number(\"reverb_mix\", \"reverb mix\", 0, 1, 0.2)
    params:add_number(\"reverb_room\", \"reverb room\", 0, 1, 0.3)
  elseif current_engine == \"AcidTest\" then
    params:add_number(\"acid_delay_beats\", \"acid delay beats\", 0.25, 4, 1, 0.25)
    params:add_number(\"acid_delay_feedback\", \"acid delay feedback\", 0, 1, 0.6)
    params:add_number(\"acid_delay_send\", \"acid delay send\", 0, 1, 0.3)
    params:add_number(\"acid_reverb_send\", \"acid reverb send\", 0, 1, 0.2)
  end
end

function init()
  params_setup()
  rebuild_progression_map()
  init_custom_chart()
  setup_engine_defaults()
  setup_engine_abstraction()
  
  midi_out = midi.connect(1)
  
  clock.set_tempo(120)
  
  redraw_metro = metro.init()
  redraw_metro.event = function()
    screen_dirty = true
  end
  redraw_metro:start(1 / 15)
  
  clock.transport.start = function()
    start_count_in()
  end
  clock.transport.stop = function()
    stop_playing()
  end
end

-------------------------------------------------
-- grid
-------------------------------------------------
function g.key(x, y, z)
  if z == 0 then return end
  
  if y <= 6 and x <= 8 then
    custom_chart[x] = {root = 36 + (y - 1) * 2, quality = \"ionian\"}
    build_custom_from_grid()
    grid_dirty = true
  elseif y == 7 and x <= 8 then
    local cur_qual = custom_chart[x].quality
    local idx = 1
    for i, q in ipairs(QUALITY_LIST) do
      if q == cur_qual then idx = i; break end
    end
    custom_chart[x].quality = QUALITY_LIST[(idx % #QUALITY_LIST) + 1]
    build_custom_from_grid()
    grid_dirty = true
  elseif y == 8 then
    if x == 1 then
      state.playing = not state.playing
      if state.playing then start_count_in() end
    elseif x == 2 then
      state.playing = false
      state.beat = 0
    end
    grid_dirty = true
  end
end

local function grid_redraw()
  if not g then return end
  g:all(0)
  
  for i = 1, 8 do
    local y = (custom_chart[i].root - 36) / 2 + 1
    g:led(i, math.clamp(y, 1, 6), 15)
  end
  
  for i = 1, 8 do
    local is_ionian = custom_chart[i].quality == \"ionian\"
    g:led(i, 7, is_ionian and 8 or 4)
  end
  
  g:led(1, 8, state.playing and 15 or 4)
  g:led(2, 8, 4)
  
  g:refresh()
end

-------------------------------------------------
-- screen
-------------------------------------------------
local function draw_page_play()
  screen.clear()
  screen.font_size(16)
  screen.level(15)
  screen.move(0, 20)
  screen.text(\"bass : \" .. note_name(state.last_note))
  screen.move(0, 35)
  screen.text(\"bar : \" .. state.bar)
  screen.move(0, 50)
  screen.text(\"tempo : \" .. math.floor(clock.get_tempo()))
  if state.playing then
    screen.level(15)
    screen.move(100, 20)
    screen.text(\">>\")
  end
end

local function draw_page_tone()
  screen.clear()
  screen.font_size(16)
  screen.level(15)
  screen.move(0, 20)
  screen.text(\"engine : \" .. current_engine)
  screen.move(0, 35)
  screen.text(\"tone adj\")
end

local function draw_page_trainer()
  screen.clear()
  screen.font_size(14)
  screen.level(15)
  screen.move(0, 20)
  screen.text(\"tempo ramp\")
  screen.move(0, 35)
  screen.text(\"status : idle\")
end

function midi_note_on(note)
  if midi_out then
    midi_out:note_on(note, 100, 1)
  end
end

function midi_note_off()
  if midi_out then
    midi_out:all_notes_off(1)
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

function update()
  if screen_dirty then
    redraw()
    screen_dirty = false
  end
  if grid_dirty then
    grid_redraw()
    grid_dirty = false
  end
end

function key(n, z)
  if z == 0 then return end
  if n == 1 then
    state.screen_page = (state.screen_page % 3) + 1
    screen_dirty = true
  elseif n == 2 then
    state.playing = not state.playing
    if state.playing then start_count_in() end
    screen_dirty = true
  elseif n == 3 then
    state.playing = true
    state.beat = 0
    state.bar = 1
    start_count_in()
    screen_dirty = true
  end
end

function enc(n, d)
  if n == 1 then
    state.screen_page = util.clamp(state.screen_page + d, 1, 3)
  elseif n == 2 then
    local tempo = clock.get_tempo()
    clock.set_tempo(util.clamp(tempo + d, 20, 300))
  elseif n == 3 then
    state.register_bias = state.register_bias + d * 0.1
  end
  screen_dirty = true
end

local draw_page_midi = function()
  screen.clear()
  screen.font_size(12)
  screen.level(15)
  screen.move(0, 20)
  screen.text(\"midi \" .. (params:get(\"midi_enabled\") == 2 and \"on\" or \"off\"))

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

function cleanup()
  clock.cancel_all()
  state.playing = false
  midi_note_off()
  opxy_all_notes_off()
  if eng.kill_all then eng.kill_all() end
  if redraw_metro then
    redraw_metro:stop()
  end
end

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
