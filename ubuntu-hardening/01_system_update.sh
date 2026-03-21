#!/bin/bash
# ============================================================
# 01_system_update.sh — Full system update + unattended upgrades
# ============================================================
set -euo pipefail
echo "[01] System Update & Auto-Upgrade Configuration"

# Full upgrade
apt-get update -y
apt-get dist-upgrade -y
apt-get autoremove -y
apt-get autoclean -y

# Install essential security tools
apt-get install -y \
  unattended-upgrades \
  apt-listchanges \
  needrestart \
  debsums \
  apt-show-versions

# Enable unattended security upgrades
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Package-Blacklist {};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Mail "root";
EOF

# Enable the auto-upgrade timer
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

systemctl enable unattended-upgrades
systemctl restart unattended-upgrades

# Disable and remove unnecessary services
UNUSED_SERVICES=(avahi-daemon cups bluetooth ModemManager)
for svc in "${UNUSED_SERVICES[@]}"; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    systemctl disable --now "$svc" && echo "[01] Disabled: $svc"
  fi
done

echo "[01] ✓ System update and auto-upgrade configured"
