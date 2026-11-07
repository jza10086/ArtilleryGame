# References and asset provenance

ArtilleryGame is an independent implementation. The code references below were inspected for concepts. Kenney Tanks is the external artwork used by the current tank scene, as documented below.

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

The battlefield artwork and effects are original. No BarrageFest or Alpacos artwork is included.

The current tank uses **Kenney Tanks** by Kenney Vleugels, CC0.
- Official asset page: https://kenney.nl/assets/tanks
- Author-published download: https://opengameart.org/content/tank-pack-80
- Source package: https://opengameart.org/sites/default/files/kenney_tanksPack.zip
- Included original Retina PNGs: `tanks_tankGrey_body2.png`, `tanks_tankTracks2.png`, `tanks_turret1.png`.
- Local assets and original license: `assets/kenney_tanks/`.
- Adaptation: scene-only sprite regions split the hull and turret; player tint, independent elevation, recoil and muzzle binding are applied in Godot. Source images are unchanged.

## Reuse boundary

Upstream licenses are documented for transparency; they do not become the
license of this independent project merely because their gameplay ideas were
studied. Any later copying or adaptation of upstream source must be reviewed
separately and must preserve the notices and license conditions that apply.

## ShellShock Live

- Official reference: https://www.shellshocklive.com/
- Concepts: multiplayer turn-based artillery, destructible landscapes, distinct ballistic weapons, dark layered scenery and bright battlefield silhouettes.
- The GodotParty implementation uses independent rules, original battlefield effects and the credited Kenney tank sprites; no ShellShock Live assets or source are included.

- Event reference: https://store.steampowered.com/news/posts/?appgroupname=ShellShock+Live&appids=326460&enddate=1645653731&feed=steam_community_announcements (official v1.0 notes: X3 buffs, Vortex portals, bumpers and attack drones). Shapes and event rules are implemented independently; no reference artwork is shipped.
