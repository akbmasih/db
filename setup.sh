#!/bin/bash
# /root/db/setup.sh
# Complete setup script for Lingudesk DB Server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        print_error "Please run as root"
        exit 1
    fi
}

# Install Docker and Docker Compose
install_docker() {
    print_info "Checking Docker installation..."
    
    if ! command -v docker &> /dev/null; then
        print_info "Installing Docker..."
        apt-get update
        apt-get install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
        add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        systemctl enable docker
        systemctl start docker
    else
        print_info "Docker is already installed"
    fi
}

# Install required packages
install_packages() {
    print_info "Installing required packages..."
    apt-get update
    apt-get install -y \
        postgresql-client \
        redis-tools \
        curl \
        wget \
        gnupg \
        jq \
        htop \
        net-tools
}

# Create directory structure
create_directories() {
    print_info "Creating directory structure..."
    
    # Main directories
    mkdir -p /root/db/{postgresql,minio/policies,redis,backup}
    mkdir -p /backup/{daily,restore,wal}
    mkdir -p /var/log/lingudesk
    
    # Set permissions
    chmod 755 /root/db
    chmod 700 /backup
    chmod 755 /var/log/lingudesk
}

# Setup firewall
setup_firewall() {
    print_info "Configuring firewall..."
    
    # Install ufw if not present
    apt-get install -y ufw
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH (custom port)
    ufw allow 2222/tcp comment 'SSH custom port'
    
    # Allow internal network access to services
    ufw allow from 10.0.0.0/24 to any port 5432 comment 'PostgreSQL from core-net'
    ufw allow from 10.0.0.0/24 to any port 6432 comment 'PgBouncer from core-net'
    ufw allow from 10.0.0.0/24 to any port 9000 comment 'MinIO API from core-net'
    ufw allow from 10.0.0.0/24 to any port 6379 comment 'Redis from core-net'
    
    # Enable firewall
    ufw --force enable
    
    print_info "Firewall configured"
}

# Generate secure passwords if .env doesn't exist
generate_env() {
    if [ ! -f /root/db/.env ]; then
        print_info "Generating .env file with secure passwords..."
        
        # Generate random passwords
        POSTGRES_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        MINIO_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        REDIS_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        BACKUP_KEY=$(openssl rand -base64 32)
        
        cat > /root/db/.env <<EOF
# /root/db/.env
# Environment variables for DB Server components

# PostgreSQL Configuration
POSTGRES_DB=lingudesk
POSTGRES_USER=db_user
POSTGRES_PASSWORD=${POSTGRES_PASS}
POSTGRES_HOST=10.0.0.5
POSTGRES_PORT=5432

# MinIO Configuration
MINIO_ROOT_USER=lingudesk_admin
MINIO_ROOT_PASSWORD=${MINIO_PASS}
MINIO_BROWSER=on
MINIO_DOMAIN=minio.lingudesk.local
MINIO_SERVER_URL=http://10.0.0.5:9000
MINIO_BROWSER_URL=http://10.0.0.5:9001

# Redis Configuration
REDIS_PASSWORD=${REDIS_PASS}
REDIS_MAXMEMORY=2gb
REDIS_MAXMEMORY_POLICY=allkeys-lru

# Backup Configuration
BACKUP_RETENTION_DAYS=30
BACKUP_ENCRYPTION_KEY=${BACKUP_KEY}
S3_BACKUP_BUCKET=lingudesk-backups

# Network Configuration
DB_INTERNAL_IP=10.0.0.5
ALLOWED_NETWORKS=10.0.0.0/24
EOF
        
        chmod 600 /root/db/.env
        print_warning "Generated passwords saved to /root/db/.env"
        print_warning "IMPORTANT: Save these passwords securely!"
    else
        print_info ".env file already exists"
    fi
}

# Make scripts executable
set_permissions() {
    print_info "Setting file permissions..."
    
    chmod +x /root/db/minio/init_buckets.sh
    chmod +x /root/db/backup/backup.sh
    chmod +x /root/db/backup/restore.sh
    chmod 600 /root/db/.env
    chmod 644 /root/db/postgresql/postgresql.conf
    chmod 644 /root/db/postgresql/pg_hba.conf
    chmod 644 /root/db/redis/redis.conf
}

# Setup cron jobs
setup_cron() {
    print_info "Setting up cron jobs..."
    
    # Add backup cron job (daily at 3 AM)
    (crontab -l 2>/dev/null | grep -v "backup.sh" ; echo "0 3 * * * /root/db/backup/backup.sh >> /var/log/lingudesk/backup.log 2>&1") | crontab -
    
    # Add cleanup cron job (weekly)
    (crontab -l 2>/dev/null | grep -v "cleanup" ; echo "0 4 * * 0 docker exec lingudesk_postgres psql -U \$POSTGRES_USER -d \$POSTGRES_DB -c 'SELECT cleanup_expired_data();' >> /var/log/lingudesk/cleanup.log 2>&1") | crontab -
    
    print_info "Cron jobs configured"
}

# Start services
start_services() {
    print_info "Starting Docker services..."
    
    cd /root/db
    
    # Pull images first
    docker compose pull
    
    # Start services
    docker compose up -d
    
    # Wait for services to be ready
    print_info "Waiting for services to start..."
    sleep 30
    
    # Check service health
    docker compose ps
}

# Verify installation
verify_installation() {
    print_info "Verifying installation..."
    
    # Check PostgreSQL
    if docker exec lingudesk_postgres pg_isready -U db_user; then
        print_info "✓ PostgreSQL is running"
    else
        print_error "✗ PostgreSQL is not responding"
    fi
    
    # Check Redis
    if docker exec lingudesk_redis redis-cli ping | grep -q PONG; then
        print_info "✓ Redis is running"
    else
        print_error "✗ Redis is not responding"
    fi
    
    # Check MinIO
    if curl -s http://localhost:9000/minio/health/live | grep -q "OK"; then
        print_info "✓ MinIO is running"
    else
        print_error "✗ MinIO is not responding"
    fi
}

# Display summary
display_summary() {
    print_info "======================================"
    print_info "DB Server Setup Completed Successfully"
    print_info "======================================"
    echo ""
    echo "Service Endpoints:"
    echo "  PostgreSQL:    10.0.0.5:5432"
    echo "  PgBouncer:     10.0.0.5:6432"
    echo "  Redis:         10.0.0.5:6379"
    echo "  MinIO API:     10.0.0.5:9000"
    echo "  MinIO Console: 10.0.0.5:9001"
    echo ""
    echo "Credentials are stored in: /root/db/.env"
    echo ""
    echo "Useful commands:"
    echo "  View logs:     docker compose logs -f"
    echo "  Stop services: docker compose down"
    echo "  Backup now:    /root/db/backup/backup.sh"
    echo "  Restore:       /root/db/backup/restore.sh"
    echo ""
    print_warning "Remember to:"
    print_warning "  1. Save the credentials from .env file"
    print_warning "  2. Configure other servers to connect"
    print_warning "  3. Test backup and restore procedures"
}

# Main execution
main() {
    print_info "Starting Lingudesk DB Server Setup"
    
    check_root
    install_docker
    install_packages
    create_directories
    generate_env
    set_permissions
    setup_firewall
    setup_cron
    start_services
    verify_installation
    display_summary
    
    print_info "Setup completed!"
}

# Run main function
main