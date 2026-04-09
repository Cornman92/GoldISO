# GoldISO Disk Layout Templates

This directory contains reusable disk layout templates for GoldISO builds. These templates define partition structures for different hardware configurations.

## Available Templates

### SingleDisk-Generic

**Files:** `SingleDisk-Generic.xml`, `SingleDisk-Generic.json`

A simple single-disk layout ideal for most installations:

- **EFI System Partition:** 100MB (FAT32)
- **Microsoft Reserved Partition:** 16MB
- **Windows Partition:** Remaining space (NTFS, C:)

**Protected Drive Letters:** C (Windows only — removable media reassigned away from C)

**Best for:**

- Single SSD/NVMe installations
- Virtual machines
- Testing environments
- Laptops with single drive
- Budget builds

**Variables:**

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `DISK_ID` | 0 | Disk ID to use for installation |
| `EFI_SIZE` | 100 | EFI partition size in MB |
| `MSR_SIZE` | 16 | MSR partition size in MB |

---

### SingleDisk-DevGaming

**Files:** `SingleDisk-DevGaming.xml`, `SingleDisk-DevGaming.json`

Single-disk layout for development and gaming workstations. Windows installs to C: with optional `C:\Dev` and `C:\Gaming` folders created post-boot.

- **EFI System Partition:** 300MB (FAT32)
- **Microsoft Reserved Partition:** 16MB
- **Windows Partition:** ~330GB (NTFS, C:)
- **Recovery Partition:** 10GB (NTFS)

**Protected Drive Letters:** C (Windows only — removable media reassigned away from C)

**Folders Created by FirstLogonCommands:**
- `C:\Dev` — development projects and tools
- `C:\Gaming` — games and game launchers (Steam, Battle.net, Epic)

**Best for:**

- Single high-capacity NVMe/SSD (1TB+)
- Developer workstations that also game
- Builds where separate data drives are not available

**Variables:**

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `DISK_ID` | 0 | Disk ID for installation |
| `EFI_SIZE` | 300 | EFI partition size in MB |
| `MSR_SIZE` | 16 | MSR partition size in MB |
| `WINDOWS_PARTITION_SIZE` | 337920 (~330GB) | Windows partition size in MB |
| `RECOVERY_SIZE` | 10240 (10GB) | Recovery partition size in MB |

---

### GamerOS-3Disk (CUSTOM - LOCKED)

**Files:** `GamerOS-3Disk.xml`, `GamerOS-3Disk.json`

**⚠️ DO NOT MODIFY** - This is a custom-tailored layout with folder-based organization.

A simplified 3-disk layout using **folders instead of multiple partitions** for easier management.

**Disk Structure:**

- **Disk 0 (232GB SSD):**
  - Primary: ~210GB (**D:**, NTFS) with folders:
    - `D:\P-Apps` folder (apps)
    - `D:\Scratch` folder (temp)
  - SSD-OP: ~22GB (RAW, overprovisioning)

- **Disk 1 (1TB HDD):**
  - Primary: Full ~1TB (**E:**, NTFS) with folders:
    - `E:\Media` folder (media)
    - `E:\Backups` folder (backups)

- **Disk 2 (1TB Windows NVMe):**
  - EFI: 300MB (FAT32)
  - MSR: 16MB
  - Recovery: 15GB (NTFS, before Windows for boot performance)
  - Windows: ~826GB (**C:**, NTFS)
  - OP: 90GB (RAW, overprovisioning)

**Protected Drive Letters:** D, E, F, C, U, V, W, X, Y, Z, R, T, M

**Folder Structure Created by FirstLogonCommands:**
- `D:\P-Apps` - Applications folder
- `D:\Scratch` - Temp/scratch space
- `E:\Media` - Media storage
- `E:\Backups` - Backup storage

**Why Folders Instead of Partitions?**
- Simpler management - no juggling multiple drive letters
- More flexible space usage (folders share pool vs fixed partition sizes)
- Same protection via `ProtectLetters.ps1`: D, E, F, C (system); U, V, W (USB); X (WinPE); Y, Z (network); R (RamDisk); T, M (mounts)

**Best for:**

- High-end gaming PCs with organized folder structures
- Users who want simpler drive letter management
- Samsung NVMe drives requiring overprovisioning

**Variables:**

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `WINDOWS_DISK_ID` | 2 | Disk ID for Windows NVMe |
| `SSD_DISK_ID` | 0 | Disk ID for SSD |
| `HDD_DISK_ID` | 1 | Disk ID for HDD |
| `WINDOWS_PARTITION_SIZE` | 845838 (~826GB) | Windows partition for 1TB drive |
| `RECOVERY_PARTITION_SIZE` | 15360 (15GB) | Recovery partition |
| `OVERPROVISIONING_SIZE` | 92160 (90GB) | NVMe OP partition |

## Using Templates

### In New-EnhancedStandaloneBuild.ps1

```powershell
# Single disk (default)
.\New-EnhancedStandaloneBuild.ps1 -SourceISO "C:\Win11.iso" -DiskLayoutTemplate "SingleDisk"

# 3-disk gaming setup
.\New-EnhancedStandaloneBuild.ps1 -SourceISO "C:\Win11.iso" -DiskLayoutTemplate "GamerOS-3Disk"
```

### In Custom Build Scripts

Load the JSON template and substitute variables:

```powershell
$template = Get-Content "SingleDisk-Generic.json" | ConvertFrom-Json

# Create variable substitution table
$variables = @{
    "DISK_ID" = "0"
    "EFI_SIZE" = "100"
    "MSR_SIZE" = "16"
}

# Apply substitutions to XML
$xmlContent = Get-Content "SingleDisk-Generic.xml" -Raw
foreach ($var in $variables.Keys) {
    $xmlContent = $xmlContent -replace "{{$var}}", $variables[$var]
}
```

### Embedding in autounattend.xml

Use the XML templates directly in your answer file:

```xml
<settings pass="windowsPE">
  <component name="Microsoft-Windows-Setup">
    <!-- Insert DiskConfiguration from template here -->
    $xmlContent
  </component>
</settings>
```

## Template Format

### XML Templates

- Use `{{VARIABLE_NAME}}` syntax for substitution points
- Standard Microsoft unattend XML format
- Compatible with Windows SIM

### JSON Templates

- Define variables with defaults and descriptions
- Include disk structure metadata
- Support programmatic access and validation

## Naming Convention (IMPORTANT - DO NOT CHANGE)

All disk layout files **must** follow this naming pattern:

```
{LayoutName}.xml
{LayoutName}.json
```

**Valid Examples:**
- `GamerOS-3Disk.xml` / `GamerOS-3Disk.json` ✅
- `SingleDisk-Generic.xml` / `SingleDisk-Generic.json` ✅
- `SingleDisk-DevGaming.xml` / `SingleDisk-DevGaming.json` ✅

**Invalid Examples (DO NOT USE):**
- `GamerOS-3Disk-Layout.xml` ❌ (old naming, removed)
- `layout_gameros.xml` ❌ (underscores, wrong case)

The layout name is referenced by:
- `Build-GoldISO.ps1 -DiskLayout` parameter
- `Build-Autounattend.ps1 -DiskLayout` parameter
- Internal validation in `Build-Autounattend.ps1` (lines 34-35)

**Never rename existing layouts** without updating all references in build scripts.

## Creating Custom Templates

1. **Copy an existing template** as a starting point
2. **Follow the naming convention** above exactly
3. **Define your partition structure** using standard Windows partition types
4. **Add variable placeholders** for configurable values
5. **Create matching JSON** for programmatic access
6. **Update `Build-Autounattend.ps1` ValidateSet** to include new layout name
7. **Test thoroughly** in a VM before production use

## Important Notes

- **Disk IDs** are 0-based and depend on BIOS/UEFI enumeration order
- **Always verify** disk IDs in your target hardware configuration
- **Backup data** before applying any disk layout - all disks are wiped
- **UEFI systems** require EFI partition (FAT32, typically 100-300MB)
- **Recovery partitions** should use type ID `de94bba4-06d1-4d40-a16a-bfd50179d6ac`

## Troubleshooting

### Wrong Disk Selected

If Windows installs to the wrong disk:

1. Check disk enumeration in BIOS/UEFI
2. Adjust `DISK_ID` or `WINDOWS_DISK_ID` variables
3. Use diskpart in WinPE to verify disk numbering

### Partition Size Issues

- Sizes are in **MB** (megabytes)
- Use `Extend` for the last partition to fill remaining space
- Ensure total partition sizes don't exceed disk capacity

### Boot Issues

- EFI partition must be first and formatted FAT32
- MSR partition (16MB) is required for GPT disks
- Check secure boot settings match your partition scheme

## Related Files

- `Scripts/Build/New-EnhancedStandaloneBuild.ps1` - Uses these templates
- `autounattend.xml` - Project's main answer file
- `Scripts/Configure-SecondaryDrives.ps1` - Post-install drive configuration

## License

These templates are part of the GoldISO project and follow the same license terms.
