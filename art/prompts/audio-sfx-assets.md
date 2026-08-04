# Audio SFX asset prompt

Use this prompt for short sound-effect candidates such as shot, impact,
explosion, and UI sounds.

Return one JSON media asset candidate using `media-asset/v1`:

- Kind: `audio`.
- Format: WAV PCM16 for review and source control; OGG can be introduced later
  if APK size demands it.
- Sample rate: 44100 Hz.
- Channels: mono unless stereo placement is part of the task.
- Duration: shot sounds under 0.22s, impact/explosion sounds under 0.45s, UI
  sounds under 0.20s.
- Peak: below 0.90 normalized peak, no clipped samples, no long silence before
  or after the transient.
- Loop: false for shot, impact, explosion, and UI effects.
- Output path: `assets/audio/<asset_id>.wav`.
- Include prompt, seed, cleanup, licensing/provenance, and approval metadata.

Do not add music, voice, or licensed sample-pack material without a separate
task and explicit provenance review.
