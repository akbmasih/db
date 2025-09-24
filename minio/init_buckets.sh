#!/bin/bash
# /root/db/minio/init_buckets.sh
# Initialize MinIO buckets and policies for Lingudesk

set -e

# Wait for MinIO to be ready
sleep 5

# Configure MinIO client
mc alias set lingudesk http://minio:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD

# Create buckets
echo "Creating buckets..."
mc mb --ignore-existing lingudesk/lingudesk-media
mc mb --ignore-existing lingudesk/lingudesk-ai-cache
mc mb --ignore-existing lingudesk/lingudesk-backups

# Set bucket versioning
echo "Configuring versioning..."
mc version enable lingudesk/lingudesk-media
mc version enable lingudesk/lingudesk-backups

# Set lifecycle policies for AI cache (expire after 30 days)
echo "Setting lifecycle policies..."
cat > /tmp/lifecycle.json <<EOF
{
    "Rules": [
        {
            "ID": "expire-old-cache",
            "Status": "Enabled",
            "Filter": {"Prefix": ""},
            "Expiration": {"Days": 30}
        }
    ]
}
EOF
mc ilm import lingudesk/lingudesk-ai-cache < /tmp/lifecycle.json

# Create service accounts for each microservice
echo "Creating service accounts..."

# Auth service account (read/write to media for profile pictures)
mc admin user add lingudesk auth_service Auth2025Service!Pass
mc admin policy attach lingudesk readwrite --user auth_service

# AI service account (read/write to ai-cache)
mc admin user add lingudesk ai_service AI2025Service!Pass
mc admin policy attach lingudesk readwrite --user ai_service

# Content service account (read/write to media)
mc admin user add lingudesk content_service Content2025Service!Pass
mc admin policy attach lingudesk readwrite --user content_service

# Backend service account (read all buckets)
mc admin user add lingudesk backend_service Backend2025Service!Pass
mc admin policy attach lingudesk readonly --user backend_service

# Set bucket policies
echo "Setting bucket policies..."

# Media bucket policy (allow presigned URLs)
cat > /tmp/media-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {"AWS": ["*"]},
            "Action": ["s3:GetObject"],
            "Resource": ["arn:aws:s3:::lingudesk-media/*"],
            "Condition": {
                "StringLike": {
                    "s3:signature": "*"
                }
            }
        }
    ]
}
EOF
mc anonymous set-json /tmp/media-policy.json lingudesk/lingudesk-media

# Create directory structure in buckets
echo "Creating directory structure..."
mc cp --recursive /dev/null lingudesk/lingudesk-media/cards/images/placeholder || true
mc cp --recursive /dev/null lingudesk/lingudesk-media/cards/audio/placeholder || true
mc cp --recursive /dev/null lingudesk/lingudesk-media/decks/covers/placeholder || true
mc cp --recursive /dev/null lingudesk/lingudesk-media/users/avatars/placeholder || true

mc cp --recursive /dev/null lingudesk/lingudesk-ai-cache/chatgpt/placeholder || true
mc cp --recursive /dev/null lingudesk/lingudesk-ai-cache/claude/placeholder || true
mc cp --recursive /dev/null lingudesk/lingudesk-ai-cache/deepseek/placeholder || true
mc cp --recursive /dev/null lingudesk/lingudesk-ai-cache/flux/placeholder || true
mc cp --recursive /dev/null lingudesk/lingudesk-ai-cache/chatterbox/placeholder || true

# Set bucket notifications (optional - for monitoring)
# mc event add lingudesk/lingudesk-media arn:minio:sqs::_:webhook --event put,delete

# Display summary
echo "MinIO initialization completed!"
echo "Buckets created:"
mc ls lingudesk/
echo ""
echo "Service accounts created:"
echo "- auth_service"
echo "- ai_service"
echo "- content_service"
echo "- backend_service"
echo ""
echo "Access MinIO console at http://10.0.0.5:9001"
echo "Username: $MINIO_ROOT_USER"

# Cleanup
rm -f /tmp/lifecycle.json /tmp/media-policy.json