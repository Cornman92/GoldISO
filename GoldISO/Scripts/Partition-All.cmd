@echo off
echo === Configuring Disk 0, 1, and 2 ===

REM ===================== DISK 0 =====================
> disk0.txt echo select disk 0
echo clean >> disk0.txt

REM 150 GB P-Apps (153600 MB)
echo create partition primary size=153600 >> disk0.txt
echo format fs=ntfs quick label="P-Apps" >> disk0.txt
echo assign letter=P >> disk0.txt

REM 60 GB Scratch (61440 MB)
echo create partition primary size=61440 >> disk0.txt
echo format fs=ntfs quick label="Scratch" >> disk0.txt
echo assign letter=S >> disk0.txt

REM Remaining space: SSD-OP (RAW) - create but do NOT format or assign letter
echo create partition primary >> disk0.txt
REM no format, no letter

diskpart /s disk0.txt



REM ===================== DISK 1 (1 TB HDD) =====================
> disk1.txt echo select disk 1
echo clean >> disk1.txt

REM Half for Media (476837 MB)
echo create partition primary size=476837 >> disk1.txt
echo format fs=ntfs quick label="Media" >> disk1.txt
echo assign letter=M >> disk1.txt

REM Half for Backups (476837 MB)
echo create partition primary size=476837 >> disk1.txt
echo format fs=ntfs quick label="Backups" >> disk1.txt
echo assign letter=B >> disk1.txt

diskpart /s disk1.txt



REM ===================== DISK 2 (OS Disk) =====================
> disk2.txt echo select disk 2
echo clean >> disk2.txt

REM EFI
echo create partition efi size=300 >> disk2.txt
echo format fs=fat32 quick label="System" >> disk2.txt

REM MSR
echo create partition msr size=16 >> disk2.txt

REM Recovery
echo create partition primary size=15360 >> disk2.txt
echo format fs=ntfs quick label="Recovery" >> disk2.txt

REM Windows - take rest for now
echo create partition primary >> disk2.txt
echo format fs=ntfs quick label="Windows" >> disk2.txt
echo assign letter=C >> disk2.txt

diskpart /s disk2.txt



REM ===================== SHRINK WINDOWS + OP ON DISK 2 =====================
> shrink2.txt echo select disk 2
echo select partition 4 >> shrink2.txt
echo shrink desired=107520 >> shrink2.txt
echo create partition primary size=92160 >> shrink2.txt
REM leave OP RAW, no format, no letter

diskpart /s shrink2.txt

echo === All disks configured ===
pause
