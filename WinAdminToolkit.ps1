<#
.SYNOPSIS
  Couteau suisse PowerShell pour sysadmin Windows.

.DESCRIPTION
  Menu interactif regroupant des commandes de diagnostic et d'administration courante.
  Par défaut, le script privilégie les actions en lecture seule. Les actions de changement
  demandent confirmation.

.NOTES
  Auteur: Warp / Oz
  Compatibilité: Windows PowerShell 5.1+
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'

$Script:ReportRoot = Join-Path $env:USERPROFILE 'Desktop\WinAdminToolkit-Reports'
$Script:LogPath = $null

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Title {
    param([string]$Title)
    Clear-Host
    Write-Host "============================================================" -ForegroundColor DarkCyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor DarkCyan
}

function Wait-ToolkitPrompt {
    Write-Host ''
    Read-Host 'Appuie sur Entrée pour continuer' | Out-Null
}

function New-ReportRoot {
    if (-not (Test-Path $Script:ReportRoot)) {
        New-Item -ItemType Directory -Path $Script:ReportRoot -Force | Out-Null
    }
}

function Initialize-ActionLog {
    New-ReportRoot
    $stamp = Get-Date -Format 'yyyyMMdd'
    $Script:LogPath = Join-Path $Script:ReportRoot "actions-$stamp.log"
    Write-ActionLog -Action 'Script démarré' -Details "Admin=$(Test-IsAdmin); User=$env:USERNAME; Computer=$env:COMPUTERNAME"
}

function Write-ActionLog {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [string]$Details = ''
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Script:LogPath)) {
            New-ReportRoot
            $stamp = Get-Date -Format 'yyyyMMdd'
            $Script:LogPath = Join-Path $Script:ReportRoot "actions-$stamp.log"
        }

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $line = if ([string]::IsNullOrWhiteSpace($Details)) {
            "[$timestamp] [$env:USERNAME@$env:COMPUTERNAME] $Action"
        } else {
            "[$timestamp] [$env:USERNAME@$env:COMPUTERNAME] $Action - $Details"
        }
        Add-Content -Path $Script:LogPath -Value $line -Encoding UTF8
    } catch {
        Write-Warning "Impossible d'écrire dans le journal: $($_.Exception.Message)"
    }
}

function Save-TextReport {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Collector
    )

    New-ReportRoot
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $safeName = $Name -replace '[^a-zA-Z0-9_-]', '_'
    $path = Join-Path $Script:ReportRoot "$safeName-$stamp.txt"

    & $Collector | Out-File -FilePath $path -Encoding UTF8 -Width 240
    Write-ActionLog -Action 'Rapport créé' -Details $path
    Write-Host "Rapport créé: $path" -ForegroundColor Green
}

function Invoke-Choice {
    param(
        [string]$Prompt = 'Choix',
        [string[]]$ValidChoices
    )

    do {
        $choice = Read-Host $Prompt
    } until ($ValidChoices -contains $choice)
    return $choice
}

function Get-ProcessCpuValue {
    param([object]$Process)

    if ($null -eq $Process.CPU) { return 0 }
    if ($Process.CPU -is [timespan]) { return $Process.CPU.TotalSeconds }
    return [double]$Process.CPU
}

function Get-LocalAdministratorsGroupName {
    try {
        $adminSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
        return $adminSid.Translate([System.Security.Principal.NTAccount]).Value.Split('\\')[-1]
    } catch {
        return 'Administrators'
    }
}

function Get-ObjectPropertyValue {
    param(
        [Parameter(Mandatory = $true)][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Show-SystemInfo {
    Write-ActionLog -Action 'Consultation' -Details 'Infos système / matériel'
    Write-Title 'Système / OS / matériel'
    Get-ComputerInfo | Select-Object CsName, WindowsProductName, WindowsVersion, OsArchitecture, OsBuildNumber, BiosSeralNumber, CsManufacturer, CsModel, CsProcessors, CsTotalPhysicalMemory | Format-List
    Write-Host ''
    Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, LastBootUpTime, InstallDate | Format-List
    Write-Host ''
    Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed | Format-Table -AutoSize
    Write-Host ''
    Get-CimInstance Win32_PhysicalMemory | Select-Object BankLabel, Manufacturer, Capacity, Speed | Format-Table -AutoSize
    Wait-ToolkitPrompt
}

function Show-PerformanceSnapshot {
    Write-ActionLog -Action 'Consultation' -Details 'Snapshot performances'
    Write-Title 'Snapshot performances'
    Write-Host 'CPU:' -ForegroundColor Yellow
    Get-CimInstance Win32_Processor | Select-Object Name, LoadPercentage | Format-Table -AutoSize
    Write-Host 'Mémoire:' -ForegroundColor Yellow
    Get-CimInstance Win32_OperatingSystem | Select-Object @{Name='TotalGB';Expression={[math]::Round($_.TotalVisibleMemorySize / 1MB, 2)}}, @{Name='FreeGB';Expression={[math]::Round($_.FreePhysicalMemory / 1MB, 2)}} | Format-Table -AutoSize
    Write-Host 'Top processus CPU:' -ForegroundColor Yellow
    Get-Process | Select-Object Name, Id, CPU, WorkingSet64, Path, @{Name='CpuSeconds';Expression={Get-ProcessCpuValue $_}} | Sort-Object CpuSeconds -Descending | Select-Object -First 15 Name, Id, CPU, WorkingSet64, Path | Format-Table -AutoSize
    Write-Host 'Top processus mémoire:' -ForegroundColor Yellow
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 15 Name, Id, @{Name='MemoryMB';Expression={[math]::Round($_.WorkingSet64 / 1MB, 2)}}, Path | Format-Table -AutoSize
    Wait-ToolkitPrompt
}

function Show-DiskInfo {
    Write-ActionLog -Action 'Consultation' -Details 'Disques / volumes'
    Write-Title 'Disques / volumes'
    Get-Volume | Sort-Object DriveLetter | Select-Object DriveLetter, FileSystemLabel, FileSystem, HealthStatus, OperationalStatus, SizeRemaining, Size | Format-Table -AutoSize
    Write-Host ''
    Get-CimInstance Win32_LogicalDisk | Select-Object DeviceID, VolumeName, FileSystem, @{Name='SizeGB';Expression={[math]::Round($_.Size / 1GB, 2)}}, @{Name='FreeGB';Expression={[math]::Round($_.FreeSpace / 1GB, 2)}}, @{Name='FreePct';Expression={if ($_.Size) {[math]::Round(($_.FreeSpace / $_.Size) * 100, 2)} else {0}}} | Format-Table -AutoSize
    Wait-ToolkitPrompt
}

function Show-NetworkInfo {
    Write-ActionLog -Action 'Consultation' -Details 'Réseau'
    Write-Title 'Réseau'
    Write-Host 'Interfaces:' -ForegroundColor Yellow
    Get-NetAdapter | Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress | Format-Table -AutoSize
    Write-Host 'IP:' -ForegroundColor Yellow
    Get-NetIPConfiguration | Format-List
    Write-Host 'DNS:' -ForegroundColor Yellow
    Get-DnsClientServerAddress | Format-Table -AutoSize
    Write-Host 'Connexions TCP établies:' -ForegroundColor Yellow
    Get-NetTCPConnection -State Established | Select-Object -First 50 LocalAddress, LocalPort, RemoteAddress, RemotePort, OwningProcess | Format-Table -AutoSize
    Wait-ToolkitPrompt
}

function Invoke-NetworkTests {
    Write-ActionLog -Action 'Ouverture outil' -Details 'Tests réseau'
    Write-Title 'Tests réseau'
    $target = Read-Host 'Cible à tester (ex: 8.8.8.8, serveur, domaine)'
    if ([string]::IsNullOrWhiteSpace($target)) {
        Write-ActionLog -Action 'Test réseau annulé' -Details 'Cible vide'
        return
    }

    Write-ActionLog -Action 'Test réseau' -Details "Ping cible=$target"
    Write-Host "Ping $target" -ForegroundColor Yellow
    Test-Connection -ComputerName $target -Count 4 -ErrorAction Continue | Format-Table -AutoSize

    $port = Read-Host 'Port TCP optionnel à tester (Entrée pour ignorer)'
    if (-not [string]::IsNullOrWhiteSpace($port)) {
        Write-ActionLog -Action 'Test réseau' -Details "TCP cible=$target port=$port"
        Test-NetConnection -ComputerName $target -Port ([int]$port) | Format-List
    }

    Write-Host 'Résolution DNS:' -ForegroundColor Yellow
    Resolve-DnsName $target -ErrorAction Continue | Format-Table -AutoSize
    Wait-ToolkitPrompt
}

function Show-ServiceTools {
    Write-ActionLog -Action 'Ouverture outil' -Details 'Services'
    Write-Title 'Services'
    Write-Host '1. Services arrêtés mais en démarrage automatique'
    Write-Host '2. Rechercher un service'
    Write-Host '3. Redémarrer un service (confirmation)'
    Write-Host '0. Retour'
    $choice = Invoke-Choice -ValidChoices @('1','2','3','0')
    Write-ActionLog -Action 'Choix services' -Details $choice

    switch ($choice) {
        '1' {
            Write-ActionLog -Action 'Consultation' -Details 'Services auto arrêtés'
            Get-CimInstance Win32_Service | Where-Object { $_.StartMode -eq 'Auto' -and $_.State -ne 'Running' } | Select-Object Name, DisplayName, State, StartMode | Format-Table -AutoSize
            Wait-ToolkitPrompt
        }
        '2' {
            $name = Read-Host 'Nom ou partie du nom'
            Write-ActionLog -Action 'Recherche service' -Details $name
            Get-Service | Where-Object { $_.Name -like "*$name*" -or $_.DisplayName -like "*$name*" } | Sort-Object DisplayName | Format-Table -AutoSize
            Wait-ToolkitPrompt
        }
        '3' {
            $name = Read-Host 'Nom exact du service à redémarrer'
            Write-ActionLog -Action 'Demande redémarrage service' -Details $name
            $service = Get-Service -Name $name -ErrorAction SilentlyContinue
            if (-not $service) {
                Write-ActionLog -Action 'Redémarrage service impossible' -Details "Service introuvable: $name"
                Write-Host 'Service introuvable.' -ForegroundColor Red
            } else {
                $confirm = Read-Host "Confirmer le redémarrage de $($service.Name) ? (O/N)"
                if ($confirm -match '^[OoYy]$') {
                    Write-ActionLog -Action 'Redémarrage service confirmé' -Details $service.Name
                    Restart-Service -Name $service.Name -Force -ErrorAction Continue
                    Get-Service -Name $service.Name | Format-Table -AutoSize
                } else {
                    Write-ActionLog -Action 'Redémarrage service annulé' -Details $service.Name
                }
            }
            Wait-ToolkitPrompt
        }
    }
}

function Show-EventTools {
    Write-ActionLog -Action 'Ouverture outil' -Details 'Journaux événements'
    Write-Title 'Journaux événements'
    Write-Host '1. Erreurs système récentes'
    Write-Host '2. Erreurs application récentes'
    Write-Host '3. Événements redémarrage/arrêt'
    Write-Host '4. Recherche par LogName et Provider'
    Write-Host '0. Retour'
    $choice = Invoke-Choice -ValidChoices @('1','2','3','4','0')
    Write-ActionLog -Action 'Choix journaux événements' -Details $choice

    switch ($choice) {
        '1' { Write-ActionLog -Action 'Consultation événements' -Details 'Erreurs système récentes'; Get-WinEvent -FilterHashtable @{LogName='System'; Level=2; StartTime=(Get-Date).AddDays(-7)} -MaxEvents 50 | Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message | Format-List; Wait-ToolkitPrompt }
        '2' { Write-ActionLog -Action 'Consultation événements' -Details 'Erreurs application récentes'; Get-WinEvent -FilterHashtable @{LogName='Application'; Level=2; StartTime=(Get-Date).AddDays(-7)} -MaxEvents 50 | Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message | Format-List; Wait-ToolkitPrompt }
        '3' { Write-ActionLog -Action 'Consultation événements' -Details 'Redémarrage/arrêt'; Get-WinEvent -FilterHashtable @{LogName='System'; Id=6005,6006,6008,1074,41; StartTime=(Get-Date).AddDays(-30)} -MaxEvents 100 | Select-Object TimeCreated, ProviderName, Id, Message | Format-List; Wait-ToolkitPrompt }
        '4' {
            $log = Read-Host 'LogName (ex: System, Application)'
            $provider = Read-Host 'ProviderName optionnel'
            Write-ActionLog -Action 'Recherche événements' -Details "LogName=$log; Provider=$provider"
            $filter = @{ LogName = $log; StartTime = (Get-Date).AddDays(-7) }
            if (-not [string]::IsNullOrWhiteSpace($provider)) { $filter.ProviderName = $provider }
            Get-WinEvent -FilterHashtable $filter -MaxEvents 100 | Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message | Format-List
            Wait-ToolkitPrompt
        }
    }
}

function Show-UserGroupTools {
    Write-ActionLog -Action 'Consultation' -Details 'Utilisateurs / groupes locaux'
    Write-Title 'Utilisateurs / groupes locaux'
    Write-Host 'Administrateurs locaux:' -ForegroundColor Yellow
    $adminGroup = Get-LocalAdministratorsGroupName
    Get-LocalGroupMember -Group $adminGroup -ErrorAction Continue | Format-Table -AutoSize
    Write-Host 'Utilisateurs locaux:' -ForegroundColor Yellow
    Get-LocalUser | Select-Object Name, Enabled, LastLogon, PasswordRequired, PasswordLastSet | Format-Table -AutoSize
    Write-Host 'Groupes locaux:' -ForegroundColor Yellow
    Get-LocalGroup | Sort-Object Name | Format-Table -AutoSize
    Wait-ToolkitPrompt
}

function Show-ScheduledTasks {
    Write-ActionLog -Action 'Consultation' -Details 'Tâches planifiées'
    Write-Title 'Tâches planifiées'
    Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' } | Select-Object TaskName, TaskPath, State, Author | Sort-Object TaskPath, TaskName | Format-Table -AutoSize
    Wait-ToolkitPrompt
}

function Show-StartupItems {
    Write-ActionLog -Action 'Consultation' -Details 'Démarrage automatique'
    Write-Title 'Démarrage automatique'
    Write-Host 'Clés Run utilisateur/machine:' -ForegroundColor Yellow
    Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue | Format-List
    Get-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue | Format-List
    Write-Host 'Dossier Startup:' -ForegroundColor Yellow
    Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" -ErrorAction SilentlyContinue | Format-Table -AutoSize
    Get-ChildItem "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup" -ErrorAction SilentlyContinue | Format-Table -AutoSize
    Wait-ToolkitPrompt
}

function Show-SecuritySnapshot {
    Write-ActionLog -Action 'Consultation' -Details 'Sécurité rapide'
    Write-Title 'Sécurité rapide'
    Write-Host 'Pare-feu:' -ForegroundColor Yellow
    Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction | Format-Table -AutoSize
    Write-Host 'Defender:' -ForegroundColor Yellow
    Get-MpComputerStatus -ErrorAction Continue | Select-Object AMServiceEnabled, AntivirusEnabled, RealTimeProtectionEnabled, AntispywareEnabled, NISEnabled, QuickScanAge, FullScanAge | Format-List
    Write-Host 'Partages SMB:' -ForegroundColor Yellow
    Get-SmbShare -ErrorAction Continue | Select-Object Name, Path, Description, CurrentUsers | Format-Table -AutoSize
    Wait-ToolkitPrompt
}

function Invoke-QuickRepairTools {
    Write-ActionLog -Action 'Ouverture outil' -Details 'Outils réparation courants'
    Write-Title 'Outils de réparation courants'
    Write-Host '1. Vider le cache DNS'
    Write-Host '2. Renouveler DHCP'
    Write-Host '3. Vérifier les fichiers système: sfc /scannow'
    Write-Host '4. Santé image Windows: DISM /Online /Cleanup-Image /RestoreHealth'
    Write-Host '0. Retour'
    $choice = Invoke-Choice -ValidChoices @('1','2','3','4','0')
    Write-ActionLog -Action 'Choix réparation' -Details $choice

    switch ($choice) {
        '1' { Write-ActionLog -Action 'Réparation lancée' -Details 'ipconfig /flushdns'; ipconfig /flushdns; Wait-ToolkitPrompt }
        '2' { Write-ActionLog -Action 'Réparation lancée' -Details 'ipconfig /release + ipconfig /renew'; ipconfig /release; ipconfig /renew; Wait-ToolkitPrompt }
        '3' { Write-ActionLog -Action 'Réparation lancée' -Details 'sfc /scannow'; sfc /scannow; Wait-ToolkitPrompt }
        '4' { Write-ActionLog -Action 'Réparation lancée' -Details 'DISM /Online /Cleanup-Image /RestoreHealth'; DISM /Online /Cleanup-Image /RestoreHealth; Wait-ToolkitPrompt }
    }
}

function Get-InstalledSoftware {
    $paths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($path in $paths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
            ForEach-Object {
                $displayName = Get-ObjectPropertyValue -InputObject $_ -Name 'DisplayName'
                if (-not [string]::IsNullOrWhiteSpace($displayName)) {
                    [pscustomobject]@{
                        DisplayName = $displayName
                        DisplayVersion = Get-ObjectPropertyValue -InputObject $_ -Name 'DisplayVersion'
                        Publisher = Get-ObjectPropertyValue -InputObject $_ -Name 'Publisher'
                        InstallDate = Get-ObjectPropertyValue -InputObject $_ -Name 'InstallDate'
                        InstallLocation = Get-ObjectPropertyValue -InputObject $_ -Name 'InstallLocation'
                    }
                }
            }
    }
}

function Get-DotNetVersions {
    Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP' -Recurse -ErrorAction SilentlyContinue |
        Get-ItemProperty -ErrorAction SilentlyContinue |
        ForEach-Object {
            $version = Get-ObjectPropertyValue -InputObject $_ -Name 'Version'
            $release = Get-ObjectPropertyValue -InputObject $_ -Name 'Release'
            if ($version -or $release) {
                [pscustomobject]@{
                    PSChildName = Get-ObjectPropertyValue -InputObject $_ -Name 'PSChildName'
                    Version = $version
                    Release = $release
                    Install = Get-ObjectPropertyValue -InputObject $_ -Name 'Install'
                }
            }
        }
}

function Test-PendingReboot {
    $checks = [ordered]@{
        ComponentBasedServicing = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        WindowsUpdate = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        PendingFileRename = $false
    }

    $sessionManager = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    if ($sessionManager -and $sessionManager.PendingFileRenameOperations) {
        $checks.PendingFileRename = $true
    }

    [pscustomobject]$checks
}

function Show-AdvancedSecurityAudit {
    Write-ActionLog -Action 'Consultation avancée' -Details 'Audit sécurité Windows'
    Write-Title 'Audit sécurité avancé'

    Write-Host 'BitLocker:' -ForegroundColor Yellow
    if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
        Get-BitLockerVolume -ErrorAction SilentlyContinue | Select-Object MountPoint, VolumeStatus, ProtectionStatus, EncryptionPercentage, LockStatus | Format-Table -AutoSize
    } else {
        Write-Host 'Module BitLocker indisponible sur ce système.' -ForegroundColor DarkYellow
    }

    Write-Host 'UAC:' -ForegroundColor Yellow
    Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction SilentlyContinue |
        Select-Object EnableLUA, ConsentPromptBehaviorAdmin, PromptOnSecureDesktop, EnableInstallerDetection | Format-List

    Write-Host 'Politique mot de passe locale:' -ForegroundColor Yellow
    net accounts

    Write-Host 'Comptes locaux:' -ForegroundColor Yellow
    Get-LocalUser -ErrorAction Continue | Select-Object Name, Enabled, LastLogon, PasswordRequired, PasswordLastSet, UserMayChangePassword | Format-Table -AutoSize

    Write-Host 'Sessions ouvertes:' -ForegroundColor Yellow
    quser 2>$null

    Write-Host 'Partages SMB et accès:' -ForegroundColor Yellow
    Get-SmbShare -ErrorAction Continue | Select-Object Name, Path, Description, CurrentUsers | Format-Table -AutoSize
    Get-SmbShare -ErrorAction SilentlyContinue | ForEach-Object {
        Get-SmbShareAccess -Name $_.Name -ErrorAction SilentlyContinue | Select-Object Name, AccountName, AccessControlType, AccessRight
    } | Format-Table -AutoSize

    Write-Host 'Règles firewall entrantes actives autorisées:' -ForegroundColor Yellow
    Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -ErrorAction Continue |
        Select-Object -First 50 DisplayName, Profile, Direction, Action, Enabled | Format-Table -AutoSize

    Wait-ToolkitPrompt
}

function Show-AdvancedNetworkDiagnostics {
    Write-ActionLog -Action 'Consultation avancée' -Details 'Diagnostic réseau avancé'
    Write-Title 'Diagnostic réseau avancé'

    Write-Host 'Routes IPv4:' -ForegroundColor Yellow
    Get-NetRoute -AddressFamily IPv4 -ErrorAction Continue | Sort-Object RouteMetric | Select-Object -First 50 DestinationPrefix, NextHop, InterfaceAlias, RouteMetric | Format-Table -AutoSize

    Write-Host 'Voisins ARP / NDP:' -ForegroundColor Yellow
    Get-NetNeighbor -ErrorAction Continue | Select-Object -First 100 InterfaceAlias, IPAddress, LinkLayerAddress, State | Format-Table -AutoSize

    Write-Host 'Ports TCP en écoute avec processus:' -ForegroundColor Yellow
    Get-NetTCPConnection -State Listen -ErrorAction Continue | ForEach-Object {
        $process = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        [pscustomobject]@{
            LocalAddress = $_.LocalAddress
            LocalPort = $_.LocalPort
            ProcessId = $_.OwningProcess
            ProcessName = $process.Name
            Path = $process.Path
        }
    } | Sort-Object LocalPort | Format-Table -AutoSize

    Write-Host 'Cache DNS client:' -ForegroundColor Yellow
    Get-DnsClientCache -ErrorAction Continue | Select-Object -First 50 Entry, RecordName, RecordType, Status, Data | Format-Table -AutoSize

    Write-Host 'Proxy WinHTTP:' -ForegroundColor Yellow
    netsh winhttp show proxy

    Write-Host 'Tests multi-cibles:' -ForegroundColor Yellow
    $targets = @('127.0.0.1', '8.8.8.8', '1.1.1.1', 'www.microsoft.com')
    $targets | ForEach-Object {
        $target = $_
        Test-NetConnection -ComputerName $target -InformationLevel Quiet -ErrorAction SilentlyContinue |
            ForEach-Object { [pscustomobject]@{ Target = $target; Reachable = $_ } }
    } | Format-Table -AutoSize

    Wait-ToolkitPrompt
}

function Show-SoftwareInventory {
    Write-ActionLog -Action 'Consultation avancée' -Details 'Inventaire logiciel et patching'
    Write-Title 'Inventaire logiciel et patching'

    Write-Host 'Logiciels installés:' -ForegroundColor Yellow
    Get-InstalledSoftware | Sort-Object DisplayName -Unique | Select-Object -First 150 DisplayName, DisplayVersion, Publisher, InstallDate | Format-Table -AutoSize

    Write-Host 'Hotfix / KB installées:' -ForegroundColor Yellow
    Get-HotFix -ErrorAction Continue | Sort-Object InstalledOn -Descending | Select-Object -First 80 HotFixID, Description, InstalledBy, InstalledOn | Format-Table -AutoSize

    Write-Host 'Versions .NET détectées:' -ForegroundColor Yellow
    Get-DotNetVersions | Format-Table -AutoSize

    Write-Host 'Services tiers en démarrage automatique:' -ForegroundColor Yellow
    Get-CimInstance Win32_Service -ErrorAction Continue |
        Where-Object { $_.StartMode -eq 'Auto' -and $_.PathName -and $_.PathName -notmatch '\\Windows\\|Microsoft' } |
        Select-Object Name, DisplayName, State, StartMode, PathName | Format-Table -AutoSize

    Wait-ToolkitPrompt
}

function Show-AdvancedPerformance {
    Write-ActionLog -Action 'Consultation avancée' -Details 'Performance approfondie'
    Write-Title 'Performance avancée'

    Write-Host 'Échantillons CPU / mémoire sur 5 secondes:' -ForegroundColor Yellow
    1..5 | ForEach-Object {
        $processor = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        [pscustomobject]@{
            TimeStamp = Get-Date
            CpuLoadPct = if ($processor) { $processor.LoadPercentage } else { $null }
            FreeMemoryMB = if ($os) { [math]::Round($os.FreePhysicalMemory / 1024, 2) } else { $null }
        }
        Start-Sleep -Seconds 1
    } | Format-Table -AutoSize

    Write-Host 'Top processus CPU:' -ForegroundColor Yellow
    Get-Process | Select-Object Name, Id, CPU, Handles, Threads, Path, @{Name='CpuSeconds';Expression={Get-ProcessCpuValue $_}}, @{Name='MemoryMB';Expression={[math]::Round($_.WorkingSet64 / 1MB, 2)}} | Sort-Object CpuSeconds -Descending | Select-Object -First 20 Name, Id, CPU, Handles, Threads, MemoryMB, Path | Format-Table -AutoSize

    Write-Host 'Volumes avec espace critique (< 15% libre):' -ForegroundColor Yellow
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Continue |
        Select-Object DeviceID, VolumeName, @{Name='SizeGB';Expression={[math]::Round($_.Size / 1GB, 2)}}, @{Name='FreeGB';Expression={[math]::Round($_.FreeSpace / 1GB, 2)}}, @{Name='FreePct';Expression={if ($_.Size) {[math]::Round(($_.FreeSpace / $_.Size) * 100, 2)} else {0}}} |
        Where-Object { $_.FreePct -lt 15 } | Format-Table -AutoSize

    Write-Host 'Crashs application récents:' -ForegroundColor Yellow
    Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000,1001; StartTime=(Get-Date).AddDays(-14)} -MaxEvents 30 -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, ProviderName, Id, Message | Format-List

    Wait-ToolkitPrompt
}

function Show-WindowsHealth {
    Write-ActionLog -Action 'Consultation avancée' -Details 'Santé Windows'
    Write-Title 'Santé Windows'

    Write-Host 'Redémarrage en attente:' -ForegroundColor Yellow
    Test-PendingReboot | Format-List

    Write-Host 'Services critiques:' -ForegroundColor Yellow
    $criticalServices = 'Winmgmt', 'EventLog', 'wuauserv', 'BITS', 'WinRM', 'MpsSvc', 'LanmanServer', 'LanmanWorkstation'
    Get-Service -Name $criticalServices -ErrorAction SilentlyContinue | Select-Object Name, DisplayName, Status, StartType | Format-Table -AutoSize

    Write-Host 'État WMI:' -ForegroundColor Yellow
    Get-CimInstance Win32_OperatingSystem -ErrorAction Continue | Select-Object Caption, Version, LastBootUpTime | Format-List

    Write-Host 'État WinRM:' -ForegroundColor Yellow
    Get-Service -Name WinRM -ErrorAction Continue | Select-Object Name, Status, StartType | Format-Table -AutoSize
    winrm enumerate winrm/config/listener 2>$null

    Write-Host 'Tâches planifiées non prêtes ou en erreur:' -ForegroundColor Yellow
    Get-ScheduledTask -ErrorAction Continue |
        Where-Object { $_.State -in @('Queued', 'Unknown') } |
        Select-Object TaskName, TaskPath, State, Author | Format-Table -AutoSize

    Write-Host 'Derniers événements Windows Update:' -ForegroundColor Yellow
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WindowsUpdateClient'; StartTime=(Get-Date).AddDays(-14)} -MaxEvents 30 -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, LevelDisplayName, Message | Format-List

    Wait-ToolkitPrompt
}

function Export-AdvancedReports {
    Write-ActionLog -Action 'Export demandé' -Details 'Rapports avancés HTML/JSON/ZIP'
    Write-Title 'Export avancé'
    New-ReportRoot
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $baseName = "rapport-avance-$stamp"
    $jsonPath = Join-Path $Script:ReportRoot "$baseName.json"
    $htmlPath = Join-Path $Script:ReportRoot "$baseName.html"
    $zipPath = Join-Path $Script:ReportRoot "$baseName.zip"

    $data = [ordered]@{
        GeneratedAt = Get-Date
        ComputerName = $env:COMPUTERNAME
        UserName = $env:USERNAME
        IsAdmin = Test-IsAdmin
        System = Get-ComputerInfo | Select-Object CsName, WindowsProductName, WindowsVersion, OsArchitecture, OsBuildNumber, CsManufacturer, CsModel, CsTotalPhysicalMemory
        Volumes = Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue | Select-Object DeviceID, VolumeName, FileSystem, Size, FreeSpace
        Network = Get-NetIPConfiguration -ErrorAction SilentlyContinue | Select-Object InterfaceAlias, IPv4Address, IPv4DefaultGateway, DNSServer
        PendingReboot = Test-PendingReboot
        ServicesAutoStopped = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.StartMode -eq 'Auto' -and $_.State -ne 'Running' } | Select-Object Name, DisplayName, State, StartMode
        HotFixes = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 50 HotFixID, Description, InstalledBy, InstalledOn
        InstalledSoftware = Get-InstalledSoftware | Sort-Object DisplayName -Unique | Select-Object -First 150 DisplayName, DisplayVersion, Publisher, InstallDate
        TopProcessesMemory = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 30 Name, Id, CPU, @{Name='MemoryMB';Expression={[math]::Round($_.WorkingSet64 / 1MB, 2)}}
    }

    $data | ConvertTo-Json -Depth 6 | Out-File -FilePath $jsonPath -Encoding UTF8 -Width 240

    $htmlSections = @()
    $htmlSections += $data.System | ConvertTo-Html -Fragment -PreContent '<h2>Système</h2>'
    $htmlSections += $data.Volumes | ConvertTo-Html -Fragment -PreContent '<h2>Volumes</h2>'
    $htmlSections += $data.ServicesAutoStopped | ConvertTo-Html -Fragment -PreContent '<h2>Services auto arrêtés</h2>'
    $htmlSections += $data.HotFixes | ConvertTo-Html -Fragment -PreContent '<h2>Hotfix récentes</h2>'
    $htmlSections += $data.InstalledSoftware | ConvertTo-Html -Fragment -PreContent '<h2>Logiciels installés</h2>'
    $htmlSections += $data.TopProcessesMemory | ConvertTo-Html -Fragment -PreContent '<h2>Top processus mémoire</h2>'
    ConvertTo-Html -Title 'WinAdminToolkit - Rapport avancé' -Body ($htmlSections -join "`n") | Out-File -FilePath $htmlPath -Encoding UTF8

    Compress-Archive -Path $jsonPath, $htmlPath -DestinationPath $zipPath -Force
    Write-ActionLog -Action 'Rapports avancés créés' -Details "$jsonPath; $htmlPath; $zipPath"
    Write-Host "Rapport JSON: $jsonPath" -ForegroundColor Green
    Write-Host "Rapport HTML: $htmlPath" -ForegroundColor Green
    Write-Host "Archive ZIP: $zipPath" -ForegroundColor Green
    Wait-ToolkitPrompt
}

function Show-AdvancedTools {
    do {
        Write-ActionLog -Action 'Ouverture outil' -Details 'Outils avancés'
        Write-Title 'Outils avancés'
        Write-Host '1. Audit sécurité Windows avancé'
        Write-Host '2. Diagnostic réseau avancé'
        Write-Host '3. Inventaire logiciel et patching'
        Write-Host '4. Analyse performance approfondie'
        Write-Host '5. Santé Windows'
        Write-Host '6. Export avancé HTML / JSON / ZIP'
        Write-Host '0. Retour'
        $choice = Invoke-Choice -ValidChoices @('1','2','3','4','5','6','0')
        Write-ActionLog -Action 'Choix outils avancés' -Details $choice

        switch ($choice) {
            '1' { Show-AdvancedSecurityAudit }
            '2' { Show-AdvancedNetworkDiagnostics }
            '3' { Show-SoftwareInventory }
            '4' { Show-AdvancedPerformance }
            '5' { Show-WindowsHealth }
            '6' { Export-AdvancedReports }
            '0' { return }
        }
    } while ($true)
}

function Export-FullReport {
    Write-ActionLog -Action 'Export demandé' -Details 'Rapport complet'
    Write-Title 'Export rapport complet'
    Save-TextReport -Name 'rapport-complet' -Collector {
        "=== Rapport WinAdminToolkit ==="
        "Date: $(Get-Date)"
        "Machine: $env:COMPUTERNAME"
        "Utilisateur: $env:USERNAME"
        "Admin: $(Test-IsAdmin)"
        ""
        "=== OS ==="
        Get-ComputerInfo | Select-Object CsName, WindowsProductName, WindowsVersion, OsArchitecture, OsBuildNumber, CsManufacturer, CsModel, CsTotalPhysicalMemory | Format-List | Out-String
        "=== Volumes ==="
        Get-Volume | Format-Table -AutoSize | Out-String
        "=== Réseau ==="
        Get-NetIPConfiguration | Format-List | Out-String
        "=== Services auto arrêtés ==="
        Get-CimInstance Win32_Service | Where-Object { $_.StartMode -eq 'Auto' -and $_.State -ne 'Running' } | Select-Object Name, DisplayName, State, StartMode | Format-Table -AutoSize | Out-String
        "=== Erreurs système 7 jours ==="
        Get-WinEvent -FilterHashtable @{LogName='System'; Level=2; StartTime=(Get-Date).AddDays(-7)} -MaxEvents 100 -ErrorAction SilentlyContinue | Select-Object TimeCreated, ProviderName, Id, Message | Format-List | Out-String
        "=== Top processus mémoire ==="
        Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 20 Name, Id, @{Name='MemoryMB';Expression={[math]::Round($_.WorkingSet64 / 1MB, 2)}} | Format-Table -AutoSize | Out-String
    }
    Wait-ToolkitPrompt
}

function Show-MainMenu {
    do {
        Write-Title 'WinAdminToolkit - couteau suisse sysadmin Windows'
        Write-Host "Mode administrateur: $(if (Test-IsAdmin) { 'Oui' } else { 'Non - certaines fonctions seront limitées' })"
        Write-Host "Journal actions: $Script:LogPath"
        Write-Host ''
        Write-Host '1. Infos système / matériel'
        Write-Host '2. Snapshot performances'
        Write-Host '3. Disques / volumes'
        Write-Host '4. Réseau'
        Write-Host '5. Tests réseau'
        Write-Host '6. Services'
        Write-Host '7. Journaux événements'
        Write-Host '8. Utilisateurs / groupes locaux'
        Write-Host '9. Tâches planifiées'
        Write-Host '10. Démarrage automatique'
        Write-Host '11. Sécurité rapide'
        Write-Host '12. Outils réparation courants'
        Write-Host '13. Export rapport complet'
        Write-Host '14. Outils avancés'
        Write-Host '0. Quitter'
        Write-Host ''
        $choice = Read-Host 'Choix'
        Write-ActionLog -Action 'Choix menu principal' -Details $choice

        switch ($choice) {
            '1' { Show-SystemInfo }
            '2' { Show-PerformanceSnapshot }
            '3' { Show-DiskInfo }
            '4' { Show-NetworkInfo }
            '5' { Invoke-NetworkTests }
            '6' { Show-ServiceTools }
            '7' { Show-EventTools }
            '8' { Show-UserGroupTools }
            '9' { Show-ScheduledTasks }
            '10' { Show-StartupItems }
            '11' { Show-SecuritySnapshot }
            '12' { Invoke-QuickRepairTools }
            '13' { Export-FullReport }
            '14' { Show-AdvancedTools }
            '0' { Write-ActionLog -Action 'Script terminé' -Details 'Quitter depuis le menu principal'; return }
            default { Write-ActionLog -Action 'Choix invalide' -Details $choice; Write-Host 'Choix invalide.' -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    } while ($true)
}

Initialize-ActionLog
Show-MainMenu


