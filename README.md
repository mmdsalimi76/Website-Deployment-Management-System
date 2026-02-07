# 🚀 Website Deployment & Management System

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg?style=flat-square&logo=powershell)](https://microsoft.com/powershell)
[![Docker](https://img.shields.io/badge/Docker-Enabled-blue.svg?style=flat-square&logo=docker)](https://www.docker.com/)
[![Django](https://img.shields.io/badge/Framework-Django-green.svg?style=flat-square&logo=django)](https://www.djangoproject.com/)
[![PostgreSQL](https://img.shields.io/badge/Database-PostgreSQL-blue.svg?style=flat-square&logo=postgresql)](https://www.postgresql.org/)

A robust, PowerShell-based automation suite designed to bridge the gap between local development and production VPS environments. This system provides a centralized dashboard for deployment, synchronization, and administrative tasks using Docker Compose.

---

## 📖 Table of Contents
- [Overview](#-overview)
- [Key Features](#-key-features)
- [Supported Stacks](#-supported-stacks)
- [Configuration Guide](#-configuration-guide)
- [System Flow & Logic](#-system-flow--logic)
- [Directory Structure](#-directory-structure)
- [Prerequisites](#-prerequisites)

---

## 🌟 Overview
The **Website Deployment & Management System** is built to ensure that code updates, database migrations, and infrastructure changes are handled safely and consistently. It provides a user-friendly interface to manage complex remote operations without manual SSH command overhead.

This project is specifically built for developers who can't access GitHub workflows or pipelines due to network restrictions.

### 🎯 Who should use it
- **Developers**: For rapid updates and patching of the production environment.
- **System Administrators**: For maintaining system health, database backups, and configuration.
- **DevOps Engineers**: For managing the end-to-end deployment pipeline.

## ✨ Key Features
- **🔄 Full Production Sync**: Mirrors the entire local project to the VPS and restarts services atomically.
- **🔪 Surgical Patching**: Selectively update specific files (hot-swap) without a full sync—ideal for rapid fixes.
- **💾 Database Lifecycle**: Automated backups, restores, and Django migrations with MD5 integrity verification.
- **🐳 Docker Orchestration**: Remote management of container builds, status checks, and health monitoring.
- **📦 Infrastructure Management**: Handles Docker image "sideloading" (transferring images as files) for restricted environments.
- **🖥️ VPS Control**: Quick terminal access and real-time log streaming for managed services.

## 🐍 Supported Stacks
While highly flexible due to its Docker-centric design, the system features specialized automation for:

- **Django**: Automatic migrations and logic-aware patching for `.py` files.
- **PostgreSQL**: Hardcoded backup/restore utilities using `pg_dump` and `psql` commands. Automated safety gates are specifically designed for Postgres containers.
- **Generic Docker**: Support for any service (Redis, Nginx, Node.js, etc.) defined in your `docker-compose.yml`. Log streaming and container management work universally.

---

## 🛠️ Configuration Guide
Before your first run, the system must be configured via the **Configuration Manager**.

### 1. Initial Launch
Run `AppLauncher.bat` or `master_interface.ps1` to open the Master Control Center. Select **Option [2] Configuration Manager**.

### 2. Essential Settings
The manager updates JSON files for Global, Database, and Docker settings:

| Category | Field | Description |
| :--- | :--- | :--- |
| **Global** | `VPS IP` | Public IP address of your remote server. |
| **Global** | `VPS User` | SSH username (usually `root`). |
| **Global** | `VPS Password` | SSH password (stored locally in `global_config.json`). |
| **Global** | `Local Root` | Absolute path to the project on your local machine. |
| **Docker** | `Compose File` | Production compose filename (e.g., `docker-compose.yml`). |
| **Database** | `DB Container` | Name of the PostgreSQL container. |

### 🚩 The FIRST_DEPLOY Flag
Toggled via the Config Manager (shortcut `f`):
- **Set to `True`**: For initial setups where the DB container isn't fully healthy yet. Skips certain pre-flight checks.
- **Set to `False` (Default)**: Normal mode with full safety gates active.

> [!TIP]
> Use **Option [6]** in the Config Manager to define **Sync Ignore Patterns** (e.g., `.git`, `node_modules`, `.env`) to keep transfers fast and secure.

---

## 📂 System Flow & Logic

### 🏗️ Entry Point: `master_interface.ps1`
The central dashboard providing a live view of your configuration. It acts as a wrapper, ensuring all sub-scripts execute in the correct environment with the latest settings.

### 🚀 Full Deployment: `orchestration/deploy_master.ps1`
The automated production pipeline follows this sequence:
1. **Validation**: Checks connectivity and tool availability.
2. **Safety Backup**: Triggers a database backup on the VPS before any changes.
3. **Production Sync**: Mirrors the project directory via `sync_orchestrator.ps1`.
4. **Container Build**: Triggers remote builds and service starts via `build_containers.ps1`.
5. **Health Check**: Monitors containers for 2 minutes to ensure stability.
6. **Migrations**: Runs final database migrations to sync schema changes.

### ⚡ Surgical Patching: `sync/selective_patch.ps1`
For rapid hotfixes without a full redeploy:
1. **Scan**: Indexes project files, excluding ignored patterns.
2. **Select**: Opens a GUI (`Out-GridView`) for the user to pick specific files.
3. **Transfer**: Compresses selection into ZIP, transfers via SCP, and extracts on VPS.
4. **Hot-Swap**: Prompts to rebuild only affected services.
5. **Rollback**: Offers DB rollback if rebuild fails and logic changes were detected.

### 🗄️ Database Management: `database/database_manager.ps1`
- **Backups**: Uses `pg_dump` inside the container to create compressed SQL files.
- **Integrity**: Uses MD5 hashing to verify backups transferred to local storage.
- **Restoration**: Lists remote backups and allows one-click restoration via `psql`.

### 🐳 Docker Management: `docker-compose/compose_manager.ps1`
Remote execution of `docker compose` commands (Up, Down, Build, Status) over SSH with built-in health monitoring and log viewing.

### �️ Container Entrypoint: `entrypoint.sh`
The operational manager for your Docker containers that handles:
- **Database Readiness**: Waits for the PostgreSQL port to be open before starting the app.
- **Role Routing**: Dynamically starts the Web server, Celery workers, or migrations based on container command.
- **Cleanup**: Removes stale PID files and prepares the environment for production.

### �🖥️ VPS & Infrastructure: `vps management/vps_manager.ps1`
- **Terminal**: Opens a direct SSH session using `plink.exe`.
- **Logs**: Streams logs from services defined in `vps_config.json`.
- **Sideloading**: `infrastructure/sideload_images.ps1` allows saving images locally, transferring them, and loading them on the VPS to bypass registry restrictions.

---

## 📁 Directory Structure
- `backups/`: Local storage for database dumps pulled from VPS.
- `bin/`: External tools (`plink.exe`, `pscp.exe`).
- `database/`: Database scripts and configuration.
- `docker-compose/`: Container management logic.
- `infrastructure/`: Image transfer and setup tools.
- `orchestration/`: Deployment and config managers.
- `sync/`: Synchronization and patching logic.
- `vps management/`: VPS interaction and log tools.

## 📋 Prerequisites
- **Local**: Windows with PowerShell 5.1+.
- **Tools**: Putty tools (`plink`, `pscp`) must be in the `bin/` folder.
- **Remote**: VPS with SSH access, Docker, and Docker Compose installed.

---
*Created for efficient VPS management and automated deployment pipelines.*
