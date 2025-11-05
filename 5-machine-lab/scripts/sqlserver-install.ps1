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

$FILE_ClUSTER_NAME='SQLC'
$SQL_CLUSTER_NAME='SQL'

. ./sqlserver-common.ps1

$netbiosDomain = ($DOMAIN_NAME -split '\.')[0].ToUpperInvariant()
$mirroringEndpointName = 'hadr_endpoint'
$mirroringEndpointPort = 5022
$primaryComputerName = $env:COMPUTERNAME -replace '\d+$','1'
$secondaryComputerName = $env:COMPUTERNAME -replace '\d+$','2'
$primaryReplicaMirroringEndpointUrl = "TCP://${primaryComputerName}.${DOMAIN_NAME}:$mirroringEndpointPort"
$secondaryReplicaMirroringEndpointUrl = "TCP://${secondaryComputerName}.${DOMAIN_NAME}:$mirroringEndpointPort"

Write-Host 'Creating the firewall rule to allow inbound access to the SQL Server TCP/IP port 1433...'
New-NetFirewallRule `
    -Name 'SQL-SERVER-In-TCP' `
    -DisplayName 'SQL Server (TCP-In)' `
    -Direction Inbound `
    -Enabled True `
    -Protocol TCP `
    -LocalPort 1433 `
    | Out-Null

Write-Host 'Creating the firewall rule to allow inbound access to the SQL Server Browser UDP/IP port 1434...'
New-NetFirewallRule `
    -Name 'SQL-SERVER-BROWSER-In-UDP' `
    -DisplayName 'SQL Server Browser (UDP-In)' `
    -Direction Inbound `
    -Enabled True `
    -Protocol UDP `
    -LocalPort 1434 `
    | Out-Null

Write-Host "Creating the firewall rule to allow inbound access to the SQL Server Mirroring TCP/IP port $mirroringEndpointPort..."
New-NetFirewallRule `
    -Name 'SQL-SERVER-MIRRORING-In-TCP' `
    -DisplayName 'SQL Server Mirroring (TCP-In)' `
    -Direction Inbound `
    -Enabled True `
    -Protocol TCP `
    -LocalPort $mirroringEndpointPort `
    | Out-Null

# download.
$setupPath = Get-SqlServerSetup

# install.
# NB this cannot be executed from a network share (e.g. c:\vagrant).
# NB the logs are saved at "$env:ProgramFiles\Microsoft SQL Server\<version>\Setup Bootstrap\Log\<YYYYMMDD_HHMMSS>".
#    e.g. "C:\Program Files\Microsoft SQL Server\160\Setup Bootstrap\Log"
# NB you could also use /INDICATEPROGRESS to make the setup write the logs to
#    stdout in realtime.
# see https://learn.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server-from-the-command-prompt?view=sql-server-ver16#integrated-install-failover-cluster-parameters
# see https://learn.microsoft.com/en-us/sql/sql-server/failover-clusters/install/create-a-new-sql-server-failover-cluster-setup?view=sql-server-ver16
# see https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/create-an-availability-group-sql-server-powershell?
Write-Host "Installing SQL Server..."
# NB the setup data path parameters are:
#       /INSTALLSQLDATADIR    System database directory
#       /SQLUSERDBDIR         User database directory
#       /SQLUSERDBLOGDIR      User database log directory
#       /SQLTEMPDBDIR         TempDB data directory
#       /SQLTEMPDBLOGDIR      TempDB log directory
#       /SQLBACKUPDIR         Backup directory
# NB when using the setup wizard, it sets /INSTALLSQLDATADIR, /SQLUSERDBDIR,
#    /SQLUSERDBLOGDIR, /SQLTEMPDBDIR, and /SQLTEMPDBLOGDIR to the same
#    directory path.
$dataRootPath = "C:\sql-server-storage"
&$setupPath `
    /IACCEPTSQLSERVERLICENSETERMS `
    /QUIET `
    /ACTION=Install `
    /FEATURES=SQLENGINE,REPLICATION `
    /UPDATEENABLED=0 `
    /INSTANCEID="$env:SQL_SERVER_INSTANCE_NAME" `
    /INSTANCENAME="$env:SQL_SERVER_INSTANCE_NAME" `
    /SQLSVCACCOUNT="$netbiosDomain\sqlserver$" `
    /AGTSVCACCOUNT="$netbiosDomain\sqlserver_agent$" `
    /SQLSYSADMINACCOUNTS="$env:USERDOMAIN\$env:USERNAME" `
    /INSTALLSQLDATADIR="$dataRootPath\Data" `
    /SQLUSERDBDIR="$dataRootPath\Data" `
    /SQLUSERDBLOGDIR="$dataRootPath\Data" `
    /SQLTEMPDBDIR="$dataRootPath\Data" `
    /SQLTEMPDBLOGDIR="$dataRootPath\Data" `
    /SQLBACKUPDIR="$dataRootPath\Backup"
if ($LASTEXITCODE) {
    $logsPath = Resolve-path "C:\Program Files\Microsoft SQL Server\*\Setup Bootstrap\Log"
    throw "failed with exit code $LASTEXITCODE. see the logs at $logsPath."
}

# Grab latest version from https://learn.microsoft.com/en-us/troubleshoot/sql/releases/sqlserver-2022/build-versions
$DownloadUrl = "https://download.microsoft.com/download/a89001cb-9c99-48d3-9f14-ded054b35fe4/SQLServer2022-KB5065865-x64.exe"
$DownloadPath = "$env:TEMP\SQLServer2022-CU.exe"
$InstallArgs = "/ACTION=Patch /QUIET /IACCEPTSQLSERVERLICENSETERMS"

Write-Host "Downloading latest SQL Server 2022 CU..."
(New-Object Net.WebClient).DownloadFile($DownloadUrl, $DownloadPath)

# Step 3: Silent installation of CU
Write-Host "Installing SQL Server 2022 CU silently..."
Start-Process -FilePath $DownloadPath -ArgumentList $InstallArgs -Wait

# Step 4: Cleanup (optional)
Remove-Item $DownloadPath -Force
Write-Host "SQL Server 2022 CU installed successfully."
