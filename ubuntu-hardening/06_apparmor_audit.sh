#!/bin/bash
# ============================================================
# 06_apparmor_audit.sh — AppArmor + auditd
# Philosophy: enforce for system daemons, complain for all
# desktop/GUI apps so new software installs work out of the box.
# ============================================================
set -euo pipefail
echo "[06] AppArmor Configuration"

export NEEDRESTART_MODE=a
export DEBIAN_FRONTEND=noninteractive

apt-get install -y apparmor apparmor-utils apparmor-profiles apparmor-profiles-extra

systemctl enable apparmor
systemctl start apparmor

# ── Complain list ─────────────────────────────────────────
# Any profile whose filename contains one of these strings
# will be set to COMPLAIN mode (logs but never blocks).
# Add your own app names here if needed.
COMPLAIN_PROFILES=(
  # ── File managers ──────────────────────────────────────
  nautilus thunar nemo dolphin pcmanfm

  # ── Web browsers ───────────────────────────────────────
  chrome google-chrome firefox brave msedge opera vivaldi chromium

  # ── Media & documents ──────────────────────────────────
  evince totem loupe eog shotwell foliate okular vlc mpv

  # ── Email & calendar ───────────────────────────────────
  geary evolution thunderbird

  # ── Developer tools ────────────────────────────────────
  code vscodium sublime jetbrains rider idea pycharm

  # ── Communication ──────────────────────────────────────
  discord slack teams zoom skype telegram signal

  # ── Productivity ───────────────────────────────────────
  obsidian notion libreoffice soffice

  # ── System GUI tools ───────────────────────────────────
  gnome-remote-desktop gparted synaptic flatpak snap

  # ── Package managers / installers ─────────────────────
  dpkg apt gdebi packagekit

  # ── Graphics ───────────────────────────────────────────
  gimp inkscape blender krita

  # ── AnyDesk remote ─────────────────────────────────────
  anydesk

  # ── Desktop shell ──────────────────────────────────────
  plasmashell gnome-shell
)

echo "[06] Setting profiles — daemons=enforce, desktop apps=complain..."
ENFORCED_COUNT=0
COMPLAIN_COUNT=0

for profile in /etc/apparmor.d/*; do
  [[ -f "$profile" ]] || continue

  bname=$(basename "$profile")
  is_complain=false

  for cp in "${COMPLAIN_PROFILES[@]}"; do
    if [[ "${bname,,}" == *"${cp,,}"* ]]; then
      is_complain=true
      break
    fi
  done

  if $is_complain; then
    aa-complain "$profile" 2>/dev/null || true
    (( COMPLAIN_COUNT++ )) || true
  else
    aa-enforce "$profile" 2>/dev/null || true
    (( ENFORCED_COUNT++ )) || true
  fi
done

echo "[06] Enforce: $ENFORCED_COUNT profiles | Complain: $COMPLAIN_COUNT profiles"

# ── Helper: relax a new app instantly ─────────────────────
# Creates /usr/local/bin/apparmor-relax so you can run:
#   sudo apparmor-relax appname
cat > /usr/local/bin/apparmor-relax << 'HELPER'
#!/bin/bash
# Usage: sudo apparmor-relax <appname>
# Sets an AppArmor profile to complain mode so a new app works.
if [[ -z "${1:-}" ]]; then
  echo "Usage: sudo apparmor-relax <appname>"
  echo "Example: sudo apparmor-relax zoom"
  exit 1
fi
APP="$1"
FOUND=0
for profile in /etc/apparmor.d/*; do
  [[ -f "$profile" ]] || continue
  if [[ "$(basename $profile)" == *"$APP"* ]]; then
    aa-complain "$profile"
    echo "Set to complain mode: $(basename $profile)"
    FOUND=1
  fi
done
systemctl reload apparmor
[[ $FOUND -eq 0 ]] && echo "No AppArmor profile found for '$APP' — app may run without restriction already."
HELPER
chmod +x /usr/local/bin/apparmor-relax

# ── auditd ────────────────────────────────────────────────
apt-get install -y auditd audispd-plugins

AUDIT_RULES=/etc/audit/rules.d/hardening.rules

if grep -q "hardening rules managed by 06_apparmor_audit" "$AUDIT_RULES" 2>/dev/null; then
  echo "[06] auditd rules already present — skipping."
else
  cat >> "$AUDIT_RULES" << 'EOF'
# === hardening rules managed by 06_apparmor_audit ===
-w /etc/passwd    -p wa -k identity
-w /etc/shadow    -p wa -k identity
-w /etc/group     -p wa -k identity
-w /etc/gshadow   -p wa -k identity
-w /etc/sudoers   -p wa -k identity
-w /etc/sudoers.d -p wa -k identity
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /etc/cron.allow -p wa -k cron
-w /etc/cron.deny  -p wa -k cron
-w /etc/cron.d     -p wa -k cron
-w /etc/crontab    -p wa -k cron
-w /var/spool/cron -p wa -k cron
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
-w /var/log/wtmp    -p wa -k logins
-w /sbin/insmod    -p x -k modules
-w /sbin/rmmod     -p x -k modules
-w /sbin/modprobe  -p x -k modules
-a always,exit -F arch=b64 -S init_module -S delete_module -k modules
-a always,exit -F arch=b64 -S setuid -S setgid -F auid>=1000 -F auid!=-1 -k privilege_esc
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=-1 -k delete
# === end hardening rules ===
EOF
  echo "[06] auditd rules written."
fi

systemctl enable auditd
systemctl restart auditd

# ── Kernel upgrade notice ─────────────────────────────────
RUNNING=$(uname -r)
EXPECTED=$(ls /boot/vmlinuz-* 2>/dev/null | sort -V | tail -1 | sed 's|/boot/vmlinuz-||')
if [[ "$RUNNING" != "$EXPECTED" ]]; then
  echo ""
  echo "  WARNING: Reboot needed — running=$RUNNING latest=$EXPECTED"
  echo "  Run: sudo reboot"
fi

echo ""
echo "[06] ✓ Done. To relax AppArmor for any new app:"
echo "       sudo apparmor-relax <appname>"
echo "   Example: sudo apparmor-relax zoom"
