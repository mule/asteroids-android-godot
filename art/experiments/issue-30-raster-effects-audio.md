# Issue 30 raster, effects, and audio slice

Date: 2026-08-04

## Goal

Prove the asset pipeline can handle a small non-vector vertical slice without a
full art overhaul: one raster presentation asset, one visual effect asset, and
two short audio effects.

## Selected assets

- `background_starfield_01`: deterministic PNG background, 1152x648 RGBA,
  intentionally low contrast so generated asteroid variants remain readable.
- `effect_impact_flash_01`: deterministic 128x128 RGBA impact flash with
  transparent alpha, layered behind existing line sparks.
- `sfx_shot_spark_01`: mono 44.1 kHz PCM16 WAV shot chirp, trimmed to 0.16s.
- `sfx_impact_thump_01`: mono 44.1 kHz PCM16 WAV asteroid impact thump,
  trimmed to 0.32s.

## What AI helped with

Codex drafted the schema split, prompt templates, deterministic generator,
validator, and runtime integration points. The assets in this slice are
procedural rather than provider-generated so the pipeline can be verified
without API keys or external model caches.

## Manual cleanup and review notes

- Background contrast was kept deliberately restrained; brighter nebula passes
  competed with ship, bullet, and asteroid silhouettes.
- Impact flash size was limited to 128x128 and a short tween because the
  existing line sparks already carry motion.
- Audio envelopes were trimmed short to avoid muddy overlap during rapid fire
  and asteroid splitting.
- WAV was retained for this slice because files are short and easier to inspect;
  OGG compression can be introduced when longer sounds make APK size meaningful.

## Verification notes

Run before approval:

```sh
python3 tools/asset_pipeline/build_media_assets.py --check
python3 tools/asset_pipeline/validate_media_assets.py art/approved/media
python3 -m unittest tests.asset_pipeline.test_media_assets
/home/japurane/.local/bin/godot --headless --path . --quit
/home/japurane/.local/bin/godot --headless --path . --script tools/asset_pipeline/check_runtime_variants.gd
```

Android acceptance should include debug APK export, install, launch, and a size
comparison against the previous debug APK when available.
