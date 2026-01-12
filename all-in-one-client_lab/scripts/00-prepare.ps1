#Requires -Version 5.1
#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
if ($env:DEBUG -eq 'True') { Set-PSDebug -Trace 1 }

$ErrorActionPreference = 'Continue'
$InformationPreference = 'Continue'
$DebugPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$DoneFile = [IO.Path]::ChangeExtension($PSCommandPath, '.done')
if (Test-Path $DoneFile) {
    Write-Host "[!] File $PSCommandPath was already processed. Skip current run."
    exit 
}

# Load environment configuration
$EnvFile = Join-Path $PSScriptRoot 'env.ps1'
if (Test-Path $EnvFile) {
    . $EnvFile
}

Write-Host '***********************************************************'
Write-Host '*     WARNING, container will reboot in some seconds!     *'
Write-Host '***********************************************************'

# Continue auto installation after container reboot
$KeyName = 'AutoInstall'
$Command = 'cmd /C (powershell -ExecutionPolicy Unrestricted -noProfile -File "c:\OEM\configure.ps1")'
New-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name $KeyName -Value $Command -PropertyType ExpandString | Out-Null

Write-Host "[+] Setting computer name: ${CLIENT_COMPUTERNAME}"
Rename-Computer -NewName ${CLIENT_COMPUTERNAME} -Force

# Write marker
'AlreadyProcessed' | Out-File "$DoneFile"

& shutdown /r /t 30 /c 'Autoinstallation' /d p:2:4
