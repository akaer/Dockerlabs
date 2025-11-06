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

$clusterName = "$FILE_CLUSTER_NAME"

$LogFilePath = 'c:\OEM\configure.log'

Start-Transcript -Path $LogFilePath -Append

Write-Host '[+] Start cluster test script'

Write-Host "[+] Waiting for the $clusterName Failover Cluster to be available..."
while ( -Not (Get-Cluster -Name $clusterName -ErrorAction SilentlyContinue) ) {
    Write-Host '[-] Wait some seconds for cluster'
    Start-Sleep -Second 30
}

while (Get-ClusterResource -Cluster $clusterName | Where-Object State -ne Online) {
    Write-Host '[-] Wait some seconds for cluster resources top get online'
    Start-Sleep -Second 30
}

while (Get-ClusterNode -Cluster $clusterName | Where-Object State -ne Up) {
    Write-Host '[-] Wait some seconds for cluster resources top get online'
    Start-Sleep -Second 30
}

Write-Host '[+] Cluster overview'
Get-ClusterResource -Cluster $clusterName
Get-ClusterNode -Cluster $clusterName

Write-Host '[+] Testing/Validating the cluster ...'
$reportPath = "c:\OEM\sql-server-cluster-validation-report-${env:COMPUTERNAME}"
Remove-Item -ErrorAction SilentlyContinue -Force "$reportPath.*" | Out-Null
Test-Cluster `
    -Cluster $clusterName `
    -ReportName $reportPath

# Continue with SQL Server setup after reboot
$KeyName = 'SqlServerInstall'
$Command = 'powershell -ExecutionPolicy Unrestricted -NoProfile -File "c:\OEM\sqlserver-install.ps1"'
New-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name $KeyName -Value $Command -PropertyType ExpandString | Out-Null

Stop-Transcript

Restart-Computer -Force

