#Requires -Version 5.1
#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
if ($env:DEBUG -eq 'True') { Set-PSDebug -Trace 1 }

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$DebugPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

trap {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

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

# enable TLS 1.1 and 1.2.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol `
    -bor [Net.SecurityProtocolType]::Tls11 `
    -bor [Net.SecurityProtocolType]::Tls12

$LogFilePath = 'c:\OEM\configure.log'

Start-Transcript -Path $LogFilePath -Append

if (-not (Test-Path 'c:\temp')) {
    New-Item -ItemType Directory -Path 'c:\temp' | Out-Null
}

Set-ExecutionPolicy -ExecutionPolicy Unrestricted

$FilesToRun = @( Get-ChildItem -Path "C:\OEM\*.ps1" -Exclude configure.ps1,env.ps1,user-profile.ps1 -ErrorAction SilentlyContinue )
$Stopwatch = New-Object System.Diagnostics.Stopwatch

Foreach($f in @( $FilesToRun )) {
    try {
        $Stopwatch.Start()
        Write-Host "[+] Starting customization with ${f}"
        & "${f}"
        $Stopwatch.Stop()
        Write-Host "[+] Done of ${f} in $($stopwatch.Elapsed.TotalSeconds) seconds"
    } finally {
        $Stopwatch.Reset()
    }
}

Write-Host '[+] Reboot VM'
Stop-Transcript

Restart-Computer -Force
