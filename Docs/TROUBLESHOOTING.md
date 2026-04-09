# GoldISO Troubleshooting Guide

## Common Issues

### Build Failures

#### "oscdimg not found"
- **Cause**: Windows ADK not installed
- **Solution**: Run with `-SkipDependencyDownload:$false` or install ADK manually

#### "Source ISO not found"
- **Cause**: `Win11-25H2x64v2.iso` not in project root
- **Solution**: Place source ISO in project root, verify path in `Build-GoldISO.ps1`

#### "DISM mount failed"
- **Cause**: Mount directory in use or permissions issue
- **Solution**: Close any apps using `C:\Mount`, run as Administrator

### Driver Injection Issues

#### "Driver injection skipped - no drivers found"
- **Cause**: Drivers directory empty or incorrect path
- **Solution**: Ensure `Drivers/` contains driver `.inf` files

#### "Hash mismatch during download"
- **Cause**: Corrupted download or incorrect checksum in manifest
- **Solution**: Update `Config/download-manifest.json` with correct SHA256

### WIM Issues

#### "WIM index out of range"
- **Cause**: Invalid index in source ISO
- **Solution**: Use `-WimIndex 1` (typically Windows Pro)

#### "WIM mount read-only"
- **Cause**: Mount point already mounted
- **Solution**: Run `Dismount-WindowsImage -Path C:\Mount -Discard`

### FirstLogonCommand Failures

#### "Access denied" during OOBE
- **Cause**: Script requires Administrator
- **Solution**: Ensure autounattend.xml has `Administrator` password set

#### "Path not found" errors
- **Cause**: Embedded script paths incorrect
- **Solution**: Verify paths in `Config/autounattend.xml` match embedded files

## Validation Commands

```powershell
# Test environment
.\Scripts\Test-Environment.ps1

# Validate answer file
.\Scripts\Test-UnattendXML.ps1 -Verbose

# Run diagnostics
.\Scripts\Testing\Test-SystemHealth.ps1
```

## Logs

- Build logs: `Logs/` (project root)
- WIM setup logs: Inside WIM at `C:\Mount\Windows\Panther\setupact.log`
- FirstLogon logs: `C:\ProgramData\Winhance\Unattend\Logs\`

## Getting Help

1. Check test results: `.\Tests\Run-AllTests.ps1`
2. Review build logs in `Logs/`
3. Run health check: `.\Scripts\Testing\Test-SystemHealth.ps1`
4. Check GitHub issues