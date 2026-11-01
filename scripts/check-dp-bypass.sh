#!/usr/bin/env bash
# ==============================================================================
# check-dp-bypass.sh
# Inspects running kernel version, NVIDIA GPU PCI runtime PM state, and counts
# prevented DisplayPort zero-lane division-by-zero crashes in dmesg / kern.log.
# ==============================================================================
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage: ./check-dp-bypass.sh [-h|--help]

Inspects the running kernel version, NVIDIA GPU PCI runtime PM state, and
counts prevented DisplayPort zero-lane division-by-zero crashes in dmesg
and /var/log/kern.log (when running the verbose nvkm_warn patch variant).

Environment Variables:
  NOUVEAU_PCI_DEV  PCI address of the discrete NVIDIA GPU (default: 0000:01:00.0)

Example:
  ./check-dp-bypass.sh
EOF
    exit 0
fi

PCI_DEV="${NOUVEAU_PCI_DEV:-0000:01:00.0}"
RUNTIME_STATUS="/sys/bus/pci/devices/${PCI_DEV}/power/runtime_status"

echo "=================================================================="
echo " Nouveau DisplayPort Zero-Lane Crash Prevention Diagnostic Report"
echo "=================================================================="
echo "Kernel Release : $(uname -r)"
echo "Full uname     : $(uname -a)"

if [[ -f "${RUNTIME_STATUS}" ]]; then
    echo "GPU PCI Status : $(cat "${RUNTIME_STATUS}") (${PCI_DEV})"
else
    echo "GPU PCI Status : N/A (not running on target T430 host)"
fi
echo "------------------------------------------------------------------"

echo "[1] Checking Kernel Ring Buffer (dmesg) for bypassed 0-lane events:"
if sudo dmesg 2>/dev/null | grep -i "DP link is inactive"; then
    COUNT=$(sudo dmesg 2>/dev/null | grep -c -i "DP link is inactive" || true)
    echo "--> Prevented ${COUNT} crash event(s) since last boot!"
else
    echo "--> No 'DP link is inactive' events in current dmesg buffer (or running silent upstream patch)."
fi

echo ""
echo "[2] Checking /var/log/kern.log history:"
if [[ -r /var/log/kern.log ]]; then
    HIST_COUNT=$(grep -c "DP link is inactive" /var/log/kern.log || true)
    echo "--> Total prevented crashes recorded in /var/log/kern.log: ${HIST_COUNT}"
    grep "DP link is inactive" /var/log/kern.log | tail -n 5 || true
else
    echo "--> /var/log/kern.log not readable or not present."
fi
echo "=================================================================="

