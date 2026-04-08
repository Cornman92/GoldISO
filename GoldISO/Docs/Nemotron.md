# GoldISO — Nemotron Agent Guide

**Last Updated**: 2026-04-08
**Model**: NVIDIA Nemotron (Llama-3.1-Nemotron-70B or similar) — strong technical reasoning, math, and systems analysis
**Best For**: Hardware compatibility analysis, performance optimization, driver strategy, system-level reasoning

---

## Your Strengths on This Project

Nemotron's technical depth and reasoning capabilities make you ideal for:

- Analyzing driver compatibility matrices for the target hardware
- Reasoning about DISM offline injection vs. post-boot installation tradeoffs
- Performance profiling analysis (Measure-BuildTime.ps1 output interpretation)
- Registry optimization reasoning (tweaks-system.cmd, tweaks-user.cmd)
- Disk partitioning math and Samsung NVMe overprovisioning calculations
- System health analysis from Get-SystemHealth.ps1 output

---

## Project Context

**GoldISO** targets a specific gaming workstation:

### Target Hardware Specification
| Component | Spec |
|-----------|------|
| Primary Storage | Samsung NVMe (Disk 2, ~950 GB total) |
| Secondary Storage | Disk 0 + Disk 1 (HDDs, configured post-install) |
| GPU | NVIDIA RTX 3060 Ti (driver 32.0.15.6094) |
| Mouse | Logitech G403 HERO (USB HID) |
| Audio | ASUS onboard audio |
| Network | Intel NIC |
| Chipset | Intel (MEI, Host Bridge) |

### Disk Layout (Disk 2 — CRITICAL)
```
Partition 1: EFI System    300 MB   (FAT32)
Partition 2: MSR           16 MB    (Reserved)
Partition 3: Windows C:    ~843 GB  (NTFS)
Partition 4: Recovery      15 GB    (NTFS/WinRE)
[Unallocated] ~90 GB                ← Samsung OP — DO NOT TOUCH
```

**Why the 90 GB gap exists**: Samsung NVMe drives benefit from leaving ~10% unallocated for wear leveling and sustained write performance. On a ~950 GB drive, ~90 GB overprovisioning is intentional engineering.

---

## Recommended Tasks for Nemotron

### 1. Driver Injection Strategy Analysis

**Current strategy:**
- **Offline (DISM into WIM)**: Intel MEI, ASUS chipset, network, storage, IDE/ATA, audio, monitors, USB controllers, software components, extensions
- **Post-boot (pnputil via FirstLogon)**: NVIDIA RTX 3060 Ti, Logitech G403 HERO

**Analyze**: Is this split optimal? Which drivers *must* be post-boot vs. can be offline?
- NVIDIA: Must be post-boot (DISM injection of full NVIDIA package causes WIM bloat and signature issues)
- Logitech HID: Can be offline, but post-boot is fine for non-boot-critical devices
- Intel MEI: Must be offline for proper specialize-phase initialization

### 2. Performance Tweaks Validation
Review `Scripts/tweaks-system.cmd` and `Scripts/tweaks-user.cmd` and evaluate:
- Which registry tweaks have documented performance impact
- Which tweaks may cause compatibility issues with Windows 11 25H2
- Whether any tweaks conflict with each other
- Whether tweaks for gaming (FSO, hardware-accelerated GPU scheduling) are present

### 3. RAM Disk Analysis
The system creates an 8 GB RAM disk at R: (`Scripts/createramdisk.cmd`).
Analyze:
- Optimal size for a gaming workstation (8 GB appropriate? System RAM?)
- Best use cases: browser cache, temp files, game shader cache
- Whether R: drive letter conflicts with common assignments
- Integration with Windows page file settings

### 4. Build Time Optimization
Given `Scripts/Measure-BuildTime.ps1` output, identify:
- Which phases dominate build time (DISM injection is typically the bottleneck)
- Whether package injection can be parallelized
- Whether the WIM dismount/remount cycle can be minimized
- Estimated time savings from each optimization

### 5. Power Plan Analysis
Review power scheme exports from settings migration and evaluate:
- Optimal power plan for gaming vs. background task workloads
- Whether "Ultimate Performance" plan is appropriate for this hardware
- Timer resolution settings impact on gaming frame times
- CPU parking settings for Intel hybrid architecture

### 6. Storage Performance Tuning
For the Samsung NVMe (Disk 2):
- Verify TRIM is enabled (should be by default on Windows 11)
- Evaluate whether Samsung Magician's RAPID mode should be enabled post-install
- Review write cache policy settings
- Assess whether the ~90 GB OP gap is sized correctly for a ~950 GB NVMe

---

## Systems Analysis Principles

When reasoning about this project:

1. **Boot path dependencies**: Drivers needed before Windows user mode loads must be offline-injected
2. **WIM size tradeoff**: Every offline-injected package increases WIM size and build time
3. **Signature enforcement**: DISM requires all injected drivers to have valid Microsoft signatures
4. **Hardware diversity**: The current config is for one specific machine; generalizing requires hardware profiles
5. **Samsung OP sizing**: ~10% of raw NAND is the Samsung recommendation; 90 GB on 950 GB ≈ 9.5% ✓

---

## Key Technical Files

| File | What to Analyze |
|------|----------------|
| `Scripts/tweaks-system.cmd` | HKLM registry tweaks — verify each has documented benefit |
| `Scripts/tweaks-user.cmd` | HKCU registry tweaks — check for conflicts with gaming tools |
| `Scripts/createramdisk.cmd` | RAM disk creation — size and drive letter |
| `Scripts/shrink-and-recovery.ps1` | Disk math — verify partition sizes add up |
| `Config/hardware-matrix.json` | Hardware profiles — evaluate completeness |
| `Scripts/Configure-RamDisk.ps1` | Full RAM disk configuration script |
| `Scripts/Get-SystemHealth.ps1` | Health check metrics — evaluate what's being measured |
| `Drivers/download-manifest.json` | Driver versions — identify stale versions |
