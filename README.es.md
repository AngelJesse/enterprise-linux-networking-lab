# Enterprise Hybrid Cloud & DevOps Lab: Módulo 1 — Enterprise Linux & Administración de Sistemas

[🇺🇸 Read in English](README.md) | [🇪🇸 Leer en Español](README.es.md)

![Linux](https://img.shields.io/badge/SO-Ubuntu%2024.04%20LTS-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)
![Seguridad](https://img.shields.io/badge/Seguridad-Ed25519%20%7C%20UFW%20%7C%20Sudoers-blue?style=for-the-badge&logo=gnubash&logoColor=white)
![Almacenamiento](https://img.shields.io/badge/Almacenamiento-LVM%20Hot--Resize-informational?style=for-the-badge&logo=linux&logoColor=white)
![Init System](https://img.shields.io/badge/Init%20System-Systemd%20%7C%20cgroups-red?style=for-the-badge&logo=linux&logoColor=white)

## 📌 Resumen Ejecutivo y Objetivo Empresarial

En arquitecturas distribuidas y entornos de nube modernos (Azure, AWS, Kubernetes), la estabilidad de la infraestructura depende directamente de la resiliencia y seguridad del sistema operativo Linux subyacente. Los errores comunes como direccionamiento IP dinámico en servidores, procesos en segundo plano no supervisados, esquemas de particionado rígidos y accesos SSH por contraseña representan graves vectores de vulnerabilidad y caídas operativas de alto costo.

Este proyecto implementa un cluster Linux multi-nodo empresarial (Ubuntu Server) con hardening de seguridad, simulando una infraestructura on-premise corporativa lista para automatización con Ansible, despliegue con Terraform y orquestación con Kubernetes.

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
   | Rol: Bastion/Ops   |     (Sin Password / No-Root)    | Rol: Carga/Apps    |
   | UFW: Solo Puerto 22|                                 | UFW: 22, 80, 443   |
   +--------------------+                                 |      9100 (IP Restringida)
                                                          | LVM: Expansión 28GB Hot
                                                          | Svc: infra-agent.service
                                                          +--------------------+
```

---

## 🛠️ Stack Tecnológico y Decisiones de Ingeniería

| Componente | Tecnología | Justificación de Ingeniería |
| :--- | :--- | :--- |
| **Sistema Operativo** | Ubuntu Server 24.04 LTS | Distribución estándar LTS con amplio soporte en nubes públicas y hosts de contenedores. |
| **Capa de Red** | Netplan + `systemd-networkd` | Gestión de red declarativa en YAML; reproducible, inmutable y determinista. |
| **Almacenamiento** | LVM2 (Logical Volume Manager) | Expansión dinámica de volúmenes lógicos y redimensionamiento en caliente de `ext4` sin downtime. |
| **Supervisor de Servicios** | Systemd (PID 1) + cgroups | Control del ciclo de vida de procesos, autorecuperación ante fallos (`SIGKILL`) y aislamiento de recursos. |
| **Seguridad y Acceso** | OpenSSH + Curva Elíptica Ed25519 | Criptografía asimétrica de alto rendimiento y mitigación total de ataques de fuerza bruta (`PasswordAuthentication no`). |
| **Delegación de Privilegios** | `/etc/sudoers.d/` (`NOPASSWD`) | Delegación granular para permitir automatización desatendida mediante Ansible y pipelines de CI/CD. |
| **Seguridad de Red** | UFW (Uncomplicated Firewall) | Filtrado de paquetes con política `Default Deny` y listas blancas por IP de origen (Source IP Whitelisting). |
| **Observabilidad** | `journalctl` (RFC 5424) + Cron | Logs estructurados binarios de alta velocidad, streaming en vivo y auditorías de salud programadas. |

---

## 🚀 Implementación Técnica Paso a Paso

### 1. Arquitectura de Red Estática (`Netplan`)
Se configuraron direcciones IP estáticas fijas para eliminar riesgos de expiración de leases por DHCP:
* `srv-control-01`: `192.168.204.10/24` (Gateway: `192.168.204.2`)
* `srv-node-01`: `192.168.204.11/24` (Gateway: `192.168.204.2`)
* Permisos asegurados con `chmod 600 /etc/netplan/*.yaml` para prevenir exposición de configuraciones de red.

### 2. Enlace Criptográfico SSH y Hardening
1. Generación del par de llaves Ed25519 en el nodo de control:
   ```bash
   ssh-keygen -t ed25519 -N "" -C "devops@srv-control-01" -f ~/.ssh/id_ed25519
   ```
2. Distribución de la llave pública al nodo de destino mediante `ssh-copy-id`.
3. Aplicación de políticas de hardening en `/etc/ssh/sshd_config.d/99-hardening.conf`:
   * `PasswordAuthentication no`
   * `PermitRootLogin no`
   * `PubkeyAuthentication yes`

### 3. Configuración de Sudoers Granular para Automatización
Configuración de escalamiento de privilegios no interactivo para compatibilidad con Ansible/Terraform:
```bash
devops ALL=(ALL) NOPASSWD:ALL
# Permisos asignados: chmod 440
```

### 4. Servicio de Telemetría Resiliente (`systemd`)
Despliegue de un agente de monitoreo en `/opt/infra-agent/agent.sh` supervisado por `/etc/systemd/system/infra-agent.service`:
* **Política de autorecuperación:** `Restart=always` con `RestartSec=3s`.
* **Prueba de Chaos Engineering:** Se evaluó la resiliencia matando el proceso violentamente con `sudo kill -9 $(pgrep -f agent.sh)`. Systemd detectó la destrucción del proceso y lo reinició automáticamente con un nuevo PID en menos de 3 segundos.

### 5. Expansión de Almacenamiento en Caliente (LVM Online Resize)
Resolución de alertas de capacidad extendiendo el volumen lógico raíz en tiempo real sin desmontar el sistema de archivos ni reiniciar:
```bash
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv -r
```
* **Resultado:** El sistema de archivos `/` pasó de **14 GB** a **28 GB** en caliente (`resize2fs` ajustó los superbloques e inodos de `ext4` en vivo).

### 6. Defensa Perimetral y Control de Puertos (`UFW`)
* **Políticas por defecto:** `default deny incoming`, `default allow outgoing`.
* **Reglas públicas estándar:** Puerto 22 (SSH), 80 (HTTP), 443 (HTTPS).
* **Regla Enterprise:** Puerto de métricas `9100/tcp` restringido exclusivamente a la IP de gestión `192.168.204.10`.

### 7. Auditoría Automatizada de Salud del Nodo (Cron)
Implementación de un script de auditoría periódica en `/usr/local/bin/infra-healthcheck.sh` programado en `/etc/cron.d/infra-healthcheck` cada 2 minutos, generando reportes estructurados en `/var/log/infra-health.log`.

---

## 🔍 Bitácora de Incidentes y Troubleshooting Resuelto

| Incidente / Síntoma | Análisis de Causa Raíz (RCA) | Solución de Ingeniería |
| :--- | :--- | :--- |
| **`WARNING: Permissions for Netplan are too open`** | Archivo creado con máscara por defecto `0644` legible por usuarios no privilegiados. | Aplicación de permisos POSIX estrictos `chmod 600 /etc/netplan/*.yaml`. |
| **`Host key verification failed` en SSH** | El cliente SSH requería confirmación interactiva para registrar la huella en `known_hosts`. | Validación explícita de autenticidad e incorporación de la clave a `~/.ssh/known_hosts`. |
| **Llave SSH generada en usuario incorrecto** | Sesión ejecutada como `root`, ubicando llaves en `/root/.ssh` (`0700`) inaccesible para `devops`. | Retorno al contexto de usuario `devops` y regeneración en `/home/devops/.ssh`. |
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

## 🎯 Próximo Hito: Módulo 2
Avanzamos a **Corporate Networking & Flujos GitOps**: Captura y análisis de paquetes con `tcpdump`, Wireshark, tablas de enrutamiento y estrategias de ramas en Git.
