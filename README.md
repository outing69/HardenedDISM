# PowerShell Windows Component Store Repair & Diagnosis Tool

> **A "Smart" wrapper for DISM and SFC that detects corruption, repairs only when necessary, and diagnoses the root cause of failures by parsing the CBS.log.**

![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## 🚀 Overview

Standard repair scripts often run `DISM /RestoreHealth` blindly, wasting time and resources on healthy systems. This tool uses **Logic Gates** to assess system health first. It is designed for both **Interactive Use** (showing progress bars) and **RMM Automation** (Datto, NinjaOne, ConnectWise) with specific "Silent" modes and robust exit code handling.

### Key Features
* **🧠 Logic Gates:** Runs `/ScanHealth` first. Only runs the heavy `/RestoreHealth` operation if actual corruption is detected.
* **🔍 Root Cause Analysis:** If a repair fails (or corruption is found), the script bypasses `TrustedInstaller` locks to read the `CBS.log`, translating obscure hex codes (e.g., `0x800f081f`) into human-readable errors.
* **🛡️ RMM Hardened:** Automatically detects if running as a 32-bit agent (SysWOW64) on a 64-bit OS and redirects to `Sysnative` to ensure `DISM` and `SFC` execute correctly.
* **⚡ Responsive UI:** Uses `Tee-Object` to capture output for logic checks while simultaneously streaming progress bars to the console for human operators.

---

## 📥 Installation

1. Download the script `Invoke-WinSxSRepair.ps1` from this repository.
2. Upload it to your RMM script library or save it to your local machine.

## 💻 Usage

### Interactive Mode (Standalone)
Run the script in an Administrator PowerShell console. It will display progress bars and live status updates.

```powershell
# Default (Scan first, repair if needed)
.\Invoke-WinSxSRepair.ps1

# Force a repair (Skip scan)
.\Invoke-WinSxSRepair.ps1 -Mode Force

### RMM / Silent Mode

Use the `-Silent` switch to suppress progress bars (prevents log bloat in RMM dashboards).

```powershell
.\Invoke-WinSxSRepair.ps1 -Mode Auto -Silent
```

-----

## ⚙️ Parameters

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| **`-Mode`** | String | `"Auto"` | **`Auto`**: Scan first. If corrupt, Repair.<br>**`Audit`**: Scan only. Log corruption but do not repair.<br>**`Force`**: Skip scan. Run Repair immediately. |
| **`-Silent`** | Switch | `$false` | Suppresses console progress bars (e.g., `10.1%`, `10.2%`) to keep RMM logs clean. |

-----

## 🔧 RMM Configuration Guide

This script includes a "Shim" that automatically maps Environment Variables to script parameters, making it native for tools like **Datto RMM**.

### Datto RMM Setup

1.  **Create Component:** Select "PowerShell" as the script type.
2.  **Paste Script:** Copy the content of `Invoke-WinSxSRepair.ps1`.
3.  **Define Variables:**
      * `Mode` (Selection): Options `Auto`, `Audit`, `Force`. Default: `Auto`.
      * `Silent` (Boolean): Default `true`.
4.  **Set Post-Conditions (Alerting):**
      * **Alert on Failure:** Trigger if StdOut contains `[FAILURE]`.
      * **Alert on Critical Corruption:** Trigger if StdOut contains `[CRITICAL]`.

### Other RMMs (NinjaOne, ConnectWise, N-Able)

Ensure the script is run as **System** (NT AUTHORITY\\SYSTEM). Pass parameters normally via the "Script Parameters" field:
`-Mode "Auto" -Silent`

-----

## 📝 Error Codes & Logging

The script uses standard exit codes for RMM monitoring:

  * **`0`**: Success (System Healthy or Repaired Successfully).
  * **`1`**: Failure (Repair failed, SFC failed, or Critical Error).

**Log Analysis:**
The script outputs tagged logs for easy parsing:

  * `[SYSTEM]`: General status updates.
  * `[CRITICAL]`: Known error matched in CBS.log (e.g., `CBS_E_SOURCE_MISSING`).
  * `[FAILURE]`: Operation failed.
  * `[LOG]`: Raw error line from CBS.log.

-----

## 📜 License

MIT License

Copyright (c) 2025

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
