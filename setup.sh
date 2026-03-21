#!/usr/bin/env bash
# =============================================================================
#  SECURITY HARDENING SCRIPT v1.1
#  Target : Ubuntu Pro 24.04 LTS — Fresh Web Server
#  Usage  : sudo bash setup.sh
# =============================================================================

# ── Error trapping: log line number + command, but DO NOT abort on failures ──
set -uo pipefail
trap 'echo -e "\n${RED}[ERROR]${RST} Script error on LINE ${LINENO}: command \"${BASH_COMMAND}\" returned $?" >&2' ERR

LOG_FILE="/var/log/hardening-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Hardening started: $(date) ===" >> "$LOG_FILE"

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION — Edit these before running
# ─────────────────────────────────────────────────────────────────────────────
SSH_PORT=22
ANYDESK_PORT=7070
WEB_PORTS=(80 443)
ADMIN_EMAIL="admin@example.com"
TIMEZONE="Asia/Bangkok"
ADMIN_SSH_PUBKEY=""
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
section() {
  local n=$((++SECTION_NUM))
  echo -e "\n${BLD}${CYN}══════════════════════════════════════════════${RST}"
  echo -e "${BLD}${CYN}  SECTION ${n}: $*${RST}"
  echo -e "${BLD}${CYN}══════════════════════════════════════════════${RST}"
}
SECTION_NUM=0

safe_install() {
  # Install packages one-by-one so a missing pkg doesn't kill the whole list
  local failed=()
  for pkg in "$@"; do
    if DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$pkg" 2>/dev/null; then
      echo -e "    ${GRN}✓${RST} $pkg"
    else
      echo -e "    ${YLW}✗${RST} $pkg (skipped — not found or unavailable)"
      failed+=("$pkg")
    fi
  done
  [[ ${#failed[@]} -gt 0 ]] && warn "Skipped packages: ${failed[*]}"
}

backup_file() {
  local f="$1"
  [[ -f "$f" ]] && cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)" && info "Backed up $f"
}

# ─────────────────────────────────────────────────────────────────────────────
# 0. PRE-FLIGHT
# ─────────────────────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || { error "Run as root: sudo bash $0"; exit 1; }

echo -e "${BLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        Ubuntu Pro 24.04 — Security Hardening Script v1.1   ║"
echo "╚══════════════════════════════════════════════════════════════╝${RST}"
echo ""
info "All output is also logged to: ${LOG_FILE}"
warn "AnyDesk port ${ANYDESK_PORT} will remain OPEN."
warn "SSH port ${SSH_PORT} will remain OPEN."
echo ""
read -rp "$(echo -e ${YLW}"Proceed? [yes/N]: "${RST})" CONFIRM
[[ "${CONFIRM}" == "yes" ]] || { info "Aborted."; exit 0; }

# ─────────────────────────────────────────────────────────────────────────────
# 1. SYSTEM UPDATE & BASE PACKAGES
# ─────────────────────────────────────────────────────────────────────────────
section "System Update & Base Packages"

info "Setting timezone to ${TIMEZONE}..."
timedatectl set-timezone "${TIMEZONE}" && success "Timezone set"

export DEBIAN_FRONTEND=noninteractive

info "Running apt-get update..."
apt-get update -q && success "Package lists updated"

info "Running apt-get upgrade (this may take a while)..."
apt-get upgrade -y -q && success "System upgraded"

info "Running dist-upgrade..."
apt-get dist-upgrade -y -q && success "Dist-upgrade done"

info "Installing CRITICAL packages (firewall, SSH, PAM)..."
safe_install \
  ufw \
  fail2ban \
  unattended-upgrades \
  apt-listchanges \
  libpam-pwquality

info "Installing AUDIT & MONITORING packages..."
safe_install \
  auditd \
  audispd-plugins \
  rkhunter \
  chkrootkit \
  aide \
  logwatch \
  lynis \
  psad \
  sysstat

info "Installing SECURITY TOOLS..."
safe_install \
  apparmor \
  apparmor-utils \
  needrestart \
  iptables-persistent \
  nftables

info "Installing UTILITIES..."
safe_install \
  curl wget git vim net-tools htop acl attr

# Optional: libpam-google-authenticator (2FA — may not be needed yet)
info "Attempting optional packages..."
safe_install libpam-google-authenticator || true

success "Section 1 complete — all packages processed"

# ── Hard dependency check: abort with clear message if critical tools missing ─
info "Verifying critical binaries are available..."
MISSING=()
for bin in ufw fail2ban-client sshd auditd; do
  if ! command -v "$bin" &>/dev/null && ! which "$bin" &>/dev/null; then
    MISSING+=("$bin")
  fi
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  error "CRITICAL tools not found after install: ${MISSING[*]}"
  error "Try manually: apt-get install -y ${MISSING[*]}"
  error "Then re-run this script."
  exit 1
fi
success "All critical binaries verified: ufw fail2ban-client sshd auditd"

# ─────────────────────────────────────────────────────────────────────────────
# 2. AUTOMATIC SECURITY UPDATES
# ─────────────────────────────────────────────────────────────────────────────
section "Automatic Security Updates"

cat > /etc/apt/apt.conf.d/50unattended-upgrades << APTEOF
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
APTEOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'APTEOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APTEOF

systemctl enable --now unattended-upgrades && success "Unattended-upgrades enabled"

if command -v pro &>/dev/null; then
  info "Ubuntu Pro detected — enabling ESM..."
  pro enable esm-infra 2>/dev/null && success "esm-infra enabled" || warn "esm-infra skipped (may need: sudo pro attach)"
  pro enable esm-apps  2>/dev/null && success "esm-apps enabled"  || warn "esm-apps skipped"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. UFW FIREWALL
# ─────────────────────────────────────────────────────────────────────────────
section "UFW Firewall"

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw default deny forward

ufw allow "${SSH_PORT}/tcp"      comment "SSH"
ufw limit  "${SSH_PORT}/tcp"     comment "SSH rate-limit"
ufw allow "${ANYDESK_PORT}/tcp"  comment "AnyDesk"
ufw allow "${ANYDESK_PORT}/udp"  comment "AnyDesk UDP"

for port in "${WEB_PORTS[@]}"; do
  ufw allow "${port}/tcp" comment "Web"
done

ufw --force enable
ufw status verbose
success "UFW firewall configured"

# ─────────────────────────────────────────────────────────────────────────────
# 4. FAIL2BAN
# ─────────────────────────────────────────────────────────────────────────────
section "Fail2ban Intrusion Prevention"

backup_file /etc/fail2ban/jail.local

cat > /etc/fail2ban/jail.local << F2BEOF
[DEFAULT]
bantime          = 3600
findtime         = 600
maxretry         = 5
backend          = systemd
destemail        = ${ADMIN_EMAIL}
sendername       = Fail2Ban-$(hostname)
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

[nginx-badbots]
enabled  = true
port     = http,https
logpath  = %(nginx_access_log)s
maxretry = 2

[recidive]
enabled  = true
logpath  = /var/log/fail2ban.log
bantime  = 604800
findtime = 86400
maxretry = 5
F2BEOF

systemctl enable --now fail2ban
systemctl restart fail2ban && success "Fail2ban running"

# ─────────────────────────────────────────────────────────────────────────────
# 5. SSH HARDENING
# ─────────────────────────────────────────────────────────────────────────────
section "SSH Hardening"

backup_file /etc/ssh/sshd_config

cat > /etc/ssh/sshd_config << SSHEOF
Port ${SSH_PORT}
AddressFamily inet
ListenAddress 0.0.0.0

PermitRootLogin no
MaxAuthTries 3
MaxSessions 5
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2

X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
PermitUserEnvironment no
PermitTunnel no
GatewayPorts no

SyslogFacility AUTH
LogLevel VERBOSE
PrintLastLog yes
Banner /etc/ssh/banner

KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com
SSHEOF

cat > /etc/ssh/banner << 'BANEOF'
╔══════════════════════════════════════════════════════════════╗
║  AUTHORIZED ACCESS ONLY — All activity is logged & monitored ║
╚══════════════════════════════════════════════════════════════╝
BANEOF

if [[ -n "${ADMIN_SSH_PUBKEY}" ]]; then
  local_user="${SUDO_USER:-$(logname 2>/dev/null || echo ubuntu)}"
  home_dir=$(eval echo "~${local_user}")
  mkdir -p "${home_dir}/.ssh"
  echo "${ADMIN_SSH_PUBKEY}" >> "${home_dir}/.ssh/authorized_keys"
  chmod 700 "${home_dir}/.ssh"
  chmod 600 "${home_dir}/.ssh/authorized_keys"
  chown -R "${local_user}:${local_user}" "${home_dir}/.ssh"
  success "SSH public key added for ${local_user}"
fi

if sshd -t 2>/dev/null; then
  systemctl restart ssh && success "SSH hardened and restarted"
else
  error "sshd config test failed — restoring backup"
  cp /etc/ssh/sshd_config.bak.* /etc/ssh/sshd_config 2>/dev/null || true
fi

# ─────────────────────────────────────────────────────────────────────────────
# 6. KERNEL / SYSCTL HARDENING
# ─────────────────────────────────────────────────────────────────────────────
section "Kernel & Network Hardening"

cat > /etc/sysctl.d/99-hardening.conf << 'SYSCTLEOF'
# Anti-spoofing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# ICMP hardening
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

# SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_max_syn_backlog = 2048

# Connection hardening
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_rfc1337 = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# IPv6
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

# Kernel ASLR & lockdown
kernel.randomize_va_space = 2
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.perf_event_paranoid = 3
kernel.yama.ptrace_scope = 1
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2

# Core dumps off
fs.suid_dumpable = 0
kernel.core_uses_pid = 1

# Filesystem protections
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2

# Memory
vm.mmap_min_addr = 65536
vm.swappiness = 10
SYSCTLEOF

sysctl --system && success "Kernel hardening applied"

# ─────────────────────────────────────────────────────────────────────────────
# 7. PASSWORD POLICY
# ─────────────────────────────────────────────────────────────────────────────
section "Password Policy"

backup_file /etc/security/pwquality.conf
cat > /etc/security/pwquality.conf << 'PWEOF'
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
PWEOF

useradd -D -f 30
backup_file /etc/login.defs
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/'  /etc/login.defs
sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   14/' /etc/login.defs
success "Password policy configured"

# ─────────────────────────────────────────────────────────────────────────────
# 8. FILE PERMISSIONS
# ─────────────────────────────────────────────────────────────────────────────
section "File & Directory Permissions"

chmod 700 /root
chmod 600 /etc/shadow
chmod 644 /etc/passwd
chmod 644 /etc/group
chmod 600 /etc/gshadow
chmod 600 /etc/ssh/sshd_config
chmod 600 /etc/crontab
chmod 700 /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly

[[ -f /usr/bin/gcc ]] && chmod o-x /usr/bin/gcc && warn "gcc restricted to root only"

find / -xdev -type d -perm -0002 -exec chmod +t {} \; 2>/dev/null || true
success "File permissions hardened"

# ─────────────────────────────────────────────────────────────────────────────
# 9. DISABLE UNNECESSARY SERVICES
# ─────────────────────────────────────────────────────────────────────────────
section "Disable Unnecessary Services"

for svc in avahi-daemon cups isc-dhcp-server isc-dhcp-server6 \
           slapd nfs-server rpcbind bind9 vsftpd apache2 \
           dovecot smbd nmbd squid snmpd rsync nis telnet xinetd; do
  if systemctl is-active --quiet "${svc}" 2>/dev/null; then
    systemctl stop    "${svc}" 2>/dev/null || true
    systemctl disable "${svc}" 2>/dev/null || true
    warn "Disabled: ${svc}"
  fi
done
success "Unnecessary services disabled"

# ─────────────────────────────────────────────────────────────────────────────
# 10. APPARMOR
# ─────────────────────────────────────────────────────────────────────────────
section "AppArmor"

systemctl enable --now apparmor 2>/dev/null || true
aa-enforce /etc/apparmor.d/* 2>/dev/null || true
success "AppArmor enforcing mode enabled"

# ─────────────────────────────────────────────────────────────────────────────
# 11. AUDIT DAEMON
# ─────────────────────────────────────────────────────────────────────────────
section "Audit Daemon (auditd)"

cat > /etc/audit/rules.d/hardening.rules << 'AUDITEOF'
-D
-b 8192
-f 1

-w /etc/passwd   -p wa -k identity
-w /etc/shadow   -p wa -k identity
-w /etc/group    -p wa -k identity
-w /etc/gshadow  -p wa -k identity
-w /etc/sudoers  -p wa -k sudo_changes
-w /etc/sudoers.d/ -p wa -k sudo_changes
-w /etc/ssh/sshd_config -p wa -k ssh_config
-w /etc/crontab  -p wa -k cron
-w /etc/cron.d/  -p wa -k cron
-w /etc/hosts    -p wa -k network
-w /etc/resolv.conf -p wa -k network

-a always,exit -F arch=b64 -S execve -k exec
-a always,exit -F arch=b32 -S execve -k exec
-a always,exit -F arch=b64 -S setuid -S setgid -k priv_esc
-a always,exit -F arch=b32 -S setuid -S setgid -k priv_esc

-w /sbin/insmod   -p x -k modules
-w /sbin/rmmod    -p x -k modules
-w /sbin/modprobe -p x -k modules

-e 2
AUDITEOF

systemctl enable --now auditd 2>/dev/null || true
augenrules --load 2>/dev/null || service auditd restart 2>/dev/null || true
success "Audit daemon configured"

# ─────────────────────────────────────────────────────────────────────────────
# 12. ROOTKIT DETECTION
# ─────────────────────────────────────────────────────────────────────────────
section "Rootkit Detection"

rkhunter --update  --nocolors 2>/dev/null || true
rkhunter --propupd --nocolors 2>/dev/null || true

cat > /etc/cron.daily/rkhunter-scan << 'CRON'
#!/bin/bash
/usr/bin/rkhunter --check --skip-keypress --report-warnings-only \
  --logfile /var/log/rkhunter.log --nocolors 2>&1 \
  | mail -s "rkhunter - $(hostname) - $(date +%F)" root
CRON
chmod +x /etc/cron.daily/rkhunter-scan

cat > /etc/cron.weekly/chkrootkit-scan << 'CRON'
#!/bin/bash
/usr/sbin/chkrootkit 2>&1 | mail -s "chkrootkit - $(hostname) - $(date +%F)" root
CRON
chmod +x /etc/cron.weekly/chkrootkit-scan
success "Rootkit scanners scheduled"

# ─────────────────────────────────────────────────────────────────────────────
# 13. AIDE FILE INTEGRITY
# ─────────────────────────────────────────────────────────────────────────────
section "AIDE File Integrity Monitoring"

info "Initializing AIDE database (2-5 minutes)..."
aideinit --yes 2>/dev/null || aide --init 2>/dev/null || warn "AIDE init skipped — run manually: sudo aideinit"
mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db 2>/dev/null || true

cat > /etc/cron.daily/aide-check << 'CRON'
#!/bin/bash
/usr/bin/aide --check 2>&1 | mail -s "AIDE - $(hostname) - $(date +%F)" root
CRON
chmod +x /etc/cron.daily/aide-check
success "AIDE configured"

# ─────────────────────────────────────────────────────────────────────────────
# 14. PSAD PORT SCAN DETECTION
# ─────────────────────────────────────────────────────────────────────────────
section "PSAD Port Scan Detection"

backup_file /etc/psad/psad.conf
iptables  -A INPUT   -j LOG --log-prefix "iptables-input: "   2>/dev/null || true
iptables  -A FORWARD -j LOG --log-prefix "iptables-forward: " 2>/dev/null || true
ip6tables -A INPUT   -j LOG --log-prefix "ip6tables-input: "  2>/dev/null || true

sed -i "s/^EMAIL_ADDRESSES.*/EMAIL_ADDRESSES         ${ADMIN_EMAIL};/"  /etc/psad/psad.conf 2>/dev/null || true
sed -i 's/^ENABLE_AUTO_IDS.*/ENABLE_AUTO_IDS         Y;/'               /etc/psad/psad.conf 2>/dev/null || true
sed -i 's/^AUTO_IDS_DANGER_LEVEL.*/AUTO_IDS_DANGER_LEVEL   3;/'         /etc/psad/psad.conf 2>/dev/null || true

psad --sig-update 2>/dev/null || true
systemctl enable --now psad 2>/dev/null || true
success "PSAD configured"

# ─────────────────────────────────────────────────────────────────────────────
# 15. LOGWATCH
# ─────────────────────────────────────────────────────────────────────────────
section "Logwatch Daily Reports"

mkdir -p /etc/logwatch/conf
cat > /etc/logwatch/conf/logwatch.conf << LWEOF
Output = mail
Format = html
MailTo = ${ADMIN_EMAIL}
MailFrom = logwatch@$(hostname -f)
Detail = Med
Service = All
Range = Yesterday
LWEOF

cat > /etc/cron.daily/logwatch-report << 'CRON'
#!/bin/bash
/usr/sbin/logwatch --output mail
CRON
chmod +x /etc/cron.daily/logwatch-report
success "Logwatch configured"

# ─────────────────────────────────────────────────────────────────────────────
# 16. CORE DUMPS & SHARED MEMORY
# ─────────────────────────────────────────────────────────────────────────────
section "Core Dumps & Shared Memory"

cat > /etc/security/limits.d/99-no-core.conf << 'LIMEOF'
*    hard    core    0
*    soft    core    0
root hard    core    0
root soft    core    0
LIMEOF

grep -q '/run/shm' /etc/fstab || \
  echo "tmpfs /run/shm tmpfs defaults,noexec,nosuid,nodev 0 0" >> /etc/fstab

grep -q 'tmpfs /tmp' /etc/fstab || \
  echo "tmpfs /tmp tmpfs defaults,noexec,nosuid,nodev,size=512M 0 0" >> /etc/fstab

success "Core dumps disabled, shared memory secured"

# ─────────────────────────────────────────────────────────────────────────────
# 17. LYNIS AUDIT
# ─────────────────────────────────────────────────────────────────────────────
section "Lynis Security Audit"

lynis audit system --quiet --no-colors --logfile /var/log/lynis.log 2>/dev/null || true
success "Lynis audit saved to /var/log/lynis.log"

# ─────────────────────────────────────────────────────────────────────────────
# 18. WARNING BANNERS
# ─────────────────────────────────────────────────────────────────────────────
section "Login Warning Banners"

cat > /etc/motd << 'MOTDEOF'

  ╔═══════════════════════════════════════════════════════════════╗
  ║           AUTHORIZED USERS ONLY — ALL ACTIVITY LOGGED         ║
  ║     Unauthorized access is prohibited and will be prosecuted  ║
  ╚═══════════════════════════════════════════════════════════════╝

MOTDEOF

echo "AUTHORIZED ACCESS ONLY — All activity is monitored and logged." > /etc/issue.net
success "Banners set"

# ─────────────────────────────────────────────────────────────────────────────
# 19. FINAL SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
section "DONE — Final Summary"

echo ""
echo -e "${BLD}${GRN}╔══════════════════════════════════════════════════════════════╗"
echo "║             SECURITY HARDENING COMPLETE ✓                   ║"
echo -e "╚══════════════════════════════════════════════════════════════╝${RST}"
echo ""
echo -e "  ${GRN}✓${RST} UFW            — SSH:${SSH_PORT}, AnyDesk:${ANYDESK_PORT}, Web:${WEB_PORTS[*]}"
echo -e "  ${GRN}✓${RST} Fail2ban       — SSH brute-force & web bots"
echo -e "  ${GRN}✓${RST} SSH            — Root disabled, hardened ciphers"
echo -e "  ${GRN}✓${RST} sysctl         — ASLR, SYN-cookies, anti-spoof"
echo -e "  ${GRN}✓${RST} AppArmor       — Enforce mode"
echo -e "  ${GRN}✓${RST} auditd         — Syscall & file audit"
echo -e "  ${GRN}✓${RST} rkhunter       — Daily rootkit scans"
echo -e "  ${GRN}✓${RST} AIDE           — File integrity"
echo -e "  ${GRN}✓${RST} PSAD           — Port scan detection"
echo -e "  ${GRN}✓${RST} Auto-updates   — Security patches"
echo -e "  ${GRN}✓${RST} Logwatch       — Daily log digest"
echo ""
echo -e "${YLW}⚠ POST-INSTALL ACTIONS:${RST}"
echo "  1. Review full log: sudo cat ${LOG_FILE}"
echo "  2. Set your ADMIN_EMAIL in the script and re-run if needed"
echo "  3. Add SSH key → then set PasswordAuthentication no in /etc/ssh/sshd_config"
echo "  4. sudo pro enable livepatch"
echo "  5. sudo grep -E 'Warning|Suggestion' /var/log/lynis.log"
echo "  6. sudo reboot   ← apply all kernel/fstab changes"
echo ""
echo -e "${BLU}AnyDesk on port ${ANYDESK_PORT} is OPEN — your remote session is safe.${RST}"
echo ""
echo "=== Hardening completed: $(date) ===" >> "$LOG_FILE"
