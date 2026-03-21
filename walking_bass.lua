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
  mixolydian    = "Mixolydian",
  aeolian       = "Minor",
  melodic_minor = "Melodic Minor",
  phrygian      = "Phrygian",
  locrian       = "Locrian",
  lydian        = "Lydian",
}

local ROOT_NAMES = {"C", "D", "E", "F", "G", "A"}

-------------------------------------------------
-- state
-------------------------------------------------
local state = {
  tempo = 120,
  playing = false,
  swing = 0,
  notes_per_bar = 4,
  progression = {
    {root=0, quality="ionian"},
    {root=0, quality="ionian"},
    {root=4, quality="ionian"},
    {root=0, quality="ionian"},
  },
  grid_progression = {
    {root=0, quality="ionian"},
    {root=0, quality="ionian"},
    {root=4, quality="ionian"},
    {root=0, quality="ionian"},
  },
  num_bars = 4,
}

local nav = {
  page = 1,
  grid_page = 1,
  root_select = 1,
  quality_select = 1,
  tempo_fine = 0,
}

local clock_id = nil
local last_beat_ms = 0
local beat_time = 0
local beat_count = 0
local screen_dirty = true
local grid_dirty = true
local portamento_time = 0.05
local current_note = nil
local current_note_start = 0
local screen_width = 128
local screen_height = 64

-------------------------------------------------
-- Engine abstraction layer
-------------------------------------------------
local function engine_init()
  if current_engine == "UprightBass" then
    engine.freq_env_attack = 0.0
    engine.freq_env_decay = 0.1
    engine.freq_env_sustain = 1.0
    engine.amp_env_attack = 0.001
    engine.amp_env_decay = 0.3
    engine.amp_env_sustain = 0.6
    engine.amp_env_release = 0.1
    engine.filter_cutoff = 200
    engine.filter_resonance = 0.1
  elseif current_engine == "AcidTest" then
    engine.delay_send = 0.3
    engine.reverb_send = 0.2
    engine.portamento_time = 0.05
  end
end

local function engine_note_on(freq, articulation)
  articulation = articulation or ARTICULATION.normal
  if current_engine == "UprightBass" then
    if articulation == ARTICULATION.ghost then
      engine.amp_env_attack = 0.001
    elseif articulation == ARTICULATION.dig then
      engine.amp_env_attack = 0.001
      engine.freq_env_decay = 0.05
    elseif articulation == ARTICULATION.staccato then
      engine.amp_env_decay = 0.15
    elseif articulation == ARTICULATION.sing then
      engine.amp_env_attack = 0.01
      engine.amp_env_sustain = 0.8
    end
    engine.hz = freq
  elseif current_engine == "AcidTest" then
    if articulation == ARTICULATION.ghost then
      engine.delay_send = 0.15
    elseif articulation == ARTICULATION.dig then
      engine.portamento_time = 0.01
    elseif articulation == ARTICULATION.staccato then
      engine.reverb_send = 0.1
    elseif articulation == ARTICULATION.sing then
      engine.portamento_time = 0.1
    end
    engine.hz = freq
  end
end

local function engine_note_off()
  if current_engine == "UprightBass" then
    engine.gate = 0
  elseif current_engine == "AcidTest" then
    engine.gate = 0
  end
end

local function engine_kill_all()
  if current_engine == "UprightBass" then
    engine.gate = 0
  elseif current_engine == "AcidTest" then
    engine.gate = 0
  end
end

local function switch_engine(name)
  if name == current_engine then return end
  current_engine = name
  engine.name = name
  save_engine_choice(name)
  engine_kill_all()
  engine_init()
  norns.script.load(norns.state.script)
end

-------------------------------------------------
-- scale & harmonic utilities
-------------------------------------------------
local function get_scale_intervals(quality)
  local scale_name = quality_to_scale[quality] or "Major"
  local scale = MusicUtil.scales[scale_name]
  if not scale then
    scale = MusicUtil.scales["Major"]
  end
  return scale
end

local function get_degree(root, scale_intervals, degree)
  local octave = math.floor((degree - 1) / #scale_intervals)
  local note_in_scale = (degree - 1) % #scale_intervals + 1
  local semitones = scale_intervals[note_in_scale]
  local midi_note = root + semitones + (octave * 12)
  return midi_note
end

local function midi_to_hz(midi_note)
  return 440 * math.pow(2, (midi_note - 69) / 12)
end

local function get_walking_bass_note(bar, beat, progression, notes_per_bar)
  local chord_idx = ((bar - 1) % #progression) + 1
  local chord = progression[chord_idx]
  local root_midi = 36 + chord.root * 2
  local scale_intervals = get_scale_intervals(chord.quality)
  
  if beat == 1 then
    return get_degree(root_midi, scale_intervals, 1)
  elseif beat == 2 then
    local up_or_down = beat % 2 == 0 and 3 or 2
    return get_degree(root_midi, scale_intervals, up_or_down)
  elseif beat == 3 then
    return get_degree(root_midi, scale_intervals, 5)
  else
    local approach = beat % 2 == 0 and 3 or 2
    return get_degree(root_midi, scale_intervals, approach)
  end
end

-------------------------------------------------
-- sequencer clock
-------------------------------------------------
local function play_beat()
  if not state.playing then return end
  
  local bar = math.floor((beat_count) / state.notes_per_bar) + 1
  local beat = (beat_count % state.notes_per_bar) + 1
  
  if current_note then
    engine_note_off()
  end
  
  local midi_note = get_walking_bass_note(bar, beat, state.progression, state.notes_per_bar)
  local hz = midi_to_hz(midi_note)
  local articulation = (beat == 1) and ARTICULATION.sing or ARTICULATION.normal
  
  engine_note_on(hz, articulation)
  current_note = midi_note
  current_note_start = beat_time
  
  midi_note_on(midi_note)
  beat_count = beat_count + 1
  
  if beat_count >= state.num_bars * state.notes_per_bar then
    beat_count = 0
  end
end

local function clock_tick()
  local now = util.time() * 1000
  local tempo_hz = state.tempo / 60 / state.notes_per_bar
  local interval_ms = 1000 / tempo_hz
  
  if now - last_beat_ms >= interval_ms then
    beat_time = beat_time + 1
    play_beat()
    screen_dirty = true
    last_beat_ms = now
  end
end

-------------------------------------------------
-- MIDI output
-------------------------------------------------
local midi_device = nil

local function midi_note_on(note)
  if midi_device and note then
    midi_device:note_on(note, 100, 1)
  end
end

local function midi_note_off()
  if midi_device and current_note then
    midi_device:note_off(current_note, 0, 1)
  end
end

-------------------------------------------------
-- OP-XY MIDI CC support
-------------------------------------------------
local opxy_ccs = {
  tempo = 1,
  quality = 2,
  root = 3,
  notes_per_bar = 4,
}

local function opxy_send_cc(cc, value)
  if midi_device then
    midi_device:cc(cc, math.floor(value), 1)
  end
end

local function opxy_all_notes_off()
  if midi_device then
    for i = 0, 127 do
      midi_device:note_off(i, 0, 1)
    end
  end
end

-------------------------------------------------
-- screen drawing
-------------------------------------------------
local function draw_screen()
  screen.clear()
  screen.level(15)
  screen.font_size(16)
  
  if nav.page == 1 then
    -- form page
    screen.move(0, 20)
    screen.text("walking_bass v4")
    screen.move(0, 35)
    screen.text("tempo: " .. state.tempo)
    screen.move(0, 50)
    screen.text("bars: " .. state.num_bars)
    
    if state.playing then
      screen.level(15)
      screen.move(100, 20)
      screen.text(">>")
    end
  elseif nav.page == 2 then
    -- mix page (engine selection)
    screen.move(0, 20)
    screen.text("engine: " .. current_engine)
    screen.move(0, 35)
    screen.text("E3 = switch")
    screen.move(0, 50)
    screen.text("notes: " .. state.notes_per_bar)
  end
  
  screen.update()
end

-------------------------------------------------
-- grid display
-------------------------------------------------
local g = grid.connect()

local function grid_redraw()
  if not g then return end
  g:all(0)
  
  -- rows 1-6: chord slots
  for bar = 1, state.num_bars do
    for root = 1, NUM_ROOTS do
      local x = bar
      local y = root
      if state.progression[bar] and state.progression[bar].root == root - 1 then
        g:led(x, y, BRIGHT.BRIGHT)
      else
        g:led(x, y, BRIGHT.DIM)
      end
    end
  end
  
  -- row 7: quality toggle
  for bar = 1, state.num_bars do
    if state.progression[bar].quality == "ionian" then
      g:led(bar, 7, BRIGHT.MID)
    else
      g:led(bar, 7, BRIGHT.GHOST)
    end
  end
  
  -- row 8: transport
  g:led(1, 8, state.playing and BRIGHT.FULL or BRIGHT.DIM)  -- play
  g:led(2, 8, BRIGHT.DIM)  -- stop
  g:led(3, 8, BRIGHT.DIM)  -- reset
  
  g:refresh()
end

-------------------------------------------------
-- grid input
-------------------------------------------------
function g.key(x, y, z)
  if z == 0 then return end
  
  if y <= 6 and x <= state.num_bars then
    -- chord selection
    state.progression[x].root = y - 1
    state.grid_progression[x].root = y - 1
    state.progression[x].quality = "ionian"
    grid_dirty = true
  elseif y == 7 and x <= state.num_bars then
    -- quality toggle
    local current = state.progression[x].quality
    local idx = 1
    for i, q in ipairs(QUALITY_LIST) do
      if q == current then idx = i; break end
    end
    state.progression[x].quality = QUALITY_LIST[(idx % #QUALITY_LIST) + 1]
    state.grid_progression[x].quality = state.progression[x].quality
    grid_dirty = true
  elseif y == 8 then
    if x == 1 then
      state.playing = not state.playing
      if state.playing then
        last_beat_ms = util.time() * 1000
        beat_count = 0
      else
        engine_note_off()
        opxy_all_notes_off()
      end
    elseif x == 2 then
      state.playing = false
      engine_kill_all()
      beat_count = 0
      beat_time = 0
      opxy_all_notes_off()
    elseif x == 3 then
      beat_count = 0
      beat_time = 0
    end
    grid_dirty = true
  end
end

-------------------------------------------------
-- encoder input
-------------------------------------------------
function enc(n, delta)
  if n == 1 then
    nav.page = util.clamp(nav.page + delta, 1, #GRID_PAGES)
    screen_dirty = true
  elseif n == 2 then
    if nav.page == 1 then
      state.tempo = util.clamp(state.tempo + delta * 5, 40, 240)
      screen_dirty = true
    else
      state.num_bars = util.clamp(state.num_bars + delta, 1, NUM_BARS_MAX)
      screen_dirty = true
    end
  elseif n == 3 then
    if nav.page == 1 then
      state.notes_per_bar = util.clamp(state.notes_per_bar + delta, 1, 8)
      screen_dirty = true
    else
      if delta > 0 then
        switch_engine("AcidTest")
      else
        switch_engine("UprightBass")
      end
      screen_dirty = true
    end
  end
end

-------------------------------------------------
-- button input
-------------------------------------------------
function key(n, z)
  if z == 0 then return end
  
  if n == 2 then
    state.playing = not state.playing
    if state.playing then
      last_beat_ms = util.time() * 1000
      beat_count = 0
    else
      engine_note_off()
      opxy_all_notes_off()
    end
    screen_dirty = true
  elseif n == 3 then
    state.playing = true
    beat_count = 0
    beat_time = 0
    last_beat_ms = util.time() * 1000
    screen_dirty = true
  end
end

-------------------------------------------------
-- initialization
-------------------------------------------------
function init()
  engine_init()
  midi_device = midi.connect(1)
  
  clock_id = clock.run(function()
    while true do
      clock_tick()
      clock.sleep(0.01)
    end
  end)
  
  screen_dirty = true
end

-------------------------------------------------
-- update loop
-------------------------------------------------
function update()
  if screen_dirty then
    draw_screen()
    screen_dirty = false
  end
  if grid_dirty then
    grid_redraw()
    grid_dirty = false
  end
end

-------------------------------------------------
-- shutdown
-------------------------------------------------
function cleanup()
  if clock_id then
    clock.cancel(clock_id)
  end
  state.playing = false
  midi_note_off()
  opxy_all_notes_off()
  screen_dirty = true
end