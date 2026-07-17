# FMCG Supply Chain Integrity Engine

## Overview

This project focuses on one of the common problems in the FMCG supply chain: the mismatch between **Primary Sales** (company to distributor) and **Secondary Sales** (distributor to retailer).

Many FMCG companies rely on distributor-reported secondary sales for demand planning, promotional analysis, and inventory management. However, secondary sales data may not always represent actual market movement because of practices such as inventory hoarding, delayed billing, target-driven stock loading, or incorrect delivery reporting.

The objective of this project is to build an analytical data warehouse that identifies these inconsistencies using SQL, Python, and Business Intelligence dashboards.

---

## Business Problem

The project attempts to answer questions such as:

- Are distributors buying inventory only to achieve monthly targets?
- Are promotional products actually reaching retailers?
- Are distributors reporting unrealistic delivery behaviour?
- Which distributors consistently show suspicious inventory movement?

Instead of relying only on manual audits, the project uses data analysis to identify unusual sales patterns.

---

## Data Warehouse Design

### Fact Tables

| Table | Description |
|--------|-------------|
| `fact_primary_sales` | Product shipments from company to distributor |
| `fact_secondary_sales` | Distributor sales to retailers |
| `fact_stock_reconciliation` | Daily calculated inventory position |

### Dimension Tables

- `dim_date`
- `dim_product`
- `dim_distributor`
- `dim_kirana`
- `dim_promotion`

The warehouse follows a star schema so that analytical queries can be executed efficiently.

---

## Analytical Objectives

### 1. Channel Stuffing Detection

Detect distributors receiving unusually high primary sales near month-end without a corresponding increase in secondary sales.

Possible indicators:

- Month-end shipment spikes
- Rising warehouse inventory
- Low sell-through percentage

---

### 2. Promotion Leakage Detection

Identify products that receive promotional inventory but are not sold during the promotional period.

Possible indicators:

- Near-zero secondary sales during promotion
- Sudden increase in sales immediately after promotion ends
- Large remaining stock during the campaign

---

### 3. Route or Beat Validation

Detect unusual delivery behaviour using secondary sales data.

Examples include:

- Very large deliveries to a single retailer
- Abnormally low retailer coverage
- Repeated bulk billing on the same day

---

### 4. Inventory Reconciliation

Calculate expected stock using

```
Opening Stock
+ Primary Sales
- Secondary Sales
= Closing Stock
```

Large deviations indicate potential reporting or operational issues.

---

## Project Workflow

### Phase 1 – Data Generation

Generate synthetic FMCG data using Python.

Tasks:

- Create master data
- Generate daily transactions
- Simulate distributor behaviour
- Inject realistic anomalies

Libraries:

- Pandas
- NumPy
- Faker

---

### Phase 2 – Database Design

Create the warehouse schema.

Tasks:

- Design star schema
- Write DDL scripts
- Load CSV data into PostgreSQL

---

### Phase 3 – SQL Analytics

Develop SQL queries to identify supply chain anomalies.

Key SQL concepts:

- Window Functions
- CTEs
- Aggregations
- CASE statements
- LAG / LEAD
- Ranking Functions

Outputs include:

- Channel Stuffing Report
- Promotion Leakage Report
- Inventory Reconciliation Report
- Distributor Risk Score

---

### Phase 4 – Dashboard

Build a Power BI dashboard for business users.

Dashboard pages:

- Executive Overview
- Distributor Performance
- Inventory Reconciliation
- Promotion Analysis
- High Risk Distributor List

---

## Technology Stack

| Category | Tools |
|----------|-------|
| Programming | Python |
| Data Processing | Pandas, NumPy |
| Data Generation | Faker |
| Database | PostgreSQL |
| Analytics | SQL |
| Visualization | Power BI |

---

## Folder Structure

```
FMCG-Supply-Chain-Integrity-Engine/
│
├── data/
│   ├── raw/
│   ├── processed/
│
├── sql/
│   ├── schema.sql
│   ├── data_load.sql
│   ├── channel_stuffing.sql
│   ├── promotion_leakage.sql
│   ├── route_validation.sql
│   └── distributor_risk_score.sql
│
├── python/
│   ├── generate_data.py
│   ├── anomaly_generator.py
│   └── reconciliation.py
│
├── dashboard/
│   └── FMCG_Dashboard.pbix
│
├── images/
│
└── README.md
```

---

## Expected Outcomes

The final solution will enable analysts to:

- Monitor inventory movement across distributors
- Detect unusual sales behaviour automatically
- Measure distributor performance using data
- Support better inventory and promotion planning

---

## Future Improvements

- Machine Learning based anomaly detection
- Real-time dashboard using streaming data
- GIS-based distributor route analysis
- Sales forecasting using historical trends
