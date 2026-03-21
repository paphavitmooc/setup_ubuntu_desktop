#!/bin/bash
# ============================================================
# 03_ssh_hardening.sh — Harden OpenSSH configuration
# ============================================================
set -euo pipefail
echo "[03] SSH Hardening"

apt-get install -y openssh-server

# Backup original config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%F)

# Write hardened sshd_config
cat > /etc/ssh/sshd_config.d/99-hardening.conf <<'EOF'
# ── Authentication ─────────────────────────────────────────
PermitRootLogin no
PasswordAuthentication yes          # Set to 'no' once SSH keys are deployed
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
MaxAuthTries 3
MaxSessions 5
LoginGraceTime 30

# ── Protocol & Crypto ──────────────────────────────────────
Protocol 2
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group14-sha256,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
HostKeyAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521,ssh-ed25519

# ── Session & Forwarding ───────────────────────────────────
ClientAliveInterval 300
ClientAliveCountMax 2
TCPKeepAlive no
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no

# ── Banners & Logging ──────────────────────────────────────
Banner /etc/ssh/banner
LogLevel VERBOSE
SyslogFacility AUTH

# ── Restrict to specific users (uncomment and edit) ────────
# AllowUsers yourusername
EOF

# Create a login banner
cat > /etc/ssh/banner <<'EOF'
*******************************************************************************
  AUTHORIZED ACCESS ONLY — All activity is monitored and logged.
  Unauthorized access will be prosecuted to the fullest extent of the law.
*******************************************************************************
EOF

# Generate stronger host keys if missing
ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" 2>/dev/null || true
ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N "" 2>/dev/null || true

# Remove weak moduli
awk '$5 >= 3071' /etc/ssh/moduli > /tmp/moduli.safe && mv /tmp/moduli.safe /etc/ssh/moduli

# Test config and restart
sshd -t && systemctl restart ssh

echo "[03] ✓ SSH hardened — PasswordAuthentication still ON (disable after adding SSH keys)"
echo "[03]   To disable password auth: set PasswordAuthentication no in /etc/ssh/sshd_config.d/99-hardening.conf"
