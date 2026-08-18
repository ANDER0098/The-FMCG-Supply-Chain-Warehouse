# ============================================================
# build_dashboard.py - Phase 4: Presentation Layer
# ============================================================
# Pipeline:  reports/csv/*.csv  -->  matplotlib charts  -->
#            single self-contained reports/dashboard.html
#
# WHY THIS DESIGN:
#  - All business logic already ran in SQL (the warehouse + the
#    fraud view). Python here is ONLY a rendering layer.
#  - Charts are embedded into the HTML as base64 data URIs, so the
#    dashboard is ONE file: double-click it, email it, host it -
#    no server, no internet, no missing images.
#  - matplotlib "Agg" backend = headless rendering (no popup window),
#    which is what you want for scripted report generation.
#
# Run:  py build_dashboard.py   (after sql/08_dashboard_exports.sql)
# ============================================================
from pathlib import Path
import base64
from datetime import datetime

import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

ROOT     = Path(__file__).resolve().parent
CSV_DIR  = ROOT / "reports" / "csv"
CHART_DIR = ROOT / "reports" / "charts"
OUT_FILE = ROOT / "reports" / "dashboard.html"
CHART_DIR.mkdir(parents=True, exist_ok=True)

# One shared palette so every chart speaks the same visual language.
BLUE, RED, AMBER, GREEN, GREY = "#4e79a7", "#e15759", "#f28e2b", "#59a14f", "#9aa0ab"
plt.rcParams.update({
    "figure.facecolor": "#1b1e27", "axes.facecolor": "#1b1e27",
    "axes.edgecolor": "#3a3f4d", "axes.labelcolor": "#dfe3ea",
    "xtick.color": "#dfe3ea", "ytick.color": "#dfe3ea",
    "text.color": "#dfe3ea", "grid.color": "#3a3f4d",
    "font.size": 9, "axes.grid": True, "grid.alpha": 0.35,
})

TIER_COLORS = {"CRITICAL": "#c0392b", "HIGH": RED, "MEDIUM": AMBER, "CLEAN": GREEN}

# ------------------------------------------------------------
# Load the SQL extracts
# ------------------------------------------------------------
risk   = pd.read_csv(CSV_DIR / "risk_list.csv")
dist005 = pd.read_csv(CSV_DIR / "dist005_daily.csv", parse_dates=["full_date"])
dist018 = pd.read_csv(CSV_DIR / "dist018_sku001_daily.csv", parse_dates=["full_date"])
drops  = pd.read_csv(CSV_DIR / "drop_size_buckets.csv")

def save(fig, name):
    path = CHART_DIR / name
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return path

def img64(path: Path) -> str:
    """Embed a file as a data URI so the HTML has zero external deps."""
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode()

# ------------------------------------------------------------
# CHART 1 - Channel stuffing: DIST005 daily purchases vs his normal
# The trailing average is computed with pandas' rolling(), the exact
# twin of the SQL window we used in file 04:
#   shift(1).rolling(28).mean()  ==  ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING
# ------------------------------------------------------------
dist005["trail"] = dist005["primary_units"].shift(1).rolling(28, min_periods=1).mean()
flagged = dist005[dist005["primary_units"] >= 4 * dist005["trail"].fillna(0)]

fig, ax = plt.subplots(figsize=(9.6, 3.4))
ax.plot(dist005["full_date"], dist005["primary_units"], color=BLUE, lw=1.2, label="Daily purchases (units)")
ax.plot(dist005["full_date"], dist005["trail"], color=GREY, lw=1.2, ls="--", label="Trailing 28-day average")
ax.scatter(flagged["full_date"], flagged["primary_units"], color=RED, s=42, zorder=3,
           label=f"Flagged spike (>=4x normal): {len(flagged)} days")
ax.set_title("DIST005 - purchases from the company (Jan-Jun 2023)", fontsize=10, loc="left")
ax.set_ylabel("units / day")
ax.legend(loc="upper left", fontsize=8, framealpha=0.2)
fig.autofmt_xdate()
chart1 = save(fig, "channel_stuffing.png")

# ------------------------------------------------------------
# CHART 2 - Promo leakage: DIST018 SKU001 secondary sales
# ------------------------------------------------------------
fig, ax = plt.subplots(figsize=(9.6, 3.4))
ax.axvspan(pd.Timestamp("2023-04-10"), pd.Timestamp("2023-04-25"),
           color=AMBER, alpha=0.25, label="Promo window (20% off)")
ax.plot(dist018["full_date"], dist018["secondary_units"], color=BLUE, lw=1.4,
        label="Daily sales to kiranas (units)")
ax.annotate("HOARDING\nzero sales while holding\n91,499 units of stock",
            xy=(pd.Timestamp("2023-04-17"), 40), xytext=(pd.Timestamp("2023-03-24"), 240),
            color=AMBER, fontsize=8, ha="center",
            arrowprops=dict(arrowstyle="->", color=AMBER))
ax.annotate("DUMP\n3x baseline, full margin",
            xy=(pd.Timestamp("2023-04-28"), 357), xytext=(pd.Timestamp("2023-05-16"), 330),
            color=RED, fontsize=8, ha="center",
            arrowprops=dict(arrowstyle="->", color=RED))
ax.set_title("DIST018 / SKU001 - sales to kirana stores around the April promo", fontsize=10, loc="left")
ax.set_ylabel("units / day")
ax.legend(loc="upper left", fontsize=8, framealpha=0.2)
fig.autofmt_xdate()
chart2 = save(fig, "promo_leakage.png")

# ------------------------------------------------------------
# CHART 3 - Route falsification: drop-size distribution
# ------------------------------------------------------------
bucket_order = ["1-20", "21-60", "61-100", "101-150", "151-200",
                "201-250", "251-300", "300+"]
pivot = (drops.pivot(index="bucket", columns="cohort", values="drop_count")
         .reindex(bucket_order).fillna(0))
x = range(len(bucket_order))
w = 0.38
fig, ax = plt.subplots(figsize=(9.6, 3.4))
ax.bar([i - w/2 for i in x], pivot["DIST012 (falsifier)"], width=w,
       color=RED, label="DIST012 (falsifier)")
ax.bar([i + w/2 for i in x], pivot["All other distributors"], width=w,
       color=GREY, label="All other distributors (19)")
ax.set_yscale("log")   # honest shops make ~170k small drops; linear scale would flatten everything
ax.set_xticks(list(x))
ax.set_xticklabels(bucket_order)
ax.set_xlabel("units delivered to ONE kirana in ONE day")
ax.set_ylabel("number of drops (log scale)")
ax.set_title("Drop-size distribution: DIST012 ships physically implausible loads", fontsize=10, loc="left")
ax.legend(fontsize=8, framealpha=0.2)
chart3 = save(fig, "drop_sizes.png")

# ------------------------------------------------------------
# CHART 4 - The ranked risk list
# ------------------------------------------------------------
top = risk.head(8).iloc[::-1]  # reverse so the biggest bar is on top
fig, ax = plt.subplots(figsize=(9.6, 3.0))
colors = [TIER_COLORS.get(t, GREY) for t in top["risk_tier"]]
ax.barh(top["distributor_id"], top["risk_score"], color=colors)
for y_pos, (_, row) in enumerate(top.iterrows()):
    ax.text(row["risk_score"] + 0.6, y_pos, f"{int(row['risk_score'])}  {row['risk_tier']}",
            va="center", fontsize=8, color="#dfe3ea")
ax.set_xlim(0, 60)
ax.set_xlabel("fraud risk score (0-100)")
ax.set_title("Ranked risk list - who the Regional Sales Manager calls first", fontsize=10, loc="left")
chart4 = save(fig, "risk_ranking.png")

# ------------------------------------------------------------
# KPIs computed from the risk view extract
# ------------------------------------------------------------
kpis = {
    "distributors": len(risk),
    "high_risk": int((risk["risk_tier"] == "HIGH").sum()),
    "stuffing": int(risk["stuffing_flags"].sum()),
    "dumps": int(risk["route_dump_events"].sum()),
}

# ------------------------------------------------------------
# HTML assembly (charts embedded as base64 -> one portable file)
# ------------------------------------------------------------
css = """
  body { background:#12141a; color:#dfe3ea; font-family:'Segoe UI',Arial,sans-serif;
         margin:0; padding:32px 40px; }
  h1 { font-size:22px; margin:0 0 4px 0; }
  .sub { color:#9aa0ab; font-size:12px; margin-bottom:24px; }
  .kpis { display:flex; gap:14px; margin-bottom:28px; flex-wrap:wrap; }
  .kpi { background:#1b1e27; border:1px solid #3a3f4d; border-radius:10px;
         padding:14px 22px; min-width:150px; }
  .kpi .v { font-size:26px; font-weight:600; }
  .kpi .l { font-size:11px; color:#9aa0ab; }
  .kpi.alert .v { color:#e15759; }
  table { border-collapse:collapse; width:100%; font-size:12.5px; }
  th { text-align:left; color:#9aa0ab; font-weight:600; padding:8px 10px;
       border-bottom:1px solid #3a3f4d; }
  td { padding:8px 10px; border-bottom:1px solid #232733; }
  tr:hover td { background:#1b1e27; }
  .badge { padding:2px 10px; border-radius:999px; font-size:11px; font-weight:600; }
  .b-HIGH  { background:#e15759; color:#12141a; }
  .b-MEDIUM{ background:#f28e2b; color:#12141a; }
  .b-CLEAN { background:#59a14f; color:#12141a; }
  .card { background:#171a22; border:1px solid #2c313d; border-radius:12px;
          padding:20px 22px; margin-bottom:26px; }
  .card h2 { font-size:15px; margin:0 0 6px 0; }
  .card p { color:#9aa0ab; font-size:12.5px; margin:0 0 14px 0; line-height:1.5; }
  img { width:100%; border-radius:6px; }
  footer { color:#6b7280; font-size:11px; margin-top:30px; line-height:1.6; }
"""

rows_html = ""
for _, r in risk.head(10).iterrows():
    tier = r["risk_tier"]
    rows_html += f"""
      <tr><td>{r['distributor_id']}</td><td>{r['distributor_name']}</td>
      <td>{r['region']}</td><td>{int(r['stuffing_flags'])}</td>
      <td>{int(r['promo_leak_flags'])}</td><td>{int(r['route_dump_events'])}</td>
      <td><b>{int(r['risk_score'])}</b></td>
      <td><span class="badge b-{tier}">{tier}</span></td></tr>"""

def card(title, text, img):
    return f'<div class="card"><h2>{title}</h2><p>{text}</p><img src="{img64(img)}" alt="{title}"></div>'

html = f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<title>FMCG Supply Chain Integrity Engine</title><style>{css}</style></head>
<body>
<h1>FMCG Supply Chain Integrity Engine</h1>
<div class="sub">Regional Sales Manager view &middot; Jan-Jun 2023 &middot; generated {datetime.now():%d %b %Y %H:%M}</div>

<div class="kpis">
  <div class="kpi"><div class="v">{kpis['distributors']}</div><div class="l">distributors screened</div></div>
  <div class="kpi alert"><div class="v">{kpis['high_risk']}</div><div class="l">HIGH-risk (fraud likely)</div></div>
  <div class="kpi"><div class="v">{kpis['stuffing']}</div><div class="l">month-end stuffing spikes</div></div>
  <div class="kpi"><div class="v">{kpis['dumps']}</div><div class="l">bulk dump deliveries</div></div>
</div>

{card("1. Channel Stuffing - DIST005",
      "Five month-ends show purchases 8-20x this distributor's own normal rate while his sales "
      "to kirana stores stayed flat (611 vs a 635/day average). Goods moved on paper only - "
      "classic target-pressure stuffing by the servicing rep.",
      chart1)}

{card("2. Promotion Leakage - DIST018",
      "During the 20% promo (shaded) this distributor reported ZERO sales of the promoted SKU "
      "while holding 91,499 units in stock - then sold at 3x baseline the morning after the promo "
      "ended. The discount was pocketed, never passed to consumers.",
      chart2)}

{card("3. Route Falsification - DIST012",
      "Every honest drop to a kirana shop is 5-20 units. DIST012 made 168 deliveries of 100-300 "
      "units to single shops - 29.7% of his total volume. No neighbourhood store can shelve that; "
      "he invoices entire routes at one shop to claim route allowances.",
      chart3)}

{card("4. Ranked Risk List",
      "All three detectors fused into one transparent score (stuffing 40 / promo 30 / route 30). "
      "DIST003's single mild flag is statistical noise - parked in MEDIUM for a routine check, "
      "which is exactly how a real investigate-list should behave.",
      chart4)}

<div class="card"><h2>Actionable Risk List (top 10 of {kpis['distributors']})</h2>
<table>
<tr><th>ID</th><th>Distributor</th><th>Region</th><th>Stuffing flags</th>
<th>Promo leaks</th><th>Bulk dumps</th><th>Score</th><th>Tier</th></tr>
{rows_html}
</table></div>

<footer>
Method: PostgreSQL star schema (7 dimensions, 3 facts, daily stock reconciliation ledger) &rarr;
three blind detectors (trailing-window ratios, promo-window conditional aggregation,
z-scored drop sizes) &rarr; transparent weighted score. Source: sql/01-08, view vw_fraud_risk_score.
</footer>
</body></html>"""

OUT_FILE.write_text(html, encoding="utf-8")
print(f"Dashboard written: {OUT_FILE}")
print(f"  size: {OUT_FILE.stat().st_size / 1024:.0f} KB (charts embedded)")
print(f"  KPIs: {kpis}")
