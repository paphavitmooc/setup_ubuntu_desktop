#!/bin/bash
# ============================================================
# 08_log_monitoring.sh — Logwatch + journald + log rotation hardening
# ============================================================
set -euo pipefail
echo "[08] Log Monitoring & Hardening"

apt-get install -y logwatch rsyslog logrotate

# ── journald: persistent logs + rate limiting ─────────────
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/hardening.conf <<'EOF'
[Journal]
Storage=persistent
Compress=yes
RateLimitInterval=30s
RateLimitBurst=1000
SystemMaxUse=2G
SystemKeepFree=500M
MaxFileSec=1month
ForwardToSyslog=yes
EOF

systemctl restart systemd-journald

# ── rsyslog: forward auth logs clearly ───────────────────
cat >> /etc/rsyslog.d/49-hardening.conf <<'EOF'
# Separate auth events
auth,authpriv.*                 /var/log/auth.log
# Log all kernel messages
kern.*                          /var/log/kern.log
# All other syslog
*.info;auth,authpriv.none       /var/log/syslog
EOF

systemctl restart rsyslog

# ── Logwatch: daily email summary ────────────────────────
cat > /etc/logwatch/conf/logwatch.conf <<'EOF'
Output = mail
Format = html
MailTo = root
MailFrom = logwatch@localhost
Range = yesterday
Detail = Med
Service = All
EOF

# Schedule daily at 07:00
cat > /etc/cron.d/logwatch <<'EOF'
0 7 * * * root /usr/sbin/logwatch --output mail 2>/dev/null
EOF

# ── Log file permissions ───────────────────────────────────
chmod 640 /var/log/auth.log 2>/dev/null || true
chmod 640 /var/log/syslog 2>/dev/null || true
chmod 750 /var/log 2>/dev/null || true

# ── Protect logs from tampering ───────────────────────────
# Set append-only on critical logs (chattr)
for logfile in /var/log/auth.log /var/log/syslog /var/log/kern.log; do
  [[ -f "$logfile" ]] && chattr +a "$logfile" && echo "[08] Set append-only: $logfile"
done

# ── Logrotate: secure settings ────────────────────────────
cat > /etc/logrotate.d/secure-logs <<'EOF'
/var/log/auth.log
/var/log/kern.log
{
    rotate 12
    monthly
    compress
    delaycompress
    missingok
    notifempty
    create 640 syslog adm
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}
EOF

# ── Live monitoring helper script ────────────────────────
cat > /usr/local/bin/watch-attacks <<'EOF'
#!/bin/bash
# Quick view of live attack attempts
echo "=== Recent SSH failures ==="
grep "Failed password\|Invalid user" /var/log/auth.log | tail -20

echo ""
echo "=== Active Fail2Ban bans ==="
fail2ban-client status sshd 2>/dev/null | grep "Banned IP"

echo ""
echo "=== UFW blocked connections (last 20) ==="
grep "UFW BLOCK" /var/log/ufw.log 2>/dev/null | tail -20

echo ""
echo "=== Top attacking IPs ==="
grep "Failed password" /var/log/auth.log | awk '{print $(NF-3)}' | sort | uniq -c | sort -rn | head -10
EOF
chmod +x /usr/local/bin/watch-attacks

echo "[08] ✓ Log monitoring configured — run 'watch-attacks' to see live threats"
