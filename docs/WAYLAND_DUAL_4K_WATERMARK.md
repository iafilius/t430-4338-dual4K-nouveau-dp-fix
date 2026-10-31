# Wayland Dual-4K@30Hz Link Training & Watermark Bounds Calibration

When driving **two external 32" 4K monitors** (**Iiyama ProLite XB3288UHSU**, EDID `PL3288UH`, `3840x2160`) simultaneously over the **Lenovo ThinkPad Mini Dock Plus Series 3 (Model 4338)** (`card2-DP-2` and `card2-DP-3`) alongside the internal **14" WQHD (`2560x1440`)** panel (`card1-LVDS-1`), a secondary display initialization bug can occur on modern Wayland compositors (Ubuntu 26.04 LTS / GNOME Mutter).

---

## 1. Symptom on Cold Boot (Wayland Atomic Modeset)

After upgrading to Ubuntu 26.04 LTS (Wayland session), cold booting with both 4K monitors attached caused the external displays to lose sync or stay dark during the initial atomic modeset, while `dmesg` logged a kernel `WARN_ON` stack trace in `drivers/gpu/drm/nouveau/dispnv50/disp.c`.

---

## 2. Root Cause: SST Watermark Overflow (`waterMark > 39`)

Inside `drivers/gpu/drm/nouveau/dispnv50/disp.c` (around line 1678, in `nv50_sor_dp_watermark_sst_calc`), the Nouveau display driver enforces a strict hardware FIFO watermark bound for Single-Stream Transport (SST) DisplayPort links:

```c
if (WARN_ON(waterMark > 39 || waterMark > numSymbolsPerLine))
    return -EINVAL;
```

On the GF108M (NVS 5400M) DisplayPort 1.1a HBR controller, requesting an uncalibrated cold-boot atomic modeset at `3840x2160 @ 30.00Hz` across both SOR pipes can cause the initial untimed pixel-clock symbol calculation to exceed `waterMark > 39`, returning `-EINVAL` and aborting `nvif_outp_dp_sst(...)` before link symbols are pushed to the physical PHY.

---

## 3. Resolution: Frequency Stepping & `monitors.xml` Profile Lock

### Step 1: Initial Link Training via 25.00Hz Stepping
If a cold DisplayPort link fails to train directly at `30.00Hz`:
1. Initialize the 4K outputs at `3840x2160 @ 25.00Hz`. At `25.00Hz`, the symbol rate remains comfortably below the `waterMark <= 39` ceiling, allowing both `DP-2` and `DP-3` lanes to train and lock cleanly.
2. Once the link is active, step the refresh rate up to `3840x2160 @ 30.00Hz`. The transition succeeds with zero `WARN_ON` errors in `dmesg`.

### Step 2: Locking the Calibrated Canvas in `~/.config/monitors.xml`
GNOME Mutter persists multi-monitor geometry in `~/.config/monitors.xml`. Ensuring the calibrated `10240 × 2160` layout is stored as the primary configuration (and pruning stale historical profiles) guarantees clean modesets across logins:

| Connector | Display Panel | Resolution | Refresh Rate | Canvas Offset `(X, Y)` | Role |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `card1-LVDS-1` | Internal 14" WQHD LCD (Intel HD 4000) | `2560 × 1440` | `60.00 Hz` | `(0, 720)` | Primary Panel |
| `card2-DP-2` | Iiyama ProLite XB3288UHSU #1 (32" 4K) | `3840 × 2160` | `30.00 Hz` | `(2560, 0)` | Left 4K External |
| `card2-DP-3` | Iiyama ProLite XB3288UHSU #2 (32" 4K) | `3840 × 2160` | `30.00 Hz` | `(6400, 0)` | Right 4K External |

