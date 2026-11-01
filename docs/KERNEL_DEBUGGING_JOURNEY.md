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
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=6 nouveau.debug=info drm.debug=2"
# And for deeper DRM / DP AUX tracing:
# drm.debug=14 log_buf_len=16M
```

Whenever the external Iiyama 4K DisplayPort monitors went into standby, `dmesg` logged a division error (`divide error: 0000 [#1] PREEMPT SMP PTI` / `Oops: divide error`):
- On builds where `nv50_disp_super_2_2_dp` was not inlined (`6.9.9` / `7.1.3`):
  `RIP: 0010:nv50_disp_super_2_2_dp+0xa7/0x320 [nouveau]`
- On builds where the compiler inlined `static void nv50_disp_super_2_2_dp` into `nv50_disp_super_2_2`:
  `RIP: 0010:nv50_disp_super_2_2+0x284/0x430 [nouveau]`

---

## 2. Finding the Exact C Source Line (`vmlinux` vs. `nv50.o`)

### First Attempt: `gdb vmlinux` (Why It Failed)
My first attempt was loading the uncompressed debug kernel image (`vmlinux`) into GDB:

```text
$ gdb /usr/lib/debug/vmlinux-6.9.9-custom
Reading symbols from /usr/lib/debug/vmlinux-6.9.9-custom...
(gdb) list *(nv50_disp_super_2_2+0x284)
No symbol "nv50_disp_super_2_2" in current context.
```

Because `CONFIG_DRM_NOUVEAU=m` builds `nouveau` as a loadable kernel module (`nouveau.ko`) rather than compiling it into `vmlinux`, none of the `nv50_disp_*` symbols are in `vmlinux`.

### What Worked: Running `objdump` and `gdb` on `nv50.o`
Instead of `vmlinux`, I ran `objdump` and `gdb` directly against the compiled module object file (`drivers/gpu/drm/nouveau/nvkm/engine/disp/nv50.o`) in the kernel build tree:

```bash
cd ~/kernel/linux-6.9.9/drivers/gpu/drm/nouveau/nvkm/engine/disp
objdump -SdCg nv50.o | less
gdb nv50.o
```

Running `list *(nv50_disp_super_2_2+0x284)` inside `gdb nv50.o` mapped the instruction offset straight to the C source lines inside `nv50_disp_super_2_2_dp()`:

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
1098
```

Looking at that function showed three divisions by `ior->dp.nr` (`12 / ior->dp.nr`, `36 / ior->dp.nr`, and `(khz * head->asy.or.depth / 8) / ior->dp.nr`) with no check that `ior->dp.nr` is non-zero.

---

## 3. Remote Kernel Debugging Dead End (`kgdboe` over Ethernet)

On **August 18, 2024**, I also tried setting up live **remote kernel debugging over Ethernet (`kgdboe`)** from a second Linux machine (`192.168.1.58`) to inspect the T430 (`192.168.1.57`) when the crash happened.

### Loading `sysprogs/kgdboe` on the T430 (`192.168.1.57`)
I cloned and compiled [`sysprogs/kgdboe`](https://github.com/sysprogs/kgdboe) (Kernel GDB over Ethernet) against the running `6.10.2-custom` kernel and loaded it using the `kallsyms_lookup_name` address:

```bash
git clone https://github.com/sysprogs/kgdboe.git
cd kgdboe
make -C /lib/modules/$(uname -r)/build M=$(pwd) modules

sudo insmod kgdboe.ko \
  kallsyms_lookup_name_address=0x$(sudo cat /proc/kallsyms | grep 'T kallsyms_lookup_name' | awk '{print $1}') \
  device_name=eth0
```

Loading `kgdboe.ko` worked at first: it forced the T430 into single-core mode (taking CPUs 1–7 offline) and started listening on UDP port `31337`:

```text
[Aug18 11:02] kgdboe: Single-core mode enabled. Shutting down all cores except #0. This is slower, but safer.
[  +0.000006] kgdboe: you can try using multi-core mode by specifying thefollowing argument:
[  +0.000004]   insmod kgdboe.ko force_single_core = 0
[  +0.025812] smpboot: CPU 1 is now offline
[  +0.029934] smpboot: CPU 2 is now offline
[  +0.030956] smpboot: CPU 3 is now offline
[  +0.026859] smpboot: CPU 4 is now offline
[  +0.025216] smpboot: CPU 5 is now offline
[  +0.032009] smpboot: CPU 6 is now offline
[  +0.025847] smpboot: CPU 7 is now offline
[  +0.006129] kgdboe: capturing network traffic on eth0 ...
[  +0.000021] kgdb: Registered I/O driver kgdboe
[  +0.000005] kgdboe: successfully initialized. Use the following gdb command to attach:
[  +0.000003]   target remote udp:192.168.1.57:31337
```

### Why It Was a Dead End
When I started `gdb ./vmlinux` on the other machine and connected over UDP:

```text
(gdb) target remote udp:192.168.1.57:31337
warning: The remote protocol may be unreliable over UDP.
Some events may be lost, rendering further debugging impossible.
Malformed response to offset query, QCfffffffe
```

As soon as GDB connected over UDP port `31337`, it returned `Malformed response to offset query, QCfffffffe` and **the remote kernel on the T430 hung completely** (*"En dan hangt de remote kernel"*). That made `kgdboe` a dead end on `6.10.x`, so I went back to `nvkm_error()` / `nvkm_warn()` logging and object disassembly.

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
