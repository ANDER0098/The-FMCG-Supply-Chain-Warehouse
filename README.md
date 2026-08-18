# FMCG Supply Chain Integrity Engine: Exposing the Primary-Secondary Sales Gap

## 📖 Project Overview

In the Fast-Moving Consumer Goods (FMCG) and Consumer Packaged Goods (CPG) sectors, the gap between **Primary Sales** (what a company ships to a distributor) and **Secondary Sales** (what the distributor claims to sell to retailers/Kiranas) is a multi-million dollar blind spot. 

This gap isn't just a software bug or a data delay; it is a human behavioral problem rooted in physical reality. Distributors may hoard promotional stock, falsify delivery routes to save fuel, or be forced into buying excess inventory to meet sales targets. 

This project is an **Analytical Data Engine** designed to mathematically corner these discrepancies. By modeling specific human behaviors and identifying anomalies in the supply chain data, this engine exposes the truth behind inventory movement.

## 🏗️ Core Architecture

The architecture relies on trapping discrepancies across three distinct metrics:

| Source System | Table | What it Measures | The "Lie" Factor |
| :--- | :--- | :--- | :--- |
| **Company ERP (SAP/Oracle)** | `fact_primary_sales` | What left the factory and hit the distributor's warehouse. | **Very Low.** Tied to revenue and tax. |
| **Distributor App (DMS)** | `fact_secondary_sales` | What the distributor claims they sold to the Kirana store. | **High.** Prone to falsified dates and bulk-billing. |
| **Automated ETL Output** | `fact_stock_reconciliation` | The daily mathematical truth: *(Opening Stock + Primary) - Secondary*. | **None.** This is where the gaps are exposed. |

### Dimension Tables
To support the analytical queries, the warehouse will include:
* `dim_date`, `dim_distributor`, `dim_kirana`, `dim_product`, `dim_promotion`

## 🎯 Key Analytical Objectives (The Blind Spots)

This engine is built to solve three specific problems using advanced SQL:

1. **Channel Stuffing Detection:** Identifying spikes in primary sales at month-end without corresponding secondary sales growth, indicating inventory dumping rather than actual growth.
2. **The Promotion Leakage Trap:** Flagging instances where secondary sales of a promoted SKU drop to zero during a promo window, only to spike at full price immediately after.
3. **Route/Beat Falsification:** Detecting impossible delivery metrics (e.g., massive bulk drops to a single rural retailer) that indicate a distributor is skipping routes to save logistics costs.

## 📊 Results (Blind Detection Run)

The engine screened all 20 distributors with no knowledge of who the planted anomalies were — and flagged exactly the three:

| Distributor | Fraud Detected | Key Evidence | Score / Tier |
| :--- | :--- | :--- | :--- |
| **DIST005** | Channel Stuffing | 5 month-ends buying 8–20× his normal volume while secondary sales stayed flat (611 vs a 635/day average) | **40 — HIGH** |
| **DIST012** | Route Falsification | 168 bulk drops of 100–300 units to single kirana shops — 29.7% of his entire volume (z-score 8.5) | **30 — HIGH** |
| **DIST018** | Promotion Leakage | Zero sales during the 20% promo while holding 91,499 units in stock, then a 3×-baseline dump the morning after it ended | **30 — HIGH** |

16 distributors scored CLEAN; one honest distributor showed a single mild statistical flag (MEDIUM — a routine check, exactly how a real investigate-list should behave).

![Ranked risk list](reports/charts/risk_ranking.png)

*Open `reports/dashboard.html` for the full Regional Sales Manager dashboard — one self-contained file, no server needed.*

## 🗺️ Roadmap & Action Plan

- [x] **Phase 1: Synthetic Data Generation (Python)** — *DONE*
  - [x] Write a Python script to generate baseline `dim` and `fact` tables.
  - [x] Inject specific, skewed data to simulate Channel Stuffing.
  - [x] Inject anomalies to simulate Promotion Hoarding.
  - [x] Inject outliers to simulate Route Falsification.
- [x] **Phase 2: Data Warehouse Design (SQL)** — *DONE*
  - [x] Define the DDL (Data Definition Language) schemas for all tables (`sql/01_schema.sql`).
  - [x] Load the synthetic CSV data into PostgreSQL via `COPY` (`sql/02_load_data.sql`).
  - [x] Build the daily `fact_stock_reconciliation` ledger (`sql/03_stock_reconciliation.sql`).
- [x] **Phase 3: The Analytical Engine (Advanced SQL)** — *DONE*
  - [x] Write the query to detect Channel Stuffing (Time-series / Window functions). (`sql/04_detect_channel_stuffing.sql`)
  - [x] Write the query to detect Promotion Leakage (Lag/Lead analysis). (`sql/05_detect_promotion_leakage.sql`)
  - [x] Write the query to detect Route Falsification (Outlier detection). (`sql/06_detect_route_falsification.sql`)
  - [x] Create a "Fraud Risk Score" View aggregating these flags per distributor. (`sql/07_fraud_risk_view.sql`)
- [x] **Phase 4: Presentation & Visualization** — *DONE*
  - [x] Build a dashboard simulating a Regional Sales Manager's view. (`build_dashboard.py` → `reports/dashboard.html` — self-contained, charts embedded, opens in any browser)
  - [x] Highlight the actionable "Risk List" of distributors. (KPI cards + ranked table with tier badges + `reports/risk_list.csv`)

## 🛠️ Technology Stack
* **Data Generation:** Python (Pandas, Numpy)
* **Data Storage/Processing:** PostgreSQL 16.9 (portable install, runs locally with no admin rights)
* **Analysis:** Advanced SQL
* **Visualization:** Python + matplotlib → single-file HTML dashboard (`reports/dashboard.html`)

## 📁 Project Structure

```
├── generate_data.py                 # Phase 1: synthetic data + planted anomalies
├── build_dashboard.py               # Phase 4: renders charts → dashboard.html
├── start_postgres.bat               # start/stop the local PostgreSQL server
├── stop_postgres.bat
├── rebuild_warehouse.bat            # drop + reload + rebuild ledger from CSVs
├── requirements.txt
├── README.md
├── data/                            # generated CSVs (dimensions + facts)
├── sql/
│   ├── 01_schema.sql                # DDL: star schema (PK/FK/CHECK + indexes)
│   ├── 02_load_data.sql             # bulk load via COPY + promo seed
│   ├── 03_stock_reconciliation.sql  # daily inventory ledger (the truth table)
│   ├── 04_detect_channel_stuffing.sql
│   ├── 05_detect_promotion_leakage.sql
│   ├── 06_detect_route_falsification.sql
│   ├── 07_fraud_risk_view.sql       # vw_fraud_risk_score (fused risk list)
│   └── 08_dashboard_exports.sql     # extracts for the dashboard
└── reports/
    ├── dashboard.html               # ← THE DELIVERABLE (self-contained)
    ├── risk_list.csv                # full scored distributor list
    ├── charts/                      # rendered chart PNGs
    └── csv/                         # dashboard extracts (regenerable)

**`FMCG_Project_and_Interview_Guide.pdf`** — a 39-page complete project walkthrough and interview preparation guide (every SQL file, every live query output, chart design rationale, 20 Q&A, demo runbook). Build sources in `docs/source/`.
```

## 🚀 How to Run

1. **Start the database** (double-click): `start_postgres.bat`
2. **Rebuild the warehouse** from CSVs: `rebuild_warehouse.bat` (or run `py generate_data.py` first for fresh data)
3. **Run the fraud engine** (any or all):
   ```
   "%LOCALAPPDATA%\fmcg-postgres\pgsql\bin\psql.exe" -U postgres -h 127.0.0.1 -d fmcg -f sql\04_detect_channel_stuffing.sql
   "%LOCALAPPDATA%\fmcg-postgres\pgsql\bin\psql.exe" -U postgres -h 127.0.0.1 -d fmcg -f sql\05_detect_promotion_leakage.sql
   "%LOCALAPPDATA%\fmcg-postgres\pgsql\bin\psql.exe" -U postgres -h 127.0.0.1 -d fmcg -f sql\06_detect_route_falsification.sql
   "%LOCALAPPDATA%\fmcg-postgres\pgsql\bin\psql.exe" -U postgres -h 127.0.0.1 -d fmcg -f sql\07_fraud_risk_view.sql
   ```
4. **The ranked risk list** (what a Regional Sales Manager reads daily):
   ```
   SELECT * FROM vw_fraud_risk_score ORDER BY risk_score DESC;
   ```
   Also exported to `reports/risk_list.csv` for BI tools.
5. **Rebuild the dashboard** (export chart data, then render):
   ```
   "%LOCALAPPDATA%\fmcg-postgres\pgsql\bin\psql.exe" -U postgres -h 127.0.0.1 -d fmcg -f sql\08_dashboard_exports.sql
   py build_dashboard.py
   ```
   Then open `reports/dashboard.html` in any browser — no server needed.
6. **Stop the database** when done: `stop_postgres.bat`

> Note: PostgreSQL lives in `%LOCALAPPDATA%\fmcg-postgres` (outside OneDrive on purpose — a live database must never be cloud-synced). The server listens on `localhost:5432` with trust authentication, which is fine for a local learning project; real deployments use passwords (`scram-sha-256`).
