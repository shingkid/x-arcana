# X Arcana audio

These original effects use deterministic synthesis from Python's standard library.
No recordings, external samples, or additional dependencies are required.

Run this command from the `XArcana` directory:

```sh
python3 Tools/GenerateAudio.py
```

The generator writes signed 16-bit PCM WAV files at 24 kHz.
Spell effects are mono for compact, low-latency playback.
The 32-second room loop is stereo.
`manifest.json` records each file's duration, peak, RMS level, and SHA-256 hash.

| Effect | Layers |
| --- | --- |
| Zap | Electrical snap, falling pitch, low impact, short shimmer |
| Fireball | Rising rush, delayed blast, bass impact, rumbling tail |
| Ice | Glass crack, crystalline partials, scattered splinters |
| Shield | Low arrival, resonant gong, sustained harmonic dome |
| Summon | Rising portal, bass impact, layered magical chord |
| Demon | Two restrained growls and a low arrival impact |
| Patronus | Airy chord, rising arrival, long silver chime |
| Revelio | Sweeping tone and shimmering discovery chimes |
| Lumos | Warm bell, soft harmonic body, airy tail |
| Sparks | Short, quieter scattered chimes |

The generator removes DC from effects and applies soft saturation before peak and RMS gain limits.
It preserves short fades at effect boundaries and a continuous ambience loop seam.
The runtime caches prepared players and uses a shared headroom budget when casts overlap.
It does not change device volume or force a different audio route.
The longer impacts and layered tails provide scale without increasing normal playback gain.

`AudioTests.swift` checks decoding, channel layout, signal bounds, effect mappings, overlap headroom, and playback interruption recovery.
Numerical checks do not replace listening on the intended output device.

## Licensed music

“Nyan Cat” by daniwell (Momone Momo vocals) is the official recording from [the creator's catalog](https://aidn.jp/sound/).
The 27-second excerpt is permitted for this noncommercial derivative game with title and artist credit under [the creator's terms](https://daniwell.com/about/).
This recording is not CC0; commercial use needs separate permission.
Its original, permission record, and preparation script are in `Fantasy Sources/Nyan Music`.
Regenerate it separately with `python3 "Fantasy Sources/Nyan Music/prepare.py"`.
The synthetic sound generator does not replace the licensed music.
