#!/bin/bash
# ==============================================================================
# Script: agent.sh
# Description: Lightweight infrastructure telemetry agent for Linux systems.
# Author: Angel (DevOps / Infrastructure Engineer)
# Supervised by: Systemd (infra-agent.service)
# ==============================================================================

set -euo pipefail

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    LOAD=$(cat /proc/loadavg | awk '{print $1}')
    MEM_FREE=$(free -m | awk '/Mem:/ {print $4}')
    echo "[$TIMESTAMP] INFRA-AGENT HEALTH: CPU Load 1m: $LOAD | Free RAM: ${MEM_FREE}MB"
    sleep 5
done
