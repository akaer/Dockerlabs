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

$env:SQL_SERVER_INSTANCE_NAME = "SQLSERVER"
$env:SQL_SERVER_INSTANCE = "SQL\$env:SQL_SERVER_INSTANCE_NAME"
$env:SQL_SERVER_PRIMARY_INSTANCE = "SQL1\$env:SQL_SERVER_INSTANCE_NAME"
$env:SQL_SERVER_SERVICE_NAME = "MSSQL`$$env:SQL_SERVER_INSTANCE_NAME"
$env:SQL_SERVER_FQDN = "sql.${DOMAIN_NAME}"

function Get-StringSha256Hash {
    param (
        [string]$InputString
    )
    $stringBytes = [System.Text.Encoding]::UTF8.GetBytes($InputString)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($stringBytes)
    $hashString = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
    return $hashString.ToLower()
}

function Get-SqlServerSetup {
    # see https://www.microsoft.com/en-us/sql-server/sql-server-downloads
    # see https://learn.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server-from-the-command-prompt?view=sql-server-ver16
    # see https://github.com/microsoft/winget-pkgs/tree/master/manifests/m/Microsoft/SQLServer/2022/Developer/
    $archiveUrl = 'https://download.microsoft.com/download/c/c/9/cc9c6797-383c-4b24-8920-dc057c1de9d3/SQL2022-SSEI-Dev.exe'
    $mediaPath = "C:\temp\download\SQLSERVER-$(Get-StringSha256Hash $archiveUrl)"
    $setupPath = "C:\temp\SQLSERVER-$(Get-StringSha256Hash $archiveUrl)\setup.exe"

    # download setup.
    if (!(Test-Path $setupPath)) {
        if (!(Test-Path $mediaPath)) {
            mkdir $mediaPath | Out-Null
        }
        $archiveName = Split-Path -Leaf $archiveUrl
        $archivePath = "$mediaPath\$archiveName"
        if (!(Test-Path $archivePath)) {
            Write-Host "Downloading $archiveName SQL Server Bootstrap Installer..."
            (New-Object Net.WebClient).DownloadFile($archiveUrl, $archivePath)
        }
        $sfxPath = "$mediaPath\SQL*ENU.exe"
        if (!(Test-Path $sfxPath)) {
            Write-Host "Downloading SQL Server Setup..."
            &$archivePath `
                /ENU `
                /LANGUAGE=en-US `
                /ACTION=Download `
                /MEDIAPATH="$mediaPath" `
                /MEDIATYPE=CAB `
                /QUIET `
                /VERBOSE `
                | Out-String -Stream `
                | Out-Host
            if ($LASTEXITCODE) {
                throw "failed with exit code $LASTEXITCODE"
            }
        }
        Write-Host "Extracting SQL Server Setup..."
        &$sfxPath `
            /Q `
            /X:"$(Split-Path -Parent $setupPath)" `
            /VERBOSE `
            | Out-String -Stream `
            | Out-Host
        if ($LASTEXITCODE) {
            throw "failed with exit code $LASTEXITCODE"
        }
    }

    return $setupPath
}