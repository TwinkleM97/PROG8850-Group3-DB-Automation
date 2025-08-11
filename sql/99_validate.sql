USE project_db;

-- Check table exists with correct columns
SHOW COLUMNS FROM ClimateData;

-- Verify humidity exists
SELECT COLUMN_NAME, IS_NULLABLE, COLUMN_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA='project_db'
  AND TABLE_NAME='ClimateData'
  AND COLUMN_NAME='humidity';

-- Seed count
SELECT COUNT(*) AS total_rows FROM ClimateData;

-- Sanity checks from concurrent ops will be printed by Python
