# Nyan Cat music

“Nyan Cat” by daniwell, with Momone Momo vocals.
The original recording is the 2011-04-05 entry in the [official music catalog](https://aidn.jp/sound/).
The original MP3 is retained unchanged as `nyancat-original.mp3`.
Its official source, catalog entry, and checksum are in `source.json`.

The [creator's published permission](https://daniwell.com/about/) was checked on 2026-11-25.
It permits music published on the creator's site in noncommercial derivative games when the song title and artist are credited.
X Arcana uses this recording for personal, non-commercial play.
This recording is not CC0.
Commercial use requires separate permission.
A dated copy of the permission page is retained in this folder.

Required visible credit: **“Nyan Cat” by daniwell (Momone Momo vocals).**
Retain that credit and these terms in shared noncommercial packages.

From the `XArcana` folder, run:

```sh
python3 "Fantasy Sources/Nyan Music/prepare.py"
```

The script uses macOS `afconvert` and the Python standard library.
It exports the first 27 seconds as `Audio/nyan.wav`, with stereo, 24 kHz, 16-bit PCM.
It applies constant gain and short endpoint fades for quiet, click-free playback.
It does not change the melody, tempo, or pitch.
It records format, duration, peak, RMS, and checksum in `Audio/nyan-source.json`.
The game starts and stops this excerpt with the spell timer.
