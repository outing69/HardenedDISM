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
