-- /db/init_data.sql
-- Initial data for Lingudesk centralized database v15
-- Insert core configuration and sample data

-- ============================================
-- DEFAULT USERS
-- ============================================

-- System admin user (for initial setup)
INSERT INTO public.users (user_id, email, full_name, role, account_type, status) VALUES
('ADMIN00001', 'admin@lingudesk.com', 'System Administrator', 'admin', 'premium', 'active'),
('TEST0USER1', 'test@lingudesk.com', 'Test User', 'user', 'free', 'active'),
('DEMO0USER1', 'demo@lingudesk.com', 'Demo User', 'user', 'plus', 'active')
ON CONFLICT (user_id) DO NOTHING;

-- Auth credentials (password: Test123!@# for all)
INSERT INTO auth.credentials (user_id, password_hash, email_verified) VALUES
('ADMIN00001', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY/gJR7YsAjFGJu', true),
('TEST0USER1', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY/gJR7YsAjFGJu', true),
('DEMO0USER1', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY/gJR7YsAjFGJu', true)
ON CONFLICT (user_id) DO NOTHING;

-- 2FA settings for admin
INSERT INTO auth.two_fa_settings (user_id, enabled, method) VALUES
('ADMIN00001', true, 'email')
ON CONFLICT (user_id) DO NOTHING;

-- ============================================
-- AI PLUGIN CONFIGURATIONS
-- ============================================

INSERT INTO ai.plugin_configs (plugin_name, enabled, config, rate_limit_per_minute, cache_enabled, cache_ttl_seconds) VALUES
('chatgpt', true, '{
  "model": "gpt-4o-mini",
  "max_tokens": 2000,
  "temperature": 0.7,
  "api_endpoint": "https://api.openai.com/v1/chat/completions"
}'::jsonb, 20, true, 86400),

('claude', true, '{
  "model": "claude-3-sonnet",
  "max_tokens": 2000,
  "temperature": 0.7,
  "api_endpoint": "https://api.anthropic.com/v1/messages"
}'::jsonb, 20, true, 86400),

('deepseek', true, '{
  "model": "deepseek-chat",
  "max_tokens": 2000,
  "temperature": 0.7,
  "api_endpoint": "https://api.deepseek.com/v1/chat/completions"
}'::jsonb, 30, true, 86400),

('flux', true, '{
  "model": "flux-1-schnell",
  "steps": 4,
  "guidance": 0,
  "width": 1024,
  "height": 1024,
  "api_endpoint": "https://api.replicate.com/v1/predictions"
}'::jsonb, 5, true, 604800),

('chatterbox', true, '{
  "model": "chatterbox-tts-v1",
  "voice": "default",
  "speed": 1.0,
  "api_endpoint": "https://api.chatterbox.com/v1/tts"
}'::jsonb, 10, true, 604800)
ON CONFLICT (plugin_name) DO UPDATE SET
  config = EXCLUDED.config,
  rate_limit_per_minute = EXCLUDED.rate_limit_per_minute,
  cache_ttl_seconds = EXCLUDED.cache_ttl_seconds;

-- ============================================
-- PRICING RULES
-- ============================================

-- ChatGPT pricing
INSERT INTO credit.pricing_rules (service_name, account_type, price_per_unit, unit_type, from_cache) VALUES
('chatgpt', 'free', 0.000100, 'token', false),
('chatgpt', 'free', 0.000050, 'token', true),
('chatgpt', 'plus', 0.000080, 'token', false),
('chatgpt', 'plus', 0.000040, 'token', true),
('chatgpt', 'premium', 0.000060, 'token', false),
('chatgpt', 'premium', 0.000030, 'token', true),

-- Claude pricing
('claude', 'free', 0.000120, 'token', false),
('claude', 'free', 0.000060, 'token', true),
('claude', 'plus', 0.000096, 'token', false),
('claude', 'plus', 0.000048, 'token', true),
('claude', 'premium', 0.000072, 'token', false),
('claude', 'premium', 0.000036, 'token', true),

-- Deepseek pricing
('deepseek', 'free', 0.000080, 'token', false),
('deepseek', 'free', 0.000040, 'token', true),
('deepseek', 'plus', 0.000064, 'token', false),
('deepseek', 'plus', 0.000032, 'token', true),
('deepseek', 'premium', 0.000048, 'token', false),
('deepseek', 'premium', 0.000024, 'token', true),

-- Flux image generation pricing
('flux', 'free', 0.050000, 'request', false),
('flux', 'free', 0.005000, 'request', true),
('flux', 'plus', 0.040000, 'request', false),
('flux', 'plus', 0.004000, 'request', true),
('flux', 'premium', 0.030000, 'request', false),
('flux', 'premium', 0.003000, 'request', true),

-- Chatterbox TTS pricing
('chatterbox', 'free', 0.000015, 'character', false),
('chatterbox', 'free', 0.000008, 'character', true),
('chatterbox', 'plus', 0.000012, 'character', false),
('chatterbox', 'plus', 0.000006, 'character', true),
('chatterbox', 'premium', 0.000009, 'character', false),
('chatterbox', 'premium', 0.000005, 'character', true),

-- Translation service pricing (free for all)
('translate', 'free', 0.000000, 'request', false),
('translate', 'plus', 0.000000, 'request', false),
('translate', 'premium', 0.000000, 'request', false)
ON CONFLICT (service_name, account_type, from_cache) DO NOTHING;

-- ============================================
-- INITIAL USER BALANCES
-- ============================================

INSERT INTO credit.balances (user_id, balance) VALUES
('ADMIN00001', 1000.0000),
('TEST0USER1', 10.0000),
('DEMO0USER1', 50.0000)
ON CONFLICT (user_id) DO NOTHING;

-- Sample subscription for demo user
INSERT INTO credit.subscriptions (user_id, plan, status, started_at, expires_at) VALUES
('DEMO0USER1', 'plus', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '30 days')
ON CONFLICT DO NOTHING;

-- ============================================
-- DEFAULT SETTINGS
-- ============================================

-- FSRS Learning Presets
INSERT INTO content.user_settings (user_id, category, key, value) VALUES
-- Global presets (user_id '0000000000' means available to all)
('0000000000', 'learning', 'preset_beginner', '{
  "name": "Beginner",
  "daily_limit": 10,
  "fsrs_weights": [0.4, 0.6, 2.4, 5.8, 4.93, 0.94, 0.86, 0.01, 1.49, 0.14, 0.94, 2.18, 0.05, 0.34, 1.26, 0.29, 2.61],
  "request_retention": 0.92,
  "maximum_interval": 365,
  "enable_fuzz": true
}'),

('0000000000', 'learning', 'preset_casual', '{
  "name": "Casual",
  "daily_limit": 20,
  "fsrs_weights": [0.4, 0.6, 2.4, 5.8, 4.93, 0.94, 0.86, 0.01, 1.49, 0.14, 0.94, 2.18, 0.05, 0.34, 1.26, 0.29, 2.61],
  "request_retention": 0.90,
  "maximum_interval": 365,
  "enable_fuzz": true
}'),

('0000000000', 'learning', 'preset_balanced', '{
  "name": "Balanced",
  "daily_limit": 30,
  "fsrs_weights": [0.4, 0.6, 2.4, 5.8, 4.93, 0.94, 0.86, 0.01, 1.49, 0.14, 0.94, 2.18, 0.05, 0.34, 1.26, 0.29, 2.61],
  "request_retention": 0.90,
  "maximum_interval": 365,
  "enable_fuzz": true
}'),

('0000000000', 'learning', 'preset_intensive', '{
  "name": "Intensive",
  "daily_limit": 50,
  "fsrs_weights": [0.5, 0.7, 2.8, 6.2, 5.1, 1.1, 0.9, 0.02, 1.6, 0.16, 1.0, 2.3, 0.06, 0.4, 1.4, 0.32, 2.8],
  "request_retention": 0.85,
  "maximum_interval": 365,
  "enable_fuzz": true
}'),

('0000000000', 'learning', 'preset_expert', '{
  "name": "Expert",
  "daily_limit": 100,
  "fsrs_weights": [0.6, 0.8, 3.2, 6.8, 5.5, 1.3, 1.0, 0.03, 1.8, 0.18, 1.1, 2.5, 0.07, 0.45, 1.6, 0.35, 3.2],
  "request_retention": 0.80,
  "maximum_interval": 365,
  "enable_fuzz": false
}'),

-- System defaults
('0000000000', 'general', 'allowed_image_formats', 'jpg,png,webp,gif'),
('0000000000', 'general', 'max_image_size_kb', '10240'),
('0000000000', 'general', 'allowed_audio_formats', 'mp3,wav,ogg,m4a'),
('0000000000', 'general', 'max_audio_size_kb', '10240'),
('0000000000', 'general', 'default_front_lang', 'en'),
('0000000000', 'general', 'default_back_lang', 'en'),

-- Test user settings
('TEST0USER1', 'display', 'theme', 'light'),
('TEST0USER1', 'display', 'font_size', 'medium'),
('TEST0USER1', 'display', 'show_timer', 'true'),
('TEST0USER1', 'display', 'auto_play_audio', 'false'),
('TEST0USER1', 'learning', 'algorithm', 'fsrs'),
('TEST0USER1', 'learning', 'daily_limit', '20')
ON CONFLICT (user_id, category, key) DO NOTHING;

-- ============================================
-- SAMPLE CONTENT DATA
-- ============================================

-- Sample deck for test user
INSERT INTO content.decks (id, user_id, name, description, front_lang, back_lang, settings) 
VALUES (
  '550e8400-e29b-41d4-a716-446655440101'::uuid,
  'TEST0USER1',
  'German to English',
  'Basic German vocabulary with English translations',
  'de',
  'en',
  '{"preset": "balanced", "shuffle": true}'::jsonb
);

-- Sample cards
INSERT INTO content.cards (
  deck_id, user_id, front_text, back_text,
  state, due, stability, difficulty, reps, lapses
) VALUES
('550e8400-e29b-41d4-a716-446655440101'::uuid, 'TEST0USER1', 'Apfel', 'Apple', 
 'New', CURRENT_TIMESTAMP + INTERVAL '1 day', 2.5, 5.0, 0, 0),
 
('550e8400-e29b-41d4-a716-446655440101'::uuid, 'TEST0USER1', 'Buch', 'Book', 
 'New', CURRENT_TIMESTAMP + INTERVAL '1 day', 2.5, 5.0, 0, 0),
 
('550e8400-e29b-41d4-a716-446655440101'::uuid, 'TEST0USER1', 'Haus', 'House', 
 'Learning', CURRENT_TIMESTAMP + INTERVAL '2 days', 3.0, 4.5, 1, 0),
 
('550e8400-e29b-41d4-a716-446655440101'::uuid, 'TEST0USER1', 'Wasser', 'Water', 
 'Review', CURRENT_TIMESTAMP + INTERVAL '5 days', 5.5, 4.0, 3, 0),
 
('550e8400-e29b-41d4-a716-446655440101'::uuid, 'TEST0USER1', 'Baum', 'Tree', 
 'Review', CURRENT_TIMESTAMP + INTERVAL '7 days', 7.0, 3.8, 4, 1);

-- Sample review logs
INSERT INTO content.review_logs (card_id, user_id, rating, state, elapsed_days, scheduled_days)
SELECT 
  c.id, 
  'TEST0USER1', 
  3, -- Good rating
  'Learning',
  1,
  2
FROM content.cards c 
WHERE c.user_id = 'TEST0USER1' 
LIMIT 2;

-- ============================================
-- SAMPLE TRANSACTIONS
-- ============================================

-- Initial balance setup transactions
INSERT INTO credit.transactions (
  user_id, amount, balance_after, type, description
) VALUES
('ADMIN00001', 1000.0000, 1000.0000, 'adjustment', 'Initial admin balance'),
('TEST0USER1', 10.0000, 10.0000, 'purchase', 'Welcome bonus'),
('DEMO0USER1', 50.0000, 50.0000, 'purchase', 'Plus subscription credit');

-- Sample usage transactions
INSERT INTO credit.transactions (
  user_id, amount, balance_after, type, service_name, description, metadata
) VALUES
('TEST0USER1', -0.0500, 9.9500, 'usage', 'chatgpt', 'Text generation - 500 tokens', 
 '{"tokens": 500, "model": "gpt-4o-mini", "from_cache": false}'::jsonb),
 
('TEST0USER1', -0.0000, 9.9500, 'usage', 'translate', 'Translation service', 
 '{"source_lang": "de", "target_lang": "en", "characters": 45}'::jsonb);

-- ============================================
-- SAMPLE AUDIT LOGS
-- ============================================

INSERT INTO audit.logs (
  service, user_id, action, resource_type, resource_id, 
  ip_address, response_code, duration_ms
) VALUES
('auth', 'TEST0USER1', 'login', 'user', 'TEST0USER1', 
 '192.168.1.100'::inet, 200, 145),
 
('credit', 'TEST0USER1', 'deduct', 'transaction', gen_random_uuid()::text, 
 '192.168.1.100'::inet, 200, 23),
 
('content', 'TEST0USER1', 'create', 'deck', '550e8400-e29b-41d4-a716-446655440101', 
 '192.168.1.100'::inet, 201, 67),
 
('ai', 'TEST0USER1', 'generate', 'chatgpt', 'cache_key_abc123', 
 '192.168.1.100'::inet, 200, 1234);

-- ============================================
-- BACKEND ROUTING TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS public.routing_rules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    input_endpoint VARCHAR(255) NOT NULL,
    output_endpoint VARCHAR(255) NOT NULL,
    user_type VARCHAR(20) NOT NULL CHECK (user_type IN ('free', 'plus', 'premium', 'all', 'admin')),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(input_endpoint, user_type)
);

INSERT INTO public.routing_rules (input_endpoint, output_endpoint, user_type) VALUES
-- Auth endpoints
('/auth/register', 'http://10.0.0.3:8000/register', 'all'),
('/auth/login', 'http://10.0.0.3:8000/login', 'all'),
('/auth/refresh', 'http://10.0.0.3:8000/refresh', 'all'),
('/auth/logout', 'http://10.0.0.3:8000/logout', 'all'),
('/auth/verify', 'http://10.0.0.3:8000/verify', 'all'),
('/auth/2fa/verify', 'http://10.0.0.3:8000/2fa/verify', 'all'),
('/auth/password/reset', 'http://10.0.0.3:8000/password/reset', 'all'),
('/auth/oauth/google', 'http://10.0.0.3:8000/oauth/google', 'all'),
('/auth/oauth/apple', 'http://10.0.0.3:8000/oauth/apple', 'all'),

-- AI endpoints
('/ai/translate', 'http://10.0.0.6:8000/translate', 'all'),
('/ai/chat', 'http://10.0.0.6:8000/chatgpt', 'all'),
('/ai/image/generate', 'http://10.0.0.6:8000/flux', 'plus'),
('/ai/image/generate', 'http://10.0.0.6:8000/flux', 'premium'),
('/ai/tts', 'http://10.0.0.6:8000/chatterbox', 'all'),

-- Content endpoints
('/api/decks', 'http://10.0.0.5:8000/decks', 'all'),
('/api/cards', 'http://10.0.0.5:8000/cards', 'all'),
('/api/review', 'http://10.0.0.5:8000/review', 'all'),
('/api/settings', 'http://10.0.0.5:8000/settings', 'all'),

-- Credit endpoints
('/credit/balance', 'http://10.0.0.4:8000/balance', 'all'),
('/credit/history', 'http://10.0.0.4:8000/history', 'all'),
('/credit/webhook/paddle', 'http://10.0.0.4:8000/webhook/paddle', 'all'),

-- Admin endpoints
('/admin/users', 'http://10.0.0.3:8000/admin/users', 'admin'),
('/admin/stats', 'http://10.0.0.4:8000/admin/stats', 'admin'),
('/admin/logs', 'http://10.0.0.7:3000/admin', 'admin')
ON CONFLICT (input_endpoint, user_type) DO NOTHING;

-- ============================================
-- BACKEND SERVICE COSTS
-- ============================================

CREATE TABLE IF NOT EXISTS public.service_costs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    endpoint_name VARCHAR(100) NOT NULL,
    min_account_type VARCHAR(20) NOT NULL CHECK (min_account_type IN ('free', 'plus', 'premium')),
    min_credit_required DECIMAL(10,4) DEFAULT 0.0000,
    credit_multiplier DECIMAL(10,4) DEFAULT 1.0000,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(endpoint_name, min_account_type)
);

INSERT INTO public.service_costs (endpoint_name, min_account_type, min_credit_required, credit_multiplier) VALUES
-- Free services
('translate', 'free', 0.0000, 0.0000),
('translate', 'plus', 0.0000, 0.0000),
('translate', 'premium', 0.0000, 0.0000),

-- AI Chat (paid for free users, discounted for plus/premium)
('chat', 'free', 0.0100, 1.0000),
('chat', 'plus', 0.0000, 0.8000),
('chat', 'premium', 0.0000, 0.6000),

-- Image generation (plus and premium only)
('image', 'plus', 0.0500, 0.8000),
('image', 'premium', 0.0300, 0.6000),

-- TTS (all users, different rates)
('tts', 'free', 0.0050, 1.0000),
('tts', 'plus', 0.0000, 0.8000),
('tts', 'premium', 0.0000, 0.6000)
ON CONFLICT (endpoint_name, min_account_type) DO NOTHING;

-- ============================================
-- CLEANUP FUNCTION
-- ============================================

CREATE OR REPLACE FUNCTION cleanup_expired_data()
RETURNS void AS $$
DECLARE
    deleted_tokens INTEGER;
    deleted_verifications INTEGER;
    deleted_logs INTEGER;
BEGIN
    -- Delete expired refresh tokens older than 7 days past expiry
    DELETE FROM auth.refresh_tokens 
    WHERE expires_at < NOW() - INTERVAL '7 days';
    GET DIAGNOSTICS deleted_tokens = ROW_COUNT;
    
    -- Delete expired email verifications
    DELETE FROM auth.email_verifications 
    WHERE expires_at < NOW() - INTERVAL '1 day';
    GET DIAGNOSTICS deleted_verifications = ROW_COUNT;
    
    -- Delete old audit logs (keep 90 days)
    DELETE FROM audit.logs 
    WHERE timestamp < NOW() - INTERVAL '90 days';
    GET DIAGNOSTICS deleted_logs = ROW_COUNT;
    
    -- Clear old AI cache entries
    DELETE FROM ai.cache_entries 
    WHERE expires_at < NOW() OR last_accessed_at < NOW() - INTERVAL '30 days';
    
    RAISE NOTICE 'Cleanup complete: % tokens, % verifications, % logs deleted', 
                 deleted_tokens, deleted_verifications, deleted_logs;
END;
$$ LANGUAGE plpgsql;

-- Schedule cleanup (use pg_cron in production)
-- SELECT cron.schedule('cleanup-expired-data', '0 3 * * *', 'SELECT cleanup_expired_data();');

-- ============================================
-- LANGUAGES TABLE AND DATA
-- ============================================

-- Create languages table in content schema
CREATE TABLE IF NOT EXISTS content.languages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(10) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    native_name VARCHAR(100),
    direction VARCHAR(3) DEFAULT 'ltr' CHECK (direction IN ('ltr', 'rtl')),
    is_active BOOLEAN DEFAULT TRUE,
    countries TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Insert language data (top 30 languages)
INSERT INTO content.languages (code, name, native_name, direction, countries) VALUES
-- Most spoken languages
('en', 'English', 'English', 'ltr', 'United States, United Kingdom, Canada, Australia, New Zealand, Ireland, South Africa'),
('zh', 'Chinese', '中文', 'ltr', 'China, Taiwan, Singapore, Malaysia'),
('hi', 'Hindi', 'हिन्दी', 'ltr', 'India, Fiji, Nepal, Mauritius'),
('es', 'Spanish', 'Español', 'ltr', 'Spain, Mexico, Colombia, Argentina, Peru, Venezuela, Chile'),
('fr', 'French', 'Français', 'ltr', 'France, Canada, Belgium, Switzerland, Haiti, Monaco'),
('ar', 'Arabic', 'العربية', 'rtl', 'Saudi Arabia, Egypt, Algeria, Sudan, Iraq, Morocco, Yemen'),
('bn', 'Bengali', 'বাংলা', 'ltr', 'Bangladesh, India'),
('ru', 'Russian', 'Русский', 'ltr', 'Russia, Belarus, Kazakhstan, Kyrgyzstan'),
('pt', 'Portuguese', 'Português', 'ltr', 'Portugal, Brazil, Angola, Mozambique'),
('ur', 'Urdu', 'اردو', 'rtl', 'Pakistan, India'),
('id', 'Indonesian', 'Bahasa Indonesia', 'ltr', 'Indonesia'),
('de', 'German', 'Deutsch', 'ltr', 'Germany, Austria, Switzerland, Luxembourg, Liechtenstein'),
('ja', 'Japanese', '日本語', 'ltr', 'Japan'),
('sw', 'Swahili', 'Kiswahili', 'ltr', 'Tanzania, Kenya, Uganda, Rwanda'),
('pa', 'Punjabi', 'ਪੰਜਾਬੀ', 'ltr', 'India, Pakistan'),
('jv', 'Javanese', 'Basa Jawa', 'ltr', 'Indonesia, Malaysia, Suriname'),
('tr', 'Turkish', 'Türkçe', 'ltr', 'Turkey, Northern Cyprus, Bulgaria'),
('ko', 'Korean', '한국어', 'ltr', 'South Korea, North Korea'),
('vi', 'Vietnamese', 'Tiếng Việt', 'ltr', 'Vietnam, Cambodia, Laos'),
('fa', 'Persian', 'فارسی', 'rtl', 'Iran, Afghanistan, Tajikistan'),

-- Additional European languages
('it', 'Italian', 'Italiano', 'ltr', 'Italy, San Marino, Vatican City, Switzerland'),
('pl', 'Polish', 'Polski', 'ltr', 'Poland'),
('uk', 'Ukrainian', 'Українська', 'ltr', 'Ukraine'),
('nl', 'Dutch', 'Nederlands', 'ltr', 'Netherlands, Belgium, Suriname'),
('el', 'Greek', 'Ελληνικά', 'ltr', 'Greece, Cyprus'),
('cs', 'Czech', 'Čeština', 'ltr', 'Czech Republic'),
('sv', 'Swedish', 'Svenska', 'ltr', 'Sweden, Finland'),
('hu', 'Hungarian', 'Magyar', 'ltr', 'Hungary'),
('ro', 'Romanian', 'Română', 'ltr', 'Romania, Moldova'),
('he', 'Hebrew', 'עברית', 'rtl', 'Israel')
ON CONFLICT (code) DO NOTHING;

-- ============================================
-- PRODUCTS TABLE FOR BACKEND
-- ============================================

CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_code VARCHAR(50) UNIQUE NOT NULL,
    product_name VARCHAR(255) NOT NULL,
    product_type VARCHAR(20) NOT NULL DEFAULT 'subscription' CHECK (product_type IN ('subscription', 'credit')),
    price DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'EUR',
    tokens INTEGER DEFAULT NULL,
    account_type VARCHAR(20) DEFAULT NULL CHECK (account_type IN ('free', 'plus', 'premium') OR account_type IS NULL),
    billing_period VARCHAR(10) DEFAULT NULL CHECK (billing_period IN ('month', 'year') OR billing_period IS NULL),
    features JSONB DEFAULT NULL,
    is_popular BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    discount_percentage INTEGER DEFAULT NULL,
    paddle_price_id VARCHAR(100) DEFAULT NULL,
    description TEXT DEFAULT NULL,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Insert product catalog
INSERT INTO public.products (
    product_code, product_name, product_type, price, currency, tokens, 
    account_type, billing_period, features, is_popular, discount_percentage,
    paddle_price_id, description, sort_order
) VALUES
-- Token bundles
('TOKENS_100', '100 Tokens', 'credit', 1.00, 'EUR', 100, NULL, NULL, NULL, false, NULL, 
 'prod_tokens_100', 'Perfect for trying out AI features', 1),
('TOKENS_500', '500 Tokens', 'credit', 4.50, 'EUR', 500, NULL, NULL, NULL, true, 10, 
 'prod_tokens_500', 'Best value for regular users', 2),
('TOKENS_1000', '1000 Tokens', 'credit', 8.50, 'EUR', 1000, NULL, NULL, NULL, false, 15, 
 'prod_tokens_1000', 'Great for power users', 3),

-- Monthly subscriptions
('PLUS_MONTHLY', 'Plus Plan', 'subscription', 2.45, 'EUR', NULL, 'plus', 'month', 
 '["Better AI models", "2000 images per deck", "Priority support"]'::jsonb, true, NULL, 
 'sub_plus_monthly', 'Perfect for regular language learners', 4),
('PREMIUM_MONTHLY', 'Premium Plan', 'subscription', 9.45, 'EUR', NULL, 'premium', 'month', 
 '["Best AI models", "Unlimited images", "Premium support"]'::jsonb, false, NULL, 
 'sub_premium_monthly', 'Ultimate language learning experience', 5),

-- Yearly subscriptions
('PLUS_YEARLY', 'Plus Plan (Yearly)', 'subscription', 20.58, 'EUR', NULL, 'plus', 'year', 
 '["Better AI models", "2000 images per deck", "Priority support", "30% discount"]'::jsonb, false, 30, 
 'sub_plus_yearly', 'Save 30% with yearly Plus subscription', 6),
('PREMIUM_YEARLY', 'Premium Plan (Yearly)', 'subscription', 79.38, 'EUR', NULL, 'premium', 'year', 
 '["Best AI models", "Unlimited images", "Premium support", "30% discount"]'::jsonb, false, 30, 
 'sub_premium_yearly', 'Save 30% with yearly Premium subscription', 7)
ON CONFLICT (product_code) DO NOTHING;

-- ============================================
-- SAMPLE LANGUAGE-SPECIFIC CONTENT
-- ============================================

-- Sample deck for German learning (using proper language codes)
UPDATE content.decks 
SET front_lang = (SELECT code FROM content.languages WHERE code = 'de'),
    back_lang = (SELECT code FROM content.languages WHERE code = 'en')
WHERE user_id = 'TEST0USER1';

-- Create additional sample decks for different languages
INSERT INTO content.decks (user_id, name, description, front_lang, back_lang, settings) VALUES
('DEMO0USER1', 'Spanish Basics', 'Essential Spanish vocabulary', 'es', 'en', 
 '{"preset": "casual", "shuffle": false}'::jsonb),
('DEMO0USER1', 'French Phrases', 'Common French expressions', 'fr', 'en', 
 '{"preset": "beginner", "shuffle": true}'::jsonb),
('TEST0USER1', 'Persian Poetry', 'Classical Persian poems with translations', 'fa', 'en', 
 '{"preset": "expert", "shuffle": false}'::jsonb);

-- ============================================
-- FINAL SETUP
-- ============================================

-- Create indexes for languages table
CREATE INDEX idx_languages_code ON content.languages(code);
CREATE INDEX idx_languages_active ON content.languages(is_active);

-- Analyze tables for query optimization
ANALYZE;

-- Show summary
SELECT 
    'Database initialization complete' as status,
    (SELECT COUNT(*) FROM public.users) as users,
    (SELECT COUNT(*) FROM content.decks) as decks,
    (SELECT COUNT(*) FROM content.cards) as cards,
    (SELECT COUNT(*) FROM ai.plugin_configs) as ai_plugins,
    (SELECT COUNT(*) FROM content.languages) as languages,
    (SELECT COUNT(*) FROM public.products) as products;