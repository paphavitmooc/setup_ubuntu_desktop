#!/bin/bash
# ============================================================
# 04_fail2ban.sh — Brute-force protection for SSH + web server
# ============================================================
set -euo pipefail
echo "[04] Fail2Ban Installation & Configuration"

apt-get install -y fail2ban

# Global defaults
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
# Ban for 1 hour after 5 failures within 10 minutes
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd
banaction = ufw

# Ignore localhost and private ranges
ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16

# Email alerts (configure your MTA if needed)
destemail = root@localhost
sender    = fail2ban@localhost
action    = %(action_mwl)s

# ── SSH ───────────────────────────────────────────────────
[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = %(syslog_authpriv)s
maxretry = 3
bantime  = 86400    ; 24 hours for SSH

# ── Nginx ────────────────────────────────────────────────
[nginx-http-auth]
enabled  = true
filter   = nginx-http-auth
logpath  = /var/log/nginx/error.log
maxretry = 5

[nginx-limit-req]
enabled  = true
filter   = nginx-limit-req
logpath  = /var/log/nginx/error.log
maxretry = 10

[nginx-botsearch]
enabled  = true
filter   = nginx-botsearch
logpath  = /var/log/nginx/access.log
maxretry = 2

# ── Apache (enable if using Apache) ──────────────────────
[apache-auth]
enabled  = false
logpath  = /var/log/apache2/error.log
maxretry = 5

[apache-badbots]
enabled  = false
logpath  = /var/log/apache2/access.log
maxretry = 2

# ── Port scan detection ───────────────────────────────────
[portscan]
enabled  = true
filter   = portscan
logpath  = /var/log/ufw.log
maxretry = 2
bantime  = 86400

# ── Repeated bad IPs (recidive) ───────────────────────────
[recidive]
enabled  = true
filter   = recidive
logpath  = /var/log/fail2ban.log
action   = %(action_mwl)s
bantime  = 604800   ; 7 days
findtime = 86400
maxretry = 5
EOF

# Custom filter: port scan via UFW log
cat > /etc/fail2ban/filter.d/portscan.conf <<'EOF'
[Definition]
failregex = .*UFW BLOCK.* SRC=<HOST> .*
ignoreregex =
EOF

# Enable and start
systemctl enable fail2ban
systemctl restart fail2ban

sleep 2
fail2ban-client status

echo "[04] ✓ Fail2Ban configured — SSH, Nginx, port-scan, recidive jails active"
