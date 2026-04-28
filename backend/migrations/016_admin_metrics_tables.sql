-- Migration 016: Admin metrics tables for operational dashboard

CREATE TABLE IF NOT EXISTS api_daily_stats (
    stat_date   DATE    NOT NULL,
    endpoint    TEXT    NOT NULL,
    method      TEXT    NOT NULL DEFAULT 'GET',
    call_count  INTEGER NOT NULL DEFAULT 0,
    error_count INTEGER NOT NULL DEFAULT 0,
    total_duration_ms BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (stat_date, endpoint, method)
);

CREATE TABLE IF NOT EXISTS external_api_daily_stats (
    stat_date    DATE    NOT NULL,
    service_name TEXT    NOT NULL,
    call_count   INTEGER NOT NULL DEFAULT 0,
    error_count  INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (stat_date, service_name)
);

CREATE TABLE IF NOT EXISTS user_daily_stats (
    stat_date   DATE    NOT NULL PRIMARY KEY,
    new_signups INTEGER NOT NULL DEFAULT 0,
    logins      INTEGER NOT NULL DEFAULT 0
);

-- Atomic increment for API request tracking
CREATE OR REPLACE FUNCTION track_api_call(
    p_endpoint    TEXT,
    p_method      TEXT,
    p_status_code INTEGER,
    p_duration_ms INTEGER
) RETURNS VOID AS $$
BEGIN
    INSERT INTO api_daily_stats
        (stat_date, endpoint, method, call_count, error_count, total_duration_ms)
    VALUES (
        CURRENT_DATE, p_endpoint, p_method, 1,
        CASE WHEN p_status_code >= 400 THEN 1 ELSE 0 END,
        p_duration_ms
    )
    ON CONFLICT (stat_date, endpoint, method) DO UPDATE SET
        call_count        = api_daily_stats.call_count + 1,
        error_count       = api_daily_stats.error_count
                            + CASE WHEN p_status_code >= 400 THEN 1 ELSE 0 END,
        total_duration_ms = api_daily_stats.total_duration_ms + p_duration_ms;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Atomic increment for external API tracking
CREATE OR REPLACE FUNCTION track_external_api_call(
    p_service TEXT,
    p_success BOOLEAN DEFAULT TRUE
) RETURNS VOID AS $$
BEGIN
    INSERT INTO external_api_daily_stats (stat_date, service_name, call_count, error_count)
    VALUES (CURRENT_DATE, p_service, 1, CASE WHEN p_success THEN 0 ELSE 1 END)
    ON CONFLICT (stat_date, service_name) DO UPDATE SET
        call_count  = external_api_daily_stats.call_count + 1,
        error_count = external_api_daily_stats.error_count
                      + CASE WHEN p_success THEN 0 ELSE 1 END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Atomic increment for user events
CREATE OR REPLACE FUNCTION track_user_event(p_event_type TEXT) RETURNS VOID AS $$
BEGIN
    INSERT INTO user_daily_stats (stat_date, new_signups, logins)
    VALUES (
        CURRENT_DATE,
        CASE WHEN p_event_type = 'signup' THEN 1 ELSE 0 END,
        CASE WHEN p_event_type = 'login'  THEN 1 ELSE 0 END
    )
    ON CONFLICT (stat_date) DO UPDATE SET
        new_signups = user_daily_stats.new_signups
                      + CASE WHEN p_event_type = 'signup' THEN 1 ELSE 0 END,
        logins      = user_daily_stats.logins
                      + CASE WHEN p_event_type = 'login'  THEN 1 ELSE 0 END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
