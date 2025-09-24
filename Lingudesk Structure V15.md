# Lingudesk System Architecture - Version 15

## System Overview

Lingudesk is a distributed language learning platform with 7 physical servers designed for security, scalability, and maintainability. The architecture separates administrative/production components from user-facing services through network segmentation and centralized data management.

### Network Architecture

```
Internet
    |
    ├── Frontend Server (91.99.52.132) - lingudesk.com
    |        |
    |    [edge-net: 10.1.0.0/24]
    |        |
    |    Backend Server (10.1.0.2)
    |        |
    |    [core-net: 10.0.0.0/24]
    |        |
    ├── Auth Server (10.0.0.3)
    ├── Credit Server (10.0.0.4)
    ├── DB Server (10.0.0.5) [PostgreSQL + MinIO + Redis]
    ├── AI Server (10.0.0.6) - External AI APIs
    └── Log Server (10.0.0.7)
```

### Key Design Principles

1. **Network Segmentation**: Two isolated networks (edge-net and core-net) connected only through Backend server
2. **Centralized Database**: Single PostgreSQL instance with schema-based separation
3. **Stateless Services**: Backend, Auth, and AI servers are stateless for scalability
4. **Security First**: HttpOnly cookies with SameSite=Lax, JWT validation, Row-Level Security

## Physical Server Infrastructure

### Server 1: Frontend Server
- **External IP**: 91.99.52.132
- **Internal IP (edge-net)**: 10.1.0.3
- **Domain**: lingudesk.com
- **Technology**: Svelte SPA
- **Purpose**: Static content serving, user interface
- **Security**: HTTPS only, no direct database access

### Server 2: Backend Server
- **Internal IP (edge-net)**: 10.1.0.2
- **Internal IP (core-net)**: 10.0.0.2
- **Technology**: FastAPI with dual network interfaces
- **Purpose**: API gateway, authentication proxy, rate limiting, cost management

#### Backend Core Functions:
1. **Authentication Proxy**:
   - Validates JWT access tokens from Authorization header
   - Manages HttpOnly cookies with refresh token identifiers
   - Handles token refresh with Auth server

2. **Rate Limiting**:
   - Authenticated endpoints: 50 req/min per user_id (standard), 10 req/min (AI)
   - Unauthenticated endpoints: 20 req/min per IP
   - Stored in Redis with automatic TTL

3. **Credit Management**:
   - Pre-flight credit check before service calls
   - Cost calculation based on service response
   - Micro-transaction aggregation (threshold: €0.01)
   - Durability mechanism for cache flush

4. **Request Routing**:
   - Virtual endpoint mapping to physical services
   - User type based routing (free/plus/premium)
   - Service availability checks

### Server 3: Auth Server
- **Internal IP (core-net)**: 10.0.0.3
- **Technology**: FastAPI + PostgreSQL (via central DB)
- **Purpose**: Authentication, JWT management, user lifecycle

#### Auth Features:
1. **User Management**:
   - 10-character user_id generation (Base32 Crockford, CSPRNG)
   - Email/password authentication with bcrypt
   - OAuth2 support (Google, Apple)

2. **JWT Tokens**:
   - RS256 algorithm with key rotation
   - Access token: 15-30 min lifetime
   - Refresh token: 7 days, encrypted, device-bound
   - Public key endpoint for internal validation

3. **Security**:
   - 2FA via email OTP
   - Account lockout after 5 failed attempts
   - Password reset with time-limited tokens
   - Comprehensive audit logging

### Server 4: DB Server
- **Internal IP (core-net)**: 10.0.0.5
- **Technologies**:
   - PostgreSQL 15+ (relational data)
   - MinIO (object storage)
   - Redis (caching, rate limiting)

#### Database Architecture:
1. **Schema Organization**:
   ```sql
   - public schema: shared tables (users base)
   - auth schema: authentication data
   - credit schema: financial transactions
   - ai schema: cache and logs
   - content schema: user data (cards, decks)
   - audit schema: unified audit logs
   ```

2. **Security**:
   - Row-Level Security (RLS) per schema
   - Encrypted sensitive fields
   - User isolation by user_id

3. **Performance**:
   - Connection pooling (pgBouncer)
   - Partitioning for large tables
   - Comprehensive indexing strategy

### Server 5: AI Server
- **External IP**: 188.245.107.89 (for AI API access)
- **Internal IP (core-net)**: 10.0.0.6
- **Technology**: FastAPI + Plugin architecture

#### AI Features:
1. **Plugin System**:
   - Modular design (plugin_chatgpt.py, plugin_flux.py, etc.)
   - Per-plugin configuration and context
   - Independent rate limiting and queuing

2. **Caching**:
   - PostgreSQL for text responses
   - MinIO for generated media
   - Cache-first strategy with explicit refresh option

3. **Supported Models**:
   - ChatGPT (OpenAI)
   - Claude (Anthropic)
   - Deepseek
   - Flux Schnell (images)
   - Chatterbox-TTS (audio)

### Server 6: Credit Server
- **Internal IP (core-net)**: 10.0.0.4
- **Technology**: FastAPI + PostgreSQL (via central DB)
- **Purpose**: Transaction management, subscription handling

#### Credit Features:
1. **User Types**: free, plus, premium
2. **Transaction Management**:
   - Append-only transaction log
   - Real-time balance calculation
   - Paddle webhook integration
3. **Admin Features**:
   - User statistics dashboard
   - Transaction history search
   - Refund and adjustment capabilities

### Server 7: Log Server
- **Internal IP (core-net)**: 10.0.0.7
- **Architecture**: Hybrid (host + containers)

#### Components:
1. **Host Level**:
   - Node Exporter (metrics)
   - Fluent Bit (log forwarding)

2. **Containers**:
   - Prometheus (metrics storage)
   - Grafana (visualization)
   - Loki (log aggregation)
   - AlertManager (notifications)

## Communication Protocols

### Token Management
1. **Access Tokens**:
   - RS256 signed JWTs
   - Claims: user_id, email, name, role, exp, iat, jti
   - Validated by each service independently

2. **Refresh Tokens**:
   - Stored encrypted in database
   - Bound to device fingerprint
   - Automatic rotation on use

### Security Measures
1. **Network Level**:
   - Development: HTTP internal, HTTPS external
   - Production: Tailscale VPN between servers

2. **Application Level**:
   - Input validation on all endpoints
   - SQL injection prevention via parameterized queries
   - XSS protection via Content Security Policy
   - CORS configured for lingudesk.com only

### Service Communication Flow
```
User Request → Frontend (HTTPS) → Backend (validate JWT) → 
→ Check Credits → Route to Service → Process → 
→ Deduct Credits → Return Response
```

## Deployment Strategy

### Development Environment
- Docker Compose for local development
- Single-node deployment for testing
- Mock external services

### Production Environment
- Individual server deployment
- Health checks and monitoring
- Automatic backup (Hetzner daily)
- Blue-green deployment capability

## Monitoring and Maintenance

### Metrics Collection
- Application metrics via Prometheus
- Log aggregation via Loki
- Real-time dashboards in Grafana
- Alert rules for critical events

### Backup Strategy
- Database: Daily automated backups
- MinIO: Object versioning enabled
- Configuration: Git version control
- Disaster recovery: 48-hour RPO

## Scalability Considerations

### Horizontal Scaling Points
- Backend servers (stateless)
- Auth servers (shared JWT keys)
- AI servers (queue distribution)

### Vertical Scaling Points
- Database server (primary bottleneck)
- MinIO storage (disk capacity)
- Redis cache (memory capacity)

## Security Compliance

### Data Protection
- GDPR compliance for EU users
- Encrypted data at rest
- TLS for data in transit
- Regular security audits

### Access Control
- Role-based access (user, plus, premium, admin)
- API key management for external services
- Audit trail for all administrative actions
- Session management with automatic timeout