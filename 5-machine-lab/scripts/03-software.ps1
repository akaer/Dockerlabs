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

function Register-BGInfoStartup {

        $bgInfo = Get-ChildItem -Path "$env:LocalAppData" -Filter 'BGInfo64.exe' -Recurse -Attributes !ReparsePoint

        if (-not ($bgInfo)) {
            Write-Host '[!] BGinfo not found!'

            return
        }

        $bgInfo = $bgInfo.FullName

        Copy-Item $bgInfo 'c:\windows\'
        $exePath = 'c:\windows\BGInfo64.exe'

        #Register Startup command for All User
        $startupPath =  Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup\BGInfo.lnk'
        $shell = New-Object -COM WScript.Shell
        $shortcut = $shell.CreateShortcut($startupPath)
        $shortcut.TargetPath = $exePath
        $shortcut.Arguments = 'c:\OEM\boxdefault.bgi /timer:0 /silent /nolicprompt'
        $shortcut.Save()

        Write-Host '[+] BGInfo registered for autostart'
}

Write-Host '[+] Install global applications'
& C:\Users\admn\AppData\Local\Microsoft\WindowsApps\winget.exe install --accept-package-agreements --accept-source-agreements --silent `
Microsoft.Edit `
7zip.7zip `
Microsoft.DotNet.SDK.8 `
Microsoft.PowerShell `
Microsoft.Sysinternals.Suite `
Notepad++.Notepad++ `
2>&1 | ForEach-Object {
    $line = "$_"
    if ($line -match '^[\x21-\x7E]') {
         Write-Host $line
    }
}
if ($LASTEXITCODE -ne 0) {
    Write-Warning "[!] winget install completed with exit code $LASTEXITCODE"
}

Register-BGInfoStartup

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

if (('SQL1' -eq "$env:COMPUTERNAME") -or ('SQL2' -eq "$env:COMPUTERNAME")) {
    Write-Host '[+] Install Failover cluster manager and PowerShell module'
    Install-WindowsFeature Failover-Clustering,RSAT-Clustering-Mgmt,RSAT-Clustering-PowerShell -IncludeManagementTools
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

