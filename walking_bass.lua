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

engine.name = "UprightBass"

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
}

local params_state = {
  tempo = 90,
  grid_octave_offset = 1,
  grid_root_note_idx = 1,
  grid_root_note = "C",
}

local ui_state = {
  page = 1,
  selected_bar = 1,
  selected_root = 1,
}

local chord_progression = {}

-------------------------------------------------
-- init chord progression
-------------------------------------------------
function init()
  screen_dirty = true

  params:add_group("walking bass", 4)

  params:add {
    type = "number",
    id = "tempo",
    name = "tempo",
    min = 40,
    max = 200,
    default = 90,
    action = function(v)
      params_state.tempo = v
    end,
  }

  params:add {
    type = "number",
    id = "swing_amount",
    name = "swing",
    min = 0,
    max = 100,
    default = 0,
  }

  params:add {
    type = "number",
    id = "density",
    name = "density",
    min = 0,
    max = 100,
    default = 93,
    action = function(v)
      state.density = v / 100
    end,
  }

  params:add {
    type = "number",
    id = "energy",
    name = "energy",
    min = 0,
    max = 100,
    default = 42,
    action = function(v)
      state.energy = v / 100
    end,
  }

  params:bang()

  build_chord_progression()

  redraw()
end

-------------------------------------------------
-- chord progression builder
-------------------------------------------------
function build_chord_progression()
  chord_progression = {}

  for bar = 1, NUM_BARS_MAX do
    chord_progression[bar] = {
      root_idx = 1,
      quality = "dorian",
      scale_notes = {},
    }

    local scale_name = quality_to_scale[chord_progression[bar].quality]
    chord_progression[bar].scale_notes = MusicUtil.build_scale(36, scale_name)
  end
end

-------------------------------------------------
-- drawing
-------------------------------------------------
function redraw()
  screen.clear()
  screen.font_size(8)

  if ui_state.page == 1 then
    draw_form_page()
  elseif ui_state.page == 2 then
    draw_mix_page()
  end

  screen.update()
end

function draw_form_page()
  screen.level(15)
  screen.move(0, 10)
  screen.text("walking bass: form")

  screen.level(8)
  screen.move(0, 24)
  screen.text("tempo: " .. params_state.tempo)
  screen.move(0, 32)
  screen.text("section: " .. state.section)
  screen.move(0, 40)
  screen.text("bar: " .. state.bar .. "/" .. NUM_BARS_MAX)

  if state.playing then
    screen.level(4)
    screen.move(100, 24)
    screen.text("playing")
  end

  screen.move(0, 48)
  if not state.solo_mode then
    screen.text("support mode")
  else
    screen.text("solo mode")
  end
end

function draw_mix_page()
  screen.level(15)
  screen.move(0, 10)
  screen.text("walking bass: mix")

  screen.level(8)
  screen.move(0, 24)
  screen.text("density: " .. util.round(state.density * 100))
  screen.move(0, 32)
  screen.text("energy: " .. util.round(state.energy * 100))
  screen.move(0, 40)
  screen.text("pocket: " .. util.round(state.pocket * 100))
  screen.move(0, 48)
  screen.text("note: " .. MusicUtil.note_num_to_name(state.last_note))
end

-------------------------------------------------
-- grid
-------------------------------------------------
function grid_redraw()
  local g = grid.connect()

  -- clear
  for x = 1, 16 do
    for y = 1, 8 do
      g:led(x, y, 0)
    end
  end

  -- chord slots (rows 1-6)
  for bar = 1, NUM_BARS_MAX do
    for root_idx = 1, NUM_ROOTS do
      local level = BRIGHT.GHOST

      if chord_progression[bar].root_idx == root_idx then
        level = BRIGHT.FULL
      end

      if bar == state.bar then
        level = level + BRIGHT.DIM
      end

      if bar <= 8 then
        g:led(bar, root_idx, util.clamp(level, 0, 15))
      else
        g:led(bar - 8, 4 + root_idx, util.clamp(level, 0, 15))
      end
    end
  end

  -- quality toggles (row 7)
  for bar = 1, 8 do
    local level = BRIGHT.MID
    if chord_progression[bar].quality == "aeolian" then
      level = BRIGHT.FULL
    end
    g:led(bar, 7, level)
  end

  -- transport (row 8)
  g:led(1, 8, state.playing and BRIGHT.FULL or BRIGHT.DIM)
  g:led(2, 8, state.solo_mode and BRIGHT.FULL or BRIGHT.DIM)

  g:refresh()
end

function grid_key(x, y, z)
  if z == 0 then return end

  -- chord slots
  if y <= 6 then
    local bar = x
    if y > NUM_ROOTS then return end
    chord_progression[bar].root_idx = y
    screen_dirty = true
  end

  -- quality toggles
  if y == 7 then
    local quality_idx = math.fmod(util.index_of(QUALITY_LIST, chord_progression[x].quality), 8) + 1
    chord_progression[x].quality = QUALITY_LIST[quality_idx]
    screen_dirty = true
  end

  -- transport
  if y == 8 then
    if x == 1 then
      if state.playing then
        clock.transport.stop()
      else
        clock.transport.start()
      end
    elseif x == 2 then
      state.solo_mode = not state.solo_mode
      screen_dirty = true
    end
  end
end

-------------------------------------------------
-- encoder
-------------------------------------------------
function enc(n, delta)
  if n == 1 then
    ui_state.page = util.clamp(ui_state.page + delta, 1, 2)
    screen_dirty = true
  elseif n == 2 then
    if ui_state.page == 1 then
      params:delta("tempo", delta * 2)
    else
      params_state.grid_root_note_idx = util.clamp(params_state.grid_root_note_idx + delta, 1, 12)
    end
  elseif n == 3 then
    if ui_state.page == 1 then
      state.section_bars_left = util.clamp(state.section_bars_left + delta, 1, 32)
      screen_dirty = true
    else
      params:delta("density", delta * 2)
    end
  end
end

-------------------------------------------------
-- key
-------------------------------------------------
function key(n, z)
  if z == 0 then return end

  if n == 2 then
    if state.playing then
      clock.transport.stop()
    else
      clock.transport.start()
    end
  elseif n == 3 then
    state.playing = false
    state.bar = 1
    state.beat = 0
    state.counting_in = false
    midi_note_off()
    screen_dirty = true
  end
end

-------------------------------------------------
-- clock
-------------------------------------------------
function clock.transport.start()
  state.playing = true
  state.counting_in = true
  state.count_in_beats_left = 4
  state.beat = 0
  state.bar = 1
  state.motif = {}
  state.motif_age = 0
  screen_dirty = true
end

function clock.tick()
  if not state.playing then return end

  if state.counting_in then
    state.count_in_beats_left = state.count_in_beats_left - 1
    if state.count_in_beats_left <= 0 then
      state.counting_in = false
    else
      return
    end
  end

  state.beat = state.beat + 1
  if state.beat > 3 then
    state.beat = 0
    advance_bar()
  end

  generate_note()
  screen_dirty = true
end

function advance_bar()
  state.bar = state.bar + 1
  if state.bar > NUM_BARS_MAX then
    state.chorus = state.chorus + 1
    state.bar = 1
  end

  state.section_bars_left = state.section_bars_left - 1
  if state.section_bars_left <= 0 then
    state.section_bars_left = 8
    if state.section == "support" then
      state.section = "solo"
    else
      state.section = "support"
    end
  end
end

function generate_note()
  local chord = chord_progression[state.bar]
  local scale = chord.scale_notes

  if state.solo_mode then
    -- solo mode: free exploration
    state.direction = math.random(-1, 1)
    state.target_note = scale[math.random(1, #scale)]
  else
    -- support mode: walking bass patterns
    local pattern_idx = (state.beat % 4) + 1

    if pattern_idx == 1 then
      state.target_note = scale[chord.root_idx]
    elseif pattern_idx == 2 then
      state.target_note = scale[math.fmod(chord.root_idx + 2, #scale) + 1]
    elseif pattern_idx == 3 then
      state.target_note = scale[math.fmod(chord.root_idx + 4, #scale) + 1]
    else
      state.target_note = scale[math.fmod(chord.root_idx + 1, #scale) + 1]
    end
  end

  play_note()
end

function play_note()
  local articulation = ARTICULATION.normal

  if math.random() < (1 - state.density) then
    articulation = ARTICULATION.ghost
  end

  if math.random() < state.energy then
    articulation = ARTICULATION.dig
  end

  if state.pocket > 0.5 then
    state.target_note = state.target_note + math.random(-1, 1)
  end

  state.last_note = state.target_note
  state.last_interval = state.last_note - state.last_midi_note

  midi_note_off()
  midi.note_on(state.target_note, 60)
  state.last_midi_note = state.target_note

  table.insert(state.phrase_memory, {note = state.target_note, articulation = articulation})
  state.motif_age = state.motif_age + 1
end

function midi_note_off()
  if state.last_midi_note then
    midi.note_off(state.last_midi_note, 0)
  end
end

function clock.transport.stop()
  state.playing = false
  midi_note_off()
  screen_dirty = true
end