"""Regenerate X Arcana's original layered sound effects with Python's standard library."""

from array import array
import hashlib
import json
import math
from pathlib import Path
import random
import sys
import wave

RATE = 24000
OUTPUT = Path(__file__).resolve().parents[1] / "Audio"
TAU = 2 * math.pi
REPORT = {}


def envelope(t, duration, attack=0.006, release=0.12):
    return min(1, max(0, t / attack)) * min(1, max(0, (duration - t) / release))


def hit(t, start, high, low, decay, gain=1):
    """A phase-continuous descending impact, with a short click-free attack."""
    age = t - start
    if age < 0:
        return 0
    phase = TAU * (low * age + (high - low) * (1 - math.exp(-age * 13)) / 13)
    return gain * math.sin(phase) * math.exp(-age * decay) * min(1, age / .004)


def bell(t, start, frequencies, decay, gain=1):
    age = t - start
    if age < 0:
        return 0
    partials = sum(math.sin(TAU * frequency * age) * math.exp(-age * decay * (1 + index * .18))
                   / (1 + index * .7) for index, frequency in enumerate(frequencies))
    return gain * partials * min(1, age / .008)


def write(name, channels, peak=.64, echoes=True, rms_limit=.16):
    loop = name == "ambience"
    for side, samples in enumerate(channels):
        if echoes:
            dry = samples[:]
            for delay, gain in [(.031, .18), (.071, .14), (.119, .11), (.181, .08),
                                (.263, .055), (.359, .04), (.487, .025)]:
                offset = int(delay * RATE)
                for i in range(offset, len(samples)):
                    samples[i] += dry[i - offset] * gain
        if not loop:
            # Remove DC and excessive sub-bass while retaining the audible impact body.
            coefficient = math.exp(-TAU * 24 / RATE)
            previous_input = previous_output = 0
            for i, value in enumerate(samples):
                filtered = value - previous_input + coefficient * previous_output
                previous_input, previous_output = value, filtered
                samples[i] = filtered * envelope(i / RATE, len(samples) / RATE, .003, .08)
        # Smooth saturation before final gain avoids hard clipping on layered transients.
        channels[side] = [math.tanh(value * 1.3) / 1.3 for value in samples]
    maximum = max(abs(value) for samples in channels for value in samples)
    rms = math.sqrt(sum(value * value for samples in channels for value in samples)
                    / sum(len(samples) for samples in channels))
    gain = min(peak / max(maximum, .001), rms_limit / max(rms, .001))
    pcm = array("h")
    for frame in zip(*channels):
        pcm.extend(round(value * gain * 32767) for value in frame)
    assert all(-32767 < sample < 32767 for sample in pcm), name + " clipped"
    peak_actual = max(abs(sample) for sample in pcm) / 32767
    rms_actual = math.sqrt(sum((sample / 32767) ** 2 for sample in pcm) / len(pcm))
    if sys.byteorder != "little":
        pcm.byteswap()
    OUTPUT.mkdir(exist_ok=True)
    path = OUTPUT / (name + ".wav")
    with wave.open(str(path), "wb") as sound:
        sound.setnchannels(len(channels))
        sound.setsampwidth(2)
        sound.setframerate(RATE)
        sound.writeframes(pcm.tobytes())
    REPORT[name] = {"sample_rate": RATE, "channels": len(channels), "bits": 16,
        "duration_seconds": len(channels[0]) / RATE, "peak": round(peak_actual, 6),
        "peak_dbfs": round(20 * math.log10(max(peak_actual, 1e-9)), 2),
        "rms_dbfs": round(20 * math.log10(max(rms_actual, 1e-9)), 2),
        "peak_ceiling": peak, "clipped_samples": 0,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def spell(name, duration):
    randomizer = random.Random("X Arcana layered " + name)
    samples = []
    phase = low = air = 0
    for i in range(int(round(duration * RATE))):
        t = i / RATE
        noise = randomizer.uniform(-1, 1)
        low += .022 * (noise - low)
        air += .20 * (noise - air)
        fizz = noise - air
        if name == "zap":
            phase += TAU * (150 + 2400 * math.exp(-t * 15)) / RATE
            arcs = .32 + .68 * math.sin(TAU * 49 * t) ** 8
            value = (.58 * math.sin(phase) + .26 * fizz * arcs) * math.exp(-t * 7)
            value += hit(t, 0, 145, 48, 5, .72)
            value += bell(t, .035, [1250, 1880, 2790], 5, .16)
            value += low * 2.2 * math.exp(-t * 4)
        elif name == "fireball":
            rush = min(1, t / .16) * math.exp(-max(0, t - .40) * 8)
            value = (low * 4.8 + air * .38 + fizz * .035) * rush
            age = max(0, t - .42)
            value += hit(t, .42, 128, 44, 3.8, 1.05)
            value += hit(t, .435, 240, 79, 7, .42)
            if t >= .42:
                value += (air * .65 + low * 3.4) * math.exp(-age * 4)
            value += bell(t, .48, [310, 467, 933], 4.2, .11)
        elif name == "ice":
            freeze = min(1, t / .04) * math.exp(-t * 4.2)
            phase += TAU * (680 + 1600 * min(t, .4)) / RATE
            value = (.10 * math.sin(phase) + fizz * .14) * freeze
            value += hit(t, .012, 310, 108, 9, .35)
            value += bell(t, .018, [1180, 1873, 2811, 3747], 2.7, .37)
            for start, frequency in [(.075, 2310), (.145, 3117), (.23, 1673), (.36, 2693)]:
                value += bell(t, start, [frequency, frequency * 1.37], 7, .12)
        elif name == "shield":
            value = hit(t, .012, 155, 51, 3.3, .70)
            value += bell(t, .015, [174.6, 261.6, 523.2, 1046.4], 1.9, .46)
            dome = min(1, t / .075) * math.exp(-t * 2.5)
            value += (.13 * math.sin(TAU * 349.2 * t + .7 * math.sin(TAU * 4.2 * t))
                      + air * .15) * dome
            value += bell(t, .20, [1396.8, 2095.2], 3.5, .10)
        elif name == "summon":
            opening = min(1, t / .15) * math.exp(-t * 1.7)
            phase += TAU * (83 + 90 * min(t, .9)) / RATE
            portal = math.sin(phase + .65 * math.sin(phase * .5)) + .32 * math.sin(phase * 1.498)
            value = (.45 * portal + low * 3.0 + air * .12) * opening
            value += hit(t, .16, 114, 41, 2.3, .78)
            value += bell(t, .24, [220, 329.63, 440, 659.25, 1318.5], 1.55, .22)
            value += bell(t, .68, [880, 1320, 1980], 2.4, .10)
        elif name == "sparks":
            value = bell(t, 0, [1680, 2520], 12, .22)
            value += bell(t, .055, [2240, 3136], 13, .18)
            value += bell(t, .12, [2870, 4018], 15, .11)
            value += fizz * .035 * math.exp(-t * 18)
        elif name == "revelio":
            phase += TAU * (320 + 850 * t / duration) / RATE
            sweep = math.sin(math.pi * t / duration) ** 1.3
            value = (.28 * math.sin(phase) + .14 * math.sin(phase * 1.5) + air * .16) * sweep
            value += bell(t, .20, [659.25, 987.77, 1318.5], 2.7, .12)
            value += hit(t, .025, 115, 66, 5, .15)
        elif name == "lumos":
            value = bell(t, 0, [523.25, 1046.5, 1569.75, 2093], 2.3, .36)
            value += bell(t, .14, [659.25, 1318.5], 2.5, .16)
            value += .14 * math.sin(TAU * 261.63 * t) * min(1, t / .05) * math.exp(-t * 2)
            value += air * .06 * math.exp(-t * 3)
        else:  # Patronus: a broad, airy chord with a clear rising arrival.
            rise = min(1, t / .22) * math.exp(-t * .95)
            chord = sum(math.sin(TAU * f * t + math.sin(TAU * .8 * t) * .18)
                        for f in [196, 293.66, 392, 587.33]) * .19
            value = (chord + low * 2.1 + air * .10) * rise
            value += hit(t, .08, 98, 49, 2.7, .30)
            value += bell(t, .28, [784, 1174.66, 1568, 2349.32], 1.7, .19)
        samples.append(value * envelope(t, duration))
    write(name, [samples], peak=.40 if name == "sparks" else .64,
          rms_limit=.10 if name == "sparks" else .16)


def demon():
    duration = 3.6
    randomizer = random.Random("X Arcana demon arrival")
    samples = []
    phase = breath = 0
    for i in range(int(round(duration * RATE))):
        t = i / RATE
        voice = 0
        for start, length in [(.18, 1.35), (1.55, 1.60)]:
            if start <= t < start + length:
                voice = math.sin(math.pi * (t - start) / length) ** .8
        pitch = 57 + 8 * math.sin(TAU * 1.1 * t) + 3 * math.sin(TAU * 7 * t)
        phase += TAU * pitch / RATE
        rasp = sum(math.sin(phase * harmonic) / harmonic ** .9 for harmonic in range(1, 9))
        noise = randomizer.uniform(-1, 1)
        breath += .11 * (noise - breath)
        growl = math.tanh(rasp * 1.5) * (.78 + .22 * math.sin(TAU * 19 * t)) + breath * .5
        value = growl * voice + hit(t, .08, 89, 39, 2.6, .40)
        samples.append(value * envelope(t, duration))
    write("demon", [samples], peak=.52, rms_limit=.12)


def ambience():
    duration = 32
    overlap = int(RATE * 0.8)
    length = duration * RATE
    channels = []
    for side in range(2):
        randomizer = random.Random(400 + side)
        air = 0
        low = 0
        samples = []
        for i in range(length + overlap):
            t = i / RATE
            noise = randomizer.uniform(-1, 1)
            low += 0.012 * (noise - low)
            air += 0.18 * (noise - air)
            breeze = 0.7 + 0.3 * math.sin(TAU * t / 11 + side)
            drone = math.sin(TAU * 55 * t) + 0.5 * math.sin(TAU * 82.5 * t + side * 0.2)
            chime = 0
            for start, frequency in [(5.3 + side, 392), (19.7 - side, 523.25), (27 + side, 659.25)]:
                age = t - start
                if 0 < age < 4:
                    chime += math.sin(TAU * frequency * age) * math.exp(-age * 1.4) * min(1, age * 12)
            samples.append(low * 1.4 + air * 0.045 * breeze + drone * 0.018 + chime * 0.012)
        # Crossfade an extra tail into the beginning for a continuous room loop.
        for i in range(overlap):
            weight = (1 - math.cos(math.pi * i / (overlap - 1))) / 2
            samples[i] = samples[length + i] * (1 - weight) + samples[i] * weight
        correction = samples[0] - samples[length - 1]
        for i in range(128):
            samples[length - 128 + i] += correction * (1 - math.cos(math.pi * i / 127)) / 2
        channels.append(samples[:length])
    write("ambience", channels, peak=.28, echoes=False, rms_limit=.06)


if __name__ == "__main__":
    for name, duration in [("zap", 1.15), ("fireball", 1.95), ("ice", 1.65), ("shield", 1.9),
                           ("summon", 2.8), ("sparks", .8), ("revelio", 1.9),
                           ("lumos", 1.8), ("patronus", 3.4)]:
        spell(name, duration)
    demon()
    ambience()
    (OUTPUT / "manifest.json").write_text(json.dumps({
        "generator": "Tools/GenerateAudio.py", "format": "signed 16-bit little-endian PCM WAV",
        "processing": "layered synthesis, diffuse echoes, soft saturation, peak and RMS headroom",
        "sounds": REPORT}, indent=2, sort_keys=True) + "\n")
    print("Created", len(REPORT), "original WAV files in", OUTPUT)
    for name, row in REPORT.items():
        print(name, row["duration_seconds"], "s; peak", row["peak_dbfs"], "dBFS; RMS", row["rms_dbfs"], "dBFS")
