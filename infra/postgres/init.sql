-- Conectar a la base de datos correcta
\c price_monitor;

-- ========================================
-- 1. EXTENSIONES
-- ========================================
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS uuid-ossp;

-- ========================================
-- 2. FUNCIONES Y TRIGGERS
-- ========================================

-- Función para actualizar updated_at automáticamente
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Función para calcular cambio de precio
CREATE OR REPLACE FUNCTION calculate_price_change()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.current_price IS NOT NULL AND NEW.current_price IS NOT NULL THEN
        NEW.price_change = NEW.current_price - OLD.current_price;
        NEW.price_change_percent = (NEW.price_change / OLD.current_price) * 100;
        
        -- Actualizar lowest/highest prices
        IF NEW.current_price < OLD.lowest_price OR OLD.lowest_price IS NULL THEN
            NEW.lowest_price = NEW.current_price;
        END IF;
        
        IF NEW.current_price > OLD.highest_price OR OLD.highest_price IS NULL THEN
            NEW.highest_price = NEW.current_price;
        END IF;
        
        -- Actualizar average price (promedio móvil)
        NEW.average_price = (
            SELECT AVG(price) 
            FROM price_history 
            WHERE product_id = NEW.id 
            AND scraped_at >= NOW() - INTERVAL '30 days'
        );
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Función para verificar alertas automáticamente
CREATE OR REPLACE FUNCTION check_price_alerts()
RETURNS TRIGGER AS $$
BEGIN
    -- Insertar alertas cuando el precio baja del target
    INSERT INTO alerts (id, user_id, product_id, type, status, trigger_price, current_price, message, created_at)
    SELECT 
        gen_random_uuid(),
        p.user_id,
        p.id,
        'PRICE_TARGET',
        'PENDING',
        p.target_price,
        NEW.current_price,
        CONCAT('🎯 El producto "', p.name, '" ha bajado a ', NEW.current_price, ' ', NEW.currency),
        CURRENT_TIMESTAMP
    FROM products p
    WHERE p.id = NEW.product_id
        AND p.target_price IS NOT NULL
        AND NEW.current_price <= p.target_price
        AND p.is_active = true
        AND NOT EXISTS (
            SELECT 1 FROM alerts a 
            WHERE a.product_id = p.id 
            AND a.type = 'PRICE_TARGET' 
            AND a.status = 'PENDING'
            AND a.created_at > NOW() - INTERVAL '24 hours'
        );
    
    -- Insertar alertas de cambio significativo (>5%)
    IF OLD.current_price IS NOT NULL AND NEW.current_price IS NOT NULL THEN
        IF ABS(NEW.current_price - OLD.current_price) / OLD.current_price > 0.05 THEN
            INSERT INTO alerts (id, user_id, product_id, type, status, trigger_price, current_price, message, created_at)
            SELECT 
                gen_random_uuid(),
                p.user_id,
                p.id,
                'PRICE_CHANGE',
                'PENDING',
                OLD.current_price,
                NEW.current_price,
                CONCAT('📊 El precio de "', p.name, '" ha cambiado en un ', 
                       ROUND(ABS((NEW.current_price - OLD.current_price) / OLD.current_price * 100), 2), 
                       '% (', OLD.current_price, ' → ', NEW.current_price, ' ', NEW.currency, ')'),
                CURRENT_TIMESTAMP
            FROM products p
            WHERE p.id = NEW.product_id
                AND p.is_active = true;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Función para limpiar datos viejos
CREATE OR REPLACE FUNCTION cleanup_old_data()
RETURNS void AS $$
BEGIN
    -- Mantener solo 1 año de historial de precios
    DELETE FROM price_history 
    WHERE scraped_at < NOW() - INTERVAL '1 year';
    
    -- Mantener solo 6 meses de logs
    DELETE FROM usage_logs 
    WHERE created_at < NOW() - INTERVAL '6 months';
    
    -- Mantener solo 3 meses de notificaciones
    DELETE FROM notifications 
    WHERE created_at < NOW() - INTERVAL '3 months';
    
    -- Cerrar scraping jobs viejos
    UPDATE scraping_jobs 
    SET status = 'failed', 
        error = 'Job expired due to timeout'
    WHERE status IN ('pending', 'in_progress')
        AND created_at < NOW() - INTERVAL '24 hours';
    
    RAISE NOTICE 'Cleanup completed at %', NOW();
END;
$$ language 'plpgsql';

-- ========================================
-- 3. TABLAS - CORE
-- ========================================

-- Tabla: users
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    name VARCHAR(100),
    telegram_id VARCHAR(50) UNIQUE,
    telegram_username VARCHAR(100),
    phone_number VARCHAR(20),
    role VARCHAR(20) DEFAULT 'USER' CHECK (role IN ('USER', 'ADMIN')),
    subscription_tier VARCHAR(20) DEFAULT 'FREE' CHECK (subscription_tier IN ('FREE', 'PRO', 'ENTERPRISE')),
    max_products INT DEFAULT 3,
    notification_preferences JSONB DEFAULT '{"email": true, "telegram": false, "webhook": false}'::jsonb,
    is_active BOOLEAN DEFAULT true,
    last_login_at TIMESTAMP,
    email_verified BOOLEAN DEFAULT false,
    verification_token VARCHAR(255),
    reset_password_token VARCHAR(255),
    reset_password_expires TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabla: user_settings
CREATE TABLE IF NOT EXISTS user_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    theme VARCHAR(20) DEFAULT 'dark',
    language VARCHAR(10) DEFAULT 'en',
    timezone VARCHAR(50) DEFAULT 'UTC',
    currency VARCHAR(3) DEFAULT 'USD',
    dashboard_layout JSONB DEFAULT '{"widgets": ["priceAlerts", "recentProducts", "priceHistory"]}'::jsonb,
    email_digest BOOLEAN DEFAULT true,
    digest_frequency VARCHAR(20) DEFAULT 'daily' CHECK (digest_frequency IN ('daily', 'weekly', 'monthly')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabla: products
CREATE TABLE IF NOT EXISTS products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    url TEXT NOT NULL,
    platform VARCHAR(20) NOT NULL CHECK (platform IN ('AMAZON', 'MERCADOLIBRE', 'EBAY', 'WALMART', 'OTHER')),
    product_id VARCHAR(255), -- ID del producto en la plataforma
    name VARCHAR(255) NOT NULL,
    description TEXT,
    image_url TEXT,
    category VARCHAR(100),
    brand VARCHAR(100),
    sku VARCHAR(100),
    upc VARCHAR(100),
    target_price DECIMAL(10,2),
    current_price DECIMAL(10,2),
    previous_price DECIMAL(10,2),
    price_change DECIMAL(10,2),
    price_change_percent DECIMAL(5,2),
    currency VARCHAR(3) DEFAULT 'USD',
    lowest_price DECIMAL(10,2),
    highest_price DECIMAL(10,2),
    average_price DECIMAL(10,2),
    is_available BOOLEAN DEFAULT true,
    stock_status VARCHAR(20) CHECK (stock_status IN ('IN_STOCK', 'OUT_OF_STOCK', 'LIMITED', 'UNKNOWN')),
    rating DECIMAL(3,2),
    reviews_count INT,
    last_check_at TIMESTAMP,
    next_check_at TIMESTAMP,
    check_frequency VARCHAR(20) DEFAULT '6h',
    is_active BOOLEAN DEFAULT true,
    webhook_url TEXT,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, url)
);

-- Tabla: price_history (TimescaleDB)
CREATE TABLE IF NOT EXISTS price_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    price DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    is_available BOOLEAN DEFAULT true,
    stock_status VARCHAR(20) CHECK (stock_status IN ('IN_STOCK', 'OUT_OF_STOCK', 'LIMITED', 'UNKNOWN')),
    scraped_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabla: alerts
CREATE TABLE IF NOT EXISTS alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(id) ON DELETE SET NULL,
    type VARCHAR(20) NOT NULL CHECK (type IN ('PRICE_DROP', 'PRICE_TARGET', 'RESTOCK', 'PRICE_CHANGE')),
    status VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'SENT', 'FAILED', 'CANCELLED')),
    trigger_price DECIMAL(10,2),
    current_price DECIMAL(10,2),
    message TEXT NOT NULL,
    metadata JSONB,
    sent_at TIMESTAMP,
    read_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabla: notifications
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    alert_id UUID REFERENCES alerts(id) ON DELETE SET NULL,
    product_id UUID REFERENCES products(id) ON DELETE SET NULL,
    channel VARCHAR(20) NOT NULL CHECK (channel IN ('EMAIL', 'TELEGRAM', 'WEBHOOK', 'PUSH')),
    channel_id VARCHAR(255), -- Email, Telegram chat ID, etc
    subject VARCHAR(255),
    content TEXT NOT NULL,
    status VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'SENT', 'DELIVERED', 'FAILED')),
    error_message TEXT,
    sent_at TIMESTAMP,
    delivered_at TIMESTAMP,
    read_at TIMESTAMP,
    retry_count INT DEFAULT 0,
    max_retries INT DEFAULT 3,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ========================================
-- 4. TABLAS - EXTRA (para futuras funcionalidades)
-- ========================================

-- Tabla: webhooks
CREATE TABLE IF NOT EXISTS webhooks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    url TEXT NOT NULL,
    secret VARCHAR(255),
    events TEXT[] NOT NULL, -- ['price_drop', 'price_target', 'restock']
    is_active BOOLEAN DEFAULT true,
    last_triggered_at TIMESTAMP,
    failure_count INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, url)
);

-- Tabla: api_keys
CREATE TABLE IF NOT EXISTS api_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    key VARCHAR(255) UNIQUE NOT NULL,
    permissions TEXT[] NOT NULL, -- ['read:products', 'write:alerts', etc]
    last_used_at TIMESTAMP,
    expires_at TIMESTAMP,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabla: scraping_jobs
CREATE TABLE IF NOT EXISTS scraping_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    status VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'IN_PROGRESS', 'COMPLETED', 'FAILED')),
    result JSONB,
    error TEXT,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    retry_count INT DEFAULT 0,
    priority INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabla: usage_logs
CREATE TABLE IF NOT EXISTS usage_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    endpoint VARCHAR(255),
    method VARCHAR(10),
    status_code INT,
    response_time INT,
    ip_address VARCHAR(45),
    user_agent TEXT,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabla: payments
CREATE TABLE IF NOT EXISTS payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    stripe_id VARCHAR(255) UNIQUE,
    paypal_id VARCHAR(255) UNIQUE,
    amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    status VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'COMPLETED', 'FAILED', 'REFUNDED')),
    subscription_id VARCHAR(255),
    plan VARCHAR(50),
    description TEXT,
    payment_method VARCHAR(50),
    metadata JSONB,
    paid_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ========================================
-- 5. TRIGGERS
-- ========================================

-- Triggers para updated_at
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_settings_updated_at
    BEFORE UPDATE ON user_settings
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_products_updated_at
    BEFORE UPDATE ON products
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_alerts_updated_at
    BEFORE UPDATE ON alerts
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_notifications_updated_at
    BEFORE UPDATE ON notifications
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_webhooks_updated_at
    BEFORE UPDATE ON webhooks
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_api_keys_updated_at
    BEFORE UPDATE ON api_keys
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_scraping_jobs_updated_at
    BEFORE UPDATE ON scraping_jobs
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_payments_updated_at
    BEFORE UPDATE ON payments
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Triggers para cálculos de precio
CREATE TRIGGER calculate_price_change_trigger
    BEFORE UPDATE ON products
    FOR EACH ROW
    WHEN (OLD.current_price IS DISTINCT FROM NEW.current_price)
    EXECUTE FUNCTION calculate_price_change();

-- Triggers para alertas automáticas
CREATE TRIGGER check_price_alerts_trigger
    AFTER UPDATE OF current_price ON products
    FOR EACH ROW
    WHEN (OLD.current_price IS DISTINCT FROM NEW.current_price)
    EXECUTE FUNCTION check_price_alerts();

-- ========================================
-- 6. CONFIGURACIÓN DE TIMESCALEDB
-- ========================================

-- Convertir price_history a hypertable
SELECT create_hypertable(
    'price_history', 
    'scraped_at',
    chunk_time_interval => INTERVAL '1 week',
    if_not_exists => TRUE
);

-- Configurar compresión
ALTER TABLE price_history SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'product_id',
    timescaledb.compress_orderby = 'scraped_at DESC'
);

-- Política de compresión (comprimir después de 30 días)
SELECT add_compression_policy(
    'price_history', 
    INTERVAL '30 days',
    if_not_exists => TRUE
);

-- Política de retención (eliminar después de 1 año)
SELECT add_retention_policy(
    'price_history', 
    INTERVAL '1 year',
    if_not_exists => TRUE
);

-- ========================================
-- 7. ÍNDICES PARA OPTIMIZACIÓN
-- ========================================

-- Índices para users
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_telegram_id ON users(telegram_id) WHERE telegram_id IS NOT NULL;
CREATE INDEX idx_users_subscription_tier ON users(subscription_tier);

-- Índices para products
CREATE INDEX idx_products_user_active ON products(user_id, is_active);
CREATE INDEX idx_products_platform ON products(platform);
CREATE INDEX idx_products_last_check ON products(last_check_at);
CREATE INDEX idx_products_current_price ON products(current_price);
CREATE INDEX idx_products_is_active ON products(is_active) WHERE is_active = true;

-- Índices para price_history
CREATE INDEX idx_price_history_product_time ON price_history(product_id, scraped_at DESC);
CREATE INDEX idx_price_history_scraped_at ON price_history(scraped_at DESC);

-- Índices para alerts
CREATE INDEX idx_alerts_user_status ON alerts(user_id, status);
CREATE INDEX idx_alerts_product_id ON alerts(product_id) WHERE product_id IS NOT NULL;
CREATE INDEX idx_alerts_created_at ON alerts(created_at DESC);

-- Índices para notifications
CREATE INDEX idx_notifications_user_status ON notifications(user_id, status);
CREATE INDEX idx_notifications_alert_id ON notifications(alert_id) WHERE alert_id IS NOT NULL;
CREATE INDEX idx_notifications_created_at ON notifications(created_at DESC);

-- Índices para scraping_jobs
CREATE INDEX idx_scraping_jobs_status_priority ON scraping_jobs(status, priority);
CREATE INDEX idx_scraping_jobs_product_id ON scraping_jobs(product_id);

-- Índices para usage_logs
CREATE INDEX idx_usage_logs_user_time ON usage_logs(user_id, created_at DESC);
CREATE INDEX idx_usage_logs_created_at ON usage_logs(created_at DESC);

-- Índices para webhooks
CREATE INDEX idx_webhooks_user_active ON webhooks(user_id, is_active);

-- Índices para api_keys
CREATE INDEX idx_api_keys_key ON api_keys(key);
CREATE INDEX idx_api_keys_user_active ON api_keys(user_id, is_active);

-- Índices para payments
CREATE INDEX idx_payments_user_id ON payments(user_id);
CREATE INDEX idx_payments_status ON payments(status);

-- ========================================
-- 8. VISTAS ÚTILES
-- ========================================

-- Vista: Productos con estadísticas de precio
CREATE OR REPLACE VIEW product_price_stats AS
SELECT 
    p.id,
    p.user_id,
    p.name,
    p.current_price,
    p.target_price,
    p.currency,
    p.is_active,
    (
        SELECT price
        FROM price_history
        WHERE product_id = p.id
        ORDER BY scraped_at DESC
        LIMIT 1
    ) AS latest_price,
    (
        SELECT AVG(price)
        FROM price_history
        WHERE product_id = p.id
            AND scraped_at >= NOW() - INTERVAL '30 days'
    ) AS avg_price_30d,
    (
        SELECT MIN(price)
        FROM price_history
        WHERE product_id = p.id
            AND scraped_at >= NOW() - INTERVAL '30 days'
    ) AS min_price_30d,
    (
        SELECT MAX(price)
        FROM price_history
        WHERE product_id = p.id
            AND scraped_at >= NOW() - INTERVAL '30 days'
    ) AS max_price_30d,
    (
        SELECT COUNT(*)
        FROM alerts a
        WHERE a.product_id = p.id
            AND a.status = 'PENDING'
    ) AS pending_alerts_count
FROM products p
WHERE p.is_active = true;

-- Vista: Alertas pendientes por usuario
CREATE OR REPLACE VIEW pending_alerts_by_user AS
SELECT 
    u.id AS user_id,
    u.email,
    u.telegram_id,
    COUNT(a.id) AS pending_count,
    JSON_AGG(
        JSON_BUILD_OBJECT(
            'product_name', p.name,
            'type', a.type,
            'message', a.message,
            'created_at', a.created_at
        )
    ) AS alerts
FROM users u
LEFT JOIN alerts a ON u.id = a.user_id AND a.status = 'PENDING'
LEFT JOIN products p ON a.product_id = p.id
GROUP BY u.id, u.email, u.telegram_id
HAVING COUNT(a.id) > 0;

-- ========================================
-- 9. DATOS DE PRUEBA (OPCIONAL)
-- ========================================

-- Insertar usuario de prueba
INSERT INTO users (
    id,
    email,
    password_hash,
    name,
    subscription_tier,
    max_products,
    is_active,
    email_verified
) VALUES (
    '11111111-1111-1111-1111-111111111111',
    'demo@example.com',
    '$2a$10$N9qo8uLOickgx2ZMRZoMy.Mr/.Zq2Nn7n7XsM3F/f5DnIYkR3qH2W', -- password: Demo123!
    'Demo User',
    'PRO',
    10,
    true,
    true
) ON CONFLICT (email) DO NOTHING;

-- Insertar productos de prueba
INSERT INTO products (
    id,
    user_id,
    url,
    platform,
    name,
    target_price,
    current_price,
    currency,
    is_active
) VALUES 
(
    '22222222-2222-2222-2222-222222222222',
    '11111111-1111-1111-1111-111111111111',
    'https://www.amazon.com/dp/B09XS7JWHH',
    'AMAZON',
    'Sony WH-1000XM5 Wireless Headphones',
    299.99,
    349.99,
    'USD',
    true
),
(
    '33333333-3333-3333-3333-333333333333',
    '11111111-1111-1111-1111-111111111111',
    'https://www.amazon.com/dp/B0CM5J9L7Z',
    'AMAZON',
    'Apple MacBook Pro 14" M3',
    1599.99,
    1799.99,
    'USD',
    true
),
(
    '44444444-4444-4444-4444-444444444444',
    '11111111-1111-1111-1111-111111111111',
    'https://www.mercadolibre.com/nike-air-max-270',
    'MERCADOLIBRE',
    'Nike Air Max 270 Running Shoes',
    129.99,
    149.99,
    'USD',
    true
) ON CONFLICT (user_id, url) DO NOTHING;

-- Insertar historial de precios (últimos 30 días)
INSERT INTO price_history (product_id, price, scraped_at)
SELECT 
    '22222222-2222-2222-2222-222222222222',
    349.99 - (random() * 50),
    NOW() - (generate_series || ' days')::interval
FROM generate_series(0, 30)
ON CONFLICT DO NOTHING;

INSERT INTO price_history (product_id, price, scraped_at)
SELECT 
    '33333333-3333-3333-3333-333333333333',
    1799.99 - (random() * 200),
    NOW() - (generate_series || ' days')::interval
FROM generate_series(0, 30)
ON CONFLICT DO NOTHING;

INSERT INTO price_history (product_id, price, scraped_at)
SELECT 
    '44444444-4444-4444-4444-444444444444',
    149.99 - (random() * 30),
    NOW() - (generate_series || ' days')::interval
FROM generate_series(0, 30)
ON CONFLICT DO NOTHING;

-- Insertar configuración de usuario
INSERT INTO user_settings (user_id, theme, language, timezone)
VALUES (
    '11111111-1111-1111-1111-111111111111',
    'dark',
    'en',
    'America/New_York'
) ON CONFLICT (user_id) DO NOTHING;

-- ========================================
-- 10. MENSAJE DE CONFIRMACIÓN
-- ========================================

DO $$
BEGIN
    RAISE NOTICE 'Database initialization completed successfully!';
    RAISE NOTICE 'Tables created: %', (
        SELECT COUNT(*) 
        FROM information_schema.tables 
        WHERE table_schema = 'public'
    );
    RAISE NOTICE 'Demo user created: demo@example.com / Demo123!';
    RAISE NOTICE 'Demo products created: 3';
    RAISE NOTICE 'Price history entries created: 93';
END $$;