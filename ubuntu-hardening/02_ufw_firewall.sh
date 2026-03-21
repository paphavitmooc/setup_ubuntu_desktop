#!/bin/bash
# ============================================================
# 02_ufw_firewall.sh — UFW Firewall with AnyDesk + Web Server rules
# Keeps AnyDesk (TCP/UDP 7070) + SSH + HTTP/HTTPS open.
# ============================================================
set -euo pipefail
echo "[02] UFW Firewall Configuration"

apt-get install -y ufw

# Reset to clean state
ufw --force reset

# Default policies — deny all inbound, allow all outbound
ufw default deny incoming
ufw default allow outgoing
ufw default deny forward

# ── SSH (change port if you've customised it) ──────────────
ufw limit 22/tcp comment 'SSH - rate limited'

# ── AnyDesk remote access ──────────────────────────────────
ufw allow 7070/tcp comment 'AnyDesk TCP'
ufw allow 7070/udp comment 'AnyDesk UDP'
# AnyDesk also uses relay via these ports (optional but recommended)
ufw allow 80/tcp  comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

# ── Web server ports ───────────────────────────────────────
# (80 and 443 already opened above)

# ── Enable UFW before editing before.rules ─────────────────
ufw --force enable
ufw status verbose

# ── Harden before.rules — insert BEFORE the COMMIT line ───
echo "[02] Injecting packet-drop rules into before.rules..."

BEFORE_RULES=/etc/ufw/before.rules

# Only inject once (idempotent)
if ! grep -q "Drop XMAS packets" "$BEFORE_RULES"; then

  TMPFILE=$(mktemp)
  while IFS= read -r line; do
    if [[ "$line" == "COMMIT" ]]; then
      cat <<'INJECT'

# ── Custom hardening rules ────────────────────────────────
# Drop invalid packets
-A ufw-before-input -m conntrack --ctstate INVALID -j DROP

# Drop TCP packets that are new and not SYN
-A ufw-before-input -p tcp ! --syn -m conntrack --ctstate NEW -j DROP

# Drop fragmented packets
-A ufw-before-input -f -j DROP

# Drop XMAS packets
-A ufw-before-input -p tcp --tcp-flags ALL ALL -j DROP

# Drop NULL packets
-A ufw-before-input -p tcp --tcp-flags ALL NONE -j DROP
# ─────────────────────────────────────────────────────────
INJECT
    fi
    echo "$line"
  done < "$BEFORE_RULES" > "$TMPFILE"

  mv "$TMPFILE" "$BEFORE_RULES"
  echo "[02] Rules injected successfully."
else
  echo "[02] Rules already present — skipping injection."
fi

ufw reload
ufw status verbose

echo "[02] ✓ Firewall configured — AnyDesk :7070, SSH :22, HTTP :80, HTTPS :443"
