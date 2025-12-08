# Context: NT AUTHORITY\SYSTEM
# Features: Service Auto-Fix | Text Parsing (NullRef Proof) | CBS Analysis

# --- RMM VARIABLE INTEGRATION ---
if (-not [string]::IsNullOrWhiteSpace($env:ForceExecutionPolicy)) {
    Write-Output "RMM Variable Detected: Setting ExecutionPolicy to '$env:ForceExecutionPolicy' for this process."
    try {
        Set-ExecutionPolicy -ExecutionPolicy $env:ForceExecutionPolicy -Scope Process -Force -ErrorAction Stop
    }
    catch {
        Write-Output "   Warning: Could not set ExecutionPolicy. GPO may be overriding this setting."
    }
}
else {
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
}

$ErrorActionPreference = "Continue"

# --- 0. ERROR DATABASE (For CBS Analysis) ---
$KnownErrors = @{
    "0x80070002" = "ERROR_FILE_NOT_FOUND";
    "0x800f0831" = "CBS_E_STORE_CORRUPTION";
    "0x8007000D" = "ERROR_INVALID_DATA";
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

# --- 1. PRE-FLIGHT CHECKS (Service Fix) ---
Write-Output "Step 0: Verifying Repair Infrastructure..."
try {
    $serv = Get-Service "TrustedInstaller" -ErrorAction Stop
    if ($serv.Status -ne "Running" -or $serv.StartType -eq "Disabled") {
        Write-Output "   Fixing TrustedInstaller Service state..."
        Set-Service "TrustedInstaller" -StartupType Manual
        Start-Service "TrustedInstaller"
        Start-Sleep -Seconds 2 
        Write-Output "   TrustedInstaller Started."
    }
} catch {
    Write-Output "   Warning: Could not adjust TrustedInstaller service. Proceeding anyway."
}

# --- 2. HELPER FUNCTION: CBS ANALYZER ---
Function Get-CbsAnalysis {
    Param($StartTime)
    Write-Output "`n[!] Repair Failed. Analyzing CBS.log for errors since $($StartTime.ToString('HH:mm:ss'))..."
    
    $LogPath = "$env:SystemRoot\Logs\CBS\CBS.log"
    if (-not (Test-Path $LogPath)) { return "CBS.log not found." }

    try {
        $FileStream = [System.IO.File]::Open($LogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $Reader = New-Object System.IO.StreamReader($FileStream)
        
        $RelevantLines = @()
        while (($Line = $Reader.ReadLine()) -ne $null) {
            if ($Line -match "^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})") {
                $TimeStr = $matches[1]
                try {
                    $LogTime = [DateTime]::ParseExact($TimeStr, "yyyy-MM-dd HH:mm:ss", $null)
                    if ($LogTime -ge $StartTime) {
                        if ($Line -match ", Error" -or $Line -match "0x[0-9a-fA-F]{8}") {
                            $RelevantLines += $Line
                        }
                    }
                } catch { continue }
            }
        }
        $Reader.Close()
        $FileStream.Close()

        if ($RelevantLines.Count -eq 0) {
            Write-Output "   No explicit error lines found in CBS.log for this timeframe."
        }
        else {
            foreach ($ErrLine in $RelevantLines) {
                foreach ($Key in $KnownErrors.Keys) {
                    if ($ErrLine -match $Key) {
                        Write-Output "   CRITICAL MATCH [$Key - $($KnownErrors[$Key])]"
                    }
                }
                Write-Output "   LOG: $ErrLine"
            }
        }
    }
    catch {
        Write-Output "   Error reading CBS Log: $($_.Exception.Message)"
    }
}

# --- 3. HELPER FUNCTION: RUN-PROCESS SAFE ---
# Helper to run commands without Tee-Object -Host issues
Function Run-ProcessSafe {
    Param($FileName, $Arguments)
    
    $pInfo = New-Object System.Diagnostics.ProcessStartInfo
    $pInfo.FileName = $FileName
    $pInfo.Arguments = $Arguments
    $pInfo.RedirectStandardOutput = $true
    $pInfo.UseShellExecute = $false
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pInfo
    $p.Start() | Out-Null

    $outputBuffer = ""
    while (-not $p.StandardOutput.EndOfStream) {
        $line = $p.StandardOutput.ReadLine()
        # Filter SFC Spam
        if ($line -notmatch "Verification \d+% complete") {
             Write-Host $line
        }
        $outputBuffer += "$line`n"
    }
    $p.WaitForExit()
    return $outputBuffer
}

# --- 4. COMPONENT STORE HEALTH (Scan) ---
Write-Output "Step 1: Assessing Component Store Health (DISM Binary)..."
Write-Output "   Please wait. This process may take 10-20 minutes..."

$scanOutputString = Run-ProcessSafe -FileName "dism.exe" -Arguments "/Online /Cleanup-Image /ScanHealth /English"

# Parse Text Output
if ($scanOutputString -match "component store is repairable" -or $scanOutputString -match "corruption detected") {
    Write-Output "   Status: Corruption detected. Initiating Repair..."
    
    # --- REPAIR EXECUTION ---
    $repairOutput = Run-ProcessSafe -FileName "dism.exe" -Arguments "/Online /Cleanup-Image /RestoreHealth /English"
    
    if ($repairOutput -match "The restore operation completed successfully") {
        Write-Output "   Repair Operation Completed Successfully."
    }
    else {
        Write-Output "   FATAL: Repair operation failed or incomplete."
        Get-CbsAnalysis -StartTime $ScriptStartTime
    }
}
elseif ($scanOutputString -match "No component store corruption detected") {
    Write-Output "   Status: Store is Healthy. No repair actions needed."
}
else {
    # Ambiguous result
    Write-Output "   Warning: Scan result unclear. Attempting force repair..."
    $repairOutput = Run-ProcessSafe -FileName "dism.exe" -Arguments "/Online /Cleanup-Image /RestoreHealth /English"

    if ($repairOutput -notmatch "The restore operation completed successfully") { 
        Get-CbsAnalysis -StartTime $ScriptStartTime 
    }
}

# --- 5. SYSTEM FILE CHECKER (SFC) ---
Write-Output "`nStep 2: Starting System File Checker (SFC)..."

# Running SFC via the helper to clean the logs
$sfcOutput = Run-ProcessSafe -FileName "sfc.exe" -Arguments "/scannow"

# Check exit code based on text output since we wrapped the process
if ($sfcOutput -match "Windows Resource Protection did not find any integrity violations") {
    Write-Output "Operation Complete. SFC Status: Clean (Exit Code 0)"
    exit 0
}
elseif ($sfcOutput -match "Windows Resource Protection found corrupt files and successfully repaired them") {
    Write-Output "Operation Complete. SFC Status: Repaired (Exit Code 1)"
    exit 1
}
else {
    Write-Output "Operation Complete. SFC Status: Failed or Unrepaired."
    exit -1
}
