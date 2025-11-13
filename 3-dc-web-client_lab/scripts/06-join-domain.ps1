#Requires -Version 5.1
#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
if ($env:DEBUG -eq 'True') { Set-PSDebug -Trace 1 }

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$DebugPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

# Load environment configuration
$EnvFile = Join-Path $PSScriptRoot 'env.ps1'
if (Test-Path $EnvFile) {
    . $EnvFile
}

if ("$env:COMPUTERNAME" -like 'dc*') {
    exit 0
}

$DOMAIN_NAME = $DOMAIN_NAME_1

Write-Host "[+] Waiting for domain to be available"
while ($true) {
    if (Test-Path -Path '\\host.lan\data\state\domain_ready.txt') {

        break

    }

    Start-Sleep -Seconds 30
}

Write-Host "[+] Join ${env:COMPUTERNAME} to ${DOMAIN_NAME}"
$PasswordSec = ConvertTo-SecureString "$LOCAL_ADMIN_PASSWORD" -AsPlainText -Force
$djuser = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ("${DOMAIN_NAME}\administrator", $PasswordSec)

# Retry domain join
$maxAttempts = 5
$delaySeconds = 30
$joined = $false

for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    try {
        Write-Host "[-]    Joining domain (attempt $attempt/$maxAttempts)..."

        Add-Computer -DomainName "$DOMAIN_NAME" -Credential $djuser -Force -ErrorAction Stop

        Write-Host '[+] Successfully joined domain'
        $joined = $true
        break
    }
    catch {
        Write-Host "[!] Attempt $attempt failed: $($_.Exception.Message)"

        if ($_.Exception.Message -match 'already a member') {
            Write-Host '[!] Already domain member'
            $joined = $true
            break
        }

        if ($attempt -lt $maxAttempts) {
            Write-Host "[-]    Retrying in $delaySeconds seconds..."
            Start-Sleep -Seconds $delaySeconds
        } else {
            throw "[!] Failed to join domain after $maxAttempts attempts: $_"
        }
    }
}

if (-not $joined) {
    Write-Error 'Domain join failed'
    exit 1
}

# After domain join, sleep 30 seconds to settle things a little bit
Start-Sleep -Seconds 30

Write-Host '[+] Allow domain users allow remote login'
$ErrorActionPreference = 'Continue'
$maxAttempts = 10
$attemptCount = 0
$success = $false

while (-not $success -and $attemptCount -lt $maxAttempts) {
    $attemptCount++
    $result = & net localgroup 'Remote Desktop Users' 'Domain Users' /add 2>&1
    if ($LASTEXITCODE -eq 0 -or $result -match 'already a member') {
        $success = $true
        Write-Host 'Successfully added Domain Users to Remote Desktop Users'
    } elseif ($result -match '1789') {
        Write-Host "Domain trust not ready, retrying... (Attempt $attemptCount/$maxAttempts)"
        Start-Sleep -Seconds 15
    } else {
        throw "Unexpected error: $result"
    }
}
$ErrorActionPreference = 'Stop'

Write-Host '[+] Deactivate auto logon'
$regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty -Path $regPath -Name 'AutoAdminLogon' -Value '0' -Type String
Remove-ItemProperty -Path $regPath -Name 'DefaultPassword' -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $regPath -Name 'AutoLogonCount' -ErrorAction SilentlyContinue
