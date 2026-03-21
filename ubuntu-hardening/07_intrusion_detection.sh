#!/bin/bash
# ============================================================
# 07_intrusion_detection.sh — AIDE file integrity + rkhunter rootkit scan
# ============================================================
set -euo pipefail
echo "[07] Intrusion Detection (AIDE + rkhunter + chkrootkit)"

apt-get install -y aide aide-common rkhunter chkrootkit

# ── AIDE: File Integrity Monitoring ───────────────────────
echo "[07] Initialising AIDE database (this takes a few minutes)..."

# Configure AIDE
cat > /etc/aide/aide.conf.d/99-custom.conf <<'EOF'
# Custom rules for web server hardening
/etc/           Full
/bin/           Full
/sbin/          Full
/usr/bin/       Full
/usr/sbin/      Full
/lib/           Full
/lib64/         Full
/boot/          Full
/var/www/       Full
!/var/log/      # Exclude dynamic log files
!/proc/
!/sys/
!/dev/
!/run/
!/tmp/
!/var/tmp/
EOF

# Initialise AIDE database
aide --config=/etc/aide/aide.conf --init 2>&1 | tail -5
if [[ -f /var/lib/aide/aide.db.new ]]; then
  cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
  echo "[07] AIDE database initialised at /var/lib/aide/aide.db"
fi

# Schedule daily AIDE checks at 3:00 AM
cat > /etc/cron.d/aide-check <<'EOF'
0 3 * * * root /usr/bin/aide --check --config=/etc/aide/aide.conf 2>&1 | mail -s "[AIDE] Integrity Report $(hostname)" root
EOF

# ── rkhunter: Rootkit Detection ───────────────────────────
echo "[07] Configuring rkhunter..."

# Configure rkhunter
# Fix Ubuntu 24.04 issue: WEB_CMD defaults to "/bin/false" (relative path) — must be empty
sed -i 's|^WEB_CMD=.*|WEB_CMD=""|' /etc/rkhunter.conf
# If the line doesn't exist yet, append it
grep -q '^WEB_CMD=' /etc/rkhunter.conf || echo 'WEB_CMD=""' >> /etc/rkhunter.conf

# Set mail and daily run
sed -i 's/^#MAIL-ON-WARNING=/MAIL-ON-WARNING=root/' /etc/rkhunter.conf 2>/dev/null || true
sed -i 's/^CRON_DAILY_RUN=""/CRON_DAILY_RUN="yes"/' /etc/default/rkhunter 2>/dev/null || true

# Try network update — skip gracefully if unreachable (non-critical)
echo "[07] Attempting rkhunter definition update (skipped if network unavailable)..."
if rkhunter --update --nocolors 2>&1 | tee /tmp/rkhunter-update.log | grep -q "Update failed"; then
  echo "[07] rkhunter network update skipped — definitions may be from package install."
  echo "[07] This is non-critical. Scan will still use locally installed signatures."
else
  echo "[07] rkhunter definitions updated OK."
fi

# Update local file property database (uses local files only — always works)
echo "[07] Updating rkhunter property database..."
rkhunter --propupd --nocolors 2>&1 | tail -3

# Run initial scan (local only — no network needed)
echo "[07] Running initial rkhunter scan..."
rkhunter --check --nocolors --skip-keypress 2>&1   | grep -E "Warning|Rootkit|Suspicious|INFECTED"   || echo "[07] rkhunter: No rootkits found"

# ── chkrootkit: Secondary rootkit scanner ─────────────────
echo "[07] Running chkrootkit scan..."
chkrootkit 2>&1 | grep -v "not found" | grep -E "INFECTED|Suspect" || echo "[07] chkrootkit: Clean"

# Schedule weekly chkrootkit
cat > /etc/cron.weekly/chkrootkit-scan <<'EOF'
#!/bin/bash
/usr/sbin/chkrootkit 2>&1 | grep -E "INFECTED|Suspect" | mail -s "[chkrootkit] Scan $(hostname)" root
EOF
chmod +x /etc/cron.weekly/chkrootkit-scan

echo "[07] ✓ AIDE, rkhunter, chkrootkit installed — daily/weekly scans scheduled"
