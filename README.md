# PROG8850 – Group 3 – Database Automation

## Overview
This project implements an **end-to-end automated database management system** with:
- CI/CD using GitHub Actions
- Automated schema creation, update, and data seeding
- Concurrent query execution for performance testing
- Advanced monitoring and logging with SigNoz

## Quick Start (One Command)
After a Codespace restart, run:
```bash
./setup_project.sh
```
Run this to generate the logs
```bash
# general log
mysql -h 127.0.0.1 -P 3307 -u root -pSecret5555 -e "USE project_db; SELECT COUNT(*) FROM ClimateData;"

# slow log — run 3–4 times
mysql -h 127.0.0.1 -P 3307 -u root -pSecret5555 -e '
USE project_db;
SELECT SQL_NO_CACHE * FROM ClimateData WHERE temperature > 10 ORDER BY RAND() LIMIT 1000;
'
```