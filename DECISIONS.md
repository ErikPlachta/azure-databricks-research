# azure-databricks — DECISIONS

Per-decision rationale for the `0.1.0` medallion design and its relationship to `0.0.1`. Append-only.

## 1. 0.0.1 Kimball → 0.1.0 medallion (architectural break)

**2026-04-27.** 0.0.1 is a single-tier Bridge-Framework Kimball model (`dim`/`bridge`/`fact`/`mart`) optimized for a single analytics consumer. 0.1.0 simulates a multi-source, multi-team enterprise lake to evaluate MV-placement strategies. Different question; different design. 0.0.1 isn't deprecated — it's the right answer for "what does a clean Kimball model look like." 0.1.0 is the right answer for "where do MVs pay off in a layered view stack." Both ship side-by-side in separate Unity Catalog catalogs.

## 2. Why 6 source systems (vs 4 or 1)

**2026-04-27.** User's enterprise env has many sources; demo modelling 1 source loses the bronze unification lesson. 4 sources (state_street/aladdin/aspen/efront) cover the financial-domain breadth. Two more added: `raw_internal_admin` (org/HR for `vbusiness_unit_dim` lineage — without this, team metadata has no plausible source) and `raw_bloomberg` (FX rates — without this, currency normalization has no source). 6 is the smallest set that gives every silver entity a plausible bronze lineage.

## 3. Bronze unification precedence per entity

**2026-04-27.** Aspen treated as default source-of-truth for master attributes (per user). Per-entity precedence in plan §"Bronze precedence". Provenance columns (`<col>_source`, `_source_pref`, `_sources_in_conflict`) emitted on every bronze view; `bronze_lineage_audit` view (07) summarizes hole/conflict counts. Aspen winning isn't absolute — `vsecurity_price` defers to state_street; `vcontract` defers to efront; etc. Provenance makes precedence behavior auditable at row-level rather than buried in code.

## 4. eFront table-shape inferences

**2026-04-27.** User doesn't have eFront's real schema; "use industry-standard". 0.1.0 infers the following:

- `contract_raw` — contract terms (covenants, maturity, principal, rate)
- `contract_summary_raw` — period-end contract snapshots
- `contract_covenant_raw` — per-contract covenant tests + status
- `capital_activity_raw` — calls, distributions, fund cashflows (GP/LP)
- `collateral_exposure_raw` — collateral-level exposure measurement
- `collateral_position_raw` — collateral-position holdings

Column lists and types are best-judgement. Flagged for revision when user provides authoritative shapes (0.2.0 milestone).

## 5. Tables vs MVs operational distinction

**2026-04-27.** Both materialize the same logical view body. Different operational profiles:

| Aspect           | `t_<entity>` table                        | `mv<entity>` MV                                                     |
| ---------------- | ----------------------------------------- | ------------------------------------------------------------------- |
| Refresh trigger  | Manual via `usp_refresh_<entity>`         | Databricks-managed (manual now; SCHEDULE in 0.1.4)                  |
| Refresh strategy | Explicit `INSERT OVERWRITE`               | Enzyme-chosen: ROW_BASED / PARTITION_OVERWRITE / COMPLETE_RECOMPUTE |
| Cost visibility  | Single explicit run                       | `event_log()` + Catalog Explorer                                    |
| Bypass support   | Yes (just don't run the proc)             | No (MV always tracks its source)                                    |
| Best for         | Nightly batch where source rarely changes | Continuous/incremental refresh                                      |

The 0.1.0 demo gradient groups them as "materialized." Production callers must read this entry before swapping a t* for an mv* or vice-versa.

## 6. View/MV byte-equality contract (permanent invariant)

**2026-04-27.** For every entity at every layer, `v<entity>` and `mv<entity>` SELECT bodies must be byte-identical (modulo the `CREATE` clause). This is the load-bearing invariant for apples-to-apples timing comparisons in `06_demos/`. A future refactor that drifts them silently breaks the pedagogy and corrupts comparison results. Lint-style check planned for 0.1.7 CI.

## 7. Why `_all` and `_pivot` patterns are deferred

**2026-04-27.** User's enterprise list shows two patterns not strictly needed by `private_debt`'s 10 views:

- `_all` siblings (UNION current + `investments_historical`) — adds a second schema, ~3 entities × 3 artifacts. ~200 LOC.
- `_pivot` cross-tab dims — uses PIVOT operator at view time. ~2-3 entities × 3 artifacts. ~150 LOC.

Skipped in 0.1.0 to keep scope manageable. Re-add costs estimated above. Documented here so the omission is explicit, not silent — important per user emphasis.

## 8. Why non-PD teams have no gold schema in 0.1.0

**2026-04-27.** Plan caps gold at 5 PD-strategy schemas to keep artifact count manageable (~250 objects already). 5 non-PD teams (`team_re_core`, `team_re_value_add`, `team_pe_buyout`, `team_infra`, `team_public_equity`) are seeded into `vbusiness_unit_dim` and have allocations + facts so silver views genuinely return cross-team rows — strengthens the S2 (silver-MV cross-team-reuse) argument. Their gold schemas land in 0.1.1.

## 9. SCD2-everywhere on silver dims

**2026-04-27.** Per user, all 8 silver `*_dim` entities use full SCD2 (preceding/succeeding chains, effective dates, is_current). Matches 0.0.1's pattern. Heavier seed code (~600-1000 LOC for history simulation) but pedagogically faithful to enterprise reality where dims do restructure over time. `vfx_rate_dim` is the one exception — Type 2 lite (effective dates but no preceding/succeeding chains, since rates simply expire when superseded).

## 10. Bloomberg = FX-only in 0.1.0

**2026-04-27.** Bloomberg is the standard real-world source for both FX rates AND security pricing. State_street already provides position-side pricing in 0.1.0. Adding Bloomberg pricing now would require a precedence-rule for `vsecurity_price` (custodian-prices vs market-quoted-prices), increasing demo complexity. Deferred to 0.1.5. In 0.1.0 Bloomberg supplies FX rates only.

## 11. Free Edition seed defaults

**2026-04-27.** Plan §"Configuration reference" defaults size for Free Edition compute fit (~100K total positions). Each `seed_n_*` var has a paid-workspace override commented inline (~2.5M positions on paid). User can flip via session var without editing seed code. Free Edition's 1-metastore/1-workspace cap doesn't preclude multi-catalog — verified at [MS Learn Free Edition limitations](https://learn.microsoft.com/en-us/azure/databricks/getting-started/free-edition-limitations). 0.1.0 uses `medallion_demo` catalog so 0.0.1 in `workspace` stays untouched.

## 12. Silver schema split (`investments` + `investments_history`) in 0.1.1

**2026-04-30.** 0.1.0's `investments` schema accumulated 23 entities × 3 artifacts (t/v/mv) + MV-backing tables = exactly 100 objects, hitting Free Edition's per-schema cap. Adding any further MV blocked. Split mirrors user's enterprise pattern (`investments` + `investments_historical`). 0.1.1 keeps 17 current entities (8 SCD2 dims + fx_rate_dim + 8 base facts) in `investments`; moves 6 entities (2 monthend + 3 cancels + 1 bridge — `vposition_monthend_fact`, `vportfolio_analytics_monthend_fact`, `vcontract_details_cancels_fact`, `vposition_cancels_fact`, `vsecurity_price_cancels_fact`, `vincome_bridge`) to `investments_history`. Cross-schema FROM clauses are fine in Spark/UC. Headroom estimate: ~30 entities × 3 = 90 in `investments` (fine for 0.1.1; a 0.1.2 expansion may need a further split, e.g., `_dim` → `investments_dims`). Bronze sits at 72/100 — flagged but not split (no immediate scope expansion). See plan p00/14.

## 13. Cascading MV bodies + byte-equality contract relaxation (0.1.1)

**2026-04-30.** Decision 6's strict byte-equality contract caused gold MV materialization to run 2.5h+ before user cancelled — every gold mv body referenced silver `v*` (the views), forcing a full re-cascade through silver views all the way to raw on every gold MV refresh. 0.1.1 relaxes the invariant: v* and mv* SELECT projections are no longer byte-identical, but they ARE _mechanically derivable_ via `s/v/mv/g` substitution at upstream references. Specifically:

- silver `mv*` references bronze `mv*` (instead of bronze `v*`)
- gold `mv*` references silver `mv*` (instead of silver `v*`)
- intra-layer mv references in IN/EXISTS clauses also use mv (e.g., gold mv reads gold mv, not gold v)

The `v*` path stays slow (production-faithful through view stack — pedagogical for "what production reality looks like without MVs"); the `mv*` path is fast (cascading materialized — pedagogical for "what MV layering buys you"). Apples-to-apples timing comparisons in `06_demos/` still hold because the substitution is mechanical and total — every entity at every layer has a paired `v`/`mv` triplet built from the same projection. Lint check planned for 0.1.7 CI: parse v body, mechanically substitute upstream refs, diff against mv body — expect zero structural diff. Supersedes Decision 6's "byte-identical" wording for 0.1.1+; 0.1.0 retains the strict form for legacy reference.

## 14. 0.1.1 gold-tier partial implementation (closed in this milestone)

**2026-05-06.** At the time the 0.1.1 work was first merged (single commit `677c7d8`), the gold tier shipped half-built: the 5 `team_pd_*` schemas + their tables/views/MVs landed, but **(a)** no per-team `refresh_all()` procs existed (no `04_gold/05_refresh_procs.sql` file at all), and **(b)** `gold_pd_consolidated` shipped as schema + 3 tables (`t_vpd_position_book`, `t_vpd_transaction_book`, `t_vpd_contract_book` per `04_gold/02_tables.sql:185-217`) but no views, no MVs, no procs. `00_setup/03_refresh_orchestrator.sql:48-53` already calls `team_pd_*.refresh_all()` and `gold_pd_consolidated.refresh_all()` — the orchestrator was committed pre-supposing those procs existed, so it fails at line 48 on first invocation.

Treated as bug, not omission, because the orchestrator references and the 3 consolidated tables were committed simultaneously with the rest of 0.1.1 — the missing pieces are clearly load-bearing for the design rather than an intentional 0.1.2 split. Closed additively in this milestone (no orchestrator rollback, no schema drop) by adding `04_gold/05_refresh_procs.sql` (~60 procs: 50 team per-entity + 5 team aggregators + 3 consolidated per-entity + 1 consolidated aggregator) and appending Section G (3 cross-team UNION views + 3 cascading MVs) to `04_gold/03_views.sql` and `04_gold/04_materialized_views.sql`. Decision #13's mechanical-derivability contract holds for the consolidated MVs (5-arm UNION ALL with `s/v/mv/g` substitution at every team-schema ref). Stale README claim "drops all 14 schemas" corrected to 15 (6 raw + bronze + investments + investments_history + 5 team_pd + gold_pd_consolidated).

## 15. Silver `vtransaction_fact` added (resolves Decision #14 caveat)

**2026-05-06.** Decision #14 closed the gold-tier gap but left a structural caveat: `gold_pd_consolidated.vpd_transaction_book` sourced directly from `bronze.vtransaction` because no silver `vtransaction_fact` existed in 0.1.1. That bypassed silver entirely for transaction data, broke the medallion tiering invariant for one entity, and put dim_sk resolution + USD/FX normalization in the gold layer instead of silver where it belonged.

Resolution: added `investments.vtransaction_fact` (table + view + cascading mv + refresh proc) modeled on the existing `vposition_analytics_fact` pattern (dedup-by-latest, temporal-resolved `portfolio_sk`/`security_sk` via SCD2 dim BETWEEN joins, USD normalization via `vfx_rate_dim`). `gold_pd_consolidated.vpd_transaction_book` now reads `investments.vtransaction_fact`; the `mv` version cascades via `investments.mvtransaction_fact` (Decision #13 contract preserved). Pre-bronze and bronze layers untouched; bronze.vtransaction is no longer a direct gold source.

Silver entity counts: `investments` 17 → 18 (8 SCD2 dims + fx_rate_dim + 9 facts); total silver across both schemas 23 → 24. Still well under Free Edition's 100/schema cap. The 0.1.5 Bloomberg-pricing milestone gains a similar pattern target (silver fact bridging bronze price sources to gold).

## 16. Free Edition deploy reality (live findings, 2026-05-06/07)

**2026-05-07.** First end-to-end deploy run via `scripts/dbx_run.py` against the live workspace (`dbc-40c058d4-649b.cloud.databricks.com`, plachtastar@gmail.com). Three findings worth promoting to decisions:

1. **Free Edition caps DBSQL pipelines at 1 concurrent**, not just at 1 SQL warehouse. Every `CREATE OR REPLACE MATERIALIZED VIEW` (and every `REFRESH MATERIALIZED VIEW`) provisions a DLT pipeline; the first attempt to submit a second concurrent MV operation fails with `[DLT ERROR CODE: QUOTA_EXCEEDED_EXCEPTION] Limit: 1; used: 2`. Implication: MV creation is **inherently serialized** on Free Edition regardless of how the runner submits statements.
2. **Per-MV cold-start dominates**: each MV refresh observed at ~5–6 min on the serverless 2X-Small + Free Edition tier, even though MV body execution against the 23K-row seed completes in seconds. Cold-start per pipeline (Spark warmup + DLT bootstrap) is the dominant cost. End-to-end deploy budget on Free Edition: bronze ~30 min (14 MVs), silver ~120 min (24 MVs cascading), gold projected ~5 h (53 MVs cascading). Total deploy: 7+ hours wall-clock on Free Edition.
3. **`CAST(p.source_key AS BIGINT)` bug** in `investments_history.vposition_cancels_fact` (silver). `source_key` is a string of the form `'SS_POS_<team>_<id>_<YYYYMMDD>'` — not numeric. Fix: `xxhash64(p.source_key)` (deterministic, stable BIGINT, satisfies `cancelled_position_sk BIGINT NOT NULL`). Other cancels facts use `CAST(NULL AS BIGINT)` for the analogous column; only the position cancel attempted a real cast. Fix applied to both `03_views.sql` and `04_materialized_views.sql`.

Operational consequence for the project: deploys against Free Edition should expect multi-hour runs and benefit from background submission + idempotent retry. Both addressed in `scripts/dbx_run.py` (curl retry on transient network failures + polling that survives client-side timeouts; server-side execution continues even if the client disconnects, so re-running with `CREATE OR REPLACE` is safe).

## 17. Bronze unification gap — cross-system FK source_keys not in the crosswalk (closed via crosswalk augmentation)

**2026-05-09.** End-to-end deploy completed (53/53 gold MVs created, 23K positions seeded, all DDL idempotent), but every gold table is empty after `CALL bronze_silver_gold_refresh()`. Root cause: `bronze.vposition` calls `bronze.fn_resolve_enterprise_key('state_street', p.portfolio_source_key)` to translate a position's portfolio FK to a unified enterprise key. `portfolio_source_key` values are stable portfolio identities (e.g. `'SS_PORT_TEAM_01'`), but no source's `source_key` column equals that string. The crosswalk MERGE in `02_crosswalk.sql` only pulls `(source_system, source_key, enterprise_key)` from each raw table's primary identity columns — so the crosswalk holds entries like `('state_street', 'SS_POS_1_1_20210508', 'EK_POS_1_1_20210508')` and `('aladdin', 'AL_RISK_1_20210508', 'EK_RISK_1_20210508')`, but never `('state_street', 'SS_PORT_TEAM_01', <ek>)`. Resolution returns NULL → silver position fact has 23000 rows with all-NULL `portfolio_sk`/`business_unit_sk` → team-filter joins (`gold.team_pd_*.vposition_analytics_fact JOIN ... ON bu_code = '<team>'`) return 0 rows → gold is empty.

Same gap affects every cross-system FK column in pre-bronze: `position_raw.portfolio_source_key`, `position_raw.security_source_key`, `transaction_raw.portfolio_source_key`, etc. The crosswalk only maps each row's primary identity, not the cross-source foreign keys those rows reference.

Three resolution paths:

1. **Augment the crosswalk MERGE** (smallest surgery, recommended). Add `UNION` arms in `02_crosswalk.sql` that pull `portfolio_source_key`+derived-canonical-EK pairs from `raw_aladdin.portfolio_risk_raw`, `security_source_key` pairs from `raw_aspen.security_master_raw`, etc. Keep the per-row identity entries; just add the cross-system FK entries alongside.
2. **Seed change**: have every source emit consistent canonical `enterprise_key` values per logical entity (e.g. all rows referencing portfolio TEAM_01 get `enterprise_key = 'EK_PORT_TEAM_01'` regardless of source). Larger refactor; touches every raw table in `08_seed.sql`.
3. **Bronze view rewrite**: change `bronze.vposition` to JOIN directly to `raw_aladdin.portfolio_risk_raw` on `portfolio_source_key` for portfolio enterprise_key resolution. Hacky and source-specific; doesn't generalize.

Option 1 is the smallest fix and closest to the intended design. Tracked in plan p01_live_deploy_and_helper as the next phase. Until resolved, `05_validate/02_fk_integrity.sql` will flag this (`orphan_position_portfolio_sks > 0`) and gold tables stay empty.

Validation: `bronze.fn_resolve_enterprise_key` works correctly when given a key actually in the crosswalk (e.g. `'SS_POS_10_10_20210508'` → `'EK_POS_10_10_20210508'`); the bug is in WHAT the crosswalk contains, not the resolver.

**2026-05-09 — closed via Option 1 (crosswalk augmentation + canonical portfolio EK).** Two coordinated changes:

1. `02_bronze/02_crosswalk.sql` MERGE source extended with cross-system FK union arms: every `portfolio_source_key` value in `raw_state_street.{position,transaction,cash_flow,nav}_raw` and `raw_aladdin.portfolio_risk_raw` gets a crosswalk row keyed `('state_street', 'SS_PORT_TEAM_NN', 'EK_PORT_TEAM_NN')` (and the same EK from the aladdin arm), where the canonical EK is derived as `'EK_' || substr(portfolio_source_key, 4)`. Roughly 50 new rows for 10 portfolios × 5 referencing tables; idempotent via `WHEN NOT MATCHED`.

2. Silver `vportfolio_dim` (and cascading `mvportfolio_dim`) now derive `enterprise_key` via the same `'EK_' || substr(r.portfolio_source_key, 4)` formula, replacing the per-row date-suffixed aladdin enterprise_key. So the join chain agrees: bronze's `fn_resolve_enterprise_key` returns `'EK_PORT_TEAM_01'` and the silver dim has rows keyed by exactly that string.

`vsecurity_dim` not touched — `raw_aspen.security_master_raw.source_key` already serves as the stable canonical security identity (3332 aspen entries in the crosswalk via the existing primary-source_key arm), so the cross-system reference from `raw_state_street.position_raw.security_source_key` resolves cleanly.

Acceptance check (post-redeploy): `bronze.vposition` has 0 NULL `portfolio_enterprise_key`; silver `t_vposition_analytics_fact.portfolio_sk` has 0 NULL; team gold tables non-empty.

**Verified live 2026-05-11:** All checks above pass against the actual workspace. `t_vposition_analytics_fact` has 0 NULL `portfolio_sk` and 0 NULL `business_unit_sk` (4999 of 4999 resolved). Team gold tables 351–533 each; `gold_pd_consolidated.t_vpd_position_book` = 2301 = exact sum of 5 teams.

## 18. Silver `vsecurity_master_fact` — Spark INSERT-OVERWRITE attribute-ID collision (worked around)

**2026-05-11.** During the clean-redeploy under DECISIONS #17, the orchestrator's silver-fact refresh chain failed at `investments.refresh_security_master_fact()` with `Cannot find column index for attribute 'bronze_loaded_at#NNNNN'` even though the column name appears in the map. The view body:

```sql
SELECT ..., s.bronze_loaded_at, ...
FROM investments.vsecurity_dim s
LEFT JOIN bronze.vsecurity bs ON bs.enterprise_key = s.enterprise_key
LEFT JOIN investments.vfx_rate_dim fx ON ...
```

Both `s` (silver dim) and `bs` (bronze view) expose `bronze_loaded_at` columns. The SELECT explicitly qualifies `s.bronze_loaded_at`, so semantically there's no ambiguity — but Spark's plan optimizer for `INSERT OVERWRITE` tracks both columns by internal attribute ID and fails to resolve which is which at the target table's `bronze_loaded_at` column. SELECT-only queries from the view work fine; the failure is specific to INSERT OVERWRITE.

Attempts that did NOT fix it:
- Restructuring the LEFT JOIN to a subquery that drops `bs.bronze_loaded_at`.
- Wrapping the body in a CTE so the outer SELECT references only resolved aliases.
- Renaming `s.bronze_loaded_at` to `s_bronze_loaded_at` in the CTE and back at the outer level.
- DROP + CREATE OR REPLACE on both view and proc.
- DROP + CREATE OR REPLACE on the target table.
- Cycling the warehouse to clear Spark plan caches.

Working workaround: remove the bronze.vsecurity LEFT JOIN entirely from `vsecurity_master_fact` and project `bronze_loaded_at` as `CAST(NULL AS TIMESTAMP)`. The `latest_close_price_local`/`latest_close_price_usd` columns become NULL too — they were only enrichment; the same price data is available via `vsecurity_price_fact`. Audit timestamp recoverable via `security_sk` join back to `vsecurity_dim`.

Same workaround applied to the cascading `mvsecurity_master_fact`.

Open: this looks like a real Spark/Databricks runtime bug, not a SQL author error. The pattern (view layered over another view, both aliasing the same underlying `loaded_at` column, INSERT OVERWRITE consuming the outer view) reproduces deterministically. Worth filing with Databricks if we keep hitting it. For now we ship the workaround and document the trade-off.
