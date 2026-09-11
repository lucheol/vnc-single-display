# vnc-single-display

Give a screen-sharing client **one normal desktop instead of a sprawling multi-monitor canvas** — automatically, for the duration of the session.

When a VNC or Screen Sharing client connects to a Mac with several displays, the server sends the bounding box of *all* of them. On a laptop with an external monitor that usually means a huge, oddly shaped canvas: tiny windows, wasted space, and a lot of panning on the client side. This watches for an incoming connection, mirrors the displays so the client sees a single screen, and puts the original layout back when the session ends.

Mirroring **merges** the desktops, so nothing becomes unreachable — every window you had open is still there. That is the difference from just capturing the main display.

Works on any Mac with more than one display. No root, no kernel extension, no third-party dependency.

---

## Contents

- [Why you might want this](#why-you-might-want-this)
- [The macOS bug it also fixes](#the-macos-bug-it-also-fixes)
- [Install](#install)
- [Usage](#usage)
- [How it works](#how-it-works)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Uninstall](#uninstall)

---

## Why you might want this

Two reasons, and you only need one of them.

**1. Multi-monitor over VNC is miserable.** The client receives one framebuffer covering every display. A 16″ laptop plus a 34″ ultrawide becomes a canvas several thousand pixels across with dead space in the corners, scaled down to fit a phone or an iPad. Most clients can select a single display once connected, but that is a per-session chore and you still lose the windows on the other screen.

**2. On some layouts the connection does not work at all.** See below.

## The macOS bug it also fixes

If your external display sits **above or to the left** of your built-in display, and the two have **different backing scale factors** (a Retina built-in at 2× next to a standard external at 1× is the common case), Apple's screen-sharing server can fail outright: the client authenticates successfully and is disconnected roughly two seconds later, every time.

The cause is a coordinate-space mix-up. The capture framebuffer is built from the union of all active displays, but the agent only resolves a secondary display's pixel-space origin by chaining from a **horizontally adjacent** neighbour. A display with no such neighbour falls back to reusing its point-space origin as if it were a pixel-space origin:

```
index 0 display 1  width 1800 3600  height 1169 2338  res 2.0   x=0     y=0      know actual 1 1
index 1 display 5  width 3440 3440  height 1440 1440  res 1.0   x=-809  y=-1440  know actual 0 1
no monitor to the left, so set actual X to virtual X  device 1 x = -809
device 1 actual 0     0     2338 3600      <- pixels
device 5 actual -1440 -809  0    2631      <- points, never converted
all displays global rect = -1440 -809 2338 3600
```

That union takes its origin from one space and its size from the other. The daemon and its agent then compute different tile grids for the same shared-memory buffer — 276 tiles per row against 552, differing by exactly the built-in display's backing scale — the buffer is allocated for the main display's area alone, and every frame read fails:

```
SSAgent_ReadScreenDataIntoSharedMemory_rpc failed, unknown error code
reached eof
read error 3 No such process
```

Mirrored, all displays share one origin, there is nothing left to convert, and the numbers agree:

| | extended | mirrored |
|---|---|---|
| `displayCount` | 2 | 1 |
| origin resolved (`know actual`) | `0 1` — fallback taken | `1 1` |
| `all displays global rect` | `-1440 -809 2338 3600` | `0 0 2338 3600` |
| `tilesPerRow` (daemon / agent) | 276 / 552 | 225 / 225 |
| failed frame reads | 4+ per attempt | 0 |
| session length | ~2 s | unlimited |

Verified on macOS 26.6.2 (25G83), Apple silicon. The related class of arrangement bug in Apple's screen sharing has been [reported by Edovia since 2020](https://help.edovia.com/en/screens-5/troubleshooting/multiple-displays-arrangement/) without a fix.

The other workarounds — unplug the monitor, or rearrange it side by side — require giving up the layout you wanted. This does not.

## Install

Requires the Xcode command line tools (`xcode-select --install`) for `swiftc`.

```bash
git clone https://github.com/lucheol/vnc-single-display.git
cd vnc-single-display
./install.sh
```

That builds the helper, installs it to `~/.local/bin`, and loads a launch agent that starts at login. Nothing is written outside your home directory and nothing runs as root.

To install somewhere else:

```bash
PREFIX=/usr/local ./install.sh
```

## Usage

There is nothing to do. Connect as usual; the layout collapses for the session and comes back afterwards.

The helper is also useful on its own:

```bash
vncdisplay status        # show every display, its origin, resolution and scale
vncdisplay mirror        # collapse to a single display now
vncdisplay unmirror      # restore the previous layout
vncdisplay is-mirrored   # exit 0 if mirrored, 1 if not — for scripting
```

Example:

```
$ vncdisplay status
state: extended
id=1    MAIN      origin=(    0,     0) pt=1800x1169 px=3600x2338 scale=2.0 mirrorsDisplay=0
id=5    secondary origin=( -809, -1440) pt=3440x1440 px=3440x1440 scale=1.0 mirrorsDisplay=0
```

Watch what the agent is doing:

```bash
tail -f ~/Library/Logs/vnc-single-display.log
```

```
2026-09-11 00:09:01  watcher started (port 5900, grace 30s)
2026-09-11 00:09:44  MIRROR ON
2026-09-11 00:21:30  MIRROR OFF - original layout restored
```

## How it works

`vncdisplay` calls `CGConfigureDisplayMirrorOfDisplay` to point every secondary display at the main one, and passes the null display to undo it. That is public CoreGraphics API — the same thing the Displays pane does.

The watcher decides when:

- **Connect** is detected from the system log, on `screensharingd` accepting a socket. The window between that and the first frame read is about one second, so polling alone reacts too late.
- **Disconnect** is detected by polling for established TCP connections on port 5900, which reconciles against real socket state rather than log semantics.

Restoring is treated as the hard requirement, with four independent guards:

1. A grace period (default 30 s), measured from the last sign of a viewer, before restoring. A reconnect during that window keeps the layout collapsed instead of thrashing the displays mid-session.
2. An **ownership flag** on disk. The watcher restores only a mirror *it* created — a layout you mirrored yourself is left alone.
3. An **exit trap**, so being killed or logged out restores the layout on the way down.
4. A **startup reconcile**. If the flag survives a crash or a reboot, the next start finds it with no viewer connected and undoes it immediately.

`uninstall.sh` restores the layout before removing anything, so uninstalling cannot strand you mirrored either.

### Known limitation

Mirroring merges the desktops, so **window positions are not preserved**. Windows that were on the external display end up on the merged desktop and stay where macOS puts them after restoring. Nothing is lost or unreachable — but if you rely on a precise window arrangement, that arrangement will not survive a session.

## Configuration

Environment variables, read by the watcher. Set them in the launch agent at `~/Library/LaunchAgents/io.github.lucheol.vnc-single-display.plist` under `EnvironmentVariables`, then reload with `launchctl kickstart -k gui/$(id -u)/io.github.lucheol.vnc-single-display`.

| Variable | Default | Meaning |
|---|---|---|
| `VNCSD_PORT` | `5900` | TCP port watched for viewers |
| `VNCSD_GRACE` | `30` | Seconds with no viewer before restoring |
| `VNCSD_BIN` | `~/.local/bin/vncdisplay` | Path to the helper |
| `VNCSD_LOG` | `~/Library/Logs/vnc-single-display.log` | Activity log |
| `VNCSD_STATE_DIR` | `~/.local/state/vnc-single-display` | Ownership flag location |

Raise `VNCSD_GRACE` if you reconnect often and want to avoid the displays flipping back and forth.

## Troubleshooting

**The first connection attempt still fails.** Expected on affected layouts. Detection is fast but reconfiguring displays takes longer than the one-second window the server allows, so the first attempt can lose the race. By then the layout is already collapsed and the reconnect succeeds. Most clients retry on their own.

To remove the race entirely, collapse the layout *before* opening the client — for example an iOS Shortcut that runs `ssh your-mac '~/.local/bin/vncdisplay mirror'` and then launches it.

**Nothing happens on connect.** Check the agent is running and read the log:

```bash
launchctl print gui/$(id -u)/io.github.lucheol.vnc-single-display | grep state
tail -20 ~/Library/Logs/vnc-single-display.log
```

**It says it is leaving the layout alone.** The displays were already mirrored when the connection arrived, so the watcher takes no ownership and will not restore anything. That is deliberate.

**Stuck mirrored.** `vncdisplay unmirror` fixes it immediately. If it keeps happening, the log will say which guard failed.

**Non-standard port.** If screen sharing runs somewhere other than 5900, set `VNCSD_PORT`.

## Uninstall

```bash
./uninstall.sh
```

Restores the layout, unloads the agent, removes the binaries. Logs are kept.

## License

[GNU General Public License v3.0](LICENSE).

This is free software and it stays that way. You may use it, study it, change it
and share it, including at work and including for money. What you may not do is
make it proprietary: anything you distribute that is built on this has to ship its
own source under the GPL too, so no closed-source product can be carved out of it.
