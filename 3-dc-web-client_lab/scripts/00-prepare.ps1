#Requires -Version 5.1
#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
if ($env:DEBUG -eq 'True') { Set-PSDebug -Trace 1 }

$ErrorActionPreference = 'Continue'
$InformationPreference = 'Continue'
$DebugPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

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
$Command = 'cmd /C if exist "C:\OEM\install.bat" start "Install" "cmd /C C:\OEM\install.bat"'
New-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name $KeyName -Value $Command -PropertyType ExpandString | Out-Null

# Set reboot marker
Write-Host '[+] Finding network adapters and resolving VM name by MAC address'
$physicalAdapters = Get-NetAdapter -Physical

# Define network configurations
$networkConfigs = @(
    @{
        Name         = 'DC1'
        MAC          = $DC1_NETWORK_MAC
        ComputerName = $DC1_COMPUTERNAME
    },
    @{
        Name         = 'DC2'
        MAC          = $DC2_NETWORK_MAC
        ComputerName = $DC2_COMPUTERNAME
    },
    @{
        Name         = 'DC3'
        MAC          = $DC3_NETWORK_MAC
        ComputerName = $DC3_COMPUTERNAME
    },
    @{
        Name         = 'Web'
        MAC          = $WEB_NETWORK_MAC
        ComputerName = $WEB_COMPUTERNAME
    },
    @{
        Name         = 'Client'
        MAC          = $CLIENT_NETWORK_MAC
        ComputerName = $CLIENT_COMPUTERNAME
    }
)

foreach ($config in $networkConfigs) {
    $adapter = $physicalAdapters | Where-Object { $_.MacAddress -eq $config.MAC }

    if ($adapter) {
        Write-Host "[+] This VM is $($config.ComputerName)"

        Write-Host "[+] $($config.ComputerName): Setting computer name"
        Rename-Computer -NewName $config.ComputerName -Force

        Write-Host '[+] VM is going into reboot'
        'Please reboot container' | Out-File "\\host.lan\Data\state\$($config.ComputerName)_reboot.txt"
    }
}

# Self destroy
Remove-Item $PSCommandPath -Force | Out-Null

Read-Host -Prompt 'Waiting for reboot...'
