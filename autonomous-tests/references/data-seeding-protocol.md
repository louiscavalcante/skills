# Data Seeding Protocol

Reference protocol for test data seeding, management, and cleanup. Embedded verbatim in plans via the self-containment mandate — agents execute seeding without needing this file post-reset.

---

## Seed Schema Discovery

Before inserting into ANY collection/table, agents MUST complete schema discovery:

1. **Query real document/row**: `findOne` / `SELECT * LIMIT 1` (without test prefix filter) to use as schema template
2. **If empty**: Read the backend service code that creates documents in that collection — look for `insertOne` / `find_one_and_update` / `INSERT` / ORM create calls
3. **Mirror exactly**: Reproduce the discovered schema — never invent fields or change types (ObjectId vs string, Date vs string, enum values, etc.)
4. **Test marker only**: Add `_testPrefix` marker as the only extra field
5. **Related projects**: Use the connection command from `relatedProjects[]` config or the cross-project seed map in the Feature Context Document

After all seeds (main + related projects): hit API read endpoints to verify serialization before proceeding.

---

## Explicit Data Seeding Plan Format

Each suite agent receives a seeding plan with this structure:

```
SEEDING PLAN:
  Table/Collection: {name}
    Fields: {field1} ({type}), {field2} ({type}), ...
    Example: { field1: "test_e2e_value1", field2: 42, ... }
    Create via: curl -X POST http://localhost:8000/api/{resource} -H "Content-Type: application/json" -d '{...}'
    — OR —
    Create via: docker compose exec mongodb mongosh dbname --eval 'db.{collection}.insertOne({...})'

  Table/Collection: {name}
    Fields: ...
    Create via: ...
```

### testDataPrefix Usage

- ALL test data MUST use the configured `testDataPrefix` (e.g., `test_e2e_`)
- Apply prefix to identifiable string fields: names, emails, titles, slugs
- Example: `test_e2e_user@example.com`, `test_e2e_Product Name`, `test_e2e_order_123`
- The prefix enables targeted cleanup without affecting pre-existing data
- For numeric/boolean/date fields where prefix is impractical, add a `_testPrefix: true` marker field

### Cross-Project Seed Map

When E2E flows span multiple services, seeding must be coordinated:

```
CROSS-PROJECT SEEDS:
  Project: {related project name}
    Connection: {connectionCommand from relatedProjects[] or config}
    Table/Collection: {name}
      Required fields: {field1}, {field2}, ...
      Relationship: {how this relates to main project data}
      Create via: {command}
```

---

## Seeding Instructions Template

Embed this block in each suite agent's prompt:

```
DATA SEEDING INSTRUCTIONS:
  1. Capture dbBaseline BEFORE any writes
  2. Execute seed schema discovery for each target collection/table
  3. Create test data using testDataPrefix "{prefix}" on all identifiable fields
  4. Verify seeds via API read endpoints (not just DB queries)
  5. Run POST_SEED consistency check
  6. Proceed to test execution only after POST_SEED passes

  Seed data for this suite:
  {per-collection seeding plan from above}

  Cross-project seeds (if applicable):
  {cross-project seed map entries relevant to this suite}
```

---

## Cleanup Instructions

After test execution and POST_TEST check, cleanup removes all test data:

1. **Query**: Find all records matching `testDataPrefix` or `_testPrefix: true`
2. **Delete**: Remove matching records only — NEVER touch pre-existing data
3. **Cross-project cleanup**: Remove test records from related project databases using their connection commands
4. **Verify**: Run POST_CLEANUP consistency check — zero test records must remain, pre-existing data must be preserved
5. **Log**: Record what was deleted (collection/table names, record counts)

Cleanup order: dependent records first (child before parent), respecting referential integrity.

```
CLEANUP:
  1. Delete from {child_collection} where {prefix_field} matches testDataPrefix
  2. Delete from {parent_collection} where {prefix_field} matches testDataPrefix
  3. Cross-project: delete from {related_collection} via {connectionCommand}
  4. Verify: count records matching testDataPrefix — must be 0
  5. Verify: non-test record counts match dbBaseline
```
