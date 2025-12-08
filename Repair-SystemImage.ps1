# Context: NT AUTHORITY\SYSTEM
# Features: Service Auto-Fix | Text Parsing (NullRef Proof) | CBS Analysis

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
        # Small sleep to ensure service handles the start request
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
        # FORCE READ: Use FileStream to bypass 'TrustedInstaller' file locks
        $FileStream = [System.IO.File]::Open($LogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $Reader = New-Object System.IO.StreamReader($FileStream)
        
        $RelevantLines = @()
        while (($Line = $Reader.ReadLine()) -ne $null) {
            # Extract Timestamp (Standard CBS format: 2023-12-01 10:00:00)
            if ($Line -match "^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})") {
                $TimeStr = $matches[1]
                try {
                    # Explicit Parse to avoid Culture/Locale issues
                    $LogTime = [DateTime]::ParseExact($TimeStr, "yyyy-MM-dd HH:mm:ss", $null)
                    
                    if ($LogTime -ge $StartTime) {
                        # Filter for Errors or Hex codes
                        if ($Line -match ", Error" -or $Line -match "0x[0-9a-fA-F]{8}") {
                            $RelevantLines += $Line
                        }
                    }
                } catch {
                    # Skip line if date parsing fails
                    continue 
                }
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

# --- 3. COMPONENT STORE HEALTH (Scan) ---
Write-Output "Step 1: Assessing Component Store Health (DISM Binary)..."
Write-Output "   Please wait. This process may take 10-20 minutes..."

# Using Start-Process to ensure we get a clean exit code and handle stdout correctly
$pInfo = New-Object System.Diagnostics.ProcessStartInfo
$pInfo.FileName = "dism.exe"
$pInfo.Arguments = "/Online /Cleanup-Image /ScanHealth /English"
$pInfo.RedirectStandardOutput = $true
$pInfo.UseShellExecute = $false
$p = New-Object System.Diagnostics.Process
$p.StartInfo = $pInfo
$p.Start() | Out-Null

# Capture Output Live
$scanOutputString = ""
while (-not $p.StandardOutput.EndOfStream) {
    $line = $p.StandardOutput.ReadLine()
    $scanOutputString += "$line`n"
    Write-Host $line # Live output to host
}
$p.WaitForExit()

# Parse Text Output
if ($scanOutputString -match "component store is repairable" -or $scanOutputString -match "corruption detected") {
    Write-Output "   Status: Corruption detected. Initiating Repair..."
    
    # --- 4. REPAIR EXECUTION ---
    # We use direct invocation with Tee-Object here, but we check patterns for success
    # because Exit Codes in DISM RestoreHealth can be misleading (0 sometimes implies success even if files weren't fixed)
    $repairOutput = & dism.exe /Online /Cleanup-Image /RestoreHealth /English 2>&1 | Tee-Object -Host
    $repairString = $repairOutput -join "`n"
    
    # Check explicitly for success message
    if ($repairString -match "The restore operation completed successfully") {
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
    $repairOutput = & dism.exe /Online /Cleanup-Image /RestoreHealth /English 2>&1 | Tee-Object -Host
    $repairString = $repairOutput -join "`n"

    if ($repairString -notmatch "The restore operation completed successfully") { 
        Get-CbsAnalysis -StartTime $ScriptStartTime 
    }
}

# --- 5. SYSTEM FILE CHECKER (SFC) ---
Write-Output "`nStep 2: Starting System File Checker (SFC)..."
# Start-Process ensures we capture the specific Exit Code from SFC
$sfcProcess = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -Wait -NoNewWindow -PassThru

Write-Output "Operation Complete. SFC Exit Code: $($sfcProcess.ExitCode)"
exit $sfcProcess.ExitCode