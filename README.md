# Alamos AMweb Kiosk on Raspberry Pi 4 — Autostart after Power Loss

This repo turns a Raspberry Pi 4 into a dedicated Alamos AMweb display:
on every boot (including unexpected power loss) the Pi automatically
opens Chromium in kiosk mode on your AMweb URL, already logged in.

It follows the official Alamos guidance and adapts it for current
Raspberry Pi OS **Bookworm** (Wayland / labwc), which the original
Alamos page does not yet cover (it still references the old LXDE
autostart path).

## What it sets up

- Chromium in `--kiosk` mode, full screen, on the AMweb URL.
- A persistent user-data-dir at `~/.config/chromium-amweb/` so the AMweb
  login (password + encryption password) survives every reboot.
- Screen blanking / screensaver disabled (display stays on 24/7).
- Auto-restart of Chromium if it ever crashes.
- Suppression of the "Chrome wasn't shut down properly" yellow bar that
  otherwise appears after power loss (Alamos KB workaround).
- Sound autoplay allowed (so the alarm gong plays without interaction).
- Noto color emoji font installed (Alamos requirement for icon
  display).
- Autostart entries written for **labwc** (default compositor on
  current Bookworm), **Wayfire** (older Bookworm releases), and
  **XDG autostart** (legacy X11/LXDE) — so the setup is portable.

## Requirements

- Raspberry Pi 4 Model B (2 GB+ RAM). Pi 5 also works but Alamos has
  not officially tested it.
- A fresh install of **Raspberry Pi OS Bookworm 64-bit (Desktop)** —
  imaged with Raspberry Pi Imager.
- Network access (Ethernet recommended for a kiosk).
- Your AMweb URL of the form `https://web.alarmmonitor.de/<AccessId>`,
  plus the AMweb password and the encryption password that you
  defined in FE2 when creating the AMweb.

## Quick start

1. Flash Raspberry Pi OS Bookworm 64-bit Desktop to an SD card with
   Raspberry Pi Imager. In the imager's advanced options, set the
   hostname, user, password, Wi-Fi (if needed), locale, and **enable
   SSH** if you want.
2. Boot the Pi, finish the on-screen welcome wizard, make sure it has
   internet.
3. Copy `setup-amweb-kiosk.sh` onto the Pi (USB stick, `scp`, etc.).
4. Open a Terminal on the Pi and run:

   ```bash
   chmod +x setup-amweb-kiosk.sh
   ./setup-amweb-kiosk.sh
   ```

   When prompted, paste your full AMweb URL.

5. Reboot:

   ```bash
   sudo reboot
   ```

6. After reboot, Chromium opens the AMweb. **Log in once** with your
   AMweb password and encryption password. From then on, every reboot
   will land directly in the logged-in AMweb.

## How "auto-login" works

The Alamos URL `https://web.alarmmonitor.de/<AccessId>` is a permanent
token URL. The login screen that follows asks for the AMweb password
and the encryption password, both of which were defined when the
AMweb was created in FE2. After a successful first login, Chromium
stores the session in its user-data-dir
(`~/.config/chromium-amweb/`). Because that directory persists on the
SD card, every subsequent reboot — including after a power loss —
loads the same session and the AMweb is shown directly, without a
new login prompt.

There is **no second secret stored on disk in plain text** by this
script. The credentials live only inside Chromium's normal cookie /
localStorage / IndexedDB files, encrypted at rest the way Chromium
encrypts them by default on Linux.

## Exiting kiosk mode

Press `Ctrl+F4` or `Alt+F4` on a keyboard attached to the Pi.

## Optional: remote access via Tailscale (`install-tailscale.sh`)

If you want to manage the Pi remotely (SSH from anywhere without
opening ports, no key management headaches), run `install-tailscale.sh`
after the kiosk is set up. It installs Tailscale, joins your tailnet
with **Tailscale SSH** enabled, and prints the IP / MagicDNS name
you can SSH to.

### One-time prep (in your Tailscale admin console)

1. Go to <https://login.tailscale.com/admin/settings/keys>.
2. Click **Generate auth key**.
   - **Reusable**: optional.
   - **Ephemeral**: leave OFF (you want the Pi to persist across reboots).
   - **Pre-approved**: ON if your tailnet requires device approval.
   - **Tags**: optional (e.g. `tag:kiosk`).
3. Copy the key. It starts with `tskey-auth-`.

### On the Pi

```bash
chmod +x install-tailscale.sh
./install-tailscale.sh
```

When prompted:
- Confirm the tailnet hostname (defaults to the Pi's current
  hostname).
- Paste the pre-auth key. Input is hidden — nothing echoes.

When the script finishes it prints the Tailscale IPv4 and the
MagicDNS hostname.

### SSH in from anywhere

From any other device on your tailnet:

```bash
ssh <pi-user>@<hostname>      # e.g. ssh pi@amweb-pi
ssh <pi-user>@<tailscale-ip>  # e.g. ssh pi@100.x.y.z
```

No password, no SSH key setup on the Pi — Tailscale SSH handles
authentication against your tailnet identity and ACLs.

### Notes / caveats

- The pre-auth key is a secret. The script never echoes it, never
  logs it, and `unset`s it from the shell as soon as `tailscale up`
  returns. It is **not** stored on disk.
- Tailscale SSH requires that your tailnet ACLs permit SSH from
  your source identity to this device. The default Tailscale ACL
  allows it; if you've customised ACLs, make sure SSH is allowed.
- The classic OpenSSH server on the Pi is independent of this. If
  you want it too, enable it with `sudo systemctl enable --now ssh`.
- To remove Tailscale later: `sudo tailscale logout && sudo apt
  remove tailscale`.

## Updating the URL later

Edit the line that begins `AMWEB_URL=` in `~/amweb-kiosk.sh`:

```bash
AMWEB_URL="https://web.alarmmonitor.de/..."
```

then reboot or run the script manually.

## Troubleshooting

**Blank / white tab after boot**
The Alamos KB recommends disabling hardware acceleration in
Chromium: open Chromium → Settings → System → "Use hardware
acceleration when available" → off → relaunch. (The kiosk script
already passes `--hide-crash-restore-bubble` and clears the crash
flag, which fixes the most common cause.)

**"Insecure content" warnings**
If your AMweb talks to a local FE2 via plain HTTP, open the AMweb in
Chromium once (outside kiosk mode, e.g. with `Ctrl+F4` first), click
the padlock → site settings, and set
*Sound = Allow*, *Insecure content = Allow*, and (Chrome ≥ 124)
*Local network access = Allow*. These are stored per-profile and
will persist.

**No sound on the alarm gong**
Make sure the Pi's audio output is configured (right-click the
speaker icon in the taskbar before kiosk starts, or use `raspi-config`).
The launcher already passes
`--autoplay-policy=no-user-gesture-required`, so autoplay is allowed.

**The browser closes/exits and stays gone**
The launcher has a `while true` loop and restarts Chromium after 5 s.
If it's not coming back, check `journalctl --user -xe` for errors.

## Sources

- [Alamos Handbuch — Autostart AMweb](https://alamos-support.atlassian.net/wiki/spaces/documentation/pages/2496790534/Autostart+AMweb)
- [Alamos Handbuch — AMweb Kioskmode/PWA und mehrere Bildschirme](https://alamos-support.atlassian.net/wiki/spaces/documentation/pages/2710208513/AMweb+Kioskmode+PWA+und+mehrere+Bildschirme)
- [Alamos Handbuch — Systemvoraussetzungen und Einstellungen für den Browser](https://alamos-support.atlassian.net/wiki/spaces/documentation/pages/2390622209/Systemvoraussetzungen+und+Einstellungen+f%C3%BCr+den+Browser)
- [Alamos Handbuch — Erste Schritte am AMweb Industrie-PC](https://alamos-support.atlassian.net/wiki/spaces/documentation/pages/2514845697/Erste+Schritte+am+AMweb+Industrie-PC)
