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

if ('DC' -ne "$env:COMPUTERNAME") {
    exit 0
}

Write-Host '[+] Install Active Directory software'
Import-Module ServerManager
Install-WindowsFeature AD-Domain-Services,RSAT-AD-AdminCenter,RSAT-ADDS-Tools

Write-Host "[+] Create domain $DOMAIN_NAME"
Import-Module ADDSDeployment
Install-ADDSForest `
    -DomainName "$DOMAIN_NAME" `
    -DomainNetBiosName "$NETBIOS_NAME" `
    -DomainMode $DOMAIN_MODE `
    -ForestMode $FOREST_MODE `
    -SkipPreChecks `
    -InstallDns `
    -CreateDnsDelegation:$false `
    -DatabasePath 'c:\AD\NTDS' `
    -SysvolPath 'c:\AD\SYSVOL' `
    -LogPath 'c:\AD\Logs' `
    -SafeModeAdministratorPassword (ConvertTo-SecureString "$AD_ADMIN_PASSWORD" -AsPlainText -Force) `
    -NoRebootOnCompletion `
    -Force

# After domain creation a reboot is needed before other machines can join the domain.
# For this we create a domain_ready.txt file in our state directory and let the other
# VMs wait for it

$DomainReadyScript = @'
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
    Exit 1
}

# Load environment configuration
$EnvFile = Join-Path $PSScriptRoot 'env.ps1'
if (Test-Path $EnvFile) {
    . $EnvFile
}

# Set encoding for proper umlaut handling
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Helper function to create PTR records dynamically
function Add-ReverseDNSRecord {
    param(
        [string]$IPAddress,
        [string]$ComputerName,
        [string]$DomainName
    )

    # Parse IP address to extract octets and reverse zone
    $octets = $IPAddress.Split('.')
    $reverseZone = "{2}.{1}.{0}.in-addr.arpa" -f $octets[0], $octets[1], $octets[2]
    $hostOctet = $octets[3]
    $fqdn = "{0}.{1}" -f $ComputerName, $DomainName

    Add-DnsServerResourceRecordPtr -ZoneName $reverseZone -Name $hostOctet -PtrDomainName $fqdn
    Write-Host "Added PTR record: $IPAddress -> $fqdn"
}

# Helper function using native PowerShell cmdlets
function New-ADOrganizationalUnitDynamic {
    param(
        [string]$Name,
        [string]$Description,
        [string]$DomainName
    )

    # Convert domain name to DN format
    $domainDN = ($DomainName.Split('.') | ForEach-Object { "dc=$_" }) -join ','

    New-ADOrganizationalUnit `
        -Name $Name `
        -Path $domainDN `
        -Description $Description `
        -ProtectedFromAccidentalDeletion $true `
        -ErrorAction SilentlyContinue

    Write-Host "[+] Created OU: ou=$Name,$domainDN"
}

# Helper function for service accounts
function New-ServiceAccount {
    param(
        [string]$SamAccountName,
        [string]$DisplayName,
        [string]$DomainName,
        [SecureString]$Password
    )

    $domainDN = ($DomainName.Split('.') | ForEach-Object { "dc=$_" }) -join ','
    $ouPath = "ou=ServiceAccounts,$domainDN"

    New-ADUser `
        -Name $SamAccountName `
        -SamAccountName $SamAccountName `
        -UserPrincipalName "$SamAccountName@$DomainName" `
        -DisplayName $DisplayName `
        -Description $DisplayName `
        -Path $ouPath `
        -AccountPassword $Password `
        -PasswordNeverExpires $true `
        -Enabled $true `
        -ChangePasswordAtLogon $false `
        -ErrorAction SilentlyContinue

    Write-Host "[+] Service Account: $SamAccountName"
}

# Helper function for employees
function New-EmployeeAccount {
    param(
        [string]$SamAccountName,
        [string]$FirstName,
        [string]$LastName,
        [string]$DomainName,
        [SecureString]$Password
    )

    $domainDN = ($DomainName.Split('.') | ForEach-Object { "dc=$_" }) -join ','
    $ouPath = "ou=Employees,$domainDN"
    $displayName = "$FirstName $LastName"

    New-ADUser `
        -Name $SamAccountName `
        -SamAccountName $SamAccountName `
        -UserPrincipalName "$SamAccountName@$DomainName" `
        -GivenName $FirstName `
        -Surname $LastName `
        -DisplayName $displayName `
        -Description $displayName `
        -Path $ouPath `
        -AccountPassword $Password `
        -PasswordNeverExpires $true `
        -Enabled $true `
        -ChangePasswordAtLogon $false `
        -ErrorAction SilentlyContinue

    Write-Host "[+] Employee: $displayName"
}

function Initialize-DnsReverseZone {
    param(
        [Parameter(Mandatory)]
        [string]$NetworkID,

        [int]$ServiceWaitAttempts = 10,
        [int]$ServiceWaitDelay = 5,
        [int]$ZoneCreateAttempts = 3,
        [int]$ZoneCreateDelay = 10
    )

    # Step 1: Wait for DNS service to be running
    Write-Host '[1/3] Verifying DNS Server service status...'

    $serviceReady = $false
    for ($i = 1; $i -le $ServiceWaitAttempts; $i++) {
        try {
            $dnsService = Get-Service -Name 'DNS' -ErrorAction Stop

            if ($dnsService.Status -ne 'Running') {
                Write-Host "[-]    Service status: $($dnsService.Status), waiting... ($i/$ServiceWaitAttempts)"
                Start-Sleep -Seconds $ServiceWaitDelay
                continue
            }

            # Verify DNS server cmdlets are accessible
            $null = Get-DnsServer -ErrorAction Stop

            Write-Host '[+] DNS Server service is operational'
            $serviceReady = $true
            break
        }
        catch {
            Write-Host "[-]    DNS not ready: $($_.Exception.Message) ($i/$ServiceWaitAttempts)"

            if ($i -lt $ServiceWaitAttempts) {
                Start-Sleep -Seconds $ServiceWaitDelay
            }
        }
    }

    if (-not $serviceReady) {
        throw "DNS Server service failed to become ready after $ServiceWaitAttempts attempts"
    }

    # Step 2: Check if zone already exists
    Write-Host '[2/3] Checking for existing reverse zone...'

    try {
        $networkParts = $NetworkID -split '/'
        $ipParts = $networkParts[0] -split '\.'
        $expectedZoneName = "$($ipParts[2]).$($ipParts[1]).$($ipParts[0]).in-addr.arpa"

        $existingZone = Get-DnsServerZone -Name $expectedZoneName -ErrorAction SilentlyContinue

        if ($existingZone) {
            Write-Host "[!] Zone '$expectedZoneName' already exists"
            return $existingZone
        }
    }
    catch {
        # Zone doesn't exist, continue
    }

    # Step 3: Create reverse zone with retry
    Write-Host '[3/3] Creating DNS reverse lookup zone...'

    for ($attempt = 1; $attempt -le $ZoneCreateAttempts; $attempt++) {
        try {
            Write-Host "[-]    Attempt $attempt/$ZoneCreateAttempts for network $NetworkID"

            $zone = Add-DnsServerPrimaryZone `
                -NetworkID $NetworkID `
                -ReplicationScope Domain `
                -DynamicUpdate Secure `
                -PassThru `
                -ErrorAction Stop

            Write-Host "[+] Successfully created zone: $($zone.ZoneName)"
            return $zone
        }
        catch {
            $errorMsg = $_.Exception.Message
            Write-Host "[!] Attempt $attempt failed: $errorMsg"

            if ($attempt -lt $ZoneCreateAttempts) {
                Write-Host "[-]    Waiting $ZoneCreateDelay seconds before retry..."
                Start-Sleep -Seconds $ZoneCreateDelay
            }
            else {
                throw "Failed to create DNS reverse zone after $ZoneCreateAttempts attempts: $errorMsg"
            }
        }
    }
}

$LogFilePath = 'c:\OEM\configure.log'

Start-Transcript -Path $LogFilePath -Append

Write-Host '[+] Start domain ready script'

# Convert domain to DN
$domainDN = ($DOMAIN_NAME.Split('.') | ForEach-Object { "dc=$_" }) -join ','
$secureUserPassword = ConvertTo-SecureString $AD_USER_PASSWORD -AsPlainText -Force

# Wait some seconds until our domain is ready to use and we can proceed
while ($true) {
    try {
        Get-ADDomain | Out-Null

        Write-Host "[+] Domain $DOMAIN_NAME ready!"
        break
    } catch {
        Start-Sleep -Seconds 10
    }
}

Write-Host '[+] Add DNS reverse lookup zone'
try {
    Initialize-DnsReverseZone -NetworkID $NETWORK_SUBNET
    Write-Host '[+] DNS reverse zone initialization complete'
}
catch {
    Write-Host "[!] DNS reverse zone initialization failed: $_"
    exit 1
}

Write-Host '[+] Add DNS entries to reverse DNS lookup zone'
Add-ReverseDNSRecord -IPAddress $DC_NETWORK_IP -ComputerName $DC_COMPUTERNAME -DomainName $DOMAIN_NAME
Add-ReverseDNSRecord -IPAddress $WEB_NETWORK_IP -ComputerName $WEB_COMPUTERNAME -DomainName $DOMAIN_NAME
Add-ReverseDNSRecord -IPAddress $CLIENT_NETWORK_IP -ComputerName $CLIENT_COMPUTERNAME -DomainName $DOMAIN_NAME

Write-Host '[+] Add DNS entries for db and mailcatcher'
Add-DnsServerResourceRecordA -Name 'db' -ZoneName $DOMAIN_NAME -IPv4Address $DOCKER_DB_IP
Add-DnsServerResourceRecordA -Name 'mail' -ZoneName $DOMAIN_NAME -IPv4Address $DOCKER_MAILCATCHER_IP

# Create OUs
New-ADOrganizationalUnitDynamic -Name 'ServiceAccounts' -Description 'Service Accounts for test lab' -DomainName $DOMAIN_NAME
New-ADOrganizationalUnitDynamic -Name 'Employees' -Description 'General employee accounts' -DomainName $DOMAIN_NAME

# Define accounts
$serviceAccounts = @(
    @{ SamId = 'svc_mastersql'; DisplayName = 'Master SQL JobService Account' }
    @{ SamId = 'svc_appserver'; DisplayName = 'AppServer Account' }
    @{ SamId = 'svc_apiserver'; DisplayName = 'ApiServer Account' }
    @{ SamId = 'svc_webportal'; DisplayName = 'Webportal Account' }
    @{ SamId = 'svc_webmanager'; DisplayName = 'Webmanager Account' }
    @{ SamId = 'svc_sts'; DisplayName = 'Secure Token Service Account' }
)

$employees = @(
    @{ SamId = 'erikam'; FirstName = 'Erika'; LastName = 'Mustermann' }
    @{ SamId = 'maxm'; FirstName = 'Max'; LastName = 'Mustermann' }
    @{ SamId = 'otton'; FirstName = 'Otto'; LastName = 'Normalverbraucher' }
    @{ SamId = 'markusm'; FirstName = 'Markus'; LastName = 'Möglich' }
    @{ SamId = 'alicem'; FirstName = 'Alice'; LastName = 'Miller' }
    @{ SamId = 'bobm'; FirstName = 'Bob'; LastName = 'Miller' }
    @{ SamId = 'mallorym'; FirstName = 'Mallory'; LastName = 'Miller' }
    @{ SamId = 'evem'; FirstName = 'Eve'; LastName = 'Miller' }
    @{ SamId = 'steveo'; FirstName = 'Steve'; LastName = 'O' }
    @{ SamId = 'fredo'; FirstName = 'Fred'; LastName = 'Ou' }
    @{ SamId = 'hansd'; FirstName = 'Hans'; LastName = 'Dc' }
    @{ SamId = 'rainern'; FirstName = 'Rainer'; LastName = 'Null' }
    @{ SamId = 'mandyc'; FirstName = 'Mandy'; LastName = 'Cn' }
    @{ SamId = 'peggyd'; FirstName = 'Peggy'; LastName = 'Dn' }
)

# Create all service accounts
$serviceAccounts | ForEach-Object {
    New-ServiceAccount -SamAccountName $_.SamId -DisplayName $_.DisplayName -DomainName $DOMAIN_NAME -Password $secureUserPassword
}

# Create all employee accounts
$employees | ForEach-Object {
    New-EmployeeAccount -SamAccountName $_.SamId -FirstName $_.FirstName -LastName $_.LastName -DomainName $DOMAIN_NAME -Password $secureUserPassword
}

# configure the AD to allow the use of Group Managed Service Accounts (gMSA).
# see https://docs.microsoft.com/en-us/windows-server/security/group-managed-service-accounts/group-managed-service-accounts-overview
# see https://docs.microsoft.com/en-us/windows-server/security/group-managed-service-accounts/create-the-key-distribution-services-kds-root-key
Write-Host '[+] Activate support for Group Managed Service Accounts (gMSA)'
Add-KdsRootKey -EffectiveTime (Get-Date).AddHours(-10) | Out-Null

$adDomain = Get-ADDomain
$domain = $adDomain.DNSRoot
$domainDn = $adDomain.DistinguishedName
$usersAdPath = "CN=Users,$domainDn"
$msaAdPath = "CN=Managed Service Accounts,$domainDn"

@(
    'svc_jobserver'
) | ForEach-Object {
    New-ADServiceAccount `
        -Path $msaAdPath `
        -DNSHostName $domain `
        -Name $_
    Set-ADServiceAccount `
        -Identity $_ `
        -PrincipalsAllowedToRetrieveManagedPassword @(
            ,"CN=Domain Controllers,$usersAdPath"
            ,"CN=Domain Computers,$usersAdPath"
        )
    # test whether this computer can use the gMSA.
    Test-ADServiceAccount `
        -Identity $_ `
        | Out-Null
}

'Domain ready' | Out-File '\\host.lan\data\state\domain_ready.txt'

Write-Host '[+] Deactivate auto logon'
$regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty -Path $regPath -Name 'AutoAdminLogon' -Value '0' -Type String
Remove-ItemProperty -Path $regPath -Name 'DefaultPassword' -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $regPath -Name 'AutoLogonCount' -ErrorAction SilentlyContinue

Stop-Transcript

Restart-Computer -Force
'@

Set-Content 'c:\oem\domain_ready.ps1' $DomainReadyScript -Force

# Continue with DomainReadyScript after reboot
$KeyName = 'DomainReady'
$Command = 'cmd /C if exist "c:\oem\domain_ready.ps1" start "Install" powershell -ExecutionPolicy Unrestricted -NoProfile -File "c:\oem\domain_ready.ps1"'
New-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name $KeyName -Value $Command -PropertyType ExpandString | Out-Null

# Use Autologon as administrator
$winlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty -Path $winlogonPath -Name 'AutoAdminLogon' -Value '1' -Type String
Set-ItemProperty -Path $winlogonPath -Name 'DefaultUserName' -Value 'administrator' -Type String
Set-ItemProperty -Path $winlogonPath -Name 'DefaultPassword' -Value "$LOCAL_ADMIN_PASSWORD" -Type String

