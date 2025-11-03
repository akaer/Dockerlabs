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

if ('CLIENT' -eq "$env:COMPUTERNAME") {

    Write-Host '[+] Install additional client packages'
    & winget install --disable-interactivity --accept-package-agreements --accept-source-agreements --silent `
        dnSpyEx.dnSpy `
        Microsoft.VisualStudioCode `
        Microsoft.SQLServerManagementStudio `
        Flameshot.Flameshot `
        Mozilla.Firefox.ESR `
        WinMerge.WinMerge `
        Softerra.LDAPBrowser `
        2>&1 | ForEach-Object {
            $line = "$_"
            if ($line -match '^[\x21-\x7E]') {
                 Write-Host $line
            }
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "[!] winget install completed with exit code $LASTEXITCODE"
    }

    #code --install-extension ms-mssql.mssql
    #code --install-extension ms-vscode.PowerShell
}

if ('WEB' -ne "$env:COMPUTERNAME") {
    exit 0
}

Write-Host '[+] Install IIS'
Import-Module ServerManager
Install-WindowsFeature -Name `
    Web-WebServer `
    ,Web-ASP `
    ,Web-Asp-Net45 `
    ,Web-Basic-Auth `
    ,Web-Default-Doc `
    ,Web-Dyn-Compression `
    ,Web-ISAPI-Ext `
    ,Web-ISAPI-Filter `
    ,Web-Net-Ext45 `
    ,Web-Stat-Compression `
    ,Web-Static-Content `
    ,Web-WebSockets `
    ,Web-Windows-Auth `
    -IncludeManagementTools

Write-Host '[+] Install DotNet Hosting bundle for IIS'
& winget install --disable-interactivity --accept-package-agreements --accept-source-agreements --silent `
    Microsoft.DotNet.HostingBundle.8 2>&1 | ForEach-Object {
    $line = "$_"
    if ($line -match '^[\x21-\x7E]') {
         Write-Host $line
    }
}
if ($LASTEXITCODE -ne 0) {
    Write-Warning "[!] winget install completed with exit code $LASTEXITCODE"
}
