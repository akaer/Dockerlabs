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
while (!(Get-Cluster -Name $clusterName -ErrorAction SilentlyContinue)) {
    Start-Sleep -Second 15
}

Write-Host '[+] Testing the cluster...'
$reportPath = "C:\OEM\sql-server-cluster-validation-report-${env:COMPUTERNAME}"
Remove-Item -ErrorAction SilentlyContinue -Force "$reportPath.*" | Out-Null
Test-Cluster `
    -Cluster $clusterName `
    -ReportName $reportPath
Start-Sleep -Seconds 30

Stop-Transcript

