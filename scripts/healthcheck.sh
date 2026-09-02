#!/bin/bash
# ==============================================================================
# Script: healthcheck.sh
# Description: Periodic healthcheck audit script executed by cron.
# Author: Angel (DevOps / Infrastructure Engineer)
# Log destination: /var/log/infra-health.log
# ==============================================================================

set -euo pipefail

LOG_FILE="/var/log/infra-health.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# 1. Gather System Metrics
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
MEM_USAGE=$(free | awk '/Mem:/ {printf("%.0f"), $3/$2 * 100}')
SVC_STATUS=$(systemctl is-active infra-agent.service || true)

# 2. Evaluate Service Health
if [ "$SVC_STATUS" != "active" ]; then
    ALERT="[CRITICAL] infra-agent.service is NOT RUNNING!"
else
    ALERT="[OK] infra-agent.service is healthy"
fi

# 3. Log Output
echo "[$TIMESTAMP] AUDIT REPORT | Disk: ${DISK_USAGE}% | RAM: ${MEM_USAGE}% | Service: $SVC_STATUS | Status: $ALERT" | tee -a "$LOG_FILE"
