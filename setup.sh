#!/usr/bin/env bash
# =============================================================================
#  NEXUS SECURITY HARDENING SCRIPT
#  Target : Ubuntu Pro 24.04 LTS — Fresh Web Server
#  Author : Alex / Linux Admin
#  Version: 1.0.0
#  Usage  : sudo bash setup.sh
#
#  ⚠️  IMPORTANT BEFORE RUNNING:
#      • You are remoting via AnyDesk on port 7070 — this port is PRESERVED.
#      • Set your SSH_PORT variable below (default 22 or your custom port).
#      • Set your WEB_PORTS if you need non-standard ports.
#      • Read each section before applying in production.
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION — Edit these before running
# ─────────────────────────────────────────────────────────────────────────────
SSH_PORT=22                        # Your SSH port (change if non-default)
ANYDESK_PORT=7070                  # AnyDesk remote access port — DO NOT REMOVE
WEB_PORTS=(80 443)                 # HTTP / HTTPS
ADMIN_EMAIL="admin@example.com"    # For logwatch / fail2ban alerts
TIMEZONE="Asia/Bangkok"            # Server timezone

# SSH hardening — set to your public key or leave empty to skip key enforcement
# ADMIN_SSH_PUBKEY="ssh-ed25519 AAAA... user@host"
ADMIN_SSH_PUBKEY=""

# Automatic reboot time after unattended-upgrades (set "" to disable)
AUTO_REBOOT_TIME="03:00"

# ─────────────────────────────────────────────────────────────────────────────
# COLOURS & HELPERS
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
BLU='\033[0;34m'; CYN='\033[0;36m'; RST='\033[0m'; BLD='\033[1m'

info()    { echo -e "${BLU}[INFO]${RST}  $*"; }
success() { echo -e "${GRN}[OK]${RST}    $*"; }
warn()    { echo -e "${YLW}[WARN]${RST}  $*"; }
error()   { echo -e "${RED}[ERROR]${RST} $*" >&2; }
section() { echo -e "\n${BLD}${CYN}══ $* ══${RST}"; }

require_root() {
  [[ $EUID -eq 0 ]] || { error "Run as root: sudo bash $0"; exit 1; }
}

backup_file() {
  local f="$1"
  [[ -f "$f" ]] && cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)" && info "Backed up $f"
}

# ─────────────────────────────────────────────────────────────────────────────
# 0. PRE-FLIGHT
# ─────────────────────────────────────────────────────────────────────────────
require_root

echo -e "${BLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        Ubuntu Pro 24.04 — Security Hardening Script         ║"
echo "╚══════════════════════════════════════════════════════════════╝${RST}"
echo ""
warn "AnyDesk port ${ANYDESK_PORT} will remain OPEN throughout all firewall rules."
warn "SSH port ${SSH_PORT} will remain OPEN."
echo ""
read -rp "$(echo -e ${YLW}"Proceed? [yes/N]: "${RST})" CONFIRM
[[ "${CONFIRM}" == "yes" ]] || { info "Aborted."; exit 0; }

# ─────────────────────────────────────────────────────────────────────────────
# 1. SYSTEM UPDATE & BASE PACKAGES
# ─────────────────────────────────────────────────────────────────────────────
section "1. System Update & Base Packages"

timedatectl set-timezone "${TIMEZONE}"
success "Timezone set to ${TIMEZONE}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get dist-upgrade -y -qq

apt-get install -y -qq \
  ufw fail2ban unattended-upgrades apt-listchanges \
  auditd audispd-plugins \
  libpam-pwquality libpam-google-authenticator \
  rkhunter chkrootkit aide \
  logwatch lynis \
  curl wget git vim net-tools htop \
  acl attr \
  apparmor apparmor-utils \
  nftables \
  needrestart \
  psad \
  iptables-persistent \
  sysstat

success "Base packages installed"

# ─────────────────────────────────────────────────────────────────────────────
# 2. AUTOMATIC SECURITY UPDATES
# ─────────────────────────────────────────────────────────────────────────────
section "2. Automatic Security Updates"

cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};
Unattended-Upgrade::Package-Blacklist {};
Unattended-Upgrade::DevRelease "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";
Unattended-Upgrade::Automatic-Reboot-Time "${AUTO_REBOOT_TIME}";
Unattended-Upgrade::Mail "${ADMIN_EMAIL}";
Unattended-Upgrade::MailReport "on-change";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

systemctl enable --now unattended-upgrades
success "Automatic security updates configured"

# Ubuntu Pro — enable ESM & livepatch if available
if command -v pro &>/dev/null; then
  info "Ubuntu Pro detected — enabling ESM security repos..."
  pro enable esm-infra  2>/dev/null || warn "esm-infra already enabled or needs attachment"
  pro enable esm-apps   2>/dev/null || warn "esm-apps already enabled or needs attachment"
  success "Ubuntu Pro ESM enabled"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. UFW FIREWALL
# ─────────────────────────────────────────────────────────────────────────────
section "3. UFW Firewall"

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw default deny forward

# SSH
ufw allow "${SSH_PORT}/tcp" comment "SSH"

# AnyDesk — CRITICAL: keep remote access open
ufw allow "${ANYDESK_PORT}/tcp" comment "AnyDesk remote"
ufw allow "${ANYDESK_PORT}/udp" comment "AnyDesk remote UDP"

# Web
for port in "${WEB_PORTS[@]}"; do
  ufw allow "${port}/tcp" comment "Web"
done

# Rate-limit SSH brute-force at UFW level
ufw limit "${SSH_PORT}/tcp" comment "SSH rate limit"

ufw --force enable
ufw status verbose
success "UFW firewall configured"

# ─────────────────────────────────────────────────────────────────────────────
# 4. FAIL2BAN — INTRUSION PREVENTION
# ─────────────────────────────────────────────────────────────────────────────
section "4. Fail2ban"

backup_file /etc/fail2ban/jail.local

cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime          = 3600
findtime         = 600
maxretry         = 5
backend          = systemd
destemail        = ${ADMIN_EMAIL}
sendername       = Fail2Ban-$(hostname)
mta              = sendmail
action           = %(action_mwl)s
ignoreip         = 127.0.0.1/8 ::1

[sshd]
enabled  = true
port     = ${SSH_PORT}
logpath  = %(sshd_log)s
maxretry = 3
bantime  = 86400

[sshd-ddos]
enabled  = true
port     = ${SSH_PORT}
logpath  = %(sshd_log)s
maxretry = 10
findtime = 30
bantime  = 86400

[nginx-http-auth]
enabled  = true
port     = http,https

[nginx-noscript]
enabled  = true
port     = http,https
logpath  = %(nginx_error_log)s

[nginx-badbots]
enabled  = true
port     = http,https
logpath  = %(nginx_access_log)s
maxretry = 2

[nginx-noproxy]
enabled  = true
port     = http,https
logpath  = %(nginx_error_log)s

[php-url-fopen]
enabled  = true
port     = http,https
logpath  = %(nginx_access_log)s

[recidive]
enabled  = true
logpath  = /var/log/fail2ban.log
action   = %(action_mwl)s
bantime  = 604800
findtime = 86400
maxretry = 5
EOF

systemctl enable --now fail2ban
systemctl restart fail2ban
success "Fail2ban configured and started"

# ─────────────────────────────────────────────────────────────────────────────
# 5. SSH HARDENING
# ─────────────────────────────────────────────────────────────────────────────
section "5. SSH Hardening"

backup_file /etc/ssh/sshd_config

cat > /etc/ssh/sshd_config << EOF
# Hardened SSH Configuration
Port ${SSH_PORT}
AddressFamily inet
ListenAddress 0.0.0.0

# Authentication
PermitRootLogin no
MaxAuthTries 3
MaxSessions 5
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Timeouts
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2

# Restrictions
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
PermitUserEnvironment no
PermitTunnel no
GatewayPorts no

# Logging
SyslogFacility AUTH
LogLevel VERBOSE

# Algorithms (strong only)
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com

# Misc
PrintLastLog yes
Banner /etc/ssh/banner
EOF

# SSH warning banner
cat > /etc/ssh/banner << 'BANNER'
╔══════════════════════════════════════════════════════════════╗
║  AUTHORIZED ACCESS ONLY — All activity is logged & monitored ║
╚══════════════════════════════════════════════════════════════╝
BANNER

# Add SSH public key if provided
if [[ -n "${ADMIN_SSH_PUBKEY}" ]]; then
  local_user=$(logname 2>/dev/null || echo "${SUDO_USER:-ubuntu}")
  home_dir=$(eval echo "~${local_user}")
  mkdir -p "${home_dir}/.ssh"
  echo "${ADMIN_SSH_PUBKEY}" >> "${home_dir}/.ssh/authorized_keys"
  chmod 700 "${home_dir}/.ssh"
  chmod 600 "${home_dir}/.ssh/authorized_keys"
  chown -R "${local_user}:${local_user}" "${home_dir}/.ssh"
  success "SSH public key added for ${local_user}"
fi

sshd -t && systemctl restart ssh
success "SSH hardened"

# ─────────────────────────────────────────────────────────────────────────────
# 6. KERNEL / SYSCTL HARDENING
# ─────────────────────────────────────────────────────────────────────────────
section "6. Kernel & Network Hardening (sysctl)"

backup_file /etc/sysctl.conf

cat > /etc/sysctl.d/99-hardening.conf << 'SYSCTL'
# ── Network: Anti-spoofing ──────────────────────────────────────────────────
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# ── Network: ICMP hardening ─────────────────────────────────────────────────
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# ── Network: SYN flood protection ──────────────────────────────────────────
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_max_syn_backlog = 2048

# ── Network: Connection hardening ──────────────────────────────────────────
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_rfc1337 = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# ── IPv6 ────────────────────────────────────────────────────────────────────
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

# ── Kernel: ASLR & hardening ────────────────────────────────────────────────
kernel.randomize_va_space = 2
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.perf_event_paranoid = 3
kernel.yama.ptrace_scope = 1
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2

# ── Kernel: Core dumps ──────────────────────────────────────────────────────
fs.suid_dumpable = 0
kernel.core_uses_pid = 1

# ── File system ─────────────────────────────────────────────────────────────
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2

# ── Virtual memory ──────────────────────────────────────────────────────────
vm.mmap_min_addr = 65536
vm.swappiness = 10
SYSCTL

sysctl --system
success "Kernel hardening applied"

# ─────────────────────────────────────────────────────────────────────────────
# 7. PASSWORD POLICY
# ─────────────────────────────────────────────────────────────────────────────
section "7. Password Policy (PAM)"

backup_file /etc/security/pwquality.conf

cat > /etc/security/pwquality.conf << 'PWQUAL'
minlen = 14
minclass = 3
maxrepeat = 3
maxclassrepeat = 4
lcredit = -1
ucredit = -1
dcredit = -1
ocredit = -1
difok = 8
gecoscheck = 1
badwords = password pass admin root
PWQUAL

# Account inactivity
useradd -D -f 30

# Password expiry defaults
backup_file /etc/login.defs
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/'  /etc/login.defs
sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   14/' /etc/login.defs

success "Password policy configured"

# ─────────────────────────────────────────────────────────────────────────────
# 8. FILE PERMISSIONS & SENSITIVE FILES
# ─────────────────────────────────────────────────────────────────────────────
section "8. File & Directory Permissions"

chmod 700 /root
chmod 600 /etc/shadow
chmod 644 /etc/passwd
chmod 644 /etc/group
chmod 600 /etc/gshadow
chmod 600 /etc/ssh/sshd_config
chmod 600 /etc/crontab
chmod 700 /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly

# Restrict compilers (comment out if building code on server)
if [[ -f /usr/bin/gcc ]]; then
  chmod o-x /usr/bin/gcc
  warn "gcc restricted to root/owner only"
fi

# Sticky bit on world-writable dirs
find / -xdev -type d -perm -0002 -exec chmod +t {} \; 2>/dev/null || true

success "File permissions hardened"

# ─────────────────────────────────────────────────────────────────────────────
# 9. DISABLE UNNECESSARY SERVICES
# ─────────────────────────────────────────────────────────────────────────────
section "9. Disable Unnecessary Services"

DISABLE_SERVICES=(
  avahi-daemon cups isc-dhcp-server isc-dhcp-server6
  slapd nfs-server rpcbind bind9 vsftpd apache2
  dovecot smbd nmbd squid snmpd rsync nis talk telnet xinetd
)

for svc in "${DISABLE_SERVICES[@]}"; do
  if systemctl is-active --quiet "${svc}" 2>/dev/null; then
    systemctl stop "${svc}"
    systemctl disable "${svc}"
    warn "Disabled: ${svc}"
  fi
done

success "Unnecessary services disabled"

# ─────────────────────────────────────────────────────────────────────────────
# 10. APPARMOR
# ─────────────────────────────────────────────────────────────────────────────
section "10. AppArmor (Mandatory Access Control)"

systemctl enable --now apparmor
aa-enforce /etc/apparmor.d/* 2>/dev/null || true
success "AppArmor enforcing mode enabled"

# ─────────────────────────────────────────────────────────────────────────────
# 11. AUDIT DAEMON
# ─────────────────────────────────────────────────────────────────────────────
section "11. Audit Daemon (auditd)"

cat > /etc/audit/rules.d/hardening.rules << 'AUDITRULES'
-D
-b 8192
-f 1

# Identity changes
-w /etc/passwd  -p wa -k identity
-w /etc/shadow  -p wa -k identity
-w /etc/group   -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/sudoers -p wa -k sudo_changes
-w /etc/sudoers.d/ -p wa -k sudo_changes
-w /var/log/auth.log -p wa -k auth_log
-w /var/log/faillog  -p wa -k auth_log

# SSH config
-w /etc/ssh/sshd_config -p wa -k ssh_config

# Cron
-w /etc/cron.allow -p wa -k cron
-w /etc/cron.deny  -p wa -k cron
-w /etc/crontab    -p wa -k cron
-w /etc/cron.d/    -p wa -k cron

# Network
-w /etc/hosts       -p wa -k network
-w /etc/hostname    -p wa -k network
-w /etc/resolv.conf -p wa -k network

# Execution
-a always,exit -F arch=b64 -S execve -k exec
-a always,exit -F arch=b32 -S execve -k exec

# Privilege escalation
-a always,exit -F arch=b64 -S setuid -S setgid -k priv_esc
-a always,exit -F arch=b32 -S setuid -S setgid -k priv_esc

# Kernel modules
-w /sbin/insmod   -p x -k modules
-w /sbin/rmmod    -p x -k modules
-w /sbin/modprobe -p x -k modules

# Immutable
-e 2
AUDITRULES

systemctl enable --now auditd
augenrules --load 2>/dev/null || service auditd restart
success "Audit daemon configured"

# ─────────────────────────────────────────────────────────────────────────────
# 12. ROOTKIT DETECTION
# ─────────────────────────────────────────────────────────────────────────────
section "12. Rootkit Detection (rkhunter + chkrootkit)"

rkhunter --update  --nocolors 2>/dev/null || true
rkhunter --propupd --nocolors 2>/dev/null || true

cat > /etc/cron.daily/rkhunter-scan << 'CRON'
#!/bin/bash
/usr/bin/rkhunter --check --skip-keypress --report-warnings-only \
  --logfile /var/log/rkhunter.log --nocolors 2>&1 \
  | mail -s "rkhunter report - $(hostname) - $(date +%F)" root
CRON
chmod +x /etc/cron.daily/rkhunter-scan

cat > /etc/cron.weekly/chkrootkit-scan << 'CRON'
#!/bin/bash
/usr/sbin/chkrootkit 2>&1 | mail -s "chkrootkit - $(hostname) - $(date +%F)" root
CRON
chmod +x /etc/cron.weekly/chkrootkit-scan

success "Rootkit scanners scheduled"

# ─────────────────────────────────────────────────────────────────────────────
# 13. AIDE — FILE INTEGRITY MONITORING
# ─────────────────────────────────────────────────────────────────────────────
section "13. AIDE File Integrity Monitoring"

info "Initializing AIDE database (this may take 2-5 minutes)..."
aideinit --yes 2>/dev/null || aide --init 2>/dev/null || true
mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db 2>/dev/null || true

cat > /etc/cron.daily/aide-check << 'CRON'
#!/bin/bash
/usr/bin/aide --check 2>&1 | mail -s "AIDE integrity check - $(hostname) - $(date +%F)" root
CRON
chmod +x /etc/cron.daily/aide-check

success "AIDE file integrity monitoring configured"

# ─────────────────────────────────────────────────────────────────────────────
# 14. PSAD — PORT SCAN DETECTION
# ─────────────────────────────────────────────────────────────────────────────
section "14. PSAD Port Scan Attack Detection"

backup_file /etc/psad/psad.conf

iptables  -A INPUT   -j LOG --log-prefix "iptables-input: "   2>/dev/null || true
iptables  -A FORWARD -j LOG --log-prefix "iptables-forward: " 2>/dev/null || true
ip6tables -A INPUT   -j LOG --log-prefix "ip6tables-input: "  2>/dev/null || true

sed -i "s/^EMAIL_ADDRESSES.*/EMAIL_ADDRESSES         ${ADMIN_EMAIL};/" /etc/psad/psad.conf
sed -i 's/^ENABLE_AUTO_IDS.*/ENABLE_AUTO_IDS         Y;/'              /etc/psad/psad.conf
sed -i 's/^AUTO_IDS_DANGER_LEVEL.*/AUTO_IDS_DANGER_LEVEL   3;/'        /etc/psad/psad.conf

psad --sig-update 2>/dev/null || true
systemctl enable --now psad
success "PSAD port scan detection enabled"

# ─────────────────────────────────────────────────────────────────────────────
# 15. LOGWATCH — LOG ANALYSIS REPORTS
# ─────────────────────────────────────────────────────────────────────────────
section "15. Logwatch Daily Reports"

cat > /etc/logwatch/conf/logwatch.conf << EOF
Output = mail
Format = html
MailTo = ${ADMIN_EMAIL}
MailFrom = logwatch@$(hostname -f)
Detail = Med
Service = All
Range = Yesterday
EOF

cat > /etc/cron.daily/logwatch-report << 'CRON'
#!/bin/bash
/usr/sbin/logwatch --output mail
CRON
chmod +x /etc/cron.daily/logwatch-report

success "Logwatch configured"

# ─────────────────────────────────────────────────────────────────────────────
# 16. CORE DUMPS & SECURE SHARED MEMORY
# ─────────────────────────────────────────────────────────────────────────────
section "16. Core Dumps & Shared Memory"

cat > /etc/security/limits.d/99-no-core.conf << 'LIMITS'
*    hard    core    0
*    soft    core    0
root hard    core    0
root soft    core    0
LIMITS

if ! grep -q '/run/shm' /etc/fstab; then
  echo "tmpfs /run/shm tmpfs defaults,noexec,nosuid,nodev 0 0" >> /etc/fstab
fi

if ! grep -q 'tmpfs /tmp' /etc/fstab; then
  echo "tmpfs /tmp tmpfs defaults,noexec,nosuid,nodev,size=512M 0 0" >> /etc/fstab
fi

success "Core dumps disabled, shared memory secured"

# ─────────────────────────────────────────────────────────────────────────────
# 17. LYNIS BASELINE AUDIT
# ─────────────────────────────────────────────────────────────────────────────
section "17. Lynis Security Audit (Baseline)"

lynis audit system --quiet --no-colors --logfile /var/log/lynis.log 2>/dev/null || true
info "Lynis audit saved to /var/log/lynis.log"

# ─────────────────────────────────────────────────────────────────────────────
# 18. MOTD — Warning Banner
# ─────────────────────────────────────────────────────────────────────────────
section "18. Login Warning Banner"

cat > /etc/motd << 'MOTD'

  ╔═══════════════════════════════════════════════════════════════╗
  ║           AUTHORIZED USERS ONLY — ALL ACTIVITY LOGGED         ║
  ║     Unauthorized access is prohibited and will be prosecuted  ║
  ╚═══════════════════════════════════════════════════════════════╝

MOTD

cat > /etc/issue.net << 'ISSUE'
AUTHORIZED ACCESS ONLY — All activity is monitored and logged.
Unauthorized access is a criminal offense.
ISSUE

success "Warning banners set"

# ─────────────────────────────────────────────────────────────────────────────
# 19. FINAL STATUS
# ─────────────────────────────────────────────────────────────────────────────
section "19. Final Status"

echo ""
echo -e "${BLD}${GRN}╔══════════════════════════════════════════════════════════════╗"
echo "║             SECURITY HARDENING COMPLETE ✓                   ║"
echo -e "╚══════════════════════════════════════════════════════════════╝${RST}"
echo ""
echo -e "  ${GRN}✓${RST} UFW Firewall       — Ports open: SSH(${SSH_PORT}), AnyDesk(${ANYDESK_PORT}), Web(${WEB_PORTS[*]})"
echo -e "  ${GRN}✓${RST} Fail2ban           — SSH brute-force & web protection"
echo -e "  ${GRN}✓${RST} SSH                — Root login disabled, hardened ciphers"
echo -e "  ${GRN}✓${RST} Kernel sysctl      — ASLR, SYN cookies, anti-spoof"
echo -e "  ${GRN}✓${RST} AppArmor           — Mandatory access control"
echo -e "  ${GRN}✓${RST} Auditd             — Filesystem & syscall auditing"
echo -e "  ${GRN}✓${RST} rkhunter/chkrootkit — Daily rootkit scans"
echo -e "  ${GRN}✓${RST} AIDE               — File integrity monitoring"
echo -e "  ${GRN}✓${RST} PSAD               — Port scan detection"
echo -e "  ${GRN}✓${RST} Unattended-upgrades — Auto security patches"
echo -e "  ${GRN}✓${RST} Logwatch           — Daily log reports"
echo -e "  ${GRN}✓${RST} Password policy    — 14-char min, 90-day expiry"
echo ""
echo -e "${YLW}⚠ POST-INSTALL ACTIONS:${RST}"
echo "  1. Edit ADMIN_EMAIL in the script before running (currently: ${ADMIN_EMAIL})"
echo "  2. Add your SSH public key (ADMIN_SSH_PUBKEY) then set PasswordAuthentication no"
echo "  3. Review Lynis: sudo grep -E 'Warning|Suggestion' /var/log/lynis.log"
echo "  4. Enable Livepatch: sudo pro enable livepatch"
echo "  5. Reboot to apply all changes: sudo reboot"
echo ""
echo -e "${BLU}Remote access preserved:${RST} AnyDesk on port ${ANYDESK_PORT} is open in firewall."
echo ""
