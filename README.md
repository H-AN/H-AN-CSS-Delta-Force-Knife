<div align="center">

# [H-AN] CS起源三角洲刀具 · Delta Force Knife

**简体中文** | [English](README.en.md)

![Game](https://img.shields.io/badge/游戏-Counter--Strike%20Source-orange)
![SourceMod](https://img.shields.io/badge/SourceMod-1.12%2B-blue)
![License](https://img.shields.io/badge/许可证-GPL--3.0-green)

**三角洲行动风格刀具统一驱动插件 —— 一份配置，驱动你所有的三角洲风格刀**

</div>

---

## 简介

本插件是 [H-AN 武器系统（HanWeaponSystem）](https://github.com/H-AN)生态下的**三角洲风格刀具通用驱动插件**。

它由北极星专属插件 `[H-AN-CSS]Polaris Knife` 进化而来：原先硬编码的动画序列、攻击间隔、伤害、音效等全部抽取为**组形式配置**。以后每制作一把新的三角洲风格刀，只需要在配置文件里新增一个组，无需再写任何代码。

> 只有配置文件中**填写了组的武器**才会被本插件驱动，未列出的武器完全不受影响。

## 功能特性

- **左键三段连招**：三个 QC 动画序列循环（默认 4→5→6），每一刀独立攻击间隔、独立伤害、独立动画帧数
- **连招空闲重置**：超过 `IdleTimeout` 未攻击后，连招自动回到第一刀
- **右键重击**：支持 1 个固定动画，或逗号分隔多个动画交替循环（北极星为 `8,6`）
- **伤害完全接管**：忽略武器原生伤害，按组配置的基础伤害 + 爆头倍率重新计算
- **三套音效系统**：
  - 每刀攻击后的**延迟旋转音**（延迟 = 动画帧数 ÷ 66 秒，向下取整到 0.1 秒；新攻击自动打断旧攻击尚未播放的旋转音）
  - **命中音**（仅攻击者可听）
  - **击杀音**：根据最近命中部位自动区分**爆头击杀音 / 普通击杀音**
  - 任何一个音效路径**留空即不播放**
- **动画驱动**：通过 HanWeaponSystem 双 ViewModel 自定义动画接口播放（VM0 序列清零 + 1 号 VM 播放自定义序列）
- **配置热重载**：管理命令即时重载，无需换图或重启

## 依赖环境

| 依赖 | 说明 |
| --- | --- |
| Counter-Strike: Source 专用服务器 | 游戏平台 |
| SourceMod **1.12+** | 编译与运行环境 |
| **HanWeaponSystem**（H-AN 武器系统） | 必须加载，提供 `Han_SetClientCustomAnim` 等动画 API |

## 安装

1. 将 `[H-AN-CSS]Delta Force Knife.sp` 编译为 `.smx`（SourceMod 1.12 spcomp），或直接使用 Release 中的 `DeltaForceKnife.smx`
2. 放入 `addons/sourcemod/plugins/`
3. 首次加载/换图后自动生成带中文注释的默认配置 `addons/sourcemod/configs/DeltaForceKnife.cfg`（内置北极星组与新刀模板）
4. 修改配置后执行 `sm_deltaforce_knife_reload` 立即生效，或换图生效

> **注意**：本插件与旧的 `[H-AN-CSS]Polaris Knife` 插件功能重叠。若配置了相同的 `ClassName`，请勿两个插件同时加载，否则会对同一把武器双重驱动（伤害计算两次、音效双份）。喜欢旧版单插件玩法的可以继续使用旧版，两者互不影响源码。

## 全局 ConVar

| ConVar | 默认值 | 说明 |
| --- | --- | --- |
| `sm_deltaforce_knife_enable` | `1` | 插件总开关 |
| `sm_deltaforce_knife_sound_enable` | `1` | 音效总开关（旋转音 / 命中音 / 击杀音） |

## 管理命令

| 命令 | 权限 | 说明 |
| --- | --- | --- |
| `sm_deltaforce_knife_reload` | `ADMFLAG_CONFIG` | 立即重载 `configs/DeltaForceKnife.cfg`（重载后所有玩家连招状态重置） |

## 刀具组配置项

配置文件为 KeyValues 格式，每把刀一个组，组名随意：

```kv
"DeltaForceKnife"
{
    "beijixing"                 // ← 组名（随意，建议用武器短名）
    {
        "ClassName"             "weapon_beijixing"
        // ...其余配置项
    }
}
```

| 配置项 | 说明 | 默认值 |
| --- | --- | --- |
| `ClassName` | **必填**。武器实体名称 | 无（缺省则跳过该组） |
| `IdleTimeout` | 连续攻击间隔超过此时间（秒）后，左键连招从第一刀重新开始 | `2.0` |
| `LeftSequence1~3` | 左键三刀的 QC 动画序列号 | `4` `5` `6` |
| `LeftFrames1~3` | 左键三刀动画帧数，同时决定旋转音延迟 = 帧数 ÷ 66 秒 | `40` `60` `61` |
| `LeftInterval1` | 左键 **第三刀 → 第一刀** 的攻击间隔（秒） | `0.6` |
| `LeftInterval2` | 左键 **第一刀 → 第二刀** 的攻击间隔（秒） | `0.3` |
| `LeftInterval3` | 左键 **第二刀 → 第三刀** 的攻击间隔（秒） | `0.4` |
| `LeftDamage1~3` | 左键三刀基础伤害 | `30` `30` `42` |
| `RightSequence` | 右键 QC 动画序列号，**逗号分隔**：填 1 个 = 固定动画；填多个 = 按顺序交替循环 | `8,6` |
| `RightFrames` | 右键动画帧数 | `61` |
| `RightInterval` | 右键 → 下一次右键 的攻击间隔（秒） | `0.6` |
| `RightDamage` | 右键基础伤害 | `60` |
| `HeadshotMultiplier` | 爆头伤害倍率 | `2.0` |
| `RotateSound1~3` | 左键各刀攻击后的延迟旋转音效路径（留空 = 不播放） | 空 |
| `RightRotateSound` | 右键攻击后的延迟旋转音效路径（留空 = 不播放） | 空 |
| `HitSound` | 普通命中音效路径（留空 = 不播放） | 空 |
| `KillSound` | 普通击杀音效路径（留空 = 不播放） | 空 |
| `HeadshotSound` | 爆头击杀音效路径（留空 = 不播放） | 空 |

> 组内未填写的键一律回落到**北极星默认值**，所以新刀如果动画布局与北极星相同，只填 `ClassName` 也能直接运行。

### 完整示例（北极星组）

```kv
"DeltaForceKnife"
{
    "beijixing"
    {
        "ClassName"             "weapon_beijixing"
        "IdleTimeout"           "2.0"

        "LeftSequence1"         "4"
        "LeftSequence2"         "5"
        "LeftSequence3"         "6"
        "LeftFrames1"           "40"
        "LeftFrames2"           "60"
        "LeftFrames3"           "61"
        "LeftInterval1"         "0.6"    // 第三刀 -> 第一刀
        "LeftInterval2"         "0.3"    // 第一刀 -> 第二刀
        "LeftInterval3"         "0.4"    // 第二刀 -> 第三刀
        "LeftDamage1"           "30.0"
        "LeftDamage2"           "30.0"
        "LeftDamage3"           "42.0"

        "RightSequence"         "8,6"
        "RightFrames"           "61"
        "RightInterval"         "0.6"
        "RightDamage"           "60.0"

        "HeadshotMultiplier"    "2.0"

        "RotateSound1"          "weapons/beijixing/beijixing_rotate_1.wav"
        "RotateSound2"          "weapons/beijixing/beijixing_rotate_2.wav"
        "RotateSound3"          "weapons/beijixing/beijixing_rotate_3.wav"
        "RightRotateSound"      "weapons/beijixing/beijixing_rotate_3.wav"

        "HitSound"              "weapons/beijixing/hit.wav"
        "KillSound"             "weapons/beijixing/kill.wav"
        "HeadshotSound"         "weapons/beijixing/headshot.wav"
    }
}
```

## 如何添加一把新刀

1. 在 `DeltaForceKnife.cfg` 中新增一个组（自动生成的配置文件末尾附有注释掉的新刀模板，复制去掉注释即可）
2. 填写新刀的 `ClassName`，按需修改三刀序列号、帧数、间隔、伤害与音效路径
3. 执行 `sm_deltaforce_knife_reload`（或换图）即可驱动新刀

```kv
"my_new_knife"
{
    "ClassName"         "weapon_mynewknife"
    "LeftSequence1"     "4"
    "LeftSequence2"     "5"
    "LeftSequence3"     "6"
    "RightSequence"     "8"      // 只填一个 = 固定重击动画
    // ...其余项按需填写，未填写的键使用北极星默认值
}
```

## 工作原理（简述）

- 通过 TempEnt Hook `PlayerAnimEvent` 捕获玩家的右键（`m_iEvent=0`）/左键（`m_iEvent=1`）攻击动画事件，推进连招状态机，改写 `m_flNextPrimaryAttack` / `m_flNextSecondaryAttack` / `m_flNextAttack` 控制攻速，并调用 HanWeaponSystem 的 `Han_SetClientCustomAnim` 播放自定义动画
- 通过 `SDKHook_TraceAttack` 接管伤害：从攻击者视角对受害者做射线检测取命中部位，命中头部（1）按爆头倍率计算，射线未命中（0）同样按爆头兜底（与北极星行为一致）
- 延迟旋转音通过携带攻击 ID 的定时器播放，新攻击会作废旧攻击尚未播放的旋转音
- 命中部位写入 `player_hurt` 事件的 `hitgroup` 字段并记录，供击杀音判断

## 行为细节

- **空闲后的第一刀不套用插件间隔**，攻速由武器本身决定；从第二刀开始由组配置接管
- 击杀音判定使用"最近一次命中部位"；致命一击不播命中音（转而播击杀音）
- 玩家在多把三角洲刀之间切换时，连招自动从第一刀重新开始
- 音效统一使用 `SNDCHAN_STATIC` 通道；旋转音全体可闻，命中/击杀音仅攻击者可闻
- 组数量上限 32，右键动画列表最多 4 个

## 相关项目

- [H-AN 武器系统 HanWeaponSystem](https://github.com/H-AN) —— 本插件的动画/武器框架依赖
- [H-AN-CSS]Polaris Knife —— 北极星专属版（本插件的逻辑来源，可独立使用）

## 作者 / 联系

- **华仔 H-AN**
- QQ 群：`107866133`
- GitHub：[https://github.com/H-AN](https://github.com/H-AN)

## 许可证

[GPL-3.0](LICENSE)
