@echo off
setlocal EnableExtensions
title Dustnado - Windows Drive Cleaner
rem ============================================================================
rem   DUSTNADO  -  the smart whirlwind cleaner for Windows drives
rem   Author : Zeel Patel
rem   License: MIT  (see LICENSE)
rem   Usage  : double-click this file.   Options: /scan /yes /keepbrowsers /nodism /deep /help
rem ============================================================================
set "SELF=%~f0"
set "DUSTNADO_ARGS=%*"
set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PSEXE%" set "PSEXE=powershell"

fltmc >nul 2>&1 || net session >nul 2>&1
if errorlevel 1 (
    echo.
    echo   Dustnado needs Administrator rights. Click YES on the Windows prompt...
    echo %* | find /i "/elevated" >nul
    if not errorlevel 1 (
        echo.
        echo   Could not get Administrator rights.
        echo   Right-click Dustnado.bat and choose Run as administrator.
        pause
        exit /b 1
    )
    "%PSEXE%" -NoProfile -ExecutionPolicy Bypass -Command "try { Start-Process -FilePath $env:SELF -ArgumentList ($env:DUSTNADO_ARGS + ' /elevated').Trim() -Verb RunAs; exit 0 } catch { exit 1 }"
    if errorlevel 1 (
        echo.
        echo   Administrator permission was denied. Nothing was changed.
        pause
    )
    exit /b
)

mode con cols=110 lines=38 >nul 2>&1
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:SELF); $i=$s.LastIndexOf('::PS'+'CODE::'); & ([scriptblock]::Create($s.Substring($i+10)))"
exit /b
::PSCODE::
# =============================================================================
#  DUSTNADO - PowerShell engine (embedded in the .bat so that ONE file is all you need)
#  https://github.com/mr-zeel-38/dustnado  -  MIT License  -  (c) Zeel Patel
# =============================================================================
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

$AppName = 'Dustnado'
$AppVer  = '1.0.1'
$Author  = 'Zeel Patel'

$cli = (' ' + $env:DUSTNADO_ARGS + ' ').ToLower()

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host ''
    Write-Host '  Dustnado needs Windows PowerShell 5.1 (included in Windows 10 and 11).' -ForegroundColor Yellow
    Write-Host '  Please update Windows PowerShell and run again.' -ForegroundColor Yellow
    Start-Sleep -Seconds 8
    return
}

if ($cli -match '\s/(help|\?)\s') {
    Write-Host ''
    Write-Host "  $AppName $AppVer  -  the smart whirlwind cleaner for Windows drives   (by $Author, MIT)" -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Usage: Dustnado.bat [options]'
    Write-Host '    /scan          Scan only - show what could be freed, delete NOTHING'
    Write-Host '    /yes           Start immediately (skip the countdown screen)'
    Write-Host '    /keepbrowsers  Do not close open browsers (their caches will be partly skipped)'
    Write-Host '    /nodism        Skip the Windows component-store cleanup (DISM)'
    Write-Host '    /deep          Deeper DISM cleanup (/ResetBase) - installed Windows updates can no longer be uninstalled'
    Write-Host '    /help          Show this help'
    Write-Host ''
    Start-Sleep -Seconds 12
    return
}

# ------------------------------- SETTINGS -----------------------------------
# Edit these if you want to switch features on/off, or use the command-line options.
$DryRun           = [bool]($cli -match '\s/scan\s')
$AutoStart        = [bool]($cli -match '\s/yes\s')
$CloseBrowsers    = -not [bool]($cli -match '\s/keepbrowsers\s')
$CleanBrowsers    = $true
$CleanAppCaches   = $true
$CleanDevCaches   = $true
$CleanGradleCache = $false   # big, but re-downloaded on your next Gradle/Flutter build
$EmptyRecycleBin  = $true    # on every fixed drive
$RemoveOldWindows = $true    # Windows.old and leftover upgrade folders
$ComponentCleanup = -not [bool]($cli -match '\s/nodism\s')
$ResetBase        = [bool]($cli -match '\s/deep\s')   # /deep = deeper DISM cleanup (installed updates can no longer be uninstalled)
$ScanTimeoutSec   = 150      # max seconds to analyse one drive (huge drives are reported as partial)
$CountdownSeconds = 12
# -----------------------------------------------------------------------------

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = "$AppName $AppVer" } catch {}
Write-Host ''
Write-Host "  Loading $AppName ..." -ForegroundColor Cyan

# ---------------------- native helper: fast scan / delete --------------------
$nativeSource = @'
using System;
using System.IO;
using System.Threading;
using System.Collections.Generic;

public sealed class DustJob
{
    public volatile bool Done;
    public volatile bool Cancel;
    public volatile string Current = "";
    public long[] Results;
    long bytes;
    long files;
    int itemsDone;
    readonly string[] items;
    readonly bool delete;
    Thread th;

    public DustJob(string[] items, bool delete)
    {
        this.items = items;
        this.delete = delete;
        this.Results = new long[items.Length];
    }

    public int ItemsTotal { get { return items.Length; } }
    public int ItemsDone { get { return Thread.VolatileRead(ref itemsDone); } }
    public long Bytes { get { return Interlocked.Read(ref bytes); } }
    public long Files { get { return Interlocked.Read(ref files); } }

    public void Start()
    {
        th = new Thread(Run, 16 * 1024 * 1024);
        th.IsBackground = true;
        th.Start();
    }

    void Run()
    {
        try
        {
            for (int i = 0; i < items.Length; i++)
            {
                if (Cancel) break;
                Current = items[i];
                long r = 0;
                try { r = delete ? Delete(items[i], true) : Measure(items[i]); } catch { }
                Results[i] = r;
                Interlocked.Increment(ref itemsDone);
            }
        }
        catch { }
        Done = true;
    }

    void Add(long b, long f)
    {
        Interlocked.Add(ref bytes, b);
        Interlocked.Add(ref files, f);
    }

    // Size of a file or folder tree (junctions / symlinks are NOT followed).
    public long Measure(string path)
    {
        long total = 0;
        try
        {
            if (File.Exists(path)) { long l = new FileInfo(path).Length; Add(l, 1); return l; }
            if (!Directory.Exists(path)) { return 0; }
            if ((new DirectoryInfo(path).Attributes & FileAttributes.ReparsePoint) != 0) { return 0; }
        }
        catch { return 0; }
        Stack<string> stack = new Stack<string>();
        stack.Push(path);
        while (stack.Count > 0)
        {
            if (Cancel) break;
            string d = stack.Pop();
            Current = d;
            DirectoryInfo di;
            try { di = new DirectoryInfo(d); } catch { continue; }
            long dirBytes = 0; long dirFiles = 0;
            try
            {
                foreach (FileInfo f in di.EnumerateFiles())
                {
                    try { dirBytes += f.Length; dirFiles++; } catch { }
                }
            }
            catch { }
            total += dirBytes;
            Add(dirBytes, dirFiles);
            try
            {
                foreach (DirectoryInfo s in di.EnumerateDirectories())
                {
                    try { if ((s.Attributes & FileAttributes.ReparsePoint) == 0) { stack.Push(s.FullName); } } catch { }
                }
            }
            catch { }
        }
        return total;
    }

    long DelFile(FileInfo f)
    {
        long len = 0;
        try
        {
            len = f.Length;
            Current = f.FullName;
            f.Attributes = FileAttributes.Normal;
            f.Delete();
            Add(len, 1);
            return len;
        }
        catch { return 0; }
    }

    // Deletes a file or folder tree. Locked / protected items are skipped. Returns bytes freed.
    public long Delete(string path, bool removeRoot)
    {
        long freed = 0;
        if (Cancel) return 0;
        try
        {
            if (path.Length > 240 && !path.StartsWith(@"\\?\")) { path = @"\\?\" + path; }
            if (File.Exists(path)) { return DelFile(new FileInfo(path)); }
            if (!Directory.Exists(path)) { return 0; }
            DirectoryInfo root = new DirectoryInfo(path);
            if ((root.Attributes & FileAttributes.ReparsePoint) != 0)
            {
                try { root.Delete(); } catch { }
                return 0;
            }
            List<FileInfo> fl = new List<FileInfo>();
            try { foreach (FileInfo f in root.EnumerateFiles()) { fl.Add(f); } } catch { }
            foreach (FileInfo f in fl) { freed += DelFile(f); }
            List<DirectoryInfo> dl = new List<DirectoryInfo>();
            try { foreach (DirectoryInfo s in root.EnumerateDirectories()) { dl.Add(s); } } catch { }
            foreach (DirectoryInfo s in dl) { freed += Delete(s.FullName, true); }
            if (removeRoot)
            {
                try { root.Attributes = FileAttributes.Normal; root.Delete(false); } catch { }
            }
        }
        catch { }
        return freed;
    }
}
'@
try { Add-Type -TypeDefinition $nativeSource -ErrorAction Stop } catch {
    Write-Host ''
    Write-Host '  Dustnado could not start its scan engine (.NET compile is blocked on this PC).' -ForegroundColor Yellow
    Write-Host '  This can happen with strict security policies. Nothing was changed.' -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    return
}

# -------------------------------- environment --------------------------------
$SD = $env:SystemDrive; if (-not $SD) { $SD = 'C:' }
$DriveLetter = $SD.Substring(0, 1).ToUpper()
$WD = $env:SystemRoot; if (-not $WD) { $WD = "$SD\Windows" }
$PD = $env:ProgramData; if (-not $PD) { $PD = "$SD\ProgramData" }

$UsersRoot = "$SD\Users"
if ($env:USERPROFILE) { $pr = Split-Path $env:USERPROFILE -Parent; if ($pr -and (Test-Path -LiteralPath $pr)) { $UsersRoot = $pr } }

$OSName = 'Windows'
try { $OSName = ((Get-CimInstance Win32_OperatingSystem).Caption -replace '^Microsoft\s+', '').Trim() } catch {}

$Drives = @()
foreach ($d in [IO.DriveInfo]::GetDrives()) {
    try {
        if ($d.DriveType -eq 'Fixed' -and $d.IsReady -and $d.TotalSize -gt 0) {
            $letter = $d.Name.Substring(0, 1).ToUpper()
            $Drives += [pscustomobject]@{ Letter = $letter; Root = $d.Name; Label = [string]$d.VolumeLabel; Format = [string]$d.DriveFormat; Total = [int64]$d.TotalSize; IsSystem = ($letter -eq $DriveLetter) }
        }
    } catch {}
}
$Drives = @($Drives | Sort-Object @{ Expression = { $_.IsSystem }; Descending = $true }, Letter)
if ($Drives.Count -eq 0) {
    Write-Host '  No fixed drives were detected. Nothing to do.' -ForegroundColor Yellow
    Start-Sleep -Seconds 6
    return
}

$skipProfiles = @('Public', 'Default', 'Default User', 'All Users', 'WDAGUtilityAccount')
$Profiles = @(Get-ChildItem -LiteralPath $UsersRoot -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { ($skipProfiles -notcontains $_.Name) -and (Test-Path -LiteralPath (Join-Path $_.FullName 'AppData\Local')) } |
    ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; UP = $_.FullName; LA = (Join-Path $_.FullName 'AppData\Local'); RA = (Join-Path $_.FullName 'AppData\Roaming') }
    })
if ($Profiles.Count -eq 0 -and $env:USERPROFILE) {
    $Profiles = @([pscustomobject]@{ Name = $env:USERNAME; UP = $env:USERPROFILE; LA = $env:LOCALAPPDATA; RA = $env:APPDATA })
}

# ------------------------------- shared state --------------------------------
$script:SW = [Diagnostics.Stopwatch]::StartNew()
$script:LastDraw = 0
$script:Spin = 0
$script:DoneW = 0
$script:CurW = 0
$script:TotalW = 1
$script:FreedDone = [int64]0
$script:CurFreed = [int64]0
$script:DelDone = [int64]0
$script:DelNow = [int64]0
$script:FilesAllDone = [int64]0
$script:FilesAllNow = [int64]0
$script:CurIdx = 0
$script:CurName = ''
$script:Step = -1
$script:Detail = ''
$script:LiveKind = 'idle'
$script:LiveText = ''
$script:Token = [int64]0
$script:TokenSeen = [int64]-1
$script:LastChangeMs = 0
$script:RateMs = 0
$script:RateFiles = [int64]0
$script:Rate = [double]0
$script:RateHist = New-Object System.Collections.Generic.List[double]
$script:TaskFreed = [int64]0
$script:TaskNote = ''
$script:TaskSkip = $false
$script:TaskPartial = $false
$script:StoppedSvc = @()
$script:Scan = @{}
$script:Hogs = @()
$script:Tips = @()
$script:DriveBefore = @{}
$script:TaskTop = 0
$script:SkipPathGuard = $false

# ------------------------------- UI primitives -------------------------------
$cB    = [string][char]0x2588
$cL    = [string][char]0x2591
$cM    = [string][char]0x2592
$cD    = [string][char]0x2593
$cH    = [string][char]0x2550
$cV    = [string][char]0x2551
$cLine = [string][char]0x2500
$cOK   = [string][char]0x221A
$cRun  = [string][char]0x25BA
$cDot  = [string][char]0x00B7
$cArr  = [string][char]0x2192
$cLive = [string][char]0x25CF
$sparkChars = @(0x2581, 0x2582, 0x2583, 0x2584, 0x2585, 0x2586, 0x2587, 0x2588) | ForEach-Object { [string][char]$_ }

function Put {
    param([int]$X, [int]$Y, [string]$Text, [string]$Fg = 'Gray')
    try { [Console]::SetCursorPosition($X, $Y); Write-Host $Text -NoNewline -ForegroundColor $Fg } catch {}
}

function Clamp01 {
    param([double]$x)
    if ($x -lt 0) { return [double]0 }
    if ($x -gt 1) { return [double]1 }
    return $x
}

function Fit {
    param([string]$s, [int]$w)
    if ($null -eq $s) { $s = '' }
    if ($s.Length -gt $w) { return $s.Substring(0, [math]::Max(0, $w)) }
    return $s.PadRight($w)
}

function Fit-Mid {
    param([string]$s, [int]$w)
    if ($null -eq $s) { $s = '' }
    if ($s.Length -le $w) { return $s.PadRight($w) }
    if ($w -lt 8) { return $s.Substring(0, $w) }
    $keep = $w - 3
    $left = [int][math]::Floor($keep * 0.35)
    $right = $keep - $left
    return ($s.Substring(0, $left) + '...' + $s.Substring($s.Length - $right))
}

function Format-Size {
    param([double]$b)
    if ($b -ge 1GB) { return ('{0:N2} GB' -f ($b / 1GB)) }
    if ($b -ge 1MB) { return ('{0:N1} MB' -f ($b / 1MB)) }
    if ($b -ge 1KB) { return ('{0:N0} KB' -f ($b / 1KB)) }
    return ('{0:N0} B' -f $b)
}

function Get-Free {
    param([string]$Letter)
    try { $d = New-Object System.IO.DriveInfo($Letter); return [int64]$d.AvailableFreeSpace } catch { return [int64]0 }
}

function Show-Bar {
    # Frac >= 0 : normal bar (with optional blinking head).  Frac < 0 : moving (indeterminate) bar.
    param([int]$X, [int]$Y, [int]$Width, [double]$Frac, [string]$Fg = 'Cyan', [bool]$Active = $false, [bool]$Blink = $false)
    try {
        [Console]::SetCursorPosition($X, $Y)
        Write-Host '[' -NoNewline -ForegroundColor DarkGray
        if ($Frac -ge 0) {
            if ($Frac -gt 1) { $Frac = 1 }
            $fill = [int][math]::Floor($Frac * $Width)
            if ($Active -and $fill -ge 1 -and $fill -lt $Width) {
                if ($fill -gt 1) { Write-Host ($cB * ($fill - 1)) -NoNewline -ForegroundColor $Fg }
                if ($Blink) { Write-Host $cB -NoNewline -ForegroundColor White } else { Write-Host $cD -NoNewline -ForegroundColor $Fg }
            } elseif ($fill -gt 0) {
                Write-Host ($cB * $fill) -NoNewline -ForegroundColor $Fg
            }
            $rest = $Width - $fill
            if ($rest -gt 0) {
                if ($Active -and $fill -lt 1) {
                    if ($Blink) { Write-Host $cD -NoNewline -ForegroundColor $Fg } else { Write-Host $cM -NoNewline -ForegroundColor DarkGray }
                    $rest--
                }
                if ($rest -gt 0) { Write-Host ($cL * $rest) -NoNewline -ForegroundColor DarkGray }
            }
        } else {
            $seg = 10
            $pos = (($script:Spin * 2) % ($Width + $seg)) - $seg
            $s = [math]::Max(0, $pos)
            $e = [math]::Min($Width, $pos + $seg)
            $mid = [math]::Max(0, $e - $s)
            $right = $Width - $s - $mid
            if ($s -gt 0)     { Write-Host ($cL * $s) -NoNewline -ForegroundColor DarkGray }
            if ($mid -gt 0)   { Write-Host ($cB * $mid) -NoNewline -ForegroundColor $Fg }
            if ($right -gt 0) { Write-Host ($cL * $right) -NoNewline -ForegroundColor DarkGray }
        }
        Write-Host ']' -NoNewline -ForegroundColor DarkGray
    } catch {}
}

function Draw-Banner {
    param([string]$Badge = '', [string]$BadgeColor = 'Green')
    $W = $script:W
    $inner = $W - 2
    Put 1 0 ([string][char]0x2554 + ($cH * $inner) + [string][char]0x2557) 'Cyan'
    for ($r = 1; $r -le 4; $r++) { Put 1 $r $cV 'Cyan'; Put 2 $r (' ' * $inner) 'Gray'; Put $W $r $cV 'Cyan' }
    Put 1 5 ([string][char]0x255A + ($cH * $inner) + [string][char]0x255D) 'Cyan'

    # tornado logo (the "dust devil")
    Put 4 1 ([string][char]0x2584 * 13) 'Cyan'
    Put 5 2 ([string][char]0x2580 + ($cD * 9) + [string][char]0x2580) 'Cyan'
    Put 7 3 ([string][char]0x2580 + ($cM * 5) + [string][char]0x2580) 'DarkCyan'
    Put 9 4 ([string][char]0x2580 + ($cL * 1) + [string][char]0x2580) 'DarkCyan'
    Put 3 1 $cDot 'DarkGray'; Put 18 1 $cDot 'DarkGray'; Put 2 3 $cDot 'DarkGray'; Put 16 2 ([string][char]0x00B0) 'DarkGray'

    # title in half-block letters: D U S T N A D O
    $t1 = ([string][char]0x2588 + [char]0x2580 + [char]0x2584) + ' ' + ([string][char]0x2588 + ' ' + [char]0x2588) + ' ' + ([string][char]0x2588 + [char]0x2580) + ' ' + ([string][char]0x2580 + [char]0x2588 + [char]0x2580) + ' ' + ([string][char]0x2588 + [char]0x2584 + ' ' + [char]0x2588) + ' ' + ([string][char]0x2584 + [char]0x2580 + [char]0x2588) + ' ' + ([string][char]0x2588 + [char]0x2580 + [char]0x2584) + ' ' + ([string][char]0x2588 + [char]0x2580 + [char]0x2588)
    $t2 = ([string][char]0x2588 + [char]0x2584 + [char]0x2580) + ' ' + ([string][char]0x2588 + [char]0x2584 + [char]0x2588) + ' ' + ([string][char]0x2584 + [char]0x2588) + ' ' + (' ' + [string][char]0x2588 + ' ') + ' ' + ([string][char]0x2588 + ' ' + [char]0x2580 + [char]0x2588) + ' ' + ([string][char]0x2588 + [char]0x2580 + [char]0x2588) + ' ' + ([string][char]0x2588 + [char]0x2584 + [char]0x2580) + ' ' + ([string][char]0x2588 + [char]0x2584 + [char]0x2588)
    Put 22 1 $t1 'Yellow'
    Put 22 2 $t2 'Yellow'
    Put 22 3 'The smart whirlwind cleaner for Windows drives' 'Cyan'
    Put 22 4 'by ' 'DarkGray'
    Put 25 4 $Author 'White'
    Put (26 + $Author.Length) 4 ("   $cDot   MIT License   $cDot   v$AppVer") 'DarkGray'
    if ($Badge) {
        $b = ' ' + $Badge + ' '
        Put ($W - $b.Length - 2) 1 $b $BadgeColor
    }
}

function Init-Layout {
    $ww = 120; $wh = 30
    try { $ww = [Console]::WindowWidth; $wh = [Console]::WindowHeight } catch {}
    $script:WinW = $ww
    $script:WinH = $wh
    $script:W  = [int][math]::Max(84, [math]::Min(100, $ww - 2))
    $script:BW = $script:W - 46
    $script:NW = [int][math]::Max(30, $script:W - 52)
    $script:nD = [int][math]::Max(1, [math]::Min($Drives.Count, 4))
    $script:rDrive0  = 7
    $script:rOverall = $script:rDrive0 + $script:nD + 1
    $script:rCurrent = $script:rOverall + 1
    $script:rLive    = $script:rCurrent + 1
    $script:rHdr     = $script:rLive + 2
    $script:rTask0   = $script:rHdr + 1
    $cnt = 13; if ($script:Tasks) { $cnt = $script:Tasks.Count }
    $script:Vis = [int][math]::Max(4, [math]::Min($cnt, $wh - $script:rTask0 - 3))
    $script:rFoot = $script:rTask0 + $script:Vis + 1
    $script:TaskTop = 0
}

function Draw-Drives {
    param([int]$Y0)
    for ($i = 0; $i -lt $script:nD; $i++) {
        $dv = $Drives[$i]
        $free = Get-Free $dv.Letter
        $used = $dv.Total - $free; if ($used -lt 0) { $used = 0 }
        $pct = $used / [double]$dv.Total
        $col = 'Green'; if ($pct -gt 0.75) { $col = 'Yellow' }; if ($pct -gt 0.90) { $col = 'Red' }
        $tag = 'DATA'
        if ($dv.IsSystem) { $tag = 'SYSTEM' } elseif ($dv.Label) { $tag = $dv.Label }
        Put 2 ($Y0 + $i) ($dv.Letter + ':') 'Cyan'
        Put 5 ($Y0 + $i) (Fit $tag 6) 'DarkGray'
        Show-Bar 12 ($Y0 + $i) $script:BW $pct $col
        Put ($script:W - 30) ($Y0 + $i) (Fit ('{0:N1}% used | {1} free' -f ($pct * 100), (Format-Size $free)) 30) 'White'
    }
}

function Draw-Task {
    param([int]$i)
    if ($i -lt $script:TaskTop -or $i -ge ($script:TaskTop + $script:Vis)) { return }
    $t = $script:Tasks[$i]
    $y = $script:rTask0 + ($i - $script:TaskTop)
    $ic = $cDot; $c = 'DarkGray'; $nc = 'DarkGray'
    switch ($t.Status) {
        'running' { $ic = $cRun; $c = 'Yellow'; $nc = 'White' }
        'done'    { $ic = $cOK;  $c = 'Green';  $nc = 'Gray' }
        'skipped' { $ic = '-';   $c = 'DarkGray'; $nc = 'DarkGray' }
    }
    $nw = $script:NW
    Put 3 $y $ic $c
    Put 6 $y (Fit $t.Name $nw) $nc
    $info = ''; $ic2 = 'DarkGray'
    if ($t.Status -eq 'done') {
        if ($t.Freed -gt 0) { $info = Format-Size $t.Freed; $ic2 = 'Green' } else { $info = '-' }
    }
    Put (7 + $nw) $y ($info.PadLeft(11)) $ic2
    $nx = 19 + $nw
    Put $nx $y (Fit ([string]$t.Note) ($script:W - $nx + 1)) 'DarkGray'
}

function Draw-Tasks {
    $n = $script:Tasks.Count
    $hdr = ($cLine * 3) + ' TASKS  ' + ('({0}-{1} of {2}) ' -f ($script:TaskTop + 1), ([math]::Min($n, $script:TaskTop + $script:Vis)), $n)
    Put 2 $script:rHdr ($hdr + ($cLine * [math]::Max(0, $script:W - $hdr.Length - 1))) 'DarkGray'
    for ($k = 0; $k -lt $script:Vis; $k++) {
        $i = $script:TaskTop + $k
        if ($i -lt $n) { Draw-Task $i } else { Put 2 ($script:rTask0 + $k) (' ' * ($script:W - 2)) 'Gray' }
    }
}

function Set-TaskTop {
    param([int]$Cur)
    $n = $script:Tasks.Count
    $top = 0
    if ($n -gt $script:Vis) { $top = [int][math]::Max(0, [math]::Min($n - $script:Vis, $Cur - [int][math]::Floor($script:Vis / 2))) }
    if ($top -ne $script:TaskTop) { $script:TaskTop = $top; Draw-Tasks }
}

function Set-Live {
    param([string]$Kind = 'idle', [string]$Text = '', [double]$Step = -1, [string]$Detail = '')
    $script:LiveKind = $Kind; $script:LiveText = $Text; $script:Step = $Step; $script:Detail = $Detail
}

function Update-UI {
    param([switch]$Force)
    $ms = $script:SW.ElapsedMilliseconds
    if (-not $Force -and (($ms - $script:LastDraw) -lt 70)) { return }
    $script:LastDraw = $ms
    $script:Spin++
    $blink = (([int][math]::Floor($ms / 350)) % 2) -eq 0
    $W = $script:W; $BW = $script:BW; $tx = $W - 30

    # activity tracking (rate + "is it stuck?" watchdog)
    if ($script:Token -ne $script:TokenSeen) { $script:TokenSeen = $script:Token; $script:LastChangeMs = $ms }
    if (($ms - $script:RateMs) -ge 250) {
        $dt = [math]::Max(0.05, ($ms - $script:RateMs) / 1000.0)
        $r = [math]::Max([double]0, ($script:FilesAllNow - $script:RateFiles) / $dt)
        $script:RateHist.Add([double]$r)
        while ($script:RateHist.Count -gt 14) { $script:RateHist.RemoveAt(0) }
        $n3 = [math]::Min(3, $script:RateHist.Count)
        $sum = 0.0; for ($k = $script:RateHist.Count - $n3; $k -lt $script:RateHist.Count; $k++) { $sum += $script:RateHist[$k] }
        $script:Rate = $sum / [math]::Max(1, $n3)
        $script:RateFiles = $script:FilesAllNow
        $script:RateMs = $ms
    }

    # drives
    Draw-Drives $script:rDrive0

    # overall
    $sf = [double]0; if ($script:Step -ge 0) { $sf = Clamp01 $script:Step }
    $ov = ($script:DoneW + ($script:CurW * $sf)) / [double]$script:TotalW
    if ($ov -gt 1) { $ov = 1 }
    $eta = '--:--'
    if ($ov -ge 0.04 -and $ov -lt 1) { $left = [timespan]::FromMilliseconds($ms * (1 - $ov) / $ov); $eta = ('{0:mm\:ss}' -f $left); if ($left.TotalHours -ge 1) { $eta = '>1h' } }
    Put 2 $script:rOverall 'OVERALL' 'Cyan'
    Show-Bar 12 $script:rOverall $BW $ov 'Cyan' ($ov -lt 1) $blink
    Put $tx $script:rOverall (Fit ('{0,3}%   ETA ~{1}' -f [int][math]::Floor($ov * 100), $eta) 30) 'White'

    # current task
    Put 2 $script:rCurrent 'TASK' 'Cyan'
    Show-Bar 12 $script:rCurrent $BW $script:Step 'Green' ($script:Step -ge 0 -and $script:Step -lt 1) $blink
    $pt = ''; if ($script:Step -ge 0) { $pt = ('{0,3}% ' -f [int][math]::Floor((Clamp01 $script:Step) * 100)) }
    Put $tx $script:rCurrent (Fit ($pt + $script:Detail) 30) 'Gray'

    # LIVE line
    $dotCol = 'DarkGreen'; if ($blink) { $dotCol = 'Green' }
    Put 2 $script:rLive $cLive $dotCol
    Put 4 $script:rLive 'LIVE' $dotCol
    $lw = $BW + 2
    $txt = $script:LiveText; $tc = 'Gray'
    if ($script:LiveKind -eq 'file') {
        if (($ms - $script:LastChangeMs) -gt 12000) { $txt = 'Big item in progress - still working, please wait...'; $tc = 'Yellow' }
    } elseif ($script:LiveKind -eq 'proc') { $tc = 'Yellow' }
    Put 12 $script:rLive (Fit-Mid $txt $lw) $tc
    if ($script:LiveKind -eq 'file') {
        $mx = 1.0; foreach ($v in $script:RateHist) { if ($v -gt $mx) { $mx = $v } }
        $sp = ''
        for ($k = 0; $k -lt 14; $k++) {
            $idx = $k - (14 - $script:RateHist.Count)
            if ($idx -lt 0) { $sp += ' ' } else { $sp += $sparkChars[[int][math]::Min([double]7, [math]::Round(7 * $script:RateHist[$idx] / $mx))] }
        }
        Put $tx $script:rLive $sp 'Cyan'
        Put ($tx + 15) $script:rLive (Fit ('{0:N0} files/s' -f $script:Rate) 15) 'DarkGray'
    } elseif ($script:LiveKind -eq 'proc') {
        Put $tx $script:rLive (Fit 'working ...' 30) 'DarkGray'
    } else {
        Put $tx $script:rLive (' ' * 30) 'Gray'
    }

    # blinking arrow on the running task
    if ($script:CurIdx -ge 1) {
        $ci = $script:CurIdx - 1
        if ($ci -ge $script:TaskTop -and $ci -lt ($script:TaskTop + $script:Vis) -and $script:Tasks[$ci].Status -eq 'running') {
            $ac = 'DarkYellow'; if ($blink) { $ac = 'Yellow' }
            Put 3 ($script:rTask0 + ($ci - $script:TaskTop)) $cRun $ac
        }
    }

    # footer
    $label = 'FREED'; if ($DryRun) { $label = 'FOUND' }
    $ts = [timespan]::FromMilliseconds($ms)
    Put 2 $script:rFoot $label 'DarkGray'
    Put 8 $script:rFoot (Fit (Format-Size ($script:FreedDone + $script:CurFreed)) 12) 'Green'
    Put 22 $script:rFoot 'FILES' 'DarkGray'
    Put 28 $script:rFoot (Fit ('{0:N0}' -f ($script:DelDone + $script:DelNow)) 11) 'White'
    Put 42 $script:rFoot 'ELAPSED' 'DarkGray'
    Put 50 $script:rFoot ('{0:hh\:mm\:ss}' -f $ts) 'White'
    Put 62 $script:rFoot 'Ctrl+C = safe stop' 'DarkGray'
}

# ------------------------------- engine helpers ------------------------------
function Invoke-DustJob {
    param([string[]]$Items, [bool]$Delete, [string]$Verb, [int]$TimeoutSec = 0, [double]$StepBase = 0, [double]$StepSpan = 1)
    $job = [DustJob]::new([string[]]$Items, $Delete)
    $job.Start()
    $t0 = $script:SW.ElapsedMilliseconds
    $baseAll = $script:FilesAllDone
    $script:LiveKind = 'file'
    while (-not $job.Done) {
        Start-Sleep -Milliseconds 35
        $ms = $script:SW.ElapsedMilliseconds
        if ($TimeoutSec -gt 0 -and (($ms - $t0) -gt ($TimeoutSec * 1000)) -and -not $job.Cancel) { $job.Cancel = $true; $script:TaskPartial = $true }
        $f = $job.Files
        $b = $job.Bytes
        $tot = $job.ItemsTotal
        $dn = $job.ItemsDone
        $script:FilesAllNow = $baseAll + $f
        $script:Token = $f + $b + $dn
        if ($Delete) { $script:CurFreed = $b; $script:DelNow = $f }
        if ($tot -le 4) { $script:Step = -1 } else { $script:Step = $StepBase + $StepSpan * ($dn / [double]$tot) }
        if ($Delete) { $script:Detail = ('{0} - {1:N0} files' -f (Format-Size $b), $f) } else { $script:Detail = ('{0:N0} files - {1}' -f $f, (Format-Size $b)) }
        $script:LiveText = $Verb + ' ' + $job.Current
        Update-UI
    }
    $script:FilesAllDone = $baseAll + $job.Files
    $script:FilesAllNow = $script:FilesAllDone
    if ($Delete) { $script:DelDone += $job.Files; $script:DelNow = 0; $script:CurFreed = 0 }
    $script:Step = $StepBase + $StepSpan
    Update-UI -Force
    return $job
}

function Test-SafePath {
    param([string]$p)
    if ($script:SkipPathGuard) { return $true }
    if ($p -notmatch '^[A-Za-z]:\\') { return $false }
    if ($p -match '^[A-Za-z]:\\?$') { return $false }
    if ($p -match '^[A-Za-z]:\\[^\\]+$') {
        # a top-level folder: only a few leftover-upgrade folders may be removed
        $leaf = Split-Path $p -Leaf
        if (@('Windows.old', '$Windows.~BT', '$WINDOWS.~WS', 'MEMORY.DMP') -notcontains $leaf) { if (Test-Path -LiteralPath $p -PathType Container) { return $false } }
    }
    if ($p -match '(?i)^[A-Za-z]:\\(Windows|Users|Program Files|Program Files \(x86\)|ProgramData)\\?$') { return $false }
    return $true
}

function Invoke-Wipe {
    # Contents = folders whose CONTENT is deleted (the folder stays).  Remove = paths (wildcards ok) deleted completely.
    param([string[]]$Contents = @(), [string[]]$Remove = @())
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $list = New-Object 'System.Collections.Generic.List[string]'
    Set-Live 'proc' 'Looking for junk files ...' -1 'searching'
    Update-UI -Force
    foreach ($c in $Contents) {
        if ([string]::IsNullOrWhiteSpace($c)) { continue }
        if (Test-Path -LiteralPath $c -PathType Container) {
            Update-UI
            foreach ($f in @(Get-ChildItem -LiteralPath $c -Force -ErrorAction SilentlyContinue)) {
                $fn = $f.FullName
                if ($seen.Add($fn) -and (Test-SafePath $fn)) { $list.Add($fn) }
            }
        }
    }
    foreach ($r in $Remove) {
        if ([string]::IsNullOrWhiteSpace($r)) { continue }
        Update-UI
        $found = @()
        if ($r -match '[\*\?]') { $found = @(Get-Item -Path $r -Force -ErrorAction SilentlyContinue) } else { $found = @(Get-Item -LiteralPath $r -Force -ErrorAction SilentlyContinue) }
        foreach ($f in $found) {
            $fn = $f.FullName
            if ($seen.Add($fn) -and (Test-SafePath $fn)) { $list.Add($fn) }
        }
    }
    if ($list.Count -eq 0) { $script:TaskNote = 'already clean'; Set-Live 'idle' '' -1 ''; Update-UI -Force; return [int64]0 }
    $verb = 'Deleting'; if ($DryRun) { $verb = 'Measuring' }
    $job = Invoke-DustJob -Items ([string[]]$list.ToArray()) -Delete (-not $DryRun) -Verb $verb
    $sum = [int64]0
    foreach ($v in $job.Results) { $sum += [int64]$v }
    $script:TaskNote = ('{0:N0} items, {1:N0} files' -f $list.Count, $job.Files)
    return $sum
}

function Read-DismPct {
    param([string]$File)
    try {
        $fs = [IO.File]::Open($File, 'Open', 'Read', 'ReadWrite')
        $sr = New-Object IO.StreamReader($fs)
        $txt = $sr.ReadToEnd()
        $sr.Close(); $fs.Close()
        $m = [regex]::Matches($txt, '(\d{1,3}(?:\.\d+)?)%')
        if ($m.Count -gt 0) { return ([double]$m[$m.Count - 1].Groups[1].Value) / 100 }
    } catch {}
    return -1
}

function Invoke-Proc {
    param([string]$File, [string]$ArgString, [string]$Text = 'Working', [switch]$Dism)
    $out = Join-Path ([IO.Path]::GetTempPath()) ('dustnado_' + [guid]::NewGuid().ToString('N') + '.log')
    $p = $null
    try { $p = Start-Process -FilePath $File -ArgumentList $ArgString -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -ErrorAction Stop } catch { $p = $null }
    if (-not $p) { return -1 }
    $null = $p.Handle
    $t0 = $script:SW.ElapsedMilliseconds
    $script:LiveKind = 'proc'
    while (-not $p.HasExited) {
        Start-Sleep -Milliseconds 60
        $pct = -1
        if ($Dism) { $pct = Read-DismPct $out }
        $sec = [int](($script:SW.ElapsedMilliseconds - $t0) / 1000)
        $script:LiveText = ('{0}  ({1}s)' -f $Text, $sec)
        $script:Step = $pct
        if ($pct -ge 0) { $script:Detail = ('{0:N0}%  {1}s' -f ($pct * 100), $sec) } else { $script:Detail = ('{0}s elapsed' -f $sec) }
        Update-UI
    }
    $p.WaitForExit()
    $code = $p.ExitCode
    Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
    $script:LiveKind = 'idle'
    return $code
}

function Skip-Task {
    param([string]$Why)
    $script:TaskSkip = $true
    $script:TaskNote = $Why
}

function Get-ProfilePaths {
    param([scriptblock]$Gen)
    $r = @()
    foreach ($p in $Profiles) { $r += @(& $Gen $p) }
    return $r
}

function Test-RebootPending {
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        if (Test-Path $k) { return $true }
    }
    return $false
}

function Test-UpdateBusy {
    if (Get-Process -Name TiWorker -ErrorAction SilentlyContinue) { return $true }
    return $false
}

function Close-Browsers {
    if (-not $CloseBrowsers -or $DryRun) { return }
    foreach ($n in 'chrome', 'msedge', 'brave', 'firefox') {
        Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 1500
}

function Restore-Services {
    foreach ($s in $script:StoppedSvc) { Start-Service -Name $s -ErrorAction SilentlyContinue }
    $script:StoppedSvc = @()
}

# --------------------------------- detection ---------------------------------
function Get-Detected {
    $probe = @(
        @('Chrome', 'LA', 'Google\Chrome\User Data'), @('Edge', 'LA', 'Microsoft\Edge\User Data'),
        @('Brave', 'LA', 'BraveSoftware\Brave-Browser\User Data'), @('Firefox', 'LA', 'Mozilla\Firefox\Profiles'),
        @('VS Code', 'RA', 'Code'), @('Cursor', 'RA', 'Cursor'), @('Discord', 'RA', 'discord'), @('Slack', 'RA', 'Slack'), @('CapCut', 'LA', 'CapCut'),
        @('npm', 'LA', 'npm-cache'), @('npm', 'RA', 'npm-cache'), @('Yarn', 'LA', 'Yarn\Cache'), @('pip', 'LA', 'pip\Cache'), @('NuGet', 'LA', 'NuGet\v3-cache'),
        @('Android Studio', 'LA', 'Google\AndroidStudio*'), @('Gradle', 'UP', '.gradle'), @('Flutter/Pub', 'LA', 'Pub\Cache'), @('Docker', 'LA', 'Docker'))
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($pr in $probe) {
        foreach ($p in $Profiles) {
            $base = $p.LA; if ($pr[1] -eq 'RA') { $base = $p.RA } elseif ($pr[1] -eq 'UP') { $base = $p.UP }
            if (Test-Path -Path (Join-Path $base $pr[2])) { if (-not $found.Contains($pr[0])) { $found.Add($pr[0]) }; break }
        }
    }
    return @($found)
}

function Get-SmartTips {
    $tips = New-Object System.Collections.Generic.List[string]
    $sysScan = $script:Scan[$DriveLetter]
    $sysFree = Get-Free $DriveLetter
    $sysDrive = $Drives | Where-Object { $_.IsSystem } | Select-Object -First 1
    $upRef = $env:USERPROFILE; if ((-not $upRef) -and $Profiles.Count -gt 0) { $upRef = $Profiles[0].UP }
    if ($sysScan -and $sysScan.Special) {
        $hib = [int64]0; if ($sysScan.Special.ContainsKey('hiberfil.sys')) { $hib = $sysScan.Special['hiberfil.sys'] }
        if ($hib -gt 3GB) { $tips.Add(('Hibernation file uses {0}. Admin terminal: powercfg /h /type reduced   (or powercfg /h off)' -f (Format-Size $hib))) }
    }
    foreach ($h in $script:Hogs) {
        $leaf = Split-Path $h.Path -Leaf
        $better = $null
        foreach ($dv in $Drives) {
            if (-not $dv.IsSystem) {
                $fr = Get-Free $dv.Letter
                if ($fr -gt ($h.Size * 1.2) -and ((-not $better) -or $fr -gt $better.Free)) { $better = [pscustomobject]@{ Letter = $dv.Letter; Free = $fr } }
            }
        }
        if ($h.Drive -ne $DriveLetter) { continue }
        if ($leaf -match '^(Videos|Pictures|Documents|Desktop|Music|Downloads)$' -and $h.Size -gt 5GB) {
            if ($better) { $tips.Add(('Your {0} folder is {1}. Move it to {2}: ({3} free) to free space on {4}:' -f $leaf, (Format-Size $h.Size), $better.Letter, (Format-Size $better.Free), $DriveLetter)) }
            elseif ($leaf -eq 'Downloads') { $tips.Add(('Downloads is {0} - review old installers and archives.' -f (Format-Size $h.Size))) }
        } elseif ($h.Size -gt 5GB -and $h.Path -match '(?i)\\(\.android|Android)(\\|$)') {
            $tips.Add(('Android SDK/emulators use {0} ({1}). Delete unused emulators in Android Studio Device Manager.' -f (Format-Size $h.Size), $leaf))
        } elseif ($h.Size -gt 3GB -and $h.Path -match '(?i)\\(Docker|Packages)$') {
            $tips.Add(('{0} is {1} (may hold WSL/Docker disks). Compact the virtual disk or remove unused images.' -f $leaf, (Format-Size $h.Size)))
        } elseif ($h.Size -gt 8GB -and $h.Path -notmatch '(?i)\\AppData\\') {
            if ($better) { $tips.Add(('{0} is {1}. You could move it to {2}: ({3} free).' -f $(if ($upRef) { $h.Path.Replace($upRef, '~') } else { $h.Path }), (Format-Size $h.Size), $better.Letter, (Format-Size $better.Free))) }
        }
    }
    foreach ($p in $Profiles) {
        $vh = @(Get-ChildItem -Path "$($p.LA)\Packages\*\LocalState\*.vhdx", "$($p.LA)\Docker\wsl\*\*.vhdx" -Force -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 5GB })
        foreach ($v in $vh) { $tips.Add(('Virtual disk {0} is {1}. Shrink it with: wsl --manage <distro> --set-sparse true' -f $v.Name, (Format-Size $v.Length))) }
    }
    if ($sysDrive -and ($sysFree / [double]$sysDrive.Total) -lt 0.10) { $tips.Add(('{0}: is still under 10% free - Windows runs best with at least 15-20% free.' -f $DriveLetter)) }
    foreach ($dv in $Drives) {
        if (-not $dv.IsSystem) {
            $fr = Get-Free $dv.Letter
            if (($fr / [double]$dv.Total) -lt 0.08) { $tips.Add(('{0}: is almost full ({1} free).' -f $dv.Letter, (Format-Size $fr))) }
        }
    }
    if ($DryRun) { $tips.Add('Run Dustnado again without /scan to actually reclaim the space listed above.') }
    return @($tips | Select-Object -Unique)
}

# ------------------------------- the task list --------------------------------
$Tasks = New-Object System.Collections.ArrayList
$script:Tasks = $Tasks
function Add-Task {
    param([string]$Name, [int]$Weight, [scriptblock]$Action, [bool]$Enabled = $true)
    [void]$Tasks.Add([pscustomobject]@{ Name = $Name; Weight = $Weight; Action = $Action; Enabled = $Enabled; Status = 'pending'; Freed = [int64]0; Note = '' })
}

Add-Task 'Scanning all drives' 10 {
    $skipNames = @('System Volume Information', '$Recycle.Bin', 'Config.Msi')
    $nd = $Drives.Count; $di = 0; $totalFolders = 0
    foreach ($dv in $Drives) {
        $dirs = @(Get-ChildItem -LiteralPath $dv.Root -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { (($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) -and ($skipNames -notcontains $_.Name) })
        $paths = @($dirs | ForEach-Object { $_.FullName })
        $folders = @(); $partial = $false
        if ($paths.Count -gt 0) {
            $script:TaskPartial = $false
            $job = Invoke-DustJob -Items $paths -Delete $false -Verb ('Scanning ' + $dv.Letter + ':') -TimeoutSec $ScanTimeoutSec -StepBase ($di / [double]$nd) -StepSpan (1 / [double]$nd)
            for ($k = 0; $k -lt $paths.Count; $k++) {
                $folders += [pscustomobject]@{ Name = $dirs[$k].Name; Path = $paths[$k]; Size = [int64]$job.Results[$k]; Drive = $dv.Letter }
            }
            $partial = $script:TaskPartial
            $totalFolders += $paths.Count
        }
        $rootFiles = @(Get-ChildItem -LiteralPath $dv.Root -File -Force -ErrorAction SilentlyContinue)
        $special = @{}
        foreach ($rf in $rootFiles) { $special[$rf.Name.ToLower()] = [int64]$rf.Length }
        $rs = 0; foreach ($rf in $rootFiles) { $rs += [int64]$rf.Length }
        $script:Scan[$dv.Letter] = @{ Folders = @($folders | Sort-Object Size -Descending); RootFiles = [int64]$rs; Special = $special; Partial = $partial }
        $di++
    }
    $script:TaskPartial = $false
    $script:TaskNote = ('{0} drives, {1} folders' -f $nd, $totalFolders)
    foreach ($k in $script:Scan.Keys) { if ($script:Scan[$k].Partial) { $script:TaskNote += ' (partial)' } }
}

Add-Task 'User temp files' 5 {
    $dirs = @(Get-ProfilePaths { param($p) "$($p.LA)\Temp" })
    foreach ($e in @($env:TEMP, $env:TMP)) { if ($e -and ((Split-Path $e -Leaf) -match '(?i)^te?mp$')) { $dirs += $e } }
    $script:TaskFreed = Invoke-Wipe -Contents $dirs
}

Add-Task 'Windows temp files' 4 {
    $script:TaskFreed = Invoke-Wipe -Contents @("$WD\Temp")
}

Add-Task 'Windows Update cache' 6 {
    if (Test-UpdateBusy) { Skip-Task 'updates installing - skipped'; return }
    if (-not $DryRun) {
        Set-Live 'proc' 'Pausing update services ...' -1 'please wait'
        Update-UI -Force
        foreach ($s in 'wuauserv', 'bits', 'DoSvc') {
            $o = Get-Service -Name $s -ErrorAction SilentlyContinue
            if ($o -and $o.Status -eq 'Running') { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue; $script:StoppedSvc += $s }
        }
        Start-Sleep -Milliseconds 800
    }
    $script:TaskFreed = Invoke-Wipe -Contents @(
        "$WD\SoftwareDistribution\Download", "$WD\SoftwareDistribution\DeliveryOptimization",
        "$WD\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache")
    Restore-Services
}

Add-Task 'Crash dumps & system logs' 4 {
    $c = @("$WD\Minidump", "$WD\LiveKernelReports", "$PD\Microsoft\Windows\WER\ReportArchive", "$PD\Microsoft\Windows\WER\ReportQueue",
        "$PD\Microsoft\Windows\WER\Temp", "$WD\Logs\DISM", "$WD\Logs\WindowsUpdate", "$WD\Logs\waasmedic")
    $c += @(Get-ProfilePaths { param($p) "$($p.LA)\CrashDumps"; "$($p.LA)\Microsoft\Windows\WER" })
    $script:TaskFreed = Invoke-Wipe -Contents $c -Remove @("$WD\MEMORY.DMP", "$WD\Logs\CBS\*.log", "$WD\Logs\CBS\*.cab")
}

Add-Task 'Thumbnail, shader & web caches' 4 {
    $c = @(Get-ProfilePaths { param($p) "$($p.LA)\Microsoft\Windows\INetCache"; "$($p.LA)\D3DSCache"; "$($p.LA)\NVIDIA\DXCache"; "$($p.LA)\NVIDIA\GLCache"; "$($p.LA)\AMD\DxCache" })
    $r = @(Get-ProfilePaths { param($p) "$($p.LA)\Microsoft\Windows\Explorer\thumbcache_*.db"; "$($p.LA)\Microsoft\Windows\Explorer\iconcache_*.db" })
    $script:TaskFreed = Invoke-Wipe -Contents $c -Remove $r
}

Add-Task 'Browser caches' 8 {
    Set-Live 'proc' 'Closing browsers so their caches can be cleaned ...' -1 'please wait'
    Update-UI -Force
    Close-Browsers
    $rm = New-Object System.Collections.ArrayList
    $subs = @('Cache', 'Code Cache', 'GPUCache', 'DawnCache', 'Media Cache', 'Service Worker\CacheStorage', 'Service Worker\ScriptCache')
    $top  = @('GrShaderCache', 'ShaderCache', 'GraphiteDawnCache', 'component_crx_cache', 'extensions_crx_cache', 'OptGuideOnDeviceModel')
    foreach ($p in $Profiles) {
        foreach ($b in @("$($p.LA)\Google\Chrome\User Data", "$($p.LA)\Microsoft\Edge\User Data", "$($p.LA)\BraveSoftware\Brave-Browser\User Data")) {
            foreach ($s in $subs) { [void]$rm.Add("$b\*\$s") }
            foreach ($t in $top)  { [void]$rm.Add("$b\$t") }
        }
        foreach ($s in 'cache2', 'startupCache', 'OfflineCache') { [void]$rm.Add("$($p.LA)\Mozilla\Firefox\Profiles\*\$s") }
    }
    $script:TaskFreed = Invoke-Wipe -Remove ([string[]]$rm.ToArray())
} $CleanBrowsers

Add-Task 'App caches (Code, Discord...)' 4 {
    $rm = New-Object System.Collections.ArrayList
    foreach ($p in $Profiles) {
        foreach ($app in 'Code', 'Code - Insiders', 'Cursor', 'discord', 'Slack') {
            foreach ($s in 'Cache', 'CachedData', 'CachedExtensionVSIXs', 'Code Cache', 'GPUCache', 'logs') { [void]$rm.Add("$($p.RA)\$app\$s") }
        }
        [void]$rm.Add("$($p.LA)\Packages\*\TempState")
    }
    $c = @(Get-ProfilePaths { param($p) "$($p.LA)\CapCut\User Data\Cache" })
    $script:TaskFreed = Invoke-Wipe -Contents $c -Remove ([string[]]$rm.ToArray())
} $CleanAppCaches

Add-Task 'Developer caches (npm, pip...)' 5 {
    $c = @(Get-ProfilePaths { param($p) "$($p.LA)\npm-cache"; "$($p.RA)\npm-cache"; "$($p.LA)\Yarn\Cache"; "$($p.LA)\pip\Cache"; "$($p.LA)\NuGet\v3-cache"; "$($p.UP)\.android\cache" })
    if ($CleanGradleCache) { $c += @(Get-ProfilePaths { param($p) "$($p.UP)\.gradle\caches" }) }
    $r = @(Get-ProfilePaths { param($p) "$($p.LA)\Google\AndroidStudio*\caches"; "$($p.LA)\Google\AndroidStudio*\log"; "$($p.LA)\Google\AndroidStudio*\tmp"; "$($p.UP)\.gradle\daemon\*\*.log" })
    $script:TaskFreed = Invoke-Wipe -Contents $c -Remove $r
} $CleanDevCaches

Add-Task 'Recycle Bin (all drives)' 3 {
    $total = [int64]0; $any = $false
    foreach ($dv in $Drives) {
        $rb = $dv.Root + '$Recycle.Bin'
        if (-not (Test-Path -LiteralPath $rb)) { continue }
        $kids = @(Get-ChildItem -LiteralPath $rb -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        if ($kids.Count -eq 0) { continue }
        $any = $true
        $paths = @(); foreach ($k in $kids) { $paths += @(Get-ChildItem -LiteralPath $k -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }
        if ($paths.Count -eq 0) { continue }
        $verb = 'Emptying'; if ($DryRun) { $verb = 'Measuring' }
        $job = Invoke-DustJob -Items $paths -Delete (-not $DryRun) -Verb ($verb + ' ' + $dv.Letter + ': Recycle Bin')
        foreach ($v in $job.Results) { $total += [int64]$v }
    }
    if ($any -and -not $DryRun) { try { Clear-RecycleBin -Force -ErrorAction Stop } catch {} }
    if (-not $any) { $script:TaskNote = 'already empty' } else { $script:TaskNote = 'all fixed drives' }
    $script:TaskFreed = $total
} $EmptyRecycleBin

Add-Task 'Old Windows install leftovers' 8 {
    $cands = @("$SD\Windows.old", "$SD\`$Windows.~BT", "$SD\`$WINDOWS.~WS")
    $present = @($cands | Where-Object { Test-Path -LiteralPath $_ })
    if ($present.Count -eq 0) { Skip-Task 'not present'; return }
    if (-not $DryRun) {
        $q = ($present | ForEach-Object { '"' + $_ + '"' }) -join ' '
        $cmdArgs = '/c for %D in (' + $q + ') do ( takeown /F "%~D" /R /A /D Y <nul >nul 2>&1 & icacls "%~D" /grant *S-1-5-32-544:F /T /C /Q <nul >nul 2>&1 )'
        $null = Invoke-Proc "$WD\System32\cmd.exe" $cmdArgs 'Taking ownership of old Windows files (can take a few minutes)'
    }
    $verb = 'Deleting'; if ($DryRun) { $verb = 'Measuring' }
    $job = Invoke-DustJob -Items $present -Delete (-not $DryRun) -Verb $verb
    $sum = [int64]0; foreach ($v in $job.Results) { $sum += [int64]$v }
    if (-not $DryRun) {
        foreach ($pth in $present) { if (Test-Path -LiteralPath $pth) { $null = Invoke-Proc "$WD\System32\cmd.exe" ('/c rd /s /q "' + $pth + '" <nul >nul 2>&1') 'Removing the last leftovers' } }
    }
    $script:TaskNote = ('{0} folder(s)' -f $present.Count)
    $script:TaskFreed = $sum
} $RemoveOldWindows

Add-Task 'Windows component store (DISM)' 30 {
    if ($DryRun) { Skip-Task 'only runs in clean mode'; return }
    if (Test-RebootPending) { Skip-Task 'restart pending - reboot, run again'; return }
    if (Test-UpdateBusy) { Skip-Task 'updates installing - skipped'; return }
    $a = Get-Free $DriveLetter
    $dargs = '/Online /Cleanup-Image /StartComponentCleanup'
    if ($ResetBase) { $dargs += ' /ResetBase' }
    $code = Invoke-Proc "$WD\System32\Dism.exe" $dargs 'Cleaning the Windows component store (WinSxS)' -Dism
    $script:TaskFreed = [int64][math]::Max([int64]0, (Get-Free $DriveLetter) - $a)
    if ($code -ne 0 -and $code -ne 3010) { $script:TaskNote = ('DISM code {0}' -f $code) } else { $script:TaskNote = 'WinSxS optimised' }
} $ComponentCleanup

Add-Task 'Final analysis & smart tips' 10 {
    $cands = New-Object System.Collections.ArrayList
    $sysScan = $script:Scan[$DriveLetter]
    foreach ($p in $Profiles) {
        foreach ($root in @($p.UP, $p.LA, $p.RA)) {
            Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
                $skip = (($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or ($_.Name -like 'OneDrive*')
                if ($root -eq $p.UP -and $_.Name -eq 'AppData') { $skip = $true }
                if (-not $skip) { [void]$cands.Add($_.FullName) }
            }
        }
    }
    $hogs = New-Object System.Collections.ArrayList
    if ($cands.Count -gt 0) {
        $arr = [string[]]$cands.ToArray()
        $job = Invoke-DustJob -Items $arr -Delete $false -Verb 'Analysing' -TimeoutSec $ScanTimeoutSec
        for ($k = 0; $k -lt $arr.Count; $k++) { [void]$hogs.Add([pscustomobject]@{ Path = $arr[$k]; Size = [int64]$job.Results[$k]; Drive = $DriveLetter }) }
    }
    # custom top-level folders on every drive (skip OS / program folders) come from the first scan
    $osNames = @('Windows', 'Program Files', 'Program Files (x86)', 'ProgramData', 'Users', 'Recovery', 'PerfLogs', 'Intel', 'AMD', 'NVIDIA', 'MSOCache', '$WinREAgent', 'Documents and Settings', '$Windows.~BT', '$WINDOWS.~WS', 'Windows.old')
    foreach ($k in $script:Scan.Keys) {
        foreach ($f in $script:Scan[$k].Folders) { if (($osNames -notcontains $f.Name) -and (Test-Path -LiteralPath $f.Path)) { [void]$hogs.Add([pscustomobject]@{ Path = $f.Path; Size = [int64]$f.Size; Drive = $k }) } }
    }
    $script:Hogs = @($hogs | Where-Object { $_.Size -gt 0 } | Sort-Object Size -Descending | Select-Object -First 15)

    $script:Tips = @(Get-SmartTips)
    $script:TaskNote = ('{0} tip(s)' -f $script:Tips.Count)
}

$script:TotalW = 0
foreach ($t in $Tasks) { if ($t.Enabled) { $script:TotalW += $t.Weight } }
if ($script:TotalW -lt 1) { $script:TotalW = 1 }

# ---------------------------------- screens ----------------------------------
function Show-Intro {
    Clear-Host
    Init-Layout
    $badge = 'SMART CLEAN'; $bc = 'Green'
    if ($DryRun) { $badge = 'SCAN ONLY'; $bc = 'Yellow' }
    Draw-Banner $badge $bc
    $det = Get-Detected
    Put 2 6 (Fit ('{0}   {1}   {2} drive(s)   {3} user profile(s)' -f $OSName, $cArr, $Drives.Count, $Profiles.Count) ($script:W - 2)) 'Gray'
    Draw-Drives 7
    $y = 7 + $script:nD + 1
    if ($Drives.Count -gt $script:nD) { Put 2 ($y - 1) ('+ {0} more drive(s) will also be scanned' -f ($Drives.Count - $script:nD)) 'DarkGray' }
    Put 2 $y 'DETECTED' 'Cyan'
    $dtxt = 'nothing special - system cleanup only'; if ($det.Count -gt 0) { $dtxt = ($det -join ', ') }
    Put 12 $y (Fit $dtxt ($script:W - 12)) 'Green'
    $y++
    $warn = New-Object System.Collections.Generic.List[string]
    $runBr = @(Get-Process -Name chrome, msedge, brave, firefox -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName } | Select-Object -Unique)
    if ($runBr.Count -gt 0 -and $CloseBrowsers -and -not $DryRun) { $warn.Add(('Open browser(s) will be closed: ' + ($runBr -join ', '))) }
    if (Test-RebootPending) { $warn.Add('A Windows restart is pending - the DISM step will be skipped') }
    if ($script:WinW -lt 90) { $warn.Add('Window is narrow - please maximize it for the best view') }
    Put 2 $y 'WARNINGS' 'Cyan'
    if ($warn.Count -eq 0) { Put 12 $y 'none' 'Green' } else { Put 12 $y (Fit ($warn -join '  |  ') ($script:W - 12)) 'Yellow' }
    $y += 2
    if ($DryRun) { Put 2 $y 'SCAN MODE: Dustnado only measures what could be freed. Nothing will be deleted.' 'Yellow' }
    else { Put 2 $y 'DUSTNADO WILL SAFELY:' 'White' }
    $y++
    $lines = @(
        'Clear temp files, update cache, crash dumps and logs for every user profile',
        'Clear browser, app and developer caches (logins and bookmarks stay safe)',
        'Empty the Recycle Bin on every drive and remove old Windows leftovers',
        $(if ($ResetBase) { 'Deep-optimise the Windows component store (DISM /ResetBase)' } else { 'Optimise the Windows component store (DISM)' }),
        'Analyse all your drives and give smart tips on what is still big')
    foreach ($l in $lines) { Put 4 $y $cOK 'Green'; Put 6 $y (Fit $l ($script:W - 8)) 'Gray'; $y++ }
    $y++
    Put 2 $y 'Your personal files (Documents, Downloads, Desktop, Videos, Pictures) are NEVER deleted.' 'Green'
    $y += 2
    Put 2 ($y + 1) '[ENTER] Clean now     [S] Scan only (no deleting)     [Q] Quit' 'Cyan'
    if ($AutoStart) { return 'start' }
    $end = (Get-Date).AddSeconds($CountdownSeconds)
    while ($true) {
        $left = [int][math]::Ceiling(($end - (Get-Date)).TotalSeconds)
        if ($left -le 0) { return 'scan' }
        Put 2 $y (Fit ('No key pressed: SAFE scan-only starts in {0} s  (nothing is deleted unless you press ENTER)' -f $left) 80) 'White'
        try {
            if ([Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true)
                if ($k.Key -eq 'Escape' -or $k.Key -eq 'Q') { return 'quit' }
                if ($k.Key -eq 'Enter') { return 'start' }
                if ($k.Key -eq 'S') { return 'scan' }
            }
        } catch {}
        Start-Sleep -Milliseconds 100
    }
}

function Draw-Main {
    Clear-Host
    Init-Layout
    $badge = 'CLEANING'; $bc = 'Green'
    if ($DryRun) { $badge = 'SCAN ONLY'; $bc = 'Yellow' }
    Draw-Banner $badge $bc
    Put 2 6 'DRIVES' 'DarkGray'
    Draw-Tasks
    Update-UI -Force
}

function Show-Report {
    param([timespan]$Elapsed)
    $recovered = [int64]0
    foreach ($dv in $Drives) {
        $d = (Get-Free $dv.Letter) - [int64]$script:DriveBefore[$dv.Letter]
        if ($d -gt 0) { $recovered += $d }
    }
    $taskSum = [int64]0; foreach ($t in $Tasks) { $taskSum += $t.Freed }
    if ($DryRun) { $recovered = $taskSum }
    $sys = $Drives | Where-Object { $_.IsSystem } | Select-Object -First 1
    $sysAfter = Get-Free $DriveLetter
    $sysBefore = [int64]$script:DriveBefore[$DriveLetter]
    $usedBefore = ($sys.Total - $sysBefore) / [double]$sys.Total
    $usedAfter  = ($sys.Total - $sysAfter) / [double]$sys.Total
    $usedBefore = Clamp01 $usedBefore
    $usedAfter  = Clamp01 $usedAfter
    $word = 'RECOVERED'; if ($DryRun) { $word = 'CAN FREE' }

    # ---- text report ----
    $reportPath = ''
    try {
        $dirs = @()
        try { $dirs += [Environment]::GetFolderPath('Desktop') } catch {}
        if ($env:SELF) { $dirs += (Split-Path $env:SELF -Parent) }
        $dirs += [IO.Path]::GetTempPath()
        $dir = $null; foreach ($d in $dirs) { if ($d -and (Test-Path -LiteralPath $d)) { $dir = $d; break } }
        $reportPath = Join-Path $dir ('Dustnado_Report_{0:yyyyMMdd_HHmmss}.txt' -f (Get-Date))
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine(("DUSTNADO {0} - {1} REPORT" -f $AppVer, $(if ($DryRun) { 'SCAN-ONLY' } else { 'CLEANUP' })))
        [void]$sb.AppendLine(('by {0}  |  MIT License' -f $Author))
        [void]$sb.AppendLine(('Date     : {0}' -f (Get-Date)))
        [void]$sb.AppendLine(('Computer : {0}  ({1})' -f $env:COMPUTERNAME, $OSName))
        [void]$sb.AppendLine(('Duration : {0:hh\:mm\:ss}' -f $Elapsed))
        [void]$sb.AppendLine(('{0} : {1}' -f $word.PadRight(8), (Format-Size $recovered)))
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('--- DRIVES ---')
        foreach ($dv in $Drives) {
            $fa = Get-Free $dv.Letter
            [void]$sb.AppendLine(('{0}:  total {1,10}   free before {2,10}   free after {3,10}   {4} {5}' -f $dv.Letter, (Format-Size $dv.Total), (Format-Size ([int64]$script:DriveBefore[$dv.Letter])), (Format-Size $fa), $dv.Format, $dv.Label))
        }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('--- TASKS ---')
        foreach ($t in $Tasks) {
            $r = $t.Status; if ($t.Status -eq 'done') { $r = Format-Size $t.Freed }
            [void]$sb.AppendLine(('{0}  {1,11}  {2}' -f (Fit $t.Name 36), $r, $t.Note))
        }
        [void]$sb.AppendLine('')
        foreach ($k in ($script:Scan.Keys | Sort-Object)) {
            [void]$sb.AppendLine(('--- FOLDERS ON {0}: (before cleanup, approximate{1}) ---' -f $k, $(if ($script:Scan[$k].Partial) { ', partial scan' } else { '' })))
            foreach ($f in ($script:Scan[$k].Folders | Select-Object -First 25)) { [void]$sb.AppendLine(('{0,11}  {1}' -f (Format-Size $f.Size), $f.Path)) }
            [void]$sb.AppendLine('')
        }
        [void]$sb.AppendLine('--- BIGGEST FOLDERS STILL USING SPACE ---')
        foreach ($h in $script:Hogs) { [void]$sb.AppendLine(('{0,11}  {1}' -f (Format-Size $h.Size), $h.Path)) }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('--- SMART TIPS ---')
        if ($script:Tips.Count -eq 0) { [void]$sb.AppendLine('(none)') }
        foreach ($tp in $script:Tips) { [void]$sb.AppendLine('* ' + $tp) }
        [IO.File]::WriteAllText($reportPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
    } catch { $reportPath = '' }

    # ---- on-screen summary ----
    Clear-Host
    $done = 'COMPLETE'; if ($DryRun) { $done = 'SCAN DONE' }
    Draw-Banner $done 'Green'
    $wh = $script:WinH
    $nT = 7; $nH = 5; $nP = 3
    if ($wh -lt 34) { $nT = 5; $nH = 4; $nP = 2 }
    if ($wh -lt 30) { $nT = 4; $nH = 3; $nP = 2 }
    $W = $script:W

    Put 2 7 ($sys.Letter + ': FREE SPACE') 'Cyan'
    if ($DryRun) { Put 18 7 (Format-Size $sysAfter) 'White' }
    else { Put 18 7 (Format-Size $sysBefore) 'Red'; Put 30 7 $cArr 'DarkGray'; Put 33 7 (Format-Size $sysAfter) 'Green' }
    Put 2 8 $word 'Cyan'
    Put 18 8 ('+ ' + (Format-Size $recovered)) 'Yellow'
    Put 40 8 ('time {0:hh\:mm\:ss}   files removed {1:N0}' -f $Elapsed, $script:DelDone) 'DarkGray'
    Put 2 9 $(if ($DryRun) { 'USED  ' } else { 'BEFORE' }) 'DarkGray'; Show-Bar 9 9 26 $usedBefore 'Red'; Put 37 9 ('{0,3}%' -f [int][math]::Round($usedBefore * 100)) 'White'
    if (-not $DryRun) { Put 50 9 'AFTER' 'DarkGray'; Show-Bar 56 9 26 $usedAfter 'Green'; Put 84 9 ('{0,3}%' -f [int][math]::Round($usedAfter * 100)) 'White' }
    $other = @($Drives | Where-Object { -not $_.IsSystem })
    $ox = 2
    foreach ($o in ($other | Select-Object -First 3)) {
        $fa = Get-Free $o.Letter
        $txt = ('{0}: {1} free' -f $o.Letter, (Format-Size $fa))
        Put $ox 10 $txt 'Gray'; $ox += $txt.Length + 4
    }

    $y = 12
    Put 2 $y (($cLine * 3) + ' ' + $(if ($DryRun) { 'RECLAIMABLE BY TASK ' } else { 'FREED BY TASK ' }) + ($cLine * ($W - 26))) 'DarkGray'
    $y++
    $doneT = @($Tasks | Where-Object { $_.Freed -gt 0 } | Sort-Object Freed -Descending)
    $maxF = 1; if ($doneT.Count -gt 0) { $maxF = [double]$doneT[0].Freed }
    foreach ($t in ($doneT | Select-Object -First $nT)) {
        Put 4 $y (Fit $t.Name 34) 'Gray'
        Put 39 $y ((Format-Size $t.Freed).PadLeft(11)) 'Green'
        Put 52 $y ($cB * [int][math]::Max(1, [math]::Floor(($t.Freed / $maxF) * 24))) 'Cyan'
        $y++
    }
    if ($doneT.Count -eq 0) { Put 4 $y 'Nothing needed cleaning - your drives were already tidy.' 'Gray'; $y++ }
    if ($doneT.Count -gt $nT) { Put 4 $y ('+ {0} more task(s)' -f ($doneT.Count - $nT)) 'DarkGray'; $y++ }

    $y++
    Put 2 $y (($cLine * 3) + ' STILL USING THE MOST SPACE (not touched - your call) ' + ($cLine * ($W - 58))) 'DarkGray'
    $y++
    $upRef = $env:USERPROFILE
    foreach ($h in ($script:Hogs | Select-Object -First $nH)) {
        Put 4 $y ((Format-Size $h.Size).PadLeft(10)) 'Yellow'
        $pp = $h.Path; if ($upRef) { $pp = $pp.Replace($upRef, '~') }
        Put 16 $y (Fit-Mid $pp ($W - 16)) 'Gray'
        $y++
    }
    if ($script:Tips.Count -gt 0) {
        $y++
        Put 2 $y (($cLine * 3) + ' SMART TIPS ' + ($cLine * ($W - 16))) 'DarkGray'
        $y++
        foreach ($tp in ($script:Tips | Select-Object -First $nP)) { Put 4 $y ($cArr + ' ') 'Cyan'; Put 6 $y (Fit $tp ($W - 8)) 'White'; $y++ }
    }
    if ($reportPath) { Put 2 ($y + 1) (Fit-Mid ('Full report saved: ' + $reportPath) ($W - 2)) 'DarkGray' }
    Put 2 ($y + 2) 'Press any key to close ...' 'Cyan'
}

# ------------------------------------ main ------------------------------------
$ranOk = $false
try {
    try { [Console]::CursorVisible = $false } catch {}
    Init-Layout
    $choice = Show-Intro
    if ($choice -eq 'quit') {
        Clear-Host
        Put 2 2 'Cancelled - nothing was changed.' 'Yellow'
        Start-Sleep -Seconds 2
        return
    }
    if ($choice -eq 'scan') { $DryRun = $true }

    foreach ($dv in $Drives) { $script:DriveBefore[$dv.Letter] = Get-Free $dv.Letter }
    $script:SW.Restart()
    $script:LastDraw = 0
    Draw-Main

    for ($i = 0; $i -lt $Tasks.Count; $i++) {
        $t = $Tasks[$i]
        $script:CurIdx = $i + 1
        $script:CurName = $t.Name
        Set-TaskTop $i
        if (-not $t.Enabled) {
            $t.Status = 'skipped'; $t.Note = 'turned off in settings'
            Draw-Task $i
            continue
        }
        $script:CurW = $t.Weight
        $script:CurFreed = [int64]0
        $script:TaskFreed = [int64]0
        $script:TaskNote = ''
        $script:TaskSkip = $false
        $script:TaskPartial = $false
        Set-Live 'idle' ('Starting: ' + $t.Name) -1 ''
        $t.Status = 'running'
        Draw-Task $i
        Update-UI -Force
        try { $null = & $t.Action } catch { $script:TaskNote = 'finished with warnings' }
        Restore-Services
        if ($script:TaskSkip) { $t.Status = 'skipped' } else { $t.Status = 'done' }
        $t.Freed = [int64]$script:TaskFreed
        $t.Note = $script:TaskNote
        $script:FreedDone += $t.Freed
        $script:CurFreed = [int64]0
        $script:DoneW += $t.Weight
        $script:CurW = 0
        Set-Live 'idle' '' -1 ''
        Draw-Task $i
        Update-UI -Force
    }

    $script:CurName = 'All done'
    $script:CurIdx = $Tasks.Count
    $script:DoneW = $script:TotalW
    Set-Live 'idle' 'All tasks finished' 1 'complete'
    Update-UI -Force
    Start-Sleep -Milliseconds 800
    Show-Report -Elapsed $script:SW.Elapsed
    $ranOk = $true
    try { while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) } } catch {}
    try { [void][Console]::ReadKey($true) } catch { Start-Sleep -Seconds 30 }
}
finally {
    Restore-Services
    try { [Console]::CursorVisible = $true } catch {}
    if (-not $ranOk) { try { [Console]::SetCursorPosition(0, [math]::Min([Console]::WindowHeight - 1, 36)); Write-Host '' } catch {} }
}
