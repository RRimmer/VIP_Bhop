# VIP_Bhop

**VIP bhop without ping dependency (no ground stickiness)**

Modified version of VIP BHOP with an on/off cycle, notifications, and a separate config.

> Developed with AI | GitHub Copilot and Claude Haiku

---

## Description

VIP_Bhop enables auto-bhop only for VIP players and controls access by time: how many seconds bhop is active and how many seconds it is on cooldown. It also supports Alert/chat notifications with translations. The key feature is that bhop does not depend on ping, so there is no sticking to the ground.

## Video

Comparison video.

[![Bhop demo](bhop.gif)](https://youtu.be/8scl9fwa_Mc)

[Watch on YouTube](https://youtu.be/8scl9fwa_Mc)

---

## Support for other games (possible)

The plugin is written for SourceMod and can work in other Source engine games if SourceMod and VIP-Core are available. Possible candidates: CS:S, TF2, DoD:S, HL2DM, and other Source mods.
Tested and verified only on CSGO.

---

## Features

- VIP bhop only for players with access to the `bhop` feature
- On/off timer control: `bhop_allowtime` and `bhop_locktime`
- Accounts for `mp_freezetime` at round start
- Alert/chat notifications with translations
- Notification recipients (everyone or VIP only)
- Per-client replication of `sv_enablebunnyhopping` and `sv_autobunnyhopping`
- Safe timer reset on round change and client disconnect
- Not ping dependent (no ground stickiness)

## Requirements

- SourceMod 1.10+
- VIP-Core

## Installation

1. Make sure SourceMod and VIP-Core are installed
2. Copy files to the appropriate directories:

```
VIP_Bhop.zip
├── addons/sourcemod/
│   ├── plugins/
│   │   └── VIP_Bhop.smx               <- Ready plugin
│   ├── scripting/
│   │   └── VIP_Bhop.sp                <- Source code
│   └── translations/
│       └── vip_bhop.phrases.txt       <- Translations and prefixes
└── cfg/vip/
    └── VIP_Bhop.cfg                   <- Console variables
```

3. Restart the server

## VIP-Core setup

Enable the `bhop` feature for the required groups in `groups.ini`.

Example:
```
"bhop"    "1"
```

If you use the VIP-Core menu, add an entry to `vip_modules.phrases.txt`:

```
"bhop"
{
    "ru"       "BunnyHop"
    "ua"       "BunnyHop"
    "en"       "BunnyHop"
    "pt"       "BunnyHop"
    "fi"       "BunnyHop"
}
```

## Configuration (ConVar)

| ConVar | Default | Description |
|---|---:|---|
| `bhop_allowtime` | 5 | How many seconds bhop is available (0 = always) |
| `bhop_locktime` | 15 | Cooldown seconds between activations (0 = no cooldown) |
| `bhop_info` | 2 | Notifications: 0 off, 1 chat, 2 Alert |
| `bhop_notify` | 0 | Who to notify: 0 everyone, 1 VIP with access |

## Translations and colors

Translation file: `addons/sourcemod/translations/vip_bhop.phrases.txt`.
You can change texts, prefixes, and color scheme there.

## Commands

Global command `!vip` - enable or disable bhop from the menu.

## Comparison with free versions

Comparison is based on source code in the repository:
- `VIP_BHOP_1.0.2.sp` (KOROVKA)
- `vip_bhop.sp` (MaZa 1.2)

| Feature | VIP_Bhop (current) | VIP_Bhop 1.2 (MaZa) | VIP_BHOP 1.0.2 (KOROVKA) |
|---|---|---|---|
| VIP feature type | FLOAT | FLOAT | BOOL |
| Delay before activation | Yes (`bhop_locktime` + `mp_freezetime`) | Yes (via feature value) | No |
| On/off timer | Yes (`bhop_allowtime`) | No | No |
| Cooldown between activations | Yes (`bhop_locktime`) | No | No |
| Alert/chat notifications | Yes (multiple types) | Yes (start only) | No |
| Notification recipients | Yes (all/VIP only) | No | No |
| Per-client `sv_enablebunnyhopping` | Yes | No | No |
| Timer cleanup on round change | Yes | No | No |
| Water check | No | No | Yes |

## Why this version is better for production

- Flexible timings: you can enable and disable bhop during the round
- Clean notifications with translations and anti-spam limits
- Safe state and timer management on round change and disconnect

If you need the simplest always-on bhop, version 1.0.2 is simpler and lighter. If you need configurable VIP bhop with timings and notifications, this version is more functional.
