CREATE DATABASE IF NOT EXISTS project_db;
USE project_db;

DROP TABLE IF EXISTS ClimateData;

CREATE TABLE ClimateData (
  record_id INT PRIMARY KEY AUTO_INCREMENT,
  location VARCHAR(100) NOT NULL,
  record_date DATE NOT NULL,
  temperature FLOAT NOT NULL,
  precipitation FLOAT NOT NULL
);
