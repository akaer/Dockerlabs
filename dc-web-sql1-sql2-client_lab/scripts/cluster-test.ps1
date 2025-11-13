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

    if (Test-Path 'c:\OEM\configure.log') {
        & notepad 'c:\OEM\configure.log'
    }
    Exit 1
}

# Load environment configuration
$EnvFile = Join-Path $PSScriptRoot 'env.ps1'
if (Test-Path $EnvFile) {
    . $EnvFile
}

$LogFilePath = 'c:\OEM\configure.log'

Start-Transcript -Path $LogFilePath -Append

if ( 'SQL1' -eq "$env:COMPUTERNAME" ) {
    do {
        $ping = Test-Connection -ComputerName SQL2 -count 1 -Quiet -ErrorAction SilentlyContinue
        Start-Sleep -Second 30
    } until ($ping)

    'Node SQL1 ready' | Out-File '\\host.lan\data\state\cluster_node_sql1.txt'
}

if ( 'SQL2' -eq "$env:COMPUTERNAME" ) {
    do {
        $ping = Test-Connection -ComputerName SQL1 -count 1 -Quiet -ErrorAction SilentlyContinue
        Start-Sleep -Second 30
    } until ($ping)

    'Node SQL2 ready' | Out-File '\\host.lan\data\state\cluster_node_sql2.txt'
}

Write-Host '[+] Wait for cluster nodes'
while ($true) {

    if ( (Test-Path -Path '\\host.lan\data\state\cluster_node_sql1.txt') -and (Test-Path -Path '\\host.lan\data\state\cluster_node_sql2.txt') ) {
        break
    }

    Start-Sleep -Second 30
}

Write-Host "[+] Waiting for the $FILE_CLUSTER_NAME Failover Cluster to be available..."
while ( -Not (Get-Cluster -Name $FILE_CLUSTER_NAME -ErrorAction SilentlyContinue) ) {
    Write-Host '[-] Wait some seconds for cluster'
    Start-Sleep -Second 30
}

while (Get-ClusterResource -Cluster $FILE_CLUSTER_NAME | Where-Object State -ne Online) {
    Write-Host '[-] Wait some seconds for cluster resources to get online'
    Start-Sleep -Second 30
}

while (Get-ClusterNode -Cluster $FILE_CLUSTER_NAME | Where-Object State -ne Up) {
    Write-Host '[-] Wait some seconds for cluster resources to get online'
    Start-Sleep -Second 30
}

Write-Host "[+] Cluster overview $FILE_CLUSTER_NAME"
Get-ClusterResource -Cluster $FILE_CLUSTER_NAME
Get-ClusterNode -Cluster $FILE_CLUSTER_NAME

Write-Host '[+] Testing/Validating the cluster ...'
$reportPath = "c:\OEM\sql-server-cluster-validation-report-${env:COMPUTERNAME}"
Remove-Item -ErrorAction SilentlyContinue -Force "$reportPath.*" | Out-Null
Test-Cluster `
    -Cluster $FILE_CLUSTER_NAME `
    -ReportName $reportPath

# Continue with SQL Server setup after reboot
$KeyName = 'SqlServerInstall'
$Command = 'powershell -ExecutionPolicy Unrestricted -NoProfile -File "c:\OEM\sqlserver-install.ps1"'
New-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name $KeyName -Value $Command -PropertyType ExpandString | Out-Null

Stop-Transcript

& shutdown /r /t 30 /c 'Autoinstallation' /d p:2:4
