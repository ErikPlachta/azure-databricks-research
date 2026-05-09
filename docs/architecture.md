# Architecture

The project is a **4-tier medallion lakehouse**: data flows from raw landings through three refinement layers, with each tier doing strictly more business logic than the one below it. This doc explains each tier, why it exists, and what it produces.

For new terms, see [glossary.md](glossary.md). For what the data represents, see [data-domain.md](data-domain.md).

## Why 4 tiers (not the classic 3)

The standard medallion pattern is bronze → silver → gold. We added a **pre-bronze** tier for one reason: in real enterprises, raw landing tables are operationally distinct from the bronze views built on top of them (different ownership, different refresh cadence, different schemas). Modeling that boundary explicitly makes the bronze unification logic legible.

```
pre-bronze  →  bronze  →  silver  →  gold
  raw          unified     business    consumer
  per source   crosswalk   logic       per team
```

## Tier 1 — Pre-bronze (raw landings)

**Purpose:** mirror what each source system actually emits. Tables only — no views, no MVs, no business logic.

**Schemas (6, one per source system):**

| Schema | Source system | What it represents |
| --- | --- | --- |
| `raw_state_street` | State Street (custodian) | Positions, transactions, security prices, cash flows, NAVs |
| `raw_aladdin` | BlackRock Aladdin | Portfolio risk, performance, compliance, trade blotter |
| `raw_aspen` | Aspen (master data) | Entity masters, securities, assets, ratings, hierarchies |
| `raw_efront` | eFront | Loan contracts, summaries, covenants, capital activity, collateral |
| `raw_internal_admin` | Internal HR/org | Business units, employees, organizational structures |
| `raw_bloomberg` | Bloomberg | FX rates only (in 0.1.1 — security pricing planned for 0.1.5) |

Every raw table carries two synthetic columns to enable bronze unification: `source_key` (the source's natural key) and `enterprise_key` (the cross-source unification key).

The seed (`01_pre_bronze/08_seed.sql`) populates all six schemas deterministically — same config produces identical data across runs.

## Tier 2 — Bronze (cross-source unification)

**Purpose:** unify all 6 sources into one entity per concept, with full provenance.

**Schema:** `bronze` (one schema for all unified entities).

**Key mechanisms:**

- **Crosswalk** — `bronze.crosswalk` is a lookup table mapping `(source_system, source_key) → enterprise_key`. Two UDFs (`fn_resolve_enterprise_key`, `fn_resolve_source_keys`) bridge between source-local IDs and the cross-source unified ID.
- **Precedence rules** — for each entity, one source is the "default" winner (Aspen for entity master data, State Street for security prices, eFront for contracts, etc.). Per-column overrides allowed.
- **Provenance columns** — every attribute carries `<col>_source` (which system it came from), `<col>_source_pref` (the precedence rank), and `<col>_sources_in_conflict` (whether sources disagreed). This makes the unification decisions auditable at row level.

**Per-entity artifacts (the t/v/mv triplet):**

Every bronze entity ships as a triplet:
- `t_<entity>` — Delta table (physical, populated by a refresh proc)
- `v<entity>` — view (logical, computed on read)
- `mv<entity>` — materialized view (cached, auto-refreshed by Databricks)

This triplet is the structural unit of the entire stack — it shows up in bronze, silver, and gold. The triplet is what enables the MV-placement experiment (see below).

**Bronze entities (14):** security, entity, asset, portfolio, position, transaction, contract, collateral, security_price, portfolio_risk, portfolio_performance, rating, business_unit, fx_rate.

## Tier 3 — Silver (business logic)

**Purpose:** turn bronze unified entities into analysis-ready dimensions and facts. SCD2 dimensions, temporal-resolved fact joins, USD currency normalization.

**Schemas (split into 2 — Free Edition's 100-objects-per-schema cap forced this):**

### `investments` — current state (18 entities)

The "live" dimensions and facts.

- **8 SCD2 dimensions:** `vsecurity_dim`, `vsecurity_rating_dim`, `vcontract_dim`, `vportfolio_dim`, `ventity_dim`, `vsecurity_industry_dim`, `vreporting_group_dim`, `vbusiness_unit_dim`
- **1 SCD2-lite dim:** `vfx_rate_dim` (effective dates only — no chain pointers, since FX rates simply expire)
- **9 facts:** `vcontract_details_fact`, `vcontract_summary_fact`, `vportfolio_analytics_fact`, `vposition_analytics_fact`, `vsecurity_master_fact`, `vsecurity_price_fact`, `vtransactions_collateral_lifecycle_fact`, `vtransactions_collateral_settlement_fact`, `vtransaction_fact`

### `investments_history` — corrections and snapshots (6 entities)

Anything that's not "current."

- **Monthend snapshots (2):** `vposition_monthend_fact`, `vportfolio_analytics_monthend_fact` — month-end frozen views for SEC/accounting reporting.
- **Cancels (3):** `vcontract_details_cancels_fact`, `vposition_cancels_fact`, `vsecurity_price_cancels_fact` — duplicate-correction rows that analysts use to audit out erroneous transactions.
- **Bridges (1):** `vincome_bridge` — interest-accrued vs interest-paid reconciliation, captures P&L timing mismatches.

### Why split?

Free Edition caps a single schema at 100 objects. 0.1.0 used a single `investments` schema and hit exactly 100, blocking further additions. The split mirrors the user's enterprise pattern (`investments` + `investments_historical`) and is what enabled 0.1.1 to add `vtransaction_fact` and the gold consolidated layer. See [DECISIONS.md #12](../DECISIONS.md#12-silver-schema-split-investments--investments_history-in-011) and [free-vs-paid.md](free-vs-paid.md).

### SCD2 mechanics

Each silver dimension tracks history with:
- `effective_start_date`, `effective_end_date` — when this version was true
- `is_current` — flag for the latest version
- `preceding_record_sk`, `succeeding_record_sk` — chain pointers for traversing history
- A surrogate key (`<entity>_sk`) that's unique **per version** (not per entity)

Facts join dimensions via temporal `BETWEEN`: `fact.event_date BETWEEN dim.effective_start_date AND dim.effective_end_date`. This guarantees a March 2025 position joins to the contract dim row that was current in March 2025 — not whatever the contract looks like today.

The seed injects realistic SCD2 churn: ~25 entity restructurings, ~10 security reissues, ~20 contract amendments per run.

## Tier 4 — Gold (consumer-facing)

**Purpose:** team-specific marts. Each private-debt strategy team gets its own schema with its own filtered/derived views.

**Schemas (6 total):**

| Schema | Contents |
| --- | --- |
| `team_pd_direct_lending` | 8 facts + 2 dim subsets (filtered to this team) |
| `team_pd_distressed` | Same shape, filtered to distressed |
| `team_pd_mezzanine` | Same shape, filtered to mezzanine |
| `team_pd_real_estate_debt` | Same shape, filtered to RE debt |
| `team_pd_specialty_finance` | Same shape, filtered to specialty finance |
| `gold_pd_consolidated` | 3 cross-team UNIONs: position book, transaction book, contract book |

Each team schema has 10 objects (8 fact views + 2 dim views). The consolidated schema has 3 cross-team facts that UNION all 5 teams' rows with a team tag.

**Liquid clustering** is applied to gold facts on `(date_col, portfolio_sk)` and to dim subsets on `(enterprise_key)` for query pruning.

5 non-PD strategy teams (RE core, RE value-add, PE buyout, infra, public equity) have rows in `vbusiness_unit_dim` and silver facts but no gold schemas in 0.1.1 — those land in 0.1.2. See [PLAN.md](../PLAN.md).

## The MV-placement experiment

The whole reason for this 4-tier stack is to answer: **where in a multi-tier view stack should materialized views live?**

Every entity at every layer ships as a t/v/mv triplet. This lets us swap which one each layer references and measure the cost/latency impact.

### Five scenarios

| # | Bronze | Silver | Gold | What it teaches |
| --- | --- | --- | --- | --- |
| **S0** | `v` | `v` | `v` | Production reality with no caching. Cross-team queries cascade through every layer; usually times out at scale. |
| **S1** | `v` | `v` | `mv` | Cache the final answer per team. Cheap (5 PD teams = 5 MVs). Fast queries, simple refresh. |
| **S2** | `v` | `mv` | `v` | Cross-team reuse. **One** silver MV refresh services all 10 teams. Often the production-recommended choice. |
| **S3** | `v` | `mv` | `mv` | Cascading. Best query speed; refresh chains stay tolerable because each layer's MV reads the materialized layer below. |
| **S4** | `mv` | `mv` | `mv` | Counter-pattern. Every layer materializes independently; refresh cost spirals. |

### What the project actually ships

0.1.1 ships **S3** for the `mv*` path (silver MVs read bronze MVs; gold MVs read silver MVs) and **S0** for the `v*` path (every view reads upstream views). Both paths exist side-by-side so demos can compare them apples-to-apples.

This was an evolution: 0.1.0 used a strict byte-equality contract between `v*` and `mv*` bodies, which forced gold MVs to read silver `v*` (slow). Gold materialization took 2.5+ hours. 0.1.1 relaxed to **mechanical derivability** (`mv` body derives from `v` body via `s/v/mv/g` substitution at upstream references), enabling cascading. Materialization dropped to ~5–10 minutes. See [DECISIONS.md #13](../DECISIONS.md#13-cascading-mv-bodies--byte-equality-contract-relaxation-011).

## Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│  pre-bronze (6 schemas, tables only)                             │
│    raw_state_street  raw_aladdin  raw_aspen                      │
│    raw_efront        raw_internal_admin  raw_bloomberg           │
│         │                                                         │
│         ▼                                                         │
│  bronze (1 schema, 14 entities × t/v/mv = 42 objects)            │
│    crosswalk + precedence + provenance                            │
│         │                                                         │
│         ▼                                                         │
│  silver (2 schemas)                                               │
│    investments         (18 entities × t/v/mv = ~54 objects)      │
│    investments_history (6 entities × t/v/mv = ~18 objects)       │
│         │                                                         │
│         ▼                                                         │
│  gold (6 schemas)                                                 │
│    team_pd_direct_lending     │  10 objects per team             │
│    team_pd_distressed         │  (8 facts + 2 dims)              │
│    team_pd_mezzanine          │                                   │
│    team_pd_real_estate_debt   │                                   │
│    team_pd_specialty_finance  │                                   │
│    gold_pd_consolidated       │  3 cross-team UNIONs             │
└─────────────────────────────────────────────────────────────────┘
```

## What this design is *not*

- **Not production.** It's a teaching artifact — every shortcut and every indirection is there to illustrate a concept.
- **Not the only valid medallion shape.** Plenty of real lakehouses skip pre-bronze, fold cancels into the main fact, or use SCD1 for some dims. We chose the maximally-illustrative variant.
- **Not the legacy 0.0.1.** That ships in catalog `workspace` as a single-tier Kimball model (`bridge`/`dim`/`fact`/`mart`). Different question, different design — kept side-by-side for reference.
