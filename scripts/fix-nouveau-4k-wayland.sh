#!/usr/bin/env bash
# ==============================================================================
# fix-nouveau-4k-wayland.sh
# Works around the Nouveau SST FIFO watermark limit (`WARN_ON(waterMark > 39)`
# in `nv50_sor_dp_watermark_sst_calc`, `drivers/gpu/drm/nouveau/dispnv50/disp.c`)
# when driving two external 32" 4K monitors (`DP-2` and `DP-3` at 3840x2160@30Hz)
# alongside the internal 2560x1440@60Hz LVDS panel on a ThinkPad T430 + 4338 Dock.
#
# How it works:
#   1. Trains both external 4K DisplayPort links at 3840x2160 @ 25Hz first
#      (which stays below the `waterMark <= 39` symbol threshold).
#   2. Steps both trained links up to 3840x2160 @ 30Hz across the full
#      10240 x 2160 desktop canvas:
#        - LVDS-1: 2560x1440 @ 60Hz at offset (0, 720) [Primary]
#        - DP-2:   3840x2160 @ 30Hz at offset (2560, 0)
#        - DP-3:   3840x2160 @ 30Hz at offset (6400, 0)
#   3. Optionally writes a clean ~/.config/monitors.xml template (--write-config)
#      so GNOME Mutter restores the working 30Hz layout automatically on login.
# ==============================================================================
set -euo pipefail

LVDS_OUT="${LVDS_OUT:-LVDS-1}"
DP_LEFT="${DP_LEFT:-DP-2}"
DP_RIGHT="${DP_RIGHT:-DP-3}"

echo "=== ThinkPad T430 + 4338 Dock Dual-4K@30Hz Wayland Watermark Fix ==="

if [[ "${1:-}" == "--write-config" ]]; then
    MONITORS_XML="${HOME}/.config/monitors.xml"
    if [[ -f "${MONITORS_XML}" ]]; then
        BACKUP="${MONITORS_XML}.bak.$(date +%Y%m%d-%H%M%S)"
        echo "[*] Backing up existing ${MONITORS_XML} to ${BACKUP}..."
        cp "${MONITORS_XML}" "${BACKUP}"
    fi
    mkdir -p "${HOME}/.config"
    cat > "${MONITORS_XML}" <<'EOF'
<monitors version="2">
  <configuration>
    <logicalmonitor>
      <x>0</x>
      <y>720</y>
      <scale>1</scale>
      <primary>yes</primary>
      <monitor>
        <monitorspec>
          <connector>LVDS-1</connector>
          <vendor>AUO</vendor>
          <product>0x1536</product>
          <serial>0x00000000</serial>
        </monitorspec>
        <mode>
          <width>2560</width>
          <height>1440</height>
          <rate>60.000</rate>
        </mode>
      </monitor>
    </logicalmonitor>
    <logicalmonitor>
      <x>2560</x>
      <y>0</y>
      <scale>1</scale>
      <monitor>
        <monitorspec>
          <connector>DP-2</connector>
          <vendor>IVM</vendor>
          <product>PL3288UH</product>
          <serial>0x00000000</serial>
        </monitorspec>
        <mode>
          <width>3840</width>
          <height>2160</height>
          <rate>29.981</rate>
        </mode>
      </monitor>
    </logicalmonitor>
    <logicalmonitor>
      <x>6400</x>
      <y>0</y>
      <scale>1</scale>
      <monitor>
        <monitorspec>
          <connector>DP-3</connector>
          <vendor>IVM</vendor>
          <product>PL3288UH</product>
          <serial>0x00000000</serial>
        </monitorspec>
        <mode>
          <width>3840</width>
          <height>2160</height>
          <rate>29.981</rate>
        </mode>
      </monitor>
    </logicalmonitor>
  </configuration>
</monitors>
EOF
    echo "[+] Wrote calibrated 10240x2160 Dual-4K@30Hz profile to ${MONITORS_XML}."
    echo "    Log out and back in (or run without --write-config) to apply."
    exit 0
fi

# Step 1: Train DP links at 25Hz first -> Step 2: Switch up to 30Hz
if command -v gdctl >/dev/null 2>&1; then
    echo "[*] Step 1/2 (gdctl): Training ${DP_LEFT} and ${DP_RIGHT} at 3840x2160@25Hz (below waterMark > 39 limit)..."
    gdctl set \
        --logical-monitor --primary --x 0 --y 720 --monitor "${LVDS_OUT}" --mode 2560x1440@60.000 \
        --logical-monitor --x 2560 --y 0 --monitor "${DP_LEFT}" --mode 3840x2160@25.000 \
        --logical-monitor --x 6400 --y 0 --monitor "${DP_RIGHT}" --mode 3840x2160@25.000 || true
    sleep 2

    echo "[*] Step 2/2 (gdctl): Stepping ${DP_LEFT} and ${DP_RIGHT} up to 3840x2160@30Hz..."
    gdctl set --persistent \
        --logical-monitor --primary --x 0 --y 720 --monitor "${LVDS_OUT}" --mode 2560x1440@60.000 \
        --logical-monitor --x 2560 --y 0 --monitor "${DP_LEFT}" --mode 3840x2160@29.981 \
        --logical-monitor --x 6400 --y 0 --monitor "${DP_RIGHT}" --mode 3840x2160@29.981
elif command -v gnome-monitor-config >/dev/null 2>&1; then
    echo "[*] Step 1/2 (gnome-monitor-config): Training ${DP_LEFT} and ${DP_RIGHT} at 3840x2160@25Hz..."
    gnome-monitor-config set \
        -LpM "${LVDS_OUT}" -x 0 -y 720 -m 2560x1440@60.000 \
        -LM "${DP_LEFT}" -x 2560 -y 0 -m 3840x2160@25.000 \
        -LM "${DP_RIGHT}" -x 6400 -y 0 -m 3840x2160@25.000 || true
    sleep 2

    echo "[*] Step 2/2 (gnome-monitor-config): Stepping ${DP_LEFT} and ${DP_RIGHT} up to 3840x2160@30Hz..."
    gnome-monitor-config set \
        -LpM "${LVDS_OUT}" -x 0 -y 720 -m 2560x1440@60.000 \
        -LM "${DP_LEFT}" -x 2560 -y 0 -m 3840x2160@29.981 \
        -LM "${DP_RIGHT}" -x 6400 -y 0 -m 3840x2160@29.981
elif command -v xrandr >/dev/null 2>&1; then
    echo "[*] Step 1/2 (xrandr): Training ${DP_LEFT} and ${DP_RIGHT} at 3840x2160@25Hz..."
    xrandr --output "${LVDS_OUT}" --primary --mode 2560x1440 --rate 60 --pos 0x720 \
           --output "${DP_LEFT}" --mode 3840x2160 --rate 25 --pos 2560x0 \
           --output "${DP_RIGHT}" --mode 3840x2160 --rate 25 --pos 6400x0 || true
    sleep 2

    echo "[*] Step 2/2 (xrandr): Stepping ${DP_LEFT} and ${DP_RIGHT} up to 3840x2160@30Hz..."
    xrandr --output "${LVDS_OUT}" --primary --mode 2560x1440 --rate 60 --pos 0x720 \
           --output "${DP_LEFT}" --mode 3840x2160 --rate 30 --pos 2560x0 \
           --output "${DP_RIGHT}" --mode 3840x2160 --rate 30 --pos 6400x0
else
    echo "[!] Neither gdctl, gnome-monitor-config, nor xrandr found. Run with --write-config to generate ~/.config/monitors.xml."
    exit 1
fi

echo "[+] Done! Full 10240x2160 desktop active (2560x1440@60Hz + 2x 3840x2160@30Hz)."
