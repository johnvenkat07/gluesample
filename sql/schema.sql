-- ====================================================
-- AWS Glue ETL Pipeline Database Schema
-- ====================================================
-- This schema supports intelligent concurrency control
-- and efficient data processing for school Excel files

-- ====================================================
-- 1. CONCURRENCY CONTROL TABLES
-- ====================================================

-- Processing locks table for school-based concurrency
CREATE TABLE IF NOT EXISTS processing_locks (
    lock_id SERIAL PRIMARY KEY,
    school_id VARCHAR(20) NOT NULL,
    batch_id VARCHAR(50) NOT NULL,
    lock_type VARCHAR(20) DEFAULT 'PROCESSING',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NOT NULL,
    status VARCHAR(20) DEFAULT 'ACTIVE',
    created_by VARCHAR(100),
    UNIQUE(school_id, lock_type)
);

-- Index for fast lock checks
CREATE INDEX IF NOT EXISTS idx_processing_locks_school 
ON processing_locks(school_id, status, expires_at);

-- ====================================================
-- 2. AUDIT AND TRACKING TABLES
-- ====================================================

-- Batch processing history
CREATE TABLE IF NOT EXISTS batch_history (
    batch_id VARCHAR(50) PRIMARY KEY,
    school_id VARCHAR(20) NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    file_size_mb DECIMAL(10,2),
    total_records INTEGER,
    processing_status VARCHAR(20) DEFAULT 'STARTED',
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    error_message TEXT,
    step_function_arn VARCHAR(500),
    created_by VARCHAR(100)
);

-- Processing steps tracking
CREATE TABLE IF NOT EXISTS processing_steps (
    step_id SERIAL PRIMARY KEY,
    batch_id VARCHAR(50) NOT NULL,
    step_name VARCHAR(50) NOT NULL,
    step_status VARCHAR(20) DEFAULT 'PENDING',
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    records_processed INTEGER DEFAULT 0,
    error_message TEXT,
    glue_job_name VARCHAR(100),
    glue_job_run_id VARCHAR(100),
    FOREIGN KEY (batch_id) REFERENCES batch_history(batch_id)
);

-- ====================================================
-- 3. RAW DATA TABLES (Excel ingestion)
-- ====================================================

-- Raw data from Excel sheets (dynamic structure)
CREATE TABLE IF NOT EXISTS raw_data (
    raw_id SERIAL PRIMARY KEY,
    batch_id VARCHAR(50) NOT NULL,
    school_id VARCHAR(20) NOT NULL,
    sheet_name VARCHAR(100) NOT NULL,
    row_number INTEGER NOT NULL,
    column_name VARCHAR(100) NOT NULL,
    column_value TEXT,
    data_type VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (batch_id) REFERENCES batch_history(batch_id)
);

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_raw_data_batch 
ON raw_data(batch_id, school_id, is_active);

CREATE INDEX IF NOT EXISTS idx_raw_data_sheet 
ON raw_data(school_id, sheet_name, is_active);

-- ====================================================
-- 4. TRANSFORMED DATA TABLES (Business Logic Applied)
-- ====================================================

-- Students table
CREATE TABLE IF NOT EXISTS actual_students (
    student_id SERIAL PRIMARY KEY,
    batch_id VARCHAR(50) NOT NULL,
    school_id VARCHAR(20) NOT NULL,
    student_number VARCHAR(50),
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    date_of_birth DATE,
    grade_level VARCHAR(10),
    enrollment_status VARCHAR(20),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (batch_id) REFERENCES batch_history(batch_id)
);

-- Teachers table
CREATE TABLE IF NOT EXISTS actual_teachers (
    teacher_id SERIAL PRIMARY KEY,
    batch_id VARCHAR(50) NOT NULL,
    school_id VARCHAR(20) NOT NULL,
    employee_id VARCHAR(50),
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    subject VARCHAR(100),
    department VARCHAR(100),
    hire_date DATE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (batch_id) REFERENCES batch_history(batch_id)
);

-- Classes table
CREATE TABLE IF NOT EXISTS actual_classes (
    class_id SERIAL PRIMARY KEY,
    batch_id VARCHAR(50) NOT NULL,
    school_id VARCHAR(20) NOT NULL,
    class_code VARCHAR(50),
    class_name VARCHAR(200),
    teacher_id INTEGER,
    grade_level VARCHAR(10),
    max_students INTEGER,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (batch_id) REFERENCES batch_history(batch_id),
    FOREIGN KEY (teacher_id) REFERENCES actual_teachers(teacher_id)
);

-- ====================================================
-- 5. STORED PROCEDURES FOR CONCURRENCY CONTROL
-- ====================================================

-- Function to acquire processing lock
CREATE OR REPLACE FUNCTION acquire_processing_lock(
    p_school_id VARCHAR(20),
    p_batch_id VARCHAR(50),
    p_lock_ttl_hours INTEGER DEFAULT 4
) RETURNS BOOLEAN AS $$
DECLARE
    lock_acquired BOOLEAN := FALSE;
BEGIN
    -- Clean up expired locks first
    DELETE FROM processing_locks 
    WHERE expires_at < CURRENT_TIMESTAMP;
    
    -- Try to acquire lock
    BEGIN
        INSERT INTO processing_locks (school_id, batch_id, expires_at, created_by)
        VALUES (
            p_school_id, 
            p_batch_id, 
            CURRENT_TIMESTAMP + INTERVAL '1 hour' * p_lock_ttl_hours,
            'lambda_trigger'
        );
        lock_acquired := TRUE;
    EXCEPTION 
        WHEN unique_violation THEN
            lock_acquired := FALSE;
    END;
    
    RETURN lock_acquired;
END;
$$ LANGUAGE plpgsql;

-- Function to release processing lock
CREATE OR REPLACE FUNCTION release_processing_lock(
    p_school_id VARCHAR(20),
    p_batch_id VARCHAR(50)
) RETURNS BOOLEAN AS $$
DECLARE
    rows_deleted INTEGER;
BEGIN
    DELETE FROM processing_locks 
    WHERE school_id = p_school_id AND batch_id = p_batch_id;
    
    GET DIAGNOSTICS rows_deleted = ROW_COUNT;
    RETURN rows_deleted > 0;
END;
$$ LANGUAGE plpgsql;

-- Function to soft delete old school data
CREATE OR REPLACE FUNCTION purge_school_data(
    p_school_id VARCHAR(20)
) RETURNS INTEGER AS $$
DECLARE
    records_updated INTEGER := 0;
BEGIN
    -- Soft delete from raw_data
    UPDATE raw_data 
    SET is_active = FALSE 
    WHERE school_id = p_school_id AND is_active = TRUE;
    GET DIAGNOSTICS records_updated = ROW_COUNT;
    
    -- Soft delete from actual tables
    UPDATE actual_students 
    SET is_active = FALSE 
    WHERE school_id = p_school_id AND is_active = TRUE;
    
    UPDATE actual_teachers 
    SET is_active = FALSE 
    WHERE school_id = p_school_id AND is_active = TRUE;
    
    UPDATE actual_classes 
    SET is_active = FALSE 
    WHERE school_id = p_school_id AND is_active = TRUE;
    
    RETURN records_updated;
END;
$$ LANGUAGE plpgsql;

-- ====================================================
-- 6. MONITORING AND HEALTH CHECK VIEWS
-- ====================================================

-- Active processing locks view
CREATE OR REPLACE VIEW active_processing_locks AS
SELECT 
    school_id,
    batch_id,
    created_at,
    expires_at,
    EXTRACT(EPOCH FROM (expires_at - CURRENT_TIMESTAMP))/60 as minutes_until_expiry
FROM processing_locks
WHERE status = 'ACTIVE' AND expires_at > CURRENT_TIMESTAMP;

-- Processing status summary view
CREATE OR REPLACE VIEW processing_status_summary AS
SELECT 
    bh.school_id,
    bh.batch_id,
    bh.file_name,
    bh.processing_status,
    bh.started_at,
    bh.completed_at,
    COUNT(ps.step_id) as total_steps,
    SUM(CASE WHEN ps.step_status = 'COMPLETED' THEN 1 ELSE 0 END) as completed_steps,
    SUM(ps.records_processed) as total_records_processed
FROM batch_history bh
LEFT JOIN processing_steps ps ON bh.batch_id = ps.batch_id
GROUP BY bh.school_id, bh.batch_id, bh.file_name, bh.processing_status, bh.started_at, bh.completed_at;

-- ====================================================
-- 7. INITIAL DATA AND CONFIGURATION
-- ====================================================

-- Clean up any existing test data
-- This would be run during deployment
-- DELETE FROM processing_locks WHERE school_id LIKE 'TEST%';