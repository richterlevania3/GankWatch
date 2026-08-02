# GankWatch

A tiny World of Warcraft **1.12 (vanilla)** addon for hardcore / open-PvP
servers. It does two things:

1. **Friend watch** — warns you the instant any player on your friends list logs
   on (banner + screen flash + chat + sound). Detection is 100% friends-list
   based (it diffs each friend's online/offline state), so it is
   **localization-proof** and works **cross-faction** on servers that allow
   cross-faction friends (e.g. OctoWoW).
2. **Zone Horde scan** — every 30s it runs a background `/who` on your *current*
   zone, filtered by Horde race, and warns you about any enemy players present.
   Requires a server where `/who` returns the opposite faction. Because a bare
   zone query may only return your own side, it queries one Horde race at a time
   (Orc / Troll / Tauren / Undead) and rotates through all four each cycle, with
   the sends spaced out to respect the client's `/who` throttle.

## Install

Clone this repo and copy the `GankWatch` folder into your client's addon folder:

```
<WoW>/Interface/AddOns/GankWatch/
```

Then fully **restart** the client (a new addon folder is not picked up by
`/reload`) and log in.

## Usage

| Command | Does |
|---|---|
| `/gankwatch seed` | Adds a built-in list of known gankers to your friends list at once |
| `/gankwatch add <name>` | Watch one more player (adds them to friends) |
| `/gankwatch remove <name>` | Stop watching (removes the friend) |
| `/gankwatch list` | Show the watchlist with online/offline status |
| `/gankwatch who` | Toggle the zone Horde scan on/off |
| `/gankwatch scan` | Run a zone Horde scan right now |
| `/gankwatch test` | Preview the alert |

`/gkw` is a short alias for `/gankwatch`.

### How it alerts

On a new login you get a center-screen raid-warning banner, a red error-frame
flash, a chat line with the player's level/class/zone, and two sounds. It will
**not** alert for people already online when *you* log in — only genuine new
logins after that.

## Notes

- **Friends lists are per-character in vanilla**, not account-wide. Run
  `/gankwatch seed` (or `add`) on each character you want protected.
- The addon re-requests the friends list every 30s as a safety net on top of the
  server's live online/offline push.
- The seeded ganker list is just a starting point — edit the `SEED` table at the
  top of `GankWatch/GankWatch.lua` to fit your own server.

## License

MIT — see [LICENSE](LICENSE). Written by richterlevania3.
