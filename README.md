# Canadian Emergency Department — SQL Analytics Project

**Domain:** Canadian Public Healthcare  
**Database:** MySQL | **IDE:** MySQL Workbench  
**Scale:** 4 tables · 9,120 rows · 20 hospitals · 7 provinces · 2 fiscal years

---

## Problem Statement

Emergency Department overcrowding is one of Canada's most documented healthcare crises. Patients wait beyond safe thresholds, leave without being seen, and admitted patients occupy ED beds for hours waiting for inpatient transfers. This project models how provincial health authorities and hospital networks analyze these problems — using real Canadian benchmarks, CIHI fiscal year structure, and authentic operational metrics.

---

## Database Schema

```
patients ──────────────────┐
                           │ patient_id (FK)
                           ▼
hospitals ────────────► ed_visits
    │          hospital_id (FK)
    │ hospital_id (FK)
    ▼
physician_shifts
```

| Table | Rows | Description |
|---|---|---|
| `patients` | 500 | Age, gender, province, chronic conditions |
| `hospitals` | 20 | Hospital name, type (teaching/community/rural), province, region |
| `ed_visits` | 5,000 | Full visit lifecycle — arrival, triage, physician, discharge |
| `physician_shifts` | 3,600 | Shift schedules with staffing levels per hospital |

---

## 8 Business Problems Solved

### Problem 1 — CTAS Benchmark Compliance
**Question:** Which hospitals are failing CTAS benchmarks, broken down by triage level?

Measures each hospital's compliance with Canada's national triage wait time targets. Calculates breach percentage per hospital per CTAS level. Surfaces the worst-performing hospitals at the top.

**SQL concepts:** CTE, `TIMESTAMPDIFF()`, `CASE WHEN`, conditional aggregation, `ROUND()`

---

### Problem 2 — Left Without Being Seen (LWBS) Rate
**Question:** What is the LWBS rate per hospital and fiscal year? Which hospital type has the worst trend?

Tracks patients who leave the ED before seeing a physician — a CIHI national quality indicator. Compares community vs. teaching vs. rural hospitals across two fiscal years.

**SQL concepts:** Conditional `SUM()`, percentage calculation, `GROUP BY`, multi-column aggregation

---

### Problem 3 — ED Boarding Analysis
**Question:** How many admitted patients exceeded the 8-hour boarding threshold?

Identifies admitted patients who remained in the ED longer than the national 8-hour guideline. Calculates average boarding hours per hospital and ranks worst-performing sites.

**SQL concepts:** `TIMESTAMPDIFF(HOUR)`, `WHERE` filtering on disposition and NULL, conditional aggregation

---

### Problem 4 — Peak Demand Hours by Hospital Type
**Question:** When does ED volume peak for teaching vs. community vs. rural hospitals?

Determines arrival patterns by hour and day of week across hospital types. Supports evidence-based shift scheduling to reduce avoidable wait time spikes.

**SQL concepts:** `HOUR()`, `DAYNAME()`, `GROUP BY` on derived columns, `COUNT()`

---

### Problem 5 — High Utilizer Identification
**Question:** Which patients visited 4+ times in a year, and what are their most common complaints?

Identifies high-frequency ED users by province and fiscal year. Shows top 2 chief complaints per patient with repeat counts. High utilizers often signal gaps in primary care access.

**SQL concepts:** Multi-CTE, `COUNT() OVER (PARTITION BY)`, `ROW_NUMBER()`, `GROUP_CONCAT()`, `CONCAT()`

---

### Problem 6 — Physician Staffing vs. Wait Time Correlation
**Question:** Does increasing physicians on duty reduce wait times? Does it differ by shift type?

Joins shift records to ED visits using a datetime `BETWEEN` condition to match patients to the shift they arrived during. Quantifies the staffing-to-wait-time relationship by shift type.

**SQL concepts:** 3-table JOIN, `BETWEEN` on datetime ranges, `GROUP BY` on staffing level and shift type

---

### Problem 7 — Provincial Equity Analysis
**Question:** Do rural hospitals serve older, sicker patients yet deliver worse wait times?

Compares average patient age, CTAS acuity, and wait times across hospital types and provinces. Directly relevant to federal-provincial health funding equity discussions.

**SQL concepts:** 3-table JOIN, `AVG()`, `COUNT(DISTINCT)`, multi-column `GROUP BY`

---

### Problem 8 — Hospital Ranking Within Province
**Question:** How does each hospital rank within its province, and how far is it from the provincial average?

Ranks hospitals by average wait time within their province. Calculates deviation from the provincial average and flags each hospital's performance status.

**SQL concepts:** `RANK() OVER (PARTITION BY)`, `AVG() OVER (PARTITION BY)`, multi-CTE, deviation calculation

---

## SQL Skills Demonstrated

| Category | Techniques Used |
|---|---|
| CTEs | Single and multi-CTE queries |
| Window Functions | `RANK()`, `ROW_NUMBER()`, `AVG() OVER (PARTITION BY)`, `COUNT() OVER (PARTITION BY)` |
| Joins | 2-table and 3-table JOINs, datetime range JOIN using `BETWEEN` |
| Aggregation | `GROUP BY`, conditional `SUM(CASE WHEN)`, `COUNT(DISTINCT)` |
| Date & Time | `TIMESTAMPDIFF()`, `HOUR()`, `DAYNAME()` |
| String Functions | `GROUP_CONCAT()`, `CONCAT()` |
| Data Quality | NULL filtering, `WHERE` clause discipline |
| Output Formatting | `ROUND()`, `ORDER BY` for stakeholder-ready results |

---

## Canadian Healthcare Context

| Term | Definition |
|---|---|
| CTAS | Canadian Triage and Acuity Scale — 5 levels from Resuscitation (1) to Non-urgent (5), each with a maximum wait time benchmark |
| LWBS | Left Without Being Seen — patients who leave before physician assessment; CIHI tracks this nationally |
| Boarding | Admitted patients waiting in the ED for an inpatient bed; 8 hours is the national threshold |
| CIHI | Canadian Institute for Health Information — defines national benchmarks and fiscal year structure |
| Fiscal Year | April 1 to March 31 (e.g., 2023-24) — standard Canadian government reporting period |

---

## Setup Instructions

```sql
-- Step 1: Create the schema in MySQL Workbench
CREATE DATABASE canadian_ed;

-- Step 2: Import the data
-- Server → Data Import → Import from Self-Contained File
-- Select: canadian_ed_mysql.sql → Start Import

-- Step 3: Run any query from the queries/ folder
```

---

## Project Structure

```
canadian-ed-analysis/
│
├── canadian_ed_mysql.sql              # Schema + all seed data (run this first)
│
├── queries/
│   ├── 01_ctas_benchmark.sql          # CTAS benchmark breach analysis
│   ├── 02_lwbs_rate.sql               # Left without being seen rate
│   ├── 03_ed_boarding.sql             # Boarding threshold analysis
│   ├── 04_peak_demand_hours.sql       # Peak arrival hours by hospital type
│   ├── 05_high_utilizers.sql          # Repeat ED visitors
│   ├── 06_staffing_vs_waittime.sql    # Physician staffing correlation
│   ├── 07_provincial_equity.sql       # Rural vs urban equity analysis
│   └── 08_hospital_ranking.sql        # Provincial hospital rankings
│
└── README.md
```

---

## Data Notes

Data is synthetically generated but modelled on real CIHI reporting structures, CTAS benchmarks, and Canadian ED operational patterns. Hospital names reflect real Canadian institutions. CTAS distributions, LWBS rates, boarding times, and arrival hour patterns are calibrated to match published CIHI national averages.

---

*Built as a portfolio project demonstrating real-world SQL analytics in the Canadian public healthcare domain.*
