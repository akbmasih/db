#!/bin/bash
# /root/db/backup/restore.sh
# Database restore script for Lingudesk DB Server

set -e

# Load environment variables
source /root/db/.env

# Variables
RESTORE_DIR="/backup/restore"
LOG_FILE="/var/log/restore.log"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Function to list available backups
list_backups() {
    log "Available backups in MinIO:"
    docker exec lingudesk_minio mc ls local/lingudesk-backups/database/ | grep ".gpg"
    
    log "Available local backups:"
    ls -lah /backup/daily/*.gpg 2>/dev/null || echo "No local backups found"
}

# Function to download backup from MinIO
download_backup() {
    local BACKUP_FILE=$1
    
    log "Downloading backup: $BACKUP_FILE"
    
    mkdir -p ${RESTORE_DIR}
    
    # Configure mc client
    docker exec lingudesk_minio mc alias set local http://localhost:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD
    
    # Download backup
    docker exec lingudesk_minio mc cp local/lingudesk-backups/database/${BACKUP_FILE} ${RESTORE_DIR}/
    
    log "Backup downloaded successfully"
}

# Function to decrypt backup
decrypt_backup() {
    local BACKUP_FILE=$1
    
    log "Decrypting backup..."
    
    cd ${RESTORE_DIR}
    
    # Decrypt with GPG
    echo $BACKUP_ENCRYPTION_KEY | gpg --batch --yes --passphrase-fd 0 \
        --decrypt ${BACKUP_FILE} > ${BACKUP_FILE%.gpg}
    
    # Extract tar archive
    tar xzf ${BACKUP_FILE%.gpg}
    
    log "Backup decrypted successfully"
}

# Function to restore PostgreSQL
restore_postgres() {
    local RESTORE_TYPE=$1  # 'full' or 'schema'
    local SCHEMA_NAME=$2   # Optional, for single schema restore
    
    log "Starting PostgreSQL restore (type: $RESTORE_TYPE)..."
    
    if [ "$RESTORE_TYPE" = "full" ]; then
        # Stop all connections
        PGPASSWORD=$POSTGRES_PASSWORD psql \
            -h localhost \
            -U $POSTGRES_USER \
            -d postgres \
            -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$POSTGRES_DB' AND pid <> pg_backend_pid();"
        
        # Restore full database
        gunzip -c ${RESTORE_DIR}/postgres/*_postgres.sql.gz | \
            PGPASSWORD=$POSTGRES_PASSWORD psql \
                -h localhost \
                -U $POSTGRES_USER \
                -d postgres \
                -v ON_ERROR_STOP=1
                
    elif [ "$RESTORE_TYPE" = "schema" ] && [ -n "$SCHEMA_NAME" ]; then
        # Restore single schema
        gunzip -c ${RESTORE_DIR}/postgres/*_schema_${SCHEMA_NAME}.sql.gz | \
            PGPASSWORD=$POSTGRES_PASSWORD psql \
                -h localhost \
                -U $POSTGRES_USER \
                -d $POSTGRES_DB \
                -v ON_ERROR_STOP=1
    fi
    
    # Analyze database after restore
    PGPASSWORD=$POSTGRES_PASSWORD psql \
        -h localhost \
        -U $POSTGRES_USER \
        -d $POSTGRES_DB \
        -c "ANALYZE;"
    
    log "PostgreSQL restore completed"
}

# Function to restore Redis
restore_redis() {
    log "Starting Redis restore..."
    
    # Stop Redis to replace dump file
    docker stop lingudesk_redis
    
    # Backup current Redis data
    mv /var/lib/docker/volumes/db_redis_data/_data/dump.rdb \
       /var/lib/docker/volumes/db_redis_data/_data/dump.rdb.bak 2>/dev/null || true
    
    # Copy restored dump file
    cp ${RESTORE_DIR}/redis/*_dump.rdb \
       /var/lib/docker/volumes/db_redis_data/_data/dump.rdb
    
    # Copy AOF file if exists
    if [ -f ${RESTORE_DIR}/redis/*_appendonly.aof ]; then
        cp ${RESTORE_DIR}/redis/*_appendonly.aof \
           /var/lib/docker/volumes/db_redis_data/_data/appendonly.aof
    fi
    
    # Set proper permissions
    chown 999:999 /var/lib/docker/volumes/db_redis_data/_data/*
    
    # Restart Redis
    docker start lingudesk_redis
    
    # Verify Redis is running
    sleep 5
    docker exec lingudesk_redis redis-cli -a $REDIS_PASSWORD ping
    
    log "Redis restore completed"
}

# Function to verify restore
verify_restore() {
    log "Verifying restore..."
    
    # Check PostgreSQL
    PGPASSWORD=$POSTGRES_PASSWORD psql \
        -h localhost \
        -U $POSTGRES_USER \
        -d $POSTGRES_DB \
        -c "SELECT COUNT(*) FROM public.users;" > /dev/null
    
    if [ $? -eq 0 ]; then
        log "PostgreSQL verification: OK"
    else
        log "ERROR: PostgreSQL verification failed"
        exit 1
    fi
    
    # Check Redis
    REDIS_CHECK=$(docker exec lingudesk_redis redis-cli -a $REDIS_PASSWORD ping)
    if [ "$REDIS_CHECK" = "PONG" ]; then
        log "Redis verification: OK"
    else
        log "ERROR: Redis verification failed"
        exit 1
    fi
    
    log "Restore verification completed"
}

# Function to cleanup restore directory
cleanup_restore() {
    log "Cleaning up restore directory..."
    rm -rf ${RESTORE_DIR}/*
    log "Cleanup completed"
}

# Interactive menu
interactive_menu() {
    echo "==================================="
    echo "Lingudesk Database Restore Utility"
    echo "==================================="
    echo ""
    echo "1. List available backups"
    echo "2. Restore from MinIO backup"
    echo "3. Restore from local backup"
    echo "4. Restore specific schema only"
    echo "5. Exit"
    echo ""
    read -p "Select option: " OPTION
    
    case $OPTION in
        1)
            list_backups
            ;;
        2)
            list_backups
            read -p "Enter backup filename: " BACKUP_FILE
            read -p "Confirm restore from $BACKUP_FILE? (yes/no): " CONFIRM
            if [ "$CONFIRM" = "yes" ]; then
                download_backup $BACKUP_FILE
                decrypt_backup $BACKUP_FILE
                restore_postgres "full"
                restore_redis
                verify_restore
                cleanup_restore
            fi
            ;;
        3)
            ls -lah /backup/daily/*.gpg
            read -p "Enter local backup path: " LOCAL_PATH
            read -p "Confirm restore from $LOCAL_PATH? (yes/no): " CONFIRM
            if [ "$CONFIRM" = "yes" ]; then
                cp $LOCAL_PATH ${RESTORE_DIR}/
                BACKUP_FILE=$(basename $LOCAL_PATH)
                decrypt_backup $BACKUP_FILE
                restore_postgres "full"
                restore_redis
                verify_restore
                cleanup_restore
            fi
            ;;
        4)
            echo "Available schemas: public, auth, credit, ai, content, audit"
            read -p "Enter schema name: " SCHEMA_NAME
            list_backups
            read -p "Enter backup filename: " BACKUP_FILE
            read -p "Confirm restore schema $SCHEMA_NAME from $BACKUP_FILE? (yes/no): " CONFIRM
            if [ "$CONFIRM" = "yes" ]; then
                download_backup $BACKUP_FILE
                decrypt_backup $BACKUP_FILE
                restore_postgres "schema" $SCHEMA_NAME
                verify_restore
                cleanup_restore
            fi
            ;;
        5)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid option"
            exit 1
            ;;
    esac
}

# Main execution
main() {
    log "=== Starting restore process ==="
    
    # Check if running with arguments or interactive
    if [ $# -eq 0 ]; then
        interactive_menu
    else
        # Command line mode
        case "$1" in
            --list)
                list_backups
                ;;
            --restore)
                if [ -z "$2" ]; then
                    echo "Usage: $0 --restore <backup_filename>"
                    exit 1
                fi
                download_backup $2
                decrypt_backup $2
                restore_postgres "full"
                restore_redis
                verify_restore
                cleanup_restore
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --list              List available backups"
                echo "  --restore <file>    Restore from specific backup"
                echo "  --help              Show this help message"
                echo ""
                echo "Run without arguments for interactive mode"
                ;;
            *)
                echo "Unknown option: $1"
                echo "Run with --help for usage information"
                exit 1
                ;;
        esac
    fi
    
    log "=== Restore process completed ==="
}

# Error handling
trap 'log "ERROR: Restore failed at line $LINENO"' ERR

# Run main function
main $@