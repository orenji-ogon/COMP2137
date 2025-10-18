# Travel-Ready Docker Lab

This project sets up a portable Docker lab environment with persistent storage, lifecycle management scripts, and GitHub-ready documentation.

## Project Structure

```
docker-starter-pack/
├── docker-compose.yml
├── README.md
├── .env.example
├── .gitignore
├── scripts/
├── mysql/init/
└── kali/
    ├── Dockerfile
    └── init/
```

## Goal

- Kali container (`cloud-ops`) with persistent `/root` via named volume.
- MySQL container with persistent `/var/lib/mysql`.
- Helper scripts for lifecycle, snapshots, backup/restore.
- GitHub-ready README for easy onboarding.

## Setup Instructions

1. Clone the repo:
   ```bash
   git clone https://github.com/your-username/docker-starter-pack.git
   cd docker-starter-pack
   ```

2. Copy and configure environment variables:
   ```bash
   cp .env.example .env
   # Edit .env with your preferred settings
   ```

3. Start the lab:
   ```bash
   docker-compose up -d
   ```

## Volume Persistence

- Kali container persists `/root` using a named volume `kali-root-vol`.
- MySQL container persists `/var/lib/mysql` using `mysql-data-vol`.

## Lifecycle Scripts

Located in `scripts/`:

- `start.sh` – Start containers
- `stop.sh` – Stop containers
- `snapshot.sh` – Create snapshots
- `backup.sh` – Backup volumes
- `restore.sh` – Restore from backup

## Snapshots & Backup
- Snapshots are stored in `snapshots/`.
- Backups are stored in `backups/`.
- Use `scripts/backup.sh` and `scripts/restore.sh` to manage data.

## Container Naming Convention

- Kali: `cloud-ops`
- MySQL: `mysql-db`

## Environment Variables

Defined in `.env.example`:

```
MYSQL_ROOT_PASSWORD=yourpassword
MYSQL_DATABASE=yourdb
MYSQL_USER=youruser
MYSQL_PASSWORD=yourpassword
```

## GitHub Best Practices

- Use `.gitignore` to exclude sensitive files and volumes.
- Keep `README.md` updated with setup and usage instructions.
- Include `LICENSE` and `CONTRIBUTING.md` if open-sourcing.

Built to be travel-ready and reproducible.
