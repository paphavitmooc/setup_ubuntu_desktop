#!/bin/bash
# ============================================================
# 05_kernel_hardening.sh — sysctl network & kernel security
# ============================================================
set -euo pipefail
echo "[05] Kernel Hardening (sysctl)"

# Backup existing config
cp /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%F)

cat > /etc/sysctl.d/99-security.conf <<'EOF'
# ── Network: IP Spoofing / Source Routing ─────────────────
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# ── Disable IP forwarding (not a router) ──────────────────
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# ── Ignore ICMP broadcast (Smurf attack) ──────────────────
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# ── SYN flood protection ──────────────────────────────────
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# ── Disable ICMP redirects ────────────────────────────────
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# ── Log martian packets (spoofed) ─────────────────────────
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# ── IPv6 tweaks ───────────────────────────────────────────
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

# ── TCP hardening ─────────────────────────────────────────
net.ipv4.tcp_timestamps = 0           # Hides uptime
net.ipv4.tcp_rfc1337 = 1             # TIME-WAIT assassination attack protection

# ── Kernel: restrict ptrace & core dumps ──────────────────
kernel.yama.ptrace_scope = 2
kernel.core_uses_pid = 1
fs.suid_dumpable = 0

# ── Restrict dmesg access ─────────────────────────────────
kernel.dmesg_restrict = 1

# ── Restrict /proc visibility ─────────────────────────────
kernel.perf_event_paranoid = 3
kernel.kptr_restrict = 2

# ── Randomise memory layout (ASLR) ───────────────────────
kernel.randomize_va_space = 2

# ── Shared memory hardening ───────────────────────────────
kernel.shmmax = 268435456
kernel.shmall = 268435456
EOF

# Apply
sysctl -p /etc/sysctl.d/99-security.conf

# Disable unused/dangerous kernel modules
cat > /etc/modprobe.d/blacklist-rare-network.conf <<'EOF'
# Uncommon network protocols — attack surface reduction
install dccp /bin/true
install sctp /bin/true
install rds  /bin/true
install tipc /bin/true
install n-hdlc /bin/true
install ax25  /bin/true
install netrom /bin/true
install x25   /bin/true
install rose  /bin/true
install decnet /bin/true
install econet /bin/true
install af_802154 /bin/true
install ipx    /bin/true
install appletalk /bin/true
install psnap  /bin/true
install p8023  /bin/true
install p8022  /bin/true
install can    /bin/true
install atm    /bin/true

# Disable USB storage (optional — comment out if needed)
# install usb-storage /bin/true

# Disable firewire (DMA attack vector)
install firewire-core /bin/true
install thunderbolt /bin/true
EOF

update-initramfs -u 2>/dev/null || true

echo "[05] ✓ Kernel hardened — sysctl applied, dangerous modules blacklisted"
