# Install The Snowflake-Connected Edition

Run `backend/dist/Snowflake_Intelligence_Workspace_Setup.sql` unchanged with an
approved warehouse and source database selected. Initial installation, app hosting
and AI are enabled. The final result includes `STATUS`, `OPEN_APP_URL` and
`NEXT_ACTION`. The existing UI opens with explicitly synthetic retail data.

An account administrator must already have approved a container compute pool and
package-download integration. An empty pool setting selects the account default;
an empty integration setting selects only a unique enabled integration with PYPI
or PACKAGE in its name. Ambiguous or unavailable prerequisites are reported, not
invented. The installer uses isolated roles and its owned database. It does not
resize shared compute or install scheduled refreshes. Warehouse, container,
storage and AI use incur charges.

## Connect Customer Data

Open the globe control, **Source discovery**, in the existing workspace.
Choose a source database, then **Discover sources**. Discovery uses the viewer's
restricted caller connection, inventories up to 12 visible relations and 32
columns per relation, and requests up to three AI mapping proposals. This is
bounded metadata discovery, not an exhaustive autonomous search.

Review or edit the source, native date column, optional grouping dimension,
numeric measure, aggregation and unit. **Preview mapping** reads aggregates for
the last 14 source days. **Activate customer data** replaces the demo canvas with
the actual query-result chart without changing the app layout. Source row count
means rows, not orders, patients, customers or any other inferred entity.

Customer mode supports one source and one reviewed metric at a time. Questions
can request its trend, grouping breakdown or total over 1-90 source days. AI
selects only a bounded operation; the application executes fixed, parameterized
SQL, never model-written SQL. Units remain in source units, with no inferred
currency conversion. No joins, forecasts, inferred ratios, retail relabeling or
synthetic fallback are performed. NULL is unknown; missing dates are not padded
with fabricated zeros. More than 200 grouped results is a visible refusal.

**Return to synthetic** restores the original saved demo work. Customer evidence
and layouts are session-local and isolated by mapping and caller-role fingerprint;
they are not written into owner-readable demo state tables. Reopening the app or
activating again starts a fresh customer canvas and rechecks source access. There
is no persistent customer-data dashboard adapter in this release. Synthetic agents,
simulated monitoring, shared reviews and messaging are disabled in customer mode.

## Caller Access

Container runtime and Streamlit 1.53.1 or newer are required; this installer pins
1.63.0. Caller connections are established at startup. Caller mode uses the
viewer's default Snowflake role, not necessarily the selected Snowsight role.
The authenticated viewer must match `CURRENT_USER()`.

An administrator with `MANAGE CALLER GRANTS` must allow the app owner role to use
the viewer's existing privileges on the selected source database/schema and
table or view. These grants do not give the viewer new privileges. No source
grants are applied automatically by the app. For example, with actual approved
identifiers substituted:

```sql
GRANT CALLER USAGE ON DATABASE SOURCE_DB TO ROLE WORKSPACE_EXECUTIVE_RUNTIME;
GRANT CALLER USAGE ON SCHEMA SOURCE_DB.SOURCE_SCHEMA TO ROLE WORKSPACE_EXECUTIVE_RUNTIME;
GRANT CALLER SELECT ON TABLE SOURCE_DB.SOURCE_SCHEMA.SOURCE_TABLE TO ROLE WORKSPACE_EXECUTIVE_RUNTIME;
```

Use `ON VIEW` for a view. The viewer also needs usable warehouse and AI privileges
for discovery/questions, including `USE AI FUNCTION AI_COMPLETE` where required.
Restricted-caller errors can name the internal `SYSTEM$MANAGED` role. Configure
the actual app owner role, not a system role. Narrow database/schema/table caller
grants to the app owner were sufficient for the hosted source-preview test.
Missing AI access leaves manual mapping available. Missing source access prevents
preview/activation. The application never substitutes an owner-rights source
query. Row-access and masking policies remain enforced by Snowflake.

## Upgrade Existing Apps

Select the existing workspace database and run
`backend/dist/Snowflake_Intelligence_Workspace_Upgrade.sql`. This source-only
upgrade validates the ownership marker and existing container app, backs up its
live source inside the account, stages the new code, copies it into the existing
app and commits. It preserves `deployment.json`, the app object and its grants,
and all business/demo tables. The receipt contains the app URL, backup path and
exact rollback SQL. Open a fresh app session after upgrading.

An ordinary setup rerun still preserves the deployed app source. It is not a
substitute for this upgrade file. The standalone HTML remains an offline visual
prototype and does not connect to Snowflake.

## Validation And Removal

Local tests cover mapping/type validation, caller-identity denial, null/sparse
results, bounded query generation, dataset isolation and the existing demo
contracts. Separate hosted, distinct-user policy tests are required before
calling the customer adapter production-ready. A created Streamlit object does
not prove that it rendered or successfully queried customer data.

Call `OPS.TEARDOWN(NULL)` in the installed database to read the removal contract.
Actual teardown requires explicit confirmation and deletes that database and its
saved work. Shared compute, integrations and roles remain. Hybrid-table deletes
do not have ordinary standard-table Fail-safe/UNDROP recovery.

This is an illustrative sample, not an official Snowflake product or a certified
production application.
