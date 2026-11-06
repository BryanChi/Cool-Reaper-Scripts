#!/usr/bin/env python3
"""Audio to MIDI sidecar for the REAPER script "Audio to MIDI.lua".

Transcribes one stretch of an audio file to notes and writes them as plain text that the
Lua side turns into a MIDI item.

Modes
  piano  Transkun (piano-only model, MAESTRO): notes, velocity and sustain pedal. Needs torch.
  poly   Basic Pitch (Spotify, ICASSP 2022) through ONNX Runtime: chords, piano, guitar, mixes.
  mono   pYIN pitch track cut into notes: bass, vocals, leads. Can add pitch bends.
  drums  Onsets sorted into kick / snare / hat by band energy (GM 36 / 38 / 42).
  auto   Picks one: drums when the sound is mostly percussive, else Basic Pitch, and mono
         instead when Basic Pitch found few real chords (overtone ghosts do not count).

Output (--out), one record per line, times in seconds from --start:
  MODE <mode actually used>
  N <start> <end> <midi pitch> <velocity 1-127>
  B <time> <bend -8192..8191>       (mono with --bends; range +-BEND_RANGE semitones)
  P <start> <end> <cc> <value>      (piano: pedal held from start to end; cc 64 = sustain)
  INFO <text>
Progress: "<pct> <message>" in --progress. Exit code in --done when finished.
"""

import argparse
import os
import sys
import tempfile
import time
import traceback

BEND_RANGE = 2.0  # semitones; REAPER's synths and most others default to +-2

PROGRESS = None


def progress(pct, msg):
    if not PROGRESS:
        return
    try:
        tmp = PROGRESS + ".tmp"
        with open(tmp, "w") as f:
            f.write("%d %s\n" % (int(pct), msg))
        os.replace(tmp, PROGRESS)
    except OSError:
        pass


def load_audio(path, start, dur, sr):
    import librosa
    import numpy as np

    y, _ = librosa.load(path, sr=sr, mono=True, offset=max(0.0, start), duration=dur if dur > 0 else None)
    y = np.asarray(y, dtype=np.float32)
    if y.size == 0:
        raise RuntimeError("No audio in the selected range.")
    return y


def db_to_vel(db, floor_db=-50.0):
    # -50 dBFS -> 20, 0 dBFS -> 127, with a slight curve so quiet notes stay audible
    x = (db - floor_db) / (-floor_db)
    x = min(1.0, max(0.0, x))
    return int(round(20 + 107 * (x ** 0.8)))


# ---------------------------------------------------------------------------------------------
# poly: Basic Pitch


def run_poly(y, sr, sens, min_ms, lo, hi):
    import numpy as np
    import soundfile as sf

    progress(10, "Loading Basic Pitch")
    from basic_pitch import ICASSP_2022_MODEL_PATH
    from basic_pitch import inference as bp
    from basic_pitch import note_creation as nc
    from basic_pitch.constants import AUDIO_SAMPLE_RATE, FFT_HOP

    model_path = ICASSP_2022_MODEL_PATH
    if not str(model_path).endswith(".onnx"):
        cand = os.path.join(os.path.dirname(str(model_path)), "nmp.onnx")
        if os.path.exists(cand):
            model_path = cand
    model = bp.Model(model_path)

    fd, wav = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    try:
        sf.write(wav, y, sr)
        progress(25, "Listening for notes")
        out = bp.run_inference(wav, model)
    finally:
        try:
            os.remove(wav)
        except OSError:
            pass

    progress(80, "Building notes")
    onset_t = 0.7 - 0.4 * sens  # 0.5 at the middle
    frame_t = 0.45 - 0.3 * sens  # 0.3 at the middle
    min_frames = max(1, int(round(min_ms / 1000.0 * (AUDIO_SAMPLE_RATE / FFT_HOP))))
    _, events = nc.model_output_to_notes(
        out,
        onset_thresh=onset_t,
        frame_thresh=frame_t,
        min_note_len=min_frames,
        min_freq=lo,
        max_freq=hi,
        multiple_pitch_bends=False,
        melodia_trick=True,
    )
    notes = []
    for st, en, pitch, amp, _bends in events:
        vel = int(round(np.clip(amp, 0, 1) * 127))
        notes.append((float(st), float(en), int(pitch), max(1, min(127, vel))))
    notes.sort()
    fps = AUDIO_SAMPLE_RATE / float(FFT_HOP)
    onset = out["onset"]

    def onset_at(t, p):
        f = int(round(t * fps))
        col = p - 21
        if col < 0 or col >= onset.shape[1]:
            return 1.0
        return float(onset[max(0, f - 1) : f + 2, col].max())

    return join_splits(drop_overtones(notes), onset_at)


def join_splits(notes, onset_at, gap=0.025):
    """Basic Pitch cuts a held note when another note starts; join the same pitch back
    when the second half follows right on and has only a weak onset (not a re-strike)."""
    out = []
    last = {}
    for st, en, p, v in notes:
        j = last.get(p)
        if j is not None:
            pst, pen, _, pv = out[j]
            if 0 <= st - pen <= gap and onset_at(st, p) < 0.8:
                out[j] = (pst, max(pen, en), p, pv)
                continue
        last[p] = len(out)
        out.append((st, en, p, v))
    return out


HARM_STEPS = (12, 19, 24, 28, 31, 34, 36)  # harmonics 2..8, rounded to semitones


def drop_overtones(notes, ratio=0.72):
    """Basic Pitch often adds quiet notes on a louder note's harmonics (octave, 12th, ...).
    Drop a note that starts inside a louder note, sits on one of its harmonics and is
    mostly covered by it."""
    out = []
    for i, (st, en, p, v) in enumerate(notes):
        ghost = False
        dur = max(1e-6, en - st)
        for st2, en2, p2, v2 in notes:
            d = p - p2
            if d not in HARM_STEPS or v > ratio * v2:
                continue
            if st < st2 - 0.03 or st > en2:
                continue
            cover = min(en, en2) - max(st, st2)
            if cover >= 0.5 * dur:
                ghost = True
                break
        if not ghost:
            out.append((st, en, p, v))
    return out


def chord_share(notes):
    """Share of notes that really overlap another note at a non-harmonic interval.
    Overtone ghosts (octave, 12th, ...) and legato smear don't count, so a bass line
    scores low and chords score high."""
    c = 0
    for i, (s, e, p, v) in enumerate(notes):
        for j, (s2, e2, p2, v2) in enumerate(notes):
            d = abs(p - p2)
            if j == i or d in HARM_STEPS or s2 > e:
                continue
            # quiet pairs and close intervals down low are model mush, not chords
            if min(v, v2) < 40 or (min(p, p2) < 40 and d < 5):
                continue
            ov = min(e, e2) - max(s, s2)
            if ov > 0.06 and ov > 0.5 * min(e - s, e2 - s2):
                c += 1
                break
    return c / float(max(1, len(notes)))


# ---------------------------------------------------------------------------------------------
# mono: pYIN


def run_mono(y, sr, sens, min_ms, lo, hi, want_bends):
    import librosa
    import numpy as np
    import scipy.ndimage as ndi

    hop = 256
    lo = lo or librosa.note_to_hz("A0")
    hi = hi or librosa.note_to_hz("C7")
    progress(15, "Tracking pitch")
    f0, voiced, vprob = librosa.pyin(
        y, fmin=lo, fmax=hi, sr=sr, frame_length=2048, hop_length=hop, fill_na=np.nan
    )
    n = len(f0)
    tframe = hop / float(sr)
    rms = librosa.feature.rms(y=y, frame_length=2048, hop_length=hop, center=True)[0][:n]
    if len(rms) < n:
        rms = np.pad(rms, (0, n - len(rms)))
    db = 20 * np.log10(np.maximum(rms, 1e-9))
    peak_db = float(np.max(db)) if n else -100.0

    progress(60, "Cutting notes")
    # voiced: pYIN's decision, loosened/tightened by sensitivity, and not in near silence
    # pYIN's own voiced/unvoiced path, plus low-probability frames at high sensitivity
    gate = peak_db - (40 + 20 * sens)
    extra = vprob >= (0.9 - 0.8 * sens) if sens > 0.5 else np.zeros(n, dtype=bool)
    on = (voiced | extra) & np.isfinite(f0) & (db > gate)
    midi = np.full(n, np.nan)
    midi[on] = librosa.hz_to_midi(f0[on])
    # fill one-frame dropouts, then median-smooth the pitch inside voiced runs
    for i in range(1, n - 1):
        if not on[i] and on[i - 1] and on[i + 1]:
            on[i] = True
            midi[i] = 0.5 * (midi[i - 1] + midi[i + 1])
    sm = midi.copy()
    if n >= 5:
        filled = np.where(on, midi, 0.0)
        med = ndi.median_filter(filled, size=5, mode="nearest")
        sm = np.where(on, med, np.nan)
        # median of a run edge mixes in zeros: keep the raw pitch there
        bad = on & (np.abs(sm - midi) > 1.5)
        sm[bad] = midi[bad]

    # re-articulations: onset strength peaks inside a voiced run split a note of the same pitch
    oenv = librosa.onset.onset_strength(y=y, sr=sr, hop_length=hop)
    delta = 0.25 - 0.17 * sens
    onsets = set(
        int(o)
        for o in librosa.onset.onset_detect(
            onset_envelope=oenv, sr=sr, hop_length=hop, backtrack=False, delta=delta, units="frames"
        )
    )

    min_frames = max(2, int(round(min_ms / 1000.0 / tframe)))

    def rises(k):
        # a re-pluck gets louder; vibrato and slides only wobble the spectrum
        before = db[max(0, k - 4) : k + 1]
        after = db[k : min(n, k + 4)]
        return len(before) and len(after) and float(np.max(after) - np.min(before)) > (4.0 - 2.0 * sens)

    notes = []
    frames = []  # per note: (i0, i1)
    i = 0
    while i < n:
        if not on[i]:
            i += 1
            continue
        j = i
        while j < n and on[j]:
            j += 1
        # voiced run [i, j): cut where the rounded pitch changes and stays changed, or at onsets
        seg_start = i
        cur = np.round(np.nanmedian(sm[i : min(j, i + 4)]))
        k = i + 1
        while k < j:
            changed = abs(sm[k] - cur) > 0.6
            stay = changed and k + 3 <= j and np.all(np.abs(sm[k : k + 3] - sm[k]) < 0.6)
            art = (k in onsets) and (k - seg_start) >= max(min_frames, 7) and rises(k)
            if (changed and stay) or art:
                frames.append((seg_start, k))
                seg_start = k
                cur = np.round(np.nanmedian(sm[k : min(j, k + 4)]))
            k += 1
        frames.append((seg_start, j))
        i = j

    bends = []
    for a, b in frames:
        if b - a < min_frames:
            continue
        seg = sm[a:b]
        pitch = int(np.round(np.nanmedian(seg)))
        if pitch < 0 or pitch > 127:
            continue
        st, en = a * tframe, b * tframe
        vel = db_to_vel(float(np.max(db[a:b])) - max(0.0, peak_db))
        notes.append((st, en, pitch, vel))
        if want_bends:
            last = None
            for f in range(a + 2, b - 1):  # edges smear into the neighbours
                dev = sm[f] - pitch
                if not np.isfinite(dev):
                    continue
                if abs(dev) < 0.12:  # under 12 cents: no bend, just tracking noise
                    dev = 0.0
                v = int(round(np.clip(dev / BEND_RANGE, -1, 1) * 8191))
                if last is None or abs(v - last) >= 64:
                    bends.append((f * tframe, v))
                    last = v
            if last not in (None, 0):
                bends.append((en, 0))

    # merge tiny gaps between the same pitch that pYIN dropped without an onset
    merged = []
    for nt in notes:
        if merged:
            p = merged[-1]
            gap_f = int(round((nt[0] - p[1]) / tframe))
            if p[2] == nt[2] and 0 <= gap_f <= 2 and int(round(nt[0] / tframe)) not in onsets:
                merged[-1] = (p[0], nt[1], p[2], max(p[3], nt[3]))
                continue
        merged.append(nt)
    return merged, bends


# ---------------------------------------------------------------------------------------------
# drums


def run_drums(y, sr, sens):
    import librosa
    import numpy as np

    hop = 256
    progress(20, "Finding hits")
    # onsets per band (low / mid / high), merged: a hat in a snare's tail still shows up
    S = librosa.power_to_db(
        librosa.feature.melspectrogram(y=y, sr=sr, hop_length=hop, n_mels=96, fmax=sr / 2)
    )
    mf = librosa.mel_frequencies(n_mels=96, fmax=sr / 2)
    edges = [0, int(np.searchsorted(mf, 150)), int(np.searchsorted(mf, 3000)), 96]
    env = librosa.onset.onset_strength_multi(S=S, sr=sr, hop_length=hop, channels=edges)
    delta = 0.2 - 0.14 * sens
    cand = []
    band_names = ("lo", "mid", "hi")
    for bi, ch in enumerate(env):
        if not np.any(ch > 0):
            continue
        ch = ch / (np.percentile(ch[ch > 0], 99) + 1e-9)
        for c in librosa.onset.onset_detect(
            onset_envelope=ch, sr=sr, hop_length=hop, backtrack=True, delta=delta, units="samples"
        ):
            cand.append((int(c), band_names[bi]))
    cand.sort()
    ons, seen = [], []
    for c, band in cand:
        if not ons or c - ons[-1] > int(0.03 * sr):
            ons.append(c)
            seen.append(set())
        seen[-1].add(band)
    progress(60, "Sorting kick / snare / hat")
    # band energy that each hit ADDS (after minus before), so a ringing kick doesn't turn the
    # next hat into a kick; one onset can be several drums at once
    win = int(0.05 * sr)
    nfft = 2048
    freqs = np.fft.rfftfreq(nfft, 1.0 / sr)
    bands = {
        "lo": freqs < 120,
        "mid": (freqs >= 180) & (freqs < 4000),
        "hi": freqs >= 6000,
    }
    w = np.hanning(win)

    def band_e(a):
        seg = y[max(0, a) : max(0, a) + win]
        if len(seg) < win:
            seg = np.pad(seg, (0, win - len(seg)))
        spec = np.abs(np.fft.rfft(seg * w, n=nfft)) ** 2
        return {k: float(spec[m].sum()) for k, m in bands.items()}, spec

    peak = float(np.max(np.abs(y))) or 1.0
    hits = []
    for s, bset in zip(ons, seen):
        after, _ = band_e(int(s) + int(0.003 * sr))
        before, _ = band_e(int(s) - win)
        add = {k: max(0.0, after[k] - before[k]) for k in after}
        lvl = 20 * np.log10(max(1e-9, float(np.max(np.abs(y[s : s + win]))) / peak))
        if lvl < -45:
            continue
        hits.append((s, add, lvl, bset))
    if not hits:
        return []
    # each band against its own loud hits, so a kick under a hat doesn't hide the hat
    ref = {k: float(np.percentile([h[1][k] for h in hits], 90)) + 1e-12 for k in bands}
    thr = 0.3 - 0.2 * sens
    notes = []
    for s, add, lvl, bset in hits:
        n = {k: add[k] / ref[k] for k in bands}
        vel = db_to_vel(lvl, -40.0)
        t = s / float(sr)
        hit = []
        if "lo" in bset and n["lo"] > thr:
            hit.append(36)
        if "mid" in bset and n["mid"] > thr:
            hit.append(38)
        if "hi" in bset and 38 not in hit:
            hit.append(42)
        if not hit:
            hit = [max((n["lo"], 36), (n["mid"], 38), (n["hi"], 42))[1]]
        for p in hit:
            notes.append((t, t + 0.1, p, vel))
    return notes


def percussive_share(y):
    import librosa
    import numpy as np

    S = np.abs(librosa.stft(y, n_fft=2048, hop_length=512))
    H, P = librosa.decompose.hpss(S)
    h, p = float((H ** 2).sum()), float((P ** 2).sum())
    return p / (h + p + 1e-12)


# ---------------------------------------------------------------------------------------------
# piano: Transkun (piano-only model trained on MAESTRO; notes, velocity, sustain pedal)


def run_piano(path, start, dur, sens, min_ms):
    import threading

    import numpy as np

    progress(4, "Loading the piano model")
    try:
        import moduleconf
        import torch
        import transkun
    except ImportError as e:
        raise RuntimeError(
            "Piano mode needs Transkun. Install it with: .venv-midi/bin/pip install transkun soxr"
        ) from e
    import librosa

    d = os.path.join(os.path.dirname(transkun.__file__), "pretrained")
    cm = moduleconf.parseFromFile(os.path.join(d, "2.0.conf"))
    TK = cm["Model"].module.TransKun
    model = TK(conf=cm["Model"].config)
    ck = torch.load(os.path.join(d, "2.0.pt"), map_location="cpu")
    model.load_state_dict(ck.get("best_state_dict", ck.get("state_dict")), strict=False)
    model.eval()
    torch.set_grad_enabled(False)

    progress(10, "Reading audio")
    y, _ = librosa.load(path, sr=model.fs, mono=False, offset=max(0.0, start), duration=dur if dur > 0 else None)
    y = np.asarray(y, dtype=np.float32)
    if y.ndim == 1:
        y = y[None, :]
    y = np.ascontiguousarray(y.T)  # (samples, channels)
    if y.shape[0] == 0:
        raise RuntimeError("No audio in the selected range.")
    secs = y.shape[0] / float(model.fs)

    # the model has no progress hook: creep the bar along while it works
    done = threading.Event()

    def creep():
        t0 = time.time()
        while not done.wait(0.5):
            frac = 1 - np.exp(-(time.time() - t0) / max(3.0, secs * 0.6))
            progress(15 + 75 * frac, "Transcribing piano")

    th = threading.Thread(target=creep, daemon=True)
    th.start()
    try:
        est = None
        if torch.backends.mps.is_available():
            # Apple GPU when it works; any op it lacks falls back to the CPU run below
            try:
                est = model.to("mps").transcribe(torch.from_numpy(y).to("mps"), discardSecondHalf=False)
            except Exception:  # noqa: BLE001
                est = None
                model = model.to("cpu")
        if est is None:
            est = model.transcribe(torch.from_numpy(y), discardSecondHalf=False)
    finally:
        done.set()

    progress(92, "Building notes")
    min_vel = int(round(30 - 30 * sens))  # Fewer drops faint notes, More keeps all
    notes, pedals = [], []
    for n in est:
        if n.pitch > 0:
            if n.end - n.start >= min_ms / 1000.0 * 0.5 and n.velocity >= min_vel:
                notes.append((float(n.start), float(n.end), int(n.pitch), max(1, min(127, int(n.velocity)))))
        elif -n.pitch == 64:  # sustain only; its soft-pedal guesses are unreliable
            pedals.append((float(n.start), float(n.end), int(-n.pitch), max(1, min(127, int(n.velocity)))))
    notes.sort()
    pedals.sort()
    return notes, pedals


# ---------------------------------------------------------------------------------------------


def main():
    global PROGRESS
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--start", type=float, default=0.0)
    ap.add_argument("--dur", type=float, default=0.0)
    ap.add_argument("--mode", default="auto", choices=["auto", "piano", "poly", "mono", "drums"])
    ap.add_argument("--sens", type=float, default=0.5, help="0 = fewer notes, 1 = more notes")
    ap.add_argument("--min-ms", type=float, default=60.0)
    ap.add_argument("--low", type=float, default=0.0, help="lowest pitch in Hz (0 = any)")
    ap.add_argument("--high", type=float, default=0.0, help="highest pitch in Hz (0 = any)")
    ap.add_argument("--bends", action="store_true")
    ap.add_argument("--progress")
    ap.add_argument("--done")
    a = ap.parse_args()
    PROGRESS = a.progress
    code = 1
    t0 = time.time()
    try:
        sens = min(1.0, max(0.0, a.sens))
        lo = a.low or None
        hi = a.high or None
        sr = 22050
        mode = a.mode
        info = []
        bends = []
        pedals = []
        y = None
        if mode != "piano":
            progress(2, "Reading audio")
            y = load_audio(a.inp, a.start, a.dur, sr)
        if mode == "piano":
            notes, pedals = run_piano(a.inp, a.start, a.dur, sens, a.min_ms)
            info.append("%d pedal presses" % len(pedals))
            if not notes:
                # not an acoustic piano to the model (electric piano, heavy processing):
                # fall back to Basic Pitch rather than return nothing
                info.append("no piano found, used Poly")
                mode = "poly"
                progress(50, "No piano found, trying Poly")
                y = load_audio(a.inp, a.start, a.dur, sr)
        elif mode == "auto":
            progress(5, "Checking the sound")
            ps = percussive_share(y)
            info.append("percussive %.0f%%" % (ps * 100))
            if ps > 0.72:
                mode = "drums"
        if mode in ("auto", "poly"):
            notes = run_poly(y, sr, sens, a.min_ms, lo, hi)
            if mode == "auto":
                ch = chord_share(notes)
                info.append("chords %.0f%%" % (ch * 100))
                mode = "poly"
                if notes and ch < 0.3:
                    mode = "mono"
                    notes, bends = run_mono(y, sr, sens, a.min_ms, lo, hi, a.bends)
        elif mode == "mono":
            notes, bends = run_mono(y, sr, sens, a.min_ms, lo, hi, a.bends)
        elif mode == "drums":
            notes = run_drums(y, sr, sens)
        progress(95, "Writing notes")
        tmp = a.out + ".tmp"
        with open(tmp, "w") as f:
            f.write("MODE %s\n" % mode)
            for st, en, p, v in notes:
                f.write("N %.5f %.5f %d %d\n" % (st, en, p, v))
            for t, v in bends:
                f.write("B %.5f %d\n" % (t, v))
            for st, en, cc, v in pedals:
                f.write("P %.5f %.5f %d %d\n" % (st, en, cc, v))
            info.append("%.1fs" % (time.time() - t0))
            f.write("INFO %s\n" % ", ".join(info))
        os.replace(tmp, a.out)
        progress(100, "Done")
        code = 0
    except Exception as e:  # noqa: BLE001
        traceback.print_exc()
        progress(100, "Error: %s" % e)
        code = 1
    finally:
        if a.done:
            with open(a.done, "w") as f:
                f.write(str(code))
    return code


if __name__ == "__main__":
    sys.exit(main())
