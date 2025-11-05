#Requires -Version 5.1
#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
if ($env:DEBUG -eq 'True') { Set-PSDebug -Trace 1 }

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$DebugPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

trap {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    Write-Host ''
    Write-Host "[$ts] ERROR: $_"
    Write-Host ''

    # Stack trace
    if ($_.ScriptStackTrace) {
        Write-Host "[$ts] --- Stack Trace ---"
        ($_.ScriptStackTrace -split '\r?\n') | Where-Object { $_.Trim() } | ForEach-Object {
            Write-Host "[$ts] $_"
        }
        Write-Host ''
    }

    # Main exception
    Write-Host "[$ts] Exception Type: $($_.Exception.GetType().FullName)"
    Write-Host "[$ts] Exception Message: $($_.Exception.Message)"

    # Walk inner exceptions
    $inner = $_.Exception.InnerException
    $level = 1
    while ($inner) {
        Write-Host ''
        Write-Host "[$ts] Inner Exception [$level]:"
        Write-Host "[$ts]   Type: $($inner.GetType().FullName)"
        Write-Host "[$ts]   Message: $($inner.Message)"

        $inner = $inner.InnerException
        $level++
    }

    Write-Host ''
    Exit 1
}

# Load environment configuration
$EnvFile = Join-Path $PSScriptRoot 'env.ps1'
if (Test-Path $EnvFile) {
    . $EnvFile
}

function Convert-DHCPToStatic {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InterfaceAlias
    )

    # Get current network configuration
    $netConfig = Get-NetAdapter -Name $InterfaceAlias | Get-NetIPConfiguration -Detailed

    if ($null -eq $netConfig) {
        throw "Network adapter '$InterfaceAlias' not found"
    }

    # Check if DHCP is currently enabled
    if ($netConfig.NetIPv4Interface.DHCP -ne 'Enabled') {
        Write-Warning "[!] Interface '$InterfaceAlias' is already using static IP configuration"
        return
    }

    # Extract current settings
    $ipAddress = $netConfig.IPv4Address.IPAddress
    $prefixLength = $netConfig.IPv4Address.PrefixLength
    $gateway = $netConfig.IPv4DefaultGateway.NextHop
    $dnsServers = $netConfig.DNSServer.ServerAddresses
    $interfaceIndex = $netConfig.InterfaceIndex

    Write-Host '[+] Current Configuration:'
    Write-Host "  IP Address    : $ipAddress/$prefixLength"
    Write-Host "  Gateway       : $gateway"
    Write-Host "  DNS Servers   : $($dnsServers -join ', ')"

    # Remove existing IP configuration
    Write-Host '[+] Removing DHCP configuration...'
    Remove-NetIPAddress -InterfaceIndex $interfaceIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    Remove-NetRoute -InterfaceIndex $interfaceIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

    Write-Host '[+] Disable DHCP'
    Set-NetIPInterface -InterfaceIndex $interfaceIndex -Dhcp Disable | Out-Null

    # Set static IP address
    Write-Host '[+] Setting static IP address...'
    New-NetIPAddress -InterfaceIndex $interfaceIndex `
                   -IPAddress $ipAddress `
                   -PrefixLength $prefixLength `
                   -DefaultGateway $gateway `
                   -AddressFamily IPv4 | Out-Null

    # Set DNS servers
    Write-Host '[+] Setting DNS servers...'
    Set-DnsClientServerAddress -InterfaceIndex $interfaceIndex `
                              -ServerAddresses $dnsServers | Out-Null

    Write-Host '[+] Configuration successfully converted to static IP!'

    # Display new configuration
    Write-Host '[+] New Configuration:'
    Get-NetIPConfiguration -InterfaceIndex $interfaceIndex | Format-List

    Start-Sleep -Seconds 30
}

$clusterName = "$FILE_CLUSTER_NAME"
$clusterIpAddress = "$FILE_CLUSTER_IP"

$LogFilePath = 'c:\OEM\configure.log'

Start-Transcript -Path $LogFilePath -Append

Write-Host '[+] Start cluster configuration script'

if (('SQL1' -eq "$env:COMPUTERNAME") -or ('SQL2' -eq "$env:COMPUTERNAME")) {

    Write-Host '[+] Convert dhcp to static ip configuration'
    Convert-DHCPToStatic 'Docker'

    Write-Host '[+] Setting the Domain network interface default gateway...'
    if (Get-NetRoute -InterfaceAlias Domain -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue) {
        Remove-NetRoute `
            -InterfaceAlias Domain `
            -DestinationPrefix '0.0.0.0/0' `
            -Confirm:$false | Out-Null
    }

    New-NetRoute `
        -InterfaceAlias Domain `
        -DestinationPrefix '0.0.0.0/0' `
        -NextHop ($clusterIpAddress -replace '\.\d+$','.1') `
        -RouteMetric 271 | Out-Null
}

if ('SQL1' -eq "$env:COMPUTERNAME") {

    Write-Host "[+] Creating the $clusterName Failover Cluster..."
    $dockerNetAdapter = Get-NetAdapter Docker
    $clusterIgnoreNetwork = ($dockerNetAdapter | Get-NetIPConfiguration).IPv4Address `
        | Select-Object -First 1 `
        | ForEach-Object {
            "$($_.IPAddress -replace '\.\d+$','.0')/$($_.PrefixLength)"
        }
    $clusterIgnoreDockerNetwork = ($dockerNetAdapter | Get-NetIPConfiguration).IPv4Address `
        | Select-Object -First 1 `
        | ForEach-Object {
            "$($_.IPAddress -replace '\.\d+$','.0')"
        }

    Write-Host "[+] Network to ignore during Cluster configuration: $clusterIgnoreNetwork"

    New-Cluster `
        -Name $clusterName `
        -Node $env:COMPUTERNAME `
        -StaticAddress $clusterIpAddress `
        -IgnoreNetwork $clusterIgnoreNetwork `
        -NoStorage

    # The IgnoreNetwork parameter seems not work; therefore we disable this cluster network
    # See: https://serverfault.com/questions/554192/change-network-used-by-cluster-traffic-types-with-powershell
    Write-Host '[+] Deactive docker network for cluster communication'
    (Get-ClusterNetwork | Where-Object { $_.Address -eq "$clusterIgnoreDockerNetwork" }).Role = 0

    Write-Host '[+] Set better name and metric for doamin cluster network'
    (Get-ClusterNetwork | Where-Object { $_.Address -ne "$clusterIgnoreDockerNetwork" }).Name = 'Domain cluster network'
    (Get-ClusterNetwork | Where-Object { $_.Address -ne "$clusterIgnoreDockerNetwork" }).Metric = 900
    Get-ClusterNetwork | Format-List -Property *

    Write-Host "[+] Waiting for the $clusterName Failover Cluster to be available..."
    while (!(Get-Cluster -Name $clusterName -ErrorAction SilentlyContinue)) {
        Start-Sleep -Second 5
    }

    $clusterFileSharePath = "\\dc.${DOMAIN_NAME}\fc-storage-${clusterName}"
    Write-Host "[+] Setting the $clusterName Failover Cluster Quorum Share to $clusterFileSharePath..."
    Set-ClusterQuorum `
        -Cluster $clusterName `
        -NodeAndFileShareMajority $clusterFileSharePath | Out-Null

    'Cluster installation ready' | Out-File '\\host.lan\data\state\cluster_installation_ready.txt'
}

if ('SQL2' -eq "$env:COMPUTERNAME") {
    Write-Host '[+] Waiting for cluster installation to be ready'
    while ($true) {
        if (Test-Path -Path '\\host.lan\data\state\cluster_installation_ready.txt') {
            break
        }

        Start-Sleep -Seconds 30
    }

    Write-Host "[+] Adding the current node to the $clusterName Failover Cluster..."
    Add-ClusterNode `
        -Cluster $clusterName `
        -Name $env:COMPUTERNAME | Out-Null

    Start-Sleep -Seconds 30

    'Cluster ready' | Out-File '\\host.lan\data\state\cluster_ready.txt'
}

Write-Host '[+] Waiting for cluster to be available'
while ($true) {
    if (Test-Path -Path '\\host.lan\data\state\cluster_ready.txt') {
        break
    }

    Start-Sleep -Seconds 30
}

$KeyName = 'ClusterTest'
$Command = 'powershell -ExecutionPolicy Unrestricted -NoProfile -File "c:\OEM\cluster_test.ps1"'
New-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name $KeyName -Value $Command -PropertyType ExpandString | Out-Null

# Use Autologon as administrator
$winlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty -Path $winlogonPath -Name 'AutoAdminLogon' -Value '1' -Type String
Set-ItemProperty -Path $winlogonPath -Name 'DefaultUserName' -Value 'administrator' -Type String
Set-ItemProperty -Path $winlogonPath -Name 'DefaultPassword' -Value "$LOCAL_ADMIN_PASSWORD" -Type String

Stop-Transcript

Restart-Computer -Force

