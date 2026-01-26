
Set-StrictMode -Version Latest
if ($env:DEBUG -eq 'True') { Set-PSDebug -Trace 1 }

$ErrorActionPreference = 'Stop'
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

Write-Host '[+] Install root ca certificate'
Import-Certificate `
    -FilePath "c:\OEM\certs\${DOMAIN_NAME}.ca.der" `
    -CertStoreLocation Cert:\LocalMachine\Root | Out-Null

Write-Host '[+] Install machine certificate'
Import-PfxCertificate `
    -FilePath "c:\OEM\certs\${env:COMPUTERNAME}.${DOMAIN_NAME}.pfx" `
    -CertStoreLocation Cert:\LocalMachine\My `
    -Password $null `
    -Exportable | Out-Null

Write-Host '[+] Register HTTPS certificate'
$cert = Get-ChildItem Cert:\LocalMachine\My -DnsName "${env:COMPUTERNAME}.${DOMAIN_NAME}"
New-WebBinding -Name 'Default Web Site' -IP '*' -Port 443 -Protocol https -Verbose
$binding = Get-WebBinding -Name 'Default Web Site' -Protocol https
$binding.AddSslCertificate($cert.Thumbprint, 'my')

& netsh advfirewall firewall add rule name='Tcp port 1880 for Jobserver' protocol=TCP localport=1880 dir=in action=allow
if ($LASTEXITCODE -ne 0) {
    throw "netsh failed with exit code $LASTEXITCODE"
}

& netsh http add urlacl url='https://*:1880/' user=Everyone
if ($LASTEXITCODE -ne 0) {
    throw "netsh failed with exit code $LASTEXITCODE"
}

$cert = Get-ChildItem Cert:\LocalMachine\My -DnsName "${env:COMPUTERNAME}.${DOMAIN_NAME}"
$Thumbprint=$cert.Thumbprint
& netsh http add sslcert ipport=0.0.0.0:1880 certhash=$Thumbprint
if ($LASTEXITCODE -ne 0) {
    throw "netsh failed with exit code $LASTEXITCODE"
}

# Write marker
'AlreadyProcessed' | Out-File "$DoneFile"
