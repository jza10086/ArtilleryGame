# 炮火争锋音效来源

以下素材可商用。原始音频未重编码；三个标记为 _short.wav 的派生文件经过截取、8 ms 淡入与尾部淡出。游戏通过 PartyAudioCue 调整音高、音量及并发。

| 素材 | 作者 | 来源与许可 | 本包文件及修改 |
| --- | --- | --- | --- |
| Engine-loop heavy vehicle/tank | Nayckron；原始循环／协作者 qubodup | [来源](https://opengameart.org/content/engine-loop-heavy-vehicletank) · [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)（选择该许可） | engine/engine_heavy_loop.ogg，下载原名 engine_heavy_loop_1.ogg；仅改名，运行时淡入淡出。署名与许可链接见 engine/LICENSE.txt。 |
| Explosions | EZduzziteh | [来源](https://opengameart.org/content/explosions-4) · [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | explosions/explosion1–4.ogg；来源文件 explosion1_0.ogg、explosion2.ogg、explosion3.ogg、explosions4.ogg，仅统一命名；许可全文见 explosions/LICENSE-CC0.txt。 |
| Sci-Fi Sounds 1.0 | Kenney | [官方网站](https://kenney.nl/assets/sci-fi-sounds) · [作者上传下载页](https://opengameart.org/content/sci-fi-sounds) · [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | kenney/ 下同名 OGG，来自 sci-fi_sounds.zip 的 Audio/。保留 License.txt；engineCircular_002_short.wav 截取前 0.42 秒、尾淡出 0.08 秒；computerNoise_002_short.wav 前 0.22 秒、尾淡出 0.05 秒；thrusterFire_000_short.wav 前 1.6 秒、尾淡出 0.4 秒。 |

## 声音映射

16 种炮弹各有独立命中 Cue；开炮分为普通、重炮、散射、能量、等离子和布雷六组。子母弹／弹雨的空中分裂与落地命中分别触发；跳弹碰撞、钻地入口、地雷布设与五段连锁震爆均按主机事件播放。发动机仅在成功移动期间连续循环。

| Cue | 本地音频 | 音量 dB | 音高 |
| --- | --- | --- | --- |
| engine | engine/engine_heavy_loop.ogg | -19 | 1 |
| fire_cannon | explosions/explosion2.ogg | -11 | 1.35 |
| fire_heavy | kenney/lowFrequency_explosion_001.ogg | -13 | 1.1 |
| fire_scatter | explosions/explosion4.ogg | -13 | 1.65 |
| fire_energy | kenney/laserLarge_000.ogg | -14 | 0.85 |
| fire_plasma | kenney/laserSmall_002.ogg | -12 | 1 |
| fire_mine | kenney/impactMetal_000.ogg | -11 | 0.75 |
| impact_standard | explosions/explosion3.ogg | -10 | 1 |
| impact_heavy | kenney/lowFrequency_explosion_000.ogg | -10 | 0.78 |
| impact_scatter | kenney/explosionCrunch_000.ogg | -16 | 1.45 |
| impact_cluster | kenney/explosionCrunch_001.ogg | -16 | 1.15 |
| impact_bounce | explosions/explosion1.ogg | -12 | 1.15 |
| impact_drill | kenney/lowFrequency_explosion_001.ogg | -11 | 0.85 |
| impact_build | kenney/explosionCrunch_004.ogg | -13 | 0.65 |
| impact_siphon | kenney/slime_000.ogg | -10 | 1 |
| impact_roller | explosions/explosion4.ogg | -10 | 0.8 |
| impact_rain | kenney/explosionCrunch_002.ogg | -18 | 1.6 |
| impact_fire | kenney/thrusterFire_000_short.wav | -12 | 0.75 |
| impact_emp | kenney/laserLarge_002.ogg | -13 | 0.65 |
| impact_teleport | kenney/forceField_000.ogg | -13 | 1.2 |
| impact_chain | kenney/explosionCrunch_003.ogg | -16 | 0.82 |
| impact_mine | explosions/explosion2.ogg | -10 | 0.75 |
| impact_shield | kenney/forceField_003.ogg | -13 | 0.9 |
| cluster_split | kenney/explosionCrunch_004.ogg | -12 | 1.8 |
| rain_split | kenney/laserRetro_002.ogg | -13 | 1.1 |
| bounce | kenney/impactMetal_003.ogg | -15 | 1.3 |
| drill | kenney/engineCircular_002_short.wav | -17 | 1.4 |
| mine_arm | kenney/computerNoise_002_short.wav | -17 | 1.4 |
