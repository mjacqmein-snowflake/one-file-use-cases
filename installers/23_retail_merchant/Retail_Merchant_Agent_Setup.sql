-- ─────────────────────────────────────────────────────────────────────────────
-- Retail Merchant Agent
-- SETTINGS  ·  the only part of this file intended to be edited
-- ─────────────────────────────────────────────────────────────────────────────

-- The gate. Nothing is created while this is FALSE.
SET MERCHANT_APPROVE = FALSE;

-- Where to build. Blank means the database currently in use.
SET MERCHANT_TARGET_DB = '';
SET MERCHANT_SCHEMA    = 'RETAIL_MERCHANT';

-- Blank means the warehouse currently in use.
SET MERCHANT_APP_WAREHOUSE = '';

-- Keep the Streamlit app warm so it opens fast for everyone.
--
-- WHAT THIS ACTUALLY DOES, because the honest answer is narrower than "keeps the
-- app running". These apps are created with ROOT_LOCATION, which means they run
-- on the WAREHOUSE runtime, and that runtime starts a SEPARATE Streamlit server
-- for every viewer -- there is no shared instance sitting there to keep warm, and
-- nothing can pre-create one.
--
-- What IS warmable is the code warehouse. Snowflake caches the Python packages
-- Streamlit needs on the warehouse, and that cache is DISCARDED when the
-- warehouse suspends -- which is the single largest part of a slow first load. So
-- TRUE creates one small warehouse that never auto-suspends, points every oneshot
-- app at it, and thereby keeps that package cache permanently hot.
--
-- ONE WAREHOUSE FOR ALL OF THEM, deliberately. Sharing is both cheaper and
-- FASTER: a warehouse already serving other apps has the cache built, so each
-- additional app benefits from the others. It is shared, so TEARDOWN does NOT
-- drop it -- one solution's teardown must not slow down every other app. Block 2
-- prints the DROP statement instead.
--
-- COST. A never-suspending XSMALL warehouse is about 24 credits/day, and it is 24
-- credits/day in total rather than per app. FALSE reverts to the warehouse you
-- are already using, with no always-on cost and slower first loads.
SET MERCHANT_KEEP_APP_WARM  = TRUE;
SET MERCHANT_WARM_WAREHOUSE = 'ONESHOT_APP_WH';

-- How long a viewer's own app session survives idling, in minutes, 5 to 240.
-- Higher means someone returning to the tab reconnects to a live session instead
-- of waiting for a new one to start.
--
-- CAVEAT WORTH KNOWING: the account-level WebSocket timeout, about 15 minutes by
-- default, can close the connection before this timer expires, and only Snowflake
-- Support can raise it. Setting 240 here is therefore an upper bound and not a
-- guarantee.
SET MERCHANT_APP_SLEEP_MINUTES = 240;

-- How far back discovery and the views look.
SET MERCHANT_WINDOW_DAYS = 14;

-- DISCOVER reads your account and reports what it found.
-- SAMPLE seeds representative data instead, and the app says so on every page.
-- Never demo SAMPLE numbers as if they were the customer's.
SET MERCHANT_MODE = 'DISCOVER';

-- Credit ceiling for steady-state cost. 0 means no ceiling. When the plan's own
-- estimate exceeds this, Block 3 refuses to plan and tells you what to turn down.
SET MERCHANT_BUDGET_CREDITS = 0;

-- ─────────────────────────────────────────────────────────────────────────────
-- MEASUREMENT
-- ─────────────────────────────────────────────────────────────────────────────

-- How much of this to stand up, and therefore how it is measured.
--
--   DISCOVER    plan only. Estimates are arithmetic; nothing is measured.
--   LIMITED     build on a warehouse this file creates, capped by a resource
--               monitor, so the credits it burns are ISOLATED and can be read
--               back from metering afterwards. This is the measurement
--               instrument: it is the only tier that produces a real number.
--   PRODUCTION  full scope, plus the operational furniture a platform team
--               expects -- monitor, budget, object tags, error notification,
--               refresh SLA, an operations view.
--
-- LIMITED exists because WAREHOUSE_METERING_HISTORY has no query-tag column. It
-- reports credits per warehouse per hour, so the ONLY way to attribute warehouse
-- credits to this run is for this run to be the only thing on that warehouse.
SET MERCHANT_DEPLOY_TIER = 'DISCOVER';

-- Names this run in QUERY_TAG so its statements can be found in history later.
-- Blank generates one. Set it yourself only if you are correlating with your own
-- observability.
SET MERCHANT_RUN_ID = '';

-- Warehouse the LIMITED and PRODUCTION tiers create for their own work. Blank
-- derives a name from the schema. It is XSMALL with a 60-second auto-suspend and
-- it is dropped by TEARDOWN.
SET MERCHANT_MEASURE_WAREHOUSE = '';

-- Credit quota for the resource monitor on that warehouse. This is a REAL
-- ceiling: the warehouse suspends when it is reached.
--
-- Read what it does NOT cover before you rely on it. A resource monitor governs
-- WAREHOUSES only. It cannot cap serverless features or AI-services tokens --
-- Snowflake's own documentation says to use a BUDGET for those. So on a solution
-- that spends most of its credits on AI, this number is not the ceiling you think
-- it is, and Block 0 prints exactly which categories it does and does not cover.
SET MERCHANT_CREDIT_CAP = 5;

-- Dollars per credit, for the readable version of every credit figure. Your rate
-- is on your contract; the default is a list-price placeholder, not your price.
SET MERCHANT_COST_PER_CREDIT = 3;

-- Ratio of output tokens to input tokens, used only to ESTIMATE AI spend before
-- it happens. AI_COUNT_TOKENS counts input tokens and cannot see output tokens,
-- so without this the estimate is systematically low. After a run the real split
-- is measured and the estimate is graded against it.
SET MERCHANT_OUTPUT_TOKEN_RATIO = 0.5;

-- ─────────────────────────────────────────────────────────────────────────────
-- PROFILE  ·  does the data support what the plan claims?
-- ─────────────────────────────────────────────────────────────────────────────

-- TRUE runs Block 2, which reads a SAMPLE of ONLY the columns the plan intends to
-- use and reports how populated they are.
--
-- This is off by default because it is the first thing in this file that reads
-- your data. Leaving it off is safe and it is also a real gap: "the column exists"
-- and "the column is usable" are different facts, and only this block can tell
-- them apart. A store-performance mart in a real account had traffic columns that
-- were present in the schema and almost entirely blank; schema-only discovery
-- builds a clean-looking dashboard on top of that and it silently lies.
--
-- Nothing example-level leaves this block. It emits null rate, distinct count, row
-- count at the intended grain, the column type, and min/max for DATE columns only.
SET MERCHANT_PROFILE = FALSE;

-- A column must be at least this percent non-null to be used. Below it, the plan
-- downgrades or refuses the thing that depended on it, and prints why.
SET MERCHANT_MIN_FILL_PCT = 60;

-- Internal. Do not edit. Block 2 publishes its statistics here in chunks.
SET MERCHANT_PROFILE_N = 0;

-- ─────────────────────────────────────────────────────────────────────────────
-- REVIEW
-- ─────────────────────────────────────────────────────────────────────────────

-- Block 3 asks the model to review the finished plan against what discovery and
-- the profile actually found, and returns PROCEED, CAVEAT or DO_NOT_PROCEED.
--
-- DO_NOT_PROCEED closes the gate even when MERCHANT_APPROVE is TRUE. Setting this to
-- TRUE overrides that. It is your call to make and the override is recorded in the
-- output, in the packet and in REVIEW_LOG, because "we were told not to and did it
-- anyway" is a thing your own audit should be able to see.
SET MERCHANT_OVERRIDE_REVIEW = FALSE;

-- ─────────────────────────────────────────────────────────────────────────────
-- OPERATIONS  ·  PRODUCTION tier only
-- ─────────────────────────────────────────────────────────────────────────────

-- An existing notification integration to send task and refresh failures to.
-- Blank skips the wiring and prints why, along with the statement your account
-- administrator would run to create one. Run SHOW NOTIFICATION INTEGRATIONS to
-- see what you already have.
--
-- Tasks accept an error integration directly. Dynamic tables do NOT -- there is no
-- equivalent clause -- so their failures are surfaced by an ALERT over refresh
-- history, which is serverless and therefore costs credits of its own. That
-- asymmetry is priced separately in the plan rather than hidden.
SET MERCHANT_NOTIFICATION_INTEGRATION = '';


-- May the dashboard CHANGE anything?
--
-- FALSE means the app is read-only: it shows you what it found and what it would
-- do, and every button in it is inert. TRUE arms the actions listed in the app's
-- promotion bar -- converting tables, applying warehouse settings, extending
-- masking -- each of which still asks for a typed confirmation and writes an
-- audit row before it runs.
--
-- This setting lives in the FILE on purpose. The whole premise of this script is
-- that a person reads the SQL and decides; moving that decision inside a web page
-- would mean a dashboard could alter production because somebody clicked. So the
-- file authorises the CLASS of change, and the app authorises the INSTANCE.
-- Nothing the app can do to YOUR data is possible unless this was TRUE when it
-- was built. It governs the LIMITED and PRODUCTION tiers -- everything that reads
-- or writes anything real. SAMPLE-tier actions are governed separately, below.
--
-- Arming it is one edit and one run: change FALSE to TRUE on the next line and
-- run this same file again. There is no command to type, no CLI to install and
-- no follow-up step -- the file IS the deployment. Said explicitly because the
-- app used to advise "re-run the script with ALLOW_ACTIONS = TRUE", which named
-- no line in any file and made a push-button deployment read like homework.
SET MERCHANT_ALLOW_ACTIONS = FALSE;

-- SAMPLE-tier actions only, and TRUE by default -- the one place this script ships
-- with a button that works out of the box.
--
-- The reasoning, because this is the only default-permit in the file and it should
-- have to justify itself. A SAMPLE action runs against seeded data this script
-- created inside its own schema. It cannot read your tables, cannot write outside
-- the schema, and TEARDOWN() removes everything it touched. So the risk it carries
-- is not the risk ALLOW_ACTIONS exists to control, and defaulting it to FALSE cost
-- something real: the app opened with every control dead, which reads as broken
-- rather than as safe, and gave a first-time reader nothing to press. The class of
-- change is genuinely different, so it gets its own switch rather than loosening
-- the one above.
--
-- Set this to FALSE if you want an inert dashboard -- a pure read-only artefact
-- with no executable surface whatsoever.
SET MERCHANT_ALLOW_SAMPLE_ACTIONS = TRUE;

-- Model used to read your discovery results and adapt the plan. Deliberately the
-- strongest available rather than the cheapest: this call decides which of your
-- objects get used and how, and a weaker model gets those judgements wrong in
-- ways that are hard to spot. It runs ONCE per plan, so the cost is negligible.
-- Verified available in this account: claude-opus-5, claude-opus-4-6,
-- openai-gpt-5.2, openai-gpt-5, claude-4-sonnet, mistral-large2.
SET MERCHANT_MODEL = 'claude-opus-5';

-- Internal. Do not edit. Block 1 publishes its findings here in chunks, because
-- one session variable caps at 16,384 bytes.
SET MERCHANT_SIGNALS_N = 0;

-- ── Source tables ────────────────────────────────────────────────────────────
-- Fully qualified names for the six retail source tables.
-- BLANK MEANS NOTHING HAPPENS. Discovery will report candidates.
SET MERCHANT_STORES_TABLE      = '';
SET MERCHANT_PRODUCTS_TABLE    = '';
SET MERCHANT_DAILY_SALES_TABLE = '';
SET MERCHANT_INVENTORY_TABLE   = '';
SET MERCHANT_TRAFFIC_TABLE     = '';
SET MERCHANT_LABOR_TABLE       = '';

-- MERCHANT_MODEL and MERCHANT_PROFILE are deliberately NOT re-declared here.
-- The shared settings block already emits SET MERCHANT_MODEL and SET MERCHANT_PROFILE,
-- and a second SET of the same name silently defeats the harness override
-- (assemble.py override_settings() patches only the FIRST SET line).


-- ─────────────────────────────────────────────────────────────────────────────
-- BLOCK 0 · PRE-FLIGHT
-- Answers only the questions that decide whether the rest can run.
-- Creates nothing. Reads no business data.
-- ─────────────────────────────────────────────────────────────────────────────
EXECUTE IMMEDIATE $$
DECLARE
  res RESULTSET;
BEGIN
  LET db   STRING := COALESCE(NULLIF($MERCHANT_TARGET_DB::VARCHAR, ''), CURRENT_DATABASE());
  LET wh   STRING := COALESCE(NULLIF($MERCHANT_APP_WAREHOUSE::VARCHAR, ''), CURRENT_WAREHOUSE());
  LET sch  STRING := $MERCHANT_SCHEMA::VARCHAR;
  LET mode STRING := UPPER(COALESCE($MERCHANT_MODE::VARCHAR, 'DISCOVER'));
  -- Solution-specific pre-flight rows. Append OBJECT_CONSTRUCT('check', ..,
  -- 'finding', .., 'fix', ..) to this and they appear in the result table.
  LET extra ARRAY := ARRAY_CONSTRUCT();

  -- 1. Can the build create its schema in that database?
  LET db_ok BOOLEAN := FALSE;
  IF (:db IS NOT NULL) THEN
    BEGIN
      EXECUTE IMMEDIATE 'SHOW GRANTS ON DATABASE "' || :db || '"';
      db_ok := (SELECT COUNT_IF("privilege" IN ('CREATE SCHEMA','OWNERSHIP')
                                AND "granted_to" = 'ROLE'
                                AND IS_ROLE_IN_SESSION("grantee_name")) > 0
                FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    EXCEPTION WHEN OTHER THEN db_ok := FALSE;
    END;
  END IF;

  -- 2. ACCOUNT_USAGE readable? Discovery leans on it heavily.
  LET au_ok BOOLEAN := FALSE;
  BEGIN
    LET probe INT := (SELECT COUNT(*) FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
                      WHERE START_TIME >= DATEADD(day, -1, CURRENT_TIMESTAMP()));
    au_ok := TRUE;
  EXCEPTION WHEN OTHER THEN au_ok := FALSE;
  END;

  -- 3. Cortex available? Decides whether the agent half of the build can run.
  LET cortex_ok BOOLEAN := FALSE;
  BEGIN
    LET probe STRING := (SELECT SNOWFLAKE.CORTEX.AI_COMPLETE(
      COALESCE(NULLIF($MERCHANT_MODEL::VARCHAR, ''), 'claude-opus-5'), 'Reply with OK.'));
    cortex_ok := TRUE;
  EXCEPTION WHEN OTHER THEN cortex_ok := FALSE;
  END;

  -- 4. Does the schema already exist? Re-running over a previous build is fine,
  --    but the operator should know before, not after.
  LET existing INT := 0;
  IF (:db_ok) THEN
    BEGIN
      -- IDENTIFIER() will not take a concatenated expression ("unexpected '||'"),
      -- so the database name is spliced into dynamic SQL and read back through
      -- RESULT_SCAN. The COUNT is aliased because RESULT_SCAN needs a name.
      EXECUTE IMMEDIATE 'SELECT COUNT(*) AS N FROM ' || :db
                     || '.INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = ''' || :sch || '''';
      existing := (SELECT N FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    EXCEPTION WHEN OTHER THEN existing := 0;
    END;
  END IF;

  -- 5. Account-level privileges the measured and hardened tiers need.
  --
  -- Read through SHOW GRANTS ON ACCOUNT rather than assumed from the role name.
  -- If the role cannot even read its own grants the handler reports NOT
  -- AUTHORIZED, which is the safe direction to be wrong in: the tier then skips
  -- the object and prints the statement an administrator would run, instead of
  -- failing mid-build on a privilege nobody checked.
  LET tier      STRING := UPPER(COALESCE(NULLIF($MERCHANT_DEPLOY_TIER::VARCHAR, ''), 'DISCOVER'));
  LET wh_ok     BOOLEAN := FALSE;
  LET rm_ok     BOOLEAN := FALSE;
  LET grants_readable BOOLEAN := FALSE;
  BEGIN
    EXECUTE IMMEDIATE 'SHOW GRANTS ON ACCOUNT';
    -- Both flags in ONE pass over the SHOW output. Reading RESULT_SCAN a second
    -- time is not safe here: LAST_QUERY_ID() has moved on by then, so the second
    -- read scans the first read and silently returns nothing.
    SELECT COUNT_IF(UPPER("privilege") = 'CREATE WAREHOUSE'
                    AND IS_ROLE_IN_SESSION("grantee_name")) > 0,
           COUNT_IF(UPPER("privilege") = 'CREATE RESOURCE MONITOR'
                    AND IS_ROLE_IN_SESSION("grantee_name")) > 0
      INTO :wh_ok, :rm_ok
      FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    grants_readable := TRUE;
  EXCEPTION WHEN OTHER THEN
    grants_readable := FALSE;
  END;
  -- ACCOUNTADMIN holds both implicitly and they do not appear as explicit grants,
  -- so a role check is the fallback rather than the primary signal.
  IF (UPPER(CURRENT_ROLE()) = 'ACCOUNTADMIN') THEN
    wh_ok := TRUE;
    rm_ok := TRUE;
  END IF;

  -- 6. Is there a notification integration to send failures to?
  LET ni       STRING := COALESCE(NULLIF($MERCHANT_NOTIFICATION_INTEGRATION::VARCHAR, ''), '');
  LET ni_found INT    := 0;
  LET ni_avail INT    := 0;
  BEGIN
    EXECUTE IMMEDIATE 'SHOW NOTIFICATION INTEGRATIONS';
    -- One pass, same reason as the grants probe above.
    SELECT COUNT(*),
           COUNT_IF(UPPER("name") = UPPER(:ni) AND "enabled" = 'true')
      INTO :ni_avail, :ni_found
      FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
  EXCEPTION WHEN OTHER THEN ni_avail := -1;
  END;

  LET profile_on BOOLEAN := FALSE;
  BEGIN
    profile_on := (SELECT TRY_CAST($MERCHANT_PROFILE::VARCHAR AS BOOLEAN));
  EXCEPTION WHEN OTHER THEN profile_on := FALSE;
  END;
  LET cap NUMBER(38,2) := COALESCE((SELECT TRY_CAST($MERCHANT_CREDIT_CAP::VARCHAR AS NUMBER)), 0);


  LET approved BOOLEAN := FALSE;
  BEGIN
    approved := (SELECT TRY_CAST($MERCHANT_APPROVE::VARCHAR AS BOOLEAN));
  EXCEPTION WHEN OTHER THEN approved := FALSE;
  END;


  res := (
    SELECT 1 AS step, 'TARGET DATABASE' AS check_name,
           COALESCE(:db, 'NONE SELECTED') AS finding,
           IFF(:db IS NULL, 'Run USE DATABASE, or set MERCHANT_TARGET_DB.',
               IFF(:db_ok, '', 'Grant CREATE SCHEMA on this database, or point at one you own.')) AS fix
    UNION ALL SELECT 2, 'CREATE SCHEMA', IFF(:db_ok, 'AUTHORIZED', 'NOT AUTHORIZED'),
           IFF(:db_ok, '', 'GRANT CREATE SCHEMA ON DATABASE ' || COALESCE(:db, '<db>') || ' TO ROLE ' || CURRENT_ROLE())
    UNION ALL SELECT 3, 'WAREHOUSE', COALESCE(:wh, 'NONE SELECTED'),
           IFF(:wh IS NULL, 'Run USE WAREHOUSE, or set MERCHANT_APP_WAREHOUSE.', '')
    UNION ALL SELECT 4, 'ACCOUNT_USAGE', IFF(:au_ok, 'READABLE', 'NOT READABLE'),
           IFF(:au_ok, '', 'GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE ' || CURRENT_ROLE())
    UNION ALL SELECT 5, 'CORTEX (' || COALESCE(NULLIF($MERCHANT_MODEL::VARCHAR, ''), 'claude-opus-5')
           || ')', IFF(:cortex_ok, 'AVAILABLE', 'NOT AVAILABLE'),
           IFF(:cortex_ok, '', 'GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE ' || CURRENT_ROLE()
               || ' — without it the agent is skipped and the dashboard still builds.')
    UNION ALL SELECT 6, 'EXISTING SCHEMA', IFF(:existing > 0, :db || '.' || :sch || ' ALREADY EXISTS', 'not present'),
           IFF(:existing > 0, 'A previous build is there. Re-running updates it in place; CALL ' || :db || '.' || :sch || '.TEARDOWN() removes it.', '')
    UNION ALL SELECT 7, 'MODE', :mode,
           IFF(:mode = 'SAMPLE', 'Seeded data. The app will label every page SAMPLE DATA. Do not present these numbers as the customer''s.', 'Reads this account.')
    UNION ALL SELECT 8, 'GATE', IFF(:approved, 'OPEN — Block 3 will build', 'CLOSED — nothing will be created'),
           IFF(:approved, 'Review the plan below before you let this run.', 'To build: set MERCHANT_APPROVE = TRUE and run the file again.')
    UNION ALL SELECT 9, 'DEPLOY TIER', :tier,
           CASE :tier
             WHEN 'DISCOVER' THEN 'Costs below are ARITHMETIC ESTIMATES. Nothing is measured at this tier. Set MERCHANT_DEPLOY_TIER = ''LIMITED'' to get a real number.'
             WHEN 'LIMITED' THEN 'Builds on its own capped warehouse so credits can be measured and attributed to this run.'
             WHEN 'PRODUCTION' THEN 'Full scope plus monitor, budget, tags, error notification and an operations view.'
             ELSE 'Unrecognised tier — treated as DISCOVER. Use DISCOVER, LIMITED or PRODUCTION.'
           END
    UNION ALL SELECT 10, 'PROFILE', IFF(:profile_on, 'ON — will sample the columns the plan uses',
                                        'OFF — column populated-ness will NOT be checked'),
           IFF(:profile_on,
               'Reads a sample of named columns only. Emits aggregates: null rate, distinct count, row count, type, and min/max for DATE columns only.',
               'This is the gap that lets a plan build on a column that exists and is empty. Set MERCHANT_PROFILE = TRUE to close it. The review will return CAVEAT rather than PROCEED while it is off.')
    -- Rows 11-14 only mean anything above DISCOVER, and saying so beats printing
    -- a NOT AUTHORIZED that does not apply to the tier the operator chose.
    UNION ALL SELECT 11, 'CREATE WAREHOUSE',
           IFF(:tier = 'DISCOVER', 'not needed at DISCOVER',
               IFF(:wh_ok, 'AUTHORIZED', 'NOT AUTHORIZED')),
           IFF(:tier = 'DISCOVER' OR :wh_ok, '',
               'GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE ' || CURRENT_ROLE()
            || ' — without it the build runs on your current warehouse and warehouse credits CANNOT be attributed to this run.')
    UNION ALL SELECT 12, 'CREATE RESOURCE MONITOR',
           IFF(:tier = 'DISCOVER', 'not needed at DISCOVER',
               IFF(:rm_ok, 'AUTHORIZED', 'NOT AUTHORIZED — only ACCOUNTADMIN can create one')),
           IFF(:tier = 'DISCOVER' OR :rm_ok, '',
               'The build continues WITHOUT a credit cap and prints the exact statement for your administrator. Nothing silently proceeds as though a cap existed.')
    UNION ALL SELECT 13, 'CAP · WHAT ' || :cap || ' CREDITS COVERS',
           IFF(:tier = 'DISCOVER', 'no cap at DISCOVER (nothing is built)',
               IFF(:rm_ok, 'warehouse compute + cloud services', 'NOTHING — no monitor could be created')),
           'A resource monitor governs warehouses only.'
    UNION ALL SELECT 14, 'CAP · WHAT IT DOES NOT COVER',
           'AI tokens, serverless tasks, Cortex Search, data-quality monitoring',
           'These are not capped by ANY resource monitor — Snowflake requires a BUDGET for them, which also needs ACCOUNTADMIN. If most of this solution''s cost is AI, the number above is not the ceiling it looks like.'
    UNION ALL SELECT 15, 'NOTIFICATION INTEGRATION',
           CASE
             WHEN :ni = '' AND :ni_avail > 0 THEN 'none selected — ' || :ni_avail || ' available in this account'
             WHEN :ni = '' THEN 'none selected'
             WHEN :ni_found > 0 THEN :ni || ' — found and enabled'
             ELSE :ni || ' — NOT FOUND or disabled'
           END,
           CASE
             WHEN :ni <> '' AND :ni_found > 0 THEN 'Task failures will be sent here. Dynamic table failures need an alert instead; the plan prices it separately.'
             WHEN :ni <> '' THEN 'Run SHOW NOTIFICATION INTEGRATIONS and use a name from that list, or leave blank to skip.'
             WHEN :ni_avail > 0 THEN 'Run SHOW NOTIFICATION INTEGRATIONS to pick one, or leave blank — failure notification is then SKIPPED and the plan says so.'
             WHEN :ni_avail = 0 THEN 'This account has none. Failure notification is skipped and the plan prints the CREATE NOTIFICATION INTEGRATION statement for your administrator.'
             ELSE 'Could not read integrations with this role. Failure notification will be skipped.'
           END
    UNION ALL
    SELECT 20 + v.index, v.value:check::STRING, v.value:finding::STRING,
           COALESCE(v.value:fix::STRING, '')
    FROM TABLE(FLATTEN(input => :extra)) v
    ORDER BY step
  );
  RETURN TABLE(res);
END;
$$;
-- ─────────────────────────────────────────────────────────────────────────────
-- BLOCK 1 · DISCOVERY  (creates nothing; reads metadata, not table contents)
--
-- Every probe runs in its own exception block, so one missing privilege costs
-- one panel rather than the whole run. Three outcomes per signal:
--
--   AVAILABLE   readable and populated in the window  → becomes a panel
--   EMPTY       readable but nothing in the window    → skipped, and said so
--   NO ACCESS   the role cannot read it               → skipped, and said so
--
-- Absence of data is never reported as health. That distinction is the whole
-- reason this block exists separately from the plan.
-- ─────────────────────────────────────────────────────────────────────────────
EXECUTE IMMEDIATE $$
DECLARE
  res RESULTSET;
BEGIN
  LET w    INT    := COALESCE((SELECT TRY_CAST($MERCHANT_WINDOW_DAYS::VARCHAR AS INT)), 14);
  LET db   STRING := COALESCE(NULLIF($MERCHANT_TARGET_DB::VARCHAR, ''), CURRENT_DATABASE());
  LET mode STRING := UPPER(COALESCE($MERCHANT_MODE::VARCHAR, 'DISCOVER'));
  LET sig  OBJECT := OBJECT_CONSTRUCT();
  LET cnt  OBJECT := OBJECT_CONSTRUCT();

  -- ── Probes ────────────────────────────────────────────────────────────────
  -- One BEGIN/EXCEPTION per signal. Copy the shape; do not merge them, because
  -- a merged probe turns one unreadable view into a dead run.
  --
  -- ── Probe: candidate store/location tables ──────────────────────────────────
  -- Standard retail + SAP HANA naming (WERKS=plant/store).
  LET own_schema STRING := UPPER($MERCHANT_SCHEMA::VARCHAR);
  LET stores_cands ARRAY := ARRAY_CONSTRUCT();
  BEGIN
    EXECUTE IMMEDIATE
      'SELECT c.TABLE_SCHEMA || ''.'' || c.TABLE_NAME AS FQN, '
   || 'COUNT(*) AS HITS, COALESCE(MAX(t.ROW_COUNT), 0) AS N_ROWS FROM '
   || :db || '.INFORMATION_SCHEMA.COLUMNS c '
   || 'JOIN ' || :db || '.INFORMATION_SCHEMA.TABLES t '
   || 'ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME '
   || 'WHERE c.TABLE_SCHEMA <> ''INFORMATION_SCHEMA'' '
   || 'AND c.TABLE_SCHEMA <> ''' || :own_schema || ''' '
   || 'AND t.TABLE_TYPE = ''BASE TABLE'' '
   || 'AND UPPER(c.COLUMN_NAME) RLIKE ''.*(STORE_ID|WERKS|STORE_NAME|STORE_SQ_FT|STATE_CODE|METRO|REGION).*'' '
   || 'GROUP BY 1 HAVING COUNT(*) >= 3 '
   || 'ORDER BY IFF(COALESCE(MAX(t.ROW_COUNT),0) > 0, 0, 1), 2 DESC, 3 DESC, 1 LIMIT 5';
    stores_cands := (SELECT COALESCE(ARRAY_AGG(OBJECT_CONSTRUCT('fqn', FQN,
                                       'hits', HITS, 'rows', N_ROWS)),
                                    ARRAY_CONSTRUCT())
                    FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    sig := OBJECT_INSERT(:sig, 'stores_candidates',
             IFF(ARRAY_SIZE(:stores_cands) > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'stores_candidates', ARRAY_SIZE(:stores_cands), TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'stores_candidates', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'stores_candidates', 0, TRUE);
  END;

  -- ── Probe: candidate product/material tables ──────────────────────────────
  -- Standard + SAP (MATNR=material/SKU, MATKL=material group/category).
  LET products_cands ARRAY := ARRAY_CONSTRUCT();
  BEGIN
    EXECUTE IMMEDIATE
      'SELECT c.TABLE_SCHEMA || ''.'' || c.TABLE_NAME AS FQN, '
   || 'COUNT(*) AS HITS, COALESCE(MAX(t.ROW_COUNT), 0) AS N_ROWS FROM '
   || :db || '.INFORMATION_SCHEMA.COLUMNS c '
   || 'JOIN ' || :db || '.INFORMATION_SCHEMA.TABLES t '
   || 'ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME '
   || 'WHERE c.TABLE_SCHEMA <> ''INFORMATION_SCHEMA'' '
   || 'AND c.TABLE_SCHEMA <> ''' || :own_schema || ''' '
   || 'AND t.TABLE_TYPE = ''BASE TABLE'' '
   || 'AND UPPER(c.COLUMN_NAME) RLIKE ''.*(SKU_ID|MATNR|PRODUCT_NAME|MATKL|CATEGORY|UNIT_COST|UNIT_RETAIL).*'' '
   || 'GROUP BY 1 HAVING COUNT(*) >= 3 '
   || 'ORDER BY IFF(COALESCE(MAX(t.ROW_COUNT),0) > 0, 0, 1), 2 DESC, 3 DESC, 1 LIMIT 5';
    products_cands := (SELECT COALESCE(ARRAY_AGG(OBJECT_CONSTRUCT('fqn', FQN,
                                       'hits', HITS, 'rows', N_ROWS)),
                                    ARRAY_CONSTRUCT())
                      FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    sig := OBJECT_INSERT(:sig, 'products_candidates',
             IFF(ARRAY_SIZE(:products_cands) > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'products_candidates', ARRAY_SIZE(:products_cands), TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'products_candidates', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'products_candidates', 0, TRUE);
  END;

  -- ── Probe: candidate sales/billing tables ─────────────────────────────────
  -- Standard + SAP (FKDAT=billing date, MENGE=quantity, NETWR=net value).
  LET sales_cands ARRAY := ARRAY_CONSTRUCT();
  BEGIN
    EXECUTE IMMEDIATE
      'SELECT c.TABLE_SCHEMA || ''.'' || c.TABLE_NAME AS FQN, '
   || 'COUNT(*) AS HITS, COALESCE(MAX(t.ROW_COUNT), 0) AS N_ROWS FROM '
   || :db || '.INFORMATION_SCHEMA.COLUMNS c '
   || 'JOIN ' || :db || '.INFORMATION_SCHEMA.TABLES t '
   || 'ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME '
   || 'WHERE c.TABLE_SCHEMA <> ''INFORMATION_SCHEMA'' '
   || 'AND c.TABLE_SCHEMA <> ''' || :own_schema || ''' '
   || 'AND t.TABLE_TYPE = ''BASE TABLE'' '
   || 'AND UPPER(c.COLUMN_NAME) RLIKE ''.*(SALE_DATE|FKDAT|UNITS_SOLD|MENGE|NET_SALES|NETWR|TRANSACTION_COUNT|DISCOUNT).*'' '
   || 'GROUP BY 1 HAVING COUNT(*) >= 3 '
   || 'ORDER BY IFF(COALESCE(MAX(t.ROW_COUNT),0) > 0, 0, 1), 2 DESC, 3 DESC, 1 LIMIT 5';
    sales_cands := (SELECT COALESCE(ARRAY_AGG(OBJECT_CONSTRUCT('fqn', FQN,
                                       'hits', HITS, 'rows', N_ROWS)),
                                    ARRAY_CONSTRUCT())
                   FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    sig := OBJECT_INSERT(:sig, 'sales_candidates',
             IFF(ARRAY_SIZE(:sales_cands) > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'sales_candidates', ARRAY_SIZE(:sales_cands), TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'sales_candidates', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'sales_candidates', 0, TRUE);
  END;

  -- ── Probe: candidate inventory/stock tables ───────────────────────────────
  -- Standard + SAP (LABST=unrestricted stock/on-hand, BUDAT=posting date).
  LET inventory_cands ARRAY := ARRAY_CONSTRUCT();
  BEGIN
    EXECUTE IMMEDIATE
      'SELECT c.TABLE_SCHEMA || ''.'' || c.TABLE_NAME AS FQN, '
   || 'COUNT(*) AS HITS, COALESCE(MAX(t.ROW_COUNT), 0) AS N_ROWS FROM '
   || :db || '.INFORMATION_SCHEMA.COLUMNS c '
   || 'JOIN ' || :db || '.INFORMATION_SCHEMA.TABLES t '
   || 'ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME '
   || 'WHERE c.TABLE_SCHEMA <> ''INFORMATION_SCHEMA'' '
   || 'AND c.TABLE_SCHEMA <> ''' || :own_schema || ''' '
   || 'AND t.TABLE_TYPE = ''BASE TABLE'' '
   || 'AND UPPER(c.COLUMN_NAME) RLIKE ''.*(UNITS_ON_HAND|LABST|SNAPSHOT_DATE|BUDAT|FIRST_RECEIVED|RECEIPT_DATE).*'' '
   || 'GROUP BY 1 HAVING COUNT(*) >= 2 '
   || 'ORDER BY IFF(COALESCE(MAX(t.ROW_COUNT),0) > 0, 0, 1), 2 DESC, 3 DESC, 1 LIMIT 5';
    inventory_cands := (SELECT COALESCE(ARRAY_AGG(OBJECT_CONSTRUCT('fqn', FQN,
                                       'hits', HITS, 'rows', N_ROWS)),
                                    ARRAY_CONSTRUCT())
                       FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    sig := OBJECT_INSERT(:sig, 'inventory_candidates',
             IFF(ARRAY_SIZE(:inventory_cands) > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'inventory_candidates', ARRAY_SIZE(:inventory_cands), TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'inventory_candidates', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'inventory_candidates', 0, TRUE);
  END;

  -- ── Probe: candidate traffic/footfall tables ──────────────────────────────
  LET traffic_cands ARRAY := ARRAY_CONSTRUCT();
  BEGIN
    EXECUTE IMMEDIATE
      'SELECT c.TABLE_SCHEMA || ''.'' || c.TABLE_NAME AS FQN, '
   || 'COUNT(*) AS HITS, COALESCE(MAX(t.ROW_COUNT), 0) AS N_ROWS FROM '
   || :db || '.INFORMATION_SCHEMA.COLUMNS c '
   || 'JOIN ' || :db || '.INFORMATION_SCHEMA.TABLES t '
   || 'ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME '
   || 'WHERE c.TABLE_SCHEMA <> ''INFORMATION_SCHEMA'' '
   || 'AND c.TABLE_SCHEMA <> ''' || :own_schema || ''' '
   || 'AND t.TABLE_TYPE = ''BASE TABLE'' '
   || 'AND UPPER(c.COLUMN_NAME) RLIKE ''.*(TRAFFIC|EXIT_COUNT|FOOTFALL|TRAFFIC_HOUR|TRAFFIC_DATE).*'' '
   || 'GROUP BY 1 HAVING COUNT(*) >= 2 '
   || 'ORDER BY IFF(COALESCE(MAX(t.ROW_COUNT),0) > 0, 0, 1), 2 DESC, 3 DESC, 1 LIMIT 5';
    traffic_cands := (SELECT COALESCE(ARRAY_AGG(OBJECT_CONSTRUCT('fqn', FQN,
                                       'hits', HITS, 'rows', N_ROWS)),
                                    ARRAY_CONSTRUCT())
                     FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    sig := OBJECT_INSERT(:sig, 'traffic_candidates',
             IFF(ARRAY_SIZE(:traffic_cands) > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'traffic_candidates', ARRAY_SIZE(:traffic_cands), TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'traffic_candidates', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'traffic_candidates', 0, TRUE);
  END;

  -- ── Probe: candidate labor/workforce tables ───────────────────────────────
  LET labor_cands ARRAY := ARRAY_CONSTRUCT();
  BEGIN
    EXECUTE IMMEDIATE
      'SELECT c.TABLE_SCHEMA || ''.'' || c.TABLE_NAME AS FQN, '
   || 'COUNT(*) AS HITS, COALESCE(MAX(t.ROW_COUNT), 0) AS N_ROWS FROM '
   || :db || '.INFORMATION_SCHEMA.COLUMNS c '
   || 'JOIN ' || :db || '.INFORMATION_SCHEMA.TABLES t '
   || 'ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME '
   || 'WHERE c.TABLE_SCHEMA <> ''INFORMATION_SCHEMA'' '
   || 'AND c.TABLE_SCHEMA <> ''' || :own_schema || ''' '
   || 'AND t.TABLE_TYPE = ''BASE TABLE'' '
   || 'AND UPPER(c.COLUMN_NAME) RLIKE ''.*(HOURS_WORKED|ASSOCIATE|LABOR|WORK_HOUR|WORK_DATE|SCHEDULE).*'' '
   || 'GROUP BY 1 HAVING COUNT(*) >= 2 '
   || 'ORDER BY IFF(COALESCE(MAX(t.ROW_COUNT),0) > 0, 0, 1), 2 DESC, 3 DESC, 1 LIMIT 5';
    labor_cands := (SELECT COALESCE(ARRAY_AGG(OBJECT_CONSTRUCT('fqn', FQN,
                                       'hits', HITS, 'rows', N_ROWS)),
                                    ARRAY_CONSTRUCT())
                   FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    sig := OBJECT_INSERT(:sig, 'labor_candidates',
             IFF(ARRAY_SIZE(:labor_cands) > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'labor_candidates', ARRAY_SIZE(:labor_cands), TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'labor_candidates', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'labor_candidates', 0, TRUE);
  END;

  -- ── Probe: Cortex AI availability ──────────────────────────────────────────
  BEGIN
    LET probe_model STRING := COALESCE(NULLIF($MERCHANT_MODEL::VARCHAR, ''), 'claude-opus-5');
    LET p STRING := (SELECT SNOWFLAKE.CORTEX.AI_COMPLETE(:probe_model, 'Reply OK.'));
    sig := OBJECT_INSERT(:sig, 'cortex', 'AVAILABLE', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'cortex', 1, TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'cortex', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'cortex', 0, TRUE);
  END;

  -- ── Probe: query history for cost measurement ──────────────────────────────
  BEGIN
    LET qh_cnt INT := (SELECT COUNT(*) FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
                        WHERE START_TIME >= DATEADD(day, -:w, CURRENT_TIMESTAMP()));
    sig := OBJECT_INSERT(:sig, 'query_history', IFF(:qh_cnt > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'query_history', :qh_cnt, TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'query_history', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'query_history', 0, TRUE);
  END;
  --
  -- Each probe should end with:
  --   sig := OBJECT_INSERT(:sig, '<name>', <'AVAILABLE'|'EMPTY'|'NO ACCESS'>, TRUE);
  --   cnt := OBJECT_INSERT(:cnt, '<name>', <row count>, TRUE);

  -- ── Publish the handoff ───────────────────────────────────────────────────
  -- Chunked, because a single session variable caps at 16,384 bytes and real
  -- discovery payloads pass that. 8 chunks of 12,000 gives 96KB of headroom.
  LET payload STRING := TO_JSON(OBJECT_CONSTRUCT(
      'sig', :sig,
      'cnt', :cnt,
      'window_days', :w,
      'mode', :mode,
      'target_db', :db,
      'discovered_at', CURRENT_TIMESTAMP()::STRING
      , 'stores_candidates', :stores_cands
      , 'products_candidates', :products_cands
      , 'sales_candidates', :sales_cands
      , 'inventory_candidates', :inventory_cands
      , 'traffic_candidates', :traffic_cands
      , 'labor_candidates', :labor_cands
  ));

  -- BASE64 before chunking. The payload is written into a session variable via
  -- a single-quoted SET literal, and Snowflake string literals process backslash
  -- escapes -- so any backslash in the payload (regex fragments captured from
  -- query text, Windows paths, escaped JSON) silently corrupts it and Block 2
  -- reports "handoff did not parse". Doubling quotes is not enough. Base64 is in
  -- the safe alphabet by construction, so nothing in the data can break the
  -- transport carrying it. Costs ~33% size against a 96KB budget.
  LET encoded STRING := BASE64_ENCODE(:payload);
  LET nchunks INT := GREATEST(1, CEIL(LENGTH(:encoded) / 12000.0));
  IF (:nchunks > 8) THEN
    res := (SELECT 'BLOCKED' AS signal, 'discovery payload is ' || LENGTH(:payload)
                   || ' bytes (' || LENGTH(:encoded) || ' encoded), over the 96KB handoff limit'
                   AS status, 0 AS rows_found,
                   'Aggregate the discovery instead of enumerating it.' AS note);
    RETURN TABLE(res);
  END IF;

  LET ci INT := 0;
  WHILE (:ci < :nchunks) DO
    LET piece STRING := SUBSTR(:encoded, :ci * 12000 + 1, 12000);
    -- Base64 contains no quotes and no backslashes, so this literal is safe.
    EXECUTE IMMEDIATE 'SET MERCHANT_SIGNALS_' || (:ci + 1)
                   || ' = ''' || :piece || '''';
    ci := :ci + 1;
  END WHILE;
  EXECUTE IMMEDIATE 'SET MERCHANT_SIGNALS_N = ' || :nchunks;

  -- Prove the handoff survived rather than assuming it did.
  IF ((SELECT COALESCE(TRY_CAST(GETVARIABLE('MERCHANT_SIGNALS_N') AS INT), 0)) <> :nchunks) THEN
    res := (SELECT 'BLOCKED' AS signal, 'handoff failed to publish' AS status,
                   0 AS rows_found, 'Re-run the file from the top.' AS note);
    RETURN TABLE(res);
  END IF;

  res := (
    SELECT f.key::STRING AS signal,
           f.value::STRING AS status,
           COALESCE(GET(:cnt, f.key)::NUMBER, 0) AS rows_found,
           CASE f.value::STRING
             WHEN 'AVAILABLE' THEN 'becomes a panel in the app'
             WHEN 'EMPTY'     THEN 'readable, but nothing in the last ' || :w || ' days — no panel'
             ELSE                  'this role cannot read the source — no panel'
           END AS note
    FROM TABLE(FLATTEN(input => :sig)) f
    ORDER BY status, signal
  );
  RETURN TABLE(res);
END;
$$;
-- ─────────────────────────────────────────────────────────────────────────────
-- BLOCK 2 · PROFILE  (creates nothing; reads a SAMPLE of named columns only)
--
-- The first block in this file that touches your data, which is why it has its
-- own gate and why that gate ships closed.
--
-- It exists because "the column exists" and "the column is usable" are different
-- facts and schema-only discovery cannot tell them apart. A store-performance mart
-- in a real account had traffic columns that were present in every catalog view
-- and almost entirely blank. Everything downstream built cleanly on top of them
-- and reported confident numbers about nothing.
--
-- WHAT LEAVES THIS BLOCK IS AGGREGATE, BY CONSTRUCTION AND NOT BY CARE.
-- The emitted shape is fixed: row count, sampled rows, null percentage, a distinct
-- count within the sample, the declared type, and MIN/MAX for date-typed columns
-- ONLY. There is no code path here that can place a value from one of your rows
-- into the output, because the only expressions ever applied to a non-date column
-- are COUNT and COUNT(DISTINCT). A MIN or MAX on a text column would return a name
-- or an identifier, so the type restriction lives in the shape rather than in a
-- warning.
--
-- The distinct count is EXACT WITHIN THE SAMPLE rather than approximate.
-- APPROX_COUNT_DISTINCT was tried first and reported 10,088 distinct values in a
-- 10,000-row sample -- correct behaviour for a sketch, and arithmetically
-- impossible to a reader, who then distrusts every other number on the page. The
-- sample is capped, so an exact count is cheap.
--
-- Every column name is checked against INFORMATION_SCHEMA before it is used in a
-- statement. Column names arrive from the settings block, which is client-edited
-- text, and interpolating unvalidated text into SQL is how a settings typo becomes
-- an injection. A name that does not match exactly is reported MISSING and never
-- reaches a query.
-- ─────────────────────────────────────────────────────────────────────────────
EXECUTE IMMEDIATE $$
DECLARE
  res RESULTSET;
BEGIN
  LET db      STRING := COALESCE(NULLIF($MERCHANT_TARGET_DB::VARCHAR, ''), CURRENT_DATABASE());
  LET min_fill NUMBER(38,2) := COALESCE((SELECT TRY_CAST($MERCHANT_MIN_FILL_PCT::VARCHAR AS NUMBER)), 60);
  LET sample_rows INT := 10000;
  LET prof_on BOOLEAN := FALSE;
  BEGIN
    prof_on := (SELECT TRY_CAST($MERCHANT_PROFILE::VARCHAR AS BOOLEAN));
  EXCEPTION WHEN OTHER THEN prof_on := FALSE;
  END;

  -- Targets the plan intends to read. One entry per table:
  --   OBJECT_CONSTRUCT('table', '<db.schema.table>',
  --                    'columns', ARRAY_CONSTRUCT('COL_A', 'COL_B'),
  --                    'grain',   'COL_A')          -- optional, single column
  -- The solution fills this in; blank means there is nothing to profile, which is
  -- a legitimate answer for a metadata-only solution.
  LET targets ARRAY := ARRAY_CONSTRUCT();
LET p_stores STRING := COALESCE(NULLIF($MERCHANT_STORES_TABLE::VARCHAR, ''), '');
LET p_products STRING := COALESCE(NULLIF($MERCHANT_PRODUCTS_TABLE::VARCHAR, ''), '');
LET p_sales STRING := COALESCE(NULLIF($MERCHANT_DAILY_SALES_TABLE::VARCHAR, ''), '');
LET p_inventory STRING := COALESCE(NULLIF($MERCHANT_INVENTORY_TABLE::VARCHAR, ''), '');
LET p_traffic STRING := COALESCE(NULLIF($MERCHANT_TRAFFIC_TABLE::VARCHAR, ''), '');
LET p_labor STRING := COALESCE(NULLIF($MERCHANT_LABOR_TABLE::VARCHAR, ''), '');

IF (:p_stores <> '') THEN
  targets := ARRAY_APPEND(:targets, OBJECT_CONSTRUCT(
    'table', :p_stores,
    'columns', ARRAY_CONSTRUCT(
        'STORE_ID', 'STORE_NAME', 'STORE_SQ_FT', 'STATE_CODE', 'METRO', 'REGION'),
    'grain', 'STORE_ID'));
END IF;

IF (:p_products <> '') THEN
  targets := ARRAY_APPEND(:targets, OBJECT_CONSTRUCT(
    'table', :p_products,
    'columns', ARRAY_CONSTRUCT(
        'SKU_ID', 'PRODUCT_NAME', 'CATEGORY', 'UNIT_COST', 'UNIT_RETAIL_PRICE'),
    'grain', 'SKU_ID'));
END IF;

IF (:p_sales <> '') THEN
  targets := ARRAY_APPEND(:targets, OBJECT_CONSTRUCT(
    'table', :p_sales,
    'columns', ARRAY_CONSTRUCT(
        'STORE_ID', 'SKU_ID', 'SALE_DATE', 'UNITS_SOLD',
        'NET_SALES_AMT', 'TRANSACTION_COUNT'),
    'grain', 'STORE_ID, SKU_ID, SALE_DATE'));
END IF;

IF (:p_inventory <> '') THEN
  targets := ARRAY_APPEND(:targets, OBJECT_CONSTRUCT(
    'table', :p_inventory,
    'columns', ARRAY_CONSTRUCT(
        'STORE_ID', 'SKU_ID', 'SNAPSHOT_DATE',
        'UNITS_ON_HAND', 'FIRST_RECEIVED_DATE'),
    'grain', 'STORE_ID, SKU_ID, SNAPSHOT_DATE'));
END IF;

IF (:p_traffic <> '') THEN
  targets := ARRAY_APPEND(:targets, OBJECT_CONSTRUCT(
    'table', :p_traffic,
    'columns', ARRAY_CONSTRUCT(
        'STORE_ID', 'TRAFFIC_DATE', 'TRAFFIC_HOUR', 'EXIT_COUNT'),
    'grain', 'STORE_ID, TRAFFIC_DATE, TRAFFIC_HOUR'));
END IF;

IF (:p_labor <> '') THEN
  targets := ARRAY_APPEND(:targets, OBJECT_CONSTRUCT(
    'table', :p_labor,
    'columns', ARRAY_CONSTRUCT(
        'STORE_ID', 'WORK_DATE', 'WORK_HOUR',
        'ASSOCIATE_ID', 'HOURS_WORKED'),
    'grain', 'STORE_ID, WORK_DATE, WORK_HOUR, ASSOCIATE_ID'));
END IF;

  IF (NOT :prof_on) THEN
    res := (SELECT 'PROFILE NOT RUN' AS target_table, '' AS column_name, '' AS data_type,
                   'SKIPPED' AS status, NULL::NUMBER AS table_rows, NULL::NUMBER AS sampled_rows,
                   NULL::NUMBER AS null_pct, NULL::NUMBER AS distinct_in_sample,
                   NULL::STRING AS min_date, NULL::STRING AS max_date,
                   'NOT_CHECKED' AS verdict,
                   'Set MERCHANT_PROFILE = TRUE to check whether the columns this plan '
                || 'uses are actually populated. Until then the plan proceeds on the '
                || 'schema alone, and the review will return CAVEAT rather than PROCEED '
                || 'for anything that depends on column content.' AS note);
    RETURN TABLE(res);
  END IF;

  IF (ARRAY_SIZE(:targets) = 0) THEN
    res := (SELECT 'NOTHING TO PROFILE' AS target_table, '' AS column_name, '' AS data_type,
                   'SKIPPED' AS status, NULL::NUMBER AS table_rows, NULL::NUMBER AS sampled_rows,
                   NULL::NUMBER AS null_pct, NULL::NUMBER AS distinct_in_sample,
                   NULL::STRING AS min_date, NULL::STRING AS max_date,
                   'NOT_APPLICABLE' AS verdict,
                   'This solution named no source columns, either because it is '
                || 'metadata-only or because its source settings are still blank.' AS note);
    RETURN TABLE(res);
  END IF;

  LET out ARRAY := ARRAY_CONSTRUCT();
  LET ti  INT   := 0;

  WHILE (:ti < ARRAY_SIZE(:targets)) DO
    LET tgt_obj VARIANT := GET(:targets, :ti);
    LET fqn     STRING  := UPPER(TRIM(COALESCE(:tgt_obj:table::STRING, '')));
    LET cols    ARRAY   := COALESCE(:tgt_obj:columns::ARRAY, ARRAY_CONSTRUCT());
    LET grain   STRING  := UPPER(TRIM(COALESCE(:tgt_obj:grain::STRING, '')));

    -- Resolve the name. Two parts get the target database prefixed; one part is
    -- ambiguous and is refused rather than guessed, because guessing which schema
    -- holds a table is how a profile ends up describing the wrong data.
    LET nparts INT := ARRAY_SIZE(SPLIT(:fqn, '.'));
    IF (:nparts = 2) THEN
      fqn := :db || '.' || :fqn;
      nparts := 3;
    END IF;

    IF (:nparts <> 3) THEN
      out := ARRAY_APPEND(:out, OBJECT_CONSTRUCT(
        'target_table', :fqn, 'column_name', '', 'data_type', '', 'status', 'UNRESOLVED',
        'verdict', 'MISSING',
        'note', 'Name it as DATABASE.SCHEMA.TABLE. A single-part name is ambiguous '
             || 'and this block will not guess which schema you meant.'));
      ti := :ti + 1;
      CONTINUE;
    END IF;

    LET p_db  STRING := SPLIT_PART(:fqn, '.', 1);
    LET p_sch STRING := SPLIT_PART(:fqn, '.', 2);
    LET p_tab STRING := SPLIT_PART(:fqn, '.', 3);

    -- The real column inventory, and the exact row count. ROW_COUNT here is
    -- metadata and therefore free and EXACT, which matters: the fill rate below is
    -- sampled and approximate, and mixing an approximate row count into it would
    -- make both numbers soft for no reason.
    LET real_cols VARIANT := NULL;
    LET tbl_rows  NUMBER  := NULL;
    LET tbl_kind  STRING  := '';
    BEGIN
      EXECUTE IMMEDIATE
        'SELECT OBJECT_AGG(COLUMN_NAME, DATA_TYPE::VARIANT) AS COLS FROM "' || :p_db
     || '".INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = ''' || :p_sch
     || ''' AND TABLE_NAME = ''' || :p_tab || '''';
      real_cols := (SELECT COLS FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
      EXECUTE IMMEDIATE
        'SELECT ROW_COUNT, TABLE_TYPE FROM "' || :p_db
     || '".INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = ''' || :p_sch
     || ''' AND TABLE_NAME = ''' || :p_tab || '''';
      SELECT ROW_COUNT, TABLE_TYPE INTO :tbl_rows, :tbl_kind
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    EXCEPTION WHEN OTHER THEN
      out := ARRAY_APPEND(:out, OBJECT_CONSTRUCT(
        'target_table', :fqn, 'column_name', '', 'data_type', '', 'status', 'NO ACCESS',
        'verdict', 'NO_ACCESS',
        'note', 'This role cannot read the catalog for that table, so nothing '
             || 'downstream of it can be checked. Nothing was created. ' || SQLERRM));
      ti := :ti + 1;
      CONTINUE;
    END;

    -- OBJECT_AGG over zero rows returns an EMPTY OBJECT, not NULL, so a
    -- non-existent table used to fall through to the per-column loop and report
    -- "the table does not have it" -- which tells the operator the table exists.
    -- A table with zero columns is impossible, so an empty inventory means the
    -- table is not there.
    IF (:real_cols IS NULL OR ARRAY_SIZE(OBJECT_KEYS(:real_cols)) = 0) THEN
      out := ARRAY_APPEND(:out, OBJECT_CONSTRUCT(
        'target_table', :fqn, 'column_name', '', 'data_type', '', 'status', 'TABLE NOT FOUND',
        'verdict', 'MISSING',
        'note', 'No such table in this account, or not visible to ' || CURRENT_ROLE()
             || '. Every column named against it is unusable for that reason, not '
             || 'because the columns are missing. Nothing was created.'));
      ti := :ti + 1;
      CONTINUE;
    END IF;

    -- Split requested columns into ones that really exist and ones that do not.
    -- Only the validated names are ever interpolated into a statement.
    LET good ARRAY := ARRAY_CONSTRUCT();
    LET ci INT := 0;
    WHILE (:ci < ARRAY_SIZE(:cols)) DO
      LET cname STRING := UPPER(TRIM(GET(:cols, :ci)::STRING));
      IF (:cname = '' OR GET(:real_cols, :cname) IS NULL) THEN
        out := ARRAY_APPEND(:out, OBJECT_CONSTRUCT(
          'target_table', :fqn, 'column_name', :cname, 'data_type', '',
          'status', 'NOT FOUND', 'table_rows', :tbl_rows, 'verdict', 'MISSING',
          'note', 'The settings name this column but the table does not have it. '
               || 'Whatever depends on it will be refused or downgraded, and the '
               || 'plan says which.'));
      ELSE
        good := ARRAY_APPEND(:good, OBJECT_CONSTRUCT(
          'name', :cname, 'type', GET(:real_cols, :cname)::STRING));
      END IF;
      ci := :ci + 1;
    END WHILE;

    IF (ARRAY_SIZE(:good) = 0) THEN
      ti := :ti + 1;
      CONTINUE;
    END IF;

    -- One statement per TABLE rather than per column: a per-column query would
    -- re-scan the sample once for every column named, which on a wide mapping is
    -- the difference between one scan and a dozen.
    --
    -- Fixed-size row sampling, so the cost does not scale with the table.
    LET sel STRING := '';
    LET gi  INT := 0;
    WHILE (:gi < ARRAY_SIZE(:good)) DO
      LET g_name STRING := GET(:good, :gi):name::STRING;
      LET g_type STRING := UPPER(GET(:good, :gi):type::STRING);
      sel := :sel || ', COUNT("' || :g_name || '") AS "NN_' || :g_name || '"'
                  || ', COUNT(DISTINCT "' || :g_name || '") AS "DC_' || :g_name || '"';
      -- MIN/MAX ONLY here, inside the date branch. This is the construction that
      -- makes a value leak impossible rather than merely discouraged.
      IF (:g_type IN ('DATE', 'TIMESTAMP_NTZ', 'TIMESTAMP_LTZ', 'TIMESTAMP_TZ', 'DATETIME')) THEN
        sel := :sel || ', MIN("' || :g_name || '")::STRING AS "MN_' || :g_name || '"'
                    || ', MAX("' || :g_name || '")::STRING AS "MX_' || :g_name || '"';
      END IF;
      gi := :gi + 1;
    END WHILE;
    IF (:grain <> '' AND GET(:real_cols, :grain) IS NOT NULL) THEN
      sel := :sel || ', COUNT(DISTINCT "' || :grain || '") AS "GRAIN_KEYS"';
    END IF;

    LET stats VARIANT := NULL;
    BEGIN
      EXECUTE IMMEDIATE 'SELECT OBJECT_CONSTRUCT(*) AS J FROM (SELECT COUNT(*) AS "SAMPLED"'
                     || :sel || ' FROM ' || :fqn || ' SAMPLE (' || :sample_rows || ' ROWS))';
      stats := (SELECT J FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    EXCEPTION WHEN OTHER THEN
      out := ARRAY_APPEND(:out, OBJECT_CONSTRUCT(
        'target_table', :fqn, 'column_name', '', 'data_type', '', 'status', 'UNREADABLE',
        'table_rows', :tbl_rows, 'verdict', 'NO_ACCESS',
        'note', 'The catalog is readable but the rows are not, so populated-ness '
             || 'is unknown. Nothing was created. ' || SQLERRM));
      ti := :ti + 1;
      CONTINUE;
    END;

    LET sampled NUMBER := COALESCE(GET(:stats, 'SAMPLED')::NUMBER, 0);
    gi := 0;
    WHILE (:gi < ARRAY_SIZE(:good)) DO
      LET g2_name STRING := GET(:good, :gi):name::STRING;
      LET g2_type STRING := UPPER(GET(:good, :gi):type::STRING);
      LET nn NUMBER := COALESCE(GET(:stats, 'NN_' || :g2_name)::NUMBER, 0);
      LET fill NUMBER(38,2) := IFF(:sampled = 0, 0, ROUND(100.0 * :nn / :sampled, 2));
      out := ARRAY_APPEND(:out, OBJECT_CONSTRUCT(
        'target_table', :fqn,
        'column_name', :g2_name,
        'data_type', :g2_type,
        'status', 'PROFILED',
        'table_rows', :tbl_rows,
        'sampled_rows', :sampled,
        -- NULL, not 100, when there is nothing to sample. Zero rows means the null
        -- rate is UNKNOWN, and "100% null" is a confident statistic about no data
        -- -- the exact species of number this block exists to stop.
        'null_pct', IFF(:sampled = 0, NULL, 100.0 - :fill),
        'distinct_in_sample', GET(:stats, 'DC_' || :g2_name)::NUMBER,
        'min_date', GET(:stats, 'MN_' || :g2_name)::STRING,
        'max_date', GET(:stats, 'MX_' || :g2_name)::STRING,
        'grain_keys', GET(:stats, 'GRAIN_KEYS')::NUMBER,
        'fill_pct', :fill,
        -- The verdict the plan acts on. ALL_NULL is separated from
        -- BELOW_THRESHOLD deliberately: a column that is entirely empty is a
        -- different conversation from one that is patchy, and collapsing them
        -- into "bad" loses the distinction the operator needs.
        'verdict', CASE
                     WHEN :sampled = 0 THEN 'EMPTY_TABLE'
                     WHEN :fill = 0 THEN 'ALL_NULL'
                     WHEN :fill < :min_fill THEN 'BELOW_THRESHOLD'
                     ELSE 'USABLE'
                   END,
        'note', CASE
                  WHEN :sampled = 0
                    THEN 'The table is empty, so nothing about this column can be '
                      || 'checked. Anything derived from it would be a number about no data.'
                  WHEN :fill = 0
                    THEN 'Present in the schema and entirely empty in the sample. This '
                      || 'is the case that looks fine to schema-only discovery and is not.'
                  WHEN :fill < :min_fill
                    THEN 'Populated ' || :fill || '% of the time, under the '
                      || :min_fill || '% floor set by MERCHANT_MIN_FILL_PCT.'
                  ELSE 'Populated ' || :fill || '% of the sample.'
                END));
      gi := :gi + 1;
    END WHILE;

    ti := :ti + 1;
  END WHILE;

  -- Publish for the plan and the review. Same chunked, base64 transport as
  -- discovery, for the same reasons: a 16KB variable cap, and backslashes in a
  -- single-quoted SET literal being eaten by the parser.
  LET payload STRING := TO_JSON(OBJECT_CONSTRUCT(
      'profile', :out,
      'min_fill_pct', :min_fill,
      'sample_rows', :sample_rows,
      'profiled_at', CURRENT_TIMESTAMP()::STRING));
  LET encoded STRING := BASE64_ENCODE(:payload);
  LET nchunks INT := GREATEST(1, CEIL(LENGTH(:encoded) / 12000.0));
  IF (:nchunks > 4) THEN
    res := (SELECT 'PROFILE TOO LARGE' AS target_table, '' AS column_name, '' AS data_type,
                   'BLOCKED' AS status, NULL::NUMBER AS table_rows, NULL::NUMBER AS sampled_rows,
                   NULL::NUMBER AS null_pct, NULL::NUMBER AS distinct_in_sample,
                   NULL::STRING AS min_date, NULL::STRING AS max_date,
                   'BLOCKED' AS verdict,
                   'Profile statistics are ' || LENGTH(:encoded) || ' encoded bytes, over the '
                || '48KB handoff limit. Name fewer columns.' AS note);
    RETURN TABLE(res);
  END IF;

  LET pi INT := 0;
  WHILE (:pi < :nchunks) DO
    LET piece STRING := SUBSTR(:encoded, :pi * 12000 + 1, 12000);
    EXECUTE IMMEDIATE 'SET MERCHANT_PROFILE_' || (:pi + 1) || ' = ''' || :piece || '''';
    pi := :pi + 1;
  END WHILE;
  EXECUTE IMMEDIATE 'SET MERCHANT_PROFILE_N = ' || :nchunks;

  res := (
    SELECT v.value:target_table::STRING     AS target_table,
           v.value:column_name::STRING      AS column_name,
           v.value:data_type::STRING        AS data_type,
           v.value:status::STRING           AS status,
           v.value:table_rows::NUMBER       AS table_rows,
           v.value:sampled_rows::NUMBER     AS sampled_rows,
           v.value:null_pct::NUMBER(38,2)   AS null_pct,
           v.value:distinct_in_sample::NUMBER AS distinct_in_sample,
           v.value:min_date::STRING         AS min_date,
           v.value:max_date::STRING         AS max_date,
           v.value:verdict::STRING          AS verdict,
           v.value:note::STRING             AS note
    FROM TABLE(FLATTEN(input => :out)) v
    ORDER BY CASE v.value:verdict::STRING
               WHEN 'EMPTY_TABLE' THEN 1 WHEN 'ALL_NULL' THEN 2
               WHEN 'MISSING' THEN 3 WHEN 'NO_ACCESS' THEN 4
               WHEN 'BELOW_THRESHOLD' THEN 5 ELSE 6 END,
             target_table, column_name
  );
  RETURN TABLE(res);
END;
$$;
-- ─────────────────────────────────────────────────────────────────────────────
-- BLOCK 3 · THE PLAN, THE REVIEW AND THE BUILD
-- Generates every statement and PRINTS it. Creates nothing while the gate is
-- FALSE. When the gate is TRUE it executes the same list it just printed.
--
-- Plan and build are ONE block on purpose. Session variables cap at 16,384
-- bytes and EXECUTE IMMEDIATE from a variable inherits that cap, so a plan of
-- any real size cannot be handed to a separate build block. Keeping them
-- together also guarantees the build runs the plan printed in THIS session
-- rather than a stale one.
-- ─────────────────────────────────────────────────────────────────────────────
EXECUTE IMMEDIATE $$
DECLARE
  res RESULTSET;
BEGIN
  -- ── Reassemble the discovery handoff ──────────────────────────────────────
  -- Unrolled on purpose: GETVARIABLE requires a constant argument and rejects
  -- 'MERCHANT_SIGNALS_' || :i with "argument 0 ... needs to be constant".
  LET nchunks INT := COALESCE((SELECT TRY_CAST(GETVARIABLE('MERCHANT_SIGNALS_N') AS INT)), 0);
  IF (:nchunks = 0) THEN
    res := (SELECT 0 AS step, 'BLOCKED' AS action,
                   'Block 1 has not run in this session. Run the file top to bottom.' AS statement);
    RETURN TABLE(res);
  END IF;

  LET buf STRING :=
       COALESCE(GETVARIABLE('MERCHANT_SIGNALS_1'), '')
    || COALESCE(GETVARIABLE('MERCHANT_SIGNALS_2'), '')
    || COALESCE(GETVARIABLE('MERCHANT_SIGNALS_3'), '')
    || COALESCE(GETVARIABLE('MERCHANT_SIGNALS_4'), '')
    || COALESCE(GETVARIABLE('MERCHANT_SIGNALS_5'), '')
    || COALESCE(GETVARIABLE('MERCHANT_SIGNALS_6'), '')
    || COALESCE(GETVARIABLE('MERCHANT_SIGNALS_7'), '')
    || COALESCE(GETVARIABLE('MERCHANT_SIGNALS_8'), '');

  -- Block 1 base64-encodes the payload so backslashes in the data cannot be
  -- eaten by the SET literal. Fall back to reading it raw so a mixed-version
  -- file still works.
  LET found VARIANT := COALESCE(TRY_PARSE_JSON(TRY_BASE64_DECODE_STRING(:buf)),
                                TRY_PARSE_JSON(:buf));
  IF (:found IS NULL) THEN
    res := (SELECT 0 AS step, 'BLOCKED' AS action,
                   'Discovery handoff did not parse (' || LENGTH(:buf)
                   || ' bytes over ' || :nchunks || ' chunks). Re-run from the top.' AS statement);
    RETURN TABLE(res);
  END IF;

  LET sig    VARIANT := :found:sig;
  LET cnt    VARIANT := :found:cnt;
  LET w      INT     := :found:window_days::INT;
  LET mode   STRING  := UPPER(COALESCE(:found:mode::STRING, 'DISCOVER'));
  LET db     STRING  := COALESCE(NULLIF($MERCHANT_TARGET_DB::VARCHAR, ''), CURRENT_DATABASE());
  LET sch    STRING  := $MERCHANT_SCHEMA::VARCHAR;
  LET wh     STRING  := COALESCE(NULLIF($MERCHANT_APP_WAREHOUSE::VARCHAR, ''), CURRENT_WAREHOUSE());
  LET budget NUMBER  := COALESCE((SELECT TRY_CAST($MERCHANT_BUDGET_CREDITS::VARCHAR AS NUMBER)), 0);

  -- ── Reassemble the profile handoff ────────────────────────────────────────
  -- Optional: Block 2 only publishes when its own gate is open. Absent is not
  -- the same as clean, and the difference is carried explicitly in :prof_status
  -- so nothing downstream can read "no findings" out of "never looked".
  LET pchunks INT := COALESCE((SELECT TRY_CAST(GETVARIABLE('MERCHANT_PROFILE_N') AS INT)), 0);
  LET prof        VARIANT := NULL;
  LET prof_status STRING  := 'NOT RUN';
  IF (:pchunks > 0) THEN
    LET pbuf STRING :=
         COALESCE(GETVARIABLE('MERCHANT_PROFILE_1'), '')
      || COALESCE(GETVARIABLE('MERCHANT_PROFILE_2'), '')
      || COALESCE(GETVARIABLE('MERCHANT_PROFILE_3'), '')
      || COALESCE(GETVARIABLE('MERCHANT_PROFILE_4'), '');
    prof := TRY_PARSE_JSON(TRY_BASE64_DECODE_STRING(:pbuf));
    prof_status := IFF(:prof IS NULL, 'UNPARSEABLE', 'AVAILABLE');
  END IF;

  -- Columns the profile says are not fit to build on. The plan reads this to
  -- downgrade or refuse, and the reviewer is shown the same list.
  LET unusable ARRAY := ARRAY_CONSTRUCT();
  LET prof_usable INT := 0;
  IF (:prof_status = 'AVAILABLE') THEN
    SELECT COUNT_IF(v.value:verdict::STRING = 'USABLE')
      INTO :prof_usable
      FROM TABLE(FLATTEN(input => :prof:profile)) v;
    SELECT COALESCE(ARRAY_AGG(OBJECT_CONSTRUCT(
                      'table',    v.value:target_table::STRING,
                      'column',   v.value:column_name::STRING,
                      'verdict',  v.value:verdict::STRING,
                      'fill_pct', v.value:fill_pct::NUMBER,
                      'note',     v.value:note::STRING)), ARRAY_CONSTRUCT())
      INTO :unusable
      FROM TABLE(FLATTEN(input => :prof:profile)) v
      WHERE v.value:verdict::STRING <> 'USABLE';
  END IF;

  -- ── This run's identity ───────────────────────────────────────────────────
  -- Everything measured later is found by this tag. Verified: ALTER SESSION SET
  -- QUERY_TAG works inside an anonymous block (it is barred only in OWNER'S
  -- RIGHTS procedures), and the tag propagates to statements this block issues by
  -- EXECUTE IMMEDIATE -- which is how the build loop runs the plan.
  --
  -- The tag is best effort on purpose. It is a measurement aid, not a safety
  -- property, so a session that refuses it must still build. The outcome is
  -- recorded rather than assumed, because a silently untagged run would later look
  -- like a run that cost nothing.
  LET run_id STRING := COALESCE(NULLIF($MERCHANT_RUN_ID::VARCHAR, ''), UUID_STRING());
  LET tier   STRING := UPPER(COALESCE(NULLIF($MERCHANT_DEPLOY_TIER::VARCHAR, ''), 'DISCOVER'));
  IF (:tier NOT IN ('DISCOVER', 'LIMITED', 'PRODUCTION')) THEN
    tier := 'DISCOVER';
  END IF;
  LET qtag STRING := TO_JSON(OBJECT_CONSTRUCT(
      'oneshot', 'Retail Merchant Agent', 'prefix', 'MERCHANT', 'run_id', :run_id, 'tier', :tier));
  LET tag_status STRING := 'NOT SET';
  BEGIN
    EXECUTE IMMEDIATE 'ALTER SESSION SET QUERY_TAG = ''' || REPLACE(:qtag, '''', '''''') || '''';
    tag_status := 'SET';
  EXCEPTION WHEN OTHER THEN
    tag_status := 'REFUSED (' || SQLERRM || ') - warehouse credits for this run '
               || 'cannot be attributed by tag and will read NOT_ATTRIBUTABLE';
  END;

  -- The warehouse the measured tiers build on, and the cap over it.
  LET meas_wh STRING := COALESCE(NULLIF($MERCHANT_MEASURE_WAREHOUSE::VARCHAR, ''),
                                 LEFT(:sch, 80) || '_ONESHOT_WH');
  LET credit_cap NUMBER(38,2) := COALESCE((SELECT TRY_CAST($MERCHANT_CREDIT_CAP::VARCHAR AS NUMBER)), 0);
  LET rate NUMBER(38,4) := COALESCE((SELECT TRY_CAST($MERCHANT_COST_PER_CREDIT::VARCHAR AS NUMBER)), 3);
  LET out_ratio NUMBER(38,4) := COALESCE((SELECT TRY_CAST($MERCHANT_OUTPUT_TOKEN_RATIO::VARCHAR AS NUMBER)), 0.5);
  LET min_fill NUMBER(38,2) := COALESCE((SELECT TRY_CAST($MERCHANT_MIN_FILL_PCT::VARCHAR AS NUMBER)), 60);
  LET notif STRING := COALESCE(NULLIF($MERCHANT_NOTIFICATION_INTEGRATION::VARCHAR, ''), '');

  -- LIMITED -> PRODUCTION extrapolation. The solution's plan overwrites these with
  -- numbers it discovered; the defaults extrapolate by a factor of one, which is
  -- the only honest default because a solution that has not said how it scales has
  -- not earned a multiplier.
  --
  -- The ratio is PRINTED rather than applied silently, so the client can check the
  -- arithmetic instead of trusting it.
  LET scale_unit       STRING := 'unspecified unit';
  LET scale_limited    NUMBER(38,4) := 1;
  LET scale_production NUMBER(38,4) := 1;
  -- Whether this role may create the isolated warehouse and its monitor. Same
  -- read as Block 0; repeated here because the plan must not depend on a human
  -- having read Block 0's output.
  LET wh_ok BOOLEAN := (UPPER(CURRENT_ROLE()) = 'ACCOUNTADMIN');
  LET rm_ok BOOLEAN := (UPPER(CURRENT_ROLE()) = 'ACCOUNTADMIN');
  IF (NOT :wh_ok) THEN
    BEGIN
      EXECUTE IMMEDIATE 'SHOW GRANTS ON ACCOUNT';
      SELECT COUNT_IF(UPPER("privilege") = 'CREATE WAREHOUSE'
                      AND IS_ROLE_IN_SESSION("grantee_name")) > 0,
             COUNT_IF(UPPER("privilege") = 'CREATE RESOURCE MONITOR'
                      AND IS_ROLE_IN_SESSION("grantee_name")) > 0
        INTO :wh_ok, :rm_ok
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    EXCEPTION WHEN OTHER THEN
      wh_ok := FALSE;
      rm_ok := FALSE;
    END;
  END IF;


  IF (:db IS NULL) THEN
    res := (SELECT 0 AS step, 'BLOCKED' AS action,
                   'No database selected. Run USE DATABASE or set MERCHANT_TARGET_DB.' AS statement);
    RETURN TABLE(res);
  END IF;
  IF (:wh IS NULL) THEN
    res := (SELECT 0 AS step, 'BLOCKED' AS action,
                   'No warehouse selected. Run USE WAREHOUSE or set MERCHANT_APP_WAREHOUSE.' AS statement);
    RETURN TABLE(res);
  END IF;

  LET tgt   STRING := :db || '.' || :sch;
  LET since STRING := 'DATEADD(day, -' || :w || ', CURRENT_TIMESTAMP())';
  LET stmts ARRAY  := ARRAY_CONSTRUCT();

  -- Running cost model. Every append that costs credits should also add to
  -- these, so the summary at the bottom is derived rather than asserted.
  --
  -- The scale is NOT optional. `LET x NUMBER := 0` is NUMBER(38,0), so every
  -- fractional credit added to it truncates to zero and the headline reports
  -- "~0 credits/day" no matter what the plan actually costs. That silently
  -- zeroed the cost model in every solution until a builder noticed the summary
  -- disagreed with its own detail lines.
  LET cost_day    NUMBER(38,6) := 0;   -- steady-state credits/day
  LET cost_once   NUMBER(38,6) := 0;   -- one-time build/backfill credits
  LET cost_detail ARRAY  := ARRAY_CONSTRUCT();
  LET dials       ARRAY  := ARRAY_CONSTRUCT();
  -- Findings the operator must read before approving: what discovery concluded,
  -- which sources were accepted or rejected, what will be skipped and why. This
  -- is the part a non-technical reader actually learns from, so it prints above
  -- the statement list rather than being buried in it.
  LET notes       ARRAY  := ARRAY_CONSTRUCT();
  -- One plain-language sentence about what the customer ends up with, printed
  -- FIRST, above the statement counts and credit figures. Without it the output
  -- opens on "191 statements | 0.42 credits/day", which reads as a build log
  -- rather than an outcome, and a business reader stops there.
  LET headline    STRING := '';

  -- ── Actions the app may offer ─────────────────────────────────────────────
  -- Solutions append to this in their own plan section below, one
  -- OBJECT_CONSTRUCT per action. (The marker for that section is NOT named here:
  -- scaffold substitutes it with a plain string replace, so spelling it in prose
  -- splices the entire plan into this comment. That is precisely how this comment
  -- came to be worded so carefully -- it happened, and produced
  -- `cost_once := :cost_once + 0.02;, one OBJECT_CONSTRUCT per action:` and a
  -- syntax error 300 lines from the cause.)
  --
  --   actions := ARRAY_APPEND(:actions, OBJECT_CONSTRUCT(
  --     'code',      'CONVERT_ELIGIBLE',            -- typed to confirm; keep it short
  --     'label',     'Convert the 25 eligible tables',
  --     'tier',      'PRODUCTION',                  -- SAMPLE | LIMITED | PRODUCTION
  --     'effect',    'Creates an Iceberg copy of each eligible table. Sources are
  --                   never modified.',
  --     'undo',      'DROP the ICE_ copies, or CALL TEARDOWN().',
  --     'est',       1.85,                          -- credits, one-time
  --     'basis',     '0.15 credits per table CTAS x 25 tables, from measured row
  --                   counts',                      -- how `est` was arrived at
  --     'sql',       ARRAY_CONSTRUCT(stmt1, stmt2)  -- runs in order
  --   ));
  --
  -- `est` and `basis` are not decoration. A button that changes production without
  -- saying what it costs is the thing this repo exists to avoid, and an estimate
  -- with no stated basis is a number someone will quote back at you. Compute `est`
  -- from something measured -- row counts, bytes, table counts discovered in
  -- Block 1 -- not from a constant, and say so in `basis`.
  LET actions     ARRAY  := ARRAY_CONSTRUCT();
  -- Was the file authorised to arm them at all? Read once, recorded in the build
  -- context, and re-checked inside RUN_ACTION so the answer cannot be edited later
  -- by anyone who can only reach the app.
  LET allow_actions BOOLEAN := COALESCE(
    (SELECT TRY_CAST($MERCHANT_ALLOW_ACTIONS::VARCHAR AS BOOLEAN)), FALSE);

  -- SAMPLE tier, governed separately and defaulting TRUE. Kept as its own variable
  -- rather than folded into :allow_actions so that the two authorisations stay
  -- distinguishable everywhere downstream -- the build context records both, and
  -- RUN_ACTION picks the one matching the action's own TIER. COALESCE to TRUE here
  -- because a build produced by an OLDER file that has no MERCHANT_ALLOW_SAMPLE_ACTIONS
  -- line should still get the new default rather than silently disarming.
  LET allow_sample_actions BOOLEAN := COALESCE(
    (SELECT TRY_CAST($MERCHANT_ALLOW_SAMPLE_ACTIONS::VARCHAR AS BOOLEAN)), TRUE);

  -- ── LLM adaptation ────────────────────────────────────────────────────────
  -- The plan is not fixed: the model reads what discovery actually found and
  -- makes the judgement calls a hardcoded rule cannot. This exists because a
  -- pattern list is always one customer behind reality — this solution's own BI
  -- probe reported "no BI tools" on an account that had ThoughtSpot running
  -- daily, because the tool identity was in the service-account NAME
  -- (IIP_THOUGHTSPOT_SVC) and not in the driver string it was matching on. A
  -- model handed the account inventory spots that immediately.
  --
  -- Three guardrails, none optional:
  --   1. The model returns JSON DECISIONS, never SQL. Nothing it emits is
  --      interpolated into a statement. The deterministic code below builds the
  --      SQL from validated choices, so a prompt injection in a table name
  --      cannot become executable.
  --   2. Every choice is validated against what discovery actually saw before
  --      it is used. A name the model invents is discarded.
  --   3. If Cortex is unavailable, the response is not JSON, or anything throws,
  --      the run falls back to deterministic defaults and SAYS SO. An LLM being
  --      down must never block a build.
  LET adapt        VARIANT := NULL;
  LET adapt_status STRING  := 'SKIPPED';
  LET adapt_raw    STRING  := '';
  LET adapt_prompt STRING  := '';
  LET adapt_model  STRING  := COALESCE(NULLIF($MERCHANT_MODEL::VARCHAR, ''), 'claude-opus-5');

  IF (:adapt_prompt <> '') THEN
    BEGIN
      adapt_raw := (SELECT SNOWFLAKE.CORTEX.AI_COMPLETE(:adapt_model,
        'You are configuring a Snowflake deployment. Answer with ONE JSON object '
     || 'and nothing else: no prose, no code fence. If you are unsure of a value, '
     || 'use null rather than guessing. Never invent an object name that is not '
     || 'listed in the input.' || CHR(10) || :adapt_prompt));
      -- Models still occasionally wrap JSON in a fence despite the instruction.
      adapt := TRY_PARSE_JSON(REGEXP_REPLACE(:adapt_raw, '^[^{]*|[^}]*$', ''));
      IF (:adapt IS NULL) THEN
        adapt_status := 'UNPARSEABLE - using deterministic defaults';
      ELSE
        adapt_status := 'APPLIED';
      END IF;
    EXCEPTION WHEN OTHER THEN
      adapt_status := 'UNAVAILABLE (' || SQLERRM || ') - using deterministic defaults';
      adapt := NULL;
    END;
    notes := ARRAY_APPEND(:notes, 'MODEL ADAPTATION (' || :adapt_model || '): ' || :adapt_status
      || '. The model chose configuration from what discovery found; it never '
      || 'produced SQL, and every choice was checked against the discovered '
      || 'inventory before use. Its reasoning is shown below.');
  END IF;


  stmts := ARRAY_APPEND(:stmts, 'CREATE SCHEMA IF NOT EXISTS ' || :tgt);
  stmts := ARRAY_APPEND(:stmts, 'CREATE STAGE IF NOT EXISTS ' || :tgt || '.APP_STAGE');

  -- ── KEEPING THE APP WARM ──────────────────────────────────────────────────
  -- The claim here is narrow on purpose, because the wide version is false.
  --
  -- These apps are created with ROOT_LOCATION, and per Snowflake's own docs that
  -- restricts them to the WAREHOUSE runtime, which "creates a personal instance of
  -- the app for each viewer" and "does not support caching between sessions".
  -- There is no shared, long-lived app process to pre-warm; the only runtime that
  -- has one is the CONTAINER runtime, which needs the app recreated with FROM, a
  -- compute pool and a PyPI access integration. So nothing below claims to keep
  -- "the app" running.
  --
  -- What it does keep warm is real and is the dominant cost of a slow first load:
  -- the code warehouse caches the Python packages Streamlit imports, and that
  -- cache is thrown away when the warehouse suspends. A warehouse that never
  -- suspends never loses it.
  --
  -- THIS IS NOT THE MISTAKE WE MADE BEFORE. An earlier attempt elsewhere ran a
  -- SELECT 1 on a schedule to "warm" a SYSTEM$MANAGED Streamlit service that not
  -- even ACCOUNTADMIN can OPERATE on -- it pinged a proxy and warmed nothing. Here
  -- the warehouse IS the cold thing, and AUTO_SUSPEND = NULL addresses it
  -- directly, with no heartbeat task to drift or lie.
  LET warm_on BOOLEAN := COALESCE(
    (SELECT TRY_CAST($MERCHANT_KEEP_APP_WARM::VARCHAR AS BOOLEAN)), FALSE);
  LET warm_wh STRING := UPPER(TRIM(COALESCE(
    NULLIF($MERCHANT_WARM_WAREHOUSE::VARCHAR, ''), 'ONESHOT_APP_WH')));
  -- An explicitly named app warehouse is an instruction, not a default, so
  -- warming leaves it alone rather than silently rehoming the app somewhere else.
  LET wh_named BOOLEAN := (NULLIF($MERCHANT_APP_WAREHOUSE::VARCHAR, '') IS NOT NULL);
  LET warm_status STRING := 'OFF';

  IF (:warm_on AND :wh_named) THEN
    warm_status := 'DECLINED_EXPLICIT_WAREHOUSE';
    notes := ARRAY_APPEND(:notes,
      'APP WARMING SKIPPED: MERCHANT_APP_WAREHOUSE names ' || :wh || ' explicitly, so '
   || 'the app stays there rather than being moved to ' || :warm_wh || '. Clear '
   || 'MERCHANT_APP_WAREHOUSE to let warming manage the app warehouse, or set '
   || 'AUTO_SUSPEND = NULL on ' || :wh || ' yourself to get the same effect.');
  ELSEIF (:warm_on AND :wh_ok) THEN
    -- Deliberately NOT recorded in ATTACHED_OBJECT_REGISTRY. That registry is what
    -- TEARDOWN drops, and this warehouse is shared by every oneshot app in the
    -- account: registering it would mean tearing down any ONE solution suspends
    -- and drops the warehouse the other twenty are relying on. The DROP is printed
    -- in the notes instead, for a human to run once nothing needs it.
    stmts := ARRAY_APPEND(:stmts,
      'CREATE WAREHOUSE IF NOT EXISTS ' || :warm_wh || ' WAREHOUSE_SIZE = XSMALL '
      -- NULL, not a large number: this is the documented way to say never suspend.
      -- Anything finite eventually discards the package cache, which is the one
      -- thing this warehouse exists to hold.
   || 'AUTO_SUSPEND = NULL AUTO_RESUME = TRUE INITIALLY_SUSPENDED = FALSE '
   || 'COMMENT = ''oneshot shared app warehouse. Never auto-suspends, so the '
   || 'Streamlit Python package cache stays hot and apps open fast. SHARED by '
   || 'every oneshot app; TEARDOWN does not drop it.''');
    -- Re-applied on every run rather than only at creation. IF NOT EXISTS means an
    -- existing warehouse keeps whatever AUTO_SUSPEND it already had, and a warm
    -- warehouse that quietly suspends at 60s is the exact failure this is for.
    stmts := ARRAY_APPEND(:stmts,
      'ALTER WAREHOUSE ' || :warm_wh || ' SET AUTO_SUSPEND = NULL AUTO_RESUME = TRUE');
    -- The app binds to whatever :wh holds when the generated app DDL renders.
    wh := :warm_wh;
    warm_status := 'ON';
    cost_day := :cost_day + 24;
    cost_detail := ARRAY_APPEND(:cost_detail,
      'APP WARMING: ' || :warm_wh || ' is an XSMALL warehouse that NEVER '
   || 'auto-suspends, so roughly 24 credits/day, every day, whether or not anyone '
   || 'opens an app. That is the cost of fast first loads and it is deliberate. It '
   || 'is also the TOTAL for every oneshot app in this account, not per app, '
   || 'because they all share this warehouse. Set MERCHANT_KEEP_APP_WARM = FALSE to '
   || 'remove it from the estimate and accept slower first loads.');
    notes := ARRAY_APPEND(:notes,
      'APP WARMING ON: this app runs on ' || :warm_wh || ', which never suspends so '
   || 'the Streamlit package cache stays hot. It is SHARED with every other oneshot '
   || 'app and TEARDOWN does NOT drop it. When nothing needs it any more: DROP '
   || 'WAREHOUSE ' || :warm_wh || '. Note what this does and does not do -- the '
   || 'warehouse runtime starts a separate app process per viewer, so each '
   || 'viewer''s FIRST load still builds their own session; what is saved is the '
   || 'package cache, which is the slowest part of it.');
  ELSEIF (:warm_on) THEN
    warm_status := 'DEGRADED_NO_PRIVILEGE';
    notes := ARRAY_APPEND(:notes,
      'APP WARMING DEGRADED: MERCHANT_KEEP_APP_WARM is TRUE but ' || CURRENT_ROLE()
   || ' cannot create a warehouse, so the app stays on ' || :wh || ' and first '
   || 'loads pay for the package cache being rebuilt after every suspend. To fix, '
   || 'either GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE ' || CURRENT_ROLE()
   || ', or have an administrator run: CREATE WAREHOUSE ' || :warm_wh
   || ' WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = NULL AUTO_RESUME = TRUE; then set '
   || 'MERCHANT_APP_WAREHOUSE = ''' || :warm_wh || '''.');
  END IF;

  -- The per-viewer sleep timer, which is the other half of a warm app and the only
  -- half that touches the app's own session rather than its warehouse.
  --
  -- Written as a stage file because that is the only route available: a
  -- ROOT_LOCATION app reads its config from .streamlit/config.toml on its stage,
  -- and a stored procedure cannot PUT. COPY INTO with a decoded literal is the
  -- same trick the app python itself arrives by; the generated app snippet below
  -- explains why base64 rather than a quoted literal.
  LET sleep_min INT := COALESCE(
    (SELECT TRY_CAST($MERCHANT_APP_SLEEP_MINUTES::VARCHAR AS INT)), 240);
  -- Clamped rather than trusted. Snowflake accepts 5 to 240 and rejects anything
  -- outside it, which would fail the file write and leave no timer at all.
  IF (:sleep_min < 5)   THEN sleep_min := 5;   END IF;
  IF (:sleep_min > 240) THEN sleep_min := 240; END IF;
  stmts := ARRAY_APPEND(:stmts,
    'COPY INTO @' || :tgt || '.APP_STAGE/.streamlit/config.toml FROM (SELECT '
 || 'BASE64_DECODE_STRING(''' || BASE64_ENCODE(
      '[snowflake]' || CHR(10) || '[snowflake.sleep]' || CHR(10)
   || 'streamlitSleepTimeoutMinutes = ' || :sleep_min || CHR(10)) || ''')) '
 || 'FILE_FORMAT = (TYPE = CSV COMPRESSION = NONE FIELD_DELIMITER = NONE '
 || 'RECORD_DELIMITER = NONE FIELD_OPTIONALLY_ENCLOSED_BY = NONE '
 || 'ESCAPE_UNENCLOSED_FIELD = NONE) OVERWRITE = TRUE SINGLE = TRUE');

  -- Registry of everything attached OUTSIDE this schema. Teardown reads it.
  -- DROP SCHEMA CASCADE does not detach DMFs, policies or tags from tables that
  -- live elsewhere, and discovering them at teardown time cannot see across
  -- schemas, so the only reliable record is the one written at build time.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE TABLE IF NOT EXISTS ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
 || '(TARGET_FQN VARCHAR, ARTIFACT VARCHAR, ARGUMENTS VARCHAR, KIND VARCHAR, '
 || 'ATTACHED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP())');

  -- ── The measurement instrument ────────────────────────────────────────────
  -- One row per statement the build ran, with its QUERY_ID. This is what makes
  -- the cost of a build measurable rather than estimated, and it is deliberately
  -- the same shape as ACTION_STATEMENT_LOG, which has been proving the pattern
  -- works for the action framework.
  --
  -- QUERY_ID rather than the query tag is the PRIMARY key into metering here.
  -- The tag is set and it does propagate, but it identifies the run, not the
  -- statement, so it cannot tell you which part of a build was expensive. The tag
  -- is the fallback for work the loop cannot see: panel queries from the app,
  -- task runs, dynamic-table refreshes.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE TABLE IF NOT EXISTS ' || :tgt || '.BUILD_STATEMENT_LOG '
 || '(RUN_ID VARCHAR, TIER VARCHAR, SEQ INT, STATEMENT VARCHAR, QUERY_ID VARCHAR, '
 || 'STATUS VARCHAR, ERROR VARCHAR, ELAPSED_MS NUMBER, ROWS_PRODUCED NUMBER, '
 || 'RAN_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP())');
  stmts := ARRAY_APPEND(:stmts,
    'CREATE TABLE IF NOT EXISTS ' || :tgt || '.COST_MEASURED '
 || '(RUN_ID VARCHAR, TIER VARCHAR, CATEGORY VARCHAR, LABEL VARCHAR, BASIS VARCHAR, '
 || 'CREDITS NUMBER(38,9), STATUS VARCHAR, SOURCE_VIEW VARCHAR, LATENCY_NOTE VARCHAR, '
 || 'ROWS_PROCESSED NUMBER, WALL_CLOCK_MS NUMBER, '
 || 'MEASURED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP())');
  -- Which run is which, so MEASURE() can be called months later and still know
  -- what it is measuring and over what window.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE TABLE IF NOT EXISTS ' || :tgt || '.RUN_LEDGER '
 || '(RUN_ID VARCHAR, TIER VARCHAR, QUERY_TAG VARCHAR, TAG_STATUS VARCHAR, '
 || 'MEASURE_WAREHOUSE VARCHAR, CREDIT_CAP NUMBER(38,2), CAP_APPLIED BOOLEAN, '
 || 'GATE_OPENED BOOLEAN, PROFILE_STATUS VARCHAR, REVIEW_VERDICT VARCHAR, '
 || 'REVIEW_OVERRIDDEN BOOLEAN, STATEMENTS_PLANNED INT, '
 || 'STARTED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(), '
 || 'RUN_BY VARCHAR DEFAULT CURRENT_USER(), TEARDOWN_AT TIMESTAMP_NTZ)');

  -- ── Isolation, so warehouse credits can be attributed at all ──────────────
  -- Registered BEFORE it is created. The other order leaves an object nobody
  -- knows about if the registry write fails, and a warehouse nobody knows about
  -- is a warehouse nobody suspends.
  --
  -- Every registry write is an ANTI-JOIN INSERT, keyed on
  -- (TARGET_FQN, ARTIFACT, KIND). The table is CREATE TABLE IF NOT EXISTS -- it has
  -- to survive, because TEARDOWN reads it -- so a plain INSERT registered the same
  -- object again on every re-run. Caught by the idempotence step at
  -- ATTACHED_OBJECT_REGISTRY 6 -> 8, the two extra rows being the owned warehouse
  -- and its resource monitor.
  --
  -- This is not cosmetic double-counting. The registry describes what is CURRENTLY
  -- attached, so duplicates inflate the "N external attachment(s)" figure shown to a
  -- customer, and TEARDOWN then reports detaching 8 things when 6 exist. It only
  -- looked harmless because DROP and UNSET happen to be idempotent; the first
  -- attachment KIND whose undo is not would fail on its second pass and be counted
  -- as a teardown failure on an account where nothing was actually wrong.
  --
  -- Note what is NOT measured: the handful of statements above this point ran on
  -- the caller's warehouse, because creating a schema requires a warehouse and
  -- this one does not exist yet. They are metadata operations and near-free, and
  -- saying so is better than implying the isolation is total.
  LET cap_applied BOOLEAN := FALSE;
  IF (:tier IN ('LIMITED', 'PRODUCTION') AND :wh_ok) THEN
    stmts := ARRAY_APPEND(:stmts,
      'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY (TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) '
   || 'SELECT ''' || :meas_wh || ''', ''WAREHOUSE'', '''', ''OWNED_WAREHOUSE'' '
   || 'WHERE NOT EXISTS (SELECT 1 FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
   || 'WHERE TARGET_FQN = ''' || :meas_wh || ''' AND ARTIFACT = ''WAREHOUSE'' '
   || 'AND KIND = ''OWNED_WAREHOUSE'')');
    stmts := ARRAY_APPEND(:stmts,
      'CREATE WAREHOUSE IF NOT EXISTS ' || :meas_wh || ' WAREHOUSE_SIZE = XSMALL '
   || 'AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE '
   || 'COMMENT = ''oneshot Retail Merchant Agent run ' || :run_id || ' - dropped by TEARDOWN''');
    IF (:rm_ok AND :credit_cap > 0) THEN
      stmts := ARRAY_APPEND(:stmts,
        'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY (TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) '
     || 'SELECT ''' || :meas_wh || '_RM'', ''RESOURCE_MONITOR'', '''', ''RESOURCE_MONITOR'' '
     || 'WHERE NOT EXISTS (SELECT 1 FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
     || 'WHERE TARGET_FQN = ''' || :meas_wh || '_RM'' AND ARTIFACT = ''RESOURCE_MONITOR'' '
     || 'AND KIND = ''RESOURCE_MONITOR'')');
      stmts := ARRAY_APPEND(:stmts,
        'CREATE RESOURCE MONITOR IF NOT EXISTS ' || :meas_wh || '_RM WITH '
        -- CREDIT_QUOTA takes an INTEGER. The cap is carried as NUMBER(38,2) so it
        -- can be compared and printed, and rendering it straight produced
        -- "CREDIT_QUOTA = 2.00", which Snowflake rejects with "invalid value
        -- [2.00]". Rounded UP, because rounding a credit ceiling down silently
        -- tightens a limit the operator chose.
     || 'CREDIT_QUOTA = ' || GREATEST(1, CEIL(:credit_cap))::INT || ' FREQUENCY = DAILY '
     || 'START_TIMESTAMP = IMMEDIATELY '
     || 'TRIGGERS ON 80 PERCENT DO NOTIFY ON 100 PERCENT DO SUSPEND '
     || 'ON 110 PERCENT DO SUSPEND_IMMEDIATE');
      stmts := ARRAY_APPEND(:stmts,
        'ALTER WAREHOUSE ' || :meas_wh || ' SET RESOURCE_MONITOR = ' || :meas_wh || '_RM');
      cap_applied := TRUE;
    END IF;
    -- Everything after this point is billed to the isolated warehouse, which is
    -- what makes WAREHOUSE_METERING_HISTORY attributable to this run.
    stmts := ARRAY_APPEND(:stmts, 'USE WAREHOUSE ' || :meas_wh);
    cost_detail := ARRAY_APPEND(:cost_detail,
      'MEASUREMENT: this build runs on ' || :meas_wh || ', an XSMALL warehouse it '
   || 'creates and TEARDOWN drops. It exists so warehouse credits can be '
   || 'attributed to this run -- WAREHOUSE_METERING_HISTORY reports per warehouse '
   || 'per hour and has no query-tag column, so isolation is the only way. '
   || IFF(:cap_applied,
          'Capped at ' || :credit_cap || ' credits/day by a resource monitor.',
          'NOT capped: this role cannot create a resource monitor, so the plan '
       || 'prints the statement for an administrator instead of pretending a '
       || 'ceiling exists.'));
  ELSEIF (:tier IN ('LIMITED', 'PRODUCTION')) THEN
    notes := ARRAY_APPEND(:notes,
      'MEASUREMENT DEGRADED: ' || :tier || ' asked for an isolated warehouse and '
   || CURRENT_ROLE() || ' cannot create one. The build runs on ' || :wh
   || ' instead. Everything still builds, rows and wall clock are still measured '
   || 'exactly, and WAREHOUSE CREDITS will read NOT_ATTRIBUTABLE rather than a '
   || 'number -- because on a shared warehouse they genuinely cannot be separated '
   || 'from everyone else''s work. To fix: GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE '
   || CURRENT_ROLE() || '.');
  END IF;

  -- ── MEASURE(): read back what this run actually cost ──────────────────────
  -- Re-callable. Every category names its own source and its own latency, and a
  -- category that has not landed says so instead of contributing a zero.
  --
  -- Five categories, four different attribution strengths, three different
  -- latencies. Collapsing them into one number would be more comfortable and
  -- would be a lie: warehouse attribution excludes idle time, metering includes
  -- it, AI tokens are in neither, and serverless is in neither and cannot be
  -- attributed by tag at all.
  --
  -- Each INSERT is independently wrapped. These views sit behind different
  -- database roles -- QUERY_ATTRIBUTION_HISTORY needs USAGE_VIEWER or
  -- GOVERNANCE_VIEWER -- so one unreadable view must cost one category, not the
  -- whole measurement.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE PROCEDURE ' || :tgt || '.MEASURE() '
 || 'RETURNS VARCHAR LANGUAGE SQL EXECUTE AS CALLER AS '
 || 'DECLARE '
 || '  run STRING := ''''; tierv STRING := ''''; tagv STRING := ''''; '
 || '  whv STRING := ''''; capped BOOLEAN := FALSE; '
 || '  t0 TIMESTAMP_NTZ; landed INT := 0; pending INT := 0; problems STRING := ''''; '
    -- The run's own statement window, and how many rows QUERY_HISTORY gave back.
    -- Declared TIMESTAMP_LTZ because the table function REJECTS TIMESTAMP_NTZ
    -- outright ("invalid type [TIMESTAMP_NTZ(9)] for parameter
    -- 'END_TIME_RANGE_START'"). The original expression only worked by accident: it
    -- was GREATEST(<ntz>, DATEADD(day,-6,CURRENT_TIMESTAMP())) and CURRENT_TIMESTAMP()
    -- is LTZ, so the coercion happened as a side effect of the guard. Being explicit
    -- means removing that guard cannot silently break the call. RAN_AT is NTZ and is
    -- converted on assignment; both come from the same session's clock and the
    -- window carries a 10-minute margin at each end, so the conversion is immaterial.
 || '  s0 TIMESTAMP_LTZ; s1 TIMESTAMP_LTZ; qh_rows INT := 0; '
 || 'BEGIN '
 || '  SELECT RUN_ID, TIER, QUERY_TAG, MEASURE_WAREHOUSE, COALESCE(CAP_APPLIED, FALSE), STARTED_AT '
 || '    INTO :run, :tierv, :tagv, :whv, :capped, :t0 '
 || '    FROM ' || :tgt || '.RUN_LEDGER ORDER BY STARTED_AT DESC LIMIT 1; '
 || '  IF (:run = '''' OR :run IS NULL) THEN '
 || '    RETURN ''No run recorded yet. MEASURE() reads the newest RUN_LEDGER row.''; '
 || '  END IF; '
 || '  DELETE FROM ' || :tgt || '.COST_MEASURED WHERE RUN_ID = :run; '
     -- 1. Rows and wall clock. NO LATENCY: the INFORMATION_SCHEMA table function
     -- is live, which is why this is MEASURED on the same run that produced it
     -- while every credit figure below may still be pending. Reporting what has
     -- landed beats withholding the row.
     --
      -- Two things went wrong here and both are the same species of bug. The window
      -- was DATEADD(day, -7, ...), which the function rejects outright with "Cannot
      -- retrieve data from more than 7 days ago" -- exactly 7 is already too far --
      -- so the whole category vanished behind a caught exception. And the join was
      -- an INNER join, so a run whose statements had aged out inserted NO ROW AT
      -- ALL, which reads as "nothing to report" rather than "could not look".
      -- LEFT JOIN plus an explicit retention branch means the row always exists and
      -- always says which of those two it is.
      --
      -- A THIRD one of the same species, found by replaying a real run: the lookup
      -- was open-ended forward with RESULT_LIMIT => 10000, and the function returns
      -- the MOST RECENT rows. On a busy account 10,000 queries can be minutes, so a
      -- MEASURE() re-called hours later never reached back to the run at all -- and
      -- reported NO_MATCHING_STATEMENTS, which asserts the statements are not there.
      -- Verified on this account: exactly 10,000 rows back, newest reaching the
      -- present, the run's own statements outside the returned set. That is the
      -- documented workflow for the pending-credit case ("re-run MEASURE() in an
      -- hour"), so the defect sat directly on the path it was built for.
      --
      -- Fixed twice over. The window is now bounded at BOTH ends from our own
      -- BUILD_STATEMENT_LOG, so the 10,000 rows are spent on the run instead of on
      -- everything since; and if the cap is hit anyway, that is its own status.
      -- Bounding alone would have been a fix that works until it quietly doesn't.
 || '  BEGIN '
 || '    SELECT MIN(RAN_AT), MAX(RAN_AT) INTO :s0, :s1 '
 || '      FROM ' || :tgt || '.BUILD_STATEMENT_LOG WHERE RUN_ID = :run; '
 || '    s0 := GREATEST(DATEADD(minute, -10, COALESCE(:s0, :t0)), '
 || '                   DATEADD(day, -6, CURRENT_TIMESTAMP())); '
 || '    s1 := DATEADD(minute, 10, COALESCE(:s1, CURRENT_TIMESTAMP())); '
 || '    SELECT COUNT(*) INTO :qh_rows FROM TABLE(' || :db || '.INFORMATION_SCHEMA.QUERY_HISTORY( '
 || '             END_TIME_RANGE_START => :s0, END_TIME_RANGE_END => :s1, '
 || '             RESULT_LIMIT => 10000)); '
 || '    INSERT INTO ' || :tgt || '.COST_MEASURED '
 || '      (RUN_ID, TIER, CATEGORY, LABEL, BASIS, CREDITS, STATUS, SOURCE_VIEW, '
 || '       LATENCY_NOTE, ROWS_PROCESSED, WALL_CLOCK_MS) '
 || '    SELECT :run, :tierv, ''WORK_DONE'', ''MEASURED'', ''BY_QUERY_ID'', NULL, '
 || '           CASE WHEN COUNT(q.QUERY_ID) > 0 THEN ''LANDED'' '
 || '                WHEN :t0 < DATEADD(day, -6, CURRENT_TIMESTAMP()) '
 || '                  THEN ''RETENTION_EXPIRED'' '
 || '                WHEN :qh_rows >= 10000 THEN ''SEARCH_WINDOW_TRUNCATED'' '
 || '                ELSE ''NO_MATCHING_STATEMENTS'' END, '
 || '           ''INFORMATION_SCHEMA.QUERY_HISTORY'', '
 || '           ''no latency, but only 7 days of retention -- after that rows and '
 || 'wall clock for this run are gone, which is a retention limit and not a zero. '
 || 'Searched '' || :s0::STRING || '' to '' || :s1::STRING || '' ('' || :qh_rows '
 || '           || '' row(s) returned; at 10000 the function caps and the window is '
 || 'reported as truncated rather than as an absence)'', '
 || '           SUM(q.ROWS_PRODUCED), SUM(q.TOTAL_ELAPSED_TIME) '
 || '      FROM ' || :tgt || '.BUILD_STATEMENT_LOG b '
 || '      LEFT JOIN TABLE(' || :db || '.INFORMATION_SCHEMA.QUERY_HISTORY( '
 || '             END_TIME_RANGE_START => :s0, END_TIME_RANGE_END => :s1, '
 || '             RESULT_LIMIT => 10000)) q ON q.QUERY_ID = b.QUERY_ID '
 || '      WHERE b.RUN_ID = :run; '
 || '  EXCEPTION WHEN OTHER THEN problems := :problems || ''WORK_DONE: '' || SQLERRM || ''; ''; '
 || '  END; '
     -- 2. Warehouse compute, attributed per statement. EIGHT hours, not six: the
     -- shared action-cost view used six and therefore called a pending
     -- measurement permanently absent for two hours of every run.
 || '  BEGIN '
 || '    INSERT INTO ' || :tgt || '.COST_MEASURED '
 || '      (RUN_ID, TIER, CATEGORY, LABEL, BASIS, CREDITS, STATUS, SOURCE_VIEW, LATENCY_NOTE) '
 || '    SELECT :run, :tierv, ''WAREHOUSE_COMPUTE'', ''MEASURED'', ''BY_QUERY_ID'', '
 || '           SUM(a.CREDITS_ATTRIBUTED_COMPUTE), '
 || '           CASE WHEN COUNT(a.QUERY_ID) > 0 THEN ''LANDED'' '
 || '                WHEN DATEDIFF(hour, :t0, CURRENT_TIMESTAMP()) < 8 '
 || '                  THEN ''NOT_YET_LANDED'' '
 || '                ELSE ''NO_ATTRIBUTABLE_COMPUTE'' END, '
 || '           ''ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY'', '
 || '           ''up to 8h; excludes idle time, cloud services, serverless and AI '
 || 'tokens, and omits queries under ~100ms'' '
 || '      FROM ' || :tgt || '.BUILD_STATEMENT_LOG b '
 || '      LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY a '
 || '        ON a.QUERY_ID = b.QUERY_ID '
 || '      WHERE b.RUN_ID = :run; '
 || '  EXCEPTION WHEN OTHER THEN problems := :problems || ''WAREHOUSE_COMPUTE: '' || SQLERRM || ''; ''; '
 || '  END; '
     -- 3. Metering for the isolated warehouse, which INCLUDES idle time and
     -- therefore will not equal the figure above. Both are correct. Only
     -- meaningful when this run owns the warehouse: on a shared one the credits
     -- belong to everyone who used it, so the honest answer is a refusal.
 || '  BEGIN '
 || '    IF (:tierv IN (''LIMITED'', ''PRODUCTION'')) THEN '
 || '      INSERT INTO ' || :tgt || '.COST_MEASURED '
 || '        (RUN_ID, TIER, CATEGORY, LABEL, BASIS, CREDITS, STATUS, SOURCE_VIEW, LATENCY_NOTE) '
 || '      SELECT :run, :tierv, ''WAREHOUSE_METERING_INCL_IDLE'', ''MEASURED'', '
 || '             ''BY_ISOLATED_WAREHOUSE'', SUM(m.CREDITS_USED_COMPUTE), '
 || '             CASE WHEN COUNT(*) > 0 THEN ''LANDED'' '
 || '                  WHEN DATEDIFF(hour, :t0, CURRENT_TIMESTAMP()) < 3 THEN ''NOT_YET_LANDED'' '
 || '                  ELSE ''NO_METERED_USAGE'' END, '
 || '             ''ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY'', '
 || '             ''up to 3h; INCLUDES warehouse idle time so it exceeds the '
 || 'attributed figure; has no query-tag column, which is why this tier builds on '
 || 'its own warehouse'' '
 || '        FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY m '
 || '        WHERE UPPER(m.WAREHOUSE_NAME) = UPPER(:whv) '
 || '          AND m.END_TIME >= DATEADD(hour, -1, :t0); '
 || '      INSERT INTO ' || :tgt || '.COST_MEASURED '
 || '        (RUN_ID, TIER, CATEGORY, LABEL, BASIS, CREDITS, STATUS, SOURCE_VIEW, LATENCY_NOTE) '
 || '      SELECT :run, :tierv, ''CLOUD_SERVICES'', ''MEASURED'', '
 || '             ''BY_ISOLATED_WAREHOUSE'', SUM(m.CREDITS_USED_CLOUD_SERVICES), '
 || '             CASE WHEN COUNT(*) > 0 THEN ''LANDED'' '
 || '                  WHEN DATEDIFF(hour, :t0, CURRENT_TIMESTAMP()) < 6 THEN ''NOT_YET_LANDED'' '
 || '                  ELSE ''NO_METERED_USAGE'' END, '
 || '             ''ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY'', ''up to 6h for this column'' '
 || '        FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY m '
 || '        WHERE UPPER(m.WAREHOUSE_NAME) = UPPER(:whv) '
 || '          AND m.END_TIME >= DATEADD(hour, -1, :t0); '
 || '    ELSE '
 || '      INSERT INTO ' || :tgt || '.COST_MEASURED '
 || '        (RUN_ID, TIER, CATEGORY, LABEL, BASIS, CREDITS, STATUS, SOURCE_VIEW, LATENCY_NOTE) '
 || '      SELECT :run, :tierv, ''WAREHOUSE_METERING_INCL_IDLE'', ''MEASURED'', '
 || '             ''NOT_ATTRIBUTABLE'', NULL, ''NOT_ATTRIBUTABLE'', '
 || '             ''ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY'', '
 || '             ''This run shared a warehouse with other work. Metering is per '
 || 'warehouse per hour with no query tag, so its credits cannot be separated from '
 || 'anyone else''''s. Run at LIMITED tier for a real number.''; '
 || '    END IF; '
 || '  EXCEPTION WHEN OTHER THEN problems := :problems || ''METERING: '' || SQLERRM || ''; ''; '
 || '  END; '
     -- 4. AI tokens. The fastest category by an order of magnitude -- about five
     -- minutes -- and the only one that carries BOTH the tag and the query id, so
     -- it is usually the first real credit figure a run produces.
     --
     -- Do NOT flatten METRICS to get a token count in the same statement. Each row
     -- carries one metric entry per token direction, so flattening multiplies the
     -- row out and SUM(CREDITS) then reports roughly double what was billed. The
     -- token split is genuinely useful and belongs in its own view over the same
     -- source, not smuggled into an aggregate whose grain it changes.
 || '  BEGIN '
 || '    INSERT INTO ' || :tgt || '.COST_MEASURED '
 || '      (RUN_ID, TIER, CATEGORY, LABEL, BASIS, CREDITS, STATUS, SOURCE_VIEW, LATENCY_NOTE) '
 || '    SELECT :run, :tierv, ''AI_TOKENS'', ''MEASURED'', ''BY_TAG'', SUM(c.CREDITS), '
 || '           CASE WHEN COUNT(*) > 0 THEN ''LANDED'' '
 || '                WHEN DATEDIFF(minute, :t0, CURRENT_TIMESTAMP()) < 10 THEN ''NOT_YET_LANDED'' '
 || '                ELSE ''NO_AI_USAGE'' END, '
 || '           ''ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY'', '
 || '           ''about 5 minutes; carries the query tag and the query id, and '
 || 'reports input and output tokens separately'' '
 || '      FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY c '
 || '      WHERE c.QUERY_TAG = :tagv; '
 || '  EXCEPTION WHEN OTHER THEN problems := :problems || ''AI_TOKENS: '' || SQLERRM || ''; ''; '
 || '  END; '
     -- 5. Serverless. Account-level by service type with no tag anywhere, so this
     -- is the weakest attribution in the set and says so: anything else in the
     -- account using the same serverless feature in the same window lands here too.
     --
     -- The prefix is applied only when SERVICE_TYPE does not already carry it.
     -- METERING_HISTORY reports SERVICE_TYPE = 'SERVERLESS_TASK', so a flat
     -- ''SERVERLESS_'' || SERVICE_TYPE produced the category SERVERLESS_SERVERLESS_TASK
     -- on a customer-facing cost line.
 || '  BEGIN '
 || '    INSERT INTO ' || :tgt || '.COST_MEASURED '
 || '      (RUN_ID, TIER, CATEGORY, LABEL, BASIS, CREDITS, STATUS, SOURCE_VIEW, LATENCY_NOTE) '
 || '    SELECT :run, :tierv, '
 || '           IFF(m.SERVICE_TYPE LIKE ''SERVERLESS%'', m.SERVICE_TYPE, '
 || '               ''SERVERLESS_'' || m.SERVICE_TYPE), ''MEASURED'', '
 || '           ''BY_TIME_WINDOW'', SUM(m.CREDITS_USED), ''LANDED'', '
 || '           ''ACCOUNT_USAGE.METERING_HISTORY'', '
 || '           ''up to 3h. WEAKEST attribution here: account-level by service '
 || 'type with no query tag, so other work using the same feature in this window is '
 || 'included. Treat as an upper bound.'' '
 || '      FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY m '
 || '      WHERE m.START_TIME >= DATEADD(hour, -1, :t0) '
 || '        AND m.SERVICE_TYPE IN (''SERVERLESS_TASK'', ''DATA_QUALITY_MONITORING'', '
 || '                               ''AUTO_CLUSTERING'', ''MATERIALIZED_VIEW'', ''PIPE'') '
 || '      GROUP BY m.SERVICE_TYPE HAVING SUM(m.CREDITS_USED) > 0; '
 || '  EXCEPTION WHEN OTHER THEN problems := :problems || ''SERVERLESS: '' || SQLERRM || ''; ''; '
 || '  END; '
 || '  SELECT COUNT_IF(STATUS = ''LANDED''), COUNT_IF(STATUS = ''NOT_YET_LANDED'') '
 || '    INTO :landed, :pending FROM ' || :tgt || '.COST_MEASURED WHERE RUN_ID = :run; '
     -- Splicing :tgt into the RETURN needs care and got this wrong once. To put a
     -- build-time name INSIDE a body string literal you break OUT of the outer
     -- literal and concatenate, as below. Writing three apostrophes in a row to
     -- mean "escaped quote then splice" does not parse -- it ends the outer literal
     -- in the middle of an expression, and the error surfaces a hundred lines later
     -- as "unexpected ARRAY_APPEND" on the next statement.
 || '  RETURN ''Measured run '' || :run || '': '' || :landed '
 || '    || '' category(ies) landed, '' || :pending || '' still pending. '' '
 || '    || ''Read ' || :tgt || '.V_COST_LINES -- every row names the source it came '' '
 || '    || ''from and how long that source takes to land. Nothing pending is '' '
 || '    || ''reported as zero.'' '
 || '    || IFF(:problems = '''', '''', '' UNREADABLE: '' || :problems); '
 || 'END');

  -- Persist the adaptation so it can be audited after the fact. Without this,
  -- a model-chosen configuration is indistinguishable from the tool having
  -- invented it, which is the first question a reviewer asks.
  IF (:adapt_prompt <> '') THEN
    stmts := ARRAY_APPEND(:stmts,
      'CREATE TABLE IF NOT EXISTS ' || :tgt || '.ADAPTATION_LOG '
   || '(RUN_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(), MODEL VARCHAR, STATUS VARCHAR, '
   || 'PROMPT VARCHAR, RESPONSE VARCHAR, RUN_BY VARCHAR DEFAULT CURRENT_USER())');
    stmts := ARRAY_APPEND(:stmts,
      'DELETE FROM ' || :tgt || '.ADAPTATION_LOG');
    stmts := ARRAY_APPEND(:stmts,
      'INSERT INTO ' || :tgt || '.ADAPTATION_LOG (MODEL, STATUS, PROMPT, RESPONSE) SELECT '
   || '''' || :adapt_model || ''', ''' || REPLACE(:adapt_status, '''', '''''') || ''', '
   || '''' || REPLACE(LEFT(:adapt_prompt, 4000), '''', '''''') || ''', '
   || '''' || REPLACE(LEFT(:adapt_raw, 4000), '''', '''''') || '''');
    cost_day := :cost_day + 0.002;
    cost_detail := ARRAY_APPEND(:cost_detail,
      'Model adaptation on ' || :adapt_model || ': one AI_COMPLETE call per run, '
   || '~0.01 credits/day at one run per day. ASSUMES a prompt of a few thousand '
   || 'characters. This is a top-tier model chosen on purpose - it runs ONCE at '
   || 'plan time, not per query, so accuracy is worth far more than the saving.');
    dials := ARRAY_APPEND(:dials,
      'Revoke SNOWFLAKE.CORTEX_USER to disable model adaptation; the plan falls '
   || 'back to deterministic defaults and still builds');
  END IF;

  -- ── Where a solution registers what it leaves RUNNING ─────────────────────
  -- Created BEFORE the PLAN splice on purpose. :stmts executes in array
  -- order, so a solution appending its INSERT inside the plan snippet would run it
  -- before a CREATE TABLE placed further down this file -- which is exactly what
  -- happened: "SQL compilation error 000904" on the first pilot, because the
  -- table did not exist yet. The two VIEWS over it stay below the splice, since
  -- they must be created after the rows land to be worth reading.
  --
  -- It is also created before V_BUILD_CONTEXT, which reads it. Snowflake views are
  -- validated at CREATE time, not late-bound, so a view naming a table that does
  -- not exist yet fails the build outright.
  --
  -- A census found 17 of 21 solutions installed nothing on a schedule, so the
  -- honest monthly figure was zero for almost all of them and nothing said so.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE TABLE IF NOT EXISTS ' || :tgt || '.STANDING_WORKLOAD ('
 || 'KIND VARCHAR, OBJECT_NAME VARCHAR, CADENCE VARCHAR, '
 || 'RUNS_PER_MONTH NUMBER(38,4), SECONDS_PER_RUN NUMBER(38,4), '
 || 'WAREHOUSE_CREDITS_PER_HOUR NUMBER(38,4), '
 || 'MEASURED_INPUT VARCHAR, BASIS VARCHAR, '
 || 'INSTALLED_AT TIMESTAMP_NTZ)');

  -- Cleared each build so a re-run does not double-count the same object. The
  -- idempotence step would catch a growing table, but a run-rate that rises every
  -- time you re-run the script is the kind of wrong that gets quoted first.
  stmts := ARRAY_APPEND(:stmts,
    'DELETE FROM ' || :tgt || '.STANDING_WORKLOAD');

  -- Mode is recorded in the schema so the app can label every page. A client
  -- reading seeded numbers as their own is not a recoverable mistake.
  --
  -- ── THE PHASE RAIL ────────────────────────────────────────────────────────
  -- The app shows the three deployment phases across the top of every page with
  -- the current one filled, so a reader can see where this build sits without
  -- opening the script. The columns below are what it draws that from.
  --
  -- TIER AND MODE ARE DIFFERENT AXES AND ARE NOT MERGED. MODE says where the
  -- numbers came from (this account, or seeded fixtures) and drives the SAMPLE
  -- DATA banner. TIER says how much of the solution is standing up. A SAMPLE
  -- build can sit at any tier, and folding them into one label would put the
  -- seeded-data warning behind a phase selector, which is exactly the mistake
  -- the banner exists to prevent.
  --
  -- WHY THE MONTHLY FIGURE IS A SUBQUERY AND NOT A LITERAL. It is the product of
  -- a cadence this build set and a duration this build measured, and neither is
  -- known here -- the plan below has not run yet. Baked in as a literal it would
  -- be zero on every solution. Evaluated at query time it reports whatever the
  -- plan actually registered. This is the same arithmetic as V_RUN_RATE_HEADLINE
  -- and deliberately not a second, competing estimate.
  --
  -- STANDING_CREDITS_PER_MONTH IS WHAT PRODUCTION WOULD ACCRUE, NOT WHAT IS
  -- ACCRUING NOW. Below PRODUCTION the solutions create their dynamic tables and
  -- tasks, refresh them once to measure a real duration, and then SUSPEND them --
  -- so a DISCOVER or LIMITED build leaves nothing recurring on the account. The
  -- app must therefore label this figure by phase and not print it as a bill.
  --
  -- VOLUME_COMPONENTS IS CARRIED SEPARATELY AND MUST NOT BE RENDERED AS ZERO. A
  -- serverless meter billed per unit of data has no cadence, so the formula above
  -- yields nothing for it. A previous version summed those to 0.00 credits/month
  -- and a continuous streaming ingest read as free.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE VIEW ' || :tgt || '.V_BUILD_CONTEXT AS SELECT '
 || '''' || :mode || ''' AS MODE, ' || :w || ' AS WINDOW_DAYS, '
 || '''' || :tgt || ''' AS BUILT_IN, '
 || 'CURRENT_TIMESTAMP() AS BUILT_AT, ''Retail Merchant Agent'' AS SOLUTION, '
 || IFF(:allow_actions, 'TRUE', 'FALSE') || ' AS ACTIONS_ENABLED, '
 || IFF(:allow_sample_actions, 'TRUE', 'FALSE') || ' AS SAMPLE_ACTIONS_ENABLED, '
 || '''' || :tier || ''' AS TIER, '
 -- The enforced ceiling on a LIMITED run: a resource monitor over a warehouse
 -- this file creates. Unlike everything else on the rail this is not an estimate,
 -- which is why the app leads the LIMITED phase with it.
 || :credit_cap || ' AS CREDIT_CAP, '
 || :rate || ' AS RATE_PER_CREDIT, '
 || '(SELECT ROUND(COALESCE(SUM(IFF(RUNS_PER_MONTH IS NOT NULL, '
 || '  RUNS_PER_MONTH * SECONDS_PER_RUN * WAREHOUSE_CREDITS_PER_HOUR '
 || '  / 3600.0, 0)), 0), 4) FROM ' || :tgt || '.STANDING_WORKLOAD) '
 || '  AS STANDING_CREDITS_PER_MONTH, '
 || '(SELECT COALESCE(COUNT_IF(RUNS_PER_MONTH IS NOT NULL), 0) FROM ' || :tgt
 || '  .STANDING_WORKLOAD) AS SCHEDULED_COMPONENTS, '
 || '(SELECT COALESCE(COUNT_IF(RUNS_PER_MONTH IS NULL), 0) FROM ' || :tgt
 || '  .STANDING_WORKLOAD) AS VOLUME_COMPONENTS, '
 -- The app has to be able to NAME the line you would edit. Every setting in the
 -- script is prefixed per solution, and the host template is shared, so without
 -- this column the app could only say "re-run with ALLOW_ACTIONS = TRUE" --
 -- which is not a line that exists in any file. That reads as unexplained manual
 -- work, and it is the reason the buttons looked like they needed a terminal.
 || '''MERCHANT'' AS SETTING_PREFIX');

  -- ── Read source tables from settings ──────────────────────────────────────
  LET stores_tbl  STRING := (SELECT NULLIF($MERCHANT_STORES_TABLE::VARCHAR, ''));
  LET products_tbl STRING := (SELECT NULLIF($MERCHANT_PRODUCTS_TABLE::VARCHAR, ''));
  LET sales_tbl   STRING := (SELECT NULLIF($MERCHANT_DAILY_SALES_TABLE::VARCHAR, ''));
  LET inv_tbl     STRING := (SELECT NULLIF($MERCHANT_INVENTORY_TABLE::VARCHAR, ''));
  LET traffic_tbl STRING := (SELECT NULLIF($MERCHANT_TRAFFIC_TABLE::VARCHAR, ''));
  LET labor_tbl   STRING := (SELECT NULLIF($MERCHANT_LABOR_TABLE::VARCHAR, ''));
  LET merchant_model STRING := COALESCE(NULLIF($MERCHANT_MODEL::VARCHAR, ''), 'claude-opus-5');

  -- Surface what discovery found for each probe group
  LET sc ARRAY := COALESCE(:found:stores_candidates::ARRAY, ARRAY_CONSTRUCT());
  LET sci INT := 0;
  WHILE (:sci < LEAST(5, ARRAY_SIZE(:sc))) DO
    notes := ARRAY_APPEND(:notes, 'CANDIDATE stores table -> ' || :db || '.'
      || GET(:sc, :sci):fqn::STRING || '  (' || GET(:sc, :sci):hits::STRING || ' matching columns)');
    sci := :sci + 1;
  END WHILE;

  LET pc ARRAY := COALESCE(:found:products_candidates::ARRAY, ARRAY_CONSTRUCT());
  LET pci INT := 0;
  WHILE (:pci < LEAST(5, ARRAY_SIZE(:pc))) DO
    notes := ARRAY_APPEND(:notes, 'CANDIDATE products table -> ' || :db || '.'
      || GET(:pc, :pci):fqn::STRING || '  (' || GET(:pc, :pci):hits::STRING || ' matching columns)');
    pci := :pci + 1;
  END WHILE;

  LET slc ARRAY := COALESCE(:found:sales_candidates::ARRAY, ARRAY_CONSTRUCT());
  LET slci INT := 0;
  WHILE (:slci < LEAST(5, ARRAY_SIZE(:slc))) DO
    notes := ARRAY_APPEND(:notes, 'CANDIDATE sales table -> ' || :db || '.'
      || GET(:slc, :slci):fqn::STRING || '  (' || GET(:slc, :slci):hits::STRING || ' matching columns)');
    slci := :slci + 1;
  END WHILE;

  LET ic ARRAY := COALESCE(:found:inventory_candidates::ARRAY, ARRAY_CONSTRUCT());
  LET ici INT := 0;
  WHILE (:ici < LEAST(5, ARRAY_SIZE(:ic))) DO
    notes := ARRAY_APPEND(:notes, 'CANDIDATE inventory table -> ' || :db || '.'
      || GET(:ic, :ici):fqn::STRING || '  (' || GET(:ic, :ici):hits::STRING || ' matching columns)');
    ici := :ici + 1;
  END WHILE;

  LET tc ARRAY := COALESCE(:found:traffic_candidates::ARRAY, ARRAY_CONSTRUCT());
  LET tci INT := 0;
  WHILE (:tci < LEAST(5, ARRAY_SIZE(:tc))) DO
    notes := ARRAY_APPEND(:notes, 'CANDIDATE traffic table -> ' || :db || '.'
      || GET(:tc, :tci):fqn::STRING || '  (' || GET(:tc, :tci):hits::STRING || ' matching columns)');
    tci := :tci + 1;
  END WHILE;

  LET lc ARRAY := COALESCE(:found:labor_candidates::ARRAY, ARRAY_CONSTRUCT());
  LET lci INT := 0;
  WHILE (:lci < LEAST(5, ARRAY_SIZE(:lc))) DO
    notes := ARRAY_APPEND(:notes, 'CANDIDATE labor table -> ' || :db || '.'
      || GET(:lc, :lci):fqn::STRING || '  (' || GET(:lc, :lci):hits::STRING || ' matching columns)');
    lci := :lci + 1;
  END WHILE;

  -- ── Phase 1: no core tables set → report candidates, build nothing ──────
  LET core_set BOOLEAN := (:stores_tbl IS NOT NULL AND :sales_tbl IS NOT NULL);
  IF (NOT :core_set) THEN
    headline := 'Nothing was built yet. This run scanned your catalog for tables that look like '
             || 'retail store, product, sales, inventory, traffic and labor data. '
             || 'Name at least MERCHANT_STORES_TABLE and MERCHANT_DAILY_SALES_TABLE and run again.';
    notes := ARRAY_APPEND(:notes,
      'NOTHING WILL BE BUILT until at minimum MERCHANT_STORES_TABLE and '
   || 'MERCHANT_DAILY_SALES_TABLE are set to fully qualified table names '
   || '(DATABASE.SCHEMA.TABLE). The remaining four tables are optional but '
   || 'unlock traffic, inventory, and labor analytics.');
  ELSE
    headline := 'A Retail Merchant Agent over your store, product, sales'
             || IFF(:inv_tbl IS NOT NULL, ', inventory', '')
             || IFF(:traffic_tbl IS NOT NULL, ', traffic', '')
             || IFF(:labor_tbl IS NOT NULL, ', labor', '')
             || ' data. '
             || 'Views compute sell-through, weeks-of-supply, conversion rate, peer comparison '
             || 'and more. A Cortex Agent diagnoses cross-measure correlations and recommends '
             || 'inventory and staffing actions.';

    -- ── Cost accumulators: NUMBER(38,6) per R2 ─────────────────────────────

    -- ── 1. V_SELL_THROUGH: UNITS_SOLD / (UNITS_SOLD + UNITS_ON_HAND) per SKU/store/week
    IF (:inv_tbl IS NOT NULL) THEN
      stmts := ARRAY_APPEND(:stmts,
        'CREATE OR REPLACE VIEW ' || :tgt || '.V_SELL_THROUGH AS '
     || 'SELECT s.STORE_ID, s.SKU_ID, DATE_TRUNC(''week'', s.SALE_DATE) AS SALE_WEEK, '
     || 'SUM(s.UNITS_SOLD) AS UNITS_SOLD, '
     || 'AVG(i.UNITS_ON_HAND) AS AVG_ON_HAND, '
     || 'ROUND(DIV0(SUM(s.UNITS_SOLD), SUM(s.UNITS_SOLD) + AVG(i.UNITS_ON_HAND)), 4) AS SELL_THROUGH_RATE '
     || 'FROM ' || :sales_tbl || ' s '
     || 'JOIN ' || :inv_tbl || ' i ON s.STORE_ID = i.STORE_ID AND s.SKU_ID = i.SKU_ID '
     || 'WHERE s.SALE_DATE >= DATEADD(day, -' || :w || ', CURRENT_DATE()) '
     || 'GROUP BY 1, 2, 3 ORDER BY SELL_THROUGH_RATE DESC');
      cost_day := :cost_day + 0.02;
      cost_detail := ARRAY_APPEND(:cost_detail, 'V_SELL_THROUGH join scan ~0.02 credits/day');
    ELSE
      stmts := ARRAY_APPEND(:stmts,
        'CREATE OR REPLACE VIEW ' || :tgt || '.V_SELL_THROUGH AS '
     || 'SELECT s.STORE_ID, s.SKU_ID, DATE_TRUNC(''week'', s.SALE_DATE) AS SALE_WEEK, '
     || 'SUM(s.UNITS_SOLD) AS UNITS_SOLD, '
     || 'NULL::NUMBER AS AVG_ON_HAND, '
     || 'NULL::NUMBER(10,4) AS SELL_THROUGH_RATE '
     || 'FROM ' || :sales_tbl || ' s '
     || 'WHERE s.SALE_DATE >= DATEADD(day, -' || :w || ', CURRENT_DATE()) '
     || 'GROUP BY 1, 2, 3');
      cost_day := :cost_day + 0.01;
      cost_detail := ARRAY_APPEND(:cost_detail, 'V_SELL_THROUGH (no inventory) ~0.01 credits/day');
    END IF;

    -- ── 2. V_WEEKS_OF_SUPPLY: UNITS_ON_HAND / AVG_WEEKLY_UNITS_SOLD
    IF (:inv_tbl IS NOT NULL) THEN
      stmts := ARRAY_APPEND(:stmts,
        'CREATE OR REPLACE VIEW ' || :tgt || '.V_WEEKS_OF_SUPPLY AS '
     || 'WITH weekly_sales AS ('
     || 'SELECT STORE_ID, SKU_ID, DATE_TRUNC(''week'', SALE_DATE) AS WK, '
     || 'SUM(UNITS_SOLD) AS WK_UNITS '
     || 'FROM ' || :sales_tbl
     || ' WHERE SALE_DATE >= DATEADD(day, -' || :w || ', CURRENT_DATE()) '
     || 'GROUP BY 1, 2, 3), '
     || 'avg_wk AS ('
     || 'SELECT STORE_ID, SKU_ID, AVG(WK_UNITS) AS AVG_WEEKLY_UNITS '
     || 'FROM weekly_sales GROUP BY 1, 2) '
     || 'SELECT i.STORE_ID, i.SKU_ID, i.UNITS_ON_HAND, a.AVG_WEEKLY_UNITS, '
     || 'ROUND(DIV0(i.UNITS_ON_HAND, a.AVG_WEEKLY_UNITS), 2) AS WEEKS_OF_SUPPLY, '
     || 'CASE WHEN DIV0(i.UNITS_ON_HAND, a.AVG_WEEKLY_UNITS) < 4 THEN ''LOW'' '
     || 'WHEN DIV0(i.UNITS_ON_HAND, a.AVG_WEEKLY_UNITS) > 8 THEN ''HIGH'' '
     || 'ELSE ''HEALTHY'' END AS WOS_STATUS '
     || 'FROM ' || :inv_tbl || ' i '
     || 'JOIN avg_wk a ON i.STORE_ID = a.STORE_ID AND i.SKU_ID = a.SKU_ID '
     || 'ORDER BY WEEKS_OF_SUPPLY');
      cost_day := :cost_day + 0.02;
      cost_detail := ARRAY_APPEND(:cost_detail, 'V_WEEKS_OF_SUPPLY join scan ~0.02 credits/day');
    ELSE
      stmts := ARRAY_APPEND(:stmts,
        'CREATE OR REPLACE VIEW ' || :tgt || '.V_WEEKS_OF_SUPPLY AS '
     || 'SELECT NULL::NUMBER AS STORE_ID, NULL::VARCHAR AS SKU_ID, '
     || 'NULL::NUMBER AS UNITS_ON_HAND, NULL::NUMBER AS AVG_WEEKLY_UNITS, '
     || 'NULL::NUMBER(10,2) AS WEEKS_OF_SUPPLY, ''NO_INVENTORY'' AS WOS_STATUS '
     || 'WHERE 1=0');
      notes := ARRAY_APPEND(:notes, 'V_WEEKS_OF_SUPPLY is empty: no inventory table set.');
    END IF;

    -- ── 3. V_INVENTORY_TURNS: COGS / AVG_INVENTORY_VALUE annualized
    IF (:inv_tbl IS NOT NULL AND :products_tbl IS NOT NULL) THEN
      stmts := ARRAY_APPEND(:stmts,
        'CREATE OR REPLACE VIEW ' || :tgt || '.V_INVENTORY_TURNS AS '
     || 'WITH cogs AS ('
     || 'SELECT s.STORE_ID, s.SKU_ID, SUM(s.UNITS_SOLD * p.UNIT_COST) AS TOTAL_COGS '
     || 'FROM ' || :sales_tbl || ' s '
     || 'JOIN ' || :products_tbl || ' p ON s.SKU_ID = p.SKU_ID '
     || 'WHERE s.SALE_DATE >= DATEADD(day, -' || :w || ', CURRENT_DATE()) '
     || 'GROUP BY 1, 2), '
     || 'inv_val AS ('
     || 'SELECT i.STORE_ID, i.SKU_ID, AVG(i.UNITS_ON_HAND * p.UNIT_COST) AS AVG_INV_VALUE '
     || 'FROM ' || :inv_tbl || ' i '
     || 'JOIN ' || :products_tbl || ' p ON i.SKU_ID = p.SKU_ID '
     || 'GROUP BY 1, 2) '
     || 'SELECT c.STORE_ID, c.SKU_ID, c.TOTAL_COGS, v.AVG_INV_VALUE, '
     || 'ROUND(DIV0(c.TOTAL_COGS, v.AVG_INV_VALUE) * (365.0 / ' || :w || '), 2) AS ANNUAL_TURNS '
     || 'FROM cogs c JOIN inv_val v ON c.STORE_ID = v.STORE_ID AND c.SKU_ID = v.SKU_ID '
     || 'ORDER BY ANNUAL_TURNS DESC');
      cost_day := :cost_day + 0.03;
      cost_detail := ARRAY_APPEND(:cost_detail, 'V_INVENTORY_TURNS three-way join ~0.03 credits/day');
    ELSE
      stmts := ARRAY_APPEND(:stmts,
        'CREATE OR REPLACE VIEW ' || :tgt || '.V_INVENTORY_TURNS AS '
     || 'SELECT NULL::NUMBER AS STORE_ID, NULL::VARCHAR AS SKU_ID, '
     || 'NULL::NUMBER(12,2) AS TOTAL_COGS, NULL::NUMBER(12,2) AS AVG_INV_VALUE, '
     || 'NULL::NUMBER(10,2) AS ANNUAL_TURNS WHERE 1=0');
      notes := ARRAY_APPEND(:notes, 'V_INVENTORY_TURNS is empty: needs inventory + products tables.');
    END IF;

    -- ── 4. V_MARKDOWN_EXPOSURE: aged inventory / total on-hand
    IF (:inv_tbl IS NOT NULL) THEN
      stmts := ARRAY_APPEND(:stmts,
        'CREATE OR REPLACE VIEW ' || :tgt || '.V_MARKDOWN_EXPOSURE AS '
     || 'SELECT STORE_ID, '
     || 'SUM(UNITS_ON_HAND) AS TOTAL_ON_HAND, '
     || 'SUM(CASE WHEN DATEDIFF(day, FIRST_RECEIVED_DATE, CURRENT_DATE()) > 60 '
     || 'THEN UNITS_ON_HAND ELSE 0 END) AS AGED_ON_HAND, '
     || 'ROUND(DIV0(SUM(CASE WHEN DATEDIFF(day, FIRST_RECEIVED_DATE, CURRENT_DATE()) > 60 '
     || 'THEN UNITS_ON_HAND ELSE 0 END), SUM(UNITS_ON_HAND)), 4) AS MARKDOWN_EXPOSURE_RATE '
     || 'FROM ' || :inv_tbl
     || ' GROUP BY 1 ORDER BY MARKDOWN_EXPOSURE_RATE DESC');
      cost_day := :cost_day + 0.01;
      cost_detail := ARRAY_APPEND(:cost_detail, 'V_MARKDOWN_EXPOSURE single scan ~0.01 credits/day');
    ELSE
      stmts := ARRAY_APPEND(:stmts,
        'CREATE OR REPLACE VIEW ' || :tgt || '.V_MARKDOWN_EXPOSURE AS '
     || 'SELECT NULL::NUMBER AS STORE_ID, NULL::NUMBER AS TOTAL_ON_HAND, '
     || 'NULL::NUMBER AS AGED_ON_HAND, NULL::NUMBER(10,4) AS MARKDOWN_EXPOSURE_RATE '
     || 'WHERE 1=0');
      notes := ARRAY_APPEND(:notes, 'V_MARKDOWN_EXPOSURE is empty: no inventory table set.');
    END IF;

    -- ── 5. V_STOCKOUT_RISK: SKU/store combos with 0 on-hand / total active combos
    IF (:inv_tbl IS NOT NULL) THEN
      stmts := ARRAY_APPEND(:stmts,
        'CREATE OR REPLACE VIEW ' || :tgt || '.V_STOCKOUT_RISK AS '
     || 'SELECT STORE_ID, '
     || 'COUNT(*) AS TOTAL_COMBOS, '
     || 'SUM(CASE WHEN UNITS_ON_HAND = 0 THEN 1 ELSE 0 END) AS STOCKOUT_COMBOS, '
     || 'ROUND(DIV0(SUM(CASE WHEN UNITS_ON_HAND = 0 THEN 1 ELSE 0 END), COUNT(*)), 4) '
     || 'AS STOCKOUT_RATE '
     || 'FROM ' || :inv_tbl
     || ' GROUP BY 1 ORDER BY STOCKOUT_RATE DESC');
      cost_day := :cost_day + 0.01;
      cost_detail := ARRAY_APPEND(:cost_detail, 'V_STOCKOUT_RISK single scan ~0.01 credits/day');
    ELSE
      stmts := ARRAY_APPEND(:stmts,
        'CREATE OR REPLACE VIEW ' || :tgt || '.V_STOCKOUT_RISK AS '
     || 'SELECT NULL::NUMBER AS STORE_ID, NULL::NUMBER AS TOTAL_COMBOS, '
     || 'NULL::NUMBER AS STOCKOUT_COMBOS, NULL::NUMBER(10,4) AS STOCKOUT_RATE WHERE 1=0');
      notes := ARRAY_APPEND(:notes, 'V_STOCKOUT_RISK is empty: no inventory table set.');
    END IF;

    -- ── 6. V_CONVERSION_RATE: TRANSACTIONS / TRAFFIC per store/day
    IF (:traffic_tbl IS NOT NULL) THEN
      stmts := ARRAY_APPEND(:stmts,
        'CREATE OR REPLACE VIEW ' || :tgt || '.V_CONVERSION_RATE AS '
     || 'WITH daily_traffic AS ('
     || 'SELECT STORE_ID, TRAFFIC_DATE, SUM(EXIT_COUNT) AS DAILY_TRAFFIC '
     || 'FROM ' || :traffic_tbl || ' GROUP BY 1, 2), '
     || 'daily_txn AS ('
     || 'SELECT STORE_ID, SALE_DATE, SUM(TRANSACTION_COUNT) AS DAILY_TRANSACTIONS '
     || 'FROM ' || :sales_tbl || ' GROUP BY 1, 2) '
     || 'SELECT t.STORE_ID, t.TRAFFIC_DATE AS REPORT_DATE, '
     || 't.DAILY_TRAFFIC, COALESCE(x.DAILY_TRANSACTIONS, 0) AS DAILY_TRANSACTIONS, '
     || 'ROUND(DIV0(COALESCE(x.DAILY_TRANSACTIONS, 0), t.DAILY_TRAFFIC), 4) AS CONVERSION_RATE '
     || 'FROM daily_traffic t '
     || 'LEFT JOIN daily_txn x ON t.STORE_ID = x.STORE_ID AND t.TRAFFIC_DATE = x.SALE_DATE '
     || 'ORDER BY CONVERSION_RATE DESC');
      cost_day := :cost_day + 0.02;
      cost_detail := ARRAY_APPEND(:cost_detail, 'V_CONVERSION_RATE join scan ~0.02 credits/day');
    ELSE
      stmts := ARRAY_APPEND(:stmts,
        'CREATE OR REPLACE VIEW ' || :tgt || '.V_CONVERSION_RATE AS '
     || 'SELECT NULL::NUMBER AS STORE_ID, NULL::DATE AS REPORT_DATE, '
     || 'NULL::NUMBER AS DAILY_TRAFFIC, NULL::NUMBER AS DAILY_TRANSACTIONS, '
     || 'NULL::NUMBER(10,4) AS CONVERSION_RATE WHERE 1=0');
      notes := ARRAY_APPEND(:notes, 'V_CONVERSION_RATE is empty: no traffic table set.');
    END IF;

    -- ── 7. V_UNITS_PER_TRANSACTION
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE VIEW ' || :tgt || '.V_UNITS_PER_TRANSACTION AS '
   || 'SELECT STORE_ID, SALE_DATE, '
   || 'SUM(UNITS_SOLD) AS TOTAL_UNITS, '
   || 'SUM(TRANSACTION_COUNT) AS TOTAL_TRANSACTIONS, '
   || 'ROUND(DIV0(SUM(UNITS_SOLD), SUM(TRANSACTION_COUNT)), 2) AS UPT '
   || 'FROM ' || :sales_tbl
   || ' WHERE SALE_DATE >= DATEADD(day, -' || :w || ', CURRENT_DATE()) '
   || 'GROUP BY 1, 2 ORDER BY UPT DESC');
    cost_day := :cost_day + 0.01;
    cost_detail := ARRAY_APPEND(:cost_detail, 'V_UNITS_PER_TRANSACTION single scan ~0.01 credits/day');

    -- ── 8. V_DOLLARS_PER_HOUR: NET_SALES / ASSOCIATE_HOURS per store/day
    IF (:labor_tbl IS NOT NULL) THEN
      stmts := ARRAY_APPEND(:stmts,
        'CREATE OR REPLACE VIEW ' || :tgt || '.V_DOLLARS_PER_HOUR AS '
     || 'WITH daily_sales_agg AS ('
     || 'SELECT STORE_ID, SALE_DATE, SUM(NET_SALES_AMT) AS DAILY_NET_SALES '
     || 'FROM ' || :sales_tbl || ' GROUP BY 1, 2), '
     || 'daily_labor AS ('
     || 'SELECT STORE_ID, WORK_DATE, SUM(HOURS_WORKED) AS TOTAL_HOURS '
     || 'FROM ' || :labor_tbl || ' GROUP BY 1, 2) '
     || 'SELECT s.STORE_ID, s.SALE_DATE AS REPORT_DATE, '
     || 's.DAILY_NET_SALES, l.TOTAL_HOURS, '
     || 'ROUND(DIV0(s.DAILY_NET_SALES, l.TOTAL_HOURS), 2) AS DOLLARS_PER_HOUR '
     || 'FROM daily_sales_agg s '
     || 'JOIN daily_labor l ON s.STORE_ID = l.STORE_ID AND s.SALE_DATE = l.WORK_DATE '
     || 'ORDER BY DOLLARS_PER_HOUR DESC');
      cost_day := :cost_day + 0.02;
      cost_detail := ARRAY_APPEND(:cost_detail, 'V_DOLLARS_PER_HOUR join scan ~0.02 credits/day');
    ELSE
      stmts := ARRAY_APPEND(:stmts,
        'CREATE OR REPLACE VIEW ' || :tgt || '.V_DOLLARS_PER_HOUR AS '
     || 'SELECT NULL::NUMBER AS STORE_ID, NULL::DATE AS REPORT_DATE, '
     || 'NULL::NUMBER(12,2) AS DAILY_NET_SALES, NULL::NUMBER(6,1) AS TOTAL_HOURS, '
     || 'NULL::NUMBER(10,2) AS DOLLARS_PER_HOUR WHERE 1=0');
      notes := ARRAY_APPEND(:notes, 'V_DOLLARS_PER_HOUR is empty: no labor table set.');
    END IF;

    -- ── 9. V_STAFFING_EFFICIENCY: conversion vs associate-hours/traffic ratio
    IF (:labor_tbl IS NOT NULL AND :traffic_tbl IS NOT NULL) THEN
      stmts := ARRAY_APPEND(:stmts,
        'CREATE OR REPLACE VIEW ' || :tgt || '.V_STAFFING_EFFICIENCY AS '
     || 'WITH daily_traffic AS ('
     || 'SELECT STORE_ID, TRAFFIC_DATE, SUM(EXIT_COUNT) AS DAILY_TRAFFIC '
     || 'FROM ' || :traffic_tbl || ' GROUP BY 1, 2), '
     || 'daily_labor AS ('
     || 'SELECT STORE_ID, WORK_DATE, SUM(HOURS_WORKED) AS TOTAL_HOURS '
     || 'FROM ' || :labor_tbl || ' GROUP BY 1, 2), '
     || 'daily_txn AS ('
     || 'SELECT STORE_ID, SALE_DATE, SUM(TRANSACTION_COUNT) AS DAILY_TXN, '
     || 'SUM(NET_SALES_AMT) AS DAILY_SALES '
     || 'FROM ' || :sales_tbl || ' GROUP BY 1, 2) '
     || 'SELECT t.STORE_ID, t.TRAFFIC_DATE AS REPORT_DATE, '
     || 't.DAILY_TRAFFIC, l.TOTAL_HOURS, '
     || 'ROUND(DIV0(l.TOTAL_HOURS, t.DAILY_TRAFFIC) * 1000, 2) AS HOURS_PER_K_TRAFFIC, '
     || 'COALESCE(x.DAILY_TXN, 0) AS DAILY_TRANSACTIONS, '
     || 'ROUND(DIV0(COALESCE(x.DAILY_TXN, 0), t.DAILY_TRAFFIC), 4) AS CONVERSION_RATE, '
     || 'ROUND(DIV0(COALESCE(x.DAILY_SALES, 0), l.TOTAL_HOURS), 2) AS SALES_PER_HOUR, '
     || 'ROUND(DIV0(COALESCE(x.DAILY_TXN, 0), l.TOTAL_HOURS), 2) AS TXN_PER_HOUR '
     || 'FROM daily_traffic t '
     || 'JOIN daily_labor l ON t.STORE_ID = l.STORE_ID AND t.TRAFFIC_DATE = l.WORK_DATE '
     || 'LEFT JOIN daily_txn x ON t.STORE_ID = x.STORE_ID AND t.TRAFFIC_DATE = x.SALE_DATE '
     || 'ORDER BY HOURS_PER_K_TRAFFIC');
      cost_day := :cost_day + 0.03;
      cost_detail := ARRAY_APPEND(:cost_detail, 'V_STAFFING_EFFICIENCY three-way join ~0.03 credits/day');
    ELSE
      stmts := ARRAY_APPEND(:stmts,
        'CREATE OR REPLACE VIEW ' || :tgt || '.V_STAFFING_EFFICIENCY AS '
     || 'SELECT NULL::NUMBER AS STORE_ID, NULL::DATE AS REPORT_DATE, '
     || 'NULL::NUMBER AS DAILY_TRAFFIC, NULL::NUMBER(6,1) AS TOTAL_HOURS, '
     || 'NULL::NUMBER(10,2) AS HOURS_PER_K_TRAFFIC, NULL::NUMBER AS DAILY_TRANSACTIONS, '
     || 'NULL::NUMBER(10,4) AS CONVERSION_RATE, NULL::NUMBER(10,2) AS SALES_PER_HOUR, '
     || 'NULL::NUMBER(10,2) AS TXN_PER_HOUR WHERE 1=0');
      notes := ARRAY_APPEND(:notes, 'V_STAFFING_EFFICIENCY is empty: needs labor + traffic tables.');
    END IF;

    -- ── 10. V_PEER_COMPARISON: rank within SQ_FT_BUCKET + REGION group
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE VIEW ' || :tgt || '.V_PEER_COMPARISON AS '
   || 'WITH store_perf AS ('
   || 'SELECT s.STORE_ID, s.STORE_NAME, s.STORE_SQ_FT, s.REGION, '
   || 'CASE WHEN s.STORE_SQ_FT < 10000 THEN ''SMALL'' '
   || 'WHEN s.STORE_SQ_FT < 25000 THEN ''MEDIUM'' '
   || 'ELSE ''LARGE'' END AS SQ_FT_BUCKET, '
   || 'SUM(d.NET_SALES_AMT) AS TOTAL_NET_SALES, '
   || 'SUM(d.UNITS_SOLD) AS TOTAL_UNITS, '
   || 'SUM(d.TRANSACTION_COUNT) AS TOTAL_TRANSACTIONS, '
   || 'ROUND(DIV0(SUM(d.NET_SALES_AMT), s.STORE_SQ_FT), 2) AS SALES_PER_SQFT '
   || 'FROM ' || :stores_tbl || ' s '
   || 'JOIN ' || :sales_tbl || ' d ON s.STORE_ID = d.STORE_ID '
   || 'WHERE d.SALE_DATE >= DATEADD(day, -' || :w || ', CURRENT_DATE()) '
   || 'GROUP BY 1, 2, 3, 4) '
   || 'SELECT *, '
   || 'RANK() OVER (PARTITION BY SQ_FT_BUCKET, REGION ORDER BY SALES_PER_SQFT DESC) AS PEER_RANK, '
   || 'COUNT(*) OVER (PARTITION BY SQ_FT_BUCKET, REGION) AS PEER_GROUP_SIZE '
   || 'FROM store_perf ORDER BY SQ_FT_BUCKET, REGION, PEER_RANK');
    cost_day := :cost_day + 0.02;
    cost_detail := ARRAY_APPEND(:cost_detail, 'V_PEER_COMPARISON join + window ~0.02 credits/day');

    -- ── V_MERCHANT_SUMMARY: rollup dashboard view
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE VIEW ' || :tgt || '.V_MERCHANT_SUMMARY AS '
   || 'SELECT s.STORE_ID, s.STORE_NAME, s.REGION, s.STORE_SQ_FT, '
   || 'SUM(d.NET_SALES_AMT) AS TOTAL_NET_SALES, '
   || 'SUM(d.UNITS_SOLD) AS TOTAL_UNITS, '
   || 'SUM(d.TRANSACTION_COUNT) AS TOTAL_TRANSACTIONS, '
   || 'ROUND(DIV0(SUM(d.UNITS_SOLD), SUM(d.TRANSACTION_COUNT)), 2) AS AVG_UPT, '
   || 'ROUND(DIV0(SUM(d.NET_SALES_AMT), s.STORE_SQ_FT), 2) AS SALES_PER_SQFT '
   || 'FROM ' || :stores_tbl || ' s '
   || 'JOIN ' || :sales_tbl || ' d ON s.STORE_ID = d.STORE_ID '
   || 'WHERE d.SALE_DATE >= DATEADD(day, -' || :w || ', CURRENT_DATE()) '
   || 'GROUP BY 1, 2, 3, 4 ORDER BY TOTAL_NET_SALES DESC');
    cost_day := :cost_day + 0.02;
    cost_detail := ARRAY_APPEND(:cost_detail, 'V_MERCHANT_SUMMARY join scan ~0.02 credits/day');

    -- ── Adaptation log table ──────────────────────────────────────────────────
    stmts := ARRAY_APPEND(:stmts,
      'CREATE TABLE IF NOT EXISTS ' || :tgt || '.ADAPTATION_LOG ('
   || 'LOG_ID NUMBER AUTOINCREMENT, '
   || 'LOGGED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(), '
   || 'OPERATION VARCHAR, '
   || 'PROMPT_SENT VARCHAR, '
   || 'RAW_REPLY VARCHAR, '
   || 'PARSED_DECISION VARIANT, '
   || 'FALLBACK_USED BOOLEAN DEFAULT FALSE, '
   || 'MODEL_USED VARCHAR)');
    -- Clear on rebuild so the dedup check (adaptation_log_has_no_repeated_calls)
    -- does not accumulate identical entries across runs.
    stmts := ARRAY_APPEND(:stmts,
      'DELETE FROM ' || :tgt || '.ADAPTATION_LOG');

    -- ── Semantic view over merchant analytics ─────────────────────────────────
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE SEMANTIC VIEW ' || :tgt || '.MERCHANT_SEMANTIC_VIEW '
   || 'TABLES (summary AS ' || :tgt || '.V_MERCHANT_SUMMARY '
   || 'PRIMARY KEY (STORE_ID) '
   || 'WITH SYNONYMS = (''store'', ''retail'', ''merchant'', ''location'') '
   || 'COMMENT = ''One row per store with aggregated retail performance metrics.'') '
   || 'FACTS (summary.total_net_sales AS TOTAL_NET_SALES, '
   || 'summary.total_units AS TOTAL_UNITS, '
   || 'summary.total_transactions AS TOTAL_TRANSACTIONS, '
   || 'summary.avg_upt AS AVG_UPT, '
   || 'summary.sales_per_sqft AS SALES_PER_SQFT) '
   || 'DIMENSIONS (summary.store_id AS STORE_ID, '
   || 'summary.store_name AS STORE_NAME, '
   || 'summary.region AS REGION, '
   || 'summary.store_sq_ft AS STORE_SQ_FT) '
   || 'METRICS (summary.all_sales AS SUM(summary.total_net_sales), '
   || 'summary.all_units AS SUM(summary.total_units), '
   || 'summary.all_transactions AS SUM(summary.total_transactions)) '
   || 'COMMENT = ''Retail merchant analytics. Ask about store performance, sales, '
   || 'units per transaction, and sales per square foot.''');
    cost_once := :cost_once + 0.01;
    cost_detail := ARRAY_APPEND(:cost_detail, 'Semantic view creation ~0.01 credits one-time');

    -- ── Merchant Agent procedure (Python) ─────────────────────────────────────
    IF (:sig:cortex::STRING = 'AVAILABLE') THEN
      LET py_agent STRING := '

import json
def run(session, question, model):
    views = {
        "V_SELL_THROUGH": "sell-through rate by SKU/store/week",
        "V_WEEKS_OF_SUPPLY": "weeks of supply with LOW/HEALTHY/HIGH status",
        "V_INVENTORY_TURNS": "annualized inventory turns by SKU/store",
        "V_MARKDOWN_EXPOSURE": "aged inventory exposure rate by store",
        "V_STOCKOUT_RISK": "stockout rate by store",
        "V_CONVERSION_RATE": "traffic-to-transaction conversion by store/day",
        "V_UNITS_PER_TRANSACTION": "UPT by store/day",
        "V_DOLLARS_PER_HOUR": "sales per associate-hour by store/day",
        "V_STAFFING_EFFICIENCY": "staffing ratio vs conversion/sales metrics",
        "V_PEER_COMPARISON": "store ranking within size+region peer group",
        "V_MERCHANT_SUMMARY": "overall store performance rollup"
    }
    view_desc = chr(10).join(f"  {k}: {v}" for k, v in views.items())
    samples = {}
    for vname in views:
        try:
            rows = session.sql(f"SELECT * FROM __TGT__.{vname} LIMIT 3").collect()
            if rows:
                samples[vname] = [r.as_dict() for r in rows]
        except:
            pass
    context = json.dumps({k: [{kk: str(vv) for kk, vv in r.items()} for r in v]
                          for k, v in samples.items()}, indent=2)
    prompt = (
        "You are a retail merchant intelligence agent. You have access to these views:"
        + chr(10) + view_desc + chr(10)
        + "Sample data from available views:" + chr(10) + context[:8000] + chr(10)
        + "Question: " + question + chr(10)
        + "Analyze the data across multiple views. When diagnosing a problem, "
        + "correlate metrics (e.g. if conversion is low, check staffing and traffic). "
        + "Always recommend specific actions. Return JSON with keys: "
        + "analysis (2-3 sentences referencing specific measures and values), "
        + "views_used (list of view names consulted), "
        + "recommendation (one actionable sentence), "
        + "confidence (HIGH, MEDIUM, LOW).")
    fallback = False
    try:
        reply = session.sql(
            "SELECT SNOWFLAKE.CORTEX.AI_COMPLETE(?, ?)",
            params=[model, prompt]).collect()[0][0]
        parsed = json.loads(reply)
    except Exception:
        fallback = True
        parsed = {"analysis": "Model unavailable; deterministic fallback. "
                  "Review the merchant views directly for store performance data.",
                  "views_used": list(samples.keys()),
                  "recommendation": "Check V_MERCHANT_SUMMARY and V_PEER_COMPARISON manually.",
                  "confidence": "LOW", "fallback": True}
        reply = json.dumps(parsed)
    session.sql(
        "INSERT INTO __TGT__.ADAPTATION_LOG (OPERATION, PROMPT_SENT, RAW_REPLY, "
        "PARSED_DECISION, FALLBACK_USED, MODEL_USED) "
        "SELECT ?, ?, ?, TRY_PARSE_JSON(?), ?, ?",
        params=["MERCHANT_AGENT", prompt[:4000], reply[:4000], reply[:4000],
                fallback, model]).collect()
    return reply
';
      py_agent := REPLACE(:py_agent, '__TGT__', :tgt);
      IF (POSITION(CHR(39) IN :py_agent) > 0) THEN
        notes := ARRAY_APPEND(:notes, 'AGENT SKIPPED: a single quote appeared in its '
          || 'Python body after substitution.');
      ELSE
        stmts := ARRAY_APPEND(:stmts,
          'CREATE OR REPLACE PROCEDURE ' || :tgt || '.MERCHANT_AGENT('
       || 'QUESTION STRING, P_MODEL STRING) RETURNS VARCHAR LANGUAGE PYTHON '
       || 'RUNTIME_VERSION = ''3.11'' PACKAGES = (''snowflake-snowpark-python'') '
       || 'HANDLER = ''run'' COMMENT = ''Retail merchant intelligence agent. Diagnoses '
       || 'cross-measure correlations, identifies staffing inefficiencies, and recommends '
       || 'inventory actions by reasoning across ten merchant views.'' '
       || 'EXECUTE AS CALLER AS '
       || CHR(39) || :py_agent || CHR(39));

        cost_once := :cost_once + 0.01;
        cost_detail := ARRAY_APPEND(:cost_detail, 'MERCHANT_AGENT procedure creation ~0.01 credits one-time');
        dials := ARRAY_APPEND(:dials, 'Each MERCHANT_AGENT call costs ~0.003 credits (one AI_COMPLETE). Frequency is user-driven.');
      END IF;
    ELSE
      notes := ARRAY_APPEND(:notes,
        'CORTEX NOT AVAILABLE to this role. MERCHANT_AGENT procedure not created. '
     || 'Grant SNOWFLAKE.CORTEX_USER to enable AI-powered merchant intelligence.');
    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- STANDING WORKLOAD — TASK_MERCHANT_DAILY_ROLLUP
    -- ══════════════════════════════════════════════════════════════════════════

    -- ── Warehouse credit rate (READ, not assumed) ───────────────────────────
    LET wh_size    STRING := 'UNKNOWN';
    LET wh_cph     NUMBER(38,2) := 1.0;
    LET wh_rate_ok BOOLEAN := FALSE;
    BEGIN
      EXECUTE IMMEDIATE 'SHOW WAREHOUSES LIKE ''' || :wh || '''';
      wh_size := (SELECT UPPER(COALESCE(MAX("size"), 'UNKNOWN'))
                  FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
      wh_cph := CASE :wh_size
          WHEN 'X-SMALL'  THEN 1   WHEN 'XSMALL'    THEN 1
          WHEN 'SMALL'    THEN 2
          WHEN 'MEDIUM'   THEN 4
          WHEN 'LARGE'    THEN 8
          WHEN 'X-LARGE'  THEN 16  WHEN 'XLARGE'    THEN 16
          WHEN '2X-LARGE' THEN 32  WHEN 'XXLARGE'   THEN 32
          WHEN '3X-LARGE' THEN 64  WHEN 'XXXLARGE'  THEN 64
          WHEN '4X-LARGE' THEN 128 WHEN 'XXXXLARGE' THEN 128
          ELSE 1 END;
      wh_rate_ok := (:wh_cph > 1 OR :wh_size IN ('X-SMALL', 'XSMALL'));
    EXCEPTION WHEN OTHER THEN
      wh_size := 'UNREADABLE'; wh_cph := 1.0; wh_rate_ok := FALSE;
    END;

    -- ── Create the rollup target table ──────────────────────────────────────
    stmts := ARRAY_APPEND(:stmts,
      'CREATE TABLE IF NOT EXISTS ' || :tgt || '.MERCHANT_DAILY_ROLLUP '
   || '(ROLLUP_DATE DATE, STORE_ID NUMBER, TOTAL_NET_SALES NUMBER(12,2), '
   || 'TOTAL_UNITS NUMBER, TOTAL_TRANSACTIONS NUMBER, '
   || 'AVG_UPT NUMBER(10,2), ROLLED_UP_AT TIMESTAMP_NTZ) '
   || 'COMMENT = ''Daily rollup of merchant performance. Written by '
   || 'TASK_MERCHANT_DAILY_ROLLUP.''');

    -- ── Create the rollup procedure ─────────────────────────────────────────
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE PROCEDURE ' || :tgt || '.ROLLUP_MERCHANT_DAILY() '
   || 'RETURNS VARCHAR LANGUAGE SQL AS '
   || 'BEGIN '
   || '  DELETE FROM ' || :tgt || '.MERCHANT_DAILY_ROLLUP '
   || '  WHERE ROLLUP_DATE = CURRENT_DATE() - 1; '
   || '  INSERT INTO ' || :tgt || '.MERCHANT_DAILY_ROLLUP '
   || '  (ROLLUP_DATE, STORE_ID, TOTAL_NET_SALES, TOTAL_UNITS, '
   || '   TOTAL_TRANSACTIONS, AVG_UPT, ROLLED_UP_AT) '
   || '  SELECT CURRENT_DATE() - 1, STORE_ID, '
   || '    SUM(NET_SALES_AMT), SUM(UNITS_SOLD), SUM(TRANSACTION_COUNT), '
   || '    ROUND(DIV0(SUM(UNITS_SOLD), SUM(TRANSACTION_COUNT)), 2), '
   || '    CURRENT_TIMESTAMP() '
   || '  FROM ' || :sales_tbl
   || '  WHERE SALE_DATE = CURRENT_DATE() - 1 '
   || '  GROUP BY STORE_ID; '
   || '  RETURN ''Rolled up '' || SQLROWCOUNT || '' store(s) for '' || (CURRENT_DATE() - 1)::VARCHAR; '
   || 'END');

    -- ── Call the procedure now to measure it ─────────────────────────────────
    stmts := ARRAY_APPEND(:stmts, 'CALL ' || :tgt || '.ROLLUP_MERCHANT_DAILY()');

    -- ── Register task in ATTACHED_OBJECT_REGISTRY ───────────────────────────
    LET task_fqn STRING := :tgt || '.TASK_MERCHANT_DAILY_ROLLUP';
    stmts := ARRAY_APPEND(:stmts,
      'DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ''TASK''');
    stmts := ARRAY_APPEND(:stmts,
      'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY (TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) '
   || 'SELECT ''' || :task_fqn || ''', ''TASK_MERCHANT_DAILY_ROLLUP'', '
   || '''USING CRON 0 6 * * * UTC'', ''TASK''');

    -- ── Actually CREATE the task ────────────────────────────────────────────
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE TASK ' || :task_fqn
   || ' WAREHOUSE = ' || :wh
   || ' SCHEDULE = ''USING CRON 0 6 * * * UTC'''
   || ' COMMENT = ''Daily merchant performance rollup by store.'''
   || ' AS CALL ' || :tgt || '.ROLLUP_MERCHANT_DAILY()');

    -- ── Tier gate: only RESUME in PRODUCTION ────────────────────────────────
    IF (:tier = 'PRODUCTION') THEN
      stmts := ARRAY_APPEND(:stmts, 'ALTER TASK ' || :task_fqn || ' RESUME');
      notes := ARRAY_APPEND(:notes,
        'TASK_MERCHANT_DAILY_ROLLUP is RESUMED and will run daily at 06:00 UTC.');
    ELSE
      stmts := ARRAY_APPEND(:stmts, 'ALTER TASK ' || :task_fqn || ' SUSPEND');
      notes := ARRAY_APPEND(:notes,
        'TIER GATE: this is a ' || :tier || ' build, so TASK_MERCHANT_DAILY_ROLLUP was '
     || 'created and SUSPENDED. The procedure was called to measure a real duration, '
     || 'so the cost projection is grounded. RESUME it to start the daily schedule.');
    END IF;

    -- ── STANDING_WORKLOAD: project the monthly cost of the daily task ───────
    --   The procedure was called above (CALL ROLLUP_MERCHANT_DAILY) so its
    --   duration is in QUERY_HISTORY_BY_SESSION. We SELECT from that to get a
    --   measured SECONDS_PER_RUN rather than a hardcoded guess.
    LET task_sec_default NUMBER(10,2) := 5.0;
    stmts := ARRAY_APPEND(:stmts,
      'INSERT INTO ' || :tgt || '.STANDING_WORKLOAD '
   || '(KIND, OBJECT_NAME, CADENCE, RUNS_PER_MONTH, SECONDS_PER_RUN, '
   || ' WAREHOUSE_CREDITS_PER_HOUR, MEASURED_INPUT, BASIS, INSTALLED_AT) '
   || 'SELECT ''TASK'', ''TASK_MERCHANT_DAILY_ROLLUP'', '
   || '''daily at 06:00 UTC'', '
   || '30, '
   || 'COALESCE(h.elapsed_sec, ' || :task_sec_default || '), '
   || :wh_cph || ', '
   || 'CASE WHEN h.elapsed_sec IS NOT NULL '
   ||   'THEN ''TOTAL_ELAPSED_TIME measured from CALL ROLLUP_MERCHANT_DAILY() '
   ||   'in this build session ('' || h.elapsed_sec || ''s)'' '
   ||   'ELSE ''no call history landed yet; using the '
   ||   :task_sec_default || 's default stated in the plan'' END, '
   || '''30 runs/month (daily at 06:00 UTC) at '' '
   || '|| COALESCE(h.elapsed_sec, ' || :task_sec_default || ') '
   || '|| ''s per run, at ' || :wh_cph || ' credits/hour on ' || :wh
   || ' (' || :wh_size
   || IFF(:wh_rate_ok, '', ' -- unreadable, so 1 credit/hour is assumed and '
   || 'this figure is a LOWER bound')
   || '). '
   || IFF(:tier = 'PRODUCTION',
          'The task is RESUMED, so this is what it will bill.',
          'This is a ' || :tier || ' build: the procedure was called to measure it '
       || 'and the task was then SUSPENDED, so this is what RESUMING it would cost, '
       || 'not what is accruing.')
   || ' PROJECTED: the cadence and the rate are facts, next month''''s row volume '
   || 'is not this month''''s.'', '
   || 'CURRENT_TIMESTAMP() '
   || 'FROM (SELECT ROUND(MAX(TOTAL_ELAPSED_TIME) / 1000, 4) AS elapsed_sec '
   ||   'FROM TABLE(' || :db || '.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION()) '
   ||   'WHERE QUERY_TEXT ILIKE ''%ROLLUP_MERCHANT_DAILY%'') h');

  END IF;  -- end Phase 2
  --           adding to :cost_day / :cost_once / :cost_detail / :dials

  -- ── The estimate, recorded so it can be graded later ──────────────────────
  -- Written to its OWN table, separate from COST_MEASURED. That separation is the
  -- mechanism, not a stylistic choice: two tables and one view with a mandatory
  -- LABEL make "never sum a measurement with a projection" a property of the
  -- schema rather than a rule someone has to remember. There is no column
  -- anywhere that contains both kinds of number.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE TABLE IF NOT EXISTS ' || :tgt || '.COST_PROJECTED '
 || '(RUN_ID VARCHAR, TIER VARCHAR, CATEGORY VARCHAR, LABEL VARCHAR, BASIS VARCHAR, '
 || 'CREDITS NUMBER(38,9), HORIZON VARCHAR, DERIVATION VARCHAR, '
 || 'PROJECTED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP())');
  stmts := ARRAY_APPEND(:stmts, 'DELETE FROM ' || :tgt || '.COST_PROJECTED '
                             || 'WHERE RUN_ID = ''' || :run_id || '''');
  stmts := ARRAY_APPEND(:stmts,
    'INSERT INTO ' || :tgt || '.COST_PROJECTED '
 || '(RUN_ID, TIER, CATEGORY, LABEL, BASIS, CREDITS, HORIZON, DERIVATION) '
 || 'SELECT ''' || :run_id || ''', ''' || :tier || ''', ''STEADY_STATE'', ''PROJECTED'', '
 || '''ARITHMETIC'', ' || :cost_day || ', ''per day'', '
 || '''Sum of this plan''''s own itemised cost lines. Arithmetic, not observed.'' '
 || 'UNION ALL SELECT ''' || :run_id || ''', ''' || :tier || ''', ''ONE_TIME_BUILD'', '
 || '''PROJECTED'', ''ARITHMETIC'', ' || :cost_once || ', ''once'', '
 || '''Sum of this plan''''s own one-time cost lines. Arithmetic, not observed.''');

  -- Everything with a credit figure on it, measured and projected side by side and
  -- never added together. LABEL is not nullable in practice because both feeding
  -- tables write it as a literal.
  --
  -- Scoped to the NEWEST run. The tables underneath are ledgers and keep every run,
  -- which is what makes MEASURE() re-callable and WI5 telemetry possible -- but a
  -- reader asking "what did this cost" means the run they just did, and an unscoped
  -- view showed two of every category with the same category reading
  -- NOT_YET_LANDED on one row and LANDED on the next. Correct, and it looks like a
  -- contradiction. V_COST_HISTORY keeps the unscoped view for anyone who wants it.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE VIEW ' || :tgt || '.V_COST_HISTORY AS '
 || 'SELECT RUN_ID, TIER, CATEGORY, LABEL, BASIS, CREDITS, '
 || :rate || ' AS RATE_PER_CREDIT, ROUND(CREDITS * ' || :rate || ', 4) AS DOLLARS, '
 || 'STATUS, SOURCE_VIEW AS SOURCE, LATENCY_NOTE AS BASIS_NOTE, '
 || 'ROWS_PROCESSED, WALL_CLOCK_MS, MEASURED_AT AS AS_OF '
 || 'FROM ' || :tgt || '.COST_MEASURED '
 || 'UNION ALL '
 || 'SELECT RUN_ID, TIER, CATEGORY, LABEL, BASIS, CREDITS, '
 || :rate || ', ROUND(CREDITS * ' || :rate || ', 4), '
 || '''ESTIMATE'', ''this plan'', DERIVATION || '' Horizon: '' || HORIZON, '
 || 'NULL, NULL, PROJECTED_AT '
 || 'FROM ' || :tgt || '.COST_PROJECTED');
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE VIEW ' || :tgt || '.V_COST_LINES AS '
 || 'SELECT * FROM ' || :tgt || '.V_COST_HISTORY WHERE RUN_ID = ('
 || 'SELECT RUN_ID FROM ' || :tgt || '.RUN_LEDGER ORDER BY STARTED_AT DESC LIMIT 1)');

  -- Subtotals BY LABEL. There is deliberately no grand total: the one number a
  -- reader most wants is the one that cannot honestly exist.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE VIEW ' || :tgt || '.V_COST_SUMMARY AS '
 || 'SELECT LABEL, COUNT(*) AS LINES, '
 || 'SUM(CASE WHEN STATUS IN (''LANDED'', ''ESTIMATE'') THEN CREDITS END) AS CREDITS, '
 || 'COUNT_IF(STATUS = ''NOT_YET_LANDED'') AS STILL_PENDING, '
 || 'COUNT_IF(STATUS = ''NOT_ATTRIBUTABLE'') AS NOT_ATTRIBUTABLE, '
 || 'MAX(AS_OF) AS AS_OF, '
 || 'CASE LABEL WHEN ''MEASURED'' THEN ''Observed from Snowflake''''s own metering. '
 || 'Pending categories are excluded from this figure rather than counted as zero.'' '
 || 'ELSE ''Arithmetic from the plan. Not observed. Do not add this to the MEASURED row.'' '
 || 'END AS WHAT_THIS_IS '
 || 'FROM ' || :tgt || '.V_COST_LINES GROUP BY LABEL');

  -- The extrapolation, with its arithmetic on screen. A multiplier the reader
  -- cannot check is a multiplier the reader should not accept.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE VIEW ' || :tgt || '.V_COST_EXTRAPOLATION AS '
 || 'SELECT m.CATEGORY, m.CREDITS AS MEASURED_AT_LIMITED, '
 || '''' || REPLACE(:scale_unit, '''', '''''') || ''' AS SCALE_UNIT, '
 || :scale_limited || ' AS LIMITED_SCALE, ' || :scale_production || ' AS PRODUCTION_SCALE, '
 || 'ROUND(DIV0(' || :scale_production || ', ' || :scale_limited || '), 4) AS RATIO, '
 || 'ROUND(m.CREDITS * DIV0(' || :scale_production || ', ' || :scale_limited || '), 6) '
 || '  AS EXTRAPOLATED_TO_PRODUCTION, '
 || '''PROJECTED'' AS LABEL, '
 || 'm.CREDITS || '' x ('' || ' || :scale_production || ' || '' / '' || ' || :scale_limited
 || ' || '') = '' || ROUND(m.CREDITS * DIV0(' || :scale_production || ', '
 || :scale_limited || '), 6) AS ARITHMETIC, '
 || 'm.STATUS AS MEASURED_STATUS, '
 || 'CASE WHEN ' || :scale_limited || ' = ' || :scale_production
 || '  THEN ''No scaling declared, so this is the measured figure unchanged. It is '
 || 'NOT a production estimate.'' '
 || '     WHEN m.STATUS <> ''LANDED'' '
 || '  THEN ''The measurement this extrapolates from has not landed yet, so the '
 || 'extrapolation is empty rather than a guess.'' '
 || '     ELSE ''Measured at LIMITED scale and multiplied by the ratio shown. The '
 || 'ratio assumes cost scales linearly in this unit, which is the assumption to '
 || 'argue with.'' END AS READ_THIS '
 || 'FROM ' || :tgt || '.COST_MEASURED m WHERE m.LABEL = ''MEASURED''');

  -- ── VALUE MODEL ───────────────────────────────────────────────────────────
  -- Three rules, and the third is the one that matters: the addressable base is
  -- computed from THEIR data, every conversion rate is an input with a stated
  -- default that they set, and if the only honest output is "here is the base, you
  -- supply the rate" then that IS the output. No invented ROI.
  --
  -- A solution declares its own lines below. A solution that declares nothing gets
  -- a single row saying so, which is a better artifact than an empty view: empty
  -- reads as broken, whereas "this solution does not claim a financial benefit"
  -- reads as a decision.
  LET value_inputs ARRAY := ARRAY_CONSTRUCT();
  LET value_base   ARRAY := ARRAY_CONSTRUCT();
  LET value_lines  ARRAY := ARRAY_CONSTRUCT();
-- ── VALUE MODEL ───────────────────────────────────────────────────────────────
-- This solution claims two concrete savings: staffing efficiency (scheduling
-- the right number of associates per traffic pattern) and markdown exposure
-- (marking down aged inventory before it erodes further). Both are measurable
-- from the views this solution builds, so the value model must exist.

-- ── Staffing savings: fewer wasted associate-hours per store per week ─────────
value_inputs := ARRAY_APPEND(:value_inputs, OBJECT_CONSTRUCT(
  'name', 'excess_hours_rate',
  'value', 0.15, 'default', 0.15, 'units', 'fraction of total associate-hours',
  'description', 'Share of associate-hours estimated as excess relative to the '
              || 'staffing-efficiency sweet spot. 15% is a placeholder from industry '
              || 'benchmarks for mid-size retail. Replace with your own scheduling data.'));
value_inputs := ARRAY_APPEND(:value_inputs, OBJECT_CONSTRUCT(
  'name', 'hourly_labor_cost',
  'value', 18.50, 'default', 18.50, 'units', 'currency per hour',
  'description', 'Fully loaded hourly cost per associate including benefits. '
              || '$18.50 is a US retail median placeholder. Use your actual figure.'));
value_inputs := ARRAY_APPEND(:value_inputs, OBJECT_CONSTRUCT(
  'name', 'weeks_per_year',
  'value', 52, 'default', 52, 'units', 'weeks',
  'description', 'Operating weeks per year for annualisation.'));

value_base := ARRAY_APPEND(:value_base, OBJECT_CONSTRUCT(
  'metric', 'weekly_associate_hours',
  'units', 'hours per week',
  'sql', 'SELECT ROUND(SUM(TOTAL_HOURS), 2) FROM ' || :tgt || '.V_DOLLARS_PER_HOUR',
  'derivation', 'Total associate-hours across all stores for the most recent '
             || 'snapshot period, from V_DOLLARS_PER_HOUR.'));

value_lines := ARRAY_APPEND(:value_lines, OBJECT_CONSTRUCT(
  'line', 'Staffing efficiency savings (UPPER BOUND)',
  'base_metric', 'weekly_associate_hours',
  'rate_input', 'excess_hours_rate',
  'value_input', 'hourly_labor_cost',
  'annualise_input', 'weeks_per_year',
  'horizon', 'per year if every excess hour were eliminated'));

-- ── Markdown savings: recovering margin on aged inventory ────────────────────
value_inputs := ARRAY_APPEND(:value_inputs, OBJECT_CONSTRUCT(
  'name', 'markdown_depth',
  'value', 0.30, 'default', 0.30, 'units', 'fraction of retail price',
  'description', 'Average markdown depth when aged inventory is finally cleared. '
              || '30% is a US apparel median. Replace with your category actuals.'));
value_inputs := ARRAY_APPEND(:value_inputs, OBJECT_CONSTRUCT(
  'name', 'early_action_recovery',
  'value', 0.10, 'default', 0.10, 'units', 'fraction of markdown avoided',
  'description', 'Share of the markdown that earlier action would have avoided. '
              || '10% is conservative: acting 2 weeks earlier on aging stock typically '
              || 'lets you sell through at a shallower discount.'));

value_base := ARRAY_APPEND(:value_base, OBJECT_CONSTRUCT(
  'metric', 'aged_inventory_retail_value',
  'units', 'currency',
  'sql', 'SELECT ROUND(SUM(i.UNITS_ON_HAND * p.UNIT_RETAIL_PRICE), 2) '
      || 'FROM ' || COALESCE(NULLIF($MERCHANT_INVENTORY_TABLE::VARCHAR, ''), :tgt || '.INVENTORY_SNAPSHOT')
      || ' i '
      || 'JOIN ' || COALESCE(NULLIF($MERCHANT_PRODUCTS_TABLE::VARCHAR, ''), :tgt || '.PRODUCTS')
      || ' p ON i.SKU_ID = p.SKU_ID '
      || 'WHERE DATEDIFF(day, i.FIRST_RECEIVED_DATE, CURRENT_DATE()) > 60',
  'derivation', 'Retail value of inventory sitting on shelves longer than 60 days, '
             || 'from the raw inventory table joined to the products table.'
             || ' V_MARKDOWN_EXPOSURE aggregates by store, so per-SKU detail must '
             || 'come from the source table.'));

value_lines := ARRAY_APPEND(:value_lines, OBJECT_CONSTRUCT(
  'line', 'Markdown avoidance from earlier aging action (UPPER BOUND)',
  'base_metric', 'aged_inventory_retail_value',
  'rate_input', 'markdown_depth',
  'value_input', 'early_action_recovery',
  'horizon', 'one-time per aging cohort'));

-- ── What cannot be measured ──────────────────────────────────────────────────
value_base := ARRAY_APPEND(:value_base, OBJECT_CONSTRUCT(
  'metric', 'incremental_conversion_revenue',
  'units', 'currency',
  'measurable', FALSE,
  'derivation', 'Would require a controlled experiment: apply the agent recommendations '
             || 'at treatment stores, withhold at control stores, difference the two.',
  'why_not', 'Nothing in the warehouse tells you whether conversion improved because '
          || 'of better staffing or because of weather, promotions, or seasonality. '
          || 'The staffing and markdown lines above are upper bounds on opportunity, '
          || 'not predictions of return.'));

  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE TABLE ' || :tgt || '.VALUE_INPUTS AS SELECT '
 || 'VALUE:name::STRING AS INPUT_NAME, VALUE:value::NUMBER(38,6) AS VALUE, '
 || 'VALUE:default::NUMBER(38,6) AS DEFAULT_VALUE, VALUE:units::STRING AS UNITS, '
 || 'IFF(VALUE:value::NUMBER(38,6) = VALUE:default::NUMBER(38,6), '
 || '''DEFAULT — you have not changed this'', ''CLIENT_SET'') AS SOURCE, '
 || 'VALUE:description::STRING AS WHAT_IT_MEANS '
 || 'FROM TABLE(FLATTEN(input => PARSE_JSON(BASE64_DECODE_STRING('''
 || BASE64_ENCODE(TO_JSON(:value_inputs)) || '''))))');

  -- The addressable base, and this is the part that has to come from THEIR data.
  --
  -- A base metric may be declared three ways, and the third is the point:
  --   'sql'   a scalar query, evaluated at BUILD time against the views this
  --           solution just created. This is the honest form -- the base is
  --           measured from the account rather than assumed.
  --   'value' a plan-time literal, for a base already known from discovery.
  --   measurable = FALSE  the solution KNOWS it cannot compute this base here, and
  --           says so with a reason instead of substituting a plausible number.
  --
  -- A base declared with 'sql' that does not compile fails the build loudly. That
  -- is deliberate: it is OUR SQL, so a broken one is a defect for the gauntlet to
  -- catch, not a condition of the customer's data to be swallowed at runtime.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE TABLE ' || :tgt || '.VALUE_BASE '
 || '(METRIC VARCHAR, BASE_VALUE NUMBER(38,4), UNITS VARCHAR, DERIVED_HOW VARCHAR, '
 || 'MEASURABLE BOOLEAN, WHY_NOT_MEASURABLE VARCHAR)');
  LET vb INT := 0;
  WHILE (:vb < ARRAY_SIZE(:value_base)) DO
    LET vb_o VARIANT := GET(:value_base, :vb);
    LET vb_m STRING := REPLACE(COALESCE(:vb_o:metric::STRING, ''), '''', '''''');
    LET vb_u STRING := REPLACE(COALESCE(:vb_o:units::STRING, ''), '''', '''''');
    LET vb_d STRING := REPLACE(COALESCE(:vb_o:derivation::STRING, ''), '''', '''''');
    LET vb_ok BOOLEAN := COALESCE(:vb_o:measurable::BOOLEAN, TRUE);
    LET vb_why STRING := REPLACE(COALESCE(:vb_o:why_not::STRING, ''), '''', '''''');
    LET vb_sql STRING := COALESCE(:vb_o:sql::STRING, '');
    stmts := ARRAY_APPEND(:stmts,
      'INSERT INTO ' || :tgt || '.VALUE_BASE '
   || '(METRIC, BASE_VALUE, UNITS, DERIVED_HOW, MEASURABLE, WHY_NOT_MEASURABLE) SELECT '
   || '''' || :vb_m || ''', '
   || CASE WHEN NOT :vb_ok THEN 'NULL'
           WHEN :vb_sql <> '' THEN '(' || :vb_sql || ')'
           ELSE COALESCE(:vb_o:value::STRING, 'NULL') END || ', '
   || '''' || :vb_u || ''', ''' || :vb_d || ''', '
   || IFF(:vb_ok, 'TRUE', 'FALSE') || ', '
   || IFF(:vb_why = '', 'NULL', '''' || :vb_why || ''''));
    vb := :vb + 1;
  END WHILE;

  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE TABLE ' || :tgt || '.VALUE_LINES AS SELECT '
 || 'VALUE:line::STRING AS LINE, VALUE:base_metric::STRING AS BASE_METRIC, '
 || 'VALUE:rate_input::STRING AS RATE_INPUT, VALUE:value_input::STRING AS VALUE_INPUT, '
     -- Names an input that converts the base's own period into a year. Without it a
     -- per-day base produced a per-day benefit which was then compared against a
     -- per-year cost, and the NET column silently subtracted a year of cost from a
     -- day of value. It read as a credible negative number, which is the worst kind
     -- of wrong. It is an INPUT rather than a constant so a client whose warehouses
     -- only run on business days can say 250 instead of 365.
 || 'VALUE:annualise_input::STRING AS ANNUALISE_INPUT, '
 || 'COALESCE(VALUE:horizon::STRING, ''per year'') AS HORIZON '
 || 'FROM TABLE(FLATTEN(input => PARSE_JSON(BASE64_DECODE_STRING('''
 || BASE64_ENCODE(TO_JSON(:value_lines)) || '''))))');

  -- Cost on one side, value on the other, both ANNUAL so the comparison is
  -- apples-to-apples, arithmetic printed on every row, and the two never blended
  -- into a single "ROI" figure. Cost is MEASURED where it has landed and PROJECTED
  -- where it has not, and the column says which.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE VIEW ' || :tgt || '.V_BUSINESS_CASE AS '
 || 'WITH cost AS ('
 || '  SELECT SUM(CASE WHEN LABEL = ''MEASURED'' AND STATUS = ''LANDED'' THEN CREDITS END) '
 || '           AS MEASURED_CREDITS, '
 || '         SUM(CASE WHEN LABEL = ''PROJECTED'' AND CATEGORY = ''STEADY_STATE'' '
 || '                  THEN CREDITS END) AS PROJECTED_CREDITS_PER_DAY, '
 || '         COUNT_IF(LABEL = ''MEASURED'' AND STATUS = ''NOT_YET_LANDED'') AS PENDING '
 || '  FROM ' || :tgt || '.V_COST_LINES) '
 || 'SELECT l.LINE, b.METRIC, b.BASE_VALUE, b.UNITS, b.DERIVED_HOW, b.MEASURABLE, '
 || '       r.INPUT_NAME AS RATE_NAME, r.VALUE AS RATE, r.SOURCE AS RATE_SOURCE, '
 || '       v.INPUT_NAME AS VALUE_NAME, v.VALUE AS VALUE_PER_UNIT, v.SOURCE AS VALUE_SOURCE, '
 || '       COALESCE(an.VALUE, 1) AS PERIODS_PER_YEAR, l.HORIZON, '
 || '       CASE WHEN NOT b.MEASURABLE THEN NULL ELSE ROUND(b.BASE_VALUE * r.VALUE '
 || '            * v.VALUE * COALESCE(an.VALUE, 1), 2) END AS GROSS_VALUE_PER_YEAR, '
 || '       ROUND(c.PROJECTED_CREDITS_PER_DAY * 365 * ' || :rate || ', 2) AS PROJECTED_COST_PER_YEAR, '
 || '       CASE WHEN NOT b.MEASURABLE THEN NULL '
 || '            ELSE ROUND(b.BASE_VALUE * r.VALUE * v.VALUE * COALESCE(an.VALUE, 1) '
 || '                       - c.PROJECTED_CREDITS_PER_DAY * 365 * ' || :rate || ', 2) '
 || '       END AS NET_PER_YEAR, '
     -- Payback in days, from two annual figures. NULL rather than a big number when
     -- annual value is zero or negative: "never" is the answer, and a division
     -- would print something that looks like a duration.
 || '       CASE WHEN NOT b.MEASURABLE '
 || '              OR COALESCE(b.BASE_VALUE * r.VALUE * v.VALUE * COALESCE(an.VALUE, 1), 0) <= 0 '
 || '            THEN NULL '
 || '            ELSE ROUND(DIV0(c.PROJECTED_CREDITS_PER_DAY * 365 * ' || :rate || ', '
 || '                            b.BASE_VALUE * r.VALUE * v.VALUE * COALESCE(an.VALUE, 1)) '
 || '                       * 365, 1) END AS PAYBACK_DAYS, '
 || '       CASE WHEN NOT b.MEASURABLE '
 || '            THEN ''UNMEASURABLE: '' || COALESCE(b.WHY_NOT_MEASURABLE, '
 || '                 ''this solution cannot compute this base from your account'') '
 || '            ELSE b.BASE_VALUE || '' '' || b.UNITS || '' x '' || r.VALUE || '' ('' '
 || '                 || r.INPUT_NAME || '') x '' || v.VALUE || '' ('' || v.INPUT_NAME '
 || '                 || '') x '' || COALESCE(an.VALUE, 1) || '' periods/yr = '' '
 || '                 || ROUND(b.BASE_VALUE * r.VALUE * v.VALUE * COALESCE(an.VALUE, 1), 2) '
 || '                 || '' per year'' END AS ARITHMETIC, '
 || '       ''The base is measured from your data. Both rates are YOURS to set -- '
 || 'the defaults are placeholders, not benchmarks, and VALUE_INPUTS says which of '
 || 'them you have actually changed. Value and cost are both annual here so they can '
 || 'be compared. Cost is '' || COALESCE(c.MEASURED_CREDITS::STRING, '
 || '''not yet measured'') || '' measured credits with '' || c.PENDING '
 || '       || '' category(ies) still pending.'' AS READ_THIS '
 || 'FROM ' || :tgt || '.VALUE_LINES l '
 || 'JOIN ' || :tgt || '.VALUE_BASE b ON b.METRIC = l.BASE_METRIC '
 || 'JOIN ' || :tgt || '.VALUE_INPUTS r ON r.INPUT_NAME = l.RATE_INPUT '
 || 'JOIN ' || :tgt || '.VALUE_INPUTS v ON v.INPUT_NAME = l.VALUE_INPUT '
 || 'LEFT JOIN ' || :tgt || '.VALUE_INPUTS an ON an.INPUT_NAME = l.ANNUALISE_INPUT '
 || 'CROSS JOIN cost c '
 || 'UNION ALL '
     -- The declared-nothing case. An empty view reads as a bug; this reads as an
     -- answer, and it is the correct answer for a solution whose benefit is
     -- operational rather than financial.
 || 'SELECT ''NO VALUE MODEL DECLARED'', NULL, NULL, NULL, NULL, FALSE, '
 || '       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '
 || '       ROUND((SELECT PROJECTED_CREDITS_PER_DAY FROM cost) * 365 * ' || :rate || ', 2), '
 || '       NULL, NULL, ''UNMEASURABLE: no financial benefit is claimed'', '
 || '       ''This solution does not assert a financial return. Its cost is shown so '
 || 'you can judge it against a benefit you decide on yourself. Inventing a rate here '
 || 'would be the dishonest option.'' '
 || 'WHERE NOT EXISTS (SELECT 1 FROM ' || :tgt || '.VALUE_LINES)');

  -- ── POC SUCCESS CRITERIA ──────────────────────────────────────────────────
  -- What would make this POC a success, decided from THEIR account rather than
  -- from a number somebody liked. Same shape as the value model above: the
  -- solution declares criteria, this block builds the objects.
  --
  -- A criterion carries two SQL scalars, `target_sql` and `actual_sql`, and BOTH
  -- are re-evaluated on every read of V_POC_SCORECARD. That is a deliberate
  -- choice by the operator and it has a cost worth naming: because the bar is
  -- re-derived from current data, a MET on Tuesday and a MET on Friday are not
  -- necessarily the same claim, and a shrinking base can lower the bar it is
  -- being judged against. The COMPARABILITY column on every row says so, so the
  -- caveat travels with the number instead of living in a design document.
  --
  -- The mechanism is worth understanding before editing. A view cannot
  -- EXECUTE IMMEDIATE a string, so target_sql/actual_sql are not stored and
  -- interpreted -- they are INLINED as scalar subqueries into the view body at
  -- build time. Reading the view re-runs them. Consequence for snippet authors:
  -- each must be an UNCORRELATED scalar subquery. A correlated one, or an EXISTS
  -- in the select list, raises "Unsupported subquery type" at build.
  --
  -- Four states, and the third and fourth are the reason this exists:
  --   MET       target compared against actual, comparison holds
  --   NOT_MET   comparison does not hold. A real failure, reported as one.
  --   PENDING   cannot be evaluated YET -- credits have not landed, a holdout
  --             group does not exist. Carries why, and when it resolves.
  --   N/A       does not apply to this build, e.g. PRODUCTION-tier only.
  -- PENDING is not a failure and must never render as one. A zero standing in
  -- for "no data yet" is the defect this design exists to prevent.
  -- WHY THESE ARE ALL poc_-PREFIXED. The first cut used sc, sc2, sc_o and so on,
  -- and two solutions legitimately declare their own `LET sc` in this same
  -- procedure body -- 09_rmn_cleanroom's adapt_apply.sql holds slot columns in one.
  -- Snowflake rejected the whole block with "Variable with name SC declared twice"
  -- and the build failed with nothing to point at the cause. A shared template does
  -- not get to squat on short identifiers that snippet authors reasonably use.
  LET success_criteria ARRAY := ARRAY_CONSTRUCT();
-- ── POC SUCCESS CRITERIA ──────────────────────────────────────────────────────
-- Targets are DERIVED from this account's data, never literal. Unmeasured
-- criteria never read NOT_MET. PENDING never rolls up to MET.

LET sc_stores STRING := COALESCE(NULLIF($MERCHANT_STORES_TABLE::VARCHAR, ''), '');
LET sc_sales  STRING := COALESCE(NULLIF($MERCHANT_DAILY_SALES_TABLE::VARCHAR, ''), '');
LET sc_inv    STRING := COALESCE(NULLIF($MERCHANT_INVENTORY_TABLE::VARCHAR, ''), '');
LET sc_traf   STRING := COALESCE(NULLIF($MERCHANT_TRAFFIC_TABLE::VARCHAR, ''), '');
LET sc_labor  STRING := COALESCE(NULLIF($MERCHANT_LABOR_TABLE::VARCHAR, ''), '');

-- ── Coverage: every configured store appears in the summary ──────────────────
IF (:sc_stores <> '' AND :sc_sales <> '') THEN
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'MERCHANT_STORE_COVERAGE',
    'label', 'The merchant summary covers every store in your stores table',
    'why', 'A store missing from V_MERCHANT_SUMMARY is one whose sell-through, '
        || 'inventory turns and conversion rate are invisible. The rollup should '
        || 'represent every active store.',
    'compare', '=',
    'units', 'distinct stores',
    'basis', 'BY_QUERY_ID',
    'target_sql', 'SELECT COUNT(DISTINCT STORE_ID) FROM ' || :sc_stores
        || ' WHERE IS_OPEN = TRUE',
    'actual_sql', 'SELECT COUNT(DISTINCT STORE_ID) FROM ' || :tgt
        || '.V_MERCHANT_SUMMARY',
    'target_derivation', 'The count of open stores in ' || :sc_stores
        || '. The summary view should represent every one.'));
END IF;

-- ── Sell-through populated: views built over sales+inventory have data ───────
IF (:sc_sales <> '' AND :sc_inv <> '') THEN
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'MERCHANT_SELL_THROUGH_POP',
    'label', 'Sell-through rates are computed for active SKU/store combinations',
    'why', 'V_SELL_THROUGH is the core retail measure. If it has no rows, the '
        || 'agent has nothing meaningful to reason about.',
    'compare', '>',
    'units', 'rows',
    'basis', 'BY_QUERY_ID',
    'target_sql', 'SELECT 0',
    'actual_sql', 'SELECT COUNT(*) FROM ' || :tgt || '.V_SELL_THROUGH',
    'target_derivation', 'Greater than zero: at least one SKU/store combination '
        || 'must have a computed sell-through rate.'));
END IF;

-- ── Markdown exposure: aged inventory is flagged ─────────────────────────────
IF (:sc_inv <> '') THEN
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'MERCHANT_MARKDOWN_FLAGGED',
    'label', 'Markdown exposure identifies inventory older than the aging threshold',
    'why', 'Inventory sitting on the shelf beyond the aging window erodes margin. '
        || 'If the view cannot spot aged stock, markdown decisions are blind.',
    'compare', '>',
    'units', 'rows with aging flag',
    'basis', 'BY_QUERY_ID',
    'target_sql', 'SELECT 0',
    'actual_sql', 'SELECT COUNT(*) FROM ' || :tgt
        || '.V_MARKDOWN_EXPOSURE WHERE AGED_ON_HAND > 0',
    'target_derivation', 'Greater than zero: the fixture data deliberately includes '
        || 'inventory received more than 60 days ago.'));
END IF;

-- ── Staffing efficiency: the measure that justifies the agent ────────────────
IF (:sc_traf <> '' AND :sc_labor <> '' AND :sc_sales <> '') THEN
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'MERCHANT_STAFFING_COMPUTED',
    'label', 'Staffing efficiency is computed for stores with traffic and labor data',
    'why', 'V_STAFFING_EFFICIENCY is the cross-measure computation that a semantic '
        || 'view cannot do alone. If it is empty, the agent collapses to a paraphraser.',
    'compare', '>',
    'units', 'rows',
    'basis', 'BY_QUERY_ID',
    'target_sql', 'SELECT 0',
    'actual_sql', 'SELECT COUNT(*) FROM ' || :tgt || '.V_STAFFING_EFFICIENCY',
    'target_derivation', 'Greater than zero: at least one store must have staffing '
        || 'efficiency computed from the intersection of traffic, labor and sales.'));
END IF;

-- ── Agent reasoning: can the agent beat the semantic view (R1) ───────────────
IF (:sc_stores <> '' AND :sc_sales <> '' AND :sc_traf <> '' AND :sc_labor <> '') THEN
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'MERCHANT_AGENT_REASONING',
    'label', 'The agent can diagnose cross-measure correlations and recommend actions',
    'why', 'An agent that restates numbers the semantic view already provides does not '
        || 'earn its place. The agent must demonstrate cross-measure reasoning: why is '
        || 'conversion low when traffic is high, and what to do about it.',
    'compare', '>=',
    'units', 'measures referenced in answer',
    'basis', 'BY_QUERY_ID',
    'target_derivation', 'Would require calling MERCHANT_AGENT with a cross-measure '
        || 'diagnostic question and checking the response references two or more of '
        || 'the ten measures plus a recommended action.',
    'pending_reason', 'Agent reasoning quality requires a live agent call and human '
        || 'review of the response. The check in manifest.py exercises this at gauntlet '
        || 'time when a Snowflake connection is available.',
    'resolves_when', 'Run the agent_cross_measure_reasoning check during the gauntlet '
        || 'with a live Snowflake connection.'));
END IF;

-- ── Cost ─────────────────────────────────────────────────────────────────────
LET sc_cap NUMBER(38,6) := COALESCE(NULLIF($MERCHANT_CREDIT_CAP::NUMBER(38,6), 0), 0);
IF (:sc_cap > 0) THEN
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'MERCHANT_COST_IN_BUDGET',
    'label', 'Measured steady-state cost stays inside your credit cap',
    'why', 'A POC that cannot state its own running cost cannot be approved for '
        || 'production, and a projection is not a measurement.',
    'compare', '<=',
    'units', 'credits',
    'basis', 'BY_TAG',
    'target_sql', 'SELECT ' || :sc_cap,
    'actual_sql', 'SELECT SUM(CREDITS) FROM ' || :tgt || '.V_COST_LINES '
        || 'WHERE LABEL = ''MEASURED'' AND STATUS = ''LANDED''',
    'target_derivation', 'Your MERCHANT_CREDIT_CAP setting, currently '
        || :sc_cap || ' credits.',
    'pending_reason', 'Warehouse credits reach ACCOUNT_USAGE on a delay, so '
        || 'nothing has been attributed to this run yet.',
    'resolves_when', 'Credits land in ACCOUNT_USAGE, typically within 8 hours. '
        || 'Call MEASURE() in this schema after that to fill it in.'));
ELSE
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'MERCHANT_COST_IN_BUDGET',
    'label', 'Measured steady-state cost stays inside your credit cap',
    'why', 'A POC that cannot state its own running cost cannot be approved for '
        || 'production.',
    'compare', '<=',
    'units', 'credits',
    'basis', 'BY_TAG',
    'target_derivation', 'No cap was set, so there is no bar to derive.',
    'na_reason', 'MERCHANT_CREDIT_CAP is 0, so no ceiling was declared for this run. '
        || 'Set it and re-run to have this criterion scored.'));
END IF;

  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE TABLE ' || :tgt || '.SUCCESS_CRITERIA '
 || '(CODE VARCHAR, LABEL VARCHAR, WHY_IT_MATTERS VARCHAR, COMPARE VARCHAR, '
 || 'UNITS VARCHAR, BASIS VARCHAR, TARGET_DERIVATION VARCHAR, '
 || 'PENDING_REASON VARCHAR, RESOLVES_WHEN VARCHAR, NA_REASON VARCHAR)');

  -- The declarations themselves, one INSERT each. Same reason the value base
  -- uses a WHILE loop rather than a FLATTEN: the fields are optional in
  -- different combinations and a single projection over the array would have to
  -- invent a shape for the absent ones.
  LET poc_i INT := 0;
  WHILE (:poc_i < ARRAY_SIZE(:success_criteria)) DO
    LET poc_o VARIANT := GET(:success_criteria, :poc_i);
    LET poc_code STRING := REPLACE(COALESCE(:poc_o:code::STRING, ''), '''', '''''');
    LET poc_lab  STRING := REPLACE(COALESCE(:poc_o:label::STRING, ''), '''', '''''');
    LET poc_why  STRING := REPLACE(COALESCE(:poc_o:why::STRING, ''), '''', '''''');
    LET poc_cmp  STRING := REPLACE(COALESCE(:poc_o:compare::STRING, '>='), '''', '''''');
    LET poc_un   STRING := REPLACE(COALESCE(:poc_o:units::STRING, ''), '''', '''''');
    LET poc_bas  STRING := REPLACE(COALESCE(:poc_o:basis::STRING, 'BY_TIME_WINDOW'), '''', '''''');
    LET poc_der  STRING := REPLACE(COALESCE(:poc_o:target_derivation::STRING, ''), '''', '''''');
    LET poc_pr   STRING := REPLACE(COALESCE(:poc_o:pending_reason::STRING, ''), '''', '''''');
    LET poc_rw   STRING := REPLACE(COALESCE(:poc_o:resolves_when::STRING, ''), '''', '''''');
    LET poc_nr   STRING := REPLACE(COALESCE(:poc_o:na_reason::STRING, ''), '''', '''''');
    stmts := ARRAY_APPEND(:stmts,
      'INSERT INTO ' || :tgt || '.SUCCESS_CRITERIA (CODE, LABEL, WHY_IT_MATTERS, '
   || 'COMPARE, UNITS, BASIS, TARGET_DERIVATION, PENDING_REASON, RESOLVES_WHEN, '
   || 'NA_REASON) SELECT '
   || '''' || :poc_code || ''', ''' || :poc_lab || ''', ''' || :poc_why || ''', '
   || '''' || :poc_cmp || ''', ''' || :poc_un || ''', ''' || :poc_bas || ''', '
   || '''' || :poc_der || ''', '
   || IFF(:poc_pr = '', 'NULL', '''' || :poc_pr || '''') || ', '
   || IFF(:poc_rw = '', 'NULL', '''' || :poc_rw || '''') || ', '
   || IFF(:poc_nr = '', 'NULL', '''' || :poc_nr || ''''));
    poc_i := :poc_i + 1;
  END WHILE;

  -- The scorecard. Each criterion becomes one SELECT with its target and actual
  -- inlined, and the arms are UNION ALLed into a single view. Built as a string
  -- because the number of arms is not known until the solution has declared.
  LET poc_body STRING := '';
  LET poc_j INT := 0;
  WHILE (:poc_j < ARRAY_SIZE(:success_criteria)) DO
    LET poc2_o VARIANT := GET(:success_criteria, :poc_j);
    LET poc2_code STRING := REPLACE(COALESCE(:poc2_o:code::STRING, ''), '''', '''''');
    LET poc2_cmp  STRING := COALESCE(:poc2_o:compare::STRING, '>=');
    LET poc2_tsql STRING := COALESCE(:poc2_o:target_sql::STRING, '');
    LET poc2_asql STRING := COALESCE(:poc2_o:actual_sql::STRING, '');
    -- An unevaluable criterion declares no actual_sql. It still gets a row --
    -- omitting it would make the scorecard look shorter than the promise.
    LET poc2_t STRING := IFF(:poc2_tsql = '', 'CAST(NULL AS NUMBER(38,6))',
                           '(' || :poc2_tsql || ')::NUMBER(38,6)');
    LET poc2_a STRING := IFF(:poc2_asql = '', 'CAST(NULL AS NUMBER(38,6))',
                           '(' || :poc2_asql || ')::NUMBER(38,6)');
    poc_body := :poc_body
      || IFF(:poc_body = '', '', ' UNION ALL ')
      || 'SELECT ''' || :poc2_code || ''' AS CODE, ' || :poc2_t || ' AS TARGET, '
      || :poc2_a || ' AS ACTUAL, ''' || REPLACE(:poc2_cmp, '''', '''''') || ''' AS CMP';
    poc_j := :poc_j + 1;
  END WHILE;

  -- The verdict CASE is deliberately ordered, and only NA_REASON forces a state.
  --
  -- PENDING_REASON is an EXPLANATION, not a state. An earlier cut had it force
  -- PENDING, which meant a criterion that declared "credits land in about eight
  -- hours" was pinned to PENDING permanently -- it could never resolve, so the
  -- one criterion whose whole point was to become answerable never did. A
  -- criterion is pending because its ACTUAL is absent, and for no other reason;
  -- the declared text only says WHY it is absent and when that changes.
  --
  -- The NULL check therefore has to come before the comparison. Reversing them
  -- would let a NULL actual reach the comparison, which returns NULL, which a
  -- naive COALESCE would then turn into a failure. "Not measured yet" reported as
  -- "failed" is the single most damaging thing this view could do.
  IF (ARRAY_SIZE(:success_criteria) > 0) THEN
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE VIEW ' || :tgt || '.V_POC_SCORECARD AS '
   || 'WITH ev AS (' || :poc_body || ') '
   || 'SELECT c.CODE, c.LABEL, c.WHY_IT_MATTERS, e.TARGET, e.ACTUAL, c.UNITS, '
   || '       c.COMPARE, c.BASIS, c.TARGET_DERIVATION, '
   || '       CASE WHEN c.NA_REASON IS NOT NULL THEN ''N/A'' '
   || '            WHEN e.ACTUAL IS NULL OR e.TARGET IS NULL THEN ''PENDING'' '
   || '            WHEN e.CMP = ''>='' AND e.ACTUAL >= e.TARGET THEN ''MET'' '
   || '            WHEN e.CMP = ''<='' AND e.ACTUAL <= e.TARGET THEN ''MET'' '
   || '            WHEN e.CMP = ''>''  AND e.ACTUAL >  e.TARGET THEN ''MET'' '
   || '            WHEN e.CMP = ''<''  AND e.ACTUAL <  e.TARGET THEN ''MET'' '
   || '            WHEN e.CMP = ''='' AND e.ACTUAL =  e.TARGET THEN ''MET'' '
   || '            ELSE ''NOT_MET'' END AS STATE, '
      -- Why a row is not simply pass/fail, in the row itself. The solution's own
      -- wording wins when it has one, because "a randomised holdout would be
      -- required" is worth infinitely more than "no measurement has landed".
   || '       CASE WHEN c.NA_REASON IS NOT NULL THEN c.NA_REASON '
   || '            WHEN e.ACTUAL IS NOT NULL AND e.TARGET IS NOT NULL THEN NULL '
   || '            WHEN c.PENDING_REASON IS NOT NULL THEN c.PENDING_REASON '
   || '            WHEN e.ACTUAL IS NULL THEN ''No measurement has landed for this '
   || 'criterion yet. It is not a failure; it is not yet answerable.'' '
   || '            ELSE ''The target could not be derived from your account -- the '
   || 'discovery input it depends on is absent.'' END AS WHY_NOT_EVALUATED, '
      -- Suppressed once the row is answerable: "resolves when credits land" under
      -- a row that has already been decided is stale advice.
   || '       CASE WHEN c.NA_REASON IS NULL '
   || '             AND (e.ACTUAL IS NULL OR e.TARGET IS NULL) '
   || '            THEN c.RESOLVES_WHEN END AS RESOLVES_WHEN, '
      -- The arithmetic, printed. A bare MET is an assertion; "42 >= 30" is
      -- checkable by the person reading it.
   || '       CASE WHEN e.ACTUAL IS NULL OR e.TARGET IS NULL THEN NULL '
   || '            ELSE ROUND(e.ACTUAL, 4) || '' '' || e.CMP || '' '' '
   || '                 || ROUND(e.TARGET, 4) || '' '' || COALESCE(c.UNITS, '''') '
   || '       END AS ARITHMETIC, '
   || '       ''Target and actual are BOTH re-derived from your account on every '
   || 'read, so this bar moves as your data moves. That is intended -- the target '
   || 'is not a number we picked -- but it means MET is a statement about today, '
   || 'not a result comparable across runs. TARGET_DERIVATION says how the bar '
   || 'was set. BASIS says how the actual was attributed.'' AS COMPARABILITY '
   || 'FROM ' || :tgt || '.SUCCESS_CRITERIA c '
   || 'JOIN ev e ON e.CODE = c.CODE');
  ELSE
    -- Declared nothing. One honest row beats an empty view, exactly as with the
    -- value model: empty reads as broken, this reads as unauthored.
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE VIEW ' || :tgt || '.V_POC_SCORECARD AS SELECT '
   || '''NO SUCCESS CRITERIA DECLARED'' AS CODE, '
   || '''This solution has not declared POC success criteria'' AS LABEL, '
   || 'NULL AS WHY_IT_MATTERS, CAST(NULL AS NUMBER(38,6)) AS TARGET, '
   || 'CAST(NULL AS NUMBER(38,6)) AS ACTUAL, NULL AS UNITS, NULL AS COMPARE, '
   || 'NULL AS BASIS, NULL AS TARGET_DERIVATION, ''PENDING'' AS STATE, '
   || '''No criteria are declared, so there is nothing to pass or fail. This is a '
   || 'gap in the solution, not a result for your account.'' AS WHY_NOT_EVALUATED, '
   || '''When this solution declares blocks/success_criteria.sql'' AS RESOLVES_WHEN, '
   || 'NULL AS ARITHMETIC, ''Nothing is being claimed here.'' AS COMPARABILITY');
  END IF;

  -- The roll-up behind the header chip. MET requires that nothing failed AND
  -- that something actually passed -- a scorecard of nothing but PENDING is not
  -- a success, and calling it one would be the whole failure mode of this
  -- feature. NOT_RUN is not a pass.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE VIEW ' || :tgt || '.V_POC_VERDICT AS '
 || 'WITH s AS (SELECT COUNT_IF(STATE = ''MET'') AS MET, '
 || '                  COUNT_IF(STATE = ''NOT_MET'') AS NOT_MET, '
 || '                  COUNT_IF(STATE = ''PENDING'') AS PENDING, '
 || '                  COUNT_IF(STATE = ''N/A'') AS NA, '
 || '                  COUNT_IF(STATE <> ''N/A'') AS SCORED '
 || '           FROM ' || :tgt || '.V_POC_SCORECARD) '
 || 'SELECT MET, NOT_MET, PENDING, NA, SCORED, '
 || '       MET || ''/'' || SCORED || '' MET'' AS HEADLINE, '
 || '       CASE WHEN SCORED = 0 THEN ''NOT_RUN'' '
 || '            WHEN NOT_MET > 0 THEN ''NOT_MET'' '
 || '            WHEN MET = 0 THEN ''PENDING'' '
 || '            WHEN PENDING > 0 THEN ''MET_WITH_PENDING'' '
 || '            ELSE ''MET'' END AS VERDICT, '
 || '       CASE WHEN SCORED = 0 THEN ''Nothing has been scored.'' '
 || '            WHEN NOT_MET > 0 THEN NOT_MET || '' criterion(s) did not meet '
 || 'target. Open the POC success tab for the arithmetic on each.'' '
 || '            WHEN MET = 0 THEN ''Nothing has failed, but nothing has been '
 || 'confirmed either -- every criterion is still pending.'' '
 || '            WHEN PENDING > 0 THEN ''Everything measurable so far has met its '
 || 'target, with '' || PENDING || '' still pending. Not a complete result yet.'' '
 || '            ELSE ''Every scored criterion met its target.'' END AS READ_THIS '
 || 'FROM s');

  -- ── PRODUCTION HARDENING ──────────────────────────────────────────────────
  -- Only at PRODUCTION tier, and every piece of it detects-then-skips with a
  -- printed reason rather than failing the build. A platform team's objection to a
  -- tool is almost never "it does too little"; it is "it left something behind
  -- that nobody owns".
  IF (:tier = 'PRODUCTION') THEN
    -- Cost attribution. The tag lives in the target schema so it disappears with
    -- it; the ONE thing outside the schema is the tag applied to the warehouse, so
    -- that is the only row the registry needs.
    stmts := ARRAY_APPEND(:stmts,
      'CREATE TAG IF NOT EXISTS ' || :tgt || '.ONESHOT_SOLUTION '
   || 'COMMENT = ''Cost attribution for Retail Merchant Agent. Query '
   || 'ACCOUNT_USAGE.TAG_REFERENCES to find everything this deployment owns.''');
    stmts := ARRAY_APPEND(:stmts,
      'ALTER SCHEMA ' || :tgt || ' SET TAG ' || :tgt || '.ONESHOT_SOLUTION = '
   || '''Retail Merchant Agent''');
    IF (:wh_ok) THEN
      stmts := ARRAY_APPEND(:stmts,
        'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY (TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) '
     || 'SELECT ''' || :meas_wh || ''', ''' || :tgt || '.ONESHOT_SOLUTION'', '
     || '''WAREHOUSE'', ''OBJECT_TAG'' '
     || 'WHERE NOT EXISTS (SELECT 1 FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
     || 'WHERE TARGET_FQN = ''' || :meas_wh || ''' AND ARTIFACT = ''' || :tgt
     || '.ONESHOT_SOLUTION'' AND KIND = ''OBJECT_TAG'')');
      stmts := ARRAY_APPEND(:stmts,
        'ALTER WAREHOUSE ' || :meas_wh || ' SET TAG ' || :tgt
     || '.ONESHOT_SOLUTION = ''Retail Merchant Agent''');
    END IF;
    cost_detail := ARRAY_APPEND(:cost_detail,
      'COST ATTRIBUTION: everything this deployment created carries the tag '
   || :tgt || '.ONESHOT_SOLUTION, so your FinOps team can find it in '
   || 'ACCOUNT_USAGE.TAG_REFERENCES without asking us. Tags cost nothing.');

    -- Failure notification. Tasks take an error integration directly; dynamic
    -- tables have NO equivalent clause, so theirs needs an alert, which is
    -- serverless and therefore costs credits of its own. That asymmetry is priced
    -- rather than hidden, and the whole thing skips loudly when there is no
    -- integration to point at.
    IF (:notif <> '') THEN
      notes := ARRAY_APPEND(:notes,
        'FAILURE NOTIFICATION: task failures will be sent to ' || :notif || '. '
     || 'Dynamic table refresh failures CANNOT use an error integration -- Snowflake '
     || 'has no such clause for them -- so if this solution creates dynamic tables '
     || 'their failures need a serverless ALERT over DYNAMIC_TABLE_REFRESH_HISTORY, '
     || 'which is priced separately in the cost lines above.');
    ELSE
      notes := ARRAY_APPEND(:notes,
        'FAILURE NOTIFICATION SKIPPED: MERCHANT_NOTIFICATION_INTEGRATION is blank, so '
     || 'nothing will tell you when a scheduled object fails. This is a real gap at '
     || 'PRODUCTION tier and the build continues anyway rather than blocking you. '
     || 'Run SHOW NOTIFICATION INTEGRATIONS to pick one; if the account has none, an '
     || 'administrator runs: CREATE NOTIFICATION INTEGRATION ONESHOT_ALERTS '
     || 'TYPE = EMAIL ENABLED = TRUE;');
    END IF;

    -- What an on-call engineer opens at 3am. Built to survive a solution that has
    -- no tasks and no dynamic tables: it returns a row saying so rather than
    -- nothing, because an empty operations view is indistinguishable from a broken
    -- one.
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE VIEW ' || :tgt || '.V_OPERATIONS AS '
   || 'SELECT ''TASK'' AS OBJECT_KIND, t.NAME AS OBJECT_NAME, '
      -- The cron string lives on ACCOUNT_USAGE.TASKS, NOT on TASK_HISTORY.
      -- t.SCHEDULE was read straight off TASK_HISTORY, which has 30 columns and
      -- none of them is SCHEDULE, so this view failed to compile on every
      -- PRODUCTION build -- and because the statement loop stops at the first
      -- failure, everything declared after it was silently never created. It went
      -- unnoticed because step 16 read only the OUTER statement results and this
      -- failure surfaced as an inner FAILED row nobody looked at.
      --
      -- COALESCE, because ACCOUNT_USAGE lags: a task created minutes ago may have
      -- history but no TASKS row yet, and a blank SLA is better than dropping the
      -- task from an operations view.
   || '       COALESCE(s.SCHEDULE, ''schedule not yet in ACCOUNT_USAGE.TASKS'') '
   || '         AS REFRESH_SLA, MAX(t.COMPLETED_TIME) AS LAST_RUN, '
   || '       COUNT_IF(t.STATE = ''FAILED'') AS FAILURES_IN_WINDOW, '
   || '       COUNT(*) AS RUNS_IN_WINDOW, NULL::NUMBER AS CREDITS_IN_WINDOW, '
   || '       ''From ACCOUNT_USAGE.TASK_HISTORY over the last '' || ' || :w
   || '         || '' days.'' AS SOURCE '
   || '  FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY t '
      -- TASKS names its columns TASK_NAME / TASK_DATABASE / TASK_SCHEMA, while
      -- TASK_HISTORY uses NAME / DATABASE_NAME / SCHEMA_NAME. Two ACCOUNT_USAGE
      -- views of the same object disagreeing on column names is exactly the kind
      -- of thing to read rather than assume -- guessing S.NAME cost another run.
   || '  LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.TASKS s '
   || '    ON s.TASK_NAME = t.NAME AND s.TASK_DATABASE = t.DATABASE_NAME '
   || '   AND s.TASK_SCHEMA = t.SCHEMA_NAME AND s.DELETED IS NULL '
   || '  WHERE t.DATABASE_NAME = ''' || :db || ''' AND t.SCHEMA_NAME = ''' || :sch || ''' '
   || '    AND t.SCHEDULED_TIME >= DATEADD(day, -' || :w || ', CURRENT_TIMESTAMP()) '
   || '  GROUP BY 1, 2, 3 '
   || 'UNION ALL '
   || 'SELECT ''DYNAMIC_TABLE'', d.NAME, d.TARGET_LAG_SEC::STRING || '' sec target lag'', '
   || '       MAX(d.REFRESH_END_TIME), COUNT_IF(d.STATE = ''FAILED''), COUNT(*), NULL, '
   || '       ''From ACCOUNT_USAGE.DYNAMIC_TABLE_REFRESH_HISTORY. Note: dynamic tables '
   || 'auto-suspend after 5 consecutive failures.'' '
   || '  FROM SNOWFLAKE.ACCOUNT_USAGE.DYNAMIC_TABLE_REFRESH_HISTORY d '
   || '  WHERE d.DATABASE_NAME = ''' || :db || ''' AND d.SCHEMA_NAME = ''' || :sch || ''' '
   || '    AND d.REFRESH_START_TIME >= DATEADD(day, -' || :w || ', CURRENT_TIMESTAMP()) '
   || '  GROUP BY 1, 2, 3 '
   || 'UNION ALL '
   || 'SELECT ''THIS DEPLOYMENT'', ''' || :sch || ''', ''not scheduled'', '
   || '       (SELECT MAX(STARTED_AT) FROM ' || :tgt || '.RUN_LEDGER), 0, '
   || '       (SELECT COUNT(*) FROM ' || :tgt || '.RUN_LEDGER), '
   || '       (SELECT SUM(CREDITS) FROM ' || :tgt || '.V_COST_LINES '
   || '         WHERE LABEL = ''MEASURED'' AND STATUS = ''LANDED''), '
   || '       ''No tasks or dynamic tables found for this schema in the window. If '
   || 'this solution creates none, that is expected and this row is the whole '
   || 'operations picture.'' ');
    cost_detail := ARRAY_APPEND(:cost_detail,
      'OPERATIONS: V_OPERATIONS reports last run, failures and credits per '
   || 'scheduled object over ' || :w || ' days. It reads ACCOUNT_USAGE views, which '
   || 'are free to query but lag by up to 45 minutes for task history.');
  END IF;

  -- ── The action registry, its audit log, and the one door in ────────────────
  -- Built AFTER the solution's plan section, because that is where a solution
  -- declares its actions.
  --
  -- CREATE OR REPLACE ... AS SELECT rather than CREATE + INSERT: a second build
  -- must not stack a second copy of every action, which is the same bug
  -- ATTACHED_OBJECT_REGISTRY had. Note the two need DIFFERENT fixes and this comment
  -- used to imply otherwise: the action registry can be rebuilt from scratch each
  -- run, so CREATE OR REPLACE is right; the attachment registry must SURVIVE, because
  -- TEARDOWN reads it, so it takes an anti-join insert instead. Reaching for
  -- CREATE OR REPLACE there would have destroyed the record of what to detach.
  -- FLATTEN over a JSON literal also avoids the VALUES-clause restriction on
  -- ARRAY/OBJECT constructors.
  --
  -- The JSON travels BASE64-ENCODED, and that is not belt-and-braces. An action's
  -- `sql` array holds generated DDL, which routinely contains quoted identifiers
  -- like "ICE_GOLD_ORDERS". TO_JSON escapes those double quotes to \", and when
  -- the result is pasted into a single-quoted SQL literal Snowflake's parser
  -- consumes the backslash -- so PARSE_JSON receives structurally broken JSON and
  -- fails with "Error parsing JSON: missing comma, pos 1628", pointing at a
  -- character that is nowhere near the actual problem. Doubling the quotes, as
  -- this line used to, does nothing about the backslash.
  --
  -- 03_generative_completion hit this first and fixed it locally by chaining a
  -- second REPLACE for backslashes; that works but depends on getting the order
  -- right and on remembering it at every new call site. The base64 alphabet
  -- contains no quote and no backslash, so the hazard cannot recur here.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE TABLE ' || :tgt || '.ACTION_REGISTRY AS SELECT '
 || 'VALUE:code::STRING AS CODE, VALUE:label::STRING AS LABEL, '
 || 'VALUE:tier::STRING AS TIER, VALUE:effect::STRING AS EFFECT, '
 || 'VALUE:undo::STRING AS UNDO, '
 || 'VALUE:est::NUMBER(38,6) AS EST_CREDITS, VALUE:basis::STRING AS EST_BASIS, '
 || 'VALUE:sql::ARRAY AS RUN_SQL, '
    -- The reverse of RUN_SQL, declared by the solution alongside it. COALESCE to an
    -- empty array so an action that genuinely cannot be reversed is representable:
    -- zero undo statements is a fact the app can show, whereas a NULL would just
    -- look like a bug.
 || 'COALESCE(VALUE:undo_sql::ARRAY, ARRAY_CONSTRUCT()) AS UNDO_SQL, '
    -- The parameters this action accepts, declared alongside its SQL. Empty array for
    -- every action that takes none, which is why an unparameterised action is byte
    -- identical in behaviour to before: ARRAY_SIZE 0 skips the whole resolver.
    --
    -- Each element is {name, label, kind, allowed_sql, options, min, max, help}. The
    -- WHITELIST LIVES HERE, in the registry, and is evaluated inside RUN_ACTION -- not
    -- passed in by the app. The app cannot influence what a value is checked against,
    -- which is the entire point: a tampered client can only ever choose from a set
    -- this build already discovered.
 || 'COALESCE(VALUE:params::ARRAY, ARRAY_CONSTRUCT()) AS PARAM_SPEC, '
 || 'CURRENT_TIMESTAMP() AS DECLARED_AT '
 || 'FROM TABLE(FLATTEN(input => PARSE_JSON(BASE64_DECODE_STRING('''
 || BASE64_ENCODE(TO_JSON(:actions)) || '''))))');

  -- One row per attempt, whether it worked or not. An action framework without an
  -- audit trail is indistinguishable from someone running DDL by hand.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE TABLE IF NOT EXISTS ' || :tgt || '.ACTION_LOG '
 || '(LOG_ID VARCHAR, CODE VARCHAR, LABEL VARCHAR, EST_CREDITS NUMBER(38,6), '
 || 'STATUS VARCHAR, STATEMENTS_RUN INT, ERROR VARCHAR, '
 || 'RUN_BY VARCHAR DEFAULT CURRENT_USER(), '
 || 'STARTED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(), '
 || 'FINISHED_AT TIMESTAMP_NTZ, UNDO_SNAPSHOT VARCHAR, PARAMS VARCHAR)');
  -- Separate ALTER because the CREATE above is IF NOT EXISTS: a schema built by an
  -- earlier artifact already has the table and would silently keep the old shape.
  stmts := ARRAY_APPEND(:stmts,
    'ALTER TABLE ' || :tgt || '.ACTION_LOG '
 || 'ADD COLUMN IF NOT EXISTS UNDO_SNAPSHOT VARCHAR');
  -- The RESOLVED parameter values this run actually used, as JSON. Without this the
  -- audit trail becomes untrue the moment an action takes parameters: two rows reading
  -- "DONE. Attach the policy" would be indistinguishable while having tiered different
  -- tables. NULL for an unparameterised action, which is honest -- there were none.
  stmts := ARRAY_APPEND(:stmts,
    'ALTER TABLE ' || :tgt || '.ACTION_LOG '
 || 'ADD COLUMN IF NOT EXISTS PARAMS VARCHAR');
  stmts := ARRAY_APPEND(:stmts,
    'CREATE TABLE IF NOT EXISTS ' || :tgt || '.ACTION_STATEMENT_LOG '
 || '(LOG_ID VARCHAR, SEQ INT, STATEMENT VARCHAR, QUERY_ID VARCHAR, '
 || 'STATUS VARCHAR, ERROR VARCHAR, '
 || 'RAN_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP())');

  -- What the app reads. Excludes RUN_SQL on purpose: the dashboard needs to show
  -- what an action DOES and what it costs, and shipping the DDL to the browser
  -- invites someone to treat the page as the source of truth for it.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE VIEW ' || :tgt || '.V_ACTIONS AS SELECT '
 || 'a.CODE, a.LABEL, a.TIER, a.EFFECT, a.UNDO, a.EST_CREDITS, a.EST_BASIS, '
 || 'ARRAY_SIZE(a.RUN_SQL) AS STATEMENTS, '
 || 'ARRAY_SIZE(a.UNDO_SQL) AS UNDO_STATEMENTS, '
 || 'ARRAY_SIZE(a.PARAM_SPEC) AS PARAM_COUNT, '
 || '(SELECT COUNT(*) FROM ' || :tgt || '.ACTION_LOG l '
 || '  WHERE l.CODE = a.CODE AND l.STATUS = ''UNDONE'') AS TIMES_UNDONE, '
 || '(SELECT COUNT(*) FROM ' || :tgt || '.ACTION_LOG l '
 || '  WHERE l.CODE = a.CODE AND l.STATUS = ''DONE'') AS TIMES_RUN, '
 || '(SELECT MAX(l.FINISHED_AT) FROM ' || :tgt || '.ACTION_LOG l '
 || '  WHERE l.CODE = a.CODE AND l.STATUS = ''DONE'') AS LAST_RUN_AT '
 || 'FROM ' || :tgt || '.ACTION_REGISTRY a '
 || 'ORDER BY CASE a.TIER WHEN ''SAMPLE'' THEN 1 WHEN ''LIMITED'' THEN 2 ELSE 3 END, a.CODE');

  -- ── What the app renders a widget from ─────────────────────────────────────
  -- One row per parameter. Deliberately EXCLUDES allowed_sql, for the same reason
  -- V_ACTIONS excludes RUN_SQL: the app does not need the whitelist QUERY, it needs
  -- the whitelist RESULT, and shipping the query invites someone to treat the browser
  -- as the place the permitted set is decided. The host reads OPTIONS_SQL only to run
  -- it for display; RUN_ACTION re-evaluates the registry's own copy when it validates,
  -- so what the app showed can never be what authorises the value.
  --
  -- ORDINAL is preserved from the declaration order so the widgets render in the order
  -- the solution author intended rather than alphabetically.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE VIEW ' || :tgt || '.V_ACTION_PARAMS AS SELECT '
 || 'a.CODE, p.INDEX AS ORDINAL, '
 || 'p.VALUE:name::STRING AS PARAM_NAME, '
 || 'COALESCE(p.VALUE:label::STRING, p.VALUE:name::STRING) AS LABEL, '
 || 'UPPER(COALESCE(p.VALUE:kind::STRING, ''IDENT'')) AS KIND, '
 || 'p.VALUE:allowed_sql::STRING AS OPTIONS_SQL, '
 || 'p.VALUE:options::ARRAY AS OPTIONS, '
 || 'p.VALUE:min::NUMBER(38,6) AS MIN_VALUE, '
 || 'p.VALUE:max::NUMBER(38,6) AS MAX_VALUE, '
 || 'COALESCE(p.VALUE:freeform::BOOLEAN, FALSE) AS FREEFORM, '
 || 'p.VALUE:help::STRING AS HELP '
 || 'FROM ' || :tgt || '.ACTION_REGISTRY a, '
 || 'LATERAL FLATTEN(input => a.PARAM_SPEC) p '
 || 'ORDER BY a.CODE, p.INDEX');

  -- Estimated against measured. The measurement is NOT available immediately:
  -- per-query credits live in QUERY_ATTRIBUTION_HISTORY, which lags by up to a few
  -- hours, so this view is empty for a while after an action runs and then fills
  -- in. Saying that plainly beats printing an estimate and letting the reader
  -- assume it was measured.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE VIEW ' || :tgt || '.V_ACTION_COST AS SELECT '
 || 'l.LOG_ID, l.CODE, l.LABEL, l.STATUS, l.EST_CREDITS, '
 || 'SUM(q.CREDITS_ATTRIBUTED_COMPUTE) AS MEASURED_CREDITS, '
 || 'COUNT(q.QUERY_ID) AS STATEMENTS_MEASURED, l.STATEMENTS_RUN, l.STARTED_AT, '
    -- Why the measurement is absent, rather than leaving a NULL to be read as a
    -- failure. QUERY_ATTRIBUTION_HISTORY only records queries that consumed
    -- WAREHOUSE COMPUTE. ALTER WAREHOUSE, CREATE VIEW and SET MASKING POLICY consume
    -- none, so for a metadata-only action no row will EVER appear -- and every
    -- action was telling the customer the figure "appears once attribution catches
    -- up". Checked against real runs: ICE_FIX matched 0 of 27 statements and
    -- WH_SUSPEND_ALL 0 of 2, permanently. A promise that never comes true is worse
    -- than saying up front that there is nothing to measure.
 || 'CASE '
 || '  WHEN COUNT(q.QUERY_ID) >= l.STATEMENTS_RUN AND l.STATEMENTS_RUN > 0 '
 || '    THEN ''MEASURED'' '
 || '  WHEN COUNT(q.QUERY_ID) > 0 '
 || '    THEN ''PARTIAL: '' || COUNT(q.QUERY_ID) || '' of '' || l.STATEMENTS_RUN '
 || '      || '' statement(s) used attributable compute; the rest were metadata-only'' '
 || '  WHEN l.STARTED_AT > DATEADD(hour, -6, CURRENT_TIMESTAMP()) '
 || '    THEN ''PENDING: attribution can lag several hours. If these statements were '
|| 'metadata-only (ALTER, CREATE VIEW, policy attach) it will stay empty because they '
|| 'consume no warehouse compute.'' '
 || '  ELSE ''NO COMPUTE MEASURED: these statements consumed no warehouse compute, so '
|| 'QUERY_ATTRIBUTION_HISTORY has nothing to attribute. Metadata operations are '
|| 'genuinely near-free -- this is not a missing measurement.'' '
 || 'END AS MEASURED_STATUS '
 || 'FROM ' || :tgt || '.ACTION_LOG l '
 || 'LEFT JOIN ' || :tgt || '.ACTION_STATEMENT_LOG s ON s.LOG_ID = l.LOG_ID '
 || 'LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY q '
 || '  ON q.QUERY_ID = s.QUERY_ID '
 || 'GROUP BY 1,2,3,4,5,8,9');

  -- ── The monthly run-rate, over whatever the solution registered above ─────
  -- THE CADENCE IS KNOWN, THE DURATION IS MEASURED, THE PRODUCT IS PROJECTED.
  -- Runs per month comes from a schedule this build itself set, so it is a fact.
  -- Seconds per run comes from what this build observed. Their product is still a
  -- PROJECTION, because next month's data volume is not this month's -- and it is
  -- labelled that way rather than presented as a bill.
  --
  -- Deliberately not summed with anything MEASURED, for the same reason step 14
  -- asserts it: a total mixing a measurement with a forecast is a number nobody
  -- can defend in a room.
  -- A row with RUNS_PER_MONTH IS NULL is VOLUME-DRIVEN: a serverless meter billed per
  -- unit of data (Snowpipe Streaming, for instance) with no schedule and no warehouse.
  -- The formula below cannot describe it, and NULL arithmetic correctly yields NULL
  -- rather than inventing a monthly figure. Every schedule-driven solution writes a
  -- positive RUNS_PER_MONTH, so this branch changes nothing for them.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE VIEW ' || :tgt || '.V_MONTHLY_RUN_RATE AS SELECT '
 || 'KIND, OBJECT_NAME, CADENCE, RUNS_PER_MONTH, SECONDS_PER_RUN, '
 || 'WAREHOUSE_CREDITS_PER_HOUR, '
    -- credits = runs x seconds x (credits/hour / 3600). Multiply BEFORE dividing:
    -- LET cps := 1.0/3600.0 rounds to scale 6 (0.000278) and a solution already
    -- shipped a 4x-low figure that way.
 || 'ROUND(RUNS_PER_MONTH * SECONDS_PER_RUN * WAREHOUSE_CREDITS_PER_HOUR '
 || '  / 3600.0, 4) AS EST_CREDITS_PER_MONTH, '
 || 'CASE WHEN RUNS_PER_MONTH IS NULL THEN ''VOLUME-DRIVEN'' '
 || '     ELSE ''PROJECTED'' END AS LABEL, MEASURED_INPUT, BASIS, INSTALLED_AT '
 || 'FROM ' || :tgt || '.STANDING_WORKLOAD');

  -- One line the app and the packet can both print. Zero rows is a legitimate
  -- and meaningful answer -- it means this solution installs nothing recurring --
  -- so it says that in words rather than rendering an empty table.
  --
  -- Scheduled and volume-driven components are reported in SEPARATE clauses and are
  -- never added together. The single-sentence version claimed every figure was
  -- "PROJECTED from schedules this build set and durations it measured", which for a
  -- continuous serverless ingest endpoint was false three times over -- no schedule was
  -- set, no duration was measured, and the resulting "About 0.02 credits/month" read as
  -- though streaming were free. A volume-driven component contributes NO credits figure
  -- here on purpose: the honest answer is a per-unit rate plus a volume the customer
  -- controls, and that lives in BASIS.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE VIEW ' || :tgt || '.V_RUN_RATE_HEADLINE AS SELECT '
 || 'CASE WHEN COUNT(*) = 0 THEN '
 || '  ''This build installs nothing that runs on a schedule. It costs storage '
 || 'plus whatever compute the people querying it use.'' '
 || 'ELSE '
 || '  CASE WHEN COUNT_IF(RUNS_PER_MONTH IS NOT NULL) > 0 THEN '
 || '    ''About '' || ROUND(SUM(IFF(RUNS_PER_MONTH IS NOT NULL, '
 || '      RUNS_PER_MONTH * SECONDS_PER_RUN * WAREHOUSE_CREDITS_PER_HOUR '
 || '      / 3600.0, 0)), 2) '
 || '    || '' credits/month across '' || COUNT_IF(RUNS_PER_MONTH IS NOT NULL) '
 || '    || '' scheduled component(s), PROJECTED from schedules this build set '
 || 'and durations it measured.'' ELSE '''' END '
 || '  || CASE WHEN COUNT_IF(RUNS_PER_MONTH IS NULL) > 0 THEN '
 || '    IFF(COUNT_IF(RUNS_PER_MONTH IS NOT NULL) > 0, '' Plus '', ''This build '
 || 'installs '') || COUNT_IF(RUNS_PER_MONTH IS NULL) '
 || '    || '' volume-driven component(s) that run continuously with NO schedule '
 || 'and NO monthly projection: the cost scales with how much data you send, not '
 || 'with a cadence. This is NOT zero -- read BASIS in V_MONTHLY_RUN_RATE for the '
 || 'per-unit rate.'' ELSE '''' END '
 || 'END AS HEADLINE, COUNT(*) AS COMPONENTS, '
 || 'ROUND(COALESCE(SUM(IFF(RUNS_PER_MONTH IS NOT NULL, '
 || '  RUNS_PER_MONTH * SECONDS_PER_RUN * WAREHOUSE_CREDITS_PER_HOUR '
 || '  / 3600.0, 0)), 0), 4) AS EST_CREDITS_PER_MONTH, '
 || 'COUNT_IF(RUNS_PER_MONTH IS NOT NULL) AS SCHEDULED_COMPONENTS, '
 || 'COUNT_IF(RUNS_PER_MONTH IS NULL) AS VOLUME_COMPONENTS '
 || 'FROM ' || :tgt || '.STANDING_WORKLOAD');


  -- The only way to run one. Everything the app can do goes through here, so the
  -- refusals below are the whole safety model:
  --   1. the action must exist in this build
  --   2. the BUILD must have been authorised FOR THAT ACTION'S TIER -- ALLOW_ACTIONS
  --      for LIMITED and PRODUCTION, ALLOW_SAMPLE_ACTIONS for SAMPLE
  --   3. the caller must type the code back exactly
  -- and it stops at the FIRST failing statement, because a half-applied change is
  -- worse than an unapplied one.
  --
  -- Existence is checked BEFORE authorisation now, because the tier is a property of
  -- the registered action and there is nothing to authorise until we know it. The
  -- swap leaks nothing: the action codes are printed in the script and listed in the
  -- app, so "no such action" was never a secret.
  --
  -- An unrecognised TIER falls to the STRICTER gate on purpose. A typo in a tier
  -- name must not be a way to get a PRODUCTION action treated as a sample.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE PROCEDURE ' || :tgt || '.RUN_ACTION(P_CODE VARCHAR, P_CONFIRM VARCHAR, P_PARAMS VARCHAR) '
 || 'RETURNS VARCHAR LANGUAGE SQL EXECUTE AS CALLER AS '
 || 'DECLARE '
 || '  enabled BOOLEAN := FALSE; lbl STRING := ''''; tier STRING := ''''; '
 || '  est NUMBER(38,6) := 0; sqls ARRAY := ARRAY_CONSTRUCT(); usnap STRING := NULL; '
 || '  i INT := 0; ran INT := 0; errs STRING := ''''; '
 || '  log_id STRING := UUID_STRING(); cnt INT := 0; '
    -- Parameter resolution state. `resolved` accumulates the EMITTED TEXT for each
    -- parameter -- already shape-checked, already whitelisted, already quoted -- so
    -- interpolation downstream is a plain REPLACE over values that have passed every
    -- gate. Nothing the caller sent is ever interpolated directly.
 || '  pspec ARRAY := ARRAY_CONSTRUCT(); pobj OBJECT := OBJECT_CONSTRUCT(); '
 || '  resolved OBJECT := OBJECT_CONSTRUCT(); pkeys ARRAY := ARRAY_CONSTRUCT(); '
 || '  k INT := 0; kk INT := 0; pj VARIANT := NULL; pname STRING := ''''; '
 || '  pkind STRING := ''''; pval STRING := NULL; asql STRING := NULL; '
 || '  emit STRING := ''''; parts ARRAY := ARRAY_CONSTRUCT(); jj INT := 0; '
 || '  part STRING := ''''; hits INT := 0; num NUMBER(38,6) := NULL; '
 || '  canon STRING := NULL; opts ARRAY := ARRAY_CONSTRUCT(); '
    -- Two accumulators, deliberately. `resolved` holds the EMITTED TEXT that goes into
    -- the statements -- quoted, so "EVENT_TS". `chosen` holds the CANONICAL VALUE a
    -- human picked -- EVENT_TS. The log gets `chosen`, because an audit trail reading
    -- {"attach_on":"\"EVENT_TS\""} makes a reader decode escaping to learn what was
    -- done; the exact text that executed is already in ACTION_STATEMENT_LOG, so nothing
    -- is lost by keeping this one readable.
 || '  chosen OBJECT := OBJECT_CONSTRUCT(); '
 || '  pmin NUMBER(38,6) := NULL; pmax NUMBER(38,6) := NULL; '
 || '  s STRING := ''''; fin ARRAY := ARRAY_CONSTRUCT(); ustmts ARRAY := ARRAY_CONSTRUCT(); '
 || 'BEGIN '
 || '  cnt := (SELECT COUNT(*) FROM ' || :tgt || '.ACTION_REGISTRY WHERE CODE = :P_CODE); '
 || '  IF (:cnt = 0) THEN '
 || '    RETURN ''REFUSED. This build declares no action called '' || :P_CODE || ''.''; '
 || '  END IF; '
 || '  tier := (SELECT UPPER(COALESCE(TIER, ''PRODUCTION'')) FROM ' || :tgt
 || '.ACTION_REGISTRY WHERE CODE = :P_CODE); '
 || '  IF (:tier = ''SAMPLE'') THEN '
 || '    enabled := (SELECT COALESCE(SAMPLE_ACTIONS_ENABLED, FALSE) FROM ' || :tgt
 || '.V_BUILD_CONTEXT LIMIT 1); '
 || '    IF (NOT COALESCE(:enabled, FALSE)) THEN '
 || '      RETURN ''REFUSED. This build was created with MERCHANT_ALLOW_SAMPLE_ACTIONS = '
 || 'FALSE, so even the seeded-data actions are inert. Re-run the script with it set '
 || 'to TRUE to arm them.''; '
 || '    END IF; '
 || '  ELSE '
 || '    enabled := (SELECT ACTIONS_ENABLED FROM ' || :tgt || '.V_BUILD_CONTEXT LIMIT 1); '
 || '    IF (NOT COALESCE(:enabled, FALSE)) THEN '
 || '      RETURN ''REFUSED. '' || :tier || '' actions touch real data and this build was '
 || 'created with MERCHANT_ALLOW_ACTIONS = FALSE, so nothing in the app can change '
 || 'anything of yours. Re-run the script with it set to TRUE to arm them.''; '
 || '    END IF; '
 || '  END IF; '
 || '  IF (:P_CONFIRM IS NULL OR UPPER(TRIM(:P_CONFIRM)) <> UPPER(TRIM(:P_CODE))) THEN '
 || '    RETURN ''REFUSED. Type the action code exactly to confirm it.''; '
 || '  END IF; '
 || '  SELECT LABEL, EST_CREDITS, RUN_SQL, TO_JSON(UNDO_SQL), PARAM_SPEC '
 || '    INTO :lbl, :est, :sqls, :usnap, :pspec '
 || '    FROM ' || :tgt || '.ACTION_REGISTRY WHERE CODE = :P_CODE; '
    -- ── Parameters: validate EVERYTHING before a single statement runs ──────────
    -- Order matters. This whole block sits BEFORE the ACTION_LOG insert and before
    -- the execution loop, so a refusal here has applied nothing at all -- which is
    -- what makes refuse-the-whole-action free rather than a rollback problem. A
    -- partially-applied change is the thing this framework works hardest to prevent,
    -- so a single bad value stops the entire action rather than running the subset
    -- that happened to validate.
 || '  pobj := COALESCE(TRY_PARSE_JSON(:P_PARAMS)::OBJECT, OBJECT_CONSTRUCT()); '
    -- Values sent to an action that declares none are a REFUSAL, not something to
    -- ignore. Silently dropping them would mean the caller believes it constrained
    -- the action and the action did something broader -- and the log would agree
    -- with the action, not the caller.
 || '  IF (ARRAY_SIZE(:pspec) = 0 AND ARRAY_SIZE(OBJECT_KEYS(:pobj)) > 0) THEN '
 || '    RETURN ''REFUSED. '' || :P_CODE || '' declares no parameters, but values were '
 || 'supplied for it. Nothing was run.''; '
 || '  END IF; '
 || '  WHILE (:k < ARRAY_SIZE(:pspec)) DO '
 || '    pj := GET(:pspec, :k); '
 || '    pname := pj:name::STRING; '
 || '    pkind := UPPER(COALESCE(pj:kind::STRING, ''IDENT'')); '
 || '    asql := pj:allowed_sql::STRING; '
 || '    pval := GET(:pobj, :pname)::STRING; '
 || '    IF (:pval IS NULL OR TRIM(:pval) = '''') THEN '
 || '      RETURN ''REFUSED. '' || :P_CODE || '' needs a value for '' || :pname '
 || '        || ''. Nothing was run.''; '
 || '    END IF; '
 || '    IF (:pkind = ''STRING'') THEN '
    -- ── A LITERAL VALUE, not an identifier ──────────────────────────────────────
    -- Some parameters land inside a string literal rather than in an object position
    -- -- an audience NAME is stored in a column, it does not name anything. Those
    -- cannot be identifier-quoted (a name with a space is legitimate) and they still
    -- cannot be bound, because RUN_ACTION EXECUTE IMMEDIATEs pre-built statement text.
    --
    -- TWO defences, again, because escaping alone is the thing that goes wrong quietly:
    --   1. A conservative CHARACTER ALLOWLIST -- letters, digits, space and a few
    --      punctuation marks that appear in real names. No single quote, no double
    --      quote, no backslash, no semicolon, no comment marker. This is a permit-list,
    --      so a character nobody thought about is refused rather than passed through.
    --   2. Quote DOUBLING on top, so even if the allowlist were later widened by
    --      someone, a quote could not terminate the literal.
    -- Length is capped so a parameter cannot be used to push a statement past a limit.
 || '      IF (LENGTH(:pval) > 200) THEN '
 || '        RETURN ''REFUSED. '' || :pname || '' is longer than 200 characters. '
 || 'Nothing was run.''; '
 || '      END IF; '
 || '      IF (NOT REGEXP_LIKE(:pval, ''[A-Za-z0-9 _.,()\\-]+'')) THEN '
 || '        RETURN ''REFUSED. '' || :pname || '' contains a character that is not '
 || 'permitted in a name. Letters, digits, spaces and _ . , ( ) - are allowed. '
 || 'Nothing was run.''; '
 || '      END IF; '
    -- The literal is emitted WITHOUT its surrounding quotes: the statement in the
    -- solution supplies those, exactly as it does for any other literal it writes, so
    -- '<<audience_name>>' reads as a literal in the source and stays one.
 || '      emit := REPLACE(:pval, '''''''', ''''''''''''); '
 || '      canon := :pval; '
 || '      IF (NOT COALESCE(pj:freeform::BOOLEAN, FALSE) '
 || '          AND ARRAY_SIZE(COALESCE(pj:options::ARRAY, ARRAY_CONSTRUCT())) = 0) THEN '
 || '        RETURN ''REFUSED. '' || :pname || '' declares no permitted values and is not '
 || 'marked freeform. Nothing was run.''; '
 || '      END IF; '
 || '    ELSEIF (:pkind = ''NUMBER'') THEN '
    -- A number is still interpolated, because clauses like ARCHIVE_FOR_DAYS = 90 are
    -- DDL and cannot be bound any more than an identifier can. The parse is the gate:
    -- it returns NULL rather than raising, so a non-numeric arrives here as a refusal
    -- instead of an exception, and the emitted text is the PARSED number rather than
    -- the caller's string -- verified: '180 OR 1=1' parses to NULL, so it cannot
    -- survive as text.
    --
    -- TRY_TO_DECIMAL(_, 38, 6), NOT TRY_TO_NUMBER. TRY_TO_NUMBER defaults to scale 0
    -- and SILENTLY ROUNDS: TRY_TO_NUMBER('90.5') is 91, verified. A parameter that
    -- quietly becomes a different number than the one chosen is worse than one that
    -- is refused.
 || '      num := TRY_TO_DECIMAL(:pval, 38, 6); '
 || '      IF (:num IS NULL) THEN '
 || '        RETURN ''REFUSED. '' || :pname || '' must be a number. Nothing was run.''; '
 || '      END IF; '
 || '      pmin := pj:min::NUMBER(38,6); pmax := pj:max::NUMBER(38,6); '
 || '      IF ((:pmin IS NOT NULL AND :num < :pmin) '
 || '          OR (:pmax IS NOT NULL AND :num > :pmax)) THEN '
 || '        RETURN ''REFUSED. '' || :pname || '' = '' || :pval || '' is outside the '
 || 'permitted range '' || COALESCE(:pmin::STRING, ''-'') || '' to '' '
 || '          || COALESCE(:pmax::STRING, ''-'') || ''. Nothing was run.''; '
 || '      END IF; '
    -- Emit 180, never 180.000000. These values land in identifier positions as well as
    -- value positions -- DEMO_COOL_POLICY_180 is a name and DEMO_COOL_POLICY_180.000000
    -- is a syntax error -- so a NUMBER(38,6) cast straight to STRING breaks the
    -- statement. Found live: the first parameterised run failed to compile on exactly
    -- this. A genuinely fractional value keeps its decimals with trailing zeros
    -- trimmed, so 90.5 stays 90.5.
 || '      IF (:num = TRUNC(:num)) THEN '
 || '        emit := :num::INT::STRING; '
 || '      ELSE '
 || '        emit := REGEXP_REPLACE(REGEXP_REPLACE(:num::STRING, ''0+$'', ''''), ''[.]$'', ''''); '
 || '      END IF; '
 || '      canon := :emit; '
 || '    ELSE '
    -- ── Gate 1: SHAPE, per dot-separated part ───────────────────────────────────
    -- Independent of the whitelist on purpose. The whitelist is only ever as good as
    -- the allowed_sql a future author writes; point it at a free-text column and it
    -- authorises arbitrary text. This gate holds regardless. REGEXP_LIKE in Snowflake
    -- matches the ENTIRE string -- verified, not assumed: ''ORDERS; DROP'' is FALSE
    -- against this pattern, as are a space and a double quote. Do not "fix" this
    -- pattern by adding anchors and do not relax it to a partial match.
    --
    -- Split on ''.'' so a qualified name is checked part by part. A name genuinely
    -- containing a dot is refused here rather than silently mis-parsed into the wrong
    -- number of parts.
 || '      parts := SPLIT(:pval, ''.''); jj := 0; '
 || '      WHILE (:jj < ARRAY_SIZE(:parts)) DO '
 || '        IF (NOT REGEXP_LIKE(GET(:parts, :jj)::STRING, ''[A-Za-z_][A-Za-z0-9_$]*'')) THEN '
 || '          RETURN ''REFUSED. '' || :pname || '' = '' || :pval || '' is not a valid '
 || 'identifier. Nothing was run.''; '
 || '        END IF; '
 || '        jj := :jj + 1; '
 || '      END WHILE; '
    -- ── Gate 2: MEMBERSHIP, which also returns the CANONICAL SPELLING ───────────
    -- DEFAULT DENY. A parameter must declare where its permitted values come from --
    -- allowed_sql (a query) or options (a literal list) -- and if it declares neither
    -- the action is REFUSED rather than falling back to the shape gate alone. An author
    -- who simply forgets allowed_sql would otherwise get an identifier accepted on shape
    -- alone and never know, which is the quiet failure this feature exists to avoid.
    -- Freeform has to be asked for in writing, and is only appropriate for a NAME BEING
    -- CREATED, which cannot be checked against things that already exist.
    --
    -- Both sources are enforced HERE, server-side. options is not merely what the app
    -- offers: a list the host renders but the procedure does not check is a dropdown
    -- pretending to be a control.
    --
    -- The comparison is case-INSENSITIVE but what gets emitted is the ALLOWED SET''S OWN
    -- SPELLING, never the caller''s. This matters specifically because the value is
    -- emitted QUOTED: a caller typing ''event_ts'' against a column stored as EVENT_TS
    -- matches, and emitting their casing would produce "event_ts", which is a DIFFERENT
    -- and non-existent object. Verified live -- the case-insensitive match accepted the
    -- lowercase spelling, which is correct, and only canonicalising makes the resulting
    -- identifier resolve. It also means a column genuinely stored lowercase is quoted in
    -- ITS spelling and resolves too.
 || '      canon := NULL; '
 || '      IF (:asql IS NOT NULL AND TRIM(:asql) <> '''') THEN '
    -- The whitelist query comes from the REGISTRY, never from the caller, so the app
    -- cannot influence what its own value is checked against. The value is BOUND rather
    -- than concatenated -- the point of the check is to constrain an attacker-controlled
    -- string, so the check itself must not concatenate one.
    --
    -- allowed_sql must expose a column named ALLOWED_VALUE. Requiring a NAME rather than
    -- reading position 1 means an author widening their SELECT list cannot silently
    -- change which column authorises values.
 || '        EXECUTE IMMEDIATE ''SELECT MAX(TO_VARCHAR(a.ALLOWED_VALUE)) FROM ('' || :asql '
 || '          || '') a WHERE UPPER(TO_VARCHAR(a.ALLOWED_VALUE)) = UPPER(?)'' USING (pval); '
 || '        SELECT $1 INTO :canon FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())); '
 || '        IF (:canon IS NULL) THEN '
 || '          RETURN ''REFUSED. '' || :pname || '' = '' || :pval || '' is not one of the '
 || 'values this build discovered for it. Nothing was run.''; '
 || '        END IF; '
 || '      ELSE '
 || '        opts := COALESCE(pj:options::ARRAY, ARRAY_CONSTRUCT()); '
 || '        IF (ARRAY_SIZE(:opts) > 0) THEN '
    -- A plain loop rather than FLATTEN over a local VARIANT: that construct raised
    -- EXPRESSION_ERROR inside a procedure body when it was tried, and a loop cannot.
 || '          jj := 0; '
 || '          WHILE (:jj < ARRAY_SIZE(:opts)) DO '
 || '            IF (UPPER(GET(:opts, :jj)::STRING) = UPPER(:pval)) THEN '
 || '              canon := GET(:opts, :jj)::STRING; '
 || '              BREAK; '
 || '            END IF; '
 || '            jj := :jj + 1; '
 || '          END WHILE; '
 || '          IF (:canon IS NULL) THEN '
 || '            RETURN ''REFUSED. '' || :pname || '' = '' || :pval || '' is not one of the '
 || 'permitted values for it. Nothing was run.''; '
 || '          END IF; '
 || '        ELSEIF (COALESCE(pj:freeform::BOOLEAN, FALSE)) THEN '
    -- Freeform: there is no set to canonicalise against, so the caller''s spelling IS
    -- the name being created. It has already passed the shape gate.
 || '          canon := :pval; '
 || '        ELSE '
 || '          RETURN ''REFUSED. '' || :pname || '' declares no permitted values and is not '
 || 'marked freeform, so this build cannot say what it is allowed to be. Nothing was run. '
 || 'This is a defect in the solution, not in what you chose.''; '
 || '        END IF; '
 || '      END IF; '
    -- ── Quote the CANONICAL value, part by part ─────────────────────────────────
    -- "DB"."SCHEMA"."TABLE", not "DB.SCHEMA.TABLE" -- the latter names one object with
    -- dots in it. ENUM values are emitted BARE because they land in positions like
    -- ARCHIVE_TIER = COOL where a quoted string is not valid syntax; the shape gate
    -- already refused anything that is not a bare word, so an unquoted enum still
    -- cannot carry punctuation.
 || '      parts := SPLIT(:canon, ''.''); jj := 0; emit := ''''; '
 || '      WHILE (:jj < ARRAY_SIZE(:parts)) DO '
 || '        part := GET(:parts, :jj)::STRING; '
 || '        IF (:pkind = ''ENUM'') THEN '
 || '          emit := :emit || IFF(:jj = 0, '''', ''.'') || :part; '
 || '        ELSE '
 || '          emit := :emit || IFF(:jj = 0, '''', ''.'') || ''"'' || :part || ''"''; '
 || '        END IF; '
 || '        jj := :jj + 1; '
 || '      END WHILE; '
 || '    END IF; '
 || '    resolved := OBJECT_INSERT(:resolved, :pname, :emit, TRUE); '
 || '    chosen := OBJECT_INSERT(:chosen, :pname, :canon, TRUE); '
 || '    k := :k + 1; '
 || '  END WHILE; '
    -- ── Interpolation, over validated text only ────────────────────────────────
    -- Both the forward statements AND the reverse ones, because the reverse set is
    -- snapshotted below and an undo must reverse THE SAME target. Resolving undo here
    -- is what makes that structural rather than a promise: UNDO_ACTION replays text
    -- that was already resolved, so it cannot be handed different values later.
 || '  pkeys := OBJECT_KEYS(:resolved); '
 || '  ustmts := PARSE_JSON(:usnap)::ARRAY; '
 || '  i := 0; '
 || '  WHILE (:i < ARRAY_SIZE(:sqls)) DO '
 || '    s := GET(:sqls, :i)::STRING; kk := 0; '
 || '    WHILE (:kk < ARRAY_SIZE(:pkeys)) DO '
 || '      s := REPLACE(:s, ''<<'' || GET(:pkeys, :kk)::STRING || ''>>'', '
 || '                   GET(:resolved, GET(:pkeys, :kk)::STRING)::STRING); '
 || '      kk := :kk + 1; '
 || '    END WHILE; '
    -- A placeholder left over means the statement names a parameter the action did not
    -- declare -- a typo between the two. Refusing beats executing DDL with a literal
    -- <<tbl>> in it, and beats the silent alternative of leaving it to fail with a
    -- syntax error that points at the wrong thing.
 || '    IF (REGEXP_LIKE(:s, ''.*<<[A-Za-z0-9_]+>>.*'', ''s'')) THEN '
 || '      RETURN ''REFUSED. Statement '' || (:i + 1) || '' of '' || :P_CODE '
 || '        || '' contains a placeholder this action does not declare. Nothing was run.''; '
 || '    END IF; '
 || '    fin := ARRAY_APPEND(:fin, :s); '
 || '    i := :i + 1; '
 || '  END WHILE; '
 || '  sqls := :fin; fin := ARRAY_CONSTRUCT(); i := 0; '
 || '  WHILE (:i < ARRAY_SIZE(:ustmts)) DO '
 || '    s := GET(:ustmts, :i)::STRING; kk := 0; '
 || '    WHILE (:kk < ARRAY_SIZE(:pkeys)) DO '
 || '      s := REPLACE(:s, ''<<'' || GET(:pkeys, :kk)::STRING || ''>>'', '
 || '                   GET(:resolved, GET(:pkeys, :kk)::STRING)::STRING); '
 || '      kk := :kk + 1; '
 || '    END WHILE; '
 || '    IF (REGEXP_LIKE(:s, ''.*<<[A-Za-z0-9_]+>>.*'', ''s'')) THEN '
 || '      RETURN ''REFUSED. Reverse statement '' || (:i + 1) || '' of '' || :P_CODE '
 || '        || '' contains a placeholder this action does not declare. Nothing was run, '
 || 'because an action whose undo cannot resolve must not run in the first place.''; '
 || '    END IF; '
 || '    fin := ARRAY_APPEND(:fin, :s); '
 || '    i := :i + 1; '
 || '  END WHILE; '
 || '  usnap := TO_JSON(:fin); i := 0; '
    -- The reverse statements are SNAPSHOTTED onto this run, not read from the
    -- registry when the undo happens. The registry holds what the action CURRENTLY
    -- declares; a rebuild between the run and the undo can change that, and then the
    -- undo reverses a different set of objects than the run created. Storing them
    -- here means an undo can only ever replay what THIS run was going to do.
    -- Stored as JSON text rather than ARRAY because an ARRAY bind through
    -- INSERT..SELECT is fragile, and TO_JSON/PARSE_JSON round-trips exactly.
 || '  INSERT INTO ' || :tgt || '.ACTION_LOG '
 || '    (LOG_ID, CODE, LABEL, EST_CREDITS, STATUS, UNDO_SNAPSHOT, PARAMS) '
 || '    SELECT :log_id, :P_CODE, :lbl, :est, ''RUNNING'', :usnap, '
    -- The RESOLVED values, not the raw input: what the statements were actually built
    -- with. NULL when the action takes none, so an unparameterised row reads as having
    -- had none rather than as an empty object that might mean anything.
 || '           IFF(ARRAY_SIZE(OBJECT_KEYS(:chosen)) = 0, NULL, TO_JSON(:chosen)); '
    -- :i indexes the ARRAY from 0, but every number this procedure SHOWS a
    -- human is :i + 1. Sabotaging the second statement of an action originally
    -- produced "statement 1: SQL compilation error", which points at the wrong
    -- DDL -- the single most expensive kind of wrong in an error message.
 || '  WHILE (:i < ARRAY_SIZE(:sqls)) DO '
 || '    BEGIN '
 || '      EXECUTE IMMEDIATE GET(:sqls, :i)::STRING; '
 || '      INSERT INTO ' || :tgt || '.ACTION_STATEMENT_LOG '
 || '        (LOG_ID, SEQ, STATEMENT, QUERY_ID, STATUS) '
 || '        SELECT :log_id, :i + 1, LEFT(GET(:sqls, :i)::STRING, 4000), '
 || '               LAST_QUERY_ID(), ''OK''; '
 || '      ran := :ran + 1; '
 || '    EXCEPTION WHEN OTHER THEN '
 || '      errs := ''statement '' || (:i + 1) || '': '' || SQLERRM; '
 || '      INSERT INTO ' || :tgt || '.ACTION_STATEMENT_LOG '
 || '        (LOG_ID, SEQ, STATEMENT, STATUS, ERROR) '
 || '        SELECT :log_id, :i + 1, LEFT(GET(:sqls, :i)::STRING, 4000), ''FAILED'', :errs; '
 || '      BREAK; '
 || '    END; '
 || '    i := :i + 1; '
 || '  END WHILE; '
 || '  UPDATE ' || :tgt || '.ACTION_LOG SET STATUS = IFF(:errs = '''', ''DONE'', ''FAILED''), '
 || '    STATEMENTS_RUN = :ran, ERROR = NULLIF(:errs, ''''), '
 || '    FINISHED_AT = CURRENT_TIMESTAMP() WHERE LOG_ID = :log_id; '
 || '  IF (:errs <> '''') THEN '
 || '    RETURN ''FAILED after '' || :ran || '' statement(s), nothing further was run. '' || :errs; '
 || '  END IF; '
 || '  RETURN ''DONE. '' || :lbl '
    -- Name the values in the RETURN, not just in the log. The message is the only
    -- thing most readers see, and "DONE. Attach the policy" is the same sentence
    -- whichever table it just tiered.
 || '    || IFF(ARRAY_SIZE(:pkeys) = 0, '''', '' on '' || TO_JSON(:chosen)) '
 || '    || '' -- '' || :ran || '' statement(s) ran. Estimated '' '
 || '    || :est || '' credits. V_ACTION_COST reconciles that against what Snowflake '' '
 || '    || ''actually charged, and its MEASURED_STATUS column says whether a '' '
 || '    || ''measurement is pending, partial, or will never arrive because the '' '
 || '    || ''statements consumed no warehouse compute.''; '
 || 'END');

  -- ── The two-argument form every existing solution and test already calls ────
  -- A DELEGATE, not a copy. There is exactly ONE implementation of the three gates
  -- and the parameter resolver, and this signature reaches it with an empty parameter
  -- object. Duplicating the body to "keep the simple path simple" would put a second
  -- copy of a safety gate in the file, and a duplicated gate is a gate that rots --
  -- F2 needed a dedicated in-sync assertion for exactly that reason.
  --
  -- So the 27 solutions that declare no parameters, and gauntlet step 12 which calls
  -- RUN_ACTION(code, confirm) positionally, keep working unchanged and still get
  -- every gate.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE PROCEDURE ' || :tgt || '.RUN_ACTION(P_CODE VARCHAR, P_CONFIRM VARCHAR) '
 || 'RETURNS VARCHAR LANGUAGE SQL EXECUTE AS CALLER AS '
 || 'DECLARE r STRING := ''''; '
 || 'BEGIN '
 || '  CALL ' || :tgt || '.RUN_ACTION(:P_CODE, :P_CONFIRM, NULL) INTO :r; '
 || '  RETURN :r; '
 || 'END');

  -- ── Undoing one action, without taking the rest down with it ───────────────
  -- Until this existed the only undo was TEARDOWN(), which drops the whole schema.
  -- That is a fine answer to "remove the demo" and a useless answer to "I pressed
  -- the production button, show me it comes back" -- it destroys the evidence
  -- along with the change. This reverses ONE action and leaves everything else
  -- standing, which is the thing you actually want before you press it for real.
  --
  -- Same three gates as RUN_ACTION, deliberately. An undo is itself a change to
  -- the account: reversing a masking policy EXPOSES a column again. It is not
  -- inherently the safe direction and does not get a weaker door.
  --
  -- DELIBERATELY NOT PARAMETERISED, and this is a safety decision rather than an
  -- omission. RUN_ACTION resolves the reverse statements and snapshots them ALREADY
  -- RESOLVED, so the undo replays the exact text built for that run. Giving this
  -- procedure a parameter argument would let a caller undo with DIFFERENT values than
  -- the run used -- an undo that reverses a different target than the action touched,
  -- which is worse than having no undo at all. The only reverse statements reachable
  -- here are the ones the run itself produced.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE PROCEDURE ' || :tgt || '.UNDO_ACTION(P_CODE VARCHAR, P_CONFIRM VARCHAR) '
 || 'RETURNS VARCHAR LANGUAGE SQL EXECUTE AS CALLER AS '
 || 'DECLARE '
 || '  enabled BOOLEAN := FALSE; lbl STRING := ''''; tier STRING := ''''; '
 || '  sqls ARRAY := ARRAY_CONSTRUCT(); last_st STRING := NULL; usnap STRING := NULL; '
 || '  i INT := 0; ran INT := 0; errs STRING := ''''; e1 STRING := ''''; '
 || '  log_id STRING := UUID_STRING(); cnt INT := 0; '
 || 'BEGIN '
 || '  cnt := (SELECT COUNT(*) FROM ' || :tgt || '.ACTION_REGISTRY WHERE CODE = :P_CODE); '
 || '  IF (:cnt = 0) THEN '
 || '    RETURN ''REFUSED. This build declares no action called '' || :P_CODE || ''.''; '
 || '  END IF; '
    -- Tier-aware, exactly as RUN_ACTION. Undo has to be reachable under the SAME
    -- authorisation that let the action run, or SAMPLE actions become one-way: the
    -- button works, the reversal refuses, and the seeded objects are stranded until
    -- TEARDOWN(). Unknown tiers fall to the stricter gate, as above.
 || '  tier := (SELECT UPPER(COALESCE(TIER, ''PRODUCTION'')) FROM ' || :tgt
 || '.ACTION_REGISTRY WHERE CODE = :P_CODE); '
 || '  IF (:tier = ''SAMPLE'') THEN '
 || '    enabled := (SELECT COALESCE(SAMPLE_ACTIONS_ENABLED, FALSE) FROM ' || :tgt
 || '.V_BUILD_CONTEXT LIMIT 1); '
 || '    IF (NOT COALESCE(:enabled, FALSE)) THEN '
 || '      RETURN ''REFUSED. This build was created with MERCHANT_ALLOW_SAMPLE_ACTIONS = FALSE.''; '
 || '    END IF; '
 || '  ELSE '
 || '    enabled := (SELECT ACTIONS_ENABLED FROM ' || :tgt || '.V_BUILD_CONTEXT LIMIT 1); '
 || '    IF (NOT COALESCE(:enabled, FALSE)) THEN '
 || '      RETURN ''REFUSED. This build was created with MERCHANT_ALLOW_ACTIONS = FALSE.''; '
 || '    END IF; '
 || '  END IF; '
 || '  IF (:P_CONFIRM IS NULL OR UPPER(TRIM(:P_CONFIRM)) <> UPPER(TRIM(:P_CODE))) THEN '
 || '    RETURN ''REFUSED. Type the action code exactly to confirm it.''; '
 || '  END IF; '
 || '  SELECT LABEL INTO :lbl FROM ' || :tgt
 || '    .ACTION_REGISTRY WHERE CODE = :P_CODE; '
    -- Prefer the snapshot taken when the action ran. Fall back to what the registry
    -- declares now, for a schema built before UNDO_SNAPSHOT existed -- that is the
    -- old, less precise behaviour, and it is better than refusing to undo at all.
 || '  BEGIN '
 || '    SELECT UNDO_SNAPSHOT INTO :usnap FROM ' || :tgt || '.ACTION_LOG '
 || '      WHERE CODE = :P_CODE AND STATUS = ''DONE'' '
 || '      ORDER BY FINISHED_AT DESC LIMIT 1; '
 || '  EXCEPTION WHEN OTHER THEN usnap := NULL; END; '
 || '  IF (:usnap IS NOT NULL) THEN '
 || '    sqls := PARSE_JSON(:usnap)::ARRAY; '
 || '  ELSE '
 || '    SELECT UNDO_SQL INTO :sqls FROM ' || :tgt
 || '      .ACTION_REGISTRY WHERE CODE = :P_CODE; '
 || '  END IF; '
 || '  IF (ARRAY_SIZE(:sqls) = 0) THEN '
 || '    RETURN ''REFUSED. '' || :P_CODE || '' declares no reverse statements. Read its '
|| 'undo text -- some changes are only reversible by hand, and pretending otherwise '
|| 'would be worse than saying so.''; '
 || '  END IF; '
    -- An unresolved placeholder can only reach here down the FALLBACK path above --
    -- a parameterised action whose run predates UNDO_SNAPSHOT, so the registry's own
    -- unresolved text was loaded instead. Executing it would run DDL containing a
    -- literal <<tbl>>; guessing a value would reverse a target this run may never have
    -- touched. Both are worse than refusing and saying which action it was.
 || '  i := 0; '
 || '  WHILE (:i < ARRAY_SIZE(:sqls)) DO '
 || '    IF (REGEXP_LIKE(GET(:sqls, :i)::STRING, ''.*<<[A-Za-z0-9_]+>>.*'', ''s'')) THEN '
 || '      RETURN ''REFUSED. '' || :P_CODE || '' takes parameters and no resolved reverse '
|| 'statements were recorded for the run being undone, so the values it used are not '
|| 'known. Run it again to record them; nothing was reversed.''; '
 || '    END IF; '
 || '    i := :i + 1; '
 || '  END WHILE; '
 || '  i := 0; '
    -- Refusing to undo something that was never done is not pedantry. Running the
    -- reverse of an un-run action can itself be destructive: the reverse of "attach
    -- a masking policy" is "unset it", which on a column somebody ELSE masked would
    -- quietly strip their protection.
    -- COUNT of DONE rows is the WRONG question: it stays true forever, so a second
    -- undo sailed past this guard and reported UNDONE again having done nothing.
    -- Verified live -- it was harmless only because the first undo had already
    -- emptied the registry it reads. The right question is what happened LAST.
 || '  last_st := (SELECT STATUS FROM ' || :tgt || '.ACTION_LOG '
 || '              WHERE CODE = :P_CODE AND STATUS IN (''DONE'', ''UNDONE'') '
 || '              ORDER BY FINISHED_AT DESC LIMIT 1); '
 || '  IF (:last_st IS NULL) THEN '
 || '    RETURN ''REFUSED. '' || :P_CODE || '' has not completed on this build, so there '
|| 'is nothing to reverse.''; '
 || '  END IF; '
 || '  IF (:last_st = ''UNDONE'') THEN '
 || '    RETURN ''REFUSED. '' || :P_CODE || '' has already been undone. Run it again '
|| 'before undoing it again.''; '
 || '  END IF; '
 || '  INSERT INTO ' || :tgt || '.ACTION_LOG (LOG_ID, CODE, LABEL, EST_CREDITS, STATUS) '
 || '    SELECT :log_id, :P_CODE, ''UNDO: '' || :lbl, 0, ''UNDOING''; '
 || '  WHILE (:i < ARRAY_SIZE(:sqls)) DO '
 || '    BEGIN '
 || '      EXECUTE IMMEDIATE GET(:sqls, :i)::STRING; '
 || '      INSERT INTO ' || :tgt || '.ACTION_STATEMENT_LOG '
 || '        (LOG_ID, SEQ, STATEMENT, QUERY_ID, STATUS) '
 || '        SELECT :log_id, :i + 1, LEFT(GET(:sqls, :i)::STRING, 4000), '
 || '               LAST_QUERY_ID(), ''OK''; '
 || '      ran := :ran + 1; '
    -- An undo does NOT stop at the first failure, which is the opposite of
    -- RUN_ACTION. Half-applying a change is bad; half-REVERSING one leaves the
    -- account in a state neither the action nor the undo describes, so it pushes on
    -- and reports everything that went wrong. Every statement is logged either way.
 || '    EXCEPTION WHEN OTHER THEN '
 || '      e1 := ''statement '' || (:i + 1) || '': '' || SQLERRM; '
 || '      errs := :errs || :e1 || ''; ''; '
 || '      INSERT INTO ' || :tgt || '.ACTION_STATEMENT_LOG '
 || '        (LOG_ID, SEQ, STATEMENT, STATUS, ERROR) '
 || '        SELECT :log_id, :i + 1, LEFT(GET(:sqls, :i)::STRING, 4000), ''FAILED'', :e1; '
 || '    END; '
 || '    i := :i + 1; '
 || '  END WHILE; '
 || '  UPDATE ' || :tgt || '.ACTION_LOG SET STATUS = IFF(:errs = '''', ''UNDONE'', ''FAILED''), '
 || '    STATEMENTS_RUN = :ran, ERROR = NULLIF(:errs, ''''), '
 || '    FINISHED_AT = CURRENT_TIMESTAMP() WHERE LOG_ID = :log_id; '
 || '  IF (:errs <> '''') THEN '
 || '    RETURN ''PARTIALLY UNDONE. '' || :ran || '' of '' || ARRAY_SIZE(:sqls) '
 || '      || '' statement(s) succeeded. '' || :errs; '
 || '  END IF; '
 || '  RETURN ''UNDONE. '' || :lbl || '' -- '' || :ran || '' reverse statement(s) ran. '' '
 || '    || ''The action can be run again.''; '
 || 'END');
  cost_once := :cost_once + 0.01;
  IF (ARRAY_SIZE(:actions) > 0) THEN
    notes := ARRAY_APPEND(:notes,
      'THIS BUILD DECLARES ' || ARRAY_SIZE(:actions) || ' ACTION(S) the app can offer. '
   || IFF(:allow_actions,
          'MERCHANT_ALLOW_ACTIONS is TRUE, so they are ARMED: a user of the dashboard can '
       || 'run them after typing the action code to confirm. Every attempt is recorded '
       || 'in ACTION_LOG.',
          'MERCHANT_ALLOW_ACTIONS is FALSE, so every button is inert and RUN_ACTION refuses. '
       || 'The app still shows what each action would do and what it would cost.'));
    LET ai INT := 0;
    WHILE (:ai < ARRAY_SIZE(:actions)) DO
      notes := ARRAY_APPEND(:notes,
        '  ACTION ' || GET(:actions, :ai):tier::STRING || ' · '
     || GET(:actions, :ai):code::STRING || ' — '
     || GET(:actions, :ai):label::STRING || '  (~'
     || GET(:actions, :ai):est::STRING || ' credits: '
     || GET(:actions, :ai):basis::STRING || ')');
      ai := :ai + 1;
    END WHILE;
  END IF;

  stmts := ARRAY_APPEND(:stmts,
    'CREATE TABLE IF NOT EXISTS ' || :tgt || '.APP_CUSTOMIZATION (ID VARCHAR, CONFIG VARIANT)');
  stmts := ARRAY_APPEND(:stmts,
    'INSERT INTO ' || :tgt || '.APP_CUSTOMIZATION (ID, CONFIG) '
 || 'SELECT ''default'', PARSE_JSON(''{"version":1}'') '
 || 'WHERE NOT EXISTS (SELECT 1 FROM ' || :tgt || '.APP_CUSTOMIZATION WHERE ID = ''default'')');
  -- ── Streamlit app: React bundle embedded as base64 ────────────────────────
  -- Generated by harness/bundle.py. Do not edit here; edit ui/ and re-run it.
  -- ui-sources sha256:3ee4df966c173e59
  --
  -- The python host is carried as base64 rather than as a quoted literal, and
  -- that is not tidiness. On its way to the stage it passes through TWO SQL
  -- literal parses -- once into this variable, once when the COPY statement built
  -- below is EXECUTE IMMEDIATEd -- and each parse consumes backslash escapes. A
  -- host line reading  js.replace("</script", "<\\/script")  arrived on the stage
  -- as  js.replace("</script", "</script"),  a silent no-op: the file was four
  -- bytes shorter, nothing failed, and the guard it implemented was simply gone.
  -- Base64 contains no quotes and no backslashes, so it cannot be mangled;
  -- BASE64_DECODE_STRING does the decoding server-side inside the COPY.
  LET py_b64 STRING :=
       'IiIiU3RyZWFtbGl0IGhvc3QgZm9yIGEgb25lc2hvdCBzb2x1dGlvbidzIFVJLiBTSEFSRUQgLS0gb25lIGNvcHkgZm9yIGV2ZXJ5IHNvbHV0aW9uLgoKUnVu'
    || 'cyBpbnNpZGUgU25vd2ZsYWtlIChTdHJlYW1saXQgaW4gU25vd2ZsYWtlKS4gSXRzIHdob2xlIGpvYiBpczoKCiAgMS4gd29yayBvdXQgd2hpY2ggc2NoZW1h'
    || 'IGl0IHdhcyBpbnN0YWxsZWQgaW50bywKICAyLiBydW4gZWFjaCBwYW5lbCdzIFNRTCwgY2F0Y2hpbmcgcGVyLXBhbmVsIGZhaWx1cmVzLAogIDMuIGhhbmQg'
    || 'dGhlIHJvd3MgYW5kIHRoZSBSZWFjdCBidW5kbGUgdG8gc3QuY29tcG9uZW50cy52MS5odG1sLgoKTm9uZSBvZiB0aGF0IHZhcmllcyBiZXR3ZWVuIHNvbHV0'
    || 'aW9ucywgc28gaXQgbGl2ZXMgaGVyZSByYXRoZXIgdGhhbiBiZWluZyBjb3BpZWQKZm91cnRlZW4gdGltZXMgLS0gdGhlIHNhbWUgcmVhc29uIGhhcm5lc3Mv'
    || 'YmxvY2tzLyoudG1wbCBpcyBzaGFyZWQuIEEgc29sdXRpb24Kc3VwcGxpZXMgb25seSBgdWkvcGFuZWxzLnB5YCwgd2hpY2ggYnVuZGxlLnB5IHNwbGljZXMg'
    || 'aW4gYXQgdGhlIFBBTkVMUyBtYXJrZXIKYmVsb3cuIChUaGF0IG1hcmtlciBpcyBub3Qgc3BlbGxlZCBoZXJlIGluIHByb3NlOiBpdCBpcyBzdWJzdGl0dXRl'
    || 'ZCB3aGVyZXZlciBpdAphcHBlYXJzLCBzbyBuYW1pbmcgaXQgaW4gYSBzZW50ZW5jZSBsZWF2ZXMgYSBzZWNvbmQgY29weSBvZiB0aGUgcGFuZWwgZGljdCBp'
    || 'biB0aGUKbWlkZGxlIG9mIHRoaXMgZG9jc3RyaW5nLiBidW5kbGUucHkgcmVmdXNlcyB0aGUgYnVpbGQgaWYgYW55IG1hcmtlciBzdXJ2aXZlcywKd2hpY2gg'
    || 'aXMgaG93IHRoaXMgbGluZSBjYW1lIHRvIGJlIHdvcmRlZCBzbyBjYXJlZnVsbHkuKQoKYnVuZGxlLnB5IHN1YnN0aXR1dGVzIHRoZSBmb3VyIHBsYWNlaG9s'
    || 'ZGVyIHRva2VucyBhc3NpZ25lZCBqdXN0IGJlbG93IGJlZm9yZSB0aGlzCmZpbGUgaXMgZW1iZWRkZWQgaW50byB0aGUgZGVsaXZlcmFibGUgU1FMLiBEbyBO'
    || 'T1Qgc3BlbGwgdGhvc2UgdG9rZW5zIGFueXdoZXJlIGVsc2UKaW4gdGhpcyBmaWxlLCBpbmNsdWRpbmcgaW4gcHJvc2U6IHRoZSBzdWJzdGl0dXRpb24gaXMg'
    || 'YSBwbGFpbiBzdHJpbmcgcmVwbGFjZSwgc28gYQptZW50aW9uIGluIGEgY29tbWVudCBnZXRzIHRoZSBlbnRpcmUgYmFzZTY0IGJ1bmRsZSBwYXN0ZWQgaW50'
    || 'byBpdCBhbmQgc2lsZW50bHkKZG91YmxlcyB0aGUgc2l6ZSBvZiB0aGUgYXJ0aWZhY3QuCgpQZXItcGFuZWwgdHJ5L2V4Y2VwdCBpcyB0aGUgc2FtZSBydWxl'
    || 'IGFzIHRoZSBkaXNjb3ZlcnkgcHJvYmVzIGluIEJsb2NrIDE6IG9uZQptaXNzaW5nIHByaXZpbGVnZSBtdXN0IGNvc3Qgb25lIHBhbmVsLCBub3QgdGhlIHdo'
    || 'b2xlIHBhZ2UuIEEgcGFuZWwgdGhhdCByYWlzZXMgaXMKcmVwb3J0ZWQgdG8gdGhlIFVJIGFzIGFuIGVycm9yIHN0cmluZyBhbmQgcmVuZGVyZWQgYXMgYSB2'
    || 'aXNpYmxlIGZhaWx1cmUgLS0gbmV2ZXIKYXMgYW4gZW1wdHkgdGFibGUsIGJlY2F1c2UgYW4gZW1wdHkgdGFibGUgcmVhZHMgYXMgInlvdSBoYXZlIG5vIGRh'
    || 'dGEiLCB3aGljaCBpcyBhCmNsYWltIGFib3V0IHRoZSBjdXN0b21lcidzIGFjY291bnQgcmF0aGVyIHRoYW4gYWJvdXQgb3VyIHF1ZXJ5LgoiIiIKaW1wb3J0'
    || 'IGJhc2U2NAppbXBvcnQgY29weQppbXBvcnQganNvbgppbXBvcnQgcmUKZnJvbSB0aW1lIGltcG9ydCBtb25vdG9uaWMKCmltcG9ydCBzdHJlYW1saXQgYXMg'
    || 'c3QKZnJvbSBzbm93Zmxha2Uuc25vd3BhcmsuY29udGV4dCBpbXBvcnQgZ2V0X2FjdGl2ZV9zZXNzaW9uCmltcG9ydCBzdHJlYW1saXQuY29tcG9uZW50cy52'
    || 'MSBhcyBjb21wb25lbnRzCgpBUFBfSlNfQjY0ID0gIktHWjFibU4wYVc5dUtDbDdJblZ6WlNCemRISnBZM1FpTzJaMWJtTjBhVzl1SUc5aktIVXBlM0psZEhW'
    || 'eWJpQjFKaVoxTGw5ZlpYTk5iMlIxYkdVbUprOWlhbVZqZEM1d2NtOTBiM1I1Y0dVdWFHRnpUM2R1VUhKdmNHVnlkSGt1WTJGc2JDaDFMQ0prWldaaGRXeDBJ'
    || 'aWsvZFM1a1pXWmhkV3gwT25WOWRtRnlJQ1JzUFh0bGVIQnZjblJ6T250OWZTeFdiajE3ZlN4WGJEMTdaWGh3YjNKMGN6cDdmWDBzV1QxN2ZUc3ZLaW9LSUNv'
    || 'Z1FHeHBZMlZ1YzJVZ1VtVmhZM1FLSUNvZ2NtVmhZM1F1Y0hKdlpIVmpkR2x2Ymk1dGFXNHVhbk1LSUNvS0lDb2dRMjl3ZVhKcFoyaDBJQ2hqS1NCR1lXTmxZ'
    || 'bTl2YXl3Z1NXNWpMaUJoYm1RZ2FYUnpJR0ZtWm1sc2FXRjBaWE11Q2lBcUNpQXFJRlJvYVhNZ2MyOTFjbU5sSUdOdlpHVWdhWE1nYkdsalpXNXpaV1FnZFc1'
    || 'a1pYSWdkR2hsSUUxSlZDQnNhV05sYm5ObElHWnZkVzVrSUdsdUlIUm9aUW9nS2lCTVNVTkZUbE5GSUdacGJHVWdhVzRnZEdobElISnZiM1FnWkdseVpXTjBi'
    || 'M0o1SUc5bUlIUm9hWE1nYzI5MWNtTmxJSFJ5WldVdUNpQXFMM1poY2lCTGJ6dG1kVzVqZEdsdmJpQnpZeWdwZTJsbUtFdHZLWEpsZEhWeWJpQlpPMHR2UFRF'
    || 'N2RtRnlJSFU5VTNsdFltOXNMbVp2Y2lnaWNtVmhZM1F1Wld4bGJXVnVkQ0lwTEdZOVUzbHRZbTlzTG1admNpZ2ljbVZoWTNRdWNHOXlkR0ZzSWlrc1lUMVRl'
    || 'VzFpYjJ3dVptOXlLQ0p5WldGamRDNW1jbUZuYldWdWRDSXBMSGc5VTNsdFltOXNMbVp2Y2lnaWNtVmhZM1F1YzNSeWFXTjBYMjF2WkdVaUtTeE9QVk41YldK'
    || 'dmJDNW1iM0lvSW5KbFlXTjBMbkJ5YjJacGJHVnlJaWtzUXoxVGVXMWliMnd1Wm05eUtDSnlaV0ZqZEM1d2NtOTJhV1JsY2lJcExIazlVM2x0WW05c0xtWnZj'
    || 'aWdpY21WaFkzUXVZMjl1ZEdWNGRDSXBMRjg5VTNsdFltOXNMbVp2Y2lnaWNtVmhZM1F1Wm05eWQyRnlaRjl5WldZaUtTeDNQVk41YldKdmJDNW1iM0lvSW5K'
    || 'bFlXTjBMbk4xYzNCbGJuTmxJaWtzUWoxVGVXMWliMnd1Wm05eUtDSnlaV0ZqZEM1dFpXMXZJaWtzVEQxVGVXMWliMnd1Wm05eUtDSnlaV0ZqZEM1c1lYcDVJ'
    || 'aWtzUVQxVGVXMWliMnd1YVhSbGNtRjBiM0k3Wm5WdVkzUnBiMjRnU0Nob0tYdHlaWFIxY200Z2FEMDlQVzUxYkd4OGZIUjVjR1Z2WmlCb0lUMGliMkpxWldO'
    || 'MElqOXVkV3hzT2lob1BVRW1KbWhiUVYxOGZHaGJJa0JBYVhSbGNtRjBiM0lpWFN4MGVYQmxiMllnYUQwOUltWjFibU4wYVc5dUlqOW9PbTUxYkd3cGZYWmhj'
    || 'aUJ5WlQxN2FYTk5iM1Z1ZEdWa09tWjFibU4wYVc5dUtDbDdjbVYwZFhKdUlURjlMR1Z1Y1hWbGRXVkdiM0pqWlZWd1pHRjBaVHBtZFc1amRHbHZiaWdwZTMw'
    || 'c1pXNXhkV1YxWlZKbGNHeGhZMlZUZEdGMFpUcG1kVzVqZEdsdmJpZ3BlMzBzWlc1eGRXVjFaVk5sZEZOMFlYUmxPbVoxYm1OMGFXOXVLQ2w3Zlgwc1J6MVBZ'
    || 'bXBsWTNRdVlYTnphV2R1TEZnOWUzMDdablZ1WTNScGIyNGdWaWhvTEdzc1VTbDdkR2hwY3k1d2NtOXdjejFvTEhSb2FYTXVZMjl1ZEdWNGREMXJMSFJvYVhN'
    || 'dWNtVm1jejFZTEhSb2FYTXVkWEJrWVhSbGNqMVJmSHh5WlgxV0xuQnliM1J2ZEhsd1pTNXBjMUpsWVdOMFEyOXRjRzl1Wlc1MFBYdDlMRll1Y0hKdmRHOTBl'
    || 'WEJsTG5ObGRGTjBZWFJsUFdaMWJtTjBhVzl1S0dnc2F5bDdhV1lvZEhsd1pXOW1JR2doUFNKdlltcGxZM1FpSmlaMGVYQmxiMllnYUNFOUltWjFibU4wYVc5'
    || 'dUlpWW1hQ0U5Ym5Wc2JDbDBhSEp2ZHlCRmNuSnZjaWdpYzJWMFUzUmhkR1VvTGk0dUtUb2dkR0ZyWlhNZ1lXNGdiMkpxWldOMElHOW1JSE4wWVhSbElIWmhj'
    || 'bWxoWW14bGN5QjBieUIxY0dSaGRHVWdiM0lnWVNCbWRXNWpkR2x2YmlCM2FHbGphQ0J5WlhSMWNtNXpJR0Z1SUc5aWFtVmpkQ0J2WmlCemRHRjBaU0IyWVhK'
    || 'cFlXSnNaWE11SWlrN2RHaHBjeTUxY0dSaGRHVnlMbVZ1Y1hWbGRXVlRaWFJUZEdGMFpTaDBhR2x6TEdnc2F5d2ljMlYwVTNSaGRHVWlLWDBzVmk1d2NtOTBi'
    || 'M1I1Y0dVdVptOXlZMlZWY0dSaGRHVTlablZ1WTNScGIyNG9hQ2w3ZEdocGN5NTFjR1JoZEdWeUxtVnVjWFZsZFdWR2IzSmpaVlZ3WkdGMFpTaDBhR2x6TEdn'
    || 'c0ltWnZjbU5sVlhCa1lYUmxJaWw5TzJaMWJtTjBhVzl1SUVabEtDbDdmVVpsTG5CeWIzUnZkSGx3WlQxV0xuQnliM1J2ZEhsd1pUdG1kVzVqZEdsdmJpQk9a'
    || 'U2hvTEdzc1VTbDdkR2hwY3k1d2NtOXdjejFvTEhSb2FYTXVZMjl1ZEdWNGREMXJMSFJvYVhNdWNtVm1jejFZTEhSb2FYTXVkWEJrWVhSbGNqMVJmSHh5Wlgx'
    || 'MllYSWdUR1U5VG1VdWNISnZkRzkwZVhCbFBXNWxkeUJHWlR0TVpTNWpiMjV6ZEhKMVkzUnZjajFPWlN4SEtFeGxMRll1Y0hKdmRHOTBlWEJsS1N4TVpTNXBj'
    || 'MUIxY21WU1pXRmpkRU52YlhCdmJtVnVkRDBoTUR0MllYSWdiMlU5UVhKeVlYa3VhWE5CY25KaGVTeFZaVDFQWW1wbFkzUXVjSEp2ZEc5MGVYQmxMbWhoYzA5'
    || 'M2JsQnliM0JsY25SNUxGTmxQWHRqZFhKeVpXNTBPbTUxYkd4OUxHcGxQWHRyWlhrNklUQXNjbVZtT2lFd0xGOWZjMlZzWmpvaE1DeGZYM052ZFhKalpUb2hN'
    || 'SDA3Wm5WdVkzUnBiMjRnU1dVb2FDeHJMRkVwZTNaaGNpQkxMRW85ZTMwc2NUMXVkV3hzTEd4bFBXNTFiR3c3YVdZb2F5RTliblZzYkNsbWIzSW9TeUJwYmlC'
    || 'ckxuSmxaaUU5UFhadmFXUWdNQ1ltS0d4bFBXc3VjbVZtS1N4ckxtdGxlU0U5UFhadmFXUWdNQ1ltS0hFOUlpSXJheTVyWlhrcExHc3BWV1V1WTJGc2JDaHJM'
    || 'RXNwSmlZaGFtVXVhR0Z6VDNkdVVISnZjR1Z5ZEhrb1N5a21KaWhLVzB0ZFBXdGJTMTBwTzNaaGNpQjBaVDFoY21kMWJXVnVkSE11YkdWdVozUm9MVEk3YVdZ'
    || 'b2RHVTlQVDB4S1VvdVkyaHBiR1J5Wlc0OVVUdGxiSE5sSUdsbUtERThkR1VwZTJadmNpaDJZWElnWVdVOVFYSnlZWGtvZEdVcExFZGxQVEE3UjJVOGRHVTdS'
    || 'MlVyS3lsaFpWdEhaVjA5WVhKbmRXMWxiblJ6VzBkbEt6SmRPMG91WTJocGJHUnlaVzQ5WVdWOWFXWW9hQ1ltYUM1a1pXWmhkV3gwVUhKdmNITXBabTl5S0Vz'
    || 'Z2FXNGdkR1U5YUM1a1pXWmhkV3gwVUhKdmNITXNkR1VwU2x0TFhUMDlQWFp2YVdRZ01DWW1LRXBiUzEwOWRHVmJTMTBwTzNKbGRIVnlibnNrSkhSNWNHVnZa'
    || 'anAxTEhSNWNHVTZhQ3hyWlhrNmNTeHlaV1k2YkdVc2NISnZjSE02U2l4ZmIzZHVaWEk2VTJVdVkzVnljbVZ1ZEgxOVpuVnVZM1JwYjI0Z2NHVW9hQ3hyS1h0'
    || 'eVpYUjFjbTU3SkNSMGVYQmxiMlk2ZFN4MGVYQmxPbWd1ZEhsd1pTeHJaWGs2YXl4eVpXWTZhQzV5WldZc2NISnZjSE02YUM1d2NtOXdjeXhmYjNkdVpYSTZh'
    || 'QzVmYjNkdVpYSjlmV1oxYm1OMGFXOXVJR3AwS0dncGUzSmxkSFZ5YmlCMGVYQmxiMllnYUQwOUltOWlhbVZqZENJbUptZ2hQVDF1ZFd4c0ppWm9MaVFrZEhs'
    || 'd1pXOW1QVDA5ZFgxbWRXNWpkR2x2YmlCMGJpaG9LWHQyWVhJZ2F6MTdJajBpT2lJOU1DSXNJam9pT2lJOU1pSjlPM0psZEhWeWJpSWtJaXRvTG5KbGNHeGhZ'
    || 'MlVvTDFzOU9sMHZaeXhtZFc1amRHbHZiaWhSS1h0eVpYUjFjbTRnYTF0UlhYMHBmWFpoY2lCNWREMHZYQzhyTDJjN1puVnVZM1JwYjI0Z1MyVW9hQ3hyS1h0'
    || 'eVpYUjFjbTRnZEhsd1pXOW1JR2c5UFNKdlltcGxZM1FpSmlab0lUMDliblZzYkNZbWFDNXJaWGtoUFc1MWJHdy9kRzRvSWlJcmFDNXJaWGtwT21zdWRHOVRk'
    || 'SEpwYm1jb016WXBmV1oxYm1OMGFXOXVJR0YwS0dnc2F5eFJMRXNzU2lsN2RtRnlJSEU5ZEhsd1pXOW1JR2c3S0hFOVBUMGlkVzVrWldacGJtVmtJbng4Y1Qw'
    || 'OVBTSmliMjlzWldGdUlpa21KaWhvUFc1MWJHd3BPM1poY2lCc1pUMGhNVHRwWmlob1BUMDliblZzYkNsc1pUMGhNRHRsYkhObElITjNhWFJqYUNoeEtYdGpZ'
    || 'WE5sSW5OMGNtbHVaeUk2WTJGelpTSnVkVzFpWlhJaU9teGxQU0V3TzJKeVpXRnJPMk5oYzJVaWIySnFaV04wSWpwemQybDBZMmdvYUM0a0pIUjVjR1Z2Wmls'
    || 'N1kyRnpaU0IxT21OaGMyVWdaanBzWlQwaE1IMTlhV1lvYkdVcGNtVjBkWEp1SUd4bFBXZ3NTajFLS0d4bEtTeG9QVXM5UFQwaUlqOGlMaUlyUzJVb2JHVXNN'
    || 'Q2s2U3l4dlpTaEtLVDhvVVQwaUlpeG9JVDF1ZFd4c0ppWW9VVDFvTG5KbGNHeGhZMlVvZVhRc0lpUW1MeUlwS3lJdklpa3NZWFFvU2l4ckxGRXNJaUlzWm5W'
    || 'dVkzUnBiMjRvUjJVcGUzSmxkSFZ5YmlCSFpYMHBLVHBLSVQxdWRXeHNKaVlvYW5Rb1Npa21KaWhLUFhCbEtFb3NVU3NvSVVvdWEyVjVmSHhzWlNZbWJHVXVh'
    || 'MlY1UFQwOVNpNXJaWGsvSWlJNktDSWlLMG91YTJWNUtTNXlaWEJzWVdObEtIbDBMQ0lrSmk4aUtTc2lMeUlwSzJncEtTeHJMbkIxYzJnb1Npa3BMREU3YVdZ'
    || 'b2JHVTlNQ3hMUFVzOVBUMGlJajhpTGlJNlN5c2lPaUlzYjJVb2FDa3BabTl5S0haaGNpQjBaVDB3TzNSbFBHZ3ViR1Z1WjNSb08zUmxLeXNwZTNFOWFGdDBa'
    || 'VjA3ZG1GeUlHRmxQVXNyUzJVb2NTeDBaU2s3YkdVclBXRjBLSEVzYXl4UkxHRmxMRW9wZldWc2MyVWdhV1lvWVdVOVNDaG9LU3gwZVhCbGIyWWdZV1U5UFNK'
    || 'bWRXNWpkR2x2YmlJcFptOXlLR2c5WVdVdVkyRnNiQ2hvS1N4MFpUMHdPeUVvY1Qxb0xtNWxlSFFvS1NrdVpHOXVaVHNwY1QxeExuWmhiSFZsTEdGbFBVc3JT'
    || 'MlVvY1N4MFpTc3JLU3hzWlNzOVlYUW9jU3hyTEZFc1lXVXNTaWs3Wld4elpTQnBaaWh4UFQwOUltOWlhbVZqZENJcGRHaHliM2NnYXoxVGRISnBibWNvYUNr'
    || 'c1JYSnliM0lvSWs5aWFtVmpkSE1nWVhKbElHNXZkQ0IyWVd4cFpDQmhjeUJoSUZKbFlXTjBJR05vYVd4a0lDaG1iM1Z1WkRvZ0lpc29hejA5UFNKYmIySnFa'
    || 'V04wSUU5aWFtVmpkRjBpUHlKdlltcGxZM1FnZDJsMGFDQnJaWGx6SUhzaUswOWlhbVZqZEM1clpYbHpLR2dwTG1wdmFXNG9JaXdnSWlrckluMGlPbXNwS3lJ'
    || 'cExpQkpaaUI1YjNVZ2JXVmhiblFnZEc4Z2NtVnVaR1Z5SUdFZ1kyOXNiR1ZqZEdsdmJpQnZaaUJqYUdsc1pISmxiaXdnZFhObElHRnVJR0Z5Y21GNUlHbHVj'
    || 'M1JsWVdRdUlpazdjbVYwZFhKdUlHeGxmV1oxYm1OMGFXOXVJSGgwS0dnc2F5eFJLWHRwWmlob1BUMXVkV3hzS1hKbGRIVnliaUJvTzNaaGNpQkxQVnRkTEVv'
    || 'OU1EdHlaWFIxY200Z1lYUW9hQ3hMTENJaUxDSWlMR1oxYm1OMGFXOXVLSEVwZTNKbGRIVnliaUJyTG1OaGJHd29VU3h4TEVvckt5bDlLU3hMZldaMWJtTjBh'
    || 'Vzl1SUVobEtHZ3BlMmxtS0dndVgzTjBZWFIxY3owOVBTMHhLWHQyWVhJZ2F6MW9MbDl5WlhOMWJIUTdhejFyS0Nrc2F5NTBhR1Z1S0daMWJtTjBhVzl1S0ZF'
    || 'cGV5aG9MbDl6ZEdGMGRYTTlQVDB3Zkh4b0xsOXpkR0YwZFhNOVBUMHRNU2ttSmlob0xsOXpkR0YwZFhNOU1TeG9MbDl5WlhOMWJIUTlVU2w5TEdaMWJtTjBh'
    || 'Vzl1S0ZFcGV5aG9MbDl6ZEdGMGRYTTlQVDB3Zkh4b0xsOXpkR0YwZFhNOVBUMHRNU2ttSmlob0xsOXpkR0YwZFhNOU1peG9MbDl5WlhOMWJIUTlVU2w5S1N4'
    || 'b0xsOXpkR0YwZFhNOVBUMHRNU1ltS0dndVgzTjBZWFIxY3owd0xHZ3VYM0psYzNWc2REMXJLWDFwWmlob0xsOXpkR0YwZFhNOVBUMHhLWEpsZEhWeWJpQm9M'
    || 'bDl5WlhOMWJIUXVaR1ZtWVhWc2REdDBhSEp2ZHlCb0xsOXlaWE4xYkhSOWRtRnlJR2hsUFh0amRYSnlaVzUwT201MWJHeDlMRkk5ZTNSeVlXNXphWFJwYjI0'
    || 'NmJuVnNiSDBzSkQxN1VtVmhZM1JEZFhKeVpXNTBSR2x6Y0dGMFkyaGxjanBvWlN4U1pXRmpkRU4xY25KbGJuUkNZWFJqYUVOdmJtWnBaenBTTEZKbFlXTjBR'
    || 'M1Z5Y21WdWRFOTNibVZ5T2xObGZUdG1kVzVqZEdsdmJpQlBLQ2w3ZEdoeWIzY2dSWEp5YjNJb0ltRmpkQ2d1TGk0cElHbHpJRzV2ZENCemRYQndiM0owWldR'
    || 'Z2FXNGdjSEp2WkhWamRHbHZiaUJpZFdsc1pITWdiMllnVW1WaFkzUXVJaWw5Y21WMGRYSnVJRmt1UTJocGJHUnlaVzQ5ZTIxaGNEcDRkQ3htYjNKRllXTm9P'
    || 'bVoxYm1OMGFXOXVLR2dzYXl4UktYdDRkQ2hvTEdaMWJtTjBhVzl1S0NsN2F5NWhjSEJzZVNoMGFHbHpMR0Z5WjNWdFpXNTBjeWw5TEZFcGZTeGpiM1Z1ZERw'
    || 'bWRXNWpkR2x2Ymlob0tYdDJZWElnYXowd08zSmxkSFZ5YmlCNGRDaG9MR1oxYm1OMGFXOXVLQ2w3YXlzcmZTa3NhMzBzZEc5QmNuSmhlVHBtZFc1amRHbHZi'
    || 'aWhvS1h0eVpYUjFjbTRnZUhRb2FDeG1kVzVqZEdsdmJpaHJLWHR5WlhSMWNtNGdhMzBwZkh4YlhYMHNiMjVzZVRwbWRXNWpkR2x2Ymlob0tYdHBaaWdoYW5R'
    || 'b2FDa3BkR2h5YjNjZ1JYSnliM0lvSWxKbFlXTjBMa05vYVd4a2NtVnVMbTl1YkhrZ1pYaHdaV04wWldRZ2RHOGdjbVZqWldsMlpTQmhJSE5wYm1kc1pTQlNa'
    || 'V0ZqZENCbGJHVnRaVzUwSUdOb2FXeGtMaUlwTzNKbGRIVnliaUJvZlgwc1dTNURiMjF3YjI1bGJuUTlWaXhaTGtaeVlXZHRaVzUwUFdFc1dTNVFjbTltYVd4'
    || 'bGNqMU9MRmt1VUhWeVpVTnZiWEJ2Ym1WdWREMU9aU3haTGxOMGNtbGpkRTF2WkdVOWVDeFpMbE4xYzNCbGJuTmxQWGNzV1M1ZlgxTkZRMUpGVkY5SlRsUkZV'
    || 'azVCVEZOZlJFOWZUazlVWDFWVFJWOVBVbDlaVDFWZlYwbE1URjlDUlY5R1NWSkZSRDBrTEZrdVlXTjBQVThzV1M1amJHOXVaVVZzWlcxbGJuUTlablZ1WTNS'
    || 'cGIyNG9hQ3hyTEZFcGUybG1LR2c5UFc1MWJHd3BkR2h5YjNjZ1JYSnliM0lvSWxKbFlXTjBMbU5zYjI1bFJXeGxiV1Z1ZENndUxpNHBPaUJVYUdVZ1lYSm5k'
    || 'VzFsYm5RZ2JYVnpkQ0JpWlNCaElGSmxZV04wSUdWc1pXMWxiblFzSUdKMWRDQjViM1VnY0dGemMyVmtJQ0lyYUNzaUxpSXBPM1poY2lCTFBVY29lMzBzYUM1'
    || 'd2NtOXdjeWtzU2oxb0xtdGxlU3h4UFdndWNtVm1MR3hsUFdndVgyOTNibVZ5TzJsbUtHc2hQVzUxYkd3cGUybG1LR3N1Y21WbUlUMDlkbTlwWkNBd0ppWW9j'
    || 'VDFyTG5KbFppeHNaVDFUWlM1amRYSnlaVzUwS1N4ckxtdGxlU0U5UFhadmFXUWdNQ1ltS0VvOUlpSXJheTVyWlhrcExHZ3VkSGx3WlNZbWFDNTBlWEJsTG1S'
    || 'bFptRjFiSFJRY205d2N5bDJZWElnZEdVOWFDNTBlWEJsTG1SbFptRjFiSFJRY205d2N6dG1iM0lvWVdVZ2FXNGdheWxWWlM1allXeHNLR3NzWVdVcEppWWhh'
    || 'bVV1YUdGelQzZHVVSEp2Y0dWeWRIa29ZV1VwSmlZb1MxdGhaVjA5YTF0aFpWMDlQVDEyYjJsa0lEQW1KblJsSVQwOWRtOXBaQ0F3UDNSbFcyRmxYVHByVzJG'
    || 'bFhTbDlkbUZ5SUdGbFBXRnlaM1Z0Wlc1MGN5NXNaVzVuZEdndE1qdHBaaWhoWlQwOVBURXBTeTVqYUdsc1pISmxiajFSTzJWc2MyVWdhV1lvTVR4aFpTbDdk'
    || 'R1U5UVhKeVlYa29ZV1VwTzJadmNpaDJZWElnUjJVOU1EdEhaVHhoWlR0SFpTc3JLWFJsVzBkbFhUMWhjbWQxYldWdWRITmJSMlVyTWwwN1N5NWphR2xzWkhK'
    || 'bGJqMTBaWDF5WlhSMWNtNTdKQ1IwZVhCbGIyWTZkU3gwZVhCbE9tZ3VkSGx3WlN4clpYazZTaXh5WldZNmNTeHdjbTl3Y3pwTExGOXZkMjVsY2pwc1pYMTlM'
    || 'Rmt1WTNKbFlYUmxRMjl1ZEdWNGREMW1kVzVqZEdsdmJpaG9LWHR5WlhSMWNtNGdhRDE3SkNSMGVYQmxiMlk2ZVN4ZlkzVnljbVZ1ZEZaaGJIVmxPbWdzWDJO'
    || 'MWNuSmxiblJXWVd4MVpUSTZhQ3hmZEdoeVpXRmtRMjkxYm5RNk1DeFFjbTkyYVdSbGNqcHVkV3hzTEVOdmJuTjFiV1Z5T201MWJHd3NYMlJsWm1GMWJIUldZ'
    || 'V3gxWlRwdWRXeHNMRjluYkc5aVlXeE9ZVzFsT201MWJHeDlMR2d1VUhKdmRtbGtaWEk5ZXlRa2RIbHdaVzltT2tNc1gyTnZiblJsZUhRNmFIMHNhQzVEYjI1'
    || 'emRXMWxjajFvZlN4WkxtTnlaV0YwWlVWc1pXMWxiblE5U1dVc1dTNWpjbVZoZEdWR1lXTjBiM0o1UFdaMWJtTjBhVzl1S0dncGUzWmhjaUJyUFVsbExtSnBi'
    || 'bVFvYm5Wc2JDeG9LVHR5WlhSMWNtNGdheTUwZVhCbFBXZ3NhMzBzV1M1amNtVmhkR1ZTWldZOVpuVnVZM1JwYjI0b0tYdHlaWFIxY201N1kzVnljbVZ1ZERw'
    || 'dWRXeHNmWDBzV1M1bWIzSjNZWEprVW1WbVBXWjFibU4wYVc5dUtHZ3BlM0psZEhWeWJuc2tKSFI1Y0dWdlpqcGZMSEpsYm1SbGNqcG9mWDBzV1M1cGMxWmhi'
    || 'R2xrUld4bGJXVnVkRDFxZEN4WkxteGhlbms5Wm5WdVkzUnBiMjRvYUNsN2NtVjBkWEp1ZXlRa2RIbHdaVzltT2t3c1gzQmhlV3h2WVdRNmUxOXpkR0YwZFhN'
    || 'NkxURXNYM0psYzNWc2REcG9mU3hmYVc1cGREcElaWDE5TEZrdWJXVnRiejFtZFc1amRHbHZiaWhvTEdzcGUzSmxkSFZ5Ym5za0pIUjVjR1Z2WmpwQ0xIUjVj'
    || 'R1U2YUN4amIyMXdZWEpsT21zOVBUMTJiMmxrSURBL2JuVnNiRHByZlgwc1dTNXpkR0Z5ZEZSeVlXNXphWFJwYjI0OVpuVnVZM1JwYjI0b2FDbDdkbUZ5SUdz'
    || 'OVVpNTBjbUZ1YzJsMGFXOXVPMUl1ZEhKaGJuTnBkR2x2YmoxN2ZUdDBjbmw3YUNncGZXWnBibUZzYkhsN1VpNTBjbUZ1YzJsMGFXOXVQV3Q5ZlN4WkxuVnVj'
    || 'M1JoWW14bFgyRmpkRDFQTEZrdWRYTmxRMkZzYkdKaFkyczlablZ1WTNScGIyNG9hQ3hyS1h0eVpYUjFjbTRnYUdVdVkzVnljbVZ1ZEM1MWMyVkRZV3hzWW1G'
    || 'amF5aG9MR3NwZlN4WkxuVnpaVU52Ym5SbGVIUTlablZ1WTNScGIyNG9hQ2w3Y21WMGRYSnVJR2hsTG1OMWNuSmxiblF1ZFhObFEyOXVkR1Y0ZENob0tYMHNX'
    || 'UzUxYzJWRVpXSjFaMVpoYkhWbFBXWjFibU4wYVc5dUtDbDdmU3haTG5WelpVUmxabVZ5Y21Wa1ZtRnNkV1U5Wm5WdVkzUnBiMjRvYUNsN2NtVjBkWEp1SUdo'
    || 'bExtTjFjbkpsYm5RdWRYTmxSR1ZtWlhKeVpXUldZV3gxWlNob0tYMHNXUzUxYzJWRlptWmxZM1E5Wm5WdVkzUnBiMjRvYUN4cktYdHlaWFIxY200Z2FHVXVZ'
    || 'M1Z5Y21WdWRDNTFjMlZGWm1abFkzUW9hQ3hyS1gwc1dTNTFjMlZKWkQxbWRXNWpkR2x2YmlncGUzSmxkSFZ5YmlCb1pTNWpkWEp5Wlc1MExuVnpaVWxrS0Ns'
    || 'OUxGa3VkWE5sU1cxd1pYSmhkR2wyWlVoaGJtUnNaVDFtZFc1amRHbHZiaWhvTEdzc1VTbDdjbVYwZFhKdUlHaGxMbU4xY25KbGJuUXVkWE5sU1cxd1pYSmhk'
    || 'R2wyWlVoaGJtUnNaU2hvTEdzc1VTbDlMRmt1ZFhObFNXNXpaWEowYVc5dVJXWm1aV04wUFdaMWJtTjBhVzl1S0dnc2F5bDdjbVYwZFhKdUlHaGxMbU4xY25K'
    || 'bGJuUXVkWE5sU1c1elpYSjBhVzl1UldabVpXTjBLR2dzYXlsOUxGa3VkWE5sVEdGNWIzVjBSV1ptWldOMFBXWjFibU4wYVc5dUtHZ3NheWw3Y21WMGRYSnVJ'
    || 'R2hsTG1OMWNuSmxiblF1ZFhObFRHRjViM1YwUldabVpXTjBLR2dzYXlsOUxGa3VkWE5sVFdWdGJ6MW1kVzVqZEdsdmJpaG9MR3NwZTNKbGRIVnliaUJvWlM1'
    || 'amRYSnlaVzUwTG5WelpVMWxiVzhvYUN4cktYMHNXUzUxYzJWU1pXUjFZMlZ5UFdaMWJtTjBhVzl1S0dnc2F5eFJLWHR5WlhSMWNtNGdhR1V1WTNWeWNtVnVk'
    || 'QzUxYzJWU1pXUjFZMlZ5S0dnc2F5eFJLWDBzV1M1MWMyVlNaV1k5Wm5WdVkzUnBiMjRvYUNsN2NtVjBkWEp1SUdobExtTjFjbkpsYm5RdWRYTmxVbVZtS0dn'
    || 'cGZTeFpMblZ6WlZOMFlYUmxQV1oxYm1OMGFXOXVLR2dwZTNKbGRIVnliaUJvWlM1amRYSnlaVzUwTG5WelpWTjBZWFJsS0dncGZTeFpMblZ6WlZONWJtTkZl'
    || 'SFJsY201aGJGTjBiM0psUFdaMWJtTjBhVzl1S0dnc2F5eFJLWHR5WlhSMWNtNGdhR1V1WTNWeWNtVnVkQzUxYzJWVGVXNWpSWGgwWlhKdVlXeFRkRzl5WlNo'
    || 'b0xHc3NVU2w5TEZrdWRYTmxWSEpoYm5OcGRHbHZiajFtZFc1amRHbHZiaWdwZTNKbGRIVnliaUJvWlM1amRYSnlaVzUwTG5WelpWUnlZVzV6YVhScGIyNG9L'
    || 'WDBzV1M1MlpYSnphVzl1UFNJeE9DNHpMakVpTEZsOWRtRnlJRWR2TzJaMWJtTjBhVzl1SUZac0tDbDdjbVYwZFhKdUlFZHZmSHdvUjI4OU1TeFhiQzVsZUhC'
    || 'dmNuUnpQWE5qS0NrcExGZHNMbVY0Y0c5eWRITjlMeW9xQ2lBcUlFQnNhV05sYm5ObElGSmxZV04wQ2lBcUlISmxZV04wTFdwemVDMXlkVzUwYVcxbExuQnli'
    || 'MlIxWTNScGIyNHViV2x1TG1wekNpQXFDaUFxSUVOdmNIbHlhV2RvZENBb1l5a2dSbUZqWldKdmIyc3NJRWx1WXk0Z1lXNWtJR2wwY3lCaFptWnBiR2xoZEdW'
    || 'ekxnb2dLZ29nS2lCVWFHbHpJSE52ZFhKalpTQmpiMlJsSUdseklHeHBZMlZ1YzJWa0lIVnVaR1Z5SUhSb1pTQk5TVlFnYkdsalpXNXpaU0JtYjNWdVpDQnBi'
    || 'aUIwYUdVS0lDb2dURWxEUlU1VFJTQm1hV3hsSUdsdUlIUm9aU0J5YjI5MElHUnBjbVZqZEc5eWVTQnZaaUIwYUdseklITnZkWEpqWlNCMGNtVmxMZ29nS2k5'
    || 'MllYSWdXRzg3Wm5WdVkzUnBiMjRnZFdNb0tYdHBaaWhZYnlseVpYUjFjbTRnVm00N1dHODlNVHQyWVhJZ2RUMVdiQ2dwTEdZOVUzbHRZbTlzTG1admNpZ2lj'
    || 'bVZoWTNRdVpXeGxiV1Z1ZENJcExHRTlVM2x0WW05c0xtWnZjaWdpY21WaFkzUXVabkpoWjIxbGJuUWlLU3g0UFU5aWFtVmpkQzV3Y205MGIzUjVjR1V1YUdG'
    || 'elQzZHVVSEp2Y0dWeWRIa3NUajExTGw5ZlUwVkRVa1ZVWDBsT1ZFVlNUa0ZNVTE5RVQxOU9UMVJmVlZORlgwOVNYMWxQVlY5WFNVeE1YMEpGWDBaSlVrVkVM'
    || 'bEpsWVdOMFEzVnljbVZ1ZEU5M2JtVnlMRU05ZTJ0bGVUb2hNQ3h5WldZNklUQXNYMTl6Wld4bU9pRXdMRjlmYzI5MWNtTmxPaUV3ZlR0bWRXNWpkR2x2YmlC'
    || 'NUtGOHNkeXhDS1h0MllYSWdUQ3hCUFh0OUxFZzliblZzYkN4eVpUMXVkV3hzTzBJaFBUMTJiMmxrSURBbUppaElQU0lpSzBJcExIY3VhMlY1SVQwOWRtOXBa'
    || 'Q0F3SmlZb1NEMGlJaXQzTG10bGVTa3NkeTV5WldZaFBUMTJiMmxrSURBbUppaHlaVDEzTG5KbFppazdabTl5S0V3Z2FXNGdkeWw0TG1OaGJHd29keXhNS1NZ'
    || 'bUlVTXVhR0Z6VDNkdVVISnZjR1Z5ZEhrb1RDa21KaWhCVzB4ZFBYZGJURjBwTzJsbUtGOG1KbDh1WkdWbVlYVnNkRkJ5YjNCektXWnZjaWhNSUdsdUlIYzlY'
    || 'eTVrWldaaGRXeDBVSEp2Y0hNc2R5bEJXMHhkUFQwOWRtOXBaQ0F3SmlZb1FWdE1YVDEzVzB4ZEtUdHlaWFIxY201N0pDUjBlWEJsYjJZNlppeDBlWEJsT2w4'
    || 'c2EyVjVPa2dzY21WbU9uSmxMSEJ5YjNCek9rRXNYMjkzYm1WeU9rNHVZM1Z5Y21WdWRIMTljbVYwZFhKdUlGWnVMa1p5WVdkdFpXNTBQV0VzVm00dWFuTjRQ'
    || 'WGtzVm00dWFuTjRjejE1TEZadWZYWmhjaUJhYnp0bWRXNWpkR2x2YmlCaFl5Z3BlM0psZEhWeWJpQmFiM3g4S0ZwdlBURXNKR3d1Wlhod2IzSjBjejExWXln'
    || 'cEtTd2tiQzVsZUhCdmNuUnpmWFpoY2lCelBXRmpLQ2tzUW13OVZtd29LVHRqYjI1emRDQmlaVDF2WXloQ2JDazdkbUZ5SUV4eVBYdDlMRkZzUFh0bGVIQnZj'
    || 'blJ6T250OWZTeEJaVDE3ZlN4WmJEMTdaWGh3YjNKMGN6cDdmWDBzUzJ3OWUzMDdMeW9xQ2lBcUlFQnNhV05sYm5ObElGSmxZV04wQ2lBcUlITmphR1ZrZFd4'
    || 'bGNpNXdjbTlrZFdOMGFXOXVMbTFwYmk1cWN3b2dLZ29nS2lCRGIzQjVjbWxuYUhRZ0tHTXBJRVpoWTJWaWIyOXJMQ0JKYm1NdUlHRnVaQ0JwZEhNZ1lXWm1h'
    || 'V3hwWVhSbGN5NEtJQ29LSUNvZ1ZHaHBjeUJ6YjNWeVkyVWdZMjlrWlNCcGN5QnNhV05sYm5ObFpDQjFibVJsY2lCMGFHVWdUVWxVSUd4cFkyVnVjMlVnWm05'
    || 'MWJtUWdhVzRnZEdobENpQXFJRXhKUTBWT1UwVWdabWxzWlNCcGJpQjBhR1VnY205dmRDQmthWEpsWTNSdmNua2diMllnZEdocGN5QnpiM1Z5WTJVZ2RISmxa'
    || 'UzRLSUNvdmRtRnlJRXB2TzJaMWJtTjBhVzl1SUdOaktDbDdjbVYwZFhKdUlFcHZmSHdvU204OU1Td29ablZ1WTNScGIyNG9kU2w3Wm5WdVkzUnBiMjRnWmlo'
    || 'U0xDUXBlM1poY2lCUFBWSXViR1Z1WjNSb08xSXVjSFZ6YUNna0tUdGxPbVp2Y2lnN01EeFBPeWw3ZG1GeUlHZzlUeTB4UGo0K01TeHJQVkpiYUYwN2FXWW9N'
    || 'RHhPS0dzc0pDa3BVbHRvWFQwa0xGSmJUMTA5YXl4UFBXZzdaV3h6WlNCaWNtVmhheUJsZlgxbWRXNWpkR2x2YmlCaEtGSXBlM0psZEhWeWJpQlNMbXhsYm1k'
    || 'MGFEMDlQVEEvYm5Wc2JEcFNXekJkZldaMWJtTjBhVzl1SUhnb1VpbDdhV1lvVWk1c1pXNW5kR2c5UFQwd0tYSmxkSFZ5YmlCdWRXeHNPM1poY2lBa1BWSmJN'
    || 'RjBzVHoxU0xuQnZjQ2dwTzJsbUtFOGhQVDBrS1h0U1d6QmRQVTg3WlRwbWIzSW9kbUZ5SUdnOU1DeHJQVkl1YkdWdVozUm9MRkU5YXo0K1BqRTdhRHhST3ls'
    || 'N2RtRnlJRXM5TWlvb2FDc3hLUzB4TEVvOVVsdExYU3h4UFVzck1TeHNaVDFTVzNGZE8ybG1LREErVGloS0xFOHBLWEU4YXlZbU1ENU9LR3hsTEVvcFB5aFNX'
    || 'MmhkUFd4bExGSmJjVjA5VHl4b1BYRXBPaWhTVzJoZFBVb3NVbHRMWFQxUExHZzlTeWs3Wld4elpTQnBaaWh4UEdzbUpqQStUaWhzWlN4UEtTbFNXMmhkUFd4'
    || 'bExGSmJjVjA5VHl4b1BYRTdaV3h6WlNCaWNtVmhheUJsZlgxeVpYUjFjbTRnSkgxbWRXNWpkR2x2YmlCT0tGSXNKQ2w3ZG1GeUlFODlVaTV6YjNKMFNXNWta'
    || 'WGd0SkM1emIzSjBTVzVrWlhnN2NtVjBkWEp1SUU4aFBUMHdQMDg2VWk1cFpDMGtMbWxrZldsbUtIUjVjR1Z2WmlCd1pYSm1iM0p0WVc1alpUMDlJbTlpYW1W'
    || 'amRDSW1KblI1Y0dWdlppQndaWEptYjNKdFlXNWpaUzV1YjNjOVBTSm1kVzVqZEdsdmJpSXBlM1poY2lCRFBYQmxjbVp2Y20xaGJtTmxPM1V1ZFc1emRHRmli'
    || 'R1ZmYm05M1BXWjFibU4wYVc5dUtDbDdjbVYwZFhKdUlFTXVibTkzS0NsOWZXVnNjMlY3ZG1GeUlIazlSR0YwWlN4ZlBYa3VibTkzS0NrN2RTNTFibk4wWVdK'
    || 'c1pWOXViM2M5Wm5WdVkzUnBiMjRvS1h0eVpYUjFjbTRnZVM1dWIzY29LUzFmZlgxMllYSWdkejFiWFN4Q1BWdGRMRXc5TVN4QlBXNTFiR3dzU0QwekxISmxQ'
    || 'U0V4TEVjOUlURXNXRDBoTVN4V1BYUjVjR1Z2WmlCelpYUlVhVzFsYjNWMFBUMGlablZ1WTNScGIyNGlQM05sZEZScGJXVnZkWFE2Ym5Wc2JDeEdaVDEwZVhC'
    || 'bGIyWWdZMnhsWVhKVWFXMWxiM1YwUFQwaVpuVnVZM1JwYjI0aVAyTnNaV0Z5VkdsdFpXOTFkRHB1ZFd4c0xFNWxQWFI1Y0dWdlppQnpaWFJKYlcxbFpHbGhk'
    || 'R1U4SW5VaVAzTmxkRWx0YldWa2FXRjBaVHB1ZFd4c08zUjVjR1Z2WmlCdVlYWnBaMkYwYjNJOEluVWlKaVp1WVhacFoyRjBiM0l1YzJOb1pXUjFiR2x1WnlF'
    || 'OVBYWnZhV1FnTUNZbWJtRjJhV2RoZEc5eUxuTmphR1ZrZFd4cGJtY3VhWE5KYm5CMWRGQmxibVJwYm1jaFBUMTJiMmxrSURBbUptNWhkbWxuWVhSdmNpNXpZ'
    || 'MmhsWkhWc2FXNW5MbWx6U1c1d2RYUlFaVzVrYVc1bkxtSnBibVFvYm1GMmFXZGhkRzl5TG5OamFHVmtkV3hwYm1jcE8yWjFibU4wYVc5dUlFeGxLRklwZTJa'
    || 'dmNpaDJZWElnSkQxaEtFSXBPeVFoUFQxdWRXeHNPeWw3YVdZb0pDNWpZV3hzWW1GamF6MDlQVzUxYkd3cGVDaENLVHRsYkhObElHbG1LQ1F1YzNSaGNuUlVh'
    || 'VzFsUEQxU0tYZ29RaWtzSkM1emIzSjBTVzVrWlhnOUpDNWxlSEJwY21GMGFXOXVWR2x0WlN4bUtIY3NKQ2s3Wld4elpTQmljbVZoYXpza1BXRW9RaWw5Zlda'
    || 'MWJtTjBhVzl1SUc5bEtGSXBlMmxtS0ZnOUlURXNUR1VvVWlrc0lVY3BhV1lvWVNoM0tTRTlQVzUxYkd3cFJ6MGhNQ3hJWlNoVlpTazdaV3h6Wlh0MllYSWdK'
    || 'RDFoS0VJcE95UWhQVDF1ZFd4c0ppWm9aU2h2WlN3a0xuTjBZWEowVkdsdFpTMVNLWDE5Wm5WdVkzUnBiMjRnVldVb1Vpd2tLWHRIUFNFeExGZ21KaWhZUFNF'
    || 'eExFWmxLRWxsS1N4SlpUMHRNU2tzY21VOUlUQTdkbUZ5SUU4OVNEdDBjbmw3Wm05eUtFeGxLQ1FwTEVFOVlTaDNLVHRCSVQwOWJuVnNiQ1ltS0NFb1FTNWxl'
    || 'SEJwY21GMGFXOXVWR2x0WlQ0a0tYeDhVaVltSVhSdUtDa3BPeWw3ZG1GeUlHZzlRUzVqWVd4c1ltRmphenRwWmloMGVYQmxiMllnYUQwOUltWjFibU4wYVc5'
    || 'dUlpbDdRUzVqWVd4c1ltRmphejF1ZFd4c0xFZzlRUzV3Y21sdmNtbDBlVXhsZG1Wc08zWmhjaUJyUFdnb1FTNWxlSEJwY21GMGFXOXVWR2x0WlR3OUpDazdK'
    || 'RDExTG5WdWMzUmhZbXhsWDI1dmR5Z3BMSFI1Y0dWdlppQnJQVDBpWm5WdVkzUnBiMjRpUDBFdVkyRnNiR0poWTJzOWF6cEJQVDA5WVNoM0tTWW1lQ2gzS1N4'
    || 'TVpTZ2tLWDFsYkhObElIZ29keWs3UVQxaEtIY3BmV2xtS0VFaFBUMXVkV3hzS1haaGNpQlJQU0V3TzJWc2MyVjdkbUZ5SUVzOVlTaENLVHRMSVQwOWJuVnNi'
    || 'Q1ltYUdVb2IyVXNTeTV6ZEdGeWRGUnBiV1V0SkNrc1VUMGhNWDF5WlhSMWNtNGdVWDFtYVc1aGJHeDVlMEU5Ym5Wc2JDeElQVThzY21VOUlURjlmWFpoY2lC'
    || 'VFpUMGhNU3hxWlQxdWRXeHNMRWxsUFMweExIQmxQVFVzYW5ROUxURTdablZ1WTNScGIyNGdkRzRvS1h0eVpYUjFjbTRoS0hVdWRXNXpkR0ZpYkdWZmJtOTNL'
    || 'Q2t0YW5ROGNHVXBmV1oxYm1OMGFXOXVJSGwwS0NsN2FXWW9hbVVoUFQxdWRXeHNLWHQyWVhJZ1VqMTFMblZ1YzNSaFlteGxYMjV2ZHlncE8ycDBQVkk3ZG1G'
    || 'eUlDUTlJVEE3ZEhKNWV5UTlhbVVvSVRBc1VpbDlabWx1WVd4c2VYc2tQMHRsS0NrNktGTmxQU0V4TEdwbFBXNTFiR3dwZlgxbGJITmxJRk5sUFNFeGZYWmhj'
    || 'aUJMWlR0cFppaDBlWEJsYjJZZ1RtVTlQU0ptZFc1amRHbHZiaUlwUzJVOVpuVnVZM1JwYjI0b0tYdE9aU2g1ZENsOU8yVnNjMlVnYVdZb2RIbHdaVzltSUUx'
    || 'bGMzTmhaMlZEYUdGdWJtVnNQQ0oxSWlsN2RtRnlJR0YwUFc1bGR5Qk5aWE56WVdkbFEyaGhibTVsYkN4NGREMWhkQzV3YjNKME1qdGhkQzV3YjNKME1TNXZi'
    || 'bTFsYzNOaFoyVTllWFFzUzJVOVpuVnVZM1JwYjI0b0tYdDRkQzV3YjNOMFRXVnpjMkZuWlNodWRXeHNLWDE5Wld4elpTQkxaVDFtZFc1amRHbHZiaWdwZTFZ'
    || 'b2VYUXNNQ2w5TzJaMWJtTjBhVzl1SUVobEtGSXBlMnBsUFZJc1UyVjhmQ2hUWlQwaE1DeExaU2dwS1gxbWRXNWpkR2x2YmlCb1pTaFNMQ1FwZTBsbFBWWW9a'
    || 'blZ1WTNScGIyNG9LWHRTS0hVdWRXNXpkR0ZpYkdWZmJtOTNLQ2twZlN3a0tYMTFMblZ1YzNSaFlteGxYMGxrYkdWUWNtbHZjbWwwZVQwMUxIVXVkVzV6ZEdG'
    || 'aWJHVmZTVzF0WldScFlYUmxVSEpwYjNKcGRIazlNU3gxTG5WdWMzUmhZbXhsWDB4dmQxQnlhVzl5YVhSNVBUUXNkUzUxYm5OMFlXSnNaVjlPYjNKdFlXeFFj'
    || 'bWx2Y21sMGVUMHpMSFV1ZFc1emRHRmliR1ZmVUhKdlptbHNhVzVuUFc1MWJHd3NkUzUxYm5OMFlXSnNaVjlWYzJWeVFteHZZMnRwYm1kUWNtbHZjbWwwZVQw'
    || 'eUxIVXVkVzV6ZEdGaWJHVmZZMkZ1WTJWc1EyRnNiR0poWTJzOVpuVnVZM1JwYjI0b1VpbDdVaTVqWVd4c1ltRmphejF1ZFd4c2ZTeDFMblZ1YzNSaFlteGxY'
    || 'Mk52Ym5ScGJuVmxSWGhsWTNWMGFXOXVQV1oxYm1OMGFXOXVLQ2w3UjN4OGNtVjhmQ2hIUFNFd0xFaGxLRlZsS1NsOUxIVXVkVzV6ZEdGaWJHVmZabTl5WTJW'
    || 'R2NtRnRaVkpoZEdVOVpuVnVZM1JwYjI0b1VpbDdNRDVTZkh3eE1qVThVajlqYjI1emIyeGxMbVZ5Y205eUtDSm1iM0pqWlVaeVlXMWxVbUYwWlNCMFlXdGxj'
    || 'eUJoSUhCdmMybDBhWFpsSUdsdWRDQmlaWFIzWldWdUlEQWdZVzVrSURFeU5Td2dabTl5WTJsdVp5Qm1jbUZ0WlNCeVlYUmxjeUJvYVdkb1pYSWdkR2hoYmlB'
    || 'eE1qVWdabkJ6SUdseklHNXZkQ0J6ZFhCd2IzSjBaV1FpS1Rwd1pUMHdQRkkvVFdGMGFDNW1iRzl2Y2lneFpUTXZVaWs2Tlgwc2RTNTFibk4wWVdKc1pWOW5a'
    || 'WFJEZFhKeVpXNTBVSEpwYjNKcGRIbE1aWFpsYkQxbWRXNWpkR2x2YmlncGUzSmxkSFZ5YmlCSWZTeDFMblZ1YzNSaFlteGxYMmRsZEVacGNuTjBRMkZzYkdK'
    || 'aFkydE9iMlJsUFdaMWJtTjBhVzl1S0NsN2NtVjBkWEp1SUdFb2R5bDlMSFV1ZFc1emRHRmliR1ZmYm1WNGREMW1kVzVqZEdsdmJpaFNLWHR6ZDJsMFkyZ29T'
    || 'Q2w3WTJGelpTQXhPbU5oYzJVZ01qcGpZWE5sSURNNmRtRnlJQ1E5TXp0aWNtVmhhenRrWldaaGRXeDBPaVE5U0gxMllYSWdUejFJTzBnOUpEdDBjbmw3Y21W'
    || 'MGRYSnVJRklvS1gxbWFXNWhiR3g1ZTBnOVQzMTlMSFV1ZFc1emRHRmliR1ZmY0dGMWMyVkZlR1ZqZFhScGIyNDlablZ1WTNScGIyNG9LWHQ5TEhVdWRXNXpk'
    || 'R0ZpYkdWZmNtVnhkV1Z6ZEZCaGFXNTBQV1oxYm1OMGFXOXVLQ2w3ZlN4MUxuVnVjM1JoWW14bFgzSjFibGRwZEdoUWNtbHZjbWwwZVQxbWRXNWpkR2x2Ymlo'
    || 'U0xDUXBlM04zYVhSamFDaFNLWHRqWVhObElERTZZMkZ6WlNBeU9tTmhjMlVnTXpwallYTmxJRFE2WTJGelpTQTFPbUp5WldGck8yUmxabUYxYkhRNlVqMHpm'
    || 'WFpoY2lCUFBVZzdTRDFTTzNSeWVYdHlaWFIxY200Z0pDZ3BmV1pwYm1Gc2JIbDdTRDFQZlgwc2RTNTFibk4wWVdKc1pWOXpZMmhsWkhWc1pVTmhiR3hpWVdO'
    || 'clBXWjFibU4wYVc5dUtGSXNKQ3hQS1h0MllYSWdhRDExTG5WdWMzUmhZbXhsWDI1dmR5Z3BPM04zYVhSamFDaDBlWEJsYjJZZ1R6MDlJbTlpYW1WamRDSW1K'
    || 'azhoUFQxdWRXeHNQeWhQUFU4dVpHVnNZWGtzVHoxMGVYQmxiMllnVHowOUltNTFiV0psY2lJbUpqQThUejlvSzA4NmFDazZUejFvTEZJcGUyTmhjMlVnTVRw'
    || 'MllYSWdhejB0TVR0aWNtVmhhenRqWVhObElESTZhejB5TlRBN1luSmxZV3M3WTJGelpTQTFPbXM5TVRBM016YzBNVGd5TXp0aWNtVmhhenRqWVhObElEUTZh'
    || 'ejB4WlRRN1luSmxZV3M3WkdWbVlYVnNkRHByUFRWbE0zMXlaWFIxY200Z2F6MVBLMnNzVWoxN2FXUTZUQ3NyTEdOaGJHeGlZV05yT2lRc2NISnBiM0pwZEhs'
    || 'TVpYWmxiRHBTTEhOMFlYSjBWR2x0WlRwUExHVjRjR2x5WVhScGIyNVVhVzFsT21zc2MyOXlkRWx1WkdWNE9pMHhmU3hQUG1nL0tGSXVjMjl5ZEVsdVpHVjRQ'
    || 'VThzWmloQ0xGSXBMR0VvZHlrOVBUMXVkV3hzSmlaU1BUMDlZU2hDS1NZbUtGZy9LRVpsS0VsbEtTeEpaVDB0TVNrNldEMGhNQ3hvWlNodlpTeFBMV2dwS1Nr'
    || 'NktGSXVjMjl5ZEVsdVpHVjRQV3NzWmloM0xGSXBMRWQ4ZkhKbGZId29SejBoTUN4SVpTaFZaU2twS1N4U2ZTeDFMblZ1YzNSaFlteGxYM05vYjNWc1pGbHBa'
    || 'V3hrUFhSdUxIVXVkVzV6ZEdGaWJHVmZkM0poY0VOaGJHeGlZV05yUFdaMWJtTjBhVzl1S0ZJcGUzWmhjaUFrUFVnN2NtVjBkWEp1SUdaMWJtTjBhVzl1S0Ns'
    || 'N2RtRnlJRTg5U0R0SVBTUTdkSEo1ZTNKbGRIVnliaUJTTG1Gd2NHeDVLSFJvYVhNc1lYSm5kVzFsYm5SektYMW1hVzVoYkd4NWUwZzlUMzE5ZlgwcEtFdHNL'
    || 'U2tzUzJ4OWRtRnlJSEZ2TzJaMWJtTjBhVzl1SUdSaktDbDdjbVYwZFhKdUlIRnZmSHdvY1c4OU1TeFpiQzVsZUhCdmNuUnpQV05qS0NrcExGbHNMbVY0Y0c5'
    || 'eWRITjlMeW9xQ2lBcUlFQnNhV05sYm5ObElGSmxZV04wQ2lBcUlISmxZV04wTFdSdmJTNXdjbTlrZFdOMGFXOXVMbTFwYmk1cWN3b2dLZ29nS2lCRGIzQjVj'
    || 'bWxuYUhRZ0tHTXBJRVpoWTJWaWIyOXJMQ0JKYm1NdUlHRnVaQ0JwZEhNZ1lXWm1hV3hwWVhSbGN5NEtJQ29LSUNvZ1ZHaHBjeUJ6YjNWeVkyVWdZMjlrWlNC'
    || 'cGN5QnNhV05sYm5ObFpDQjFibVJsY2lCMGFHVWdUVWxVSUd4cFkyVnVjMlVnWm05MWJtUWdhVzRnZEdobENpQXFJRXhKUTBWT1UwVWdabWxzWlNCcGJpQjBh'
    || 'R1VnY205dmRDQmthWEpsWTNSdmNua2diMllnZEdocGN5QnpiM1Z5WTJVZ2RISmxaUzRLSUNvdmRtRnlJR0p2TzJaMWJtTjBhVzl1SUdaaktDbDdhV1lvWW04'
    || 'cGNtVjBkWEp1SUVGbE8ySnZQVEU3ZG1GeUlIVTlWbXdvS1N4bVBXUmpLQ2s3Wm5WdVkzUnBiMjRnWVNobEtYdG1iM0lvZG1GeUlIUTlJbWgwZEhCek9pOHZj'
    || 'bVZoWTNScWN5NXZjbWN2Wkc5amN5OWxjbkp2Y2kxa1pXTnZaR1Z5TG1oMGJXdy9hVzUyWVhKcFlXNTBQU0lyWlN4dVBURTdianhoY21kMWJXVnVkSE11YkdW'
    || 'dVozUm9PMjRyS3lsMEt6MGlKbUZ5WjNOYlhUMGlLMlZ1WTI5a1pWVlNTVU52YlhCdmJtVnVkQ2hoY21kMWJXVnVkSE5iYmwwcE8zSmxkSFZ5YmlKTmFXNXBa'
    || 'bWxsWkNCU1pXRmpkQ0JsY25KdmNpQWpJaXRsS3lJN0lIWnBjMmwwSUNJcmRDc2lJR1p2Y2lCMGFHVWdablZzYkNCdFpYTnpZV2RsSUc5eUlIVnpaU0IwYUdV'
    || 'Z2JtOXVMVzFwYm1sbWFXVmtJR1JsZGlCbGJuWnBjbTl1YldWdWRDQm1iM0lnWm5Wc2JDQmxjbkp2Y25NZ1lXNWtJR0ZrWkdsMGFXOXVZV3dnYUdWc2NHWjFi'
    || 'Q0IzWVhKdWFXNW5jeTRpZlhaaGNpQjRQVzVsZHlCVFpYUXNUajE3ZlR0bWRXNWpkR2x2YmlCREtHVXNkQ2w3ZVNobExIUXBMSGtvWlNzaVEyRndkSFZ5WlNJ'
    || 'c2RDbDlablZ1WTNScGIyNGdlU2hsTEhRcGUyWnZjaWhPVzJWZFBYUXNaVDB3TzJVOGRDNXNaVzVuZEdnN1pTc3JLWGd1WVdSa0tIUmJaVjBwZlhaaGNpQmZQ'
    || 'U0VvZEhsd1pXOW1JSGRwYm1SdmR6NGlkU0o4ZkhSNWNHVnZaaUIzYVc1a2IzY3VaRzlqZFcxbGJuUStJblVpZkh4MGVYQmxiMllnZDJsdVpHOTNMbVJ2WTNW'
    || 'dFpXNTBMbU55WldGMFpVVnNaVzFsYm5RK0luVWlLU3gzUFU5aWFtVmpkQzV3Y205MGIzUjVjR1V1YUdGelQzZHVVSEp2Y0dWeWRIa3NRajB2WGxzNlFTMWFY'
    || 'MkV0ZWx4MU1EQkRNQzFjZFRBd1JEWmNkVEF3UkRndFhIVXdNRVkyWEhVd01FWTRMVngxTURKR1JseDFNRE0zTUMxY2RUQXpOMFJjZFRBek4wWXRYSFV4Umta'
    || 'R1hIVXlNREJETFZ4MU1qQXdSRngxTWpBM01DMWNkVEl4T0VaY2RUSkRNREF0WEhVeVJrVkdYSFV6TURBeExWeDFSRGRHUmx4MVJqa3dNQzFjZFVaRVEwWmNk'
    || 'VVpFUmpBdFhIVkdSa1pFWFZzNlFTMWFYMkV0ZWx4MU1EQkRNQzFjZFRBd1JEWmNkVEF3UkRndFhIVXdNRVkyWEhVd01FWTRMVngxTURKR1JseDFNRE0zTUMx'
    || 'Y2RUQXpOMFJjZFRBek4wWXRYSFV4UmtaR1hIVXlNREJETFZ4MU1qQXdSRngxTWpBM01DMWNkVEl4T0VaY2RUSkRNREF0WEhVeVJrVkdYSFV6TURBeExWeDFS'
    || 'RGRHUmx4MVJqa3dNQzFjZFVaRVEwWmNkVVpFUmpBdFhIVkdSa1pFWEMwdU1DMDVYSFV3TUVJM1hIVXdNekF3TFZ4MU1ETTJSbHgxTWpBelJpMWNkVEl3TkRC'
    || 'ZEtpUXZMRXc5ZTMwc1FUMTdmVHRtZFc1amRHbHZiaUJJS0dVcGUzSmxkSFZ5YmlCM0xtTmhiR3dvUVN4bEtUOGhNRHAzTG1OaGJHd29UQ3hsS1Q4aE1UcENM'
    || 'blJsYzNRb1pTay9RVnRsWFQwaE1Eb29URnRsWFQwaE1Dd2hNU2w5Wm5WdVkzUnBiMjRnY21Vb1pTeDBMRzRzY2lsN2FXWW9iaUU5UFc1MWJHd21KbTR1ZEhs'
    || 'd1pUMDlQVEFwY21WMGRYSnVJVEU3YzNkcGRHTm9LSFI1Y0dWdlppQjBLWHRqWVhObEltWjFibU4wYVc5dUlqcGpZWE5sSW5ONWJXSnZiQ0k2Y21WMGRYSnVJ'
    || 'VEE3WTJGelpTSmliMjlzWldGdUlqcHlaWFIxY200Z2NqOGhNVHB1SVQwOWJuVnNiRDhoYmk1aFkyTmxjSFJ6UW05dmJHVmhibk02S0dVOVpTNTBiMHh2ZDJW'
    || 'eVEyRnpaU2dwTG5Oc2FXTmxLREFzTlNrc1pTRTlQU0prWVhSaExTSW1KbVVoUFQwaVlYSnBZUzBpS1R0a1pXWmhkV3gwT25KbGRIVnliaUV4ZlgxbWRXNWpk'
    || 'R2x2YmlCSEtHVXNkQ3h1TEhJcGUybG1LSFE5UFQxdWRXeHNmSHgwZVhCbGIyWWdkRDRpZFNKOGZISmxLR1VzZEN4dUxISXBLWEpsZEhWeWJpRXdPMmxtS0hJ'
    || 'cGNtVjBkWEp1SVRFN2FXWW9iaUU5UFc1MWJHd3BjM2RwZEdOb0tHNHVkSGx3WlNsN1kyRnpaU0F6T25KbGRIVnliaUYwTzJOaGMyVWdORHB5WlhSMWNtNGdk'
    || 'RDA5UFNFeE8yTmhjMlVnTlRweVpYUjFjbTRnYVhOT1lVNG9kQ2s3WTJGelpTQTJPbkpsZEhWeWJpQnBjMDVoVGloMEtYeDhNVDUwZlhKbGRIVnliaUV4Zlda'
    || 'MWJtTjBhVzl1SUZnb1pTeDBMRzRzY2l4c0xHa3NieWw3ZEdocGN5NWhZMk5sY0hSelFtOXZiR1ZoYm5NOWREMDlQVEo4ZkhROVBUMHpmSHgwUFQwOU5DeDBh'
    || 'R2x6TG1GMGRISnBZblYwWlU1aGJXVTljaXgwYUdsekxtRjBkSEpwWW5WMFpVNWhiV1Z6Y0dGalpUMXNMSFJvYVhNdWJYVnpkRlZ6WlZCeWIzQmxjblI1UFc0'
    || 'c2RHaHBjeTV3Y205d1pYSjBlVTVoYldVOVpTeDBhR2x6TG5SNWNHVTlkQ3gwYUdsekxuTmhibWwwYVhwbFZWSk1QV2tzZEdocGN5NXlaVzF2ZG1WRmJYQjBl'
    || 'Vk4wY21sdVp6MXZmWFpoY2lCV1BYdDlPeUpqYUdsc1pISmxiaUJrWVc1blpYSnZkWE5zZVZObGRFbHVibVZ5U0ZSTlRDQmtaV1poZFd4MFZtRnNkV1VnWkdW'
    || 'bVlYVnNkRU5vWldOclpXUWdhVzV1WlhKSVZFMU1JSE4xY0hCeVpYTnpRMjl1ZEdWdWRFVmthWFJoWW14bFYyRnlibWx1WnlCemRYQndjbVZ6YzBoNVpISmhk'
    || 'R2x2YmxkaGNtNXBibWNnYzNSNWJHVWlMbk53YkdsMEtDSWdJaWt1Wm05eVJXRmphQ2htZFc1amRHbHZiaWhsS1h0V1cyVmRQVzVsZHlCWUtHVXNNQ3doTVN4'
    || 'bExHNTFiR3dzSVRFc0lURXBmU2tzVzFzaVlXTmpaWEIwUTJoaGNuTmxkQ0lzSW1GalkyVndkQzFqYUdGeWMyVjBJbDBzV3lKamJHRnpjMDVoYldVaUxDSmpi'
    || 'R0Z6Y3lKZExGc2lhSFJ0YkVadmNpSXNJbVp2Y2lKZExGc2lhSFIwY0VWeGRXbDJJaXdpYUhSMGNDMWxjWFZwZGlKZFhTNW1iM0pGWVdOb0tHWjFibU4wYVc5'
    || 'dUtHVXBlM1poY2lCMFBXVmJNRjA3Vmx0MFhUMXVaWGNnV0NoMExERXNJVEVzWlZzeFhTeHVkV3hzTENFeExDRXhLWDBwTEZzaVkyOXVkR1Z1ZEVWa2FYUmhZ'
    || 'bXhsSWl3aVpISmhaMmRoWW14bElpd2ljM0JsYkd4RGFHVmpheUlzSW5aaGJIVmxJbDB1Wm05eVJXRmphQ2htZFc1amRHbHZiaWhsS1h0V1cyVmRQVzVsZHlC'
    || 'WUtHVXNNaXdoTVN4bExuUnZURzkzWlhKRFlYTmxLQ2tzYm5Wc2JDd2hNU3doTVNsOUtTeGJJbUYxZEc5U1pYWmxjbk5sSWl3aVpYaDBaWEp1WVd4U1pYTnZk'
    || 'WEpqWlhOU1pYRjFhWEpsWkNJc0ltWnZZM1Z6WVdKc1pTSXNJbkJ5WlhObGNuWmxRV3h3YUdFaVhTNW1iM0pGWVdOb0tHWjFibU4wYVc5dUtHVXBlMVpiWlYw'
    || 'OWJtVjNJRmdvWlN3eUxDRXhMR1VzYm5Wc2JDd2hNU3doTVNsOUtTd2lZV3hzYjNkR2RXeHNVMk55WldWdUlHRnplVzVqSUdGMWRHOUdiMk4xY3lCaGRYUnZV'
    || 'R3hoZVNCamIyNTBjbTlzY3lCa1pXWmhkV3gwSUdSbFptVnlJR1JwYzJGaWJHVmtJR1JwYzJGaWJHVlFhV04wZFhKbFNXNVFhV04wZFhKbElHUnBjMkZpYkdW'
    || 'U1pXMXZkR1ZRYkdGNVltRmpheUJtYjNKdFRtOVdZV3hwWkdGMFpTQm9hV1JrWlc0Z2JHOXZjQ0J1YjAxdlpIVnNaU0J1YjFaaGJHbGtZWFJsSUc5d1pXNGdj'
    || 'R3hoZVhOSmJteHBibVVnY21WaFpFOXViSGtnY21WeGRXbHlaV1FnY21WMlpYSnpaV1FnYzJOdmNHVmtJSE5sWVcxc1pYTnpJR2wwWlcxVFkyOXdaU0l1YzNC'
    || 'c2FYUW9JaUFpS1M1bWIzSkZZV05vS0daMWJtTjBhVzl1S0dVcGUxWmJaVjA5Ym1WM0lGZ29aU3d6TENFeExHVXVkRzlNYjNkbGNrTmhjMlVvS1N4dWRXeHNM'
    || 'Q0V4TENFeEtYMHBMRnNpWTJobFkydGxaQ0lzSW0xMWJIUnBjR3hsSWl3aWJYVjBaV1FpTENKelpXeGxZM1JsWkNKZExtWnZja1ZoWTJnb1puVnVZM1JwYjI0'
    || 'b1pTbDdWbHRsWFQxdVpYY2dXQ2hsTERNc0lUQXNaU3h1ZFd4c0xDRXhMQ0V4S1gwcExGc2lZMkZ3ZEhWeVpTSXNJbVJ2ZDI1c2IyRmtJbDB1Wm05eVJXRmph'
    || 'Q2htZFc1amRHbHZiaWhsS1h0V1cyVmRQVzVsZHlCWUtHVXNOQ3doTVN4bExHNTFiR3dzSVRFc0lURXBmU2tzV3lKamIyeHpJaXdpY205M2N5SXNJbk5wZW1V'
    || 'aUxDSnpjR0Z1SWwwdVptOXlSV0ZqYUNobWRXNWpkR2x2YmlobEtYdFdXMlZkUFc1bGR5QllLR1VzTml3aE1TeGxMRzUxYkd3c0lURXNJVEVwZlNrc1d5Snli'
    || 'M2RUY0dGdUlpd2ljM1JoY25RaVhTNW1iM0pGWVdOb0tHWjFibU4wYVc5dUtHVXBlMVpiWlYwOWJtVjNJRmdvWlN3MUxDRXhMR1V1ZEc5TWIzZGxja05oYzJV'
    || 'b0tTeHVkV3hzTENFeExDRXhLWDBwTzNaaGNpQkdaVDB2VzF3dE9sMG9XMkV0ZWwwcEwyYzdablZ1WTNScGIyNGdUbVVvWlNsN2NtVjBkWEp1SUdWYk1WMHVk'
    || 'RzlWY0hCbGNrTmhjMlVvS1gwaVlXTmpaVzUwTFdobGFXZG9kQ0JoYkdsbmJtMWxiblF0WW1GelpXeHBibVVnWVhKaFltbGpMV1p2Y20wZ1ltRnpaV3hwYm1V'
    || 'dGMyaHBablFnWTJGd0xXaGxhV2RvZENCamJHbHdMWEJoZEdnZ1kyeHBjQzF5ZFd4bElHTnZiRzl5TFdsdWRHVnljRzlzWVhScGIyNGdZMjlzYjNJdGFXNTBa'
    || 'WEp3YjJ4aGRHbHZiaTFtYVd4MFpYSnpJR052Ykc5eUxYQnliMlpwYkdVZ1kyOXNiM0l0Y21WdVpHVnlhVzVuSUdSdmJXbHVZVzUwTFdKaGMyVnNhVzVsSUdW'
    || 'dVlXSnNaUzFpWVdOclozSnZkVzVrSUdacGJHd3RiM0JoWTJsMGVTQm1hV3hzTFhKMWJHVWdabXh2YjJRdFkyOXNiM0lnWm14dmIyUXRiM0JoWTJsMGVTQm1i'
    || 'MjUwTFdaaGJXbHNlU0JtYjI1MExYTnBlbVVnWm05dWRDMXphWHBsTFdGa2FuVnpkQ0JtYjI1MExYTjBjbVYwWTJnZ1ptOXVkQzF6ZEhsc1pTQm1iMjUwTFha'
    || 'aGNtbGhiblFnWm05dWRDMTNaV2xuYUhRZ1oyeDVjR2d0Ym1GdFpTQm5iSGx3YUMxdmNtbGxiblJoZEdsdmJpMW9iM0pwZW05dWRHRnNJR2RzZVhCb0xXOXlh'
    || 'V1Z1ZEdGMGFXOXVMWFpsY25ScFkyRnNJR2h2Y21sNkxXRmtkaTE0SUdodmNtbDZMVzl5YVdkcGJpMTRJR2x0WVdkbExYSmxibVJsY21sdVp5QnNaWFIwWlhJ'
    || 'dGMzQmhZMmx1WnlCc2FXZG9kR2x1WnkxamIyeHZjaUJ0WVhKclpYSXRaVzVrSUcxaGNtdGxjaTF0YVdRZ2JXRnlhMlZ5TFhOMFlYSjBJRzkyWlhKc2FXNWxM'
    || 'WEJ2YzJsMGFXOXVJRzkyWlhKc2FXNWxMWFJvYVdOcmJtVnpjeUJ3WVdsdWRDMXZjbVJsY2lCd1lXNXZjMlV0TVNCd2IybHVkR1Z5TFdWMlpXNTBjeUJ5Wlc1'
    || 'a1pYSnBibWN0YVc1MFpXNTBJSE5vWVhCbExYSmxibVJsY21sdVp5QnpkRzl3TFdOdmJHOXlJSE4wYjNBdGIzQmhZMmwwZVNCemRISnBhMlYwYUhKdmRXZG9M'
    || 'WEJ2YzJsMGFXOXVJSE4wY21sclpYUm9jbTkxWjJndGRHaHBZMnR1WlhOeklITjBjbTlyWlMxa1lYTm9ZWEp5WVhrZ2MzUnliMnRsTFdSaGMyaHZabVp6WlhR'
    || 'Z2MzUnliMnRsTFd4cGJtVmpZWEFnYzNSeWIydGxMV3hwYm1WcWIybHVJSE4wY205clpTMXRhWFJsY214cGJXbDBJSE4wY205clpTMXZjR0ZqYVhSNUlITjBj'
    || 'bTlyWlMxM2FXUjBhQ0IwWlhoMExXRnVZMmh2Y2lCMFpYaDBMV1JsWTI5eVlYUnBiMjRnZEdWNGRDMXlaVzVrWlhKcGJtY2dkVzVrWlhKc2FXNWxMWEJ2YzJs'
    || 'MGFXOXVJSFZ1WkdWeWJHbHVaUzEwYUdsamEyNWxjM01nZFc1cFkyOWtaUzFpYVdScElIVnVhV052WkdVdGNtRnVaMlVnZFc1cGRITXRjR1Z5TFdWdElIWXRZ'
    || 'V3h3YUdGaVpYUnBZeUIyTFdoaGJtZHBibWNnZGkxcFpHVnZaM0poY0docFl5QjJMVzFoZEdobGJXRjBhV05oYkNCMlpXTjBiM0l0WldabVpXTjBJSFpsY25R'
    || 'dFlXUjJMWGtnZG1WeWRDMXZjbWxuYVc0dGVDQjJaWEowTFc5eWFXZHBiaTE1SUhkdmNtUXRjM0JoWTJsdVp5QjNjbWwwYVc1bkxXMXZaR1VnZUcxc2JuTTZl'
    || 'R3hwYm1zZ2VDMW9aV2xuYUhRaUxuTndiR2wwS0NJZ0lpa3VabTl5UldGamFDaG1kVzVqZEdsdmJpaGxLWHQyWVhJZ2REMWxMbkpsY0d4aFkyVW9SbVVzVG1V'
    || 'cE8xWmJkRjA5Ym1WM0lGZ29kQ3d4TENFeExHVXNiblZzYkN3aE1Td2hNU2w5S1N3aWVHeHBibXM2WVdOMGRXRjBaU0I0YkdsdWF6cGhjbU55YjJ4bElIaHNh'
    || 'VzVyT25KdmJHVWdlR3hwYm1zNmMyaHZkeUI0YkdsdWF6cDBhWFJzWlNCNGJHbHVhenAwZVhCbElpNXpjR3hwZENnaUlDSXBMbVp2Y2tWaFkyZ29ablZ1WTNS'
    || 'cGIyNG9aU2w3ZG1GeUlIUTlaUzV5WlhCc1lXTmxLRVpsTEU1bEtUdFdXM1JkUFc1bGR5QllLSFFzTVN3aE1TeGxMQ0pvZEhSd09pOHZkM2QzTG5jekxtOXla'
    || 'eTh4T1RrNUwzaHNhVzVySWl3aE1Td2hNU2w5S1N4YkluaHRiRHBpWVhObElpd2llRzFzT214aGJtY2lMQ0o0Yld3NmMzQmhZMlVpWFM1bWIzSkZZV05vS0da'
    || 'MWJtTjBhVzl1S0dVcGUzWmhjaUIwUFdVdWNtVndiR0ZqWlNoR1pTeE9aU2s3Vmx0MFhUMXVaWGNnV0NoMExERXNJVEVzWlN3aWFIUjBjRG92TDNkM2R5NTNN'
    || 'eTV2Y21jdldFMU1MekU1T1RndmJtRnRaWE53WVdObElpd2hNU3doTVNsOUtTeGJJblJoWWtsdVpHVjRJaXdpWTNKdmMzTlBjbWxuYVc0aVhTNW1iM0pGWVdO'
    || 'b0tHWjFibU4wYVc5dUtHVXBlMVpiWlYwOWJtVjNJRmdvWlN3eExDRXhMR1V1ZEc5TWIzZGxja05oYzJVb0tTeHVkV3hzTENFeExDRXhLWDBwTEZZdWVHeHBi'
    || 'bXRJY21WbVBXNWxkeUJZS0NKNGJHbHVhMGh5WldZaUxERXNJVEVzSW5oc2FXNXJPbWh5WldZaUxDSm9kSFJ3T2k4dmQzZDNMbmN6TG05eVp5OHhPVGs1TDNo'
    || 'c2FXNXJJaXdoTUN3aE1Ta3NXeUp6Y21NaUxDSm9jbVZtSWl3aVlXTjBhVzl1SWl3aVptOXliVUZqZEdsdmJpSmRMbVp2Y2tWaFkyZ29ablZ1WTNScGIyNG9a'
    || 'U2w3Vmx0bFhUMXVaWGNnV0NobExERXNJVEVzWlM1MGIweHZkMlZ5UTJGelpTZ3BMRzUxYkd3c0lUQXNJVEFwZlNrN1puVnVZM1JwYjI0Z1RHVW9aU3gwTEc0'
    || 'c2NpbDdkbUZ5SUd3OVZpNW9ZWE5QZDI1UWNtOXdaWEowZVNoMEtUOVdXM1JkT201MWJHdzdLR3doUFQxdWRXeHNQMnd1ZEhsd1pTRTlQVEE2Y254OElTZ3lQ'
    || 'SFF1YkdWdVozUm9LWHg4ZEZzd1hTRTlQU0p2SWlZbWRGc3dYU0U5UFNKUElueDhkRnN4WFNFOVBTSnVJaVltZEZzeFhTRTlQU0pPSWlrbUppaEhLSFFzYml4'
    || 'c0xISXBKaVlvYmoxdWRXeHNLU3h5Zkh4c1BUMDliblZzYkQ5SUtIUXBKaVlvYmowOVBXNTFiR3cvWlM1eVpXMXZkbVZCZEhSeWFXSjFkR1VvZENrNlpTNXpa'
    || 'WFJCZEhSeWFXSjFkR1VvZEN3aUlpdHVLU2s2YkM1dGRYTjBWWE5sVUhKdmNHVnlkSGsvWlZ0c0xuQnliM0JsY25SNVRtRnRaVjA5YmowOVBXNTFiR3cvYkM1'
    || 'MGVYQmxQVDA5TXo4aE1Ub2lJanB1T2loMFBXd3VZWFIwY21saWRYUmxUbUZ0WlN4eVBXd3VZWFIwY21saWRYUmxUbUZ0WlhOd1lXTmxMRzQ5UFQxdWRXeHNQ'
    || 'MlV1Y21WdGIzWmxRWFIwY21saWRYUmxLSFFwT2loc1BXd3VkSGx3WlN4dVBXdzlQVDB6Zkh4c1BUMDlOQ1ltYmowOVBTRXdQeUlpT2lJaUsyNHNjajlsTG5O'
    || 'bGRFRjBkSEpwWW5WMFpVNVRLSElzZEN4dUtUcGxMbk5sZEVGMGRISnBZblYwWlNoMExHNHBLU2twZlhaaGNpQnZaVDExTGw5ZlUwVkRVa1ZVWDBsT1ZFVlNU'
    || 'a0ZNVTE5RVQxOU9UMVJmVlZORlgwOVNYMWxQVlY5WFNVeE1YMEpGWDBaSlVrVkVMRlZsUFZONWJXSnZiQzVtYjNJb0luSmxZV04wTG1Wc1pXMWxiblFpS1N4'
    || 'VFpUMVRlVzFpYjJ3dVptOXlLQ0p5WldGamRDNXdiM0owWVd3aUtTeHFaVDFUZVcxaWIyd3VabTl5S0NKeVpXRmpkQzVtY21GbmJXVnVkQ0lwTEVsbFBWTjVi'
    || 'V0p2YkM1bWIzSW9JbkpsWVdOMExuTjBjbWxqZEY5dGIyUmxJaWtzY0dVOVUzbHRZbTlzTG1admNpZ2ljbVZoWTNRdWNISnZabWxzWlhJaUtTeHFkRDFUZVcx'
    || 'aWIyd3VabTl5S0NKeVpXRmpkQzV3Y205MmFXUmxjaUlwTEhSdVBWTjViV0p2YkM1bWIzSW9JbkpsWVdOMExtTnZiblJsZUhRaUtTeDVkRDFUZVcxaWIyd3Va'
    || 'bTl5S0NKeVpXRmpkQzVtYjNKM1lYSmtYM0psWmlJcExFdGxQVk41YldKdmJDNW1iM0lvSW5KbFlXTjBMbk4xYzNCbGJuTmxJaWtzWVhROVUzbHRZbTlzTG1a'
    || 'dmNpZ2ljbVZoWTNRdWMzVnpjR1Z1YzJWZmJHbHpkQ0lwTEhoMFBWTjViV0p2YkM1bWIzSW9JbkpsWVdOMExtMWxiVzhpS1N4SVpUMVRlVzFpYjJ3dVptOXlL'
    || 'Q0p5WldGamRDNXNZWHA1SWlrc2FHVTlVM2x0WW05c0xtWnZjaWdpY21WaFkzUXViMlptYzJOeVpXVnVJaWtzVWoxVGVXMWliMnd1YVhSbGNtRjBiM0k3Wm5W'
    || 'dVkzUnBiMjRnSkNobEtYdHlaWFIxY200Z1pUMDlQVzUxYkd4OGZIUjVjR1Z2WmlCbElUMGliMkpxWldOMElqOXVkV3hzT2lobFBWSW1KbVZiVWwxOGZHVmJJ'
    || 'a0JBYVhSbGNtRjBiM0lpWFN4MGVYQmxiMllnWlQwOUltWjFibU4wYVc5dUlqOWxPbTUxYkd3cGZYWmhjaUJQUFU5aWFtVmpkQzVoYzNOcFoyNHNhRHRtZFc1'
    || 'amRHbHZiaUJyS0dVcGUybG1LR2c5UFQxMmIybGtJREFwZEhKNWUzUm9jbTkzSUVWeWNtOXlLQ2w5WTJGMFkyZ29iaWw3ZG1GeUlIUTliaTV6ZEdGamF5NTBj'
    || 'bWx0S0NrdWJXRjBZMmdvTDF4dUtDQXFLR0YwSUNrL0tTOHBPMmc5ZENZbWRGc3hYWHg4SWlKOWNtVjBkWEp1WUFwZ0syZ3JaWDEyWVhJZ1VUMGhNVHRtZFc1'
    || 'amRHbHZiaUJMS0dVc2RDbDdhV1lvSVdWOGZGRXBjbVYwZFhKdUlpSTdVVDBoTUR0MllYSWdiajFGY25KdmNpNXdjbVZ3WVhKbFUzUmhZMnRVY21GalpUdEZj'
    || 'bkp2Y2k1d2NtVndZWEpsVTNSaFkydFVjbUZqWlQxMmIybGtJREE3ZEhKNWUybG1LSFFwYVdZb2REMW1kVzVqZEdsdmJpZ3BlM1JvY205M0lFVnljbTl5S0Ns'
    || 'OUxFOWlhbVZqZEM1a1pXWnBibVZRY205d1pYSjBlU2gwTG5CeWIzUnZkSGx3WlN3aWNISnZjSE1pTEh0elpYUTZablZ1WTNScGIyNG9LWHQwYUhKdmR5QkZj'
    || 'bkp2Y2lncGZYMHBMSFI1Y0dWdlppQlNaV1pzWldOMFBUMGliMkpxWldOMElpWW1VbVZtYkdWamRDNWpiMjV6ZEhKMVkzUXBlM1J5ZVh0U1pXWnNaV04wTG1O'
    || 'dmJuTjBjblZqZENoMExGdGRLWDFqWVhSamFDaG5LWHQyWVhJZ2NqMW5mVkpsWm14bFkzUXVZMjl1YzNSeWRXTjBLR1VzVzEwc2RDbDlaV3h6Wlh0MGNubDdk'
    || 'QzVqWVd4c0tDbDlZMkYwWTJnb1p5bDdjajFuZldVdVkyRnNiQ2gwTG5CeWIzUnZkSGx3WlNsOVpXeHpaWHQwY25sN2RHaHliM2NnUlhKeWIzSW9LWDFqWVhS'
    || 'amFDaG5LWHR5UFdkOVpTZ3BmWDFqWVhSamFDaG5LWHRwWmlobkppWnlKaVowZVhCbGIyWWdaeTV6ZEdGamF6MDlJbk4wY21sdVp5SXBlMlp2Y2loMllYSWdi'
    || 'RDFuTG5OMFlXTnJMbk53YkdsMEtHQUtZQ2tzYVQxeUxuTjBZV05yTG5Od2JHbDBLR0FLWUNrc2J6MXNMbXhsYm1kMGFDMHhMR005YVM1c1pXNW5kR2d0TVRz'
    || 'eFBEMXZKaVl3UEQxakppWnNXMjlkSVQwOWFWdGpYVHNwWXkwdE8yWnZjaWc3TVR3OWJ5WW1NRHc5WXp0dkxTMHNZeTB0S1dsbUtHeGJiMTBoUFQxcFcyTmRL'
    || 'WHRwWmlodklUMDlNWHg4WXlFOVBURXBaRzhnYVdZb2J5MHRMR010TFN3d1BtTjhmR3hiYjEwaFBUMXBXMk5kS1h0MllYSWdaRDFnQ21BcmJGdHZYUzV5WlhC'
    || 'c1lXTmxLQ0lnWVhRZ2JtVjNJQ0lzSWlCaGRDQWlLVHR5WlhSMWNtNGdaUzVrYVhOd2JHRjVUbUZ0WlNZbVpDNXBibU5zZFdSbGN5Z2lQR0Z1YjI1NWJXOTFj'
    || 'ejRpS1NZbUtHUTlaQzV5WlhCc1lXTmxLQ0k4WVc1dmJubHRiM1Z6UGlJc1pTNWthWE53YkdGNVRtRnRaU2twTEdSOWQyaHBiR1VvTVR3OWJ5WW1NRHc5WXlr'
    || 'N1luSmxZV3Q5ZlgxbWFXNWhiR3g1ZTFFOUlURXNSWEp5YjNJdWNISmxjR0Z5WlZOMFlXTnJWSEpoWTJVOWJuMXlaWFIxY200b1pUMWxQMlV1WkdsemNHeGhl'
    || 'VTVoYldWOGZHVXVibUZ0WlRvaUlpay9heWhsS1RvaUluMW1kVzVqZEdsdmJpQktLR1VwZTNOM2FYUmphQ2hsTG5SaFp5bDdZMkZ6WlNBMU9uSmxkSFZ5YmlC'
    || 'cktHVXVkSGx3WlNrN1kyRnpaU0F4TmpweVpYUjFjbTRnYXlnaVRHRjZlU0lwTzJOaGMyVWdNVE02Y21WMGRYSnVJR3NvSWxOMWMzQmxibk5sSWlrN1kyRnpa'
    || 'U0F4T1RweVpYUjFjbTRnYXlnaVUzVnpjR1Z1YzJWTWFYTjBJaWs3WTJGelpTQXdPbU5oYzJVZ01qcGpZWE5sSURFMU9uSmxkSFZ5YmlCbFBVc29aUzUwZVhC'
    || 'bExDRXhLU3hsTzJOaGMyVWdNVEU2Y21WMGRYSnVJR1U5U3lobExuUjVjR1V1Y21WdVpHVnlMQ0V4S1N4bE8yTmhjMlVnTVRweVpYUjFjbTRnWlQxTEtHVXVk'
    || 'SGx3WlN3aE1Da3NaVHRrWldaaGRXeDBPbkpsZEhWeWJpSWlmWDFtZFc1amRHbHZiaUJ4S0dVcGUybG1LR1U5UFc1MWJHd3BjbVYwZFhKdUlHNTFiR3c3YVdZ'
    || 'b2RIbHdaVzltSUdVOVBTSm1kVzVqZEdsdmJpSXBjbVYwZFhKdUlHVXVaR2x6Y0d4aGVVNWhiV1Y4ZkdVdWJtRnRaWHg4Ym5Wc2JEdHBaaWgwZVhCbGIyWWda'
    || 'VDA5SW5OMGNtbHVaeUlwY21WMGRYSnVJR1U3YzNkcGRHTm9LR1VwZTJOaGMyVWdhbVU2Y21WMGRYSnVJa1p5WVdkdFpXNTBJanRqWVhObElGTmxPbkpsZEhW'
    || 'eWJpSlFiM0owWVd3aU8yTmhjMlVnY0dVNmNtVjBkWEp1SWxCeWIyWnBiR1Z5SWp0allYTmxJRWxsT25KbGRIVnliaUpUZEhKcFkzUk5iMlJsSWp0allYTmxJ'
    || 'RXRsT25KbGRIVnliaUpUZFhOd1pXNXpaU0k3WTJGelpTQmhkRHB5WlhSMWNtNGlVM1Z6Y0dWdWMyVk1hWE4wSW4xcFppaDBlWEJsYjJZZ1pUMDlJbTlpYW1W'
    || 'amRDSXBjM2RwZEdOb0tHVXVKQ1IwZVhCbGIyWXBlMk5oYzJVZ2RHNDZjbVYwZFhKdUtHVXVaR2x6Y0d4aGVVNWhiV1Y4ZkNKRGIyNTBaWGgwSWlrcklpNURi'
    || 'MjV6ZFcxbGNpSTdZMkZ6WlNCcWREcHlaWFIxY200b1pTNWZZMjl1ZEdWNGRDNWthWE53YkdGNVRtRnRaWHg4SWtOdmJuUmxlSFFpS1NzaUxsQnliM1pwWkdW'
    || 'eUlqdGpZWE5sSUhsME9uWmhjaUIwUFdVdWNtVnVaR1Z5TzNKbGRIVnliaUJsUFdVdVpHbHpjR3hoZVU1aGJXVXNaWHg4S0dVOWRDNWthWE53YkdGNVRtRnRa'
    || 'WHg4ZEM1dVlXMWxmSHdpSWl4bFBXVWhQVDBpSWo4aVJtOXlkMkZ5WkZKbFppZ2lLMlVySWlraU9pSkdiM0ozWVhKa1VtVm1JaWtzWlR0allYTmxJSGgwT25K'
    || 'bGRIVnliaUIwUFdVdVpHbHpjR3hoZVU1aGJXVjhmRzUxYkd3c2RDRTlQVzUxYkd3L2REcHhLR1V1ZEhsd1pTbDhmQ0pOWlcxdklqdGpZWE5sSUVobE9uUTla'
    || 'UzVmY0dGNWJHOWhaQ3hsUFdVdVgybHVhWFE3ZEhKNWUzSmxkSFZ5YmlCeEtHVW9kQ2twZldOaGRHTm9lMzE5Y21WMGRYSnVJRzUxYkd4OVpuVnVZM1JwYjI0'
    || 'Z2JHVW9aU2w3ZG1GeUlIUTlaUzUwZVhCbE8zTjNhWFJqYUNobExuUmhaeWw3WTJGelpTQXlORHB5WlhSMWNtNGlRMkZqYUdVaU8yTmhjMlVnT1RweVpYUjFj'
    || 'bTRvZEM1a2FYTndiR0Y1VG1GdFpYeDhJa052Ym5SbGVIUWlLU3NpTGtOdmJuTjFiV1Z5SWp0allYTmxJREV3T25KbGRIVnliaWgwTGw5amIyNTBaWGgwTG1S'
    || 'cGMzQnNZWGxPWVcxbGZId2lRMjl1ZEdWNGRDSXBLeUl1VUhKdmRtbGtaWElpTzJOaGMyVWdNVGc2Y21WMGRYSnVJa1JsYUhsa2NtRjBaV1JHY21GbmJXVnVk'
    || 'Q0k3WTJGelpTQXhNVHB5WlhSMWNtNGdaVDEwTG5KbGJtUmxjaXhsUFdVdVpHbHpjR3hoZVU1aGJXVjhmR1V1Ym1GdFpYeDhJaUlzZEM1a2FYTndiR0Y1VG1G'
    || 'dFpYeDhLR1VoUFQwaUlqOGlSbTl5ZDJGeVpGSmxaaWdpSzJVcklpa2lPaUpHYjNKM1lYSmtVbVZtSWlrN1kyRnpaU0EzT25KbGRIVnliaUpHY21GbmJXVnVk'
    || 'Q0k3WTJGelpTQTFPbkpsZEhWeWJpQjBPMk5oYzJVZ05EcHlaWFIxY200aVVHOXlkR0ZzSWp0allYTmxJRE02Y21WMGRYSnVJbEp2YjNRaU8yTmhjMlVnTmpw'
    || 'eVpYUjFjbTRpVkdWNGRDSTdZMkZ6WlNBeE5qcHlaWFIxY200Z2NTaDBLVHRqWVhObElEZzZjbVYwZFhKdUlIUTlQVDFKWlQ4aVUzUnlhV04wVFc5a1pTSTZJ'
    || 'azF2WkdVaU8yTmhjMlVnTWpJNmNtVjBkWEp1SWs5bVpuTmpjbVZsYmlJN1kyRnpaU0F4TWpweVpYUjFjbTRpVUhKdlptbHNaWElpTzJOaGMyVWdNakU2Y21W'
    || 'MGRYSnVJbE5qYjNCbElqdGpZWE5sSURFek9uSmxkSFZ5YmlKVGRYTndaVzV6WlNJN1kyRnpaU0F4T1RweVpYUjFjbTRpVTNWemNHVnVjMlZNYVhOMElqdGpZ'
    || 'WE5sSURJMU9uSmxkSFZ5YmlKVWNtRmphVzVuVFdGeWEyVnlJanRqWVhObElERTZZMkZ6WlNBd09tTmhjMlVnTVRjNlkyRnpaU0F5T21OaGMyVWdNVFE2WTJG'
    || 'elpTQXhOVHBwWmloMGVYQmxiMllnZEQwOUltWjFibU4wYVc5dUlpbHlaWFIxY200Z2RDNWthWE53YkdGNVRtRnRaWHg4ZEM1dVlXMWxmSHh1ZFd4c08ybG1L'
    || 'SFI1Y0dWdlppQjBQVDBpYzNSeWFXNW5JaWx5WlhSMWNtNGdkSDF5WlhSMWNtNGdiblZzYkgxbWRXNWpkR2x2YmlCMFpTaGxLWHR6ZDJsMFkyZ29kSGx3Wlc5'
    || 'bUlHVXBlMk5oYzJVaVltOXZiR1ZoYmlJNlkyRnpaU0p1ZFcxaVpYSWlPbU5oYzJVaWMzUnlhVzVuSWpwallYTmxJblZ1WkdWbWFXNWxaQ0k2Y21WMGRYSnVJ'
    || 'R1U3WTJGelpTSnZZbXBsWTNRaU9uSmxkSFZ5YmlCbE8yUmxabUYxYkhRNmNtVjBkWEp1SWlKOWZXWjFibU4wYVc5dUlHRmxLR1VwZTNaaGNpQjBQV1V1ZEhs'
    || 'd1pUdHlaWFIxY200b1pUMWxMbTV2WkdWT1lXMWxLU1ltWlM1MGIweHZkMlZ5UTJGelpTZ3BQVDA5SW1sdWNIVjBJaVltS0hROVBUMGlZMmhsWTJ0aWIzZ2lm'
    || 'SHgwUFQwOUluSmhaR2x2SWlsOVpuVnVZM1JwYjI0Z1IyVW9aU2w3ZG1GeUlIUTlZV1VvWlNrL0ltTm9aV05yWldRaU9pSjJZV3gxWlNJc2JqMVBZbXBsWTNR'
    || 'dVoyVjBUM2R1VUhKdmNHVnlkSGxFWlhOamNtbHdkRzl5S0dVdVkyOXVjM1J5ZFdOMGIzSXVjSEp2ZEc5MGVYQmxMSFFwTEhJOUlpSXJaVnQwWFR0cFppZ2ha'
    || 'UzVvWVhOUGQyNVFjbTl3WlhKMGVTaDBLU1ltZEhsd1pXOW1JRzQ4SW5VaUppWjBlWEJsYjJZZ2JpNW5aWFE5UFNKbWRXNWpkR2x2YmlJbUpuUjVjR1Z2WmlC'
    || 'dUxuTmxkRDA5SW1aMWJtTjBhVzl1SWlsN2RtRnlJR3c5Ymk1blpYUXNhVDF1TG5ObGREdHlaWFIxY200Z1QySnFaV04wTG1SbFptbHVaVkJ5YjNCbGNuUjVL'
    || 'R1VzZEN4N1kyOXVabWxuZFhKaFlteGxPaUV3TEdkbGREcG1kVzVqZEdsdmJpZ3BlM0psZEhWeWJpQnNMbU5oYkd3b2RHaHBjeWw5TEhObGREcG1kVzVqZEds'
    || 'dmJpaHZLWHR5UFNJaUsyOHNhUzVqWVd4c0tIUm9hWE1zYnlsOWZTa3NUMkpxWldOMExtUmxabWx1WlZCeWIzQmxjblI1S0dVc2RDeDdaVzUxYldWeVlXSnNa'
    || 'VHB1TG1WdWRXMWxjbUZpYkdWOUtTeDdaMlYwVm1Gc2RXVTZablZ1WTNScGIyNG9LWHR5WlhSMWNtNGdjbjBzYzJWMFZtRnNkV1U2Wm5WdVkzUnBiMjRvYnls'
    || 'N2NqMGlJaXR2ZlN4emRHOXdWSEpoWTJ0cGJtYzZablZ1WTNScGIyNG9LWHRsTGw5MllXeDFaVlJ5WVdOclpYSTliblZzYkN4a1pXeGxkR1VnWlZ0MFhYMTlm'
    || 'WDFtZFc1amRHbHZiaUJOY2lobEtYdGxMbDkyWVd4MVpWUnlZV05yWlhKOGZDaGxMbDkyWVd4MVpWUnlZV05yWlhJOVIyVW9aU2twZldaMWJtTjBhVzl1SUda'
    || 'ektHVXBlMmxtS0NGbEtYSmxkSFZ5YmlFeE8zWmhjaUIwUFdVdVgzWmhiSFZsVkhKaFkydGxjanRwWmlnaGRDbHlaWFIxY200aE1EdDJZWElnYmoxMExtZGxk'
    || 'RlpoYkhWbEtDa3NjajBpSWp0eVpYUjFjbTRnWlNZbUtISTlZV1VvWlNrL1pTNWphR1ZqYTJWa1B5SjBjblZsSWpvaVptRnNjMlVpT21VdWRtRnNkV1VwTEdV'
    || 'OWNpeGxJVDA5Ymo4b2RDNXpaWFJXWVd4MVpTaGxLU3doTUNrNklURjlablZ1WTNScGIyNGdVSElvWlNsN2FXWW9aVDFsZkh3b2RIbHdaVzltSUdSdlkzVnRa'
    || 'VzUwUENKMUlqOWtiMk4xYldWdWREcDJiMmxrSURBcExIUjVjR1Z2WmlCbFBpSjFJaWx5WlhSMWNtNGdiblZzYkR0MGNubDdjbVYwZFhKdUlHVXVZV04wYVha'
    || 'bFJXeGxiV1Z1ZEh4OFpTNWliMlI1ZldOaGRHTm9lM0psZEhWeWJpQmxMbUp2WkhsOWZXWjFibU4wYVc5dUlHSnNLR1VzZENsN2RtRnlJRzQ5ZEM1amFHVmph'
    || 'MlZrTzNKbGRIVnliaUJQS0h0OUxIUXNlMlJsWm1GMWJIUkRhR1ZqYTJWa09uWnZhV1FnTUN4a1pXWmhkV3gwVm1Gc2RXVTZkbTlwWkNBd0xIWmhiSFZsT25a'
    || 'dmFXUWdNQ3hqYUdWamEyVmtPbTQvUDJVdVgzZHlZWEJ3WlhKVGRHRjBaUzVwYm1sMGFXRnNRMmhsWTJ0bFpIMHBmV1oxYm1OMGFXOXVJSEJ6S0dVc2RDbDdk'
    || 'bUZ5SUc0OWRDNWtaV1poZFd4MFZtRnNkV1U5UFc1MWJHdy9JaUk2ZEM1a1pXWmhkV3gwVm1Gc2RXVXNjajEwTG1Ob1pXTnJaV1FoUFc1MWJHdy9kQzVqYUdW'
    || 'amEyVmtPblF1WkdWbVlYVnNkRU5vWldOclpXUTdiajEwWlNoMExuWmhiSFZsSVQxdWRXeHNQM1F1ZG1Gc2RXVTZiaWtzWlM1ZmQzSmhjSEJsY2xOMFlYUmxQ'
    || 'WHRwYm1sMGFXRnNRMmhsWTJ0bFpEcHlMR2x1YVhScFlXeFdZV3gxWlRwdUxHTnZiblJ5YjJ4c1pXUTZkQzUwZVhCbFBUMDlJbU5vWldOclltOTRJbng4ZEM1'
    || 'MGVYQmxQVDA5SW5KaFpHbHZJajkwTG1Ob1pXTnJaV1FoUFc1MWJHdzZkQzUyWVd4MVpTRTliblZzYkgxOVpuVnVZM1JwYjI0Z2FITW9aU3gwS1h0MFBYUXVZ'
    || 'MmhsWTJ0bFpDeDBJVDF1ZFd4c0ppWk1aU2hsTENKamFHVmphMlZrSWl4MExDRXhLWDFtZFc1amRHbHZiaUJsYVNobExIUXBlMmh6S0dVc2RDazdkbUZ5SUc0'
    || 'OWRHVW9kQzUyWVd4MVpTa3NjajEwTG5SNWNHVTdhV1lvYmlFOWJuVnNiQ2x5UFQwOUltNTFiV0psY2lJL0tHNDlQVDB3SmlabExuWmhiSFZsUFQwOUlpSjhm'
    || 'R1V1ZG1Gc2RXVWhQVzRwSmlZb1pTNTJZV3gxWlQwaUlpdHVLVHBsTG5aaGJIVmxJVDA5SWlJcmJpWW1LR1V1ZG1Gc2RXVTlJaUlyYmlrN1pXeHpaU0JwWmlo'
    || 'eVBUMDlJbk4xWW0xcGRDSjhmSEk5UFQwaWNtVnpaWFFpS1h0bExuSmxiVzkyWlVGMGRISnBZblYwWlNnaWRtRnNkV1VpS1R0eVpYUjFjbTU5ZEM1b1lYTlBk'
    || 'MjVRY205d1pYSjBlU2dpZG1Gc2RXVWlLVDkwYVNobExIUXVkSGx3WlN4dUtUcDBMbWhoYzA5M2JsQnliM0JsY25SNUtDSmtaV1poZFd4MFZtRnNkV1VpS1NZ'
    || 'bWRHa29aU3gwTG5SNWNHVXNkR1VvZEM1a1pXWmhkV3gwVm1Gc2RXVXBLU3gwTG1Ob1pXTnJaV1E5UFc1MWJHd21KblF1WkdWbVlYVnNkRU5vWldOclpXUWhQ'
    || 'VzUxYkd3bUppaGxMbVJsWm1GMWJIUkRhR1ZqYTJWa1BTRWhkQzVrWldaaGRXeDBRMmhsWTJ0bFpDbDlablZ1WTNScGIyNGdiWE1vWlN4MExHNHBlMmxtS0hR'
    || 'dWFHRnpUM2R1VUhKdmNHVnlkSGtvSW5aaGJIVmxJaWw4ZkhRdWFHRnpUM2R1VUhKdmNHVnlkSGtvSW1SbFptRjFiSFJXWVd4MVpTSXBLWHQyWVhJZ2NqMTBM'
    || 'blI1Y0dVN2FXWW9JU2h5SVQwOUluTjFZbTFwZENJbUpuSWhQVDBpY21WelpYUWlmSHgwTG5aaGJIVmxJVDA5ZG05cFpDQXdKaVowTG5aaGJIVmxJVDA5Ym5W'
    || 'c2JDa3BjbVYwZFhKdU8zUTlJaUlyWlM1ZmQzSmhjSEJsY2xOMFlYUmxMbWx1YVhScFlXeFdZV3gxWlN4dWZIeDBQVDA5WlM1MllXeDFaWHg4S0dVdWRtRnNk'
    || 'V1U5ZENrc1pTNWtaV1poZFd4MFZtRnNkV1U5ZEgxdVBXVXVibUZ0WlN4dUlUMDlJaUltSmlobExtNWhiV1U5SWlJcExHVXVaR1ZtWVhWc2RFTm9aV05yWldR'
    || 'OUlTRmxMbDkzY21Gd2NHVnlVM1JoZEdVdWFXNXBkR2xoYkVOb1pXTnJaV1FzYmlFOVBTSWlKaVlvWlM1dVlXMWxQVzRwZldaMWJtTjBhVzl1SUhScEtHVXNk'
    || 'Q3h1S1hzb2RDRTlQU0p1ZFcxaVpYSWlmSHhRY2lobExtOTNibVZ5Ukc5amRXMWxiblFwSVQwOVpTa21KaWh1UFQxdWRXeHNQMlV1WkdWbVlYVnNkRlpoYkhW'
    || 'bFBTSWlLMlV1WDNkeVlYQndaWEpUZEdGMFpTNXBibWwwYVdGc1ZtRnNkV1U2WlM1a1pXWmhkV3gwVm1Gc2RXVWhQVDBpSWl0dUppWW9aUzVrWldaaGRXeDBW'
    || 'bUZzZFdVOUlpSXJiaWtwZlhaaGNpQkNiajFCY25KaGVTNXBjMEZ5Y21GNU8yWjFibU4wYVc5dUlIbHVLR1VzZEN4dUxISXBlMmxtS0dVOVpTNXZjSFJwYjI1'
    || 'ekxIUXBlM1E5ZTMwN1ptOXlLSFpoY2lCc1BUQTdiRHh1TG14bGJtZDBhRHRzS3lzcGRGc2lKQ0lyYmx0c1hWMDlJVEE3Wm05eUtHNDlNRHR1UEdVdWJHVnVa'
    || 'M1JvTzI0ckt5bHNQWFF1YUdGelQzZHVVSEp2Y0dWeWRIa29JaVFpSzJWYmJsMHVkbUZzZFdVcExHVmJibDB1YzJWc1pXTjBaV1FoUFQxc0ppWW9aVnR1WFM1'
    || 'elpXeGxZM1JsWkQxc0tTeHNKaVp5SmlZb1pWdHVYUzVrWldaaGRXeDBVMlZzWldOMFpXUTlJVEFwZldWc2MyVjdabTl5S0c0OUlpSXJkR1VvYmlrc2REMXVk'
    || 'V3hzTEd3OU1EdHNQR1V1YkdWdVozUm9PMndyS3lsN2FXWW9aVnRzWFM1MllXeDFaVDA5UFc0cGUyVmJiRjB1YzJWc1pXTjBaV1E5SVRBc2NpWW1LR1ZiYkYw'
    || 'dVpHVm1ZWFZzZEZObGJHVmpkR1ZrUFNFd0tUdHlaWFIxY201OWRDRTlQVzUxYkd4OGZHVmJiRjB1WkdsellXSnNaV1I4ZkNoMFBXVmJiRjBwZlhRaFBUMXVk'
    || 'V3hzSmlZb2RDNXpaV3hsWTNSbFpEMGhNQ2w5ZldaMWJtTjBhVzl1SUc1cEtHVXNkQ2w3YVdZb2RDNWtZVzVuWlhKdmRYTnNlVk5sZEVsdWJtVnlTRlJOVENF'
    || 'OWJuVnNiQ2wwYUhKdmR5QkZjbkp2Y2loaEtEa3hLU2s3Y21WMGRYSnVJRThvZTMwc2RDeDdkbUZzZFdVNmRtOXBaQ0F3TEdSbFptRjFiSFJXWVd4MVpUcDJi'
    || 'MmxrSURBc1kyaHBiR1J5Wlc0NklpSXJaUzVmZDNKaGNIQmxjbE4wWVhSbExtbHVhWFJwWVd4V1lXeDFaWDBwZldaMWJtTjBhVzl1SUhaektHVXNkQ2w3ZG1G'
    || 'eUlHNDlkQzUyWVd4MVpUdHBaaWh1UFQxdWRXeHNLWHRwWmlodVBYUXVZMmhwYkdSeVpXNHNkRDEwTG1SbFptRjFiSFJXWVd4MVpTeHVJVDF1ZFd4c0tYdHBa'
    || 'aWgwSVQxdWRXeHNLWFJvY205M0lFVnljbTl5S0dFb09USXBLVHRwWmloQ2JpaHVLU2w3YVdZb01UeHVMbXhsYm1kMGFDbDBhSEp2ZHlCRmNuSnZjaWhoS0Rr'
    || 'ektTazdiajF1V3pCZGZYUTlibjEwUFQxdWRXeHNKaVlvZEQwaUlpa3NiajEwZldVdVgzZHlZWEJ3WlhKVGRHRjBaVDE3YVc1cGRHbGhiRlpoYkhWbE9uUmxL'
    || 'RzRwZlgxbWRXNWpkR2x2YmlCbmN5aGxMSFFwZTNaaGNpQnVQWFJsS0hRdWRtRnNkV1VwTEhJOWRHVW9kQzVrWldaaGRXeDBWbUZzZFdVcE8yNGhQVzUxYkd3'
    || 'bUppaHVQU0lpSzI0c2JpRTlQV1V1ZG1Gc2RXVW1KaWhsTG5aaGJIVmxQVzRwTEhRdVpHVm1ZWFZzZEZaaGJIVmxQVDF1ZFd4c0ppWmxMbVJsWm1GMWJIUldZ'
    || 'V3gxWlNFOVBXNG1KaWhsTG1SbFptRjFiSFJXWVd4MVpUMXVLU2tzY2lFOWJuVnNiQ1ltS0dVdVpHVm1ZWFZzZEZaaGJIVmxQU0lpSzNJcGZXWjFibU4wYVc5'
    || 'dUlIbHpLR1VwZTNaaGNpQjBQV1V1ZEdWNGRFTnZiblJsYm5RN2REMDlQV1V1WDNkeVlYQndaWEpUZEdGMFpTNXBibWwwYVdGc1ZtRnNkV1VtSm5RaFBUMGlJ'
    || 'aVltZENFOVBXNTFiR3dtSmlobExuWmhiSFZsUFhRcGZXWjFibU4wYVc5dUlIaHpLR1VwZTNOM2FYUmphQ2hsS1h0allYTmxJbk4yWnlJNmNtVjBkWEp1SW1o'
    || 'MGRIQTZMeTkzZDNjdWR6TXViM0puTHpJd01EQXZjM1puSWp0allYTmxJbTFoZEdnaU9uSmxkSFZ5YmlKb2RIUndPaTh2ZDNkM0xuY3pMbTl5Wnk4eE9UazRM'
    || 'MDFoZEdndlRXRjBhRTFNSWp0a1pXWmhkV3gwT25KbGRIVnliaUpvZEhSd09pOHZkM2QzTG5jekxtOXlaeTh4T1RrNUwzaG9kRzFzSW4xOVpuVnVZM1JwYjI0'
    || 'Z2Nta29aU3gwS1h0eVpYUjFjbTRnWlQwOWJuVnNiSHg4WlQwOVBTSm9kSFJ3T2k4dmQzZDNMbmN6TG05eVp5OHhPVGs1TDNob2RHMXNJajk0Y3loMEtUcGxQ'
    || 'VDA5SW1oMGRIQTZMeTkzZDNjdWR6TXViM0puTHpJd01EQXZjM1puSWlZbWREMDlQU0ptYjNKbGFXZHVUMkpxWldOMElqOGlhSFIwY0RvdkwzZDNkeTUzTXk1'
    || 'dmNtY3ZNVGs1T1M5NGFIUnRiQ0k2WlgxMllYSWdUM0lzZDNNOUtHWjFibU4wYVc5dUtHVXBlM0psZEhWeWJpQjBlWEJsYjJZZ1RWTkJjSEE4SW5VaUppWk5V'
    || 'MEZ3Y0M1bGVHVmpWVzV6WVdabFRHOWpZV3hHZFc1amRHbHZiajltZFc1amRHbHZiaWgwTEc0c2NpeHNLWHROVTBGd2NDNWxlR1ZqVlc1ellXWmxURzlqWVd4'
    || 'R2RXNWpkR2x2YmlobWRXNWpkR2x2YmlncGUzSmxkSFZ5YmlCbEtIUXNiaXh5TEd3cGZTbDlPbVY5S1NobWRXNWpkR2x2YmlobExIUXBlMmxtS0dVdWJtRnRa'
    || 'WE53WVdObFZWSkpJVDA5SW1oMGRIQTZMeTkzZDNjdWR6TXViM0puTHpJd01EQXZjM1puSW54OEltbHVibVZ5U0ZSTlRDSnBiaUJsS1dVdWFXNXVaWEpJVkUx'
    || 'TVBYUTdaV3h6Wlh0bWIzSW9UM0k5VDNKOGZHUnZZM1Z0Wlc1MExtTnlaV0YwWlVWc1pXMWxiblFvSW1ScGRpSXBMRTl5TG1sdWJtVnlTRlJOVEQwaVBITjJa'
    || 'ejRpSzNRdWRtRnNkV1ZQWmlncExuUnZVM1J5YVc1bktDa3JJand2YzNablBpSXNkRDFQY2k1bWFYSnpkRU5vYVd4a08yVXVabWx5YzNSRGFHbHNaRHNwWlM1'
    || 'eVpXMXZkbVZEYUdsc1pDaGxMbVpwY25OMFEyaHBiR1FwTzJadmNpZzdkQzVtYVhKemRFTm9hV3hrT3lsbExtRndjR1Z1WkVOb2FXeGtLSFF1Wm1seWMzUkRh'
    || 'R2xzWkNsOWZTazdablZ1WTNScGIyNGdVVzRvWlN4MEtYdHBaaWgwS1h0MllYSWdiajFsTG1acGNuTjBRMmhwYkdRN2FXWW9iaVltYmowOVBXVXViR0Z6ZEVO'
    || 'b2FXeGtKaVp1TG01dlpHVlVlWEJsUFQwOU15bDdiaTV1YjJSbFZtRnNkV1U5ZER0eVpYUjFjbTU5ZldVdWRHVjRkRU52Ym5SbGJuUTlkSDEyWVhJZ1dXNDll'
    || 'MkZ1YVcxaGRHbHZia2wwWlhKaGRHbHZia052ZFc1ME9pRXdMR0Z6Y0dWamRGSmhkR2x2T2lFd0xHSnZjbVJsY2tsdFlXZGxUM1YwYzJWME9pRXdMR0p2Y21S'
    || 'bGNrbHRZV2RsVTJ4cFkyVTZJVEFzWW05eVpHVnlTVzFoWjJWWGFXUjBhRG9oTUN4aWIzaEdiR1Y0T2lFd0xHSnZlRVpzWlhoSGNtOTFjRG9oTUN4aWIzaFBj'
    || 'bVJwYm1Gc1IzSnZkWEE2SVRBc1kyOXNkVzF1UTI5MWJuUTZJVEFzWTI5c2RXMXVjem9oTUN4bWJHVjRPaUV3TEdac1pYaEhjbTkzT2lFd0xHWnNaWGhRYjNO'
    || 'cGRHbDJaVG9oTUN4bWJHVjRVMmh5YVc1ck9pRXdMR1pzWlhoT1pXZGhkR2wyWlRvaE1DeG1iR1Y0VDNKa1pYSTZJVEFzWjNKcFpFRnlaV0U2SVRBc1ozSnBa'
    || 'Rkp2ZHpvaE1DeG5jbWxrVW05M1JXNWtPaUV3TEdkeWFXUlNiM2RUY0dGdU9pRXdMR2R5YVdSU2IzZFRkR0Z5ZERvaE1DeG5jbWxrUTI5c2RXMXVPaUV3TEdk'
    || 'eWFXUkRiMngxYlc1RmJtUTZJVEFzWjNKcFpFTnZiSFZ0YmxOd1lXNDZJVEFzWjNKcFpFTnZiSFZ0YmxOMFlYSjBPaUV3TEdadmJuUlhaV2xuYUhRNklUQXNi'
    || 'R2x1WlVOc1lXMXdPaUV3TEd4cGJtVklaV2xuYUhRNklUQXNiM0JoWTJsMGVUb2hNQ3h2Y21SbGNqb2hNQ3h2Y25Cb1lXNXpPaUV3TEhSaFlsTnBlbVU2SVRB'
    || 'c2QybGtiM2R6T2lFd0xIcEpibVJsZURvaE1DeDZiMjl0T2lFd0xHWnBiR3hQY0dGamFYUjVPaUV3TEdac2IyOWtUM0JoWTJsMGVUb2hNQ3h6ZEc5d1QzQmhZ'
    || 'MmwwZVRvaE1DeHpkSEp2YTJWRVlYTm9ZWEp5WVhrNklUQXNjM1J5YjJ0bFJHRnphRzltWm5ObGREb2hNQ3h6ZEhKdmEyVk5hWFJsY214cGJXbDBPaUV3TEhO'
    || 'MGNtOXJaVTl3WVdOcGRIazZJVEFzYzNSeWIydGxWMmxrZEdnNklUQjlMR05rUFZzaVYyVmlhMmwwSWl3aWJYTWlMQ0pOYjNvaUxDSlBJbDA3VDJKcVpXTjBM'
    || 'bXRsZVhNb1dXNHBMbVp2Y2tWaFkyZ29ablZ1WTNScGIyNG9aU2w3WTJRdVptOXlSV0ZqYUNobWRXNWpkR2x2YmloMEtYdDBQWFFyWlM1amFHRnlRWFFvTUNr'
    || 'dWRHOVZjSEJsY2tOaGMyVW9LU3RsTG5OMVluTjBjbWx1WnlneEtTeFpibHQwWFQxWmJsdGxYWDBwZlNrN1puVnVZM1JwYjI0Z1UzTW9aU3gwTEc0cGUzSmxk'
    || 'SFZ5YmlCMFBUMXVkV3hzZkh4MGVYQmxiMllnZEQwOUltSnZiMnhsWVc0aWZIeDBQVDA5SWlJL0lpSTZibng4ZEhsd1pXOW1JSFFoUFNKdWRXMWlaWElpZkh4'
    || 'MFBUMDlNSHg4V1c0dWFHRnpUM2R1VUhKdmNHVnlkSGtvWlNrbUpsbHVXMlZkUHlnaUlpdDBLUzUwY21sdEtDazZkQ3NpY0hnaWZXWjFibU4wYVc5dUlGOXpL'
    || 'R1VzZENsN1pUMWxMbk4wZVd4bE8yWnZjaWgyWVhJZ2JpQnBiaUIwS1dsbUtIUXVhR0Z6VDNkdVVISnZjR1Z5ZEhrb2Jpa3BlM1poY2lCeVBXNHVhVzVrWlho'
    || 'UFppZ2lMUzBpS1QwOVBUQXNiRDFUY3lodUxIUmJibDBzY2lrN2JqMDlQU0ptYkc5aGRDSW1KaWh1UFNKamMzTkdiRzloZENJcExISS9aUzV6WlhSUWNtOXda'
    || 'WEowZVNodUxHd3BPbVZiYmwwOWJIMTlkbUZ5SUdSa1BVOG9lMjFsYm5WcGRHVnRPaUV3ZlN4N1lYSmxZVG9oTUN4aVlYTmxPaUV3TEdKeU9pRXdMR052YkRv'
    || 'aE1DeGxiV0psWkRvaE1DeG9jam9oTUN4cGJXYzZJVEFzYVc1d2RYUTZJVEFzYTJWNVoyVnVPaUV3TEd4cGJtczZJVEFzYldWMFlUb2hNQ3h3WVhKaGJUb2hN'
    || 'Q3h6YjNWeVkyVTZJVEFzZEhKaFkyczZJVEFzZDJKeU9pRXdmU2s3Wm5WdVkzUnBiMjRnYkdrb1pTeDBLWHRwWmloMEtYdHBaaWhrWkZ0bFhTWW1LSFF1WTJo'
    || 'cGJHUnlaVzRoUFc1MWJHeDhmSFF1WkdGdVoyVnliM1Z6YkhsVFpYUkpibTVsY2toVVRVd2hQVzUxYkd3cEtYUm9jbTkzSUVWeWNtOXlLR0VvTVRNM0xHVXBL'
    || 'VHRwWmloMExtUmhibWRsY205MWMyeDVVMlYwU1c1dVpYSklWRTFNSVQxdWRXeHNLWHRwWmloMExtTm9hV3hrY21WdUlUMXVkV3hzS1hSb2NtOTNJRVZ5Y205'
    || 'eUtHRW9OakFwS1R0cFppaDBlWEJsYjJZZ2RDNWtZVzVuWlhKdmRYTnNlVk5sZEVsdWJtVnlTRlJOVENFOUltOWlhbVZqZENKOGZDRW9JbDlmYUhSdGJDSnBi'
    || 'aUIwTG1SaGJtZGxjbTkxYzJ4NVUyVjBTVzV1WlhKSVZFMU1LU2wwYUhKdmR5QkZjbkp2Y2loaEtEWXhLU2w5YVdZb2RDNXpkSGxzWlNFOWJuVnNiQ1ltZEhs'
    || 'd1pXOW1JSFF1YzNSNWJHVWhQU0p2WW1wbFkzUWlLWFJvY205M0lFVnljbTl5S0dFb05qSXBLWDE5Wm5WdVkzUnBiMjRnYVdrb1pTeDBLWHRwWmlobExtbHVa'
    || 'R1Y0VDJZb0lpMGlLVDA5UFMweEtYSmxkSFZ5YmlCMGVYQmxiMllnZEM1cGN6MDlJbk4wY21sdVp5STdjM2RwZEdOb0tHVXBlMk5oYzJVaVlXNXViM1JoZEds'
    || 'dmJpMTRiV3dpT21OaGMyVWlZMjlzYjNJdGNISnZabWxzWlNJNlkyRnpaU0ptYjI1MExXWmhZMlVpT21OaGMyVWlabTl1ZEMxbVlXTmxMWE55WXlJNlkyRnpa'
    || 'U0ptYjI1MExXWmhZMlV0ZFhKcElqcGpZWE5sSW1admJuUXRabUZqWlMxbWIzSnRZWFFpT21OaGMyVWlabTl1ZEMxbVlXTmxMVzVoYldVaU9tTmhjMlVpYlds'
    || 'emMybHVaeTFuYkhsd2FDSTZjbVYwZFhKdUlURTdaR1ZtWVhWc2REcHlaWFIxY200aE1IMTlkbUZ5SUc5cFBXNTFiR3c3Wm5WdVkzUnBiMjRnYzJrb1pTbDdj'
    || 'bVYwZFhKdUlHVTlaUzUwWVhKblpYUjhmR1V1YzNKalJXeGxiV1Z1ZEh4OGQybHVaRzkzTEdVdVkyOXljbVZ6Y0c5dVpHbHVaMVZ6WlVWc1pXMWxiblFtSmlo'
    || 'bFBXVXVZMjl5Y21WemNHOXVaR2x1WjFWelpVVnNaVzFsYm5RcExHVXVibTlrWlZSNWNHVTlQVDB6UDJVdWNHRnlaVzUwVG05a1pUcGxmWFpoY2lCMWFUMXVk'
    || 'V3hzTEhodVBXNTFiR3dzZDI0OWJuVnNiRHRtZFc1amRHbHZiaUJyY3lobEtYdHBaaWhsUFdoeUtHVXBLWHRwWmloMGVYQmxiMllnZFdraFBTSm1kVzVqZEds'
    || 'dmJpSXBkR2h5YjNjZ1JYSnliM0lvWVNneU9EQXBLVHQyWVhJZ2REMWxMbk4wWVhSbFRtOWtaVHQwSmlZb2REMXViQ2gwS1N4MWFTaGxMbk4wWVhSbFRtOWta'
    || 'U3hsTG5SNWNHVXNkQ2twZlgxbWRXNWpkR2x2YmlCRmN5aGxLWHQ0Ymo5M2JqOTNiaTV3ZFhOb0tHVXBPbmR1UFZ0bFhUcDRiajFsZldaMWJtTjBhVzl1SUU1'
    || 'ektDbDdhV1lvZUc0cGUzWmhjaUJsUFhodUxIUTlkMjQ3YVdZb2QyNDllRzQ5Ym5Wc2JDeHJjeWhsS1N4MEtXWnZjaWhsUFRBN1pUeDBMbXhsYm1kMGFEdGxL'
    || 'eXNwYTNNb2RGdGxYU2w5ZldaMWJtTjBhVzl1SUdwektHVXNkQ2w3Y21WMGRYSnVJR1VvZENsOVpuVnVZM1JwYjI0Z1ZITW9LWHQ5ZG1GeUlHRnBQU0V4TzJa'
    || 'MWJtTjBhVzl1SUVOektHVXNkQ3h1S1h0cFppaGhhU2x5WlhSMWNtNGdaU2gwTEc0cE8yRnBQU0V3TzNSeWVYdHlaWFIxY200Z2FuTW9aU3gwTEc0cGZXWnBi'
    || 'bUZzYkhsN1lXazlJVEVzS0hodUlUMDliblZzYkh4OGQyNGhQVDF1ZFd4c0tTWW1LRlJ6S0Nrc1RuTW9LU2w5ZldaMWJtTjBhVzl1SUV0dUtHVXNkQ2w3ZG1G'
    || 'eUlHNDlaUzV6ZEdGMFpVNXZaR1U3YVdZb2JqMDlQVzUxYkd3cGNtVjBkWEp1SUc1MWJHdzdkbUZ5SUhJOWJtd29iaWs3YVdZb2NqMDlQVzUxYkd3cGNtVjBk'
    || 'WEp1SUc1MWJHdzdiajF5VzNSZE8yVTZjM2RwZEdOb0tIUXBlMk5oYzJVaWIyNURiR2xqYXlJNlkyRnpaU0p2YmtOc2FXTnJRMkZ3ZEhWeVpTSTZZMkZ6WlNK'
    || 'dmJrUnZkV0pzWlVOc2FXTnJJanBqWVhObEltOXVSRzkxWW14bFEyeHBZMnREWVhCMGRYSmxJanBqWVhObEltOXVUVzkxYzJWRWIzZHVJanBqWVhObEltOXVU'
    || 'VzkxYzJWRWIzZHVRMkZ3ZEhWeVpTSTZZMkZ6WlNKdmJrMXZkWE5sVFc5MlpTSTZZMkZ6WlNKdmJrMXZkWE5sVFc5MlpVTmhjSFIxY21VaU9tTmhjMlVpYjI1'
    || 'TmIzVnpaVlZ3SWpwallYTmxJbTl1VFc5MWMyVlZjRU5oY0hSMWNtVWlPbU5oYzJVaWIyNU5iM1Z6WlVWdWRHVnlJam9vY2owaGNpNWthWE5oWW14bFpDbDhm'
    || 'Q2hsUFdVdWRIbHdaU3h5UFNFb1pUMDlQU0ppZFhSMGIyNGlmSHhsUFQwOUltbHVjSFYwSW54OFpUMDlQU0p6Wld4bFkzUWlmSHhsUFQwOUluUmxlSFJoY21W'
    || 'aElpa3BMR1U5SVhJN1luSmxZV3NnWlR0a1pXWmhkV3gwT21VOUlURjlhV1lvWlNseVpYUjFjbTRnYm5Wc2JEdHBaaWh1SmlaMGVYQmxiMllnYmlFOUltWjFi'
    || 'bU4wYVc5dUlpbDBhSEp2ZHlCRmNuSnZjaWhoS0RJek1TeDBMSFI1Y0dWdlppQnVLU2s3Y21WMGRYSnVJRzU5ZG1GeUlHTnBQU0V4TzJsbUtGOHBkSEo1ZTNa'
    || 'aGNpQkhiajE3ZlR0UFltcGxZM1F1WkdWbWFXNWxVSEp2Y0dWeWRIa29SMjRzSW5CaGMzTnBkbVVpTEh0blpYUTZablZ1WTNScGIyNG9LWHRqYVQwaE1IMTlL'
    || 'U3gzYVc1a2IzY3VZV1JrUlhabGJuUk1hWE4wWlc1bGNpZ2lkR1Z6ZENJc1IyNHNSMjRwTEhkcGJtUnZkeTV5WlcxdmRtVkZkbVZ1ZEV4cGMzUmxibVZ5S0NK'
    || 'MFpYTjBJaXhIYml4SGJpbDlZMkYwWTJoN1kyazlJVEY5Wm5WdVkzUnBiMjRnWm1Rb1pTeDBMRzRzY2l4c0xHa3NieXhqTEdRcGUzWmhjaUJuUFVGeWNtRjVM'
    || 'bkJ5YjNSdmRIbHdaUzV6YkdsalpTNWpZV3hzS0dGeVozVnRaVzUwY3l3ektUdDBjbmw3ZEM1aGNIQnNlU2h1TEdjcGZXTmhkR05vS0VVcGUzUm9hWE11YjI1'
    || 'RmNuSnZjaWhGS1gxOWRtRnlJRmh1UFNFeExFbHlQVzUxYkd3c2VuSTlJVEVzWkdrOWJuVnNiQ3h3WkQxN2IyNUZjbkp2Y2pwbWRXNWpkR2x2YmlobEtYdFli'
    || 'ajBoTUN4SmNqMWxmWDA3Wm5WdVkzUnBiMjRnYUdRb1pTeDBMRzRzY2l4c0xHa3NieXhqTEdRcGUxaHVQU0V4TEVseVBXNTFiR3dzWm1RdVlYQndiSGtvY0dR'
    || 'c1lYSm5kVzFsYm5SektYMW1kVzVqZEdsdmJpQnRaQ2hsTEhRc2JpeHlMR3dzYVN4dkxHTXNaQ2w3YVdZb2FHUXVZWEJ3Ykhrb2RHaHBjeXhoY21kMWJXVnVk'
    || 'SE1wTEZodUtYdHBaaWhZYmlsN2RtRnlJR2M5U1hJN1dHNDlJVEVzU1hJOWJuVnNiSDFsYkhObElIUm9jbTkzSUVWeWNtOXlLR0VvTVRrNEtTazdlbko4ZkNo'
    || 'NmNqMGhNQ3hrYVQxbktYMTlablZ1WTNScGIyNGdibTRvWlNsN2RtRnlJSFE5WlN4dVBXVTdhV1lvWlM1aGJIUmxjbTVoZEdVcFptOXlLRHQwTG5KbGRIVnli'
    || 'anNwZEQxMExuSmxkSFZ5Ymp0bGJITmxlMlU5ZER0a2J5QjBQV1VzS0hRdVpteGhaM01tTkRBNU9Da2hQVDB3SmlZb2JqMTBMbkpsZEhWeWJpa3NaVDEwTG5K'
    || 'bGRIVnlianQzYUdsc1pTaGxLWDF5WlhSMWNtNGdkQzUwWVdjOVBUMHpQMjQ2Ym5Wc2JIMW1kVzVqZEdsdmJpQk1jeWhsS1h0cFppaGxMblJoWnowOVBURXpL'
    || 'WHQyWVhJZ2REMWxMbTFsYlc5cGVtVmtVM1JoZEdVN2FXWW9kRDA5UFc1MWJHd21KaWhsUFdVdVlXeDBaWEp1WVhSbExHVWhQVDF1ZFd4c0ppWW9kRDFsTG0x'
    || 'bGJXOXBlbVZrVTNSaGRHVXBLU3gwSVQwOWJuVnNiQ2x5WlhSMWNtNGdkQzVrWldoNVpISmhkR1ZrZlhKbGRIVnliaUJ1ZFd4c2ZXWjFibU4wYVc5dUlGSnpL'
    || 'R1VwZTJsbUtHNXVLR1VwSVQwOVpTbDBhSEp2ZHlCRmNuSnZjaWhoS0RFNE9Da3BmV1oxYm1OMGFXOXVJSFprS0dVcGUzWmhjaUIwUFdVdVlXeDBaWEp1WVhS'
    || 'bE8ybG1LQ0YwS1h0cFppaDBQVzV1S0dVcExIUTlQVDF1ZFd4c0tYUm9jbTkzSUVWeWNtOXlLR0VvTVRnNEtTazdjbVYwZFhKdUlIUWhQVDFsUDI1MWJHdzZa'
    || 'WDFtYjNJb2RtRnlJRzQ5WlN4eVBYUTdPeWw3ZG1GeUlHdzliaTV5WlhSMWNtNDdhV1lvYkQwOVBXNTFiR3dwWW5KbFlXczdkbUZ5SUdrOWJDNWhiSFJsY201'
    || 'aGRHVTdhV1lvYVQwOVBXNTFiR3dwZTJsbUtISTliQzV5WlhSMWNtNHNjaUU5UFc1MWJHd3BlMjQ5Y2p0amIyNTBhVzUxWlgxaWNtVmhhMzFwWmloc0xtTm9h'
    || 'V3hrUFQwOWFTNWphR2xzWkNsN1ptOXlLR2s5YkM1amFHbHNaRHRwT3lsN2FXWW9hVDA5UFc0cGNtVjBkWEp1SUZKektHd3BMR1U3YVdZb2FUMDlQWElwY21W'
    || 'MGRYSnVJRkp6S0d3cExIUTdhVDFwTG5OcFlteHBibWQ5ZEdoeWIzY2dSWEp5YjNJb1lTZ3hPRGdwS1gxcFppaHVMbkpsZEhWeWJpRTlQWEl1Y21WMGRYSnVL'
    || 'VzQ5YkN4eVBXazdaV3h6Wlh0bWIzSW9kbUZ5SUc4OUlURXNZejFzTG1Ob2FXeGtPMk03S1h0cFppaGpQVDA5YmlsN2J6MGhNQ3h1UFd3c2NqMXBPMkp5WldG'
    || 'cmZXbG1LR005UFQxeUtYdHZQU0V3TEhJOWJDeHVQV2s3WW5KbFlXdDlZejFqTG5OcFlteHBibWQ5YVdZb0lXOHBlMlp2Y2loalBXa3VZMmhwYkdRN1l6c3Bl'
    || 'MmxtS0dNOVBUMXVLWHR2UFNFd0xHNDlhU3h5UFd3N1luSmxZV3Q5YVdZb1l6MDlQWElwZTI4OUlUQXNjajFwTEc0OWJEdGljbVZoYTMxalBXTXVjMmxpYkds'
    || 'dVozMXBaaWdoYnlsMGFISnZkeUJGY25KdmNpaGhLREU0T1NrcGZYMXBaaWh1TG1Gc2RHVnlibUYwWlNFOVBYSXBkR2h5YjNjZ1JYSnliM0lvWVNneE9UQXBL'
    || 'WDFwWmlodUxuUmhaeUU5UFRNcGRHaHliM2NnUlhKeWIzSW9ZU2d4T0RncEtUdHlaWFIxY200Z2JpNXpkR0YwWlU1dlpHVXVZM1Z5Y21WdWREMDlQVzQvWlRw'
    || 'MGZXWjFibU4wYVc5dUlFMXpLR1VwZTNKbGRIVnliaUJsUFhaa0tHVXBMR1VoUFQxdWRXeHNQMUJ6S0dVcE9tNTFiR3g5Wm5WdVkzUnBiMjRnVUhNb1pTbDdh'
    || 'V1lvWlM1MFlXYzlQVDAxZkh4bExuUmhaejA5UFRZcGNtVjBkWEp1SUdVN1ptOXlLR1U5WlM1amFHbHNaRHRsSVQwOWJuVnNiRHNwZTNaaGNpQjBQVkJ6S0dV'
    || 'cE8ybG1LSFFoUFQxdWRXeHNLWEpsZEhWeWJpQjBPMlU5WlM1emFXSnNhVzVuZlhKbGRIVnliaUJ1ZFd4c2ZYWmhjaUJQY3oxbUxuVnVjM1JoWW14bFgzTmph'
    || 'R1ZrZFd4bFEyRnNiR0poWTJzc1NYTTlaaTUxYm5OMFlXSnNaVjlqWVc1alpXeERZV3hzWW1GamF5eG5aRDFtTG5WdWMzUmhZbXhsWDNOb2IzVnNaRmxwWld4'
    || 'a0xIbGtQV1l1ZFc1emRHRmliR1ZmY21WeGRXVnpkRkJoYVc1MExIWmxQV1l1ZFc1emRHRmliR1ZmYm05M0xIaGtQV1l1ZFc1emRHRmliR1ZmWjJWMFEzVnlj'
    || 'bVZ1ZEZCeWFXOXlhWFI1VEdWMlpXd3NabWs5Wmk1MWJuTjBZV0pzWlY5SmJXMWxaR2xoZEdWUWNtbHZjbWwwZVN4NmN6MW1MblZ1YzNSaFlteGxYMVZ6WlhK'
    || 'Q2JHOWphMmx1WjFCeWFXOXlhWFI1TEVSeVBXWXVkVzV6ZEdGaWJHVmZUbTl5YldGc1VISnBiM0pwZEhrc2QyUTlaaTUxYm5OMFlXSnNaVjlNYjNkUWNtbHZj'
    || 'bWwwZVN4RWN6MW1MblZ1YzNSaFlteGxYMGxrYkdWUWNtbHZjbWwwZVN4QmNqMXVkV3hzTEhkMFBXNTFiR3c3Wm5WdVkzUnBiMjRnVTJRb1pTbDdhV1lvZDNR'
    || 'bUpuUjVjR1Z2WmlCM2RDNXZia052YlcxcGRFWnBZbVZ5VW05dmREMDlJbVoxYm1OMGFXOXVJaWwwY25sN2QzUXViMjVEYjIxdGFYUkdhV0psY2xKdmIzUW9R'
    || 'WElzWlN4MmIybGtJREFzS0dVdVkzVnljbVZ1ZEM1bWJHRm5jeVl4TWpncFBUMDlNVEk0S1gxallYUmphSHQ5ZlhaaGNpQmpkRDFOWVhSb0xtTnNlak15UDAx'
    || 'aGRHZ3VZMng2TXpJNlJXUXNYMlE5VFdGMGFDNXNiMmNzYTJROVRXRjBhQzVNVGpJN1puVnVZM1JwYjI0Z1JXUW9aU2w3Y21WMGRYSnVJR1UrUGo0OU1DeGxQ'
    || 'VDA5TUQ4ek1qb3pNUzBvWDJRb1pTa3ZhMlI4TUNsOE1IMTJZWElnUm5JOU5qUXNWWEk5TkRFNU5ETXdORHRtZFc1amRHbHZiaUJhYmlobEtYdHpkMmwwWTJn'
    || 'b1pTWXRaU2w3WTJGelpTQXhPbkpsZEhWeWJpQXhPMk5oYzJVZ01qcHlaWFIxY200Z01qdGpZWE5sSURRNmNtVjBkWEp1SURRN1kyRnpaU0E0T25KbGRIVnli'
    || 'aUE0TzJOaGMyVWdNVFk2Y21WMGRYSnVJREUyTzJOaGMyVWdNekk2Y21WMGRYSnVJRE15TzJOaGMyVWdOalE2WTJGelpTQXhNamc2WTJGelpTQXlOVFk2WTJG'
    || 'elpTQTFNVEk2WTJGelpTQXhNREkwT21OaGMyVWdNakEwT0RwallYTmxJRFF3T1RZNlkyRnpaU0E0TVRreU9tTmhjMlVnTVRZek9EUTZZMkZ6WlNBek1qYzJP'
    || 'RHBqWVhObElEWTFOVE0yT21OaGMyVWdNVE14TURjeU9tTmhjMlVnTWpZeU1UUTBPbU5oYzJVZ05USTBNamc0T21OaGMyVWdNVEEwT0RVM05qcGpZWE5sSURJ'
    || 'd09UY3hOVEk2Y21WMGRYSnVJR1VtTkRFNU5ESTBNRHRqWVhObElEUXhPVFF6TURRNlkyRnpaU0E0TXpnNE5qQTRPbU5oYzJVZ01UWTNOemN5TVRZNlkyRnpa'
    || 'U0F6TXpVMU5EUXpNanBqWVhObElEWTNNVEE0T0RZME9uSmxkSFZ5YmlCbEpqRXpNREF5TXpReU5EdGpZWE5sSURFek5ESXhOemN5T0RweVpYUjFjbTRnTVRN'
    || 'ME1qRTNOekk0TzJOaGMyVWdNalk0TkRNMU5EVTJPbkpsZEhWeWJpQXlOamcwTXpVME5UWTdZMkZ6WlNBMU16WTROekE1TVRJNmNtVjBkWEp1SURVek5qZzNN'
    || 'RGt4TWp0allYTmxJREV3TnpNM05ERTRNalE2Y21WMGRYSnVJREV3TnpNM05ERTRNalE3WkdWbVlYVnNkRHB5WlhSMWNtNGdaWDE5Wm5WdVkzUnBiMjRnU0hJ'
    || 'b1pTeDBLWHQyWVhJZ2JqMWxMbkJsYm1ScGJtZE1ZVzVsY3p0cFppaHVQVDA5TUNseVpYUjFjbTRnTUR0MllYSWdjajB3TEd3OVpTNXpkWE53Wlc1a1pXUk1Z'
    || 'VzVsY3l4cFBXVXVjR2x1WjJWa1RHRnVaWE1zYnoxdUpqSTJPRFF6TlRRMU5UdHBaaWh2SVQwOU1DbDdkbUZ5SUdNOWJ5WitiRHRqSVQwOU1EOXlQVnB1S0dN'
    || 'cE9paHBKajF2TEdraFBUMHdKaVlvY2oxYWJpaHBLU2twZldWc2MyVWdiejF1Sm41c0xHOGhQVDB3UDNJOVdtNG9ieWs2YVNFOVBUQW1KaWh5UFZwdUtHa3BL'
    || 'VHRwWmloeVBUMDlNQ2x5WlhSMWNtNGdNRHRwWmloMElUMDlNQ1ltZENFOVBYSW1KaWgwSm13cFBUMDlNQ1ltS0d3OWNpWXRjaXhwUFhRbUxYUXNiRDQ5YVh4'
    || 'OGJEMDlQVEUySmlZb2FTWTBNVGswTWpRd0tTRTlQVEFwS1hKbGRIVnliaUIwTzJsbUtDaHlKalFwSVQwOU1DWW1LSEo4UFc0bU1UWXBMSFE5WlM1bGJuUmhi'
    || 'bWRzWldSTVlXNWxjeXgwSVQwOU1DbG1iM0lvWlQxbExtVnVkR0Z1WjJ4bGJXVnVkSE1zZENZOWNqc3dQSFE3S1c0OU16RXRZM1FvZENrc2JEMHhQRHh1TEhK'
    || 'OFBXVmJibDBzZENZOWZtdzdjbVYwZFhKdUlISjlablZ1WTNScGIyNGdUbVFvWlN4MEtYdHpkMmwwWTJnb1pTbDdZMkZ6WlNBeE9tTmhjMlVnTWpwallYTmxJ'
    || 'RFE2Y21WMGRYSnVJSFFyTWpVd08yTmhjMlVnT0RwallYTmxJREUyT21OaGMyVWdNekk2WTJGelpTQTJORHBqWVhObElERXlPRHBqWVhObElESTFOanBqWVhO'
    || 'bElEVXhNanBqWVhObElERXdNalE2WTJGelpTQXlNRFE0T21OaGMyVWdOREE1TmpwallYTmxJRGd4T1RJNlkyRnpaU0F4TmpNNE5EcGpZWE5sSURNeU56WTRP'
    || 'bU5oYzJVZ05qVTFNelk2WTJGelpTQXhNekV3TnpJNlkyRnpaU0F5TmpJeE5EUTZZMkZ6WlNBMU1qUXlPRGc2WTJGelpTQXhNRFE0TlRjMk9tTmhjMlVnTWpB'
    || 'NU56RTFNanB5WlhSMWNtNGdkQ3MxWlRNN1kyRnpaU0EwTVRrME16QTBPbU5oYzJVZ09ETTRPRFl3T0RwallYTmxJREUyTnpjM01qRTJPbU5oYzJVZ016TTFO'
    || 'VFEwTXpJNlkyRnpaU0EyTnpFd09EZzJORHB5WlhSMWNtNHRNVHRqWVhObElERXpOREl4TnpjeU9EcGpZWE5sSURJMk9EUXpOVFExTmpwallYTmxJRFV6Tmpn'
    || 'M01Ea3hNanBqWVhObElERXdOek0zTkRFNE1qUTZjbVYwZFhKdUxURTdaR1ZtWVhWc2REcHlaWFIxY200dE1YMTlablZ1WTNScGIyNGdhbVFvWlN4MEtYdG1i'
    || 'M0lvZG1GeUlHNDlaUzV6ZFhOd1pXNWtaV1JNWVc1bGN5eHlQV1V1Y0dsdVoyVmtUR0Z1WlhNc2JEMWxMbVY0Y0dseVlYUnBiMjVVYVcxbGN5eHBQV1V1Y0dW'
    || 'dVpHbHVaMHhoYm1Wek96QThhVHNwZTNaaGNpQnZQVE14TFdOMEtHa3BMR005TVR3OGJ5eGtQV3hiYjEwN1pEMDlQUzB4UHlnb1l5WnVLVDA5UFRCOGZDaGpK'
    || 'bklwSVQwOU1Da21KaWhzVzI5ZFBVNWtLR01zZENrcE9tUThQWFFtSmlobExtVjRjR2x5WldSTVlXNWxjM3c5WXlrc2FTWTlmbU45ZldaMWJtTjBhVzl1SUhC'
    || 'cEtHVXBlM0psZEhWeWJpQmxQV1V1Y0dWdVpHbHVaMHhoYm1WekppMHhNRGN6TnpReE9ESTFMR1VoUFQwd1AyVTZaU1l4TURjek56UXhPREkwUHpFd056TTNO'
    || 'REU0TWpRNk1IMW1kVzVqZEdsdmJpQkJjeWdwZTNaaGNpQmxQVVp5TzNKbGRIVnliaUJHY2p3OFBURXNLRVp5SmpReE9UUXlOREFwUFQwOU1DWW1LRVp5UFRZ'
    || 'MEtTeGxmV1oxYm1OMGFXOXVJR2hwS0dVcGUyWnZjaWgyWVhJZ2REMWJYU3h1UFRBN016RStianR1S3lzcGRDNXdkWE5vS0dVcE8zSmxkSFZ5YmlCMGZXWjFi'
    || 'bU4wYVc5dUlFcHVLR1VzZEN4dUtYdGxMbkJsYm1ScGJtZE1ZVzVsYzN3OWRDeDBJVDA5TlRNMk9EY3dPVEV5SmlZb1pTNXpkWE53Wlc1a1pXUk1ZVzVsY3ow'
    || 'd0xHVXVjR2x1WjJWa1RHRnVaWE05TUNrc1pUMWxMbVYyWlc1MFZHbHRaWE1zZEQwek1TMWpkQ2gwS1N4bFczUmRQVzU5Wm5WdVkzUnBiMjRnVkdRb1pTeDBL'
    || 'WHQyWVhJZ2JqMWxMbkJsYm1ScGJtZE1ZVzVsY3laK2REdGxMbkJsYm1ScGJtZE1ZVzVsY3oxMExHVXVjM1Z6Y0dWdVpHVmtUR0Z1WlhNOU1DeGxMbkJwYm1k'
    || 'bFpFeGhibVZ6UFRBc1pTNWxlSEJwY21Wa1RHRnVaWE1tUFhRc1pTNXRkWFJoWW14bFVtVmhaRXhoYm1WekpqMTBMR1V1Wlc1MFlXNW5iR1ZrVEdGdVpYTW1Q'
    || 'WFFzZEQxbExtVnVkR0Z1WjJ4bGJXVnVkSE03ZG1GeUlISTlaUzVsZG1WdWRGUnBiV1Z6TzJadmNpaGxQV1V1Wlhod2FYSmhkR2x2YmxScGJXVnpPekE4Ympz'
    || 'cGUzWmhjaUJzUFRNeExXTjBLRzRwTEdrOU1UdzhiRHQwVzJ4ZFBUQXNjbHRzWFQwdE1TeGxXMnhkUFMweExHNG1QWDVwZlgxbWRXNWpkR2x2YmlCdGFTaGxM'
    || 'SFFwZTNaaGNpQnVQV1V1Wlc1MFlXNW5iR1ZrVEdGdVpYTjhQWFE3Wm05eUtHVTlaUzVsYm5SaGJtZHNaVzFsYm5Sek8yNDdLWHQyWVhJZ2NqMHpNUzFqZENo'
    || 'dUtTeHNQVEU4UEhJN2JDWjBmR1ZiY2wwbWRDWW1LR1ZiY2wxOFBYUXBMRzRtUFg1c2ZYMTJZWElnYm1VOU1EdG1kVzVqZEdsdmJpQkdjeWhsS1h0eVpYUjFj'
    || 'bTRnWlNZOUxXVXNNVHhsUHpROFpUOG9aU1l5TmpnME16VTBOVFVwSVQwOU1EOHhOam8xTXpZNE56QTVNVEk2TkRveGZYWmhjaUJWY3l4MmFTeEljeXdrY3l4'
    || 'WGN5eG5hVDBoTVN3a2NqMWJYU3hFZEQxdWRXeHNMRUYwUFc1MWJHd3NSblE5Ym5Wc2JDeHhiajF1WlhjZ1RXRndMR0p1UFc1bGR5Qk5ZWEFzVlhROVcxMHNR'
    || 'MlE5SW0xdmRYTmxaRzkzYmlCdGIzVnpaWFZ3SUhSdmRXTm9ZMkZ1WTJWc0lIUnZkV05vWlc1a0lIUnZkV05vYzNSaGNuUWdZWFY0WTJ4cFkyc2daR0pzWTJ4'
    || 'cFkyc2djRzlwYm5SbGNtTmhibU5sYkNCd2IybHVkR1Z5Wkc5M2JpQndiMmx1ZEdWeWRYQWdaSEpoWjJWdVpDQmtjbUZuYzNSaGNuUWdaSEp2Y0NCamIyMXdi'
    || 'M05wZEdsdmJtVnVaQ0JqYjIxd2IzTnBkR2x2Ym5OMFlYSjBJR3RsZVdSdmQyNGdhMlY1Y0hKbGMzTWdhMlY1ZFhBZ2FXNXdkWFFnZEdWNGRFbHVjSFYwSUdO'
    || 'dmNIa2dZM1YwSUhCaGMzUmxJR05zYVdOcklHTm9ZVzVuWlNCamIyNTBaWGgwYldWdWRTQnlaWE5sZENCemRXSnRhWFFpTG5Od2JHbDBLQ0lnSWlrN1puVnVZ'
    || 'M1JwYjI0Z1ZuTW9aU3gwS1h0emQybDBZMmdvWlNsN1kyRnpaU0ptYjJOMWMybHVJanBqWVhObEltWnZZM1Z6YjNWMElqcEVkRDF1ZFd4c08ySnlaV0ZyTzJO'
    || 'aGMyVWlaSEpoWjJWdWRHVnlJanBqWVhObEltUnlZV2RzWldGMlpTSTZRWFE5Ym5Wc2JEdGljbVZoYXp0allYTmxJbTF2ZFhObGIzWmxjaUk2WTJGelpTSnRi'
    || 'M1Z6Wlc5MWRDSTZSblE5Ym5Wc2JEdGljbVZoYXp0allYTmxJbkJ2YVc1MFpYSnZkbVZ5SWpwallYTmxJbkJ2YVc1MFpYSnZkWFFpT25GdUxtUmxiR1YwWlNo'
    || 'MExuQnZhVzUwWlhKSlpDazdZbkpsWVdzN1kyRnpaU0puYjNSd2IybHVkR1Z5WTJGd2RIVnlaU0k2WTJGelpTSnNiM04wY0c5cGJuUmxjbU5oY0hSMWNtVWlP'
    || 'bUp1TG1SbGJHVjBaU2gwTG5CdmFXNTBaWEpKWkNsOWZXWjFibU4wYVc5dUlHVnlLR1VzZEN4dUxISXNiQ3hwS1h0eVpYUjFjbTRnWlQwOVBXNTFiR3g4ZkdV'
    || 'dWJtRjBhWFpsUlhabGJuUWhQVDFwUHlobFBYdGliRzlqYTJWa1QyNDZkQ3hrYjIxRmRtVnVkRTVoYldVNmJpeGxkbVZ1ZEZONWMzUmxiVVpzWVdkek9uSXNi'
    || 'bUYwYVhabFJYWmxiblE2YVN4MFlYSm5aWFJEYjI1MFlXbHVaWEp6T2x0c1hYMHNkQ0U5UFc1MWJHd21KaWgwUFdoeUtIUXBMSFFoUFQxdWRXeHNKaVoyYVNo'
    || 'MEtTa3NaU2s2S0dVdVpYWmxiblJUZVhOMFpXMUdiR0ZuYzN3OWNpeDBQV1V1ZEdGeVoyVjBRMjl1ZEdGcGJtVnljeXhzSVQwOWJuVnNiQ1ltZEM1cGJtUmxl'
    || 'RTltS0d3cFBUMDlMVEVtSm5RdWNIVnphQ2hzS1N4bEtYMW1kVzVqZEdsdmJpQk1aQ2hsTEhRc2JpeHlMR3dwZTNOM2FYUmphQ2gwS1h0allYTmxJbVp2WTNW'
    || 'emFXNGlPbkpsZEhWeWJpQkVkRDFsY2loRWRDeGxMSFFzYml4eUxHd3BMQ0V3TzJOaGMyVWlaSEpoWjJWdWRHVnlJanB5WlhSMWNtNGdRWFE5WlhJb1FYUXNa'
    || 'U3gwTEc0c2NpeHNLU3doTUR0allYTmxJbTF2ZFhObGIzWmxjaUk2Y21WMGRYSnVJRVowUFdWeUtFWjBMR1VzZEN4dUxISXNiQ2tzSVRBN1kyRnpaU0p3YjJs'
    || 'dWRHVnliM1psY2lJNmRtRnlJR2s5YkM1d2IybHVkR1Z5U1dRN2NtVjBkWEp1SUhGdUxuTmxkQ2hwTEdWeUtIRnVMbWRsZENocEtYeDhiblZzYkN4bExIUXNi'
    || 'aXh5TEd3cEtTd2hNRHRqWVhObEltZHZkSEJ2YVc1MFpYSmpZWEIwZFhKbElqcHlaWFIxY200Z2FUMXNMbkJ2YVc1MFpYSkpaQ3hpYmk1elpYUW9hU3hsY2lo'
    || 'aWJpNW5aWFFvYVNsOGZHNTFiR3dzWlN4MExHNHNjaXhzS1Nrc0lUQjljbVYwZFhKdUlURjlablZ1WTNScGIyNGdRbk1vWlNsN2RtRnlJSFE5Y200b1pTNTBZ'
    || 'WEpuWlhRcE8ybG1LSFFoUFQxdWRXeHNLWHQyWVhJZ2JqMXViaWgwS1R0cFppaHVJVDA5Ym5Wc2JDbDdhV1lvZEQxdUxuUmhaeXgwUFQwOU1UTXBlMmxtS0hR'
    || 'OVRITW9iaWtzZENFOVBXNTFiR3dwZTJVdVlteHZZMnRsWkU5dVBYUXNWM01vWlM1d2NtbHZjbWwwZVN4bWRXNWpkR2x2YmlncGUwaHpLRzRwZlNrN2NtVjBk'
    || 'WEp1ZlgxbGJITmxJR2xtS0hROVBUMHpKaVp1TG5OMFlYUmxUbTlrWlM1amRYSnlaVzUwTG0xbGJXOXBlbVZrVTNSaGRHVXVhWE5FWldoNVpISmhkR1ZrS1h0'
    || 'bExtSnNiMk5yWldSUGJqMXVMblJoWnowOVBUTS9iaTV6ZEdGMFpVNXZaR1V1WTI5dWRHRnBibVZ5U1c1bWJ6cHVkV3hzTzNKbGRIVnlibjE5ZldVdVlteHZZ'
    || 'MnRsWkU5dVBXNTFiR3g5Wm5WdVkzUnBiMjRnVjNJb1pTbDdhV1lvWlM1aWJHOWphMlZrVDI0aFBUMXVkV3hzS1hKbGRIVnliaUV4TzJadmNpaDJZWElnZEQx'
    || 'bExuUmhjbWRsZEVOdmJuUmhhVzVsY25NN01EeDBMbXhsYm1kMGFEc3BlM1poY2lCdVBYaHBLR1V1Wkc5dFJYWmxiblJPWVcxbExHVXVaWFpsYm5SVGVYTjBa'
    || 'VzFHYkdGbmN5eDBXekJkTEdVdWJtRjBhWFpsUlhabGJuUXBPMmxtS0c0OVBUMXVkV3hzS1h0dVBXVXVibUYwYVhabFJYWmxiblE3ZG1GeUlISTlibVYzSUc0'
    || 'dVkyOXVjM1J5ZFdOMGIzSW9iaTUwZVhCbExHNHBPMjlwUFhJc2JpNTBZWEpuWlhRdVpHbHpjR0YwWTJoRmRtVnVkQ2h5S1N4dmFUMXVkV3hzZldWc2MyVWdj'
    || 'bVYwZFhKdUlIUTlhSElvYmlrc2RDRTlQVzUxYkd3bUpuWnBLSFFwTEdVdVlteHZZMnRsWkU5dVBXNHNJVEU3ZEM1emFHbG1kQ2dwZlhKbGRIVnliaUV3Zlda'
    || 'MWJtTjBhVzl1SUZGektHVXNkQ3h1S1h0WGNpaGxLU1ltYmk1a1pXeGxkR1VvZENsOVpuVnVZM1JwYjI0Z1VtUW9LWHRuYVQwaE1TeEVkQ0U5UFc1MWJHd21K'
    || 'bGR5S0VSMEtTWW1LRVIwUFc1MWJHd3BMRUYwSVQwOWJuVnNiQ1ltVjNJb1FYUXBKaVlvUVhROWJuVnNiQ2tzUm5RaFBUMXVkV3hzSmlaWGNpaEdkQ2ttSmlo'
    || 'R2REMXVkV3hzS1N4eGJpNW1iM0pGWVdOb0tGRnpLU3hpYmk1bWIzSkZZV05vS0ZGektYMW1kVzVqZEdsdmJpQjBjaWhsTEhRcGUyVXVZbXh2WTJ0bFpFOXVQ'
    || 'VDA5ZENZbUtHVXVZbXh2WTJ0bFpFOXVQVzUxYkd3c1oybDhmQ2huYVQwaE1DeG1MblZ1YzNSaFlteGxYM05qYUdWa2RXeGxRMkZzYkdKaFkyc29aaTUxYm5O'
    || 'MFlXSnNaVjlPYjNKdFlXeFFjbWx2Y21sMGVTeFNaQ2twS1gxbWRXNWpkR2x2YmlCdWNpaGxLWHRtZFc1amRHbHZiaUIwS0d3cGUzSmxkSFZ5YmlCMGNpaHNM'
    || 'R1VwZldsbUtEQThKSEl1YkdWdVozUm9LWHQwY2lna2Nsc3dYU3hsS1R0bWIzSW9kbUZ5SUc0OU1UdHVQQ1J5TG14bGJtZDBhRHR1S3lzcGUzWmhjaUJ5UFNS'
    || 'eVcyNWRPM0l1WW14dlkydGxaRTl1UFQwOVpTWW1LSEl1WW14dlkydGxaRTl1UFc1MWJHd3BmWDFtYjNJb1JIUWhQVDF1ZFd4c0ppWjBjaWhFZEN4bEtTeEJk'
    || 'Q0U5UFc1MWJHd21KblJ5S0VGMExHVXBMRVowSVQwOWJuVnNiQ1ltZEhJb1JuUXNaU2tzY1c0dVptOXlSV0ZqYUNoMEtTeGliaTVtYjNKRllXTm9LSFFwTEc0'
    || 'OU1EdHVQRlYwTG14bGJtZDBhRHR1S3lzcGNqMVZkRnR1WFN4eUxtSnNiMk5yWldSUGJqMDlQV1VtSmloeUxtSnNiMk5yWldSUGJqMXVkV3hzS1R0bWIzSW9P'
    || 'ekE4VlhRdWJHVnVaM1JvSmlZb2JqMVZkRnN3WFN4dUxtSnNiMk5yWldSUGJqMDlQVzUxYkd3cE95bENjeWh1S1N4dUxtSnNiMk5yWldSUGJqMDlQVzUxYkd3'
    || 'bUpsVjBMbk5vYVdaMEtDbDlkbUZ5SUZOdVBXOWxMbEpsWVdOMFEzVnljbVZ1ZEVKaGRHTm9RMjl1Wm1sbkxGWnlQU0V3TzJaMWJtTjBhVzl1SUUxa0tHVXNk'
    || 'Q3h1TEhJcGUzWmhjaUJzUFc1bExHazlVMjR1ZEhKaGJuTnBkR2x2Ymp0VGJpNTBjbUZ1YzJsMGFXOXVQVzUxYkd3N2RISjVlMjVsUFRFc2VXa29aU3gwTEc0'
    || 'c2NpbDlabWx1WVd4c2VYdHVaVDFzTEZOdUxuUnlZVzV6YVhScGIyNDlhWDE5Wm5WdVkzUnBiMjRnVUdRb1pTeDBMRzRzY2lsN2RtRnlJR3c5Ym1Vc2FUMVRi'
    || 'aTUwY21GdWMybDBhVzl1TzFOdUxuUnlZVzV6YVhScGIyNDliblZzYkR0MGNubDdibVU5TkN4NWFTaGxMSFFzYml4eUtYMW1hVzVoYkd4NWUyNWxQV3dzVTI0'
    || 'dWRISmhibk5wZEdsdmJqMXBmWDFtZFc1amRHbHZiaUI1YVNobExIUXNiaXh5S1h0cFppaFdjaWw3ZG1GeUlHdzllR2tvWlN4MExHNHNjaWs3YVdZb2JEMDlQ'
    || 'VzUxYkd3cFJHa29aU3gwTEhJc1FuSXNiaWtzVm5Nb1pTeHlLVHRsYkhObElHbG1LRXhrS0d3c1pTeDBMRzRzY2lrcGNpNXpkRzl3VUhKdmNHRm5ZWFJwYjI0'
    || 'b0tUdGxiSE5sSUdsbUtGWnpLR1VzY2lrc2RDWTBKaVl0TVR4RFpDNXBibVJsZUU5bUtHVXBLWHRtYjNJb08yd2hQVDF1ZFd4c095bDdkbUZ5SUdrOWFISW9i'
    || 'Q2s3YVdZb2FTRTlQVzUxYkd3bUpsVnpLR2twTEdrOWVHa29aU3gwTEc0c2Npa3NhVDA5UFc1MWJHd21Ka1JwS0dVc2RDeHlMRUp5TEc0cExHazlQVDFzS1dK'
    || 'eVpXRnJPMnc5YVgxc0lUMDliblZzYkNZbWNpNXpkRzl3VUhKdmNHRm5ZWFJwYjI0b0tYMWxiSE5sSUVScEtHVXNkQ3h5TEc1MWJHd3NiaWw5ZlhaaGNpQkNj'
    || 'ajF1ZFd4c08yWjFibU4wYVc5dUlIaHBLR1VzZEN4dUxISXBlMmxtS0VKeVBXNTFiR3dzWlQxemFTaHlLU3hsUFhKdUtHVXBMR1VoUFQxdWRXeHNLV2xtS0hR'
    || 'OWJtNG9aU2tzZEQwOVBXNTFiR3dwWlQxdWRXeHNPMlZzYzJVZ2FXWW9iajEwTG5SaFp5eHVQVDA5TVRNcGUybG1LR1U5VEhNb2RDa3NaU0U5UFc1MWJHd3Bj'
    || 'bVYwZFhKdUlHVTdaVDF1ZFd4c2ZXVnNjMlVnYVdZb2JqMDlQVE1wZTJsbUtIUXVjM1JoZEdWT2IyUmxMbU4xY25KbGJuUXViV1Z0YjJsNlpXUlRkR0YwWlM1'
    || 'cGMwUmxhSGxrY21GMFpXUXBjbVYwZFhKdUlIUXVkR0ZuUFQwOU16OTBMbk4wWVhSbFRtOWtaUzVqYjI1MFlXbHVaWEpKYm1adk9tNTFiR3c3WlQxdWRXeHNm'
    || 'V1ZzYzJVZ2RDRTlQV1VtSmlobFBXNTFiR3dwTzNKbGRIVnliaUJDY2oxbExHNTFiR3g5Wm5WdVkzUnBiMjRnV1hNb1pTbDdjM2RwZEdOb0tHVXBlMk5oYzJV'
    || 'aVkyRnVZMlZzSWpwallYTmxJbU5zYVdOcklqcGpZWE5sSW1Oc2IzTmxJanBqWVhObEltTnZiblJsZUhSdFpXNTFJanBqWVhObEltTnZjSGtpT21OaGMyVWlZ'
    || 'M1YwSWpwallYTmxJbUYxZUdOc2FXTnJJanBqWVhObEltUmliR05zYVdOcklqcGpZWE5sSW1SeVlXZGxibVFpT21OaGMyVWlaSEpoWjNOMFlYSjBJanBqWVhO'
    || 'bEltUnliM0FpT21OaGMyVWlabTlqZFhOcGJpSTZZMkZ6WlNKbWIyTjFjMjkxZENJNlkyRnpaU0pwYm5CMWRDSTZZMkZ6WlNKcGJuWmhiR2xrSWpwallYTmxJ'
    || 'bXRsZVdSdmQyNGlPbU5oYzJVaWEyVjVjSEpsYzNNaU9tTmhjMlVpYTJWNWRYQWlPbU5oYzJVaWJXOTFjMlZrYjNkdUlqcGpZWE5sSW0xdmRYTmxkWEFpT21O'
    || 'aGMyVWljR0Z6ZEdVaU9tTmhjMlVpY0dGMWMyVWlPbU5oYzJVaWNHeGhlU0k2WTJGelpTSndiMmx1ZEdWeVkyRnVZMlZzSWpwallYTmxJbkJ2YVc1MFpYSmti'
    || 'M2R1SWpwallYTmxJbkJ2YVc1MFpYSjFjQ0k2WTJGelpTSnlZWFJsWTJoaGJtZGxJanBqWVhObEluSmxjMlYwSWpwallYTmxJbkpsYzJsNlpTSTZZMkZ6WlNK'
    || 'elpXVnJaV1FpT21OaGMyVWljM1ZpYldsMElqcGpZWE5sSW5SdmRXTm9ZMkZ1WTJWc0lqcGpZWE5sSW5SdmRXTm9aVzVrSWpwallYTmxJblJ2ZFdOb2MzUmhj'
    || 'blFpT21OaGMyVWlkbTlzZFcxbFkyaGhibWRsSWpwallYTmxJbU5vWVc1blpTSTZZMkZ6WlNKelpXeGxZM1JwYjI1amFHRnVaMlVpT21OaGMyVWlkR1Y0ZEVs'
    || 'dWNIVjBJanBqWVhObEltTnZiWEJ2YzJsMGFXOXVjM1JoY25RaU9tTmhjMlVpWTI5dGNHOXphWFJwYjI1bGJtUWlPbU5oYzJVaVkyOXRjRzl6YVhScGIyNTFj'
    || 'R1JoZEdVaU9tTmhjMlVpWW1WbWIzSmxZbXgxY2lJNlkyRnpaU0poWm5SbGNtSnNkWElpT21OaGMyVWlZbVZtYjNKbGFXNXdkWFFpT21OaGMyVWlZbXgxY2lJ'
    || 'NlkyRnpaU0ptZFd4c2MyTnlaV1Z1WTJoaGJtZGxJanBqWVhObEltWnZZM1Z6SWpwallYTmxJbWhoYzJoamFHRnVaMlVpT21OaGMyVWljRzl3YzNSaGRHVWlP'
    || 'bU5oYzJVaWMyVnNaV04wSWpwallYTmxJbk5sYkdWamRITjBZWEowSWpweVpYUjFjbTRnTVR0allYTmxJbVJ5WVdjaU9tTmhjMlVpWkhKaFoyVnVkR1Z5SWpw'
    || 'allYTmxJbVJ5WVdkbGVHbDBJanBqWVhObEltUnlZV2RzWldGMlpTSTZZMkZ6WlNKa2NtRm5iM1psY2lJNlkyRnpaU0p0YjNWelpXMXZkbVVpT21OaGMyVWli'
    || 'VzkxYzJWdmRYUWlPbU5oYzJVaWJXOTFjMlZ2ZG1WeUlqcGpZWE5sSW5CdmFXNTBaWEp0YjNabElqcGpZWE5sSW5CdmFXNTBaWEp2ZFhRaU9tTmhjMlVpY0c5'
    || 'cGJuUmxjbTkyWlhJaU9tTmhjMlVpYzJOeWIyeHNJanBqWVhObEluUnZaMmRzWlNJNlkyRnpaU0owYjNWamFHMXZkbVVpT21OaGMyVWlkMmhsWld3aU9tTmhj'
    || 'MlVpYlc5MWMyVmxiblJsY2lJNlkyRnpaU0p0YjNWelpXeGxZWFpsSWpwallYTmxJbkJ2YVc1MFpYSmxiblJsY2lJNlkyRnpaU0p3YjJsdWRHVnliR1ZoZG1V'
    || 'aU9uSmxkSFZ5YmlBME8yTmhjMlVpYldWemMyRm5aU0k2YzNkcGRHTm9LSGhrS0NrcGUyTmhjMlVnWm1rNmNtVjBkWEp1SURFN1kyRnpaU0I2Y3pweVpYUjFj'
    || 'bTRnTkR0allYTmxJRVJ5T21OaGMyVWdkMlE2Y21WMGRYSnVJREUyTzJOaGMyVWdSSE02Y21WMGRYSnVJRFV6TmpnM01Ea3hNanRrWldaaGRXeDBPbkpsZEhW'
    || 'eWJpQXhObjFrWldaaGRXeDBPbkpsZEhWeWJpQXhObjE5ZG1GeUlFaDBQVzUxYkd3c2QyazliblZzYkN4UmNqMXVkV3hzTzJaMWJtTjBhVzl1SUV0ektDbDdh'
    || 'V1lvVVhJcGNtVjBkWEp1SUZGeU8zWmhjaUJsTEhROWQya3NiajEwTG14bGJtZDBhQ3h5TEd3OUluWmhiSFZsSW1sdUlFaDBQMGgwTG5aaGJIVmxPa2gwTG5S'
    || 'bGVIUkRiMjUwWlc1MExHazliQzVzWlc1bmRHZzdabTl5S0dVOU1EdGxQRzRtSm5SYlpWMDlQVDFzVzJWZE8yVXJLeWs3ZG1GeUlHODliaTFsTzJadmNpaHlQ'
    || 'VEU3Y2p3OWJ5WW1kRnR1TFhKZFBUMDliRnRwTFhKZE8zSXJLeWs3Y21WMGRYSnVJRkZ5UFd3dWMyeHBZMlVvWlN3eFBISS9NUzF5T25admFXUWdNQ2w5Wm5W'
    || 'dVkzUnBiMjRnV1hJb1pTbDdkbUZ5SUhROVpTNXJaWGxEYjJSbE8zSmxkSFZ5YmlKamFHRnlRMjlrWlNKcGJpQmxQeWhsUFdVdVkyaGhja052WkdVc1pUMDlQ'
    || 'VEFtSm5ROVBUMHhNeVltS0dVOU1UTXBLVHBsUFhRc1pUMDlQVEV3SmlZb1pUMHhNeWtzTXpJOFBXVjhmR1U5UFQweE16OWxPakI5Wm5WdVkzUnBiMjRnUzNJ'
    || 'b0tYdHlaWFIxY200aE1IMW1kVzVqZEdsdmJpQkhjeWdwZTNKbGRIVnliaUV4ZldaMWJtTjBhVzl1SUZobEtHVXBlMloxYm1OMGFXOXVJSFFvYml4eUxHd3Nh'
    || 'U3h2S1h0MGFHbHpMbDl5WldGamRFNWhiV1U5Yml4MGFHbHpMbDkwWVhKblpYUkpibk4wUFd3c2RHaHBjeTUwZVhCbFBYSXNkR2hwY3k1dVlYUnBkbVZGZG1W'
    || 'dWREMXBMSFJvYVhNdWRHRnlaMlYwUFc4c2RHaHBjeTVqZFhKeVpXNTBWR0Z5WjJWMFBXNTFiR3c3Wm05eUtIWmhjaUJqSUdsdUlHVXBaUzVvWVhOUGQyNVFj'
    || 'bTl3WlhKMGVTaGpLU1ltS0c0OVpWdGpYU3gwYUdselcyTmRQVzQvYmlocEtUcHBXMk5kS1R0eVpYUjFjbTRnZEdocGN5NXBjMFJsWm1GMWJIUlFjbVYyWlc1'
    || 'MFpXUTlLR2t1WkdWbVlYVnNkRkJ5WlhabGJuUmxaQ0U5Ym5Wc2JEOXBMbVJsWm1GMWJIUlFjbVYyWlc1MFpXUTZhUzV5WlhSMWNtNVdZV3gxWlQwOVBTRXhL'
    || 'VDlMY2pwSGN5eDBhR2x6TG1selVISnZjR0ZuWVhScGIyNVRkRzl3Y0dWa1BVZHpMSFJvYVhOOWNtVjBkWEp1SUU4b2RDNXdjbTkwYjNSNWNHVXNlM0J5Wlha'
    || 'bGJuUkVaV1poZFd4ME9tWjFibU4wYVc5dUtDbDdkR2hwY3k1a1pXWmhkV3gwVUhKbGRtVnVkR1ZrUFNFd08zWmhjaUJ1UFhSb2FYTXVibUYwYVhabFJYWmxi'
    || 'blE3YmlZbUtHNHVjSEpsZG1WdWRFUmxabUYxYkhRL2JpNXdjbVYyWlc1MFJHVm1ZWFZzZENncE9uUjVjR1Z2WmlCdUxuSmxkSFZ5YmxaaGJIVmxJVDBpZFc1'
    || 'cmJtOTNiaUltSmlodUxuSmxkSFZ5YmxaaGJIVmxQU0V4S1N4MGFHbHpMbWx6UkdWbVlYVnNkRkJ5WlhabGJuUmxaRDFMY2lsOUxITjBiM0JRY205d1lXZGhk'
    || 'R2x2YmpwbWRXNWpkR2x2YmlncGUzWmhjaUJ1UFhSb2FYTXVibUYwYVhabFJYWmxiblE3YmlZbUtHNHVjM1J2Y0ZCeWIzQmhaMkYwYVc5dVAyNHVjM1J2Y0ZC'
    || 'eWIzQmhaMkYwYVc5dUtDazZkSGx3Wlc5bUlHNHVZMkZ1WTJWc1FuVmlZbXhsSVQwaWRXNXJibTkzYmlJbUppaHVMbU5oYm1ObGJFSjFZbUpzWlQwaE1Da3Nk'
    || 'R2hwY3k1cGMxQnliM0JoWjJGMGFXOXVVM1J2Y0hCbFpEMUxjaWw5TEhCbGNuTnBjM1E2Wm5WdVkzUnBiMjRvS1h0OUxHbHpVR1Z5YzJsemRHVnVkRHBMY24w'
    || 'cExIUjlkbUZ5SUY5dVBYdGxkbVZ1ZEZCb1lYTmxPakFzWW5WaVlteGxjem93TEdOaGJtTmxiR0ZpYkdVNk1DeDBhVzFsVTNSaGJYQTZablZ1WTNScGIyNG9a'
    || 'U2w3Y21WMGRYSnVJR1V1ZEdsdFpWTjBZVzF3Zkh4RVlYUmxMbTV2ZHlncGZTeGtaV1poZFd4MFVISmxkbVZ1ZEdWa09qQXNhWE5VY25WemRHVmtPakI5TEZO'
    || 'cFBWaGxLRjl1S1N4eWNqMVBLSHQ5TEY5dUxIdDJhV1YzT2pBc1pHVjBZV2xzT2pCOUtTeFBaRDFZWlNoeWNpa3NYMmtzYTJrc2JISXNSM0k5VHloN2ZTeHlj'
    || 'aXg3YzJOeVpXVnVXRG93TEhOamNtVmxibGs2TUN4amJHbGxiblJZT2pBc1kyeHBaVzUwV1Rvd0xIQmhaMlZZT2pBc2NHRm5aVms2TUN4amRISnNTMlY1T2pB'
    || 'c2MyaHBablJMWlhrNk1DeGhiSFJMWlhrNk1DeHRaWFJoUzJWNU9qQXNaMlYwVFc5a2FXWnBaWEpUZEdGMFpUcE9hU3hpZFhSMGIyNDZNQ3hpZFhSMGIyNXpP'
    || 'akFzY21Wc1lYUmxaRlJoY21kbGREcG1kVzVqZEdsdmJpaGxLWHR5WlhSMWNtNGdaUzV5Wld4aGRHVmtWR0Z5WjJWMFBUMDlkbTlwWkNBd1AyVXVabkp2YlVW'
    || 'c1pXMWxiblE5UFQxbExuTnlZMFZzWlcxbGJuUS9aUzUwYjBWc1pXMWxiblE2WlM1bWNtOXRSV3hsYldWdWREcGxMbkpsYkdGMFpXUlVZWEpuWlhSOUxHMXZk'
    || 'bVZ0Wlc1MFdEcG1kVzVqZEdsdmJpaGxLWHR5WlhSMWNtNGliVzkyWlcxbGJuUllJbWx1SUdVL1pTNXRiM1psYldWdWRGZzZLR1VoUFQxc2NpWW1LR3h5Smla'
    || 'bExuUjVjR1U5UFQwaWJXOTFjMlZ0YjNabElqOG9YMms5WlM1elkzSmxaVzVZTFd4eUxuTmpjbVZsYmxnc2EyazlaUzV6WTNKbFpXNVpMV3h5TG5OamNtVmxi'
    || 'bGtwT210cFBWOXBQVEFzYkhJOVpTa3NYMmtwZlN4dGIzWmxiV1Z1ZEZrNlpuVnVZM1JwYjI0b1pTbDdjbVYwZFhKdUltMXZkbVZ0Wlc1MFdTSnBiaUJsUDJV'
    || 'dWJXOTJaVzFsYm5SWk9tdHBmWDBwTEZoelBWaGxLRWR5S1N4SlpEMVBLSHQ5TEVkeUxIdGtZWFJoVkhKaGJuTm1aWEk2TUgwcExIcGtQVmhsS0Vsa0tTeEVa'
    || 'RDFQS0h0OUxISnlMSHR5Wld4aGRHVmtWR0Z5WjJWME9qQjlLU3hGYVQxWVpTaEVaQ2tzUVdROVR5aDdmU3hmYml4N1lXNXBiV0YwYVc5dVRtRnRaVG93TEdW'
    || 'c1lYQnpaV1JVYVcxbE9qQXNjSE5sZFdSdlJXeGxiV1Z1ZERvd2ZTa3NSbVE5V0dVb1FXUXBMRlZrUFU4b2UzMHNYMjRzZTJOc2FYQmliMkZ5WkVSaGRHRTZa'
    || 'blZ1WTNScGIyNG9aU2w3Y21WMGRYSnVJbU5zYVhCaWIyRnlaRVJoZEdFaWFXNGdaVDlsTG1Oc2FYQmliMkZ5WkVSaGRHRTZkMmx1Wkc5M0xtTnNhWEJpYjJG'
    || 'eVpFUmhkR0Y5ZlNrc1NHUTlXR1VvVldRcExDUmtQVThvZTMwc1gyNHNlMlJoZEdFNk1IMHBMRnB6UFZobEtDUmtLU3hYWkQxN1JYTmpPaUpGYzJOaGNHVWlM'
    || 'Rk53WVdObFltRnlPaUlnSWl4TVpXWjBPaUpCY25KdmQweGxablFpTEZWd09pSkJjbkp2ZDFWd0lpeFNhV2RvZERvaVFYSnliM2RTYVdkb2RDSXNSRzkzYmpv'
    || 'aVFYSnliM2RFYjNkdUlpeEVaV3c2SWtSbGJHVjBaU0lzVjJsdU9pSlBVeUlzVFdWdWRUb2lRMjl1ZEdWNGRFMWxiblVpTEVGd2NITTZJa052Ym5SbGVIUk5a'
    || 'VzUxSWl4VFkzSnZiR3c2SWxOamNtOXNiRXh2WTJzaUxFMXZlbEJ5YVc1MFlXSnNaVXRsZVRvaVZXNXBaR1Z1ZEdsbWFXVmtJbjBzVm1ROWV6ZzZJa0poWTJ0'
    || 'emNHRmpaU0lzT1RvaVZHRmlJaXd4TWpvaVEyeGxZWElpTERFek9pSkZiblJsY2lJc01UWTZJbE5vYVdaMElpd3hOem9pUTI5dWRISnZiQ0lzTVRnNklrRnNk'
    || 'Q0lzTVRrNklsQmhkWE5sSWl3eU1Eb2lRMkZ3YzB4dlkyc2lMREkzT2lKRmMyTmhjR1VpTERNeU9pSWdJaXd6TXpvaVVHRm5aVlZ3SWl3ek5Eb2lVR0ZuWlVS'
    || 'dmQyNGlMRE0xT2lKRmJtUWlMRE0yT2lKSWIyMWxJaXd6TnpvaVFYSnliM2RNWldaMElpd3pPRG9pUVhKeWIzZFZjQ0lzTXprNklrRnljbTkzVW1sbmFIUWlM'
    || 'RFF3T2lKQmNuSnZkMFJ2ZDI0aUxEUTFPaUpKYm5ObGNuUWlMRFEyT2lKRVpXeGxkR1VpTERFeE1qb2lSakVpTERFeE16b2lSaklpTERFeE5Eb2lSak1pTERF'
    || 'eE5Ub2lSalFpTERFeE5qb2lSalVpTERFeE56b2lSallpTERFeE9Eb2lSamNpTERFeE9Ub2lSamdpTERFeU1Eb2lSamtpTERFeU1Ub2lSakV3SWl3eE1qSTZJ'
    || 'a1l4TVNJc01USXpPaUpHTVRJaUxERTBORG9pVG5WdFRHOWpheUlzTVRRMU9pSlRZM0p2Ykd4TWIyTnJJaXd5TWpRNklrMWxkR0VpZlN4Q1pEMTdRV3gwT2lK'
    || 'aGJIUkxaWGtpTEVOdmJuUnliMnc2SW1OMGNteExaWGtpTEUxbGRHRTZJbTFsZEdGTFpYa2lMRk5vYVdaME9pSnphR2xtZEV0bGVTSjlPMloxYm1OMGFXOXVJ'
    || 'RkZrS0dVcGUzWmhjaUIwUFhSb2FYTXVibUYwYVhabFJYWmxiblE3Y21WMGRYSnVJSFF1WjJWMFRXOWthV1pwWlhKVGRHRjBaVDkwTG1kbGRFMXZaR2xtYVdW'
    || 'eVUzUmhkR1VvWlNrNktHVTlRbVJiWlYwcFB5RWhkRnRsWFRvaE1YMW1kVzVqZEdsdmJpQk9hU2dwZTNKbGRIVnliaUJSWkgxMllYSWdXV1E5VHloN2ZTeHlj'
    || 'aXg3YTJWNU9tWjFibU4wYVc5dUtHVXBlMmxtS0dVdWEyVjVLWHQyWVhJZ2REMVhaRnRsTG10bGVWMThmR1V1YTJWNU8ybG1LSFFoUFQwaVZXNXBaR1Z1ZEds'
    || 'bWFXVmtJaWx5WlhSMWNtNGdkSDF5WlhSMWNtNGdaUzUwZVhCbFBUMDlJbXRsZVhCeVpYTnpJajhvWlQxWmNpaGxLU3hsUFQwOU1UTS9Ja1Z1ZEdWeUlqcFRk'
    || 'SEpwYm1jdVpuSnZiVU5vWVhKRGIyUmxLR1VwS1RwbExuUjVjR1U5UFQwaWEyVjVaRzkzYmlKOGZHVXVkSGx3WlQwOVBTSnJaWGwxY0NJL1ZtUmJaUzVyWlhs'
    || 'RGIyUmxYWHg4SWxWdWFXUmxiblJwWm1sbFpDSTZJaUo5TEdOdlpHVTZNQ3hzYjJOaGRHbHZiam93TEdOMGNteExaWGs2TUN4emFHbG1kRXRsZVRvd0xHRnNk'
    || 'RXRsZVRvd0xHMWxkR0ZMWlhrNk1DeHlaWEJsWVhRNk1DeHNiMk5oYkdVNk1DeG5aWFJOYjJScFptbGxjbE4wWVhSbE9rNXBMR05vWVhKRGIyUmxPbVoxYm1O'
    || 'MGFXOXVLR1VwZTNKbGRIVnliaUJsTG5SNWNHVTlQVDBpYTJWNWNISmxjM01pUDFseUtHVXBPakI5TEd0bGVVTnZaR1U2Wm5WdVkzUnBiMjRvWlNsN2NtVjBk'
    || 'WEp1SUdVdWRIbHdaVDA5UFNKclpYbGtiM2R1SW54OFpTNTBlWEJsUFQwOUltdGxlWFZ3SWo5bExtdGxlVU52WkdVNk1IMHNkMmhwWTJnNlpuVnVZM1JwYjI0'
    || 'b1pTbDdjbVYwZFhKdUlHVXVkSGx3WlQwOVBTSnJaWGx3Y21WemN5SS9XWElvWlNrNlpTNTBlWEJsUFQwOUltdGxlV1J2ZDI0aWZIeGxMblI1Y0dVOVBUMGlh'
    || 'MlY1ZFhBaVAyVXVhMlY1UTI5a1pUb3dmWDBwTEV0a1BWaGxLRmxrS1N4SFpEMVBLSHQ5TEVkeUxIdHdiMmx1ZEdWeVNXUTZNQ3gzYVdSMGFEb3dMR2hsYVdk'
    || 'b2REb3dMSEJ5WlhOemRYSmxPakFzZEdGdVoyVnVkR2xoYkZCeVpYTnpkWEpsT2pBc2RHbHNkRmc2TUN4MGFXeDBXVG93TEhSM2FYTjBPakFzY0c5cGJuUmxj'
    || 'bFI1Y0dVNk1DeHBjMUJ5YVcxaGNuazZNSDBwTEVwelBWaGxLRWRrS1N4WVpEMVBLSHQ5TEhKeUxIdDBiM1ZqYUdWek9qQXNkR0Z5WjJWMFZHOTFZMmhsY3pv'
    || 'd0xHTm9ZVzVuWldSVWIzVmphR1Z6T2pBc1lXeDBTMlY1T2pBc2JXVjBZVXRsZVRvd0xHTjBjbXhMWlhrNk1DeHphR2xtZEV0bGVUb3dMR2RsZEUxdlpHbG1h'
    || 'V1Z5VTNSaGRHVTZUbWw5S1N4YVpEMVlaU2hZWkNrc1NtUTlUeWg3ZlN4ZmJpeDdjSEp2Y0dWeWRIbE9ZVzFsT2pBc1pXeGhjSE5sWkZScGJXVTZNQ3h3YzJW'
    || 'MVpHOUZiR1Z0Wlc1ME9qQjlLU3h4WkQxWVpTaEtaQ2tzWW1ROVR5aDdmU3hIY2l4N1pHVnNkR0ZZT21aMWJtTjBhVzl1S0dVcGUzSmxkSFZ5YmlKa1pXeDBZ'
    || 'VmdpYVc0Z1pUOWxMbVJsYkhSaFdEb2lkMmhsWld4RVpXeDBZVmdpYVc0Z1pUOHRaUzUzYUdWbGJFUmxiSFJoV0Rvd2ZTeGtaV3gwWVZrNlpuVnVZM1JwYjI0'
    || 'b1pTbDdjbVYwZFhKdUltUmxiSFJoV1NKcGJpQmxQMlV1WkdWc2RHRlpPaUozYUdWbGJFUmxiSFJoV1NKcGJpQmxQeTFsTG5kb1pXVnNSR1ZzZEdGWk9pSjNh'
    || 'R1ZsYkVSbGJIUmhJbWx1SUdVL0xXVXVkMmhsWld4RVpXeDBZVG93ZlN4a1pXeDBZVm82TUN4a1pXeDBZVTF2WkdVNk1IMHBMR1ZtUFZobEtHSmtLU3gwWmox'
    || 'Yk9Td3hNeXd5Tnl3ek1sMHNhbWs5WHlZbUlrTnZiWEJ2YzJsMGFXOXVSWFpsYm5RaWFXNGdkMmx1Wkc5M0xHbHlQVzUxYkd3N1h5WW1JbVJ2WTNWdFpXNTBU'
    || 'VzlrWlNKcGJpQmtiMk4xYldWdWRDWW1LR2x5UFdSdlkzVnRaVzUwTG1SdlkzVnRaVzUwVFc5a1pTazdkbUZ5SUc1bVBWOG1KaUpVWlhoMFJYWmxiblFpYVc0'
    || 'Z2QybHVaRzkzSmlZaGFYSXNjWE05WHlZbUtDRnFhWHg4YVhJbUpqZzhhWEltSmpFeFBqMXBjaWtzWW5NOUlpQWlMR1YxUFNFeE8yWjFibU4wYVc5dUlIUjFL'
    || 'R1VzZENsN2MzZHBkR05vS0dVcGUyTmhjMlVpYTJWNWRYQWlPbkpsZEhWeWJpQjBaaTVwYm1SbGVFOW1LSFF1YTJWNVEyOWtaU2toUFQwdE1UdGpZWE5sSW10'
    || 'bGVXUnZkMjRpT25KbGRIVnliaUIwTG10bGVVTnZaR1VoUFQweU1qazdZMkZ6WlNKclpYbHdjbVZ6Y3lJNlkyRnpaU0p0YjNWelpXUnZkMjRpT21OaGMyVWla'
    || 'bTlqZFhOdmRYUWlPbkpsZEhWeWJpRXdPMlJsWm1GMWJIUTZjbVYwZFhKdUlURjlmV1oxYm1OMGFXOXVJRzUxS0dVcGUzSmxkSFZ5YmlCbFBXVXVaR1YwWVds'
    || 'c0xIUjVjR1Z2WmlCbFBUMGliMkpxWldOMElpWW1JbVJoZEdFaWFXNGdaVDlsTG1SaGRHRTZiblZzYkgxMllYSWdhMjQ5SVRFN1puVnVZM1JwYjI0Z2NtWW9a'
    || 'U3gwS1h0emQybDBZMmdvWlNsN1kyRnpaU0pqYjIxd2IzTnBkR2x2Ym1WdVpDSTZjbVYwZFhKdUlHNTFLSFFwTzJOaGMyVWlhMlY1Y0hKbGMzTWlPbkpsZEhW'
    || 'eWJpQjBMbmRvYVdOb0lUMDlNekkvYm5Wc2JEb29aWFU5SVRBc1luTXBPMk5oYzJVaWRHVjRkRWx1Y0hWMElqcHlaWFIxY200Z1pUMTBMbVJoZEdFc1pUMDlQ'
    || 'V0p6SmlabGRUOXVkV3hzT21VN1pHVm1ZWFZzZERweVpYUjFjbTRnYm5Wc2JIMTlablZ1WTNScGIyNGdiR1lvWlN4MEtYdHBaaWhyYmlseVpYUjFjbTRnWlQw'
    || 'OVBTSmpiMjF3YjNOcGRHbHZibVZ1WkNKOGZDRnFhU1ltZEhVb1pTeDBLVDhvWlQxTGN5Z3BMRkZ5UFhkcFBVaDBQVzUxYkd3c2EyNDlJVEVzWlNrNmJuVnNi'
    || 'RHR6ZDJsMFkyZ29aU2w3WTJGelpTSndZWE4wWlNJNmNtVjBkWEp1SUc1MWJHdzdZMkZ6WlNKclpYbHdjbVZ6Y3lJNmFXWW9JU2gwTG1OMGNteExaWGw4ZkhR'
    || 'dVlXeDBTMlY1Zkh4MExtMWxkR0ZMWlhrcGZIeDBMbU4wY214TFpYa21KblF1WVd4MFMyVjVLWHRwWmloMExtTm9ZWEltSmpFOGRDNWphR0Z5TG14bGJtZDBh'
    || 'Q2x5WlhSMWNtNGdkQzVqYUdGeU8ybG1LSFF1ZDJocFkyZ3BjbVYwZFhKdUlGTjBjbWx1Wnk1bWNtOXRRMmhoY2tOdlpHVW9kQzUzYUdsamFDbDljbVYwZFhK'
    || 'dUlHNTFiR3c3WTJGelpTSmpiMjF3YjNOcGRHbHZibVZ1WkNJNmNtVjBkWEp1SUhGekppWjBMbXh2WTJGc1pTRTlQU0pyYnlJL2JuVnNiRHAwTG1SaGRHRTda'
    || 'R1ZtWVhWc2REcHlaWFIxY200Z2JuVnNiSDE5ZG1GeUlHOW1QWHRqYjJ4dmNqb2hNQ3hrWVhSbE9pRXdMR1JoZEdWMGFXMWxPaUV3TENKa1lYUmxkR2x0WlMx'
    || 'c2IyTmhiQ0k2SVRBc1pXMWhhV3c2SVRBc2JXOXVkR2c2SVRBc2JuVnRZbVZ5T2lFd0xIQmhjM04zYjNKa09pRXdMSEpoYm1kbE9pRXdMSE5sWVhKamFEb2hN'
    || 'Q3gwWld3NklUQXNkR1Y0ZERvaE1DeDBhVzFsT2lFd0xIVnliRG9oTUN4M1pXVnJPaUV3ZlR0bWRXNWpkR2x2YmlCeWRTaGxLWHQyWVhJZ2REMWxKaVpsTG01'
    || 'dlpHVk9ZVzFsSmlabExtNXZaR1ZPWVcxbExuUnZURzkzWlhKRFlYTmxLQ2s3Y21WMGRYSnVJSFE5UFQwaWFXNXdkWFFpUHlFaGIyWmJaUzUwZVhCbFhUcDBQ'
    || 'VDA5SW5SbGVIUmhjbVZoSW4xbWRXNWpkR2x2YmlCc2RTaGxMSFFzYml4eUtYdEZjeWh5S1N4MFBXSnlLSFFzSW05dVEyaGhibWRsSWlrc01EeDBMbXhsYm1k'
    || 'MGFDWW1LRzQ5Ym1WM0lGTnBLQ0p2YmtOb1lXNW5aU0lzSW1Ob1lXNW5aU0lzYm5Wc2JDeHVMSElwTEdVdWNIVnphQ2g3WlhabGJuUTZiaXhzYVhOMFpXNWxj'
    || 'bk02ZEgwcEtYMTJZWElnYjNJOWJuVnNiQ3h6Y2oxdWRXeHNPMloxYm1OMGFXOXVJSE5tS0dVcGUxOTFLR1VzTUNsOVpuVnVZM1JwYjI0Z1dISW9aU2w3ZG1G'
    || 'eUlIUTlRMjRvWlNrN2FXWW9abk1vZENrcGNtVjBkWEp1SUdWOVpuVnVZM1JwYjI0Z2RXWW9aU3gwS1h0cFppaGxQVDA5SW1Ob1lXNW5aU0lwY21WMGRYSnVJ'
    || 'SFI5ZG1GeUlHbDFQU0V4TzJsbUtGOHBlM1poY2lCVWFUdHBaaWhmS1h0MllYSWdRMms5SW05dWFXNXdkWFFpYVc0Z1pHOWpkVzFsYm5RN2FXWW9JVU5wS1h0'
    || 'MllYSWdiM1U5Wkc5amRXMWxiblF1WTNKbFlYUmxSV3hsYldWdWRDZ2laR2wySWlrN2IzVXVjMlYwUVhSMGNtbGlkWFJsS0NKdmJtbHVjSFYwSWl3aWNtVjBk'
    || 'WEp1T3lJcExFTnBQWFI1Y0dWdlppQnZkUzV2Ym1sdWNIVjBQVDBpWm5WdVkzUnBiMjRpZlZScFBVTnBmV1ZzYzJVZ1ZHazlJVEU3YVhVOVZHa21KaWdoWkc5'
    || 'amRXMWxiblF1Wkc5amRXMWxiblJOYjJSbGZIdzVQR1J2WTNWdFpXNTBMbVJ2WTNWdFpXNTBUVzlrWlNsOVpuVnVZM1JwYjI0Z2MzVW9LWHR2Y2lZbUtHOXlM'
    || 'bVJsZEdGamFFVjJaVzUwS0NKdmJuQnliM0JsY25SNVkyaGhibWRsSWl4MWRTa3NjM0k5YjNJOWJuVnNiQ2w5Wm5WdVkzUnBiMjRnZFhVb1pTbDdhV1lvWlM1'
    || 'd2NtOXdaWEowZVU1aGJXVTlQVDBpZG1Gc2RXVWlKaVpZY2loemNpa3BlM1poY2lCMFBWdGRPMngxS0hRc2MzSXNaU3h6YVNobEtTa3NRM01vYzJZc2RDbDlm'
    || 'V1oxYm1OMGFXOXVJR0ZtS0dVc2RDeHVLWHRsUFQwOUltWnZZM1Z6YVc0aVB5aHpkU2dwTEc5eVBYUXNjM0k5Yml4dmNpNWhkSFJoWTJoRmRtVnVkQ2dpYjI1'
    || 'd2NtOXdaWEowZVdOb1lXNW5aU0lzZFhVcEtUcGxQVDA5SW1adlkzVnpiM1YwSWlZbWMzVW9LWDFtZFc1amRHbHZiaUJqWmlobEtYdHBaaWhsUFQwOUluTmxi'
    || 'R1ZqZEdsdmJtTm9ZVzVuWlNKOGZHVTlQVDBpYTJWNWRYQWlmSHhsUFQwOUltdGxlV1J2ZDI0aUtYSmxkSFZ5YmlCWWNpaHpjaWw5Wm5WdVkzUnBiMjRnWkdZ'
    || 'b1pTeDBLWHRwWmlobFBUMDlJbU5zYVdOcklpbHlaWFIxY200Z1dISW9kQ2w5Wm5WdVkzUnBiMjRnWm1Zb1pTeDBLWHRwWmlobFBUMDlJbWx1Y0hWMElueDha'
    || 'VDA5UFNKamFHRnVaMlVpS1hKbGRIVnliaUJZY2loMEtYMW1kVzVqZEdsdmJpQndaaWhsTEhRcGUzSmxkSFZ5YmlCbFBUMDlkQ1ltS0dVaFBUMHdmSHd4TDJV'
    || 'OVBUMHhMM1FwZkh4bElUMDlaU1ltZENFOVBYUjlkbUZ5SUdSMFBYUjVjR1Z2WmlCUFltcGxZM1F1YVhNOVBTSm1kVzVqZEdsdmJpSS9UMkpxWldOMExtbHpP'
    || 'bkJtTzJaMWJtTjBhVzl1SUhWeUtHVXNkQ2w3YVdZb1pIUW9aU3gwS1NseVpYUjFjbTRoTUR0cFppaDBlWEJsYjJZZ1pTRTlJbTlpYW1WamRDSjhmR1U5UFQx'
    || 'dWRXeHNmSHgwZVhCbGIyWWdkQ0U5SW05aWFtVmpkQ0o4ZkhROVBUMXVkV3hzS1hKbGRIVnliaUV4TzNaaGNpQnVQVTlpYW1WamRDNXJaWGx6S0dVcExISTlU'
    || 'MkpxWldOMExtdGxlWE1vZENrN2FXWW9iaTVzWlc1bmRHZ2hQVDF5TG14bGJtZDBhQ2x5WlhSMWNtNGhNVHRtYjNJb2NqMHdPM0k4Ymk1c1pXNW5kR2c3Y2lz'
    || 'cktYdDJZWElnYkQxdVczSmRPMmxtS0NGM0xtTmhiR3dvZEN4c0tYeDhJV1IwS0dWYmJGMHNkRnRzWFNrcGNtVjBkWEp1SVRGOWNtVjBkWEp1SVRCOVpuVnVZ'
    || 'M1JwYjI0Z1lYVW9aU2w3Wm05eUtEdGxKaVpsTG1acGNuTjBRMmhwYkdRN0tXVTlaUzVtYVhKemRFTm9hV3hrTzNKbGRIVnliaUJsZldaMWJtTjBhVzl1SUdO'
    || 'MUtHVXNkQ2w3ZG1GeUlHNDlZWFVvWlNrN1pUMHdPMlp2Y2loMllYSWdjanR1T3lsN2FXWW9iaTV1YjJSbFZIbHdaVDA5UFRNcGUybG1LSEk5WlN0dUxuUmxl'
    || 'SFJEYjI1MFpXNTBMbXhsYm1kMGFDeGxQRDEwSmlaeVBqMTBLWEpsZEhWeWJudHViMlJsT200c2IyWm1jMlYwT25RdFpYMDdaVDF5ZldVNmUyWnZjaWc3Ympz'
    || 'cGUybG1LRzR1Ym1WNGRGTnBZbXhwYm1jcGUyNDliaTV1WlhoMFUybGliR2x1Wnp0aWNtVmhheUJsZlc0OWJpNXdZWEpsYm5ST2IyUmxmVzQ5ZG05cFpDQXdm'
    || 'VzQ5WVhVb2JpbDlmV1oxYm1OMGFXOXVJR1IxS0dVc2RDbDdjbVYwZFhKdUlHVW1KblEvWlQwOVBYUS9JVEE2WlNZbVpTNXViMlJsVkhsd1pUMDlQVE0vSVRF'
    || 'NmRDWW1kQzV1YjJSbFZIbHdaVDA5UFRNL1pIVW9aU3gwTG5CaGNtVnVkRTV2WkdVcE9pSmpiMjUwWVdsdWN5SnBiaUJsUDJVdVkyOXVkR0ZwYm5Nb2RDazZa'
    || 'UzVqYjIxd1lYSmxSRzlqZFcxbGJuUlFiM05wZEdsdmJqOGhJU2hsTG1OdmJYQmhjbVZFYjJOMWJXVnVkRkJ2YzJsMGFXOXVLSFFwSmpFMktUb2hNVG9oTVgx'
    || 'bWRXNWpkR2x2YmlCbWRTZ3BlMlp2Y2loMllYSWdaVDEzYVc1a2IzY3NkRDFRY2lncE8zUWdhVzV6ZEdGdVkyVnZaaUJsTGtoVVRVeEpSbkpoYldWRmJHVnRa'
    || 'VzUwT3lsN2RISjVlM1poY2lCdVBYUjVjR1Z2WmlCMExtTnZiblJsYm5SWGFXNWtiM2N1Ykc5allYUnBiMjR1YUhKbFpqMDlJbk4wY21sdVp5SjlZMkYwWTJo'
    || 'N2JqMGhNWDFwWmlodUtXVTlkQzVqYjI1MFpXNTBWMmx1Wkc5M08yVnNjMlVnWW5KbFlXczdkRDFRY2lobExtUnZZM1Z0Wlc1MEtYMXlaWFIxY200Z2RIMW1k'
    || 'VzVqZEdsdmJpQk1hU2hsS1h0MllYSWdkRDFsSmlabExtNXZaR1ZPWVcxbEppWmxMbTV2WkdWT1lXMWxMblJ2VEc5M1pYSkRZWE5sS0NrN2NtVjBkWEp1SUhR'
    || 'bUppaDBQVDA5SW1sdWNIVjBJaVltS0dVdWRIbHdaVDA5UFNKMFpYaDBJbng4WlM1MGVYQmxQVDA5SW5ObFlYSmphQ0o4ZkdVdWRIbHdaVDA5UFNKMFpXd2lm'
    || 'SHhsTG5SNWNHVTlQVDBpZFhKc0lueDhaUzUwZVhCbFBUMDlJbkJoYzNOM2IzSmtJaWw4ZkhROVBUMGlkR1Y0ZEdGeVpXRWlmSHhsTG1OdmJuUmxiblJGWkds'
    || 'MFlXSnNaVDA5UFNKMGNuVmxJaWw5Wm5WdVkzUnBiMjRnYUdZb1pTbDdkbUZ5SUhROVpuVW9LU3h1UFdVdVptOWpkWE5sWkVWc1pXMHNjajFsTG5ObGJHVmpk'
    || 'R2x2YmxKaGJtZGxPMmxtS0hRaFBUMXVKaVp1SmladUxtOTNibVZ5Ukc5amRXMWxiblFtSm1SMUtHNHViM2R1WlhKRWIyTjFiV1Z1ZEM1a2IyTjFiV1Z1ZEVW'
    || 'c1pXMWxiblFzYmlrcGUybG1LSEloUFQxdWRXeHNKaVpNYVNodUtTbDdhV1lvZEQxeUxuTjBZWEowTEdVOWNpNWxibVFzWlQwOVBYWnZhV1FnTUNZbUtHVTlk'
    || 'Q2tzSW5ObGJHVmpkR2x2YmxOMFlYSjBJbWx1SUc0cGJpNXpaV3hsWTNScGIyNVRkR0Z5ZEQxMExHNHVjMlZzWldOMGFXOXVSVzVrUFUxaGRHZ3ViV2x1S0dV'
    || 'c2JpNTJZV3gxWlM1c1pXNW5kR2dwTzJWc2MyVWdhV1lvWlQwb2REMXVMbTkzYm1WeVJHOWpkVzFsYm5SOGZHUnZZM1Z0Wlc1MEtTWW1kQzVrWldaaGRXeDBW'
    || 'bWxsZDN4OGQybHVaRzkzTEdVdVoyVjBVMlZzWldOMGFXOXVLWHRsUFdVdVoyVjBVMlZzWldOMGFXOXVLQ2s3ZG1GeUlHdzliaTUwWlhoMFEyOXVkR1Z1ZEM1'
    || 'c1pXNW5kR2dzYVQxTllYUm9MbTFwYmloeUxuTjBZWEowTEd3cE8zSTljaTVsYm1ROVBUMTJiMmxrSURBL2FUcE5ZWFJvTG0xcGJpaHlMbVZ1WkN4c0tTd2ha'
    || 'UzVsZUhSbGJtUW1KbWsrY2lZbUtHdzljaXh5UFdrc2FUMXNLU3hzUFdOMUtHNHNhU2s3ZG1GeUlHODlZM1VvYml4eUtUdHNKaVp2SmlZb1pTNXlZVzVuWlVO'
    || 'dmRXNTBJVDA5TVh4OFpTNWhibU5vYjNKT2IyUmxJVDA5YkM1dWIyUmxmSHhsTG1GdVkyaHZjazltWm5ObGRDRTlQV3d1YjJabWMyVjBmSHhsTG1adlkzVnpU'
    || 'bTlrWlNFOVBXOHVibTlrWlh4OFpTNW1iMk4xYzA5bVpuTmxkQ0U5UFc4dWIyWm1jMlYwS1NZbUtIUTlkQzVqY21WaGRHVlNZVzVuWlNncExIUXVjMlYwVTNS'
    || 'aGNuUW9iQzV1YjJSbExHd3ViMlptYzJWMEtTeGxMbkpsYlc5MlpVRnNiRkpoYm1kbGN5Z3BMR2srY2o4b1pTNWhaR1JTWVc1blpTaDBLU3hsTG1WNGRHVnVa'
    || 'Q2h2TG01dlpHVXNieTV2Wm1aelpYUXBLVG9vZEM1elpYUkZibVFvYnk1dWIyUmxMRzh1YjJabWMyVjBLU3hsTG1Ga1pGSmhibWRsS0hRcEtTbDlmV1p2Y2lo'
    || 'MFBWdGRMR1U5Ymp0bFBXVXVjR0Z5Wlc1MFRtOWtaVHNwWlM1dWIyUmxWSGx3WlQwOVBURW1KblF1Y0hWemFDaDdaV3hsYldWdWREcGxMR3hsWm5RNlpTNXpZ'
    || 'M0p2Ykd4TVpXWjBMSFJ2Y0RwbExuTmpjbTlzYkZSdmNIMHBPMlp2Y2loMGVYQmxiMllnYmk1bWIyTjFjejA5SW1aMWJtTjBhVzl1SWlZbWJpNW1iMk4xY3ln'
    || 'cExHNDlNRHR1UEhRdWJHVnVaM1JvTzI0ckt5bGxQWFJiYmwwc1pTNWxiR1Z0Wlc1MExuTmpjbTlzYkV4bFpuUTlaUzVzWldaMExHVXVaV3hsYldWdWRDNXpZ'
    || 'M0p2Ykd4VWIzQTlaUzUwYjNCOWZYWmhjaUJ0WmoxZkppWWlaRzlqZFcxbGJuUk5iMlJsSW1sdUlHUnZZM1Z0Wlc1MEppWXhNVDQ5Wkc5amRXMWxiblF1Wkc5'
    || 'amRXMWxiblJOYjJSbExFVnVQVzUxYkd3c1VtazliblZzYkN4aGNqMXVkV3hzTEUxcFBTRXhPMloxYm1OMGFXOXVJSEIxS0dVc2RDeHVLWHQyWVhJZ2NqMXVM'
    || 'bmRwYm1SdmR6MDlQVzQvYmk1a2IyTjFiV1Z1ZERwdUxtNXZaR1ZVZVhCbFBUMDlPVDl1T200dWIzZHVaWEpFYjJOMWJXVnVkRHROYVh4OFJXNDlQVzUxYkd4'
    || 'OGZFVnVJVDA5VUhJb2NpbDhmQ2h5UFVWdUxDSnpaV3hsWTNScGIyNVRkR0Z5ZENKcGJpQnlKaVpNYVNoeUtUOXlQWHR6ZEdGeWREcHlMbk5sYkdWamRHbHZi'
    || 'bE4wWVhKMExHVnVaRHB5TG5ObGJHVmpkR2x2YmtWdVpIMDZLSEk5S0hJdWIzZHVaWEpFYjJOMWJXVnVkQ1ltY2k1dmQyNWxja1J2WTNWdFpXNTBMbVJsWm1G'
    || 'MWJIUldhV1YzZkh4M2FXNWtiM2NwTG1kbGRGTmxiR1ZqZEdsdmJpZ3BMSEk5ZTJGdVkyaHZjazV2WkdVNmNpNWhibU5vYjNKT2IyUmxMR0Z1WTJodmNrOW1a'
    || 'bk5sZERweUxtRnVZMmh2Y2s5bVpuTmxkQ3htYjJOMWMwNXZaR1U2Y2k1bWIyTjFjMDV2WkdVc1ptOWpkWE5QWm1aelpYUTZjaTVtYjJOMWMwOW1abk5sZEgw'
    || 'cExHRnlKaVoxY2loaGNpeHlLWHg4S0dGeVBYSXNjajFpY2loU2FTd2liMjVUWld4bFkzUWlLU3d3UEhJdWJHVnVaM1JvSmlZb2REMXVaWGNnVTJrb0ltOXVV'
    || 'MlZzWldOMElpd2ljMlZzWldOMElpeHVkV3hzTEhRc2Jpa3NaUzV3ZFhOb0tIdGxkbVZ1ZERwMExHeHBjM1JsYm1WeWN6cHlmU2tzZEM1MFlYSm5aWFE5Ulc0'
    || 'cEtTbDlablZ1WTNScGIyNGdXbklvWlN4MEtYdDJZWElnYmoxN2ZUdHlaWFIxY200Z2JsdGxMblJ2VEc5M1pYSkRZWE5sS0NsZFBYUXVkRzlNYjNkbGNrTmhj'
    || 'MlVvS1N4dVd5SlhaV0pyYVhRaUsyVmRQU0ozWldKcmFYUWlLM1FzYmxzaVRXOTZJaXRsWFQwaWJXOTZJaXQwTEc1OWRtRnlJRTV1UFh0aGJtbHRZWFJwYjI1'
    || 'bGJtUTZXbklvSWtGdWFXMWhkR2x2YmlJc0lrRnVhVzFoZEdsdmJrVnVaQ0lwTEdGdWFXMWhkR2x2Ym1sMFpYSmhkR2x2YmpwYWNpZ2lRVzVwYldGMGFXOXVJ'
    || 'aXdpUVc1cGJXRjBhVzl1U1hSbGNtRjBhVzl1SWlrc1lXNXBiV0YwYVc5dWMzUmhjblE2V25Jb0lrRnVhVzFoZEdsdmJpSXNJa0Z1YVcxaGRHbHZibE4wWVhK'
    || 'MElpa3NkSEpoYm5OcGRHbHZibVZ1WkRwYWNpZ2lWSEpoYm5OcGRHbHZiaUlzSWxSeVlXNXphWFJwYjI1RmJtUWlLWDBzVUdrOWUzMHNhSFU5ZTMwN1h5WW1L'
    || 'R2gxUFdSdlkzVnRaVzUwTG1OeVpXRjBaVVZzWlcxbGJuUW9JbVJwZGlJcExuTjBlV3hsTENKQmJtbHRZWFJwYjI1RmRtVnVkQ0pwYmlCM2FXNWtiM2Q4ZkNo'
    || 'a1pXeGxkR1VnVG00dVlXNXBiV0YwYVc5dVpXNWtMbUZ1YVcxaGRHbHZiaXhrWld4bGRHVWdUbTR1WVc1cGJXRjBhVzl1YVhSbGNtRjBhVzl1TG1GdWFXMWhk'
    || 'R2x2Yml4a1pXeGxkR1VnVG00dVlXNXBiV0YwYVc5dWMzUmhjblF1WVc1cGJXRjBhVzl1S1N3aVZISmhibk5wZEdsdmJrVjJaVzUwSW1sdUlIZHBibVJ2ZDN4'
    || 'OFpHVnNaWFJsSUU1dUxuUnlZVzV6YVhScGIyNWxibVF1ZEhKaGJuTnBkR2x2YmlrN1puVnVZM1JwYjI0Z1NuSW9aU2w3YVdZb1VHbGJaVjBwY21WMGRYSnVJ'
    || 'RkJwVzJWZE8ybG1LQ0ZPYmx0bFhTbHlaWFIxY200Z1pUdDJZWElnZEQxT2JsdGxYU3h1TzJadmNpaHVJR2x1SUhRcGFXWW9kQzVvWVhOUGQyNVFjbTl3WlhK'
    || 'MGVTaHVLU1ltYmlCcGJpQm9kU2x5WlhSMWNtNGdVR2xiWlYwOWRGdHVYVHR5WlhSMWNtNGdaWDEyWVhJZ2JYVTlTbklvSW1GdWFXMWhkR2x2Ym1WdVpDSXBM'
    || 'SFoxUFVweUtDSmhibWx0WVhScGIyNXBkR1Z5WVhScGIyNGlLU3huZFQxS2NpZ2lZVzVwYldGMGFXOXVjM1JoY25RaUtTeDVkVDFLY2lnaWRISmhibk5wZEds'
    || 'dmJtVnVaQ0lwTEhoMVBXNWxkeUJOWVhBc2QzVTlJbUZpYjNKMElHRjFlRU5zYVdOcklHTmhibU5sYkNCallXNVFiR0Y1SUdOaGJsQnNZWGxVYUhKdmRXZG9J'
    || 'R05zYVdOcklHTnNiM05sSUdOdmJuUmxlSFJOWlc1MUlHTnZjSGtnWTNWMElHUnlZV2NnWkhKaFowVnVaQ0JrY21GblJXNTBaWElnWkhKaFowVjRhWFFnWkhK'
    || 'aFoweGxZWFpsSUdSeVlXZFBkbVZ5SUdSeVlXZFRkR0Z5ZENCa2NtOXdJR1IxY21GMGFXOXVRMmhoYm1kbElHVnRjSFJwWldRZ1pXNWpjbmx3ZEdWa0lHVnVa'
    || 'R1ZrSUdWeWNtOXlJR2R2ZEZCdmFXNTBaWEpEWVhCMGRYSmxJR2x1Y0hWMElHbHVkbUZzYVdRZ2EyVjVSRzkzYmlCclpYbFFjbVZ6Y3lCclpYbFZjQ0JzYjJG'
    || 'a0lHeHZZV1JsWkVSaGRHRWdiRzloWkdWa1RXVjBZV1JoZEdFZ2JHOWhaRk4wWVhKMElHeHZjM1JRYjJsdWRHVnlRMkZ3ZEhWeVpTQnRiM1Z6WlVSdmQyNGdi'
    || 'VzkxYzJWTmIzWmxJRzF2ZFhObFQzVjBJRzF2ZFhObFQzWmxjaUJ0YjNWelpWVndJSEJoYzNSbElIQmhkWE5sSUhCc1lYa2djR3hoZVdsdVp5QndiMmx1ZEdW'
    || 'eVEyRnVZMlZzSUhCdmFXNTBaWEpFYjNkdUlIQnZhVzUwWlhKTmIzWmxJSEJ2YVc1MFpYSlBkWFFnY0c5cGJuUmxjazkyWlhJZ2NHOXBiblJsY2xWd0lIQnli'
    || 'MmR5WlhOeklISmhkR1ZEYUdGdVoyVWdjbVZ6WlhRZ2NtVnphWHBsSUhObFpXdGxaQ0J6WldWcmFXNW5JSE4wWVd4c1pXUWdjM1ZpYldsMElITjFjM0JsYm1R'
    || 'Z2RHbHRaVlZ3WkdGMFpTQjBiM1ZqYUVOaGJtTmxiQ0IwYjNWamFFVnVaQ0IwYjNWamFGTjBZWEowSUhadmJIVnRaVU5vWVc1blpTQnpZM0p2Ykd3Z2RHOW5a'
    || 'MnhsSUhSdmRXTm9UVzkyWlNCM1lXbDBhVzVuSUhkb1pXVnNJaTV6Y0d4cGRDZ2lJQ0lwTzJaMWJtTjBhVzl1SUNSMEtHVXNkQ2w3ZUhVdWMyVjBLR1VzZENr'
    || 'c1F5aDBMRnRsWFNsOVptOXlLSFpoY2lCUGFUMHdPMDlwUEhkMUxteGxibWQwYUR0UGFTc3JLWHQyWVhJZ1NXazlkM1ZiVDJsZExIWm1QVWxwTG5SdlRHOTNa'
    || 'WEpEWVhObEtDa3NaMlk5U1dsYk1GMHVkRzlWY0hCbGNrTmhjMlVvS1N0SmFTNXpiR2xqWlNneEtUc2tkQ2gyWml3aWIyNGlLMmRtS1gwa2RDaHRkU3dpYjI1'
    || 'QmJtbHRZWFJwYjI1RmJtUWlLU3drZENoMmRTd2liMjVCYm1sdFlYUnBiMjVKZEdWeVlYUnBiMjRpS1N3a2RDaG5kU3dpYjI1QmJtbHRZWFJwYjI1VGRHRnlk'
    || 'Q0lwTENSMEtDSmtZbXhqYkdsamF5SXNJbTl1Ukc5MVlteGxRMnhwWTJzaUtTd2tkQ2dpWm05amRYTnBiaUlzSW05dVJtOWpkWE1pS1N3a2RDZ2labTlqZFhO'
    || 'dmRYUWlMQ0p2YmtKc2RYSWlLU3drZENoNWRTd2liMjVVY21GdWMybDBhVzl1Ulc1a0lpa3NlU2dpYjI1TmIzVnpaVVZ1ZEdWeUlpeGJJbTF2ZFhObGIzVjBJ'
    || 'aXdpYlc5MWMyVnZkbVZ5SWwwcExIa29JbTl1VFc5MWMyVk1aV0YyWlNJc1d5SnRiM1Z6Wlc5MWRDSXNJbTF2ZFhObGIzWmxjaUpkS1N4NUtDSnZibEJ2YVc1'
    || 'MFpYSkZiblJsY2lJc1d5SndiMmx1ZEdWeWIzVjBJaXdpY0c5cGJuUmxjbTkyWlhJaVhTa3NlU2dpYjI1UWIybHVkR1Z5VEdWaGRtVWlMRnNpY0c5cGJuUmxj'
    || 'bTkxZENJc0luQnZhVzUwWlhKdmRtVnlJbDBwTEVNb0ltOXVRMmhoYm1kbElpd2lZMmhoYm1kbElHTnNhV05ySUdadlkzVnphVzRnWm05amRYTnZkWFFnYVc1'
    || 'd2RYUWdhMlY1Wkc5M2JpQnJaWGwxY0NCelpXeGxZM1JwYjI1amFHRnVaMlVpTG5Od2JHbDBLQ0lnSWlrcExFTW9JbTl1VTJWc1pXTjBJaXdpWm05amRYTnZk'
    || 'WFFnWTI5dWRHVjRkRzFsYm5VZ1pISmhaMlZ1WkNCbWIyTjFjMmx1SUd0bGVXUnZkMjRnYTJWNWRYQWdiVzkxYzJWa2IzZHVJRzF2ZFhObGRYQWdjMlZzWldO'
    || 'MGFXOXVZMmhoYm1kbElpNXpjR3hwZENnaUlDSXBLU3hES0NKdmJrSmxabTl5WlVsdWNIVjBJaXhiSW1OdmJYQnZjMmwwYVc5dVpXNWtJaXdpYTJWNWNISmxj'
    || 'M01pTENKMFpYaDBTVzV3ZFhRaUxDSndZWE4wWlNKZEtTeERLQ0p2YmtOdmJYQnZjMmwwYVc5dVJXNWtJaXdpWTI5dGNHOXphWFJwYjI1bGJtUWdabTlqZFhO'
    || 'dmRYUWdhMlY1Wkc5M2JpQnJaWGx3Y21WemN5QnJaWGwxY0NCdGIzVnpaV1J2ZDI0aUxuTndiR2wwS0NJZ0lpa3BMRU1vSW05dVEyOXRjRzl6YVhScGIyNVRk'
    || 'R0Z5ZENJc0ltTnZiWEJ2YzJsMGFXOXVjM1JoY25RZ1ptOWpkWE52ZFhRZ2EyVjVaRzkzYmlCclpYbHdjbVZ6Y3lCclpYbDFjQ0J0YjNWelpXUnZkMjRpTG5O'
    || 'd2JHbDBLQ0lnSWlrcExFTW9JbTl1UTI5dGNHOXphWFJwYjI1VmNHUmhkR1VpTENKamIyMXdiM05wZEdsdmJuVndaR0YwWlNCbWIyTjFjMjkxZENCclpYbGti'
    || 'M2R1SUd0bGVYQnlaWE56SUd0bGVYVndJRzF2ZFhObFpHOTNiaUl1YzNCc2FYUW9JaUFpS1NrN2RtRnlJR055UFNKaFltOXlkQ0JqWVc1d2JHRjVJR05oYm5C'
    || 'c1lYbDBhSEp2ZFdkb0lHUjFjbUYwYVc5dVkyaGhibWRsSUdWdGNIUnBaV1FnWlc1amNubHdkR1ZrSUdWdVpHVmtJR1Z5Y205eUlHeHZZV1JsWkdSaGRHRWdi'
    || 'RzloWkdWa2JXVjBZV1JoZEdFZ2JHOWhaSE4wWVhKMElIQmhkWE5sSUhCc1lYa2djR3hoZVdsdVp5QndjbTluY21WemN5QnlZWFJsWTJoaGJtZGxJSEpsYzJs'
    || 'NlpTQnpaV1ZyWldRZ2MyVmxhMmx1WnlCemRHRnNiR1ZrSUhOMWMzQmxibVFnZEdsdFpYVndaR0YwWlNCMmIyeDFiV1ZqYUdGdVoyVWdkMkZwZEdsdVp5SXVj'
    || 'M0JzYVhRb0lpQWlLU3g1WmoxdVpYY2dVMlYwS0NKallXNWpaV3dnWTJ4dmMyVWdhVzUyWVd4cFpDQnNiMkZrSUhOamNtOXNiQ0IwYjJkbmJHVWlMbk53Ykds'
    || 'MEtDSWdJaWt1WTI5dVkyRjBLR055S1NrN1puVnVZM1JwYjI0Z1UzVW9aU3gwTEc0cGUzWmhjaUJ5UFdVdWRIbHdaWHg4SW5WdWEyNXZkMjR0WlhabGJuUWlP'
    || 'MlV1WTNWeWNtVnVkRlJoY21kbGREMXVMRzFrS0hJc2RDeDJiMmxrSURBc1pTa3NaUzVqZFhKeVpXNTBWR0Z5WjJWMFBXNTFiR3g5Wm5WdVkzUnBiMjRnWDNV'
    || 'b1pTeDBLWHQwUFNoMEpqUXBJVDA5TUR0bWIzSW9kbUZ5SUc0OU1EdHVQR1V1YkdWdVozUm9PMjRyS3lsN2RtRnlJSEk5WlZ0dVhTeHNQWEl1WlhabGJuUTdj'
    || 'ajF5TG14cGMzUmxibVZ5Y3p0bE9udDJZWElnYVQxMmIybGtJREE3YVdZb2RDbG1iM0lvZG1GeUlHODljaTVzWlc1bmRHZ3RNVHN3UEQxdk8yOHRMU2w3ZG1G'
    || 'eUlHTTljbHR2WFN4a1BXTXVhVzV6ZEdGdVkyVXNaejFqTG1OMWNuSmxiblJVWVhKblpYUTdhV1lvWXoxakxteHBjM1JsYm1WeUxHUWhQVDFwSmlac0xtbHpV'
    || 'SEp2Y0dGbllYUnBiMjVUZEc5d2NHVmtLQ2twWW5KbFlXc2daVHRUZFNoc0xHTXNaeWtzYVQxa2ZXVnNjMlVnWm05eUtHODlNRHR2UEhJdWJHVnVaM1JvTzI4'
    || 'ckt5bDdhV1lvWXoxeVcyOWRMR1E5WXk1cGJuTjBZVzVqWlN4blBXTXVZM1Z5Y21WdWRGUmhjbWRsZEN4alBXTXViR2x6ZEdWdVpYSXNaQ0U5UFdrbUptd3Vh'
    || 'WE5RY205d1lXZGhkR2x2YmxOMGIzQndaV1FvS1NsaWNtVmhheUJsTzFOMUtHd3NZeXhuS1N4cFBXUjlmWDFwWmloNmNpbDBhSEp2ZHlCbFBXUnBMSHB5UFNF'
    || 'eExHUnBQVzUxYkd3c1pYMW1kVzVqZEdsdmJpQnpaU2hsTEhRcGUzWmhjaUJ1UFhSYlYybGRPMjQ5UFQxMmIybGtJREFtSmlodVBYUmJWMmxkUFc1bGR5QlRa'
    || 'WFFwTzNaaGNpQnlQV1VySWw5ZlluVmlZbXhsSWp0dUxtaGhjeWh5S1h4OEtHdDFLSFFzWlN3eUxDRXhLU3h1TG1Ga1pDaHlLU2w5Wm5WdVkzUnBiMjRnZW1r'
    || 'b1pTeDBMRzRwZTNaaGNpQnlQVEE3ZENZbUtISjhQVFFwTEd0MUtHNHNaU3h5TEhRcGZYWmhjaUJ4Y2owaVgzSmxZV04wVEdsemRHVnVhVzVuSWl0TllYUm9M'
    || 'bkpoYm1SdmJTZ3BMblJ2VTNSeWFXNW5LRE0yS1M1emJHbGpaU2d5S1R0bWRXNWpkR2x2YmlCa2NpaGxLWHRwWmlnaFpWdHhjbDBwZTJWYmNYSmRQU0V3TEhn'
    || 'dVptOXlSV0ZqYUNobWRXNWpkR2x2YmlodUtYdHVJVDA5SW5ObGJHVmpkR2x2Ym1Ob1lXNW5aU0ltSmloNVppNW9ZWE1vYmlsOGZIcHBLRzRzSVRFc1pTa3Nl'
    || 'bWtvYml3aE1DeGxLU2w5S1R0MllYSWdkRDFsTG01dlpHVlVlWEJsUFQwOU9UOWxPbVV1YjNkdVpYSkViMk4xYldWdWREdDBQVDA5Ym5Wc2JIeDhkRnR4Y2wx'
    || 'OGZDaDBXM0Z5WFQwaE1DeDZhU2dpYzJWc1pXTjBhVzl1WTJoaGJtZGxJaXdoTVN4MEtTbDlmV1oxYm1OMGFXOXVJR3QxS0dVc2RDeHVMSElwZTNOM2FYUmph'
    || 'Q2haY3loMEtTbDdZMkZ6WlNBeE9uWmhjaUJzUFUxa08ySnlaV0ZyTzJOaGMyVWdORHBzUFZCa08ySnlaV0ZyTzJSbFptRjFiSFE2YkQxNWFYMXVQV3d1WW1s'
    || 'dVpDaHVkV3hzTEhRc2JpeGxLU3hzUFhadmFXUWdNQ3doWTJsOGZIUWhQVDBpZEc5MVkyaHpkR0Z5ZENJbUpuUWhQVDBpZEc5MVkyaHRiM1psSWlZbWRDRTlQ'
    || 'U0ozYUdWbGJDSjhmQ2hzUFNFd0tTeHlQMndoUFQxMmIybGtJREEvWlM1aFpHUkZkbVZ1ZEV4cGMzUmxibVZ5S0hRc2JpeDdZMkZ3ZEhWeVpUb2hNQ3h3WVhO'
    || 'emFYWmxPbXg5S1RwbExtRmtaRVYyWlc1MFRHbHpkR1Z1WlhJb2RDeHVMQ0V3S1Rwc0lUMDlkbTlwWkNBd1AyVXVZV1JrUlhabGJuUk1hWE4wWlc1bGNpaDBM'
    || 'RzRzZTNCaGMzTnBkbVU2YkgwcE9tVXVZV1JrUlhabGJuUk1hWE4wWlc1bGNpaDBMRzRzSVRFcGZXWjFibU4wYVc5dUlFUnBLR1VzZEN4dUxISXNiQ2w3ZG1G'
    || 'eUlHazljanRwWmlnb2RDWXhLVDA5UFRBbUppaDBKaklwUFQwOU1DWW1jaUU5UFc1MWJHd3BaVHBtYjNJb096c3BlMmxtS0hJOVBUMXVkV3hzS1hKbGRIVnli'
    || 'anQyWVhJZ2J6MXlMblJoWnp0cFppaHZQVDA5TTN4OGJ6MDlQVFFwZTNaaGNpQmpQWEl1YzNSaGRHVk9iMlJsTG1OdmJuUmhhVzVsY2tsdVptODdhV1lvWXow'
    || 'OVBXeDhmR011Ym05a1pWUjVjR1U5UFQwNEppWmpMbkJoY21WdWRFNXZaR1U5UFQxc0tXSnlaV0ZyTzJsbUtHODlQVDAwS1dadmNpaHZQWEl1Y21WMGRYSnVP'
    || 'MjhoUFQxdWRXeHNPeWw3ZG1GeUlHUTlieTUwWVdjN2FXWW9LR1E5UFQwemZIeGtQVDA5TkNrbUppaGtQVzh1YzNSaGRHVk9iMlJsTG1OdmJuUmhhVzVsY2ts'
    || 'dVptOHNaRDA5UFd4OGZHUXVibTlrWlZSNWNHVTlQVDA0Smlaa0xuQmhjbVZ1ZEU1dlpHVTlQVDFzS1NseVpYUjFjbTQ3YnoxdkxuSmxkSFZ5Ym4xbWIzSW9P'
    || 'Mk1oUFQxdWRXeHNPeWw3YVdZb2J6MXliaWhqS1N4dlBUMDliblZzYkNseVpYUjFjbTQ3YVdZb1pEMXZMblJoWnl4a1BUMDlOWHg4WkQwOVBUWXBlM0k5YVQx'
    || 'dk8yTnZiblJwYm5WbElHVjlZejFqTG5CaGNtVnVkRTV2WkdWOWZYSTljaTV5WlhSMWNtNTlRM01vWm5WdVkzUnBiMjRvS1h0MllYSWdaejFwTEVVOWMya29i'
    || 'aWtzYWoxYlhUdGxPbnQyWVhJZ1V6MTRkUzVuWlhRb1pTazdhV1lvVXlFOVBYWnZhV1FnTUNsN2RtRnlJRTA5VTJrc1NUMWxPM04zYVhSamFDaGxLWHRqWVhO'
    || 'bEltdGxlWEJ5WlhOeklqcHBaaWhaY2lodUtUMDlQVEFwWW5KbFlXc2daVHRqWVhObEltdGxlV1J2ZDI0aU9tTmhjMlVpYTJWNWRYQWlPazA5UzJRN1luSmxZ'
    || 'V3M3WTJGelpTSm1iMk4xYzJsdUlqcEpQU0ptYjJOMWN5SXNUVDFGYVR0aWNtVmhhenRqWVhObEltWnZZM1Z6YjNWMElqcEpQU0ppYkhWeUlpeE5QVVZwTzJK'
    || 'eVpXRnJPMk5oYzJVaVltVm1iM0psWW14MWNpSTZZMkZ6WlNKaFpuUmxjbUpzZFhJaU9rMDlSV2s3WW5KbFlXczdZMkZ6WlNKamJHbGpheUk2YVdZb2JpNWlk'
    || 'WFIwYjI0OVBUMHlLV0p5WldGcklHVTdZMkZ6WlNKaGRYaGpiR2xqYXlJNlkyRnpaU0prWW14amJHbGpheUk2WTJGelpTSnRiM1Z6WldSdmQyNGlPbU5oYzJV'
    || 'aWJXOTFjMlZ0YjNabElqcGpZWE5sSW0xdmRYTmxkWEFpT21OaGMyVWliVzkxYzJWdmRYUWlPbU5oYzJVaWJXOTFjMlZ2ZG1WeUlqcGpZWE5sSW1OdmJuUmxl'
    || 'SFJ0Wlc1MUlqcE5QVmh6TzJKeVpXRnJPMk5oYzJVaVpISmhaeUk2WTJGelpTSmtjbUZuWlc1a0lqcGpZWE5sSW1SeVlXZGxiblJsY2lJNlkyRnpaU0prY21G'
    || 'blpYaHBkQ0k2WTJGelpTSmtjbUZuYkdWaGRtVWlPbU5oYzJVaVpISmhaMjkyWlhJaU9tTmhjMlVpWkhKaFozTjBZWEowSWpwallYTmxJbVJ5YjNBaU9rMDll'
    || 'bVE3WW5KbFlXczdZMkZ6WlNKMGIzVmphR05oYm1ObGJDSTZZMkZ6WlNKMGIzVmphR1Z1WkNJNlkyRnpaU0owYjNWamFHMXZkbVVpT21OaGMyVWlkRzkxWTJo'
    || 'emRHRnlkQ0k2VFQxYVpEdGljbVZoYXp0allYTmxJRzExT21OaGMyVWdkblU2WTJGelpTQm5kVHBOUFVaa08ySnlaV0ZyTzJOaGMyVWdlWFU2VFQxeFpEdGlj'
    || 'bVZoYXp0allYTmxJbk5qY205c2JDSTZUVDFQWkR0aWNtVmhhenRqWVhObEluZG9aV1ZzSWpwTlBXVm1PMkp5WldGck8yTmhjMlVpWTI5d2VTSTZZMkZ6WlNK'
    || 'amRYUWlPbU5oYzJVaWNHRnpkR1VpT2swOVNHUTdZbkpsWVdzN1kyRnpaU0puYjNSd2IybHVkR1Z5WTJGd2RIVnlaU0k2WTJGelpTSnNiM04wY0c5cGJuUmxj'
    || 'bU5oY0hSMWNtVWlPbU5oYzJVaWNHOXBiblJsY21OaGJtTmxiQ0k2WTJGelpTSndiMmx1ZEdWeVpHOTNiaUk2WTJGelpTSndiMmx1ZEdWeWJXOTJaU0k2WTJG'
    || 'elpTSndiMmx1ZEdWeWIzVjBJanBqWVhObEluQnZhVzUwWlhKdmRtVnlJanBqWVhObEluQnZhVzUwWlhKMWNDSTZUVDFLYzMxMllYSWdlajBvZENZMEtTRTlQ'
    || 'VEFzWjJVOUlYb21KbVU5UFQwaWMyTnliMnhzSWl4dFBYby9VeUU5UFc1MWJHdy9VeXNpUTJGd2RIVnlaU0k2Ym5Wc2JEcFRPM285VzEwN1ptOXlLSFpoY2lC'
    || 'd1BXY3NkanR3SVQwOWJuVnNiRHNwZTNZOWNEdDJZWElnVkQxMkxuTjBZWFJsVG05a1pUdHBaaWgyTG5SaFp6MDlQVFVtSmxRaFBUMXVkV3hzSmlZb2RqMVVM'
    || 'RzBoUFQxdWRXeHNKaVlvVkQxTGJpaHdMRzBwTEZRaFBXNTFiR3dtSm5vdWNIVnphQ2htY2lod0xGUXNkaWtwS1Nrc1oyVXBZbkpsWVdzN2NEMXdMbkpsZEhW'
    || 'eWJuMHdQSG91YkdWdVozUm9KaVlvVXoxdVpYY2dUU2hUTEVrc2JuVnNiQ3h1TEVVcExHb3VjSFZ6YUNoN1pYWmxiblE2VXl4c2FYTjBaVzVsY25NNmVuMHBL'
    || 'WDE5YVdZb0tIUW1OeWs5UFQwd0tYdGxPbnRwWmloVFBXVTlQVDBpYlc5MWMyVnZkbVZ5SW54OFpUMDlQU0p3YjJsdWRHVnliM1psY2lJc1RUMWxQVDA5SW0x'
    || 'dmRYTmxiM1YwSW54OFpUMDlQU0p3YjJsdWRHVnliM1YwSWl4VEppWnVJVDA5YjJrbUppaEpQVzR1Y21Wc1lYUmxaRlJoY21kbGRIeDhiaTVtY205dFJXeGxi'
    || 'V1Z1ZENrbUppaHliaWhKS1h4OFNWdFVkRjBwS1dKeVpXRnJJR1U3YVdZb0tFMThmRk1wSmlZb1V6MUZMbmRwYm1SdmR6MDlQVVUvUlRvb1V6MUZMbTkzYm1W'
    || 'eVJHOWpkVzFsYm5RcFAxTXVaR1ZtWVhWc2RGWnBaWGQ4ZkZNdWNHRnlaVzUwVjJsdVpHOTNPbmRwYm1SdmR5eE5QeWhKUFc0dWNtVnNZWFJsWkZSaGNtZGxk'
    || 'SHg4Ymk1MGIwVnNaVzFsYm5Rc1RUMW5MRWs5U1Q5eWJpaEpLVHB1ZFd4c0xFa2hQVDF1ZFd4c0ppWW9aMlU5Ym00b1NTa3NTU0U5UFdkbGZIeEpMblJoWnlF'
    || 'OVBUVW1Ka2t1ZEdGbklUMDlOaWttSmloSlBXNTFiR3dwS1Rvb1RUMXVkV3hzTEVrOVp5a3NUU0U5UFVrcEtYdHBaaWg2UFZoekxGUTlJbTl1VFc5MWMyVk1a'
    || 'V0YyWlNJc2JUMGliMjVOYjNWelpVVnVkR1Z5SWl4d1BTSnRiM1Z6WlNJc0tHVTlQVDBpY0c5cGJuUmxjbTkxZENKOGZHVTlQVDBpY0c5cGJuUmxjbTkyWlhJ'
    || 'aUtTWW1LSG85U25Nc1ZEMGliMjVRYjJsdWRHVnlUR1ZoZG1VaUxHMDlJbTl1VUc5cGJuUmxja1Z1ZEdWeUlpeHdQU0p3YjJsdWRHVnlJaWtzWjJVOVRUMDli'
    || 'blZzYkQ5VE9rTnVLRTBwTEhZOVNUMDliblZzYkQ5VE9rTnVLRWtwTEZNOWJtVjNJSG9vVkN4d0t5SnNaV0YyWlNJc1RTeHVMRVVwTEZNdWRHRnlaMlYwUFdk'
    || 'bExGTXVjbVZzWVhSbFpGUmhjbWRsZEQxMkxGUTliblZzYkN4eWJpaEZLVDA5UFdjbUppaDZQVzVsZHlCNktHMHNjQ3NpWlc1MFpYSWlMRWtzYml4RktTeDZM'
    || 'blJoY21kbGREMTJMSG91Y21Wc1lYUmxaRlJoY21kbGREMW5aU3hVUFhvcExHZGxQVlFzVFNZbVNTbDBPbnRtYjNJb2VqMU5MRzA5U1N4d1BUQXNkajE2TzNZ'
    || 'N2RqMXFiaWgyS1Nsd0t5czdabTl5S0hZOU1DeFVQVzA3VkR0VVBXcHVLRlFwS1hZckt6dG1iM0lvT3pBOGNDMTJPeWw2UFdwdUtIb3BMSEF0TFR0bWIzSW9P'
    || 'ekE4ZGkxd095bHRQV3B1S0cwcExIWXRMVHRtYjNJb08zQXRMVHNwZTJsbUtIbzlQVDF0Zkh4dElUMDliblZzYkNZbWVqMDlQVzB1WVd4MFpYSnVZWFJsS1dK'
    || 'eVpXRnJJSFE3ZWoxcWJpaDZLU3h0UFdwdUtHMHBmWG85Ym5Wc2JIMWxiSE5sSUhvOWJuVnNiRHROSVQwOWJuVnNiQ1ltUlhVb2FpeFRMRTBzZWl3aE1Ta3NT'
    || 'U0U5UFc1MWJHd21KbWRsSVQwOWJuVnNiQ1ltUlhVb2FpeG5aU3hKTEhvc0lUQXBmWDFsT250cFppaFRQV2MvUTI0b1p5azZkMmx1Wkc5M0xFMDlVeTV1YjJS'
    || 'bFRtRnRaU1ltVXk1dWIyUmxUbUZ0WlM1MGIweHZkMlZ5UTJGelpTZ3BMRTA5UFQwaWMyVnNaV04wSW54OFRUMDlQU0pwYm5CMWRDSW1KbE11ZEhsd1pUMDlQ'
    || 'U0ptYVd4bElpbDJZWElnUkQxMVpqdGxiSE5sSUdsbUtISjFLRk1wS1dsbUtHbDFLVVE5Wm1ZN1pXeHpaWHRFUFdObU8zWmhjaUJHUFdGbWZXVnNjMlVvVFQx'
    || 'VExtNXZaR1ZPWVcxbEtTWW1UUzUwYjB4dmQyVnlRMkZ6WlNncFBUMDlJbWx1Y0hWMElpWW1LRk11ZEhsd1pUMDlQU0pqYUdWamEySnZlQ0o4ZkZNdWRIbHda'
    || 'VDA5UFNKeVlXUnBieUlwSmlZb1JEMWtaaWs3YVdZb1JDWW1LRVE5UkNobExHY3BLU2w3YkhVb2FpeEVMRzRzUlNrN1luSmxZV3NnWlgxR0ppWkdLR1VzVXl4'
    || 'bktTeGxQVDA5SW1adlkzVnpiM1YwSWlZbUtFWTlVeTVmZDNKaGNIQmxjbE4wWVhSbEtTWW1SaTVqYjI1MGNtOXNiR1ZrSmlaVExuUjVjR1U5UFQwaWJuVnRZ'
    || 'bVZ5SWlZbWRHa29VeXdpYm5WdFltVnlJaXhUTG5aaGJIVmxLWDF6ZDJsMFkyZ29SajFuUDBOdUtHY3BPbmRwYm1SdmR5eGxLWHRqWVhObEltWnZZM1Z6YVc0'
    || 'aU9paHlkU2hHS1h4OFJpNWpiMjUwWlc1MFJXUnBkR0ZpYkdVOVBUMGlkSEoxWlNJcEppWW9SVzQ5Uml4U2FUMW5MR0Z5UFc1MWJHd3BPMkp5WldGck8yTmhj'
    || 'MlVpWm05amRYTnZkWFFpT21GeVBWSnBQVVZ1UFc1MWJHdzdZbkpsWVdzN1kyRnpaU0p0YjNWelpXUnZkMjRpT2sxcFBTRXdPMkp5WldGck8yTmhjMlVpWTI5'
    || 'dWRHVjRkRzFsYm5VaU9tTmhjMlVpYlc5MWMyVjFjQ0k2WTJGelpTSmtjbUZuWlc1a0lqcE5hVDBoTVN4d2RTaHFMRzRzUlNrN1luSmxZV3M3WTJGelpTSnpa'
    || 'V3hsWTNScGIyNWphR0Z1WjJVaU9tbG1LRzFtS1dKeVpXRnJPMk5oYzJVaWEyVjVaRzkzYmlJNlkyRnpaU0pyWlhsMWNDSTZjSFVvYWl4dUxFVXBmWFpoY2lC'
    || 'Vk8ybG1LR3BwS1dVNmUzTjNhWFJqYUNobEtYdGpZWE5sSW1OdmJYQnZjMmwwYVc5dWMzUmhjblFpT25aaGNpQlhQU0p2YmtOdmJYQnZjMmwwYVc5dVUzUmhj'
    || 'blFpTzJKeVpXRnJJR1U3WTJGelpTSmpiMjF3YjNOcGRHbHZibVZ1WkNJNlZ6MGliMjVEYjIxd2IzTnBkR2x2YmtWdVpDSTdZbkpsWVdzZ1pUdGpZWE5sSW1O'
    || 'dmJYQnZjMmwwYVc5dWRYQmtZWFJsSWpwWFBTSnZia052YlhCdmMybDBhVzl1VlhCa1lYUmxJanRpY21WaGF5QmxmVmM5ZG05cFpDQXdmV1ZzYzJVZ2EyNC9k'
    || 'SFVvWlN4dUtTWW1LRmM5SW05dVEyOXRjRzl6YVhScGIyNUZibVFpS1RwbFBUMDlJbXRsZVdSdmQyNGlKaVp1TG10bGVVTnZaR1U5UFQweU1qa21KaWhYUFNK'
    || 'dmJrTnZiWEJ2YzJsMGFXOXVVM1JoY25RaUtUdFhKaVlvY1hNbUptNHViRzlqWVd4bElUMDlJbXR2SWlZbUtHdHVmSHhYSVQwOUltOXVRMjl0Y0c5emFYUnBi'
    || 'MjVUZEdGeWRDSS9WejA5UFNKdmJrTnZiWEJ2YzJsMGFXOXVSVzVrSWlZbWEyNG1KaWhWUFV0ektDa3BPaWhJZEQxRkxIZHBQU0oyWVd4MVpTSnBiaUJJZEQ5'
    || 'SWRDNTJZV3gxWlRwSWRDNTBaWGgwUTI5dWRHVnVkQ3hyYmowaE1Da3BMRVk5WW5Jb1p5eFhLU3d3UEVZdWJHVnVaM1JvSmlZb1Z6MXVaWGNnV25Nb1Z5eGxM'
    || 'RzUxYkd3c2JpeEZLU3hxTG5CMWMyZ29lMlYyWlc1ME9sY3NiR2x6ZEdWdVpYSnpPa1o5S1N4VlAxY3VaR0YwWVQxVk9paFZQVzUxS0c0cExGVWhQVDF1ZFd4'
    || 'c0ppWW9WeTVrWVhSaFBWVXBLU2twTENoVlBXNW1QM0ptS0dVc2JpazZiR1lvWlN4dUtTa21KaWhuUFdKeUtHY3NJbTl1UW1WbWIzSmxTVzV3ZFhRaUtTd3dQ'
    || 'R2N1YkdWdVozUm9KaVlvUlQxdVpYY2dXbk1vSW05dVFtVm1iM0psU1c1d2RYUWlMQ0ppWldadmNtVnBibkIxZENJc2JuVnNiQ3h1TEVVcExHb3VjSFZ6YUNo'
    || 'N1pYWmxiblE2UlN4c2FYTjBaVzVsY25NNlozMHBMRVV1WkdGMFlUMVZLU2w5WDNVb2FpeDBLWDBwZldaMWJtTjBhVzl1SUdaeUtHVXNkQ3h1S1h0eVpYUjFj'
    || 'bTU3YVc1emRHRnVZMlU2WlN4c2FYTjBaVzVsY2pwMExHTjFjbkpsYm5SVVlYSm5aWFE2Ym4xOVpuVnVZM1JwYjI0Z1luSW9aU3gwS1h0bWIzSW9kbUZ5SUc0'
    || 'OWRDc2lRMkZ3ZEhWeVpTSXNjajFiWFR0bElUMDliblZzYkRzcGUzWmhjaUJzUFdVc2FUMXNMbk4wWVhSbFRtOWtaVHRzTG5SaFp6MDlQVFVtSm1raFBUMXVk'
    || 'V3hzSmlZb2JEMXBMR2s5UzI0b1pTeHVLU3hwSVQxdWRXeHNKaVp5TG5WdWMyaHBablFvWm5Jb1pTeHBMR3dwS1N4cFBVdHVLR1VzZENrc2FTRTliblZzYkNZ'
    || 'bWNpNXdkWE5vS0daeUtHVXNhU3hzS1NrcExHVTlaUzV5WlhSMWNtNTljbVYwZFhKdUlISjlablZ1WTNScGIyNGdhbTRvWlNsN2FXWW9aVDA5UFc1MWJHd3Bj'
    || 'bVYwZFhKdUlHNTFiR3c3Wkc4Z1pUMWxMbkpsZEhWeWJqdDNhR2xzWlNobEppWmxMblJoWnlFOVBUVXBPM0psZEhWeWJpQmxmSHh1ZFd4c2ZXWjFibU4wYVc5'
    || 'dUlFVjFLR1VzZEN4dUxISXNiQ2w3Wm05eUtIWmhjaUJwUFhRdVgzSmxZV04wVG1GdFpTeHZQVnRkTzI0aFBUMXVkV3hzSmladUlUMDljanNwZTNaaGNpQmpQ'
    || 'VzRzWkQxakxtRnNkR1Z5Ym1GMFpTeG5QV011YzNSaGRHVk9iMlJsTzJsbUtHUWhQVDF1ZFd4c0ppWmtQVDA5Y2lsaWNtVmhhenRqTG5SaFp6MDlQVFVtSm1j'
    || 'aFBUMXVkV3hzSmlZb1l6MW5MR3cvS0dROVMyNG9iaXhwS1N4a0lUMXVkV3hzSmladkxuVnVjMmhwWm5Rb1puSW9iaXhrTEdNcEtTazZiSHg4S0dROVMyNG9i'
    || 'aXhwS1N4a0lUMXVkV3hzSmladkxuQjFjMmdvWm5Jb2JpeGtMR01wS1NrcExHNDliaTV5WlhSMWNtNTlieTVzWlc1bmRHZ2hQVDB3SmlabExuQjFjMmdvZTJW'
    || 'MlpXNTBPblFzYkdsemRHVnVaWEp6T205OUtYMTJZWElnZUdZOUwxeHlYRzQvTDJjc2QyWTlMMXgxTURBd01IeGNkVVpHUmtRdlp6dG1kVzVqZEdsdmJpQk9k'
    || 'U2hsS1h0eVpYUjFjbTRvZEhsd1pXOW1JR1U5UFNKemRISnBibWNpUDJVNklpSXJaU2t1Y21Wd2JHRmpaU2g0Wml4Z0NtQXBMbkpsY0d4aFkyVW9kMllzSWlJ'
    || 'cGZXWjFibU4wYVc5dUlHVnNLR1VzZEN4dUtYdHBaaWgwUFU1MUtIUXBMRTUxS0dVcElUMDlkQ1ltYmlsMGFISnZkeUJGY25KdmNpaGhLRFF5TlNrcGZXWjFi'
    || 'bU4wYVc5dUlIUnNLQ2w3ZlhaaGNpQkJhVDF1ZFd4c0xFWnBQVzUxYkd3N1puVnVZM1JwYjI0Z1ZXa29aU3gwS1h0eVpYUjFjbTRnWlQwOVBTSjBaWGgwWVhK'
    || 'bFlTSjhmR1U5UFQwaWJtOXpZM0pwY0hRaWZIeDBlWEJsYjJZZ2RDNWphR2xzWkhKbGJqMDlJbk4wY21sdVp5SjhmSFI1Y0dWdlppQjBMbU5vYVd4a2NtVnVQ'
    || 'VDBpYm5WdFltVnlJbng4ZEhsd1pXOW1JSFF1WkdGdVoyVnliM1Z6YkhsVFpYUkpibTVsY2toVVRVdzlQU0p2WW1wbFkzUWlKaVowTG1SaGJtZGxjbTkxYzJ4'
    || 'NVUyVjBTVzV1WlhKSVZFMU1JVDA5Ym5Wc2JDWW1kQzVrWVc1blpYSnZkWE5zZVZObGRFbHVibVZ5U0ZSTlRDNWZYMmgwYld3aFBXNTFiR3g5ZG1GeUlFaHBQ'
    || 'WFI1Y0dWdlppQnpaWFJVYVcxbGIzVjBQVDBpWm5WdVkzUnBiMjRpUDNObGRGUnBiV1Z2ZFhRNmRtOXBaQ0F3TEZObVBYUjVjR1Z2WmlCamJHVmhjbFJwYldW'
    || 'dmRYUTlQU0ptZFc1amRHbHZiaUkvWTJ4bFlYSlVhVzFsYjNWME9uWnZhV1FnTUN4cWRUMTBlWEJsYjJZZ1VISnZiV2x6WlQwOUltWjFibU4wYVc5dUlqOVFj'
    || 'bTl0YVhObE9uWnZhV1FnTUN4ZlpqMTBlWEJsYjJZZ2NYVmxkV1ZOYVdOeWIzUmhjMnM5UFNKbWRXNWpkR2x2YmlJL2NYVmxkV1ZOYVdOeWIzUmhjMnM2ZEhs'
    || 'd1pXOW1JR3AxUENKMUlqOW1kVzVqZEdsdmJpaGxLWHR5WlhSMWNtNGdhblV1Y21WemIyeDJaU2h1ZFd4c0tTNTBhR1Z1S0dVcExtTmhkR05vS0d0bUtYMDZT'
    || 'R2s3Wm5WdVkzUnBiMjRnYTJZb1pTbDdjMlYwVkdsdFpXOTFkQ2htZFc1amRHbHZiaWdwZTNSb2NtOTNJR1Y5S1gxbWRXNWpkR2x2YmlBa2FTaGxMSFFwZTNa'
    || 'aGNpQnVQWFFzY2owd08yUnZlM1poY2lCc1BXNHVibVY0ZEZOcFlteHBibWM3YVdZb1pTNXlaVzF2ZG1WRGFHbHNaQ2h1S1N4c0ppWnNMbTV2WkdWVWVYQmxQ'
    || 'VDA5T0NscFppaHVQV3d1WkdGMFlTeHVQVDA5SWk4a0lpbDdhV1lvY2owOVBUQXBlMlV1Y21WdGIzWmxRMmhwYkdRb2JDa3NibklvZENrN2NtVjBkWEp1ZlhJ'
    || 'dExYMWxiSE5sSUc0aFBUMGlKQ0ltSm00aFBUMGlKRDhpSmladUlUMDlJaVFoSW54OGNpc3JPMjQ5YkgxM2FHbHNaU2h1S1R0dWNpaDBLWDFtZFc1amRHbHZi'
    || 'aUJYZENobEtYdG1iM0lvTzJVaFBXNTFiR3c3WlQxbExtNWxlSFJUYVdKc2FXNW5LWHQyWVhJZ2REMWxMbTV2WkdWVWVYQmxPMmxtS0hROVBUMHhmSHgwUFQw'
    || 'OU15bGljbVZoYXp0cFppaDBQVDA5T0NsN2FXWW9kRDFsTG1SaGRHRXNkRDA5UFNJa0lueDhkRDA5UFNJa0lTSjhmSFE5UFQwaUpEOGlLV0p5WldGck8ybG1L'
    || 'SFE5UFQwaUx5UWlLWEpsZEhWeWJpQnVkV3hzZlgxeVpYUjFjbTRnWlgxbWRXNWpkR2x2YmlCVWRTaGxLWHRsUFdVdWNISmxkbWx2ZFhOVGFXSnNhVzVuTzJa'
    || 'dmNpaDJZWElnZEQwd08yVTdLWHRwWmlobExtNXZaR1ZVZVhCbFBUMDlPQ2w3ZG1GeUlHNDlaUzVrWVhSaE8ybG1LRzQ5UFQwaUpDSjhmRzQ5UFQwaUpDRWlm'
    || 'SHh1UFQwOUlpUS9JaWw3YVdZb2REMDlQVEFwY21WMGRYSnVJR1U3ZEMwdGZXVnNjMlVnYmowOVBTSXZKQ0ltSm5RckszMWxQV1V1Y0hKbGRtbHZkWE5UYVdK'
    || 'c2FXNW5mWEpsZEhWeWJpQnVkV3hzZlhaaGNpQlViajFOWVhSb0xuSmhibVJ2YlNncExuUnZVM1J5YVc1bktETTJLUzV6YkdsalpTZ3lLU3hUZEQwaVgxOXla'
    || 'V0ZqZEVacFltVnlKQ0lyVkc0c2NISTlJbDlmY21WaFkzUlFjbTl3Y3lRaUsxUnVMRlIwUFNKZlgzSmxZV04wUTI5dWRHRnBibVZ5SkNJclZHNHNWMms5SWw5'
    || 'ZmNtVmhZM1JGZG1WdWRITWtJaXRVYml4RlpqMGlYMTl5WldGamRFeHBjM1JsYm1WeWN5UWlLMVJ1TEU1bVBTSmZYM0psWVdOMFNHRnVaR3hsY3lRaUsxUnVP'
    || 'MloxYm1OMGFXOXVJSEp1S0dVcGUzWmhjaUIwUFdWYlUzUmRPMmxtS0hRcGNtVjBkWEp1SUhRN1ptOXlLSFpoY2lCdVBXVXVjR0Z5Wlc1MFRtOWtaVHR1T3ls'
    || 'N2FXWW9kRDF1VzFSMFhYeDhibHRUZEYwcGUybG1LRzQ5ZEM1aGJIUmxjbTVoZEdVc2RDNWphR2xzWkNFOVBXNTFiR3g4Zkc0aFBUMXVkV3hzSmladUxtTm9h'
    || 'V3hrSVQwOWJuVnNiQ2xtYjNJb1pUMVVkU2hsS1R0bElUMDliblZzYkRzcGUybG1LRzQ5WlZ0VGRGMHBjbVYwZFhKdUlHNDdaVDFVZFNobEtYMXlaWFIxY200'
    || 'Z2RIMWxQVzRzYmoxbExuQmhjbVZ1ZEU1dlpHVjljbVYwZFhKdUlHNTFiR3g5Wm5WdVkzUnBiMjRnYUhJb1pTbDdjbVYwZFhKdUlHVTlaVnRUZEYxOGZHVmJW'
    || 'SFJkTENGbGZIeGxMblJoWnlFOVBUVW1KbVV1ZEdGbklUMDlOaVltWlM1MFlXY2hQVDB4TXlZbVpTNTBZV2NoUFQwelAyNTFiR3c2WlgxbWRXNWpkR2x2YmlC'
    || 'RGJpaGxLWHRwWmlobExuUmhaejA5UFRWOGZHVXVkR0ZuUFQwOU5pbHlaWFIxY200Z1pTNXpkR0YwWlU1dlpHVTdkR2h5YjNjZ1JYSnliM0lvWVNnek15a3Bm'
    || 'V1oxYm1OMGFXOXVJRzVzS0dVcGUzSmxkSFZ5YmlCbFczQnlYWHg4Ym5Wc2JIMTJZWElnVm1rOVcxMHNURzQ5TFRFN1puVnVZM1JwYjI0Z1ZuUW9aU2w3Y21W'
    || 'MGRYSnVlMk4xY25KbGJuUTZaWDE5Wm5WdVkzUnBiMjRnZFdVb1pTbDdNRDVNYm54OEtHVXVZM1Z5Y21WdWREMVdhVnRNYmwwc1ZtbGJURzVkUFc1MWJHd3NU'
    || 'RzR0TFNsOVpuVnVZM1JwYjI0Z2FXVW9aU3gwS1h0TWJpc3JMRlpwVzB4dVhUMWxMbU4xY25KbGJuUXNaUzVqZFhKeVpXNTBQWFI5ZG1GeUlFSjBQWHQ5TEZK'
    || 'bFBWWjBLRUowS1N3a1pUMVdkQ2doTVNrc2JHNDlRblE3Wm5WdVkzUnBiMjRnVW00b1pTeDBLWHQyWVhJZ2JqMWxMblI1Y0dVdVkyOXVkR1Y0ZEZSNWNHVnpP'
    || 'MmxtS0NGdUtYSmxkSFZ5YmlCQ2REdDJZWElnY2oxbExuTjBZWFJsVG05a1pUdHBaaWh5SmlaeUxsOWZjbVZoWTNSSmJuUmxjbTVoYkUxbGJXOXBlbVZrVlc1'
    || 'dFlYTnJaV1JEYUdsc1pFTnZiblJsZUhROVBUMTBLWEpsZEhWeWJpQnlMbDlmY21WaFkzUkpiblJsY201aGJFMWxiVzlwZW1Wa1RXRnphMlZrUTJocGJHUkRi'
    || 'MjUwWlhoME8zWmhjaUJzUFh0OUxHazdabTl5S0drZ2FXNGdiaWxzVzJsZFBYUmJhVjA3Y21WMGRYSnVJSEltSmlobFBXVXVjM1JoZEdWT2IyUmxMR1V1WDE5'
    || 'eVpXRmpkRWx1ZEdWeWJtRnNUV1Z0YjJsNlpXUlZibTFoYzJ0bFpFTm9hV3hrUTI5dWRHVjRkRDEwTEdVdVgxOXlaV0ZqZEVsdWRHVnlibUZzVFdWdGIybDZa'
    || 'V1JOWVhOclpXUkRhR2xzWkVOdmJuUmxlSFE5YkNrc2JIMW1kVzVqZEdsdmJpQlhaU2hsS1h0eVpYUjFjbTRnWlQxbExtTm9hV3hrUTI5dWRHVjRkRlI1Y0dW'
    || 'ekxHVWhQVzUxYkd4OVpuVnVZM1JwYjI0Z2Ntd29LWHQxWlNna1pTa3NkV1VvVW1VcGZXWjFibU4wYVc5dUlFTjFLR1VzZEN4dUtYdHBaaWhTWlM1amRYSnla'
    || 'VzUwSVQwOVFuUXBkR2h5YjNjZ1JYSnliM0lvWVNneE5qZ3BLVHRwWlNoU1pTeDBLU3hwWlNna1pTeHVLWDFtZFc1amRHbHZiaUJNZFNobExIUXNiaWw3ZG1G'
    || 'eUlISTlaUzV6ZEdGMFpVNXZaR1U3YVdZb2REMTBMbU5vYVd4a1EyOXVkR1Y0ZEZSNWNHVnpMSFI1Y0dWdlppQnlMbWRsZEVOb2FXeGtRMjl1ZEdWNGRDRTlJ'
    || 'bVoxYm1OMGFXOXVJaWx5WlhSMWNtNGdianR5UFhJdVoyVjBRMmhwYkdSRGIyNTBaWGgwS0NrN1ptOXlLSFpoY2lCc0lHbHVJSElwYVdZb0lTaHNJR2x1SUhR'
    || 'cEtYUm9jbTkzSUVWeWNtOXlLR0VvTVRBNExHeGxLR1VwZkh3aVZXNXJibTkzYmlJc2JDa3BPM0psZEhWeWJpQlBLSHQ5TEc0c2NpbDlablZ1WTNScGIyNGdi'
    || 'R3dvWlNsN2NtVjBkWEp1SUdVOUtHVTlaUzV6ZEdGMFpVNXZaR1VwSmlabExsOWZjbVZoWTNSSmJuUmxjbTVoYkUxbGJXOXBlbVZrVFdWeVoyVmtRMmhwYkdS'
    || 'RGIyNTBaWGgwZkh4Q2RDeHNiajFTWlM1amRYSnlaVzUwTEdsbEtGSmxMR1VwTEdsbEtDUmxMQ1JsTG1OMWNuSmxiblFwTENFd2ZXWjFibU4wYVc5dUlGSjFL'
    || 'R1VzZEN4dUtYdDJZWElnY2oxbExuTjBZWFJsVG05a1pUdHBaaWdoY2lsMGFISnZkeUJGY25KdmNpaGhLREUyT1NrcE8yNC9LR1U5VEhVb1pTeDBMR3h1S1N4'
    || 'eUxsOWZjbVZoWTNSSmJuUmxjbTVoYkUxbGJXOXBlbVZrVFdWeVoyVmtRMmhwYkdSRGIyNTBaWGgwUFdVc2RXVW9KR1VwTEhWbEtGSmxLU3hwWlNoU1pTeGxL'
    || 'U2s2ZFdVb0pHVXBMR2xsS0NSbExHNHBmWFpoY2lCRGREMXVkV3hzTEdsc1BTRXhMRUpwUFNFeE8yWjFibU4wYVc5dUlFMTFLR1VwZTBOMFBUMDliblZzYkQ5'
    || 'RGREMWJaVjA2UTNRdWNIVnphQ2hsS1gxbWRXNWpkR2x2YmlCcVppaGxLWHRwYkQwaE1DeE5kU2hsS1gxbWRXNWpkR2x2YmlCUmRDZ3BlMmxtS0NGQ2FTWW1R'
    || 'M1FoUFQxdWRXeHNLWHRDYVQwaE1EdDJZWElnWlQwd0xIUTlibVU3ZEhKNWUzWmhjaUJ1UFVOME8yWnZjaWh1WlQweE8yVThiaTVzWlc1bmRHZzdaU3NyS1h0'
    || 'MllYSWdjajF1VzJWZE8yUnZJSEk5Y2lnaE1DazdkMmhwYkdVb2NpRTlQVzUxYkd3cGZVTjBQVzUxYkd3c2FXdzlJVEY5WTJGMFkyZ29iQ2w3ZEdoeWIzY2dR'
    || 'M1FoUFQxdWRXeHNKaVlvUTNROVEzUXVjMnhwWTJVb1pTc3hLU2tzVDNNb1pta3NVWFFwTEd4OVptbHVZV3hzZVh0dVpUMTBMRUpwUFNFeGZYMXlaWFIxY200'
    || 'Z2JuVnNiSDEyWVhJZ1RXNDlXMTBzVUc0OU1DeHZiRDF1ZFd4c0xITnNQVEFzYm5ROVcxMHNjblE5TUN4dmJqMXVkV3hzTEV4MFBURXNVblE5SWlJN1puVnVZ'
    || 'M1JwYjI0Z2MyNG9aU3gwS1h0TmJsdFFiaXNyWFQxemJDeE5ibHRRYmlzclhUMXZiQ3h2YkQxbExITnNQWFI5Wm5WdVkzUnBiMjRnVUhVb1pTeDBMRzRwZTI1'
    || 'MFczSjBLeXRkUFV4MExHNTBXM0owS3l0ZFBWSjBMRzUwVzNKMEt5dGRQVzl1TEc5dVBXVTdkbUZ5SUhJOVRIUTdaVDFTZER0MllYSWdiRDB6TWkxamRDaHlL'
    || 'UzB4TzNJbVBYNG9NVHc4YkNrc2JpczlNVHQyWVhJZ2FUMHpNaTFqZENoMEtTdHNPMmxtS0RNd1BHa3BlM1poY2lCdlBXd3RiQ1UxTzJrOUtISW1LREU4UEc4'
    || 'cExURXBMblJ2VTNSeWFXNW5LRE15S1N4eVBqNDlieXhzTFQxdkxFeDBQVEU4UERNeUxXTjBLSFFwSzJ4OGJqdzhiSHh5TEZKMFBXa3JaWDFsYkhObElFeDBQ'
    || 'VEU4UEdsOGJqdzhiSHh5TEZKMFBXVjlablZ1WTNScGIyNGdVV2tvWlNsN1pTNXlaWFIxY200aFBUMXVkV3hzSmlZb2MyNG9aU3d4S1N4UWRTaGxMREVzTUNr'
    || 'cGZXWjFibU4wYVc5dUlGbHBLR1VwZTJadmNpZzdaVDA5UFc5c095bHZiRDFOYmxzdExWQnVYU3hOYmx0UWJsMDliblZzYkN4emJEMU5ibHN0TFZCdVhTeE5i'
    || 'bHRRYmwwOWJuVnNiRHRtYjNJb08yVTlQVDF2YmpzcGIyNDliblJiTFMxeWRGMHNiblJiY25SZFBXNTFiR3dzVW5ROWJuUmJMUzF5ZEYwc2JuUmJjblJkUFc1'
    || 'MWJHd3NUSFE5Ym5SYkxTMXlkRjBzYm5SYmNuUmRQVzUxYkd4OWRtRnlJRnBsUFc1MWJHd3NTbVU5Ym5Wc2JDeGpaVDBoTVN4bWREMXVkV3hzTzJaMWJtTjBh'
    || 'Vzl1SUU5MUtHVXNkQ2w3ZG1GeUlHNDljM1FvTlN4dWRXeHNMRzUxYkd3c01DazdiaTVsYkdWdFpXNTBWSGx3WlQwaVJFVk1SVlJGUkNJc2JpNXpkR0YwWlU1'
    || 'dlpHVTlkQ3h1TG5KbGRIVnliajFsTEhROVpTNWtaV3hsZEdsdmJuTXNkRDA5UFc1MWJHdy9LR1V1WkdWc1pYUnBiMjV6UFZ0dVhTeGxMbVpzWVdkemZEMHhO'
    || 'aWs2ZEM1d2RYTm9LRzRwZldaMWJtTjBhVzl1SUVsMUtHVXNkQ2w3YzNkcGRHTm9LR1V1ZEdGbktYdGpZWE5sSURVNmRtRnlJRzQ5WlM1MGVYQmxPM0psZEhW'
    || 'eWJpQjBQWFF1Ym05a1pWUjVjR1VoUFQweGZIeHVMblJ2VEc5M1pYSkRZWE5sS0NraFBUMTBMbTV2WkdWT1lXMWxMblJ2VEc5M1pYSkRZWE5sS0NrL2JuVnNi'
    || 'RHAwTEhRaFBUMXVkV3hzUHlobExuTjBZWFJsVG05a1pUMTBMRnBsUFdVc1NtVTlWM1FvZEM1bWFYSnpkRU5vYVd4a0tTd2hNQ2s2SVRFN1kyRnpaU0EyT25K'
    || 'bGRIVnliaUIwUFdVdWNHVnVaR2x1WjFCeWIzQnpQVDA5SWlKOGZIUXVibTlrWlZSNWNHVWhQVDB6UDI1MWJHdzZkQ3gwSVQwOWJuVnNiRDhvWlM1emRHRjBa'
    || 'VTV2WkdVOWRDeGFaVDFsTEVwbFBXNTFiR3dzSVRBcE9pRXhPMk5oYzJVZ01UTTZjbVYwZFhKdUlIUTlkQzV1YjJSbFZIbHdaU0U5UFRnL2JuVnNiRHAwTEhR'
    || 'aFBUMXVkV3hzUHlodVBXOXVJVDA5Ym5Wc2JEOTdhV1E2VEhRc2IzWmxjbVpzYjNjNlVuUjlPbTUxYkd3c1pTNXRaVzF2YVhwbFpGTjBZWFJsUFh0a1pXaDVa'
    || 'SEpoZEdWa09uUXNkSEpsWlVOdmJuUmxlSFE2Yml4eVpYUnllVXhoYm1VNk1UQTNNemMwTVRneU5IMHNiajF6ZENneE9DeHVkV3hzTEc1MWJHd3NNQ2tzYmk1'
    || 'emRHRjBaVTV2WkdVOWRDeHVMbkpsZEhWeWJqMWxMR1V1WTJocGJHUTliaXhhWlQxbExFcGxQVzUxYkd3c0lUQXBPaUV4TzJSbFptRjFiSFE2Y21WMGRYSnVJ'
    || 'VEY5ZldaMWJtTjBhVzl1SUV0cEtHVXBlM0psZEhWeWJpaGxMbTF2WkdVbU1Ta2hQVDB3SmlZb1pTNW1iR0ZuY3lZeE1qZ3BQVDA5TUgxbWRXNWpkR2x2YmlC'
    || 'SGFTaGxLWHRwWmloalpTbDdkbUZ5SUhROVNtVTdhV1lvZENsN2RtRnlJRzQ5ZER0cFppZ2hTWFVvWlN4MEtTbDdhV1lvUzJrb1pTa3BkR2h5YjNjZ1JYSnli'
    || 'M0lvWVNnME1UZ3BLVHQwUFZkMEtHNHVibVY0ZEZOcFlteHBibWNwTzNaaGNpQnlQVnBsTzNRbUprbDFLR1VzZENrL1QzVW9jaXh1S1Rvb1pTNW1iR0ZuY3ox'
    || 'bExtWnNZV2R6SmkwME1EazNmRElzWTJVOUlURXNXbVU5WlNsOWZXVnNjMlY3YVdZb1Mya29aU2twZEdoeWIzY2dSWEp5YjNJb1lTZzBNVGdwS1R0bExtWnNZ'
    || 'V2R6UFdVdVpteGhaM01tTFRRd09UZDhNaXhqWlQwaE1TeGFaVDFsZlgxOVpuVnVZM1JwYjI0Z2VuVW9aU2w3Wm05eUtHVTlaUzV5WlhSMWNtNDdaU0U5UFc1'
    || 'MWJHd21KbVV1ZEdGbklUMDlOU1ltWlM1MFlXY2hQVDB6SmlabExuUmhaeUU5UFRFek95bGxQV1V1Y21WMGRYSnVPMXBsUFdWOVpuVnVZM1JwYjI0Z2RXd29a'
    || 'U2w3YVdZb1pTRTlQVnBsS1hKbGRIVnliaUV4TzJsbUtDRmpaU2x5WlhSMWNtNGdlblVvWlNrc1kyVTlJVEFzSVRFN2RtRnlJSFE3YVdZb0tIUTlaUzUwWVdj'
    || 'aFBUMHpLU1ltSVNoMFBXVXVkR0ZuSVQwOU5Ta21KaWgwUFdVdWRIbHdaU3gwUFhRaFBUMGlhR1ZoWkNJbUpuUWhQVDBpWW05a2VTSW1KaUZWYVNobExuUjVj'
    || 'R1VzWlM1dFpXMXZhWHBsWkZCeWIzQnpLU2tzZENZbUtIUTlTbVVwS1h0cFppaExhU2hsS1NsMGFISnZkeUJFZFNncExFVnljbTl5S0dFb05ERTRLU2s3Wm05'
    || 'eUtEdDBPeWxQZFNobExIUXBMSFE5VjNRb2RDNXVaWGgwVTJsaWJHbHVaeWw5YVdZb2VuVW9aU2tzWlM1MFlXYzlQVDB4TXlsN2FXWW9aVDFsTG0xbGJXOXBl'
    || 'bVZrVTNSaGRHVXNaVDFsSVQwOWJuVnNiRDlsTG1SbGFIbGtjbUYwWldRNmJuVnNiQ3doWlNsMGFISnZkeUJGY25KdmNpaGhLRE14TnlrcE8yVTZlMlp2Y2lo'
    || 'bFBXVXVibVY0ZEZOcFlteHBibWNzZEQwd08yVTdLWHRwWmlobExtNXZaR1ZVZVhCbFBUMDlPQ2w3ZG1GeUlHNDlaUzVrWVhSaE8ybG1LRzQ5UFQwaUx5UWlL'
    || 'WHRwWmloMFBUMDlNQ2w3U21VOVYzUW9aUzV1WlhoMFUybGliR2x1WnlrN1luSmxZV3NnWlgxMExTMTlaV3h6WlNCdUlUMDlJaVFpSmladUlUMDlJaVFoSWlZ'
    || 'bWJpRTlQU0lrUHlKOGZIUXJLMzFsUFdVdWJtVjRkRk5wWW14cGJtZDlTbVU5Ym5Wc2JIMTlaV3h6WlNCS1pUMWFaVDlYZENobExuTjBZWFJsVG05a1pTNXVa'
    || 'WGgwVTJsaWJHbHVaeWs2Ym5Wc2JEdHlaWFIxY200aE1IMW1kVzVqZEdsdmJpQkVkU2dwZTJadmNpaDJZWElnWlQxS1pUdGxPeWxsUFZkMEtHVXVibVY0ZEZO'
    || 'cFlteHBibWNwZldaMWJtTjBhVzl1SUU5dUtDbDdTbVU5V21VOWJuVnNiQ3hqWlQwaE1YMW1kVzVqZEdsdmJpQllhU2hsS1h0bWREMDlQVzUxYkd3L1puUTlX'
    || 'MlZkT21aMExuQjFjMmdvWlNsOWRtRnlJRlJtUFc5bExsSmxZV04wUTNWeWNtVnVkRUpoZEdOb1EyOXVabWxuTzJaMWJtTjBhVzl1SUcxeUtHVXNkQ3h1S1h0'
    || 'cFppaGxQVzR1Y21WbUxHVWhQVDF1ZFd4c0ppWjBlWEJsYjJZZ1pTRTlJbVoxYm1OMGFXOXVJaVltZEhsd1pXOW1JR1VoUFNKdlltcGxZM1FpS1h0cFppaHVM'
    || 'bDl2ZDI1bGNpbDdhV1lvYmoxdUxsOXZkMjVsY2l4dUtYdHBaaWh1TG5SaFp5RTlQVEVwZEdoeWIzY2dSWEp5YjNJb1lTZ3pNRGtwS1R0MllYSWdjajF1TG5O'
    || 'MFlYUmxUbTlrWlgxcFppZ2hjaWwwYUhKdmR5QkZjbkp2Y2loaEtERTBOeXhsS1NrN2RtRnlJR3c5Y2l4cFBTSWlLMlU3Y21WMGRYSnVJSFFoUFQxdWRXeHNK'
    || 'aVowTG5KbFppRTlQVzUxYkd3bUpuUjVjR1Z2WmlCMExuSmxaajA5SW1aMWJtTjBhVzl1SWlZbWRDNXlaV1l1WDNOMGNtbHVaMUpsWmowOVBXay9kQzV5WldZ'
    || 'NktIUTlablZ1WTNScGIyNG9ieWw3ZG1GeUlHTTliQzV5Wldaek8yODlQVDF1ZFd4c1AyUmxiR1YwWlNCalcybGRPbU5iYVYwOWIzMHNkQzVmYzNSeWFXNW5V'
    || 'bVZtUFdrc2RDbDlhV1lvZEhsd1pXOW1JR1VoUFNKemRISnBibWNpS1hSb2NtOTNJRVZ5Y205eUtHRW9NamcwS1NrN2FXWW9JVzR1WDI5M2JtVnlLWFJvY205'
    || 'M0lFVnljbTl5S0dFb01qa3dMR1VwS1gxeVpYUjFjbTRnWlgxbWRXNWpkR2x2YmlCaGJDaGxMSFFwZTNSb2NtOTNJR1U5VDJKcVpXTjBMbkJ5YjNSdmRIbHda'
    || 'UzUwYjFOMGNtbHVaeTVqWVd4c0tIUXBMRVZ5Y205eUtHRW9NekVzWlQwOVBTSmJiMkpxWldOMElFOWlhbVZqZEYwaVB5SnZZbXBsWTNRZ2QybDBhQ0JyWlhs'
    || 'eklIc2lLMDlpYW1WamRDNXJaWGx6S0hRcExtcHZhVzRvSWl3Z0lpa3JJbjBpT21VcEtYMW1kVzVqZEdsdmJpQkJkU2hsS1h0MllYSWdkRDFsTGw5cGJtbDBP'
    || 'M0psZEhWeWJpQjBLR1V1WDNCaGVXeHZZV1FwZldaMWJtTjBhVzl1SUVaMUtHVXBlMloxYm1OMGFXOXVJSFFvYlN4d0tYdHBaaWhsS1h0MllYSWdkajF0TG1S'
    || 'bGJHVjBhVzl1Y3p0MlBUMDliblZzYkQ4b2JTNWtaV3hsZEdsdmJuTTlXM0JkTEcwdVpteGhaM044UFRFMktUcDJMbkIxYzJnb2NDbDlmV1oxYm1OMGFXOXVJ'
    || 'RzRvYlN4d0tYdHBaaWdoWlNseVpYUjFjbTRnYm5Wc2JEdG1iM0lvTzNBaFBUMXVkV3hzT3lsMEtHMHNjQ2tzY0Qxd0xuTnBZbXhwYm1jN2NtVjBkWEp1SUc1'
    || 'MWJHeDlablZ1WTNScGIyNGdjaWh0TEhBcGUyWnZjaWh0UFc1bGR5Qk5ZWEE3Y0NFOVBXNTFiR3c3S1hBdWEyVjVJVDA5Ym5Wc2JEOXRMbk5sZENod0xtdGxl'
    || 'U3h3S1RwdExuTmxkQ2h3TG1sdVpHVjRMSEFwTEhBOWNDNXphV0pzYVc1bk8zSmxkSFZ5YmlCdGZXWjFibU4wYVc5dUlHd29iU3h3S1h0eVpYUjFjbTRnYlQx'
    || 'aWRDaHRMSEFwTEcwdWFXNWtaWGc5TUN4dExuTnBZbXhwYm1jOWJuVnNiQ3h0ZldaMWJtTjBhVzl1SUdrb2JTeHdMSFlwZTNKbGRIVnliaUJ0TG1sdVpHVjRQ'
    || 'WFlzWlQ4b2RqMXRMbUZzZEdWeWJtRjBaU3gySVQwOWJuVnNiRDhvZGoxMkxtbHVaR1Y0TEhZOGNEOG9iUzVtYkdGbmMzdzlNaXh3S1RwMktUb29iUzVtYkdG'
    || 'bmMzdzlNaXh3S1NrNktHMHVabXhoWjNOOFBURXdORGcxTnpZc2NDbDlablZ1WTNScGIyNGdieWh0S1h0eVpYUjFjbTRnWlNZbWJTNWhiSFJsY201aGRHVTlQ'
    || 'VDF1ZFd4c0ppWW9iUzVtYkdGbmMzdzlNaWtzYlgxbWRXNWpkR2x2YmlCaktHMHNjQ3gyTEZRcGUzSmxkSFZ5YmlCd1BUMDliblZzYkh4OGNDNTBZV2NoUFQw'
    || 'MlB5aHdQU1J2S0hZc2JTNXRiMlJsTEZRcExIQXVjbVYwZFhKdVBXMHNjQ2s2S0hBOWJDaHdMSFlwTEhBdWNtVjBkWEp1UFcwc2NDbDlablZ1WTNScGIyNGda'
    || 'Q2h0TEhBc2RpeFVLWHQyWVhJZ1JEMTJMblI1Y0dVN2NtVjBkWEp1SUVROVBUMXFaVDlGS0cwc2NDeDJMbkJ5YjNCekxtTm9hV3hrY21WdUxGUXNkaTVyWlhr'
    || 'cE9uQWhQVDF1ZFd4c0ppWW9jQzVsYkdWdFpXNTBWSGx3WlQwOVBVUjhmSFI1Y0dWdlppQkVQVDBpYjJKcVpXTjBJaVltUkNFOVBXNTFiR3dtSmtRdUpDUjBl'
    || 'WEJsYjJZOVBUMUlaU1ltUVhVb1JDazlQVDF3TG5SNWNHVXBQeWhVUFd3b2NDeDJMbkJ5YjNCektTeFVMbkpsWmoxdGNpaHRMSEFzZGlrc1ZDNXlaWFIxY200'
    || 'OWJTeFVLVG9vVkQxUGJDaDJMblI1Y0dVc2RpNXJaWGtzZGk1d2NtOXdjeXh1ZFd4c0xHMHViVzlrWlN4VUtTeFVMbkpsWmoxdGNpaHRMSEFzZGlrc1ZDNXla'
    || 'WFIxY200OWJTeFVLWDFtZFc1amRHbHZiaUJuS0cwc2NDeDJMRlFwZTNKbGRIVnliaUJ3UFQwOWJuVnNiSHg4Y0M1MFlXY2hQVDAwZkh4d0xuTjBZWFJsVG05'
    || 'a1pTNWpiMjUwWVdsdVpYSkpibVp2SVQwOWRpNWpiMjUwWVdsdVpYSkpibVp2Zkh4d0xuTjBZWFJsVG05a1pTNXBiWEJzWlcxbGJuUmhkR2x2YmlFOVBYWXVh'
    || 'VzF3YkdWdFpXNTBZWFJwYjI0L0tIQTlWMjhvZGl4dExtMXZaR1VzVkNrc2NDNXlaWFIxY200OWJTeHdLVG9vY0Qxc0tIQXNkaTVqYUdsc1pISmxibng4VzEw'
    || 'cExIQXVjbVYwZFhKdVBXMHNjQ2w5Wm5WdVkzUnBiMjRnUlNodExIQXNkaXhVTEVRcGUzSmxkSFZ5YmlCd1BUMDliblZzYkh4OGNDNTBZV2NoUFQwM1B5aHdQ'
    || 'VzF1S0hZc2JTNXRiMlJsTEZRc1JDa3NjQzV5WlhSMWNtNDliU3h3S1Rvb2NEMXNLSEFzZGlrc2NDNXlaWFIxY200OWJTeHdLWDFtZFc1amRHbHZiaUJxS0cw'
    || 'c2NDeDJLWHRwWmloMGVYQmxiMllnY0QwOUluTjBjbWx1WnlJbUpuQWhQVDBpSW54OGRIbHdaVzltSUhBOVBTSnVkVzFpWlhJaUtYSmxkSFZ5YmlCd1BTUnZL'
    || 'Q0lpSzNBc2JTNXRiMlJsTEhZcExIQXVjbVYwZFhKdVBXMHNjRHRwWmloMGVYQmxiMllnY0QwOUltOWlhbVZqZENJbUpuQWhQVDF1ZFd4c0tYdHpkMmwwWTJn'
    || 'b2NDNGtKSFI1Y0dWdlppbDdZMkZ6WlNCVlpUcHlaWFIxY200Z2RqMVBiQ2h3TG5SNWNHVXNjQzVyWlhrc2NDNXdjbTl3Y3l4dWRXeHNMRzB1Ylc5a1pTeDJL'
    || 'U3gyTG5KbFpqMXRjaWh0TEc1MWJHd3NjQ2tzZGk1eVpYUjFjbTQ5YlN4Mk8yTmhjMlVnVTJVNmNtVjBkWEp1SUhBOVYyOG9jQ3h0TG0xdlpHVXNkaWtzY0M1'
    || 'eVpYUjFjbTQ5YlN4d08yTmhjMlVnU0dVNmRtRnlJRlE5Y0M1ZmFXNXBkRHR5WlhSMWNtNGdhaWh0TEZRb2NDNWZjR0Y1Ykc5aFpDa3NkaWw5YVdZb1FtNG9j'
    || 'Q2w4ZkNRb2NDa3BjbVYwZFhKdUlIQTliVzRvY0N4dExtMXZaR1VzZGl4dWRXeHNLU3h3TG5KbGRIVnliajF0TEhBN1lXd29iU3h3S1gxeVpYUjFjbTRnYm5W'
    || 'c2JIMW1kVzVqZEdsdmJpQlRLRzBzY0N4MkxGUXBlM1poY2lCRVBYQWhQVDF1ZFd4c1AzQXVhMlY1T201MWJHdzdhV1lvZEhsd1pXOW1JSFk5UFNKemRISnBi'
    || 'bWNpSmlaMklUMDlJaUo4ZkhSNWNHVnZaaUIyUFQwaWJuVnRZbVZ5SWlseVpYUjFjbTRnUkNFOVBXNTFiR3cvYm5Wc2JEcGpLRzBzY0N3aUlpdDJMRlFwTzJs'
    || 'bUtIUjVjR1Z2WmlCMlBUMGliMkpxWldOMElpWW1kaUU5UFc1MWJHd3BlM04zYVhSamFDaDJMaVFrZEhsd1pXOW1LWHRqWVhObElGVmxPbkpsZEhWeWJpQjJM'
    || 'bXRsZVQwOVBVUS9aQ2h0TEhBc2RpeFVLVHB1ZFd4c08yTmhjMlVnVTJVNmNtVjBkWEp1SUhZdWEyVjVQVDA5UkQ5bktHMHNjQ3gyTEZRcE9tNTFiR3c3WTJG'
    || 'elpTQklaVHB5WlhSMWNtNGdSRDEyTGw5cGJtbDBMRk1vYlN4d0xFUW9kaTVmY0dGNWJHOWhaQ2tzVkNsOWFXWW9RbTRvZGlsOGZDUW9kaWtwY21WMGRYSnVJ'
    || 'RVFoUFQxdWRXeHNQMjUxYkd3NlJTaHRMSEFzZGl4VUxHNTFiR3dwTzJGc0tHMHNkaWw5Y21WMGRYSnVJRzUxYkd4OVpuVnVZM1JwYjI0Z1RTaHRMSEFzZGl4'
    || 'VUxFUXBlMmxtS0hSNWNHVnZaaUJVUFQwaWMzUnlhVzVuSWlZbVZDRTlQU0lpZkh4MGVYQmxiMllnVkQwOUltNTFiV0psY2lJcGNtVjBkWEp1SUcwOWJTNW5a'
    || 'WFFvZGlsOGZHNTFiR3dzWXlod0xHMHNJaUlyVkN4RUtUdHBaaWgwZVhCbGIyWWdWRDA5SW05aWFtVmpkQ0ltSmxRaFBUMXVkV3hzS1h0emQybDBZMmdvVkM0'
    || 'a0pIUjVjR1Z2WmlsN1kyRnpaU0JWWlRweVpYUjFjbTRnYlQxdExtZGxkQ2hVTG10bGVUMDlQVzUxYkd3L2RqcFVMbXRsZVNsOGZHNTFiR3dzWkNod0xHMHNW'
    || 'Q3hFS1R0allYTmxJRk5sT25KbGRIVnliaUJ0UFcwdVoyVjBLRlF1YTJWNVBUMDliblZzYkQ5Mk9sUXVhMlY1S1h4OGJuVnNiQ3huS0hBc2JTeFVMRVFwTzJO'
    || 'aGMyVWdTR1U2ZG1GeUlFWTlWQzVmYVc1cGREdHlaWFIxY200Z1RTaHRMSEFzZGl4R0tGUXVYM0JoZVd4dllXUXBMRVFwZldsbUtFSnVLRlFwZkh3a0tGUXBL'
    || 'WEpsZEhWeWJpQnRQVzB1WjJWMEtIWXBmSHh1ZFd4c0xFVW9jQ3h0TEZRc1JDeHVkV3hzS1R0aGJDaHdMRlFwZlhKbGRIVnliaUJ1ZFd4c2ZXWjFibU4wYVc5'
    || 'dUlFa29iU3h3TEhZc1ZDbDdabTl5S0haaGNpQkVQVzUxYkd3c1JqMXVkV3hzTEZVOWNDeFhQWEE5TUN4RlpUMXVkV3hzTzFVaFBUMXVkV3hzSmlaWFBIWXVi'
    || 'R1Z1WjNSb08xY3JLeWw3VlM1cGJtUmxlRDVYUHloRlpUMVZMRlU5Ym5Wc2JDazZSV1U5VlM1emFXSnNhVzVuTzNaaGNpQmlQVk1vYlN4VkxIWmJWMTBzVkNr'
    || 'N2FXWW9ZajA5UFc1MWJHd3BlMVU5UFQxdWRXeHNKaVlvVlQxRlpTazdZbkpsWVd0OVpTWW1WU1ltWWk1aGJIUmxjbTVoZEdVOVBUMXVkV3hzSmlaMEtHMHNW'
    || 'U2tzY0QxcEtHSXNjQ3hYS1N4R1BUMDliblZzYkQ5RVBXSTZSaTV6YVdKc2FXNW5QV0lzUmoxaUxGVTlSV1Y5YVdZb1Z6MDlQWFl1YkdWdVozUm9LWEpsZEhW'
    || 'eWJpQnVLRzBzVlNrc1kyVW1Kbk51S0cwc1Z5a3NSRHRwWmloVlBUMDliblZzYkNsN1ptOXlLRHRYUEhZdWJHVnVaM1JvTzFjckt5bFZQV29vYlN4MlcxZGRM'
    || 'RlFwTEZVaFBUMXVkV3hzSmlZb2NEMXBLRlVzY0N4WEtTeEdQVDA5Ym5Wc2JEOUVQVlU2Umk1emFXSnNhVzVuUFZVc1JqMVZLVHR5WlhSMWNtNGdZMlVtSm5O'
    || 'dUtHMHNWeWtzUkgxbWIzSW9WVDF5S0cwc1ZTazdWengyTG14bGJtZDBhRHRYS3lzcFJXVTlUU2hWTEcwc1Z5eDJXMWRkTEZRcExFVmxJVDA5Ym5Wc2JDWW1L'
    || 'R1VtSmtWbExtRnNkR1Z5Ym1GMFpTRTlQVzUxYkd3bUpsVXVaR1ZzWlhSbEtFVmxMbXRsZVQwOVBXNTFiR3cvVnpwRlpTNXJaWGtwTEhBOWFTaEZaU3h3TEZj'
    || 'cExFWTlQVDF1ZFd4c1AwUTlSV1U2Umk1emFXSnNhVzVuUFVWbExFWTlSV1VwTzNKbGRIVnliaUJsSmlaVkxtWnZja1ZoWTJnb1puVnVZM1JwYjI0b1pXNHBl'
    || 'M0psZEhWeWJpQjBLRzBzWlc0cGZTa3NZMlVtSm5OdUtHMHNWeWtzUkgxbWRXNWpkR2x2YmlCNktHMHNjQ3gyTEZRcGUzWmhjaUJFUFNRb2RpazdhV1lvZEhs'
    || 'd1pXOW1JRVFoUFNKbWRXNWpkR2x2YmlJcGRHaHliM2NnUlhKeWIzSW9ZU2d4TlRBcEtUdHBaaWgyUFVRdVkyRnNiQ2gyS1N4MlBUMXVkV3hzS1hSb2NtOTNJ'
    || 'RVZ5Y205eUtHRW9NVFV4S1NrN1ptOXlLSFpoY2lCR1BVUTliblZzYkN4VlBYQXNWejF3UFRBc1JXVTliblZzYkN4aVBYWXVibVY0ZENncE8xVWhQVDF1ZFd4'
    || 'c0ppWWhZaTVrYjI1bE8xY3JLeXhpUFhZdWJtVjRkQ2dwS1h0VkxtbHVaR1Y0UGxjL0tFVmxQVlVzVlQxdWRXeHNLVHBGWlQxVkxuTnBZbXhwYm1jN2RtRnlJ'
    || 'R1Z1UFZNb2JTeFZMR0l1ZG1Gc2RXVXNWQ2s3YVdZb1pXNDlQVDF1ZFd4c0tYdFZQVDA5Ym5Wc2JDWW1LRlU5UldVcE8ySnlaV0ZyZldVbUpsVW1KbVZ1TG1G'
    || 'c2RHVnlibUYwWlQwOVBXNTFiR3dtSm5Rb2JTeFZLU3h3UFdrb1pXNHNjQ3hYS1N4R1BUMDliblZzYkQ5RVBXVnVPa1l1YzJsaWJHbHVaejFsYml4R1BXVnVM'
    || 'RlU5UldWOWFXWW9ZaTVrYjI1bEtYSmxkSFZ5YmlCdUtHMHNWU2tzWTJVbUpuTnVLRzBzVnlrc1JEdHBaaWhWUFQwOWJuVnNiQ2w3Wm05eUtEc2hZaTVrYjI1'
    || 'bE8xY3JLeXhpUFhZdWJtVjRkQ2dwS1dJOWFpaHRMR0l1ZG1Gc2RXVXNWQ2tzWWlFOVBXNTFiR3dtSmlod1BXa29ZaXh3TEZjcExFWTlQVDF1ZFd4c1AwUTlZ'
    || 'anBHTG5OcFlteHBibWM5WWl4R1BXSXBPM0psZEhWeWJpQmpaU1ltYzI0b2JTeFhLU3hFZldadmNpaFZQWElvYlN4VktUc2hZaTVrYjI1bE8xY3JLeXhpUFhZ'
    || 'dWJtVjRkQ2dwS1dJOVRTaFZMRzBzVnl4aUxuWmhiSFZsTEZRcExHSWhQVDF1ZFd4c0ppWW9aU1ltWWk1aGJIUmxjbTVoZEdVaFBUMXVkV3hzSmlaVkxtUmxi'
    || 'R1YwWlNoaUxtdGxlVDA5UFc1MWJHdy9WenBpTG10bGVTa3NjRDFwS0dJc2NDeFhLU3hHUFQwOWJuVnNiRDlFUFdJNlJpNXphV0pzYVc1blBXSXNSajFpS1R0'
    || 'eVpYUjFjbTRnWlNZbVZTNW1iM0pGWVdOb0tHWjFibU4wYVc5dUtHOXdLWHR5WlhSMWNtNGdkQ2h0TEc5d0tYMHBMR05sSmlaemJpaHRMRmNwTEVSOVpuVnVZ'
    || 'M1JwYjI0Z1oyVW9iU3h3TEhZc1ZDbDdhV1lvZEhsd1pXOW1JSFk5UFNKdlltcGxZM1FpSmlaMklUMDliblZzYkNZbWRpNTBlWEJsUFQwOWFtVW1Kbll1YTJW'
    || 'NVBUMDliblZzYkNZbUtIWTlkaTV3Y205d2N5NWphR2xzWkhKbGJpa3NkSGx3Wlc5bUlIWTlQU0p2WW1wbFkzUWlKaVoySVQwOWJuVnNiQ2w3YzNkcGRHTm9L'
    || 'SFl1SkNSMGVYQmxiMllwZTJOaGMyVWdWV1U2WlRwN1ptOXlLSFpoY2lCRVBYWXVhMlY1TEVZOWNEdEdJVDA5Ym5Wc2JEc3BlMmxtS0VZdWEyVjVQVDA5UkNs'
    || 'N2FXWW9SRDEyTG5SNWNHVXNSRDA5UFdwbEtYdHBaaWhHTG5SaFp6MDlQVGNwZTI0b2JTeEdMbk5wWW14cGJtY3BMSEE5YkNoR0xIWXVjSEp2Y0hNdVkyaHBi'
    || 'R1J5Wlc0cExIQXVjbVYwZFhKdVBXMHNiVDF3TzJKeVpXRnJJR1Y5ZldWc2MyVWdhV1lvUmk1bGJHVnRaVzUwVkhsd1pUMDlQVVI4ZkhSNWNHVnZaaUJFUFQw'
    || 'aWIySnFaV04wSWlZbVJDRTlQVzUxYkd3bUprUXVKQ1IwZVhCbGIyWTlQVDFJWlNZbVFYVW9SQ2s5UFQxR0xuUjVjR1VwZTI0b2JTeEdMbk5wWW14cGJtY3BM'
    || 'SEE5YkNoR0xIWXVjSEp2Y0hNcExIQXVjbVZtUFcxeUtHMHNSaXgyS1N4d0xuSmxkSFZ5YmoxdExHMDljRHRpY21WaGF5QmxmVzRvYlN4R0tUdGljbVZoYTMx'
    || 'bGJITmxJSFFvYlN4R0tUdEdQVVl1YzJsaWJHbHVaMzEyTG5SNWNHVTlQVDFxWlQ4b2NEMXRiaWgyTG5CeWIzQnpMbU5vYVd4a2NtVnVMRzB1Ylc5a1pTeFVM'
    || 'SFl1YTJWNUtTeHdMbkpsZEhWeWJqMXRMRzA5Y0NrNktGUTlUMndvZGk1MGVYQmxMSFl1YTJWNUxIWXVjSEp2Y0hNc2JuVnNiQ3h0TG0xdlpHVXNWQ2tzVkM1'
    || 'eVpXWTliWElvYlN4d0xIWXBMRlF1Y21WMGRYSnVQVzBzYlQxVUtYMXlaWFIxY200Z2J5aHRLVHRqWVhObElGTmxPbVU2ZTJadmNpaEdQWFl1YTJWNU8zQWhQ'
    || 'VDF1ZFd4c095bDdhV1lvY0M1clpYazlQVDFHS1dsbUtIQXVkR0ZuUFQwOU5DWW1jQzV6ZEdGMFpVNXZaR1V1WTI5dWRHRnBibVZ5U1c1bWJ6MDlQWFl1WTI5'
    || 'dWRHRnBibVZ5U1c1bWJ5WW1jQzV6ZEdGMFpVNXZaR1V1YVcxd2JHVnRaVzUwWVhScGIyNDlQVDEyTG1sdGNHeGxiV1Z1ZEdGMGFXOXVLWHR1S0cwc2NDNXph'
    || 'V0pzYVc1bktTeHdQV3dvY0N4MkxtTm9hV3hrY21WdWZIeGJYU2tzY0M1eVpYUjFjbTQ5YlN4dFBYQTdZbkpsWVdzZ1pYMWxiSE5sZTI0b2JTeHdLVHRpY21W'
    || 'aGEzMWxiSE5sSUhRb2JTeHdLVHR3UFhBdWMybGliR2x1WjMxd1BWZHZLSFlzYlM1dGIyUmxMRlFwTEhBdWNtVjBkWEp1UFcwc2JUMXdmWEpsZEhWeWJpQnZL'
    || 'RzBwTzJOaGMyVWdTR1U2Y21WMGRYSnVJRVk5ZGk1ZmFXNXBkQ3huWlNodExIQXNSaWgyTGw5d1lYbHNiMkZrS1N4VUtYMXBaaWhDYmloMktTbHlaWFIxY200'
    || 'Z1NTaHRMSEFzZGl4VUtUdHBaaWdrS0hZcEtYSmxkSFZ5YmlCNktHMHNjQ3gyTEZRcE8yRnNLRzBzZGlsOWNtVjBkWEp1SUhSNWNHVnZaaUIyUFQwaWMzUnlh'
    || 'VzVuSWlZbWRpRTlQU0lpZkh4MGVYQmxiMllnZGowOUltNTFiV0psY2lJL0tIWTlJaUlyZGl4d0lUMDliblZzYkNZbWNDNTBZV2M5UFQwMlB5aHVLRzBzY0M1'
    || 'emFXSnNhVzVuS1N4d1BXd29jQ3gyS1N4d0xuSmxkSFZ5YmoxdExHMDljQ2s2S0c0b2JTeHdLU3h3UFNSdktIWXNiUzV0YjJSbExGUXBMSEF1Y21WMGRYSnVQ'
    || 'VzBzYlQxd0tTeHZLRzBwS1RwdUtHMHNjQ2w5Y21WMGRYSnVJR2RsZlhaaGNpQkpiajFHZFNnaE1Da3NWWFU5Um5Vb0lURXBMR05zUFZaMEtHNTFiR3dwTEdS'
    || 'c1BXNTFiR3dzZW00OWJuVnNiQ3hhYVQxdWRXeHNPMloxYm1OMGFXOXVJRXBwS0NsN1dtazllbTQ5Wkd3OWJuVnNiSDFtZFc1amRHbHZiaUJ4YVNobEtYdDJZ'
    || 'WElnZEQxamJDNWpkWEp5Wlc1ME8zVmxLR05zS1N4bExsOWpkWEp5Wlc1MFZtRnNkV1U5ZEgxbWRXNWpkR2x2YmlCaWFTaGxMSFFzYmlsN1ptOXlLRHRsSVQw'
    || 'OWJuVnNiRHNwZTNaaGNpQnlQV1V1WVd4MFpYSnVZWFJsTzJsbUtDaGxMbU5vYVd4a1RHRnVaWE1tZENraFBUMTBQeWhsTG1Ob2FXeGtUR0Z1WlhOOFBYUXNj'
    || 'aUU5UFc1MWJHd21KaWh5TG1Ob2FXeGtUR0Z1WlhOOFBYUXBLVHB5SVQwOWJuVnNiQ1ltS0hJdVkyaHBiR1JNWVc1bGN5WjBLU0U5UFhRbUppaHlMbU5vYVd4'
    || 'a1RHRnVaWE44UFhRcExHVTlQVDF1S1dKeVpXRnJPMlU5WlM1eVpYUjFjbTU5ZldaMWJtTjBhVzl1SUVSdUtHVXNkQ2w3Wkd3OVpTeGFhVDE2YmoxdWRXeHNM'
    || 'R1U5WlM1a1pYQmxibVJsYm1OcFpYTXNaU0U5UFc1MWJHd21KbVV1Wm1seWMzUkRiMjUwWlhoMElUMDliblZzYkNZbUtDaGxMbXhoYm1WekpuUXBJVDA5TUNZ'
    || 'bUtGWmxQU0V3S1N4bExtWnBjbk4wUTI5dWRHVjRkRDF1ZFd4c0tYMW1kVzVqZEdsdmJpQnNkQ2hsS1h0MllYSWdkRDFsTGw5amRYSnlaVzUwVm1Gc2RXVTdh'
    || 'V1lvV21raFBUMWxLV2xtS0dVOWUyTnZiblJsZUhRNlpTeHRaVzF2YVhwbFpGWmhiSFZsT25Rc2JtVjRkRHB1ZFd4c2ZTeDZiajA5UFc1MWJHd3BlMmxtS0dS'
    || 'c1BUMDliblZzYkNsMGFISnZkeUJGY25KdmNpaGhLRE13T0NrcE8zcHVQV1VzWkd3dVpHVndaVzVrWlc1amFXVnpQWHRzWVc1bGN6b3dMR1pwY25OMFEyOXVk'
    || 'R1Y0ZERwbGZYMWxiSE5sSUhwdVBYcHVMbTVsZUhROVpUdHlaWFIxY200Z2RIMTJZWElnZFc0OWJuVnNiRHRtZFc1amRHbHZiaUJsYnlobEtYdDFiajA5UFc1'
    || 'MWJHdy9kVzQ5VzJWZE9uVnVMbkIxYzJnb1pTbDlablZ1WTNScGIyNGdTSFVvWlN4MExHNHNjaWw3ZG1GeUlHdzlkQzVwYm5SbGNteGxZWFpsWkR0eVpYUjFj'
    || 'bTRnYkQwOVBXNTFiR3cvS0c0dWJtVjRkRDF1TEdWdktIUXBLVG9vYmk1dVpYaDBQV3d1Ym1WNGRDeHNMbTVsZUhROWJpa3NkQzVwYm5SbGNteGxZWFpsWkQx'
    || 'dUxFMTBLR1VzY2lsOVpuVnVZM1JwYjI0Z1RYUW9aU3gwS1h0bExteGhibVZ6ZkQxME8zWmhjaUJ1UFdVdVlXeDBaWEp1WVhSbE8yWnZjaWh1SVQwOWJuVnNi'
    || 'Q1ltS0c0dWJHRnVaWE44UFhRcExHNDlaU3hsUFdVdWNtVjBkWEp1TzJVaFBUMXVkV3hzT3lsbExtTm9hV3hrVEdGdVpYTjhQWFFzYmoxbExtRnNkR1Z5Ym1G'
    || 'MFpTeHVJVDA5Ym5Wc2JDWW1LRzR1WTJocGJHUk1ZVzVsYzN3OWRDa3NiajFsTEdVOVpTNXlaWFIxY200N2NtVjBkWEp1SUc0dWRHRm5QVDA5TXo5dUxuTjBZ'
    || 'WFJsVG05a1pUcHVkV3hzZlhaaGNpQlpkRDBoTVR0bWRXNWpkR2x2YmlCMGJ5aGxLWHRsTG5Wd1pHRjBaVkYxWlhWbFBYdGlZWE5sVTNSaGRHVTZaUzV0Wlcx'
    || 'dmFYcGxaRk4wWVhSbExHWnBjbk4wUW1GelpWVndaR0YwWlRwdWRXeHNMR3hoYzNSQ1lYTmxWWEJrWVhSbE9tNTFiR3dzYzJoaGNtVmtPbnR3Wlc1a2FXNW5P'
    || 'bTUxYkd3c2FXNTBaWEpzWldGMlpXUTZiblZzYkN4c1lXNWxjem93ZlN4bFptWmxZM1J6T201MWJHeDlmV1oxYm1OMGFXOXVJQ1IxS0dVc2RDbDdaVDFsTG5W'
    || 'd1pHRjBaVkYxWlhWbExIUXVkWEJrWVhSbFVYVmxkV1U5UFQxbEppWW9kQzUxY0dSaGRHVlJkV1YxWlQxN1ltRnpaVk4wWVhSbE9tVXVZbUZ6WlZOMFlYUmxM'
    || 'R1pwY25OMFFtRnpaVlZ3WkdGMFpUcGxMbVpwY25OMFFtRnpaVlZ3WkdGMFpTeHNZWE4wUW1GelpWVndaR0YwWlRwbExteGhjM1JDWVhObFZYQmtZWFJsTEhO'
    || 'b1lYSmxaRHBsTG5Ob1lYSmxaQ3hsWm1abFkzUnpPbVV1WldabVpXTjBjMzBwZldaMWJtTjBhVzl1SUZCMEtHVXNkQ2w3Y21WMGRYSnVlMlYyWlc1MFZHbHRa'
    || 'VHBsTEd4aGJtVTZkQ3gwWVdjNk1DeHdZWGxzYjJGa09tNTFiR3dzWTJGc2JHSmhZMnM2Ym5Wc2JDeHVaWGgwT201MWJHeDlmV1oxYm1OMGFXOXVJRXQwS0dV'
    || 'c2RDeHVLWHQyWVhJZ2NqMWxMblZ3WkdGMFpWRjFaWFZsTzJsbUtISTlQVDF1ZFd4c0tYSmxkSFZ5YmlCdWRXeHNPMmxtS0hJOWNpNXphR0Z5WldRc0tGb21N'
    || 'aWtoUFQwd0tYdDJZWElnYkQxeUxuQmxibVJwYm1jN2NtVjBkWEp1SUd3OVBUMXVkV3hzUDNRdWJtVjRkRDEwT2loMExtNWxlSFE5YkM1dVpYaDBMR3d1Ym1W'
    || 'NGREMTBLU3h5TG5CbGJtUnBibWM5ZEN4TmRDaGxMRzRwZlhKbGRIVnliaUJzUFhJdWFXNTBaWEpzWldGMlpXUXNiRDA5UFc1MWJHdy9LSFF1Ym1WNGREMTBM'
    || 'R1Z2S0hJcEtUb29kQzV1WlhoMFBXd3VibVY0ZEN4c0xtNWxlSFE5ZENrc2NpNXBiblJsY214bFlYWmxaRDEwTEUxMEtHVXNiaWw5Wm5WdVkzUnBiMjRnWm13'
    || 'b1pTeDBMRzRwZTJsbUtIUTlkQzUxY0dSaGRHVlJkV1YxWlN4MElUMDliblZzYkNZbUtIUTlkQzV6YUdGeVpXUXNLRzRtTkRFNU5ESTBNQ2toUFQwd0tTbDdk'
    || 'bUZ5SUhJOWRDNXNZVzVsY3p0eUpqMWxMbkJsYm1ScGJtZE1ZVzVsY3l4dWZEMXlMSFF1YkdGdVpYTTliaXh0YVNobExHNHBmWDFtZFc1amRHbHZiaUJYZFNo'
    || 'bExIUXBlM1poY2lCdVBXVXVkWEJrWVhSbFVYVmxkV1VzY2oxbExtRnNkR1Z5Ym1GMFpUdHBaaWh5SVQwOWJuVnNiQ1ltS0hJOWNpNTFjR1JoZEdWUmRXVjFa'
    || 'U3h1UFQwOWNpa3BlM1poY2lCc1BXNTFiR3dzYVQxdWRXeHNPMmxtS0c0OWJpNW1hWEp6ZEVKaGMyVlZjR1JoZEdVc2JpRTlQVzUxYkd3cGUyUnZlM1poY2lC'
    || 'dlBYdGxkbVZ1ZEZScGJXVTZiaTVsZG1WdWRGUnBiV1VzYkdGdVpUcHVMbXhoYm1Vc2RHRm5PbTR1ZEdGbkxIQmhlV3h2WVdRNmJpNXdZWGxzYjJGa0xHTmhi'
    || 'R3hpWVdOck9tNHVZMkZzYkdKaFkyc3NibVY0ZERwdWRXeHNmVHRwUFQwOWJuVnNiRDlzUFdrOWJ6cHBQV2t1Ym1WNGREMXZMRzQ5Ymk1dVpYaDBmWGRvYVd4'
    || 'bEtHNGhQVDF1ZFd4c0tUdHBQVDA5Ym5Wc2JEOXNQV2s5ZERwcFBXa3VibVY0ZEQxMGZXVnNjMlVnYkQxcFBYUTdiajE3WW1GelpWTjBZWFJsT25JdVltRnpa'
    || 'Vk4wWVhSbExHWnBjbk4wUW1GelpWVndaR0YwWlRwc0xHeGhjM1JDWVhObFZYQmtZWFJsT21rc2MyaGhjbVZrT25JdWMyaGhjbVZrTEdWbVptVmpkSE02Y2k1'
    || 'bFptWmxZM1J6ZlN4bExuVndaR0YwWlZGMVpYVmxQVzQ3Y21WMGRYSnVmV1U5Ymk1c1lYTjBRbUZ6WlZWd1pHRjBaU3hsUFQwOWJuVnNiRDl1TG1acGNuTjBR'
    || 'bUZ6WlZWd1pHRjBaVDEwT21VdWJtVjRkRDEwTEc0dWJHRnpkRUpoYzJWVmNHUmhkR1U5ZEgxbWRXNWpkR2x2YmlCd2JDaGxMSFFzYml4eUtYdDJZWElnYkQx'
    || 'bExuVndaR0YwWlZGMVpYVmxPMWwwUFNFeE8zWmhjaUJwUFd3dVptbHljM1JDWVhObFZYQmtZWFJsTEc4OWJDNXNZWE4wUW1GelpWVndaR0YwWlN4alBXd3Vj'
    || 'MmhoY21Wa0xuQmxibVJwYm1jN2FXWW9ZeUU5UFc1MWJHd3BlMnd1YzJoaGNtVmtMbkJsYm1ScGJtYzliblZzYkR0MllYSWdaRDFqTEdjOVpDNXVaWGgwTzJR'
    || 'dWJtVjRkRDF1ZFd4c0xHODlQVDF1ZFd4c1AyazlaenB2TG01bGVIUTlaeXh2UFdRN2RtRnlJRVU5WlM1aGJIUmxjbTVoZEdVN1JTRTlQVzUxYkd3bUppaEZQ'
    || 'VVV1ZFhCa1lYUmxVWFZsZFdVc1l6MUZMbXhoYzNSQ1lYTmxWWEJrWVhSbExHTWhQVDF2SmlZb1l6MDlQVzUxYkd3L1JTNW1hWEp6ZEVKaGMyVlZjR1JoZEdV'
    || 'OVp6cGpMbTVsZUhROVp5eEZMbXhoYzNSQ1lYTmxWWEJrWVhSbFBXUXBLWDFwWmlocElUMDliblZzYkNsN2RtRnlJR285YkM1aVlYTmxVM1JoZEdVN2J6MHdM'
    || 'RVU5Wnoxa1BXNTFiR3dzWXoxcE8yUnZlM1poY2lCVFBXTXViR0Z1WlN4TlBXTXVaWFpsYm5SVWFXMWxPMmxtS0NoeUpsTXBQVDA5VXlsN1JTRTlQVzUxYkd3'
    || 'bUppaEZQVVV1Ym1WNGREMTdaWFpsYm5SVWFXMWxPazBzYkdGdVpUb3dMSFJoWnpwakxuUmhaeXh3WVhsc2IyRmtPbU11Y0dGNWJHOWhaQ3hqWVd4c1ltRmph'
    || 'enBqTG1OaGJHeGlZV05yTEc1bGVIUTZiblZzYkgwcE8yVTZlM1poY2lCSlBXVXNlajFqTzNOM2FYUmphQ2hUUFhRc1RUMXVMSG91ZEdGbktYdGpZWE5sSURF'
    || 'NmFXWW9TVDE2TG5CaGVXeHZZV1FzZEhsd1pXOW1JRWs5UFNKbWRXNWpkR2x2YmlJcGUybzlTUzVqWVd4c0tFMHNhaXhUS1R0aWNtVmhheUJsZldvOVNUdGlj'
    || 'bVZoYXlCbE8yTmhjMlVnTXpwSkxtWnNZV2R6UFVrdVpteGhaM01tTFRZMU5UTTNmREV5T0R0allYTmxJREE2YVdZb1NUMTZMbkJoZVd4dllXUXNVejEwZVhC'
    || 'bGIyWWdTVDA5SW1aMWJtTjBhVzl1SWo5SkxtTmhiR3dvVFN4cUxGTXBPa2tzVXowOWJuVnNiQ2xpY21WaGF5QmxPMm85VHloN2ZTeHFMRk1wTzJKeVpXRnJJ'
    || 'R1U3WTJGelpTQXlPbGwwUFNFd2ZYMWpMbU5oYkd4aVlXTnJJVDA5Ym5Wc2JDWW1ZeTVzWVc1bElUMDlNQ1ltS0dVdVpteGhaM044UFRZMExGTTliQzVsWm1a'
    || 'bFkzUnpMRk05UFQxdWRXeHNQMnd1WldabVpXTjBjejFiWTEwNlV5NXdkWE5vS0dNcEtYMWxiSE5sSUUwOWUyVjJaVzUwVkdsdFpUcE5MR3hoYm1VNlV5eDBZ'
    || 'V2M2WXk1MFlXY3NjR0Y1Ykc5aFpEcGpMbkJoZVd4dllXUXNZMkZzYkdKaFkyczZZeTVqWVd4c1ltRmpheXh1WlhoME9tNTFiR3g5TEVVOVBUMXVkV3hzUHlo'
    || 'blBVVTlUU3hrUFdvcE9rVTlSUzV1WlhoMFBVMHNiM3c5VXp0cFppaGpQV011Ym1WNGRDeGpQVDA5Ym5Wc2JDbDdhV1lvWXoxc0xuTm9ZWEpsWkM1d1pXNWth'
    || 'VzVuTEdNOVBUMXVkV3hzS1dKeVpXRnJPMU05WXl4alBWTXVibVY0ZEN4VExtNWxlSFE5Ym5Wc2JDeHNMbXhoYzNSQ1lYTmxWWEJrWVhSbFBWTXNiQzV6YUdG'
    || 'eVpXUXVjR1Z1WkdsdVp6MXVkV3hzZlgxM2FHbHNaU2doTUNrN2FXWW9SVDA5UFc1MWJHd21KaWhrUFdvcExHd3VZbUZ6WlZOMFlYUmxQV1FzYkM1bWFYSnpk'
    || 'RUpoYzJWVmNHUmhkR1U5Wnl4c0xteGhjM1JDWVhObFZYQmtZWFJsUFVVc2REMXNMbk5vWVhKbFpDNXBiblJsY214bFlYWmxaQ3gwSVQwOWJuVnNiQ2w3YkQx'
    || 'ME8yUnZJRzk4UFd3dWJHRnVaU3hzUFd3dWJtVjRkRHQzYUdsc1pTaHNJVDA5ZENsOVpXeHpaU0JwUFQwOWJuVnNiQ1ltS0d3dWMyaGhjbVZrTG14aGJtVnpQ'
    || 'VEFwTzJSdWZEMXZMR1V1YkdGdVpYTTlieXhsTG0xbGJXOXBlbVZrVTNSaGRHVTlhbjE5Wm5WdVkzUnBiMjRnVm5Vb1pTeDBMRzRwZTJsbUtHVTlkQzVsWm1a'
    || 'bFkzUnpMSFF1WldabVpXTjBjejF1ZFd4c0xHVWhQVDF1ZFd4c0tXWnZjaWgwUFRBN2REeGxMbXhsYm1kMGFEdDBLeXNwZTNaaGNpQnlQV1ZiZEYwc2JEMXlM'
    || 'bU5oYkd4aVlXTnJPMmxtS0d3aFBUMXVkV3hzS1h0cFppaHlMbU5oYkd4aVlXTnJQVzUxYkd3c2NqMXVMSFI1Y0dWdlppQnNJVDBpWm5WdVkzUnBiMjRpS1hS'
    || 'b2NtOTNJRVZ5Y205eUtHRW9NVGt4TEd3cEtUdHNMbU5oYkd3b2NpbDlmWDEyWVhJZ2RuSTllMzBzWDNROVZuUW9kbklwTEdkeVBWWjBLSFp5S1N4NWNqMVdk'
    || 'Q2gyY2lrN1puVnVZM1JwYjI0Z1lXNG9aU2w3YVdZb1pUMDlQWFp5S1hSb2NtOTNJRVZ5Y205eUtHRW9NVGMwS1NrN2NtVjBkWEp1SUdWOVpuVnVZM1JwYjI0'
    || 'Z2JtOG9aU3gwS1h0emQybDBZMmdvYVdVb2VYSXNkQ2tzYVdVb1ozSXNaU2tzYVdVb1gzUXNkbklwTEdVOWRDNXViMlJsVkhsd1pTeGxLWHRqWVhObElEazZZ'
    || 'MkZ6WlNBeE1UcDBQU2gwUFhRdVpHOWpkVzFsYm5SRmJHVnRaVzUwS1Q5MExtNWhiV1Z6Y0dGalpWVlNTVHB5YVNodWRXeHNMQ0lpS1R0aWNtVmhhenRrWlda'
    || 'aGRXeDBPbVU5WlQwOVBUZy9kQzV3WVhKbGJuUk9iMlJsT25Rc2REMWxMbTVoYldWemNHRmpaVlZTU1h4OGJuVnNiQ3hsUFdVdWRHRm5UbUZ0WlN4MFBYSnBL'
    || 'SFFzWlNsOWRXVW9YM1FwTEdsbEtGOTBMSFFwZldaMWJtTjBhVzl1SUVGdUtDbDdkV1VvWDNRcExIVmxLR2R5S1N4MVpTaDVjaWw5Wm5WdVkzUnBiMjRnUW5V'
    || 'b1pTbDdZVzRvZVhJdVkzVnljbVZ1ZENrN2RtRnlJSFE5WVc0b1gzUXVZM1Z5Y21WdWRDa3NiajF5YVNoMExHVXVkSGx3WlNrN2RDRTlQVzRtSmlocFpTaG5j'
    || 'aXhsS1N4cFpTaGZkQ3h1S1NsOVpuVnVZM1JwYjI0Z2NtOG9aU2w3WjNJdVkzVnljbVZ1ZEQwOVBXVW1KaWgxWlNoZmRDa3NkV1VvWjNJcEtYMTJZWElnWkdV'
    || 'OVZuUW9NQ2s3Wm5WdVkzUnBiMjRnYUd3b1pTbDdabTl5S0haaGNpQjBQV1U3ZENFOVBXNTFiR3c3S1h0cFppaDBMblJoWnowOVBURXpLWHQyWVhJZ2JqMTBM'
    || 'bTFsYlc5cGVtVmtVM1JoZEdVN2FXWW9iaUU5UFc1MWJHd21KaWh1UFc0dVpHVm9lV1J5WVhSbFpDeHVQVDA5Ym5Wc2JIeDhiaTVrWVhSaFBUMDlJaVEvSW54'
    || 'OGJpNWtZWFJoUFQwOUlpUWhJaWtwY21WMGRYSnVJSFI5Wld4elpTQnBaaWgwTG5SaFp6MDlQVEU1SmlaMExtMWxiVzlwZW1Wa1VISnZjSE11Y21WMlpXRnNU'
    || 'M0prWlhJaFBUMTJiMmxrSURBcGUybG1LQ2gwTG1ac1lXZHpKakV5T0NraFBUMHdLWEpsZEhWeWJpQjBmV1ZzYzJVZ2FXWW9kQzVqYUdsc1pDRTlQVzUxYkd3'
    || 'cGUzUXVZMmhwYkdRdWNtVjBkWEp1UFhRc2REMTBMbU5vYVd4a08yTnZiblJwYm5WbGZXbG1LSFE5UFQxbEtXSnlaV0ZyTzJadmNpZzdkQzV6YVdKc2FXNW5Q'
    || 'VDA5Ym5Wc2JEc3BlMmxtS0hRdWNtVjBkWEp1UFQwOWJuVnNiSHg4ZEM1eVpYUjFjbTQ5UFQxbEtYSmxkSFZ5YmlCdWRXeHNPM1E5ZEM1eVpYUjFjbTU5ZEM1'
    || 'emFXSnNhVzVuTG5KbGRIVnliajEwTG5KbGRIVnliaXgwUFhRdWMybGliR2x1WjMxeVpYUjFjbTRnYm5Wc2JIMTJZWElnYkc4OVcxMDdablZ1WTNScGIyNGdh'
    || 'VzhvS1h0bWIzSW9kbUZ5SUdVOU1EdGxQR3h2TG14bGJtZDBhRHRsS3lzcGJHOWJaVjB1WDNkdmNtdEpibEJ5YjJkeVpYTnpWbVZ5YzJsdmJsQnlhVzFoY25r'
    || 'OWJuVnNiRHRzYnk1c1pXNW5kR2c5TUgxMllYSWdiV3c5YjJVdVVtVmhZM1JEZFhKeVpXNTBSR2x6Y0dGMFkyaGxjaXh2YnoxdlpTNVNaV0ZqZEVOMWNuSmxi'
    || 'blJDWVhSamFFTnZibVpwWnl4amJqMHdMR1psUFc1MWJHd3NlR1U5Ym5Wc2JDeGZaVDF1ZFd4c0xIWnNQU0V4TEhoeVBTRXhMSGR5UFRBc1EyWTlNRHRtZFc1'
    || 'amRHbHZiaUJOWlNncGUzUm9jbTkzSUVWeWNtOXlLR0VvTXpJeEtTbDlablZ1WTNScGIyNGdjMjhvWlN4MEtYdHBaaWgwUFQwOWJuVnNiQ2x5WlhSMWNtNGhN'
    || 'VHRtYjNJb2RtRnlJRzQ5TUR0dVBIUXViR1Z1WjNSb0ppWnVQR1V1YkdWdVozUm9PMjRyS3lscFppZ2haSFFvWlZ0dVhTeDBXMjVkS1NseVpYUjFjbTRoTVR0'
    || 'eVpYUjFjbTRoTUgxbWRXNWpkR2x2YmlCMWJ5aGxMSFFzYml4eUxHd3NhU2w3YVdZb1kyNDlhU3htWlQxMExIUXViV1Z0YjJsNlpXUlRkR0YwWlQxdWRXeHNM'
    || 'SFF1ZFhCa1lYUmxVWFZsZFdVOWJuVnNiQ3gwTG14aGJtVnpQVEFzYld3dVkzVnljbVZ1ZEQxbFBUMDliblZzYkh4OFpTNXRaVzF2YVhwbFpGTjBZWFJsUFQw'
    || 'OWJuVnNiRDlRWmpwUFppeGxQVzRvY2l4c0tTeDRjaWw3YVQwd08yUnZlMmxtS0hoeVBTRXhMSGR5UFRBc01qVThQV2twZEdoeWIzY2dSWEp5YjNJb1lTZ3pN'
    || 'REVwS1R0cEt6MHhMRjlsUFhobFBXNTFiR3dzZEM1MWNHUmhkR1ZSZFdWMVpUMXVkV3hzTEcxc0xtTjFjbkpsYm5ROVNXWXNaVDF1S0hJc2JDbDlkMmhwYkdV'
    || 'b2VISXBmV2xtS0cxc0xtTjFjbkpsYm5ROWVHd3NkRDE0WlNFOVBXNTFiR3dtSm5obExtNWxlSFFoUFQxdWRXeHNMR051UFRBc1gyVTllR1U5Wm1VOWJuVnNi'
    || 'Q3gyYkQwaE1TeDBLWFJvY205M0lFVnljbTl5S0dFb016QXdLU2s3Y21WMGRYSnVJR1Y5Wm5WdVkzUnBiMjRnWVc4b0tYdDJZWElnWlQxM2NpRTlQVEE3Y21W'
    || 'MGRYSnVJSGR5UFRBc1pYMW1kVzVqZEdsdmJpQnJkQ2dwZTNaaGNpQmxQWHR0WlcxdmFYcGxaRk4wWVhSbE9tNTFiR3dzWW1GelpWTjBZWFJsT201MWJHd3NZ'
    || 'bUZ6WlZGMVpYVmxPbTUxYkd3c2NYVmxkV1U2Ym5Wc2JDeHVaWGgwT201MWJHeDlPM0psZEhWeWJpQmZaVDA5UFc1MWJHdy9abVV1YldWdGIybDZaV1JUZEdG'
    || 'MFpUMWZaVDFsT2w5bFBWOWxMbTVsZUhROVpTeGZaWDFtZFc1amRHbHZiaUJwZENncGUybG1LSGhsUFQwOWJuVnNiQ2w3ZG1GeUlHVTlabVV1WVd4MFpYSnVZ'
    || 'WFJsTzJVOVpTRTlQVzUxYkd3L1pTNXRaVzF2YVhwbFpGTjBZWFJsT201MWJHeDlaV3h6WlNCbFBYaGxMbTVsZUhRN2RtRnlJSFE5WDJVOVBUMXVkV3hzUDJa'
    || 'bExtMWxiVzlwZW1Wa1UzUmhkR1U2WDJVdWJtVjRkRHRwWmloMElUMDliblZzYkNsZlpUMTBMSGhsUFdVN1pXeHpaWHRwWmlobFBUMDliblZzYkNsMGFISnZk'
    || 'eUJGY25KdmNpaGhLRE14TUNrcE8zaGxQV1VzWlQxN2JXVnRiMmw2WldSVGRHRjBaVHA0WlM1dFpXMXZhWHBsWkZOMFlYUmxMR0poYzJWVGRHRjBaVHA0WlM1'
    || 'aVlYTmxVM1JoZEdVc1ltRnpaVkYxWlhWbE9uaGxMbUpoYzJWUmRXVjFaU3h4ZFdWMVpUcDRaUzV4ZFdWMVpTeHVaWGgwT201MWJHeDlMRjlsUFQwOWJuVnNi'
    || 'RDltWlM1dFpXMXZhWHBsWkZOMFlYUmxQVjlsUFdVNlgyVTlYMlV1Ym1WNGREMWxmWEpsZEhWeWJpQmZaWDFtZFc1amRHbHZiaUJUY2lobExIUXBlM0psZEhW'
    || 'eWJpQjBlWEJsYjJZZ2REMDlJbVoxYm1OMGFXOXVJajkwS0dVcE9uUjlablZ1WTNScGIyNGdZMjhvWlNsN2RtRnlJSFE5YVhRb0tTeHVQWFF1Y1hWbGRXVTdh'
    || 'V1lvYmowOVBXNTFiR3dwZEdoeWIzY2dSWEp5YjNJb1lTZ3pNVEVwS1R0dUxteGhjM1JTWlc1a1pYSmxaRkpsWkhWalpYSTlaVHQyWVhJZ2NqMTRaU3hzUFhJ'
    || 'dVltRnpaVkYxWlhWbExHazliaTV3Wlc1a2FXNW5PMmxtS0draFBUMXVkV3hzS1h0cFppaHNJVDA5Ym5Wc2JDbDdkbUZ5SUc4OWJDNXVaWGgwTzJ3dWJtVjRk'
    || 'RDFwTG01bGVIUXNhUzV1WlhoMFBXOTljaTVpWVhObFVYVmxkV1U5YkQxcExHNHVjR1Z1WkdsdVp6MXVkV3hzZldsbUtHd2hQVDF1ZFd4c0tYdHBQV3d1Ym1W'
    || 'NGRDeHlQWEl1WW1GelpWTjBZWFJsTzNaaGNpQmpQVzg5Ym5Wc2JDeGtQVzUxYkd3c1p6MXBPMlJ2ZTNaaGNpQkZQV2N1YkdGdVpUdHBaaWdvWTI0bVJTazlQ'
    || 'VDFGS1dRaFBUMXVkV3hzSmlZb1pEMWtMbTVsZUhROWUyeGhibVU2TUN4aFkzUnBiMjQ2Wnk1aFkzUnBiMjRzYUdGelJXRm5aWEpUZEdGMFpUcG5MbWhoYzBW'
    || 'aFoyVnlVM1JoZEdVc1pXRm5aWEpUZEdGMFpUcG5MbVZoWjJWeVUzUmhkR1VzYm1WNGREcHVkV3hzZlNrc2NqMW5MbWhoYzBWaFoyVnlVM1JoZEdVL1p5NWxZ'
    || 'V2RsY2xOMFlYUmxPbVVvY2l4bkxtRmpkR2x2YmlrN1pXeHpaWHQyWVhJZ2FqMTdiR0Z1WlRwRkxHRmpkR2x2YmpwbkxtRmpkR2x2Yml4b1lYTkZZV2RsY2xO'
    || 'MFlYUmxPbWN1YUdGelJXRm5aWEpUZEdGMFpTeGxZV2RsY2xOMFlYUmxPbWN1WldGblpYSlRkR0YwWlN4dVpYaDBPbTUxYkd4OU8yUTlQVDF1ZFd4c1B5aGpQ'
    || 'V1E5YWl4dlBYSXBPbVE5WkM1dVpYaDBQV29zWm1VdWJHRnVaWE44UFVVc1pHNThQVVY5WnoxbkxtNWxlSFI5ZDJocGJHVW9aeUU5UFc1MWJHd21KbWNoUFQx'
    || 'cEtUdGtQVDA5Ym5Wc2JEOXZQWEk2WkM1dVpYaDBQV01zWkhRb2NpeDBMbTFsYlc5cGVtVmtVM1JoZEdVcGZId29WbVU5SVRBcExIUXViV1Z0YjJsNlpXUlRk'
    || 'R0YwWlQxeUxIUXVZbUZ6WlZOMFlYUmxQVzhzZEM1aVlYTmxVWFZsZFdVOVpDeHVMbXhoYzNSU1pXNWtaWEpsWkZOMFlYUmxQWEo5YVdZb1pUMXVMbWx1ZEdW'
    || 'eWJHVmhkbVZrTEdVaFBUMXVkV3hzS1h0c1BXVTdaRzhnYVQxc0xteGhibVVzWm1VdWJHRnVaWE44UFdrc1pHNThQV2tzYkQxc0xtNWxlSFE3ZDJocGJHVW9i'
    || 'Q0U5UFdVcGZXVnNjMlVnYkQwOVBXNTFiR3dtSmlodUxteGhibVZ6UFRBcE8zSmxkSFZ5Ymx0MExtMWxiVzlwZW1Wa1UzUmhkR1VzYmk1a2FYTndZWFJqYUYx'
    || 'OVpuVnVZM1JwYjI0Z1ptOG9aU2w3ZG1GeUlIUTlhWFFvS1N4dVBYUXVjWFZsZFdVN2FXWW9iajA5UFc1MWJHd3BkR2h5YjNjZ1JYSnliM0lvWVNnek1URXBL'
    || 'VHR1TG14aGMzUlNaVzVrWlhKbFpGSmxaSFZqWlhJOVpUdDJZWElnY2oxdUxtUnBjM0JoZEdOb0xHdzliaTV3Wlc1a2FXNW5MR2s5ZEM1dFpXMXZhWHBsWkZO'
    || 'MFlYUmxPMmxtS0d3aFBUMXVkV3hzS1h0dUxuQmxibVJwYm1jOWJuVnNiRHQyWVhJZ2J6MXNQV3d1Ym1WNGREdGtieUJwUFdVb2FTeHZMbUZqZEdsdmJpa3Ni'
    || 'ejF2TG01bGVIUTdkMmhwYkdVb2J5RTlQV3dwTzJSMEtHa3NkQzV0WlcxdmFYcGxaRk4wWVhSbEtYeDhLRlpsUFNFd0tTeDBMbTFsYlc5cGVtVmtVM1JoZEdV'
    || 'OWFTeDBMbUpoYzJWUmRXVjFaVDA5UFc1MWJHd21KaWgwTG1KaGMyVlRkR0YwWlQxcEtTeHVMbXhoYzNSU1pXNWtaWEpsWkZOMFlYUmxQV2w5Y21WMGRYSnVX'
    || 'MmtzY2wxOVpuVnVZM1JwYjI0Z1VYVW9LWHQ5Wm5WdVkzUnBiMjRnV1hVb1pTeDBLWHQyWVhJZ2JqMW1aU3h5UFdsMEtDa3NiRDEwS0Nrc2FUMGhaSFFvY2k1'
    || 'dFpXMXZhWHBsWkZOMFlYUmxMR3dwTzJsbUtHa21KaWh5TG0xbGJXOXBlbVZrVTNSaGRHVTliQ3hXWlQwaE1Da3NjajF5TG5GMVpYVmxMSEJ2S0ZoMUxtSnBi'
    || 'bVFvYm5Wc2JDeHVMSElzWlNrc1cyVmRLU3h5TG1kbGRGTnVZWEJ6YUc5MElUMDlkSHg4YVh4OFgyVWhQVDF1ZFd4c0ppWmZaUzV0WlcxdmFYcGxaRk4wWVhS'
    || 'bExuUmhaeVl4S1h0cFppaHVMbVpzWVdkemZEMHlNRFE0TEY5eUtEa3NSM1V1WW1sdVpDaHVkV3hzTEc0c2NpeHNMSFFwTEhadmFXUWdNQ3h1ZFd4c0tTeHJa'
    || 'VDA5UFc1MWJHd3BkR2h5YjNjZ1JYSnliM0lvWVNnek5Ea3BLVHNvWTI0bU16QXBJVDA5TUh4OFMzVW9iaXgwTEd3cGZYSmxkSFZ5YmlCc2ZXWjFibU4wYVc5'
    || 'dUlFdDFLR1VzZEN4dUtYdGxMbVpzWVdkemZEMHhOak00TkN4bFBYdG5aWFJUYm1Gd2MyaHZkRHAwTEhaaGJIVmxPbTU5TEhROVptVXVkWEJrWVhSbFVYVmxk'
    || 'V1VzZEQwOVBXNTFiR3cvS0hROWUyeGhjM1JGWm1abFkzUTZiblZzYkN4emRHOXlaWE02Ym5Wc2JIMHNabVV1ZFhCa1lYUmxVWFZsZFdVOWRDeDBMbk4wYjNK'
    || 'bGN6MWJaVjBwT2lodVBYUXVjM1J2Y21WekxHNDlQVDF1ZFd4c1AzUXVjM1J2Y21WelBWdGxYVHB1TG5CMWMyZ29aU2twZldaMWJtTjBhVzl1SUVkMUtHVXNk'
    || 'Q3h1TEhJcGUzUXVkbUZzZFdVOWJpeDBMbWRsZEZOdVlYQnphRzkwUFhJc1duVW9kQ2ttSmtwMUtHVXBmV1oxYm1OMGFXOXVJRmgxS0dVc2RDeHVLWHR5WlhS'
    || 'MWNtNGdiaWhtZFc1amRHbHZiaWdwZTFwMUtIUXBKaVpLZFNobEtYMHBmV1oxYm1OMGFXOXVJRnAxS0dVcGUzWmhjaUIwUFdVdVoyVjBVMjVoY0hOb2IzUTda'
    || 'VDFsTG5aaGJIVmxPM1J5ZVh0MllYSWdiajEwS0NrN2NtVjBkWEp1SVdSMEtHVXNiaWw5WTJGMFkyaDdjbVYwZFhKdUlUQjlmV1oxYm1OMGFXOXVJRXAxS0dV'
    || 'cGUzWmhjaUIwUFUxMEtHVXNNU2s3ZENFOVBXNTFiR3dtSm5aMEtIUXNaU3d4TEMweEtYMW1kVzVqZEdsdmJpQnhkU2hsS1h0MllYSWdkRDFyZENncE8zSmxk'
    || 'SFZ5YmlCMGVYQmxiMllnWlQwOUltWjFibU4wYVc5dUlpWW1LR1U5WlNncEtTeDBMbTFsYlc5cGVtVmtVM1JoZEdVOWRDNWlZWE5sVTNSaGRHVTlaU3hsUFh0'
    || 'd1pXNWthVzVuT201MWJHd3NhVzUwWlhKc1pXRjJaV1E2Ym5Wc2JDeHNZVzVsY3pvd0xHUnBjM0JoZEdOb09tNTFiR3dzYkdGemRGSmxibVJsY21Wa1VtVmtk'
    || 'V05sY2pwVGNpeHNZWE4wVW1WdVpHVnlaV1JUZEdGMFpUcGxmU3gwTG5GMVpYVmxQV1VzWlQxbExtUnBjM0JoZEdOb1BVMW1MbUpwYm1Rb2JuVnNiQ3htWlN4'
    || 'bEtTeGJkQzV0WlcxdmFYcGxaRk4wWVhSbExHVmRmV1oxYm1OMGFXOXVJRjl5S0dVc2RDeHVMSElwZTNKbGRIVnliaUJsUFh0MFlXYzZaU3hqY21WaGRHVTZk'
    || 'Q3hrWlhOMGNtOTVPbTRzWkdWd2N6cHlMRzVsZUhRNmJuVnNiSDBzZEQxbVpTNTFjR1JoZEdWUmRXVjFaU3gwUFQwOWJuVnNiRDhvZEQxN2JHRnpkRVZtWm1W'
    || 'amREcHVkV3hzTEhOMGIzSmxjenB1ZFd4c2ZTeG1aUzUxY0dSaGRHVlJkV1YxWlQxMExIUXViR0Z6ZEVWbVptVmpkRDFsTG01bGVIUTlaU2s2S0c0OWRDNXNZ'
    || 'WE4wUldabVpXTjBMRzQ5UFQxdWRXeHNQM1F1YkdGemRFVm1abVZqZEQxbExtNWxlSFE5WlRvb2NqMXVMbTVsZUhRc2JpNXVaWGgwUFdVc1pTNXVaWGgwUFhJ'
    || 'c2RDNXNZWE4wUldabVpXTjBQV1VwS1N4bGZXWjFibU4wYVc5dUlHSjFLQ2w3Y21WMGRYSnVJR2wwS0NrdWJXVnRiMmw2WldSVGRHRjBaWDFtZFc1amRHbHZi'
    || 'aUJuYkNobExIUXNiaXh5S1h0MllYSWdiRDFyZENncE8yWmxMbVpzWVdkemZEMWxMR3d1YldWdGIybDZaV1JUZEdGMFpUMWZjaWd4ZkhRc2JpeDJiMmxrSURB'
    || 'c2NqMDlQWFp2YVdRZ01EOXVkV3hzT25JcGZXWjFibU4wYVc5dUlIbHNLR1VzZEN4dUxISXBlM1poY2lCc1BXbDBLQ2s3Y2oxeVBUMDlkbTlwWkNBd1AyNTFi'
    || 'R3c2Y2p0MllYSWdhVDEyYjJsa0lEQTdhV1lvZUdVaFBUMXVkV3hzS1h0MllYSWdiejE0WlM1dFpXMXZhWHBsWkZOMFlYUmxPMmxtS0drOWJ5NWtaWE4wY205'
    || 'NUxISWhQVDF1ZFd4c0ppWnpieWh5TEc4dVpHVndjeWtwZTJ3dWJXVnRiMmw2WldSVGRHRjBaVDFmY2loMExHNHNhU3h5S1R0eVpYUjFjbTU5ZldabExtWnNZ'
    || 'V2R6ZkQxbExHd3ViV1Z0YjJsNlpXUlRkR0YwWlQxZmNpZ3hmSFFzYml4cExISXBmV1oxYm1OMGFXOXVJR1ZoS0dVc2RDbDdjbVYwZFhKdUlHZHNLRGd6T1RB'
    || 'Mk5UWXNPQ3hsTEhRcGZXWjFibU4wYVc5dUlIQnZLR1VzZENsN2NtVjBkWEp1SUhsc0tESXdORGdzT0N4bExIUXBmV1oxYm1OMGFXOXVJSFJoS0dVc2RDbDdj'
    || 'bVYwZFhKdUlIbHNLRFFzTWl4bExIUXBmV1oxYm1OMGFXOXVJRzVoS0dVc2RDbDdjbVYwZFhKdUlIbHNLRFFzTkN4bExIUXBmV1oxYm1OMGFXOXVJSEpoS0dV'
    || 'c2RDbDdhV1lvZEhsd1pXOW1JSFE5UFNKbWRXNWpkR2x2YmlJcGNtVjBkWEp1SUdVOVpTZ3BMSFFvWlNrc1puVnVZM1JwYjI0b0tYdDBLRzUxYkd3cGZUdHBa'
    || 'aWgwSVQxdWRXeHNLWEpsZEhWeWJpQmxQV1VvS1N4MExtTjFjbkpsYm5ROVpTeG1kVzVqZEdsdmJpZ3BlM1F1WTNWeWNtVnVkRDF1ZFd4c2ZYMW1kVzVqZEds'
    || 'dmJpQnNZU2hsTEhRc2JpbDdjbVYwZFhKdUlHNDliaUU5Ym5Wc2JEOXVMbU52Ym1OaGRDaGJaVjBwT201MWJHd3NlV3dvTkN3MExISmhMbUpwYm1Rb2JuVnNi'
    || 'Q3gwTEdVcExHNHBmV1oxYm1OMGFXOXVJR2h2S0NsN2ZXWjFibU4wYVc5dUlHbGhLR1VzZENsN2RtRnlJRzQ5YVhRb0tUdDBQWFE5UFQxMmIybGtJREEvYm5W'
    || 'c2JEcDBPM1poY2lCeVBXNHViV1Z0YjJsNlpXUlRkR0YwWlR0eVpYUjFjbTRnY2lFOVBXNTFiR3dtSm5RaFBUMXVkV3hzSmlaemJ5aDBMSEpiTVYwcFAzSmJN'
    || 'RjA2S0c0dWJXVnRiMmw2WldSVGRHRjBaVDFiWlN4MFhTeGxLWDFtZFc1amRHbHZiaUJ2WVNobExIUXBlM1poY2lCdVBXbDBLQ2s3ZEQxMFBUMDlkbTlwWkNB'
    || 'd1AyNTFiR3c2ZER0MllYSWdjajF1TG0xbGJXOXBlbVZrVTNSaGRHVTdjbVYwZFhKdUlISWhQVDF1ZFd4c0ppWjBJVDA5Ym5Wc2JDWW1jMjhvZEN4eVd6RmRL'
    || 'VDl5V3pCZE9paGxQV1VvS1N4dUxtMWxiVzlwZW1Wa1UzUmhkR1U5VzJVc2RGMHNaU2w5Wm5WdVkzUnBiMjRnYzJFb1pTeDBMRzRwZTNKbGRIVnliaWhqYmlZ'
    || 'eU1TazlQVDB3UHlobExtSmhjMlZUZEdGMFpTWW1LR1V1WW1GelpWTjBZWFJsUFNFeExGWmxQU0V3S1N4bExtMWxiVzlwZW1Wa1UzUmhkR1U5YmlrNktHUjBL'
    || 'RzRzZENsOGZDaHVQVUZ6S0Nrc1ptVXViR0Z1WlhOOFBXNHNaRzU4UFc0c1pTNWlZWE5sVTNSaGRHVTlJVEFwTEhRcGZXWjFibU4wYVc5dUlFeG1LR1VzZENs'
    || 'N2RtRnlJRzQ5Ym1VN2JtVTliaUU5UFRBbUpqUStiajl1T2pRc1pTZ2hNQ2s3ZG1GeUlISTliMjh1ZEhKaGJuTnBkR2x2Ymp0dmJ5NTBjbUZ1YzJsMGFXOXVQ'
    || 'WHQ5TzNSeWVYdGxLQ0V4S1N4MEtDbDlabWx1WVd4c2VYdHVaVDF1TEc5dkxuUnlZVzV6YVhScGIyNDljbjE5Wm5WdVkzUnBiMjRnZFdFb0tYdHlaWFIxY200'
    || 'Z2FYUW9LUzV0WlcxdmFYcGxaRk4wWVhSbGZXWjFibU4wYVc5dUlGSm1LR1VzZEN4dUtYdDJZWElnY2oxS2RDaGxLVHRwWmlodVBYdHNZVzVsT25Jc1lXTjBh'
    || 'Vzl1T200c2FHRnpSV0ZuWlhKVGRHRjBaVG9oTVN4bFlXZGxjbE4wWVhSbE9tNTFiR3dzYm1WNGREcHVkV3hzZlN4aFlTaGxLU2xqWVNoMExHNHBPMlZzYzJV'
    || 'Z2FXWW9iajFJZFNobExIUXNiaXh5S1N4dUlUMDliblZzYkNsN2RtRnlJR3c5UkdVb0tUdDJkQ2h1TEdVc2NpeHNLU3hrWVNodUxIUXNjaWw5ZldaMWJtTjBh'
    || 'Vzl1SUUxbUtHVXNkQ3h1S1h0MllYSWdjajFLZENobEtTeHNQWHRzWVc1bE9uSXNZV04wYVc5dU9tNHNhR0Z6UldGblpYSlRkR0YwWlRvaE1TeGxZV2RsY2xO'
    || 'MFlYUmxPbTUxYkd3c2JtVjRkRHB1ZFd4c2ZUdHBaaWhoWVNobEtTbGpZU2gwTEd3cE8yVnNjMlY3ZG1GeUlHazlaUzVoYkhSbGNtNWhkR1U3YVdZb1pTNXNZ'
    || 'VzVsY3owOVBUQW1KaWhwUFQwOWJuVnNiSHg4YVM1c1lXNWxjejA5UFRBcEppWW9hVDEwTG14aGMzUlNaVzVrWlhKbFpGSmxaSFZqWlhJc2FTRTlQVzUxYkd3'
    || 'cEtYUnllWHQyWVhJZ2J6MTBMbXhoYzNSU1pXNWtaWEpsWkZOMFlYUmxMR005YVNodkxHNHBPMmxtS0d3dWFHRnpSV0ZuWlhKVGRHRjBaVDBoTUN4c0xtVmha'
    || 'MlZ5VTNSaGRHVTlZeXhrZENoakxHOHBLWHQyWVhJZ1pEMTBMbWx1ZEdWeWJHVmhkbVZrTzJROVBUMXVkV3hzUHloc0xtNWxlSFE5YkN4bGJ5aDBLU2s2S0d3'
    || 'dWJtVjRkRDFrTG01bGVIUXNaQzV1WlhoMFBXd3BMSFF1YVc1MFpYSnNaV0YyWldROWJEdHlaWFIxY201OWZXTmhkR05vZTMxbWFXNWhiR3g1ZTMxdVBVaDFL'
    || 'R1VzZEN4c0xISXBMRzRoUFQxdWRXeHNKaVlvYkQxRVpTZ3BMSFowS0c0c1pTeHlMR3dwTEdSaEtHNHNkQ3h5S1NsOWZXWjFibU4wYVc5dUlHRmhLR1VwZTNa'
    || 'aGNpQjBQV1V1WVd4MFpYSnVZWFJsTzNKbGRIVnliaUJsUFQwOVptVjhmSFFoUFQxdWRXeHNKaVowUFQwOVptVjlablZ1WTNScGIyNGdZMkVvWlN4MEtYdDRj'
    || 'ajEyYkQwaE1EdDJZWElnYmoxbExuQmxibVJwYm1jN2JqMDlQVzUxYkd3L2RDNXVaWGgwUFhRNktIUXVibVY0ZEQxdUxtNWxlSFFzYmk1dVpYaDBQWFFwTEdV'
    || 'dWNHVnVaR2x1WnoxMGZXWjFibU4wYVc5dUlHUmhLR1VzZEN4dUtYdHBaaWdvYmlZME1UazBNalF3S1NFOVBUQXBlM1poY2lCeVBYUXViR0Z1WlhNN2NpWTla'
    || 'UzV3Wlc1a2FXNW5UR0Z1WlhNc2JudzljaXgwTG14aGJtVnpQVzRzYldrb1pTeHVLWDE5ZG1GeUlIaHNQWHR5WldGa1EyOXVkR1Y0ZERwc2RDeDFjMlZEWVd4'
    || 'c1ltRmphenBOWlN4MWMyVkRiMjUwWlhoME9rMWxMSFZ6WlVWbVptVmpkRHBOWlN4MWMyVkpiWEJsY21GMGFYWmxTR0Z1Wkd4bE9rMWxMSFZ6WlVsdWMyVnlk'
    || 'R2x2YmtWbVptVmpkRHBOWlN4MWMyVk1ZWGx2ZFhSRlptWmxZM1E2VFdVc2RYTmxUV1Z0YnpwTlpTeDFjMlZTWldSMVkyVnlPazFsTEhWelpWSmxaanBOWlN4'
    || 'MWMyVlRkR0YwWlRwTlpTeDFjMlZFWldKMVoxWmhiSFZsT2sxbExIVnpaVVJsWm1WeWNtVmtWbUZzZFdVNlRXVXNkWE5sVkhKaGJuTnBkR2x2YmpwTlpTeDFj'
    || 'MlZOZFhSaFlteGxVMjkxY21ObE9rMWxMSFZ6WlZONWJtTkZlSFJsY201aGJGTjBiM0psT2sxbExIVnpaVWxrT2sxbExIVnVjM1JoWW14bFgybHpUbVYzVW1W'
    || 'amIyNWphV3hsY2pvaE1YMHNVR1k5ZTNKbFlXUkRiMjUwWlhoME9teDBMSFZ6WlVOaGJHeGlZV05yT21aMWJtTjBhVzl1S0dVc2RDbDdjbVYwZFhKdUlHdDBL'
    || 'Q2t1YldWdGIybDZaV1JUZEdGMFpUMWJaU3gwUFQwOWRtOXBaQ0F3UDI1MWJHdzZkRjBzWlgwc2RYTmxRMjl1ZEdWNGREcHNkQ3gxYzJWRlptWmxZM1E2WldF'
    || 'c2RYTmxTVzF3WlhKaGRHbDJaVWhoYm1Sc1pUcG1kVzVqZEdsdmJpaGxMSFFzYmlsN2NtVjBkWEp1SUc0OWJpRTliblZzYkQ5dUxtTnZibU5oZENoYlpWMHBP'
    || 'bTUxYkd3c1oyd29OREU1TkRNd09DdzBMSEpoTG1KcGJtUW9iblZzYkN4MExHVXBMRzRwZlN4MWMyVk1ZWGx2ZFhSRlptWmxZM1E2Wm5WdVkzUnBiMjRvWlN4'
    || 'MEtYdHlaWFIxY200Z1oyd29OREU1TkRNd09DdzBMR1VzZENsOUxIVnpaVWx1YzJWeWRHbHZia1ZtWm1WamREcG1kVzVqZEdsdmJpaGxMSFFwZTNKbGRIVnli'
    || 'aUJuYkNnMExESXNaU3gwS1gwc2RYTmxUV1Z0YnpwbWRXNWpkR2x2YmlobExIUXBlM1poY2lCdVBXdDBLQ2s3Y21WMGRYSnVJSFE5ZEQwOVBYWnZhV1FnTUQ5'
    || 'dWRXeHNPblFzWlQxbEtDa3NiaTV0WlcxdmFYcGxaRk4wWVhSbFBWdGxMSFJkTEdWOUxIVnpaVkpsWkhWalpYSTZablZ1WTNScGIyNG9aU3gwTEc0cGUzWmhj'
    || 'aUJ5UFd0MEtDazdjbVYwZFhKdUlIUTliaUU5UFhadmFXUWdNRDl1S0hRcE9uUXNjaTV0WlcxdmFYcGxaRk4wWVhSbFBYSXVZbUZ6WlZOMFlYUmxQWFFzWlQx'
    || 'N2NHVnVaR2x1WnpwdWRXeHNMR2x1ZEdWeWJHVmhkbVZrT201MWJHd3NiR0Z1WlhNNk1DeGthWE53WVhSamFEcHVkV3hzTEd4aGMzUlNaVzVrWlhKbFpGSmxa'
    || 'SFZqWlhJNlpTeHNZWE4wVW1WdVpHVnlaV1JUZEdGMFpUcDBmU3h5TG5GMVpYVmxQV1VzWlQxbExtUnBjM0JoZEdOb1BWSm1MbUpwYm1Rb2JuVnNiQ3htWlN4'
    || 'bEtTeGJjaTV0WlcxdmFYcGxaRk4wWVhSbExHVmRmU3gxYzJWU1pXWTZablZ1WTNScGIyNG9aU2w3ZG1GeUlIUTlhM1FvS1R0eVpYUjFjbTRnWlQxN1kzVnlj'
    || 'bVZ1ZERwbGZTeDBMbTFsYlc5cGVtVmtVM1JoZEdVOVpYMHNkWE5sVTNSaGRHVTZjWFVzZFhObFJHVmlkV2RXWVd4MVpUcG9ieXgxYzJWRVpXWmxjbkpsWkZa'
    || 'aGJIVmxPbVoxYm1OMGFXOXVLR1VwZTNKbGRIVnliaUJyZENncExtMWxiVzlwZW1Wa1UzUmhkR1U5Wlgwc2RYTmxWSEpoYm5OcGRHbHZianBtZFc1amRHbHZi'
    || 'aWdwZTNaaGNpQmxQWEYxS0NFeEtTeDBQV1ZiTUYwN2NtVjBkWEp1SUdVOVRHWXVZbWx1WkNodWRXeHNMR1ZiTVYwcExHdDBLQ2t1YldWdGIybDZaV1JUZEdG'
    || 'MFpUMWxMRnQwTEdWZGZTeDFjMlZOZFhSaFlteGxVMjkxY21ObE9tWjFibU4wYVc5dUtDbDdmU3gxYzJWVGVXNWpSWGgwWlhKdVlXeFRkRzl5WlRwbWRXNWpk'
    || 'R2x2YmlobExIUXNiaWw3ZG1GeUlISTlabVVzYkQxcmRDZ3BPMmxtS0dObEtYdHBaaWh1UFQwOWRtOXBaQ0F3S1hSb2NtOTNJRVZ5Y205eUtHRW9OREEzS1Nr'
    || 'N2JqMXVLQ2w5Wld4elpYdHBaaWh1UFhRb0tTeHJaVDA5UFc1MWJHd3BkR2h5YjNjZ1JYSnliM0lvWVNnek5Ea3BLVHNvWTI0bU16QXBJVDA5TUh4OFMzVW9j'
    || 'aXgwTEc0cGZXd3ViV1Z0YjJsNlpXUlRkR0YwWlQxdU8zWmhjaUJwUFh0MllXeDFaVHB1TEdkbGRGTnVZWEJ6YUc5ME9uUjlPM0psZEhWeWJpQnNMbkYxWlhW'
    || 'bFBXa3NaV0VvV0hVdVltbHVaQ2h1ZFd4c0xISXNhU3hsS1N4YlpWMHBMSEl1Wm14aFozTjhQVEl3TkRnc1gzSW9PU3hIZFM1aWFXNWtLRzUxYkd3c2NpeHBM'
    || 'RzRzZENrc2RtOXBaQ0F3TEc1MWJHd3BMRzU5TEhWelpVbGtPbVoxYm1OMGFXOXVLQ2w3ZG1GeUlHVTlhM1FvS1N4MFBXdGxMbWxrWlc1MGFXWnBaWEpRY21W'
    || 'bWFYZzdhV1lvWTJVcGUzWmhjaUJ1UFZKMExISTlUSFE3Ymowb2NpWitLREU4UERNeUxXTjBLSElwTFRFcEtTNTBiMU4wY21sdVp5Z3pNaWtyYml4MFBTSTZJ'
    || 'aXQwS3lKU0lpdHVMRzQ5ZDNJckt5d3dQRzRtSmloMEt6MGlTQ0lyYmk1MGIxTjBjbWx1Wnlnek1pa3BMSFFyUFNJNkluMWxiSE5sSUc0OVEyWXJLeXgwUFNJ'
    || 'NklpdDBLeUp5SWl0dUxuUnZVM1J5YVc1bktETXlLU3NpT2lJN2NtVjBkWEp1SUdVdWJXVnRiMmw2WldSVGRHRjBaVDEwZlN4MWJuTjBZV0pzWlY5cGMwNWxk'
    || 'MUpsWTI5dVkybHNaWEk2SVRGOUxFOW1QWHR5WldGa1EyOXVkR1Y0ZERwc2RDeDFjMlZEWVd4c1ltRmphenBwWVN4MWMyVkRiMjUwWlhoME9teDBMSFZ6WlVW'
    || 'bVptVmpkRHB3Ynl4MWMyVkpiWEJsY21GMGFYWmxTR0Z1Wkd4bE9teGhMSFZ6WlVsdWMyVnlkR2x2YmtWbVptVmpkRHAwWVN4MWMyVk1ZWGx2ZFhSRlptWmxZ'
    || 'M1E2Ym1Fc2RYTmxUV1Z0YnpwdllTeDFjMlZTWldSMVkyVnlPbU52TEhWelpWSmxaanBpZFN4MWMyVlRkR0YwWlRwbWRXNWpkR2x2YmlncGUzSmxkSFZ5YmlC'
    || 'amJ5aFRjaWw5TEhWelpVUmxZblZuVm1Gc2RXVTZhRzhzZFhObFJHVm1aWEp5WldSV1lXeDFaVHBtZFc1amRHbHZiaWhsS1h0MllYSWdkRDFwZENncE8zSmxk'
    || 'SFZ5YmlCellTaDBMSGhsTG0xbGJXOXBlbVZrVTNSaGRHVXNaU2w5TEhWelpWUnlZVzV6YVhScGIyNDZablZ1WTNScGIyNG9LWHQyWVhJZ1pUMWpieWhUY2ls'
    || 'Yk1GMHNkRDFwZENncExtMWxiVzlwZW1Wa1UzUmhkR1U3Y21WMGRYSnVXMlVzZEYxOUxIVnpaVTExZEdGaWJHVlRiM1Z5WTJVNlVYVXNkWE5sVTNsdVkwVjRk'
    || 'R1Z5Ym1Gc1UzUnZjbVU2V1hVc2RYTmxTV1E2ZFdFc2RXNXpkR0ZpYkdWZmFYTk9aWGRTWldOdmJtTnBiR1Z5T2lFeGZTeEpaajE3Y21WaFpFTnZiblJsZUhR'
    || 'NmJIUXNkWE5sUTJGc2JHSmhZMnM2YVdFc2RYTmxRMjl1ZEdWNGREcHNkQ3gxYzJWRlptWmxZM1E2Y0c4c2RYTmxTVzF3WlhKaGRHbDJaVWhoYm1Sc1pUcHNZ'
    || 'U3gxYzJWSmJuTmxjblJwYjI1RlptWmxZM1E2ZEdFc2RYTmxUR0Y1YjNWMFJXWm1aV04wT201aExIVnpaVTFsYlc4NmIyRXNkWE5sVW1Wa2RXTmxjanBtYnl4'
    || 'MWMyVlNaV1k2WW5Vc2RYTmxVM1JoZEdVNlpuVnVZM1JwYjI0b0tYdHlaWFIxY200Z1ptOG9VM0lwZlN4MWMyVkVaV0oxWjFaaGJIVmxPbWh2TEhWelpVUmxa'
    || 'bVZ5Y21Wa1ZtRnNkV1U2Wm5WdVkzUnBiMjRvWlNsN2RtRnlJSFE5YVhRb0tUdHlaWFIxY200Z2VHVTlQVDF1ZFd4c1AzUXViV1Z0YjJsNlpXUlRkR0YwWlQx'
    || 'bE9uTmhLSFFzZUdVdWJXVnRiMmw2WldSVGRHRjBaU3hsS1gwc2RYTmxWSEpoYm5OcGRHbHZianBtZFc1amRHbHZiaWdwZTNaaGNpQmxQV1p2S0ZOeUtWc3dY'
    || 'U3gwUFdsMEtDa3ViV1Z0YjJsNlpXUlRkR0YwWlR0eVpYUjFjbTViWlN4MFhYMHNkWE5sVFhWMFlXSnNaVk52ZFhKalpUcFJkU3gxYzJWVGVXNWpSWGgwWlhK'
    || 'dVlXeFRkRzl5WlRwWmRTeDFjMlZKWkRwMVlTeDFibk4wWVdKc1pWOXBjMDVsZDFKbFkyOXVZMmxzWlhJNklURjlPMloxYm1OMGFXOXVJSEIwS0dVc2RDbDdh'
    || 'V1lvWlNZbVpTNWtaV1poZFd4MFVISnZjSE1wZTNROVR5aDdmU3gwS1N4bFBXVXVaR1ZtWVhWc2RGQnliM0J6TzJadmNpaDJZWElnYmlCcGJpQmxLWFJiYmww'
    || 'OVBUMTJiMmxrSURBbUppaDBXMjVkUFdWYmJsMHBPM0psZEhWeWJpQjBmWEpsZEhWeWJpQjBmV1oxYm1OMGFXOXVJRzF2S0dVc2RDeHVMSElwZTNROVpTNXRa'
    || 'VzF2YVhwbFpGTjBZWFJsTEc0OWJpaHlMSFFwTEc0OWJqMDliblZzYkQ5ME9rOG9lMzBzZEN4dUtTeGxMbTFsYlc5cGVtVmtVM1JoZEdVOWJpeGxMbXhoYm1W'
    || 'elBUMDlNQ1ltS0dVdWRYQmtZWFJsVVhWbGRXVXVZbUZ6WlZOMFlYUmxQVzRwZlhaaGNpQjNiRDE3YVhOTmIzVnVkR1ZrT21aMWJtTjBhVzl1S0dVcGUzSmxk'
    || 'SFZ5YmlobFBXVXVYM0psWVdOMFNXNTBaWEp1WVd4ektUOXViaWhsS1QwOVBXVTZJVEY5TEdWdWNYVmxkV1ZUWlhSVGRHRjBaVHBtZFc1amRHbHZiaWhsTEhR'
    || 'c2JpbDdaVDFsTGw5eVpXRmpkRWx1ZEdWeWJtRnNjenQyWVhJZ2NqMUVaU2dwTEd3OVNuUW9aU2tzYVQxUWRDaHlMR3dwTzJrdWNHRjViRzloWkQxMExHNGhQ'
    || 'VzUxYkd3bUppaHBMbU5oYkd4aVlXTnJQVzRwTEhROVMzUW9aU3hwTEd3cExIUWhQVDF1ZFd4c0ppWW9kblFvZEN4bExHd3NjaWtzWm13b2RDeGxMR3dwS1gw'
    || 'c1pXNXhkV1YxWlZKbGNHeGhZMlZUZEdGMFpUcG1kVzVqZEdsdmJpaGxMSFFzYmlsN1pUMWxMbDl5WldGamRFbHVkR1Z5Ym1Gc2N6dDJZWElnY2oxRVpTZ3BM'
    || 'R3c5U25Rb1pTa3NhVDFRZENoeUxHd3BPMmt1ZEdGblBURXNhUzV3WVhsc2IyRmtQWFFzYmlFOWJuVnNiQ1ltS0drdVkyRnNiR0poWTJzOWJpa3NkRDFMZENo'
    || 'bExHa3NiQ2tzZENFOVBXNTFiR3dtSmloMmRDaDBMR1VzYkN4eUtTeG1iQ2gwTEdVc2JDa3BmU3hsYm5GMVpYVmxSbTl5WTJWVmNHUmhkR1U2Wm5WdVkzUnBi'
    || 'MjRvWlN4MEtYdGxQV1V1WDNKbFlXTjBTVzUwWlhKdVlXeHpPM1poY2lCdVBVUmxLQ2tzY2oxS2RDaGxLU3hzUFZCMEtHNHNjaWs3YkM1MFlXYzlNaXgwSVQx'
    || 'dWRXeHNKaVlvYkM1allXeHNZbUZqYXoxMEtTeDBQVXQwS0dVc2JDeHlLU3gwSVQwOWJuVnNiQ1ltS0haMEtIUXNaU3h5TEc0cExHWnNLSFFzWlN4eUtTbDlm'
    || 'VHRtZFc1amRHbHZiaUJtWVNobExIUXNiaXh5TEd3c2FTeHZLWHR5WlhSMWNtNGdaVDFsTG5OMFlYUmxUbTlrWlN4MGVYQmxiMllnWlM1emFHOTFiR1JEYjIx'
    || 'd2IyNWxiblJWY0dSaGRHVTlQU0ptZFc1amRHbHZiaUkvWlM1emFHOTFiR1JEYjIxd2IyNWxiblJWY0dSaGRHVW9jaXhwTEc4cE9uUXVjSEp2ZEc5MGVYQmxK'
    || 'aVowTG5CeWIzUnZkSGx3WlM1cGMxQjFjbVZTWldGamRFTnZiWEJ2Ym1WdWREOGhkWElvYml4eUtYeDhJWFZ5S0d3c2FTazZJVEI5Wm5WdVkzUnBiMjRnY0dF'
    || 'b1pTeDBMRzRwZTNaaGNpQnlQU0V4TEd3OVFuUXNhVDEwTG1OdmJuUmxlSFJVZVhCbE8zSmxkSFZ5YmlCMGVYQmxiMllnYVQwOUltOWlhbVZqZENJbUpta2hQ'
    || 'VDF1ZFd4c1AyazliSFFvYVNrNktHdzlWMlVvZENrL2JHNDZVbVV1WTNWeWNtVnVkQ3h5UFhRdVkyOXVkR1Y0ZEZSNWNHVnpMR2s5S0hJOWNpRTliblZzYkNr'
    || 'L1VtNG9aU3hzS1RwQ2RDa3NkRDF1WlhjZ2RDaHVMR2twTEdVdWJXVnRiMmw2WldSVGRHRjBaVDEwTG5OMFlYUmxJVDA5Ym5Wc2JDWW1kQzV6ZEdGMFpTRTlQ'
    || 'WFp2YVdRZ01EOTBMbk4wWVhSbE9tNTFiR3dzZEM1MWNHUmhkR1Z5UFhkc0xHVXVjM1JoZEdWT2IyUmxQWFFzZEM1ZmNtVmhZM1JKYm5SbGNtNWhiSE05WlN4'
    || 'eUppWW9aVDFsTG5OMFlYUmxUbTlrWlN4bExsOWZjbVZoWTNSSmJuUmxjbTVoYkUxbGJXOXBlbVZrVlc1dFlYTnJaV1JEYUdsc1pFTnZiblJsZUhROWJDeGxM'
    || 'bDlmY21WaFkzUkpiblJsY201aGJFMWxiVzlwZW1Wa1RXRnphMlZrUTJocGJHUkRiMjUwWlhoMFBXa3BMSFI5Wm5WdVkzUnBiMjRnYUdFb1pTeDBMRzRzY2ls'
    || 'N1pUMTBMbk4wWVhSbExIUjVjR1Z2WmlCMExtTnZiWEJ2Ym1WdWRGZHBiR3hTWldObGFYWmxVSEp2Y0hNOVBTSm1kVzVqZEdsdmJpSW1KblF1WTI5dGNHOXVa'
    || 'VzUwVjJsc2JGSmxZMlZwZG1WUWNtOXdjeWh1TEhJcExIUjVjR1Z2WmlCMExsVk9VMEZHUlY5amIyMXdiMjVsYm5SWGFXeHNVbVZqWldsMlpWQnliM0J6UFQw'
    || 'aVpuVnVZM1JwYjI0aUppWjBMbFZPVTBGR1JWOWpiMjF3YjI1bGJuUlhhV3hzVW1WalpXbDJaVkJ5YjNCektHNHNjaWtzZEM1emRHRjBaU0U5UFdVbUpuZHNM'
    || 'bVZ1Y1hWbGRXVlNaWEJzWVdObFUzUmhkR1VvZEN4MExuTjBZWFJsTEc1MWJHd3BmV1oxYm1OMGFXOXVJSFp2S0dVc2RDeHVMSElwZTNaaGNpQnNQV1V1YzNS'
    || 'aGRHVk9iMlJsTzJ3dWNISnZjSE05Yml4c0xuTjBZWFJsUFdVdWJXVnRiMmw2WldSVGRHRjBaU3hzTG5KbFpuTTllMzBzZEc4b1pTazdkbUZ5SUdrOWRDNWpi'
    || 'MjUwWlhoMFZIbHdaVHQwZVhCbGIyWWdhVDA5SW05aWFtVmpkQ0ltSm1raFBUMXVkV3hzUDJ3dVkyOXVkR1Y0ZEQxc2RDaHBLVG9vYVQxWFpTaDBLVDlzYmpw'
    || 'U1pTNWpkWEp5Wlc1MExHd3VZMjl1ZEdWNGREMVNiaWhsTEdrcEtTeHNMbk4wWVhSbFBXVXViV1Z0YjJsNlpXUlRkR0YwWlN4cFBYUXVaMlYwUkdWeWFYWmxa'
    || 'Rk4wWVhSbFJuSnZiVkJ5YjNCekxIUjVjR1Z2WmlCcFBUMGlablZ1WTNScGIyNGlKaVlvYlc4b1pTeDBMR2tzYmlrc2JDNXpkR0YwWlQxbExtMWxiVzlwZW1W'
    || 'a1UzUmhkR1VwTEhSNWNHVnZaaUIwTG1kbGRFUmxjbWwyWldSVGRHRjBaVVp5YjIxUWNtOXdjejA5SW1aMWJtTjBhVzl1SW54OGRIbHdaVzltSUd3dVoyVjBV'
    || 'MjVoY0hOb2IzUkNaV1p2Y21WVmNHUmhkR1U5UFNKbWRXNWpkR2x2YmlKOGZIUjVjR1Z2WmlCc0xsVk9VMEZHUlY5amIyMXdiMjVsYm5SWGFXeHNUVzkxYm5R'
    || 'aFBTSm1kVzVqZEdsdmJpSW1KblI1Y0dWdlppQnNMbU52YlhCdmJtVnVkRmRwYkd4TmIzVnVkQ0U5SW1aMWJtTjBhVzl1SW54OEtIUTliQzV6ZEdGMFpTeDBl'
    || 'WEJsYjJZZ2JDNWpiMjF3YjI1bGJuUlhhV3hzVFc5MWJuUTlQU0ptZFc1amRHbHZiaUltSm13dVkyOXRjRzl1Wlc1MFYybHNiRTF2ZFc1MEtDa3NkSGx3Wlc5'
    || 'bUlHd3VWVTVUUVVaRlgyTnZiWEJ2Ym1WdWRGZHBiR3hOYjNWdWREMDlJbVoxYm1OMGFXOXVJaVltYkM1VlRsTkJSa1ZmWTI5dGNHOXVaVzUwVjJsc2JFMXZk'
    || 'VzUwS0Nrc2RDRTlQV3d1YzNSaGRHVW1KbmRzTG1WdWNYVmxkV1ZTWlhCc1lXTmxVM1JoZEdVb2JDeHNMbk4wWVhSbExHNTFiR3dwTEhCc0tHVXNiaXhzTEhJ'
    || 'cExHd3VjM1JoZEdVOVpTNXRaVzF2YVhwbFpGTjBZWFJsS1N4MGVYQmxiMllnYkM1amIyMXdiMjVsYm5SRWFXUk5iM1Z1ZEQwOUltWjFibU4wYVc5dUlpWW1L'
    || 'R1V1Wm14aFozTjhQVFF4T1RRek1EZ3BmV1oxYm1OMGFXOXVJRVp1S0dVc2RDbDdkSEo1ZTNaaGNpQnVQU0lpTEhJOWREdGtieUJ1S3oxS0tISXBMSEk5Y2k1'
    || 'eVpYUjFjbTQ3ZDJocGJHVW9jaWs3ZG1GeUlHdzlibjFqWVhSamFDaHBLWHRzUFdBS1JYSnliM0lnWjJWdVpYSmhkR2x1WnlCemRHRmphem9nWUN0cExtMWxj'
    || 'M05oWjJVcllBcGdLMmt1YzNSaFkydDljbVYwZFhKdWUzWmhiSFZsT21Vc2MyOTFjbU5sT25Rc2MzUmhZMnM2YkN4a2FXZGxjM1E2Ym5Wc2JIMTlablZ1WTNS'
    || 'cGIyNGdaMjhvWlN4MExHNHBlM0psZEhWeWJudDJZV3gxWlRwbExITnZkWEpqWlRwdWRXeHNMSE4wWVdOck9tNC9QMjUxYkd3c1pHbG5aWE4wT25RL1AyNTFi'
    || 'R3g5ZldaMWJtTjBhVzl1SUhsdktHVXNkQ2w3ZEhKNWUyTnZibk52YkdVdVpYSnliM0lvZEM1MllXeDFaU2w5WTJGMFkyZ29iaWw3YzJWMFZHbHRaVzkxZENo'
    || 'bWRXNWpkR2x2YmlncGUzUm9jbTkzSUc1OUtYMTlkbUZ5SUhwbVBYUjVjR1Z2WmlCWFpXRnJUV0Z3UFQwaVpuVnVZM1JwYjI0aVAxZGxZV3ROWVhBNlRXRndP'
    || 'MloxYm1OMGFXOXVJRzFoS0dVc2RDeHVLWHR1UFZCMEtDMHhMRzRwTEc0dWRHRm5QVE1zYmk1d1lYbHNiMkZrUFh0bGJHVnRaVzUwT201MWJHeDlPM1poY2lC'
    || 'eVBYUXVkbUZzZFdVN2NtVjBkWEp1SUc0dVkyRnNiR0poWTJzOVpuVnVZM1JwYjI0b0tYdFViSHg4S0ZSc1BTRXdMRTl2UFhJcExIbHZLR1VzZENsOUxHNTla'
    || 'blZ1WTNScGIyNGdkbUVvWlN4MExHNHBlMjQ5VUhRb0xURXNiaWtzYmk1MFlXYzlNenQyWVhJZ2NqMWxMblI1Y0dVdVoyVjBSR1Z5YVhabFpGTjBZWFJsUm5K'
    || 'dmJVVnljbTl5TzJsbUtIUjVjR1Z2WmlCeVBUMGlablZ1WTNScGIyNGlLWHQyWVhJZ2JEMTBMblpoYkhWbE8yNHVjR0Y1Ykc5aFpEMW1kVzVqZEdsdmJpZ3Bl'
    || 'M0psZEhWeWJpQnlLR3dwZlN4dUxtTmhiR3hpWVdOclBXWjFibU4wYVc5dUtDbDdlVzhvWlN4MEtYMTlkbUZ5SUdrOVpTNXpkR0YwWlU1dlpHVTdjbVYwZFhK'
    || 'dUlHa2hQVDF1ZFd4c0ppWjBlWEJsYjJZZ2FTNWpiMjF3YjI1bGJuUkVhV1JEWVhSamFEMDlJbVoxYm1OMGFXOXVJaVltS0c0dVkyRnNiR0poWTJzOVpuVnVZ'
    || 'M1JwYjI0b0tYdDVieWhsTEhRcExIUjVjR1Z2WmlCeUlUMGlablZ1WTNScGIyNGlKaVlvV0hROVBUMXVkV3hzUDFoMFBXNWxkeUJUWlhRb1czUm9hWE5kS1Rw'
    || 'WWRDNWhaR1FvZEdocGN5a3BPM1poY2lCdlBYUXVjM1JoWTJzN2RHaHBjeTVqYjIxd2IyNWxiblJFYVdSRFlYUmphQ2gwTG5aaGJIVmxMSHRqYjIxd2IyNWxi'
    || 'blJUZEdGamF6cHZJVDA5Ym5Wc2JEOXZPaUlpZlNsOUtTeHVmV1oxYm1OMGFXOXVJR2RoS0dVc2RDeHVLWHQyWVhJZ2NqMWxMbkJwYm1kRFlXTm9aVHRwWmlo'
    || 'eVBUMDliblZzYkNsN2NqMWxMbkJwYm1kRFlXTm9aVDF1WlhjZ2VtWTdkbUZ5SUd3OWJtVjNJRk5sZER0eUxuTmxkQ2gwTEd3cGZXVnNjMlVnYkQxeUxtZGxk'
    || 'Q2gwS1N4c1BUMDlkbTlwWkNBd0ppWW9iRDF1WlhjZ1UyVjBMSEl1YzJWMEtIUXNiQ2twTzJ3dWFHRnpLRzRwZkh3b2JDNWhaR1FvYmlrc1pUMVlaaTVpYVc1'
    || 'a0tHNTFiR3dzWlN4MExHNHBMSFF1ZEdobGJpaGxMR1VwS1gxbWRXNWpkR2x2YmlCNVlTaGxLWHRrYjN0MllYSWdkRHRwWmlnb2REMWxMblJoWnowOVBURXpL'
    || 'U1ltS0hROVpTNXRaVzF2YVhwbFpGTjBZWFJsTEhROWRDRTlQVzUxYkd3L2RDNWtaV2g1WkhKaGRHVmtJVDA5Ym5Wc2JEb2hNQ2tzZENseVpYUjFjbTRnWlR0'
    || 'bFBXVXVjbVYwZFhKdWZYZG9hV3hsS0dVaFBUMXVkV3hzS1R0eVpYUjFjbTRnYm5Wc2JIMW1kVzVqZEdsdmJpQjRZU2hsTEhRc2JpeHlMR3dwZTNKbGRIVnli'
    || 'aWhsTG0xdlpHVW1NU2s5UFQwd1B5aGxQVDA5ZEQ5bExtWnNZV2R6ZkQwMk5UVXpOam9vWlM1bWJHRm5jM3c5TVRJNExHNHVabXhoWjNOOFBURXpNVEEzTWl4'
    || 'dUxtWnNZV2R6SmowdE5USTRNRFVzYmk1MFlXYzlQVDB4SmlZb2JpNWhiSFJsY201aGRHVTlQVDF1ZFd4c1AyNHVkR0ZuUFRFM09paDBQVkIwS0MweExERXBM'
    || 'SFF1ZEdGblBUSXNTM1FvYml4MExERXBLU2tzYmk1c1lXNWxjM3c5TVNrc1pTazZLR1V1Wm14aFozTjhQVFkxTlRNMkxHVXViR0Z1WlhNOWJDeGxLWDEyWVhJ'
    || 'Z1JHWTliMlV1VW1WaFkzUkRkWEp5Wlc1MFQzZHVaWElzVm1VOUlURTdablZ1WTNScGIyNGdlbVVvWlN4MExHNHNjaWw3ZEM1amFHbHNaRDFsUFQwOWJuVnNi'
    || 'RDlWZFNoMExHNTFiR3dzYml4eUtUcEpiaWgwTEdVdVkyaHBiR1FzYml4eUtYMW1kVzVqZEdsdmJpQjNZU2hsTEhRc2JpeHlMR3dwZTI0OWJpNXlaVzVrWlhJ'
    || 'N2RtRnlJR2s5ZEM1eVpXWTdjbVYwZFhKdUlFUnVLSFFzYkNrc2NqMTFieWhsTEhRc2JpeHlMR2tzYkNrc2JqMWhieWdwTEdVaFBUMXVkV3hzSmlZaFZtVS9L'
    || 'SFF1ZFhCa1lYUmxVWFZsZFdVOVpTNTFjR1JoZEdWUmRXVjFaU3gwTG1ac1lXZHpKajB0TWpBMU15eGxMbXhoYm1WekpqMStiQ3hQZENobExIUXNiQ2twT2lo'
    || 'alpTWW1iaVltVVdrb2RDa3NkQzVtYkdGbmMzdzlNU3g2WlNobExIUXNjaXhzS1N4MExtTm9hV3hrS1gxbWRXNWpkR2x2YmlCVFlTaGxMSFFzYml4eUxHd3Bl'
    || 'MmxtS0dVOVBUMXVkV3hzS1h0MllYSWdhVDF1TG5SNWNHVTdjbVYwZFhKdUlIUjVjR1Z2WmlCcFBUMGlablZ1WTNScGIyNGlKaVloU0c4b2FTa21KbWt1WkdW'
    || 'bVlYVnNkRkJ5YjNCelBUMDlkbTlwWkNBd0ppWnVMbU52YlhCaGNtVTlQVDF1ZFd4c0ppWnVMbVJsWm1GMWJIUlFjbTl3Y3owOVBYWnZhV1FnTUQ4b2RDNTBZ'
    || 'V2M5TVRVc2RDNTBlWEJsUFdrc1gyRW9aU3gwTEdrc2NpeHNLU2s2S0dVOVQyd29iaTUwZVhCbExHNTFiR3dzY2l4MExIUXViVzlrWlN4c0tTeGxMbkpsWmox'
    || 'MExuSmxaaXhsTG5KbGRIVnliajEwTEhRdVkyaHBiR1E5WlNsOWFXWW9hVDFsTG1Ob2FXeGtMQ2hsTG14aGJtVnpKbXdwUFQwOU1DbDdkbUZ5SUc4OWFTNXRa'
    || 'VzF2YVhwbFpGQnliM0J6TzJsbUtHNDliaTVqYjIxd1lYSmxMRzQ5YmlFOVBXNTFiR3cvYmpwMWNpeHVLRzhzY2lrbUptVXVjbVZtUFQwOWRDNXlaV1lwY21W'
    || 'MGRYSnVJRTkwS0dVc2RDeHNLWDF5WlhSMWNtNGdkQzVtYkdGbmMzdzlNU3hsUFdKMEtHa3NjaWtzWlM1eVpXWTlkQzV5WldZc1pTNXlaWFIxY200OWRDeDBM'
    || 'bU5vYVd4a1BXVjlablZ1WTNScGIyNGdYMkVvWlN4MExHNHNjaXhzS1h0cFppaGxJVDA5Ym5Wc2JDbDdkbUZ5SUdrOVpTNXRaVzF2YVhwbFpGQnliM0J6TzJs'
    || 'bUtIVnlLR2tzY2lrbUptVXVjbVZtUFQwOWRDNXlaV1lwYVdZb1ZtVTlJVEVzZEM1d1pXNWthVzVuVUhKdmNITTljajFwTENobExteGhibVZ6Sm13cElUMDlN'
    || 'Q2tvWlM1bWJHRm5jeVl4TXpFd056SXBJVDA5TUNZbUtGWmxQU0V3S1R0bGJITmxJSEpsZEhWeWJpQjBMbXhoYm1WelBXVXViR0Z1WlhNc1QzUW9aU3gwTEd3'
    || 'cGZYSmxkSFZ5YmlCNGJ5aGxMSFFzYml4eUxHd3BmV1oxYm1OMGFXOXVJR3RoS0dVc2RDeHVLWHQyWVhJZ2NqMTBMbkJsYm1ScGJtZFFjbTl3Y3l4c1BYSXVZ'
    || 'MmhwYkdSeVpXNHNhVDFsSVQwOWJuVnNiRDlsTG0xbGJXOXBlbVZrVTNSaGRHVTZiblZzYkR0cFppaHlMbTF2WkdVOVBUMGlhR2xrWkdWdUlpbHBaaWdvZEM1'
    || 'dGIyUmxKakVwUFQwOU1DbDBMbTFsYlc5cGVtVmtVM1JoZEdVOWUySmhjMlZNWVc1bGN6b3dMR05oWTJobFVHOXZiRHB1ZFd4c0xIUnlZVzV6YVhScGIyNXpP'
    || 'bTUxYkd4OUxHbGxLRWh1TEhGbEtTeHhaWHc5Ymp0bGJITmxlMmxtS0NodUpqRXdOek0zTkRFNE1qUXBQVDA5TUNseVpYUjFjbTRnWlQxcElUMDliblZzYkQ5'
    || 'cExtSmhjMlZNWVc1bGMzeHVPbTRzZEM1c1lXNWxjejEwTG1Ob2FXeGtUR0Z1WlhNOU1UQTNNemMwTVRneU5DeDBMbTFsYlc5cGVtVmtVM1JoZEdVOWUySmhj'
    || 'MlZNWVc1bGN6cGxMR05oWTJobFVHOXZiRHB1ZFd4c0xIUnlZVzV6YVhScGIyNXpPbTUxYkd4OUxIUXVkWEJrWVhSbFVYVmxkV1U5Ym5Wc2JDeHBaU2hJYml4'
    || 'eFpTa3NjV1Y4UFdVc2JuVnNiRHQwTG0xbGJXOXBlbVZrVTNSaGRHVTllMkpoYzJWTVlXNWxjem93TEdOaFkyaGxVRzl2YkRwdWRXeHNMSFJ5WVc1emFYUnBi'
    || 'MjV6T201MWJHeDlMSEk5YVNFOVBXNTFiR3cvYVM1aVlYTmxUR0Z1WlhNNmJpeHBaU2hJYml4eFpTa3NjV1Y4UFhKOVpXeHpaU0JwSVQwOWJuVnNiRDhvY2ox'
    || 'cExtSmhjMlZNWVc1bGMzeHVMSFF1YldWdGIybDZaV1JUZEdGMFpUMXVkV3hzS1RweVBXNHNhV1VvU0c0c2NXVXBMSEZsZkQxeU8zSmxkSFZ5YmlCNlpTaGxM'
    || 'SFFzYkN4dUtTeDBMbU5vYVd4a2ZXWjFibU4wYVc5dUlFVmhLR1VzZENsN2RtRnlJRzQ5ZEM1eVpXWTdLR1U5UFQxdWRXeHNKaVp1SVQwOWJuVnNiSHg4WlNF'
    || 'OVBXNTFiR3dtSm1VdWNtVm1JVDA5YmlrbUppaDBMbVpzWVdkemZEMDFNVElzZEM1bWJHRm5jM3c5TWpBNU56RTFNaWw5Wm5WdVkzUnBiMjRnZUc4b1pTeDBM'
    || 'RzRzY2l4c0tYdDJZWElnYVQxWFpTaHVLVDlzYmpwU1pTNWpkWEp5Wlc1ME8zSmxkSFZ5YmlCcFBWSnVLSFFzYVNrc1JHNG9kQ3hzS1N4dVBYVnZLR1VzZEN4'
    || 'dUxISXNhU3hzS1N4eVBXRnZLQ2tzWlNFOVBXNTFiR3dtSmlGV1pUOG9kQzUxY0dSaGRHVlJkV1YxWlQxbExuVndaR0YwWlZGMVpYVmxMSFF1Wm14aFozTW1Q'
    || 'UzB5TURVekxHVXViR0Z1WlhNbVBYNXNMRTkwS0dVc2RDeHNLU2s2S0dObEppWnlKaVpSYVNoMEtTeDBMbVpzWVdkemZEMHhMSHBsS0dVc2RDeHVMR3dwTEhR'
    || 'dVkyaHBiR1FwZldaMWJtTjBhVzl1SUU1aEtHVXNkQ3h1TEhJc2JDbDdhV1lvVjJVb2Jpa3BlM1poY2lCcFBTRXdPMnhzS0hRcGZXVnNjMlVnYVQwaE1UdHBa'
    || 'aWhFYmloMExHd3BMSFF1YzNSaGRHVk9iMlJsUFQwOWJuVnNiQ2xmYkNobExIUXBMSEJoS0hRc2JpeHlLU3gyYnloMExHNHNjaXhzS1N4eVBTRXdPMlZzYzJV'
    || 'Z2FXWW9aVDA5UFc1MWJHd3BlM1poY2lCdlBYUXVjM1JoZEdWT2IyUmxMR005ZEM1dFpXMXZhWHBsWkZCeWIzQnpPMjh1Y0hKdmNITTlZenQyWVhJZ1pEMXZM'
    || 'bU52Ym5SbGVIUXNaejF1TG1OdmJuUmxlSFJVZVhCbE8zUjVjR1Z2WmlCblBUMGliMkpxWldOMElpWW1aeUU5UFc1MWJHdy9aejFzZENobktUb29aejFYWlNo'
    || 'dUtUOXNianBTWlM1amRYSnlaVzUwTEdjOVVtNG9kQ3huS1NrN2RtRnlJRVU5Ymk1blpYUkVaWEpwZG1Wa1UzUmhkR1ZHY205dFVISnZjSE1zYWoxMGVYQmxi'
    || 'MllnUlQwOUltWjFibU4wYVc5dUlueDhkSGx3Wlc5bUlHOHVaMlYwVTI1aGNITm9iM1JDWldadmNtVlZjR1JoZEdVOVBTSm1kVzVqZEdsdmJpSTdhbng4ZEhs'
    || 'd1pXOW1JRzh1VlU1VFFVWkZYMk52YlhCdmJtVnVkRmRwYkd4U1pXTmxhWFpsVUhKdmNITWhQU0ptZFc1amRHbHZiaUltSm5SNWNHVnZaaUJ2TG1OdmJYQnZi'
    || 'bVZ1ZEZkcGJHeFNaV05sYVhabFVISnZjSE1oUFNKbWRXNWpkR2x2YmlKOGZDaGpJVDA5Y254OFpDRTlQV2NwSmlab1lTaDBMRzhzY2l4bktTeFpkRDBoTVR0'
    || 'MllYSWdVejEwTG0xbGJXOXBlbVZrVTNSaGRHVTdieTV6ZEdGMFpUMVRMSEJzS0hRc2NpeHZMR3dwTEdROWRDNXRaVzF2YVhwbFpGTjBZWFJsTEdNaFBUMXlm'
    || 'SHhUSVQwOVpIeDhKR1V1WTNWeWNtVnVkSHg4V1hRL0tIUjVjR1Z2WmlCRlBUMGlablZ1WTNScGIyNGlKaVlvYlc4b2RDeHVMRVVzY2lrc1pEMTBMbTFsYlc5'
    || 'cGVtVmtVM1JoZEdVcExDaGpQVmwwZkh4bVlTaDBMRzRzWXl4eUxGTXNaQ3huS1NrL0tHcDhmSFI1Y0dWdlppQnZMbFZPVTBGR1JWOWpiMjF3YjI1bGJuUlhh'
    || 'V3hzVFc5MWJuUWhQU0ptZFc1amRHbHZiaUltSm5SNWNHVnZaaUJ2TG1OdmJYQnZibVZ1ZEZkcGJHeE5iM1Z1ZENFOUltWjFibU4wYVc5dUlueDhLSFI1Y0dW'
    || 'dlppQnZMbU52YlhCdmJtVnVkRmRwYkd4TmIzVnVkRDA5SW1aMWJtTjBhVzl1SWlZbWJ5NWpiMjF3YjI1bGJuUlhhV3hzVFc5MWJuUW9LU3gwZVhCbGIyWWdi'
    || 'eTVWVGxOQlJrVmZZMjl0Y0c5dVpXNTBWMmxzYkUxdmRXNTBQVDBpWm5WdVkzUnBiMjRpSmladkxsVk9VMEZHUlY5amIyMXdiMjVsYm5SWGFXeHNUVzkxYm5R'
    || 'b0tTa3NkSGx3Wlc5bUlHOHVZMjl0Y0c5dVpXNTBSR2xrVFc5MWJuUTlQU0ptZFc1amRHbHZiaUltSmloMExtWnNZV2R6ZkQwME1UazBNekE0S1NrNktIUjVj'
    || 'R1Z2WmlCdkxtTnZiWEJ2Ym1WdWRFUnBaRTF2ZFc1MFBUMGlablZ1WTNScGIyNGlKaVlvZEM1bWJHRm5jM3c5TkRFNU5ETXdPQ2tzZEM1dFpXMXZhWHBsWkZC'
    || 'eWIzQnpQWElzZEM1dFpXMXZhWHBsWkZOMFlYUmxQV1FwTEc4dWNISnZjSE05Y2l4dkxuTjBZWFJsUFdRc2J5NWpiMjUwWlhoMFBXY3NjajFqS1Rvb2RIbHda'
    || 'VzltSUc4dVkyOXRjRzl1Wlc1MFJHbGtUVzkxYm5ROVBTSm1kVzVqZEdsdmJpSW1KaWgwTG1ac1lXZHpmRDAwTVRrME16QTRLU3h5UFNFeEtYMWxiSE5sZTI4'
    || 'OWRDNXpkR0YwWlU1dlpHVXNKSFVvWlN4MEtTeGpQWFF1YldWdGIybDZaV1JRY205d2N5eG5QWFF1ZEhsd1pUMDlQWFF1Wld4bGJXVnVkRlI1Y0dVL1l6cHdk'
    || 'Q2gwTG5SNWNHVXNZeWtzYnk1d2NtOXdjejFuTEdvOWRDNXdaVzVrYVc1blVISnZjSE1zVXoxdkxtTnZiblJsZUhRc1pEMXVMbU52Ym5SbGVIUlVlWEJsTEhS'
    || 'NWNHVnZaaUJrUFQwaWIySnFaV04wSWlZbVpDRTlQVzUxYkd3L1pEMXNkQ2hrS1Rvb1pEMVhaU2h1S1Q5c2JqcFNaUzVqZFhKeVpXNTBMR1E5VW00b2RDeGtL'
    || 'U2s3ZG1GeUlFMDliaTVuWlhSRVpYSnBkbVZrVTNSaGRHVkdjbTl0VUhKdmNITTdLRVU5ZEhsd1pXOW1JRTA5UFNKbWRXNWpkR2x2YmlKOGZIUjVjR1Z2WmlC'
    || 'dkxtZGxkRk51WVhCemFHOTBRbVZtYjNKbFZYQmtZWFJsUFQwaVpuVnVZM1JwYjI0aUtYeDhkSGx3Wlc5bUlHOHVWVTVUUVVaRlgyTnZiWEJ2Ym1WdWRGZHBi'
    || 'R3hTWldObGFYWmxVSEp2Y0hNaFBTSm1kVzVqZEdsdmJpSW1KblI1Y0dWdlppQnZMbU52YlhCdmJtVnVkRmRwYkd4U1pXTmxhWFpsVUhKdmNITWhQU0ptZFc1'
    || 'amRHbHZiaUo4ZkNoaklUMDlhbng4VXlFOVBXUXBKaVpvWVNoMExHOHNjaXhrS1N4WmREMGhNU3hUUFhRdWJXVnRiMmw2WldSVGRHRjBaU3h2TG5OMFlYUmxQ'
    || 'Vk1zY0d3b2RDeHlMRzhzYkNrN2RtRnlJRWs5ZEM1dFpXMXZhWHBsWkZOMFlYUmxPMk1oUFQxcWZIeFRJVDA5U1h4OEpHVXVZM1Z5Y21WdWRIeDhXWFEvS0hS'
    || 'NWNHVnZaaUJOUFQwaVpuVnVZM1JwYjI0aUppWW9iVzhvZEN4dUxFMHNjaWtzU1QxMExtMWxiVzlwZW1Wa1UzUmhkR1VwTENoblBWbDBmSHhtWVNoMExHNHNa'
    || 'eXh5TEZNc1NTeGtLWHg4SVRFcFB5aEZmSHgwZVhCbGIyWWdieTVWVGxOQlJrVmZZMjl0Y0c5dVpXNTBWMmxzYkZWd1pHRjBaU0U5SW1aMWJtTjBhVzl1SWlZ'
    || 'bWRIbHdaVzltSUc4dVkyOXRjRzl1Wlc1MFYybHNiRlZ3WkdGMFpTRTlJbVoxYm1OMGFXOXVJbng4S0hSNWNHVnZaaUJ2TG1OdmJYQnZibVZ1ZEZkcGJHeFZj'
    || 'R1JoZEdVOVBTSm1kVzVqZEdsdmJpSW1KbTh1WTI5dGNHOXVaVzUwVjJsc2JGVndaR0YwWlNoeUxFa3NaQ2tzZEhsd1pXOW1JRzh1VlU1VFFVWkZYMk52YlhC'
    || 'dmJtVnVkRmRwYkd4VmNHUmhkR1U5UFNKbWRXNWpkR2x2YmlJbUptOHVWVTVUUVVaRlgyTnZiWEJ2Ym1WdWRGZHBiR3hWY0dSaGRHVW9jaXhKTEdRcEtTeDBl'
    || 'WEJsYjJZZ2J5NWpiMjF3YjI1bGJuUkVhV1JWY0dSaGRHVTlQU0ptZFc1amRHbHZiaUltSmloMExtWnNZV2R6ZkQwMEtTeDBlWEJsYjJZZ2J5NW5aWFJUYm1G'
    || 'd2MyaHZkRUpsWm05eVpWVndaR0YwWlQwOUltWjFibU4wYVc5dUlpWW1LSFF1Wm14aFozTjhQVEV3TWpRcEtUb29kSGx3Wlc5bUlHOHVZMjl0Y0c5dVpXNTBS'
    || 'R2xrVlhCa1lYUmxJVDBpWm5WdVkzUnBiMjRpZkh4alBUMDlaUzV0WlcxdmFYcGxaRkJ5YjNCekppWlRQVDA5WlM1dFpXMXZhWHBsWkZOMFlYUmxmSHdvZEM1'
    || 'bWJHRm5jM3c5TkNrc2RIbHdaVzltSUc4dVoyVjBVMjVoY0hOb2IzUkNaV1p2Y21WVmNHUmhkR1VoUFNKbWRXNWpkR2x2YmlKOGZHTTlQVDFsTG0xbGJXOXBl'
    || 'bVZrVUhKdmNITW1KbE05UFQxbExtMWxiVzlwZW1Wa1UzUmhkR1Y4ZkNoMExtWnNZV2R6ZkQweE1ESTBLU3gwTG0xbGJXOXBlbVZrVUhKdmNITTljaXgwTG0x'
    || 'bGJXOXBlbVZrVTNSaGRHVTlTU2tzYnk1d2NtOXdjejF5TEc4dWMzUmhkR1U5U1N4dkxtTnZiblJsZUhROVpDeHlQV2NwT2loMGVYQmxiMllnYnk1amIyMXdi'
    || 'MjVsYm5SRWFXUlZjR1JoZEdVaFBTSm1kVzVqZEdsdmJpSjhmR005UFQxbExtMWxiVzlwZW1Wa1VISnZjSE1tSmxNOVBUMWxMbTFsYlc5cGVtVmtVM1JoZEdW'
    || 'OGZDaDBMbVpzWVdkemZEMDBLU3gwZVhCbGIyWWdieTVuWlhSVGJtRndjMmh2ZEVKbFptOXlaVlZ3WkdGMFpTRTlJbVoxYm1OMGFXOXVJbng4WXowOVBXVXVi'
    || 'V1Z0YjJsNlpXUlFjbTl3Y3lZbVV6MDlQV1V1YldWdGIybDZaV1JUZEdGMFpYeDhLSFF1Wm14aFozTjhQVEV3TWpRcExISTlJVEVwZlhKbGRIVnliaUIzYnlo'
    || 'bExIUXNiaXh5TEdrc2JDbDlablZ1WTNScGIyNGdkMjhvWlN4MExHNHNjaXhzTEdrcGUwVmhLR1VzZENrN2RtRnlJRzg5S0hRdVpteGhaM01tTVRJNEtTRTlQ'
    || 'VEE3YVdZb0lYSW1KaUZ2S1hKbGRIVnliaUJzSmlaU2RTaDBMRzRzSVRFcExFOTBLR1VzZEN4cEtUdHlQWFF1YzNSaGRHVk9iMlJsTEVSbUxtTjFjbkpsYm5R'
    || 'OWREdDJZWElnWXoxdkppWjBlWEJsYjJZZ2JpNW5aWFJFWlhKcGRtVmtVM1JoZEdWR2NtOXRSWEp5YjNJaFBTSm1kVzVqZEdsdmJpSS9iblZzYkRweUxuSmxi'
    || 'bVJsY2lncE8zSmxkSFZ5YmlCMExtWnNZV2R6ZkQweExHVWhQVDF1ZFd4c0ppWnZQeWgwTG1Ob2FXeGtQVWx1S0hRc1pTNWphR2xzWkN4dWRXeHNMR2twTEhR'
    || 'dVkyaHBiR1E5U1c0b2RDeHVkV3hzTEdNc2FTa3BPbnBsS0dVc2RDeGpMR2twTEhRdWJXVnRiMmw2WldSVGRHRjBaVDF5TG5OMFlYUmxMR3dtSmxKMUtIUXNi'
    || 'aXdoTUNrc2RDNWphR2xzWkgxbWRXNWpkR2x2YmlCcVlTaGxLWHQyWVhJZ2REMWxMbk4wWVhSbFRtOWtaVHQwTG5CbGJtUnBibWREYjI1MFpYaDBQME4xS0dV'
    || 'c2RDNXdaVzVrYVc1blEyOXVkR1Y0ZEN4MExuQmxibVJwYm1kRGIyNTBaWGgwSVQwOWRDNWpiMjUwWlhoMEtUcDBMbU52Ym5SbGVIUW1Ka04xS0dVc2RDNWpi'
    || 'MjUwWlhoMExDRXhLU3h1YnlobExIUXVZMjl1ZEdGcGJtVnlTVzVtYnlsOVpuVnVZM1JwYjI0Z1ZHRW9aU3gwTEc0c2NpeHNLWHR5WlhSMWNtNGdUMjRvS1N4'
    || 'WWFTaHNLU3gwTG1ac1lXZHpmRDB5TlRZc2VtVW9aU3gwTEc0c2Npa3NkQzVqYUdsc1pIMTJZWElnVTI4OWUyUmxhSGxrY21GMFpXUTZiblZzYkN4MGNtVmxR'
    || 'Mjl1ZEdWNGREcHVkV3hzTEhKbGRISjVUR0Z1WlRvd2ZUdG1kVzVqZEdsdmJpQmZieWhsS1h0eVpYUjFjbTU3WW1GelpVeGhibVZ6T21Vc1kyRmphR1ZRYjI5'
    || 'c09tNTFiR3dzZEhKaGJuTnBkR2x2Ym5NNmJuVnNiSDE5Wm5WdVkzUnBiMjRnUTJFb1pTeDBMRzRwZTNaaGNpQnlQWFF1Y0dWdVpHbHVaMUJ5YjNCekxHdzla'
    || 'R1V1WTNWeWNtVnVkQ3hwUFNFeExHODlLSFF1Wm14aFozTW1NVEk0S1NFOVBUQXNZenRwWmlnb1l6MXZLWHg4S0dNOVpTRTlQVzUxYkd3bUptVXViV1Z0YjJs'
    || 'NlpXUlRkR0YwWlQwOVBXNTFiR3cvSVRFNktHd21NaWtoUFQwd0tTeGpQeWhwUFNFd0xIUXVabXhoWjNNbVBTMHhNamtwT2lobFBUMDliblZzYkh4OFpTNXRa'
    || 'VzF2YVhwbFpGTjBZWFJsSVQwOWJuVnNiQ2ttSmloc2ZEMHhLU3hwWlNoa1pTeHNKakVwTEdVOVBUMXVkV3hzS1hKbGRIVnliaUJIYVNoMEtTeGxQWFF1YldW'
    || 'dGIybDZaV1JUZEdGMFpTeGxJVDA5Ym5Wc2JDWW1LR1U5WlM1a1pXaDVaSEpoZEdWa0xHVWhQVDF1ZFd4c0tUOG9LSFF1Ylc5a1pTWXhLVDA5UFRBL2RDNXNZ'
    || 'VzVsY3oweE9tVXVaR0YwWVQwOVBTSWtJU0kvZEM1c1lXNWxjejA0T25RdWJHRnVaWE05TVRBM016YzBNVGd5TkN4dWRXeHNLVG9vYnoxeUxtTm9hV3hrY21W'
    || 'dUxHVTljaTVtWVd4c1ltRmpheXhwUHloeVBYUXViVzlrWlN4cFBYUXVZMmhwYkdRc2J6MTdiVzlrWlRvaWFHbGtaR1Z1SWl4amFHbHNaSEpsYmpwdmZTd29j'
    || 'aVl4S1QwOVBUQW1KbWtoUFQxdWRXeHNQeWhwTG1Ob2FXeGtUR0Z1WlhNOU1DeHBMbkJsYm1ScGJtZFFjbTl3Y3oxdktUcHBQVWxzS0c4c2Npd3dMRzUxYkd3'
    || 'cExHVTliVzRvWlN4eUxHNHNiblZzYkNrc2FTNXlaWFIxY200OWRDeGxMbkpsZEhWeWJqMTBMR2t1YzJsaWJHbHVaejFsTEhRdVkyaHBiR1E5YVN4MExtTm9h'
    || 'V3hrTG0xbGJXOXBlbVZrVTNSaGRHVTlYMjhvYmlrc2RDNXRaVzF2YVhwbFpGTjBZWFJsUFZOdkxHVXBPbXR2S0hRc2J5a3BPMmxtS0d3OVpTNXRaVzF2YVhw'
    || 'bFpGTjBZWFJsTEd3aFBUMXVkV3hzSmlZb1l6MXNMbVJsYUhsa2NtRjBaV1FzWXlFOVBXNTFiR3dwS1hKbGRIVnliaUJCWmlobExIUXNieXh5TEdNc2JDeHVL'
    || 'VHRwWmlocEtYdHBQWEl1Wm1Gc2JHSmhZMnNzYnoxMExtMXZaR1VzYkQxbExtTm9hV3hrTEdNOWJDNXphV0pzYVc1bk8zWmhjaUJrUFh0dGIyUmxPaUpvYVdS'
    || 'a1pXNGlMR05vYVd4a2NtVnVPbkl1WTJocGJHUnlaVzU5TzNKbGRIVnliaWh2SmpFcFBUMDlNQ1ltZEM1amFHbHNaQ0U5UFd3L0tISTlkQzVqYUdsc1pDeHlM'
    || 'bU5vYVd4a1RHRnVaWE05TUN4eUxuQmxibVJwYm1kUWNtOXdjejFrTEhRdVpHVnNaWFJwYjI1elBXNTFiR3dwT2loeVBXSjBLR3dzWkNrc2NpNXpkV0owY21W'
    || 'bFJteGhaM005YkM1emRXSjBjbVZsUm14aFozTW1NVFEyT0RBd05qUXBMR01oUFQxdWRXeHNQMms5WW5Rb1l5eHBLVG9vYVQxdGJpaHBMRzhzYml4dWRXeHNL'
    || 'U3hwTG1ac1lXZHpmRDB5S1N4cExuSmxkSFZ5YmoxMExISXVjbVYwZFhKdVBYUXNjaTV6YVdKc2FXNW5QV2tzZEM1amFHbHNaRDF5TEhJOWFTeHBQWFF1WTJo'
    || 'cGJHUXNiejFsTG1Ob2FXeGtMbTFsYlc5cGVtVmtVM1JoZEdVc2J6MXZQVDA5Ym5Wc2JEOWZieWh1S1RwN1ltRnpaVXhoYm1Wek9tOHVZbUZ6WlV4aGJtVnpm'
    || 'RzRzWTJGamFHVlFiMjlzT201MWJHd3NkSEpoYm5OcGRHbHZibk02Ynk1MGNtRnVjMmwwYVc5dWMzMHNhUzV0WlcxdmFYcGxaRk4wWVhSbFBXOHNhUzVqYUds'
    || 'c1pFeGhibVZ6UFdVdVkyaHBiR1JNWVc1bGN5WitiaXgwTG0xbGJXOXBlbVZrVTNSaGRHVTlVMjhzY24xeVpYUjFjbTRnYVQxbExtTm9hV3hrTEdVOWFTNXph'
    || 'V0pzYVc1bkxISTlZblFvYVN4N2JXOWtaVG9pZG1semFXSnNaU0lzWTJocGJHUnlaVzQ2Y2k1amFHbHNaSEpsYm4wcExDaDBMbTF2WkdVbU1TazlQVDB3SmlZ'
    || 'b2NpNXNZVzVsY3oxdUtTeHlMbkpsZEhWeWJqMTBMSEl1YzJsaWJHbHVaejF1ZFd4c0xHVWhQVDF1ZFd4c0ppWW9iajEwTG1SbGJHVjBhVzl1Y3l4dVBUMDli'
    || 'blZzYkQ4b2RDNWtaV3hsZEdsdmJuTTlXMlZkTEhRdVpteGhaM044UFRFMktUcHVMbkIxYzJnb1pTa3BMSFF1WTJocGJHUTljaXgwTG0xbGJXOXBlbVZrVTNS'
    || 'aGRHVTliblZzYkN4eWZXWjFibU4wYVc5dUlHdHZLR1VzZENsN2NtVjBkWEp1SUhROVNXd29lMjF2WkdVNkluWnBjMmxpYkdVaUxHTm9hV3hrY21WdU9uUjlM'
    || 'R1V1Ylc5a1pTd3dMRzUxYkd3cExIUXVjbVYwZFhKdVBXVXNaUzVqYUdsc1pEMTBmV1oxYm1OMGFXOXVJRk5zS0dVc2RDeHVMSElwZTNKbGRIVnliaUJ5SVQw'
    || 'OWJuVnNiQ1ltV0drb2Npa3NTVzRvZEN4bExtTm9hV3hrTEc1MWJHd3NiaWtzWlQxcmJ5aDBMSFF1Y0dWdVpHbHVaMUJ5YjNCekxtTm9hV3hrY21WdUtTeGxM'
    || 'bVpzWVdkemZEMHlMSFF1YldWdGIybDZaV1JUZEdGMFpUMXVkV3hzTEdWOVpuVnVZM1JwYjI0Z1FXWW9aU3gwTEc0c2NpeHNMR2tzYnlsN2FXWW9iaWx5WlhS'
    || 'MWNtNGdkQzVtYkdGbmN5WXlOVFkvS0hRdVpteGhaM01tUFMweU5UY3NjajFuYnloRmNuSnZjaWhoS0RReU1pa3BLU3hUYkNobExIUXNieXh5S1NrNmRDNXRa'
    || 'VzF2YVhwbFpGTjBZWFJsSVQwOWJuVnNiRDhvZEM1amFHbHNaRDFsTG1Ob2FXeGtMSFF1Wm14aFozTjhQVEV5T0N4dWRXeHNLVG9vYVQxeUxtWmhiR3hpWVdO'
    || 'ckxHdzlkQzV0YjJSbExISTlTV3dvZTIxdlpHVTZJblpwYzJsaWJHVWlMR05vYVd4a2NtVnVPbkl1WTJocGJHUnlaVzU5TEd3c01DeHVkV3hzS1N4cFBXMXVL'
    || 'R2tzYkN4dkxHNTFiR3dwTEdrdVpteGhaM044UFRJc2NpNXlaWFIxY200OWRDeHBMbkpsZEhWeWJqMTBMSEl1YzJsaWJHbHVaejFwTEhRdVkyaHBiR1E5Y2l3'
    || 'b2RDNXRiMlJsSmpFcElUMDlNQ1ltU1c0b2RDeGxMbU5vYVd4a0xHNTFiR3dzYnlrc2RDNWphR2xzWkM1dFpXMXZhWHBsWkZOMFlYUmxQVjl2S0c4cExIUXVi'
    || 'V1Z0YjJsNlpXUlRkR0YwWlQxVGJ5eHBLVHRwWmlnb2RDNXRiMlJsSmpFcFBUMDlNQ2x5WlhSMWNtNGdVMndvWlN4MExHOHNiblZzYkNrN2FXWW9iQzVrWVhS'
    || 'aFBUMDlJaVFoSWlsN2FXWW9jajFzTG01bGVIUlRhV0pzYVc1bkppWnNMbTVsZUhSVGFXSnNhVzVuTG1SaGRHRnpaWFFzY2lsMllYSWdZejF5TG1SbmMzUTdj'
    || 'bVYwZFhKdUlISTlZeXhwUFVWeWNtOXlLR0VvTkRFNUtTa3NjajFuYnlocExISXNkbTlwWkNBd0tTeFRiQ2hsTEhRc2J5eHlLWDFwWmloalBTaHZKbVV1WTJo'
    || 'cGJHUk1ZVzVsY3lraFBUMHdMRlpsZkh4aktYdHBaaWh5UFd0bExISWhQVDF1ZFd4c0tYdHpkMmwwWTJnb2J5WXRieWw3WTJGelpTQTBPbXc5TWp0aWNtVmhh'
    || 'enRqWVhObElERTJPbXc5T0R0aWNtVmhhenRqWVhObElEWTBPbU5oYzJVZ01USTRPbU5oYzJVZ01qVTJPbU5oYzJVZ05URXlPbU5oYzJVZ01UQXlORHBqWVhO'
    || 'bElESXdORGc2WTJGelpTQTBNRGsyT21OaGMyVWdPREU1TWpwallYTmxJREUyTXpnME9tTmhjMlVnTXpJM05qZzZZMkZ6WlNBMk5UVXpOanBqWVhObElERXpN'
    || 'VEEzTWpwallYTmxJREkyTWpFME5EcGpZWE5sSURVeU5ESTRPRHBqWVhObElERXdORGcxTnpZNlkyRnpaU0F5TURrM01UVXlPbU5oYzJVZ05ERTVORE13TkRw'
    || 'allYTmxJRGd6T0RnMk1EZzZZMkZ6WlNBeE5qYzNOekl4TmpwallYTmxJRE16TlRVME5ETXlPbU5oYzJVZ05qY3hNRGc0TmpRNmJEMHpNanRpY21WaGF6dGpZ'
    || 'WE5sSURVek5qZzNNRGt4TWpwc1BUSTJPRFF6TlRRMU5qdGljbVZoYXp0a1pXWmhkV3gwT213OU1IMXNQU2hzSmloeUxuTjFjM0JsYm1SbFpFeGhibVZ6Zkc4'
    || 'cEtTRTlQVEEvTURwc0xHd2hQVDB3Smlac0lUMDlhUzV5WlhSeWVVeGhibVVtSmlocExuSmxkSEo1VEdGdVpUMXNMRTEwS0dVc2JDa3NkblFvY2l4bExHd3NM'
    || 'VEVwS1gxeVpYUjFjbTRnVlc4b0tTeHlQV2R2S0VWeWNtOXlLR0VvTkRJeEtTa3BMRk5zS0dVc2RDeHZMSElwZlhKbGRIVnliaUJzTG1SaGRHRTlQVDBpSkQ4'
    || 'aVB5aDBMbVpzWVdkemZEMHhNamdzZEM1amFHbHNaRDFsTG1Ob2FXeGtMSFE5V21ZdVltbHVaQ2h1ZFd4c0xHVXBMR3d1WDNKbFlXTjBVbVYwY25rOWRDeHVk'
    || 'V3hzS1Rvb1pUMXBMblJ5WldWRGIyNTBaWGgwTEVwbFBWZDBLR3d1Ym1WNGRGTnBZbXhwYm1jcExGcGxQWFFzWTJVOUlUQXNablE5Ym5Wc2JDeGxJVDA5Ym5W'
    || 'c2JDWW1LRzUwVzNKMEt5dGRQVXgwTEc1MFczSjBLeXRkUFZKMExHNTBXM0owS3l0ZFBXOXVMRXgwUFdVdWFXUXNVblE5WlM1dmRtVnlabXh2ZHl4dmJqMTBL'
    || 'U3gwUFd0dktIUXNjaTVqYUdsc1pISmxiaWtzZEM1bWJHRm5jM3c5TkRBNU5peDBLWDFtZFc1amRHbHZiaUJNWVNobExIUXNiaWw3WlM1c1lXNWxjM3c5ZER0'
    || 'MllYSWdjajFsTG1Gc2RHVnlibUYwWlR0eUlUMDliblZzYkNZbUtISXViR0Z1WlhOOFBYUXBMR0pwS0dVdWNtVjBkWEp1TEhRc2JpbDlablZ1WTNScGIyNGdS'
    || 'VzhvWlN4MExHNHNjaXhzS1h0MllYSWdhVDFsTG0xbGJXOXBlbVZrVTNSaGRHVTdhVDA5UFc1MWJHdy9aUzV0WlcxdmFYcGxaRk4wWVhSbFBYdHBjMEpoWTJ0'
    || 'M1lYSmtjenAwTEhKbGJtUmxjbWx1WnpwdWRXeHNMSEpsYm1SbGNtbHVaMU4wWVhKMFZHbHRaVG93TEd4aGMzUTZjaXgwWVdsc09tNHNkR0ZwYkUxdlpHVTZi'
    || 'SDA2S0drdWFYTkNZV05yZDJGeVpITTlkQ3hwTG5KbGJtUmxjbWx1WnoxdWRXeHNMR2t1Y21WdVpHVnlhVzVuVTNSaGNuUlVhVzFsUFRBc2FTNXNZWE4wUFhJ'
    || 'c2FTNTBZV2xzUFc0c2FTNTBZV2xzVFc5a1pUMXNLWDFtZFc1amRHbHZiaUJTWVNobExIUXNiaWw3ZG1GeUlISTlkQzV3Wlc1a2FXNW5VSEp2Y0hNc2JEMXlM'
    || 'bkpsZG1WaGJFOXlaR1Z5TEdrOWNpNTBZV2xzTzJsbUtIcGxLR1VzZEN4eUxtTm9hV3hrY21WdUxHNHBMSEk5WkdVdVkzVnljbVZ1ZEN3b2NpWXlLU0U5UFRB'
    || 'cGNqMXlKakY4TWl4MExtWnNZV2R6ZkQweE1qZzdaV3h6Wlh0cFppaGxJVDA5Ym5Wc2JDWW1LR1V1Wm14aFozTW1NVEk0S1NFOVBUQXBaVHBtYjNJb1pUMTBM'
    || 'bU5vYVd4a08yVWhQVDF1ZFd4c095bDdhV1lvWlM1MFlXYzlQVDB4TXlsbExtMWxiVzlwZW1Wa1UzUmhkR1VoUFQxdWRXeHNKaVpNWVNobExHNHNkQ2s3Wld4'
    || 'elpTQnBaaWhsTG5SaFp6MDlQVEU1S1V4aEtHVXNiaXgwS1R0bGJITmxJR2xtS0dVdVkyaHBiR1FoUFQxdWRXeHNLWHRsTG1Ob2FXeGtMbkpsZEhWeWJqMWxM'
    || 'R1U5WlM1amFHbHNaRHRqYjI1MGFXNTFaWDFwWmlobFBUMDlkQ2xpY21WaGF5QmxPMlp2Y2lnN1pTNXphV0pzYVc1blBUMDliblZzYkRzcGUybG1LR1V1Y21W'
    || 'MGRYSnVQVDA5Ym5Wc2JIeDhaUzV5WlhSMWNtNDlQVDEwS1dKeVpXRnJJR1U3WlQxbExuSmxkSFZ5Ym4xbExuTnBZbXhwYm1jdWNtVjBkWEp1UFdVdWNtVjBk'
    || 'WEp1TEdVOVpTNXphV0pzYVc1bmZYSW1QVEY5YVdZb2FXVW9aR1VzY2lrc0tIUXViVzlrWlNZeEtUMDlQVEFwZEM1dFpXMXZhWHBsWkZOMFlYUmxQVzUxYkd3'
    || 'N1pXeHpaU0J6ZDJsMFkyZ29iQ2w3WTJGelpTSm1iM0ozWVhKa2N5STZabTl5S0c0OWRDNWphR2xzWkN4c1BXNTFiR3c3YmlFOVBXNTFiR3c3S1dVOWJpNWhi'
    || 'SFJsY201aGRHVXNaU0U5UFc1MWJHd21KbWhzS0dVcFBUMDliblZzYkNZbUtHdzliaWtzYmoxdUxuTnBZbXhwYm1jN2JqMXNMRzQ5UFQxdWRXeHNQeWhzUFhR'
    || 'dVkyaHBiR1FzZEM1amFHbHNaRDF1ZFd4c0tUb29iRDF1TG5OcFlteHBibWNzYmk1emFXSnNhVzVuUFc1MWJHd3BMRVZ2S0hRc0lURXNiQ3h1TEdrcE8ySnla'
    || 'V0ZyTzJOaGMyVWlZbUZqYTNkaGNtUnpJanBtYjNJb2JqMXVkV3hzTEd3OWRDNWphR2xzWkN4MExtTm9hV3hrUFc1MWJHdzdiQ0U5UFc1MWJHdzdLWHRwWmlo'
    || 'bFBXd3VZV3gwWlhKdVlYUmxMR1VoUFQxdWRXeHNKaVpvYkNobEtUMDlQVzUxYkd3cGUzUXVZMmhwYkdROWJEdGljbVZoYTMxbFBXd3VjMmxpYkdsdVp5eHNM'
    || 'bk5wWW14cGJtYzliaXh1UFd3c2JEMWxmVVZ2S0hRc0lUQXNiaXh1ZFd4c0xHa3BPMkp5WldGck8yTmhjMlVpZEc5blpYUm9aWElpT2tWdktIUXNJVEVzYm5W'
    || 'c2JDeHVkV3hzTEhadmFXUWdNQ2s3WW5KbFlXczdaR1ZtWVhWc2REcDBMbTFsYlc5cGVtVmtVM1JoZEdVOWJuVnNiSDF5WlhSMWNtNGdkQzVqYUdsc1pIMW1k'
    || 'VzVqZEdsdmJpQmZiQ2hsTEhRcGV5aDBMbTF2WkdVbU1TazlQVDB3SmlabElUMDliblZzYkNZbUtHVXVZV3gwWlhKdVlYUmxQVzUxYkd3c2RDNWhiSFJsY201'
    || 'aGRHVTliblZzYkN4MExtWnNZV2R6ZkQweUtYMW1kVzVqZEdsdmJpQlBkQ2hsTEhRc2JpbDdhV1lvWlNFOVBXNTFiR3dtSmloMExtUmxjR1Z1WkdWdVkybGxj'
    || 'ejFsTG1SbGNHVnVaR1Z1WTJsbGN5a3NaRzU4UFhRdWJHRnVaWE1zS0c0bWRDNWphR2xzWkV4aGJtVnpLVDA5UFRBcGNtVjBkWEp1SUc1MWJHdzdhV1lvWlNF'
    || 'OVBXNTFiR3dtSm5RdVkyaHBiR1FoUFQxbExtTm9hV3hrS1hSb2NtOTNJRVZ5Y205eUtHRW9NVFV6S1NrN2FXWW9kQzVqYUdsc1pDRTlQVzUxYkd3cGUyWnZj'
    || 'aWhsUFhRdVkyaHBiR1FzYmoxaWRDaGxMR1V1Y0dWdVpHbHVaMUJ5YjNCektTeDBMbU5vYVd4a1BXNHNiaTV5WlhSMWNtNDlkRHRsTG5OcFlteHBibWNoUFQx'
    || 'dWRXeHNPeWxsUFdVdWMybGliR2x1Wnl4dVBXNHVjMmxpYkdsdVp6MWlkQ2hsTEdVdWNHVnVaR2x1WjFCeWIzQnpLU3h1TG5KbGRIVnliajEwTzI0dWMybGli'
    || 'R2x1WnoxdWRXeHNmWEpsZEhWeWJpQjBMbU5vYVd4a2ZXWjFibU4wYVc5dUlFWm1LR1VzZEN4dUtYdHpkMmwwWTJnb2RDNTBZV2NwZTJOaGMyVWdNenBxWVNo'
    || 'MEtTeFBiaWdwTzJKeVpXRnJPMk5oYzJVZ05UcENkU2gwS1R0aWNtVmhhenRqWVhObElERTZWMlVvZEM1MGVYQmxLU1ltYkd3b2RDazdZbkpsWVdzN1kyRnpa'
    || 'U0EwT201dktIUXNkQzV6ZEdGMFpVNXZaR1V1WTI5dWRHRnBibVZ5U1c1bWJ5azdZbkpsWVdzN1kyRnpaU0F4TURwMllYSWdjajEwTG5SNWNHVXVYMk52Ym5S'
    || 'bGVIUXNiRDEwTG0xbGJXOXBlbVZrVUhKdmNITXVkbUZzZFdVN2FXVW9ZMndzY2k1ZlkzVnljbVZ1ZEZaaGJIVmxLU3h5TGw5amRYSnlaVzUwVm1Gc2RXVTli'
    || 'RHRpY21WaGF6dGpZWE5sSURFek9tbG1LSEk5ZEM1dFpXMXZhWHBsWkZOMFlYUmxMSEloUFQxdWRXeHNLWEpsZEhWeWJpQnlMbVJsYUhsa2NtRjBaV1FoUFQx'
    || 'dWRXeHNQeWhwWlNoa1pTeGtaUzVqZFhKeVpXNTBKakVwTEhRdVpteGhaM044UFRFeU9DeHVkV3hzS1Rvb2JpWjBMbU5vYVd4a0xtTm9hV3hrVEdGdVpYTXBJ'
    || 'VDA5TUQ5RFlTaGxMSFFzYmlrNktHbGxLR1JsTEdSbExtTjFjbkpsYm5RbU1Ta3NaVDFQZENobExIUXNiaWtzWlNFOVBXNTFiR3cvWlM1emFXSnNhVzVuT201'
    || 'MWJHd3BPMmxsS0dSbExHUmxMbU4xY25KbGJuUW1NU2s3WW5KbFlXczdZMkZ6WlNBeE9UcHBaaWh5UFNodUpuUXVZMmhwYkdSTVlXNWxjeWtoUFQwd0xDaGxM'
    || 'bVpzWVdkekpqRXlPQ2toUFQwd0tYdHBaaWh5S1hKbGRIVnliaUJTWVNobExIUXNiaWs3ZEM1bWJHRm5jM3c5TVRJNGZXbG1LR3c5ZEM1dFpXMXZhWHBsWkZO'
    || 'MFlYUmxMR3doUFQxdWRXeHNKaVlvYkM1eVpXNWtaWEpwYm1jOWJuVnNiQ3hzTG5SaGFXdzliblZzYkN4c0xteGhjM1JGWm1abFkzUTliblZzYkNrc2FXVW9a'
    || 'R1VzWkdVdVkzVnljbVZ1ZENrc2NpbGljbVZoYXp0eVpYUjFjbTRnYm5Wc2JEdGpZWE5sSURJeU9tTmhjMlVnTWpNNmNtVjBkWEp1SUhRdWJHRnVaWE05TUN4'
    || 'cllTaGxMSFFzYmlsOWNtVjBkWEp1SUU5MEtHVXNkQ3h1S1gxMllYSWdUV0VzVG04c1VHRXNUMkU3VFdFOVpuVnVZM1JwYjI0b1pTeDBLWHRtYjNJb2RtRnlJ'
    || 'RzQ5ZEM1amFHbHNaRHR1SVQwOWJuVnNiRHNwZTJsbUtHNHVkR0ZuUFQwOU5YeDhiaTUwWVdjOVBUMDJLV1V1WVhCd1pXNWtRMmhwYkdRb2JpNXpkR0YwWlU1'
    || 'dlpHVXBPMlZzYzJVZ2FXWW9iaTUwWVdjaFBUMDBKaVp1TG1Ob2FXeGtJVDA5Ym5Wc2JDbDdiaTVqYUdsc1pDNXlaWFIxY200OWJpeHVQVzR1WTJocGJHUTdZ'
    || 'Mjl1ZEdsdWRXVjlhV1lvYmowOVBYUXBZbkpsWVdzN1ptOXlLRHR1TG5OcFlteHBibWM5UFQxdWRXeHNPeWw3YVdZb2JpNXlaWFIxY200OVBUMXVkV3hzZkh4'
    || 'dUxuSmxkSFZ5YmowOVBYUXBjbVYwZFhKdU8yNDliaTV5WlhSMWNtNTliaTV6YVdKc2FXNW5MbkpsZEhWeWJqMXVMbkpsZEhWeWJpeHVQVzR1YzJsaWJHbHVa'
    || 'MzE5TEU1dlBXWjFibU4wYVc5dUtDbDdmU3hRWVQxbWRXNWpkR2x2YmlobExIUXNiaXh5S1h0MllYSWdiRDFsTG0xbGJXOXBlbVZrVUhKdmNITTdhV1lvYkNF'
    || 'OVBYSXBlMlU5ZEM1emRHRjBaVTV2WkdVc1lXNG9YM1F1WTNWeWNtVnVkQ2s3ZG1GeUlHazliblZzYkR0emQybDBZMmdvYmlsN1kyRnpaU0pwYm5CMWRDSTZi'
    || 'RDFpYkNobExHd3BMSEk5WW13b1pTeHlLU3hwUFZ0ZE8ySnlaV0ZyTzJOaGMyVWljMlZzWldOMElqcHNQVThvZTMwc2JDeDdkbUZzZFdVNmRtOXBaQ0F3ZlNr'
    || 'c2NqMVBLSHQ5TEhJc2UzWmhiSFZsT25admFXUWdNSDBwTEdrOVcxMDdZbkpsWVdzN1kyRnpaU0owWlhoMFlYSmxZU0k2YkQxdWFTaGxMR3dwTEhJOWJta29a'
    || 'U3h5S1N4cFBWdGRPMkp5WldGck8yUmxabUYxYkhRNmRIbHdaVzltSUd3dWIyNURiR2xqYXlFOUltWjFibU4wYVc5dUlpWW1kSGx3Wlc5bUlISXViMjVEYkds'
    || 'amF6MDlJbVoxYm1OMGFXOXVJaVltS0dVdWIyNWpiR2xqYXoxMGJDbDliR2tvYml4eUtUdDJZWElnYnp0dVBXNTFiR3c3Wm05eUtHY2dhVzRnYkNscFppZ2hj'
    || 'aTVvWVhOUGQyNVFjbTl3WlhKMGVTaG5LU1ltYkM1b1lYTlBkMjVRY205d1pYSjBlU2huS1NZbWJGdG5YU0U5Ym5Wc2JDbHBaaWhuUFQwOUluTjBlV3hsSWls'
    || 'N2RtRnlJR005YkZ0blhUdG1iM0lvYnlCcGJpQmpLV011YUdGelQzZHVVSEp2Y0dWeWRIa29ieWttSmlodWZId29iajE3ZlNrc2JsdHZYVDBpSWlsOVpXeHpa'
    || 'U0JuSVQwOUltUmhibWRsY205MWMyeDVVMlYwU1c1dVpYSklWRTFNSWlZbVp5RTlQU0pqYUdsc1pISmxiaUltSm1jaFBUMGljM1Z3Y0hKbGMzTkRiMjUwWlc1'
    || 'MFJXUnBkR0ZpYkdWWFlYSnVhVzVuSWlZbVp5RTlQU0p6ZFhCd2NtVnpjMGg1WkhKaGRHbHZibGRoY201cGJtY2lKaVpuSVQwOUltRjFkRzlHYjJOMWN5SW1K'
    || 'aWhPTG1oaGMwOTNibEJ5YjNCbGNuUjVLR2NwUDJsOGZDaHBQVnRkS1Rvb2FUMXBmSHhiWFNrdWNIVnphQ2huTEc1MWJHd3BLVHRtYjNJb1p5QnBiaUJ5S1h0'
    || 'MllYSWdaRDF5VzJkZE8ybG1LR005YkNFOWJuVnNiRDlzVzJkZE9uWnZhV1FnTUN4eUxtaGhjMDkzYmxCeWIzQmxjblI1S0djcEppWmtJVDA5WXlZbUtHUWhQ'
    || 'VzUxYkd4OGZHTWhQVzUxYkd3cEtXbG1LR2M5UFQwaWMzUjViR1VpS1dsbUtHTXBlMlp2Y2lodklHbHVJR01wSVdNdWFHRnpUM2R1VUhKdmNHVnlkSGtvYnls'
    || 'OGZHUW1KbVF1YUdGelQzZHVVSEp2Y0dWeWRIa29ieWw4ZkNodWZId29iajE3ZlNrc2JsdHZYVDBpSWlrN1ptOXlLRzhnYVc0Z1pDbGtMbWhoYzA5M2JsQnli'
    || 'M0JsY25SNUtHOHBKaVpqVzI5ZElUMDlaRnR2WFNZbUtHNThmQ2h1UFh0OUtTeHVXMjlkUFdSYmIxMHBmV1ZzYzJVZ2JueDhLR2w4ZkNocFBWdGRLU3hwTG5C'
    || 'MWMyZ29aeXh1S1Nrc2JqMWtPMlZzYzJVZ1p6MDlQU0prWVc1blpYSnZkWE5zZVZObGRFbHVibVZ5U0ZSTlRDSS9LR1E5WkQ5a0xsOWZhSFJ0YkRwMmIybGtJ'
    || 'REFzWXoxalAyTXVYMTlvZEcxc09uWnZhV1FnTUN4a0lUMXVkV3hzSmlaaklUMDlaQ1ltS0drOWFYeDhXMTBwTG5CMWMyZ29aeXhrS1NrNlp6MDlQU0pqYUds'
    || 'c1pISmxiaUkvZEhsd1pXOW1JR1FoUFNKemRISnBibWNpSmlaMGVYQmxiMllnWkNFOUltNTFiV0psY2lKOGZDaHBQV2w4ZkZ0ZEtTNXdkWE5vS0djc0lpSXJa'
    || 'Q2s2WnlFOVBTSnpkWEJ3Y21WemMwTnZiblJsYm5SRlpHbDBZV0pzWlZkaGNtNXBibWNpSmlabklUMDlJbk4xY0hCeVpYTnpTSGxrY21GMGFXOXVWMkZ5Ym1s'
    || 'dVp5SW1KaWhPTG1oaGMwOTNibEJ5YjNCbGNuUjVLR2NwUHloa0lUMXVkV3hzSmlablBUMDlJbTl1VTJOeWIyeHNJaVltYzJVb0luTmpjbTlzYkNJc1pTa3Nh'
    || 'WHg4WXowOVBXUjhmQ2hwUFZ0ZEtTazZLR2s5YVh4OFcxMHBMbkIxYzJnb1p5eGtLU2w5YmlZbUtHazlhWHg4VzEwcExuQjFjMmdvSW5OMGVXeGxJaXh1S1R0'
    || 'MllYSWdaejFwT3loMExuVndaR0YwWlZGMVpYVmxQV2NwSmlZb2RDNW1iR0ZuYzN3OU5DbDlmU3hQWVQxbWRXNWpkR2x2YmlobExIUXNiaXh5S1h0dUlUMDlj'
    || 'aVltS0hRdVpteGhaM044UFRRcGZUdG1kVzVqZEdsdmJpQnJjaWhsTEhRcGUybG1LQ0ZqWlNsemQybDBZMmdvWlM1MFlXbHNUVzlrWlNsN1kyRnpaU0pvYVdS'
    || 'a1pXNGlPblE5WlM1MFlXbHNPMlp2Y2loMllYSWdiajF1ZFd4c08zUWhQVDF1ZFd4c095bDBMbUZzZEdWeWJtRjBaU0U5UFc1MWJHd21KaWh1UFhRcExIUTlk'
    || 'QzV6YVdKc2FXNW5PMjQ5UFQxdWRXeHNQMlV1ZEdGcGJEMXVkV3hzT200dWMybGliR2x1WnoxdWRXeHNPMkp5WldGck8yTmhjMlVpWTI5c2JHRndjMlZrSWpw'
    || 'dVBXVXVkR0ZwYkR0bWIzSW9kbUZ5SUhJOWJuVnNiRHR1SVQwOWJuVnNiRHNwYmk1aGJIUmxjbTVoZEdVaFBUMXVkV3hzSmlZb2NqMXVLU3h1UFc0dWMybGli'
    || 'R2x1Wnp0eVBUMDliblZzYkQ5MGZIeGxMblJoYVd3OVBUMXVkV3hzUDJVdWRHRnBiRDF1ZFd4c09tVXVkR0ZwYkM1emFXSnNhVzVuUFc1MWJHdzZjaTV6YVdK'
    || 'c2FXNW5QVzUxYkd4OWZXWjFibU4wYVc5dUlGQmxLR1VwZTNaaGNpQjBQV1V1WVd4MFpYSnVZWFJsSVQwOWJuVnNiQ1ltWlM1aGJIUmxjbTVoZEdVdVkyaHBi'
    || 'R1E5UFQxbExtTm9hV3hrTEc0OU1DeHlQVEE3YVdZb2RDbG1iM0lvZG1GeUlHdzlaUzVqYUdsc1pEdHNJVDA5Ym5Wc2JEc3Bibnc5YkM1c1lXNWxjM3hzTG1O'
    || 'b2FXeGtUR0Z1WlhNc2NudzliQzV6ZFdKMGNtVmxSbXhoWjNNbU1UUTJPREF3TmpRc2NudzliQzVtYkdGbmN5WXhORFk0TURBMk5DeHNMbkpsZEhWeWJqMWxM'
    || 'R3c5YkM1emFXSnNhVzVuTzJWc2MyVWdabTl5S0d3OVpTNWphR2xzWkR0c0lUMDliblZzYkRzcGJudzliQzVzWVc1bGMzeHNMbU5vYVd4a1RHRnVaWE1zY253'
    || 'OWJDNXpkV0owY21WbFJteGhaM01zY253OWJDNW1iR0ZuY3l4c0xuSmxkSFZ5YmoxbExHdzliQzV6YVdKc2FXNW5PM0psZEhWeWJpQmxMbk4xWW5SeVpXVkdi'
    || 'R0ZuYzN3OWNpeGxMbU5vYVd4a1RHRnVaWE05Yml4MGZXWjFibU4wYVc5dUlGVm1LR1VzZEN4dUtYdDJZWElnY2oxMExuQmxibVJwYm1kUWNtOXdjenR6ZDJs'
    || 'MFkyZ29XV2tvZENrc2RDNTBZV2NwZTJOaGMyVWdNanBqWVhObElERTJPbU5oYzJVZ01UVTZZMkZ6WlNBd09tTmhjMlVnTVRFNlkyRnpaU0EzT21OaGMyVWdP'
    || 'RHBqWVhObElERXlPbU5oYzJVZ09UcGpZWE5sSURFME9uSmxkSFZ5YmlCUVpTaDBLU3h1ZFd4c08yTmhjMlVnTVRweVpYUjFjbTRnVjJVb2RDNTBlWEJsS1NZ'
    || 'bWNtd29LU3hRWlNoMEtTeHVkV3hzTzJOaGMyVWdNenB5WlhSMWNtNGdjajEwTG5OMFlYUmxUbTlrWlN4QmJpZ3BMSFZsS0NSbEtTeDFaU2hTWlNrc2FXOG9L'
    || 'U3h5TG5CbGJtUnBibWREYjI1MFpYaDBKaVlvY2k1amIyNTBaWGgwUFhJdWNHVnVaR2x1WjBOdmJuUmxlSFFzY2k1d1pXNWthVzVuUTI5dWRHVjRkRDF1ZFd4'
    || 'c0tTd29aVDA5UFc1MWJHeDhmR1V1WTJocGJHUTlQVDF1ZFd4c0tTWW1LSFZzS0hRcFAzUXVabXhoWjNOOFBUUTZaVDA5UFc1MWJHeDhmR1V1YldWdGIybDZa'
    || 'V1JUZEdGMFpTNXBjMFJsYUhsa2NtRjBaV1FtSmloMExtWnNZV2R6SmpJMU5pazlQVDB3Zkh3b2RDNW1iR0ZuYzN3OU1UQXlOQ3htZENFOVBXNTFiR3dtSmlo'
    || 'RWJ5aG1kQ2tzWm5ROWJuVnNiQ2twS1N4T2J5aGxMSFFwTEZCbEtIUXBMRzUxYkd3N1kyRnpaU0ExT25KdktIUXBPM1poY2lCc1BXRnVLSGx5TG1OMWNuSmxi'
    || 'blFwTzJsbUtHNDlkQzUwZVhCbExHVWhQVDF1ZFd4c0ppWjBMbk4wWVhSbFRtOWtaU0U5Ym5Wc2JDbFFZU2hsTEhRc2JpeHlMR3dwTEdVdWNtVm1JVDA5ZEM1'
    || 'eVpXWW1KaWgwTG1ac1lXZHpmRDAxTVRJc2RDNW1iR0ZuYzN3OU1qQTVOekUxTWlrN1pXeHpaWHRwWmlnaGNpbDdhV1lvZEM1emRHRjBaVTV2WkdVOVBUMXVk'
    || 'V3hzS1hSb2NtOTNJRVZ5Y205eUtHRW9NVFkyS1NrN2NtVjBkWEp1SUZCbEtIUXBMRzUxYkd4OWFXWW9aVDFoYmloZmRDNWpkWEp5Wlc1MEtTeDFiQ2gwS1Ns'
    || 'N2NqMTBMbk4wWVhSbFRtOWtaU3h1UFhRdWRIbHdaVHQyWVhJZ2FUMTBMbTFsYlc5cGVtVmtVSEp2Y0hNN2MzZHBkR05vS0hKYlUzUmRQWFFzY2x0d2NsMDlh'
    || 'U3hsUFNoMExtMXZaR1VtTVNraFBUMHdMRzRwZTJOaGMyVWlaR2xoYkc5bklqcHpaU2dpWTJGdVkyVnNJaXh5S1N4elpTZ2lZMnh2YzJVaUxISXBPMkp5WldG'
    || 'ck8yTmhjMlVpYVdaeVlXMWxJanBqWVhObEltOWlhbVZqZENJNlkyRnpaU0psYldKbFpDSTZjMlVvSW14dllXUWlMSElwTzJKeVpXRnJPMk5oYzJVaWRtbGta'
    || 'VzhpT21OaGMyVWlZWFZrYVc4aU9tWnZjaWhzUFRBN2JEeGpjaTVzWlc1bmRHZzdiQ3NyS1hObEtHTnlXMnhkTEhJcE8ySnlaV0ZyTzJOaGMyVWljMjkxY21O'
    || 'bElqcHpaU2dpWlhKeWIzSWlMSElwTzJKeVpXRnJPMk5oYzJVaWFXMW5JanBqWVhObEltbHRZV2RsSWpwallYTmxJbXhwYm1zaU9uTmxLQ0psY25KdmNpSXNj'
    || 'aWtzYzJVb0lteHZZV1FpTEhJcE8ySnlaV0ZyTzJOaGMyVWlaR1YwWVdsc2N5STZjMlVvSW5SdloyZHNaU0lzY2lrN1luSmxZV3M3WTJGelpTSnBibkIxZENJ'
    || 'NmNITW9jaXhwS1N4elpTZ2lhVzUyWVd4cFpDSXNjaWs3WW5KbFlXczdZMkZ6WlNKelpXeGxZM1FpT25JdVgzZHlZWEJ3WlhKVGRHRjBaVDE3ZDJGelRYVnNk'
    || 'R2x3YkdVNklTRnBMbTExYkhScGNHeGxmU3h6WlNnaWFXNTJZV3hwWkNJc2NpazdZbkpsWVdzN1kyRnpaU0owWlhoMFlYSmxZU0k2ZG5Nb2NpeHBLU3h6WlNn'
    || 'aWFXNTJZV3hwWkNJc2NpbDliR2tvYml4cEtTeHNQVzUxYkd3N1ptOXlLSFpoY2lCdklHbHVJR2twYVdZb2FTNW9ZWE5QZDI1UWNtOXdaWEowZVNodktTbDdk'
    || 'bUZ5SUdNOWFWdHZYVHR2UFQwOUltTm9hV3hrY21WdUlqOTBlWEJsYjJZZ1l6MDlJbk4wY21sdVp5SS9jaTUwWlhoMFEyOXVkR1Z1ZENFOVBXTW1KaWhwTG5O'
    || 'MWNIQnlaWE56U0hsa2NtRjBhVzl1VjJGeWJtbHVaeUU5UFNFd0ppWmxiQ2h5TG5SbGVIUkRiMjUwWlc1MExHTXNaU2tzYkQxYkltTm9hV3hrY21WdUlpeGpY'
    || 'U2s2ZEhsd1pXOW1JR005UFNKdWRXMWlaWElpSmlaeUxuUmxlSFJEYjI1MFpXNTBJVDA5SWlJcll5WW1LR2t1YzNWd2NISmxjM05JZVdSeVlYUnBiMjVYWVhK'
    || 'dWFXNW5JVDA5SVRBbUptVnNLSEl1ZEdWNGRFTnZiblJsYm5Rc1l5eGxLU3hzUFZzaVkyaHBiR1J5Wlc0aUxDSWlLMk5kS1RwT0xtaGhjMDkzYmxCeWIzQmxj'
    || 'blI1S0c4cEppWmpJVDF1ZFd4c0ppWnZQVDA5SW05dVUyTnliMnhzSWlZbWMyVW9Jbk5qY205c2JDSXNjaWw5YzNkcGRHTm9LRzRwZTJOaGMyVWlhVzV3ZFhR'
    || 'aU9rMXlLSElwTEcxektISXNhU3doTUNrN1luSmxZV3M3WTJGelpTSjBaWGgwWVhKbFlTSTZUWElvY2lrc2VYTW9jaWs3WW5KbFlXczdZMkZ6WlNKelpXeGxZ'
    || 'M1FpT21OaGMyVWliM0IwYVc5dUlqcGljbVZoYXp0a1pXWmhkV3gwT25SNWNHVnZaaUJwTG05dVEyeHBZMnM5UFNKbWRXNWpkR2x2YmlJbUppaHlMbTl1WTJ4'
    || 'cFkyczlkR3dwZlhJOWJDeDBMblZ3WkdGMFpWRjFaWFZsUFhJc2NpRTlQVzUxYkd3bUppaDBMbVpzWVdkemZEMDBLWDFsYkhObGUyODliQzV1YjJSbFZIbHda'
    || 'VDA5UFRrL2JEcHNMbTkzYm1WeVJHOWpkVzFsYm5Rc1pUMDlQU0pvZEhSd09pOHZkM2QzTG5jekxtOXlaeTh4T1RrNUwzaG9kRzFzSWlZbUtHVTllSE1vYmlr'
    || 'cExHVTlQVDBpYUhSMGNEb3ZMM2QzZHk1M015NXZjbWN2TVRrNU9TOTRhSFJ0YkNJL2JqMDlQU0p6WTNKcGNIUWlQeWhsUFc4dVkzSmxZWFJsUld4bGJXVnVk'
    || 'Q2dpWkdsMklpa3NaUzVwYm01bGNraFVUVXc5SWp4elkzSnBjSFErUEZ3dmMyTnlhWEIwUGlJc1pUMWxMbkpsYlc5MlpVTm9hV3hrS0dVdVptbHljM1JEYUds'
    || 'c1pDa3BPblI1Y0dWdlppQnlMbWx6UFQwaWMzUnlhVzVuSWo5bFBXOHVZM0psWVhSbFJXeGxiV1Z1ZENodUxIdHBjenB5TG1semZTazZLR1U5Ynk1amNtVmhk'
    || 'R1ZGYkdWdFpXNTBLRzRwTEc0OVBUMGljMlZzWldOMElpWW1LRzg5WlN4eUxtMTFiSFJwY0d4bFAyOHViWFZzZEdsd2JHVTlJVEE2Y2k1emFYcGxKaVlvYnk1'
    || 'emFYcGxQWEl1YzJsNlpTa3BLVHBsUFc4dVkzSmxZWFJsUld4bGJXVnVkRTVUS0dVc2Jpa3NaVnRUZEYwOWRDeGxXM0J5WFQxeUxFMWhLR1VzZEN3aE1Td2hN'
    || 'U2tzZEM1emRHRjBaVTV2WkdVOVpUdGxPbnR6ZDJsMFkyZ29iejFwYVNodUxISXBMRzRwZTJOaGMyVWlaR2xoYkc5bklqcHpaU2dpWTJGdVkyVnNJaXhsS1N4'
    || 'elpTZ2lZMnh2YzJVaUxHVXBMR3c5Y2p0aWNtVmhhenRqWVhObEltbG1jbUZ0WlNJNlkyRnpaU0p2WW1wbFkzUWlPbU5oYzJVaVpXMWlaV1FpT25ObEtDSnNi'
    || 'MkZrSWl4bEtTeHNQWEk3WW5KbFlXczdZMkZ6WlNKMmFXUmxieUk2WTJGelpTSmhkV1JwYnlJNlptOXlLR3c5TUR0c1BHTnlMbXhsYm1kMGFEdHNLeXNwYzJV'
    || 'b1kzSmJiRjBzWlNrN2JEMXlPMkp5WldGck8yTmhjMlVpYzI5MWNtTmxJanB6WlNnaVpYSnliM0lpTEdVcExHdzljanRpY21WaGF6dGpZWE5sSW1sdFp5STZZ'
    || 'MkZ6WlNKcGJXRm5aU0k2WTJGelpTSnNhVzVySWpwelpTZ2laWEp5YjNJaUxHVXBMSE5sS0NKc2IyRmtJaXhsS1N4c1BYSTdZbkpsWVdzN1kyRnpaU0prWlhS'
    || 'aGFXeHpJanB6WlNnaWRHOW5aMnhsSWl4bEtTeHNQWEk3WW5KbFlXczdZMkZ6WlNKcGJuQjFkQ0k2Y0hNb1pTeHlLU3hzUFdKc0tHVXNjaWtzYzJVb0ltbHVk'
    || 'bUZzYVdRaUxHVXBPMkp5WldGck8yTmhjMlVpYjNCMGFXOXVJanBzUFhJN1luSmxZV3M3WTJGelpTSnpaV3hsWTNRaU9tVXVYM2R5WVhCd1pYSlRkR0YwWlQx'
    || 'N2QyRnpUWFZzZEdsd2JHVTZJU0Z5TG0xMWJIUnBjR3hsZlN4c1BVOG9lMzBzY2l4N2RtRnNkV1U2ZG05cFpDQXdmU2tzYzJVb0ltbHVkbUZzYVdRaUxHVXBP'
    || 'Mkp5WldGck8yTmhjMlVpZEdWNGRHRnlaV0VpT25aektHVXNjaWtzYkQxdWFTaGxMSElwTEhObEtDSnBiblpoYkdsa0lpeGxLVHRpY21WaGF6dGtaV1poZFd4'
    || 'ME9tdzljbjFzYVNodUxHd3BMR005YkR0bWIzSW9hU0JwYmlCaktXbG1LR011YUdGelQzZHVVSEp2Y0dWeWRIa29hU2twZTNaaGNpQmtQV05iYVYwN2FUMDlQ'
    || 'U0p6ZEhsc1pTSS9YM01vWlN4a0tUcHBQVDA5SW1SaGJtZGxjbTkxYzJ4NVUyVjBTVzV1WlhKSVZFMU1JajhvWkQxa1AyUXVYMTlvZEcxc09uWnZhV1FnTUN4'
    || 'a0lUMXVkV3hzSmlaM2N5aGxMR1FwS1RwcFBUMDlJbU5vYVd4a2NtVnVJajkwZVhCbGIyWWdaRDA5SW5OMGNtbHVaeUkvS0c0aFBUMGlkR1Y0ZEdGeVpXRWlm'
    || 'SHhrSVQwOUlpSXBKaVpSYmlobExHUXBPblI1Y0dWdlppQmtQVDBpYm5WdFltVnlJaVltVVc0b1pTd2lJaXRrS1RwcElUMDlJbk4xY0hCeVpYTnpRMjl1ZEdW'
    || 'dWRFVmthWFJoWW14bFYyRnlibWx1WnlJbUpta2hQVDBpYzNWd2NISmxjM05JZVdSeVlYUnBiMjVYWVhKdWFXNW5JaVltYVNFOVBTSmhkWFJ2Um05amRYTWlK'
    || 'aVlvVGk1b1lYTlBkMjVRY205d1pYSjBlU2hwS1Q5a0lUMXVkV3hzSmlacFBUMDlJbTl1VTJOeWIyeHNJaVltYzJVb0luTmpjbTlzYkNJc1pTazZaQ0U5Ym5W'
    || 'c2JDWW1UR1VvWlN4cExHUXNieWtwZlhOM2FYUmphQ2h1S1h0allYTmxJbWx1Y0hWMElqcE5jaWhsS1N4dGN5aGxMSElzSVRFcE8ySnlaV0ZyTzJOaGMyVWlk'
    || 'R1Y0ZEdGeVpXRWlPazF5S0dVcExIbHpLR1VwTzJKeVpXRnJPMk5oYzJVaWIzQjBhVzl1SWpweUxuWmhiSFZsSVQxdWRXeHNKaVpsTG5ObGRFRjBkSEpwWW5W'
    || 'MFpTZ2lkbUZzZFdVaUxDSWlLM1JsS0hJdWRtRnNkV1VwS1R0aWNtVmhhenRqWVhObEluTmxiR1ZqZENJNlpTNXRkV3gwYVhCc1pUMGhJWEl1YlhWc2RHbHdi'
    || 'R1VzYVQxeUxuWmhiSFZsTEdraFBXNTFiR3cvZVc0b1pTd2hJWEl1YlhWc2RHbHdiR1VzYVN3aE1TazZjaTVrWldaaGRXeDBWbUZzZFdVaFBXNTFiR3dtSm5s'
    || 'dUtHVXNJU0Z5TG0xMWJIUnBjR3hsTEhJdVpHVm1ZWFZzZEZaaGJIVmxMQ0V3S1R0aWNtVmhhenRrWldaaGRXeDBPblI1Y0dWdlppQnNMbTl1UTJ4cFkyczlQ'
    || 'U0ptZFc1amRHbHZiaUltSmlobExtOXVZMnhwWTJzOWRHd3BmWE4zYVhSamFDaHVLWHRqWVhObEltSjFkSFJ2YmlJNlkyRnpaU0pwYm5CMWRDSTZZMkZ6WlNK'
    || 'elpXeGxZM1FpT21OaGMyVWlkR1Y0ZEdGeVpXRWlPbkk5SVNGeUxtRjFkRzlHYjJOMWN6dGljbVZoYXlCbE8yTmhjMlVpYVcxbklqcHlQU0V3TzJKeVpXRnJJ'
    || 'R1U3WkdWbVlYVnNkRHB5UFNFeGZYMXlKaVlvZEM1bWJHRm5jM3c5TkNsOWRDNXlaV1loUFQxdWRXeHNKaVlvZEM1bWJHRm5jM3c5TlRFeUxIUXVabXhoWjNO'
    || 'OFBUSXdPVGN4TlRJcGZYSmxkSFZ5YmlCUVpTaDBLU3h1ZFd4c08yTmhjMlVnTmpwcFppaGxKaVowTG5OMFlYUmxUbTlrWlNFOWJuVnNiQ2xQWVNobExIUXNa'
    || 'UzV0WlcxdmFYcGxaRkJ5YjNCekxISXBPMlZzYzJWN2FXWW9kSGx3Wlc5bUlISWhQU0p6ZEhKcGJtY2lKaVowTG5OMFlYUmxUbTlrWlQwOVBXNTFiR3dwZEdo'
    || 'eWIzY2dSWEp5YjNJb1lTZ3hOallwS1R0cFppaHVQV0Z1S0hseUxtTjFjbkpsYm5RcExHRnVLRjkwTG1OMWNuSmxiblFwTEhWc0tIUXBLWHRwWmloeVBYUXVj'
    || 'M1JoZEdWT2IyUmxMRzQ5ZEM1dFpXMXZhWHBsWkZCeWIzQnpMSEpiVTNSZFBYUXNLR2s5Y2k1dWIyUmxWbUZzZFdVaFBUMXVLU1ltS0dVOVdtVXNaU0U5UFc1'
    || 'MWJHd3BLWE4zYVhSamFDaGxMblJoWnlsN1kyRnpaU0F6T21Wc0tISXVibTlrWlZaaGJIVmxMRzRzS0dVdWJXOWtaU1l4S1NFOVBUQXBPMkp5WldGck8yTmhj'
    || 'MlVnTlRwbExtMWxiVzlwZW1Wa1VISnZjSE11YzNWd2NISmxjM05JZVdSeVlYUnBiMjVYWVhKdWFXNW5JVDA5SVRBbUptVnNLSEl1Ym05a1pWWmhiSFZsTEc0'
    || 'c0tHVXViVzlrWlNZeEtTRTlQVEFwZldrbUppaDBMbVpzWVdkemZEMDBLWDFsYkhObElISTlLRzR1Ym05a1pWUjVjR1U5UFQwNVAyNDZiaTV2ZDI1bGNrUnZZ'
    || 'M1Z0Wlc1MEtTNWpjbVZoZEdWVVpYaDBUbTlrWlNoeUtTeHlXMU4wWFQxMExIUXVjM1JoZEdWT2IyUmxQWEo5Y21WMGRYSnVJRkJsS0hRcExHNTFiR3c3WTJG'
    || 'elpTQXhNenBwWmloMVpTaGtaU2tzY2oxMExtMWxiVzlwZW1Wa1UzUmhkR1VzWlQwOVBXNTFiR3g4ZkdVdWJXVnRiMmw2WldSVGRHRjBaU0U5UFc1MWJHd21K'
    || 'bVV1YldWdGIybDZaV1JUZEdGMFpTNWtaV2g1WkhKaGRHVmtJVDA5Ym5Wc2JDbDdhV1lvWTJVbUprcGxJVDA5Ym5Wc2JDWW1LSFF1Ylc5a1pTWXhLU0U5UFRB'
    || 'bUppaDBMbVpzWVdkekpqRXlPQ2s5UFQwd0tVUjFLQ2tzVDI0b0tTeDBMbVpzWVdkemZEMDVPRFUyTUN4cFBTRXhPMlZzYzJVZ2FXWW9hVDExYkNoMEtTeHlJ'
    || 'VDA5Ym5Wc2JDWW1jaTVrWldoNVpISmhkR1ZrSVQwOWJuVnNiQ2w3YVdZb1pUMDlQVzUxYkd3cGUybG1LQ0ZwS1hSb2NtOTNJRVZ5Y205eUtHRW9NekU0S1Nr'
    || 'N2FXWW9hVDEwTG0xbGJXOXBlbVZrVTNSaGRHVXNhVDFwSVQwOWJuVnNiRDlwTG1SbGFIbGtjbUYwWldRNmJuVnNiQ3doYVNsMGFISnZkeUJGY25KdmNpaGhL'
    || 'RE14TnlrcE8ybGJVM1JkUFhSOVpXeHpaU0JQYmlncExDaDBMbVpzWVdkekpqRXlPQ2s5UFQwd0ppWW9kQzV0WlcxdmFYcGxaRk4wWVhSbFBXNTFiR3dwTEhR'
    || 'dVpteGhaM044UFRRN1VHVW9kQ2tzYVQwaE1YMWxiSE5sSUdaMElUMDliblZzYkNZbUtFUnZLR1owS1N4bWREMXVkV3hzS1N4cFBTRXdPMmxtS0NGcEtYSmxk'
    || 'SFZ5YmlCMExtWnNZV2R6SmpZMU5UTTJQM1E2Ym5Wc2JIMXlaWFIxY200b2RDNW1iR0ZuY3lZeE1qZ3BJVDA5TUQ4b2RDNXNZVzVsY3oxdUxIUXBPaWh5UFhJ'
    || 'aFBUMXVkV3hzTEhJaFBUMG9aU0U5UFc1MWJHd21KbVV1YldWdGIybDZaV1JUZEdGMFpTRTlQVzUxYkd3cEppWnlKaVlvZEM1amFHbHNaQzVtYkdGbmMzdzlP'
    || 'REU1TWl3b2RDNXRiMlJsSmpFcElUMDlNQ1ltS0dVOVBUMXVkV3hzZkh3b1pHVXVZM1Z5Y21WdWRDWXhLU0U5UFRBL2QyVTlQVDB3SmlZb2QyVTlNeWs2Vlc4'
    || 'b0tTa3BMSFF1ZFhCa1lYUmxVWFZsZFdVaFBUMXVkV3hzSmlZb2RDNW1iR0ZuYzN3OU5Da3NVR1VvZENrc2JuVnNiQ2s3WTJGelpTQTBPbkpsZEhWeWJpQkJi'
    || 'aWdwTEU1dktHVXNkQ2tzWlQwOVBXNTFiR3dtSm1SeUtIUXVjM1JoZEdWT2IyUmxMbU52Ym5SaGFXNWxja2x1Wm04cExGQmxLSFFwTEc1MWJHdzdZMkZ6WlNB'
    || 'eE1EcHlaWFIxY200Z2NXa29kQzUwZVhCbExsOWpiMjUwWlhoMEtTeFFaU2gwS1N4dWRXeHNPMk5oYzJVZ01UYzZjbVYwZFhKdUlGZGxLSFF1ZEhsd1pTa21K'
    || 'bkpzS0Nrc1VHVW9kQ2tzYm5Wc2JEdGpZWE5sSURFNU9tbG1LSFZsS0dSbEtTeHBQWFF1YldWdGIybDZaV1JUZEdGMFpTeHBQVDA5Ym5Wc2JDbHlaWFIxY200'
    || 'Z1VHVW9kQ2tzYm5Wc2JEdHBaaWh5UFNoMExtWnNZV2R6SmpFeU9Da2hQVDB3TEc4OWFTNXlaVzVrWlhKcGJtY3NiejA5UFc1MWJHd3BhV1lvY2lscmNpaHBM'
    || 'Q0V4S1R0bGJITmxlMmxtS0hkbElUMDlNSHg4WlNFOVBXNTFiR3dtSmlobExtWnNZV2R6SmpFeU9Da2hQVDB3S1dadmNpaGxQWFF1WTJocGJHUTdaU0U5UFc1'
    || 'MWJHdzdLWHRwWmlodlBXaHNLR1VwTEc4aFBUMXVkV3hzS1h0bWIzSW9kQzVtYkdGbmMzdzlNVEk0TEd0eUtHa3NJVEVwTEhJOWJ5NTFjR1JoZEdWUmRXVjFa'
    || 'U3h5SVQwOWJuVnNiQ1ltS0hRdWRYQmtZWFJsVVhWbGRXVTljaXgwTG1ac1lXZHpmRDAwS1N4MExuTjFZblJ5WldWR2JHRm5jejB3TEhJOWJpeHVQWFF1WTJo'
    || 'cGJHUTdiaUU5UFc1MWJHdzdLV2s5Yml4bFBYSXNhUzVtYkdGbmN5WTlNVFEyT0RBd05qWXNiejFwTG1Gc2RHVnlibUYwWlN4dlBUMDliblZzYkQ4b2FTNWph'
    || 'R2xzWkV4aGJtVnpQVEFzYVM1c1lXNWxjejFsTEdrdVkyaHBiR1E5Ym5Wc2JDeHBMbk4xWW5SeVpXVkdiR0ZuY3owd0xHa3ViV1Z0YjJsNlpXUlFjbTl3Y3ox'
    || 'dWRXeHNMR2t1YldWdGIybDZaV1JUZEdGMFpUMXVkV3hzTEdrdWRYQmtZWFJsVVhWbGRXVTliblZzYkN4cExtUmxjR1Z1WkdWdVkybGxjejF1ZFd4c0xHa3Vj'
    || 'M1JoZEdWT2IyUmxQVzUxYkd3cE9paHBMbU5vYVd4a1RHRnVaWE05Ynk1amFHbHNaRXhoYm1WekxHa3ViR0Z1WlhNOWJ5NXNZVzVsY3l4cExtTm9hV3hrUFc4'
    || 'dVkyaHBiR1FzYVM1emRXSjBjbVZsUm14aFozTTlNQ3hwTG1SbGJHVjBhVzl1Y3oxdWRXeHNMR2t1YldWdGIybDZaV1JRY205d2N6MXZMbTFsYlc5cGVtVmtV'
    || 'SEp2Y0hNc2FTNXRaVzF2YVhwbFpGTjBZWFJsUFc4dWJXVnRiMmw2WldSVGRHRjBaU3hwTG5Wd1pHRjBaVkYxWlhWbFBXOHVkWEJrWVhSbFVYVmxkV1VzYVM1'
    || 'MGVYQmxQVzh1ZEhsd1pTeGxQVzh1WkdWd1pXNWtaVzVqYVdWekxHa3VaR1Z3Wlc1a1pXNWphV1Z6UFdVOVBUMXVkV3hzUDI1MWJHdzZlMnhoYm1Wek9tVXVi'
    || 'R0Z1WlhNc1ptbHljM1JEYjI1MFpYaDBPbVV1Wm1seWMzUkRiMjUwWlhoMGZTa3NiajF1TG5OcFlteHBibWM3Y21WMGRYSnVJR2xsS0dSbExHUmxMbU4xY25K'
    || 'bGJuUW1NWHd5S1N4MExtTm9hV3hrZldVOVpTNXphV0pzYVc1bmZXa3VkR0ZwYkNFOVBXNTFiR3dtSm5abEtDaytKRzRtSmloMExtWnNZV2R6ZkQweE1qZ3Nj'
    || 'ajBoTUN4cmNpaHBMQ0V4S1N4MExteGhibVZ6UFRReE9UUXpNRFFwZldWc2MyVjdhV1lvSVhJcGFXWW9aVDFvYkNodktTeGxJVDA5Ym5Wc2JDbDdhV1lvZEM1'
    || 'bWJHRm5jM3c5TVRJNExISTlJVEFzYmoxbExuVndaR0YwWlZGMVpYVmxMRzRoUFQxdWRXeHNKaVlvZEM1MWNHUmhkR1ZSZFdWMVpUMXVMSFF1Wm14aFozTjhQ'
    || 'VFFwTEd0eUtHa3NJVEFwTEdrdWRHRnBiRDA5UFc1MWJHd21KbWt1ZEdGcGJFMXZaR1U5UFQwaWFHbGtaR1Z1SWlZbUlXOHVZV3gwWlhKdVlYUmxKaVloWTJV'
    || 'cGNtVjBkWEp1SUZCbEtIUXBMRzUxYkd4OVpXeHpaU0F5S25abEtDa3RhUzV5Wlc1a1pYSnBibWRUZEdGeWRGUnBiV1UrSkc0bUptNGhQVDB4TURjek56UXhP'
    || 'REkwSmlZb2RDNW1iR0ZuYzN3OU1USTRMSEk5SVRBc2EzSW9hU3doTVNrc2RDNXNZVzVsY3owME1UazBNekEwS1R0cExtbHpRbUZqYTNkaGNtUnpQeWh2TG5O'
    || 'cFlteHBibWM5ZEM1amFHbHNaQ3gwTG1Ob2FXeGtQVzhwT2lodVBXa3ViR0Z6ZEN4dUlUMDliblZzYkQ5dUxuTnBZbXhwYm1jOWJ6cDBMbU5vYVd4a1BXOHNh'
    || 'UzVzWVhOMFBXOHBmWEpsZEhWeWJpQnBMblJoYVd3aFBUMXVkV3hzUHloMFBXa3VkR0ZwYkN4cExuSmxibVJsY21sdVp6MTBMR2t1ZEdGcGJEMTBMbk5wWW14'
    || 'cGJtY3NhUzV5Wlc1a1pYSnBibWRUZEdGeWRGUnBiV1U5ZG1Vb0tTeDBMbk5wWW14cGJtYzliblZzYkN4dVBXUmxMbU4xY25KbGJuUXNhV1VvWkdVc2NqOXVK'
    || 'akY4TWpwdUpqRXBMSFFwT2loUVpTaDBLU3h1ZFd4c0tUdGpZWE5sSURJeU9tTmhjMlVnTWpNNmNtVjBkWEp1SUVadktDa3NjajEwTG0xbGJXOXBlbVZrVTNS'
    || 'aGRHVWhQVDF1ZFd4c0xHVWhQVDF1ZFd4c0ppWmxMbTFsYlc5cGVtVmtVM1JoZEdVaFBUMXVkV3hzSVQwOWNpWW1LSFF1Wm14aFozTjhQVGd4T1RJcExISW1K'
    || 'aWgwTG0xdlpHVW1NU2toUFQwd1B5aHhaU1l4TURjek56UXhPREkwS1NFOVBUQW1KaWhRWlNoMEtTeDBMbk4xWW5SeVpXVkdiR0ZuY3lZMkppWW9kQzVtYkdG'
    || 'bmMzdzlPREU1TWlrcE9sQmxLSFFwTEc1MWJHdzdZMkZ6WlNBeU5EcHlaWFIxY200Z2JuVnNiRHRqWVhObElESTFPbkpsZEhWeWJpQnVkV3hzZlhSb2NtOTNJ'
    || 'RVZ5Y205eUtHRW9NVFUyTEhRdWRHRm5LU2w5Wm5WdVkzUnBiMjRnU0dZb1pTeDBLWHR6ZDJsMFkyZ29XV2tvZENrc2RDNTBZV2NwZTJOaGMyVWdNVHB5WlhS'
    || 'MWNtNGdWMlVvZEM1MGVYQmxLU1ltY213b0tTeGxQWFF1Wm14aFozTXNaU1kyTlRVek5qOG9kQzVtYkdGbmN6MWxKaTAyTlRVek4zd3hNamdzZENrNmJuVnNi'
    || 'RHRqWVhObElETTZjbVYwZFhKdUlFRnVLQ2tzZFdVb0pHVXBMSFZsS0ZKbEtTeHBieWdwTEdVOWRDNW1iR0ZuY3l3b1pTWTJOVFV6TmlraFBUMHdKaVlvWlNZ'
    || 'eE1qZ3BQVDA5TUQ4b2RDNW1iR0ZuY3oxbEppMDJOVFV6TjN3eE1qZ3NkQ2s2Ym5Wc2JEdGpZWE5sSURVNmNtVjBkWEp1SUhKdktIUXBMRzUxYkd3N1kyRnpa'
    || 'U0F4TXpwcFppaDFaU2hrWlNrc1pUMTBMbTFsYlc5cGVtVmtVM1JoZEdVc1pTRTlQVzUxYkd3bUptVXVaR1ZvZVdSeVlYUmxaQ0U5UFc1MWJHd3BlMmxtS0hR'
    || 'dVlXeDBaWEp1WVhSbFBUMDliblZzYkNsMGFISnZkeUJGY25KdmNpaGhLRE0wTUNrcE8wOXVLQ2w5Y21WMGRYSnVJR1U5ZEM1bWJHRm5jeXhsSmpZMU5UTTJQ'
    || 'eWgwTG1ac1lXZHpQV1VtTFRZMU5UTTNmREV5T0N4MEtUcHVkV3hzTzJOaGMyVWdNVGs2Y21WMGRYSnVJSFZsS0dSbEtTeHVkV3hzTzJOaGMyVWdORHB5WlhS'
    || 'MWNtNGdRVzRvS1N4dWRXeHNPMk5oYzJVZ01UQTZjbVYwZFhKdUlIRnBLSFF1ZEhsd1pTNWZZMjl1ZEdWNGRDa3NiblZzYkR0allYTmxJREl5T21OaGMyVWdN'
    || 'ak02Y21WMGRYSnVJRVp2S0Nrc2JuVnNiRHRqWVhObElESTBPbkpsZEhWeWJpQnVkV3hzTzJSbFptRjFiSFE2Y21WMGRYSnVJRzUxYkd4OWZYWmhjaUJyYkQw'
    || 'aE1TeFBaVDBoTVN3a1pqMTBlWEJsYjJZZ1YyVmhhMU5sZEQwOUltWjFibU4wYVc5dUlqOVhaV0ZyVTJWME9sTmxkQ3hRUFc1MWJHdzdablZ1WTNScGIyNGdW'
    || 'VzRvWlN4MEtYdDJZWElnYmoxbExuSmxaanRwWmlodUlUMDliblZzYkNscFppaDBlWEJsYjJZZ2JqMDlJbVoxYm1OMGFXOXVJaWwwY25sN2JpaHVkV3hzS1gx'
    || 'allYUmphQ2h5S1h0dFpTaGxMSFFzY2lsOVpXeHpaU0J1TG1OMWNuSmxiblE5Ym5Wc2JIMW1kVzVqZEdsdmJpQnFieWhsTEhRc2JpbDdkSEo1ZTI0b0tYMWpZ'
    || 'WFJqYUNoeUtYdHRaU2hsTEhRc2NpbDlmWFpoY2lCSllUMGhNVHRtZFc1amRHbHZiaUJYWmlobExIUXBlMmxtS0VGcFBWWnlMR1U5Wm5Vb0tTeE1hU2hsS1Ns'
    || 'N2FXWW9Jbk5sYkdWamRHbHZibE4wWVhKMEltbHVJR1VwZG1GeUlHNDllM04wWVhKME9tVXVjMlZzWldOMGFXOXVVM1JoY25Rc1pXNWtPbVV1YzJWc1pXTjBh'
    || 'Vzl1Ulc1a2ZUdGxiSE5sSUdVNmUyNDlLRzQ5WlM1dmQyNWxja1J2WTNWdFpXNTBLU1ltYmk1a1pXWmhkV3gwVm1sbGQzeDhkMmx1Wkc5M08zWmhjaUJ5UFc0'
    || 'dVoyVjBVMlZzWldOMGFXOXVKaVp1TG1kbGRGTmxiR1ZqZEdsdmJpZ3BPMmxtS0hJbUpuSXVjbUZ1WjJWRGIzVnVkQ0U5UFRBcGUyNDljaTVoYm1Ob2IzSk9i'
    || 'MlJsTzNaaGNpQnNQWEl1WVc1amFHOXlUMlptYzJWMExHazljaTVtYjJOMWMwNXZaR1U3Y2oxeUxtWnZZM1Z6VDJabWMyVjBPM1J5ZVh0dUxtNXZaR1ZVZVhC'
    || 'bExHa3VibTlrWlZSNWNHVjlZMkYwWTJoN2JqMXVkV3hzTzJKeVpXRnJJR1Y5ZG1GeUlHODlNQ3hqUFMweExHUTlMVEVzWnowd0xFVTlNQ3hxUFdVc1V6MXVk'
    || 'V3hzTzNRNlptOXlLRHM3S1h0bWIzSW9kbUZ5SUUwN2FpRTlQVzU4Zkd3aFBUMHdKaVpxTG01dlpHVlVlWEJsSVQwOU0zeDhLR005Ynl0c0tTeHFJVDA5YVh4'
    || 'OGNpRTlQVEFtSm1vdWJtOWtaVlI1Y0dVaFBUMHpmSHdvWkQxdkszSXBMR291Ym05a1pWUjVjR1U5UFQwekppWW9ieXM5YWk1dWIyUmxWbUZzZFdVdWJHVnVa'
    || 'M1JvS1N3b1RUMXFMbVpwY25OMFEyaHBiR1FwSVQwOWJuVnNiRHNwVXoxcUxHbzlUVHRtYjNJb096c3BlMmxtS0dvOVBUMWxLV0p5WldGcklIUTdhV1lvVXow'
    || 'OVBXNG1KaXNyWnowOVBXd21KaWhqUFc4cExGTTlQVDFwSmlZckswVTlQVDF5SmlZb1pEMXZLU3dvVFQxcUxtNWxlSFJUYVdKc2FXNW5LU0U5UFc1MWJHd3BZ'
    || 'bkpsWVdzN2FqMVRMRk05YWk1d1lYSmxiblJPYjJSbGZXbzlUWDF1UFdNOVBUMHRNWHg4WkQwOVBTMHhQMjUxYkd3NmUzTjBZWEowT21Nc1pXNWtPbVI5ZldW'
    || 'c2MyVWdiajF1ZFd4c2ZXNDlibng4ZTNOMFlYSjBPakFzWlc1a09qQjlmV1ZzYzJVZ2JqMXVkV3hzTzJadmNpaEdhVDE3Wm05amRYTmxaRVZzWlcwNlpTeHpa'
    || 'V3hsWTNScGIyNVNZVzVuWlRwdWZTeFdjajBoTVN4UVBYUTdVQ0U5UFc1MWJHdzdLV2xtS0hROVVDeGxQWFF1WTJocGJHUXNLSFF1YzNWaWRISmxaVVpzWVdk'
    || 'ekpqRXdNamdwSVQwOU1DWW1aU0U5UFc1MWJHd3BaUzV5WlhSMWNtNDlkQ3hRUFdVN1pXeHpaU0JtYjNJb08xQWhQVDF1ZFd4c095bDdkRDFRTzNSeWVYdDJZ'
    || 'WElnU1QxMExtRnNkR1Z5Ym1GMFpUdHBaaWdvZEM1bWJHRm5jeVl4TURJMEtTRTlQVEFwYzNkcGRHTm9LSFF1ZEdGbktYdGpZWE5sSURBNlkyRnpaU0F4TVRw'
    || 'allYTmxJREUxT21KeVpXRnJPMk5oYzJVZ01UcHBaaWhKSVQwOWJuVnNiQ2w3ZG1GeUlIbzlTUzV0WlcxdmFYcGxaRkJ5YjNCekxHZGxQVWt1YldWdGIybDZa'
    || 'V1JUZEdGMFpTeHRQWFF1YzNSaGRHVk9iMlJsTEhBOWJTNW5aWFJUYm1Gd2MyaHZkRUpsWm05eVpWVndaR0YwWlNoMExtVnNaVzFsYm5SVWVYQmxQVDA5ZEM1'
    || 'MGVYQmxQM282Y0hRb2RDNTBlWEJsTEhvcExHZGxLVHR0TGw5ZmNtVmhZM1JKYm5SbGNtNWhiRk51WVhCemFHOTBRbVZtYjNKbFZYQmtZWFJsUFhCOVluSmxZ'
    || 'V3M3WTJGelpTQXpPblpoY2lCMlBYUXVjM1JoZEdWT2IyUmxMbU52Ym5SaGFXNWxja2x1Wm04N2RpNXViMlJsVkhsd1pUMDlQVEUvZGk1MFpYaDBRMjl1ZEdW'
    || 'dWREMGlJanAyTG01dlpHVlVlWEJsUFQwOU9TWW1kaTVrYjJOMWJXVnVkRVZzWlcxbGJuUW1Kbll1Y21WdGIzWmxRMmhwYkdRb2RpNWtiMk4xYldWdWRFVnNa'
    || 'VzFsYm5RcE8ySnlaV0ZyTzJOaGMyVWdOVHBqWVhObElEWTZZMkZ6WlNBME9tTmhjMlVnTVRjNlluSmxZV3M3WkdWbVlYVnNkRHAwYUhKdmR5QkZjbkp2Y2lo'
    || 'aEtERTJNeWtwZlgxallYUmphQ2hVS1h0dFpTaDBMSFF1Y21WMGRYSnVMRlFwZldsbUtHVTlkQzV6YVdKc2FXNW5MR1VoUFQxdWRXeHNLWHRsTG5KbGRIVnli'
    || 'ajEwTG5KbGRIVnliaXhRUFdVN1luSmxZV3Q5VUQxMExuSmxkSFZ5Ym4xeVpYUjFjbTRnU1QxSllTeEpZVDBoTVN4SmZXWjFibU4wYVc5dUlFVnlLR1VzZEN4'
    || 'dUtYdDJZWElnY2oxMExuVndaR0YwWlZGMVpYVmxPMmxtS0hJOWNpRTlQVzUxYkd3L2NpNXNZWE4wUldabVpXTjBPbTUxYkd3c2NpRTlQVzUxYkd3cGUzWmhj'
    || 'aUJzUFhJOWNpNXVaWGgwTzJSdmUybG1LQ2hzTG5SaFp5WmxLVDA5UFdVcGUzWmhjaUJwUFd3dVpHVnpkSEp2ZVR0c0xtUmxjM1J5YjNrOWRtOXBaQ0F3TEdr'
    || 'aFBUMTJiMmxrSURBbUptcHZLSFFzYml4cEtYMXNQV3d1Ym1WNGRIMTNhR2xzWlNoc0lUMDljaWw5ZldaMWJtTjBhVzl1SUVWc0tHVXNkQ2w3YVdZb2REMTBM'
    || 'blZ3WkdGMFpWRjFaWFZsTEhROWRDRTlQVzUxYkd3L2RDNXNZWE4wUldabVpXTjBPbTUxYkd3c2RDRTlQVzUxYkd3cGUzWmhjaUJ1UFhROWRDNXVaWGgwTzJS'
    || 'dmUybG1LQ2h1TG5SaFp5WmxLVDA5UFdVcGUzWmhjaUJ5UFc0dVkzSmxZWFJsTzI0dVpHVnpkSEp2ZVQxeUtDbDliajF1TG01bGVIUjlkMmhwYkdVb2JpRTlQ'
    || 'WFFwZlgxbWRXNWpkR2x2YmlCVWJ5aGxLWHQyWVhJZ2REMWxMbkpsWmp0cFppaDBJVDA5Ym5Wc2JDbDdkbUZ5SUc0OVpTNXpkR0YwWlU1dlpHVTdjM2RwZEdO'
    || 'b0tHVXVkR0ZuS1h0allYTmxJRFU2WlQxdU8ySnlaV0ZyTzJSbFptRjFiSFE2WlQxdWZYUjVjR1Z2WmlCMFBUMGlablZ1WTNScGIyNGlQM1FvWlNrNmRDNWpk'
    || 'WEp5Wlc1MFBXVjlmV1oxYm1OMGFXOXVJSHBoS0dVcGUzWmhjaUIwUFdVdVlXeDBaWEp1WVhSbE8zUWhQVDF1ZFd4c0ppWW9aUzVoYkhSbGNtNWhkR1U5Ym5W'
    || 'c2JDeDZZU2gwS1Nrc1pTNWphR2xzWkQxdWRXeHNMR1V1WkdWc1pYUnBiMjV6UFc1MWJHd3NaUzV6YVdKc2FXNW5QVzUxYkd3c1pTNTBZV2M5UFQwMUppWW9k'
    || 'RDFsTG5OMFlYUmxUbTlrWlN4MElUMDliblZzYkNZbUtHUmxiR1YwWlNCMFcxTjBYU3hrWld4bGRHVWdkRnR3Y2wwc1pHVnNaWFJsSUhSYlYybGRMR1JsYkdW'
    || 'MFpTQjBXMFZtWFN4a1pXeGxkR1VnZEZ0T1psMHBLU3hsTG5OMFlYUmxUbTlrWlQxdWRXeHNMR1V1Y21WMGRYSnVQVzUxYkd3c1pTNWtaWEJsYm1SbGJtTnBa'
    || 'WE05Ym5Wc2JDeGxMbTFsYlc5cGVtVmtVSEp2Y0hNOWJuVnNiQ3hsTG0xbGJXOXBlbVZrVTNSaGRHVTliblZzYkN4bExuQmxibVJwYm1kUWNtOXdjejF1ZFd4'
    || 'c0xHVXVjM1JoZEdWT2IyUmxQVzUxYkd3c1pTNTFjR1JoZEdWUmRXVjFaVDF1ZFd4c2ZXWjFibU4wYVc5dUlFUmhLR1VwZTNKbGRIVnliaUJsTG5SaFp6MDlQ'
    || 'VFY4ZkdVdWRHRm5QVDA5TTN4OFpTNTBZV2M5UFQwMGZXWjFibU4wYVc5dUlFRmhLR1VwZTJVNlptOXlLRHM3S1h0bWIzSW9PMlV1YzJsaWJHbHVaejA5UFc1'
    || 'MWJHdzdLWHRwWmlobExuSmxkSFZ5YmowOVBXNTFiR3g4ZkVSaEtHVXVjbVYwZFhKdUtTbHlaWFIxY200Z2JuVnNiRHRsUFdVdWNtVjBkWEp1ZldadmNpaGxM'
    || 'bk5wWW14cGJtY3VjbVYwZFhKdVBXVXVjbVYwZFhKdUxHVTlaUzV6YVdKc2FXNW5PMlV1ZEdGbklUMDlOU1ltWlM1MFlXY2hQVDAySmlabExuUmhaeUU5UFRF'
    || 'NE95bDdhV1lvWlM1bWJHRm5jeVl5Zkh4bExtTm9hV3hrUFQwOWJuVnNiSHg4WlM1MFlXYzlQVDAwS1dOdmJuUnBiblZsSUdVN1pTNWphR2xzWkM1eVpYUjFj'
    || 'bTQ5WlN4bFBXVXVZMmhwYkdSOWFXWW9JU2hsTG1ac1lXZHpKaklwS1hKbGRIVnliaUJsTG5OMFlYUmxUbTlrWlgxOVpuVnVZM1JwYjI0Z1EyOG9aU3gwTEc0'
    || 'cGUzWmhjaUJ5UFdVdWRHRm5PMmxtS0hJOVBUMDFmSHh5UFQwOU5pbGxQV1V1YzNSaGRHVk9iMlJsTEhRL2JpNXViMlJsVkhsd1pUMDlQVGcvYmk1d1lYSmxi'
    || 'blJPYjJSbExtbHVjMlZ5ZEVKbFptOXlaU2hsTEhRcE9tNHVhVzV6WlhKMFFtVm1iM0psS0dVc2RDazZLRzR1Ym05a1pWUjVjR1U5UFQwNFB5aDBQVzR1Y0dG'
    || 'eVpXNTBUbTlrWlN4MExtbHVjMlZ5ZEVKbFptOXlaU2hsTEc0cEtUb29kRDF1TEhRdVlYQndaVzVrUTJocGJHUW9aU2twTEc0OWJpNWZjbVZoWTNSU2IyOTBR'
    || 'Mjl1ZEdGcGJtVnlMRzRoUFc1MWJHeDhmSFF1YjI1amJHbGpheUU5UFc1MWJHeDhmQ2gwTG05dVkyeHBZMnM5ZEd3cEtUdGxiSE5sSUdsbUtISWhQVDAwSmlZ'
    || 'b1pUMWxMbU5vYVd4a0xHVWhQVDF1ZFd4c0tTbG1iM0lvUTI4b1pTeDBMRzRwTEdVOVpTNXphV0pzYVc1bk8yVWhQVDF1ZFd4c095bERieWhsTEhRc2Jpa3Na'
    || 'VDFsTG5OcFlteHBibWQ5Wm5WdVkzUnBiMjRnVEc4b1pTeDBMRzRwZTNaaGNpQnlQV1V1ZEdGbk8ybG1LSEk5UFQwMWZIeHlQVDA5TmlsbFBXVXVjM1JoZEdW'
    || 'T2IyUmxMSFEvYmk1cGJuTmxjblJDWldadmNtVW9aU3gwS1RwdUxtRndjR1Z1WkVOb2FXeGtLR1VwTzJWc2MyVWdhV1lvY2lFOVBUUW1KaWhsUFdVdVkyaHBi'
    || 'R1FzWlNFOVBXNTFiR3dwS1dadmNpaE1ieWhsTEhRc2Jpa3NaVDFsTG5OcFlteHBibWM3WlNFOVBXNTFiR3c3S1V4dktHVXNkQ3h1S1N4bFBXVXVjMmxpYkds'
    || 'dVozMTJZWElnVkdVOWJuVnNiQ3hvZEQwaE1UdG1kVzVqZEdsdmJpQkhkQ2hsTEhRc2JpbDdabTl5S0c0OWJpNWphR2xzWkR0dUlUMDliblZzYkRzcFJtRW9a'
    || 'U3gwTEc0cExHNDliaTV6YVdKc2FXNW5mV1oxYm1OMGFXOXVJRVpoS0dVc2RDeHVLWHRwWmloM2RDWW1kSGx3Wlc5bUlIZDBMbTl1UTI5dGJXbDBSbWxpWlhK'
    || 'VmJtMXZkVzUwUFQwaVpuVnVZM1JwYjI0aUtYUnllWHQzZEM1dmJrTnZiVzFwZEVacFltVnlWVzV0YjNWdWRDaEJjaXh1S1gxallYUmphSHQ5YzNkcGRHTm9L'
    || 'RzR1ZEdGbktYdGpZWE5sSURVNlQyVjhmRlZ1S0c0c2RDazdZMkZ6WlNBMk9uWmhjaUJ5UFZSbExHdzlhSFE3VkdVOWJuVnNiQ3hIZENobExIUXNiaWtzVkdV'
    || 'OWNpeG9kRDFzTEZSbElUMDliblZzYkNZbUtHaDBQeWhsUFZSbExHNDliaTV6ZEdGMFpVNXZaR1VzWlM1dWIyUmxWSGx3WlQwOVBUZy9aUzV3WVhKbGJuUk9i'
    || 'MlJsTG5KbGJXOTJaVU5vYVd4a0tHNHBPbVV1Y21WdGIzWmxRMmhwYkdRb2Jpa3BPbFJsTG5KbGJXOTJaVU5vYVd4a0tHNHVjM1JoZEdWT2IyUmxLU2s3WW5K'
    || 'bFlXczdZMkZ6WlNBeE9EcFVaU0U5UFc1MWJHd21KaWhvZEQ4b1pUMVVaU3h1UFc0dWMzUmhkR1ZPYjJSbExHVXVibTlrWlZSNWNHVTlQVDA0UHlScEtHVXVj'
    || 'R0Z5Wlc1MFRtOWtaU3h1S1RwbExtNXZaR1ZVZVhCbFBUMDlNU1ltSkdrb1pTeHVLU3h1Y2lobEtTazZKR2tvVkdVc2JpNXpkR0YwWlU1dlpHVXBLVHRpY21W'
    || 'aGF6dGpZWE5sSURRNmNqMVVaU3hzUFdoMExGUmxQVzR1YzNSaGRHVk9iMlJsTG1OdmJuUmhhVzVsY2tsdVptOHNhSFE5SVRBc1IzUW9aU3gwTEc0cExGUmxQ'
    || 'WElzYUhROWJEdGljbVZoYXp0allYTmxJREE2WTJGelpTQXhNVHBqWVhObElERTBPbU5oYzJVZ01UVTZhV1lvSVU5bEppWW9jajF1TG5Wd1pHRjBaVkYxWlhW'
    || 'bExISWhQVDF1ZFd4c0ppWW9jajF5TG14aGMzUkZabVpsWTNRc2NpRTlQVzUxYkd3cEtTbDdiRDF5UFhJdWJtVjRkRHRrYjN0MllYSWdhVDFzTEc4OWFTNWta'
    || 'WE4wY205NU8yazlhUzUwWVdjc2J5RTlQWFp2YVdRZ01DWW1LQ2hwSmpJcElUMDlNSHg4S0drbU5Da2hQVDB3S1NZbWFtOG9iaXgwTEc4cExHdzliQzV1Wlho'
    || 'MGZYZG9hV3hsS0d3aFBUMXlLWDFIZENobExIUXNiaWs3WW5KbFlXczdZMkZ6WlNBeE9tbG1LQ0ZQWlNZbUtGVnVLRzRzZENrc2NqMXVMbk4wWVhSbFRtOWta'
    || 'U3gwZVhCbGIyWWdjaTVqYjIxd2IyNWxiblJYYVd4c1ZXNXRiM1Z1ZEQwOUltWjFibU4wYVc5dUlpa3BkSEo1ZTNJdWNISnZjSE05Ymk1dFpXMXZhWHBsWkZC'
    || 'eWIzQnpMSEl1YzNSaGRHVTliaTV0WlcxdmFYcGxaRk4wWVhSbExISXVZMjl0Y0c5dVpXNTBWMmxzYkZWdWJXOTFiblFvS1gxallYUmphQ2hqS1h0dFpTaHVM'
    || 'SFFzWXlsOVIzUW9aU3gwTEc0cE8ySnlaV0ZyTzJOaGMyVWdNakU2UjNRb1pTeDBMRzRwTzJKeVpXRnJPMk5oYzJVZ01qSTZiaTV0YjJSbEpqRS9LRTlsUFNo'
    || 'eVBVOWxLWHg4Ymk1dFpXMXZhWHBsWkZOMFlYUmxJVDA5Ym5Wc2JDeEhkQ2hsTEhRc2Jpa3NUMlU5Y2lrNlIzUW9aU3gwTEc0cE8ySnlaV0ZyTzJSbFptRjFi'
    || 'SFE2UjNRb1pTeDBMRzRwZlgxbWRXNWpkR2x2YmlCVllTaGxLWHQyWVhJZ2REMWxMblZ3WkdGMFpWRjFaWFZsTzJsbUtIUWhQVDF1ZFd4c0tYdGxMblZ3WkdG'
    || 'MFpWRjFaWFZsUFc1MWJHdzdkbUZ5SUc0OVpTNXpkR0YwWlU1dlpHVTdiajA5UFc1MWJHd21KaWh1UFdVdWMzUmhkR1ZPYjJSbFBXNWxkeUFrWmlrc2RDNW1i'
    || 'M0pGWVdOb0tHWjFibU4wYVc5dUtISXBlM1poY2lCc1BVcG1MbUpwYm1Rb2JuVnNiQ3hsTEhJcE8yNHVhR0Z6S0hJcGZId29iaTVoWkdRb2Npa3NjaTUwYUdW'
    || 'dUtHd3NiQ2twZlNsOWZXWjFibU4wYVc5dUlHMTBLR1VzZENsN2RtRnlJRzQ5ZEM1a1pXeGxkR2x2Ym5NN2FXWW9iaUU5UFc1MWJHd3BabTl5S0haaGNpQnlQ'
    || 'VEE3Y2p4dUxteGxibWQwYUR0eUt5c3BlM1poY2lCc1BXNWJjbDA3ZEhKNWUzWmhjaUJwUFdVc2J6MTBMR005Ynp0bE9tWnZjaWc3WXlFOVBXNTFiR3c3S1h0'
    || 'emQybDBZMmdvWXk1MFlXY3BlMk5oYzJVZ05UcFVaVDFqTG5OMFlYUmxUbTlrWlN4b2REMGhNVHRpY21WaGF5QmxPMk5oYzJVZ016cFVaVDFqTG5OMFlYUmxU'
    || 'bTlrWlM1amIyNTBZV2x1WlhKSmJtWnZMR2gwUFNFd08ySnlaV0ZySUdVN1kyRnpaU0EwT2xSbFBXTXVjM1JoZEdWT2IyUmxMbU52Ym5SaGFXNWxja2x1Wm04'
    || 'c2FIUTlJVEE3WW5KbFlXc2daWDFqUFdNdWNtVjBkWEp1ZldsbUtGUmxQVDA5Ym5Wc2JDbDBhSEp2ZHlCRmNuSnZjaWhoS0RFMk1Da3BPMFpoS0drc2J5eHNL'
    || 'U3hVWlQxdWRXeHNMR2gwUFNFeE8zWmhjaUJrUFd3dVlXeDBaWEp1WVhSbE8yUWhQVDF1ZFd4c0ppWW9aQzV5WlhSMWNtNDliblZzYkNrc2JDNXlaWFIxY200'
    || 'OWJuVnNiSDFqWVhSamFDaG5LWHR0WlNoc0xIUXNaeWw5ZldsbUtIUXVjM1ZpZEhKbFpVWnNZV2R6SmpFeU9EVTBLV1p2Y2loMFBYUXVZMmhwYkdRN2RDRTlQ'
    || 'VzUxYkd3N0tVaGhLSFFzWlNrc2REMTBMbk5wWW14cGJtZDlablZ1WTNScGIyNGdTR0VvWlN4MEtYdDJZWElnYmoxbExtRnNkR1Z5Ym1GMFpTeHlQV1V1Wm14'
    || 'aFozTTdjM2RwZEdOb0tHVXVkR0ZuS1h0allYTmxJREE2WTJGelpTQXhNVHBqWVhObElERTBPbU5oYzJVZ01UVTZhV1lvYlhRb2RDeGxLU3hGZENobEtTeHlK'
    || 'alFwZTNSeWVYdEZjaWd6TEdVc1pTNXlaWFIxY200cExFVnNLRE1zWlNsOVkyRjBZMmdvZWlsN2JXVW9aU3hsTG5KbGRIVnliaXg2S1gxMGNubDdSWElvTlN4'
    || 'bExHVXVjbVYwZFhKdUtYMWpZWFJqYUNoNktYdHRaU2hsTEdVdWNtVjBkWEp1TEhvcGZYMWljbVZoYXp0allYTmxJREU2YlhRb2RDeGxLU3hGZENobEtTeHlK'
    || 'alV4TWlZbWJpRTlQVzUxYkd3bUpsVnVLRzRzYmk1eVpYUjFjbTRwTzJKeVpXRnJPMk5oYzJVZ05UcHBaaWh0ZENoMExHVXBMRVYwS0dVcExISW1OVEV5Smla'
    || 'dUlUMDliblZzYkNZbVZXNG9iaXh1TG5KbGRIVnliaWtzWlM1bWJHRm5jeVl6TWlsN2RtRnlJR3c5WlM1emRHRjBaVTV2WkdVN2RISjVlMUZ1S0d3c0lpSXBm'
    || 'V05oZEdOb0tIb3BlMjFsS0dVc1pTNXlaWFIxY200c2VpbDlmV2xtS0hJbU5DWW1LR3c5WlM1emRHRjBaVTV2WkdVc2JDRTliblZzYkNrcGUzWmhjaUJwUFdV'
    || 'dWJXVnRiMmw2WldSUWNtOXdjeXh2UFc0aFBUMXVkV3hzUDI0dWJXVnRiMmw2WldSUWNtOXdjenBwTEdNOVpTNTBlWEJsTEdROVpTNTFjR1JoZEdWUmRXVjFa'
    || 'VHRwWmlobExuVndaR0YwWlZGMVpYVmxQVzUxYkd3c1pDRTlQVzUxYkd3cGRISjVlMk05UFQwaWFXNXdkWFFpSmlacExuUjVjR1U5UFQwaWNtRmthVzhpSmla'
    || 'cExtNWhiV1VoUFc1MWJHd21KbWh6S0d3c2FTa3NhV2tvWXl4dktUdDJZWElnWnoxcGFTaGpMR2twTzJadmNpaHZQVEE3Ynp4a0xteGxibWQwYUR0dkt6MHlL'
    || 'WHQyWVhJZ1JUMWtXMjlkTEdvOVpGdHZLekZkTzBVOVBUMGljM1I1YkdVaVAxOXpLR3dzYWlrNlJUMDlQU0prWVc1blpYSnZkWE5zZVZObGRFbHVibVZ5U0ZS'
    || 'TlRDSS9kM01vYkN4cUtUcEZQVDA5SW1Ob2FXeGtjbVZ1SWo5UmJpaHNMR29wT2t4bEtHd3NSU3hxTEdjcGZYTjNhWFJqYUNoaktYdGpZWE5sSW1sdWNIVjBJ'
    || 'anBsYVNoc0xHa3BPMkp5WldGck8yTmhjMlVpZEdWNGRHRnlaV0VpT21kektHd3NhU2s3WW5KbFlXczdZMkZ6WlNKelpXeGxZM1FpT25aaGNpQlRQV3d1WDNk'
    || 'eVlYQndaWEpUZEdGMFpTNTNZWE5OZFd4MGFYQnNaVHRzTGw5M2NtRndjR1Z5VTNSaGRHVXVkMkZ6VFhWc2RHbHdiR1U5SVNGcExtMTFiSFJwY0d4bE8zWmhj'
    || 'aUJOUFdrdWRtRnNkV1U3VFNFOWJuVnNiRDk1Ymloc0xDRWhhUzV0ZFd4MGFYQnNaU3hOTENFeEtUcFRJVDA5SVNGcExtMTFiSFJwY0d4bEppWW9hUzVrWlda'
    || 'aGRXeDBWbUZzZFdVaFBXNTFiR3cvZVc0b2JDd2hJV2t1YlhWc2RHbHdiR1VzYVM1a1pXWmhkV3gwVm1Gc2RXVXNJVEFwT25sdUtHd3NJU0ZwTG0xMWJIUnBj'
    || 'R3hsTEdrdWJYVnNkR2x3YkdVL1cxMDZJaUlzSVRFcEtYMXNXM0J5WFQxcGZXTmhkR05vS0hvcGUyMWxLR1VzWlM1eVpYUjFjbTRzZWlsOWZXSnlaV0ZyTzJO'
    || 'aGMyVWdOanBwWmlodGRDaDBMR1VwTEVWMEtHVXBMSEltTkNsN2FXWW9aUzV6ZEdGMFpVNXZaR1U5UFQxdWRXeHNLWFJvY205M0lFVnljbTl5S0dFb01UWXlL'
    || 'U2s3YkQxbExuTjBZWFJsVG05a1pTeHBQV1V1YldWdGIybDZaV1JRY205d2N6dDBjbmw3YkM1dWIyUmxWbUZzZFdVOWFYMWpZWFJqYUNoNktYdHRaU2hsTEdV'
    || 'dWNtVjBkWEp1TEhvcGZYMWljbVZoYXp0allYTmxJRE02YVdZb2JYUW9kQ3hsS1N4RmRDaGxLU3h5SmpRbUptNGhQVDF1ZFd4c0ppWnVMbTFsYlc5cGVtVmtV'
    || 'M1JoZEdVdWFYTkVaV2g1WkhKaGRHVmtLWFJ5ZVh0dWNpaDBMbU52Ym5SaGFXNWxja2x1Wm04cGZXTmhkR05vS0hvcGUyMWxLR1VzWlM1eVpYUjFjbTRzZWls'
    || 'OVluSmxZV3M3WTJGelpTQTBPbTEwS0hRc1pTa3NSWFFvWlNrN1luSmxZV3M3WTJGelpTQXhNenB0ZENoMExHVXBMRVYwS0dVcExHdzlaUzVqYUdsc1pDeHNM'
    || 'bVpzWVdkekpqZ3hPVEltSmlocFBXd3ViV1Z0YjJsNlpXUlRkR0YwWlNFOVBXNTFiR3dzYkM1emRHRjBaVTV2WkdVdWFYTklhV1JrWlc0OWFTd2hhWHg4YkM1'
    || 'aGJIUmxjbTVoZEdVaFBUMXVkV3hzSmlac0xtRnNkR1Z5Ym1GMFpTNXRaVzF2YVhwbFpGTjBZWFJsSVQwOWJuVnNiSHg4S0ZCdlBYWmxLQ2twS1N4eUpqUW1K'
    || 'bFZoS0dVcE8ySnlaV0ZyTzJOaGMyVWdNakk2YVdZb1JUMXVJVDA5Ym5Wc2JDWW1iaTV0WlcxdmFYcGxaRk4wWVhSbElUMDliblZzYkN4bExtMXZaR1VtTVQ4'
    || 'b1QyVTlLR2M5VDJVcGZIeEZMRzEwS0hRc1pTa3NUMlU5WnlrNmJYUW9kQ3hsS1N4RmRDaGxLU3h5SmpneE9USXBlMmxtS0djOVpTNXRaVzF2YVhwbFpGTjBZ'
    || 'WFJsSVQwOWJuVnNiQ3dvWlM1emRHRjBaVTV2WkdVdWFYTklhV1JrWlc0OVp5a21KaUZGSmlZb1pTNXRiMlJsSmpFcElUMDlNQ2xtYjNJb1VEMWxMRVU5WlM1'
    || 'amFHbHNaRHRGSVQwOWJuVnNiRHNwZTJadmNpaHFQVkE5UlR0UUlUMDliblZzYkRzcGUzTjNhWFJqYUNoVFBWQXNUVDFUTG1Ob2FXeGtMRk11ZEdGbktYdGpZ'
    || 'WE5sSURBNlkyRnpaU0F4TVRwallYTmxJREUwT21OaGMyVWdNVFU2UlhJb05DeFRMRk11Y21WMGRYSnVLVHRpY21WaGF6dGpZWE5sSURFNlZXNG9VeXhUTG5K'
    || 'bGRIVnliaWs3ZG1GeUlFazlVeTV6ZEdGMFpVNXZaR1U3YVdZb2RIbHdaVzltSUVrdVkyOXRjRzl1Wlc1MFYybHNiRlZ1Ylc5MWJuUTlQU0ptZFc1amRHbHZi'
    || 'aUlwZTNJOVV5eHVQVk11Y21WMGRYSnVPM1J5ZVh0MFBYSXNTUzV3Y205d2N6MTBMbTFsYlc5cGVtVmtVSEp2Y0hNc1NTNXpkR0YwWlQxMExtMWxiVzlwZW1W'
    || 'a1UzUmhkR1VzU1M1amIyMXdiMjVsYm5SWGFXeHNWVzV0YjNWdWRDZ3BmV05oZEdOb0tIb3BlMjFsS0hJc2JpeDZLWDE5WW5KbFlXczdZMkZ6WlNBMU9sVnVL'
    || 'Rk1zVXk1eVpYUjFjbTRwTzJKeVpXRnJPMk5oYzJVZ01qSTZhV1lvVXk1dFpXMXZhWHBsWkZOMFlYUmxJVDA5Ym5Wc2JDbDdWbUVvYWlrN1kyOXVkR2x1ZFdW'
    || 'OWZVMGhQVDF1ZFd4c1B5aE5MbkpsZEhWeWJqMVRMRkE5VFNrNlZtRW9haWw5UlQxRkxuTnBZbXhwYm1kOVpUcG1iM0lvUlQxdWRXeHNMR285WlRzN0tYdHBa'
    || 'aWhxTG5SaFp6MDlQVFVwZTJsbUtFVTlQVDF1ZFd4c0tYdEZQV283ZEhKNWUydzlhaTV6ZEdGMFpVNXZaR1VzWno4b2FUMXNMbk4wZVd4bExIUjVjR1Z2WmlC'
    || 'cExuTmxkRkJ5YjNCbGNuUjVQVDBpWm5WdVkzUnBiMjRpUDJrdWMyVjBVSEp2Y0dWeWRIa29JbVJwYzNCc1lYa2lMQ0p1YjI1bElpd2lhVzF3YjNKMFlXNTBJ'
    || 'aWs2YVM1a2FYTndiR0Y1UFNKdWIyNWxJaWs2S0dNOWFpNXpkR0YwWlU1dlpHVXNaRDFxTG0xbGJXOXBlbVZrVUhKdmNITXVjM1I1YkdVc2J6MWtJVDF1ZFd4'
    || 'c0ppWmtMbWhoYzA5M2JsQnliM0JsY25SNUtDSmthWE53YkdGNUlpay9aQzVrYVhOd2JHRjVPbTUxYkd3c1l5NXpkSGxzWlM1a2FYTndiR0Y1UFZOektDSmth'
    || 'WE53YkdGNUlpeHZLU2w5WTJGMFkyZ29laWw3YldVb1pTeGxMbkpsZEhWeWJpeDZLWDE5ZldWc2MyVWdhV1lvYWk1MFlXYzlQVDAyS1h0cFppaEZQVDA5Ym5W'
    || 'c2JDbDBjbmw3YWk1emRHRjBaVTV2WkdVdWJtOWtaVlpoYkhWbFBXYy9JaUk2YWk1dFpXMXZhWHBsWkZCeWIzQnpmV05oZEdOb0tIb3BlMjFsS0dVc1pTNXla'
    || 'WFIxY200c2VpbDlmV1ZzYzJVZ2FXWW9LR291ZEdGbklUMDlNakltSm1vdWRHRm5JVDA5TWpOOGZHb3ViV1Z0YjJsNlpXUlRkR0YwWlQwOVBXNTFiR3g4Zkdv'
    || 'OVBUMWxLU1ltYWk1amFHbHNaQ0U5UFc1MWJHd3BlMm91WTJocGJHUXVjbVYwZFhKdVBXb3NhajFxTG1Ob2FXeGtPMk52Ym5ScGJuVmxmV2xtS0dvOVBUMWxL'
    || 'V0p5WldGcklHVTdabTl5S0R0cUxuTnBZbXhwYm1jOVBUMXVkV3hzT3lsN2FXWW9haTV5WlhSMWNtNDlQVDF1ZFd4c2ZIeHFMbkpsZEhWeWJqMDlQV1VwWW5K'
    || 'bFlXc2daVHRGUFQwOWFpWW1LRVU5Ym5Wc2JDa3NhajFxTG5KbGRIVnlibjFGUFQwOWFpWW1LRVU5Ym5Wc2JDa3NhaTV6YVdKc2FXNW5MbkpsZEhWeWJqMXFM'
    || 'bkpsZEhWeWJpeHFQV291YzJsaWJHbHVaMzE5WW5KbFlXczdZMkZ6WlNBeE9UcHRkQ2gwTEdVcExFVjBLR1VwTEhJbU5DWW1WV0VvWlNrN1luSmxZV3M3WTJG'
    || 'elpTQXlNVHBpY21WaGF6dGtaV1poZFd4ME9tMTBLSFFzWlNrc1JYUW9aU2w5ZldaMWJtTjBhVzl1SUVWMEtHVXBlM1poY2lCMFBXVXVabXhoWjNNN2FXWW9k'
    || 'Q1l5S1h0MGNubDdaVHA3Wm05eUtIWmhjaUJ1UFdVdWNtVjBkWEp1TzI0aFBUMXVkV3hzT3lsN2FXWW9SR0VvYmlrcGUzWmhjaUJ5UFc0N1luSmxZV3NnWlgx'
    || 'dVBXNHVjbVYwZFhKdWZYUm9jbTkzSUVWeWNtOXlLR0VvTVRZd0tTbDljM2RwZEdOb0tISXVkR0ZuS1h0allYTmxJRFU2ZG1GeUlHdzljaTV6ZEdGMFpVNXZa'
    || 'R1U3Y2k1bWJHRm5jeVl6TWlZbUtGRnVLR3dzSWlJcExISXVabXhoWjNNbVBTMHpNeWs3ZG1GeUlHazlRV0VvWlNrN1RHOG9aU3hwTEd3cE8ySnlaV0ZyTzJO'
    || 'aGMyVWdNenBqWVhObElEUTZkbUZ5SUc4OWNpNXpkR0YwWlU1dlpHVXVZMjl1ZEdGcGJtVnlTVzVtYnl4alBVRmhLR1VwTzBOdktHVXNZeXh2S1R0aWNtVmhh'
    || 'enRrWldaaGRXeDBPblJvY205M0lFVnljbTl5S0dFb01UWXhLU2w5ZldOaGRHTm9LR1FwZTIxbEtHVXNaUzV5WlhSMWNtNHNaQ2w5WlM1bWJHRm5jeVk5TFRO'
    || 'OWRDWTBNRGsySmlZb1pTNW1iR0ZuY3lZOUxUUXdPVGNwZldaMWJtTjBhVzl1SUZabUtHVXNkQ3h1S1h0UVBXVXNKR0VvWlNsOVpuVnVZM1JwYjI0Z0pHRW9a'
    || 'U3gwTEc0cGUyWnZjaWgyWVhJZ2NqMG9aUzV0YjJSbEpqRXBJVDA5TUR0UUlUMDliblZzYkRzcGUzWmhjaUJzUFZBc2FUMXNMbU5vYVd4a08ybG1LR3d1ZEdG'
    || 'blBUMDlNakltSm5JcGUzWmhjaUJ2UFd3dWJXVnRiMmw2WldSVGRHRjBaU0U5UFc1MWJHeDhmR3RzTzJsbUtDRnZLWHQyWVhJZ1l6MXNMbUZzZEdWeWJtRjBa'
    || 'U3hrUFdNaFBUMXVkV3hzSmlaakxtMWxiVzlwZW1Wa1UzUmhkR1VoUFQxdWRXeHNmSHhQWlR0alBXdHNPM1poY2lCblBVOWxPMmxtS0d0c1BXOHNLRTlsUFdR'
    || 'cEppWWhaeWxtYjNJb1VEMXNPMUFoUFQxdWRXeHNPeWx2UFZBc1pEMXZMbU5vYVd4a0xHOHVkR0ZuUFQwOU1qSW1KbTh1YldWdGIybDZaV1JUZEdGMFpTRTlQ'
    || 'VzUxYkd3L1FtRW9iQ2s2WkNFOVBXNTFiR3cvS0dRdWNtVjBkWEp1UFc4c1VEMWtLVHBDWVNoc0tUdG1iM0lvTzJraFBUMXVkV3hzT3lsUVBXa3NKR0VvYVNr'
    || 'c2FUMXBMbk5wWW14cGJtYzdVRDFzTEd0c1BXTXNUMlU5WjMxWFlTaGxLWDFsYkhObEtHd3VjM1ZpZEhKbFpVWnNZV2R6SmpnM056SXBJVDA5TUNZbWFTRTlQ'
    || 'VzUxYkd3L0tHa3VjbVYwZFhKdVBXd3NVRDFwS1RwWFlTaGxLWDE5Wm5WdVkzUnBiMjRnVjJFb1pTbDdabTl5S0R0UUlUMDliblZzYkRzcGUzWmhjaUIwUFZB'
    || 'N2FXWW9LSFF1Wm14aFozTW1PRGMzTWlraFBUMHdLWHQyWVhJZ2JqMTBMbUZzZEdWeWJtRjBaVHQwY25sN2FXWW9LSFF1Wm14aFozTW1PRGMzTWlraFBUMHdL'
    || 'WE4zYVhSamFDaDBMblJoWnlsN1kyRnpaU0F3T21OaGMyVWdNVEU2WTJGelpTQXhOVHBQWlh4OFJXd29OU3gwS1R0aWNtVmhhenRqWVhObElERTZkbUZ5SUhJ'
    || 'OWRDNXpkR0YwWlU1dlpHVTdhV1lvZEM1bWJHRm5jeVkwSmlZaFQyVXBhV1lvYmowOVBXNTFiR3dwY2k1amIyMXdiMjVsYm5SRWFXUk5iM1Z1ZENncE8yVnNj'
    || 'MlY3ZG1GeUlHdzlkQzVsYkdWdFpXNTBWSGx3WlQwOVBYUXVkSGx3WlQ5dUxtMWxiVzlwZW1Wa1VISnZjSE02Y0hRb2RDNTBlWEJsTEc0dWJXVnRiMmw2WldS'
    || 'UWNtOXdjeWs3Y2k1amIyMXdiMjVsYm5SRWFXUlZjR1JoZEdVb2JDeHVMbTFsYlc5cGVtVmtVM1JoZEdVc2NpNWZYM0psWVdOMFNXNTBaWEp1WVd4VGJtRndj'
    || 'Mmh2ZEVKbFptOXlaVlZ3WkdGMFpTbDlkbUZ5SUdrOWRDNTFjR1JoZEdWUmRXVjFaVHRwSVQwOWJuVnNiQ1ltVm5Vb2RDeHBMSElwTzJKeVpXRnJPMk5oYzJV'
    || 'Z016cDJZWElnYnoxMExuVndaR0YwWlZGMVpYVmxPMmxtS0c4aFBUMXVkV3hzS1h0cFppaHVQVzUxYkd3c2RDNWphR2xzWkNFOVBXNTFiR3dwYzNkcGRHTm9L'
    || 'SFF1WTJocGJHUXVkR0ZuS1h0allYTmxJRFU2YmoxMExtTm9hV3hrTG5OMFlYUmxUbTlrWlR0aWNtVmhhenRqWVhObElERTZiajEwTG1Ob2FXeGtMbk4wWVhS'
    || 'bFRtOWtaWDFXZFNoMExHOHNiaWw5WW5KbFlXczdZMkZ6WlNBMU9uWmhjaUJqUFhRdWMzUmhkR1ZPYjJSbE8ybG1LRzQ5UFQxdWRXeHNKaVowTG1ac1lXZHpK'
    || 'alFwZTI0OVl6dDJZWElnWkQxMExtMWxiVzlwZW1Wa1VISnZjSE03YzNkcGRHTm9LSFF1ZEhsd1pTbDdZMkZ6WlNKaWRYUjBiMjRpT21OaGMyVWlhVzV3ZFhR'
    || 'aU9tTmhjMlVpYzJWc1pXTjBJanBqWVhObEluUmxlSFJoY21WaElqcGtMbUYxZEc5R2IyTjFjeVltYmk1bWIyTjFjeWdwTzJKeVpXRnJPMk5oYzJVaWFXMW5J'
    || 'anBrTG5OeVl5WW1LRzR1YzNKalBXUXVjM0pqS1gxOVluSmxZV3M3WTJGelpTQTJPbUp5WldGck8yTmhjMlVnTkRwaWNtVmhhenRqWVhObElERXlPbUp5WldG'
    || 'ck8yTmhjMlVnTVRNNmFXWW9kQzV0WlcxdmFYcGxaRk4wWVhSbFBUMDliblZzYkNsN2RtRnlJR2M5ZEM1aGJIUmxjbTVoZEdVN2FXWW9aeUU5UFc1MWJHd3Bl'
    || 'M1poY2lCRlBXY3ViV1Z0YjJsNlpXUlRkR0YwWlR0cFppaEZJVDA5Ym5Wc2JDbDdkbUZ5SUdvOVJTNWtaV2g1WkhKaGRHVmtPMm9oUFQxdWRXeHNKaVp1Y2lo'
    || 'cUtYMTlmV0p5WldGck8yTmhjMlVnTVRrNlkyRnpaU0F4TnpwallYTmxJREl4T21OaGMyVWdNakk2WTJGelpTQXlNenBqWVhObElESTFPbUp5WldGck8yUmxa'
    || 'bUYxYkhRNmRHaHliM2NnUlhKeWIzSW9ZU2d4TmpNcEtYMVBaWHg4ZEM1bWJHRm5jeVkxTVRJbUpsUnZLSFFwZldOaGRHTm9LRk1wZTIxbEtIUXNkQzV5WlhS'
    || 'MWNtNHNVeWw5ZldsbUtIUTlQVDFsS1h0UVBXNTFiR3c3WW5KbFlXdDlhV1lvYmoxMExuTnBZbXhwYm1jc2JpRTlQVzUxYkd3cGUyNHVjbVYwZFhKdVBYUXVj'
    || 'bVYwZFhKdUxGQTlianRpY21WaGEzMVFQWFF1Y21WMGRYSnVmWDFtZFc1amRHbHZiaUJXWVNobEtYdG1iM0lvTzFBaFBUMXVkV3hzT3lsN2RtRnlJSFE5VUR0'
    || 'cFppaDBQVDA5WlNsN1VEMXVkV3hzTzJKeVpXRnJmWFpoY2lCdVBYUXVjMmxpYkdsdVp6dHBaaWh1SVQwOWJuVnNiQ2w3Ymk1eVpYUjFjbTQ5ZEM1eVpYUjFj'
    || 'bTRzVUQxdU8ySnlaV0ZyZlZBOWRDNXlaWFIxY201OWZXWjFibU4wYVc5dUlFSmhLR1VwZTJadmNpZzdVQ0U5UFc1MWJHdzdLWHQyWVhJZ2REMVFPM1J5ZVh0'
    || 'emQybDBZMmdvZEM1MFlXY3BlMk5oYzJVZ01EcGpZWE5sSURFeE9tTmhjMlVnTVRVNmRtRnlJRzQ5ZEM1eVpYUjFjbTQ3ZEhKNWUwVnNLRFFzZENsOVkyRjBZ'
    || 'MmdvWkNsN2JXVW9kQ3h1TEdRcGZXSnlaV0ZyTzJOaGMyVWdNVHAyWVhJZ2NqMTBMbk4wWVhSbFRtOWtaVHRwWmloMGVYQmxiMllnY2k1amIyMXdiMjVsYm5S'
    || 'RWFXUk5iM1Z1ZEQwOUltWjFibU4wYVc5dUlpbDdkbUZ5SUd3OWRDNXlaWFIxY200N2RISjVlM0l1WTI5dGNHOXVaVzUwUkdsa1RXOTFiblFvS1gxallYUmph'
    || 'Q2hrS1h0dFpTaDBMR3dzWkNsOWZYWmhjaUJwUFhRdWNtVjBkWEp1TzNSeWVYdFVieWgwS1gxallYUmphQ2hrS1h0dFpTaDBMR2tzWkNsOVluSmxZV3M3WTJG'
    || 'elpTQTFPblpoY2lCdlBYUXVjbVYwZFhKdU8zUnllWHRVYnloMEtYMWpZWFJqYUNoa0tYdHRaU2gwTEc4c1pDbDlmWDFqWVhSamFDaGtLWHR0WlNoMExIUXVj'
    || 'bVYwZFhKdUxHUXBmV2xtS0hROVBUMWxLWHRRUFc1MWJHdzdZbkpsWVd0OWRtRnlJR005ZEM1emFXSnNhVzVuTzJsbUtHTWhQVDF1ZFd4c0tYdGpMbkpsZEhW'
    || 'eWJqMTBMbkpsZEhWeWJpeFFQV003WW5KbFlXdDlVRDEwTG5KbGRIVnlibjE5ZG1GeUlFSm1QVTFoZEdndVkyVnBiQ3hPYkQxdlpTNVNaV0ZqZEVOMWNuSmxi'
    || 'blJFYVhOd1lYUmphR1Z5TEZKdlBXOWxMbEpsWVdOMFEzVnljbVZ1ZEU5M2JtVnlMRzkwUFc5bExsSmxZV04wUTNWeWNtVnVkRUpoZEdOb1EyOXVabWxuTEZv'
    || 'OU1DeHJaVDF1ZFd4c0xIbGxQVzUxYkd3c1EyVTlNQ3h4WlQwd0xFaHVQVlowS0RBcExIZGxQVEFzVG5JOWJuVnNiQ3hrYmowd0xHcHNQVEFzVFc4OU1DeHFj'
    || 'ajF1ZFd4c0xFSmxQVzUxYkd3c1VHODlNQ3drYmoweEx6QXNTWFE5Ym5Wc2JDeFViRDBoTVN4UGJ6MXVkV3hzTEZoMFBXNTFiR3dzUTJ3OUlURXNXblE5Ym5W'
    || 'c2JDeE1iRDB3TEZSeVBUQXNTVzg5Ym5Wc2JDeFNiRDB0TVN4TmJEMHdPMloxYm1OMGFXOXVJRVJsS0NsN2NtVjBkWEp1S0ZvbU5pa2hQVDB3UDNabEtDazZV'
    || 'bXdoUFQwdE1UOVNiRHBTYkQxMlpTZ3BmV1oxYm1OMGFXOXVJRXAwS0dVcGUzSmxkSFZ5YmlobExtMXZaR1VtTVNrOVBUMHdQekU2S0ZvbU1pa2hQVDB3Smla'
    || 'RFpTRTlQVEEvUTJVbUxVTmxPbFJtTG5SeVlXNXphWFJwYjI0aFBUMXVkV3hzUHloTmJEMDlQVEFtSmloTmJEMUJjeWdwS1N4TmJDazZLR1U5Ym1Vc1pTRTlQ'
    || 'VEI4ZkNobFBYZHBibVJ2ZHk1bGRtVnVkQ3hsUFdVOVBUMTJiMmxrSURBL01UWTZXWE1vWlM1MGVYQmxLU2tzWlNsOVpuVnVZM1JwYjI0Z2RuUW9aU3gwTEc0'
    || 'c2NpbDdhV1lvTlRBOFZISXBkR2h5YjNjZ1ZISTlNQ3hKYnoxdWRXeHNMRVZ5Y205eUtHRW9NVGcxS1NrN1NtNG9aU3h1TEhJcExDZ29XaVl5S1QwOVBUQjhm'
    || 'R1VoUFQxclpTa21KaWhsUFQwOWEyVW1KaWdvV2lZeUtUMDlQVEFtSmlocWJIdzliaWtzZDJVOVBUMDBKaVp4ZENobExFTmxLU2tzVVdVb1pTeHlLU3h1UFQw'
    || 'OU1TWW1XajA5UFRBbUppaDBMbTF2WkdVbU1TazlQVDB3SmlZb0pHNDlkbVVvS1NzMU1EQXNhV3dtSmxGMEtDa3BLWDFtZFc1amRHbHZiaUJSWlNobExIUXBl'
    || 'M1poY2lCdVBXVXVZMkZzYkdKaFkydE9iMlJsTzJwa0tHVXNkQ2s3ZG1GeUlISTlTSElvWlN4bFBUMDlhMlUvUTJVNk1DazdhV1lvY2owOVBUQXBiaUU5UFc1'
    || 'MWJHd21Ka2x6S0c0cExHVXVZMkZzYkdKaFkydE9iMlJsUFc1MWJHd3NaUzVqWVd4c1ltRmphMUJ5YVc5eWFYUjVQVEE3Wld4elpTQnBaaWgwUFhJbUxYSXNa'
    || 'UzVqWVd4c1ltRmphMUJ5YVc5eWFYUjVJVDA5ZENsN2FXWW9iaUU5Ym5Wc2JDWW1TWE1vYmlrc2REMDlQVEVwWlM1MFlXYzlQVDB3UDJwbUtGbGhMbUpwYm1R'
    || 'b2JuVnNiQ3hsS1NrNlRYVW9XV0V1WW1sdVpDaHVkV3hzTEdVcEtTeGZaaWhtZFc1amRHbHZiaWdwZXloYUpqWXBQVDA5TUNZbVVYUW9LWDBwTEc0OWJuVnNi'
    || 'RHRsYkhObGUzTjNhWFJqYUNoR2N5aHlLU2w3WTJGelpTQXhPbTQ5Wm1rN1luSmxZV3M3WTJGelpTQTBPbTQ5ZW5NN1luSmxZV3M3WTJGelpTQXhOanB1UFVS'
    || 'eU8ySnlaV0ZyTzJOaGMyVWdOVE0yT0Rjd09URXlPbTQ5UkhNN1luSmxZV3M3WkdWbVlYVnNkRHB1UFVSeWZXNDlaV01vYml4UllTNWlhVzVrS0c1MWJHd3Na'
    || 'U2twZldVdVkyRnNiR0poWTJ0UWNtbHZjbWwwZVQxMExHVXVZMkZzYkdKaFkydE9iMlJsUFc1OWZXWjFibU4wYVc5dUlGRmhLR1VzZENsN2FXWW9VbXc5TFRF'
    || 'c1RXdzlNQ3dvV2lZMktTRTlQVEFwZEdoeWIzY2dSWEp5YjNJb1lTZ3pNamNwS1R0MllYSWdiajFsTG1OaGJHeGlZV05yVG05a1pUdHBaaWhYYmlncEppWmxM'
    || 'bU5oYkd4aVlXTnJUbTlrWlNFOVBXNHBjbVYwZFhKdUlHNTFiR3c3ZG1GeUlISTlTSElvWlN4bFBUMDlhMlUvUTJVNk1DazdhV1lvY2owOVBUQXBjbVYwZFhK'
    || 'dUlHNTFiR3c3YVdZb0tISW1NekFwSVQwOU1IeDhLSEltWlM1bGVIQnBjbVZrVEdGdVpYTXBJVDA5TUh4OGRDbDBQVkJzS0dVc2NpazdaV3h6Wlh0MFBYSTdk'
    || 'bUZ5SUd3OVdqdGFmRDB5TzNaaGNpQnBQVWRoS0NrN0tHdGxJVDA5Wlh4OFEyVWhQVDEwS1NZbUtFbDBQVzUxYkd3c0pHNDlkbVVvS1NzMU1EQXNjRzRvWlN4'
    || 'MEtTazdaRzhnZEhKNWUwdG1LQ2s3WW5KbFlXdDlZMkYwWTJnb1l5bDdTMkVvWlN4aktYMTNhR2xzWlNnaE1DazdTbWtvS1N4T2JDNWpkWEp5Wlc1MFBXa3NX'
    || 'ajFzTEhsbElUMDliblZzYkQ5MFBUQTZLR3RsUFc1MWJHd3NRMlU5TUN4MFBYZGxLWDFwWmloMElUMDlNQ2w3YVdZb2REMDlQVEltSmloc1BYQnBLR1VwTEd3'
    || 'aFBUMHdKaVlvY2oxc0xIUTllbThvWlN4c0tTa3BMSFE5UFQweEtYUm9jbTkzSUc0OVRuSXNjRzRvWlN3d0tTeHhkQ2hsTEhJcExGRmxLR1VzZG1Vb0tTa3Ni'
    || 'anRwWmloMFBUMDlOaWx4ZENobExISXBPMlZzYzJWN2FXWW9iRDFsTG1OMWNuSmxiblF1WVd4MFpYSnVZWFJsTENoeUpqTXdLVDA5UFRBbUppRlJaaWhzS1NZ'
    || 'bUtIUTlVR3dvWlN4eUtTeDBQVDA5TWlZbUtHazljR2tvWlNrc2FTRTlQVEFtSmloeVBXa3NkRDE2YnlobExHa3BLU2tzZEQwOVBURXBLWFJvY205M0lHNDlU'
    || 'bklzY0c0b1pTd3dLU3h4ZENobExISXBMRkZsS0dVc2RtVW9LU2tzYmp0emQybDBZMmdvWlM1bWFXNXBjMmhsWkZkdmNtczliQ3hsTG1acGJtbHphR1ZrVEdG'
    || 'dVpYTTljaXgwS1h0allYTmxJREE2WTJGelpTQXhPblJvY205M0lFVnljbTl5S0dFb016UTFLU2s3WTJGelpTQXlPbWh1S0dVc1FtVXNTWFFwTzJKeVpXRnJP'
    || 'Mk5oYzJVZ016cHBaaWh4ZENobExISXBMQ2h5SmpFek1EQXlNelF5TkNrOVBUMXlKaVlvZEQxUWJ5czFNREF0ZG1Vb0tTd3hNRHgwS1NsN2FXWW9TSElvWlN3'
    || 'd0tTRTlQVEFwWW5KbFlXczdhV1lvYkQxbExuTjFjM0JsYm1SbFpFeGhibVZ6TENoc0puSXBJVDA5Y2lsN1JHVW9LU3hsTG5CcGJtZGxaRXhoYm1WemZEMWxM'
    || 'bk4xYzNCbGJtUmxaRXhoYm1WekptdzdZbkpsWVd0OVpTNTBhVzFsYjNWMFNHRnVaR3hsUFVocEtHaHVMbUpwYm1Rb2JuVnNiQ3hsTEVKbExFbDBLU3gwS1R0'
    || 'aWNtVmhhMzFvYmlobExFSmxMRWwwS1R0aWNtVmhhenRqWVhObElEUTZhV1lvY1hRb1pTeHlLU3dvY2lZME1UazBNalF3S1QwOVBYSXBZbkpsWVdzN1ptOXlL'
    || 'SFE5WlM1bGRtVnVkRlJwYldWekxHdzlMVEU3TUR4eU95bDdkbUZ5SUc4OU16RXRZM1FvY2lrN2FUMHhQRHh2TEc4OWRGdHZYU3h2UG13bUppaHNQVzhwTEhJ'
    || 'bVBYNXBmV2xtS0hJOWJDeHlQWFpsS0NrdGNpeHlQU2d4TWpBK2NqOHhNakE2TkRnd1BuSS9ORGd3T2pFd09EQStjajh4TURnd09qRTVNakErY2o4eE9USXdP'
    || 'ak5sTXo1eVB6TmxNem8wTXpJd1BuSS9ORE15TURveE9UWXdLa0ptS0hJdk1UazJNQ2twTFhJc01UQThjaWw3WlM1MGFXMWxiM1YwU0dGdVpHeGxQVWhwS0do'
    || 'dUxtSnBibVFvYm5Wc2JDeGxMRUpsTEVsMEtTeHlLVHRpY21WaGEzMW9iaWhsTEVKbExFbDBLVHRpY21WaGF6dGpZWE5sSURVNmFHNG9aU3hDWlN4SmRDazdZ'
    || 'bkpsWVdzN1pHVm1ZWFZzZERwMGFISnZkeUJGY25KdmNpaGhLRE15T1NrcGZYMTljbVYwZFhKdUlGRmxLR1VzZG1Vb0tTa3NaUzVqWVd4c1ltRmphMDV2WkdV'
    || 'OVBUMXVQMUZoTG1KcGJtUW9iblZzYkN4bEtUcHVkV3hzZldaMWJtTjBhVzl1SUhwdktHVXNkQ2w3ZG1GeUlHNDlhbkk3Y21WMGRYSnVJR1V1WTNWeWNtVnVk'
    || 'QzV0WlcxdmFYcGxaRk4wWVhSbExtbHpSR1ZvZVdSeVlYUmxaQ1ltS0hCdUtHVXNkQ2t1Wm14aFozTjhQVEkxTmlrc1pUMVFiQ2hsTEhRcExHVWhQVDB5SmlZ'
    || 'b2REMUNaU3hDWlQxdUxIUWhQVDF1ZFd4c0ppWkVieWgwS1Nrc1pYMW1kVzVqZEdsdmJpQkVieWhsS1h0Q1pUMDlQVzUxYkd3L1FtVTlaVHBDWlM1d2RYTm9M'
    || 'bUZ3Y0d4NUtFSmxMR1VwZldaMWJtTjBhVzl1SUZGbUtHVXBlMlp2Y2loMllYSWdkRDFsT3pzcGUybG1LSFF1Wm14aFozTW1NVFl6T0RRcGUzWmhjaUJ1UFhR'
    || 'dWRYQmtZWFJsVVhWbGRXVTdhV1lvYmlFOVBXNTFiR3dtSmlodVBXNHVjM1J2Y21WekxHNGhQVDF1ZFd4c0tTbG1iM0lvZG1GeUlISTlNRHR5UEc0dWJHVnVa'
    || 'M1JvTzNJckt5bDdkbUZ5SUd3OWJsdHlYU3hwUFd3dVoyVjBVMjVoY0hOb2IzUTdiRDFzTG5aaGJIVmxPM1J5ZVh0cFppZ2haSFFvYVNncExHd3BLWEpsZEhW'
    || 'eWJpRXhmV05oZEdOb2UzSmxkSFZ5YmlFeGZYMTlhV1lvYmoxMExtTm9hV3hrTEhRdWMzVmlkSEpsWlVac1lXZHpKakUyTXpnMEppWnVJVDA5Ym5Wc2JDbHVM'
    || 'bkpsZEhWeWJqMTBMSFE5Ymp0bGJITmxlMmxtS0hROVBUMWxLV0p5WldGck8yWnZjaWc3ZEM1emFXSnNhVzVuUFQwOWJuVnNiRHNwZTJsbUtIUXVjbVYwZFhK'
    || 'dVBUMDliblZzYkh4OGRDNXlaWFIxY200OVBUMWxLWEpsZEhWeWJpRXdPM1E5ZEM1eVpYUjFjbTU5ZEM1emFXSnNhVzVuTG5KbGRIVnliajEwTG5KbGRIVnli'
    || 'aXgwUFhRdWMybGliR2x1WjMxOWNtVjBkWEp1SVRCOVpuVnVZM1JwYjI0Z2NYUW9aU3gwS1h0bWIzSW9kQ1k5ZmsxdkxIUW1QWDVxYkN4bExuTjFjM0JsYm1S'
    || 'bFpFeGhibVZ6ZkQxMExHVXVjR2x1WjJWa1RHRnVaWE1tUFg1MExHVTlaUzVsZUhCcGNtRjBhVzl1VkdsdFpYTTdNRHgwT3lsN2RtRnlJRzQ5TXpFdFkzUW9k'
    || 'Q2tzY2oweFBEeHVPMlZiYmwwOUxURXNkQ1k5Zm5KOWZXWjFibU4wYVc5dUlGbGhLR1VwZTJsbUtDaGFKallwSVQwOU1DbDBhSEp2ZHlCRmNuSnZjaWhoS0RN'
    || 'eU55a3BPMWR1S0NrN2RtRnlJSFE5U0hJb1pTd3dLVHRwWmlnb2RDWXhLVDA5UFRBcGNtVjBkWEp1SUZGbEtHVXNkbVVvS1Nrc2JuVnNiRHQyWVhJZ2JqMVFi'
    || 'Q2hsTEhRcE8ybG1LR1V1ZEdGbklUMDlNQ1ltYmowOVBUSXBlM1poY2lCeVBYQnBLR1VwTzNJaFBUMHdKaVlvZEQxeUxHNDllbThvWlN4eUtTbDlhV1lvYmow'
    || 'OVBURXBkR2h5YjNjZ2JqMU9jaXh3YmlobExEQXBMSEYwS0dVc2RDa3NVV1VvWlN4MlpTZ3BLU3h1TzJsbUtHNDlQVDAyS1hSb2NtOTNJRVZ5Y205eUtHRW9N'
    || 'elExS1NrN2NtVjBkWEp1SUdVdVptbHVhWE5vWldSWGIzSnJQV1V1WTNWeWNtVnVkQzVoYkhSbGNtNWhkR1VzWlM1bWFXNXBjMmhsWkV4aGJtVnpQWFFzYUc0'
    || 'b1pTeENaU3hKZENrc1VXVW9aU3gyWlNncEtTeHVkV3hzZldaMWJtTjBhVzl1SUVGdktHVXNkQ2w3ZG1GeUlHNDlXanRhZkQweE8zUnllWHR5WlhSMWNtNGda'
    || 'U2gwS1gxbWFXNWhiR3g1ZTFvOWJpeGFQVDA5TUNZbUtDUnVQWFpsS0Nrck5UQXdMR2xzSmlaUmRDZ3BLWDE5Wm5WdVkzUnBiMjRnWm00b1pTbDdXblFoUFQx'
    || 'dWRXeHNKaVphZEM1MFlXYzlQVDB3SmlZb1dpWTJLVDA5UFRBbUpsZHVLQ2s3ZG1GeUlIUTlXanRhZkQweE8zWmhjaUJ1UFc5MExuUnlZVzV6YVhScGIyNHNj'
    || 'ajF1WlR0MGNubDdhV1lvYjNRdWRISmhibk5wZEdsdmJqMXVkV3hzTEc1bFBURXNaU2x5WlhSMWNtNGdaU2dwZldacGJtRnNiSGw3Ym1VOWNpeHZkQzUwY21G'
    || 'dWMybDBhVzl1UFc0c1dqMTBMQ2hhSmpZcFBUMDlNQ1ltVVhRb0tYMTlablZ1WTNScGIyNGdSbThvS1h0eFpUMUliaTVqZFhKeVpXNTBMSFZsS0VodUtYMW1k'
    || 'VzVqZEdsdmJpQndiaWhsTEhRcGUyVXVabWx1YVhOb1pXUlhiM0pyUFc1MWJHd3NaUzVtYVc1cGMyaGxaRXhoYm1WelBUQTdkbUZ5SUc0OVpTNTBhVzFsYjNW'
    || 'MFNHRnVaR3hsTzJsbUtHNGhQVDB0TVNZbUtHVXVkR2x0Wlc5MWRFaGhibVJzWlQwdE1TeFRaaWh1S1Nrc2VXVWhQVDF1ZFd4c0tXWnZjaWh1UFhsbExuSmxk'
    || 'SFZ5Ymp0dUlUMDliblZzYkRzcGUzWmhjaUJ5UFc0N2MzZHBkR05vS0ZscEtISXBMSEl1ZEdGbktYdGpZWE5sSURFNmNqMXlMblI1Y0dVdVkyaHBiR1JEYjI1'
    || 'MFpYaDBWSGx3WlhNc2NpRTliblZzYkNZbWNtd29LVHRpY21WaGF6dGpZWE5sSURNNlFXNG9LU3gxWlNna1pTa3NkV1VvVW1VcExHbHZLQ2s3WW5KbFlXczdZ'
    || 'MkZ6WlNBMU9uSnZLSElwTzJKeVpXRnJPMk5oYzJVZ05EcEJiaWdwTzJKeVpXRnJPMk5oYzJVZ01UTTZkV1VvWkdVcE8ySnlaV0ZyTzJOaGMyVWdNVGs2ZFdV'
    || 'b1pHVXBPMkp5WldGck8yTmhjMlVnTVRBNmNXa29jaTUwZVhCbExsOWpiMjUwWlhoMEtUdGljbVZoYXp0allYTmxJREl5T21OaGMyVWdNak02Um04b0tYMXVQ'
    || 'VzR1Y21WMGRYSnVmV2xtS0d0bFBXVXNlV1U5WlQxaWRDaGxMbU4xY25KbGJuUXNiblZzYkNrc1EyVTljV1U5ZEN4M1pUMHdMRTV5UFc1MWJHd3NUVzg5YW13'
    || 'OVpHNDlNQ3hDWlQxcWNqMXVkV3hzTEhWdUlUMDliblZzYkNsN1ptOXlLSFE5TUR0MFBIVnVMbXhsYm1kMGFEdDBLeXNwYVdZb2JqMTFibHQwWFN4eVBXNHVh'
    || 'VzUwWlhKc1pXRjJaV1FzY2lFOVBXNTFiR3dwZTI0dWFXNTBaWEpzWldGMlpXUTliblZzYkR0MllYSWdiRDF5TG01bGVIUXNhVDF1TG5CbGJtUnBibWM3YVdZ'
    || 'b2FTRTlQVzUxYkd3cGUzWmhjaUJ2UFdrdWJtVjRkRHRwTG01bGVIUTliQ3h5TG01bGVIUTliMzF1TG5CbGJtUnBibWM5Y24xMWJqMXVkV3hzZlhKbGRIVnli'
    || 'aUJsZldaMWJtTjBhVzl1SUV0aEtHVXNkQ2w3Wkc5N2RtRnlJRzQ5ZVdVN2RISjVlMmxtS0VwcEtDa3NiV3d1WTNWeWNtVnVkRDE0YkN4MmJDbDdabTl5S0ha'
    || 'aGNpQnlQV1psTG0xbGJXOXBlbVZrVTNSaGRHVTdjaUU5UFc1MWJHdzdLWHQyWVhJZ2JEMXlMbkYxWlhWbE8yd2hQVDF1ZFd4c0ppWW9iQzV3Wlc1a2FXNW5Q'
    || 'VzUxYkd3cExISTljaTV1WlhoMGZYWnNQU0V4ZldsbUtHTnVQVEFzWDJVOWVHVTlabVU5Ym5Wc2JDeDRjajBoTVN4M2NqMHdMRkp2TG1OMWNuSmxiblE5Ym5W'
    || 'c2JDeHVQVDA5Ym5Wc2JIeDhiaTV5WlhSMWNtNDlQVDF1ZFd4c0tYdDNaVDB4TEU1eVBYUXNlV1U5Ym5Wc2JEdGljbVZoYTMxbE9udDJZWElnYVQxbExHODli'
    || 'aTV5WlhSMWNtNHNZejF1TEdROWREdHBaaWgwUFVObExHTXVabXhoWjNOOFBUTXlOelk0TEdRaFBUMXVkV3hzSmlaMGVYQmxiMllnWkQwOUltOWlhbVZqZENJ'
    || 'bUpuUjVjR1Z2WmlCa0xuUm9aVzQ5UFNKbWRXNWpkR2x2YmlJcGUzWmhjaUJuUFdRc1JUMWpMR285UlM1MFlXYzdhV1lvS0VVdWJXOWtaU1l4S1QwOVBUQW1K'
    || 'aWhxUFQwOU1IeDhhajA5UFRFeGZIeHFQVDA5TVRVcEtYdDJZWElnVXoxRkxtRnNkR1Z5Ym1GMFpUdFRQeWhGTG5Wd1pHRjBaVkYxWlhWbFBWTXVkWEJrWVhS'
    || 'bFVYVmxkV1VzUlM1dFpXMXZhWHBsWkZOMFlYUmxQVk11YldWdGIybDZaV1JUZEdGMFpTeEZMbXhoYm1WelBWTXViR0Z1WlhNcE9paEZMblZ3WkdGMFpWRjFa'
    || 'WFZsUFc1MWJHd3NSUzV0WlcxdmFYcGxaRk4wWVhSbFBXNTFiR3dwZlhaaGNpQk5QWGxoS0c4cE8ybG1LRTBoUFQxdWRXeHNLWHROTG1ac1lXZHpKajB0TWpV'
    || 'M0xIaGhLRTBzYnl4akxHa3NkQ2tzVFM1dGIyUmxKakVtSm1kaEtHa3NaeXgwS1N4MFBVMHNaRDFuTzNaaGNpQkpQWFF1ZFhCa1lYUmxVWFZsZFdVN2FXWW9T'
    || 'VDA5UFc1MWJHd3BlM1poY2lCNlBXNWxkeUJUWlhRN2VpNWhaR1FvWkNrc2RDNTFjR1JoZEdWUmRXVjFaVDE2ZldWc2MyVWdTUzVoWkdRb1pDazdZbkpsWVdz'
    || 'Z1pYMWxiSE5sZTJsbUtDaDBKakVwUFQwOU1DbDdaMkVvYVN4bkxIUXBMRlZ2S0NrN1luSmxZV3NnWlgxa1BVVnljbTl5S0dFb05ESTJLU2w5ZldWc2MyVWdh'
    || 'V1lvWTJVbUptTXViVzlrWlNZeEtYdDJZWElnWjJVOWVXRW9ieWs3YVdZb1oyVWhQVDF1ZFd4c0tYc29aMlV1Wm14aFozTW1OalUxTXpZcFBUMDlNQ1ltS0dk'
    || 'bExtWnNZV2R6ZkQweU5UWXBMSGhoS0dkbExHOHNZeXhwTEhRcExGaHBLRVp1S0dRc1l5a3BPMkp5WldGcklHVjlmV2s5WkQxR2JpaGtMR01wTEhkbElUMDlO'
    || 'Q1ltS0hkbFBUSXBMR3B5UFQwOWJuVnNiRDlxY2oxYmFWMDZhbkl1Y0hWemFDaHBLU3hwUFc4N1pHOTdjM2RwZEdOb0tHa3VkR0ZuS1h0allYTmxJRE02YVM1'
    || 'bWJHRm5jM3c5TmpVMU16WXNkQ1k5TFhRc2FTNXNZVzVsYzN3OWREdDJZWElnYlQxdFlTaHBMR1FzZENrN1YzVW9hU3h0S1R0aWNtVmhheUJsTzJOaGMyVWdN'
    || 'VHBqUFdRN2RtRnlJSEE5YVM1MGVYQmxMSFk5YVM1emRHRjBaVTV2WkdVN2FXWW9LR2t1Wm14aFozTW1NVEk0S1QwOVBUQW1KaWgwZVhCbGIyWWdjQzVuWlhS'
    || 'RVpYSnBkbVZrVTNSaGRHVkdjbTl0UlhKeWIzSTlQU0ptZFc1amRHbHZiaUo4ZkhZaFBUMXVkV3hzSmlaMGVYQmxiMllnZGk1amIyMXdiMjVsYm5SRWFXUkRZ'
    || 'WFJqYUQwOUltWjFibU4wYVc5dUlpWW1LRmgwUFQwOWJuVnNiSHg4SVZoMExtaGhjeWgyS1NrcEtYdHBMbVpzWVdkemZEMDJOVFV6Tml4MEpqMHRkQ3hwTG14'
    || 'aGJtVnpmRDEwTzNaaGNpQlVQWFpoS0drc1l5eDBLVHRYZFNocExGUXBPMkp5WldGcklHVjlmV2s5YVM1eVpYUjFjbTU5ZDJocGJHVW9hU0U5UFc1MWJHd3Bm'
    || 'VnBoS0c0cGZXTmhkR05vS0VRcGUzUTlSQ3g1WlQwOVBXNG1KbTRoUFQxdWRXeHNKaVlvZVdVOWJqMXVMbkpsZEhWeWJpazdZMjl1ZEdsdWRXVjlZbkpsWVd0'
    || 'OWQyaHBiR1VvSVRBcGZXWjFibU4wYVc5dUlFZGhLQ2w3ZG1GeUlHVTlUbXd1WTNWeWNtVnVkRHR5WlhSMWNtNGdUbXd1WTNWeWNtVnVkRDE0YkN4bFBUMDli'
    || 'blZzYkQ5NGJEcGxmV1oxYm1OMGFXOXVJRlZ2S0NsN0tIZGxQVDA5TUh4OGQyVTlQVDB6Zkh4M1pUMDlQVElwSmlZb2QyVTlOQ2tzYTJVOVBUMXVkV3hzZkh3'
    || 'b1pHNG1Nalk0TkRNMU5EVTFLVDA5UFRBbUppaHFiQ1l5TmpnME16VTBOVFVwUFQwOU1IeDhjWFFvYTJVc1EyVXBmV1oxYm1OMGFXOXVJRkJzS0dVc2RDbDdk'
    || 'bUZ5SUc0OVdqdGFmRDB5TzNaaGNpQnlQVWRoS0NrN0tHdGxJVDA5Wlh4OFEyVWhQVDEwS1NZbUtFbDBQVzUxYkd3c2NHNG9aU3gwS1NrN1pHOGdkSEo1ZTFs'
    || 'bUtDazdZbkpsWVd0OVkyRjBZMmdvYkNsN1MyRW9aU3hzS1gxM2FHbHNaU2doTUNrN2FXWW9TbWtvS1N4YVBXNHNUbXd1WTNWeWNtVnVkRDF5TEhsbElUMDli'
    || 'blZzYkNsMGFISnZkeUJGY25KdmNpaGhLREkyTVNrcE8zSmxkSFZ5YmlCclpUMXVkV3hzTEVObFBUQXNkMlY5Wm5WdVkzUnBiMjRnV1dZb0tYdG1iM0lvTzNs'
    || 'bElUMDliblZzYkRzcFdHRW9lV1VwZldaMWJtTjBhVzl1SUV0bUtDbDdabTl5S0R0NVpTRTlQVzUxYkd3bUppRm5aQ2dwT3lsWVlTaDVaU2w5Wm5WdVkzUnBi'
    || 'MjRnV0dFb1pTbDdkbUZ5SUhROVltRW9aUzVoYkhSbGNtNWhkR1VzWlN4eFpTazdaUzV0WlcxdmFYcGxaRkJ5YjNCelBXVXVjR1Z1WkdsdVoxQnliM0J6TEhR'
    || 'OVBUMXVkV3hzUDFwaEtHVXBPbmxsUFhRc1VtOHVZM1Z5Y21WdWREMXVkV3hzZldaMWJtTjBhVzl1SUZwaEtHVXBlM1poY2lCMFBXVTdaRzk3ZG1GeUlHNDlk'
    || 'QzVoYkhSbGNtNWhkR1U3YVdZb1pUMTBMbkpsZEhWeWJpd29kQzVtYkdGbmN5WXpNamMyT0NrOVBUMHdLWHRwWmlodVBWVm1LRzRzZEN4eFpTa3NiaUU5UFc1'
    || 'MWJHd3BlM2xsUFc0N2NtVjBkWEp1ZlgxbGJITmxlMmxtS0c0OVNHWW9iaXgwS1N4dUlUMDliblZzYkNsN2JpNW1iR0ZuY3lZOU16STNOamNzZVdVOWJqdHla'
    || 'WFIxY201OWFXWW9aU0U5UFc1MWJHd3BaUzVtYkdGbmMzdzlNekkzTmpnc1pTNXpkV0owY21WbFJteGhaM005TUN4bExtUmxiR1YwYVc5dWN6MXVkV3hzTzJW'
    || 'c2MyVjdkMlU5Tml4NVpUMXVkV3hzTzNKbGRIVnlibjE5YVdZb2REMTBMbk5wWW14cGJtY3NkQ0U5UFc1MWJHd3BlM2xsUFhRN2NtVjBkWEp1ZlhsbFBYUTla'
    || 'WDEzYUdsc1pTaDBJVDA5Ym5Wc2JDazdkMlU5UFQwd0ppWW9kMlU5TlNsOVpuVnVZM1JwYjI0Z2FHNG9aU3gwTEc0cGUzWmhjaUJ5UFc1bExHdzliM1F1ZEhK'
    || 'aGJuTnBkR2x2Ymp0MGNubDdiM1F1ZEhKaGJuTnBkR2x2YmoxdWRXeHNMRzVsUFRFc1IyWW9aU3gwTEc0c2NpbDlabWx1WVd4c2VYdHZkQzUwY21GdWMybDBh'
    || 'Vzl1UFd3c2JtVTljbjF5WlhSMWNtNGdiblZzYkgxbWRXNWpkR2x2YmlCSFppaGxMSFFzYml4eUtYdGtieUJYYmlncE8zZG9hV3hsS0ZwMElUMDliblZzYkNr'
    || 'N2FXWW9LRm9tTmlraFBUMHdLWFJvY205M0lFVnljbTl5S0dFb016STNLU2s3YmoxbExtWnBibWx6YUdWa1YyOXlhenQyWVhJZ2JEMWxMbVpwYm1semFHVmtU'
    || 'R0Z1WlhNN2FXWW9iajA5UFc1MWJHd3BjbVYwZFhKdUlHNTFiR3c3YVdZb1pTNW1hVzVwYzJobFpGZHZjbXM5Ym5Wc2JDeGxMbVpwYm1semFHVmtUR0Z1WlhN'
    || 'OU1DeHVQVDA5WlM1amRYSnlaVzUwS1hSb2NtOTNJRVZ5Y205eUtHRW9NVGMzS1NrN1pTNWpZV3hzWW1GamEwNXZaR1U5Ym5Wc2JDeGxMbU5oYkd4aVlXTnJV'
    || 'SEpwYjNKcGRIazlNRHQyWVhJZ2FUMXVMbXhoYm1WemZHNHVZMmhwYkdSTVlXNWxjenRwWmloVVpDaGxMR2twTEdVOVBUMXJaU1ltS0hsbFBXdGxQVzUxYkd3'
    || 'c1EyVTlNQ2tzS0c0dWMzVmlkSEpsWlVac1lXZHpKakl3TmpRcFBUMDlNQ1ltS0c0dVpteGhaM01tTWpBMk5DazlQVDB3Zkh4RGJIeDhLRU5zUFNFd0xHVmpL'
    || 'RVJ5TEdaMWJtTjBhVzl1S0NsN2NtVjBkWEp1SUZkdUtDa3NiblZzYkgwcEtTeHBQU2h1TG1ac1lXZHpKakUxT1Rrd0tTRTlQVEFzS0c0dWMzVmlkSEpsWlVa'
    || 'c1lXZHpKakUxT1Rrd0tTRTlQVEI4ZkdrcGUyazliM1F1ZEhKaGJuTnBkR2x2Yml4dmRDNTBjbUZ1YzJsMGFXOXVQVzUxYkd3N2RtRnlJRzg5Ym1VN2JtVTlN'
    || 'VHQyWVhJZ1l6MWFPMXA4UFRRc1VtOHVZM1Z5Y21WdWREMXVkV3hzTEZkbUtHVXNiaWtzU0dFb2JpeGxLU3hvWmloR2FTa3NWbkk5SVNGQmFTeEdhVDFCYVQx'
    || 'dWRXeHNMR1V1WTNWeWNtVnVkRDF1TEZabUtHNHBMSGxrS0Nrc1dqMWpMRzVsUFc4c2IzUXVkSEpoYm5OcGRHbHZiajFwZldWc2MyVWdaUzVqZFhKeVpXNTBQ'
    || 'VzQ3YVdZb1Eyd21KaWhEYkQwaE1TeGFkRDFsTEV4c1BXd3BMR2s5WlM1d1pXNWthVzVuVEdGdVpYTXNhVDA5UFRBbUppaFlkRDF1ZFd4c0tTeFRaQ2h1TG5O'
    || 'MFlYUmxUbTlrWlNrc1VXVW9aU3gyWlNncEtTeDBJVDA5Ym5Wc2JDbG1iM0lvY2oxbExtOXVVbVZqYjNabGNtRmliR1ZGY25KdmNpeHVQVEE3Ymp4MExteGxi'
    || 'bWQwYUR0dUt5c3BiRDEwVzI1ZExISW9iQzUyWVd4MVpTeDdZMjl0Y0c5dVpXNTBVM1JoWTJzNmJDNXpkR0ZqYXl4a2FXZGxjM1E2YkM1a2FXZGxjM1I5S1R0'
    || 'cFppaFViQ2wwYUhKdmR5QlViRDBoTVN4bFBVOXZMRTl2UFc1MWJHd3NaVHR5WlhSMWNtNG9UR3dtTVNraFBUMHdKaVpsTG5SaFp5RTlQVEFtSmxkdUtDa3Nh'
    || 'VDFsTG5CbGJtUnBibWRNWVc1bGN5d29hU1l4S1NFOVBUQS9aVDA5UFVsdlAxUnlLeXM2S0ZSeVBUQXNTVzg5WlNrNlZISTlNQ3hSZENncExHNTFiR3g5Wm5W'
    || 'dVkzUnBiMjRnVjI0b0tYdHBaaWhhZENFOVBXNTFiR3dwZTNaaGNpQmxQVVp6S0V4c0tTeDBQVzkwTG5SeVlXNXphWFJwYjI0c2JqMXVaVHQwY25sN2FXWW9i'
    || 'M1F1ZEhKaGJuTnBkR2x2YmoxdWRXeHNMRzVsUFRFMlBtVS9NVFk2WlN4YWREMDlQVzUxYkd3cGRtRnlJSEk5SVRFN1pXeHpaWHRwWmlobFBWcDBMRnAwUFc1'
    || 'MWJHd3NUR3c5TUN3b1dpWTJLU0U5UFRBcGRHaHliM2NnUlhKeWIzSW9ZU2d6TXpFcEtUdDJZWElnYkQxYU8yWnZjaWhhZkQwMExGQTlaUzVqZFhKeVpXNTBP'
    || 'MUFoUFQxdWRXeHNPeWw3ZG1GeUlHazlVQ3h2UFdrdVkyaHBiR1E3YVdZb0tGQXVabXhoWjNNbU1UWXBJVDA5TUNsN2RtRnlJR005YVM1a1pXeGxkR2x2Ym5N'
    || 'N2FXWW9ZeUU5UFc1MWJHd3BlMlp2Y2loMllYSWdaRDB3TzJROFl5NXNaVzVuZEdnN1pDc3JLWHQyWVhJZ1p6MWpXMlJkTzJadmNpaFFQV2M3VUNFOVBXNTFi'
    || 'R3c3S1h0MllYSWdSVDFRTzNOM2FYUmphQ2hGTG5SaFp5bDdZMkZ6WlNBd09tTmhjMlVnTVRFNlkyRnpaU0F4TlRwRmNpZzRMRVVzYVNsOWRtRnlJR285UlM1'
    || 'amFHbHNaRHRwWmlocUlUMDliblZzYkNscUxuSmxkSFZ5YmoxRkxGQTlhanRsYkhObElHWnZjaWc3VUNFOVBXNTFiR3c3S1h0RlBWQTdkbUZ5SUZNOVJTNXph'
    || 'V0pzYVc1bkxFMDlSUzV5WlhSMWNtNDdhV1lvZW1Fb1JTa3NSVDA5UFdjcGUxQTliblZzYkR0aWNtVmhhMzFwWmloVElUMDliblZzYkNsN1V5NXlaWFIxY200'
    || 'OVRTeFFQVk03WW5KbFlXdDlVRDFOZlgxOWRtRnlJRWs5YVM1aGJIUmxjbTVoZEdVN2FXWW9TU0U5UFc1MWJHd3BlM1poY2lCNlBVa3VZMmhwYkdRN2FXWW9l'
    || 'aUU5UFc1MWJHd3BlMGt1WTJocGJHUTliblZzYkR0a2IzdDJZWElnWjJVOWVpNXphV0pzYVc1bk8zb3VjMmxpYkdsdVp6MXVkV3hzTEhvOVoyVjlkMmhwYkdV'
    || 'b2VpRTlQVzUxYkd3cGZYMVFQV2w5ZldsbUtDaHBMbk4xWW5SeVpXVkdiR0ZuY3lZeU1EWTBLU0U5UFRBbUptOGhQVDF1ZFd4c0tXOHVjbVYwZFhKdVBXa3NV'
    || 'RDF2TzJWc2MyVWdaVHBtYjNJb08xQWhQVDF1ZFd4c095bDdhV1lvYVQxUUxDaHBMbVpzWVdkekpqSXdORGdwSVQwOU1DbHpkMmwwWTJnb2FTNTBZV2NwZTJO'
    || 'aGMyVWdNRHBqWVhObElERXhPbU5oYzJVZ01UVTZSWElvT1N4cExHa3VjbVYwZFhKdUtYMTJZWElnYlQxcExuTnBZbXhwYm1jN2FXWW9iU0U5UFc1MWJHd3Bl'
    || 'MjB1Y21WMGRYSnVQV2t1Y21WMGRYSnVMRkE5YlR0aWNtVmhheUJsZlZBOWFTNXlaWFIxY201OWZYWmhjaUJ3UFdVdVkzVnljbVZ1ZER0bWIzSW9VRDF3TzFB'
    || 'aFBUMXVkV3hzT3lsN2J6MVFPM1poY2lCMlBXOHVZMmhwYkdRN2FXWW9LRzh1YzNWaWRISmxaVVpzWVdkekpqSXdOalFwSVQwOU1DWW1kaUU5UFc1MWJHd3Bk'
    || 'aTV5WlhSMWNtNDlieXhRUFhZN1pXeHpaU0JsT21admNpaHZQWEE3VUNFOVBXNTFiR3c3S1h0cFppaGpQVkFzS0dNdVpteGhaM01tTWpBME9Da2hQVDB3S1hS'
    || 'eWVYdHpkMmwwWTJnb1l5NTBZV2NwZTJOaGMyVWdNRHBqWVhObElERXhPbU5oYzJVZ01UVTZSV3dvT1N4aktYMTlZMkYwWTJnb1JDbDdiV1VvWXl4akxuSmxk'
    || 'SFZ5Yml4RUtYMXBaaWhqUFQwOWJ5bDdVRDF1ZFd4c08ySnlaV0ZySUdWOWRtRnlJRlE5WXk1emFXSnNhVzVuTzJsbUtGUWhQVDF1ZFd4c0tYdFVMbkpsZEhW'
    || 'eWJqMWpMbkpsZEhWeWJpeFFQVlE3WW5KbFlXc2daWDFRUFdNdWNtVjBkWEp1ZlgxcFppaGFQV3dzVVhRb0tTeDNkQ1ltZEhsd1pXOW1JSGQwTG05dVVHOXpk'
    || 'RU52YlcxcGRFWnBZbVZ5VW05dmREMDlJbVoxYm1OMGFXOXVJaWwwY25sN2QzUXViMjVRYjNOMFEyOXRiV2wwUm1saVpYSlNiMjkwS0VGeUxHVXBmV05oZEdO'
    || 'b2UzMXlQU0V3ZlhKbGRIVnliaUJ5ZldacGJtRnNiSGw3Ym1VOWJpeHZkQzUwY21GdWMybDBhVzl1UFhSOWZYSmxkSFZ5YmlFeGZXWjFibU4wYVc5dUlFcGhL'
    || 'R1VzZEN4dUtYdDBQVVp1S0c0c2RDa3NkRDF0WVNobExIUXNNU2tzWlQxTGRDaGxMSFFzTVNrc2REMUVaU2dwTEdVaFBUMXVkV3hzSmlZb1NtNG9aU3d4TEhR'
    || 'cExGRmxLR1VzZENrcGZXWjFibU4wYVc5dUlHMWxLR1VzZEN4dUtYdHBaaWhsTG5SaFp6MDlQVE1wU21Fb1pTeGxMRzRwTzJWc2MyVWdabTl5S0R0MElUMDli'
    || 'blZzYkRzcGUybG1LSFF1ZEdGblBUMDlNeWw3U21Fb2RDeGxMRzRwTzJKeVpXRnJmV1ZzYzJVZ2FXWW9kQzUwWVdjOVBUMHhLWHQyWVhJZ2NqMTBMbk4wWVhS'
    || 'bFRtOWtaVHRwWmloMGVYQmxiMllnZEM1MGVYQmxMbWRsZEVSbGNtbDJaV1JUZEdGMFpVWnliMjFGY25KdmNqMDlJbVoxYm1OMGFXOXVJbng4ZEhsd1pXOW1J'
    || 'SEl1WTI5dGNHOXVaVzUwUkdsa1EyRjBZMmc5UFNKbWRXNWpkR2x2YmlJbUppaFlkRDA5UFc1MWJHeDhmQ0ZZZEM1b1lYTW9jaWtwS1h0bFBVWnVLRzRzWlNr'
    || 'c1pUMTJZU2gwTEdVc01Ta3NkRDFMZENoMExHVXNNU2tzWlQxRVpTZ3BMSFFoUFQxdWRXeHNKaVlvU200b2RDd3hMR1VwTEZGbEtIUXNaU2twTzJKeVpXRnJm'
    || 'WDEwUFhRdWNtVjBkWEp1ZlgxbWRXNWpkR2x2YmlCWVppaGxMSFFzYmlsN2RtRnlJSEk5WlM1d2FXNW5RMkZqYUdVN2NpRTlQVzUxYkd3bUpuSXVaR1ZzWlhS'
    || 'bEtIUXBMSFE5UkdVb0tTeGxMbkJwYm1kbFpFeGhibVZ6ZkQxbExuTjFjM0JsYm1SbFpFeGhibVZ6Sm00c2EyVTlQVDFsSmlZb1EyVW1iaWs5UFQxdUppWW9k'
    || 'MlU5UFQwMGZIeDNaVDA5UFRNbUppaERaU1l4TXpBd01qTTBNalFwUFQwOVEyVW1KalV3TUQ1MlpTZ3BMVkJ2UDNCdUtHVXNNQ2s2VFc5OFBXNHBMRkZsS0dV'
    || 'c2RDbDlablZ1WTNScGIyNGdjV0VvWlN4MEtYdDBQVDA5TUNZbUtDaGxMbTF2WkdVbU1TazlQVDB3UDNROU1Ub29kRDFWY2l4VmNqdzhQVEVzS0ZWeUpqRXpN'
    || 'REF5TXpReU5DazlQVDB3SmlZb1ZYSTlOREU1TkRNd05Da3BLVHQyWVhJZ2JqMUVaU2dwTzJVOVRYUW9aU3gwS1N4bElUMDliblZzYkNZbUtFcHVLR1VzZEN4'
    || 'dUtTeFJaU2hsTEc0cEtYMW1kVzVqZEdsdmJpQmFaaWhsS1h0MllYSWdkRDFsTG0xbGJXOXBlbVZrVTNSaGRHVXNiajB3TzNRaFBUMXVkV3hzSmlZb2JqMTBM'
    || 'bkpsZEhKNVRHRnVaU2tzY1dFb1pTeHVLWDFtZFc1amRHbHZiaUJLWmlobExIUXBlM1poY2lCdVBUQTdjM2RwZEdOb0tHVXVkR0ZuS1h0allYTmxJREV6T25a'
    || 'aGNpQnlQV1V1YzNSaGRHVk9iMlJsTEd3OVpTNXRaVzF2YVhwbFpGTjBZWFJsTzJ3aFBUMXVkV3hzSmlZb2JqMXNMbkpsZEhKNVRHRnVaU2s3WW5KbFlXczdZ'
    || 'MkZ6WlNBeE9UcHlQV1V1YzNSaGRHVk9iMlJsTzJKeVpXRnJPMlJsWm1GMWJIUTZkR2h5YjNjZ1JYSnliM0lvWVNnek1UUXBLWDF5SVQwOWJuVnNiQ1ltY2k1'
    || 'a1pXeGxkR1VvZENrc2NXRW9aU3h1S1gxMllYSWdZbUU3WW1FOVpuVnVZM1JwYjI0b1pTeDBMRzRwZTJsbUtHVWhQVDF1ZFd4c0tXbG1LR1V1YldWdGIybDZa'
    || 'V1JRY205d2N5RTlQWFF1Y0dWdVpHbHVaMUJ5YjNCemZId2taUzVqZFhKeVpXNTBLVlpsUFNFd08yVnNjMlY3YVdZb0tHVXViR0Z1WlhNbWJpazlQVDB3SmlZ'
    || 'b2RDNW1iR0ZuY3lZeE1qZ3BQVDA5TUNseVpYUjFjbTRnVm1VOUlURXNSbVlvWlN4MExHNHBPMVpsUFNobExtWnNZV2R6SmpFek1UQTNNaWtoUFQwd2ZXVnNj'
    || 'MlVnVm1VOUlURXNZMlVtSmloMExtWnNZV2R6SmpFd05EZzFOellwSVQwOU1DWW1VSFVvZEN4emJDeDBMbWx1WkdWNEtUdHpkMmwwWTJnb2RDNXNZVzVsY3ow'
    || 'd0xIUXVkR0ZuS1h0allYTmxJREk2ZG1GeUlISTlkQzUwZVhCbE8xOXNLR1VzZENrc1pUMTBMbkJsYm1ScGJtZFFjbTl3Y3p0MllYSWdiRDFTYmloMExGSmxM'
    || 'bU4xY25KbGJuUXBPMFJ1S0hRc2Jpa3NiRDExYnlodWRXeHNMSFFzY2l4bExHd3NiaWs3ZG1GeUlHazlZVzhvS1R0eVpYUjFjbTRnZEM1bWJHRm5jM3c5TVN4'
    || 'MGVYQmxiMllnYkQwOUltOWlhbVZqZENJbUptd2hQVDF1ZFd4c0ppWjBlWEJsYjJZZ2JDNXlaVzVrWlhJOVBTSm1kVzVqZEdsdmJpSW1KbXd1SkNSMGVYQmxi'
    || 'Mlk5UFQxMmIybGtJREEvS0hRdWRHRm5QVEVzZEM1dFpXMXZhWHBsWkZOMFlYUmxQVzUxYkd3c2RDNTFjR1JoZEdWUmRXVjFaVDF1ZFd4c0xGZGxLSElwUHlo'
    || 'cFBTRXdMR3hzS0hRcEtUcHBQU0V4TEhRdWJXVnRiMmw2WldSVGRHRjBaVDFzTG5OMFlYUmxJVDA5Ym5Wc2JDWW1iQzV6ZEdGMFpTRTlQWFp2YVdRZ01EOXNM'
    || 'bk4wWVhSbE9tNTFiR3dzZEc4b2RDa3NiQzUxY0dSaGRHVnlQWGRzTEhRdWMzUmhkR1ZPYjJSbFBXd3NiQzVmY21WaFkzUkpiblJsY201aGJITTlkQ3gyYnlo'
    || 'MExISXNaU3h1S1N4MFBYZHZLRzUxYkd3c2RDeHlMQ0V3TEdrc2Jpa3BPaWgwTG5SaFp6MHdMR05sSmlacEppWlJhU2gwS1N4NlpTaHVkV3hzTEhRc2JDeHVL'
    || 'U3gwUFhRdVkyaHBiR1FwTEhRN1kyRnpaU0F4TmpweVBYUXVaV3hsYldWdWRGUjVjR1U3WlRwN2MzZHBkR05vS0Y5c0tHVXNkQ2tzWlQxMExuQmxibVJwYm1k'
    || 'UWNtOXdjeXhzUFhJdVgybHVhWFFzY2oxc0tISXVYM0JoZVd4dllXUXBMSFF1ZEhsd1pUMXlMR3c5ZEM1MFlXYzlZbVlvY2lrc1pUMXdkQ2h5TEdVcExHd3Bl'
    || 'Mk5oYzJVZ01EcDBQWGh2S0c1MWJHd3NkQ3h5TEdVc2JpazdZbkpsWVdzZ1pUdGpZWE5sSURFNmREMU9ZU2h1ZFd4c0xIUXNjaXhsTEc0cE8ySnlaV0ZySUdV'
    || 'N1kyRnpaU0F4TVRwMFBYZGhLRzUxYkd3c2RDeHlMR1VzYmlrN1luSmxZV3NnWlR0allYTmxJREUwT25ROVUyRW9iblZzYkN4MExISXNjSFFvY2k1MGVYQmxM'
    || 'R1VwTEc0cE8ySnlaV0ZySUdWOWRHaHliM2NnUlhKeWIzSW9ZU2d6TURZc2Npd2lJaWtwZlhKbGRIVnliaUIwTzJOaGMyVWdNRHB5WlhSMWNtNGdjajEwTG5S'
    || 'NWNHVXNiRDEwTG5CbGJtUnBibWRRY205d2N5eHNQWFF1Wld4bGJXVnVkRlI1Y0dVOVBUMXlQMnc2Y0hRb2NpeHNLU3g0YnlobExIUXNjaXhzTEc0cE8yTmhj'
    || 'MlVnTVRweVpYUjFjbTRnY2oxMExuUjVjR1VzYkQxMExuQmxibVJwYm1kUWNtOXdjeXhzUFhRdVpXeGxiV1Z1ZEZSNWNHVTlQVDF5UDJ3NmNIUW9jaXhzS1N4'
    || 'T1lTaGxMSFFzY2l4c0xHNHBPMk5oYzJVZ016cGxPbnRwWmlocVlTaDBLU3hsUFQwOWJuVnNiQ2wwYUhKdmR5QkZjbkp2Y2loaEtETTROeWtwTzNJOWRDNXda'
    || 'VzVrYVc1blVISnZjSE1zYVQxMExtMWxiVzlwZW1Wa1UzUmhkR1VzYkQxcExtVnNaVzFsYm5Rc0pIVW9aU3gwS1N4d2JDaDBMSElzYm5Wc2JDeHVLVHQyWVhJ'
    || 'Z2J6MTBMbTFsYlc5cGVtVmtVM1JoZEdVN2FXWW9jajF2TG1Wc1pXMWxiblFzYVM1cGMwUmxhSGxrY21GMFpXUXBhV1lvYVQxN1pXeGxiV1Z1ZERweUxHbHpS'
    || 'R1ZvZVdSeVlYUmxaRG9oTVN4allXTm9aVHB2TG1OaFkyaGxMSEJsYm1ScGJtZFRkWE53Wlc1elpVSnZkVzVrWVhKcFpYTTZieTV3Wlc1a2FXNW5VM1Z6Y0dW'
    || 'dWMyVkNiM1Z1WkdGeWFXVnpMSFJ5WVc1emFYUnBiMjV6T204dWRISmhibk5wZEdsdmJuTjlMSFF1ZFhCa1lYUmxVWFZsZFdVdVltRnpaVk4wWVhSbFBXa3Nk'
    || 'QzV0WlcxdmFYcGxaRk4wWVhSbFBXa3NkQzVtYkdGbmN5WXlOVFlwZTJ3OVJtNG9SWEp5YjNJb1lTZzBNak1wS1N4MEtTeDBQVlJoS0dVc2RDeHlMRzRzYkNr'
    || 'N1luSmxZV3NnWlgxbGJITmxJR2xtS0hJaFBUMXNLWHRzUFVadUtFVnljbTl5S0dFb05ESTBLU2tzZENrc2REMVVZU2hsTEhRc2NpeHVMR3dwTzJKeVpXRnJJ'
    || 'R1Y5Wld4elpTQm1iM0lvU21VOVYzUW9kQzV6ZEdGMFpVNXZaR1V1WTI5dWRHRnBibVZ5U1c1bWJ5NW1hWEp6ZEVOb2FXeGtLU3hhWlQxMExHTmxQU0V3TEda'
    || 'MFBXNTFiR3dzYmoxVmRTaDBMRzUxYkd3c2NpeHVLU3gwTG1Ob2FXeGtQVzQ3YmpzcGJpNW1iR0ZuY3oxdUxtWnNZV2R6SmkwemZEUXdPVFlzYmoxdUxuTnBZ'
    || 'bXhwYm1jN1pXeHpaWHRwWmloUGJpZ3BMSEk5UFQxc0tYdDBQVTkwS0dVc2RDeHVLVHRpY21WaGF5QmxmWHBsS0dVc2RDeHlMRzRwZlhROWRDNWphR2xzWkgx'
    || 'eVpYUjFjbTRnZER0allYTmxJRFU2Y21WMGRYSnVJRUoxS0hRcExHVTlQVDF1ZFd4c0ppWkhhU2gwS1N4eVBYUXVkSGx3WlN4c1BYUXVjR1Z1WkdsdVoxQnli'
    || 'M0J6TEdrOVpTRTlQVzUxYkd3L1pTNXRaVzF2YVhwbFpGQnliM0J6T201MWJHd3NiejFzTG1Ob2FXeGtjbVZ1TEZWcEtISXNiQ2svYnoxdWRXeHNPbWtoUFQx'
    || 'dWRXeHNKaVpWYVNoeUxHa3BKaVlvZEM1bWJHRm5jM3c5TXpJcExFVmhLR1VzZENrc2VtVW9aU3gwTEc4c2Jpa3NkQzVqYUdsc1pEdGpZWE5sSURZNmNtVjBk'
    || 'WEp1SUdVOVBUMXVkV3hzSmlaSGFTaDBLU3h1ZFd4c08yTmhjMlVnTVRNNmNtVjBkWEp1SUVOaEtHVXNkQ3h1S1R0allYTmxJRFE2Y21WMGRYSnVJRzV2S0hR'
    || 'c2RDNXpkR0YwWlU1dlpHVXVZMjl1ZEdGcGJtVnlTVzVtYnlrc2NqMTBMbkJsYm1ScGJtZFFjbTl3Y3l4bFBUMDliblZzYkQ5MExtTm9hV3hrUFVsdUtIUXNi'
    || 'blZzYkN4eUxHNHBPbnBsS0dVc2RDeHlMRzRwTEhRdVkyaHBiR1E3WTJGelpTQXhNVHB5WlhSMWNtNGdjajEwTG5SNWNHVXNiRDEwTG5CbGJtUnBibWRRY205'
    || 'd2N5eHNQWFF1Wld4bGJXVnVkRlI1Y0dVOVBUMXlQMnc2Y0hRb2NpeHNLU3gzWVNobExIUXNjaXhzTEc0cE8yTmhjMlVnTnpweVpYUjFjbTRnZW1Vb1pTeDBM'
    || 'SFF1Y0dWdVpHbHVaMUJ5YjNCekxHNHBMSFF1WTJocGJHUTdZMkZ6WlNBNE9uSmxkSFZ5YmlCNlpTaGxMSFFzZEM1d1pXNWthVzVuVUhKdmNITXVZMmhwYkdS'
    || 'eVpXNHNiaWtzZEM1amFHbHNaRHRqWVhObElERXlPbkpsZEhWeWJpQjZaU2hsTEhRc2RDNXdaVzVrYVc1blVISnZjSE11WTJocGJHUnlaVzRzYmlrc2RDNWph'
    || 'R2xzWkR0allYTmxJREV3T21VNmUybG1LSEk5ZEM1MGVYQmxMbDlqYjI1MFpYaDBMR3c5ZEM1d1pXNWthVzVuVUhKdmNITXNhVDEwTG0xbGJXOXBlbVZrVUhK'
    || 'dmNITXNiejFzTG5aaGJIVmxMR2xsS0dOc0xISXVYMk4xY25KbGJuUldZV3gxWlNrc2NpNWZZM1Z5Y21WdWRGWmhiSFZsUFc4c2FTRTlQVzUxYkd3cGFXWW9a'
    || 'SFFvYVM1MllXeDFaU3h2S1NsN2FXWW9hUzVqYUdsc1pISmxiajA5UFd3dVkyaHBiR1J5Wlc0bUppRWtaUzVqZFhKeVpXNTBLWHQwUFU5MEtHVXNkQ3h1S1R0'
    || 'aWNtVmhheUJsZlgxbGJITmxJR1p2Y2locFBYUXVZMmhwYkdRc2FTRTlQVzUxYkd3bUppaHBMbkpsZEhWeWJqMTBLVHRwSVQwOWJuVnNiRHNwZTNaaGNpQmpQ'
    || 'V2t1WkdWd1pXNWtaVzVqYVdWek8ybG1LR01oUFQxdWRXeHNLWHR2UFdrdVkyaHBiR1E3Wm05eUtIWmhjaUJrUFdNdVptbHljM1JEYjI1MFpYaDBPMlFoUFQx'
    || 'dWRXeHNPeWw3YVdZb1pDNWpiMjUwWlhoMFBUMDljaWw3YVdZb2FTNTBZV2M5UFQweEtYdGtQVkIwS0MweExHNG1MVzRwTEdRdWRHRm5QVEk3ZG1GeUlHYzlh'
    || 'UzUxY0dSaGRHVlJkV1YxWlR0cFppaG5JVDA5Ym5Wc2JDbDdaejFuTG5Ob1lYSmxaRHQyWVhJZ1JUMW5MbkJsYm1ScGJtYzdSVDA5UFc1MWJHdy9aQzV1Wlho'
    || 'MFBXUTZLR1F1Ym1WNGREMUZMbTVsZUhRc1JTNXVaWGgwUFdRcExHY3VjR1Z1WkdsdVp6MWtmWDFwTG14aGJtVnpmRDF1TEdROWFTNWhiSFJsY201aGRHVXNa'
    || 'Q0U5UFc1MWJHd21KaWhrTG14aGJtVnpmRDF1S1N4aWFTaHBMbkpsZEhWeWJpeHVMSFFwTEdNdWJHRnVaWE44UFc0N1luSmxZV3Q5WkQxa0xtNWxlSFI5ZldW'
    || 'c2MyVWdhV1lvYVM1MFlXYzlQVDB4TUNsdlBXa3VkSGx3WlQwOVBYUXVkSGx3WlQ5dWRXeHNPbWt1WTJocGJHUTdaV3h6WlNCcFppaHBMblJoWnowOVBURTRL'
    || 'WHRwWmlodlBXa3VjbVYwZFhKdUxHODlQVDF1ZFd4c0tYUm9jbTkzSUVWeWNtOXlLR0VvTXpReEtTazdieTVzWVc1bGMzdzliaXhqUFc4dVlXeDBaWEp1WVhS'
    || 'bExHTWhQVDF1ZFd4c0ppWW9ZeTVzWVc1bGMzdzliaWtzWW1rb2J5eHVMSFFwTEc4OWFTNXphV0pzYVc1bmZXVnNjMlVnYnoxcExtTm9hV3hrTzJsbUtHOGhQ'
    || 'VDF1ZFd4c0tXOHVjbVYwZFhKdVBXazdaV3h6WlNCbWIzSW9iejFwTzI4aFBUMXVkV3hzT3lsN2FXWW9iejA5UFhRcGUyODliblZzYkR0aWNtVmhhMzFwWmlo'
    || 'cFBXOHVjMmxpYkdsdVp5eHBJVDA5Ym5Wc2JDbDdhUzV5WlhSMWNtNDlieTV5WlhSMWNtNHNiejFwTzJKeVpXRnJmVzg5Ynk1eVpYUjFjbTU5YVQxdmZYcGxL'
    || 'R1VzZEN4c0xtTm9hV3hrY21WdUxHNHBMSFE5ZEM1amFHbHNaSDF5WlhSMWNtNGdkRHRqWVhObElEazZjbVYwZFhKdUlHdzlkQzUwZVhCbExISTlkQzV3Wlc1'
    || 'a2FXNW5VSEp2Y0hNdVkyaHBiR1J5Wlc0c1JHNG9kQ3h1S1N4c1BXeDBLR3dwTEhJOWNpaHNLU3gwTG1ac1lXZHpmRDB4TEhwbEtHVXNkQ3h5TEc0cExIUXVZ'
    || 'MmhwYkdRN1kyRnpaU0F4TkRweVpYUjFjbTRnY2oxMExuUjVjR1VzYkQxd2RDaHlMSFF1Y0dWdVpHbHVaMUJ5YjNCektTeHNQWEIwS0hJdWRIbHdaU3hzS1N4'
    || 'VFlTaGxMSFFzY2l4c0xHNHBPMk5oYzJVZ01UVTZjbVYwZFhKdUlGOWhLR1VzZEN4MExuUjVjR1VzZEM1d1pXNWthVzVuVUhKdmNITXNiaWs3WTJGelpTQXhO'
    || 'enB5WlhSMWNtNGdjajEwTG5SNWNHVXNiRDEwTG5CbGJtUnBibWRRY205d2N5eHNQWFF1Wld4bGJXVnVkRlI1Y0dVOVBUMXlQMnc2Y0hRb2NpeHNLU3hmYkNo'
    || 'bExIUXBMSFF1ZEdGblBURXNWMlVvY2lrL0tHVTlJVEFzYkd3b2RDa3BPbVU5SVRFc1JHNG9kQ3h1S1N4d1lTaDBMSElzYkNrc2RtOG9kQ3h5TEd3c2Jpa3Nk'
    || 'MjhvYm5Wc2JDeDBMSElzSVRBc1pTeHVLVHRqWVhObElERTVPbkpsZEhWeWJpQlNZU2hsTEhRc2JpazdZMkZ6WlNBeU1qcHlaWFIxY200Z2EyRW9aU3gwTEc0'
    || 'cGZYUm9jbTkzSUVWeWNtOXlLR0VvTVRVMkxIUXVkR0ZuS1NsOU8yWjFibU4wYVc5dUlHVmpLR1VzZENsN2NtVjBkWEp1SUU5ektHVXNkQ2w5Wm5WdVkzUnBi'
    || 'MjRnY1dZb1pTeDBMRzRzY2lsN2RHaHBjeTUwWVdjOVpTeDBhR2x6TG10bGVUMXVMSFJvYVhNdWMybGliR2x1WnoxMGFHbHpMbU5vYVd4a1BYUm9hWE11Y21W'
    || 'MGRYSnVQWFJvYVhNdWMzUmhkR1ZPYjJSbFBYUm9hWE11ZEhsd1pUMTBhR2x6TG1Wc1pXMWxiblJVZVhCbFBXNTFiR3dzZEdocGN5NXBibVJsZUQwd0xIUm9h'
    || 'WE11Y21WbVBXNTFiR3dzZEdocGN5NXdaVzVrYVc1blVISnZjSE05ZEN4MGFHbHpMbVJsY0dWdVpHVnVZMmxsY3oxMGFHbHpMbTFsYlc5cGVtVmtVM1JoZEdV'
    || 'OWRHaHBjeTUxY0dSaGRHVlJkV1YxWlQxMGFHbHpMbTFsYlc5cGVtVmtVSEp2Y0hNOWJuVnNiQ3gwYUdsekxtMXZaR1U5Y2l4MGFHbHpMbk4xWW5SeVpXVkdi'
    || 'R0ZuY3oxMGFHbHpMbVpzWVdkelBUQXNkR2hwY3k1a1pXeGxkR2x2Ym5NOWJuVnNiQ3gwYUdsekxtTm9hV3hrVEdGdVpYTTlkR2hwY3k1c1lXNWxjejB3TEhS'
    || 'b2FYTXVZV3gwWlhKdVlYUmxQVzUxYkd4OVpuVnVZM1JwYjI0Z2MzUW9aU3gwTEc0c2NpbDdjbVYwZFhKdUlHNWxkeUJ4WmlobExIUXNiaXh5S1gxbWRXNWpk'
    || 'R2x2YmlCSWJ5aGxLWHR5WlhSMWNtNGdaVDFsTG5CeWIzUnZkSGx3WlN3aEtDRmxmSHdoWlM1cGMxSmxZV04wUTI5dGNHOXVaVzUwS1gxbWRXNWpkR2x2YmlC'
    || 'aVppaGxLWHRwWmloMGVYQmxiMllnWlQwOUltWjFibU4wYVc5dUlpbHlaWFIxY200Z1NHOG9aU2svTVRvd08ybG1LR1VoUFc1MWJHd3BlMmxtS0dVOVpTNGtK'
    || 'SFI1Y0dWdlppeGxQVDA5ZVhRcGNtVjBkWEp1SURFeE8ybG1LR1U5UFQxNGRDbHlaWFIxY200Z01UUjljbVYwZFhKdUlESjlablZ1WTNScGIyNGdZblFvWlN4'
    || 'MEtYdDJZWElnYmoxbExtRnNkR1Z5Ym1GMFpUdHlaWFIxY200Z2JqMDlQVzUxYkd3L0tHNDljM1FvWlM1MFlXY3NkQ3hsTG10bGVTeGxMbTF2WkdVcExHNHVa'
    || 'V3hsYldWdWRGUjVjR1U5WlM1bGJHVnRaVzUwVkhsd1pTeHVMblI1Y0dVOVpTNTBlWEJsTEc0dWMzUmhkR1ZPYjJSbFBXVXVjM1JoZEdWT2IyUmxMRzR1WVd4'
    || 'MFpYSnVZWFJsUFdVc1pTNWhiSFJsY201aGRHVTliaWs2S0c0dWNHVnVaR2x1WjFCeWIzQnpQWFFzYmk1MGVYQmxQV1V1ZEhsd1pTeHVMbVpzWVdkelBUQXNi'
    || 'aTV6ZFdKMGNtVmxSbXhoWjNNOU1DeHVMbVJsYkdWMGFXOXVjejF1ZFd4c0tTeHVMbVpzWVdkelBXVXVabXhoWjNNbU1UUTJPREF3TmpRc2JpNWphR2xzWkV4'
    || 'aGJtVnpQV1V1WTJocGJHUk1ZVzVsY3l4dUxteGhibVZ6UFdVdWJHRnVaWE1zYmk1amFHbHNaRDFsTG1Ob2FXeGtMRzR1YldWdGIybDZaV1JRY205d2N6MWxM'
    || 'bTFsYlc5cGVtVmtVSEp2Y0hNc2JpNXRaVzF2YVhwbFpGTjBZWFJsUFdVdWJXVnRiMmw2WldSVGRHRjBaU3h1TG5Wd1pHRjBaVkYxWlhWbFBXVXVkWEJrWVhS'
    || 'bFVYVmxkV1VzZEQxbExtUmxjR1Z1WkdWdVkybGxjeXh1TG1SbGNHVnVaR1Z1WTJsbGN6MTBQVDA5Ym5Wc2JEOXVkV3hzT250c1lXNWxjenAwTG14aGJtVnpM'
    || 'R1pwY25OMFEyOXVkR1Y0ZERwMExtWnBjbk4wUTI5dWRHVjRkSDBzYmk1emFXSnNhVzVuUFdVdWMybGliR2x1Wnl4dUxtbHVaR1Y0UFdVdWFXNWtaWGdzYmk1'
    || 'eVpXWTlaUzV5WldZc2JuMW1kVzVqZEdsdmJpQlBiQ2hsTEhRc2JpeHlMR3dzYVNsN2RtRnlJRzg5TWp0cFppaHlQV1VzZEhsd1pXOW1JR1U5UFNKbWRXNWpk'
    || 'R2x2YmlJcFNHOG9aU2ttSmlodlBURXBPMlZzYzJVZ2FXWW9kSGx3Wlc5bUlHVTlQU0p6ZEhKcGJtY2lLVzg5TlR0bGJITmxJR1U2YzNkcGRHTm9LR1VwZTJO'
    || 'aGMyVWdhbVU2Y21WMGRYSnVJRzF1S0c0dVkyaHBiR1J5Wlc0c2JDeHBMSFFwTzJOaGMyVWdTV1U2YnowNExHeDhQVGc3WW5KbFlXczdZMkZ6WlNCd1pUcHla'
    || 'WFIxY200Z1pUMXpkQ2d4TWl4dUxIUXNiSHd5S1N4bExtVnNaVzFsYm5SVWVYQmxQWEJsTEdVdWJHRnVaWE05YVN4bE8yTmhjMlVnUzJVNmNtVjBkWEp1SUdV'
    || 'OWMzUW9NVE1zYml4MExHd3BMR1V1Wld4bGJXVnVkRlI1Y0dVOVMyVXNaUzVzWVc1bGN6MXBMR1U3WTJGelpTQmhkRHB5WlhSMWNtNGdaVDF6ZENneE9TeHVM'
    || 'SFFzYkNrc1pTNWxiR1Z0Wlc1MFZIbHdaVDFoZEN4bExteGhibVZ6UFdrc1pUdGpZWE5sSUdobE9uSmxkSFZ5YmlCSmJDaHVMR3dzYVN4MEtUdGtaV1poZFd4'
    || 'ME9tbG1LSFI1Y0dWdlppQmxQVDBpYjJKcVpXTjBJaVltWlNFOVBXNTFiR3dwYzNkcGRHTm9LR1V1SkNSMGVYQmxiMllwZTJOaGMyVWdhblE2YnoweE1EdGlj'
    || 'bVZoYXlCbE8yTmhjMlVnZEc0NmJ6MDVPMkp5WldGcklHVTdZMkZ6WlNCNWREcHZQVEV4TzJKeVpXRnJJR1U3WTJGelpTQjRkRHB2UFRFME8ySnlaV0ZySUdV'
    || 'N1kyRnpaU0JJWlRwdlBURTJMSEk5Ym5Wc2JEdGljbVZoYXlCbGZYUm9jbTkzSUVWeWNtOXlLR0VvTVRNd0xHVTlQVzUxYkd3L1pUcDBlWEJsYjJZZ1pTd2lJ'
    || 'aWtwZlhKbGRIVnliaUIwUFhOMEtHOHNiaXgwTEd3cExIUXVaV3hsYldWdWRGUjVjR1U5WlN4MExuUjVjR1U5Y2l4MExteGhibVZ6UFdrc2RIMW1kVzVqZEds'
    || 'dmJpQnRiaWhsTEhRc2JpeHlLWHR5WlhSMWNtNGdaVDF6ZENnM0xHVXNjaXgwS1N4bExteGhibVZ6UFc0c1pYMW1kVzVqZEdsdmJpQkpiQ2hsTEhRc2JpeHlL'
    || 'WHR5WlhSMWNtNGdaVDF6ZENneU1peGxMSElzZENrc1pTNWxiR1Z0Wlc1MFZIbHdaVDFvWlN4bExteGhibVZ6UFc0c1pTNXpkR0YwWlU1dlpHVTllMmx6U0ds'
    || 'a1pHVnVPaUV4ZlN4bGZXWjFibU4wYVc5dUlDUnZLR1VzZEN4dUtYdHlaWFIxY200Z1pUMXpkQ2cyTEdVc2JuVnNiQ3gwS1N4bExteGhibVZ6UFc0c1pYMW1k'
    || 'VzVqZEdsdmJpQlhieWhsTEhRc2JpbDdjbVYwZFhKdUlIUTljM1FvTkN4bExtTm9hV3hrY21WdUlUMDliblZzYkQ5bExtTm9hV3hrY21WdU9sdGRMR1V1YTJW'
    || 'NUxIUXBMSFF1YkdGdVpYTTliaXgwTG5OMFlYUmxUbTlrWlQxN1kyOXVkR0ZwYm1WeVNXNW1ienBsTG1OdmJuUmhhVzVsY2tsdVptOHNjR1Z1WkdsdVowTm9h'
    || 'V3hrY21WdU9tNTFiR3dzYVcxd2JHVnRaVzUwWVhScGIyNDZaUzVwYlhCc1pXMWxiblJoZEdsdmJuMHNkSDFtZFc1amRHbHZiaUJsY0NobExIUXNiaXh5TEd3'
    || 'cGUzUm9hWE11ZEdGblBYUXNkR2hwY3k1amIyNTBZV2x1WlhKSmJtWnZQV1VzZEdocGN5NW1hVzVwYzJobFpGZHZjbXM5ZEdocGN5NXdhVzVuUTJGamFHVTlk'
    || 'R2hwY3k1amRYSnlaVzUwUFhSb2FYTXVjR1Z1WkdsdVowTm9hV3hrY21WdVBXNTFiR3dzZEdocGN5NTBhVzFsYjNWMFNHRnVaR3hsUFMweExIUm9hWE11WTJG'
    || 'c2JHSmhZMnRPYjJSbFBYUm9hWE11Y0dWdVpHbHVaME52Ym5SbGVIUTlkR2hwY3k1amIyNTBaWGgwUFc1MWJHd3NkR2hwY3k1allXeHNZbUZqYTFCeWFXOXlh'
    || 'WFI1UFRBc2RHaHBjeTVsZG1WdWRGUnBiV1Z6UFdocEtEQXBMSFJvYVhNdVpYaHdhWEpoZEdsdmJsUnBiV1Z6UFdocEtDMHhLU3gwYUdsekxtVnVkR0Z1WjJ4'
    || 'bFpFeGhibVZ6UFhSb2FYTXVabWx1YVhOb1pXUk1ZVzVsY3oxMGFHbHpMbTExZEdGaWJHVlNaV0ZrVEdGdVpYTTlkR2hwY3k1bGVIQnBjbVZrVEdGdVpYTTlk'
    || 'R2hwY3k1d2FXNW5aV1JNWVc1bGN6MTBhR2x6TG5OMWMzQmxibVJsWkV4aGJtVnpQWFJvYVhNdWNHVnVaR2x1WjB4aGJtVnpQVEFzZEdocGN5NWxiblJoYm1k'
    || 'c1pXMWxiblJ6UFdocEtEQXBMSFJvYVhNdWFXUmxiblJwWm1sbGNsQnlaV1pwZUQxeUxIUm9hWE11YjI1U1pXTnZkbVZ5WVdKc1pVVnljbTl5UFd3c2RHaHBj'
    || 'eTV0ZFhSaFlteGxVMjkxY21ObFJXRm5aWEpJZVdSeVlYUnBiMjVFWVhSaFBXNTFiR3g5Wm5WdVkzUnBiMjRnVm04b1pTeDBMRzRzY2l4c0xHa3NieXhqTEdR'
    || 'cGUzSmxkSFZ5YmlCbFBXNWxkeUJsY0NobExIUXNiaXhqTEdRcExIUTlQVDB4UHloMFBURXNhVDA5UFNFd0ppWW9kSHc5T0NrcE9uUTlNQ3hwUFhOMEtETXNi'
    || 'blZzYkN4dWRXeHNMSFFwTEdVdVkzVnljbVZ1ZEQxcExHa3VjM1JoZEdWT2IyUmxQV1VzYVM1dFpXMXZhWHBsWkZOMFlYUmxQWHRsYkdWdFpXNTBPbklzYVhO'
    || 'RVpXaDVaSEpoZEdWa09tNHNZMkZqYUdVNmJuVnNiQ3gwY21GdWMybDBhVzl1Y3pwdWRXeHNMSEJsYm1ScGJtZFRkWE53Wlc1elpVSnZkVzVrWVhKcFpYTTZi'
    || 'blZzYkgwc2RHOG9hU2tzWlgxbWRXNWpkR2x2YmlCMGNDaGxMSFFzYmlsN2RtRnlJSEk5TXp4aGNtZDFiV1Z1ZEhNdWJHVnVaM1JvSmlaaGNtZDFiV1Z1ZEhO'
    || 'Yk0xMGhQVDEyYjJsa0lEQS9ZWEpuZFcxbGJuUnpXek5kT201MWJHdzdjbVYwZFhKdWV5UWtkSGx3Wlc5bU9sTmxMR3RsZVRweVBUMXVkV3hzUDI1MWJHdzZJ'
    || 'aUlyY2l4amFHbHNaSEpsYmpwbExHTnZiblJoYVc1bGNrbHVabTg2ZEN4cGJYQnNaVzFsYm5SaGRHbHZianB1ZlgxbWRXNWpkR2x2YmlCMFl5aGxLWHRwWmln'
    || 'aFpTbHlaWFIxY200Z1FuUTdaVDFsTGw5eVpXRmpkRWx1ZEdWeWJtRnNjenRsT250cFppaHViaWhsS1NFOVBXVjhmR1V1ZEdGbklUMDlNU2wwYUhKdmR5QkZj'
    || 'bkp2Y2loaEtERTNNQ2twTzNaaGNpQjBQV1U3Wkc5N2MzZHBkR05vS0hRdWRHRm5LWHRqWVhObElETTZkRDEwTG5OMFlYUmxUbTlrWlM1amIyNTBaWGgwTzJK'
    || 'eVpXRnJJR1U3WTJGelpTQXhPbWxtS0ZkbEtIUXVkSGx3WlNrcGUzUTlkQzV6ZEdGMFpVNXZaR1V1WDE5eVpXRmpkRWx1ZEdWeWJtRnNUV1Z0YjJsNlpXUk5a'
    || 'WEpuWldSRGFHbHNaRU52Ym5SbGVIUTdZbkpsWVdzZ1pYMTlkRDEwTG5KbGRIVnlibjEzYUdsc1pTaDBJVDA5Ym5Wc2JDazdkR2h5YjNjZ1JYSnliM0lvWVNn'
    || 'eE56RXBLWDFwWmlobExuUmhaejA5UFRFcGUzWmhjaUJ1UFdVdWRIbHdaVHRwWmloWFpTaHVLU2x5WlhSMWNtNGdUSFVvWlN4dUxIUXBmWEpsZEhWeWJpQjBm'
    || 'V1oxYm1OMGFXOXVJRzVqS0dVc2RDeHVMSElzYkN4cExHOHNZeXhrS1h0eVpYUjFjbTRnWlQxV2J5aHVMSElzSVRBc1pTeHNMR2tzYnl4akxHUXBMR1V1WTI5'
    || 'dWRHVjRkRDEwWXlodWRXeHNLU3h1UFdVdVkzVnljbVZ1ZEN4eVBVUmxLQ2tzYkQxS2RDaHVLU3hwUFZCMEtISXNiQ2tzYVM1allXeHNZbUZqYXoxMFB6OXVk'
    || 'V3hzTEV0MEtHNHNhU3hzS1N4bExtTjFjbkpsYm5RdWJHRnVaWE05YkN4S2JpaGxMR3dzY2lrc1VXVW9aU3h5S1N4bGZXWjFibU4wYVc5dUlIcHNLR1VzZEN4'
    || 'dUxISXBlM1poY2lCc1BYUXVZM1Z5Y21WdWRDeHBQVVJsS0Nrc2J6MUtkQ2hzS1R0eVpYUjFjbTRnYmoxMFl5aHVLU3gwTG1OdmJuUmxlSFE5UFQxdWRXeHNQ'
    || 'M1F1WTI5dWRHVjRkRDF1T25RdWNHVnVaR2x1WjBOdmJuUmxlSFE5Yml4MFBWQjBLR2tzYnlrc2RDNXdZWGxzYjJGa1BYdGxiR1Z0Wlc1ME9tVjlMSEk5Y2ow'
    || 'OVBYWnZhV1FnTUQ5dWRXeHNPbklzY2lFOVBXNTFiR3dtSmloMExtTmhiR3hpWVdOclBYSXBMR1U5UzNRb2JDeDBMRzhwTEdVaFBUMXVkV3hzSmlZb2RuUW9a'
    || 'U3hzTEc4c2FTa3NabXdvWlN4c0xHOHBLU3h2ZldaMWJtTjBhVzl1SUVSc0tHVXBlMmxtS0dVOVpTNWpkWEp5Wlc1MExDRmxMbU5vYVd4a0tYSmxkSFZ5YmlC'
    || 'dWRXeHNPM04zYVhSamFDaGxMbU5vYVd4a0xuUmhaeWw3WTJGelpTQTFPbkpsZEhWeWJpQmxMbU5vYVd4a0xuTjBZWFJsVG05a1pUdGtaV1poZFd4ME9uSmxk'
    || 'SFZ5YmlCbExtTm9hV3hrTG5OMFlYUmxUbTlrWlgxOVpuVnVZM1JwYjI0Z2NtTW9aU3gwS1h0cFppaGxQV1V1YldWdGIybDZaV1JUZEdGMFpTeGxJVDA5Ym5W'
    || 'c2JDWW1aUzVrWldoNVpISmhkR1ZrSVQwOWJuVnNiQ2w3ZG1GeUlHNDlaUzV5WlhSeWVVeGhibVU3WlM1eVpYUnllVXhoYm1VOWJpRTlQVEFtSm00OGREOXVP'
    || 'blI5ZldaMWJtTjBhVzl1SUVKdktHVXNkQ2w3Y21Nb1pTeDBLU3dvWlQxbExtRnNkR1Z5Ym1GMFpTa21KbkpqS0dVc2RDbDlablZ1WTNScGIyNGdibkFvS1h0'
    || 'eVpYUjFjbTRnYm5Wc2JIMTJZWElnYkdNOWRIbHdaVzltSUhKbGNHOXlkRVZ5Y205eVBUMGlablZ1WTNScGIyNGlQM0psY0c5eWRFVnljbTl5T21aMWJtTjBh'
    || 'Vzl1S0dVcGUyTnZibk52YkdVdVpYSnliM0lvWlNsOU8yWjFibU4wYVc5dUlGRnZLR1VwZTNSb2FYTXVYMmx1ZEdWeWJtRnNVbTl2ZEQxbGZVRnNMbkJ5YjNS'
    || 'dmRIbHdaUzV5Wlc1a1pYSTlVVzh1Y0hKdmRHOTBlWEJsTG5KbGJtUmxjajFtZFc1amRHbHZiaWhsS1h0MllYSWdkRDEwYUdsekxsOXBiblJsY201aGJGSnZi'
    || 'M1E3YVdZb2REMDlQVzUxYkd3cGRHaHliM2NnUlhKeWIzSW9ZU2cwTURrcEtUdDZiQ2hsTEhRc2JuVnNiQ3h1ZFd4c0tYMHNRV3d1Y0hKdmRHOTBlWEJsTG5W'
    || 'dWJXOTFiblE5VVc4dWNISnZkRzkwZVhCbExuVnViVzkxYm5ROVpuVnVZM1JwYjI0b0tYdDJZWElnWlQxMGFHbHpMbDlwYm5SbGNtNWhiRkp2YjNRN2FXWW9a'
    || 'U0U5UFc1MWJHd3BlM1JvYVhNdVgybHVkR1Z5Ym1Gc1VtOXZkRDF1ZFd4c08zWmhjaUIwUFdVdVkyOXVkR0ZwYm1WeVNXNW1ienRtYmlobWRXNWpkR2x2Ymln'
    || 'cGUzcHNLRzUxYkd3c1pTeHVkV3hzTEc1MWJHd3BmU2tzZEZ0VWRGMDliblZzYkgxOU8yWjFibU4wYVc5dUlFRnNLR1VwZTNSb2FYTXVYMmx1ZEdWeWJtRnNV'
    || 'bTl2ZEQxbGZVRnNMbkJ5YjNSdmRIbHdaUzUxYm5OMFlXSnNaVjl6WTJobFpIVnNaVWg1WkhKaGRHbHZiajFtZFc1amRHbHZiaWhsS1h0cFppaGxLWHQyWVhJ'
    || 'Z2REMGtjeWdwTzJVOWUySnNiMk5yWldSUGJqcHVkV3hzTEhSaGNtZGxkRHBsTEhCeWFXOXlhWFI1T25SOU8yWnZjaWgyWVhJZ2JqMHdPMjQ4VlhRdWJHVnVa'
    || 'M1JvSmlaMElUMDlNQ1ltZER4VmRGdHVYUzV3Y21sdmNtbDBlVHR1S3lzcE8xVjBMbk53YkdsalpTaHVMREFzWlNrc2JqMDlQVEFtSmtKektHVXBmWDA3Wm5W'
    || 'dVkzUnBiMjRnV1c4b1pTbDdjbVYwZFhKdUlTZ2haWHg4WlM1dWIyUmxWSGx3WlNFOVBURW1KbVV1Ym05a1pWUjVjR1VoUFQwNUppWmxMbTV2WkdWVWVYQmxJ'
    || 'VDA5TVRFcGZXWjFibU4wYVc5dUlFWnNLR1VwZTNKbGRIVnliaUVvSVdWOGZHVXVibTlrWlZSNWNHVWhQVDB4SmlabExtNXZaR1ZVZVhCbElUMDlPU1ltWlM1'
    || 'dWIyUmxWSGx3WlNFOVBURXhKaVlvWlM1dWIyUmxWSGx3WlNFOVBUaDhmR1V1Ym05a1pWWmhiSFZsSVQwOUlpQnlaV0ZqZEMxdGIzVnVkQzF3YjJsdWRDMTFi'
    || 'bk4wWVdKc1pTQWlLU2w5Wm5WdVkzUnBiMjRnYVdNb0tYdDlablZ1WTNScGIyNGdjbkFvWlN4MExHNHNjaXhzS1h0cFppaHNLWHRwWmloMGVYQmxiMllnY2ow'
    || 'OUltWjFibU4wYVc5dUlpbDdkbUZ5SUdrOWNqdHlQV1oxYm1OMGFXOXVLQ2w3ZG1GeUlHYzlSR3dvYnlrN2FTNWpZV3hzS0djcGZYMTJZWElnYnoxdVl5aDBM'
    || 'SElzWlN3d0xHNTFiR3dzSVRFc0lURXNJaUlzYVdNcE8zSmxkSFZ5YmlCbExsOXlaV0ZqZEZKdmIzUkRiMjUwWVdsdVpYSTlieXhsVzFSMFhUMXZMbU4xY25K'
    || 'bGJuUXNaSElvWlM1dWIyUmxWSGx3WlQwOVBUZy9aUzV3WVhKbGJuUk9iMlJsT21VcExHWnVLQ2tzYjMxbWIzSW9PMnc5WlM1c1lYTjBRMmhwYkdRN0tXVXVj'
    || 'bVZ0YjNabFEyaHBiR1FvYkNrN2FXWW9kSGx3Wlc5bUlISTlQU0ptZFc1amRHbHZiaUlwZTNaaGNpQmpQWEk3Y2oxbWRXNWpkR2x2YmlncGUzWmhjaUJuUFVS'
    || 'c0tHUXBPMk11WTJGc2JDaG5LWDE5ZG1GeUlHUTlWbThvWlN3d0xDRXhMRzUxYkd3c2JuVnNiQ3doTVN3aE1Td2lJaXhwWXlrN2NtVjBkWEp1SUdVdVgzSmxZ'
    || 'V04wVW05dmRFTnZiblJoYVc1bGNqMWtMR1ZiVkhSZFBXUXVZM1Z5Y21WdWRDeGtjaWhsTG01dlpHVlVlWEJsUFQwOU9EOWxMbkJoY21WdWRFNXZaR1U2WlNr'
    || 'c1ptNG9ablZ1WTNScGIyNG9LWHQ2YkNoMExHUXNiaXh5S1gwcExHUjlablZ1WTNScGIyNGdWV3dvWlN4MExHNHNjaXhzS1h0MllYSWdhVDF1TGw5eVpXRmpk'
    || 'Rkp2YjNSRGIyNTBZV2x1WlhJN2FXWW9hU2w3ZG1GeUlHODlhVHRwWmloMGVYQmxiMllnYkQwOUltWjFibU4wYVc5dUlpbDdkbUZ5SUdNOWJEdHNQV1oxYm1O'
    || 'MGFXOXVLQ2w3ZG1GeUlHUTlSR3dvYnlrN1l5NWpZV3hzS0dRcGZYMTZiQ2gwTEc4c1pTeHNLWDFsYkhObElHODljbkFvYml4MExHVXNiQ3h5S1R0eVpYUjFj'
    || 'bTRnUkd3b2J5bDlWWE05Wm5WdVkzUnBiMjRvWlNsN2MzZHBkR05vS0dVdWRHRm5LWHRqWVhObElETTZkbUZ5SUhROVpTNXpkR0YwWlU1dlpHVTdhV1lvZEM1'
    || 'amRYSnlaVzUwTG0xbGJXOXBlbVZrVTNSaGRHVXVhWE5FWldoNVpISmhkR1ZrS1h0MllYSWdiajFhYmloMExuQmxibVJwYm1kTVlXNWxjeWs3YmlFOVBUQW1K'
    || 'aWh0YVNoMExHNThNU2tzVVdVb2RDeDJaU2dwS1N3b1dpWTJLVDA5UFRBbUppZ2tiajEyWlNncEt6VXdNQ3hSZENncEtTbDlZbkpsWVdzN1kyRnpaU0F4TXpw'
    || 'bWJpaG1kVzVqZEdsdmJpZ3BlM1poY2lCeVBVMTBLR1VzTVNrN2FXWW9jaUU5UFc1MWJHd3BlM1poY2lCc1BVUmxLQ2s3ZG5Rb2NpeGxMREVzYkNsOWZTa3NR'
    || 'bThvWlN3eEtYMTlMSFpwUFdaMWJtTjBhVzl1S0dVcGUybG1LR1V1ZEdGblBUMDlNVE1wZTNaaGNpQjBQVTEwS0dVc01UTTBNakUzTnpJNEtUdHBaaWgwSVQw'
    || 'OWJuVnNiQ2w3ZG1GeUlHNDlSR1VvS1R0MmRDaDBMR1VzTVRNME1qRTNOekk0TEc0cGZVSnZLR1VzTVRNME1qRTNOekk0S1gxOUxFaHpQV1oxYm1OMGFXOXVL'
    || 'R1VwZTJsbUtHVXVkR0ZuUFQwOU1UTXBlM1poY2lCMFBVcDBLR1VwTEc0OVRYUW9aU3gwS1R0cFppaHVJVDA5Ym5Wc2JDbDdkbUZ5SUhJOVJHVW9LVHQyZENo'
    || 'dUxHVXNkQ3h5S1gxQ2J5aGxMSFFwZlgwc0pITTlablZ1WTNScGIyNG9LWHR5WlhSMWNtNGdibVY5TEZkelBXWjFibU4wYVc5dUtHVXNkQ2w3ZG1GeUlHNDli'
    || 'bVU3ZEhKNWUzSmxkSFZ5YmlCdVpUMWxMSFFvS1gxbWFXNWhiR3g1ZTI1bFBXNTlmU3gxYVQxbWRXNWpkR2x2YmlobExIUXNiaWw3YzNkcGRHTm9LSFFwZTJO'
    || 'aGMyVWlhVzV3ZFhRaU9tbG1LR1ZwS0dVc2Jpa3NkRDF1TG01aGJXVXNiaTUwZVhCbFBUMDlJbkpoWkdsdklpWW1kQ0U5Ym5Wc2JDbDdabTl5S0c0OVpUdHVM'
    || 'bkJoY21WdWRFNXZaR1U3S1c0OWJpNXdZWEpsYm5ST2IyUmxPMlp2Y2lodVBXNHVjWFZsY25sVFpXeGxZM1J2Y2tGc2JDZ2lhVzV3ZFhSYmJtRnRaVDBpSzBw'
    || 'VFQwNHVjM1J5YVc1bmFXWjVLQ0lpSzNRcEt5ZGRXM1I1Y0dVOUluSmhaR2x2SWwwbktTeDBQVEE3ZER4dUxteGxibWQwYUR0MEt5c3BlM1poY2lCeVBXNWJk'
    || 'RjA3YVdZb2NpRTlQV1VtSm5JdVptOXliVDA5UFdVdVptOXliU2w3ZG1GeUlHdzlibXdvY2lrN2FXWW9JV3dwZEdoeWIzY2dSWEp5YjNJb1lTZzVNQ2twTzJa'
    || 'ektISXBMR1ZwS0hJc2JDbDlmWDFpY21WaGF6dGpZWE5sSW5SbGVIUmhjbVZoSWpwbmN5aGxMRzRwTzJKeVpXRnJPMk5oYzJVaWMyVnNaV04wSWpwMFBXNHVk'
    || 'bUZzZFdVc2RDRTliblZzYkNZbWVXNG9aU3doSVc0dWJYVnNkR2x3YkdVc2RDd2hNU2w5ZlN4cWN6MUJieXhVY3oxbWJqdDJZWElnYkhBOWUzVnphVzVuUTJ4'
    || 'cFpXNTBSVzUwY25sUWIybHVkRG9oTVN4RmRtVnVkSE02VzJoeUxFTnVMRzVzTEVWekxFNXpMRUZ2WFgwc1EzSTllMlpwYm1SR2FXSmxja0o1U0c5emRFbHVj'
    || 'M1JoYm1ObE9uSnVMR0oxYm1Sc1pWUjVjR1U2TUN4MlpYSnphVzl1T2lJeE9DNHpMakVpTEhKbGJtUmxjbVZ5VUdGamEyRm5aVTVoYldVNkluSmxZV04wTFdS'
    || 'dmJTSjlMR2x3UFh0aWRXNWtiR1ZVZVhCbE9rTnlMbUoxYm1Sc1pWUjVjR1VzZG1WeWMybHZianBEY2k1MlpYSnphVzl1TEhKbGJtUmxjbVZ5VUdGamEyRm5a'
    || 'VTVoYldVNlEzSXVjbVZ1WkdWeVpYSlFZV05yWVdkbFRtRnRaU3h5Wlc1a1pYSmxja052Ym1acFp6cERjaTV5Wlc1a1pYSmxja052Ym1acFp5eHZkbVZ5Y21s'
    || 'a1pVaHZiMnRUZEdGMFpUcHVkV3hzTEc5MlpYSnlhV1JsU0c5dmExTjBZWFJsUkdWc1pYUmxVR0YwYURwdWRXeHNMRzkyWlhKeWFXUmxTRzl2YTFOMFlYUmxV'
    || 'bVZ1WVcxbFVHRjBhRHB1ZFd4c0xHOTJaWEp5YVdSbFVISnZjSE02Ym5Wc2JDeHZkbVZ5Y21sa1pWQnliM0J6UkdWc1pYUmxVR0YwYURwdWRXeHNMRzkyWlhK'
    || 'eWFXUmxVSEp2Y0hOU1pXNWhiV1ZRWVhSb09tNTFiR3dzYzJWMFJYSnliM0pJWVc1a2JHVnlPbTUxYkd3c2MyVjBVM1Z6Y0dWdWMyVklZVzVrYkdWeU9tNTFi'
    || 'R3dzYzJOb1pXUjFiR1ZWY0dSaGRHVTZiblZzYkN4amRYSnlaVzUwUkdsemNHRjBZMmhsY2xKbFpqcHZaUzVTWldGamRFTjFjbkpsYm5SRWFYTndZWFJqYUdW'
    || 'eUxHWnBibVJJYjNOMFNXNXpkR0Z1WTJWQ2VVWnBZbVZ5T21aMWJtTjBhVzl1S0dVcGUzSmxkSFZ5YmlCbFBVMXpLR1VwTEdVOVBUMXVkV3hzUDI1MWJHdzZa'
    || 'UzV6ZEdGMFpVNXZaR1Y5TEdacGJtUkdhV0psY2tKNVNHOXpkRWx1YzNSaGJtTmxPa055TG1acGJtUkdhV0psY2tKNVNHOXpkRWx1YzNSaGJtTmxmSHh1Y0N4'
    || 'bWFXNWtTRzl6ZEVsdWMzUmhibU5sYzBadmNsSmxabkpsYzJnNmJuVnNiQ3h6WTJobFpIVnNaVkpsWm5KbGMyZzZiblZzYkN4elkyaGxaSFZzWlZKdmIzUTZi'
    || 'blZzYkN4elpYUlNaV1p5WlhOb1NHRnVaR3hsY2pwdWRXeHNMR2RsZEVOMWNuSmxiblJHYVdKbGNqcHVkV3hzTEhKbFkyOXVZMmxzWlhKV1pYSnphVzl1T2lJ'
    || 'eE9DNHpMakV0Ym1WNGRDMW1NVE16T0dZNE1EZ3dMVEl3TWpRd05ESTJJbjA3YVdZb2RIbHdaVzltSUY5ZlVrVkJRMVJmUkVWV1ZFOVBURk5mUjB4UFFrRk1Y'
    || 'MGhQVDB0Zlh6d2lkU0lwZTNaaGNpQkliRDFmWDFKRlFVTlVYMFJGVmxSUFQweFRYMGRNVDBKQlRGOUlUMDlMWDE4N2FXWW9JVWhzTG1selJHbHpZV0pzWldR'
    || 'bUpraHNMbk4xY0hCdmNuUnpSbWxpWlhJcGRISjVlMEZ5UFVoc0xtbHVhbVZqZENocGNDa3NkM1E5U0d4OVkyRjBZMmg3ZlgxeVpYUjFjbTRnUVdVdVgxOVRS'
    || 'VU5TUlZSZlNVNVVSVkpPUVV4VFgwUlBYMDVQVkY5VlUwVmZUMUpmV1U5VlgxZEpURXhmUWtWZlJrbFNSVVE5YkhBc1FXVXVZM0psWVhSbFVHOXlkR0ZzUFda'
    || 'MWJtTjBhVzl1S0dVc2RDbDdkbUZ5SUc0OU1qeGhjbWQxYldWdWRITXViR1Z1WjNSb0ppWmhjbWQxYldWdWRITmJNbDBoUFQxMmIybGtJREEvWVhKbmRXMWxi'
    || 'blJ6V3pKZE9tNTFiR3c3YVdZb0lWbHZLSFFwS1hSb2NtOTNJRVZ5Y205eUtHRW9NakF3S1NrN2NtVjBkWEp1SUhSd0tHVXNkQ3h1ZFd4c0xHNHBmU3hCWlM1'
    || 'amNtVmhkR1ZTYjI5MFBXWjFibU4wYVc5dUtHVXNkQ2w3YVdZb0lWbHZLR1VwS1hSb2NtOTNJRVZ5Y205eUtHRW9Nams1S1NrN2RtRnlJRzQ5SVRFc2NqMGlJ'
    || 'aXhzUFd4ak8zSmxkSFZ5YmlCMElUMXVkV3hzSmlZb2RDNTFibk4wWVdKc1pWOXpkSEpwWTNSTmIyUmxQVDA5SVRBbUppaHVQU0V3S1N4MExtbGtaVzUwYVda'
    || 'cFpYSlFjbVZtYVhnaFBUMTJiMmxrSURBbUppaHlQWFF1YVdSbGJuUnBabWxsY2xCeVpXWnBlQ2tzZEM1dmJsSmxZMjkyWlhKaFlteGxSWEp5YjNJaFBUMTJi'
    || 'MmxrSURBbUppaHNQWFF1YjI1U1pXTnZkbVZ5WVdKc1pVVnljbTl5S1Nrc2REMVdieWhsTERFc0lURXNiblZzYkN4dWRXeHNMRzRzSVRFc2NpeHNLU3hsVzFS'
    || 'MFhUMTBMbU4xY25KbGJuUXNaSElvWlM1dWIyUmxWSGx3WlQwOVBUZy9aUzV3WVhKbGJuUk9iMlJsT21VcExHNWxkeUJSYnloMEtYMHNRV1V1Wm1sdVpFUlBU'
    || 'VTV2WkdVOVpuVnVZM1JwYjI0b1pTbDdhV1lvWlQwOWJuVnNiQ2x5WlhSMWNtNGdiblZzYkR0cFppaGxMbTV2WkdWVWVYQmxQVDA5TVNseVpYUjFjbTRnWlR0'
    || 'MllYSWdkRDFsTGw5eVpXRmpkRWx1ZEdWeWJtRnNjenRwWmloMFBUMDlkbTlwWkNBd0tYUm9jbTkzSUhSNWNHVnZaaUJsTG5KbGJtUmxjajA5SW1aMWJtTjBh'
    || 'Vzl1SWo5RmNuSnZjaWhoS0RFNE9Da3BPaWhsUFU5aWFtVmpkQzVyWlhsektHVXBMbXB2YVc0b0lpd2lLU3hGY25KdmNpaGhLREkyT0N4bEtTa3BPM0psZEhW'
    || 'eWJpQmxQVTF6S0hRcExHVTlaVDA5UFc1MWJHdy9iblZzYkRwbExuTjBZWFJsVG05a1pTeGxmU3hCWlM1bWJIVnphRk41Ym1NOVpuVnVZM1JwYjI0b1pTbDdj'
    || 'bVYwZFhKdUlHWnVLR1VwZlN4QlpTNW9lV1J5WVhSbFBXWjFibU4wYVc5dUtHVXNkQ3h1S1h0cFppZ2hSbXdvZENrcGRHaHliM2NnUlhKeWIzSW9ZU2d5TURB'
    || 'cEtUdHlaWFIxY200Z1ZXd29iblZzYkN4bExIUXNJVEFzYmlsOUxFRmxMbWg1WkhKaGRHVlNiMjkwUFdaMWJtTjBhVzl1S0dVc2RDeHVLWHRwWmlnaFdXOG9a'
    || 'U2twZEdoeWIzY2dSWEp5YjNJb1lTZzBNRFVwS1R0MllYSWdjajF1SVQxdWRXeHNKaVp1TG1oNVpISmhkR1ZrVTI5MWNtTmxjM3g4Ym5Wc2JDeHNQU0V4TEdr'
    || 'OUlpSXNiejFzWXp0cFppaHVJVDF1ZFd4c0ppWW9iaTUxYm5OMFlXSnNaVjl6ZEhKcFkzUk5iMlJsUFQwOUlUQW1KaWhzUFNFd0tTeHVMbWxrWlc1MGFXWnBa'
    || 'WEpRY21WbWFYZ2hQVDEyYjJsa0lEQW1KaWhwUFc0dWFXUmxiblJwWm1sbGNsQnlaV1pwZUNrc2JpNXZibEpsWTI5MlpYSmhZbXhsUlhKeWIzSWhQVDEyYjJs'
    || 'a0lEQW1KaWh2UFc0dWIyNVNaV052ZG1WeVlXSnNaVVZ5Y205eUtTa3NkRDF1WXloMExHNTFiR3dzWlN3eExHNC9QMjUxYkd3c2JDd2hNU3hwTEc4cExHVmJW'
    || 'SFJkUFhRdVkzVnljbVZ1ZEN4a2NpaGxLU3h5S1dadmNpaGxQVEE3WlR4eUxteGxibWQwYUR0bEt5c3BiajF5VzJWZExHdzliaTVmWjJWMFZtVnljMmx2Yml4'
    || 'c1BXd29iaTVmYzI5MWNtTmxLU3gwTG0xMWRHRmliR1ZUYjNWeVkyVkZZV2RsY2toNVpISmhkR2x2YmtSaGRHRTlQVzUxYkd3L2RDNXRkWFJoWW14bFUyOTFj'
    || 'bU5sUldGblpYSkllV1J5WVhScGIyNUVZWFJoUFZ0dUxHeGRPblF1YlhWMFlXSnNaVk52ZFhKalpVVmhaMlZ5U0hsa2NtRjBhVzl1UkdGMFlTNXdkWE5vS0c0'
    || 'c2JDazdjbVYwZFhKdUlHNWxkeUJCYkNoMEtYMHNRV1V1Y21WdVpHVnlQV1oxYm1OMGFXOXVLR1VzZEN4dUtYdHBaaWdoUm13b2RDa3BkR2h5YjNjZ1JYSnli'
    || 'M0lvWVNneU1EQXBLVHR5WlhSMWNtNGdWV3dvYm5Wc2JDeGxMSFFzSVRFc2JpbDlMRUZsTG5WdWJXOTFiblJEYjIxd2IyNWxiblJCZEU1dlpHVTlablZ1WTNS'
    || 'cGIyNG9aU2w3YVdZb0lVWnNLR1VwS1hSb2NtOTNJRVZ5Y205eUtHRW9OREFwS1R0eVpYUjFjbTRnWlM1ZmNtVmhZM1JTYjI5MFEyOXVkR0ZwYm1WeVB5aG1i'
    || 'aWhtZFc1amRHbHZiaWdwZTFWc0tHNTFiR3dzYm5Wc2JDeGxMQ0V4TEdaMWJtTjBhVzl1S0NsN1pTNWZjbVZoWTNSU2IyOTBRMjl1ZEdGcGJtVnlQVzUxYkd3'
    || 'c1pWdFVkRjA5Ym5Wc2JIMHBmU2tzSVRBcE9pRXhmU3hCWlM1MWJuTjBZV0pzWlY5aVlYUmphR1ZrVlhCa1lYUmxjejFCYnl4QlpTNTFibk4wWVdKc1pWOXla'
    || 'VzVrWlhKVGRXSjBjbVZsU1c1MGIwTnZiblJoYVc1bGNqMW1kVzVqZEdsdmJpaGxMSFFzYml4eUtYdHBaaWdoUm13b2Jpa3BkR2h5YjNjZ1JYSnliM0lvWVNn'
    || 'eU1EQXBLVHRwWmlobFBUMXVkV3hzZkh4bExsOXlaV0ZqZEVsdWRHVnlibUZzY3owOVBYWnZhV1FnTUNsMGFISnZkeUJGY25KdmNpaGhLRE00S1NrN2NtVjBk'
    || 'WEp1SUZWc0tHVXNkQ3h1TENFeExISXBmU3hCWlM1MlpYSnphVzl1UFNJeE9DNHpMakV0Ym1WNGRDMW1NVE16T0dZNE1EZ3dMVEl3TWpRd05ESTJJaXhCWlgx'
    || 'MllYSWdaWE03Wm5WdVkzUnBiMjRnY0dNb0tYdHBaaWhsY3lseVpYUjFjbTRnVVd3dVpYaHdiM0owY3p0bGN6MHhPMloxYm1OMGFXOXVJSFVvS1h0cFppZ2hL'
    || 'SFI1Y0dWdlppQmZYMUpGUVVOVVgwUkZWbFJQVDB4VFgwZE1UMEpCVEY5SVQwOUxYMTgrSW5VaWZIeDBlWEJsYjJZZ1gxOVNSVUZEVkY5RVJWWlVUMDlNVTE5'
    || 'SFRFOUNRVXhmU0U5UFMxOWZMbU5vWldOclJFTkZJVDBpWm5WdVkzUnBiMjRpS1NsMGNubDdYMTlTUlVGRFZGOUVSVlpVVDA5TVUxOUhURTlDUVV4ZlNFOVBT'
    || 'MTlmTG1Ob1pXTnJSRU5GS0hVcGZXTmhkR05vS0dZcGUyTnZibk52YkdVdVpYSnliM0lvWmlsOWZYSmxkSFZ5YmlCMUtDa3NVV3d1Wlhod2IzSjBjejFtWXln'
    || 'cExGRnNMbVY0Y0c5eWRITjlkbUZ5SUhSek8yWjFibU4wYVc5dUlHaGpLQ2w3YVdZb2RITXBjbVYwZFhKdUlFeHlPM1J6UFRFN2RtRnlJSFU5Y0dNb0tUdHla'
    || 'WFIxY200Z1RISXVZM0psWVhSbFVtOXZkRDExTG1OeVpXRjBaVkp2YjNRc1RISXVhSGxrY21GMFpWSnZiM1E5ZFM1b2VXUnlZWFJsVW05dmRDeE1jbjEyWVhJ'
    || 'Z2JXTTlhR01vS1R0amIyNXpkQ0IyWXowaVgxOU5SVkpEU0VGT1ZGOUVRVlJCWDE4aUxHZGpQWHRqYjI1MFpYaDBPbnQ5TEhCaGJtVnNjenA3ZlN4bVlYUmhi'
    || 'RG9pVG04Z1pHRjBZU0J3WVhsc2IyRmtJSGRoY3lCcGJtcGxZM1JsWkM0Z1ZHaHBjeUJpZFdsc1pDQnZaaUIwYUdVZ1lYQndJR2x6SUdKeWIydGxianNnY21V'
    || 'dGNuVnVJR2hoY201bGMzTXVZblZ1Wkd4bElHRnVaQ0J5WldKMWFXeGtMaUo5TzJaMWJtTjBhVzl1SUhsaktIVTlkbU1wZTJOdmJuTjBJR1k5ZDJsdVpHOTNX'
    || 'M1ZkTzJsbUtDRm1mSHgwZVhCbGIyWWdaaUU5SW05aWFtVmpkQ0lwY21WMGRYSnVJR2RqTzJOdmJuTjBJR0U5Wmp0eVpYUjFjbTU3WTI5dWRHVjRkRHBoTG1O'
    || 'dmJuUmxlSFEvUDN0OUxIQmhibVZzY3pwaExuQmhibVZzY3o4L2UzMHNabUYwWVd3NllTNW1ZWFJoYkN4amRYTjBiMjFwZW1GMGFXOXVPbUV1WTNWemRHOXRh'
    || 'WHBoZEdsdmJpeGpkWE4wYjIxcGVtRjBhVzl1WDJWeWNtOXlPbUV1WTNWemRHOXRhWHBoZEdsdmJsOWxjbkp2Y2l4dVlYWnBaMkYwYVc5dU9tRXVibUYyYVdk'
    || 'aGRHbHZibjE5Wm5WdVkzUnBiMjRnZG00b2RTbDdjbVYwZFhKdUlTRjFKaVlpWlhKeWIzSWlhVzRnZFgxbWRXNWpkR2x2YmlCNFl5aDFLWHR5WlhSMWNtNGdk'
    || 'U1ltSW5KdmQzTWlhVzRnZFNZbWRTNTBjblZ1WTJGMFpXUS9kUzUwY25WdVkyRjBaV1E2TUgxbWRXNWpkR2x2YmlCbmJpaDFLWHR5WlhSMWNtNGhkWHg4SVNn'
    || 'aVpYSnliM0lpYVc0Z2RTay9JVEU2TDJSdlpYTWdibTkwSUdWNGFYTjBJRzl5SUc1dmRDQmhkWFJvYjNKcGVtVmtMMmt1ZEdWemRDaDFMbVZ5Y205eUtYMW1k'
    || 'VzVqZEdsdmJpQmxkQ2gxTEdZcGUyTnZibk4wSUdFOWRTNXdZVzVsYkhOYlpsMDdjbVYwZFhKdUlHRW1KaUp5YjNkekltbHVJR0UvWVM1eWIzZHpPbHRkZlda'
    || 'MWJtTjBhVzl1SUU1MEtIVXBlMmxtS0hSNWNHVnZaaUIxUFQwaWJuVnRZbVZ5SWlseVpYUjFjbTRnVG5WdFltVnlMbWx6Um1sdWFYUmxLSFVwUDNVNmJuVnNi'
    || 'RHRwWmloMGVYQmxiMllnZFNFOUluTjBjbWx1WnlJcGNtVjBkWEp1SUc1MWJHdzdZMjl1YzNRZ1pqMTFMblJ5YVcwb0tUdHBaaWhtUFQwOUlpSjhmQ0V2WGxz'
    || 'ckxWMC9LRnhrSzF3dVAxeGtLbnhjTGx4a0t5a29XMlZGWFZzckxWMC9YR1FyS1Q4a0x5NTBaWE4wS0dZcEtYSmxkSFZ5YmlCdWRXeHNPMk52Ym5OMElHRTlU'
    || 'blZ0WW1WeUtHWXBPM0psZEhWeWJpQk9kVzFpWlhJdWFYTkdhVzVwZEdVb1lTay9ZVHB1ZFd4c2ZXWjFibU4wYVc5dUlHVmxLSFVwZTJsbUtIVTlQVzUxYkd4'
    || 'OGZIVTlQVDBpSWlseVpYUjFjbTRpNG9DVUlqdGpiMjV6ZENCbVBVNTBLSFVwTzJsbUtHWTlQVDF1ZFd4c0tYSmxkSFZ5YmlCVGRISnBibWNvZFNrN2FXWW9a'
    || 'ajA5UFRBcGNtVjBkWEp1SWpBaU8yTnZibk4wSUdFOVRXRjBhQzVoWW5Nb1ppazdhV1lvWVR3MVpTMDBLWEpsZEhWeWJpQm1QREEvSWo0Z0xUQXVNREF4SWpv'
    || 'aVBDQXdMakF3TVNJN2JHVjBJSGc3Y21WMGRYSnVJR0UrUFRGbE16OTRQVEE2WVQ0OU1UQXdQM2c5TVRwaFBqMHhQM2c5TWpwNFBUTXNaaTUwYjB4dlkyRnNa'
    || 'Vk4wY21sdVp5Z2laVzR0VlZNaUxIdHRhVzVwYlhWdFJuSmhZM1JwYjI1RWFXZHBkSE02TUN4dFlYaHBiWFZ0Um5KaFkzUnBiMjVFYVdkcGRITTZlSDBwZlda'
    || 'MWJtTjBhVzl1SUZKeUtIVXNaajB4S1h0amIyNXpkQ0JoUFU1MEtIVXBPM0psZEhWeWJpQmhQVDA5Ym5Wc2JEOGk0b0NVSWpwaExuUnZURzlqWVd4bFUzUnlh'
    || 'VzVuS0NKbGJpMVZVeUlzZTIxcGJtbHRkVzFHY21GamRHbHZia1JwWjJsMGN6b3dMRzFoZUdsdGRXMUdjbUZqZEdsdmJrUnBaMmwwY3pwbWZTa3JJaVVpZlda'
    || 'MWJtTjBhVzl1SUhkaktIVXBlMk52Ym5OMElHWTlVM1J5YVc1bktIVS9QeUlpS1M1MGIxVndjR1Z5UTJGelpTZ3BMblJ5YVcwb0tUdHlaWFIxY200Z1pqMDlQ'
    || 'U0pOUlZRaWZIeG1QVDA5SWs1UFZGOU5SVlFpZkh4bVBUMDlJazR2UVNJL1pqb2lVRVZPUkVsT1J5SjlZMjl1YzNRZ2RYUTlkVDArZFQwOWJuVnNiRDhpSWpw'
    || 'VGRISnBibWNvZFNrN1puVnVZM1JwYjI0Z2JuTW9kU2w3Y21WMGRYSnVJR1YwS0hVc0luQnZZMTl6WTI5eVpXTmhjbVFpS1M1dFlYQW9aajArS0h0amIyUmxP'
    || 'blYwS0dZdVEwOUVSU2tzYkdGaVpXdzZkWFFvWmk1TVFVSkZUQ2tzZDJoNU9uVjBLR1l1VjBoWlgwbFVYMDFCVkZSRlVsTXBMSFJoY21kbGREcG1MbFJCVWtk'
    || 'RlZEOC9iblZzYkN4aFkzUjFZV3c2Wmk1QlExUlZRVXcvUDI1MWJHd3NkVzVwZEhNNmRYUW9aaTVWVGtsVVV5a3NZMjl0Y0dGeVpUcDFkQ2htTGtOUFRWQkJV'
    || 'a1VwTEdKaGMybHpPblYwS0dZdVFrRlRTVk1wTEdSbGNtbDJZWFJwYjI0NmRYUW9aaTVVUVZKSFJWUmZSRVZTU1ZaQlZFbFBUaWtzYzNSaGRHVTZkMk1vWmk1'
    || 'VFZFRlVSU2tzZDJoNVRtOTBPblYwS0dZdVYwaFpYMDVQVkY5RlZrRk1WVUZVUlVRcExISmxjMjlzZG1WelYyaGxianAxZENobUxsSkZVMDlNVmtWVFgxZElS'
    || 'VTRwTEdGeWFYUm9iV1YwYVdNNmRYUW9aaTVCVWtsVVNFMUZWRWxES1N4amIyMXdZWEpoWW1sc2FYUjVPblYwS0dZdVEwOU5VRUZTUVVKSlRFbFVXU2w5S1Ns'
    || 'OVpuVnVZM1JwYjI0Z1UyTW9kU2w3WTI5dWMzUWdaajExTG5CaGJtVnNjeTV3YjJOZmMyTnZjbVZqWVhKa0xHRTlibk1vZFNrN2FXWW9kbTRvWmlrcGNtVjBk'
    || 'WEp1ZTIxbGREb3dMRzV2ZEUxbGREb3dMSEJsYm1ScGJtYzZNQ3h1WVRvd0xITmpiM0psWkRvd0xHaGxZV1JzYVc1bE9pTGlnSlFpTEhabGNtUnBZM1E2SWs1'
    || 'UFZGOVNWVTRpTEhKbFlXUlVhR2x6T21kdUtHWXBQeUpVYUdVZ2MyTnZjbVZqWVhKa0lIWnBaWGR6SUhkbGNtVWdibTkwSUdKMWFXeDBJR0o1SUhSb2FYTWdj'
    || 'blZ1TENCdmNpQjBhR2x6SUhKdmJHVWdZMkZ1Ym05MElITmxaU0IwYUdWdExpQlRibTkzWm14aGEyVWdaRzlsY3lCdWIzUWdaR2x6ZEdsdVozVnBjMmdnZEdo'
    || 'bElIUjNieTRpT2lKVWFHVWdjMk52Y21WallYSmtJSEYxWlhKNUlHWmhhV3hsWkN3Z2MyOGdibTkwYUdsdVp5Qm9aWEpsSUdseklITmpiM0psWkM0aUxIVnVZ'
    || 'WFpoYVd4aFlteGxPbVl1WlhKeWIzSjlPMk52Ym5OMElIZzlZUzVtYVd4MFpYSW9TRDArU0M1emRHRjBaVDA5UFNKTlJWUWlLUzVzWlc1bmRHZ3NUajFoTG1a'
    || 'cGJIUmxjaWhJUFQ1SUxuTjBZWFJsUFQwOUlrNVBWRjlOUlZRaUtTNXNaVzVuZEdnc1F6MWhMbVpwYkhSbGNpaElQVDVJTG5OMFlYUmxQVDA5SWxCRlRrUkpU'
    || 'a2NpS1M1c1pXNW5kR2dzZVQxaExtWnBiSFJsY2loSVBUNUlMbk4wWVhSbFBUMDlJazR2UVNJcExteGxibWQwYUN4ZlBXRXViR1Z1WjNSb0xYa3NkejFmUFQw'
    || 'OU1EOGlUazlVWDFKVlRpSTZUajR3UHlKT1QxUmZUVVZVSWpwNFBUMDlNRDhpVUVWT1JFbE9SeUk2UXo0d1B5Sk5SVlJmVjBsVVNGOVFSVTVFU1U1SElqb2lU'
    || 'VVZVSWl4Q1BXVjBLSFVzSW5CdlkxOTJaWEprYVdOMElpbGJNRjBzVEQxQ1AxTjBjbWx1WnloQ0xsWkZVa1JKUTFRL1B5SWlLVG9pSWl4QlBTRWhUQ1ltVENF'
    || 'OVBYYzdjbVYwZFhKdWUyMWxkRHA0TEc1dmRFMWxkRHBPTEhCbGJtUnBibWM2UXl4dVlUcDVMSE5qYjNKbFpEcGZMR2hsWVdSc2FXNWxPbDg5UFQwd1B5SnVi'
    || 'M1FnYzJOdmNtVmtJanBnSkh0NGZTOGtlMTk5SUcxbGRHQXNkbVZ5WkdsamREcDNMSEpsWVdSVWFHbHpPa0UvWUZSb1pTQnpZMjl5WldOaGNtUWdjbTkzY3lC'
    || 'aGJtUWdkR2hsSUhKdmJHd3RkWEFnZG1sbGR5QmthWE5oWjNKbFpTQW9jbTkzY3lCellYa2dKSHQzZlN3Z1ZsOVFUME5mVmtWU1JFbERWQ0J6WVhseklDUjdU'
    || 'SDBwTGlCVWNuVnpkQ0J1WldsMGFHVnlJSFZ1ZEdsc0lIUm9ZWFFnYVhNZ1pYaHdiR0ZwYm1Wa0xtQTZRajlUZEhKcGJtY29RaTVTUlVGRVgxUklTVk0vUHlJ'
    || 'aUtUb2lJbjE5WTI5dWMzUWdSMnc5V3lKRVNWTkRUMVpGVWlJc0lreEpUVWxVUlVRaUxDSlFVazlFVlVOVVNVOU9JbDBzWDJNOWUwUkpVME5QVmtWU09pSkVh'
    || 'WE5qYjNabGNua2lMRXhKVFVsVVJVUTZJa3hwYldsMFpXUWdjblZ1SWl4UVVrOUVWVU5VU1U5T09pSlFjbTlrZFdOMGFXOXVJbjBzYTJNOWUwUkpVME5QVmtW'
    || 'U09pSlNaV0ZrY3lCMGFHVWdZV05qYjNWdWRDQmhibVFnY21Wd2IzSjBjeUIzYUdGMElHbDBJR1p2ZFc1a0xpQkJibmwwYUdsdVp5QnlaV04xY25KcGJtY2dh'
    || 'WE1nWTNKbFlYUmxaQ3dnY21WbWNtVnphR1ZrSUc5dVkyVWdjMjhnYVhSeklHTnZjM1FnWTJGdUlHSmxJRzFsWVhOMWNtVmtMQ0IwYUdWdUlITjFjM0JsYm1S'
    || 'bFpDNGlMRXhKVFVsVVJVUTZJbFJvWlNCellXMWxJR0oxYVd4a0lHOXVJR0Z1SUdsemIyeGhkR1ZrSUhkaGNtVm9iM1Z6WlNCM2FYUm9JR0VnY21WemIzVnlZ'
    || 'MlVnYlc5dWFYUnZjaUJ2ZG1WeUlHbDBMQ0J6YnlCMGFHVWdZM0psWkdsMGN5QnBkQ0JpZFhKdWN5QmhjbVVnWVhSMGNtbGlkWFJoWW14bElHRnVaQ0JqWVc0'
    || 'Z1ltVWdjbVZoWkNCaVlXTnJJR1p5YjIwZ2JXVjBaWEpwYm1jdUlGUm9hWE1nYVhNZ2RHaGxJRzl1YkhrZ2NHaGhjMlVnZEdoaGRDQndjbTlrZFdObGN5QmhJ'
    || 'RzFsWVhOMWNtVmtJRzUxYldKbGNpNGlMRkJTVDBSVlExUkpUMDQ2SWtaMWJHd2djMk52Y0dVc0lHRnVaQ0IwYUdVZ2NtVmpkWEp5YVc1bklHOWlhbVZqZEhN'
    || 'Z1lYSmxJR3hsWm5RZ2NuVnVibWx1Wnk0Z1FXUmtjeUIwYUdVZ2IzQmxjbUYwYVc5dVlXd2dablZ5Ym1sMGRYSmxJR0VnY0d4aGRHWnZjbTBnZEdWaGJTQmxl'
    || 'SEJsWTNSek9pQnRiMjVwZEc5eUxDQmlkV1JuWlhRc0lHOWlhbVZqZENCMFlXZHpMQ0JsY25KdmNpQnViM1JwWm1sallYUnBiMjRzSUhKbFpuSmxjMmdnVTB4'
    || 'QkxDQmhiaUJ2Y0dWeVlYUnBiMjV6SUhacFpYY3VJbjA3Wm5WdVkzUnBiMjRnY25Nb2RTeG1LWHR5WlhSMWNtNGdkVDA5UFc1MWJHeDhmR1k5UFQxdWRXeHNm'
    || 'SHgxUFQwOU1EOGlJam9pZmlRaUsyVmxLSFVxWmlsOVpuVnVZM1JwYjI0Z1JXTW9kU2w3WTI5dWMzUWdaajFUZEhKcGJtY29kUzVVU1VWU1B6OGlJaWt1ZEc5'
    || 'VmNIQmxja05oYzJVb0tTeGhQVWRzTG1sdVkyeDFaR1Z6S0dZcFAyWTZJa1JKVTBOUFZrVlNJaXg0UFVkc0xtbHVaR1Y0VDJZb1lTa3NUajFPZENoMUxsSkJW'
    || 'RVZmVUVWU1gwTlNSVVJKVkNrc1F6MU9kQ2gxTGtOU1JVUkpWRjlEUVZBcExIazlUblFvZFM1VFZFRk9SRWxPUjE5RFVrVkVTVlJUWDFCRlVsOU5UMDVVU0Nr'
    || 'c1h6MU9kQ2gxTGxORFNFVkVWVXhGUkY5RFQwMVFUMDVGVGxSVEtUOC9NQ3gzUFU1MEtIVXVWazlNVlUxRlgwTlBUVkJQVGtWT1ZGTXBQejh3TEVJOWR6NHdQ'
    || 'MkFnS3lBa2UzZDlJSFp2YkhWdFpTMWtjbWwyWlc1Z09pSWlPMnhsZENCTUxFRTdYejR3SmlaNUlUMDliblZzYkNZbWVUNHdQeWhNUFdCK0pIdGxaU2g1S1gw'
    || 'Z1kzSmxaR2wwY3k5dGIyNTBhQ1I3UW4xZ0xFRTlJbkJ5YjJwbFkzUmxaQ0JtY205dElIUm9aU0JqWVdSbGJtTmxJSFJvYVhNZ1luVnBiR1FnYzJWMElHRnVa'
    || 'Q0IwYUdVZ1pIVnlZWFJwYjI0Z2FYUWdiV1ZoYzNWeVpXUXVJRTV2ZENCaElHSnBiR3d1SWlzb2R6NHdQeUlnVkdobElIWnZiSFZ0WlMxa2NtbDJaVzRnWTI5'
    || 'dGNHOXVaVzUwY3lCb1lYWmxJRzV2SUcxdmJuUm9iSGtnWm1sbmRYSmxJR0YwSUdGc2JEc2dkR2hsYVhJZ1kyOXpkQ0J6WTJGc1pYTWdkMmwwYUNCb2IzY2di'
    || 'WFZqYUNCa1lYUmhJSGx2ZFNCelpXNWtMaUk2SWlJcEtUcGZQakEvS0V3OVlDUjdYMzBnYzJOb1pXUjFiR1ZrSUdOdmJYQnZibVZ1ZENSN1h6MDlQVEUvSWlJ'
    || 'NkluTWlmU1I3UW4xZ0xFRTlZVDA5UFNKUVVrOUVWVU5VU1U5T0lqOGljbVZuYVhOMFpYSmxaQ0J2YmlCaElITmphR1ZrZFd4bExDQmlkWFFnZEdobElISmxZ'
    || 'Mjl5WkdWa0lHTmhaR1Z1WTJVZ2FYTWdlbVZ5Ynl3Z2MyOGdibThnYlc5dWRHaHNlU0JtYVdkMWNtVWdZMkZ1SUdKbElHUmxjbWwyWldRdUlGUnlaV0YwSUhS'
    || 'b2FYTWdZWE1nZFc1cmJtOTNiaXdnYm05MElHRnpJR1p5WldVdUlqb2lkR2hsSUhKbFkzVnljbWx1WnlCdlltcGxZM1J6SUdGeVpTQnBibk4wWVd4c1pXUWdZ'
    || 'VzVrSUhOMWMzQmxibVJsWkNCaGRDQjBhR2x6SUhScFpYSXNJSE52SUc1dklHTmhaR1Z1WTJVZ2FYTWdiMjRnY21WamIzSmtJSFJ2SUhCeWIycGxZM1FnWm5K'
    || 'dmJTNGdWR2hwY3lCcGN5Qk9UMVFnZW1WeWJ5QXRMU0JpZFdsc1pDQmhkQ0JRVWs5RVZVTlVTVTlPSUhSdklHZGxkQ0IwYUdVZ2JXVmhjM1Z5WldRZ2JXOXVk'
    || 'R2hzZVNCbWFXZDFjbVV1SWlrNmR6NHdQeWhNUFdBa2UzZDlJSFp2YkhWdFpTMWtjbWwyWlc0Z1kyOXRjRzl1Wlc1MEpIdDNQVDA5TVQ4aUlqb2ljeUo5WUN4'
    || 'QlBTSnVieUJqWVdSbGJtTmxMQ0J6YnlCdWJ5QnRiMjUwYUd4NUlIQnliMnBsWTNScGIyNGdhWE1nY0c5emMybGliR1V1SUZSb2FYTWdhWE1nVGs5VUlIcGxj'
    || 'bThnTFMwZ2RHaGxJR052YzNRZ2MyTmhiR1Z6SUhkcGRHZ2dhRzkzSUcxMVkyZ2daR0YwWVNCNWIzVWdjMlZ1WkM0aUtUb29URDBpYm05MGFHbHVaeUJ5WldO'
    || 'MWNuSnBibWNpTEVFOUluUm9hWE1nYzI5c2RYUnBiMjRnYVc1emRHRnNiSE1nYm05MGFHbHVaeUJ2YmlCaElITmphR1ZrZFd4bExpQkpkQ0JqYjNOMGN5Qnpk'
    || 'Rzl5WVdkbElIQnNkWE1nZDJoaGRHVjJaWElnWTI5dGNIVjBaU0IwYUdVZ2NHVnZjR3hsSUhGMVpYSjVhVzVuSUdsMElIVnpaUzRpS1R0amIyNXpkQ0JJUFh0'
    || 'RVNWTkRUMVpGVWpwN1ptbG5kWEpsT2lJd0lHTnlaV1JwZEhNdmJXOXVkR2dpTEcxdmJtVjVPaUlpTEdKaGMybHpPaUp1YjNSb2FXNW5JR2x6SUd4bFpuUWdj'
    || 'blZ1Ym1sdVp5d2djMjhnYm05MGFHbHVaeUJ5WldOMWNuTXVJRlJvWlNCdmJtVXRkR2x0WlNCeVpXRmtJR2wwYzJWc1ppQnBjeUJoSUdoaGJtUm1kV3dnYjJZ'
    || 'Z2NYVmxjbWxsY3k0aWZTeE1TVTFKVkVWRU9udG1hV2QxY21VNlF5WW1RejR3UDJEaWlhUWdKSHRsWlNoREtYMGdZM0psWkdsMGN5QnZibVV0ZEdsdFpXQTZJ'
    || 'bTV2SUdOaGNDQnpaWFFpTEcxdmJtVjVPa01tSmtNK01EOXljeWhETEU0cE9pSWlMR0poYzJsek9rTW1Ka00rTUQ4aVlXNGdaVzVtYjNKalpXUWdZMlZwYkds'
    || 'dVp5d2dibTkwSUdGdUlHVnpkR2x0WVhSbE9pQmhJSEpsYzI5MWNtTmxJRzF2Ym1sMGIzSWdjM1Z6Y0dWdVpITWdkR2hsSUhkaGNtVm9iM1Z6WlNCM2FHVnVJ'
    || 'R2wwSUdseklISmxZV05vWldRdUlFbDBJR2R2ZG1WeWJuTWdWMEZTUlVoUFZWTkZJR055WldScGRITWdiMjVzZVNBdExTQnViM1FnYzJWeWRtVnliR1Z6Y3lC'
    || 'bVpXRjBkWEpsY3lCaGJtUWdibTkwSUVGSklIUnZhMlZ1Y3k0aU9pSkRVa1ZFU1ZSZlEwRlFJR2x6SURBc0lITnZJSFJvWlhKbElHbHpJRzV2SUdWdVptOXlZ'
    || 'MlZrSUdObGFXeHBibWNnYjI0Z2RHaHBjeUJ5ZFc0dUluMHNVRkpQUkZWRFZFbFBUanA3Wm1sbmRYSmxPa3dzYlc5dVpYazZjbk1vZVN4T0tTeGlZWE5wY3pw'
    || 'QmZYMHNjbVU5VTNSeWFXNW5LSFV1VTBWVVZFbE9SMTlRVWtWR1NWZy9QeUlpS1M1MGNtbHRLQ2s3Y21WMGRYSnVJRWRzTG0xaGNDZ29SeXhZS1QwK0tIdHBa'
    || 'RHBITEd4aFltVnNPbDlqVzBkZExITjBZWFJsT2xnOGVEOGlaRzl1WlNJNldEMDlQWGcvSW1OMWNuSmxiblFpT2lKaGFHVmhaQ0lzTGk0dVNGdEhYU3hpYkhW'
    || 'eVlqcHJZMXRIWFN4elpYUjBhVzVuT25KbFAyQlRSVlFnSkh0eVpYMWZSRVZRVEU5WlgxUkpSVklnUFNBbkpIdEhmU2M3WURwZ1UwVlVJRHh3Y21WbWFYZytY'
    || 'MFJGVUV4UFdWOVVTVVZTSUQwZ0p5UjdSMzBuTzJCOUtTbDlablZ1WTNScGIyNGdUbU1vZTNOcGVtVTZkVDB4T1N4amIyeHZjanBtUFNJak1qbGlOV1U0SW4w'
    || 'cGUzSmxkSFZ5YmlCekxtcHplSE1vSW5OMlp5SXNlM2RwWkhSb09uVXNhR1ZwWjJoME9uVXNkbWxsZDBKdmVEb2lNQ0F3SURRekxqUWdORE11TlNJc1ptbHNi'
    || 'RHBtTEhKdmJHVTZJbWx0WnlJc0ltRnlhV0V0YkdGaVpXd2lPaUpUYm05M1pteGhhMlVpTEdOb2FXeGtjbVZ1T2x0ekxtcHplQ2dpY0dGMGFDSXNlMlE2SWsw'
    || 'ek55NHlOak0zTkRZMUxETXpMakV5T0Rrd05pQk1Namd1TURnM09UWTFOU3d5Tnk0NE1qZ3hNalVnUXpJMkxqYzVPRGt3TWpVc01qY3VNRGcxT1RNNElESTFM'
    || 'akUxTURRMk5UVXNNamN1TlRJM016UTBJREkwTGpRd05ETTNNVFVzTWpndU9ERTJOREEySUVNeU5DNHhNVFV6TURnMUxESTVMak15TkRJeE9TQXlOQzR3TURJ'
    || 'd01qYzFMREk1TGpnNE1qZ3hNaUF5TkM0d05UWTNNVFUxTERNd0xqUXlOVGM0TVNCTU1qUXVNRFUyTnpFMU5TdzBNQzQzT0RVeE5UWWdRekkwTGpBMU5qY3hO'
    || 'VFVzTkRJdU1qWTFOakkxSURJMUxqSTFPVGd6T1RVc05ETXVORFk0TnpVZ01qWXVOelEwTWpFMU5TdzBNeTQwTmpnM05TQkRNamd1TWpJME5qZ3pOU3cwTXk0'
    || 'ME5qZzNOU0F5T1M0ME1qYzRNRGcxTERReUxqSTJOVFl5TlNBeU9TNDBNamM0TURnMUxEUXdMamM0TlRFMU5pQk1Namt1TkRJM09EQTROU3d6TkM0NE1qZ3hN'
    || 'alVnVERNMExqVTJPRFF6TXpVc016Y3VOemsyT0RjMUlFTXpOUzQ0TlRjME9UWTFMRE00TGpVME1qazJPU0F6Tnk0MU1EazRNemsxTERNNExqQTVOelkxTmlB'
    || 'ek9DNHlOVEl3TWpjMUxETTJMamd3T0RVNU5DQkRNemd1T1RrNE1USXhOU3d6TlM0MU1UazFNekVnTXpndU5UVTJOekUxTlN3ek15NDROekV3T1RRZ016Y3VN'
    || 'all6TnpRMk5Td3pNeTR4TWpnNU1EWWlmU2tzY3k1cWMzZ29JbkJoZEdnaUxIdGtPaUpOTVRRdU5EUXpORE16TlN3eU1TNDNOamsxTXpFZ1F6RTBMalExT1RB'
    || 'MU9EVXNNakF1T0RFeU5TQXhNeTQ1TlRVeE5USTFMREU1TGpreU1UZzNOU0F4TXk0eE1qY3dNamMxTERFNUxqUTBNVFF3TmlCTU15NDVOVEV5TkRZME9Td3hO'
    || 'QzR4TkRRMU16RWdRek11TlRVeU9EQTRORGtzTVRNdU9URTBNRFl5SURNdU1EazFOemMzTkRrc01UTXVOemt5T1RZNUlESXVOak00TnpRMk5Ea3NNVE11Tnpr'
    || 'eU9UWTVJRU14TGpZNU56TXpPVFE1TERFekxqYzVNamsyT1NBd0xqZ3lNak16T1RRNU5Td3hOQzR5T1RZNE56VWdNQzR6TlRNMU9EazBPVFVzTVRVdU1UQTVN'
    || 'emMxSUVNdE1DNHpOekk1TnpJMU1EVXNNVFl1TXpZM01UZzRJREF1TURZd05qSXhORGsxTERFM0xqazRNRFEyT1NBeExqTXhPRFF6TXpRNUxERTRMamN3TnpB'
    || 'ek1TQk1OaTQyTURjME9UWTBPU3d5TVM0M05UYzRNVElnVERFdU16RTRORE16TkRrc01qUXVPREV5TlNCRE1DNDNNRGt3TlRnME9UVXNNalV1TVRZME1EWXlJ'
    || 'REF1TWpjeE5UVTRORGsxTERJMUxqY3pNRFEyT1NBd0xqQTVNVGczTVRRNU5Td3lOaTQwTVRBeE5UWWdReTB3TGpBNU1UY3lNalV3TlN3eU55NHdPRGs0TkRR'
    || 'Z01DNHdNREl3TWpjME9UUTVOaXd5Tnk0NE1EQTNPREVnTUM0ek5UTTFPRGswT1RVc01qZ3VOREV3TVRVMklFTXdMamd5TWpNek9UUTVOU3d5T1M0eU1qSTJO'
    || 'VFlnTVM0Mk9UY3pNemswT1N3eU9TNDNNalkxTmpJZ01pNDJNelE0TXprME9Td3lPUzQzTWpZMU5qSWdRek11TURrMU56YzNORGtzTWprdU56STJOVFl5SURN'
    || 'dU5UVXlPREE0TkRrc01qa3VOakExTkRZNUlETXVPVFV4TWpRMk5Ea3NNamt1TXpjMUlFd3hNeTR4TWpjd01qYzFMREkwTGpBM09ERXlOU0JETVRNdU9UUTNN'
    || 'ek01TlN3eU15NDJNREUxTmpJZ01UUXVORFV4TWpRMk5Td3lNaTQzTVRnM05TQXhOQzQwTkRNME16TTFMREl4TGpjMk9UVXpNU0o5S1N4ekxtcHplQ2dpY0dG'
    || 'MGFDSXNlMlE2SWswMkxqQXpNekkzTnpRNUxERXdMak01TURZeU5TQk1NVFV1TWpBNU1EVTROU3d4TlM0Mk9EYzFJRU14Tmk0eU56a3pOekUxTERFMkxqTXdP'
    || 'RFU1TkNBeE55NDFPVGsyT0RNMUxERTJMakV3TlRRMk9TQXhPQzQwTkRNME16TTFMREUxTGpJNE1USTFJRU14T0M0NU56ZzFPRGsxTERFMExqYzRPVEEyTWlB'
    || 'eE9TNHpNVEEyTWpFMUxERTBMakE0TlRrek9DQXhPUzR6TVRBMk1qRTFMREV6TGpNd05EWTRPQ0JNTVRrdU16RXdOakl4TlN3eUxqWTROelVnUXpFNUxqTXhN'
    || 'RFl5TVRVc01TNHlNRE14TWpVZ01UZ3VNVEEzTkRrMk5Td3dJREUyTGpZeU56QXlOelVzTUNCRE1UVXVNVFF5TmpVeU5Td3dJREV6TGprek9UVXlOelVzTVM0'
    || 'eU1ETXhNalVnTVRNdU9UTTVOVEkzTlN3eUxqWTROelVnVERFekxqa3pPVFV5TnpVc09DNDNNekEwTmprZ1REZ3VOekk0TlRnNU5Ea3NOUzQzTWpJMk5UWWdR'
    || 'emN1TkRNNU5USTNORGtzTkM0NU56WTFOaklnTlM0M09URXdPRGswT1N3MUxqUXhOemsyT1NBMUxqQTBORGs1TmpRNUxEWXVOekEzTURNeElFTTBMakk1T0Rr'
    || 'd01qUTVMRGN1T1RrMk1EazBJRFF1TnpRME1qRTFORGtzT1M0Mk5EUTFNekVnTmk0d016TXlOemMwT1N3eE1DNHpPVEEyTWpVaWZTa3NjeTVxYzNnb0luQmhk'
    || 'R2dpTEh0a09pSk5Nall1TmpZMk1EZzVOU3d5TWk0eE9Ua3lNVGtnUXpJMkxqWTJOakE0T1RVc01qSXVOREF5TXpRMElESTJMalUwT0Rrd01qVXNNakl1Tmpn'
    || 'ek5UazBJREkyTGpRd05ETTNNVFVzTWpJdU9ETXlNRE14SUV3eU1pNDNOamMyTlRJMUxESTJMalEyT0RjMUlFTXlNaTQyTWpNeE1qRTFMREkyTGpZeE16STRN'
    || 'U0F5TWk0ek16YzVOalUxTERJMkxqY3pNRFEyT1NBeU1pNHhNelE0TXprMUxESTJMamN6TURRMk9TQk1NakV1TWpBNU1EVTROU3d5Tmk0M016QTBOamtnUXpJ'
    || 'eExqQXdOVGt6TXpVc01qWXVOek13TkRZNUlESXdMamN5TURjM056VXNNall1TmpFek1qZ3hJREl3TGpVM05qSTBOalVzTWpZdU5EWTROelVnVERFMkxqa3pO'
    || 'VFl5TVRVc01qSXVPRE15TURNeElFTXhOaTQzT1RFd09EazFMREl5TGpZNE16VTVOQ0F4Tmk0Mk56TTVNREkxTERJeUxqUXdNak0wTkNBeE5pNDJOek01TURJ'
    || 'MUxESXlMakU1T1RJeE9TQk1NVFl1Tmpjek9UQXlOU3d5TVM0eU56TTBNemdnUXpFMkxqWTNNemt3TWpVc01qRXVNRFkyTkRBMklERTJMamM1TVRBNE9UVXNN'
    || 'akF1TnpnMU1UVTJJREUyTGprek5UWXlNVFVzTWpBdU5qUXdOakkxSUV3eU1DNDFOell5TkRZMUxERTNJRU15TUM0M01qQTNOemMxTERFMkxqZzFOVFEyT1NB'
    || 'eU1TNHdNRFU1TXpNMUxERTJMamN6T0RJNE1TQXlNUzR5TURrd05UZzFMREUyTGpjek9ESTRNU0JNTWpJdU1UTTBPRE01TlN3eE5pNDNNemd5T0RFZ1F6SXlM'
    || 'ak16TnprMk5UVXNNVFl1TnpNNE1qZ3hJREl5TGpZeU16RXlNVFVzTVRZdU9EVTFORFk1SURJeUxqYzJOelkxTWpVc01UY2dUREkyTGpRd05ETTNNVFVzTWpB'
    || 'dU5qUXdOakkxSUVNeU5pNDFORGc1TURJMUxESXdMamM0TlRFMU5pQXlOaTQyTmpZd09EazFMREl4TGpBMk5qUXdOaUF5Tmk0Mk5qWXdPRGsxTERJeExqSTNN'
    || 'elF6T0NCTU1qWXVOalkyTURnNU5Td3lNaTR4T1RreU1Ua2dXaUJOTWpNdU5ERTVPVGsyTlN3eU1TNDNOVE01TURZZ1RESXpMalF4T1RrNU5qVXNNakV1TnpF'
    || 'ME9EUTBJRU15TXk0ME1UazVPVFkxTERJeExqVTJOalF3TmlBeU15NHpNelF3TlRnMUxESXhMak0xT1RNM05TQXlNeTR5TWpnMU9EazFMREl4TGpJMUlFd3lN'
    || 'aTR4TlRRek56RTFMREl3TGpFM09UWTRPQ0JETWpJdU1EUTRPVEF5TlN3eU1DNHdOekF6TVRJZ01qRXVPRFF4T0RjeE5Td3hPUzQ1T0RRek56VWdNakV1Tmpn'
    || 'NU5USTNOU3d4T1M0NU9EUXpOelVnVERJeExqWTFNRFEyTlRVc01Ua3VPVGcwTXpjMUlFTXlNUzQxTURJd01qYzFMREU1TGprNE5ETTNOU0F5TVM0eU9UUTVP'
    || 'VFkxTERJd0xqQTNNRE14TWlBeU1TNHhPRFUyTWpFMUxESXdMakUzT1RZNE9DQk1NakF1TVRFMU16QTROU3d5TVM0eU5TQkRNakF1TURBNU9ETTVOU3d5TVM0'
    || 'ek5UVTBOamtnTVRrdU9USXpPVEF5TlN3eU1TNDFOakkxSURFNUxqa3lNemt3TWpVc01qRXVOekUwT0RRMElFd3hPUzQ1TWpNNU1ESTFMREl4TGpjMU16a3dO'
    || 'aUJETVRrdU9USXpPVEF5TlN3eU1TNDVNRFl5TlNBeU1DNHdNRGs0TXprMUxESXlMakV4TXpJNE1TQXlNQzR4TVRVek1EZzFMREl5TGpJeE9EYzFJRXd5TVM0'
    || 'eE9EVTJNakUxTERJekxqSTVNamsyT1NCRE1qRXVNamswT1RrMk5Td3lNeTR6T1RnME16Z2dNakV1TlRBeU1ESTNOU3d5TXk0ME9EUXpOelVnTWpFdU5qVXdO'
    || 'RFkxTlN3eU15NDBPRFF6TnpVZ1RESXhMalk0T1RVeU56VXNNak11TkRnME16YzFJRU15TVM0NE5ERTROekUxTERJekxqUTRORE0zTlNBeU1pNHdORGc1TURJ'
    || 'MUxESXpMak01T0RRek9DQXlNaTR4TlRRek56RTFMREl6TGpJNU1qazJPU0JNTWpNdU1qSTROVGc1TlN3eU1pNHlNVGczTlNCRE1qTXVNek0wTURVNE5Td3lN'
    || 'aTR4TVRNeU9ERWdNak11TkRFNU9UazJOU3d5TVM0NU1EWXlOU0F5TXk0ME1UazVPVFkxTERJeExqYzFNemt3TmlCYUluMHBMSE11YW5ONEtDSndZWFJvSWl4'
    || 'N1pEb2lUVEk0TGpBNE56azJOVFVzTVRVdU5qZzNOU0JNTXpjdU1qWXpOelEyTlN3eE1DNHpPVEEyTWpVZ1F6TTRMalUxTWpnd09EVXNPUzQyTkRnME16Z2dN'
    || 'emd1T1RrNE1USXhOU3czTGprNU5qQTVOQ0F6T0M0eU5USXdNamMxTERZdU56QTNNRE14SUVNek55NDFNRFU1TXpNMUxEVXVOREUzT1RZNUlETTFMamcxTnpR'
    || 'NU5qVXNOQzQ1TnpZMU5qSWdNelF1TlRZNE5ETXpOU3cxTGpjeU1qWTFOaUJNTWprdU5ESTNPREE0TlN3NExqWTVNVFF3TmlCTU1qa3VOREkzT0RBNE5Td3lM'
    || 'alk0TnpVZ1F6STVMalF5Tnpnd09EVXNNUzR5TURNeE1qVWdNamd1TWpJME5qZ3pOU3d0TlM0Mk9EUXpOREU0T1dVdE1UUWdNall1TnpRME1qRTFOU3d0TlM0'
    || 'Mk9EUXpOREU0T1dVdE1UUWdRekkxTGpJMU9UZ3pPVFVzTFRVdU5qZzBNelF4T0RsbExURTBJREkwTGpBMU5qY3hOVFVzTVM0eU1ETXhNalVnTWpRdU1EVTJO'
    || 'ekUxTlN3eUxqWTROelVnVERJMExqQTFOamN4TlRVc01UTXVNRGt6TnpVZ1F6STBMakF3TlRrek16VXNNVE11TmpNeU9ERXlJREkwTGpFeE1UUXdNalVzTVRR'
    || 'dU1UazFNekV5SURJMExqUXdORE0zTVRVc01UUXVOekF6TVRJMUlFTXlOUzR4TlRBME5qVTFMREUxTGprNU1qRTRPQ0F5Tmk0M09UZzVNREkxTERFMkxqUXpN'
    || 'elU1TkNBeU9DNHdPRGM1TmpVMUxERTFMalk0TnpVaWZTa3NjeTVxYzNnb0luQmhkR2dpTEh0a09pSk5NVGN1TURRNE9UQXlOU3d5Tnk0MU1UVTJNalVnUXpF'
    || 'MkxqUXpPVFV5TnpVc01qY3VNems0TkRNNElERTFMamM0TnpFNE16VXNNamN1TkRrMk1EazBJREUxTGpJd09UQTFPRFVzTWpjdU9ESTRNVEkxSUV3MkxqQXpN'
    || 'ekkzTnpRNUxETXpMakV5T0Rrd05pQkROQzQzTkRReU1UVTBPU3d6TXk0NE56RXdPVFFnTkM0eU9UZzVNREkwT1N3ek5TNDFNVGsxTXpFZ05TNHdORFE1T1RZ'
    || 'ME9Td3pOaTQ0TURnMU9UUWdRelV1TnpreE1EZzVORGtzTXpndU1UQXhOVFl5SURjdU5ETTVOVEkzTkRrc016Z3VOVFF5T1RZNUlEZ3VOekk0TlRnNU5Ea3NN'
    || 'emN1TnprMk9EYzFJRXd4TXk0NU16azFNamMxTERNMExqYzRPVEEyTWlCTU1UTXVPVE01TlRJM05TdzBNQzQzT0RVeE5UWWdRekV6TGprek9UVXlOelVzTkRJ'
    || 'dU1qWTFOakkxSURFMUxqRTBNalkxTWpVc05ETXVORFk0TnpVZ01UWXVOakkzTURJM05TdzBNeTQwTmpnM05TQkRNVGd1TVRBM05EazJOU3cwTXk0ME5qZzNO'
    || 'U0F4T1M0ek1UQTJNakUxTERReUxqSTJOVFl5TlNBeE9TNHpNVEEyTWpFMUxEUXdMamM0TlRFMU5pQk1NVGt1TXpFd05qSXhOU3d6TUM0eE5qYzVOamtnUXpF'
    || 'NUxqTXhNRFl5TVRVc01qZ3VPREk0TVRJMUlERTRMak16TURFMU1qVXNNamN1TnpFNE56VWdNVGN1TURRNE9UQXlOU3d5Tnk0MU1UVTJNalVpZlNrc2N5NXFj'
    || 'M2dvSW5CaGRHZ2lMSHRrT2lKTk5ESXVPVGs0TVRJeE5Td3hOUzR3TnpneE1qVWdRelF5TGpJMU5Ua3pNelVzTVRNdU56ZzFNVFUySURRd0xqWXdNelU0T1RV'
    || 'c01UTXVNelF6TnpVZ016a3VNekUwTlRJM05Td3hOQzR3T0RrNE5EUWdURE13TGpFek9EYzBOalVzTVRrdU16ZzJOekU1SUVNeU9TNHlOVGs0TXprMUxERTVM'
    || 'amc1TkRVek1TQXlPQzQzTnpVME5qVTFMREl3TGpneU5ESXhPU0F5T0M0M09URXdPRGsxTERJeExqYzJPVFV6TVNCRE1qZ3VOemd6TWpjM05Td3lNaTQzTVRB'
    || 'NU16Z2dNamt1TWpZM05qVXlOU3d5TXk0Mk1qZzVNRFlnTXpBdU1UTTROelEyTlN3eU5DNHhNamc1TURZZ1RETTVMak14TkRVeU56VXNNamt1TkRJNU5qZzRJ'
    || 'RU0wTUM0Mk1ETTFPRGsxTERNd0xqRTNNVGczTlNBME1pNHlOVEl3TWpjMUxESTVMamN6TURRMk9TQTBNaTQ1T1RneE1qRTFMREk0TGpRME1UUXdOaUJETkRN'
    || 'dU56UTBNakUxTlN3eU55NHhOVEl6TkRRZ05ETXVNams0T1RBeU5Td3lOUzQxTURNNU1EWWdOREl1TURBNU9ETTVOU3d5TkM0M05UYzRNVElnVERNMkxqZ3hO'
    || 'RFV5TnpVc01qRXVOelUzT0RFeUlFdzBNaTR3TURrNE16azFMREU0TGpjMU56Z3hNaUJETkRNdU16QXlPREE0TlN3eE9DNHdNVFUyTWpVZ05ETXVOelEwTWpF'
    || 'MU5Td3hOaTR6TmpjeE9EZ2dOREl1T1RrNE1USXhOU3d4TlM0d056Z3hNalVpZlNsZGZTbDlZMjl1YzNRZ2FtTTllMjkyWlhKMmFXVjNPbk11YW5ONGN5aHpM'
    || 'a1p5WVdkdFpXNTBMSHRqYUdsc1pISmxianBiY3k1cWMzZ29JbkpsWTNRaUxIdDRPaUl5SWl4NU9pSXlJaXgzYVdSMGFEb2lOUzQxSWl4b1pXbG5hSFE2SWpV'
    || 'dU5TSXNjbmc2SWpFdU1pSjlLU3h6TG1wemVDZ2ljbVZqZENJc2UzZzZJamd1TlNJc2VUb2lNaUlzZDJsa2RHZzZJalV1TlNJc2FHVnBaMmgwT2lJMUxqVWlM'
    || 'SEo0T2lJeExqSWlmU2tzY3k1cWMzZ29JbkpsWTNRaUxIdDRPaUl5SWl4NU9pSTRMalVpTEhkcFpIUm9PaUkxTGpVaUxHaGxhV2RvZERvaU5TNDFJaXh5ZURv'
    || 'aU1TNHlJbjBwTEhNdWFuTjRLQ0p5WldOMElpeDdlRG9pT0M0MUlpeDVPaUk0TGpVaUxIZHBaSFJvT2lJMUxqVWlMR2hsYVdkb2REb2lOUzQxSWl4eWVEb2lN'
    || 'UzR5SW4wcFhYMHBMSEJsYjNCc1pUcHpMbXB6ZUhNb2N5NUdjbUZuYldWdWRDeDdZMmhwYkdSeVpXNDZXM011YW5ONEtDSmphWEpqYkdVaUxIdGplRG9pTmlJ'
    || 'c1kzazZJalV1TlNJc2Nqb2lNaTQwSW4wcExITXVhbk40S0NKd1lYUm9JaXg3WkRvaVRUSWdNVE11TldNd0xUSXVNaUF4TGpndE15NDJJRFF0TXk0MmN6UWdN'
    || 'UzQwSURRZ015NDJJbjBwTEhNdWFuTjRLQ0p3WVhSb0lpeDdaRG9pVFRFeElEUXVNbUV5TGpJZ01pNHlJREFnTUNBeElEQWdOQzR6VFRFeExqWWdNVE11TldN'
    || 'd0xURXVOeTB1TnkweUxqa3RNUzQ0TFRNdU5DSjlLVjE5S1N4elpXZHRaVzUwY3pwekxtcHplSE1vY3k1R2NtRm5iV1Z1ZEN4N1kyaHBiR1J5Wlc0NlczTXVh'
    || 'bk40S0NKamFYSmpiR1VpTEh0amVEb2lOaUlzWTNrNklqWWlMSEk2SWpNdU5pSjlLU3h6TG1wemVDZ2lZMmx5WTJ4bElpeDdZM2c2SWpFd0lpeGplVG9pTVRB'
    || 'aUxISTZJak11TmlKOUtWMTlLU3hwWkdWdWRHbDBlVHB6TG1wemVITW9jeTVHY21GbmJXVnVkQ3g3WTJocGJHUnlaVzQ2VzNNdWFuTjRLQ0p3WVhSb0lpeDda'
    || 'RG9pVFRnZ01tRXpJRE1nTUNBd0lERWdNeUF6ZGpFaWZTa3NjeTVxYzNnb0luQmhkR2dpTEh0a09pSk5OU0EyVmpWaE15QXpJREFnTUNBeElERXRNaTR5SW4w'
    || 'cExITXVhbk40S0NKd1lYUm9JaXg3WkRvaVRUUXVOU0EzTGpWak1DQXpJREVnTkM0MUlETXVOU0EyTGpVaWZTa3NjeTVxYzNnb0luQmhkR2dpTEh0a09pSk5P'
    || 'Q0EyZGpNdU5TSjlLU3h6TG1wemVDZ2ljR0YwYUNJc2UyUTZJazB4TVM0MUlEY3VOV013SURJdExqUWdNeTR6TFRFdU1pQTBMalFpZlNsZGZTa3NZMjkyWlhK'
    || 'aFoyVTZjeTVxYzNoektITXVSbkpoWjIxbGJuUXNlMk5vYVd4a2NtVnVPbHR6TG1wemVDZ2lZMmx5WTJ4bElpeDdZM2c2SWpnaUxHTjVPaUk0SWl4eU9pSTJJ'
    || 'bjBwTEhNdWFuTjRLQ0p3WVhSb0lpeDdaRG9pVFRnZ01tRTJJRFlnTUNBd0lERWdNQ0F4TWlJc1ptbHNiRG9pWTNWeWNtVnVkRU52Ykc5eUlpeHpkSEp2YTJV'
    || 'NkltNXZibVVpTEc5d1lXTnBkSGs2SWk0eU1pSjlLU3h6TG1wemVDZ2ljR0YwYUNJc2UyUTZJazA0SURRdU5YWXpMalZzTWk0MUlERXVOaUo5S1YxOUtTeHRi'
    || 'MjVsZVRwekxtcHplSE1vY3k1R2NtRm5iV1Z1ZEN4N1kyaHBiR1J5Wlc0NlczTXVhbk40S0NKd1lYUm9JaXg3WkRvaVRUZ2dNUzQ0ZGpFeUxqUWlmU2tzY3k1'
    || 'cWMzZ29JbkJoZEdnaUxIdGtPaUpOTVRFZ05DNDJZekF0TVM0eExURXVNeTB4TGprdE15MHhMamx6TFRNZ0xqZ3RNeUF4TGpsak1DQXhMaklnTVM0eUlERXVO'
    || 'eUF6SURJdU1uTXpJREVnTXlBeUxqTmpNQ0F4TGpJdE1TNHpJREl0TXlBeWN5MHpMUzQ0TFRNdE1pSjlLVjE5S1N4emFHbGxiR1E2Y3k1cWMzaHpLSE11Um5K'
    || 'aFoyMWxiblFzZTJOb2FXeGtjbVZ1T2x0ekxtcHplQ2dpY0dGMGFDSXNlMlE2SWswNElERXVPQ0F6SURNdU9IWTBZekFnTXlBeUxqRWdOUzQwSURVZ05pNDBJ'
    || 'REl1T1MweElEVXRNeTQwSURVdE5pNDBkaTAwV2lKOUtTeHpMbXB6ZUNnaWNHRjBhQ0lzZTJRNklrMDJJRGd1TVd3eExqWWdNUzQyVERFd0xqUWdOaTQySW4w'
    || 'cFhYMHBMSFJoWW14bE9uTXVhbk40Y3loekxrWnlZV2R0Wlc1MExIdGphR2xzWkhKbGJqcGJjeTVxYzNnb0luSmxZM1FpTEh0NE9pSXlJaXg1T2lJeUxqZ2lM'
    || 'SGRwWkhSb09pSXhNaUlzYUdWcFoyaDBPaUl4TUM0MElpeHllRG9pTVM0MEluMHBMSE11YW5ONEtDSndZWFJvSWl4N1pEb2lUVElnTmk0emFERXlUVFl1TkNB'
    || 'MkxqTjJOaTQ1SW4wcFhYMHBMR1pzYjNjNmN5NXFjM2h6S0hNdVJuSmhaMjFsYm5Rc2UyTm9hV3hrY21WdU9sdHpMbXB6ZUNnaWNtVmpkQ0lzZTNnNklqRXVO'
    || 'aUlzZVRvaU5TNDRJaXgzYVdSMGFEb2lOQ0lzYUdWcFoyaDBPaUkwTGpRaUxISjRPaUl4TGpFaWZTa3NjeTVxYzNnb0luSmxZM1FpTEh0NE9pSXhNQzQwSWl4'
    || 'NU9pSXlMalFpTEhkcFpIUm9PaUkwSWl4b1pXbG5hSFE2SWpRdU5DSXNjbmc2SWpFdU1TSjlLU3h6TG1wemVDZ2ljbVZqZENJc2UzZzZJakV3TGpRaUxIazZJ'
    || 'amt1TWlJc2QybGtkR2c2SWpRaUxHaGxhV2RvZERvaU5DNDBJaXh5ZURvaU1TNHhJbjBwTEhNdWFuTjRLQ0p3WVhSb0lpeDdaRG9pVFRVdU5pQTRhREl1TW1F'
    || 'eExqSWdNUzR5SURBZ01DQXdJREV1TWkweExqSldOQzQyYURFdU5FMDFMallnT0dneUxqSmhNUzR5SURFdU1pQXdJREFnTVNBeExqSWdNUzR5ZGpJdU1tZ3hM'
    || 'alFpZlNsZGZTa3NZMmhsWTJzNmN5NXFjM2h6S0hNdVJuSmhaMjFsYm5Rc2UyTm9hV3hrY21WdU9sdHpMbXB6ZUNnaVkybHlZMnhsSWl4N1kzZzZJamdpTEdO'
    || 'NU9pSTRJaXh5T2lJMkluMHBMSE11YW5ONEtDSndZWFJvSWl4N1pEb2lUVFV1TkNBNExqSWdOeTR5SURFd2JETXVOQzB6TGpjaWZTbGRmU2tzZDJGeWJqcHpM'
    || 'bXB6ZUhNb2N5NUdjbUZuYldWdWRDeDdZMmhwYkdSeVpXNDZXM011YW5ONEtDSndZWFJvSWl4N1pEb2lUVGdnTWk0MElERXVPU0F4TTJneE1pNHlURGdnTWk0'
    || 'MFdpSjlLU3h6TG1wemVDZ2ljR0YwYUNJc2UyUTZJazA0SURZdU5IWXpUVGdnTVRFdU0zWXVNU0o5S1YxOUtTeHpjR0Z5YXpwekxtcHplSE1vY3k1R2NtRm5i'
    || 'V1Z1ZEN4N1kyaHBiR1J5Wlc0NlczTXVhbk40S0NKd1lYUm9JaXg3WkRvaVRUSWdNVEV1Tkd3ekxqSXRNeTQySURJdU5DQXlJRFF1TkMwMUluMHBMSE11YW5O'
    || 'NEtDSndZWFJvSWl4N1pEb2lUVEV5SURRdU9HZ3RNaTQyVFRFeUlEUXVPSFl5TGpZaWZTbGRmU2tzWTJ4dlkyczZjeTVxYzNoektITXVSbkpoWjIxbGJuUXNl'
    || 'Mk5vYVd4a2NtVnVPbHR6TG1wemVDZ2lZMmx5WTJ4bElpeDdZM2c2SWpnaUxHTjVPaUk0SWl4eU9pSTJJbjBwTEhNdWFuTjRLQ0p3WVhSb0lpeDdaRG9pVFRn'
    || 'Z05DNDJWamhzTWk0MklERXVOeUo5S1YxOUtTeHNZWGxsY25NNmN5NXFjM2h6S0hNdVJuSmhaMjFsYm5Rc2UyTm9hV3hrY21WdU9sdHpMbXB6ZUNnaWNHRjBh'
    || 'Q0lzZTJRNklrMDRJREV1T1NBeUlEVnNOaUF6TGpGTU1UUWdOU0E0SURFdU9Wb2lmU2tzY3k1cWMzZ29JbkJoZEdnaUxIdGtPaUpOTWlBNExqUWdPQ0F4TVM0'
    || 'MWJEWXRNeTR4VFRJZ01URXVOQ0E0SURFMExqVnNOaTB6TGpFaWZTbGRmU2w5TzJaMWJtTjBhVzl1SUZSaktIdHVZVzFsT25Vc2MybDZaVHBtUFRFMWZTbDdj'
    || 'bVYwZFhKdUlITXVhbk40S0NKemRtY2lMSHQzYVdSMGFEcG1MR2hsYVdkb2REcG1MSFpwWlhkQ2IzZzZJakFnTUNBeE5pQXhOaUlzWm1sc2JEb2libTl1WlNJ'
    || 'c2MzUnliMnRsT2lKamRYSnlaVzUwUTI5c2IzSWlMSE4wY205clpWZHBaSFJvT2lJeExqVTFJaXh6ZEhKdmEyVk1hVzVsWTJGd09pSnliM1Z1WkNJc2MzUnli'
    || 'MnRsVEdsdVpXcHZhVzQ2SW5KdmRXNWtJaXdpWVhKcFlTMW9hV1JrWlc0aU9pSjBjblZsSWl4amFHbHNaSEpsYmpwcVkxdDFYWDBwZldaMWJtTjBhVzl1SUVO'
    || 'aktIdHpiMngxZEdsdmJqcDFMSE4xWW5ScGRHeGxPbVlzYzJWamRHbHZibk02WVN4aFkzUnBkbVU2ZUN4dmJsQnBZMnM2VGl4bWIyOTBPa045S1h0amIyNXpk'
    || 'Q0I1UFV3OVBrd3VkRzlNYjNkbGNrTmhjMlVvS1M1eVpYQnNZV05sS0M5YlhtRXRlakF0T1YwckwyY3NJaUlwTEY4OWVTaDFLU3gzUFdZL2VTaG1LVG9pSWl4'
    || 'Q1BTRWhkeVltSVY4dWFXNWpiSFZrWlhNb2R5a21KaUYzTG1sdVkyeDFaR1Z6S0Y4cE8zSmxkSFZ5YmlCekxtcHplSE1vSW1GemFXUmxJaXg3WTJ4aGMzTk9Z'
    || 'VzFsT2lKemFXUmxJaXhqYUdsc1pISmxianBiY3k1cWMzaHpLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbk5wWkdWZlgySnlZVzVrSWl4amFHbHNaSEpsYmpw'
    || 'YmN5NXFjM2dvVG1Nc2UzTnBlbVU2TWpKOUtTeHpMbXB6ZUhNb0ltUnBkaUlzZTNOMGVXeGxPbnR0YVc1WGFXUjBhRG93ZlN4amFHbHNaSEpsYmpwYmN5NXFj'
    || 'M2dvSW1ScGRpSXNlMk5zWVhOelRtRnRaVG9pYzJsa1pWOWZkMjl5WkcxaGNtc2lMR05vYVd4a2NtVnVPblY5S1N4Q1AzTXVhbk40S0NKa2FYWWlMSHRqYkdG'
    || 'emMwNWhiV1U2SW5OcFpHVmZYM04xWWlJc1kyaHBiR1J5Wlc0NlpuMHBPbTUxYkd4ZGZTbGRmU2tzY3k1cWMzZ29JbTVoZGlJc2UyTnNZWE56VG1GdFpUb2li'
    || 'bUYySWl4amFHbHNaSEpsYmpwaExtMWhjQ2dvVEN4QktUMCtlMk52Ym5OMElFZzlRVDR3UDJGYlFTMHhYUzVuY205MWNEcDJiMmxrSURBc2NtVTlUQzVuY205'
    || 'MWNDWW1UQzVuY205MWNDRTlQVWcvVEM1bmNtOTFjRHB1ZFd4c0xFYzljeTVxYzNoektDSmlkWFIwYjI0aUxIdGpiR0Z6YzA1aGJXVTZJbTVoZGw5ZmFYUmxi'
    || 'U0lyS0V3dVozSnZkWEEvSWlCdVlYWmZYMmwwWlcwdExYTjFZaUk2SWlJcEt5aE1MbWxrUFQwOWVEOGlJRzVoZGw5ZmFYUmxiUzB0YjI0aU9pSWlLU3dpWkdG'
    || 'MFlTMXZibVZ6YUc5MElqb2libUYyTFdsMFpXMGlMQ0prWVhSaExYTmxZM1JwYjI0aU9rd3VhV1FzYjI1RGJHbGphem9vS1QwK1RpaE1MbWxrS1N3aVlYSnBZ'
    || 'UzFqZFhKeVpXNTBJanBNTG1sa1BUMDllRDhpY0dGblpTSTZkbTlwWkNBd0xHTm9hV3hrY21WdU9sdHpMbXB6ZUNoVVl5eDdibUZ0WlRwTUxtbGpiMjQvUHlK'
    || 'dmRtVnlkbWxsZHlKOUtTeHpMbXB6ZUhNb0luTndZVzRpTEh0emRIbHNaVHA3YldsdVYybGtkR2c2TUN4bWJHVjRPakY5TEdOb2FXeGtjbVZ1T2x0ekxtcHpl'
    || 'Q2dpYzNCaGJpSXNlMk5zWVhOelRtRnRaVG9pYm1GMlgxOXNZV0psYkNJc1kyaHBiR1J5Wlc0NlRDNXNZV0psYkgwcExFd3VaR1Z6WXo5ekxtcHplQ2dpYzNC'
    || 'aGJpSXNlMk5zWVhOelRtRnRaVG9pYm1GMlgxOWtaWE5qSWl4amFHbHNaSEpsYmpwTUxtUmxjMk45S1RwdWRXeHNYWDBwTEV3dVltRmtaMlUvY3k1cWMzZ29J'
    || 'bk53WVc0aUxIdGpiR0Z6YzA1aGJXVTZJbTVoZGw5ZlltRmtaMlVnYm1GMlgxOWlZV1JuWlMwdElpc29UQzVpWVdSblpWUnZibVUvUHlKcFpHeGxJaWtzWTJo'
    || 'cGJHUnlaVzQ2VEM1aVlXUm5aWDBwT201MWJHd3NUQzV6ZEdGMGRYTS9jeTVxYzNnb0luTndZVzRpTEh0amJHRnpjMDVoYldVNkltNWhkbDlmWkc5MElHNWhk'
    || 'bDlmWkc5MExTMGlLMHd1YzNSaGRIVnpmU2s2Ym5Wc2JGMTlMRXd1YVdRcE8zSmxkSFZ5YmlCeVpUOXpMbXB6ZUhNb1ltVXVSbkpoWjIxbGJuUXNlMk5vYVd4'
    || 'a2NtVnVPbHR6TG1wemVDZ2lhRElpTEh0amJHRnpjMDVoYldVNkltNWhkbDlmWjNKdmRYQWlMR05vYVd4a2NtVnVPa3d1WjNKdmRYQjlLU3hIWFgwc0ltYzZJ'
    || 'aXRCS1RwSGZTbDlLU3hEUDNNdWFuTjRLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbk5wWkdWZlgyWnZiM1FpTEdOb2FXeGtjbVZ1T2tOOUtUcHVkV3hzWFgw'
    || 'cGZXWjFibU4wYVc5dUlIUjBLSHQwYVhSc1pUcDFMR2hwYm5RNlppeGphR2xzWkhKbGJqcGhMSGRwWkdVNmVIMHBlM0psZEhWeWJpQnpMbXB6ZUhNb0luTmxZ'
    || 'M1JwYjI0aUxIdGpiR0Z6YzA1aGJXVTZJbU5oY21RaUt5aDRQeUlnWTJGeVpDMHRkMmxrWlNJNklpSXBMQ0prWVhSaExXOXVaWE5vYjNRaU9pSmpZWEprSWl4'
    || 'amFHbHNaSEpsYmpwYmN5NXFjM2h6S0NKb1pXRmtaWElpTEh0amJHRnpjMDVoYldVNkltTmhjbVJmWDJobFlXUWlMR05vYVd4a2NtVnVPbHR6TG1wemVDZ2lh'
    || 'RElpTEh0amFHbHNaSEpsYmpwMWZTa3Naajl6TG1wemVDZ2ljQ0lzZTJOc1lYTnpUbUZ0WlRvaVkyRnlaRjlmYUdsdWRDSXNZMmhwYkdSeVpXNDZabjBwT201'
    || 'MWJHeGRmU2tzWVYxOUtYMW1kVzVqZEdsdmJpQlpaU2g3Y0dGdVpXdzZkU3gzYUdWdVRXbHpjMmx1WnpwbUxHNXZkRUoxYVd4MFFteHZZMnM2WVN4amFHbHNa'
    || 'SEpsYmpwNGZTbDdhV1lvSVhVcGNtVjBkWEp1SUdFL2N5NXFjM2dvY3k1R2NtRm5iV1Z1ZEN4N1kyaHBiR1J5Wlc0NllYMHBPbk11YW5ONGN5Z2laR2wySWl4'
    || 'N1kyeGhjM05PWVcxbE9pSndZVzVsYkMxdWIzUmlkV2xzZENJc0ltUmhkR0V0YjI1bGMyaHZkQ0k2SW5CaGJtVnNMVzV2ZEdKMWFXeDBJaXhqYUdsc1pISmxi'
    || 'anBiY3k1cWMzZ29Jbk4wY205dVp5SXNlMk5vYVd4a2NtVnVPaUpVYUdseklISjFiaUJrYVdRZ2JtOTBJR0oxYVd4a0lIUm9hWE1nY0dGeWRDNGlmU2tzY3k1'
    || 'cWMzZ29JbkFpTEh0amFHbHNaSEpsYmpwbVB6OGlWR2hsSUhOamNtbHdkQ0J5WVc0Z2FXNGdhWFJ6SUdSbFptRjFiSFFzSUhKbFlXUXRiMjVzZVNCdGIyUmxM'
    || 'Q0IzYUdsamFDQnBibk53WldOMGN5QjViM1Z5SUdGalkyOTFiblFnZDJsMGFHOTFkQ0JqY21WaGRHbHVaeUJoYm5sMGFHbHVaeTRnUm1sc2JDQnBiaUIwYUdV'
    || 'Z2MyVjBkR2x1WjNNZ1lYUWdkR2hsSUhSdmNDQnZaaUIwYUdVZ2MyTnlhWEIwSUdGdVpDQnlkVzRnYVhRZ1lXZGhhVzRnZEc4Z1luVnBiR1FnZEdocGN5NGlm'
    || 'U2xkZlNrN2FXWW9aMjRvZFNrcGNtVjBkWEp1SUdFL2N5NXFjM2dvY3k1R2NtRm5iV1Z1ZEN4N1kyaHBiR1J5Wlc0NllYMHBPbk11YW5ONGN5Z2laR2wySWl4'
    || 'N1kyeGhjM05PWVcxbE9pSndZVzVsYkMxdWIzUmlkV2xzZENJc0ltUmhkR0V0YjI1bGMyaHZkQ0k2SW5CaGJtVnNMVzV2ZEdKMWFXeDBJaXhqYUdsc1pISmxi'
    || 'anBiY3k1cWMzZ29Jbk4wY205dVp5SXNlMk5vYVd4a2NtVnVPaUpVYUdseklIQmhjblFnYUdGeklHNXZkQ0JpWldWdUlHSjFhV3gwSUhsbGRDNGlmU2tzY3k1'
    || 'cWMzZ29JbkFpTEh0amFHbHNaSEpsYmpwbVB6OGlWR2hwY3lCeWRXNGdaR2xrSUc1dmRDQmpjbVZoZEdVZ2RHaGxJRzlpYW1WamRITWdkR2hwY3lCallYSmtJ'
    || 'SEpsWVdSekxpQkdhV3hzSUdsdUlIUm9aU0J6WlhSMGFXNW5jeUJoZENCMGFHVWdkRzl3SUc5bUlIUm9aU0J6WTNKcGNIUWdZVzVrSUhKMWJpQnBkQ0JoWjJG'
    || 'cGJpNGlmU2tzY3k1cWMzZ29JbkFpTEh0amJHRnpjMDVoYldVNkluQmhibVZzTFc1dmRHSjFhV3gwWDE5aGJIUWlMR05vYVd4a2NtVnVPaWRKWmlCNWIzVWda'
    || 'WGh3WldOMFpXUWdhWFFnZEc4Z1pYaHBjM1FzSUhSb1pTQnpZVzFsSUZOdWIzZG1iR0ZyWlNCbGNuSnZjaUJqYjNabGNuTWdJbTV2ZENCaGRYUm9iM0pwZW1W'
    || 'a0lpRGlnSlFnZVc5MUlHMWhlU0JpWlNCdGFYTnphVzVuSUdFZ1ozSmhiblFnY21GMGFHVnlJSFJvWVc0Z1lTQmlkV2xzWkM0bmZTbGRmU2s3YVdZb2RtNG9k'
    || 'U2twY21WMGRYSnVJSE11YW5ONGN5Z2laR2wySWl4N1kyeGhjM05PWVcxbE9pSndZVzVsYkMxbGNuSnZjaUlzSW1SaGRHRXRiMjVsYzJodmRDSTZJbkJoYm1W'
    || 'c0xXVnljbTl5SWl4amFHbHNaSEpsYmpwYmN5NXFjM2dvSW5OMGNtOXVaeUlzZTJOb2FXeGtjbVZ1T2lKVWFHbHpJSEYxWlhKNUlHUnBaQ0J1YjNRZ2NuVnVM'
    || 'aUo5S1N4ekxtcHplQ2dpWTI5a1pTSXNlMk5vYVd4a2NtVnVPblV1WlhKeWIzSjlLVjE5S1R0cFppZ2hkUzV5YjNkekxteGxibWQwYUNseVpYUjFjbTRnY3k1'
    || 'cWMzZ29JbkFpTEh0amJHRnpjMDVoYldVNkluQmhibVZzTFdWdGNIUjVJaXdpWkdGMFlTMXZibVZ6YUc5MElqb2ljR0Z1Wld3dFpXMXdkSGtpTEdOb2FXeGtj'
    || 'bVZ1T2lKVWFHVWdjWFZsY25rZ2NtRnVJR0Z1WkNCeVpYUjFjbTVsWkNCdWJ5QnliM2R6TGlKOUtUdGpiMjV6ZENCT1BYaGpLSFVwTzNKbGRIVnliaUJ6TG1w'
    || 'emVITW9jeTVHY21GbmJXVnVkQ3g3WTJocGJHUnlaVzQ2VzA0L2N5NXFjM2h6S0NKd0lpeDdZMnhoYzNOT1lXMWxPaUp3WVc1bGJDMTBjblZ1WXlJc0ltUmhk'
    || 'R0V0YjI1bGMyaHZkQ0k2SW5CaGJtVnNMWFJ5ZFc1allYUmxaQ0lzWTJocGJHUnlaVzQ2V3lKVGFHOTNhVzVuSUhSb1pTQm1hWEp6ZENBaUxHVmxLRTRwTENJ'
    || 'Z2NtOTNjeTRnVkdocGN5QnhkV1Z5ZVNCeVpYUjFjbTVsWkNCdGIzSmxMQ0J6YnlCaGJua2dkRzkwWVd3Z2IyNGdkR2hwY3lCallYSmtJR2x6SUdFZ1pteHZi'
    || 'M0lzSUc1dmRDQmhJR052ZFc1MExpSmRmU2s2Ym5Wc2JDeDRYWDBwZldaMWJtTjBhVzl1SUhwMEtIdHliM2R6T25Vc1kyOXNjenBtTEcxaGVEcGhMRzl1VUds'
    || 'amF6cDRMR0ZqZEdsMlpUcE9mU2w3WTI5dWMzUWdRejFoUDNVdWMyeHBZMlVvTUN4aEtUcDFPM0psZEhWeWJpQnpMbXB6ZUhNb0ltUnBkaUlzZTJOc1lYTnpU'
    || 'bUZ0WlRvaWRHRmliR1V0ZDNKaGNDSXNZMmhwYkdSeVpXNDZXM011YW5ONGN5Z2lkR0ZpYkdVaUxIdGpiR0Z6YzA1aGJXVTZlRDhpZEdGaWJHVXRMWEJwWTJz'
    || 'aU9pSWlMR05vYVd4a2NtVnVPbHR6TG1wemVDZ2lkR2hsWVdRaUxIdGphR2xzWkhKbGJqcHpMbXB6ZUNnaWRISWlMSHRqYUdsc1pISmxianBtTG0xaGNDaDVQ'
    || 'VDV6TG1wemVDZ2lkR2dpTEh0amJHRnpjMDVoYldVNmVTNWhiR2xuYmowOVBTSnlhV2RvZENJL0luSWlPaUlpTEdOb2FXeGtjbVZ1T25rdWJHRmlaV3cvUDNr'
    || 'dWEyVjVmU3g1TG10bGVTa3BmU2w5S1N4ekxtcHplQ2dpZEdKdlpIa2lMSHRqYUdsc1pISmxianBETG0xaGNDZ29lU3hmS1QwK2N5NXFjM2dvSW5SeUlpeDdZ'
    || 'MnhoYzNOT1lXMWxPbmdtSmw4OVBUMU9QeUowY2kwdGIyNGlPaUlpTEc5dVEyeHBZMnM2ZUQ4b0tUMCtlQ2g1TEY4cE9uWnZhV1FnTUN4MFlXSkpibVJsZURw'
    || 'NFB6QTZkbTlwWkNBd0xDSmhjbWxoTFhObGJHVmpkR1ZrSWpwNFAxODlQVDFPT25admFXUWdNQ3h2Ymt0bGVVUnZkMjQ2ZUQ4b2R6MCtleWgzTG10bGVUMDlQ'
    || 'U0pGYm5SbGNpSjhmSGN1YTJWNVBUMDlJaUFpS1NZbUtIY3VjSEpsZG1WdWRFUmxabUYxYkhRb0tTeDRLSGtzWHlrcGZTazZkbTlwWkNBd0xHTm9hV3hrY21W'
    || 'dU9tWXViV0Z3S0hjOVBuTXVhbk40S0NKMFpDSXNlMk5zWVhOelRtRnRaVHAzTG1Gc2FXZHVQVDA5SW5KcFoyaDBJajhpY2lJNklpSXNZMmhwYkdSeVpXNDZk'
    || 'eTV5Wlc1a1pYSS9keTV5Wlc1a1pYSW9lVnQzTG10bGVWMHNlU2s2VEdNb2VWdDNMbXRsZVYwcGZTeDNMbXRsZVNrcGZTeGZLU2w5S1YxOUtTeGhKaVoxTG14'
    || 'bGJtZDBhRDVoUDNNdWFuTjRjeWdpY0NJc2UyTnNZWE56VG1GdFpUb2lkR0ZpYkdVdGJXOXlaU0lzWTJocGJHUnlaVzQ2VzJWbEtIVXViR1Z1WjNSb0xXRXBM'
    || 'Q0lnYlc5eVpTQnliM2NvY3lrZ2JtOTBJSE5vYjNkdUlsMTlLVHB1ZFd4c1hYMHBmV1oxYm1OMGFXOXVJRXhqS0hVcGUybG1LSFU5UFc1MWJHd3BjbVYwZFhK'
    || 'dUlITXVhbk40S0NKemNHRnVJaXg3WTJ4aGMzTk9ZVzFsT2lKdWRXeHNJaXhqYUdsc1pISmxiam9pVGxWTVRDSjlLVHRqYjI1emRDQm1QVTUwS0hVcE8zSmxk'
    || 'SFZ5YmlCbUlUMDliblZzYkQ5bFpTaG1LVHBUZEhKcGJtY29kU2w5Wm5WdVkzUnBiMjRnVW1Nb2UyTm9hV3hrY21WdU9uVXNkRzl1WlRwbWZTbDdjbVYwZFhK'
    || 'dUlITXVhbk40S0NKemNHRnVJaXg3WTJ4aGMzTk9ZVzFsT2lKd2FXeHNJaXNvWmo4aUlIQnBiR3d0TFNJclpqb2lJaWtzWTJocGJHUnlaVzQ2ZFgwcGZXWjFi'
    || 'bU4wYVc5dUlHeHpLSHQwYVhSc1pUcDFMR05vYVd4a2NtVnVPbVo5S1h0eVpYUjFjbTRnY3k1cWMzaHpLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbU5oZG1W'
    || 'aGRDSXNJbVJoZEdFdGIyNWxjMmh2ZENJNkltTmhkbVZoZENJc1kyaHBiR1J5Wlc0NlczTXVhbk40S0NKemRISnZibWNpTEh0amFHbHNaSEpsYmpwMWZTa3Nj'
    || 'eTVxYzNnb0luQWlMSHRqYUdsc1pISmxianBtZlNsZGZTbDlablZ1WTNScGIyNGdhWE1vZTJOb2FXeGtjbVZ1T25WOUtYdHlaWFIxY200Z2N5NXFjM2dvSW1S'
    || 'cGRpSXNlMk5zWVhOelRtRnRaVG9pYldWMGFHOWtJaXdpWkdGMFlTMXZibVZ6YUc5MElqb2liV1YwYUc5a0lpeGphR2xzWkhKbGJqcDFmU2w5WTI5dWMzUWdi'
    || 'M005V3lKVFFVMVFURVVpTENKTVNVMUpWRVZFSWl3aVVGSlBSRlZEVkVsUFRpSmRMRTFqUFh0VFFVMVFURVU2SWxObFpXUmxaQ0JrWVhSaElPS0FsQ0J6WVda'
    || 'bElIUnZJSEoxYmlCeVpYQmxZWFJsWkd4NUxDQndjbTkyWlhNZ2RHaGxJSE5vWVhCbElIZHBkR2h2ZFhRZ2RHOTFZMmhwYm1jZ1lXNTVkR2hwYm1jZ2NtVmhi'
    || 'QzRpTEV4SlRVbFVSVVE2SWxsdmRYSWdaR0YwWVN3Z1pHVnNhV0psY21GMFpXeDVJR0p2ZFc1a1pXUWc0b0NVSUdFZ2MzVmljMlYwTENCaElHTmhjQ3dnYjNJ'
    || 'Z1lTQnphVzVuYkdVZ2IySnFaV04wTGlJc1VGSlBSRlZEVkVsUFRqb2lXVzkxY2lCa1lYUmhMQ0JoZENCbWRXeHNJSE5qYjNCbExpQlNaV0ZrSUhSb1pTQjFi'
    || 'bVJ2SUd4cGJtVWdZbVZtYjNKbElIbHZkU0J5ZFc0Z2FYUXVJbjA3Wm5WdVkzUnBiMjRnVUdNb2UyRmpkR2x2Ym5NNmRYMHBlMk52Ym5OMFcyWXNZVjA5WW1V'
    || 'dWRYTmxVM1JoZEdVb0lURXBMSGc5ZTMwN1ptOXlLR052Ym5OMElIa2diMllnZFNsN1kyOXVjM1FnWHoxVGRISnBibWNvZVM1VVNVVlNQejhpVUZKUFJGVkRW'
    || 'RWxQVGlJcExuUnZWWEJ3WlhKRFlYTmxLQ2s3S0hoYlgxMC9QeWg0VzE5ZFBWdGRLU2t1Y0hWemFDaDVLWDFqYjI1emRDQk9QWFV1YkdWdVozUm9MRU05YjNN'
    || 'dVptbHNkR1Z5S0hrOVBudDJZWElnWHp0eVpYUjFjbTRvWHoxNFczbGRLVDA5Ym5Wc2JEOTJiMmxrSURBNlh5NXNaVzVuZEdoOUtTNXRZWEFvZVQwK0tIdDBh'
    || 'V1Z5T25rc1kyOTFiblE2ZUZ0NVhTNXNaVzVuZEdoOUtTazdjbVYwZFhKdUlITXVhbk40Y3loekxrWnlZV2R0Wlc1MExIdGphR2xzWkhKbGJqcGJjeTVxYzNo'
    || 'ektDSmlkWFIwYjI0aUxIdDBlWEJsT2lKaWRYUjBiMjRpTEdOc1lYTnpUbUZ0WlRvaVlXTjBMWE4xYlcxaGNua2lMRzl1UTJ4cFkyczZLQ2s5UG1Fb2VUMCtJ'
    || 'WGtwTENKaGNtbGhMV1Y0Y0dGdVpHVmtJanBtTEdOb2FXeGtjbVZ1T2x0ekxtcHplSE1vSW5Od1lXNGlMSHRqYkdGemMwNWhiV1U2SW1GamRDMXpkVzF0WVhK'
    || 'NVgxOWpiM1Z1ZENJc1kyaHBiR1J5Wlc0NlcyVmxLRTRwTENJZ1lXTjBhVzl1SWl4T1BUMDlNVDhpSWpvaWN5SmRmU2tzUXk1dFlYQW9LSHQwYVdWeU9ua3NZ'
    || 'MjkxYm5RNlgzMHBQVDV6TG1wemVITW9Jbk53WVc0aUxIdGpiR0Z6YzA1aGJXVTZJbUZqZEMxemRXMXRZWEo1WDE5MGFXVnlJaXhqYUdsc1pISmxianBiZVN3'
    || 'aUlDSXNYMTE5TEhrcEtTeHpMbXB6ZUNnaWMzWm5JaXg3WTJ4aGMzTk9ZVzFsT2lKaFkzUXRjM1Z0YldGeWVWOWZZMmhsZG5KdmJpSXJLR1kvSWlCaFkzUXRj'
    || 'M1Z0YldGeWVWOWZZMmhsZG5KdmJpMHRiM0JsYmlJNklpSXBMSGRwWkhSb09pSXhOQ0lzYUdWcFoyaDBPaUl4TkNJc2RtbGxkMEp2ZURvaU1DQXdJREUySURF'
    || 'MklpeG1hV3hzT2lKdWIyNWxJaXdpWVhKcFlTMW9hV1JrWlc0aU9pSjBjblZsSWl4amFHbHNaSEpsYmpwekxtcHplQ2dpY0dGMGFDSXNlMlE2SWswMElEWnNO'
    || 'Q0EwSURRdE5DSXNjM1J5YjJ0bE9pSmpkWEp5Wlc1MFEyOXNiM0lpTEhOMGNtOXJaVmRwWkhSb09pSXhMalVpTEhOMGNtOXJaVXhwYm1WallYQTZJbkp2ZFc1'
    || 'a0lpeHpkSEp2YTJWTWFXNWxhbTlwYmpvaWNtOTFibVFpZlNsOUtWMTlLU3htUDNNdWFuTjRjeWh6TGtaeVlXZHRaVzUwTEh0amFHbHNaSEpsYmpwYmIzTXVi'
    || 'V0Z3S0hrOVBudGpiMjV6ZENCZlBYaGJlVjA3Y21WMGRYSnVJVjk4ZkNGZkxteGxibWQwYUQ5dWRXeHNPbk11YW5ONGN5aGlaUzVHY21GbmJXVnVkQ3g3WTJo'
    || 'cGJHUnlaVzQ2VzNNdWFuTjRLQ0p3SWl4N1kyeGhjM05PWVcxbE9pSmhZM1JmWDNScFpYSWlMR05vYVd4a2NtVnVPbmw5S1N4ekxtcHplQ2dpY0NJc2UyTnNZ'
    || 'WE56VG1GdFpUb2lZV04wWDE5MGFXVnlMV1JsYzJNaUxHTm9hV3hrY21WdU9rMWpXM2xkUHo4aUluMHBMSE11YW5ONEtDSmthWFlpTEh0amJHRnpjMDVoYldV'
    || 'NkltRmpkRjlmWjNKcFpDSXNZMmhwYkdSeVpXNDZYeTV0WVhBb2R6MCtjeTVxYzNoektDSmthWFlpTEh0amJHRnpjMDVoYldVNkltRmpkRjlmWTJGeVpDSXNZ'
    || 'MmhwYkdSeVpXNDZXM011YW5ONEtDSmthWFlpTEh0amJHRnpjMDVoYldVNkltRmpkRjlmWTI5a1pTSXNZMmhwYkdSeVpXNDZVM1J5YVc1bktIY3VRMDlFUlNs'
    || 'OUtTeHpMbXB6ZUNnaVpHbDJJaXg3WTJ4aGMzTk9ZVzFsT2lKaFkzUmZYMnhoWW1Wc0lpeGphR2xzWkhKbGJqcFRkSEpwYm1jb2R5NU1RVUpGVEQ4L2R5NURU'
    || 'MFJGS1gwcExITXVhbk40S0NKa2FYWWlMSHRqYkdGemMwNWhiV1U2SW1GamRGOWZaV1ptWldOMElpeGphR2xzWkhKbGJqcFRkSEpwYm1jb2R5NUZSa1pGUTFR'
    || 'L1B5TGlnSlFpS1gwcExITXVhbk40Y3lnaVpHbDJJaXg3WTJ4aGMzTk9ZVzFsT2lKaFkzUmZYMjFsZEdFaUxHTm9hV3hrY21WdU9sdHpMbXB6ZUhNb0luTndZ'
    || 'VzRpTEh0amFHbHNaSEpsYmpwYkluNGlMRWxqS0hjdVJWTlVYME5TUlVSSlZGTXBMQ0lnWTNKbFpHbDBjeUpkZlNrc2N5NXFjM2h6S0NKemNHRnVJaXg3WTJo'
    || 'cGJHUnlaVzQ2VzJWbEtIY3VVMVJCVkVWTlJVNVVVeWtzSWlCemRHMTBJaXhZYkNoM0xsTlVRVlJGVFVWT1ZGTXBQVDA5TVQ4aUlqb2ljeUpkZlNrc2R5NVZU'
    || 'a1JQWDFOVVFWUkZUVVZPVkZNL2N5NXFjM2dvSW5Od1lXNGlMSHRqYkdGemMwNWhiV1U2SW1GamRGOWZkVzVrYnlJc1kyaHBiR1J5Wlc0NkluVnVaRzhnWVha'
    || 'aGFXeGhZbXhsSW4wcE9uTXVhbk40S0NKemNHRnVJaXg3WTJ4aGMzTk9ZVzFsT2lKaFkzUmZYMjV2ZFc1a2J5SXNZMmhwYkdSeVpXNDZJbTV2SUdGMWRHOHRk'
    || 'VzVrYnlKOUtWMTlLU3hZYkNoM0xsUkpUVVZUWDFKVlRpaytNRDl6TG1wemVITW9JbVJwZGlJc2UyTnNZWE56VG1GdFpUb2lZV04wWDE5eWRXNXpJaXhqYUds'
    || 'c1pISmxianBiSWxKMWJpQWlMR1ZsS0hjdVZFbE5SVk5mVWxWT0tTd2llQ0lzV0d3b2R5NVVTVTFGVTE5VlRrUlBUa1VwUGpBL1lDd2dkVzVrYjI1bElDUjda'
    || 'V1VvZHk1VVNVMUZVMTlWVGtSUFRrVXBmWGhnT2lJaVhYMHBPbTUxYkd4ZGZTeFRkSEpwYm1jb2R5NURUMFJGS1NrcGZTbGRmU3g1S1gwcExITXVhbk40S0NK'
    || 'd0lpeDdZMnhoYzNOT1lXMWxPaUpoWTNSZlgyWnZiM1FpTEdOb2FXeGtjbVZ1T2lKVWFHVWdZMjl1ZEhKdmJITWdabTl5SUhSb1pYTmxJR0ZqZEdsdmJuTWdZ'
    || 'WEpsSUdKbGJHOTNJSFJvWlNCa1lYTm9ZbTloY21RZzRvQ1VJSE5qY205c2JDQndZWE4wSUhSb1pTQmphR0Z5ZEhNZ2RHOGdabWx1WkNCMGFHVWdZblYwZEc5'
    || 'dWN5QmhibVFnWTI5dVptbHliV0YwYVc5dUlITjBaWEF1SW4wcFhYMHBPbTUxYkd4ZGZTbDlablZ1WTNScGIyNGdUMk1vZTJ4dlp6cDFmU2w3WTI5dWMzUmJa'
    || 'aXhoWFQxaVpTNTFjMlZUZEdGMFpTZ2hNU2tzZUQxMUxteGxibWQwYUN4T1BYVXVabWxzZEdWeUtIazlQbnRqYjI1emRDQmZQVk4wY21sdVp5aDVMbE5VUVZS'
    || 'VlV6OC9JaUlwTG5SdlZYQndaWEpEWVhObEtDazdjbVYwZFhKdUlGODlQVDBpUkU5T1JTSjhmRjg5UFQwaVZVNUVUMDVGSW4wcExteGxibWQwYUN4RFBYVXVa'
    || 'bWxzZEdWeUtIazlQbE4wY21sdVp5aDVMbE5VUVZSVlV6OC9JaUlwTG5SdlZYQndaWEpEWVhObEtDazlQVDBpUmtGSlRFVkVJaWt1YkdWdVozUm9PM0psZEhW'
    || 'eWJpQnpMbXB6ZUhNb2N5NUdjbUZuYldWdWRDeDdZMmhwYkdSeVpXNDZXM011YW5ONGN5Z2lZblYwZEc5dUlpeDdkSGx3WlRvaVluVjBkRzl1SWl4amJHRnpj'
    || 'MDVoYldVNkltRmpkQzF6ZFcxdFlYSjVJaXh2YmtOc2FXTnJPaWdwUFQ1aEtIazlQaUY1S1N3aVlYSnBZUzFsZUhCaGJtUmxaQ0k2Wml4amFHbHNaSEpsYmpw'
    || 'YmN5NXFjM2h6S0NKemNHRnVJaXg3WTJ4aGMzTk9ZVzFsT2lKaFkzUXRjM1Z0YldGeWVWOWZZMjkxYm5RaUxHTm9hV3hrY21WdU9sdGxaU2g0S1N3aUlITjBa'
    || 'WEFpTEhnOVBUMHhQeUlpT2lKeklsMTlLU3h6TG1wemVITW9Jbk53WVc0aUxIdGphR2xzWkhKbGJqcGJUaXdpSUdOdmJYQnNaWFJsWkNJc1F6NHdQMkFzSUNS'
    || 'N1EzMGdabUZwYkdWa1lEb2lJbDE5S1N4ekxtcHplQ2dpYzNabklpeDdZMnhoYzNOT1lXMWxPaUpoWTNRdGMzVnRiV0Z5ZVY5ZlkyaGxkbkp2YmlJcktHWS9J'
    || 'aUJoWTNRdGMzVnRiV0Z5ZVY5ZlkyaGxkbkp2YmkwdGIzQmxiaUk2SWlJcExIZHBaSFJvT2lJeE5DSXNhR1ZwWjJoME9pSXhOQ0lzZG1sbGQwSnZlRG9pTUNB'
    || 'd0lERTJJREUySWl4bWFXeHNPaUp1YjI1bElpd2lZWEpwWVMxb2FXUmtaVzRpT2lKMGNuVmxJaXhqYUdsc1pISmxianB6TG1wemVDZ2ljR0YwYUNJc2UyUTZJ'
    || 'azAwSURac05DQTBJRFF0TkNJc2MzUnliMnRsT2lKamRYSnlaVzUwUTI5c2IzSWlMSE4wY205clpWZHBaSFJvT2lJeExqVWlMSE4wY205clpVeHBibVZqWVhB'
    || 'NkluSnZkVzVrSWl4emRISnZhMlZNYVc1bGFtOXBiam9pY205MWJtUWlmU2w5S1YxOUtTeG1QM011YW5ONEtIcDBMSHR5YjNkek9uVXNZMjlzY3pwYmUydGxl'
    || 'VG9pUTA5RVJTSXNiR0ZpWld3NklrRmpkR2x2YmlKOUxIdHJaWGs2SWxOVVFWUlZVeUlzYkdGaVpXdzZJbE4wWVhSMWN5SXNjbVZ1WkdWeU9uazlQbnRqYjI1'
    || 'emRDQmZQVk4wY21sdVp5aDVQejhpSWlrc2R6MWZQVDA5SWtSUFRrVWlmSHhmUFQwOUlsVk9SRTlPUlNJL0ltZHZiMlFpT2w4OVBUMGlSa0ZKVEVWRUlqOGlZ'
    || 'bUZrSWpvaWQyRnliaUk3Y21WMGRYSnVJSE11YW5ONEtGSmpMSHQwYjI1bE9uY3NZMmhwYkdSeVpXNDZYM3g4SXVLQWxDSjlLWDE5TEh0clpYazZJbE5VUVZS'
    || 'RlRVVk9WRk5mVWxWT0lpeHNZV0psYkRvaVUzUnRkSE1pTEdGc2FXZHVPaUp5YVdkb2RDSjlMSHRyWlhrNklsTlVRVkpVUlVSZlFWUWlMR3hoWW1Wc09pSlRk'
    || 'R0Z5ZEdWa0lpeHlaVzVrWlhJNmVUMCtlVDlUZEhKcGJtY29lU2t1YzJ4cFkyVW9NQ3d4T1NrdWNtVndiR0ZqWlNnaVZDSXNJaUFpS1RvaTRvQ1VJbjBzZTJ0'
    || 'bGVUb2lSa2xPU1ZOSVJVUmZRVlFpTEd4aFltVnNPaUpHYVc1cGMyaGxaQ0lzY21WdVpHVnlPbms5UG5rL1UzUnlhVzVuS0hrcExuTnNhV05sS0RBc01Ua3BM'
    || 'bkpsY0d4aFkyVW9JbFFpTENJZ0lpazZJdUtBbENKOUxIdHJaWGs2SWtWU1VrOVNJaXhzWVdKbGJEb2lSWEp5YjNJaUxISmxibVJsY2pwNVBUNTVQM011YW5O'
    || 'NEtDSnpjR0Z1SWl4N2RHbDBiR1U2VTNSeWFXNW5LSGtwTEdOb2FXeGtjbVZ1T2xOMGNtbHVaeWg1S1M1emJHbGpaU2d3TERZd0tYMHBPaUxpZ0pRaWZWMTlL'
    || 'VHB1ZFd4c1hYMHBmV1oxYm1OMGFXOXVJRWxqS0hVcGUybG1LSFU5UFc1MWJHd3BjbVYwZFhKdUl1S0FsQ0k3ZEhKNWUzSmxkSFZ5YmlCT2RXMWlaWElvZFNr'
    || 'dWRHOUdhWGhsWkNnektTNXlaWEJzWVdObEtDOHdLeVF2TENJaUtTNXlaWEJzWVdObEtDOWNMaVF2TENJaUtYeDhJakFpZldOaGRHTm9lM0psZEhWeWJpQlRk'
    || 'SEpwYm1jb2RTbDlmV1oxYm1OMGFXOXVJRmhzS0hVcGUzSmxkSFZ5YmlCMGVYQmxiMllnZFQwOUltNTFiV0psY2lJL2RUcE9kVzFpWlhJb2RTbDhmREI5WTI5'
    || 'dWMzUWdlbU05ZTAxRlZEb2k0cHlUSWl4T1QxUmZUVVZVT2lMaW5KY2lMRkJGVGtSSlRrYzZJdUtBbENJc0lrNHZRU0k2SXVLWGl5SjlMSE56UFh0TlJWUTZJ'
    || 'azFGVkNJc1RrOVVYMDFGVkRvaVRrOVVJRTFGVkNJc1VFVk9SRWxPUnpvaVVFVk9SRWxPUnlJc0lrNHZRU0k2SWs0dlFTSjlMRnBzUFh0TlJWUTZJbTFsZENJ'
    || 'c1RrOVVYMDFGVkRvaWJtOTBiV1YwSWl4UVJVNUVTVTVIT2lKd1pXNWthVzVuSWl3aVRpOUJJam9pYm1FaWZUdG1kVzVqZEdsdmJpQkVZeWg3ZGpwMUxHOXVU'
    || 'M0JsYmpwbWZTbDdZMjl1YzNRZ1lUMTFMblpsY21ScFkzUTlQVDBpVGs5VVgwMUZWQ0kvSW1KaFpDSTZkUzUyWlhKa2FXTjBQVDA5SWsxRlZDSS9JbWR2YjJR'
    || 'aU9uVXVkbVZ5WkdsamREMDlQU0pOUlZSZlYwbFVTRjlRUlU1RVNVNUhJajhpZDJGeWJpSTZJbWxrYkdVaUxIZzlkUzUxYm1GMllXbHNZV0pzWlQ4aVVFOURJ'
    || 'SE4xWTJObGMzTTZJRzV2ZENCaWRXbHNkQ0k2ZFM1MlpYSmthV04wUFQwOUlrNVBWRjlTVlU0aVB5SlFUME1nYzNWalkyVnpjem9nYm05MElITmpiM0psWkNJ'
    || 'NllGQlBReUJ6ZFdOalpYTnpPaUFrZTNVdWJXVjBmU0J2WmlBa2UzVXVjMk52Y21Wa2ZTQmpjbWwwWlhKcFlTQnRaWFJnS3loMUxuQmxibVJwYm1jL1lDd2dK'
    || 'SHQxTG5CbGJtUnBibWQ5SUhCbGJtUnBibWRnT2lJaUtTeE9QWE11YW5ONGN5aHpMa1p5WVdkdFpXNTBMSHRqYUdsc1pISmxianBiY3k1cWMzZ29Jbk53WVc0'
    || 'aUxIdGpiR0Z6YzA1aGJXVTZJbkJ2WXkxamFHbHdYMTl1ZFcwaUxHTm9hV3hrY21WdU9uVXVkVzVoZG1GcGJHRmliR1Y4ZkhVdWRtVnlaR2xqZEQwOVBTSk9U'
    || 'MVJmVWxWT0lqOGk0b0NVSWpwZ0pIdDFMbTFsZEgwdkpIdDFMbk5qYjNKbFpIMWdmU2tzY3k1cWMzZ29Jbk53WVc0aUxIdGpiR0Z6YzA1aGJXVTZJbkJ2WXkx'
    || 'amFHbHdYMTkzYjNKa0lpeGphR2xzWkhKbGJqcDFMblZ1WVhaaGFXeGhZbXhsUHlKdWIzUWdZblZwYkhRaU9uVXVkbVZ5WkdsamREMDlQU0pPVDFSZlVsVk9J'
    || 'ajhpYm05MElITmpiM0psWkNJNkltMWxkQ0o5S1N4MUxtNXZkRTFsZEQ5ekxtcHplSE1vSW5Od1lXNGlMSHRqYkdGemMwNWhiV1U2SW5Cdll5MWphR2x3WDE5'
    || 'bWJHRm5JaXhqYUdsc1pISmxianBiZFM1dWIzUk5aWFFzSWlCbVlXbHNaV1FpWFgwcE9tNTFiR3dzZFM1d1pXNWthVzVuSmlZaGRTNXViM1JOWlhRL2N5NXFj'
    || 'M2h6S0NKemNHRnVJaXg3WTJ4aGMzTk9ZVzFsT2lKd2IyTXRZMmhwY0Y5ZlpteGhaeUlzWTJocGJHUnlaVzQ2VzNVdWNHVnVaR2x1Wnl3aUlIQmxibVJwYm1j'
    || 'aVhYMHBPbTUxYkd4ZGZTazdjbVYwZFhKdUlHWS9jeTVxYzNnb0ltSjFkSFJ2YmlJc2UzUjVjR1U2SW1KMWRIUnZiaUlzSW1SaGRHRXRjRzlqSWpwMUxuWmxj'
    || 'bVJwWTNRc1kyeGhjM05PWVcxbE9pSndiMk10WTJocGNDQndiMk10WTJocGNDMHRJaXRoTEc5dVEyeHBZMnM2Wml3aVlYSnBZUzFzWVdKbGJDSTZlQ3gwYVhS'
    || 'c1pUcDRMR05vYVd4a2NtVnVPazU5S1RwekxtcHplQ2dpYzNCaGJpSXNleUprWVhSaExYQnZZeUk2ZFM1MlpYSmthV04wTEdOc1lYTnpUbUZ0WlRvaWNHOWpM'
    || 'V05vYVhBZ2NHOWpMV05vYVhBdExTSXJZU3NpSUhCdll5MWphR2x3TFMxemRHRjBhV01pTENKaGNtbGhMV3hoWW1Wc0lqcDRMSFJwZEd4bE9uZ3NZMmhwYkdS'
    || 'eVpXNDZUbjBwZldaMWJtTjBhVzl1SUhWektIdGpjbWwwWlhKcFlUcDFMSFk2Wml4d1lXNWxiRHBoTEhabGNtUnBZM1JRWVc1bGJEcDRmU2w3ZG1GeUlFTTdZ'
    || 'Mjl1YzNRZ1RqMG9LRU05ZFM1bWFXNWtLSGs5UG5rdVkyOXRjR0Z5WVdKcGJHbDBlU2twUFQxdWRXeHNQM1p2YVdRZ01EcERMbU52YlhCaGNtRmlhV3hwZEhr'
    || 'cFB6OGlJanR5WlhSMWNtNGdjeTVxYzNoektITXVSbkpoWjIxbGJuUXNlMk5vYVd4a2NtVnVPbHR6TG1wemVDaDBkQ3g3ZEdsMGJHVTZJbFpsY21ScFkzUWlM'
    || 'SGRwWkdVNklUQXNhR2x1ZERvaVEyOTFiblJsWkNCbWNtOXRJSFJvWlNCamNtbDBaWEpwWVNCaVpXeHZkeTRnVGk5QklHTnlhWFJsY21saElHRnlaU0JsZUdO'
    || 'c2RXUmxaQ0JtY205dElIUm9aU0JrWlc1dmJXbHVZWFJ2Y2k0aUxHTm9hV3hrY21WdU9uTXVhbk40S0ZsbExIdHdZVzVsYkRwNFB6OWhMSGRvWlc1TmFYTnph'
    || 'VzVuT25NdWFuTjRLSE11Um5KaFoyMWxiblFzZTJOb2FXeGtjbVZ1T2lKVWFHVWdjR3hoYmlCemRHVndJR0oxYVd4a2N5QjBhR1VnYzJOdmNtVmpZWEprSUha'
    || 'cFpYZHpMaUJHYVd4c0lHbHVJSFJvWlNCelpYUjBhVzVuY3lCaGRDQjBhR1VnZEc5d0lHOW1JSFJvWlNCelkzSnBjSFFnWVc1a0lISjFiaUJwZENCaFoyRnBi'
    || 'aUIwYnlCb1lYWmxJSFJvYVhNZ1VFOURJSE5qYjNKbFpDNGlmU2tzWTJocGJHUnlaVzQ2Y3k1cWMzaHpLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbkJ2WTE5'
    || 'ZmRtVnlaR2xqZENCd2IyTmZYM1psY21ScFkzUXRMU0lyS0dZdWRtVnlaR2xqZEQwOVBTSk9UMVJmVFVWVUlqOGlZbUZrSWpwbUxuWmxjbVJwWTNROVBUMGlU'
    || 'VVZVSWo4aVoyOXZaQ0k2Wmk1MlpYSmthV04wUFQwOUlrMUZWRjlYU1ZSSVgxQkZUa1JKVGtjaVB5SjNZWEp1SWpvaWFXUnNaU0lwTEdOb2FXeGtjbVZ1T2x0'
    || 'ekxtcHplQ2dpWkdsMklpeDdZMnhoYzNOT1lXMWxPaUp3YjJOZlgyaGxZV1JzYVc1bElpeGphR2xzWkhKbGJqcG1MbWhsWVdSc2FXNWxmU2tzY3k1cWMzZ29J'
    || 'bkFpTEh0amJHRnpjMDVoYldVNkluQnZZMTlmY21WaFpDSXNZMmhwYkdSeVpXNDZaaTV5WldGa1ZHaHBjMzBwTEhNdWFuTjRLQ0prYVhZaUxIdGpiR0Z6YzA1'
    || 'aGJXVTZJbkJ2WTE5ZmRHRnNiSGtpTEdOb2FXeGtjbVZ1T2xzaVRVVlVJaXdpVGs5VVgwMUZWQ0lzSWxCRlRrUkpUa2NpTENKT0wwRWlYUzV0WVhBb2VUMCtl'
    || 'Mk52Ym5OMElGODllVDA5UFNKTlJWUWlQMll1YldWME9uazlQVDBpVGs5VVgwMUZWQ0kvWmk1dWIzUk5aWFE2ZVQwOVBTSlFSVTVFU1U1SElqOW1MbkJsYm1S'
    || 'cGJtYzZaaTV1WVR0eVpYUjFjbTRnY3k1cWMzaHpLQ0p6Y0dGdUlpeDdZMnhoYzNOT1lXMWxPaUp3YjJOZlgzUnBZMnNnY0c5algxOTBhV05yTFMwaUsxcHNX'
    || 'M2xkTEdOb2FXeGtjbVZ1T2x0ekxtcHplQ2dpWWlJc2UyTm9hV3hrY21WdU9sOTlLU3dpSUNJc2MzTmJlVjFkZlN4NUtYMHBmU2xkZlNsOUtYMHBMSE11YW5O'
    || 'NEtIUjBMSHQwYVhSc1pUb2lRM0pwZEdWeWFXRWlMSGRwWkdVNklUQXNhR2x1ZERvaVJXRmphQ0IwWVhKblpYUWdhWE1nWkdWeWFYWmxaQ0JtY205dElIbHZk'
    || 'WElnWVdOamIzVnVkQ3dnWVc1a0lHVmhZMmdnY205M0lITm9iM2R6SUhSb1pTQmhjbWwwYUcxbGRHbGpJR0psYUdsdVpDQnBkSE1nYzNSaGRHVXVJaXhqYUds'
    || 'c1pISmxianB6TG1wemVDaFpaU3g3Y0dGdVpXdzZZU3gzYUdWdVRXbHpjMmx1WnpwekxtcHplQ2h6TGtaeVlXZHRaVzUwTEh0amFHbHNaSEpsYmpvaVRtOGdZ'
    || 'M0pwZEdWeWFXRWdhR0YyWlNCaVpXVnVJSE5qYjNKbFpDQmlaV05oZFhObElIUm9aU0IyYVdWM2N5QjBhR1Y1SUhKbFlXUWdkMlZ5WlNCdWIzUWdZblZwYkhR'
    || 'Z1lua2dkR2hwY3lCeWRXNHVJbjBwTEdOb2FXeGtjbVZ1T25NdWFuTjRjeWdpWkdsMklpeDdZMnhoYzNOT1lXMWxPaUp3YjJNaUxHTm9hV3hrY21WdU9sdDFM'
    || 'bTFoY0NoNVBUNXpMbXB6ZUhNb0ltUnBkaUlzZTJOc1lYTnpUbUZ0WlRvaWNHOWpMWEp2ZHlCd2IyTXRjbTkzTFMwaUsxcHNXM2t1YzNSaGRHVmRMR05vYVd4'
    || 'a2NtVnVPbHR6TG1wemVDZ2laR2wySWl4N1kyeGhjM05PWVcxbE9pSndiMk10Y205M1gxOXRZWEpySWl3aVlYSnBZUzFvYVdSa1pXNGlPaUowY25WbElpeGph'
    || 'R2xzWkhKbGJqcDZZMXQ1TG5OMFlYUmxYWDBwTEhNdWFuTjRjeWdpWkdsMklpeDdZMnhoYzNOT1lXMWxPaUp3YjJNdGNtOTNYMTlpYjJSNUlpeGphR2xzWkhK'
    || 'bGJqcGJjeTVxYzNoektDSmthWFlpTEh0amJHRnpjMDVoYldVNkluQnZZeTF5YjNkZlgzUnZjQ0lzWTJocGJHUnlaVzQ2VzNNdWFuTjRLQ0p6Y0dGdUlpeDdZ'
    || 'MnhoYzNOT1lXMWxPaUp3YjJNdGNtOTNYMTlzWVdKbGJDSXNZMmhwYkdSeVpXNDZlUzVzWVdKbGJIeDhlUzVqYjJSbGZTa3NjeTVxYzNnb0luTndZVzRpTEh0'
    || 'amJHRnpjMDVoYldVNkluQnZZeTF5YjNkZlgzTjBZWFJsSUhCdll5MXliM2RmWDNOMFlYUmxMUzBpSzFwc1cza3VjM1JoZEdWZExHTm9hV3hrY21WdU9uTnpX'
    || 'M2t1YzNSaGRHVmRmU2xkZlNrc2VTNTNhSGsvY3k1cWMzZ29JbkFpTEh0amJHRnpjMDVoYldVNkluQnZZeTF5YjNkZlgzZG9lU0lzWTJocGJHUnlaVzQ2ZVM1'
    || 'M2FIbDlLVHB1ZFd4c0xIa3VZWEpwZEdodFpYUnBZejl6TG1wemVDZ2ljQ0lzZTJOc1lYTnpUbUZ0WlRvaWNHOWpMWEp2ZDE5ZmJXRjBhQ0lzWTJocGJHUnla'
    || 'VzQ2Y3k1cWMzZ29JbU52WkdVaUxIdGphR2xzWkhKbGJqcDVMbUZ5YVhSb2JXVjBhV045S1gwcE9uTXVhbk40S0NKd0lpeDdZMnhoYzNOT1lXMWxPaUp3YjJN'
    || 'dGNtOTNYMTl0WVhSb0lIQnZZeTF5YjNkZlgyMWhkR2d0TFc1dmJtVWlMR05vYVd4a2NtVnVPbk11YW5ONGN5Z2ljM0JoYmlJc2UyTm9hV3hrY21WdU9sc2lk'
    || 'R0Z5WjJWMElDSXNlUzUwWVhKblpYUTlQVDF1ZFd4c1B5TGlnSlFpT21WbEtIa3VkR0Z5WjJWMEtTeDVMblZ1YVhSelB5SWdJaXQ1TG5WdWFYUnpPaUlpTENJ'
    || 'Z3dyY2dZV04wZFdGc0lHNXZkQ0JoZG1GcGJHRmliR1VpWFgwcGZTa3NlUzUzYUhsT2IzUS9jeTVxYzNnb0luQWlMSHRqYkdGemMwNWhiV1U2SW5Cdll5MXli'
    || 'M2RmWDNCbGJtUWlMR05vYVd4a2NtVnVPbmt1ZDJoNVRtOTBmU2s2Ym5Wc2JDeDVMbkpsYzI5c2RtVnpWMmhsYmo5ekxtcHplSE1vSW5BaUxIdGpiR0Z6YzA1'
    || 'aGJXVTZJbkJ2WXkxeWIzZGZYM2RvWlc0aUxHTm9hV3hrY21WdU9sc2lVbVZ6YjJ4MlpYTWdkMmhsYmpvZ0lpeDVMbkpsYzI5c2RtVnpWMmhsYmwxOUtUcHVk'
    || 'V3hzTEhNdWFuTjRjeWdpWkd3aUxIdGpiR0Z6YzA1aGJXVTZJbkJ2WXkxeWIzZGZYMjFsZEdFaUxHTm9hV3hrY21WdU9sdHpMbXB6ZUhNb0ltUnBkaUlzZTJO'
    || 'b2FXeGtjbVZ1T2x0ekxtcHplQ2dpWkhRaUxIdGphR2xzWkhKbGJqb2lTRzkzSUhSb1pTQjBZWEpuWlhRZ2QyRnpJSE5sZENKOUtTeHpMbXB6ZUNnaVpHUWlM'
    || 'SHRqYUdsc1pISmxianA1TG1SbGNtbDJZWFJwYjI1OGZITXVhbk40S0NKbGJTSXNlMk5vYVd4a2NtVnVPaUpPYjNRZ2MzUmhkR1ZrSU9LQWxDQjBjbVZoZENC'
    || 'MGFHbHpJSFJoY21kbGRDQmhjeUIxYm1WNGNHeGhhVzVsWkM0aWZTbDlLVjE5S1N4NUxtSmhjMmx6UDNNdWFuTjRjeWdpWkdsMklpeDdZMmhwYkdSeVpXNDZX'
    || 'M011YW5ONEtDSmtkQ0lzZTJOb2FXeGtjbVZ1T2lKQ1lYTnBjeUJ2WmlCMGFHVWdZV04wZFdGc0luMHBMSE11YW5ONEtDSmtaQ0lzZTJOb2FXeGtjbVZ1T25N'
    || 'dWFuTjRLQ0pqYjJSbElpeDdZMmhwYkdSeVpXNDZlUzVpWVhOcGMzMHBmU2xkZlNrNmJuVnNiRjE5S1YxOUtWMTlMSGt1WTI5a1pTa3BMRTQvY3k1cWMzZ29J'
    || 'bkFpTEh0amJHRnpjMDVoYldVNkluQnZZMTlmYm05MFpTSXNZMmhwYkdSeVpXNDZUbjBwT201MWJHeGRmU2w5S1gwcFhYMHBmV1oxYm1OMGFXOXVJRUZqS0hV'
    || 'c1ppbDdZMjl1YzNRZ1lUMTFMbU4xYzNSdmJXbDZZWFJwYjI0L1AzdDlMSGc5S0dFdWNHRnVaV3h6UHo5YlhTa3ViV0Z3S0VNOVBpaDdhV1E2UXk1cFpDeHNZ'
    || 'V0psYkRwRExuUnBkR3hsTEdsamIyNDZJblJoWW14bElpeHdZVzVsYkhNNlcwTXVhV1JkTEhKbGJtUmxjam9vS1QwK2N5NXFjM2dvWVhNc2UzQmhlV3h2WVdR'
    || 'NmRTeHpjR1ZqT2tOOUtYMHBLU3hPUFdFdWMyVmpkR2x2Ymw5dmNtUmxjajgvVzEwN2NtVjBkWEp1V3k0dUxtWXNMaTR1ZUYwdWJXRndLRU05UG50MllYSWdl'
    || 'VHR5WlhSMWNtNTdMaTR1UXl4c1lXSmxiRHBETG1sa1BUMDlJbkJ2WTE5emRXTmpaWE56SWo5RExteGhZbVZzT2lnb2VUMWhMbk5sWTNScGIyNWZiR0ZpWld4'
    || 'ektUMDliblZzYkQ5MmIybGtJREE2ZVZ0RExtbGtYU2svUDBNdWJHRmlaV3g5ZlNrdWMyOXlkQ2dvUXl4NUtUMCtlMk52Ym5OMElGODlUaTVwYm1SbGVFOW1L'
    || 'RU11YVdRcExIYzlUaTVwYm1SbGVFOW1LSGt1YVdRcE8zSmxkSFZ5YmloZlBEQS9UaTVzWlc1bmRHZzZYeWt0S0hjOE1EOU9MbXhsYm1kMGFEcDNLWDBwZlda'
    || 'MWJtTjBhVzl1SUdGektIdHdZWGxzYjJGa09uVXNjM0JsWXpwbWZTbDdkbUZ5SUVJN1kyOXVjM1FnWVQxMUxuQmhibVZzYzF0bUxtbGtYU3g0UFdFbUppRjJi'
    || 'aWhoS1Q5aExuSnZkM002VzEwc1RqMTRMbTFoY0NoTVBUNU9kQ2hNTGxaQlRGVkZLU2tzUXoxT0xtVjJaWEo1S0V3OVBrd2hQVDF1ZFd4c0tTeDVQVTFoZEdn'
    || 'dWJXbHVLREFzTGk0dVRpNXRZWEFvVEQwK1REOC9NQ2twTEhjOVRXRjBhQzV0WVhnb01Dd3VMaTVPTG0xaGNDaE1QVDVNUHo4d0tTa3RlWHg4TVR0eVpYUjFj'
    || 'bTRnY3k1cWMzZ29Jbk5sWTNScGIyNGlMSHR6ZEhsc1pUcDdaM0pwWkVOdmJIVnRiam9pTVNBdklDMHhJaXh0YVc1WGFXUjBhRG93ZlN3aVpHRjBZUzF2Ym1W'
    || 'emFHOTBJam9pWTNWemRHOXRMWEJoYm1Wc0lpeGphR2xzWkhKbGJqcHpMbXB6ZUNoWlpTeDdjR0Z1Wld3NllTeGphR2xzWkhKbGJqcG1MbXRwYm1ROVBUMGlk'
    || 'R0ZpYkdVaVAzTXVhbk40S0hwMExIdHliM2R6T25nc2JXRjRPbVl1YkdsdGFYUXNZMjlzY3pwUFltcGxZM1F1YTJWNWN5aDRXekJkUHo5N2ZTa3ViV0Z3S0V3'
    || 'OVBpaDdhMlY1T2t4OUtTbDlLVHBEUDJZdWEybHVaRDA5UFNKdFpYUnlhV01pUDNndWJHVnVaM1JvSVQwOU1YeDhZU1ltSVhadUtHRXBKaVpoTG5SeWRXNWpZ'
    || 'WFJsWkQ5ekxtcHplQ2dpY0NJc2UzSnZiR1U2SW1Gc1pYSjBJaXhqYUdsc1pISmxiam9pUVNCdFpYUnlhV01nZG1sbGR5QnRkWE4wSUhKbGRIVnliaUJsZUdG'
    || 'amRHeDVJRzl1WlNCeWIzY3VJbjBwT25NdWFuTjRjeWdpWkd3aUxIdGphR2xzWkhKbGJqcGJjeTVxYzNnb0ltUjBJaXg3WTJocGJHUnlaVzQ2VTNSeWFXNW5L'
    || 'Q2dvUWoxNFd6QmRLVDA5Ym5Wc2JEOTJiMmxrSURBNlFpNU1RVUpGVENrL1B5SWlLWDBwTEhNdWFuTjRLQ0prWkNJc2UzTjBlV3hsT250bWIyNTBVMmw2WlRv'
    || 'ek5peHRZWEpuYVc0NklqaHdlQ0F3SWl4bWIyNTBWbUZ5YVdGdWRFNTFiV1Z5YVdNNkluUmhZblZzWVhJdGJuVnRjeUo5TEdOb2FXeGtjbVZ1T21WbEtFNWJN'
    || 'RjBwZlNsZGZTazZjeTVxYzNnb0ltUnBkaUlzZTNOMGVXeGxPbnRrYVhOd2JHRjVPaUpuY21sa0lpeG5ZWEE2TVRKOUxHTm9hV3hrY21WdU9uZ3ViV0Z3S0No'
    || 'TUxFRXBQVDU3WTI5dWMzUWdTRDFPVzBGZFB6OHdMSEpsUFMxNUwzY3FNVEF3TEVjOUtFZ3RlU2t2ZHlveE1EQTdjbVYwZFhKdUlITXVhbk40Y3lnaVpHbDJJ'
    || 'aXg3YzNSNWJHVTZlMlJwYzNCc1lYazZJbWR5YVdRaUxHZHlhV1JVWlcxd2JHRjBaVU52YkhWdGJuTTZJbTFwYm0xaGVDZ3hNREJ3ZUN3Z01XWnlLU0J0YVc1'
    || 'dFlYZ29PREJ3ZUN3Z00yWnlLU0J0YVc1dFlYZ29OakJ3ZUN3Z01XWnlLU0lzWjJGd09qRXlMR0ZzYVdkdVNYUmxiWE02SW1ObGJuUmxjaUo5TEdOb2FXeGtj'
    || 'bVZ1T2x0ekxtcHplQ2dpYzNCaGJpSXNlM04wZVd4bE9udHZkbVZ5Wm14dmQxZHlZWEE2SW1GdWVYZG9aWEpsSW4wc1kyaHBiR1J5Wlc0NlUzUnlhVzVuS0V3'
    || 'dVRFRkNSVXcvUHlJaUtYMHBMSE11YW5ONGN5Z2laR2wySWl4N2NtOXNaVG9pYVcxbklpd2lZWEpwWVMxc1lXSmxiQ0k2WUNSN1UzUnlhVzVuS0V3dVRFRkNS'
    || 'VXdwZlRvZ0pIdGxaU2hJS1gxZ0xITjBlV3hsT250b1pXbG5hSFE2TWpJc2NHOXphWFJwYjI0NkluSmxiR0YwYVhabElpeGlZV05yWjNKdmRXNWtPaUoyWVhJ'
    || 'b0xTMXNhVzVsTENBalpUUmxOMlZqS1NKOUxHTm9hV3hrY21WdU9sdHpMbXB6ZUNnaVpHbDJJaXg3YzNSNWJHVTZlM0J2YzJsMGFXOXVPaUpoWW5OdmJIVjBa'
    || 'U0lzYkdWbWREcGdKSHROWVhSb0xtMXBiaWh5WlN4SEtYMGxZQ3gzYVdSMGFEcGdKSHROWVhSb0xtRmljeWhITFhKbEtYMGxZQ3hvWldsbmFIUTZJakV3TUNV'
    || 'aUxHSmhZMnRuY205MWJtUTZJblpoY2lndExXRmpZMlZ1ZEN3Z0l6RTJOemxoTlNraWZYMHBMSE11YW5ONEtDSmthWFlpTEh0emRIbHNaVHA3Y0c5emFYUnBi'
    || 'MjQ2SW1GaWMyOXNkWFJsSWl4c1pXWjBPbUFrZTNKbGZTVmdMSGRwWkhSb09qRXNhR1ZwWjJoME9pSXhNREFsSWl4aVlXTnJaM0p2ZFc1a09pSjJZWElvTFMx'
    || 'cGJtc3NJQ014TnpJeE1tSXBJbjE5S1YxOUtTeHpMbXB6ZUNnaWMzQmhiaUlzZTNOMGVXeGxPbnQwWlhoMFFXeHBaMjQ2SW5KcFoyaDBJaXhtYjI1MFZtRnlh'
    || 'V0Z1ZEU1MWJXVnlhV002SW5SaFluVnNZWEl0Ym5WdGN5SjlMR05vYVd4a2NtVnVPbVZsS0VncGZTbGRmU3hCS1gwcGZTazZjeTVxYzNnb0luQWlMSHR5YjJ4'
    || 'bE9pSmhiR1Z5ZENJc1kyaHBiR1J5Wlc0NklsWkJURlZGSUcxMWMzUWdZbVVnYm5WdFpYSnBZeTRnVG04Z1kyaGhjblFnZDJGeklHUnlZWGR1TGlKOUtYMHBm'
    || 'U2w5Wm5WdVkzUnBiMjRnUm1Nb2RTbDdkbUZ5SUhnc1RqdGpiMjV6ZENCbVBTaDRQWFU5UFc1MWJHdy9kbTlwWkNBd09uVXVZblZwYkdSbGNsOTFjbXdwUFQx'
    || 'dWRXeHNQM1p2YVdRZ01EcDRMbTFoZEdOb0tDOWVhSFIwY0hNNlhDOWNMMkZ3Y0Z3dWMyNXZkMlpzWVd0bFhDNWpiMjFjTHloYllTMTZRUzFhTUMwNVh5MWRL'
    || 'eWxjTHloYllTMTZRUzFhTUMwNVh5MWRLeWxjTHlOY0wzTjBjbVZoYld4cGRDMWhjSEJ6WEM5YlFTMWFNQzA1WDEwclhDNWJRUzFhTUMwNVgxMHJYQzViUVMx'
    || 'YU1DMDVYMTBySkM4cExHRTlLRTQ5ZFQwOWJuVnNiRDkyYjJsa0lEQTZkUzUyYVdWM1pYSmZkWEpzS1QwOWJuVnNiRDkyYjJsa0lEQTZUaTV0WVhSamFDZ3ZY'
    || 'bWgwZEhCek9sd3ZYQzloY0hCY0xuTnViM2RtYkdGclpWd3VZMjl0WEM5emRISmxZVzFzYVhSY0x5aGJZUzE2UVMxYU1DMDVYeTFkS3lsY0x5aGJZUzE2UVMx'
    || 'YU1DMDVYeTFkS3lsY0x5TmNMMkZ3Y0hOY0wxdGhMWHBCTFZvd0xUbGZMVjBySkM4cE8zSmxkSFZ5YmlGbWZId2hZWHg4WmxzeFhTRTlQV0ZiTVYxOGZHWmJN'
    || 'bDBoUFQxaFd6SmRQMjUxYkd3NlczdHNZV0psYkRvaVFYQndJRzl1YkhraUxHaHlaV1k2ZFM1MmFXVjNaWEpmZFhKc2ZTeDdiR0ZpWld3NklsTm9iM2NnVTI1'
    || 'dmQzTnBaMmgwSWl4b2NtVm1PblV1WW5WcGJHUmxjbDkxY214OVhYMW1kVzVqZEdsdmJpQlZZeWg3Ym1GMmFXZGhkR2x2YmpwMWZTbDdZMjl1YzNRZ1pqMUNi'
    || 'QzUxYzJWU1pXWW9iblZzYkNrc1lUMUdZeWgxS1R0eVpYUjFjbTRnUW13dWRYTmxSV1ptWldOMEtDZ3BQVDU3WTI5dWMzUWdlRDFPUFQ1N1ppNWpkWEp5Wlc1'
    || 'MEppWWhaaTVqZFhKeVpXNTBMbU52Ym5SaGFXNXpLRTR1ZEdGeVoyVjBLU1ltS0dZdVkzVnljbVZ1ZEM1dmNHVnVQU0V4S1gwN2NtVjBkWEp1SUdSdlkzVnRa'
    || 'VzUwTG1Ga1pFVjJaVzUwVEdsemRHVnVaWElvSW5CdmFXNTBaWEprYjNkdUlpeDRLU3dvS1QwK1pHOWpkVzFsYm5RdWNtVnRiM1psUlhabGJuUk1hWE4wWlc1'
    || 'bGNpZ2ljRzlwYm5SbGNtUnZkMjRpTEhncGZTeGJYU2tzWVQ5ekxtcHplSE1vSW1SbGRHRnBiSE1pTEh0amJHRnpjMDVoYldVNkltRndjQzEyYVdWM0xXMWxi'
    || 'blVpTEhKbFpqcG1MQ0prWVhSaExXOXVaWE5vYjNRaU9pSjJhV1YzTFcxbGJuVWlMRzl1UzJWNVJHOTNianA0UFQ1N2RtRnlJRTRzUXp0NExtdGxlVDA5UFNK'
    || 'RmMyTmhjR1VpSmlZb0tFNDlaaTVqZFhKeVpXNTBLU0U5Ym5Wc2JDWW1UaTV2Y0dWdUtTWW1LSGd1Y0hKbGRtVnVkRVJsWm1GMWJIUW9LU3htTG1OMWNuSmxi'
    || 'blF1YjNCbGJqMGhNU3dvUXoxbUxtTjFjbkpsYm5RdWNYVmxjbmxUWld4bFkzUnZjaWdpYzNWdGJXRnllU0lwS1QwOWJuVnNiSHg4UXk1bWIyTjFjeWdwS1gw'
    || 'c1kyaHBiR1J5Wlc0NlczTXVhbk40S0NKemRXMXRZWEo1SWl4N0ltRnlhV0V0YkdGaVpXd2lPaUpCY0hBZ2RtbGxkeUJ2Y0hScGIyNXpJaXgwYVhSc1pUb2lR'
    || 'WEJ3SUhacFpYY2diM0IwYVc5dWN5SXNZMmhwYkdSeVpXNDZjeTVxYzNnb0luTjJaeUlzZTNacFpYZENiM2c2SWpBZ01DQXlOQ0F5TkNJc2QybGtkR2c2SWpJ'
    || 'd0lpeG9aV2xuYUhRNklqSXdJaXhtYVd4c09pSnViMjVsSWl4emRISnZhMlU2SW1OMWNuSmxiblJEYjJ4dmNpSXNjM1J5YjJ0bFYybGtkR2c2SWpFdU5pSXNj'
    || 'M1J5YjJ0bFRHbHVaV05oY0RvaWNtOTFibVFpTEhOMGNtOXJaVXhwYm1WcWIybHVPaUp5YjNWdVpDSXNJbUZ5YVdFdGFHbGtaR1Z1SWpvaWRISjFaU0lzWTJo'
    || 'cGJHUnlaVzQ2Y3k1cWMzZ29JbkJoZEdnaUxIdGtPaUpOT0NBelNETjJOVzB4TXkwMWFEVjJOVTB6SURFMmRqVm9OVzB4TXkwMWRqVm9MVFVpZlNsOUtYMHBM'
    || 'SE11YW5ONEtDSmthWFlpTEh0amJHRnpjMDVoYldVNkltRndjQzEyYVdWM0xXOXdkR2x2Ym5NaUxHTm9hV3hrY21WdU9tRXViV0Z3S0hnOVBuTXVhbk40S0NK'
    || 'aElpeDdhSEpsWmpwNExtaHlaV1lzZEdGeVoyVjBPaUpmWW14aGJtc2lMSEpsYkRvaWJtOXZjR1Z1WlhJZ2JtOXlaV1psY25KbGNpSXNJbUZ5YVdFdGJHRmla'
    || 'V3dpT21Ba2UzZ3ViR0ZpWld4OUlDaHZjR1Z1Y3lCcGJpQmhJRzVsZHlCMFlXSXBZQ3h2YmtOc2FXTnJPaWdwUFQ1N1ppNWpkWEp5Wlc1MEppWW9aaTVqZFhK'
    || 'eVpXNTBMbTl3Wlc0OUlURXBmU3hqYUdsc1pISmxianA0TG14aFltVnNmU3g0TG14aFltVnNLU2w5S1YxOUtUcHVkV3hzZldOdmJuTjBJRXBzUFNKd2IyTmZj'
    || 'M1ZqWTJWemN5STdablZ1WTNScGIyNGdTR01vZTNCaGVXeHZZV1E2ZFN4elpXTjBhVzl1Y3pwbUxITjFZblJwZEd4bE9tRXNZMmhwYkdSeVpXNDZlSDBwZTNa'
    || 'aGNpQnZaU3hWWlN4VFpTeHFaU3hKWlR0amIyNXpkQ0JPUFhVdVkyOXVkR1Y0ZEQ4L2UzMHNlVDFUZEhKcGJtY29UaTVOVDBSRlB6OGlJaWt1ZEc5VmNIQmxj'
    || 'a05oYzJVb0tUMDlQU0pUUVUxUVRFVWlMRjg5S0NodlpUMTFMbU4xYzNSdmJXbDZZWFJwYjI0cFBUMXVkV3hzUDNadmFXUWdNRHB2WlM1MGFYUnNaU2svUDFO'
    || 'MGNtbHVaeWhPTGxOUFRGVlVTVTlPUHo4aVUyNXZkMlpzWVd0bElITnZiSFYwYVc5dUlpa3NkejFUWXloMUtTeENQVzV6S0hVcExFdzllMmxrT2twc0xHeGhZ'
    || 'bVZzT2lKUVQwTWdjM1ZqWTJWemN5SXNaR1Z6WXpvaVZHRnlaMlYwY3l3Z1lXNWtJSGRvWlhSb1pYSWdkR2hsZVNCaGNtVWdiV1YwSWl4cFkyOXVPbmN1ZG1W'
    || 'eVpHbGpkRDA5UFNKT1QxUmZUVVZVSWo4aWQyRnliaUk2SW1Ob1pXTnJJaXhpWVdSblpUcDNMblZ1WVhaaGFXeGhZbXhsZkh4M0xuWmxjbVJwWTNROVBUMGlU'
    || 'azlVWDFKVlRpSS9kbTlwWkNBd09tQWtlM2N1YldWMGZTOGtlM2N1YzJOdmNtVmtmV0FzWW1Ga1oyVlViMjVsT25jdWRtVnlaR2xqZEQwOVBTSk9UMVJmVFVW'
    || 'VUlqOGlZbUZrSWpwM0xuWmxjbVJwWTNROVBUMGlUVVZVSWo4aVoyOXZaQ0k2ZHk1MlpYSmthV04wUFQwOUlrMUZWRjlYU1ZSSVgxQkZUa1JKVGtjaVB5SjNZ'
    || 'WEp1SWpvaWFXUnNaU0lzY0dGdVpXeHpPbHNpY0c5algzTmpiM0psWTJGeVpDSXNJbkJ2WTE5MlpYSmthV04wSWwwc2NtVnVaR1Z5T2lncFBUNXpMbXB6ZUNo'
    || 'MWN5eDdZM0pwZEdWeWFXRTZRaXgyT25jc2NHRnVaV3c2ZFM1d1lXNWxiSE11Y0c5algzTmpiM0psWTJGeVpDeDJaWEprYVdOMFVHRnVaV3c2ZFM1d1lXNWxi'
    || 'SE11Y0c5algzWmxjbVJwWTNSOUtYMHNRVDFtSmlabUxteGxibWQwYUQ5Qll5aDFMR1l1YzI5dFpTaHdaVDArY0dVdWFXUTlQVDFLYkNrL1pqcGJMaTR1Wml4'
    || 'TVhTazZkbTlwWkNBd0xFZzlLRlZsUFhVdVkzVnpkRzl0YVhwaGRHbHZiaWs5UFc1MWJHdy9kbTlwWkNBd09sVmxMbVJsWm1GMWJIUmZjMlZqZEdsdmJpeHla'
    || 'VDBvS0ZObFBVRTlQVzUxYkd3L2RtOXBaQ0F3T2tFdVptbHVaQ2h3WlQwK2NHVXVhV1E5UFQxSUtTazlQVzUxYkd3L2RtOXBaQ0F3T2xObExtbGtLVDgvS0No'
    || 'cVpUMUJQVDF1ZFd4c1AzWnZhV1FnTURwQld6QmRLVDA5Ym5Wc2JEOTJiMmxrSURBNmFtVXVhV1FwUHo4aUlpeGJSeXhZWFQxaVpTNTFjMlZUZEdGMFpTaHla'
    || 'U2tzVmowb1FUMDliblZzYkQ5MmIybGtJREE2UVM1bWFXNWtLSEJsUFQ1d1pTNXBaRDA5UFVjcEtUOC9LRUU5UFc1MWJHdy9kbTlwWkNBd09rRmJNRjBwTzJs'
    || 'bUtIVXVabUYwWVd3cGNtVjBkWEp1SUhNdWFuTjRLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbUZ3Y0NCaGNIQXRMVzV2Ym1GMklpeGphR2xzWkhKbGJqcHpM'
    || 'bXB6ZUhNb0ltUnBkaUlzZTJOc1lYTnpUbUZ0WlRvaVptRjBZV3dpTENKa1lYUmhMVzl1WlhOb2IzUWlPaUptWVhSaGJDSXNZMmhwYkdSeVpXNDZXM011YW5O'
    || 'NEtDSm9NU0lzZTJOb2FXeGtjbVZ1T2lKVWFHbHpJR0Z3Y0NCallXNXViM1FnYzJodmR5QmhibmwwYUdsdVp5SjlLU3h6TG1wemVDZ2lZMjlrWlNJc2UyTm9h'
    || 'V3hrY21WdU9uVXVabUYwWVd4OUtWMTlLWDBwTzJOdmJuTjBJRVpsUFNFaFFTWW1RUzVzWlc1bmRHZytNQ3hPWlQxekxtcHplSE1vY3k1R2NtRm5iV1Z1ZEN4'
    || 'N1kyaHBiR1J5Wlc0Nlczay9jeTVxYzNnb0ltUnBkaUlzZTJOc1lYTnpUbUZ0WlRvaVltRnVibVZ5SUdKaGJtNWxjaTB0YzJGdGNHeGxJaXdpWkdGMFlTMXZi'
    || 'bVZ6YUc5MElqb2ljMkZ0Y0d4bExXSmhibTVsY2lJc1kyaHBiR1J5Wlc0NklsTkJUVkJNUlNCRVFWUkJJT0tBbENCMGFHVnpaU0J1ZFcxaVpYSnpJR052YldV'
    || 'Z1puSnZiU0J6WldWa1pXUWdabWw0ZEhWeVpYTXNJRzV2ZENCbWNtOXRJSGx2ZFhJZ1lXTmpiM1Z1ZENKOUtUcHVkV3hzTEhNdWFuTjRjeWdpYUdWaFpHVnlJ'
    || 'aXg3WTJ4aGMzTk9ZVzFsT2lKaGNIQmZYMmhsWVdRaUxHTm9hV3hrY21WdU9sdHpMbXB6ZUhNb0ltUnBkaUlzZTJOb2FXeGtjbVZ1T2x0ekxtcHplQ2dpYURF'
    || 'aUxIdGphR2xzWkhKbGJqcFdQMVl1YkdGaVpXdzZYMzBwTEhNdWFuTjRjeWdpY0NJc2UyTnNZWE56VG1GdFpUb2lZWEJ3WDE5emRXSWlMR05vYVd4a2NtVnVP'
    || 'bHNpWW5WcGJIUWdhVzRnSWl4ekxtcHplQ2dpWTI5a1pTSXNlMk5vYVd4a2NtVnVPbE4wY21sdVp5aE9Ma0pWU1V4VVgwbE9QejhpNG9DVUlpbDlLU3hPTGxk'
    || 'SlRrUlBWMTlFUVZsVFAzTXVhbk40Y3loekxrWnlZV2R0Wlc1MExIdGphR2xzWkhKbGJqcGJJaURDdHlBaUxGTjBjbWx1WnloT0xsZEpUa1JQVjE5RVFWbFRL'
    || 'U3dpTFdSaGVTQjNhVzVrYjNjaVhYMHBPbTUxYkd3c1RpNUNWVWxNVkY5QlZEOXpMbXB6ZUhNb2N5NUdjbUZuYldWdWRDeDdZMmhwYkdSeVpXNDZXeUlnd3Jj'
    || 'Z0lpeFRkSEpwYm1jb1RpNUNWVWxNVkY5QlZDa3VjMnhwWTJVb01Dd3hPU2t1Y21Wd2JHRmpaU2dpVkNJc0lpQWlLVjE5S1RwdWRXeHNYWDBwWFgwcExITXVh'
    || 'bk40Y3lnaVpHbDJJaXg3WTJ4aGMzTk9ZVzFsT2lKaGNIQmZYMmhsWVdSeWFXZG9kQ0lzWTJocGJHUnlaVzQ2VzNNdWFuTjRLRVJqTEh0Mk9uY3NiMjVQY0dW'
    || 'dU9rWmxQeWdwUFQ1WUtFcHNLVHAyYjJsa0lEQjlLU3h6TG1wemVDaFdZeXg3Y0dGNWJHOWhaRHAxZlNrc2N5NXFjM2dvVldNc2UyNWhkbWxuWVhScGIyNDZk'
    || 'UzV1WVhacFoyRjBhVzl1ZlNsZGZTbGRmU2tzY3k1cWMzZ29RbU1zZTNCaGVXeHZZV1E2ZFgwcExIVXVZM1Z6ZEc5dGFYcGhkR2x2Ymw5bGNuSnZjajl6TG1w'
    || 'emVDZ2ljQ0lzZTNKdmJHVTZJbUZzWlhKMElpeGpiR0Z6YzA1aGJXVTZJbkJoYm1Wc0xXVnljbTl5SWl4amFHbHNaSEpsYmpwMUxtTjFjM1J2YldsNllYUnBi'
    || 'MjVmWlhKeWIzSjlLVHB1ZFd4c1hYMHBPMmxtS0NGR1pTbHlaWFIxY200Z2N5NXFjM2dvSW1ScGRpSXNlMk5zWVhOelRtRnRaVG9pWVhCd0lHRndjQzB0Ym05'
    || 'dVlYWWlMR05vYVd4a2NtVnVPbk11YW5ONGN5Z2laR2wySWl4N1kyeGhjM05PWVcxbE9pSnRZV2x1SWl4amFHbHNaSEpsYmpwYlRtVXNjeTVxYzNoektDSnRZ'
    || 'V2x1SWl4N1kyeGhjM05PWVcxbE9pSm5jbWxrSWl3aVpHRjBZUzF2Ym1WemFHOTBJam9pYzJWamRHbHZiaUlzSW1SaGRHRXRjMlZqZEdsdmJpSTZJbk5wYm1k'
    || 'c1pTSXNZMmhwYkdSeVpXNDZXM2dzS0Nnb1NXVTlkUzVqZFhOMGIyMXBlbUYwYVc5dUtUMDliblZzYkQ5MmIybGtJREE2U1dVdWNHRnVaV3h6S1Q4L1cxMHBM'
    || 'bTFoY0Nod1pUMCtjeTVxYzNoektHSmxMa1p5WVdkdFpXNTBMSHRqYUdsc1pISmxianBiY3k1cWMzZ29JbWd5SWl4N2MzUjViR1U2ZTJkeWFXUkRiMngxYlc0'
    || 'NklqRWdMeUF0TVNKOUxHTm9hV3hrY21WdU9uQmxMblJwZEd4bGZTa3NjeTVxYzNnb1lYTXNlM0JoZVd4dllXUTZkU3h6Y0dWak9uQmxmU2xkZlN4d1pTNXBa'
    || 'Q2twTEhNdWFuTjRLSFZ6TEh0amNtbDBaWEpwWVRwQ0xIWTZkeXh3WVc1bGJEcDFMbkJoYm1Wc2N5NXdiMk5mYzJOdmNtVmpZWEprTEhabGNtUnBZM1JRWVc1'
    || 'bGJEcDFMbkJoYm1Wc2N5NXdiMk5mZG1WeVpHbGpkSDBwWFgwcExITXVhbk40S0ZkakxIdDlLVjE5S1gwcE8yTnZibk4wSUV4bFBVRXViV0Z3S0hCbFBUNG9l'
    || 'eTR1TG5CbExITjBZWFIxY3pwd1pTNXpkR0YwZFhNL1B5UmpLSFVzY0dVcGZTa3BPM0psZEhWeWJpQnpMbXB6ZUhNb0ltUnBkaUlzZTJOc1lYTnpUbUZ0WlRv'
    || 'aVlYQndJaXhqYUdsc1pISmxianBiY3k1cWMzZ29RMk1zZTNOdmJIVjBhVzl1T2w4c2MzVmlkR2wwYkdVNllTeHpaV04wYVc5dWN6cE1aU3hoWTNScGRtVTZS'
    || 'eXh2YmxCcFkyczZXQ3htYjI5ME9uTXVhbk40S0hNdVJuSmhaMjFsYm5Rc2UyTm9hV3hrY21WdU9pSkVZWFJoSUdOdmJXVnpJR1p5YjIwZ2RtbGxkM01nYVc0'
    || 'Z2RHaHBjeUJ6WTJobGJXRXVJRkpsWVdSeklHMWhlU0JpWlNCeVpYVnpaV1FnWm05eUlETXdJSE5sWTI5dVpITWdkMmwwYUdsdUlIbHZkWElnYzJWemMybHZi'
    || 'anNnVW1WbWNtVnphQ0JrWVhSaElHWmxkR05vWlhNZ1lXZGhhVzR1SW4wcGZTa3NjeTVxYzNoektDSmthWFlpTEh0amJHRnpjMDVoYldVNkltMWhhVzRpTEdO'
    || 'b2FXeGtjbVZ1T2x0T1pTeHpMbXB6ZUNnaWJXRnBiaUlzZTJOc1lYTnpUbUZ0WlRvaVozSnBaQ0J5ZGlJc0ltUmhkR0V0YjI1bGMyaHZkQ0k2SW5ObFkzUnBi'
    || 'MjRpTENKa1lYUmhMWE5sWTNScGIyNGlPa2NzWTJocGJHUnlaVzQ2Vmo5V0xuSmxibVJsY2lncE9tNTFiR3g5TEVjcFhYMHBYWDBwZldaMWJtTjBhVzl1SUNS'
    || 'aktIVXNaaWw3WTI5dWMzUWdZVDFtTG5CaGJtVnNjejgvVzEwN2FXWW9ZUzV6YjIxbEtIZzlQblp1S0hVdWNHRnVaV3h6VzNoZEtTWW1JV2R1S0hVdWNHRnVa'
    || 'V3h6VzNoZEtTa3BjbVYwZFhKdUltSmhaQ0k3YVdZb1lTNXpiMjFsS0hnOVBtZHVLSFV1Y0dGdVpXeHpXM2hkS1NrcGNtVjBkWEp1SW1sdVptOGlmV1oxYm1O'
    || 'MGFXOXVJRmRqS0NsN2NtVjBkWEp1SUhNdWFuTjRLQ0ptYjI5MFpYSWlMSHRqYkdGemMwNWhiV1U2SW1Gd2NGOWZabTl2ZENJc2MzUjViR1U2ZTIxaGNtZHBi'
    || 'bFJ2Y0RveU1DeG1iMjUwVTJsNlpUb3hNUzQxTEdOdmJHOXlPaUoyWVhJb0xTMWthVzBwSW4wc1kyaHBiR1J5Wlc0NklrUmhkR0VnWTI5dFpYTWdabkp2YlNC'
    || 'MmFXVjNjeUJwYmlCMGFHbHpJSE5qYUdWdFlTNGdVbVZoWkhNZ2JXRjVJR0psSUhKbGRYTmxaQ0JtYjNJZ016QWdjMlZqYjI1a2N5QjNhWFJvYVc0Z2VXOTFj'
    || 'aUJ6WlhOemFXOXVPeUJTWldaeVpYTm9JR1JoZEdFZ1ptVjBZMmhsY3lCaFoyRnBiaTRpZlNsOVpuVnVZM1JwYjI0Z1ZtTW9lM0JoZVd4dllXUTZkWDBwZTNa'
    || 'aGNpQjVPMk52Ym5OMElHWTlSV01vZFM1amIyNTBaWGgwS1N4YllTeDRYVDFpWlM1MWMyVlRkR0YwWlNodWRXeHNLU3hPUFNnb2VUMW1MbVpwYm1Rb1h6MCtY'
    || 'eTV6ZEdGMFpUMDlQU0pqZFhKeVpXNTBJaWtwUFQxdWRXeHNQM1p2YVdRZ01EcDVMbWxrS1Q4L2JuVnNiQ3hEUFdFL1ppNW1hVzVrS0Y4OVBsOHVhV1E5UFQx'
    || 'aEtUcHVkV3hzTzNKbGRIVnliaUJ6TG1wemVITW9JbVJwZGlJc2UyTnNZWE56VG1GdFpUb2ljR2hoYzJVaUxHTm9hV3hrY21WdU9sdHpMbXB6ZUNnaVpHbDJJ'
    || 'aXg3WTJ4aGMzTk9ZVzFsT2lKd2FHRnpaVjlmY21GcGJDSXNjbTlzWlRvaVozSnZkWEFpTENKaGNtbGhMV3hoWW1Wc0lqb2lSR1Z3Ykc5NWJXVnVkQ0J3YUdG'
    || 'elpTSXNZMmhwYkdSeVpXNDZaaTV0WVhBb1h6MCtjeTVxYzNoektDSmlkWFIwYjI0aUxIdDBlWEJsT2lKaWRYUjBiMjRpTENKa1lYUmhMWEJvWVhObElqcGZM'
    || 'bWxrTEdOc1lYTnpUbUZ0WlRvaWNHaGhjMlZmWDJKMGJpQndhR0Z6WlY5ZlluUnVMUzBpSzE4dWMzUmhkR1VyS0dFOVBUMWZMbWxrUHlJZ2FYTXRiM0JsYmlJ'
    || 'NklpSXBMQ0poY21saExXTjFjbkpsYm5RaU9sOHVjM1JoZEdVOVBUMGlZM1Z5Y21WdWRDSS9Jbk4wWlhBaU9uWnZhV1FnTUN3aVlYSnBZUzFsZUhCaGJtUmxa'
    || 'Q0k2WVQwOVBWOHVhV1FzYjI1RGJHbGphem9vS1QwK2VDaGhQVDA5WHk1cFpEOXVkV3hzT2w4dWFXUXBMR05vYVd4a2NtVnVPbHR6TG1wemVDZ2ljM0JoYmlJ'
    || 'c2UyTnNZWE56VG1GdFpUb2ljR2hoYzJWZlgyeGhZbVZzSWl4amFHbHNaSEpsYmpwZkxteGhZbVZzZlNrc2N5NXFjM2dvSW5Od1lXNGlMSHRqYkdGemMwNWhi'
    || 'V1U2SW5Cb1lYTmxYMTltYVdkMWNtVWlMR05vYVd4a2NtVnVPbDh1Wm1sbmRYSmxmU2tzWHk1dGIyNWxlVDl6TG1wemVDZ2ljM0JoYmlJc2UyTnNZWE56VG1G'
    || 'dFpUb2ljR2hoYzJWZlgyMXZibVY1SWl4amFHbHNaSEpsYmpwZkxtMXZibVY1ZlNrNmJuVnNiRjE5TEY4dWFXUXBLWDBwTEVNL2N5NXFjM2h6S0NKa2FYWWlM'
    || 'SHRqYkdGemMwNWhiV1U2SW5Cb1lYTmxYMTlrWlhSaGFXd2lMR05vYVd4a2NtVnVPbHR6TG1wemVDZ2ljQ0lzZTJOc1lYTnpUbUZ0WlRvaWNHaGhjMlZmWDJK'
    || 'c2RYSmlJaXhqYUdsc1pISmxianBETG1Kc2RYSmlmU2tzY3k1cWMzaHpLQ0p3SWl4N1kyeGhjM05PWVcxbE9pSndhR0Z6WlY5ZlltRnphWE1pTEdOb2FXeGtj'
    || 'bVZ1T2x0ekxtcHplQ2dpYzNSeWIyNW5JaXg3WTJocGJHUnlaVzQ2UXk1bWFXZDFjbVY5S1N4RExtMXZibVY1UDNNdWFuTjRjeWh6TGtaeVlXZHRaVzUwTEh0'
    || 'amFHbHNaSEpsYmpwYklpQW9JaXhETG0xdmJtVjVMQ0lwSWwxOUtUcHVkV3hzTENJZzRvQ1VJQ0lzUXk1aVlYTnBjMTE5S1N4RExtbGtQVDA5VGo5ekxtcHpl'
    || 'Q2dpY0NJc2UyTnNZWE56VG1GdFpUb2ljR2hoYzJWZlgzZG9aWEpsSWl4amFHbHNaSEpsYmpvaVZHaHBjeUJpZFdsc1pDQnBjeUJwYmlCMGFHbHpJSEJvWVhO'
    || 'bExpSjlLVHB6TG1wemVITW9JbkFpTEh0amJHRnpjMDVoYldVNkluQm9ZWE5sWDE5b2IzY2lMR05vYVd4a2NtVnVPbHNpVkc4Z2JXOTJaU0JvWlhKbExDQnpa'
    || 'WFFnZEdocGN5QnBiaUIwYUdVZ2MyTnlhWEIwSUdGdVpDQnlkVzRnYVhRZ1lXZGhhVzQ2SWl3aUlDSXNjeTVxYzNnb0ltTnZaR1VpTEh0amFHbHNaSEpsYmpw'
    || 'RExuTmxkSFJwYm1kOUtWMTlLVjE5S1RwdWRXeHNYWDBwZldaMWJtTjBhVzl1SUVKaktIdHdZWGxzYjJGa09uVjlLWHRqYjI1emRDQm1QVTlpYW1WamRDNXJa'
    || 'WGx6S0hVdWNHRnVaV3h6S1M1bWFXeDBaWElvVGowK1RpRTlQU0pqYjI1MFpYaDBJaWtzWVQxbUxtWnBiSFJsY2loT1BUNW5iaWgxTG5CaGJtVnNjMXRPWFNr'
    || 'cExIZzlaaTVtYVd4MFpYSW9UajArZG00b2RTNXdZVzVsYkhOYlRsMHBKaVloWjI0b2RTNXdZVzVsYkhOYlRsMHBLVHR5WlhSMWNtNGhZUzVzWlc1bmRHZ21K'
    || 'aUY0TG14bGJtZDBhRDl1ZFd4c09uTXVhbk40Y3loekxrWnlZV2R0Wlc1MExIdGphR2xzWkhKbGJqcGJlQzVzWlc1bmRHZy9jeTVxYzNoektDSmthWFlpTEh0'
    || 'amJHRnpjMDVoYldVNkltSmhibTVsY2lCaVlXNXVaWEl0TFdaaGFXd2lMR05vYVd4a2NtVnVPbHQ0TG14bGJtZDBhQ3dpSUc5bUlDSXNaaTVzWlc1bmRHZ3NJ'
    || 'aUJ3WVc1bGJITWdaR2xrSUc1dmRDQnNiMkZrSUNnaUxIZ3VhbTlwYmlnaUxDQWlLU3dpS1M0Z1ZHaGxJRzUxYldKbGNuTWdZbVZzYjNjZ1lYSmxJR2x1WTI5'
    || 'dGNHeGxkR1V1SWwxOUtUcHVkV3hzTEdFdWJHVnVaM1JvUDNNdWFuTjRjeWdpWkdsMklpeDdZMnhoYzNOT1lXMWxPaUppWVc1dVpYSWdZbUZ1Ym1WeUxTMXBi'
    || 'bVp2SWl4amFHbHNaSEpsYmpwYllTNXNaVzVuZEdnc0lpQnZaaUFpTEdZdWJHVnVaM1JvTENJZ2MyVmpkR2x2Ym5NZ2QyVnlaU0J1YjNRZ1luVnBiSFFnWW5r'
    || 'Z2RHaHBjeUJ5ZFc0Z0tDSXNZUzVxYjJsdUtDSXNJQ0lwTENJcExpQlVhR0YwSUdseklHVjRjR1ZqZEdWa0lHOXVJR0VnWkdselkyOTJaWEo1TFc5dWJIa2dj'
    || 'blZ1SU9LQWxDQmxZV05vSUdOaGNtUWdjMkY1Y3lCM2FHbGphQ0J6WlhSMGFXNW5JR1pwYkd4eklHbDBJR2x1TGlKZGZTazZiblZzYkYxOUtYMW1kVzVqZEds'
    || 'dmJpQlJZeWgxS1h0amIyNXpkQ0JtUFdSdlkzVnRaVzUwTG1kbGRFVnNaVzFsYm5SQ2VVbGtLQ0p5YjI5MElpazdhV1lvSVdZcGUyTnZibk52YkdVdVpYSnli'
    || 'M0lvSW05dVpYTm9iM1FnVlVrNklHNXZJQ055YjI5MElHVnNaVzFsYm5RZ2RHOGdiVzkxYm5RZ2FXNTBieUlwTzNKbGRIVnlibjFqYjI1emRDQmhQWGxqS0Nr'
    || 'N2JXTXVZM0psWVhSbFVtOXZkQ2htS1M1eVpXNWtaWElvY3k1cWMzZ29jeTVHY21GbmJXVnVkQ3g3WTJocGJHUnlaVzQ2ZFNoaEtYMHBLWDFtZFc1amRHbHZi'
    || 'aUJqY3loN2VEcDFMSGs2Wml4MmFYTnBZbXhsT21Fc1kyaHBiR1J5Wlc0NmVIMHBlMk52Ym5OMElFNDlZbVV1ZFhObFVtVm1LRzUxYkd3cExGdERMSGxkUFdK'
    || 'bExuVnpaVk4wWVhSbEtIdHNaV1owT2pBc2RHOXdPakI5S1R0eVpYUjFjbTRnWW1VdWRYTmxSV1ptWldOMEtDZ3BQVDU3YVdZb0lXRjhmQ0ZPTG1OMWNuSmxi'
    || 'blFwY21WMGRYSnVPMk52Ym5OMElGODlUaTVqZFhKeVpXNTBMSGM5WHk1dlptWnpaWFJYYVdSMGFDeENQVjh1YjJabWMyVjBTR1ZwWjJoMExFdzlkMmx1Wkc5'
    || 'M0xtbHVibVZ5VjJsa2RHZ3NRVDEzYVc1a2IzY3VhVzV1WlhKSVpXbG5hSFFzU0QxMUt6RXlLM2MrVEQ5MUxYY3RPRHAxS3pFeUxISmxQV1lyT0N0Q1BrRS9a'
    || 'aTFDTFRRNlppczRPM2tvZTJ4bFpuUTZUV0YwYUM1dFlYZ29NaXhJS1N4MGIzQTZUV0YwYUM1dFlYZ29NaXh5WlNsOUtYMHNXM1VzWml4aFhTa3NZVDl6TG1w'
    || 'emVDZ2laR2wySWl4N2NtVm1PazRzWTJ4aGMzTk9ZVzFsT2lKb2IzWmxjaTFrWlhSaGFXd2lMSE4wZVd4bE9udHNaV1owT2tNdWJHVm1kQ3gwYjNBNlF5NTBi'
    || 'M0I5TEdOb2FXeGtjbVZ1T25oOUtUcHVkV3hzZldaMWJtTjBhVzl1SUdkMEtIVXBlMk52Ym5OMElHWTlkSGx3Wlc5bUlIVTlQU0p1ZFcxaVpYSWlQM1U2VG5W'
    || 'dFltVnlLSFVwTzNKbGRIVnliaUJPZFcxaVpYSXVhWE5HYVc1cGRHVW9aaWsvWmpvd2ZXWjFibU4wYVc5dUlIRnNLSFVwZTNKbGRIVnliaUJUZEhKcGJtY29k'
    || 'UzVUVkU5U1JWOU9RVTFGUHo5MUxsTlVUMUpGWDBsRVB6OGk0b0NVSWlsOVkyOXVjM1FnV1dNOVczdHJaWGs2SWxOQlRFVlRYMUJGVWw5VFVVWlVJaXhzWVdK'
    || 'bGJEb2lKQzlUY1VaMElpeHdjbVZtYVhnNklpUWlmU3g3YTJWNU9pSkJWa2RmVlZCVUlpeHNZV0psYkRvaVFYWm5JRlZRVkNKOUxIdHJaWGs2SWxSUFZFRk1Y'
    || 'MDVGVkY5VFFVeEZVeUlzYkdGaVpXdzZJazVsZENCellXeGxjeUlzY0hKbFptbDRPaUlrSW4wc2UydGxlVG9pVkU5VVFVeGZWRkpCVGxOQlExUkpUMDVUSWl4'
    || 'c1lXSmxiRG9pVkhodUluMWRPMloxYm1OMGFXOXVJRXRqS0hVcGUzSmxkSFZ5YmlCWll5NXRZWEFvWmowK2UyTnZibk4wSUdFOWRTNXRZWEFvZVQwK1ozUW9l'
    || 'VnRtTG10bGVWMHBLUzVtYVd4MFpYSW9lVDArZVQ0d0tTeDRQV0V1YkdWdVozUm9mSHd4TEU0OVlTNXlaV1IxWTJVb0tIa3NYeWs5UG5rclh5d3dLUzk0TEVN'
    || 'OVlTNXlaV1IxWTJVb0tIa3NYeWs5UG5rcktGOHRUaWtxS2pJc01Da3ZlRHR5WlhSMWNtNTdMaTR1Wml4dFpXRnVPazRzYzNSa09rMWhkR2d1YzNGeWRDaERL'
    || 'WHg4TVgxOUtYMW1kVzVqZEdsdmJpQkhZeWgxTEdZc1lTbDdhV1lvWVQwOVBUQjhmSFU5UFQwd0tYSmxkSFZ5YmlKMllYSW9MUzF6ZFhKbVlXTmxMVElwSWp0'
    || 'amIyNXpkQ0I0UFUxaGRHZ3ViV0Y0S0MweUxFMWhkR2d1YldsdUtESXNLSFV0WmlrdllTa3BPM0psZEhWeWJpQjRQajB3UDJCeVoySmhLREl5TENBeE5qTXNJ'
    || 'RGMwTENBa2V5Z3VNU3Q0THpJcUxqVXBMblJ2Um1sNFpXUW9NaWw5S1dBNllISm5ZbUVvTWpNeUxDQXdMQ0F5T0N3Z0pIc29MakVyTFhndk1pb3VORElwTG5S'
    || 'dlJtbDRaV1FvTWlsOUtXQjlablZ1WTNScGIyNGdaSE1vZFN4bUtYdHlaWFIxY200b1ppNXdjbVZtYVhnL1B5SWlLU3RsWlNoMUtYMW1kVzVqZEdsdmJpQllZ'
    || 'eWg3Y0RwMWZTbDdZMjl1YzNRZ1pqMWxkQ2gxTENKemRXMXRZWEo1SWlrc1cyRXNlRjA5WW1VdWRYTmxVM1JoZEdVb2JuVnNiQ2s3YVdZb0lXWXViR1Z1WjNS'
    || 'b0tYSmxkSFZ5YmlCekxtcHplQ2dpY0NJc2UzTjBlV3hsT250bWIyNTBVMmw2WlRveE1peGpiMnh2Y2pvaWRtRnlLQzB0WkdsdEtTSXNjR0ZrWkdsdVp6b2lN'
    || 'VEp3ZUNBd0luMHNZMmhwYkdSeVpXNDZJazV2SUhOMGIzSmxJR1JoZEdFdUlGTmxkQ0JOUlZKRFNFRk9WRjlUVkU5U1JWTmZWRUZDVEVVZ1lXNWtJRTFGVWtO'
    || 'SVFVNVVYMFJCU1V4WlgxTkJURVZUWDFSQlFreEZMaUo5S1R0amIyNXpkQ0JPUFV0aktHWXBMRU05V3k0dUxtWmRMbk52Y25Rb0tIa3NYeWs5UG1kMEtGOHVV'
    || 'MEZNUlZOZlVFVlNYMU5SUmxRcExXZDBLSGt1VTBGTVJWTmZVRVZTWDFOUlJsUXBLVHR5WlhSMWNtNGdjeTVxYzNoektDSmthWFlpTEh0emRIbHNaVHA3YjNa'
    || 'bGNtWnNiM2RZT2lKaGRYUnZJaXh3YjNOcGRHbHZiam9pY21Wc1lYUnBkbVVpZlN4amFHbHNaSEpsYmpwYmN5NXFjM2h6S0NKMFlXSnNaU0lzZTNOMGVXeGxP'
    || 'bnRpYjNKa1pYSkRiMnhzWVhCelpUb2ljMlZ3WVhKaGRHVWlMR0p2Y21SbGNsTndZV05wYm1jNk1peDNhV1IwYURvaVlYVjBieUo5TEdOb2FXeGtjbVZ1T2x0'
    || 'ekxtcHplQ2dpZEdobFlXUWlMSHRqYUdsc1pISmxianB6TG1wemVITW9JblJ5SWl4N1kyaHBiR1J5Wlc0NlczTXVhbk40S0NKMGFDSXNlM04wZVd4bE9udDBa'
    || 'WGgwUVd4cFoyNDZJbXhsWm5RaUxHWnZiblJUYVhwbE9qRXhMR052Ykc5eU9pSjJZWElvTFMxdGRYUmxaQ2tpTEhCaFpHUnBibWM2SWpSd2VDQXhNSEI0SURa'
    || 'd2VDQXdJaXhtYjI1MFYyVnBaMmgwT2pVd01DeHRhVzVYYVdSMGFEb3hNVEI5TEdOb2FXeGtjbVZ1T2lKVGRHOXlaU0o5S1N4T0xtMWhjQ2g1UFQ1ekxtcHpl'
    || 'Q2dpZEdnaUxIdHpkSGxzWlRwN2RHVjRkRUZzYVdkdU9pSmpaVzUwWlhJaUxHWnZiblJUYVhwbE9qRXhMR052Ykc5eU9pSjJZWElvTFMxdGRYUmxaQ2tpTEhC'
    || 'aFpHUnBibWM2SWpSd2VDQTBjSGdnTm5CNElpeG1iMjUwVjJWcFoyaDBPalV3TUN4M2FXUjBhRG80TUgwc1kyaHBiR1J5Wlc0NmVTNXNZV0psYkgwc2VTNXJa'
    || 'WGtwS1YxOUtYMHBMSE11YW5ONEtDSjBZbTlrZVNJc2UyTm9hV3hrY21WdU9rTXViV0Z3S0NoNUxGOHBQVDV6TG1wemVITW9JblJ5SWl4N1kyaHBiR1J5Wlc0'
    || 'NlczTXVhbk40S0NKMFpDSXNlM04wZVd4bE9udG1iMjUwVTJsNlpUb3hNaXh3WVdSa2FXNW5PaUkxY0hnZ01UQndlQ0ExY0hnZ01DSXNZMjlzYjNJNkluWmhj'
    || 'aWd0TFhSbGVIUXBJaXgzYUdsMFpWTndZV05sT2lKdWIzZHlZWEFpTEcxaGVGZHBaSFJvT2pFMU1DeHZkbVZ5Wm14dmR6b2lhR2xrWkdWdUlpeDBaWGgwVDNa'
    || 'bGNtWnNiM2M2SW1Wc2JHbHdjMmx6SW4wc2RHbDBiR1U2Y1d3b2VTa3NZMmhwYkdSeVpXNDZjV3dvZVNsOUtTeE9MbTFoY0NoM1BUNTdZMjl1YzNRZ1FqMW5k'
    || 'Q2g1VzNjdWEyVjVYU2s3Y21WMGRYSnVJSE11YW5ONEtDSjBaQ0lzZTNOMGVXeGxPbnQzYVdSMGFEbzRNQ3hvWldsbmFIUTZNeklzWW1GamEyZHliM1Z1WkRw'
    || 'SFl5aENMSGN1YldWaGJpeDNMbk4wWkNrc2RHVjRkRUZzYVdkdU9pSmpaVzUwWlhJaUxHWnZiblJUYVhwbE9qRXhMR052Ykc5eU9pSjJZWElvTFMxdGRYUmxa'
    || 'Q2tpTEdKdmNtUmxjbEpoWkdsMWN6b3pMR04xY25OdmNqb2laR1ZtWVhWc2RDSjlMRzl1VFc5MWMyVkZiblJsY2pwTVBUNTRLSHQ0T2t3dVkyeHBaVzUwV0N4'
    || 'NU9rd3VZMnhwWlc1MFdTeHpkRzl5WlU1aGJXVTZjV3dvZVNrc2JXVjBjbWxqT25jdWJHRmlaV3dzZG1Gc2RXVTZaSE1vUWl4M0tTeGhkbWM2WkhNb2R5NXRa'
    || 'V0Z1TEhjcGZTa3NiMjVOYjNWelpVMXZkbVU2VEQwK1lTWW1lQ2g3TGk0dVlTeDRPa3d1WTJ4cFpXNTBXQ3g1T2t3dVkyeHBaVzUwV1gwcExHOXVUVzkxYzJW'
    || 'TVpXRjJaVG9vS1QwK2VDaHVkV3hzS1N4amFHbHNaSEpsYmpwbFpTaENLWDBzZHk1clpYa3BmU2xkZlN4ZktTbDlLVjE5S1N4ekxtcHplQ2hqY3l4N2VEb29Z'
    || 'VDA5Ym5Wc2JEOTJiMmxrSURBNllTNTRLVDgvTUN4NU9paGhQVDF1ZFd4c1AzWnZhV1FnTURwaExua3BQejh3TEhacGMybGliR1U2SVNGaExHTm9hV3hrY21W'
    || 'dU9tRS9jeTVxYzNoektDSmthWFlpTEh0emRIbHNaVHA3Wm05dWRGTnBlbVU2TVRJc2JHbHVaVWhsYVdkb2REb3hMalo5TEdOb2FXeGtjbVZ1T2x0ekxtcHpl'
    || 'Q2dpYzNSeWIyNW5JaXg3WTJocGJHUnlaVzQ2WVM1emRHOXlaVTVoYldWOUtTeHpMbXB6ZUNnaVluSWlMSHQ5S1N4aExtMWxkSEpwWXl3aU9pQWlMR0V1ZG1G'
    || 'c2RXVXNjeTVxYzNnb0ltSnlJaXg3ZlNrc0lsQmxaWElnWVhabk9pQWlMR0V1WVhablhYMHBPbTUxYkd4OUtWMTlLWDFtZFc1amRHbHZiaUJhWXloMUtYdGpi'
    || 'MjV6ZENCbVBXNWxkeUJOWVhBN1ptOXlLR052Ym5OMElHRWdiMllnZFNsN1kyOXVjM1FnZUQxVGRISnBibWNvWVM1VFMxVmZTVVEvUHlJaUtTeE9QV1l1WjJW'
    || 'MEtIZ3BQejk3ZFc1cGRITTZNQ3gzYjNOVGRXMDZNQ3hqYm5RNk1DeDNiM0p6ZEZOMFlYUjFjem9pU0VWQlRGUklXU0o5TzA0dWRXNXBkSE1yUFdkMEtHRXVW'
    || 'VTVKVkZOZlQwNWZTRUZPUkNrc1RpNTNiM05UZFcwclBXZDBLR0V1VjBWRlMxTmZUMFpmVTFWUVVFeFpLU3hPTG1OdWRDczlNVHRqYjI1emRDQkRQVk4wY21s'
    || 'dVp5aGhMbGRQVTE5VFZFRlVWVk0vUHlKSVJVRk1WRWhaSWlrN0tFTTlQVDBpU0VsSFNDSjhmRU05UFQwaVRFOVhJaVltVGk1M2IzSnpkRk4wWVhSMWN5RTlQ'
    || 'U0pJU1VkSUlpa21KaWhPTG5kdmNuTjBVM1JoZEhWelBVTXBMR1l1YzJWMEtIZ3NUaWw5Y21WMGRYSnVXeTR1TG1ZdVpXNTBjbWxsY3lncFhTNXRZWEFvS0Z0'
    || 'aExIaGRLVDArS0h0emEzVTZZU3gzYjNNNmVDNWpiblErTUQ5NExuZHZjMU4xYlM5NExtTnVkRG93TEhWdWFYUnpPbmd1ZFc1cGRITXNjM1JoZEhWek9uZ3Vk'
    || 'Mjl5YzNSVGRHRjBkWE45S1NrdVptbHNkR1Z5S0dFOVBtRXVkMjl6UGpBcExuTnZjblFvS0dFc2VDazlQbmd1ZDI5ekxXRXVkMjl6S1gxbWRXNWpkR2x2YmlC'
    || 'S1l5aDFLWHR5WlhSMWNtNGdkVDA5UFNKSVNVZElJajhpZG1GeUtDMHRkMkZ5YmlraU9uVTlQVDBpVEU5WElqOGlkbUZ5S0MwdFltRmtLU0k2SW5aaGNpZ3RM'
    || 'V2R2YjJRcEluMW1kVzVqZEdsdmJpQnhZeWg3Y0RwMWZTbDdZMjl1YzNRZ1pqMWxkQ2gxTENKM1pXVnJjMTl2Wmw5emRYQndiSGtpS1N4YllTeDRYVDFpWlM1'
    || 'MWMyVlRkR0YwWlNodWRXeHNLVHRwWmlnaFppNXNaVzVuZEdncGNtVjBkWEp1SUhNdWFuTjRLQ0p3SWl4N2MzUjViR1U2ZTJadmJuUlRhWHBsT2pFeUxHTnZi'
    || 'Rzl5T2lKMllYSW9MUzFrYVcwcElpeHdZV1JrYVc1bk9pSXhNbkI0SURBaWZTeGphR2xzWkhKbGJqb2lUbThnYVc1MlpXNTBiM0o1SUdSaGRHRXVJRk5sZENC'
    || 'TlJWSkRTRUZPVkY5SlRsWkZUbFJQVWxsZlZFRkNURVV1SW4wcE8yTnZibk4wSUU0OVdtTW9aaWtzUXoxT0xuTnNhV05sS0RBc01qQXBMSGs5VGk1c1pXNW5k'
    || 'R2d0UXk1c1pXNW5kR2c3YVdZb0lVTXViR1Z1WjNSb0tYSmxkSFZ5YmlCekxtcHplQ2dpY0NJc2UzTjBlV3hsT250bWIyNTBVMmw2WlRveE1peGpiMnh2Y2pv'
    || 'aWRtRnlLQzB0WkdsdEtTSXNjR0ZrWkdsdVp6b2lNVEp3ZUNBd0luMHNZMmhwYkdSeVpXNDZJazV2SUhkbFpXdHpMVzltTFhOMWNIQnNlU0JrWVhSaElHTnZi'
    || 'WEIxZEdWa0xpSjlLVHRqYjI1emRDQmZQVTFoZEdndWJXRjRLQzR1TGtNdWJXRndLRlk5UGxZdWQyOXpLU3d4S1N4M1BUZzRMRUk5TXpRd0xFdzlNakFzUVQw'
    || 'ekxFZzlReTVzWlc1bmRHZ3FLRXdyUVNrc2NtVTlkeXRDS3pVd0xFYzlORHc5WHo5M0t6UXZYeXBDT2kweExGZzlPRHc5WHo5M0t6Z3ZYeXBDT2kweE8zSmxk'
    || 'SFZ5YmlCekxtcHplSE1vSW1ScGRpSXNlM04wZVd4bE9udHdiM05wZEdsdmJqb2ljbVZzWVhScGRtVWlmU3hqYUdsc1pISmxianBiY3k1cWMzaHpLQ0p6ZG1j'
    || 'aUxIdDJhV1YzUW05NE9tQXdJREFnSkh0eVpYMGdKSHRJS3pJNGZXQXNkMmxrZEdnNklqRXdNQ1VpTEhOMGVXeGxPbnR0WVhoWGFXUjBhRHB5WlN4a2FYTndi'
    || 'R0Y1T2lKaWJHOWpheUo5TEdOb2FXeGtjbVZ1T2x0SFBqQS9jeTVxYzNoektITXVSbkpoWjIxbGJuUXNlMk5vYVd4a2NtVnVPbHR6TG1wemVDZ2liR2x1WlNJ'
    || 'c2UzZ3hPa2NzZVRFNk1DeDRNanBITEhreU9rZ3NjM1J5YjJ0bE9pSjJZWElvTFMxc2FXNWxMVElwSWl4emRISnZhMlZYYVdSMGFEb3hMSE4wY205clpVUmhj'
    || 'MmhoY25KaGVUb2lNeXd6SW4wcExITXVhbk40S0NKMFpYaDBJaXg3ZURwSExIazZTQ3N4TXl4MFpYaDBRVzVqYUc5eU9pSnRhV1JrYkdVaUxITjBlV3hsT250'
    || 'bWIyNTBVMmw2WlRveE1TeG1hV3hzT2lKMllYSW9MUzFrYVcwcEluMHNZMmhwYkdSeVpXNDZJalIzSW4wcFhYMHBPbTUxYkd3c1dENHdQM011YW5ONGN5aHpM'
    || 'a1p5WVdkdFpXNTBMSHRqYUdsc1pISmxianBiY3k1cWMzZ29JbXhwYm1VaUxIdDRNVHBZTEhreE9qQXNlREk2V0N4NU1qcElMSE4wY205clpUb2lkbUZ5S0Mw'
    || 'dGJHbHVaUzB5S1NJc2MzUnliMnRsVjJsa2RHZzZNU3h6ZEhKdmEyVkVZWE5vWVhKeVlYazZJak1zTXlKOUtTeHpMbXB6ZUNnaWRHVjRkQ0lzZTNnNldDeDVP'
    || 'a2dyTVRNc2RHVjRkRUZ1WTJodmNqb2liV2xrWkd4bElpeHpkSGxzWlRwN1ptOXVkRk5wZW1VNk1URXNabWxzYkRvaWRtRnlLQzB0WkdsdEtTSjlMR05vYVd4'
    || 'a2NtVnVPaUk0ZHlKOUtWMTlLVHB1ZFd4c0xFTXViV0Z3S0NoV0xFWmxLVDArZTJOdmJuTjBJRTVsUFVabEtpaE1LMEVwTEV4bFBVMWhkR2d1YldGNEtESXNW'
    || 'aTUzYjNNdlh5cENLVHR5WlhSMWNtNGdjeTVxYzNoektDSm5JaXg3YzNSNWJHVTZlMk4xY25OdmNqb2laR1ZtWVhWc2RDSjlMRzl1VFc5MWMyVkZiblJsY2pw'
    || 'dlpUMCtlQ2g3ZURwdlpTNWpiR2xsYm5SWUxIazZiMlV1WTJ4cFpXNTBXU3h6YTNVNlZpNXphM1VzZDI5ek9sWXVkMjl6TEhWdWFYUnpPbFl1ZFc1cGRITXNj'
    || 'M1JoZEhWek9sWXVjM1JoZEhWemZTa3NiMjVOYjNWelpVMXZkbVU2YjJVOVBtRW1KbmdvZXk0dUxtRXNlRHB2WlM1amJHbGxiblJZTEhrNmIyVXVZMnhwWlc1'
    || 'MFdYMHBMRzl1VFc5MWMyVk1aV0YyWlRvb0tUMCtlQ2h1ZFd4c0tTeGphR2xzWkhKbGJqcGJjeTVxYzNnb0luUmxlSFFpTEh0NE9uY3ROaXg1T2s1bEswd3ZN'
    || 'aXgwWlhoMFFXNWphRzl5T2lKbGJtUWlMR1J2YldsdVlXNTBRbUZ6Wld4cGJtVTZJbU5sYm5SeVlXd2lMSE4wZVd4bE9udG1iMjUwVTJsNlpUb3hNU3htYVd4'
    || 'c09pSjJZWElvTFMxdGRYUmxaQ2tpZlN4amFHbHNaSEpsYmpwV0xuTnJkWDBwTEhNdWFuTjRLQ0p5WldOMElpeDdlRHAzTEhrNlRtVXNkMmxrZEdnNlRHVXNh'
    || 'R1ZwWjJoME9rd3Njbmc2TXl4bWFXeHNPa3BqS0ZZdWMzUmhkSFZ6S1N4dmNHRmphWFI1T2k0M01uMHBMSE11YW5ONGN5Z2lkR1Y0ZENJc2UzZzZkeXRNWlNz'
    || 'MUxIazZUbVVyVEM4eUxHUnZiV2x1WVc1MFFtRnpaV3hwYm1VNkltTmxiblJ5WVd3aUxITjBlV3hsT250bWIyNTBVMmw2WlRveE1TeG1hV3hzT2lKMllYSW9M'
    || 'UzFrYVcwcEluMHNZMmhwYkdSeVpXNDZXMVl1ZDI5ekxuUnZSbWw0WldRb01Ta3NJbmNpWFgwcFhYMHNWaTV6YTNVcGZTa3NlVDR3UDNNdWFuTjRjeWdpZEdW'
    || 'NGRDSXNlM2c2ZHl4NU9rZ3JNalFzYzNSNWJHVTZlMlp2Ym5SVGFYcGxPakV4TEdacGJHdzZJblpoY2lndExXUnBiU2tpZlN4amFHbHNaSEpsYmpwYmVTd2lJ'
    || 'RzF2Y21VZ1UwdFZjeUJ1YjNRZ2MyaHZkMjRpWFgwcE9tNTFiR3hkZlNrc2N5NXFjM2dvWTNNc2UzZzZLR0U5UFc1MWJHdy9kbTlwWkNBd09tRXVlQ2svUHpB'
    || 'c2VUb29ZVDA5Ym5Wc2JEOTJiMmxrSURBNllTNTVLVDgvTUN4MmFYTnBZbXhsT2lFaFlTeGphR2xzWkhKbGJqcGhQM011YW5ONGN5Z2laR2wySWl4N2MzUjVi'
    || 'R1U2ZTJadmJuUlRhWHBsT2pFeUxHeHBibVZJWldsbmFIUTZNUzQyZlN4amFHbHNaSEpsYmpwYmN5NXFjM2dvSW5OMGNtOXVaeUlzZTJOb2FXeGtjbVZ1T21F'
    || 'dWMydDFmU2tzY3k1cWMzZ29JbUp5SWl4N2ZTa3NJbGRsWld0eklHOW1JSE4xY0hCc2VUb2dJaXhoTG5kdmN5NTBiMFpwZUdWa0tERXBMSE11YW5ONEtDSmlj'
    || 'aUlzZTMwcExDSlZibWwwY3lCdmJpQm9ZVzVrT2lBaUxHVmxLR0V1ZFc1cGRITXBMSE11YW5ONEtDSmljaUlzZTMwcExDSlRkR0YwZFhNNklDSXNZUzV6ZEdG'
    || 'MGRYTmRmU2s2Ym5Wc2JIMHBYWDBwZldOdmJuTjBJR0pqUFZ0N2EyVjVPaUpUVkU5U1JWOU9RVTFGSWl4c1lXSmxiRG9pVTNSdmNtVWlmU3g3YTJWNU9pSlNS'
    || 'VWRKVDA0aUxHeGhZbVZzT2lKU1pXZHBiMjRpZlN4N2EyVjVPaUpUVVY5R1ZGOUNWVU5MUlZRaUxHeGhZbVZzT2lKVGFYcGxJbjBzZTJ0bGVUb2lVMEZNUlZO'
    || 'ZlVFVlNYMU5SUmxRaUxHeGhZbVZzT2lJa0wxTnhSblFpTEdGc2FXZHVPaUp5YVdkb2RDSXNjbVZ1WkdWeU9uVTlQbVZsS0hVcGZTeDdhMlY1T2lKUVJVVlNY'
    || 'MUpCVGtzaUxHeGhZbVZzT2lKU1lXNXJJaXhoYkdsbmJqb2ljbWxuYUhRaUxISmxibVJsY2pwMVBUNWxaU2gxS1gwc2UydGxlVG9pVUVWRlVsOUhVazlWVUY5'
    || 'VFNWcEZJaXhzWVdKbGJEb2liMllpTEdGc2FXZHVPaUp5YVdkb2RDSXNjbVZ1WkdWeU9uVTlQbVZsS0hVcGZWMDdablZ1WTNScGIyNGdaV1FvZTNBNmRYMHBl'
    || 'M0psZEhWeWJpQnpMbXB6ZUhNb2N5NUdjbUZuYldWdWRDeDdZMmhwYkdSeVpXNDZXM011YW5ONEtIUjBMSHQwYVhSc1pUb2lVM1J2Y21VZ2NHVnlabTl5YldG'
    || 'dVkyVWdhR1ZoZENCdFlYQWlMR05vYVd4a2NtVnVPbk11YW5ONGN5aFpaU3g3Y0dGdVpXdzZkUzV3WVc1bGJITXVjM1Z0YldGeWVTeDNhR1Z1VFdsemMybHVa'
    || 'em9pVTJWMElFMUZVa05JUVU1VVgxTlVUMUpGVTE5VVFVSk1SU0JoYm1RZ1RVVlNRMGhCVGxSZlJFRkpURmxmVTBGTVJWTmZWRUZDVEVVdUlpeGphR2xzWkhK'
    || 'bGJqcGJjeTVxYzNnb1dHTXNlM0E2ZFgwcExITXVhbk40S0dsekxIdGphR2xzWkhKbGJqb2lRMlZzYkhNZ1kyOXNiM1Z5WldRZ1lua2dlaTF6WTI5eVpTQjJj'
    || 'eUJ3WldWeUlHRjJaWEpoWjJVdUlFZHlaV1Z1SUQwZ1lXSnZkbVVnYldWaGJpd2djbVZrSUQwZ1ltVnNiM2N1SUVaeWIyMGdWbDlOUlZKRFNFRk9WRjlUVlUx'
    || 'TlFWSlpJRzkyWlhJZ2RHaGxJR052Ym1acFozVnlaV1FnZDJsdVpHOTNMaUo5S1YxOUtYMHBMSE11YW5ONEtIUjBMSHQwYVhSc1pUb2lVR1ZsY2lCeVlXNXJh'
    || 'VzVuSWl4amFHbHNaSEpsYmpwekxtcHplSE1vV1dVc2UzQmhibVZzT25VdWNHRnVaV3h6TG5CbFpYSmZZMjl0Y0dGeWFYTnZiaXgzYUdWdVRXbHpjMmx1Wnpv'
    || 'aVVHVmxjaUJqYjIxd1lYSnBjMjl1SUc1dmRDQmlkV2xzZEM0aUxHTm9hV3hrY21WdU9sdHpMbXB6ZUNoNmRDeDdjbTkzY3pwbGRDaDFMQ0p3WldWeVgyTnZi'
    || 'WEJoY21semIyNGlLU3hqYjJ4ek9tSmpmU2tzY3k1cWMzZ29iSE1zZTNScGRHeGxPaUpRWldWeUlHZHliM1Z3Y3lJc1kyaHBiR1J5Wlc0NklsSmhibXRsWkNC'
    || 'M2FYUm9hVzRnYzJsNlpTMWlkV05yWlhRZ0t5QnlaV2RwYjI0Z2NHVmxjaUJuY205MWNDNGdWR2xsY3lCemFHRnlaU0JoSUhKaGJtc3VJbjBwWFgwcGZTbGRm'
    || 'U2w5WTI5dWMzUWdkR1E5VzN0clpYazZJbE5VVDFKRlgwbEVJaXhzWVdKbGJEb2lVM1J2Y21VaUxISmxibVJsY2pwMVBUNVRkSEpwYm1jb2RUOC9JdUtBbENJ'
    || 'cGZTeDdhMlY1T2lKVVQxUkJURjlQVGw5SVFVNUVJaXhzWVdKbGJEb2lUMjRnYUdGdVpDSXNZV3hwWjI0NkluSnBaMmgwSWl4eVpXNWtaWEk2ZFQwK1pXVW9k'
    || 'U2w5TEh0clpYazZJa0ZIUlVSZlQwNWZTRUZPUkNJc2JHRmlaV3c2SWtGblpXUWdLRFl3WkNzcElpeGhiR2xuYmpvaWNtbG5hSFFpTEhKbGJtUmxjanAxUFQ1'
    || 'bFpTaDFLWDBzZTJ0bGVUb2lUVUZTUzBSUFYwNWZSVmhRVDFOVlVrVmZVa0ZVUlNJc2JHRmlaV3c2SWtWNGNHOXpkWEpsSWl4aGJHbG5iam9pY21sbmFIUWlM'
    || 'SEpsYm1SbGNqcDFQVDVTY2lobmRDaDFLU294TURBcGZWMHNibVE5VzN0clpYazZJbE5VVDFKRlgwbEVJaXhzWVdKbGJEb2lVM1J2Y21VaUxISmxibVJsY2pw'
    || 'MVBUNVRkSEpwYm1jb2RUOC9JdUtBbENJcGZTeDdhMlY1T2lKVFMxVmZTVVFpTEd4aFltVnNPaUpUUzFVaWZTeDdhMlY1T2lKVFFVeEZYMWRGUlVzaUxHeGhZ'
    || 'bVZzT2lKWFpXVnJJaXh5Wlc1a1pYSTZkVDArZFQ5VGRISnBibWNvZFNrdWMyeHBZMlVvTUN3eE1DazZJdUtBbENKOUxIdHJaWGs2SWxWT1NWUlRYMU5QVEVR'
    || 'aUxHeGhZbVZzT2lKVGIyeGtJaXhoYkdsbmJqb2ljbWxuYUhRaUxISmxibVJsY2pwMVBUNWxaU2gxS1gwc2UydGxlVG9pVTBWTVRGOVVTRkpQVlVkSVgxSkJW'
    || 'RVVpTEd4aFltVnNPaUpTWVhSbElpeGhiR2xuYmpvaWNtbG5hSFFpTEhKbGJtUmxjanAxUFQ1N1kyOXVjM1FnWmoxbmRDaDFLU294TURBN2NtVjBkWEp1SUdZ'
    || 'K01EOVNjaWhtS1RvaTRvQ1VJbjE5WFR0bWRXNWpkR2x2YmlCeVpDaDdjRHAxZlNsN2NtVjBkWEp1SUhNdWFuTjRjeWh6TGtaeVlXZHRaVzUwTEh0amFHbHNa'
    || 'SEpsYmpwYmN5NXFjM2dvZEhRc2UzUnBkR3hsT2lKSmJuWmxiblJ2Y25rZ2NtbHpheUJpZVNCVFMxVWlMR05vYVd4a2NtVnVPbk11YW5ONGN5aFpaU3g3Y0dG'
    || 'dVpXdzZkUzV3WVc1bGJITXVkMlZsYTNOZmIyWmZjM1Z3Y0d4NUxIZG9aVzVOYVhOemFXNW5PaUpUWlhRZ1RVVlNRMGhCVGxSZlNVNVdSVTVVVDFKWlgxUkJR'
    || 'a3hGTGlJc1kyaHBiR1J5Wlc0NlczTXVhbk40S0hGakxIdHdPblY5S1N4ekxtcHplQ2hwY3l4N1kyaHBiR1J5Wlc0NklrSmhjbk1nYzJsNlpXUWdZbmtnWVha'
    || 'bklIZGxaV3R6SUc5bUlITjFjSEJzZVNCd1pYSWdVMHRWTGlCVWFISmxjMmh2YkdSek9pQk1UMWNnUENBMGR5QW9jM1J2WTJ0dmRYUWdjbWx6YXlrc0lFaEZR'
    || 'VXhVU0ZrZ05DMDRkeXdnU0VsSFNDQStJRGgzSUNodFlYSnJaRzkzYmlCeWFYTnJLUzRnUm5KdmJTQldYMWRGUlV0VFgwOUdYMU5WVUZCTVdTNGlmU2xkZlNs'
    || 'OUtTeHpMbXB6ZUNoMGRDeDdkR2wwYkdVNklrMWhjbXRrYjNkdUlHVjRjRzl6ZFhKbElHSjVJSE4wYjNKbElpeGphR2xzWkhKbGJqcHpMbXB6ZUhNb1dXVXNl'
    || 'M0JoYm1Wc09uVXVjR0Z1Wld4ekxtMWhjbXRrYjNkdVgyVjRjRzl6ZFhKbExIZG9aVzVOYVhOemFXNW5PaUpUWlhRZ1RVVlNRMGhCVGxSZlNVNVdSVTVVVDFK'
    || 'WlgxUkJRa3hGTGlJc1kyaHBiR1J5Wlc0NlczTXVhbk40S0hwMExIdHliM2R6T21WMEtIVXNJbTFoY210a2IzZHVYMlY0Y0c5emRYSmxJaWtzWTI5c2N6cDBa'
    || 'SDBwTEhNdWFuTjRLR3h6TEh0MGFYUnNaVG9pUVdkbFpDQnBiblpsYm5SdmNua2lMR05vYVd4a2NtVnVPaUpCWjJWa0lEMGdkVzVwZEhNZ2IyNGdhR0Z1WkNC'
    || 'M2FHVnlaU0JHU1ZKVFZGOVNSVU5GU1ZaRlJGOUVRVlJGSUdseklENGdOakFnWkdGNWN5QmhaMjh1SW4wcFhYMHBmU2tzY3k1cWMzZ29kSFFzZTNScGRHeGxP'
    || 'aUpUWld4c0xYUm9jbTkxWjJnZ1lua2dVMHRWSWl4amFHbHNaSEpsYmpwekxtcHplQ2haWlN4N2NHRnVaV3c2ZFM1d1lXNWxiSE11YzJWc2JGOTBhSEp2ZFdk'
    || 'b0xIZG9aVzVOYVhOemFXNW5PaUpPWldWa2N5QnBiblpsYm5SdmNua2dLeUJ6WVd4bGN5QjBZV0pzWlhNdUlpeGphR2xzWkhKbGJqcHpMbXB6ZUNoNmRDeDdj'
    || 'bTkzY3pwbGRDaDFMQ0p6Wld4c1gzUm9jbTkxWjJnaUtTeGpiMnh6T201a0xHMWhlRG8wTUgwcGZTbDlLVjE5S1gxamIyNXpkQ0JzWkQxYmUydGxlVG9pVTFS'
    || 'UFVrVmZTVVFpTEd4aFltVnNPaUpUZEc5eVpTSXNjbVZ1WkdWeU9uVTlQbE4wY21sdVp5aDFQejhpNG9DVUlpbDlMSHRyWlhrNklsSkZVRTlTVkY5RVFWUkZJ'
    || 'aXhzWVdKbGJEb2lSR0YwWlNJc2NtVnVaR1Z5T25VOVBuVS9VM1J5YVc1bktIVXBMbk5zYVdObEtEQXNNVEFwT2lMaWdKUWlmU3g3YTJWNU9pSkVRVWxNV1Y5'
    || 'VVVrRkdSa2xESWl4c1lXSmxiRG9pVkhKaFptWnBZeUlzWVd4cFoyNDZJbkpwWjJoMElpeHlaVzVrWlhJNmRUMCtaV1VvZFNsOUxIdHJaWGs2SWtSQlNVeFpY'
    || 'MVJTUVU1VFFVTlVTVTlPVXlJc2JHRmlaV3c2SWxSNGJpSXNZV3hwWjI0NkluSnBaMmgwSWl4eVpXNWtaWEk2ZFQwK1pXVW9kU2w5TEh0clpYazZJa05QVGxa'
    || 'RlVsTkpUMDVmVWtGVVJTSXNiR0ZpWld3NklsSmhkR1VpTEdGc2FXZHVPaUp5YVdkb2RDSXNjbVZ1WkdWeU9uVTlQbEp5S0dkMEtIVXBLakV3TUNsOVhTeHBa'
    || 'RDFiZTJ0bGVUb2lVMVJQVWtWZlNVUWlMR3hoWW1Wc09pSlRkRzl5WlNJc2NtVnVaR1Z5T25VOVBsTjBjbWx1WnloMVB6OGk0b0NVSWlsOUxIdHJaWGs2SWxK'
    || 'RlVFOVNWRjlFUVZSRklpeHNZV0psYkRvaVJHRjBaU0lzY21WdVpHVnlPblU5UG5VL1UzUnlhVzVuS0hVcExuTnNhV05sS0RBc01UQXBPaUxpZ0pRaWZTeDdh'
    || 'MlY1T2lKRVFVbE1XVjlPUlZSZlUwRk1SVk1pTEd4aFltVnNPaUpUWVd4bGN5SXNZV3hwWjI0NkluSnBaMmgwSWl4eVpXNWtaWEk2ZFQwK0lpUWlLMlZsS0hV'
    || 'cGZTeDdhMlY1T2lKVVQxUkJURjlJVDFWU1V5SXNiR0ZpWld3NklraHZkWEp6SWl4aGJHbG5iam9pY21sbmFIUWlMSEpsYm1SbGNqcDFQVDVsWlNoMUtYMHNl'
    || 'MnRsZVRvaVJFOU1URUZTVTE5UVJWSmZTRTlWVWlJc2JHRmlaV3c2SWlRdmFISWlMR0ZzYVdkdU9pSnlhV2RvZENJc2NtVnVaR1Z5T25VOVBpSWtJaXRsWlNo'
    || 'MUtYMWRMRzlrUFZ0N2EyVjVPaUpUVkU5U1JWOUpSQ0lzYkdGaVpXdzZJbE4wYjNKbElpeHlaVzVrWlhJNmRUMCtVM1J5YVc1bktIVS9QeUxpZ0pRaUtYMHNl'
    || 'MnRsZVRvaVVrVlFUMUpVWDBSQlZFVWlMR3hoWW1Wc09pSkVZWFJsSWl4eVpXNWtaWEk2ZFQwK2RUOVRkSEpwYm1jb2RTa3VjMnhwWTJVb01Dd3hNQ2s2SXVL'
    || 'QWxDSjlMSHRyWlhrNklraFBWVkpUWDFCRlVsOUxYMVJTUVVaR1NVTWlMR3hoWW1Wc09pSkljbk12U3lCMGNtRm1abWxqSWl4aGJHbG5iam9pY21sbmFIUWlM'
    || 'SEpsYm1SbGNqcDFQVDVsWlNoMUtYMHNlMnRsZVRvaVEwOU9Wa1ZTVTBsUFRsOVNRVlJGSWl4c1lXSmxiRG9pUTI5dWRpQnlZWFJsSWl4aGJHbG5iam9pY21s'
    || 'bmFIUWlMSEpsYm1SbGNqcDFQVDVTY2lobmRDaDFLU294TURBcGZTeDdhMlY1T2lKVFFVeEZVMTlRUlZKZlNFOVZVaUlzYkdGaVpXdzZJaVF2YUhJaUxHRnNh'
    || 'V2R1T2lKeWFXZG9kQ0lzY21WdVpHVnlPblU5UGlJa0lpdGxaU2gxS1gxZE8yWjFibU4wYVc5dUlITmtLSHR3T25WOUtYdGpiMjV6ZENCbVBXVjBLSFVzSW1O'
    || 'dmJuWmxjbk5wYjI0aUtTeGhQV1YwS0hVc0ltUnZiR3hoY25OZmNHVnlYMmh2ZFhJaUtTeDRQV1YwS0hVc0luTjBZV1ptYVc1blgyVm1abWxqYVdWdVkza2lL'
    || 'VHR5WlhSMWNtNGdjeTVxYzNoektITXVSbkpoWjIxbGJuUXNlMk5vYVd4a2NtVnVPbHR6TG1wemVDaDBkQ3g3ZEdsMGJHVTZJbFJ5WVdabWFXTXRkRzh0ZEhK'
    || 'aGJuTmhZM1JwYjI0Z1kyOXVkbVZ5YzJsdmJpSXNZMmhwYkdSeVpXNDZjeTVxYzNnb1dXVXNlM0JoYm1Wc09uVXVjR0Z1Wld4ekxtTnZiblpsY25OcGIyNHNk'
    || 'MmhsYmsxcGMzTnBibWM2SWxObGRDQk5SVkpEU0VGT1ZGOVVVa0ZHUmtsRFgxUkJRa3hGTGlJc1kyaHBiR1J5Wlc0NlppNXNaVzVuZEdnK01EOXpMbXB6ZUNo'
    || 'NmRDeDdjbTkzY3pwbUxHTnZiSE02YkdRc2JXRjRPalF3ZlNrNmN5NXFjM2dvSW5BaUxIdHpkSGxzWlRwN1ptOXVkRk5wZW1VNk1USXNZMjlzYjNJNkluWmhj'
    || 'aWd0TFdScGJTa2lmU3hqYUdsc1pISmxiam9pVG04Z1kyOXVkbVZ5YzJsdmJpQmtZWFJoTGlKOUtYMHBmU2tzY3k1cWMzZ29kSFFzZTNScGRHeGxPaUpUWVd4'
    || 'bGN5QndaWElnWVhOemIyTnBZWFJsTFdodmRYSWlMR05vYVd4a2NtVnVPbk11YW5ONEtGbGxMSHR3WVc1bGJEcDFMbkJoYm1Wc2N5NWtiMnhzWVhKelgzQmxj'
    || 'bDlvYjNWeUxIZG9aVzVOYVhOemFXNW5PaUpUWlhRZ1RVVlNRMGhCVGxSZlRFRkNUMUpmVkVGQ1RFVXVJaXhqYUdsc1pISmxianBoTG14bGJtZDBhRDR3UDNN'
    || 'dWFuTjRLSHAwTEh0eWIzZHpPbUVzWTI5c2N6cHBaQ3h0WVhnNk5EQjlLVHB6TG1wemVDZ2ljQ0lzZTNOMGVXeGxPbnRtYjI1MFUybDZaVG94TWl4amIyeHZj'
    || 'am9pZG1GeUtDMHRaR2x0S1NKOUxHTm9hV3hrY21WdU9pSk9ieUJzWVdKdmNpQmtZWFJoTGlKOUtYMHBmU2tzY3k1cWMzZ29kSFFzZTNScGRHeGxPaUpUZEdG'
    || 'bVptbHVaeUJsWm1acFkybGxibU41SWl4amFHbHNaSEpsYmpwekxtcHplQ2haWlN4N2NHRnVaV3c2ZFM1d1lXNWxiSE11YzNSaFptWnBibWRmWldabWFXTnBa'
    || 'VzVqZVN4M2FHVnVUV2x6YzJsdVp6b2lVMlYwSUUxRlVrTklRVTVVWDB4QlFrOVNYMVJCUWt4RklHRnVaQ0JOUlZKRFNFRk9WRjlVVWtGR1JrbERYMVJCUWt4'
    || 'RkxpSXNZMmhwYkdSeVpXNDZlQzVzWlc1bmRHZytNRDl6TG1wemVDaDZkQ3g3Y205M2N6cDRMR052YkhNNmIyUXNiV0Y0T2pRd2ZTazZjeTVxYzNnb0luQWlM'
    || 'SHR6ZEhsc1pUcDdabTl1ZEZOcGVtVTZNVElzWTI5c2IzSTZJblpoY2lndExXUnBiU2tpZlN4amFHbHNaSEpsYmpvaVRtOGdjM1JoWm1acGJtY2daR0YwWVM0'
    || 'aWZTbDlLWDBwWFgwcGZXWjFibU4wYVc5dUlIVmtLSHR3T25WOUtYdHlaWFIxY200Z2N5NXFjM2h6S0hNdVJuSmhaMjFsYm5Rc2UyTm9hV3hrY21WdU9sdHpM'
    || 'bXB6ZUNoMGRDeDdkR2wwYkdVNklsZG9ZWFFnZEdocGN5QnpiMngxZEdsdmJpQmpZVzRnWkc4aUxHTm9hV3hrY21WdU9uTXVhbk40S0ZsbExIdHdZVzVsYkRw'
    || 'MUxuQmhibVZzY3k1aFkzUnBiMjV6TEdOb2FXeGtjbVZ1T25NdWFuTjRLRkJqTEh0aFkzUnBiMjV6T21WMEtIVXNJbUZqZEdsdmJuTWlLWDBwZlNsOUtTeHpM'
    || 'bXB6ZUNoMGRDeDdkR2wwYkdVNklrRmpkR2x2YmlCb2FYTjBiM0o1SWl4amFHbHNaSEpsYmpwekxtcHplQ2haWlN4N2NHRnVaV3c2ZFM1d1lXNWxiSE11WVdO'
    || 'MGFXOXVYMnh2Wnl4amFHbHNaSEpsYmpwekxtcHplQ2hQWXl4N2JHOW5PbVYwS0hVc0ltRmpkR2x2Ymw5c2IyY2lLWDBwZlNsOUtWMTlLWDFtZFc1amRHbHZi'
    || 'aUJoWkNoN2NEcDFmU2w3WTI5dWMzUWdaajFiZTJsa09pSndaWEptYjNKdFlXNWpaU0lzYkdGaVpXdzZJbE4wYjNKbElIQmxjbVp2Y20xaGJtTmxJaXhrWlhO'
    || 'ak9pSkRjbTl6Y3kxemRHOXlaU0JqYjIxd1lYSnBjMjl1SUc5dUlHWnZkWElnYldWMGNtbGpjeUlzYVdOdmJqb2liM1psY25acFpYY2lMSEJoYm1Wc2N6cGJJ'
    || 'bk4xYlcxaGNua2lMQ0p3WldWeVgyTnZiWEJoY21semIyNGlYU3h5Wlc1a1pYSTZLQ2s5UG5NdWFuTjRLR1ZrTEh0d09uVjlLWDBzZTJsa09pSnBiblpsYm5S'
    || 'dmNua2lMR3hoWW1Wc09pSkpiblpsYm5SdmNua2lMR1JsYzJNNklsTjFjSEJzZVNCc1pYWmxiSE1nWVc1a0lHMWhjbXRrYjNkdUlHVjRjRzl6ZFhKbElpeHBZ'
    || 'Mjl1T2lKc1lYbGxjbk1pTEhCaGJtVnNjenBiSW5kbFpXdHpYMjltWDNOMWNIQnNlU0lzSW0xaGNtdGtiM2R1WDJWNGNHOXpkWEpsSWl3aWMyVnNiRjkwYUhK'
    || 'dmRXZG9JbDBzY21WdVpHVnlPaWdwUFQ1ekxtcHplQ2h5WkN4N2NEcDFmU2w5TEh0cFpEb2liM0JsY21GMGFXOXVjeUlzYkdGaVpXdzZJazl3WlhKaGRHbHZi'
    || 'bk1pTEdSbGMyTTZJbE4wWVdabWFXNW5MQ0JqYjI1MlpYSnphVzl1TENCaGJtUWdjMkZzWlhNZ1pXWm1hV05wWlc1amVTSXNhV052YmpvaWMzQmhjbXNpTEhC'
    || 'aGJtVnNjenBiSW1OdmJuWmxjbk5wYjI0aUxDSmtiMnhzWVhKelgzQmxjbDlvYjNWeUlpd2ljM1JoWm1acGJtZGZaV1ptYVdOcFpXNWplU0pkTEhKbGJtUmxj'
    || 'am9vS1QwK2N5NXFjM2dvYzJRc2UzQTZkWDBwZlN4N2FXUTZJbUZqZEdsdmJuTWlMR3hoWW1Wc09pSlhhR0YwSUhSb2FYTWdZMkZ1SUdSdklpeGtaWE5qT2lK'
    || 'QlkzUnBiMjV6SUdGdVpDQm9hWE4wYjNKNUlpeHBZMjl1T2lKbWJHOTNJaXh3WVc1bGJITTZXeUpoWTNScGIyNXpJaXdpWVdOMGFXOXVYMnh2WnlKZExISmxi'
    || 'bVJsY2pvb0tUMCtjeTVxYzNnb2RXUXNlM0E2ZFgwcGZWMDdjbVYwZFhKdUlITXVhbk40S0VoakxIdHdZWGxzYjJGa09uVXNjM1ZpZEdsMGJHVTZJa0p5YVdO'
    || 'ckxXRnVaQzF0YjNKMFlYSWdiV1Z5WTJoaGJuUWdhVzUwWld4c2FXZGxibU5sSWl4elpXTjBhVzl1Y3pwbWZTbDlVV01vZFQwK2N5NXFjM2dvWVdRc2UzQTZk'
    || 'WDBwS1gwcEtDazdDZz09IgpBUFBfQ1NTX0I2NCA9ICJMbUZ3Y0MxMmFXVjNMVzFsYm5WN2NHOXphWFJwYjI0NmNtVnNZWFJwZG1VN1pteGxlRHB1YjI1bE8y'
    || 'MWhjbWRwYmkxc1pXWjBPbUYxZEc4N1kyOXNiM0k2ZG1GeUtDMHRibUYyZVN3Z0l6QTVNV1l6TmlsOUxtRndjQzEyYVdWM0xXMWxiblUrYzNWdGJXRnllWHRr'
    || 'YVhOd2JHRjVPbVpzWlhnN1lXeHBaMjR0YVhSbGJYTTZZMlZ1ZEdWeU8ycDFjM1JwWm5rdFkyOXVkR1Z1ZERwalpXNTBaWEk3ZDJsa2RHZzZNelp3ZUR0b1pX'
    || 'bG5hSFE2TXpad2VEdHdZV1JrYVc1bk9qQTdZbTl5WkdWeU9qQTdZbTl5WkdWeUxYSmhaR2wxY3pvMWNIZzdZM1Z5YzI5eU9uQnZhVzUwWlhJN2JHbHpkQzF6'
    || 'ZEhsc1pUcHViMjVsZlM1aGNIQXRkbWxsZHkxdFpXNTFQbk4xYlcxaGNuazZPaTEzWldKcmFYUXRaR1YwWVdsc2N5MXRZWEpyWlhKN1pHbHpjR3hoZVRwdWIy'
    || 'NWxmUzVoY0hBdGRtbGxkeTF0Wlc1MVBuTjFiVzFoY25rNmFHOTJaWElzTG1Gd2NDMTJhV1YzTFcxbGJuVmJiM0JsYmwwK2MzVnRiV0Z5ZVh0aVlXTnJaM0p2'
    || 'ZFc1a09uWmhjaWd0TFhOMWNtWmhZMlV0TWl3Z0kyWXpaak5tTkNsOUxtRndjQzEyYVdWM0xXMWxiblUrYzNWdGJXRnllVHBtYjJOMWN5MTJhWE5wWW14bExD'
    || 'NWhjSEF0ZG1sbGR5MXZjSFJwYjI1elBtRTZabTlqZFhNdGRtbHphV0pzWlh0dmRYUnNhVzVsT2pKd2VDQnpiMnhwWkNCMllYSW9MUzFoWTJObGJuUXNJQ013'
    || 'TURnMFpEUXBPMjkxZEd4cGJtVXRiMlptYzJWME9qSndlSDB1WVhCd0xYWnBaWGN0YjNCMGFXOXVjM3R3YjNOcGRHbHZianBoWW5OdmJIVjBaVHQ2TFdsdVpH'
    || 'VjRPak13TzNKcFoyaDBPakE3ZEc5d09tTmhiR01vTVRBd0pTQXJJRFp3ZUNrN2QybGtkR2c2TVRjMGNIZzdiV0Y0TFhkcFpIUm9PbU5oYkdNb01UQXdkbmNn'
    || 'TFNBek1uQjRLVHRrYVhOd2JHRjVPbWR5YVdRN1oyRndPakp3ZUR0d1lXUmthVzVuT2pWd2VEdGliM0prWlhJNk1YQjRJSE52Ykdsa0lIWmhjaWd0TFd4cGJt'
    || 'VXNJQ05sTW1VeVpUWXBPMkp2Y21SbGNpMXlZV1JwZFhNNk5uQjRPMkpoWTJ0bmNtOTFibVE2STJabVpqdGliM2d0YzJoaFpHOTNPakFnTm5CNElERTRjSGdn'
    || 'SXpBNU1XWXpOakZtZlM1aGNIQXRkbWxsZHkxdmNIUnBiMjV6UG1GN1pHbHpjR3hoZVRwaWJHOWphenR3WVdSa2FXNW5Pamx3ZUNBeE1IQjRPMk52Ykc5eU9t'
    || 'bHVhR1Z5YVhRN1ptOXVkRHBwYm1obGNtbDBPMlp2Ym5RdGMybDZaVG94TTNCNE8yeHBibVV0YUdWcFoyaDBPakV1TlR0MFpYaDBMV1JsWTI5eVlYUnBiMjQ2'
    || 'Ym05dVpUdGliM0prWlhJdGNtRmthWFZ6T2pOd2VIMHVZWEJ3TFhacFpYY3RiM0IwYVc5dWN6NWhPbWh2ZG1WeWUySmhZMnRuY205MWJtUTZkbUZ5S0MwdGMz'
    || 'VnlabUZqWlMweUxDQWpaak5tTTJZMEtYMDZjbTl2ZEhzdExXSm5PaUFqWmpobU9HWTRPeTB0YzNWeVptRmpaVG9nSTJabVptWm1aanN0TFhOMWNtWmhZMlV0'
    || 'TWpvZ0kyWXpaak5tTkRzdExYTjFjbVpoWTJVdE16b2dJMlZpWldKbFpEc3RMV3hwYm1VNklDTmxOV1UxWlRjN0xTMXNhVzVsTFRJNklDTmtObVEyWkRrN0xT'
    || 'MTBaWGgwT2lBak1URXhNVEV4T3kwdGJYVjBaV1E2SUNNMllqWmlObUk3TFMxa2FXMDZJQ05oTTJFellUTTdMUzFoWTJObGJuUTZJQ013TURnMFpEUTdMUzF1'
    || 'WVhaNU9pQWpNR0V5TXpReU95MHRjMnQ1T2lBak1qbGlOV1U0T3kwdFoyOXZaRG9nSXpFMllUTTBZVHN0TFhkaGNtNDZJQ05tTlRsbE1HSTdMUzFpWVdRNklD'
    || 'TmxPREF3TVdNN0xTMTJhVzlzWlhRNklDTTNZek5oWldRN0xTMW5iMjlrTFhkaGMyZzZJSEpuWW1Fb01qSXNJREUyTXl3Z056UXNJQzR3T0NrN0xTMTNZWEp1'
    || 'TFhkaGMyZzZJSEpuWW1Fb01qUTFMQ0F4TlRnc0lERXhMQ0F1TVNrN0xTMWlZV1F0ZDJGemFEb2djbWRpWVNneU16SXNJREFzSURJNExDQXVNRGNwT3kwdFlX'
    || 'TmpaVzUwTFhkaGMyZzZJSEpuWW1Fb01Dd2dNVE15TENBeU1USXNJQzR3TnlrN0xTMXlZV1JwZFhNNklERXljSGc3TFMxeVlXUnBkWE10YkdjNklERTJjSGc3'
    || 'TFMxeVlXUnBkWE10ZUd3NklESXdjSGc3TFMxemFDMWpZWEprT2lBd0lERndlQ0F6Y0hnZ2NtZGlZU2d3TENBd0xDQXdMQ0F1TURZcExDQXdJREp3ZUNBeE1u'
    || 'QjRJSEpuWW1Fb01Dd2dNQ3dnTUN3Z0xqQTBLVHN0TFhOb0xXMWtPaUF3SURKd2VDQTRjSGdnY21kaVlTZ3dMQ0F3TENBd0xDQXVNRGdwTENBd0lEaHdlQ0F5'
    || 'TkhCNElISm5ZbUVvTUN3Z01Dd2dNQ3dnTGpBMktUc3RMWE5vTFdodmRtVnlPaUF3SURSd2VDQXhObkI0SUhKblltRW9NQ3dnTUN3Z01Dd2dMakVwTENBd0lE'
    || 'RXljSGdnTXpad2VDQnlaMkpoS0RBc0lEQXNJREFzSUM0d055azdMUzFsWVhObE9pQmpkV0pwWXkxaVpYcHBaWElvTGpJeUxDQXhMQ0F1TXpZc0lERXBPeTB0'
    || 'YzJsa1pXSmhjaTEzT2lBeU16WndlSDBxZTJKdmVDMXphWHBwYm1jNlltOXlaR1Z5TFdKdmVIMW9kRzFzTEdKdlpIbDdiV0Z5WjJsdU9qQTdjR0ZrWkdsdVp6'
    || 'b3dPMkpoWTJ0bmNtOTFibVE2ZG1GeUtDMHRZbWNwTzJOdmJHOXlPblpoY2lndExYUmxlSFFwTzJadmJuUXRabUZ0YVd4NU9pMWhjSEJzWlMxemVYTjBaVzBz'
    || 'UW14cGJtdE5ZV05UZVhOMFpXMUdiMjUwTEZObFoyOWxJRlZKTEVobGJIWmxkR2xqWVNCT1pYVmxMRUZ5YVdGc0xITmhibk10YzJWeWFXWTdabTl1ZEMxemFY'
    || 'cGxPakUwY0hnN2JHbHVaUzFvWldsbmFIUTZNUzQxT3kxM1pXSnJhWFF0Wm05dWRDMXpiVzl2ZEdocGJtYzZZVzUwYVdGc2FXRnpaV1E3TFcxdmVpMXZjM2d0'
    || 'Wm05dWRDMXpiVzl2ZEdocGJtYzZaM0poZVhOallXeGxmUzVoY0hCN1pHbHpjR3hoZVRwbmNtbGtPMmR5YVdRdGRHVnRjR3hoZEdVdFkyOXNkVzF1Y3pwMllY'
    || 'SW9MUzF6YVdSbFltRnlMWGNwSUcxcGJtMWhlQ2d3TERGbWNpazdaMkZ3T2pBN2JXbHVMV2hsYVdkb2REb3hNREFsZlM1aGNIQXRMVzV2Ym1GMmUyZHlhV1F0'
    || 'ZEdWdGNHeGhkR1V0WTI5c2RXMXVjenB0YVc1dFlYZ29NQ3d4Wm5JcGZTNXphV1JsZTNCdmMybDBhVzl1T25OMGFXTnJlVHQwYjNBNk1EdGhiR2xuYmkxelpX'
    || 'eG1Pbk4wWVhKME8zQmhaR1JwYm1jNk1qQndlQ0F4TkhCNElERTRjSGc3WW05eVpHVnlMWEpwWjJoME9qRndlQ0J6YjJ4cFpDQjJZWElvTFMxc2FXNWxLVHRp'
    || 'WVdOclozSnZkVzVrT25aaGNpZ3RMWE4xY21aaFkyVXBPMjFwYmkxb1pXbG5hSFE2TVRBd2RtaDlMbk5wWkdWZlgySnlZVzVrZTJScGMzQnNZWGs2Wm14bGVE'
    || 'dGhiR2xuYmkxcGRHVnRjenBqWlc1MFpYSTdaMkZ3T2psd2VEdHdZV1JrYVc1bk9qQWdObkI0SURFMmNIaDlMbk5wWkdWZlgySnlZVzVrSUhOMlozdG1iR1Y0'
    || 'T201dmJtVjlMbk5wWkdWZlgzZHZjbVJ0WVhKcmUyWnZiblF0YzJsNlpUb3hNM0I0TzJadmJuUXRkMlZwWjJoME9qY3dNRHRzWlhSMFpYSXRjM0JoWTJsdVp6'
    || 'b3RMakF4WlcwN1kyOXNiM0k2ZG1GeUtDMHRibUYyZVNrN2JHbHVaUzFvWldsbmFIUTZNUzR4TlgwdWMybGtaVjlmYzNWaWUyWnZiblF0YzJsNlpUb3hNWEI0'
    || 'TzJadmJuUXRkMlZwWjJoME9qVXdNRHRqYjJ4dmNqcDJZWElvTFMxa2FXMHBPMnhsZEhSbGNpMXpjR0ZqYVc1bk9pNHdNbVZ0ZlM1dVlYWjdaR2x6Y0d4aGVU'
    || 'cG1iR1Y0TzJac1pYZ3RaR2x5WldOMGFXOXVPbU52YkhWdGJqdG5ZWEE2TW5CNGZTNXVZWFpmWDJsMFpXMTdaR2x6Y0d4aGVUcG1iR1Y0TzJGc2FXZHVMV2ww'
    || 'Wlcxek9tWnNaWGd0YzNSaGNuUTdaMkZ3T2psd2VEdHdZV1JrYVc1bk9qaHdlQ0E1Y0hnN1ltOXlaR1Z5TFhKaFpHbDFjem81Y0hnN1ltOXlaR1Z5T2pBN1lt'
    || 'RmphMmR5YjNWdVpEcHViMjVsTzNkcFpIUm9PakV3TUNVN2RHVjRkQzFoYkdsbmJqcHNaV1owTzJOMWNuTnZjanB3YjJsdWRHVnlPMk52Ykc5eU9uWmhjaWd0'
    || 'TFcxMWRHVmtLVHQwY21GdWMybDBhVzl1T21KaFkydG5jbTkxYm1RZ0xqRTBjeUIyWVhJb0xTMWxZWE5sS1N4amIyeHZjaUF1TVRSeklIWmhjaWd0TFdWaGMy'
    || 'VXBPMlp2Ym5RNmFXNW9aWEpwZEgwdWJtRjJYMTlwZEdWdE9taHZkbVZ5ZTJKaFkydG5jbTkxYm1RNmRtRnlLQzB0YzNWeVptRmpaUzB5S1R0amIyeHZjanAy'
    || 'WVhJb0xTMTBaWGgwS1gwdWJtRjJYMTlwZEdWdElITjJaM3RtYkdWNE9tNXZibVU3YldGeVoybHVMWFJ2Y0RveGNIaDlMbTVoZGw5ZmJHRmlaV3g3Wm05dWRD'
    || 'MXphWHBsT2pFeUxqVndlRHRtYjI1MExYZGxhV2RvZERvMk1EQTdaR2x6Y0d4aGVUcGliRzlqYXp0c2FXNWxMV2hsYVdkb2REb3hMak0xZlM1dVlYWmZYMlJs'
    || 'YzJON1ptOXVkQzF6YVhwbE9qRXhjSGc3WTI5c2IzSTZkbUZ5S0MwdFpHbHRLVHRrYVhOd2JHRjVPbUpzYjJOck8yeHBibVV0YUdWcFoyaDBPakV1TTMwdWJt'
    || 'RjJYMTlwZEdWdExTMXZibnRpWVdOclozSnZkVzVrT25aaGNpZ3RMV0ZqWTJWdWRDMTNZWE5vS1R0amIyeHZjanAyWVhJb0xTMWhZMk5sYm5RcGZTNXVZWFpm'
    || 'WDJsMFpXMHRMVzl1SUM1dVlYWmZYMnhoWW1Wc2UyTnZiRzl5T25aaGNpZ3RMV0ZqWTJWdWRDbDlMbTVoZGw5ZmFYUmxiUzB0YjI0Z0xtNWhkbDlmWkdWelkz'
    || 'dGpiMnh2Y2pwMllYSW9MUzFoWTJObGJuUXBPMjl3WVdOcGRIazZMamQ5TG01aGRsOWZaRzkwZTNkcFpIUm9Palp3ZUR0b1pXbG5hSFE2Tm5CNE8ySnZjbVJs'
    || 'Y2kxeVlXUnBkWE02TlRBbE8yMWhjbWRwYmpvMWNIZ2dNQ0F3SUdGMWRHODdabXhsZURwdWIyNWxmUzV1WVhaZlgyUnZkQzB0WW1Ga2UySmhZMnRuY205MWJt'
    || 'UTZkbUZ5S0MwdFltRmtLWDB1Ym1GMlgxOWtiM1F0TFhkaGNtNTdZbUZqYTJkeWIzVnVaRHAyWVhJb0xTMTNZWEp1S1gwdWJtRjJYMTlrYjNRdExXbHVabTk3'
    || 'WW1GamEyZHliM1Z1WkRwMllYSW9MUzF6YTNrcGZTNXVZWFpmWDJkeWIzVndlMjFoY21kcGJqb3hOWEI0SURBZ00zQjRPM0JoWkdScGJtYzZNQ0E1Y0hnN1pt'
    || 'OXVkQzF6YVhwbE9qRXhjSGc3Wm05dWRDMTNaV2xuYUhRNk56QXdPM1JsZUhRdGRISmhibk5tYjNKdE9uVndjR1Z5WTJGelpUdHNaWFIwWlhJdGMzQmhZMmx1'
    || 'WnpvdU1EUmxiVHRqYjJ4dmNqcDJZWElvTFMxdGRYUmxaQ2s3YkdsdVpTMW9aV2xuYUhRNk1TNHpmUzV1WVhaZlgyZHliM1Z3T21acGNuTjBMV05vYVd4a2Uy'
    || 'MWhjbWRwYmkxMGIzQTZNWEI0ZlM1dVlYWmZYMmwwWlcwdExYTjFZbnR3WVdSa2FXNW5MV3hsWm5RNk1qSndlSDB1YzJsa1pWOWZabTl2ZEh0dFlYSm5hVzR0'
    || 'ZEc5d09qRTRjSGc3Y0dGa1pHbHVaem94TVhCNElEaHdlQ0F3TzJKdmNtUmxjaTEwYjNBNk1YQjRJSE52Ykdsa0lIWmhjaWd0TFd4cGJtVXBPMlp2Ym5RdGMy'
    || 'bDZaVG94TVhCNE8yTnZiRzl5T25aaGNpZ3RMV1JwYlNrN2JHbHVaUzFvWldsbmFIUTZNUzQwTlgwdWJXRnBibnR3WVdSa2FXNW5Pakl5Y0hnZ01qWndlQ0F6'
    || 'TUhCNE8yMXBiaTEzYVdSMGFEb3dmUzVoY0hCZlgyaGxZV1I3WkdsemNHeGhlVHBtYkdWNE8yRnNhV2R1TFdsMFpXMXpPbVpzWlhndGMzUmhjblE3YW5WemRH'
    || 'bG1lUzFqYjI1MFpXNTBPbk53WVdObExXSmxkSGRsWlc0N1oyRndPakU0Y0hnN2JXRnlaMmx1TFdKdmRIUnZiVG94T0hCNE8yWnNaWGd0ZDNKaGNEcDNjbUZ3'
    || 'ZlM1aGNIQmZYMmhsWVdRK0tudHRhVzR0ZDJsa2RHZzZNRHR0WVhndGQybGtkR2c2TVRBd0pYMHVZWEJ3WDE5b1pXRmtjbWxuYUhSN2JXbHVMWGRwWkhSb09q'
    || 'QTdiV0Y0TFhkcFpIUm9PakV3TUNVN1pHbHpjR3hoZVRwbWJHVjRPMkZzYVdkdUxXbDBaVzF6T21ac1pYZ3RjM1JoY25RN1oyRndPakV3Y0hnN1pteGxlQzEz'
    || 'Y21Gd09uZHlZWEI5TG1Gd2NGOWZhR1ZoWkNCb01YdHRZWEpuYVc0Nk1EdG1iMjUwTFhOcGVtVTZNakZ3ZUR0bWIyNTBMWGRsYVdkb2REbzNNREE3YkdWMGRH'
    || 'VnlMWE53WVdOcGJtYzZMUzR3TW1WdE8yTnZiRzl5T25aaGNpZ3RMVzVoZG5rcE8yeHBibVV0YUdWcFoyaDBPakV1TW4wdVlYQndYMTl6ZFdKN2JXRnlaMmx1'
    || 'T2pWd2VDQXdJREE3Wm05dWRDMXphWHBsT2pFeWNIZzdZMjlzYjNJNmRtRnlLQzB0YlhWMFpXUXBmUzVoY0hCZlgzTjFZaUJqYjJSbGUySmhZMnRuY205MWJt'
    || 'UTZkbUZ5S0MwdGMzVnlabUZqWlMweUtUdGliM0prWlhJNk1YQjRJSE52Ykdsa0lIWmhjaWd0TFd4cGJtVXBPM0JoWkdScGJtYzZNWEI0SURad2VEdGliM0pr'
    || 'WlhJdGNtRmthWFZ6T2pWd2VEdG1iMjUwTFhOcGVtVTZNVEZ3ZUR0amIyeHZjanAyWVhJb0xTMXVZWFo1S1gwdWNHaGhjMlY3Wm14bGVEcHViMjVsTzJScGMz'
    || 'QnNZWGs2Wm14bGVEdG1iR1Y0TFdScGNtVmpkR2x2YmpwamIyeDFiVzQ3WVd4cFoyNHRhWFJsYlhNNlpteGxlQzFsYm1RN1oyRndPamh3ZUR0dFlYZ3RkMmxr'
    || 'ZEdnNk1UQXdKWDB1Y0doaGMyVmZYM0poYVd4N1pHbHpjR3hoZVRwcGJteHBibVV0Wm14bGVEdGhiR2xuYmkxcGRHVnRjenB6ZEhKbGRHTm9PMkp2Y21SbGNq'
    || 'b3hjSGdnYzI5c2FXUWdkbUZ5S0MwdGJHbHVaU2s3WW05eVpHVnlMWEpoWkdsMWN6cDJZWElvTFMxeVlXUnBkWE1wTzJKaFkydG5jbTkxYm1RNmRtRnlLQzB0'
    || 'YzNWeVptRmpaU2s3YjNabGNtWnNiM2M2YUdsa1pHVnVPMjFoZUMxM2FXUjBhRG94TURBbGZTNXdhR0Z6WlY5ZlluUnVleTEzWldKcmFYUXRZWEJ3WldGeVlX'
    || 'NWpaVHB1YjI1bE95MXRiM290WVhCd1pXRnlZVzVqWlRwdWIyNWxPMkZ3Y0dWaGNtRnVZMlU2Ym05dVpUdGlZV05yWjNKdmRXNWtPbTV2Ym1VN1ltOXlaR1Z5'
    || 'T2pBN1ltOXlaR1Z5TFd4bFpuUTZNWEI0SUhOdmJHbGtJSFpoY2lndExXeHBibVVwTzJScGMzQnNZWGs2Wm14bGVEdG1iR1Y0TFdScGNtVmpkR2x2YmpwamIy'
    || 'eDFiVzQ3WVd4cFoyNHRhWFJsYlhNNlpteGxlQzF6ZEdGeWREdG5ZWEE2TW5CNE8zQmhaR1JwYm1jNk4zQjRJREV5Y0hnN1kzVnljMjl5T25CdmFXNTBaWEk3'
    || 'ZEdWNGRDMWhiR2xuYmpwc1pXWjBPMlp2Ym5RNmFXNW9aWEpwZER0amIyeHZjanAyWVhJb0xTMXRkWFJsWkNrN2JXbHVMWGRwWkhSb09qQjlMbkJvWVhObFgx'
    || 'OWlkRzQ2Wm1seWMzUXRZMmhwYkdSN1ltOXlaR1Z5TFd4bFpuUTZNSDB1Y0doaGMyVmZYMkowYmpwb2IzWmxjbnRpWVdOclozSnZkVzVrT25aaGNpZ3RMWE4x'
    || 'Y21aaFkyVXRNaWw5TG5Cb1lYTmxYMTlpZEc0NlptOWpkWE10ZG1semFXSnNaWHR2ZFhSc2FXNWxPakp3ZUNCemIyeHBaQ0IyWVhJb0xTMWhZMk5sYm5RcE8y'
    || 'OTFkR3hwYm1VdGIyWm1jMlYwT2kweWNIaDlMbkJvWVhObFgxOXNZV0psYkh0bWIyNTBMWE5wZW1VNk1URndlRHRtYjI1MExYZGxhV2RvZERvMk1EQTdiR1Yw'
    || 'ZEdWeUxYTndZV05wYm1jNkxqQTBaVzA3ZEdWNGRDMTBjbUZ1YzJadmNtMDZkWEJ3WlhKallYTmxPM2RvYVhSbExYTndZV05sT201dmQzSmhjSDB1Y0doaGMy'
    || 'VmZYMlpwWjNWeVpYdG1iMjUwTFhOcGVtVTZNVEp3ZUR0bWIyNTBMWGRsYVdkb2REbzFNREE3ZDJocGRHVXRjM0JoWTJVNmJtOXliV0ZzTzI5MlpYSm1iRzkz'
    || 'TFhkeVlYQTZZVzU1ZDJobGNtVjlMbkJvWVhObFgxOXRiMjVsZVh0bWIyNTBMWE5wZW1VNk1URndlRHRqYjJ4dmNqcDJZWElvTFMxdGRYUmxaQ2s3ZDJocGRH'
    || 'VXRjM0JoWTJVNmJtOTNjbUZ3ZlM1d2FHRnpaVjlmWW5SdUxTMWpkWEp5Wlc1MGUySmhZMnRuY205MWJtUTZkbUZ5S0MwdFlXTmpaVzUwTFhkaGMyZ3BPMk52'
    || 'Ykc5eU9uWmhjaWd0TFc1aGRua3BmUzV3YUdGelpWOWZZblJ1TFMxamRYSnlaVzUwSUM1d2FHRnpaVjlmYkdGaVpXeDdZMjlzYjNJNmRtRnlLQzB0WVdOalpX'
    || 'NTBLWDB1Y0doaGMyVmZYMkowYmkwdFkzVnljbVZ1ZENBdWNHaGhjMlZmWDJacFozVnlaWHRqYjJ4dmNqcDJZWElvTFMxMFpYaDBLVHRtYjI1MExYZGxhV2Rv'
    || 'ZERvMk1EQjlMbkJvWVhObFgxOWlkRzR0TFdSdmJtVWdMbkJvWVhObFgxOXNZV0psYkN3dWNHaGhjMlZmWDJKMGJpMHRZV2hsWVdRZ0xuQm9ZWE5sWDE5c1lX'
    || 'SmxiQ3d1Y0doaGMyVmZYMkowYmkwdFlXaGxZV1FnTG5Cb1lYTmxYMTltYVdkMWNtVjdZMjlzYjNJNmRtRnlLQzB0YlhWMFpXUXBmUzV3YUdGelpWOWZZblJ1'
    || 'TG1sekxXOXdaVzU3WW1GamEyZHliM1Z1WkRwMllYSW9MUzF6ZFhKbVlXTmxMVE1wZlM1d2FHRnpaVjlmWW5SdUxTMWpkWEp5Wlc1MExtbHpMVzl3Wlc1N1lt'
    || 'RmphMmR5YjNWdVpEcDJZWElvTFMxaFkyTmxiblF0ZDJGemFDbDlMbkJvWVhObFgxOWtaWFJoYVd4N2JXRjRMWGRwWkhSb09qUXpNSEI0TzNSbGVIUXRZV3hw'
    || 'WjI0NmJHVm1kRHRpWVdOclozSnZkVzVrT25aaGNpZ3RMWE4xY21aaFkyVXRNaWs3WW05eVpHVnlPakZ3ZUNCemIyeHBaQ0IyWVhJb0xTMXNhVzVsS1R0aWIz'
    || 'SmtaWEl0Y21Ga2FYVnpPblpoY2lndExYSmhaR2wxY3lrN2NHRmtaR2x1WnpveE1IQjRJREV5Y0hoOUxuQm9ZWE5sWDE5a1pYUmhhV3dnY0h0dFlYSm5hVzQ2'
    || 'TUNBd0lEWndlRHRtYjI1MExYTnBlbVU2TVRFdU5YQjRPMnhwYm1VdGFHVnBaMmgwT2pFdU5YMHVjR2hoYzJWZlgyUmxkR0ZwYkNCd09teGhjM1F0WTJocGJH'
    || 'UjdiV0Z5WjJsdUxXSnZkSFJ2YlRvd2ZTNXdhR0Z6WlY5ZllteDFjbUo3WTI5c2IzSTZkbUZ5S0MwdGRHVjRkQ2w5TG5Cb1lYTmxYMTlpWVhOcGMzdGpiMnh2'
    || 'Y2pwMllYSW9MUzF0ZFhSbFpDbDlMbkJvWVhObFgxOWlZWE5wY3lCemRISnZibWQ3WTI5c2IzSTZkbUZ5S0MwdGRHVjRkQ2s3Wm05dWRDMTNaV2xuYUhRNk5q'
    || 'QXdmUzV3YUdGelpWOWZkMmhsY21WN1kyOXNiM0k2ZG1GeUtDMHRZV05qWlc1MEtUdG1iMjUwTFhkbGFXZG9kRG8yTURCOUxuQm9ZWE5sWDE5b2IzZDdZMjlz'
    || 'YjNJNmRtRnlLQzB0YlhWMFpXUXBmUzV3YUdGelpWOWZhRzkzSUdOdlpHVjdZbUZqYTJkeWIzVnVaRHAyWVhJb0xTMXpkWEptWVdObEtUdGliM0prWlhJNk1Y'
    || 'QjRJSE52Ykdsa0lIWmhjaWd0TFd4cGJtVXBPM0JoWkdScGJtYzZNWEI0SURad2VEdGliM0prWlhJdGNtRmthWFZ6T2pWd2VEdG1iMjUwTFhOcGVtVTZNVEZ3'
    || 'ZUR0amIyeHZjanAyWVhJb0xTMXVZWFo1S1R0M2FHbDBaUzF6Y0dGalpUcHViM2R5WVhCOVFHMWxaR2xoS0cxaGVDMTNhV1IwYURvM01qQndlQ2w3TG1Gd2NI'
    || 'dG5jbWxrTFhSbGJYQnNZWFJsTFdOdmJIVnRibk02YldsdWJXRjRLREFzTVdaeUtYMHVjMmxrWlh0d2IzTnBkR2x2YmpwemRHRjBhV003YldsdUxXaGxhV2Rv'
    || 'ZERvd08zQmhaR1JwYm1jNk1USndlRHRpYjNKa1pYSXRjbWxuYUhRNk1EdGliM0prWlhJdFltOTBkRzl0T2pGd2VDQnpiMnhwWkNCMllYSW9MUzFzYVc1bEtY'
    || 'MHVjMmxrWlNBdWJtRjJlMlpzWlhndFpHbHlaV04wYVc5dU9uSnZkenRtYkdWNExYZHlZWEE2ZDNKaGNIMHVjMmxrWlNBdWJtRjJYMTlwZEdWdGUzZHBaSFJv'
    || 'T21GMWRHODdabXhsZURveElERWdNVFF3Y0hoOUxuTnBaR1VnTG01aGRsOWZaM0p2ZFhCN1pteGxlQzFpWVhOcGN6b3hNREFsZlM1emFXUmxYMTltYjI5MGUy'
    || 'UnBjM0JzWVhrNmJtOXVaWDB1YldGcGJudHdZV1JrYVc1bk9qRTJjSGg5TG1Gd2NGOWZhR1ZoWkh0bWJHVjRMV1JwY21WamRHbHZianBqYjJ4MWJXNTlMbkJv'
    || 'WVhObGUyRnNhV2R1TFdsMFpXMXpPbVpzWlhndGMzUmhjblE3ZDJsa2RHZzZNVEF3SlgwdWNHaGhjMlZmWDNKaGFXeDdkMmxrZEdnNk1UQXdKWDB1Y0doaGMy'
    || 'VmZYMkowYm50bWJHVjRPakVnTVNBd2ZYMHVaM0pwWkh0a2FYTndiR0Y1T21keWFXUTdaMkZ3T2pFMGNIZzdaM0pwWkMxMFpXMXdiR0YwWlMxamIyeDFiVzV6'
    || 'T25KbGNHVmhkQ2hoZFhSdkxXWnBkQ3h0YVc1dFlYZ29iV2x1S0RNek1IQjRMREV3TUNVcExERm1jaWtwTzJGc2FXZHVMV2wwWlcxek9uTjBZWEowZlM1aVlX'
    || 'NXVaWEo3WW05eVpHVnlMWEpoWkdsMWN6b3dJSFpoY2lndExYSmhaR2wxY3lrZ2RtRnlLQzB0Y21Ga2FYVnpLU0F3TzNCaFpHUnBibWM2T0hCNElERXpjSGc3'
    || 'YldGeVoybHVMV0p2ZEhSdmJUb3hNbkI0TzJadmJuUXRjMmw2WlRveE1pNDFjSGc3Wm05dWRDMTNaV2xuYUhRNk5UQXdPMnhwYm1VdGFHVnBaMmgwT2pFdU5E'
    || 'VTdZbTl5WkdWeUxXeGxablE2TTNCNElITnZiR2xrSUhSeVlXNXpjR0Z5Wlc1MGZTNWlZVzV1WlhJdExYTmhiWEJzWlh0aVlXTnJaM0p2ZFc1a09pTm1OVGxs'
    || 'TUdJd1pUdGliM0prWlhJdGJHVm1kQzFqYjJ4dmNqcDJZWElvTFMxM1lYSnVLVHRqYjJ4dmNqb2pPR0UxTmpBd08yWnZiblF0ZDJWcFoyaDBPall3TUgwdVlt'
    || 'RnVibVZ5TFMxbVlXbHNlMkpoWTJ0bmNtOTFibVE2STJVNE1EQXhZekJrTzJKdmNtUmxjaTFzWldaMExXTnZiRzl5T25aaGNpZ3RMV0poWkNrN1kyOXNiM0k2'
    || 'STJFek1EQXhORHRtYjI1MExYZGxhV2RvZERvMk1EQjlMbUpoYm01bGNpMHRhVzVtYjN0aVlXTnJaM0p2ZFc1a09pTXdNRGcwWkRRd1pEdGliM0prWlhJdGJH'
    || 'Vm1kQzFqYjJ4dmNqcDJZWElvTFMxaFkyTmxiblFwTzJOdmJHOXlPaU13TURWaE9URjlMbU5oY21SN1ltRmphMmR5YjNWdVpEcDJZWElvTFMxemRYSm1ZV05s'
    || 'S1R0aWIzSmtaWEk2TVhCNElITnZiR2xrSUhaaGNpZ3RMV3hwYm1VcE8ySnZjbVJsY2kxeVlXUnBkWE02ZG1GeUtDMHRjbUZrYVhWektUdHdZV1JrYVc1bk9q'
    || 'RTJjSGdnTVRod2VDQXhPSEI0TzJKdmVDMXphR0ZrYjNjNmRtRnlLQzB0YzJndFkyRnlaQ2s3ZEhKaGJuTnBkR2x2YmpwaWIzZ3RjMmhoWkc5M0lDNHljeUIy'
    || 'WVhJb0xTMWxZWE5sS1gwdVkyRnlaRHBvYjNabGNudGliM2d0YzJoaFpHOTNPblpoY2lndExYTm9MVzFrS1gwdVkyRnlaQzB0ZDJsa1pYdG5jbWxrTFdOdmJI'
    || 'VnRiam94SUM4Z0xURjlMbU5oY21SZlgyaGxZV1I3YldGeVoybHVMV0p2ZEhSdmJUb3hOSEI0ZlM1allYSmtYMTlvWldGa0lHZ3llMjFoY21kcGJqb3dPMlp2'
    || 'Ym5RdGMybDZaVG94TVhCNE8yWnZiblF0ZDJWcFoyaDBPamN3TUR0MFpYaDBMWFJ5WVc1elptOXliVHAxY0hCbGNtTmhjMlU3YkdWMGRHVnlMWE53WVdOcGJt'
    || 'YzZMakEwWlcwN1kyOXNiM0k2ZG1GeUtDMHRaR2x0S1gwdVkyRnlaRjlmYUdsdWRIdHRZWEpuYVc0Nk5uQjRJREFnTUR0bWIyNTBMWE5wZW1VNk1USndlRHRq'
    || 'YjJ4dmNqcDJZWElvTFMxdGRYUmxaQ2s3YkdsdVpTMW9aV2xuYUhRNk1TNDFmUzV1YjNSbGUyMWhjbWRwYmpvd0lEQWdPWEI0TzJadmJuUXRjMmw2WlRveE0z'
    || 'QjRPMnhwYm1VdGFHVnBaMmgwT2pFdU5qdGpiMnh2Y2pwMllYSW9MUzF0ZFhSbFpDbDlMbTV2ZEdVNmJHRnpkQzFqYUdsc1pIdHRZWEpuYVc0dFltOTBkRzl0'
    || 'T2pCOUxuTjFZbnR0WVhKbmFXNDZNVGh3ZUNBd0lEbHdlRHRtYjI1MExYTnBlbVU2TVRGd2VEdG1iMjUwTFhkbGFXZG9kRG8zTURBN2RHVjRkQzEwY21GdWMy'
    || 'WnZjbTA2ZFhCd1pYSmpZWE5sTzJ4bGRIUmxjaTF6Y0dGamFXNW5PaTR3TkdWdE8yTnZiRzl5T25aaGNpZ3RMV1JwYlNsOUxuTjBZWFF0Y205M2UyUnBjM0Jz'
    || 'WVhrNlozSnBaRHRuWVhBNk1URndlRHRuY21sa0xYUmxiWEJzWVhSbExXTnZiSFZ0Ym5NNmNtVndaV0YwS0dGMWRHOHRabWwwTEcxcGJtMWhlQ2d4TkRod2VD'
    || 'd3habklwS1gwdWMzUmhkSHRpWVdOclozSnZkVzVrT25aaGNpZ3RMWE4xY21aaFkyVXBPMkp2Y21SbGNqb3hjSGdnYzI5c2FXUWdkbUZ5S0MwdGJHbHVaU2s3'
    || 'WW05eVpHVnlMWEpoWkdsMWN6cDJZWElvTFMxeVlXUnBkWE1wTzNCaFpHUnBibWM2TVROd2VDQXhOWEI0SURFMGNIaDlMbk4wWVhSZlgyeGhZbVZzZTJadmJu'
    || 'UXRjMmw2WlRveE1YQjRPMlp2Ym5RdGQyVnBaMmgwT2pZd01EdDBaWGgwTFhSeVlXNXpabTl5YlRwMWNIQmxjbU5oYzJVN2JHVjBkR1Z5TFhOd1lXTnBibWM2'
    || 'TGpBMFpXMDdZMjlzYjNJNmRtRnlLQzB0WkdsdEtYMHVjM1JoZEY5ZmRtRnNkV1Y3Wm05dWRDMXphWHBsT2pNd2NIZzdabTl1ZEMxM1pXbG5hSFE2TnpBd08y'
    || 'MWhjbWRwYmkxMGIzQTZOSEI0TzJ4cGJtVXRhR1ZwWjJoME9qRXVNRGc3YkdWMGRHVnlMWE53WVdOcGJtYzZMUzR3TWpWbGJUdG1iMjUwTFhaaGNtbGhiblF0'
    || 'Ym5WdFpYSnBZenAwWVdKMWJHRnlMVzUxYlhNN1kyOXNiM0k2ZG1GeUtDMHRibUYyZVNsOUxuTjBZWFJmWDNWdWFYUjdabTl1ZEMxemFYcGxPakUwY0hnN1ky'
    || 'OXNiM0k2ZG1GeUtDMHRaR2x0S1R0dFlYSm5hVzR0YkdWbWREb3pjSGc3Wm05dWRDMTNaV2xuYUhRNk5UQXdPMnhsZEhSbGNpMXpjR0ZqYVc1bk9qQjlMbk4w'
    || 'WVhSZlgzTjFZbnRtYjI1MExYTnBlbVU2TVRFdU5YQjRPMk52Ykc5eU9uWmhjaWd0TFcxMWRHVmtLVHR0WVhKbmFXNHRkRzl3T2pSd2VEdHNhVzVsTFdobGFX'
    || 'ZG9kRG94TGpSOUxuTjBZWFF0TFdkdmIyUWdMbk4wWVhSZlgzWmhiSFZsZTJOdmJHOXlPblpoY2lndExXZHZiMlFwZlM1emRHRjBMUzEzWVhKdUlDNXpkR0Yw'
    || 'WDE5MllXeDFaWHRqYjJ4dmNqb2pZamczTXpCaGZTNXpkR0YwTFMxaVlXUWdMbk4wWVhSZlgzWmhiSFZsZTJOdmJHOXlPblpoY2lndExXSmhaQ2w5TG5OMFlY'
    || 'UXRMV2R2YjJSN1ltOXlaR1Z5TFdOdmJHOXlPaU14Tm1Fek5HRTBaRHRpWVdOclozSnZkVzVrT25aaGNpZ3RMV2R2YjJRdGQyRnphQ2w5TG5OMFlYUXRMWGRo'
    || 'Y201N1ltOXlaR1Z5TFdOdmJHOXlPaU5tTlRsbE1HSTFOenRpWVdOclozSnZkVzVrT25aaGNpZ3RMWGRoY200dGQyRnphQ2w5TG5OMFlYUXRMV0poWkh0aWIz'
    || 'SmtaWEl0WTI5c2IzSTZJMlU0TURBeFl6UTNPMkpoWTJ0bmNtOTFibVE2ZG1GeUtDMHRZbUZrTFhkaGMyZ3BmUzUwWVdKc1pTMTNjbUZ3ZTI5MlpYSm1iRzkz'
    || 'TFhnNllYVjBienR0WVhKbmFXNHRkRzl3T2pFeWNIZzdZbUZqYTJkeWIzVnVaRHBzYVc1bFlYSXRaM0poWkdsbGJuUW9kRzhnY21sbmFIUXNkbUZ5S0MwdGMz'
    || 'VnlabUZqWlNrc2NtZGlZU2d5TlRVc01qVTFMREkxTlN3d0tTa2diR1ZtZENBdklESXdjSGdnTVRBd0pTQnVieTF5WlhCbFlYUWdiRzlqWVd3c2JHbHVaV0Z5'
    || 'TFdkeVlXUnBaVzUwS0hSdklHeGxablFzZG1GeUtDMHRjM1Z5Wm1GalpTa3NjbWRpWVNneU5UVXNNalUxTERJMU5Td3dLU2tnY21sbmFIUWdMeUF5TUhCNElE'
    || 'RXdNQ1VnYm04dGNtVndaV0YwSUd4dlkyRnNMR3hwYm1WaGNpMW5jbUZrYVdWdWRDaDBieUJ5YVdkb2RDd2pNVEV4TVRFeE1XRXNJekV4TVRBcElHeGxablFn'
    || 'THlBeE1YQjRJREV3TUNVZ2JtOHRjbVZ3WldGMElITmpjbTlzYkN4c2FXNWxZWEl0WjNKaFpHbGxiblFvZEc4Z2JHVm1kQ3dqTVRFeE1URXhNV0VzSXpFeE1U'
    || 'QXBJSEpwWjJoMElDOGdNVEZ3ZUNBeE1EQWxJRzV2TFhKbGNHVmhkQ0J6WTNKdmJHeDlkR0ZpYkdWN2QybGtkR2c2TVRBd0pUdGliM0prWlhJdFkyOXNiR0Z3'
    || 'YzJVNlkyOXNiR0Z3YzJVN1ptOXVkQzF6YVhwbE9qRXlMalZ3ZUgxMGFHVmhaQ0IwYUh0MFpYaDBMV0ZzYVdkdU9teGxablE3Wm05dWRDMXphWHBsT2pFeGNI'
    || 'ZzdabTl1ZEMxM1pXbG5hSFE2TnpBd08zUmxlSFF0ZEhKaGJuTm1iM0p0T25Wd2NHVnlZMkZ6WlR0c1pYUjBaWEl0YzNCaFkybHVaem91TURSbGJUdGpiMnh2'
    || 'Y2pwMllYSW9MUzFrYVcwcE8zQmhaR1JwYm1jNk4zQjRJREV3Y0hnN1ltOXlaR1Z5TFdKdmRIUnZiVG94Y0hnZ2MyOXNhV1FnZG1GeUtDMHRiR2x1WlNrN1lt'
    || 'RmphMmR5YjNWdVpEcDJZWElvTFMxemRYSm1ZV05sTFRJcE8zZG9hWFJsTFhOd1lXTmxPbTV2ZDNKaGNEdHdiM05wZEdsdmJqcHpkR2xqYTNrN2RHOXdPakI5'
    || 'ZEdobFlXUWdkR2c2Wm1seWMzUXRZMmhwYkdSN1ltOXlaR1Z5TFhSdmNDMXNaV1owTFhKaFpHbDFjem8zY0hoOWRHaGxZV1FnZEdnNmJHRnpkQzFqYUdsc1pI'
    || 'dGliM0prWlhJdGRHOXdMWEpwWjJoMExYSmhaR2wxY3pvM2NIaDlkR0p2WkhrZ2RHUjdjR0ZrWkdsdVp6bzRjSGdnTVRCd2VEdGliM0prWlhJdFltOTBkRzl0'
    || 'T2pGd2VDQnpiMnhwWkNCMllYSW9MUzFzYVc1bEtUdGpiMnh2Y2pwMllYSW9MUzEwWlhoMEtUdDJaWEowYVdOaGJDMWhiR2xuYmpwMGIzQjlkR0p2WkhrZ2RI'
    || 'STZiR0Z6ZEMxamFHbHNaQ0IwWkh0aWIzSmtaWEl0WW05MGRHOXRPakI5ZEdKdlpIa2dkSEk2YUc5MlpYSWdkR1I3WW1GamEyZHliM1Z1WkRwMllYSW9MUzF6'
    || 'ZFhKbVlXTmxMVElwZlhSa0xuSXNkR2d1Y250MFpYaDBMV0ZzYVdkdU9uSnBaMmgwTzJadmJuUXRkbUZ5YVdGdWRDMXVkVzFsY21sak9uUmhZblZzWVhJdGJu'
    || 'VnRjMzB1Ym5Wc2JIdGpiMnh2Y2pwMllYSW9MUzFrYVcwcE8yWnZiblF0YzNSNWJHVTZhWFJoYkdsamZTNTBZV0pzWlMxdGIzSmxlMjFoY21kcGJqbzVjSGdn'
    || 'TUNBd08yWnZiblF0YzJsNlpUb3hNUzQxY0hnN1kyOXNiM0k2ZG1GeUtDMHRaR2x0S1gwdVltRnljM3RrYVhOd2JHRjVPbVpzWlhnN1pteGxlQzFrYVhKbFkz'
    || 'UnBiMjQ2WTI5c2RXMXVPMmRoY0RvNGNIZzdiV0Z5WjJsdUxYUnZjRG8wY0hoOUxtSmhjbnRrYVhOd2JHRjVPbWR5YVdRN1ozSnBaQzEwWlcxd2JHRjBaUzFq'
    || 'YjJ4MWJXNXpPbTFwYm0xaGVDZ3hOREJ3ZUN3ek1DVXBJREZtY2lBM09IQjRPMkZzYVdkdUxXbDBaVzF6T21ObGJuUmxjanRuWVhBNk1URndlRHRtYjI1MExY'
    || 'TnBlbVU2TVRKd2VIMHVZbUZ5WDE5c1lXSmxiSHRqYjJ4dmNqcDJZWElvTFMxdGRYUmxaQ2s3Wm05dWRDMTNaV2xuYUhRNk5UQXdPMnhwYm1VdGFHVnBaMmgw'
    || 'T2pFdU16dHZkbVZ5Wm14dmR5MTNjbUZ3T21GdWVYZG9aWEpsTzNkdmNtUXRZbkpsWVdzNlluSmxZV3N0ZDI5eVpEdGthWE53YkdGNU9pMTNaV0pyYVhRdFlt'
    || 'OTRPeTEzWldKcmFYUXRZbTk0TFc5eWFXVnVkRHAyWlhKMGFXTmhiRHN0ZDJWaWEybDBMV3hwYm1VdFkyeGhiWEE2TWp0dmRtVnlabXh2ZHpwb2FXUmtaVzU5'
    || 'TG1KaGNsOWZkSEpoWTJ0N1ltRmphMmR5YjNWdVpEcDJZWElvTFMxemRYSm1ZV05sTFRNcE8ySnZjbVJsY2kxeVlXUnBkWE02TlhCNE8yaGxhV2RvZERveE9I'
    || 'QjRPMjkyWlhKbWJHOTNPbWhwWkdSbGJuMHVZbUZ5WDE5bWFXeHNlMmhsYVdkb2REb3hNREFsTzJKaFkydG5jbTkxYm1RNmRtRnlLQzB0WVdOalpXNTBLVHRp'
    || 'YjNKa1pYSXRjbUZrYVhWek9qVndlSDB1WW1GeVgxOW1hV3hzTFMxbmIyOWtlMkpoWTJ0bmNtOTFibVE2ZG1GeUtDMHRaMjl2WkNsOUxtSmhjbDlmWm1sc2JD'
    || 'MHRkMkZ5Ym50aVlXTnJaM0p2ZFc1a09uWmhjaWd0TFhkaGNtNHBmUzVpWVhKZlgyWnBiR3d0TFdKaFpIdGlZV05yWjNKdmRXNWtPblpoY2lndExXSmhaQ2w5'
    || 'TG1KaGNsOWZkbUZzZFdWN2RHVjRkQzFoYkdsbmJqcHlhV2RvZER0bWIyNTBMWFpoY21saGJuUXRiblZ0WlhKcFl6cDBZV0oxYkdGeUxXNTFiWE03WTI5c2Iz'
    || 'STZkbUZ5S0MwdGRHVjRkQ2s3Wm05dWRDMTNaV2xuYUhRNk5qQXdmUzV0WlhSbGNudHdiM05wZEdsdmJqcHlaV3hoZEdsMlpUdGlZV05yWjNKdmRXNWtPblpo'
    || 'Y2lndExYTjFjbVpoWTJVdE15azdZbTl5WkdWeUxYSmhaR2wxY3pvMWNIZzdhR1ZwWjJoME9qSXdjSGc3YjNabGNtWnNiM2M2YUdsa1pHVnVPMjFwYmkxM2FX'
    || 'UjBhRG81Tm5CNGZTNXRaWFJsY2w5ZlptbHNiSHRvWldsbmFIUTZNVEF3SlR0aVlXTnJaM0p2ZFc1a09uWmhjaWd0TFdGalkyVnVkQ2w5TG0xbGRHVnlYMTlt'
    || 'YVd4c0xTMW5iMjlrZTJKaFkydG5jbTkxYm1RNmRtRnlLQzB0WjI5dlpDbDlMbTFsZEdWeVgxOW1hV3hzTFMxM1lYSnVlMkpoWTJ0bmNtOTFibVE2ZG1GeUtD'
    || 'MHRkMkZ5YmlsOUxtMWxkR1Z5WDE5bWFXeHNMUzFpWVdSN1ltRmphMmR5YjNWdVpEcDJZWElvTFMxaVlXUXBmUzV0WlhSbGNsOWZkR1Y0ZEh0d2IzTnBkR2x2'
    || 'YmpwaFluTnZiSFYwWlR0MGIzQTZNRHR5YVdkb2REb3dPMkp2ZEhSdmJUb3dPMnhsWm5RNk1EdGthWE53YkdGNU9tWnNaWGc3WVd4cFoyNHRhWFJsYlhNNlky'
    || 'VnVkR1Z5TzJwMWMzUnBabmt0WTI5dWRHVnVkRHBqWlc1MFpYSTdabTl1ZEMxemFYcGxPakV4Y0hnN1ptOXVkQzEzWldsbmFIUTZOekF3TzJOdmJHOXlPblpo'
    || 'Y2lndExXNWhkbmtwTzJadmJuUXRkbUZ5YVdGdWRDMXVkVzFsY21sak9uUmhZblZzWVhJdGJuVnRjMzB1YldWMFpYSXRjbTkzZTJScGMzQnNZWGs2Wm14bGVE'
    || 'dG1iR1Y0TFdScGNtVmpkR2x2YmpwamIyeDFiVzQ3WjJGd09qWndlRHR0WVhKbmFXNDZOSEI0SURBZ01UUndlSDB1YldWMFpYSXRjbTkzWDE5b1pXRmtlMlJw'
    || 'YzNCc1lYazZabXhsZUR0aGJHbG5iaTFwZEdWdGN6cGlZWE5sYkdsdVpUdHFkWE4wYVdaNUxXTnZiblJsYm5RNmMzQmhZMlV0WW1WMGQyVmxianRuWVhBNk1U'
    || 'SndlRHRtYjI1MExYTnBlbVU2TVRKd2VIMHViV1YwWlhJdGNtOTNYMTlzWVdKbGJIdGpiMnh2Y2pwMllYSW9MUzF0ZFhSbFpDazdabTl1ZEMxM1pXbG5hSFE2'
    || 'TlRBd2ZTNXRaWFJsY2kxeWIzZGZYM1poYkhWbGUyTnZiRzl5T25aaGNpZ3RMWFJsZUhRcE8yWnZiblF0ZDJWcFoyaDBPall3TUR0bWIyNTBMWFpoY21saGJu'
    || 'UXRiblZ0WlhKcFl6cDBZV0oxYkdGeUxXNTFiWE03ZDJocGRHVXRjM0JoWTJVNmJtOTNjbUZ3ZlM1dFpYUmxjaTF5YjNkZlgyOW1lMk52Ykc5eU9uWmhjaWd0'
    || 'TFcxMWRHVmtLVHRtYjI1MExYZGxhV2RvZERvME1EQTdiV0Z5WjJsdUxXeGxablE2TjNCNE8yWnZiblF0YzJsNlpUb3hNWEI0TzJ4bGRIUmxjaTF6Y0dGamFX'
    || 'NW5PaTR3TVdWdGZTNXRaWFJsY2kxeWIzY2dMbTFsZEdWeWUyaGxhV2RvZERveE1IQjRPMkp2Y21SbGNpMXlZV1JwZFhNNk0zQjRPMjFwYmkxM2FXUjBhRG93'
    || 'ZlM1dFpYUmxjaTB0WTJWc2JIdG9aV2xuYUhRNk1UZHdlRHRpYjNKa1pYSXRjbUZrYVhWek9qTndlRHR0YVc0dGQybGtkR2c2Tnpod2VIMHViM1pzZTJScGMz'
    || 'QnNZWGs2WjNKcFpEdG5jbWxrTFhSbGJYQnNZWFJsTFdOdmJIVnRibk02YldsdWJXRjRLREFzTVdaeUtTQmhkWFJ2TzJkaGNEb3lNbkI0TzJGc2FXZHVMV2ww'
    || 'Wlcxek9tTmxiblJsY2p0dFlYSm5hVzR0ZEc5d09qUndlSDB1YjNac1gxOW1hV2QxY21WN1pHbHpjR3hoZVRwbWJHVjRPMlpzWlhndFpHbHlaV04wYVc5dU9t'
    || 'TnZiSFZ0Ymp0bllYQTZNVFp3ZUR0dGFXNHRkMmxrZEdnNk1IMHViM1pzWDE5emFXUmxlMjFwYmkxM2FXUjBhRG93ZlM1dmRteGZYMmhsWVdSN1pHbHpjR3ho'
    || 'ZVRwbWJHVjRPMkZzYVdkdUxXbDBaVzF6T21KaGMyVnNhVzVsTzJwMWMzUnBabmt0WTI5dWRHVnVkRHB6Y0dGalpTMWlaWFIzWldWdU8yZGhjRG94TW5CNE8y'
    || 'WnZiblF0YzJsNlpUb3hNbkI0TzIxaGNtZHBiaTFpYjNSMGIyMDZOWEI0ZlM1dmRteGZYMjVoYldWN1kyOXNiM0k2ZG1GeUtDMHRiWFYwWldRcE8yWnZiblF0'
    || 'ZDJWcFoyaDBPalV3TUgwdWIzWnNYMTl1ZTJOdmJHOXlPblpoY2lndExXNWhkbmtwTzJadmJuUXRkMlZwWjJoME9qY3dNRHRtYjI1MExYWmhjbWxoYm5RdGJu'
    || 'VnRaWEpwWXpwMFlXSjFiR0Z5TFc1MWJYTTdabTl1ZEMxemFYcGxPakUxY0hoOUxtOTJiRjlmZEhKaFkydDdhR1ZwWjJoME9qSXljSGc3WW1GamEyZHliM1Z1'
    || 'WkRwMllYSW9MUzF6ZFhKbVlXTmxMVE1wTzJKdmNtUmxjaTF5WVdScGRYTTZNM0I0TzI5MlpYSm1iRzkzT21ocFpHUmxianR0YVc0dGQybGtkR2c2TTNCNGZT'
    || 'NXZkbXhmWDJKdmRHaDdhR1ZwWjJoME9qRXdNQ1U3WW1GamEyZHliM1Z1WkRwMllYSW9MUzFoWTJObGJuUXBPMkp2Y21SbGNpMXlZV1JwZFhNNk0zQjRJREFn'
    || 'TUNBemNIaDlMbTkyYkY5ZmNtRjBaWHR0WVhKbmFXNHRkRzl3T2pWd2VEdG1iMjUwTFhOcGVtVTZNVEZ3ZUR0amIyeHZjanAyWVhJb0xTMXRkWFJsWkNrN1pt'
    || 'OXVkQzEyWVhKcFlXNTBMVzUxYldWeWFXTTZkR0ZpZFd4aGNpMXVkVzF6ZlM1dmRteGZYMjFwWkh0bWJHVjRPbTV2Ym1VN2RHVjRkQzFoYkdsbmJqcHlhV2Rv'
    || 'ZER0d1lXUmthVzVuTFd4bFpuUTZNakJ3ZUR0aWIzSmtaWEl0YkdWbWREb3hjSGdnYzI5c2FXUWdkbUZ5S0MwdGJHbHVaU2w5TG05MmJGOWZiV2xrTFc1N1pt'
    || 'OXVkQzF6YVhwbE9qTXdjSGc3Wm05dWRDMTNaV2xuYUhRNk56QXdPMnhwYm1VdGFHVnBaMmgwT2pFdU1EVTdZMjlzYjNJNmRtRnlLQzB0WVdOalpXNTBLVHRz'
    || 'WlhSMFpYSXRjM0JoWTJsdVp6b3RMakF5TldWdE8yWnZiblF0ZG1GeWFXRnVkQzF1ZFcxbGNtbGpPblJoWW5Wc1lYSXRiblZ0YzMwdWIzWnNYMTl0YVdRdGJH'
    || 'RmllMlp2Ym5RdGMybDZaVG94TVhCNE8yTnZiRzl5T25aaGNpZ3RMVzExZEdWa0tUdHRZWEpuYVc0dGRHOXdPalZ3ZUR0c2FXNWxMV2hsYVdkb2REb3hMak0x'
    || 'ZlVCdFpXUnBZU2h0WVhndGQybGtkR2c2T1RBd2NIZ3BleTV2ZG14N1ozSnBaQzEwWlcxd2JHRjBaUzFqYjJ4MWJXNXpPbTFwYm0xaGVDZ3dMREZtY2lsOUxt'
    || 'OTJiRjlmYldsa2UzUmxlSFF0WVd4cFoyNDZiR1ZtZER0d1lXUmthVzVuT2pFeWNIZ2dNQ0F3TzJKdmNtUmxjaTFzWldaME9qQTdZbTl5WkdWeUxYUnZjRG94'
    || 'Y0hnZ2MyOXNhV1FnZG1GeUtDMHRiR2x1WlNsOWZTNXdhV3hzZTJScGMzQnNZWGs2YVc1c2FXNWxMV0pzYjJOck8yWnZiblF0YzJsNlpUb3hNWEI0TzJadmJu'
    || 'UXRkMlZwWjJoME9qY3dNRHR3WVdSa2FXNW5Pakp3ZUNBNGNIZzdZbTl5WkdWeUxYSmhaR2wxY3pvNU9UbHdlRHRpYjNKa1pYSTZNWEI0SUhOdmJHbGtJSFpo'
    || 'Y2lndExXeHBibVV0TWlrN1kyOXNiM0k2ZG1GeUtDMHRiWFYwWldRcE8yeGxkSFJsY2kxemNHRmphVzVuT2k0d01tVnRPM2RvYVhSbExYTndZV05sT201dmQz'
    || 'SmhjSDB1Y0dsc2JDMHRaMjl2Wkh0amIyeHZjanAyWVhJb0xTMW5iMjlrS1R0aWIzSmtaWEl0WTI5c2IzSTZJekUyWVRNMFlUWTJPMkpoWTJ0bmNtOTFibVE2'
    || 'ZG1GeUtDMHRaMjl2WkMxM1lYTm9LWDB1Y0dsc2JDMHRkMkZ5Ym50amIyeHZjam9qWVRnMllUQTFPMkp2Y21SbGNpMWpiMnh2Y2pvalpqVTVaVEJpTnpNN1lt'
    || 'RmphMmR5YjNWdVpEcDJZWElvTFMxM1lYSnVMWGRoYzJncGZTNXdhV3hzTFMxaVlXUjdZMjlzYjNJNmRtRnlLQzB0WW1Ga0tUdGliM0prWlhJdFkyOXNiM0k2'
    || 'STJVNE1EQXhZell4TzJKaFkydG5jbTkxYm1RNmRtRnlLQzB0WW1Ga0xYZGhjMmdwZlM1d1lXbHllMkp2Y21SbGNqb3hjSGdnYzI5c2FXUWdkbUZ5S0MwdGJH'
    || 'bHVaU2s3WW05eVpHVnlMWEpoWkdsMWN6bzRjSGc3Y0dGa1pHbHVaem94TVhCNElERXpjSGdnTVRKd2VEdGlZV05yWjNKdmRXNWtPblpoY2lndExYTjFjbVpo'
    || 'WTJVcE8yMWhjbWRwYmkxaWIzUjBiMjA2TVRCd2VIMHVjR0ZwY2w5ZmFHVmhaSHRrYVhOd2JHRjVPbVpzWlhnN1lXeHBaMjR0YVhSbGJYTTZZMlZ1ZEdWeU8y'
    || 'ZGhjRG94TUhCNE8yWnNaWGd0ZDNKaGNEcDNjbUZ3TzIxaGNtZHBiaTFpYjNSMGIyMDZPWEI0ZlM1d1lXbHlYMTlwWkhON1ptOXVkQzF6YVhwbE9qRXhMalZ3'
    || 'ZUR0amIyeHZjanAyWVhJb0xTMXRkWFJsWkNrN1ptOXVkQzEzWldsbmFIUTZOVEF3TzI5MlpYSm1iRzkzTFhkeVlYQTZZVzU1ZDJobGNtVjlMbkJoYVhKZlgz'
    || 'WnplMk52Ykc5eU9uWmhjaWd0TFdScGJTazdjR0ZrWkdsdVp6b3dJRE53ZUgwdWNHRnBjbDlmY205M2MzdGthWE53YkdGNU9tWnNaWGc3Wm14bGVDMWthWEps'
    || 'WTNScGIyNDZZMjlzZFcxdU8yZGhjRG94Y0hoOUxuQmhhWEpmWDNKdmQzdGthWE53YkdGNU9tZHlhV1E3WjNKcFpDMTBaVzF3YkdGMFpTMWpiMngxYlc1ek9q'
    || 'WXljSGdnYldsdWJXRjRLREFzTVdaeUtTQXhPSEI0SUcxcGJtMWhlQ2d3TERGbWNpazdaMkZ3T2psd2VEdGhiR2xuYmkxcGRHVnRjenBpWVhObGJHbHVaVHRt'
    || 'YjI1MExYTnBlbVU2TVRKd2VEdHdZV1JrYVc1bk9qUndlQ0EyY0hnN1ltOXlaR1Z5TFhKaFpHbDFjem8wY0hoOUxuQmhhWEpmWDJ4aFltVnNlMlp2Ym5RdGMy'
    || 'bDZaVG94TVhCNE8yWnZiblF0ZDJWcFoyaDBPall3TUR0MFpYaDBMWFJ5WVc1elptOXliVHAxY0hCbGNtTmhjMlU3YkdWMGRHVnlMWE53WVdOcGJtYzZMakEw'
    || 'WlcwN1kyOXNiM0k2ZG1GeUtDMHRaR2x0S1gwdWNHRnBjbDlmZG1Gc2UyOTJaWEptYkc5M0xYZHlZWEE2WVc1NWQyaGxjbVU3WTI5c2IzSTZkbUZ5S0MwdGRH'
    || 'VjRkQ2w5TG5CaGFYSmZYMjFoY210N2RHVjRkQzFoYkdsbmJqcGpaVzUwWlhJN1ptOXVkQzEzWldsbmFIUTZOekF3TzJadmJuUXRkbUZ5YVdGdWRDMXVkVzFs'
    || 'Y21sak9uUmhZblZzWVhJdGJuVnRjMzB1Y0dGcGNsOWZjbTkzTFMxa2FXWm1lMkpoWTJ0bmNtOTFibVE2ZG1GeUtDMHRkMkZ5YmkxM1lYTm9LWDB1Y0dGcGNs'
    || 'OWZjbTkzTFMxa2FXWm1JQzV3WVdseVgxOXRZWEpyZTJOdmJHOXlPaU5oT0RaaE1EVjlMbkJoYVhKZlgzSnZkeTB0YzJGdFpTQXVjR0ZwY2w5ZmJXRnlhM3Rq'
    || 'YjJ4dmNqcDJZWElvTFMxa2FXMHBmUzV1YjNSbGMzdHRZWEpuYVc0Nk1EdHdZV1JrYVc1bkxXeGxablE2TVRsd2VIMHVibTkwWlhNZ2JHbDdiV0Z5WjJsdU9q'
    || 'QWdNQ0F4TUhCNE8yeHBibVV0YUdWcFoyaDBPakV1Tmp0amIyeHZjanAyWVhJb0xTMXRkWFJsWkNrN1ptOXVkQzF6YVhwbE9qRXlMalZ3ZUgwdWJtOTBaWE1n'
    || 'YkdrZ2MzUnliMjVuZTJOdmJHOXlPblpoY2lndExYUmxlSFFwTzJadmJuUXRkMlZwWjJoME9qWXdNSDB1Ym05MFpYTWdiR2s2YkdGemRDMWphR2xzWkh0dFlY'
    || 'Sm5hVzR0WW05MGRHOXRPakI5TG01dmRHVnpJR052WkdWN1ltRmphMmR5YjNWdVpEcDJZWElvTFMxemRYSm1ZV05sTFRJcE8ySnZjbVJsY2pveGNIZ2djMjlz'
    || 'YVdRZ2RtRnlLQzB0YkdsdVpTazdjR0ZrWkdsdVp6b3hjSGdnTlhCNE8ySnZjbVJsY2kxeVlXUnBkWE02TkhCNE8yWnZiblF0YzJsNlpUb3hNUzQxY0hnN1ky'
    || 'OXNiM0k2ZG1GeUtDMHRibUYyZVNsOUxuQmhibVZzTFdWeWNtOXllMkpoWTJ0bmNtOTFibVE2ZG1GeUtDMHRZbUZrTFhkaGMyZ3BPMkp2Y21SbGNqb3hjSGdn'
    || 'YzI5c2FXUWdjbWRpWVNneU16SXNNQ3d5T0N3dU16SXBPMkp2Y21SbGNpMXlZV1JwZFhNNmRtRnlLQzB0Y21Ga2FYVnpLVHR3WVdSa2FXNW5PakV4Y0hnZ01U'
    || 'TndlRHRtYjI1MExYTnBlbVU2TVRJdU5YQjRmUzV3WVc1bGJDMWxjbkp2Y2lCemRISnZibWQ3WkdsemNHeGhlVHBpYkc5amF6dGpiMnh2Y2pwMllYSW9MUzFp'
    || 'WVdRcE8yMWhjbWRwYmkxaWIzUjBiMjA2TlhCNGZTNXdZVzVsYkMxbGNuSnZjaUJqYjJSbGUyTnZiRzl5T2lNNFpqQXdNVFE3ZDI5eVpDMWljbVZoYXpwaWNt'
    || 'VmhheTEzYjNKa08zZG9hWFJsTFhOd1lXTmxPbkJ5WlMxM2NtRndPMlp2Ym5RdGMybDZaVG94TVM0MWNIaDlMbkJoYm1Wc0xXVnRjSFI1TEM1d1lXNWxiQzF0'
    || 'YVhOemFXNW5lMk52Ykc5eU9uWmhjaWd0TFcxMWRHVmtLVHRtYjI1MExYTnBlbVU2TVRJdU5YQjRPMjFoY21kcGJqb3dmUzV3WVc1bGJDMTBjblZ1WTN0aVlX'
    || 'TnJaM0p2ZFc1a09uWmhjaWd0TFhkaGNtNHRkMkZ6YUNrN1ltOXlaR1Z5T2pGd2VDQnpiMnhwWkNCeVoySmhLREkwTlN3eE5UZ3NNVEVzTGpRcE8ySnZjbVJs'
    || 'Y2kxeVlXUnBkWE02TkhCNE8zQmhaR1JwYm1jNk9IQjRJREV4Y0hnN2JXRnlaMmx1T2pBZ01DQXhNWEI0TzJadmJuUXRjMmw2WlRveE1TNDFjSGc3WTI5c2Iz'
    || 'STZJemhoTlRZd01EdHNhVzVsTFdobGFXZG9kRG94TGpWOUxtTmhkbVZoZEh0aVlXTnJaM0p2ZFc1a09uWmhjaWd0TFhkaGNtNHRkMkZ6YUNrN1ltOXlaR1Z5'
    || 'T2pGd2VDQnpiMnhwWkNCeVoySmhLREkwTlN3eE5UZ3NNVEVzTGpRcE8ySnZjbVJsY2kxeVlXUnBkWE02ZG1GeUtDMHRjbUZrYVhWektUdHdZV1JrYVc1bk9q'
    || 'RXhjSGdnTVROd2VEdHRZWEpuYVc0Nk1USndlQ0F3SURBN1ptOXVkQzF6YVhwbE9qRXlMalZ3ZUgwdVkyRjJaV0YwSUhOMGNtOXVaM3RrYVhOd2JHRjVPbUpz'
    || 'YjJOck8yTnZiRzl5T2lNNFlUVTJNREE3YldGeVoybHVMV0p2ZEhSdmJUbzFjSGc3Wm05dWRDMTNaV2xuYUhRNk56QXdmUzVqWVhabFlYUWdjSHR0WVhKbmFX'
    || 'NDZNRHRqYjJ4dmNqcDJZWElvTFMxdGRYUmxaQ2s3YkdsdVpTMW9aV2xuYUhRNk1TNDJmUzV3WVc1bGJDMXViM1JpZFdsc2RIdGlZV05yWjNKdmRXNWtPblpo'
    || 'Y2lndExXRmpZMlZ1ZEMxM1lYTm9LVHRpYjNKa1pYSTZNWEI0SUhOdmJHbGtJSEpuWW1Fb01Dd3hNeklzTWpFeUxDNHpLVHRpYjNKa1pYSXRjbUZrYVhWek9u'
    || 'WmhjaWd0TFhKaFpHbDFjeWs3Y0dGa1pHbHVaem94TW5CNElERTBjSGc3Wm05dWRDMXphWHBsT2pFeUxqVndlSDB1Y0dGdVpXd3RibTkwWW5WcGJIUWdjM1J5'
    || 'YjI1bmUyUnBjM0JzWVhrNllteHZZMnM3WTI5c2IzSTZkbUZ5S0MwdFlXTmpaVzUwS1R0dFlYSm5hVzR0WW05MGRHOXRPalZ3ZUgwdWNHRnVaV3d0Ym05MFlu'
    || 'VnBiSFFnY0h0dFlYSm5hVzQ2TUR0amIyeHZjanAyWVhJb0xTMXRkWFJsWkNrN2JHbHVaUzFvWldsbmFIUTZNUzQyZlM1d1lXNWxiQzF1YjNSaWRXbHNkRjlm'
    || 'WVd4MGUyMWhjbWRwYmkxMGIzQTZPSEI0SVdsdGNHOXlkR0Z1ZER0bWIyNTBMWE5wZW1VNk1URXVOWEI0TzI5d1lXTnBkSGs2TGpsOUxtNXZkSGxsZEh0aVlX'
    || 'TnJaM0p2ZFc1a09uWmhjaWd0TFhOMWNtWmhZMlV0TWlrN1ltOXlaR1Z5T2pGd2VDQnpiMnhwWkNCMllYSW9MUzFzYVc1bEtUdGliM0prWlhJdGNtRmthWFZ6'
    || 'T25aaGNpZ3RMWEpoWkdsMWN5azdjR0ZrWkdsdVp6b3hOWEI0SURFM2NIZ2dNVFp3ZUR0bWIyNTBMWE5wZW1VNk1USXVOWEI0ZlM1dWIzUjVaWFErYzNSeWIy'
    || 'NW5lMlJwYzNCc1lYazZZbXh2WTJzN1kyOXNiM0k2ZG1GeUtDMHRibUYyZVNrN1ptOXVkQzF6YVhwbE9qRXpMalZ3ZUR0dFlYSm5hVzR0WW05MGRHOXRPamR3'
    || 'ZUgwdWJtOTBlV1YwSUhCN2JXRnlaMmx1T2pBN1kyOXNiM0k2ZG1GeUtDMHRiWFYwWldRcE8yeHBibVV0YUdWcFoyaDBPakV1Tm4wdWJtOTBlV1YwSUdOdlpH'
    || 'VjdZbUZqYTJkeWIzVnVaRHAyWVhJb0xTMXpkWEptWVdObEtUdGliM0prWlhJNk1YQjRJSE52Ykdsa0lIWmhjaWd0TFd4cGJtVXRNaWs3Y0dGa1pHbHVaem94'
    || 'Y0hnZ05YQjRPMkp2Y21SbGNpMXlZV1JwZFhNNk5IQjRPMlp2Ym5RdGMybDZaVG94TVM0MWNIZzdZMjlzYjNJNmRtRnlLQzB0Ym1GMmVTazdkMmhwZEdVdGMz'
    || 'QmhZMlU2Ym05M2NtRndmUzV1YjNSNVpYUmZYM2RvWVhSN2JXRnlaMmx1TFhSdmNEb3hNM0I0SVdsdGNHOXlkR0Z1ZER0amIyeHZjanAyWVhJb0xTMTBaWGgw'
    || 'S1NGcGJYQnZjblJoYm5RN1ptOXVkQzEzWldsbmFIUTZOVEF3ZlM1dWIzUjVaWFJmWDNScFpYSnplMjFoY21kcGJqbzVjSGdnTUNBd08zQmhaR1JwYm1jNk1E'
    || 'dHNhWE4wTFhOMGVXeGxPbTV2Ym1VN1pHbHpjR3hoZVRwbWJHVjRPMlpzWlhndFpHbHlaV04wYVc5dU9tTnZiSFZ0Ymp0bllYQTZPSEI0ZlM1dWIzUjVaWFJm'
    || 'WDNScFpYSnpJR3hwZTJScGMzQnNZWGs2WjNKcFpEdG5jbWxrTFhSbGJYQnNZWFJsTFdOdmJIVnRibk02T1Rad2VDQnRhVzV0WVhnb01Dd3habklwTzJkaGNE'
    || 'b3hNbkI0TzJGc2FXZHVMV2wwWlcxek9tSmhjMlZzYVc1bE8zQmhaR1JwYm1jdGJHVm1kRG94TVhCNE8ySnZjbVJsY2kxc1pXWjBPakp3ZUNCemIyeHBaQ0Iy'
    || 'WVhJb0xTMXNhVzVsTFRJcGZTNXViM1I1WlhSZlgzUnBaWEo3Wm05dWRDMXphWHBsT2pFeGNIZzdabTl1ZEMxM1pXbG5hSFE2TnpBd08yeGxkSFJsY2kxemNH'
    || 'RmphVzVuT2k0d05HVnRPM1JsZUhRdGRISmhibk5tYjNKdE9uVndjR1Z5WTJGelpUdGpiMnh2Y2pwMllYSW9MUzFrYVcwcGZTNXViM1I1WlhSZlgzUnBaWEl0'
    || 'WkdWelkzdGpiMnh2Y2pwMllYSW9MUzF0ZFhSbFpDazdiR2x1WlMxb1pXbG5hSFE2TVM0MU8yWnZiblF0YzJsNlpUb3hNbkI0ZlM1dWIzUjVaWFJmWDJadmIz'
    || 'UjdiV0Z5WjJsdUxYUnZjRG94TTNCNElXbHRjRzl5ZEdGdWREdHdZV1JrYVc1bkxYUnZjRG94TVhCNE8ySnZjbVJsY2kxMGIzQTZNWEI0SUhOdmJHbGtJSFpo'
    || 'Y2lndExXeHBibVVwTzJadmJuUXRjMmw2WlRveE1TNDFjSGg5TG1aaGRHRnNlMkpoWTJ0bmNtOTFibVE2ZG1GeUtDMHRZbUZrTFhkaGMyZ3BPMkp2Y21SbGNq'
    || 'b3hjSGdnYzI5c2FXUWdjbWRpWVNneU16SXNNQ3d5T0N3dU16WXBPMkp2Y21SbGNpMXlZV1JwZFhNNmRtRnlLQzB0Y21Ga2FYVnpMV3huS1R0d1lXUmthVzVu'
    || 'T2pJd2NIZ2dNakp3ZUR0dFlYSm5hVzQ2TWpSd2VIMHVabUYwWVd3Z2FERjdiV0Z5WjJsdU9qQWdNQ0E1Y0hnN1ptOXVkQzF6YVhwbE9qRTNjSGc3WTI5c2Iz'
    || 'STZkbUZ5S0MwdFltRmtLWDB1Wm1GMFlXd2dZMjlrWlh0amIyeHZjam9qT0dZd01ERTBPM2RvYVhSbExYTndZV05sT25CeVpTMTNjbUZ3TzJadmJuUXRjMmw2'
    || 'WlRveE1uQjRmUzVrYjI1MWRIdGthWE53YkdGNU9tWnNaWGc3WVd4cFoyNHRhWFJsYlhNNlkyVnVkR1Z5TzJkaGNEb3hPSEI0ZlM1a2IyNTFkRjlmWm1sbmUy'
    || 'WnNaWGc2Ym05dVpYMHVaRzl1ZFhSZlgydGxlWHRrYVhOd2JHRjVPbVpzWlhnN1pteGxlQzFrYVhKbFkzUnBiMjQ2WTI5c2RXMXVPMmRoY0RvM2NIZzdiV2x1'
    || 'TFhkcFpIUm9PakI5TG1SdmJuVjBYMTl5YjNkN1pHbHpjR3hoZVRwbWJHVjRPMkZzYVdkdUxXbDBaVzF6T21ObGJuUmxjanRuWVhBNk9IQjRPMlp2Ym5RdGMy'
    || 'bDZaVG94TW5CNGZTNWtiMjUxZEY5ZmMzZDdkMmxrZEdnNk9YQjRPMmhsYVdkb2REbzVjSGc3WW05eVpHVnlMWEpoWkdsMWN6b3pjSGc3Wm14bGVEcHViMjVs'
    || 'ZlM1a2IyNTFkRjlmYkdGaWUyTnZiRzl5T25aaGNpZ3RMVzExZEdWa0tUdHZkbVZ5Wm14dmR6cG9hV1JrWlc0N2RHVjRkQzF2ZG1WeVpteHZkenBsYkd4cGNI'
    || 'TnBjenQzYUdsMFpTMXpjR0ZqWlRwdWIzZHlZWEI5TG1SdmJuVjBYMTkyWVd4N1kyOXNiM0k2ZG1GeUtDMHRkR1Y0ZENrN1ptOXVkQzEzWldsbmFIUTZOakF3'
    || 'TzJadmJuUXRkbUZ5YVdGdWRDMXVkVzFsY21sak9uUmhZblZzWVhJdGJuVnRjenR0WVhKbmFXNHRiR1ZtZERwaGRYUnZmUzVrYjI1MWRGOWZZMlZ1ZEdWeWUy'
    || 'WnZiblF0ZG1GeWFXRnVkQzF1ZFcxbGNtbGpPblJoWW5Wc1lYSXRiblZ0YzMwdWMzQmhjbXQ3WkdsemNHeGhlVHBpYkc5amEzMHVjM0JoY210ZlgyeHBibVY3'
    || 'Wm1sc2JEcHViMjVsTzNOMGNtOXJaVHAyWVhJb0xTMWhZMk5sYm5RcE8zTjBjbTlyWlMxM2FXUjBhRG95TzNOMGNtOXJaUzFzYVc1bFkyRndPbkp2ZFc1a08z'
    || 'TjBjbTlyWlMxc2FXNWxhbTlwYmpweWIzVnVaSDB1YzNCaGNtdGZYMkZ5WldGN1ptbHNiRHAyWVhJb0xTMWhZMk5sYm5RdGQyRnphQ2s3YzNSeWIydGxPbTV2'
    || 'Ym1WOUxuTndZWEpyWDE5a2IzUjdabWxzYkRwMllYSW9MUzFoWTJObGJuUXBmUzVtYkc5M2UyUnBjM0JzWVhrNlpteGxlRHRoYkdsbmJpMXBkR1Z0Y3pwemRI'
    || 'SmxkR05vTzIxaGNtZHBiaTEwYjNBNk5uQjRmUzVtYkc5M1gxOWliM2g3Wm14bGVEb3hJREVnTUR0dGFXNHRkMmxrZEdnNk1EdDBaWGgwTFdGc2FXZHVPbU5s'
    || 'Ym5SbGNqdGlZV05yWjNKdmRXNWtPblpoY2lndExYTjFjbVpoWTJVcE8ySnZjbVJsY2pveGNIZ2djMjlzYVdRZ2RtRnlLQzB0YkdsdVpTMHlLVHRpYjNKa1pY'
    || 'SXRjbUZrYVhWek9qRXdjSGc3Y0dGa1pHbHVaem94TVhCNElERXdjSGg5TG1ac2IzZGZYMkp2ZUMwdGIyNTdZbUZqYTJkeWIzVnVaRHAyWVhJb0xTMWhZMk5s'
    || 'Ym5RdGQyRnphQ2s3WW05eVpHVnlMV052Ykc5eU9uWmhjaWd0TFdGalkyVnVkQ2w5TG1ac2IzZGZYMnhoWW50bWIyNTBMWE5wZW1VNk1URXVOWEI0TzJadmJu'
    || 'UXRkMlZwWjJoME9qWXdNRHRqYjJ4dmNqcDJZWElvTFMxdVlYWjVLVHRzYVc1bExXaGxhV2RvZERveExqTTdiM1psY21ac2IzY3RkM0poY0RwaGJubDNhR1Z5'
    || 'WlgwdVpteHZkMTlmYzNWaWUyWnZiblF0YzJsNlpUb3hNWEI0TzJOdmJHOXlPblpoY2lndExXUnBiU2s3YldGeVoybHVMWFJ2Y0RvemNIZzdiR2x1WlMxb1pX'
    || 'bG5hSFE2TVM0emZTNW1iRzkzWDE5c2FXNXJlMlpzWlhnNk1DQXdJREkwY0hnN1lXeHBaMjR0YzJWc1pqcGpaVzUwWlhJN2FHVnBaMmgwT2pKd2VEdGlZV05y'
    || 'WjNKdmRXNWtPblpoY2lndExXeHBibVV0TWlrN1ltOXlaR1Z5TFhKaFpHbDFjem95Y0hoOUxtWnNiM2RmWDJ4cGJtc3RMVzl1ZTJKaFkydG5jbTkxYm1RdGFX'
    || 'MWhaMlU2YkdsdVpXRnlMV2R5WVdScFpXNTBLRGt3WkdWbkxIWmhjaWd0TFhOcmVTa2dNQ0EwTlNVc2RISmhibk53WVhKbGJuUWdORFVsSURFd01DVXBPMkpo'
    || 'WTJ0bmNtOTFibVF0YzJsNlpUb3hNM0I0SURKd2VEdGlZV05yWjNKdmRXNWtMWEpsY0dWaGREcHlaWEJsWVhRdGVEdGlZV05yWjNKdmRXNWtMV052Ykc5eU9u'
    || 'UnlZVzV6Y0dGeVpXNTBmUzVoWTNSZlgzUnBaWEo3YldGeVoybHVPakUyY0hnZ01DQXljSGc3Wm05dWRDMXphWHBsT2pFeGNIZzdabTl1ZEMxM1pXbG5hSFE2'
    || 'TnpBd08zUmxlSFF0ZEhKaGJuTm1iM0p0T25Wd2NHVnlZMkZ6WlR0c1pYUjBaWEl0YzNCaFkybHVaem91TURSbGJUdGpiMnh2Y2pwMllYSW9MUzF0ZFhSbFpD'
    || 'bDlMbUZqZEY5ZmRHbGxjaTFrWlhOamUyMWhjbWRwYmpvd0lEQWdNVEJ3ZUR0bWIyNTBMWE5wZW1VNk1USndlRHRqYjJ4dmNqcDJZWElvTFMxdGRYUmxaQ2s3'
    || 'YkdsdVpTMW9aV2xuYUhRNk1TNDFmUzVoWTNSZlgyZHlhV1I3WkdsemNHeGhlVHBuY21sa08yZGhjRG94TUhCNE8yZHlhV1F0ZEdWdGNHeGhkR1V0WTI5c2RX'
    || 'MXVjenB5WlhCbFlYUW9ZWFYwYnkxbWFYUXNiV2x1YldGNEtESTBNSEI0TERGbWNpa3BPMjFoY21kcGJpMWliM1IwYjIwNk1UUndlSDB1WVdOMFgxOWpZWEpr'
    || 'ZTJKaFkydG5jbTkxYm1RNmRtRnlLQzB0YzNWeVptRmpaUzB5S1R0aWIzSmtaWEk2TVhCNElITnZiR2xrSUhaaGNpZ3RMV3hwYm1VcE8ySnZjbVJsY2kxeVlX'
    || 'UnBkWE02ZG1GeUtDMHRjbUZrYVhWektUdHdZV1JrYVc1bk9qRXljSGdnTVRSd2VIMHVZV04wWDE5amIyUmxlMlp2Ym5RdGMybDZaVG94TVhCNE8yWnZiblF0'
    || 'ZDJWcFoyaDBPamN3TUR0MFpYaDBMWFJ5WVc1elptOXliVHAxY0hCbGNtTmhjMlU3YkdWMGRHVnlMWE53WVdOcGJtYzZMakEwWlcwN1kyOXNiM0k2ZG1GeUtD'
    || 'MHRZV05qWlc1MEtUdHRZWEpuYVc0dFltOTBkRzl0T2pOd2VIMHVZV04wWDE5c1lXSmxiSHRtYjI1MExYTnBlbVU2TVROd2VEdG1iMjUwTFhkbGFXZG9kRG8y'
    || 'TURBN1kyOXNiM0k2ZG1GeUtDMHRibUYyZVNrN2JHbHVaUzFvWldsbmFIUTZNUzR6ZlM1aFkzUmZYMlZtWm1WamRIdG1iMjUwTFhOcGVtVTZNVEp3ZUR0amIy'
    || 'eHZjanAyWVhJb0xTMXRkWFJsWkNrN2JXRnlaMmx1TFhSdmNEbzBjSGc3YkdsdVpTMW9aV2xuYUhRNk1TNDBOWDB1WVdOMFgxOXRaWFJoZTJScGMzQnNZWGs2'
    || 'Wm14bGVEdG1iR1Y0TFhkeVlYQTZkM0poY0R0bllYQTZObkI0SURFeWNIZzdiV0Z5WjJsdUxYUnZjRG80Y0hnN1ptOXVkQzF6YVhwbE9qRXhjSGc3WTI5c2Iz'
    || 'STZkbUZ5S0MwdGJYVjBaV1FwZlM1aFkzUmZYM1Z1Wkc5N1kyOXNiM0k2ZG1GeUtDMHRaMjl2WkNrN1ptOXVkQzEzWldsbmFIUTZOakF3ZlM1aFkzUmZYMjV2'
    || 'ZFc1a2IzdGpiMnh2Y2pwMllYSW9MUzFrYVcwcGZTNWhZM1JmWDNKMWJuTjdabTl1ZEMxemFYcGxPakV4Y0hnN1kyOXNiM0k2ZG1GeUtDMHRiWFYwWldRcE8y'
    || 'MWhjbWRwYmkxMGIzQTZObkI0TzJadmJuUXRkMlZwWjJoME9qVXdNSDB1WVdOMFgxOW1iMjkwZTIxaGNtZHBiam94TkhCNElEQWdNRHRtYjI1MExYTnBlbVU2'
    || 'TVRKd2VEdGpiMnh2Y2pwMllYSW9MUzF0ZFhSbFpDazdiR2x1WlMxb1pXbG5hSFE2TVM0MU5UdGliM0prWlhJdGRHOXdPakZ3ZUNCemIyeHBaQ0IyWVhJb0xT'
    || 'MXNhVzVsS1R0d1lXUmthVzVuTFhSdmNEb3hNbkI0ZlM1eWRudHZjR0ZqYVhSNU9qQTdkSEpoYm5ObWIzSnRPblJ5WVc1emJHRjBaVmtvTjNCNEtUdGhibWx0'
    || 'WVhScGIyNDZjblpwYmlBdU5USnpJSFpoY2lndExXVmhjMlVwSUdadmNuZGhjbVJ6ZlVCclpYbG1jbUZ0WlhNZ2NuWnBibnQwYjN0dmNHRmphWFI1T2pFN2RI'
    || 'Smhibk5tYjNKdE9tNXZibVY5ZlVCdFpXUnBZU2h3Y21WbVpYSnpMWEpsWkhWalpXUXRiVzkwYVc5dU9uSmxaSFZqWlNsN0tudGhibWx0WVhScGIyNDZibTl1'
    || 'WlNGcGJYQnZjblJoYm5RN2RISmhibk5wZEdsdmJqcHViMjVsSVdsdGNHOXlkR0Z1ZEgwdWNuWjdiM0JoWTJsMGVUb3hPM1J5WVc1elptOXliVHB1YjI1bGZY'
    || 'MHVZWEJ3WDE5b1pXRmtjbWxuYUhSN1pteGxlRHB1YjI1bE8yUnBjM0JzWVhrNlpteGxlRHRtYkdWNExXUnBjbVZqZEdsdmJqcGpiMngxYlc0N1lXeHBaMjR0'
    || 'YVhSbGJYTTZabXhsZUMxbGJtUTdaMkZ3T2pod2VIMHVjRzlqTFdOb2FYQjdaR2x6Y0d4aGVUcHBibXhwYm1VdFpteGxlRHRoYkdsbmJpMXBkR1Z0Y3pwaVlY'
    || 'TmxiR2x1WlR0bllYQTZOM0I0TzNCaFpHUnBibWM2Tm5CNElERXhjSGc3WW05eVpHVnlMWEpoWkdsMWN6cDJZWElvTFMxeVlXUnBkWE1wTzJKdmNtUmxjam94'
    || 'Y0hnZ2MyOXNhV1FnZG1GeUtDMHRiR2x1WlNrN1ltRmphMmR5YjNWdVpEcDJZWElvTFMxemRYSm1ZV05sS1R0bWIyNTBPbWx1YUdWeWFYUTdZM1Z5YzI5eU9u'
    || 'QnZhVzUwWlhJN2QyaHBkR1V0YzNCaFkyVTZibTkzY21Gd08zUnlZVzV6YVhScGIyNDZZbUZqYTJkeWIzVnVaQ0F1TVRKeklHVmhjMlVzWW05eVpHVnlMV052'
    || 'Ykc5eUlDNHhNbk1nWldGelpYMHVjRzlqTFdOb2FYQTZhRzkyWlhKN1ltRmphMmR5YjNWdVpEcDJZWElvTFMxemRYSm1ZV05sTFRJcE8ySnZjbVJsY2kxamIy'
    || 'eHZjanAyWVhJb0xTMXNhVzVsTFRJcGZTNXdiMk10WTJocGNDMHRjM1JoZEdsamUyTjFjbk52Y2pwa1pXWmhkV3gwZlM1d2IyTXRZMmhwY0MwdGMzUmhkR2xq'
    || 'T21odmRtVnllMkpoWTJ0bmNtOTFibVE2ZG1GeUtDMHRjM1Z5Wm1GalpTazdZbTl5WkdWeUxXTnZiRzl5T25aaGNpZ3RMV3hwYm1VcGZTNXdiMk10WTJocGNE'
    || 'cG1iMk4xY3kxMmFYTnBZbXhsZTI5MWRHeHBibVU2TW5CNElITnZiR2xrSUhaaGNpZ3RMV0ZqWTJWdWRDazdiM1YwYkdsdVpTMXZabVp6WlhRNk1uQjRmUzV3'
    || 'YjJNdFkyaHBjRjlmYm5WdGUyWnZiblF0YzJsNlpUb3hOWEI0TzJadmJuUXRkMlZwWjJoME9qY3dNRHRtYjI1MExYWmhjbWxoYm5RdGJuVnRaWEpwWXpwMFlX'
    || 'SjFiR0Z5TFc1MWJYTTdiR1YwZEdWeUxYTndZV05wYm1jNkxTNHdNV1Z0ZlM1d2IyTXRZMmhwY0Y5ZmQyOXlaSHRtYjI1MExYTnBlbVU2TVRGd2VEdG1iMjUw'
    || 'TFhkbGFXZG9kRG8yTURBN2RHVjRkQzEwY21GdWMyWnZjbTA2ZFhCd1pYSmpZWE5sTzJ4bGRIUmxjaTF6Y0dGamFXNW5PaTR3TkdWdE8yTnZiRzl5T25aaGNp'
    || 'Z3RMVzExZEdWa0tYMHVjRzlqTFdOb2FYQmZYMlpzWVdkN1ptOXVkQzF6YVhwbE9qRXhjSGc3Wm05dWRDMTNaV2xuYUhRNk5qQXdPM1JsZUhRdGRISmhibk5t'
    || 'YjNKdE9uVndjR1Z5WTJGelpUdHNaWFIwWlhJdGMzQmhZMmx1WnpvdU1EUmxiVHR3WVdSa2FXNW5MV3hsWm5RNk4zQjRPMjFoY21kcGJpMXNaV1owT2pGd2VE'
    || 'dGliM0prWlhJdGJHVm1kRG94Y0hnZ2MyOXNhV1FnZG1GeUtDMHRiR2x1WlNrN1kyOXNiM0k2ZG1GeUtDMHRiWFYwWldRcGZTNXdiMk10WTJocGNDMHRaMjl2'
    || 'Wkh0aWIzSmtaWEl0WTI5c2IzSTZJekUyWVRNMFlUVTVPMkpoWTJ0bmNtOTFibVE2ZG1GeUtDMHRaMjl2WkMxM1lYTm9LWDB1Y0c5akxXTm9hWEF0TFdkdmIy'
    || 'UWdMbkJ2WXkxamFHbHdYMTl1ZFcxN1kyOXNiM0k2ZG1GeUtDMHRaMjl2WkNsOUxuQnZZeTFqYUdsd0xTMTNZWEp1ZTJKdmNtUmxjaTFqYjJ4dmNqb2paalU1'
    || 'WlRCaU5qWTdZbUZqYTJkeWIzVnVaRHAyWVhJb0xTMTNZWEp1TFhkaGMyZ3BmUzV3YjJNdFkyaHBjQzB0ZDJGeWJpQXVjRzlqTFdOb2FYQmZYMjUxYlh0amIy'
    || 'eHZjam9qWVRFMk1qQTNmUzV3YjJNdFkyaHBjQzB0WW1Ga2UySnZjbVJsY2kxamIyeHZjam9qWlRnd01ERmpOVGs3WW1GamEyZHliM1Z1WkRwMllYSW9MUzFp'
    || 'WVdRdGQyRnphQ2w5TG5Cdll5MWphR2x3TFMxaVlXUWdMbkJ2WXkxamFHbHdYMTl1ZFcxN1kyOXNiM0k2ZG1GeUtDMHRZbUZrS1gwdWNHOWpMV05vYVhBdExX'
    || 'bGtiR1VnTG5Cdll5MWphR2x3WDE5dWRXMTdZMjlzYjNJNmRtRnlLQzB0YlhWMFpXUXBmUzV1WVhaZlgySmhaR2RsZTJac1pYZzZibTl1WlR0dFlYSm5hVzR0'
    || 'YkdWbWREcGhkWFJ2TzNCaFpHUnBibWM2TVhCNElEWndlRHRpYjNKa1pYSXRjbUZrYVhWek9qSXdjSGc3Wm05dWRDMXphWHBsT2pFeGNIZzdabTl1ZEMxM1pX'
    || 'bG5hSFE2TnpBd08yWnZiblF0ZG1GeWFXRnVkQzF1ZFcxbGNtbGpPblJoWW5Wc1lYSXRiblZ0Y3p0aWIzSmtaWEk2TVhCNElITnZiR2xrSUhaaGNpZ3RMV3hw'
    || 'Ym1VcE8ySmhZMnRuY205MWJtUTZkbUZ5S0MwdGMzVnlabUZqWlMweUtUdGpiMnh2Y2pwMllYSW9MUzF0ZFhSbFpDbDlMbTVoZGw5ZlltRmtaMlV0TFdkdmIy'
    || 'UjdZMjlzYjNJNmRtRnlLQzB0WjI5dlpDazdZbTl5WkdWeUxXTnZiRzl5T2lNeE5tRXpOR0UxT1R0aVlXTnJaM0p2ZFc1a09uWmhjaWd0TFdkdmIyUXRkMkZ6'
    || 'YUNsOUxtNWhkbDlmWW1Ga1oyVXRMWGRoY201N1kyOXNiM0k2STJFeE5qSXdOenRpYjNKa1pYSXRZMjlzYjNJNkkyWTFPV1V3WWpZMk8ySmhZMnRuY205MWJt'
    || 'UTZkbUZ5S0MwdGQyRnliaTEzWVhOb0tYMHVibUYyWDE5aVlXUm5aUzB0WW1Ga2UyTnZiRzl5T25aaGNpZ3RMV0poWkNrN1ltOXlaR1Z5TFdOdmJHOXlPaU5s'
    || 'T0RBd01XTTFPVHRpWVdOclozSnZkVzVrT25aaGNpZ3RMV0poWkMxM1lYTm9LWDB1Ym1GMlgxOWlZV1JuWlMwdGFXUnNaWHRqYjJ4dmNqcDJZWElvTFMxdGRY'
    || 'UmxaQ2w5TG01aGRsOWZZbUZrWjJVckxtNWhkbDlmWkc5MGUyMWhjbWRwYmkxc1pXWjBPalp3ZUgwdWNHOWplMlJwYzNCc1lYazZabXhsZUR0bWJHVjRMV1Jw'
    || 'Y21WamRHbHZianBqYjJ4MWJXNDdaMkZ3T2pFeWNIaDlMbkJ2WTE5ZmRtVnlaR2xqZEh0aWIzSmtaWEk2TW5CNElITnZiR2xrSUhaaGNpZ3RMV3hwYm1VcE8y'
    || 'SnZjbVJsY2kxeVlXUnBkWE02ZG1GeUtDMHRjbUZrYVhWektUdGlZV05yWjNKdmRXNWtPblpoY2lndExYTjFjbVpoWTJVcE8zQmhaR1JwYm1jNk1UVndlQ0F4'
    || 'TjNCNGZTNXdiMk5mWDNabGNtUnBZM1F0TFdkdmIyUjdZbTl5WkdWeUxXTnZiRzl5T2lNeE5tRXpOR0UzTXp0aVlXTnJaM0p2ZFc1a09uWmhjaWd0TFdkdmIy'
    || 'UXRkMkZ6YUNsOUxuQnZZMTlmZG1WeVpHbGpkQzB0ZDJGeWJudGliM0prWlhJdFkyOXNiM0k2STJZMU9XVXdZamN6TzJKaFkydG5jbTkxYm1RNmRtRnlLQzB0'
    || 'ZDJGeWJpMTNZWE5vS1gwdWNHOWpYMTkyWlhKa2FXTjBMUzFpWVdSN1ltOXlaR1Z5TFdOdmJHOXlPaU5sT0RBd01XTTFPVHRpWVdOclozSnZkVzVrT25aaGNp'
    || 'Z3RMV0poWkMxM1lYTm9LWDB1Y0c5algxOTJaWEprYVdOMExTMXBaR3hsZTJKdmNtUmxjaTFqYjJ4dmNqcDJZWElvTFMxc2FXNWxMVElwZlM1d2IyTmZYMmhs'
    || 'WVdSc2FXNWxlMlp2Ym5RdGMybDZaVG96TUhCNE8yWnZiblF0ZDJWcFoyaDBPamN3TUR0c1pYUjBaWEl0YzNCaFkybHVaem90TGpBeU5XVnRPMlp2Ym5RdGRt'
    || 'RnlhV0Z1ZEMxdWRXMWxjbWxqT25SaFluVnNZWEl0Ym5WdGN6dGpiMnh2Y2pwMllYSW9MUzF1WVhaNUtUdHNhVzVsTFdobGFXZG9kRG94TGpGOUxuQnZZMTlm'
    || 'Y21WaFpIdHRZWEpuYVc0Nk5uQjRJREFnTUR0bWIyNTBMWE5wZW1VNk1USXVOWEI0TzJOdmJHOXlPblpoY2lndExXMTFkR1ZrS1R0c2FXNWxMV2hsYVdkb2RE'
    || 'b3hMalY5TG5CdlkxOWZkR0ZzYkhsN1pHbHpjR3hoZVRwbWJHVjRPMlpzWlhndGQzSmhjRHAzY21Gd08yZGhjRG94TkhCNE8yMWhjbWRwYmkxMGIzQTZNVEp3'
    || 'ZUgwdWNHOWpYMTkwYVdOcmUyWnZiblF0YzJsNlpUb3hNWEI0TzJadmJuUXRkMlZwWjJoME9qWXdNRHQwWlhoMExYUnlZVzV6Wm05eWJUcDFjSEJsY21OaGMy'
    || 'VTdiR1YwZEdWeUxYTndZV05wYm1jNkxqQTBaVzA3WTI5c2IzSTZkbUZ5S0MwdGJYVjBaV1FwZlM1d2IyTmZYM1JwWTJzZ1ludG1iMjUwTFhOcGVtVTZNVE53'
    || 'ZUR0bWIyNTBMWGRsYVdkb2REbzNNREE3Wm05dWRDMTJZWEpwWVc1MExXNTFiV1Z5YVdNNmRHRmlkV3hoY2kxdWRXMXpPMjFoY21kcGJpMXlhV2RvZERvemNI'
    || 'aDlMbkJ2WTE5ZmRHbGpheTB0YldWMElHSjdZMjlzYjNJNmRtRnlLQzB0WjI5dlpDbDlMbkJ2WTE5ZmRHbGpheTB0Ym05MGJXVjBJR0o3WTI5c2IzSTZkbUZ5'
    || 'S0MwdFltRmtLWDB1Y0c5algxOTBhV05yTFMxd1pXNWthVzVuSUdKN1kyOXNiM0k2ZG1GeUtDMHRiWFYwWldRcGZTNXdiMk5mWDNScFkyc3RMVzVoSUdKN1ky'
    || 'OXNiM0k2ZG1GeUtDMHRaR2x0S1gwdWNHOWpMWEp2ZDN0a2FYTndiR0Y1T21ac1pYZzdaMkZ3T2pFeWNIZzdjR0ZrWkdsdVp6b3hOSEI0SURFMmNIZzdZbTl5'
    || 'WkdWeU9qRndlQ0J6YjJ4cFpDQjJZWElvTFMxc2FXNWxLVHRpYjNKa1pYSXRjbUZrYVhWek9uWmhjaWd0TFhKaFpHbDFjeWs3WW1GamEyZHliM1Z1WkRwMllY'
    || 'SW9MUzF6ZFhKbVlXTmxLWDB1Y0c5akxYSnZkeTB0Ym05MGJXVjBlMkpoWTJ0bmNtOTFibVE2ZG1GeUtDMHRZbUZrTFhkaGMyZ3BPMkp2Y21SbGNpMWpiMnh2'
    || 'Y2pvalpUZ3dNREZqTXpoOUxuQnZZeTF5YjNjdExXMWxkSHRpWVdOclozSnZkVzVrT25aaGNpZ3RMWE4xY21aaFkyVXBmUzV3YjJNdGNtOTNMUzF1WVh0dmNH'
    || 'RmphWFI1T2k0M01uMHVjRzlqTFhKdmQxOWZiV0Z5YTN0bWJHVjRPbTV2Ym1VN2QybGtkR2c2TWpKd2VEdG9aV2xuYUhRNk1qSndlRHRpYjNKa1pYSXRjbUZr'
    || 'YVhWek9qVXdKVHRrYVhOd2JHRjVPbWR5YVdRN2NHeGhZMlV0YVhSbGJYTTZZMlZ1ZEdWeU8yWnZiblF0YzJsNlpUb3hNM0I0TzJadmJuUXRkMlZwWjJoME9q'
    || 'Y3dNRHRzYVc1bExXaGxhV2RvZERveGZTNXdiMk10Y205M0xTMXRaWFFnTG5Cdll5MXliM2RmWDIxaGNtdDdZbUZqYTJkeWIzVnVaRHAyWVhJb0xTMW5iMjlr'
    || 'TFhkaGMyZ3BPMk52Ykc5eU9uWmhjaWd0TFdkdmIyUXBmUzV3YjJNdGNtOTNMUzF1YjNSdFpYUWdMbkJ2WXkxeWIzZGZYMjFoY210N1ltRmphMmR5YjNWdVpE'
    || 'b2paVGd3TURGak1qRTdZMjlzYjNJNmRtRnlLQzB0WW1Ga0tYMHVjRzlqTFhKdmR5MHRjR1Z1WkdsdVp5QXVjRzlqTFhKdmQxOWZiV0Z5YTN0aVlXTnJaM0p2'
    || 'ZFc1a09uWmhjaWd0TFhOMWNtWmhZMlV0TXlrN1kyOXNiM0k2ZG1GeUtDMHRiWFYwWldRcGZTNXdiMk10Y205M0xTMXVZU0F1Y0c5akxYSnZkMTlmYldGeWEz'
    || 'dGlZV05yWjNKdmRXNWtPblJ5WVc1emNHRnlaVzUwTzJOdmJHOXlPblpoY2lndExXUnBiU2s3WW05NExYTm9ZV1J2ZHpwcGJuTmxkQ0F3SURBZ01DQXhjSGdn'
    || 'ZG1GeUtDMHRiR2x1WlMweUtYMHVjRzlqTFhKdmQxOWZZbTlrZVh0dGFXNHRkMmxrZEdnNk1EdG1iR1Y0T2pGOUxuQnZZeTF5YjNkZlgzUnZjSHRrYVhOd2JH'
    || 'RjVPbVpzWlhnN1lXeHBaMjR0YVhSbGJYTTZZbUZ6Wld4cGJtVTdaMkZ3T2pFd2NIZzdhblZ6ZEdsbWVTMWpiMjUwWlc1ME9uTndZV05sTFdKbGRIZGxaVzU5'
    || 'TG5Cdll5MXliM2RmWDJ4aFltVnNlMlp2Ym5RdGMybDZaVG94TXk0MWNIZzdabTl1ZEMxM1pXbG5hSFE2TmpBd08yTnZiRzl5T25aaGNpZ3RMVzVoZG5rcE8y'
    || 'eHBibVV0YUdWcFoyaDBPakV1TXpWOUxuQnZZeTF5YjNkZlgzTjBZWFJsZTJac1pYZzZibTl1WlR0bWIyNTBMWE5wZW1VNk1URndlRHRtYjI1MExYZGxhV2Rv'
    || 'ZERvM01EQTdkR1Y0ZEMxMGNtRnVjMlp2Y20wNmRYQndaWEpqWVhObE8yeGxkSFJsY2kxemNHRmphVzVuT2k0d05HVnRmUzV3YjJNdGNtOTNYMTl6ZEdGMFpT'
    || 'MHRiV1YwZTJOdmJHOXlPblpoY2lndExXZHZiMlFwZlM1d2IyTXRjbTkzWDE5emRHRjBaUzB0Ym05MGJXVjBlMk52Ykc5eU9uWmhjaWd0TFdKaFpDbDlMbkJ2'
    || 'WXkxeWIzZGZYM04wWVhSbExTMXdaVzVrYVc1bmUyTnZiRzl5T25aaGNpZ3RMVzExZEdWa0tYMHVjRzlqTFhKdmQxOWZjM1JoZEdVdExXNWhlMk52Ykc5eU9u'
    || 'WmhjaWd0TFdScGJTbDlMbkJ2WXkxeWIzZGZYM2RvZVh0dFlYSm5hVzQ2TlhCNElEQWdNRHRtYjI1MExYTnBlbVU2TVRKd2VEdGpiMnh2Y2pwMllYSW9MUzF0'
    || 'ZFhSbFpDazdiR2x1WlMxb1pXbG5hSFE2TVM0MWZTNXdiMk10Y205M1gxOXRZWFJvZTIxaGNtZHBiam80Y0hnZ01DQXdmUzV3YjJNdGNtOTNYMTl0WVhSb0lH'
    || 'TnZaR1Y3WkdsemNHeGhlVHBwYm14cGJtVXRZbXh2WTJzN2NHRmtaR2x1WnpvemNIZ2dPSEI0TzJKdmNtUmxjaTF5WVdScGRYTTZOWEI0TzJKaFkydG5jbTkx'
    || 'Ym1RNmRtRnlLQzB0YzNWeVptRmpaUzB5S1R0aWIzSmtaWEk2TVhCNElITnZiR2xrSUhaaGNpZ3RMV3hwYm1VcE8yWnZiblF0YzJsNlpUb3hNbkI0TzJadmJu'
    || 'UXRkbUZ5YVdGdWRDMXVkVzFsY21sak9uUmhZblZzWVhJdGJuVnRjenRqYjJ4dmNqcDJZWElvTFMxdVlYWjVLWDB1Y0c5akxYSnZkMTlmYldGMGFDMHRibTl1'
    || 'Wlh0bWIyNTBMWE5wZW1VNk1URXVOWEI0TzJOdmJHOXlPblpoY2lndExXUnBiU2s3Wm05dWRDMXpkSGxzWlRwcGRHRnNhV045TG5Cdll5MXliM2RmWDNCbGJt'
    || 'UjdiV0Z5WjJsdU9qZHdlQ0F3SURBN1ptOXVkQzF6YVhwbE9qRXljSGc3WTI5c2IzSTZkbUZ5S0MwdGRHVjRkQ2s3YkdsdVpTMW9aV2xuYUhRNk1TNDFmUzV3'
    || 'YjJNdGNtOTNYMTkzYUdWdWUyMWhjbWRwYmpvMGNIZ2dNQ0F3TzJadmJuUXRjMmw2WlRveE1YQjRPMk52Ykc5eU9uWmhjaWd0TFcxMWRHVmtLVHRtYjI1MExY'
    || 'ZGxhV2RvZERvMk1EQjlMbkJ2WXkxeWIzZGZYMjFsZEdGN2JXRnlaMmx1T2pFd2NIZ2dNQ0F3TzNCaFpHUnBibWN0ZEc5d09qbHdlRHRpYjNKa1pYSXRkRzl3'
    || 'T2pGd2VDQnpiMnhwWkNCMllYSW9MUzFzYVc1bEtUdGthWE53YkdGNU9tZHlhV1E3WjJGd09qaHdlQ0F5TUhCNE8yZHlhV1F0ZEdWdGNHeGhkR1V0WTI5c2RX'
    || 'MXVjem94Wm5KOVFHMWxaR2xoS0cxcGJpMTNhV1IwYURvNU1EQndlQ2w3TG5Cdll5MXliM2RmWDIxbGRHRjdaM0pwWkMxMFpXMXdiR0YwWlMxamIyeDFiVzV6'
    || 'T2pObWNpQXhabko5ZlM1d2IyTXRjbTkzWDE5dFpYUmhJR1IwZTJadmJuUXRjMmw2WlRveE1YQjRPMlp2Ym5RdGQyVnBaMmgwT2pZd01EdDBaWGgwTFhSeVlX'
    || 'NXpabTl5YlRwMWNIQmxjbU5oYzJVN2JHVjBkR1Z5TFhOd1lXTnBibWM2TGpBMFpXMDdZMjlzYjNJNmRtRnlLQzB0WkdsdEtUdHRZWEpuYVc0dFltOTBkRzl0'
    || 'T2pKd2VIMHVjRzlqTFhKdmQxOWZiV1YwWVNCa1pIdHRZWEpuYVc0Nk1EdG1iMjUwTFhOcGVtVTZNVEV1TlhCNE8yTnZiRzl5T25aaGNpZ3RMVzExZEdWa0tU'
    || 'dHNhVzVsTFdobGFXZG9kRG94TGpWOUxuQnZZeTF5YjNkZlgyMWxkR0VnWkdRZ1kyOWtaWHRtYjI1MExYTnBlbVU2TVRGd2VEdGpiMnh2Y2pwMllYSW9MUzF1'
    || 'WVhaNUtYMHVjRzlqWDE5dWIzUmxlMjFoY21kcGJqb3ljSGdnTUNBd08zQmhaR1JwYm1jNk1UQndlQ0F4TTNCNE8ySnZjbVJsY2kxeVlXUnBkWE02ZG1GeUtD'
    || 'MHRjbUZrYVhWektUdGlZV05yWjNKdmRXNWtPblpoY2lndExYTjFjbVpoWTJVdE1pazdZbTl5WkdWeU9qRndlQ0J6YjJ4cFpDQjJZWElvTFMxc2FXNWxLVHRt'
    || 'YjI1MExYTnBlbVU2TVRGd2VEdGpiMnh2Y2pwMllYSW9MUzF0ZFhSbFpDazdiR2x1WlMxb1pXbG5hSFE2TVM0MU5YMHVjRzlqTFdWdGNIUjVlM0JoWkdScGJt'
    || 'YzZNakJ3ZUR0aWIzSmtaWEl0Y21Ga2FYVnpPblpoY2lndExYSmhaR2wxY3lrN1ltOXlaR1Z5T2pGd2VDQmtZWE5vWldRZ2RtRnlLQzB0YkdsdVpTMHlLVHRp'
    || 'WVdOclozSnZkVzVrT25aaGNpZ3RMWE4xY21aaFkyVXBmUzV3YjJNdFpXMXdkSGtnYURON2JXRnlaMmx1T2pBN1ptOXVkQzF6YVhwbE9qRTBjSGc3WTI5c2Iz'
    || 'STZkbUZ5S0MwdGJtRjJlU2w5TG5Cdll5MWxiWEIwZVNCd2UyMWhjbWRwYmpvMmNIZ2dNQ0F4TUhCNE8yWnZiblF0YzJsNlpUb3hNaTQxY0hnN1kyOXNiM0k2'
    || 'ZG1GeUtDMHRiWFYwWldRcE8yeHBibVV0YUdWcFoyaDBPakV1TlgwdWNHOWpMV1Z0Y0hSNUlHTnZaR1Y3WkdsemNHeGhlVHBpYkc5amF6dHdZV1JrYVc1bk9q'
    || 'aHdlQ0F4TUhCNE8ySnZjbVJsY2kxeVlXUnBkWE02Tm5CNE8ySmhZMnRuY205MWJtUTZkbUZ5S0MwdGMzVnlabUZqWlMweUtUdGliM0prWlhJNk1YQjRJSE52'
    || 'Ykdsa0lIWmhjaWd0TFd4cGJtVXBPMlp2Ym5RdGMybDZaVG94TVhCNE8yTnZiRzl5T25aaGNpZ3RMWFJsZUhRcE8zZG9hWFJsTFhOd1lXTmxPbkJ5WlMxM2Nt'
    || 'RndPM2R2Y21RdFluSmxZV3M2WW5KbFlXc3RkMjl5WkgwdWFXNXpjR1ZqZEh0a2FYTndiR0Y1T21keWFXUTdaM0pwWkMxMFpXMXdiR0YwWlMxamIyeDFiVzV6'
    || 'T20xcGJtMWhlQ2d3TERGbWNpa2dNekF3Y0hnN1oyRndPakUyY0hnN1lXeHBaMjR0YVhSbGJYTTZjM1JoY25SOUxtbHVjM0JsWTNSZlgyeHBjM1I3YldsdUxY'
    || 'ZHBaSFJvT2pCOUxtbHVjM0JsWTNSZlgyUmxkR0ZwYkh0aVlXTnJaM0p2ZFc1a09uWmhjaWd0TFhOMWNtWmhZMlV0TWlrN1ltOXlaR1Z5T2pGd2VDQnpiMnhw'
    || 'WkNCMllYSW9MUzFzYVc1bEtUdGliM0prWlhJdGNtRmthWFZ6T25aaGNpZ3RMWEpoWkdsMWN5azdjR0ZrWkdsdVp6b3hOSEI0SURFMWNIZ2dNVFZ3ZUgwdWFX'
    || 'NXpjR1ZqZEY5ZmRHbDBiR1Y3YldGeVoybHVPakFnTUNBeE1IQjRPMlp2Ym5RdGMybDZaVG94TkhCNE8yWnZiblF0ZDJWcFoyaDBPall3TUR0amIyeHZjanAy'
    || 'WVhJb0xTMTBaWGgwS1R0dmRtVnlabXh2ZHkxM2NtRndPbUZ1ZVhkb1pYSmxmUzVwYm5Od1pXTjBYMTltYVdWc1pITjdaR2x6Y0d4aGVUcG5jbWxrTzJkeWFX'
    || 'UXRkR1Z0Y0d4aGRHVXRZMjlzZFcxdWN6cGhkWFJ2SUcxcGJtMWhlQ2d3TERGbWNpazdaMkZ3T2pkd2VDQXhNbkI0TzIxaGNtZHBiam93ZlM1cGJuTndaV04w'
    || 'WDE5bWFXVnNaSE1nWkhSN1ptOXVkQzF6YVhwbE9qRXhjSGc3Wm05dWRDMTNaV2xuYUhRNk5qQXdPM1JsZUhRdGRISmhibk5tYjNKdE9uVndjR1Z5WTJGelpU'
    || 'dHNaWFIwWlhJdGMzQmhZMmx1WnpvdU1EUmxiVHRqYjJ4dmNqcDJZWElvTFMxa2FXMHBPM2RvYVhSbExYTndZV05sT201dmQzSmhjSDB1YVc1emNHVmpkRjlm'
    || 'Wm1sbGJHUnpJR1JrZTIxaGNtZHBiam93TzJadmJuUXRjMmw2WlRveE1pNDFjSGc3WTI5c2IzSTZkbUZ5S0MwdGRHVjRkQ2s3Wm05dWRDMTJZWEpwWVc1MExX'
    || 'NTFiV1Z5YVdNNmRHRmlkV3hoY2kxdWRXMXpPMjkyWlhKbWJHOTNMWGR5WVhBNllXNTVkMmhsY21WOUxtbHVjM0JsWTNSZlgyNXZkR1Y3YldGeVoybHVPakV5'
    || 'Y0hnZ01DQXdPMlp2Ym5RdGMybDZaVG94TVM0MWNIZzdZMjlzYjNJNmRtRnlLQzB0YlhWMFpXUXBPMnhwYm1VdGFHVnBaMmgwT2pFdU5YMHVkR0ZpYkdVdExY'
    || 'QnBZMnNnZEdKdlpIa2dkSEo3WTNWeWMyOXlPbkJ2YVc1MFpYSjlMblJoWW14bExTMXdhV05ySUhSaWIyUjVJSFJ5T21odmRtVnllMkpoWTJ0bmNtOTFibVE2'
    || 'ZG1GeUtDMHRjM1Z5Wm1GalpTMHlLWDB1ZEdGaWJHVXRMWEJwWTJzZ2RHSnZaSGtnZEhJdWRISXRMVzl1ZTJKaFkydG5jbTkxYm1RNmRtRnlLQzB0WVdOalpX'
    || 'NTBMWGRoYzJncGZTNTBZV0pzWlMwdGNHbGpheUIwWW05a2VTQjBjanBtYjJOMWN5MTJhWE5wWW14bGUyOTFkR3hwYm1VNk1uQjRJSE52Ykdsa0lIWmhjaWd0'
    || 'TFdGalkyVnVkQ2s3YjNWMGJHbHVaUzF2Wm1aelpYUTZMVEp3ZUgwdWMyVm5YMTlpWVhKN1pHbHpjR3hoZVRwcGJteHBibVV0Wm14bGVEdG5ZWEE2TW5CNE8z'
    || 'QmhaR1JwYm1jNk1uQjRPMjFoY21kcGJpMWliM1IwYjIwNk1USndlRHRpWVdOclozSnZkVzVrT25aaGNpZ3RMWE4xY21aaFkyVXRNaWs3WW05eVpHVnlPakZ3'
    || 'ZUNCemIyeHBaQ0IyWVhJb0xTMXNhVzVsS1R0aWIzSmtaWEl0Y21Ga2FYVnpPamh3ZUgwdWMyVm5YMTlpZEc1N0xYZGxZbXRwZEMxaGNIQmxZWEpoYm1ObE9t'
    || 'NXZibVU3TFcxdmVpMWhjSEJsWVhKaGJtTmxPbTV2Ym1VN1lYQndaV0Z5WVc1alpUcHViMjVsTzJKdmNtUmxjam93TzJKaFkydG5jbTkxYm1RNmRISmhibk53'
    || 'WVhKbGJuUTdZM1Z5YzI5eU9uQnZhVzUwWlhJN2NHRmtaR2x1WnpvMWNIZ2dNVEZ3ZUR0aWIzSmtaWEl0Y21Ga2FYVnpPalp3ZUR0bWIyNTBPbWx1YUdWeWFY'
    || 'UTdabTl1ZEMxemFYcGxPakV5Y0hnN1ptOXVkQzEzWldsbmFIUTZOVEF3TzJOdmJHOXlPblpoY2lndExXMTFkR1ZrS1gwdWMyVm5YMTlpZEc0dExXOXVlMkpo'
    || 'WTJ0bmNtOTFibVE2ZG1GeUtDMHRjM1Z5Wm1GalpTazdZMjlzYjNJNmRtRnlLQzB0ZEdWNGRDazdZbTk0TFhOb1lXUnZkenAyWVhJb0xTMXphQzFqWVhKa0tY'
    || 'MHVjMlZuWDE5aWRHNDZabTlqZFhNdGRtbHphV0pzWlh0dmRYUnNhVzVsT2pKd2VDQnpiMnhwWkNCMllYSW9MUzFoWTJObGJuUXBPMjkxZEd4cGJtVXRiMlpt'
    || 'YzJWME9qRndlSDB1ZEhKbGJtUjdZbUZqYTJkeWIzVnVaRHAyWVhJb0xTMXpkWEptWVdObEtUdGliM0prWlhJNk1YQjRJSE52Ykdsa0lIWmhjaWd0TFd4cGJt'
    || 'VXBPMkp2Y21SbGNpMXlZV1JwZFhNNmRtRnlLQzB0Y21Ga2FYVnpLVHR3WVdSa2FXNW5PakV6Y0hnZ01UVndlQ0F4TkhCNE8yUnBjM0JzWVhrNlpteGxlRHRo'
    || 'YkdsbmJpMXBkR1Z0Y3pwbWJHVjRMV1Z1WkR0cWRYTjBhV1o1TFdOdmJuUmxiblE2YzNCaFkyVXRZbVYwZDJWbGJqdG5ZWEE2TVRSd2VIMHVkSEpsYm1SZlgy'
    || 'aGxZV1I3YldsdUxYZHBaSFJvT2pCOUxuUnlaVzVrWDE5emNHRnlhM3RrYVhOd2JHRjVPbVpzWlhnN1pteGxlQzFrYVhKbFkzUnBiMjQ2WTI5c2RXMXVPMkZz'
    || 'YVdkdUxXbDBaVzF6T21ac1pYZ3RaVzVrTzJkaGNEb3pjSGc3Wm14bGVEcHViMjVsZlM1MGNtVnVaRjlmZDJsdWUyWnZiblF0YzJsNlpUb3hNWEI0TzJ4bGRI'
    || 'UmxjaTF6Y0dGamFXNW5PaTR3TkdWdE8zUmxlSFF0ZEhKaGJuTm1iM0p0T25Wd2NHVnlZMkZ6WlR0amIyeHZjanAyWVhJb0xTMWthVzBwZlM1MGNtVnVaRjlm'
    || 'Ym05dVpYdG1iMjUwTFhOcGVtVTZNVEV1TlhCNE8yTnZiRzl5T25aaGNpZ3RMV1JwYlNrN1ptOXVkQzF6ZEhsc1pUcHViM0p0WVd4OUxuUnlaVzVrTFMxbmIy'
    || 'OWtJQzV6ZEdGMFgxOTJZV3gxWlh0amIyeHZjanAyWVhJb0xTMW5iMjlrS1gwdWRISmxibVF0TFhkaGNtNGdMbk4wWVhSZlgzWmhiSFZsZTJOdmJHOXlPblpo'
    || 'Y2lndExYZGhjbTRwZlM1MGNtVnVaQzB0WW1Ga0lDNXpkR0YwWDE5MllXeDFaWHRqYjJ4dmNqcDJZWElvTFMxaVlXUXBmVUJ0WldScFlTaHRZWGd0ZDJsa2RH'
    || 'ZzZNVEV3TUhCNEtYc3VhVzV6Y0dWamRIdG5jbWxrTFhSbGJYQnNZWFJsTFdOdmJIVnRibk02YldsdWJXRjRLREFzTVdaeUtYMTlMbTkyYkY5ZmMzVmllMlp2'
    || 'Ym5RdGMybDZaVG94TVhCNE8yeHBibVV0YUdWcFoyaDBPakV1TXpVN1kyOXNiM0k2ZG1GeUtDMHRaR2x0S1R0dFlYSm5hVzQ2TW5CNElEQWdObkI0TzI5MlpY'
    || 'Sm1iRzkzTFhkeVlYQTZZVzU1ZDJobGNtVTdabTl1ZEMxMllYSnBZVzUwTFc1MWJXVnlhV002ZEdGaWRXeGhjaTF1ZFcxemZTNXdZVzVsYkMxbGNuSnZjaTB0'
    || 'WVhWNGUyMWhjbWRwYmkxMGIzQTZNVEJ3ZUR0d1lXUmthVzVuT2pod2VDQXhNSEI0TzJadmJuUXRjMmw2WlRveE1uQjRmUzV3WVc1bGJDMWxjbkp2Y2kwdFlY'
    || 'VjRJSEI3YldGeVoybHVPalJ3ZUNBd0lEWndlSDB1Y0dGdVpXd3RkSEoxYm1NdExXRjFlQ3d1Y0dGdVpXd3RibTkwWW5WcGJIUXRMV0YxZUh0dFlYSm5hVzR0'
    || 'ZEc5d09qRXdjSGc3Wm05dWRDMXphWHBsT2pFeWNIaDlMbVJsWm14cGMzUjdiV0Z5WjJsdUxYUnZjRG95Y0hoOUxtUmxabXhwYzNSZlgyaGxZV1I3Wm05dWRD'
    || 'MXphWHBsT2pFeGNIZzdabTl1ZEMxM1pXbG5hSFE2TnpBd08zUmxlSFF0ZEhKaGJuTm1iM0p0T25Wd2NHVnlZMkZ6WlR0c1pYUjBaWEl0YzNCaFkybHVaem91'
    || 'TURSbGJUdGpiMnh2Y2pwMllYSW9MUzFrYVcwcE8zQmhaR1JwYm1jdFltOTBkRzl0T2pod2VEdHRZWEpuYVc0dFltOTBkRzl0T2pFd2NIZzdZbTl5WkdWeUxX'
    || 'SnZkSFJ2YlRveGNIZ2djMjlzYVdRZ2RtRnlLQzB0YkdsdVpTbDlMbVJsWm14cGMzUmZYMmR5YVdSN1pHbHpjR3hoZVRwbmNtbGtPMk52YkhWdGJpMW5ZWEE2'
    || 'TXpSd2VIMHVaR1ZtYkdsemRGOWZaM0pwWkMwdE1YdG5jbWxrTFhSbGJYQnNZWFJsTFdOdmJIVnRibk02TVdaeWZTNWtaV1pzYVhOMFgxOW5jbWxrTFMweWUy'
    || 'ZHlhV1F0ZEdWdGNHeGhkR1V0WTI5c2RXMXVjem94Wm5JZ01XWnlmVUJ0WldScFlTaHRZWGd0ZDJsa2RHZzZPVEF3Y0hncGV5NWtaV1pzYVhOMFgxOW5jbWxr'
    || 'TFMweWUyZHlhV1F0ZEdWdGNHeGhkR1V0WTI5c2RXMXVjem94Wm5KOWZTNWtaV1pzYVhOMFgxOXliM2Q3WkdsemNHeGhlVHBuY21sa08yZHlhV1F0ZEdWdGNH'
    || 'eGhkR1V0WTI5c2RXMXVjem94Wm5JZ1lYVjBienRuY21sa0xYUmxiWEJzWVhSbExXRnlaV0Z6T2lKc1lXSmxiQ0IyWVd4MVpTSWdJbTV2ZEdVZ2JtOTBaU0k3'
    || 'WVd4cFoyNHRhWFJsYlhNNlltRnpaV3hwYm1VN1kyOXNkVzF1TFdkaGNEb3hObkI0TzNCaFpHUnBibWM2TlhCNElEQTdiV2x1TFdobGFXZG9kRG95TkhCNE8y'
    || 'SnZjbVJsY2kxaWIzUjBiMjA2TVhCNElITnZiR2xrSUhaaGNpZ3RMV3hwYm1VdGMyOW1kQ3dnY21kaVlTZ3hOeXd4Tnl3eE55d3VNRFVwS1gwdVpHVm1iR2x6'
    || 'ZEY5ZmNtOTNPbXhoYzNRdFkyaHBiR1I3WW05eVpHVnlMV0p2ZEhSdmJUb3dmUzVrWldac2FYTjBYMTlzWVdKbGJIdG5jbWxrTFdGeVpXRTZiR0ZpWld3N1pt'
    || 'OXVkQzF6YVhwbE9qRXlMalZ3ZUR0amIyeHZjanAyWVhJb0xTMXRkWFJsWkNsOUxtUmxabXhwYzNSZlgzWmhiSFZsZTJkeWFXUXRZWEpsWVRwMllXeDFaVHRt'
    || 'YjI1MExYTnBlbVU2TVRJdU5YQjRPMlp2Ym5RdGQyVnBaMmgwT2pZd01EdGpiMnh2Y2pwMllYSW9MUzEwWlhoMEtUdDBaWGgwTFdGc2FXZHVPbkpwWjJoME8y'
    || 'WnZiblF0ZG1GeWFXRnVkQzF1ZFcxbGNtbGpPblJoWW5Wc1lYSXRiblZ0YzMwdVpHVm1iR2x6ZEY5ZmRtRnNkV1V0TFdkdmIyUjdZMjlzYjNJNmRtRnlLQzB0'
    || 'WjI5dlpDbDlMbVJsWm14cGMzUmZYM1poYkhWbExTMTNZWEp1ZTJOdmJHOXlPaU5pT0Rjek1HRjlMbVJsWm14cGMzUmZYM1poYkhWbExTMWlZV1I3WTI5c2Iz'
    || 'STZkbUZ5S0MwdFltRmtLWDB1WkdWbWJHbHpkRjlmYm05MFpYdG5jbWxrTFdGeVpXRTZibTkwWlR0bWIyNTBMWE5wZW1VNk1URndlRHRqYjJ4dmNqcDJZWElv'
    || 'TFMxa2FXMHBPMnhwYm1VdGFHVnBaMmgwT2pFdU5EVTdiV0Z5WjJsdUxYUnZjRG95Y0hoOUxtMWxkR2h2Wkh0bWIyNTBMWE5wZW1VNk1URndlRHRqYjJ4dmNq'
    || 'cDJZWElvTFMxa2FXMHBPMnhwYm1VdGFHVnBaMmgwT2pFdU5UdHRZWEpuYVc0dGRHOXdPamh3ZUgwdWJXVjBhRzlrSUhOMGNtOXVaM3RqYjJ4dmNqcDJZWElv'
    || 'TFMxdGRYUmxaQ2s3Wm05dWRDMTNaV2xuYUhRNk56QXdmUzVqWld4c0xTMXVZWHRtYjI1MExYTnBlbVU2TVRGd2VEdG1iMjUwTFhkbGFXZG9kRG8zTURBN2JH'
    || 'VjBkR1Z5TFhOd1lXTnBibWM2TGpBelpXMDdZMjlzYjNJNmRtRnlLQzB0YlhWMFpXUXBPMk4xY25OdmNqcG9aV3h3ZlM1alpXeHNMUzF1YjI1bGUyTnZiRzl5'
    || 'T25aaGNpZ3RMV1JwYlNrN1kzVnljMjl5T21obGJIQjlMbUZqZEMxemRXMXRZWEo1ZTJScGMzQnNZWGs2Wm14bGVEdGhiR2xuYmkxcGRHVnRjenBqWlc1MFpY'
    || 'STdaMkZ3T2pFd2NIZzdabXhsZUMxM2NtRndPbmR5WVhBN2NHRmtaR2x1WnpveE1IQjRJREUwY0hnN1ltOXlaR1Z5T2pGd2VDQnpiMnhwWkNCMllYSW9MUzFz'
    || 'YVc1bEtUdGliM0prWlhJdGNtRmthWFZ6T25aaGNpZ3RMWEpoWkdsMWN5azdZbUZqYTJkeWIzVnVaRHAyWVhJb0xTMXpkWEptWVdObExUSXBPMk4xY25OdmNq'
    || 'cHdiMmx1ZEdWeU8yWnZiblF0YzJsNlpUb3hNaTQxY0hnN1kyOXNiM0k2ZG1GeUtDMHRiWFYwWldRcE8yeHBibVV0YUdWcFoyaDBPakV1TkgwdVlXTjBMWE4x'
    || 'YlcxaGNuazZhRzkyWlhKN1ltRmphMmR5YjNWdVpEcDJZWElvTFMxemRYSm1ZV05sS1R0aWIzSmtaWEl0WTI5c2IzSTZkbUZ5S0MwdGJHbHVaUzB5S1gwdVlX'
    || 'TjBMWE4xYlcxaGNuazZabTlqZFhNdGRtbHphV0pzWlh0dmRYUnNhVzVsT2pKd2VDQnpiMnhwWkNCMllYSW9MUzFoWTJObGJuUXBPMjkxZEd4cGJtVXRiMlpt'
    || 'YzJWME9qSndlSDB1WVdOMExYTjFiVzFoY25sZlgyTnZkVzUwZTJadmJuUXRkMlZwWjJoME9qY3dNRHRqYjJ4dmNqcDJZWElvTFMxdVlYWjVLWDB1WVdOMExY'
    || 'TjFiVzFoY25sZlgzUnBaWEo3Wm05dWRDMXphWHBsT2pFeGNIZzdabTl1ZEMxM1pXbG5hSFE2TmpBd08zUmxlSFF0ZEhKaGJuTm1iM0p0T25Wd2NHVnlZMkZ6'
    || 'WlR0c1pYUjBaWEl0YzNCaFkybHVaem91TURSbGJUdHdZV1JrYVc1bk9qRndlQ0EzY0hnN1ltOXlaR1Z5TFhKaFpHbDFjem8wY0hnN1ltRmphMmR5YjNWdVpE'
    || 'cDJZWElvTFMxemRYSm1ZV05sS1R0aWIzSmtaWEk2TVhCNElITnZiR2xrSUhaaGNpZ3RMV3hwYm1VcE8yTnZiRzl5T25aaGNpZ3RMV1JwYlNsOUxtRmpkQzF6'
    || 'ZFcxdFlYSjVYMTlqYUdWMmNtOXVlMjFoY21kcGJpMXNaV1owT21GMWRHODdabXhsZURwdWIyNWxPM1J5WVc1emFYUnBiMjQ2ZEhKaGJuTm1iM0p0SUM0eWN5'
    || 'QjJZWElvTFMxbFlYTmxLVHRqYjJ4dmNqcDJZWElvTFMxa2FXMHBmUzVoWTNRdGMzVnRiV0Z5ZVY5ZlkyaGxkbkp2YmkwdGIzQmxibnQwY21GdWMyWnZjbTA2'
    || 'Y205MFlYUmxLREU0TUdSbFp5bDlMbVJ5YVd4c0xYSnZkMTlmZEc5bloyeGxleTEzWldKcmFYUXRZWEJ3WldGeVlXNWpaVHB1YjI1bE95MXRiM290WVhCd1pX'
    || 'RnlZVzVqWlRwdWIyNWxPMkZ3Y0dWaGNtRnVZMlU2Ym05dVpUdGliM0prWlhJNk1EdGlZV05yWjNKdmRXNWtPblJ5WVc1emNHRnlaVzUwTzJOMWNuTnZjanB3'
    || 'YjJsdWRHVnlPMlJwYzNCc1lYazZabXhsZUR0aGJHbG5iaTFwZEdWdGN6cGpaVzUwWlhJN1oyRndPamh3ZUR0M2FXUjBhRG94TURBbE8zQmhaR1JwYm1jNk9I'
    || 'QjRJREV3Y0hnN2RHVjRkQzFoYkdsbmJqcHNaV1owTzJadmJuUTZhVzVvWlhKcGREdGpiMnh2Y2pwcGJtaGxjbWwwTzJKdmNtUmxjaTF5WVdScGRYTTZObkI0'
    || 'ZlM1a2NtbHNiQzF5YjNkZlgzUnZaMmRzWlRwb2IzWmxjbnRpWVdOclozSnZkVzVrT25aaGNpZ3RMWE4xY21aaFkyVXRNaWw5TG1SeWFXeHNMWEp2ZDE5ZmRH'
    || 'OW5aMnhsT21adlkzVnpMWFpwYzJsaWJHVjdiM1YwYkdsdVpUb3ljSGdnYzI5c2FXUWdkbUZ5S0MwdFlXTmpaVzUwS1R0dmRYUnNhVzVsTFc5bVpuTmxkRG90'
    || 'TW5CNGZTNWtjbWxzYkMxeWIzZGZYMk5vWlhaeWIyNTdabXhsZURwdWIyNWxPM1J5WVc1emFYUnBiMjQ2ZEhKaGJuTm1iM0p0SUM0eE5uTWdkbUZ5S0MwdFpX'
    || 'RnpaU2s3WTI5c2IzSTZkbUZ5S0MwdFpHbHRLWDB1WkhKcGJHd3RjbTkzWDE5amFHVjJjbTl1TFMxdmNHVnVlM1J5WVc1elptOXliVHB5YjNSaGRHVW9PVEJr'
    || 'WldjcGZTNWtjbWxzYkMxeWIzZGZYMk5vYVd4a2NtVnVlMjkyWlhKbWJHOTNPbWhwWkdSbGJqdDBjbUZ1YzJsMGFXOXVPbTFoZUMxb1pXbG5hSFFnTGpKeklI'
    || 'WmhjaWd0TFdWaGMyVXBPM0JoWkdScGJtY3RiR1ZtZERveE9IQjRmUzVvYjNabGNpMWtaWFJoYVd4N2NHOXphWFJwYjI0NlptbDRaV1E3ZWkxcGJtUmxlRG81'
    || 'TURBN2NHOXBiblJsY2kxbGRtVnVkSE02Ym05dVpUdGlZV05yWjNKdmRXNWtPblpoY2lndExYTjFjbVpoWTJVcE8ySnZjbVJsY2pveGNIZ2djMjlzYVdRZ2Rt'
    || 'RnlLQzB0YkdsdVpTMHlLVHRpYjNKa1pYSXRjbUZrYVhWek9qaHdlRHR3WVdSa2FXNW5Pamh3ZUNBeE1YQjRPMkp2ZUMxemFHRmtiM2M2ZG1GeUtDMHRjMmd0'
    || 'YldRcE8yWnZiblF0YzJsNlpUb3hNbkI0TzJOdmJHOXlPblpoY2lndExYUmxlSFFwTzJ4cGJtVXRhR1ZwWjJoME9qRXVORFU3YldGNExYZHBaSFJvT2pJNE1I'
    || 'QjRPM2RvYVhSbExYTndZV05sT201dmNtMWhiSDB1YzJOaGJHVXRZbUZ5ZTJScGMzQnNZWGs2Wm14bGVEdDNhV1IwYURveE1EQWxPMmhsYVdkb2REb3lNbkI0'
    || 'TzJKdmNtUmxjaTF5WVdScGRYTTZOSEI0TzI5MlpYSm1iRzkzT21ocFpHUmxibjB1YzJOaGJHVXRZbUZ5WDE5elpXZDdiV2x1TFhkcFpIUm9Pakp3ZUR0d2Iz'
    || 'TnBkR2x2YmpweVpXeGhkR2wyWlgwdWMyTmhiR1V0WW1GeVgxOXpaV2M2Wm1seWMzUXRZMmhwYkdSN1ltOXlaR1Z5TFhKaFpHbDFjem8wY0hnZ01DQXdJRFJ3'
    || 'ZUgwdWMyTmhiR1V0WW1GeVgxOXpaV2M2YkdGemRDMWphR2xzWkh0aWIzSmtaWEl0Y21Ga2FYVnpPakFnTkhCNElEUndlQ0F3ZlM1elkyRnNaUzFpWVhKZlgy'
    || 'eGhZbVZzZTNCdmMybDBhVzl1T21GaWMyOXNkWFJsTzNSdmNEb3dPM0pwWjJoME9qQTdZbTkwZEc5dE9qQTdiR1ZtZERvd08yUnBjM0JzWVhrNlpteGxlRHRo'
    || 'YkdsbmJpMXBkR1Z0Y3pwalpXNTBaWEk3YW5WemRHbG1lUzFqYjI1MFpXNTBPbU5sYm5SbGNqdG1iMjUwTFhOcGVtVTZNVEZ3ZUR0bWIyNTBMWGRsYVdkb2RE'
    || 'bzJNREE3WTI5c2IzSTZJMlptWmp0dmRtVnlabXh2ZHpwb2FXUmtaVzQ3ZEdWNGRDMXZkbVZ5Wm14dmR6cGxiR3hwY0hOcGN6dDNhR2wwWlMxemNHRmpaVHB1'
    || 'YjNkeVlYQTdjR0ZrWkdsdVp6b3dJRFJ3ZUgwSyIKU09MVVRJT05fTkFNRSA9ICJSZXRhaWwgTWVyY2hhbnQgQWdlbnQiCkdMT0JBTF9OQU1FID0gIl9fTUVS'
    || 'Q0hBTlRfREFUQV9fIgpBUFBfT0JKRUNUID0gIiIKCmltcG9ydCBqc29uCmltcG9ydCByZQoKCmRlZiB2YWxpZGF0ZV9jdXN0b21pemF0aW9uKHJhdyk6CiAg'
    || 'ICBpZiBpc2luc3RhbmNlKHJhdywgc3RyKToKICAgICAgICByYXcgPSBqc29uLmxvYWRzKHJhdykKICAgIGlmIG5vdCBpc2luc3RhbmNlKHJhdywgZGljdCk6'
    || 'CiAgICAgICAgcmFpc2UgVmFsdWVFcnJvcigiQ3VzdG9taXphdGlvbiBtdXN0IGJlIGEgSlNPTiBvYmplY3QiKQogICAgYWxsb3dlZCA9IHsidmVyc2lvbiIs'
    || 'ICJ0aXRsZSIsICJkZWZhdWx0X3NlY3Rpb24iLCAic2VjdGlvbl9sYWJlbHMiLCAic2VjdGlvbl9vcmRlciIsICJwYW5lbHMifQogICAgdW5rbm93biA9IHNl'
    || 'dChyYXcpIC0gYWxsb3dlZAogICAgaWYgdW5rbm93bjoKICAgICAgICByYWlzZSBWYWx1ZUVycm9yKCJVbmtub3duIGN1c3RvbWl6YXRpb24ga2V5czogIiAr'
    || 'ICIsICIuam9pbihzb3J0ZWQodW5rbm93bikpKQogICAgaWYgcmF3LmdldCgidmVyc2lvbiIsIDEpICE9IDE6CiAgICAgICAgcmFpc2UgVmFsdWVFcnJvcigi'
    || 'T25seSBjdXN0b21pemF0aW9uIHZlcnNpb24gMSBpcyBzdXBwb3J0ZWQiKQoKICAgIGRlZiB0ZXh0KHZhbHVlLCBsaW1pdCk6CiAgICAgICAgaWYgbm90IGlz'
    || 'aW5zdGFuY2UodmFsdWUsIHN0cikgb3Igbm90IHZhbHVlLnN0cmlwKCkgb3IgbGVuKHZhbHVlKSA+IGxpbWl0OgogICAgICAgICAgICByYWlzZSBWYWx1ZUVy'
    || 'cm9yKCJFeHBlY3RlZCBub25lbXB0eSB0ZXh0IG9mIGF0IG1vc3QgIiArIHN0cihsaW1pdCkgKyAiIGNoYXJhY3RlcnMiKQogICAgICAgIHJldHVybiB2YWx1'
    || 'ZQoKICAgIGRlZiBzZWN0aW9uKHZhbHVlKToKICAgICAgICB2YWx1ZSA9IHRleHQodmFsdWUsIDgwKQogICAgICAgIGlmIG5vdCByZS5mdWxsbWF0Y2gociJb'
    || 'YS16XVthLXowLTlfXSoiLCB2YWx1ZSk6CiAgICAgICAgICAgIHJhaXNlIFZhbHVlRXJyb3IoIkludmFsaWQgc2VjdGlvbiBJRDogIiArIHZhbHVlKQogICAg'
    || 'ICAgIHJldHVybiB2YWx1ZQoKICAgIHJlc3VsdCA9IHsidmVyc2lvbiI6IDEsICJzZWN0aW9uX2xhYmVscyI6IHt9LCAic2VjdGlvbl9vcmRlciI6IFtdLCAi'
    || 'cGFuZWxzIjogW119CiAgICBpZiAidGl0bGUiIGluIHJhdzoKICAgICAgICByZXN1bHRbInRpdGxlIl0gPSB0ZXh0KHJhd1sidGl0bGUiXSwgMTIwKQogICAg'
    || 'aWYgImRlZmF1bHRfc2VjdGlvbiIgaW4gcmF3OgogICAgICAgIHJlc3VsdFsiZGVmYXVsdF9zZWN0aW9uIl0gPSBzZWN0aW9uKHJhd1siZGVmYXVsdF9zZWN0'
    || 'aW9uIl0pCiAgICBsYWJlbHMgPSByYXcuZ2V0KCJzZWN0aW9uX2xhYmVscyIsIHt9KQogICAgaWYgbm90IGlzaW5zdGFuY2UobGFiZWxzLCBkaWN0KSBvciBs'
    || 'ZW4obGFiZWxzKSA+IDMwOgogICAgICAgIHJhaXNlIFZhbHVlRXJyb3IoInNlY3Rpb25fbGFiZWxzIG11c3QgY29udGFpbiBhdCBtb3N0IDMwIGVudHJpZXMi'
    || 'KQogICAgZm9yIGtleSwgdmFsdWUgaW4gbGFiZWxzLml0ZW1zKCk6CiAgICAgICAga2V5ID0gc2VjdGlvbihrZXkpCiAgICAgICAgaWYga2V5ID09ICJwb2Nf'
    || 'c3VjY2VzcyI6CiAgICAgICAgICAgIHJhaXNlIFZhbHVlRXJyb3IoIlBPQyBzdWNjZXNzIGNhbm5vdCBiZSByZW5hbWVkIikKICAgICAgICByZXN1bHRbInNl'
    || 'Y3Rpb25fbGFiZWxzIl1ba2V5XSA9IHRleHQodmFsdWUsIDgwKQogICAgb3JkZXIgPSByYXcuZ2V0KCJzZWN0aW9uX29yZGVyIiwgW10pCiAgICBpZiBub3Qg'
    || 'aXNpbnN0YW5jZShvcmRlciwgbGlzdCkgb3IgbGVuKG9yZGVyKSA+IDMwOgogICAgICAgIHJhaXNlIFZhbHVlRXJyb3IoInNlY3Rpb25fb3JkZXIgbXVzdCBi'
    || 'ZSBhIGxpc3Qgb2YgYXQgbW9zdCAzMCBzZWN0aW9uIElEcyIpCiAgICByZXN1bHRbInNlY3Rpb25fb3JkZXIiXSA9IFtzZWN0aW9uKHZhbHVlKSBmb3IgdmFs'
    || 'dWUgaW4gb3JkZXJdCiAgICBpZiBsZW4oc2V0KHJlc3VsdFsic2VjdGlvbl9vcmRlciJdKSkgIT0gbGVuKG9yZGVyKToKICAgICAgICByYWlzZSBWYWx1ZUVy'
    || 'cm9yKCJzZWN0aW9uX29yZGVyIGNvbnRhaW5zIGR1cGxpY2F0ZXMiKQogICAgcGFuZWxzID0gcmF3LmdldCgicGFuZWxzIiwgW10pCiAgICBpZiBub3QgaXNp'
    || 'bnN0YW5jZShwYW5lbHMsIGxpc3QpIG9yIGxlbihwYW5lbHMpID4gNjoKICAgICAgICByYWlzZSBWYWx1ZUVycm9yKCJBdCBtb3N0IHNpeCBjdXN0b20gcGFu'
    || 'ZWxzIGFyZSBzdXBwb3J0ZWQiKQogICAgdXNlZCA9IHNldCgpCiAgICBmb3IgcGFuZWwgaW4gcGFuZWxzOgogICAgICAgIGlmIG5vdCBpc2luc3RhbmNlKHBh'
    || 'bmVsLCBkaWN0KSBvciBzZXQocGFuZWwpIC0geyJpZCIsICJ0aXRsZSIsICJ2aWV3IiwgImtpbmQiLCAibGltaXQifToKICAgICAgICAgICAgcmFpc2UgVmFs'
    || 'dWVFcnJvcigiSW52YWxpZCBwYW5lbCBmaWVsZHMiKQogICAgICAgIHBhbmVsX2lkID0gc2VjdGlvbihwYW5lbC5nZXQoImlkIikpCiAgICAgICAgaWYgbm90'
    || 'IHBhbmVsX2lkLnN0YXJ0c3dpdGgoImN1c3RvbV8iKSBvciBwYW5lbF9pZCBpbiB1c2VkOgogICAgICAgICAgICByYWlzZSBWYWx1ZUVycm9yKCJQYW5lbCBJ'
    || 'RHMgbXVzdCBiZSB1bmlxdWUgYW5kIHN0YXJ0IHdpdGggY3VzdG9tXyIpCiAgICAgICAgdXNlZC5hZGQocGFuZWxfaWQpCiAgICAgICAgdmlldyA9IHRleHQo'
    || 'cGFuZWwuZ2V0KCJ2aWV3IiksIDEyOCkKICAgICAgICBpZiBub3QgcmUuZnVsbG1hdGNoKHIiVl9DVVNUT01fW0EtWjAtOV9dKyIsIHZpZXcpOgogICAgICAg'
    || 'ICAgICByYWlzZSBWYWx1ZUVycm9yKCJQYW5lbCB2aWV3cyBtdXN0IGJlIHVucXVhbGlmaWVkIFZfQ1VTVE9NXyogaWRlbnRpZmllcnMiKQogICAgICAgIGtp'
    || 'bmQgPSBwYW5lbC5nZXQoImtpbmQiLCAidGFibGUiKQogICAgICAgIGlmIGtpbmQgbm90IGluIHsidGFibGUiLCAiYmFyIiwgIm1ldHJpYyJ9OgogICAgICAg'
    || 'ICAgICByYWlzZSBWYWx1ZUVycm9yKCJQYW5lbCBraW5kIG11c3QgYmUgdGFibGUsIGJhciwgb3IgbWV0cmljIikKICAgICAgICBsaW1pdCA9IHBhbmVsLmdl'
    || 'dCgibGltaXQiLCAxMDApCiAgICAgICAgaWYgdHlwZShsaW1pdCkgaXMgbm90IGludCBvciBub3QgMSA8PSBsaW1pdCA8PSAyMDA6CiAgICAgICAgICAgIHJh'
    || 'aXNlIFZhbHVlRXJyb3IoIlBhbmVsIGxpbWl0IG11c3QgYmUgYW4gaW50ZWdlciBmcm9tIDEgdG8gMjAwIikKICAgICAgICByZXN1bHRbInBhbmVscyJdLmFw'
    || 'cGVuZCh7ImlkIjogcGFuZWxfaWQsICJ0aXRsZSI6IHRleHQocGFuZWwuZ2V0KCJ0aXRsZSIpLCAxMjApLAogICAgICAgICAgICAgICAgICAgICAgICAgICAg'
    || 'ICAgICAidmlldyI6IHZpZXcsICJraW5kIjoga2luZCwgImxpbWl0IjogbGltaXR9KQogICAgcmV0dXJuIHJlc3VsdAoKCmRlZiBsb2FkX2N1c3RvbWl6YXRp'
    || 'b24oc2Vzc2lvbiwgdGFyZ2V0KToKICAgIHRyeToKICAgICAgICByZWNvcmRzID0gc2Vzc2lvbi5zcWwoIlNFTEVDVCBDT05GSUcgRlJPTSAiICsgdGFyZ2V0'
    || 'ICsKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIi5BUFBfQ1VTVE9NSVpBVElPTiBXSEVSRSBJRCA9ICdkZWZhdWx0JyIpLmxpbWl0KDIpLmNvbGxl'
    || 'Y3QoKQogICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBleGM6CiAgICAgICAgcmV0dXJuIHt9LCB7fSwgIkN1c3RvbWl6YXRpb24gdW5hdmFpbGFibGU6ICIgKyBz'
    || 'dHIoZXhjKQogICAgaWYgbm90IHJlY29yZHM6CiAgICAgICAgcmV0dXJuIHt9LCB7fSwgTm9uZQogICAgaWYgbGVuKHJlY29yZHMpICE9IDE6CiAgICAgICAg'
    || 'cmV0dXJuIHt9LCB7fSwgIkN1c3RvbWl6YXRpb24gcmVqZWN0ZWQ6IGV4cGVjdGVkIGV4YWN0bHkgb25lIGRlZmF1bHQgcm93IgogICAgdHJ5OgogICAgICAg'
    || 'IGNvbmZpZyA9IHZhbGlkYXRlX2N1c3RvbWl6YXRpb24ocmVjb3Jkc1swXVsiQ09ORklHIl0pCiAgICBleGNlcHQgKFZhbHVlRXJyb3IsIFR5cGVFcnJvciwg'
    || 'S2V5RXJyb3IpIGFzIGV4YzoKICAgICAgICByZXR1cm4ge30sIHt9LCAiQ3VzdG9taXphdGlvbiByZWplY3RlZDogIiArIHN0cihleGMpCiAgICBwYW5lbHMg'
    || 'PSB7fQogICAgZm9yIHNwZWMgaW4gY29uZmlnWyJwYW5lbHMiXToKICAgICAgICB0cnk6CiAgICAgICAgICAgIHJvd3MgPSBbcm93LmFzX2RpY3QoKSBmb3Ig'
    || 'cm93IGluIHNlc3Npb24uc3FsKAogICAgICAgICAgICAgICAgIlNFTEVDVCAqIEZST00gIiArIHRhcmdldCArICIuIiArIHNwZWNbInZpZXciXSArICIgT1JE'
    || 'RVIgQlkgMSIKICAgICAgICAgICAgKS5saW1pdChzcGVjWyJsaW1pdCJdICsgMSkuY29sbGVjdCgpXQogICAgICAgICAgICBpZiBzcGVjWyJraW5kIl0gaW4g'
    || 'eyJiYXIiLCAibWV0cmljIn0gYW5kIHJvd3M6CiAgICAgICAgICAgICAgICBpZiBub3QgeyJMQUJFTCIsICJWQUxVRSJ9Lmlzc3Vic2V0KHJvd3NbMF0pOgog'
    || 'ICAgICAgICAgICAgICAgICAgIHJhaXNlIFZhbHVlRXJyb3IoIkJhciBhbmQgbWV0cmljIHZpZXdzIG11c3QgZXhwb3NlIExBQkVMIGFuZCBWQUxVRSBjb2x1'
    || 'bW5zIikKICAgICAgICAgICAgcmVzdWx0ID0geyJyb3dzIjoganNvbi5sb2Fkcyhqc29uLmR1bXBzKHJvd3NbOnNwZWNbImxpbWl0Il1dLCBkZWZhdWx0PXN0'
    || 'cikpfQogICAgICAgICAgICBpZiBsZW4ocm93cykgPiBzcGVjWyJsaW1pdCJdOgogICAgICAgICAgICAgICAgcmVzdWx0WyJ0cnVuY2F0ZWQiXSA9IHNwZWNb'
    || 'ImxpbWl0Il0KICAgICAgICAgICAgcGFuZWxzW3NwZWNbImlkIl1dID0gcmVzdWx0CiAgICAgICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBleGM6CiAgICAgICAg'
    || 'ICAgIHBhbmVsc1tzcGVjWyJpZCJdXSA9IHsiZXJyb3IiOiBzdHIoZXhjKX0KICAgIHJldHVybiBjb25maWcsIHBhbmVscywgTm9uZQoKCiMgRklSU1QgU3Ry'
    || 'ZWFtbGl0IGNhbGwsIGJlZm9yZSBhbnl0aGluZyBlbHNlIGNhbiBiZWNvbWUgb25lLiBTdHJlYW1saXQncyAibWFnaWMiCiMgcmVuZGVycyBhbnkgYmFyZSB0'
    || 'b3AtbGV2ZWwgZXhwcmVzc2lvbiAtLSBpbmNsdWRpbmcgYSBtb2R1bGUgZG9jc3RyaW5nIC0tIGFzCiMgbWFya2Rvd24sIGFuZCB0aGF0IGNvdW50cyBhcyBh'
    || 'IFN0cmVhbWxpdCBjb21tYW5kLCBhZnRlciB3aGljaCBzZXRfcGFnZV9jb25maWcKIyByYWlzZXMgU3RyZWFtbGl0QVBJRXhjZXB0aW9uIGFuZCB0aGUgcGFn'
    || 'ZSBpcyBhIHRyYWNlYmFjay4KIwojIFRoYXQgaXMgbm90IGEgaHlwb3RoZXRpY2FsLiBUaGlzIGhvc3QgdXNlZCB0byBjYWxsIHNldF9wYWdlX2NvbmZpZyBi'
    || 'ZWxvdyB0aGUKIyBwYW5lbCBzcGxpY2U7IHNwbGljaW5nIGEgcGFuZWxzLnB5IHRoYXQgb3BlbmVkIHdpdGggYSBkb2NzdHJpbmcgcmVuZGVyZWQgdGhlCiMg'
    || 'ZG9jc3RyaW5nIGFzIHBhZ2UgcHJvc2UsIGFuZCB0aGUgYXBwIHNoaXBwZWQgYXMgYW4gZXhjZXB0aW9uLiBOb3RoaW5nIGluIHRoZQojIHBpcGVsaW5lIGNh'
    || 'dWdodCBpdCwgYmVjYXVzZSBub3RoaW5nIGV4ZWN1dGVkIHRoaXMgZmlsZSBvdXRzaWRlIFNub3dmbGFrZSAtLQojIGdhdW50bGV0IHN0ZXAgMTAgcGFyc2Vz'
    || 'IFBBTkVMUyBvdXQgb2YgaXQgYW5kIHJ1bnMgdGhlIFNRTCBpdHNlbGYuIGJ1bmRsZS5weSBub3cKIyBleGVjdXRlcyB0aGlzIG1vZHVsZSBhZ2FpbnN0IHN0'
    || 'dWJiZWQgc3RyZWFtbGl0L3Nub3dwYXJrIG1vZHVsZXMgYW5kIGFzc2VydHMKIyBzZXRfcGFnZV9jb25maWcgaXMgdGhlIGZpcnN0IGNhbGwsIHdoaWNoIGlz'
    || 'IHRoZSBvbmx5IGNoZWNrIHRoYXQgd291bGQgaGF2ZS4Kc3Quc2V0X3BhZ2VfY29uZmlnKHBhZ2VfdGl0bGU9U09MVVRJT05fTkFNRSwgbGF5b3V0PSJ3aWRl'
    || 'IikKCiMg4pSA4pSAIE1ha2UgU3RyZWFtbGl0IGdldCBvdXQgb2YgdGhlIHdheSDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi'
    || 'lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKIyBUaGUgYXBwIGlz'
    || 'IG9uZSBmdWxsLWJsZWVkIFJlYWN0IHBhZ2UgaW5zaWRlIGNvbXBvbmVudHMuaHRtbC4gV2l0aG91dCB0aGlzLAojIFN0cmVhbWxpdCBmcmFtZXMgaXQgaW4g'
    || 'aXRzIG93biBjaHJvbWU6IGEgZGFyayBwYWdlIGJhY2tncm91bmQgYXJvdW5kIHRoZQojIGlmcmFtZSwgfjZyZW0gb2YgdG9wIHBhZGRpbmcsIGEgY2VudHJl'
    || 'ZCBtYXgtd2lkdGggYmxvY2sgY29udGFpbmVyLCBhbmQgdGhlCiMgdG9vbGJhci9mb290ZXIuIFRoZSByZXN1bHQgcmVhZHMgYXMgYSBzbWFsbCB3aW5kb3cg'
    || 'ZmxvYXRpbmcgaW4gYSBibGFjayBib3JkZXIsCiMgd2hpY2ggaXMgZXhhY3RseSBob3cgaXQgc2hpcHBlZCBhbmQgd2hhdCB0aGUgZmlyc3Qgc2NyZWVuc2hv'
    || 'dCBzaG93ZWQuCiMKIyBJbmxpbmUgQ1NTIHRocm91Z2ggc3QubWFya2Rvd24gaXMgdGhlIHN1cHBvcnRlZCByb3V0ZSAtLSBTbm93Zmxha2UncyBDdXN0b20g'
    || 'VUkKIyByZWxlYXNlIG5vdGVzIG5hbWUgIkN1c3RvbSBIVE1MIGFuZCBDU1MgdXNpbmcgdW5zYWZlX2FsbG93X2h0bWw9VHJ1ZSBpbgojIHN0Lm1hcmtkb3du'
    || 'IiBleHBsaWNpdGx5LiBJdCBpcyBOT1QgYSBDU1AgcHJvYmxlbTogdGhlIENTUCBibG9ja3MgZXh0ZXJuYWwKIyByZXNvdXJjZXMgYW5kIGV2YWwoKSwgbm90'
    || 'IGFuIGlubGluZSA8c3R5bGU+LgojCiMgVGhpcyBtdXN0IGNvbWUgQUZURVIgc2V0X3BhZ2VfY29uZmlnICh3aGljaCBoYXMgdG8gYmUgdGhlIGZpcnN0IFN0'
    || 'cmVhbWxpdCBjYWxsKQojIGFuZCBCRUZPUkUgdGhlIGNvbXBvbmVudCwgb3IgdGhlIHBhZ2UgcGFpbnRzIGRhcmsgYW5kIHRoZW4gcmVmbG93cy4Kc3QubWFy'
    || 'a2Rvd24oCiAgICAiIiIKICAgIDxzdHlsZT4KICAgICAgLyogS2lsbCB0aGUgZGFyayBjYW52YXMgYW5kIHRoZSBwYWRkaW5nIHRoYXQgY3JlYXRlcyB0aGUg'
    || 'IndpbmRvd2VkIiBsb29rLiAqLwogICAgICAuc3RBcHAsIFtkYXRhLXRlc3RpZD0ic3RBcHBWaWV3Q29udGFpbmVyIl0sIFtkYXRhLXRlc3RpZD0ic3RNYWlu'
    || 'Il0gewogICAgICAgICAgYmFja2dyb3VuZDogI2Y4ZjhmOCAhaW1wb3J0YW50OwogICAgICB9CiAgICAgIFtkYXRhLXRlc3RpZD0ic3RIZWFkZXIiXSwgW2Rh'
    || 'dGEtdGVzdGlkPSJzdFRvb2xiYXIiXSwgZm9vdGVyIHsgZGlzcGxheTogbm9uZSAhaW1wb3J0YW50OyB9CiAgICAgIC8qIEEgcGFnZSBtYXJnaW4gcmF0aGVy'
    || 'IHRoYW4gemVybzogdGhlIGNvbXBvbmVudCBrZWVwcyBpdHMgb3duIGludGVybmFsCiAgICAgICAgIHBhZGRpbmcsIGFuZCB0aGlzIGxpbmVzIHRoZSBwcm9t'
    || 'b3Rpb24gYmFyIHVwIHdpdGggdGhlIGNhcmRzIGluc2lkZSBpdC4gKi8KICAgICAgLmJsb2NrLWNvbnRhaW5lciwgW2RhdGEtdGVzdGlkPSJzdE1haW5CbG9j'
    || 'a0NvbnRhaW5lciJdIHsKICAgICAgICAgIHBhZGRpbmc6IDAgMCAyMnB4ICFpbXBvcnRhbnQ7IG1heC13aWR0aDogMTAwJSAhaW1wb3J0YW50OwogICAgICB9'
    || 'CiAgICAgIC8qIE5PVCBgW2RhdGEtdGVzdGlkPSJzdFZlcnRpY2FsQmxvY2siXSB7IGdhcDogMCB9YC4gVGhhdCB3YXMgaGVyZSB0byBjbG9zZQogICAgICAg'
    || 'ICB0aGUgc3RyaXAgYWJvdmUgdGhlIGNvbXBvbmVudCwgYW5kIGl0IGFsc28gY29sbGFwc2VkIHRoZSBmbGV4IGdhcCB0aGF0CiAgICAgICAgIFN0cmVhbWxp'
    || 'dCB1c2VzIHRvIHNwYWNlIGV2ZXJ5IHdpZGdldCAtLSB3aGljaCBkcmV3IGVhY2ggY2FwdGlvbiBvZiB0aGUKICAgICAgICAgcHJvbW90aW9uIGJhciBkaXJl'
    || 'Y3RseSBvbiB0b3Agb2YgdGhlIG5leHQgb25lLiBTY29wZSBpdCB0byB0aGUgYmxvY2sgdGhhdAogICAgICAgICBhY3R1YWxseSBob2xkcyB0aGUgaWZyYW1l'
    || 'LiAqLwogICAgICBbZGF0YS10ZXN0aWQ9InN0VmVydGljYWxCbG9jayJdOmhhcyg+IFtkYXRhLXRlc3RpZD0ic3RJRnJhbWUiXSkgeyBnYXA6IDAgIWltcG9y'
    || 'dGFudDsgfQogICAgICAvKiBUaGUgY29tcG9uZW50IGlmcmFtZSBzaG91bGQgYmUgdGhlIHdob2xlIHBhZ2UsIG5vdCBhIGNlbnRyZWQgY2FyZC4gKi8KICAg'
    || 'ICAgW2RhdGEtdGVzdGlkPSJzdElGcmFtZSJdLCBpZnJhbWUgeyB3aWR0aDogMTAwJSAhaW1wb3J0YW50OyBib3JkZXI6IDAgIWltcG9ydGFudDsgfQogICAg'
    || 'ICBpZnJhbWVbc3JjZG9jKj0iZGF0YS1vbmVzaG90LWRhc2hib2FyZCJdIHsKICAgICAgICAgIGhlaWdodDogY2FsYygxMDBkdmggLSAxMDBweCkgIWltcG9y'
    || 'dGFudDsKICAgICAgICAgIG1pbi1oZWlnaHQ6IDQ4MHB4OwogICAgICB9CiAgICAgIFtkYXRhLXRlc3RpZD0ic3RNYWluIl0geyBvdmVyZmxvdzogYXV0bzsg'
    || 'fQoKICAgICAgLyog4pSA4pSAIHByb21vdGlvbiBiYXIg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA'
    || '4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA'
    || '4pSA4pSA4pSACiAgICAgICAgIE5hdGl2ZSBTdHJlYW1saXQgd2lkZ2V0cywgZHJhZ2dlZCBhcyBjbG9zZSB0byB0aGUgUmVhY3QgZGVzaWduIHN5c3RlbSBh'
    || 'cwogICAgICAgICBDU1MgYWxsb3dzLiBUaGV5IGNhbm5vdCBsaXZlIGluc2lkZSB0aGUgY29tcG9uZW50IChzZWUgcHJvbW90aW9uX2JhciksCiAgICAgICAg'
    || 'IHNvIHRoZSBzZWFtIGlzIHJlYWw7IHRoaXMgbmFycm93cyBpdC4gRm9udCBhbmQgY29sb3VyIG9ubHkgLS0gbWFyZ2lucyBhbmQKICAgICAgICAgbGluZS1o'
    || 'ZWlnaHQgYXJlIFN0cmVhbWxpdCdzIGJ1c2luZXNzLCBhbmQgb3ZlcnJpZGluZyB0aGVtIGlzIHdoYXQgYnJva2UKICAgICAgICAgdGhlIGxheW91dCB0aGUg'
    || 'Zmlyc3QgdGltZS4gKi8KICAgICAgW2RhdGEtdGVzdGlkPSJzdENhcHRpb25Db250YWluZXIiXSBwIHsKICAgICAgICAgIGZvbnQtc2l6ZTogMTJweCAhaW1w'
    || 'b3J0YW50OyBjb2xvcjogIzZiNmI2YiAhaW1wb3J0YW50OwogICAgICB9CiAgICAgIC5zdEJ1dHRvbiBidXR0b24sCiAgICAgIFtkYXRhLXRlc3RpZD0ic3RC'
    || 'YXNlQnV0dG9uLXNlY29uZGFyeSJdLAogICAgICBbZGF0YS10ZXN0aWQ9InN0QmFzZUJ1dHRvbi1wcmltYXJ5Il0gewogICAgICAgICAgYm9yZGVyLXJhZGl1'
    || 'czogMTBweCAhaW1wb3J0YW50OyBib3JkZXI6IDFweCBzb2xpZCAjZTVlNWU3ICFpbXBvcnRhbnQ7CiAgICAgICAgICBiYWNrZ3JvdW5kOiAjZmZmZmZmICFp'
    || 'bXBvcnRhbnQ7IGNvbG9yOiAjMGEyMzQyICFpbXBvcnRhbnQ7CiAgICAgICAgICBmb250LXdlaWdodDogNjUwICFpbXBvcnRhbnQ7IGZvbnQtc2l6ZTogMTIu'
    || 'NXB4ICFpbXBvcnRhbnQ7CiAgICAgICAgICBwYWRkaW5nOiA4cHggMTRweCAhaW1wb3J0YW50OwogICAgICAgICAgYm94LXNoYWRvdzogMCAxcHggM3B4IHJn'
    || 'YmEoMCwwLDAsLjA2KSwgMCAycHggMTJweCByZ2JhKDAsMCwwLC4wNCkgIWltcG9ydGFudDsKICAgICAgICAgIHRyYW5zaXRpb246IGJveC1zaGFkb3cgMjAw'
    || 'bXMgY3ViaWMtYmV6aWVyKC4yMiwxLC4zNiwxKSAhaW1wb3J0YW50OwogICAgICB9CiAgICAgIC5zdEJ1dHRvbiBidXR0b246aG92ZXI6bm90KDpkaXNhYmxl'
    || 'ZCksCiAgICAgIFtkYXRhLXRlc3RpZD0ic3RCYXNlQnV0dG9uLXNlY29uZGFyeSJdOmhvdmVyOm5vdCg6ZGlzYWJsZWQpIHsKICAgICAgICAgIGJvcmRlci1j'
    || 'b2xvcjogIzAwODRkNCAhaW1wb3J0YW50OyBjb2xvcjogIzAwODRkNCAhaW1wb3J0YW50OwogICAgICAgICAgYm94LXNoYWRvdzogMCAycHggOHB4IHJnYmEo'
    || 'MCwwLDAsLjA4KSwgMCA4cHggMjRweCByZ2JhKDAsMCwwLC4wNikgIWltcG9ydGFudDsKICAgICAgfQogICAgICAuc3RCdXR0b24gYnV0dG9uOmRpc2FibGVk'
    || 'IHsgb3BhY2l0eTogLjQ1ICFpbXBvcnRhbnQ7IH0KICAgICAgW2RhdGEtdGVzdGlkPSJzdEJhc2VCdXR0b24tcHJpbWFyeSJdLCAuc3RCdXR0b24gYnV0dG9u'
    || 'W2tpbmQ9InByaW1hcnkiXSB7CiAgICAgICAgICBiYWNrZ3JvdW5kOiAjMDA4NGQ0ICFpbXBvcnRhbnQ7IGJvcmRlci1jb2xvcjogIzAwODRkNCAhaW1wb3J0'
    || 'YW50OwogICAgICAgICAgY29sb3I6ICNmZmZmZmYgIWltcG9ydGFudDsKICAgICAgfQogICAgICBociB7IGJvcmRlci1jb2xvcjogI2U1ZTVlNyAhaW1wb3J0'
    || 'YW50OyB9CiAgICA8L3N0eWxlPgogICAgIiIiLAogICAgdW5zYWZlX2FsbG93X2h0bWw9VHJ1ZSwKKQoKUk9XX0NBUCA9IDUwMDAgICAjIGEgcGFuZWwgdGhh'
    || 'dCB3b3VsZCByZXR1cm4gbW9yZSBpcyB0cnVuY2F0ZWQsIGFuZCBzYXlzIHNvCgojIOKUgOKUgCBUaGUgc29sdXRpb24ncyBwYW5lbHMg4pSA4pSA4pSA4pSA'
    || '4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA'
    || '4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACiMgUEFORUxTIG1hcHMgYSBwYW5lbCBuYW1lIHRvIHRoZSBT'
    || 'UUwgdGhhdCBmaWxscyBpdC4ge3RndH0gaXMgdGhpcyBhcHAncyBvd24KIyBzY2hlbWEsIHJlc29sdmVkIGF0IHJ1bnRpbWUgcmF0aGVyIHRoYW4gYmFrZWQg'
    || 'aW4gYXQgYnVuZGxlIHRpbWUsIGJlY2F1c2UgdGhlCiMgYnVuZGxlIGlzIGJ1aWx0IGJlZm9yZSBhbnlvbmUgaGFzIGNob3NlbiBhIHRhcmdldCBzY2hlbWEu'
    || 'CiMKIyBFdmVyeSBzb2x1dGlvbiBkZWNsYXJlcyBhIHBhbmVsIG5hbWVkIGBjb250ZXh0YCBzZWxlY3RpbmcgVl9CVUlMRF9DT05URVhUOiB0aGUKIyBzaGVs'
    || 'bCByZWFkcyBNT0RFIGZyb20gaXQgdG8gZGVjaWRlIHdoZXRoZXIgdG8gc2hvdyB0aGUgU0FNUExFIGJhbm5lciwgYW5kIGEKIyBtaXNzaW5nIE1PREUgbWVh'
    || 'bnMgc2VlZGVkIG51bWJlcnMgY291bGQgcmVuZGVyIHVubGFiZWxsZWQuCiMKIyBHYXVudGxldCBzdGVwIDEwIHBhcnNlcyB0aGlzIGRpY3Qgc3RhdGljYWxs'
    || 'eSBhbmQgcnVucyBlYWNoIHF1ZXJ5IGFnYWluc3QgdGhlCiMgcmVhbCBidWlsdCBzY2hlbWEsIHdoaWNoIGlzIHRoZSBvbmx5IHRlc3QgdGhlc2UgcXVlcmll'
    || 'cyBnZXQgLS0gdGhleSBsaXZlIGluIGEKIyBweXRob24gZmlsZSB0aGF0IG5ldmVyIGV4ZWN1dGVzIG91dHNpZGUgU25vd2ZsYWtlLgojCiMgQSBwYW5lbCBt'
    || 'YXkgY2FycnkgOm5hbWUgUExBQ0VIT0xERVJTIG5hbWluZyBhIGNvbnRyb2wgZGVjbGFyZWQgaW4gQ09OVFJPTFMKIyBiZWxvdy4gVGhleSBhcmUgcmVwbGFj'
    || 'ZWQgd2l0aCBwb3NpdGlvbmFsIGJpbmRzIGF0IHF1ZXJ5IHRpbWUsIG5ldmVyIGJ5IHN0cmluZwojIGludGVycG9sYXRpb24gLS0gc2VlIHJlc29sdmVfcGFu'
    || 'ZWxfc3FsKCkuIE9ubHkgREVDTEFSRUQgbmFtZXMgYXJlIGVsaWdpYmxlLCBzbyBhCiMgYDo6VkFSQ0hBUmAgY2FzdCBvciBhbnkgb3RoZXIgc3RyYXkgY29s'
    || 'b24gY2FuIG5ldmVyIGJlIG1pc3Rha2VuIGZvciBvbmUuCiMKIyBDT05UUk9MUyBkZWZhdWx0cyB0byBlbXB0eSBIRVJFLCBhYm92ZSB0aGUgc3BsaWNlLCBz'
    || 'byB0aGF0IGEgc29sdXRpb24ncyBvd24KIyBgQ09OVFJPTFMgPSBbLi4uXWAgaW4gcGFuZWxzLnB5IChzcGxpY2VkIGluIGJlbG93KSBvdmVycmlkZXMgaXQs'
    || 'IGFuZCBhIHNvbHV0aW9uCiMgdGhhdCBkZWNsYXJlcyBub25lIGtlZXBzIGV4YWN0bHkgdG9kYXkncyBiZWhhdmlvdXI6IG5vIHdpZGdldHMsIG5vIGJpbmRz'
    || 'LCBhbmQgYQojIHBhbmVsIHF1ZXJ5IGJ5dGUtaWRlbnRpY2FsIHRvIHdoYXQgaXQgd2FzIGJlZm9yZSB0aGlzIG1lY2hhbmlzbSBleGlzdGVkLgojCiMgRWFj'
    || 'aCBjb250cm9sIGlzIGEgbGl0ZXJhbCBkaWN0LCBiZWNhdXNlIGJ1bmRsZS5weSByZWFkcyB0aGVzZSBzdGF0aWNhbGx5IGZvciB0aGUKIyBzYW1lIHJlYXNv'
    || 'biBpdCByZWFkcyBQQU5FTFMgc3RhdGljYWxseSAtLSBzdGVwIDEwIG5lZWRzIHRoZSBERUZBVUxUUyB0byBiZSBhYmxlCiMgdG8gZXhlY3V0ZSBhIHBhcmFt'
    || 'ZXRlcmlzZWQgcGFuZWwgYXQgYWxsOgojICAgeyJrZXkiOiAibWV0cm8iLCAgICAgICAgIyB0aGUgOm5hbWUgdXNlZCBpbiBwYW5lbCBTUUwsIGFuZCB0aGUg'
    || 'c2Vzc2lvbl9zdGF0ZSBrZXkKIyAgICAibGFiZWwiOiAiTWV0cm8iLCAgICAgICMgd2hhdCB0aGUgd2lkZ2V0IGlzIGNhbGxlZCBvbiBzY3JlZW4KIyAgICAi'
    || 'a2luZCI6ICJzZWxlY3QiLCAgICAgICMgc2VsZWN0IHwgc2xpZGVyIHwgbnVtYmVyIHwgdGV4dAojICAgICJkZWZhdWx0IjogTm9uZSwgICAgICAgIyB2YWx1'
    || 'ZSB1c2VkIGJlZm9yZSB0aGUgdXNlciB0b3VjaGVzIGFueXRoaW5nLCBhbmQgdGhlCiMgICAgICAgICAgICAgICAgICAgICAgICAgICAjIHZhbHVlIHN0ZXAg'
    || 'MTAgYmluZHMgd2hlbiBpdCBydW5zIHRoZSBwYW5lbAojICAgICJvcHRpb25zX3NxbCI6ICJTRUxFQ1QgRElTVElOQ1QgTUVUUk8gRlJPTSB7dGd0fS5WX1gg'
    || 'T1JERVIgQlkgMSIsICAjIHNlbGVjdCBvbmx5CiMgICAgIm9wdGlvbnMiOiBbIkEiLCAiQiJdLCAjIHNlbGVjdCBvbmx5LCB3aGVuIHRoZSBsaXN0IGlzIGZp'
    || 'eGVkIHJhdGhlciB0aGFuIHF1ZXJpZWQKIyAgICAibWluIjogMCwgIm1heCI6IDEwMCwgInN0ZXAiOiAxLCAgICMgc2xpZGVyL251bWJlciBvbmx5CiMgICAg'
    || 'ImhlbHAiOiAiLi4uIn0gICAgICAgICAjIG9wdGlvbmFsIG9uZS1saW5lIGV4cGxhbmF0aW9uIHVuZGVyIHRoZSB3aWRnZXQKQ09OVFJPTFMgPSBbXQpQQU5F'
    || 'TFMgPSB7CiAgICAiY29udGV4dCI6ICJTRUxFQ1QgKiBGUk9NIHt0Z3R9LlZfQlVJTERfQ09OVEVYVCIsCgogICAgInNlbGxfdGhyb3VnaCI6ICgKICAgICAg'
    || 'ICAiU0VMRUNUIFNUT1JFX0lELCBTS1VfSUQsIFNBTEVfV0VFSywgVU5JVFNfU09MRCwgQVZHX09OX0hBTkQsICIKICAgICAgICAiU0VMTF9USFJPVUdIX1JB'
    || 'VEUgRlJPTSB7dGd0fS5WX1NFTExfVEhST1VHSCBPUkRFUiBCWSBTRUxMX1RIUk9VR0hfUkFURSBERVNDIExJTUlUIDIwMCIKICAgICksCgogICAgIndlZWtz'
    || 'X29mX3N1cHBseSI6ICgKICAgICAgICAiU0VMRUNUICogRlJPTSB7dGd0fS5WX1dFRUtTX09GX1NVUFBMWSBPUkRFUiBCWSAxIExJTUlUIDIwMCIKICAgICks'
    || 'CgogICAgImNvbnZlcnNpb24iOiAoCiAgICAgICAgIlNFTEVDVCAqIEZST00ge3RndH0uVl9DT05WRVJTSU9OX1JBVEUgT1JERVIgQlkgMSBMSU1JVCAyMDAi'
    || 'CiAgICApLAoKICAgICJzdGFmZmluZ19lZmZpY2llbmN5IjogKAogICAgICAgICJTRUxFQ1QgKiBGUk9NIHt0Z3R9LlZfU1RBRkZJTkdfRUZGSUNJRU5DWSBP'
    || 'UkRFUiBCWSAxIExJTUlUIDIwMCIKICAgICksCgogICAgImRvbGxhcnNfcGVyX2hvdXIiOiAoCiAgICAgICAgIlNFTEVDVCAqIEZST00ge3RndH0uVl9ET0xM'
    || 'QVJTX1BFUl9IT1VSIE9SREVSIEJZIDEgTElNSVQgMjAwIgogICAgKSwKCiAgICAibWFya2Rvd25fZXhwb3N1cmUiOiAoCiAgICAgICAgIlNFTEVDVCAqIEZS'
    || 'T00ge3RndH0uVl9NQVJLRE9XTl9FWFBPU1VSRSBPUkRFUiBCWSAxIExJTUlUIDIwMCIKICAgICksCgogICAgInBlZXJfY29tcGFyaXNvbiI6ICgKICAgICAg'
    || 'ICAiU0VMRUNUICogRlJPTSB7dGd0fS5WX1BFRVJfQ09NUEFSSVNPTiBPUkRFUiBCWSAxIExJTUlUIDIwMCIKICAgICksCgogICAgInN1bW1hcnkiOiAoCiAg'
    || 'ICAgICAgIlNFTEVDVCAqIEZST00ge3RndH0uVl9NRVJDSEFOVF9TVU1NQVJZIE9SREVSIEJZIDEgTElNSVQgMjAwIgogICAgKSwKfQoKIyDilIDilIAgU2hh'
    || 'cmVkIGFjdGlvbiBwYW5lbHMg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA'
    || '4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACiMgRXZl'
    || 'cnkgYnVpbGQgd2l0aCB0aGUgYWN0aW9uIGZyYW1ld29yayBjcmVhdGVzIFZfQUNUSU9OUyBhbmQgQUNUSU9OX0xPRzsgYnVpbGRzCiMgd2l0aG91dCBpdCBz'
    || 'aW1wbHkgcHJvZHVjZSBhICJkb2VzIG5vdCBleGlzdCIgZXJyb3IsIHdoaWNoIHRoZSBSZWFjdCBzaGVsbAojIHJlbmRlcnMgYXMgdGhlIHN0YW5kYXJkIG5v'
    || 'dC1idWlsdCBzdGF0ZS4gQWRkZWQgaGVyZSByYXRoZXIgdGhhbiBpbiBldmVyeQojIHBhbmVscy5weSBzbyBhIG5ldyBzb2x1dGlvbiBnZXRzIHRoZW0gZm9y'
    || 'IGZyZWUuClBBTkVMU1siYWN0aW9ucyJdID0gKAogICAgIlNFTEVDVCBDT0RFLCBMQUJFTCwgVElFUiwgRUZGRUNULCBFU1RfQ1JFRElUUywgU1RBVEVNRU5U'
    || 'UywgIgogICAgIlVORE9fU1RBVEVNRU5UUywgVElNRVNfUlVOLCBUSU1FU19VTkRPTkUgRlJPTSB7dGd0fS5WX0FDVElPTlMiCikKUEFORUxTWyJhY3Rpb25f'
    || 'bG9nIl0gPSAoCiAgICAiU0VMRUNUIENPREUsIFNUQVRVUywgU1RBVEVNRU5UU19SVU4sIFNUQVJURURfQVQsIEZJTklTSEVEX0FULCBFUlJPUiAiCiAgICAi'
    || 'RlJPTSB7dGd0fS5BQ1RJT05fTE9HIE9SREVSIEJZIFNUQVJURURfQVQgREVTQyBMSU1JVCAxMCIKKQoKIyDilIDilIAgU2hhcmVkIFBPQyBzdWNjZXNzIHBh'
    || 'bmVscyDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi'
    || 'lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKIyBCb3RoIHZpZXdzIGFyZSBjcmVhdGVkIGJ5IGV2ZXJ5'
    || 'IGJ1aWxkLCBpbmNsdWRpbmcgYnVpbGRzIHdob3NlIHNvbHV0aW9uCiMgZGVjbGFyZWQgbm8gY3JpdGVyaWEgLS0gdGhvc2UgZ2V0IHRoZSBzaW5nbGUgIk5P'
    || 'IFNVQ0NFU1MgQ1JJVEVSSUEgREVDTEFSRUQiCiMgcm93IHJhdGhlciB0aGFuIGFuIGVtcHR5IHJlc3VsdCwgc28gdGhlIHRhYiBuZXZlciByZW5kZXJzIGJs'
    || 'YW5rIGFuZCBibGFuayBpcwojIG5ldmVyIG1pc3Rha2VuIGZvciB6ZXJvLgojCiMgUmVhZGluZyBWX1BPQ19TQ09SRUNBUkQgcmUtZXhlY3V0ZXMgdGhlIHRh'
    || 'cmdldCBhbmQgYWN0dWFsIHNjYWxhcnMgaW5saW5lZCBpbnRvCiMgaXQsIHNvIHRoZXNlIHR3byBxdWVyaWVzIGFyZSBob3cgdGhlIG51bWJlcnMgc3RheSBs'
    || 'aXZlLiBUaGF0IGFsc28gbWVhbnMgdGhleQojIGFyZSB0aGUgbW9zdCBleHBlbnNpdmUgcGFuZWxzIGhlcmUsIGFuZCB0aGUgb25seSBvbmVzIHdob3NlIGNv'
    || 'c3Qgc2NhbGVzIHdpdGgKIyB0aGUgY3JpdGVyaWEgYSBzb2x1dGlvbiBkZWNsYXJlcy4KUEFORUxTWyJwb2Nfc2NvcmVjYXJkIl0gPSAoCiAgICAiU0VMRUNU'
    || 'IENPREUsIExBQkVMLCBXSFlfSVRfTUFUVEVSUywgVEFSR0VULCBBQ1RVQUwsIFVOSVRTLCBDT01QQVJFLCBCQVNJUywgIgogICAgIlRBUkdFVF9ERVJJVkFU'
    || 'SU9OLCBTVEFURSwgV0hZX05PVF9FVkFMVUFURUQsIFJFU09MVkVTX1dIRU4sIEFSSVRITUVUSUMsICIKICAgICJDT01QQVJBQklMSVRZIEZST00ge3RndH0u'
    || 'Vl9QT0NfU0NPUkVDQVJEICIKICAgICMgTk9UX01FVCBmaXJzdC4gQSBzY29yZWNhcmQgc29ydGVkIGJ5IGNvZGUgYnVyaWVzIHRoZSBvbmUgcm93IHRoZSBy'
    || 'ZWFkZXIKICAgICMgbW9zdCBuZWVkcywgYW5kIFBFTkRJTkcgc29ydGluZyBhYm92ZSBhIGZhaWx1cmUgcmVhZHMgYXMgcmVhc3N1cmFuY2UuCiAgICAiT1JE'
    || 'RVIgQlkgQ0FTRSBTVEFURSBXSEVOICdOT1RfTUVUJyBUSEVOIDAgV0hFTiAnUEVORElORycgVEhFTiAxICIKICAgICJXSEVOICdNRVQnIFRIRU4gMiBFTFNF'
    || 'IDMgRU5ELCBDT0RFIgopClBBTkVMU1sicG9jX3ZlcmRpY3QiXSA9ICgKICAgICJTRUxFQ1QgTUVULCBOT1RfTUVULCBQRU5ESU5HLCBOQSwgU0NPUkVELCBI'
    || 'RUFETElORSwgVkVSRElDVCwgUkVBRF9USElTICIKICAgICJGUk9NIHt0Z3R9LlZfUE9DX1ZFUkRJQ1QiCikKCgpkZWYgdGFyZ2V0X3NjaGVtYShzZXNzaW9u'
    || 'KSAtPiBzdHI6CiAgICAiIiJUaGUgc2NoZW1hIHRoaXMgU3RyZWFtbGl0IG9iamVjdCBsaXZlcyBpbi4KCiAgICBTdHJlYW1saXQgaW4gU25vd2ZsYWtlIHJ1'
    || 'bnMgd2l0aCB0aGUgYXBwJ3Mgb3duIGRhdGFiYXNlIGFuZCBzY2hlbWEgY3VycmVudCwKICAgIHNvIHRoaXMgaXMgcmVsaWFibGUgYW5kIG5lZWRzIG5vIGJ1'
    || 'aWxkLXRpbWUgc3Vic3RpdHV0aW9uLiBRdW90ZWQgaWRlbnRpZmllcnMKICAgIGNvbWUgYmFjayB3aXRoIHF1b3RlcyBhbHJlYWR5LCB3aGljaCBpcyB3aHkg'
    || 'dGhleSBhcmUgc3RyaXBwZWQuCiAgICAiIiIKICAgIGNhY2hlZCA9IHN0LnNlc3Npb25fc3RhdGUuZ2V0KCJvbmVzaG90X3RhcmdldF9zY2hlbWEiKQogICAg'
    || 'aWYgY2FjaGVkOgogICAgICAgIHJldHVybiBjYWNoZWQKICAgIHJvdyA9IHNlc3Npb24uc3FsKAogICAgICAgICJTRUxFQ1QgQ1VSUkVOVF9EQVRBQkFTRSgp'
    || 'IEFTIEQsIENVUlJFTlRfU0NIRU1BKCkgQVMgUyIpLmNvbGxlY3QoKVswXQogICAgZGIsIHNjID0gKHJvd1siRCJdIG9yICIiKS5zdHJpcCgnIicpLCAocm93'
    || 'WyJTIl0gb3IgIiIpLnN0cmlwKCciJykKICAgIHRhcmdldCA9IGRiICsgIi4iICsgc2MKICAgIHN0LnNlc3Npb25fc3RhdGVbIm9uZXNob3RfdGFyZ2V0X3Nj'
    || 'aGVtYSJdID0gdGFyZ2V0CiAgICByZXR1cm4gdGFyZ2V0CgoKZGVmIGFwcF9uYXZpZ2F0aW9uKHNlc3Npb24sIHRhcmdldCk6CiAgICBjYWNoZV9rZXkgPSAi'
    || 'b25lc2hvdF92aWV3ZXI6IiArIHRhcmdldCArICIuIiArIEFQUF9PQkpFQ1QKICAgIGlmIGNhY2hlX2tleSBub3QgaW4gc3Quc2Vzc2lvbl9zdGF0ZToKICAg'
    || 'ICAgICB0cnk6CiAgICAgICAgICAgIGlmIG5vdCByZS5mdWxsbWF0Y2gociJbQS1aYS16MC05X10rXC5bQS1aYS16MC05X10rIiwgdGFyZ2V0KSBvciBub3Qg'
    || 'cmUuZnVsbG1hdGNoKHIiW0EtWmEtejAtOV9dKyIsIEFQUF9PQkpFQ1QpOgogICAgICAgICAgICAgICAgcmV0dXJuIHt9CiAgICAgICAgICAgIGFjY291bnQg'
    || 'PSBzZXNzaW9uLnNxbCgiU0VMRUNUIENVUlJFTlRfT1JHQU5JWkFUSU9OX05BTUUoKSBBUyBPUkcsIENVUlJFTlRfQUNDT1VOVF9OQU1FKCkgQVMgQUNDT1VO'
    || 'VCIpLmNvbGxlY3QoKVswXQogICAgICAgICAgICBhcHBzID0gc2Vzc2lvbi5zcWwoIlNIT1cgU1RSRUFNTElUUyBJTiBTQ0hFTUEgIiArIHRhcmdldCkuY29s'
    || 'bGVjdCgpCiAgICAgICAgICAgIGFwcCA9IG5leHQoKHJvdy5hc19kaWN0KCkgZm9yIHJvdyBpbiBhcHBzIGlmIHN0cihyb3cuYXNfZGljdCgpLmdldCgibmFt'
    || 'ZSIsICIiKSkudXBwZXIoKSA9PSBBUFBfT0JKRUNULnVwcGVyKCkpLCBOb25lKQogICAgICAgICAgICBwYXJ0cyA9IFtzdHIoYWNjb3VudFsiT1JHIl0pLmxv'
    || 'd2VyKCksIHN0cihhY2NvdW50WyJBQ0NPVU5UIl0pLmxvd2VyKCksIHN0cigoYXBwIG9yIHt9KS5nZXQoInVybF9pZCIsICIiKSldCiAgICAgICAgICAgIGlm'
    || 'IG5vdCBhbGwocmUuZnVsbG1hdGNoKHIiW0EtWmEtejAtOV8tXSsiLCB2YWx1ZSkgZm9yIHZhbHVlIGluIHBhcnRzKToKICAgICAgICAgICAgICAgIHJldHVy'
    || 'biB7fQogICAgICAgICAgICBzdC5zZXNzaW9uX3N0YXRlW2NhY2hlX2tleV0gPSAiaHR0cHM6Ly9hcHAuc25vd2ZsYWtlLmNvbS9zdHJlYW1saXQvIiArIHBh'
    || 'cnRzWzBdICsgIi8iICsgcGFydHNbMV0gKyAiLyMvYXBwcy8iICsgcGFydHNbMl0KICAgICAgICAgICAgc3Quc2Vzc2lvbl9zdGF0ZVtjYWNoZV9rZXkgKyAi'
    || 'OmJ1aWxkZXIiXSA9ICJodHRwczovL2FwcC5zbm93Zmxha2UuY29tLyIgKyBwYXJ0c1swXSArICIvIiArIHBhcnRzWzFdICsgIi8jL3N0cmVhbWxpdC1hcHBz'
    || 'LyIgKyB0YXJnZXQgKyAiLiIgKyBBUFBfT0JKRUNUCiAgICAgICAgZXhjZXB0IEV4Y2VwdGlvbjoKICAgICAgICAgICAgcmV0dXJuIHt9CiAgICByZXR1cm4g'
    || 'eyJ2aWV3ZXJfdXJsIjogc3Quc2Vzc2lvbl9zdGF0ZVtjYWNoZV9rZXldLCAiYnVpbGRlcl91cmwiOiBzdC5zZXNzaW9uX3N0YXRlLmdldChjYWNoZV9rZXkg'
    || 'KyAiOmJ1aWxkZXIiLCAiIil9CgoKZGVmIGludmFsaWRhdGVfcGFuZWxfY2FjaGUoKToKICAgIHN0LnNlc3Npb25fc3RhdGUucG9wKCJvbmVzaG90X3BhbmVs'
    || 'X2NhY2hlIiwgTm9uZSkKCgpkZWYgY2FjaGVkX3BhbmVsKHNlc3Npb24sIHNxbCwgYmluZHMsIHR0bD0zMCk6CiAgICBlbnRyaWVzID0gc3Quc2Vzc2lvbl9z'
    || 'dGF0ZS5zZXRkZWZhdWx0KCJvbmVzaG90X3BhbmVsX2NhY2hlIiwge30pCiAgICBrZXkgPSBqc29uLmR1bXBzKFtzcWwsIGJpbmRzXSwgc29ydF9rZXlzPVRy'
    || 'dWUsIGRlZmF1bHQ9c3RyKQogICAgbm93ID0gbW9ub3RvbmljKCkKICAgIGVudHJ5ID0gZW50cmllcy5nZXQoa2V5KQogICAgaWYgZW50cnkgYW5kIG5vdyAt'
    || 'IGVudHJ5WzBdIDwgdHRsOgogICAgICAgIHJldHVybiBjb3B5LmRlZXBjb3B5KGVudHJ5WzFdKQogICAgZnJhbWUgPSBzZXNzaW9uLnNxbChzcWwsIHBhcmFt'
    || 'cz1iaW5kcykgaWYgYmluZHMgZWxzZSBzZXNzaW9uLnNxbChzcWwpCiAgICByb3dzID0gW3Jvdy5hc19kaWN0KCkgZm9yIHJvdyBpbiBmcmFtZS5saW1pdChS'
    || 'T1dfQ0FQICsgMSkuY29sbGVjdCgpXQogICAgcGFuZWwgPSB7InJvd3MiOiBqc29uLmxvYWRzKGpzb24uZHVtcHMocm93c1s6Uk9XX0NBUF0sIGRlZmF1bHQ9'
    || 'c3RyKSl9CiAgICBpZiBsZW4ocm93cykgPiBST1dfQ0FQOgogICAgICAgIHBhbmVsWyJ0cnVuY2F0ZWQiXSA9IFJPV19DQVAKICAgIGVudHJpZXNba2V5XSA9'
    || 'IChub3csIHBhbmVsKQogICAgd2hpbGUgbGVuKGVudHJpZXMpID4gODA6CiAgICAgICAgZW50cmllcy5wb3AobmV4dChpdGVyKGVudHJpZXMpKSkKICAgIHJl'
    || 'dHVybiBjb3B5LmRlZXBjb3B5KHBhbmVsKQoKCmRlZiByZXNvbHZlX3BhbmVsX3NxbChzcWw6IHN0ciwgcGFyYW1zOiBkaWN0KToKICAgICIiIihzcWxfd2l0'
    || 'aF9wb3NpdGlvbmFsX2JpbmRzLCBiaW5kcykgZm9yIG9uZSBwYW5lbC4KCiAgICBCSU5EUywgTk9UIElOVEVSUE9MQVRJT04uIEEgY29udHJvbCdzIHZhbHVl'
    || 'IGlzIGNob3NlbiBieSB3aG9ldmVyIGlzIGxvb2tpbmcgYXQKICAgIHRoZSBwYWdlLCBzbyBwYXN0aW5nIGl0IGludG8gdGhlIFNRTCB0ZXh0IHdvdWxkIGJl'
    || 'IGFuIGluamVjdGlvbiBob2xlIGluIGEgcXVlcnkKICAgIHRoYXQgcnVucyB3aXRoIHRoZSBhcHAgb3duZXIncyBwcml2aWxlZ2VzLiBFdmVyeSB2YWx1ZSBs'
    || 'ZWF2ZXMgaGVyZSBhcyBhIGA/YC4KCiAgICBPTkxZIERFQ0xBUkVEIE5BTUVTIEFSRSBFTElHSUJMRS4gVGhlIHBhdHRlcm4gaXMgYnVpbHQgZnJvbSB0aGUg'
    || 'a2V5cyBvZiBgcGFyYW1zYAogICAgcmF0aGVyIHRoYW4gZnJvbSBhIGdlbmVyaWMgYDpcXHcrYCwgd2hpY2ggaXMgd2hhdCBtYWtlcyBgOjpWQVJDSEFSYCBz'
    || 'YWZlOiB0aGUKICAgIHNlY29uZCBjb2xvbiBvZiBhIGNhc3QgY2Fubm90IGJlZ2luIGEgZGVjbGFyZWQgbmFtZSwgYW5kIHRoZSBuZWdhdGl2ZSBsb29rYmVo'
    || 'aW5kCiAgICByZWZ1c2VzIGl0IGEgc2Vjb25kIHRpbWUuIEFueXRoaW5nIGVsc2UgY29sb24tc2hhcGVkIGluIGEgcGFuZWwgLS0gYSBzdGFnZSBwYXRoLAog'
    || 'ICAgYSBKU09OIHRyYXZlcnNhbCAtLSBpcyBsZWZ0IHVudG91Y2hlZCBiZWNhdXNlIGl0IHdhcyBuZXZlciBkZWNsYXJlZC4KCiAgICBMb25nZXN0IG5hbWUg'
    || 'Zmlyc3Qgc28gdGhhdCBkZWNsYXJpbmcgYm90aCBgbWV0cm9gIGFuZCBgbWV0cm9fY29kZWAgY2Fubm90IGhhdmUKICAgIHRoZSBzaG9ydGVyIG9uZSBlYXQg'
    || 'dGhlIGZyb250IG9mIHRoZSBsb25nZXIuCgogICAgVEhJUyBGVU5DVElPTiBJUyBEVVBMSUNBVEVEIGluIGhhcm5lc3MvYnVuZGxlLnB5LiBJdCBoYXMgdG8g'
    || 'YmU6IHRoaXMgZmlsZSBpcwogICAgc3RhbmRhbG9uZSBjb2RlIHRoYXQgcnVucyBpbnNpZGUgU25vd2ZsYWtlIGFuZCBjYW5ub3QgaW1wb3J0IHRoZSBoYXJu'
    || 'ZXNzLCB3aGlsZQogICAgZ2F1bnRsZXQgc3RlcCAxMCBhbmQgdGhlIHJlbmRlciBjaGVjayBuZWVkIHRoZSBpZGVudGljYWwgc3Vic3RpdHV0aW9uIHRvIHRl'
    || 'c3QKICAgIHdoYXQgdGhlIGFwcCB3aWxsIHJlYWxseSBydW4uIElmIHlvdSBjaGFuZ2Ugb25lLCBjaGFuZ2UgYm90aCAtLSB0aGUgcGFpciBpcwogICAgY292'
    || 'ZXJlZCBieSBhIHRlc3QgaW4gYnVuZGxlLnB5IHRoYXQgY29tcGFyZXMgdGhlbS4KICAgICIiIgogICAgaWYgbm90IHBhcmFtczoKICAgICAgICByZXR1cm4g'
    || 'c3FsLCBbXQogICAgbmFtZXMgPSBzb3J0ZWQocGFyYW1zLCBrZXk9bGVuLCByZXZlcnNlPVRydWUpCiAgICBwYXQgPSByZS5jb21waWxlKHIiKD88ITopOigi'
    || 'ICsgInwiLmpvaW4ocmUuZXNjYXBlKG4pIGZvciBuIGluIG5hbWVzKSArIHIiKVxiIikKICAgIGJpbmRzID0gW10KCiAgICBkZWYgc3ViKG0pOgogICAgICAg'
    || 'IGJpbmRzLmFwcGVuZChwYXJhbXNbbS5ncm91cCgxKV0pCiAgICAgICAgcmV0dXJuICI/IgoKICAgIHJldHVybiBwYXQuc3ViKHN1Yiwgc3FsKSwgYmluZHMK'
    || 'CgpkZWYgcnVuX3BhbmVscyhzZXNzaW9uLCB0Z3Q6IHN0ciwgcGFyYW1zOiBkaWN0ID0gTm9uZSkgLT4gZGljdDoKICAgICIiIlJ1biBldmVyeSBwYW5lbCwg'
    || 'b25lIGZhaWx1cmUgY29zdGluZyBvbmUgcGFuZWwuCgogICAgRmV0Y2hlcyBST1dfQ0FQICsgMSByb3dzIHNvIHRoYXQgaGl0dGluZyB0aGUgY2FwIGlzIERF'
    || 'VEVDVEFCTEUuIFNlbGVjdGluZwogICAgZXhhY3RseSBST1dfQ0FQIGlzIGluZGlzdGluZ3Vpc2hhYmxlIGZyb20gInRoZSBhbnN3ZXIgaGFwcGVuZWQgdG8g'
    || 'YmUgNTAwMCIsCiAgICBhbmQgYSBjYXJkIHRoYXQgY291bnRzIHJvd3MgY2xpZW50LXNpZGUgdG8gcHJvZHVjZSBhIGhlYWRsaW5lIC0tICI0MTIgdGFibGVz'
    || 'CiAgICBhcmUgZWxpZ2libGUiIC0tIHdvdWxkIHRoZW4gcmVwb3J0IHRoZSBjYXAgYXMgaWYgaXQgd2VyZSB0aGUgdG90YWwuIFRoZSBleHRyYQogICAgcm93'
    || 'IGlzIGRyb3BwZWQgYmVmb3JlIHRoZSBwYXlsb2FkIGlzIGJ1aWx0OyBvbmx5IHRoZSBmbGFnIHN1cnZpdmVzLgoKICAgIGBwYXJhbXNgIGNhcnJpZXMgdGhl'
    || 'IGN1cnJlbnQgdmFsdWUgb2YgZXZlcnkgZGVjbGFyZWQgY29udHJvbC4gVGhpcyBydW5zIG9uIEVWRVJZCiAgICBTdHJlYW1saXQgcmVydW4sIHdoaWNoIGlz'
    || 'IHRoZSB3aG9sZSByZWFzb24gYSBjb250cm9sIGNhbiBjaGFuZ2Ugd2hhdCB0aGUgUmVhY3QKICAgIHBhZ2Ugc2hvd3M6IHRoZSBpZnJhbWUgY2Fubm90IHJl'
    || 'LXF1ZXJ5LCBidXQgdGhlIGhvc3QgcmUtcXVlcmllcyBmb3IgaXQgYW5kIGhhbmRzCiAgICBkb3duIGEgZnJlc2ggcGF5bG9hZC4gQSBzb2x1dGlvbiB0aGF0'
    || 'IGRlY2xhcmVzIG5vIGNvbnRyb2xzIHBhc3NlcyBhbiBlbXB0eSBkaWN0CiAgICBhbmQgdGFrZXMgdGhlIG5vLWJpbmRzIHBhdGggYmVsb3csIHNvIGl0cyBx'
    || 'dWVyeSBpcyB1bmNoYW5nZWQuCiAgICAiIiIKICAgIHBhcmFtcyA9IHBhcmFtcyBvciB7fQogICAgb3V0ID0ge30KICAgIGZvciBuYW1lLCBzcWwgaW4gUEFO'
    || 'RUxTLml0ZW1zKCk6CiAgICAgICAgdHJ5OgogICAgICAgICAgICBxLCBiaW5kcyA9IHJlc29sdmVfcGFuZWxfc3FsKHNxbC5yZXBsYWNlKCJ7dGd0fSIsIHRn'
    || 'dCksIHBhcmFtcykKICAgICAgICAgICAgIyBUaGUgbm8tYmluZHMgY2FsbCBpcyBrZXB0IGRpc3RpbmN0IHJhdGhlciB0aGFuIGFsd2F5cyBwYXNzaW5nCiAg'
    || 'ICAgICAgICAgICMgcGFyYW1zPVtdOiBldmVyeSBleGlzdGluZyBwYW5lbCBnb2VzIGRvd24gdGhpcyBwYXRoIHVudG91Y2hlZCwgc28gdGhpcwogICAgICAg'
    || 'ICAgICAjIG1lY2hhbmlzbSBjYW5ub3QgcmVncmVzcyBhIHNvbHV0aW9uIHRoYXQgbmV2ZXIgb3B0ZWQgaW50byBpdC4KICAgICAgICAgICAgb3V0W25hbWVd'
    || 'ID0gY2FjaGVkX3BhbmVsKHNlc3Npb24sIHEsIGJpbmRzKQogICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZXhjOgogICAgICAgICAgICBvdXRbbmFtZV0g'
    || 'PSB7ImVycm9yIjogdHlwZShleGMpLl9fbmFtZV9fICsgIjogIiArIHN0cihleGMpWzo0MDBdfQogICAgcmV0dXJuIG91dAoKCmRlZiBidWlsZF9odG1sKHBh'
    || 'eWxvYWQ6IGRpY3QpIC0+IHN0cjoKICAgIGpzID0gYmFzZTY0LmI2NGRlY29kZShBUFBfSlNfQjY0KS5kZWNvZGUoInV0Zi04IikKICAgIGNzcyA9IGJhc2U2'
    || 'NC5iNjRkZWNvZGUoQVBQX0NTU19CNjQpLmRlY29kZSgidXRmLTgiKQogICAgZGF0YSA9IGpzb24uZHVtcHMocGF5bG9hZCkKICAgICMgVGhlIG9ubHkgZXNj'
    || 'YXBlIHRoYXQgbWF0dGVycyB3aGVuIGlubGluaW5nIGludG8gPHNjcmlwdD46IHRoZSBzZXF1ZW5jZQogICAgIyA8L3NjcmlwdCB3b3VsZCBlbmQgdGhlIHRh'
    || 'ZyBlYXJseS4gSXQgY2FuIGFwcGVhciBpbiBKUyBvbmx5IGluc2lkZSBhIHN0cmluZwogICAgIyBvciBhIGNvbW1lbnQsIHNvIG5ldXRyYWxpc2luZyBpdCBj'
    || 'YW5ub3QgY2hhbmdlIGJlaGF2aW91ci4KICAgIGpzID0ganMucmVwbGFjZSgiPC9zY3JpcHQiLCAiPFxcL3NjcmlwdCIpCiAgICBkYXRhID0gZGF0YS5yZXBs'
    || 'YWNlKCI8LyIsICI8XFwvIikKICAgIHJldHVybiAoCiAgICAgICAgIjwhZG9jdHlwZSBodG1sPjxodG1sPjxoZWFkPjxtZXRhIGNoYXJzZXQ9J3V0Zi04Jz48'
    || 'c3R5bGU+IiArIGNzcwogICAgICAgICsgIjwvc3R5bGU+PC9oZWFkPjxib2R5IGRhdGEtb25lc2hvdC1kYXNoYm9hcmQ+PGRpdiBpZD0ncm9vdCc+PC9kaXY+'
    || 'IgogICAgICAgICsgIjxzY3JpcHQ+d2luZG93WyIgKyBqc29uLmR1bXBzKEdMT0JBTF9OQU1FKSArICJdID0gIiArIGRhdGEgKyAiOzwvc2NyaXB0PiIKICAg'
    || 'ICAgICArICI8c2NyaXB0PiIgKyBqcyArICI8L3NjcmlwdD48L2JvZHk+PC9odG1sPiIKICAgICkKCgpUSUVSX09SREVSID0gWyJTQU1QTEUiLCAiTElNSVRF'
    || 'RCIsICJQUk9EVUNUSU9OIl0KVElFUl9CTFVSQiA9IHsKICAgICJTQU1QTEUiOiAgICAgIlNlZWRlZCBkYXRhLiBTYWZlIHRvIHJ1biByZXBlYXRlZGx5OyBw'
    || 'cm92ZXMgdGhlIHNoYXBlIHdpdGhvdXQgIgogICAgICAgICAgICAgICAgICAidG91Y2hpbmcgYW55dGhpbmcgcmVhbC4iLAogICAgIkxJTUlURUQiOiAgICAi'
    || 'WW91ciBkYXRhLCBkZWxpYmVyYXRlbHkgYm91bmRlZCDigJQgYSBzdWJzZXQsIGEgY2FwLCBvciBhIHNpbmdsZSAiCiAgICAgICAgICAgICAgICAgICJvYmpl'
    || 'Y3QuIE1lYW50IHRvIGJlIHJldmVyc2libGUuIiwKICAgICJQUk9EVUNUSU9OIjogIllvdXIgZGF0YSwgYXQgZnVsbCBzY29wZS4gUmVhZCB0aGUgdW5kbyBs'
    || 'aW5lIGJlZm9yZSB5b3UgcnVuIGl0LiIsCn0KCgpkZWYgZm10X2NyZWRpdHModikgLT4gc3RyOgogICAgIiIiMC4wMiwgbm90IDAuMDIwMDAwLgoKICAgIEVT'
    || 'VF9DUkVESVRTIGlzIE5VTUJFUigzOCw2KSBzbyB0aGF0IGZyYWN0aW9uYWwgY3JlZGl0cyBzdXJ2aXZlIHRoZSByb3VuZCB0cmlwLAogICAgYW5kIHN0cigp'
    || 'IG9uIGEgRGVjaW1hbCBrZWVwcyBldmVyeSB0cmFpbGluZyB6ZXJvLiBTaXggZGVjaW1hbCBwbGFjZXMgaW4gYQogICAgYnV0dG9uIGNhcHRpb24gcmVhZHMg'
    || 'YXMgYSBtYWNoaW5lIHRhbGtpbmcgdG8gaXRzZWxmLgogICAgIiIiCiAgICBpZiB2IGlzIE5vbmU6CiAgICAgICAgcmV0dXJuICJcdTIwMTQiCiAgICB0cnk6'
    || 'CiAgICAgICAgcyA9IGYie2Zsb2F0KHYpOi4zZn0iLnJzdHJpcCgiMCIpLnJzdHJpcCgiLiIpCiAgICAgICAgcmV0dXJuIHMgb3IgIjAiCiAgICBleGNlcHQg'
    || 'KFR5cGVFcnJvciwgVmFsdWVFcnJvcik6CiAgICAgICAgcmV0dXJuIHN0cih2KQoKCmRlZiBsb2FkX3J1bGVfY29uZmlnKHNlc3Npb24sIHRndDogc3RyKToK'
    || 'ICAgICIiIigodGllciwgYWxsb3dfcmVhbCwgYWxsb3dfc2FtcGxlKSwgcm93cykgZm9yIGEgc29sdXRpb24gd2l0aCBhIHR1bmFibGUgcnVsZQogICAgc2V0'
    || 'LCBlbHNlICgoIiIsIEZhbHNlLCBGYWxzZSksIFtdKS4KCiAgICBXSFkgVEhJUyBSRUFEUyBUSUVSIEFORCBOT1QgTU9ERS4gSXQgdXNlZCB0byByZXR1cm4g'
    || 'TU9ERSwgYW5kIGNvbmZpZ19iYXIgZ2F0ZWQKICAgIG9uIGBtb2RlIGluICgiUE9DIiwgIlBST0RVQ1RJT04iKWAuIE1PREUgY2FuIG9ubHkgZXZlciBob2xk'
    || 'IERJU0NPVkVSIG9yIFNBTVBMRQogICAgLS0gdGhvc2UgYXJlIHRoZSBvbmx5IHR3byB2YWx1ZXMgdGhlIHNldHRpbmdzIHRlbXBsYXRlIGRlZmluZXMsIGFu'
    || 'ZAogICAgMDBfc2V0dGluZ3NfYW5kX2Jsb2NrMCBkb2N1bWVudHMgdGhlbSBhcyBhIERBVEEgU09VUkNFIHN3aXRjaDogRElTQ09WRVIgcmVhZHMKICAgIHlv'
    || 'dXIgYWNjb3VudCwgU0FNUExFIHNlZWRzIGZpeHR1cmVzIGluc3RlYWQuICJQT0MiIHdhcyBuZXZlciBhIHJlYWNoYWJsZSB2YWx1ZSwKICAgIHNvIHRoZSBj'
    || 'b250cm9scyB3ZXJlIGRlYWQgaW4gZXZlcnkgc29sdXRpb24sIGluIGV2ZXJ5IG1vZGUsIGFuZAogICAgU0VUX1JVTEVfQ09ORklHIC8gUkVCVUlMRF9SRVNP'
    || 'TFVUSU9OIC8gUkVTRVRfUlVMRV9ERUZBVUxUUyBjb3VsZCBub3QgYmUgcmVhY2hlZAogICAgZnJvbSB0aGUgYXBwIGF0IGFsbC4KCiAgICBUaGUgZ2F0ZSB3'
    || 'YXMgd3JpdHRlbiBhZ2FpbnN0IGEgRElTQ09WRVIgLT4gUE9DIC0+IFBST0RVQ1RJT04gbWF0dXJpdHkgbGFkZGVyCiAgICB0aGF0IHdhcyBuZXZlciBpbXBs'
    || 'ZW1lbnRlZC4gVGhlIGxhZGRlciB0aGF0IGRvZXMgZXhpc3QgaXMgVElFUgogICAgKFNBTVBMRSAvIExJTUlURUQgLyBQUk9EVUNUSU9OKSwgd2hpY2ggaXMg'
    || 'd2hhdCBnb3Zlcm5zIGhvdyBtdWNoIHJlYWwgZGF0YSB0aGUKICAgIGJ1aWxkIGlzIGFsbG93ZWQgdG8gdG91Y2guIFNvIHRoZSBnYXRlIG5vdyByZWFkcyBU'
    || 'SUVSLCBhbmQgcmV1c2VzIHRoZSBTQU1FIHR3bwogICAgYXV0aG9yaXNhdGlvbnMgcHJvbW90aW9uX2JhciByZWFkcyAtLSBBTExPV19BQ1RJT05TIGZvciBM'
    || 'SU1JVEVEIGFuZCBQUk9EVUNUSU9OLAogICAgQUxMT1dfU0FNUExFX0FDVElPTlMgZm9yIFNBTVBMRS4gVGhhdCBpcyBkZWxpYmVyYXRlOiBhIHRocmVzaG9s'
    || 'ZCBjaGFuZ2UgY29zdHMgYQogICAgUkVCVUlMRF9SRVNPTFVUSU9OIGNhbGwsIHdoaWNoIGlzIGFuIGFjdGlvbiwgc28gaWYgdGhlIHR3byBzdXJmYWNlcyBk'
    || 'aXNhZ3JlZWQKICAgIGFib3V0IHdoYXQgaXMgbGl2ZSBvbmUgb2YgdGhlbSB3b3VsZCBiZSBseWluZy4KCiAgICBOTyBQRVItU09MVVRJT04gRkxBRywgQU5E'
    || 'IFRIQVQgSVMgVEhFIFdIT0xFIFNBRkVUWSBBUkdVTUVOVC4gVGhpcyBnYXRlcyBvbgogICAgd2hldGhlciBWX1JVTEVfQ09ORklHIGV4aXN0cywgZXhhY3Rs'
    || 'eSBhcyBsb2FkX2FjdGlvbnMoKSBnYXRlcyBvbiBWX0FDVElPTlMuCiAgICBUd2VudHktZml2ZSBvZiB0aGUgdHdlbnR5LXNldmVuIHNvbHV0aW9ucyBkbyBu'
    || 'b3QgZGVmaW5lIHRoYXQgdmlldywgc28gZm9yIHRoZW0KICAgIHRoaXMgcmV0dXJucyAoKCIiLCBGYWxzZSwgRmFsc2UpLCBbXSkgb24gdGhlIGZpcnN0IGV4'
    || 'Y2VwdGlvbiBhbmQgY29uZmlnX2JhcigpCiAgICBkcmF3cyBub3RoaW5nIC0tIG5vIG5ldyBzZXR0aW5nIHRvIHNldCB3cm9uZywgbm8gc2Vjb25kIGNvZGUg'
    || 'cGF0aCB0aHJvdWdoIHRoZQogICAgc2hlbGwsIGFuZCBubyB3YXkgZm9yIGEgc29sdXRpb24gdGhhdCBuZXZlciBvcHRlZCBpbiB0byBncm93IGEgY29udHJv'
    || 'bCBzdXJmYWNlCiAgICBieSBhY2NpZGVudC4KCiAgICBUaGUgZ2F0ZSBjb21lcyBiYWNrIHdpdGggdGhlIHJvd3MgYmVjYXVzZSB0aGUgY2FsbGVyIG5lZWRz'
    || 'IGJvdGggdG8gZGVjaWRlCiAgICBhbnl0aGluZywgYW5kIHJlYWRpbmcgaXQgdHdpY2UgaW52aXRlcyB0aGUgdHdvIHJlYWRzIHRvIGRpc2FncmVlIGFjcm9z'
    || 'cyBhIHJlcnVuLgogICAgIiIiCiAgICB0cnk6CiAgICAgICAgcm93cyA9IFtyLmFzX2RpY3QoKSBmb3IgciBpbiBzZXNzaW9uLnNxbCgKICAgICAgICAgICAg'
    || 'IlNFTEVDVCBSVUxFX0lELCBHUk9VUF9MQUJFTCwgUExBSU5fTEFCRUwsIFBMQUlOX0RFU0MsIElTX0FDVElWRSwgIgogICAgICAgICAgICAiSVNfTU9ESUZJ'
    || 'RUQsIFRIUkVTSE9MRCwgVEhSRVNIT0xEX0VESVRBQkxFLCBMSU5LUywgU09MRV9MSU5LUyAiCiAgICAgICAgICAgICJGUk9NICIgKyB0Z3QgKyAiLlZfUlVM'
    || 'RV9DT05GSUcgT1JERVIgQlkgR1JPVVBfU0VRLCBSVUxFX1NFUSIpLmNvbGxlY3QoKV0KICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgcmV0dXJuICgi'
    || 'IiwgRmFsc2UsIEZhbHNlKSwgW10KICAgICMgUmVhZCBkZWZlbnNpdmVseSBhbmQgZmFpbCBDTE9TRUQgb24gZWFjaCBvbmUgaW5kZXBlbmRlbnRseS4gQSBy'
    || 'dWxlIHNldCB3aG9zZQogICAgIyB0aWVyIG9yIGF1dGhvcmlzYXRpb24gY2Fubm90IGJlIGVzdGFibGlzaGVkIGlzIHRyZWF0ZWQgYXMgcmVhZC1vbmx5LCBi'
    || 'ZWNhdXNlCiAgICAjIHRoZSBmYWlsdXJlIGRpcmVjdGlvbiBtYXR0ZXJzOiBndWVzc2luZyAibGl2ZSIgaGVyZSB3b3VsZCBhcm0gY29udHJvbHMgdGhhdAog'
    || 'ICAgIyBjYWxsIGEgcmVidWlsZCBvbiBhIGJ1aWxkIHdlIGtub3cgbm90aGluZyBhYm91dC4KICAgIHRyeToKICAgICAgICB0aWVyID0gc3RyKHNlc3Npb24u'
    || 'c3FsKAogICAgICAgICAgICAiU0VMRUNUIFRJRVIgRlJPTSAiICsgdGd0ICsgIi5WX0JVSUxEX0NPTlRFWFQiKS5jb2xsZWN0KClbMF1bMF0KICAgICAgICAg'
    || 'ICAgb3IgIiIpLnVwcGVyKCkKICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgdGllciA9ICIiCiAgICB0cnk6CiAgICAgICAgYWxsb3dfcmVhbCA9IGJv'
    || 'b2woc2Vzc2lvbi5zcWwoCiAgICAgICAgICAgICJTRUxFQ1QgQUNUSU9OU19FTkFCTEVEIEZST00gIiArIHRndCArICIuVl9CVUlMRF9DT05URVhUIikuY29s'
    || 'bGVjdCgpWzBdWzBdKQogICAgZXhjZXB0IEV4Y2VwdGlvbjoKICAgICAgICBhbGxvd19yZWFsID0gRmFsc2UKICAgIHRyeToKICAgICAgICBhbGxvd19zYW1w'
    || 'bGUgPSBib29sKHNlc3Npb24uc3FsKAogICAgICAgICAgICAiU0VMRUNUIENPQUxFU0NFKFNBTVBMRV9BQ1RJT05TX0VOQUJMRUQsIEZBTFNFKSBGUk9NICIg'
    || 'KyB0Z3QKICAgICAgICAgICAgKyAiLlZfQlVJTERfQ09OVEVYVCIpLmNvbGxlY3QoKVswXVswXSkKICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgYWxs'
    || 'b3dfc2FtcGxlID0gRmFsc2UKICAgIHJldHVybiAodGllciwgYWxsb3dfcmVhbCwgYWxsb3dfc2FtcGxlKSwgcm93cwoKCmRlZiBjb25maWdfYmFyKHNlc3Np'
    || 'b24sIHRndDogc3RyKSAtPiBOb25lOgogICAgIiIiVGhlIHR1bmFibGUgcnVsZSBzZXQ6IHJlYWQtb25seSB1bnRpbCB0aGUgYnVpbGQgaXMgYXV0aG9yaXNl'
    || 'ZCB0byBhY3QuCgogICAgU3RyZWFtbGl0IHJhdGhlciB0aGFuIFJlYWN0IGZvciB0aGUgc2FtZSBwaHlzaWNhbCByZWFzb24gcHJvbW90aW9uX2JhciBpcyAt'
    || 'LQogICAgY29tcG9uZW50cy5odG1sIGlzIGEgc2FuZGJveGVkIGNyb3NzLW9yaWdpbiBpZnJhbWUgd2l0aCBubyBTbm93Zmxha2Ugc2Vzc2lvbiwKICAgIHNv'
    || 'IGEgUmVhY3Qgc2xpZGVyIGNhbm5vdCBjYWxsIGEgcHJvY2VkdXJlLiBUaGUgUmVhY3QgcGFnZSBzaG93cyB0aGUgcnVsZXMgYW5kCiAgICB3aGF0IGVhY2gg'
    || 'b25lIGNvbnRyaWJ1dGVzOyB0aGlzIGlzIHdoZXJlIHRoZXkgY2hhbmdlLgoKICAgIFdIWSBSRUFELU9OTFkgUkFUSEVSIFRIQU4gSElEREVOLiBXaGVuIHRo'
    || 'ZSBidWlsZCBpcyBub3QgYXV0aG9yaXNlZCB0byBydW4KICAgIGFjdGlvbnMsIHRoZSBydWxlIHNldCBpcyBzdGlsbCB0aGUgcGFydCB3b3J0aCBzZWVpbmcg'
    || 'LS0gdHVuYWJsZSBtYXRjaGluZyBpcyB0aGUKICAgIHByb2R1Y3QuIEhpZGluZyB0aGUgcGFuZWwgd291bGQgbWlzcmVwcmVzZW50IGl0LiBBcm1pbmcgaXQg'
    || 'd291bGQgYmUgd29yc2U6IGF0CiAgICBTQU1QTEUgdGllciBhIHJlYWRlciB3b3VsZCB0dW5lIHRocmVzaG9sZHMgYWdhaW5zdCBzZWVkZWQgcm93cyBhbmQg'
    || 'cmVhZCB0aGUKICAgIHJlc3VsdCBhcyB0aGVpciBvd24gZGF0YS4gU28gdGhlIHZhbHVlcyBhbHdheXMgcmVuZGVyLCBsYWJlbGxlZCBhcyBhIHByZXNldCB3'
    || 'aGVuCiAgICB0aGV5IGNhbm5vdCBiZSBjaGFuZ2VkLCBhbmQgdGhlIGNvbnRyb2xzIGFycml2ZSB3aXRoIHRoZSBhdXRob3Jpc2F0aW9uIHRoYXQgbWFrZXMK'
    || 'ICAgIHRoZW0gbWVhbiBzb21ldGhpbmcuCiAgICAiIiIKICAgICh0aWVyLCBhbGxvd19yZWFsLCBhbGxvd19zYW1wbGUpLCByb3dzID0gbG9hZF9ydWxlX2Nv'
    || 'bmZpZyhzZXNzaW9uLCB0Z3QpCiAgICBpZiBub3Qgcm93czoKICAgICAgICByZXR1cm4KCiAgICAjIFRoZSBTQU1FIHNwbGl0IHByb21vdGlvbl9iYXIgYXBw'
    || 'bGllcywgZm9yIHRoZSBzYW1lIHJlYXNvbjogU0FNUExFIHJ1bnMgYWdhaW5zdAogICAgIyBzZWVkZWQgcm93cyB0aGlzIHNjcmlwdCBjcmVhdGVkLCBldmVy'
    || 'eXRoaW5nIGVsc2UgdG91Y2hlcyB0aGUgY3VzdG9tZXIncyBvd24KICAgICMgb2JqZWN0cy4gQXBwbHlpbmcgYSB0aHJlc2hvbGQgY2FsbHMgUkVCVUlMRF9S'
    || 'RVNPTFVUSU9OLCBzbyBpdCBhbnN3ZXJzIHRvIHRoZQogICAgIyBhY3Rpb24gYXV0aG9yaXNhdGlvbnMgcmF0aGVyIHRoYW4gdG8gYSBzZWNvbmQsIHBhcmFs'
    || 'bGVsIG5vdGlvbiBvZiAibGl2ZSIuCiAgICBsaXZlID0gYWxsb3dfc2FtcGxlIGlmIHRpZXIgPT0gIlNBTVBMRSIgZWxzZSBhbGxvd19yZWFsCiAgICBzdC5j'
    || 'YXB0aW9uKCJNQVRDSElORyBSVUxFUyIgKyAoIiIgaWYgbGl2ZSBlbHNlICIgXHUwMGI3IFBSRVNFVCwgTk9UIFlFVCBUVU5BQkxFIikpCiAgICBpZiBub3Qg'
    || 'bGl2ZToKICAgICAgICB3aHkgPSAoCiAgICAgICAgICAgICJBY3Rpb25zIGFyZSBzd2l0Y2hlZCBvZmYgZm9yIHRoaXMgYnVpbGQsIHNvIHRoZXNlIGFyZSB0'
    || 'aGUgcHJlc2V0IHJ1bGVzICIKICAgICAgICAgICAgImFzIHNoaXBwZWQuIFRoZXkgYXJlIHNob3duIGJlY2F1c2UgdGhlIHJ1bGUgc2V0IGlzIHRoZSBwYXJ0'
    || 'IHdvcnRoICIKICAgICAgICAgICAgInNlZWluZywgYW5kIHRoZXkgYXJlIG5vdCBlZGl0YWJsZSBiZWNhdXNlIGFwcGx5aW5nIGEgY2hhbmdlIGNhbGxzIGEg'
    || 'IgogICAgICAgICAgICAicmVidWlsZC4iKQogICAgICAgIGlmIHRpZXIgPT0gIlNBTVBMRSI6CiAgICAgICAgICAgIHdoeSA9ICgKICAgICAgICAgICAgICAg'
    || 'ICJUaGlzIGJ1aWxkIHJhbiBhdCBTQU1QTEUgdGllciwgc28gdGhlc2UgYXJlIHRoZSBwcmVzZXQgcnVsZXMgIgogICAgICAgICAgICAgICAgInJ1bm5pbmcg'
    || 'b3ZlciB0aGUgYnVuZGxlZCBzYW1wbGUgcm93cy4gVGhleSBhcmUgc2hvd24gYmVjYXVzZSB0aGUgIgogICAgICAgICAgICAgICAgInJ1bGUgc2V0IGlzIHRo'
    || 'ZSBwYXJ0IHdvcnRoIHNlZWluZywgYW5kIHRoZXkgYXJlIG5vdCBlZGl0YWJsZSAiCiAgICAgICAgICAgICAgICAiYmVjYXVzZSB0dW5pbmcgYSB0aHJlc2hv'
    || 'bGQgYWdhaW5zdCBzZWVkZWQgZGF0YSB3b3VsZCBwcm9kdWNlIGEgIgogICAgICAgICAgICAgICAgIm51bWJlciB0aGF0IGRlc2NyaWJlcyB0aGUgZml4dHVy'
    || 'ZSByYXRoZXIgdGhhbiB5b3VyIGFjY291bnQuIikKICAgICAgICBlbGlmIG5vdCB0aWVyOgogICAgICAgICAgICB3aHkgPSAoCiAgICAgICAgICAgICAgICAi'
    || 'VGhpcyBidWlsZCdzIHRpZXIgY291bGQgbm90IGJlIHJlYWQsIHNvIHRoZSBjb250cm9scyBzdGF5ICIKICAgICAgICAgICAgICAgICJyZWFkLW9ubHkgcmF0'
    || 'aGVyIHRoYW4gYXJtaW5nIGEgcmVidWlsZCBhZ2FpbnN0IGEgYnVpbGQgd2UgY2Fubm90ICIKICAgICAgICAgICAgICAgICJpZGVudGlmeS4gVGhlIHZhbHVl'
    || 'cyBiZWxvdyBhcmUgdGhlIHJ1bGVzIGFzIHNoaXBwZWQuIikKICAgICAgICBzdC5jYXB0aW9uKHdoeSArICIgRW5hYmxlIGFjdGlvbnMgYW5kIHJlLXJ1biBh'
    || 'dCBMSU1JVEVEIG9yIFBST0RVQ1RJT04gdGllciAiCiAgICAgICAgICAgICAgICAgICAgICAgICAiYW5kIHRoZSBjb250cm9scyBiZWxvdyBiZWNvbWUgbGl2'
    || 'ZS4iKQoKICAgIGRpcnR5ID0gYW55KGJvb2woci5nZXQoIklTX01PRElGSUVEIikpIGZvciByIGluIHJvd3MpCiAgICBhdF9yaXNrID0gc3VtKGludChyLmdl'
    || 'dCgiU09MRV9MSU5LUyIpIG9yIDApCiAgICAgICAgICAgICAgICAgIGZvciByIGluIHJvd3MgaWYgbm90IGJvb2woci5nZXQoIklTX0FDVElWRSIpKSkKICAg'
    || 'IGlmIGRpcnR5OgogICAgICAgIHN0LmNhcHRpb24oIkNIQU5HRUQgRlJPTSBERUZBVUxUUyBcdTAwYjcgcmVidWlsZCB0byBhcHBseSIpCiAgICBpZiBhdF9y'
    || 'aXNrOgogICAgICAgIHN0LmNhcHRpb24oIkVzdGltYXRlZCBpbXBhY3Q6IGFib3V0ICIgKyBmInthdF9yaXNrOix9IgogICAgICAgICAgICAgICAgICAgKyAi'
    || 'IGNvbm5lY3Rpb25zIHdvdWxkIGJlIHJlbW92ZWQsIGJlY2F1c2UgdGhleSBhcmUgaGVsZCBieSBhICIKICAgICAgICAgICAgICAgICAgICAgInJ1bGUgdGhh'
    || 'dCBpcyBjdXJyZW50bHkgc3dpdGNoZWQgb2ZmLiIpCgogICAgZ3JvdXAgPSBOb25lCiAgICBmb3IgciBpbiByb3dzOgogICAgICAgIGcgPSBzdHIoci5nZXQo'
    || 'IkdST1VQX0xBQkVMIikgb3IgIiIpCiAgICAgICAgaWYgZyAhPSBncm91cDoKICAgICAgICAgICAgZ3JvdXAgPSBnCiAgICAgICAgICAgIHN0LmNhcHRpb24o'
    || 'Zy51cHBlcigpKQogICAgICAgIHJpZCA9IHN0cihyLmdldCgiUlVMRV9JRCIpIG9yICIiKQogICAgICAgIGxhYmVsID0gc3RyKHIuZ2V0KCJQTEFJTl9MQUJF'
    || 'TCIpIG9yIHJpZCkKICAgICAgICBhY3RpdmUgPSBib29sKHIuZ2V0KCJJU19BQ1RJVkUiKSkKICAgICAgICB0aHIgPSByLmdldCgiVEhSRVNIT0xEIikKICAg'
    || 'ICAgICBlZGl0YWJsZSA9IGJvb2woci5nZXQoIlRIUkVTSE9MRF9FRElUQUJMRSIpKSBhbmQgdGhyIGlzIG5vdCBOb25lCiAgICAgICAgbGlua3MgPSBpbnQo'
    || 'ci5nZXQoIkxJTktTIikgb3IgMCkKICAgICAgICBzb2xlID0gaW50KHIuZ2V0KCJTT0xFX0xJTktTIikgb3IgMCkKCiAgICAgICAgYzEsIGMyLCBjMyA9IHN0'
    || 'LmNvbHVtbnMoWzMsIDIsIDJdKQogICAgICAgIHdpdGggYzE6CiAgICAgICAgICAgIGlmIGxpdmU6CiAgICAgICAgICAgICAgICBuZXdfYWN0aXZlID0gc3Qu'
    || 'dG9nZ2xlKGxhYmVsLCB2YWx1ZT1hY3RpdmUsIGtleT0icmFfIiArIHJpZCkKICAgICAgICAgICAgZWxzZToKICAgICAgICAgICAgICAgIHN0LmNhcHRpb24o'
    || 'KCJPTiAgIiBpZiBhY3RpdmUgZWxzZSAiT0ZGICIpICsgbGFiZWwpCiAgICAgICAgICAgICAgICBuZXdfYWN0aXZlID0gYWN0aXZlCiAgICAgICAgICAgIGlm'
    || 'IHIuZ2V0KCJQTEFJTl9ERVNDIik6CiAgICAgICAgICAgICAgICBzdC5jYXB0aW9uKHN0cihyWyJQTEFJTl9ERVNDIl0pKQogICAgICAgIHdpdGggYzI6CiAg'
    || 'ICAgICAgICAgIG5ld190aHIgPSB0aHIKICAgICAgICAgICAgaWYgZWRpdGFibGU6CiAgICAgICAgICAgICAgICBpZiBsaXZlOgogICAgICAgICAgICAgICAg'
    || 'ICAgIG5ld190aHIgPSBzdC5zbGlkZXIoCiAgICAgICAgICAgICAgICAgICAgICAgICJIb3cgc2ltaWxhciBpcyBjbG9zZSBlbm91Z2giLCBtaW5fdmFsdWU9'
    || 'NTAsIG1heF92YWx1ZT0xMDAsCiAgICAgICAgICAgICAgICAgICAgICAgIHZhbHVlPWludChyb3VuZChmbG9hdCh0aHIpICogMTAwKSksIHN0ZXA9MSwga2V5'
    || 'PSJydF8iICsgcmlkLAogICAgICAgICAgICAgICAgICAgICAgICBoZWxwPSJoaWdoZXIgaXMgc3RyaWN0ZXIgXHUyMDE0IGZld2VyLCBzYWZlciBtYXRjaGVz'
    || 'IikKICAgICAgICAgICAgICAgICAgICBuZXdfdGhyID0gbmV3X3RociAvIDEwMC4wCiAgICAgICAgICAgICAgICBlbHNlOgogICAgICAgICAgICAgICAgICAg'
    || 'IHN0LmNhcHRpb24oInNpbWlsYXJpdHkgIiArIHN0cihpbnQocm91bmQoZmxvYXQodGhyKSAqIDEwMCkpKSArICIlIikKICAgICAgICB3aXRoIGMzOgogICAg'
    || 'ICAgICAgICBzdC5jYXB0aW9uKGYie2xpbmtzOix9IiArICIgY29ubmVjdGlvbnMgbWFkZSIpCiAgICAgICAgICAgIGlmIHNvbGU6CiAgICAgICAgICAgICAg'
    || 'ICBzdC5jYXB0aW9uKGYie3NvbGU6LH0iICsgIiB3b3VsZCBiZSBsb3N0IHdpdGhvdXQgaXQiKQoKICAgICAgICAjIE9uZSBDQUxMIHBlciBjaGFuZ2VkIHJ1'
    || 'bGUsIGFuZCBvbmx5IG9uIGEgcmVhbCBjaGFuZ2UuIFdyaXRpbmcgb24gZXZlcnkKICAgICAgICAjIHJlcnVuIHdvdWxkIGlzc3VlIGEgcHJvY2VkdXJlIGNh'
    || 'bGwgcGVyIHJ1bGUgcGVyIHJlcGFpbnQsIHdoaWNoIGlzIGJvdGggYQogICAgICAgICMgY29zdCBhbmQgYSBmYWxzZSBhdWRpdCB0cmFpbCAtLSB0aGUgY29u'
    || 'ZmlnIGhpc3Rvcnkgd291bGQgcmVjb3JkIGVkaXRzCiAgICAgICAgIyBub2JvZHkgbWFkZS4KICAgICAgICBpZiBsaXZlIGFuZCAobmV3X2FjdGl2ZSAhPSBh'
    || 'Y3RpdmUgb3IKICAgICAgICAgICAgICAgICAgICAgKGVkaXRhYmxlIGFuZCBuZXdfdGhyIGlzIG5vdCBOb25lIGFuZCB0aHIgaXMgbm90IE5vbmUKICAgICAg'
    || 'ICAgICAgICAgICAgICAgIGFuZCBhYnMoZmxvYXQobmV3X3RocikgLSBmbG9hdCh0aHIpKSA+IDFlLTkpKToKICAgICAgICAgICAgdHJ5OgogICAgICAgICAg'
    || 'ICAgICAgc2Vzc2lvbi5zcWwoIkNBTEwgIiArIHRndCArICIuU0VUX1JVTEVfQ09ORklHKD8sID8sID8pIiwKICAgICAgICAgICAgICAgICAgICAgICAgICAg'
    || 'IHBhcmFtcz1bcmlkLCBib29sKG5ld19hY3RpdmUpLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBmbG9hdChuZXdfdGhyKSBpZiBuZXdf'
    || 'dGhyIGlzIG5vdCBOb25lIGVsc2UgTm9uZV0pLmNvbGxlY3QoKQogICAgICAgICAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGV4YzoKICAgICAgICAgICAgICAg'
    || 'IHN0LmVycm9yKCJDb3VsZCBub3Qgc2F2ZSAiICsgcmlkICsgIjogIiArIHN0cihleGMpLAogICAgICAgICAgICAgICAgICAgICAgICAgaWNvbj0iOm1hdGVy'
    || 'aWFsL2Vycm9yOiIpCiAgICAgICAgICAgIGVsc2U6CiAgICAgICAgICAgICAgICBpbnZhbGlkYXRlX3BhbmVsX2NhY2hlKCkKICAgICAgICAgICAgICAgIHN0'
    || 'LnJlcnVuKCkKCiAgICBpZiBub3QgbGl2ZToKICAgICAgICBzdC5kaXZpZGVyKCkKICAgICAgICByZXR1cm4KCiAgICBiMSwgYjIgPSBzdC5jb2x1bW5zKFsx'
    || 'LCAxXSkKICAgIHdpdGggYjE6CiAgICAgICAgaWYgc3QuYnV0dG9uKCJSZXN0b3JlIGRlZmF1bHRzIiwga2V5PSJjZmdfcmVzZXQiKToKICAgICAgICAgICAg'
    || 'dHJ5OgogICAgICAgICAgICAgICAgb3V0ID0gc2Vzc2lvbi5zcWwoIkNBTEwgIiArIHRndCArICIuUkVTRVRfUlVMRV9ERUZBVUxUUygpIikuY29sbGVjdCgp'
    || 'WzBdWzBdCiAgICAgICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZXhjOgogICAgICAgICAgICAgICAgb3V0ID0gIkZBSUxFRCB0byByZXN0b3JlIGRlZmF1'
    || 'bHRzOiAiICsgc3RyKGV4YykKICAgICAgICAgICAgc3Quc2Vzc2lvbl9zdGF0ZVsiY2ZnX3Jlc3VsdCJdID0gc3RyKG91dCkKICAgICAgICAgICAgaW52YWxp'
    || 'ZGF0ZV9wYW5lbF9jYWNoZSgpCiAgICAgICAgICAgIHN0LnJlcnVuKCkKICAgIHdpdGggYjI6CiAgICAgICAgaWYgc3QuYnV0dG9uKCJSZWJ1aWxkIHJlY29y'
    || 'ZHMiLCBrZXk9ImNmZ19yZWJ1aWxkIiwgdHlwZT0icHJpbWFyeSIpOgogICAgICAgICAgICB0cnk6CiAgICAgICAgICAgICAgICBvdXQgPSBzZXNzaW9uLnNx'
    || 'bCgiQ0FMTCAiICsgdGd0ICsgIi5SRUJVSUxEX1JFU09MVVRJT04oKSIpLmNvbGxlY3QoKVswXVswXQogICAgICAgICAgICBleGNlcHQgRXhjZXB0aW9uIGFz'
    || 'IGV4YzoKICAgICAgICAgICAgICAgIG91dCA9ICJGQUlMRUQgdG8gcmVidWlsZDogIiArIHN0cihleGMpCiAgICAgICAgICAgIHN0LnNlc3Npb25fc3RhdGVb'
    || 'ImNmZ19yZXN1bHQiXSA9IHN0cihvdXQpCiAgICAgICAgICAgIGludmFsaWRhdGVfcGFuZWxfY2FjaGUoKQogICAgICAgICAgICBzdC5yZXJ1bigpCgogICAg'
    || 'bXNnID0gc3RyKHN0LnNlc3Npb25fc3RhdGUuZ2V0KCJjZmdfcmVzdWx0Iikgb3IgIiIpCiAgICBpZiBtc2c6CiAgICAgICAgaWYgbXNnLnN0YXJ0c3dpdGgo'
    || 'IkRPTkUiKSBvciBtc2cuc3RhcnRzd2l0aCgiUkVCVUlMVCIpIG9yIG1zZy5zdGFydHN3aXRoKCJSRVNUT1JFRCIpOgogICAgICAgICAgICBzdC5zdWNjZXNz'
    || 'KG1zZywgaWNvbj0iOm1hdGVyaWFsL2NoZWNrOiIpCiAgICAgICAgZWxpZiBtc2cuc3RhcnRzd2l0aCgiUkVGVVNFRCIpOgogICAgICAgICAgICBzdC53YXJu'
    || 'aW5nKG1zZywgaWNvbj0iOm1hdGVyaWFsL2Jsb2NrOiIpCiAgICAgICAgZWxzZToKICAgICAgICAgICAgc3QuZXJyb3IobXNnLCBpY29uPSI6bWF0ZXJpYWwv'
    || 'ZXJyb3I6IikKICAgIHN0LmRpdmlkZXIoKQoKCmRlZiBsb2FkX2FjdGlvbnMoc2Vzc2lvbiwgdGd0OiBzdHIpOgogICAgIiIiKChhbGxvd19yZWFsLCBhbGxv'
    || 'd19zYW1wbGUpLCByb3dzKS4gUmV0dXJucyAoKEZhbHNlLCBGYWxzZSksIFtdKSBmb3IgYW55CiAgICBidWlsZCB3aXRob3V0IHRoZSBmcmFtZXdvcmsuCgog'
    || 'ICAgV3JhcHBlZCBiZWNhdXNlIGEgc2NoZW1hIGJ1aWx0IGJ5IGFuIG9sZGVyIGFydGlmYWN0IGhhcyBubyBWX0FDVElPTlMsIGFuZCB0aGUKICAgIGFwcCBt'
    || 'dXN0IHN0aWxsIHdvcmsgYWdhaW5zdCBpdCByYXRoZXIgdGhhbiBzaG93aW5nIGEgdHJhY2ViYWNrIHdoZXJlIHRoZQogICAgcHJvbW90aW9uIGJhciB3b3Vs'
    || 'ZCBiZS4KICAgICIiIgogICAgdHJ5OgogICAgICAgIHJvd3MgPSBbci5hc19kaWN0KCkgZm9yIHIgaW4gc2Vzc2lvbi5zcWwoCiAgICAgICAgICAgICJTRUxF'
    || 'Q1QgQ09ERSwgTEFCRUwsIFRJRVIsIEVGRkVDVCwgVU5ETywgRVNUX0NSRURJVFMsIEVTVF9CQVNJUywgIgogICAgICAgICAgICAiU1RBVEVNRU5UUywgVU5E'
    || 'T19TVEFURU1FTlRTLCBUSU1FU19SVU4sIFRJTUVTX1VORE9ORSwgTEFTVF9SVU5fQVQgRlJPTSAiICsgdGd0ICsgIi5WX0FDVElPTlMiKS5jb2xsZWN0KCld'
    || 'CiAgICBleGNlcHQgRXhjZXB0aW9uOgogICAgICAgIHJldHVybiAoRmFsc2UsIEZhbHNlKSwgW10KICAgICMgVHdvIGF1dGhvcmlzYXRpb25zLCBub3Qgb25l'
    || 'LiBBTExPV19BQ1RJT05TIGdvdmVybnMgTElNSVRFRCBhbmQgUFJPRFVDVElPTiAtLQogICAgIyBhbnl0aGluZyB0aGF0IHJlYWRzIG9yIHdyaXRlcyByZWFs'
    || 'IGRhdGEuIEFMTE9XX1NBTVBMRV9BQ1RJT05TIGdvdmVybnMgU0FNUExFLAogICAgIyBhbmQgZGVmYXVsdHMgVFJVRSwgc28gYSBmcmVzaGx5IGluc3RhbGxl'
    || 'ZCBhcHAgaGFzIHNvbWV0aGluZyB0aGF0IHdvcmtzLgogICAgIwogICAgIyBUaGlzIG1pcnJvcnMgUlVOX0FDVElPTiByYXRoZXIgdGhhbiBkZWNpZGluZyBh'
    || 'bnl0aGluZzogdGhlIHByb2NlZHVyZSBlbmZvcmNlcwogICAgIyB0aGUgc2FtZSBzcGxpdCBzZXJ2ZXItc2lkZSBhbmQgcmVmdXNlcyByZWdhcmRsZXNzIG9m'
    || 'IHdoYXQgdGhpcyByZXR1cm5zLiBJZiB0aGUKICAgICMgdHdvIGV2ZXIgZGlzYWdyZWUgdGhlIHByb2Mgd2lucywgd2hpY2ggaXMgdGhlIGNvcnJlY3QgZGly'
    || 'ZWN0aW9uIC0tIGEgZGlzYWJsZWQKICAgICMgYnV0dG9uIGlzIGEgbnVpc2FuY2UsIGEgYnV0dG9uIHRoYXQgYXBwZWFycyBsaXZlIGFuZCB0aGVuIHJlZnVz'
    || 'ZXMgaXMgYSBsaWUuCiAgICAjIFNBTVBMRV9BQ1RJT05TX0VOQUJMRUQgaXMgcmVhZCBkZWZlbnNpdmVseSBiZWNhdXNlIGEgc2NoZW1hIGJ1aWx0IGJ5IGFu'
    || 'IG9sZGVyCiAgICAjIGZpbGUgd2lsbCBub3QgaGF2ZSB0aGUgY29sdW1uLgogICAgdHJ5OgogICAgICAgIGVuYWJsZWQgPSBib29sKHNlc3Npb24uc3FsKAog'
    || 'ICAgICAgICAgICAiU0VMRUNUIEFDVElPTlNfRU5BQkxFRCBGUk9NICIgKyB0Z3QgKyAiLlZfQlVJTERfQ09OVEVYVCIKICAgICAgICApLmNvbGxlY3QoKVsw'
    || 'XVswXSkKICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgZW5hYmxlZCA9IEZhbHNlCiAgICB0cnk6CiAgICAgICAgc2FtcGxlX2VuYWJsZWQgPSBib29s'
    || 'KHNlc3Npb24uc3FsKAogICAgICAgICAgICAiU0VMRUNUIENPQUxFU0NFKFNBTVBMRV9BQ1RJT05TX0VOQUJMRUQsIEZBTFNFKSBGUk9NICIgKyB0Z3QgKyAi'
    || 'LlZfQlVJTERfQ09OVEVYVCIKICAgICAgICApLmNvbGxlY3QoKVswXVswXSkKICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgc2FtcGxlX2VuYWJsZWQg'
    || 'PSBGYWxzZQogICAgcmV0dXJuIChlbmFibGVkLCBzYW1wbGVfZW5hYmxlZCksIHJvd3MKCgpkZWYgbG9hZF9wcmVmaXgoc2Vzc2lvbiwgdGd0OiBzdHIpIC0+'
    || 'IHN0cjoKICAgICIiIlRoZSBwZXItc29sdXRpb24gc2V0dGluZyBwcmVmaXgsIG9yICcnIGlmIHRoaXMgYnVpbGQgcHJlZGF0ZXMgdGhlIGNvbHVtbi4KCiAg'
    || 'ICBLZXB0IHNlcGFyYXRlIGZyb20gbG9hZF9hY3Rpb25zIHJhdGhlciB0aGFuIHdpZGVuaW5nIGl0cyByZXR1cm4sIGJlY2F1c2UKICAgIGV2ZXJ5IGNhbGxl'
    || 'ciBvZiB0aGF0IHBhaXItb2YtdHVwbGVzIHNpZ25hdHVyZSB3b3VsZCBoYXZlIHRvIGNoYW5nZSBhbmQgbm9uZQogICAgb2YgdGhlbSB3YW50IHRoZSBwcmVm'
    || 'aXguIFRoaXMgZXhpc3RzIHNvIHRoZSBhcHAgY2FuIHByaW50IHRoZSBsaW5lIHlvdSB3b3VsZAogICAgYWN0dWFsbHkgZWRpdCBpbnN0ZWFkIG9mIGEgc2V0'
    || 'dGluZyBuYW1lIHRoYXQgYXBwZWFycyBpbiBubyBmaWxlLgogICAgIiIiCiAgICB0cnk6CiAgICAgICAgcmV0dXJuIHN0cihzZXNzaW9uLnNxbCgKICAgICAg'
    || 'ICAgICAgIlNFTEVDVCBTRVRUSU5HX1BSRUZJWCBGUk9NICIgKyB0Z3QgKyAiLlZfQlVJTERfQ09OVEVYVCIKICAgICAgICApLmNvbGxlY3QoKVswXVswXSBv'
    || 'ciAiIikKICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgcmV0dXJuICIiCgoKZGVmIGxvYWRfaGVhZGxpbmUoc2Vzc2lvbiwgdGd0OiBzdHIpOgogICAg'
    || 'IiIiVGhlIG9uZS1saW5lIG1vbnRobHkgcnVuIHJhdGUsIG9yIE5vbmUuCgogICAgV3JhcHBlZCBmb3IgdGhlIHNhbWUgcmVhc29uIGxvYWRfYWN0aW9ucyBp'
    || 'czogYSBzY2hlbWEgYnVpbHQgYnkgYW4gb2xkZXIKICAgIGFydGlmYWN0IGhhcyBubyBWX1JVTl9SQVRFX0hFQURMSU5FLCBhbmQgdGhlIGFwcCBtdXN0IHN0'
    || 'aWxsIHdvcmsgYWdhaW5zdCBpdAogICAgcmF0aGVyIHRoYW4gc2hvd2luZyBhIHRyYWNlYmFjayB3aGVyZSB0aGUgc3RhbmRpbmcgY29zdCB3b3VsZCBiZS4K'
    || 'CiAgICBUaGlzIGlzIHRoZSBvbmx5IHN1cmZhY2UgdGhhdCBwcmludHMgaXQuIFRoZSB2aWV3IGhhcyBleGlzdGVkIGZvciBldmVyeQogICAgYnVpbGQgZm9y'
    || 'IGEgd2hpbGUgYW5kIHdhcyByZWFkIGJ5IG5vdGhpbmcgYnV0IHRoZSB0ZXN0IGhhcm5lc3MsIHNvIHRoZQogICAgc2VudGVuY2Ugd3JpdHRlbiBmb3IgdGhl'
    || 'IGFwcCB0byBwcmludCB3YXMgcHJpbnRlZCBieSBub2JvZHkuCiAgICAiIiIKICAgIHRyeToKICAgICAgICByb3dzID0gc2Vzc2lvbi5zcWwoCiAgICAgICAg'
    || 'ICAgICJTRUxFQ1QgSEVBRExJTkUsIEVTVF9DUkVESVRTX1BFUl9NT05USCBGUk9NICIgKyB0Z3QgKyAiLlZfUlVOX1JBVEVfSEVBRExJTkUiCiAgICAgICAg'
    || 'KS5jb2xsZWN0KCkKICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgcmV0dXJuIE5vbmUKICAgIGlmIG5vdCByb3dzOgogICAgICAgIHJldHVybiBOb25l'
    || 'CiAgICByID0gcm93c1swXS5hc19kaWN0KCkKICAgIHJldHVybiAoc3RyKHIuZ2V0KCJIRUFETElORSIpIG9yICIiKSwgci5nZXQoIkVTVF9DUkVESVRTX1BF'
    || 'Ul9NT05USCIpKQoKCmRlZiBsb2FkX2FjdGlvbl9wYXJhbXMoc2Vzc2lvbiwgdGd0OiBzdHIpOgogICAgIiIie2FjdGlvbl9jb2RlOiBbcGFyYW0gZGljdCwg'
    || 'Li4uXX0uIEVtcHR5IGRpY3QgZm9yIGFueSBidWlsZCB3aXRob3V0IHBhcmFtcy4KCiAgICBXcmFwcGVkIGZvciB0aGUgc2FtZSByZWFzb24gbG9hZF9hY3Rp'
    || 'b25zIGlzOiBhIHNjaGVtYSBidWlsdCBieSBhbiBvbGRlciBhcnRpZmFjdAogICAgaGFzIG5vIFZfQUNUSU9OX1BBUkFNUywgYW5kIHRoZSBhcHAgbXVzdCBr'
    || 'ZWVwIHdvcmtpbmcgYWdhaW5zdCBpdCByYXRoZXIgdGhhbgogICAgc2hvd2luZyBhIHRyYWNlYmFjayB3aGVyZSB0aGUgcHJvbW90aW9uIGJhciB3b3VsZCBi'
    || 'ZS4gQW4gZW1wdHkgcmVzdWx0IGlzIHRoZQogICAgbm9ybWFsIGNhc2UgLS0gbW9zdCBhY3Rpb25zIHRha2Ugbm8gcGFyYW1ldGVycyBhbmQgcmVuZGVyIGV4'
    || 'YWN0bHkgYXMgYmVmb3JlLgoKICAgIERlbGliZXJhdGVseSBOT1QgZm9sZGVkIGludG8gbG9hZF9hY3Rpb25zLiBUaGF0IGZ1bmN0aW9uJ3MgU0VMRUNUIGxp'
    || 'c3QgaXMgaXRzCiAgICBjb21wYXRpYmlsaXR5IGNvbnRyYWN0IHdpdGggb2xkZXIgc2NoZW1hczsgYWRkaW5nIGEgY29sdW1uIHRvIGl0IHdvdWxkIG1ha2Ug'
    || 'ZXZlcnkKICAgIGJ1aWxkIHdpdGhvdXQgdGhhdCBjb2x1bW4gZmFsbCBpbnRvIHRoZSBleGNlcHQgYnJhbmNoIGFuZCBsb3NlIGl0cyB3aG9sZSBhY3Rpb24K'
    || 'ICAgIGJhci4gQSBzZXBhcmF0ZSwgc2VwYXJhdGVseS13cmFwcGVkIHJlYWQgZGVncmFkZXMgdG8gIm5vIHBhcmFtZXRlcnMiIGluc3RlYWQuCiAgICAiIiIK'
    || 'ICAgIHRyeToKICAgICAgICByb3dzID0gW3IuYXNfZGljdCgpIGZvciByIGluIHNlc3Npb24uc3FsKAogICAgICAgICAgICAiU0VMRUNUIENPREUsIE9SRElO'
    || 'QUwsIFBBUkFNX05BTUUsIExBQkVMLCBLSU5ELCBPUFRJT05TX1NRTCwgT1BUSU9OUywgIgogICAgICAgICAgICAiTUlOX1ZBTFVFLCBNQVhfVkFMVUUsIEhF'
    || 'TFAgRlJPTSAiICsgdGd0ICsgIi5WX0FDVElPTl9QQVJBTVMgIgogICAgICAgICAgICAiT1JERVIgQlkgQ09ERSwgT1JESU5BTCIpLmNvbGxlY3QoKV0KICAg'
    || 'IGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgcmV0dXJuIHt9CiAgICBvdXQgPSB7fQogICAgZm9yIHIgaW4gcm93czoKICAgICAgICBvdXQuc2V0ZGVmYXVs'
    || 'dChzdHIoci5nZXQoIkNPREUiKSBvciAiIiksIFtdKS5hcHBlbmQocikKICAgIHJldHVybiBvdXQKCgpkZWYgYWN0aW9uX3BhcmFtX29wdGlvbnMoc2Vzc2lv'
    || 'biwgcCkgLT4gbGlzdDoKICAgICIiIlRoZSBjaG9pY2VzIHRvIE9GRkVSIGZvciBvbmUgcGFyYW1ldGVyLiBEaXNwbGF5IG9ubHkuCgogICAgVGhpcyBsaXN0'
    || 'IGlzIHdoYXQgdGhlIHdpZGdldCBzaG93czsgaXQgaXMgTk9UIHdoYXQgYXV0aG9yaXNlcyB0aGUgdmFsdWUuIFRoZQogICAgcHJvY2VkdXJlIHJlLXJ1bnMg'
    || 'dGhlIHJlZ2lzdHJ5J3Mgb3duIGFsbG93ZWRfc3FsIHdoZW4gaXQgdmFsaWRhdGVzLCBzbyBhIHN0YWxlIG9yCiAgICB0YW1wZXJlZCBsaXN0IGhlcmUgY2Fu'
    || 'bm90IHdpZGVuIHdoYXQgYW4gYWN0aW9uIHdpbGwgYWNjZXB0IC0tIGl0IGNhbiBvbmx5IGZhaWwgdG8KICAgIG9mZmVyIHNvbWV0aGluZyB0aGUgcHJvY2Vk'
    || 'dXJlIHdvdWxkIGhhdmUgcGVybWl0dGVkLiBUaGF0IGFzeW1tZXRyeSBpcyBkZWxpYmVyYXRlOgogICAgdGhlIGFwcCBpcyBhbGxvd2VkIHRvIGJlIHdyb25n'
    || 'IGluIHRoZSBkaXJlY3Rpb24gb2Ygb2ZmZXJpbmcgdG9vIGxpdHRsZS4KICAgICIiIgogICAgb3B0cyA9IHAuZ2V0KCJPUFRJT05TIikKICAgIGlmIG9wdHM6'
    || 'CiAgICAgICAgdHJ5OgogICAgICAgICAgICByZXR1cm4gW3N0cih2KSBmb3IgdiBpbiAoanNvbi5sb2FkcyhvcHRzKSBpZiBpc2luc3RhbmNlKG9wdHMsIHN0'
    || 'cikgZWxzZSBvcHRzKV0KICAgICAgICBleGNlcHQgRXhjZXB0aW9uOgogICAgICAgICAgICBwYXNzCiAgICBzcWwgPSBzdHIocC5nZXQoIk9QVElPTlNfU1FM'
    || 'Iikgb3IgIiIpLnN0cmlwKCkKICAgIGlmIG5vdCBzcWw6CiAgICAgICAgcmV0dXJuIFtdCiAgICB0cnk6CiAgICAgICAgcmV0dXJuIFtzdHIoclswXSkgZm9y'
    || 'IHIgaW4gc2Vzc2lvbi5zcWwoCiAgICAgICAgICAgICJTRUxFQ1QgQUxMT1dFRF9WQUxVRSBGUk9NICgiICsgc3FsICsgIikgTElNSVQgIiArIHN0cihST1df'
    || 'Q0FQKSkuY29sbGVjdCgpXQogICAgZXhjZXB0IEV4Y2VwdGlvbjoKICAgICAgICAjIEEgYnJva2VuIG9wdGlvbnMgcXVlcnkgbXVzdCBub3QgdGFrZSB0aGUg'
    || 'd2hvbGUgcHJvbW90aW9uIGJhciBkb3duIHdpdGggaXQuCiAgICAgICAgIyBSZXR1cm5pbmcgbm90aGluZyBsZWF2ZXMgdGhlIGZpZWxkIGVtcHR5LCB0aGUg'
    || 'UnVuIGJ1dHRvbiBkaXNhYmxlZCwgYW5kIHRoZQogICAgICAgICMgcmVzdCBvZiB0aGUgYWN0aW9ucyB1c2FibGUuCiAgICAgICAgcmV0dXJuIFtdCgoKZGVm'
    || 'IGFjdGlvbl9wYXJhbV92YWx1ZXMoc2Vzc2lvbiwgY29kZTogc3RyLCBwYXJhbXM6IGxpc3QpOgogICAgIiIiUmVuZGVyIG9uZSB3aWRnZXQgcGVyIHBhcmFt'
    || 'ZXRlciBhbmQgcmV0dXJuICh2YWx1ZXMgZGljdCwgYWxsX3N1cHBsaWVkKS4KCiAgICBQbGFjZWQgSU5TSURFIHRoZSBhcm1lZCBjb25maXJtYXRpb24gYmxv'
    || 'Y2sgYnkgdGhlIGNhbGxlciwgbm90IG9uIHRoZSBhY3Rpb24gY2FyZC4KICAgIFR3byByZWFzb25zLiBUaGUgdmFsdWVzIG11c3Qgbm90IGJlIGFibGUgdG8g'
    || 'Y2hhbmdlIGJldHdlZW4gYXJtaW5nIGFuZCBjb25maXJtaW5nCiAgICAtLSB0aGUgdHlwZWQgY29kZSBjb25maXJtcyBhIHNwZWNpZmljIGNoYW5nZSwgc28g'
    || 'dGhlIGNoYW5nZSBoYXMgdG8gYmUgc2V0dGxlZAogICAgYmVmb3JlIGl0IGlzIHR5cGVkLiBBbmQgaXQga2VlcHMgdGhlIHR5cGVkIGNvbmZpcm1hdGlvbiBh'
    || 'cyB0aGUgZ2VudWluZSBsYXN0IHN0ZXAKICAgIHJhdGhlciB0aGFuIG9uZSBmaWVsZCBhbW9uZyBzZXZlcmFsLgogICAgIiIiCiAgICB2YWxzID0ge30KICAg'
    || 'IG1pc3NpbmcgPSBGYWxzZQogICAgZm9yIHAgaW4gcGFyYW1zOgogICAgICAgIG5hbWUgPSBzdHIocC5nZXQoIlBBUkFNX05BTUUiKSBvciAiIikKICAgICAg'
    || 'ICBsYWJlbCA9IHN0cihwLmdldCgiTEFCRUwiKSBvciBuYW1lKQogICAgICAgIGtpbmQgPSBzdHIocC5nZXQoIktJTkQiKSBvciAiSURFTlQiKS51cHBlcigp'
    || 'CiAgICAgICAga2V5ID0gInBhcmFtXyIgKyBjb2RlICsgIl8iICsgbmFtZQogICAgICAgIGhlbHBfdHh0ID0gc3RyKHAuZ2V0KCJIRUxQIikgb3IgIiIpIG9y'
    || 'IE5vbmUKICAgICAgICBpZiBraW5kID09ICJOVU1CRVIiOgogICAgICAgICAgICBsbyA9IHAuZ2V0KCJNSU5fVkFMVUUiKQogICAgICAgICAgICBoaSA9IHAu'
    || 'Z2V0KCJNQVhfVkFMVUUiKQogICAgICAgICAgICB2ID0gc3QubnVtYmVyX2lucHV0KAogICAgICAgICAgICAgICAgbGFiZWwsIGtleT1rZXksIGhlbHA9aGVs'
    || 'cF90eHQsCiAgICAgICAgICAgICAgICBtaW5fdmFsdWU9ZmxvYXQobG8pIGlmIGxvIGlzIG5vdCBOb25lIGVsc2UgTm9uZSwKICAgICAgICAgICAgICAgIG1h'
    || 'eF92YWx1ZT1mbG9hdChoaSkgaWYgaGkgaXMgbm90IE5vbmUgZWxzZSBOb25lLAogICAgICAgICAgICAgICAgdmFsdWU9ZmxvYXQobG8pIGlmIGxvIGlzIG5v'
    || 'dCBOb25lIGVsc2UgMC4wLAogICAgICAgICAgICAgICAgc3RlcD0xLjApCiAgICAgICAgICAgICMgRW1pdCB3aG9sZSBudW1iZXJzIHdpdGhvdXQgYSB0cmFp'
    || 'bGluZyAuMDogQVJDSElWRV9GT1JfREFZUyA9IDkwLjAgaXMgbm90CiAgICAgICAgICAgICMgdmFsaWQgaW4gdGhlIERETCBjbGF1c2UgdGhpcyBsYW5kcyBp'
    || 'bi4KICAgICAgICAgICAgdmFsc1tuYW1lXSA9IHN0cihpbnQodikpIGlmIGZsb2F0KHYpLmlzX2ludGVnZXIoKSBlbHNlIHN0cih2KQogICAgICAgICAgICBj'
    || 'b250aW51ZQogICAgICAgIGNob2ljZXMgPSBhY3Rpb25fcGFyYW1fb3B0aW9ucyhzZXNzaW9uLCBwKQogICAgICAgIGlmIGNob2ljZXM6CiAgICAgICAgICAg'
    || 'ICMgaW5kZXg9Tm9uZSBzbyBub3RoaW5nIGlzIHByZS1zZWxlY3RlZC4gQSBwcmUtZmlsbGVkIHRhcmdldCBpcyBob3cgc29tZW9uZQogICAgICAgICAgICAj'
    || 'IHJ1bnMgYSBjaGFuZ2UgYWdhaW5zdCB3aGF0ZXZlciBoYXBwZW5lZCB0byBzb3J0IGZpcnN0LgogICAgICAgICAgICB2ID0gc3Quc2VsZWN0Ym94KGxhYmVs'
    || 'LCBjaG9pY2VzLCBpbmRleD1Ob25lLCBrZXk9a2V5LCBoZWxwPWhlbHBfdHh0LAogICAgICAgICAgICAgICAgICAgICAgICAgICAgIHBsYWNlaG9sZGVyPSJD'
    || 'aG9vc2UgIiArIGxhYmVsLmxvd2VyKCkpCiAgICAgICAgICAgIGlmIHYgaXMgTm9uZToKICAgICAgICAgICAgICAgIG1pc3NpbmcgPSBUcnVlCiAgICAgICAg'
    || 'ICAgIGVsc2U6CiAgICAgICAgICAgICAgICB2YWxzW25hbWVdID0gc3RyKHYpCiAgICAgICAgZWxpZiBwLmdldCgiRlJFRUZPUk0iKToKICAgICAgICAgICAg'
    || 'IyBBIG5hbWUgYmVpbmcgQ1JFQVRFRCBjYW5ub3QgYmUgY2hlY2tlZCBhZ2FpbnN0IGEgbGlzdCBvZiB0aGluZ3MgdGhhdAogICAgICAgICAgICAjIGFscmVh'
    || 'ZHkgZXhpc3QsIHNvIHRoaXMgb25lIGlzIHR5cGVkLiBJdCBpcyBub3QgdW52YWxpZGF0ZWQ6IHRoZSBwcm9jZWR1cmUKICAgICAgICAgICAgIyBzdGlsbCBh'
    || 'cHBsaWVzIHRoZSBpZGVudGlmaWVyIHNoYXBlIGdhdGUsIHNvIGFueXRoaW5nIGNhcnJ5aW5nIGEgcXVvdGUsIGEKICAgICAgICAgICAgIyBzcGFjZSBvciBh'
    || 'IHN0YXRlbWVudCB0ZXJtaW5hdG9yIGlzIHJlZnVzZWQgc2VydmVyLXNpZGUuCiAgICAgICAgICAgIHYgPSBzdC50ZXh0X2lucHV0KGxhYmVsLCBrZXk9a2V5'
    || 'LCBoZWxwPWhlbHBfdHh0KQogICAgICAgICAgICBpZiBub3Qgc3RyKHYgb3IgIiIpLnN0cmlwKCk6CiAgICAgICAgICAgICAgICBtaXNzaW5nID0gVHJ1ZQog'
    || 'ICAgICAgICAgICBlbHNlOgogICAgICAgICAgICAgICAgdmFsc1tuYW1lXSA9IHN0cih2KS5zdHJpcCgpCiAgICAgICAgZWxzZToKICAgICAgICAgICAgc3Qu'
    || 'Y2FwdGlvbihsYWJlbCArICIg4oCUIG5vIHBlcm1pdHRlZCB2YWx1ZXMgYXJlIGF2YWlsYWJsZSBmb3IgdGhpcyBidWlsZCwgIgogICAgICAgICAgICAgICAg'
    || 'ICAgICAgICJzbyB0aGlzIGFjdGlvbiBjYW5ub3QgcnVuLiBOb3RoaW5nIGlzIHN3aXRjaGVkIG9mZjsgdGhlcmUgaXMgIgogICAgICAgICAgICAgICAgICAg'
    || 'ICAgICJzaW1wbHkgbm90aGluZyBpdCBjb3VsZCBsZWdhbGx5IGJlIHBvaW50ZWQgYXQuIikKICAgICAgICAgICAgbWlzc2luZyA9IFRydWUKICAgIHJldHVy'
    || 'biB2YWxzLCBub3QgbWlzc2luZwoKCmRlZiBwcm9tb3Rpb25fYmFyKHNlc3Npb24sIHRndDogc3RyKSAtPiBOb25lOgogICAgIiIiVGhlIG9uZSBwbGFjZSBp'
    || 'biB0aGUgYXBwIHRoYXQgY2FuIGNoYW5nZSB0aGUgYWNjb3VudC4KCiAgICBOYXRpdmUgU3RyZWFtbGl0IHJhdGhlciB0aGFuIHBhcnQgb2YgdGhlIFJlYWN0'
    || 'IHBhZ2UsIGFuZCBub3QgYnkgcHJlZmVyZW5jZToKICAgIHRoZSBidW5kbGUgcnVucyBpbnNpZGUgY29tcG9uZW50cy5odG1sLCB3aGljaCBpcyBhIHNhbmRi'
    || 'b3hlZCBjcm9zcy1vcmlnaW4KICAgIGlmcmFtZSB3aXRoIG5vIFNub3dmbGFrZSBzZXNzaW9uLCBzbyBhIFJlYWN0IGJ1dHRvbiBwaHlzaWNhbGx5IGNhbm5v'
    || 'dCBleGVjdXRlCiAgICBhbnl0aGluZy4gVGhlIGJpZGlyZWN0aW9uYWwgYWx0ZXJuYXRpdmUgKHN0LmNvbXBvbmVudHMudjIpIG5lZWRzIFN0cmVhbWxpdAog'
    || 'ICAgMS41NyssIGFuZCB3YXJlaG91c2UgcnVudGltZXMgY2FwIGF0IDEuNTIuMi4gU28gdGhlIGRpc3BsYXkgaXMgUmVhY3QgYW5kIHRoZQogICAgY29udHJv'
    || 'bHMgYXJlIFN0cmVhbWxpdCwgc3R5bGVkIHRvIHNpdCB3aXRoIGl0LgoKICAgIERlbGliZXJhdGVseSB1c2VzIG5vIHN0Lm1hcmtkb3duOiB0aGUgaG9zdCBj'
    || 'aGVjayB0cmVhdHMgc3RyYXkgbWFya2Rvd24gYXMKICAgIHBhZ2UgY29udGVudCBsZWFraW5nIG91dHNpZGUgdGhlIGNvbXBvbmVudCwgd2hpY2ggaXMgaG93'
    || 'IGEgc3BsaWNlZCBkb2NzdHJpbmcKICAgIG9uY2Ugc2hpcHBlZCB0aGUgd2hvbGUgYXBwIGFzIGEgdHJhY2ViYWNrLiBXaWRnZXRzIGFyZSBpbnRlbnRpb25h'
    || 'bCBhbmQKICAgIGV4ZW1wdDsgcHJvc2UgaXMgbm90LgogICAgIiIiCiAgICAoYWxsb3dfcmVhbCwgYWxsb3dfc2FtcGxlKSwgcm93cyA9IGxvYWRfYWN0aW9u'
    || 'cyhzZXNzaW9uLCB0Z3QpCgogICAgIyBUaGUgc3RhbmRpbmcgY29zdCBwcmludHMgd2hldGhlciBvciBub3QgdGhpcyBidWlsZCByZWdpc3RlcmVkIGFueSBh'
    || 'Y3Rpb25zLAogICAgIyBhbmQgQkVGT1JFIHRoZW0sIGJlY2F1c2UgaXQgaXMgdGhlIHJlY3VycmluZyBudW1iZXIuIEVhY2ggYnV0dG9uIGJlbG93CiAgICAj'
    || 'IGNvc3RzIHNvbWV0aGluZyBPTkNFOyB0aGlzIGlzIHdoYXQgdGhlIGJ1aWxkIGNvc3RzIGV2ZXJ5IG1vbnRoIGlmIG5vYm9keQogICAgIyB0b3VjaGVzIGl0'
    || 'IGFnYWluLiBEZWxpYmVyYXRlbHkgbm90IHN1bW1lZCB3aXRoIHRoZSBwZXItYWN0aW9uIGVzdGltYXRlcyAtLQogICAgIyBvbmUgaXMgUFJPSkVDVEVEIGFu'
    || 'ZCB0aGUgb3RoZXIgaXMgbWVhc3VyZWQsIGFuZCBhZGRpbmcgdGhlbSB3b3VsZCBpbnZlbnQgYQogICAgIyBmaWd1cmUgdGhhdCBtZWFucyBub3RoaW5nLgog'
    || 'ICAgaGwgPSBsb2FkX2hlYWRsaW5lKHNlc3Npb24sIHRndCkKICAgIGlmIGhsIGlzIG5vdCBOb25lIGFuZCBobFswXToKICAgICAgICBzdC5jYXB0aW9uKCJX'
    || 'SEFUIFRISVMgQ09TVFMgVE8gTEVBVkUgUlVOTklORyIpCiAgICAgICAgc3QuY2FwdGlvbihobFswXSkKCiAgICBpZiBub3Qgcm93czoKICAgICAgICByZXR1'
    || 'cm4KCiAgICBzdC5jYXB0aW9uKCJXSEFUIFRISVMgQ0FOIERPIE5FWFQiKQogICAgIyBPbmx5IHdhcm4gYWJvdXQgd2hhdCBpcyBhY3R1YWxseSBzd2l0Y2hl'
    || 'ZCBvZmYuIEFubm91bmNpbmcgInRoZXNlIGFyZSBzd2l0Y2hlZAogICAgIyBvZmYiIG92ZXIgYSBsaXN0IGNvbnRhaW5pbmcgbGl2ZSBTQU1QTEUgYnV0dG9u'
    || 'cyBpcyB3b3JzZSB0aGFuIHNpbGVuY2U6IHRoZQogICAgIyByZWFkZXIgYmVsaWV2ZXMgaXQgYW5kIHN0b3BzIHRyeWluZy4KICAgIGlmIG5vdCBhbGxvd19y'
    || 'ZWFsIGFuZCBub3QgYWxsb3dfc2FtcGxlOgogICAgICAgIHBmeCA9IGxvYWRfcHJlZml4KHNlc3Npb24sIHRndCkKICAgICAgICAjIE5hbWUgdGhlIGxpbmUs'
    || 'IG5vdCB0aGUgc2V0dGluZy4gInJlLXJ1biB3aXRoIEFMTE9XX0FDVElPTlMgPSBUUlVFIiBzZW50CiAgICAgICAgIyB0aGUgcmVhZGVyIGxvb2tpbmcgZm9y'
    || 'IGEgc2V0dGluZyB0aGF0IGFwcGVhcnMgaW4gbm8gZmlsZSB1bmRlciB0aGF0CiAgICAgICAgIyBuYW1lLCB3aGljaCBpcyBob3cgYSBwdXNoLWJ1dHRvbiBk'
    || 'ZXBsb3ltZW50IGNhbWUgdG8gbG9vayBsaWtlIGl0IG5lZWRlZAogICAgICAgICMgYSB0ZXJtaW5hbCBzZXNzaW9uIGFuZCBzb21lIGd1ZXNzd29yay4KICAg'
    || 'ICAgICBhcm0gPSAoIlNFVCAiICsgcGZ4ICsgIl9BTExPV19BQ1RJT05TID0gVFJVRTsiKSBpZiBwZnggZWxzZSAiQUxMT1dfQUNUSU9OUyA9IFRSVUUiCiAg'
    || 'ICAgICAgc3QuaW5mbygKICAgICAgICAgICAgIlRoZXNlIGFyZSBzd2l0Y2hlZCBvZmYuIFRoaXMgYnVpbGQgd2FzIGNyZWF0ZWQgd2l0aCAiCiAgICAgICAg'
    || 'ICAgICJBTExPV19BQ1RJT05TID0gRkFMU0UsIHNvIHRoZSBidXR0b25zIGJlbG93IGFyZSBpbmVydCBhbmQgdGhlICIKICAgICAgICAgICAgInByb2NlZHVy'
    || 'ZSBiZWhpbmQgdGhlbSByZWZ1c2VzLiBFdmVyeXRoaW5nIGVhY2ggb25lIHdvdWxkIGRvLCBhbmQgIgogICAgICAgICAgICAid2hhdCBpdCB3b3VsZCBjb3N0'
    || 'LCBpcyBsaXN0ZWQgYW55d2F5IOKAlCB0byBhcm0gdGhlbSwgY2hhbmdlIHRoZSAiCiAgICAgICAgICAgICJsaW5lIG5lYXIgdGhlIHRvcCBvZiB0aGUgc2Ny'
    || 'aXB0IHlvdSBhbHJlYWR5IHJhbiB0byAiCiAgICAgICAgICAgICsgYXJtICsgIiBhbmQgcnVuIHRoYXQgZmlsZSBhZ2Fpbi4gVGhlcmUgaXMgbm90aGluZyBl'
    || 'bHNlIHRvIHR5cGU6ICIKICAgICAgICAgICAgInRoZSBmaWxlIGlzIHRoZSBvbmx5IHBsYWNlIHRoaXMgaXMgc3dpdGNoZWQgb24sIGFuZCBydW5uaW5nIGl0'
    || 'IGlzICIKICAgICAgICAgICAgInRoZSB3aG9sZSBwcm9jZWR1cmUuIiwKICAgICAgICAgICAgaWNvbj0iOm1hdGVyaWFsL2xvY2s6IikKCiAgICBieV90aWVy'
    || 'ID0ge30KICAgIGZvciByIGluIHJvd3M6CiAgICAgICAgYnlfdGllci5zZXRkZWZhdWx0KHN0cihyLmdldCgiVElFUiIpIG9yICJQUk9EVUNUSU9OIikudXBw'
    || 'ZXIoKSwgW10pLmFwcGVuZChyKQoKICAgIGZvciB0aWVyIGluIFRJRVJfT1JERVI6CiAgICAgICAgZ3JvdXAgPSBieV90aWVyLmdldCh0aWVyLCBbXSkKICAg'
    || 'ICAgICBpZiBub3QgZ3JvdXA6CiAgICAgICAgICAgIGNvbnRpbnVlCiAgICAgICAgIyBTQU1QTEUgcnVucyBvbiBzZWVkZWQgZGF0YSB0aGlzIHNjcmlwdCBj'
    || 'cmVhdGVkLCBzbyBpdCBhbnN3ZXJzIHRvCiAgICAgICAgIyBBTExPV19TQU1QTEVfQUNUSU9OUy4gRXZlcnl0aGluZyBlbHNlIHRvdWNoZXMgdGhlIGN1c3Rv'
    || 'bWVyJ3Mgb3duIG9iamVjdHMKICAgICAgICAjIGFuZCBhbnN3ZXJzIHRvIEFMTE9XX0FDVElPTlMuIFVua25vd24gdGllcnMgdGFrZSB0aGUgc3RyaWN0ZXIg'
    || 'Z2F0ZS4KICAgICAgICB0aWVyX2VuYWJsZWQgPSBhbGxvd19zYW1wbGUgaWYgdGllciA9PSAiU0FNUExFIiBlbHNlIGFsbG93X3JlYWwKICAgICAgICBzdC5j'
    || 'YXB0aW9uKHRpZXIgKyAiIOKAlCAiICsgVElFUl9CTFVSQi5nZXQodGllciwgIiIpCiAgICAgICAgICAgICAgICAgICArICgiIiBpZiB0aWVyX2VuYWJsZWQg'
    || 'ZWxzZQogICAgICAgICAgICAgICAgICAgICAgIiAgwrcgIHN3aXRjaGVkIG9mZiBpbiB0aGUgZmlsZSIpKQogICAgICAgIGNvbHMgPSBzdC5jb2x1bW5zKGxl'
    || 'bihncm91cCkpCiAgICAgICAgZm9yIGNvbCwgciBpbiB6aXAoY29scywgZ3JvdXApOgogICAgICAgICAgICB3aXRoIGNvbDoKICAgICAgICAgICAgICAgIGNv'
    || 'ZGUgPSBzdHIoci5nZXQoIkNPREUiKSBvciAiIikKICAgICAgICAgICAgICAgIGVzdCA9IHIuZ2V0KCJFU1RfQ1JFRElUUyIpCiAgICAgICAgICAgICAgICAj'
    || 'IFRocmVlIGxpbmVzIGFuZCBhIGJ1dHRvbiwgbm90IGZpdmUgbGluZXMgYW5kIGEgYnV0dG9uLiBUaGUKICAgICAgICAgICAgICAgICMgZXN0aW1hdGUgYW5k'
    || 'IGl0cyBiYXNpcyBzdGlsbCB0cmF2ZWwgV0lUSCB0aGUgY29udHJvbCAtLSBhIGJ1dHRvbgogICAgICAgICAgICAgICAgIyB0aGF0IGNoYW5nZXMgcHJvZHVj'
    || 'dGlvbiB3aXRob3V0IHNheWluZyB3aGF0IGl0IGNvc3RzIGlzIHRoZSB0aGluZwogICAgICAgICAgICAgICAgIyB0aGlzIHJlcG8gZXhpc3RzIHRvIGF2b2lk'
    || 'IC0tIGJ1dCBgYmFzaXNgIGFuZCBgdW5kb2AgYmVsb25nIGluIHRoZQogICAgICAgICAgICAgICAgIyB0b29sdGlwLiBSZW5kZXJlZCBhcyBjb2x1bW5zIG9m'
    || 'IGJvZHkgdGV4dCB0aGV5IHdlcmUgZm91ciBsaW5lcyBvZgogICAgICAgICAgICAgICAgIyBwcm9zZSBlYWNoLCBhbmQgdGhlIHJlYWRlciBzdG9wcGVkIGJl'
    || 'Zm9yZSB0aGUgYnV0dG9uLgogICAgICAgICAgICAgICAgc3QuY2FwdGlvbigiKioiICsgc3RyKHIuZ2V0KCJMQUJFTCIpIG9yIGNvZGUpICsgIioqIikKICAg'
    || 'ICAgICAgICAgICAgIHN0LmNhcHRpb24oIn4iICsgZm10X2NyZWRpdHMoZXN0KSArICIgY3JlZGl0cyDCtyAiCiAgICAgICAgICAgICAgICAgICAgICAgICAg'
    || 'ICsgc3RyKHIuZ2V0KCJTVEFURU1FTlRTIikgb3IgMCkgKyAiIHN0YXRlbWVudChzKSIKICAgICAgICAgICAgICAgICAgICAgICAgICAgKyAoIiDCtyBydW4g'
    || 'IiArIHN0cihyWyJUSU1FU19SVU4iXSkgKyAieCBhbHJlYWR5IgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICBpZiByLmdldCgiVElNRVNfUlVOIikg'
    || 'ZWxzZSAiIikpCiAgICAgICAgICAgICAgICBzdC5jYXB0aW9uKHN0cihyLmdldCgiRUZGRUNUIikgb3IgIm5vdCBzdGF0ZWQiKSkKICAgICAgICAgICAgICAg'
    || 'IGlmIHN0LmJ1dHRvbigiUnVuICIgKyBjb2RlLCBrZXk9ImFybV8iICsgY29kZSwgZGlzYWJsZWQ9bm90IHRpZXJfZW5hYmxlZCwKICAgICAgICAgICAgICAg'
    || 'ICAgICAgICAgICAgICB1c2VfY29udGFpbmVyX3dpZHRoPVRydWUsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgaGVscD0iRXN0aW1hdGUgYmFzaXM6'
    || 'ICIgKyBzdHIoci5nZXQoIkVTVF9CQVNJUyIpIG9yICJub3Qgc3RhdGVkIikKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICsgIlxuXG5UbyB1'
    || 'bmRvOiAiICsgc3RyKHIuZ2V0KCJVTkRPIikgb3IgIm5vdCBzdGF0ZWQiKSk6CiAgICAgICAgICAgICAgICAgICAgc3Quc2Vzc2lvbl9zdGF0ZVsiYXJtZWQi'
    || 'XSA9IGNvZGUKICAgICAgICAgICAgICAgICAgICBzdC5zZXNzaW9uX3N0YXRlLnBvcCgicmVzdWx0XyIgKyBjb2RlLCBOb25lKQogICAgICAgICAgICAgICAg'
    || 'IyBVbmRvIGFwcGVhcnMgb25seSBvbmNlIHRoZSBhY3Rpb24gaGFzIGFjdHVhbGx5IGNvbXBsZXRlZCwgYmVjYXVzZQogICAgICAgICAgICAgICAgIyBVTkRP'
    || 'X0FDVElPTiByZWZ1c2VzIG90aGVyd2lzZSBhbmQgYSBidXR0b24gd2hvc2Ugb25seSBvdXRjb21lIGlzIGEKICAgICAgICAgICAgICAgICMgcmVmdXNhbCB0'
    || 'ZWFjaGVzIHRoZSByZWFkZXIgdG8gZGlzdHJ1c3QgYWxsIG9mIHRoZW0uIEFuIGFjdGlvbiB3aXRoCiAgICAgICAgICAgICAgICAjIG5vIHJldmVyc2Ugc3Rh'
    || 'dGVtZW50cyBuZXZlciBzaG93cyBvbmUgYXQgYWxsIC0tIHNheWluZyAibm90CiAgICAgICAgICAgICAgICAjIHJldmVyc2libGUiIHBsYWlubHkgYmVhdHMg'
    || 'b2ZmZXJpbmcgYSBjb250cm9sIHRoYXQgY2Fubm90IHdvcmsuCiAgICAgICAgICAgICAgICBpZiByLmdldCgiVU5ET19TVEFURU1FTlRTIikgYW5kIHIuZ2V0'
    || 'KCJUSU1FU19SVU4iKToKICAgICAgICAgICAgICAgICAgICBpZiBzdC5idXR0b24oIlVuZG8gIiArIGNvZGUsIGtleT0idW5kb2FybV8iICsgY29kZSwKICAg'
    || 'ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgZGlzYWJsZWQ9bm90IHRpZXJfZW5hYmxlZCwgdXNlX2NvbnRhaW5lcl93aWR0aD1UcnVlLAogICAgICAg'
    || 'ICAgICAgICAgICAgICAgICAgICAgICAgICBoZWxwPSJSdW5zICIgKyBzdHIoclsiVU5ET19TVEFURU1FTlRTIl0pCiAgICAgICAgICAgICAgICAgICAgICAg'
    || 'ICAgICAgICAgICAgICAgKyAiIHJldmVyc2Ugc3RhdGVtZW50KHMpLiAiICsgc3RyKHIuZ2V0KCJVTkRPIikgb3IgIiIpKToKICAgICAgICAgICAgICAgICAg'
    || 'ICAgICAgc3Quc2Vzc2lvbl9zdGF0ZVsiYXJtZWQiXSA9IGNvZGUKICAgICAgICAgICAgICAgICAgICAgICAgc3Quc2Vzc2lvbl9zdGF0ZVsiYXJtZWRfdW5k'
    || 'byJdID0gVHJ1ZQogICAgICAgICAgICAgICAgICAgICAgICBzdC5zZXNzaW9uX3N0YXRlLnBvcCgicmVzdWx0XyIgKyBjb2RlLCBOb25lKQogICAgICAgICAg'
    || 'ICAgICAgZWxpZiByLmdldCgiVElNRVNfUlVOIikgYW5kIG5vdCByLmdldCgiVU5ET19TVEFURU1FTlRTIik6CiAgICAgICAgICAgICAgICAgICAgc3QuY2Fw'
    || 'dGlvbigiTm8gYXV0b21hdGljIHVuZG8g4oCUIHNlZSB0aGUgdW5kbyBub3RlIGluIHRoZSB0b29sdGlwLiIpCiAgICAgICAgICAgICAgICBpZiByLmdldCgi'
    || 'VElNRVNfVU5ET05FIik6CiAgICAgICAgICAgICAgICAgICAgc3QuY2FwdGlvbigiVW5kb25lICIgKyBzdHIoclsiVElNRVNfVU5ET05FIl0pICsgIngiKQoK'
    || 'ICAgIGFybWVkID0gc3Quc2Vzc2lvbl9zdGF0ZS5nZXQoImFybWVkIikKICAgIHVuZG9pbmcgPSBib29sKHN0LnNlc3Npb25fc3RhdGUuZ2V0KCJhcm1lZF91'
    || 'bmRvIikpCiAgICAjIFJlc29sdmUgdGhlIEFSTUVEIGFjdGlvbidzIG93biB0aWVyLiBEZWxpYmVyYXRlbHkgbm90IGB0aWVyX2VuYWJsZWRgIGZyb20gdGhl'
    || 'CiAgICAjIGxvb3AgYWJvdmU6IHRoYXQgdmFyaWFibGUgaG9sZHMgd2hpY2hldmVyIHRpZXIgaGFwcGVuZWQgdG8gYmUgcmVuZGVyZWQgbGFzdCwKICAgICMg'
    || 'c28gcmV1c2luZyBpdCBoZXJlIHdvdWxkIGdhdGUgdGhlIGNvbmZpcm1hdGlvbiBvbiBhbiB1bnJlbGF0ZWQgYWN0aW9uLiBEZWZhdWx0CiAgICAjIHRvIHRo'
    || 'ZSBzdHJpY3RlciBmbGFnIHdoZW4gdGhlIGNvZGUgY2Fubm90IGJlIGZvdW5kLgogICAgYXJtZWRfdGllciA9ICJQUk9EVUNUSU9OIgogICAgZm9yIHIgaW4g'
    || 'cm93czoKICAgICAgICBpZiBzdHIoci5nZXQoIkNPREUiKSBvciAiIikgPT0gc3RyKGFybWVkIG9yICIiKToKICAgICAgICAgICAgYXJtZWRfdGllciA9IHN0'
    || 'cihyLmdldCgiVElFUiIpIG9yICJQUk9EVUNUSU9OIikudXBwZXIoKQogICAgICAgICAgICBicmVhawogICAgYXJtZWRfZW5hYmxlZCA9IGFsbG93X3NhbXBs'
    || 'ZSBpZiBhcm1lZF90aWVyID09ICJTQU1QTEUiIGVsc2UgYWxsb3dfcmVhbAogICAgaWYgYXJtZWQgYW5kIGFybWVkX2VuYWJsZWQ6CiAgICAgICAgc3QuY2Fw'
    || 'dGlvbigoIkNPTkZJUk0gVU5ETyBPRiAiIGlmIHVuZG9pbmcgZWxzZSAiQ09ORklSTSAiKSArIGFybWVkKQogICAgICAgICMgUGFyYW1ldGVycyBhcmUgY2hv'
    || 'c2VuIEhFUkUsIGJlZm9yZSB0aGUgY29kZSBpcyB0eXBlZCwgYW5kIG9ubHkgZm9yIGEgZm9yd2FyZAogICAgICAgICMgcnVuLiBBbiB1bmRvIHRha2VzIG5v'
    || 'bmUgYnkgZGVzaWduOiBSVU5fQUNUSU9OIHJlc29sdmVkIGFuZCBzbmFwc2hvdHRlZCB0aGUKICAgICAgICAjIHJldmVyc2Ugc3RhdGVtZW50cyB3aGVuIHRo'
    || 'ZSBhY3Rpb24gcmFuLCBzbyBVTkRPX0FDVElPTiByZXBsYXlzIHRoYXQgZXhhY3QKICAgICAgICAjIHRleHQuIE9mZmVyaW5nIHRoZSB2YWx1ZXMgYWdhaW4g'
    || 'd291bGQgaW52aXRlIHJldmVyc2luZyBhIGRpZmZlcmVudCB0YXJnZXQKICAgICAgICAjIHRoYW4gdGhlIG9uZSB0aGF0IHdhcyBjaGFuZ2VkLCB3aGljaCBp'
    || 'cyB3b3JzZSB0aGFuIGhhdmluZyBubyB1bmRvLgogICAgICAgIHB2YWxzLCBwcmVhZHkgPSB7fSwgVHJ1ZQogICAgICAgIGlmIG5vdCB1bmRvaW5nOgogICAg'
    || 'ICAgICAgICBhcGFyYW1zID0gbG9hZF9hY3Rpb25fcGFyYW1zKHNlc3Npb24sIHRndCkuZ2V0KGFybWVkLCBbXSkKICAgICAgICAgICAgaWYgYXBhcmFtczoK'
    || 'ICAgICAgICAgICAgICAgIHN0LmNhcHRpb24oIkNob29zZSB3aGF0IGl0IHJ1bnMgYWdhaW5zdC4gVGhlc2UgYXJlIHRoZSBvbmx5IHZhbHVlcyB0aGlzICIK'
    || 'ICAgICAgICAgICAgICAgICAgICAgICAgICAgImJ1aWxkIGRpc2NvdmVyZWQgZm9yIGl0LCBhbmQgdGhlIHByb2NlZHVyZSByZS1jaGVja3MgeW91ciAiCiAg'
    || 'ICAgICAgICAgICAgICAgICAgICAgICAgICJjaG9pY2UgYWdhaW5zdCB0aGF0IHNhbWUgbGlzdCBiZWZvcmUgaXQgcnVucyBhbnl0aGluZy4iKQogICAgICAg'
    || 'ICAgICAgICAgcHZhbHMsIHByZWFkeSA9IGFjdGlvbl9wYXJhbV92YWx1ZXMoc2Vzc2lvbiwgYXJtZWQsIGFwYXJhbXMpCiAgICAgICAgc3QuY2FwdGlvbigi'
    || 'VHlwZSB0aGUgYWN0aW9uIGNvZGUgZXhhY3RseS4gVGhpcyBpcyB0aGUgbGFzdCBzdGVwIGJlZm9yZSBpdCBydW5zLiIKICAgICAgICAgICAgICAgICAgICsg'
    || 'KCIgVGhpcyBSRVZFUlNFUyB0aGUgYWN0aW9uOyByZXZlcnNpbmcgYSBtYXNraW5nIHBvbGljeSBleHBvc2VzICIKICAgICAgICAgICAgICAgICAgICAgICJ0'
    || 'aGUgY29sdW1uIGFnYWluLCBzbyBpdCBpcyBhIGNoYW5nZSBsaWtlIGFueSBvdGhlci4iCiAgICAgICAgICAgICAgICAgICAgICBpZiB1bmRvaW5nIGVsc2Ug'
    || 'IiIpKQogICAgICAgIHR5cGVkID0gc3QudGV4dF9pbnB1dCgiQ29uZmlybWF0aW9uIiwga2V5PSJjb25maXJtXyIgKyBhcm1lZCwKICAgICAgICAgICAgICAg'
    || 'ICAgICAgICAgICAgICAgbGFiZWxfdmlzaWJpbGl0eT0iY29sbGFwc2VkIiwgcGxhY2Vob2xkZXI9YXJtZWQpCiAgICAgICAgYzEsIGMyID0gc3QuY29sdW1u'
    || 'cyhbMSwgNF0pCiAgICAgICAgd2l0aCBjMToKICAgICAgICAgICAgIyBEaXNhYmxlZCB1bnRpbCBldmVyeSBwYXJhbWV0ZXIgaGFzIGEgdmFsdWUuIFRoZSBw'
    || 'cm9jZWR1cmUgcmVmdXNlcyBhCiAgICAgICAgICAgICMgbWlzc2luZyBvbmUgYW55d2F5IC0tIHRoaXMgb25seSBhdm9pZHMgdGVhY2hpbmcgdGhlIHJlYWRl'
    || 'ciB0aGF0IHRoZQogICAgICAgICAgICAjIGJ1dHRvbiBwcm9kdWNlcyByZWZ1c2Fscy4KICAgICAgICAgICAgZ28gPSBzdC5idXR0b24oIlJ1biBpdCIsIGtl'
    || 'eT0iZ29fIiArIGFybWVkLCB0eXBlPSJwcmltYXJ5IiwKICAgICAgICAgICAgICAgICAgICAgICAgICAgZGlzYWJsZWQ9bm90IHByZWFkeSkKICAgICAgICB3'
    || 'aXRoIGMyOgogICAgICAgICAgICBpZiBzdC5idXR0b24oIkNhbmNlbCIsIGtleT0iY2FuY2VsXyIgKyBhcm1lZCk6CiAgICAgICAgICAgICAgICBzdC5zZXNz'
    || 'aW9uX3N0YXRlLnBvcCgiYXJtZWQiLCBOb25lKQogICAgICAgICAgICAgICAgc3Quc2Vzc2lvbl9zdGF0ZS5wb3AoImFybWVkX3VuZG8iLCBOb25lKQogICAg'
    || 'ICAgICAgICAgICAgZ28gPSBGYWxzZQogICAgICAgIGlmIGdvOgogICAgICAgICAgICAjIFRoZSB0eXBlZCB2YWx1ZSBpcyBwYXNzZWQgYXMgYSBCSU5ELCBu'
    || 'ZXZlciBjb25jYXRlbmF0ZWQuIEl0IGlzCiAgICAgICAgICAgICMgYXR0YWNrZXItY29udHJvbGxlZCB0ZXh0IGdvaW5nIGludG8gYSBwcm9jZWR1cmUgY2Fs'
    || 'bCwgYW5kIHRoZQogICAgICAgICAgICAjIHByb2NlZHVyZSBjb21wYXJlcyBpdCB0byB0aGUgY29kZSByYXRoZXIgdGhhbiBleGVjdXRpbmcgaXQgLS0gYnV0'
    || 'CiAgICAgICAgICAgICMgYmluZGluZyBpcyB3aGF0IG1ha2VzIHRoYXQgdHJ1ZSByZWdhcmRsZXNzIG9mIHdoYXQgd2FzIHR5cGVkLgogICAgICAgICAgICAj'
    || 'CiAgICAgICAgICAgICMgVGhlIHBhcmFtZXRlciB2YWx1ZXMgYXJlIGJvdW5kIHRvbywgYXMgb25lIEpTT04gc3RyaW5nLiBUaGV5IGNhbm5vdCBiZQogICAg'
    || 'ICAgICAgICAjIGJvdW5kIGFzIGFuIE9CSkVDVCAtLSBhbmQgSlNPTiB0ZXh0IGlzIHdoYXQgVU5ET19TTkFQU0hPVCBhbHJlYWR5IHVzZXMsCiAgICAgICAg'
    || 'ICAgICMgZm9yIHRoZSBkb2N1bWVudGVkIHJlYXNvbiB0aGF0IGFuIEFSUkFZIGJpbmQgaXMgZnJhZ2lsZSB3aGlsZQogICAgICAgICAgICAjIFRPX0pTT04v'
    || 'UEFSU0VfSlNPTiByb3VuZC10cmlwcyBleGFjdGx5LiBCaW5kaW5nIGlzIG5vdCB3aGF0IG1ha2VzIHRoZW0KICAgICAgICAgICAgIyBzYWZlOiB0aGUgcHJv'
    || 'Y2VkdXJlIHZhbGlkYXRlcyBldmVyeSB2YWx1ZSBhZ2FpbnN0IHRoZSByZWdpc3RyeSdzIG93bgogICAgICAgICAgICAjIGFsbG93ZWQgbGlzdCBiZWZvcmUg'
    || 'aW50ZXJwb2xhdGluZyBhbnkgb2YgdGhlbS4gQmluZGluZyBqdXN0IG1lYW5zIHRoZQogICAgICAgICAgICAjIGNhbGwgaXRzZWxmIGNhbm5vdCBiZSBicm9r'
    || 'ZW4gYnkgd2hhdCB3YXMgY2hvc2VuLgogICAgICAgICAgICAjCiAgICAgICAgICAgICMgQW4gYWN0aW9uIHdpdGggbm8gcGFyYW1ldGVycyB0YWtlcyB0aGUg'
    || 'VFdPLUFSR1VNRU5UIHBhdGgsIHVuY2hhbmdlZCwgc28KICAgICAgICAgICAgIyBldmVyeSBleGlzdGluZyBzb2x1dGlvbiBjYWxscyBleGFjdGx5IHdoYXQg'
    || 'aXQgY2FsbGVkIGJlZm9yZS4KICAgICAgICAgICAgaWYgcHZhbHM6CiAgICAgICAgICAgICAgICBwcm9jID0gIi5SVU5fQUNUSU9OKD8sID8sID8pIgogICAg'
    || 'ICAgICAgICAgICAgYXJncyA9IFthcm1lZCwgdHlwZWQsIGpzb24uZHVtcHMocHZhbHMpXQogICAgICAgICAgICBlbHNlOgogICAgICAgICAgICAgICAgcHJv'
    || 'YyA9ICIuVU5ET19BQ1RJT04oPywgPykiIGlmIHVuZG9pbmcgZWxzZSAiLlJVTl9BQ1RJT04oPywgPykiCiAgICAgICAgICAgICAgICBhcmdzID0gW2FybWVk'
    || 'LCB0eXBlZF0KICAgICAgICAgICAgdHJ5OgogICAgICAgICAgICAgICAgb3V0ID0gc2Vzc2lvbi5zcWwoIkNBTEwgIiArIHRndCArIHByb2MsCiAgICAgICAg'
    || 'ICAgICAgICAgICAgICAgICAgICAgICAgICBwYXJhbXM9YXJncykuY29sbGVjdCgpWzBdWzBdCiAgICAgICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZXhj'
    || 'OgogICAgICAgICAgICAgICAgb3V0ID0gIkZBSUxFRCB0byBjYWxsICIgKyBwcm9jLnNwbGl0KCIoIilbMF0uc3RyaXAoIi4iKSArICI6ICIgKyBzdHIoZXhj'
    || 'KQogICAgICAgICAgICBzdC5zZXNzaW9uX3N0YXRlWyJyZXN1bHRfIiArIGFybWVkXSA9IHN0cihvdXQpCiAgICAgICAgICAgIHN0LnNlc3Npb25fc3RhdGUu'
    || 'cG9wKCJhcm1lZCIsIE5vbmUpCiAgICAgICAgICAgIHN0LnNlc3Npb25fc3RhdGUucG9wKCJhcm1lZF91bmRvIiwgTm9uZSkKICAgICAgICAgICAgaW52YWxp'
    || 'ZGF0ZV9wYW5lbF9jYWNoZSgpCiAgICAgICAgICAgIHN0LnJlcnVuKCkKCiAgICBmb3IgayBpbiBbayBmb3IgayBpbiBzdC5zZXNzaW9uX3N0YXRlIGlmIHN0'
    || 'cihrKS5zdGFydHN3aXRoKCJyZXN1bHRfIildOgogICAgICAgIG1zZyA9IHN0cihzdC5zZXNzaW9uX3N0YXRlW2tdKQogICAgICAgIGlmIG1zZy5zdGFydHN3'
    || 'aXRoKCJET05FIikgb3IgbXNnLnN0YXJ0c3dpdGgoIlVORE9ORSIpOgogICAgICAgICAgICBzdC5zdWNjZXNzKG1zZywgaWNvbj0iOm1hdGVyaWFsL2NoZWNr'
    || 'OiIpCiAgICAgICAgZWxpZiBtc2cuc3RhcnRzd2l0aCgiUEFSVElBTExZIFVORE9ORSIpOgogICAgICAgICAgICAjIE5vdCBhbiBlcnJvciBhbmQgbm90IGEg'
    || 'c3VjY2Vzczogc29tZSBvZiB0aGUgYWNjb3VudCBjYW1lIGJhY2sgYW5kIHNvbWUKICAgICAgICAgICAgIyBkaWQgbm90LCBhbmQgdGhlIHJlYWRlciBoYXMg'
    || 'dG8ga25vdyB3aGljaCB3aXRob3V0IGd1ZXNzaW5nLgogICAgICAgICAgICBzdC53YXJuaW5nKG1zZywgaWNvbj0iOm1hdGVyaWFsL3dhcm5pbmc6IikKICAg'
    || 'ICAgICBlbGlmIG1zZy5zdGFydHN3aXRoKCJSRUZVU0VEIik6CiAgICAgICAgICAgIHN0Lndhcm5pbmcobXNnLCBpY29uPSI6bWF0ZXJpYWwvYmxvY2s6IikK'
    || 'ICAgICAgICBlbHNlOgogICAgICAgICAgICBzdC5lcnJvcihtc2csIGljb249IjptYXRlcmlhbC9lcnJvcjoiKQogICAgc3QuZGl2aWRlcigpCgoKZGVmIGxv'
    || 'YWRfYWdlbnQoc2Vzc2lvbiwgdGd0OiBzdHIpOgogICAgIiIiVGhlIGRlY2xhcmVkIGFnZW50LCBvciBOb25lLgoKICAgIEdhdGVzIG9uIHdoZXRoZXIgdGhl'
    || 'IHNvbHV0aW9uIGJ1aWx0IFZfQUdFTlRfQ0hBVCwgZXhhY3RseSBhcyBsb2FkX2FjdGlvbnMgZ2F0ZXMKICAgIG9uIFZfQUNUSU9OUyBhbmQgbG9hZF9ydWxl'
    || 'X2NvbmZpZyBvbiBWX1JVTEVfQ09ORklHLiBTaXggc29sdXRpb25zIGFscmVhZHkgYnVpbGQKICAgIGFuIGFnZW50IHByb2NlZHVyZSB0aGF0IG5vdGhpbmcg'
    || 'Y291bGQgcmVhY2ggLS0gQVNLX0dPVkVSTkFOQ0UsCiAgICBESUFHTk9TRV9GQUlMVVJFLCBFWFBMQUlOX1BSSVZBQ1lfQkxPQ0ssIEFTU0VTU19NSUdSQVRJ'
    || 'T04gYW5kIGZyaWVuZHMgd2VyZQogICAgY2FsbGFibGUgb25seSBmcm9tIGEgd29ya3NoZWV0LiBEZWNsYXJpbmcgb25lIHZpZXcgbm93IHN1cmZhY2VzIGl0'
    || 'LgoKICAgIEEgc29sdXRpb24gd2hvc2UgYWdlbnQgZGVwZW5kcyBvbiBDb3J0ZXggYmVpbmcgYXZhaWxhYmxlIG11c3QgY3JlYXRlIHRoaXMgdmlldwogICAg'
    || 'aW5zaWRlIHRoZSBzYW1lIGF2YWlsYWJpbGl0eSBjaGVjayB0aGF0IGNyZWF0ZXMgdGhlIHByb2NlZHVyZSwgc28gdGhhdCB0aGUgY2hhdAogICAgbmV2ZXIg'
    || 'YXBwZWFycyBmb3IgYSBidWlsZCB3aGVyZSB0aGUgbW9kZWwgd2FzIHVucmVhY2hhYmxlLgogICAgIiIiCiAgICB0cnk6CiAgICAgICAgcm93cyA9IFtyLmFz'
    || 'X2RpY3QoKSBmb3IgciBpbiBzZXNzaW9uLnNxbCgKICAgICAgICAgICAgIlNFTEVDVCBBR0VOVF9MQUJFTCwgUFJPQ19OQU1FLCBQTEFDRUhPTERFUiwgQkxV'
    || 'UkIgIgogICAgICAgICAgICAiRlJPTSAiICsgdGd0ICsgIi5WX0FHRU5UX0NIQVQiKS5jb2xsZWN0KCldCiAgICBleGNlcHQgRXhjZXB0aW9uOgogICAgICAg'
    || 'IHJldHVybiBOb25lCiAgICBpZiBub3Qgcm93czoKICAgICAgICByZXR1cm4gTm9uZQogICAgYSA9IHJvd3NbMF0KICAgICMgVGhlIHByb2NlZHVyZSBOQU1F'
    || 'IGNhbm5vdCBiZSBhIGJpbmQgLS0gaXQgaXMgYW4gaWRlbnRpZmllciwgc28gaXQgaGFzIHRvIGJlCiAgICAjIGNvbmNhdGVuYXRlZCBpbnRvIHRoZSBDQUxM'
    || 'LiBJdCBjb21lcyBmcm9tIGEgdmlldyB0aGlzIGJ1aWxkIGNyZWF0ZWQgcmF0aGVyCiAgICAjIHRoYW4gZnJvbSBhbnl0aGluZyBhIHJlYWRlciB0eXBlZCwg'
    || 'YnV0IGl0IGlzIHZhbGlkYXRlZCBhbnl3YXk6IGEgdmlldyBpcyBhCiAgICAjIHRoaW5nIHNvbWVvbmUgY2FuIGxhdGVyIEFMVEVSLCBhbmQgdGhlIGNvc3Qg'
    || 'b2YgYmVpbmcgd3JvbmcgaGVyZSBpcyBhcmJpdHJhcnkKICAgICMgU1FMIHJ1bm5pbmcgYXMgdGhlIGFwcCBvd25lci4gVGhlIHF1ZXN0aW9uIGl0c2VsZiBJ'
    || 'UyBib3VuZC4KICAgIHByb2MgPSBzdHIoYS5nZXQoIlBST0NfTkFNRSIpIG9yICIiKQogICAgaWYgbm90IHJlLmZ1bGxtYXRjaChyIltBLVphLXpfXVtBLVph'
    || 'LXowLTlfXSoiLCBwcm9jKToKICAgICAgICByZXR1cm4gTm9uZQogICAgYVsiUFJPQ19OQU1FIl0gPSBwcm9jCiAgICByZXR1cm4gYQoKCmRlZiBhZ2VudF9i'
    || 'YXIoc2Vzc2lvbiwgdGd0OiBzdHIpIC0+IE5vbmU6CiAgICAiIiJBc2sgdGhlIHNvbHV0aW9uJ3Mgb3duIGFnZW50IGEgcXVlc3Rpb24sIGluIHRoZSBhcHAu'
    || 'CgogICAgQkVUV0VFTiB0aGUgcnVsZXMgYW5kIHRoZSBhY3Rpb25zLCB3aGljaCBpcyB0aGUgcmVhZGluZyBvcmRlciB0aGUgcGFnZSBhbHJlYWR5CiAgICBh'
    || 'cmd1ZXMgZm9yOiB0aGUgZGFzaGJvYXJkIHNheXMgd2hhdCBpcyB0cnVlLCBjb25maWdfYmFyIHR1bmVzIGhvdyBpdCB3YXMKICAgIGRlY2lkZWQsIHRoaXMg'
    || 'ZXhwbGFpbnMgaXQgaW4gd29yZHMsIGFuZCBwcm9tb3Rpb25fYmFyIGFjdHMgb24gaXQuIEFuIGFuc3dlciBpcwogICAgbW9zdCB1c2VmdWwgaW1tZWRpYXRl'
    || 'bHkgYmVmb3JlIHRoZSBkZWNpc2lvbiBpdCBpbmZvcm1zLgoKICAgIHN0LmNoYXRfaW5wdXQgcmF0aGVyIHRoYW4gYSBSZWFjdCBjaGF0IGJveCBmb3IgdGhl'
    || 'IHVzdWFsIHJlYXNvbiAtLSB0aGUgYnVuZGxlCiAgICBydW5zIGluIGEgc2FuZGJveGVkIGlmcmFtZSB3aXRoIG5vIHNlc3Npb24gYW5kIGNhbm5vdCBjYWxs'
    || 'IGEgcHJvY2VkdXJlLgoKICAgIEhJU1RPUlkgSVMgUEVSIFNFU1NJT04gQU5EIE5PVCBQRVJTSVNURUQuIE5vdGhpbmcgaGVyZSB3cml0ZXMgdG8gdGhlIGFj'
    || 'Y291bnQ6CiAgICBhIHF1ZXN0aW9uIGNvc3RzIGEgc21hbGwgYW1vdW50IG9mIENvcnRleCBjcmVkaXQgYW5kIHJldHVybnMgYSBzdHJpbmcuIFRoYXQgaXMK'
    || 'ICAgIGFsc28gd2h5IHRoaXMgaXMgbm90IHRpZXItZ2F0ZWQgdGhlIHdheSBhbiBhY3Rpb24gaXMgLS0gdGhlcmUgaXMgbm90aGluZyB0bwogICAgdW5kbyAt'
    || 'LSBidXQgdGhlIGNvc3QgaXMgc3RhdGVkIHJhdGhlciB0aGFuIGxlZnQgYXMgYSBzdXJwcmlzZS4KICAgICIiIgogICAgYSA9IGxvYWRfYWdlbnQoc2Vzc2lv'
    || 'biwgdGd0KQogICAgaWYgbm90IGE6CiAgICAgICAgcmV0dXJuCgogICAgc3QuY2FwdGlvbihzdHIoYS5nZXQoIkFHRU5UX0xBQkVMIikgb3IgIkFTSyBUSEUg'
    || 'QUdFTlQiKS51cHBlcigpKQogICAgYmx1cmIgPSBzdHIoYS5nZXQoIkJMVVJCIikgb3IgIiIpCiAgICBpZiBibHVyYjoKICAgICAgICBzdC5jYXB0aW9uKGJs'
    || 'dXJiICsgIiBFYWNoIHF1ZXN0aW9uIGNhbGxzIGEgQ29ydGV4IG1vZGVsLCBzbyBpdCBjb3N0cyBhICIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICJz'
    || 'bWFsbCBhbW91bnQgb2YgY3JlZGl0IGFuZCB0YWtlcyBhIGZldyBzZWNvbmRzLiIpCgogICAgaGlzdF9rZXkgPSAiYWdlbnRfaGlzdCIKICAgIGlmIGhpc3Rf'
    || 'a2V5IG5vdCBpbiBzdC5zZXNzaW9uX3N0YXRlOgogICAgICAgIHN0LnNlc3Npb25fc3RhdGVbaGlzdF9rZXldID0gW10KCiAgICBmb3IgcSwgYW5zIGluIHN0'
    || 'LnNlc3Npb25fc3RhdGVbaGlzdF9rZXldOgogICAgICAgIHdpdGggc3QuY2hhdF9tZXNzYWdlKCJ1c2VyIik6CiAgICAgICAgICAgIHN0LndyaXRlKHEpCiAg'
    || 'ICAgICAgd2l0aCBzdC5jaGF0X21lc3NhZ2UoImFzc2lzdGFudCIpOgogICAgICAgICAgICBzdC53cml0ZShhbnMpCgogICAgYXNrZWQgPSBzdC5jaGF0X2lu'
    || 'cHV0KHN0cihhLmdldCgiUExBQ0VIT0xERVIiKSBvciAiQXNrIGEgcXVlc3Rpb24iKSwKICAgICAgICAgICAgICAgICAgICAgICAgICBrZXk9ImFnZW50X3Ei'
    || 'KQogICAgaWYgYXNrZWQ6CiAgICAgICAgd2l0aCBzdC5zcGlubmVyKCJBc2tpbmcgdGhlIGFnZW50Li4uIik6CiAgICAgICAgICAgIHRyeToKICAgICAgICAg'
    || 'ICAgICAgICMgVGhlIHF1ZXN0aW9uIGlzIEJPVU5ELiBDb25jYXRlbmF0aW5nIGl0IHdvdWxkIGxldCB3aGF0ZXZlcgogICAgICAgICAgICAgICAgIyBzb21l'
    || 'Ym9keSB0eXBlcyBlbmQgdXAgYXMgU1FMIHJ1bm5pbmcgd2l0aCB0aGUgYXBwIG93bmVyJ3MgcmlnaHRzLgogICAgICAgICAgICAgICAgb3V0ID0gc2Vzc2lv'
    || 'bi5zcWwoCiAgICAgICAgICAgICAgICAgICAgIkNBTEwgIiArIHRndCArICIuIiArIGFbIlBST0NfTkFNRSJdICsgIig/KSIsCiAgICAgICAgICAgICAgICAg'
    || 'ICAgcGFyYW1zPVthc2tlZF0pLmNvbGxlY3QoKVswXVswXQogICAgICAgICAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGV4YzoKICAgICAgICAgICAgICAgICMg'
    || 'UmVwb3J0IHRoZSBmYWlsdXJlIGFzIHRoZSBhbnN3ZXIgcmF0aGVyIHRoYW4gc3dhbGxvd2luZyBpdC4gQQogICAgICAgICAgICAgICAgIyBjaGF0IHRoYXQg'
    || 'c2lsZW50bHkgcmV0dXJucyBub3RoaW5nIHJlYWRzIGFzICJ0aGUgYWdlbnQgaGFkIG5vCiAgICAgICAgICAgICAgICAjIG9waW5pb24iLCB3aGljaCBpcyBh'
    || 'IGNsYWltIGFib3V0IHRoZSBxdWVzdGlvbiByYXRoZXIgdGhhbiBhYm91dAogICAgICAgICAgICAgICAgIyB0aGUgY2FsbCB0aGF0IGZhaWxlZC4KICAgICAg'
    || 'ICAgICAgICAgIG91dCA9ICgiVGhlIGFnZW50IGNvdWxkIG5vdCBhbnN3ZXI6ICIgKyB0eXBlKGV4YykuX19uYW1lX18gKyAiOiAiCiAgICAgICAgICAgICAg'
    || 'ICAgICAgICAgKyBzdHIoZXhjKVs6MzAwXSkKICAgICAgICBzdC5zZXNzaW9uX3N0YXRlW2hpc3Rfa2V5XS5hcHBlbmQoKGFza2VkLCBzdHIob3V0KSkpCiAg'
    || 'ICAgICAgc3QucmVydW4oKQogICAgc3QuZGl2aWRlcigpCgoKZGVmIGNvbnRyb2xfdmFsdWVzKHNlc3Npb24sIHRndDogc3RyKSAtPiBkaWN0OgogICAgIiIi'
    || 'UmVuZGVyIHRoZSBkZWNsYXJlZCBjb250cm9scyBhbmQgcmV0dXJuIHtuYW1lOiBjdXJyZW50IHZhbHVlfS4KCiAgICBBQk9WRSBUSEUgREFTSEJPQVJELCB1'
    || 'bmxpa2UgY29uZmlnX2JhciBhbmQgcHJvbW90aW9uX2JhciwgYW5kIHRoZSBkaWZmZXJlbmNlIGlzCiAgICB0aGUgcG9pbnQuIFRoZXNlIGNvbnRyb2xzIGRl'
    || 'Y2lkZSBXSEFUIFRIRSBQQUdFIElTIEFCT1VUIC0tIHdoaWNoIG1ldHJvLCB3aGljaAogICAgd2luZG93LCB3aGljaCBtaW5pbXVtIHNjb3JlIC0tIHNvIHRo'
    || 'ZXkgYmVsb25nIHdoZXJlIHlvdSB3b3VsZCBsb29rIGJlZm9yZQogICAgcmVhZGluZy4gY29uZmlnX2JhciB0dW5lcyB0aGUgcnVsZXMgYmVoaW5kIHRoZSBu'
    || 'dW1iZXJzIGFuZCBwcm9tb3Rpb25fYmFyIGFjdHMgb24KICAgIHRoZW0sIHdoaWNoIGlzIHdoeSBib3RoIG9mIHRob3NlIHNpdCB1bmRlcm5lYXRoLgoKICAg'
    || 'IFdpZGdldHMsIG5vdCBSZWFjdCwgZm9yIHRoZSBzYW1lIHBoeXNpY2FsIHJlYXNvbiBldmVyeXRoaW5nIGVsc2UgaGVyZSBpczogdGhlCiAgICBidW5kbGUg'
    || 'cnVucyBpbiBhIHNhbmRib3hlZCBpZnJhbWUgd2l0aCBubyBzZXNzaW9uLCBzbyBhIFJlYWN0IHNlbGVjdGJveCBjYW5ub3QKICAgIHJlLXF1ZXJ5LiBUaGlz'
    || 'IGlzIHdoZXJlIHRoZSBjaG9vc2luZyBoYXBwZW5zOyB0aGUgcGFnZSBiZWxvdyByZS1yZW5kZXJzIGZyb20gYQogICAgcGF5bG9hZCB0aGUgaG9zdCBmZXRj'
    || 'aGVzIGFnYWluIG9uIHRoZSByZXN1bHRpbmcgcmVydW4uCgogICAgU29sdXRpb25zIHRoYXQgZGVjbGFyZSBubyBjb250cm9scyBkcmF3IE5PVEhJTkcgLS0g'
    || 'bm8gaGVhZGVyLCBubyBleHBhbmRlciwgbm8KICAgIGVtcHR5IHJvdy4gU2FtZSBhcmd1bWVudCBhcyBsb2FkX3J1bGVfY29uZmlnIGdhdGluZyBvbiBWX1JV'
    || 'TEVfQ09ORklHOiBhIHNvbHV0aW9uCiAgICB0aGF0IG5ldmVyIG9wdGVkIGluIG11c3Qgbm90IGdyb3cgYSBjb250cm9sIHN1cmZhY2UgYnkgYWNjaWRlbnQu'
    || 'CgogICAgQSBmYWlsZWQgb3B0aW9ucyBxdWVyeSBjb3N0cyB0aGF0IE9ORSBjb250cm9sIGl0cyBsaXN0IGFuZCBub3RoaW5nIGVsc2UsIGFuZCBpdAogICAg'
    || 'c2F5cyBzby4gRmFsbGluZyBiYWNrIHRvIGEgc2lsZW50IGVtcHR5IHNlbGVjdGJveCB3b3VsZCByZWFkIGFzICJ0aGVyZSBhcmUgbm8KICAgIG1ldHJvcyIs'
    || 'IGEgY2xhaW0gYWJvdXQgdGhlIGN1c3RvbWVyJ3MgZGF0YSByYXRoZXIgdGhhbiBhYm91dCBvdXIgcXVlcnkuCiAgICAiIiIKICAgIGlmIG5vdCBDT05UUk9M'
    || 'UzoKICAgICAgICByZXR1cm4ge30KICAgIHBhcmFtcyA9IHt9CiAgICBjb2xzID0gc3QuY29sdW1ucyhtaW4obGVuKENPTlRST0xTKSwgNCkpCiAgICBmb3Ig'
    || 'aSwgc3BlYyBpbiBlbnVtZXJhdGUoQ09OVFJPTFMpOgogICAgICAgIGtleSA9IHN0cihzcGVjLmdldCgia2V5Iikgb3IgIiIpCiAgICAgICAgaWYgbm90IGtl'
    || 'eToKICAgICAgICAgICAgY29udGludWUKICAgICAgICBsYWJlbCA9IHN0cihzcGVjLmdldCgibGFiZWwiKSBvciBrZXkpCiAgICAgICAga2luZCA9IHN0cihz'
    || 'cGVjLmdldCgia2luZCIpIG9yICJ0ZXh0IikubG93ZXIoKQogICAgICAgIGRlZmF1bHQgPSBzcGVjLmdldCgiZGVmYXVsdCIpCiAgICAgICAgaGVscF90eHQg'
    || 'PSBzcGVjLmdldCgiaGVscCIpIG9yIE5vbmUKICAgICAgICB3a2V5ID0gImN0bF8iICsga2V5CiAgICAgICAgd2l0aCBjb2xzW2kgJSBsZW4oY29scyldOgog'
    || 'ICAgICAgICAgICBpZiBraW5kID09ICJzZWxlY3QiOgogICAgICAgICAgICAgICAgb3B0aW9ucyA9IHNwZWMuZ2V0KCJvcHRpb25zIikKICAgICAgICAgICAg'
    || 'ICAgIGlmIG5vdCBvcHRpb25zIGFuZCBzcGVjLmdldCgib3B0aW9uc19zcWwiKToKICAgICAgICAgICAgICAgICAgICB0cnk6CiAgICAgICAgICAgICAgICAg'
    || 'ICAgICAgIG9wdGlvbnMgPSBbCiAgICAgICAgICAgICAgICAgICAgICAgICAgICByWzBdIGZvciByIGluIHNlc3Npb24uc3FsKAogICAgICAgICAgICAgICAg'
    || 'ICAgICAgICAgICAgICAgIHN0cihzcGVjWyJvcHRpb25zX3NxbCJdKS5yZXBsYWNlKCJ7dGd0fSIsIHRndCkKICAgICAgICAgICAgICAgICAgICAgICAgICAg'
    || 'ICkubGltaXQoMTAwMCkuY29sbGVjdCgpXQogICAgICAgICAgICAgICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZXhjOgogICAgICAgICAgICAgICAgICAg'
    || 'ICAgICBzdC5jYXB0aW9uKGxhYmVsICsgIiBcdTAwYjcgY291bGQgbm90IGxvYWQgY2hvaWNlczogIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg'
    || 'ICAgICsgdHlwZShleGMpLl9fbmFtZV9fKQogICAgICAgICAgICAgICAgICAgICAgICBvcHRpb25zID0gW10KICAgICAgICAgICAgICAgIG9wdGlvbnMgPSBb'
    || 'byBmb3IgbyBpbiAob3B0aW9ucyBvciBbXSkgaWYgbyBpcyBub3QgTm9uZV0KICAgICAgICAgICAgICAgIGlmIG5vdCBvcHRpb25zOgogICAgICAgICAgICAg'
    || 'ICAgICAgICMgTm90aGluZyB0byBjaG9vc2UgZnJvbSBpcyBub3QgdGhlIHNhbWUgYXMgYW4gZW1wdHkgY2hvaWNlLgogICAgICAgICAgICAgICAgICAgICMg'
    || 'QmluZCB0aGUgZGVmYXVsdCBzbyB0aGUgcGFuZWwgc3RpbGwgcnVucyBhbmQgc3RpbGwgc2F5cyB3aGF0CiAgICAgICAgICAgICAgICAgICAgIyBpdCByYW4g'
    || 'd2l0aC4KICAgICAgICAgICAgICAgICAgICBwYXJhbXNba2V5XSA9IGRlZmF1bHQKICAgICAgICAgICAgICAgICAgICBzdC5jYXB0aW9uKGxhYmVsICsgIiBc'
    || 'dTAwYjcgbm8gY2hvaWNlcyBhdmFpbGFibGUiKQogICAgICAgICAgICAgICAgICAgIGNvbnRpbnVlCiAgICAgICAgICAgICAgICBpZHggPSBvcHRpb25zLmlu'
    || 'ZGV4KGRlZmF1bHQpIGlmIGRlZmF1bHQgaW4gb3B0aW9ucyBlbHNlIDAKICAgICAgICAgICAgICAgIHBhcmFtc1trZXldID0gc3Quc2VsZWN0Ym94KGxhYmVs'
    || 'LCBvcHRpb25zLCBpbmRleD1pZHgsIGtleT13a2V5LAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgaGVscD1oZWxwX3R4dCkK'
    || 'ICAgICAgICAgICAgZWxpZiBraW5kID09ICJzbGlkZXIiOgogICAgICAgICAgICAgICAgbG8gPSBzcGVjLmdldCgibWluIiwgMCkKICAgICAgICAgICAgICAg'
    || 'IGhpID0gc3BlYy5nZXQoIm1heCIsIDEwMCkKICAgICAgICAgICAgICAgIHBhcmFtc1trZXldID0gc3Quc2xpZGVyKAogICAgICAgICAgICAgICAgICAgIGxh'
    || 'YmVsLCBtaW5fdmFsdWU9bG8sIG1heF92YWx1ZT1oaSwKICAgICAgICAgICAgICAgICAgICB2YWx1ZT1kZWZhdWx0IGlmIGRlZmF1bHQgaXMgbm90IE5vbmUg'
    || 'ZWxzZSBsbywKICAgICAgICAgICAgICAgICAgICBzdGVwPXNwZWMuZ2V0KCJzdGVwIiwgMSksIGtleT13a2V5LCBoZWxwPWhlbHBfdHh0KQogICAgICAgICAg'
    || 'ICBlbGlmIGtpbmQgPT0gIm51bWJlciI6CiAgICAgICAgICAgICAgICBwYXJhbXNba2V5XSA9IHN0Lm51bWJlcl9pbnB1dCgKICAgICAgICAgICAgICAgICAg'
    || 'ICBsYWJlbCwgdmFsdWU9ZGVmYXVsdCBpZiBkZWZhdWx0IGlzIG5vdCBOb25lIGVsc2UgMCwKICAgICAgICAgICAgICAgICAgICBtaW5fdmFsdWU9c3BlYy5n'
    || 'ZXQoIm1pbiIpLCBtYXhfdmFsdWU9c3BlYy5nZXQoIm1heCIpLAogICAgICAgICAgICAgICAgICAgIHN0ZXA9c3BlYy5nZXQoInN0ZXAiLCAxKSwga2V5PXdr'
    || 'ZXksIGhlbHA9aGVscF90eHQpCiAgICAgICAgICAgIGVsc2U6CiAgICAgICAgICAgICAgICBwYXJhbXNba2V5XSA9IHN0LnRleHRfaW5wdXQoCiAgICAgICAg'
    || 'ICAgICAgICAgICAgbGFiZWwsIHZhbHVlPSIiIGlmIGRlZmF1bHQgaXMgTm9uZSBlbHNlIHN0cihkZWZhdWx0KSwKICAgICAgICAgICAgICAgICAgICBrZXk9'
    || 'd2tleSwgaGVscD1oZWxwX3R4dCkKICAgIHJldHVybiBwYXJhbXMKCgpkZWYgbWFpbigpIC0+IE5vbmU6CiAgICB0cnk6CiAgICAgICAgc2Vzc2lvbiA9IGdl'
    || 'dF9hY3RpdmVfc2Vzc2lvbigpCiAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGV4YzoKICAgICAgICAjIE5vIHNlc3Npb24gbWVhbnMgdGhlIGFwcCBjYW5ub3Qg'
    || 'cXVlcnkgYW55dGhpbmcuIFNheSB0aGF0IHBsYWlubHkKICAgICAgICAjIGluc3RlYWQgb2YgcmVuZGVyaW5nIGVtcHR5IHBhbmVscyB0aGF0IGxvb2sgbGlr'
    || 'ZSByZWFsIHplcm9lcy4KICAgICAgICBjb21wb25lbnRzLmh0bWwoYnVpbGRfaHRtbCh7ImNvbnRleHQiOiB7fSwgInBhbmVscyI6IHt9LAogICAgICAgICAg'
    || 'ICAgICAgICAgICAgICAgICAgICAgICAgICAiZmF0YWwiOiAiTm8gYWN0aXZlIFNub3dmbGFrZSBzZXNzaW9uOiAiICsgc3RyKGV4Yyl9KSwKICAgICAgICAg'
    || 'ICAgICAgICAgICAgICAgaGVpZ2h0PTQwMCwgc2Nyb2xsaW5nPUZhbHNlKQogICAgICAgIHJldHVybgoKICAgIHRndCA9IHRhcmdldF9zY2hlbWEoc2Vzc2lv'
    || 'bikKICAgIG5hdmlnYXRpb24gPSBhcHBfbmF2aWdhdGlvbihzZXNzaW9uLCB0Z3QpCiAgICAjIEJFRk9SRSBydW5fcGFuZWxzLCBiZWNhdXNlIHRoZWlyIHZh'
    || 'bHVlcyBhcmUgd2hhdCB0aGUgcGFuZWxzIGFyZSBmaWx0ZXJlZCBieS4KICAgIHBhcmFtcyA9IGNvbnRyb2xfdmFsdWVzKHNlc3Npb24sIHRndCkKICAgIHBh'
    || 'bmVscyA9IHJ1bl9wYW5lbHMoc2Vzc2lvbiwgdGd0LCBwYXJhbXMpCiAgICBjdXN0b21pemF0aW9uLCBjdXN0b21fcGFuZWxzLCBjdXN0b21pemF0aW9uX2Vy'
    || 'cm9yID0gbG9hZF9jdXN0b21pemF0aW9uKHNlc3Npb24sIHRndCkKICAgIHBhbmVscy51cGRhdGUoY3VzdG9tX3BhbmVscykKICAgICMgVGhlIHNoZWxsJ3Mg'
    || 'TU9ERSBiYW5uZXIgYW5kIGJ1aWxkIHByb3ZlbmFuY2UgY29tZSBmcm9tIHRoZSBgY29udGV4dGAgcGFuZWwuCiAgICAjIElmIGl0IGZhaWxlZCwgc2F5IHNv'
    || 'IHRocm91Z2ggdGhlIG5vcm1hbCBjb250ZXh0IGZpZWxkcyByYXRoZXIgdGhhbiBsZWF2aW5nCiAgICAjIE1PREUgYmxhbmsgLS0gYSBwYWdlIHdpdGggbm8g'
    || 'bW9kZSBiYWRnZSBpcyBhIHBhZ2UgdGhhdCBjb3VsZCBiZSBzaG93aW5nCiAgICAjIHNlZWRlZCBudW1iZXJzIHdpdGggbm90aGluZyB0byBzYXkgc28uCiAg'
    || 'ICBjdHggPSB7fQogICAgZ290ID0gcGFuZWxzLmdldCgiY29udGV4dCIsIHt9KQogICAgaWYgInJvd3MiIGluIGdvdCBhbmQgZ290WyJyb3dzIl06CiAgICAg'
    || 'ICAgY3R4ID0gZ290WyJyb3dzIl1bMF0KICAgIGVsc2U6CiAgICAgICAgY3R4ID0geyJTT0xVVElPTiI6IFNPTFVUSU9OX05BTUUsICJCVUlMVF9JTiI6IHRn'
    || 'dCwgIk1PREUiOiAiVU5LTk9XTiJ9CgogICAgY29tcG9uZW50cy5odG1sKGJ1aWxkX2h0bWwoeyJjb250ZXh0IjogY3R4LCAicGFuZWxzIjogcGFuZWxzLAog'
    || 'ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJjdXN0b21pemF0aW9uIjogY3VzdG9taXphdGlvbiwKICAgICAgICAgICAgICAgICAgICAgICAgICAg'
    || 'ICAgICAiY3VzdG9taXphdGlvbl9lcnJvciI6IGN1c3RvbWl6YXRpb25fZXJyb3IsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIm5hdmlnYXRp'
    || 'b24iOiBuYXZpZ2F0aW9ufSksCiAgICAgICAgICAgICAgICAgICAgaGVpZ2h0PTkwMCwgc2Nyb2xsaW5nPVRydWUpCgogICAgaWYgc3QuYnV0dG9uKCJSZWZy'
    || 'ZXNoIGRhdGEiLCBrZXk9InJlZnJlc2hfcGFuZWxfZGF0YSIpOgogICAgICAgIGludmFsaWRhdGVfcGFuZWxfY2FjaGUoKQogICAgICAgIGlmIGhhc2F0dHIo'
    || 'c3QsICJyZXJ1biIpOgogICAgICAgICAgICBzdC5yZXJ1bigpCiAgICAgICAgZWxzZToKICAgICAgICAgICAgc3QuZXhwZXJpbWVudGFsX3JlcnVuKCkKCiAg'
    || 'ICAjIEFGVEVSIHRoZSBkYXNoYm9hcmQgYW5kIEJFRk9SRSB0aGUgcHJvbW90aW9uIGJhci4gVGhlIG9yZGVyIGlzIGFuIGFyZ3VtZW50OgogICAgIyB0aGUg'
    || 'cnVsZXMgZXhwbGFpbiB0aGUgbnVtYmVycyBpbW1lZGlhdGVseSBhYm92ZSB0aGVtLCBhbmQgdGhlIHByb21vdGlvbiBiYXIKICAgICMgaXMgdGhlICJ3aGF0'
    || 'IGRvIEkgZG8gYWJvdXQgdGhpcyIgdGhhdCBzaG91bGQgY29tZSBsYXN0LiBBIHJlYWRlciB3aG8gY2hhbmdlcwogICAgIyBhIHRocmVzaG9sZCBoZXJlIGlz'
    || 'IHN0aWxsIHJlYWRpbmcgdGhlIGRhc2hib2FyZDsgYSByZWFkZXIgYXQgdGhlIHByb21vdGlvbgogICAgIyBiYXIgaGFzIGZpbmlzaGVkLiBTb2x1dGlvbnMg'
    || 'd2l0aG91dCBWX1JVTEVfQ09ORklHIGRyYXcgbm90aGluZyBhdCBhbGwuCiAgICBjb25maWdfYmFyKHNlc3Npb24sIHRndCkKCiAgICAjIEJFVFdFRU4gdGhl'
    || 'IHJ1bGVzIGFuZCB0aGUgYWN0aW9ucy4gVGhlIGFnZW50IGV4cGxhaW5zIHdoYXQgdGhlIG51bWJlcnMgbWVhbgogICAgIyBhbmQgaXMgbW9zdCB1c2VmdWwg'
    || 'aW1tZWRpYXRlbHkgYmVmb3JlIHRoZSBkZWNpc2lvbiBpdCBpbmZvcm1zOyBzb2x1dGlvbnMgdGhhdAogICAgIyBkZWNsYXJlIG5vIFZfQUdFTlRfQ0hBVCBk'
    || 'cmF3IG5vdGhpbmcgYXQgYWxsLgogICAgYWdlbnRfYmFyKHNlc3Npb24sIHRndCkKCiAgICAjIEFGVEVSIHRoZSBkYXNoYm9hcmQsIG5vdCBiZWZvcmUuIFRo'
    || 'ZSBwcm9tb3Rpb24gYmFyIGlzIHRoZSBhbnN3ZXIgdG8gIndoYXQgZG8KICAgICMgSSBkbyBhYm91dCB0aGlzPyIsIGFuZCB0aGF0IHF1ZXN0aW9uIG9ubHkg'
    || 'bWFrZXMgc2Vuc2Ugb25jZSB0aGUgbnVtYmVycyBhYm92ZQogICAgIyBpdCBoYXZlIGJlZW4gcmVhZC4gUHV0dGluZyBpdCBvbiB0b3Agd291bGQgYWxzbyBw'
    || 'dXNoIHRoZSB3aG9sZSBkYXNoYm9hcmQKICAgICMgYmVsb3cgdGhlIGZvbGQgb24gYSBsYXB0b3AuCiAgICBwcm9tb3Rpb25fYmFyKHNlc3Npb24sIHRndCkK'
    || 'CgptYWluKCkK';

  stmts := ARRAY_APPEND(:stmts,
    'COPY INTO @' || :tgt || '.APP_STAGE/streamlit_app.py '
 || 'FROM (SELECT BASE64_DECODE_STRING(''' || :py_b64 || ''')) '
 || 'FILE_FORMAT = (TYPE = CSV COMPRESSION = NONE '
 || 'FIELD_DELIMITER = NONE RECORD_DELIMITER = NONE FIELD_OPTIONALLY_ENCLOSED_BY = NONE '
 || 'ESCAPE_UNENCLOSED_FIELD = NONE) OVERWRITE = TRUE SINGLE = TRUE');

  stmts := ARRAY_APPEND(:stmts,
    'COPY INTO @' || :tgt || '.APP_STAGE/environment.yml '
 || 'FROM (SELECT BASE64_DECODE_STRING(''bmFtZTogb25lc2hvdApjaGFubmVsczoKICAtIHNub3dmbGFrZQpkZXBlbmRlbmNpZXM6CiAgLSBzdHJlYW1saXQ9MS41Mi4yCiAgLSBzbm93Zmxha2Utc25vd3BhcmstcHl0aG9uCg=='')) '
 || 'FILE_FORMAT = (TYPE = CSV COMPRESSION = NONE FIELD_DELIMITER = NONE '
 || 'RECORD_DELIMITER = NONE FIELD_OPTIONALLY_ENCLOSED_BY = NONE '
 || 'ESCAPE_UNENCLOSED_FIELD = NONE) OVERWRITE = TRUE SINGLE = TRUE');

  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE STREAMLIT ' || :tgt || '. '
 || 'ROOT_LOCATION = ''@' || :tgt || '.APP_STAGE'' MAIN_FILE = ''streamlit_app.py'' '
 || 'QUERY_WAREHOUSE = ' || :wh || ' COMMENT = ''Retail Merchant Agent — generated from account discovery''');

  -- The app runs on the app warehouse whenever someone opens it. Auto-suspend
  -- makes this small, but it is not zero and the operator should see it.
  cost_day    := :cost_day + 0.10;
  cost_detail := ARRAY_APPEND(:cost_detail,
    'Streamlit app on ' || :wh || ' ~0.10 credits/day. ASSUMES an XS warehouse, '
 || 'auto-suspend 60s, and roughly 20 page views/day. Heavier use scales this linearly.');
  dials       := ARRAY_APPEND(:dials,
    'Point MERCHANT_APP_WAREHOUSE at an XS warehouse to cut app cost');
  -- Only claim the app exists when this snippet is present. The template used to
  -- print "OPEN THE APP" unconditionally, which told operators to open a
  -- Streamlit object that was never created for solutions built without a UI.
  -- Two independent reviewers caught it; it now lives with the code that
  -- actually creates the app.
  notes       := ARRAY_APPEND(:notes,
    'OPEN THE APP after building: Snowsight > Projects > Streamlit > ');
  --          bundle embedded as base64, plus COPY INTO and CREATE STREAMLIT

  -- ── DETERMINISTIC GATES ───────────────────────────────────────────────────
  -- These evaluate FIRST and they work with Cortex face down. The review that
  -- follows is judgement on top of them, never a substitute for them: a rule that
  -- only holds when an LLM is reachable is not a rule.
  LET hard_block STRING := '';
  IF (:prof_status = 'AVAILABLE') THEN
    LET n_dead INT := 0;
    SELECT COUNT_IF(v.value:verdict::STRING IN ('ALL_NULL', 'EMPTY_TABLE'))
      INTO :n_dead FROM TABLE(FLATTEN(input => :unusable)) v;

    -- A WHOLE NAMED TABLE that is unreadable, absent or empty. Counted per TABLE
    -- rather than per column, and that distinction is the fix for a defect this
    -- suite caught: the only refusal rule was "no usable column ANYWHERE", so
    -- pointing C360_MEMBERS_TABLE at an unreadable table while orders, events and
    -- subscriptions stayed healthy left prof_usable > 0 and the build went ahead.
    -- It then created a schema, failed on CREATE VIEW V_IDENTITY_MAP with "does not
    -- exist or not authorized", and left a HALF-BUILT schema behind -- after the
    -- profile output had already told the operator "Nothing was created".
    --
    -- Averaging a broken spine against three healthy satellites is the wrong
    -- arithmetic. An operator does not name a table they do not need, so any named
    -- table that yields nothing is a refusal on its own.
    LET dead_tables ARRAY := ARRAY_CONSTRUCT();
    SELECT COALESCE(ARRAY_AGG(t || ' (' || why || ')'), ARRAY_CONSTRUCT())
      INTO :dead_tables
      FROM (SELECT v.value:target_table::STRING AS t,
                   ANY_VALUE(v.value:verdict::STRING) AS why,
                    COUNT_IF(v.value:verdict::STRING
                             IN ('NO_ACCESS', 'MISSING')) AS bad,
                   COUNT(*) AS n
              FROM TABLE(FLATTEN(input => :prof:profile)) v
             GROUP BY 1 HAVING bad = n);

    IF (ARRAY_SIZE(:dead_tables) > 0) THEN
      hard_block := 'A source table you named yields nothing usable: '
                 || ARRAY_TO_STRING(:dead_tables, '; ') || '. Every column probed on '
                 || 'it came back unreadable, absent or empty, so views built over it '
                 || 'would either fail to create or return nothing. Nothing has been '
                 || 'created. Fix the table name, the grant, or the load that should '
                 || 'have populated it, then re-run. This is a deterministic refusal '
                 || 'and it stands whether or not the model review runs.';
    ELSEIF (:prof_usable = 0 AND ARRAY_SIZE(:unusable) > 0 AND :n_dead < ARRAY_SIZE(:unusable)) THEN
      hard_block := 'The profile found NO usable column among the ' || ARRAY_SIZE(:unusable)
                 || ' it checked. There is nothing here to build on, so building '
                 || 'would produce a dashboard of numbers about no data. This is a '
                 || 'deterministic refusal from ' || 'MERCHANT' || '_MIN_FILL_PCT = ' || :min_fill
                 || ', not a judgement call, and it stands whether or not the model '
                 || 'review runs.';
    ELSEIF (:n_dead > 0) THEN
      notes := ARRAY_APPEND(:notes,
        'PROFILE: ' || :n_dead || ' column(s) are entirely empty or sit on an empty '
     || 'table, and ' || ARRAY_SIZE(:unusable) || ' in total fell below the '
     || :min_fill || '% floor. Anything depending on them is downgraded and named '
     || 'below. The plan continues on what is left.');
    END IF;
  ELSE
    notes := ARRAY_APPEND(:notes,
      'PROFILE ' || :prof_status || ': column populated-ness was NOT checked, so '
   || 'nothing in this plan knows whether the columns it reads contain anything. '
   || 'This is the failure mode that produces a clean-looking dashboard over blank '
   || 'columns. Set MERCHANT_PROFILE = TRUE and re-run to close it.');
  END IF;

  -- ── RUNTIME REVIEW ────────────────────────────────────────────────────────
  -- A second, separate model call that reviews the FINISHED plan against what was
  -- actually found. It exists because nobody on our side will ever see this
  -- account: the review that used to happen in a person's head between discovery
  -- and build has to happen inside the file or not at all.
  --
  -- It is given the facts and NOT the adapter's reasoning. Shown why a choice was
  -- made, a reviewer rationalises the choice instead of testing it -- so the
  -- adaptation prompt and its reply are deliberately absent from this input.
  --
  -- Same three rules as adaptation, no exceptions: JSON decisions never SQL, every
  -- named object validated against discovery or discarded, and a failure falls
  -- back and says so rather than blocking.
  LET review_verdict    STRING := 'NOT_RUN';
  LET review_findings   ARRAY  := ARRAY_CONSTRUCT();
  LET review_raw        STRING := '';
  LET review_prompt     STRING := '';
  LET review_status     STRING := 'SKIPPED';
  LET review_overridden BOOLEAN := FALSE;
  LET override_asked    BOOLEAN := FALSE;
  BEGIN
    override_asked := (SELECT TRY_CAST($MERCHANT_OVERRIDE_REVIEW::VARCHAR AS BOOLEAN));
  EXCEPTION WHEN OTHER THEN override_asked := FALSE;
  END;

  review_prompt :=
       'Review this Snowflake deployment plan. You are the last check before it '
    || 'runs unattended in a customer account that nobody from the vendor can see. '
    || CHR(10) || CHR(10)
    || 'Return ONE JSON object, no prose, no code fence:' || CHR(10)
    || '{"verdict":"PROCEED|CAVEAT|DO_NOT_PROCEED","findings":[' || CHR(10)
    || ' {"severity":"HIGH|MEDIUM|LOW","object":"<a name from the input, or null>",'
    || '"finding":"<what is wrong>","evidence":"<the specific fact from the input '
    || 'that shows it>"}]}' || CHR(10) || CHR(10)
    || 'Rules for your verdict:' || CHR(10)
    || '- PROCEED with findings:[] when the plan is sound. A reviewer who always '
    || 'finds three problems is noise and will be ignored. Say nothing when there '
    || 'is nothing to say.' || CHR(10)
    || '- CAVEAT when it should run but the reader must know something first.' || CHR(10)
    || '- DO_NOT_PROCEED only when running it would produce misleading output or '
    || 'damage. This CLOSES THE GATE, so use it when you mean it.' || CHR(10)
    -- Calibration, and it is here because the first live run got this wrong: the
    -- model returned DO_NOT_PROCEED on a healthy plan whose only blemish was that
    -- the optional profile had not been run, then returned PROCEED on the identical
    -- plan seconds later. An unrun profile is a KNOWN GAP that the file already
    -- reports in three other places; it is a caveat, not a reason to refuse. Naming
    -- the specific cases keeps the strong verdict for things that deserve it.
    || '- These are CAVEAT, never DO_NOT_PROCEED on their own: the profile was not '
    || 'run; a cost estimate you consider optimistic; a solution that reads business '
    || 'data and says so; an absent capability the plan already reports as absent; '
    || 'missing operational furniture at a tier that does not claim to install it; '
    || 'all source tables are present but contain zero rows when the plan already '
    || 'acknowledges the empty condition in its notes and adjusts its cost '
    || 'projection accordingly — this is graceful degradation, not a defect.' || CHR(10)
    || '- Reserve DO_NOT_PROCEED for: building a metric on a column the profile '
    || 'reported ALL_NULL or on an EMPTY_TABLE; a grain that cannot support the '
    || 'metric being claimed; a source that is evidently a backup, test or staging '
    || 'copy being presented as production; or a statement that would modify data '
    || 'outside the target schema without saying so.' || CHR(10)
    || '- Do not infer a problem from something the input does not mention. Absence '
    || 'of a fact is not evidence of a defect.' || CHR(10)
    || '- Every finding must cite a specific fact from the input in "evidence". A '
    || 'finding you cannot ground in the input is one you should not report.' || CHR(10)
    || '- Judge what a threshold cannot: a table that is plainly a backup or test '
    || 'copy despite its name, a grain that does not support the metric being '
    || 'claimed, a column that is populated but semantically wrong for the use '
    || 'case, a value model resting on a near-empty base.' || CHR(10) || CHR(10)
    || 'SOLUTION: Retail Merchant Agent' || CHR(10)
    || 'TIER: ' || :tier || CHR(10)
    || 'TARGET: ' || :tgt || CHR(10)
    || 'DISCOVERY (probe -> availability): ' || LEFT(TO_JSON(:sig), 3000) || CHR(10)
    -- `cnt` is NOT row counts. Each probe decides what it counts, and most count
    -- objects rather than rows -- C360's candidate probes put ARRAY_SIZE(candidates)
    -- here, so "10" means ten candidate TABLES. Labelling it "row counts" made the
    -- reviewer state, as a HIGH finding with evidence attached, that "every
    -- discovered source holds 10 rows" on an account where the sources held
    -- hundreds of thousands. A fabricated data-scale claim in the one place whose
    -- job is to catch fabricated claims is worse than no claim, so the label says
    -- what the number actually is and the reviewer is told not to infer volume.
    || 'DISCOVERY (probe -> counts; UNITS ARE PROBE-DEFINED and are usually object '
    || 'or candidate counts, NOT row counts -- do not infer data volume or table '
    || 'size from these numbers): ' || LEFT(TO_JSON(:cnt), 2000) || CHR(10)
    || 'PROFILE STATUS: ' || :prof_status || CHR(10)
    || 'PROFILE USABLE COLUMNS: ' || :prof_usable || CHR(10)
    || 'PROFILE PROBLEMS: ' || LEFT(TO_JSON(:unusable), 4000) || CHR(10)
    || 'COST ESTIMATE: ' || :cost_day || ' credits/day steady state, '
    || :cost_once || ' credits one-time (arithmetic, not measured)' || CHR(10)
    || 'STATEMENT COUNT: ' || ARRAY_SIZE(:stmts) || CHR(10)
    || 'STATEMENTS: ' || LEFT(TO_JSON(:stmts), 12000);

  IF (:adapt_status = 'SKIPPED' AND :adapt_prompt = '') THEN
    review_status := 'NO MODEL CONFIGURED';
  END IF;

  BEGIN
    review_raw := (SELECT SNOWFLAKE.CORTEX.AI_COMPLETE(:adapt_model, :review_prompt));
    LET rv VARIANT := TRY_PARSE_JSON(REGEXP_REPLACE(:review_raw, '^[^{]*|[^}]*$', ''));
    IF (:rv IS NULL) THEN
      review_status  := 'UNPARSEABLE';
      review_verdict := 'NOT_RUN';
    ELSE
      LET v STRING := UPPER(COALESCE(:rv:verdict::STRING, ''));
      IF (:v IN ('PROCEED', 'CAVEAT', 'DO_NOT_PROCEED')) THEN
        review_verdict := :v;
        review_status  := 'APPLIED';
        review_findings := COALESCE(:rv:findings::ARRAY, ARRAY_CONSTRUCT());
      ELSE
        review_status  := 'UNRECOGNISED VERDICT ' || LEFT(:v, 40);
        review_verdict := 'NOT_RUN';
      END IF;
    END IF;
  EXCEPTION WHEN OTHER THEN
    review_status  := 'UNAVAILABLE (' || SQLERRM || ')';
    review_verdict := 'NOT_RUN';
  END;

  -- NOT_RUN is its own state, and that is what lets two rules hold at once: an
  -- LLM outage must never block a build, and nothing may proceed as though a
  -- review that did not run had passed. NOT_RUN does neither.
  notes := ARRAY_APPEND(:notes,
    'RUNTIME REVIEW (' || :adapt_model || '): ' || :review_verdict
 || ' [' || :review_status || ']. '
 || CASE :review_verdict
      WHEN 'PROCEED' THEN 'The model reviewed the finished plan against what '
        || 'discovery and the profile found and raised nothing.'
      WHEN 'CAVEAT' THEN 'The plan can run. Read the findings first.'
      WHEN 'DO_NOT_PROCEED' THEN 'THE GATE IS CLOSED BY THIS VERDICT, even if '
        || 'MERCHANT_APPROVE is TRUE. To build anyway set MERCHANT_OVERRIDE_REVIEW = TRUE; '
        || 'that is your call to make and it is recorded in the output, in the '
        || 'packet and in REVIEW_LOG.'
      ELSE 'The review did NOT run, so it is not a pass. The deterministic gates '
        || 'above still applied and the build is not blocked by this.'
    END);
  IF (ARRAY_SIZE(:review_findings) > 0) THEN
    LET fi INT := 0;
    WHILE (:fi < ARRAY_SIZE(:review_findings)) DO
      notes := ARRAY_APPEND(:notes,
        '  REVIEW ' || COALESCE(GET(:review_findings, :fi):severity::STRING, '?')
     || ' · ' || COALESCE(GET(:review_findings, :fi):object::STRING, '(plan)')
     || ' — ' || COALESCE(GET(:review_findings, :fi):finding::STRING, '')
     || '  [evidence: ' || COALESCE(GET(:review_findings, :fi):evidence::STRING, 'NONE CITED') || ']');
      fi := :fi + 1;
    END WHILE;
  END IF;

  -- Persisted next to ADAPTATION_LOG, for the same reason: a model judgement
  -- nobody can audit is indistinguishable from the tool inventing one.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE TABLE IF NOT EXISTS ' || :tgt || '.REVIEW_LOG '
 || '(RUN_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(), RUN_ID VARCHAR, MODEL VARCHAR, '
 || 'STATUS VARCHAR, VERDICT VARCHAR, OVERRIDDEN BOOLEAN, FINDINGS VARIANT, '
 || 'PROMPT VARCHAR, RESPONSE VARCHAR, RUN_BY VARCHAR DEFAULT CURRENT_USER())');
  stmts := ARRAY_APPEND(:stmts,
    'INSERT INTO ' || :tgt || '.REVIEW_LOG '
 || '(RUN_ID, MODEL, STATUS, VERDICT, OVERRIDDEN, FINDINGS, PROMPT, RESPONSE) SELECT '
 || '''' || :run_id || ''', ''' || :adapt_model || ''', '
 || '''' || REPLACE(:review_status, '''', '''''') || ''', ''' || :review_verdict || ''', '
 || IFF(:override_asked AND :review_verdict = 'DO_NOT_PROCEED', 'TRUE', 'FALSE') || ', '
 || 'PARSE_JSON(BASE64_DECODE_STRING(''' || BASE64_ENCODE(TO_JSON(:review_findings)) || ''')), '
 || 'BASE64_DECODE_STRING(''' || BASE64_ENCODE(LEFT(:review_prompt, 12000)) || '''), '
 || 'BASE64_DECODE_STRING(''' || BASE64_ENCODE(LEFT(:review_raw, 8000)) || ''')');

  -- ── Budget guard ──────────────────────────────────────────────────────────
  -- A ceiling that only warns is not a ceiling. Refuse to plan, and say what to
  -- turn down, before anyone has the chance to approve it.
  IF (:budget > 0 AND :cost_day > :budget) THEN
    res := (
      SELECT 0 AS step, 'BLOCKED — OVER BUDGET' AS action,
             'Estimated steady state ' || ROUND(:cost_day, 3) || ' credits/day exceeds '
             || 'MERCHANT_BUDGET_CREDITS = ' || :budget || '. Nothing was created.' AS statement
      UNION ALL
      SELECT 1 + INDEX, 'TURN THIS DOWN', VALUE::STRING FROM TABLE(FLATTEN(input => :dials))
      UNION ALL
      SELECT 90 + INDEX, 'COST DETAIL', VALUE::STRING FROM TABLE(FLATTEN(input => :cost_detail))
      ORDER BY step
    );
    RETURN TABLE(res);
  END IF;

  -- ── Gate ──────────────────────────────────────────────────────────────────
  LET approved BOOLEAN := FALSE;
  BEGIN
    approved := (SELECT TRY_CAST($MERCHANT_APPROVE::VARCHAR AS BOOLEAN));
  EXCEPTION WHEN OTHER THEN approved := FALSE;
  END;

  -- Two things can close a gate the operator opened, and they are not the same
  -- kind of thing. The deterministic refusal is arithmetic and cannot be
  -- overridden from the settings block. The review verdict is judgement and CAN
  -- be, because the client owns the decision and the override is the audit trail.
  LET gate_closed_by STRING := '';
  IF (:hard_block <> '') THEN
    approved := FALSE;
    gate_closed_by := 'DETERMINISTIC CHECK';
  ELSEIF (:review_verdict = 'DO_NOT_PROCEED' AND NOT :override_asked) THEN
    approved := FALSE;
    gate_closed_by := 'REVIEW VERDICT';
  ELSEIF (:review_verdict = 'DO_NOT_PROCEED' AND :override_asked) THEN
    review_overridden := TRUE;
    notes := ARRAY_APPEND(:notes,
      'OVERRIDE IN EFFECT: the review returned DO_NOT_PROCEED and '
   || 'MERCHANT_OVERRIDE_REVIEW = TRUE, so the build proceeded anyway. The verdict and '
   || 'this override are both recorded in REVIEW_LOG and in the packet.');
  END IF;

  -- ── The discovery packet ──────────────────────────────────────────────────
  -- The only pre-build artifact that can leave the account, and therefore the only
  -- thing a client can circulate internally to get this approved. It is built from
  -- Block 1 metadata plus AGGREGATE profile statistics; it contains no row values
  -- from any business table, and the gauntlet asserts that against sentinel data.
  --
  -- Returned as ROWS, never written to a table. A gate-closed run creates nothing
  -- and a step of the gauntlet asserts the target schema is absent afterwards, so
  -- persisting the packet would break the guarantee that makes it shareable.
  LET pk_md STRING :=
       '# ' || 'Retail Merchant Agent' || ' — discovery packet' || CHR(10) || CHR(10)
    || '- Account: ' || CURRENT_ACCOUNT() || '  ·  Region: ' || CURRENT_REGION() || CHR(10)
    || '- Target: `' || :tgt || '`  ·  Role: ' || CURRENT_ROLE() || CHR(10)
    || '- Run id: `' || :run_id || '`  ·  Tier: ' || :tier || CHR(10)
    || '- Generated: ' || CURRENT_TIMESTAMP()::STRING || CHR(10)
    || '- Nothing was created. This is the output of a gate-closed run.' || CHR(10) || CHR(10)
    || '## Verdict' || CHR(10) || CHR(10)
    || '**' || IFF(:gate_closed_by <> '', 'WILL NOT BUILD (' || :gate_closed_by || ')',
                   IFF(:approved, 'WILL BUILD', 'GATE CLOSED BY SETTING'))
    || '**  ·  review: **' || :review_verdict || '** (' || :review_status || ')' || CHR(10) || CHR(10)
    || IFF(:hard_block <> '', '> ' || :hard_block || CHR(10) || CHR(10), '')
    || '## Cost' || CHR(10) || CHR(10)
    || '| what | credits | basis |' || CHR(10) || '|---|---|---|' || CHR(10)
    || '| steady state | ' || ROUND(:cost_day, 3) || '/day | PROJECTED — arithmetic |' || CHR(10)
    -- The row the reader circulating this actually needs. Whoever approves spend
    -- approves it monthly; a per-day figure makes them do the multiplication and
    -- they do it wrong. Same arithmetic, 30.4 days.
    || '| left running | ' || ROUND(:cost_day * 30.4, 2) || '/month | PROJECTED — arithmetic |' || CHR(10)
    || '| one-time build | ' || ROUND(:cost_once, 3) || ' | PROJECTED — arithmetic |' || CHR(10)
    || '| measured | — | only a LIMITED or PRODUCTION run produces one |' || CHR(10) || CHR(10)
    || '## What discovery found' || CHR(10) || CHR(10) || '```' || CHR(10)
    || TO_JSON(:sig) || CHR(10) || '```' || CHR(10) || CHR(10)
    || '## Profile' || CHR(10) || CHR(10)
    || 'Status: **' || :prof_status || '**  ·  usable columns: ' || :prof_usable
    || '  ·  problems: ' || ARRAY_SIZE(:unusable) || CHR(10) || CHR(10)
    || IFF(:prof_status = 'AVAILABLE',
           'Aggregates only — null rate, distinct count, row count, type, and '
        || 'min/max for date columns. No example values.' || CHR(10) || CHR(10)
        || '```' || CHR(10) || TO_JSON(:unusable) || CHR(10) || '```' || CHR(10),
           '_Not run. Column populated-ness is unverified._' || CHR(10)) || CHR(10)
    || '## Review findings' || CHR(10) || CHR(10)
    || IFF(ARRAY_SIZE(:review_findings) = 0,
           '_None._' || CHR(10),
           '```' || CHR(10) || TO_JSON(:review_findings) || CHR(10) || '```' || CHR(10))
    || CHR(10) || '## The plan (' || ARRAY_SIZE(:stmts) || ' statements)' || CHR(10) || CHR(10)
    || '```sql' || CHR(10) || LEFT(ARRAY_TO_STRING(:stmts, ';' || CHR(10)), 40000)
    || CHR(10) || '```' || CHR(10) || CHR(10)
    || '## Removing it, if it is built' || CHR(10) || CHR(10)
    || '```sql' || CHR(10) || 'CALL ' || :tgt || '.TEARDOWN();' || CHR(10) || '```' || CHR(10);

  LET pk_json STRING := TO_JSON(OBJECT_CONSTRUCT(
      'solution', 'Retail Merchant Agent', 'run_id', :run_id, 'tier', :tier,
      'account', CURRENT_ACCOUNT(), 'region', CURRENT_REGION(), 'role', CURRENT_ROLE(),
      'target', :tgt, 'generated_at', CURRENT_TIMESTAMP()::STRING,
      'created_anything', FALSE,
      'gate_closed_by', :gate_closed_by,
      'deterministic_block', :hard_block,
      'review', OBJECT_CONSTRUCT('verdict', :review_verdict, 'status', :review_status,
                                 'model', :adapt_model, 'overridden', :review_overridden,
                                 'findings', :review_findings),
      'discovery', OBJECT_CONSTRUCT('availability', :sig, 'row_counts', :cnt,
                                    'window_days', :w),
      'profile', OBJECT_CONSTRUCT('status', :prof_status, 'usable_columns', :prof_usable,
                                  'min_fill_pct', :min_fill, 'problems', :unusable),
      'cost_projected', OBJECT_CONSTRUCT('steady_state_credits_per_day', :cost_day,
                                         'one_time_credits', :cost_once,
                                         'label', 'PROJECTED',
                                         'basis', 'arithmetic from this plan, not measured'),
      'statements', :stmts));

  IF (NOT COALESCE(:approved, FALSE)) THEN
    res := (
      SELECT -1 AS step, 'WHAT THIS GIVES YOU' AS action,
             COALESCE(NULLIF(:headline, ''), 'Retail Merchant Agent') AS statement
      UNION ALL
      SELECT 0, 'TARGET',
             :tgt || '  |  ' || :w || ' day window  |  warehouse ' || :wh
             || '  |  ' || ARRAY_SIZE(:stmts) || ' statements'
      UNION ALL SELECT 1, 'MODE',
             IFF(:mode = 'SAMPLE',
                 'SAMPLE — seeded data. Every page will be labelled SAMPLE DATA.',
                 'DISCOVER — built from this account')
      UNION ALL SELECT 2, 'COST · STEADY STATE (PROJECTED)',
             '~' || ROUND(:cost_day, 3) || ' credits/day (~$' || ROUND(:cost_day * :rate, 2)
             || '/day at $' || :rate || '/credit). ARITHMETIC, not measured — only a '
             || 'LIMITED or PRODUCTION run produces a measured figure.'
      UNION ALL SELECT 3, 'COST · ONE TIME (PROJECTED)',
             '~' || ROUND(:cost_once, 3) || ' credits to build'
      -- A per-day figure is not something anyone can budget against. The question
      -- actually being asked of these scripts is "what does leaving this on cost
      -- us", and that is a monthly number. 30.4 days, so a month means a month
      -- and not four weeks. Derived from the same arithmetic as step 2 and
      -- labelled the same way -- it is the SAME estimate on a useful cadence, not
      -- a second, better one, and it is never added to a measured figure.
      UNION ALL SELECT 3.5, 'COST · PER MONTH IF LEFT RUNNING (PROJECTED)',
             '~' || ROUND(:cost_day * 30.4, 2) || ' credits/month (~$'
             || ROUND(:cost_day * 30.4 * :rate, 2) || '/month at $' || :rate
             || '/credit). Same arithmetic as steady state, on the cadence you '
             || 'get billed on. After a LIMITED or PRODUCTION build, '
             || :tgt || '.V_RUN_RATE_HEADLINE carries the measured version.'
      UNION ALL SELECT 4, 'BUDGET',
             IFF(:budget > 0, 'ceiling ' || :budget || ' credits/day — within it',
                 'no ceiling set (MERCHANT_BUDGET_CREDITS = 0)')
      UNION ALL SELECT 5, 'REVIEW',
             :review_verdict || ' (' || :review_status || ') · '
             || ARRAY_SIZE(:review_findings) || ' finding(s)'
      UNION ALL SELECT 6, 'WHY THE GATE IS CLOSED',
             CASE WHEN :gate_closed_by = 'DETERMINISTIC CHECK' THEN :hard_block
                  WHEN :gate_closed_by = 'REVIEW VERDICT'
                    THEN 'The review returned DO_NOT_PROCEED. Read the findings above. '
                      || 'To build anyway set MERCHANT_OVERRIDE_REVIEW = TRUE.'
                  ELSE 'MERCHANT_APPROVE is FALSE. Nothing was created.' END
      UNION ALL
      SELECT 8 + INDEX, 'READ THIS', VALUE::STRING FROM TABLE(FLATTEN(input => :notes))
      UNION ALL
      SELECT 40 + INDEX, 'COST DETAIL', VALUE::STRING FROM TABLE(FLATTEN(input => :cost_detail))
      UNION ALL
      SELECT 60 + INDEX, 'TURN IT DOWN', VALUE::STRING FROM TABLE(FLATTEN(input => :dials))
      UNION ALL SELECT 80, 'TO REMOVE EVERYTHING', 'After build: CALL ' || :tgt || '.TEARDOWN();'
      -- The packet. Two rows, each one value, copied straight out of the worksheet.
      -- Deliberately after the human-readable summary and before the raw statement
      -- list, which is where a reader looking for something to circulate will land.
      UNION ALL SELECT 90, 'PACKET · MARKDOWN (copy this to share)', :pk_md
      UNION ALL SELECT 91, 'PACKET · JSON (copy this for tooling)', :pk_json
      UNION ALL
      SELECT 100 + INDEX, 'WILL RUN (only if approved)',
             IFF(LENGTH(VALUE::STRING) > 400,
                 LEFT(VALUE::STRING, 300) || ' ... [' || LENGTH(VALUE::STRING) || ' chars]',
                 VALUE::STRING)
      FROM TABLE(FLATTEN(input => :stmts))
      ORDER BY step
    );
    RETURN TABLE(res);
  END IF;

  -- ── APPROVED: build ───────────────────────────────────────────────────────
  -- Stops at the first failure because later statements depend on earlier ones.
  --
  -- Every statement's QUERY_ID is captured as it runs. That is the whole
  -- measurement instrument: with it, the credits, rows and elapsed time of this
  -- build can be read back from history exactly. Without it there is only
  -- arithmetic. LAST_QUERY_ID() is verified to return the id of the statement the
  -- loop just issued by EXECUTE IMMEDIATE, not the id of the enclosing block.
  --
  -- The ids are accumulated and written ONCE after the loop rather than inserted
  -- per statement. Inserting inside the loop cannot work: BUILD_STATEMENT_LOG is
  -- itself created by one of the statements in this list, so the first few
  -- iterations would be writing to a table that does not exist yet.
  LET log  ARRAY := ARRAY_CONSTRUCT();
  LET qlog ARRAY := ARRAY_CONSTRUCT();
  LET i    INT   := 0;
  LET build_start TIMESTAMP_NTZ := CURRENT_TIMESTAMP();
  WHILE (:i < ARRAY_SIZE(:stmts)) DO
    LET s STRING := GET(:stmts, :i)::STRING;
    BEGIN
      EXECUTE IMMEDIATE :s;
      log := ARRAY_APPEND(:log, OBJECT_CONSTRUCT('n', :i + 1, 'status', 'OK',
                                                 'stmt', LEFT(:s, 120), 'error', ''));
      qlog := ARRAY_APPEND(:qlog, OBJECT_CONSTRUCT(
        'seq', :i + 1, 'qid', LAST_QUERY_ID(), 'status', 'OK',
        'stmt', LEFT(:s, 4000), 'err', ''));
    EXCEPTION WHEN OTHER THEN
      log := ARRAY_APPEND(:log, OBJECT_CONSTRUCT('n', :i + 1, 'status', 'FAILED',
                                                 'stmt', LEFT(:s, 120), 'error', SQLERRM));
      qlog := ARRAY_APPEND(:qlog, OBJECT_CONSTRUCT(
        'seq', :i + 1, 'qid', '', 'status', 'FAILED',
        'stmt', LEFT(:s, 4000), 'err', LEFT(SQLERRM, 2000)));
      i := ARRAY_SIZE(:stmts);
    END;
    i := :i + 1;
  END WHILE;

  -- Persist the statement log and this run's ledger row. Wrapped because a failed
  -- build may not have created the tables these write to, and a measurement
  -- bookkeeping failure must never be reported as a build failure.
  --
  -- Base64 for the same reason the action registry uses it: this payload contains
  -- generated DDL with quoted identifiers, TO_JSON escapes those to backslash-quote,
  -- and a single-quoted SQL literal then eats the backslash.
  BEGIN
    EXECUTE IMMEDIATE
      'INSERT INTO ' || :tgt || '.BUILD_STATEMENT_LOG '
   || '(RUN_ID, TIER, SEQ, STATEMENT, QUERY_ID, STATUS, ERROR) SELECT '
   || '''' || :run_id || ''', ''' || :tier || ''', '
   || 'VALUE:seq::INT, VALUE:stmt::STRING, NULLIF(VALUE:qid::STRING, ''''), '
   || 'VALUE:status::STRING, NULLIF(VALUE:err::STRING, '''') '
   || 'FROM TABLE(FLATTEN(input => PARSE_JSON(BASE64_DECODE_STRING('''
   || BASE64_ENCODE(TO_JSON(:qlog)) || '''))))';
  EXCEPTION WHEN OTHER THEN
    log := ARRAY_APPEND(:log, OBJECT_CONSTRUCT('n', 9990, 'status', 'FAILED',
      'stmt', 'INSERT INTO BUILD_STATEMENT_LOG', 'error', SQLERRM));
  END;
  BEGIN
    EXECUTE IMMEDIATE
      'INSERT INTO ' || :tgt || '.RUN_LEDGER (RUN_ID, TIER, QUERY_TAG, TAG_STATUS, '
   || 'MEASURE_WAREHOUSE, CREDIT_CAP, CAP_APPLIED, GATE_OPENED, PROFILE_STATUS, '
   || 'REVIEW_VERDICT, REVIEW_OVERRIDDEN, STATEMENTS_PLANNED) SELECT '
   || '''' || :run_id || ''', ''' || :tier || ''', '
   || '''' || REPLACE(:qtag, '''', '''''') || ''', ''' || REPLACE(:tag_status, '''', '''''') || ''', '
   || '''' || IFF(:cap_applied OR :tier <> 'DISCOVER', :meas_wh, :wh) || ''', '
   || :credit_cap || ', ' || IFF(:cap_applied, 'TRUE', 'FALSE') || ', TRUE, '
   || '''' || :prof_status || ''', ''' || :review_verdict || ''', '
   || IFF(:review_overridden, 'TRUE', 'FALSE') || ', ' || ARRAY_SIZE(:stmts);
  EXCEPTION WHEN OTHER THEN
    log := ARRAY_APPEND(:log, OBJECT_CONSTRUCT('n', 9991, 'status', 'FAILED',
      'stmt', 'INSERT INTO RUN_LEDGER', 'error', SQLERRM));
  END;

  -- Take the first measurement immediately. Rows and wall clock land NOW because
  -- INFORMATION_SCHEMA.QUERY_HISTORY has no latency; credits do not, and each
  -- category reports its own source and window rather than a shared guess.
  BEGIN
    EXECUTE IMMEDIATE 'CALL ' || :tgt || '.MEASURE()';
  EXCEPTION WHEN OTHER THEN
    log := ARRAY_APPEND(:log, OBJECT_CONSTRUCT('n', 9992, 'status', 'FAILED',
      'stmt', 'CALL MEASURE()', 'error', SQLERRM));
  END;

  -- Hand the session back. If this build created its own warehouse and the
  -- session is still pointed at it, a later TEARDOWN drops the warehouse out from
  -- under whoever is still connected.
  IF (:tier IN ('LIMITED', 'PRODUCTION') AND :wh_ok AND :wh IS NOT NULL) THEN
    BEGIN
      EXECUTE IMMEDIATE 'USE WAREHOUSE ' || :wh;
    EXCEPTION WHEN OTHER THEN NULL;
    END;
  END IF;

  -- ── Teardown procedure ────────────────────────────────────────────────────
  -- Body is SINGLE-quoted. A dollar-quoted procedure body nested inside this
  -- dollar-quoted block would terminate the outer block at the first inner
  -- delimiter, reparsing the file into far more statements than it has and
  -- reporting "syntax error unexpected DECLARE". Note that the delimiter is not
  -- comment-aware either: writing the two-dollar sequence in a comment IN HERE
  -- ends the block just as surely as writing it in code. Internal quotes are
  -- doubled once, for the procedure-body literal.
  BEGIN
    EXECUTE IMMEDIATE
      'CREATE OR REPLACE PROCEDURE ' || :tgt || '.TEARDOWN() RETURNS VARCHAR LANGUAGE SQL AS '
   || 'DECLARE r RESULTSET; detached INT DEFAULT 0; failed INT DEFAULT 0; '
   || 'skipped INT DEFAULT 0; skipped_kinds ARRAY DEFAULT ARRAY_CONSTRUCT(); '
   || 'failed_items ARRAY DEFAULT ARRAY_CONSTRUCT(); BEGIN '
      -- The solution's OWN teardown section runs FIRST, and it is required to
      -- DELETE the registry rows it handles.
      --
      -- Order matters here and got it wrong once. With the shared loop first, a
      -- solution-specific KIND fell through to the fallback and was counted as
      -- unhandled, then the solution's own section detached it a moment later -- so
      -- the return message reported the same four rows as both detached and NOT
      -- detached. Handling them first and deleting them means the shared loop only
      -- ever sees rows it is responsible for, which is what makes its fallback
      -- report trustworthy.
   || 'LET r_task RESULTSET := (SELECT TARGET_FQN FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ''TASK''); FOR t_rec IN r_task DO BEGIN EXECUTE IMMEDIATE ''ALTER TASK IF EXISTS '' || t_rec.TARGET_FQN || '' SUSPEND''; EXECUTE IMMEDIATE ''DROP TASK IF EXISTS '' || t_rec.TARGET_FQN; detached := :detached + 1; EXCEPTION WHEN OTHER THEN failed := :failed + 1; failed_items := ARRAY_APPEND(:failed_items, t_rec.TARGET_FQN || '': '' || SQLERRM); END; END FOR; DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ''TASK'';
LET r_proc RESULTSET := (SELECT TARGET_FQN, ARTIFACT, ARGUMENTS FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ''PROCEDURE''); FOR p_rec IN r_proc DO BEGIN EXECUTE IMMEDIATE ''DROP PROCEDURE IF EXISTS '' || p_rec.TARGET_FQN || ''('' || p_rec.ARGUMENTS || '')''; detached := :detached + 1; EXCEPTION WHEN OTHER THEN failed := :failed + 1; failed_items := ARRAY_APPEND(:failed_items, p_rec.TARGET_FQN || '': '' || SQLERRM); END; END FOR; DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ''PROCEDURE'';
LET r_sv RESULTSET := (SELECT TARGET_FQN FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ''SEMANTIC_VIEW''); FOR sv_rec IN r_sv DO BEGIN EXECUTE IMMEDIATE ''DROP SEMANTIC VIEW IF EXISTS '' || sv_rec.TARGET_FQN; detached := :detached + 1; EXCEPTION WHEN OTHER THEN failed := :failed + 1; failed_items := ARRAY_APPEND(:failed_items, sv_rec.TARGET_FQN || '': '' || SQLERRM); END; END FOR; DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ''SEMANTIC_VIEW'';
LET r_agent RESULTSET := (SELECT TARGET_FQN FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ''AGENT''); FOR a_rec IN r_agent DO BEGIN EXECUTE IMMEDIATE ''DROP CORTEX AGENT IF EXISTS '' || a_rec.TARGET_FQN; detached := :detached + 1; EXCEPTION WHEN OTHER THEN failed := :failed + 1; failed_items := ARRAY_APPEND(:failed_items, a_rec.TARGET_FQN || '': '' || SQLERRM); END; END FOR; DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ''AGENT'';'
      -- ORDER IS LOAD-BEARING, and the lack of it was a real defect. Two kinds of
      -- row live in this registry: ones that UNSET an attachment from an object that
      -- survives, and ones that DROP an object this run owns. At PRODUCTION tier the
      -- same warehouse is both -- it is dropped by its OWNED_WAREHOUSE row and it
      -- carries the cost-attribution tag named by an OBJECT_TAG row. Unordered, the
      -- drop ran first (it is planned first), so the UNSET then addressed a warehouse
      -- that no longer existed and failed with a compilation error. Teardown reported
      -- "Detached 2 (1 failed)" on a run where nothing was wrong, which is worse than
      -- a cosmetic bug: the one message a customer has to be able to trust said
      -- something might still be attached to their account.
      --
      -- So: unset from parents first, drop owned objects after, and the warehouse
      -- last of all because everything else attaches to it. TARGET_FQN breaks ties so
      -- two runs of the same teardown report in the same order.
   || 'r := (SELECT TARGET_FQN, ARTIFACT, ARGUMENTS, KIND FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
   || 'ORDER BY CASE KIND WHEN ''OWNED_WAREHOUSE'' THEN 3 '
   || 'WHEN ''RESOURCE_MONITOR'' THEN 2 WHEN ''ALERT'' THEN 2 ELSE 1 END, TARGET_FQN); '
   || 'FOR rec IN r DO BEGIN '
   || 'EXECUTE IMMEDIATE CASE rec.KIND '
   || 'WHEN ''DMF'' THEN ''ALTER TABLE '' || rec.TARGET_FQN || '' DROP DATA METRIC FUNCTION '' || rec.ARTIFACT || '' ON ('' || rec.ARGUMENTS || '')'' '
   || 'WHEN ''MASKING_POLICY'' THEN ''ALTER TABLE '' || rec.TARGET_FQN || '' MODIFY COLUMN '' || rec.ARGUMENTS || '' UNSET MASKING POLICY'' '
   || 'WHEN ''TAG'' THEN ''ALTER TABLE '' || rec.TARGET_FQN || '' UNSET TAG '' || rec.ARTIFACT '
      -- Added with the tiers that create them. A KIND without a branch here is a
      -- leak, which is why the fallback below counts rather than swallows.
   || 'WHEN ''OWNED_WAREHOUSE'' THEN ''DROP WAREHOUSE IF EXISTS '' || rec.TARGET_FQN '
   || 'WHEN ''RESOURCE_MONITOR'' THEN ''DROP RESOURCE MONITOR IF EXISTS '' || rec.TARGET_FQN '
   || 'WHEN ''OBJECT_TAG'' THEN ''ALTER '' || rec.ARGUMENTS || '' '' || rec.TARGET_FQN || '' UNSET TAG '' || rec.ARTIFACT '
   || 'WHEN ''ALERT'' THEN ''DROP ALERT IF EXISTS '' || rec.TARGET_FQN '
   || 'WHEN ''TASK_ERROR_INTEGRATION'' THEN ''ALTER TASK '' || rec.TARGET_FQN || '' UNSET ERROR_INTEGRATION'' '
      -- NOT ''SELECT 1''. That is what this used to be, and it made an
      -- unrecognised KIND increment the detached counter -- so adding a new
      -- attachment type without adding a branch above leaked the attachment while
      -- the procedure reported a clean teardown. A deliberate divide-by-zero is a
      -- crude way to reach the handler below, and it is reached on purpose: the row
      -- is then counted as SKIPPED and named in the return message, so the gap is
      -- visible in the one place someone is looking.
   || 'ELSE ''SELECT 1/0'' END; '
   || 'detached := :detached + 1; '
   || 'EXCEPTION WHEN OTHER THEN '
   || 'IF (rec.KIND NOT IN (''DMF'', ''MASKING_POLICY'', ''TAG'', ''OWNED_WAREHOUSE'', '
   || '''RESOURCE_MONITOR'', ''OBJECT_TAG'', ''ALERT'', ''TASK_ERROR_INTEGRATION'')) THEN '
   || 'skipped := :skipped + 1; '
   || 'skipped_kinds := ARRAY_APPEND(:skipped_kinds, rec.KIND || '' on '' || rec.TARGET_FQN); '
   || 'ELSE failed := :failed + 1; '
   || 'failed_items := ARRAY_APPEND(:failed_items, rec.TARGET_FQN || '': '' || SQLERRM); '
   || 'END IF; END; '
   || 'END FOR; '
   || 'BEGIN UPDATE ' || :tgt || '.RUN_LEDGER SET TEARDOWN_AT = CURRENT_TIMESTAMP() '
   || 'WHERE TEARDOWN_AT IS NULL; EXCEPTION WHEN OTHER THEN NULL; END; '
   || 'EXECUTE IMMEDIATE ''DROP SCHEMA IF EXISTS ' || :tgt || ' CASCADE''; '
   || 'RETURN ''Teardown complete. Detached '' || :detached || '' external attachment(s) ('' '
   || '|| :failed || '' failed).'' || IFF(:failed > 0, CHR(10) || ''Failed: '' '
   || '|| ARRAY_TO_STRING(:failed_items, CHR(10)), '''') '
   || '|| IFF(:skipped > 0, CHR(10) || ''NOT DETACHED -- no teardown branch for '' '
   || '|| :skipped || '' registry row(s), which means they are STILL ATTACHED: '' '
   || '|| ARRAY_TO_STRING(:skipped_kinds, ''; '') '
   || '|| CHR(10) || ''Either the solution handles these kinds in its own teardown '
   || 'section, or a new attachment type was added without a branch. Verify by hand.'', ''''); END';
    log := ARRAY_APPEND(:log, OBJECT_CONSTRUCT('n', ARRAY_SIZE(:stmts) + 1, 'status', 'OK',
                                               'stmt', 'CREATE PROCEDURE TEARDOWN()', 'error', ''));
  EXCEPTION WHEN OTHER THEN
    log := ARRAY_APPEND(:log, OBJECT_CONSTRUCT('n', ARRAY_SIZE(:stmts) + 1, 'status', 'FAILED',
                                               'stmt', 'CREATE PROCEDURE TEARDOWN()', 'error', SQLERRM));
  END;

  -- The notes and the review verdict are emitted HERE as well as on the gate-closed
  -- path, and leaving them out of this one was a real gap. Everything the review has
  -- to say -- the verdict, its status, and every finding it raised -- was printed only
  -- on the dry run. The run that actually creates objects returned a statement log and
  -- a cost line, so a client who set APPROVE = TRUE and read the output was never told
  -- what the review concluded about what they had just built. That is exactly backwards:
  -- the dry run is the one where nothing is at stake. It matters most for NOT_RUN, which
  -- is silent by nature -- an unreachable model neither approves nor refuses, and a
  -- reader who is told nothing will read that as approval.
  res := (
    SELECT v.value:n::INT AS n, v.value:status::STRING AS status,
           v.value:stmt::STRING AS statement, v.value:error::STRING AS error
    FROM TABLE(FLATTEN(input => :log)) v
    UNION ALL SELECT 9700, 'REVIEW',
           :review_verdict || ' (' || :review_status || ') · '
        || ARRAY_SIZE(:review_findings) || ' finding(s) · model ' || :adapt_model, ''
    UNION ALL
    SELECT 9701 + INDEX, 'READ THIS', VALUE::STRING, '' FROM TABLE(FLATTEN(input => :notes))
    UNION ALL SELECT 9996, 'MODE', :mode, ''
    UNION ALL SELECT 9998, 'STEADY STATE COST',
           '~' || ROUND(:cost_day, 3) || ' credits/day', ''
    UNION ALL SELECT 9999, 'TO REMOVE EVERYTHING', 'CALL ' || :tgt || '.TEARDOWN();', ''
    ORDER BY n
  );
  RETURN TABLE(res);
END;
$$;
