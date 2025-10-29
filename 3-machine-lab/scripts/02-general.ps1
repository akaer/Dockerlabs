#Requires -Version 5.1
#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
if ($env:DEBUG -eq 'True') { Set-PSDebug -Trace 1 }

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$DebugPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$CustomTimeZone = 'W. Europe Standard Time'

function Register-BGInfoStartup {

        $bgInfo = Get-ChildItem -Path "$env:LocalAppData" -Filter 'BGInfo64.exe' -Recurse -Attributes !ReparsePoint

        if (-not ($bgInfo)) {
            Write-Host '[!] BGinfo not found!'

            return
        }

        $bgInfo = $bgInfo.FullName

        Copy-Item $bgInfo 'c:\windows\'
        $exePath = 'c:\windows\BGInfo64.exe'

        #Register Startup command for All User
        $startupPath =  Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup\BGInfo.lnk'
        $shell = New-Object -COM WScript.Shell
        $shortcut = $shell.CreateShortcut($startupPath)
        $shortcut.TargetPath = $exePath
        $shortcut.Arguments = 'c:\OEM\boxdefault.bgi /timer:0 /silent /nolicprompt'
        $shortcut.Save()

        Write-Host '[+] BGInfo registered for autostart'
}

Write-Host '[+] Configure defender'
Set-MpPreference -DisableRealtimeMonitoring $true
Set-MpPreference -DisableBehaviorMonitoring $true

Write-Host '[+] Set time zone'
Set-Timezone -Name "$CustomTimeZone"

Write-Host '[+] Configure Microsoft Edge browser'
$edgePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
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

Write-Host '[+] Eject cd from drive'
$sh = New-Object -ComObject 'Shell.Application'
$sh.Namespace(17).Items() | Where-Object { $_.Type -eq 'CD Drive' } | foreach { $_.InvokeVerb('Eject') }

Write-Host '[+] Enable file and printer sharing'
Set-NetFirewallRule -DisplayGroup 'File and Printer Sharing' -Enabled True -Profile Any

Write-Host '[+] Disable use simple file sharing'
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'ForceGuest' -Value '0' -PropertyType 'DWord' -Force | Out-Null

Write-Host '[+] Disable indexing on all drives'
Get-WmiObject Win32_Volume -Filter "IndexingEnabled=$true" | Set-WMIInstance -Arguments @{IndexingEnabled=$false}

Write-Host '[+] Disable automatically restart on failure'
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name 'AutoReboot' -Value '0' -PropertyType 'DWord' -Force | Out-Null

Write-Host '[+] Disable crash dump files'
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name 'CrashDumpEnabled' -Value '0' -PropertyType 'DWord' -Force | Out-Null

Write-Host '[+] Do not write last access time'
& fsutil behavior set disablelastaccess 1
if ($LASTEXITCODE -ne 0) {
    throw "fsutil failed with exit code $LASTEXITCODE"
}

Write-Host '[+] Allow response to Ping'
New-NetFirewallRule -DisplayName 'ICMP Allow incoming V4 echo request' `
                    -Protocol ICMPv4 `
                    -IcmpType 8 `
                    -Direction Inbound `
                    -Action Allow `
                    -Profile Any

Write-Host '[+] Enable UAC'
New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableLUA' -Value '1' -PropertyType 'DWord' -Force | Out-Null

Write-Host '[+] Share c:\temp folder'
New-SmbShare -Name 'temp' -Path 'C:\temp' -ChangeAccess 'Everyone'

Write-Host '[+] Updating NuGet provider to a version higher than 2.8.5.201.'
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null

Write-Host '[+] Specify the installation policy'
Set-PSRepository -InstallationPolicy Trusted -Name PSGallery

Write-Host '[+] Install PowerShellGet'
Install-Module -Name PowerShellGet -Force -Scope AllUsers

Write-Host '[+] Installing / update PowerShell Pester module'
Install-Module -Name Pester -Force -SkipPublisherCheck -Scope AllUsers

Write-Host '[+] Installing / update PowerShell SQLServer module'
Install-Module -Name SqlServer -Force -AllowClobber -Scope Allusers

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

Write-Host '[+] Small icons in taskbar'
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarGlomLevel' -Value '2' -PropertyType 'DWord' -Force | Out-Null

Write-Host '[+] Enable Always show all icons and notifications on the taskbar'
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' -Name 'EnableAutoTray' -Value '0' -PropertyType 'DWord' -Force | Out-Null

Write-Host '[+] Align taskbar on the left side'
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarAl' -Type 'DWord' -Value 0

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

Write-Host '[+] Upgrade all installed packages'
& winget upgrade --all --disable-interactivity --accept-package-agreements --accept-source-agreements --silent
if ($LASTEXITCODE -ne 0) {
        throw "winget failed with exit code $LASTEXITCODE"
}

Write-Host '[+] Install global applications'
& winget install --accept-package-agreements --accept-source-agreements --silent `
Microsoft.Edit `
7zip.7zip `
Microsoft.DotNet.SDK.8 `
Microsoft.PowerShell `
Microsoft.Sysinternals.Suite `
Notepad++.Notepad++
if ($LASTEXITCODE -ne 0) {
        throw "winget failed with exit code $LASTEXITCODE"
}

Register-BGInfoStartup

$TargetScript = 'C:\OEM\addon-software.ps1'
if (Test-Path "$TargetScript") {
    $SourceFilePath = 'powershell.exe'
    $ShortcutPath = 'C:\Users\Public\Desktop\Install more apps.lnk'
    $WScriptObj = New-Object -ComObject ('WScript.Shell')
    $shortcut = $WscriptObj.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $SourceFilePath
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy bypass -File $TargetScript"
    $shortcut.Save()
}

