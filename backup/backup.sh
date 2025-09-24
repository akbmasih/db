#!/bin/bash
# /root/db/backup/backup.sh
# Automated backup script for Lingudesk DB Server

set -e

# Load environment variables
source /root/db/.env

# Set variables
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backup/daily"
BACKUP_PREFIX="lingudesk_backup_${BACKUP_DATE}"
LOG_FILE="/var/log/backup.log"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Function to check disk space
check_disk_space() {
    AVAILABLE=$(df /backup | tail -1 | awk '{print $4}')
    REQUIRED=5242880  # 5GB in KB
    if [ $AVAILABLE -lt $REQUIRED ]; then
        log "ERROR: Insufficient disk space for backup"
        exit 1
    fi
}

# Function to backup PostgreSQL
backup_postgres() {
    log "Starting PostgreSQL backup..."
    
    # Create backup directory
    mkdir -p ${BACKUP_DIR}/postgres
    
    # Dump all databases
    PGPASSWORD=$POSTGRES_PASSWORD pg_dumpall \
        -h localhost \
        -U $POSTGRES_USER \
        --clean \
        --if-exists \
        --verbose \
        | gzip > ${BACKUP_DIR}/postgres/${BACKUP_PREFIX}_postgres.sql.gz
    
    # Backup individual schemas for faster restore
    for schema in public auth credit ai content audit; do
        PGPASSWORD=$POSTGRES_PASSWORD pg_dump \
            -h localhost \
            -U $POSTGRES_USER \
            -d $POSTGRES_DB \
            -n $schema \
            --verbose \
            | gzip > ${BACKUP_DIR}/postgres/${BACKUP_PREFIX}_schema_${schema}.sql.gz
    done
    
    log "PostgreSQL backup completed"
}

# Function to backup Redis
backup_redis() {
    log "Starting Redis backup..."
    
    mkdir -p ${BACKUP_DIR}/redis
    
    # Force Redis to save
    docker exec lingudesk_redis redis-cli -a $REDIS_PASSWORD BGSAVE
    
    # Wait for save to complete
    sleep 5
    
    # Copy Redis dump files
    docker cp lingudesk_redis:/data/dump.rdb ${BACKUP_DIR}/redis/${BACKUP_PREFIX}_dump.rdb
    docker cp lingudesk_redis:/data/appendonly.aof ${BACKUP_DIR}/redis/${BACKUP_PREFIX}_appendonly.aof 2>/dev/null || true
    
    log "Redis backup completed"
}

# Function to backup MinIO metadata
backup_minio_metadata() {
    log "Starting MinIO metadata backup..."
    
    mkdir -p ${BACKUP_DIR}/minio
    
    # Export MinIO configuration
    docker exec lingudesk_minio mc alias set local http://localhost:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD
    docker exec lingudesk_minio mc admin config export local > ${BACKUP_DIR}/minio/${BACKUP_PREFIX}_config.json
    
    # List all buckets and their policies
    docker exec lingudesk_minio mc ls local --json > ${BACKUP_DIR}/minio/${BACKUP_PREFIX}_buckets.json
    
    log "MinIO metadata backup completed"
}

# Function to encrypt backup
encrypt_backup() {
    log "Encrypting backup..."
    
    cd ${BACKUP_DIR}
    tar czf ${BACKUP_PREFIX}.tar.gz postgres/ redis/ minio/
    
    # Encrypt with GPG
    echo $BACKUP_ENCRYPTION_KEY | gpg --batch --yes --passphrase-fd 0 --cipher-algo AES256 \
        --symmetric --output ${BACKUP_PREFIX}.tar.gz.gpg ${BACKUP_PREFIX}.tar.gz
    
    # Remove unencrypted files
    rm -rf postgres/ redis/ minio/ ${BACKUP_PREFIX}.tar.gz
    
    log "Backup encrypted successfully"
}

# Function to upload to MinIO
upload_to_minio() {
    log "Uploading backup to MinIO..."
    
    # Configure mc client
    docker exec lingudesk_minio mc alias set local http://localhost:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD
    
    # Upload encrypted backup
    docker exec lingudesk_minio mc cp ${BACKUP_DIR}/${BACKUP_PREFIX}.tar.gz.gpg local/lingudesk-backups/database/
    
    log "Backup uploaded to MinIO"
}

# Function to cleanup old backups
cleanup_old_backups() {
    log "Cleaning up old backups..."
    
    # Remove local backups older than 7 days
    find ${BACKUP_DIR} -name "*.tar.gz.gpg" -mtime +7 -delete
    
    # Remove MinIO backups older than retention period
    docker exec lingudesk_minio mc rm --recursive --force --older-than ${BACKUP_RETENTION_DAYS}d \
        local/lingudesk-backups/database/
    
    log "Old backups cleaned up"
}

# Function to verify backup
verify_backup() {
    log "Verifying backup..."
    
    BACKUP_SIZE=$(stat -c%s "${BACKUP_DIR}/${BACKUP_PREFIX}.tar.gz.gpg")
    if [ $BACKUP_SIZE -lt 1000 ]; then
        log "ERROR: Backup file too small, possible corruption"
        exit 1
    fi
    
    log "Backup verification passed (Size: $BACKUP_SIZE bytes)"
}

# Main execution
main() {
    log "=== Starting backup process ==="
    
    check_disk_space
    backup_postgres
    backup_redis
    backup_minio_metadata
    encrypt_backup
    upload_to_minio
    verify_backup
    cleanup_old_backups
    
    log "=== Backup process completed successfully ==="
    
    # Send notification (optional)
    # curl -X POST http://10.0.0.7:9093/api/v1/alerts \
    #     -H "Content-Type: application/json" \
    #     -d "{\"alert\": \"Backup completed\", \"status\": \"success\", \"timestamp\": \"$(date -Iseconds)\"}"
}

# Error handling
trap 'log "ERROR: Backup failed at line $LINENO"' ERR

# Run main function
main