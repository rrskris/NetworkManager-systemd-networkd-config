# NetworkManager-systemd-networkd-config

# systemd-networkd-config

Production-grade migration script for transitioning RedHat-based systems and EKS worker nodes from NetworkManager to systemd-networkd with DNS stub listener disabling for CoreDNS compatibility.

## Overview

This repository contains a comprehensive bash script for migrating to systemd-networkd and disabling DNS Stub listeners, essential for:

- **EKS 1.30+ worker nodes** - Ensures CoreDNS compatibility
- **Rocky Linux** - Modern RedHat-based distributions
- **AlmaLinux** - Community-driven RHEL alternative
- **Any RedHat family server** - Requiring modern network stack management

## Features

* Automatic primary interface detection  
* Cloud-init network config lockdown  
* systemd-networkd DHCP configuration  
* DNS stub listener disabling for CoreDNS  
* NetworkManager decommissioning  
* Legacy artifact cleanup  
* Production validation suite with 4 critical checks  

## Usage

```bash
chmod +x eks-production-ami-prep.sh
sudo ./eks-production-ami-prep.sh
```

## Production Validation Suite

The script includes 4 critical validation checks:

1. **Interface Status Check** - Ensures systemd-networkd is managing the interface
2. **DNS Stub Listener Check** - Verifies 127.0.0.53:53 is NOT listening (prevents CoreDNS conflicts)
3. **resolv.conf Symlink Check** - Confirms proper linking to systemd-resolved uplink
4. **DNS Resolution Functional Check** - Validates nameserver configuration

## Prerequisites

- Root/sudo access
- systemd-based Linux system (Rocky, AlmaLinux, RHEL, etc.)
- For EKS: Running on an EC2 instance

## Script Workflow

### Configuration Steps

1. **Disable cloud-init network management** - Prevents conflicts during boot
2. **Configure systemd-networkd** - Sets up DHCP with proper metrics
3. **Disable DNS stub listener** - Removes 127.0.0.53 listener
4. **Link resolv.conf** - Points to systemd-resolved uplink
5. **Decommission NetworkManager** - Stops and masks NetworkManager services
6. **Clean legacy artifacts** - Removes old network config files
7. **Activate new network stack** - Enables and starts systemd-networkd

## Author

**Vamshi Krishna Santhapuri**

## Compliance

- EKS 1.30+
- Production Grade
- CoreDNS compatible

## Safety Notes

! This script makes system-level network changes. Test in non-production environments first.  
! Ensure you have remote access/console access before running on remote systems.  
! The script uses `set -euo pipefail` to exit on errors.

## License

MIT
