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

Without that check, switching the two 4K monitors over to my second laptop (on HDMI), letting the monitors go into power-saving standby when that laptop falls asleep, and then switching them back (or waking them up) triggers a **kernel division-by-zero oops** on the T430. During that transition (`DRM: DDC responded, but no EDID for DP-2 / DP-3`), the T430 is not properly informed or polled about the actual DisplayPort link state: `nouveau` assumes the monitor output is active and runs `nv50_disp_super_2_2_dp()` while the active DisplayPort lane count is still `0` (`ior->dp.nr == 0`). Even though this is a corner case—and whether the underlying state quirk is in the monitor firmware, the dock, or kernel polling—**the Linux kernel must never crash on it.**

### What You Actually See (Symptoms on a Hybrid `i915` + `nouveau` Laptop)

Because this is a hybrid Optimus laptop where the **Intel HD 4000 (`i915`)** drives the internal laptop screen (`LVDS-1`) and the **NVIDIA NVS 5400M (`nouveau`)** drives the docked DisplayPort monitors (`DP-2`, `DP-3`), the crash shows up as a split set of symptoms:
- **External DisplayPort Monitors (`nouveau`): Always Stay Black.** Once the crash hits on wake-up, both external 4K monitors stay completely black (*"monitor no longer there after display wakeup"*).
- **Internal Laptop Screen (`i915`): Sometimes Keeps Working, Sometimes Freezes/Stays Black.** Depending on whether the Wayland compositor (GNOME Mutter / GDM3) blocks waiting on the wedged `nouveau` DRM device (`card2`), the internal Intel screen sometimes wakes up and keeps working—and other times stays black or frozen with an unresponsive local keyboard.
- **Runaway System Load (`1 → 50+` via `gpu-manager`):** The crashed `nvkm-disp` kworker hangs in uninterruptible sleep (`D` state), setting the baseline load average to `1.0`. Every time `gpu-manager`, `udev`, or a display query runs and touches the wedged NVIDIA DRM node, another process hangs in `D` state (`load = load + 1`), stair-stepping the system load to **`50+`** even at near-zero CPU usage.
- **Normal `reboot` Always Hangs:** Attempting a normal shutdown or `sudo reboot` hangs indefinitely waiting on the wedged `nouveau` display workqueue, forcing a manual hard power-button reset (and an `fsck` on the next boot).

I first tracked down and patched this bug in **July 2024** ([GitLab Issue #377](https://gitlab.freedesktop.org/drm/nouveau/-/issues/377)). After running a patched `6.16.5` kernel for **226 days of continuous uptime** and then hitting the exact same freeze again within 24 hours on a clean mainline **`7.1.3`** kernel in **July 2026**, I put together this repository so I don't have to dig up my notes every time—and to help kernel maintainers as well as other ThinkPad T430 / NVIDIA users struggling with unexplained DisplayPort black-screen freezes. Because you often need to log in via SSH from a second machine to see the `nv50_disp_super_2_2_dp` kernel oops in `dmesg`, this `ior->dp.nr == 0` condition (or similar DisplayPort link-state mismatches) is **[possibly related to a number of other NVIDIA/Nouveau DisplayPort black-screen, input-switching, and wake-from-sleep freezes reported across bug trackers and forums](docs/HARDWARE_AND_DRIVER_HISTORY.md#5-possibly-related-nvidianouveau-displayport-black-screen--wake-up-reports)**.

### Quick Navigation by Audience

| If you are... | Start here |
| :--- | :--- |
| **A Linux Kernel / Nouveau Maintainer** | [Section 2: Root Cause & Backtrace](#2-root-cause-the-end-of-workday-division-by-zero-bug) • [Section 3: The Patch & `b4 am`](#3-the-kernel-patch-nv50c--tested-kernels) • [`docs/KERNEL_TEST_MATRIX.md`](docs/KERNEL_TEST_MATRIX.md) |
| **A ThinkPad T430 / 4338 Dock / Legacy NVIDIA User** | [`docs/HARDWARE_AND_DRIVER_HISTORY.md`](docs/HARDWARE_AND_DRIVER_HISTORY.md) • [Section 4: Building & Scripts](#4-building-the-kernel-helper-scripts--deep-dive-docs) • [`docs/WAYLAND_DUAL_4K_WATERMARK.md`](docs/WAYLAND_DUAL_4K_WATERMARK.md) |
| **Interested in the Kernel Debugging Backstory** | [`docs/KERNEL_DEBUGGING_JOURNEY.md`](docs/KERNEL_DEBUGGING_JOURNEY.md) (compiling with `DEBUG_INFO`, decoding backtraces with `gdb nv50.o` / `objdump` / `faddr2line`, and why `kgdboe` failed) |

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

### Three Ways to Trigger / Reproduce the Bug
1. **Fast 30-Second Reproducer ([GitLab Issue #377](https://gitlab.freedesktop.org/drm/nouveau/-/issues/377)):** In a Wayland + GDM3/GNOME session, lock the laptop (`Win+L` / `Super+L`) and wait a few seconds for it to turn off the internal and external displays. Switch the external monitors to another input and let them enter power-save mode, then wake the T430.
2. **Daily "End-of-Workday" Standby Scenario:** Switch both 32" Iiyama 4K monitors to their **HDMI** inputs (displaying the MacBook Pro) while the T430 stays docked on **DisplayPort** (`DP-2` and `DP-3`). When the MacBook Pro sleeps at the end of the workday, both monitors enter **power-saving standby** (`ior->dp.nr == 0`). Waking or switching back to the T430 triggers `nv50_disp_super` while `ior->dp.nr == 0`.
3. **Rebooting While Monitors Are Switched Away:** Switch the external monitors to the second laptop, reboot the T430 while they are switched away, and switch the monitors back to the T430.

In all three cases, the T430 is not properly informed or polled for the actual link state (`DRM: DDC responded, but no EDID for DP-2 / DP-3`). `nouveau` assumes the monitor is still/again active and calls `nv50_disp_super_2_2_dp()` before DisplayPort link training has established active lanes (`ior->dp.nr == 0`). Inside `drivers/gpu/drm/nouveau/nvkm/engine/disp/nv50.c`, `nv50_disp_super_2_2_dp()` divides directly by `ior->dp.nr` in three places without checking for zero:

```c
// drivers/gpu/drm/nouveau/nvkm/engine/disp/nv50.c (lines 1179–1190)
h = h - (3 * ior->dp.ef) - (12 / ior->dp.nr);                   // <-- divide by 0
v = v - ((36 / ior->dp.nr) + 3) - 1;                            // <-- divide by 0
link_data_rate = (khz * head->asy.or.depth / 8) / ior->dp.nr;   // <-- divide by 0
```

### Kernel Oops Backtrace (Unpatched Kernel)

> [!TIP]
> **Debugging Tip — Use SSH from a Second Machine When Screen & Keyboard Are Dead:**
> When this bug hits, the external screens stay black and—if the compositor blocks on the wedged `nouveau` DRM device—the internal screen and local keyboard also stop responding (even `Ctrl+Alt+F2` does not switch to a text console). However, the Linux network stack and `sshd` stay alive! By logging in via **SSH from a second laptop**, you can run `sudo dmesg -T` live to catch the `nv50_disp_super_2_2_dp` divide error, see the stuck `kworker` and `gpu-manager` processes driving the system load from `1.0` up to `50+`, and flush disks with `sync` before power-cycling (since `sudo reboot` also hangs waiting on the dead `nvkm-disp` workqueue).

```text
[Tue Jul 23 18:36:32 2024] nouveau 0000:01:00.0: DRM: DDC responded, but no EDID for DP-2
[Tue Jul 23 18:36:32 2024] nouveau 0000:01:00.0: DRM: DDC responded, but no EDID for DP-3
[Tue Jul 23 18:36:33 2024] divide error: 0000 [#1] PREEMPT SMP PTI
[Tue Jul 23 18:36:33 2024] CPU: 1 PID: 70 Comm: kworker/u32:2 Not tainted 6.9.9-060909-generic #202407111135
[Tue Jul 23 18:36:33 2024] Hardware name: LENOVO 2349G7G/2349G7G, BIOS G1ETC2WW (2.82 ) 08/07/2019
[Tue Jul 23 18:36:33 2024] Workqueue: nvkm-disp nv50_disp_super [nouveau]
[Tue Jul 23 18:36:33 2024] RIP: 0010:nv50_disp_super_2_2_dp+0xa6/0x320 [nouveau]
[Tue Jul 23 18:36:33 2024] Code: 44 24 4e 41 0f b7 54 24 4c 41 83 e0 01 4c 89 ef 83 e8 19 29 d0 31 d2 48 98 49 0f af c6 48 f7 f1 31 d2 48 89 c1 b8 24 00 00 00 <f7> fe 31 d2 43 8d 34 40 48 63 f6 29 c1 b8 0c 00 00 00 41 f7 f9 83
[Tue Jul 23 18:36:33 2024] RAX: 0000000000000024 RBX: 00000000000001f6 RCX: 0000000000000794
[Tue Jul 23 18:36:33 2024] RDX: 0000000000000000 RSI: 0000000000000000 RDI: ffff9533951d5100
[Tue Jul 23 18:36:33 2024] Call Trace:
[Tue Jul 23 18:36:33 2024]  <TASK>
[Tue Jul 23 18:36:33 2024]  ? exc_divide_error+0x3a/0x70
[Tue Jul 23 18:36:33 2024]  ? nv50_disp_super_2_2_dp+0xa6/0x320 [nouveau]
[Tue Jul 23 18:36:33 2024]  nv50_disp_super_2_2+0xf2/0x160 [nouveau]
[Tue Jul 23 18:36:33 2024]  nv50_disp_super+0x139/0x280 [nouveau]
...
[Tue Jul 23 18:36:35 2024] nouveau 0000:01:00.0: DRM: core notifier timeout
[Tue Jul 23 18:36:37 2024] nouveau 0000:01:00.0: DRM: base-1: timeout
```

*(Notice how you can read the bug right out of the register dump: `b8 24 00 00 00` loads `0x24` = **`36`** into `RAX`, and `<f7> fe` (`idiv %esi`) divides `RAX=36` by `RSI: 0000000000000000` (`ior->dp.nr == 0`)—which is literally `36 / ior->dp.nr`! For the full story of how I decoded this in 2024 using `gdb nv50.o` and `objdump`, and why remote kernel debugging over Ethernet with `kgdboe` hung the target kernel, see **[`docs/KERNEL_DEBUGGING_JOURNEY.md`](docs/KERNEL_DEBUGGING_JOURNEY.md)**).*

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
| **Aug 2024** | Mainline `6.10.y` | 💥 Crash present in vanilla tree | ✅ Stable | [GitLab MR !27](https://gitlab.freedesktop.org/drm/nouveau/-/merge_requests/27) |
| **2025–Jul 2026** | Mainline `6.16.5-custom` | 💥 Crash present in vanilla tree | ✅ **226 days continuous uptime** | Local long-term production run |
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
