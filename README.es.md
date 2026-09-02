# Enterprise Hybrid Cloud & DevOps Lab: Módulos 1 y 2 — Enterprise Linux & Redes Corporativas

[🇺🇸 Read in English](README.md) | [🇪🇸 Leer en Español](README.es.md)

![Linux](https://img.shields.io/badge/SO-Ubuntu%2024.04%20LTS-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)
![Networking](https://img.shields.io/badge/Networking-TCP%203--Way%20Handshake%20%7C%20Enrutamiento%20%7C%20DNS-success?style=for-the-badge&logo=wireshark&logoColor=white)
![Seguridad](https://img.shields.io/badge/Seguridad-Ed25519%20%7C%20UFW%20%7C%20Sudoers-blue?style=for-the-badge&logo=gnubash&logoColor=white)
![Almacenamiento](https://img.shields.io/badge/Almacenamiento-LVM%20Hot--Resize-informational?style=for-the-badge&logo=linux&logoColor=white)
![Init System](https://img.shields.io/badge/Init%20System-Systemd%20%7C%20cgroups-red?style=for-the-badge&logo=linux&logoColor=white)

## 📌 Resumen Ejecutivo y Objetivo Empresarial

En entornos de nube empresarial (Azure, AWS, Kubernetes), la estabilidad y confiabilidad de la infraestructura dependen directamente de la resiliencia del sistema operativo Linux y de los fundamentos de redes a bajo nivel. Más del 80% de las caídas en sistemas distribuidos atribuidas a "errores de aplicación" son causadas en realidad por bucles de enrutamiento, paquetes descartados en firewalls, timeouts de resolución DNS o desajustes en sockets TCP.

Este proyecto implementa un cluster Linux multi-nodo corporativo con direccionamiento estático inmutable, filtrado de paquetes granular, telemetría automatizada y diagnóstico forense de paquetes en tiempo real, preparado para Migración Cloud (Azure) y Gestión de Configuración (Ansible).

---

## 🏗️ Topología de Arquitectura

```
                     RED CORPORATIVA DEL LAB (192.168.204.0/24)
                                         |
             +---------------------------+---------------------------+
             |                                                       |
             v                                                       v
   +--------------------+                                 +--------------------+
   |   srv-control-01   |                                 |    srv-node-01     |
   |   (Ubuntu Server)  |                                 |   (Ubuntu Server)  |
   |                    |                                 |                    |
   | IP: 192.168.204.10 | <==== Protocolo SSH Ed25519 ==> | IP: 192.168.204.11 |
   | Rol: Bastion/Ops   |     (Sin Password / No-Root)    | Rol: Carga/Web     |
   | Enrutamiento: Fijo |                                 | Svc: NGINX (P80)   |
   | IP Forwarding: ON  |                                 | Telemetría: Systemd|
   | UFW: Solo Puerto 22|                                 | UFW: 22, 80, 443   |
   +--------------------+                                 |      9100 (Restr.) |
                                                          | LVM: Expansión 28GB|
                                                          +--------------------+
```

---

## 🛠️ Stack Tecnológico y Decisiones de Ingeniería

| Componente | Tecnología | Justificación de Ingeniería |
| :--- | :--- | :--- |
| **Sistema Operativo** | Ubuntu Server 24.04 LTS | Distribución estándar LTS con soporte de largo plazo en nubes públicas y contenedores. |
| **Capa de Red** | Netplan + `systemd-networkd` | Gestión de red declarativa en YAML; reproducible e inmutable entre reinicios. |
| **Inspección de Paquetes** | `tcpdump` + Filtros BPF | Diagnóstico a nivel de cable para inspección de banderas TCP (`[S]`, `[S.]`, `[.]`, `[P.]`, `[F.]`, `[R.]`). |
| **Resolución DNS** | `bind9-dnsutils` (`dig`) + `systemd-resolved` | Diagnóstico granular de DNS (A, CNAME, TXT, PTR inverso) y medición de latencia en milisegundos. |
| **Enrutamiento Kernel** | `iproute2` (`ip route`) + `sysctl` | Políticas de enrutamiento estático y reenvío de paquetes IPv4 (`net.ipv4.ip_forward = 1`). |
| **Almacenamiento** | LVM2 (Logical Volume Manager) | Expansión dinámica de volúmenes lógicos y redimensionamiento en caliente de `ext4` sin downtime. |
| **Supervisor de Servicios** | Systemd (PID 1) + cgroups | Control de ciclo de vida de procesos, autorecuperación ante fallos (`SIGKILL`) y aislamiento de recursos. |
| **Seguridad y Acceso** | OpenSSH + Curva Elíptica Ed25519 | Criptografía asimétrica de alto rendimiento y mitigación total de fuerza bruta (`PasswordAuthentication no`). |
| **Seguridad de Red** | UFW (Uncomplicated Firewall) | Filtrado de paquetes con política `Default Deny` y listas blancas por IP de origen (Source IP Whitelisting). |

---

## 🚀 Implementación Técnica Paso a Paso

### 1. Arquitectura de Red Estática y DNS Local
* `srv-control-01`: `192.168.204.10/24` (Gateway: `192.168.204.2`)
* `srv-node-01`: `192.168.204.11/24` (Gateway: `192.168.204.2`)
* Resolución local configurada en `/etc/hosts` para desacoplar scripts de automatización de IPs fijas.

### 2. Inspección Forense: El 3-Way Handshake de TCP
Captura y análisis de paquetes con filtros BPF:
```bash
sudo tcpdump -ni ens33 'tcp port 80 and host 192.168.204.10' -c 15
```
* **Fase 1: Handshake:** `Flags [S]` (SYN) $\rightarrow$ `Flags [S.]` (SYN-ACK) $\rightarrow$ `Flags [.]` (ACK).
* **Fase 2: Intercambio L7:** `Flags [P.]` (`HTTP GET /`) $\rightarrow$ `Flags [P.]` (`HTTP 200 OK`).
* **Fase 3: Cierre Elegante (Teardown):** `Flags [F.]` (FIN) $\rightarrow$ `Flags [F.]` (FIN) $\rightarrow$ `Flags [.]` (ACK).
* **Connection Refused vs Timed Out:** Documentación de cómo puertos cerrados generan respuesta inmediata `Flags [R.]` (RST-ACK) vs bloqueos de Firewall (DROP) que causan retransmisiones y timeout.

### 3. Diagnóstico Avanzado de DNS
* Auditoría de registros `A` y distribución Anycast Round-Robin con `dig google.com`.
* Validación de registros de verificación Cloud con `dig github.com TXT +short`.
* Resolución inversa (`PTR`) sobre `8.8.8.8` apuntando a `dns.google.`.

### 4. Enrutamiento del Kernel e IP Forwarding
* Inyección de rutas estáticas corporativas: `sudo ip route add 10.50.0.0/16 via 192.168.204.2 dev ens33`.
* Verificación de la tabla de enrutamiento con `ip route get 10.50.15.20`.
* Activación persistente de reenvío de paquetes IPv4 para roles de Router/Kubernetes:
  ```bash
  # /etc/sysctl.d/99-ip-forward.conf
  net.ipv4.ip_forward = 1
  ```

### 5. Hardening SSH Criptográfico y Sudoers
* Despliegue de llaves Ed25519 sin contraseña entre nodos.
* Hardening con `/etc/ssh/sshd_config.d/99-hardening.conf` (`PasswordAuthentication no`, `PermitRootLogin no`).
* Escalamiento de privilegios en `/etc/sudoers.d/devops` (`NOPASSWD:ALL`).

### 6. Elasticidad de Almacenamiento y Servicios Resilientes
* Expansión en caliente del volumen raíz de 14GB a 28GB mediante `lvextend -l +100%FREE ... -r`.
* Despliegue de agente en `/opt/infra-agent/agent.sh` con autorecuperación ante señales `SIGKILL (-9)`.

---

## 🔍 Bitácora de Incidentes y Troubleshooting Resuelto

| Incidente / Síntoma | Análisis de Causa Raíz (RCA) | Solución de Ingeniería |
| :--- | :--- | :--- |
| **`Connection refused` en puerto 80** | Puerto abierto en UFW pero sin servicio escuchando; el kernel respondió con TCP RST-ACK. | Instalación y activación del demonio NGINX (`systemctl enable --now nginx`). |
| **`WARNING: Permissions for Netplan are too open`** | Archivo creado con máscara `0644` legible por usuarios no privilegiados. | Aplicación de permisos POSIX estrictos `chmod 600 /etc/netplan/*.yaml`. |
| **`Host key verification failed` en SSH** | El cliente SSH requería confirmación interactiva para registrar la huella en `known_hosts`. | Validación explícita de autenticidad e incorporación de la clave a `~/.ssh/known_hosts`. |
| **`-bash: !/bin/bash: event not found`** | La terminal interactiva activó la expansión de historial de Bash por el carácter `!`. | Migración al patrón `sudo tee /ruta <<'EOF'` con comillas simples literales. |

---

## 📂 Estructura del Repositorio

```
enterprise-linux-networking-lab/
├── README.md               # Documentación en Inglés
├── README.es.md            # Documentación en Español
├── .gitignore
├── configs/
│   ├── 99-hardening.conf
│   ├── 99-ip-forward.conf
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

## 🎯 Próximo Hito: Módulo 3
Avanzamos a **Microsoft Azure Enterprise Infrastructure**: Resource Groups, VNets, Subnets, NSGs, Azure Virtual Machines, Storage Accounts, Load Balancers y mejores prácticas del Well-Architected Framework.
