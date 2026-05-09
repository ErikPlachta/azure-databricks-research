# Data Domain

The data this project models, in plain English. No finance background assumed.

For how the data flows through the tiers, see [architecture.md](architecture.md). For term definitions, see [glossary.md](glossary.md).

## What we're simulating

A **private debt fund**. Plain English: an investment firm that lends money to companies (instead of buying their stock). The fund holds a portfolio of loans and loan-like securities, manages collateral backing those loans, and reports performance to investors.

Why a private-debt fund? Because the user works on data infrastructure for one. The architecture lessons are the same for any multi-source enterprise lakehouse — the domain is just enough realism to keep the SQL legible.

The fund has **10 strategy teams** in the seed:
- 5 PD (private-debt) teams: direct lending, distressed, mezzanine, real-estate debt, specialty finance
- 5 non-PD teams (private equity, real estate, infrastructure, public equity) — present in `vbusiness_unit_dim` and silver facts so cross-team queries return real rows, but no gold marts in 0.1.1

## Entities

These are the "nouns" of the domain. Each has a SCD2 dimension in silver (so we track history of attribute changes).

| Entity | Real-world meaning | Default seed scale |
| --- | --- | --- |
| **Security** | A tradable financial instrument — a bond, a loan, a fixed-income note. Has issuer, coupon, maturity, rating. | 200 (Free) / 700 (paid) |
| **Entity** (counterparty) | A company we deal with — borrower, issuer, partner. Can restructure, get acquired, go bankrupt. | 100 / 200 |
| **Asset** | Collateral backing loans — real estate, equipment, securities, receivables. | 60 / 300 |
| **Contract** | A loan agreement — principal, coupon, spread, maturity, covenants. Amends over its lifetime. | 100 / 500 |
| **Portfolio** | A grouping of positions managed by one team for one strategy. | ~10 |
| **Business unit** | An internal team (e.g., `team_pd_distressed`). | 10 |
| **Reporting group** | Hierarchy nodes for rolling up portfolios into segments. | ~5 |

## Events

The "verbs" — operational rows that flow through fact tables. These are the high-volume, time-series side of the domain.

| Event | What it captures | Default seed scale |
| --- | --- | --- |
| **Position** | A daily holding: portfolio X owns N units of security Y on date D, with market and book value. | ~20–25K (Free) |
| **Transaction** | A trade or cash event — buy, sell, interest accrual, principal payment, settlement. | varies; ~20 per security per year |
| **Security price** | Daily price for each security. | days × securities |
| **Cash flow** | Coupon payments, principal repayments, distributions. | varies |
| **NAV** | Net asset value of a portfolio at a point in time. | daily |
| **Portfolio risk** | Risk metrics (duration, DV01, etc.) per portfolio per period. | periodic |
| **Portfolio performance** | Return metrics per portfolio per period. | periodic |
| **Compliance check** | Aladdin compliance pass/fail per portfolio per rule. | periodic |
| **Trade blotter** | Aladdin's order/execution record. | per trade |
| **Rating** | Credit rating per security/entity, with effective dates (rating histories). | series |
| **FX rate** | Bloomberg's daily currency rate (USD vs EUR/GBP/JPY/CAD/AUD). Drives USD normalization in silver. | daily × 5 |
| **Capital activity** | Fund-level GP/LP cash flows — capital calls and distributions. | periodic |
| **Collateral exposure / position** | eFront's collateral measurement and holdings rows. | periodic |

## Edge cases the seed deliberately injects

The seed is not just "happy path" data. It bakes in the messy real-world cases that make a lakehouse interesting.

### SCD2 corrections (~25–55 per run)

Every run injects deliberate dimension churn so SCD2 chains are non-trivial:
- ~25 entity restructurings (counterparty renames, M&A)
- ~10 security reissues (CUSIP changes, bond exchanges)
- ~20 contract amendments (covenant changes, maturity extensions)

Each correction lands as a "v2" row with a later `effective_start_date`. Silver detects the matching `enterprise_key` and chains the rows via `preceding_record_sk`/`succeeding_record_sk`.

**Why it matters:** without SCD2 churn, you'd never exercise temporal joins or chain traversal. The pedagogy needs realistic chains.

### Cancels (corrections of bad rows)

The seed injects a small number of duplicate rows where the second is a correction of the first (e.g., "we double-counted that position"). Silver detects them and routes the corrections into `investments_history.*_cancels_fact` tables. Analysts join cancels to the live fact to audit out the erroneous rows.

**Why it matters:** real source systems emit corrections constantly. The lakehouse has to surface them without losing the audit trail.

### Month-end snapshots

The seed flags month-end dates so silver can build `*_monthend_fact` tables — point-in-time frozen views aligned to the SEC/accounting reporting cadence.

**Why it matters:** "as of month-end" reporting is a different query pattern from "current state" reporting and demonstrates why split current/historical schemas exist.

### Multi-currency

5 non-USD currencies (EUR, GBP, JPY, CAD, AUD) appear in positions/transactions. Silver normalizes everything to USD via `vfx_rate_dim` (SCD2-lite). Without this, the `BETWEEN`-join temporal pattern wouldn't have a low-stakes case to demonstrate.

### Inter-source disagreement

Aspen and State Street both emit security master attributes. Sometimes they disagree on, e.g., a security's coupon — the seed injects deliberate conflicts. Bronze precedence rules pick a winner; provenance columns surface the conflict so analysts can spot it.

## Determinism

Every value the seed generates derives from `sha2(seed_components, 256)`. There's no `rand()`, no `uuid()`, no system clock. **Same configuration ⇒ byte-identical data.**

This matters for:
- **Validation gates** — `05_validate/*.sql` asserts specific row counts. They'd be impossible against random data.
- **Performance comparisons** — apples-to-apples timing of view-vs-MV-vs-table requires identical inputs.
- **Demo reproducibility** — the user can re-run the deploy weeks later and get the same query results.

The default seed config sizes for Free Edition (~100K total positions). A paid-workspace override (`packages/0.1.1/00_setup/01_config.sql`) flips to ~2.5M positions. See [free-vs-paid.md](free-vs-paid.md).

## What the data is *not*

- **Not real production data.** Every number is synthetic; every entity name is procedurally generated.
- **Not financial advice.** Don't infer industry numbers from the seed. The scale and ratios are sized for legibility, not realism.
- **Not eFront's real schema.** eFront's table shapes are inferred from industry-standard usage; flagged for revision when authoritative shapes are available. See [DECISIONS.md #4](../DECISIONS.md#4-efront-table-shape-inferences).

## Where to look in the code

- Seed orchestrator: [`packages/0.1.1/01_pre_bronze/08_seed.sql`](../packages/0.1.1/01_pre_bronze/08_seed.sql) — 6 phases, ~800 lines
- Seed configuration: [`packages/0.1.1/00_setup/01_config.sql`](../packages/0.1.1/00_setup/01_config.sql) — Free vs paid sizing knobs
- Bronze unification: [`packages/0.1.1/02_bronze/02_crosswalk.sql`](../packages/0.1.1/02_bronze/02_crosswalk.sql) — crosswalk table + UDFs
- Silver SCD2 patterns: [`packages/0.1.1/03_silver/03_views.sql`](../packages/0.1.1/03_silver/03_views.sql) — pattern docs in the file header
