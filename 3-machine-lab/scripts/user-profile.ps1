Set-StrictMode -Version Latest
if ( $env:DEBUG -eq 'True' ) { Set-PSDebug -Trace 1 }
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$DebugPreference = 'SilentlyContinue' # Valid values are 'SilentlyContinue' -> Don't show any debug messages; Continue -> Show debug messages.
$ProgressPreference = 'SilentlyContinue'

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

