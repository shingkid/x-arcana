"""Prepare the licensed 27-second Nyan Cat excerpt with macOS audio tools and stdlib."""
from array import array
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import wave

ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT.parents[1] / 'Audio'
RATE = 24000
SECONDS = 27
SOURCE = ROOT / 'nyancat-original.mp3'
metadata = json.loads((ROOT / 'source.json').read_text())
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == metadata['sha256'], 'Source changed'
with tempfile.TemporaryDirectory(prefix='xarcana-nyan-') as temporary:
    decoded = Path(temporary) / 'decoded.wav'
    subprocess.run(['/usr/bin/afconvert', str(SOURCE), str(decoded), '-f', 'WAVE',
                    '-d', 'LEI16@24000', '-c', '2'], check=True)
    with wave.open(str(decoded), 'rb') as audio:
        assert audio.getframerate() == RATE and audio.getsampwidth() == 2
        assert audio.getnchannels() == 2 and audio.getnframes() >= RATE * SECONDS
        pcm = array('h', audio.readframes(RATE * SECONDS))
if sys.byteorder != 'little':
    pcm.byteswap()
samples = [value / 32768 for value in pcm]
# Only a short click-free entrance/exit and constant gain. No pitch, tempo, or melody edits.
for index in range(len(samples)):
    t = (index // 2) / RATE
    samples[index] *= min(1, t / 0.015, max(0, (SECONDS - 1 / RATE - t) / 0.12))
peak = max(map(abs, samples))
rms = max(math.sqrt(sum(value * value for value in samples[channel::2]) / (len(samples) // 2))
          for channel in range(2))
gain = min(0.50 / max(peak, 0.001), 0.14 / max(rms, 0.001))
pcm = array('h', (round(value * gain * 32767) for value in samples))
peak = max(abs(value) for value in pcm) / 32768
rms = max(math.sqrt(sum((value / 32768) ** 2 for value in pcm[channel::2]) / (len(pcm) // 2))
          for channel in range(2))
assert peak <= 0.50004 and rms <= 0.14004
assert pcm[0] == pcm[1] == pcm[-1] == pcm[-2] == 0
if sys.byteorder != 'little':
    pcm.byteswap()
OUTPUT.mkdir(exist_ok=True)
target = OUTPUT / 'nyan.wav'
with wave.open(str(target), 'wb') as audio:
    audio.setnchannels(2)
    audio.setsampwidth(2)
    audio.setframerate(RATE)
    audio.writeframes(pcm.tobytes())
report = {**metadata, 'resource': 'Audio/nyan.wav', 'source_start_seconds': 0,
          'duration_seconds': SECONDS, 'sample_rate': RATE, 'channels': 2,
          'pcm_bits': 16, 'peak': peak, 'rms': rms, 'gain': gain,
          'sha256_pcm_resource': hashlib.sha256(target.read_bytes()).hexdigest()}
(OUTPUT / 'nyan-source.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({key: report[key] for key in ['resource', 'duration_seconds', 'peak', 'rms', 'sha256_pcm_resource']}, indent=2))
