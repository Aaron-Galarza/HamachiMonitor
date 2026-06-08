# Hamachi Monitor

Herramienta de monitoreo y recuperación automática para LogMeIn Hamachi en Windows.

Desarrollada para entornos con múltiples sucursales conectadas por VPN Hamachi, donde la estabilidad del túnel es crítica para la operación.

**by [Aaron Galarza](https://github.com/Aaron-Galarza)**

---

## ¿Qué hace?

- **Watchdog automático**: verifica conectividad cada 30 segundos y reinicia Hamachi si detecta 3 fallos consecutivos
- **Recuperación sin intervención**: el servicio se restaura solo, sin necesidad de que alguien inicie sesión
- **Monitor interactivo** (`audHam`): muestra todas las redes y peers conectados, permite elegir cuál auditar y queda en modo live

---

## Instalación (un solo comando)

Abrí PowerShell como **Administrador** y ejecutá:

```powershell
iex (iwr "https://raw.githubusercontent.com/Aaron-Galarza/hamachi-monitor/main/install.ps1").Content
```

El instalador:
1. Descarga todos los archivos necesarios
2. Crea la tarea programada que corre el watchdog al inicio del sistema
3. Agrega el comando `audHam` al PATH

---

## Uso

En cualquier terminal (CMD o PowerShell):

```
audHam
```

Muestra las redes Hamachi detectadas, te pide elegir cuál monitorear y la IP target, y queda en modo live mostrando el estado cada 30 segundos.

---

## Estructura

```
C:\HamachiMonitor\
├── hamachi_watchdog.ps1   # Watchdog principal (corre como servicio)
├── hamachi_watchdog.log   # Log en tiempo real
└── bin\
    ├── audHam.bat         # Comando global
    └── audHam_runner.ps1  # Lógica del monitor interactivo
```

---

## Requisitos

- Windows 10 / 11 / Server 2019+
- LogMeIn Hamachi instalado (versión gratuita o paga)
- PowerShell 5.1+
- Ejecutar el instalador como Administrador

---

## Log de ejemplo

```
[2026-06-08 15:00:33] [WARN] FALLO 1/3 - sin respuesta de 25.63.123.119.
[2026-06-08 15:01:10] [WARN] FALLO 2/3 - sin respuesta de 25.63.123.119.
[2026-06-08 15:01:47] [WARN] FALLO 3/3 - sin respuesta de 25.63.123.119.
[2026-06-08 15:01:47] [ERROR] CRITICO - 3 fallos consecutivos. Reiniciando Hamachi...
[2026-06-08 15:02:02] [INFO] Servicio reiniciado OK.
[2026-06-08 15:04:12] [INFO] RECUPERADO - ping OK tras reinicio.
```
