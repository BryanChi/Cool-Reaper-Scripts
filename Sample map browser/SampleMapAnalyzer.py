#!/usr/bin/env python3
"""
Lightweight external analyzer for Sample Map Browser.

Reads an audio file and returns JSON with optional fields:
  - dominant_freq: estimated dominant frequency in Hz
  - rms_energy: root-mean-square amplitude (0.0-1.0 when float data)
  - sample_type: "Drum" or "Swell" if detected
  - snap_offset: time in seconds for drum hit point or swell peak

Uses wave/audioop for WAV/AIFF analysis with time-domain onset detection.
The script is intentionally forgiving: unsupported formats simply produce
null metrics rather than exiting with an error.
"""

from __future__ import annotations

import audioop
import cmath
import json
import math
import os
import sys
import wave
from typing import Dict, List, Optional


def simple_fft(samples: List[float]) -> List[complex]:
    """Simple FFT implementation using Cooley-Tukey algorithm."""
    n = len(samples)
    if n <= 1:
        return [complex(s, 0) for s in samples]
    
    # Pad to next power of 2 for efficiency
    n_padded = 1
    while n_padded < n:
        n_padded <<= 1
    
    # Convert to complex array
    x = [complex(samples[i] if i < n else 0.0, 0.0) for i in range(n_padded)]
    
    # Cooley-Tukey FFT
    def fft_rec(x_in):
        n_in = len(x_in)
        if n_in <= 1:
            return x_in
        even = fft_rec([x_in[i] for i in range(0, n_in, 2)])
        odd = fft_rec([x_in[i] for i in range(1, n_in, 2)])
        result = [0] * n_in
        for k in range(n_in // 2):
            t = cmath.exp(-2j * cmath.pi * k / n_in) * odd[k]
            result[k] = even[k] + t
            result[k + n_in // 2] = even[k] - t
        return result
    
    return fft_rec(x)


def detect_drum_cue_point(
    samples: List[float], 
    sr: int, 
    energy_envelope: List[float],
    window_size: int = 512,
    hop_size: int = 256
) -> Optional[float]:
    """
    Detect drum hit point: find the attack/onset (sudden energy increase).
    Returns time in seconds of the detected hit point.
    """
    if not energy_envelope or len(energy_envelope) < 2:
        return None
    
    # Normalize energy envelope
    max_energy = max(energy_envelope) if energy_envelope else 1.0
    if max_energy == 0:
        return None
    energy_norm = [e / max_energy for e in energy_envelope]
    
    # Calculate envelope derivative (sudden energy increase)
    energy_derivative = []
    for i in range(len(energy_norm) - 1):
        deriv = energy_norm[i + 1] - energy_norm[i]
        energy_derivative.append(max(0, deriv))  # Only positive changes
    
    # Calculate high-frequency content for each window (drums have sharp transients)
    hf_content = []
    for i in range(0, len(samples) - window_size + 1, hop_size):
        window = samples[i:i + window_size]
        try:
            fft_result = simple_fft(window)
            magnitude = [abs(x) for x in fft_result]
            # Focus on high frequencies (upper half of spectrum)
            hf_start = len(magnitude) // 2
            hf_energy = sum(magnitude[hf_start:]) / len(magnitude[hf_start:]) if hf_start < len(magnitude) else 0.0
            hf_content.append(hf_energy)
        except Exception:
            hf_content.append(0.0)
    
    # Normalize HF content
    max_hf = max(hf_content) if hf_content else 1.0
    if max_hf == 0:
        hf_norm = [0.0] * len(hf_content)
    else:
        hf_norm = [h / max_hf for h in hf_content]
    
    # Combine signals: onset score = energy derivative + high-frequency burst
    onset_scores = []
    for i in range(min(len(energy_derivative), len(hf_norm))):
        # Weight: 70% energy derivative (sudden increase), 30% high-frequency content
        score = 0.7 * energy_derivative[i] + 0.3 * hf_norm[i]
        onset_scores.append(score)
    
    if not onset_scores:
        return None
    
    # Find the peak onset in the first 2 seconds (drums hit early)
    max_window_time = int(2.0 * sr / hop_size)
    search_range = min(max_window_time, len(onset_scores))
    
    if search_range < 1:
        return None
    
    # Find the maximum score in the search range
    max_score = max(onset_scores[:search_range])
    if max_score < 0.05:
        return None
    
    # Find the first significant peak (attack point)
    best_window = 0
    for i in range(1, search_range - 1):
        # Check if this is a local peak above threshold
        if onset_scores[i] > onset_scores[i-1] and onset_scores[i] >= onset_scores[i+1]:
            if onset_scores[i] >= max_score * 0.4:  # At least 40% of max
                best_window = i
                break
    
    # If no clear peak found, use the maximum in the range
    if best_window == 0:
        best_window = max(range(search_range), key=lambda i: onset_scores[i])
    
    # Convert window index to time (in seconds)
    onset_time = (best_window * hop_size + window_size / 2) / float(sr)
    
    return onset_time


def detect_swell_cue_point(
    samples: List[float], 
    sr: int, 
    energy_envelope: List[float],
    window_size: int = 512,
    hop_size: int = 256
) -> Optional[float]:
    """
    Detect swell cue point: find the peak (loudest point) and then where energy drops off drastically.
    Returns time in seconds of the drop-off point after the peak.
    """
    if not energy_envelope or len(energy_envelope) < 3:
        return None
    
    # Normalize energy envelope
    max_energy = max(energy_envelope) if energy_envelope else 1.0
    if max_energy == 0:
        return None
    energy_norm = [e / max_energy for e in energy_envelope]
    
    # Find the peak (loudest point)
    peak_idx = max(range(len(energy_norm)), key=lambda i: energy_norm[i])
    peak_energy = energy_norm[peak_idx]
    
    # Look for where energy drops off drastically after the peak
    # Check for a drop of at least 30% from peak within the next 20% of the sample
    drop_threshold = peak_energy * 0.7  # 30% drop
    search_end = min(len(energy_norm), peak_idx + int(len(energy_norm) * 0.2))
    
    drop_off_idx = None
    for i in range(peak_idx + 1, search_end):
        if energy_norm[i] <= drop_threshold:
            # Found significant drop
            drop_off_idx = i
            break
    
    # If no clear drop found, look for the steepest negative derivative after peak
    if drop_off_idx is None:
        max_drop = 0.0
        for i in range(peak_idx + 1, min(len(energy_norm) - 1, search_end)):
            drop = energy_norm[i] - energy_norm[i + 1]  # Negative derivative
            if drop > max_drop:
                max_drop = drop
                drop_off_idx = i + 1
        
        # If still no clear drop, use a point slightly after the peak (10% of sample length)
        if drop_off_idx is None:
            drop_off_idx = min(peak_idx + max(1, int(len(energy_norm) * 0.1)), len(energy_norm) - 1)
    
    # Convert window index to time (in seconds)
    cue_time = (drop_off_idx * hop_size + window_size / 2) / float(sr)
    
    return cue_time


def samples_from_raw(raw: bytes, sampwidth: int) -> List[float]:
    """Convert raw audio bytes to float samples."""
    samples = []
    max_val = float(2 ** (8 * sampwidth - 1))
    
    if sampwidth == 1:
        # 8-bit unsigned
        for i in range(0, len(raw), sampwidth):
            val = raw[i]
            samples.append((val - 128) / 128.0)
    elif sampwidth == 2:
        # 16-bit signed
        for i in range(0, len(raw) - 1, sampwidth):
            val = int.from_bytes(raw[i:i+2], byteorder='little', signed=True)
            samples.append(val / max_val)
    elif sampwidth == 3:
        # 24-bit signed
        for i in range(0, len(raw) - 2, sampwidth):
            b0, b1, b2 = raw[i], raw[i+1], raw[i+2]
            val = (b0 | (b1 << 8) | (b2 << 16))
            if val & 0x800000:
                val -= 0x1000000
            samples.append(val / max_val)
    elif sampwidth == 4:
        # 32-bit signed
        for i in range(0, len(raw) - 3, sampwidth):
            val = int.from_bytes(raw[i:i+4], byteorder='little', signed=True)
            samples.append(val / max_val)
    else:
        return []
    
    return samples


def analyze_with_wave(path: str) -> Optional[Dict[str, float]]:
    """
    Analyze audio file using wave module with proper onset detection for cue points.
    Uses time-domain analysis + simple FFT for onset detection.
    """
    try:
        with wave.open(path, "rb") as wf:
            frames = wf.getnframes()
            sr = wf.getframerate()
            sampwidth = wf.getsampwidth()
            n_channels = wf.getnchannels()

            if frames == 0 or sr <= 0 or sampwidth == 0:
                return None

            # Read only first 2 seconds for faster analysis (enough for cue point detection)
            max_frames = min(frames, sr * 2)
            raw = wf.readframes(max_frames)
            if not raw:
                return None

            # Convert to mono if needed
            if n_channels > 1:
                try:
                    raw = audioop.tomono(raw, sampwidth, 0.5, 0.5)
                except Exception:
                    pass

            # Overall RMS (normalized)
            rms = audioop.rms(raw, sampwidth)
            max_val = float(2 ** (8 * sampwidth - 1))
            rms_norm = rms / max_val if max_val else 0.0

            # Convert raw bytes to float samples
            samples = samples_from_raw(raw, sampwidth)
            if not samples:
                return None
            
            # Calculate dominant frequency with a more reliable method
            dominant_freq = None

            try:
                if len(samples) >= 512:
                    # Pick the loudest window (up to 1 second) to avoid silence
                    window_len = min(sr, len(samples))
                    step = max(256, window_len // 4)
                    best_start, best_energy = 0, -1.0
                    for start in range(0, len(samples) - window_len + 1, step):
                        window_samples = samples[start:start + window_len]
                        energy = sum(x * x for x in window_samples)
                        if energy > best_energy:
                            best_energy = energy
                            best_start = start

                    analysis_samples = samples[best_start:best_start + window_len]
                    if not analysis_samples:
                        analysis_samples = samples[:window_len]

                    # Require a minimal energy to avoid picking silence
                    rms_energy = math.sqrt(sum(x * x for x in analysis_samples) / len(analysis_samples))
                    if rms_energy > 1e-6:
                        # Choose FFT size as power of two, capped for speed
                        fft_size = 1
                        while fft_size < len(analysis_samples):
                            fft_size <<= 1
                        fft_size = min(fft_size, 8192)

                        fft_input = analysis_samples[:fft_size]
                        if len(fft_input) < fft_size:
                            fft_input.extend([0.0] * (fft_size - len(fft_input)))

                        # Hann window to reduce leakage
                        window = [0.5 * (1 - math.cos(2 * math.pi * i / (fft_size - 1))) for i in range(fft_size)]
                        fft_input_windowed = [fft_input[i] * window[i] for i in range(fft_size)]

                        # FFT and magnitude
                        fft_result = simple_fft(fft_input_windowed)
                        magnitude = [abs(x) for x in fft_result]
                        half_mag = magnitude[:fft_size // 2]

                        # Skip DC and sub-audio; search 40 Hz to 6000 Hz
                        min_bin = max(1, int(40 * fft_size / sr))
                        max_bin = min(len(half_mag) - 1, int(6000 * fft_size / sr))

                        if max_bin > min_bin:
                            # Harmonic Product Spectrum to emphasize fundamentals
                            hps = half_mag[:max_bin + 1]
                            for r in (2, 3, 4):
                                for i in range(min_bin, max_bin // r):
                                    hps[i] *= half_mag[i * r]

                            # Noise floor estimate (median-based)
                            sorted_slice = sorted(hps[min_bin:max_bin + 1])
                            median_mag = sorted_slice[len(sorted_slice) // 2] if sorted_slice else 0.0
                            threshold = max(median_mag * 4.0, max(hps) * 0.02)

                            peak_bin = min_bin
                            peak_val = 0.0
                            for i in range(min_bin, max_bin + 1):
                                if hps[i] > peak_val:
                                    peak_val = hps[i]
                                    peak_bin = i

                            if peak_val > threshold:
                                dominant_freq = (peak_bin * sr) / fft_size
                                dominant_freq = max(40.0, min(8000.0, dominant_freq))

                # Fallback: zero-crossing estimate for simple tones
                if dominant_freq is None and len(samples) >= 256:
                    zc_samples = samples[:min(len(samples), sr)]
                    zero_crossings = 0
                    for i in range(1, len(zc_samples)):
                        prev, curr = zc_samples[i - 1], zc_samples[i]
                        if (prev >= 0 and curr < 0) or (prev <= 0 and curr > 0):
                            zero_crossings += 1
                    if zero_crossings > 2:
                        freq_est = (zero_crossings * sr) / (2 * len(zc_samples))
                        if 40.0 <= freq_est <= 8000.0:
                            dominant_freq = freq_est

            except Exception:
                # Silently fail - dominant_freq remains None
                pass

            # Detect sample type from filename/path (not audio content)
            sample_type = None
            path_lower = path.lower()
            # Check if "swell" appears in filename or path
            is_swell = "swell" in path_lower
            if is_swell:
                sample_type = "Swell"
            
            # Only build energy envelope and detect cue points for swells (skip expensive processing for others)
            snap_offset = None
            if is_swell:
                # Build energy envelope for swell cue point detection
                window_size = 512
                hop_size = 256
                energy_envelope = []
                for i in range(0, len(samples) - window_size + 1, hop_size):
                    window = samples[i:i + window_size]
                    energy = math.sqrt(sum(x * x for x in window) / len(window))
                    energy_envelope.append(energy)
                
                if energy_envelope:
                    # For swells: find the peak and then where energy drops off drastically
                    snap_offset = detect_swell_cue_point(samples, sr, energy_envelope, window_size, hop_size)

            result = {
                "dominant_freq": dominant_freq,
                "rms_energy": rms_norm,
            }
            if sample_type:
                result["sample_type"] = sample_type
            if snap_offset is not None:
                result["snap_offset"] = snap_offset

            return result
    except Exception as e:
        # Debug: uncomment to see errors
        # sys.stderr.write(f"analyze_with_wave error: {str(e)}\n")
        return None


def main() -> int:
    if len(sys.argv) < 2:
        sys.stderr.write("Usage: SampleMapAnalyzer.py /path/to/audio\n")
        return 1

    path = sys.argv[1]
    if not os.path.isfile(path):
        sys.stderr.write(f"File not found: {path}\n")
        return 1

    result = {}

    # Use wave analyzer (no external dependencies)
    data = analyze_with_wave(path)

    if data:
        # Only include fields that have valid values
        for k, v in data.items():
            if v is not None:
                result[k] = v
    
    sys.stdout.write(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())

