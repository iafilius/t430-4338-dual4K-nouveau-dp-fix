#!/usr/bin/env bash
# ==============================================================================
# wake-nouveau-dp.sh
# Wakes the discrete NVIDIA NVS 5400M (GF108M) GPU from PCI runtime suspend
# and re-enables external DisplayPort monitors (DP-2 & DP-3) when multi-input
# monitors (e.g. Iiyama ProLite XB3288UHSU) do not emit a hotplug pulse on
# input switchback.
# ==============================================================================
set -euo pipefail

PCI_DEV="${NOUVEAU_PCI_DEV:-0000:01:00.0}"
POWER_CTRL="/sys/bus/pci/devices/${PCI_DEV}/power/control"
RUNTIME_STATUS="/sys/bus/pci/devices/${PCI_DEV}/power/runtime_status"

echo "=== Nouveau DisplayPort Wake-Up Utility ==="
if [[ -f "${RUNTIME_STATUS}" ]]; then
    echo "[*] Current GPU (${PCI_DEV}) runtime status: $(cat "${RUNTIME_STATUS}")"
else
    echo "[!] Warning: PCI device ${PCI_DEV} not found in sysfs."
fi

echo "[*] Forcing GPU power state to 'on' for hardware link rescan..."
echo on | sudo tee "${POWER_CTRL}" >/dev/null
sleep 2

echo "[*] Probing display subsystem via lshw..."
sudo lshw -C display >/dev/null 2>&1 || true

echo "[*] Restoring GPU power control to 'auto' (Runtime PM enabled)..."
echo auto | sudo tee "${POWER_CTRL}" >/dev/null

if [[ -f "${RUNTIME_STATUS}" ]]; then
    echo "[*] Updated GPU (${PCI_DEV}) runtime status: $(cat "${RUNTIME_STATUS}")"
fi

# Trigger Xwayland / X11 xrandr auto-detection if available
USER_ID="$(id -u)"
MUTTER_AUTH="$(ls /run/user/"${USER_ID}"/.mutter-Xwaylandauth.* 2>/dev/null | head -n 1 || true)"

if [[ -n "${MUTTER_AUTH}" ]]; then
    echo "[*] Triggering GNOME/Mutter Xwayland display reconfiguration..."
    XAUTHORITY="${MUTTER_AUTH}" DISPLAY="${DISPLAY:-:0}" xrandr --auto || true
elif command -v xrandr >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    echo "[*] Triggering xrandr --auto on DISPLAY=${DISPLAY}..."
    xrandr --auto || true
fi

echo "[+] Done! External DisplayPort monitors should now be active."

