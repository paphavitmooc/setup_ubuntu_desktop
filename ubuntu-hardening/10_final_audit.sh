#!/bin/bash
# ============================================================
# 10_final_audit.sh — Security audit + Lynis scan
# Each section writes directly — no pipe buffering
# ============================================================
set -euo pipefail

REPORT="/root/security-audit-$(date +%F).txt"
> "$REPORT"   # truncate/create fresh

# Helper: print section header to screen AND file
section() {
  echo "" | tee -a "$REPORT"
  echo "══════════════════════════════════════════" | tee -a "$REPORT"
  echo "  $1" | tee -a "$REPORT"
  echo "══════════════════════════════════════════" | tee -a "$REPORT"
}

apt-get install -y lynis net-tools 2>&1 | grep -E "^(Setting up|already)" || true

echo "============================================================" | tee "$REPORT"
echo " Ubuntu 24.04 Security Audit -- $(hostname) -- $(date)"     | tee -a "$REPORT"
echo "============================================================" | tee -a "$REPORT"

# ── 1. Users ──────────────────────────────────────────────
section "USERS WITH UID 0 (should only be root)"
awk -F: '($3 == "0") {print $1}' /etc/passwd | tee -a "$REPORT"

section "USERS WITH NO PASSWORD"
awk -F: '($2 == "") {print $1}' /etc/shadow 2>/dev/null | tee -a "$REPORT" || echo "(none)" | tee -a "$REPORT"

section "SUDO GROUP MEMBERS"
grep -Po '^sudo.+:\K.*' /etc/group 2>/dev/null | tee -a "$REPORT" || true

# ── 2. Network ────────────────────────────────────────────
section "OPEN PORTS (listening)"
ss -tlnp 2>/dev/null | tee -a "$REPORT"

section "UFW STATUS"
ufw status verbose 2>/dev/null | tee -a "$REPORT"

section "UNEXPECTED OPEN PORTS (not 22/80/443/7070/53/123)"
ss -tlnp 2>/dev/null \
  | awk 'NR>1{print $4}' \
  | grep -oP '(?<=:)[0-9]+' \
  | sort -un \
  | grep -vE '^(22|80|443|7070|53|68|123|3306|5432)$' \
  | while read -r port; do
      echo "  WARNING: Port $port open -- verify intentional" | tee -a "$REPORT"
    done || echo "  None found." | tee -a "$REPORT"

# ── 3. Services ───────────────────────────────────────────
section "FAIL2BAN JAILS"
fail2ban-client status 2>/dev/null | tee -a "$REPORT" || echo "fail2ban not running" | tee -a "$REPORT"

section "ACTIVE BANS PER JAIL"
fail2ban-client status 2>/dev/null \
  | grep "Jail list" \
  | sed 's/.*://;s/,/ /g' \
  | tr ' ' '\n' \
  | while read -r jail; do
      jail=$(echo "$jail" | xargs)
      [[ -z "$jail" ]] && continue
      COUNT=$(fail2ban-client status "$jail" 2>/dev/null | grep "Currently banned" | awk '{print $NF}')
      BANNED=$(fail2ban-client status "$jail" 2>/dev/null | grep "Banned IP" | cut -d: -f2 | xargs)
      echo "  [$jail] banned=$COUNT  IPs: ${BANNED:-none}" | tee -a "$REPORT"
    done

section "APPARMOR STATUS"
aa-status 2>/dev/null \
  | grep -E "profiles are loaded|in enforce|in complain|unconfined" \
  | tee -a "$REPORT"

section "RUNNING SERVICES"
systemctl list-units --type=service --state=running --no-pager 2>/dev/null | tee -a "$REPORT"

# ── 4. SSH ────────────────────────────────────────────────
section "SSH CONFIGURATION"
sshd -T 2>/dev/null \
  | grep -E "permitrootlogin|passwordauthentication|pubkeyauthentication|maxauthtries|port|logingracetime" \
  | tee -a "$REPORT"

# ── 5. File system ────────────────────────────────────────
section "SUID/SGID BINARIES (snap/proc/sys excluded)"
find / \
  -path /proc -prune -o \
  -path /sys  -prune -o \
  -path /snap -prune -o \
  -path /run  -prune -o \
  \( -perm -4000 -o -perm -2000 \) -type f -print \
  2>/dev/null \
  | sort \
  | tee -a "$REPORT"

section "WORLD-WRITABLE FILES (top 30, snap/proc/sys excluded)"
find / \
  -path /proc -prune -o \
  -path /sys  -prune -o \
  -path /snap -prune -o \
  -path /run  -prune -o \
  -xdev -type f -perm -0002 -print \
  2>/dev/null \
  | head -30 \
  | tee -a "$REPORT"

# ── 6. Cron ───────────────────────────────────────────────
section "CRON JOBS"
ls -la /etc/cron.d /etc/cron.daily /etc/cron.weekly /etc/crontab 2>/dev/null | tee -a "$REPORT" || true
ls -la /var/spool/cron/crontabs/ 2>/dev/null | tee -a "$REPORT" || echo "  (no user crontabs)" | tee -a "$REPORT"

# ── 7. Kernel & patches ───────────────────────────────────
section "KERNEL VERSION"
uname -a | tee -a "$REPORT"
RUNNING=$(uname -r)
LATEST=$(ls /boot/vmlinuz-* 2>/dev/null | sort -V | tail -1 | sed 's|/boot/vmlinuz-||')
if [[ "$RUNNING" != "$LATEST" ]]; then
  echo "  WARNING: Reboot needed -- running=$RUNNING  latest=$LATEST" | tee -a "$REPORT"
else
  echo "  OK: Running latest kernel $RUNNING" | tee -a "$REPORT"
fi

section "UBUNTU PRO / ESM STATUS"
pro status 2>/dev/null | tee -a "$REPORT" || echo "Ubuntu Pro status unavailable" | tee -a "$REPORT"

# ── 8. Lynis ──────────────────────────────────────────────
section "LYNIS HARDENING AUDIT"
echo "[10] Running Lynis (takes ~2-3 minutes)..."
lynis audit system --quick --no-colors 2>&1 | tee -a "$REPORT"

# ── 9. Final summary ──────────────────────────────────────
SCORE=$(grep -i "hardening index" "$REPORT" | grep -oP '[0-9]+' | tail -1)

echo "" | tee -a "$REPORT"
echo "========================================================" | tee -a "$REPORT"
echo "  SECURITY AUDIT COMPLETE" | tee -a "$REPORT"
echo "  Report : $REPORT" | tee -a "$REPORT"
if [[ -n "$SCORE" ]]; then
  GRADE="AIM FOR 80+"
  [[ "$SCORE" -ge 80 ]] && GRADE="GOOD"
  echo "  Lynis  : $SCORE / 100  [$GRADE]" | tee -a "$REPORT"
fi
echo "========================================================" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"
echo "  NEXT STEPS:" | tee -a "$REPORT"
echo "  1. Add SSH key then set PasswordAuthentication no" | tee -a "$REPORT"
echo "  2. certbot --nginx -d yourdomain.com   (HTTPS)" | tee -a "$REPORT"
echo "  3. sudo reboot  (if kernel upgrade pending)" | tee -a "$REPORT"
echo "  4. sudo watch-attacks  (live threat view)" | tee -a "$REPORT"
echo "========================================================" | tee -a "$REPORT"
