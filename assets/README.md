# Original artwork

`background.svg`, `tank_coral.svg`, `tank_mint.svg`, and `icon.svg` were drawn specifically for this project as original SVG artwork. No third-party game sprites, mascots, logos, or code were traced or copied.

These four SVG files are released under **CC0 1.0 Universal** (public domain dedication): https://creativecommons.org/publicdomain/zero/1.0/ . Attribution is not required.

## Integration

- Background: a 1440 × 900 logical canvas, imported at **2880 × 1800 (2×)** for crisp high-definition rendering. Smooth vector curves, layered gradients, and rounded coastal silhouettes; no pixel-art texture. Sun at (1110, 190), water horizon around y=725. Foreground gameplay water can be placed at y=790.
- Tanks: transparent 80 × 58 logical canvas, imported at **320 × 232 (4×)**. Smooth rounded designer-toy forms, gradient volumes, and simplified wheel/face details. Ground contact at y=55, body/turret pivot about (40, 24). Barrel deliberately omitted for independently rotating gameplay barrel. SVGs face neither direction and may be mirrored. For drawing at a physics foot position, suggested image offset is (-40, -55).
- Icon: 128 × 128 logical canvas, imported at **512 × 512 (4×)**.
- Palette: navy outlines `#294653`, coral `#ed9178`, mint `#81c6b2`, warm paper `#f7edcf`.
- All SVG sources remain resolution-independent; use linear/mipmap filtering for scaled rendering, not nearest-neighbor filtering.

## Fonts

`ui.ttf` and `ui_bold.ttf` are DejaVu Sans and DejaVu Sans Bold, bundled from the system DejaVu distribution. They are **not CC0**; their original Bitstream Vera/DejaVu notices and redistribution terms are preserved in `FONT_LICENSE.txt`.

Artwork textures generate mipmaps and use explicit linear-mipmap sampling in game, so the high-resolution tank curves remain smooth when drawn at small gameplay sizes. The terrain's signed-distance texture has a separate linear sampler and is reconstructed analytically by its shader.
