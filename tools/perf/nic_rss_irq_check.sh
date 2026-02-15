#!/usr/bin/env bash
set -euo pipefail

IFACE="${1:-}"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This tool is Linux-only."
  exit 2
fi

pick_iface() {
  if command -v ip >/dev/null 2>&1; then
    ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' || true
  fi
}

if [[ -z "${IFACE}" ]]; then
  IFACE="$(pick_iface || true)"
fi

echo "== Stream Hub perf: NIC/RSS/IRQ check"
echo "ts=$(date -Is)"
echo "host=$(hostname)"
echo "kernel=$(uname -r)"
echo "cpu_count=$(nproc)"
echo

if [[ -z "${IFACE}" ]]; then
  echo "WARN: interface not provided and could not be auto-detected."
  echo "Usage: $0 <iface>"
  exit 0
fi

if [[ ! -d "/sys/class/net/${IFACE}" ]]; then
  echo "ERROR: interface not found: ${IFACE}"
  echo "Available: $(ls -1 /sys/class/net | tr '\n' ' ')"
  exit 2
fi

echo "iface=${IFACE}"
echo

echo "== sysctl (UDP buffers)"
for k in \
  net.core.rmem_max net.core.wmem_max net.core.rmem_default net.core.wmem_default \
  net.core.netdev_max_backlog \
  net.ipv4.udp_rmem_min net.ipv4.udp_wmem_min \
; do
  sysctl -n "$k" 2>/dev/null | awk -v k="$k" '{print k"="$0}' || true
done
echo

echo "== irqbalance"
if command -v systemctl >/dev/null 2>&1; then
  systemctl is-active irqbalance 2>/dev/null | awk '{print "irqbalance_systemd="$0}' || true
fi
if command -v pgrep >/dev/null 2>&1; then
  if pgrep -x irqbalance >/dev/null 2>&1; then
    echo "irqbalance_process=running"
  else
    echo "irqbalance_process=stopped"
  fi
fi
echo

echo "== ethtool"
if command -v ethtool >/dev/null 2>&1; then
  echo "-- driver"
  ethtool -i "${IFACE}" 2>/dev/null || true
  echo
  echo "-- channels"
  ethtool -l "${IFACE}" 2>/dev/null || true
  echo
  echo "-- RSS indirection table (top 32 lines)"
  ethtool -x "${IFACE}" 2>/dev/null | head -n 32 || true
else
  echo "WARN: ethtool not installed."
fi
echo

echo "== interrupts (best-effort grep)"
if [[ -r /proc/interrupts ]]; then
  # Many drivers include iface name in the IRQ label, e.g. eth0-TxRx-0.
  grep -E "${IFACE}|TxRx|rx|mlx|ixgbe|i40e|igb" /proc/interrupts | head -n 80 || true
else
  echo "WARN: /proc/interrupts not readable."
fi
echo

echo "== RPS (Receive Packet Steering) per RX queue"
if [[ -d "/sys/class/net/${IFACE}/queues" ]]; then
  found=0
  for q in /sys/class/net/"${IFACE}"/queues/rx-*; do
    [[ -d "$q" ]] || continue
    if [[ -f "$q/rps_cpus" ]]; then
      found=1
      echo "$(basename "$q") rps_cpus=$(cat "$q/rps_cpus")"
    fi
  done
  if [[ "$found" -eq 0 ]]; then
    echo "no rx-* queues found"
  fi
else
  echo "WARN: queues directory not found."
fi
echo

cat <<'TXT'
== Notes
- If one CPU hits 100% under many UDP multicast streams, common causes are:
  - IRQs pinned to a single core (irqbalance disabled / manual pinning)
  - RSS disabled or too few RX queues
  - RPS disabled on drivers without RSS

- For best results with Stream Hub "dataplane" mode:
  - enable RSS (multiple RX queues) if the NIC supports it
  - keep irqbalance running, or spread IRQ affinity manually
  - only use RPS as a fallback when RSS is not available
TXT

