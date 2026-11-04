# Audio to MIDI

REAPER script: select audio items, run **Audio to MIDI.lua**, pick a mode and press Convert.
Each item gets a new track right under its own with a MIDI item over the same span
(take pitch and playrate are taken into account).

| Mode | Engine | Good for |
|------|--------|----------|
| Auto | picks one of the three below | anything |
| Poly | Basic Pitch (Spotify, ONNX Runtime) | piano, guitar, chords, mixes |
| Mono | pYIN pitch tracking | bass, vocals, leads; optional pitch bends (±2 semitones) |
| Drums | per-band onsets | kick 36 / snare 38 / hat 42 |

Auto goes to Drums when the sound is mostly percussive, else runs Basic Pitch and switches to Mono
when it found few real chords (overtone ghosts like octaves and 12ths don't count).

Options: Fewer / Normal / More notes, shortest note (30 / 60 / 120 ms), pitch bends, snap to the
project grid, add ReaSynth, mute the original.

Needs ReaImGui and a Python venv `.venv-midi` next to the script (or in any Scripts subfolder).
The window offers to set it up on first run; by hand:

    python3 -m venv .venv-midi
    .venv-midi/bin/pip install --no-deps basic-pitch==0.4.0
    .venv-midi/bin/pip install -r requirements.txt

`AudioToMidi.py` also works on its own:

    .venv-midi/bin/python AudioToMidi.py --in song.wav --out notes.txt --mode auto --bends
