# Verification record

## Local simulation

Godot 4.7.2 stable, Linux, headless:

- `tests/test_terrain.gd`: **33 checks passed**.
- `tests/tests_gameplay.gd`: **52 checks passed**.
- Main scene starts without script/runtime errors.
- `git diff --check`: clean before publication.

Notable regressions covered: a hard landing that starts a frame exactly at the
surface must still deal fall damage; victory is delayed until all surviving
units finish falling, so two final water deaths correctly produce a draw.
Mouse buttons consume event coordinates in the centered game canvas, avoiding
stale pointer queries after fullscreen/window resize.

## Native cloud desktop

Played on the dot's cloud Linux desktop using Godot's Compatibility renderer
(Mesa llvmpipe software rendering, not a hardware-GPU benchmark). Verified the
actual window and screenshots, movement, jumping, hold/release fire, terrain
craters, knockback, water elimination, alternating turns and the help overlay.
HD revision also verified fullscreen transition and mouse weapon selection in
both windowed and fullscreen layouts. SVG artwork imports were checked at
320×232 per tank with generated mipmaps and explicit linear-mipmap sampling.
A deterministic native capture runs the same real simulation to exercise
normal and split shells, using a true 1920×1080 native SubViewport (not image
upscaling). The cloud desktop only exposes physical display modes up to
1364×1024, so literal desktop fullscreen 1080p is not claimed. The game itself
uses a 16:9 composition and supports normal fullscreen on the available display.

HD revision checks also cover continuous collision/visual agreement at a fresh
crater edge, subpixel-continuous distance evaluation, and reconstructed crater
boundaries remaining within one topology cell of the carved circle.

Capture media is intentionally outside the Git repository. No generated video,
GIF, engine binaries, export templates, `.godot` cache or ZIP is committed.

## Remote checks

The repository was empty at the start and has no existing CI workflow. Local
simulation and native desktop verification are recorded above; no CI pass is
claimed. The published commit is verified against the remote main branch.

## Deliberate limitations

Local hotseat only; no AI, network multiplayer or save game. A 3-pixel topology
grid is reconstructed as a continuous surface for both drawing and edge
collision. Detached terrain chunks
fall vertically without rigid-body rotation. Fixed overview camera preserves
the whole battlefield; projectiles above it use an offscreen marker.
