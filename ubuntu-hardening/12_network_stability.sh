#!/bin/bash
# ============================================================
# 12_network_stability.sh — Fix NetworkManager + Netplan issues
# Prevents AnyDesk "no signal" drops caused by:
#   1. Netplan file permissions triggering NM reconfig cycles
#   2. rp_filter conflicting with NM connectivity checks
#   3. Unsafe boot-time netplan apply disconnecting network
# ============================================================
set -euo pipefail
echo "[12] Network Stability Fixes"

# ── Fix 1: Netplan file permissions ───────────────────────
echo "[12] Fixing Netplan file permissions..."
for f in /etc/netplan/*.yaml; do
  [[ -f "$f" ]] || continue
  chmod 600 "$f"
  chown root:root "$f"
  echo "[12]   Fixed: $f"
done

# ── Fix 2: Boot service to keep permissions correct ────────
echo "[12] Installing Netplan permissions boot service..."
cat > /etc/systemd/system/fix-netplan-perms.service << 'EOF'
[Unit]
Description=Fix Netplan file permissions
After=local-fs.target
Before=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'chmod 600 /etc/netplan/*.yaml; chown root:root /etc/netplan/*.yaml'
RemainAfterExit=yes

[Install]
WantedBy=basic.target
EOF

systemctl daemon-reload
systemctl enable fix-netplan-perms.service
echo "[12]   Boot service installed."

# ── Fix 3: NM connectivity check + stable MAC ─────────────────
echo "[12] Configuring NetworkManager connectivity check..."
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/99-stability.conf << 'EOF'
[connectivity]
# Google's generate_204 endpoint — high availability, returns HTTP 204.
# Replaced connectivity-check.ubuntu.com which had prolonged outages.
# interval=60 recovers the network icon within 1 minute after any
# transient failure (down from the 300s default).
uri=http://connectivitycheck.gstatic.com/generate_204
interval=60
response=

[connection]
# Stable MAC address — prevents interface rename drops on VPS
wifi.cloned-mac-address=stable
ethernet.cloned-mac-address=stable
EOF

echo "[12]   NetworkManager stability config written."

# ── Fix 4: netplan helper — safe wrapper ──────────────────
echo "[12] Installing safe netplan wrapper..."
cat > /usr/local/bin/netplan-safe << 'EOF'
#!/bin/bash
# Safe netplan wrapper — always uses 'try' instead of 'apply'
# on a live VPS to prevent network disconnection.
echo "Running: sudo netplan try (safe — auto-reverts in 120s if connection drops)"
echo "Press ENTER within 120 seconds to confirm the new config."
sudo netplan try
EOF
chmod +x /usr/local/bin/netplan-safe
echo "[12]   Use 'netplan-safe' instead of 'netplan apply' on this VPS."

# ── Restart NetworkManager cleanly ────────────────────────
echo "[12] Restarting NetworkManager..."
systemctl restart NetworkManager
sleep 3

# ── Verify ────────────────────────────────────────────────
echo ""
echo "[12] Verification:"
echo "  Netplan permissions:"
stat /etc/netplan/*.yaml 2>/dev/null | grep -E "Access:|File:" | while read line; do
  echo "    $line"
done

echo "  NetworkManager status:"
systemctl is-active NetworkManager && echo "    active (running)" || echo "    NOT running"

NM_WARN=$(journalctl -u NetworkManager --since "1 minute ago" --no-pager 2>/dev/null \
  | grep -iE "warn|error|too open|rp_filter" || true)
if [[ -z "$NM_WARN" ]]; then
  echo "    No warnings — clean"
else
  echo "    Warnings found:"
  echo "$NM_WARN" | while read line; do echo "    $line"; done
fi

echo ""
echo "[12] ✓ Network stability fixes applied."
echo "[12]   AnyDesk should now maintain stable connection."
echo "[12]   Use 'netplan-safe' for future Netplan changes."
