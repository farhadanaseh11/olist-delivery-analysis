# Delivery Performance and Customer Satisfaction: An Analysis of the Olist Marketplace

**Tools:** PostgreSQL 17, DBeaver
**Data:** [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) — ~100,000 orders, 2016–2018

---

## The Question

Olist is a Brazilian e-commerce marketplace connecting small and mid-sized merchants to
customers nationwide. Review scores directly affect seller retention on the platform.

This analysis answers a question a Marketplace Operations lead would ask:

> **Our review scores are hurting seller retention. How much of that is delivery
> performance, and where should we intervene first?**

---

## Headline Findings

**Late delivery is severe but not the main driver.** Late orders produce 1–2 star reviews
at **5.9× the on-time rate** — yet account for only about **28% of all bad reviews**,
because 92% of orders arrive on time and even a 9% failure rate across 88,000 orders
produces more total damage.

**The bad reviews are not concentrated in bad sellers.** 55% come from sellers performing
*above* platform average. They are high-volume, not low-quality.

**No single intervention solves the problem.** Fixing every underperforming seller
addresses 16% of bad reviews. Eliminating lateness entirely addresses 28%. Both are
ceilings, not forecasts.

---

## Method

### Setup

Tables were defined explicitly with DDL before loading, rather than letting the import tool
infer column types. Inferred imports read all eight order timestamp columns as text, which
causes date comparisons to evaluate as alphabetical string comparisons and return silently
incorrect results. Typed `TIMESTAMP` columns are what make the lateness calculation valid.

Data loaded via `psql` using `\copy`.

### Data quality findings

**Duplicate load on two tables.** Row counts were verified against published table sizes
immediately after import. Two came back at exactly double:

| Table | Loaded | Expected |
|---|---|---|
| `customers` | 198,882 | 99,441 |
| `sellers` | 6,190 | 3,095 |

The exact 2× ratio indicated a repeated load rather than genuine duplicates. Both were
truncated and reloaded. Nothing errored — undetected, every per-customer and per-seller
metric would have been wrong by a factor of two.

**Status/timestamp inconsistency.** Eight orders carry `order_status = 'delivered'` with a
null `order_delivered_customer_date`. Excluded: lateness cannot be evaluated without a
delivery date, and null comparisons in SQL return null rather than false, meaning these
rows would have silently dropped out of the late count while remaining in the denominator.

**Orphaned orders.** 775 orders have no rows in `order_items`. Already outside the analysis
population.

### Analysis population

```sql
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
```

**96,470 delivered orders (97.0% of 99,441).** For review-based analysis, the inner join to
`order_reviews` reduces this to **96,353**.

| Excluded | Reason |
|---|---|
| In transit (`shipped`, `invoiced`, `processing`, `approved`, `created`) | Not yet delivered; no opportunity to be late |
| `canceled`, `unavailable` | No delivery outcome exists or ever will |
| 8 delivered orders with null timestamps | Source data inconsistency |

Every row in the denominator must have been eligible to appear in the numerator. Including
orders that could not have been late would inflate the denominator and understate the rate.

---

## Phase 1 — How bad is delivery performance?

**8.11% of delivered orders arrived after the promised date.** Roughly 7,800 customers were
given a delivery date the platform did not meet.

---

## Phase 2 — Does lateness move review scores?

| | Orders | Avg score | 1–2 star | 5 star |
|---|---|---|---|---|
| On time | 88,653 | 4.29 | 9.23% | 62.43% |
| Late | 7,700 | 2.57 | **54.03%** | 22.22% |

Over half of all late deliveries produce an actively negative review — **5.9× the on-time
rate**. Both ends of the scale move: the 5-star rate collapses by two-thirds, so this is a
genuine flip from satisfied to angry, not merely fewer delighted customers.

### Dose-response

Grouping by severity rules out most confounding explanations. A third variable can produce a
two-group difference; it rarely produces a clean gradient.

| Days late | Orders | Avg score | 1–2 star |
|---|---|---|---|
| On time or early | 89,944 | 4.29 | 9.28% |
| 1–3 | 1,856 | 3.29 | 32.17% |
| 4–7 | 1,756 | 2.10 | 67.65% |
| 8–14 | 1,452 | 1.68 | 80.03% |
| 15+ | 1,345 | 1.72 | 78.29% |

Two things stand out.

**The steepest drop is between 1–3 and 4–7 days** (+35.5 points of bad-review rate) — the
point where the majority outcome flips from mostly tolerant to mostly angry. If intervention
capacity is limited, the four-day threshold is where it pays.

**Damage saturates around day 8.** The 15+ bucket is marginally *better* than 8–14. Customers
bottom out; there is no marginal review value in rescuing a 20-day-late order over a 10-day
one.

### Sizing the effect

Late orders carry 4,160 bad reviews. But those orders would have failed at the baseline
9.23% rate anyway:

- 7,700 × 9.23% = **711** baseline bad reviews
- 4,160 − 711 = **~3,449 excess bad reviews attributable to lateness**
- 3,449 ÷ 12,343 total = **~28%**

*Assumption: late orders carry the same baseline non-delivery failure rate as on-time
orders. If slow-shipping items (heavy, bulky) also arrive damaged more often, this figure is
somewhat overstated.*

---

## Phase 3 — Where is the damage concentrated?

### Attribution

`order_items` is item-grain, not order-grain. Profiling first:

- **98.7%** of orders involve exactly one seller
- **90.1%** are single-item

Analysis restricted to single-seller orders (1.3% excluded), so every review traces to
exactly one merchant without ambiguity.

### Seller segmentation

412 sellers with ≥50 orders, split on late rate (10%) and bad review rate (20%):

| Segment | Sellers | Orders | Bad reviews | Share |
|---|---|---|---|---|
| Healthy | 282 | 46,882 | 4,927 | **54.6%** |
| Late but forgiven | 98 | 19,729 | 2,783 | 30.8% |
| Late and badly reviewed | 21 | 3,526 | 987 | 10.9% |
| On time but badly reviewed | 11 | 1,278 | 325 | 3.6% |

**Over half the damage comes from sellers doing nothing wrong.** Healthy sellers are on time
with below-average bad review rates — they simply handle half the marketplace's volume. The
32 genuinely problematic sellers account for 14.5% of bad reviews combined.

This is the volume-versus-rate distinction: rates identify who is broken, counts identify
where the damage is. They point to different sellers.

### A hypothesis that failed

The 98 "Late but forgiven" sellers are late 13% of the time with bad review rates under 14%.
The hypothesis: they pad their delivery estimates, so customers are warned and not upset.

**The data rejected it.**

| Segment | Late % | Bad rev % | Promised days | Actual days | Buffer | Days late when late |
|---|---|---|---|---|---|---|
| Late and badly reviewed | 17.0 | 31.1 | 25.4 | 17.4 | 8.1 | 10.1 |
| On time but badly reviewed | 6.0 | 25.5 | 26.6 | 12.8 | **13.8** | 11.8 |
| Late but forgiven | 13.1 | 13.7 | 22.5 | 13.2 | 9.3 | 8.0 |
| Healthy | 5.3 | 9.8 | 23.6 | 11.2 | 12.4 | 8.7 |

Both late segments have near-identical buffers (9.3 vs 8.1 days). The segment with the
*largest* buffer — 13.8 days — still takes 25.5% bad reviews. Padding protects on-time
statistics; it does not protect against unhappy customers.

### What actually tracks

**Absolute wait time**, not punctuality:

| Segment | Actual days waited | Bad review % |
|---|---|---|
| Healthy | 11.2 | 9.8 |
| Late but forgiven | 13.2 | 13.7 |
| Late and badly reviewed | 17.4 | 31.1 |

"Late" is measured against a date Olist chooses. Customers appear to react to how long they
actually waited. A seller quoting 25 days and delivering in 17 is technically on time and
still has an unhappy customer, because 17 days is a long wait.

The exception is instructive: "On time but badly reviewed" delivers in 12.8 days — fast —
and still takes 25.5% bad reviews. Those 11 sellers have a problem delivery speed cannot
explain.

---

## Phase 4 — What is the opportunity worth?

Benchmark: sellers above the median bad-review rate improve to the median. Deliberately
conservative — half of all sellers already perform at or better than this level, so the
target is demonstrably achievable rather than aspirational.

| Metric | Value |
|---|---|
| Sellers above median | 201 |
| Orders affected | 38,567 |
| Current bad reviews | 6,284 |
| Bad reviews at median performance | 4,285 |
| **Recoverable** | **1,999** |
| Median bad review rate | 11.11% |

**1,999 ÷ 12,343 = 16.2%** — roughly one bad review in six.

The value is concentrated in the tail. Many of the 201 sit barely above the median and
recovering anything from them is negligible; the opportunity is really in the worst few
dozen.

---

## Recommendation

Two levers, different targets, **partial overlap — they cannot be summed**:

**Lever A — reduce absolute delivery time (platform-wide).** Ceiling ~3,449 bad reviews
(28%). Requires eliminating lateness entirely, so realistic capture is a fraction.

**Lever B — remediate underperforming sellers.** Ceiling 1,999 (16%). Concentrated in the
worst few dozen merchants, which makes it actionable.

The overlap matters: a below-median seller's late order appears in both figures, a healthy
seller's late order only in A, and a below-median seller's on-time quality failure only in
B.

**Priority order:**

1. **Lever B first** — concentrated, identifiable, actionable
2. **Lever A second** — larger ceiling, harder and slower to move
3. **Commission separate research into on-time bad reviews** — the largest bucket (~8,200,
   two-thirds of the total) and the least understood. These are customers who received
   their order on schedule and were unhappy anyway. The cause lies outside this dataset.

**The headline for a decision-maker: no single intervention solves Olist's review problem.**
Delivery improvements and seller remediation together cap out well below half. Treating this
as a delivery problem alone would over-invest in a lever with a hard ceiling.

---

## Limitations

- **Observational, not causal.** The dose-response gradient makes a confounding explanation
  unlikely but does not eliminate it. An order-level regression controlling for product
  category, weight, and customer region would be the next step.
- **Conditional on delivery.** All figures describe delivered orders. Orders cancelled or in
  transit are excluded by design.
- **Seller-level averages.** Phase 3 comparisons use 4 aggregated rows from 412 sellers.
  Directional, not conclusive.
- **Baseline assumption.** The 28% attribution assumes late orders carry the same
  non-delivery failure rate as on-time orders.
- **Volume floor.** Sellers with fewer than 50 orders are excluded; their rates are
  statistically unstable.

---

## Repository

| File | Contents |
|---|---|
| `sql/01_create_tables.sql` | Table definitions with typed columns |
| `sql/02_analysis.sql` | All analysis queries, phases 1–4 |
| `README.md` | This document |

