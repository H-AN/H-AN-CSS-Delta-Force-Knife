<div align="center">

# [H-AN] CS:S Delta Force Knife

[简体中文](README.md) | **English**

![Game](https://img.shields.io/badge/Game-Counter--Strike%20Source-orange)
![SourceMod](https://img.shields.io/badge/SourceMod-1.12%2B-blue)
![License](https://img.shields.io/badge/License-GPL--3.0-green)

**A universal driver plugin for Delta Force style knives — one config file drives all of your Delta Force style knives**

</div>

---

## Introduction

This is a **universal driver plugin for Delta Force style knives** within the [H-AN Weapon System (HanWeaponSystem)](https://github.com/H-AN) ecosystem for Counter-Strike: Source.

It evolved from the Polaris-exclusive plugin `[H-AN-CSS]Polaris Knife`: everything that used to be hard-coded — animation sequences, attack intervals, damage, sound effects — has been extracted into **group-based configuration**. From now on, every new Delta Force style knife only needs a new group in the config file, with zero code changes.

> Only weapons that are **listed as a group in the config file** are driven by this plugin. Weapons not listed are completely unaffected.

## Features

- **3-hit left-click combo**: three QC animation sequences in a loop (default 4→5→6), each hit with its own attack interval, damage and animation frame count
- **Combo idle reset**: after not attacking for longer than `IdleTimeout`, the combo automatically restarts from the first hit
- **Right-click heavy attack**: supports a single fixed animation, or multiple comma-separated animations played in alternating order (Polaris uses `8,6`)
- **Full damage override**: the weapon's native damage is ignored; damage is recalculated from the group's base damage + headshot multiplier
- **Three sound systems**:
  - **Delayed blade-rotate sound** after each attack (configured as `frame:path` — plays when the animation reaches that frame; delay = frame ÷ animation fps, exact with no rounding; a new attack automatically cancels the previous attack's pending sound)
  - **Hit sound** (attacker only)
  - **Kill sound**: automatically distinguishes between **headshot kill sound** and **normal kill sound** based on the last registered hitgroup
  - Any sound path can be **left empty to disable that sound**
- **Animation driver**: played through the HanWeaponSystem dual-ViewModel custom animation API (sequence 0 forced on VM0 + custom sequence on VM1)
- **Dual draw animation** (optional): every weapon draw has a 50% chance to play the vanilla synced draw and a 50% chance to play the configured special draw sequence, each with its own draw sound; attacks take priority and interrupt the draw animation normally
- **Config hot reload**: reload instantly with an admin command, no map change or restart needed

## Requirements

| Requirement | Notes |
| --- | --- |
| Counter-Strike: Source dedicated server | Game platform |
| SourceMod **1.12+** | Compile & runtime environment |
| **HanWeaponSystem** (H-AN Weapon System) | Must be loaded — provides `Han_SetClientCustomAnim` and related animation APIs |

## Installation

1. Compile `[H-AN-CSS]Delta Force Knife.sp` into a `.smx` with SourceMod 1.12's spcomp, or grab `DeltaForceKnife.smx` from the Release page
2. Drop it into `addons/sourcemod/plugins/`
3. On first load / map change, a fully commented default config is auto-generated at `addons/sourcemod/configs/DeltaForceKnife.cfg` (includes the Polaris group and a template for new knives)
4. After editing the config, run `sm_deltaforce_knife_reload` for it to take effect immediately, or change the map

> **Note**: this plugin overlaps with the old `[H-AN-CSS]Polaris Knife` plugin. If both are configured with the same `ClassName`, do **not** load them at the same time, otherwise the same weapon will be driven twice (damage applied twice, sounds doubled). If you prefer the old single-knife plugin, you can keep using it — the two plugins do not touch each other's source code.

## Global ConVars

| ConVar | Default | Description |
| --- | --- | --- |
| `sm_deltaforce_knife_enable` | `1` | Master switch of the plugin |
| `sm_deltaforce_knife_sound_enable` | `1` | Master switch for all sounds (rotate / hit / kill sounds) |

## Admin Command

| Command | Flag | Description |
| --- | --- | --- |
| `sm_deltaforce_knife_reload` | `ADMFLAG_CONFIG` | Reloads `configs/DeltaForceKnife.cfg` immediately (all players' combo states are reset) |

## Knife Group Config Reference

The config file uses KeyValues format — one group per knife, group names are arbitrary:

```kv
"DeltaForceKnife"
{
    "beijixing"                 // ← group name (arbitrary, weapon short name recommended)
    {
        "ClassName"             "weapon_beijixing"
        // ...other keys
    }
}
```

| Key | Description | Default |
| --- | --- | --- |
| `ClassName` | **Required.** Weapon entity classname | none (group is skipped if missing) |
| `IdleTimeout` | If the gap between two attacks exceeds this many seconds, the left combo restarts from the first hit | `2.0` |
| `LeftSequence1~3` | QC animation sequence numbers of the three left-click hits | `4` `5` `6` |
| `LeftFrames1~3` | Total animation frame counts of the three left-click hits (passed to the weapon system, state duration = frames ÷ 30 s; not used for sounds) | `40` `60` `61` |
| `LeftFps1~3` | Animation fps of each left-click hit, used for the rotate-sound frame conversion | `66` |
| `LeftInterval1` | Attack interval of left click **3rd hit → 1st hit** (seconds) | `0.6` |
| `LeftInterval2` | Attack interval of left click **1st hit → 2nd hit** (seconds) | `0.3` |
| `LeftInterval3` | Attack interval of left click **2nd hit → 3rd hit** (seconds) | `0.4` |
| `LeftDamage1~3` | Base damage of the three left-click hits | `30` `30` `42` |
| `RightSequence` | Right-click QC animation sequence numbers, **comma-separated**: one value = fixed animation; multiple values = played in alternating order | `8,6` |
| `RightFrames` | Total animation frame count of the right-click attack (passed to the weapon system; not used for sounds) | `61` |
| `RightFps` | Right-click animation fps, used for the rotate-sound frame conversion | `66` |
| `RightInterval` | Attack interval from one right click to the next (seconds) | `0.6` |
| `RightDamage` | Base damage of the right-click heavy attack | `60` |
| `HeadshotMultiplier` | Headshot damage multiplier | `2.0` |
| `RotateSound1~3` | Blade-rotate sound of each left-click hit, format **`frame:path`** = starts playing at frame N of the animation (no frame = plays immediately at frame 0; empty = not played). Supports **multiple chained entries separated by commas** (e.g. `"5:xx/a.wav,33:xx/b.wav"` = a at frame 5, b at frame 33), each delayed independently on the shared channel, up to 4 entries | empty |
| `RightRotateSound` | Right-click blade-rotate sound, same format as `RotateSound1~3`, also supports comma-separated multiple entries | empty |
| `DrawSequence2` | QC sequence number of the special draw. **Filling this enables the dual draw animation**: every draw has a 50% chance to play the vanilla synced draw and a 50% chance to play this sequence; not filled = draws are not touched | empty |
| `DrawFrames2` | Total frame count of the special draw animation (state duration = frames ÷ 30 s, must cover the whole draw) | none |
| `DrawSound1` | Normal draw sound (played when the synced draw plays; empty = not played) | empty |
| `DrawSound2` | Special draw sound (played when the special draw plays; empty = not played) | empty |
| `HitSound` | Normal hit sound path (empty = not played) | empty |
| `KillSound` | Normal kill sound path (empty = not played) | empty |
| `HeadshotSound` | Headshot kill sound path (empty = not played) | empty |

> Any key missing inside a group falls back to the **Polaris defaults**, so if a new knife shares the Polaris animation layout, filling in only `ClassName` is enough to make it work.

### Full Example (Polaris group)

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
        "LeftInterval1"         "0.6"    // 3rd hit -> 1st hit
        "LeftInterval2"         "0.3"    // 1st hit -> 2nd hit
        "LeftInterval3"         "0.4"    // 2nd hit -> 3rd hit
        "LeftDamage1"           "30.0"
        "LeftDamage2"           "30.0"
        "LeftDamage3"           "42.0"

        "RightSequence"         "8,6"
        "RightFrames"           "61"
        "RightInterval"         "0.6"
        "RightDamage"           "60.0"

        "HeadshotMultiplier"    "2.0"

        "RotateSound1"          "40:weapons/beijixing/beijixing_rotate_1.wav"
        "RotateSound2"          "60:weapons/beijixing/beijixing_rotate_2.wav"
        "RotateSound3"          "61:weapons/beijixing/beijixing_rotate_3.wav"
        "RightRotateSound"      "61:weapons/beijixing/beijixing_rotate_3.wav"

        "HitSound"              "weapons/beijixing/hit.wav"
        "KillSound"             "weapons/beijixing/kill.wav"
        "HeadshotSound"         "weapons/beijixing/headshot.wav"
    }
}
```

## How to Add a New Knife

1. Add a new group in `DeltaForceKnife.cfg` (the auto-generated config ends with a commented-out template — copy it and remove the comment markers)
2. Fill in the new knife's `ClassName` and adjust the sequence numbers, frame counts, intervals, damage and sound paths as needed
3. Run `sm_deltaforce_knife_reload` (or change the map) and the new knife is driven immediately

```kv
"my_new_knife"
{
    "ClassName"         "weapon_mynewknife"
    "LeftSequence1"     "4"
    "LeftSequence2"     "5"
    "LeftSequence3"     "6"
    "LeftFps1"          "64"     // animation fps (defaults to 66 if omitted)
    "RotateSound1"      "40:weapons/mynewknife/rotate_1.wav"   // starts playing at frame 40
    "RotateSound3"      "7:weapons/mynewknife/fire.wav,43:weapons/mynewknife/rotate_3.wav"   // chained sounds: fire at frame 7, rotate_3 at frame 43
    "RightSequence"     "8"      // a single value = fixed heavy attack animation
    // ...fill in the rest as needed; missing keys use the Polaris defaults
}
```

## How It Works (Brief)

- A TempEnt hook on `PlayerAnimEvent` captures the player's right-click (`m_iEvent=0`) / left-click (`m_iEvent=1`) attack animation events, advances the combo state machine, rewrites `m_flNextPrimaryAttack` / `m_flNextSecondaryAttack` / `m_flNextAttack` to control attack speed, and calls HanWeaponSystem's `Han_SetClientCustomAnim` to play the custom animation
- `SDKHook_TraceAttack` takes over damage: a ray is traced from the attacker's viewpoint against the victim to obtain the hitgroup; head hits (1) are multiplied by the headshot multiplier, and a missed ray (0) also counts as a headshot as a fallback (identical to Polaris behavior)
- Blade-rotate sounds are played through timers carrying an attack ID; the delay = configured rotate frame ÷ animation fps (exact conversion, no rounding); a new attack invalidates the previous attack's pending sound
- The hitgroup is written into the `hitgroup` field of the `player_hurt` event and recorded for the kill sound decision

## Behavior Details

- **The first hit after an idle period does not get the plugin interval** — its attack speed is decided by the weapon itself; from the second hit on, the group config takes over
- When the dual draw animation is enabled, the **`switchsound` of that weapon must be left empty in the weapon system's config**, otherwise every draw would additionally play a fixed switch sound on top
- **The normal draw already carries the original switch sound** (baked into the original draw animation's sound event, processed by the sound-replacement hook), so `DrawSound1` should usually stay empty; the special draw animation has no embedded sound and gets its sound from `DrawSound2`
- The kill sound uses the "last registered hitgroup"; a lethal hit does not play the hit sound (the kill sound plays instead)
- **Any weapon switch resets the combo** (switching away, back, or picking up) — drawing a Delta Force knife always starts from the first hit; switching also cancels pending blade-rotate sounds
- All sounds use the `SNDCHAN_STATIC` channel; rotate sounds are audible to everyone, hit/kill sounds only to the attacker
- Up to 32 knife groups and up to 4 right-click animation entries per group

## Related Projects

- [H-AN Weapon System (HanWeaponSystem)](https://github.com/H-AN) — the animation/weapon framework this plugin depends on
- [H-AN-CSS]Polaris Knife — the Polaris-exclusive edition (the origin of this plugin's logic, usable on its own)

## Author / Contact

- **HuaZai H-AN**
- QQ group: `107866133`
- GitHub: [https://github.com/H-AN](https://github.com/H-AN)

## License

[GPL-3.0](LICENSE)
