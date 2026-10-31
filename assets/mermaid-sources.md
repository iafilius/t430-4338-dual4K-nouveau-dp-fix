# Editable Mermaid Source Diagrams

This file preserves the editable [Mermaid](https://mermaid.js.org/) definitions corresponding to the custom high-resolution SVG infographics in `assets/`. GitHub renders these blocks natively as well.

---

## 1. Hybrid GPU & Shared Dual-4K Display Topology

```mermaid
flowchart TB
    subgraph T430["💻 Lenovo ThinkPad T430 (Ubuntu / Kernel 7.1.3-custom)"]
        direction LR
        IGPU["<b>Intel HD 4000 (iGPU)</b><br/>Driver: i915 (card1)<br/>Output: card1-LVDS-1"]
        DGPU["<b>NVIDIA NVS 5400M (GF108M)</b><br/>Driver: nouveau (card2)<br/>Engine: nv50_disp_super_2_2_dp()"]
        LCD["<b>Internal 14-inch WQHD Mod LCD</b><br/>2560 × 1440 @ 60.00Hz<br/>Canvas Offset: (0, 720)"]
        IGPU --> LCD
    end

    subgraph DOCK["🔌 Lenovo ThinkPad Mini Dock Plus Series 3 (Model 4338)"]
        DP2["Dock Port: card2-DP-2"]
        DP3["Dock Port: card2-DP-3"]
    end

    subgraph WORK["💼 Secondary Laptop: MacBook Pro (Work)"]
        HDMI1["1× Native HDMI Output"]
        HDMI2["1× USB-C to HDMI Adapter"]
    end

    subgraph MONITORS["🖥️ Dual 32-inch 4K Monitors (Total Span: 10240 × 2160)"]
        M1["<b>Monitor #1: Iiyama ProLite XB3288UHSU</b><br/>EDID: PL3288UH • 3840 × 2160 @ 30Hz<br/>Inputs: 1× DisplayPort, 2× HDMI<br/>Canvas Offset: (2560, 0)"]
        M2["<b>Monitor #2: Iiyama ProLite XB3288UHSU</b><br/>EDID: PL3288UH • 3840 × 2160 @ 30Hz<br/>Inputs: 1× DisplayPort, 2× HDMI<br/>Canvas Offset: (6400, 0)"]
    end

    DGPU ==>|"Proprietary Dock Connector"| DOCK
    DP2 ==>|"1× DisplayPort Cable"| M1
    DP3 ==>|"1× DisplayPort Cable"| M2
    HDMI1 -.->|"1× Native HDMI Cable"| M1
    HDMI2 -.->|"1× USB-C → HDMI Cable"| M2
```

---

## 2. The "End-of-Workday" DisplayPort Link Training Crash Sequence

```mermaid
sequenceDiagram
    autonumber
    participant WL as Secondary Work Laptop (HDMI)
    participant MON as 2x Iiyama XB3288UHSU (4K)
    participant DOCK as 4338 Dock (DP-2 / DP-3)
    participant NV as Nouveau Driver (nv50_disp_super_2_2_dp)
    participant OS as Linux Kernel / System State

    Note over WL,MON: Workday Session: Monitors switched to HDMI Input
    WL->>MON: Workday ends -> Work laptop enters sleep / shuts down
    MON->>DOCK: No active HDMI signal -> Monitors enter Power-Save Standby
    DOCK->>NV: HPD / Modeset Interrupt triggered on T430 wake-up
    Note over DOCK,NV: Active DisplayPort lane count drops to 0 (ior->dp.nr == 0)

    alt Unpatched Mainline Kernel (6.8.x / 6.9.9 / 6.10.y / 7.1.3)
        NV->>NV: Executes (12 / ior->dp.nr) and (36 / ior->dp.nr)
        NV--xOS: 💥 Divide-by-zero Kernel Oops in nvkm-disp workqueue!
        OS--xOS: 💀 Screen freeze, system load >= 1.0, reboot hangs -> Hard reset + fsck!
    else Patched Kernel ([PATCH v2] Early-Exit Guard)
        NV->>NV: Checks `if (ior->dp.nr == 0) return;`
        NV->>OS: ✅ Safely aborts DP symbol math on inactive link
        OS->>OS: 🛡️ NVS 5400M enters PCI runtime_status = suspended cleanly
    end
```

---

## 3. ThinkPad T430 64KB UEFI NVRAM Exhaustion & Recovery Flow

```mermaid
flowchart LR
    subgraph PROBLEM["❌ Why BIOS Halts with 'Non-volatile memory is full'"]
        A["64 KB Total NVRAM<br/>(65,516 Bytes)"] --> B["Lenovo System Vars<br/>~34.4 KB (52.5%)"]
        A --> C["Factory Secure Boot Keys<br/>(dbx + db + KEK + PK)<br/>26.7 KB (40.8%)"]
        A --> D["Remaining Free Space<br/>Only 4.3 KB (6.7%)"]
        E["Ubuntu sbkeysync<br/>(secureboot-db.service)"] -.->|"Re-writes 17.9KB dbx on boot"| C
        F["Nouveau Kernel Panics<br/>(efi-pstore dumps)"] -.->|"Fills remaining 4.3KB"| D
        D ==> G["💥 Fails 10 KB POST Margin<br/>BIOS F1 Halt on Reboot"]
    end

    subgraph SOLUTION["✅ Three-Step Permanent Fix (>31 KB Free)"]
        S1["1. BIOS Secure Boot:<br/>'Reset to Setup Mode'<br/>(Wipes 26.7 KB keys)"] --> S2["2. Purge Ubuntu Sync:<br/>apt purge secureboot-db<br/>+ disable fwupd uefi_dbx"]
        S2 --> S3["3. Disable Crash Dumps:<br/>GRUB efi_pstore.pstore_disable=1"]
        S3 ==> OK["🛡️ 31.1 KB Free (47.5%)<br/>Zero BIOS F1 Prompts"]
    end
```

