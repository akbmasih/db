# Lingudesk DB Server Documentation

## Overview
Centralized database server for Lingudesk v15, providing PostgreSQL, MinIO object storage, Redis caching, and connection pooling through PgBouncer.

## Architecture

```
DB Server (10.0.0.5)
├── PostgreSQL 15 (Port 5432)
│   ├── 6 Schemas (public, auth, credit, ai, content, audit)
│   ├── Row-Level Security
│   └── Automated Backups
├── PgBouncer (Port 6432)
│   └── Connection Pooling
├── MinIO (Ports 9000, 9001)
│   ├── Object Storage
│   └── S3-Compatible API
└── Redis 7 (Port 6379)
    ├── Caching Layer
    └── Rate Limiting Store
```

## Quick Start

### Prerequisites
- Docker Engine 24.0+
- Docker Compose 2.20+
- 4GB RAM minimum (8GB recommended)
- 50GB disk space minimum

### Installation

```bash
# Clone or copy the db directory to your server
cd /opt/lingudesk/db

# Run the setup script
chmod +x setup.sh
./setup.sh

# Or manual setup:
docker compose up -d
```

## Configuration

### Environment Variables (.env)
```bash
# PostgreSQL
POSTGRES_DB=lingudesk
POSTGRES_USER=postgres
POSTGRES_PASSWORD=<generated>
DB_USER=db_user
DB_PASSWORD=<generated>

# MinIO
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=<generated>

# Redis
REDIS_PASSWORD=<generated>
REDIS_MAXMEMORY=2gb
```

### Database Schemas

| Schema  | Purpose | Tables |
|---------|---------|--------|
| public  | Shared core data | users, routing_rules, products |
| auth    | Authentication | credentials, refresh_tokens, oauth_accounts |
| credit  | Financial data | balances, transactions, subscriptions |
| ai      | AI caching | cache_entries, usage_logs, plugin_configs |
| content | User content | decks, cards, review_logs, languages |
| audit   | Logging | logs (partitioned by month) |

### Service Ports

| Service | Internal Port | External Port | Purpose |
|---------|--------------|---------------|---------|
| PostgreSQL | 5432 | 5432 | Primary database |
| PgBouncer | 6432 | 6432 | Connection pooling |
| MinIO API | 9000 | 9000 | S3 API endpoint |
| MinIO Console | 9001 | 9001 | Web management UI |
| Redis | 6379 | 6379 | Caching & rate limiting |

## Operations

### Health Check
```bash
./monitoring/health-check.sh
```

### Backup
```bash
# Manual backup
./backup/backup.sh

# Automated backups run daily at 3 AM
# Configured via BACKUP_SCHEDULE in .env
```

### Restore
```bash
# List available backups
./backup/restore.sh -l

# Restore from specific date
./backup/restore.sh -d 20250120

# Restore specific file
./backup/restore.sh -f /backup/lingudesk_backup_20250120_030000.sql.gz
```

### Container Management
```bash
# View logs
docker compose logs -f [service_name]

# Restart a service
docker compose restart postgres

# Stop all services
docker compose down

# Remove all data (CAUTION!)
docker compose down -v
```

## MinIO Buckets

| Bucket | Purpose | Policy |
|--------|---------|--------|
| media | User uploads (images, audio) | Public read |
| ai-cache | AI generated content | Private |
| backups | Database backups | Private |
| temp | Temporary files (24h TTL) | Private |
| static | Static assets | Public read |

### Access MinIO Console
1. Navigate to http://localhost:9001
2. Login with credentials from .env file
3. Manage buckets, users, and policies

## Redis Usage

### Key Patterns
```
rate_limit:user:{user_id}          # User rate limiting
rate_limit:ip:{ip_address}         # IP rate limiting
session:{session_id}                # User sessions
cache:query:{query_hash}           # Query cache
queue:ai:{plugin_name}              # AI processing queues
stats:realtime:{metric_name}        # Real-time statistics
```

### Memory Management
- Max memory: 2GB (configurable)
- Eviction policy: allkeys-lru
- Persistence: RDB snapshots + AOF

## PgBouncer Configuration

### Pool Modes
- **transaction** (default): For web applications
- **session**: For admin connections
- **statement**: For simple queries only

### Connection Pools
```
lingudesk_auth     - Pool size: 20
lingudesk_credit   - Pool size: 15
lingudesk_ai       - Pool size: 25
lingudesk_content  - Pool size: 30
lingudesk_audit    - Pool size: 10
lingudesk_admin    - Pool size: 5 (session mode)
```

## Performance Tuning

### PostgreSQL Optimization
- Shared buffers: 256MB
- Effective cache size: 1GB
- Max connections: 200
- Work memory: 4MB per operation

### System Parameters
```bash
# Required for optimal performance
sudo sysctl -w vm.max_map_count=262144
sudo sysctl -w vm.overcommit_memory=1
```

## Security

### Network Security
- All services bound to internal network only
- No external access except through Backend server
- TLS encryption for production (Tailscale)

### Database Security
- Row-Level Security (RLS) enabled
- User isolation by user_id
- Encrypted sensitive fields
- Regular password rotation

### Backup Security
- Encrypted backups in production
- Retention policy: 7 days default
- Off-site backup to MinIO

## Monitoring

### Metrics Available
- PostgreSQL: connections, size, query performance
- Redis: memory usage, key count, hit rate
- MinIO: bucket usage, request rate
- System: CPU, memory, disk usage

### Alerting Thresholds
- Disk usage > 80%
- Memory usage > 90%
- Failed backups
- Service down > 5 minutes

## Troubleshooting

### Common Issues

#### PostgreSQL Connection Refused
```bash
# Check if container is running
docker ps | grep postgres

# Check logs
docker logs lingudesk_postgres

# Verify credentials
psql -h localhost -U postgres -d lingudesk
```

#### MinIO Not Accessible
```bash
# Check MinIO health
curl http://localhost:9000/minio/health/live

# Reset MinIO credentials
docker compose down minio minio-init
docker compose up -d minio minio-init
```

#### Redis Memory Issues
```bash
# Check memory usage
redis-cli -a $REDIS_PASSWORD INFO memory

# Flush cache if needed
redis-cli -a $REDIS_PASSWORD FLUSHDB
```

#### Backup Failures
```bash
# Check backup logs
tail -f /backup/backup.log

# Verify disk space
df -h /backup

# Test backup manually
./backup/backup.sh
```

## Maintenance

### Daily Tasks
- Monitor health check output
- Verify backup completion

### Weekly Tasks
- Review error logs
- Check disk usage trends
- Update security patches

### Monthly Tasks
- Analyze slow query logs
- Review and optimize indexes
- Clean old audit logs

## Development vs Production

### Development Settings
```yaml
profiles:
  - development
# Includes Redis Commander UI
# Verbose logging enabled
# No TLS required
```

### Production Settings
```yaml
profiles:
  - production
# TLS via Tailscale
# Minimal logging
# Encrypted backups
# No debug tools
```

## Support

### Logs Location
- PostgreSQL: `/var/lib/postgresql/data/log`
- MinIO: Container logs only
- Redis: Container logs only
- Backups: `/backup/*.log`

### Getting Help
1. Check health status: `./monitoring/health-check.sh`
2. Review logs: `docker compose logs [service]`
3. Consult this README
4. Contact system administrator

## License
Proprietary - Lingudesk © 2025
