# Verification record

## Local simulation

Godot 4.7.2 stable, Linux, headless:

- `tests/test_terrain.gd`: **30 checks passed**.
- `tests/tests_gameplay.gd`: **52 checks passed**.
- Main scene starts without script/runtime errors.
- `git diff --check`: clean before publication.

Notable regressions covered: a hard landing that starts a frame exactly at the
surface must still deal fall damage; victory is delayed until all surviving
units finish falling, so two final water deaths correctly produce a draw.

## Native cloud desktop

Played on the dot's cloud Linux desktop using Godot's Compatibility renderer
(Mesa llvmpipe software rendering, not a hardware-GPU benchmark). Verified the
actual window and screenshots, movement, jumping, hold/release fire, terrain
craters, knockback, water elimination, alternating turns and the help overlay.
A deterministic native capture runs the same real simulation to exercise
normal and split shells and record clear gameplay/impact frames.

Capture media is intentionally outside the Git repository. No generated video,
GIF, engine binaries, export templates, `.godot` cache or ZIP is committed.

## Remote checks

The repository was empty at the start and has no existing CI workflow. Local
simulation and native desktop verification are recorded above; no CI pass is
claimed. The published commit is verified against the remote main branch.

## Deliberate limitations

Local hotseat only; no AI, network multiplayer or save game. A 3-pixel terrain
cell trades subpixel edges for predictable collisions. Detached terrain chunks
fall vertically without rigid-body rotation. Fixed overview camera preserves
the whole battlefield; projectiles above it use an offscreen marker.
