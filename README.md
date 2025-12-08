# HardenedDISM
This script is designed to run as SYSTEM. If you are testing this manually, you must run your PowerShell terminal as Administrator, or the service checks and DISM commands will fail.

This PowerShell script serves as an advanced wrapper for Windows repair utilities (DISM and SFC), designed for unattended execution and robust error handling. Unlike standard batch implementations, this script actively parses the Windows Component Based Servicing (CBS) log to identify specific failure causes when repairs are unsuccessful.

It is made to run in restricted environments (e.g., NT AUTHORITY\SYSTEM) and handles file locking issues that typically prevent scripts from reading logs during active repair sessions.

Key Features

Intelligent Workflow: Automatically chains DISM /ScanHealth, DISM /RestoreHealth, and SFC /scannow based on corruption detection.

Locked File Access: Utilizes .NET [System.IO.FileStream] with ReadWrite sharing to parse CBS.log even while TrustedInstaller.exe holds an exclusive lock on the file.

Error Analysis: If a repair fails, the script parses the log for specific error codes (e.g., 0x800f081F, 0x80070002) and outputs the root cause to the console.

Locale Independence: Forces DISM to output in English to ensure regex status matching works correctly regardless of the host OS language settings.

Service Recovery: automatically validates and attempts to start the TrustedInstaller service if it is disabled or stopped.

Usage The script requires Administrative privileges.

**powershell.exe -ExecutionPolicy Bypass -File .\Repair-SystemImage.ps1**

Return Codes The script passes through the exit code from the final sfc.exe process, allowing RMM tools or CI/CD pipelines to determine the final system health status.


# ---  ERROR DATABASE (For CBS Analysis) ---
    "0x80070002" = "ERROR_FILE_NOT_FOUND
    "0x800f0831" = "CBS_E_STORE_CORRUPTION
    "0x8007000D" = "ERROR_INVALID_DATA
    "0x800F081F" = "CBS_E_SOURCE_MISSING
    "0x80073712" = "ERROR_SXS_COMPONENT_STORE_CORRUPT
    "0x800736CC" = "ERROR_SXS_FILE_HASH_MISMATCH
    "0x800705B9" = "ERROR_XML_PARSE_ERROR
    "0x80070246" = "ERROR_ILLEGAL_CHARACTER
    "0x8007370D" = "ERROR_SXS_IDENTITY_PARSE_ERROR
    "0x8007370B" = "ERROR_SXS_INVALID_IDENTITY_ATTRIBUTE_NAME
    "0x8007370A" = "ERROR_SXS_INVALID_IDENTITY_ATTRIBUTE_VALUE
    "0x80070057" = "ERROR_INVALID_PARAMETER
    "0x800B0100" = "TRUST_E_NOSIGNATURE
    "0x80092003" = "CRYPT_E_FILE_ERROR
    "0x800B0101" = "CERT_E_EXPIRED
    "0x8007371B" = "ERROR_SXS_TRANSACTION_CLOSURE_INCOMPLETE
    "0x80070490" = "ERROR_NOT_FOUND
    "0x800f0984" = "PSFX_E_MATCHING_BINARY_MISSING
    "0x800f0986" = "PSFX_E_APPLY_FORWARD_DELTA_FAILED
    "0x800f0982" = "PSFX_E_MATCHING_COMPONENT_NOT_FOUND
    "0x8024002E" = "WU_E_WU_DISABLED
    "0x800f0906" = "CBS_E_DOWNLOAD_FAILURE

