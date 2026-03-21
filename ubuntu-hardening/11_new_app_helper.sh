#!/bin/bash
# ============================================================
# 11_new_app_helper.sh — Run this when a new app doesn't work
# after installation. Fixes the most common issues caused by
# the hardening suite.
#
# Usage:
#   sudo bash 11_new_app_helper.sh appname
#   sudo bash 11_new_app_helper.sh zoom
#   sudo bash 11_new_app_helper.sh anydesk
#   sudo bash 11_new_app_helper.sh docker
# ============================================================
set -euo pipefail

APP="${1:-}"

if [[ -z "$APP" ]]; then
  echo ""
  echo "Usage: sudo bash 11_new_app_helper.sh <appname>"
  echo ""
  echo "Examples:"
  echo "  sudo bash 11_new_app_helper.sh zoom"
  echo "  sudo bash 11_new_app_helper.sh docker"
  echo "  sudo bash 11_new_app_helper.sh anydesk"
  echo ""
  echo "What this script does:"
  echo "  1. Relaxes AppArmor profile for the app (complain mode)"
  echo "  2. Opens UFW firewall port if you specify one"
  echo "  3. Whitelists app in Fail2Ban if needed"
  echo "  4. Fixes .deb install permission issues"
  echo "  5. Shows what is blocking the app"
  echo ""
  exit 0
fi

echo "============================================"
echo " New App Helper — fixing: $APP"
echo "============================================"

# ── Step 1: AppArmor relax ────────────────────────────────
echo ""
echo "[1] Checking AppArmor profile for '$APP'..."
FOUND=0
for profile in /etc/apparmor.d/*; do
  [[ -f "$profile" ]] || continue
  bname=$(basename "$profile")
  if [[ "${bname,,}" == *"${APP,,}"* ]]; then
    aa-complain "$profile" 2>/dev/null && echo "    Set to complain: $bname" || true
    FOUND=1
  fi
done
if [[ $FOUND -eq 0 ]]; then
  echo "    No AppArmor profile found for '$APP' — no restriction to remove."
else
  systemctl reload apparmor
  echo "    AppArmor reloaded."
fi

# ── Step 2: Check if app is blocked by Fail2Ban ──────────
echo ""
echo "[2] Checking Fail2Ban for any bans on localhost..."
LOCAL_BANNED=$(fail2ban-client status 2>/dev/null \
  | grep "Jail list" \
  | sed 's/.*://;s/,/ /g' \
  | tr ' ' '\n' \
  | while read -r jail; do
      jail=$(echo "$jail" | xargs)
      [[ -z "$jail" ]] && continue
      fail2ban-client status "$jail" 2>/dev/null \
        | grep "Banned IP" \
        | grep -E "127\.|192\.168\.|10\." || true
    done)
if [[ -n "$LOCAL_BANNED" ]]; then
  echo "    WARNING: Local IP is banned in Fail2Ban — $LOCAL_BANNED"
  echo "    Run: sudo fail2ban-client unban <your-ip>"
else
  echo "    No local bans found in Fail2Ban."
fi

# ── Step 3: UFW port helper ───────────────────────────────
echo ""
echo "[3] UFW port — if '$APP' needs a specific port, run:"
echo "    sudo ufw allow <port>/tcp comment '$APP'"
echo "    Example: sudo ufw allow 8096/tcp comment 'Jellyfin'"
echo "    Example: sudo ufw allow 3000/tcp comment 'Grafana'"

# ── Step 4: Fix .deb install permission issue ─────────────
echo ""
echo "[4] If you installed a .deb file and got permission errors:"
echo "    sudo chmod 644 ~/Downloads/*.deb"
echo "    sudo dpkg -i ~/Downloads/appname.deb"
echo "    sudo apt-get install -f"

# ── Step 5: Check audit log for what blocked the app ─────
echo ""
echo "[5] Checking audit log for recent denials related to '$APP'..."
DENIALS=$(grep -i "$APP" /var/log/audit/audit.log 2>/dev/null \
  | grep "type=AVC\|DENIED" \
  | tail -10 || true)
if [[ -n "$DENIALS" ]]; then
  echo "    Found AppArmor/SELinux denials:"
  echo "$DENIALS" | while read -r line; do echo "    $line"; done
else
  echo "    No audit denials found for '$APP'."
fi

# ── Step 6: Check syslog for app errors ──────────────────
echo ""
echo "[6] Recent syslog errors mentioning '$APP'..."
journalctl -n 20 --no-pager 2>/dev/null \
  | grep -i "$APP" \
  | grep -iE "error|denied|failed|block" \
  | tail -10 \
  || echo "    No recent errors found in journal."

# ── Special app fixes ─────────────────────────────────────
echo ""
case "${APP,,}" in
  docker)
    echo "[*] Docker special fix — enabling required kernel features..."
    sudo sysctl -w net.ipv4.ip_forward=1
    sudo sed -i 's/^net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/' /etc/sysctl.d/99-security.conf
    sudo ufw allow in on docker0 comment 'Docker internal'
    sudo ufw allow 2375/tcp comment 'Docker daemon (local only)'
    echo "    Docker networking enabled."
    ;;
  nginx|apache|apache2)
    echo "[*] Web server fix — ensuring ports 80/443 open in UFW..."
    ufw allow 80/tcp  comment 'HTTP'  2>/dev/null || true
    ufw allow 443/tcp comment 'HTTPS' 2>/dev/null || true
    echo "    Ports 80/443 confirmed open."
    ;;
  mysql|mariadb)
    echo "[*] MySQL/MariaDB — port 3306 is NOT opened in UFW (correct for security)."
    echo "    MySQL should only be accessed locally. If you need remote access:"
    echo "    sudo ufw allow from <trusted-ip> to any port 3306"
    ;;
  postgres|postgresql)
    echo "[*] PostgreSQL — port 5432 is NOT opened in UFW (correct for security)."
    echo "    Use local socket or SSH tunnel for remote access."
    ;;
  nodejs|node|npm)
    echo "[*] Node.js — if running a dev server on port 3000:"
    echo "    sudo ufw allow 3000/tcp comment 'Node.js dev'"
    ;;
  *)
    echo "[*] No special fix needed for '$APP' — general steps above should work."
    ;;
esac

echo ""
echo "============================================"
echo " Done. Try launching '$APP' now."
echo " If still broken, check AppArmor logs:"
echo "   sudo journalctl -f | grep -i apparmor"
echo "============================================"
