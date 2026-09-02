# Enterprise Hybrid Cloud & DevOps Lab: Module 1 — Enterprise Linux & Systems Administration

[🇺🇸 Read in English](README.md) | [🇪🇸 Leer en Español](README.es.md)

![Linux](https://img.shields.io/badge/OS-Ubuntu%2024.04%20LTS-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)
![Security](https://img.shields.io/badge/Security-Ed25519%20%7C%20UFW%20%7C%20Sudoers-blue?style=for-the-badge&logo=gnubash&logoColor=white)
![Storage](https://img.shields.io/badge/Storage-LVM%20Hot--Resize-informational?style=for-the-badge&logo=linux&logoColor=white)
![Init System](https://img.shields.io/badge/Init%20System-Systemd%20%7C%20cgroups-red?style=for-the-badge&logo=linux&logoColor=white)

## 📌 Executive Summary & Business Objective

In modern cloud and distributed architectures (Azure, AWS, Kubernetes), infrastructure stability relies directly on the resilience and security of the underlying Linux operating system. Misconfigurations in static routing, unmanaged background processes, rigid partition layouts, and permissive SSH policies represent major security risks and cause costly production outages.

This project implements a hardened, multi-node enterprise Linux cluster simulating an on-premise infrastructure environment ready for cloud automation, configuration management (Ansible), and container orchestration.

---

## 🏗️ Architecture Topology

```
                         CORPORATE LAB NETWORK (192.168.204.0/24)
                                            |
                +---------------------------+---------------------------+
                |                                                       |
                v                                                       v
      +--------------------+                                 +--------------------+
      |   srv-control-01   |                                 |    srv-node-01     |
      |   (Ubuntu Server)  |                                 |   (Ubuntu Server)  |
      |                    |                                 |                    |
      | IP: 192.168.204.10 | <==== Ed25519 SSH Protocol ===> | IP: 192.168.204.11 |
      | Role: Bastion/Ops  |      (Passwordless / No-Root)   | Role: Workload/App |
      | UFW: Port 22 Only  |                                 | UFW: 22, 80, 443   |
      +--------------------+                                 |      9100 (IP-Restricted)
                                                             | LVM: Online 28GB Resize
                                                             | Svc: infra-agent.service
                                                             +--------------------+
```

---

## 🛠️ Technology Stack & Engineering Decisions

| Component | Technology | Enterprise Rationale |
| :--- | :--- | :--- |
| **Operating System** | Ubuntu Server 24.04 LTS | Standard long-term support distribution across cloud vendors and container hosts. |
| **Networking Layer** | Netplan + `systemd-networkd` | Declarative YAML-based network management; reproducible and deterministic across boots. |
| **Storage Management** | LVM2 (Logical Volume Manager) | Dynamic volume expansion and zero-downtime online filesystem resizing (`ext4`). |
| **Service Supervisor** | Systemd (PID 1) + cgroups | Process lifecycle management, automatic recovery on failure (`SIGKILL`), and CPU/RAM isolation. |
| **Security & Access** | OpenSSH + Ed25519 Elliptic Curve | High-performance asymmetric cryptography; brute-force mitigation (`PasswordAuthentication no`). |
| **Privilege Delegation** | `/etc/sudoers.d/` (`NOPASSWD`) | Secure granular privilege delegation for desattended automation pipelines (Ansible / CI/CD). |
| **Network Security** | UFW (Uncomplicated Firewall) | Stateful packet filtering with strict `Default Deny` and Source IP Whitelisting for metrics. |
| **Observability** | `journalctl` (RFC 5424) + Cron | Indexed binary system logging, streaming tails, and scheduled health auditing. |

---

## 🚀 Step-by-Step Implementation & Runbook

### 1. Static Network Architecture (`Netplan`)
Static IPs were assigned to eliminate DHCP lease expiration risks:
* `srv-control-01`: `192.168.204.10/24` (Gateway: `192.168.204.2`)
* `srv-node-01`: `192.168.204.11/24` (Gateway: `192.168.204.2`)
* Permissions secured to `chmod 600 /etc/netplan/*.yaml` to prevent sensitive network configuration disclosure.

### 2. Cryptographic SSH Handshake & Hardening
1. Generated Ed25519 keypair on control node:
   ```bash
   ssh-keygen -t ed25519 -N "" -C "devops@srv-control-01" -f ~/.ssh/id_ed25519
   ```
2. Exported public key to target node via `ssh-copy-id`.
3. Applied security hardening in `/etc/ssh/sshd_config.d/99-hardening.conf`:
   * `PasswordAuthentication no`
   * `PermitRootLogin no`
   * `PubkeyAuthentication yes`

### 3. Granular Sudoers Configuration for Automation
Configured non-interactive privilege escalation for Ansible/Terraform compatibility:
```bash
devops ALL=(ALL) NOPASSWD:ALL
# Permissions set to chmod 440
```

### 4. Custom Resilient Telemetry Service (`systemd`)
Developed and deployed an infrastructure health agent at `/opt/infra-agent/agent.sh` supervised by `/etc/systemd/system/infra-agent.service`:
* **Auto-recovery policy:** `Restart=always` with `RestartSec=3s`.
* **Chaos Engineering Test:** Evaluated resilience under `sudo kill -9 $(pgrep -f agent.sh)`. Systemd successfully detected the process destruction and resurrected the service with a new PID within 3 seconds.

### 5. Hot Storage Expansion (LVM Online Resize)
Resolved low-disk capacity by expanding the root logical volume in real-time without unmounting or rebooting:
```bash
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv -r
```
* **Result:** Expanded `/` filesystem from **14 GB** to **28 GB** online (`resize2fs` adjusted ext4 superblock live).

### 6. Perimeter Defense & Port Hardening (`UFW`)
* **Default Policies:** `default deny incoming`, `default allow outgoing`.
* **Standard Rules:** Port 22 (SSH), 80 (HTTP), 443 (HTTPS).
* **Enterprise Whitelisting:** Metric Port `9100/tcp` restricted strictly to `192.168.204.10` (Control Node).

### 7. Automated Node Healthcheck & Telemetry Audit (Cron)
Implemented periodic node monitoring script at `/usr/local/bin/infra-healthcheck.sh` scheduled via `/etc/cron.d/infra-healthcheck` every 2 minutes, outputting structured audits to `/var/log/infra-health.log`.

---

## 🔍 Incident Simulation & Troubleshooting Log

| Incident / Symptom | Root Cause Analysis (RCA) | Engineering Solution |
| :--- | :--- | :--- |
| **`WARNING: Permissions for Netplan are too open`** | File created with default `0644` mask allowing read access to other unprivileged users. | Enforced strict POSIX octal permission `chmod 600 /etc/netplan/*.yaml`. |
| **`Host key verification failed` on SSH copy** | SSH client requires interactive confirmation to append host fingerprint to `known_hosts`. | Explicitly validated authenticity and accepted host key into `~/.ssh/known_hosts`. |
| **SSH Key generated in incorrect user context** | Session was running as `root`, placing keys in `/root/.ssh` (`0700`) unreadable by `devops`. | Regressed to unprivileged `devops` context and generated keypair inside `/home/devops/.ssh`. |
| **`-bash: !/bin/bash: event not found`** | Interactive Bash history expansion triggered by `!` inside double-quoted string. | Migrated to non-interpolated `sudo tee /path <<'EOF'` pattern. |

---

## 📂 Repository Structure

```
enterprise-linux-networking-lab/
├── README.md
├── .gitignore
├── configs/
│   ├── 99-hardening.conf
│   ├── cron-infra-healthcheck
│   ├── netplan-control.yaml
│   ├── netplan-node.yaml
│   └── sudoers-devops
├── scripts/
│   ├── agent.sh
│   └── healthcheck.sh
└── systemd/
    └── infra-agent.service
```

---

## 🎯 Next Roadmap Milestone: Module 2
Advancing to **Corporate Networking & Git/GitHub Workflows**: Deep packet analysis with `tcpdump`, Wireshark capture, routing tables, and production Git branching strategies.
