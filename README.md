## Admin tools

### WinAdminToolkit

`tools/WinAdminToolkit.ps1` is an interactive PowerShell toolkit for Windows sysadmin diagnostics and common maintenance tasks.

It includes menu-driven sections for:

- system and hardware information
- performance snapshots
- disks and volumes
- network information and connectivity tests
- services
- Windows event logs
- local users and groups
- scheduled tasks
- startup items
- quick security checks
- common repair tools
- full report export
- advanced tools for security auditing, network diagnostics, software inventory, performance analysis, Windows health checks, and HTML/JSON/ZIP exports

Run it with:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\WinAdminToolkit.ps1
```

Some actions require an elevated PowerShell session.

### Advanced tools

The `14. Outils avancés` menu adds read-only advanced diagnostics by default:

- Windows security audit: BitLocker, UAC, local password policy, local accounts, SMB shares, firewall allow rules, and active sessions
- advanced network diagnostics: IPv4 routes, neighbor cache, listening TCP ports with owning processes, DNS client cache, WinHTTP proxy, and multi-target reachability tests
- software and patch inventory: installed applications, hotfixes, .NET versions, and third-party auto-start services
- performance analysis: sampled CPU/memory/disk counters, top CPU/memory processes, low disk space checks, and recent application crash events
- Windows health checks: pending reboot indicators, critical services, WMI, WinRM, scheduled task anomalies, and Windows Update events
- advanced exports: JSON, HTML, and ZIP reports written to `Desktop\WinAdminToolkit-Reports`

## Refactoring notes

The toolkit was refactored to follow PowerShell approved verb naming conventions:

- `Pause-Toolkit` was renamed to `Wait-ToolkitPrompt`.
- `Ensure-ReportRoot` was renamed to `New-ReportRoot`.

The script also records user actions in a daily log file under:

`Desktop\WinAdminToolkit-Reports\actions-YYYYMMDD.log`

Logged actions include script start and exit, menu selections, service searches and restart confirmations, network test targets, event log searches, repair actions, and report exports.
