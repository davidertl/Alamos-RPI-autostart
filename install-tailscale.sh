#!/bin/bash
# ---------------------------------------------------------------------------
# Tailscale installer for the AMweb Kiosk Pi.
#
# What this does:
#   1. Installs Tailscale via the official Tailscale install script.
#   2. Enables and starts the tailscaled service.
#   3. Prompts you for a pre-auth key (hidden input, never echoed).
#   4. Joins the tailnet with --ssh enabled (so you can SSH in via Tailscale
#      without managing keys; auth is handled by your tailnet ACLs).
#   5. Prints the Tailscale IPv4 and MagicDNS name so you know how to SSH in.
#
# Pre-auth key:
#   Generate one in your Tailscale admin console:
#     https://login.tailscale.com/admin/settings/keys
#   - "Reusable": optional
#   - "Ephemeral": NO (you want the Pi to persist)
#   - "Pre-approved": YES if your tailnet requires device approval
#   - Tags: optional (e.g. tag:kiosk)
#   The key starts with "tskey-auth-".
#
# Usage:
#   chmod +x install-tailscale.sh
#   ./install-tailscale.sh
#
# After this, from any device on your tailnet:
#   ssh <pi-user>@<hostname>     (e.g. ssh pi@amweb-pi)
#   or
#   ssh <pi-user>@<tailscale-ip> (e.g. ssh pi@100.x.y.z)
# ---------------------------------------------------------------------------

set -euo pipefail

# ---------- 0. Sanity checks ----------------------------------------------
if [[ $EUID -eq 0 ]]; then
    echo "Please run this script as your normal user, NOT as root."
    echo "It will call sudo where needed."
    exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
    echo "ERROR: 'sudo' is required but not installed."
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "Installing curl (required to fetch the Tailscale installer)..."
    sudo apt-get update
    sudo apt-get install -y curl
fi

echo "============================================================"
echo " Tailscale installer for the AMweb Kiosk Pi"
echo "============================================================"

# ---------- 1. Hostname ---------------------------------------------------
CURRENT_HOST="$(hostname)"
DEFAULT_HOST="$CURRENT_HOST"
read -rp "Tailnet hostname for this Pi [$DEFAULT_HOST]: " TS_HOSTNAME
TS_HOSTNAME="${TS_HOSTNAME:-$DEFAULT_HOST}"

# Tailscale hostnames must be lowercase, alnum + hyphens. Be lenient: just warn.
if ! [[ "$TS_HOSTNAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
    echo "WARNING: hostname '$TS_HOSTNAME' contains characters Tailscale may"
    echo "         normalise. Recommended: lowercase letters, digits, hyphens."
    read -rp "Continue anyway? [y/N]: " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || exit 1
fi

# ---------- 2. Pre-auth key (hidden input) --------------------------------
echo ""
echo "Paste your Tailscale pre-auth key now."
echo "Generate one at: https://login.tailscale.com/admin/settings/keys"
echo "(Input is hidden. Nothing will be echoed.)"
TS_AUTHKEY=""
while [[ -z "$TS_AUTHKEY" ]]; do
    read -rsp "Pre-auth key: " TS_AUTHKEY
    echo ""
    if [[ -z "$TS_AUTHKEY" ]]; then
        echo "Empty input. Try again."
        continue
    fi
    if [[ ! "$TS_AUTHKEY" == tskey-auth-* ]]; then
        echo "That does not look like a Tailscale pre-auth key."
        echo "Pre-auth keys start with 'tskey-auth-'."
        read -rp "Use it anyway? [y/N]: " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            TS_AUTHKEY=""
            continue
        fi
    fi
done

# ---------- 3. Install Tailscale ------------------------------------------
echo ""
echo "[1/3] Installing Tailscale (this may take a minute)..."
if ! command -v tailscale >/dev/null 2>&1; then
    curl -fsSL https://tailscale.com/install.sh | sh
else
    echo "      Tailscale is already installed; skipping installer."
fi

# ---------- 4. Enable + start tailscaled ----------------------------------
echo "[2/3] Enabling and starting the tailscaled service..."
sudo systemctl enable --now tailscaled

# ---------- 5. Join the tailnet -------------------------------------------
echo "[3/3] Joining the tailnet as '$TS_HOSTNAME' with --ssh enabled..."
# --ssh         : enable Tailscale SSH (no manual key management)
# --auth-key    : the pre-auth key from the admin console
# --hostname    : what this device shows up as in your tailnet
# --accept-dns  : let MagicDNS resolve other devices for you
sudo tailscale up \
    --ssh \
    --auth-key="$TS_AUTHKEY" \
    --hostname="$TS_HOSTNAME" \
    --accept-dns=true

# Clear the key from memory as soon as we're done with it.
unset TS_AUTHKEY

# ---------- 6. Report connection info -------------------------------------
echo ""
echo "============================================================"
echo " Tailscale is up. Connection info:"
echo ""
TS_IPV4="$(sudo tailscale ip -4 2>/dev/null || echo '(not yet assigned)')"
echo "  Hostname (MagicDNS): $TS_HOSTNAME"
echo "  Tailscale IPv4:      $TS_IPV4"
echo "  Local user:          $(id -un)"
echo ""
echo " From any other device on your tailnet, you can now SSH in:"
echo "   ssh $(id -un)@$TS_HOSTNAME"
echo "   ssh $(id -un)@$TS_IPV4"
echo ""
echo " Full Tailscale status:"
echo "------------------------------------------------------------"
sudo tailscale status || true
echo "============================================================"
