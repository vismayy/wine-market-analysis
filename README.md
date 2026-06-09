# Bread & Butter Wines: Canadian Market Positioning & Competitive Analysis

> **Client:** WX Brands (Bread & Butter Wines) <br>
> **Delivered via:** George Brown College Capstone Engagement <br>
> **Role:** Team Lead

---

## Overview

This project was delivered as a real client engagement for WX Brands — the global wine portfolio company behind Bread & Butter Wines — through George Brown College's Analytics for Business Decision Making program.

The Canadian wine market contracted by **-3.46% YoY** in 2024, representing a loss of 1.39 million cases. Against this backdrop, Bread & Butter achieved **+27% YoY volume growth**, reaching the **#1 position by volume among all USA-origin wine brands in Canada** — displacing Barefoot after years of market leadership.

This analysis covers competitive performance across four major provinces (Ontario, Quebec, British Columbia, and Alberta), identifies strategic gaps, and delivers data-backed recommendations for market expansion and pricing optimization.

---

## Key Findings

| # | Finding | Implication |
|---|---------|-------------|
| 1 | Quebec has the highest per-capita wine consumption in Canada (1.54 cases/person — 85% above Ontario) yet generates only 13.6% of B&B's national volume | Largest untapped growth opportunity in the portfolio |
| 2 | B&B holds the #1 USA-origin Chardonnay position in BC but grows at +2% while value-tier competitors (19 Crimes: +440%, Crow Canyon: +92%) erode the category from below | Premium positioning under structural threat |
| 3 | B&B ranks #2 in Pinot Noir simultaneously across Alberta, BC, and Ontario — with Meiomi declining in all three markets | Strongest and most defensible national position in the portfolio |
| 4 | Kirkland Signature controls 88.7% of the Cabernet Sauvignon 3000ml format in Alberta — a format representing 10.8% of provincial volume — with no meaningful B&B presence | Immediate format expansion opportunity |

---

## Solution Architecture

```
Raw Excel Data (4 Provinces)
        │
        ▼
Python ETL Pipeline
(OOP design · pandas · IntervalIndex price mapping · melt() normalization)
        │
        ▼
SQL Server Data Warehouse
(Star Schema · Fact + Dimension tables)
        │
        ▼
T-SQL Analytical Models
(6-CTE pipeline · Window Functions · HHI · Concentration Ratios · Strategic Positioning)
        │
        ▼
Power BI Semantic Layer
(Analysis-ready imports only · reduced model complexity)
        │
        ▼
Executive Report + Dashboards
```

---

## Deliverables

### 1. Executive Report — Market Insights & Strategic Recommendations
Five-slide narrative report covering the four key market stories with quantified findings and actionable recommendations. Each story follows a structured argument: market context → competitive data → strategic implication.

📄 [`reports/executive_report.pdf`](reports/executive_report.pdf)




















