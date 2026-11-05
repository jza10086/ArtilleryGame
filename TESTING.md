# 火炮大战验证

在 GodotParty 工程中使用系统 PATH 的 `godot`。所有验证脚本、日志、截图和隔离配置都位于工程根目录 `tmp/test/`，不随内容包发行。

```powershell
godot --headless --path F:/GodotProjects/GodotParty --script res://tmp/test/artillery/check.gd --log-file F:/GodotProjects/GodotParty/tmp/test/artillery/check.log
python tmp/test/artillery/network.py training 1
python tmp/test/artillery/network.py ffa 2
python tmp/test/artillery/network.py teams 4
godot --path F:/GodotProjects/GodotParty --script res://tmp/test/artillery/preview.gd --resolution 1920x1080 --log-file F:/GodotProjects/GodotParty/tmp/test/artillery/preview.log
```

历史基础玩法验证使用 Godot 4.7.2 完成：

- 规则自动检查：三模式人数集合、2–8 人回合控制、八类炮弹飞行、弹药消耗、挖坑与造山、虹吸回血、单人无敌/重置、非法输入、团队输赢、断线与同时阵亡排名。
- 真实框架运行：单人试射/重置/结束测试；双进程 ENet 混战连续两局；四进程 ENet 团队局。覆盖准备门、客户端操作、主机快照、结算门和主游戏持久化提交。联机检查在各参与者完成真实发射后使用低生命决胜夹具加快结束，不代表完整长局平衡验收。
- 画面检查：原生 1920×1080 战场与弹药库截图，未使用其他分辨率。

尚未进行人工手感与炮弹平衡验收、跨机器/外网联机、八进程压力测试。旧 prototype 的历史验证不作为正式版验收结果。

## Kenney 坦克与扩展弹药、事件

本轮在 Godot 4.7.2 完成规则检查与绑定检查，范围包括 16 种弹药飞行结束、弹雨七枚子弹、EMP 一次性减速、护盾吸收、跃迁、持续燃烧、感应雷、连锁延时爆破、黑洞偏转与吞噬、增幅、补给的一次性领取及事件到期。坡面炮口和实弹位置一致，后坐复位通过。

双进程 ENet 混战连续两局检查通过；双方收到事件与 16 种弹药快照，实际发射空爆弹雨和燃烧弹并完成结算。此次未重跑四人团队或八人局。

1920×1080 原生场景检查覆盖 Kenney 坦克近景、完整战场、4×4 弹药库、弹雨飞行／命中、黑洞、补给、增幅力场、火区和护盾。全长对局的平衡与手感仍需玩家试玩。
