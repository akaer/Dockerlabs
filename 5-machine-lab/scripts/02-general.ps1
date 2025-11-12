#Requires -Version 5.1
#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
if ($env:DEBUG -eq 'True') { Set-PSDebug -Trace 1 }

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$DebugPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$CustomTimeZone = 'W. Europe Standard Time'

function Test-Winget {
    param(
        [int]$Retries = 5,
        [int]$Delay = 15
    )

    Write-Host '[+] Verify winget is working as expected'

    $ErrorActionPreference = 'Continue'
    for ($i = 1; $i -le $Retries; $i++) {
        Write-Host "[-] Attempt $i/$Retries..."

        try {
            Write-Host '[-] Winget info:'
            $info = winget --info 2>&1

            if ($LASTEXITCODE -eq 0) {
                $info
            }

            Write-Host '[-] Winget sources:'
            $info = winget source list 2>&1

            if ($LASTEXITCODE -eq 0) {
                $info
            }

            return $true
        }
        catch {
            Write-Warning $_.Exception.Message
        }

        if ($i -lt $Retries) {
            Start-Sleep -Seconds $Delay
        }
    }

    Write-Error "[!] Winget verification failed after $Retries attempts"

    $ErrorActionPreference = 'Stop'
    return $false
}

Write-Host '[+] Configure defender'
Set-MpPreference -DisableRealtimeMonitoring $true
Set-MpPreference -DisableBehaviorMonitoring $true

Write-Host '[+] Set time zone'
Set-Timezone -Name "$CustomTimeZone"

Write-Host '[+] Configure Microsoft Edge browser'
$edgePolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
if (-not (Test-Path $edgePolicyPath)) {
    New-Item -Path $edgePolicyPath -Force | Out-Null
}
Set-ItemProperty -Path $edgePolicyPath -Name HideFirstRunExperience -Value 1
Set-ItemProperty -Path $edgePolicyPath -Name SyncDisabled -Value 1
Set-ItemProperty -Path $edgePolicyPath -Name RestoreOnStartup -Value 5
Set-ItemProperty -Path $edgePolicyPath -Name RestoreOnStartupURLs -Value 'about:blank'
Set-ItemProperty -Path $EdgePolicyPath -Name HomepageLocation -Value 'about:blank'
Set-ItemProperty -Path $EdgePolicyPath -Name NewTabPageLocation -Value 'about:blank'

Write-Host '[+] Disable Windows Updates'
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -Name NoAutoUpdate -Value 1
Stop-Service -Name wuauserv -Force -ErrorAction Stop
Set-Service -Name wuauserv -StartupType Disabled -ErrorAction Stop

Write-Host '[+] Enable file and printer sharing'
Set-NetFirewallRule -DisplayGroup 'File and Printer Sharing' -Enabled True -Profile Any | Out-Null

Write-Host '[+] Disable use simple file sharing'
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'ForceGuest' -Value '0' -PropertyType 'DWord' -Force | Out-Null

Write-Host '[+] Disable indexing on all drives'
Get-WmiObject Win32_Volume -Filter "IndexingEnabled=$true" | Set-WMIInstance -Arguments @{IndexingEnabled=$false} | Out-Null

Write-Host '[+] Disable automatically restart on failure'
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name 'AutoReboot' -Value '0' -PropertyType 'DWord' -Force | Out-Null

if (('SQL1' -eq "$env:COMPUTERNAME") -or ('SQL2' -eq "$env:COMPUTERNAME")) {
    Write-Host '[+] Enable active crash dump files'
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name 'CrashDumpEnabled' -Value '1' -PropertyType 'DWord' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name 'FilterPages' -Value '1' -PropertyType 'DWord' -Force | Out-Null
} else {
    Write-Host '[+] Disable crash dump files'
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name 'CrashDumpEnabled' -Value '0' -PropertyType 'DWord' -Force | Out-Null
}

Write-Host '[+] Do not write last access time'
& fsutil behavior set disablelastaccess 1 2>&1 | ForEach-Object {
    Write-Host "$_"
}
if ($LASTEXITCODE -ne 0) {
    throw "fsutil failed with exit code $LASTEXITCODE"
}

Write-Host '[+] Allow response to Ping'
New-NetFirewallRule -DisplayName 'ICMP Allow incoming V4 echo request' `
                    -Protocol ICMPv4 `
                    -IcmpType 8 `
                    -Direction Inbound `
                    -Action Allow `
                    -Profile Any | Out-Null

if ('CLIENT' -eq "$env:COMPUTERNAME") {
    Write-Host '[+] Enable UAC'
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableLUA' -Value '1' -PropertyType 'DWord' -Force | Out-Null
}

Write-Host '[+] Share c:\temp folder'
New-SmbShare -Name 'temp' -Path 'C:\temp' -ChangeAccess 'Everyone' | Out-Null

Write-Host '[+] Updating NuGet provider to a version higher than 2.8.5.201.'
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null

Write-Host '[+] Specify the installation policy'
Set-PSRepository -InstallationPolicy Trusted -Name PSGallery

Write-Host '[+] Installing PowerShellGet'
Install-Module -Name PowerShellGet -Force -SkipPublisherCheck -Scope AllUsers

Write-Host '[+] Installing / update PowerShell Pester module'
Install-Module -Name Pester -Force -SkipPublisherCheck -Scope AllUsers

Write-Host '[+] Installing / update PowerShell SQLServer module'
Install-Module -Name SqlServer -Force -AllowClobber -Scope Allusers

Write-Host '[+] Installing PowerShell WinGet'
Install-Module -Name Microsoft.WinGet.Client -Force -Scope AllUsers

Write-Host '[+] Show menu in Explorer'
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'AlwaysShowMenus' -Value '1' -PropertyType 'DWord' -Force | Out-Null

Write-Host '[+] Show file extensions in Explorer'
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Value '0' -PropertyType 'DWord' -Force | Out-Null

Write-Host '[+] Show hidden files in Explorer'
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Hidden' -Value '1' -PropertyType 'DWord' -Force | Out-Null

Write-Host '[+] Disable Hide protected operating system files in Explorer'
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowSuperHidden' -Value '1' -PropertyType 'DWord' -Force | Out-Null

Write-Host '[+] Enable Launch folder windows in a separate process in Explorer'
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'SeparateProcess' -Value '1' -PropertyType 'DWord' -Force | Out-Null

Write-Host '[+] Small icons in taskbar'
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarSmallIcons' -Value '1' -PropertyType 'DWord' -Force | Out-Null
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarGlomLevel' -Value '2' -PropertyType 'DWord' -Force | Out-Null

Write-Host '[+] Enable Always show all icons and notifications on the taskbar'
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' -Name 'EnableAutoTray' -Value '0' -PropertyType 'DWord' -Force | Out-Null

Write-Host '[+] Align taskbar on the left side'
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarAl' -Type 'DWord' -Value 0 -Force | Out-Null

Write-Host '[+] Show all folders'
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'NavPaneShowAllFolders' -Value '1' -PropertyType 'DWord' -Force | Out-Null

Write-Host '[+] Do not hide empty drives with no media'
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideDrivesWithNoMedia' -Value '0' -PropertyType 'DWord' -Force | Out-Null

Write-Host '[+] Do not use the sharing wizard'
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'SharingWizardOn' -Value '0' -PropertyType 'DWord' -Force | Out-Null

Write-Host '[+] Do not hide folder merge conflicts'
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideMergeConflicts' -Value '0' -PropertyType 'DWord' -Force | Out-Null

Write-Host '[+] Disable checkboxes in explorer'
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'AutoCheckSelect' -Value '0' -PropertyType 'DWord' -Force | Out-Null

Write-Host '[+] Enable status-bar in Explorer'
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Internet Explorer\Main' -Name 'StatusBarOther' -Value '1' -PropertyType 'DWord' -Force | Out-Null

Write-Host '[+] Disabling Screensaver'
New-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'ScreenSaveActive' -Value '0' -PropertyType 'DWord' -Force | Out-Null

Write-Host '[+] Add permanent environment variables to disable telemetry'
[System.Environment]::SetEnvironmentVariable('DOTNET_CLI_TELEMETRY_OPTOUT','1', 'Machine')
[System.Environment]::SetEnvironmentVariable('DOTNET_EnableDiagnostics','0', 'Machine')
[System.Environment]::SetEnvironmentVariable('DOTNET_TELEMETRY_OPTOUT','1', 'Machine')
[System.Environment]::SetEnvironmentVariable('POWERSHELL_CLI_TELEMETRY_OPTOUT','1', 'Machine')
[System.Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT','1', 'Machine')
[System.Environment]::SetEnvironmentVariable('POWERSHELL_UPDATECHECK','Off', 'Machine')
[System.Environment]::SetEnvironmentVariable('POWERSHELL_UPDATECHECK_OPTOUT','1', 'Machine')

$TargetScript = 'C:\OEM\user-profile.ps1'
if (Test-Path "$TargetScript") {
    $SourceFilePath = 'powershell.exe'
    $ShortcutPath = 'C:\Users\Public\Desktop\Run me once.lnk'
    $WScriptObj = New-Object -ComObject ('WScript.Shell')
    $shortcut = $WscriptObj.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $SourceFilePath
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy bypass -File $TargetScript"
    $shortcut.Save()
}

if (Test-Winget) {
    Write-Host '[+] Update winget sources'
    & winget source update 2>&1 | ForEach-Object {
        $line = "$_"
        if ($line -match '^[\x21-\x7E]') {
            Write-Host $line
        }
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "[!] winget source update completed with exit code $LASTEXITCODE"
    }

    Write-Host '[+] Upgrade all base apps'
    & winget upgrade --all --disable-interactivity --accept-package-agreements --accept-source-agreements 2>&1 | ForEach-Object {
        $line = "$_"
        if ($line -match '^[\x21-\x7E]') {
            Write-Host $line
        }
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "[!] winget source update completed with exit code $LASTEXITCODE"
    }
}
