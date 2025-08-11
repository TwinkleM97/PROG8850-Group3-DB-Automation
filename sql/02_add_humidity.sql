USE project_db;
ALTER TABLE ClimateData
  ADD COLUMN humidity FLOAT NOT NULL DEFAULT 0.0;
