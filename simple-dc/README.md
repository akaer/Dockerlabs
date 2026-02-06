# Simple DC Lab - Active Directory Test Environment

A containerized Active Directory (AD) test lab built with Docker and Windows Server 2025. This lab provides a complete domain environment for testing and development purposes.

## Table of Contents

- [Overview](#overview)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Lab Configuration](#lab-configuration)
- [Installed Software](#installed-software)
- [Domain Users and Service Accounts](#domain-users-and-service-accounts)
- [Network Configuration](#network-configuration)
- [Ports & Access](#ports--access)
- [Troubleshooting](#troubleshooting)
- [Use Cases](#use-cases)
- [Security Notice](#security-notice)
- [Support & Development](#support--development)
- [License](#license)
- [References](#references)

## Overview

This project deploys a self-contained Windows Server 2025 Domain Controller in a Docker container with a fully configured Active Directory forest. The lab includes pre-configured service accounts, domain users, DNS, certificate infrastructure, and common development tools.

**Domain:** `qs-lab.local` (NetBIOS: `QS-LAB`)
**Forest Mode:** Windows Server 2025
**Domain Mode:** Windows Server 2025

## Project Structure

```
simple-dc/
├── compose.yml                    # Docker Compose configuration
├── env.demo                       # Environment variables for lab configuration
├── deploy.sh                      # Initialize and deploy the lab
├── start.sh                       # Start the lab environment
├── stop.sh                        # Shutdown the lab (containers remain)
├── restart.sh                     # Restart the lab environment
├── stop_and_cleanup.sh            # Complete removal of lab and all data
├── scripts/                       # PowerShell configuration scripts
│   ├── 00-prepare.ps1            # Initial VM preparation and computer naming
│   ├── 01-network.ps1            # Network adapter configuration
│   ├── 02-general.ps1            # General system settings and software installation
│   ├── 04-certificates.ps1       # SSL/TLS certificate installation
│   ├── 05-prepare-for-ad.ps1     # Active Directory setup and user creation
│   ├── configure.ps1             # Main orchestration script
│   ├── env.ps1                   # PowerShell environment variables (generated)
│   ├── install.bat               # Batch file entry point
│   ├── user-profile.ps1          # User profile customization
│   └── certs/                    # Certificate storage directory
├── helper/
│   └── create_certificates.sh    # CA and certificate generation
├── ISOs/
│   ├── download.sh               # Windows Server 2025 ISO download script
│   └── 26100.1742.240906-0331... # Windows Server 2025 ISO (download required)
└── shared/
    └── state/                    # Shared state directory for VM coordination

```

## Prerequisites

### Host System Requirements
- Linux with KVM virtualization support
- Docker and Docker Compose
- Minimum 8GB RAM (16GB+ recommended)
- 100GB free disk space
- Required utilities:
  - `unix2dos`
  - `inotifywait`
  - `docker`
  - `vde_switch` (Virtual Distributed Ethernet)

### Installation

Install required tools (beside docker) on Ubuntu/Debian:
```bash
sudo apt-get update
sudo apt-get install -y dos2unix inotify-tools vde2
```

## Quick Start

### 1. Download Windows Server 2025 ISO

```bash
cd ISOs
bash download.sh
cd ..
```

The ISO should be automatically detected and placed in the `ISOs/` directory.

### 2. Deploy the Lab

```bash
bash deploy.sh
```

This will:
- Generate SSL certificates
- Set up virtual networking with VDE
- Create Docker containers
- Execute Windows Server setup scripts
- Configure Active Directory
- Create domain users and service accounts
- Wait for domain stabilization (may take 10-15 minutes)

### 3. Access the Lab

Once deployment completes:
- **RDP Access:** Connect to `localhost:4002` using RDP client
- **Local Admin:** `admn` / `P@ssw0rd`
- **DC Hostname:** `dc`
- **IP Address:** `192.168.42.10`
- **Domain:** `qs-lab.local`

### 4. Lab Management

```bash
# Shutdown the lab (preserve container data)
bash stop.sh

# Start the lab again
bash start.sh

# Restart the lab
bash restart.sh

# Complete cleanup (remove all data)
bash stop_and_cleanup.sh
```

## Lab Configuration

### Environment Variables

Edit `env.demo` to customize the lab. Key variables:

```bash
# Local Administrator Account
LOCAL_ADMIN_ACCOUNT=admn
LOCAL_ADMIN_PASSWORD=P@ssw0rd

# Domain Settings
DOMAIN_NAME=qs-lab.local
NETBIOS_NAME=QS-LAB
AD_ADMIN_PASSWORD=P@ssw0rd
AD_USER_PASSWORD=P@ssw0rd

# Network Configuration (DC VM)
DC_NETWORK_IP=192.168.42.10
NETWORK_SUBNET=192.168.42.0/24

# Docker Network
DOCKER_SUBNET=172.42.0.0/16
```

## Installed Software

### Windows Server 2025 Roles & Features
- **Active Directory Domain Services**
  - DNS Server (integrated with AD)
  - Remote Server Administration Tools (RSAT)
  - AD Administration Center
- **File and Printer Sharing**

### Development & System Tools
- **Microsoft PowerShell 7.x**
- **.NET SDK 8.0 and 10.0**
- **7-Zip** (compression utility)
- **Notepad++** (text editor)
- **Microsoft Sysinternals Suite**
  - Process Explorer
  - Task Manager
  - Registry Editor utilities
  - Performance monitoring tools
- **Microsoft Edit** (visual editor)

### System Utilities
- BGInfo (system information display)
- Certificate management tools
- Windows Update disabled (for lab stability)
- Windows Defender antivirus disabled (for performance)
- UAC enabled for security
- File and Printer sharing enabled
- Ping (ICMP) enabled

## Domain Users and Service Accounts

### Domain Administrator
- **Account:** `administrator` (forest root account)
- **Password:** `P@ssw0rd`
- **Type:** Domain Admin

### Service Accounts (OU: ServiceAccounts)

| Account | Display Name | Purpose |
|---------|--------------|---------|
| `svc_mastersql` | Master SQL JobService Account | SQL Server job agent service |
| `svc_appserver` | AppServer Account | Application server service |
| `svc_apiserver` | ApiServer Account | API server service |
| `svc_webportal` | Webportal Account | Web portal application |
| `svc_webmanager` | Webmanager Account | Web management service |
| `svc_sts` | Secure Token Service Account | Token service authentication |
| `svc_jobserver` | Job Server Account | Group Managed Service Account (gMSA) |

### Employee Accounts (OU: Employees)

| Username | Full Name |
|----------|-----------|
| `erikam` | Erika Mustermann |
| `maxm` | Max Mustermann |
| `otton` | Otto Normalverbraucher |
| `markusm` | Markus Möglich |
| `alicem` | Alice Miller |
| `bobm` | Bob Miller |
| `mallorym` | Mallory Miller |
| `evem` | Eve Miller |
| `steveo` | Steve O |
| `fredo` | Fred Ou |
| `hansd` | Hans Dc |
| `rainern` | Rainer Null |
| `mandyc` | Mandy Cn |
| `peggyd` | Peggy Dn |

All domain users have password: `P@ssw0rd`
All passwords are set to never expire for lab purposes.

### Group Managed Service Accounts (gMSA)
- `svc_jobserver` - Configured for automatic password management
- Allowed principals: Domain Controllers and Domain Computers

## Network Configuration

### Domain Network (VM)
- **Interface:** Domain (renamed)
- **IP:** 192.168.42.10
- **Netmask:** 255.255.255.0
- **Gateway:** 192.168.42.1
- **DNS:** 192.168.42.10 (local DC)
- **MAC:** 52:54:00:00:00:01

### Docker Network
- **Subnet:** 172.42.0.0/16
- **Gateway:** 172.42.0.1
- **DC Container IP:** 172.42.0.10
- **Driver:** Bridge

### DNS & Certificates
- Integrated DNS server on DC
- Reverse lookup zone configured for 192.168.42.0/24
- Self-signed CA certificate: `qs-lab.local.ca.der`
- Root CA installed in DC trusted store

## Ports & Access

| Port | Protocol | Service | Purpose |
|------|----------|---------|---------|
| 4002 | TCP/UDP | RDP | Remote Desktop (VM desktop) |
| 8002 | TCP | SPICE | VM console access |
| 5001 | TCP | HTTP | Job Server (HTTP) |
| 5002 | TCP | HTTP | Job Server (Alt HTTP) |
| 1880 | TCP | HTTPS | Secure service endpoint |

## Troubleshooting

### Lab Won't Deploy
1. Verify KVM is enabled: `grep -o vmx /proc/cpuinfo | wc -l` (should be non-zero)
2. Check Docker daemon: `sudo systemctl status docker`
3. Verify ISO file exists and is correct size
4. Review logs: `sudo docker logs -f dc`

### RDP Connection Fails
1. Confirm container is running: `sudo docker ps | grep dc`
2. Wait for Windows Server boot (check SPICE console on port 8002)
3. Verify network connectivity: `ping 172.42.0.10`
4. Check firewall: `sudo ufw allow 4002`

### Domain Users Not Accessible
1. Verify DC is joined to domain: `nltest /dclist:qs-lab.local` (from RDP)
2. Check Active Directory replication
3. Review PowerShell logs in `scripts/configure.log`

### Certificate Errors
1. Re-generate certificates: `bash helper/create_certificates.sh qs-lab.local`
2. Clear old certificates from shared directory
3. Redeploy: `bash stop_and_cleanup.sh && bash deploy.sh`

## Use Cases

- **Active Directory Development:** Test AD-integrated applications
- **PowerShell Scripting:** Develop and test domain automation scripts
- **Security Testing:** Lab environment for permission and authentication testing
- **Application Deployment:** Test multi-tier application deployments with service accounts
- **AD Replication Study:** Understand domain controller and replication concepts
- **Learning:** Educational resource for Windows Server administration

## Security Notice

⚠️ **This is a lab environment. DO NOT use in production.**

Security considerations for this lab:
- Default passwords are simple and non-changing
- Defender and Windows Update are disabled
- Certificates are self-signed
- All lab data is in plain text
- No encryption or audit logging enforced
- Intended for isolated testing only

## Support & Development

### Project Structure
- Multiple lab configurations available in parent directory
- Shared scripts and configurations
- Modular PowerShell scripts for customization

### Extending the Lab

To add additional users or modify configurations:

1. Edit `scripts/05-prepare-for-ad.ps1`
2. Modify the `$employees` or `$serviceAccounts` arrays
3. Redeploy: `bash stop_and_cleanup.sh && bash deploy.sh`

To add software:

1. Edit `scripts/02-general.ps1`
2. Add applications to the `winget install` command
3. Redeploy the lab

## License

See LICENSE file in the parent repository

## References

- [Windows Server 2025 Documentation](https://docs.microsoft.com/en-us/windows-server/)
- [Active Directory Administration](https://docs.microsoft.com/en-us/windows-server/identity/ad-ds/ad-ds-getting-started)
- [Group Managed Service Accounts](https://docs.microsoft.com/en-us/windows-server/security/group-managed-service-accounts/group-managed-service-accounts-overview)
- [Docker Desktop for Linux](https://docs.docker.com/desktop/install/linux-install/)
