# References and asset provenance

ArtilleryGame is an independent implementation. The projects below were inspected
as conceptual references; their source code and artwork were not copied into
this project.

## BarrageFest

- Game page: https://ega-supremo.itch.io/barragefest
- Official source linked by that page: https://github.com/EGA-SUPREMO/Course-Notes-Godot
- Upstream code license: GNU GPL 3.0 (`LICENSE.txt`).
- The game page separately labels its artwork CC BY 4.0 and describes Hololive
  fan-mascot characters. That artwork is not used here.
- Concepts reviewed: subtracting an explosion polygon from terrain polygons;
  separating collision, rendering, and explosion effects; explicit player
  action states; ballistics visualization; multiple projectile behaviors.
- Relevant upstream files: `scripts/terrain.gd`, `scripts/missile.gd`,
  `scripts/trajectory.gd`, and `scripts/states/`.
- BarrageFest is described by its author as a real-time artillery prototype;
  it is not used as a complete sequential-turn implementation.

## Alpacos

- Official source: https://github.com/Loethor/Alpacos
- Upstream license: MIT, copyright 2023 Luis Roma (`LICENSE`).
- Concepts reviewed: procedural terrain, circular alpha-mask terrain damage,
  image-derived collision outlines, independently composed aiming/charging/
  explosion components, and a timed physical grenade.
- Relevant upstream files: `levels/level_generator.gd`, `items/grenade.gd`,
  `components/`, `characters/alpaca.gd`, and `game/game_state.gd`.
- The inspected game-state script contains wind selection and a turn-duration
  constant, not a complete turn controller. ArtilleryGame's match and turn
  control are implemented independently.

## Artwork

The artwork shipped with ArtilleryGame is original project artwork. No
BarrageFest or Alpacos artwork is included.

Kenney's side-view **Tanks** pack was also researched as a possible alternative:
https://kenney.nl/assets/tanks . Its official page and included license identify
it as CC0. That pack is not included in this version. If added in a later
version, retain its provenance and keep this statement accurate.

## Reuse boundary

Upstream licenses are documented for transparency; they do not become the
license of this independent project merely because their gameplay ideas were
studied. Any later copying or adaptation of upstream source must be reviewed
separately and must preserve the notices and license conditions that apply.
