# ⛽ Fuel Prices WebApp

**Website:** [blancostudio.dev/benzinai_italia](https://blancostudio.dev/benzinai_italia)  

This project provides a **web application** to check **real-time fuel prices in Italy**, updated daily using official open data from the Italian Ministry of Enterprises and Made in Italy (MIMIT).  

Data is refreshed automatically every morning at **09:00 CET** by a Bash script that downloads, validates, and installs the latest datasets.

---

## 🚀 Features
- Real-time fuel prices by **city, street or location**
- Advanced search by:
  - lowest price  
  - distance from your position  
  - fuel type  
- Interactive map with markers for each gas station  
- Dedicated station pages with full details and **Google Maps integration**  

---

## 🛠️ Backend: Data Updater Script
The backend consists of a **Bash script** (`fuel_data_updater.sh`) that:
1. Downloads the latest CSV files from the [MIMIT Open Data portal](https://www.mimit.gov.it/it/open-data/elenco-dataset/carburanti-prezzi-praticati-e-anagrafica-degli-impianti).
   - `anagrafica_impianti_attivi.csv` (list of active fuel stations)  
   - `prezzo_alle_8.csv` (fuel prices as of 8:00 AM)  
2. Validates the integrity of the CSV files.  
3. Creates backups of existing data (kept for 7 days).  
4. Installs the updated files into the website directory.  
5. Logs all operations in `/var/log/fuel_data_updater.log`.  
6. Optionally sends notifications (via email) on success or failure.  

---

## 📂 File Structure
- `/var/www/blancostudio.dev/public_html/benzinai_italia` → Public web directory  
- `/tmp/fuel_data_YYYYMMDD_HHMMSS` → Temporary download folder  
- `/var/log/fuel_data_updater.log` → Update log file  
- `backup_*.csv` → Daily backups (kept for 7 days)  
- `last_update.txt` → Timestamp of last successful update  

---

## ⚡ Automation
The script is executed daily at **09:00** via `cron`. Example crontab entry:

```bash
0 9 * * * /path/to/fuel_data_updater.sh >> /var/log/fuel_data_updater.log 2>&1
