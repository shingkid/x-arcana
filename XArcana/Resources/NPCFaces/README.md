# Public placeholder texture regions

`Resources/NPCFaces/regions.json` contains authored coordinates for the generated robot icons.
These are geometric construction coordinates, not detected human facial landmarks.
Each record sets `faceDetected` to `false` and records procedural provenance.
No photograph or private face-analysis record is required or included.

Each row preserves the `id`, `name`, and `image` fields from `NPCPortraits/roster.json`.
The image paths are relative to `Resources/NPCPortraits`.
All images are 256 by 256 pixels.
Coordinates are normalized from zero to one, with the origin at the bottom left.
The eye and mouth coordinates align the robot artwork with the runtime zombie face surface.
The renderer requires only `faceRect`, `leftEye`, `rightEye`, and `mouth`.

Run `python3 XArcana/Tools/PreparePublicAssets.py --portraits-only` to regenerate the icons and this coordinate data.
The generated icons and metadata are CC0 1.0 Universal.
The generated hashes are in `Resources/PublicAssets.json`.
