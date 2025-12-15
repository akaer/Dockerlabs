#Requires -Version 5.1
#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
if ($env:DEBUG -eq 'True') { Set-PSDebug -Trace 1 }

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$DebugPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$EnvFile = Join-Path $PSScriptRoot 'env.ps1'
if (Test-Path $EnvFile) {
    . $EnvFile
}

function ConvertTo-PrefixLength {
    param([string]$SubnetMask)

    $octets = $SubnetMask.Split('.')
    $binaryString = ($octets | ForEach-Object { [Convert]::ToString([int]$_, 2).PadLeft(8, '0') }) -join ''
    return ($binaryString.ToCharArray() | Where-Object { $_ -eq '1' }).Count
}

function Set-NetworkAdapterConfiguration {
    param(
        [Parameter(Mandatory)]
        [Microsoft.Management.Infrastructure.CimInstance]$Adapter,

        [Parameter(Mandatory)]
        [string]$IPAddress,

        [Parameter(Mandatory)]
        [string]$SubnetMask,

        [Parameter(Mandatory)]
        [string[]]$DNSServers,

        [Parameter(Mandatory)]
        [string]$ComputerName,

        [string]$AdapterName = 'Domain'
    )

    Write-Host "[+] ${ComputerName}: Renaming adapter to '$AdapterName'"
    $Adapter | Rename-NetAdapter -NewName $AdapterName

    Write-Host "[+] ${ComputerName}: Disable IPv6"
    Disable-NetAdapterBinding -Name "$AdapterName" -ComponentID ms_tcpip6

    Set-NetIPInterface -InterfaceAlias "$AdapterName" -AddressFamily IPv4 -DadTransmits 0

    Get-NetIPAddress -InterfaceAlias $AdapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false
    New-NetIPAddress -InterfaceAlias $AdapterName -IPAddress $IPAddress -PrefixLength (ConvertTo-PrefixLength $SubnetMask) -AddressFamily IPv4

    Start-Sleep -Seconds 5

    Write-Host "[+] ${ComputerName}: Configuring DNS servers"
    $Adapter | Set-DnsClientServerAddress -ServerAddresses $DNSServers

}

$RebootFile = "\\host.lan\Data\state\${Env:ComputerName}_reboot.txt"
Write-Host '[+] Remove reboot file'
if (Test-Path "$RebootFile") {
    Remove-Item "$RebootFile" -Force | Out-Null
}

Write-Host '[+] Before network configuration'
Get-NetIPConfiguration -Detailed

Write-Host '[+] Finding network adapters'
$physicalAdapters = Get-NetAdapter -Physical

$networkConfigs = @(
    @{
        Name         = 'DC1'
        MAC          = $DC1_NETWORK_MAC
        IP           = $DC1_NETWORK_IP
        Netmask      = $DC1_NETWORK_NETMASK
        DNS          = $DC1_NETWORK_DNS
        ComputerName = $DC1_COMPUTERNAME
    },
    @{
        Name         = 'DC2'
        MAC          = $DC2_NETWORK_MAC
        IP           = $DC2_NETWORK_IP
        Netmask      = $DC2_NETWORK_NETMASK
        DNS          = $DC2_NETWORK_DNS
        ComputerName = $DC2_COMPUTERNAME
    },
    @{
        Name         = 'DC3'
        MAC          = $DC3_NETWORK_MAC
        IP           = $DC3_NETWORK_IP
        Netmask      = $DC3_NETWORK_NETMASK
        DNS          = $DC3_NETWORK_DNS
        ComputerName = $DC3_COMPUTERNAME
    },
    @{
        Name         = 'Web'
        MAC          = $WEB_NETWORK_MAC
        IP           = $WEB_NETWORK_IP
        Netmask      = $WEB_NETWORK_NETMASK
        DNS          = $WEB_NETWORK_DNS
        ComputerName = $WEB_COMPUTERNAME
    },
    @{
        Name         = 'Client'
        MAC          = $CLIENT_NETWORK_MAC
        IP           = $CLIENT_NETWORK_IP
        Netmask      = $CLIENT_NETWORK_NETMASK
        DNS          = $CLIENT_NETWORK_DNS
        ComputerName = $CLIENT_COMPUTERNAME
    }
)

# Configure each network adapter
$configuredMACs = foreach ($config in $networkConfigs) {
    $adapter = $physicalAdapters | Where-Object { $_.MacAddress -eq $config.MAC }

    if ($adapter) {
        Set-NetworkAdapterConfiguration `
            -Adapter $adapter `
            -IPAddress $config.IP `
            -SubnetMask $config.Netmask `
            -DNSServers $config.DNS `
            -ComputerName $config.ComputerName

        $config.MAC
    }
}

# Disable DNS registration for non-domain adapters
Write-Host '[+] Disabling DNS registration for non-domain adapters'
$physicalAdapters |
    Where-Object { $_.MacAddress -notin $configuredMACs } |
    Set-DNSClient -RegisterThisConnectionsAddress $false

Write-Host '[+] Rename non-domain adapters'
$physicalAdapters |
    Where-Object { $_.MacAddress -notin $configuredMACs } |
    Rename-NetAdapter -NewName 'Docker'

Write-Host '[+] Disable IPv6 for non-domain adapter'
Disable-NetAdapterBinding -Name 'Docker' -ComponentID ms_tcpip6

Set-NetIPInterface -InterfaceAlias 'Docker' -InterfaceMetric 1000
Set-NetIPInterface -InterfaceAlias 'Domain' -InterfaceMetric 10

Write-Host '[+] After network configuration'
Get-NetIPConfiguration -Detailed
