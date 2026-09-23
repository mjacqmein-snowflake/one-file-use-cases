# Install the Snowflake-Connected Edition

`backend/dist/Snowflake_Intelligence_Workspace_Setup.sql` is the single SQL
installer. It creates a synthetic retail demonstration in your Snowflake
account, including data, semantic views, Cortex Agents and a Streamlit app.
The standalone HTML remains an offline visual prototype; it does not connect
to Snowflake or persist state across reloads.

## Prerequisites

- A non-trial Snowflake account on a supported AWS or Azure region with hybrid
  tables available.
- An existing approved query warehouse and container compute pool. An empty
  `WORKSPACE_POOL` selects the account's default Streamlit pool.
- An enabled external access integration approved for Python package downloads.
  Set `WORKSPACE_PACKAGE_EAI` to its name; the installer does not create one.
- An installer role authorized to create the isolated database and roles, grant
  warehouse/pool/integration access, and assign Cortex privileges. Ask your
  administrator to review the scope rather than granting broad user access.
- Access to Opus 5 for portfolio questions. Brand and custom specialists use
  automatic model selection. Availability depends on your account and routing.

## Run

1. Open the SQL file in a Snowflake worksheet with your approved installer role
   and warehouse selected.
2. Review the first nine settings. Choose a new database and two new role names.
   Keep the three gates FALSE for the first run; it reports preflight only and
   creates no objects.
3. Set `WORKSPACE_PACKAGE_EAI` and verify the selected warehouse/pool. To install
   the complete demo, set `WORKSPACE_INSTALL`, `WORKSPACE_AI` and
   `WORKSPACE_HOST` to TRUE, then run the whole file.
4. Read the returned status for both AI and HOST. Open
   `<your database>.APP.EXECUTIVE_WORKSPACE` in Snowsight. First startup may
   install dependencies; an existing app is not replaced by rerunning the installer.
5. Ask for net revenue by brand for September 7-13, 2026. Review the query
   evidence, choose Generate chart, and add it to the dashboard. Reload to
   verify your chart is retained.

## Scope

All business records are fictional. The five brands are Harbor Retail, Summit
Outfitters, Grove Goods, Metro Apparel and Coast Supply. Weekly charts and agent
questions use the installed synthetic retail snapshot. Live Intelligence is a
separate, explicitly simulated event feed, not live ingestion.

The installed edition includes real Cortex questions, chart suggestions and
on-demand previews, click/drag placement, persistent dashboard state, conflict
handling, quiet autosave, scoped specialists, compact startup data, exact-image
deduplication, startup retry and source-digest backend loading.

Email, Slack and Teams remain disabled. Reviews are records, not business-system
actions. Fictional personas are presentation scopes, not production access
controls. Do not connect sensitive business data without a separately reviewed
authorization and data-adapter design. Check AI explanations against the returned
evidence; a previous model response misstated a total despite correct query rows.

The installer uses existing shared compute without resizing it or changing its
settings. Container, warehouse, storage and AI use incur charges. No scheduled
refresh is installed, and no fixed-price estimate or free-use claim is made.

## Rerun And Removal

Rerunning preserves saved state and existing app/agent objects. It does not
upgrade a deployed app's source. Readable source is staged in the installed
database; source-only changes should be reviewed and backed up before publishing.

Call `OPS.TEARDOWN(NULL)` in the installed database to read the removal contract.
Actual teardown requires its explicit confirmation string and deletes that
database, including saved work. Shared compute, integrations and account roles
remain. `OPS.RESET_SAVED_STATE(NULL)` similarly describes, but does not perform,
a saved-state reset. Hybrid-table deletions do not have ordinary standard-table
Fail-safe/UNDROP recovery.

This is an illustrative sample, not an official Snowflake product or a certified
production application. Validation in an isolated database on the author's
account does not guarantee installation in every other account.
