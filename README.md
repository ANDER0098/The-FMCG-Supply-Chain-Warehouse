FMCG Supply Chain Integrity Engine: Exposing the Primary-Secondary Sales Gap
📖 Project Overview
In the Fast-Moving Consumer Goods (FMCG) and Consumer Packaged Goods (CPG) sectors, the gap between Primary Sales (what a company ships to a distributor) and Secondary Sales (what the distributor claims to sell to retailers/Kiranas) is a multi-million dollar blind spot.

This gap isn't just a software bug or a data delay; it is a human behavioral problem rooted in physical reality. Distributors may hoard promotional stock, falsify delivery routes to save fuel, or be forced into buying excess inventory to meet sales targets.

This project is an Analytical Data Engine designed to mathematically corner these discrepancies. By modeling specific human behaviors and identifying anomalies in the supply chain data, this engine exposes the truth behind inventory movement.

🏗️ Core Architecture
The architecture relies on trapping discrepancies across three distinct metrics:

Source System	Table	What it Measures	The "Lie" Factor
Company ERP (SAP/Oracle)	fact_primary_sales	What left the factory and hit the distributor's warehouse.	Very Low. Tied to revenue and tax.
Distributor App (DMS)	fact_secondary_sales	What the distributor claims they sold to the Kirana store.	High. Prone to falsified dates and bulk-billing.
Automated ETL Output	fact_stock_reconciliation	The daily mathematical truth: (Opening Stock + Primary) - Secondary.	None. This is where the gaps are exposed.
Dimension Tables
To support the analytical queries, the warehouse will include:

dim_date, dim_distributor, dim_kirana, dim_product, dim_promotion
🎯 Key Analytical Objectives (The Blind Spots)
This engine is built to solve three specific problems using advanced SQL:

Channel Stuffing Detection: Identifying spikes in primary sales at month-end without corresponding secondary sales growth, indicating inventory dumping rather than actual growth.
The Promotion Leakage Trap: Flagging instances where secondary sales of a promoted SKU drop to zero during a promo window, only to spike at full price immediately after.
Route/Beat Falsification: Detecting impossible delivery metrics (e.g., massive bulk drops to a single rural retailer) that indicate a distributor is skipping routes to save logistics costs.
🗺️ Roadmap & Action Plan
 Phase 1: Synthetic Data Generation (Python)
 Write a Python script to generate baseline dim and fact tables.
 Inject specific, skewed data to simulate Channel Stuffing.
 Inject anomalies to simulate Promotion Hoarding.
 Inject outliers to simulate Route Falsification.
 Phase 2: Data Warehouse Design (SQL)
 Define the DDL (Data Definition Language) schemas for all tables.
 Load the synthetic CSV/Parquet data into the SQL database.
 Phase 3: The Analytical Engine (Advanced SQL)
 Write the query to detect Channel Stuffing (Time-series / Window functions).
 Write the query to detect Promotion Leakage (Lag/Lead analysis).
 Write the query to detect Route Falsification (Outlier detection).
 Create a "Fraud Risk Score" View aggregating these flags per distributor.
 Phase 4: Presentation & Visualization
 Build a BI Dashboard (Tableau/PowerBI/Looker) simulating a Regional Sales Manager's view.
 Highlight the actionable "Risk List" of distributors.
🛠️ Technology Stack
Data Generation: Python (Pandas, Numpy, Faker)
Data Storage/Processing: PostgreSQL / Snowflake / BigQuery (TBD)
Analysis: Advanced SQL
Visualization: TBD
