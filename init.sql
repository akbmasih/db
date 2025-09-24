-- /db/init.sql
-- Centralized PostgreSQL database structure for Lingudesk v15
-- Single database serving all microservices with schema separation

-- ============================================
-- EXTENSIONS
-- ============================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm"; -- For text search

-- ============================================
-- SCHEMAS
-- ============================================
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS credit;
CREATE SCHEMA IF NOT EXISTS ai;
CREATE SCHEMA IF NOT EXISTS content;
CREATE SCHEMA IF NOT EXISTS audit;

-- ============================================
-- PUBLIC SCHEMA - SHARED TABLES
-- ============================================

-- Core users table (minimal, shared across all services)
CREATE TABLE public.users (
    user_id VARCHAR(10) PRIMARY KEY, -- 10-char Base32 Crockford
    email VARCHAR(255) UNIQUE NOT NULL,
    email_normalized VARCHAR(255) GENERATED ALWAYS AS (LOWER(email)) STORED,
    full_name VARCHAR(255),
    role VARCHAR(20) DEFAULT 'user' CHECK (role IN ('user', 'admin')),
    account_type VARCHAR(20) DEFAULT 'free' CHECK (account_type IN ('free', 'plus', 'premium')),
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'deleted', 'pending')),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_users_email ON public.users(email_normalized);
CREATE INDEX idx_users_account_type ON public.users(account_type);
CREATE INDEX idx_users_status ON public.users(status);

-- ============================================
-- AUTH SCHEMA
-- ============================================

-- Authentication credentials
CREATE TABLE auth.credentials (
    user_id VARCHAR(10) PRIMARY KEY REFERENCES public.users(user_id) ON DELETE CASCADE,
    password_hash TEXT NOT NULL,
    password_changed_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    email_verified BOOLEAN DEFAULT FALSE,
    email_verified_at TIMESTAMPTZ,
    failed_login_attempts INTEGER DEFAULT 0,
    locked_until TIMESTAMPTZ,
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Refresh tokens
CREATE TABLE auth.refresh_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id VARCHAR(10) NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    token_identifier VARCHAR(64) UNIQUE NOT NULL, -- Opaque identifier for cookie
    token_hash VARCHAR(128) UNIQUE NOT NULL, -- Actual token hash
    device_fingerprint VARCHAR(64),
    ip_address INET,
    user_agent TEXT,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    last_used_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    usage_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_refresh_tokens_user_id ON auth.refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_identifier ON auth.refresh_tokens(token_identifier);
CREATE INDEX idx_refresh_tokens_expires ON auth.refresh_tokens(expires_at);

-- 2FA settings
CREATE TABLE auth.two_fa_settings (
    user_id VARCHAR(10) PRIMARY KEY REFERENCES public.users(user_id) ON DELETE CASCADE,
    enabled BOOLEAN DEFAULT FALSE,
    method VARCHAR(20) DEFAULT 'email' CHECK (method IN ('email', 'totp')),
    secret_encrypted TEXT,
    backup_codes TEXT[],
    last_used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Email verifications
CREATE TABLE auth.email_verifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) NOT NULL,
    code VARCHAR(6) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    verified_at TIMESTAMPTZ,
    attempts INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(email, code)
);

CREATE INDEX idx_email_verifications_email ON auth.email_verifications(email);
CREATE INDEX idx_email_verifications_expires ON auth.email_verifications(expires_at);

-- Password resets
CREATE TABLE auth.password_resets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id VARCHAR(10) NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    token_hash VARCHAR(128) UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    ip_address INET,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_password_resets_token ON auth.password_resets(token_hash);
CREATE INDEX idx_password_resets_expires ON auth.password_resets(expires_at);

-- OAuth providers
CREATE TABLE auth.oauth_accounts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id VARCHAR(10) NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    provider VARCHAR(20) NOT NULL CHECK (provider IN ('google', 'apple')),
    provider_user_id VARCHAR(255) NOT NULL,
    access_token_encrypted TEXT,
    refresh_token_encrypted TEXT,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(provider, provider_user_id)
);

CREATE INDEX idx_oauth_accounts_user_id ON auth.oauth_accounts(user_id);
CREATE INDEX idx_oauth_accounts_provider ON auth.oauth_accounts(provider, provider_user_id);

-- ============================================
-- CREDIT SCHEMA
-- ============================================

-- User balances
CREATE TABLE credit.balances (
    user_id VARCHAR(10) PRIMARY KEY REFERENCES public.users(user_id) ON DELETE CASCADE,
    balance DECIMAL(12,4) DEFAULT 0.0000 CHECK (balance >= 0),
    total_spent DECIMAL(12,4) DEFAULT 0.0000,
    total_purchased DECIMAL(12,4) DEFAULT 0.0000,
    last_transaction_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Transactions
CREATE TABLE credit.transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id VARCHAR(10) NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    amount DECIMAL(12,4) NOT NULL,
    balance_after DECIMAL(12,4) NOT NULL,
    type VARCHAR(20) NOT NULL CHECK (type IN ('usage', 'purchase', 'refund', 'adjustment', 'subscription')),
    service_name VARCHAR(50),
    description TEXT,
    metadata JSONB DEFAULT '{}',
    reference_id VARCHAR(100), -- External reference (Paddle order ID, etc.)
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_transactions_user_id ON credit.transactions(user_id);
CREATE INDEX idx_transactions_type ON credit.transactions(type);
CREATE INDEX idx_transactions_created_at ON credit.transactions(created_at);
CREATE INDEX idx_transactions_reference ON credit.transactions(reference_id);

-- Subscriptions
CREATE TABLE credit.subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id VARCHAR(10) NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    plan VARCHAR(20) NOT NULL CHECK (plan IN ('plus', 'premium')),
    status VARCHAR(20) NOT NULL CHECK (status IN ('active', 'cancelled', 'expired', 'paused')),
    started_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    paddle_subscription_id VARCHAR(100),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_subscriptions_user_id ON credit.subscriptions(user_id);
CREATE INDEX idx_subscriptions_status ON credit.subscriptions(status);
CREATE INDEX idx_subscriptions_paddle_id ON credit.subscriptions(paddle_subscription_id);

-- Pricing rules
CREATE TABLE credit.pricing_rules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    service_name VARCHAR(50) NOT NULL,
    account_type VARCHAR(20) NOT NULL CHECK (account_type IN ('free', 'plus', 'premium')),
    price_per_unit DECIMAL(10,8) NOT NULL CHECK (price_per_unit >= 0),
    unit_type VARCHAR(20) DEFAULT 'token', -- token, request, character
    from_cache BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(service_name, account_type, from_cache)
);

CREATE INDEX idx_pricing_rules_lookup ON credit.pricing_rules(service_name, account_type, is_active);

-- ============================================
-- AI SCHEMA
-- ============================================

-- AI cache entries
CREATE TABLE ai.cache_entries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cache_key VARCHAR(64) UNIQUE NOT NULL, -- SHA256 hash of request
    plugin_name VARCHAR(50) NOT NULL,
    request_hash VARCHAR(64) NOT NULL,
    request_data JSONB NOT NULL,
    response_data JSONB NOT NULL,
    response_type VARCHAR(20) DEFAULT 'text', -- text, image, audio
    media_url TEXT, -- MinIO URL for media
    tokens_used INTEGER DEFAULT 0,
    processing_time_ms INTEGER,
    accessed_count INTEGER DEFAULT 1,
    last_accessed_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_cache_key ON ai.cache_entries(cache_key);
CREATE INDEX idx_cache_plugin ON ai.cache_entries(plugin_name);
CREATE INDEX idx_cache_expires ON ai.cache_entries(expires_at);
CREATE INDEX idx_cache_accessed ON ai.cache_entries(last_accessed_at);

-- AI usage logs
CREATE TABLE ai.usage_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id VARCHAR(10) REFERENCES public.users(user_id) ON DELETE SET NULL,
    plugin_name VARCHAR(50) NOT NULL,
    endpoint VARCHAR(100) NOT NULL,
    request_data JSONB,
    response_data JSONB,
    tokens_used INTEGER DEFAULT 0,
    cost DECIMAL(10,4) DEFAULT 0.0000,
    processing_time_ms INTEGER,
    from_cache BOOLEAN DEFAULT FALSE,
    cache_key VARCHAR(64),
    error_code VARCHAR(50),
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_usage_logs_user ON ai.usage_logs(user_id);
CREATE INDEX idx_usage_logs_plugin ON ai.usage_logs(plugin_name);
CREATE INDEX idx_usage_logs_created ON ai.usage_logs(created_at);

-- Plugin configurations
CREATE TABLE ai.plugin_configs (
    plugin_name VARCHAR(50) PRIMARY KEY,
    enabled BOOLEAN DEFAULT TRUE,
    config JSONB DEFAULT '{}',
    rate_limit_per_minute INTEGER DEFAULT 20,
    cache_enabled BOOLEAN DEFAULT TRUE,
    cache_ttl_seconds INTEGER DEFAULT 86400, -- 24 hours
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- CONTENT SCHEMA
-- ============================================

-- Decks
CREATE TABLE content.decks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id VARCHAR(10) NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    front_lang VARCHAR(10) DEFAULT 'en',
    back_lang VARCHAR(10) DEFAULT 'en',
    settings JSONB DEFAULT '{}',
    card_count INTEGER DEFAULT 0,
    is_public BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_decks_user_id ON content.decks(user_id);
CREATE INDEX idx_decks_public ON content.decks(is_public);

-- Cards
CREATE TABLE content.cards (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    deck_id UUID NOT NULL REFERENCES content.decks(id) ON DELETE CASCADE,
    user_id VARCHAR(10) NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    front_text TEXT NOT NULL,
    back_text TEXT NOT NULL,
    front_audio_url TEXT,
    back_audio_url TEXT,
    front_image_url TEXT,
    back_image_url TEXT,
    metadata JSONB DEFAULT '{}',
    -- FSRS fields
    due TIMESTAMPTZ,
    stability FLOAT DEFAULT 0,
    difficulty FLOAT DEFAULT 0,
    elapsed_days INTEGER DEFAULT 0,
    scheduled_days INTEGER DEFAULT 0,
    reps INTEGER DEFAULT 0,
    lapses INTEGER DEFAULT 0,
    state VARCHAR(20) DEFAULT 'New' CHECK (state IN ('New', 'Learning', 'Review', 'Relearning')),
    last_review TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_cards_deck_id ON content.cards(deck_id);
CREATE INDEX idx_cards_user_id ON content.cards(user_id);
CREATE INDEX idx_cards_due ON content.cards(due);
CREATE INDEX idx_cards_state ON content.cards(state);

-- Review logs
CREATE TABLE content.review_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    card_id UUID NOT NULL REFERENCES content.cards(id) ON DELETE CASCADE,
    user_id VARCHAR(10) NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 4),
    state VARCHAR(20) NOT NULL,
    elapsed_days INTEGER DEFAULT 0,
    scheduled_days INTEGER DEFAULT 0,
    review_duration_ms INTEGER,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_review_logs_card ON content.review_logs(card_id);
CREATE INDEX idx_review_logs_user ON content.review_logs(user_id);
CREATE INDEX idx_review_logs_created ON content.review_logs(created_at);

-- User settings
CREATE TABLE content.user_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id VARCHAR(10) NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    category VARCHAR(50) NOT NULL, -- general, learning, display
    key VARCHAR(100) NOT NULL,
    value TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, category, key)
);

CREATE INDEX idx_user_settings_user ON content.user_settings(user_id);
CREATE INDEX idx_user_settings_category ON content.user_settings(category);

-- ============================================
-- AUDIT SCHEMA
-- ============================================

-- Unified audit log
CREATE TABLE audit.logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    timestamp TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    service VARCHAR(50) NOT NULL, -- auth, credit, ai, content, backend
    user_id VARCHAR(10) REFERENCES public.users(user_id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    resource_type VARCHAR(50),
    resource_id VARCHAR(100),
    ip_address INET,
    user_agent TEXT,
    request_id UUID,
    response_code INTEGER,
    duration_ms INTEGER,
    metadata JSONB DEFAULT '{}',
    error_message TEXT
);

CREATE INDEX idx_audit_timestamp ON audit.logs(timestamp);
CREATE INDEX idx_audit_service ON audit.logs(service);
CREATE INDEX idx_audit_user ON audit.logs(user_id);
CREATE INDEX idx_audit_action ON audit.logs(action);
CREATE INDEX idx_audit_request ON audit.logs(request_id);

-- Partition by month for performance
CREATE TABLE audit.logs_y2025m01 PARTITION OF audit.logs
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

-- ============================================
-- FUNCTIONS
-- ============================================

-- Auto-update timestamp function
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply update triggers
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_auth_credentials_updated_at BEFORE UPDATE ON auth.credentials
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_credit_balances_updated_at BEFORE UPDATE ON credit.balances
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_credit_subscriptions_updated_at BEFORE UPDATE ON credit.subscriptions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_ai_plugin_configs_updated_at BEFORE UPDATE ON ai.plugin_configs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_content_decks_updated_at BEFORE UPDATE ON content.decks
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_content_cards_updated_at BEFORE UPDATE ON content.cards
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_content_user_settings_updated_at BEFORE UPDATE ON content.user_settings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Function to update card count in deck
CREATE OR REPLACE FUNCTION update_deck_card_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE content.decks SET card_count = card_count + 1 WHERE id = NEW.deck_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE content.decks SET card_count = card_count - 1 WHERE id = OLD.deck_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_deck_count_on_insert AFTER INSERT ON content.cards
    FOR EACH ROW EXECUTE FUNCTION update_deck_card_count();

CREATE TRIGGER update_deck_count_on_delete AFTER DELETE ON content.cards
    FOR EACH ROW EXECUTE FUNCTION update_deck_card_count();

-- Function to update balance after transaction
CREATE OR REPLACE FUNCTION update_user_balance()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE credit.balances 
    SET balance = NEW.balance_after,
        last_transaction_at = NEW.created_at,
        total_spent = CASE 
            WHEN NEW.type = 'usage' AND NEW.amount < 0 
            THEN total_spent + ABS(NEW.amount)
            ELSE total_spent
        END,
        total_purchased = CASE 
            WHEN NEW.type = 'purchase' AND NEW.amount > 0 
            THEN total_purchased + NEW.amount
            ELSE total_purchased
        END
    WHERE user_id = NEW.user_id;
    
    -- Create balance record if not exists
    IF NOT FOUND THEN
        INSERT INTO credit.balances (user_id, balance, last_transaction_at)
        VALUES (NEW.user_id, NEW.balance_after, NEW.created_at);
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_balance_after_transaction AFTER INSERT ON credit.transactions
    FOR EACH ROW EXECUTE FUNCTION update_user_balance();

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================

-- Enable RLS on sensitive tables
ALTER TABLE content.decks ENABLE ROW LEVEL SECURITY;
ALTER TABLE content.cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE content.review_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE content.user_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE credit.balances ENABLE ROW LEVEL SECURITY;
ALTER TABLE credit.transactions ENABLE ROW LEVEL SECURITY;

-- RLS Policies (using session variables set by application)
CREATE POLICY users_own_decks ON content.decks
    FOR ALL USING (user_id = current_setting('app.current_user_id', true));

CREATE POLICY users_own_cards ON content.cards
    FOR ALL USING (user_id = current_setting('app.current_user_id', true));

CREATE POLICY users_own_reviews ON content.review_logs
    FOR ALL USING (user_id = current_setting('app.current_user_id', true));

CREATE POLICY users_own_settings ON content.user_settings
    FOR ALL USING (user_id = current_setting('app.current_user_id', true));

CREATE POLICY users_own_balance ON credit.balances
    FOR SELECT USING (user_id = current_setting('app.current_user_id', true));

CREATE POLICY users_own_transactions ON credit.transactions
    FOR SELECT USING (user_id = current_setting('app.current_user_id', true));

-- ============================================
-- VIEWS
-- ============================================

-- User dashboard view
CREATE VIEW public.user_dashboard AS
SELECT 
    u.user_id,
    u.email,
    u.full_name,
    u.account_type,
    u.status,
    ac.email_verified,
    ac.last_login_at,
    cb.balance,
    cb.total_spent,
    (SELECT COUNT(*) FROM content.decks WHERE user_id = u.user_id) as deck_count,
    (SELECT COUNT(*) FROM content.cards WHERE user_id = u.user_id) as card_count,
    u.created_at
FROM public.users u
LEFT JOIN auth.credentials ac ON u.user_id = ac.user_id
LEFT JOIN credit.balances cb ON u.user_id = cb.user_id;

-- Service usage statistics view
CREATE VIEW public.service_usage_stats AS
SELECT 
    DATE_TRUNC('day', created_at) as date,
    plugin_name as service,
    COUNT(*) as request_count,
    SUM(tokens_used) as total_tokens,
    SUM(cost) as total_cost,
    AVG(processing_time_ms) as avg_processing_time,
    SUM(CASE WHEN from_cache THEN 1 ELSE 0 END) as cache_hits
FROM ai.usage_logs
GROUP BY DATE_TRUNC('day', created_at), plugin_name;

-- ============================================
-- PERMISSIONS
-- ============================================

-- Grant schema usage
GRANT USAGE ON SCHEMA public, auth, credit, ai, content, audit TO db_user;

-- Grant appropriate permissions to application user
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO db_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA auth TO db_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA credit TO db_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA ai TO db_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA content TO db_user;
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA audit TO db_user;

-- Grant sequence permissions
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO db_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA auth TO db_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA credit TO db_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA ai TO db_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA content TO db_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA audit TO db_user;

-- Grant execute on functions
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO db_user;