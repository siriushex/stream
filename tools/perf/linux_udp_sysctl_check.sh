#!/usr/bin/env bash
set -euo pipefail

# Linux-only helper: shows kernel UDP/network backlog/buffer sysctl values that often
# cause softnet drops + "one core 100%" symptoms with many TS streams.
#
# IMPORTANT:
# - This script does NOT change anything by default.
# - It prints current values and a safe-ish baseline suggestion.
#
# Usage:
#   tools/perf/linux_udp_sysctl_check.sh

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "SKIP: Linux only"
  exit 0
fi

get_sysctl() {
  local key="$1"
  sysctl -n "$key" 2>/dev/null || echo "n/a"
}

echo "== Kernel net/UDP sysctl snapshot =="
echo "Tip: softnet drops -> check /proc/net/softnet_stat and IRQ/RSS (tools/perf/nic_rss_irq_check.sh)"
echo

# Reasonable baselines for typical TS workloads. Tune for your host.
declare -A SUGGESTED=(
  ["net.core.netdev_max_backlog"]="250000"
  ["net.core.rmem_max"]="33554432"
  ["net.core.wmem_max"]="33554432"
  ["net.core.rmem_default"]="262144"
  ["net.core.wmem_default"]="262144"
  ["net.ipv4.udp_rmem_min"]="16384"
  ["net.ipv4.udp_wmem_min"]="16384"
)

printf "%-28s %-12s %-12s\n" "KEY" "CURRENT" "SUGGESTED"
printf "%-28s %-12s %-12s\n" "----------------------------" "----------" "----------"
for key in "${!SUGGESTED[@]}"; do
  cur="$(get_sysctl "$key")"
  printf "%-28s %-12s %-12s\n" "$key" "$cur" "${SUGGESTED[$key]}"
done | sort

echo
echo "NOTE:"
echo "- These values are not mandatory; they are a starting point."
echo "- Increasing buffers increases RAM usage; test on staging first."

