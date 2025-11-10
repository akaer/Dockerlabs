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

    if (Test-Path 'c:\OEM\configure.log') {
        & notepad 'c:\OEM\configure.log'
    }
    Exit 1
}

# Load environment configuration
$EnvFile = Join-Path $PSScriptRoot 'env.ps1'
if (Test-Path $EnvFile) {
    . $EnvFile
}

$LogFilePath = 'c:\OEM\configure.log'

Start-Transcript -Path $LogFilePath -Append

. c:\OEM\sqlserver-common.ps1

if ( 'SQL1' -eq "$env:COMPUTERNAME" ) {
    do {
        $ping = Test-Connection -ComputerName SQL2 -count 1 -Quiet -ErrorAction SilentlyContinue
        Start-Sleep -Second 30
    } until ($ping)
}

if ( 'SQL2' -eq "$env:COMPUTERNAME" ) {
    do {
        $ping = Test-Connection -ComputerName SQL1 -count 1 -Quiet -ErrorAction SilentlyContinue
        Start-Sleep -Second 30
    } until ($ping)
}

$mirroringEndpointName = 'hadr_endpoint'
$mirroringEndpointPort = 5022
$primaryComputerName = $env:COMPUTERNAME -replace '\d+$','1'
$secondaryComputerName = $env:COMPUTERNAME -replace '\d+$','2'
$primaryReplicaMirroringEndpointUrl = "TCP://${primaryComputerName}.${DOMAIN_NAME}:$mirroringEndpointPort"
$secondaryReplicaMirroringEndpointUrl = "TCP://${secondaryComputerName}.${DOMAIN_NAME}:$mirroringEndpointPort"

Write-Host "[+] Waiting for the $FILE_CLUSTER_NAME Failover Cluster to be available..."
while ( -Not (Get-Cluster -Name $FILE_CLUSTER_NAME -ErrorAction SilentlyContinue) ) {
    Write-Host '[-] Wait some seconds for cluster'
    Start-Sleep -Second 30
}

while (Get-ClusterResource -Cluster $FILE_CLUSTER_NAME | Where-Object State -ne Online) {
    Write-Host '[-] Wait some seconds for cluster resources to get online'
    Start-Sleep -Second 30
}

while (Get-ClusterNode -Cluster $FILE_CLUSTER_NAME | Where-Object State -ne Up) {
    Write-Host '[-] Wait some seconds for cluster resources to get online'
    Start-Sleep -Second 30
}

Write-Host "[+] Cluster overview $FILE_CLUSTER_NAME"
Get-ClusterResource -Cluster $FILE_CLUSTER_NAME
Get-ClusterNode -Cluster $FILE_CLUSTER_NAME

Write-Host '[+] Creating the firewall rule to allow inbound access to the SQL Server TCP/IP port 1433...'
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
    -Name '[+] SQL-SERVER-BROWSER-In-UDP' `
    -DisplayName 'SQL Server Browser (UDP-In)' `
    -Direction Inbound `
    -Enabled True `
    -Protocol UDP `
    -LocalPort 1434 `
    | Out-Null

Write-Host "[+] Creating the firewall rule to allow inbound access to the SQL Server Mirroring TCP/IP port $mirroringEndpointPort..."
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
Write-Host 'Installing SQL Server...'
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
$dataRootPath = 'C:\sql-server-storage'
& $setupPath `
    /IACCEPTSQLSERVERLICENSETERMS `
    /QUIET `
    /ACTION=Install `
    /FEATURES=SQLENGINE,REPLICATION `
    /UPDATEENABLED=1 `
    /INSTANCEID="$env:SQL_SERVER_INSTANCE_NAME" `
    /INSTANCENAME="$env:SQL_SERVER_INSTANCE_NAME" `
    /SQLSVCACCOUNT="$NETBIOS_NAME\sqlserver$" `
    /AGTSVCACCOUNT="$NETBIOS_NAME\sqlserver_agent$" `
    /SQLSYSADMINACCOUNTS="$env:USERDOMAIN\$env:USERNAME" `
    /INSTALLSQLDATADIR="$dataRootPath\Data" `
    /SQLUSERDBDIR="$dataRootPath\Data" `
    /SQLUSERDBLOGDIR="$dataRootPath\Data" `
    /SQLTEMPDBDIR="$dataRootPath\Data" `
    /SQLTEMPDBLOGDIR="$dataRootPath\Data" `
    /SQLBACKUPDIR="$dataRootPath\Backup"
if ($LASTEXITCODE -ne 0) {
    $logsPath = Resolve-path "C:\Program Files\Microsoft SQL Server\*\Setup Bootstrap\Log"
    throw "[!] SQL Server installation failed with exit code $LASTEXITCODE. See the logs at $logsPath."
}

# Grab latest version from https://learn.microsoft.com/en-us/troubleshoot/sql/releases/sqlserver-2022/build-versions
#$DownloadUrl = 'https://download.microsoft.com/download/a89001cb-9c99-48d3-9f14-ded054b35fe4/SQLServer2022-KB5065865-x64.exe'
#$DownloadPath = "$env:TEMP\SQLServer2022-CU.exe"
#$InstallArgs = '/ACTION=Patch /QUIET /IACCEPTSQLSERVERLICENSETERMS'

#Write-Host '[+] Downloading latest SQL Server 2022 CU...'
#(New-Object Net.WebClient).DownloadFile($DownloadUrl, $DownloadPath)

# Step 3: Silent installation of CU
#Write-Host '[+] Installing SQL Server 2022 CU silently...'
#Start-Process -FilePath $DownloadPath -ArgumentList $InstallArgs -Wait

# Step 4: Cleanup (optional)
#Remove-Item $DownloadPath -Force
#Write-Host '[+] SQL Server 2022 CU installed successfully.'

Write-Host "[+] Configuring SQL Server to allow encrypted connections at ${SQL_CLUSTER_NAME}.${DOMAIN_NAME}..."
$certificate = Get-ChildItem -DnsName "${SQL_CLUSTER_NAME}.${DOMAIN_NAME}" Cert:\LocalMachine\My
$superSocketNetLibPath = Resolve-Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL*.$env:SQL_SERVER_INSTANCE_NAME\MSSQLServer\SuperSocketNetLib"
Set-ItemProperty `
    -Path $superSocketNetLibPath `
    -Name Certificate `
    -Value $certificate.Thumbprint
Set-ItemProperty `
    -Path $superSocketNetLibPath `
    -Name ForceEncryption `
    -Value 0

Unblock-File 'c:\OEM\Security.Cryptography.dll'
Add-Type -Path 'c:\OEM\Security.Cryptography.dll'

function Get-PrivateKeyContainerPath() {
    param(
        [Parameter(Mandatory=$true)][string][ValidateNotNullOrEmpty()]$name,
        [Parameter(Mandatory=$true)][boolean]$isCng
    )

    Write-Host '[-] Search private key container'
    if ($isCng) {
        $searchDirectories = @('Microsoft\Crypto\Keys', 'Microsoft\Crypto\SystemKeys')
    } else {
        $searchDirectories = @('Microsoft\Crypto\RSA\MachineKeys', 'Microsoft\Crypto\RSA\S-1-5-18', 'Microsoft\Crypto\RSA\S-1-5-19', 'Crypto\DSS\S-1-5-20')
    }
    $commonApplicationDataDirectory = [Environment]::GetFolderPath('CommonApplicationData')
    foreach ($searchDirectory in $searchDirectories) {
        $privateKeyFile = Get-ChildItem -Path "$commonApplicationDataDirectory\$searchDirectory" -Filter $name -Recurse
        if ($privateKeyFile) {

            Write-Host "[-] Key container found: $($privateKeyFile.FullName)"
            return $privateKeyFile.FullName
        }
    }
    throw "[!] Cannot find private key file path for the $name key container."
}

function Grant-PrivateKeyReadPermissions($certificate, $accountName) {
    if ([Security.Cryptography.X509Certificates.X509CertificateExtensionMethods]::HasCngKey($certificate)) {
        $privateKey = [Security.Cryptography.X509Certificates.X509Certificate2ExtensionMethods]::GetCngPrivateKey($certificate)
        $keyContainerName = $privateKey.UniqueName
        $privateKeyPath = Get-PrivateKeyContainerPath $keyContainerName $true
    } elseif ($certificate.PrivateKey) {
        $privateKey = $certificate.PrivateKey
        $keyContainerName = $certificate.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
        $privateKeyPath = Get-PrivateKeyContainerPath $keyContainerName $false
    } else {
        throw '[!] Certificate does not have a private key, or that key is inaccessible, therefore permission cannot be granted.'
    }
    $acl = Get-Acl -Path $privateKeyPath
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule @($accountName, 'Read', 'Allow')))
    Set-Acl $privateKeyPath $acl
}

Write-Host "[+] Granting SQL Server Read permissions to the ${SQL_CLUSTER_NAME}.${DOMAIN_NAME} private key..."
Grant-PrivateKeyReadPermissions $certificate "$NETBIOS_NAME\SqlServer$"

Write-Host "[+] Restarting the SQL Server $env:SQL_SERVER_SERVICE_NAME service..."
Restart-Service $env:SQL_SERVER_SERVICE_NAME -Force

Write-Host '[+] Enabling and starting the SQL Server Browser service...'
Set-Service -Name SQLBrowser -StartupType Automatic
Start-Service -Name SQLBrowser

Write-Host '[+] Enable TCP for the SQL Server and set port to 1433'
$regPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL*.$env:SQL_SERVER_INSTANCE_NAME\MSSQLServer\SuperSocketNetLib\Tcp\IPAll"
Set-ItemProperty -Path $regPath -Name TcpPort -Value '1433'
Set-ItemProperty -Path $regPath -Name TcpDynamicPorts -Value ''
Set-ItemProperty -Path "$regPath\.." -Name Enabled -Value 1

Import-Module SqlServer

Write-Host '[+] Enabling Mixed Mode Authentication'
$server = New-Object Microsoft.SqlServer.Management.Smo.Server "$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME"
$server.Settings.LoginMode = 'Mixed'
$server.Alter()

Write-Host '[+] Enable sa sql login'
Invoke-Sqlcmd `
    -ServerInstance "$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME" `
    -Query @"
ALTER LOGIN [sa] WITH PASSWORD='$SQL_SA_PASSWORD', CHECK_POLICY=OFF
GO
ALTER LOGIN [sa] ENABLE
GO
"@

Write-Host "[+] Creating the $NETBIOS_NAME\SqlServer$ account login as a regular user..."
$server = New-Object Microsoft.SqlServer.Management.Smo.Server("$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME")
$login = New-Object Microsoft.SqlServer.Management.Smo.Login($server, "$NETBIOS_NAME\SqlServer$")
$login.LoginType = [Microsoft.SqlServer.Management.Smo.LoginType]::WindowsUser
$login.Create()

Write-Host '[+] SQL Server Version:'
$versionResult = Invoke-Sqlcmd `
    -ServerInstance "$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME" `
    -Query 'select @@version as Version'
Write-Output $versionResult.Version

# enable always on and restart sql server.
Write-Host '[+] Enabling Always On Availability Groups'
Enable-SqlAlwaysOn `
    -ServerInstance "$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME" `
    -Force

# verify that always on is enabled.
Write-Host '[+] Verifying that Always On Availability Groups is enabled'
$result = Invoke-Sqlcmd `
    -ServerInstance "$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME" `
    -Query "select serverproperty('IsHadrEnabled') as IsHadrEnabled"
if ($result.IsHadrEnabled -ne 1) {
    throw '[!] Failed to enable Always On.'
}

Write-Host '[+] Creating the database mirroring endpoint...'
$mirroringEndpoint = New-SqlHadrEndpoint `
    -Path "SQLSERVER:\SQL\$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME" `
    -Name $mirroringEndpointName `
    -Port $mirroringEndpointPort

Write-Host "[+] Granting the $NETBIOS_NAME\SqlServer$ account connect access to the $mirroringEndpointName endpoint..."
Invoke-Sqlcmd `
    -ServerInstance "$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME" `
    -Query "grant connect on endpoint::[$mirroringEndpointName] to [$NETBIOS_NAME\SqlServer$]"

Write-Host "[+] Starting the database mirroring endpoint..."
Set-SqlHadrEndpoint `
    -InputObject $mirroringEndpoint `
    -State Started `
    | Out-Null

Write-Host "[+] Verifying the database mirroring endpoint..."
$endpoint = Get-Item "SQLSERVER:\SQL\$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME\Endpoints\$mirroringEndpointName"
if ($endpoint.EndpointState -ne 'Started') {
    throw "[!] The database mirroring endpoint is not started. Instead its on the $($endpoint.EndpointState) state."
}

if ( 'SQL1' -eq "$env:COMPUTERNAME" ) {
    Write-Host "[+] Creating the $SQL_CLUSTER_NAME Availability Group with the $primaryComputerName and $secondaryComputerName computers"
    $versionResult = Invoke-Sqlcmd `
        -ServerInstance "$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME" `
        -Query "select serverproperty('ProductVersion') as version"

    $version = ($versionResult.version -split '\.')[0..1] -join '.'
    $primaryReplica = New-SqlAvailabilityReplica `
        -Name "$primaryComputerName\$env:SQL_SERVER_INSTANCE_NAME" `
        -EndpointURL $primaryReplicaMirroringEndpointUrl `
        -AvailabilityMode SynchronousCommit `
        -FailoverMode Automatic `
        -SeedingMode Automatic `
        -Version $version `
        -AsTemplate

    $secondaryReplica = New-SqlAvailabilityReplica `
        -Name "$secondaryComputerName\$env:SQL_SERVER_INSTANCE_NAME" `
        -EndpointURL $secondaryReplicaMirroringEndpointUrl `
        -AvailabilityMode SynchronousCommit `
        -FailoverMode Automatic `
        -SeedingMode Automatic `
        -Version $version `
        -AsTemplate

    New-SqlAvailabilityGroup `
        -Path "SQLSERVER:\SQL\$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME" `
        -Name $SQL_CLUSTER_NAME `
        -ContainedAvailabilityGroup `
        -AvailabilityReplica @($primaryReplica, $secondaryReplica) `
        | Out-Null

    'availability group ready' | Out-File '\\host.lan\data\state\cluster_agl_created.txt'
}

if ( 'SQL2' -eq "$env:COMPUTERNAME" ) {

    Write-Host '[+] Wait for availability group creation'
    while ($true) {

        if (Test-Path -Path '\\host.lan\data\state\cluster_agl_created.txt') {
            break
        }

        Start-Sleep -Second 30
    }

    Write-Host "[+] Joining the $SQL_CLUSTER_NAME Availability Group"
    Join-SqlAvailabilityGroup `
        -Path "SQLSERVER:\SQL\$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME" `
        -Name $SQL_CLUSTER_NAME

    'availability group joined' | Out-File '\\host.lan\data\state\cluster_agl_joined.txt'
}

Write-Host '[+] Wait for availability group join'
while ($true) {

    if (Test-Path -Path '\\host.lan\data\state\cluster_agl_joined.txt') {
        break
    }

    Start-Sleep -Second 30
}

Write-Host "[+] Granting the $SQL_CLUSTER_NAME Availability Group permissions to create any database"
Grant-SqlAvailabilityGroupCreateAnyDatabase `
    -Path "SQLSERVER:\SQL\$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME\AvailabilityGroups\$SQL_CLUSTER_NAME"

Write-Host "[+] Getting the $SQL_CLUSTER_NAME Availability Group status"
Get-ChildItem `
    -Path "SQLSERVER:\SQL\$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME\AvailabilityGroups\$SQL_CLUSTER_NAME\AvailabilityReplicas" `
    | Format-Table

if ( 'SQL1' -eq "$env:COMPUTERNAME" ) {
    Write-Host "[+] Creating the $SQL_CLUSTER_NAME Availability Group Listener"
    # HINT: this will create the $SQL_CLUSTER_NAME Computer account in the DC.
    # TODO: Make subnet dynamic / a variable
    New-SqlAvailabilityGroupListener `
        -Path "SQLSERVER:\SQL\$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME\AvailabilityGroups\$SQL_CLUSTER_NAME" `
        -Name $SQL_CLUSTER_NAME `
        -StaticIp "$SQL_CLUSTER_IP/255.255.255.0" `
        -Port 1433 `
        | Out-Null
}

Write-Host "[+] Enabling contained database authentication"
Invoke-Sqlcmd `
    -ServerInstance "$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME" `
    -Query @"
exec sp_configure 'contained database authentication', 1;
reconfigure;
"@

Write-Host '[+] Deactivate auto logon'
$regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty -Path $regPath -Name 'AutoAdminLogon' -Value '0' -Type String
Remove-ItemProperty -Path $regPath -Name 'DefaultPassword' -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $regPath -Name 'DefaultDomainName' -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $regPath -Name 'AutoLogonCount' -ErrorAction SilentlyContinue

Stop-Transcript
