# The 2024 Kernel Debugging Journey: `gdb`, `objdump`, and the `kgdboe` Remote Debugging Dead-End

This document chronicles the original July–September 2024 investigation on the ThinkPad T430 (`6.8.0-38-generic` → `6.9.9-custom` → `6.10.2-custom`) that tracked down the `nv50_disp_super_2_2_dp` division-by-zero crash, including the tools that worked (`objdump`, `gdb` on module `.o` files, kernel boot debug flags), the dead ends (`gdb vmlinux` missing module symbols, `kgdboe` hanging the target kernel over UDP, and testing an early `nouveau_dp.c` AUX power patch), and the evolution of the fix.

---

## 1. Capturing the Crash with Kernel Boot Debug Parameters

To capture detailed DRM and Nouveau state transitions leading up to the freeze, `/etc/default/grub` was configured with verbose debug parameters:

```bash
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=6 nouveau.debug=info drm.debug=2"
# And for deeper DRM atomic / DP AUX tracing:
# drm.debug=14 log_buf_len=16M
```

When the external Iiyama 4K DisplayPort monitors went into standby, `dmesg` recorded the fatal division error (`divide error: 0000 [#1] PREEMPT SMP PTI` / `Oops: divide error`):
- On non-inlined builds (`6.9.9` / `7.1.3`):
  `RIP: 0010:nv50_disp_super_2_2_dp+0xa7/0x320 [nouveau]`
- On compiler-inlined builds (where `static void nv50_disp_super_2_2_dp` was inlined into `nv50_disp_super_2_2`):
  `RIP: 0010:nv50_disp_super_2_2+0x284/0x430 [nouveau]`

---

## 2. Pinpointing the Exact C Source Line (`vmlinux` vs. `nv50.o`)

### First Attempt: `gdb vmlinux` (Why It Failed)
Initially, we tried loading the uncompressed debug kernel image (`vmlinux`) into GDB:

```text
$ gdb /usr/lib/debug/vmlinux-6.9.9-custom
Reading symbols from /usr/lib/debug/vmlinux-6.9.9-custom...
(gdb) list *(nv50_disp_super_2_2+0x284)
No symbol "nv50_disp_super_2_2" in current context.
```

Because `CONFIG_DRM_NOUVEAU=m` builds `nouveau` as a loadable kernel module (`nouveau.ko`) rather than statically linking it into `vmlinux`, none of the `nv50_disp_*` symbols exist inside `vmlinux`.

### Breakthrough: Inspecting `nv50.o` with `objdump` and `gdb`
Instead of `vmlinux`, we pointed `objdump` and `gdb` directly at the compiled object file (`drivers/gpu/drm/nouveau/nvkm/engine/disp/nv50.o`) inside the kernel build tree:

```bash
cd ~/kernel/linux-6.9.9/drivers/gpu/drm/nouveau/nvkm/engine/disp
objdump -SdCg nv50.o | less
gdb nv50.o
```

Running `list *(nv50_disp_super_2_2+0x284)` inside `gdb nv50.o` immediately resolved the instruction offset to the exact C source lines inside `nv50_disp_super_2_2_dp()`:

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

Inspecting the surrounding lines showed three separate divisions by `ior->dp.nr` (`12 / ior->dp.nr`, `36 / ior->dp.nr`, and `(khz * head->asy.or.depth / 8) / ior->dp.nr`) with no check verifying that `ior->dp.nr > 0`.

---

## 3. The Remote Kernel Debugging Dead-End (`kgdboe` over Ethernet)

Before settling on printk/register tracing, on **August 18, 2024**, we attempted to set up live **remote kernel debugging over Ethernet (`kgdboe`)** from a second Linux machine (`192.168.1.58`) to inspect the T430 (`192.168.1.57`) live when the crash occurred.

### Setting up `sysprogs/kgdboe` on the T430 Target (`192.168.1.57`)
We cloned and compiled [`sysprogs/kgdboe`](https://github.com/sysprogs/kgdboe) (Kernel GDB over Ethernet) against the running custom kernel (`6.10.2-custom`) and loaded it via `kallsyms_lookup_name`:

```bash
git clone https://github.com/sysprogs/kgdboe.git
cd kgdboe
make -C /lib/modules/$(uname -r)/build M=$(pwd) modules

sudo insmod kgdboe.ko \
  kallsyms_lookup_name_address=0x$(sudo cat /proc/kallsyms | grep 'T kallsyms_lookup_name' | awk '{print $1}') \
  device_name=eth0
```

Loading `kgdboe.ko` succeeded in `dmesg`, forcing the T430 into single-core mode (taking CPUs 1 through 7 offline to avoid SMP race conditions in the network polling driver):

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

### Why `kgdboe` Turned Out to Be a Dead End
When we launched `gdb ./vmlinux` on the remote host and attached to the UDP socket:

```text
(gdb) target remote udp:192.168.1.57:31337
warning: The remote protocol may be unreliable over UDP.
Some events may be lost, rendering further debugging impossible.
Malformed response to offset query, QCfffffffe
```

The moment GDB sent its initial packet over UDP port `31337`, it returned `Malformed response to offset query, QCfffffffe` and **the T430 target kernel hard-locked completely** (*"En dan hangt de remote kernel"*). Between UDP packet loss in netpoll, modern kernel preemption/lockdep checks, and `kgdboe`'s out-of-tree hacks, remote kernel debugging over Ethernet proved completely unusable on 6.10.x—forcing us back to targeted `nvkm_error()` / `nvkm_warn()` instrumentation and object-file disassembly.

---

## 4. Testing Candidate Fixes & Evolution of the Patch (Aug–Sep 2024)

### 4.1 Testing Lyude Paul's `nouveau_dp.c` AUX Power Patch (Did Not Fix the Crash)
During initial discussions on [GitLab Issue #377](https://gitlab.freedesktop.org/drm/nouveau/-/issues/377), we also tested a hypothesis in `drivers/gpu/drm/nouveau/nouveau_dp.c` (commit `50994e2c0ee2` in our local test tree, `"lyude paul patch"`), commenting out the `drm_dp_dpcd_set_powered(&nv_connector->aux, false);` call when `ret == NOUVEAU_DP_NONE`:

```c
// Tested in drivers/gpu/drm/nouveau/nouveau_dp.c (Aug 2024):
if (ret == NOUVEAU_DP_NONE)
    // drm_dp_dpcd_set_powered(&nv_connector->aux, false);
```

While aimed at DP AUX power state handling, commenting out that line did **not** prevent `ior->dp.nr` from becoming `0` when the monitors entered standby, nor did it stop `nv50_disp_super_2_2_dp()` from dividing by zero.

### 4.2 Evolution from Caller-Side Guard (`nv50_disp_super_2_2`) to Callee Guard (`nv50_disp_super_2_2_dp`)
Our very first working fix in August 2024 (local commits `1aedc41b40b7` and `66a3fdd3e368`) guarded the call site inside `nv50_disp_super_2_2()` and logged an explicit `"ArFi: ior->dp.nr == 0"` marker:

```c
// Initial Aug 2024 prototype at the caller in nv50_disp_super_2_2():
if (ior->type == SOR && ior->asy.proto == DP) {
    if (ior->dp.nr != 0) {
        nv50_disp_super_2_2_dp(head, ior); // only execute when dp.nr > 0
    } else {
        nvkm_error(subdev, "ArFi:  ior->dp.nr == 0 \n");
    }
}
```

Sure enough, the next time the monitors went into standby, instead of a fatal kernel oops and frozen laptop, `dmesg` cleanly logged `ArFi: ior->dp.nr == 0` and the system stayed 100% responsive!

To make the fix self-contained and idiomatic for upstream submission, we moved the guard directly to the top of `nv50_disp_super_2_2_dp()`:

```c
	/* If the DisplayPort link is inactive (0 lanes), skip configuration */
	if (ior->dp.nr == 0)
		return;
```

---

## 5. Serendipitous Discovery: The `lshw -c video` Display Wake-Up Trick

Once the kernel no longer crashed when the monitors went to sleep, we noticed a secondary quirk: when switching the Iiyama 4K monitors back from the work laptop (HDMI) to the T430 (DisplayPort), the screens sometimes stayed black because the monitors didn't send an HPD pulse and the NVIDIA GPU had entered PCI runtime suspend.

While inspecting sysfs attributes under `/sys/devices/pci0000:00/0000:00:01.0/0000:01:00.0/graphics/fb1` in July 2024, we ran `lshw -c video` to check the PCI card state—and **both 4K monitors suddenly lit up!**

From `~/kernel/nouveau-debug/readme.txt` (July 2024):
> *"Huh? now xrandr shows all screens again!!! as if it was waked-up!!! I think i saw the backlight go on during: `lshw -c video`"*

Querying the PCI configuration space via `lshw -c video` forced the Linux kernel to wake `0000:01:00.0` (the NVS 5400M) out of PCI runtime suspend (`D3cold`/`D3hot` → `D0`), which in turn prompted `nouveau` and `xrandr` to re-detect both DisplayPort outputs. That discovery became the basis for [`scripts/wake-nouveau-dp.sh`](../scripts/wake-nouveau-dp.sh).
