# Historical Kernel Test Matrix & Upstream Submission Timeline (2024–2026)

This document tracks every Linux kernel release tested on the **Lenovo ThinkPad T430 (NVIDIA NVS 5400M / GF108M)** docked in the **ThinkPad Mini Dock Plus Series 3 (Model 4338)** driving dual **32" Iiyama ProLite XB3288UHSU (`PL3288UH`) 4K** monitors via DisplayPort (`DP-2` and `DP-3`).

---

## 1. Tested Linux Kernel Matrix

| Date / Period | Distribution / Base | Kernel Version | Unpatched Behavior | Patched Behavior (`ior->dp.nr == 0` guard) | Upstream Artifact / Reference |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **July 2024** | Ubuntu 24.04 LTS | `6.8.0-x-generic` | 💥 Daily divide-by-zero oops in `nv50_disp_super_2_2_dp` when external 4K displays enter power-save standby or switch to HDMI input. | ✅ 100% stable; zero lockups across months of daily multi-input switching. | [FreeDesktop GitLab Issue #377](https://gitlab.freedesktop.org/drm/nouveau/-/issues/377) |
| **July 2024** | Mainline Stable | `6.9.9` | 💥 Identical `RIP: 0010:nv50_disp_super_2_2_dp+0xa7/0x320 [nouveau]` crash within 24h; system load spikes to `>= 1.0`, reboot hangs. | ✅ 100% stable; clean early-exit when `ior->dp.nr == 0`. | [GitLab MR !25 (`linux-6.9.y`)](https://gitlab.freedesktop.org/drm/nouveau/-/merge_requests/25) |
| **Aug 2024** | Mainline Stable | `6.10.y` | 💥 Crash still present in upstream `nv50.c`. | ✅ Patched locally and run continuously fornearly two years without a single display-triggered kernel panic. | [GitLab MR !27 (`linux-6.10.y`)](https://gitlab.freedesktop.org/drm/nouveau/-/merge_requests/27) |
| **July 2026** | Ubuntu 26.04 LTS / Mainline | `7.1.3` (Vanilla) | 💥 Booted clean mainline `7.1.3` without local patch: system froze within 24 hours when external monitors entered standby, requiring hard power reset and `fsck`. | — | Confirmed bug remains unfixed in mainline 7.x series. |
| **July–Oct 2026** | Ubuntu 26.04 LTS / Custom | `7.1.3-custom #2` | — | ✅ Patched with both verbose (`nvkm_warn`) and silent (`[PATCH v2]`) variants. Verified in `dmesg` that standby transitions safely skip DP configuration and allow GPU PCI runtime suspend (`suspended`). | [LKML Thread (`69D67A9F-1A56...`)](https://lore.kernel.org/lkml/69D67A9F-1A56-4814-AE68-50559DED42AF@xs4all.nl/) & [`[PATCH v2]` (`msg54492`)](https://www.mail-archive.com/nouveau@lists.freedesktop.org/msg54492.html) |

---

## 2. Chronological Upstream Communication Log

### Phase 1: Original Discovery & FreeDesktop GitLab (July–August 2024)
* **July 23, 2024 — [GitLab Issue #377](https://gitlab.freedesktop.org/drm/nouveau/-/issues/377):**
  Reported the full kernel oops backtrace on Ubuntu 24.04 (`6.8.0.x`) and mainline `6.9.9`:
  ```text
  [di jul 23 10:28:25 2024] nouveau 0000:01:00.0: DRM: DDC responded, but no EDID for DP-2
  [di jul 23 10:28:25 2024] nouveau 0000:01:00.0: DRM: DDC responded, but no EDID for DP-3
  [di jul 23 10:28:26 2024] Workqueue: nvkm-disp nv50_disp_super [nouveau]
  [di jul 23 10:28:26 2024] RIP: 0010:nv50_disp_super_2_2_dp+0xa7/0x320 [nouveau]
  ```
* **Summer 2024 — [GitLab MR !25](https://gitlab.freedesktop.org/drm/nouveau/-/merge_requests/25) & [MR !27](https://gitlab.freedesktop.org/drm/nouveau/-/merge_requests/27):**
  Opened merge requests against `linux-6.9.y` and `linux-6.10.y` demonstrating the early-return guard when `ior->dp.nr == 0`.

### Phase 2: Mainline 7.1.3 Rediscovery & LKML Submission (July–October 2026)
* **July 16, 2026 — Initial LKML Patch Submission ([msg53751](https://www.mail-archive.com/nouveau@lists.freedesktop.org/msg53751.html)):**
  Submitted `[PATCH] drm/nouveau/disp: Prevent division-by-zero during DisplayPort link training transitions` (`Message-ID: 69D67A9F-1A56-4814-AE68-50559DED42AF@xs4all.nl`) to Nouveau display maintainer **Lyude Paul** (`lyude@redhat.com`), co-maintainer **Danilo Krummrich** (`dakr@kernel.org`), `nouveau@lists.freedesktop.org`, `dri-devel@lists.freedesktop.org`, and `linux-kernel@vger.kernel.org`.
* **July 16, 2026 — Maintainer Reply from Lyude Paul ([msg53750](https://www.mail-archive.com/nouveau@lists.freedesktop.org/msg53750.html)):**
  Lyude asked whether generative AI was used in drafting the email/commit message and requested sending a single patch variant rather than dual Option A (silent) / Option B (verbose) diffs.
* **July 17, 2026 — Author Clarification ([msg53752](https://www.mail-archive.com/nouveau@lists.freedesktop.org/msg53752.html)):**
  Clarified that the root-cause analysis and C fix were manually debugged and authored in 2024 ([GitLab Issue #377](https://gitlab.freedesktop.org/drm/nouveau/-/issues/377)), while AI was only used in 2026 to help structure the submission email after re-encountering the freeze on kernel `7.1.3`. Provided the single silent patch (`if (ior->dp.nr == 0) return;`).
* **August 5, 2026 — Status Update from Lyude Paul ([msg53903](https://www.mail-archive.com/nouveau@lists.freedesktop.org/msg53903.html)):**
  > *"JFYI - going to try to review/test this ASAP, just been sidetracked chasing some big runtime PM issues in nouveau atm :S"*
* **October 18, 2026 — Friendly Follow-Up Ping ([msg54461](https://www.mail-archive.com/nouveau@lists.freedesktop.org/msg54461.html)):**
  Sent a gentle check-in asking if a standalone `[PATCH v2]` was desired.
* **October 23, 2026 — Reply from Lyude Paul ([msg54482](https://www.mail-archive.com/nouveau@lists.freedesktop.org/msg54482.html)):**
  > *"I will try to review this asap, unfortunately I am quite swamped and in the middle of moving - so I need to focus on the stuff that's assigned on my plate this week. I think the one thing that would be appreciated is if you could re-add the old commit message you had before generating the new one with an LLM - it was easier to read IMO."*
* **October 25, 2026 — `[PATCH v2]` Submitted with Original 2024 Commit Message ([msg54492](https://www.mail-archive.com/nouveau@lists.freedesktop.org/msg54492.html)):**
  Submitted `[PATCH v2] drm/nouveau/disp: Prevent divide by zero after screen wake-up` (`Message-ID: EB2FB627-5EFE-4572-81D9-3D965C868C90@xs4all.nl`) with the concise 2024 commit message restored. Currently awaiting final maintainer pickup into `drm-misc-next`.

---

## 3. Live Upstream Tracking Links

* **Canonical Lore LKML Thread:**  
  https://lore.kernel.org/lkml/69D67A9F-1A56-4814-AE68-50559DED42AF@xs4all.nl/
* **The Mail Archive (`nouveau@lists.freedesktop.org` Thread View):**  
  https://www.mail-archive.com/search?l=nouveau@lists.freedesktop.org&q=Filius
* **FreeDesktop GitLab Issue #377:**  
  https://gitlab.freedesktop.org/drm/nouveau/-/issues/377

