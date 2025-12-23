<#
.SYNOPSIS
    Automated Windows Component Store Repair & CBS Log Analysis Tool.
.DESCRIPTION
    RMM-Ready version. Automates DISM/SFC with logic gates.
.PARAMETER Mode
    "Auto"  (Default) = Scan first. If corrupt, Repair.
    "Audit" = Scan only. Do not repair.
    "Force" = Skip scan. Go straight to Repair.
.PARAMETER Silent
    Boolean. Default True. Suppresses progress bars (Recommended for RMM logs).
#>
[CmdletBinding()]
Param(
    [ValidateSet("Auto", "Audit", "Force")]
    [string]$Mode = "Auto",

    [bool]$Silent = $true
)

# --- DATTO RMM INTEGRATION SHIM ---
if ($env:Mode) { $Mode = $env:Mode }
if ($env:Silent) { $Silent = $env:Silent -eq 'true' }

$ErrorActionPreference = "Continue"

# --- 0. PATH FIX FOR RMM (32-bit vs 64-bit) ---
# RMM agents often run as 32-bit. This ensures we can find DISM/SFC in the 64-bit folder.
if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
    # We are 32-bit on 64-bit OS -> Use Sysnative to reach 64-bit tools
    $DismPath = "$env:SystemRoot\Sysnative\dism.exe"
    $SfcPath  = "$env:SystemRoot\Sysnative\sfc.exe"
} else {
    # We are 64-bit on 64-bit OS -> Use standard System32
    $DismPath = "$env:SystemRoot\System32\dism.exe"
    $SfcPath  = "$env:SystemRoot\System32\sfc.exe"
}

# --- 1. ERROR DATABASE ---
$KnownErrors = @{
    "0x80070002" = "ERROR_FILE_NOT_FOUND";
    "0x800f0831" = "CBS_E_STORE_CORRUPTION";
    "0x800F081F" = "CBS_E_SOURCE_MISSING";
    "0x80073712" = "ERROR_SXS_COMPONENT_STORE_CORRUPT";
    "0x800736CC" = "ERROR_SXS_FILE_HASH_MISMATCH";
    "0x800705B9" = "ERROR_XML_PARSE_ERROR";
    "0x80070246" = "ERROR_ILLEGAL_CHARACTER";
    "0x8007370D" = "ERROR_SXS_IDENTITY_PARSE_ERROR";
    "0x8007370B" = "ERROR_SXS_INVALID_IDENTITY_ATTRIBUTE_NAME";
    "0x8007370A" = "ERROR_SXS_INVALID_IDENTITY_ATTRIBUTE_VALUE";
    "0x80070057" = "ERROR_INVALID_PARAMETER";
    "0x800B0100" = "TRUST_E_NOSIGNATURE";
    "0x80092003" = "CRYPT_E_FILE_ERROR";
    "0x800B0101" = "CERT_E_EXPIRED";
    "0x8007371B" = "ERROR_SXS_TRANSACTION_CLOSURE_INCOMPLETE";
    "0x80070490" = "ERROR_NOT_FOUND";
    "0x800f0984" = "PSFX_E_MATCHING_BINARY_MISSING";
    "0x800f0986" = "PSFX_E_APPLY_FORWARD_DELTA_FAILED";
    "0x800f0982" = "PSFX_E_MATCHING_COMPONENT_NOT_FOUND";
    "0x8024002E" = "WU_E_WU_DISABLED";
    "0x800f0906" = "CBS_E_DOWNLOAD_FAILURE";
}
$ScriptStartTime = Get-Date

# --- HELPER: RMM SAFE LOGGER ---
Function Invoke-DismCommand {
    Param([string]$Arguments)
    
    # Use the calculated path (Sysnative or System32)
    $quietFlag = if ($Silent) { " /Quiet" } else { "" }
    $cmdString = "& '$DismPath' $Arguments$quietFlag"
    
    if ($Silent) {
        Write-Output "   (Silent Mode: Progress bar hidden for RMM logging)"
        $res = Invoke-Expression "$cmdString 2>&1"
        $global:DismExitCode = $LASTEXITCODE
        return $res
    } else {
        # Interactive
        Invoke-Expression "$cmdString 2>&1" | Tee-Object -Variable Captured
        $global:DismExitCode = $LASTEXITCODE
        return $Captured
    }
}

# --- HELPER: CBS ANALYZER ---
Function Get-CbsAnalysis {
    Param($StartTime)
    
    $LogPath = "$env:SystemRoot\Logs\CBS\CBS.log"
    if (-not (Test-Path $LogPath)) { return "CBS.log not found." }

    try {
        $FileStream = [System.IO.File]::Open($LogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $Reader = New-Object System.IO.StreamReader($FileStream)
        
        $RelevantLines = @()
        while (($Line = $Reader.ReadLine()) -ne $null) {
            if ($Line -match "^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})") {
                $LogTime = [DateTime]$matches[1]
                if ($LogTime -ge $StartTime) {
                    if ($Line -match ", Error" -or $Line -match "0x[0-9a-fA-F]{8}") {
                        $RelevantLines += $Line
                    }
                }
            }
        }
        $Reader.Close(); $FileStream.Close()

        if ($RelevantLines.Count -eq 0) {
            Write-Output "   [CBS LOG] No explicit error lines found."
        }
        else {
            foreach ($ErrLine in $RelevantLines) {
                foreach ($Key in $KnownErrors.Keys) {
                    if ($ErrLine -match $Key) {
                        Write-Output "   [CRITICAL] $($KnownErrors[$Key]) ($Key)"
                    }
                }
                Write-Output "   [LOG] $ErrLine"
            }
        }
    }
    catch { Write-Output "   Error reading CBS Log: $($_.Exception.Message)" }
}

# --- 2. START ---
Write-Output "Starting Maintenance. Mode: $Mode"

# Service Fix (Hardened with Null Check)
try {
    $serv = Get-Service "TrustedInstaller" -ErrorAction SilentlyContinue
    if ($serv) {
        if ($serv.Status -ne "Running") {
            Set-Service "TrustedInstaller" -StartupType Manual
            Start-Service "TrustedInstaller"
        }
    } else {
        Write-Output "   Warning: TrustedInstaller service not found. Proceeding..."
    }
} catch { Write-Output "   Warning: Service check failed." }

# --- 3. LOGIC GATES ---
$RunRepair = $false

if ($Mode -eq "Force") {
    Write-Output "Step 1: Force mode selected. Skipping scan."
    $RunRepair = $true
}
else {
    Write-Output "Step 1: Scanning Component Store Health..."
    $scanOutput = Invoke-DismCommand -Arguments "/Online /Cleanup-Image /ScanHealth /English"
    $scanString = $scanOutput -join "`n"

    if ($scanString -match "No component store corruption detected") {
        Write-Output "   STATUS: System is Healthy. No repair needed."
    }
    elseif ($scanString -match "component store is repairable" -or $scanString -match "corruption detected") {
        Write-Output "   STATUS: Corruption Detected."
        Write-Output "   [!] Analysing corruption details..."
        Get-CbsAnalysis -StartTime $ScriptStartTime
        
        if ($Mode -ne "Audit") {
            $RunRepair = $true
        } else {
            Write-Output "   Audit Mode: Skipping repair."
        }
    }
    else {
        Write-Output "   STATUS: Unknown result. Defaulting to Repair."
        $RunRepair = $true
    }
}

# --- 4. REPAIR EXECUTION ---
if ($RunRepair) {
    Write-Output "Step 2: Starting Repair Operation..."
    $null = Invoke-DismCommand -Arguments "/Online /Cleanup-Image /RestoreHealth /English"
    
    if ($global:DismExitCode -eq 0) {
        Write-Output "   [SYSTEM] Repair Sequence Finalized."
    }
    else {
        Write-Output "   [FAILURE] Repair failed (Exit Code: $global:DismExitCode)."
        Get-CbsAnalysis -StartTime $ScriptStartTime
        exit 1
    }
}

# --- 5. SFC (Hardened with Path Check and Null Check) ---
Write-Output "`nStep 3: Running SFC..."

# Use the safe path variable we defined at the top
if (Test-Path $SfcPath) {
    try {
        $sfcProcess = Start-Process -FilePath $SfcPath -ArgumentList "/scannow" -Wait -NoNewWindow -PassThru
        
        # NULL CHECK: Did the process actually start?
        if ($sfcProcess) {
            Write-Output "SFC Completed with Exit Code: $($sfcProcess.ExitCode)"
            if ($sfcProcess.ExitCode -ne 0) { exit 1 }
        } else {
            Write-Output "   [FAILURE] SFC failed to launch (Process object is null)."
            exit 1
        }
    }
    catch {
        Write-Output "   [FAILURE] Failed to execute SFC: $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Output "   [FAILURE] sfc.exe not found at $SfcPath"
    exit 1
}

exit 0
