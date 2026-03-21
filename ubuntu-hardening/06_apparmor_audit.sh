#!/bin/bash
# ============================================================
# 06_apparmor_audit.sh — AppArmor enforce mode + profile audit
# ============================================================
set -euo pipefail
echo "[06] AppArmor Configuration"

# Suppress needrestart interactive prompts during apt
export NEEDRESTART_MODE=a
export DEBIAN_FRONTEND=noninteractive

apt-get install -y apparmor apparmor-utils apparmor-profiles apparmor-profiles-extra

# Enable AppArmor
systemctl enable apparmor
systemctl start apparmor

# Desktop app profiles that break normal usage in enforce mode
# These are set to complain mode (logs but does not block)
COMPLAIN_PROFILES=(
  nautilus          # GNOME Files — enforce breaks folder browsing
  evince            # PDF viewer
  totem             # Video player
  geary             # Email client
  evolution         # Email/calendar
  epiphany          # GNOME browser
  loupe             # Image viewer
  foliate           # Ebook reader
)

echo "[06] Setting profiles to enforce mode (desktop apps kept in complain)..."
for profile in /etc/apparmor.d/*; do
  [[ -f "$profile" ]] || continue   # skip directories

  basename=$(basename "$profile")
  skip=false
  for cp in "${COMPLAIN_PROFILES[@]}"; do
    if [[ "$basename" == *"$cp"* ]]; then
      skip=true
      break
    fi
  done

  if $skip; then
    aa-complain "$profile" 2>/dev/null || true
    echo "[06]   complain mode: $basename"
  else
    aa-enforce "$profile" 2>/dev/null || true
  fi
done

# Summary counts only
TOTAL=$(aa-status 2>/dev/null | grep "profiles are loaded"   | awk '{print $1}')
ENFORCED=$(aa-status 2>/dev/null | grep "profiles are in enforce" | awk '{print $1}')
echo "[06] AppArmor: $TOTAL profiles loaded, $ENFORCED in enforce mode"

# ── auditd: idempotent install ────────────────────────────
apt-get install -y auditd audispd-plugins

AUDIT_RULES=/etc/audit/rules.d/hardening.rules

if grep -q "hardening rules managed by 06_apparmor_audit" "$AUDIT_RULES" 2>/dev/null; then
  echo "[06] auditd rules already present — skipping."
else
  cat >> "$AUDIT_RULES" <<'EOF'
# === hardening rules managed by 06_apparmor_audit ===

# Monitor authentication files
-w /etc/passwd   -p wa -k identity
-w /etc/shadow   -p wa -k identity
-w /etc/group    -p wa -k identity
-w /etc/gshadow  -p wa -k identity
-w /etc/sudoers  -p wa -k identity
-w /etc/sudoers.d -p wa -k identity

# Monitor SSH config
-w /etc/ssh/sshd_config -p wa -k sshd_config

# Monitor cron
-w /etc/cron.allow      -p wa -k cron
-w /etc/cron.deny       -p wa -k cron
-w /etc/cron.d          -p wa -k cron
-w /etc/crontab         -p wa -k cron
-w /var/spool/cron      -p wa -k cron

# Monitor login/logout events
-w /var/log/faillog     -p wa -k logins
-w /var/log/lastlog     -p wa -k logins
-w /var/log/wtmp        -p wa -k logins

# Monitor kernel module loading
-w /sbin/insmod         -p x  -k modules
-w /sbin/rmmod          -p x  -k modules
-w /sbin/modprobe       -p x  -k modules
-a always,exit -F arch=b64 -S init_module -S delete_module -k modules

# Monitor privilege escalation
-a always,exit -F arch=b64 -S setuid -S setgid -F auid>=1000 -F auid!=-1 -k privilege_esc

# Monitor file deletions by users
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=-1 -k delete

# === end hardening rules ===
EOF
  echo "[06] auditd rules written to $AUDIT_RULES"
fi

systemctl enable auditd
systemctl restart auditd

# ── Kernel upgrade notice ─────────────────────────────────
RUNNING=$(uname -r)
EXPECTED=$(ls /boot/vmlinuz-* 2>/dev/null | sort -V | tail -1 | sed 's|/boot/vmlinuz-||')
if [[ "$RUNNING" != "$EXPECTED" ]]; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ⚠  REBOOT REQUIRED"
  echo "  Running kernel : $RUNNING"
  echo "  Latest kernel  : $EXPECTED"
  echo "  Run: sudo reboot"
  echo "  Then re-run any remaining scripts after reboot."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

echo "[06] ✓ AppArmor enforced, auditd configured with security audit rules"
