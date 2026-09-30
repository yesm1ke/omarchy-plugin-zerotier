# ZeroTier for the Omarchy bar

A ZeroTier widget for the Omarchy bar: service on/off, joined networks with
join and leave, members with names and ZeroTier IPs (via a ZeroTier Central
API token) or local peers, and one-tap copy of addresses and IDs. The icon
hides with the system tray drawer.

This is a fork of
[Michallote/omarchy-zerotier-plugin](https://github.com/Michallote/omarchy-zerotier-plugin)
(v1.1.0, commit `e271d9e`) with security fixes and a few additions; the
history keeps upstream's commit and every change as its own commit.

## Differences from upstream

1. **The ZeroTier Central token no longer lingers in `/tmp`.** Upstream ran
   `exec curl -K "$tmp"`, which replaced the shell before its cleanup trap
   could run, leaving a token-bearing curl config behind on every member
   refresh.
2. **The privileged setup step no longer writes into your home as root.**
   Upstream checked `~/.config/zerotier` for symlinks and then ran `chmod`,
   `chown`, `mktemp` and `mv` on it as root — a check-then-use race on a
   user-writable path. Now root only opens the daemon token and drops to your
   uid with `setpriv`; everything under `~/.config/zerotier` is done as you.
3. **The first run works with zerotier-cli 1.16.** Before setup, 1.16 reports
   "missing port and zerotier-one.port not found", which upstream did not
   recognise, so the widget said "Service not responding" and never offered
   the authorize step.
4. **The Central token is read only from `~/.config/zerotier/central-token`.**
   The upstream `apiToken` setting would put the token in `shell.json`, which
   people commonly keep in a dotfiles repository.
5. **The icon hides with the system tray drawer** (`hideWithTray`, see below).
6. Plugin id `io.github.yesm1ke.zerotier`.

## Install

```sh
omarchy plugin add https://github.com/yesm1ke/omarchy-plugin-zerotier --enable
omarchy bar move io.github.yesm1ke.zerotier --after omarchy.tray
```

Requires `zerotier-one` (`omarchy pkg add zerotier-one`, then
`sudo systemctl enable --now zerotier-one`), plus `wl-copy`, `curl`, `pkexec`
and `setpriv`, which Omarchy ships.

### First run

Open the panel and click **Authorize ZeroTier access** (or toggle ZeroTier
on). One polkit prompt copies the daemon's local API token into
`~/.config/zerotier/` (mode 600) so `zerotier-cli` can run without privileges
afterwards. That token controls the local ZeroTier daemon; treat the directory
as a secret and keep it out of backups you share.

### Member names

Create a read token at my.zerotier.com → Account → API Access and paste it into
the field in the panel's Members section. Without it the panel lists local
peers instead.

## Controls

Left click opens the panel, right click starts or stops `zerotier-one`
(polkit prompt), middle click refreshes. In the panel: `j`/`k` or arrows move,
Enter opens the copy menu, `c` copies, `t` toggles the service, `r` refreshes,
Escape closes. IPC: `omarchy-shell io.github.yesm1ke.zerotier toggle|refresh|status|up|down`.

## Settings

| Setting | Default | |
|---|---|---|
| `hideWithTray` | `true` | `false` keeps the icon always visible |
| `refreshIntervalSec` | `30` | how often `zerotier-cli` is polled |

## Hiding with the tray

`TrayFollower.qml` finds the `omarchy.tray` widget among its sibling bar slots
and mirrors its `expanded` state: the icon collapses while the drawer is
closed, slides out with it on hover, and keeps the drawer open while hovered
or while its panel is open. It relies on bar internals; if a future Omarchy
changes them, the icon simply stays visible.

## Uninstall

```sh
omarchy plugin remove io.github.yesm1ke.zerotier
rm -rf ~/.config/zerotier
```

## License

MIT, see [LICENSE](LICENSE).
