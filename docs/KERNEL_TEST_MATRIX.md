# Historical Kernel Test Matrix & Upstream Timeline (2024–2026)

This document lists the Linux kernel versions tested on my **Lenovo ThinkPad T430 (NVIDIA NVS 5400M / GF108M)** in the **Type 4338 Dock** with two **32" Iiyama ProLite XB3288UHSU (`PL3288UH`) 4K** monitors on DisplayPort (`DP-2` and `DP-3`).

---

## 1. Tested Linux Kernels

| Date / Period | Distribution / Driver | Kernel Version | Unpatched Behavior | Patched Behavior (`ior->dp.nr == 0` check) | Upstream Link |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Pre-2024** | Proprietary `nvidia-390` (`390.157`) vs. early `nouveau` | `5.x` – `6.5.x` | Early `nouveau` was unusable on this docked setup. Proprietary `nvidia-driver-390` (`390.157`) was Xorg/X11-only (no Wayland) and increasingly broke DKMS builds on newer kernels. | Switched to in-tree **`nouveau` + Wayland** in 2024 once `nouveau` handled the dual-4K setup. | — |
| **July 2024** | Ubuntu 24.04 LTS (`nouveau`) | `6.8.0-x-generic` | 💥 Divide-by-zero oops in `nv50_disp_super_2_2_dp` whenever the 4K monitors went into standby or switched to HDMI. | ✅ Stable across daily input switching and standby cycles. | [FreeDesktop GitLab Issue #377](https://gitlab.freedesktop.org/drm/nouveau/-/issues/377) |
| **July 2024** | Mainline Stable | `6.9.9` | 💥 Same `RIP: 0010:nv50_disp_super_2_2_dp+0xa7/0x320 [nouveau]` crash; load climbs to `>= 1.0`, `reboot` hangs. | ✅ Stable; early return when `ior->dp.nr == 0`. | [GitLab MR !25 (`linux-6.9.y`)](https://gitlab.freedesktop.org/drm/nouveau/-/merge_requests/25) |
| **Aug 2024** | Mainline Stable | `6.10.y` | 💥 Bug still present in upstream `nv50.c`. | ✅ Patched locally and used daily for nearly two years without a crash. | [GitLab MR !27 (`linux-6.10.y`)](https://gitlab.freedesktop.org/drm/nouveau/-/merge_requests/27) |
| **July 2026** | Ubuntu 26.04 LTS / Mainline | `7.1.3` (Vanilla) | 💥 Tested clean mainline `7.1.3` without the patch: system froze within 24 hours on monitor standby, requiring a hard power reset and `fsck`. | — | Confirmed still unfixed in mainline 7.x. |
| **July–Oct 2026** | Ubuntu 26.04 LTS / Custom | `7.1.3-custom #2` | — | ✅ Patched and verified in `dmesg`. Standby transitions skip DP calculation cleanly and allow GPU PCI runtime suspend (`suspended`). | [LKML Thread (`69D67A9F-1A56...`)](https://lore.kernel.org/lkml/69D67A9F-1A56-4814-AE68-50559DED42AF@xs4all.nl/) & [`[PATCH v2]` (`msg54492`)](https://www.mail-archive.com/nouveau@lists.freedesktop.org/msg54492.html) |

---

## 2. Upstream Submission Log

### Phase 1: FreeDesktop GitLab (July–August 2024)
* **July 23, 2024 — [GitLab Issue #377](https://gitlab.freedesktop.org/drm/nouveau/-/issues/377):**
  Reported the kernel oops backtrace on Ubuntu 24.04 (`6.8.0.x`) and mainline `6.9.9`:
  ```text
  [di jul 23 10:28:25 2024] nouveau 0000:01:00.0: DRM: DDC responded, but no EDID for DP-2
  [di jul 23 10:28:25 2024] nouveau 0000:01:00.0: DRM: DDC responded, but no EDID for DP-3
  [di jul 23 10:28:26 2024] Workqueue: nvkm-disp nv50_disp_super [nouveau]
  [di jul 23 10:28:26 2024] RIP: 0010:nv50_disp_super_2_2_dp+0xa7/0x320 [nouveau]
  ```
* **Summer 2024 — [GitLab MR !25](https://gitlab.freedesktop.org/drm/nouveau/-/merge_requests/25) & [MR !27](https://gitlab.freedesktop.org/drm/nouveau/-/merge_requests/27):**
  Opened merge requests against `linux-6.9.y` and `linux-6.10.y` with the `ior->dp.nr == 0` guard.

### Phase 2: Mainline 7.1.3 & LKML Submission (July–October 2026)
* **July 16, 2026 — Initial LKML Patch ([msg53751](https://www.mail-archive.com/nouveau@lists.freedesktop.org/msg53751.html)):**
  Sent `[PATCH] drm/nouveau/disp: Prevent division-by-zero during DisplayPort link training transitions` (`Message-ID: 69D67A9F-1A56-4814-AE68-50559DED42AF@xs4all.nl`) to Nouveau maintainer **Lyude Paul** (`lyude@redhat.com`), **Danilo Krummrich** (`dakr@kernel.org`), `nouveau@lists.freedesktop.org`, `dri-devel@lists.freedesktop.org`, and `linux-kernel@vger.kernel.org`.
* **July 16–17, 2026 — Maintainer Feedback & Follow-Up ([msg53750](https://www.mail-archive.com/nouveau@lists.freedesktop.org/msg53750.html), [msg53752](https://www.mail-archive.com/nouveau@lists.freedesktop.org/msg53752.html)):**
  Lyude asked about the LLM-assisted email wording and asked for a single patch variant instead of two options. I replied with the background from the 2024 GitLab report and provided the single silent patch (`if (ior->dp.nr == 0) return;`).
* **August 5, 2026 — Status Update from Lyude Paul ([msg53903](https://www.mail-archive.com/nouveau@lists.freedesktop.org/msg53903.html)):**
  > *"JFYI - going to try to review/test this ASAP, just been sidetracked chasing some big runtime PM issues in nouveau atm :S"*
* **October 18–23, 2026 — Follow-Up & Commit Message Request ([msg54461](https://www.mail-archive.com/nouveau@lists.freedesktop.org/msg54461.html), [msg54482](https://www.mail-archive.com/nouveau@lists.freedesktop.org/msg54482.html)):**
  Lyude asked to restore my original, shorter 2024 commit message (*"it was easier to read IMO"*).
* **October 25, 2026 — `[PATCH v2]` Sent with Original 2024 Commit Message ([msg54492](https://www.mail-archive.com/nouveau@lists.freedesktop.org/msg54492.html)):**
  Submitted `[PATCH v2] drm/nouveau/disp: Prevent divide by zero after screen wake-up` (`Message-ID: EB2FB627-5EFE-4572-81D9-3D965C868C90@xs4all.nl`) with the original 2024 commit message restored.

---

## 3. Upstream Links

* **Lore LKML Thread:** https://lore.kernel.org/lkml/69D67A9F-1A56-4814-AE68-50559DED42AF@xs4all.nl/
* **Mail Archive (`nouveau@lists.freedesktop.org`):** https://www.mail-archive.com/search?l=nouveau@lists.freedesktop.org&q=Filius
* **FreeDesktop GitLab Issue #377:** https://gitlab.freedesktop.org/drm/nouveau/-/issues/377
