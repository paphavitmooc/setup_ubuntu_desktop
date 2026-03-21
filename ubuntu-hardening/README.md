# Ubuntu 24.04 LTS — Security Hardening Suite
> Web server + AnyDesk remote access + desktop GUI friendly

## Files

| Script | Purpose |
|--------|---------|
| `00_run_all.sh` | Master runner — executes all scripts in order |
| `01_system_update.sh` | Full upgrade + unattended security updates |
| `02_ufw_firewall.sh` | UFW firewall — SSH/HTTP/HTTPS + AnyDesk :7070 |
| `03_ssh_hardening.sh` | Harden OpenSSH |
| `04_fail2ban.sh` | Brute-force protection — SSH + Nginx + port scan |
| `05_kernel_hardening.sh` | sysctl hardening + dangerous module blacklist |
| `06_apparmor_audit.sh` | AppArmor — daemons enforced, desktop apps in complain |
| `07_intrusion_detection.sh` | AIDE + rkhunter + chkrootkit |
| `08_log_monitoring.sh` | Logwatch + journald + append-only logs |
| `09_web_server_security.sh` | Nginx security headers + rate limiting |
| `10_final_audit.sh` | Lynis audit + full security report |
| `11_new_app_helper.sh` | **Run this when a new app does not work** |

## Quick Start

```bash
sudo chmod +x *.sh
sudo bash 00_run_all.sh
```

## When a new app does not work after install

```bash
sudo bash 11_new_app_helper.sh appname

# Examples:
sudo bash 11_new_app_helper.sh zoom
sudo bash 11_new_app_helper.sh docker
sudo bash 11_new_app_helper.sh anydesk
```

Or relax AppArmor for any app directly:
```bash
sudo apparmor-relax appname
```

## Install a .deb file correctly

```bash
sudo chmod 644 ~/Downloads/appname.deb
sudo dpkg -i ~/Downloads/appname.deb
sudo apt-get install -f
```

## Open a port for a new app

```bash
sudo ufw allow 8096/tcp comment 'Jellyfin'
sudo ufw allow 3000/tcp comment 'My app'
sudo ufw status
```

## Ports open by default

| Port | Protocol | Service |
|------|----------|---------|
| 22 | TCP | SSH (rate-limited) |
| 80 | TCP | HTTP |
| 443 | TCP | HTTPS |
| 7070 | TCP+UDP | AnyDesk |

## AppArmor mode explained

| Mode | Meaning |
|------|---------|
| enforce | Actively blocks forbidden actions — used for system daemons |
| complain | Logs but never blocks — used for all desktop/GUI apps |

## After running — checklist
- [ ] Add SSH key: `ssh-copy-id user@server`
- [ ] Disable password SSH: set `PasswordAuthentication no` in `/etc/ssh/sshd_config.d/99-hardening.conf`
- [ ] Get SSL cert: `sudo certbot --nginx -d yourdomain.com`
- [ ] Hide Postfix banner: `sudo postconf -e "smtpd_banner = \$myhostname ESMTP"`
- [ ] Monitor attacks: `sudo watch-attacks`
