#!/usr/bin/env bash
#
# install-xrdp-xfce-arch.sh
#
# Installs + configures XRDP (xorgxrdp backend) for EndeavourOS/Arch with XFCE.
#
# Goals:
# - Connect via RDP and get an XFCE desktop (Xorg backend, not VNC)
# - Run xrdp daemon unprivileged (xrdp user) instead of root
# - Open firewall port 3389 if firewalld is installed (optional)
#
# Notes:
# - Uses yay whenever possible (as requested). yay will install repo packages too.
# - Login uses your normal user account (e.g. mia). No special "xrdp login user".
#
set -euo pipefail

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────
info()    { echo -e "\e[1;34m[INFO]\e[0m  $*"; }
success() { echo -e "\e[1;1;32m[OK]\e[0m    $*"; }
warn()    { echo -e "\e[1;33m[WARN]\e[0m  $*"; }
error()   { echo -e "\e[1;31m[ERROR]\e[0m $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || error "Missing required command: $1"
}

backup_file() {
  local f="$1"
  if [ -f "$f" ]; then
    sudo cp -a "$f" "$f.bak.$(date +%Y%m%d-%H%M%S)"
    warn "Backed up $f"
  fi
}

# Must NOT be run as root (yay doesn't allow it)
if [ "${EUID:-0}" -eq 0 ]; then
  error "Do not run as root. Run as your normal user; sudo will be used internally."
fi

need_cmd sudo
need_cmd systemctl
need_cmd sed
need_cmd grep
need_cmd yay

# ─────────────────────────────────────────────
# 0) Sanity checks
# ─────────────────────────────────────────────
if ! command -v startxfce4 >/dev/null 2>&1; then
  warn "startxfce4 not found. XFCE might not be fully installed. (Package: xfce4)"
fi

# ─────────────────────────────────────────────
# 1) Install xrdp + xorgxrdp
# ─────────────────────────────────────────────
info "Installing xrdp + xorgxrdp (and a few common XFCE bits) via yay..."
yay -S --noconfirm --needed xrdp xorgxrdp xfce4 xfce4-goodies xterm dbus
success "Packages installed."

# ─────────────────────────────────────────────
# 2) Ensure xrdp system user/group exist
#    (On some setups these might not exist; running as root is not recommended.)
# ─────────────────────────────────────────────
info "Ensuring xrdp system user/group exist..."
if ! getent group xrdp >/dev/null 2>&1; then
  sudo groupadd --system xrdp
  success "Created group: xrdp"
else
  info "Group xrdp already exists."
fi

if ! getent passwd xrdp >/dev/null 2>&1; then
  sudo useradd --system \
    --gid xrdp \
    --home-dir /var/lib/xrdp --create-home \
    --shell /usr/bin/nologin \
    xrdp
  success "Created user: xrdp"
else
  info "User xrdp already exists."
fi

# ─────────────────────────────────────────────
# 3) Configure xrdp to use Xorg backend (xorgxrdp)
# ─────────────────────────────────────────────
XRDP_INI="/etc/xrdp/xrdp.ini"
info "Checking $XRDP_INI for Xorg backend..."
if [ ! -f "$XRDP_INI" ]; then
  error "$XRDP_INI not found. Was xrdp installed correctly?"
fi

backup_file "$XRDP_INI"

# Un-comment a commented [Xorg] header if present
sudo sed -i 's/^#\s*\[Xorg\]/[Xorg]/' "$XRDP_INI" || true

if ! grep -q '^\[Xorg\]' "$XRDP_INI"; then
  warn "No [Xorg] section found in $XRDP_INI. xorgxrdp may not be installed correctly."
else
  success "Xorg backend appears present in $XRDP_INI."
fi

# ─────────────────────────────────────────────
# 4) Configure /etc/xrdp/startwm.sh to start XFCE for XRDP sessions
#    IMPORTANT: Do NOT append exec after the end of the script.
#    Patch inside wm_start() so XRDP_SESSION triggers XFCE.
# ─────────────────────────────────────────────
STARTWM="/etc/xrdp/startwm.sh"
info "Configuring $STARTWM for XFCE..."
if [ ! -f "$STARTWM" ]; then
  error "$STARTWM not found. Was xrdp installed correctly?"
fi

backup_file "$STARTWM"

# Insert our block once (idempotent). We add it inside wm_start() after locale handling.
MARKER_BEGIN="# --- XRDP XFCE START (added by install-xrdp-xfce-arch.sh) ---"
MARKER_END="# --- XRDP XFCE END ---"

if sudo grep -qF "$MARKER_BEGIN" "$STARTWM"; then
  info "XFCE start block already present in $STARTWM. Skipping insertion."
else
  # We insert after the block:
  #   if [ -r /etc/locale.conf ]; then ... fi
  # which is present in Arch's startwm.sh.
  info "Inserting XFCE start block into wm_start()..."
  sudo awk -v mb="$MARKER_BEGIN" -v me="$MARKER_END" '
    BEGIN { inserted=0 }
    {
      print $0
      if (!inserted &&
          $0 ~ /^  if \[ -r \/etc\/locale\.conf \ ]; then$/) {
        # We wait until we see the closing "fi" of that locale block, then insert.
        in_locale=1
      }
      else if (!inserted && in_locale && $0 ~ /^  fi$/) {
        print ""
        print "  " mb
        print "  if [ -n \"${XRDP_SESSION:-}\" ]; then"
        print "    export XDG_SESSION_TYPE=x11"
        print "    export XDG_CURRENT_DESKTOP=XFCE"
        print "    export XDG_SESSION_DESKTOP=xfce"
        print "    export DESKTOP_SESSION=xfce"
        print ""
        print "    # Ensure we have a session D-Bus"
        print "    if command -v dbus-launch >/dev/null 2>&1 && [ -z \"${DBUS_SESSION_BUS_ADDRESS:-}\" ]; then"
        print "      eval \"$(dbus-launch --sh-syntax --exit-with-session)\""
        print "    fi"
        print ""
        print "    exec /usr/bin/startxfce4"
        print "  fi"
        print "  " me
        print ""
        inserted=1
        in_locale=0
      }
    }
    END {
      if (!inserted) {
        # If the expected locale block was not found, we still want to fail loudly.
        # (Better than silently producing a broken config.)
        exit 42
      }
    }
  ' "$STARTWM" | sudo tee "$STARTWM" >/dev/null

  if [ "${PIPESTATUS[0]}" -eq 42 ]; then
    error "Could not patch $STARTWM (unexpected format). Please paste the file and I will adapt the patch."
  fi

  sudo chmod +x "$STARTWM"
  success "$STARTWM configured to start XFCE for XRDP sessions."
fi

# ─────────────────────────────────────────────
# 5) Run xrdp daemon as unprivileged xrdp user (systemd override)
# ─────────────────────────────────────────────
info "Configuring systemd override so xrdp runs as user xrdp..."
sudo install -d -m 0755 /etc/systemd/system/xrdp.service.d

sudo tee /etc/systemd/system/xrdp.service.d/override.conf >/dev/null <<'EOF'
[Service]
User=xrdp
Group=xrdp
EOF

sudo systemctl daemon-reload
success "systemd override installed."

# ─────────────────────────────────────────────
# 6) Fix permissions for xrdp TLS + rsa keys + logs so unprivileged xrdp can run
# ─────────────────────────────────────────────
info "Fixing permissions for xrdp cert/key/rsakeys and log files..."

# Ensure log files exist and are writable by xrdp
sudo touch /var/log/xrdp.log /var/log/xrdp-sesman.log
sudo chown xrdp:xrdp /var/log/xrdp.log /var/log/xrdp-sesman.log
sudo chmod 0640 /var/log/xrdp.log /var/log/xrdp-sesman.log

# Ensure /etc/xrdp is group-accessible to xrdp and important files are readable
if [ -d /etc/xrdp ]; then
  sudo chgrp xrdp /etc/xrdp
  sudo chmod 0750 /etc/xrdp || true

  for f in /etc/xrdp/cert.pem /etc/xrdp/key.pem /etc/xrdp/rsakeys.ini; do
    if [ -f "$f" ]; then
      sudo chgrp xrdp "$f"
      sudo chmod 0640 "$f"
    fi
  done
fi

success "Permissions updated."

# ─────────────────────────────────────────────
# 7) Optional firewall: open 3389/tcp if firewalld exists
# ─────────────────────────────────────────────
if command -v firewall-cmd >/dev/null 2>&1; then
  info "Configuring firewalld to allow RDP on port 3389/tcp..."
  if ! systemctl is-active --quiet firewalld; then
    info "firewalld is not running. Enabling and starting it..."
    sudo systemctl enable --now firewalld
  fi
  sudo firewall-cmd --zone=public --add-port=3389/tcp --permanent
  sudo firewall-cmd --reload
  success "firewalld configured. Port 3389/tcp is open."
else
  warn "firewall-cmd not found; skipping firewall configuration."
fi

# ─────────────────────────────────────────────
# 8) Enable + start services
# ─────────────────────────────────────────────
info "Enabling and starting xrdp services..."
sudo systemctl enable --now xrdp-sesman
sudo systemctl enable --now xrdp
success "xrdp services enabled and started."

# ─────────────────────────────────────────────
# 9) Done
# ─────────────────────────────────────────────
IP_ADDR="$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}' || true)"

echo ""
echo -e "\e[1;32m══════════════════════════════════════════════\e[0m"
echo -e "\e[1;32m  XRDP + XFCE setup complete!\e[0m"
echo -e "\e[1;32m══════════════════════════════════════════════\e[0m"
echo ""
if [ -n "$IP_ADDR" ]; then
  echo "Connect via RDP to: ${IP_ADDR}:3389"
else
  echo "Connect via RDP to: <this-host>:3389"
fi
echo "Login with your normal user (e.g. mia)."
echo ""
echo "Logs (need sudo):"
echo "  sudo tail -n 200 /var/log/xrdp.log"
echo "  sudo tail -n 200 /var/log/xrdp-sesman.log"
echo ""
warn "If you get locked out by pam_faillock after bad attempts: sudo faillock --user $USER --reset"
