# Wayland Dual-4K@30Hz Link Training & Watermark Setup (`waterMark > 39`)

When driving **two external 32" 4K monitors** (**Iiyama ProLite XB3288UHSU**, EDID `PL3288UH`, `3840×2160`) through the **Lenovo Type 4338 Dock** (`card2-DP-2` and `card2-DP-3`) alongside the internal **14" WQHD (`2560×1440`)** panel (`card1-LVDS-1`), you can hit a secondary display initialization issue on Wayland (Ubuntu 26.04 LTS / GNOME Mutter).

---

## 1. Symptom on Cold Boot

After upgrading to Ubuntu 26.04 LTS (Wayland), cold booting with both 4K monitors attached sometimes left one or both external monitors dark during the initial modeset, with `dmesg` logging a `WARN_ON` in `drivers/gpu/drm/nouveau/dispnv50/disp.c`.

---

## 2. Cause: SST Watermark Limit (`waterMark > 39`)

In `drivers/gpu/drm/nouveau/dispnv50/disp.c` (around line 1678, in `nv50_sor_dp_watermark_sst_calc`), `nouveau` checks the FIFO watermark limit for Single-Stream Transport (SST) DisplayPort links:

```c
if (WARN_ON(waterMark > 39 || waterMark > numSymbolsPerLine))
    return -EINVAL;
```

On the NVS 5400M (`GF108M`) DisplayPort 1.1a HBR controller, an uncalibrated cold-boot modeset at `3840×2160 @ 30.00Hz` across both pipes can exceed `waterMark > 39`, returning `-EINVAL` and aborting link training on the second monitor.

---

## 3. Workaround: `25Hz → 30Hz` Stepping & `~/.config/monitors.xml`

### Step 1: Bring Up the Link at `25.00Hz` First (or Run `scripts/fix-nouveau-4k-wayland.sh`)
If a cold DisplayPort link fails to come up directly at `30.00Hz`:
1. Set the 4K outputs to `3840×2160 @ 25.00Hz` first. At `25.00Hz`, the symbol rate stays below the `waterMark <= 39` limit, so both `DP-2` and `DP-3` train cleanly.
2. Once both displays are active, switch them to `3840×2160 @ 30.00Hz`.

You can run [`scripts/fix-nouveau-4k-wayland.sh`](../scripts/fix-nouveau-4k-wayland.sh) to perform the `25Hz → 30Hz` step-up automatically (or run `./scripts/fix-nouveau-4k-wayland.sh --write-config` to write a clean `~/.config/monitors.xml` profile).

### Step 2: Save the Layout in `~/.config/monitors.xml`
GNOME Mutter stores monitor layouts in `~/.config/monitors.xml`. Keeping the calibrated `10240 × 2160` layout as the active entry (and removing old conflicting profiles) ensures Mutter applies the working modeset on login:

| Connector | Display Panel | Resolution | Refresh Rate | Canvas Offset `(X, Y)` | Role |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `card1-LVDS-1` | Internal 14" WQHD LCD (Intel HD 4000) | `2560 × 1440` | `60.00 Hz` | `(0, 720)` | Internal Laptop Screen |
| `card2-DP-2` | Iiyama ProLite XB3288UHSU #1 (32" 4K) | `3840 × 2160` | `30.00 Hz` | `(2560, 0)` | Left 4K Monitor |
| `card2-DP-3` | Iiyama ProLite XB3288UHSU #2 (32" 4K) | `3840 × 2160` | `30.00 Hz` | `(6400, 0)` | Right 4K Monitor |
