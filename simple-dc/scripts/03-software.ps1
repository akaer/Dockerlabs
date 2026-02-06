#Requires -Version 5.1
#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
if ($env:DEBUG -eq 'True') { Set-PSDebug -Trace 1 }

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$DebugPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

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
& winget install --disable-interactivity --accept-package-agreements --accept-source-agreements --silent -e --source winget `
Microsoft.Edit `
7zip.7zip `
Microsoft.DotNet.SDK.8 `
Microsoft.DotNet.SDK.10 `
Microsoft.PowerShell `
Microsoft.Sysinternals.BGInfo `
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

