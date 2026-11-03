# Dash illustrated redesign

2026-11-03. Current illustration version. A finished, coherent singing illustration was generated first from a Dash-inspired sticker reference, then used to generate three complete poses for each costume. Face, garment overlap, microphone grip and megaphone contact are drawn together rather than reconstructed from independently generated facial/limb pieces. The generated illustration's authored colors and shading are preserved without palette quantization.

- Sources: `sources/master.png` and three original pose sheets. Built-in image_gen prompts and repository-relative source paths are in [generation-prompts.json](generation-prompts.json).
- Nine transparent poses: three costumes × greeting / handheld microphone / megaphone. `scripts/normalize.py` uses alpha connectivity to separate the complete figures, remove detached debris and repair opaque-region pinholes. Bottom-foot centroids provide a shared anchor. Source art is not repainted.
- Blender: [dash_2d.blend](dash_2d.blend), 20 bones, 16 weighted meshes. Each illustrated pose uses a 64×80 deformable grid and UV texture. Local falloffs move wings and the singing beak subtly; the megaphone gesture remains coherent to preserve grip and mouthpiece alignment.
- Eight NLA loops: idle, listen, speak, wave, celebrate, reconnect, sing, megaphone. The same app state names are retained. Notes, stars and outward sound waves have independent animated bones.
- Expressions are authored in the three pose illustrations. This revision does not retain the old independent blinking-eye layers; it does not claim phoneme lip sync. Instead it uses soft mesh motion and pose changes to preserve illustration quality.
- Runtime: 24 RGBA atlases, 512px tiles, 24 frames per clip at 12fps. App and native overlay asset paths are unchanged. Earlier experiments are not included in the public repository.

## Requirements

Blender (tested with 5.2.2 LTS), Python with `Pillow` and `mcp`, and the official Blender Lab MCP server/CLI (`blender-mcp`) for the helper workflow. Configure `BLENDER_PATH` for your Blender executable and `BLENDER_MCP_PORT` for the server. These authoring tools are optional; the app uses committed atlases.

## Reproduce

1. Use Python with Pillow installed and run `python art/dash_2d/illustrated/scripts/normalize.py` from the repository root. Source images are already included.
2. Run `scripts/build_rig.py` through official Blender Lab MCP (`tools/blender_lab.py execute-cli`) with an existing .blend as seed.
3. Run `scripts/render_{hanbok,gat,dancheong}.py` against this source through the same MCP.
4. Run `tools/package_dash_2d.py art/dash_2d/illustrated`.
5. Run `scripts/validate_rig.py` through official MCP, then capture Flutter test screens and build macOS.

[Motion review](renders/motion-preview.webp) · [Compact style review](renders/style-preview.webp) · [All clips](renders/contact-sheet.jpg)
