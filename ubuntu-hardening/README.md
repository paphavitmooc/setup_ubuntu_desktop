# Ubuntu 24.04 LTS — Security Hardening Suite
> For: Fresh Ubuntu Pro 24.04 web server with AnyDesk (port 7070) remote access

## Files

| Script | Purpose |
|--------|---------|
| `00_run_all.sh` | **Master runner** — executes all scripts in order |
| `01_system_update.sh` | Full system upgrade + unattended security updates |
| `02_ufw_firewall.sh` | UFW firewall — allows SSH/HTTP/HTTPS + AnyDesk :7070 |
| `03_ssh_hardening.sh` | Harden OpenSSH (ciphers, auth, timeouts) |
| `04_fail2ban.sh` | Brute-force protection for SSH + Nginx |
| `05_kernel_hardening.sh` | sysctl network/kernel tuning + blacklist dangerous modules |
| `06_apparmor_audit.sh` | AppArmor enforce mode + auditd rules |
| `07_intrusion_detection.sh` | AIDE file integrity + rkhunter + chkrootkit |
| `08_log_monitoring.sh` | Logwatch + journald + append-only logs + `watch-attacks` tool |
| `09_web_server_security.sh` | Nginx security headers, rate limiting, bad-bot blocking |
| `10_final_audit.sh` | Lynis audit + full security report |

## Quick Start

```bash
# Upload this folder to your VPS, then:
sudo chmod +x *.sh
sudo bash 00_run_all.sh
```

## Ports kept open
| Port | Protocol | Service |
|------|----------|---------|
| 22 | TCP | SSH (rate-limited) |
| 80 | TCP | HTTP |
| 443 | TCP | HTTPS |
| 7070 | TCP+UDP | AnyDesk |

## After running — checklist
- [ ] Add SSH public key: `ssh-copy-id user@server`
- [ ] Disable password SSH: edit `PasswordAuthentication no` in `/etc/ssh/sshd_config.d/99-hardening.conf`
- [ ] Get free SSL cert: `sudo certbot --nginx -d yourdomain.com`
- [ ] Review Lynis report at `/root/security-audit-YYYY-MM-DD.txt`
- [ ] Monitor attacks: `sudo watch-attacks`

## What it protects against
- SSH brute force (Fail2Ban + rate-limited UFW rule)
- SYN flood / DDoS (sysctl SYN cookies + Nginx rate limiting)
- IP spoofing & ICMP Smurf attacks (rp_filter + icmp broadcast ignore)
- Rootkits (rkhunter + chkrootkit daily scan)
- File tampering (AIDE daily integrity check)
- Web attacks: XSS, clickjacking, MIME sniffing, bad bots, SQLi paths
- Kernel exploits (ASLR, ptrace restriction, module blacklist)
- Port scanning (UFW BLOCK + Fail2Ban portscan jail)
