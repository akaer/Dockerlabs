#Requires -Version 5.1
#Requires -RunAsAdministrator

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

Write-Host '[+] Install IIS'
Enable-WindowsOptionalFeature -All -Online -NoRestart -FeatureName `
  IIS-WebServerRole `
 ,IIS-WebServer `
 ,IIS-WebServerManagementTools `
 ,IIS-WindowsAuthentication `
 ,IIS-HttpCompressionStatic `
 ,IIS-BasicAuthentication `
 ,IIS-ASP `
 ,IIS-ASPNET45 `
 ,IIS-ISAPIExtensions `
 ,IIS-ISAPIFilter `
 ,IIS-WebSockets `
 ,IIS-DefaultDocument `
 ,IIS-StaticContent `
 ,IIS-HttpCompressionDynamic `
 ,IIS-ManagementScriptingTools

Write-Host '[+] Install DotNet Hosting bundle for IIS'
& winget install --disable-interactivity --accept-package-agreements --accept-source-agreements --silent `
    Microsoft.DotNet.HostingBundle.8 Microsoft.DotNet.HostingBundle.10 2>&1 | ForEach-Object {
    $line = "$_"
    if ($line -match '^[\x21-\x7E]') {
         Write-Host $line
    }
}
if ($LASTEXITCODE -ne 0) {
    Write-Warning "[!] winget install completed with exit code $LASTEXITCODE"
}

# Write marker
'AlreadyProcessed' | Out-File "$DoneFile"
