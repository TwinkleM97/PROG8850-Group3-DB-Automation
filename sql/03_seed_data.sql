USE project_db;

INSERT INTO ClimateData (location, record_date, temperature, precipitation, humidity) VALUES
('Ottawa',       '2025-07-01', 28.4,  3.2,  65.0),
('Ottawa',       '2025-07-02', 29.1,  0.0,  58.0),
('Toronto',      '2025-07-01', 30.2,  1.0,  62.0),
('Toronto',      '2025-07-02', 27.9,  6.1,  70.0),
('Montreal',     '2025-07-01', 26.3,  4.5,  68.0),
('Montreal',     '2025-07-02', 25.0,  0.0,  55.0),
('Vancouver',    '2025-07-01', 22.1,  7.4,  78.0),
('Vancouver',    '2025-07-02', 23.0,  2.2,  74.0),
('Calgary',      '2025-07-01', 24.5,  0.0,  40.0),
('Calgary',      '2025-07-02', 25.1,  0.0,  35.0);
