
#!/usr/bin/env bash
#
# system_health_monitor.sh
# Simple Linux system health monitor (Bash)
# Checks: CPU, Memory, Disk, and configured processes
# Logs to /var/log/system_health.log (change if needed)
#
# Exit codes:
#   0 = OK (all checks below thresholds)
#   1 = WARNING (one or more metrics exceeded thresholds)
#   2 = CRITICAL / script error

########################
# Configuration section
########################
LOGFILE="/var/log/system_health.log"       # where to append alerts (must be writable)
CPU_THRESHOLD=20      
MEM_THRESHOLD=20      
DISK_THRESHOLD=20      

WATCH_PROCESSES=("sshd" "nginx")

MAIL_TO=""  
MAIL_SUBJECT="System Health Alert on $(hostname)"
########################
# End configuration
########################

touch "$LOGFILE" 2>/dev/null || { echo "Cannot write to $LOGFILE. Run as root or change LOGFILE." ; exit 2; }

timestamp() { date +"%Y-%m-%d %H:%M:%S"; }

log() {
  local level="$1"; shift
  echo "$(timestamp) [$level] $*" | tee -a "$LOGFILE"
}

send_mail() {
  local body="$1"
  if [[ -n "$MAIL_TO" ]]; then
    if command -v mail >/dev/null 2>&1; then
      echo -e "$body" | mail -s "$MAIL_SUBJECT" "$MAIL_TO"
    elif command -v mailx >/dev/null 2>&1; then
      echo -e "$body" | mailx -s "$MAIL_SUBJECT" "$MAIL_TO"
    else
      log "WARN" "Mail tool not found (mail/mailx). Skipping email alert."
    fi
  fi
}

########################
# Helper: CPU usage using /proc/stat
# returns integer percent CPU used (0-100)
########################
get_cpu_usage() {
  read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
  prev_total=$((user + nice + system + idle + iowait + irq + softirq + steal))
  prev_idle=$((idle + iowait))
  sleep 1
  read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
  total=$((user + nice + system + idle + iowait + irq + softirq + steal))
  idle_now=$((idle + iowait))
  total_diff=$((total - prev_total))
  idle_diff=$((idle_now - prev_idle))
  if (( total_diff == 0 )); then
    echo 0
    return
  fi
  used=$((total_diff - idle_diff))
  cpu_pct=$(( (used * 100) / total_diff ))
  echo "$cpu_pct"
}

########################
# Helper: Memory usage percentage
# returns integer percent memory used
########################
get_mem_usage() {
  if free_out=$(free -m); then
    total=$(echo "$free_out" | awk '/^Mem:/ {print $2}')
    if awk '/^Mem:/ {print $7}' <<<"$free_out" >/dev/null 2>&1; then
      avail=$(echo "$free_out" | awk '/^Mem:/ {print $7}')
    else
      free_=$(echo "$free_out" | awk '/^Mem:/ {print $4}')
      buffers=$(echo "$free_out" | awk '/^Mem:/ {print $6}')
      cached=$(echo "$free_out" | awk '/^Mem:/ {print $7}')
      avail=$((free_ + buffers + cached))
    fi
    used=$(( total - avail ))
    if (( total == 0 )); then
      echo 0
    else
      mem_pct=$(( (used * 100) / total ))
      echo "$mem_pct"
    fi
  else
    echo 0
  fi
}

########################
# Helper: check disk usage for all mounted filesystems
# If any usage >= DISK_THRESHOLD, prints the offending lines
# returns 0 if all below threshold; 1 if any above
########################
check_disk_usage() {
  local threshold=$1
  df -P -x tmpfs -x devtmpfs | awk -v thr="$threshold" 'NR>1 {
    # $5 is Use% like "12%"
    gsub("%","",$5)
    if ($5+0 >= thr) {
      print $0
    }
  }'
}

########################
# Helper: check processes
# returns non-empty list of missing process names
########################
check_processes() {
  local missing=()
  for p in "${WATCH_PROCESSES[@]}"; do
    if ! pgrep -f "$p" >/dev/null 2>&1; then
      missing+=("$p")
    fi
  done
  if (( ${#missing[@]} == 0 )); then
    return 0
  else
    for m in "${missing[@]}"; do echo "$m"; done
    return 1
  fi
}

########################
# Main checks
########################
STATUS=0
ALERT_MESSAGES=()

# CPU
cpu_used=$(get_cpu_usage)
if (( cpu_used >= CPU_THRESHOLD )); then
  STATUS=1
  ALERT_MESSAGES+=("High CPU usage: ${cpu_used}% (threshold ${CPU_THRESHOLD}%)")
  log "WARN" "High CPU usage: ${cpu_used}% (threshold ${CPU_THRESHOLD}%)"
else
  log "INFO" "CPU usage: ${cpu_used}%"
fi

# Memory
mem_used=$(get_mem_usage)
if (( mem_used >= MEM_THRESHOLD )); then
  STATUS=1
  ALERT_MESSAGES+=("High Memory usage: ${mem_used}% (threshold ${MEM_THRESHOLD}%)")
  log "WARN" "High Memory usage: ${mem_used}% (threshold ${MEM_THRESHOLD}%)"
else
  log "INFO" "Memory usage: ${mem_used}%"
fi

# Disk
disk_issues=$(check_disk_usage "$DISK_THRESHOLD")
if [[ -n "$disk_issues" ]]; then
  STATUS=1
  ALERT_MESSAGES+=("Disk usage exceeded threshold (${DISK_THRESHOLD}%):\n$disk_issues")
  log "WARN" "Disk usage issues found (>= ${DISK_THRESHOLD}%):"
  while IFS= read -r line; do log "WARN" "$line"; done <<<"$disk_issues"
else
  log "INFO" "Disk usage: all filesystems below ${DISK_THRESHOLD}%"
fi

# Processes
missing_procs=$(check_processes)
if [[ -n "$missing_procs" ]]; then
  STATUS=1
  msg="Missing processes: $(echo "$missing_procs" | tr '\n' ',' | sed 's/,$//')"
  ALERT_MESSAGES+=("$msg")
  log "WARN" "$msg"
else
  log "INFO" "All monitored processes are running: ${WATCH_PROCESSES[*]}"
fi

# Final report / alert
if (( STATUS == 0 )); then
  log "OK" "System health OK."
  exit 0
else
  body="$(hostname) - System health alert at $(timestamp)\n\n"
  for m in "${ALERT_MESSAGES[@]}"; do
    body+="$m\n\n"
  done
  body+="--- End of alert ---\n"
  send_mail "$body"
  log "ALERT" "Sent alert. (MAIL_TO=${MAIL_TO:-disabled})"
  exit 1
fi
