# The 2024 Linux Kernel Debugging Journey: `gdb`, `objdump`, and the `kgdboe` Dead End

This document covers the July–September 2024 debugging sessions on my ThinkPad T430 (`6.8.0-38-generic` → `6.9.9-custom` → `6.10.2-custom`) to track down the `nv50_disp_super_2_2_dp` division-by-zero crash: what worked (`objdump`, `gdb` on `nv50.o`, kernel boot debug flags), what turned into a dead end (`gdb vmlinux` missing module symbols, `kgdboe` hanging the target kernel over UDP, and testing a `nouveau_dp.c` AUX power change), and how the patch evolved.

---

## 1. Capturing the Crash via SSH & Kernel Boot Debug Parameters

### Why You Need SSH from a Second Machine
When this crash happens, **all screens stay black or frozen and the local keyboard stops responding completely** (even `Ctrl+Alt+F2` to switch to a virtual console does nothing). Sitting in front of the laptop, it looks like a total hardware lockup.

However, logging in via **SSH from a second computer** (`ssh arjan@192.168.1.57`) revealed that the Linux kernel, networking, and user space were still running in the background:
- Only the `nvkm-disp` display workqueue had crashed and locked up the display pipeline (`DRM: core notifier timeout` / `base-0: timeout`).
- Because the crashed kernel worker was stuck in D-state/uninterruptible wait, `uptime` showed the system load climbing above `1.0`, and running `sudo reboot` over SSH hung indefinitely waiting for the display subsystem to shut down.
- Having an active SSH session made it possible to inspect `sudo dmesg -T` live at the moment of the crash and run `sync` before holding down the power button (avoiding dirty root filesystem `fsck` runs on the next boot).

### Kernel Boot Debug Flags (`/etc/default/grub`)
To capture full DRM and Nouveau trace logs over SSH leading up to the freeze, I configured `/etc/default/grub` with extra debug flags:

```bash
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=6 nouveau.debug=info drm.debug=2 log_buf_len=16M"
# For deeper DRM atomic / DP AUX tracing:
# drm.debug=14 log_buf_len=16M
# Optional if testing screen wake-up / IOMMU interactions:
# intel_iommu=off iommu=pt
```

Whenever the external Iiyama 4K DisplayPort monitors went into standby, `dmesg` logged a division error (`divide error: 0000 [#1] PREEMPT SMP PTI` / `Oops: divide error`):
- On builds where `nv50_disp_super_2_2_dp` was not inlined (`6.9.9` / `7.1.3`):
  `RIP: 0010:nv50_disp_super_2_2_dp+0xa7/0x320 [nouveau]`
- On builds where the compiler inlined `static void nv50_disp_super_2_2_dp` into `nv50_disp_super_2_2`:
  `RIP: 0010:nv50_disp_super_2_2+0x284/0x430 [nouveau]`

---

## 2. Compiling the Kernel with Debug Symbols & Decoding Backtraces

If you want `gdb`, `objdump`, or `faddr2line` to map a crash address like `nv50_disp_super_2_2_dp+0xa7/0x320` to the exact C source file and line number, the kernel (and its modules) must be compiled with **DWARF debug symbols (`CONFIG_DEBUG_INFO=y`)**.

### Step 2.1: Configuring `.config` for Kernel & Module Debugging
Inside the extracted kernel source tree (e.g. `~/kernel/linux-7.1.3`), start from your running Ubuntu/Debian config, strip the distro signing keys (which otherwise break local builds), and enable `DEBUG_KERNEL` + `DEBUG_INFO`:

```bash
# 1. Reuse the running kernel's configuration as baseline
cp /boot/config-$(uname -r) .config

# 2. Clear canonical/distro signing keys so local .deb packaging succeeds
./scripts/config --file .config --disable MODULE_SIG
./scripts/config --file .config --set-str SYSTEM_TRUSTED_KEYS ""
./scripts/config --file .config --set-str CONFIG_SYSTEM_REVOCATION_KEYS ""

# 3. Enable debug symbols (DWARF) for vmlinux and all .ko / .o module objects
./scripts/config --file .config -d COMPILE_TEST -e DEBUG_KERNEL -e DEBUG_INFO

# Optional: increase compiled-in Nouveau debug limits
# ./scripts/config --file .config --set-val CONFIG_NOUVEAU_DEBUG 5
# ./scripts/config --file .config --set-val CONFIG_NOUVEAU_DEBUG_DEFAULT 3

yes "" | make oldconfig
```

### Step 2.2: Building `.deb` Packages (Including the `-dbg` Symbols Package)
```bash
# Build binary .deb packages across all CPU cores
# (Use bindeb-pkg when building from a kernel.org tarball, or deb-pkg in a git clone)
make -j $(getconf _NPROCESSORS_ONLN) bindeb-pkg LOCALVERSION=-custom

# Tip: if a parallel build fails and the compiler error is buried in parallel output,
# re-run single-threaded to see the exact failure:
# make -j 1 bindeb-pkg LOCALVERSION=-custom
```

When `CONFIG_DEBUG_INFO` is enabled, the build produces **four** `.deb` packages in the parent directory (`..`):
1. `linux-image-<ver>-custom_*.deb` — the bootable kernel and modules (`/lib/modules/<ver>-custom/`).
2. `linux-headers-<ver>-custom_*.deb` — headers for building external modules (`dkms`, `kgdboe`, etc.).
3. `linux-image-<ver>-custom-dbg_*.deb` (~1.5 GB) — **unstripped debug symbols** installed under `/usr/lib/debug/lib/modules/<ver>-custom/` and `/usr/lib/debug/vmlinux-<ver>-custom`.
4. `linux-libc-dev_*.deb` — userspace C library headers.

### Step 2.3: Pitfall — Why `gdb vmlinux` Cannot Find `[nouveau]` Symbols
My first attempt was loading the uncompressed debug kernel image (`vmlinux`) into GDB:

```text
$ gdb /usr/lib/debug/vmlinux-6.9.9-custom
Reading symbols from /usr/lib/debug/vmlinux-6.9.9-custom...
(gdb) list *(nv50_disp_super_2_2+0x284)
No symbol "nv50_disp_super_2_2" in current context.
```

**Why this fails:** When `dmesg` shows `[nouveau]` at the end of `RIP: 0010:nv50_disp_super_2_2_dp+0xa7/0x320 [nouveau]`, that function lives in the loadable kernel module (`CONFIG_DRM_NOUVEAU=m` → `nouveau.ko`), **not** in the core `vmlinux` binary.
*(Note: If GDB also complains that `scripts/gdb/vmlinux-gdb.py` auto-loading was declined, add `add-auto-load-safe-path /home/arjan/kernel/linux/scripts/gdb/vmlinux-gdb.py` to `~/.config/gdb/gdbinit`).*

### Step 2.4: Three Ways to Map `func+0xoffset` to the Exact C Source Line

#### Method A: `gdb` Directly on the Module Object (`nv50.o` or `nouveau.ko`)
Point `gdb` at the compiled object file (`drivers/gpu/drm/nouveau/nvkm/engine/disp/nv50.o`) in your build tree (or the unstripped `nouveau.ko` from the `-dbg` package):

```bash
cd ~/kernel/linux-6.9.9/drivers/gpu/drm/nouveau/nvkm/engine/disp
gdb nv50.o
```

Inside `gdb`, pass the exact `function+0xoffset` from the `RIP:` line in `dmesg` to `list *()`:

```text
(gdb) list *(nv50_disp_super_2_2+0x284)
0x3f84 is in nv50_disp_super_2_2 (drivers/gpu/drm/nouveau/nvkm/engine/disp/nv50.c:1094).
1089            v = head->asy.vblanks - head->asy.vblanke - 25;
1090            v = v * linkKBps;
1091            do_div(v, khz);
1092            v = v - ((36 / ior->dp.nr) + 3) - 1;
1093            nvkm_wr32(device, 0x610af4 + (head->id * 0x800), (v << 16) | h);
1094            nvkm_wr32(device, 0x610af8 + (head->id * 0x800),
1095                      active_syms_frac << 16 | active_syms_int);
1096
1097            link_data_rate = (khz * head->asy.or.depth / 8) / ior->dp.nr;
```
*(Or on non-inlined builds: `(gdb) list *(nv50_disp_super_2_2_dp+0xa7)`).*

#### Method B: `objdump` Interleaved Source + Assembly Disassembly
To inspect the generated x86_64 `div` instructions interleaved with C source lines and line numbers:

```bash
cd ~/kernel/linux-6.9.9/drivers/gpu/drm/nouveau/nvkm/engine/disp
objdump -SdCg nv50.o | less
# Or with relocations and explicit line numbers (per kernel.org bug-hunting guide):
objdump -r -S -l --disassemble nv50.o | less
```

#### Method C: Using the Kernel's `scripts/faddr2line` Utility
From the root of the kernel build tree, you can also run `scripts/faddr2line` against `nouveau.o` / `nouveau.ko` or `nv50.o`:

```bash
./scripts/faddr2line drivers/gpu/drm/nouveau/nvkm/engine/disp/nv50.o nv50_disp_super_2_2_dp+0xa7
```

Looking at `nv50_disp_super_2_2_dp()` in `nv50.c` immediately showed three divisions by `ior->dp.nr` (`12 / ior->dp.nr`, `36 / ior->dp.nr`, and `(khz * head->asy.or.depth / 8) / ior->dp.nr`) with no check that `ior->dp.nr` is non-zero.

---

## 3. Remote Kernel Debugging Dead End (`kgdboe` over Ethernet) & Current Status

On **August 18, 2024**, I also tried setting up live **remote kernel debugging over Ethernet (`kgdboe`)** from a second Linux machine (`192.168.1.58`) to inspect the T430 (`192.168.1.57`) when the crash happened, and reported my findings upstream in **[`sysprogs/kgdboe` Issue #21 ("Any plans for recent kernels? (6.11)")](https://github.com/sysprogs/kgdboe/issues/21)**.

### 3.1 Step 1: Compile Errors & Warnings on Kernel 6.9+ / 6.10+ / 6.11-rc3 (Aug 2024)
In August 2024, [`sysprogs/kgdboe`](https://github.com/sysprogs/kgdboe) had not been updated since kernel 5.15 / 6.2. Compiling it against `6.9.9-custom`, `6.10.2-custom`, and `6.11.0-rc3-custom` immediately ran into kernel API breakages and compiler errors/warnings:
- **Removed/Renamed Kernel APIs in 6.9+:**
  - `nethook.c:202`: `nr_irqs` was no longer exported to modules (had to be replaced with `irq_get_nr_irqs()`).
  - `irqsync.c:45`: `del_timer(&mgr->timer)` was removed in 6.9+ in favor of `timer_delete_sync(&mgr->timer)` (and `from_timer()` was later replaced by `timer_container_of()` in 6.16+).
  - `kgdboe_main.c`: `MODPOST` complained about a missing `MODULE_DESCRIPTION()`.
- **Pointer Conversion & Ring-Buffer Warnings in `kgdboe_io.c`:**
  - `kgdboe_io.c:175`: `initialization of 'int *' from 'long unsigned int' makes pointer from integer without a cast [-Wint-conversion]` on `int *_gro_normal_batch = kallsyms_lookup_name("gro_normal_batch");` (which newer GCC treats as a build error unless cast to `(int *)`).
  - `kgdboe_io.c:88`: `-Wmisleading-indentation` on `while (s_IncomingRingBufferReadPosition == s_IncomingRingBufferWritePosition)` without a trailing semicolon.

### 3.2 Step 2: Loading `kgdboe.ko` Worked, Followed by `QCfffffffe` & a Hung Kernel
After patching those build issues so `kgdboe.ko` compiled cleanly, I loaded it on the T430 (`192.168.1.57`) by passing the `kallsyms_lookup_name` address from `/proc/kallsyms` (since `kallsyms_lookup_name` is no longer exported to modules since Linux 5.7):

```bash
git clone https://github.com/sysprogs/kgdboe.git
cd kgdboe
make -C /lib/modules/$(uname -r)/build M=$(pwd) modules

sudo insmod kgdboe.ko \
  kallsyms_lookup_name_address=0x$(sudo cat /proc/kallsyms | grep 'T kallsyms_lookup_name' | awk '{print $1}') \
  device_name=eth0
```

Loading `kgdboe.ko` succeeded at first: it forced the T430 into single-core mode (taking CPUs 1–7 offline) and started listening on UDP port `31337`:

```text
[zo aug 18 18:17:32 2024] kgdboe: loading out-of-tree module taints kernel.
[zo aug 18 18:17:32 2024] netpoll: kgdboe: local IP 192.168.1.57
[zo aug 18 18:17:32 2024] kgdboe: single-core mode enabled. Shutting down all cores except #0. This is slower, but safer.
[zo aug 18 18:17:32 2024] smpboot: CPU 1 is now offline
...
[zo aug 18 18:17:32 2024] smpboot: CPU 7 is now offline
[zo aug 18 18:17:32 2024] KGDB: Registered I/O driver kgdboe
[zo aug 18 18:17:32 2024] kgdboe: Successfully initialized. Use the following gdb command to attach:
[zo aug 18 18:17:32 2024] 	target remote udp:192.168.1.57:31337
```

However, as soon as I started `gdb ./vmlinux` on the second machine and attached over UDP:

```text
(gdb) target remote udp:192.168.1.57:31337
warning: The remote protocol may be unreliable over UDP.
Some events may be lost, rendering further debugging impossible.
Malformed response to offset query, QCfffffffe
```

GDB immediately failed with `Malformed response to offset query, QCfffffffe` and **the target kernel on the T430 hung completely** (*"En dan hangt de remote kernel"*). That made `kgdboe` a dead end in August 2024, so I went back to `nvkm_error()` / `nvkm_warn()` logging and `gdb nv50.o` / `objdump` disassembly.

### 3.3 Why It Hung in 2024 & Current Status of `kgdboe` (2025–2026 Update)
Nearly a year after I opened **[`sysprogs/kgdboe` Issue #21](https://github.com/sysprogs/kgdboe/issues/21)**, upstream merged **[PR #23](https://github.com/sysprogs/kgdboe/pull/23)** and commit **[`d4b4f22`](https://github.com/sysprogs/kgdboe/commit/d4b4f22)** (*"Added support for Linux 6.9.0+ / Linux 6.14"*, Aug 2025), which revealed one of the key reasons why 6.9+ kernels failed after compiling:
1. **`gro_normal_batch` Moved into `struct net_hotdata` in Linux 6.9+:**
   In kernels `< 6.9`, `kgdboe_io_init()` looked up the standalone symbol `kallsyms_lookup_name("gro_normal_batch")` and set it to `1` so the Linux networking stack would not batch incoming UDP packets via Generic Receive Offload (GRO). In Linux 6.9+, `gro_normal_batch` was moved inside `struct net_hotdata net_hotdata` (`<net/hotdata.h>`). Because `kallsyms_lookup_name("gro_normal_batch")` returned `0` (`NULL`) on 6.9+, GRO packet batching remained active during the GDB UDP handshake:
   ```c
   // Fixed in sysprogs/kgdboe commit 68a4620 / d4b4f22 (Aug 2025):
   #if LINUX_VERSION_CODE < KERNEL_VERSION(6,9,0)
       int *_gro_normal_batch = kallsyms_lookup_name("gro_normal_batch");
       if (_gro_normal_batch)
           *_gro_normal_batch = 1;
   #else
       struct net_hotdata *_net_hotdata = (struct net_hotdata *)kallsyms_lookup_name("net_hotdata");
       if (_net_hotdata)
           _net_hotdata->gro_normal_batch = 1;
   #endif
   ```
2. **Remaining Limitations of `kgdboe` Today:**
   Even with the August 2025 fixes in [`sysprogs/kgdboe`](https://github.com/sysprogs/kgdboe), live GDB debugging over Ethernet (`netpoll`) on physical hardware remains fragile when regular network traffic is present on the same NIC (as noted by other contributors in [Issue #21](https://github.com/sysprogs/kgdboe/issues/21), `netpoll` ring-buffer sharing with the active NIC driver can still corrupt the GDB stub state and lock the target).
   - **What works reliably on bare metal today:**
     - **SSH + `dmesg -T`** (when only the display workqueue crashes, as in this Nouveau bug).
     - **`netconsole`** (`modprobe netconsole netconsole=@/,@192.168.1.58/`) to stream kernel `printk` / oops messages over UDP in real time even when a crash panics the whole kernel.
     - **`kdump` / `crash`** to capture a post-mortem `vmcore` across a warm kexec reboot, or **`objdump` / `gdb` on `.o` module files** (`Step 2.4` above) once you have the `RIP:` line.

---

## 4. Testing Candidate Fixes & Refining the Patch (Aug–Sep 2024)

### 4.1 Testing the `nouveau_dp.c` AUX Power Change (Did Not Fix the Crash)
During early discussions on [GitLab Issue #377](https://gitlab.freedesktop.org/drm/nouveau/-/issues/377), I also tested commenting out `drm_dp_dpcd_set_powered(&nv_connector->aux, false);` in `drivers/gpu/drm/nouveau/nouveau_dp.c` (local commit `50994e2c0ee2`):

```c
// Tested in drivers/gpu/drm/nouveau/nouveau_dp.c (Aug 2024):
if (ret == NOUVEAU_DP_NONE)
    // drm_dp_dpcd_set_powered(&nv_connector->aux, false);
```

That did not stop `ior->dp.nr` from dropping to `0` when the monitors went into standby, and the kernel still crashed in `nv50_disp_super_2_2_dp()`.

### 4.2 Moving the Guard from `nv50_disp_super_2_2()` into `nv50_disp_super_2_2_dp()`
My first working fix in August 2024 (local commits `1aedc41b40b7` and `66a3fdd3e368`) checked `ior->dp.nr != 0` at the call site in `nv50_disp_super_2_2()` and logged `"ArFi: ior->dp.nr == 0"`:

```c
// Initial Aug 2024 check in nv50_disp_super_2_2():
if (ior->type == SOR && ior->asy.proto == DP) {
    if (ior->dp.nr != 0) {
        nv50_disp_super_2_2_dp(head, ior); // only execute when dp.nr > 0
    } else {
        nvkm_error(subdev, "ArFi:  ior->dp.nr == 0 \n");
    }
}
```

The next time the monitors went into standby, instead of a kernel oops and a frozen laptop, `dmesg` logged `ArFi: ior->dp.nr == 0` and the system kept running normally.

For upstream submission, I moved that check to the start of `nv50_disp_super_2_2_dp()` itself:

```c
	/* If the DisplayPort link is inactive (0 lanes), skip configuration */
	if (ior->dp.nr == 0)
		return;
```

---

## 5. Finding the `lshw -c video` Display Wake-Up Trick

Once the kernel no longer crashed on monitor standby, I noticed a smaller quirk: when switching the Iiyama 4K monitors back from the MacBook Pro (HDMI) to the T430 (DisplayPort), the screens sometimes stayed black because the monitors did not send a new HPD pulse and the NVIDIA GPU had gone into PCI runtime suspend.

While looking around `/sys/devices/pci0000:00/0000:00:01.0/0000:01:00.0/graphics/fb1` in July 2024, I ran `lshw -c video`—and both 4K monitors woke up and came back on.

From my notes in `~/kernel/nouveau-debug/readme.txt` (July 2024):
> *"Huh? now xrandr shows all screens again!!! as if it was waked-up!!! I think i saw the backlight go on during: `lshw -c video`"*

Probing PCI via `lshw -c video` wakes `0000:01:00.0` (the NVS 5400M) out of PCI runtime suspend, allowing `nouveau` and `xrandr` to re-detect both DisplayPort monitors. That became the basis for [`scripts/wake-nouveau-dp.sh`](../scripts/wake-nouveau-dp.sh).
