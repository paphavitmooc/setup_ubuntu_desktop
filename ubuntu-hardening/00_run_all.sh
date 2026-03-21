#!/bin/bash
# ============================================================
# 00_run_all.sh — Ubuntu 24.04 LTS Security Hardening Suite
# Run this as root to execute all hardening steps in order.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/ubuntu-hardening.log"

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Must be run as root: sudo bash $0"
  exit 1
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

SCRIPTS=(
  "01_system_update.sh"
  "02_ufw_firewall.sh"
  "03_ssh_hardening.sh"
  "04_fail2ban.sh"
  "05_kernel_hardening.sh"
  "06_apparmor_audit.sh"
  "07_intrusion_detection.sh"
  "08_log_monitoring.sh"
  "09_web_server_security.sh"
  "10_final_audit.sh"
  "11_new_app_helper.sh"
  "12_network_stability.sh"
)

log "====== Ubuntu 24.04 Hardening Suite Started ======"

FAILED_SCRIPTS=()

for script in "${SCRIPTS[@]}"; do
  if [[ -f "$SCRIPT_DIR/$script" ]]; then
    log ">>> Running: $script"
    chmod +x "$SCRIPT_DIR/$script"
    if bash "$SCRIPT_DIR/$script" 2>&1 | tee -a "$LOG_FILE"; then
      log "<<< Done: $script"
    else
      log "[ERROR] $script failed (exit $?) — continuing with remaining scripts"
      FAILED_SCRIPTS+=("$script")
    fi
  else
    log "[WARN] Script not found: $script — skipping"
  fi
done

if [[ ${#FAILED_SCRIPTS[@]} -gt 0 ]]; then
  log "====== WARNING: ${#FAILED_SCRIPTS[@]} script(s) failed: ${FAILED_SCRIPTS[*]} ======"
  log "====== Review $LOG_FILE for details. ======"
else
  log "====== All scripts completed successfully. ======"
fi

log "====== Hardening Complete. Review: $LOG_FILE ======"
