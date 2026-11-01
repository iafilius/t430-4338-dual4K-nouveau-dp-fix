# Lenovo ThinkPad T430 + 4338 Dock + Dual 4K: Linux Kernel Nouveau DisplayPort Division-by-Zero Fix

[![Linux Kernel](https://img.shields.io/badge/Linux_Kernel-6.8.x_%E2%86%92_7.1.3-007ec6?logo=linux&logoColor=white)](docs/KERNEL_TEST_MATRIX.md)
[![Subsystem](https://img.shields.io/badge/Subsystem-drm%2Fnouveau%2Fdisp_(nv50.c)-76B900?logo=nvidia&logoColor=white)](patches/0001-drm-nouveau-disp-Prevent-divide-by-zero-after-screen-wake-up.patch)
[![Hardware](https://img.shields.io/badge/Hardware-ThinkPad_T430_%2B_4338_Dock-E2231A?logo=lenovo&logoColor=white)](docs/HARDWARE_AND_DRIVER_HISTORY.md)
[![Displays](https://img.shields.io/badge/Displays-2x_32%22_Iiyama_XB3288UHSU_4K-38bdf8)](docs/HARDWARE_AND_DRIVER_HISTORY.md)
[![Upstream Status](https://img.shields.io/badge/Upstream_LKML-%5BPATCH_v2%5D_In_Review-f59e0b)](https://www.mail-archive.com/nouveau@lists.freedesktop.org/msg54492.html)

![ThinkPad T430 + 4338 Dock + Dual 32" 4K Shared Workstation](assets/hero-banner.png)

> **Author:** Arjan Filius (`iafilius@xs4all.nl`)  
> **Target Function:** `nv50_disp_super_2_2_dp()` in `drivers/gpu/drm/nouveau/nvkm/engine/disp/nv50.c`  
> **Upstream Bug Reports:** [FreeDesktop GitLab Issue #377](https://gitlab.freedesktop.org/drm/nouveau/-/issues/377) • [MR !25](https://gitlab.freedesktop.org/drm/nouveau/-/merge_requests/25) • [MR !27](https://gitlab.freedesktop.org/drm/nouveau/-/merge_requests/27)  
> **LKML Submission:** [Lore Thread](https://lore.kernel.org/lkml/69D67A9F-1A56-4814-AE68-50559DED42AF@xs4all.nl/) • [`nouveau@lists.freedesktop.org` (`[PATCH v2]`)](https://www.mail-archive.com/nouveau@lists.freedesktop.org/msg54492.html)

---

## Overview

The **Lenovo ThinkPad T430** has a discrete **NVIDIA NVS 5400M (`GF108M` Fermi)** GPU wired to the digital display ports on the **Type 4338 Dock**. NVIDIA ended support for this chipset years ago, freezing the legacy proprietary driver at **`390.157`** (`nvidia-driver-390`). That made the proprietary driver a dead end for two reasons:
1. **Broken Kernel Upgrades:** Getting `nvidia-dkms-390` to compile on newer Linux kernels was a constant struggle that regularly broke upgrades.
2. **Xorg/X11 Only (No Wayland):** The `390.xx` driver has no support for **Wayland** (no GBM, DMA-BUF Reverse PRIME, or Xwayland acceleration).

Dropping the proprietary driver was an easy decision once the open-source **`nouveau`** driver matured. Together with **Wayland** (replacing Xorg/X11), `nouveau` drives my T430's internal **WQHD (`2560×1440`)** screen alongside **two external 32-inch 4K (`3840×2160 @ 30Hz`) monitors** (**10240 × 2160 total desktop**)—pushing the 2012 hardware to its physical limit.

**Does it work? Yes, out of the box—but it is only reliable with a small one-liner kernel patch (`if (ior->dp.nr == 0) return;`).**

Without that check, switching the two 4K monitors over to my second laptop (on HDMI), letting the monitors go into power-saving standby when that laptop falls asleep, and then switching them back (or waking them up) triggers a **kernel division-by-zero oops** on the T430. During that transition (`DRM: DDC responded, but no EDID for DP-2 / DP-3`), the T430 is not properly informed or polled about the actual DisplayPort link state: `nouveau` assumes the monitor output is active and runs `nv50_disp_super_2_2_dp()` while the active DisplayPort lane count is still `0` (`ior->dp.nr == 0`). Even though this is a corner case—and whether the underlying state quirk is in the monitor firmware, the dock, or kernel polling—**the Linux kernel must never crash on it.** Without the patch, the desktop freezes, system load climbs above `1.0`, `reboot` hangs, and the laptop needs a hard power reset.

I first tracked down and patched this bug in **July 2024** ([GitLab Issue #377](https://gitlab.freedesktop.org/drm/nouveau/-/issues/377)). After hitting the exact same freeze again on a clean mainline **`7.1.3`** kernel in **July 2026**, I put together this repository so I don't have to dig up my notes every time—and to help kernel maintainers as well as other ThinkPad T430 / NVIDIA users struggling with unexplained DisplayPort black-screen freezes. Because you can only see the `nv50_disp_super_2_2_dp` kernel oops if you log in via SSH from a second machine after the screens go dark, this `ior->dp.nr == 0` condition (or similar DisplayPort link-state mismatches) is **[possibly related to a number of other NVIDIA/Nouveau DisplayPort black-screen, input-switching, and wake-from-sleep freezes reported across bug trackers and forums](docs/HARDWARE_AND_DRIVER_HISTORY.md#5-possibly-related-nvidianouveau-displayport-black-screen--wake-up-reports)**.

### Quick Navigation by Audience

| If you are... | Start here |
| :--- | :--- |
| **A Linux Kernel / Nouveau Maintainer** | [Section 2: Root Cause & Backtrace](#2-root-cause-the-end-of-workday-division-by-zero-bug) • [Section 3: The Patch & `b4 am`](#3-the-kernel-patch-nv50c--tested-kernels) • [`docs/KERNEL_TEST_MATRIX.md`](docs/KERNEL_TEST_MATRIX.md) |
| **A ThinkPad T430 / 4338 Dock / Legacy NVIDIA User** | [`docs/HARDWARE_AND_DRIVER_HISTORY.md`](docs/HARDWARE_AND_DRIVER_HISTORY.md) • [Section 4: Building & Scripts](#4-building-the-kernel-helper-scripts--deep-dive-docs) • [`docs/WAYLAND_DUAL_4K_WATERMARK.md`](docs/WAYLAND_DUAL_4K_WATERMARK.md) |
| **Interested in the Kernel Debugging Backstory** | [`docs/KERNEL_DEBUGGING_JOURNEY.md`](docs/KERNEL_DEBUGGING_JOURNEY.md) (`gdb nv50.o`, `objdump`, and why remote debugging via `kgdboe` failed) |

---

## 1. Hardware & Shared Dual-4K Topology

![Hybrid GPU & Shared Dual-4K Display Topology](assets/architecture-topology.svg)

*Full 4338 Dock port specs, `2× 4K@30Hz` bandwidth limits, and the `nvidia-390` → `nouveau` + Wayland migration history are documented in **[`docs/HARDWARE_AND_DRIVER_HISTORY.md`](docs/HARDWARE_AND_DRIVER_HISTORY.md)**.*

* **ThinkPad T430 + Type 4338 Dock (Left):** Intel HD 4000 (`i915`) drives the internal `2560×1440 @ 60Hz` panel (`card1-LVDS-1`). The discrete NVIDIA NVS 5400M (`nouveau`, `0000:01:00.0`) drives the two rear DisplayPort outputs on the 4338 Dock:
  * **Cyan cable (`card2-DP-2`):** → Left 32" Iiyama ProLite XB3288UHSU (`3840×2160 @ 30Hz`).
  * **Green cable (`card2-DP-3`):** → Right 32" Iiyama ProLite XB3288UHSU (`3840×2160 @ 30Hz`).
* **Apple MacBook Pro Work Laptop (Right):** Shares both 4K monitors via HDMI (**Cyan** USB-C-to-HDMI adapter on the left to the Left Monitor; **Green** native HDMI cable on the right to the Right Monitor). No cable connects the two laptops.

---

## 2. Root Cause: The "End-of-Workday" Division-by-Zero Bug

![The End-of-Workday Crash State Machine](assets/crash-state-machine.svg)

### How the Crash Happens
1. **Switch inputs to the 2nd laptop:** Both 32" Iiyama 4K monitors are switched to their **HDMI** inputs (displaying the MacBook Pro) while the T430 stays docked on **DisplayPort** (`DP-2` and `DP-3`).
2. **Monitors enter power-saving standby:** At the end of the workday, the MacBook Pro goes to sleep. With no active signal on HDMI, both monitors enter **power-saving standby**, and the DisplayPort lane count drops to `0` (`ior->dp.nr == 0`).
3. **Switch back / wake up with stale link state:** When the monitors wake up or are switched back to the T430, the T430 is not properly informed or polled for the actual link situation (`DRM: DDC responded, but no EDID for DP-2 / DP-3`). The display engine assumes the monitor is still/again there and triggers the `nv50_disp_super` modeset supervisor before DisplayPort link training has established active lanes (`ior->dp.nr == 0`).
4. **Unchecked division by zero in `nv50.c`:** Whether this desynchronized state is a quirk in the monitor firmware or in `nouveau`'s hot-plug/polling logic, the kernel must not crash on it. Inside `drivers/gpu/drm/nouveau/nvkm/engine/disp/nv50.c`, `nv50_disp_super_2_2_dp()` divides directly by `ior->dp.nr` in three places without checking for zero:

```c
// drivers/gpu/drm/nouveau/nvkm/engine/disp/nv50.c (lines 1179–1190)
h = h - (3 * ior->dp.ef) - (12 / ior->dp.nr);                   // <-- divide by 0
v = v - ((36 / ior->dp.nr) + 3) - 1;                            // <-- divide by 0
link_data_rate = (khz * head->asy.or.depth / 8) / ior->dp.nr;   // <-- divide by 0
```

### Kernel Oops Backtrace (Unpatched Kernel)
```text
[di jul 23 10:28:25 2024] nouveau 0000:01:00.0: DRM: DDC responded, but no EDID for DP-2
[di jul 23 10:28:25 2024] nouveau 0000:01:00.0: DRM: DDC responded, but no EDID for DP-3
[di jul 23 10:28:26 2024] Workqueue: nvkm-disp nv50_disp_super [nouveau]
[di jul 23 10:28:26 2024] RIP: 0010:nv50_disp_super_2_2_dp+0xa7/0x320 [nouveau]
[di jul 23 10:28:26 2024]  ? nv50_disp_super_2_2_dp+0xa7/0x320 [nouveau]
[di jul 23 10:28:26 2024]  nv50_disp_super_2_2+0xf2/0x160 [nouveau]
[di jul 23 10:28:26 2024]  nv50_disp_super+0x139/0x280 [nouveau]
...
[di jul 23 10:28:28 2024] nouveau 0000:01:00.0: DRM: core notifier timeout
[di jul 23 10:28:31 2024] nouveau 0000:01:00.0: DRM: base-0: timeout
```

*(For the story of how I pinpointed these lines in 2024 using `gdb nv50.o` and `objdump`, and why attempting remote kernel debugging over Ethernet with `kgdboe` hung the target kernel, see **[`docs/KERNEL_DEBUGGING_JOURNEY.md`](docs/KERNEL_DEBUGGING_JOURNEY.md)**).*

---

## 3. The Kernel Patch (`nv50.c`) & Tested Kernels

Two patch variants are available in [`patches/`](patches/):

### Variant A: Silent Upstream `[PATCH v2]` (Submitted to LKML)
File: [`patches/0001-drm-nouveau-disp-Prevent-divide-by-zero-after-screen-wake-up.patch`](patches/0001-drm-nouveau-disp-Prevent-divide-by-zero-after-screen-wake-up.patch)

```diff
diff --git a/drivers/gpu/drm/nouveau/nvkm/engine/disp/nv50.c b/drivers/gpu/drm/nouveau/nvkm/engine/disp/nv50.c
index 51c045bdfcbb..ab1bc0898def 100644
--- a/drivers/gpu/drm/nouveau/nvkm/engine/disp/nv50.c
+++ b/drivers/gpu/drm/nouveau/nvkm/engine/disp/nv50.c
@@ -1157,6 +1157,10 @@ nv50_disp_super_2_2_dp(struct nvkm_head *head, struct nvkm_ior *ior)
 {
 	struct nvkm_subdev *subdev = &head->disp->engine.subdev;
 
+	/* If the DisplayPort link is inactive (0 lanes), skip configuration */
+	if (ior->dp.nr == 0)
+		return;
+
 	const u32 khz = head->asy.hz / 1000;
 	const u32 linkKBps = ior->dp.bw * 27000;
 	const u32 symbol = 100000;
```

Maintainers can pull `[PATCH v2]` directly from Lore using `b4`:
```bash
b4 am EB2FB627-5EFE-4572-81D9-3D965C868C90@xs4all.nl
git am ./*.mbx
```

### Variant B: Diagnostic `nvkm_warn()` Patch (With Kernel Logging so You Know a Crash Was Prevented)
File: [`patches/0001-drm-nouveau-disp-verbose-dmesg-logging.patch`](patches/0001-drm-nouveau-disp-verbose-dmesg-logging.patch) — this is the version I run locally on my T430 so `dmesg` explicitly logs every time a `lanes = 0` division-by-zero crash has been prevented:

```diff
diff --git a/drivers/gpu/drm/nouveau/nvkm/engine/disp/nv50.c b/drivers/gpu/drm/nouveau/nvkm/engine/disp/nv50.c
index 51c045bdfcbb..38a917ef021c 100644
--- a/drivers/gpu/drm/nouveau/nvkm/engine/disp/nv50.c
+++ b/drivers/gpu/drm/nouveau/nvkm/engine/disp/nv50.c
@@ -1157,6 +1157,12 @@ nv50_disp_super_2_2_dp(struct nvkm_head *head, struct nvkm_ior *ior)
 {
 	struct nvkm_subdev *subdev = &head->disp->engine.subdev;
 
+	/* If the DisplayPort link is inactive (0 lanes), skip configuration */
+	if (ior->dp.nr == 0) {
+		nvkm_warn(subdev, "DP link is inactive (lanes = 0), skipping display configuration.\n");
+		return;
+	}
+
 	const u32 khz = head->asy.hz / 1000;
 	const u32 linkKBps = ior->dp.bw * 27000;
 	const u32 symbol = 100000;
```

Example `dmesg` output when a crash is prevented:
```text
[45162.232371] nouveau 0000:01:00.0: disp: DP link is inactive (lanes = 0), skipping display configuration.
```

### Tested Kernel Summary (2024–2026)

Full details and LKML correspondence are in **[`docs/KERNEL_TEST_MATRIX.md`](docs/KERNEL_TEST_MATRIX.md)**.

| Period | Kernel Version | Unpatched | Patched | Reference |
| :--- | :--- | :--- | :--- | :--- |
| **July 2024** | Ubuntu `6.8.0-x-generic` | 💥 Freeze on monitor standby | ✅ Stable | [GitLab Issue #377](https://gitlab.freedesktop.org/drm/nouveau/-/issues/377) |
| **July 2024** | Mainline `6.9.9` | 💥 Divide-by-zero in `nv50_disp_super_2_2_dp` | ✅ Stable | [GitLab MR !25](https://gitlab.freedesktop.org/drm/nouveau/-/merge_requests/25) |
| **Aug 2024** | Mainline `6.10.y` | 💥 Crash present in vanilla tree | ✅ Stable (ran ~2 years) | [GitLab MR !27](https://gitlab.freedesktop.org/drm/nouveau/-/merge_requests/27) |
| **July 2026** | Mainline `7.1.3` (Vanilla) | 💥 Froze within 24h + forced `fsck` | — | Still unfixed in vanilla 7.1.3 |
| **July–Oct 2026** | Mainline `7.1.3-custom #2` | — | ✅ Stable (`dmesg` verified) | [LKML `[PATCH v2]` (`msg54492`)](https://www.mail-archive.com/nouveau@lists.freedesktop.org/msg54492.html) |

---

## 4. Building the Kernel, Helper Scripts & Deep-Dive Docs

### Helper Scripts (`scripts/`)
```bash
# 1. Download, patch, and build .deb packages for a mainline kernel (e.g. 7.1.3):
./scripts/build-patched-kernel.sh 7.1.3 verbose

# 2. Check dmesg/kern.log for prevented crashes and check GPU PCI runtime status:
./scripts/check-dp-bypass.sh

# 3. Wake the NVS 5400M from PCI runtime suspend when switching monitors back from HDMI to DP:
./scripts/wake-nouveau-dp.sh

# 4. Train dual 4K@30Hz Wayland links via 25Hz->30Hz stepping (or pass --write-config for ~/.config/monitors.xml):
./scripts/fix-nouveau-4k-wayland.sh
```

### Documentation Index (`docs/` & `assets/`)
* **[`docs/HARDWARE_AND_DRIVER_HISTORY.md`](docs/HARDWARE_AND_DRIVER_HISTORY.md)** — T430 + Type 4338 Dock port wiring, running `2× 4K@30Hz` at the hardware limit, and why I moved from `nvidia-driver-390` (`390.157` / X11) to `nouveau` + Wayland.
* **[`docs/KERNEL_DEBUGGING_JOURNEY.md`](docs/KERNEL_DEBUGGING_JOURNEY.md)** — How I debugged the crash in 2024 with `gdb nv50.o` and `objdump`, the dead end with `kgdboe` remote UDP kernel debugging, and discovering `lshw -c video` to wake the GPU.
* **[`docs/KERNEL_TEST_MATRIX.md`](docs/KERNEL_TEST_MATRIX.md)** — Full 2024–2026 kernel test log and LKML review history.
* **[`docs/WAYLAND_DUAL_4K_WATERMARK.md`](docs/WAYLAND_DUAL_4K_WATERMARK.md)** — Fixing the Wayland cold-boot `WARN_ON(waterMark > 39)` issue in `disp.c` via `25Hz → 30Hz` stepping and `~/.config/monitors.xml`.
* **[`assets/mermaid-sources.md`](assets/mermaid-sources.md)** — Editable Mermaid definitions for the repository diagrams.

---

## License

Kernel patches in `patches/` are provided under **GPL-2.0** (`Signed-off-by: Arjan Filius <iafilius@xs4all.nl>`). Documentation, scripts, and diagrams are released under the **MIT License**.
