# DB Consistency Check Protocol

Reference protocol for inline database consistency verification. Embedded verbatim in plans via the self-containment mandate — agents execute checks without needing this file post-reset.

---

## Baseline Capture

Before any DB modification (seeding, test execution), capture record counts per collection/table via `connectionCommand`. Store as `dbBaseline` in agent context.

```
dbBaseline = {
  "<collection/table>": <count>,
  ...
}
```

Command patterns:
- **MongoDB**: `db.getCollectionNames().forEach(c => print(c + ": " + db[c].countDocuments({})))` via `connectionCommand`
- **SQL**: `SELECT tablename, n_live_tup FROM pg_stat_user_tables ORDER BY tablename;` or equivalent via `connectionCommand`

---

## POST_SEED Checks

Run immediately after seeding completes, before test execution begins.

| # | Check | How | PASS | WARN | FAIL |
|---|-------|-----|------|------|------|
| 1 | Record count verification | Compare current counts to `dbBaseline` + expected seed counts. Only collections/tables targeted by seeding should have increased. | Counts match expected | Minor count deviation (<5%) | Missing seeds or wrong counts |
| 2 | Schema conformance | Sample seeded records, compare fields/types against discovered schema from seed schema discovery step | All fields/types match | Extra non-breaking field | Missing required field or type mismatch |
| 3 | Referential integrity | For seeded records with foreign keys/refs: verify referenced documents/rows exist | All refs resolve | — | Orphan reference found |
| 4 | No collateral writes | Compare non-seeded collection/table counts to `dbBaseline` — must be identical | No changes to non-target collections/tables | — | Unexpected writes to non-target collections/tables |

---

## POST_TEST Checks

Run immediately after test execution completes, before cleanup begins.

| # | Check | How | PASS | WARN | FAIL |
|---|-------|-----|------|------|------|
| 1 | Orphan scan | Query for `testDataPrefix` records with broken references (foreign keys/refs pointing to non-existent documents/rows) | No orphans | — | Orphan records found |
| 2 | Duplicate scan | Query for duplicate records within `testDataPrefix` scope where uniqueness is expected | No duplicates | — | Duplicates found |
| 3 | Mutation audit | Compare non-test record counts (records WITHOUT `testDataPrefix`) to `dbBaseline` — must be identical | Pre-existing data untouched | — | Non-test data modified |
| 4 | Unexpected collections/tables | Compare current collection/table list to `dbBaseline` collection/table list | No new collections/tables | New index created (non-blocking) | Unexpected collection/table created |

---

## POST_CLEANUP Checks

Run immediately after cleanup completes, before documentation or finalization.

| # | Check | How | PASS | WARN | FAIL |
|---|-------|-----|------|------|------|
| 1 | Cleanup completeness | Count records matching `testDataPrefix` — must be 0 | Zero test records remain | — | Test records still present |
| 2 | Pre-existing preservation | Compare non-test record counts to `dbBaseline` — must be identical | Pre-existing data preserved | — | Pre-existing data lost or modified |
| 3 | Structural integrity | Verify collections/tables and indexes from `dbBaseline` still exist | All structures intact | — | Collection/table or index dropped |

---

## POST_FIX Checks

Run after fix application (autonomous-fixes only). **Conditional**: skip for non-DB fixes (fixes that do not touch DB-interacting code).

| # | Check | How | PASS | WARN | FAIL |
|---|-------|-----|------|------|------|
| 1 | No unintended writes | Compare current record counts to pre-fix counts — only expected changes allowed | Counts match expectations | — | Unexpected record count change |
| 2 | Schema intact | Sample records from affected collections/tables — fields/types must match pre-fix schema | Schema unchanged | — | Schema altered |
| 3 | No orphans introduced | Query for broken references in affected collections/tables | No orphans | — | Orphan records introduced |

---

## Result Format

Each check point produces a structured result:

```
DB_CONSISTENCY: {CHECK_POINT}
  Checks: {passed}/{total}
  Status: {PASS | WARN | FAIL}
  Details:
    - Check 1: {PASS | WARN | FAIL} — {detail if not PASS}
    - Check 2: {PASS | WARN | FAIL} — {detail if not PASS}
    ...
```

### Status Rules

- **PASS**: All checks passed — no issues.
- **WARN**: Unexpected but non-blocking anomaly (e.g., extra index created, minor count deviation). Does not block execution. Reported in documentation.
- **FAIL**: Data integrity violation (orphans, mutations to non-test data, missing seeds, schema damage). Reported as finding. May block subsequent phases at orchestrator discretion.

### Reporting

Agents include DB consistency results alongside suite PASS/FAIL when reporting back to orchestrator. Results flow into test-results/fix-results documentation under a `### DB Consistency` subsection when any check returned WARN or FAIL.
