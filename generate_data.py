import pandas as pd
import numpy as np
import random
from datetime import datetime, timedelta
import os

# Set random seed for reproducibility
np.random.seed(42)
random.seed(42)

# Ensure data directory exists
DATA_DIR = "./data"
os.makedirs(DATA_DIR, exist_ok=True)

print("Starting FMCG Synthetic Data Generation...")

# ==========================================
# 1. GENERATE DIMENSION TABLES
# ==========================================
print("Generating Dimensions...")

# --- dim_date ---
start_date = datetime(2023, 1, 1)
end_date = datetime(2023, 6, 30) # 6 months of data
date_list = [start_date + timedelta(days=x) for x in range((end_date-start_date).days + 1)]

dim_date = pd.DataFrame({'date': date_list})
dim_date['date_id'] = dim_date['date'].dt.strftime('%Y%m%d').astype(int)
dim_date['year'] = dim_date['date'].dt.year
dim_date['month'] = dim_date['date'].dt.month
dim_date['day'] = dim_date['date'].dt.day
# Flag end of month (approximate for simplicity - last 3 days of month)
dim_date['is_month_end'] = dim_date['date'].dt.is_month_end
dim_date.to_csv(f"{DATA_DIR}/dim_date.csv", index=False)

# --- dim_product ---
products = [
    {"sku_id": "SKU001", "brand": "CleanMax", "category": "Soap", "mrp": 45, "units_per_case": 100},
    {"sku_id": "SKU002", "brand": "CleanMax", "category": "Detergent", "mrp": 120, "units_per_case": 50},
    {"sku_id": "SKU003", "brand": "HairGlow", "category": "Shampoo", "mrp": 180, "units_per_case": 40},
    {"sku_id": "SKU004", "brand": "NutriBite", "category": "Biscuits", "mrp": 30, "units_per_case": 120},
    {"sku_id": "SKU005", "brand": "NutriBite", "category": "Snacks", "mrp": 20, "units_per_case": 200},
]
dim_product = pd.DataFrame(products)
dim_product.to_csv(f"{DATA_DIR}/dim_product.csv", index=False)

# --- dim_sales_rep ---
reps = [
    {"rep_id": "REP01", "rep_name": "Ravi Kumar", "region": "North"},
    {"rep_id": "REP02", "rep_name": "Priya Singh", "region": "South"},
    {"rep_id": "REP03", "rep_name": "Amit Patel", "region": "West"},
    {"rep_id": "REP04", "rep_name": "Neha Sharma", "region": "East"}
]
dim_sales_rep = pd.DataFrame(reps)
dim_sales_rep.to_csv(f"{DATA_DIR}/dim_sales_rep.csv", index=False)

# --- dim_distributor ---
distributors = []
for i in range(1, 21): # 20 distributors
    distributors.append({
        "distributor_id": f"DIST{i:03d}",
        "distributor_name": f"Enterprise Sales {i}",
        "rep_id": random.choice(["REP01", "REP02", "REP03", "REP04"]),
        "region": random.choice(["Urban", "Semi-Urban", "Rural"])
    })
dim_distributor = pd.DataFrame(distributors)
dim_distributor.to_csv(f"{DATA_DIR}/dim_distributor.csv", index=False)

# --- dim_kirana ---
kiranas = []
for i in range(1, 501): # 500 Kirana stores
    dist_id = random.choice(distributors)['distributor_id']
    kiranas.append({
        "kirana_id": f"KIR{i:04d}",
        "kirana_name": f"Sri Ram Provisions {i}",
        "distributor_id": dist_id, # Which distributor serves them
        "pin_code": random.randint(400001, 400100)
    })
dim_kirana = pd.DataFrame(kiranas)
dim_kirana.to_csv(f"{DATA_DIR}/dim_kirana.csv", index=False)

# ==========================================
# 2. GENERATE FACT TABLES WITH ANOMALIES
# ==========================================
print("Generating Fact Tables (This may take a moment)...")

primary_sales = []
secondary_sales = []

# Target identifiers for our anomalies
STUFFING_DISTRIBUTOR = "DIST005"
FALSIFY_DISTRIBUTOR = "DIST012"
PROMO_DISTRIBUTOR = "DIST018"
PROMO_SKU = "SKU001"
PROMO_START = datetime(2023, 4, 10)
PROMO_END = datetime(2023, 4, 25)

for index, row in dim_date.iterrows():
    curr_date = row['date']
    date_id = row['date_id']
    is_month_end = row['is_month_end']
    
    for dist in distributors:
        dist_id = dist['distributor_id']
        rep_id = dist['rep_id']
        
        for prod in products:
            sku_id = prod['sku_id']
            
            # --- NORMAL BEHAVIOR ---
            # Baseline Primary Sales (Company ships to Distributor roughly every 3-5 days)
            if random.random() < 0.3: 
                base_qty_cases = random.randint(10, 50)
                
                # ANOMALY 1: CHANNEL STUFFING
                # DIST005 is forced to buy massive stock at month end by their rep to hit targets
                if dist_id == STUFFING_DISTRIBUTOR and is_month_end:
                    base_qty_cases = base_qty_cases * 8 # Massive spike
                    
                primary_sales.append({
                    "date_id": date_id,
                    "distributor_id": dist_id,
                    "sku_id": sku_id,
                    "rep_id": rep_id,
                    "qty_cases": base_qty_cases
                })
            
            # Baseline Secondary Sales (Distributor sells to Kiranas daily)
            # Find kiranas attached to this distributor
            dist_kiranas = dim_kirana[dim_kirana['distributor_id'] == dist_id]['kirana_id'].tolist()
            
            if len(dist_kiranas) > 0:
                # ANOMALY 3: ROUTE FALSIFICATION
                # DIST012 claims to visit 20 shops, but actually dumps all stock at one shop
                if dist_id == FALSIFY_DISTRIBUTOR and random.random() < 0.2:
                    # Dump 200 units to a single Kirana on this day
                    unlucky_kirana = random.choice(dist_kiranas)
                    secondary_sales.append({
                        "date_id": date_id,
                        "kirana_id": unlucky_kirana,
                        "distributor_id": dist_id,
                        "sku_id": sku_id,
                        "qty_units": random.randint(150, 300) # Abnormal huge drop
                    })
                else:
                    # Normal route distribution
                    for k_id in random.sample(dist_kiranas, min(10, len(dist_kiranas))): # Visits ~10 shops a day
                        # ANOMALY 2: PROMOTION LEAKAGE
                        # DIST018 hoards SKU001 during promo period, doesn't sell to Kiranas.
                        # Then sells massive amounts right after promo ends.
                        is_promo_period = PROMO_START <= curr_date <= PROMO_END
                        is_post_promo_period = PROMO_END < curr_date <= PROMO_END + timedelta(days=15)
                        
                        qty_units = random.randint(5, 20)
                        
                        if dist_id == PROMO_DISTRIBUTOR and sku_id == PROMO_SKU:
                            if is_promo_period:
                                qty_units = 0 # Hoarding
                            elif is_post_promo_period:
                                qty_units = qty_units * 3 # Selling hoarded stock at full margin later
                                
                        if qty_units > 0:
                            secondary_sales.append({
                                "date_id": date_id,
                                "kirana_id": k_id,
                                "distributor_id": dist_id,
                                "sku_id": sku_id,
                                "qty_units": qty_units
                            })

df_primary = pd.DataFrame(primary_sales)
# Add an auto-incrementing ID
df_primary.insert(0, 'primary_order_id', range(1, 1 + len(df_primary)))
df_primary.to_csv(f"{DATA_DIR}/fact_primary_sales.csv", index=False)

df_secondary = pd.DataFrame(secondary_sales)
df_secondary.insert(0, 'secondary_order_id', range(1, 1 + len(df_secondary)))
df_secondary.to_csv(f"{DATA_DIR}/fact_secondary_sales.csv", index=False)

print(f"Data generation complete! Files saved to {DATA_DIR}/")
print(f" - Primary Sales records: {len(df_primary)}")
print(f" - Secondary Sales records: {len(df_secondary)}")
print("Anomalies injected successfully for analysis.")
