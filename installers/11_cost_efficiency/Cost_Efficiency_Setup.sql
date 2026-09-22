-- ─────────────────────────────────────────────────────────────────────────────
-- Warehouse Cost Efficiency
-- SETTINGS  ·  the only part of this file intended to be edited
-- ─────────────────────────────────────────────────────────────────────────────

-- The gate. Nothing is created while this is FALSE.
SET COSTEFF_APPROVE = FALSE;

-- Where to build. Blank means the database currently in use.
SET COSTEFF_TARGET_DB = '';
SET COSTEFF_SCHEMA    = 'COST_EFFICIENCY';

-- Blank means the warehouse currently in use.
SET COSTEFF_APP_WAREHOUSE = '';

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
SET COSTEFF_KEEP_APP_WARM  = TRUE;
SET COSTEFF_WARM_WAREHOUSE = 'ONESHOT_APP_WH';

-- How long a viewer's own app session survives idling, in minutes, 5 to 240.
-- Higher means someone returning to the tab reconnects to a live session instead
-- of waiting for a new one to start.
--
-- CAVEAT WORTH KNOWING: the account-level WebSocket timeout, about 15 minutes by
-- default, can close the connection before this timer expires, and only Snowflake
-- Support can raise it. Setting 240 here is therefore an upper bound and not a
-- guarantee.
SET COSTEFF_APP_SLEEP_MINUTES = 240;

-- How far back discovery and the views look.
SET COSTEFF_WINDOW_DAYS = 14;

-- DISCOVER reads your account and reports what it found.
-- SAMPLE seeds representative data instead, and the app says so on every page.
-- Never demo SAMPLE numbers as if they were the customer's.
SET COSTEFF_MODE = 'DISCOVER';

-- Credit ceiling for steady-state cost. 0 means no ceiling. When the plan's own
-- estimate exceeds this, Block 3 refuses to plan and tells you what to turn down.
SET COSTEFF_BUDGET_CREDITS = 0;

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
SET COSTEFF_DEPLOY_TIER = 'DISCOVER';

-- Names this run in QUERY_TAG so its statements can be found in history later.
-- Blank generates one. Set it yourself only if you are correlating with your own
-- observability.
SET COSTEFF_RUN_ID = '';

-- Warehouse the LIMITED and PRODUCTION tiers create for their own work. Blank
-- derives a name from the schema. It is XSMALL with a 60-second auto-suspend and
-- it is dropped by TEARDOWN.
SET COSTEFF_MEASURE_WAREHOUSE = '';

-- Credit quota for the resource monitor on that warehouse. This is a REAL
-- ceiling: the warehouse suspends when it is reached.
--
-- Read what it does NOT cover before you rely on it. A resource monitor governs
-- WAREHOUSES only. It cannot cap serverless features or AI-services tokens --
-- Snowflake's own documentation says to use a BUDGET for those. So on a solution
-- that spends most of its credits on AI, this number is not the ceiling you think
-- it is, and Block 0 prints exactly which categories it does and does not cover.
SET COSTEFF_CREDIT_CAP = 5;

-- Dollars per credit, for the readable version of every credit figure. Your rate
-- is on your contract; the default is a list-price placeholder, not your price.
SET COSTEFF_COST_PER_CREDIT = 3;

-- Ratio of output tokens to input tokens, used only to ESTIMATE AI spend before
-- it happens. AI_COUNT_TOKENS counts input tokens and cannot see output tokens,
-- so without this the estimate is systematically low. After a run the real split
-- is measured and the estimate is graded against it.
SET COSTEFF_OUTPUT_TOKEN_RATIO = 0.5;

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
SET COSTEFF_PROFILE = FALSE;

-- A column must be at least this percent non-null to be used. Below it, the plan
-- downgrades or refuses the thing that depended on it, and prints why.
SET COSTEFF_MIN_FILL_PCT = 60;

-- Internal. Do not edit. Block 2 publishes its statistics here in chunks.
SET COSTEFF_PROFILE_N = 0;

-- ─────────────────────────────────────────────────────────────────────────────
-- REVIEW
-- ─────────────────────────────────────────────────────────────────────────────

-- Block 3 asks the model to review the finished plan against what discovery and
-- the profile actually found, and returns PROCEED, CAVEAT or DO_NOT_PROCEED.
--
-- DO_NOT_PROCEED closes the gate even when COSTEFF_APPROVE is TRUE. Setting this to
-- TRUE overrides that. It is your call to make and the override is recorded in the
-- output, in the packet and in REVIEW_LOG, because "we were told not to and did it
-- anyway" is a thing your own audit should be able to see.
SET COSTEFF_OVERRIDE_REVIEW = FALSE;

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
SET COSTEFF_NOTIFICATION_INTEGRATION = '';


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
SET COSTEFF_ALLOW_ACTIONS = FALSE;

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
SET COSTEFF_ALLOW_SAMPLE_ACTIONS = TRUE;

-- Model used to read your discovery results and adapt the plan. Deliberately the
-- strongest available rather than the cheapest: this call decides which of your
-- objects get used and how, and a weaker model gets those judgements wrong in
-- ways that are hard to spot. It runs ONCE per plan, so the cost is negligible.
-- Verified available in this account: claude-opus-5, claude-opus-4-6,
-- openai-gpt-5.2, openai-gpt-5, claude-4-sonnet, mistral-large2.
SET COSTEFF_MODEL = 'claude-opus-5';

-- Internal. Do not edit. Block 1 publishes its findings here in chunks, because
-- one session variable caps at 16,384 bytes.
SET COSTEFF_SIGNALS_N = 0;

-- ── Scope for warehouse changes ───────────────────────────────────────────────
-- Comma-separated warehouse names this build may ALTER. BLANK MEANS NOTHING IS
-- ALTERED: discovery still reports every candidate and the savings views still
-- build, but no warehouse setting is touched.
--
-- This has to be a real SET line rather than a bare GETVARIABLE read. Otherwise
-- the setting is invisible to anyone reading the file, and the test harness
-- cannot drive it, which left the ALTER path in this solution completely
-- unexercised while every gauntlet step still reported green.
SET COSTEFF_WAREHOUSES = '';


-- ─────────────────────────────────────────────────────────────────────────────
-- BLOCK 0 · PRE-FLIGHT
-- Answers only the questions that decide whether the rest can run.
-- Creates nothing. Reads no business data.
-- ─────────────────────────────────────────────────────────────────────────────
EXECUTE IMMEDIATE $$
DECLARE
  res RESULTSET;
BEGIN
  LET db   STRING := COALESCE(NULLIF($COSTEFF_TARGET_DB::VARCHAR, ''), CURRENT_DATABASE());
  LET wh   STRING := COALESCE(NULLIF($COSTEFF_APP_WAREHOUSE::VARCHAR, ''), CURRENT_WAREHOUSE());
  LET sch  STRING := $COSTEFF_SCHEMA::VARCHAR;
  LET mode STRING := UPPER(COALESCE($COSTEFF_MODE::VARCHAR, 'DISCOVER'));
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
      COALESCE(NULLIF($COSTEFF_MODEL::VARCHAR, ''), 'claude-opus-5'), 'Reply with OK.'));
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
  LET tier      STRING := UPPER(COALESCE(NULLIF($COSTEFF_DEPLOY_TIER::VARCHAR, ''), 'DISCOVER'));
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
  LET ni       STRING := COALESCE(NULLIF($COSTEFF_NOTIFICATION_INTEGRATION::VARCHAR, ''), '');
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
    profile_on := (SELECT TRY_CAST($COSTEFF_PROFILE::VARCHAR AS BOOLEAN));
  EXCEPTION WHEN OTHER THEN profile_on := FALSE;
  END;
  LET cap NUMBER(38,2) := COALESCE((SELECT TRY_CAST($COSTEFF_CREDIT_CAP::VARCHAR AS NUMBER)), 0);


  LET approved BOOLEAN := FALSE;
  BEGIN
    approved := (SELECT TRY_CAST($COSTEFF_APPROVE::VARCHAR AS BOOLEAN));
  EXCEPTION WHEN OTHER THEN approved := FALSE;
  END;


  res := (
    SELECT 1 AS step, 'TARGET DATABASE' AS check_name,
           COALESCE(:db, 'NONE SELECTED') AS finding,
           IFF(:db IS NULL, 'Run USE DATABASE, or set COSTEFF_TARGET_DB.',
               IFF(:db_ok, '', 'Grant CREATE SCHEMA on this database, or point at one you own.')) AS fix
    UNION ALL SELECT 2, 'CREATE SCHEMA', IFF(:db_ok, 'AUTHORIZED', 'NOT AUTHORIZED'),
           IFF(:db_ok, '', 'GRANT CREATE SCHEMA ON DATABASE ' || COALESCE(:db, '<db>') || ' TO ROLE ' || CURRENT_ROLE())
    UNION ALL SELECT 3, 'WAREHOUSE', COALESCE(:wh, 'NONE SELECTED'),
           IFF(:wh IS NULL, 'Run USE WAREHOUSE, or set COSTEFF_APP_WAREHOUSE.', '')
    UNION ALL SELECT 4, 'ACCOUNT_USAGE', IFF(:au_ok, 'READABLE', 'NOT READABLE'),
           IFF(:au_ok, '', 'GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE ' || CURRENT_ROLE())
    UNION ALL SELECT 5, 'CORTEX (' || COALESCE(NULLIF($COSTEFF_MODEL::VARCHAR, ''), 'claude-opus-5')
           || ')', IFF(:cortex_ok, 'AVAILABLE', 'NOT AVAILABLE'),
           IFF(:cortex_ok, '', 'GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE ' || CURRENT_ROLE()
               || ' — without it the agent is skipped and the dashboard still builds.')
    UNION ALL SELECT 6, 'EXISTING SCHEMA', IFF(:existing > 0, :db || '.' || :sch || ' ALREADY EXISTS', 'not present'),
           IFF(:existing > 0, 'A previous build is there. Re-running updates it in place; CALL ' || :db || '.' || :sch || '.TEARDOWN() removes it.', '')
    UNION ALL SELECT 7, 'MODE', :mode,
           IFF(:mode = 'SAMPLE', 'Seeded data. The app will label every page SAMPLE DATA. Do not present these numbers as the customer''s.', 'Reads this account.')
    UNION ALL SELECT 8, 'GATE', IFF(:approved, 'OPEN — Block 3 will build', 'CLOSED — nothing will be created'),
           IFF(:approved, 'Review the plan below before you let this run.', 'To build: set COSTEFF_APPROVE = TRUE and run the file again.')
    UNION ALL SELECT 9, 'DEPLOY TIER', :tier,
           CASE :tier
             WHEN 'DISCOVER' THEN 'Costs below are ARITHMETIC ESTIMATES. Nothing is measured at this tier. Set COSTEFF_DEPLOY_TIER = ''LIMITED'' to get a real number.'
             WHEN 'LIMITED' THEN 'Builds on its own capped warehouse so credits can be measured and attributed to this run.'
             WHEN 'PRODUCTION' THEN 'Full scope plus monitor, budget, tags, error notification and an operations view.'
             ELSE 'Unrecognised tier — treated as DISCOVER. Use DISCOVER, LIMITED or PRODUCTION.'
           END
    UNION ALL SELECT 10, 'PROFILE', IFF(:profile_on, 'ON — will sample the columns the plan uses',
                                        'OFF — column populated-ness will NOT be checked'),
           IFF(:profile_on,
               'Reads a sample of named columns only. Emits aggregates: null rate, distinct count, row count, type, and min/max for DATE columns only.',
               'This is the gap that lets a plan build on a column that exists and is empty. Set COSTEFF_PROFILE = TRUE to close it. The review will return CAVEAT rather than PROCEED while it is off.')
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
  LET w    INT    := COALESCE((SELECT TRY_CAST($COSTEFF_WINDOW_DAYS::VARCHAR AS INT)), 14);
  LET db   STRING := COALESCE(NULLIF($COSTEFF_TARGET_DB::VARCHAR, ''), CURRENT_DATABASE());
  LET mode STRING := UPPER(COALESCE($COSTEFF_MODE::VARCHAR, 'DISCOVER'));
  LET sig  OBJECT := OBJECT_CONSTRUCT();
  LET cnt  OBJECT := OBJECT_CONSTRUCT();

  -- ── Probes ────────────────────────────────────────────────────────────────
  -- One BEGIN/EXCEPTION per signal. Copy the shape; do not merge them, because
  -- a merged probe turns one unreadable view into a dead run.
  --
  -- Probe: warehouse inventory via SHOW WAREHOUSES
  BEGIN
    EXECUTE IMMEDIATE 'SHOW WAREHOUSES';
    LET wh_count INT := (SELECT COUNT(*) AS N FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    sig := OBJECT_INSERT(:sig, 'warehouses', IFF(:wh_count > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'warehouses', :wh_count, TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'warehouses', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'warehouses', 0, TRUE);
  END;

  -- Probe: credit consumption from WAREHOUSE_METERING_HISTORY
  BEGIN
    LET cr_rows INT := (SELECT COUNT(*) FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
                        WHERE START_TIME >= DATEADD(day, -:w, CURRENT_TIMESTAMP()));
    sig := OBJECT_INSERT(:sig, 'credit_history', IFF(:cr_rows > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'credit_history', :cr_rows, TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'credit_history', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'credit_history', 0, TRUE);
  END;

  -- Probe: warehouse events (suspend/resume churn)
  BEGIN
    LET ev_rows INT := (SELECT COUNT(*) FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_EVENTS_HISTORY
                        WHERE TIMESTAMP >= DATEADD(day, -:w, CURRENT_TIMESTAMP()));
    sig := OBJECT_INSERT(:sig, 'wh_events', IFF(:ev_rows > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'wh_events', :ev_rows, TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'wh_events', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'wh_events', 0, TRUE);
  END;

  -- Probe: query history for queue/spill pressure
  BEGIN
    LET qh_rows INT := (SELECT COUNT(*) FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
                        WHERE START_TIME >= DATEADD(day, -:w, CURRENT_TIMESTAMP()));
    sig := OBJECT_INSERT(:sig, 'query_history', IFF(:qh_rows > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'query_history', :qh_rows, TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'query_history', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'query_history', 0, TRUE);
  END;

  -- Probe: resource monitors
  BEGIN
    LET rm_rows INT := (SELECT COUNT(*) FROM SNOWFLAKE.ACCOUNT_USAGE.RESOURCE_MONITORS);
    sig := OBJECT_INSERT(:sig, 'resource_monitors', IFF(:rm_rows > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'resource_monitors', :rm_rows, TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'resource_monitors', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'resource_monitors', 0, TRUE);
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
      , 'warehouse_count', COALESCE(GET(:cnt, 'warehouses')::NUMBER, 0)
      , 'credit_history_rows', COALESCE(GET(:cnt, 'credit_history')::NUMBER, 0)
      , 'wh_events_rows', COALESCE(GET(:cnt, 'wh_events')::NUMBER, 0)
      , 'query_history_rows', COALESCE(GET(:cnt, 'query_history')::NUMBER, 0)
      , 'resource_monitor_count', COALESCE(GET(:cnt, 'resource_monitors')::NUMBER, 0)
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
    EXECUTE IMMEDIATE 'SET COSTEFF_SIGNALS_' || (:ci + 1)
                   || ' = ''' || :piece || '''';
    ci := :ci + 1;
  END WHILE;
  EXECUTE IMMEDIATE 'SET COSTEFF_SIGNALS_N = ' || :nchunks;

  -- Prove the handoff survived rather than assuming it did.
  IF ((SELECT COALESCE(TRY_CAST(GETVARIABLE('COSTEFF_SIGNALS_N') AS INT), 0)) <> :nchunks) THEN
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
  LET db      STRING := COALESCE(NULLIF($COSTEFF_TARGET_DB::VARCHAR, ''), CURRENT_DATABASE());
  LET min_fill NUMBER(38,2) := COALESCE((SELECT TRY_CAST($COSTEFF_MIN_FILL_PCT::VARCHAR AS NUMBER)), 60);
  LET sample_rows INT := 10000;
  LET prof_on BOOLEAN := FALSE;
  BEGIN
    prof_on := (SELECT TRY_CAST($COSTEFF_PROFILE::VARCHAR AS BOOLEAN));
  EXCEPTION WHEN OTHER THEN prof_on := FALSE;
  END;

  -- Targets the plan intends to read. One entry per table:
  --   OBJECT_CONSTRUCT('table', '<db.schema.table>',
  --                    'columns', ARRAY_CONSTRUCT('COL_A', 'COL_B'),
  --                    'grain',   'COL_A')          -- optional, single column
  -- The solution fills this in; blank means there is nothing to profile, which is
  -- a legitimate answer for a metadata-only solution.
  LET targets ARRAY := ARRAY_CONSTRUCT();

  IF (NOT :prof_on) THEN
    res := (SELECT 'PROFILE NOT RUN' AS target_table, '' AS column_name, '' AS data_type,
                   'SKIPPED' AS status, NULL::NUMBER AS table_rows, NULL::NUMBER AS sampled_rows,
                   NULL::NUMBER AS null_pct, NULL::NUMBER AS distinct_in_sample,
                   NULL::STRING AS min_date, NULL::STRING AS max_date,
                   'NOT_CHECKED' AS verdict,
                   'Set COSTEFF_PROFILE = TRUE to check whether the columns this plan '
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
                      || :min_fill || '% floor set by COSTEFF_MIN_FILL_PCT.'
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
    EXECUTE IMMEDIATE 'SET COSTEFF_PROFILE_' || (:pi + 1) || ' = ''' || :piece || '''';
    pi := :pi + 1;
  END WHILE;
  EXECUTE IMMEDIATE 'SET COSTEFF_PROFILE_N = ' || :nchunks;

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
  -- 'COSTEFF_SIGNALS_' || :i with "argument 0 ... needs to be constant".
  LET nchunks INT := COALESCE((SELECT TRY_CAST(GETVARIABLE('COSTEFF_SIGNALS_N') AS INT)), 0);
  IF (:nchunks = 0) THEN
    res := (SELECT 0 AS step, 'BLOCKED' AS action,
                   'Block 1 has not run in this session. Run the file top to bottom.' AS statement);
    RETURN TABLE(res);
  END IF;

  LET buf STRING :=
       COALESCE(GETVARIABLE('COSTEFF_SIGNALS_1'), '')
    || COALESCE(GETVARIABLE('COSTEFF_SIGNALS_2'), '')
    || COALESCE(GETVARIABLE('COSTEFF_SIGNALS_3'), '')
    || COALESCE(GETVARIABLE('COSTEFF_SIGNALS_4'), '')
    || COALESCE(GETVARIABLE('COSTEFF_SIGNALS_5'), '')
    || COALESCE(GETVARIABLE('COSTEFF_SIGNALS_6'), '')
    || COALESCE(GETVARIABLE('COSTEFF_SIGNALS_7'), '')
    || COALESCE(GETVARIABLE('COSTEFF_SIGNALS_8'), '');

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
  LET db     STRING  := COALESCE(NULLIF($COSTEFF_TARGET_DB::VARCHAR, ''), CURRENT_DATABASE());
  LET sch    STRING  := $COSTEFF_SCHEMA::VARCHAR;
  LET wh     STRING  := COALESCE(NULLIF($COSTEFF_APP_WAREHOUSE::VARCHAR, ''), CURRENT_WAREHOUSE());
  LET budget NUMBER  := COALESCE((SELECT TRY_CAST($COSTEFF_BUDGET_CREDITS::VARCHAR AS NUMBER)), 0);

  -- ── Reassemble the profile handoff ────────────────────────────────────────
  -- Optional: Block 2 only publishes when its own gate is open. Absent is not
  -- the same as clean, and the difference is carried explicitly in :prof_status
  -- so nothing downstream can read "no findings" out of "never looked".
  LET pchunks INT := COALESCE((SELECT TRY_CAST(GETVARIABLE('COSTEFF_PROFILE_N') AS INT)), 0);
  LET prof        VARIANT := NULL;
  LET prof_status STRING  := 'NOT RUN';
  IF (:pchunks > 0) THEN
    LET pbuf STRING :=
         COALESCE(GETVARIABLE('COSTEFF_PROFILE_1'), '')
      || COALESCE(GETVARIABLE('COSTEFF_PROFILE_2'), '')
      || COALESCE(GETVARIABLE('COSTEFF_PROFILE_3'), '')
      || COALESCE(GETVARIABLE('COSTEFF_PROFILE_4'), '');
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
  LET run_id STRING := COALESCE(NULLIF($COSTEFF_RUN_ID::VARCHAR, ''), UUID_STRING());
  LET tier   STRING := UPPER(COALESCE(NULLIF($COSTEFF_DEPLOY_TIER::VARCHAR, ''), 'DISCOVER'));
  IF (:tier NOT IN ('DISCOVER', 'LIMITED', 'PRODUCTION')) THEN
    tier := 'DISCOVER';
  END IF;
  LET qtag STRING := TO_JSON(OBJECT_CONSTRUCT(
      'oneshot', 'Warehouse Cost Efficiency', 'prefix', 'COSTEFF', 'run_id', :run_id, 'tier', :tier));
  LET tag_status STRING := 'NOT SET';
  BEGIN
    EXECUTE IMMEDIATE 'ALTER SESSION SET QUERY_TAG = ''' || REPLACE(:qtag, '''', '''''') || '''';
    tag_status := 'SET';
  EXCEPTION WHEN OTHER THEN
    tag_status := 'REFUSED (' || SQLERRM || ') - warehouse credits for this run '
               || 'cannot be attributed by tag and will read NOT_ATTRIBUTABLE';
  END;

  -- The warehouse the measured tiers build on, and the cap over it.
  LET meas_wh STRING := COALESCE(NULLIF($COSTEFF_MEASURE_WAREHOUSE::VARCHAR, ''),
                                 LEFT(:sch, 80) || '_ONESHOT_WH');
  LET credit_cap NUMBER(38,2) := COALESCE((SELECT TRY_CAST($COSTEFF_CREDIT_CAP::VARCHAR AS NUMBER)), 0);
  LET rate NUMBER(38,4) := COALESCE((SELECT TRY_CAST($COSTEFF_COST_PER_CREDIT::VARCHAR AS NUMBER)), 3);
  LET out_ratio NUMBER(38,4) := COALESCE((SELECT TRY_CAST($COSTEFF_OUTPUT_TOKEN_RATIO::VARCHAR AS NUMBER)), 0.5);
  LET min_fill NUMBER(38,2) := COALESCE((SELECT TRY_CAST($COSTEFF_MIN_FILL_PCT::VARCHAR AS NUMBER)), 60);
  LET notif STRING := COALESCE(NULLIF($COSTEFF_NOTIFICATION_INTEGRATION::VARCHAR, ''), '');

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
                   'No database selected. Run USE DATABASE or set COSTEFF_TARGET_DB.' AS statement);
    RETURN TABLE(res);
  END IF;
  IF (:wh IS NULL) THEN
    res := (SELECT 0 AS step, 'BLOCKED' AS action,
                   'No warehouse selected. Run USE WAREHOUSE or set COSTEFF_APP_WAREHOUSE.' AS statement);
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
    (SELECT TRY_CAST($COSTEFF_ALLOW_ACTIONS::VARCHAR AS BOOLEAN)), FALSE);

  -- SAMPLE tier, governed separately and defaulting TRUE. Kept as its own variable
  -- rather than folded into :allow_actions so that the two authorisations stay
  -- distinguishable everywhere downstream -- the build context records both, and
  -- RUN_ACTION picks the one matching the action's own TIER. COALESCE to TRUE here
  -- because a build produced by an OLDER file that has no COSTEFF_ALLOW_SAMPLE_ACTIONS
  -- line should still get the new default rather than silently disarming.
  LET allow_sample_actions BOOLEAN := COALESCE(
    (SELECT TRY_CAST($COSTEFF_ALLOW_SAMPLE_ACTIONS::VARCHAR AS BOOLEAN)), TRUE);

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
  LET adapt_model  STRING  := COALESCE(NULLIF($COSTEFF_MODEL::VARCHAR, ''), 'claude-opus-5');

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
    (SELECT TRY_CAST($COSTEFF_KEEP_APP_WARM::VARCHAR AS BOOLEAN)), FALSE);
  LET warm_wh STRING := UPPER(TRIM(COALESCE(
    NULLIF($COSTEFF_WARM_WAREHOUSE::VARCHAR, ''), 'ONESHOT_APP_WH')));
  -- An explicitly named app warehouse is an instruction, not a default, so
  -- warming leaves it alone rather than silently rehoming the app somewhere else.
  LET wh_named BOOLEAN := (NULLIF($COSTEFF_APP_WAREHOUSE::VARCHAR, '') IS NOT NULL);
  LET warm_status STRING := 'OFF';

  IF (:warm_on AND :wh_named) THEN
    warm_status := 'DECLINED_EXPLICIT_WAREHOUSE';
    notes := ARRAY_APPEND(:notes,
      'APP WARMING SKIPPED: COSTEFF_APP_WAREHOUSE names ' || :wh || ' explicitly, so '
   || 'the app stays there rather than being moved to ' || :warm_wh || '. Clear '
   || 'COSTEFF_APP_WAREHOUSE to let warming manage the app warehouse, or set '
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
   || 'because they all share this warehouse. Set COSTEFF_KEEP_APP_WARM = FALSE to '
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
      'APP WARMING DEGRADED: COSTEFF_KEEP_APP_WARM is TRUE but ' || CURRENT_ROLE()
   || ' cannot create a warehouse, so the app stays on ' || :wh || ' and first '
   || 'loads pay for the package cache being rebuilt after every suspend. To fix, '
   || 'either GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE ' || CURRENT_ROLE()
   || ', or have an administrator run: CREATE WAREHOUSE ' || :warm_wh
   || ' WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = NULL AUTO_RESUME = TRUE; then set '
   || 'COSTEFF_APP_WAREHOUSE = ''' || :warm_wh || '''.');
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
    (SELECT TRY_CAST($COSTEFF_APP_SLEEP_MINUTES::VARCHAR AS INT)), 240);
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
   || 'COMMENT = ''oneshot Warehouse Cost Efficiency run ' || :run_id || ' - dropped by TEARDOWN''');
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
 || 'CURRENT_TIMESTAMP() AS BUILT_AT, ''Warehouse Cost Efficiency'' AS SOLUTION, '
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
 || '''COSTEFF'' AS SETTING_PREFIX');

  -- ── Warehouse Cost Efficiency Plan ──────────────────────────────────────────

  -- Credit consumption view (always created if credit_history is available)
  IF (:sig:credit_history::STRING = 'AVAILABLE') THEN
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE VIEW ' || :tgt || '.V_WH_CREDIT_CONSUMPTION AS '
   || 'SELECT WAREHOUSE_NAME, DATE_TRUNC(''day'', START_TIME) AS DAY, '
   || 'SUM(CREDITS_USED) AS CREDITS_USED, '
   || 'SUM(CREDITS_USED_COMPUTE) AS CREDITS_COMPUTE, '
   || 'SUM(CREDITS_USED_CLOUD_SERVICES) AS CREDITS_CLOUD '
   || 'FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY '
   || 'WHERE START_TIME >= ' || :since || ' '
   || 'GROUP BY 1, 2 ORDER BY 1, 2');
    cost_day    := :cost_day + 0.02;
    cost_detail := ARRAY_APPEND(:cost_detail, 'V_WH_CREDIT_CONSUMPTION scanned on read ~0.02 credits/day');
    dials       := ARRAY_APPEND(:dials, 'WINDOW_DAYS ' || :w || ' -> 7 saves ~0.01 credits/day on consumption view');
  END IF;

  -- Warehouse churn view (suspend/resume frequency per day)
  IF (:sig:wh_events::STRING = 'AVAILABLE') THEN
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE VIEW ' || :tgt || '.V_WH_CHURN AS '
   || 'SELECT WAREHOUSE_NAME, DATE_TRUNC(''day'', TIMESTAMP) AS DAY, '
   || 'COUNT_IF(EVENT_NAME = ''RESUME_WAREHOUSE'') AS RESUMES, '
   || 'COUNT_IF(EVENT_NAME = ''SUSPEND_WAREHOUSE'') AS SUSPENDS, '
   || 'COUNT(*) AS TOTAL_EVENTS '
   || 'FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_EVENTS_HISTORY '
   || 'WHERE TIMESTAMP >= ' || :since || ' '
   || 'GROUP BY 1, 2 ORDER BY 1, 2');
    cost_day    := :cost_day + 0.01;
    cost_detail := ARRAY_APPEND(:cost_detail, 'V_WH_CHURN scanned on read ~0.01 credits/day');
  END IF;

  -- Queue and spill pressure view
  IF (:sig:query_history::STRING = 'AVAILABLE') THEN
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE VIEW ' || :tgt || '.V_WH_PRESSURE AS '
   || 'SELECT WAREHOUSE_NAME, DATE_TRUNC(''day'', START_TIME) AS DAY, '
   || 'COUNT(*) AS QUERY_COUNT, '
   || 'SUM(QUEUED_OVERLOAD_TIME) / 1000 AS QUEUED_SECONDS, '
   || 'SUM(BYTES_SPILLED_TO_LOCAL_STORAGE) / POWER(1024, 3) AS SPILL_LOCAL_GB, '
   || 'SUM(BYTES_SPILLED_TO_REMOTE_STORAGE) / POWER(1024, 3) AS SPILL_REMOTE_GB '
   || 'FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY '
   || 'WHERE START_TIME >= ' || :since || ' AND WAREHOUSE_NAME IS NOT NULL '
   || 'GROUP BY 1, 2 ORDER BY 1, 2');
    cost_day    := :cost_day + 0.03;
    cost_detail := ARRAY_APPEND(:cost_detail, 'V_WH_PRESSURE scanned on read ~0.03 credits/day');
    dials       := ARRAY_APPEND(:dials, 'WINDOW_DAYS ' || :w || ' -> 7 saves ~0.015 credits/day on pressure view');
  END IF;

  -- Drill tree: account total -> top warehouses -> top query patterns per
  -- warehouse. Materialized as a table because the QUERY_HISTORY scan is too
  -- expensive to repeat on every panel read, and the drill is a build-time
  -- snapshot anyway. The credit attribution at the query level is PROPORTIONAL
  -- TO ELAPSED TIME, not measured -- Snowflake does not expose per-query
  -- credits in QUERY_HISTORY. The column says Q_TIME_PCT, not Q_CREDIT_PCT,
  -- and the UI carries a Method note saying so.
  IF (:sig:credit_history::STRING = 'AVAILABLE' AND :sig:query_history::STRING = 'AVAILABLE') THEN
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE TABLE ' || :tgt || '.WH_DRILL_TREE AS '
   || 'WITH acct AS ('
   || 'SELECT SUM(CREDITS_USED) AS TOTAL_CREDITS '
   || 'FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY '
   || 'WHERE START_TIME >= ' || :since
   || '), '
   || 'wh AS ('
   || 'SELECT WAREHOUSE_NAME, '
   || 'ROUND(SUM(CREDITS_USED), 2) AS WH_CREDITS, '
   || 'ROW_NUMBER() OVER (ORDER BY SUM(CREDITS_USED) DESC) AS WH_RANK '
   || 'FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY '
   || 'WHERE START_TIME >= ' || :since || ' '
   || 'GROUP BY 1'
   || '), '
   -- Three deliberate choices here, each of which changed the answer on real data.
   --
   -- 1. WAREHOUSE_SIZE IS NOT NULL. Metadata operations (DESCRIBE, LIST_FILES,
   --    SHOW) run without a warehouse and consume no warehouse compute. Measured
   --    over 30 days on this account: DESCRIBE ran 169,503 times for 0.0059 cloud
   --    credits, LIST_FILES 169,380 times for 0.0021, and every single one of them
   --    had a NULL warehouse size. Ranked by elapsed time they took second and
   --    third place on the second-largest warehouse, so the drill pointed at
   --    Streamlit stage polling instead of at anything that costs money. This is a
   --    cost drill, so a query that used no warehouse does not belong in it.
   --
   -- 2. EXECUTION_TIME, not TOTAL_ELAPSED_TIME. Elapsed includes compile, queue
   --    and client fetch. A query that waited is not a query that consumed.
   --
   -- 3. Literals are stripped before grouping. This is what makes a PATTERN rather
   --    than a text: without it, the same statement with different bound values is
   --    169,000 distinct groups. It also means we are not painting arbitrary
   --    predicate values onto a screen someone is about to show their director.
   || 'qh AS ('
   || 'SELECT q.WAREHOUSE_NAME, '
   || 'q.QUERY_TYPE, '
   || 'LEFT(REGEXP_REPLACE(REGEXP_REPLACE(REGEXP_REPLACE('
   ||   'q.QUERY_TEXT, ''\\''[^\\'']*\\'''', ''?''), '
   ||   '''\\\\b\\\\d+\\\\b'', ''N''), '
   ||   '''\\\\s+'', '' ''), 100) AS QUERY_PATTERN, '
   || 'COUNT(*) AS EXECUTIONS, '
   || 'SUM(CASE WHEN q.QUERY_TEXT IS NULL OR q.QUERY_TEXT = '''' THEN 1 ELSE 0 END) AS UNLABELLED, '
   || 'ROUND(SUM(q.EXECUTION_TIME) / 1000, 1) AS TOTAL_SECONDS '
   || 'FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY q '
   || 'WHERE q.START_TIME >= ' || :since || ' '
   || 'AND q.WAREHOUSE_NAME IN (SELECT WAREHOUSE_NAME FROM wh WHERE WH_RANK <= 5) '
   || 'AND q.WAREHOUSE_SIZE IS NOT NULL '
   || 'GROUP BY 1, 2, 3'
   || '), '
   || 'qr AS ('
   || 'SELECT qh.*, '
   || 'SUM(TOTAL_SECONDS) OVER (PARTITION BY WAREHOUSE_NAME) AS WH_TOTAL_SECONDS, '
   || 'ROW_NUMBER() OVER (PARTITION BY WAREHOUSE_NAME ORDER BY TOTAL_SECONDS DESC) AS Q_RANK '
   || 'FROM qh'
   || ') '
   || 'SELECT w.WH_RANK, w.WAREHOUSE_NAME, w.WH_CREDITS, '
   || 'ROUND(w.WH_CREDITS / NULLIF(a.TOTAL_CREDITS, 0) * 100, 1) AS WH_PCT, '
   || 'ROUND(a.TOTAL_CREDITS, 2) AS ACCT_TOTAL_CREDITS, '
   || 'q.Q_RANK, q.QUERY_TYPE, q.QUERY_PATTERN, q.EXECUTIONS, '
   || 'q.UNLABELLED, '
   || 'q.TOTAL_SECONDS, '
   || 'ROUND(q.TOTAL_SECONDS / NULLIF(q.WH_TOTAL_SECONDS, 0) * 100, 1) AS Q_TIME_PCT '
   || 'FROM wh w '
   || 'CROSS JOIN acct a '
   || 'LEFT JOIN qr q ON w.WAREHOUSE_NAME = q.WAREHOUSE_NAME AND q.Q_RANK <= 3 '
   || 'WHERE w.WH_RANK <= 5 '
   || 'ORDER BY w.WH_RANK, q.Q_RANK');
    cost_once   := :cost_once + 0.05;
    cost_detail := ARRAY_APPEND(:cost_detail, 'WH_DRILL_TREE one-time build ~0.05 credits (scans QUERY_HISTORY + WAREHOUSE_METERING_HISTORY)');
  END IF;

  -- Snapshot warehouse inventory (SHOW + RESULT_SCAN in one block)
  IF (:sig:warehouses::STRING = 'AVAILABLE') THEN
    stmts := ARRAY_APPEND(:stmts,
      'BEGIN SHOW WAREHOUSES; '
   || 'CREATE OR REPLACE TABLE ' || :tgt || '.WH_INVENTORY AS '
   || 'SELECT "name" AS WAREHOUSE_NAME, "size" AS WH_SIZE, '
   || '"auto_suspend"::INT AS AUTO_SUSPEND_SECS, '
   || 'COALESCE("resource_monitor", '''') AS RESOURCE_MONITOR, '
   || 'COALESCE("generation", '''') AS GENERATION, '
   || 'COALESCE("type", '''') AS WH_TYPE, '
   || 'CURRENT_TIMESTAMP() AS SNAPSHOT_AT '
   || 'FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) '
    -- The demo warehouse this script creates for its own SAMPLE action is NOT
    -- part of the customer's estate and must never appear in the inventory. It
    -- sits at AUTO_SUSPEND = 900, so on a SECOND build the savings view flagged
    -- it and SAVINGS_PROJECTIONS grew by a row -- the solution recommending a fix
    -- for a warehouse it had created. Caught by the idempotency step.
 || 'WHERE "name" <> ' || CHAR(39) || :sch || '_DEMO_WH' || CHAR(39) || '; END');
    cost_once := :cost_once + 0.01;

    -- Register fixture warehouses so teardown can drop them
    stmts := ARRAY_APPEND(:stmts,
      'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY (TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) '
   || 'SELECT w.WAREHOUSE_NAME, ''WAREHOUSE'', ''FIXTURE'', ''FIXTURE_WAREHOUSE'' '
   || 'FROM ' || :tgt || '.WH_INVENTORY w WHERE w.WAREHOUSE_NAME LIKE ''GAUNTLET!_WH!_%'' ESCAPE ''!'' '
   || 'AND NOT EXISTS (SELECT 1 FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY r '
   || 'WHERE r.TARGET_FQN = w.WAREHOUSE_NAME AND r.KIND = ''FIXTURE_WAREHOUSE'')');

    -- Savings summary view
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE VIEW ' || :tgt || '.V_WH_SAVINGS_SUMMARY AS '
   || 'WITH credits AS ('
   || 'SELECT WAREHOUSE_NAME, SUM(CREDITS_USED) AS TOTAL_CREDITS, '
   || 'COUNT(DISTINCT DATE_TRUNC(''day'', START_TIME)) AS ACTIVE_DAYS '
   || 'FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY '
   || 'WHERE START_TIME >= ' || :since || ' GROUP BY 1'
   || '), '
   || 'churn AS ('
   || 'SELECT WAREHOUSE_NAME, '
   || 'COUNT_IF(EVENT_NAME = ''RESUME_WAREHOUSE'') AS TOTAL_RESUMES, '
   || 'COUNT_IF(EVENT_NAME = ''SUSPEND_WAREHOUSE'') AS TOTAL_SUSPENDS, '
   || 'COUNT(DISTINCT DATE_TRUNC(''day'', TIMESTAMP)) AS CHURN_DAYS '
   || 'FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_EVENTS_HISTORY '
   || 'WHERE TIMESTAMP >= ' || :since || ' GROUP BY 1'
   || ') '
   || 'SELECT w.WAREHOUSE_NAME, w.WH_SIZE, w.GENERATION, w.WH_TYPE, '
   || 'w.AUTO_SUSPEND_SECS, w.RESOURCE_MONITOR, '
   || 'COALESCE(c.TOTAL_CREDITS, 0) AS CREDITS_USED, '
   || 'COALESCE(c.ACTIVE_DAYS, 0) AS ACTIVE_DAYS, '
   || 'COALESCE(ch.TOTAL_RESUMES, 0) AS TOTAL_RESUMES, '
   || 'COALESCE(DIV0(ch.TOTAL_RESUMES, NULLIF(ch.CHURN_DAYS, 0)), 0) AS AVG_RESUMES_PER_DAY, '
   || 'COALESCE(ch.TOTAL_SUSPENDS, 0) AS TOTAL_SUSPENDS, '
   || 'CASE '
   || 'WHEN w.GENERATION NOT IN (''2'', '''') AND COALESCE(c.TOTAL_CREDITS, 0) > 0 THEN ''GEN2_UPGRADE'' '
   || 'WHEN COALESCE(DIV0(ch.TOTAL_RESUMES, NULLIF(ch.CHURN_DAYS, 0)), 0) > 5 THEN ''ADAPTIVE_CANDIDATE'' '
      -- STANDARD only. An INTERACTIVE warehouse is SUPPOSED to sit resident --
      -- staying warm is the product -- and this account has one at
      -- AUTO_SUSPEND = 86400 that the rule was flagging as waste. Telling a
      -- customer to set 60s on it would degrade the exact thing they bought.
      -- ADAPTIVE warehouses manage their own suspension, so they are out too.
   || 'WHEN w.AUTO_SUSPEND_SECS > 300 AND UPPER(w.WH_TYPE) = ''STANDARD'' '
   || '  THEN ''REDUCE_AUTO_SUSPEND'' '
   || 'WHEN w.RESOURCE_MONITOR IN ('''', ''null'') THEN ''ADD_RESOURCE_MONITOR'' '
   || 'ELSE ''OK'' END AS RECOMMENDATION, '
      -- Savings are MODELLED from measured events, not taken as a percentage of
      -- spend. The previous version multiplied total credits by 0.05 for
      -- auto-suspend and 0.10 for Gen2. Both were invented. Reducing AUTO_SUSPEND
      -- does not save 5% of a warehouse's credits -- it saves the idle seconds
      -- between the last query finishing and the suspend threshold, which has
      -- nothing to do with how busy the warehouse is. On a warehouse that never
      -- goes idle the saving is zero however much it spends.
      --
      -- The model: each SUSPEND event marks one idle period, and that period burns
      -- roughly AUTO_SUSPEND seconds at the warehouse's per-hour credit rate.
      -- Dropping the threshold to 60s saves (AUTO_SUSPEND - 60) seconds per idle
      -- period. Every input is measured -- suspend count from
      -- WAREHOUSE_EVENTS_HISTORY, threshold and size from SHOW WAREHOUSES -- and
      -- the credit rates are Snowflake's published per-size figures.
      --
      -- It is an UPPER bound: if a query arrives during the idle window the
      -- warehouse never idles the full threshold. Stated as such in the plan.
   || 'CASE '
   || 'WHEN w.AUTO_SUSPEND_SECS > 300 AND UPPER(w.WH_TYPE) = ''STANDARD'' '
   || '  THEN ROUND(COALESCE(ch.TOTAL_SUSPENDS, 0) '
   || '       * GREATEST(w.AUTO_SUSPEND_SECS - 60, 0) / 3600.0 '
   || '       * CASE UPPER(w.WH_SIZE) '
   || '           WHEN ''X-SMALL'' THEN 1 WHEN ''SMALL'' THEN 2 '
   || '           WHEN ''MEDIUM'' THEN 4 WHEN ''LARGE'' THEN 8 '
   || '           WHEN ''X-LARGE'' THEN 16 WHEN ''2X-LARGE'' THEN 32 '
   || '           WHEN ''3X-LARGE'' THEN 64 WHEN ''4X-LARGE'' THEN 128 '
   || '           ELSE 1 END, 2) '
      -- Gen2 deliberately projects NOTHING, and the reason is stronger than
      -- "workload-dependent". Gen2 bills at a HIGHER rate per second than Gen1 --
      -- about 1.35x on AWS and GCP, 1.25x on Azure -- so the saving is the
      -- shortened runtime MINUS that premium, and it is negative whenever the
      -- workload does not speed up by more than roughly 26%. A positive number
      -- here would be a guess wearing a decimal point, and a guess in the
      -- optimistic direction.
      --
      -- Note what that means for GEN2_UPGRADE above: it is an ELIGIBILITY flag,
      -- not a recommendation to convert. It fires on any non-Gen2 standard
      -- warehouse that spent credits, including idle-heavy ones where converting
      -- is a straight loss. 24_warehouse_generation is the solution that judges
      -- each warehouse on measured utilisation and workload shape and then
      -- measures the outcome; read this column as "can move", not "should move".
   || 'ELSE 0 END AS EST_SAVINGS_CREDITS '
   || 'FROM ' || :tgt || '.WH_INVENTORY w '
   || 'LEFT JOIN credits c ON w.WAREHOUSE_NAME = c.WAREHOUSE_NAME '
   || 'LEFT JOIN churn ch ON w.WAREHOUSE_NAME = ch.WAREHOUSE_NAME');
    cost_day    := :cost_day + 0.02;
    cost_detail := ARRAY_APPEND(:cost_detail, 'V_WH_SAVINGS_SUMMARY scanned on read ~0.02 credits/day');
  END IF;

  -- Projection table for measured vs projected savings
  stmts := ARRAY_APPEND(:stmts,
    'CREATE TABLE IF NOT EXISTS ' || :tgt || '.SAVINGS_PROJECTIONS ('
 || 'WAREHOUSE_NAME VARCHAR, RECOMMENDATION VARCHAR, '
 || 'PROJECTED_SAVINGS_CREDITS NUMBER(10,2), '
 || 'MEASURED_SAVINGS_CREDITS NUMBER(10,2) DEFAULT NULL, '
 || 'APPLIED_AT TIMESTAMP_NTZ DEFAULT NULL, '
 || 'MEASURED_AT TIMESTAMP_NTZ DEFAULT NULL, '
 || 'NOTES VARCHAR DEFAULT NULL, '
 || 'CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP())');

  -- Populate projections from savings view (if WH_INVENTORY exists)
  IF (:sig:warehouses::STRING = 'AVAILABLE') THEN
  -- Refresh, do not append: a second build would otherwise double every
  -- projected saving shown on the dashboard.
  stmts := ARRAY_APPEND(:stmts, 'DELETE FROM ' || :tgt || '.SAVINGS_PROJECTIONS');
    stmts := ARRAY_APPEND(:stmts,
      'INSERT INTO ' || :tgt || '.SAVINGS_PROJECTIONS (WAREHOUSE_NAME, RECOMMENDATION, PROJECTED_SAVINGS_CREDITS) '
   || 'SELECT WAREHOUSE_NAME, RECOMMENDATION, EST_SAVINGS_CREDITS '
   || 'FROM ' || :tgt || '.V_WH_SAVINGS_SUMMARY WHERE RECOMMENDATION != ''OK''');
  END IF;

  -- Apply warehouse changes scoped to COSTEFF_WAREHOUSES (blank = do nothing)
  LET wh_list STRING := '';
  BEGIN
    wh_list := COALESCE((SELECT NULLIF($COSTEFF_WAREHOUSES::VARCHAR, '')), '');
  EXCEPTION WHEN OTHER THEN
    wh_list := '';
  END;

  IF (:wh_list != '' AND :sig:warehouses::STRING = 'AVAILABLE') THEN
    -- Record prior AUTO_SUSPEND for warehouses that will be changed
    stmts := ARRAY_APPEND(:stmts,
      'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY (TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) '
   || 'SELECT w.WAREHOUSE_NAME, ''AUTO_SUSPEND'', w.AUTO_SUSPEND_SECS::VARCHAR, ''WAREHOUSE_SETTING'' '
   || 'FROM ' || :tgt || '.WH_INVENTORY w '
   || 'WHERE w.AUTO_SUSPEND_SECS > 300 '
   || 'AND w.WAREHOUSE_NAME IN (SELECT TRIM(VALUE) FROM TABLE(SPLIT_TO_TABLE(''' || :wh_list || ''', '',''))) '
   -- Never overwrite an already-recorded original. On a second build the setting
   -- has already been changed, so re-recording it would save the ALTERED value as
   -- the "prior" one and teardown would restore the wrong number.
   || 'AND NOT EXISTS (SELECT 1 FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY r '
   || 'WHERE r.TARGET_FQN = w.WAREHOUSE_NAME AND r.ARTIFACT = ''AUTO_SUSPEND'')');

    -- Reduce auto_suspend to 60s for high-suspend warehouses in the list
    stmts := ARRAY_APPEND(:stmts,
      'BEGIN '
   || 'LET cur CURSOR FOR SELECT WAREHOUSE_NAME FROM ' || :tgt || '.WH_INVENTORY '
   || 'WHERE AUTO_SUSPEND_SECS > 300 '
   || 'AND WAREHOUSE_NAME IN (SELECT TRIM(VALUE) FROM TABLE(SPLIT_TO_TABLE(''' || :wh_list || ''', '',''))); '
   || 'FOR rec IN cur DO '
   || 'BEGIN EXECUTE IMMEDIATE ''ALTER WAREHOUSE "'' || rec.WAREHOUSE_NAME || ''" SET AUTO_SUSPEND = 60''; '
   || 'EXCEPTION WHEN OTHER THEN NULL; END; '
   || 'END FOR; END');

    cost_once := :cost_once + 0.02;
    cost_detail := ARRAY_APPEND(:cost_detail, 'Warehouse ALTERs (one-time, scoped to COSTEFF_WAREHOUSES) ~0.02 credits');
    dials       := ARRAY_APPEND(:dials, 'Clear COSTEFF_WAREHOUSES to skip all ALTER operations');
  END IF;

  cost_once := :cost_once + 0.01;
  dials := ARRAY_APPEND(:dials, 'WINDOW_DAYS ' || :w || ' -> 7 reduces view scan cost by ~40%');
  cost_detail := ARRAY_APPEND(:cost_detail,
    'EST_SAVINGS_CREDITS is modelled, not a percentage of spend: measured SUSPEND '
 || 'events x (AUTO_SUSPEND - 60) seconds x the published credit rate for that '
 || 'warehouse size. It is an UPPER bound, because a warehouse that gets another '
 || 'query mid-idle never burns the full threshold. Gen2 projects 0 on purpose -- '
 || 'Snowflake publishes no fixed improvement percentage, so any number here would '
 || 'be invented.');

  -- The SAMPLE action needs something disposable to change, and it must NOT create
  -- that itself. CREATE WAREHOUSE makes the new warehouse the session's CURRENT
  -- warehouse; when the undo then dropped it, every later statement in that session
  -- failed with "No active warehouse selected" -- including the UPDATE that
  -- UNDO_ACTION uses to close its own log. The build creates it instead, where the
  -- hijack is harmless, and the action only toggles a setting on it.
  --
  -- Appended AFTER the WH_INVENTORY snapshot above so the snapshot cannot see it,
  -- and excluded by name from the flagged set below: a demo warehouse sitting at
  -- AUTO_SUSPEND 900 would otherwise be counted as one of the customer's problems.
  LET demo_wh STRING := :sch || '_DEMO_WH';
  IF (:sig:warehouses::STRING = 'AVAILABLE') THEN
    stmts := ARRAY_APPEND(:stmts,
      'CREATE WAREHOUSE IF NOT EXISTS ' || :demo_wh || ' WAREHOUSE_SIZE = XSMALL '
   || 'AUTO_SUSPEND = 900 INITIALLY_SUSPENDED = TRUE COMMENT = '
   || CHAR(39) || 'Throwaway target for the ' || :sch || ' SAMPLE action. '
   || 'Dropped by TEARDOWN().' || CHAR(39));
    stmts := ARRAY_APPEND(:stmts,
      'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
   || '(TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) SELECT ' || CHAR(39) || :demo_wh
   || CHAR(39) || ', ' || CHAR(39) || 'FIXTURE' || CHAR(39) || ', '
   || CHAR(39) || 'FIXTURE' || CHAR(39) || ', ' || CHAR(39) || 'FIXTURE_WAREHOUSE'
   || CHAR(39) || ' WHERE NOT EXISTS (SELECT 1 FROM ' || :tgt
   || '.ATTACHED_OBJECT_REGISTRY WHERE TARGET_FQN = ' || CHAR(39) || :demo_wh
   || CHAR(39) || ' AND KIND = ' || CHAR(39) || 'FIXTURE_WAREHOUSE' || CHAR(39) || ')');
    cost_detail := ARRAY_APPEND(:cost_detail,
      :demo_wh || ' is created suspended and never runs a query, so it bills nothing');
  END IF;

  -- ── The push-button next step ──────────────────────────────────────────────
  -- COSTEFF_WAREHOUSES above is the old way to act on this: name the warehouses
  -- in the settings block, re-run the whole file, and the build ALTERs them. That
  -- works, and nobody does it -- it asks someone to edit SQL and re-run a 400KB
  -- script to change one number. The actions below are the same changes as
  -- buttons, and they are the reason the registry writes prior values: TEARDOWN
  -- restores every WAREHOUSE_SETTING row, so the undo text on these is a fact
  -- rather than a promise.
  --
  -- Facts come from SHOW WAREHOUSES at plan time rather than from WH_INVENTORY,
  -- which this build has not created yet. Same RESULT_SCAN pattern the inventory
  -- snapshot uses a few statements up.
  LET wf OBJECT := OBJECT_CONSTRUCT();
  IF (:sig:warehouses::STRING = 'AVAILABLE') THEN
    BEGIN
      SHOW WAREHOUSES;
      SELECT OBJECT_CONSTRUCT(
               'susp_n', COUNT_IF("auto_suspend"::INT > 300
                                  AND UPPER(COALESCE("type", '')) = 'STANDARD'),
               -- Gen2 is standard-only and unavailable at 5X/6X-Large, so a
               -- warehouse outside those bounds is not a candidate however old it is.
               'gen1_n', COUNT_IF(COALESCE("generation", '') NOT IN ('2')
                                  AND UPPER(COALESCE("type", '')) = 'STANDARD'
                                  AND UPPER("size") NOT IN ('5X-LARGE', '6X-LARGE')),
               -- NOT MAX_BY: it breaks ties arbitrarily, and APP_WH and
               -- COMPUTE_WH tie at 600s on this very account -- the caption would
               -- name one warehouse and the ALTER would change another. Zero-pad
               -- the seconds so a lexicographic MAX orders by seconds first and
               -- then by name, which is deterministic and repeatable.
               'worst', SPLIT_PART(MAX(LPAD("auto_suspend"::VARCHAR, 12, '0')
                                       || '|' || "name"), '|', 2)
             ) INTO :wf
      FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
      WHERE UPPER(COALESCE("type", '')) = 'STANDARD'
        AND "name" <> :demo_wh;
    EXCEPTION WHEN OTHER THEN
      wf := OBJECT_CONSTRUCT();
    END;
  END IF;

  LET susp_n INT    := COALESCE(:wf:susp_n::INT, 0);
  LET gen1_n INT    := COALESCE(:wf:gen1_n::INT, 0);
  LET worst  STRING := COALESCE(:wf:worst::STRING, '');

  -- Reused by every action below. Registering the PRIOR value is what makes the
  -- change reversible, and the NOT EXISTS guard is what stops a second press from
  -- recording 60 as the "original" and making teardown a no-op.
  LET reg_susp STRING :=
      'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
   || '(TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) '
   || 'SELECT w.WAREHOUSE_NAME, ''AUTO_SUSPEND'', w.AUTO_SUSPEND_SECS::VARCHAR, '
   || '''WAREHOUSE_SETTING'' FROM ' || :tgt || '.WH_INVENTORY w '
   || 'WHERE w.AUTO_SUSPEND_SECS > 300 AND UPPER(w.WH_TYPE) = ''STANDARD'' '
   || 'AND w.WAREHOUSE_NAME <> ' || CHAR(39) || :demo_wh || CHAR(39) || ' '
   || 'AND NOT EXISTS (SELECT 1 FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY r '
   || 'WHERE r.TARGET_FQN = w.WAREHOUSE_NAME AND r.ARTIFACT = ''AUTO_SUSPEND'')';

  -- The reverse of every AUTO_SUSPEND change: replay what was recorded, then drop
  -- the recording. Dropping it matters -- leaving the rows behind means the NOT
  -- EXISTS guard on the next press treats 60 as the original value and the change
  -- becomes permanent without anyone choosing that.
  LET undo_susp ARRAY := ARRAY_CONSTRUCT(
      'BEGIN LET c CURSOR FOR SELECT TARGET_FQN, ARGUMENTS FROM ' || :tgt
   || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ' || CHAR(39) || 'WAREHOUSE_SETTING'
   || CHAR(39) || ' AND ARTIFACT = ' || CHAR(39) || 'AUTO_SUSPEND' || CHAR(39) || '; '
   || 'FOR r IN c DO '
   || 'EXECUTE IMMEDIATE ' || CHAR(39) || 'ALTER WAREHOUSE "' || CHAR(39)
   || ' || r.TARGET_FQN || ' || CHAR(39) || '" SET AUTO_SUSPEND = ' || CHAR(39)
   || ' || r.ARGUMENTS; '
   || 'END FOR; END',
      'DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
   || 'WHERE KIND = ' || CHAR(39) || 'WAREHOUSE_SETTING' || CHAR(39)
   || ' AND ARTIFACT = ' || CHAR(39) || 'AUTO_SUSPEND' || CHAR(39));

  -- SAMPLE. Creates its own warehouse to fix, so the mechanism -- change,
  -- record, restore -- is provable without touching anything of the customer's.
  -- INITIALLY_SUSPENDED so it costs nothing: a warehouse bills when it runs, and
  -- this one never does. Registered as FIXTURE_WAREHOUSE, which teardown drops.
  actions := ARRAY_APPEND(:actions, OBJECT_CONSTRUCT(
    'code',   'WH_DEMO',
    'label',  'Change and restore a setting on a throwaway warehouse',
    'tier',   'SAMPLE',
    'effect', 'Records the AUTO_SUSPEND of ' || :demo_wh || ' -- a suspended '
           || 'warehouse this script created for exactly this purpose -- and sets '
           || 'it to 60. None of your warehouses are touched. Press Undo to watch '
           || 'it come back to 900.',
    'undo',   'Undo restores the recorded value. TEARDOWN() drops the warehouse.',
    'est',    0.0,
    'basis',  'One ALTER WAREHOUSE against a warehouse that is suspended and never '
           || 'runs a query. ALTER is metadata; nothing here consumes compute. '
           || 'Earlier this said 0.0 while the action CREATED the warehouse, which '
           || 'started it and cost ~0.02 -- the create moved into the build so the '
           || 'zero is now true.',
    'sql',    ARRAY_CONSTRUCT(
      'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
   || '(TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) SELECT ' || CHAR(39) || :demo_wh
   || CHAR(39) || ', ' || CHAR(39) || 'AUTO_SUSPEND' || CHAR(39) || ', '
   || CHAR(39) || '900' || CHAR(39) || ', ' || CHAR(39) || 'WAREHOUSE_SETTING'
   || CHAR(39) || ' WHERE NOT EXISTS (SELECT 1 FROM ' || :tgt
   || '.ATTACHED_OBJECT_REGISTRY WHERE TARGET_FQN = ' || CHAR(39) || :demo_wh
   || CHAR(39) || ' AND ARTIFACT = ' || CHAR(39) || 'AUTO_SUSPEND' || CHAR(39) || ')',
      'ALTER WAREHOUSE "' || :demo_wh || '" SET AUTO_SUSPEND = 60'),
    'undo_sql', ARRAY_CONSTRUCT(
      'ALTER WAREHOUSE "' || :demo_wh || '" SET AUTO_SUSPEND = 900',
      'DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE TARGET_FQN = '
   || CHAR(39) || :demo_wh || CHAR(39) || ' AND ARTIFACT = ' || CHAR(39)
   || 'AUTO_SUSPEND' || CHAR(39))
  ));

  IF (:susp_n > 0) THEN
    -- LIMITED. One warehouse, the worst offender, named on the button.
    actions := ARRAY_APPEND(:actions, OBJECT_CONSTRUCT(
      'code',   'WH_ONE',
      'label',  'Cut idle time on one warehouse: ' || :worst,
      'tier',   'LIMITED',
      'effect', 'Records ' || :worst || '''s current AUTO_SUSPEND and sets it to '
             || '60 seconds. Queries already running are unaffected -- '
             || 'AUTO_SUSPEND only governs how long it idles before shutting '
             || 'down. The projected saving is the EST_SAVINGS_CREDITS figure '
             || 'for this warehouse on the table above.',
      'undo',   'CALL ' || :tgt || '.TEARDOWN() restores the recorded value, or '
             || 'read it back from ATTACHED_OBJECT_REGISTRY and set it yourself.',
      'est',    0.01,
      'basis',  'One ALTER WAREHOUSE, which is a metadata operation and consumes '
             || 'no compute. The 0.01 is the statement overhead, not the saving.',
      'sql',    ARRAY_CONSTRUCT(
        'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
     || '(TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) '
     || 'SELECT w.WAREHOUSE_NAME, ''AUTO_SUSPEND'', w.AUTO_SUSPEND_SECS::VARCHAR, '
     || '''WAREHOUSE_SETTING'' FROM ' || :tgt || '.WH_INVENTORY w '
     || 'WHERE w.WAREHOUSE_NAME = ''' || :worst || ''' '
     || 'AND NOT EXISTS (SELECT 1 FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY r '
     || 'WHERE r.TARGET_FQN = w.WAREHOUSE_NAME AND r.ARTIFACT = ''AUTO_SUSPEND'')',
        'ALTER WAREHOUSE "' || :worst || '" SET AUTO_SUSPEND = 60'),
      'undo_sql', ARRAY_CONSTRUCT(
        'BEGIN LET c CURSOR FOR SELECT ARGUMENTS FROM ' || :tgt
     || '.ATTACHED_OBJECT_REGISTRY WHERE TARGET_FQN = ' || CHAR(39) || :worst
     || CHAR(39) || ' AND ARTIFACT = ' || CHAR(39) || 'AUTO_SUSPEND' || CHAR(39) || '; '
     || 'FOR r IN c DO '
     || 'EXECUTE IMMEDIATE ' || CHAR(39) || 'ALTER WAREHOUSE "' || :worst
     || '" SET AUTO_SUSPEND = ' || CHAR(39) || ' || r.ARGUMENTS; '
     || 'END FOR; END',
        'DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE TARGET_FQN = '
     || CHAR(39) || :worst || CHAR(39) || ' AND ARTIFACT = ' || CHAR(39)
     || 'AUTO_SUSPEND' || CHAR(39))
    ));

    -- PRODUCTION. The whole flagged set. No EXCEPTION handler on the loop, on
    -- purpose: the build path swallows ALTER failures with WHEN OTHER THEN NULL,
    -- which is defensible for a build and wrong for a button -- RUN_ACTION must
    -- see the failure so it stops and logs it instead of reporting DONE.
    actions := ARRAY_APPEND(:actions, OBJECT_CONSTRUCT(
      'code',   'WH_SUSPEND_ALL',
      'label',  'Cut idle time on all ' || :susp_n || ' flagged warehouse(s)',
      'tier',   'PRODUCTION',
      'effect', 'Records the current AUTO_SUSPEND of every STANDARD warehouse '
             || 'over 300s in the inventory this build snapshotted, then sets '
             || 'each to 60. INTERACTIVE and ADAPTIVE warehouses are excluded -- '
             || 'they are meant to stay resident. Stops at the first failure.',
      'undo',   'CALL ' || :tgt || '.TEARDOWN() restores every recorded value.',
      'est',    ROUND(0.01 * :susp_n, 3),
      'basis',  :susp_n || ' ALTER WAREHOUSE statements at ~0.01 credits of '
             || 'overhead each. ALTER is metadata-only, so this is the cost to '
             || 'apply, not the saving -- the saving is on the table above.',
      'sql',    ARRAY_CONSTRUCT(
        :reg_susp,
        'BEGIN LET c CURSOR FOR SELECT WAREHOUSE_NAME FROM ' || :tgt
     || '.WH_INVENTORY WHERE AUTO_SUSPEND_SECS > 300 '
     || 'AND UPPER(WH_TYPE) = ''STANDARD'' '
     || 'AND WAREHOUSE_NAME <> ' || CHAR(39) || :demo_wh || CHAR(39) || '; '
     || 'FOR r IN c DO '
     || 'EXECUTE IMMEDIATE ''ALTER WAREHOUSE "'' || r.WAREHOUSE_NAME '
     || '|| ''" SET AUTO_SUSPEND = 60''; '
     || 'END FOR; END'),
      'undo_sql', :undo_susp
    ));
  END IF;

  IF (:gen1_n > 0) THEN
    -- On an account whose whole fleet is already Gen2 this button does not appear,
    -- because gen1_n is 0. That was the case here for a long time and it hid a
    -- defect: the Gen1 fixture was being created WITHOUT a GENERATION clause, and
    -- Gen2 is the default for new standard warehouses since the 2026_03 bundle, so
    -- the "Gen1" fixture was a Gen2 warehouse and this action was never exercised.
    -- The fixture now pins GENERATION='1'.
    actions := ARRAY_APPEND(:actions, OBJECT_CONSTRUCT(
      'code',   'WH_GEN2',
      'label',  'Move ' || :gen1_n || ' warehouse(s) to Gen2',
      'tier',   'PRODUCTION',
      'effect', 'Sets GENERATION = ''2'' on every eligible STANDARD warehouse. '
             || 'Gen2 is faster on scans, DELETE, UPDATE and MERGE, and it bills '
             || 'at a HIGHER rate per second -- around 1.35x Gen1 on AWS and GCP, '
             || '1.25x on Azure. So this is not automatically a saving: the work '
             || 'has to finish more than about 26% faster just to cost the same, '
             || 'and on an idle-heavy warehouse it will cost MORE. This button '
             || 'converts every eligible warehouse without checking which side of '
             || 'that line each one falls on, so prefer 24_warehouse_generation, '
             || 'which judges each warehouse on measured utilisation and workload '
             || 'shape, converts only the ones the evidence supports, and measures '
             || 'the result. Snowpark-optimized warehouses and sizes 5X-Large and '
             || 'above are excluded because Gen2 does not support them.',
      'undo',   'Reversible: CALL ' || :tgt || '.TEARDOWN() sets GENERATION back, '
             || 'and Snowflake supports moving from Gen2 to Gen1 directly.',
      'est',    ROUND(0.01 * :gen1_n, 3),
      'basis',  :gen1_n || ' ALTER WAREHOUSE statements, metadata-only. The cost '
             || 'to WATCH FOR is not this: converting a RUNNING warehouse bills '
             || 'both the old and new compute until in-flight queries drain, so '
             || 'the cheapest time to press this is when the fleet is idle.',
      'sql',    ARRAY_CONSTRUCT(
        -- '1' rather than the observed value: SHOW WAREHOUSES reports a blank or
        -- 'None' generation for warehouses predating the column, and restoring
        -- `SET GENERATION = ` would be a syntax error. A non-Gen2 standard
        -- warehouse is a Gen1 warehouse, so that is what gets recorded.
        'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
     || '(TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) '
     || 'SELECT w.WAREHOUSE_NAME, ''GENERATION'', '
     || 'CHAR(39) || ''1'' || CHAR(39), '
     || '''WAREHOUSE_SETTING'' FROM ' || :tgt || '.WH_INVENTORY w '
     || 'WHERE COALESCE(w.GENERATION, '''') NOT IN (''2'') '
     || 'AND UPPER(w.WH_TYPE) = ''STANDARD'' '
     || 'AND UPPER(w.WH_SIZE) NOT IN (''5X-LARGE'', ''6X-LARGE'') '
     || 'AND NOT EXISTS (SELECT 1 FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY r '
     || 'WHERE r.TARGET_FQN = w.WAREHOUSE_NAME AND r.ARTIFACT = ''GENERATION'')',
        'BEGIN LET c CURSOR FOR SELECT WAREHOUSE_NAME FROM ' || :tgt
     || '.WH_INVENTORY WHERE COALESCE(GENERATION, '''') NOT IN (''2'') '
     || 'AND UPPER(WH_TYPE) = ''STANDARD'' '
     || 'AND UPPER(WH_SIZE) NOT IN (''5X-LARGE'', ''6X-LARGE''); '
     || 'FOR r IN c DO '
     || 'EXECUTE IMMEDIATE ''ALTER WAREHOUSE "'' || r.WAREHOUSE_NAME '
     || '|| ''" SET GENERATION = ''''2''''''; '
     || 'END FOR; END'),
      'undo_sql', ARRAY_CONSTRUCT(
        'BEGIN LET c CURSOR FOR SELECT TARGET_FQN, ARGUMENTS FROM ' || :tgt
     || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ' || CHAR(39) || 'WAREHOUSE_SETTING'
     || CHAR(39) || ' AND ARTIFACT = ' || CHAR(39) || 'GENERATION' || CHAR(39) || '; '
     || 'FOR r IN c DO '
     || 'EXECUTE IMMEDIATE ' || CHAR(39) || 'ALTER WAREHOUSE "' || CHAR(39)
     || ' || r.TARGET_FQN || ' || CHAR(39) || '" SET GENERATION = ' || CHAR(39)
     || ' || r.ARGUMENTS; '
     || 'END FOR; END',
        'DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
     || 'WHERE KIND = ' || CHAR(39) || 'WAREHOUSE_SETTING' || CHAR(39)
     || ' AND ARTIFACT = ' || CHAR(39) || 'GENERATION' || CHAR(39))
    ));
  END IF;

  -- ══════════════════════════════════════════════════════════════════════════
  -- STANDING WORKLOAD — TASK_COST_WATCH
  -- ══════════════════════════════════════════════════════════════════════════
  -- Warehouse waste reappears as workloads change, so a one-off saving report
  -- is a moment in time rather than the FinOps practice it should start.

  -- Read warehouse credit rate off the actual warehouse.
  LET cw_wh_size    STRING := 'UNKNOWN';
  LET cw_wh_cph     NUMBER(38,2) := 1.0;
  LET cw_wh_rate_ok BOOLEAN := FALSE;
  BEGIN
    EXECUTE IMMEDIATE 'SHOW WAREHOUSES LIKE ''' || :wh || '''';
    cw_wh_size := (SELECT UPPER(COALESCE(MAX("size"), 'UNKNOWN'))
                FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    cw_wh_cph := CASE :cw_wh_size
        WHEN 'X-SMALL'  THEN 1   WHEN 'XSMALL'    THEN 1
        WHEN 'SMALL'    THEN 2
        WHEN 'MEDIUM'   THEN 4
        WHEN 'LARGE'    THEN 8
        WHEN 'X-LARGE'  THEN 16  WHEN 'XLARGE'    THEN 16
        WHEN '2X-LARGE' THEN 32  WHEN 'XXLARGE'   THEN 32
        WHEN '3X-LARGE' THEN 64  WHEN 'XXXLARGE'  THEN 64
        WHEN '4X-LARGE' THEN 128 WHEN 'XXXXLARGE' THEN 128
        ELSE 1 END;
    cw_wh_rate_ok := (:cw_wh_cph > 1 OR :cw_wh_size IN ('X-SMALL', 'XSMALL'));
  EXCEPTION WHEN OTHER THEN
    cw_wh_size := 'UNREADABLE'; cw_wh_cph := 1.0; cw_wh_rate_ok := FALSE;
  END;

  LET cw_task_fqn STRING := :tgt || '.TASK_COST_WATCH';

  -- Create a procedure the task calls: refreshes the savings summary.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE PROCEDURE ' || :tgt || '.COST_WATCH() '
 || 'RETURNS VARCHAR LANGUAGE SQL AS BEGIN '
 || 'DELETE FROM ' || :tgt || '.SAVINGS_PROJECTIONS; '
 || 'INSERT INTO ' || :tgt || '.SAVINGS_PROJECTIONS '
 || '(WAREHOUSE_NAME, RECOMMENDATION, PROJECTED_SAVINGS_CREDITS) '
 || 'SELECT WAREHOUSE_NAME, RECOMMENDATION, EST_SAVINGS_CREDITS '
 || 'FROM ' || :tgt || '.V_WH_SAVINGS_SUMMARY WHERE RECOMMENDATION != ''OK''; '
 || 'RETURN ''COST_WATCH COMPLETE''; END');

  -- Register in ATTACHED_OBJECT_REGISTRY
  stmts := ARRAY_APPEND(:stmts,
    'DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ''TASK''');
  stmts := ARRAY_APPEND(:stmts,
    'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY (TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) '
 || 'SELECT ''' || :cw_task_fqn || ''', ''TASK_COST_WATCH'', ''USING CRON 0 6 * * * UTC'', ''TASK''');

  -- Create the task (daily at 06:00 UTC)
  --
  -- SUSPEND first. Snowflake refuses to CREATE OR REPLACE a task that is
  -- currently started, and at PRODUCTION tier the previous build deliberately
  -- LEAVES this one running -- so a re-run at PRODUCTION would hit that refusal
  -- on a script whose whole promise is that you can re-run it. IF EXISTS because
  -- the first build has no task to suspend.
  stmts := ARRAY_APPEND(:stmts,
    'ALTER TASK IF EXISTS ' || :cw_task_fqn || ' SUSPEND');
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE TASK ' || :cw_task_fqn || ' WAREHOUSE = ' || :wh
 || ' SCHEDULE = ''USING CRON 0 6 * * * UTC'''
 || ' COMMENT = ''Refreshes savings projections daily so new waste is caught as workloads change.'''
 || ' AS CALL ' || :tgt || '.COST_WATCH()');

  -- RESUME
  stmts := ARRAY_APPEND(:stmts, 'ALTER TASK ' || :cw_task_fqn || ' RESUME');

  -- Tier gate
  LET standing_live_cw BOOLEAN := (:tier = 'PRODUCTION');
  LET runs_per_month_cw NUMBER(38,4) := IFF(:standing_live_cw, 30.4, 0);
  LET cadence_label_cw STRING := 'daily at 06:00 UTC'
    || IFF(:standing_live_cw, '', ', SUSPENDED at ' || :tier || ' tier');
  LET gate_basis_cw STRING := IFF(:standing_live_cw,
      'Left RUNNING because this build is PRODUCTION tier — this is a charge you will see.',
      'SUSPENDED by this build because the tier is ' || :tier || ', not PRODUCTION. '
        || 'At PRODUCTION the same task would fire 30.4 times a month.');

  IF (NOT :standing_live_cw) THEN
    stmts := ARRAY_APPEND(:stmts, 'ALTER TASK ' || :cw_task_fqn || ' SUSPEND');
  END IF;

  -- Measure SECONDS_PER_RUN
  -- Floor the measurement at this build's start. QUERY_HISTORY_BY_SESSION is the
  -- true history of the SESSION, so a re-run into the same schema would otherwise
  -- average in the previous run's calls -- true history of a statement, false
  -- history of the object being priced. Copied from 02, which is where the
  -- measurement pattern above came from; referencing it without declaring it made
  -- the whole plan block fail to compile with "invalid identifier".
  LET build_floor_utc STRING := (
    SELECT TO_CHAR(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP()),
                   'YYYY-MM-DD HH24:MI:SS.FF3'));
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE TABLE ' || :tgt || '.COSTWATCH_RUN_COST '
 || 'COMMENT = ''Measured elapsed time of COST_WATCH(), body of TASK_COST_WATCH.'' AS '
 || 'SELECT COUNT(*) AS RUNS_OBSERVED, '
 || 'ROUND(AVG(TOTAL_ELAPSED_TIME) / 1000.0, 3) AS AVG_SECONDS '
  -- Qualified with the target DATABASE. An unqualified INFORMATION_SCHEMA
  -- resolves against whatever database the session happens to be in, which is
  -- set on a first build and not guaranteed on a re-run -- so the second build
  -- failed with "Invalid identifier INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION"
  -- and gauntlet step 7 caught it. The database is known here; name it.
 || 'FROM TABLE(' || :db || '.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION('
 || 'RESULT_LIMIT => 10000)) '
 || 'WHERE QUERY_TYPE = ''CALL'' '
 || 'AND EXECUTION_STATUS = ''SUCCESS'' '
 || 'AND QUERY_TEXT ILIKE ''%' || :tgt || '.COST_WATCH()%'' '
 || 'AND CONVERT_TIMEZONE(''UTC'', START_TIME)::TIMESTAMP_NTZ >= '''
 || :build_floor_utc || '''::TIMESTAMP_NTZ');

  -- INSERT into STANDING_WORKLOAD
  stmts := ARRAY_APPEND(:stmts,
    'INSERT INTO ' || :tgt || '.STANDING_WORKLOAD '
 || '(KIND, OBJECT_NAME, CADENCE, RUNS_PER_MONTH, SECONDS_PER_RUN, '
 || ' WAREHOUSE_CREDITS_PER_HOUR, MEASURED_INPUT, BASIS, INSTALLED_AT) '
 || 'SELECT ''TASK'', ''TASK_COST_WATCH'', '
 || '  ''' || :cadence_label_cw || ''', '
 || '  ' || :runs_per_month_cw || ', '
 || '  COALESCE(r.AVG_SECONDS, 1.0), '
 || '  ' || :cw_wh_cph || ', '
 || '  CASE WHEN r.AVG_SECONDS IS NOT NULL '
 || '    THEN ''TOTAL_ELAPSED_TIME averaged over '' || r.RUNS_OBSERVED '
 || '      || '' COST_WATCH() call(s) this build made; the task body is that exact call'' '
 || '    ELSE ''no COST_WATCH() call was readable in this session''''s query '
 || 'history, so this uses the 1-warehouse-second floor stated in the plan'' END, '
 || '  ''CRON 0 6 * * * UTC = daily = 30.4 runs/month, times measured seconds '
 || 'per refresh, at ' || :cw_wh_cph || ' credits/hour ('
 || IFF(:cw_wh_rate_ok, :wh || ' is ' || :cw_wh_size,
        'size of ' || :wh || ' unreadable, so 1 credit/hour is a LOWER bound')
 || '). ' || :gate_basis_cw || ''', '
 || '  CURRENT_TIMESTAMP() '
 || 'FROM ' || :tgt || '.COSTWATCH_RUN_COST r');
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
-- The honest shape for a cost solution: a base MEASURED from the account, times a
-- reclaim fraction the CLIENT sets, times their own credit price.
--
-- Note what this does NOT do. It does not claim a saving. The contract is explicit
-- that a saving cannot be measured -- credits before and credits after are both
-- observable, but attributing the difference to the change assumes nothing else in
-- the account moved, which is never true. So the base here is "credits/day
-- currently going to warehouses this run flagged", which is a fact, and the
-- fraction of that you can actually reclaim is a judgement that belongs to you.
--
-- The default reclaim fraction is deliberately low. A generous default is a
-- number an SE would quote in a meeting, and it would be ours rather than theirs.
value_inputs := ARRAY_APPEND(:value_inputs, OBJECT_CONSTRUCT(
  'name', 'reclaim_fraction',
  'value', 0.15, 'default', 0.15, 'units', 'fraction of flagged spend',
  'description', 'How much of the flagged warehouse spend you believe you can '
              || 'actually reclaim. 0.15 is a deliberately conservative placeholder, '
              || 'not a benchmark and not a promise. Set it to your own number -- '
              || 'VALUE_INPUTS records whether you did.'));
value_inputs := ARRAY_APPEND(:value_inputs, OBJECT_CONSTRUCT(
  'name', 'credit_price',
  'value', 3, 'default', 3, 'units', 'currency per credit',
  'description', 'Your contracted price per credit. The 3 is list-price shorthand '
              || 'and is almost certainly not your rate; it is on your contract.'));
value_inputs := ARRAY_APPEND(:value_inputs, OBJECT_CONSTRUCT(
  'name', 'days_per_year',
  'value', 365, 'default', 365, 'units', 'days',
  'description', 'Annualisation factor. Lower it if the flagged warehouses only '
              || 'run on business days.'));

-- Measured at BUILD time from the view this solution just created, so the number
-- is this account's rather than an assumption. DIV0 because a window with no
-- credit history must produce 0, not an error.
value_base := ARRAY_APPEND(:value_base, OBJECT_CONSTRUCT(
  'metric', 'flagged_warehouse_credits_per_day',
  'units', 'credits/day',
  'sql', 'SELECT ROUND(DIV0(SUM(CREDITS_USED), NULLIF(MAX(ACTIVE_DAYS), 0)), 4) '
      || 'FROM ' || :tgt || '.V_WH_SAVINGS_SUMMARY '
      || 'WHERE RECOMMENDATION IS NOT NULL AND RECOMMENDATION <> ''none''',
  'derivation', 'Total credits over the discovery window for warehouses this run '
             || 'flagged, divided by the days they were active. Read from '
             || 'ACCOUNT_USAGE, so it is this account''s real consumption.'));

-- The second base is declared UNMEASURABLE on purpose, and it is the more
-- important line of the two. Whether a warehouse change slows anyone down cannot
-- be established from metering: it needs a before-and-after on queue time and
-- spill that only exists once the change has been live for a while. Printing a
-- number here would be the fabrication this work item exists to prevent.
value_base := ARRAY_APPEND(:value_base, OBJECT_CONSTRUCT(
  'metric', 'performance_risk_of_reclaiming',
  'units', 'queued seconds added',
  'measurable', FALSE,
  'derivation', 'Would require a before-and-after comparison of queue time and '
             || 'spill on the flagged warehouses.',
  'why_not', 'Nothing in metering can tell you whether cutting idle time slows a '
          || 'pipeline down. V_WH_PRESSURE shows the queueing and spill that exist '
          || 'TODAY as counter-evidence, but the effect of a change can only be '
          || 'measured after the change has been live. Re-run MEASURE() and compare '
          || 'V_WH_PRESSURE a week after applying anything.'));

value_lines := ARRAY_APPEND(:value_lines, OBJECT_CONSTRUCT(
  'line', 'Reclaimable warehouse spend',
  'base_metric', 'flagged_warehouse_credits_per_day',
  'rate_input', 'reclaim_fraction',
  'value_input', 'credit_price',
  -- The base is per DAY. Without this the annual cost was being subtracted from a
  -- daily benefit and NET came out plausibly negative.
  'annualise_input', 'days_per_year',
  'horizon', 'per year, at your credit price'));
value_lines := ARRAY_APPEND(:value_lines, OBJECT_CONSTRUCT(
  'line', 'Performance cost of reclaiming it',
  'base_metric', 'performance_risk_of_reclaiming',
  'rate_input', 'reclaim_fraction',
  'value_input', 'credit_price',
  'annualise_input', 'days_per_year',
  'horizon', 'unmeasurable'));

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
-- What would make this Cost Efficiency POC a success, measured against bars
-- derived from THIS account rather than from a pitch.
--
-- EVERY CRITERION IS GATED ON THE SIGNAL IT READS. Discovery probes report
-- which ACCOUNT_USAGE views are accessible; criteria are only declared when
-- the views they depend on were actually built.
--
-- WHAT IS DELIBERATELY NOT HERE. There is no "X% of credits saved" criterion.
-- Savings are PROJECTED from measured events, not measured savings; claiming a
-- projected saving as a result would be measuring the projection, not the
-- outcome. The measured-impact criterion below is deliberately pending until
-- recommendations are applied and enough time passes to compare.

-- ── Coverage: the savings view covers every inventoried warehouse ─────────────
IF (:sig:warehouses::STRING = 'AVAILABLE') THEN
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'COSTEFF_WH_COVERED',
    'label', 'The savings view covers every warehouse in the inventory',
    'why', 'A savings analysis that silently drops warehouses underestimates the '
        || 'estate. If the join between inventory and savings loses rows, the total '
        || 'projected saving is incomplete and could miss the largest contributor.',
    'compare', '=',
    'units', 'warehouses',
    'basis', 'BY_QUERY_ID',
    'target_sql', 'SELECT COUNT(*) FROM ' || :tgt || '.WH_INVENTORY',
    'actual_sql', 'SELECT COUNT(*) FROM ' || :tgt || '.V_WH_SAVINGS_SUMMARY',
    'target_derivation', 'The row count of WH_INVENTORY, which is a snapshot of '
        || 'SHOW WAREHOUSES taken at build time. The comparison is equality: every '
        || 'warehouse should appear in the savings view, even if its recommendation is OK.'));

  -- ── Grounded: savings come from measured events, not invented rates ─────────
  -- The previous version of this solution multiplied credits by a fixed
  -- percentage. This version counts actual SUSPEND events and computes idle
  -- seconds from the actual AUTO_SUSPEND setting.
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'COSTEFF_SAVINGS_GROUNDED',
    'label', 'At least one projected saving is derived from measured warehouse events',
    'why', 'A saving expressed as "5% of credits" is a guess; a saving expressed as '
        || '"N suspend events x (AUTO_SUSPEND - 60) seconds x the published credit '
        || 'rate" is arithmetic over measured inputs. This criterion verifies the '
        || 'latter form exists.',
    'compare', '>=',
    'units', 'warehouses with projected savings',
    'basis', 'BY_QUERY_ID',
    'target_sql', 'SELECT LEAST(1, COUNT_IF(EST_SAVINGS_CREDITS > 0)) FROM ' || :tgt
        || '.V_WH_SAVINGS_SUMMARY',
    'actual_sql', 'SELECT COUNT(*) FROM ' || :tgt || '.SAVINGS_PROJECTIONS '
        || 'WHERE PROJECTED_SAVINGS_CREDITS > 0',
    'target_derivation', 'At least one warehouse with a nonzero projected saving in '
        || 'V_WH_SAVINGS_SUMMARY. If no warehouse has a recommendation, this account '
        || 'is already well-optimised and the target is zero -- both sides will be '
        || 'zero and the criterion is MET.'));
END IF;

-- ── Measured impact: pending until changes are applied ────────────────────────
IF (:sig:warehouses::STRING = 'AVAILABLE') THEN
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'COSTEFF_MEASURED_IMPACT',
    'label', 'Projected savings are confirmed by actual measured reduction in credits',
    'why', 'A projected saving is a MODEL, not a result. Until the recommended '
        || 'changes are applied and enough time passes to compare before-and-after '
        || 'credit consumption, no saving has been realised.',
    'compare', '>=',
    'units', 'credits saved',
    'basis', 'BY_TIME_WINDOW',
    'target_derivation', 'Would be derived from the difference in credit consumption '
        || 'before and after applying the recommended warehouse changes, over a '
        || 'comparable time window.',
    'pending_reason', 'Savings projections are computed from measured events but the '
        || 'saving itself is a prediction. Confirming it requires applying the '
        || 'recommended AUTO_SUSPEND and Gen2 changes, then comparing credit '
        || 'consumption over a comparable period.',
    'resolves_when', 'Apply the recommended changes (the SAMPLE action does one for you), '
        || 'wait at least ' || :w || ' days, then compare credit consumption. '
        || 'SAVINGS_PROJECTIONS has a MEASURED_SAVINGS_CREDITS column for this.'));
END IF;

-- ── Cost ──────────────────────────────────────────────────────────────────────
IF (:credit_cap > 0) THEN
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'COSTEFF_COST_IN_BUDGET',
    'label', 'Measured steady-state cost stays inside your credit cap',
    'why', 'A POC that cannot state its own running cost cannot be approved for '
        || 'production, and a projection is not a measurement.',
    'compare', '<=',
    'units', 'credits',
    'basis', 'BY_TAG',
    'target_sql', 'SELECT ' || :credit_cap,
    'actual_sql', 'SELECT SUM(CREDITS) FROM ' || :tgt || '.V_COST_LINES '
        || 'WHERE LABEL = ''MEASURED'' AND STATUS = ''LANDED''',
    'target_derivation', 'Your COSTEFF_CREDIT_CAP setting, currently '
        || :credit_cap || ' credits.',
    'pending_reason', 'Warehouse credits reach ACCOUNT_USAGE on a delay, so '
        || 'nothing has been attributed to this run yet. This is an absence of '
        || 'data, not a cost of zero and not a failure.',
    'resolves_when', 'credits land in ACCOUNT_USAGE, typically within 8 hours -- '
        || 'call MEASURE() in this schema after that to fill it in'));
ELSE
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'COSTEFF_COST_IN_BUDGET',
    'label', 'Measured steady-state cost stays inside your credit cap',
    'why', 'A POC that cannot state its own running cost cannot be approved for '
        || 'production.',
    'compare', '<=',
    'units', 'credits',
    'basis', 'BY_TAG',
    'target_derivation', 'No cap was set, so there is no bar to derive.',
    'na_reason', 'COSTEFF_CREDIT_CAP is 0, so no ceiling was declared for this run. '
        || 'Set it and re-run to have this criterion scored. Picking a default '
        || 'ceiling here would invent a standard you did not choose.'));
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
   || 'COMMENT = ''Cost attribution for Warehouse Cost Efficiency. Query '
   || 'ACCOUNT_USAGE.TAG_REFERENCES to find everything this deployment owns.''');
    stmts := ARRAY_APPEND(:stmts,
      'ALTER SCHEMA ' || :tgt || ' SET TAG ' || :tgt || '.ONESHOT_SOLUTION = '
   || '''Warehouse Cost Efficiency''');
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
     || '.ONESHOT_SOLUTION = ''Warehouse Cost Efficiency''');
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
        'FAILURE NOTIFICATION SKIPPED: COSTEFF_NOTIFICATION_INTEGRATION is blank, so '
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
 || '      RETURN ''REFUSED. This build was created with COSTEFF_ALLOW_SAMPLE_ACTIONS = '
 || 'FALSE, so even the seeded-data actions are inert. Re-run the script with it set '
 || 'to TRUE to arm them.''; '
 || '    END IF; '
 || '  ELSE '
 || '    enabled := (SELECT ACTIONS_ENABLED FROM ' || :tgt || '.V_BUILD_CONTEXT LIMIT 1); '
 || '    IF (NOT COALESCE(:enabled, FALSE)) THEN '
 || '      RETURN ''REFUSED. '' || :tier || '' actions touch real data and this build was '
 || 'created with COSTEFF_ALLOW_ACTIONS = FALSE, so nothing in the app can change '
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
 || '      RETURN ''REFUSED. This build was created with COSTEFF_ALLOW_SAMPLE_ACTIONS = FALSE.''; '
 || '    END IF; '
 || '  ELSE '
 || '    enabled := (SELECT ACTIONS_ENABLED FROM ' || :tgt || '.V_BUILD_CONTEXT LIMIT 1); '
 || '    IF (NOT COALESCE(:enabled, FALSE)) THEN '
 || '      RETURN ''REFUSED. This build was created with COSTEFF_ALLOW_ACTIONS = FALSE.''; '
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
          'COSTEFF_ALLOW_ACTIONS is TRUE, so they are ARMED: a user of the dashboard can '
       || 'run them after typing the action code to confirm. Every attempt is recorded '
       || 'in ACTION_LOG.',
          'COSTEFF_ALLOW_ACTIONS is FALSE, so every button is inert and RUN_ACTION refuses. '
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
  -- ui-sources sha256:880f92a810da6e4e
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
    || 'MSBhcyBjb21wb25lbnRzCgpBUFBfSlNfQjY0ID0gIktHWjFibU4wYVc5dUtDbDdJblZ6WlNCemRISnBZM1FpTzJaMWJtTjBhVzl1SUhOaktIVXBlM0psZEhW'
    || 'eWJpQjFKaVoxTGw5ZlpYTk5iMlIxYkdVbUprOWlhbVZqZEM1d2NtOTBiM1I1Y0dVdWFHRnpUM2R1VUhKdmNHVnlkSGt1WTJGc2JDaDFMQ0prWldaaGRXeDBJ'
    || 'aWsvZFM1a1pXWmhkV3gwT25WOWRtRnlJRkZzUFh0bGVIQnZjblJ6T250OWZTeEhiajE3ZlN4SGJEMTdaWGh3YjNKMGN6cDdmWDBzV2oxN2ZUc3ZLaW9LSUNv'
    || 'Z1FHeHBZMlZ1YzJVZ1VtVmhZM1FLSUNvZ2NtVmhZM1F1Y0hKdlpIVmpkR2x2Ymk1dGFXNHVhbk1LSUNvS0lDb2dRMjl3ZVhKcFoyaDBJQ2hqS1NCR1lXTmxZ'
    || 'bTl2YXl3Z1NXNWpMaUJoYm1RZ2FYUnpJR0ZtWm1sc2FXRjBaWE11Q2lBcUNpQXFJRlJvYVhNZ2MyOTFjbU5sSUdOdlpHVWdhWE1nYkdsalpXNXpaV1FnZFc1'
    || 'a1pYSWdkR2hsSUUxSlZDQnNhV05sYm5ObElHWnZkVzVrSUdsdUlIUm9aUW9nS2lCTVNVTkZUbE5GSUdacGJHVWdhVzRnZEdobElISnZiM1FnWkdseVpXTjBi'
    || 'M0o1SUc5bUlIUm9hWE1nYzI5MWNtTmxJSFJ5WldVdUNpQXFMM1poY2lCeGJ6dG1kVzVqZEdsdmJpQjFZeWdwZTJsbUtIRnZLWEpsZEhWeWJpQmFPM0Z2UFRF'
    || 'N2RtRnlJSFU5VTNsdFltOXNMbVp2Y2lnaWNtVmhZM1F1Wld4bGJXVnVkQ0lwTEdROVUzbHRZbTlzTG1admNpZ2ljbVZoWTNRdWNHOXlkR0ZzSWlrc1lUMVRl'
    || 'VzFpYjJ3dVptOXlLQ0p5WldGamRDNW1jbUZuYldWdWRDSXBMR2M5VTNsdFltOXNMbVp2Y2lnaWNtVmhZM1F1YzNSeWFXTjBYMjF2WkdVaUtTeDRQVk41YldK'
    || 'dmJDNW1iM0lvSW5KbFlXTjBMbkJ5YjJacGJHVnlJaWtzUXoxVGVXMWliMnd1Wm05eUtDSnlaV0ZqZEM1d2NtOTJhV1JsY2lJcExGTTlVM2x0WW05c0xtWnZj'
    || 'aWdpY21WaFkzUXVZMjl1ZEdWNGRDSXBMSGM5VTNsdFltOXNMbVp2Y2lnaWNtVmhZM1F1Wm05eWQyRnlaRjl5WldZaUtTeGZQVk41YldKdmJDNW1iM0lvSW5K'
    || 'bFlXTjBMbk4xYzNCbGJuTmxJaWtzVEQxVGVXMWliMnd1Wm05eUtDSnlaV0ZqZEM1dFpXMXZJaWtzVGoxVGVXMWliMnd1Wm05eUtDSnlaV0ZqZEM1c1lYcDVJ'
    || 'aWtzVHoxVGVXMWliMnd1YVhSbGNtRjBiM0k3Wm5WdVkzUnBiMjRnUmlob0tYdHlaWFIxY200Z2FEMDlQVzUxYkd4OGZIUjVjR1Z2WmlCb0lUMGliMkpxWldO'
    || 'MElqOXVkV3hzT2lob1BVOG1KbWhiVDExOGZHaGJJa0JBYVhSbGNtRjBiM0lpWFN4MGVYQmxiMllnYUQwOUltWjFibU4wYVc5dUlqOW9PbTUxYkd3cGZYWmhj'
    || 'aUJMUFh0cGMwMXZkVzUwWldRNlpuVnVZM1JwYjI0b0tYdHlaWFIxY200aE1YMHNaVzV4ZFdWMVpVWnZjbU5sVlhCa1lYUmxPbVoxYm1OMGFXOXVLQ2w3ZlN4'
    || 'bGJuRjFaWFZsVW1Wd2JHRmpaVk4wWVhSbE9tWjFibU4wYVc5dUtDbDdmU3hsYm5GMVpYVmxVMlYwVTNSaGRHVTZablZ1WTNScGIyNG9LWHQ5ZlN4SFBVOWlh'
    || 'bVZqZEM1aGMzTnBaMjRzVmoxN2ZUdG1kVzVqZEdsdmJpQlJLR2dzYXl4WUtYdDBhR2x6TG5CeWIzQnpQV2dzZEdocGN5NWpiMjUwWlhoMFBXc3NkR2hwY3k1'
    || 'eVpXWnpQVllzZEdocGN5NTFjR1JoZEdWeVBWaDhmRXQ5VVM1d2NtOTBiM1I1Y0dVdWFYTlNaV0ZqZEVOdmJYQnZibVZ1ZEQxN2ZTeFJMbkJ5YjNSdmRIbHda'
    || 'UzV6WlhSVGRHRjBaVDFtZFc1amRHbHZiaWhvTEdzcGUybG1LSFI1Y0dWdlppQm9JVDBpYjJKcVpXTjBJaVltZEhsd1pXOW1JR2doUFNKbWRXNWpkR2x2YmlJ'
    || 'bUptZ2hQVzUxYkd3cGRHaHliM2NnUlhKeWIzSW9Jbk5sZEZOMFlYUmxLQzR1TGlrNklIUmhhMlZ6SUdGdUlHOWlhbVZqZENCdlppQnpkR0YwWlNCMllYSnBZ'
    || 'V0pzWlhNZ2RHOGdkWEJrWVhSbElHOXlJR0VnWm5WdVkzUnBiMjRnZDJocFkyZ2djbVYwZFhKdWN5QmhiaUJ2WW1wbFkzUWdiMllnYzNSaGRHVWdkbUZ5YVdG'
    || 'aWJHVnpMaUlwTzNSb2FYTXVkWEJrWVhSbGNpNWxibkYxWlhWbFUyVjBVM1JoZEdVb2RHaHBjeXhvTEdzc0luTmxkRk4wWVhSbElpbDlMRkV1Y0hKdmRHOTBl'
    || 'WEJsTG1admNtTmxWWEJrWVhSbFBXWjFibU4wYVc5dUtHZ3BlM1JvYVhNdWRYQmtZWFJsY2k1bGJuRjFaWFZsUm05eVkyVlZjR1JoZEdVb2RHaHBjeXhvTENK'
    || 'bWIzSmpaVlZ3WkdGMFpTSXBmVHRtZFc1amRHbHZiaUJSWlNncGUzMVJaUzV3Y205MGIzUjVjR1U5VVM1d2NtOTBiM1I1Y0dVN1puVnVZM1JwYjI0Z2EyVW9h'
    || 'Q3hyTEZncGUzUm9hWE11Y0hKdmNITTlhQ3gwYUdsekxtTnZiblJsZUhROWF5eDBhR2x6TG5KbFpuTTlWaXgwYUdsekxuVndaR0YwWlhJOVdIeDhTMzEyWVhJ'
    || 'Z2FtVTlhMlV1Y0hKdmRHOTBlWEJsUFc1bGR5QlJaVHRxWlM1amIyNXpkSEoxWTNSdmNqMXJaU3hIS0dwbExGRXVjSEp2ZEc5MGVYQmxLU3hxWlM1cGMxQjFj'
    || 'bVZTWldGamRFTnZiWEJ2Ym1WdWREMGhNRHQyWVhJZ2RtVTlRWEp5WVhrdWFYTkJjbkpoZVN4TlpUMVBZbXBsWTNRdWNISnZkRzkwZVhCbExtaGhjMDkzYmxC'
    || 'eWIzQmxjblI1TEhobFBYdGpkWEp5Wlc1ME9tNTFiR3g5TEdObFBYdHJaWGs2SVRBc2NtVm1PaUV3TEY5ZmMyVnNaam9oTUN4ZlgzTnZkWEpqWlRvaE1IMDda'
    || 'blZ1WTNScGIyNGdaR1VvYUN4ckxGZ3BlM1poY2lCS0xHVmxQWHQ5TEhSbFBXNTFiR3dzYjJVOWJuVnNiRHRwWmlocklUMXVkV3hzS1dadmNpaEtJR2x1SUdz'
    || 'dWNtVm1JVDA5ZG05cFpDQXdKaVlvYjJVOWF5NXlaV1lwTEdzdWEyVjVJVDA5ZG05cFpDQXdKaVlvZEdVOUlpSXJheTVyWlhrcExHc3BUV1V1WTJGc2JDaHJM'
    || 'RW9wSmlZaFkyVXVhR0Z6VDNkdVVISnZjR1Z5ZEhrb1Npa21KaWhsWlZ0S1hUMXJXMHBkS1R0MllYSWdiR1U5WVhKbmRXMWxiblJ6TG14bGJtZDBhQzB5TzJs'
    || 'bUtHeGxQVDA5TVNsbFpTNWphR2xzWkhKbGJqMVlPMlZzYzJVZ2FXWW9NVHhzWlNsN1ptOXlLSFpoY2lCbVpUMUJjbkpoZVNoc1pTa3NkSFE5TUR0MGREeHNa'
    || 'VHQwZENzcktXWmxXM1IwWFQxaGNtZDFiV1Z1ZEhOYmRIUXJNbDA3WldVdVkyaHBiR1J5Wlc0OVptVjlhV1lvYUNZbWFDNWtaV1poZFd4MFVISnZjSE1wWm05'
    || 'eUtFb2dhVzRnYkdVOWFDNWtaV1poZFd4MFVISnZjSE1zYkdVcFpXVmJTbDA5UFQxMmIybGtJREFtSmlobFpWdEtYVDFzWlZ0S1hTazdjbVYwZFhKdWV5UWtk'
    || 'SGx3Wlc5bU9uVXNkSGx3WlRwb0xHdGxlVHAwWlN4eVpXWTZiMlVzY0hKdmNITTZaV1VzWDI5M2JtVnlPbmhsTG1OMWNuSmxiblI5ZldaMWJtTjBhVzl1SUhK'
    || 'bEtHZ3NheWw3Y21WMGRYSnVleVFrZEhsd1pXOW1PblVzZEhsd1pUcG9MblI1Y0dVc2EyVjVPbXNzY21WbU9tZ3VjbVZtTEhCeWIzQnpPbWd1Y0hKdmNITXNY'
    || 'MjkzYm1WeU9tZ3VYMjkzYm1WeWZYMW1kVzVqZEdsdmJpQktaU2hvS1h0eVpYUjFjbTRnZEhsd1pXOW1JR2c5UFNKdlltcGxZM1FpSmlab0lUMDliblZzYkNZ'
    || 'bWFDNGtKSFI1Y0dWdlpqMDlQWFY5Wm5WdVkzUnBiMjRnWW1Vb2FDbDdkbUZ5SUdzOWV5STlJam9pUFRBaUxDSTZJam9pUFRJaWZUdHlaWFIxY200aUpDSXJh'
    || 'QzV5WlhCc1lXTmxLQzliUFRwZEwyY3NablZ1WTNScGIyNG9XQ2w3Y21WMGRYSnVJR3RiV0YxOUtYMTJZWElnSkdVOUwxd3ZLeTluTzJaMWJtTjBhVzl1SUdW'
    || 'MEtHZ3NheWw3Y21WMGRYSnVJSFI1Y0dWdlppQm9QVDBpYjJKcVpXTjBJaVltYUNFOVBXNTFiR3dtSm1ndWEyVjVJVDF1ZFd4c1AySmxLQ0lpSzJndWEyVjVL'
    || 'VHByTG5SdlUzUnlhVzVuS0RNMktYMW1kVzVqZEdsdmJpQndkQ2hvTEdzc1dDeEtMR1ZsS1h0MllYSWdkR1U5ZEhsd1pXOW1JR2c3S0hSbFBUMDlJblZ1WkdW'
    || 'bWFXNWxaQ0o4ZkhSbFBUMDlJbUp2YjJ4bFlXNGlLU1ltS0dnOWJuVnNiQ2s3ZG1GeUlHOWxQU0V4TzJsbUtHZzlQVDF1ZFd4c0tXOWxQU0V3TzJWc2MyVWdj'
    || 'M2RwZEdOb0tIUmxLWHRqWVhObEluTjBjbWx1WnlJNlkyRnpaU0p1ZFcxaVpYSWlPbTlsUFNFd08ySnlaV0ZyTzJOaGMyVWliMkpxWldOMElqcHpkMmwwWTJn'
    || 'b2FDNGtKSFI1Y0dWdlppbDdZMkZ6WlNCMU9tTmhjMlVnWkRwdlpUMGhNSDE5YVdZb2IyVXBjbVYwZFhKdUlHOWxQV2dzWldVOVpXVW9iMlVwTEdnOVNqMDlQ'
    || 'U0lpUHlJdUlpdGxkQ2h2WlN3d0tUcEtMSFpsS0dWbEtUOG9XRDBpSWl4b0lUMXVkV3hzSmlZb1dEMW9MbkpsY0d4aFkyVW9KR1VzSWlRbUx5SXBLeUl2SWlr'
    || 'c2NIUW9aV1VzYXl4WUxDSWlMR1oxYm1OMGFXOXVLSFIwS1h0eVpYUjFjbTRnZEhSOUtTazZaV1VoUFc1MWJHd21KaWhLWlNobFpTa21KaWhsWlQxeVpTaGxa'
    || 'U3hZS3lnaFpXVXVhMlY1Zkh4dlpTWW1iMlV1YTJWNVBUMDlaV1V1YTJWNVB5SWlPaWdpSWl0bFpTNXJaWGtwTG5KbGNHeGhZMlVvSkdVc0lpUW1MeUlwS3lJ'
    || 'dklpa3JhQ2twTEdzdWNIVnphQ2hsWlNrcExERTdhV1lvYjJVOU1DeEtQVW85UFQwaUlqOGlMaUk2U2lzaU9pSXNkbVVvYUNrcFptOXlLSFpoY2lCc1pUMHdP'
    || 'MnhsUEdndWJHVnVaM1JvTzJ4bEt5c3BlM1JsUFdoYmJHVmRPM1poY2lCbVpUMUtLMlYwS0hSbExHeGxLVHR2WlNzOWNIUW9kR1VzYXl4WUxHWmxMR1ZsS1gx'
    || 'bGJITmxJR2xtS0dabFBVWW9hQ2tzZEhsd1pXOW1JR1psUFQwaVpuVnVZM1JwYjI0aUtXWnZjaWhvUFdabExtTmhiR3dvYUNrc2JHVTlNRHNoS0hSbFBXZ3Vi'
    || 'bVY0ZENncEtTNWtiMjVsT3lsMFpUMTBaUzUyWVd4MVpTeG1aVDFLSzJWMEtIUmxMR3hsS3lzcExHOWxLejF3ZENoMFpTeHJMRmdzWm1Vc1pXVXBPMlZzYzJV'
    || 'Z2FXWW9kR1U5UFQwaWIySnFaV04wSWlsMGFISnZkeUJyUFZOMGNtbHVaeWhvS1N4RmNuSnZjaWdpVDJKcVpXTjBjeUJoY21VZ2JtOTBJSFpoYkdsa0lHRnpJ'
    || 'R0VnVW1WaFkzUWdZMmhwYkdRZ0tHWnZkVzVrT2lBaUt5aHJQVDA5SWx0dlltcGxZM1FnVDJKcVpXTjBYU0kvSW05aWFtVmpkQ0IzYVhSb0lHdGxlWE1nZXlJ'
    || 'clQySnFaV04wTG10bGVYTW9hQ2t1YW05cGJpZ2lMQ0FpS1NzaWZTSTZheWtySWlrdUlFbG1JSGx2ZFNCdFpXRnVkQ0IwYnlCeVpXNWtaWElnWVNCamIyeHNa'
    || 'V04wYVc5dUlHOW1JR05vYVd4a2NtVnVMQ0IxYzJVZ1lXNGdZWEp5WVhrZ2FXNXpkR1ZoWkM0aUtUdHlaWFIxY200Z2IyVjlablZ1WTNScGIyNGdkM1FvYUN4'
    || 'ckxGZ3BlMmxtS0dnOVBXNTFiR3dwY21WMGRYSnVJR2c3ZG1GeUlFbzlXMTBzWldVOU1EdHlaWFIxY200Z2NIUW9hQ3hLTENJaUxDSWlMR1oxYm1OMGFXOXVL'
    || 'SFJsS1h0eVpYUjFjbTRnYXk1allXeHNLRmdzZEdVc1pXVXJLeWw5S1N4S2ZXWjFibU4wYVc5dUlFZGxLR2dwZTJsbUtHZ3VYM04wWVhSMWN6MDlQUzB4S1h0'
    || 'MllYSWdhejFvTGw5eVpYTjFiSFE3YXoxcktDa3NheTUwYUdWdUtHWjFibU4wYVc5dUtGZ3BleWhvTGw5emRHRjBkWE05UFQwd2ZIeG9MbDl6ZEdGMGRYTTlQ'
    || 'VDB0TVNrbUppaG9MbDl6ZEdGMGRYTTlNU3hvTGw5eVpYTjFiSFE5V0NsOUxHWjFibU4wYVc5dUtGZ3BleWhvTGw5emRHRjBkWE05UFQwd2ZIeG9MbDl6ZEdG'
    || 'MGRYTTlQVDB0TVNrbUppaG9MbDl6ZEdGMGRYTTlNaXhvTGw5eVpYTjFiSFE5V0NsOUtTeG9MbDl6ZEdGMGRYTTlQVDB0TVNZbUtHZ3VYM04wWVhSMWN6MHdM'
    || 'R2d1WDNKbGMzVnNkRDFyS1gxcFppaG9MbDl6ZEdGMGRYTTlQVDB4S1hKbGRIVnliaUJvTGw5eVpYTjFiSFF1WkdWbVlYVnNkRHQwYUhKdmR5Qm9MbDl5WlhO'
    || 'MWJIUjlkbUZ5SUdkbFBYdGpkWEp5Wlc1ME9tNTFiR3g5TEUwOWUzUnlZVzV6YVhScGIyNDZiblZzYkgwc1NEMTdVbVZoWTNSRGRYSnlaVzUwUkdsemNHRjBZ'
    || 'MmhsY2pwblpTeFNaV0ZqZEVOMWNuSmxiblJDWVhSamFFTnZibVpwWnpwTkxGSmxZV04wUTNWeWNtVnVkRTkzYm1WeU9uaGxmVHRtZFc1amRHbHZiaUJKS0Ns'
    || 'N2RHaHliM2NnUlhKeWIzSW9JbUZqZENndUxpNHBJR2x6SUc1dmRDQnpkWEJ3YjNKMFpXUWdhVzRnY0hKdlpIVmpkR2x2YmlCaWRXbHNaSE1nYjJZZ1VtVmhZ'
    || 'M1F1SWlsOWNtVjBkWEp1SUZvdVEyaHBiR1J5Wlc0OWUyMWhjRHAzZEN4bWIzSkZZV05vT21aMWJtTjBhVzl1S0dnc2F5eFlLWHQzZENob0xHWjFibU4wYVc5'
    || 'dUtDbDdheTVoY0hCc2VTaDBhR2x6TEdGeVozVnRaVzUwY3lsOUxGZ3BmU3hqYjNWdWREcG1kVzVqZEdsdmJpaG9LWHQyWVhJZ2F6MHdPM0psZEhWeWJpQjNk'
    || 'Q2hvTEdaMWJtTjBhVzl1S0NsN2F5c3JmU2tzYTMwc2RHOUJjbkpoZVRwbWRXNWpkR2x2Ymlob0tYdHlaWFIxY200Z2QzUW9hQ3htZFc1amRHbHZiaWhyS1h0'
    || 'eVpYUjFjbTRnYTMwcGZIeGJYWDBzYjI1c2VUcG1kVzVqZEdsdmJpaG9LWHRwWmlnaFNtVW9hQ2twZEdoeWIzY2dSWEp5YjNJb0lsSmxZV04wTGtOb2FXeGtj'
    || 'bVZ1TG05dWJIa2daWGh3WldOMFpXUWdkRzhnY21WalpXbDJaU0JoSUhOcGJtZHNaU0JTWldGamRDQmxiR1Z0Wlc1MElHTm9hV3hrTGlJcE8zSmxkSFZ5YmlC'
    || 'b2ZYMHNXaTVEYjIxd2IyNWxiblE5VVN4YUxrWnlZV2R0Wlc1MFBXRXNXaTVRY205bWFXeGxjajE0TEZvdVVIVnlaVU52YlhCdmJtVnVkRDFyWlN4YUxsTjBj'
    || 'bWxqZEUxdlpHVTlaeXhhTGxOMWMzQmxibk5sUFY4c1dpNWZYMU5GUTFKRlZGOUpUbFJGVWs1QlRGTmZSRTlmVGs5VVgxVlRSVjlQVWw5WlQxVmZWMGxNVEY5'
    || 'Q1JWOUdTVkpGUkQxSUxGb3VZV04wUFVrc1dpNWpiRzl1WlVWc1pXMWxiblE5Wm5WdVkzUnBiMjRvYUN4ckxGZ3BlMmxtS0dnOVBXNTFiR3dwZEdoeWIzY2dS'
    || 'WEp5YjNJb0lsSmxZV04wTG1Oc2IyNWxSV3hsYldWdWRDZ3VMaTRwT2lCVWFHVWdZWEpuZFcxbGJuUWdiWFZ6ZENCaVpTQmhJRkpsWVdOMElHVnNaVzFsYm5R'
    || 'c0lHSjFkQ0I1YjNVZ2NHRnpjMlZrSUNJcmFDc2lMaUlwTzNaaGNpQktQVWNvZTMwc2FDNXdjbTl3Y3lrc1pXVTlhQzVyWlhrc2RHVTlhQzV5WldZc2IyVTlh'
    || 'QzVmYjNkdVpYSTdhV1lvYXlFOWJuVnNiQ2w3YVdZb2F5NXlaV1loUFQxMmIybGtJREFtSmloMFpUMXJMbkpsWml4dlpUMTRaUzVqZFhKeVpXNTBLU3hyTG10'
    || 'bGVTRTlQWFp2YVdRZ01DWW1LR1ZsUFNJaUsyc3VhMlY1S1N4b0xuUjVjR1VtSm1ndWRIbHdaUzVrWldaaGRXeDBVSEp2Y0hNcGRtRnlJR3hsUFdndWRIbHda'
    || 'UzVrWldaaGRXeDBVSEp2Y0hNN1ptOXlLR1psSUdsdUlHc3BUV1V1WTJGc2JDaHJMR1psS1NZbUlXTmxMbWhoYzA5M2JsQnliM0JsY25SNUtHWmxLU1ltS0Vw'
    || 'YlptVmRQV3RiWm1WZFBUMDlkbTlwWkNBd0ppWnNaU0U5UFhadmFXUWdNRDlzWlZ0bVpWMDZhMXRtWlYwcGZYWmhjaUJtWlQxaGNtZDFiV1Z1ZEhNdWJHVnVa'
    || 'M1JvTFRJN2FXWW9abVU5UFQweEtVb3VZMmhwYkdSeVpXNDlXRHRsYkhObElHbG1LREU4Wm1VcGUyeGxQVUZ5Y21GNUtHWmxLVHRtYjNJb2RtRnlJSFIwUFRB'
    || 'N2RIUThabVU3ZEhRckt5bHNaVnQwZEYwOVlYSm5kVzFsYm5SelczUjBLekpkTzBvdVkyaHBiR1J5Wlc0OWJHVjljbVYwZFhKdWV5UWtkSGx3Wlc5bU9uVXNk'
    || 'SGx3WlRwb0xuUjVjR1VzYTJWNU9tVmxMSEpsWmpwMFpTeHdjbTl3Y3pwS0xGOXZkMjVsY2pwdlpYMTlMRm91WTNKbFlYUmxRMjl1ZEdWNGREMW1kVzVqZEds'
    || 'dmJpaG9LWHR5WlhSMWNtNGdhRDE3SkNSMGVYQmxiMlk2VXl4ZlkzVnljbVZ1ZEZaaGJIVmxPbWdzWDJOMWNuSmxiblJXWVd4MVpUSTZhQ3hmZEdoeVpXRmtR'
    || 'MjkxYm5RNk1DeFFjbTkyYVdSbGNqcHVkV3hzTEVOdmJuTjFiV1Z5T201MWJHd3NYMlJsWm1GMWJIUldZV3gxWlRwdWRXeHNMRjluYkc5aVlXeE9ZVzFsT201'
    || 'MWJHeDlMR2d1VUhKdmRtbGtaWEk5ZXlRa2RIbHdaVzltT2tNc1gyTnZiblJsZUhRNmFIMHNhQzVEYjI1emRXMWxjajFvZlN4YUxtTnlaV0YwWlVWc1pXMWxi'
    || 'blE5WkdVc1dpNWpjbVZoZEdWR1lXTjBiM0o1UFdaMWJtTjBhVzl1S0dncGUzWmhjaUJyUFdSbExtSnBibVFvYm5Wc2JDeG9LVHR5WlhSMWNtNGdheTUwZVhC'
    || 'bFBXZ3NhMzBzV2k1amNtVmhkR1ZTWldZOVpuVnVZM1JwYjI0b0tYdHlaWFIxY201N1kzVnljbVZ1ZERwdWRXeHNmWDBzV2k1bWIzSjNZWEprVW1WbVBXWjFi'
    || 'bU4wYVc5dUtHZ3BlM0psZEhWeWJuc2tKSFI1Y0dWdlpqcDNMSEpsYm1SbGNqcG9mWDBzV2k1cGMxWmhiR2xrUld4bGJXVnVkRDFLWlN4YUxteGhlbms5Wm5W'
    || 'dVkzUnBiMjRvYUNsN2NtVjBkWEp1ZXlRa2RIbHdaVzltT2s0c1gzQmhlV3h2WVdRNmUxOXpkR0YwZFhNNkxURXNYM0psYzNWc2REcG9mU3hmYVc1cGREcEha'
    || 'WDE5TEZvdWJXVnRiejFtZFc1amRHbHZiaWhvTEdzcGUzSmxkSFZ5Ym5za0pIUjVjR1Z2WmpwTUxIUjVjR1U2YUN4amIyMXdZWEpsT21zOVBUMTJiMmxrSURB'
    || 'L2JuVnNiRHByZlgwc1dpNXpkR0Z5ZEZSeVlXNXphWFJwYjI0OVpuVnVZM1JwYjI0b2FDbDdkbUZ5SUdzOVRTNTBjbUZ1YzJsMGFXOXVPMDB1ZEhKaGJuTnBk'
    || 'R2x2YmoxN2ZUdDBjbmw3YUNncGZXWnBibUZzYkhsN1RTNTBjbUZ1YzJsMGFXOXVQV3Q5ZlN4YUxuVnVjM1JoWW14bFgyRmpkRDFKTEZvdWRYTmxRMkZzYkdK'
    || 'aFkyczlablZ1WTNScGIyNG9hQ3hyS1h0eVpYUjFjbTRnWjJVdVkzVnljbVZ1ZEM1MWMyVkRZV3hzWW1GamF5aG9MR3NwZlN4YUxuVnpaVU52Ym5SbGVIUTla'
    || 'blZ1WTNScGIyNG9hQ2w3Y21WMGRYSnVJR2RsTG1OMWNuSmxiblF1ZFhObFEyOXVkR1Y0ZENob0tYMHNXaTUxYzJWRVpXSjFaMVpoYkhWbFBXWjFibU4wYVc5'
    || 'dUtDbDdmU3hhTG5WelpVUmxabVZ5Y21Wa1ZtRnNkV1U5Wm5WdVkzUnBiMjRvYUNsN2NtVjBkWEp1SUdkbExtTjFjbkpsYm5RdWRYTmxSR1ZtWlhKeVpXUldZ'
    || 'V3gxWlNob0tYMHNXaTUxYzJWRlptWmxZM1E5Wm5WdVkzUnBiMjRvYUN4cktYdHlaWFIxY200Z1oyVXVZM1Z5Y21WdWRDNTFjMlZGWm1abFkzUW9hQ3hyS1gw'
    || 'c1dpNTFjMlZKWkQxbWRXNWpkR2x2YmlncGUzSmxkSFZ5YmlCblpTNWpkWEp5Wlc1MExuVnpaVWxrS0NsOUxGb3VkWE5sU1cxd1pYSmhkR2wyWlVoaGJtUnNa'
    || 'VDFtZFc1amRHbHZiaWhvTEdzc1dDbDdjbVYwZFhKdUlHZGxMbU4xY25KbGJuUXVkWE5sU1cxd1pYSmhkR2wyWlVoaGJtUnNaU2hvTEdzc1dDbDlMRm91ZFhO'
    || 'bFNXNXpaWEowYVc5dVJXWm1aV04wUFdaMWJtTjBhVzl1S0dnc2F5bDdjbVYwZFhKdUlHZGxMbU4xY25KbGJuUXVkWE5sU1c1elpYSjBhVzl1UldabVpXTjBL'
    || 'R2dzYXlsOUxGb3VkWE5sVEdGNWIzVjBSV1ptWldOMFBXWjFibU4wYVc5dUtHZ3NheWw3Y21WMGRYSnVJR2RsTG1OMWNuSmxiblF1ZFhObFRHRjViM1YwUlda'
    || 'bVpXTjBLR2dzYXlsOUxGb3VkWE5sVFdWdGJ6MW1kVzVqZEdsdmJpaG9MR3NwZTNKbGRIVnliaUJuWlM1amRYSnlaVzUwTG5WelpVMWxiVzhvYUN4cktYMHNX'
    || 'aTUxYzJWU1pXUjFZMlZ5UFdaMWJtTjBhVzl1S0dnc2F5eFlLWHR5WlhSMWNtNGdaMlV1WTNWeWNtVnVkQzUxYzJWU1pXUjFZMlZ5S0dnc2F5eFlLWDBzV2k1'
    || 'MWMyVlNaV1k5Wm5WdVkzUnBiMjRvYUNsN2NtVjBkWEp1SUdkbExtTjFjbkpsYm5RdWRYTmxVbVZtS0dncGZTeGFMblZ6WlZOMFlYUmxQV1oxYm1OMGFXOXVL'
    || 'R2dwZTNKbGRIVnliaUJuWlM1amRYSnlaVzUwTG5WelpWTjBZWFJsS0dncGZTeGFMblZ6WlZONWJtTkZlSFJsY201aGJGTjBiM0psUFdaMWJtTjBhVzl1S0dn'
    || 'c2F5eFlLWHR5WlhSMWNtNGdaMlV1WTNWeWNtVnVkQzUxYzJWVGVXNWpSWGgwWlhKdVlXeFRkRzl5WlNob0xHc3NXQ2w5TEZvdWRYTmxWSEpoYm5OcGRHbHZi'
    || 'ajFtZFc1amRHbHZiaWdwZTNKbGRIVnliaUJuWlM1amRYSnlaVzUwTG5WelpWUnlZVzV6YVhScGIyNG9LWDBzV2k1MlpYSnphVzl1UFNJeE9DNHpMakVpTEZw'
    || 'OWRtRnlJRXB2TzJaMWJtTjBhVzl1SUZsc0tDbDdjbVYwZFhKdUlFcHZmSHdvU204OU1TeEhiQzVsZUhCdmNuUnpQWFZqS0NrcExFZHNMbVY0Y0c5eWRITjlM'
    || 'eW9xQ2lBcUlFQnNhV05sYm5ObElGSmxZV04wQ2lBcUlISmxZV04wTFdwemVDMXlkVzUwYVcxbExuQnliMlIxWTNScGIyNHViV2x1TG1wekNpQXFDaUFxSUVO'
    || 'dmNIbHlhV2RvZENBb1l5a2dSbUZqWldKdmIyc3NJRWx1WXk0Z1lXNWtJR2wwY3lCaFptWnBiR2xoZEdWekxnb2dLZ29nS2lCVWFHbHpJSE52ZFhKalpTQmpi'
    || 'MlJsSUdseklHeHBZMlZ1YzJWa0lIVnVaR1Z5SUhSb1pTQk5TVlFnYkdsalpXNXpaU0JtYjNWdVpDQnBiaUIwYUdVS0lDb2dURWxEUlU1VFJTQm1hV3hsSUds'
    || 'dUlIUm9aU0J5YjI5MElHUnBjbVZqZEc5eWVTQnZaaUIwYUdseklITnZkWEpqWlNCMGNtVmxMZ29nS2k5MllYSWdZbTg3Wm5WdVkzUnBiMjRnWVdNb0tYdHBa'
    || 'aWhpYnlseVpYUjFjbTRnUjI0N1ltODlNVHQyWVhJZ2RUMVpiQ2dwTEdROVUzbHRZbTlzTG1admNpZ2ljbVZoWTNRdVpXeGxiV1Z1ZENJcExHRTlVM2x0WW05'
    || 'c0xtWnZjaWdpY21WaFkzUXVabkpoWjIxbGJuUWlLU3huUFU5aWFtVmpkQzV3Y205MGIzUjVjR1V1YUdGelQzZHVVSEp2Y0dWeWRIa3NlRDExTGw5ZlUwVkRV'
    || 'a1ZVWDBsT1ZFVlNUa0ZNVTE5RVQxOU9UMVJmVlZORlgwOVNYMWxQVlY5WFNVeE1YMEpGWDBaSlVrVkVMbEpsWVdOMFEzVnljbVZ1ZEU5M2JtVnlMRU05ZTJ0'
    || 'bGVUb2hNQ3h5WldZNklUQXNYMTl6Wld4bU9pRXdMRjlmYzI5MWNtTmxPaUV3ZlR0bWRXNWpkR2x2YmlCVEtIY3NYeXhNS1h0MllYSWdUaXhQUFh0OUxFWTli'
    || 'blZzYkN4TFBXNTFiR3c3VENFOVBYWnZhV1FnTUNZbUtFWTlJaUlyVENrc1h5NXJaWGtoUFQxMmIybGtJREFtSmloR1BTSWlLMTh1YTJWNUtTeGZMbkpsWmlF'
    || 'OVBYWnZhV1FnTUNZbUtFczlYeTV5WldZcE8yWnZjaWhPSUdsdUlGOHBaeTVqWVd4c0tGOHNUaWttSmlGRExtaGhjMDkzYmxCeWIzQmxjblI1S0U0cEppWW9U'
    || 'MXRPWFQxZlcwNWRLVHRwWmloM0ppWjNMbVJsWm1GMWJIUlFjbTl3Y3lsbWIzSW9UaUJwYmlCZlBYY3VaR1ZtWVhWc2RGQnliM0J6TEY4cFQxdE9YVDA5UFha'
    || 'dmFXUWdNQ1ltS0U5YlRsMDlYMXRPWFNrN2NtVjBkWEp1ZXlRa2RIbHdaVzltT21Rc2RIbHdaVHAzTEd0bGVUcEdMSEpsWmpwTExIQnliM0J6T2s4c1gyOTNi'
    || 'bVZ5T25ndVkzVnljbVZ1ZEgxOWNtVjBkWEp1SUVkdUxrWnlZV2R0Wlc1MFBXRXNSMjR1YW5ONFBWTXNSMjR1YW5ONGN6MVRMRWR1ZlhaaGNpQmxjenRtZFc1'
    || 'amRHbHZiaUJqWXlncGUzSmxkSFZ5YmlCbGMzeDhLR1Z6UFRFc1VXd3VaWGh3YjNKMGN6MWhZeWdwS1N4UmJDNWxlSEJ2Y25SemZYWmhjaUJ2UFdOaktDa3NT'
    || 'Mnc5V1d3b0tUdGpiMjV6ZENCQmREMXpZeWhMYkNrN2RtRnlJRXh5UFh0OUxGaHNQWHRsZUhCdmNuUnpPbnQ5ZlN4Q1pUMTdmU3hhYkQxN1pYaHdiM0owY3pw'
    || 'N2ZYMHNjV3c5ZTMwN0x5b3FDaUFxSUVCc2FXTmxibk5sSUZKbFlXTjBDaUFxSUhOamFHVmtkV3hsY2k1d2NtOWtkV04wYVc5dUxtMXBiaTVxY3dvZ0tnb2dL'
    || 'aUJEYjNCNWNtbG5hSFFnS0dNcElFWmhZMlZpYjI5ckxDQkpibU11SUdGdVpDQnBkSE1nWVdabWFXeHBZWFJsY3k0S0lDb0tJQ29nVkdocGN5QnpiM1Z5WTJV'
    || 'Z1kyOWtaU0JwY3lCc2FXTmxibk5sWkNCMWJtUmxjaUIwYUdVZ1RVbFVJR3hwWTJWdWMyVWdabTkxYm1RZ2FXNGdkR2hsQ2lBcUlFeEpRMFZPVTBVZ1ptbHNa'
    || 'U0JwYmlCMGFHVWdjbTl2ZENCa2FYSmxZM1J2Y25rZ2IyWWdkR2hwY3lCemIzVnlZMlVnZEhKbFpTNEtJQ292ZG1GeUlIUnpPMloxYm1OMGFXOXVJR1JqS0Ns'
    || 'N2NtVjBkWEp1SUhSemZId29kSE05TVN3b1puVnVZM1JwYjI0b2RTbDdablZ1WTNScGIyNGdaQ2hOTEVncGUzWmhjaUJKUFUwdWJHVnVaM1JvTzAwdWNIVnph'
    || 'Q2hJS1R0bE9tWnZjaWc3TUR4Sk95bDdkbUZ5SUdnOVNTMHhQajQrTVN4clBVMWJhRjA3YVdZb01EeDRLR3NzU0NrcFRWdG9YVDFJTEUxYlNWMDlheXhKUFdn'
    || 'N1pXeHpaU0JpY21WaGF5QmxmWDFtZFc1amRHbHZiaUJoS0UwcGUzSmxkSFZ5YmlCTkxteGxibWQwYUQwOVBUQS9iblZzYkRwTld6QmRmV1oxYm1OMGFXOXVJ'
    || 'R2NvVFNsN2FXWW9UUzVzWlc1bmRHZzlQVDB3S1hKbGRIVnliaUJ1ZFd4c08zWmhjaUJJUFUxYk1GMHNTVDFOTG5CdmNDZ3BPMmxtS0VraFBUMUlLWHROV3pC'
    || 'ZFBVazdaVHBtYjNJb2RtRnlJR2c5TUN4clBVMHViR1Z1WjNSb0xGZzlhejQrUGpFN2FEeFlPeWw3ZG1GeUlFbzlNaW9vYUNzeEtTMHhMR1ZsUFUxYlNsMHNk'
    || 'R1U5U2lzeExHOWxQVTFiZEdWZE8ybG1LREErZUNobFpTeEpLU2wwWlR4ckppWXdQbmdvYjJVc1pXVXBQeWhOVzJoZFBXOWxMRTFiZEdWZFBVa3NhRDEwWlNr'
    || 'NktFMWJhRjA5WldVc1RWdEtYVDFKTEdnOVNpazdaV3h6WlNCcFppaDBaVHhySmlZd1BuZ29iMlVzU1NrcFRWdG9YVDF2WlN4TlczUmxYVDFKTEdnOWRHVTda'
    || 'V3h6WlNCaWNtVmhheUJsZlgxeVpYUjFjbTRnU0gxbWRXNWpkR2x2YmlCNEtFMHNTQ2w3ZG1GeUlFazlUUzV6YjNKMFNXNWtaWGd0U0M1emIzSjBTVzVrWlhn'
    || 'N2NtVjBkWEp1SUVraFBUMHdQMGs2VFM1cFpDMUlMbWxrZldsbUtIUjVjR1Z2WmlCd1pYSm1iM0p0WVc1alpUMDlJbTlpYW1WamRDSW1KblI1Y0dWdlppQnda'
    || 'WEptYjNKdFlXNWpaUzV1YjNjOVBTSm1kVzVqZEdsdmJpSXBlM1poY2lCRFBYQmxjbVp2Y20xaGJtTmxPM1V1ZFc1emRHRmliR1ZmYm05M1BXWjFibU4wYVc5'
    || 'dUtDbDdjbVYwZFhKdUlFTXVibTkzS0NsOWZXVnNjMlY3ZG1GeUlGTTlSR0YwWlN4M1BWTXVibTkzS0NrN2RTNTFibk4wWVdKc1pWOXViM2M5Wm5WdVkzUnBi'
    || 'MjRvS1h0eVpYUjFjbTRnVXk1dWIzY29LUzEzZlgxMllYSWdYejFiWFN4TVBWdGRMRTQ5TVN4UFBXNTFiR3dzUmowekxFczlJVEVzUnowaE1TeFdQU0V4TEZF'
    || 'OWRIbHdaVzltSUhObGRGUnBiV1Z2ZFhROVBTSm1kVzVqZEdsdmJpSS9jMlYwVkdsdFpXOTFkRHB1ZFd4c0xGRmxQWFI1Y0dWdlppQmpiR1ZoY2xScGJXVnZk'
    || 'WFE5UFNKbWRXNWpkR2x2YmlJL1kyeGxZWEpVYVcxbGIzVjBPbTUxYkd3c2EyVTlkSGx3Wlc5bUlITmxkRWx0YldWa2FXRjBaVHdpZFNJL2MyVjBTVzF0WldS'
    || 'cFlYUmxPbTUxYkd3N2RIbHdaVzltSUc1aGRtbG5ZWFJ2Y2p3aWRTSW1KbTVoZG1sbllYUnZjaTV6WTJobFpIVnNhVzVuSVQwOWRtOXBaQ0F3SmladVlYWnBa'
    || 'MkYwYjNJdWMyTm9aV1IxYkdsdVp5NXBjMGx1Y0hWMFVHVnVaR2x1WnlFOVBYWnZhV1FnTUNZbWJtRjJhV2RoZEc5eUxuTmphR1ZrZFd4cGJtY3VhWE5KYm5C'
    || 'MWRGQmxibVJwYm1jdVltbHVaQ2h1WVhacFoyRjBiM0l1YzJOb1pXUjFiR2x1WnlrN1puVnVZM1JwYjI0Z2FtVW9UU2w3Wm05eUtIWmhjaUJJUFdFb1RDazdT'
    || 'Q0U5UFc1MWJHdzdLWHRwWmloSUxtTmhiR3hpWVdOclBUMDliblZzYkNsbktFd3BPMlZzYzJVZ2FXWW9TQzV6ZEdGeWRGUnBiV1U4UFUwcFp5aE1LU3hJTG5O'
    || 'dmNuUkpibVJsZUQxSUxtVjRjR2x5WVhScGIyNVVhVzFsTEdRb1h5eElLVHRsYkhObElHSnlaV0ZyTzBnOVlTaE1LWDE5Wm5WdVkzUnBiMjRnZG1Vb1RTbDdh'
    || 'V1lvVmowaE1TeHFaU2hOS1N3aFJ5bHBaaWhoS0Y4cElUMDliblZzYkNsSFBTRXdMRWRsS0UxbEtUdGxiSE5sZTNaaGNpQklQV0VvVENrN1NDRTlQVzUxYkd3'
    || 'bUptZGxLSFpsTEVndWMzUmhjblJVYVcxbExVMHBmWDFtZFc1amRHbHZiaUJOWlNoTkxFZ3BlMGM5SVRFc1ZpWW1LRlk5SVRFc1VXVW9aR1VwTEdSbFBTMHhL'
    || 'U3hMUFNFd08zWmhjaUJKUFVZN2RISjVlMlp2Y2locVpTaElLU3hQUFdFb1h5azdUeUU5UFc1MWJHd21KaWdoS0U4dVpYaHdhWEpoZEdsdmJsUnBiV1UrU0Ns'
    || 'OGZFMG1KaUZpWlNncEtUc3BlM1poY2lCb1BVOHVZMkZzYkdKaFkyczdhV1lvZEhsd1pXOW1JR2c5UFNKbWRXNWpkR2x2YmlJcGUwOHVZMkZzYkdKaFkyczli'
    || 'blZzYkN4R1BVOHVjSEpwYjNKcGRIbE1aWFpsYkR0MllYSWdhejFvS0U4dVpYaHdhWEpoZEdsdmJsUnBiV1U4UFVncE8wZzlkUzUxYm5OMFlXSnNaVjl1YjNj'
    || 'b0tTeDBlWEJsYjJZZ2F6MDlJbVoxYm1OMGFXOXVJajlQTG1OaGJHeGlZV05yUFdzNlR6MDlQV0VvWHlrbUptY29YeWtzYW1Vb1NDbDlaV3h6WlNCbktGOHBP'
    || 'MDg5WVNoZktYMXBaaWhQSVQwOWJuVnNiQ2wyWVhJZ1dEMGhNRHRsYkhObGUzWmhjaUJLUFdFb1RDazdTaUU5UFc1MWJHd21KbWRsS0habExFb3VjM1JoY25S'
    || 'VWFXMWxMVWdwTEZnOUlURjljbVYwZFhKdUlGaDlabWx1WVd4c2VYdFBQVzUxYkd3c1JqMUpMRXM5SVRGOWZYWmhjaUI0WlQwaE1TeGpaVDF1ZFd4c0xHUmxQ'
    || 'UzB4TEhKbFBUVXNTbVU5TFRFN1puVnVZM1JwYjI0Z1ltVW9LWHR5WlhSMWNtNGhLSFV1ZFc1emRHRmliR1ZmYm05M0tDa3RTbVU4Y21VcGZXWjFibU4wYVc5'
    || 'dUlDUmxLQ2w3YVdZb1kyVWhQVDF1ZFd4c0tYdDJZWElnVFQxMUxuVnVjM1JoWW14bFgyNXZkeWdwTzBwbFBVMDdkbUZ5SUVnOUlUQTdkSEo1ZTBnOVkyVW9J'
    || 'VEFzVFNsOVptbHVZV3hzZVh0SVAyVjBLQ2s2S0hobFBTRXhMR05sUFc1MWJHd3BmWDFsYkhObElIaGxQU0V4ZlhaaGNpQmxkRHRwWmloMGVYQmxiMllnYTJV'
    || 'OVBTSm1kVzVqZEdsdmJpSXBaWFE5Wm5WdVkzUnBiMjRvS1h0clpTZ2taU2w5TzJWc2MyVWdhV1lvZEhsd1pXOW1JRTFsYzNOaFoyVkRhR0Z1Ym1Wc1BDSjFJ'
    || 'aWw3ZG1GeUlIQjBQVzVsZHlCTlpYTnpZV2RsUTJoaGJtNWxiQ3gzZEQxd2RDNXdiM0owTWp0d2RDNXdiM0owTVM1dmJtMWxjM05oWjJVOUpHVXNaWFE5Wm5W'
    || 'dVkzUnBiMjRvS1h0M2RDNXdiM04wVFdWemMyRm5aU2h1ZFd4c0tYMTlaV3h6WlNCbGREMW1kVzVqZEdsdmJpZ3BlMUVvSkdVc01DbDlPMloxYm1OMGFXOXVJ'
    || 'RWRsS0UwcGUyTmxQVTBzZUdWOGZDaDRaVDBoTUN4bGRDZ3BLWDFtZFc1amRHbHZiaUJuWlNoTkxFZ3BlMlJsUFZFb1puVnVZM1JwYjI0b0tYdE5LSFV1ZFc1'
    || 'emRHRmliR1ZmYm05M0tDa3BmU3hJS1gxMUxuVnVjM1JoWW14bFgwbGtiR1ZRY21sdmNtbDBlVDAxTEhVdWRXNXpkR0ZpYkdWZlNXMXRaV1JwWVhSbFVISnBi'
    || 'M0pwZEhrOU1TeDFMblZ1YzNSaFlteGxYMHh2ZDFCeWFXOXlhWFI1UFRRc2RTNTFibk4wWVdKc1pWOU9iM0p0WVd4UWNtbHZjbWwwZVQwekxIVXVkVzV6ZEdG'
    || 'aWJHVmZVSEp2Wm1sc2FXNW5QVzUxYkd3c2RTNTFibk4wWVdKc1pWOVZjMlZ5UW14dlkydHBibWRRY21sdmNtbDBlVDB5TEhVdWRXNXpkR0ZpYkdWZlkyRnVZ'
    || 'MlZzUTJGc2JHSmhZMnM5Wm5WdVkzUnBiMjRvVFNsN1RTNWpZV3hzWW1GamF6MXVkV3hzZlN4MUxuVnVjM1JoWW14bFgyTnZiblJwYm5WbFJYaGxZM1YwYVc5'
    || 'dVBXWjFibU4wYVc5dUtDbDdSM3g4UzN4OEtFYzlJVEFzUjJVb1RXVXBLWDBzZFM1MWJuTjBZV0pzWlY5bWIzSmpaVVp5WVcxbFVtRjBaVDFtZFc1amRHbHZi'
    || 'aWhOS1hzd1BrMThmREV5TlR4TlAyTnZibk52YkdVdVpYSnliM0lvSW1admNtTmxSbkpoYldWU1lYUmxJSFJoYTJWeklHRWdjRzl6YVhScGRtVWdhVzUwSUdK'
    || 'bGRIZGxaVzRnTUNCaGJtUWdNVEkxTENCbWIzSmphVzVuSUdaeVlXMWxJSEpoZEdWeklHaHBaMmhsY2lCMGFHRnVJREV5TlNCbWNITWdhWE1nYm05MElITjFj'
    || 'SEJ2Y25SbFpDSXBPbkpsUFRBOFRUOU5ZWFJvTG1ac2IyOXlLREZsTXk5TktUbzFmU3gxTG5WdWMzUmhZbXhsWDJkbGRFTjFjbkpsYm5SUWNtbHZjbWwwZVV4'
    || 'bGRtVnNQV1oxYm1OMGFXOXVLQ2w3Y21WMGRYSnVJRVo5TEhVdWRXNXpkR0ZpYkdWZloyVjBSbWx5YzNSRFlXeHNZbUZqYTA1dlpHVTlablZ1WTNScGIyNG9L'
    || 'WHR5WlhSMWNtNGdZU2hmS1gwc2RTNTFibk4wWVdKc1pWOXVaWGgwUFdaMWJtTjBhVzl1S0UwcGUzTjNhWFJqYUNoR0tYdGpZWE5sSURFNlkyRnpaU0F5T21O'
    || 'aGMyVWdNenAyWVhJZ1NEMHpPMkp5WldGck8yUmxabUYxYkhRNlNEMUdmWFpoY2lCSlBVWTdSajFJTzNSeWVYdHlaWFIxY200Z1RTZ3BmV1pwYm1Gc2JIbDdS'
    || 'ajFKZlgwc2RTNTFibk4wWVdKc1pWOXdZWFZ6WlVWNFpXTjFkR2x2YmoxbWRXNWpkR2x2YmlncGUzMHNkUzUxYm5OMFlXSnNaVjl5WlhGMVpYTjBVR0ZwYm5R'
    || 'OVpuVnVZM1JwYjI0b0tYdDlMSFV1ZFc1emRHRmliR1ZmY25WdVYybDBhRkJ5YVc5eWFYUjVQV1oxYm1OMGFXOXVLRTBzU0NsN2MzZHBkR05vS0UwcGUyTmhj'
    || 'MlVnTVRwallYTmxJREk2WTJGelpTQXpPbU5oYzJVZ05EcGpZWE5sSURVNlluSmxZV3M3WkdWbVlYVnNkRHBOUFROOWRtRnlJRWs5Ump0R1BVMDdkSEo1ZTNK'
    || 'bGRIVnliaUJJS0NsOVptbHVZV3hzZVh0R1BVbDlmU3gxTG5WdWMzUmhZbXhsWDNOamFHVmtkV3hsUTJGc2JHSmhZMnM5Wm5WdVkzUnBiMjRvVFN4SUxFa3Bl'
    || 'M1poY2lCb1BYVXVkVzV6ZEdGaWJHVmZibTkzS0NrN2MzZHBkR05vS0hSNWNHVnZaaUJKUFQwaWIySnFaV04wSWlZbVNTRTlQVzUxYkd3L0tFazlTUzVrWld4'
    || 'aGVTeEpQWFI1Y0dWdlppQkpQVDBpYm5WdFltVnlJaVltTUR4SlAyZ3JTVHBvS1RwSlBXZ3NUU2w3WTJGelpTQXhPblpoY2lCclBTMHhPMkp5WldGck8yTmhj'
    || 'MlVnTWpwclBUSTFNRHRpY21WaGF6dGpZWE5sSURVNmF6MHhNRGN6TnpReE9ESXpPMkp5WldGck8yTmhjMlVnTkRwclBURmxORHRpY21WaGF6dGtaV1poZFd4'
    || 'ME9tczlOV1V6ZlhKbGRIVnliaUJyUFVrcmF5eE5QWHRwWkRwT0t5c3NZMkZzYkdKaFkyczZTQ3h3Y21sdmNtbDBlVXhsZG1Wc09rMHNjM1JoY25SVWFXMWxP'
    || 'a2tzWlhod2FYSmhkR2x2YmxScGJXVTZheXh6YjNKMFNXNWtaWGc2TFRGOUxFaythRDhvVFM1emIzSjBTVzVrWlhnOVNTeGtLRXdzVFNrc1lTaGZLVDA5UFc1'
    || 'MWJHd21KazA5UFQxaEtFd3BKaVlvVmo4b1VXVW9aR1VwTEdSbFBTMHhLVHBXUFNFd0xHZGxLSFpsTEVrdGFDa3BLVG9vVFM1emIzSjBTVzVrWlhnOWF5eGtL'
    || 'RjhzVFNrc1IzeDhTM3g4S0VjOUlUQXNSMlVvVFdVcEtTa3NUWDBzZFM1MWJuTjBZV0pzWlY5emFHOTFiR1JaYVdWc1pEMWlaU3gxTG5WdWMzUmhZbXhsWDNk'
    || 'eVlYQkRZV3hzWW1GamF6MW1kVzVqZEdsdmJpaE5LWHQyWVhJZ1NEMUdPM0psZEhWeWJpQm1kVzVqZEdsdmJpZ3BlM1poY2lCSlBVWTdSajFJTzNSeWVYdHla'
    || 'WFIxY200Z1RTNWhjSEJzZVNoMGFHbHpMR0Z5WjNWdFpXNTBjeWw5Wm1sdVlXeHNlWHRHUFVsOWZYMTlLU2h4YkNrcExIRnNmWFpoY2lCdWN6dG1kVzVqZEds'
    || 'dmJpQm1ZeWdwZTNKbGRIVnliaUJ1YzN4OEtHNXpQVEVzV213dVpYaHdiM0owY3oxa1l5Z3BLU3hhYkM1bGVIQnZjblJ6ZlM4cUtnb2dLaUJBYkdsalpXNXpa'
    || 'U0JTWldGamRBb2dLaUJ5WldGamRDMWtiMjB1Y0hKdlpIVmpkR2x2Ymk1dGFXNHVhbk1LSUNvS0lDb2dRMjl3ZVhKcFoyaDBJQ2hqS1NCR1lXTmxZbTl2YXl3'
    || 'Z1NXNWpMaUJoYm1RZ2FYUnpJR0ZtWm1sc2FXRjBaWE11Q2lBcUNpQXFJRlJvYVhNZ2MyOTFjbU5sSUdOdlpHVWdhWE1nYkdsalpXNXpaV1FnZFc1a1pYSWdk'
    || 'R2hsSUUxSlZDQnNhV05sYm5ObElHWnZkVzVrSUdsdUlIUm9aUW9nS2lCTVNVTkZUbE5GSUdacGJHVWdhVzRnZEdobElISnZiM1FnWkdseVpXTjBiM0o1SUc5'
    || 'bUlIUm9hWE1nYzI5MWNtTmxJSFJ5WldVdUNpQXFMM1poY2lCeWN6dG1kVzVqZEdsdmJpQndZeWdwZTJsbUtISnpLWEpsZEhWeWJpQkNaVHR5Y3oweE8zWmhj'
    || 'aUIxUFZsc0tDa3NaRDFtWXlncE8yWjFibU4wYVc5dUlHRW9aU2w3Wm05eUtIWmhjaUIwUFNKb2RIUndjem92TDNKbFlXTjBhbk11YjNKbkwyUnZZM012WlhK'
    || 'eWIzSXRaR1ZqYjJSbGNpNW9kRzFzUDJsdWRtRnlhV0Z1ZEQwaUsyVXNiajB4TzI0OFlYSm5kVzFsYm5SekxteGxibWQwYUR0dUt5c3BkQ3M5SWlaaGNtZHpX'
    || 'MTA5SWl0bGJtTnZaR1ZWVWtsRGIyMXdiMjVsYm5Rb1lYSm5kVzFsYm5SelcyNWRLVHR5WlhSMWNtNGlUV2x1YVdacFpXUWdVbVZoWTNRZ1pYSnliM0lnSXlJ'
    || 'clpTc2lPeUIyYVhOcGRDQWlLM1FySWlCbWIzSWdkR2hsSUdaMWJHd2diV1Z6YzJGblpTQnZjaUIxYzJVZ2RHaGxJRzV2YmkxdGFXNXBabWxsWkNCa1pYWWda'
    || 'VzUyYVhKdmJtMWxiblFnWm05eUlHWjFiR3dnWlhKeWIzSnpJR0Z1WkNCaFpHUnBkR2x2Ym1Gc0lHaGxiSEJtZFd3Z2QyRnlibWx1WjNNdUluMTJZWElnWnox'
    || 'dVpYY2dVMlYwTEhnOWUzMDdablZ1WTNScGIyNGdReWhsTEhRcGUxTW9aU3gwS1N4VEtHVXJJa05oY0hSMWNtVWlMSFFwZldaMWJtTjBhVzl1SUZNb1pTeDBL'
    || 'WHRtYjNJb2VGdGxYVDEwTEdVOU1EdGxQSFF1YkdWdVozUm9PMlVyS3lsbkxtRmtaQ2gwVzJWZEtYMTJZWElnZHowaEtIUjVjR1Z2WmlCM2FXNWtiM2MrSW5V'
    || 'aWZIeDBlWEJsYjJZZ2QybHVaRzkzTG1SdlkzVnRaVzUwUGlKMUlueDhkSGx3Wlc5bUlIZHBibVJ2ZHk1a2IyTjFiV1Z1ZEM1amNtVmhkR1ZGYkdWdFpXNTBQ'
    || 'aUoxSWlrc1h6MVBZbXBsWTNRdWNISnZkRzkwZVhCbExtaGhjMDkzYmxCeWIzQmxjblI1TEV3OUwxNWJPa0V0V2w5aExYcGNkVEF3UXpBdFhIVXdNRVEyWEhV'
    || 'd01FUTRMVngxTURCR05seDFNREJHT0MxY2RUQXlSa1pjZFRBek56QXRYSFV3TXpkRVhIVXdNemRHTFZ4MU1VWkdSbHgxTWpBd1F5MWNkVEl3TUVSY2RUSXdO'
    || 'ekF0WEhVeU1UaEdYSFV5UXpBd0xWeDFNa1pGUmx4MU16QXdNUzFjZFVRM1JrWmNkVVk1TURBdFhIVkdSRU5HWEhWR1JFWXdMVngxUmtaR1JGMWJPa0V0V2w5'
    || 'aExYcGNkVEF3UXpBdFhIVXdNRVEyWEhVd01FUTRMVngxTURCR05seDFNREJHT0MxY2RUQXlSa1pjZFRBek56QXRYSFV3TXpkRVhIVXdNemRHTFZ4MU1VWkdS'
    || 'bHgxTWpBd1F5MWNkVEl3TUVSY2RUSXdOekF0WEhVeU1UaEdYSFV5UXpBd0xWeDFNa1pGUmx4MU16QXdNUzFjZFVRM1JrWmNkVVk1TURBdFhIVkdSRU5HWEhW'
    || 'R1JFWXdMVngxUmtaR1JGd3RMakF0T1Z4MU1EQkNOMXgxTURNd01DMWNkVEF6TmtaY2RUSXdNMFl0WEhVeU1EUXdYU29rTHl4T1BYdDlMRTg5ZTMwN1puVnVZ'
    || 'M1JwYjI0Z1JpaGxLWHR5WlhSMWNtNGdYeTVqWVd4c0tFOHNaU2svSVRBNlh5NWpZV3hzS0U0c1pTay9JVEU2VEM1MFpYTjBLR1VwUDA5YlpWMDlJVEE2S0U1'
    || 'YlpWMDlJVEFzSVRFcGZXWjFibU4wYVc5dUlFc29aU3gwTEc0c2NpbDdhV1lvYmlFOVBXNTFiR3dtSm00dWRIbHdaVDA5UFRBcGNtVjBkWEp1SVRFN2MzZHBk'
    || 'R05vS0hSNWNHVnZaaUIwS1h0allYTmxJbVoxYm1OMGFXOXVJanBqWVhObEluTjViV0p2YkNJNmNtVjBkWEp1SVRBN1kyRnpaU0ppYjI5c1pXRnVJanB5WlhS'
    || 'MWNtNGdjajhoTVRwdUlUMDliblZzYkQ4aGJpNWhZMk5sY0hSelFtOXZiR1ZoYm5NNktHVTlaUzUwYjB4dmQyVnlRMkZ6WlNncExuTnNhV05sS0RBc05Ta3Na'
    || 'U0U5UFNKa1lYUmhMU0ltSm1VaFBUMGlZWEpwWVMwaUtUdGtaV1poZFd4ME9uSmxkSFZ5YmlFeGZYMW1kVzVqZEdsdmJpQkhLR1VzZEN4dUxISXBlMmxtS0hR'
    || 'OVBUMXVkV3hzZkh4MGVYQmxiMllnZEQ0aWRTSjhmRXNvWlN4MExHNHNjaWtwY21WMGRYSnVJVEE3YVdZb2NpbHlaWFIxY200aE1UdHBaaWh1SVQwOWJuVnNi'
    || 'Q2x6ZDJsMFkyZ29iaTUwZVhCbEtYdGpZWE5sSURNNmNtVjBkWEp1SVhRN1kyRnpaU0EwT25KbGRIVnliaUIwUFQwOUlURTdZMkZ6WlNBMU9uSmxkSFZ5YmlC'
    || 'cGMwNWhUaWgwS1R0allYTmxJRFk2Y21WMGRYSnVJR2x6VG1GT0tIUXBmSHd4UG5SOWNtVjBkWEp1SVRGOVpuVnVZM1JwYjI0Z1ZpaGxMSFFzYml4eUxHd3Nh'
    || 'U3h6S1h0MGFHbHpMbUZqWTJWd2RITkNiMjlzWldGdWN6MTBQVDA5TW54OGREMDlQVE44ZkhROVBUMDBMSFJvYVhNdVlYUjBjbWxpZFhSbFRtRnRaVDF5TEhS'
    || 'b2FYTXVZWFIwY21saWRYUmxUbUZ0WlhOd1lXTmxQV3dzZEdocGN5NXRkWE4wVlhObFVISnZjR1Z5ZEhrOWJpeDBhR2x6TG5CeWIzQmxjblI1VG1GdFpUMWxM'
    || 'SFJvYVhNdWRIbHdaVDEwTEhSb2FYTXVjMkZ1YVhScGVtVlZVa3c5YVN4MGFHbHpMbkpsYlc5MlpVVnRjSFI1VTNSeWFXNW5QWE45ZG1GeUlGRTllMzA3SW1O'
    || 'b2FXeGtjbVZ1SUdSaGJtZGxjbTkxYzJ4NVUyVjBTVzV1WlhKSVZFMU1JR1JsWm1GMWJIUldZV3gxWlNCa1pXWmhkV3gwUTJobFkydGxaQ0JwYm01bGNraFVU'
    || 'VXdnYzNWd2NISmxjM05EYjI1MFpXNTBSV1JwZEdGaWJHVlhZWEp1YVc1bklITjFjSEJ5WlhOelNIbGtjbUYwYVc5dVYyRnlibWx1WnlCemRIbHNaU0l1YzNC'
    || 'c2FYUW9JaUFpS1M1bWIzSkZZV05vS0daMWJtTjBhVzl1S0dVcGUxRmJaVjA5Ym1WM0lGWW9aU3d3TENFeExHVXNiblZzYkN3aE1Td2hNU2w5S1N4Yld5SmhZ'
    || 'Mk5sY0hSRGFHRnljMlYwSWl3aVlXTmpaWEIwTFdOb1lYSnpaWFFpWFN4YkltTnNZWE56VG1GdFpTSXNJbU5zWVhOeklsMHNXeUpvZEcxc1JtOXlJaXdpWm05'
    || 'eUlsMHNXeUpvZEhSd1JYRjFhWFlpTENKb2RIUndMV1Z4ZFdsMklsMWRMbVp2Y2tWaFkyZ29ablZ1WTNScGIyNG9aU2w3ZG1GeUlIUTlaVnN3WFR0UlczUmRQ'
    || 'VzVsZHlCV0tIUXNNU3doTVN4bFd6RmRMRzUxYkd3c0lURXNJVEVwZlNrc1d5SmpiMjUwWlc1MFJXUnBkR0ZpYkdVaUxDSmtjbUZuWjJGaWJHVWlMQ0p6Y0dW'
    || 'c2JFTm9aV05ySWl3aWRtRnNkV1VpWFM1bWIzSkZZV05vS0daMWJtTjBhVzl1S0dVcGUxRmJaVjA5Ym1WM0lGWW9aU3d5TENFeExHVXVkRzlNYjNkbGNrTmhj'
    || 'MlVvS1N4dWRXeHNMQ0V4TENFeEtYMHBMRnNpWVhWMGIxSmxkbVZ5YzJVaUxDSmxlSFJsY201aGJGSmxjMjkxY21ObGMxSmxjWFZwY21Wa0lpd2labTlqZFhO'
    || 'aFlteGxJaXdpY0hKbGMyVnlkbVZCYkhCb1lTSmRMbVp2Y2tWaFkyZ29ablZ1WTNScGIyNG9aU2w3VVZ0bFhUMXVaWGNnVmlobExESXNJVEVzWlN4dWRXeHNM'
    || 'Q0V4TENFeEtYMHBMQ0poYkd4dmQwWjFiR3hUWTNKbFpXNGdZWE41Ym1NZ1lYVjBiMFp2WTNWeklHRjFkRzlRYkdGNUlHTnZiblJ5YjJ4eklHUmxabUYxYkhR'
    || 'Z1pHVm1aWElnWkdsellXSnNaV1FnWkdsellXSnNaVkJwWTNSMWNtVkpibEJwWTNSMWNtVWdaR2x6WVdKc1pWSmxiVzkwWlZCc1lYbGlZV05ySUdadmNtMU9i'
    || 'MVpoYkdsa1lYUmxJR2hwWkdSbGJpQnNiMjl3SUc1dlRXOWtkV3hsSUc1dlZtRnNhV1JoZEdVZ2IzQmxiaUJ3YkdGNWMwbHViR2x1WlNCeVpXRmtUMjVzZVNC'
    || 'eVpYRjFhWEpsWkNCeVpYWmxjbk5sWkNCelkyOXdaV1FnYzJWaGJXeGxjM01nYVhSbGJWTmpiM0JsSWk1emNHeHBkQ2dpSUNJcExtWnZja1ZoWTJnb1puVnVZ'
    || 'M1JwYjI0b1pTbDdVVnRsWFQxdVpYY2dWaWhsTERNc0lURXNaUzUwYjB4dmQyVnlRMkZ6WlNncExHNTFiR3dzSVRFc0lURXBmU2tzV3lKamFHVmphMlZrSWl3'
    || 'aWJYVnNkR2x3YkdVaUxDSnRkWFJsWkNJc0luTmxiR1ZqZEdWa0lsMHVabTl5UldGamFDaG1kVzVqZEdsdmJpaGxLWHRSVzJWZFBXNWxkeUJXS0dVc015d2hN'
    || 'Q3hsTEc1MWJHd3NJVEVzSVRFcGZTa3NXeUpqWVhCMGRYSmxJaXdpWkc5M2JteHZZV1FpWFM1bWIzSkZZV05vS0daMWJtTjBhVzl1S0dVcGUxRmJaVjA5Ym1W'
    || 'M0lGWW9aU3cwTENFeExHVXNiblZzYkN3aE1Td2hNU2w5S1N4YkltTnZiSE1pTENKeWIzZHpJaXdpYzJsNlpTSXNJbk53WVc0aVhTNW1iM0pGWVdOb0tHWjFi'
    || 'bU4wYVc5dUtHVXBlMUZiWlYwOWJtVjNJRllvWlN3MkxDRXhMR1VzYm5Wc2JDd2hNU3doTVNsOUtTeGJJbkp2ZDFOd1lXNGlMQ0p6ZEdGeWRDSmRMbVp2Y2tW'
    || 'aFkyZ29ablZ1WTNScGIyNG9aU2w3VVZ0bFhUMXVaWGNnVmlobExEVXNJVEVzWlM1MGIweHZkMlZ5UTJGelpTZ3BMRzUxYkd3c0lURXNJVEVwZlNrN2RtRnlJ'
    || 'RkZsUFM5YlhDMDZYU2hiWVMxNlhTa3ZaenRtZFc1amRHbHZiaUJyWlNobEtYdHlaWFIxY200Z1pWc3hYUzUwYjFWd2NHVnlRMkZ6WlNncGZTSmhZMk5sYm5R'
    || 'dGFHVnBaMmgwSUdGc2FXZHViV1Z1ZEMxaVlYTmxiR2x1WlNCaGNtRmlhV010Wm05eWJTQmlZWE5sYkdsdVpTMXphR2xtZENCallYQXRhR1ZwWjJoMElHTnNh'
    || 'WEF0Y0dGMGFDQmpiR2x3TFhKMWJHVWdZMjlzYjNJdGFXNTBaWEp3YjJ4aGRHbHZiaUJqYjJ4dmNpMXBiblJsY25CdmJHRjBhVzl1TFdacGJIUmxjbk1nWTI5'
    || 'c2IzSXRjSEp2Wm1sc1pTQmpiMnh2Y2kxeVpXNWtaWEpwYm1jZ1pHOXRhVzVoYm5RdFltRnpaV3hwYm1VZ1pXNWhZbXhsTFdKaFkydG5jbTkxYm1RZ1ptbHNi'
    || 'QzF2Y0dGamFYUjVJR1pwYkd3dGNuVnNaU0JtYkc5dlpDMWpiMnh2Y2lCbWJHOXZaQzF2Y0dGamFYUjVJR1p2Ym5RdFptRnRhV3g1SUdadmJuUXRjMmw2WlNC'
    || 'bWIyNTBMWE5wZW1VdFlXUnFkWE4wSUdadmJuUXRjM1J5WlhSamFDQm1iMjUwTFhOMGVXeGxJR1p2Ym5RdGRtRnlhV0Z1ZENCbWIyNTBMWGRsYVdkb2RDQm5i'
    || 'SGx3YUMxdVlXMWxJR2RzZVhCb0xXOXlhV1Z1ZEdGMGFXOXVMV2h2Y21sNmIyNTBZV3dnWjJ4NWNHZ3RiM0pwWlc1MFlYUnBiMjR0ZG1WeWRHbGpZV3dnYUc5'
    || 'eWFYb3RZV1IyTFhnZ2FHOXlhWG90YjNKcFoybHVMWGdnYVcxaFoyVXRjbVZ1WkdWeWFXNW5JR3hsZEhSbGNpMXpjR0ZqYVc1bklHeHBaMmgwYVc1bkxXTnZi'
    || 'Rzl5SUcxaGNtdGxjaTFsYm1RZ2JXRnlhMlZ5TFcxcFpDQnRZWEpyWlhJdGMzUmhjblFnYjNabGNteHBibVV0Y0c5emFYUnBiMjRnYjNabGNteHBibVV0ZEdo'
    || 'cFkydHVaWE56SUhCaGFXNTBMVzl5WkdWeUlIQmhibTl6WlMweElIQnZhVzUwWlhJdFpYWmxiblJ6SUhKbGJtUmxjbWx1WnkxcGJuUmxiblFnYzJoaGNHVXRj'
    || 'bVZ1WkdWeWFXNW5JSE4wYjNBdFkyOXNiM0lnYzNSdmNDMXZjR0ZqYVhSNUlITjBjbWxyWlhSb2NtOTFaMmd0Y0c5emFYUnBiMjRnYzNSeWFXdGxkR2h5YjNW'
    || 'bmFDMTBhR2xqYTI1bGMzTWdjM1J5YjJ0bExXUmhjMmhoY25KaGVTQnpkSEp2YTJVdFpHRnphRzltWm5ObGRDQnpkSEp2YTJVdGJHbHVaV05oY0NCemRISnZh'
    || 'MlV0YkdsdVpXcHZhVzRnYzNSeWIydGxMVzFwZEdWeWJHbHRhWFFnYzNSeWIydGxMVzl3WVdOcGRIa2djM1J5YjJ0bExYZHBaSFJvSUhSbGVIUXRZVzVqYUc5'
    || 'eUlIUmxlSFF0WkdWamIzSmhkR2x2YmlCMFpYaDBMWEpsYm1SbGNtbHVaeUIxYm1SbGNteHBibVV0Y0c5emFYUnBiMjRnZFc1a1pYSnNhVzVsTFhSb2FXTnJi'
    || 'bVZ6Y3lCMWJtbGpiMlJsTFdKcFpHa2dkVzVwWTI5a1pTMXlZVzVuWlNCMWJtbDBjeTF3WlhJdFpXMGdkaTFoYkhCb1lXSmxkR2xqSUhZdGFHRnVaMmx1WnlC'
    || 'MkxXbGtaVzluY21Gd2FHbGpJSFl0YldGMGFHVnRZWFJwWTJGc0lIWmxZM1J2Y2kxbFptWmxZM1FnZG1WeWRDMWhaSFl0ZVNCMlpYSjBMVzl5YVdkcGJpMTRJ'
    || 'SFpsY25RdGIzSnBaMmx1TFhrZ2QyOXlaQzF6Y0dGamFXNW5JSGR5YVhScGJtY3RiVzlrWlNCNGJXeHVjenA0YkdsdWF5QjRMV2hsYVdkb2RDSXVjM0JzYVhR'
    || 'b0lpQWlLUzVtYjNKRllXTm9LR1oxYm1OMGFXOXVLR1VwZTNaaGNpQjBQV1V1Y21Wd2JHRmpaU2hSWlN4clpTazdVVnQwWFQxdVpYY2dWaWgwTERFc0lURXNa'
    || 'U3h1ZFd4c0xDRXhMQ0V4S1gwcExDSjRiR2x1YXpwaFkzUjFZWFJsSUhoc2FXNXJPbUZ5WTNKdmJHVWdlR3hwYm1zNmNtOXNaU0I0YkdsdWF6cHphRzkzSUho'
    || 'c2FXNXJPblJwZEd4bElIaHNhVzVyT25SNWNHVWlMbk53YkdsMEtDSWdJaWt1Wm05eVJXRmphQ2htZFc1amRHbHZiaWhsS1h0MllYSWdkRDFsTG5KbGNHeGhZ'
    || 'MlVvVVdVc2EyVXBPMUZiZEYwOWJtVjNJRllvZEN3eExDRXhMR1VzSW1oMGRIQTZMeTkzZDNjdWR6TXViM0puTHpFNU9Ua3ZlR3hwYm1zaUxDRXhMQ0V4S1gw'
    || 'cExGc2llRzFzT21KaGMyVWlMQ0o0Yld3NmJHRnVaeUlzSW5odGJEcHpjR0ZqWlNKZExtWnZja1ZoWTJnb1puVnVZM1JwYjI0b1pTbDdkbUZ5SUhROVpTNXla'
    || 'WEJzWVdObEtGRmxMR3RsS1R0UlczUmRQVzVsZHlCV0tIUXNNU3doTVN4bExDSm9kSFJ3T2k4dmQzZDNMbmN6TG05eVp5OVlUVXd2TVRrNU9DOXVZVzFsYzNC'
    || 'aFkyVWlMQ0V4TENFeEtYMHBMRnNpZEdGaVNXNWtaWGdpTENKamNtOXpjMDl5YVdkcGJpSmRMbVp2Y2tWaFkyZ29ablZ1WTNScGIyNG9aU2w3VVZ0bFhUMXVa'
    || 'WGNnVmlobExERXNJVEVzWlM1MGIweHZkMlZ5UTJGelpTZ3BMRzUxYkd3c0lURXNJVEVwZlNrc1VTNTRiR2x1YTBoeVpXWTlibVYzSUZZb0luaHNhVzVyU0hK'
    || 'bFppSXNNU3doTVN3aWVHeHBibXM2YUhKbFppSXNJbWgwZEhBNkx5OTNkM2N1ZHpNdWIzSm5MekU1T1RrdmVHeHBibXNpTENFd0xDRXhLU3hiSW5OeVl5SXNJ'
    || 'bWh5WldZaUxDSmhZM1JwYjI0aUxDSm1iM0p0UVdOMGFXOXVJbDB1Wm05eVJXRmphQ2htZFc1amRHbHZiaWhsS1h0UlcyVmRQVzVsZHlCV0tHVXNNU3doTVN4'
    || 'bExuUnZURzkzWlhKRFlYTmxLQ2tzYm5Wc2JDd2hNQ3doTUNsOUtUdG1kVzVqZEdsdmJpQnFaU2hsTEhRc2JpeHlLWHQyWVhJZ2JEMVJMbWhoYzA5M2JsQnli'
    || 'M0JsY25SNUtIUXBQMUZiZEYwNmJuVnNiRHNvYkNFOVBXNTFiR3cvYkM1MGVYQmxJVDA5TURweWZId2hLREk4ZEM1c1pXNW5kR2dwZkh4MFd6QmRJVDA5SW04'
    || 'aUppWjBXekJkSVQwOUlrOGlmSHgwV3pGZElUMDlJbTRpSmlaMFd6RmRJVDA5SWs0aUtTWW1LRWNvZEN4dUxHd3NjaWttSmlodVBXNTFiR3dwTEhKOGZHdzlQ'
    || 'VDF1ZFd4c1AwWW9kQ2ttSmlodVBUMDliblZzYkQ5bExuSmxiVzkyWlVGMGRISnBZblYwWlNoMEtUcGxMbk5sZEVGMGRISnBZblYwWlNoMExDSWlLMjRwS1Rw'
    || 'c0xtMTFjM1JWYzJWUWNtOXdaWEowZVQ5bFcyd3VjSEp2Y0dWeWRIbE9ZVzFsWFQxdVBUMDliblZzYkQ5c0xuUjVjR1U5UFQwelB5RXhPaUlpT200NktIUTli'
    || 'QzVoZEhSeWFXSjFkR1ZPWVcxbExISTliQzVoZEhSeWFXSjFkR1ZPWVcxbGMzQmhZMlVzYmowOVBXNTFiR3cvWlM1eVpXMXZkbVZCZEhSeWFXSjFkR1VvZENr'
    || 'NktHdzliQzUwZVhCbExHNDliRDA5UFROOGZHdzlQVDAwSmladVBUMDlJVEEvSWlJNklpSXJiaXh5UDJVdWMyVjBRWFIwY21saWRYUmxUbE1vY2l4MExHNHBP'
    || 'bVV1YzJWMFFYUjBjbWxpZFhSbEtIUXNiaWtwS1NsOWRtRnlJSFpsUFhVdVgxOVRSVU5TUlZSZlNVNVVSVkpPUVV4VFgwUlBYMDVQVkY5VlUwVmZUMUpmV1U5'
    || 'VlgxZEpURXhmUWtWZlJrbFNSVVFzVFdVOVUzbHRZbTlzTG1admNpZ2ljbVZoWTNRdVpXeGxiV1Z1ZENJcExIaGxQVk41YldKdmJDNW1iM0lvSW5KbFlXTjBM'
    || 'bkJ2Y25SaGJDSXBMR05sUFZONWJXSnZiQzVtYjNJb0luSmxZV04wTG1aeVlXZHRaVzUwSWlrc1pHVTlVM2x0WW05c0xtWnZjaWdpY21WaFkzUXVjM1J5YVdO'
    || 'MFgyMXZaR1VpS1N4eVpUMVRlVzFpYjJ3dVptOXlLQ0p5WldGamRDNXdjbTltYVd4bGNpSXBMRXBsUFZONWJXSnZiQzVtYjNJb0luSmxZV04wTG5CeWIzWnBa'
    || 'R1Z5SWlrc1ltVTlVM2x0WW05c0xtWnZjaWdpY21WaFkzUXVZMjl1ZEdWNGRDSXBMQ1JsUFZONWJXSnZiQzVtYjNJb0luSmxZV04wTG1admNuZGhjbVJmY21W'
    || 'bUlpa3NaWFE5VTNsdFltOXNMbVp2Y2lnaWNtVmhZM1F1YzNWemNHVnVjMlVpS1N4d2REMVRlVzFpYjJ3dVptOXlLQ0p5WldGamRDNXpkWE53Wlc1elpWOXNh'
    || 'WE4wSWlrc2QzUTlVM2x0WW05c0xtWnZjaWdpY21WaFkzUXViV1Z0YnlJcExFZGxQVk41YldKdmJDNW1iM0lvSW5KbFlXTjBMbXhoZW5raUtTeG5aVDFUZVcx'
    || 'aWIyd3VabTl5S0NKeVpXRmpkQzV2Wm1aelkzSmxaVzRpS1N4TlBWTjViV0p2YkM1cGRHVnlZWFJ2Y2p0bWRXNWpkR2x2YmlCSUtHVXBlM0psZEhWeWJpQmxQ'
    || 'VDA5Ym5Wc2JIeDhkSGx3Wlc5bUlHVWhQU0p2WW1wbFkzUWlQMjUxYkd3NktHVTlUU1ltWlZ0TlhYeDhaVnNpUUVCcGRHVnlZWFJ2Y2lKZExIUjVjR1Z2WmlC'
    || 'bFBUMGlablZ1WTNScGIyNGlQMlU2Ym5Wc2JDbDlkbUZ5SUVrOVQySnFaV04wTG1GemMybG5iaXhvTzJaMWJtTjBhVzl1SUdzb1pTbDdhV1lvYUQwOVBYWnZh'
    || 'V1FnTUNsMGNubDdkR2h5YjNjZ1JYSnliM0lvS1gxallYUmphQ2h1S1h0MllYSWdkRDF1TG5OMFlXTnJMblJ5YVcwb0tTNXRZWFJqYUNndlhHNG9JQ29vWVhR'
    || 'Z0tUOHBMeWs3YUQxMEppWjBXekZkZkh3aUluMXlaWFIxY201Z0NtQXJhQ3RsZlhaaGNpQllQU0V4TzJaMWJtTjBhVzl1SUVvb1pTeDBLWHRwWmlnaFpYeDhX'
    || 'Q2x5WlhSMWNtNGlJanRZUFNFd08zWmhjaUJ1UFVWeWNtOXlMbkJ5WlhCaGNtVlRkR0ZqYTFSeVlXTmxPMFZ5Y205eUxuQnlaWEJoY21WVGRHRmphMVJ5WVdO'
    || 'bFBYWnZhV1FnTUR0MGNubDdhV1lvZENscFppaDBQV1oxYm1OMGFXOXVLQ2w3ZEdoeWIzY2dSWEp5YjNJb0tYMHNUMkpxWldOMExtUmxabWx1WlZCeWIzQmxj'
    || 'blI1S0hRdWNISnZkRzkwZVhCbExDSndjbTl3Y3lJc2UzTmxkRHBtZFc1amRHbHZiaWdwZTNSb2NtOTNJRVZ5Y205eUtDbDlmU2tzZEhsd1pXOW1JRkpsWm14'
    || 'bFkzUTlQU0p2WW1wbFkzUWlKaVpTWldac1pXTjBMbU52Ym5OMGNuVmpkQ2w3ZEhKNWUxSmxabXhsWTNRdVkyOXVjM1J5ZFdOMEtIUXNXMTBwZldOaGRHTm9L'
    || 'SGtwZTNaaGNpQnlQWGw5VW1WbWJHVmpkQzVqYjI1emRISjFZM1FvWlN4YlhTeDBLWDFsYkhObGUzUnllWHQwTG1OaGJHd29LWDFqWVhSamFDaDVLWHR5UFhs'
    || 'OVpTNWpZV3hzS0hRdWNISnZkRzkwZVhCbEtYMWxiSE5sZTNSeWVYdDBhSEp2ZHlCRmNuSnZjaWdwZldOaGRHTm9LSGtwZTNJOWVYMWxLQ2w5ZldOaGRHTm9L'
    || 'SGtwZTJsbUtIa21KbkltSm5SNWNHVnZaaUI1TG5OMFlXTnJQVDBpYzNSeWFXNW5JaWw3Wm05eUtIWmhjaUJzUFhrdWMzUmhZMnN1YzNCc2FYUW9ZQXBnS1N4'
    || 'cFBYSXVjM1JoWTJzdWMzQnNhWFFvWUFwZ0tTeHpQV3d1YkdWdVozUm9MVEVzWXoxcExteGxibWQwYUMweE96RThQWE1tSmpBOFBXTW1KbXhiYzEwaFBUMXBX'
    || 'Mk5kT3lsakxTMDdabTl5S0RzeFBEMXpKaVl3UEQxak8zTXRMU3hqTFMwcGFXWW9iRnR6WFNFOVBXbGJZMTBwZTJsbUtITWhQVDB4Zkh4aklUMDlNU2xrYnlC'
    || 'cFppaHpMUzBzWXkwdExEQStZM3g4YkZ0elhTRTlQV2xiWTEwcGUzWmhjaUJtUFdBS1lDdHNXM05kTG5KbGNHeGhZMlVvSWlCaGRDQnVaWGNnSWl3aUlHRjBJ'
    || 'Q0lwTzNKbGRIVnliaUJsTG1ScGMzQnNZWGxPWVcxbEppWm1MbWx1WTJ4MVpHVnpLQ0k4WVc1dmJubHRiM1Z6UGlJcEppWW9aajFtTG5KbGNHeGhZMlVvSWp4'
    || 'aGJtOXVlVzF2ZFhNK0lpeGxMbVJwYzNCc1lYbE9ZVzFsS1Nrc1puMTNhR2xzWlNneFBEMXpKaVl3UEQxaktUdGljbVZoYTMxOWZXWnBibUZzYkhsN1dEMGhN'
    || 'U3hGY25KdmNpNXdjbVZ3WVhKbFUzUmhZMnRVY21GalpUMXVmWEpsZEhWeWJpaGxQV1UvWlM1a2FYTndiR0Y1VG1GdFpYeDhaUzV1WVcxbE9pSWlLVDlyS0dV'
    || 'cE9pSWlmV1oxYm1OMGFXOXVJR1ZsS0dVcGUzTjNhWFJqYUNobExuUmhaeWw3WTJGelpTQTFPbkpsZEhWeWJpQnJLR1V1ZEhsd1pTazdZMkZ6WlNBeE5qcHla'
    || 'WFIxY200Z2F5Z2lUR0Y2ZVNJcE8yTmhjMlVnTVRNNmNtVjBkWEp1SUdzb0lsTjFjM0JsYm5ObElpazdZMkZ6WlNBeE9UcHlaWFIxY200Z2F5Z2lVM1Z6Y0dW'
    || 'dWMyVk1hWE4wSWlrN1kyRnpaU0F3T21OaGMyVWdNanBqWVhObElERTFPbkpsZEhWeWJpQmxQVW9vWlM1MGVYQmxMQ0V4S1N4bE8yTmhjMlVnTVRFNmNtVjBk'
    || 'WEp1SUdVOVNpaGxMblI1Y0dVdWNtVnVaR1Z5TENFeEtTeGxPMk5oYzJVZ01UcHlaWFIxY200Z1pUMUtLR1V1ZEhsd1pTd2hNQ2tzWlR0a1pXWmhkV3gwT25K'
    || 'bGRIVnliaUlpZlgxbWRXNWpkR2x2YmlCMFpTaGxLWHRwWmlobFBUMXVkV3hzS1hKbGRIVnliaUJ1ZFd4c08ybG1LSFI1Y0dWdlppQmxQVDBpWm5WdVkzUnBi'
    || 'MjRpS1hKbGRIVnliaUJsTG1ScGMzQnNZWGxPWVcxbGZIeGxMbTVoYldWOGZHNTFiR3c3YVdZb2RIbHdaVzltSUdVOVBTSnpkSEpwYm1jaUtYSmxkSFZ5YmlC'
    || 'bE8zTjNhWFJqYUNobEtYdGpZWE5sSUdObE9uSmxkSFZ5YmlKR2NtRm5iV1Z1ZENJN1kyRnpaU0I0WlRweVpYUjFjbTRpVUc5eWRHRnNJanRqWVhObElISmxP'
    || 'bkpsZEhWeWJpSlFjbTltYVd4bGNpSTdZMkZ6WlNCa1pUcHlaWFIxY200aVUzUnlhV04wVFc5a1pTSTdZMkZ6WlNCbGREcHlaWFIxY200aVUzVnpjR1Z1YzJV'
    || 'aU8yTmhjMlVnY0hRNmNtVjBkWEp1SWxOMWMzQmxibk5sVEdsemRDSjlhV1lvZEhsd1pXOW1JR1U5UFNKdlltcGxZM1FpS1hOM2FYUmphQ2hsTGlRa2RIbHda'
    || 'VzltS1h0allYTmxJR0psT25KbGRIVnliaWhsTG1ScGMzQnNZWGxPWVcxbGZId2lRMjl1ZEdWNGRDSXBLeUl1UTI5dWMzVnRaWElpTzJOaGMyVWdTbVU2Y21W'
    || 'MGRYSnVLR1V1WDJOdmJuUmxlSFF1WkdsemNHeGhlVTVoYldWOGZDSkRiMjUwWlhoMElpa3JJaTVRY205MmFXUmxjaUk3WTJGelpTQWtaVHAyWVhJZ2REMWxM'
    || 'bkpsYm1SbGNqdHlaWFIxY200Z1pUMWxMbVJwYzNCc1lYbE9ZVzFsTEdWOGZDaGxQWFF1WkdsemNHeGhlVTVoYldWOGZIUXVibUZ0Wlh4OElpSXNaVDFsSVQw'
    || 'OUlpSS9Ja1p2Y25kaGNtUlNaV1lvSWl0bEt5SXBJam9pUm05eWQyRnlaRkpsWmlJcExHVTdZMkZ6WlNCM2REcHlaWFIxY200Z2REMWxMbVJwYzNCc1lYbE9Z'
    || 'VzFsZkh4dWRXeHNMSFFoUFQxdWRXeHNQM1E2ZEdVb1pTNTBlWEJsS1h4OElrMWxiVzhpTzJOaGMyVWdSMlU2ZEQxbExsOXdZWGxzYjJGa0xHVTlaUzVmYVc1'
    || 'cGREdDBjbmw3Y21WMGRYSnVJSFJsS0dVb2RDa3BmV05oZEdOb2UzMTljbVYwZFhKdUlHNTFiR3g5Wm5WdVkzUnBiMjRnYjJVb1pTbDdkbUZ5SUhROVpTNTBl'
    || 'WEJsTzNOM2FYUmphQ2hsTG5SaFp5bDdZMkZ6WlNBeU5EcHlaWFIxY200aVEyRmphR1VpTzJOaGMyVWdPVHB5WlhSMWNtNG9kQzVrYVhOd2JHRjVUbUZ0Wlh4'
    || 'OElrTnZiblJsZUhRaUtTc2lMa052Ym5OMWJXVnlJanRqWVhObElERXdPbkpsZEhWeWJpaDBMbDlqYjI1MFpYaDBMbVJwYzNCc1lYbE9ZVzFsZkh3aVEyOXVk'
    || 'R1Y0ZENJcEt5SXVVSEp2ZG1sa1pYSWlPMk5oYzJVZ01UZzZjbVYwZFhKdUlrUmxhSGxrY21GMFpXUkdjbUZuYldWdWRDSTdZMkZ6WlNBeE1UcHlaWFIxY200'
    || 'Z1pUMTBMbkpsYm1SbGNpeGxQV1V1WkdsemNHeGhlVTVoYldWOGZHVXVibUZ0Wlh4OElpSXNkQzVrYVhOd2JHRjVUbUZ0Wlh4OEtHVWhQVDBpSWo4aVJtOXlk'
    || 'MkZ5WkZKbFppZ2lLMlVySWlraU9pSkdiM0ozWVhKa1VtVm1JaWs3WTJGelpTQTNPbkpsZEhWeWJpSkdjbUZuYldWdWRDSTdZMkZ6WlNBMU9uSmxkSFZ5YmlC'
    || 'ME8yTmhjMlVnTkRweVpYUjFjbTRpVUc5eWRHRnNJanRqWVhObElETTZjbVYwZFhKdUlsSnZiM1FpTzJOaGMyVWdOanB5WlhSMWNtNGlWR1Y0ZENJN1kyRnpa'
    || 'U0F4TmpweVpYUjFjbTRnZEdVb2RDazdZMkZ6WlNBNE9uSmxkSFZ5YmlCMFBUMDlaR1UvSWxOMGNtbGpkRTF2WkdVaU9pSk5iMlJsSWp0allYTmxJREl5T25K'
    || 'bGRIVnliaUpQWm1aelkzSmxaVzRpTzJOaGMyVWdNVEk2Y21WMGRYSnVJbEJ5YjJacGJHVnlJanRqWVhObElESXhPbkpsZEhWeWJpSlRZMjl3WlNJN1kyRnpa'
    || 'U0F4TXpweVpYUjFjbTRpVTNWemNHVnVjMlVpTzJOaGMyVWdNVGs2Y21WMGRYSnVJbE4xYzNCbGJuTmxUR2x6ZENJN1kyRnpaU0F5TlRweVpYUjFjbTRpVkhK'
    || 'aFkybHVaMDFoY210bGNpSTdZMkZ6WlNBeE9tTmhjMlVnTURwallYTmxJREUzT21OaGMyVWdNanBqWVhObElERTBPbU5oYzJVZ01UVTZhV1lvZEhsd1pXOW1J'
    || 'SFE5UFNKbWRXNWpkR2x2YmlJcGNtVjBkWEp1SUhRdVpHbHpjR3hoZVU1aGJXVjhmSFF1Ym1GdFpYeDhiblZzYkR0cFppaDBlWEJsYjJZZ2REMDlJbk4wY21s'
    || 'dVp5SXBjbVYwZFhKdUlIUjljbVYwZFhKdUlHNTFiR3g5Wm5WdVkzUnBiMjRnYkdVb1pTbDdjM2RwZEdOb0tIUjVjR1Z2WmlCbEtYdGpZWE5sSW1KdmIyeGxZ'
    || 'VzRpT21OaGMyVWliblZ0WW1WeUlqcGpZWE5sSW5OMGNtbHVaeUk2WTJGelpTSjFibVJsWm1sdVpXUWlPbkpsZEhWeWJpQmxPMk5oYzJVaWIySnFaV04wSWpw'
    || 'eVpYUjFjbTRnWlR0a1pXWmhkV3gwT25KbGRIVnliaUlpZlgxbWRXNWpkR2x2YmlCbVpTaGxLWHQyWVhJZ2REMWxMblI1Y0dVN2NtVjBkWEp1S0dVOVpTNXVi'
    || 'MlJsVG1GdFpTa21KbVV1ZEc5TWIzZGxja05oYzJVb0tUMDlQU0pwYm5CMWRDSW1KaWgwUFQwOUltTm9aV05yWW05NElueDhkRDA5UFNKeVlXUnBieUlwZlda'
    || 'MWJtTjBhVzl1SUhSMEtHVXBlM1poY2lCMFBXWmxLR1VwUHlKamFHVmphMlZrSWpvaWRtRnNkV1VpTEc0OVQySnFaV04wTG1kbGRFOTNibEJ5YjNCbGNuUjVS'
    || 'R1Z6WTNKcGNIUnZjaWhsTG1OdmJuTjBjblZqZEc5eUxuQnliM1J2ZEhsd1pTeDBLU3h5UFNJaUsyVmJkRjA3YVdZb0lXVXVhR0Z6VDNkdVVISnZjR1Z5ZEhr'
    || 'b2RDa21KblI1Y0dWdlppQnVQQ0oxSWlZbWRIbHdaVzltSUc0dVoyVjBQVDBpWm5WdVkzUnBiMjRpSmlaMGVYQmxiMllnYmk1elpYUTlQU0ptZFc1amRHbHZi'
    || 'aUlwZTNaaGNpQnNQVzR1WjJWMExHazliaTV6WlhRN2NtVjBkWEp1SUU5aWFtVmpkQzVrWldacGJtVlFjbTl3WlhKMGVTaGxMSFFzZTJOdmJtWnBaM1Z5WVdK'
    || 'c1pUb2hNQ3huWlhRNlpuVnVZM1JwYjI0b0tYdHlaWFIxY200Z2JDNWpZV3hzS0hSb2FYTXBmU3h6WlhRNlpuVnVZM1JwYjI0b2N5bDdjajBpSWl0ekxHa3VZ'
    || 'MkZzYkNoMGFHbHpMSE1wZlgwcExFOWlhbVZqZEM1a1pXWnBibVZRY205d1pYSjBlU2hsTEhRc2UyVnVkVzFsY21GaWJHVTZiaTVsYm5WdFpYSmhZbXhsZlNr'
    || 'c2UyZGxkRlpoYkhWbE9tWjFibU4wYVc5dUtDbDdjbVYwZFhKdUlISjlMSE5sZEZaaGJIVmxPbVoxYm1OMGFXOXVLSE1wZTNJOUlpSXJjMzBzYzNSdmNGUnlZ'
    || 'V05yYVc1bk9tWjFibU4wYVc5dUtDbDdaUzVmZG1Gc2RXVlVjbUZqYTJWeVBXNTFiR3dzWkdWc1pYUmxJR1ZiZEYxOWZYMTlablZ1WTNScGIyNGdTWElvWlNs'
    || 'N1pTNWZkbUZzZFdWVWNtRmphMlZ5Zkh3b1pTNWZkbUZzZFdWVWNtRmphMlZ5UFhSMEtHVXBLWDFtZFc1amRHbHZiaUJ3Y3lobEtYdHBaaWdoWlNseVpYUjFj'
    || 'bTRoTVR0MllYSWdkRDFsTGw5MllXeDFaVlJ5WVdOclpYSTdhV1lvSVhRcGNtVjBkWEp1SVRBN2RtRnlJRzQ5ZEM1blpYUldZV3gxWlNncExISTlJaUk3Y21W'
    || 'MGRYSnVJR1VtSmloeVBXWmxLR1VwUDJVdVkyaGxZMnRsWkQ4aWRISjFaU0k2SW1aaGJITmxJanBsTG5aaGJIVmxLU3hsUFhJc1pTRTlQVzQvS0hRdWMyVjBW'
    || 'bUZzZFdVb1pTa3NJVEFwT2lFeGZXWjFibU4wYVc5dUlFRnlLR1VwZTJsbUtHVTlaWHg4S0hSNWNHVnZaaUJrYjJOMWJXVnVkRHdpZFNJL1pHOWpkVzFsYm5R'
    || 'NmRtOXBaQ0F3S1N4MGVYQmxiMllnWlQ0aWRTSXBjbVYwZFhKdUlHNTFiR3c3ZEhKNWUzSmxkSFZ5YmlCbExtRmpkR2wyWlVWc1pXMWxiblI4ZkdVdVltOWtl'
    || 'WDFqWVhSamFIdHlaWFIxY200Z1pTNWliMlI1ZlgxbWRXNWpkR2x2YmlCeWFTaGxMSFFwZTNaaGNpQnVQWFF1WTJobFkydGxaRHR5WlhSMWNtNGdTU2g3ZlN4'
    || 'MExIdGtaV1poZFd4MFEyaGxZMnRsWkRwMmIybGtJREFzWkdWbVlYVnNkRlpoYkhWbE9uWnZhV1FnTUN4MllXeDFaVHAyYjJsa0lEQXNZMmhsWTJ0bFpEcHVQ'
    || 'ejlsTGw5M2NtRndjR1Z5VTNSaGRHVXVhVzVwZEdsaGJFTm9aV05yWldSOUtYMW1kVzVqZEdsdmJpQm9jeWhsTEhRcGUzWmhjaUJ1UFhRdVpHVm1ZWFZzZEZa'
    || 'aGJIVmxQVDF1ZFd4c1B5SWlPblF1WkdWbVlYVnNkRlpoYkhWbExISTlkQzVqYUdWamEyVmtJVDF1ZFd4c1AzUXVZMmhsWTJ0bFpEcDBMbVJsWm1GMWJIUkRh'
    || 'R1ZqYTJWa08yNDliR1VvZEM1MllXeDFaU0U5Ym5Wc2JEOTBMblpoYkhWbE9tNHBMR1V1WDNkeVlYQndaWEpUZEdGMFpUMTdhVzVwZEdsaGJFTm9aV05yWldR'
    || 'NmNpeHBibWwwYVdGc1ZtRnNkV1U2Yml4amIyNTBjbTlzYkdWa09uUXVkSGx3WlQwOVBTSmphR1ZqYTJKdmVDSjhmSFF1ZEhsd1pUMDlQU0p5WVdScGJ5SS9k'
    || 'QzVqYUdWamEyVmtJVDF1ZFd4c09uUXVkbUZzZFdVaFBXNTFiR3g5ZldaMWJtTjBhVzl1SUcxektHVXNkQ2w3ZEQxMExtTm9aV05yWldRc2RDRTliblZzYkNZ'
    || 'bWFtVW9aU3dpWTJobFkydGxaQ0lzZEN3aE1TbDlablZ1WTNScGIyNGdiR2tvWlN4MEtYdHRjeWhsTEhRcE8zWmhjaUJ1UFd4bEtIUXVkbUZzZFdVcExISTlk'
    || 'QzUwZVhCbE8ybG1LRzRoUFc1MWJHd3BjajA5UFNKdWRXMWlaWElpUHlodVBUMDlNQ1ltWlM1MllXeDFaVDA5UFNJaWZIeGxMblpoYkhWbElUMXVLU1ltS0dV'
    || 'dWRtRnNkV1U5SWlJcmJpazZaUzUyWVd4MVpTRTlQU0lpSzI0bUppaGxMblpoYkhWbFBTSWlLMjRwTzJWc2MyVWdhV1lvY2owOVBTSnpkV0p0YVhRaWZIeHlQ'
    || 'VDA5SW5KbGMyVjBJaWw3WlM1eVpXMXZkbVZCZEhSeWFXSjFkR1VvSW5aaGJIVmxJaWs3Y21WMGRYSnVmWFF1YUdGelQzZHVVSEp2Y0dWeWRIa29JblpoYkhW'
    || 'bElpay9hV2tvWlN4MExuUjVjR1VzYmlrNmRDNW9ZWE5QZDI1UWNtOXdaWEowZVNnaVpHVm1ZWFZzZEZaaGJIVmxJaWttSm1scEtHVXNkQzUwZVhCbExHeGxL'
    || 'SFF1WkdWbVlYVnNkRlpoYkhWbEtTa3NkQzVqYUdWamEyVmtQVDF1ZFd4c0ppWjBMbVJsWm1GMWJIUkRhR1ZqYTJWa0lUMXVkV3hzSmlZb1pTNWtaV1poZFd4'
    || 'MFEyaGxZMnRsWkQwaElYUXVaR1ZtWVhWc2RFTm9aV05yWldRcGZXWjFibU4wYVc5dUlIWnpLR1VzZEN4dUtYdHBaaWgwTG1oaGMwOTNibEJ5YjNCbGNuUjVL'
    || 'Q0oyWVd4MVpTSXBmSHgwTG1oaGMwOTNibEJ5YjNCbGNuUjVLQ0prWldaaGRXeDBWbUZzZFdVaUtTbDdkbUZ5SUhJOWRDNTBlWEJsTzJsbUtDRW9jaUU5UFNK'
    || 'emRXSnRhWFFpSmlaeUlUMDlJbkpsYzJWMElueDhkQzUyWVd4MVpTRTlQWFp2YVdRZ01DWW1kQzUyWVd4MVpTRTlQVzUxYkd3cEtYSmxkSFZ5Ymp0MFBTSWlL'
    || 'MlV1WDNkeVlYQndaWEpUZEdGMFpTNXBibWwwYVdGc1ZtRnNkV1VzYm54OGREMDlQV1V1ZG1Gc2RXVjhmQ2hsTG5aaGJIVmxQWFFwTEdVdVpHVm1ZWFZzZEZa'
    || 'aGJIVmxQWFI5YmoxbExtNWhiV1VzYmlFOVBTSWlKaVlvWlM1dVlXMWxQU0lpS1N4bExtUmxabUYxYkhSRGFHVmphMlZrUFNFaFpTNWZkM0poY0hCbGNsTjBZ'
    || 'WFJsTG1sdWFYUnBZV3hEYUdWamEyVmtMRzRoUFQwaUlpWW1LR1V1Ym1GdFpUMXVLWDFtZFc1amRHbHZiaUJwYVNobExIUXNiaWw3S0hRaFBUMGliblZ0WW1W'
    || 'eUlueDhRWElvWlM1dmQyNWxja1J2WTNWdFpXNTBLU0U5UFdVcEppWW9iajA5Ym5Wc2JEOWxMbVJsWm1GMWJIUldZV3gxWlQwaUlpdGxMbDkzY21Gd2NHVnlV'
    || 'M1JoZEdVdWFXNXBkR2xoYkZaaGJIVmxPbVV1WkdWbVlYVnNkRlpoYkhWbElUMDlJaUlyYmlZbUtHVXVaR1ZtWVhWc2RGWmhiSFZsUFNJaUsyNHBLWDEyWVhJ'
    || 'Z1dHNDlRWEp5WVhrdWFYTkJjbkpoZVR0bWRXNWpkR2x2YmlCM2JpaGxMSFFzYml4eUtYdHBaaWhsUFdVdWIzQjBhVzl1Y3l4MEtYdDBQWHQ5TzJadmNpaDJZ'
    || 'WElnYkQwd08ydzhiaTVzWlc1bmRHZzdiQ3NyS1hSYklpUWlLMjViYkYxZFBTRXdPMlp2Y2lodVBUQTdianhsTG14bGJtZDBhRHR1S3lzcGJEMTBMbWhoYzA5'
    || 'M2JsQnliM0JsY25SNUtDSWtJaXRsVzI1ZExuWmhiSFZsS1N4bFcyNWRMbk5sYkdWamRHVmtJVDA5YkNZbUtHVmJibDB1YzJWc1pXTjBaV1E5YkNrc2JDWW1j'
    || 'aVltS0dWYmJsMHVaR1ZtWVhWc2RGTmxiR1ZqZEdWa1BTRXdLWDFsYkhObGUyWnZjaWh1UFNJaUsyeGxLRzRwTEhROWJuVnNiQ3hzUFRBN2JEeGxMbXhsYm1k'
    || 'MGFEdHNLeXNwZTJsbUtHVmJiRjB1ZG1Gc2RXVTlQVDF1S1h0bFcyeGRMbk5sYkdWamRHVmtQU0V3TEhJbUppaGxXMnhkTG1SbFptRjFiSFJUWld4bFkzUmxa'
    || 'RDBoTUNrN2NtVjBkWEp1ZlhRaFBUMXVkV3hzZkh4bFcyeGRMbVJwYzJGaWJHVmtmSHdvZEQxbFcyeGRLWDEwSVQwOWJuVnNiQ1ltS0hRdWMyVnNaV04wWldR'
    || 'OUlUQXBmWDFtZFc1amRHbHZiaUJ2YVNobExIUXBlMmxtS0hRdVpHRnVaMlZ5YjNWemJIbFRaWFJKYm01bGNraFVUVXdoUFc1MWJHd3BkR2h5YjNjZ1JYSnli'
    || 'M0lvWVNnNU1Ta3BPM0psZEhWeWJpQkpLSHQ5TEhRc2UzWmhiSFZsT25admFXUWdNQ3hrWldaaGRXeDBWbUZzZFdVNmRtOXBaQ0F3TEdOb2FXeGtjbVZ1T2lJ'
    || 'aUsyVXVYM2R5WVhCd1pYSlRkR0YwWlM1cGJtbDBhV0ZzVm1Gc2RXVjlLWDFtZFc1amRHbHZiaUJuY3lobExIUXBlM1poY2lCdVBYUXVkbUZzZFdVN2FXWW9i'
    || 'ajA5Ym5Wc2JDbDdhV1lvYmoxMExtTm9hV3hrY21WdUxIUTlkQzVrWldaaGRXeDBWbUZzZFdVc2JpRTliblZzYkNsN2FXWW9kQ0U5Ym5Wc2JDbDBhSEp2ZHlC'
    || 'RmNuSnZjaWhoS0RreUtTazdhV1lvV0c0b2Jpa3BlMmxtS0RFOGJpNXNaVzVuZEdncGRHaHliM2NnUlhKeWIzSW9ZU2c1TXlrcE8yNDlibHN3WFgxMFBXNTlk'
    || 'RDA5Ym5Wc2JDWW1LSFE5SWlJcExHNDlkSDFsTGw5M2NtRndjR1Z5VTNSaGRHVTllMmx1YVhScFlXeFdZV3gxWlRwc1pTaHVLWDE5Wm5WdVkzUnBiMjRnZVhN'
    || 'b1pTeDBLWHQyWVhJZ2JqMXNaU2gwTG5aaGJIVmxLU3h5UFd4bEtIUXVaR1ZtWVhWc2RGWmhiSFZsS1R0dUlUMXVkV3hzSmlZb2JqMGlJaXR1TEc0aFBUMWxM'
    || 'blpoYkhWbEppWW9aUzUyWVd4MVpUMXVLU3gwTG1SbFptRjFiSFJXWVd4MVpUMDliblZzYkNZbVpTNWtaV1poZFd4MFZtRnNkV1VoUFQxdUppWW9aUzVrWlda'
    || 'aGRXeDBWbUZzZFdVOWJpa3BMSEloUFc1MWJHd21KaWhsTG1SbFptRjFiSFJXWVd4MVpUMGlJaXR5S1gxbWRXNWpkR2x2YmlCNGN5aGxLWHQyWVhJZ2REMWxM'
    || 'blJsZUhSRGIyNTBaVzUwTzNROVBUMWxMbDkzY21Gd2NHVnlVM1JoZEdVdWFXNXBkR2xoYkZaaGJIVmxKaVowSVQwOUlpSW1KblFoUFQxdWRXeHNKaVlvWlM1'
    || 'MllXeDFaVDEwS1gxbWRXNWpkR2x2YmlCVGN5aGxLWHR6ZDJsMFkyZ29aU2w3WTJGelpTSnpkbWNpT25KbGRIVnliaUpvZEhSd09pOHZkM2QzTG5jekxtOXla'
    || 'eTh5TURBd0wzTjJaeUk3WTJGelpTSnRZWFJvSWpweVpYUjFjbTRpYUhSMGNEb3ZMM2QzZHk1M015NXZjbWN2TVRrNU9DOU5ZWFJvTDAxaGRHaE5UQ0k3WkdW'
    || 'bVlYVnNkRHB5WlhSMWNtNGlhSFIwY0RvdkwzZDNkeTUzTXk1dmNtY3ZNVGs1T1M5NGFIUnRiQ0o5ZldaMWJtTjBhVzl1SUhOcEtHVXNkQ2w3Y21WMGRYSnVJ'
    || 'R1U5UFc1MWJHeDhmR1U5UFQwaWFIUjBjRG92TDNkM2R5NTNNeTV2Y21jdk1UazVPUzk0YUhSdGJDSS9VM01vZENrNlpUMDlQU0pvZEhSd09pOHZkM2QzTG5j'
    || 'ekxtOXlaeTh5TURBd0wzTjJaeUltSm5ROVBUMGlabTl5WldsbmJrOWlhbVZqZENJL0ltaDBkSEE2THk5M2QzY3Vkek11YjNKbkx6RTVPVGt2ZUdoMGJXd2lP'
    || 'bVY5ZG1GeUlIcHlMSGR6UFNobWRXNWpkR2x2YmlobEtYdHlaWFIxY200Z2RIbHdaVzltSUUxVFFYQndQQ0oxSWlZbVRWTkJjSEF1WlhobFkxVnVjMkZtWlV4'
    || 'dlkyRnNSblZ1WTNScGIyNC9ablZ1WTNScGIyNG9kQ3h1TEhJc2JDbDdUVk5CY0hBdVpYaGxZMVZ1YzJGbVpVeHZZMkZzUm5WdVkzUnBiMjRvWm5WdVkzUnBi'
    || 'MjRvS1h0eVpYUjFjbTRnWlNoMExHNHNjaXhzS1gwcGZUcGxmU2tvWm5WdVkzUnBiMjRvWlN4MEtYdHBaaWhsTG01aGJXVnpjR0ZqWlZWU1NTRTlQU0pvZEhS'
    || 'd09pOHZkM2QzTG5jekxtOXlaeTh5TURBd0wzTjJaeUo4ZkNKcGJtNWxja2hVVFV3aWFXNGdaU2xsTG1sdWJtVnlTRlJOVEQxME8yVnNjMlY3Wm05eUtIcHlQ'
    || 'WHB5Zkh4a2IyTjFiV1Z1ZEM1amNtVmhkR1ZGYkdWdFpXNTBLQ0prYVhZaUtTeDZjaTVwYm01bGNraFVUVXc5SWp4emRtYytJaXQwTG5aaGJIVmxUMllvS1M1'
    || 'MGIxTjBjbWx1WnlncEt5SThMM04yWno0aUxIUTllbkl1Wm1seWMzUkRhR2xzWkR0bExtWnBjbk4wUTJocGJHUTdLV1V1Y21WdGIzWmxRMmhwYkdRb1pTNW1h'
    || 'WEp6ZEVOb2FXeGtLVHRtYjNJb08zUXVabWx5YzNSRGFHbHNaRHNwWlM1aGNIQmxibVJEYUdsc1pDaDBMbVpwY25OMFEyaHBiR1FwZlgwcE8yWjFibU4wYVc5'
    || 'dUlGcHVLR1VzZENsN2FXWW9kQ2w3ZG1GeUlHNDlaUzVtYVhKemRFTm9hV3hrTzJsbUtHNG1KbTQ5UFQxbExteGhjM1JEYUdsc1pDWW1iaTV1YjJSbFZIbHda'
    || 'VDA5UFRNcGUyNHVibTlrWlZaaGJIVmxQWFE3Y21WMGRYSnVmWDFsTG5SbGVIUkRiMjUwWlc1MFBYUjlkbUZ5SUhGdVBYdGhibWx0WVhScGIyNUpkR1Z5WVhS'
    || 'cGIyNURiM1Z1ZERvaE1DeGhjM0JsWTNSU1lYUnBiem9oTUN4aWIzSmtaWEpKYldGblpVOTFkSE5sZERvaE1DeGliM0prWlhKSmJXRm5aVk5zYVdObE9pRXdM'
    || 'R0p2Y21SbGNrbHRZV2RsVjJsa2RHZzZJVEFzWW05NFJteGxlRG9oTUN4aWIzaEdiR1Y0UjNKdmRYQTZJVEFzWW05NFQzSmthVzVoYkVkeWIzVndPaUV3TEdO'
    || 'dmJIVnRia052ZFc1ME9pRXdMR052YkhWdGJuTTZJVEFzWm14bGVEb2hNQ3htYkdWNFIzSnZkem9oTUN4bWJHVjRVRzl6YVhScGRtVTZJVEFzWm14bGVGTm9j'
    || 'bWx1YXpvaE1DeG1iR1Y0VG1WbllYUnBkbVU2SVRBc1pteGxlRTl5WkdWeU9pRXdMR2R5YVdSQmNtVmhPaUV3TEdkeWFXUlNiM2M2SVRBc1ozSnBaRkp2ZDBW'
    || 'dVpEb2hNQ3huY21sa1VtOTNVM0JoYmpvaE1DeG5jbWxrVW05M1UzUmhjblE2SVRBc1ozSnBaRU52YkhWdGJqb2hNQ3huY21sa1EyOXNkVzF1Ulc1a09pRXdM'
    || 'R2R5YVdSRGIyeDFiVzVUY0dGdU9pRXdMR2R5YVdSRGIyeDFiVzVUZEdGeWREb2hNQ3htYjI1MFYyVnBaMmgwT2lFd0xHeHBibVZEYkdGdGNEb2hNQ3hzYVc1'
    || 'bFNHVnBaMmgwT2lFd0xHOXdZV05wZEhrNklUQXNiM0prWlhJNklUQXNiM0p3YUdGdWN6b2hNQ3gwWVdKVGFYcGxPaUV3TEhkcFpHOTNjem9oTUN4NlNXNWta'
    || 'WGc2SVRBc2VtOXZiVG9oTUN4bWFXeHNUM0JoWTJsMGVUb2hNQ3htYkc5dlpFOXdZV05wZEhrNklUQXNjM1J2Y0U5d1lXTnBkSGs2SVRBc2MzUnliMnRsUkdG'
    || 'emFHRnljbUY1T2lFd0xITjBjbTlyWlVSaGMyaHZabVp6WlhRNklUQXNjM1J5YjJ0bFRXbDBaWEpzYVcxcGREb2hNQ3h6ZEhKdmEyVlBjR0ZqYVhSNU9pRXdM'
    || 'SE4wY205clpWZHBaSFJvT2lFd2ZTeGtaRDFiSWxkbFltdHBkQ0lzSW0xeklpd2lUVzk2SWl3aVR5SmRPMDlpYW1WamRDNXJaWGx6S0hGdUtTNW1iM0pGWVdO'
    || 'b0tHWjFibU4wYVc5dUtHVXBlMlJrTG1admNrVmhZMmdvWm5WdVkzUnBiMjRvZENsN2REMTBLMlV1WTJoaGNrRjBLREFwTG5SdlZYQndaWEpEWVhObEtDa3Ja'
    || 'UzV6ZFdKemRISnBibWNvTVNrc2NXNWJkRjA5Y1c1YlpWMTlLWDBwTzJaMWJtTjBhVzl1SUY5ektHVXNkQ3h1S1h0eVpYUjFjbTRnZEQwOWJuVnNiSHg4ZEhs'
    || 'd1pXOW1JSFE5UFNKaWIyOXNaV0Z1SW54OGREMDlQU0lpUHlJaU9tNThmSFI1Y0dWdlppQjBJVDBpYm5WdFltVnlJbng4ZEQwOVBUQjhmSEZ1TG1oaGMwOTNi'
    || 'bEJ5YjNCbGNuUjVLR1VwSmlaeGJsdGxYVDhvSWlJcmRDa3VkSEpwYlNncE9uUXJJbkI0SW4xbWRXNWpkR2x2YmlCRmN5aGxMSFFwZTJVOVpTNXpkSGxzWlR0'
    || 'bWIzSW9kbUZ5SUc0Z2FXNGdkQ2xwWmloMExtaGhjMDkzYmxCeWIzQmxjblI1S0c0cEtYdDJZWElnY2oxdUxtbHVaR1Y0VDJZb0lpMHRJaWs5UFQwd0xHdzlY'
    || 'M01vYml4MFcyNWRMSElwTzI0OVBUMGlabXh2WVhRaUppWW9iajBpWTNOelJteHZZWFFpS1N4eVAyVXVjMlYwVUhKdmNHVnlkSGtvYml4c0tUcGxXMjVkUFd4'
    || 'OWZYWmhjaUJtWkQxSktIdHRaVzUxYVhSbGJUb2hNSDBzZTJGeVpXRTZJVEFzWW1GelpUb2hNQ3hpY2pvaE1DeGpiMnc2SVRBc1pXMWlaV1E2SVRBc2FISTZJ'
    || 'VEFzYVcxbk9pRXdMR2x1Y0hWME9pRXdMR3RsZVdkbGJqb2hNQ3hzYVc1ck9pRXdMRzFsZEdFNklUQXNjR0Z5WVcwNklUQXNjMjkxY21ObE9pRXdMSFJ5WVdO'
    || 'ck9pRXdMSGRpY2pvaE1IMHBPMloxYm1OMGFXOXVJSFZwS0dVc2RDbDdhV1lvZENsN2FXWW9abVJiWlYwbUppaDBMbU5vYVd4a2NtVnVJVDF1ZFd4c2ZIeDBM'
    || 'bVJoYm1kbGNtOTFjMng1VTJWMFNXNXVaWEpJVkUxTUlUMXVkV3hzS1NsMGFISnZkeUJGY25KdmNpaGhLREV6Tnl4bEtTazdhV1lvZEM1a1lXNW5aWEp2ZFhO'
    || 'c2VWTmxkRWx1Ym1WeVNGUk5UQ0U5Ym5Wc2JDbDdhV1lvZEM1amFHbHNaSEpsYmlFOWJuVnNiQ2wwYUhKdmR5QkZjbkp2Y2loaEtEWXdLU2s3YVdZb2RIbHda'
    || 'VzltSUhRdVpHRnVaMlZ5YjNWemJIbFRaWFJKYm01bGNraFVUVXdoUFNKdlltcGxZM1FpZkh3aEtDSmZYMmgwYld3aWFXNGdkQzVrWVc1blpYSnZkWE5zZVZO'
    || 'bGRFbHVibVZ5U0ZSTlRDa3BkR2h5YjNjZ1JYSnliM0lvWVNnMk1Ta3BmV2xtS0hRdWMzUjViR1VoUFc1MWJHd21KblI1Y0dWdlppQjBMbk4wZVd4bElUMGli'
    || 'MkpxWldOMElpbDBhSEp2ZHlCRmNuSnZjaWhoS0RZeUtTbDlmV1oxYm1OMGFXOXVJR0ZwS0dVc2RDbDdhV1lvWlM1cGJtUmxlRTltS0NJdElpazlQVDB0TVNs'
    || 'eVpYUjFjbTRnZEhsd1pXOW1JSFF1YVhNOVBTSnpkSEpwYm1jaU8zTjNhWFJqYUNobEtYdGpZWE5sSW1GdWJtOTBZWFJwYjI0dGVHMXNJanBqWVhObEltTnZi'
    || 'Rzl5TFhCeWIyWnBiR1VpT21OaGMyVWlabTl1ZEMxbVlXTmxJanBqWVhObEltWnZiblF0Wm1GalpTMXpjbU1pT21OaGMyVWlabTl1ZEMxbVlXTmxMWFZ5YVNJ'
    || 'NlkyRnpaU0ptYjI1MExXWmhZMlV0Wm05eWJXRjBJanBqWVhObEltWnZiblF0Wm1GalpTMXVZVzFsSWpwallYTmxJbTFwYzNOcGJtY3RaMng1Y0dnaU9uSmxk'
    || 'SFZ5YmlFeE8yUmxabUYxYkhRNmNtVjBkWEp1SVRCOWZYWmhjaUJqYVQxdWRXeHNPMloxYm1OMGFXOXVJR1JwS0dVcGUzSmxkSFZ5YmlCbFBXVXVkR0Z5WjJW'
    || 'MGZIeGxMbk55WTBWc1pXMWxiblI4ZkhkcGJtUnZkeXhsTG1OdmNuSmxjM0J2Ym1ScGJtZFZjMlZGYkdWdFpXNTBKaVlvWlQxbExtTnZjbkpsYzNCdmJtUnBi'
    || 'bWRWYzJWRmJHVnRaVzUwS1N4bExtNXZaR1ZVZVhCbFBUMDlNejlsTG5CaGNtVnVkRTV2WkdVNlpYMTJZWElnWm1rOWJuVnNiQ3hmYmoxdWRXeHNMRVZ1UFc1'
    || 'MWJHdzdablZ1WTNScGIyNGdUbk1vWlNsN2FXWW9aVDE0Y2lobEtTbDdhV1lvZEhsd1pXOW1JR1pwSVQwaVpuVnVZM1JwYjI0aUtYUm9jbTkzSUVWeWNtOXlL'
    || 'R0VvTWpnd0tTazdkbUZ5SUhROVpTNXpkR0YwWlU1dlpHVTdkQ1ltS0hROWIyd29kQ2tzWm1rb1pTNXpkR0YwWlU1dlpHVXNaUzUwZVhCbExIUXBLWDE5Wm5W'
    || 'dVkzUnBiMjRnYTNNb1pTbDdYMjQvUlc0L1JXNHVjSFZ6YUNobEtUcEZiajFiWlYwNlgyNDlaWDFtZFc1amRHbHZiaUJxY3lncGUybG1LRjl1S1h0MllYSWda'
    || 'VDFmYml4MFBVVnVPMmxtS0VWdVBWOXVQVzUxYkd3c1RuTW9aU2tzZENsbWIzSW9aVDB3TzJVOGRDNXNaVzVuZEdnN1pTc3JLVTV6S0hSYlpWMHBmWDFtZFc1'
    || 'amRHbHZiaUJEY3lobExIUXBlM0psZEhWeWJpQmxLSFFwZldaMWJtTjBhVzl1SUZSektDbDdmWFpoY2lCd2FUMGhNVHRtZFc1amRHbHZiaUJTY3lobExIUXNi'
    || 'aWw3YVdZb2NHa3BjbVYwZFhKdUlHVW9kQ3h1S1R0d2FUMGhNRHQwY25sN2NtVjBkWEp1SUVOektHVXNkQ3h1S1gxbWFXNWhiR3g1ZTNCcFBTRXhMQ2hmYmlF'
    || 'OVBXNTFiR3g4ZkVWdUlUMDliblZzYkNrbUppaFVjeWdwTEdwektDa3BmWDFtZFc1amRHbHZiaUJLYmlobExIUXBlM1poY2lCdVBXVXVjM1JoZEdWT2IyUmxP'
    || 'MmxtS0c0OVBUMXVkV3hzS1hKbGRIVnliaUJ1ZFd4c08zWmhjaUJ5UFc5c0tHNHBPMmxtS0hJOVBUMXVkV3hzS1hKbGRIVnliaUJ1ZFd4c08yNDljbHQwWFR0'
    || 'bE9uTjNhWFJqYUNoMEtYdGpZWE5sSW05dVEyeHBZMnNpT21OaGMyVWliMjVEYkdsamEwTmhjSFIxY21VaU9tTmhjMlVpYjI1RWIzVmliR1ZEYkdsamF5STZZ'
    || 'MkZ6WlNKdmJrUnZkV0pzWlVOc2FXTnJRMkZ3ZEhWeVpTSTZZMkZ6WlNKdmJrMXZkWE5sUkc5M2JpSTZZMkZ6WlNKdmJrMXZkWE5sUkc5M2JrTmhjSFIxY21V'
    || 'aU9tTmhjMlVpYjI1TmIzVnpaVTF2ZG1VaU9tTmhjMlVpYjI1TmIzVnpaVTF2ZG1WRFlYQjBkWEpsSWpwallYTmxJbTl1VFc5MWMyVlZjQ0k2WTJGelpTSnZi'
    || 'azF2ZFhObFZYQkRZWEIwZFhKbElqcGpZWE5sSW05dVRXOTFjMlZGYm5SbGNpSTZLSEk5SVhJdVpHbHpZV0pzWldRcGZId29aVDFsTG5SNWNHVXNjajBoS0dV'
    || 'OVBUMGlZblYwZEc5dUlueDhaVDA5UFNKcGJuQjFkQ0o4ZkdVOVBUMGljMlZzWldOMElueDhaVDA5UFNKMFpYaDBZWEpsWVNJcEtTeGxQU0Z5TzJKeVpXRnJJ'
    || 'R1U3WkdWbVlYVnNkRHBsUFNFeGZXbG1LR1VwY21WMGRYSnVJRzUxYkd3N2FXWW9iaVltZEhsd1pXOW1JRzRoUFNKbWRXNWpkR2x2YmlJcGRHaHliM2NnUlhK'
    || 'eWIzSW9ZU2d5TXpFc2RDeDBlWEJsYjJZZ2Jpa3BPM0psZEhWeWJpQnVmWFpoY2lCb2FUMGhNVHRwWmloM0tYUnllWHQyWVhJZ1ltNDllMzA3VDJKcVpXTjBM'
    || 'bVJsWm1sdVpWQnliM0JsY25SNUtHSnVMQ0p3WVhOemFYWmxJaXg3WjJWME9tWjFibU4wYVc5dUtDbDdhR2s5SVRCOWZTa3NkMmx1Wkc5M0xtRmtaRVYyWlc1'
    || 'MFRHbHpkR1Z1WlhJb0luUmxjM1FpTEdKdUxHSnVLU3gzYVc1a2IzY3VjbVZ0YjNabFJYWmxiblJNYVhOMFpXNWxjaWdpZEdWemRDSXNZbTRzWW00cGZXTmhk'
    || 'R05vZTJocFBTRXhmV1oxYm1OMGFXOXVJSEJrS0dVc2RDeHVMSElzYkN4cExITXNZeXhtS1h0MllYSWdlVDFCY25KaGVTNXdjbTkwYjNSNWNHVXVjMnhwWTJV'
    || 'dVkyRnNiQ2hoY21kMWJXVnVkSE1zTXlrN2RISjVlM1F1WVhCd2JIa29iaXg1S1gxallYUmphQ2hxS1h0MGFHbHpMbTl1UlhKeWIzSW9haWw5ZlhaaGNpQmxj'
    || 'ajBoTVN4VmNqMXVkV3hzTEVaeVBTRXhMRzFwUFc1MWJHd3NhR1E5ZTI5dVJYSnliM0k2Wm5WdVkzUnBiMjRvWlNsN1pYSTlJVEFzVlhJOVpYMTlPMloxYm1O'
    || 'MGFXOXVJRzFrS0dVc2RDeHVMSElzYkN4cExITXNZeXhtS1h0bGNqMGhNU3hWY2oxdWRXeHNMSEJrTG1Gd2NHeDVLR2hrTEdGeVozVnRaVzUwY3lsOVpuVnVZ'
    || 'M1JwYjI0Z2RtUW9aU3gwTEc0c2NpeHNMR2tzY3l4akxHWXBlMmxtS0cxa0xtRndjR3g1S0hSb2FYTXNZWEpuZFcxbGJuUnpLU3hsY2lsN2FXWW9aWElwZTNa'
    || 'aGNpQjVQVlZ5TzJWeVBTRXhMRlZ5UFc1MWJHeDlaV3h6WlNCMGFISnZkeUJGY25KdmNpaGhLREU1T0NrcE8wWnlmSHdvUm5JOUlUQXNiV2s5ZVNsOWZXWjFi'
    || 'bU4wYVc5dUlHeHVLR1VwZTNaaGNpQjBQV1VzYmoxbE8ybG1LR1V1WVd4MFpYSnVZWFJsS1dadmNpZzdkQzV5WlhSMWNtNDdLWFE5ZEM1eVpYUjFjbTQ3Wld4'
    || 'elpYdGxQWFE3Wkc4Z2REMWxMQ2gwTG1ac1lXZHpKalF3T1RncElUMDlNQ1ltS0c0OWRDNXlaWFIxY200cExHVTlkQzV5WlhSMWNtNDdkMmhwYkdVb1pTbDlj'
    || 'bVYwZFhKdUlIUXVkR0ZuUFQwOU16OXVPbTUxYkd4OVpuVnVZM1JwYjI0Z1QzTW9aU2w3YVdZb1pTNTBZV2M5UFQweE15bDdkbUZ5SUhROVpTNXRaVzF2YVhw'
    || 'bFpGTjBZWFJsTzJsbUtIUTlQVDF1ZFd4c0ppWW9aVDFsTG1Gc2RHVnlibUYwWlN4bElUMDliblZzYkNZbUtIUTlaUzV0WlcxdmFYcGxaRk4wWVhSbEtTa3Nk'
    || 'Q0U5UFc1MWJHd3BjbVYwZFhKdUlIUXVaR1ZvZVdSeVlYUmxaSDF5WlhSMWNtNGdiblZzYkgxbWRXNWpkR2x2YmlCTmN5aGxLWHRwWmloc2JpaGxLU0U5UFdV'
    || 'cGRHaHliM2NnUlhKeWIzSW9ZU2d4T0RncEtYMW1kVzVqZEdsdmJpQm5aQ2hsS1h0MllYSWdkRDFsTG1Gc2RHVnlibUYwWlR0cFppZ2hkQ2w3YVdZb2REMXNi'
    || 'aWhsS1N4MFBUMDliblZzYkNsMGFISnZkeUJGY25KdmNpaGhLREU0T0NrcE8zSmxkSFZ5YmlCMElUMDlaVDl1ZFd4c09tVjlabTl5S0haaGNpQnVQV1VzY2ox'
    || 'ME96c3BlM1poY2lCc1BXNHVjbVYwZFhKdU8ybG1LR3c5UFQxdWRXeHNLV0p5WldGck8zWmhjaUJwUFd3dVlXeDBaWEp1WVhSbE8ybG1LR2s5UFQxdWRXeHNL'
    || 'WHRwWmloeVBXd3VjbVYwZFhKdUxISWhQVDF1ZFd4c0tYdHVQWEk3WTI5dWRHbHVkV1Y5WW5KbFlXdDlhV1lvYkM1amFHbHNaRDA5UFdrdVkyaHBiR1FwZTJa'
    || 'dmNpaHBQV3d1WTJocGJHUTdhVHNwZTJsbUtHazlQVDF1S1hKbGRIVnliaUJOY3loc0tTeGxPMmxtS0drOVBUMXlLWEpsZEhWeWJpQk5jeWhzS1N4ME8yazlh'
    || 'UzV6YVdKc2FXNW5mWFJvY205M0lFVnljbTl5S0dFb01UZzRLU2w5YVdZb2JpNXlaWFIxY200aFBUMXlMbkpsZEhWeWJpbHVQV3dzY2oxcE8yVnNjMlY3Wm05'
    || 'eUtIWmhjaUJ6UFNFeExHTTliQzVqYUdsc1pEdGpPeWw3YVdZb1l6MDlQVzRwZTNNOUlUQXNiajFzTEhJOWFUdGljbVZoYTMxcFppaGpQVDA5Y2lsN2N6MGhN'
    || 'Q3h5UFd3c2JqMXBPMkp5WldGcmZXTTlZeTV6YVdKc2FXNW5mV2xtS0NGektYdG1iM0lvWXoxcExtTm9hV3hrTzJNN0tYdHBaaWhqUFQwOWJpbDdjejBoTUN4'
    || 'dVBXa3NjajFzTzJKeVpXRnJmV2xtS0dNOVBUMXlLWHR6UFNFd0xISTlhU3h1UFd3N1luSmxZV3Q5WXoxakxuTnBZbXhwYm1kOWFXWW9JWE1wZEdoeWIzY2dS'
    || 'WEp5YjNJb1lTZ3hPRGtwS1gxOWFXWW9iaTVoYkhSbGNtNWhkR1VoUFQxeUtYUm9jbTkzSUVWeWNtOXlLR0VvTVRrd0tTbDlhV1lvYmk1MFlXY2hQVDB6S1hS'
    || 'b2NtOTNJRVZ5Y205eUtHRW9NVGc0S1NrN2NtVjBkWEp1SUc0dWMzUmhkR1ZPYjJSbExtTjFjbkpsYm5ROVBUMXVQMlU2ZEgxbWRXNWpkR2x2YmlCRWN5aGxL'
    || 'WHR5WlhSMWNtNGdaVDFuWkNobEtTeGxJVDA5Ym5Wc2JEOVFjeWhsS1RwdWRXeHNmV1oxYm1OMGFXOXVJRkJ6S0dVcGUybG1LR1V1ZEdGblBUMDlOWHg4WlM1'
    || 'MFlXYzlQVDAyS1hKbGRIVnliaUJsTzJadmNpaGxQV1V1WTJocGJHUTdaU0U5UFc1MWJHdzdLWHQyWVhJZ2REMVFjeWhsS1R0cFppaDBJVDA5Ym5Wc2JDbHla'
    || 'WFIxY200Z2REdGxQV1V1YzJsaWJHbHVaMzF5WlhSMWNtNGdiblZzYkgxMllYSWdUSE05WkM1MWJuTjBZV0pzWlY5elkyaGxaSFZzWlVOaGJHeGlZV05yTEVs'
    || 'elBXUXVkVzV6ZEdGaWJHVmZZMkZ1WTJWc1EyRnNiR0poWTJzc2VXUTlaQzUxYm5OMFlXSnNaVjl6YUc5MWJHUlphV1ZzWkN4NFpEMWtMblZ1YzNSaFlteGxY'
    || 'M0psY1hWbGMzUlFZV2x1ZEN4VFpUMWtMblZ1YzNSaFlteGxYMjV2ZHl4VFpEMWtMblZ1YzNSaFlteGxYMmRsZEVOMWNuSmxiblJRY21sdmNtbDBlVXhsZG1W'
    || 'c0xIWnBQV1F1ZFc1emRHRmliR1ZmU1cxdFpXUnBZWFJsVUhKcGIzSnBkSGtzUVhNOVpDNTFibk4wWVdKc1pWOVZjMlZ5UW14dlkydHBibWRRY21sdmNtbDBl'
    || 'U3hYY2oxa0xuVnVjM1JoWW14bFgwNXZjbTFoYkZCeWFXOXlhWFI1TEhka1BXUXVkVzV6ZEdGaWJHVmZURzkzVUhKcGIzSnBkSGtzZW5NOVpDNTFibk4wWVdK'
    || 'c1pWOUpaR3hsVUhKcGIzSnBkSGtzSkhJOWJuVnNiQ3hmZEQxdWRXeHNPMloxYm1OMGFXOXVJRjlrS0dVcGUybG1LRjkwSmlaMGVYQmxiMllnWDNRdWIyNURi'
    || 'MjF0YVhSR2FXSmxjbEp2YjNROVBTSm1kVzVqZEdsdmJpSXBkSEo1ZTE5MExtOXVRMjl0YldsMFJtbGlaWEpTYjI5MEtDUnlMR1VzZG05cFpDQXdMQ2hsTG1O'
    || 'MWNuSmxiblF1Wm14aFozTW1NVEk0S1QwOVBURXlPQ2w5WTJGMFkyaDdmWDEyWVhJZ2FIUTlUV0YwYUM1amJIb3pNajlOWVhSb0xtTnNlak15T210a0xFVmtQ'
    || 'VTFoZEdndWJHOW5MRTVrUFUxaGRHZ3VURTR5TzJaMWJtTjBhVzl1SUd0a0tHVXBlM0psZEhWeWJpQmxQajQrUFRBc1pUMDlQVEEvTXpJNk16RXRLRVZrS0dV'
    || 'cEwwNWtmREFwZkRCOWRtRnlJRlp5UFRZMExFaHlQVFF4T1RRek1EUTdablZ1WTNScGIyNGdkSElvWlNsN2MzZHBkR05vS0dVbUxXVXBlMk5oYzJVZ01UcHla'
    || 'WFIxY200Z01UdGpZWE5sSURJNmNtVjBkWEp1SURJN1kyRnpaU0EwT25KbGRIVnliaUEwTzJOaGMyVWdPRHB5WlhSMWNtNGdPRHRqWVhObElERTJPbkpsZEhW'
    || 'eWJpQXhOanRqWVhObElETXlPbkpsZEhWeWJpQXpNanRqWVhObElEWTBPbU5oYzJVZ01USTRPbU5oYzJVZ01qVTJPbU5oYzJVZ05URXlPbU5oYzJVZ01UQXlO'
    || 'RHBqWVhObElESXdORGc2WTJGelpTQTBNRGsyT21OaGMyVWdPREU1TWpwallYTmxJREUyTXpnME9tTmhjMlVnTXpJM05qZzZZMkZ6WlNBMk5UVXpOanBqWVhO'
    || 'bElERXpNVEEzTWpwallYTmxJREkyTWpFME5EcGpZWE5sSURVeU5ESTRPRHBqWVhObElERXdORGcxTnpZNlkyRnpaU0F5TURrM01UVXlPbkpsZEhWeWJpQmxK'
    || 'alF4T1RReU5EQTdZMkZ6WlNBME1UazBNekEwT21OaGMyVWdPRE00T0RZd09EcGpZWE5sSURFMk56YzNNakUyT21OaGMyVWdNek0xTlRRME16STZZMkZ6WlNB'
    || 'Mk56RXdPRGcyTkRweVpYUjFjbTRnWlNZeE16QXdNak0wTWpRN1kyRnpaU0F4TXpReU1UYzNNamc2Y21WMGRYSnVJREV6TkRJeE56Y3lPRHRqWVhObElESTJP'
    || 'RFF6TlRRMU5qcHlaWFIxY200Z01qWTRORE0xTkRVMk8yTmhjMlVnTlRNMk9EY3dPVEV5T25KbGRIVnliaUExTXpZNE56QTVNVEk3WTJGelpTQXhNRGN6TnpR'
    || 'eE9ESTBPbkpsZEhWeWJpQXhNRGN6TnpReE9ESTBPMlJsWm1GMWJIUTZjbVYwZFhKdUlHVjlmV1oxYm1OMGFXOXVJRUp5S0dVc2RDbDdkbUZ5SUc0OVpTNXda'
    || 'VzVrYVc1blRHRnVaWE03YVdZb2JqMDlQVEFwY21WMGRYSnVJREE3ZG1GeUlISTlNQ3hzUFdVdWMzVnpjR1Z1WkdWa1RHRnVaWE1zYVQxbExuQnBibWRsWkV4'
    || 'aGJtVnpMSE05YmlZeU5qZzBNelUwTlRVN2FXWW9jeUU5UFRBcGUzWmhjaUJqUFhNbWZtdzdZeUU5UFRBL2NqMTBjaWhqS1Rvb2FTWTljeXhwSVQwOU1DWW1L'
    || 'SEk5ZEhJb2FTa3BLWDFsYkhObElITTliaVorYkN4eklUMDlNRDl5UFhSeUtITXBPbWtoUFQwd0ppWW9jajEwY2locEtTazdhV1lvY2owOVBUQXBjbVYwZFhK'
    || 'dUlEQTdhV1lvZENFOVBUQW1KblFoUFQxeUppWW9kQ1pzS1QwOVBUQW1KaWhzUFhJbUxYSXNhVDEwSmkxMExHdytQV2w4Zkd3OVBUMHhOaVltS0drbU5ERTVO'
    || 'REkwTUNraFBUMHdLU2x5WlhSMWNtNGdkRHRwWmlnb2NpWTBLU0U5UFRBbUppaHlmRDF1SmpFMktTeDBQV1V1Wlc1MFlXNW5iR1ZrVEdGdVpYTXNkQ0U5UFRB'
    || 'cFptOXlLR1U5WlM1bGJuUmhibWRzWlcxbGJuUnpMSFFtUFhJN01EeDBPeWx1UFRNeExXaDBLSFFwTEd3OU1UdzhiaXh5ZkQxbFcyNWRMSFFtUFg1c08zSmxk'
    || 'SFZ5YmlCeWZXWjFibU4wYVc5dUlHcGtLR1VzZENsN2MzZHBkR05vS0dVcGUyTmhjMlVnTVRwallYTmxJREk2WTJGelpTQTBPbkpsZEhWeWJpQjBLekkxTUR0'
    || 'allYTmxJRGc2WTJGelpTQXhOanBqWVhObElETXlPbU5oYzJVZ05qUTZZMkZ6WlNBeE1qZzZZMkZ6WlNBeU5UWTZZMkZ6WlNBMU1USTZZMkZ6WlNBeE1ESTBP'
    || 'bU5oYzJVZ01qQTBPRHBqWVhObElEUXdPVFk2WTJGelpTQTRNVGt5T21OaGMyVWdNVFl6T0RRNlkyRnpaU0F6TWpjMk9EcGpZWE5sSURZMU5UTTJPbU5oYzJV'
    || 'Z01UTXhNRGN5T21OaGMyVWdNall5TVRRME9tTmhjMlVnTlRJME1qZzRPbU5oYzJVZ01UQTBPRFUzTmpwallYTmxJREl3T1RjeE5USTZjbVYwZFhKdUlIUXJO'
    || 'V1V6TzJOaGMyVWdOREU1TkRNd05EcGpZWE5sSURnek9EZzJNRGc2WTJGelpTQXhOamMzTnpJeE5qcGpZWE5sSURNek5UVTBORE15T21OaGMyVWdOamN4TURn'
    || 'NE5qUTZjbVYwZFhKdUxURTdZMkZ6WlNBeE16UXlNVGMzTWpnNlkyRnpaU0F5TmpnME16VTBOVFk2WTJGelpTQTFNelk0TnpBNU1USTZZMkZ6WlNBeE1EY3pO'
    || 'elF4T0RJME9uSmxkSFZ5YmkweE8yUmxabUYxYkhRNmNtVjBkWEp1TFRGOWZXWjFibU4wYVc5dUlFTmtLR1VzZENsN1ptOXlLSFpoY2lCdVBXVXVjM1Z6Y0dW'
    || 'dVpHVmtUR0Z1WlhNc2NqMWxMbkJwYm1kbFpFeGhibVZ6TEd3OVpTNWxlSEJwY21GMGFXOXVWR2x0WlhNc2FUMWxMbkJsYm1ScGJtZE1ZVzVsY3pzd1BHazdL'
    || 'WHQyWVhJZ2N6MHpNUzFvZENocEtTeGpQVEU4UEhNc1pqMXNXM05kTzJZOVBUMHRNVDhvS0dNbWJpazlQVDB3Zkh3b1l5WnlLU0U5UFRBcEppWW9iRnR6WFQx'
    || 'cVpDaGpMSFFwS1RwbVBEMTBKaVlvWlM1bGVIQnBjbVZrVEdGdVpYTjhQV01wTEdrbVBYNWpmWDFtZFc1amRHbHZiaUJuYVNobEtYdHlaWFIxY200Z1pUMWxM'
    || 'bkJsYm1ScGJtZE1ZVzVsY3lZdE1UQTNNemMwTVRneU5TeGxJVDA5TUQ5bE9tVW1NVEEzTXpjME1UZ3lORDh4TURjek56UXhPREkwT2pCOVpuVnVZM1JwYjI0'
    || 'Z1ZYTW9LWHQyWVhJZ1pUMVdjanR5WlhSMWNtNGdWbkk4UEQweExDaFdjaVkwTVRrME1qUXdLVDA5UFRBbUppaFdjajAyTkNrc1pYMW1kVzVqZEdsdmJpQjVh'
    || 'U2hsS1h0bWIzSW9kbUZ5SUhROVcxMHNiajB3T3pNeFBtNDdiaXNyS1hRdWNIVnphQ2hsS1R0eVpYUjFjbTRnZEgxbWRXNWpkR2x2YmlCdWNpaGxMSFFzYmls'
    || 'N1pTNXdaVzVrYVc1blRHRnVaWE44UFhRc2RDRTlQVFV6TmpnM01Ea3hNaVltS0dVdWMzVnpjR1Z1WkdWa1RHRnVaWE05TUN4bExuQnBibWRsWkV4aGJtVnpQ'
    || 'VEFwTEdVOVpTNWxkbVZ1ZEZScGJXVnpMSFE5TXpFdGFIUW9kQ2tzWlZ0MFhUMXVmV1oxYm1OMGFXOXVJRlJrS0dVc2RDbDdkbUZ5SUc0OVpTNXdaVzVrYVc1'
    || 'blRHRnVaWE1tZm5RN1pTNXdaVzVrYVc1blRHRnVaWE05ZEN4bExuTjFjM0JsYm1SbFpFeGhibVZ6UFRBc1pTNXdhVzVuWldSTVlXNWxjejB3TEdVdVpYaHdh'
    || 'WEpsWkV4aGJtVnpKajEwTEdVdWJYVjBZV0pzWlZKbFlXUk1ZVzVsY3lZOWRDeGxMbVZ1ZEdGdVoyeGxaRXhoYm1WekpqMTBMSFE5WlM1bGJuUmhibWRzWlcx'
    || 'bGJuUnpPM1poY2lCeVBXVXVaWFpsYm5SVWFXMWxjenRtYjNJb1pUMWxMbVY0Y0dseVlYUnBiMjVVYVcxbGN6c3dQRzQ3S1h0MllYSWdiRDB6TVMxb2RDaHVL'
    || 'U3hwUFRFOFBHdzdkRnRzWFQwd0xISmJiRjA5TFRFc1pWdHNYVDB0TVN4dUpqMSthWDE5Wm5WdVkzUnBiMjRnZUdrb1pTeDBLWHQyWVhJZ2JqMWxMbVZ1ZEdG'
    || 'dVoyeGxaRXhoYm1WemZEMTBPMlp2Y2lobFBXVXVaVzUwWVc1bmJHVnRaVzUwY3p0dU95bDdkbUZ5SUhJOU16RXRhSFFvYmlrc2JEMHhQRHh5TzJ3bWRIeGxX'
    || 'M0pkSm5RbUppaGxXM0pkZkQxMEtTeHVKajErYkgxOWRtRnlJR2xsUFRBN1puVnVZM1JwYjI0Z1JuTW9aU2w3Y21WMGRYSnVJR1VtUFMxbExERThaVDgwUEdV'
    || 'L0tHVW1Nalk0TkRNMU5EVTFLU0U5UFRBL01UWTZOVE0yT0Rjd09URXlPalE2TVgxMllYSWdWM01zVTJrc0pITXNWbk1zU0hNc2QyazlJVEVzVVhJOVcxMHNW'
    || 'WFE5Ym5Wc2JDeEdkRDF1ZFd4c0xGZDBQVzUxYkd3c2NuSTlibVYzSUUxaGNDeHNjajF1WlhjZ1RXRndMQ1IwUFZ0ZExGSmtQU0p0YjNWelpXUnZkMjRnYlc5'
    || 'MWMyVjFjQ0IwYjNWamFHTmhibU5sYkNCMGIzVmphR1Z1WkNCMGIzVmphSE4wWVhKMElHRjFlR05zYVdOcklHUmliR05zYVdOcklIQnZhVzUwWlhKallXNWpa'
    || 'V3dnY0c5cGJuUmxjbVJ2ZDI0Z2NHOXBiblJsY25Wd0lHUnlZV2RsYm1RZ1pISmhaM04wWVhKMElHUnliM0FnWTI5dGNHOXphWFJwYjI1bGJtUWdZMjl0Y0c5'
    || 'emFYUnBiMjV6ZEdGeWRDQnJaWGxrYjNkdUlHdGxlWEJ5WlhOeklHdGxlWFZ3SUdsdWNIVjBJSFJsZUhSSmJuQjFkQ0JqYjNCNUlHTjFkQ0J3WVhOMFpTQmpi'
    || 'R2xqYXlCamFHRnVaMlVnWTI5dWRHVjRkRzFsYm5VZ2NtVnpaWFFnYzNWaWJXbDBJaTV6Y0d4cGRDZ2lJQ0lwTzJaMWJtTjBhVzl1SUVKektHVXNkQ2w3YzNk'
    || 'cGRHTm9LR1VwZTJOaGMyVWlabTlqZFhOcGJpSTZZMkZ6WlNKbWIyTjFjMjkxZENJNlZYUTliblZzYkR0aWNtVmhhenRqWVhObEltUnlZV2RsYm5SbGNpSTZZ'
    || 'MkZ6WlNKa2NtRm5iR1ZoZG1VaU9rWjBQVzUxYkd3N1luSmxZV3M3WTJGelpTSnRiM1Z6Wlc5MlpYSWlPbU5oYzJVaWJXOTFjMlZ2ZFhRaU9sZDBQVzUxYkd3'
    || 'N1luSmxZV3M3WTJGelpTSndiMmx1ZEdWeWIzWmxjaUk2WTJGelpTSndiMmx1ZEdWeWIzVjBJanB5Y2k1a1pXeGxkR1VvZEM1d2IybHVkR1Z5U1dRcE8ySnla'
    || 'V0ZyTzJOaGMyVWlaMjkwY0c5cGJuUmxjbU5oY0hSMWNtVWlPbU5oYzJVaWJHOXpkSEJ2YVc1MFpYSmpZWEIwZFhKbElqcHNjaTVrWld4bGRHVW9kQzV3YjJs'
    || 'dWRHVnlTV1FwZlgxbWRXNWpkR2x2YmlCcGNpaGxMSFFzYml4eUxHd3NhU2w3Y21WMGRYSnVJR1U5UFQxdWRXeHNmSHhsTG01aGRHbDJaVVYyWlc1MElUMDlh'
    || 'VDhvWlQxN1lteHZZMnRsWkU5dU9uUXNaRzl0UlhabGJuUk9ZVzFsT200c1pYWmxiblJUZVhOMFpXMUdiR0ZuY3pweUxHNWhkR2wyWlVWMlpXNTBPbWtzZEdG'
    || 'eVoyVjBRMjl1ZEdGcGJtVnljenBiYkYxOUxIUWhQVDF1ZFd4c0ppWW9kRDE0Y2loMEtTeDBJVDA5Ym5Wc2JDWW1VMmtvZENrcExHVXBPaWhsTG1WMlpXNTBV'
    || 'M2x6ZEdWdFJteGhaM044UFhJc2REMWxMblJoY21kbGRFTnZiblJoYVc1bGNuTXNiQ0U5UFc1MWJHd21KblF1YVc1a1pYaFBaaWhzS1QwOVBTMHhKaVowTG5C'
    || 'MWMyZ29iQ2tzWlNsOVpuVnVZM1JwYjI0Z1QyUW9aU3gwTEc0c2NpeHNLWHR6ZDJsMFkyZ29kQ2w3WTJGelpTSm1iMk4xYzJsdUlqcHlaWFIxY200Z1ZYUTlh'
    || 'WElvVlhRc1pTeDBMRzRzY2l4c0tTd2hNRHRqWVhObEltUnlZV2RsYm5SbGNpSTZjbVYwZFhKdUlFWjBQV2x5S0VaMExHVXNkQ3h1TEhJc2JDa3NJVEE3WTJG'
    || 'elpTSnRiM1Z6Wlc5MlpYSWlPbkpsZEhWeWJpQlhkRDFwY2loWGRDeGxMSFFzYml4eUxHd3BMQ0V3TzJOaGMyVWljRzlwYm5SbGNtOTJaWElpT25aaGNpQnBQ'
    || 'V3d1Y0c5cGJuUmxja2xrTzNKbGRIVnliaUJ5Y2k1elpYUW9hU3hwY2loeWNpNW5aWFFvYVNsOGZHNTFiR3dzWlN4MExHNHNjaXhzS1Nrc0lUQTdZMkZ6WlNK'
    || 'bmIzUndiMmx1ZEdWeVkyRndkSFZ5WlNJNmNtVjBkWEp1SUdrOWJDNXdiMmx1ZEdWeVNXUXNiSEl1YzJWMEtHa3NhWElvYkhJdVoyVjBLR2twZkh4dWRXeHNM'
    || 'R1VzZEN4dUxISXNiQ2twTENFd2ZYSmxkSFZ5YmlFeGZXWjFibU4wYVc5dUlGRnpLR1VwZTNaaGNpQjBQVzl1S0dVdWRHRnlaMlYwS1R0cFppaDBJVDA5Ym5W'
    || 'c2JDbDdkbUZ5SUc0OWJHNG9kQ2s3YVdZb2JpRTlQVzUxYkd3cGUybG1LSFE5Ymk1MFlXY3NkRDA5UFRFektYdHBaaWgwUFU5ektHNHBMSFFoUFQxdWRXeHNL'
    || 'WHRsTG1Kc2IyTnJaV1JQYmoxMExFaHpLR1V1Y0hKcGIzSnBkSGtzWm5WdVkzUnBiMjRvS1hza2N5aHVLWDBwTzNKbGRIVnlibjE5Wld4elpTQnBaaWgwUFQw'
    || 'OU15WW1iaTV6ZEdGMFpVNXZaR1V1WTNWeWNtVnVkQzV0WlcxdmFYcGxaRk4wWVhSbExtbHpSR1ZvZVdSeVlYUmxaQ2w3WlM1aWJHOWphMlZrVDI0OWJpNTBZ'
    || 'V2M5UFQwelAyNHVjM1JoZEdWT2IyUmxMbU52Ym5SaGFXNWxja2x1Wm04NmJuVnNiRHR5WlhSMWNtNTlmWDFsTG1Kc2IyTnJaV1JQYmoxdWRXeHNmV1oxYm1O'
    || 'MGFXOXVJRWR5S0dVcGUybG1LR1V1WW14dlkydGxaRTl1SVQwOWJuVnNiQ2x5WlhSMWNtNGhNVHRtYjNJb2RtRnlJSFE5WlM1MFlYSm5aWFJEYjI1MFlXbHVa'
    || 'WEp6T3pBOGRDNXNaVzVuZEdnN0tYdDJZWElnYmoxRmFTaGxMbVJ2YlVWMlpXNTBUbUZ0WlN4bExtVjJaVzUwVTNsemRHVnRSbXhoWjNNc2RGc3dYU3hsTG01'
    || 'aGRHbDJaVVYyWlc1MEtUdHBaaWh1UFQwOWJuVnNiQ2w3YmoxbExtNWhkR2wyWlVWMlpXNTBPM1poY2lCeVBXNWxkeUJ1TG1OdmJuTjBjblZqZEc5eUtHNHVk'
    || 'SGx3WlN4dUtUdGphVDF5TEc0dWRHRnlaMlYwTG1ScGMzQmhkR05vUlhabGJuUW9jaWtzWTJrOWJuVnNiSDFsYkhObElISmxkSFZ5YmlCMFBYaHlLRzRwTEhR'
    || 'aFBUMXVkV3hzSmlaVGFTaDBLU3hsTG1Kc2IyTnJaV1JQYmoxdUxDRXhPM1F1YzJocFpuUW9LWDF5WlhSMWNtNGhNSDFtZFc1amRHbHZiaUJIY3lobExIUXNi'
    || 'aWw3UjNJb1pTa21KbTR1WkdWc1pYUmxLSFFwZldaMWJtTjBhVzl1SUUxa0tDbDdkMms5SVRFc1ZYUWhQVDF1ZFd4c0ppWkhjaWhWZENrbUppaFZkRDF1ZFd4'
    || 'c0tTeEdkQ0U5UFc1MWJHd21Ka2R5S0VaMEtTWW1LRVowUFc1MWJHd3BMRmQwSVQwOWJuVnNiQ1ltUjNJb1YzUXBKaVlvVjNROWJuVnNiQ2tzY25JdVptOXlS'
    || 'V0ZqYUNoSGN5a3NiSEl1Wm05eVJXRmphQ2hIY3lsOVpuVnVZM1JwYjI0Z2IzSW9aU3gwS1h0bExtSnNiMk5yWldSUGJqMDlQWFFtSmlobExtSnNiMk5yWldS'
    || 'UGJqMXVkV3hzTEhkcGZId29kMms5SVRBc1pDNTFibk4wWVdKc1pWOXpZMmhsWkhWc1pVTmhiR3hpWVdOcktHUXVkVzV6ZEdGaWJHVmZUbTl5YldGc1VISnBi'
    || 'M0pwZEhrc1RXUXBLU2w5Wm5WdVkzUnBiMjRnYzNJb1pTbDdablZ1WTNScGIyNGdkQ2hzS1h0eVpYUjFjbTRnYjNJb2JDeGxLWDFwWmlnd1BGRnlMbXhsYm1k'
    || 'MGFDbDdiM0lvVVhKYk1GMHNaU2s3Wm05eUtIWmhjaUJ1UFRFN2JqeFJjaTVzWlc1bmRHZzdiaXNyS1h0MllYSWdjajFSY2x0dVhUdHlMbUpzYjJOclpXUlBi'
    || 'ajA5UFdVbUppaHlMbUpzYjJOclpXUlBiajF1ZFd4c0tYMTlabTl5S0ZWMElUMDliblZzYkNZbWIzSW9WWFFzWlNrc1JuUWhQVDF1ZFd4c0ppWnZjaWhHZEN4'
    || 'bEtTeFhkQ0U5UFc1MWJHd21KbTl5S0ZkMExHVXBMSEp5TG1admNrVmhZMmdvZENrc2JISXVabTl5UldGamFDaDBLU3h1UFRBN2Jqd2tkQzVzWlc1bmRHZzdi'
    || 'aXNyS1hJOUpIUmJibDBzY2k1aWJHOWphMlZrVDI0OVBUMWxKaVlvY2k1aWJHOWphMlZrVDI0OWJuVnNiQ2s3Wm05eUtEc3dQQ1IwTG14bGJtZDBhQ1ltS0c0'
    || 'OUpIUmJNRjBzYmk1aWJHOWphMlZrVDI0OVBUMXVkV3hzS1RzcFVYTW9iaWtzYmk1aWJHOWphMlZrVDI0OVBUMXVkV3hzSmlZa2RDNXphR2xtZENncGZYWmhj'
    || 'aUJPYmoxMlpTNVNaV0ZqZEVOMWNuSmxiblJDWVhSamFFTnZibVpwWnl4WmNqMGhNRHRtZFc1amRHbHZiaUJFWkNobExIUXNiaXh5S1h0MllYSWdiRDFwWlN4'
    || 'cFBVNXVMblJ5WVc1emFYUnBiMjQ3VG00dWRISmhibk5wZEdsdmJqMXVkV3hzTzNSeWVYdHBaVDB4TEY5cEtHVXNkQ3h1TEhJcGZXWnBibUZzYkhsN2FXVTli'
    || 'Q3hPYmk1MGNtRnVjMmwwYVc5dVBXbDlmV1oxYm1OMGFXOXVJRkJrS0dVc2RDeHVMSElwZTNaaGNpQnNQV2xsTEdrOVRtNHVkSEpoYm5OcGRHbHZianRPYmk1'
    || 'MGNtRnVjMmwwYVc5dVBXNTFiR3c3ZEhKNWUybGxQVFFzWDJrb1pTeDBMRzRzY2lsOVptbHVZV3hzZVh0cFpUMXNMRTV1TG5SeVlXNXphWFJwYjI0OWFYMTla'
    || 'blZ1WTNScGIyNGdYMmtvWlN4MExHNHNjaWw3YVdZb1dYSXBlM1poY2lCc1BVVnBLR1VzZEN4dUxISXBPMmxtS0d3OVBUMXVkV3hzS1ZkcEtHVXNkQ3h5TEV0'
    || 'eUxHNHBMRUp6S0dVc2NpazdaV3h6WlNCcFppaFBaQ2hzTEdVc2RDeHVMSElwS1hJdWMzUnZjRkJ5YjNCaFoyRjBhVzl1S0NrN1pXeHpaU0JwWmloQ2N5aGxM'
    || 'SElwTEhRbU5DWW1MVEU4VW1RdWFXNWtaWGhQWmlobEtTbDdabTl5S0R0c0lUMDliblZzYkRzcGUzWmhjaUJwUFhoeUtHd3BPMmxtS0draFBUMXVkV3hzSmla'
    || 'WGN5aHBLU3hwUFVWcEtHVXNkQ3h1TEhJcExHazlQVDF1ZFd4c0ppWlhhU2hsTEhRc2NpeExjaXh1S1N4cFBUMDliQ2xpY21WaGF6dHNQV2w5YkNFOVBXNTFi'
    || 'R3dtSm5JdWMzUnZjRkJ5YjNCaFoyRjBhVzl1S0NsOVpXeHpaU0JYYVNobExIUXNjaXh1ZFd4c0xHNHBmWDEyWVhJZ1MzSTliblZzYkR0bWRXNWpkR2x2YmlC'
    || 'RmFTaGxMSFFzYml4eUtYdHBaaWhMY2oxdWRXeHNMR1U5Wkdrb2Npa3NaVDF2YmlobEtTeGxJVDA5Ym5Wc2JDbHBaaWgwUFd4dUtHVXBMSFE5UFQxdWRXeHNL'
    || 'V1U5Ym5Wc2JEdGxiSE5sSUdsbUtHNDlkQzUwWVdjc2JqMDlQVEV6S1h0cFppaGxQVTl6S0hRcExHVWhQVDF1ZFd4c0tYSmxkSFZ5YmlCbE8yVTliblZzYkgx'
    || 'bGJITmxJR2xtS0c0OVBUMHpLWHRwWmloMExuTjBZWFJsVG05a1pTNWpkWEp5Wlc1MExtMWxiVzlwZW1Wa1UzUmhkR1V1YVhORVpXaDVaSEpoZEdWa0tYSmxk'
    || 'SFZ5YmlCMExuUmhaejA5UFRNL2RDNXpkR0YwWlU1dlpHVXVZMjl1ZEdGcGJtVnlTVzVtYnpwdWRXeHNPMlU5Ym5Wc2JIMWxiSE5sSUhRaFBUMWxKaVlvWlQx'
    || 'dWRXeHNLVHR5WlhSMWNtNGdTM0k5WlN4dWRXeHNmV1oxYm1OMGFXOXVJRmx6S0dVcGUzTjNhWFJqYUNobEtYdGpZWE5sSW1OaGJtTmxiQ0k2WTJGelpTSmpi'
    || 'R2xqYXlJNlkyRnpaU0pqYkc5elpTSTZZMkZ6WlNKamIyNTBaWGgwYldWdWRTSTZZMkZ6WlNKamIzQjVJanBqWVhObEltTjFkQ0k2WTJGelpTSmhkWGhqYkds'
    || 'amF5STZZMkZ6WlNKa1lteGpiR2xqYXlJNlkyRnpaU0prY21GblpXNWtJanBqWVhObEltUnlZV2R6ZEdGeWRDSTZZMkZ6WlNKa2NtOXdJanBqWVhObEltWnZZ'
    || 'M1Z6YVc0aU9tTmhjMlVpWm05amRYTnZkWFFpT21OaGMyVWlhVzV3ZFhRaU9tTmhjMlVpYVc1MllXeHBaQ0k2WTJGelpTSnJaWGxrYjNkdUlqcGpZWE5sSW10'
    || 'bGVYQnlaWE56SWpwallYTmxJbXRsZVhWd0lqcGpZWE5sSW0xdmRYTmxaRzkzYmlJNlkyRnpaU0p0YjNWelpYVndJanBqWVhObEluQmhjM1JsSWpwallYTmxJ'
    || 'bkJoZFhObElqcGpZWE5sSW5Cc1lYa2lPbU5oYzJVaWNHOXBiblJsY21OaGJtTmxiQ0k2WTJGelpTSndiMmx1ZEdWeVpHOTNiaUk2WTJGelpTSndiMmx1ZEdW'
    || 'eWRYQWlPbU5oYzJVaWNtRjBaV05vWVc1blpTSTZZMkZ6WlNKeVpYTmxkQ0k2WTJGelpTSnlaWE5wZW1VaU9tTmhjMlVpYzJWbGEyVmtJanBqWVhObEluTjFZ'
    || 'bTFwZENJNlkyRnpaU0owYjNWamFHTmhibU5sYkNJNlkyRnpaU0owYjNWamFHVnVaQ0k2WTJGelpTSjBiM1ZqYUhOMFlYSjBJanBqWVhObEluWnZiSFZ0WldO'
    || 'b1lXNW5aU0k2WTJGelpTSmphR0Z1WjJVaU9tTmhjMlVpYzJWc1pXTjBhVzl1WTJoaGJtZGxJanBqWVhObEluUmxlSFJKYm5CMWRDSTZZMkZ6WlNKamIyMXdi'
    || 'M05wZEdsdmJuTjBZWEowSWpwallYTmxJbU52YlhCdmMybDBhVzl1Wlc1a0lqcGpZWE5sSW1OdmJYQnZjMmwwYVc5dWRYQmtZWFJsSWpwallYTmxJbUpsWm05'
    || 'eVpXSnNkWElpT21OaGMyVWlZV1owWlhKaWJIVnlJanBqWVhObEltSmxabTl5WldsdWNIVjBJanBqWVhObEltSnNkWElpT21OaGMyVWlablZzYkhOamNtVmxi'
    || 'bU5vWVc1blpTSTZZMkZ6WlNKbWIyTjFjeUk2WTJGelpTSm9ZWE5vWTJoaGJtZGxJanBqWVhObEluQnZjSE4wWVhSbElqcGpZWE5sSW5ObGJHVmpkQ0k2WTJG'
    || 'elpTSnpaV3hsWTNSemRHRnlkQ0k2Y21WMGRYSnVJREU3WTJGelpTSmtjbUZuSWpwallYTmxJbVJ5WVdkbGJuUmxjaUk2WTJGelpTSmtjbUZuWlhocGRDSTZZ'
    || 'MkZ6WlNKa2NtRm5iR1ZoZG1VaU9tTmhjMlVpWkhKaFoyOTJaWElpT21OaGMyVWliVzkxYzJWdGIzWmxJanBqWVhObEltMXZkWE5sYjNWMElqcGpZWE5sSW0x'
    || 'dmRYTmxiM1psY2lJNlkyRnpaU0p3YjJsdWRHVnliVzkyWlNJNlkyRnpaU0p3YjJsdWRHVnliM1YwSWpwallYTmxJbkJ2YVc1MFpYSnZkbVZ5SWpwallYTmxJ'
    || 'bk5qY205c2JDSTZZMkZ6WlNKMGIyZG5iR1VpT21OaGMyVWlkRzkxWTJodGIzWmxJanBqWVhObEluZG9aV1ZzSWpwallYTmxJbTF2ZFhObFpXNTBaWElpT21O'
    || 'aGMyVWliVzkxYzJWc1pXRjJaU0k2WTJGelpTSndiMmx1ZEdWeVpXNTBaWElpT21OaGMyVWljRzlwYm5SbGNteGxZWFpsSWpweVpYUjFjbTRnTkR0allYTmxJ'
    || 'bTFsYzNOaFoyVWlPbk4zYVhSamFDaFRaQ2dwS1h0allYTmxJSFpwT25KbGRIVnliaUF4TzJOaGMyVWdRWE02Y21WMGRYSnVJRFE3WTJGelpTQlhjanBqWVhO'
    || 'bElIZGtPbkpsZEhWeWJpQXhOanRqWVhObElIcHpPbkpsZEhWeWJpQTFNelk0TnpBNU1USTdaR1ZtWVhWc2REcHlaWFIxY200Z01UWjlaR1ZtWVhWc2REcHla'
    || 'WFIxY200Z01UWjlmWFpoY2lCV2REMXVkV3hzTEU1cFBXNTFiR3dzV0hJOWJuVnNiRHRtZFc1amRHbHZiaUJMY3lncGUybG1LRmh5S1hKbGRIVnliaUJZY2p0'
    || 'MllYSWdaU3gwUFU1cExHNDlkQzVzWlc1bmRHZ3NjaXhzUFNKMllXeDFaU0pwYmlCV2REOVdkQzUyWVd4MVpUcFdkQzUwWlhoMFEyOXVkR1Z1ZEN4cFBXd3Vi'
    || 'R1Z1WjNSb08yWnZjaWhsUFRBN1pUeHVKaVowVzJWZFBUMDliRnRsWFR0bEt5c3BPM1poY2lCelBXNHRaVHRtYjNJb2NqMHhPM0k4UFhNbUpuUmJiaTF5WFQw'
    || 'OVBXeGJhUzF5WFR0eUt5c3BPM0psZEhWeWJpQlljajFzTG5Oc2FXTmxLR1VzTVR4eVB6RXRjanAyYjJsa0lEQXBmV1oxYm1OMGFXOXVJRnB5S0dVcGUzWmhj'
    || 'aUIwUFdVdWEyVjVRMjlrWlR0eVpYUjFjbTRpWTJoaGNrTnZaR1VpYVc0Z1pUOG9aVDFsTG1Ob1lYSkRiMlJsTEdVOVBUMHdKaVowUFQwOU1UTW1KaWhsUFRF'
    || 'ektTazZaVDEwTEdVOVBUMHhNQ1ltS0dVOU1UTXBMRE15UEQxbGZIeGxQVDA5TVRNL1pUb3dmV1oxYm1OMGFXOXVJSEZ5S0NsN2NtVjBkWEp1SVRCOVpuVnVZ'
    || 'M1JwYjI0Z1dITW9LWHR5WlhSMWNtNGhNWDFtZFc1amRHbHZiaUJ1ZENobEtYdG1kVzVqZEdsdmJpQjBLRzRzY2l4c0xHa3NjeWw3ZEdocGN5NWZjbVZoWTNS'
    || 'T1lXMWxQVzRzZEdocGN5NWZkR0Z5WjJWMFNXNXpkRDFzTEhSb2FYTXVkSGx3WlQxeUxIUm9hWE11Ym1GMGFYWmxSWFpsYm5ROWFTeDBhR2x6TG5SaGNtZGxk'
    || 'RDF6TEhSb2FYTXVZM1Z5Y21WdWRGUmhjbWRsZEQxdWRXeHNPMlp2Y2loMllYSWdZeUJwYmlCbEtXVXVhR0Z6VDNkdVVISnZjR1Z5ZEhrb1l5a21KaWh1UFdW'
    || 'YlkxMHNkR2hwYzF0alhUMXVQMjRvYVNrNmFWdGpYU2s3Y21WMGRYSnVJSFJvYVhNdWFYTkVaV1poZFd4MFVISmxkbVZ1ZEdWa1BTaHBMbVJsWm1GMWJIUlFj'
    || 'bVYyWlc1MFpXUWhQVzUxYkd3L2FTNWtaV1poZFd4MFVISmxkbVZ1ZEdWa09ta3VjbVYwZFhKdVZtRnNkV1U5UFQwaE1Tay9jWEk2V0hNc2RHaHBjeTVwYzFC'
    || 'eWIzQmhaMkYwYVc5dVUzUnZjSEJsWkQxWWN5eDBhR2x6ZlhKbGRIVnliaUJKS0hRdWNISnZkRzkwZVhCbExIdHdjbVYyWlc1MFJHVm1ZWFZzZERwbWRXNWpk'
    || 'R2x2YmlncGUzUm9hWE11WkdWbVlYVnNkRkJ5WlhabGJuUmxaRDBoTUR0MllYSWdiajEwYUdsekxtNWhkR2wyWlVWMlpXNTBPMjRtSmlodUxuQnlaWFpsYm5S'
    || 'RVpXWmhkV3gwUDI0dWNISmxkbVZ1ZEVSbFptRjFiSFFvS1RwMGVYQmxiMllnYmk1eVpYUjFjbTVXWVd4MVpTRTlJblZ1YTI1dmQyNGlKaVlvYmk1eVpYUjFj'
    || 'bTVXWVd4MVpUMGhNU2tzZEdocGN5NXBjMFJsWm1GMWJIUlFjbVYyWlc1MFpXUTljWElwZlN4emRHOXdVSEp2Y0dGbllYUnBiMjQ2Wm5WdVkzUnBiMjRvS1h0'
    || 'MllYSWdiajEwYUdsekxtNWhkR2wyWlVWMlpXNTBPMjRtSmlodUxuTjBiM0JRY205d1lXZGhkR2x2Ymo5dUxuTjBiM0JRY205d1lXZGhkR2x2YmlncE9uUjVj'
    || 'R1Z2WmlCdUxtTmhibU5sYkVKMVltSnNaU0U5SW5WdWEyNXZkMjRpSmlZb2JpNWpZVzVqWld4Q2RXSmliR1U5SVRBcExIUm9hWE11YVhOUWNtOXdZV2RoZEds'
    || 'dmJsTjBiM0J3WldROWNYSXBmU3h3WlhKemFYTjBPbVoxYm1OMGFXOXVLQ2w3ZlN4cGMxQmxjbk5wYzNSbGJuUTZjWEo5S1N4MGZYWmhjaUJyYmoxN1pYWmxi'
    || 'blJRYUdGelpUb3dMR0oxWW1Kc1pYTTZNQ3hqWVc1alpXeGhZbXhsT2pBc2RHbHRaVk4wWVcxd09tWjFibU4wYVc5dUtHVXBlM0psZEhWeWJpQmxMblJwYldW'
    || 'VGRHRnRjSHg4UkdGMFpTNXViM2NvS1gwc1pHVm1ZWFZzZEZCeVpYWmxiblJsWkRvd0xHbHpWSEoxYzNSbFpEb3dmU3hyYVQxdWRDaHJiaWtzZFhJOVNTaDdm'
    || 'U3hyYml4N2RtbGxkem93TEdSbGRHRnBiRG93ZlNrc1RHUTliblFvZFhJcExHcHBMRU5wTEdGeUxFcHlQVWtvZTMwc2RYSXNlM05qY21WbGJsZzZNQ3h6WTNK'
    || 'bFpXNVpPakFzWTJ4cFpXNTBXRG93TEdOc2FXVnVkRms2TUN4d1lXZGxXRG93TEhCaFoyVlpPakFzWTNSeWJFdGxlVG93TEhOb2FXWjBTMlY1T2pBc1lXeDBT'
    || 'MlY1T2pBc2JXVjBZVXRsZVRvd0xHZGxkRTF2WkdsbWFXVnlVM1JoZEdVNlVta3NZblYwZEc5dU9qQXNZblYwZEc5dWN6b3dMSEpsYkdGMFpXUlVZWEpuWlhR'
    || 'NlpuVnVZM1JwYjI0b1pTbDdjbVYwZFhKdUlHVXVjbVZzWVhSbFpGUmhjbWRsZEQwOVBYWnZhV1FnTUQ5bExtWnliMjFGYkdWdFpXNTBQVDA5WlM1emNtTkZi'
    || 'R1Z0Wlc1MFAyVXVkRzlGYkdWdFpXNTBPbVV1Wm5KdmJVVnNaVzFsYm5RNlpTNXlaV3hoZEdWa1ZHRnlaMlYwZlN4dGIzWmxiV1Z1ZEZnNlpuVnVZM1JwYjI0'
    || 'b1pTbDdjbVYwZFhKdUltMXZkbVZ0Wlc1MFdDSnBiaUJsUDJVdWJXOTJaVzFsYm5SWU9paGxJVDA5WVhJbUppaGhjaVltWlM1MGVYQmxQVDA5SW0xdmRYTmxi'
    || 'VzkyWlNJL0tHcHBQV1V1YzJOeVpXVnVXQzFoY2k1elkzSmxaVzVZTEVOcFBXVXVjMk55WldWdVdTMWhjaTV6WTNKbFpXNVpLVHBEYVQxcWFUMHdMR0Z5UFdV'
    || 'cExHcHBLWDBzYlc5MlpXMWxiblJaT21aMWJtTjBhVzl1S0dVcGUzSmxkSFZ5YmlKdGIzWmxiV1Z1ZEZraWFXNGdaVDlsTG0xdmRtVnRaVzUwV1RwRGFYMTlL'
    || 'U3hhY3oxdWRDaEtjaWtzU1dROVNTaDdmU3hLY2l4N1pHRjBZVlJ5WVc1elptVnlPakI5S1N4QlpEMXVkQ2hKWkNrc2VtUTlTU2g3ZlN4MWNpeDdjbVZzWVhS'
    || 'bFpGUmhjbWRsZERvd2ZTa3NWR2s5Ym5Rb2VtUXBMRlZrUFVrb2UzMHNhMjRzZTJGdWFXMWhkR2x2Yms1aGJXVTZNQ3hsYkdGd2MyVmtWR2x0WlRvd0xIQnpa'
    || 'WFZrYjBWc1pXMWxiblE2TUgwcExFWmtQVzUwS0ZWa0tTeFhaRDFKS0h0OUxHdHVMSHRqYkdsd1ltOWhjbVJFWVhSaE9tWjFibU4wYVc5dUtHVXBlM0psZEhW'
    || 'eWJpSmpiR2x3WW05aGNtUkVZWFJoSW1sdUlHVS9aUzVqYkdsd1ltOWhjbVJFWVhSaE9uZHBibVJ2ZHk1amJHbHdZbTloY21SRVlYUmhmWDBwTENSa1BXNTBL'
    || 'RmRrS1N4V1pEMUpLSHQ5TEd0dUxIdGtZWFJoT2pCOUtTeHhjejF1ZENoV1pDa3NTR1E5ZTBWell6b2lSWE5qWVhCbElpeFRjR0ZqWldKaGNqb2lJQ0lzVEdW'
    || 'bWREb2lRWEp5YjNkTVpXWjBJaXhWY0RvaVFYSnliM2RWY0NJc1VtbG5hSFE2SWtGeWNtOTNVbWxuYUhRaUxFUnZkMjQ2SWtGeWNtOTNSRzkzYmlJc1JHVnNP'
    || 'aUpFWld4bGRHVWlMRmRwYmpvaVQxTWlMRTFsYm5VNklrTnZiblJsZUhSTlpXNTFJaXhCY0hCek9pSkRiMjUwWlhoMFRXVnVkU0lzVTJOeWIyeHNPaUpUWTNK'
    || 'dmJHeE1iMk5ySWl4TmIzcFFjbWx1ZEdGaWJHVkxaWGs2SWxWdWFXUmxiblJwWm1sbFpDSjlMRUprUFhzNE9pSkNZV05yYzNCaFkyVWlMRGs2SWxSaFlpSXNN'
    || 'VEk2SWtOc1pXRnlJaXd4TXpvaVJXNTBaWElpTERFMk9pSlRhR2xtZENJc01UYzZJa052Ym5SeWIyd2lMREU0T2lKQmJIUWlMREU1T2lKUVlYVnpaU0lzTWpB'
    || 'NklrTmhjSE5NYjJOcklpd3lOem9pUlhOallYQmxJaXd6TWpvaUlDSXNNek02SWxCaFoyVlZjQ0lzTXpRNklsQmhaMlZFYjNkdUlpd3pOVG9pUlc1a0lpd3pO'
    || 'am9pU0c5dFpTSXNNemM2SWtGeWNtOTNUR1ZtZENJc016ZzZJa0Z5Y205M1ZYQWlMRE01T2lKQmNuSnZkMUpwWjJoMElpdzBNRG9pUVhKeWIzZEViM2R1SWl3'
    || 'ME5Ub2lTVzV6WlhKMElpdzBOam9pUkdWc1pYUmxJaXd4TVRJNklrWXhJaXd4TVRNNklrWXlJaXd4TVRRNklrWXpJaXd4TVRVNklrWTBJaXd4TVRZNklrWTFJ'
    || 'aXd4TVRjNklrWTJJaXd4TVRnNklrWTNJaXd4TVRrNklrWTRJaXd4TWpBNklrWTVJaXd4TWpFNklrWXhNQ0lzTVRJeU9pSkdNVEVpTERFeU16b2lSakV5SWl3'
    || 'eE5EUTZJazUxYlV4dlkyc2lMREUwTlRvaVUyTnliMnhzVEc5amF5SXNNakkwT2lKTlpYUmhJbjBzVVdROWUwRnNkRG9pWVd4MFMyVjVJaXhEYjI1MGNtOXNP'
    || 'aUpqZEhKc1MyVjVJaXhOWlhSaE9pSnRaWFJoUzJWNUlpeFRhR2xtZERvaWMyaHBablJMWlhraWZUdG1kVzVqZEdsdmJpQkhaQ2hsS1h0MllYSWdkRDEwYUds'
    || 'ekxtNWhkR2wyWlVWMlpXNTBPM0psZEhWeWJpQjBMbWRsZEUxdlpHbG1hV1Z5VTNSaGRHVS9kQzVuWlhSTmIyUnBabWxsY2xOMFlYUmxLR1VwT2lobFBWRmtX'
    || 'MlZkS1Q4aElYUmJaVjA2SVRGOVpuVnVZM1JwYjI0Z1Vta29LWHR5WlhSMWNtNGdSMlI5ZG1GeUlGbGtQVWtvZTMwc2RYSXNlMnRsZVRwbWRXNWpkR2x2Ymlo'
    || 'bEtYdHBaaWhsTG10bGVTbDdkbUZ5SUhROVNHUmJaUzVyWlhsZGZIeGxMbXRsZVR0cFppaDBJVDA5SWxWdWFXUmxiblJwWm1sbFpDSXBjbVYwZFhKdUlIUjlj'
    || 'bVYwZFhKdUlHVXVkSGx3WlQwOVBTSnJaWGx3Y21WemN5SS9LR1U5V25Jb1pTa3NaVDA5UFRFelB5SkZiblJsY2lJNlUzUnlhVzVuTG1aeWIyMURhR0Z5UTI5'
    || 'a1pTaGxLU2s2WlM1MGVYQmxQVDA5SW10bGVXUnZkMjRpZkh4bExuUjVjR1U5UFQwaWEyVjVkWEFpUDBKa1cyVXVhMlY1UTI5a1pWMThmQ0pWYm1sa1pXNTBh'
    || 'V1pwWldRaU9pSWlmU3hqYjJSbE9qQXNiRzlqWVhScGIyNDZNQ3hqZEhKc1MyVjVPakFzYzJocFpuUkxaWGs2TUN4aGJIUkxaWGs2TUN4dFpYUmhTMlY1T2pB'
    || 'c2NtVndaV0YwT2pBc2JHOWpZV3hsT2pBc1oyVjBUVzlrYVdacFpYSlRkR0YwWlRwU2FTeGphR0Z5UTI5a1pUcG1kVzVqZEdsdmJpaGxLWHR5WlhSMWNtNGda'
    || 'UzUwZVhCbFBUMDlJbXRsZVhCeVpYTnpJajlhY2lobEtUb3dmU3hyWlhsRGIyUmxPbVoxYm1OMGFXOXVLR1VwZTNKbGRIVnliaUJsTG5SNWNHVTlQVDBpYTJW'
    || 'NVpHOTNiaUo4ZkdVdWRIbHdaVDA5UFNKclpYbDFjQ0kvWlM1clpYbERiMlJsT2pCOUxIZG9hV05vT21aMWJtTjBhVzl1S0dVcGUzSmxkSFZ5YmlCbExuUjVj'
    || 'R1U5UFQwaWEyVjVjSEpsYzNNaVAxcHlLR1VwT21VdWRIbHdaVDA5UFNKclpYbGtiM2R1SW54OFpTNTBlWEJsUFQwOUltdGxlWFZ3SWo5bExtdGxlVU52WkdV'
    || 'Nk1IMTlLU3hMWkQxdWRDaFpaQ2tzV0dROVNTaDdmU3hLY2l4N2NHOXBiblJsY2tsa09qQXNkMmxrZEdnNk1DeG9aV2xuYUhRNk1DeHdjbVZ6YzNWeVpUb3dM'
    || 'SFJoYm1kbGJuUnBZV3hRY21WemMzVnlaVG93TEhScGJIUllPakFzZEdsc2RGazZNQ3gwZDJsemREb3dMSEJ2YVc1MFpYSlVlWEJsT2pBc2FYTlFjbWx0WVhK'
    || 'NU9qQjlLU3hLY3oxdWRDaFlaQ2tzV21ROVNTaDdmU3gxY2l4N2RHOTFZMmhsY3pvd0xIUmhjbWRsZEZSdmRXTm9aWE02TUN4amFHRnVaMlZrVkc5MVkyaGxj'
    || 'em93TEdGc2RFdGxlVG93TEcxbGRHRkxaWGs2TUN4amRISnNTMlY1T2pBc2MyaHBablJMWlhrNk1DeG5aWFJOYjJScFptbGxjbE4wWVhSbE9sSnBmU2tzY1dR'
    || 'OWJuUW9XbVFwTEVwa1BVa29lMzBzYTI0c2UzQnliM0JsY25SNVRtRnRaVG93TEdWc1lYQnpaV1JVYVcxbE9qQXNjSE5sZFdSdlJXeGxiV1Z1ZERvd2ZTa3NZ'
    || 'bVE5Ym5Rb1NtUXBMR1ZtUFVrb2UzMHNTbklzZTJSbGJIUmhXRHBtZFc1amRHbHZiaWhsS1h0eVpYUjFjbTRpWkdWc2RHRllJbWx1SUdVL1pTNWtaV3gwWVZn'
    || 'NkluZG9aV1ZzUkdWc2RHRllJbWx1SUdVL0xXVXVkMmhsWld4RVpXeDBZVmc2TUgwc1pHVnNkR0ZaT21aMWJtTjBhVzl1S0dVcGUzSmxkSFZ5YmlKa1pXeDBZ'
    || 'VmtpYVc0Z1pUOWxMbVJsYkhSaFdUb2lkMmhsWld4RVpXeDBZVmtpYVc0Z1pUOHRaUzUzYUdWbGJFUmxiSFJoV1RvaWQyaGxaV3hFWld4MFlTSnBiaUJsUHkx'
    || 'bExuZG9aV1ZzUkdWc2RHRTZNSDBzWkdWc2RHRmFPakFzWkdWc2RHRk5iMlJsT2pCOUtTeDBaajF1ZENobFppa3NibVk5V3prc01UTXNNamNzTXpKZExFOXBQ'
    || 'WGNtSmlKRGIyMXdiM05wZEdsdmJrVjJaVzUwSW1sdUlIZHBibVJ2ZHl4amNqMXVkV3hzTzNjbUppSmtiMk4xYldWdWRFMXZaR1VpYVc0Z1pHOWpkVzFsYm5R'
    || 'bUppaGpjajFrYjJOMWJXVnVkQzVrYjJOMWJXVnVkRTF2WkdVcE8zWmhjaUJ5WmoxM0ppWWlWR1Y0ZEVWMlpXNTBJbWx1SUhkcGJtUnZkeVltSVdOeUxHSnpQ'
    || 'WGNtSmlnaFQybDhmR055SmlZNFBHTnlKaVl4TVQ0OVkzSXBMR1YxUFNJZ0lpeDBkVDBoTVR0bWRXNWpkR2x2YmlCdWRTaGxMSFFwZTNOM2FYUmphQ2hsS1h0'
    || 'allYTmxJbXRsZVhWd0lqcHlaWFIxY200Z2JtWXVhVzVrWlhoUFppaDBMbXRsZVVOdlpHVXBJVDA5TFRFN1kyRnpaU0pyWlhsa2IzZHVJanB5WlhSMWNtNGdk'
    || 'QzVyWlhsRGIyUmxJVDA5TWpJNU8yTmhjMlVpYTJWNWNISmxjM01pT21OaGMyVWliVzkxYzJWa2IzZHVJanBqWVhObEltWnZZM1Z6YjNWMElqcHlaWFIxY200'
    || 'aE1EdGtaV1poZFd4ME9uSmxkSFZ5YmlFeGZYMW1kVzVqZEdsdmJpQnlkU2hsS1h0eVpYUjFjbTRnWlQxbExtUmxkR0ZwYkN4MGVYQmxiMllnWlQwOUltOWlh'
    || 'bVZqZENJbUppSmtZWFJoSW1sdUlHVS9aUzVrWVhSaE9tNTFiR3g5ZG1GeUlHcHVQU0V4TzJaMWJtTjBhVzl1SUd4bUtHVXNkQ2w3YzNkcGRHTm9LR1VwZTJO'
    || 'aGMyVWlZMjl0Y0c5emFYUnBiMjVsYm1RaU9uSmxkSFZ5YmlCeWRTaDBLVHRqWVhObEltdGxlWEJ5WlhOeklqcHlaWFIxY200Z2RDNTNhR2xqYUNFOVBUTXlQ'
    || 'MjUxYkd3NktIUjFQU0V3TEdWMUtUdGpZWE5sSW5SbGVIUkpibkIxZENJNmNtVjBkWEp1SUdVOWRDNWtZWFJoTEdVOVBUMWxkU1ltZEhVL2JuVnNiRHBsTzJS'
    || 'bFptRjFiSFE2Y21WMGRYSnVJRzUxYkd4OWZXWjFibU4wYVc5dUlHOW1LR1VzZENsN2FXWW9hbTRwY21WMGRYSnVJR1U5UFQwaVkyOXRjRzl6YVhScGIyNWxi'
    || 'bVFpZkh3aFQya21KbTUxS0dVc2RDay9LR1U5UzNNb0tTeFljajFPYVQxV2REMXVkV3hzTEdwdVBTRXhMR1VwT201MWJHdzdjM2RwZEdOb0tHVXBlMk5oYzJV'
    || 'aWNHRnpkR1VpT25KbGRIVnliaUJ1ZFd4c08yTmhjMlVpYTJWNWNISmxjM01pT21sbUtDRW9kQzVqZEhKc1MyVjVmSHgwTG1Gc2RFdGxlWHg4ZEM1dFpYUmhT'
    || 'MlY1S1h4OGRDNWpkSEpzUzJWNUppWjBMbUZzZEV0bGVTbDdhV1lvZEM1amFHRnlKaVl4UEhRdVkyaGhjaTVzWlc1bmRHZ3BjbVYwZFhKdUlIUXVZMmhoY2p0'
    || 'cFppaDBMbmRvYVdOb0tYSmxkSFZ5YmlCVGRISnBibWN1Wm5KdmJVTm9ZWEpEYjJSbEtIUXVkMmhwWTJncGZYSmxkSFZ5YmlCdWRXeHNPMk5oYzJVaVkyOXRj'
    || 'Rzl6YVhScGIyNWxibVFpT25KbGRIVnliaUJpY3lZbWRDNXNiMk5oYkdVaFBUMGlhMjhpUDI1MWJHdzZkQzVrWVhSaE8yUmxabUYxYkhRNmNtVjBkWEp1SUc1'
    || 'MWJHeDlmWFpoY2lCelpqMTdZMjlzYjNJNklUQXNaR0YwWlRvaE1DeGtZWFJsZEdsdFpUb2hNQ3dpWkdGMFpYUnBiV1V0Ykc5allXd2lPaUV3TEdWdFlXbHNP'
    || 'aUV3TEcxdmJuUm9PaUV3TEc1MWJXSmxjam9oTUN4d1lYTnpkMjl5WkRvaE1DeHlZVzVuWlRvaE1DeHpaV0Z5WTJnNklUQXNkR1ZzT2lFd0xIUmxlSFE2SVRB'
    || 'c2RHbHRaVG9oTUN4MWNtdzZJVEFzZDJWbGF6b2hNSDA3Wm5WdVkzUnBiMjRnYkhVb1pTbDdkbUZ5SUhROVpTWW1aUzV1YjJSbFRtRnRaU1ltWlM1dWIyUmxU'
    || 'bUZ0WlM1MGIweHZkMlZ5UTJGelpTZ3BPM0psZEhWeWJpQjBQVDA5SW1sdWNIVjBJajhoSVhObVcyVXVkSGx3WlYwNmREMDlQU0owWlhoMFlYSmxZU0o5Wm5W'
    || 'dVkzUnBiMjRnYVhVb1pTeDBMRzRzY2lsN2EzTW9jaWtzZEQxeWJDaDBMQ0p2YmtOb1lXNW5aU0lwTERBOGRDNXNaVzVuZEdnbUppaHVQVzVsZHlCcmFTZ2li'
    || 'MjVEYUdGdVoyVWlMQ0pqYUdGdVoyVWlMRzUxYkd3c2JpeHlLU3hsTG5CMWMyZ29lMlYyWlc1ME9tNHNiR2x6ZEdWdVpYSnpPblI5S1NsOWRtRnlJR1J5UFc1'
    || 'MWJHd3Nabkk5Ym5Wc2JEdG1kVzVqZEdsdmJpQjFaaWhsS1h0RmRTaGxMREFwZldaMWJtTjBhVzl1SUdKeUtHVXBlM1poY2lCMFBVMXVLR1VwTzJsbUtIQnpL'
    || 'SFFwS1hKbGRIVnliaUJsZldaMWJtTjBhVzl1SUdGbUtHVXNkQ2w3YVdZb1pUMDlQU0pqYUdGdVoyVWlLWEpsZEhWeWJpQjBmWFpoY2lCdmRUMGhNVHRwWmlo'
    || 'M0tYdDJZWElnVFdrN2FXWW9keWw3ZG1GeUlFUnBQU0p2Ym1sdWNIVjBJbWx1SUdSdlkzVnRaVzUwTzJsbUtDRkVhU2w3ZG1GeUlITjFQV1J2WTNWdFpXNTBM'
    || 'bU55WldGMFpVVnNaVzFsYm5Rb0ltUnBkaUlwTzNOMUxuTmxkRUYwZEhKcFluVjBaU2dpYjI1cGJuQjFkQ0lzSW5KbGRIVnlianNpS1N4RWFUMTBlWEJsYjJZ'
    || 'Z2MzVXViMjVwYm5CMWREMDlJbVoxYm1OMGFXOXVJbjFOYVQxRWFYMWxiSE5sSUUxcFBTRXhPMjkxUFUxcEppWW9JV1J2WTNWdFpXNTBMbVJ2WTNWdFpXNTBU'
    || 'VzlrWlh4OE9UeGtiMk4xYldWdWRDNWtiMk4xYldWdWRFMXZaR1VwZldaMWJtTjBhVzl1SUhWMUtDbDdaSEltSmloa2NpNWtaWFJoWTJoRmRtVnVkQ2dpYjI1'
    || 'd2NtOXdaWEowZVdOb1lXNW5aU0lzWVhVcExHWnlQV1J5UFc1MWJHd3BmV1oxYm1OMGFXOXVJR0YxS0dVcGUybG1LR1V1Y0hKdmNHVnlkSGxPWVcxbFBUMDlJ'
    || 'blpoYkhWbElpWW1ZbklvWm5JcEtYdDJZWElnZEQxYlhUdHBkU2gwTEdaeUxHVXNaR2tvWlNrcExGSnpLSFZtTEhRcGZYMW1kVzVqZEdsdmJpQmpaaWhsTEhR'
    || 'c2JpbDdaVDA5UFNKbWIyTjFjMmx1SWo4b2RYVW9LU3hrY2oxMExHWnlQVzRzWkhJdVlYUjBZV05vUlhabGJuUW9JbTl1Y0hKdmNHVnlkSGxqYUdGdVoyVWlM'
    || 'R0YxS1NrNlpUMDlQU0ptYjJOMWMyOTFkQ0ltSm5WMUtDbDlablZ1WTNScGIyNGdaR1lvWlNsN2FXWW9aVDA5UFNKelpXeGxZM1JwYjI1amFHRnVaMlVpZkh4'
    || 'bFBUMDlJbXRsZVhWd0lueDhaVDA5UFNKclpYbGtiM2R1SWlseVpYUjFjbTRnWW5Jb1puSXBmV1oxYm1OMGFXOXVJR1ptS0dVc2RDbDdhV1lvWlQwOVBTSmpi'
    || 'R2xqYXlJcGNtVjBkWEp1SUdKeUtIUXBmV1oxYm1OMGFXOXVJSEJtS0dVc2RDbDdhV1lvWlQwOVBTSnBibkIxZENKOGZHVTlQVDBpWTJoaGJtZGxJaWx5WlhS'
    || 'MWNtNGdZbklvZENsOVpuVnVZM1JwYjI0Z2FHWW9aU3gwS1h0eVpYUjFjbTRnWlQwOVBYUW1KaWhsSVQwOU1IeDhNUzlsUFQwOU1TOTBLWHg4WlNFOVBXVW1K'
    || 'blFoUFQxMGZYWmhjaUJ0ZEQxMGVYQmxiMllnVDJKcVpXTjBMbWx6UFQwaVpuVnVZM1JwYjI0aVAwOWlhbVZqZEM1cGN6cG9aanRtZFc1amRHbHZiaUJ3Y2lo'
    || 'bExIUXBlMmxtS0cxMEtHVXNkQ2twY21WMGRYSnVJVEE3YVdZb2RIbHdaVzltSUdVaFBTSnZZbXBsWTNRaWZIeGxQVDA5Ym5Wc2JIeDhkSGx3Wlc5bUlIUWhQ'
    || 'U0p2WW1wbFkzUWlmSHgwUFQwOWJuVnNiQ2x5WlhSMWNtNGhNVHQyWVhJZ2JqMVBZbXBsWTNRdWEyVjVjeWhsS1N4eVBVOWlhbVZqZEM1clpYbHpLSFFwTzJs'
    || 'bUtHNHViR1Z1WjNSb0lUMDljaTVzWlc1bmRHZ3BjbVYwZFhKdUlURTdabTl5S0hJOU1EdHlQRzR1YkdWdVozUm9PM0lyS3lsN2RtRnlJR3c5Ymx0eVhUdHBa'
    || 'aWdoWHk1allXeHNLSFFzYkNsOGZDRnRkQ2hsVzJ4ZExIUmJiRjBwS1hKbGRIVnliaUV4ZlhKbGRIVnliaUV3ZldaMWJtTjBhVzl1SUdOMUtHVXBlMlp2Y2ln'
    || 'N1pTWW1aUzVtYVhKemRFTm9hV3hrT3lsbFBXVXVabWx5YzNSRGFHbHNaRHR5WlhSMWNtNGdaWDFtZFc1amRHbHZiaUJrZFNobExIUXBlM1poY2lCdVBXTjFL'
    || 'R1VwTzJVOU1EdG1iM0lvZG1GeUlISTdianNwZTJsbUtHNHVibTlrWlZSNWNHVTlQVDB6S1h0cFppaHlQV1VyYmk1MFpYaDBRMjl1ZEdWdWRDNXNaVzVuZEdn'
    || 'c1pUdzlkQ1ltY2o0OWRDbHlaWFIxY201N2JtOWtaVHB1TEc5bVpuTmxkRHAwTFdWOU8yVTljbjFsT250bWIzSW9PMjQ3S1h0cFppaHVMbTVsZUhSVGFXSnNh'
    || 'VzVuS1h0dVBXNHVibVY0ZEZOcFlteHBibWM3WW5KbFlXc2daWDF1UFc0dWNHRnlaVzUwVG05a1pYMXVQWFp2YVdRZ01IMXVQV04xS0c0cGZYMW1kVzVqZEds'
    || 'dmJpQm1kU2hsTEhRcGUzSmxkSFZ5YmlCbEppWjBQMlU5UFQxMFB5RXdPbVVtSm1VdWJtOWtaVlI1Y0dVOVBUMHpQeUV4T25RbUpuUXVibTlrWlZSNWNHVTlQ'
    || 'VDB6UDJaMUtHVXNkQzV3WVhKbGJuUk9iMlJsS1RvaVkyOXVkR0ZwYm5NaWFXNGdaVDlsTG1OdmJuUmhhVzV6S0hRcE9tVXVZMjl0Y0dGeVpVUnZZM1Z0Wlc1'
    || 'MFVHOXphWFJwYjI0L0lTRW9aUzVqYjIxd1lYSmxSRzlqZFcxbGJuUlFiM05wZEdsdmJpaDBLU1l4TmlrNklURTZJVEY5Wm5WdVkzUnBiMjRnY0hVb0tYdG1i'
    || 'M0lvZG1GeUlHVTlkMmx1Wkc5M0xIUTlRWElvS1R0MElHbHVjM1JoYm1ObGIyWWdaUzVJVkUxTVNVWnlZVzFsUld4bGJXVnVkRHNwZTNSeWVYdDJZWElnYmox'
    || 'MGVYQmxiMllnZEM1amIyNTBaVzUwVjJsdVpHOTNMbXh2WTJGMGFXOXVMbWh5WldZOVBTSnpkSEpwYm1jaWZXTmhkR05vZTI0OUlURjlhV1lvYmlsbFBYUXVZ'
    || 'Mjl1ZEdWdWRGZHBibVJ2ZHp0bGJITmxJR0p5WldGck8zUTlRWElvWlM1a2IyTjFiV1Z1ZENsOWNtVjBkWEp1SUhSOVpuVnVZM1JwYjI0Z1VHa29aU2w3ZG1G'
    || 'eUlIUTlaU1ltWlM1dWIyUmxUbUZ0WlNZbVpTNXViMlJsVG1GdFpTNTBiMHh2ZDJWeVEyRnpaU2dwTzNKbGRIVnliaUIwSmlZb2REMDlQU0pwYm5CMWRDSW1K'
    || 'aWhsTG5SNWNHVTlQVDBpZEdWNGRDSjhmR1V1ZEhsd1pUMDlQU0p6WldGeVkyZ2lmSHhsTG5SNWNHVTlQVDBpZEdWc0lueDhaUzUwZVhCbFBUMDlJblZ5YkNK'
    || 'OGZHVXVkSGx3WlQwOVBTSndZWE56ZDI5eVpDSXBmSHgwUFQwOUluUmxlSFJoY21WaElueDhaUzVqYjI1MFpXNTBSV1JwZEdGaWJHVTlQVDBpZEhKMVpTSXBm'
    || 'V1oxYm1OMGFXOXVJRzFtS0dVcGUzWmhjaUIwUFhCMUtDa3NiajFsTG1adlkzVnpaV1JGYkdWdExISTlaUzV6Wld4bFkzUnBiMjVTWVc1blpUdHBaaWgwSVQw'
    || 'OWJpWW1iaVltYmk1dmQyNWxja1J2WTNWdFpXNTBKaVptZFNodUxtOTNibVZ5Ukc5amRXMWxiblF1Wkc5amRXMWxiblJGYkdWdFpXNTBMRzRwS1h0cFppaHlJ'
    || 'VDA5Ym5Wc2JDWW1VR2tvYmlrcGUybG1LSFE5Y2k1emRHRnlkQ3hsUFhJdVpXNWtMR1U5UFQxMmIybGtJREFtSmlobFBYUXBMQ0p6Wld4bFkzUnBiMjVUZEdG'
    || 'eWRDSnBiaUJ1S1c0dWMyVnNaV04wYVc5dVUzUmhjblE5ZEN4dUxuTmxiR1ZqZEdsdmJrVnVaRDFOWVhSb0xtMXBiaWhsTEc0dWRtRnNkV1V1YkdWdVozUm9L'
    || 'VHRsYkhObElHbG1LR1U5S0hROWJpNXZkMjVsY2tSdlkzVnRaVzUwZkh4a2IyTjFiV1Z1ZENrbUpuUXVaR1ZtWVhWc2RGWnBaWGQ4ZkhkcGJtUnZkeXhsTG1k'
    || 'bGRGTmxiR1ZqZEdsdmJpbDdaVDFsTG1kbGRGTmxiR1ZqZEdsdmJpZ3BPM1poY2lCc1BXNHVkR1Y0ZEVOdmJuUmxiblF1YkdWdVozUm9MR2s5VFdGMGFDNXRh'
    || 'VzRvY2k1emRHRnlkQ3hzS1R0eVBYSXVaVzVrUFQwOWRtOXBaQ0F3UDJrNlRXRjBhQzV0YVc0b2NpNWxibVFzYkNrc0lXVXVaWGgwWlc1a0ppWnBQbkltSmlo'
    || 'c1BYSXNjajFwTEdrOWJDa3NiRDFrZFNodUxHa3BPM1poY2lCelBXUjFLRzRzY2lrN2JDWW1jeVltS0dVdWNtRnVaMlZEYjNWdWRDRTlQVEY4ZkdVdVlXNWph'
    || 'Rzl5VG05a1pTRTlQV3d1Ym05a1pYeDhaUzVoYm1Ob2IzSlBabVp6WlhRaFBUMXNMbTltWm5ObGRIeDhaUzVtYjJOMWMwNXZaR1VoUFQxekxtNXZaR1Y4ZkdV'
    || 'dVptOWpkWE5QWm1aelpYUWhQVDF6TG05bVpuTmxkQ2ttSmloMFBYUXVZM0psWVhSbFVtRnVaMlVvS1N4MExuTmxkRk4wWVhKMEtHd3VibTlrWlN4c0xtOW1a'
    || 'bk5sZENrc1pTNXlaVzF2ZG1WQmJHeFNZVzVuWlhNb0tTeHBQbkkvS0dVdVlXUmtVbUZ1WjJVb2RDa3NaUzVsZUhSbGJtUW9jeTV1YjJSbExITXViMlptYzJW'
    || 'MEtTazZLSFF1YzJWMFJXNWtLSE11Ym05a1pTeHpMbTltWm5ObGRDa3NaUzVoWkdSU1lXNW5aU2gwS1NrcGZYMW1iM0lvZEQxYlhTeGxQVzQ3WlQxbExuQmhj'
    || 'bVZ1ZEU1dlpHVTdLV1V1Ym05a1pWUjVjR1U5UFQweEppWjBMbkIxYzJnb2UyVnNaVzFsYm5RNlpTeHNaV1owT21VdWMyTnliMnhzVEdWbWRDeDBiM0E2WlM1'
    || 'elkzSnZiR3hVYjNCOUtUdG1iM0lvZEhsd1pXOW1JRzR1Wm05amRYTTlQU0ptZFc1amRHbHZiaUltSm00dVptOWpkWE1vS1N4dVBUQTdiangwTG14bGJtZDBh'
    || 'RHR1S3lzcFpUMTBXMjVkTEdVdVpXeGxiV1Z1ZEM1elkzSnZiR3hNWldaMFBXVXViR1ZtZEN4bExtVnNaVzFsYm5RdWMyTnliMnhzVkc5d1BXVXVkRzl3Zlgx'
    || 'MllYSWdkbVk5ZHlZbUltUnZZM1Z0Wlc1MFRXOWtaU0pwYmlCa2IyTjFiV1Z1ZENZbU1URStQV1J2WTNWdFpXNTBMbVJ2WTNWdFpXNTBUVzlrWlN4RGJqMXVk'
    || 'V3hzTEV4cFBXNTFiR3dzYUhJOWJuVnNiQ3hKYVQwaE1UdG1kVzVqZEdsdmJpQm9kU2hsTEhRc2JpbDdkbUZ5SUhJOWJpNTNhVzVrYjNjOVBUMXVQMjR1Wkc5'
    || 'amRXMWxiblE2Ymk1dWIyUmxWSGx3WlQwOVBUay9ianB1TG05M2JtVnlSRzlqZFcxbGJuUTdTV2w4ZkVOdVBUMXVkV3hzZkh4RGJpRTlQVUZ5S0hJcGZId29j'
    || 'ajFEYml3aWMyVnNaV04wYVc5dVUzUmhjblFpYVc0Z2NpWW1VR2tvY2lrL2NqMTdjM1JoY25RNmNpNXpaV3hsWTNScGIyNVRkR0Z5ZEN4bGJtUTZjaTV6Wld4'
    || 'bFkzUnBiMjVGYm1SOU9paHlQU2h5TG05M2JtVnlSRzlqZFcxbGJuUW1Kbkl1YjNkdVpYSkViMk4xYldWdWRDNWtaV1poZFd4MFZtbGxkM3g4ZDJsdVpHOTNL'
    || 'UzVuWlhSVFpXeGxZM1JwYjI0b0tTeHlQWHRoYm1Ob2IzSk9iMlJsT25JdVlXNWphRzl5VG05a1pTeGhibU5vYjNKUFptWnpaWFE2Y2k1aGJtTm9iM0pQWm1a'
    || 'elpYUXNabTlqZFhOT2IyUmxPbkl1Wm05amRYTk9iMlJsTEdadlkzVnpUMlptYzJWME9uSXVabTlqZFhOUFptWnpaWFI5S1N4b2NpWW1jSElvYUhJc2NpbDhm'
    || 'Q2hvY2oxeUxISTljbXdvVEdrc0ltOXVVMlZzWldOMElpa3NNRHh5TG14bGJtZDBhQ1ltS0hROWJtVjNJR3RwS0NKdmJsTmxiR1ZqZENJc0luTmxiR1ZqZENJ'
    || 'c2JuVnNiQ3gwTEc0cExHVXVjSFZ6YUNoN1pYWmxiblE2ZEN4c2FYTjBaVzVsY25NNmNuMHBMSFF1ZEdGeVoyVjBQVU51S1NrcGZXWjFibU4wYVc5dUlHVnNL'
    || 'R1VzZENsN2RtRnlJRzQ5ZTMwN2NtVjBkWEp1SUc1YlpTNTBiMHh2ZDJWeVEyRnpaU2dwWFQxMExuUnZURzkzWlhKRFlYTmxLQ2tzYmxzaVYyVmlhMmwwSWl0'
    || 'bFhUMGlkMlZpYTJsMElpdDBMRzViSWsxdmVpSXJaVjA5SW0xdmVpSXJkQ3h1ZlhaaGNpQlViajE3WVc1cGJXRjBhVzl1Wlc1a09tVnNLQ0pCYm1sdFlYUnBi'
    || 'MjRpTENKQmJtbHRZWFJwYjI1RmJtUWlLU3hoYm1sdFlYUnBiMjVwZEdWeVlYUnBiMjQ2Wld3b0lrRnVhVzFoZEdsdmJpSXNJa0Z1YVcxaGRHbHZia2wwWlhK'
    || 'aGRHbHZiaUlwTEdGdWFXMWhkR2x2Ym5OMFlYSjBPbVZzS0NKQmJtbHRZWFJwYjI0aUxDSkJibWx0WVhScGIyNVRkR0Z5ZENJcExIUnlZVzV6YVhScGIyNWxi'
    || 'bVE2Wld3b0lsUnlZVzV6YVhScGIyNGlMQ0pVY21GdWMybDBhVzl1Ulc1a0lpbDlMRUZwUFh0OUxHMTFQWHQ5TzNjbUppaHRkVDFrYjJOMWJXVnVkQzVqY21W'
    || 'aGRHVkZiR1Z0Wlc1MEtDSmthWFlpS1M1emRIbHNaU3dpUVc1cGJXRjBhVzl1UlhabGJuUWlhVzRnZDJsdVpHOTNmSHdvWkdWc1pYUmxJRlJ1TG1GdWFXMWhk'
    || 'R2x2Ym1WdVpDNWhibWx0WVhScGIyNHNaR1ZzWlhSbElGUnVMbUZ1YVcxaGRHbHZibWwwWlhKaGRHbHZiaTVoYm1sdFlYUnBiMjRzWkdWc1pYUmxJRlJ1TG1G'
    || 'dWFXMWhkR2x2Ym5OMFlYSjBMbUZ1YVcxaGRHbHZiaWtzSWxSeVlXNXphWFJwYjI1RmRtVnVkQ0pwYmlCM2FXNWtiM2Q4ZkdSbGJHVjBaU0JVYmk1MGNtRnVj'
    || 'MmwwYVc5dVpXNWtMblJ5WVc1emFYUnBiMjRwTzJaMWJtTjBhVzl1SUhSc0tHVXBlMmxtS0VGcFcyVmRLWEpsZEhWeWJpQkJhVnRsWFR0cFppZ2hWRzViWlYw'
    || 'cGNtVjBkWEp1SUdVN2RtRnlJSFE5Vkc1YlpWMHNianRtYjNJb2JpQnBiaUIwS1dsbUtIUXVhR0Z6VDNkdVVISnZjR1Z5ZEhrb2Jpa21KbTRnYVc0Z2JYVXBj'
    || 'bVYwZFhKdUlFRnBXMlZkUFhSYmJsMDdjbVYwZFhKdUlHVjlkbUZ5SUhaMVBYUnNLQ0poYm1sdFlYUnBiMjVsYm1RaUtTeG5kVDEwYkNnaVlXNXBiV0YwYVc5'
    || 'dWFYUmxjbUYwYVc5dUlpa3NlWFU5ZEd3b0ltRnVhVzFoZEdsdmJuTjBZWEowSWlrc2VIVTlkR3dvSW5SeVlXNXphWFJwYjI1bGJtUWlLU3hUZFQxdVpYY2dU'
    || 'V0Z3TEhkMVBTSmhZbTl5ZENCaGRYaERiR2xqYXlCallXNWpaV3dnWTJGdVVHeGhlU0JqWVc1UWJHRjVWR2h5YjNWbmFDQmpiR2xqYXlCamJHOXpaU0JqYjI1'
    || 'MFpYaDBUV1Z1ZFNCamIzQjVJR04xZENCa2NtRm5JR1J5WVdkRmJtUWdaSEpoWjBWdWRHVnlJR1J5WVdkRmVHbDBJR1J5WVdkTVpXRjJaU0JrY21GblQzWmxj'
    || 'aUJrY21GblUzUmhjblFnWkhKdmNDQmtkWEpoZEdsdmJrTm9ZVzVuWlNCbGJYQjBhV1ZrSUdWdVkzSjVjSFJsWkNCbGJtUmxaQ0JsY25KdmNpQm5iM1JRYjJs'
    || 'dWRHVnlRMkZ3ZEhWeVpTQnBibkIxZENCcGJuWmhiR2xrSUd0bGVVUnZkMjRnYTJWNVVISmxjM01nYTJWNVZYQWdiRzloWkNCc2IyRmtaV1JFWVhSaElHeHZZ'
    || 'V1JsWkUxbGRHRmtZWFJoSUd4dllXUlRkR0Z5ZENCc2IzTjBVRzlwYm5SbGNrTmhjSFIxY21VZ2JXOTFjMlZFYjNkdUlHMXZkWE5sVFc5MlpTQnRiM1Z6WlU5'
    || 'MWRDQnRiM1Z6WlU5MlpYSWdiVzkxYzJWVmNDQndZWE4wWlNCd1lYVnpaU0J3YkdGNUlIQnNZWGxwYm1jZ2NHOXBiblJsY2tOaGJtTmxiQ0J3YjJsdWRHVnlS'
    || 'RzkzYmlCd2IybHVkR1Z5VFc5MlpTQndiMmx1ZEdWeVQzVjBJSEJ2YVc1MFpYSlBkbVZ5SUhCdmFXNTBaWEpWY0NCd2NtOW5jbVZ6Y3lCeVlYUmxRMmhoYm1k'
    || 'bElISmxjMlYwSUhKbGMybDZaU0J6WldWclpXUWdjMlZsYTJsdVp5QnpkR0ZzYkdWa0lITjFZbTFwZENCemRYTndaVzVrSUhScGJXVlZjR1JoZEdVZ2RHOTFZ'
    || 'MmhEWVc1alpXd2dkRzkxWTJoRmJtUWdkRzkxWTJoVGRHRnlkQ0IyYjJ4MWJXVkRhR0Z1WjJVZ2MyTnliMnhzSUhSdloyZHNaU0IwYjNWamFFMXZkbVVnZDJG'
    || 'cGRHbHVaeUIzYUdWbGJDSXVjM0JzYVhRb0lpQWlLVHRtZFc1amRHbHZiaUJJZENobExIUXBlMU4xTG5ObGRDaGxMSFFwTEVNb2RDeGJaVjBwZldadmNpaDJZ'
    || 'WElnZW1rOU1EdDZhVHgzZFM1c1pXNW5kR2c3ZW1rckt5bDdkbUZ5SUZWcFBYZDFXM3BwWFN4blpqMVZhUzUwYjB4dmQyVnlRMkZ6WlNncExIbG1QVlZwV3pC'
    || 'ZExuUnZWWEJ3WlhKRFlYTmxLQ2tyVldrdWMyeHBZMlVvTVNrN1NIUW9aMllzSW05dUlpdDVaaWw5U0hRb2RuVXNJbTl1UVc1cGJXRjBhVzl1Ulc1a0lpa3NT'
    || 'SFFvWjNVc0ltOXVRVzVwYldGMGFXOXVTWFJsY21GMGFXOXVJaWtzU0hRb2VYVXNJbTl1UVc1cGJXRjBhVzl1VTNSaGNuUWlLU3hJZENnaVpHSnNZMnhwWTJz'
    || 'aUxDSnZia1J2ZFdKc1pVTnNhV05ySWlrc1NIUW9JbVp2WTNWemFXNGlMQ0p2YmtadlkzVnpJaWtzU0hRb0ltWnZZM1Z6YjNWMElpd2liMjVDYkhWeUlpa3NT'
    || 'SFFvZUhVc0ltOXVWSEpoYm5OcGRHbHZia1Z1WkNJcExGTW9JbTl1VFc5MWMyVkZiblJsY2lJc1d5SnRiM1Z6Wlc5MWRDSXNJbTF2ZFhObGIzWmxjaUpkS1N4'
    || 'VEtDSnZiazF2ZFhObFRHVmhkbVVpTEZzaWJXOTFjMlZ2ZFhRaUxDSnRiM1Z6Wlc5MlpYSWlYU2tzVXlnaWIyNVFiMmx1ZEdWeVJXNTBaWElpTEZzaWNHOXBi'
    || 'blJsY205MWRDSXNJbkJ2YVc1MFpYSnZkbVZ5SWwwcExGTW9JbTl1VUc5cGJuUmxja3hsWVhabElpeGJJbkJ2YVc1MFpYSnZkWFFpTENKd2IybHVkR1Z5YjNa'
    || 'bGNpSmRLU3hES0NKdmJrTm9ZVzVuWlNJc0ltTm9ZVzVuWlNCamJHbGpheUJtYjJOMWMybHVJR1p2WTNWemIzVjBJR2x1Y0hWMElHdGxlV1J2ZDI0Z2EyVjVk'
    || 'WEFnYzJWc1pXTjBhVzl1WTJoaGJtZGxJaTV6Y0d4cGRDZ2lJQ0lwS1N4REtDSnZibE5sYkdWamRDSXNJbVp2WTNWemIzVjBJR052Ym5SbGVIUnRaVzUxSUdS'
    || 'eVlXZGxibVFnWm05amRYTnBiaUJyWlhsa2IzZHVJR3RsZVhWd0lHMXZkWE5sWkc5M2JpQnRiM1Z6WlhWd0lITmxiR1ZqZEdsdmJtTm9ZVzVuWlNJdWMzQnNh'
    || 'WFFvSWlBaUtTa3NReWdpYjI1Q1pXWnZjbVZKYm5CMWRDSXNXeUpqYjIxd2IzTnBkR2x2Ym1WdVpDSXNJbXRsZVhCeVpYTnpJaXdpZEdWNGRFbHVjSFYwSWl3'
    || 'aWNHRnpkR1VpWFNrc1F5Z2liMjVEYjIxd2IzTnBkR2x2YmtWdVpDSXNJbU52YlhCdmMybDBhVzl1Wlc1a0lHWnZZM1Z6YjNWMElHdGxlV1J2ZDI0Z2EyVjVj'
    || 'SEpsYzNNZ2EyVjVkWEFnYlc5MWMyVmtiM2R1SWk1emNHeHBkQ2dpSUNJcEtTeERLQ0p2YmtOdmJYQnZjMmwwYVc5dVUzUmhjblFpTENKamIyMXdiM05wZEds'
    || 'dmJuTjBZWEowSUdadlkzVnpiM1YwSUd0bGVXUnZkMjRnYTJWNWNISmxjM01nYTJWNWRYQWdiVzkxYzJWa2IzZHVJaTV6Y0d4cGRDZ2lJQ0lwS1N4REtDSnZi'
    || 'a052YlhCdmMybDBhVzl1VlhCa1lYUmxJaXdpWTI5dGNHOXphWFJwYjI1MWNHUmhkR1VnWm05amRYTnZkWFFnYTJWNVpHOTNiaUJyWlhsd2NtVnpjeUJyWlhs'
    || 'MWNDQnRiM1Z6WldSdmQyNGlMbk53YkdsMEtDSWdJaWtwTzNaaGNpQnRjajBpWVdKdmNuUWdZMkZ1Y0d4aGVTQmpZVzV3YkdGNWRHaHliM1ZuYUNCa2RYSmhk'
    || 'R2x2Ym1Ob1lXNW5aU0JsYlhCMGFXVmtJR1Z1WTNKNWNIUmxaQ0JsYm1SbFpDQmxjbkp2Y2lCc2IyRmtaV1JrWVhSaElHeHZZV1JsWkcxbGRHRmtZWFJoSUd4'
    || 'dllXUnpkR0Z5ZENCd1lYVnpaU0J3YkdGNUlIQnNZWGxwYm1jZ2NISnZaM0psYzNNZ2NtRjBaV05vWVc1blpTQnlaWE5wZW1VZ2MyVmxhMlZrSUhObFpXdHBi'
    || 'bWNnYzNSaGJHeGxaQ0J6ZFhOd1pXNWtJSFJwYldWMWNHUmhkR1VnZG05c2RXMWxZMmhoYm1kbElIZGhhWFJwYm1jaUxuTndiR2wwS0NJZ0lpa3NlR1k5Ym1W'
    || 'M0lGTmxkQ2dpWTJGdVkyVnNJR05zYjNObElHbHVkbUZzYVdRZ2JHOWhaQ0J6WTNKdmJHd2dkRzluWjJ4bElpNXpjR3hwZENnaUlDSXBMbU52Ym1OaGRDaHRj'
    || 'aWtwTzJaMWJtTjBhVzl1SUY5MUtHVXNkQ3h1S1h0MllYSWdjajFsTG5SNWNHVjhmQ0oxYm10dWIzZHVMV1YyWlc1MElqdGxMbU4xY25KbGJuUlVZWEpuWlhR'
    || 'OWJpeDJaQ2h5TEhRc2RtOXBaQ0F3TEdVcExHVXVZM1Z5Y21WdWRGUmhjbWRsZEQxdWRXeHNmV1oxYm1OMGFXOXVJRVYxS0dVc2RDbDdkRDBvZENZMEtTRTlQ'
    || 'VEE3Wm05eUtIWmhjaUJ1UFRBN2JqeGxMbXhsYm1kMGFEdHVLeXNwZTNaaGNpQnlQV1ZiYmwwc2JEMXlMbVYyWlc1ME8zSTljaTVzYVhOMFpXNWxjbk03WlRw'
    || 'N2RtRnlJR2s5ZG05cFpDQXdPMmxtS0hRcFptOXlLSFpoY2lCelBYSXViR1Z1WjNSb0xURTdNRHc5Y3p0ekxTMHBlM1poY2lCalBYSmJjMTBzWmoxakxtbHVj'
    || 'M1JoYm1ObExIazlZeTVqZFhKeVpXNTBWR0Z5WjJWME8ybG1LR005WXk1c2FYTjBaVzVsY2l4bUlUMDlhU1ltYkM1cGMxQnliM0JoWjJGMGFXOXVVM1J2Y0hC'
    || 'bFpDZ3BLV0p5WldGcklHVTdYM1VvYkN4akxIa3BMR2s5Wm4xbGJITmxJR1p2Y2loelBUQTdjenh5TG14bGJtZDBhRHR6S3lzcGUybG1LR005Y2x0elhTeG1Q'
    || 'V011YVc1emRHRnVZMlVzZVQxakxtTjFjbkpsYm5SVVlYSm5aWFFzWXoxakxteHBjM1JsYm1WeUxHWWhQVDFwSmlac0xtbHpVSEp2Y0dGbllYUnBiMjVUZEc5'
    || 'd2NHVmtLQ2twWW5KbFlXc2daVHRmZFNoc0xHTXNlU2tzYVQxbWZYMTlhV1lvUm5JcGRHaHliM2NnWlQxdGFTeEdjajBoTVN4dGFUMXVkV3hzTEdWOVpuVnVZ'
    || 'M1JwYjI0Z2RXVW9aU3gwS1h0MllYSWdiajEwVzBkcFhUdHVQVDA5ZG05cFpDQXdKaVlvYmoxMFcwZHBYVDF1WlhjZ1UyVjBLVHQyWVhJZ2NqMWxLeUpmWDJK'
    || 'MVltSnNaU0k3Ymk1b1lYTW9jaWw4ZkNoT2RTaDBMR1VzTWl3aE1Ta3NiaTVoWkdRb2Npa3BmV1oxYm1OMGFXOXVJRVpwS0dVc2RDeHVLWHQyWVhJZ2NqMHdP'
    || 'M1FtSmloeWZEMDBLU3hPZFNodUxHVXNjaXgwS1gxMllYSWdibXc5SWw5eVpXRmpkRXhwYzNSbGJtbHVaeUlyVFdGMGFDNXlZVzVrYjIwb0tTNTBiMU4wY21s'
    || 'dVp5Z3pOaWt1YzJ4cFkyVW9NaWs3Wm5WdVkzUnBiMjRnZG5Jb1pTbDdhV1lvSVdWYmJteGRLWHRsVzI1c1hUMGhNQ3huTG1admNrVmhZMmdvWm5WdVkzUnBi'
    || 'MjRvYmlsN2JpRTlQU0p6Wld4bFkzUnBiMjVqYUdGdVoyVWlKaVlvZUdZdWFHRnpLRzRwZkh4R2FTaHVMQ0V4TEdVcExFWnBLRzRzSVRBc1pTa3BmU2s3ZG1G'
    || 'eUlIUTlaUzV1YjJSbFZIbHdaVDA5UFRrL1pUcGxMbTkzYm1WeVJHOWpkVzFsYm5RN2REMDlQVzUxYkd4OGZIUmJibXhkZkh3b2RGdHViRjA5SVRBc1Jta29J'
    || 'bk5sYkdWamRHbHZibU5vWVc1blpTSXNJVEVzZENrcGZYMW1kVzVqZEdsdmJpQk9kU2hsTEhRc2JpeHlLWHR6ZDJsMFkyZ29XWE1vZENrcGUyTmhjMlVnTVRw'
    || 'MllYSWdiRDFFWkR0aWNtVmhhenRqWVhObElEUTZiRDFRWkR0aWNtVmhhenRrWldaaGRXeDBPbXc5WDJsOWJqMXNMbUpwYm1Rb2JuVnNiQ3gwTEc0c1pTa3Ni'
    || 'RDEyYjJsa0lEQXNJV2hwZkh4MElUMDlJblJ2ZFdOb2MzUmhjblFpSmlaMElUMDlJblJ2ZFdOb2JXOTJaU0ltSm5RaFBUMGlkMmhsWld3aWZId29iRDBoTUNr'
    || 'c2NqOXNJVDA5ZG05cFpDQXdQMlV1WVdSa1JYWmxiblJNYVhOMFpXNWxjaWgwTEc0c2UyTmhjSFIxY21VNklUQXNjR0Z6YzJsMlpUcHNmU2s2WlM1aFpHUkZk'
    || 'bVZ1ZEV4cGMzUmxibVZ5S0hRc2Jpd2hNQ2s2YkNFOVBYWnZhV1FnTUQ5bExtRmtaRVYyWlc1MFRHbHpkR1Z1WlhJb2RDeHVMSHR3WVhOemFYWmxPbXg5S1Rw'
    || 'bExtRmtaRVYyWlc1MFRHbHpkR1Z1WlhJb2RDeHVMQ0V4S1gxbWRXNWpkR2x2YmlCWGFTaGxMSFFzYml4eUxHd3BlM1poY2lCcFBYSTdhV1lvS0hRbU1TazlQ'
    || 'VDB3SmlZb2RDWXlLVDA5UFRBbUpuSWhQVDF1ZFd4c0tXVTZabTl5S0RzN0tYdHBaaWh5UFQwOWJuVnNiQ2x5WlhSMWNtNDdkbUZ5SUhNOWNpNTBZV2M3YVdZ'
    || 'b2N6MDlQVE44ZkhNOVBUMDBLWHQyWVhJZ1l6MXlMbk4wWVhSbFRtOWtaUzVqYjI1MFlXbHVaWEpKYm1adk8ybG1LR005UFQxc2ZIeGpMbTV2WkdWVWVYQmxQ'
    || 'VDA5T0NZbVl5NXdZWEpsYm5ST2IyUmxQVDA5YkNsaWNtVmhhenRwWmloelBUMDlOQ2xtYjNJb2N6MXlMbkpsZEhWeWJqdHpJVDA5Ym5Wc2JEc3BlM1poY2lC'
    || 'bVBYTXVkR0ZuTzJsbUtDaG1QVDA5TTN4OFpqMDlQVFFwSmlZb1pqMXpMbk4wWVhSbFRtOWtaUzVqYjI1MFlXbHVaWEpKYm1adkxHWTlQVDFzZkh4bUxtNXZa'
    || 'R1ZVZVhCbFBUMDlPQ1ltWmk1d1lYSmxiblJPYjJSbFBUMDliQ2twY21WMGRYSnVPM005Y3k1eVpYUjFjbTU5Wm05eUtEdGpJVDA5Ym5Wc2JEc3BlMmxtS0hN'
    || 'OWIyNG9ZeWtzY3owOVBXNTFiR3dwY21WMGRYSnVPMmxtS0dZOWN5NTBZV2NzWmowOVBUVjhmR1k5UFQwMktYdHlQV2s5Y3p0amIyNTBhVzUxWlNCbGZXTTlZ'
    || 'eTV3WVhKbGJuUk9iMlJsZlgxeVBYSXVjbVYwZFhKdWZWSnpLR1oxYm1OMGFXOXVLQ2w3ZG1GeUlIazlhU3hxUFdScEtHNHBMRlE5VzEwN1pUcDdkbUZ5SUVV'
    || 'OVUzVXVaMlYwS0dVcE8ybG1LRVVoUFQxMmIybGtJREFwZTNaaGNpQkVQV3RwTEVFOVpUdHpkMmwwWTJnb1pTbDdZMkZ6WlNKclpYbHdjbVZ6Y3lJNmFXWW9X'
    || 'bklvYmlrOVBUMHdLV0p5WldGcklHVTdZMkZ6WlNKclpYbGtiM2R1SWpwallYTmxJbXRsZVhWd0lqcEVQVXRrTzJKeVpXRnJPMk5oYzJVaVptOWpkWE5wYmlJ'
    || 'NlFUMGlabTlqZFhNaUxFUTlWR2s3WW5KbFlXczdZMkZ6WlNKbWIyTjFjMjkxZENJNlFUMGlZbXgxY2lJc1JEMVVhVHRpY21WaGF6dGpZWE5sSW1KbFptOXla'
    || 'V0pzZFhJaU9tTmhjMlVpWVdaMFpYSmliSFZ5SWpwRVBWUnBPMkp5WldGck8yTmhjMlVpWTJ4cFkyc2lPbWxtS0c0dVluVjBkRzl1UFQwOU1pbGljbVZoYXlC'
    || 'bE8yTmhjMlVpWVhWNFkyeHBZMnNpT21OaGMyVWlaR0pzWTJ4cFkyc2lPbU5oYzJVaWJXOTFjMlZrYjNkdUlqcGpZWE5sSW0xdmRYTmxiVzkyWlNJNlkyRnpa'
    || 'U0p0YjNWelpYVndJanBqWVhObEltMXZkWE5sYjNWMElqcGpZWE5sSW0xdmRYTmxiM1psY2lJNlkyRnpaU0pqYjI1MFpYaDBiV1Z1ZFNJNlJEMWFjenRpY21W'
    || 'aGF6dGpZWE5sSW1SeVlXY2lPbU5oYzJVaVpISmhaMlZ1WkNJNlkyRnpaU0prY21GblpXNTBaWElpT21OaGMyVWlaSEpoWjJWNGFYUWlPbU5oYzJVaVpISmha'
    || 'MnhsWVhabElqcGpZWE5sSW1SeVlXZHZkbVZ5SWpwallYTmxJbVJ5WVdkemRHRnlkQ0k2WTJGelpTSmtjbTl3SWpwRVBVRmtPMkp5WldGck8yTmhjMlVpZEc5'
    || 'MVkyaGpZVzVqWld3aU9tTmhjMlVpZEc5MVkyaGxibVFpT21OaGMyVWlkRzkxWTJodGIzWmxJanBqWVhObEluUnZkV05vYzNSaGNuUWlPa1E5Y1dRN1luSmxZ'
    || 'V3M3WTJGelpTQjJkVHBqWVhObElHZDFPbU5oYzJVZ2VYVTZSRDFHWkR0aWNtVmhhenRqWVhObElIaDFPa1E5WW1RN1luSmxZV3M3WTJGelpTSnpZM0p2Ykd3'
    || 'aU9rUTlUR1E3WW5KbFlXczdZMkZ6WlNKM2FHVmxiQ0k2UkQxMFpqdGljbVZoYXp0allYTmxJbU52Y0hraU9tTmhjMlVpWTNWMElqcGpZWE5sSW5CaGMzUmxJ'
    || 'anBFUFNSa08ySnlaV0ZyTzJOaGMyVWlaMjkwY0c5cGJuUmxjbU5oY0hSMWNtVWlPbU5oYzJVaWJHOXpkSEJ2YVc1MFpYSmpZWEIwZFhKbElqcGpZWE5sSW5C'
    || 'dmFXNTBaWEpqWVc1alpXd2lPbU5oYzJVaWNHOXBiblJsY21SdmQyNGlPbU5oYzJVaWNHOXBiblJsY20xdmRtVWlPbU5oYzJVaWNHOXBiblJsY205MWRDSTZZ'
    || 'MkZ6WlNKd2IybHVkR1Z5YjNabGNpSTZZMkZ6WlNKd2IybHVkR1Z5ZFhBaU9rUTlTbk45ZG1GeUlIbzlLSFFtTkNraFBUMHdMSGRsUFNGNkppWmxQVDA5SW5O'
    || 'amNtOXNiQ0lzYlQxNlAwVWhQVDF1ZFd4c1AwVXJJa05oY0hSMWNtVWlPbTUxYkd3NlJUdDZQVnRkTzJadmNpaDJZWElnY0QxNUxIWTdjQ0U5UFc1MWJHdzdL'
    || 'WHQyUFhBN2RtRnlJRkk5ZGk1emRHRjBaVTV2WkdVN2FXWW9kaTUwWVdjOVBUMDFKaVpTSVQwOWJuVnNiQ1ltS0hZOVVpeHRJVDA5Ym5Wc2JDWW1LRkk5U200'
    || 'b2NDeHRLU3hTSVQxdWRXeHNKaVo2TG5CMWMyZ29aM0lvY0N4U0xIWXBLU2twTEhkbEtXSnlaV0ZyTzNBOWNDNXlaWFIxY201OU1EeDZMbXhsYm1kMGFDWW1L'
    || 'RVU5Ym1WM0lFUW9SU3hCTEc1MWJHd3NiaXhxS1N4VUxuQjFjMmdvZTJWMlpXNTBPa1VzYkdsemRHVnVaWEp6T25wOUtTbDlmV2xtS0NoMEpqY3BQVDA5TUNs'
    || 'N1pUcDdhV1lvUlQxbFBUMDlJbTF2ZFhObGIzWmxjaUo4ZkdVOVBUMGljRzlwYm5SbGNtOTJaWElpTEVROVpUMDlQU0p0YjNWelpXOTFkQ0o4ZkdVOVBUMGlj'
    || 'RzlwYm5SbGNtOTFkQ0lzUlNZbWJpRTlQV05wSmlZb1FUMXVMbkpsYkdGMFpXUlVZWEpuWlhSOGZHNHVabkp2YlVWc1pXMWxiblFwSmlZb2IyNG9RU2w4ZkVG'
    || 'YlZIUmRLU2xpY21WaGF5QmxPMmxtS0NoRWZIeEZLU1ltS0VVOWFpNTNhVzVrYjNjOVBUMXFQMm82S0VVOWFpNXZkMjVsY2tSdlkzVnRaVzUwS1Q5RkxtUmxa'
    || 'bUYxYkhSV2FXVjNmSHhGTG5CaGNtVnVkRmRwYm1SdmR6cDNhVzVrYjNjc1JEOG9RVDF1TG5KbGJHRjBaV1JVWVhKblpYUjhmRzR1ZEc5RmJHVnRaVzUwTEVR'
    || 'OWVTeEJQVUUvYjI0b1FTazZiblZzYkN4QklUMDliblZzYkNZbUtIZGxQV3h1S0VFcExFRWhQVDEzWlh4OFFTNTBZV2NoUFQwMUppWkJMblJoWnlFOVBUWXBK'
    || 'aVlvUVQxdWRXeHNLU2s2S0VROWJuVnNiQ3hCUFhrcExFUWhQVDFCS1NsN2FXWW9lajFhY3l4U1BTSnZiazF2ZFhObFRHVmhkbVVpTEcwOUltOXVUVzkxYzJW'
    || 'RmJuUmxjaUlzY0QwaWJXOTFjMlVpTENobFBUMDlJbkJ2YVc1MFpYSnZkWFFpZkh4bFBUMDlJbkJ2YVc1MFpYSnZkbVZ5SWlrbUppaDZQVXB6TEZJOUltOXVV'
    || 'RzlwYm5SbGNreGxZWFpsSWl4dFBTSnZibEJ2YVc1MFpYSkZiblJsY2lJc2NEMGljRzlwYm5SbGNpSXBMSGRsUFVROVBXNTFiR3cvUlRwTmJpaEVLU3gyUFVF'
    || 'OVBXNTFiR3cvUlRwTmJpaEJLU3hGUFc1bGR5QjZLRklzY0NzaWJHVmhkbVVpTEVRc2JpeHFLU3hGTG5SaGNtZGxkRDEzWlN4RkxuSmxiR0YwWldSVVlYSm5a'
    || 'WFE5ZGl4U1BXNTFiR3dzYjI0b2FpazlQVDE1SmlZb2VqMXVaWGNnZWlodExIQXJJbVZ1ZEdWeUlpeEJMRzRzYWlrc2VpNTBZWEpuWlhROWRpeDZMbkpsYkdG'
    || 'MFpXUlVZWEpuWlhROWQyVXNVajE2S1N4M1pUMVNMRVFtSmtFcGREcDdabTl5S0hvOVJDeHRQVUVzY0Qwd0xIWTllanQyTzNZOVVtNG9kaWtwY0Nzck8yWnZj'
    || 'aWgyUFRBc1VqMXRPMUk3VWoxU2JpaFNLU2wyS3lzN1ptOXlLRHN3UEhBdGRqc3BlajFTYmloNktTeHdMUzA3Wm05eUtEc3dQSFl0Y0RzcGJUMVNiaWh0S1N4'
    || 'MkxTMDdabTl5S0R0d0xTMDdLWHRwWmloNlBUMDliWHg4YlNFOVBXNTFiR3dtSm5vOVBUMXRMbUZzZEdWeWJtRjBaU2xpY21WaGF5QjBPM285VW00b2Vpa3Ni'
    || 'VDFTYmlodEtYMTZQVzUxYkd4OVpXeHpaU0I2UFc1MWJHdzdSQ0U5UFc1MWJHd21KbXQxS0ZRc1JTeEVMSG9zSVRFcExFRWhQVDF1ZFd4c0ppWjNaU0U5UFc1'
    || 'MWJHd21KbXQxS0ZRc2QyVXNRU3g2TENFd0tYMTlaVHA3YVdZb1JUMTVQMDF1S0hrcE9uZHBibVJ2ZHl4RVBVVXVibTlrWlU1aGJXVW1Ka1V1Ym05a1pVNWhi'
    || 'V1V1ZEc5TWIzZGxja05oYzJVb0tTeEVQVDA5SW5ObGJHVmpkQ0o4ZkVROVBUMGlhVzV3ZFhRaUppWkZMblI1Y0dVOVBUMGlabWxzWlNJcGRtRnlJRlU5WVdZ'
    || 'N1pXeHpaU0JwWmloc2RTaEZLU2xwWmlodmRTbFZQWEJtTzJWc2MyVjdWVDFrWmp0MllYSWdWejFqWm4xbGJITmxLRVE5UlM1dWIyUmxUbUZ0WlNrbUprUXVk'
    || 'RzlNYjNkbGNrTmhjMlVvS1QwOVBTSnBibkIxZENJbUppaEZMblI1Y0dVOVBUMGlZMmhsWTJ0aWIzZ2lmSHhGTG5SNWNHVTlQVDBpY21Ga2FXOGlLU1ltS0ZV'
    || 'OVptWXBPMmxtS0ZVbUppaFZQVlVvWlN4NUtTa3BlMmwxS0ZRc1ZTeHVMR29wTzJKeVpXRnJJR1Y5VnlZbVZ5aGxMRVVzZVNrc1pUMDlQU0ptYjJOMWMyOTFk'
    || 'Q0ltSmloWFBVVXVYM2R5WVhCd1pYSlRkR0YwWlNrbUpsY3VZMjl1ZEhKdmJHeGxaQ1ltUlM1MGVYQmxQVDA5SW01MWJXSmxjaUltSm1scEtFVXNJbTUxYldK'
    || 'bGNpSXNSUzUyWVd4MVpTbDljM2RwZEdOb0tGYzllVDlOYmloNUtUcDNhVzVrYjNjc1pTbDdZMkZ6WlNKbWIyTjFjMmx1SWpvb2JIVW9WeWw4ZkZjdVkyOXVk'
    || 'R1Z1ZEVWa2FYUmhZbXhsUFQwOUluUnlkV1VpS1NZbUtFTnVQVmNzVEdrOWVTeG9jajF1ZFd4c0tUdGljbVZoYXp0allYTmxJbVp2WTNWemIzVjBJanBvY2ox'
    || 'TWFUMURiajF1ZFd4c08ySnlaV0ZyTzJOaGMyVWliVzkxYzJWa2IzZHVJanBKYVQwaE1EdGljbVZoYXp0allYTmxJbU52Ym5SbGVIUnRaVzUxSWpwallYTmxJ'
    || 'bTF2ZFhObGRYQWlPbU5oYzJVaVpISmhaMlZ1WkNJNlNXazlJVEVzYUhVb1ZDeHVMR29wTzJKeVpXRnJPMk5oYzJVaWMyVnNaV04wYVc5dVkyaGhibWRsSWpw'
    || 'cFppaDJaaWxpY21WaGF6dGpZWE5sSW10bGVXUnZkMjRpT21OaGMyVWlhMlY1ZFhBaU9taDFLRlFzYml4cUtYMTJZWElnSkR0cFppaFBhU2xsT250emQybDBZ'
    || 'MmdvWlNsN1kyRnpaU0pqYjIxd2IzTnBkR2x2Ym5OMFlYSjBJanAyWVhJZ1FqMGliMjVEYjIxd2IzTnBkR2x2YmxOMFlYSjBJanRpY21WaGF5QmxPMk5oYzJV'
    || 'aVkyOXRjRzl6YVhScGIyNWxibVFpT2tJOUltOXVRMjl0Y0c5emFYUnBiMjVGYm1RaU8ySnlaV0ZySUdVN1kyRnpaU0pqYjIxd2IzTnBkR2x2Ym5Wd1pHRjBa'
    || 'U0k2UWowaWIyNURiMjF3YjNOcGRHbHZibFZ3WkdGMFpTSTdZbkpsWVdzZ1pYMUNQWFp2YVdRZ01IMWxiSE5sSUdwdVAyNTFLR1VzYmlrbUppaENQU0p2YmtO'
    || 'dmJYQnZjMmwwYVc5dVJXNWtJaWs2WlQwOVBTSnJaWGxrYjNkdUlpWW1iaTVyWlhsRGIyUmxQVDA5TWpJNUppWW9RajBpYjI1RGIyMXdiM05wZEdsdmJsTjBZ'
    || 'WEowSWlrN1FpWW1LR0p6SmladUxteHZZMkZzWlNFOVBTSnJieUltSmlocWJueDhRaUU5UFNKdmJrTnZiWEJ2YzJsMGFXOXVVM1JoY25RaVAwSTlQVDBpYjI1'
    || 'RGIyMXdiM05wZEdsdmJrVnVaQ0ltSm1wdUppWW9KRDFMY3lncEtUb29WblE5YWl4T2FUMGlkbUZzZFdVaWFXNGdWblEvVm5RdWRtRnNkV1U2Vm5RdWRHVjRk'
    || 'RU52Ym5SbGJuUXNhbTQ5SVRBcEtTeFhQWEpzS0hrc1Fpa3NNRHhYTG14bGJtZDBhQ1ltS0VJOWJtVjNJSEZ6S0VJc1pTeHVkV3hzTEc0c2Fpa3NWQzV3ZFhO'
    || 'b0tIdGxkbVZ1ZERwQ0xHeHBjM1JsYm1WeWN6cFhmU2tzSkQ5Q0xtUmhkR0U5SkRvb0pEMXlkU2h1S1N3a0lUMDliblZzYkNZbUtFSXVaR0YwWVQwa0tTa3BL'
    || 'U3dvSkQxeVpqOXNaaWhsTEc0cE9tOW1LR1VzYmlrcEppWW9lVDF5YkNoNUxDSnZia0psWm05eVpVbHVjSFYwSWlrc01EeDVMbXhsYm1kMGFDWW1LR285Ym1W'
    || 'M0lIRnpLQ0p2YmtKbFptOXlaVWx1Y0hWMElpd2lZbVZtYjNKbGFXNXdkWFFpTEc1MWJHd3NiaXhxS1N4VUxuQjFjMmdvZTJWMlpXNTBPbW9zYkdsemRHVnVa'
    || 'WEp6T25sOUtTeHFMbVJoZEdFOUpDa3BmVVYxS0ZRc2RDbDlLWDFtZFc1amRHbHZiaUJuY2lobExIUXNiaWw3Y21WMGRYSnVlMmx1YzNSaGJtTmxPbVVzYkds'
    || 'emRHVnVaWEk2ZEN4amRYSnlaVzUwVkdGeVoyVjBPbTU5ZldaMWJtTjBhVzl1SUhKc0tHVXNkQ2w3Wm05eUtIWmhjaUJ1UFhRcklrTmhjSFIxY21VaUxISTlX'
    || 'MTA3WlNFOVBXNTFiR3c3S1h0MllYSWdiRDFsTEdrOWJDNXpkR0YwWlU1dlpHVTdiQzUwWVdjOVBUMDFKaVpwSVQwOWJuVnNiQ1ltS0d3OWFTeHBQVXB1S0dV'
    || 'c2Jpa3NhU0U5Ym5Wc2JDWW1jaTUxYm5Ob2FXWjBLR2R5S0dVc2FTeHNLU2tzYVQxS2JpaGxMSFFwTEdraFBXNTFiR3dtSm5JdWNIVnphQ2huY2lobExHa3Ni'
    || 'Q2twS1N4bFBXVXVjbVYwZFhKdWZYSmxkSFZ5YmlCeWZXWjFibU4wYVc5dUlGSnVLR1VwZTJsbUtHVTlQVDF1ZFd4c0tYSmxkSFZ5YmlCdWRXeHNPMlJ2SUdV'
    || 'OVpTNXlaWFIxY200N2QyaHBiR1VvWlNZbVpTNTBZV2NoUFQwMUtUdHlaWFIxY200Z1pYeDhiblZzYkgxbWRXNWpkR2x2YmlCcmRTaGxMSFFzYml4eUxHd3Bl'
    || 'Mlp2Y2loMllYSWdhVDEwTGw5eVpXRmpkRTVoYldVc2N6MWJYVHR1SVQwOWJuVnNiQ1ltYmlFOVBYSTdLWHQyWVhJZ1l6MXVMR1k5WXk1aGJIUmxjbTVoZEdV'
    || 'c2VUMWpMbk4wWVhSbFRtOWtaVHRwWmlobUlUMDliblZzYkNZbVpqMDlQWElwWW5KbFlXczdZeTUwWVdjOVBUMDFKaVo1SVQwOWJuVnNiQ1ltS0dNOWVTeHNQ'
    || 'eWhtUFVwdUtHNHNhU2tzWmlFOWJuVnNiQ1ltY3k1MWJuTm9hV1owS0dkeUtHNHNaaXhqS1NrcE9teDhmQ2htUFVwdUtHNHNhU2tzWmlFOWJuVnNiQ1ltY3k1'
    || 'd2RYTm9LR2R5S0c0c1ppeGpLU2twS1N4dVBXNHVjbVYwZFhKdWZYTXViR1Z1WjNSb0lUMDlNQ1ltWlM1d2RYTm9LSHRsZG1WdWREcDBMR3hwYzNSbGJtVnlj'
    || 'enB6ZlNsOWRtRnlJRk5tUFM5Y2NseHVQeTluTEhkbVBTOWNkVEF3TURCOFhIVkdSa1pFTDJjN1puVnVZM1JwYjI0Z2FuVW9aU2w3Y21WMGRYSnVLSFI1Y0dW'
    || 'dlppQmxQVDBpYzNSeWFXNW5JajlsT2lJaUsyVXBMbkpsY0d4aFkyVW9VMllzWUFwZ0tTNXlaWEJzWVdObEtIZG1MQ0lpS1gxbWRXNWpkR2x2YmlCc2JDaGxM'
    || 'SFFzYmlsN2FXWW9kRDFxZFNoMEtTeHFkU2hsS1NFOVBYUW1KbTRwZEdoeWIzY2dSWEp5YjNJb1lTZzBNalVwS1gxbWRXNWpkR2x2YmlCcGJDZ3BlMzEyWVhJ'
    || 'Z0pHazliblZzYkN4V2FUMXVkV3hzTzJaMWJtTjBhVzl1SUVocEtHVXNkQ2w3Y21WMGRYSnVJR1U5UFQwaWRHVjRkR0Z5WldFaWZIeGxQVDA5SW01dmMyTnlh'
    || 'WEIwSW54OGRIbHdaVzltSUhRdVkyaHBiR1J5Wlc0OVBTSnpkSEpwYm1jaWZIeDBlWEJsYjJZZ2RDNWphR2xzWkhKbGJqMDlJbTUxYldKbGNpSjhmSFI1Y0dW'
    || 'dlppQjBMbVJoYm1kbGNtOTFjMng1VTJWMFNXNXVaWEpJVkUxTVBUMGliMkpxWldOMElpWW1kQzVrWVc1blpYSnZkWE5zZVZObGRFbHVibVZ5U0ZSTlRDRTlQ'
    || 'VzUxYkd3bUpuUXVaR0Z1WjJWeWIzVnpiSGxUWlhSSmJtNWxja2hVVFV3dVgxOW9kRzFzSVQxdWRXeHNmWFpoY2lCQ2FUMTBlWEJsYjJZZ2MyVjBWR2x0Wlc5'
    || 'MWREMDlJbVoxYm1OMGFXOXVJajl6WlhSVWFXMWxiM1YwT25admFXUWdNQ3hmWmoxMGVYQmxiMllnWTJ4bFlYSlVhVzFsYjNWMFBUMGlablZ1WTNScGIyNGlQ'
    || 'Mk5zWldGeVZHbHRaVzkxZERwMmIybGtJREFzUTNVOWRIbHdaVzltSUZCeWIyMXBjMlU5UFNKbWRXNWpkR2x2YmlJL1VISnZiV2x6WlRwMmIybGtJREFzUldZ'
    || 'OWRIbHdaVzltSUhGMVpYVmxUV2xqY205MFlYTnJQVDBpWm5WdVkzUnBiMjRpUDNGMVpYVmxUV2xqY205MFlYTnJPblI1Y0dWdlppQkRkVHdpZFNJL1puVnVZ'
    || 'M1JwYjI0b1pTbDdjbVYwZFhKdUlFTjFMbkpsYzI5c2RtVW9iblZzYkNrdWRHaGxiaWhsS1M1allYUmphQ2hPWmlsOU9rSnBPMloxYm1OMGFXOXVJRTVtS0dV'
    || 'cGUzTmxkRlJwYldWdmRYUW9ablZ1WTNScGIyNG9LWHQwYUhKdmR5QmxmU2w5Wm5WdVkzUnBiMjRnVVdrb1pTeDBLWHQyWVhJZ2JqMTBMSEk5TUR0a2IzdDJZ'
    || 'WElnYkQxdUxtNWxlSFJUYVdKc2FXNW5PMmxtS0dVdWNtVnRiM1psUTJocGJHUW9iaWtzYkNZbWJDNXViMlJsVkhsd1pUMDlQVGdwYVdZb2JqMXNMbVJoZEdF'
    || 'c2JqMDlQU0l2SkNJcGUybG1LSEk5UFQwd0tYdGxMbkpsYlc5MlpVTm9hV3hrS0d3cExITnlLSFFwTzNKbGRIVnlibjF5TFMxOVpXeHpaU0J1SVQwOUlpUWlK'
    || 'aVp1SVQwOUlpUS9JaVltYmlFOVBTSWtJU0o4ZkhJckt6dHVQV3g5ZDJocGJHVW9iaWs3YzNJb2RDbDlablZ1WTNScGIyNGdRblFvWlNsN1ptOXlLRHRsSVQx'
    || 'dWRXeHNPMlU5WlM1dVpYaDBVMmxpYkdsdVp5bDdkbUZ5SUhROVpTNXViMlJsVkhsd1pUdHBaaWgwUFQwOU1YeDhkRDA5UFRNcFluSmxZV3M3YVdZb2REMDlQ'
    || 'VGdwZTJsbUtIUTlaUzVrWVhSaExIUTlQVDBpSkNKOGZIUTlQVDBpSkNFaWZIeDBQVDA5SWlRL0lpbGljbVZoYXp0cFppaDBQVDA5SWk4a0lpbHlaWFIxY200'
    || 'Z2JuVnNiSDE5Y21WMGRYSnVJR1Y5Wm5WdVkzUnBiMjRnVkhVb1pTbDdaVDFsTG5CeVpYWnBiM1Z6VTJsaWJHbHVaenRtYjNJb2RtRnlJSFE5TUR0bE95bDdh'
    || 'V1lvWlM1dWIyUmxWSGx3WlQwOVBUZ3BlM1poY2lCdVBXVXVaR0YwWVR0cFppaHVQVDA5SWlRaWZIeHVQVDA5SWlRaElueDhiajA5UFNJa1B5SXBlMmxtS0hR'
    || 'OVBUMHdLWEpsZEhWeWJpQmxPM1F0TFgxbGJITmxJRzQ5UFQwaUx5UWlKaVowS3l0OVpUMWxMbkJ5WlhacGIzVnpVMmxpYkdsdVozMXlaWFIxY200Z2JuVnNi'
    || 'SDEyWVhJZ1QyNDlUV0YwYUM1eVlXNWtiMjBvS1M1MGIxTjBjbWx1Wnlnek5pa3VjMnhwWTJVb01pa3NSWFE5SWw5ZmNtVmhZM1JHYVdKbGNpUWlLMDl1TEhs'
    || 'eVBTSmZYM0psWVdOMFVISnZjSE1rSWl0UGJpeFVkRDBpWDE5eVpXRmpkRU52Ym5SaGFXNWxjaVFpSzA5dUxFZHBQU0pmWDNKbFlXTjBSWFpsYm5SekpDSXJU'
    || 'MjRzYTJZOUlsOWZjbVZoWTNSTWFYTjBaVzVsY25Na0lpdFBiaXhxWmowaVgxOXlaV0ZqZEVoaGJtUnNaWE1rSWl0UGJqdG1kVzVqZEdsdmJpQnZiaWhsS1h0'
    || 'MllYSWdkRDFsVzBWMFhUdHBaaWgwS1hKbGRIVnliaUIwTzJadmNpaDJZWElnYmoxbExuQmhjbVZ1ZEU1dlpHVTdianNwZTJsbUtIUTlibHRVZEYxOGZHNWJS'
    || 'WFJkS1h0cFppaHVQWFF1WVd4MFpYSnVZWFJsTEhRdVkyaHBiR1FoUFQxdWRXeHNmSHh1SVQwOWJuVnNiQ1ltYmk1amFHbHNaQ0U5UFc1MWJHd3BabTl5S0dV'
    || 'OVZIVW9aU2s3WlNFOVBXNTFiR3c3S1h0cFppaHVQV1ZiUlhSZEtYSmxkSFZ5YmlCdU8yVTlWSFVvWlNsOWNtVjBkWEp1SUhSOVpUMXVMRzQ5WlM1d1lYSmxi'
    || 'blJPYjJSbGZYSmxkSFZ5YmlCdWRXeHNmV1oxYm1OMGFXOXVJSGh5S0dVcGUzSmxkSFZ5YmlCbFBXVmJSWFJkZkh4bFcxUjBYU3doWlh4OFpTNTBZV2NoUFQw'
    || 'MUppWmxMblJoWnlFOVBUWW1KbVV1ZEdGbklUMDlNVE1tSm1VdWRHRm5JVDA5TXo5dWRXeHNPbVY5Wm5WdVkzUnBiMjRnVFc0b1pTbDdhV1lvWlM1MFlXYzlQ'
    || 'VDAxZkh4bExuUmhaejA5UFRZcGNtVjBkWEp1SUdVdWMzUmhkR1ZPYjJSbE8zUm9jbTkzSUVWeWNtOXlLR0VvTXpNcEtYMW1kVzVqZEdsdmJpQnZiQ2hsS1h0'
    || 'eVpYUjFjbTRnWlZ0NWNsMThmRzUxYkd4OWRtRnlJRmxwUFZ0ZExFUnVQUzB4TzJaMWJtTjBhVzl1SUZGMEtHVXBlM0psZEhWeWJudGpkWEp5Wlc1ME9tVjlm'
    || 'V1oxYm1OMGFXOXVJR0ZsS0dVcGV6QStSRzU4ZkNobExtTjFjbkpsYm5ROVdXbGJSRzVkTEZscFcwUnVYVDF1ZFd4c0xFUnVMUzBwZldaMWJtTjBhVzl1SUhO'
    || 'bEtHVXNkQ2w3Ukc0ckt5eFphVnRFYmwwOVpTNWpkWEp5Wlc1MExHVXVZM1Z5Y21WdWREMTBmWFpoY2lCSGREMTdmU3hKWlQxUmRDaEhkQ2tzV1dVOVVYUW9J'
    || 'VEVwTEhOdVBVZDBPMloxYm1OMGFXOXVJRkJ1S0dVc2RDbDdkbUZ5SUc0OVpTNTBlWEJsTG1OdmJuUmxlSFJVZVhCbGN6dHBaaWdoYmlseVpYUjFjbTRnUjNR'
    || 'N2RtRnlJSEk5WlM1emRHRjBaVTV2WkdVN2FXWW9jaVltY2k1ZlgzSmxZV04wU1c1MFpYSnVZV3hOWlcxdmFYcGxaRlZ1YldGemEyVmtRMmhwYkdSRGIyNTBa'
    || 'WGgwUFQwOWRDbHlaWFIxY200Z2NpNWZYM0psWVdOMFNXNTBaWEp1WVd4TlpXMXZhWHBsWkUxaGMydGxaRU5vYVd4a1EyOXVkR1Y0ZER0MllYSWdiRDE3ZlN4'
    || 'cE8yWnZjaWhwSUdsdUlHNHBiRnRwWFQxMFcybGRPM0psZEhWeWJpQnlKaVlvWlQxbExuTjBZWFJsVG05a1pTeGxMbDlmY21WaFkzUkpiblJsY201aGJFMWxi'
    || 'VzlwZW1Wa1ZXNXRZWE5yWldSRGFHbHNaRU52Ym5SbGVIUTlkQ3hsTGw5ZmNtVmhZM1JKYm5SbGNtNWhiRTFsYlc5cGVtVmtUV0Z6YTJWa1EyaHBiR1JEYjI1'
    || 'MFpYaDBQV3dwTEd4OVpuVnVZM1JwYjI0Z1MyVW9aU2w3Y21WMGRYSnVJR1U5WlM1amFHbHNaRU52Ym5SbGVIUlVlWEJsY3l4bElUMXVkV3hzZldaMWJtTjBh'
    || 'Vzl1SUhOc0tDbDdZV1VvV1dVcExHRmxLRWxsS1gxbWRXNWpkR2x2YmlCU2RTaGxMSFFzYmlsN2FXWW9TV1V1WTNWeWNtVnVkQ0U5UFVkMEtYUm9jbTkzSUVW'
    || 'eWNtOXlLR0VvTVRZNEtTazdjMlVvU1dVc2RDa3NjMlVvV1dVc2JpbDlablZ1WTNScGIyNGdUM1VvWlN4MExHNHBlM1poY2lCeVBXVXVjM1JoZEdWT2IyUmxP'
    || 'MmxtS0hROWRDNWphR2xzWkVOdmJuUmxlSFJVZVhCbGN5eDBlWEJsYjJZZ2NpNW5aWFJEYUdsc1pFTnZiblJsZUhRaFBTSm1kVzVqZEdsdmJpSXBjbVYwZFhK'
    || 'dUlHNDdjajF5TG1kbGRFTm9hV3hrUTI5dWRHVjRkQ2dwTzJadmNpaDJZWElnYkNCcGJpQnlLV2xtS0NFb2JDQnBiaUIwS1NsMGFISnZkeUJGY25KdmNpaGhL'
    || 'REV3T0N4dlpTaGxLWHg4SWxWdWEyNXZkMjRpTEd3cEtUdHlaWFIxY200Z1NTaDdmU3h1TEhJcGZXWjFibU4wYVc5dUlIVnNLR1VwZTNKbGRIVnliaUJsUFNo'
    || 'bFBXVXVjM1JoZEdWT2IyUmxLU1ltWlM1ZlgzSmxZV04wU1c1MFpYSnVZV3hOWlcxdmFYcGxaRTFsY21kbFpFTm9hV3hrUTI5dWRHVjRkSHg4UjNRc2MyNDlT'
    || 'V1V1WTNWeWNtVnVkQ3h6WlNoSlpTeGxLU3h6WlNoWlpTeFpaUzVqZFhKeVpXNTBLU3doTUgxbWRXNWpkR2x2YmlCTmRTaGxMSFFzYmlsN2RtRnlJSEk5WlM1'
    || 'emRHRjBaVTV2WkdVN2FXWW9JWElwZEdoeWIzY2dSWEp5YjNJb1lTZ3hOamtwS1R0dVB5aGxQVTkxS0dVc2RDeHpiaWtzY2k1ZlgzSmxZV04wU1c1MFpYSnVZ'
    || 'V3hOWlcxdmFYcGxaRTFsY21kbFpFTm9hV3hrUTI5dWRHVjRkRDFsTEdGbEtGbGxLU3hoWlNoSlpTa3NjMlVvU1dVc1pTa3BPbUZsS0ZsbEtTeHpaU2haWlN4'
    || 'dUtYMTJZWElnVW5ROWJuVnNiQ3hoYkQwaE1TeExhVDBoTVR0bWRXNWpkR2x2YmlCRWRTaGxLWHRTZEQwOVBXNTFiR3cvVW5ROVcyVmRPbEowTG5CMWMyZ29a'
    || 'U2w5Wm5WdVkzUnBiMjRnUTJZb1pTbDdZV3c5SVRBc1JIVW9aU2w5Wm5WdVkzUnBiMjRnV1hRb0tYdHBaaWdoUzJrbUpsSjBJVDA5Ym5Wc2JDbDdTMms5SVRB'
    || 'N2RtRnlJR1U5TUN4MFBXbGxPM1J5ZVh0MllYSWdiajFTZER0bWIzSW9hV1U5TVR0bFBHNHViR1Z1WjNSb08yVXJLeWw3ZG1GeUlISTlibHRsWFR0a2J5QnlQ'
    || 'WElvSVRBcE8zZG9hV3hsS0hJaFBUMXVkV3hzS1gxU2REMXVkV3hzTEdGc1BTRXhmV05oZEdOb0tHd3BlM1JvY205M0lGSjBJVDA5Ym5Wc2JDWW1LRkowUFZK'
    || 'MExuTnNhV05sS0dVck1Ta3BMRXh6S0hacExGbDBLU3hzZldacGJtRnNiSGw3YVdVOWRDeExhVDBoTVgxOWNtVjBkWEp1SUc1MWJHeDlkbUZ5SUV4dVBWdGRM'
    || 'RWx1UFRBc1kydzliblZzYkN4a2JEMHdMRzkwUFZ0ZExITjBQVEFzZFc0OWJuVnNiQ3hQZEQweExFMTBQU0lpTzJaMWJtTjBhVzl1SUdGdUtHVXNkQ2w3VEc1'
    || 'YlNXNHJLMTA5Wkd3c1RHNWJTVzRySzEwOVkyd3NZMnc5WlN4a2JEMTBmV1oxYm1OMGFXOXVJRkIxS0dVc2RDeHVLWHR2ZEZ0emRDc3JYVDFQZEN4dmRGdHpk'
    || 'Q3NyWFQxTmRDeHZkRnR6ZENzclhUMTFiaXgxYmoxbE8zWmhjaUJ5UFU5ME8yVTlUWFE3ZG1GeUlHdzlNekl0YUhRb2Npa3RNVHR5SmoxK0tERThQR3dwTEc0'
    || 'clBURTdkbUZ5SUdrOU16SXRhSFFvZENrcmJEdHBaaWd6TUR4cEtYdDJZWElnY3oxc0xXd2xOVHRwUFNoeUppZ3hQRHh6S1MweEtTNTBiMU4wY21sdVp5Z3pN'
    || 'aWtzY2o0K1BYTXNiQzA5Y3l4UGREMHhQRHd6TWkxb2RDaDBLU3RzZkc0OFBHeDhjaXhOZEQxcEsyVjlaV3h6WlNCUGREMHhQRHhwZkc0OFBHeDhjaXhOZEQx'
    || 'bGZXWjFibU4wYVc5dUlGaHBLR1VwZTJVdWNtVjBkWEp1SVQwOWJuVnNiQ1ltS0dGdUtHVXNNU2tzVUhVb1pTd3hMREFwS1gxbWRXNWpkR2x2YmlCYWFTaGxL'
    || 'WHRtYjNJb08yVTlQVDFqYkRzcFkydzlURzViTFMxSmJsMHNURzViU1c1ZFBXNTFiR3dzWkd3OVRHNWJMUzFKYmwwc1RHNWJTVzVkUFc1MWJHdzdabTl5S0R0'
    || 'bFBUMDlkVzQ3S1hWdVBXOTBXeTB0YzNSZExHOTBXM04wWFQxdWRXeHNMRTEwUFc5MFd5MHRjM1JkTEc5MFczTjBYVDF1ZFd4c0xFOTBQVzkwV3kwdGMzUmRM'
    || 'RzkwVzNOMFhUMXVkV3hzZlhaaGNpQnlkRDF1ZFd4c0xHeDBQVzUxYkd3c2NHVTlJVEVzZG5ROWJuVnNiRHRtZFc1amRHbHZiaUJNZFNobExIUXBlM1poY2lC'
    || 'dVBXUjBLRFVzYm5Wc2JDeHVkV3hzTERBcE8yNHVaV3hsYldWdWRGUjVjR1U5SWtSRlRFVlVSVVFpTEc0dWMzUmhkR1ZPYjJSbFBYUXNiaTV5WlhSMWNtNDla'
    || 'U3gwUFdVdVpHVnNaWFJwYjI1ekxIUTlQVDF1ZFd4c1B5aGxMbVJsYkdWMGFXOXVjejFiYmwwc1pTNW1iR0ZuYzN3OU1UWXBPblF1Y0hWemFDaHVLWDFtZFc1'
    || 'amRHbHZiaUJKZFNobExIUXBlM04zYVhSamFDaGxMblJoWnlsN1kyRnpaU0ExT25aaGNpQnVQV1V1ZEhsd1pUdHlaWFIxY200Z2REMTBMbTV2WkdWVWVYQmxJ'
    || 'VDA5TVh4OGJpNTBiMHh2ZDJWeVEyRnpaU2dwSVQwOWRDNXViMlJsVG1GdFpTNTBiMHh2ZDJWeVEyRnpaU2dwUDI1MWJHdzZkQ3gwSVQwOWJuVnNiRDhvWlM1'
    || 'emRHRjBaVTV2WkdVOWRDeHlkRDFsTEd4MFBVSjBLSFF1Wm1seWMzUkRhR2xzWkNrc0lUQXBPaUV4TzJOaGMyVWdOanB5WlhSMWNtNGdkRDFsTG5CbGJtUnBi'
    || 'bWRRY205d2N6MDlQU0lpZkh4MExtNXZaR1ZVZVhCbElUMDlNejl1ZFd4c09uUXNkQ0U5UFc1MWJHdy9LR1V1YzNSaGRHVk9iMlJsUFhRc2NuUTlaU3hzZEQx'
    || 'dWRXeHNMQ0V3S1RvaE1UdGpZWE5sSURFek9uSmxkSFZ5YmlCMFBYUXVibTlrWlZSNWNHVWhQVDA0UDI1MWJHdzZkQ3gwSVQwOWJuVnNiRDhvYmoxMWJpRTlQ'
    || 'VzUxYkd3L2UybGtPazkwTEc5MlpYSm1iRzkzT2sxMGZUcHVkV3hzTEdVdWJXVnRiMmw2WldSVGRHRjBaVDE3WkdWb2VXUnlZWFJsWkRwMExIUnlaV1ZEYjI1'
    || 'MFpYaDBPbTRzY21WMGNubE1ZVzVsT2pFd056TTNOREU0TWpSOUxHNDlaSFFvTVRnc2JuVnNiQ3h1ZFd4c0xEQXBMRzR1YzNSaGRHVk9iMlJsUFhRc2JpNXla'
    || 'WFIxY200OVpTeGxMbU5vYVd4a1BXNHNjblE5WlN4c2REMXVkV3hzTENFd0tUb2hNVHRrWldaaGRXeDBPbkpsZEhWeWJpRXhmWDFtZFc1amRHbHZiaUJ4YVNo'
    || 'bEtYdHlaWFIxY200b1pTNXRiMlJsSmpFcElUMDlNQ1ltS0dVdVpteGhaM01tTVRJNEtUMDlQVEI5Wm5WdVkzUnBiMjRnU21rb1pTbDdhV1lvY0dVcGUzWmhj'
    || 'aUIwUFd4ME8ybG1LSFFwZTNaaGNpQnVQWFE3YVdZb0lVbDFLR1VzZENrcGUybG1LSEZwS0dVcEtYUm9jbTkzSUVWeWNtOXlLR0VvTkRFNEtTazdkRDFDZENo'
    || 'dUxtNWxlSFJUYVdKc2FXNW5LVHQyWVhJZ2NqMXlkRHQwSmlaSmRTaGxMSFFwUDB4MUtISXNiaWs2S0dVdVpteGhaM005WlM1bWJHRm5jeVl0TkRBNU4zd3lM'
    || 'SEJsUFNFeExISjBQV1VwZlgxbGJITmxlMmxtS0hGcEtHVXBLWFJvY205M0lFVnljbTl5S0dFb05ERTRLU2s3WlM1bWJHRm5jejFsTG1ac1lXZHpKaTAwTURr'
    || 'M2ZESXNjR1U5SVRFc2NuUTlaWDE5ZldaMWJtTjBhVzl1SUVGMUtHVXBlMlp2Y2lobFBXVXVjbVYwZFhKdU8yVWhQVDF1ZFd4c0ppWmxMblJoWnlFOVBUVW1K'
    || 'bVV1ZEdGbklUMDlNeVltWlM1MFlXY2hQVDB4TXpzcFpUMWxMbkpsZEhWeWJqdHlkRDFsZldaMWJtTjBhVzl1SUdac0tHVXBlMmxtS0dVaFBUMXlkQ2x5WlhS'
    || 'MWNtNGhNVHRwWmlnaGNHVXBjbVYwZFhKdUlFRjFLR1VwTEhCbFBTRXdMQ0V4TzNaaGNpQjBPMmxtS0NoMFBXVXVkR0ZuSVQwOU15a21KaUVvZEQxbExuUmha'
    || 'eUU5UFRVcEppWW9kRDFsTG5SNWNHVXNkRDEwSVQwOUltaGxZV1FpSmlaMElUMDlJbUp2WkhraUppWWhTR2tvWlM1MGVYQmxMR1V1YldWdGIybDZaV1JRY205'
    || 'd2N5a3BMSFFtSmloMFBXeDBLU2w3YVdZb2NXa29aU2twZEdoeWIzY2dlblVvS1N4RmNuSnZjaWhoS0RReE9Da3BPMlp2Y2lnN2REc3BUSFVvWlN4MEtTeDBQ'
    || 'VUowS0hRdWJtVjRkRk5wWW14cGJtY3BmV2xtS0VGMUtHVXBMR1V1ZEdGblBUMDlNVE1wZTJsbUtHVTlaUzV0WlcxdmFYcGxaRk4wWVhSbExHVTlaU0U5UFc1'
    || 'MWJHdy9aUzVrWldoNVpISmhkR1ZrT201MWJHd3NJV1VwZEdoeWIzY2dSWEp5YjNJb1lTZ3pNVGNwS1R0bE9udG1iM0lvWlQxbExtNWxlSFJUYVdKc2FXNW5M'
    || 'SFE5TUR0bE95bDdhV1lvWlM1dWIyUmxWSGx3WlQwOVBUZ3BlM1poY2lCdVBXVXVaR0YwWVR0cFppaHVQVDA5SWk4a0lpbDdhV1lvZEQwOVBUQXBlMngwUFVK'
    || 'MEtHVXVibVY0ZEZOcFlteHBibWNwTzJKeVpXRnJJR1Y5ZEMwdGZXVnNjMlVnYmlFOVBTSWtJaVltYmlFOVBTSWtJU0ltSm00aFBUMGlKRDhpZkh4MEt5dDla'
    || 'VDFsTG01bGVIUlRhV0pzYVc1bmZXeDBQVzUxYkd4OWZXVnNjMlVnYkhROWNuUS9RblFvWlM1emRHRjBaVTV2WkdVdWJtVjRkRk5wWW14cGJtY3BPbTUxYkd3'
    || 'N2NtVjBkWEp1SVRCOVpuVnVZM1JwYjI0Z2VuVW9LWHRtYjNJb2RtRnlJR1U5YkhRN1pUc3BaVDFDZENobExtNWxlSFJUYVdKc2FXNW5LWDFtZFc1amRHbHZi'
    || 'aUJCYmlncGUyeDBQWEowUFc1MWJHd3NjR1U5SVRGOVpuVnVZM1JwYjI0Z1lta29aU2w3ZG5ROVBUMXVkV3hzUDNaMFBWdGxYVHAyZEM1d2RYTm9LR1VwZlha'
    || 'aGNpQlVaajEyWlM1U1pXRmpkRU4xY25KbGJuUkNZWFJqYUVOdmJtWnBaenRtZFc1amRHbHZiaUJUY2lobExIUXNiaWw3YVdZb1pUMXVMbkpsWml4bElUMDli'
    || 'blZzYkNZbWRIbHdaVzltSUdVaFBTSm1kVzVqZEdsdmJpSW1KblI1Y0dWdlppQmxJVDBpYjJKcVpXTjBJaWw3YVdZb2JpNWZiM2R1WlhJcGUybG1LRzQ5Ymk1'
    || 'ZmIzZHVaWElzYmlsN2FXWW9iaTUwWVdjaFBUMHhLWFJvY205M0lFVnljbTl5S0dFb016QTVLU2s3ZG1GeUlISTliaTV6ZEdGMFpVNXZaR1Y5YVdZb0lYSXBk'
    || 'R2h5YjNjZ1JYSnliM0lvWVNneE5EY3NaU2twTzNaaGNpQnNQWElzYVQwaUlpdGxPM0psZEhWeWJpQjBJVDA5Ym5Wc2JDWW1kQzV5WldZaFBUMXVkV3hzSmla'
    || 'MGVYQmxiMllnZEM1eVpXWTlQU0ptZFc1amRHbHZiaUltSm5RdWNtVm1MbDl6ZEhKcGJtZFNaV1k5UFQxcFAzUXVjbVZtT2loMFBXWjFibU4wYVc5dUtITXBl'
    || 'M1poY2lCalBXd3VjbVZtY3p0elBUMDliblZzYkQ5a1pXeGxkR1VnWTF0cFhUcGpXMmxkUFhOOUxIUXVYM04wY21sdVoxSmxaajFwTEhRcGZXbG1LSFI1Y0dW'
    || 'dlppQmxJVDBpYzNSeWFXNW5JaWwwYUhKdmR5QkZjbkp2Y2loaEtESTROQ2twTzJsbUtDRnVMbDl2ZDI1bGNpbDBhSEp2ZHlCRmNuSnZjaWhoS0RJNU1DeGxL'
    || 'U2w5Y21WMGRYSnVJR1Y5Wm5WdVkzUnBiMjRnY0d3b1pTeDBLWHQwYUhKdmR5QmxQVTlpYW1WamRDNXdjbTkwYjNSNWNHVXVkRzlUZEhKcGJtY3VZMkZzYkNo'
    || 'MEtTeEZjbkp2Y2loaEtETXhMR1U5UFQwaVcyOWlhbVZqZENCUFltcGxZM1JkSWo4aWIySnFaV04wSUhkcGRHZ2dhMlY1Y3lCN0lpdFBZbXBsWTNRdWEyVjVj'
    || 'eWgwS1M1cWIybHVLQ0lzSUNJcEt5SjlJanBsS1NsOVpuVnVZM1JwYjI0Z1ZYVW9aU2w3ZG1GeUlIUTlaUzVmYVc1cGREdHlaWFIxY200Z2RDaGxMbDl3WVhs'
    || 'c2IyRmtLWDFtZFc1amRHbHZiaUJHZFNobEtYdG1kVzVqZEdsdmJpQjBLRzBzY0NsN2FXWW9aU2w3ZG1GeUlIWTliUzVrWld4bGRHbHZibk03ZGowOVBXNTFi'
    || 'R3cvS0cwdVpHVnNaWFJwYjI1elBWdHdYU3h0TG1ac1lXZHpmRDB4TmlrNmRpNXdkWE5vS0hBcGZYMW1kVzVqZEdsdmJpQnVLRzBzY0NsN2FXWW9JV1VwY21W'
    || 'MGRYSnVJRzUxYkd3N1ptOXlLRHR3SVQwOWJuVnNiRHNwZENodExIQXBMSEE5Y0M1emFXSnNhVzVuTzNKbGRIVnliaUJ1ZFd4c2ZXWjFibU4wYVc5dUlISW9i'
    || 'U3h3S1h0bWIzSW9iVDF1WlhjZ1RXRndPM0FoUFQxdWRXeHNPeWx3TG10bGVTRTlQVzUxYkd3L2JTNXpaWFFvY0M1clpYa3NjQ2s2YlM1elpYUW9jQzVwYm1S'
    || 'bGVDeHdLU3h3UFhBdWMybGliR2x1Wnp0eVpYUjFjbTRnYlgxbWRXNWpkR2x2YmlCc0tHMHNjQ2w3Y21WMGRYSnVJRzA5ZEc0b2JTeHdLU3h0TG1sdVpHVjRQ'
    || 'VEFzYlM1emFXSnNhVzVuUFc1MWJHd3NiWDFtZFc1amRHbHZiaUJwS0cwc2NDeDJLWHR5WlhSMWNtNGdiUzVwYm1SbGVEMTJMR1UvS0hZOWJTNWhiSFJsY201'
    || 'aGRHVXNkaUU5UFc1MWJHdy9LSFk5ZGk1cGJtUmxlQ3gyUEhBL0tHMHVabXhoWjNOOFBUSXNjQ2s2ZGlrNktHMHVabXhoWjNOOFBUSXNjQ2twT2lodExtWnNZ'
    || 'V2R6ZkQweE1EUTROVGMyTEhBcGZXWjFibU4wYVc5dUlITW9iU2w3Y21WMGRYSnVJR1VtSm0wdVlXeDBaWEp1WVhSbFBUMDliblZzYkNZbUtHMHVabXhoWjNO'
    || 'OFBUSXBMRzE5Wm5WdVkzUnBiMjRnWXlodExIQXNkaXhTS1h0eVpYUjFjbTRnY0QwOVBXNTFiR3g4ZkhBdWRHRm5JVDA5Tmo4b2NEMVJieWgyTEcwdWJXOWta'
    || 'U3hTS1N4d0xuSmxkSFZ5YmoxdExIQXBPaWh3UFd3b2NDeDJLU3h3TG5KbGRIVnliajF0TEhBcGZXWjFibU4wYVc5dUlHWW9iU3h3TEhZc1VpbDdkbUZ5SUZV'
    || 'OWRpNTBlWEJsTzNKbGRIVnliaUJWUFQwOVkyVS9haWh0TEhBc2RpNXdjbTl3Y3k1amFHbHNaSEpsYml4U0xIWXVhMlY1S1Rwd0lUMDliblZzYkNZbUtIQXVa'
    || 'V3hsYldWdWRGUjVjR1U5UFQxVmZIeDBlWEJsYjJZZ1ZUMDlJbTlpYW1WamRDSW1KbFVoUFQxdWRXeHNKaVpWTGlRa2RIbHdaVzltUFQwOVIyVW1KbFYxS0ZV'
    || 'cFBUMDljQzUwZVhCbEtUOG9VajFzS0hBc2RpNXdjbTl3Y3lrc1VpNXlaV1k5VTNJb2JTeHdMSFlwTEZJdWNtVjBkWEp1UFcwc1VpazZLRkk5ZW13b2RpNTBl'
    || 'WEJsTEhZdWEyVjVMSFl1Y0hKdmNITXNiblZzYkN4dExtMXZaR1VzVWlrc1VpNXlaV1k5VTNJb2JTeHdMSFlwTEZJdWNtVjBkWEp1UFcwc1VpbDlablZ1WTNS'
    || 'cGIyNGdlU2h0TEhBc2RpeFNLWHR5WlhSMWNtNGdjRDA5UFc1MWJHeDhmSEF1ZEdGbklUMDlOSHg4Y0M1emRHRjBaVTV2WkdVdVkyOXVkR0ZwYm1WeVNXNW1i'
    || 'eUU5UFhZdVkyOXVkR0ZwYm1WeVNXNW1iM3g4Y0M1emRHRjBaVTV2WkdVdWFXMXdiR1Z0Wlc1MFlYUnBiMjRoUFQxMkxtbHRjR3hsYldWdWRHRjBhVzl1UHlo'
    || 'd1BVZHZLSFlzYlM1dGIyUmxMRklwTEhBdWNtVjBkWEp1UFcwc2NDazZLSEE5YkNod0xIWXVZMmhwYkdSeVpXNThmRnRkS1N4d0xuSmxkSFZ5YmoxdExIQXBm'
    || 'V1oxYm1OMGFXOXVJR29vYlN4d0xIWXNVaXhWS1h0eVpYUjFjbTRnY0QwOVBXNTFiR3g4ZkhBdWRHRm5JVDA5Tno4b2NEMW5iaWgyTEcwdWJXOWtaU3hTTEZV'
    || 'cExIQXVjbVYwZFhKdVBXMHNjQ2s2S0hBOWJDaHdMSFlwTEhBdWNtVjBkWEp1UFcwc2NDbDlablZ1WTNScGIyNGdWQ2h0TEhBc2RpbDdhV1lvZEhsd1pXOW1J'
    || 'SEE5UFNKemRISnBibWNpSmlad0lUMDlJaUo4ZkhSNWNHVnZaaUJ3UFQwaWJuVnRZbVZ5SWlseVpYUjFjbTRnY0QxUmJ5Z2lJaXR3TEcwdWJXOWtaU3gyS1N4'
    || 'd0xuSmxkSFZ5YmoxdExIQTdhV1lvZEhsd1pXOW1JSEE5UFNKdlltcGxZM1FpSmlad0lUMDliblZzYkNsN2MzZHBkR05vS0hBdUpDUjBlWEJsYjJZcGUyTmhj'
    || 'MlVnVFdVNmNtVjBkWEp1SUhZOWVtd29jQzUwZVhCbExIQXVhMlY1TEhBdWNISnZjSE1zYm5Wc2JDeHRMbTF2WkdVc2Rpa3NkaTV5WldZOVUzSW9iU3h1ZFd4'
    || 'c0xIQXBMSFl1Y21WMGRYSnVQVzBzZGp0allYTmxJSGhsT25KbGRIVnliaUJ3UFVkdktIQXNiUzV0YjJSbExIWXBMSEF1Y21WMGRYSnVQVzBzY0R0allYTmxJ'
    || 'RWRsT25aaGNpQlNQWEF1WDJsdWFYUTdjbVYwZFhKdUlGUW9iU3hTS0hBdVgzQmhlV3h2WVdRcExIWXBmV2xtS0ZodUtIQXBmSHhJS0hBcEtYSmxkSFZ5YmlC'
    || 'd1BXZHVLSEFzYlM1dGIyUmxMSFlzYm5Wc2JDa3NjQzV5WlhSMWNtNDliU3h3TzNCc0tHMHNjQ2w5Y21WMGRYSnVJRzUxYkd4OVpuVnVZM1JwYjI0Z1JTaHRM'
    || 'SEFzZGl4U0tYdDJZWElnVlQxd0lUMDliblZzYkQ5d0xtdGxlVHB1ZFd4c08ybG1LSFI1Y0dWdlppQjJQVDBpYzNSeWFXNW5JaVltZGlFOVBTSWlmSHgwZVhC'
    || 'bGIyWWdkajA5SW01MWJXSmxjaUlwY21WMGRYSnVJRlVoUFQxdWRXeHNQMjUxYkd3Nll5aHRMSEFzSWlJcmRpeFNLVHRwWmloMGVYQmxiMllnZGowOUltOWlh'
    || 'bVZqZENJbUpuWWhQVDF1ZFd4c0tYdHpkMmwwWTJnb2RpNGtKSFI1Y0dWdlppbDdZMkZ6WlNCTlpUcHlaWFIxY200Z2RpNXJaWGs5UFQxVlAyWW9iU3h3TEhZ'
    || 'c1VpazZiblZzYkR0allYTmxJSGhsT25KbGRIVnliaUIyTG10bGVUMDlQVlUvZVNodExIQXNkaXhTS1RwdWRXeHNPMk5oYzJVZ1IyVTZjbVYwZFhKdUlGVTlk'
    || 'aTVmYVc1cGRDeEZLRzBzY0N4VktIWXVYM0JoZVd4dllXUXBMRklwZldsbUtGaHVLSFlwZkh4SUtIWXBLWEpsZEhWeWJpQlZJVDA5Ym5Wc2JEOXVkV3hzT21v'
    || 'b2JTeHdMSFlzVWl4dWRXeHNLVHR3YkNodExIWXBmWEpsZEhWeWJpQnVkV3hzZldaMWJtTjBhVzl1SUVRb2JTeHdMSFlzVWl4VktYdHBaaWgwZVhCbGIyWWdV'
    || 'ajA5SW5OMGNtbHVaeUltSmxJaFBUMGlJbng4ZEhsd1pXOW1JRkk5UFNKdWRXMWlaWElpS1hKbGRIVnliaUJ0UFcwdVoyVjBLSFlwZkh4dWRXeHNMR01vY0N4'
    || 'dExDSWlLMUlzVlNrN2FXWW9kSGx3Wlc5bUlGSTlQU0p2WW1wbFkzUWlKaVpTSVQwOWJuVnNiQ2w3YzNkcGRHTm9LRkl1SkNSMGVYQmxiMllwZTJOaGMyVWdU'
    || 'V1U2Y21WMGRYSnVJRzA5YlM1blpYUW9VaTVyWlhrOVBUMXVkV3hzUDNZNlVpNXJaWGtwZkh4dWRXeHNMR1lvY0N4dExGSXNWU2s3WTJGelpTQjRaVHB5WlhS'
    || 'MWNtNGdiVDF0TG1kbGRDaFNMbXRsZVQwOVBXNTFiR3cvZGpwU0xtdGxlU2w4Zkc1MWJHd3NlU2h3TEcwc1VpeFZLVHRqWVhObElFZGxPblpoY2lCWFBWSXVY'
    || 'Mmx1YVhRN2NtVjBkWEp1SUVRb2JTeHdMSFlzVnloU0xsOXdZWGxzYjJGa0tTeFZLWDFwWmloWWJpaFNLWHg4U0NoU0tTbHlaWFIxY200Z2JUMXRMbWRsZENo'
    || 'MktYeDhiblZzYkN4cUtIQXNiU3hTTEZVc2JuVnNiQ2s3Y0d3b2NDeFNLWDF5WlhSMWNtNGdiblZzYkgxbWRXNWpkR2x2YmlCQktHMHNjQ3gyTEZJcGUyWnZj'
    || 'aWgyWVhJZ1ZUMXVkV3hzTEZjOWJuVnNiQ3drUFhBc1FqMXdQVEFzVW1VOWJuVnNiRHNrSVQwOWJuVnNiQ1ltUWp4MkxteGxibWQwYUR0Q0t5c3BleVF1YVc1'
    || 'a1pYZytRajhvVW1VOUpDd2tQVzUxYkd3cE9sSmxQU1F1YzJsaWJHbHVaenQyWVhJZ2JtVTlSU2h0TENRc2RsdENYU3hTS1R0cFppaHVaVDA5UFc1MWJHd3Bl'
    || 'eVE5UFQxdWRXeHNKaVlvSkQxU1pTazdZbkpsWVd0OVpTWW1KQ1ltYm1VdVlXeDBaWEp1WVhSbFBUMDliblZzYkNZbWRDaHRMQ1FwTEhBOWFTaHVaU3h3TEVJ'
    || 'cExGYzlQVDF1ZFd4c1AxVTlibVU2Vnk1emFXSnNhVzVuUFc1bExGYzlibVVzSkQxU1pYMXBaaWhDUFQwOWRpNXNaVzVuZEdncGNtVjBkWEp1SUc0b2JTd2tL'
    || 'U3h3WlNZbVlXNG9iU3hDS1N4Vk8ybG1LQ1E5UFQxdWRXeHNLWHRtYjNJb08wSThkaTVzWlc1bmRHZzdRaXNyS1NROVZDaHRMSFpiUWwwc1Vpa3NKQ0U5UFc1'
    || 'MWJHd21KaWh3UFdrb0pDeHdMRUlwTEZjOVBUMXVkV3hzUDFVOUpEcFhMbk5wWW14cGJtYzlKQ3hYUFNRcE8zSmxkSFZ5YmlCd1pTWW1ZVzRvYlN4Q0tTeFZm'
    || 'V1p2Y2lna1BYSW9iU3drS1R0Q1BIWXViR1Z1WjNSb08wSXJLeWxTWlQxRUtDUXNiU3hDTEhaYlFsMHNVaWtzVW1VaFBUMXVkV3hzSmlZb1pTWW1VbVV1WVd4'
    || 'MFpYSnVZWFJsSVQwOWJuVnNiQ1ltSkM1a1pXeGxkR1VvVW1VdWEyVjVQVDA5Ym5Wc2JEOUNPbEpsTG10bGVTa3NjRDFwS0ZKbExIQXNRaWtzVnowOVBXNTFi'
    || 'R3cvVlQxU1pUcFhMbk5wWW14cGJtYzlVbVVzVnoxU1pTazdjbVYwZFhKdUlHVW1KaVF1Wm05eVJXRmphQ2htZFc1amRHbHZiaWh1YmlsN2NtVjBkWEp1SUhR'
    || 'b2JTeHViaWw5S1N4d1pTWW1ZVzRvYlN4Q0tTeFZmV1oxYm1OMGFXOXVJSG9vYlN4d0xIWXNVaWw3ZG1GeUlGVTlTQ2gyS1R0cFppaDBlWEJsYjJZZ1ZTRTlJ'
    || 'bVoxYm1OMGFXOXVJaWwwYUhKdmR5QkZjbkp2Y2loaEtERTFNQ2twTzJsbUtIWTlWUzVqWVd4c0tIWXBMSFk5UFc1MWJHd3BkR2h5YjNjZ1JYSnliM0lvWVNn'
    || 'eE5URXBLVHRtYjNJb2RtRnlJRmM5VlQxdWRXeHNMQ1E5Y0N4Q1BYQTlNQ3hTWlQxdWRXeHNMRzVsUFhZdWJtVjRkQ2dwT3lRaFBUMXVkV3hzSmlZaGJtVXVa'
    || 'Rzl1WlR0Q0t5c3NibVU5ZGk1dVpYaDBLQ2twZXlRdWFXNWtaWGcrUWo4b1VtVTlKQ3drUFc1MWJHd3BPbEpsUFNRdWMybGliR2x1Wnp0MllYSWdibTQ5UlNo'
    || 'dExDUXNibVV1ZG1Gc2RXVXNVaWs3YVdZb2JtNDlQVDF1ZFd4c0tYc2tQVDA5Ym5Wc2JDWW1LQ1E5VW1VcE8ySnlaV0ZyZldVbUppUW1KbTV1TG1Gc2RHVnli'
    || 'bUYwWlQwOVBXNTFiR3dtSm5Rb2JTd2tLU3h3UFdrb2JtNHNjQ3hDS1N4WFBUMDliblZzYkQ5VlBXNXVPbGN1YzJsaWJHbHVaejF1Yml4WFBXNXVMQ1E5VW1W'
    || 'OWFXWW9ibVV1Wkc5dVpTbHlaWFIxY200Z2JpaHRMQ1FwTEhCbEppWmhiaWh0TEVJcExGVTdhV1lvSkQwOVBXNTFiR3dwZTJadmNpZzdJVzVsTG1SdmJtVTdR'
    || 'aXNyTEc1bFBYWXVibVY0ZENncEtXNWxQVlFvYlN4dVpTNTJZV3gxWlN4U0tTeHVaU0U5UFc1MWJHd21KaWh3UFdrb2JtVXNjQ3hDS1N4WFBUMDliblZzYkQ5'
    || 'VlBXNWxPbGN1YzJsaWJHbHVaejF1WlN4WFBXNWxLVHR5WlhSMWNtNGdjR1VtSm1GdUtHMHNRaWtzVlgxbWIzSW9KRDF5S0cwc0pDazdJVzVsTG1SdmJtVTdR'
    || 'aXNyTEc1bFBYWXVibVY0ZENncEtXNWxQVVFvSkN4dExFSXNibVV1ZG1Gc2RXVXNVaWtzYm1VaFBUMXVkV3hzSmlZb1pTWW1ibVV1WVd4MFpYSnVZWFJsSVQw'
    || 'OWJuVnNiQ1ltSkM1a1pXeGxkR1VvYm1VdWEyVjVQVDA5Ym5Wc2JEOUNPbTVsTG10bGVTa3NjRDFwS0c1bExIQXNRaWtzVnowOVBXNTFiR3cvVlQxdVpUcFhM'
    || 'bk5wWW14cGJtYzlibVVzVnoxdVpTazdjbVYwZFhKdUlHVW1KaVF1Wm05eVJXRmphQ2htZFc1amRHbHZiaWh6Y0NsN2NtVjBkWEp1SUhRb2JTeHpjQ2w5S1N4'
    || 'd1pTWW1ZVzRvYlN4Q0tTeFZmV1oxYm1OMGFXOXVJSGRsS0cwc2NDeDJMRklwZTJsbUtIUjVjR1Z2WmlCMlBUMGliMkpxWldOMElpWW1kaUU5UFc1MWJHd21K'
    || 'bll1ZEhsd1pUMDlQV05sSmlaMkxtdGxlVDA5UFc1MWJHd21KaWgyUFhZdWNISnZjSE11WTJocGJHUnlaVzRwTEhSNWNHVnZaaUIyUFQwaWIySnFaV04wSWlZ'
    || 'bWRpRTlQVzUxYkd3cGUzTjNhWFJqYUNoMkxpUWtkSGx3Wlc5bUtYdGpZWE5sSUUxbE9tVTZlMlp2Y2loMllYSWdWVDEyTG10bGVTeFhQWEE3VnlFOVBXNTFi'
    || 'R3c3S1h0cFppaFhMbXRsZVQwOVBWVXBlMmxtS0ZVOWRpNTBlWEJsTEZVOVBUMWpaU2w3YVdZb1Z5NTBZV2M5UFQwM0tYdHVLRzBzVnk1emFXSnNhVzVuS1N4'
    || 'd1BXd29WeXgyTG5CeWIzQnpMbU5vYVd4a2NtVnVLU3h3TG5KbGRIVnliajF0TEcwOWNEdGljbVZoYXlCbGZYMWxiSE5sSUdsbUtGY3VaV3hsYldWdWRGUjVj'
    || 'R1U5UFQxVmZIeDBlWEJsYjJZZ1ZUMDlJbTlpYW1WamRDSW1KbFVoUFQxdWRXeHNKaVpWTGlRa2RIbHdaVzltUFQwOVIyVW1KbFYxS0ZVcFBUMDlWeTUwZVhC'
    || 'bEtYdHVLRzBzVnk1emFXSnNhVzVuS1N4d1BXd29WeXgyTG5CeWIzQnpLU3h3TG5KbFpqMVRjaWh0TEZjc2Rpa3NjQzV5WlhSMWNtNDliU3h0UFhBN1luSmxZ'
    || 'V3NnWlgxdUtHMHNWeWs3WW5KbFlXdDlaV3h6WlNCMEtHMHNWeWs3VnoxWExuTnBZbXhwYm1kOWRpNTBlWEJsUFQwOVkyVS9LSEE5WjI0b2RpNXdjbTl3Y3k1'
    || 'amFHbHNaSEpsYml4dExtMXZaR1VzVWl4MkxtdGxlU2tzY0M1eVpYUjFjbTQ5YlN4dFBYQXBPaWhTUFhwc0tIWXVkSGx3WlN4MkxtdGxlU3gyTG5CeWIzQnpM'
    || 'RzUxYkd3c2JTNXRiMlJsTEZJcExGSXVjbVZtUFZOeUtHMHNjQ3gyS1N4U0xuSmxkSFZ5YmoxdExHMDlVaWw5Y21WMGRYSnVJSE1vYlNrN1kyRnpaU0I0WlRw'
    || 'bE9udG1iM0lvVnoxMkxtdGxlVHR3SVQwOWJuVnNiRHNwZTJsbUtIQXVhMlY1UFQwOVZ5bHBaaWh3TG5SaFp6MDlQVFFtSm5BdWMzUmhkR1ZPYjJSbExtTnZi'
    || 'blJoYVc1bGNrbHVabTg5UFQxMkxtTnZiblJoYVc1bGNrbHVabThtSm5BdWMzUmhkR1ZPYjJSbExtbHRjR3hsYldWdWRHRjBhVzl1UFQwOWRpNXBiWEJzWlcx'
    || 'bGJuUmhkR2x2YmlsN2JpaHRMSEF1YzJsaWJHbHVaeWtzY0Qxc0tIQXNkaTVqYUdsc1pISmxibng4VzEwcExIQXVjbVYwZFhKdVBXMHNiVDF3TzJKeVpXRnJJ'
    || 'R1Y5Wld4elpYdHVLRzBzY0NrN1luSmxZV3Q5Wld4elpTQjBLRzBzY0NrN2NEMXdMbk5wWW14cGJtZDljRDFIYnloMkxHMHViVzlrWlN4U0tTeHdMbkpsZEhW'
    || 'eWJqMXRMRzA5Y0gxeVpYUjFjbTRnY3lodEtUdGpZWE5sSUVkbE9uSmxkSFZ5YmlCWFBYWXVYMmx1YVhRc2QyVW9iU3h3TEZjb2RpNWZjR0Y1Ykc5aFpDa3NV'
    || 'aWw5YVdZb1dHNG9kaWtwY21WMGRYSnVJRUVvYlN4d0xIWXNVaWs3YVdZb1NDaDJLU2x5WlhSMWNtNGdlaWh0TEhBc2RpeFNLVHR3YkNodExIWXBmWEpsZEhW'
    || 'eWJpQjBlWEJsYjJZZ2RqMDlJbk4wY21sdVp5SW1KblloUFQwaUlueDhkSGx3Wlc5bUlIWTlQU0p1ZFcxaVpYSWlQeWgyUFNJaUszWXNjQ0U5UFc1MWJHd21K'
    || 'bkF1ZEdGblBUMDlOajhvYmlodExIQXVjMmxpYkdsdVp5a3NjRDFzS0hBc2Rpa3NjQzV5WlhSMWNtNDliU3h0UFhBcE9paHVLRzBzY0Nrc2NEMVJieWgyTEcw'
    || 'dWJXOWtaU3hTS1N4d0xuSmxkSFZ5YmoxdExHMDljQ2tzY3lodEtTazZiaWh0TEhBcGZYSmxkSFZ5YmlCM1pYMTJZWElnZW00OVJuVW9JVEFwTEZkMVBVWjFL'
    || 'Q0V4S1N4b2JEMVJkQ2h1ZFd4c0tTeHRiRDF1ZFd4c0xGVnVQVzUxYkd3c1pXODliblZzYkR0bWRXNWpkR2x2YmlCMGJ5Z3BlMlZ2UFZWdVBXMXNQVzUxYkd4'
    || 'OVpuVnVZM1JwYjI0Z2JtOG9aU2w3ZG1GeUlIUTlhR3d1WTNWeWNtVnVkRHRoWlNob2JDa3NaUzVmWTNWeWNtVnVkRlpoYkhWbFBYUjlablZ1WTNScGIyNGdj'
    || 'bThvWlN4MExHNHBlMlp2Y2lnN1pTRTlQVzUxYkd3N0tYdDJZWElnY2oxbExtRnNkR1Z5Ym1GMFpUdHBaaWdvWlM1amFHbHNaRXhoYm1WekpuUXBJVDA5ZEQ4'
    || 'b1pTNWphR2xzWkV4aGJtVnpmRDEwTEhJaFBUMXVkV3hzSmlZb2NpNWphR2xzWkV4aGJtVnpmRDEwS1NrNmNpRTlQVzUxYkd3bUppaHlMbU5vYVd4a1RHRnVa'
    || 'WE1tZENraFBUMTBKaVlvY2k1amFHbHNaRXhoYm1WemZEMTBLU3hsUFQwOWJpbGljbVZoYXp0bFBXVXVjbVYwZFhKdWZYMW1kVzVqZEdsdmJpQkdiaWhsTEhR'
    || 'cGUyMXNQV1VzWlc4OVZXNDliblZzYkN4bFBXVXVaR1Z3Wlc1a1pXNWphV1Z6TEdVaFBUMXVkV3hzSmlabExtWnBjbk4wUTI5dWRHVjRkQ0U5UFc1MWJHd21K'
    || 'aWdvWlM1c1lXNWxjeVowS1NFOVBUQW1KaWhZWlQwaE1Da3NaUzVtYVhKemRFTnZiblJsZUhROWJuVnNiQ2w5Wm5WdVkzUnBiMjRnZFhRb1pTbDdkbUZ5SUhR'
    || 'OVpTNWZZM1Z5Y21WdWRGWmhiSFZsTzJsbUtHVnZJVDA5WlNscFppaGxQWHRqYjI1MFpYaDBPbVVzYldWdGIybDZaV1JXWVd4MVpUcDBMRzVsZUhRNmJuVnNi'
    || 'SDBzVlc0OVBUMXVkV3hzS1h0cFppaHRiRDA5UFc1MWJHd3BkR2h5YjNjZ1JYSnliM0lvWVNnek1EZ3BLVHRWYmoxbExHMXNMbVJsY0dWdVpHVnVZMmxsY3ox'
    || 'N2JHRnVaWE02TUN4bWFYSnpkRU52Ym5SbGVIUTZaWDE5Wld4elpTQlZiajFWYmk1dVpYaDBQV1U3Y21WMGRYSnVJSFI5ZG1GeUlHTnVQVzUxYkd3N1puVnVZ'
    || 'M1JwYjI0Z2JHOG9aU2w3WTI0OVBUMXVkV3hzUDJOdVBWdGxYVHBqYmk1d2RYTm9LR1VwZldaMWJtTjBhVzl1SUNSMUtHVXNkQ3h1TEhJcGUzWmhjaUJzUFhR'
    || 'dWFXNTBaWEpzWldGMlpXUTdjbVYwZFhKdUlHdzlQVDF1ZFd4c1B5aHVMbTVsZUhROWJpeHNieWgwS1NrNktHNHVibVY0ZEQxc0xtNWxlSFFzYkM1dVpYaDBQ'
    || 'VzRwTEhRdWFXNTBaWEpzWldGMlpXUTliaXhFZENobExISXBmV1oxYm1OMGFXOXVJRVIwS0dVc2RDbDdaUzVzWVc1bGMzdzlkRHQyWVhJZ2JqMWxMbUZzZEdW'
    || 'eWJtRjBaVHRtYjNJb2JpRTlQVzUxYkd3bUppaHVMbXhoYm1WemZEMTBLU3h1UFdVc1pUMWxMbkpsZEhWeWJqdGxJVDA5Ym5Wc2JEc3BaUzVqYUdsc1pFeGhi'
    || 'bVZ6ZkQxMExHNDlaUzVoYkhSbGNtNWhkR1VzYmlFOVBXNTFiR3dtSmlodUxtTm9hV3hrVEdGdVpYTjhQWFFwTEc0OVpTeGxQV1V1Y21WMGRYSnVPM0psZEhW'
    || 'eWJpQnVMblJoWnowOVBUTS9iaTV6ZEdGMFpVNXZaR1U2Ym5Wc2JIMTJZWElnUzNROUlURTdablZ1WTNScGIyNGdhVzhvWlNsN1pTNTFjR1JoZEdWUmRXVjFa'
    || 'VDE3WW1GelpWTjBZWFJsT21VdWJXVnRiMmw2WldSVGRHRjBaU3htYVhKemRFSmhjMlZWY0dSaGRHVTZiblZzYkN4c1lYTjBRbUZ6WlZWd1pHRjBaVHB1ZFd4'
    || 'c0xITm9ZWEpsWkRwN2NHVnVaR2x1WnpwdWRXeHNMR2x1ZEdWeWJHVmhkbVZrT201MWJHd3NiR0Z1WlhNNk1IMHNaV1ptWldOMGN6cHVkV3hzZlgxbWRXNWpk'
    || 'R2x2YmlCV2RTaGxMSFFwZTJVOVpTNTFjR1JoZEdWUmRXVjFaU3gwTG5Wd1pHRjBaVkYxWlhWbFBUMDlaU1ltS0hRdWRYQmtZWFJsVVhWbGRXVTllMkpoYzJW'
    || 'VGRHRjBaVHBsTG1KaGMyVlRkR0YwWlN4bWFYSnpkRUpoYzJWVmNHUmhkR1U2WlM1bWFYSnpkRUpoYzJWVmNHUmhkR1VzYkdGemRFSmhjMlZWY0dSaGRHVTZa'
    || 'UzVzWVhOMFFtRnpaVlZ3WkdGMFpTeHphR0Z5WldRNlpTNXphR0Z5WldRc1pXWm1aV04wY3pwbExtVm1abVZqZEhOOUtYMW1kVzVqZEdsdmJpQlFkQ2hsTEhR'
    || 'cGUzSmxkSFZ5Ym50bGRtVnVkRlJwYldVNlpTeHNZVzVsT25Rc2RHRm5PakFzY0dGNWJHOWhaRHB1ZFd4c0xHTmhiR3hpWVdOck9tNTFiR3dzYm1WNGREcHVk'
    || 'V3hzZlgxbWRXNWpkR2x2YmlCWWRDaGxMSFFzYmlsN2RtRnlJSEk5WlM1MWNHUmhkR1ZSZFdWMVpUdHBaaWh5UFQwOWJuVnNiQ2x5WlhSMWNtNGdiblZzYkR0'
    || 'cFppaHlQWEl1YzJoaGNtVmtMQ2hpSmpJcElUMDlNQ2w3ZG1GeUlHdzljaTV3Wlc1a2FXNW5PM0psZEhWeWJpQnNQVDA5Ym5Wc2JEOTBMbTVsZUhROWREb29k'
    || 'QzV1WlhoMFBXd3VibVY0ZEN4c0xtNWxlSFE5ZENrc2NpNXdaVzVrYVc1blBYUXNSSFFvWlN4dUtYMXlaWFIxY200Z2JEMXlMbWx1ZEdWeWJHVmhkbVZrTEd3'
    || 'OVBUMXVkV3hzUHloMExtNWxlSFE5ZEN4c2J5aHlLU2s2S0hRdWJtVjRkRDFzTG01bGVIUXNiQzV1WlhoMFBYUXBMSEl1YVc1MFpYSnNaV0YyWldROWRDeEVk'
    || 'Q2hsTEc0cGZXWjFibU4wYVc5dUlIWnNLR1VzZEN4dUtYdHBaaWgwUFhRdWRYQmtZWFJsVVhWbGRXVXNkQ0U5UFc1MWJHd21KaWgwUFhRdWMyaGhjbVZrTENo'
    || 'dUpqUXhPVFF5TkRBcElUMDlNQ2twZTNaaGNpQnlQWFF1YkdGdVpYTTdjaVk5WlM1d1pXNWthVzVuVEdGdVpYTXNibnc5Y2l4MExteGhibVZ6UFc0c2VHa29a'
    || 'U3h1S1gxOVpuVnVZM1JwYjI0Z1NIVW9aU3gwS1h0MllYSWdiajFsTG5Wd1pHRjBaVkYxWlhWbExISTlaUzVoYkhSbGNtNWhkR1U3YVdZb2NpRTlQVzUxYkd3'
    || 'bUppaHlQWEl1ZFhCa1lYUmxVWFZsZFdVc2JqMDlQWElwS1h0MllYSWdiRDF1ZFd4c0xHazliblZzYkR0cFppaHVQVzR1Wm1seWMzUkNZWE5sVlhCa1lYUmxM'
    || 'RzRoUFQxdWRXeHNLWHRrYjN0MllYSWdjejE3WlhabGJuUlVhVzFsT200dVpYWmxiblJVYVcxbExHeGhibVU2Ymk1c1lXNWxMSFJoWnpwdUxuUmhaeXh3WVhs'
    || 'c2IyRmtPbTR1Y0dGNWJHOWhaQ3hqWVd4c1ltRmphenB1TG1OaGJHeGlZV05yTEc1bGVIUTZiblZzYkgwN2FUMDlQVzUxYkd3L2JEMXBQWE02YVQxcExtNWxl'
    || 'SFE5Y3l4dVBXNHVibVY0ZEgxM2FHbHNaU2h1SVQwOWJuVnNiQ2s3YVQwOVBXNTFiR3cvYkQxcFBYUTZhVDFwTG01bGVIUTlkSDFsYkhObElHdzlhVDEwTzI0'
    || 'OWUySmhjMlZUZEdGMFpUcHlMbUpoYzJWVGRHRjBaU3htYVhKemRFSmhjMlZWY0dSaGRHVTZiQ3hzWVhOMFFtRnpaVlZ3WkdGMFpUcHBMSE5vWVhKbFpEcHlM'
    || 'bk5vWVhKbFpDeGxabVpsWTNSek9uSXVaV1ptWldOMGMzMHNaUzUxY0dSaGRHVlJkV1YxWlQxdU8zSmxkSFZ5Ym4xbFBXNHViR0Z6ZEVKaGMyVlZjR1JoZEdV'
    || 'c1pUMDlQVzUxYkd3L2JpNW1hWEp6ZEVKaGMyVlZjR1JoZEdVOWREcGxMbTVsZUhROWRDeHVMbXhoYzNSQ1lYTmxWWEJrWVhSbFBYUjlablZ1WTNScGIyNGda'
    || 'MndvWlN4MExHNHNjaWw3ZG1GeUlHdzlaUzUxY0dSaGRHVlJkV1YxWlR0TGREMGhNVHQyWVhJZ2FUMXNMbVpwY25OMFFtRnpaVlZ3WkdGMFpTeHpQV3d1YkdG'
    || 'emRFSmhjMlZWY0dSaGRHVXNZejFzTG5Ob1lYSmxaQzV3Wlc1a2FXNW5PMmxtS0dNaFBUMXVkV3hzS1h0c0xuTm9ZWEpsWkM1d1pXNWthVzVuUFc1MWJHdzdk'
    || 'bUZ5SUdZOVl5eDVQV1l1Ym1WNGREdG1MbTVsZUhROWJuVnNiQ3h6UFQwOWJuVnNiRDlwUFhrNmN5NXVaWGgwUFhrc2N6MW1PM1poY2lCcVBXVXVZV3gwWlhK'
    || 'dVlYUmxPMm9oUFQxdWRXeHNKaVlvYWoxcUxuVndaR0YwWlZGMVpYVmxMR005YWk1c1lYTjBRbUZ6WlZWd1pHRjBaU3hqSVQwOWN5WW1LR005UFQxdWRXeHNQ'
    || 'Mm91Wm1seWMzUkNZWE5sVlhCa1lYUmxQWGs2WXk1dVpYaDBQWGtzYWk1c1lYTjBRbUZ6WlZWd1pHRjBaVDFtS1NsOWFXWW9hU0U5UFc1MWJHd3BlM1poY2lC'
    || 'VVBXd3VZbUZ6WlZOMFlYUmxPM005TUN4cVBYazlaajF1ZFd4c0xHTTlhVHRrYjN0MllYSWdSVDFqTG14aGJtVXNSRDFqTG1WMlpXNTBWR2x0WlR0cFppZ29j'
    || 'aVpGS1QwOVBVVXBlMm9oUFQxdWRXeHNKaVlvYWoxcUxtNWxlSFE5ZTJWMlpXNTBWR2x0WlRwRUxHeGhibVU2TUN4MFlXYzZZeTUwWVdjc2NHRjViRzloWkRw'
    || 'akxuQmhlV3h2WVdRc1kyRnNiR0poWTJzNll5NWpZV3hzWW1GamF5eHVaWGgwT201MWJHeDlLVHRsT250MllYSWdRVDFsTEhvOVl6dHpkMmwwWTJnb1JUMTBM'
    || 'RVE5Yml4NkxuUmhaeWw3WTJGelpTQXhPbWxtS0VFOWVpNXdZWGxzYjJGa0xIUjVjR1Z2WmlCQlBUMGlablZ1WTNScGIyNGlLWHRVUFVFdVkyRnNiQ2hFTEZR'
    || 'c1JTazdZbkpsWVdzZ1pYMVVQVUU3WW5KbFlXc2daVHRqWVhObElETTZRUzVtYkdGbmN6MUJMbVpzWVdkekppMDJOVFV6TjN3eE1qZzdZMkZ6WlNBd09tbG1L'
    || 'RUU5ZWk1d1lYbHNiMkZrTEVVOWRIbHdaVzltSUVFOVBTSm1kVzVqZEdsdmJpSS9RUzVqWVd4c0tFUXNWQ3hGS1RwQkxFVTlQVzUxYkd3cFluSmxZV3NnWlR0'
    || 'VVBVa29lMzBzVkN4RktUdGljbVZoYXlCbE8yTmhjMlVnTWpwTGREMGhNSDE5WXk1allXeHNZbUZqYXlFOVBXNTFiR3dtSm1NdWJHRnVaU0U5UFRBbUppaGxM'
    || 'bVpzWVdkemZEMDJOQ3hGUFd3dVpXWm1aV04wY3l4RlBUMDliblZzYkQ5c0xtVm1abVZqZEhNOVcyTmRPa1V1Y0hWemFDaGpLU2w5Wld4elpTQkVQWHRsZG1W'
    || 'dWRGUnBiV1U2UkN4c1lXNWxPa1VzZEdGbk9tTXVkR0ZuTEhCaGVXeHZZV1E2WXk1d1lYbHNiMkZrTEdOaGJHeGlZV05yT21NdVkyRnNiR0poWTJzc2JtVjRk'
    || 'RHB1ZFd4c2ZTeHFQVDA5Ym5Wc2JEOG9lVDFxUFVRc1pqMVVLVHBxUFdvdWJtVjRkRDFFTEhOOFBVVTdhV1lvWXoxakxtNWxlSFFzWXowOVBXNTFiR3dwZTJs'
    || 'bUtHTTliQzV6YUdGeVpXUXVjR1Z1WkdsdVp5eGpQVDA5Ym5Wc2JDbGljbVZoYXp0RlBXTXNZejFGTG01bGVIUXNSUzV1WlhoMFBXNTFiR3dzYkM1c1lYTjBR'
    || 'bUZ6WlZWd1pHRjBaVDFGTEd3dWMyaGhjbVZrTG5CbGJtUnBibWM5Ym5Wc2JIMTlkMmhwYkdVb0lUQXBPMmxtS0dvOVBUMXVkV3hzSmlZb1pqMVVLU3hzTG1K'
    || 'aGMyVlRkR0YwWlQxbUxHd3VabWx5YzNSQ1lYTmxWWEJrWVhSbFBYa3NiQzVzWVhOMFFtRnpaVlZ3WkdGMFpUMXFMSFE5YkM1emFHRnlaV1F1YVc1MFpYSnNa'
    || 'V0YyWldRc2RDRTlQVzUxYkd3cGUydzlkRHRrYnlCemZEMXNMbXhoYm1Vc2JEMXNMbTVsZUhRN2QyaHBiR1VvYkNFOVBYUXBmV1ZzYzJVZ2FUMDlQVzUxYkd3'
    || 'bUppaHNMbk5vWVhKbFpDNXNZVzVsY3owd0tUdHdibnc5Y3l4bExteGhibVZ6UFhNc1pTNXRaVzF2YVhwbFpGTjBZWFJsUFZSOWZXWjFibU4wYVc5dUlFSjFL'
    || 'R1VzZEN4dUtYdHBaaWhsUFhRdVpXWm1aV04wY3l4MExtVm1abVZqZEhNOWJuVnNiQ3hsSVQwOWJuVnNiQ2xtYjNJb2REMHdPM1E4WlM1c1pXNW5kR2c3ZENz'
    || 'cktYdDJZWElnY2oxbFczUmRMR3c5Y2k1allXeHNZbUZqYXp0cFppaHNJVDA5Ym5Wc2JDbDdhV1lvY2k1allXeHNZbUZqYXoxdWRXeHNMSEk5Yml4MGVYQmxi'
    || 'MllnYkNFOUltWjFibU4wYVc5dUlpbDBhSEp2ZHlCRmNuSnZjaWhoS0RFNU1TeHNLU2s3YkM1allXeHNLSElwZlgxOWRtRnlJSGR5UFh0OUxFNTBQVkYwS0hk'
    || 'eUtTeGZjajFSZENoM2Npa3NSWEk5VVhRb2QzSXBPMloxYm1OMGFXOXVJR1J1S0dVcGUybG1LR1U5UFQxM2NpbDBhSEp2ZHlCRmNuSnZjaWhoS0RFM05Da3BP'
    || 'M0psZEhWeWJpQmxmV1oxYm1OMGFXOXVJRzl2S0dVc2RDbDdjM2RwZEdOb0tITmxLRVZ5TEhRcExITmxLRjl5TEdVcExITmxLRTUwTEhkeUtTeGxQWFF1Ym05'
    || 'a1pWUjVjR1VzWlNsN1kyRnpaU0E1T21OaGMyVWdNVEU2ZEQwb2REMTBMbVJ2WTNWdFpXNTBSV3hsYldWdWRDay9kQzV1WVcxbGMzQmhZMlZWVWtrNmMya29i'
    || 'blZzYkN3aUlpazdZbkpsWVdzN1pHVm1ZWFZzZERwbFBXVTlQVDA0UDNRdWNHRnlaVzUwVG05a1pUcDBMSFE5WlM1dVlXMWxjM0JoWTJWVlVrbDhmRzUxYkd3'
    || 'c1pUMWxMblJoWjA1aGJXVXNkRDF6YVNoMExHVXBmV0ZsS0U1MEtTeHpaU2hPZEN4MEtYMW1kVzVqZEdsdmJpQlhiaWdwZTJGbEtFNTBLU3hoWlNoZmNpa3NZ'
    || 'V1VvUlhJcGZXWjFibU4wYVc5dUlGRjFLR1VwZTJSdUtFVnlMbU4xY25KbGJuUXBPM1poY2lCMFBXUnVLRTUwTG1OMWNuSmxiblFwTEc0OWMya29kQ3hsTG5S'
    || 'NWNHVXBPM1FoUFQxdUppWW9jMlVvWDNJc1pTa3NjMlVvVG5Rc2Jpa3BmV1oxYm1OMGFXOXVJSE52S0dVcGUxOXlMbU4xY25KbGJuUTlQVDFsSmlZb1lXVW9U'
    || 'blFwTEdGbEtGOXlLU2w5ZG1GeUlHaGxQVkYwS0RBcE8yWjFibU4wYVc5dUlIbHNLR1VwZTJadmNpaDJZWElnZEQxbE8zUWhQVDF1ZFd4c095bDdhV1lvZEM1'
    || 'MFlXYzlQVDB4TXlsN2RtRnlJRzQ5ZEM1dFpXMXZhWHBsWkZOMFlYUmxPMmxtS0c0aFBUMXVkV3hzSmlZb2JqMXVMbVJsYUhsa2NtRjBaV1FzYmowOVBXNTFi'
    || 'R3g4Zkc0dVpHRjBZVDA5UFNJa1B5SjhmRzR1WkdGMFlUMDlQU0lrSVNJcEtYSmxkSFZ5YmlCMGZXVnNjMlVnYVdZb2RDNTBZV2M5UFQweE9TWW1kQzV0Wlcx'
    || 'dmFYcGxaRkJ5YjNCekxuSmxkbVZoYkU5eVpHVnlJVDA5ZG05cFpDQXdLWHRwWmlnb2RDNW1iR0ZuY3lZeE1qZ3BJVDA5TUNseVpYUjFjbTRnZEgxbGJITmxJ'
    || 'R2xtS0hRdVkyaHBiR1FoUFQxdWRXeHNLWHQwTG1Ob2FXeGtMbkpsZEhWeWJqMTBMSFE5ZEM1amFHbHNaRHRqYjI1MGFXNTFaWDFwWmloMFBUMDlaU2xpY21W'
    || 'aGF6dG1iM0lvTzNRdWMybGliR2x1WnowOVBXNTFiR3c3S1h0cFppaDBMbkpsZEhWeWJqMDlQVzUxYkd4OGZIUXVjbVYwZFhKdVBUMDlaU2x5WlhSMWNtNGdi'
    || 'blZzYkR0MFBYUXVjbVYwZFhKdWZYUXVjMmxpYkdsdVp5NXlaWFIxY200OWRDNXlaWFIxY200c2REMTBMbk5wWW14cGJtZDljbVYwZFhKdUlHNTFiR3g5ZG1G'
    || 'eUlIVnZQVnRkTzJaMWJtTjBhVzl1SUdGdktDbDdabTl5S0haaGNpQmxQVEE3WlR4MWJ5NXNaVzVuZEdnN1pTc3JLWFZ2VzJWZExsOTNiM0pyU1c1UWNtOW5j'
    || 'bVZ6YzFabGNuTnBiMjVRY21sdFlYSjVQVzUxYkd3N2RXOHViR1Z1WjNSb1BUQjlkbUZ5SUhoc1BYWmxMbEpsWVdOMFEzVnljbVZ1ZEVScGMzQmhkR05vWlhJ'
    || 'c1kyODlkbVV1VW1WaFkzUkRkWEp5Wlc1MFFtRjBZMmhEYjI1bWFXY3NabTQ5TUN4dFpUMXVkV3hzTEVWbFBXNTFiR3dzUTJVOWJuVnNiQ3hUYkQwaE1TeE9j'
    || 'ajBoTVN4cmNqMHdMRkptUFRBN1puVnVZM1JwYjI0Z1FXVW9LWHQwYUhKdmR5QkZjbkp2Y2loaEtETXlNU2twZldaMWJtTjBhVzl1SUdadktHVXNkQ2w3YVdZ'
    || 'b2REMDlQVzUxYkd3cGNtVjBkWEp1SVRFN1ptOXlLSFpoY2lCdVBUQTdiangwTG14bGJtZDBhQ1ltYmp4bExteGxibWQwYUR0dUt5c3BhV1lvSVcxMEtHVmJi'
    || 'bDBzZEZ0dVhTa3BjbVYwZFhKdUlURTdjbVYwZFhKdUlUQjlablZ1WTNScGIyNGdjRzhvWlN4MExHNHNjaXhzTEdrcGUybG1LR1p1UFdrc2JXVTlkQ3gwTG0x'
    || 'bGJXOXBlbVZrVTNSaGRHVTliblZzYkN4MExuVndaR0YwWlZGMVpYVmxQVzUxYkd3c2RDNXNZVzVsY3owd0xIaHNMbU4xY25KbGJuUTlaVDA5UFc1MWJHeDhm'
    || 'R1V1YldWdGIybDZaV1JUZEdGMFpUMDlQVzUxYkd3L1VHWTZUR1lzWlQxdUtISXNiQ2tzVG5JcGUyazlNRHRrYjN0cFppaE9jajBoTVN4cmNqMHdMREkxUEQx'
    || 'cEtYUm9jbTkzSUVWeWNtOXlLR0VvTXpBeEtTazdhU3M5TVN4RFpUMUZaVDF1ZFd4c0xIUXVkWEJrWVhSbFVYVmxkV1U5Ym5Wc2JDeDRiQzVqZFhKeVpXNTBQ'
    || 'VWxtTEdVOWJpaHlMR3dwZlhkb2FXeGxLRTV5S1gxcFppaDRiQzVqZFhKeVpXNTBQVVZzTEhROVJXVWhQVDF1ZFd4c0ppWkZaUzV1WlhoMElUMDliblZzYkN4'
    || 'bWJqMHdMRU5sUFVWbFBXMWxQVzUxYkd3c1UydzlJVEVzZENsMGFISnZkeUJGY25KdmNpaGhLRE13TUNrcE8zSmxkSFZ5YmlCbGZXWjFibU4wYVc5dUlHaHZL'
    || 'Q2w3ZG1GeUlHVTlhM0loUFQwd08zSmxkSFZ5YmlCcmNqMHdMR1Y5Wm5WdVkzUnBiMjRnYTNRb0tYdDJZWElnWlQxN2JXVnRiMmw2WldSVGRHRjBaVHB1ZFd4'
    || 'c0xHSmhjMlZUZEdGMFpUcHVkV3hzTEdKaGMyVlJkV1YxWlRwdWRXeHNMSEYxWlhWbE9tNTFiR3dzYm1WNGREcHVkV3hzZlR0eVpYUjFjbTRnUTJVOVBUMXVk'
    || 'V3hzUDIxbExtMWxiVzlwZW1Wa1UzUmhkR1U5UTJVOVpUcERaVDFEWlM1dVpYaDBQV1VzUTJWOVpuVnVZM1JwYjI0Z1lYUW9LWHRwWmloRlpUMDlQVzUxYkd3'
    || 'cGUzWmhjaUJsUFcxbExtRnNkR1Z5Ym1GMFpUdGxQV1VoUFQxdWRXeHNQMlV1YldWdGIybDZaV1JUZEdGMFpUcHVkV3hzZldWc2MyVWdaVDFGWlM1dVpYaDBP'
    || 'M1poY2lCMFBVTmxQVDA5Ym5Wc2JEOXRaUzV0WlcxdmFYcGxaRk4wWVhSbE9rTmxMbTVsZUhRN2FXWW9kQ0U5UFc1MWJHd3BRMlU5ZEN4RlpUMWxPMlZzYzJW'
    || 'N2FXWW9aVDA5UFc1MWJHd3BkR2h5YjNjZ1JYSnliM0lvWVNnek1UQXBLVHRGWlQxbExHVTllMjFsYlc5cGVtVmtVM1JoZEdVNlJXVXViV1Z0YjJsNlpXUlRk'
    || 'R0YwWlN4aVlYTmxVM1JoZEdVNlJXVXVZbUZ6WlZOMFlYUmxMR0poYzJWUmRXVjFaVHBGWlM1aVlYTmxVWFZsZFdVc2NYVmxkV1U2UldVdWNYVmxkV1VzYm1W'
    || 'NGREcHVkV3hzZlN4RFpUMDlQVzUxYkd3L2JXVXViV1Z0YjJsNlpXUlRkR0YwWlQxRFpUMWxPa05sUFVObExtNWxlSFE5WlgxeVpYUjFjbTRnUTJWOVpuVnVZ'
    || 'M1JwYjI0Z2FuSW9aU3gwS1h0eVpYUjFjbTRnZEhsd1pXOW1JSFE5UFNKbWRXNWpkR2x2YmlJL2RDaGxLVHAwZldaMWJtTjBhVzl1SUcxdktHVXBlM1poY2lC'
    || 'MFBXRjBLQ2tzYmoxMExuRjFaWFZsTzJsbUtHNDlQVDF1ZFd4c0tYUm9jbTkzSUVWeWNtOXlLR0VvTXpFeEtTazdiaTVzWVhOMFVtVnVaR1Z5WldSU1pXUjFZ'
    || 'MlZ5UFdVN2RtRnlJSEk5UldVc2JEMXlMbUpoYzJWUmRXVjFaU3hwUFc0dWNHVnVaR2x1Wnp0cFppaHBJVDA5Ym5Wc2JDbDdhV1lvYkNFOVBXNTFiR3dwZTNa'
    || 'aGNpQnpQV3d1Ym1WNGREdHNMbTVsZUhROWFTNXVaWGgwTEdrdWJtVjRkRDF6ZlhJdVltRnpaVkYxWlhWbFBXdzlhU3h1TG5CbGJtUnBibWM5Ym5Wc2JIMXBa'
    || 'aWhzSVQwOWJuVnNiQ2w3YVQxc0xtNWxlSFFzY2oxeUxtSmhjMlZUZEdGMFpUdDJZWElnWXoxelBXNTFiR3dzWmoxdWRXeHNMSGs5YVR0a2IzdDJZWElnYWox'
    || 'NUxteGhibVU3YVdZb0tHWnVKbW9wUFQwOWFpbG1JVDA5Ym5Wc2JDWW1LR1k5Wmk1dVpYaDBQWHRzWVc1bE9qQXNZV04wYVc5dU9ua3VZV04wYVc5dUxHaGhj'
    || 'MFZoWjJWeVUzUmhkR1U2ZVM1b1lYTkZZV2RsY2xOMFlYUmxMR1ZoWjJWeVUzUmhkR1U2ZVM1bFlXZGxjbE4wWVhSbExHNWxlSFE2Ym5Wc2JIMHBMSEk5ZVM1'
    || 'b1lYTkZZV2RsY2xOMFlYUmxQM2t1WldGblpYSlRkR0YwWlRwbEtISXNlUzVoWTNScGIyNHBPMlZzYzJWN2RtRnlJRlE5ZTJ4aGJtVTZhaXhoWTNScGIyNDZl'
    || 'UzVoWTNScGIyNHNhR0Z6UldGblpYSlRkR0YwWlRwNUxtaGhjMFZoWjJWeVUzUmhkR1VzWldGblpYSlRkR0YwWlRwNUxtVmhaMlZ5VTNSaGRHVXNibVY0ZERw'
    || 'dWRXeHNmVHRtUFQwOWJuVnNiRDhvWXoxbVBWUXNjejF5S1RwbVBXWXVibVY0ZEQxVUxHMWxMbXhoYm1WemZEMXFMSEJ1ZkQxcWZYazllUzV1WlhoMGZYZG9h'
    || 'V3hsS0hraFBUMXVkV3hzSmlaNUlUMDlhU2s3WmowOVBXNTFiR3cvY3oxeU9tWXVibVY0ZEQxakxHMTBLSElzZEM1dFpXMXZhWHBsWkZOMFlYUmxLWHg4S0Zo'
    || 'bFBTRXdLU3gwTG0xbGJXOXBlbVZrVTNSaGRHVTljaXgwTG1KaGMyVlRkR0YwWlQxekxIUXVZbUZ6WlZGMVpYVmxQV1lzYmk1c1lYTjBVbVZ1WkdWeVpXUlRk'
    || 'R0YwWlQxeWZXbG1LR1U5Ymk1cGJuUmxjbXhsWVhabFpDeGxJVDA5Ym5Wc2JDbDdiRDFsTzJSdklHazliQzVzWVc1bExHMWxMbXhoYm1WemZEMXBMSEJ1ZkQx'
    || 'cExHdzliQzV1WlhoME8zZG9hV3hsS0d3aFBUMWxLWDFsYkhObElHdzlQVDF1ZFd4c0ppWW9iaTVzWVc1bGN6MHdLVHR5WlhSMWNtNWJkQzV0WlcxdmFYcGxa'
    || 'Rk4wWVhSbExHNHVaR2x6Y0dGMFkyaGRmV1oxYm1OMGFXOXVJSFp2S0dVcGUzWmhjaUIwUFdGMEtDa3NiajEwTG5GMVpYVmxPMmxtS0c0OVBUMXVkV3hzS1hS'
    || 'b2NtOTNJRVZ5Y205eUtHRW9NekV4S1NrN2JpNXNZWE4wVW1WdVpHVnlaV1JTWldSMVkyVnlQV1U3ZG1GeUlISTliaTVrYVhOd1lYUmphQ3hzUFc0dWNHVnVa'
    || 'R2x1Wnl4cFBYUXViV1Z0YjJsNlpXUlRkR0YwWlR0cFppaHNJVDA5Ym5Wc2JDbDdiaTV3Wlc1a2FXNW5QVzUxYkd3N2RtRnlJSE05YkQxc0xtNWxlSFE3Wkc4'
    || 'Z2FUMWxLR2tzY3k1aFkzUnBiMjRwTEhNOWN5NXVaWGgwTzNkb2FXeGxLSE1oUFQxc0tUdHRkQ2hwTEhRdWJXVnRiMmw2WldSVGRHRjBaU2w4ZkNoWVpUMGhN'
    || 'Q2tzZEM1dFpXMXZhWHBsWkZOMFlYUmxQV2tzZEM1aVlYTmxVWFZsZFdVOVBUMXVkV3hzSmlZb2RDNWlZWE5sVTNSaGRHVTlhU2tzYmk1c1lYTjBVbVZ1WkdW'
    || 'eVpXUlRkR0YwWlQxcGZYSmxkSFZ5Ymx0cExISmRmV1oxYm1OMGFXOXVJRWQxS0NsN2ZXWjFibU4wYVc5dUlGbDFLR1VzZENsN2RtRnlJRzQ5YldVc2NqMWhk'
    || 'Q2dwTEd3OWRDZ3BMR2s5SVcxMEtISXViV1Z0YjJsNlpXUlRkR0YwWlN4c0tUdHBaaWhwSmlZb2NpNXRaVzF2YVhwbFpGTjBZWFJsUFd3c1dHVTlJVEFwTEhJ'
    || 'OWNpNXhkV1YxWlN4bmJ5aGFkUzVpYVc1a0tHNTFiR3dzYml4eUxHVXBMRnRsWFNrc2NpNW5aWFJUYm1Gd2MyaHZkQ0U5UFhSOGZHbDhmRU5sSVQwOWJuVnNi'
    || 'Q1ltUTJVdWJXVnRiMmw2WldSVGRHRjBaUzUwWVdjbU1TbDdhV1lvYmk1bWJHRm5jM3c5TWpBME9DeERjaWc1TEZoMUxtSnBibVFvYm5Wc2JDeHVMSElzYkN4'
    || 'MEtTeDJiMmxrSURBc2JuVnNiQ2tzVkdVOVBUMXVkV3hzS1hSb2NtOTNJRVZ5Y205eUtHRW9NelE1S1NrN0tHWnVKak13S1NFOVBUQjhmRXQxS0c0c2RDeHNL'
    || 'WDF5WlhSMWNtNGdiSDFtZFc1amRHbHZiaUJMZFNobExIUXNiaWw3WlM1bWJHRm5jM3c5TVRZek9EUXNaVDE3WjJWMFUyNWhjSE5vYjNRNmRDeDJZV3gxWlRw'
    || 'dWZTeDBQVzFsTG5Wd1pHRjBaVkYxWlhWbExIUTlQVDF1ZFd4c1B5aDBQWHRzWVhOMFJXWm1aV04wT201MWJHd3NjM1J2Y21Wek9tNTFiR3g5TEcxbExuVnda'
    || 'R0YwWlZGMVpYVmxQWFFzZEM1emRHOXlaWE05VzJWZEtUb29iajEwTG5OMGIzSmxjeXh1UFQwOWJuVnNiRDkwTG5OMGIzSmxjejFiWlYwNmJpNXdkWE5vS0dV'
    || 'cEtYMW1kVzVqZEdsdmJpQllkU2hsTEhRc2JpeHlLWHQwTG5aaGJIVmxQVzRzZEM1blpYUlRibUZ3YzJodmREMXlMSEYxS0hRcEppWktkU2hsS1gxbWRXNWpk'
    || 'R2x2YmlCYWRTaGxMSFFzYmlsN2NtVjBkWEp1SUc0b1puVnVZM1JwYjI0b0tYdHhkU2gwS1NZbVNuVW9aU2w5S1gxbWRXNWpkR2x2YmlCeGRTaGxLWHQyWVhJ'
    || 'Z2REMWxMbWRsZEZOdVlYQnphRzkwTzJVOVpTNTJZV3gxWlR0MGNubDdkbUZ5SUc0OWRDZ3BPM0psZEhWeWJpRnRkQ2hsTEc0cGZXTmhkR05vZTNKbGRIVnli'
    || 'aUV3ZlgxbWRXNWpkR2x2YmlCS2RTaGxLWHQyWVhJZ2REMUVkQ2hsTERFcE8zUWhQVDF1ZFd4c0ppWlRkQ2gwTEdVc01Td3RNU2w5Wm5WdVkzUnBiMjRnWW5V'
    || 'b1pTbDdkbUZ5SUhROWEzUW9LVHR5WlhSMWNtNGdkSGx3Wlc5bUlHVTlQU0ptZFc1amRHbHZiaUltSmlobFBXVW9LU2tzZEM1dFpXMXZhWHBsWkZOMFlYUmxQ'
    || 'WFF1WW1GelpWTjBZWFJsUFdVc1pUMTdjR1Z1WkdsdVp6cHVkV3hzTEdsdWRHVnliR1ZoZG1Wa09tNTFiR3dzYkdGdVpYTTZNQ3hrYVhOd1lYUmphRHB1ZFd4'
    || 'c0xHeGhjM1JTWlc1a1pYSmxaRkpsWkhWalpYSTZhbklzYkdGemRGSmxibVJsY21Wa1UzUmhkR1U2Wlgwc2RDNXhkV1YxWlQxbExHVTlaUzVrYVhOd1lYUmph'
    || 'RDFFWmk1aWFXNWtLRzUxYkd3c2JXVXNaU2tzVzNRdWJXVnRiMmw2WldSVGRHRjBaU3hsWFgxbWRXNWpkR2x2YmlCRGNpaGxMSFFzYml4eUtYdHlaWFIxY200'
    || 'Z1pUMTdkR0ZuT21Vc1kzSmxZWFJsT25Rc1pHVnpkSEp2ZVRwdUxHUmxjSE02Y2l4dVpYaDBPbTUxYkd4OUxIUTliV1V1ZFhCa1lYUmxVWFZsZFdVc2REMDlQ'
    || 'VzUxYkd3L0tIUTllMnhoYzNSRlptWmxZM1E2Ym5Wc2JDeHpkRzl5WlhNNmJuVnNiSDBzYldVdWRYQmtZWFJsVVhWbGRXVTlkQ3gwTG14aGMzUkZabVpsWTNR'
    || 'OVpTNXVaWGgwUFdVcE9paHVQWFF1YkdGemRFVm1abVZqZEN4dVBUMDliblZzYkQ5MExteGhjM1JGWm1abFkzUTlaUzV1WlhoMFBXVTZLSEk5Ymk1dVpYaDBM'
    || 'RzR1Ym1WNGREMWxMR1V1Ym1WNGREMXlMSFF1YkdGemRFVm1abVZqZEQxbEtTa3NaWDFtZFc1amRHbHZiaUJsWVNncGUzSmxkSFZ5YmlCaGRDZ3BMbTFsYlc5'
    || 'cGVtVmtVM1JoZEdWOVpuVnVZM1JwYjI0Z2Qyd29aU3gwTEc0c2NpbDdkbUZ5SUd3OWEzUW9LVHR0WlM1bWJHRm5jM3c5WlN4c0xtMWxiVzlwZW1Wa1UzUmhk'
    || 'R1U5UTNJb01YeDBMRzRzZG05cFpDQXdMSEk5UFQxMmIybGtJREEvYm5Wc2JEcHlLWDFtZFc1amRHbHZiaUJmYkNobExIUXNiaXh5S1h0MllYSWdiRDFoZENn'
    || 'cE8zSTljajA5UFhadmFXUWdNRDl1ZFd4c09uSTdkbUZ5SUdrOWRtOXBaQ0F3TzJsbUtFVmxJVDA5Ym5Wc2JDbDdkbUZ5SUhNOVJXVXViV1Z0YjJsNlpXUlRk'
    || 'R0YwWlR0cFppaHBQWE11WkdWemRISnZlU3h5SVQwOWJuVnNiQ1ltWm04b2NpeHpMbVJsY0hNcEtYdHNMbTFsYlc5cGVtVmtVM1JoZEdVOVEzSW9kQ3h1TEdr'
    || 'c2NpazdjbVYwZFhKdWZYMXRaUzVtYkdGbmMzdzlaU3hzTG0xbGJXOXBlbVZrVTNSaGRHVTlRM0lvTVh4MExHNHNhU3h5S1gxbWRXNWpkR2x2YmlCMFlTaGxM'
    || 'SFFwZTNKbGRIVnliaUIzYkNnNE16a3dOalUyTERnc1pTeDBLWDFtZFc1amRHbHZiaUJuYnlobExIUXBlM0psZEhWeWJpQmZiQ2d5TURRNExEZ3NaU3gwS1gx'
    || 'bWRXNWpkR2x2YmlCdVlTaGxMSFFwZTNKbGRIVnliaUJmYkNnMExESXNaU3gwS1gxbWRXNWpkR2x2YmlCeVlTaGxMSFFwZTNKbGRIVnliaUJmYkNnMExEUXNa'
    || 'U3gwS1gxbWRXNWpkR2x2YmlCc1lTaGxMSFFwZTJsbUtIUjVjR1Z2WmlCMFBUMGlablZ1WTNScGIyNGlLWEpsZEhWeWJpQmxQV1VvS1N4MEtHVXBMR1oxYm1O'
    || 'MGFXOXVLQ2w3ZENodWRXeHNLWDA3YVdZb2RDRTliblZzYkNseVpYUjFjbTRnWlQxbEtDa3NkQzVqZFhKeVpXNTBQV1VzWm5WdVkzUnBiMjRvS1h0MExtTjFj'
    || 'bkpsYm5ROWJuVnNiSDE5Wm5WdVkzUnBiMjRnYVdFb1pTeDBMRzRwZTNKbGRIVnliaUJ1UFc0aFBXNTFiR3cvYmk1amIyNWpZWFFvVzJWZEtUcHVkV3hzTEY5'
    || 'c0tEUXNOQ3hzWVM1aWFXNWtLRzUxYkd3c2RDeGxLU3h1S1gxbWRXNWpkR2x2YmlCNWJ5Z3BlMzFtZFc1amRHbHZiaUJ2WVNobExIUXBlM1poY2lCdVBXRjBL'
    || 'Q2s3ZEQxMFBUMDlkbTlwWkNBd1AyNTFiR3c2ZER0MllYSWdjajF1TG0xbGJXOXBlbVZrVTNSaGRHVTdjbVYwZFhKdUlISWhQVDF1ZFd4c0ppWjBJVDA5Ym5W'
    || 'c2JDWW1abThvZEN4eVd6RmRLVDl5V3pCZE9paHVMbTFsYlc5cGVtVmtVM1JoZEdVOVcyVXNkRjBzWlNsOVpuVnVZM1JwYjI0Z2MyRW9aU3gwS1h0MllYSWdi'
    || 'ajFoZENncE8zUTlkRDA5UFhadmFXUWdNRDl1ZFd4c09uUTdkbUZ5SUhJOWJpNXRaVzF2YVhwbFpGTjBZWFJsTzNKbGRIVnliaUJ5SVQwOWJuVnNiQ1ltZENF'
    || 'OVBXNTFiR3dtSm1adktIUXNjbHN4WFNrL2Nsc3dYVG9vWlQxbEtDa3NiaTV0WlcxdmFYcGxaRk4wWVhSbFBWdGxMSFJkTEdVcGZXWjFibU4wYVc5dUlIVmhL'
    || 'R1VzZEN4dUtYdHlaWFIxY200b1ptNG1NakVwUFQwOU1EOG9aUzVpWVhObFUzUmhkR1VtSmlobExtSmhjMlZUZEdGMFpUMGhNU3hZWlQwaE1Da3NaUzV0Wlcx'
    || 'dmFYcGxaRk4wWVhSbFBXNHBPaWh0ZENodUxIUXBmSHdvYmoxVmN5Z3BMRzFsTG14aGJtVnpmRDF1TEhCdWZEMXVMR1V1WW1GelpWTjBZWFJsUFNFd0tTeDBL'
    || 'WDFtZFc1amRHbHZiaUJQWmlobExIUXBlM1poY2lCdVBXbGxPMmxsUFc0aFBUMHdKaVkwUG00L2JqbzBMR1VvSVRBcE8zWmhjaUJ5UFdOdkxuUnlZVzV6YVhS'
    || 'cGIyNDdZMjh1ZEhKaGJuTnBkR2x2YmoxN2ZUdDBjbmw3WlNnaE1Ta3NkQ2dwZldacGJtRnNiSGw3YVdVOWJpeGpieTUwY21GdWMybDBhVzl1UFhKOWZXWjFi'
    || 'bU4wYVc5dUlHRmhLQ2w3Y21WMGRYSnVJR0YwS0NrdWJXVnRiMmw2WldSVGRHRjBaWDFtZFc1amRHbHZiaUJOWmlobExIUXNiaWw3ZG1GeUlISTlZblFvWlNr'
    || 'N2FXWW9iajE3YkdGdVpUcHlMR0ZqZEdsdmJqcHVMR2hoYzBWaFoyVnlVM1JoZEdVNklURXNaV0ZuWlhKVGRHRjBaVHB1ZFd4c0xHNWxlSFE2Ym5Wc2JIMHNZ'
    || 'MkVvWlNrcFpHRW9kQ3h1S1R0bGJITmxJR2xtS0c0OUpIVW9aU3gwTEc0c2Npa3NiaUU5UFc1MWJHd3BlM1poY2lCc1BVaGxLQ2s3VTNRb2JpeGxMSElzYkNr'
    || 'c1ptRW9iaXgwTEhJcGZYMW1kVzVqZEdsdmJpQkVaaWhsTEhRc2JpbDdkbUZ5SUhJOVluUW9aU2tzYkQxN2JHRnVaVHB5TEdGamRHbHZianB1TEdoaGMwVmha'
    || 'MlZ5VTNSaGRHVTZJVEVzWldGblpYSlRkR0YwWlRwdWRXeHNMRzVsZUhRNmJuVnNiSDA3YVdZb1kyRW9aU2twWkdFb2RDeHNLVHRsYkhObGUzWmhjaUJwUFdV'
    || 'dVlXeDBaWEp1WVhSbE8ybG1LR1V1YkdGdVpYTTlQVDB3SmlZb2FUMDlQVzUxYkd4OGZHa3ViR0Z1WlhNOVBUMHdLU1ltS0drOWRDNXNZWE4wVW1WdVpHVnla'
    || 'V1JTWldSMVkyVnlMR2toUFQxdWRXeHNLU2wwY25sN2RtRnlJSE05ZEM1c1lYTjBVbVZ1WkdWeVpXUlRkR0YwWlN4alBXa29jeXh1S1R0cFppaHNMbWhoYzBW'
    || 'aFoyVnlVM1JoZEdVOUlUQXNiQzVsWVdkbGNsTjBZWFJsUFdNc2JYUW9ZeXh6S1NsN2RtRnlJR1k5ZEM1cGJuUmxjbXhsWVhabFpEdG1QVDA5Ym5Wc2JEOG9i'
    || 'QzV1WlhoMFBXd3NiRzhvZENrcE9paHNMbTVsZUhROVppNXVaWGgwTEdZdWJtVjRkRDFzS1N4MExtbHVkR1Z5YkdWaGRtVmtQV3c3Y21WMGRYSnVmWDFqWVhS'
    || 'amFIdDlabWx1WVd4c2VYdDliajBrZFNobExIUXNiQ3h5S1N4dUlUMDliblZzYkNZbUtHdzlTR1VvS1N4VGRDaHVMR1VzY2l4c0tTeG1ZU2h1TEhRc2Npa3Bm'
    || 'WDFtZFc1amRHbHZiaUJqWVNobEtYdDJZWElnZEQxbExtRnNkR1Z5Ym1GMFpUdHlaWFIxY200Z1pUMDlQVzFsZkh4MElUMDliblZzYkNZbWREMDlQVzFsZlda'
    || 'MWJtTjBhVzl1SUdSaEtHVXNkQ2w3VG5JOVUydzlJVEE3ZG1GeUlHNDlaUzV3Wlc1a2FXNW5PMjQ5UFQxdWRXeHNQM1F1Ym1WNGREMTBPaWgwTG01bGVIUTli'
    || 'aTV1WlhoMExHNHVibVY0ZEQxMEtTeGxMbkJsYm1ScGJtYzlkSDFtZFc1amRHbHZiaUJtWVNobExIUXNiaWw3YVdZb0tHNG1OREU1TkRJME1Da2hQVDB3S1h0'
    || 'MllYSWdjajEwTG14aGJtVnpPM0ltUFdVdWNHVnVaR2x1WjB4aGJtVnpMRzU4UFhJc2RDNXNZVzVsY3oxdUxIaHBLR1VzYmlsOWZYWmhjaUJGYkQxN2NtVmha'
    || 'RU52Ym5SbGVIUTZkWFFzZFhObFEyRnNiR0poWTJzNlFXVXNkWE5sUTI5dWRHVjRkRHBCWlN4MWMyVkZabVpsWTNRNlFXVXNkWE5sU1cxd1pYSmhkR2wyWlVo'
    || 'aGJtUnNaVHBCWlN4MWMyVkpibk5sY25ScGIyNUZabVpsWTNRNlFXVXNkWE5sVEdGNWIzVjBSV1ptWldOME9rRmxMSFZ6WlUxbGJXODZRV1VzZFhObFVtVmtk'
    || 'V05sY2pwQlpTeDFjMlZTWldZNlFXVXNkWE5sVTNSaGRHVTZRV1VzZFhObFJHVmlkV2RXWVd4MVpUcEJaU3gxYzJWRVpXWmxjbkpsWkZaaGJIVmxPa0ZsTEhW'
    || 'elpWUnlZVzV6YVhScGIyNDZRV1VzZFhObFRYVjBZV0pzWlZOdmRYSmpaVHBCWlN4MWMyVlRlVzVqUlhoMFpYSnVZV3hUZEc5eVpUcEJaU3gxYzJWSlpEcEJa'
    || 'U3gxYm5OMFlXSnNaVjlwYzA1bGQxSmxZMjl1WTJsc1pYSTZJVEY5TEZCbVBYdHlaV0ZrUTI5dWRHVjRkRHAxZEN4MWMyVkRZV3hzWW1GamF6cG1kVzVqZEds'
    || 'dmJpaGxMSFFwZTNKbGRIVnliaUJyZENncExtMWxiVzlwZW1Wa1UzUmhkR1U5VzJVc2REMDlQWFp2YVdRZ01EOXVkV3hzT25SZExHVjlMSFZ6WlVOdmJuUmxl'
    || 'SFE2ZFhRc2RYTmxSV1ptWldOME9uUmhMSFZ6WlVsdGNHVnlZWFJwZG1WSVlXNWtiR1U2Wm5WdVkzUnBiMjRvWlN4MExHNHBlM0psZEhWeWJpQnVQVzRoUFc1'
    || 'MWJHdy9iaTVqYjI1allYUW9XMlZkS1RwdWRXeHNMSGRzS0RReE9UUXpNRGdzTkN4c1lTNWlhVzVrS0c1MWJHd3NkQ3hsS1N4dUtYMHNkWE5sVEdGNWIzVjBS'
    || 'V1ptWldOME9tWjFibU4wYVc5dUtHVXNkQ2w3Y21WMGRYSnVJSGRzS0RReE9UUXpNRGdzTkN4bExIUXBmU3gxYzJWSmJuTmxjblJwYjI1RlptWmxZM1E2Wm5W'
    || 'dVkzUnBiMjRvWlN4MEtYdHlaWFIxY200Z2Qyd29OQ3d5TEdVc2RDbDlMSFZ6WlUxbGJXODZablZ1WTNScGIyNG9aU3gwS1h0MllYSWdiajFyZENncE8zSmxk'
    || 'SFZ5YmlCMFBYUTlQVDEyYjJsa0lEQS9iblZzYkRwMExHVTlaU2dwTEc0dWJXVnRiMmw2WldSVGRHRjBaVDFiWlN4MFhTeGxmU3gxYzJWU1pXUjFZMlZ5T21a'
    || 'MWJtTjBhVzl1S0dVc2RDeHVLWHQyWVhJZ2NqMXJkQ2dwTzNKbGRIVnliaUIwUFc0aFBUMTJiMmxrSURBL2JpaDBLVHAwTEhJdWJXVnRiMmw2WldSVGRHRjBa'
    || 'VDF5TG1KaGMyVlRkR0YwWlQxMExHVTllM0JsYm1ScGJtYzZiblZzYkN4cGJuUmxjbXhsWVhabFpEcHVkV3hzTEd4aGJtVnpPakFzWkdsemNHRjBZMmc2Ym5W'
    || 'c2JDeHNZWE4wVW1WdVpHVnlaV1JTWldSMVkyVnlPbVVzYkdGemRGSmxibVJsY21Wa1UzUmhkR1U2ZEgwc2NpNXhkV1YxWlQxbExHVTlaUzVrYVhOd1lYUmph'
    || 'RDFOWmk1aWFXNWtLRzUxYkd3c2JXVXNaU2tzVzNJdWJXVnRiMmw2WldSVGRHRjBaU3hsWFgwc2RYTmxVbVZtT21aMWJtTjBhVzl1S0dVcGUzWmhjaUIwUFd0'
    || 'MEtDazdjbVYwZFhKdUlHVTllMk4xY25KbGJuUTZaWDBzZEM1dFpXMXZhWHBsWkZOMFlYUmxQV1Y5TEhWelpWTjBZWFJsT21KMUxIVnpaVVJsWW5WblZtRnNk'
    || 'V1U2ZVc4c2RYTmxSR1ZtWlhKeVpXUldZV3gxWlRwbWRXNWpkR2x2YmlobEtYdHlaWFIxY200Z2EzUW9LUzV0WlcxdmFYcGxaRk4wWVhSbFBXVjlMSFZ6WlZS'
    || 'eVlXNXphWFJwYjI0NlpuVnVZM1JwYjI0b0tYdDJZWElnWlQxaWRTZ2hNU2tzZEQxbFd6QmRPM0psZEhWeWJpQmxQVTltTG1KcGJtUW9iblZzYkN4bFd6RmRL'
    || 'U3hyZENncExtMWxiVzlwZW1Wa1UzUmhkR1U5WlN4YmRDeGxYWDBzZFhObFRYVjBZV0pzWlZOdmRYSmpaVHBtZFc1amRHbHZiaWdwZTMwc2RYTmxVM2x1WTBW'
    || 'NGRHVnlibUZzVTNSdmNtVTZablZ1WTNScGIyNG9aU3gwTEc0cGUzWmhjaUJ5UFcxbExHdzlhM1FvS1R0cFppaHdaU2w3YVdZb2JqMDlQWFp2YVdRZ01DbDBh'
    || 'SEp2ZHlCRmNuSnZjaWhoS0RRd055a3BPMjQ5YmlncGZXVnNjMlY3YVdZb2JqMTBLQ2tzVkdVOVBUMXVkV3hzS1hSb2NtOTNJRVZ5Y205eUtHRW9NelE1S1Nr'
    || 'N0tHWnVKak13S1NFOVBUQjhmRXQxS0hJc2RDeHVLWDFzTG0xbGJXOXBlbVZrVTNSaGRHVTlianQyWVhJZ2FUMTdkbUZzZFdVNmJpeG5aWFJUYm1Gd2MyaHZk'
    || 'RHAwZlR0eVpYUjFjbTRnYkM1eGRXVjFaVDFwTEhSaEtGcDFMbUpwYm1Rb2JuVnNiQ3h5TEdrc1pTa3NXMlZkS1N4eUxtWnNZV2R6ZkQweU1EUTRMRU55S0Rr'
    || 'c1dIVXVZbWx1WkNodWRXeHNMSElzYVN4dUxIUXBMSFp2YVdRZ01DeHVkV3hzS1N4dWZTeDFjMlZKWkRwbWRXNWpkR2x2YmlncGUzWmhjaUJsUFd0MEtDa3Nk'
    || 'RDFVWlM1cFpHVnVkR2xtYVdWeVVISmxabWw0TzJsbUtIQmxLWHQyWVhJZ2JqMU5kQ3h5UFU5ME8yNDlLSEltZmlneFBEd3pNaTFvZENoeUtTMHhLU2t1ZEc5'
    || 'VGRISnBibWNvTXpJcEsyNHNkRDBpT2lJcmRDc2lVaUlyYml4dVBXdHlLeXNzTUR4dUppWW9kQ3M5SWtnaUsyNHVkRzlUZEhKcGJtY29NeklwS1N4MEt6MGlP'
    || 'aUo5Wld4elpTQnVQVkptS3lzc2REMGlPaUlyZENzaWNpSXJiaTUwYjFOMGNtbHVaeWd6TWlrcklqb2lPM0psZEhWeWJpQmxMbTFsYlc5cGVtVmtVM1JoZEdV'
    || 'OWRIMHNkVzV6ZEdGaWJHVmZhWE5PWlhkU1pXTnZibU5wYkdWeU9pRXhmU3hNWmoxN2NtVmhaRU52Ym5SbGVIUTZkWFFzZFhObFEyRnNiR0poWTJzNmIyRXNk'
    || 'WE5sUTI5dWRHVjRkRHAxZEN4MWMyVkZabVpsWTNRNloyOHNkWE5sU1cxd1pYSmhkR2wyWlVoaGJtUnNaVHBwWVN4MWMyVkpibk5sY25ScGIyNUZabVpsWTNR'
    || 'NmJtRXNkWE5sVEdGNWIzVjBSV1ptWldOME9uSmhMSFZ6WlUxbGJXODZjMkVzZFhObFVtVmtkV05sY2pwdGJ5eDFjMlZTWldZNlpXRXNkWE5sVTNSaGRHVTZa'
    || 'blZ1WTNScGIyNG9LWHR5WlhSMWNtNGdiVzhvYW5JcGZTeDFjMlZFWldKMVoxWmhiSFZsT25sdkxIVnpaVVJsWm1WeWNtVmtWbUZzZFdVNlpuVnVZM1JwYjI0'
    || 'b1pTbDdkbUZ5SUhROVlYUW9LVHR5WlhSMWNtNGdkV0VvZEN4RlpTNXRaVzF2YVhwbFpGTjBZWFJsTEdVcGZTeDFjMlZVY21GdWMybDBhVzl1T21aMWJtTjBh'
    || 'Vzl1S0NsN2RtRnlJR1U5Ylc4b2FuSXBXekJkTEhROVlYUW9LUzV0WlcxdmFYcGxaRk4wWVhSbE8zSmxkSFZ5Ymx0bExIUmRmU3gxYzJWTmRYUmhZbXhsVTI5'
    || 'MWNtTmxPa2QxTEhWelpWTjVibU5GZUhSbGNtNWhiRk4wYjNKbE9sbDFMSFZ6WlVsa09tRmhMSFZ1YzNSaFlteGxYMmx6VG1WM1VtVmpiMjVqYVd4bGNqb2hN'
    || 'WDBzU1dZOWUzSmxZV1JEYjI1MFpYaDBPblYwTEhWelpVTmhiR3hpWVdOck9tOWhMSFZ6WlVOdmJuUmxlSFE2ZFhRc2RYTmxSV1ptWldOME9tZHZMSFZ6WlVs'
    || 'dGNHVnlZWFJwZG1WSVlXNWtiR1U2YVdFc2RYTmxTVzV6WlhKMGFXOXVSV1ptWldOME9tNWhMSFZ6WlV4aGVXOTFkRVZtWm1WamREcHlZU3gxYzJWTlpXMXZP'
    || 'bk5oTEhWelpWSmxaSFZqWlhJNmRtOHNkWE5sVW1WbU9tVmhMSFZ6WlZOMFlYUmxPbVoxYm1OMGFXOXVLQ2w3Y21WMGRYSnVJSFp2S0dweUtYMHNkWE5sUkdW'
    || 'aWRXZFdZV3gxWlRwNWJ5eDFjMlZFWldabGNuSmxaRlpoYkhWbE9tWjFibU4wYVc5dUtHVXBlM1poY2lCMFBXRjBLQ2s3Y21WMGRYSnVJRVZsUFQwOWJuVnNi'
    || 'RDkwTG0xbGJXOXBlbVZrVTNSaGRHVTlaVHAxWVNoMExFVmxMbTFsYlc5cGVtVmtVM1JoZEdVc1pTbDlMSFZ6WlZSeVlXNXphWFJwYjI0NlpuVnVZM1JwYjI0'
    || 'b0tYdDJZWElnWlQxMmJ5aHFjaWxiTUYwc2REMWhkQ2dwTG0xbGJXOXBlbVZrVTNSaGRHVTdjbVYwZFhKdVcyVXNkRjE5TEhWelpVMTFkR0ZpYkdWVGIzVnlZ'
    || 'MlU2UjNVc2RYTmxVM2x1WTBWNGRHVnlibUZzVTNSdmNtVTZXWFVzZFhObFNXUTZZV0VzZFc1emRHRmliR1ZmYVhOT1pYZFNaV052Ym1OcGJHVnlPaUV4ZlR0'
    || 'bWRXNWpkR2x2YmlCbmRDaGxMSFFwZTJsbUtHVW1KbVV1WkdWbVlYVnNkRkJ5YjNCektYdDBQVWtvZTMwc2RDa3NaVDFsTG1SbFptRjFiSFJRY205d2N6dG1i'
    || 'M0lvZG1GeUlHNGdhVzRnWlNsMFcyNWRQVDA5ZG05cFpDQXdKaVlvZEZ0dVhUMWxXMjVkS1R0eVpYUjFjbTRnZEgxeVpYUjFjbTRnZEgxbWRXNWpkR2x2YmlC'
    || 'NGJ5aGxMSFFzYml4eUtYdDBQV1V1YldWdGIybDZaV1JUZEdGMFpTeHVQVzRvY2l4MEtTeHVQVzQ5UFc1MWJHdy9kRHBKS0h0OUxIUXNiaWtzWlM1dFpXMXZh'
    || 'WHBsWkZOMFlYUmxQVzRzWlM1c1lXNWxjejA5UFRBbUppaGxMblZ3WkdGMFpWRjFaWFZsTG1KaGMyVlRkR0YwWlQxdUtYMTJZWElnVG13OWUybHpUVzkxYm5S'
    || 'bFpEcG1kVzVqZEdsdmJpaGxLWHR5WlhSMWNtNG9aVDFsTGw5eVpXRmpkRWx1ZEdWeWJtRnNjeWsvYkc0b1pTazlQVDFsT2lFeGZTeGxibkYxWlhWbFUyVjBV'
    || 'M1JoZEdVNlpuVnVZM1JwYjI0b1pTeDBMRzRwZTJVOVpTNWZjbVZoWTNSSmJuUmxjbTVoYkhNN2RtRnlJSEk5U0dVb0tTeHNQV0owS0dVcExHazlVSFFvY2l4'
    || 'c0tUdHBMbkJoZVd4dllXUTlkQ3h1SVQxdWRXeHNKaVlvYVM1allXeHNZbUZqYXoxdUtTeDBQVmgwS0dVc2FTeHNLU3gwSVQwOWJuVnNiQ1ltS0ZOMEtIUXNa'
    || 'U3hzTEhJcExIWnNLSFFzWlN4c0tTbDlMR1Z1Y1hWbGRXVlNaWEJzWVdObFUzUmhkR1U2Wm5WdVkzUnBiMjRvWlN4MExHNHBlMlU5WlM1ZmNtVmhZM1JKYm5S'
    || 'bGNtNWhiSE03ZG1GeUlISTlTR1VvS1N4c1BXSjBLR1VwTEdrOVVIUW9jaXhzS1R0cExuUmhaejB4TEdrdWNHRjViRzloWkQxMExHNGhQVzUxYkd3bUppaHBM'
    || 'bU5oYkd4aVlXTnJQVzRwTEhROVdIUW9aU3hwTEd3cExIUWhQVDF1ZFd4c0ppWW9VM1FvZEN4bExHd3NjaWtzZG13b2RDeGxMR3dwS1gwc1pXNXhkV1YxWlVa'
    || 'dmNtTmxWWEJrWVhSbE9tWjFibU4wYVc5dUtHVXNkQ2w3WlQxbExsOXlaV0ZqZEVsdWRHVnlibUZzY3p0MllYSWdiajFJWlNncExISTlZblFvWlNrc2JEMVFk'
    || 'Q2h1TEhJcE8yd3VkR0ZuUFRJc2RDRTliblZzYkNZbUtHd3VZMkZzYkdKaFkyczlkQ2tzZEQxWWRDaGxMR3dzY2lrc2RDRTlQVzUxYkd3bUppaFRkQ2gwTEdV'
    || 'c2NpeHVLU3gyYkNoMExHVXNjaWtwZlgwN1puVnVZM1JwYjI0Z2NHRW9aU3gwTEc0c2NpeHNMR2tzY3lsN2NtVjBkWEp1SUdVOVpTNXpkR0YwWlU1dlpHVXNk'
    || 'SGx3Wlc5bUlHVXVjMmh2ZFd4a1EyOXRjRzl1Wlc1MFZYQmtZWFJsUFQwaVpuVnVZM1JwYjI0aVAyVXVjMmh2ZFd4a1EyOXRjRzl1Wlc1MFZYQmtZWFJsS0hJ'
    || 'c2FTeHpLVHAwTG5CeWIzUnZkSGx3WlNZbWRDNXdjbTkwYjNSNWNHVXVhWE5RZFhKbFVtVmhZM1JEYjIxd2IyNWxiblEvSVhCeUtHNHNjaWw4ZkNGd2NpaHNM'
    || 'R2twT2lFd2ZXWjFibU4wYVc5dUlHaGhLR1VzZEN4dUtYdDJZWElnY2owaE1TeHNQVWQwTEdrOWRDNWpiMjUwWlhoMFZIbHdaVHR5WlhSMWNtNGdkSGx3Wlc5'
    || 'bUlHazlQU0p2WW1wbFkzUWlKaVpwSVQwOWJuVnNiRDlwUFhWMEtHa3BPaWhzUFV0bEtIUXBQM051T2tsbExtTjFjbkpsYm5Rc2NqMTBMbU52Ym5SbGVIUlVl'
    || 'WEJsY3l4cFBTaHlQWEloUFc1MWJHd3BQMUJ1S0dVc2JDazZSM1FwTEhROWJtVjNJSFFvYml4cEtTeGxMbTFsYlc5cGVtVmtVM1JoZEdVOWRDNXpkR0YwWlNF'
    || 'OVBXNTFiR3dtSm5RdWMzUmhkR1VoUFQxMmIybGtJREEvZEM1emRHRjBaVHB1ZFd4c0xIUXVkWEJrWVhSbGNqMU9iQ3hsTG5OMFlYUmxUbTlrWlQxMExIUXVY'
    || 'M0psWVdOMFNXNTBaWEp1WVd4elBXVXNjaVltS0dVOVpTNXpkR0YwWlU1dlpHVXNaUzVmWDNKbFlXTjBTVzUwWlhKdVlXeE5aVzF2YVhwbFpGVnViV0Z6YTJW'
    || 'a1EyaHBiR1JEYjI1MFpYaDBQV3dzWlM1ZlgzSmxZV04wU1c1MFpYSnVZV3hOWlcxdmFYcGxaRTFoYzJ0bFpFTm9hV3hrUTI5dWRHVjRkRDFwS1N4MGZXWjFi'
    || 'bU4wYVc5dUlHMWhLR1VzZEN4dUxISXBlMlU5ZEM1emRHRjBaU3gwZVhCbGIyWWdkQzVqYjIxd2IyNWxiblJYYVd4c1VtVmpaV2wyWlZCeWIzQnpQVDBpWm5W'
    || 'dVkzUnBiMjRpSmlaMExtTnZiWEJ2Ym1WdWRGZHBiR3hTWldObGFYWmxVSEp2Y0hNb2JpeHlLU3gwZVhCbGIyWWdkQzVWVGxOQlJrVmZZMjl0Y0c5dVpXNTBW'
    || 'MmxzYkZKbFkyVnBkbVZRY205d2N6MDlJbVoxYm1OMGFXOXVJaVltZEM1VlRsTkJSa1ZmWTI5dGNHOXVaVzUwVjJsc2JGSmxZMlZwZG1WUWNtOXdjeWh1TEhJ'
    || 'cExIUXVjM1JoZEdVaFBUMWxKaVpPYkM1bGJuRjFaWFZsVW1Wd2JHRmpaVk4wWVhSbEtIUXNkQzV6ZEdGMFpTeHVkV3hzS1gxbWRXNWpkR2x2YmlCVGJ5aGxM'
    || 'SFFzYml4eUtYdDJZWElnYkQxbExuTjBZWFJsVG05a1pUdHNMbkJ5YjNCelBXNHNiQzV6ZEdGMFpUMWxMbTFsYlc5cGVtVmtVM1JoZEdVc2JDNXlaV1p6UFh0'
    || 'OUxHbHZLR1VwTzNaaGNpQnBQWFF1WTI5dWRHVjRkRlI1Y0dVN2RIbHdaVzltSUdrOVBTSnZZbXBsWTNRaUppWnBJVDA5Ym5Wc2JEOXNMbU52Ym5SbGVIUTlk'
    || 'WFFvYVNrNktHazlTMlVvZENrL2MyNDZTV1V1WTNWeWNtVnVkQ3hzTG1OdmJuUmxlSFE5VUc0b1pTeHBLU2tzYkM1emRHRjBaVDFsTG0xbGJXOXBlbVZrVTNS'
    || 'aGRHVXNhVDEwTG1kbGRFUmxjbWwyWldSVGRHRjBaVVp5YjIxUWNtOXdjeXgwZVhCbGIyWWdhVDA5SW1aMWJtTjBhVzl1SWlZbUtIaHZLR1VzZEN4cExHNHBM'
    || 'R3d1YzNSaGRHVTlaUzV0WlcxdmFYcGxaRk4wWVhSbEtTeDBlWEJsYjJZZ2RDNW5aWFJFWlhKcGRtVmtVM1JoZEdWR2NtOXRVSEp2Y0hNOVBTSm1kVzVqZEds'
    || 'dmJpSjhmSFI1Y0dWdlppQnNMbWRsZEZOdVlYQnphRzkwUW1WbWIzSmxWWEJrWVhSbFBUMGlablZ1WTNScGIyNGlmSHgwZVhCbGIyWWdiQzVWVGxOQlJrVmZZ'
    || 'Mjl0Y0c5dVpXNTBWMmxzYkUxdmRXNTBJVDBpWm5WdVkzUnBiMjRpSmlaMGVYQmxiMllnYkM1amIyMXdiMjVsYm5SWGFXeHNUVzkxYm5RaFBTSm1kVzVqZEds'
    || 'dmJpSjhmQ2gwUFd3dWMzUmhkR1VzZEhsd1pXOW1JR3d1WTI5dGNHOXVaVzUwVjJsc2JFMXZkVzUwUFQwaVpuVnVZM1JwYjI0aUppWnNMbU52YlhCdmJtVnVk'
    || 'RmRwYkd4TmIzVnVkQ2dwTEhSNWNHVnZaaUJzTGxWT1UwRkdSVjlqYjIxd2IyNWxiblJYYVd4c1RXOTFiblE5UFNKbWRXNWpkR2x2YmlJbUptd3VWVTVUUVVa'
    || 'RlgyTnZiWEJ2Ym1WdWRGZHBiR3hOYjNWdWRDZ3BMSFFoUFQxc0xuTjBZWFJsSmlaT2JDNWxibkYxWlhWbFVtVndiR0ZqWlZOMFlYUmxLR3dzYkM1emRHRjBa'
    || 'U3h1ZFd4c0tTeG5iQ2hsTEc0c2JDeHlLU3hzTG5OMFlYUmxQV1V1YldWdGIybDZaV1JUZEdGMFpTa3NkSGx3Wlc5bUlHd3VZMjl0Y0c5dVpXNTBSR2xrVFc5'
    || 'MWJuUTlQU0ptZFc1amRHbHZiaUltSmlobExtWnNZV2R6ZkQwME1UazBNekE0S1gxbWRXNWpkR2x2YmlBa2JpaGxMSFFwZTNSeWVYdDJZWElnYmowaUlpeHlQ'
    || 'WFE3Wkc4Z2JpczlaV1VvY2lrc2NqMXlMbkpsZEhWeWJqdDNhR2xzWlNoeUtUdDJZWElnYkQxdWZXTmhkR05vS0drcGUydzlZQXBGY25KdmNpQm5aVzVsY21G'
    || 'MGFXNW5JSE4wWVdOck9pQmdLMmt1YldWemMyRm5aU3RnQ21BcmFTNXpkR0ZqYTMxeVpYUjFjbTU3ZG1Gc2RXVTZaU3h6YjNWeVkyVTZkQ3h6ZEdGamF6cHNM'
    || 'R1JwWjJWemREcHVkV3hzZlgxbWRXNWpkR2x2YmlCM2J5aGxMSFFzYmlsN2NtVjBkWEp1ZTNaaGJIVmxPbVVzYzI5MWNtTmxPbTUxYkd3c2MzUmhZMnM2Ymo4'
    || 'L2JuVnNiQ3hrYVdkbGMzUTZkRDgvYm5Wc2JIMTlablZ1WTNScGIyNGdYMjhvWlN4MEtYdDBjbmw3WTI5dWMyOXNaUzVsY25KdmNpaDBMblpoYkhWbEtYMWpZ'
    || 'WFJqYUNodUtYdHpaWFJVYVcxbGIzVjBLR1oxYm1OMGFXOXVLQ2w3ZEdoeWIzY2dibjBwZlgxMllYSWdRV1k5ZEhsd1pXOW1JRmRsWVd0TllYQTlQU0ptZFc1'
    || 'amRHbHZiaUkvVjJWaGEwMWhjRHBOWVhBN1puVnVZM1JwYjI0Z2RtRW9aU3gwTEc0cGUyNDlVSFFvTFRFc2Jpa3NiaTUwWVdjOU15eHVMbkJoZVd4dllXUTll'
    || 'MlZzWlcxbGJuUTZiblZzYkgwN2RtRnlJSEk5ZEM1MllXeDFaVHR5WlhSMWNtNGdiaTVqWVd4c1ltRmphejFtZFc1amRHbHZiaWdwZTAxc2ZId29UV3c5SVRB'
    || 'c2VtODljaWtzWDI4b1pTeDBLWDBzYm4xbWRXNWpkR2x2YmlCbllTaGxMSFFzYmlsN2JqMVFkQ2d0TVN4dUtTeHVMblJoWnowek8zWmhjaUJ5UFdVdWRIbHda'
    || 'UzVuWlhSRVpYSnBkbVZrVTNSaGRHVkdjbTl0UlhKeWIzSTdhV1lvZEhsd1pXOW1JSEk5UFNKbWRXNWpkR2x2YmlJcGUzWmhjaUJzUFhRdWRtRnNkV1U3Ymk1'
    || 'd1lYbHNiMkZrUFdaMWJtTjBhVzl1S0NsN2NtVjBkWEp1SUhJb2JDbDlMRzR1WTJGc2JHSmhZMnM5Wm5WdVkzUnBiMjRvS1h0ZmJ5aGxMSFFwZlgxMllYSWdh'
    || 'VDFsTG5OMFlYUmxUbTlrWlR0eVpYUjFjbTRnYVNFOVBXNTFiR3dtSm5SNWNHVnZaaUJwTG1OdmJYQnZibVZ1ZEVScFpFTmhkR05vUFQwaVpuVnVZM1JwYjI0'
    || 'aUppWW9iaTVqWVd4c1ltRmphejFtZFc1amRHbHZiaWdwZTE5dktHVXNkQ2tzZEhsd1pXOW1JSEloUFNKbWRXNWpkR2x2YmlJbUppaHhkRDA5UFc1MWJHdy9j'
    || 'WFE5Ym1WM0lGTmxkQ2hiZEdocGMxMHBPbkYwTG1Ga1pDaDBhR2x6S1NrN2RtRnlJSE05ZEM1emRHRmphenQwYUdsekxtTnZiWEJ2Ym1WdWRFUnBaRU5oZEdO'
    || 'b0tIUXVkbUZzZFdVc2UyTnZiWEJ2Ym1WdWRGTjBZV05yT25NaFBUMXVkV3hzUDNNNklpSjlLWDBwTEc1OVpuVnVZM1JwYjI0Z2VXRW9aU3gwTEc0cGUzWmhj'
    || 'aUJ5UFdVdWNHbHVaME5oWTJobE8ybG1LSEk5UFQxdWRXeHNLWHR5UFdVdWNHbHVaME5oWTJobFBXNWxkeUJCWmp0MllYSWdiRDF1WlhjZ1UyVjBPM0l1YzJW'
    || 'MEtIUXNiQ2w5Wld4elpTQnNQWEl1WjJWMEtIUXBMR3c5UFQxMmIybGtJREFtSmloc1BXNWxkeUJUWlhRc2NpNXpaWFFvZEN4c0tTazdiQzVvWVhNb2JpbDhm'
    || 'Q2hzTG1Ga1pDaHVLU3hsUFZwbUxtSnBibVFvYm5Wc2JDeGxMSFFzYmlrc2RDNTBhR1Z1S0dVc1pTa3BmV1oxYm1OMGFXOXVJSGhoS0dVcGUyUnZlM1poY2lC'
    || 'ME8ybG1LQ2gwUFdVdWRHRm5QVDA5TVRNcEppWW9kRDFsTG0xbGJXOXBlbVZrVTNSaGRHVXNkRDEwSVQwOWJuVnNiRDkwTG1SbGFIbGtjbUYwWldRaFBUMXVk'
    || 'V3hzT2lFd0tTeDBLWEpsZEhWeWJpQmxPMlU5WlM1eVpYUjFjbTU5ZDJocGJHVW9aU0U5UFc1MWJHd3BPM0psZEhWeWJpQnVkV3hzZldaMWJtTjBhVzl1SUZO'
    || 'aEtHVXNkQ3h1TEhJc2JDbDdjbVYwZFhKdUtHVXViVzlrWlNZeEtUMDlQVEEvS0dVOVBUMTBQMlV1Wm14aFozTjhQVFkxTlRNMk9paGxMbVpzWVdkemZEMHhN'
    || 'amdzYmk1bWJHRm5jM3c5TVRNeE1EY3lMRzR1Wm14aFozTW1QUzAxTWpnd05TeHVMblJoWnowOVBURW1KaWh1TG1Gc2RHVnlibUYwWlQwOVBXNTFiR3cvYmk1'
    || 'MFlXYzlNVGM2S0hROVVIUW9MVEVzTVNrc2RDNTBZV2M5TWl4WWRDaHVMSFFzTVNrcEtTeHVMbXhoYm1WemZEMHhLU3hsS1Rvb1pTNW1iR0ZuYzN3OU5qVTFN'
    || 'ellzWlM1c1lXNWxjejFzTEdVcGZYWmhjaUI2WmoxMlpTNVNaV0ZqZEVOMWNuSmxiblJQZDI1bGNpeFlaVDBoTVR0bWRXNWpkR2x2YmlCV1pTaGxMSFFzYml4'
    || 'eUtYdDBMbU5vYVd4a1BXVTlQVDF1ZFd4c1AxZDFLSFFzYm5Wc2JDeHVMSElwT25wdUtIUXNaUzVqYUdsc1pDeHVMSElwZldaMWJtTjBhVzl1SUhkaEtHVXNk'
    || 'Q3h1TEhJc2JDbDdiajF1TG5KbGJtUmxjanQyWVhJZ2FUMTBMbkpsWmp0eVpYUjFjbTRnUm00b2RDeHNLU3h5UFhCdktHVXNkQ3h1TEhJc2FTeHNLU3h1UFdo'
    || 'dktDa3NaU0U5UFc1MWJHd21KaUZZWlQ4b2RDNTFjR1JoZEdWUmRXVjFaVDFsTG5Wd1pHRjBaVkYxWlhWbExIUXVabXhoWjNNbVBTMHlNRFV6TEdVdWJHRnVa'
    || 'WE1tUFg1c0xFeDBLR1VzZEN4c0tTazZLSEJsSmladUppWllhU2gwS1N4MExtWnNZV2R6ZkQweExGWmxLR1VzZEN4eUxHd3BMSFF1WTJocGJHUXBmV1oxYm1O'
    || 'MGFXOXVJRjloS0dVc2RDeHVMSElzYkNsN2FXWW9aVDA5UFc1MWJHd3BlM1poY2lCcFBXNHVkSGx3WlR0eVpYUjFjbTRnZEhsd1pXOW1JR2s5UFNKbWRXNWpk'
    || 'R2x2YmlJbUppRkNieWhwS1NZbWFTNWtaV1poZFd4MFVISnZjSE05UFQxMmIybGtJREFtSm00dVkyOXRjR0Z5WlQwOVBXNTFiR3dtSm00dVpHVm1ZWFZzZEZC'
    || 'eWIzQnpQVDA5ZG05cFpDQXdQeWgwTG5SaFp6MHhOU3gwTG5SNWNHVTlhU3hGWVNobExIUXNhU3h5TEd3cEtUb29aVDE2YkNodUxuUjVjR1VzYm5Wc2JDeHlM'
    || 'SFFzZEM1dGIyUmxMR3dwTEdVdWNtVm1QWFF1Y21WbUxHVXVjbVYwZFhKdVBYUXNkQzVqYUdsc1pEMWxLWDFwWmlocFBXVXVZMmhwYkdRc0tHVXViR0Z1WlhN'
    || 'bWJDazlQVDB3S1h0MllYSWdjejFwTG0xbGJXOXBlbVZrVUhKdmNITTdhV1lvYmoxdUxtTnZiWEJoY21Vc2JqMXVJVDA5Ym5Wc2JEOXVPbkJ5TEc0b2N5eHlL'
    || 'U1ltWlM1eVpXWTlQVDEwTG5KbFppbHlaWFIxY200Z1RIUW9aU3gwTEd3cGZYSmxkSFZ5YmlCMExtWnNZV2R6ZkQweExHVTlkRzRvYVN4eUtTeGxMbkpsWmox'
    || 'MExuSmxaaXhsTG5KbGRIVnliajEwTEhRdVkyaHBiR1E5WlgxbWRXNWpkR2x2YmlCRllTaGxMSFFzYml4eUxHd3BlMmxtS0dVaFBUMXVkV3hzS1h0MllYSWdh'
    || 'VDFsTG0xbGJXOXBlbVZrVUhKdmNITTdhV1lvY0hJb2FTeHlLU1ltWlM1eVpXWTlQVDEwTG5KbFppbHBaaWhZWlQwaE1TeDBMbkJsYm1ScGJtZFFjbTl3Y3ox'
    || 'eVBXa3NLR1V1YkdGdVpYTW1iQ2toUFQwd0tTaGxMbVpzWVdkekpqRXpNVEEzTWlraFBUMHdKaVlvV0dVOUlUQXBPMlZzYzJVZ2NtVjBkWEp1SUhRdWJHRnVa'
    || 'WE05WlM1c1lXNWxjeXhNZENobExIUXNiQ2w5Y21WMGRYSnVJRVZ2S0dVc2RDeHVMSElzYkNsOVpuVnVZM1JwYjI0Z1RtRW9aU3gwTEc0cGUzWmhjaUJ5UFhR'
    || 'dWNHVnVaR2x1WjFCeWIzQnpMR3c5Y2k1amFHbHNaSEpsYml4cFBXVWhQVDF1ZFd4c1AyVXViV1Z0YjJsNlpXUlRkR0YwWlRwdWRXeHNPMmxtS0hJdWJXOWta'
    || 'VDA5UFNKb2FXUmtaVzRpS1dsbUtDaDBMbTF2WkdVbU1TazlQVDB3S1hRdWJXVnRiMmw2WldSVGRHRjBaVDE3WW1GelpVeGhibVZ6T2pBc1kyRmphR1ZRYjI5'
    || 'c09tNTFiR3dzZEhKaGJuTnBkR2x2Ym5NNmJuVnNiSDBzYzJVb1NHNHNhWFFwTEdsMGZEMXVPMlZzYzJWN2FXWW9LRzRtTVRBM016YzBNVGd5TkNrOVBUMHdL'
    || 'WEpsZEhWeWJpQmxQV2toUFQxdWRXeHNQMmt1WW1GelpVeGhibVZ6Zkc0NmJpeDBMbXhoYm1WelBYUXVZMmhwYkdSTVlXNWxjejB4TURjek56UXhPREkwTEhR'
    || 'dWJXVnRiMmw2WldSVGRHRjBaVDE3WW1GelpVeGhibVZ6T21Vc1kyRmphR1ZRYjI5c09tNTFiR3dzZEhKaGJuTnBkR2x2Ym5NNmJuVnNiSDBzZEM1MWNHUmhk'
    || 'R1ZSZFdWMVpUMXVkV3hzTEhObEtFaHVMR2wwS1N4cGRIdzlaU3h1ZFd4c08zUXViV1Z0YjJsNlpXUlRkR0YwWlQxN1ltRnpaVXhoYm1Wek9qQXNZMkZqYUdW'
    || 'UWIyOXNPbTUxYkd3c2RISmhibk5wZEdsdmJuTTZiblZzYkgwc2NqMXBJVDA5Ym5Wc2JEOXBMbUpoYzJWTVlXNWxjenB1TEhObEtFaHVMR2wwS1N4cGRIdzlj'
    || 'bjFsYkhObElHa2hQVDF1ZFd4c1B5aHlQV2t1WW1GelpVeGhibVZ6Zkc0c2RDNXRaVzF2YVhwbFpGTjBZWFJsUFc1MWJHd3BPbkk5Yml4elpTaEliaXhwZENr'
    || 'c2FYUjhQWEk3Y21WMGRYSnVJRlpsS0dVc2RDeHNMRzRwTEhRdVkyaHBiR1I5Wm5WdVkzUnBiMjRnYTJFb1pTeDBLWHQyWVhJZ2JqMTBMbkpsWmpzb1pUMDlQ'
    || 'VzUxYkd3bUptNGhQVDF1ZFd4c2ZIeGxJVDA5Ym5Wc2JDWW1aUzV5WldZaFBUMXVLU1ltS0hRdVpteGhaM044UFRVeE1peDBMbVpzWVdkemZEMHlNRGszTVRV'
    || 'eUtYMW1kVzVqZEdsdmJpQkZieWhsTEhRc2JpeHlMR3dwZTNaaGNpQnBQVXRsS0c0cFAzTnVPa2xsTG1OMWNuSmxiblE3Y21WMGRYSnVJR2s5VUc0b2RDeHBL'
    || 'U3hHYmloMExHd3BMRzQ5Y0c4b1pTeDBMRzRzY2l4cExHd3BMSEk5YUc4b0tTeGxJVDA5Ym5Wc2JDWW1JVmhsUHloMExuVndaR0YwWlZGMVpYVmxQV1V1ZFhC'
    || 'a1lYUmxVWFZsZFdVc2RDNW1iR0ZuY3lZOUxUSXdOVE1zWlM1c1lXNWxjeVk5Zm13c1RIUW9aU3gwTEd3cEtUb29jR1VtSm5JbUpsaHBLSFFwTEhRdVpteGha'
    || 'M044UFRFc1ZtVW9aU3gwTEc0c2JDa3NkQzVqYUdsc1pDbDlablZ1WTNScGIyNGdhbUVvWlN4MExHNHNjaXhzS1h0cFppaExaU2h1S1NsN2RtRnlJR2s5SVRB'
    || 'N2RXd29kQ2w5Wld4elpTQnBQU0V4TzJsbUtFWnVLSFFzYkNrc2RDNXpkR0YwWlU1dlpHVTlQVDF1ZFd4c0tXcHNLR1VzZENrc2FHRW9kQ3h1TEhJcExGTnZL'
    || 'SFFzYml4eUxHd3BMSEk5SVRBN1pXeHpaU0JwWmlobFBUMDliblZzYkNsN2RtRnlJSE05ZEM1emRHRjBaVTV2WkdVc1l6MTBMbTFsYlc5cGVtVmtVSEp2Y0hN'
    || 'N2N5NXdjbTl3Y3oxak8zWmhjaUJtUFhNdVkyOXVkR1Y0ZEN4NVBXNHVZMjl1ZEdWNGRGUjVjR1U3ZEhsd1pXOW1JSGs5UFNKdlltcGxZM1FpSmlaNUlUMDli'
    || 'blZzYkQ5NVBYVjBLSGtwT2loNVBVdGxLRzRwUDNOdU9rbGxMbU4xY25KbGJuUXNlVDFRYmloMExIa3BLVHQyWVhJZ2FqMXVMbWRsZEVSbGNtbDJaV1JUZEdG'
    || 'MFpVWnliMjFRY205d2N5eFVQWFI1Y0dWdlppQnFQVDBpWm5WdVkzUnBiMjRpZkh4MGVYQmxiMllnY3k1blpYUlRibUZ3YzJodmRFSmxabTl5WlZWd1pHRjBa'
    || 'VDA5SW1aMWJtTjBhVzl1SWp0VWZIeDBlWEJsYjJZZ2N5NVZUbE5CUmtWZlkyOXRjRzl1Wlc1MFYybHNiRkpsWTJWcGRtVlFjbTl3Y3lFOUltWjFibU4wYVc5'
    || 'dUlpWW1kSGx3Wlc5bUlITXVZMjl0Y0c5dVpXNTBWMmxzYkZKbFkyVnBkbVZRY205d2N5RTlJbVoxYm1OMGFXOXVJbng4S0dNaFBUMXlmSHhtSVQwOWVTa21K'
    || 'bTFoS0hRc2N5eHlMSGtwTEV0MFBTRXhPM1poY2lCRlBYUXViV1Z0YjJsNlpXUlRkR0YwWlR0ekxuTjBZWFJsUFVVc1oyd29kQ3h5TEhNc2JDa3NaajEwTG0x'
    || 'bGJXOXBlbVZrVTNSaGRHVXNZeUU5UFhKOGZFVWhQVDFtZkh4WlpTNWpkWEp5Wlc1MGZIeExkRDhvZEhsd1pXOW1JR285UFNKbWRXNWpkR2x2YmlJbUppaDRi'
    || 'eWgwTEc0c2FpeHlLU3htUFhRdWJXVnRiMmw2WldSVGRHRjBaU2tzS0dNOVMzUjhmSEJoS0hRc2JpeGpMSElzUlN4bUxIa3BLVDhvVkh4OGRIbHdaVzltSUhN'
    || 'dVZVNVRRVVpGWDJOdmJYQnZibVZ1ZEZkcGJHeE5iM1Z1ZENFOUltWjFibU4wYVc5dUlpWW1kSGx3Wlc5bUlITXVZMjl0Y0c5dVpXNTBWMmxzYkUxdmRXNTBJ'
    || 'VDBpWm5WdVkzUnBiMjRpZkh3b2RIbHdaVzltSUhNdVkyOXRjRzl1Wlc1MFYybHNiRTF2ZFc1MFBUMGlablZ1WTNScGIyNGlKaVp6TG1OdmJYQnZibVZ1ZEZk'
    || 'cGJHeE5iM1Z1ZENncExIUjVjR1Z2WmlCekxsVk9VMEZHUlY5amIyMXdiMjVsYm5SWGFXeHNUVzkxYm5ROVBTSm1kVzVqZEdsdmJpSW1Kbk11VlU1VFFVWkZY'
    || 'Mk52YlhCdmJtVnVkRmRwYkd4TmIzVnVkQ2dwS1N4MGVYQmxiMllnY3k1amIyMXdiMjVsYm5SRWFXUk5iM1Z1ZEQwOUltWjFibU4wYVc5dUlpWW1LSFF1Wm14'
    || 'aFozTjhQVFF4T1RRek1EZ3BLVG9vZEhsd1pXOW1JSE11WTI5dGNHOXVaVzUwUkdsa1RXOTFiblE5UFNKbWRXNWpkR2x2YmlJbUppaDBMbVpzWVdkemZEMDBN'
    || 'VGswTXpBNEtTeDBMbTFsYlc5cGVtVmtVSEp2Y0hNOWNpeDBMbTFsYlc5cGVtVmtVM1JoZEdVOVppa3NjeTV3Y205d2N6MXlMSE11YzNSaGRHVTlaaXh6TG1O'
    || 'dmJuUmxlSFE5ZVN4eVBXTXBPaWgwZVhCbGIyWWdjeTVqYjIxd2IyNWxiblJFYVdSTmIzVnVkRDA5SW1aMWJtTjBhVzl1SWlZbUtIUXVabXhoWjNOOFBUUXhP'
    || 'VFF6TURncExISTlJVEVwZldWc2MyVjdjejEwTG5OMFlYUmxUbTlrWlN4V2RTaGxMSFFwTEdNOWRDNXRaVzF2YVhwbFpGQnliM0J6TEhrOWRDNTBlWEJsUFQw'
    || 'OWRDNWxiR1Z0Wlc1MFZIbHdaVDlqT21kMEtIUXVkSGx3WlN4aktTeHpMbkJ5YjNCelBYa3NWRDEwTG5CbGJtUnBibWRRY205d2N5eEZQWE11WTI5dWRHVjRk'
    || 'Q3htUFc0dVkyOXVkR1Y0ZEZSNWNHVXNkSGx3Wlc5bUlHWTlQU0p2WW1wbFkzUWlKaVptSVQwOWJuVnNiRDltUFhWMEtHWXBPaWhtUFV0bEtHNHBQM051T2ts'
    || 'bExtTjFjbkpsYm5Rc1pqMVFiaWgwTEdZcEtUdDJZWElnUkQxdUxtZGxkRVJsY21sMlpXUlRkR0YwWlVaeWIyMVFjbTl3Y3pzb2FqMTBlWEJsYjJZZ1JEMDlJ'
    || 'bVoxYm1OMGFXOXVJbng4ZEhsd1pXOW1JSE11WjJWMFUyNWhjSE5vYjNSQ1pXWnZjbVZWY0dSaGRHVTlQU0ptZFc1amRHbHZiaUlwZkh4MGVYQmxiMllnY3k1'
    || 'VlRsTkJSa1ZmWTI5dGNHOXVaVzUwVjJsc2JGSmxZMlZwZG1WUWNtOXdjeUU5SW1aMWJtTjBhVzl1SWlZbWRIbHdaVzltSUhNdVkyOXRjRzl1Wlc1MFYybHNi'
    || 'RkpsWTJWcGRtVlFjbTl3Y3lFOUltWjFibU4wYVc5dUlueDhLR01oUFQxVWZIeEZJVDA5WmlrbUptMWhLSFFzY3l4eUxHWXBMRXQwUFNFeExFVTlkQzV0Wlcx'
    || 'dmFYcGxaRk4wWVhSbExITXVjM1JoZEdVOVJTeG5iQ2gwTEhJc2N5eHNLVHQyWVhJZ1FUMTBMbTFsYlc5cGVtVmtVM1JoZEdVN1l5RTlQVlI4ZkVVaFBUMUJm'
    || 'SHhaWlM1amRYSnlaVzUwZkh4TGREOG9kSGx3Wlc5bUlFUTlQU0ptZFc1amRHbHZiaUltSmloNGJ5aDBMRzRzUkN4eUtTeEJQWFF1YldWdGIybDZaV1JUZEdG'
    || 'MFpTa3NLSGs5UzNSOGZIQmhLSFFzYml4NUxISXNSU3hCTEdZcGZId2hNU2svS0dwOGZIUjVjR1Z2WmlCekxsVk9VMEZHUlY5amIyMXdiMjVsYm5SWGFXeHNW'
    || 'WEJrWVhSbElUMGlablZ1WTNScGIyNGlKaVowZVhCbGIyWWdjeTVqYjIxd2IyNWxiblJYYVd4c1ZYQmtZWFJsSVQwaVpuVnVZM1JwYjI0aWZId29kSGx3Wlc5'
    || 'bUlITXVZMjl0Y0c5dVpXNTBWMmxzYkZWd1pHRjBaVDA5SW1aMWJtTjBhVzl1SWlZbWN5NWpiMjF3YjI1bGJuUlhhV3hzVlhCa1lYUmxLSElzUVN4bUtTeDBl'
    || 'WEJsYjJZZ2N5NVZUbE5CUmtWZlkyOXRjRzl1Wlc1MFYybHNiRlZ3WkdGMFpUMDlJbVoxYm1OMGFXOXVJaVltY3k1VlRsTkJSa1ZmWTI5dGNHOXVaVzUwVjJs'
    || 'c2JGVndaR0YwWlNoeUxFRXNaaWtwTEhSNWNHVnZaaUJ6TG1OdmJYQnZibVZ1ZEVScFpGVndaR0YwWlQwOUltWjFibU4wYVc5dUlpWW1LSFF1Wm14aFozTjhQ'
    || 'VFFwTEhSNWNHVnZaaUJ6TG1kbGRGTnVZWEJ6YUc5MFFtVm1iM0psVlhCa1lYUmxQVDBpWm5WdVkzUnBiMjRpSmlZb2RDNW1iR0ZuYzN3OU1UQXlOQ2twT2lo'
    || 'MGVYQmxiMllnY3k1amIyMXdiMjVsYm5SRWFXUlZjR1JoZEdVaFBTSm1kVzVqZEdsdmJpSjhmR005UFQxbExtMWxiVzlwZW1Wa1VISnZjSE1tSmtVOVBUMWxM'
    || 'bTFsYlc5cGVtVmtVM1JoZEdWOGZDaDBMbVpzWVdkemZEMDBLU3gwZVhCbGIyWWdjeTVuWlhSVGJtRndjMmh2ZEVKbFptOXlaVlZ3WkdGMFpTRTlJbVoxYm1O'
    || 'MGFXOXVJbng4WXowOVBXVXViV1Z0YjJsNlpXUlFjbTl3Y3lZbVJUMDlQV1V1YldWdGIybDZaV1JUZEdGMFpYeDhLSFF1Wm14aFozTjhQVEV3TWpRcExIUXVi'
    || 'V1Z0YjJsNlpXUlFjbTl3Y3oxeUxIUXViV1Z0YjJsNlpXUlRkR0YwWlQxQktTeHpMbkJ5YjNCelBYSXNjeTV6ZEdGMFpUMUJMSE11WTI5dWRHVjRkRDFtTEhJ'
    || 'OWVTazZLSFI1Y0dWdlppQnpMbU52YlhCdmJtVnVkRVJwWkZWd1pHRjBaU0U5SW1aMWJtTjBhVzl1SW54OFl6MDlQV1V1YldWdGIybDZaV1JRY205d2N5WW1S'
    || 'VDA5UFdVdWJXVnRiMmw2WldSVGRHRjBaWHg4S0hRdVpteGhaM044UFRRcExIUjVjR1Z2WmlCekxtZGxkRk51WVhCemFHOTBRbVZtYjNKbFZYQmtZWFJsSVQw'
    || 'aVpuVnVZM1JwYjI0aWZIeGpQVDA5WlM1dFpXMXZhWHBsWkZCeWIzQnpKaVpGUFQwOVpTNXRaVzF2YVhwbFpGTjBZWFJsZkh3b2RDNW1iR0ZuYzN3OU1UQXlO'
    || 'Q2tzY2owaE1TbDljbVYwZFhKdUlFNXZLR1VzZEN4dUxISXNhU3hzS1gxbWRXNWpkR2x2YmlCT2J5aGxMSFFzYml4eUxHd3NhU2w3YTJFb1pTeDBLVHQyWVhJ'
    || 'Z2N6MG9kQzVtYkdGbmN5WXhNamdwSVQwOU1EdHBaaWdoY2lZbUlYTXBjbVYwZFhKdUlHd21KazExS0hRc2Jpd2hNU2tzVEhRb1pTeDBMR2twTzNJOWRDNXpk'
    || 'R0YwWlU1dlpHVXNlbVl1WTNWeWNtVnVkRDEwTzNaaGNpQmpQWE1tSm5SNWNHVnZaaUJ1TG1kbGRFUmxjbWwyWldSVGRHRjBaVVp5YjIxRmNuSnZjaUU5SW1a'
    || 'MWJtTjBhVzl1SWo5dWRXeHNPbkl1Y21WdVpHVnlLQ2s3Y21WMGRYSnVJSFF1Wm14aFozTjhQVEVzWlNFOVBXNTFiR3dtSm5NL0tIUXVZMmhwYkdROWVtNG9k'
    || 'Q3hsTG1Ob2FXeGtMRzUxYkd3c2FTa3NkQzVqYUdsc1pEMTZiaWgwTEc1MWJHd3NZeXhwS1NrNlZtVW9aU3gwTEdNc2FTa3NkQzV0WlcxdmFYcGxaRk4wWVhS'
    || 'bFBYSXVjM1JoZEdVc2JDWW1UWFVvZEN4dUxDRXdLU3gwTG1Ob2FXeGtmV1oxYm1OMGFXOXVJRU5oS0dVcGUzWmhjaUIwUFdVdWMzUmhkR1ZPYjJSbE8zUXVj'
    || 'R1Z1WkdsdVowTnZiblJsZUhRL1VuVW9aU3gwTG5CbGJtUnBibWREYjI1MFpYaDBMSFF1Y0dWdVpHbHVaME52Ym5SbGVIUWhQVDEwTG1OdmJuUmxlSFFwT25R'
    || 'dVkyOXVkR1Y0ZENZbVVuVW9aU3gwTG1OdmJuUmxlSFFzSVRFcExHOXZLR1VzZEM1amIyNTBZV2x1WlhKSmJtWnZLWDFtZFc1amRHbHZiaUJVWVNobExIUXNi'
    || 'aXh5TEd3cGUzSmxkSFZ5YmlCQmJpZ3BMR0pwS0d3cExIUXVabXhoWjNOOFBUSTFOaXhXWlNobExIUXNiaXh5S1N4MExtTm9hV3hrZlhaaGNpQnJiejE3WkdW'
    || 'b2VXUnlZWFJsWkRwdWRXeHNMSFJ5WldWRGIyNTBaWGgwT201MWJHd3NjbVYwY25sTVlXNWxPakI5TzJaMWJtTjBhVzl1SUdwdktHVXBlM0psZEhWeWJudGlZ'
    || 'WE5sVEdGdVpYTTZaU3hqWVdOb1pWQnZiMnc2Ym5Wc2JDeDBjbUZ1YzJsMGFXOXVjenB1ZFd4c2ZYMW1kVzVqZEdsdmJpQlNZU2hsTEhRc2JpbDdkbUZ5SUhJ'
    || 'OWRDNXdaVzVrYVc1blVISnZjSE1zYkQxb1pTNWpkWEp5Wlc1MExHazlJVEVzY3owb2RDNW1iR0ZuY3lZeE1qZ3BJVDA5TUN4ak8ybG1LQ2hqUFhNcGZId29Z'
    || 'ejFsSVQwOWJuVnNiQ1ltWlM1dFpXMXZhWHBsWkZOMFlYUmxQVDA5Ym5Wc2JEOGhNVG9vYkNZeUtTRTlQVEFwTEdNL0tHazlJVEFzZEM1bWJHRm5jeVk5TFRF'
    || 'eU9TazZLR1U5UFQxdWRXeHNmSHhsTG0xbGJXOXBlbVZrVTNSaGRHVWhQVDF1ZFd4c0tTWW1LR3g4UFRFcExITmxLR2hsTEd3bU1Ta3NaVDA5UFc1MWJHd3Bj'
    || 'bVYwZFhKdUlFcHBLSFFwTEdVOWRDNXRaVzF2YVhwbFpGTjBZWFJsTEdVaFBUMXVkV3hzSmlZb1pUMWxMbVJsYUhsa2NtRjBaV1FzWlNFOVBXNTFiR3dwUHln'
    || 'b2RDNXRiMlJsSmpFcFBUMDlNRDkwTG14aGJtVnpQVEU2WlM1a1lYUmhQVDA5SWlRaElqOTBMbXhoYm1WelBUZzZkQzVzWVc1bGN6MHhNRGN6TnpReE9ESTBM'
    || 'RzUxYkd3cE9paHpQWEl1WTJocGJHUnlaVzRzWlQxeUxtWmhiR3hpWVdOckxHay9LSEk5ZEM1dGIyUmxMR2s5ZEM1amFHbHNaQ3h6UFh0dGIyUmxPaUpvYVdS'
    || 'a1pXNGlMR05vYVd4a2NtVnVPbk45TENoeUpqRXBQVDA5TUNZbWFTRTlQVzUxYkd3L0tHa3VZMmhwYkdSTVlXNWxjejB3TEdrdWNHVnVaR2x1WjFCeWIzQnpQ'
    || 'WE1wT21rOVZXd29jeXh5TERBc2JuVnNiQ2tzWlQxbmJpaGxMSElzYml4dWRXeHNLU3hwTG5KbGRIVnliajEwTEdVdWNtVjBkWEp1UFhRc2FTNXphV0pzYVc1'
    || 'blBXVXNkQzVqYUdsc1pEMXBMSFF1WTJocGJHUXViV1Z0YjJsNlpXUlRkR0YwWlQxcWJ5aHVLU3gwTG0xbGJXOXBlbVZrVTNSaGRHVTlhMjhzWlNrNlEyOG9k'
    || 'Q3h6S1NrN2FXWW9iRDFsTG0xbGJXOXBlbVZrVTNSaGRHVXNiQ0U5UFc1MWJHd21KaWhqUFd3dVpHVm9lV1J5WVhSbFpDeGpJVDA5Ym5Wc2JDa3BjbVYwZFhK'
    || 'dUlGVm1LR1VzZEN4ekxISXNZeXhzTEc0cE8ybG1LR2twZTJrOWNpNW1ZV3hzWW1GamF5eHpQWFF1Ylc5a1pTeHNQV1V1WTJocGJHUXNZejFzTG5OcFlteHBi'
    || 'bWM3ZG1GeUlHWTllMjF2WkdVNkltaHBaR1JsYmlJc1kyaHBiR1J5Wlc0NmNpNWphR2xzWkhKbGJuMDdjbVYwZFhKdUtITW1NU2s5UFQwd0ppWjBMbU5vYVd4'
    || 'a0lUMDliRDhvY2oxMExtTm9hV3hrTEhJdVkyaHBiR1JNWVc1bGN6MHdMSEl1Y0dWdVpHbHVaMUJ5YjNCelBXWXNkQzVrWld4bGRHbHZibk05Ym5Wc2JDazZL'
    || 'SEk5ZEc0b2JDeG1LU3h5TG5OMVluUnlaV1ZHYkdGbmN6MXNMbk4xWW5SeVpXVkdiR0ZuY3lZeE5EWTRNREEyTkNrc1l5RTlQVzUxYkd3L2FUMTBiaWhqTEdr'
    || 'cE9paHBQV2R1S0drc2N5eHVMRzUxYkd3cExHa3VabXhoWjNOOFBUSXBMR2t1Y21WMGRYSnVQWFFzY2k1eVpYUjFjbTQ5ZEN4eUxuTnBZbXhwYm1jOWFTeDBM'
    || 'bU5vYVd4a1BYSXNjajFwTEdrOWRDNWphR2xzWkN4elBXVXVZMmhwYkdRdWJXVnRiMmw2WldSVGRHRjBaU3h6UFhNOVBUMXVkV3hzUDJwdktHNHBPbnRpWVhO'
    || 'bFRHRnVaWE02Y3k1aVlYTmxUR0Z1WlhOOGJpeGpZV05vWlZCdmIydzZiblZzYkN4MGNtRnVjMmwwYVc5dWN6cHpMblJ5WVc1emFYUnBiMjV6ZlN4cExtMWxi'
    || 'VzlwZW1Wa1UzUmhkR1U5Y3l4cExtTm9hV3hrVEdGdVpYTTlaUzVqYUdsc1pFeGhibVZ6Sm41dUxIUXViV1Z0YjJsNlpXUlRkR0YwWlQxcmJ5eHlmWEpsZEhW'
    || 'eWJpQnBQV1V1WTJocGJHUXNaVDFwTG5OcFlteHBibWNzY2oxMGJpaHBMSHR0YjJSbE9pSjJhWE5wWW14bElpeGphR2xzWkhKbGJqcHlMbU5vYVd4a2NtVnVm'
    || 'U2tzS0hRdWJXOWtaU1l4S1QwOVBUQW1KaWh5TG14aGJtVnpQVzRwTEhJdWNtVjBkWEp1UFhRc2NpNXphV0pzYVc1blBXNTFiR3dzWlNFOVBXNTFiR3dtSmlo'
    || 'dVBYUXVaR1ZzWlhScGIyNXpMRzQ5UFQxdWRXeHNQeWgwTG1SbGJHVjBhVzl1Y3oxYlpWMHNkQzVtYkdGbmMzdzlNVFlwT200dWNIVnphQ2hsS1Nrc2RDNWph'
    || 'R2xzWkQxeUxIUXViV1Z0YjJsNlpXUlRkR0YwWlQxdWRXeHNMSEo5Wm5WdVkzUnBiMjRnUTI4b1pTeDBLWHR5WlhSMWNtNGdkRDFWYkNoN2JXOWtaVG9pZG1s'
    || 'emFXSnNaU0lzWTJocGJHUnlaVzQ2ZEgwc1pTNXRiMlJsTERBc2JuVnNiQ2tzZEM1eVpYUjFjbTQ5WlN4bExtTm9hV3hrUFhSOVpuVnVZM1JwYjI0Z2Eyd29a'
    || 'U3gwTEc0c2NpbDdjbVYwZFhKdUlISWhQVDF1ZFd4c0ppWmlhU2h5S1N4NmJpaDBMR1V1WTJocGJHUXNiblZzYkN4dUtTeGxQVU52S0hRc2RDNXdaVzVrYVc1'
    || 'blVISnZjSE11WTJocGJHUnlaVzRwTEdVdVpteGhaM044UFRJc2RDNXRaVzF2YVhwbFpGTjBZWFJsUFc1MWJHd3NaWDFtZFc1amRHbHZiaUJWWmlobExIUXNi'
    || 'aXh5TEd3c2FTeHpLWHRwWmlodUtYSmxkSFZ5YmlCMExtWnNZV2R6SmpJMU5qOG9kQzVtYkdGbmN5WTlMVEkxTnl4eVBYZHZLRVZ5Y205eUtHRW9OREl5S1Nr'
    || 'cExHdHNLR1VzZEN4ekxISXBLVHAwTG0xbGJXOXBlbVZrVTNSaGRHVWhQVDF1ZFd4c1B5aDBMbU5vYVd4a1BXVXVZMmhwYkdRc2RDNW1iR0ZuYzN3OU1USTRM'
    || 'RzUxYkd3cE9paHBQWEl1Wm1Gc2JHSmhZMnNzYkQxMExtMXZaR1VzY2oxVmJDaDdiVzlrWlRvaWRtbHphV0pzWlNJc1kyaHBiR1J5Wlc0NmNpNWphR2xzWkhK'
    || 'bGJuMHNiQ3d3TEc1MWJHd3BMR2s5WjI0b2FTeHNMSE1zYm5Wc2JDa3NhUzVtYkdGbmMzdzlNaXh5TG5KbGRIVnliajEwTEdrdWNtVjBkWEp1UFhRc2NpNXph'
    || 'V0pzYVc1blBXa3NkQzVqYUdsc1pEMXlMQ2gwTG0xdlpHVW1NU2toUFQwd0ppWjZiaWgwTEdVdVkyaHBiR1FzYm5Wc2JDeHpLU3gwTG1Ob2FXeGtMbTFsYlc5'
    || 'cGVtVmtVM1JoZEdVOWFtOG9jeWtzZEM1dFpXMXZhWHBsWkZOMFlYUmxQV3R2TEdrcE8ybG1LQ2gwTG0xdlpHVW1NU2s5UFQwd0tYSmxkSFZ5YmlCcmJDaGxM'
    || 'SFFzY3l4dWRXeHNLVHRwWmloc0xtUmhkR0U5UFQwaUpDRWlLWHRwWmloeVBXd3VibVY0ZEZOcFlteHBibWNtSm13dWJtVjRkRk5wWW14cGJtY3VaR0YwWVhO'
    || 'bGRDeHlLWFpoY2lCalBYSXVaR2R6ZER0eVpYUjFjbTRnY2oxakxHazlSWEp5YjNJb1lTZzBNVGtwS1N4eVBYZHZLR2tzY2l4MmIybGtJREFwTEd0c0tHVXNk'
    || 'Q3h6TEhJcGZXbG1LR005S0hNbVpTNWphR2xzWkV4aGJtVnpLU0U5UFRBc1dHVjhmR01wZTJsbUtISTlWR1VzY2lFOVBXNTFiR3dwZTNOM2FYUmphQ2h6Smkx'
    || 'ektYdGpZWE5sSURRNmJEMHlPMkp5WldGck8yTmhjMlVnTVRZNmJEMDRPMkp5WldGck8yTmhjMlVnTmpRNlkyRnpaU0F4TWpnNlkyRnpaU0F5TlRZNlkyRnpa'
    || 'U0ExTVRJNlkyRnpaU0F4TURJME9tTmhjMlVnTWpBME9EcGpZWE5sSURRd09UWTZZMkZ6WlNBNE1Ua3lPbU5oYzJVZ01UWXpPRFE2WTJGelpTQXpNamMyT0Rw'
    || 'allYTmxJRFkxTlRNMk9tTmhjMlVnTVRNeE1EY3lPbU5oYzJVZ01qWXlNVFEwT21OaGMyVWdOVEkwTWpnNE9tTmhjMlVnTVRBME9EVTNOanBqWVhObElESXdP'
    || 'VGN4TlRJNlkyRnpaU0EwTVRrME16QTBPbU5oYzJVZ09ETTRPRFl3T0RwallYTmxJREUyTnpjM01qRTJPbU5oYzJVZ016TTFOVFEwTXpJNlkyRnpaU0EyTnpF'
    || 'd09EZzJORHBzUFRNeU8ySnlaV0ZyTzJOaGMyVWdOVE0yT0Rjd09URXlPbXc5TWpZNE5ETTFORFUyTzJKeVpXRnJPMlJsWm1GMWJIUTZiRDB3Zld3OUtHd21L'
    || 'SEl1YzNWemNHVnVaR1ZrVEdGdVpYTjhjeWtwSVQwOU1EOHdPbXdzYkNFOVBUQW1KbXdoUFQxcExuSmxkSEo1VEdGdVpTWW1LR2t1Y21WMGNubE1ZVzVsUFd3'
    || 'c1JIUW9aU3hzS1N4VGRDaHlMR1VzYkN3dE1Ta3BmWEpsZEhWeWJpQklieWdwTEhJOWQyOG9SWEp5YjNJb1lTZzBNakVwS1Nrc2Eyd29aU3gwTEhNc2NpbDlj'
    || 'bVYwZFhKdUlHd3VaR0YwWVQwOVBTSWtQeUkvS0hRdVpteGhaM044UFRFeU9DeDBMbU5vYVd4a1BXVXVZMmhwYkdRc2REMXhaaTVpYVc1a0tHNTFiR3dzWlNr'
    || 'c2JDNWZjbVZoWTNSU1pYUnllVDEwTEc1MWJHd3BPaWhsUFdrdWRISmxaVU52Ym5SbGVIUXNiSFE5UW5Rb2JDNXVaWGgwVTJsaWJHbHVaeWtzY25ROWRDeHda'
    || 'VDBoTUN4MmREMXVkV3hzTEdVaFBUMXVkV3hzSmlZb2IzUmJjM1FySzEwOVQzUXNiM1JiYzNRcksxMDlUWFFzYjNSYmMzUXJLMTA5ZFc0c1QzUTlaUzVwWkN4'
    || 'TmREMWxMbTkyWlhKbWJHOTNMSFZ1UFhRcExIUTlRMjhvZEN4eUxtTm9hV3hrY21WdUtTeDBMbVpzWVdkemZEMDBNRGsyTEhRcGZXWjFibU4wYVc5dUlFOWhL'
    || 'R1VzZEN4dUtYdGxMbXhoYm1WemZEMTBPM1poY2lCeVBXVXVZV3gwWlhKdVlYUmxPM0loUFQxdWRXeHNKaVlvY2k1c1lXNWxjM3c5ZENrc2NtOG9aUzV5WlhS'
    || 'MWNtNHNkQ3h1S1gxbWRXNWpkR2x2YmlCVWJ5aGxMSFFzYml4eUxHd3BlM1poY2lCcFBXVXViV1Z0YjJsNlpXUlRkR0YwWlR0cFBUMDliblZzYkQ5bExtMWxi'
    || 'VzlwZW1Wa1UzUmhkR1U5ZTJselFtRmphM2RoY21Sek9uUXNjbVZ1WkdWeWFXNW5PbTUxYkd3c2NtVnVaR1Z5YVc1blUzUmhjblJVYVcxbE9qQXNiR0Z6ZERw'
    || 'eUxIUmhhV3c2Yml4MFlXbHNUVzlrWlRwc2ZUb29hUzVwYzBKaFkydDNZWEprY3oxMExHa3VjbVZ1WkdWeWFXNW5QVzUxYkd3c2FTNXlaVzVrWlhKcGJtZFRk'
    || 'R0Z5ZEZScGJXVTlNQ3hwTG14aGMzUTljaXhwTG5SaGFXdzliaXhwTG5SaGFXeE5iMlJsUFd3cGZXWjFibU4wYVc5dUlFMWhLR1VzZEN4dUtYdDJZWElnY2ox'
    || 'MExuQmxibVJwYm1kUWNtOXdjeXhzUFhJdWNtVjJaV0ZzVDNKa1pYSXNhVDF5TG5SaGFXdzdhV1lvVm1Vb1pTeDBMSEl1WTJocGJHUnlaVzRzYmlrc2NqMW9a'
    || 'UzVqZFhKeVpXNTBMQ2h5SmpJcElUMDlNQ2x5UFhJbU1Yd3lMSFF1Wm14aFozTjhQVEV5T0R0bGJITmxlMmxtS0dVaFBUMXVkV3hzSmlZb1pTNW1iR0ZuY3lZ'
    || 'eE1qZ3BJVDA5TUNsbE9tWnZjaWhsUFhRdVkyaHBiR1E3WlNFOVBXNTFiR3c3S1h0cFppaGxMblJoWnowOVBURXpLV1V1YldWdGIybDZaV1JUZEdGMFpTRTlQ'
    || 'VzUxYkd3bUprOWhLR1VzYml4MEtUdGxiSE5sSUdsbUtHVXVkR0ZuUFQwOU1Ua3BUMkVvWlN4dUxIUXBPMlZzYzJVZ2FXWW9aUzVqYUdsc1pDRTlQVzUxYkd3'
    || 'cGUyVXVZMmhwYkdRdWNtVjBkWEp1UFdVc1pUMWxMbU5vYVd4a08yTnZiblJwYm5WbGZXbG1LR1U5UFQxMEtXSnlaV0ZySUdVN1ptOXlLRHRsTG5OcFlteHBi'
    || 'bWM5UFQxdWRXeHNPeWw3YVdZb1pTNXlaWFIxY200OVBUMXVkV3hzZkh4bExuSmxkSFZ5YmowOVBYUXBZbkpsWVdzZ1pUdGxQV1V1Y21WMGRYSnVmV1V1YzJs'
    || 'aWJHbHVaeTV5WlhSMWNtNDlaUzV5WlhSMWNtNHNaVDFsTG5OcFlteHBibWQ5Y2lZOU1YMXBaaWh6WlNob1pTeHlLU3dvZEM1dGIyUmxKakVwUFQwOU1DbDBM'
    || 'bTFsYlc5cGVtVmtVM1JoZEdVOWJuVnNiRHRsYkhObElITjNhWFJqYUNoc0tYdGpZWE5sSW1admNuZGhjbVJ6SWpwbWIzSW9iajEwTG1Ob2FXeGtMR3c5Ym5W'
    || 'c2JEdHVJVDA5Ym5Wc2JEc3BaVDF1TG1Gc2RHVnlibUYwWlN4bElUMDliblZzYkNZbWVXd29aU2s5UFQxdWRXeHNKaVlvYkQxdUtTeHVQVzR1YzJsaWJHbHVa'
    || 'enR1UFd3c2JqMDlQVzUxYkd3L0tHdzlkQzVqYUdsc1pDeDBMbU5vYVd4a1BXNTFiR3dwT2loc1BXNHVjMmxpYkdsdVp5eHVMbk5wWW14cGJtYzliblZzYkNr'
    || 'c1ZHOG9kQ3doTVN4c0xHNHNhU2s3WW5KbFlXczdZMkZ6WlNKaVlXTnJkMkZ5WkhNaU9tWnZjaWh1UFc1MWJHd3NiRDEwTG1Ob2FXeGtMSFF1WTJocGJHUTli'
    || 'blZzYkR0c0lUMDliblZzYkRzcGUybG1LR1U5YkM1aGJIUmxjbTVoZEdVc1pTRTlQVzUxYkd3bUpubHNLR1VwUFQwOWJuVnNiQ2w3ZEM1amFHbHNaRDFzTzJK'
    || 'eVpXRnJmV1U5YkM1emFXSnNhVzVuTEd3dWMybGliR2x1WnoxdUxHNDliQ3hzUFdWOVZHOG9kQ3doTUN4dUxHNTFiR3dzYVNrN1luSmxZV3M3WTJGelpTSjBi'
    || 'MmRsZEdobGNpSTZWRzhvZEN3aE1TeHVkV3hzTEc1MWJHd3NkbTlwWkNBd0tUdGljbVZoYXp0a1pXWmhkV3gwT25RdWJXVnRiMmw2WldSVGRHRjBaVDF1ZFd4'
    || 'c2ZYSmxkSFZ5YmlCMExtTm9hV3hrZldaMWJtTjBhVzl1SUdwc0tHVXNkQ2w3S0hRdWJXOWtaU1l4S1QwOVBUQW1KbVVoUFQxdWRXeHNKaVlvWlM1aGJIUmxj'
    || 'bTVoZEdVOWJuVnNiQ3gwTG1Gc2RHVnlibUYwWlQxdWRXeHNMSFF1Wm14aFozTjhQVElwZldaMWJtTjBhVzl1SUV4MEtHVXNkQ3h1S1h0cFppaGxJVDA5Ym5W'
    || 'c2JDWW1LSFF1WkdWd1pXNWtaVzVqYVdWelBXVXVaR1Z3Wlc1a1pXNWphV1Z6S1N4d2JudzlkQzVzWVc1bGN5d29iaVowTG1Ob2FXeGtUR0Z1WlhNcFBUMDlN'
    || 'Q2x5WlhSMWNtNGdiblZzYkR0cFppaGxJVDA5Ym5Wc2JDWW1kQzVqYUdsc1pDRTlQV1V1WTJocGJHUXBkR2h5YjNjZ1JYSnliM0lvWVNneE5UTXBLVHRwWmlo'
    || 'MExtTm9hV3hrSVQwOWJuVnNiQ2w3Wm05eUtHVTlkQzVqYUdsc1pDeHVQWFJ1S0dVc1pTNXdaVzVrYVc1blVISnZjSE1wTEhRdVkyaHBiR1E5Yml4dUxuSmxk'
    || 'SFZ5YmoxME8yVXVjMmxpYkdsdVp5RTlQVzUxYkd3N0tXVTlaUzV6YVdKc2FXNW5MRzQ5Ymk1emFXSnNhVzVuUFhSdUtHVXNaUzV3Wlc1a2FXNW5VSEp2Y0hN'
    || 'cExHNHVjbVYwZFhKdVBYUTdiaTV6YVdKc2FXNW5QVzUxYkd4OWNtVjBkWEp1SUhRdVkyaHBiR1I5Wm5WdVkzUnBiMjRnUm1Zb1pTeDBMRzRwZTNOM2FYUmph'
    || 'Q2gwTG5SaFp5bDdZMkZ6WlNBek9rTmhLSFFwTEVGdUtDazdZbkpsWVdzN1kyRnpaU0ExT2xGMUtIUXBPMkp5WldGck8yTmhjMlVnTVRwTFpTaDBMblI1Y0dV'
    || 'cEppWjFiQ2gwS1R0aWNtVmhhenRqWVhObElEUTZiMjhvZEN4MExuTjBZWFJsVG05a1pTNWpiMjUwWVdsdVpYSkpibVp2S1R0aWNtVmhhenRqWVhObElERXdP'
    || 'blpoY2lCeVBYUXVkSGx3WlM1ZlkyOXVkR1Y0ZEN4c1BYUXViV1Z0YjJsNlpXUlFjbTl3Y3k1MllXeDFaVHR6WlNob2JDeHlMbDlqZFhKeVpXNTBWbUZzZFdV'
    || 'cExISXVYMk4xY25KbGJuUldZV3gxWlQxc08ySnlaV0ZyTzJOaGMyVWdNVE02YVdZb2NqMTBMbTFsYlc5cGVtVmtVM1JoZEdVc2NpRTlQVzUxYkd3cGNtVjBk'
    || 'WEp1SUhJdVpHVm9lV1J5WVhSbFpDRTlQVzUxYkd3L0tITmxLR2hsTEdobExtTjFjbkpsYm5RbU1Ta3NkQzVtYkdGbmMzdzlNVEk0TEc1MWJHd3BPaWh1Sm5R'
    || 'dVkyaHBiR1F1WTJocGJHUk1ZVzVsY3lraFBUMHdQMUpoS0dVc2RDeHVLVG9vYzJVb2FHVXNhR1V1WTNWeWNtVnVkQ1l4S1N4bFBVeDBLR1VzZEN4dUtTeGxJ'
    || 'VDA5Ym5Wc2JEOWxMbk5wWW14cGJtYzZiblZzYkNrN2MyVW9hR1VzYUdVdVkzVnljbVZ1ZENZeEtUdGljbVZoYXp0allYTmxJREU1T21sbUtISTlLRzRtZEM1'
    || 'amFHbHNaRXhoYm1WektTRTlQVEFzS0dVdVpteGhaM01tTVRJNEtTRTlQVEFwZTJsbUtISXBjbVYwZFhKdUlFMWhLR1VzZEN4dUtUdDBMbVpzWVdkemZEMHhN'
    || 'amg5YVdZb2JEMTBMbTFsYlc5cGVtVmtVM1JoZEdVc2JDRTlQVzUxYkd3bUppaHNMbkpsYm1SbGNtbHVaejF1ZFd4c0xHd3VkR0ZwYkQxdWRXeHNMR3d1YkdG'
    || 'emRFVm1abVZqZEQxdWRXeHNLU3h6WlNob1pTeG9aUzVqZFhKeVpXNTBLU3h5S1dKeVpXRnJPM0psZEhWeWJpQnVkV3hzTzJOaGMyVWdNakk2WTJGelpTQXlN'
    || 'enB5WlhSMWNtNGdkQzVzWVc1bGN6MHdMRTVoS0dVc2RDeHVLWDF5WlhSMWNtNGdUSFFvWlN4MExHNHBmWFpoY2lCRVlTeFNieXhRWVN4TVlUdEVZVDFtZFc1'
    || 'amRHbHZiaWhsTEhRcGUyWnZjaWgyWVhJZ2JqMTBMbU5vYVd4a08yNGhQVDF1ZFd4c095bDdhV1lvYmk1MFlXYzlQVDAxZkh4dUxuUmhaejA5UFRZcFpTNWhj'
    || 'SEJsYm1SRGFHbHNaQ2h1TG5OMFlYUmxUbTlrWlNrN1pXeHpaU0JwWmlodUxuUmhaeUU5UFRRbUptNHVZMmhwYkdRaFBUMXVkV3hzS1h0dUxtTm9hV3hrTG5K'
    || 'bGRIVnliajF1TEc0OWJpNWphR2xzWkR0amIyNTBhVzUxWlgxcFppaHVQVDA5ZENsaWNtVmhhenRtYjNJb08yNHVjMmxpYkdsdVp6MDlQVzUxYkd3N0tYdHBa'
    || 'aWh1TG5KbGRIVnliajA5UFc1MWJHeDhmRzR1Y21WMGRYSnVQVDA5ZENseVpYUjFjbTQ3YmoxdUxuSmxkSFZ5Ym4xdUxuTnBZbXhwYm1jdWNtVjBkWEp1UFc0'
    || 'dWNtVjBkWEp1TEc0OWJpNXphV0pzYVc1bmZYMHNVbTg5Wm5WdVkzUnBiMjRvS1h0OUxGQmhQV1oxYm1OMGFXOXVLR1VzZEN4dUxISXBlM1poY2lCc1BXVXVi'
    || 'V1Z0YjJsNlpXUlFjbTl3Y3p0cFppaHNJVDA5Y2lsN1pUMTBMbk4wWVhSbFRtOWtaU3hrYmloT2RDNWpkWEp5Wlc1MEtUdDJZWElnYVQxdWRXeHNPM04zYVhS'
    || 'amFDaHVLWHRqWVhObEltbHVjSFYwSWpwc1BYSnBLR1VzYkNrc2NqMXlhU2hsTEhJcExHazlXMTA3WW5KbFlXczdZMkZ6WlNKelpXeGxZM1FpT213OVNTaDdm'
    || 'U3hzTEh0MllXeDFaVHAyYjJsa0lEQjlLU3h5UFVrb2UzMHNjaXg3ZG1Gc2RXVTZkbTlwWkNBd2ZTa3NhVDFiWFR0aWNtVmhhenRqWVhObEluUmxlSFJoY21W'
    || 'aElqcHNQVzlwS0dVc2JDa3NjajF2YVNobExISXBMR2s5VzEwN1luSmxZV3M3WkdWbVlYVnNkRHAwZVhCbGIyWWdiQzV2YmtOc2FXTnJJVDBpWm5WdVkzUnBi'
    || 'MjRpSmlaMGVYQmxiMllnY2k1dmJrTnNhV05yUFQwaVpuVnVZM1JwYjI0aUppWW9aUzV2Ym1Oc2FXTnJQV2xzS1gxMWFTaHVMSElwTzNaaGNpQnpPMjQ5Ym5W'
    || 'c2JEdG1iM0lvZVNCcGJpQnNLV2xtS0NGeUxtaGhjMDkzYmxCeWIzQmxjblI1S0hrcEppWnNMbWhoYzA5M2JsQnliM0JsY25SNUtIa3BKaVpzVzNsZElUMXVk'
    || 'V3hzS1dsbUtIazlQVDBpYzNSNWJHVWlLWHQyWVhJZ1l6MXNXM2xkTzJadmNpaHpJR2x1SUdNcFl5NW9ZWE5QZDI1UWNtOXdaWEowZVNoektTWW1LRzU4ZkNo'
    || 'dVBYdDlLU3h1VzNOZFBTSWlLWDFsYkhObElIa2hQVDBpWkdGdVoyVnliM1Z6YkhsVFpYUkpibTVsY2toVVRVd2lKaVo1SVQwOUltTm9hV3hrY21WdUlpWW1l'
    || 'U0U5UFNKemRYQndjbVZ6YzBOdmJuUmxiblJGWkdsMFlXSnNaVmRoY201cGJtY2lKaVo1SVQwOUluTjFjSEJ5WlhOelNIbGtjbUYwYVc5dVYyRnlibWx1WnlJ'
    || 'bUpua2hQVDBpWVhWMGIwWnZZM1Z6SWlZbUtIZ3VhR0Z6VDNkdVVISnZjR1Z5ZEhrb2VTay9hWHg4S0drOVcxMHBPaWhwUFdsOGZGdGRLUzV3ZFhOb0tIa3Ni'
    || 'blZzYkNrcE8yWnZjaWg1SUdsdUlISXBlM1poY2lCbVBYSmJlVjA3YVdZb1l6MXNJVDF1ZFd4c1AyeGJlVjA2ZG05cFpDQXdMSEl1YUdGelQzZHVVSEp2Y0dW'
    || 'eWRIa29lU2ttSm1ZaFBUMWpKaVlvWmlFOWJuVnNiSHg4WXlFOWJuVnNiQ2twYVdZb2VUMDlQU0p6ZEhsc1pTSXBhV1lvWXlsN1ptOXlLSE1nYVc0Z1l5a2hZ'
    || 'eTVvWVhOUGQyNVFjbTl3WlhKMGVTaHpLWHg4WmlZbVppNW9ZWE5QZDI1UWNtOXdaWEowZVNoektYeDhLRzU4ZkNodVBYdDlLU3h1VzNOZFBTSWlLVHRtYjNJ'
    || 'b2N5QnBiaUJtS1dZdWFHRnpUM2R1VUhKdmNHVnlkSGtvY3lrbUptTmJjMTBoUFQxbVczTmRKaVlvYm54OEtHNDllMzBwTEc1YmMxMDlabHR6WFNsOVpXeHpa'
    || 'U0J1Zkh3b2FYeDhLR2s5VzEwcExHa3VjSFZ6YUNoNUxHNHBLU3h1UFdZN1pXeHpaU0I1UFQwOUltUmhibWRsY205MWMyeDVVMlYwU1c1dVpYSklWRTFNSWo4'
    || 'b1pqMW1QMll1WDE5b2RHMXNPblp2YVdRZ01DeGpQV00vWXk1ZlgyaDBiV3c2ZG05cFpDQXdMR1loUFc1MWJHd21KbU1oUFQxbUppWW9hVDFwZkh4YlhTa3Vj'
    || 'SFZ6YUNoNUxHWXBLVHA1UFQwOUltTm9hV3hrY21WdUlqOTBlWEJsYjJZZ1ppRTlJbk4wY21sdVp5SW1KblI1Y0dWdlppQm1JVDBpYm5WdFltVnlJbng4S0dr'
    || 'OWFYeDhXMTBwTG5CMWMyZ29lU3dpSWl0bUtUcDVJVDA5SW5OMWNIQnlaWE56UTI5dWRHVnVkRVZrYVhSaFlteGxWMkZ5Ym1sdVp5SW1KbmtoUFQwaWMzVndj'
    || 'SEpsYzNOSWVXUnlZWFJwYjI1WFlYSnVhVzVuSWlZbUtIZ3VhR0Z6VDNkdVVISnZjR1Z5ZEhrb2VTay9LR1loUFc1MWJHd21Kbms5UFQwaWIyNVRZM0p2Ykd3'
    || 'aUppWjFaU2dpYzJOeWIyeHNJaXhsS1N4cGZIeGpQVDA5Wm54OEtHazlXMTBwS1Rvb2FUMXBmSHhiWFNrdWNIVnphQ2g1TEdZcEtYMXVKaVlvYVQxcGZIeGJY'
    || 'U2t1Y0hWemFDZ2ljM1I1YkdVaUxHNHBPM1poY2lCNVBXazdLSFF1ZFhCa1lYUmxVWFZsZFdVOWVTa21KaWgwTG1ac1lXZHpmRDAwS1gxOUxFeGhQV1oxYm1O'
    || 'MGFXOXVLR1VzZEN4dUxISXBlMjRoUFQxeUppWW9kQzVtYkdGbmMzdzlOQ2w5TzJaMWJtTjBhVzl1SUZSeUtHVXNkQ2w3YVdZb0lYQmxLWE4zYVhSamFDaGxM'
    || 'blJoYVd4TmIyUmxLWHRqWVhObEltaHBaR1JsYmlJNmREMWxMblJoYVd3N1ptOXlLSFpoY2lCdVBXNTFiR3c3ZENFOVBXNTFiR3c3S1hRdVlXeDBaWEp1WVhS'
    || 'bElUMDliblZzYkNZbUtHNDlkQ2tzZEQxMExuTnBZbXhwYm1jN2JqMDlQVzUxYkd3L1pTNTBZV2xzUFc1MWJHdzZiaTV6YVdKc2FXNW5QVzUxYkd3N1luSmxZ'
    || 'V3M3WTJGelpTSmpiMnhzWVhCelpXUWlPbTQ5WlM1MFlXbHNPMlp2Y2loMllYSWdjajF1ZFd4c08yNGhQVDF1ZFd4c095bHVMbUZzZEdWeWJtRjBaU0U5UFc1'
    || 'MWJHd21KaWh5UFc0cExHNDliaTV6YVdKc2FXNW5PM0k5UFQxdWRXeHNQM1I4ZkdVdWRHRnBiRDA5UFc1MWJHdy9aUzUwWVdsc1BXNTFiR3c2WlM1MFlXbHNM'
    || 'bk5wWW14cGJtYzliblZzYkRweUxuTnBZbXhwYm1jOWJuVnNiSDE5Wm5WdVkzUnBiMjRnZW1Vb1pTbDdkbUZ5SUhROVpTNWhiSFJsY201aGRHVWhQVDF1ZFd4'
    || 'c0ppWmxMbUZzZEdWeWJtRjBaUzVqYUdsc1pEMDlQV1V1WTJocGJHUXNiajB3TEhJOU1EdHBaaWgwS1dadmNpaDJZWElnYkQxbExtTm9hV3hrTzJ3aFBUMXVk'
    || 'V3hzT3lsdWZEMXNMbXhoYm1WemZHd3VZMmhwYkdSTVlXNWxjeXh5ZkQxc0xuTjFZblJ5WldWR2JHRm5jeVl4TkRZNE1EQTJOQ3h5ZkQxc0xtWnNZV2R6SmpF'
    || 'ME5qZ3dNRFkwTEd3dWNtVjBkWEp1UFdVc2JEMXNMbk5wWW14cGJtYzdaV3h6WlNCbWIzSW9iRDFsTG1Ob2FXeGtPMndoUFQxdWRXeHNPeWx1ZkQxc0xteGhi'
    || 'bVZ6Zkd3dVkyaHBiR1JNWVc1bGN5eHlmRDFzTG5OMVluUnlaV1ZHYkdGbmN5eHlmRDFzTG1ac1lXZHpMR3d1Y21WMGRYSnVQV1VzYkQxc0xuTnBZbXhwYm1j'
    || 'N2NtVjBkWEp1SUdVdWMzVmlkSEpsWlVac1lXZHpmRDF5TEdVdVkyaHBiR1JNWVc1bGN6MXVMSFI5Wm5WdVkzUnBiMjRnVjJZb1pTeDBMRzRwZTNaaGNpQnlQ'
    || 'WFF1Y0dWdVpHbHVaMUJ5YjNCek8zTjNhWFJqYUNoYWFTaDBLU3gwTG5SaFp5bDdZMkZ6WlNBeU9tTmhjMlVnTVRZNlkyRnpaU0F4TlRwallYTmxJREE2WTJG'
    || 'elpTQXhNVHBqWVhObElEYzZZMkZ6WlNBNE9tTmhjMlVnTVRJNlkyRnpaU0E1T21OaGMyVWdNVFE2Y21WMGRYSnVJSHBsS0hRcExHNTFiR3c3WTJGelpTQXhP'
    || 'bkpsZEhWeWJpQkxaU2gwTG5SNWNHVXBKaVp6YkNncExIcGxLSFFwTEc1MWJHdzdZMkZ6WlNBek9uSmxkSFZ5YmlCeVBYUXVjM1JoZEdWT2IyUmxMRmR1S0Nr'
    || 'c1lXVW9XV1VwTEdGbEtFbGxLU3hoYnlncExISXVjR1Z1WkdsdVowTnZiblJsZUhRbUppaHlMbU52Ym5SbGVIUTljaTV3Wlc1a2FXNW5RMjl1ZEdWNGRDeHlM'
    || 'bkJsYm1ScGJtZERiMjUwWlhoMFBXNTFiR3dwTENobFBUMDliblZzYkh4OFpTNWphR2xzWkQwOVBXNTFiR3dwSmlZb1ptd29kQ2svZEM1bWJHRm5jM3c5TkRw'
    || 'bFBUMDliblZzYkh4OFpTNXRaVzF2YVhwbFpGTjBZWFJsTG1selJHVm9lV1J5WVhSbFpDWW1LSFF1Wm14aFozTW1NalUyS1QwOVBUQjhmQ2gwTG1ac1lXZHpm'
    || 'RDB4TURJMExIWjBJVDA5Ym5Wc2JDWW1LRmR2S0haMEtTeDJkRDF1ZFd4c0tTa3BMRkp2S0dVc2RDa3NlbVVvZENrc2JuVnNiRHRqWVhObElEVTZjMjhvZENr'
    || 'N2RtRnlJR3c5Wkc0b1JYSXVZM1Z5Y21WdWRDazdhV1lvYmoxMExuUjVjR1VzWlNFOVBXNTFiR3dtSm5RdWMzUmhkR1ZPYjJSbElUMXVkV3hzS1ZCaEtHVXNk'
    || 'Q3h1TEhJc2JDa3NaUzV5WldZaFBUMTBMbkpsWmlZbUtIUXVabXhoWjNOOFBUVXhNaXgwTG1ac1lXZHpmRDB5TURrM01UVXlLVHRsYkhObGUybG1LQ0Z5S1h0'
    || 'cFppaDBMbk4wWVhSbFRtOWtaVDA5UFc1MWJHd3BkR2h5YjNjZ1JYSnliM0lvWVNneE5qWXBLVHR5WlhSMWNtNGdlbVVvZENrc2JuVnNiSDFwWmlobFBXUnVL'
    || 'RTUwTG1OMWNuSmxiblFwTEdac0tIUXBLWHR5UFhRdWMzUmhkR1ZPYjJSbExHNDlkQzUwZVhCbE8zWmhjaUJwUFhRdWJXVnRiMmw2WldSUWNtOXdjenR6ZDJs'
    || 'MFkyZ29jbHRGZEYwOWRDeHlXM2x5WFQxcExHVTlLSFF1Ylc5a1pTWXhLU0U5UFRBc2JpbDdZMkZ6WlNKa2FXRnNiMmNpT25WbEtDSmpZVzVqWld3aUxISXBM'
    || 'SFZsS0NKamJHOXpaU0lzY2lrN1luSmxZV3M3WTJGelpTSnBabkpoYldVaU9tTmhjMlVpYjJKcVpXTjBJanBqWVhObEltVnRZbVZrSWpwMVpTZ2liRzloWkNJ'
    || 'c2NpazdZbkpsWVdzN1kyRnpaU0oyYVdSbGJ5STZZMkZ6WlNKaGRXUnBieUk2Wm05eUtHdzlNRHRzUEcxeUxteGxibWQwYUR0c0t5c3BkV1VvYlhKYmJGMHNj'
    || 'aWs3WW5KbFlXczdZMkZ6WlNKemIzVnlZMlVpT25WbEtDSmxjbkp2Y2lJc2NpazdZbkpsWVdzN1kyRnpaU0pwYldjaU9tTmhjMlVpYVcxaFoyVWlPbU5oYzJV'
    || 'aWJHbHVheUk2ZFdVb0ltVnljbTl5SWl4eUtTeDFaU2dpYkc5aFpDSXNjaWs3WW5KbFlXczdZMkZ6WlNKa1pYUmhhV3h6SWpwMVpTZ2lkRzluWjJ4bElpeHlL'
    || 'VHRpY21WaGF6dGpZWE5sSW1sdWNIVjBJanBvY3loeUxHa3BMSFZsS0NKcGJuWmhiR2xrSWl4eUtUdGljbVZoYXp0allYTmxJbk5sYkdWamRDSTZjaTVmZDNK'
    || 'aGNIQmxjbE4wWVhSbFBYdDNZWE5OZFd4MGFYQnNaVG9oSVdrdWJYVnNkR2x3YkdWOUxIVmxLQ0pwYm5aaGJHbGtJaXh5S1R0aWNtVmhhenRqWVhObEluUmxl'
    || 'SFJoY21WaElqcG5jeWh5TEdrcExIVmxLQ0pwYm5aaGJHbGtJaXh5S1gxMWFTaHVMR2twTEd3OWJuVnNiRHRtYjNJb2RtRnlJSE1nYVc0Z2FTbHBaaWhwTG1o'
    || 'aGMwOTNibEJ5YjNCbGNuUjVLSE1wS1h0MllYSWdZejFwVzNOZE8zTTlQVDBpWTJocGJHUnlaVzRpUDNSNWNHVnZaaUJqUFQwaWMzUnlhVzVuSWo5eUxuUmxl'
    || 'SFJEYjI1MFpXNTBJVDA5WXlZbUtHa3VjM1Z3Y0hKbGMzTkllV1J5WVhScGIyNVhZWEp1YVc1bklUMDlJVEFtSm14c0tISXVkR1Y0ZEVOdmJuUmxiblFzWXl4'
    || 'bEtTeHNQVnNpWTJocGJHUnlaVzRpTEdOZEtUcDBlWEJsYjJZZ1l6MDlJbTUxYldKbGNpSW1Kbkl1ZEdWNGRFTnZiblJsYm5RaFBUMGlJaXRqSmlZb2FTNXpk'
    || 'WEJ3Y21WemMwaDVaSEpoZEdsdmJsZGhjbTVwYm1jaFBUMGhNQ1ltYkd3b2NpNTBaWGgwUTI5dWRHVnVkQ3hqTEdVcExHdzlXeUpqYUdsc1pISmxiaUlzSWlJ'
    || 'clkxMHBPbmd1YUdGelQzZHVVSEp2Y0dWeWRIa29jeWttSm1NaFBXNTFiR3dtSm5NOVBUMGliMjVUWTNKdmJHd2lKaVoxWlNnaWMyTnliMnhzSWl4eUtYMXpk'
    || 'MmwwWTJnb2JpbDdZMkZ6WlNKcGJuQjFkQ0k2U1hJb2Npa3Nkbk1vY2l4cExDRXdLVHRpY21WaGF6dGpZWE5sSW5SbGVIUmhjbVZoSWpwSmNpaHlLU3g0Y3lo'
    || 'eUtUdGljbVZoYXp0allYTmxJbk5sYkdWamRDSTZZMkZ6WlNKdmNIUnBiMjRpT21KeVpXRnJPMlJsWm1GMWJIUTZkSGx3Wlc5bUlHa3ViMjVEYkdsamF6MDlJ'
    || 'bVoxYm1OMGFXOXVJaVltS0hJdWIyNWpiR2xqYXoxcGJDbDljajFzTEhRdWRYQmtZWFJsVVhWbGRXVTljaXh5SVQwOWJuVnNiQ1ltS0hRdVpteGhaM044UFRR'
    || 'cGZXVnNjMlY3Y3oxc0xtNXZaR1ZVZVhCbFBUMDlPVDlzT213dWIzZHVaWEpFYjJOMWJXVnVkQ3hsUFQwOUltaDBkSEE2THk5M2QzY3Vkek11YjNKbkx6RTVP'
    || 'VGt2ZUdoMGJXd2lKaVlvWlQxVGN5aHVLU2tzWlQwOVBTSm9kSFJ3T2k4dmQzZDNMbmN6TG05eVp5OHhPVGs1TDNob2RHMXNJajl1UFQwOUluTmpjbWx3ZENJ'
    || 'L0tHVTljeTVqY21WaGRHVkZiR1Z0Wlc1MEtDSmthWFlpS1N4bExtbHVibVZ5U0ZSTlREMGlQSE5qY21sd2RENDhYQzl6WTNKcGNIUStJaXhsUFdVdWNtVnRi'
    || 'M1psUTJocGJHUW9aUzVtYVhKemRFTm9hV3hrS1NrNmRIbHdaVzltSUhJdWFYTTlQU0p6ZEhKcGJtY2lQMlU5Y3k1amNtVmhkR1ZGYkdWdFpXNTBLRzRzZTJs'
    || 'ek9uSXVhWE45S1Rvb1pUMXpMbU55WldGMFpVVnNaVzFsYm5Rb2Jpa3NiajA5UFNKelpXeGxZM1FpSmlZb2N6MWxMSEl1YlhWc2RHbHdiR1UvY3k1dGRXeDBh'
    || 'WEJzWlQwaE1EcHlMbk5wZW1VbUppaHpMbk5wZW1VOWNpNXphWHBsS1NrcE9tVTljeTVqY21WaGRHVkZiR1Z0Wlc1MFRsTW9aU3h1S1N4bFcwVjBYVDEwTEdW'
    || 'YmVYSmRQWElzUkdFb1pTeDBMQ0V4TENFeEtTeDBMbk4wWVhSbFRtOWtaVDFsTzJVNmUzTjNhWFJqYUNoelBXRnBLRzRzY2lrc2JpbDdZMkZ6WlNKa2FXRnNi'
    || 'MmNpT25WbEtDSmpZVzVqWld3aUxHVXBMSFZsS0NKamJHOXpaU0lzWlNrc2JEMXlPMkp5WldGck8yTmhjMlVpYVdaeVlXMWxJanBqWVhObEltOWlhbVZqZENJ'
    || 'NlkyRnpaU0psYldKbFpDSTZkV1VvSW14dllXUWlMR1VwTEd3OWNqdGljbVZoYXp0allYTmxJblpwWkdWdklqcGpZWE5sSW1GMVpHbHZJanBtYjNJb2JEMHdP'
    || 'Mnc4YlhJdWJHVnVaM1JvTzJ3ckt5bDFaU2h0Y2x0c1hTeGxLVHRzUFhJN1luSmxZV3M3WTJGelpTSnpiM1Z5WTJVaU9uVmxLQ0psY25KdmNpSXNaU2tzYkQx'
    || 'eU8ySnlaV0ZyTzJOaGMyVWlhVzFuSWpwallYTmxJbWx0WVdkbElqcGpZWE5sSW14cGJtc2lPblZsS0NKbGNuSnZjaUlzWlNrc2RXVW9JbXh2WVdRaUxHVXBM'
    || 'R3c5Y2p0aWNtVmhhenRqWVhObEltUmxkR0ZwYkhNaU9uVmxLQ0owYjJkbmJHVWlMR1VwTEd3OWNqdGljbVZoYXp0allYTmxJbWx1Y0hWMElqcG9jeWhsTEhJ'
    || 'cExHdzljbWtvWlN4eUtTeDFaU2dpYVc1MllXeHBaQ0lzWlNrN1luSmxZV3M3WTJGelpTSnZjSFJwYjI0aU9tdzljanRpY21WaGF6dGpZWE5sSW5ObGJHVmpk'
    || 'Q0k2WlM1ZmQzSmhjSEJsY2xOMFlYUmxQWHQzWVhOTmRXeDBhWEJzWlRvaElYSXViWFZzZEdsd2JHVjlMR3c5U1NoN2ZTeHlMSHQyWVd4MVpUcDJiMmxrSURC'
    || 'OUtTeDFaU2dpYVc1MllXeHBaQ0lzWlNrN1luSmxZV3M3WTJGelpTSjBaWGgwWVhKbFlTSTZaM01vWlN4eUtTeHNQVzlwS0dVc2Npa3NkV1VvSW1sdWRtRnNh'
    || 'V1FpTEdVcE8ySnlaV0ZyTzJSbFptRjFiSFE2YkQxeWZYVnBLRzRzYkNrc1l6MXNPMlp2Y2locElHbHVJR01wYVdZb1l5NW9ZWE5QZDI1UWNtOXdaWEowZVNo'
    || 'cEtTbDdkbUZ5SUdZOVkxdHBYVHRwUFQwOUluTjBlV3hsSWo5RmN5aGxMR1lwT21rOVBUMGlaR0Z1WjJWeWIzVnpiSGxUWlhSSmJtNWxja2hVVFV3aVB5aG1Q'
    || 'V1kvWmk1ZlgyaDBiV3c2ZG05cFpDQXdMR1loUFc1MWJHd21KbmR6S0dVc1ppa3BPbWs5UFQwaVkyaHBiR1J5Wlc0aVAzUjVjR1Z2WmlCbVBUMGljM1J5YVc1'
    || 'bklqOG9iaUU5UFNKMFpYaDBZWEpsWVNKOGZHWWhQVDBpSWlrbUpscHVLR1VzWmlrNmRIbHdaVzltSUdZOVBTSnVkVzFpWlhJaUppWmFiaWhsTENJaUsyWXBP'
    || 'bWtoUFQwaWMzVndjSEpsYzNORGIyNTBaVzUwUldScGRHRmliR1ZYWVhKdWFXNW5JaVltYVNFOVBTSnpkWEJ3Y21WemMwaDVaSEpoZEdsdmJsZGhjbTVwYm1j'
    || 'aUppWnBJVDA5SW1GMWRHOUdiMk4xY3lJbUppaDRMbWhoYzA5M2JsQnliM0JsY25SNUtHa3BQMlloUFc1MWJHd21KbWs5UFQwaWIyNVRZM0p2Ykd3aUppWjFa'
    || 'U2dpYzJOeWIyeHNJaXhsS1RwbUlUMXVkV3hzSmlacVpTaGxMR2tzWml4ektTbDljM2RwZEdOb0tHNHBlMk5oYzJVaWFXNXdkWFFpT2tseUtHVXBMSFp6S0dV'
    || 'c2Npd2hNU2s3WW5KbFlXczdZMkZ6WlNKMFpYaDBZWEpsWVNJNlNYSW9aU2tzZUhNb1pTazdZbkpsWVdzN1kyRnpaU0p2Y0hScGIyNGlPbkl1ZG1Gc2RXVWhQ'
    || 'VzUxYkd3bUptVXVjMlYwUVhSMGNtbGlkWFJsS0NKMllXeDFaU0lzSWlJcmJHVW9jaTUyWVd4MVpTa3BPMkp5WldGck8yTmhjMlVpYzJWc1pXTjBJanBsTG0x'
    || 'MWJIUnBjR3hsUFNFaGNpNXRkV3gwYVhCc1pTeHBQWEl1ZG1Gc2RXVXNhU0U5Ym5Wc2JEOTNiaWhsTENFaGNpNXRkV3gwYVhCc1pTeHBMQ0V4S1RweUxtUmxa'
    || 'bUYxYkhSV1lXeDFaU0U5Ym5Wc2JDWW1kMjRvWlN3aElYSXViWFZzZEdsd2JHVXNjaTVrWldaaGRXeDBWbUZzZFdVc0lUQXBPMkp5WldGck8yUmxabUYxYkhR'
    || 'NmRIbHdaVzltSUd3dWIyNURiR2xqYXowOUltWjFibU4wYVc5dUlpWW1LR1V1YjI1amJHbGphejFwYkNsOWMzZHBkR05vS0c0cGUyTmhjMlVpWW5WMGRHOXVJ'
    || 'anBqWVhObEltbHVjSFYwSWpwallYTmxJbk5sYkdWamRDSTZZMkZ6WlNKMFpYaDBZWEpsWVNJNmNqMGhJWEl1WVhWMGIwWnZZM1Z6TzJKeVpXRnJJR1U3WTJG'
    || 'elpTSnBiV2NpT25JOUlUQTdZbkpsWVdzZ1pUdGtaV1poZFd4ME9uSTlJVEY5ZlhJbUppaDBMbVpzWVdkemZEMDBLWDEwTG5KbFppRTlQVzUxYkd3bUppaDBM'
    || 'bVpzWVdkemZEMDFNVElzZEM1bWJHRm5jM3c5TWpBNU56RTFNaWw5Y21WMGRYSnVJSHBsS0hRcExHNTFiR3c3WTJGelpTQTJPbWxtS0dVbUpuUXVjM1JoZEdW'
    || 'T2IyUmxJVDF1ZFd4c0tVeGhLR1VzZEN4bExtMWxiVzlwZW1Wa1VISnZjSE1zY2lrN1pXeHpaWHRwWmloMGVYQmxiMllnY2lFOUluTjBjbWx1WnlJbUpuUXVj'
    || 'M1JoZEdWT2IyUmxQVDA5Ym5Wc2JDbDBhSEp2ZHlCRmNuSnZjaWhoS0RFMk5pa3BPMmxtS0c0OVpHNG9SWEl1WTNWeWNtVnVkQ2tzWkc0b1RuUXVZM1Z5Y21W'
    || 'dWRDa3NabXdvZENrcGUybG1LSEk5ZEM1emRHRjBaVTV2WkdVc2JqMTBMbTFsYlc5cGVtVmtVSEp2Y0hNc2NsdEZkRjA5ZEN3b2FUMXlMbTV2WkdWV1lXeDFa'
    || 'U0U5UFc0cEppWW9aVDF5ZEN4bElUMDliblZzYkNrcGMzZHBkR05vS0dVdWRHRm5LWHRqWVhObElETTZiR3dvY2k1dWIyUmxWbUZzZFdVc2Jpd29aUzV0YjJS'
    || 'bEpqRXBJVDA5TUNrN1luSmxZV3M3WTJGelpTQTFPbVV1YldWdGIybDZaV1JRY205d2N5NXpkWEJ3Y21WemMwaDVaSEpoZEdsdmJsZGhjbTVwYm1jaFBUMGhN'
    || 'Q1ltYkd3b2NpNXViMlJsVm1Gc2RXVXNiaXdvWlM1dGIyUmxKakVwSVQwOU1DbDlhU1ltS0hRdVpteGhaM044UFRRcGZXVnNjMlVnY2owb2JpNXViMlJsVkhs'
    || 'd1pUMDlQVGsvYmpwdUxtOTNibVZ5Ukc5amRXMWxiblFwTG1OeVpXRjBaVlJsZUhST2IyUmxLSElwTEhKYlJYUmRQWFFzZEM1emRHRjBaVTV2WkdVOWNuMXla'
    || 'WFIxY200Z2VtVW9kQ2tzYm5Wc2JEdGpZWE5sSURFek9tbG1LR0ZsS0dobEtTeHlQWFF1YldWdGIybDZaV1JUZEdGMFpTeGxQVDA5Ym5Wc2JIeDhaUzV0Wlcx'
    || 'dmFYcGxaRk4wWVhSbElUMDliblZzYkNZbVpTNXRaVzF2YVhwbFpGTjBZWFJsTG1SbGFIbGtjbUYwWldRaFBUMXVkV3hzS1h0cFppaHdaU1ltYkhRaFBUMXVk'
    || 'V3hzSmlZb2RDNXRiMlJsSmpFcElUMDlNQ1ltS0hRdVpteGhaM01tTVRJNEtUMDlQVEFwZW5Vb0tTeEJiaWdwTEhRdVpteGhaM044UFRrNE5UWXdMR2s5SVRF'
    || 'N1pXeHpaU0JwWmlocFBXWnNLSFFwTEhJaFBUMXVkV3hzSmlaeUxtUmxhSGxrY21GMFpXUWhQVDF1ZFd4c0tYdHBaaWhsUFQwOWJuVnNiQ2w3YVdZb0lXa3Bk'
    || 'R2h5YjNjZ1JYSnliM0lvWVNnek1UZ3BLVHRwWmlocFBYUXViV1Z0YjJsNlpXUlRkR0YwWlN4cFBXa2hQVDF1ZFd4c1Aya3VaR1ZvZVdSeVlYUmxaRHB1ZFd4'
    || 'c0xDRnBLWFJvY205M0lFVnljbTl5S0dFb016RTNLU2s3YVZ0RmRGMDlkSDFsYkhObElFRnVLQ2tzS0hRdVpteGhaM01tTVRJNEtUMDlQVEFtSmloMExtMWxi'
    || 'VzlwZW1Wa1UzUmhkR1U5Ym5Wc2JDa3NkQzVtYkdGbmMzdzlORHQ2WlNoMEtTeHBQU0V4ZldWc2MyVWdkblFoUFQxdWRXeHNKaVlvVjI4b2RuUXBMSFowUFc1'
    || 'MWJHd3BMR2s5SVRBN2FXWW9JV2twY21WMGRYSnVJSFF1Wm14aFozTW1OalUxTXpZL2REcHVkV3hzZlhKbGRIVnliaWgwTG1ac1lXZHpKakV5T0NraFBUMHdQ'
    || 'eWgwTG14aGJtVnpQVzRzZENrNktISTljaUU5UFc1MWJHd3NjaUU5UFNobElUMDliblZzYkNZbVpTNXRaVzF2YVhwbFpGTjBZWFJsSVQwOWJuVnNiQ2ttSm5J'
    || 'bUppaDBMbU5vYVd4a0xtWnNZV2R6ZkQwNE1Ua3lMQ2gwTG0xdlpHVW1NU2toUFQwd0ppWW9aVDA5UFc1MWJHeDhmQ2hvWlM1amRYSnlaVzUwSmpFcElUMDlN'
    || 'RDlPWlQwOVBUQW1KaWhPWlQwektUcElieWdwS1Nrc2RDNTFjR1JoZEdWUmRXVjFaU0U5UFc1MWJHd21KaWgwTG1ac1lXZHpmRDAwS1N4NlpTaDBLU3h1ZFd4'
    || 'c0tUdGpZWE5sSURRNmNtVjBkWEp1SUZkdUtDa3NVbThvWlN4MEtTeGxQVDA5Ym5Wc2JDWW1kbklvZEM1emRHRjBaVTV2WkdVdVkyOXVkR0ZwYm1WeVNXNW1i'
    || 'eWtzZW1Vb2RDa3NiblZzYkR0allYTmxJREV3T25KbGRIVnliaUJ1YnloMExuUjVjR1V1WDJOdmJuUmxlSFFwTEhwbEtIUXBMRzUxYkd3N1kyRnpaU0F4Tnpw'
    || 'eVpYUjFjbTRnUzJVb2RDNTBlWEJsS1NZbWMyd29LU3g2WlNoMEtTeHVkV3hzTzJOaGMyVWdNVGs2YVdZb1lXVW9hR1VwTEdrOWRDNXRaVzF2YVhwbFpGTjBZ'
    || 'WFJsTEdrOVBUMXVkV3hzS1hKbGRIVnliaUI2WlNoMEtTeHVkV3hzTzJsbUtISTlLSFF1Wm14aFozTW1NVEk0S1NFOVBUQXNjejFwTG5KbGJtUmxjbWx1Wnl4'
    || 'elBUMDliblZzYkNscFppaHlLVlJ5S0drc0lURXBPMlZzYzJWN2FXWW9UbVVoUFQwd2ZIeGxJVDA5Ym5Wc2JDWW1LR1V1Wm14aFozTW1NVEk0S1NFOVBUQXBa'
    || 'bTl5S0dVOWRDNWphR2xzWkR0bElUMDliblZzYkRzcGUybG1LSE05ZVd3b1pTa3NjeUU5UFc1MWJHd3BlMlp2Y2loMExtWnNZV2R6ZkQweE1qZ3NWSElvYVN3'
    || 'aE1Ta3NjajF6TG5Wd1pHRjBaVkYxWlhWbExISWhQVDF1ZFd4c0ppWW9kQzUxY0dSaGRHVlJkV1YxWlQxeUxIUXVabXhoWjNOOFBUUXBMSFF1YzNWaWRISmxa'
    || 'VVpzWVdkelBUQXNjajF1TEc0OWRDNWphR2xzWkR0dUlUMDliblZzYkRzcGFUMXVMR1U5Y2l4cExtWnNZV2R6SmoweE5EWTRNREEyTml4elBXa3VZV3gwWlhK'
    || 'dVlYUmxMSE05UFQxdWRXeHNQeWhwTG1Ob2FXeGtUR0Z1WlhNOU1DeHBMbXhoYm1WelBXVXNhUzVqYUdsc1pEMXVkV3hzTEdrdWMzVmlkSEpsWlVac1lXZHpQ'
    || 'VEFzYVM1dFpXMXZhWHBsWkZCeWIzQnpQVzUxYkd3c2FTNXRaVzF2YVhwbFpGTjBZWFJsUFc1MWJHd3NhUzUxY0dSaGRHVlJkV1YxWlQxdWRXeHNMR2t1WkdW'
    || 'd1pXNWtaVzVqYVdWelBXNTFiR3dzYVM1emRHRjBaVTV2WkdVOWJuVnNiQ2s2S0drdVkyaHBiR1JNWVc1bGN6MXpMbU5vYVd4a1RHRnVaWE1zYVM1c1lXNWxj'
    || 'ejF6TG14aGJtVnpMR2t1WTJocGJHUTljeTVqYUdsc1pDeHBMbk4xWW5SeVpXVkdiR0ZuY3owd0xHa3VaR1ZzWlhScGIyNXpQVzUxYkd3c2FTNXRaVzF2YVhw'
    || 'bFpGQnliM0J6UFhNdWJXVnRiMmw2WldSUWNtOXdjeXhwTG0xbGJXOXBlbVZrVTNSaGRHVTljeTV0WlcxdmFYcGxaRk4wWVhSbExHa3VkWEJrWVhSbFVYVmxk'
    || 'V1U5Y3k1MWNHUmhkR1ZSZFdWMVpTeHBMblI1Y0dVOWN5NTBlWEJsTEdVOWN5NWtaWEJsYm1SbGJtTnBaWE1zYVM1a1pYQmxibVJsYm1OcFpYTTlaVDA5UFc1'
    || 'MWJHdy9iblZzYkRwN2JHRnVaWE02WlM1c1lXNWxjeXhtYVhKemRFTnZiblJsZUhRNlpTNW1hWEp6ZEVOdmJuUmxlSFI5S1N4dVBXNHVjMmxpYkdsdVp6dHla'
    || 'WFIxY200Z2MyVW9hR1VzYUdVdVkzVnljbVZ1ZENZeGZESXBMSFF1WTJocGJHUjlaVDFsTG5OcFlteHBibWQ5YVM1MFlXbHNJVDA5Ym5Wc2JDWW1VMlVvS1Q1'
    || 'Q2JpWW1LSFF1Wm14aFozTjhQVEV5T0N4eVBTRXdMRlJ5S0drc0lURXBMSFF1YkdGdVpYTTlOREU1TkRNd05DbDlaV3h6Wlh0cFppZ2hjaWxwWmlobFBYbHNL'
    || 'SE1wTEdVaFBUMXVkV3hzS1h0cFppaDBMbVpzWVdkemZEMHhNamdzY2owaE1DeHVQV1V1ZFhCa1lYUmxVWFZsZFdVc2JpRTlQVzUxYkd3bUppaDBMblZ3WkdG'
    || 'MFpWRjFaWFZsUFc0c2RDNW1iR0ZuYzN3OU5Da3NWSElvYVN3aE1Da3NhUzUwWVdsc1BUMDliblZzYkNZbWFTNTBZV2xzVFc5a1pUMDlQU0pvYVdSa1pXNGlK'
    || 'aVloY3k1aGJIUmxjbTVoZEdVbUppRndaU2x5WlhSMWNtNGdlbVVvZENrc2JuVnNiSDFsYkhObElESXFVMlVvS1MxcExuSmxibVJsY21sdVoxTjBZWEowVkds'
    || 'dFpUNUNiaVltYmlFOVBURXdOek0zTkRFNE1qUW1KaWgwTG1ac1lXZHpmRDB4TWpnc2NqMGhNQ3hVY2locExDRXhLU3gwTG14aGJtVnpQVFF4T1RRek1EUXBP'
    || 'Mmt1YVhOQ1lXTnJkMkZ5WkhNL0tITXVjMmxpYkdsdVp6MTBMbU5vYVd4a0xIUXVZMmhwYkdROWN5azZLRzQ5YVM1c1lYTjBMRzRoUFQxdWRXeHNQMjR1YzJs'
    || 'aWJHbHVaejF6T25RdVkyaHBiR1E5Y3l4cExteGhjM1E5Y3lsOWNtVjBkWEp1SUdrdWRHRnBiQ0U5UFc1MWJHdy9LSFE5YVM1MFlXbHNMR2t1Y21WdVpHVnlh'
    || 'VzVuUFhRc2FTNTBZV2xzUFhRdWMybGliR2x1Wnl4cExuSmxibVJsY21sdVoxTjBZWEowVkdsdFpUMVRaU2dwTEhRdWMybGliR2x1WnoxdWRXeHNMRzQ5YUdV'
    || 'dVkzVnljbVZ1ZEN4elpTaG9aU3h5UDI0bU1Yd3lPbTRtTVNrc2RDazZLSHBsS0hRcExHNTFiR3dwTzJOaGMyVWdNakk2WTJGelpTQXlNenB5WlhSMWNtNGdW'
    || 'bThvS1N4eVBYUXViV1Z0YjJsNlpXUlRkR0YwWlNFOVBXNTFiR3dzWlNFOVBXNTFiR3dtSm1VdWJXVnRiMmw2WldSVGRHRjBaU0U5UFc1MWJHd2hQVDF5SmlZ'
    || 'b2RDNW1iR0ZuYzN3OU9ERTVNaWtzY2lZbUtIUXViVzlrWlNZeEtTRTlQVEEvS0dsMEpqRXdOek0zTkRFNE1qUXBJVDA5TUNZbUtIcGxLSFFwTEhRdWMzVmlk'
    || 'SEpsWlVac1lXZHpKalltSmloMExtWnNZV2R6ZkQwNE1Ua3lLU2s2ZW1Vb2RDa3NiblZzYkR0allYTmxJREkwT25KbGRIVnliaUJ1ZFd4c08yTmhjMlVnTWpV'
    || 'NmNtVjBkWEp1SUc1MWJHeDlkR2h5YjNjZ1JYSnliM0lvWVNneE5UWXNkQzUwWVdjcEtYMW1kVzVqZEdsdmJpQWtaaWhsTEhRcGUzTjNhWFJqYUNoYWFTaDBL'
    || 'U3gwTG5SaFp5bDdZMkZ6WlNBeE9uSmxkSFZ5YmlCTFpTaDBMblI1Y0dVcEppWnpiQ2dwTEdVOWRDNW1iR0ZuY3l4bEpqWTFOVE0yUHloMExtWnNZV2R6UFdV'
    || 'bUxUWTFOVE0zZkRFeU9DeDBLVHB1ZFd4c08yTmhjMlVnTXpweVpYUjFjbTRnVjI0b0tTeGhaU2haWlNrc1lXVW9TV1VwTEdGdktDa3NaVDEwTG1ac1lXZHpM'
    || 'Q2hsSmpZMU5UTTJLU0U5UFRBbUppaGxKakV5T0NrOVBUMHdQeWgwTG1ac1lXZHpQV1VtTFRZMU5UTTNmREV5T0N4MEtUcHVkV3hzTzJOaGMyVWdOVHB5WlhS'
    || 'MWNtNGdjMjhvZENrc2JuVnNiRHRqWVhObElERXpPbWxtS0dGbEtHaGxLU3hsUFhRdWJXVnRiMmw2WldSVGRHRjBaU3hsSVQwOWJuVnNiQ1ltWlM1a1pXaDVa'
    || 'SEpoZEdWa0lUMDliblZzYkNsN2FXWW9kQzVoYkhSbGNtNWhkR1U5UFQxdWRXeHNLWFJvY205M0lFVnljbTl5S0dFb016UXdLU2s3UVc0b0tYMXlaWFIxY200'
    || 'Z1pUMTBMbVpzWVdkekxHVW1OalUxTXpZL0tIUXVabXhoWjNNOVpTWXROalUxTXpkOE1USTRMSFFwT201MWJHdzdZMkZ6WlNBeE9UcHlaWFIxY200Z1lXVW9h'
    || 'R1VwTEc1MWJHdzdZMkZ6WlNBME9uSmxkSFZ5YmlCWGJpZ3BMRzUxYkd3N1kyRnpaU0F4TURweVpYUjFjbTRnYm04b2RDNTBlWEJsTGw5amIyNTBaWGgwS1N4'
    || 'dWRXeHNPMk5oYzJVZ01qSTZZMkZ6WlNBeU16cHlaWFIxY200Z1ZtOG9LU3h1ZFd4c08yTmhjMlVnTWpRNmNtVjBkWEp1SUc1MWJHdzdaR1ZtWVhWc2REcHla'
    || 'WFIxY200Z2JuVnNiSDE5ZG1GeUlFTnNQU0V4TEZWbFBTRXhMRlptUFhSNWNHVnZaaUJYWldGclUyVjBQVDBpWm5WdVkzUnBiMjRpUDFkbFlXdFRaWFE2VTJW'
    || 'MExGQTliblZzYkR0bWRXNWpkR2x2YmlCV2JpaGxMSFFwZTNaaGNpQnVQV1V1Y21WbU8ybG1LRzRoUFQxdWRXeHNLV2xtS0hSNWNHVnZaaUJ1UFQwaVpuVnVZ'
    || 'M1JwYjI0aUtYUnllWHR1S0c1MWJHd3BmV05oZEdOb0tISXBlM2xsS0dVc2RDeHlLWDFsYkhObElHNHVZM1Z5Y21WdWREMXVkV3hzZldaMWJtTjBhVzl1SUU5'
    || 'dktHVXNkQ3h1S1h0MGNubDdiaWdwZldOaGRHTm9LSElwZTNsbEtHVXNkQ3h5S1gxOWRtRnlJRWxoUFNFeE8yWjFibU4wYVc5dUlFaG1LR1VzZENsN2FXWW9K'
    || 'R2s5V1hJc1pUMXdkU2dwTEZCcEtHVXBLWHRwWmlnaWMyVnNaV04wYVc5dVUzUmhjblFpYVc0Z1pTbDJZWElnYmoxN2MzUmhjblE2WlM1elpXeGxZM1JwYjI1'
    || 'VGRHRnlkQ3hsYm1RNlpTNXpaV3hsWTNScGIyNUZibVI5TzJWc2MyVWdaVHA3Ymowb2JqMWxMbTkzYm1WeVJHOWpkVzFsYm5RcEppWnVMbVJsWm1GMWJIUldh'
    || 'V1YzZkh4M2FXNWtiM2M3ZG1GeUlISTliaTVuWlhSVFpXeGxZM1JwYjI0bUptNHVaMlYwVTJWc1pXTjBhVzl1S0NrN2FXWW9jaVltY2k1eVlXNW5aVU52ZFc1'
    || 'MElUMDlNQ2w3YmoxeUxtRnVZMmh2Y2s1dlpHVTdkbUZ5SUd3OWNpNWhibU5vYjNKUFptWnpaWFFzYVQxeUxtWnZZM1Z6VG05a1pUdHlQWEl1Wm05amRYTlBa'
    || 'bVp6WlhRN2RISjVlMjR1Ym05a1pWUjVjR1VzYVM1dWIyUmxWSGx3WlgxallYUmphSHR1UFc1MWJHdzdZbkpsWVdzZ1pYMTJZWElnY3owd0xHTTlMVEVzWmow'
    || 'dE1TeDVQVEFzYWowd0xGUTlaU3hGUFc1MWJHdzdkRHBtYjNJb096c3BlMlp2Y2loMllYSWdSRHRVSVQwOWJueDhiQ0U5UFRBbUpsUXVibTlrWlZSNWNHVWhQ'
    || 'VDB6Zkh3b1l6MXpLMndwTEZRaFBUMXBmSHh5SVQwOU1DWW1WQzV1YjJSbFZIbHdaU0U5UFROOGZDaG1QWE1yY2lrc1ZDNXViMlJsVkhsd1pUMDlQVE1tSmlo'
    || 'ekt6MVVMbTV2WkdWV1lXeDFaUzVzWlc1bmRHZ3BMQ2hFUFZRdVptbHljM1JEYUdsc1pDa2hQVDF1ZFd4c095bEZQVlFzVkQxRU8yWnZjaWc3T3lsN2FXWW9W'
    || 'RDA5UFdVcFluSmxZV3NnZER0cFppaEZQVDA5YmlZbUt5dDVQVDA5YkNZbUtHTTljeWtzUlQwOVBXa21KaXNyYWowOVBYSW1KaWhtUFhNcExDaEVQVlF1Ym1W'
    || 'NGRGTnBZbXhwYm1jcElUMDliblZzYkNsaWNtVmhhenRVUFVVc1JUMVVMbkJoY21WdWRFNXZaR1Y5VkQxRWZXNDlZejA5UFMweGZIeG1QVDA5TFRFL2JuVnNi'
    || 'RHA3YzNSaGNuUTZZeXhsYm1RNlpuMTlaV3h6WlNCdVBXNTFiR3g5YmoxdWZIeDdjM1JoY25RNk1DeGxibVE2TUgxOVpXeHpaU0J1UFc1MWJHdzdabTl5S0Za'
    || 'cFBYdG1iMk4xYzJWa1JXeGxiVHBsTEhObGJHVmpkR2x2YmxKaGJtZGxPbTU5TEZseVBTRXhMRkE5ZER0UUlUMDliblZzYkRzcGFXWW9kRDFRTEdVOWRDNWph'
    || 'R2xzWkN3b2RDNXpkV0owY21WbFJteGhaM01tTVRBeU9Da2hQVDB3SmlabElUMDliblZzYkNsbExuSmxkSFZ5YmoxMExGQTlaVHRsYkhObElHWnZjaWc3VUNF'
    || 'OVBXNTFiR3c3S1h0MFBWQTdkSEo1ZTNaaGNpQkJQWFF1WVd4MFpYSnVZWFJsTzJsbUtDaDBMbVpzWVdkekpqRXdNalFwSVQwOU1DbHpkMmwwWTJnb2RDNTBZ'
    || 'V2NwZTJOaGMyVWdNRHBqWVhObElERXhPbU5oYzJVZ01UVTZZbkpsWVdzN1kyRnpaU0F4T21sbUtFRWhQVDF1ZFd4c0tYdDJZWElnZWoxQkxtMWxiVzlwZW1W'
    || 'a1VISnZjSE1zZDJVOVFTNXRaVzF2YVhwbFpGTjBZWFJsTEcwOWRDNXpkR0YwWlU1dlpHVXNjRDF0TG1kbGRGTnVZWEJ6YUc5MFFtVm1iM0psVlhCa1lYUmxL'
    || 'SFF1Wld4bGJXVnVkRlI1Y0dVOVBUMTBMblI1Y0dVL2VqcG5kQ2gwTG5SNWNHVXNlaWtzZDJVcE8yMHVYMTl5WldGamRFbHVkR1Z5Ym1Gc1UyNWhjSE5vYjNS'
    || 'Q1pXWnZjbVZWY0dSaGRHVTljSDFpY21WaGF6dGpZWE5sSURNNmRtRnlJSFk5ZEM1emRHRjBaVTV2WkdVdVkyOXVkR0ZwYm1WeVNXNW1ienQyTG01dlpHVlVl'
    || 'WEJsUFQwOU1UOTJMblJsZUhSRGIyNTBaVzUwUFNJaU9uWXVibTlrWlZSNWNHVTlQVDA1SmlaMkxtUnZZM1Z0Wlc1MFJXeGxiV1Z1ZENZbWRpNXlaVzF2ZG1W'
    || 'RGFHbHNaQ2gyTG1SdlkzVnRaVzUwUld4bGJXVnVkQ2s3WW5KbFlXczdZMkZ6WlNBMU9tTmhjMlVnTmpwallYTmxJRFE2WTJGelpTQXhOenBpY21WaGF6dGta'
    || 'V1poZFd4ME9uUm9jbTkzSUVWeWNtOXlLR0VvTVRZektTbDlmV05oZEdOb0tGSXBlM2xsS0hRc2RDNXlaWFIxY200c1VpbDlhV1lvWlQxMExuTnBZbXhwYm1j'
    || 'c1pTRTlQVzUxYkd3cGUyVXVjbVYwZFhKdVBYUXVjbVYwZFhKdUxGQTlaVHRpY21WaGEzMVFQWFF1Y21WMGRYSnVmWEpsZEhWeWJpQkJQVWxoTEVsaFBTRXhM'
    || 'RUY5Wm5WdVkzUnBiMjRnVW5Jb1pTeDBMRzRwZTNaaGNpQnlQWFF1ZFhCa1lYUmxVWFZsZFdVN2FXWW9jajF5SVQwOWJuVnNiRDl5TG14aGMzUkZabVpsWTNR'
    || 'NmJuVnNiQ3h5SVQwOWJuVnNiQ2w3ZG1GeUlHdzljajF5TG01bGVIUTdaRzk3YVdZb0tHd3VkR0ZuSm1VcFBUMDlaU2w3ZG1GeUlHazliQzVrWlhOMGNtOTVP'
    || 'Mnd1WkdWemRISnZlVDEyYjJsa0lEQXNhU0U5UFhadmFXUWdNQ1ltVDI4b2RDeHVMR2twZld3OWJDNXVaWGgwZlhkb2FXeGxLR3doUFQxeUtYMTlablZ1WTNS'
    || 'cGIyNGdWR3dvWlN4MEtYdHBaaWgwUFhRdWRYQmtZWFJsVVhWbGRXVXNkRDEwSVQwOWJuVnNiRDkwTG14aGMzUkZabVpsWTNRNmJuVnNiQ3gwSVQwOWJuVnNi'
    || 'Q2w3ZG1GeUlHNDlkRDEwTG01bGVIUTdaRzk3YVdZb0tHNHVkR0ZuSm1VcFBUMDlaU2w3ZG1GeUlISTliaTVqY21WaGRHVTdiaTVrWlhOMGNtOTVQWElvS1gx'
    || 'dVBXNHVibVY0ZEgxM2FHbHNaU2h1SVQwOWRDbDlmV1oxYm1OMGFXOXVJRTF2S0dVcGUzWmhjaUIwUFdVdWNtVm1PMmxtS0hRaFBUMXVkV3hzS1h0MllYSWdi'
    || 'ajFsTG5OMFlYUmxUbTlrWlR0emQybDBZMmdvWlM1MFlXY3BlMk5oYzJVZ05UcGxQVzQ3WW5KbFlXczdaR1ZtWVhWc2REcGxQVzU5ZEhsd1pXOW1JSFE5UFNK'
    || 'bWRXNWpkR2x2YmlJL2RDaGxLVHAwTG1OMWNuSmxiblE5WlgxOVpuVnVZM1JwYjI0Z1FXRW9aU2w3ZG1GeUlIUTlaUzVoYkhSbGNtNWhkR1U3ZENFOVBXNTFi'
    || 'R3dtSmlobExtRnNkR1Z5Ym1GMFpUMXVkV3hzTEVGaEtIUXBLU3hsTG1Ob2FXeGtQVzUxYkd3c1pTNWtaV3hsZEdsdmJuTTliblZzYkN4bExuTnBZbXhwYm1j'
    || 'OWJuVnNiQ3hsTG5SaFp6MDlQVFVtSmloMFBXVXVjM1JoZEdWT2IyUmxMSFFoUFQxdWRXeHNKaVlvWkdWc1pYUmxJSFJiUlhSZExHUmxiR1YwWlNCMFczbHlY'
    || 'U3hrWld4bGRHVWdkRnRIYVYwc1pHVnNaWFJsSUhSYmEyWmRMR1JsYkdWMFpTQjBXMnBtWFNrcExHVXVjM1JoZEdWT2IyUmxQVzUxYkd3c1pTNXlaWFIxY200'
    || 'OWJuVnNiQ3hsTG1SbGNHVnVaR1Z1WTJsbGN6MXVkV3hzTEdVdWJXVnRiMmw2WldSUWNtOXdjejF1ZFd4c0xHVXViV1Z0YjJsNlpXUlRkR0YwWlQxdWRXeHNM'
    || 'R1V1Y0dWdVpHbHVaMUJ5YjNCelBXNTFiR3dzWlM1emRHRjBaVTV2WkdVOWJuVnNiQ3hsTG5Wd1pHRjBaVkYxWlhWbFBXNTFiR3g5Wm5WdVkzUnBiMjRnZW1F'
    || 'b1pTbDdjbVYwZFhKdUlHVXVkR0ZuUFQwOU5YeDhaUzUwWVdjOVBUMHpmSHhsTG5SaFp6MDlQVFI5Wm5WdVkzUnBiMjRnVldFb1pTbDdaVHBtYjNJb096c3Bl'
    || 'Mlp2Y2lnN1pTNXphV0pzYVc1blBUMDliblZzYkRzcGUybG1LR1V1Y21WMGRYSnVQVDA5Ym5Wc2JIeDhlbUVvWlM1eVpYUjFjbTRwS1hKbGRIVnliaUJ1ZFd4'
    || 'c08yVTlaUzV5WlhSMWNtNTlabTl5S0dVdWMybGliR2x1Wnk1eVpYUjFjbTQ5WlM1eVpYUjFjbTRzWlQxbExuTnBZbXhwYm1jN1pTNTBZV2NoUFQwMUppWmxM'
    || 'blJoWnlFOVBUWW1KbVV1ZEdGbklUMDlNVGc3S1h0cFppaGxMbVpzWVdkekpqSjhmR1V1WTJocGJHUTlQVDF1ZFd4c2ZIeGxMblJoWnowOVBUUXBZMjl1ZEds'
    || 'dWRXVWdaVHRsTG1Ob2FXeGtMbkpsZEhWeWJqMWxMR1U5WlM1amFHbHNaSDFwWmlnaEtHVXVabXhoWjNNbU1pa3BjbVYwZFhKdUlHVXVjM1JoZEdWT2IyUmxm'
    || 'WDFtZFc1amRHbHZiaUJFYnlobExIUXNiaWw3ZG1GeUlISTlaUzUwWVdjN2FXWW9jajA5UFRWOGZISTlQVDAyS1dVOVpTNXpkR0YwWlU1dlpHVXNkRDl1TG01'
    || 'dlpHVlVlWEJsUFQwOU9EOXVMbkJoY21WdWRFNXZaR1V1YVc1elpYSjBRbVZtYjNKbEtHVXNkQ2s2Ymk1cGJuTmxjblJDWldadmNtVW9aU3gwS1Rvb2JpNXVi'
    || 'MlJsVkhsd1pUMDlQVGcvS0hROWJpNXdZWEpsYm5ST2IyUmxMSFF1YVc1elpYSjBRbVZtYjNKbEtHVXNiaWtwT2loMFBXNHNkQzVoY0hCbGJtUkRhR2xzWkNo'
    || 'bEtTa3NiajF1TGw5eVpXRmpkRkp2YjNSRGIyNTBZV2x1WlhJc2JpRTliblZzYkh4OGRDNXZibU5zYVdOcklUMDliblZzYkh4OEtIUXViMjVqYkdsamF6MXBi'
    || 'Q2twTzJWc2MyVWdhV1lvY2lFOVBUUW1KaWhsUFdVdVkyaHBiR1FzWlNFOVBXNTFiR3dwS1dadmNpaEVieWhsTEhRc2Jpa3NaVDFsTG5OcFlteHBibWM3WlNF'
    || 'OVBXNTFiR3c3S1VSdktHVXNkQ3h1S1N4bFBXVXVjMmxpYkdsdVozMW1kVzVqZEdsdmJpQlFieWhsTEhRc2JpbDdkbUZ5SUhJOVpTNTBZV2M3YVdZb2NqMDlQ'
    || 'VFY4ZkhJOVBUMDJLV1U5WlM1emRHRjBaVTV2WkdVc2REOXVMbWx1YzJWeWRFSmxabTl5WlNobExIUXBPbTR1WVhCd1pXNWtRMmhwYkdRb1pTazdaV3h6WlNC'
    || 'cFppaHlJVDA5TkNZbUtHVTlaUzVqYUdsc1pDeGxJVDA5Ym5Wc2JDa3BabTl5S0ZCdktHVXNkQ3h1S1N4bFBXVXVjMmxpYkdsdVp6dGxJVDA5Ym5Wc2JEc3BV'
    || 'RzhvWlN4MExHNHBMR1U5WlM1emFXSnNhVzVuZlhaaGNpQkVaVDF1ZFd4c0xIbDBQU0V4TzJaMWJtTjBhVzl1SUZwMEtHVXNkQ3h1S1h0bWIzSW9iajF1TG1O'
    || 'b2FXeGtPMjRoUFQxdWRXeHNPeWxHWVNobExIUXNiaWtzYmoxdUxuTnBZbXhwYm1kOVpuVnVZM1JwYjI0Z1JtRW9aU3gwTEc0cGUybG1LRjkwSmlaMGVYQmxi'
    || 'MllnWDNRdWIyNURiMjF0YVhSR2FXSmxjbFZ1Ylc5MWJuUTlQU0ptZFc1amRHbHZiaUlwZEhKNWUxOTBMbTl1UTI5dGJXbDBSbWxpWlhKVmJtMXZkVzUwS0NS'
    || 'eUxHNHBmV05oZEdOb2UzMXpkMmwwWTJnb2JpNTBZV2NwZTJOaGMyVWdOVHBWWlh4OFZtNG9iaXgwS1R0allYTmxJRFk2ZG1GeUlISTlSR1VzYkQxNWREdEVa'
    || 'VDF1ZFd4c0xGcDBLR1VzZEN4dUtTeEVaVDF5TEhsMFBXd3NSR1VoUFQxdWRXeHNKaVlvZVhRL0tHVTlSR1VzYmoxdUxuTjBZWFJsVG05a1pTeGxMbTV2WkdW'
    || 'VWVYQmxQVDA5T0Q5bExuQmhjbVZ1ZEU1dlpHVXVjbVZ0YjNabFEyaHBiR1FvYmlrNlpTNXlaVzF2ZG1WRGFHbHNaQ2h1S1NrNlJHVXVjbVZ0YjNabFEyaHBi'
    || 'R1FvYmk1emRHRjBaVTV2WkdVcEtUdGljbVZoYXp0allYTmxJREU0T2tSbElUMDliblZzYkNZbUtIbDBQeWhsUFVSbExHNDliaTV6ZEdGMFpVNXZaR1VzWlM1'
    || 'dWIyUmxWSGx3WlQwOVBUZy9VV2tvWlM1d1lYSmxiblJPYjJSbExHNHBPbVV1Ym05a1pWUjVjR1U5UFQweEppWlJhU2hsTEc0cExITnlLR1VwS1RwUmFTaEVa'
    || 'U3h1TG5OMFlYUmxUbTlrWlNrcE8ySnlaV0ZyTzJOaGMyVWdORHB5UFVSbExHdzllWFFzUkdVOWJpNXpkR0YwWlU1dlpHVXVZMjl1ZEdGcGJtVnlTVzVtYnl4'
    || 'NWREMGhNQ3hhZENobExIUXNiaWtzUkdVOWNpeDVkRDFzTzJKeVpXRnJPMk5oYzJVZ01EcGpZWE5sSURFeE9tTmhjMlVnTVRRNlkyRnpaU0F4TlRwcFppZ2hW'
    || 'V1VtSmloeVBXNHVkWEJrWVhSbFVYVmxkV1VzY2lFOVBXNTFiR3dtSmloeVBYSXViR0Z6ZEVWbVptVmpkQ3h5SVQwOWJuVnNiQ2twS1h0c1BYSTljaTV1Wlho'
    || 'ME8yUnZlM1poY2lCcFBXd3NjejFwTG1SbGMzUnliM2s3YVQxcExuUmhaeXh6SVQwOWRtOXBaQ0F3SmlZb0tHa21NaWtoUFQwd2ZId29hU1kwS1NFOVBUQXBK'
    || 'aVpQYnlodUxIUXNjeWtzYkQxc0xtNWxlSFI5ZDJocGJHVW9iQ0U5UFhJcGZWcDBLR1VzZEN4dUtUdGljbVZoYXp0allYTmxJREU2YVdZb0lWVmxKaVlvVm00'
    || 'b2JpeDBLU3h5UFc0dWMzUmhkR1ZPYjJSbExIUjVjR1Z2WmlCeUxtTnZiWEJ2Ym1WdWRGZHBiR3hWYm0xdmRXNTBQVDBpWm5WdVkzUnBiMjRpS1NsMGNubDdj'
    || 'aTV3Y205d2N6MXVMbTFsYlc5cGVtVmtVSEp2Y0hNc2NpNXpkR0YwWlQxdUxtMWxiVzlwZW1Wa1UzUmhkR1VzY2k1amIyMXdiMjVsYm5SWGFXeHNWVzV0YjNW'
    || 'dWRDZ3BmV05oZEdOb0tHTXBlM2xsS0c0c2RDeGpLWDFhZENobExIUXNiaWs3WW5KbFlXczdZMkZ6WlNBeU1UcGFkQ2hsTEhRc2JpazdZbkpsWVdzN1kyRnpa'
    || 'U0F5TWpwdUxtMXZaR1VtTVQ4b1ZXVTlLSEk5VldVcGZIeHVMbTFsYlc5cGVtVmtVM1JoZEdVaFBUMXVkV3hzTEZwMEtHVXNkQ3h1S1N4VlpUMXlLVHBhZENo'
    || 'bExIUXNiaWs3WW5KbFlXczdaR1ZtWVhWc2REcGFkQ2hsTEhRc2JpbDlmV1oxYm1OMGFXOXVJRmRoS0dVcGUzWmhjaUIwUFdVdWRYQmtZWFJsVVhWbGRXVTdh'
    || 'V1lvZENFOVBXNTFiR3dwZTJVdWRYQmtZWFJsVVhWbGRXVTliblZzYkR0MllYSWdiajFsTG5OMFlYUmxUbTlrWlR0dVBUMDliblZzYkNZbUtHNDlaUzV6ZEdG'
    || 'MFpVNXZaR1U5Ym1WM0lGWm1LU3gwTG1admNrVmhZMmdvWm5WdVkzUnBiMjRvY2lsN2RtRnlJR3c5U21ZdVltbHVaQ2h1ZFd4c0xHVXNjaWs3Ymk1b1lYTW9j'
    || 'aWw4ZkNodUxtRmtaQ2h5S1N4eUxuUm9aVzRvYkN4c0tTbDlLWDE5Wm5WdVkzUnBiMjRnZUhRb1pTeDBLWHQyWVhJZ2JqMTBMbVJsYkdWMGFXOXVjenRwWmlo'
    || 'dUlUMDliblZzYkNsbWIzSW9kbUZ5SUhJOU1EdHlQRzR1YkdWdVozUm9PM0lyS3lsN2RtRnlJR3c5Ymx0eVhUdDBjbmw3ZG1GeUlHazlaU3h6UFhRc1l6MXpP'
    || 'MlU2Wm05eUtEdGpJVDA5Ym5Wc2JEc3BlM04zYVhSamFDaGpMblJoWnlsN1kyRnpaU0ExT2tSbFBXTXVjM1JoZEdWT2IyUmxMSGwwUFNFeE8ySnlaV0ZySUdV'
    || 'N1kyRnpaU0F6T2tSbFBXTXVjM1JoZEdWT2IyUmxMbU52Ym5SaGFXNWxja2x1Wm04c2VYUTlJVEE3WW5KbFlXc2daVHRqWVhObElEUTZSR1U5WXk1emRHRjBa'
    || 'VTV2WkdVdVkyOXVkR0ZwYm1WeVNXNW1ieXg1ZEQwaE1EdGljbVZoYXlCbGZXTTlZeTV5WlhSMWNtNTlhV1lvUkdVOVBUMXVkV3hzS1hSb2NtOTNJRVZ5Y205'
    || 'eUtHRW9NVFl3S1NrN1JtRW9hU3h6TEd3cExFUmxQVzUxYkd3c2VYUTlJVEU3ZG1GeUlHWTliQzVoYkhSbGNtNWhkR1U3WmlFOVBXNTFiR3dtSmlobUxuSmxk'
    || 'SFZ5YmoxdWRXeHNLU3hzTG5KbGRIVnliajF1ZFd4c2ZXTmhkR05vS0hrcGUzbGxLR3dzZEN4NUtYMTlhV1lvZEM1emRXSjBjbVZsUm14aFozTW1NVEk0TlRR'
    || 'cFptOXlLSFE5ZEM1amFHbHNaRHQwSVQwOWJuVnNiRHNwSkdFb2RDeGxLU3gwUFhRdWMybGliR2x1WjMxbWRXNWpkR2x2YmlBa1lTaGxMSFFwZTNaaGNpQnVQ'
    || 'V1V1WVd4MFpYSnVZWFJsTEhJOVpTNW1iR0ZuY3p0emQybDBZMmdvWlM1MFlXY3BlMk5oYzJVZ01EcGpZWE5sSURFeE9tTmhjMlVnTVRRNlkyRnpaU0F4TlRw'
    || 'cFppaDRkQ2gwTEdVcExHcDBLR1VwTEhJbU5DbDdkSEo1ZTFKeUtETXNaU3hsTG5KbGRIVnliaWtzVkd3b015eGxLWDFqWVhSamFDaDZLWHQ1WlNobExHVXVj'
    || 'bVYwZFhKdUxIb3BmWFJ5ZVh0U2NpZzFMR1VzWlM1eVpYUjFjbTRwZldOaGRHTm9LSG9wZTNsbEtHVXNaUzV5WlhSMWNtNHNlaWw5ZldKeVpXRnJPMk5oYzJV'
    || 'Z01UcDRkQ2gwTEdVcExHcDBLR1VwTEhJbU5URXlKaVp1SVQwOWJuVnNiQ1ltVm00b2JpeHVMbkpsZEhWeWJpazdZbkpsWVdzN1kyRnpaU0ExT21sbUtIaDBL'
    || 'SFFzWlNrc2FuUW9aU2tzY2lZMU1USW1KbTRoUFQxdWRXeHNKaVpXYmlodUxHNHVjbVYwZFhKdUtTeGxMbVpzWVdkekpqTXlLWHQyWVhJZ2JEMWxMbk4wWVhS'
    || 'bFRtOWtaVHQwY25sN1dtNG9iQ3dpSWlsOVkyRjBZMmdvZWlsN2VXVW9aU3hsTG5KbGRIVnliaXg2S1gxOWFXWW9jaVkwSmlZb2JEMWxMbk4wWVhSbFRtOWta'
    || 'U3hzSVQxdWRXeHNLU2w3ZG1GeUlHazlaUzV0WlcxdmFYcGxaRkJ5YjNCekxITTliaUU5UFc1MWJHdy9iaTV0WlcxdmFYcGxaRkJ5YjNCek9ta3NZejFsTG5S'
    || 'NWNHVXNaajFsTG5Wd1pHRjBaVkYxWlhWbE8ybG1LR1V1ZFhCa1lYUmxVWFZsZFdVOWJuVnNiQ3htSVQwOWJuVnNiQ2wwY25sN1l6MDlQU0pwYm5CMWRDSW1K'
    || 'bWt1ZEhsd1pUMDlQU0p5WVdScGJ5SW1KbWt1Ym1GdFpTRTliblZzYkNZbWJYTW9iQ3hwS1N4aGFTaGpMSE1wTzNaaGNpQjVQV0ZwS0dNc2FTazdabTl5S0hN'
    || 'OU1EdHpQR1l1YkdWdVozUm9PM01yUFRJcGUzWmhjaUJxUFdaYmMxMHNWRDFtVzNNck1WMDdhajA5UFNKemRIbHNaU0kvUlhNb2JDeFVLVHBxUFQwOUltUmhi'
    || 'bWRsY205MWMyeDVVMlYwU1c1dVpYSklWRTFNSWo5M2N5aHNMRlFwT21vOVBUMGlZMmhwYkdSeVpXNGlQMXB1S0d3c1ZDazZhbVVvYkN4cUxGUXNlU2w5YzNk'
    || 'cGRHTm9LR01wZTJOaGMyVWlhVzV3ZFhRaU9teHBLR3dzYVNrN1luSmxZV3M3WTJGelpTSjBaWGgwWVhKbFlTSTZlWE1vYkN4cEtUdGljbVZoYXp0allYTmxJ'
    || 'bk5sYkdWamRDSTZkbUZ5SUVVOWJDNWZkM0poY0hCbGNsTjBZWFJsTG5kaGMwMTFiSFJwY0d4bE8yd3VYM2R5WVhCd1pYSlRkR0YwWlM1M1lYTk5kV3gwYVhC'
    || 'c1pUMGhJV2t1YlhWc2RHbHdiR1U3ZG1GeUlFUTlhUzUyWVd4MVpUdEVJVDF1ZFd4c1AzZHVLR3dzSVNGcExtMTFiSFJwY0d4bExFUXNJVEVwT2tVaFBUMGhJ'
    || 'V2t1YlhWc2RHbHdiR1VtSmlocExtUmxabUYxYkhSV1lXeDFaU0U5Ym5Wc2JEOTNiaWhzTENFaGFTNXRkV3gwYVhCc1pTeHBMbVJsWm1GMWJIUldZV3gxWlN3'
    || 'aE1DazZkMjRvYkN3aElXa3ViWFZzZEdsd2JHVXNhUzV0ZFd4MGFYQnNaVDliWFRvaUlpd2hNU2twZld4YmVYSmRQV2w5WTJGMFkyZ29laWw3ZVdVb1pTeGxM'
    || 'bkpsZEhWeWJpeDZLWDE5WW5KbFlXczdZMkZ6WlNBMk9tbG1LSGgwS0hRc1pTa3NhblFvWlNrc2NpWTBLWHRwWmlobExuTjBZWFJsVG05a1pUMDlQVzUxYkd3'
    || 'cGRHaHliM2NnUlhKeWIzSW9ZU2d4TmpJcEtUdHNQV1V1YzNSaGRHVk9iMlJsTEdrOVpTNXRaVzF2YVhwbFpGQnliM0J6TzNSeWVYdHNMbTV2WkdWV1lXeDFa'
    || 'VDFwZldOaGRHTm9LSG9wZTNsbEtHVXNaUzV5WlhSMWNtNHNlaWw5ZldKeVpXRnJPMk5oYzJVZ016cHBaaWg0ZENoMExHVXBMR3AwS0dVcExISW1OQ1ltYmlF'
    || 'OVBXNTFiR3dtSm00dWJXVnRiMmw2WldSVGRHRjBaUzVwYzBSbGFIbGtjbUYwWldRcGRISjVlM055S0hRdVkyOXVkR0ZwYm1WeVNXNW1ieWw5WTJGMFkyZ29l'
    || 'aWw3ZVdVb1pTeGxMbkpsZEhWeWJpeDZLWDFpY21WaGF6dGpZWE5sSURRNmVIUW9kQ3hsS1N4cWRDaGxLVHRpY21WaGF6dGpZWE5sSURFek9uaDBLSFFzWlNr'
    || 'c2FuUW9aU2tzYkQxbExtTm9hV3hrTEd3dVpteGhaM01tT0RFNU1pWW1LR2s5YkM1dFpXMXZhWHBsWkZOMFlYUmxJVDA5Ym5Wc2JDeHNMbk4wWVhSbFRtOWta'
    || 'UzVwYzBocFpHUmxiajFwTENGcGZIeHNMbUZzZEdWeWJtRjBaU0U5UFc1MWJHd21KbXd1WVd4MFpYSnVZWFJsTG0xbGJXOXBlbVZrVTNSaGRHVWhQVDF1ZFd4'
    || 'c2ZId29RVzg5VTJVb0tTa3BMSEltTkNZbVYyRW9aU2s3WW5KbFlXczdZMkZ6WlNBeU1qcHBaaWhxUFc0aFBUMXVkV3hzSmladUxtMWxiVzlwZW1Wa1UzUmhk'
    || 'R1VoUFQxdWRXeHNMR1V1Ylc5a1pTWXhQeWhWWlQwb2VUMVZaU2w4Zkdvc2VIUW9kQ3hsS1N4VlpUMTVLVHA0ZENoMExHVXBMR3AwS0dVcExISW1PREU1TWls'
    || 'N2FXWW9lVDFsTG0xbGJXOXBlbVZrVTNSaGRHVWhQVDF1ZFd4c0xDaGxMbk4wWVhSbFRtOWtaUzVwYzBocFpHUmxiajE1S1NZbUlXb21KaWhsTG0xdlpHVW1N'
    || 'U2toUFQwd0tXWnZjaWhRUFdVc2FqMWxMbU5vYVd4a08yb2hQVDF1ZFd4c095bDdabTl5S0ZROVVEMXFPMUFoUFQxdWRXeHNPeWw3YzNkcGRHTm9LRVU5VUN4'
    || 'RVBVVXVZMmhwYkdRc1JTNTBZV2NwZTJOaGMyVWdNRHBqWVhObElERXhPbU5oYzJVZ01UUTZZMkZ6WlNBeE5UcFNjaWcwTEVVc1JTNXlaWFIxY200cE8ySnla'
    || 'V0ZyTzJOaGMyVWdNVHBXYmloRkxFVXVjbVYwZFhKdUtUdDJZWElnUVQxRkxuTjBZWFJsVG05a1pUdHBaaWgwZVhCbGIyWWdRUzVqYjIxd2IyNWxiblJYYVd4'
    || 'c1ZXNXRiM1Z1ZEQwOUltWjFibU4wYVc5dUlpbDdjajFGTEc0OVJTNXlaWFIxY200N2RISjVlM1E5Y2l4QkxuQnliM0J6UFhRdWJXVnRiMmw2WldSUWNtOXdj'
    || 'eXhCTG5OMFlYUmxQWFF1YldWdGIybDZaV1JUZEdGMFpTeEJMbU52YlhCdmJtVnVkRmRwYkd4VmJtMXZkVzUwS0NsOVkyRjBZMmdvZWlsN2VXVW9jaXh1TEhv'
    || 'cGZYMWljbVZoYXp0allYTmxJRFU2Vm00b1JTeEZMbkpsZEhWeWJpazdZbkpsWVdzN1kyRnpaU0F5TWpwcFppaEZMbTFsYlc5cGVtVmtVM1JoZEdVaFBUMXVk'
    || 'V3hzS1h0Q1lTaFVLVHRqYjI1MGFXNTFaWDE5UkNFOVBXNTFiR3cvS0VRdWNtVjBkWEp1UFVVc1VEMUVLVHBDWVNoVUtYMXFQV291YzJsaWJHbHVaMzFsT21a'
    || 'dmNpaHFQVzUxYkd3c1ZEMWxPenNwZTJsbUtGUXVkR0ZuUFQwOU5TbDdhV1lvYWowOVBXNTFiR3dwZTJvOVZEdDBjbmw3YkQxVUxuTjBZWFJsVG05a1pTeDVQ'
    || 'eWhwUFd3dWMzUjViR1VzZEhsd1pXOW1JR2t1YzJWMFVISnZjR1Z5ZEhrOVBTSm1kVzVqZEdsdmJpSS9hUzV6WlhSUWNtOXdaWEowZVNnaVpHbHpjR3hoZVNJ'
    || 'c0ltNXZibVVpTENKcGJYQnZjblJoYm5RaUtUcHBMbVJwYzNCc1lYazlJbTV2Ym1VaUtUb29ZejFVTG5OMFlYUmxUbTlrWlN4bVBWUXViV1Z0YjJsNlpXUlFj'
    || 'bTl3Y3k1emRIbHNaU3h6UFdZaFBXNTFiR3dtSm1ZdWFHRnpUM2R1VUhKdmNHVnlkSGtvSW1ScGMzQnNZWGtpS1Q5bUxtUnBjM0JzWVhrNmJuVnNiQ3hqTG5O'
    || 'MGVXeGxMbVJwYzNCc1lYazlYM01vSW1ScGMzQnNZWGtpTEhNcEtYMWpZWFJqYUNoNktYdDVaU2hsTEdVdWNtVjBkWEp1TEhvcGZYMTlaV3h6WlNCcFppaFVM'
    || 'blJoWnowOVBUWXBlMmxtS0dvOVBUMXVkV3hzS1hSeWVYdFVMbk4wWVhSbFRtOWtaUzV1YjJSbFZtRnNkV1U5ZVQ4aUlqcFVMbTFsYlc5cGVtVmtVSEp2Y0hO'
    || 'OVkyRjBZMmdvZWlsN2VXVW9aU3hsTG5KbGRIVnliaXg2S1gxOVpXeHpaU0JwWmlnb1ZDNTBZV2NoUFQweU1pWW1WQzUwWVdjaFBUMHlNM3g4VkM1dFpXMXZh'
    || 'WHBsWkZOMFlYUmxQVDA5Ym5Wc2JIeDhWRDA5UFdVcEppWlVMbU5vYVd4a0lUMDliblZzYkNsN1ZDNWphR2xzWkM1eVpYUjFjbTQ5VkN4VVBWUXVZMmhwYkdR'
    || 'N1kyOXVkR2x1ZFdWOWFXWW9WRDA5UFdVcFluSmxZV3NnWlR0bWIzSW9PMVF1YzJsaWJHbHVaejA5UFc1MWJHdzdLWHRwWmloVUxuSmxkSFZ5YmowOVBXNTFi'
    || 'R3g4ZkZRdWNtVjBkWEp1UFQwOVpTbGljbVZoYXlCbE8ybzlQVDFVSmlZb2FqMXVkV3hzS1N4VVBWUXVjbVYwZFhKdWZXbzlQVDFVSmlZb2FqMXVkV3hzS1N4'
    || 'VUxuTnBZbXhwYm1jdWNtVjBkWEp1UFZRdWNtVjBkWEp1TEZROVZDNXphV0pzYVc1bmZYMWljbVZoYXp0allYTmxJREU1T25oMEtIUXNaU2tzYW5Rb1pTa3Nj'
    || 'aVkwSmlaWFlTaGxLVHRpY21WaGF6dGpZWE5sSURJeE9tSnlaV0ZyTzJSbFptRjFiSFE2ZUhRb2RDeGxLU3hxZENobEtYMTlablZ1WTNScGIyNGdhblFvWlNs'
    || 'N2RtRnlJSFE5WlM1bWJHRm5jenRwWmloMEpqSXBlM1J5ZVh0bE9udG1iM0lvZG1GeUlHNDlaUzV5WlhSMWNtNDdiaUU5UFc1MWJHdzdLWHRwWmloNllTaHVL'
    || 'U2w3ZG1GeUlISTlianRpY21WaGF5QmxmVzQ5Ymk1eVpYUjFjbTU5ZEdoeWIzY2dSWEp5YjNJb1lTZ3hOakFwS1gxemQybDBZMmdvY2k1MFlXY3BlMk5oYzJV'
    || 'Z05UcDJZWElnYkQxeUxuTjBZWFJsVG05a1pUdHlMbVpzWVdkekpqTXlKaVlvV200b2JDd2lJaWtzY2k1bWJHRm5jeVk5TFRNektUdDJZWElnYVQxVllTaGxL'
    || 'VHRRYnlobExHa3NiQ2s3WW5KbFlXczdZMkZ6WlNBek9tTmhjMlVnTkRwMllYSWdjejF5TG5OMFlYUmxUbTlrWlM1amIyNTBZV2x1WlhKSmJtWnZMR005VldF'
    || 'b1pTazdSRzhvWlN4akxITXBPMkp5WldGck8yUmxabUYxYkhRNmRHaHliM2NnUlhKeWIzSW9ZU2d4TmpFcEtYMTlZMkYwWTJnb1ppbDdlV1VvWlN4bExuSmxk'
    || 'SFZ5Yml4bUtYMWxMbVpzWVdkekpqMHRNMzEwSmpRd09UWW1KaWhsTG1ac1lXZHpKajB0TkRBNU55bDlablZ1WTNScGIyNGdRbVlvWlN4MExHNHBlMUE5WlN4'
    || 'V1lTaGxLWDFtZFc1amRHbHZiaUJXWVNobExIUXNiaWw3Wm05eUtIWmhjaUJ5UFNobExtMXZaR1VtTVNraFBUMHdPMUFoUFQxdWRXeHNPeWw3ZG1GeUlHdzlV'
    || 'Q3hwUFd3dVkyaHBiR1E3YVdZb2JDNTBZV2M5UFQweU1pWW1jaWw3ZG1GeUlITTliQzV0WlcxdmFYcGxaRk4wWVhSbElUMDliblZzYkh4OFEydzdhV1lvSVhN'
    || 'cGUzWmhjaUJqUFd3dVlXeDBaWEp1WVhSbExHWTlZeUU5UFc1MWJHd21KbU11YldWdGIybDZaV1JUZEdGMFpTRTlQVzUxYkd4OGZGVmxPMk05UTJ3N2RtRnlJ'
    || 'SGs5VldVN2FXWW9RMnc5Y3l3b1ZXVTlaaWttSmlGNUtXWnZjaWhRUFd3N1VDRTlQVzUxYkd3N0tYTTlVQ3htUFhNdVkyaHBiR1FzY3k1MFlXYzlQVDB5TWlZ'
    || 'bWN5NXRaVzF2YVhwbFpGTjBZWFJsSVQwOWJuVnNiRDlSWVNoc0tUcG1JVDA5Ym5Wc2JEOG9aaTV5WlhSMWNtNDljeXhRUFdZcE9sRmhLR3dwTzJadmNpZzdh'
    || 'U0U5UFc1MWJHdzdLVkE5YVN4V1lTaHBLU3hwUFdrdWMybGliR2x1Wnp0UVBXd3NRMnc5WXl4VlpUMTVmVWhoS0dVcGZXVnNjMlVvYkM1emRXSjBjbVZsUm14'
    || 'aFozTW1PRGMzTWlraFBUMHdKaVpwSVQwOWJuVnNiRDhvYVM1eVpYUjFjbTQ5YkN4UVBXa3BPa2hoS0dVcGZYMW1kVzVqZEdsdmJpQklZU2hsS1h0bWIzSW9P'
    || 'MUFoUFQxdWRXeHNPeWw3ZG1GeUlIUTlVRHRwWmlnb2RDNW1iR0ZuY3lZNE56Y3lLU0U5UFRBcGUzWmhjaUJ1UFhRdVlXeDBaWEp1WVhSbE8zUnllWHRwWmln'
    || 'b2RDNW1iR0ZuY3lZNE56Y3lLU0U5UFRBcGMzZHBkR05vS0hRdWRHRm5LWHRqWVhObElEQTZZMkZ6WlNBeE1UcGpZWE5sSURFMU9sVmxmSHhVYkNnMUxIUXBP'
    || 'Mkp5WldGck8yTmhjMlVnTVRwMllYSWdjajEwTG5OMFlYUmxUbTlrWlR0cFppaDBMbVpzWVdkekpqUW1KaUZWWlNscFppaHVQVDA5Ym5Wc2JDbHlMbU52YlhC'
    || 'dmJtVnVkRVJwWkUxdmRXNTBLQ2s3Wld4elpYdDJZWElnYkQxMExtVnNaVzFsYm5SVWVYQmxQVDA5ZEM1MGVYQmxQMjR1YldWdGIybDZaV1JRY205d2N6cG5k'
    || 'Q2gwTG5SNWNHVXNiaTV0WlcxdmFYcGxaRkJ5YjNCektUdHlMbU52YlhCdmJtVnVkRVJwWkZWd1pHRjBaU2hzTEc0dWJXVnRiMmw2WldSVGRHRjBaU3h5TGw5'
    || 'ZmNtVmhZM1JKYm5SbGNtNWhiRk51WVhCemFHOTBRbVZtYjNKbFZYQmtZWFJsS1gxMllYSWdhVDEwTG5Wd1pHRjBaVkYxWlhWbE8ya2hQVDF1ZFd4c0ppWkNk'
    || 'U2gwTEdrc2NpazdZbkpsWVdzN1kyRnpaU0F6T25aaGNpQnpQWFF1ZFhCa1lYUmxVWFZsZFdVN2FXWW9jeUU5UFc1MWJHd3BlMmxtS0c0OWJuVnNiQ3gwTG1O'
    || 'b2FXeGtJVDA5Ym5Wc2JDbHpkMmwwWTJnb2RDNWphR2xzWkM1MFlXY3BlMk5oYzJVZ05UcHVQWFF1WTJocGJHUXVjM1JoZEdWT2IyUmxPMkp5WldGck8yTmhj'
    || 'MlVnTVRwdVBYUXVZMmhwYkdRdWMzUmhkR1ZPYjJSbGZVSjFLSFFzY3l4dUtYMWljbVZoYXp0allYTmxJRFU2ZG1GeUlHTTlkQzV6ZEdGMFpVNXZaR1U3YVdZ'
    || 'b2JqMDlQVzUxYkd3bUpuUXVabXhoWjNNbU5DbDdiajFqTzNaaGNpQm1QWFF1YldWdGIybDZaV1JRY205d2N6dHpkMmwwWTJnb2RDNTBlWEJsS1h0allYTmxJ'
    || 'bUoxZEhSdmJpSTZZMkZ6WlNKcGJuQjFkQ0k2WTJGelpTSnpaV3hsWTNRaU9tTmhjMlVpZEdWNGRHRnlaV0VpT21ZdVlYVjBiMFp2WTNWekppWnVMbVp2WTNW'
    || 'ektDazdZbkpsWVdzN1kyRnpaU0pwYldjaU9tWXVjM0pqSmlZb2JpNXpjbU05Wmk1emNtTXBmWDFpY21WaGF6dGpZWE5sSURZNlluSmxZV3M3WTJGelpTQTBP'
    || 'bUp5WldGck8yTmhjMlVnTVRJNlluSmxZV3M3WTJGelpTQXhNenBwWmloMExtMWxiVzlwZW1Wa1UzUmhkR1U5UFQxdWRXeHNLWHQyWVhJZ2VUMTBMbUZzZEdW'
    || 'eWJtRjBaVHRwWmloNUlUMDliblZzYkNsN2RtRnlJR285ZVM1dFpXMXZhWHBsWkZOMFlYUmxPMmxtS0dvaFBUMXVkV3hzS1h0MllYSWdWRDFxTG1SbGFIbGtj'
    || 'bUYwWldRN1ZDRTlQVzUxYkd3bUpuTnlLRlFwZlgxOVluSmxZV3M3WTJGelpTQXhPVHBqWVhObElERTNPbU5oYzJVZ01qRTZZMkZ6WlNBeU1qcGpZWE5sSURJ'
    || 'ek9tTmhjMlVnTWpVNlluSmxZV3M3WkdWbVlYVnNkRHAwYUhKdmR5QkZjbkp2Y2loaEtERTJNeWtwZlZWbGZIeDBMbVpzWVdkekpqVXhNaVltVFc4b2RDbDlZ'
    || 'MkYwWTJnb1JTbDdlV1VvZEN4MExuSmxkSFZ5Yml4RktYMTlhV1lvZEQwOVBXVXBlMUE5Ym5Wc2JEdGljbVZoYTMxcFppaHVQWFF1YzJsaWJHbHVaeXh1SVQw'
    || 'OWJuVnNiQ2w3Ymk1eVpYUjFjbTQ5ZEM1eVpYUjFjbTRzVUQxdU8ySnlaV0ZyZlZBOWRDNXlaWFIxY201OWZXWjFibU4wYVc5dUlFSmhLR1VwZTJadmNpZzdV'
    || 'Q0U5UFc1MWJHdzdLWHQyWVhJZ2REMVFPMmxtS0hROVBUMWxLWHRRUFc1MWJHdzdZbkpsWVd0OWRtRnlJRzQ5ZEM1emFXSnNhVzVuTzJsbUtHNGhQVDF1ZFd4'
    || 'c0tYdHVMbkpsZEhWeWJqMTBMbkpsZEhWeWJpeFFQVzQ3WW5KbFlXdDlVRDEwTG5KbGRIVnlibjE5Wm5WdVkzUnBiMjRnVVdFb1pTbDdabTl5S0R0UUlUMDli'
    || 'blZzYkRzcGUzWmhjaUIwUFZBN2RISjVlM04zYVhSamFDaDBMblJoWnlsN1kyRnpaU0F3T21OaGMyVWdNVEU2WTJGelpTQXhOVHAyWVhJZ2JqMTBMbkpsZEhW'
    || 'eWJqdDBjbmw3Vkd3b05DeDBLWDFqWVhSamFDaG1LWHQ1WlNoMExHNHNaaWw5WW5KbFlXczdZMkZ6WlNBeE9uWmhjaUJ5UFhRdWMzUmhkR1ZPYjJSbE8ybG1L'
    || 'SFI1Y0dWdlppQnlMbU52YlhCdmJtVnVkRVJwWkUxdmRXNTBQVDBpWm5WdVkzUnBiMjRpS1h0MllYSWdiRDEwTG5KbGRIVnlianQwY25sN2NpNWpiMjF3YjI1'
    || 'bGJuUkVhV1JOYjNWdWRDZ3BmV05oZEdOb0tHWXBlM2xsS0hRc2JDeG1LWDE5ZG1GeUlHazlkQzV5WlhSMWNtNDdkSEo1ZTAxdktIUXBmV05oZEdOb0tHWXBl'
    || 'M2xsS0hRc2FTeG1LWDFpY21WaGF6dGpZWE5sSURVNmRtRnlJSE05ZEM1eVpYUjFjbTQ3ZEhKNWUwMXZLSFFwZldOaGRHTm9LR1lwZTNsbEtIUXNjeXhtS1gx'
    || 'OWZXTmhkR05vS0dZcGUzbGxLSFFzZEM1eVpYUjFjbTRzWmlsOWFXWW9kRDA5UFdVcGUxQTliblZzYkR0aWNtVmhhMzEyWVhJZ1l6MTBMbk5wWW14cGJtYzdh'
    || 'V1lvWXlFOVBXNTFiR3dwZTJNdWNtVjBkWEp1UFhRdWNtVjBkWEp1TEZBOVl6dGljbVZoYTMxUVBYUXVjbVYwZFhKdWZYMTJZWElnVVdZOVRXRjBhQzVqWlds'
    || 'c0xGSnNQWFpsTGxKbFlXTjBRM1Z5Y21WdWRFUnBjM0JoZEdOb1pYSXNURzg5ZG1VdVVtVmhZM1JEZFhKeVpXNTBUM2R1WlhJc1kzUTlkbVV1VW1WaFkzUkRk'
    || 'WEp5Wlc1MFFtRjBZMmhEYjI1bWFXY3NZajB3TEZSbFBXNTFiR3dzWDJVOWJuVnNiQ3hRWlQwd0xHbDBQVEFzU0c0OVVYUW9NQ2tzVG1VOU1DeFBjajF1ZFd4'
    || 'c0xIQnVQVEFzVDJ3OU1DeEpiejB3TEUxeVBXNTFiR3dzV21VOWJuVnNiQ3hCYnowd0xFSnVQVEV2TUN4SmREMXVkV3hzTEUxc1BTRXhMSHB2UFc1MWJHd3Nj'
    || 'WFE5Ym5Wc2JDeEViRDBoTVN4S2REMXVkV3hzTEZCc1BUQXNSSEk5TUN4VmJ6MXVkV3hzTEV4c1BTMHhMRWxzUFRBN1puVnVZM1JwYjI0Z1NHVW9LWHR5WlhS'
    || 'MWNtNG9ZaVkyS1NFOVBUQS9VMlVvS1RwTWJDRTlQUzB4UDB4c09reHNQVk5sS0NsOVpuVnVZM1JwYjI0Z1luUW9aU2w3Y21WMGRYSnVLR1V1Ylc5a1pTWXhL'
    || 'VDA5UFRBL01Ub29ZaVl5S1NFOVBUQW1KbEJsSVQwOU1EOVFaU1l0VUdVNlZHWXVkSEpoYm5OcGRHbHZiaUU5UFc1MWJHdy9LRWxzUFQwOU1DWW1LRWxzUFZW'
    || 'ektDa3BMRWxzS1Rvb1pUMXBaU3hsSVQwOU1IeDhLR1U5ZDJsdVpHOTNMbVYyWlc1MExHVTlaVDA5UFhadmFXUWdNRDh4TmpwWmN5aGxMblI1Y0dVcEtTeGxL'
    || 'WDFtZFc1amRHbHZiaUJUZENobExIUXNiaXh5S1h0cFppZzFNRHhFY2lsMGFISnZkeUJFY2owd0xGVnZQVzUxYkd3c1JYSnliM0lvWVNneE9EVXBLVHR1Y2lo'
    || 'bExHNHNjaWtzS0NoaUpqSXBQVDA5TUh4OFpTRTlQVlJsS1NZbUtHVTlQVDFVWlNZbUtDaGlKaklwUFQwOU1DWW1LRTlzZkQxdUtTeE9aVDA5UFRRbUptVnVL'
    || 'R1VzVUdVcEtTeHhaU2hsTEhJcExHNDlQVDB4SmlaaVBUMDlNQ1ltS0hRdWJXOWtaU1l4S1QwOVBUQW1KaWhDYmoxVFpTZ3BLelV3TUN4aGJDWW1XWFFvS1Nr'
    || 'cGZXWjFibU4wYVc5dUlIRmxLR1VzZENsN2RtRnlJRzQ5WlM1allXeHNZbUZqYTA1dlpHVTdRMlFvWlN4MEtUdDJZWElnY2oxQ2NpaGxMR1U5UFQxVVpUOVFa'
    || 'VG93S1R0cFppaHlQVDA5TUNsdUlUMDliblZzYkNZbVNYTW9iaWtzWlM1allXeHNZbUZqYTA1dlpHVTliblZzYkN4bExtTmhiR3hpWVdOclVISnBiM0pwZEhr'
    || 'OU1EdGxiSE5sSUdsbUtIUTljaVl0Y2l4bExtTmhiR3hpWVdOclVISnBiM0pwZEhraFBUMTBLWHRwWmlodUlUMXVkV3hzSmlaSmN5aHVLU3gwUFQwOU1TbGxM'
    || 'blJoWnowOVBUQS9RMllvV1dFdVltbHVaQ2h1ZFd4c0xHVXBLVHBFZFNoWllTNWlhVzVrS0c1MWJHd3NaU2twTEVWbUtHWjFibU4wYVc5dUtDbDdLR0ltTmlr'
    || 'OVBUMHdKaVpaZENncGZTa3NiajF1ZFd4c08yVnNjMlY3YzNkcGRHTm9LRVp6S0hJcEtYdGpZWE5sSURFNmJqMTJhVHRpY21WaGF6dGpZWE5sSURRNmJqMUJj'
    || 'enRpY21WaGF6dGpZWE5sSURFMk9tNDlWM0k3WW5KbFlXczdZMkZ6WlNBMU16WTROekE1TVRJNmJqMTZjenRpY21WaGF6dGtaV1poZFd4ME9tNDlWM0o5Ymox'
    || 'MFl5aHVMRWRoTG1KcGJtUW9iblZzYkN4bEtTbDlaUzVqWVd4c1ltRmphMUJ5YVc5eWFYUjVQWFFzWlM1allXeHNZbUZqYTA1dlpHVTlibjE5Wm5WdVkzUnBi'
    || 'MjRnUjJFb1pTeDBLWHRwWmloTWJEMHRNU3hKYkQwd0xDaGlKallwSVQwOU1DbDBhSEp2ZHlCRmNuSnZjaWhoS0RNeU55a3BPM1poY2lCdVBXVXVZMkZzYkdK'
    || 'aFkydE9iMlJsTzJsbUtGRnVLQ2ttSm1VdVkyRnNiR0poWTJ0T2IyUmxJVDA5YmlseVpYUjFjbTRnYm5Wc2JEdDJZWElnY2oxQ2NpaGxMR1U5UFQxVVpUOVFa'
    || 'VG93S1R0cFppaHlQVDA5TUNseVpYUjFjbTRnYm5Wc2JEdHBaaWdvY2lZek1Da2hQVDB3Zkh3b2NpWmxMbVY0Y0dseVpXUk1ZVzVsY3lraFBUMHdmSHgwS1hR'
    || 'OVFXd29aU3h5S1R0bGJITmxlM1E5Y2p0MllYSWdiRDFpTzJKOFBUSTdkbUZ5SUdrOVdHRW9LVHNvVkdVaFBUMWxmSHhRWlNFOVBYUXBKaVlvU1hROWJuVnNi'
    || 'Q3hDYmoxVFpTZ3BLelV3TUN4dGJpaGxMSFFwS1R0a2J5QjBjbmw3UzJZb0tUdGljbVZoYTMxallYUmphQ2hqS1h0TFlTaGxMR01wZlhkb2FXeGxLQ0V3S1R0'
    || 'MGJ5Z3BMRkpzTG1OMWNuSmxiblE5YVN4aVBXd3NYMlVoUFQxdWRXeHNQM1E5TURvb1ZHVTliblZzYkN4UVpUMHdMSFE5VG1VcGZXbG1LSFFoUFQwd0tYdHBa'
    || 'aWgwUFQwOU1pWW1LR3c5WjJrb1pTa3NiQ0U5UFRBbUppaHlQV3dzZEQxR2J5aGxMR3dwS1Nrc2REMDlQVEVwZEdoeWIzY2diajFQY2l4dGJpaGxMREFwTEdW'
    || 'dUtHVXNjaWtzY1dVb1pTeFRaU2dwS1N4dU8ybG1LSFE5UFQwMktXVnVLR1VzY2lrN1pXeHpaWHRwWmloc1BXVXVZM1Z5Y21WdWRDNWhiSFJsY201aGRHVXNL'
    || 'SEltTXpBcFBUMDlNQ1ltSVVkbUtHd3BKaVlvZEQxQmJDaGxMSElwTEhROVBUMHlKaVlvYVQxbmFTaGxLU3hwSVQwOU1DWW1LSEk5YVN4MFBVWnZLR1VzYVNr'
    || 'cEtTeDBQVDA5TVNrcGRHaHliM2NnYmoxUGNpeHRiaWhsTERBcExHVnVLR1VzY2lrc2NXVW9aU3hUWlNncEtTeHVPM04zYVhSamFDaGxMbVpwYm1semFHVmtW'
    || 'Mjl5YXoxc0xHVXVabWx1YVhOb1pXUk1ZVzVsY3oxeUxIUXBlMk5oYzJVZ01EcGpZWE5sSURFNmRHaHliM2NnUlhKeWIzSW9ZU2d6TkRVcEtUdGpZWE5sSURJ'
    || 'NmRtNG9aU3hhWlN4SmRDazdZbkpsWVdzN1kyRnpaU0F6T21sbUtHVnVLR1VzY2lrc0tISW1NVE13TURJek5ESTBLVDA5UFhJbUppaDBQVUZ2S3pVd01DMVRa'
    || 'U2dwTERFd1BIUXBLWHRwWmloQ2NpaGxMREFwSVQwOU1DbGljbVZoYXp0cFppaHNQV1V1YzNWemNHVnVaR1ZrVEdGdVpYTXNLR3dtY2lraFBUMXlLWHRJWlNn'
    || 'cExHVXVjR2x1WjJWa1RHRnVaWE44UFdVdWMzVnpjR1Z1WkdWa1RHRnVaWE1tYkR0aWNtVmhhMzFsTG5ScGJXVnZkWFJJWVc1a2JHVTlRbWtvZG00dVltbHVa'
    || 'Q2h1ZFd4c0xHVXNXbVVzU1hRcExIUXBPMkp5WldGcmZYWnVLR1VzV21Vc1NYUXBPMkp5WldGck8yTmhjMlVnTkRwcFppaGxiaWhsTEhJcExDaHlKalF4T1RR'
    || 'eU5EQXBQVDA5Y2lsaWNtVmhhenRtYjNJb2REMWxMbVYyWlc1MFZHbHRaWE1zYkQwdE1Uc3dQSEk3S1h0MllYSWdjejB6TVMxb2RDaHlLVHRwUFRFOFBITXNj'
    || 'ejEwVzNOZExITStiQ1ltS0d3OWN5a3NjaVk5Zm1sOWFXWW9jajFzTEhJOVUyVW9LUzF5TEhJOUtERXlNRDV5UHpFeU1EbzBPREErY2o4ME9EQTZNVEE0TUQ1'
    || 'eVB6RXdPREE2TVRreU1ENXlQekU1TWpBNk0yVXpQbkkvTTJVek9qUXpNakErY2o4ME16SXdPakU1TmpBcVVXWW9jaTh4T1RZd0tTa3RjaXd4TUR4eUtYdGxM'
    || 'blJwYldWdmRYUklZVzVrYkdVOVFta29kbTR1WW1sdVpDaHVkV3hzTEdVc1dtVXNTWFFwTEhJcE8ySnlaV0ZyZlhadUtHVXNXbVVzU1hRcE8ySnlaV0ZyTzJO'
    || 'aGMyVWdOVHAyYmlobExGcGxMRWwwS1R0aWNtVmhhenRrWldaaGRXeDBPblJvY205M0lFVnljbTl5S0dFb016STVLU2w5ZlgxeVpYUjFjbTRnY1dVb1pTeFRa'
    || 'U2dwS1N4bExtTmhiR3hpWVdOclRtOWtaVDA5UFc0L1IyRXVZbWx1WkNodWRXeHNMR1VwT201MWJHeDlablZ1WTNScGIyNGdSbThvWlN4MEtYdDJZWElnYmox'
    || 'TmNqdHlaWFIxY200Z1pTNWpkWEp5Wlc1MExtMWxiVzlwZW1Wa1UzUmhkR1V1YVhORVpXaDVaSEpoZEdWa0ppWW9iVzRvWlN4MEtTNW1iR0ZuYzN3OU1qVTJL'
    || 'U3hsUFVGc0tHVXNkQ2tzWlNFOVBUSW1KaWgwUFZwbExGcGxQVzRzZENFOVBXNTFiR3dtSmxkdktIUXBLU3hsZldaMWJtTjBhVzl1SUZkdktHVXBlMXBsUFQw'
    || 'OWJuVnNiRDlhWlQxbE9scGxMbkIxYzJndVlYQndiSGtvV21Vc1pTbDlablZ1WTNScGIyNGdSMllvWlNsN1ptOXlLSFpoY2lCMFBXVTdPeWw3YVdZb2RDNW1i'
    || 'R0ZuY3lZeE5qTTROQ2w3ZG1GeUlHNDlkQzUxY0dSaGRHVlJkV1YxWlR0cFppaHVJVDA5Ym5Wc2JDWW1LRzQ5Ymk1emRHOXlaWE1zYmlFOVBXNTFiR3dwS1da'
    || 'dmNpaDJZWElnY2owd08zSThiaTVzWlc1bmRHZzdjaXNyS1h0MllYSWdiRDF1VzNKZExHazliQzVuWlhSVGJtRndjMmh2ZER0c1BXd3VkbUZzZFdVN2RISjVl'
    || 'MmxtS0NGdGRDaHBLQ2tzYkNrcGNtVjBkWEp1SVRGOVkyRjBZMmg3Y21WMGRYSnVJVEY5ZlgxcFppaHVQWFF1WTJocGJHUXNkQzV6ZFdKMGNtVmxSbXhoWjNN'
    || 'bU1UWXpPRFFtSm00aFBUMXVkV3hzS1c0dWNtVjBkWEp1UFhRc2REMXVPMlZzYzJWN2FXWW9kRDA5UFdVcFluSmxZV3M3Wm05eUtEdDBMbk5wWW14cGJtYzlQ'
    || 'VDF1ZFd4c095bDdhV1lvZEM1eVpYUjFjbTQ5UFQxdWRXeHNmSHgwTG5KbGRIVnliajA5UFdVcGNtVjBkWEp1SVRBN2REMTBMbkpsZEhWeWJuMTBMbk5wWW14'
    || 'cGJtY3VjbVYwZFhKdVBYUXVjbVYwZFhKdUxIUTlkQzV6YVdKc2FXNW5mWDF5WlhSMWNtNGhNSDFtZFc1amRHbHZiaUJsYmlobExIUXBlMlp2Y2loMEpqMStT'
    || 'VzhzZENZOWZrOXNMR1V1YzNWemNHVnVaR1ZrVEdGdVpYTjhQWFFzWlM1d2FXNW5aV1JNWVc1bGN5WTlmblFzWlQxbExtVjRjR2x5WVhScGIyNVVhVzFsY3pz'
    || 'd1BIUTdLWHQyWVhJZ2JqMHpNUzFvZENoMEtTeHlQVEU4UEc0N1pWdHVYVDB0TVN4MEpqMStjbjE5Wm5WdVkzUnBiMjRnV1dFb1pTbDdhV1lvS0dJbU5pa2hQ'
    || 'VDB3S1hSb2NtOTNJRVZ5Y205eUtHRW9NekkzS1NrN1VXNG9LVHQyWVhJZ2REMUNjaWhsTERBcE8ybG1LQ2gwSmpFcFBUMDlNQ2x5WlhSMWNtNGdjV1VvWlN4'
    || 'VFpTZ3BLU3h1ZFd4c08zWmhjaUJ1UFVGc0tHVXNkQ2s3YVdZb1pTNTBZV2NoUFQwd0ppWnVQVDA5TWlsN2RtRnlJSEk5WjJrb1pTazdjaUU5UFRBbUppaDBQ'
    || 'WElzYmoxR2J5aGxMSElwS1gxcFppaHVQVDA5TVNsMGFISnZkeUJ1UFU5eUxHMXVLR1VzTUNrc1pXNG9aU3gwS1N4eFpTaGxMRk5sS0NrcExHNDdhV1lvYmow'
    || 'OVBUWXBkR2h5YjNjZ1JYSnliM0lvWVNnek5EVXBLVHR5WlhSMWNtNGdaUzVtYVc1cGMyaGxaRmR2Y21zOVpTNWpkWEp5Wlc1MExtRnNkR1Z5Ym1GMFpTeGxM'
    || 'bVpwYm1semFHVmtUR0Z1WlhNOWRDeDJiaWhsTEZwbExFbDBLU3h4WlNobExGTmxLQ2twTEc1MWJHeDlablZ1WTNScGIyNGdKRzhvWlN4MEtYdDJZWElnYmox'
    || 'aU8ySjhQVEU3ZEhKNWUzSmxkSFZ5YmlCbEtIUXBmV1pwYm1Gc2JIbDdZajF1TEdJOVBUMHdKaVlvUW00OVUyVW9LU3MxTURBc1lXd21KbGwwS0NrcGZYMW1k'
    || 'VzVqZEdsdmJpQm9iaWhsS1h0S2RDRTlQVzUxYkd3bUprcDBMblJoWnowOVBUQW1KaWhpSmpZcFBUMDlNQ1ltVVc0b0tUdDJZWElnZEQxaU8ySjhQVEU3ZG1G'
    || 'eUlHNDlZM1F1ZEhKaGJuTnBkR2x2Yml4eVBXbGxPM1J5ZVh0cFppaGpkQzUwY21GdWMybDBhVzl1UFc1MWJHd3NhV1U5TVN4bEtYSmxkSFZ5YmlCbEtDbDla'
    || 'bWx1WVd4c2VYdHBaVDF5TEdOMExuUnlZVzV6YVhScGIyNDliaXhpUFhRc0tHSW1OaWs5UFQwd0ppWlpkQ2dwZlgxbWRXNWpkR2x2YmlCV2J5Z3BlMmwwUFVo'
    || 'dUxtTjFjbkpsYm5Rc1lXVW9TRzRwZldaMWJtTjBhVzl1SUcxdUtHVXNkQ2w3WlM1bWFXNXBjMmhsWkZkdmNtczliblZzYkN4bExtWnBibWx6YUdWa1RHRnVa'
    || 'WE05TUR0MllYSWdiajFsTG5ScGJXVnZkWFJJWVc1a2JHVTdhV1lvYmlFOVBTMHhKaVlvWlM1MGFXMWxiM1YwU0dGdVpHeGxQUzB4TEY5bUtHNHBLU3hmWlNF'
    || 'OVBXNTFiR3dwWm05eUtHNDlYMlV1Y21WMGRYSnVPMjRoUFQxdWRXeHNPeWw3ZG1GeUlISTlianR6ZDJsMFkyZ29XbWtvY2lrc2NpNTBZV2NwZTJOaGMyVWdN'
    || 'VHB5UFhJdWRIbHdaUzVqYUdsc1pFTnZiblJsZUhSVWVYQmxjeXh5SVQxdWRXeHNKaVp6YkNncE8ySnlaV0ZyTzJOaGMyVWdNenBYYmlncExHRmxLRmxsS1N4'
    || 'aFpTaEpaU2tzWVc4b0tUdGljbVZoYXp0allYTmxJRFU2YzI4b2NpazdZbkpsWVdzN1kyRnpaU0EwT2xkdUtDazdZbkpsWVdzN1kyRnpaU0F4TXpwaFpTaG9a'
    || 'U2s3WW5KbFlXczdZMkZ6WlNBeE9UcGhaU2hvWlNrN1luSmxZV3M3WTJGelpTQXhNRHB1YnloeUxuUjVjR1V1WDJOdmJuUmxlSFFwTzJKeVpXRnJPMk5oYzJV'
    || 'Z01qSTZZMkZ6WlNBeU16cFdieWdwZlc0OWJpNXlaWFIxY201OWFXWW9WR1U5WlN4ZlpUMWxQWFJ1S0dVdVkzVnljbVZ1ZEN4dWRXeHNLU3hRWlQxcGREMTBM'
    || 'RTVsUFRBc1QzSTliblZzYkN4SmJ6MVBiRDF3Ymowd0xGcGxQVTF5UFc1MWJHd3NZMjRoUFQxdWRXeHNLWHRtYjNJb2REMHdPM1E4WTI0dWJHVnVaM1JvTzNR'
    || 'ckt5bHBaaWh1UFdOdVczUmRMSEk5Ymk1cGJuUmxjbXhsWVhabFpDeHlJVDA5Ym5Wc2JDbDdiaTVwYm5SbGNteGxZWFpsWkQxdWRXeHNPM1poY2lCc1BYSXVi'
    || 'bVY0ZEN4cFBXNHVjR1Z1WkdsdVp6dHBaaWhwSVQwOWJuVnNiQ2w3ZG1GeUlITTlhUzV1WlhoME8ya3VibVY0ZEQxc0xISXVibVY0ZEQxemZXNHVjR1Z1Wkds'
    || 'dVp6MXlmV051UFc1MWJHeDljbVYwZFhKdUlHVjlablZ1WTNScGIyNGdTMkVvWlN4MEtYdGtiM3QyWVhJZ2JqMWZaVHQwY25sN2FXWW9kRzhvS1N4NGJDNWpk'
    || 'WEp5Wlc1MFBVVnNMRk5zS1h0bWIzSW9kbUZ5SUhJOWJXVXViV1Z0YjJsNlpXUlRkR0YwWlR0eUlUMDliblZzYkRzcGUzWmhjaUJzUFhJdWNYVmxkV1U3YkNF'
    || 'OVBXNTFiR3dtSmloc0xuQmxibVJwYm1jOWJuVnNiQ2tzY2oxeUxtNWxlSFI5VTJ3OUlURjlhV1lvWm00OU1DeERaVDFGWlQxdFpUMXVkV3hzTEU1eVBTRXhM'
    || 'R3R5UFRBc1RHOHVZM1Z5Y21WdWREMXVkV3hzTEc0OVBUMXVkV3hzZkh4dUxuSmxkSFZ5YmowOVBXNTFiR3dwZTA1bFBURXNUM0k5ZEN4ZlpUMXVkV3hzTzJK'
    || 'eVpXRnJmV1U2ZTNaaGNpQnBQV1VzY3oxdUxuSmxkSFZ5Yml4alBXNHNaajEwTzJsbUtIUTlVR1VzWXk1bWJHRm5jM3c5TXpJM05qZ3NaaUU5UFc1MWJHd21K'
    || 'blI1Y0dWdlppQm1QVDBpYjJKcVpXTjBJaVltZEhsd1pXOW1JR1l1ZEdobGJqMDlJbVoxYm1OMGFXOXVJaWw3ZG1GeUlIazlaaXhxUFdNc1ZEMXFMblJoWnp0'
    || 'cFppZ29haTV0YjJSbEpqRXBQVDA5TUNZbUtGUTlQVDB3Zkh4VVBUMDlNVEY4ZkZROVBUMHhOU2twZTNaaGNpQkZQV291WVd4MFpYSnVZWFJsTzBVL0tHb3Vk'
    || 'WEJrWVhSbFVYVmxkV1U5UlM1MWNHUmhkR1ZSZFdWMVpTeHFMbTFsYlc5cGVtVmtVM1JoZEdVOVJTNXRaVzF2YVhwbFpGTjBZWFJsTEdvdWJHRnVaWE05UlM1'
    || 'c1lXNWxjeWs2S0dvdWRYQmtZWFJsVVhWbGRXVTliblZzYkN4cUxtMWxiVzlwZW1Wa1UzUmhkR1U5Ym5Wc2JDbDlkbUZ5SUVROWVHRW9jeWs3YVdZb1JDRTlQ'
    || 'VzUxYkd3cGUwUXVabXhoWjNNbVBTMHlOVGNzVTJFb1JDeHpMR01zYVN4MEtTeEVMbTF2WkdVbU1TWW1lV0VvYVN4NUxIUXBMSFE5UkN4bVBYazdkbUZ5SUVF'
    || 'OWRDNTFjR1JoZEdWUmRXVjFaVHRwWmloQlBUMDliblZzYkNsN2RtRnlJSG85Ym1WM0lGTmxkRHQ2TG1Ga1pDaG1LU3gwTG5Wd1pHRjBaVkYxWlhWbFBYcDla'
    || 'V3h6WlNCQkxtRmtaQ2htS1R0aWNtVmhheUJsZldWc2MyVjdhV1lvS0hRbU1TazlQVDB3S1h0NVlTaHBMSGtzZENrc1NHOG9LVHRpY21WaGF5QmxmV1k5UlhK'
    || 'eWIzSW9ZU2cwTWpZcEtYMTlaV3h6WlNCcFppaHdaU1ltWXk1dGIyUmxKakVwZTNaaGNpQjNaVDE0WVNoektUdHBaaWgzWlNFOVBXNTFiR3dwZXloM1pTNW1i'
    || 'R0ZuY3lZMk5UVXpOaWs5UFQwd0ppWW9kMlV1Wm14aFozTjhQVEkxTmlrc1UyRW9kMlVzY3l4akxHa3NkQ2tzWW1rb0pHNG9aaXhqS1NrN1luSmxZV3NnWlgx'
    || 'OWFUMW1QU1J1S0dZc1l5a3NUbVVoUFQwMEppWW9UbVU5TWlrc1RYSTlQVDF1ZFd4c1AwMXlQVnRwWFRwTmNpNXdkWE5vS0drcExHazljenRrYjN0emQybDBZ'
    || 'MmdvYVM1MFlXY3BlMk5oYzJVZ016cHBMbVpzWVdkemZEMDJOVFV6Tml4MEpqMHRkQ3hwTG14aGJtVnpmRDEwTzNaaGNpQnRQWFpoS0drc1ppeDBLVHRJZFNo'
    || 'cExHMHBPMkp5WldGcklHVTdZMkZ6WlNBeE9tTTlaanQyWVhJZ2NEMXBMblI1Y0dVc2RqMXBMbk4wWVhSbFRtOWtaVHRwWmlnb2FTNW1iR0ZuY3lZeE1qZ3BQ'
    || 'VDA5TUNZbUtIUjVjR1Z2WmlCd0xtZGxkRVJsY21sMlpXUlRkR0YwWlVaeWIyMUZjbkp2Y2owOUltWjFibU4wYVc5dUlueDhkaUU5UFc1MWJHd21KblI1Y0dW'
    || 'dlppQjJMbU52YlhCdmJtVnVkRVJwWkVOaGRHTm9QVDBpWm5WdVkzUnBiMjRpSmlZb2NYUTlQVDF1ZFd4c2ZId2hjWFF1YUdGektIWXBLU2twZTJrdVpteGha'
    || 'M044UFRZMU5UTTJMSFFtUFMxMExHa3ViR0Z1WlhOOFBYUTdkbUZ5SUZJOVoyRW9hU3hqTEhRcE8waDFLR2tzVWlrN1luSmxZV3NnWlgxOWFUMXBMbkpsZEhW'
    || 'eWJuMTNhR2xzWlNocElUMDliblZzYkNsOWNXRW9iaWw5WTJGMFkyZ29WU2w3ZEQxVkxGOWxQVDA5YmlZbWJpRTlQVzUxYkd3bUppaGZaVDF1UFc0dWNtVjBk'
    || 'WEp1S1R0amIyNTBhVzUxWlgxaWNtVmhhMzEzYUdsc1pTZ2hNQ2w5Wm5WdVkzUnBiMjRnV0dFb0tYdDJZWElnWlQxU2JDNWpkWEp5Wlc1ME8zSmxkSFZ5YmlC'
    || 'U2JDNWpkWEp5Wlc1MFBVVnNMR1U5UFQxdWRXeHNQMFZzT21WOVpuVnVZM1JwYjI0Z1NHOG9LWHNvVG1VOVBUMHdmSHhPWlQwOVBUTjhmRTVsUFQwOU1pa21K'
    || 'aWhPWlQwMEtTeFVaVDA5UFc1MWJHeDhmQ2h3YmlZeU5qZzBNelUwTlRVcFBUMDlNQ1ltS0U5c0pqSTJPRFF6TlRRMU5TazlQVDB3Zkh4bGJpaFVaU3hRWlNs'
    || 'OVpuVnVZM1JwYjI0Z1FXd29aU3gwS1h0MllYSWdiajFpTzJKOFBUSTdkbUZ5SUhJOVdHRW9LVHNvVkdVaFBUMWxmSHhRWlNFOVBYUXBKaVlvU1hROWJuVnNi'
    || 'Q3h0YmlobExIUXBLVHRrYnlCMGNubDdXV1lvS1R0aWNtVmhhMzFqWVhSamFDaHNLWHRMWVNobExHd3BmWGRvYVd4bEtDRXdLVHRwWmloMGJ5Z3BMR0k5Yml4'
    || 'U2JDNWpkWEp5Wlc1MFBYSXNYMlVoUFQxdWRXeHNLWFJvY205M0lFVnljbTl5S0dFb01qWXhLU2s3Y21WMGRYSnVJRlJsUFc1MWJHd3NVR1U5TUN4T1pYMW1k'
    || 'VzVqZEdsdmJpQlpaaWdwZTJadmNpZzdYMlVoUFQxdWRXeHNPeWxhWVNoZlpTbDlablZ1WTNScGIyNGdTMllvS1h0bWIzSW9PMTlsSVQwOWJuVnNiQ1ltSVhs'
    || 'a0tDazdLVnBoS0Y5bEtYMW1kVzVqZEdsdmJpQmFZU2hsS1h0MllYSWdkRDFsWXlobExtRnNkR1Z5Ym1GMFpTeGxMR2wwS1R0bExtMWxiVzlwZW1Wa1VISnZj'
    || 'SE05WlM1d1pXNWthVzVuVUhKdmNITXNkRDA5UFc1MWJHdy9jV0VvWlNrNlgyVTlkQ3hNYnk1amRYSnlaVzUwUFc1MWJHeDlablZ1WTNScGIyNGdjV0VvWlNs'
    || 'N2RtRnlJSFE5WlR0a2IzdDJZWElnYmoxMExtRnNkR1Z5Ym1GMFpUdHBaaWhsUFhRdWNtVjBkWEp1TENoMExtWnNZV2R6SmpNeU56WTRLVDA5UFRBcGUybG1L'
    || 'RzQ5VjJZb2JpeDBMR2wwS1N4dUlUMDliblZzYkNsN1gyVTlianR5WlhSMWNtNTlmV1ZzYzJWN2FXWW9iajBrWmlodUxIUXBMRzRoUFQxdWRXeHNLWHR1TG1a'
    || 'c1lXZHpKajB6TWpjMk55eGZaVDF1TzNKbGRIVnlibjFwWmlobElUMDliblZzYkNsbExtWnNZV2R6ZkQwek1qYzJPQ3hsTG5OMVluUnlaV1ZHYkdGbmN6MHdM'
    || 'R1V1WkdWc1pYUnBiMjV6UFc1MWJHdzdaV3h6Wlh0T1pUMDJMRjlsUFc1MWJHdzdjbVYwZFhKdWZYMXBaaWgwUFhRdWMybGliR2x1Wnl4MElUMDliblZzYkNs'
    || 'N1gyVTlkRHR5WlhSMWNtNTlYMlU5ZEQxbGZYZG9hV3hsS0hRaFBUMXVkV3hzS1R0T1pUMDlQVEFtSmloT1pUMDFLWDFtZFc1amRHbHZiaUIyYmlobExIUXNi'
    || 'aWw3ZG1GeUlISTlhV1VzYkQxamRDNTBjbUZ1YzJsMGFXOXVPM1J5ZVh0amRDNTBjbUZ1YzJsMGFXOXVQVzUxYkd3c2FXVTlNU3hZWmlobExIUXNiaXh5S1gx'
    || 'bWFXNWhiR3g1ZTJOMExuUnlZVzV6YVhScGIyNDliQ3hwWlQxeWZYSmxkSFZ5YmlCdWRXeHNmV1oxYm1OMGFXOXVJRmhtS0dVc2RDeHVMSElwZTJSdklGRnVL'
    || 'Q2s3ZDJocGJHVW9TblFoUFQxdWRXeHNLVHRwWmlnb1lpWTJLU0U5UFRBcGRHaHliM2NnUlhKeWIzSW9ZU2d6TWpjcEtUdHVQV1V1Wm1sdWFYTm9aV1JYYjNK'
    || 'ck8zWmhjaUJzUFdVdVptbHVhWE5vWldSTVlXNWxjenRwWmlodVBUMDliblZzYkNseVpYUjFjbTRnYm5Wc2JEdHBaaWhsTG1acGJtbHphR1ZrVjI5eWF6MXVk'
    || 'V3hzTEdVdVptbHVhWE5vWldSTVlXNWxjejB3TEc0OVBUMWxMbU4xY25KbGJuUXBkR2h5YjNjZ1JYSnliM0lvWVNneE56Y3BLVHRsTG1OaGJHeGlZV05yVG05'
    || 'a1pUMXVkV3hzTEdVdVkyRnNiR0poWTJ0UWNtbHZjbWwwZVQwd08zWmhjaUJwUFc0dWJHRnVaWE44Ymk1amFHbHNaRXhoYm1Wek8ybG1LRlJrS0dVc2FTa3Na'
    || 'VDA5UFZSbEppWW9YMlU5VkdVOWJuVnNiQ3hRWlQwd0tTd29iaTV6ZFdKMGNtVmxSbXhoWjNNbU1qQTJOQ2s5UFQwd0ppWW9iaTVtYkdGbmN5WXlNRFkwS1Qw'
    || 'OVBUQjhmRVJzZkh3b1JHdzlJVEFzZEdNb1YzSXNablZ1WTNScGIyNG9LWHR5WlhSMWNtNGdVVzRvS1N4dWRXeHNmU2twTEdrOUtHNHVabXhoWjNNbU1UVTVP'
    || 'VEFwSVQwOU1Dd29iaTV6ZFdKMGNtVmxSbXhoWjNNbU1UVTVPVEFwSVQwOU1IeDhhU2w3YVQxamRDNTBjbUZ1YzJsMGFXOXVMR04wTG5SeVlXNXphWFJwYjI0'
    || 'OWJuVnNiRHQyWVhJZ2N6MXBaVHRwWlQweE8zWmhjaUJqUFdJN1ludzlOQ3hNYnk1amRYSnlaVzUwUFc1MWJHd3NTR1lvWlN4dUtTd2tZU2h1TEdVcExHMW1L'
    || 'RlpwS1N4WmNqMGhJU1JwTEZacFBTUnBQVzUxYkd3c1pTNWpkWEp5Wlc1MFBXNHNRbVlvYmlrc2VHUW9LU3hpUFdNc2FXVTljeXhqZEM1MGNtRnVjMmwwYVc5'
    || 'dVBXbDlaV3h6WlNCbExtTjFjbkpsYm5ROWJqdHBaaWhFYkNZbUtFUnNQU0V4TEVwMFBXVXNVR3c5YkNrc2FUMWxMbkJsYm1ScGJtZE1ZVzVsY3l4cFBUMDlN'
    || 'Q1ltS0hGMFBXNTFiR3dwTEY5a0tHNHVjM1JoZEdWT2IyUmxLU3h4WlNobExGTmxLQ2twTEhRaFBUMXVkV3hzS1dadmNpaHlQV1V1YjI1U1pXTnZkbVZ5WVdK'
    || 'c1pVVnljbTl5TEc0OU1EdHVQSFF1YkdWdVozUm9PMjRyS3lsc1BYUmJibDBzY2loc0xuWmhiSFZsTEh0amIyMXdiMjVsYm5SVGRHRmphenBzTG5OMFlXTnJM'
    || 'R1JwWjJWemREcHNMbVJwWjJWemRIMHBPMmxtS0Uxc0tYUm9jbTkzSUUxc1BTRXhMR1U5ZW04c2VtODliblZzYkN4bE8zSmxkSFZ5YmloUWJDWXhLU0U5UFRB'
    || 'bUptVXVkR0ZuSVQwOU1DWW1VVzRvS1N4cFBXVXVjR1Z1WkdsdVoweGhibVZ6TENocEpqRXBJVDA5TUQ5bFBUMDlWVzgvUkhJckt6b29SSEk5TUN4VmJ6MWxL'
    || 'VHBFY2owd0xGbDBLQ2tzYm5Wc2JIMW1kVzVqZEdsdmJpQlJiaWdwZTJsbUtFcDBJVDA5Ym5Wc2JDbDdkbUZ5SUdVOVJuTW9VR3dwTEhROVkzUXVkSEpoYm5O'
    || 'cGRHbHZiaXh1UFdsbE8zUnllWHRwWmloamRDNTBjbUZ1YzJsMGFXOXVQVzUxYkd3c2FXVTlNVFkrWlQ4eE5qcGxMRXAwUFQwOWJuVnNiQ2wyWVhJZ2NqMGhN'
    || 'VHRsYkhObGUybG1LR1U5U25Rc1NuUTliblZzYkN4UWJEMHdMQ2hpSmpZcElUMDlNQ2wwYUhKdmR5QkZjbkp2Y2loaEtETXpNU2twTzNaaGNpQnNQV0k3Wm05'
    || 'eUtHSjhQVFFzVUQxbExtTjFjbkpsYm5RN1VDRTlQVzUxYkd3N0tYdDJZWElnYVQxUUxITTlhUzVqYUdsc1pEdHBaaWdvVUM1bWJHRm5jeVl4TmlraFBUMHdL'
    || 'WHQyWVhJZ1l6MXBMbVJsYkdWMGFXOXVjenRwWmloaklUMDliblZzYkNsN1ptOXlLSFpoY2lCbVBUQTdaanhqTG14bGJtZDBhRHRtS3lzcGUzWmhjaUI1UFdO'
    || 'YlpsMDdabTl5S0ZBOWVUdFFJVDA5Ym5Wc2JEc3BlM1poY2lCcVBWQTdjM2RwZEdOb0tHb3VkR0ZuS1h0allYTmxJREE2WTJGelpTQXhNVHBqWVhObElERTFP'
    || 'bEp5S0Rnc2FpeHBLWDEyWVhJZ1ZEMXFMbU5vYVd4a08ybG1LRlFoUFQxdWRXeHNLVlF1Y21WMGRYSnVQV29zVUQxVU8yVnNjMlVnWm05eUtEdFFJVDA5Ym5W'
    || 'c2JEc3BlMm85VUR0MllYSWdSVDFxTG5OcFlteHBibWNzUkQxcUxuSmxkSFZ5Ymp0cFppaEJZU2hxS1N4cVBUMDllU2w3VUQxdWRXeHNPMkp5WldGcmZXbG1L'
    || 'RVVoUFQxdWRXeHNLWHRGTG5KbGRIVnliajFFTEZBOVJUdGljbVZoYTMxUVBVUjlmWDEyWVhJZ1FUMXBMbUZzZEdWeWJtRjBaVHRwWmloQklUMDliblZzYkNs'
    || 'N2RtRnlJSG85UVM1amFHbHNaRHRwWmloNklUMDliblZzYkNsN1FTNWphR2xzWkQxdWRXeHNPMlJ2ZTNaaGNpQjNaVDE2TG5OcFlteHBibWM3ZWk1emFXSnNh'
    || 'VzVuUFc1MWJHd3NlajEzWlgxM2FHbHNaU2g2SVQwOWJuVnNiQ2w5ZlZBOWFYMTlhV1lvS0drdWMzVmlkSEpsWlVac1lXZHpKakl3TmpRcElUMDlNQ1ltY3lF'
    || 'OVBXNTFiR3dwY3k1eVpYUjFjbTQ5YVN4UVBYTTdaV3h6WlNCbE9tWnZjaWc3VUNFOVBXNTFiR3c3S1h0cFppaHBQVkFzS0drdVpteGhaM01tTWpBME9Da2hQ'
    || 'VDB3S1hOM2FYUmphQ2hwTG5SaFp5bDdZMkZ6WlNBd09tTmhjMlVnTVRFNlkyRnpaU0F4TlRwU2NpZzVMR2tzYVM1eVpYUjFjbTRwZlhaaGNpQnRQV2t1YzJs'
    || 'aWJHbHVaenRwWmlodElUMDliblZzYkNsN2JTNXlaWFIxY200OWFTNXlaWFIxY200c1VEMXRPMkp5WldGcklHVjlVRDFwTG5KbGRIVnlibjE5ZG1GeUlIQTla'
    || 'UzVqZFhKeVpXNTBPMlp2Y2loUVBYQTdVQ0U5UFc1MWJHdzdLWHR6UFZBN2RtRnlJSFk5Y3k1amFHbHNaRHRwWmlnb2N5NXpkV0owY21WbFJteGhaM01tTWpB'
    || 'Mk5Da2hQVDB3SmlaMklUMDliblZzYkNsMkxuSmxkSFZ5YmoxekxGQTlkanRsYkhObElHVTZabTl5S0hNOWNEdFFJVDA5Ym5Wc2JEc3BlMmxtS0dNOVVDd29Z'
    || 'eTVtYkdGbmN5WXlNRFE0S1NFOVBUQXBkSEo1ZTNOM2FYUmphQ2hqTG5SaFp5bDdZMkZ6WlNBd09tTmhjMlVnTVRFNlkyRnpaU0F4TlRwVWJDZzVMR01wZlgx'
    || 'allYUmphQ2hWS1h0NVpTaGpMR011Y21WMGRYSnVMRlVwZldsbUtHTTlQVDF6S1h0UVBXNTFiR3c3WW5KbFlXc2daWDEyWVhJZ1VqMWpMbk5wWW14cGJtYzdh'
    || 'V1lvVWlFOVBXNTFiR3dwZTFJdWNtVjBkWEp1UFdNdWNtVjBkWEp1TEZBOVVqdGljbVZoYXlCbGZWQTlZeTV5WlhSMWNtNTlmV2xtS0dJOWJDeFpkQ2dwTEY5'
    || 'MEppWjBlWEJsYjJZZ1gzUXViMjVRYjNOMFEyOXRiV2wwUm1saVpYSlNiMjkwUFQwaVpuVnVZM1JwYjI0aUtYUnllWHRmZEM1dmJsQnZjM1JEYjIxdGFYUkdh'
    || 'V0psY2xKdmIzUW9KSElzWlNsOVkyRjBZMmg3ZlhJOUlUQjljbVYwZFhKdUlISjlabWx1WVd4c2VYdHBaVDF1TEdOMExuUnlZVzV6YVhScGIyNDlkSDE5Y21W'
    || 'MGRYSnVJVEY5Wm5WdVkzUnBiMjRnU21Fb1pTeDBMRzRwZTNROUpHNG9iaXgwS1N4MFBYWmhLR1VzZEN3eEtTeGxQVmgwS0dVc2RDd3hLU3gwUFVobEtDa3Na'
    || 'U0U5UFc1MWJHd21KaWh1Y2lobExERXNkQ2tzY1dVb1pTeDBLU2w5Wm5WdVkzUnBiMjRnZVdVb1pTeDBMRzRwZTJsbUtHVXVkR0ZuUFQwOU15bEtZU2hsTEdV'
    || 'c2JpazdaV3h6WlNCbWIzSW9PM1FoUFQxdWRXeHNPeWw3YVdZb2RDNTBZV2M5UFQwektYdEtZU2gwTEdVc2JpazdZbkpsWVd0OVpXeHpaU0JwWmloMExuUmha'
    || 'ejA5UFRFcGUzWmhjaUJ5UFhRdWMzUmhkR1ZPYjJSbE8ybG1LSFI1Y0dWdlppQjBMblI1Y0dVdVoyVjBSR1Z5YVhabFpGTjBZWFJsUm5KdmJVVnljbTl5UFQw'
    || 'aVpuVnVZM1JwYjI0aWZIeDBlWEJsYjJZZ2NpNWpiMjF3YjI1bGJuUkVhV1JEWVhSamFEMDlJbVoxYm1OMGFXOXVJaVltS0hGMFBUMDliblZzYkh4OElYRjBM'
    || 'bWhoY3loeUtTa3BlMlU5Skc0b2JpeGxLU3hsUFdkaEtIUXNaU3d4S1N4MFBWaDBLSFFzWlN3eEtTeGxQVWhsS0Nrc2RDRTlQVzUxYkd3bUppaHVjaWgwTERF'
    || 'c1pTa3NjV1VvZEN4bEtTazdZbkpsWVd0OWZYUTlkQzV5WlhSMWNtNTlmV1oxYm1OMGFXOXVJRnBtS0dVc2RDeHVLWHQyWVhJZ2NqMWxMbkJwYm1kRFlXTm9a'
    || 'VHR5SVQwOWJuVnNiQ1ltY2k1a1pXeGxkR1VvZENrc2REMUlaU2dwTEdVdWNHbHVaMlZrVEdGdVpYTjhQV1V1YzNWemNHVnVaR1ZrVEdGdVpYTW1iaXhVWlQw'
    || 'OVBXVW1KaWhRWlNadUtUMDlQVzRtSmloT1pUMDlQVFI4ZkU1bFBUMDlNeVltS0ZCbEpqRXpNREF5TXpReU5DazlQVDFRWlNZbU5UQXdQbE5sS0NrdFFXOC9i'
    || 'VzRvWlN3d0tUcEpiM3c5Ymlrc2NXVW9aU3gwS1gxbWRXNWpkR2x2YmlCaVlTaGxMSFFwZTNROVBUMHdKaVlvS0dVdWJXOWtaU1l4S1QwOVBUQS9kRDB4T2lo'
    || 'MFBVaHlMRWh5UER3OU1Td29TSEltTVRNd01ESXpOREkwS1QwOVBUQW1KaWhJY2owME1UazBNekEwS1NrcE8zWmhjaUJ1UFVobEtDazdaVDFFZENobExIUXBM'
    || 'R1VoUFQxdWRXeHNKaVlvYm5Jb1pTeDBMRzRwTEhGbEtHVXNiaWtwZldaMWJtTjBhVzl1SUhGbUtHVXBlM1poY2lCMFBXVXViV1Z0YjJsNlpXUlRkR0YwWlN4'
    || 'dVBUQTdkQ0U5UFc1MWJHd21KaWh1UFhRdWNtVjBjbmxNWVc1bEtTeGlZU2hsTEc0cGZXWjFibU4wYVc5dUlFcG1LR1VzZENsN2RtRnlJRzQ5TUR0emQybDBZ'
    || 'MmdvWlM1MFlXY3BlMk5oYzJVZ01UTTZkbUZ5SUhJOVpTNXpkR0YwWlU1dlpHVXNiRDFsTG0xbGJXOXBlbVZrVTNSaGRHVTdiQ0U5UFc1MWJHd21KaWh1UFd3'
    || 'dWNtVjBjbmxNWVc1bEtUdGljbVZoYXp0allYTmxJREU1T25JOVpTNXpkR0YwWlU1dlpHVTdZbkpsWVdzN1pHVm1ZWFZzZERwMGFISnZkeUJGY25KdmNpaGhL'
    || 'RE14TkNrcGZYSWhQVDF1ZFd4c0ppWnlMbVJsYkdWMFpTaDBLU3hpWVNobExHNHBmWFpoY2lCbFl6dGxZejFtZFc1amRHbHZiaWhsTEhRc2JpbDdhV1lvWlNF'
    || 'OVBXNTFiR3dwYVdZb1pTNXRaVzF2YVhwbFpGQnliM0J6SVQwOWRDNXdaVzVrYVc1blVISnZjSE44ZkZsbExtTjFjbkpsYm5RcFdHVTlJVEE3Wld4elpYdHBa'
    || 'aWdvWlM1c1lXNWxjeVp1S1QwOVBUQW1KaWgwTG1ac1lXZHpKakV5T0NrOVBUMHdLWEpsZEhWeWJpQllaVDBoTVN4R1ppaGxMSFFzYmlrN1dHVTlLR1V1Wm14'
    || 'aFozTW1NVE14TURjeUtTRTlQVEI5Wld4elpTQllaVDBoTVN4d1pTWW1LSFF1Wm14aFozTW1NVEEwT0RVM05pa2hQVDB3SmlaUWRTaDBMR1JzTEhRdWFXNWta'
    || 'WGdwTzNOM2FYUmphQ2gwTG14aGJtVnpQVEFzZEM1MFlXY3BlMk5oYzJVZ01qcDJZWElnY2oxMExuUjVjR1U3YW13b1pTeDBLU3hsUFhRdWNHVnVaR2x1WjFC'
    || 'eWIzQnpPM1poY2lCc1BWQnVLSFFzU1dVdVkzVnljbVZ1ZENrN1JtNG9kQ3h1S1N4c1BYQnZLRzUxYkd3c2RDeHlMR1VzYkN4dUtUdDJZWElnYVQxb2J5Z3BP'
    || 'M0psZEhWeWJpQjBMbVpzWVdkemZEMHhMSFI1Y0dWdlppQnNQVDBpYjJKcVpXTjBJaVltYkNFOVBXNTFiR3dtSm5SNWNHVnZaaUJzTG5KbGJtUmxjajA5SW1a'
    || 'MWJtTjBhVzl1SWlZbWJDNGtKSFI1Y0dWdlpqMDlQWFp2YVdRZ01EOG9kQzUwWVdjOU1TeDBMbTFsYlc5cGVtVmtVM1JoZEdVOWJuVnNiQ3gwTG5Wd1pHRjBa'
    || 'VkYxWlhWbFBXNTFiR3dzUzJVb2Npay9LR2s5SVRBc2RXd29kQ2twT21rOUlURXNkQzV0WlcxdmFYcGxaRk4wWVhSbFBXd3VjM1JoZEdVaFBUMXVkV3hzSmla'
    || 'c0xuTjBZWFJsSVQwOWRtOXBaQ0F3UDJ3dWMzUmhkR1U2Ym5Wc2JDeHBieWgwS1N4c0xuVndaR0YwWlhJOVRtd3NkQzV6ZEdGMFpVNXZaR1U5YkN4c0xsOXla'
    || 'V0ZqZEVsdWRHVnlibUZzY3oxMExGTnZLSFFzY2l4bExHNHBMSFE5VG04b2JuVnNiQ3gwTEhJc0lUQXNhU3h1S1NrNktIUXVkR0ZuUFRBc2NHVW1KbWttSmxo'
    || 'cEtIUXBMRlpsS0c1MWJHd3NkQ3hzTEc0cExIUTlkQzVqYUdsc1pDa3NkRHRqWVhObElERTJPbkk5ZEM1bGJHVnRaVzUwVkhsd1pUdGxPbnR6ZDJsMFkyZ29h'
    || 'bXdvWlN4MEtTeGxQWFF1Y0dWdVpHbHVaMUJ5YjNCekxHdzljaTVmYVc1cGRDeHlQV3dvY2k1ZmNHRjViRzloWkNrc2RDNTBlWEJsUFhJc2JEMTBMblJoWnox'
    || 'bGNDaHlLU3hsUFdkMEtISXNaU2tzYkNsN1kyRnpaU0F3T25ROVJXOG9iblZzYkN4MExISXNaU3h1S1R0aWNtVmhheUJsTzJOaGMyVWdNVHAwUFdwaEtHNTFi'
    || 'R3dzZEN4eUxHVXNiaWs3WW5KbFlXc2daVHRqWVhObElERXhPblE5ZDJFb2JuVnNiQ3gwTEhJc1pTeHVLVHRpY21WaGF5QmxPMk5oYzJVZ01UUTZkRDFmWVNo'
    || 'dWRXeHNMSFFzY2l4bmRDaHlMblI1Y0dVc1pTa3NiaWs3WW5KbFlXc2daWDEwYUhKdmR5QkZjbkp2Y2loaEtETXdOaXh5TENJaUtTbDljbVYwZFhKdUlIUTdZ'
    || 'MkZ6WlNBd09uSmxkSFZ5YmlCeVBYUXVkSGx3WlN4c1BYUXVjR1Z1WkdsdVoxQnliM0J6TEd3OWRDNWxiR1Z0Wlc1MFZIbHdaVDA5UFhJL2JEcG5kQ2h5TEd3'
    || 'cExFVnZLR1VzZEN4eUxHd3NiaWs3WTJGelpTQXhPbkpsZEhWeWJpQnlQWFF1ZEhsd1pTeHNQWFF1Y0dWdVpHbHVaMUJ5YjNCekxHdzlkQzVsYkdWdFpXNTBW'
    || 'SGx3WlQwOVBYSS9iRHBuZENoeUxHd3BMR3BoS0dVc2RDeHlMR3dzYmlrN1kyRnpaU0F6T21VNmUybG1LRU5oS0hRcExHVTlQVDF1ZFd4c0tYUm9jbTkzSUVW'
    || 'eWNtOXlLR0VvTXpnM0tTazdjajEwTG5CbGJtUnBibWRRY205d2N5eHBQWFF1YldWdGIybDZaV1JUZEdGMFpTeHNQV2t1Wld4bGJXVnVkQ3hXZFNobExIUXBM'
    || 'R2RzS0hRc2NpeHVkV3hzTEc0cE8zWmhjaUJ6UFhRdWJXVnRiMmw2WldSVGRHRjBaVHRwWmloeVBYTXVaV3hsYldWdWRDeHBMbWx6UkdWb2VXUnlZWFJsWkNs'
    || 'cFppaHBQWHRsYkdWdFpXNTBPbklzYVhORVpXaDVaSEpoZEdWa09pRXhMR05oWTJobE9uTXVZMkZqYUdVc2NHVnVaR2x1WjFOMWMzQmxibk5sUW05MWJtUmhj'
    || 'bWxsY3pwekxuQmxibVJwYm1kVGRYTndaVzV6WlVKdmRXNWtZWEpwWlhNc2RISmhibk5wZEdsdmJuTTZjeTUwY21GdWMybDBhVzl1YzMwc2RDNTFjR1JoZEdW'
    || 'UmRXVjFaUzVpWVhObFUzUmhkR1U5YVN4MExtMWxiVzlwZW1Wa1UzUmhkR1U5YVN4MExtWnNZV2R6SmpJMU5pbDdiRDBrYmloRmNuSnZjaWhoS0RReU15a3BM'
    || 'SFFwTEhROVZHRW9aU3gwTEhJc2JpeHNLVHRpY21WaGF5QmxmV1ZzYzJVZ2FXWW9jaUU5UFd3cGUydzlKRzRvUlhKeWIzSW9ZU2cwTWpRcEtTeDBLU3gwUFZS'
    || 'aEtHVXNkQ3h5TEc0c2JDazdZbkpsWVdzZ1pYMWxiSE5sSUdadmNpaHNkRDFDZENoMExuTjBZWFJsVG05a1pTNWpiMjUwWVdsdVpYSkpibVp2TG1acGNuTjBR'
    || 'MmhwYkdRcExISjBQWFFzY0dVOUlUQXNkblE5Ym5Wc2JDeHVQVmQxS0hRc2JuVnNiQ3h5TEc0cExIUXVZMmhwYkdROWJqdHVPeWx1TG1ac1lXZHpQVzR1Wm14'
    || 'aFozTW1MVE44TkRBNU5peHVQVzR1YzJsaWJHbHVaenRsYkhObGUybG1LRUZ1S0Nrc2NqMDlQV3dwZTNROVRIUW9aU3gwTEc0cE8ySnlaV0ZySUdWOVZtVW9a'
    || 'U3gwTEhJc2JpbDlkRDEwTG1Ob2FXeGtmWEpsZEhWeWJpQjBPMk5oYzJVZ05UcHlaWFIxY200Z1VYVW9kQ2tzWlQwOVBXNTFiR3dtSmtwcEtIUXBMSEk5ZEM1'
    || 'MGVYQmxMR3c5ZEM1d1pXNWthVzVuVUhKdmNITXNhVDFsSVQwOWJuVnNiRDlsTG0xbGJXOXBlbVZrVUhKdmNITTZiblZzYkN4elBXd3VZMmhwYkdSeVpXNHNT'
    || 'R2tvY2l4c0tUOXpQVzUxYkd3NmFTRTlQVzUxYkd3bUpraHBLSElzYVNrbUppaDBMbVpzWVdkemZEMHpNaWtzYTJFb1pTeDBLU3hXWlNobExIUXNjeXh1S1N4'
    || 'MExtTm9hV3hrTzJOaGMyVWdOanB5WlhSMWNtNGdaVDA5UFc1MWJHd21Ka3BwS0hRcExHNTFiR3c3WTJGelpTQXhNenB5WlhSMWNtNGdVbUVvWlN4MExHNHBP'
    || 'Mk5oYzJVZ05EcHlaWFIxY200Z2IyOG9kQ3gwTG5OMFlYUmxUbTlrWlM1amIyNTBZV2x1WlhKSmJtWnZLU3h5UFhRdWNHVnVaR2x1WjFCeWIzQnpMR1U5UFQx'
    || 'dWRXeHNQM1F1WTJocGJHUTllbTRvZEN4dWRXeHNMSElzYmlrNlZtVW9aU3gwTEhJc2Jpa3NkQzVqYUdsc1pEdGpZWE5sSURFeE9uSmxkSFZ5YmlCeVBYUXVk'
    || 'SGx3WlN4c1BYUXVjR1Z1WkdsdVoxQnliM0J6TEd3OWRDNWxiR1Z0Wlc1MFZIbHdaVDA5UFhJL2JEcG5kQ2h5TEd3cExIZGhLR1VzZEN4eUxHd3NiaWs3WTJG'
    || 'elpTQTNPbkpsZEhWeWJpQldaU2hsTEhRc2RDNXdaVzVrYVc1blVISnZjSE1zYmlrc2RDNWphR2xzWkR0allYTmxJRGc2Y21WMGRYSnVJRlpsS0dVc2RDeDBM'
    || 'bkJsYm1ScGJtZFFjbTl3Y3k1amFHbHNaSEpsYml4dUtTeDBMbU5vYVd4a08yTmhjMlVnTVRJNmNtVjBkWEp1SUZabEtHVXNkQ3gwTG5CbGJtUnBibWRRY205'
    || 'd2N5NWphR2xzWkhKbGJpeHVLU3gwTG1Ob2FXeGtPMk5oYzJVZ01UQTZaVHA3YVdZb2NqMTBMblI1Y0dVdVgyTnZiblJsZUhRc2JEMTBMbkJsYm1ScGJtZFFj'
    || 'bTl3Y3l4cFBYUXViV1Z0YjJsNlpXUlFjbTl3Y3l4elBXd3VkbUZzZFdVc2MyVW9hR3dzY2k1ZlkzVnljbVZ1ZEZaaGJIVmxLU3h5TGw5amRYSnlaVzUwVm1G'
    || 'c2RXVTljeXhwSVQwOWJuVnNiQ2xwWmlodGRDaHBMblpoYkhWbExITXBLWHRwWmlocExtTm9hV3hrY21WdVBUMDliQzVqYUdsc1pISmxiaVltSVZsbExtTjFj'
    || 'bkpsYm5RcGUzUTlUSFFvWlN4MExHNHBPMkp5WldGcklHVjlmV1ZzYzJVZ1ptOXlLR2s5ZEM1amFHbHNaQ3hwSVQwOWJuVnNiQ1ltS0drdWNtVjBkWEp1UFhR'
    || 'cE8ya2hQVDF1ZFd4c095bDdkbUZ5SUdNOWFTNWtaWEJsYm1SbGJtTnBaWE03YVdZb1l5RTlQVzUxYkd3cGUzTTlhUzVqYUdsc1pEdG1iM0lvZG1GeUlHWTlZ'
    || 'eTVtYVhKemRFTnZiblJsZUhRN1ppRTlQVzUxYkd3N0tYdHBaaWhtTG1OdmJuUmxlSFE5UFQxeUtYdHBaaWhwTG5SaFp6MDlQVEVwZTJZOVVIUW9MVEVzYmlZ'
    || 'dGJpa3NaaTUwWVdjOU1qdDJZWElnZVQxcExuVndaR0YwWlZGMVpYVmxPMmxtS0hraFBUMXVkV3hzS1h0NVBYa3VjMmhoY21Wa08zWmhjaUJxUFhrdWNHVnVa'
    || 'R2x1Wnp0cVBUMDliblZzYkQ5bUxtNWxlSFE5Wmpvb1ppNXVaWGgwUFdvdWJtVjRkQ3hxTG01bGVIUTlaaWtzZVM1d1pXNWthVzVuUFdaOWZXa3ViR0Z1WlhO'
    || 'OFBXNHNaajFwTG1Gc2RHVnlibUYwWlN4bUlUMDliblZzYkNZbUtHWXViR0Z1WlhOOFBXNHBMSEp2S0drdWNtVjBkWEp1TEc0c2RDa3NZeTVzWVc1bGMzdzli'
    || 'anRpY21WaGEzMW1QV1l1Ym1WNGRIMTlaV3h6WlNCcFppaHBMblJoWnowOVBURXdLWE05YVM1MGVYQmxQVDA5ZEM1MGVYQmxQMjUxYkd3NmFTNWphR2xzWkR0'
    || 'bGJITmxJR2xtS0drdWRHRm5QVDA5TVRncGUybG1LSE05YVM1eVpYUjFjbTRzY3owOVBXNTFiR3dwZEdoeWIzY2dSWEp5YjNJb1lTZ3pOREVwS1R0ekxteGhi'
    || 'bVZ6ZkQxdUxHTTljeTVoYkhSbGNtNWhkR1VzWXlFOVBXNTFiR3dtSmloakxteGhibVZ6ZkQxdUtTeHlieWh6TEc0c2RDa3NjejFwTG5OcFlteHBibWQ5Wld4'
    || 'elpTQnpQV2t1WTJocGJHUTdhV1lvY3lFOVBXNTFiR3dwY3k1eVpYUjFjbTQ5YVR0bGJITmxJR1p2Y2loelBXazdjeUU5UFc1MWJHdzdLWHRwWmloelBUMDlk'
    || 'Q2w3Y3oxdWRXeHNPMkp5WldGcmZXbG1LR2s5Y3k1emFXSnNhVzVuTEdraFBUMXVkV3hzS1h0cExuSmxkSFZ5YmoxekxuSmxkSFZ5Yml4elBXazdZbkpsWVd0'
    || 'OWN6MXpMbkpsZEhWeWJuMXBQWE45Vm1Vb1pTeDBMR3d1WTJocGJHUnlaVzRzYmlrc2REMTBMbU5vYVd4a2ZYSmxkSFZ5YmlCME8yTmhjMlVnT1RweVpYUjFj'
    || 'bTRnYkQxMExuUjVjR1VzY2oxMExuQmxibVJwYm1kUWNtOXdjeTVqYUdsc1pISmxiaXhHYmloMExHNHBMR3c5ZFhRb2JDa3NjajF5S0d3cExIUXVabXhoWjNO'
    || 'OFBURXNWbVVvWlN4MExISXNiaWtzZEM1amFHbHNaRHRqWVhObElERTBPbkpsZEhWeWJpQnlQWFF1ZEhsd1pTeHNQV2QwS0hJc2RDNXdaVzVrYVc1blVISnZj'
    || 'SE1wTEd3OVozUW9jaTUwZVhCbExHd3BMRjloS0dVc2RDeHlMR3dzYmlrN1kyRnpaU0F4TlRweVpYUjFjbTRnUldFb1pTeDBMSFF1ZEhsd1pTeDBMbkJsYm1S'
    || 'cGJtZFFjbTl3Y3l4dUtUdGpZWE5sSURFM09uSmxkSFZ5YmlCeVBYUXVkSGx3WlN4c1BYUXVjR1Z1WkdsdVoxQnliM0J6TEd3OWRDNWxiR1Z0Wlc1MFZIbHda'
    || 'VDA5UFhJL2JEcG5kQ2h5TEd3cExHcHNLR1VzZENrc2RDNTBZV2M5TVN4TFpTaHlLVDhvWlQwaE1DeDFiQ2gwS1NrNlpUMGhNU3hHYmloMExHNHBMR2hoS0hR'
    || 'c2NpeHNLU3hUYnloMExISXNiQ3h1S1N4T2J5aHVkV3hzTEhRc2Npd2hNQ3hsTEc0cE8yTmhjMlVnTVRrNmNtVjBkWEp1SUUxaEtHVXNkQ3h1S1R0allYTmxJ'
    || 'REl5T25KbGRIVnliaUJPWVNobExIUXNiaWw5ZEdoeWIzY2dSWEp5YjNJb1lTZ3hOVFlzZEM1MFlXY3BLWDA3Wm5WdVkzUnBiMjRnZEdNb1pTeDBLWHR5WlhS'
    || 'MWNtNGdUSE1vWlN4MEtYMW1kVzVqZEdsdmJpQmlaaWhsTEhRc2JpeHlLWHQwYUdsekxuUmhaejFsTEhSb2FYTXVhMlY1UFc0c2RHaHBjeTV6YVdKc2FXNW5Q'
    || 'WFJvYVhNdVkyaHBiR1E5ZEdocGN5NXlaWFIxY200OWRHaHBjeTV6ZEdGMFpVNXZaR1U5ZEdocGN5NTBlWEJsUFhSb2FYTXVaV3hsYldWdWRGUjVjR1U5Ym5W'
    || 'c2JDeDBhR2x6TG1sdVpHVjRQVEFzZEdocGN5NXlaV1k5Ym5Wc2JDeDBhR2x6TG5CbGJtUnBibWRRY205d2N6MTBMSFJvYVhNdVpHVndaVzVrWlc1amFXVnpQ'
    || 'WFJvYVhNdWJXVnRiMmw2WldSVGRHRjBaVDEwYUdsekxuVndaR0YwWlZGMVpYVmxQWFJvYVhNdWJXVnRiMmw2WldSUWNtOXdjejF1ZFd4c0xIUm9hWE11Ylc5'
    || 'a1pUMXlMSFJvYVhNdWMzVmlkSEpsWlVac1lXZHpQWFJvYVhNdVpteGhaM005TUN4MGFHbHpMbVJsYkdWMGFXOXVjejF1ZFd4c0xIUm9hWE11WTJocGJHUk1Z'
    || 'VzVsY3oxMGFHbHpMbXhoYm1WelBUQXNkR2hwY3k1aGJIUmxjbTVoZEdVOWJuVnNiSDFtZFc1amRHbHZiaUJrZENobExIUXNiaXh5S1h0eVpYUjFjbTRnYm1W'
    || 'M0lHSm1LR1VzZEN4dUxISXBmV1oxYm1OMGFXOXVJRUp2S0dVcGUzSmxkSFZ5YmlCbFBXVXVjSEp2ZEc5MGVYQmxMQ0VvSVdWOGZDRmxMbWx6VW1WaFkzUkRi'
    || 'MjF3YjI1bGJuUXBmV1oxYm1OMGFXOXVJR1Z3S0dVcGUybG1LSFI1Y0dWdlppQmxQVDBpWm5WdVkzUnBiMjRpS1hKbGRIVnliaUJDYnlobEtUOHhPakE3YVdZ'
    || 'b1pTRTliblZzYkNsN2FXWW9aVDFsTGlRa2RIbHdaVzltTEdVOVBUMGtaU2x5WlhSMWNtNGdNVEU3YVdZb1pUMDlQWGQwS1hKbGRIVnliaUF4TkgxeVpYUjFj'
    || 'bTRnTW4xbWRXNWpkR2x2YmlCMGJpaGxMSFFwZTNaaGNpQnVQV1V1WVd4MFpYSnVZWFJsTzNKbGRIVnliaUJ1UFQwOWJuVnNiRDhvYmoxa2RDaGxMblJoWnl4'
    || 'MExHVXVhMlY1TEdVdWJXOWtaU2tzYmk1bGJHVnRaVzUwVkhsd1pUMWxMbVZzWlcxbGJuUlVlWEJsTEc0dWRIbHdaVDFsTG5SNWNHVXNiaTV6ZEdGMFpVNXZa'
    || 'R1U5WlM1emRHRjBaVTV2WkdVc2JpNWhiSFJsY201aGRHVTlaU3hsTG1Gc2RHVnlibUYwWlQxdUtUb29iaTV3Wlc1a2FXNW5VSEp2Y0hNOWRDeHVMblI1Y0dV'
    || 'OVpTNTBlWEJsTEc0dVpteGhaM005TUN4dUxuTjFZblJ5WldWR2JHRm5jejB3TEc0dVpHVnNaWFJwYjI1elBXNTFiR3dwTEc0dVpteGhaM005WlM1bWJHRm5j'
    || 'eVl4TkRZNE1EQTJOQ3h1TG1Ob2FXeGtUR0Z1WlhNOVpTNWphR2xzWkV4aGJtVnpMRzR1YkdGdVpYTTlaUzVzWVc1bGN5eHVMbU5vYVd4a1BXVXVZMmhwYkdR'
    || 'c2JpNXRaVzF2YVhwbFpGQnliM0J6UFdVdWJXVnRiMmw2WldSUWNtOXdjeXh1TG0xbGJXOXBlbVZrVTNSaGRHVTlaUzV0WlcxdmFYcGxaRk4wWVhSbExHNHVk'
    || 'WEJrWVhSbFVYVmxkV1U5WlM1MWNHUmhkR1ZSZFdWMVpTeDBQV1V1WkdWd1pXNWtaVzVqYVdWekxHNHVaR1Z3Wlc1a1pXNWphV1Z6UFhROVBUMXVkV3hzUDI1'
    || 'MWJHdzZlMnhoYm1Wek9uUXViR0Z1WlhNc1ptbHljM1JEYjI1MFpYaDBPblF1Wm1seWMzUkRiMjUwWlhoMGZTeHVMbk5wWW14cGJtYzlaUzV6YVdKc2FXNW5M'
    || 'RzR1YVc1a1pYZzlaUzVwYm1SbGVDeHVMbkpsWmoxbExuSmxaaXh1ZldaMWJtTjBhVzl1SUhwc0tHVXNkQ3h1TEhJc2JDeHBLWHQyWVhJZ2N6MHlPMmxtS0hJ'
    || 'OVpTeDBlWEJsYjJZZ1pUMDlJbVoxYm1OMGFXOXVJaWxDYnlobEtTWW1LSE05TVNrN1pXeHpaU0JwWmloMGVYQmxiMllnWlQwOUluTjBjbWx1WnlJcGN6MDFP'
    || 'MlZzYzJVZ1pUcHpkMmwwWTJnb1pTbDdZMkZ6WlNCalpUcHlaWFIxY200Z1oyNG9iaTVqYUdsc1pISmxiaXhzTEdrc2RDazdZMkZ6WlNCa1pUcHpQVGdzYkh3'
    || 'OU9EdGljbVZoYXp0allYTmxJSEpsT25KbGRIVnliaUJsUFdSMEtERXlMRzRzZEN4c2ZESXBMR1V1Wld4bGJXVnVkRlI1Y0dVOWNtVXNaUzVzWVc1bGN6MXBM'
    || 'R1U3WTJGelpTQmxkRHB5WlhSMWNtNGdaVDFrZENneE15eHVMSFFzYkNrc1pTNWxiR1Z0Wlc1MFZIbHdaVDFsZEN4bExteGhibVZ6UFdrc1pUdGpZWE5sSUhC'
    || 'ME9uSmxkSFZ5YmlCbFBXUjBLREU1TEc0c2RDeHNLU3hsTG1Wc1pXMWxiblJVZVhCbFBYQjBMR1V1YkdGdVpYTTlhU3hsTzJOaGMyVWdaMlU2Y21WMGRYSnVJ'
    || 'RlZzS0c0c2JDeHBMSFFwTzJSbFptRjFiSFE2YVdZb2RIbHdaVzltSUdVOVBTSnZZbXBsWTNRaUppWmxJVDA5Ym5Wc2JDbHpkMmwwWTJnb1pTNGtKSFI1Y0dW'
    || 'dlppbDdZMkZ6WlNCS1pUcHpQVEV3TzJKeVpXRnJJR1U3WTJGelpTQmlaVHB6UFRrN1luSmxZV3NnWlR0allYTmxJQ1JsT25NOU1URTdZbkpsWVdzZ1pUdGpZ'
    || 'WE5sSUhkME9uTTlNVFE3WW5KbFlXc2daVHRqWVhObElFZGxPbk05TVRZc2NqMXVkV3hzTzJKeVpXRnJJR1Y5ZEdoeWIzY2dSWEp5YjNJb1lTZ3hNekFzWlQw'
    || 'OWJuVnNiRDlsT25SNWNHVnZaaUJsTENJaUtTbDljbVYwZFhKdUlIUTlaSFFvY3l4dUxIUXNiQ2tzZEM1bGJHVnRaVzUwVkhsd1pUMWxMSFF1ZEhsd1pUMXlM'
    || 'SFF1YkdGdVpYTTlhU3gwZldaMWJtTjBhVzl1SUdkdUtHVXNkQ3h1TEhJcGUzSmxkSFZ5YmlCbFBXUjBLRGNzWlN4eUxIUXBMR1V1YkdGdVpYTTliaXhsZlda'
    || 'MWJtTjBhVzl1SUZWc0tHVXNkQ3h1TEhJcGUzSmxkSFZ5YmlCbFBXUjBLREl5TEdVc2NpeDBLU3hsTG1Wc1pXMWxiblJVZVhCbFBXZGxMR1V1YkdGdVpYTTli'
    || 'aXhsTG5OMFlYUmxUbTlrWlQxN2FYTklhV1JrWlc0NklURjlMR1Y5Wm5WdVkzUnBiMjRnVVc4b1pTeDBMRzRwZTNKbGRIVnliaUJsUFdSMEtEWXNaU3h1ZFd4'
    || 'c0xIUXBMR1V1YkdGdVpYTTliaXhsZldaMWJtTjBhVzl1SUVkdktHVXNkQ3h1S1h0eVpYUjFjbTRnZEQxa2RDZzBMR1V1WTJocGJHUnlaVzRoUFQxdWRXeHNQ'
    || 'MlV1WTJocGJHUnlaVzQ2VzEwc1pTNXJaWGtzZENrc2RDNXNZVzVsY3oxdUxIUXVjM1JoZEdWT2IyUmxQWHRqYjI1MFlXbHVaWEpKYm1adk9tVXVZMjl1ZEdG'
    || 'cGJtVnlTVzVtYnl4d1pXNWthVzVuUTJocGJHUnlaVzQ2Ym5Wc2JDeHBiWEJzWlcxbGJuUmhkR2x2YmpwbExtbHRjR3hsYldWdWRHRjBhVzl1ZlN4MGZXWjFi'
    || 'bU4wYVc5dUlIUndLR1VzZEN4dUxISXNiQ2w3ZEdocGN5NTBZV2M5ZEN4MGFHbHpMbU52Ym5SaGFXNWxja2x1Wm04OVpTeDBhR2x6TG1acGJtbHphR1ZrVjI5'
    || 'eWF6MTBhR2x6TG5CcGJtZERZV05vWlQxMGFHbHpMbU4xY25KbGJuUTlkR2hwY3k1d1pXNWthVzVuUTJocGJHUnlaVzQ5Ym5Wc2JDeDBhR2x6TG5ScGJXVnZk'
    || 'WFJJWVc1a2JHVTlMVEVzZEdocGN5NWpZV3hzWW1GamEwNXZaR1U5ZEdocGN5NXdaVzVrYVc1blEyOXVkR1Y0ZEQxMGFHbHpMbU52Ym5SbGVIUTliblZzYkN4'
    || 'MGFHbHpMbU5oYkd4aVlXTnJVSEpwYjNKcGRIazlNQ3gwYUdsekxtVjJaVzUwVkdsdFpYTTllV2tvTUNrc2RHaHBjeTVsZUhCcGNtRjBhVzl1VkdsdFpYTTll'
    || 'V2tvTFRFcExIUm9hWE11Wlc1MFlXNW5iR1ZrVEdGdVpYTTlkR2hwY3k1bWFXNXBjMmhsWkV4aGJtVnpQWFJvYVhNdWJYVjBZV0pzWlZKbFlXUk1ZVzVsY3ox'
    || 'MGFHbHpMbVY0Y0dseVpXUk1ZVzVsY3oxMGFHbHpMbkJwYm1kbFpFeGhibVZ6UFhSb2FYTXVjM1Z6Y0dWdVpHVmtUR0Z1WlhNOWRHaHBjeTV3Wlc1a2FXNW5U'
    || 'R0Z1WlhNOU1DeDBhR2x6TG1WdWRHRnVaMnhsYldWdWRITTllV2tvTUNrc2RHaHBjeTVwWkdWdWRHbG1hV1Z5VUhKbFptbDRQWElzZEdocGN5NXZibEpsWTI5'
    || 'MlpYSmhZbXhsUlhKeWIzSTliQ3gwYUdsekxtMTFkR0ZpYkdWVGIzVnlZMlZGWVdkbGNraDVaSEpoZEdsdmJrUmhkR0U5Ym5Wc2JIMW1kVzVqZEdsdmJpQlpi'
    || 'eWhsTEhRc2JpeHlMR3dzYVN4ekxHTXNaaWw3Y21WMGRYSnVJR1U5Ym1WM0lIUndLR1VzZEN4dUxHTXNaaWtzZEQwOVBURS9LSFE5TVN4cFBUMDlJVEFtSmlo'
    || 'MGZEMDRLU2s2ZEQwd0xHazlaSFFvTXl4dWRXeHNMRzUxYkd3c2RDa3NaUzVqZFhKeVpXNTBQV2tzYVM1emRHRjBaVTV2WkdVOVpTeHBMbTFsYlc5cGVtVmtV'
    || 'M1JoZEdVOWUyVnNaVzFsYm5RNmNpeHBjMFJsYUhsa2NtRjBaV1E2Yml4allXTm9aVHB1ZFd4c0xIUnlZVzV6YVhScGIyNXpPbTUxYkd3c2NHVnVaR2x1WjFO'
    || 'MWMzQmxibk5sUW05MWJtUmhjbWxsY3pwdWRXeHNmU3hwYnlocEtTeGxmV1oxYm1OMGFXOXVJRzV3S0dVc2RDeHVLWHQyWVhJZ2NqMHpQR0Z5WjNWdFpXNTBj'
    || 'eTVzWlc1bmRHZ21KbUZ5WjNWdFpXNTBjMXN6WFNFOVBYWnZhV1FnTUQ5aGNtZDFiV1Z1ZEhOYk0xMDZiblZzYkR0eVpYUjFjbTU3SkNSMGVYQmxiMlk2ZUdV'
    || 'c2EyVjVPbkk5UFc1MWJHdy9iblZzYkRvaUlpdHlMR05vYVd4a2NtVnVPbVVzWTI5dWRHRnBibVZ5U1c1bWJ6cDBMR2x0Y0d4bGJXVnVkR0YwYVc5dU9tNTlm'
    || 'V1oxYm1OMGFXOXVJRzVqS0dVcGUybG1LQ0ZsS1hKbGRIVnliaUJIZER0bFBXVXVYM0psWVdOMFNXNTBaWEp1WVd4ek8yVTZlMmxtS0d4dUtHVXBJVDA5Wlh4'
    || 'OFpTNTBZV2NoUFQweEtYUm9jbTkzSUVWeWNtOXlLR0VvTVRjd0tTazdkbUZ5SUhROVpUdGtiM3R6ZDJsMFkyZ29kQzUwWVdjcGUyTmhjMlVnTXpwMFBYUXVj'
    || 'M1JoZEdWT2IyUmxMbU52Ym5SbGVIUTdZbkpsWVdzZ1pUdGpZWE5sSURFNmFXWW9TMlVvZEM1MGVYQmxLU2w3ZEQxMExuTjBZWFJsVG05a1pTNWZYM0psWVdO'
    || 'MFNXNTBaWEp1WVd4TlpXMXZhWHBsWkUxbGNtZGxaRU5vYVd4a1EyOXVkR1Y0ZER0aWNtVmhheUJsZlgxMFBYUXVjbVYwZFhKdWZYZG9hV3hsS0hRaFBUMXVk'
    || 'V3hzS1R0MGFISnZkeUJGY25KdmNpaGhLREUzTVNrcGZXbG1LR1V1ZEdGblBUMDlNU2w3ZG1GeUlHNDlaUzUwZVhCbE8ybG1LRXRsS0c0cEtYSmxkSFZ5YmlC'
    || 'UGRTaGxMRzRzZENsOWNtVjBkWEp1SUhSOVpuVnVZM1JwYjI0Z2NtTW9aU3gwTEc0c2NpeHNMR2tzY3l4akxHWXBlM0psZEhWeWJpQmxQVmx2S0c0c2Npd2hN'
    || 'Q3hsTEd3c2FTeHpMR01zWmlrc1pTNWpiMjUwWlhoMFBXNWpLRzUxYkd3cExHNDlaUzVqZFhKeVpXNTBMSEk5U0dVb0tTeHNQV0owS0c0cExHazlVSFFvY2l4'
    || 'c0tTeHBMbU5oYkd4aVlXTnJQWFEvUDI1MWJHd3NXSFFvYml4cExHd3BMR1V1WTNWeWNtVnVkQzVzWVc1bGN6MXNMRzV5S0dVc2JDeHlLU3h4WlNobExISXBM'
    || 'R1Y5Wm5WdVkzUnBiMjRnUm13b1pTeDBMRzRzY2lsN2RtRnlJR3c5ZEM1amRYSnlaVzUwTEdrOVNHVW9LU3h6UFdKMEtHd3BPM0psZEhWeWJpQnVQVzVqS0c0'
    || 'cExIUXVZMjl1ZEdWNGREMDlQVzUxYkd3L2RDNWpiMjUwWlhoMFBXNDZkQzV3Wlc1a2FXNW5RMjl1ZEdWNGREMXVMSFE5VUhRb2FTeHpLU3gwTG5CaGVXeHZZ'
    || 'V1E5ZTJWc1pXMWxiblE2Wlgwc2NqMXlQVDA5ZG05cFpDQXdQMjUxYkd3NmNpeHlJVDA5Ym5Wc2JDWW1LSFF1WTJGc2JHSmhZMnM5Y2lrc1pUMVlkQ2hzTEhR'
    || 'c2N5a3NaU0U5UFc1MWJHd21KaWhUZENobExHd3NjeXhwS1N4MmJDaGxMR3dzY3lrcExITjlablZ1WTNScGIyNGdWMndvWlNsN2FXWW9aVDFsTG1OMWNuSmxi'
    || 'blFzSVdVdVkyaHBiR1FwY21WMGRYSnVJRzUxYkd3N2MzZHBkR05vS0dVdVkyaHBiR1F1ZEdGbktYdGpZWE5sSURVNmNtVjBkWEp1SUdVdVkyaHBiR1F1YzNS'
    || 'aGRHVk9iMlJsTzJSbFptRjFiSFE2Y21WMGRYSnVJR1V1WTJocGJHUXVjM1JoZEdWT2IyUmxmWDFtZFc1amRHbHZiaUJzWXlobExIUXBlMmxtS0dVOVpTNXRa'
    || 'VzF2YVhwbFpGTjBZWFJsTEdVaFBUMXVkV3hzSmlabExtUmxhSGxrY21GMFpXUWhQVDF1ZFd4c0tYdDJZWElnYmoxbExuSmxkSEo1VEdGdVpUdGxMbkpsZEhK'
    || 'NVRHRnVaVDF1SVQwOU1DWW1iangwUDI0NmRIMTlablZ1WTNScGIyNGdTMjhvWlN4MEtYdHNZeWhsTEhRcExDaGxQV1V1WVd4MFpYSnVZWFJsS1NZbWJHTW9a'
    || 'U3gwS1gxbWRXNWpkR2x2YmlCeWNDZ3BlM0psZEhWeWJpQnVkV3hzZlhaaGNpQnBZejEwZVhCbGIyWWdjbVZ3YjNKMFJYSnliM0k5UFNKbWRXNWpkR2x2YmlJ'
    || 'L2NtVndiM0owUlhKeWIzSTZablZ1WTNScGIyNG9aU2w3WTI5dWMyOXNaUzVsY25KdmNpaGxLWDA3Wm5WdVkzUnBiMjRnV0c4b1pTbDdkR2hwY3k1ZmFXNTBa'
    || 'WEp1WVd4U2IyOTBQV1Y5Skd3dWNISnZkRzkwZVhCbExuSmxibVJsY2oxWWJ5NXdjbTkwYjNSNWNHVXVjbVZ1WkdWeVBXWjFibU4wYVc5dUtHVXBlM1poY2lC'
    || 'MFBYUm9hWE11WDJsdWRHVnlibUZzVW05dmREdHBaaWgwUFQwOWJuVnNiQ2wwYUhKdmR5QkZjbkp2Y2loaEtEUXdPU2twTzBac0tHVXNkQ3h1ZFd4c0xHNTFi'
    || 'R3dwZlN3a2JDNXdjbTkwYjNSNWNHVXVkVzV0YjNWdWREMVlieTV3Y205MGIzUjVjR1V1ZFc1dGIzVnVkRDFtZFc1amRHbHZiaWdwZTNaaGNpQmxQWFJvYVhN'
    || 'dVgybHVkR1Z5Ym1Gc1VtOXZkRHRwWmlobElUMDliblZzYkNsN2RHaHBjeTVmYVc1MFpYSnVZV3hTYjI5MFBXNTFiR3c3ZG1GeUlIUTlaUzVqYjI1MFlXbHVa'
    || 'WEpKYm1adk8yaHVLR1oxYm1OMGFXOXVLQ2w3Um13b2JuVnNiQ3hsTEc1MWJHd3NiblZzYkNsOUtTeDBXMVIwWFQxdWRXeHNmWDA3Wm5WdVkzUnBiMjRnSkd3'
    || 'b1pTbDdkR2hwY3k1ZmFXNTBaWEp1WVd4U2IyOTBQV1Y5Skd3dWNISnZkRzkwZVhCbExuVnVjM1JoWW14bFgzTmphR1ZrZFd4bFNIbGtjbUYwYVc5dVBXWjFi'
    || 'bU4wYVc5dUtHVXBlMmxtS0dVcGUzWmhjaUIwUFZaektDazdaVDE3WW14dlkydGxaRTl1T201MWJHd3NkR0Z5WjJWME9tVXNjSEpwYjNKcGRIazZkSDA3Wm05'
    || 'eUtIWmhjaUJ1UFRBN2Jqd2tkQzVzWlc1bmRHZ21KblFoUFQwd0ppWjBQQ1IwVzI1ZExuQnlhVzl5YVhSNU8yNHJLeWs3SkhRdWMzQnNhV05sS0c0c01DeGxL'
    || 'U3h1UFQwOU1DWW1VWE1vWlNsOWZUdG1kVzVqZEdsdmJpQmFieWhsS1h0eVpYUjFjbTRoS0NGbGZIeGxMbTV2WkdWVWVYQmxJVDA5TVNZbVpTNXViMlJsVkhs'
    || 'd1pTRTlQVGttSm1VdWJtOWtaVlI1Y0dVaFBUMHhNU2w5Wm5WdVkzUnBiMjRnVm13b1pTbDdjbVYwZFhKdUlTZ2haWHg4WlM1dWIyUmxWSGx3WlNFOVBURW1K'
    || 'bVV1Ym05a1pWUjVjR1VoUFQwNUppWmxMbTV2WkdWVWVYQmxJVDA5TVRFbUppaGxMbTV2WkdWVWVYQmxJVDA5T0h4OFpTNXViMlJsVm1Gc2RXVWhQVDBpSUhK'
    || 'bFlXTjBMVzF2ZFc1MExYQnZhVzUwTFhWdWMzUmhZbXhsSUNJcEtYMW1kVzVqZEdsdmJpQnZZeWdwZTMxbWRXNWpkR2x2YmlCc2NDaGxMSFFzYml4eUxHd3Bl'
    || 'MmxtS0d3cGUybG1LSFI1Y0dWdlppQnlQVDBpWm5WdVkzUnBiMjRpS1h0MllYSWdhVDF5TzNJOVpuVnVZM1JwYjI0b0tYdDJZWElnZVQxWGJDaHpLVHRwTG1O'
    || 'aGJHd29lU2w5ZlhaaGNpQnpQWEpqS0hRc2NpeGxMREFzYm5Wc2JDd2hNU3doTVN3aUlpeHZZeWs3Y21WMGRYSnVJR1V1WDNKbFlXTjBVbTl2ZEVOdmJuUmhh'
    || 'VzVsY2oxekxHVmJWSFJkUFhNdVkzVnljbVZ1ZEN4MmNpaGxMbTV2WkdWVWVYQmxQVDA5T0Q5bExuQmhjbVZ1ZEU1dlpHVTZaU2tzYUc0b0tTeHpmV1p2Y2ln'
    || 'N2JEMWxMbXhoYzNSRGFHbHNaRHNwWlM1eVpXMXZkbVZEYUdsc1pDaHNLVHRwWmloMGVYQmxiMllnY2owOUltWjFibU4wYVc5dUlpbDdkbUZ5SUdNOWNqdHlQ'
    || 'V1oxYm1OMGFXOXVLQ2w3ZG1GeUlIazlWMndvWmlrN1l5NWpZV3hzS0hrcGZYMTJZWElnWmoxWmJ5aGxMREFzSVRFc2JuVnNiQ3h1ZFd4c0xDRXhMQ0V4TENJ'
    || 'aUxHOWpLVHR5WlhSMWNtNGdaUzVmY21WaFkzUlNiMjkwUTI5dWRHRnBibVZ5UFdZc1pWdFVkRjA5Wmk1amRYSnlaVzUwTEhaeUtHVXVibTlrWlZSNWNHVTlQ'
    || 'VDA0UDJVdWNHRnlaVzUwVG05a1pUcGxLU3hvYmlobWRXNWpkR2x2YmlncGUwWnNLSFFzWml4dUxISXBmU2tzWm4xbWRXNWpkR2x2YmlCSWJDaGxMSFFzYml4'
    || 'eUxHd3BlM1poY2lCcFBXNHVYM0psWVdOMFVtOXZkRU52Ym5SaGFXNWxjanRwWmlocEtYdDJZWElnY3oxcE8ybG1LSFI1Y0dWdlppQnNQVDBpWm5WdVkzUnBi'
    || 'MjRpS1h0MllYSWdZejFzTzJ3OVpuVnVZM1JwYjI0b0tYdDJZWElnWmoxWGJDaHpLVHRqTG1OaGJHd29aaWw5ZlVac0tIUXNjeXhsTEd3cGZXVnNjMlVnY3ox'
    || 'c2NDaHVMSFFzWlN4c0xISXBPM0psZEhWeWJpQlhiQ2h6S1gxWGN6MW1kVzVqZEdsdmJpaGxLWHR6ZDJsMFkyZ29aUzUwWVdjcGUyTmhjMlVnTXpwMllYSWdk'
    || 'RDFsTG5OMFlYUmxUbTlrWlR0cFppaDBMbU4xY25KbGJuUXViV1Z0YjJsNlpXUlRkR0YwWlM1cGMwUmxhSGxrY21GMFpXUXBlM1poY2lCdVBYUnlLSFF1Y0dW'
    || 'dVpHbHVaMHhoYm1WektUdHVJVDA5TUNZbUtIaHBLSFFzYm53eEtTeHhaU2gwTEZObEtDa3BMQ2hpSmpZcFBUMDlNQ1ltS0VKdVBWTmxLQ2tyTlRBd0xGbDBL'
    || 'Q2twS1gxaWNtVmhhenRqWVhObElERXpPbWh1S0daMWJtTjBhVzl1S0NsN2RtRnlJSEk5UkhRb1pTd3hLVHRwWmloeUlUMDliblZzYkNsN2RtRnlJR3c5U0dV'
    || 'b0tUdFRkQ2h5TEdVc01TeHNLWDE5S1N4TGJ5aGxMREVwZlgwc1UyazlablZ1WTNScGIyNG9aU2w3YVdZb1pTNTBZV2M5UFQweE15bDdkbUZ5SUhROVJIUW9a'
    || 'U3d4TXpReU1UYzNNamdwTzJsbUtIUWhQVDF1ZFd4c0tYdDJZWElnYmoxSVpTZ3BPMU4wS0hRc1pTd3hNelF5TVRjM01qZ3NiaWw5UzI4b1pTd3hNelF5TVRj'
    || 'M01qZ3BmWDBzSkhNOVpuVnVZM1JwYjI0b1pTbDdhV1lvWlM1MFlXYzlQVDB4TXlsN2RtRnlJSFE5WW5Rb1pTa3NiajFFZENobExIUXBPMmxtS0c0aFBUMXVk'
    || 'V3hzS1h0MllYSWdjajFJWlNncE8xTjBLRzRzWlN4MExISXBmVXR2S0dVc2RDbDlmU3hXY3oxbWRXNWpkR2x2YmlncGUzSmxkSFZ5YmlCcFpYMHNTSE05Wm5W'
    || 'dVkzUnBiMjRvWlN4MEtYdDJZWElnYmoxcFpUdDBjbmw3Y21WMGRYSnVJR2xsUFdVc2RDZ3BmV1pwYm1Gc2JIbDdhV1U5Ym4xOUxHWnBQV1oxYm1OMGFXOXVL'
    || 'R1VzZEN4dUtYdHpkMmwwWTJnb2RDbDdZMkZ6WlNKcGJuQjFkQ0k2YVdZb2JHa29aU3h1S1N4MFBXNHVibUZ0WlN4dUxuUjVjR1U5UFQwaWNtRmthVzhpSmla'
    || 'MElUMXVkV3hzS1h0bWIzSW9iajFsTzI0dWNHRnlaVzUwVG05a1pUc3BiajF1TG5CaGNtVnVkRTV2WkdVN1ptOXlLRzQ5Ymk1eGRXVnllVk5sYkdWamRHOXlR'
    || 'V3hzS0NKcGJuQjFkRnR1WVcxbFBTSXJTbE5QVGk1emRISnBibWRwWm5rb0lpSXJkQ2tySjExYmRIbHdaVDBpY21Ga2FXOGlYU2NwTEhROU1EdDBQRzR1YkdW'
    || 'dVozUm9PM1FyS3lsN2RtRnlJSEk5Ymx0MFhUdHBaaWh5SVQwOVpTWW1jaTVtYjNKdFBUMDlaUzVtYjNKdEtYdDJZWElnYkQxdmJDaHlLVHRwWmlnaGJDbDBh'
    || 'SEp2ZHlCRmNuSnZjaWhoS0Rrd0tTazdjSE1vY2lrc2JHa29jaXhzS1gxOWZXSnlaV0ZyTzJOaGMyVWlkR1Y0ZEdGeVpXRWlPbmx6S0dVc2JpazdZbkpsWVdz'
    || 'N1kyRnpaU0p6Wld4bFkzUWlPblE5Ymk1MllXeDFaU3gwSVQxdWRXeHNKaVozYmlobExDRWhiaTV0ZFd4MGFYQnNaU3gwTENFeEtYMTlMRU56UFNSdkxGUnpQ'
    || 'V2h1TzNaaGNpQnBjRDE3ZFhOcGJtZERiR2xsYm5SRmJuUnllVkJ2YVc1ME9pRXhMRVYyWlc1MGN6cGJlSElzVFc0c2Iyd3NhM01zYW5Nc0pHOWRmU3hRY2ox'
    || 'N1ptbHVaRVpwWW1WeVFubEliM04wU1c1emRHRnVZMlU2YjI0c1luVnVaR3hsVkhsd1pUb3dMSFpsY25OcGIyNDZJakU0TGpNdU1TSXNjbVZ1WkdWeVpYSlFZ'
    || 'V05yWVdkbFRtRnRaVG9pY21WaFkzUXRaRzl0SW4wc2IzQTllMkoxYm1Sc1pWUjVjR1U2VUhJdVluVnVaR3hsVkhsd1pTeDJaWEp6YVc5dU9sQnlMblpsY25O'
    || 'cGIyNHNjbVZ1WkdWeVpYSlFZV05yWVdkbFRtRnRaVHBRY2k1eVpXNWtaWEpsY2xCaFkydGhaMlZPWVcxbExISmxibVJsY21WeVEyOXVabWxuT2xCeUxuSmxi'
    || 'bVJsY21WeVEyOXVabWxuTEc5MlpYSnlhV1JsU0c5dmExTjBZWFJsT201MWJHd3NiM1psY25KcFpHVkliMjlyVTNSaGRHVkVaV3hsZEdWUVlYUm9PbTUxYkd3'
    || 'c2IzWmxjbkpwWkdWSWIyOXJVM1JoZEdWU1pXNWhiV1ZRWVhSb09tNTFiR3dzYjNabGNuSnBaR1ZRY205d2N6cHVkV3hzTEc5MlpYSnlhV1JsVUhKdmNITkVa'
    || 'V3hsZEdWUVlYUm9PbTUxYkd3c2IzWmxjbkpwWkdWUWNtOXdjMUpsYm1GdFpWQmhkR2c2Ym5Wc2JDeHpaWFJGY25KdmNraGhibVJzWlhJNmJuVnNiQ3h6WlhS'
    || 'VGRYTndaVzV6WlVoaGJtUnNaWEk2Ym5Wc2JDeHpZMmhsWkhWc1pWVndaR0YwWlRwdWRXeHNMR04xY25KbGJuUkVhWE53WVhSamFHVnlVbVZtT25abExsSmxZ'
    || 'V04wUTNWeWNtVnVkRVJwYzNCaGRHTm9aWElzWm1sdVpFaHZjM1JKYm5OMFlXNWpaVUo1Um1saVpYSTZablZ1WTNScGIyNG9aU2w3Y21WMGRYSnVJR1U5UkhN'
    || 'b1pTa3NaVDA5UFc1MWJHdy9iblZzYkRwbExuTjBZWFJsVG05a1pYMHNabWx1WkVacFltVnlRbmxJYjNOMFNXNXpkR0Z1WTJVNlVISXVabWx1WkVacFltVnlR'
    || 'bmxJYjNOMFNXNXpkR0Z1WTJWOGZISndMR1pwYm1SSWIzTjBTVzV6ZEdGdVkyVnpSbTl5VW1WbWNtVnphRHB1ZFd4c0xITmphR1ZrZFd4bFVtVm1jbVZ6YURw'
    || 'dWRXeHNMSE5qYUdWa2RXeGxVbTl2ZERwdWRXeHNMSE5sZEZKbFpuSmxjMmhJWVc1a2JHVnlPbTUxYkd3c1oyVjBRM1Z5Y21WdWRFWnBZbVZ5T201MWJHd3Nj'
    || 'bVZqYjI1amFXeGxjbFpsY25OcGIyNDZJakU0TGpNdU1TMXVaWGgwTFdZeE16TTRaamd3T0RBdE1qQXlOREEwTWpZaWZUdHBaaWgwZVhCbGIyWWdYMTlTUlVG'
    || 'RFZGOUVSVlpVVDA5TVUxOUhURTlDUVV4ZlNFOVBTMTlmUENKMUlpbDdkbUZ5SUVKc1BWOWZVa1ZCUTFSZlJFVldWRTlQVEZOZlIweFBRa0ZNWDBoUFQwdGZY'
    || 'enRwWmlnaFFtd3VhWE5FYVhOaFlteGxaQ1ltUW13dWMzVndjRzl5ZEhOR2FXSmxjaWwwY25sN0pISTlRbXd1YVc1cVpXTjBLRzl3S1N4ZmREMUNiSDFqWVhS'
    || 'amFIdDlmWEpsZEhWeWJpQkNaUzVmWDFORlExSkZWRjlKVGxSRlVrNUJURk5mUkU5ZlRrOVVYMVZUUlY5UFVsOVpUMVZmVjBsTVRGOUNSVjlHU1ZKRlJEMXBj'
    || 'Q3hDWlM1amNtVmhkR1ZRYjNKMFlXdzlablZ1WTNScGIyNG9aU3gwS1h0MllYSWdiajB5UEdGeVozVnRaVzUwY3k1c1pXNW5kR2dtSm1GeVozVnRaVzUwYzFz'
    || 'eVhTRTlQWFp2YVdRZ01EOWhjbWQxYldWdWRITmJNbDA2Ym5Wc2JEdHBaaWdoV204b2RDa3BkR2h5YjNjZ1JYSnliM0lvWVNneU1EQXBLVHR5WlhSMWNtNGdi'
    || 'bkFvWlN4MExHNTFiR3dzYmlsOUxFSmxMbU55WldGMFpWSnZiM1E5Wm5WdVkzUnBiMjRvWlN4MEtYdHBaaWdoV204b1pTa3BkR2h5YjNjZ1JYSnliM0lvWVNn'
    || 'eU9Ua3BLVHQyWVhJZ2JqMGhNU3h5UFNJaUxHdzlhV003Y21WMGRYSnVJSFFoUFc1MWJHd21KaWgwTG5WdWMzUmhZbXhsWDNOMGNtbGpkRTF2WkdVOVBUMGhN'
    || 'Q1ltS0c0OUlUQXBMSFF1YVdSbGJuUnBabWxsY2xCeVpXWnBlQ0U5UFhadmFXUWdNQ1ltS0hJOWRDNXBaR1Z1ZEdsbWFXVnlVSEpsWm1sNEtTeDBMbTl1VW1W'
    || 'amIzWmxjbUZpYkdWRmNuSnZjaUU5UFhadmFXUWdNQ1ltS0d3OWRDNXZibEpsWTI5MlpYSmhZbXhsUlhKeWIzSXBLU3gwUFZsdktHVXNNU3doTVN4dWRXeHNM'
    || 'RzUxYkd3c2Jpd2hNU3h5TEd3cExHVmJWSFJkUFhRdVkzVnljbVZ1ZEN4MmNpaGxMbTV2WkdWVWVYQmxQVDA5T0Q5bExuQmhjbVZ1ZEU1dlpHVTZaU2tzYm1W'
    || 'M0lGaHZLSFFwZlN4Q1pTNW1hVzVrUkU5TlRtOWtaVDFtZFc1amRHbHZiaWhsS1h0cFppaGxQVDF1ZFd4c0tYSmxkSFZ5YmlCdWRXeHNPMmxtS0dVdWJtOWta'
    || 'VlI1Y0dVOVBUMHhLWEpsZEhWeWJpQmxPM1poY2lCMFBXVXVYM0psWVdOMFNXNTBaWEp1WVd4ek8ybG1LSFE5UFQxMmIybGtJREFwZEdoeWIzY2dkSGx3Wlc5'
    || 'bUlHVXVjbVZ1WkdWeVBUMGlablZ1WTNScGIyNGlQMFZ5Y205eUtHRW9NVGc0S1NrNktHVTlUMkpxWldOMExtdGxlWE1vWlNrdWFtOXBiaWdpTENJcExFVnlj'
    || 'bTl5S0dFb01qWTRMR1VwS1NrN2NtVjBkWEp1SUdVOVJITW9kQ2tzWlQxbFBUMDliblZzYkQ5dWRXeHNPbVV1YzNSaGRHVk9iMlJsTEdWOUxFSmxMbVpzZFhO'
    || 'b1UzbHVZejFtZFc1amRHbHZiaWhsS1h0eVpYUjFjbTRnYUc0b1pTbDlMRUpsTG1oNVpISmhkR1U5Wm5WdVkzUnBiMjRvWlN4MExHNHBlMmxtS0NGV2JDaDBL'
    || 'U2wwYUhKdmR5QkZjbkp2Y2loaEtESXdNQ2twTzNKbGRIVnliaUJJYkNodWRXeHNMR1VzZEN3aE1DeHVLWDBzUW1VdWFIbGtjbUYwWlZKdmIzUTlablZ1WTNS'
    || 'cGIyNG9aU3gwTEc0cGUybG1LQ0ZhYnlobEtTbDBhSEp2ZHlCRmNuSnZjaWhoS0RRd05Ta3BPM1poY2lCeVBXNGhQVzUxYkd3bUptNHVhSGxrY21GMFpXUlRi'
    || 'M1Z5WTJWemZIeHVkV3hzTEd3OUlURXNhVDBpSWl4elBXbGpPMmxtS0c0aFBXNTFiR3dtSmlodUxuVnVjM1JoWW14bFgzTjBjbWxqZEUxdlpHVTlQVDBoTUNZ'
    || 'bUtHdzlJVEFwTEc0dWFXUmxiblJwWm1sbGNsQnlaV1pwZUNFOVBYWnZhV1FnTUNZbUtHazliaTVwWkdWdWRHbG1hV1Z5VUhKbFptbDRLU3h1TG05dVVtVmpi'
    || 'M1psY21GaWJHVkZjbkp2Y2lFOVBYWnZhV1FnTUNZbUtITTliaTV2YmxKbFkyOTJaWEpoWW14bFJYSnliM0lwS1N4MFBYSmpLSFFzYm5Wc2JDeGxMREVzYmo4'
    || 'L2JuVnNiQ3hzTENFeExHa3NjeWtzWlZ0VWRGMDlkQzVqZFhKeVpXNTBMSFp5S0dVcExISXBabTl5S0dVOU1EdGxQSEl1YkdWdVozUm9PMlVyS3lsdVBYSmJa'
    || 'VjBzYkQxdUxsOW5aWFJXWlhKemFXOXVMR3c5YkNodUxsOXpiM1Z5WTJVcExIUXViWFYwWVdKc1pWTnZkWEpqWlVWaFoyVnlTSGxrY21GMGFXOXVSR0YwWVQw'
    || 'OWJuVnNiRDkwTG0xMWRHRmliR1ZUYjNWeVkyVkZZV2RsY2toNVpISmhkR2x2YmtSaGRHRTlXMjRzYkYwNmRDNXRkWFJoWW14bFUyOTFjbU5sUldGblpYSkll'
    || 'V1J5WVhScGIyNUVZWFJoTG5CMWMyZ29iaXhzS1R0eVpYUjFjbTRnYm1WM0lDUnNLSFFwZlN4Q1pTNXlaVzVrWlhJOVpuVnVZM1JwYjI0b1pTeDBMRzRwZTJs'
    || 'bUtDRldiQ2gwS1NsMGFISnZkeUJGY25KdmNpaGhLREl3TUNrcE8zSmxkSFZ5YmlCSWJDaHVkV3hzTEdVc2RDd2hNU3h1S1gwc1FtVXVkVzV0YjNWdWRFTnZi'
    || 'WEJ2Ym1WdWRFRjBUbTlrWlQxbWRXNWpkR2x2YmlobEtYdHBaaWdoVm13b1pTa3BkR2h5YjNjZ1JYSnliM0lvWVNnME1Da3BPM0psZEhWeWJpQmxMbDl5WldG'
    || 'amRGSnZiM1JEYjI1MFlXbHVaWEkvS0dodUtHWjFibU4wYVc5dUtDbDdTR3dvYm5Wc2JDeHVkV3hzTEdVc0lURXNablZ1WTNScGIyNG9LWHRsTGw5eVpXRmpk'
    || 'Rkp2YjNSRGIyNTBZV2x1WlhJOWJuVnNiQ3hsVzFSMFhUMXVkV3hzZlNsOUtTd2hNQ2s2SVRGOUxFSmxMblZ1YzNSaFlteGxYMkpoZEdOb1pXUlZjR1JoZEdW'
    || 'elBTUnZMRUpsTG5WdWMzUmhZbXhsWDNKbGJtUmxjbE4xWW5SeVpXVkpiblJ2UTI5dWRHRnBibVZ5UFdaMWJtTjBhVzl1S0dVc2RDeHVMSElwZTJsbUtDRldi'
    || 'Q2h1S1NsMGFISnZkeUJGY25KdmNpaGhLREl3TUNrcE8ybG1LR1U5UFc1MWJHeDhmR1V1WDNKbFlXTjBTVzUwWlhKdVlXeHpQVDA5ZG05cFpDQXdLWFJvY205'
    || 'M0lFVnljbTl5S0dFb016Z3BLVHR5WlhSMWNtNGdTR3dvWlN4MExHNHNJVEVzY2lsOUxFSmxMblpsY25OcGIyNDlJakU0TGpNdU1TMXVaWGgwTFdZeE16TTRa'
    || 'amd3T0RBdE1qQXlOREEwTWpZaUxFSmxmWFpoY2lCc2N6dG1kVzVqZEdsdmJpQm9ZeWdwZTJsbUtHeHpLWEpsZEhWeWJpQlliQzVsZUhCdmNuUnpPMnh6UFRF'
    || 'N1puVnVZM1JwYjI0Z2RTZ3BlMmxtS0NFb2RIbHdaVzltSUY5ZlVrVkJRMVJmUkVWV1ZFOVBURk5mUjB4UFFrRk1YMGhQVDB0Zlh6NGlkU0o4ZkhSNWNHVnZa'
    || 'aUJmWDFKRlFVTlVYMFJGVmxSUFQweFRYMGRNVDBKQlRGOUlUMDlMWDE4dVkyaGxZMnRFUTBVaFBTSm1kVzVqZEdsdmJpSXBLWFJ5ZVh0ZlgxSkZRVU5VWDBS'
    || 'RlZsUlBUMHhUWDBkTVQwSkJURjlJVDA5TFgxOHVZMmhsWTJ0RVEwVW9kU2w5WTJGMFkyZ29aQ2w3WTI5dWMyOXNaUzVsY25KdmNpaGtLWDE5Y21WMGRYSnVJ'
    || 'SFVvS1N4WWJDNWxlSEJ2Y25SelBYQmpLQ2tzV0d3dVpYaHdiM0owYzMxMllYSWdhWE03Wm5WdVkzUnBiMjRnYldNb0tYdHBaaWhwY3lseVpYUjFjbTRnVEhJ'
    || 'N2FYTTlNVHQyWVhJZ2RUMW9ZeWdwTzNKbGRIVnliaUJNY2k1amNtVmhkR1ZTYjI5MFBYVXVZM0psWVhSbFVtOXZkQ3hNY2k1b2VXUnlZWFJsVW05dmREMTFM'
    || 'bWg1WkhKaGRHVlNiMjkwTEV4eWZYWmhjaUIyWXoxdFl5Z3BPMk52Ym5OMElHZGpQU0pmWDBOUFUxUkZSa1pmUkVGVVFWOWZJaXg1WXoxN1kyOXVkR1Y0ZERw'
    || 'N2ZTeHdZVzVsYkhNNmUzMHNabUYwWVd3NklrNXZJR1JoZEdFZ2NHRjViRzloWkNCM1lYTWdhVzVxWldOMFpXUXVJRlJvYVhNZ1luVnBiR1FnYjJZZ2RHaGxJ'
    || 'R0Z3Y0NCcGN5QmljbTlyWlc0N0lISmxMWEoxYmlCb1lYSnVaWE56TG1KMWJtUnNaU0JoYm1RZ2NtVmlkV2xzWkM0aWZUdG1kVzVqZEdsdmJpQjRZeWgxUFdk'
    || 'aktYdGpiMjV6ZENCa1BYZHBibVJ2ZDF0MVhUdHBaaWdoWkh4OGRIbHdaVzltSUdRaFBTSnZZbXBsWTNRaUtYSmxkSFZ5YmlCNVl6dGpiMjV6ZENCaFBXUTdj'
    || 'bVYwZFhKdWUyTnZiblJsZUhRNllTNWpiMjUwWlhoMFB6OTdmU3h3WVc1bGJITTZZUzV3WVc1bGJITS9QM3Q5TEdaaGRHRnNPbUV1Wm1GMFlXd3NZM1Z6ZEc5'
    || 'dGFYcGhkR2x2YmpwaExtTjFjM1J2YldsNllYUnBiMjRzWTNWemRHOXRhWHBoZEdsdmJsOWxjbkp2Y2pwaExtTjFjM1J2YldsNllYUnBiMjVmWlhKeWIzSXNi'
    || 'bUYyYVdkaGRHbHZianBoTG01aGRtbG5ZWFJwYjI1OWZXWjFibU4wYVc5dUlIbHVLSFVwZTNKbGRIVnliaUVoZFNZbUltVnljbTl5SW1sdUlIVjlablZ1WTNS'
    || 'cGIyNGdVMk1vZFNsN2NtVjBkWEp1SUhVbUppSnliM2R6SW1sdUlIVW1KblV1ZEhKMWJtTmhkR1ZrUDNVdWRISjFibU5oZEdWa09qQjlablZ1WTNScGIyNGdl'
    || 'RzRvZFNsN2NtVjBkWEp1SVhWOGZDRW9JbVZ5Y205eUltbHVJSFVwUHlFeE9pOWtiMlZ6SUc1dmRDQmxlR2x6ZENCdmNpQnViM1FnWVhWMGFHOXlhWHBsWkM5'
    || 'cExuUmxjM1FvZFM1bGNuSnZjaWw5Wm5WdVkzUnBiMjRnVDJVb2RTeGtLWHRqYjI1emRDQmhQWFV1Y0dGdVpXeHpXMlJkTzNKbGRIVnliaUJoSmlZaWNtOTNj'
    || 'eUpwYmlCaFAyRXVjbTkzY3pwYlhYMW1kVzVqZEdsdmJpQjZkQ2gxS1h0cFppaDBlWEJsYjJZZ2RUMDlJbTUxYldKbGNpSXBjbVYwZFhKdUlFNTFiV0psY2k1'
    || 'cGMwWnBibWwwWlNoMUtUOTFPbTUxYkd3N2FXWW9kSGx3Wlc5bUlIVWhQU0p6ZEhKcGJtY2lLWEpsZEhWeWJpQnVkV3hzTzJOdmJuTjBJR1E5ZFM1MGNtbHRL'
    || 'Q2s3YVdZb1pEMDlQU0lpZkh3aEwxNWJLeTFkUHloY1pDdGNMajljWkNwOFhDNWNaQ3NwS0Z0bFJWMWJLeTFkUDF4a0t5ay9KQzh1ZEdWemRDaGtLU2x5WlhS'
    || 'MWNtNGdiblZzYkR0amIyNXpkQ0JoUFU1MWJXSmxjaWhrS1R0eVpYUjFjbTRnVG5WdFltVnlMbWx6Um1sdWFYUmxLR0VwUDJFNmJuVnNiSDFtZFc1amRHbHZi'
    || 'aUJaS0hVcGUybG1LSFU5UFc1MWJHeDhmSFU5UFQwaUlpbHlaWFIxY200aTRvQ1VJanRqYjI1emRDQmtQWHAwS0hVcE8ybG1LR1E5UFQxdWRXeHNLWEpsZEhW'
    || 'eWJpQlRkSEpwYm1jb2RTazdhV1lvWkQwOVBUQXBjbVYwZFhKdUlqQWlPMk52Ym5OMElHRTlUV0YwYUM1aFluTW9aQ2s3YVdZb1lUdzFaUzAwS1hKbGRIVnli'
    || 'aUJrUERBL0lqNGdMVEF1TURBeElqb2lQQ0F3TGpBd01TSTdiR1YwSUdjN2NtVjBkWEp1SUdFK1BURmxNejluUFRBNllUNDlNVEF3UDJjOU1UcGhQajB4UDJj'
    || 'OU1qcG5QVE1zWkM1MGIweHZZMkZzWlZOMGNtbHVaeWdpWlc0dFZWTWlMSHR0YVc1cGJYVnRSbkpoWTNScGIyNUVhV2RwZEhNNk1DeHRZWGhwYlhWdFJuSmhZ'
    || 'M1JwYjI1RWFXZHBkSE02WjMwcGZXWjFibU4wYVc5dUlIZGpLSFVwZTJOdmJuTjBJR1E5VTNSeWFXNW5LSFUvUHlJaUtTNTBiMVZ3Y0dWeVEyRnpaU2dwTG5S'
    || 'eWFXMG9LVHR5WlhSMWNtNGdaRDA5UFNKTlJWUWlmSHhrUFQwOUlrNVBWRjlOUlZRaWZIeGtQVDA5SWs0dlFTSS9aRG9pVUVWT1JFbE9SeUo5WTI5dWMzUWda'
    || 'blE5ZFQwK2RUMDliblZzYkQ4aUlqcFRkSEpwYm1jb2RTazdablZ1WTNScGIyNGdiM01vZFNsN2NtVjBkWEp1SUU5bEtIVXNJbkJ2WTE5elkyOXlaV05oY21R'
    || 'aUtTNXRZWEFvWkQwK0tIdGpiMlJsT21aMEtHUXVRMDlFUlNrc2JHRmlaV3c2Wm5Rb1pDNU1RVUpGVENrc2QyaDVPbVowS0dRdVYwaFpYMGxVWDAxQlZGUkZV'
    || 'bE1wTEhSaGNtZGxkRHBrTGxSQlVrZEZWRDgvYm5Wc2JDeGhZM1IxWVd3NlpDNUJRMVJWUVV3L1AyNTFiR3dzZFc1cGRITTZablFvWkM1VlRrbFVVeWtzWTI5'
    || 'dGNHRnlaVHBtZENoa0xrTlBUVkJCVWtVcExHSmhjMmx6T21aMEtHUXVRa0ZUU1ZNcExHUmxjbWwyWVhScGIyNDZablFvWkM1VVFWSkhSVlJmUkVWU1NWWkJW'
    || 'RWxQVGlrc2MzUmhkR1U2ZDJNb1pDNVRWRUZVUlNrc2QyaDVUbTkwT21aMEtHUXVWMGhaWDA1UFZGOUZWa0ZNVlVGVVJVUXBMSEpsYzI5c2RtVnpWMmhsYmpw'
    || 'bWRDaGtMbEpGVTA5TVZrVlRYMWRJUlU0cExHRnlhWFJvYldWMGFXTTZablFvWkM1QlVrbFVTRTFGVkVsREtTeGpiMjF3WVhKaFltbHNhWFI1T21aMEtHUXVR'
    || 'MDlOVUVGU1FVSkpURWxVV1NsOUtTbDlablZ1WTNScGIyNGdYMk1vZFNsN1kyOXVjM1FnWkQxMUxuQmhibVZzY3k1d2IyTmZjMk52Y21WallYSmtMR0U5YjNN'
    || 'b2RTazdhV1lvZVc0b1pDa3BjbVYwZFhKdWUyMWxkRG93TEc1dmRFMWxkRG93TEhCbGJtUnBibWM2TUN4dVlUb3dMSE5qYjNKbFpEb3dMR2hsWVdSc2FXNWxP'
    || 'aUxpZ0pRaUxIWmxjbVJwWTNRNklrNVBWRjlTVlU0aUxISmxZV1JVYUdsek9uaHVLR1FwUHlKVWFHVWdjMk52Y21WallYSmtJSFpwWlhkeklIZGxjbVVnYm05'
    || 'MElHSjFhV3gwSUdKNUlIUm9hWE1nY25WdUxDQnZjaUIwYUdseklISnZiR1VnWTJGdWJtOTBJSE5sWlNCMGFHVnRMaUJUYm05M1pteGhhMlVnWkc5bGN5QnVi'
    || 'M1FnWkdsemRHbHVaM1ZwYzJnZ2RHaGxJSFIzYnk0aU9pSlVhR1VnYzJOdmNtVmpZWEprSUhGMVpYSjVJR1poYVd4bFpDd2djMjhnYm05MGFHbHVaeUJvWlhK'
    || 'bElHbHpJSE5qYjNKbFpDNGlMSFZ1WVhaaGFXeGhZbXhsT21RdVpYSnliM0o5TzJOdmJuTjBJR2M5WVM1bWFXeDBaWElvUmowK1JpNXpkR0YwWlQwOVBTSk5S'
    || 'VlFpS1M1c1pXNW5kR2dzZUQxaExtWnBiSFJsY2loR1BUNUdMbk4wWVhSbFBUMDlJazVQVkY5TlJWUWlLUzVzWlc1bmRHZ3NRejFoTG1acGJIUmxjaWhHUFQ1'
    || 'R0xuTjBZWFJsUFQwOUlsQkZUa1JKVGtjaUtTNXNaVzVuZEdnc1V6MWhMbVpwYkhSbGNpaEdQVDVHTG5OMFlYUmxQVDA5SWs0dlFTSXBMbXhsYm1kMGFDeDNQ'
    || 'V0V1YkdWdVozUm9MVk1zWHoxM1BUMDlNRDhpVGs5VVgxSlZUaUk2ZUQ0d1B5Sk9UMVJmVFVWVUlqcG5QVDA5TUQ4aVVFVk9SRWxPUnlJNlF6NHdQeUpOUlZS'
    || 'ZlYwbFVTRjlRUlU1RVNVNUhJam9pVFVWVUlpeE1QVTlsS0hVc0luQnZZMTkyWlhKa2FXTjBJaWxiTUYwc1RqMU1QMU4wY21sdVp5aE1MbFpGVWtSSlExUS9Q'
    || 'eUlpS1RvaUlpeFBQU0VoVGlZbVRpRTlQVjg3Y21WMGRYSnVlMjFsZERwbkxHNXZkRTFsZERwNExIQmxibVJwYm1jNlF5eHVZVHBUTEhOamIzSmxaRHAzTEdo'
    || 'bFlXUnNhVzVsT25jOVBUMHdQeUp1YjNRZ2MyTnZjbVZrSWpwZ0pIdG5mUzhrZTNkOUlHMWxkR0FzZG1WeVpHbGpkRHBmTEhKbFlXUlVhR2x6T2s4L1lGUm9a'
    || 'U0J6WTI5eVpXTmhjbVFnY205M2N5QmhibVFnZEdobElISnZiR3d0ZFhBZ2RtbGxkeUJrYVhOaFozSmxaU0FvY205M2N5QnpZWGtnSkh0ZmZTd2dWbDlRVDBO'
    || 'ZlZrVlNSRWxEVkNCellYbHpJQ1I3VG4wcExpQlVjblZ6ZENCdVpXbDBhR1Z5SUhWdWRHbHNJSFJvWVhRZ2FYTWdaWGh3YkdGcGJtVmtMbUE2VEQ5VGRISnBi'
    || 'bWNvVEM1U1JVRkVYMVJJU1ZNL1B5SWlLVG9pSW4xOVkyOXVjM1FnU213OVd5SkVTVk5EVDFaRlVpSXNJa3hKVFVsVVJVUWlMQ0pRVWs5RVZVTlVTVTlPSWww'
    || 'c1JXTTllMFJKVTBOUFZrVlNPaUpFYVhOamIzWmxjbmtpTEV4SlRVbFVSVVE2SWt4cGJXbDBaV1FnY25WdUlpeFFVazlFVlVOVVNVOU9PaUpRY205a2RXTjBh'
    || 'Vzl1SW4wc1RtTTllMFJKVTBOUFZrVlNPaUpTWldGa2N5QjBhR1VnWVdOamIzVnVkQ0JoYm1RZ2NtVndiM0owY3lCM2FHRjBJR2wwSUdadmRXNWtMaUJCYm5s'
    || 'MGFHbHVaeUJ5WldOMWNuSnBibWNnYVhNZ1kzSmxZWFJsWkN3Z2NtVm1jbVZ6YUdWa0lHOXVZMlVnYzI4Z2FYUnpJR052YzNRZ1kyRnVJR0psSUcxbFlYTjFj'
    || 'bVZrTENCMGFHVnVJSE4xYzNCbGJtUmxaQzRpTEV4SlRVbFVSVVE2SWxSb1pTQnpZVzFsSUdKMWFXeGtJRzl1SUdGdUlHbHpiMnhoZEdWa0lIZGhjbVZvYjNW'
    || 'elpTQjNhWFJvSUdFZ2NtVnpiM1Z5WTJVZ2JXOXVhWFJ2Y2lCdmRtVnlJR2wwTENCemJ5QjBhR1VnWTNKbFpHbDBjeUJwZENCaWRYSnVjeUJoY21VZ1lYUjBj'
    || 'bWxpZFhSaFlteGxJR0Z1WkNCallXNGdZbVVnY21WaFpDQmlZV05ySUdaeWIyMGdiV1YwWlhKcGJtY3VJRlJvYVhNZ2FYTWdkR2hsSUc5dWJIa2djR2hoYzJV'
    || 'Z2RHaGhkQ0J3Y205a2RXTmxjeUJoSUcxbFlYTjFjbVZrSUc1MWJXSmxjaTRpTEZCU1QwUlZRMVJKVDA0NklrWjFiR3dnYzJOdmNHVXNJR0Z1WkNCMGFHVWdj'
    || 'bVZqZFhKeWFXNW5JRzlpYW1WamRITWdZWEpsSUd4bFpuUWdjblZ1Ym1sdVp5NGdRV1JrY3lCMGFHVWdiM0JsY21GMGFXOXVZV3dnWm5WeWJtbDBkWEpsSUdF'
    || 'Z2NHeGhkR1p2Y20wZ2RHVmhiU0JsZUhCbFkzUnpPaUJ0YjI1cGRHOXlMQ0JpZFdSblpYUXNJRzlpYW1WamRDQjBZV2R6TENCbGNuSnZjaUJ1YjNScFptbGpZ'
    || 'WFJwYjI0c0lISmxabkpsYzJnZ1UweEJMQ0JoYmlCdmNHVnlZWFJwYjI1eklIWnBaWGN1SW4wN1puVnVZM1JwYjI0Z2MzTW9kU3hrS1h0eVpYUjFjbTRnZFQw'
    || 'OVBXNTFiR3g4ZkdROVBUMXVkV3hzZkh4MVBUMDlNRDhpSWpvaWZpUWlLMWtvZFNwa0tYMW1kVzVqZEdsdmJpQnJZeWgxS1h0amIyNXpkQ0JrUFZOMGNtbHVa'
    || 'eWgxTGxSSlJWSS9QeUlpS1M1MGIxVndjR1Z5UTJGelpTZ3BMR0U5U213dWFXNWpiSFZrWlhNb1pDay9aRG9pUkVsVFEwOVdSVklpTEdjOVNtd3VhVzVrWlho'
    || 'UFppaGhLU3g0UFhwMEtIVXVVa0ZVUlY5UVJWSmZRMUpGUkVsVUtTeERQWHAwS0hVdVExSkZSRWxVWDBOQlVDa3NVejE2ZENoMUxsTlVRVTVFU1U1SFgwTlNS'
    || 'VVJKVkZOZlVFVlNYMDFQVGxSSUtTeDNQWHAwS0hVdVUwTklSVVJWVEVWRVgwTlBUVkJQVGtWT1ZGTXBQejh3TEY4OWVuUW9kUzVXVDB4VlRVVmZRMDlOVUU5'
    || 'T1JVNVVVeWsvUHpBc1REMWZQakEvWUNBcklDUjdYMzBnZG05c2RXMWxMV1J5YVhabGJtQTZJaUk3YkdWMElFNHNUenQzUGpBbUpsTWhQVDF1ZFd4c0ppWlRQ'
    || 'akEvS0U0OVlINGtlMWtvVXlsOUlHTnlaV1JwZEhNdmJXOXVkR2drZTB4OVlDeFBQU0p3Y205cVpXTjBaV1FnWm5KdmJTQjBhR1VnWTJGa1pXNWpaU0IwYUds'
    || 'eklHSjFhV3hrSUhObGRDQmhibVFnZEdobElHUjFjbUYwYVc5dUlHbDBJRzFsWVhOMWNtVmtMaUJPYjNRZ1lTQmlhV3hzTGlJcktGOCtNRDhpSUZSb1pTQjJi'
    || 'MngxYldVdFpISnBkbVZ1SUdOdmJYQnZibVZ1ZEhNZ2FHRjJaU0J1YnlCdGIyNTBhR3g1SUdacFozVnlaU0JoZENCaGJHdzdJSFJvWldseUlHTnZjM1FnYzJO'
    || 'aGJHVnpJSGRwZEdnZ2FHOTNJRzExWTJnZ1pHRjBZU0I1YjNVZ2MyVnVaQzRpT2lJaUtTazZkejR3UHloT1BXQWtlM2Q5SUhOamFHVmtkV3hsWkNCamIyMXdi'
    || 'MjVsYm5Ra2UzYzlQVDB4UHlJaU9pSnpJbjBrZTB4OVlDeFBQV0U5UFQwaVVGSlBSRlZEVkVsUFRpSS9JbkpsWjJsemRHVnlaV1FnYjI0Z1lTQnpZMmhsWkhW'
    || 'c1pTd2dZblYwSUhSb1pTQnlaV052Y21SbFpDQmpZV1JsYm1ObElHbHpJSHBsY204c0lITnZJRzV2SUcxdmJuUm9iSGtnWm1sbmRYSmxJR05oYmlCaVpTQmta'
    || 'WEpwZG1Wa0xpQlVjbVZoZENCMGFHbHpJR0Z6SUhWdWEyNXZkMjRzSUc1dmRDQmhjeUJtY21WbExpSTZJblJvWlNCeVpXTjFjbkpwYm1jZ2IySnFaV04wY3lC'
    || 'aGNtVWdhVzV6ZEdGc2JHVmtJR0Z1WkNCemRYTndaVzVrWldRZ1lYUWdkR2hwY3lCMGFXVnlMQ0J6YnlCdWJ5QmpZV1JsYm1ObElHbHpJRzl1SUhKbFkyOXla'
    || 'Q0IwYnlCd2NtOXFaV04wSUdaeWIyMHVJRlJvYVhNZ2FYTWdUazlVSUhwbGNtOGdMUzBnWW5WcGJHUWdZWFFnVUZKUFJGVkRWRWxQVGlCMGJ5Qm5aWFFnZEdo'
    || 'bElHMWxZWE4xY21Wa0lHMXZiblJvYkhrZ1ptbG5kWEpsTGlJcE9sOCtNRDhvVGoxZ0pIdGZmU0IyYjJ4MWJXVXRaSEpwZG1WdUlHTnZiWEJ2Ym1WdWRDUjdY'
    || 'ejA5UFRFL0lpSTZJbk1pZldBc1R6MGlibThnWTJGa1pXNWpaU3dnYzI4Z2JtOGdiVzl1ZEdoc2VTQndjbTlxWldOMGFXOXVJR2x6SUhCdmMzTnBZbXhsTGlC'
    || 'VWFHbHpJR2x6SUU1UFZDQjZaWEp2SUMwdElIUm9aU0JqYjNOMElITmpZV3hsY3lCM2FYUm9JR2h2ZHlCdGRXTm9JR1JoZEdFZ2VXOTFJSE5sYm1RdUlpazZL'
    || 'RTQ5SW01dmRHaHBibWNnY21WamRYSnlhVzVuSWl4UFBTSjBhR2x6SUhOdmJIVjBhVzl1SUdsdWMzUmhiR3h6SUc1dmRHaHBibWNnYjI0Z1lTQnpZMmhsWkhW'
    || 'c1pTNGdTWFFnWTI5emRITWdjM1J2Y21GblpTQndiSFZ6SUhkb1lYUmxkbVZ5SUdOdmJYQjFkR1VnZEdobElIQmxiM0JzWlNCeGRXVnllV2x1WnlCcGRDQjFj'
    || 'MlV1SWlrN1kyOXVjM1FnUmoxN1JFbFRRMDlXUlZJNmUyWnBaM1Z5WlRvaU1DQmpjbVZrYVhSekwyMXZiblJvSWl4dGIyNWxlVG9pSWl4aVlYTnBjem9pYm05'
    || 'MGFHbHVaeUJwY3lCc1pXWjBJSEoxYm01cGJtY3NJSE52SUc1dmRHaHBibWNnY21WamRYSnpMaUJVYUdVZ2IyNWxMWFJwYldVZ2NtVmhaQ0JwZEhObGJHWWdh'
    || 'WE1nWVNCb1lXNWtablZzSUc5bUlIRjFaWEpwWlhNdUluMHNURWxOU1ZSRlJEcDdabWxuZFhKbE9rTW1Ka00rTUQ5ZzRvbWtJQ1I3V1NoREtYMGdZM0psWkds'
    || 'MGN5QnZibVV0ZEdsdFpXQTZJbTV2SUdOaGNDQnpaWFFpTEcxdmJtVjVPa01tSmtNK01EOXpjeWhETEhncE9pSWlMR0poYzJsek9rTW1Ka00rTUQ4aVlXNGda'
    || 'VzVtYjNKalpXUWdZMlZwYkdsdVp5d2dibTkwSUdGdUlHVnpkR2x0WVhSbE9pQmhJSEpsYzI5MWNtTmxJRzF2Ym1sMGIzSWdjM1Z6Y0dWdVpITWdkR2hsSUhk'
    || 'aGNtVm9iM1Z6WlNCM2FHVnVJR2wwSUdseklISmxZV05vWldRdUlFbDBJR2R2ZG1WeWJuTWdWMEZTUlVoUFZWTkZJR055WldScGRITWdiMjVzZVNBdExTQnVi'
    || 'M1FnYzJWeWRtVnliR1Z6Y3lCbVpXRjBkWEpsY3lCaGJtUWdibTkwSUVGSklIUnZhMlZ1Y3k0aU9pSkRVa1ZFU1ZSZlEwRlFJR2x6SURBc0lITnZJSFJvWlhK'
    || 'bElHbHpJRzV2SUdWdVptOXlZMlZrSUdObGFXeHBibWNnYjI0Z2RHaHBjeUJ5ZFc0dUluMHNVRkpQUkZWRFZFbFBUanA3Wm1sbmRYSmxPazRzYlc5dVpYazZj'
    || 'M01vVXl4NEtTeGlZWE5wY3pwUGZYMHNTejFUZEhKcGJtY29kUzVUUlZSVVNVNUhYMUJTUlVaSldEOC9JaUlwTG5SeWFXMG9LVHR5WlhSMWNtNGdTbXd1YldG'
    || 'd0tDaEhMRllwUFQ0b2UybGtPa2NzYkdGaVpXdzZSV05iUjEwc2MzUmhkR1U2Vmp4blB5SmtiMjVsSWpwV1BUMDlaejhpWTNWeWNtVnVkQ0k2SW1Gb1pXRmtJ'
    || 'aXd1TGk1R1cwZGRMR0pzZFhKaU9rNWpXMGRkTEhObGRIUnBibWM2U3o5Z1UwVlVJQ1I3UzMxZlJFVlFURTlaWDFSSlJWSWdQU0FuSkh0SGZTYzdZRHBnVTBW'
    || 'VUlEeHdjbVZtYVhnK1gwUkZVRXhQV1Y5VVNVVlNJRDBnSnlSN1IzMG5PMkI5S1NsOVpuVnVZM1JwYjI0Z2FtTW9lM05wZW1VNmRUMHhPU3hqYjJ4dmNqcGtQ'
    || 'U0lqTWpsaU5XVTRJbjBwZTNKbGRIVnliaUJ2TG1wemVITW9Jbk4yWnlJc2UzZHBaSFJvT25Vc2FHVnBaMmgwT25Vc2RtbGxkMEp2ZURvaU1DQXdJRFF6TGpR'
    || 'Z05ETXVOU0lzWm1sc2JEcGtMSEp2YkdVNkltbHRaeUlzSW1GeWFXRXRiR0ZpWld3aU9pSlRibTkzWm14aGEyVWlMR05vYVd4a2NtVnVPbHR2TG1wemVDZ2lj'
    || 'R0YwYUNJc2UyUTZJazB6Tnk0eU5qTTNORFkxTERNekxqRXlPRGt3TmlCTU1qZ3VNRGczT1RZMU5Td3lOeTQ0TWpneE1qVWdRekkyTGpjNU9Ea3dNalVzTWpj'
    || 'dU1EZzFPVE00SURJMUxqRTFNRFEyTlRVc01qY3VOVEkzTXpRMElESTBMalF3TkRNM01UVXNNamd1T0RFMk5EQTJJRU15TkM0eE1UVXpNRGcxTERJNUxqTXlO'
    || 'REl4T1NBeU5DNHdNREl3TWpjMUxESTVMamc0TWpneE1pQXlOQzR3TlRZM01UVTFMRE13TGpReU5UYzRNU0JNTWpRdU1EVTJOekUxTlN3ME1DNDNPRFV4TlRZ'
    || 'Z1F6STBMakExTmpjeE5UVXNOREl1TWpZMU5qSTFJREkxTGpJMU9UZ3pPVFVzTkRNdU5EWTROelVnTWpZdU56UTBNakUxTlN3ME15NDBOamczTlNCRE1qZ3VN'
    || 'akkwTmpnek5TdzBNeTQwTmpnM05TQXlPUzQwTWpjNE1EZzFMRFF5TGpJMk5UWXlOU0F5T1M0ME1qYzRNRGcxTERRd0xqYzROVEUxTmlCTU1qa3VOREkzT0RB'
    || 'NE5Td3pOQzQ0TWpneE1qVWdURE0wTGpVMk9EUXpNelVzTXpjdU56azJPRGMxSUVNek5TNDROVGMwT1RZMUxETTRMalUwTWprMk9TQXpOeTQxTURrNE16azFM'
    || 'RE00TGpBNU56WTFOaUF6T0M0eU5USXdNamMxTERNMkxqZ3dPRFU1TkNCRE16Z3VPVGs0TVRJeE5Td3pOUzQxTVRrMU16RWdNemd1TlRVMk56RTFOU3d6TXk0'
    || 'NE56RXdPVFFnTXpjdU1qWXpOelEyTlN3ek15NHhNamc1TURZaWZTa3NieTVxYzNnb0luQmhkR2dpTEh0a09pSk5NVFF1TkRRek5ETXpOU3d5TVM0M05qazFN'
    || 'ekVnUXpFMExqUTFPVEExT0RVc01qQXVPREV5TlNBeE15NDVOVFV4TlRJMUxERTVMamt5TVRnM05TQXhNeTR4TWpjd01qYzFMREU1TGpRME1UUXdOaUJNTXk0'
    || 'NU5URXlORFkwT1N3eE5DNHhORFExTXpFZ1F6TXVOVFV5T0RBNE5Ea3NNVE11T1RFME1EWXlJRE11TURrMU56YzNORGtzTVRNdU56a3lPVFk1SURJdU5qTTRO'
    || 'elEyTkRrc01UTXVOemt5T1RZNUlFTXhMalk1TnpNek9UUTVMREV6TGpjNU1qazJPU0F3TGpneU1qTXpPVFE1TlN3eE5DNHlPVFk0TnpVZ01DNHpOVE0xT0Rr'
    || 'ME9UVXNNVFV1TVRBNU16YzFJRU10TUM0ek56STVOekkxTURVc01UWXVNelkzTVRnNElEQXVNRFl3TmpJeE5EazFMREUzTGprNE1EUTJPU0F4TGpNeE9EUXpN'
    || 'elE1TERFNExqY3dOekF6TVNCTU5pNDJNRGMwT1RZME9Td3lNUzQzTlRjNE1USWdUREV1TXpFNE5ETXpORGtzTWpRdU9ERXlOU0JETUM0M01Ea3dOVGcwT1RV'
    || 'c01qVXVNVFkwTURZeUlEQXVNamN4TlRVNE5EazFMREkxTGpjek1EUTJPU0F3TGpBNU1UZzNNVFE1TlN3eU5pNDBNVEF4TlRZZ1F5MHdMakE1TVRjeU1qVXdO'
    || 'U3d5Tnk0d09EazRORFFnTUM0d01ESXdNamMwT1RRNU5pd3lOeTQ0TURBM09ERWdNQzR6TlRNMU9EazBPVFVzTWpndU5ERXdNVFUySUVNd0xqZ3lNak16T1RR'
    || 'NU5Td3lPUzR5TWpJMk5UWWdNUzQyT1Rjek16azBPU3d5T1M0M01qWTFOaklnTWk0Mk16UTRNemswT1N3eU9TNDNNalkxTmpJZ1F6TXVNRGsxTnpjM05Ea3NN'
    || 'amt1TnpJMk5UWXlJRE11TlRVeU9EQTRORGtzTWprdU5qQTFORFk1SURNdU9UVXhNalEyTkRrc01qa3VNemMxSUV3eE15NHhNamN3TWpjMUxESTBMakEzT0RF'
    || 'eU5TQkRNVE11T1RRM016TTVOU3d5TXk0Mk1ERTFOaklnTVRRdU5EVXhNalEyTlN3eU1pNDNNVGczTlNBeE5DNDBORE0wTXpNMUxESXhMamMyT1RVek1TSjlL'
    || 'U3h2TG1wemVDZ2ljR0YwYUNJc2UyUTZJazAyTGpBek16STNOelE1TERFd0xqTTVNRFl5TlNCTU1UVXVNakE1TURVNE5Td3hOUzQyT0RjMUlFTXhOaTR5Tnpr'
    || 'ek56RTFMREUyTGpNd09EVTVOQ0F4Tnk0MU9UazJPRE0xTERFMkxqRXdOVFEyT1NBeE9DNDBORE0wTXpNMUxERTFMakk0TVRJMUlFTXhPQzQ1TnpnMU9EazFM'
    || 'REUwTGpjNE9UQTJNaUF4T1M0ek1UQTJNakUxTERFMExqQTROVGt6T0NBeE9TNHpNVEEyTWpFMUxERXpMak13TkRZNE9DQk1NVGt1TXpFd05qSXhOU3d5TGpZ'
    || 'NE56VWdRekU1TGpNeE1EWXlNVFVzTVM0eU1ETXhNalVnTVRndU1UQTNORGsyTlN3d0lERTJMall5TnpBeU56VXNNQ0JETVRVdU1UUXlOalV5TlN3d0lERXpM'
    || 'amt6T1RVeU56VXNNUzR5TURNeE1qVWdNVE11T1RNNU5USTNOU3d5TGpZNE56VWdUREV6TGprek9UVXlOelVzT0M0M016QTBOamtnVERndU56STROVGc1TkRr'
    || 'c05TNDNNakkyTlRZZ1F6Y3VORE01TlRJM05Ea3NOQzQ1TnpZMU5qSWdOUzQzT1RFd09EazBPU3cxTGpReE56azJPU0ExTGpBME5EazVOalE1TERZdU56QTNN'
    || 'RE14SUVNMExqSTVPRGt3TWpRNUxEY3VPVGsyTURrMElEUXVOelEwTWpFMU5Ea3NPUzQyTkRRMU16RWdOaTR3TXpNeU56YzBPU3d4TUM0ek9UQTJNalVpZlNr'
    || 'c2J5NXFjM2dvSW5CaGRHZ2lMSHRrT2lKTk1qWXVOalkyTURnNU5Td3lNaTR4T1RreU1Ua2dRekkyTGpZMk5qQTRPVFVzTWpJdU5EQXlNelEwSURJMkxqVTBP'
    || 'RGt3TWpVc01qSXVOamd6TlRrMElESTJMalF3TkRNM01UVXNNakl1T0RNeU1ETXhJRXd5TWk0M05qYzJOVEkxTERJMkxqUTJPRGMxSUVNeU1pNDJNak14TWpF'
    || 'MUxESTJMall4TXpJNE1TQXlNaTR6TXpjNU5qVTFMREkyTGpjek1EUTJPU0F5TWk0eE16UTRNemsxTERJMkxqY3pNRFEyT1NCTU1qRXVNakE1TURVNE5Td3lO'
    || 'aTQzTXpBME5qa2dRekl4TGpBd05Ua3pNelVzTWpZdU56TXdORFk1SURJd0xqY3lNRGMzTnpVc01qWXVOakV6TWpneElESXdMalUzTmpJME5qVXNNall1TkRZ'
    || 'NE56VWdUREUyTGprek5UWXlNVFVzTWpJdU9ETXlNRE14SUVNeE5pNDNPVEV3T0RrMUxESXlMalk0TXpVNU5DQXhOaTQyTnpNNU1ESTFMREl5TGpRd01qTTBO'
    || 'Q0F4Tmk0Mk56TTVNREkxTERJeUxqRTVPVEl4T1NCTU1UWXVOamN6T1RBeU5Td3lNUzR5TnpNME16Z2dRekUyTGpZM016a3dNalVzTWpFdU1EWTJOREEySURF'
    || 'MkxqYzVNVEE0T1RVc01qQXVOemcxTVRVMklERTJMamt6TlRZeU1UVXNNakF1TmpRd05qSTFJRXd5TUM0MU56WXlORFkxTERFM0lFTXlNQzQzTWpBM056YzFM'
    || 'REUyTGpnMU5UUTJPU0F5TVM0d01EVTVNek0xTERFMkxqY3pPREk0TVNBeU1TNHlNRGt3TlRnMUxERTJMamN6T0RJNE1TQk1Nakl1TVRNME9ETTVOU3d4Tmk0'
    || 'M016Z3lPREVnUXpJeUxqTXpOemsyTlRVc01UWXVOek00TWpneElESXlMall5TXpFeU1UVXNNVFl1T0RVMU5EWTVJREl5TGpjMk56WTFNalVzTVRjZ1RESTJM'
    || 'alF3TkRNM01UVXNNakF1TmpRd05qSTFJRU15Tmk0MU5EZzVNREkxTERJd0xqYzROVEUxTmlBeU5pNDJOall3T0RrMUxESXhMakEyTmpRd05pQXlOaTQyTmpZ'
    || 'd09EazFMREl4TGpJM016UXpPQ0JNTWpZdU5qWTJNRGc1TlN3eU1pNHhPVGt5TVRrZ1dpQk5Nak11TkRFNU9UazJOU3d5TVM0M05UTTVNRFlnVERJekxqUXhP'
    || 'VGs1TmpVc01qRXVOekUwT0RRMElFTXlNeTQwTVRrNU9UWTFMREl4TGpVMk5qUXdOaUF5TXk0ek16UXdOVGcxTERJeExqTTFPVE0zTlNBeU15NHlNamcxT0Rr'
    || 'MUxESXhMakkxSUV3eU1pNHhOVFF6TnpFMUxESXdMakUzT1RZNE9DQkRNakl1TURRNE9UQXlOU3d5TUM0d056QXpNVElnTWpFdU9EUXhPRGN4TlN3eE9TNDVP'
    || 'RFF6TnpVZ01qRXVOamc1TlRJM05Td3hPUzQ1T0RRek56VWdUREl4TGpZMU1EUTJOVFVzTVRrdU9UZzBNemMxSUVNeU1TNDFNREl3TWpjMUxERTVMams0TkRN'
    || 'M05TQXlNUzR5T1RRNU9UWTFMREl3TGpBM01ETXhNaUF5TVM0eE9EVTJNakUxTERJd0xqRTNPVFk0T0NCTU1qQXVNVEUxTXpBNE5Td3lNUzR5TlNCRE1qQXVN'
    || 'REE1T0RNNU5Td3lNUzR6TlRVME5qa2dNVGt1T1RJek9UQXlOU3d5TVM0MU5qSTFJREU1TGpreU16a3dNalVzTWpFdU56RTBPRFEwSUV3eE9TNDVNak01TURJ'
    || 'MUxESXhMamMxTXprd05pQkRNVGt1T1RJek9UQXlOU3d5TVM0NU1EWXlOU0F5TUM0d01EazRNemsxTERJeUxqRXhNekk0TVNBeU1DNHhNVFV6TURnMUxESXlM'
    || 'akl4T0RjMUlFd3lNUzR4T0RVMk1qRTFMREl6TGpJNU1qazJPU0JETWpFdU1qazBPVGsyTlN3eU15NHpPVGcwTXpnZ01qRXVOVEF5TURJM05Td3lNeTQwT0RR'
    || 'ek56VWdNakV1TmpVd05EWTFOU3d5TXk0ME9EUXpOelVnVERJeExqWTRPVFV5TnpVc01qTXVORGcwTXpjMUlFTXlNUzQ0TkRFNE56RTFMREl6TGpRNE5ETTNO'
    || 'U0F5TWk0d05EZzVNREkxTERJekxqTTVPRFF6T0NBeU1pNHhOVFF6TnpFMUxESXpMakk1TWprMk9TQk1Nak11TWpJNE5UZzVOU3d5TWk0eU1UZzNOU0JETWpN'
    || 'dU16TTBNRFU0TlN3eU1pNHhNVE15T0RFZ01qTXVOREU1T1RrMk5Td3lNUzQ1TURZeU5TQXlNeTQwTVRrNU9UWTFMREl4TGpjMU16a3dOaUJhSW4wcExHOHVh'
    || 'bk40S0NKd1lYUm9JaXg3WkRvaVRUSTRMakE0TnprMk5UVXNNVFV1TmpnM05TQk1NemN1TWpZek56UTJOU3d4TUM0ek9UQTJNalVnUXpNNExqVTFNamd3T0RV'
    || 'c09TNDJORGcwTXpnZ016Z3VPVGs0TVRJeE5TdzNMams1TmpBNU5DQXpPQzR5TlRJd01qYzFMRFl1TnpBM01ETXhJRU16Tnk0MU1EVTVNek0xTERVdU5ERTNP'
    || 'VFk1SURNMUxqZzFOelE1TmpVc05DNDVOelkxTmpJZ016UXVOVFk0TkRNek5TdzFMamN5TWpZMU5pQk1Namt1TkRJM09EQTROU3c0TGpZNU1UUXdOaUJNTWpr'
    || 'dU5ESTNPREE0TlN3eUxqWTROelVnUXpJNUxqUXlOemd3T0RVc01TNHlNRE14TWpVZ01qZ3VNakkwTmpnek5Td3ROUzQyT0RRek5ERTRPV1V0TVRRZ01qWXVO'
    || 'elEwTWpFMU5Td3ROUzQyT0RRek5ERTRPV1V0TVRRZ1F6STFMakkxT1Rnek9UVXNMVFV1TmpnME16UXhPRGxsTFRFMElESTBMakExTmpjeE5UVXNNUzR5TURN'
    || 'eE1qVWdNalF1TURVMk56RTFOU3d5TGpZNE56VWdUREkwTGpBMU5qY3hOVFVzTVRNdU1Ea3pOelVnUXpJMExqQXdOVGt6TXpVc01UTXVOak15T0RFeUlESTBM'
    || 'akV4TVRRd01qVXNNVFF1TVRrMU16RXlJREkwTGpRd05ETTNNVFVzTVRRdU56QXpNVEkxSUVNeU5TNHhOVEEwTmpVMUxERTFMams1TWpFNE9DQXlOaTQzT1Rn'
    || 'NU1ESTFMREUyTGpRek16VTVOQ0F5T0M0d09EYzVOalUxTERFMUxqWTROelVpZlNrc2J5NXFjM2dvSW5CaGRHZ2lMSHRrT2lKTk1UY3VNRFE0T1RBeU5Td3lO'
    || 'eTQxTVRVMk1qVWdRekUyTGpRek9UVXlOelVzTWpjdU16azRORE00SURFMUxqYzROekU0TXpVc01qY3VORGsyTURrMElERTFMakl3T1RBMU9EVXNNamN1T0RJ'
    || 'NE1USTFJRXcyTGpBek16STNOelE1TERNekxqRXlPRGt3TmlCRE5DNDNORFF5TVRVME9Td3pNeTQ0TnpFd09UUWdOQzR5T1RnNU1ESTBPU3d6TlM0MU1UazFN'
    || 'ekVnTlM0d05EUTVPVFkwT1N3ek5pNDRNRGcxT1RRZ1F6VXVOemt4TURnNU5Ea3NNemd1TVRBeE5UWXlJRGN1TkRNNU5USTNORGtzTXpndU5UUXlPVFk1SURn'
    || 'dU56STROVGc1TkRrc016Y3VOemsyT0RjMUlFd3hNeTQ1TXprMU1qYzFMRE0wTGpjNE9UQTJNaUJNTVRNdU9UTTVOVEkzTlN3ME1DNDNPRFV4TlRZZ1F6RXpM'
    || 'amt6T1RVeU56VXNOREl1TWpZMU5qSTFJREUxTGpFME1qWTFNalVzTkRNdU5EWTROelVnTVRZdU5qSTNNREkzTlN3ME15NDBOamczTlNCRE1UZ3VNVEEzTkRr'
    || 'Mk5TdzBNeTQwTmpnM05TQXhPUzR6TVRBMk1qRTFMRFF5TGpJMk5UWXlOU0F4T1M0ek1UQTJNakUxTERRd0xqYzROVEUxTmlCTU1Ua3VNekV3TmpJeE5Td3pN'
    || 'QzR4TmpjNU5qa2dRekU1TGpNeE1EWXlNVFVzTWpndU9ESTRNVEkxSURFNExqTXpNREUxTWpVc01qY3VOekU0TnpVZ01UY3VNRFE0T1RBeU5Td3lOeTQxTVRV'
    || 'Mk1qVWlmU2tzYnk1cWMzZ29JbkJoZEdnaUxIdGtPaUpOTkRJdU9UazRNVEl4TlN3eE5TNHdOemd4TWpVZ1F6UXlMakkxTlRrek16VXNNVE11TnpnMU1UVTJJ'
    || 'RFF3TGpZd016VTRPVFVzTVRNdU16UXpOelVnTXprdU16RTBOVEkzTlN3eE5DNHdPRGs0TkRRZ1RETXdMakV6T0RjME5qVXNNVGt1TXpnMk56RTVJRU15T1M0'
    || 'eU5UazRNemsxTERFNUxqZzVORFV6TVNBeU9DNDNOelUwTmpVMUxESXdMamd5TkRJeE9TQXlPQzQzT1RFd09EazFMREl4TGpjMk9UVXpNU0JETWpndU56Z3pN'
    || 'amMzTlN3eU1pNDNNVEE1TXpnZ01qa3VNalkzTmpVeU5Td3lNeTQyTWpnNU1EWWdNekF1TVRNNE56UTJOU3d5TkM0eE1qZzVNRFlnVERNNUxqTXhORFV5TnpV'
    || 'c01qa3VOREk1TmpnNElFTTBNQzQyTURNMU9EazFMRE13TGpFM01UZzNOU0EwTWk0eU5USXdNamMxTERJNUxqY3pNRFEyT1NBME1pNDVPVGd4TWpFMUxESTRM'
    || 'alEwTVRRd05pQkRORE11TnpRME1qRTFOU3d5Tnk0eE5USXpORFFnTkRNdU1qazRPVEF5TlN3eU5TNDFNRE01TURZZ05ESXVNREE1T0RNNU5Td3lOQzQzTlRj'
    || 'NE1USWdURE0yTGpneE5EVXlOelVzTWpFdU56VTNPREV5SUV3ME1pNHdNRGs0TXprMUxERTRMamMxTnpneE1pQkRORE11TXpBeU9EQTROU3d4T0M0d01UVTJN'
    || 'alVnTkRNdU56UTBNakUxTlN3eE5pNHpOamN4T0RnZ05ESXVPVGs0TVRJeE5Td3hOUzR3TnpneE1qVWlmU2xkZlNsOVkyOXVjM1FnUTJNOWUyOTJaWEoyYVdW'
    || 'M09tOHVhbk40Y3lodkxrWnlZV2R0Wlc1MExIdGphR2xzWkhKbGJqcGJieTVxYzNnb0luSmxZM1FpTEh0NE9pSXlJaXg1T2lJeUlpeDNhV1IwYURvaU5TNDFJ'
    || 'aXhvWldsbmFIUTZJalV1TlNJc2NuZzZJakV1TWlKOUtTeHZMbXB6ZUNnaWNtVmpkQ0lzZTNnNklqZ3VOU0lzZVRvaU1pSXNkMmxrZEdnNklqVXVOU0lzYUdW'
    || 'cFoyaDBPaUkxTGpVaUxISjRPaUl4TGpJaWZTa3NieTVxYzNnb0luSmxZM1FpTEh0NE9pSXlJaXg1T2lJNExqVWlMSGRwWkhSb09pSTFMalVpTEdobGFXZG9k'
    || 'RG9pTlM0MUlpeHllRG9pTVM0eUluMHBMRzh1YW5ONEtDSnlaV04wSWl4N2VEb2lPQzQxSWl4NU9pSTRMalVpTEhkcFpIUm9PaUkxTGpVaUxHaGxhV2RvZERv'
    || 'aU5TNDFJaXh5ZURvaU1TNHlJbjBwWFgwcExIQmxiM0JzWlRwdkxtcHplSE1vYnk1R2NtRm5iV1Z1ZEN4N1kyaHBiR1J5Wlc0NlcyOHVhbk40S0NKamFYSmpi'
    || 'R1VpTEh0amVEb2lOaUlzWTNrNklqVXVOU0lzY2pvaU1pNDBJbjBwTEc4dWFuTjRLQ0p3WVhSb0lpeDdaRG9pVFRJZ01UTXVOV013TFRJdU1pQXhMamd0TXk0'
    || 'MklEUXRNeTQyY3pRZ01TNDBJRFFnTXk0MkluMHBMRzh1YW5ONEtDSndZWFJvSWl4N1pEb2lUVEV4SURRdU1tRXlMaklnTWk0eUlEQWdNQ0F4SURBZ05DNHpU'
    || 'VEV4TGpZZ01UTXVOV013TFRFdU55MHVOeTB5TGprdE1TNDRMVE11TkNKOUtWMTlLU3h6WldkdFpXNTBjenB2TG1wemVITW9ieTVHY21GbmJXVnVkQ3g3WTJo'
    || 'cGJHUnlaVzQ2VzI4dWFuTjRLQ0pqYVhKamJHVWlMSHRqZURvaU5pSXNZM2s2SWpZaUxISTZJak11TmlKOUtTeHZMbXB6ZUNnaVkybHlZMnhsSWl4N1kzZzZJ'
    || 'akV3SWl4amVUb2lNVEFpTEhJNklqTXVOaUo5S1YxOUtTeHBaR1Z1ZEdsMGVUcHZMbXB6ZUhNb2J5NUdjbUZuYldWdWRDeDdZMmhwYkdSeVpXNDZXMjh1YW5O'
    || 'NEtDSndZWFJvSWl4N1pEb2lUVGdnTW1FeklETWdNQ0F3SURFZ015QXpkakVpZlNrc2J5NXFjM2dvSW5CaGRHZ2lMSHRrT2lKTk5TQTJWalZoTXlBeklEQWdN'
    || 'Q0F4SURFdE1pNHlJbjBwTEc4dWFuTjRLQ0p3WVhSb0lpeDdaRG9pVFRRdU5TQTNMalZqTUNBeklERWdOQzQxSURNdU5TQTJMalVpZlNrc2J5NXFjM2dvSW5C'
    || 'aGRHZ2lMSHRrT2lKTk9DQTJkak11TlNKOUtTeHZMbXB6ZUNnaWNHRjBhQ0lzZTJRNklrMHhNUzQxSURjdU5XTXdJREl0TGpRZ015NHpMVEV1TWlBMExqUWlm'
    || 'U2xkZlNrc1kyOTJaWEpoWjJVNmJ5NXFjM2h6S0c4dVJuSmhaMjFsYm5Rc2UyTm9hV3hrY21WdU9sdHZMbXB6ZUNnaVkybHlZMnhsSWl4N1kzZzZJamdpTEdO'
    || 'NU9pSTRJaXh5T2lJMkluMHBMRzh1YW5ONEtDSndZWFJvSWl4N1pEb2lUVGdnTW1FMklEWWdNQ0F3SURFZ01DQXhNaUlzWm1sc2JEb2lZM1Z5Y21WdWRFTnZi'
    || 'Rzl5SWl4emRISnZhMlU2SW01dmJtVWlMRzl3WVdOcGRIazZJaTR5TWlKOUtTeHZMbXB6ZUNnaWNHRjBhQ0lzZTJRNklrMDRJRFF1TlhZekxqVnNNaTQxSURF'
    || 'dU5pSjlLVjE5S1N4dGIyNWxlVHB2TG1wemVITW9ieTVHY21GbmJXVnVkQ3g3WTJocGJHUnlaVzQ2VzI4dWFuTjRLQ0p3WVhSb0lpeDdaRG9pVFRnZ01TNDRk'
    || 'akV5TGpRaWZTa3NieTVxYzNnb0luQmhkR2dpTEh0a09pSk5NVEVnTkM0Mll6QXRNUzR4TFRFdU15MHhMamt0TXkweExqbHpMVE1nTGpndE15QXhMamxqTUNB'
    || 'eExqSWdNUzR5SURFdU55QXpJREl1TW5NeklERWdNeUF5TGpOak1DQXhMakl0TVM0eklESXRNeUF5Y3kwekxTNDRMVE10TWlKOUtWMTlLU3h6YUdsbGJHUTZi'
    || 'eTVxYzNoektHOHVSbkpoWjIxbGJuUXNlMk5vYVd4a2NtVnVPbHR2TG1wemVDZ2ljR0YwYUNJc2UyUTZJazA0SURFdU9DQXpJRE11T0hZMFl6QWdNeUF5TGpF'
    || 'Z05TNDBJRFVnTmk0MElESXVPUzB4SURVdE15NDBJRFV0Tmk0MGRpMDBXaUo5S1N4dkxtcHplQ2dpY0dGMGFDSXNlMlE2SWswMklEZ3VNV3d4TGpZZ01TNDJU'
    || 'REV3TGpRZ05pNDJJbjBwWFgwcExIUmhZbXhsT204dWFuTjRjeWh2TGtaeVlXZHRaVzUwTEh0amFHbHNaSEpsYmpwYmJ5NXFjM2dvSW5KbFkzUWlMSHQ0T2lJ'
    || 'eUlpeDVPaUl5TGpnaUxIZHBaSFJvT2lJeE1pSXNhR1ZwWjJoME9pSXhNQzQwSWl4eWVEb2lNUzQwSW4wcExHOHVhbk40S0NKd1lYUm9JaXg3WkRvaVRUSWdO'
    || 'aTR6YURFeVRUWXVOQ0EyTGpOMk5pNDVJbjBwWFgwcExHWnNiM2M2Ynk1cWMzaHpLRzh1Um5KaFoyMWxiblFzZTJOb2FXeGtjbVZ1T2x0dkxtcHplQ2dpY21W'
    || 'amRDSXNlM2c2SWpFdU5pSXNlVG9pTlM0NElpeDNhV1IwYURvaU5DSXNhR1ZwWjJoME9pSTBMalFpTEhKNE9pSXhMakVpZlNrc2J5NXFjM2dvSW5KbFkzUWlM'
    || 'SHQ0T2lJeE1DNDBJaXg1T2lJeUxqUWlMSGRwWkhSb09pSTBJaXhvWldsbmFIUTZJalF1TkNJc2NuZzZJakV1TVNKOUtTeHZMbXB6ZUNnaWNtVmpkQ0lzZTNn'
    || 'NklqRXdMalFpTEhrNklqa3VNaUlzZDJsa2RHZzZJalFpTEdobGFXZG9kRG9pTkM0MElpeHllRG9pTVM0eEluMHBMRzh1YW5ONEtDSndZWFJvSWl4N1pEb2lU'
    || 'VFV1TmlBNGFESXVNbUV4TGpJZ01TNHlJREFnTUNBd0lERXVNaTB4TGpKV05DNDJhREV1TkUwMUxqWWdPR2d5TGpKaE1TNHlJREV1TWlBd0lEQWdNU0F4TGpJ'
    || 'Z01TNHlkakl1TW1neExqUWlmU2xkZlNrc1kyaGxZMnM2Ynk1cWMzaHpLRzh1Um5KaFoyMWxiblFzZTJOb2FXeGtjbVZ1T2x0dkxtcHplQ2dpWTJseVkyeGxJ'
    || 'aXg3WTNnNklqZ2lMR041T2lJNElpeHlPaUkySW4wcExHOHVhbk40S0NKd1lYUm9JaXg3WkRvaVRUVXVOQ0E0TGpJZ055NHlJREV3YkRNdU5DMHpMamNpZlNs'
    || 'ZGZTa3NkMkZ5YmpwdkxtcHplSE1vYnk1R2NtRm5iV1Z1ZEN4N1kyaHBiR1J5Wlc0NlcyOHVhbk40S0NKd1lYUm9JaXg3WkRvaVRUZ2dNaTQwSURFdU9TQXhN'
    || 'Mmd4TWk0eVREZ2dNaTQwV2lKOUtTeHZMbXB6ZUNnaWNHRjBhQ0lzZTJRNklrMDRJRFl1TkhZelRUZ2dNVEV1TTNZdU1TSjlLVjE5S1N4emNHRnlhenB2TG1w'
    || 'emVITW9ieTVHY21GbmJXVnVkQ3g3WTJocGJHUnlaVzQ2VzI4dWFuTjRLQ0p3WVhSb0lpeDdaRG9pVFRJZ01URXVOR3d6TGpJdE15NDJJREl1TkNBeUlEUXVO'
    || 'QzAxSW4wcExHOHVhbk40S0NKd1lYUm9JaXg3WkRvaVRURXlJRFF1T0dndE1pNDJUVEV5SURRdU9IWXlMallpZlNsZGZTa3NZMnh2WTJzNmJ5NXFjM2h6S0c4'
    || 'dVJuSmhaMjFsYm5Rc2UyTm9hV3hrY21WdU9sdHZMbXB6ZUNnaVkybHlZMnhsSWl4N1kzZzZJamdpTEdONU9pSTRJaXh5T2lJMkluMHBMRzh1YW5ONEtDSndZ'
    || 'WFJvSWl4N1pEb2lUVGdnTkM0MlZqaHNNaTQySURFdU55SjlLVjE5S1N4c1lYbGxjbk02Ynk1cWMzaHpLRzh1Um5KaFoyMWxiblFzZTJOb2FXeGtjbVZ1T2x0'
    || 'dkxtcHplQ2dpY0dGMGFDSXNlMlE2SWswNElERXVPU0F5SURWc05pQXpMakZNTVRRZ05TQTRJREV1T1ZvaWZTa3NieTVxYzNnb0luQmhkR2dpTEh0a09pSk5N'
    || 'aUE0TGpRZ09DQXhNUzQxYkRZdE15NHhUVElnTVRFdU5DQTRJREUwTGpWc05pMHpMakVpZlNsZGZTbDlPMloxYm1OMGFXOXVJRlJqS0h0dVlXMWxPblVzYzJs'
    || 'NlpUcGtQVEUxZlNsN2NtVjBkWEp1SUc4dWFuTjRLQ0p6ZG1jaUxIdDNhV1IwYURwa0xHaGxhV2RvZERwa0xIWnBaWGRDYjNnNklqQWdNQ0F4TmlBeE5pSXNa'
    || 'bWxzYkRvaWJtOXVaU0lzYzNSeWIydGxPaUpqZFhKeVpXNTBRMjlzYjNJaUxITjBjbTlyWlZkcFpIUm9PaUl4TGpVMUlpeHpkSEp2YTJWTWFXNWxZMkZ3T2lK'
    || 'eWIzVnVaQ0lzYzNSeWIydGxUR2x1WldwdmFXNDZJbkp2ZFc1a0lpd2lZWEpwWVMxb2FXUmtaVzRpT2lKMGNuVmxJaXhqYUdsc1pISmxianBEWTF0MVhYMHBm'
    || 'V1oxYm1OMGFXOXVJRkpqS0h0emIyeDFkR2x2YmpwMUxITjFZblJwZEd4bE9tUXNjMlZqZEdsdmJuTTZZU3hoWTNScGRtVTZaeXh2YmxCcFkyczZlQ3htYjI5'
    || 'ME9rTjlLWHRqYjI1emRDQlRQVTQ5UGs0dWRHOU1iM2RsY2tOaGMyVW9LUzV5WlhCc1lXTmxLQzliWG1FdGVqQXRPVjByTDJjc0lpSXBMSGM5VXloMUtTeGZQ'
    || 'V1EvVXloa0tUb2lJaXhNUFNFaFh5WW1JWGN1YVc1amJIVmtaWE1vWHlrbUppRmZMbWx1WTJ4MVpHVnpLSGNwTzNKbGRIVnliaUJ2TG1wemVITW9JbUZ6YVdS'
    || 'bElpeDdZMnhoYzNOT1lXMWxPaUp6YVdSbElpeGphR2xzWkhKbGJqcGJieTVxYzNoektDSmthWFlpTEh0amJHRnpjMDVoYldVNkluTnBaR1ZmWDJKeVlXNWtJ'
    || 'aXhqYUdsc1pISmxianBiYnk1cWMzZ29hbU1zZTNOcGVtVTZNako5S1N4dkxtcHplSE1vSW1ScGRpSXNlM04wZVd4bE9udHRhVzVYYVdSMGFEb3dmU3hqYUds'
    || 'c1pISmxianBiYnk1cWMzZ29JbVJwZGlJc2UyTnNZWE56VG1GdFpUb2ljMmxrWlY5ZmQyOXlaRzFoY21zaUxHTm9hV3hrY21WdU9uVjlLU3hNUDI4dWFuTjRL'
    || 'Q0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbk5wWkdWZlgzTjFZaUlzWTJocGJHUnlaVzQ2WkgwcE9tNTFiR3hkZlNsZGZTa3NieTVxYzNnb0ltNWhkaUlzZTJO'
    || 'c1lYTnpUbUZ0WlRvaWJtRjJJaXhqYUdsc1pISmxianBoTG0xaGNDZ29UaXhQS1QwK2UyTnZibk4wSUVZOVR6NHdQMkZiVHkweFhTNW5jbTkxY0RwMmIybGtJ'
    || 'REFzU3oxT0xtZHliM1Z3SmlaT0xtZHliM1Z3SVQwOVJqOU9MbWR5YjNWd09tNTFiR3dzUnoxdkxtcHplSE1vSW1KMWRIUnZiaUlzZTJOc1lYTnpUbUZ0WlRv'
    || 'aWJtRjJYMTlwZEdWdElpc29UaTVuY205MWNEOGlJRzVoZGw5ZmFYUmxiUzB0YzNWaUlqb2lJaWtyS0U0dWFXUTlQVDFuUHlJZ2JtRjJYMTlwZEdWdExTMXZi'
    || 'aUk2SWlJcExDSmtZWFJoTFc5dVpYTm9iM1FpT2lKdVlYWXRhWFJsYlNJc0ltUmhkR0V0YzJWamRHbHZiaUk2VGk1cFpDeHZia05zYVdOck9pZ3BQVDU0S0U0'
    || 'dWFXUXBMQ0poY21saExXTjFjbkpsYm5RaU9rNHVhV1E5UFQxblB5SndZV2RsSWpwMmIybGtJREFzWTJocGJHUnlaVzQ2VzI4dWFuTjRLRlJqTEh0dVlXMWxP'
    || 'azR1YVdOdmJqOC9JbTkyWlhKMmFXVjNJbjBwTEc4dWFuTjRjeWdpYzNCaGJpSXNlM04wZVd4bE9udHRhVzVYYVdSMGFEb3dMR1pzWlhnNk1YMHNZMmhwYkdS'
    || 'eVpXNDZXMjh1YW5ONEtDSnpjR0Z1SWl4N1kyeGhjM05PWVcxbE9pSnVZWFpmWDJ4aFltVnNJaXhqYUdsc1pISmxianBPTG14aFltVnNmU2tzVGk1a1pYTmpQ'
    || 'Mjh1YW5ONEtDSnpjR0Z1SWl4N1kyeGhjM05PWVcxbE9pSnVZWFpmWDJSbGMyTWlMR05vYVd4a2NtVnVPazR1WkdWelkzMHBPbTUxYkd4ZGZTa3NUaTVpWVdS'
    || 'blpUOXZMbXB6ZUNnaWMzQmhiaUlzZTJOc1lYTnpUbUZ0WlRvaWJtRjJYMTlpWVdSblpTQnVZWFpmWDJKaFpHZGxMUzBpS3loT0xtSmhaR2RsVkc5dVpUOC9J'
    || 'bWxrYkdVaUtTeGphR2xzWkhKbGJqcE9MbUpoWkdkbGZTazZiblZzYkN4T0xuTjBZWFIxY3o5dkxtcHplQ2dpYzNCaGJpSXNlMk5zWVhOelRtRnRaVG9pYm1G'
    || 'MlgxOWtiM1FnYm1GMlgxOWtiM1F0TFNJclRpNXpkR0YwZFhOOUtUcHVkV3hzWFgwc1RpNXBaQ2s3Y21WMGRYSnVJRXMvYnk1cWMzaHpLRUYwTGtaeVlXZHRa'
    || 'VzUwTEh0amFHbHNaSEpsYmpwYmJ5NXFjM2dvSW1neUlpeDdZMnhoYzNOT1lXMWxPaUp1WVhaZlgyZHliM1Z3SWl4amFHbHNaSEpsYmpwT0xtZHliM1Z3ZlNr'
    || 'c1IxMTlMQ0puT2lJclR5azZSMzBwZlNrc1F6OXZMbXB6ZUNnaVpHbDJJaXg3WTJ4aGMzTk9ZVzFsT2lKemFXUmxYMTltYjI5MElpeGphR2xzWkhKbGJqcERm'
    || 'U2s2Ym5Wc2JGMTlLWDFtZFc1amRHbHZiaUJEZENoN2JHRmlaV3c2ZFN4MllXeDFaVHBrTEhWdWFYUTZZU3h6ZFdJNlp5eDBiMjVsT25oOUtYdHlaWFIxY200'
    || 'Z2J5NXFjM2h6S0NKa2FYWWlMSHRqYkdGemMwNWhiV1U2SW5OMFlYUWlLeWg0UHlJZ2MzUmhkQzB0SWl0NE9pSWlLU3dpWkdGMFlTMXZibVZ6YUc5MElqb2lj'
    || 'M1JoZENJc1kyaHBiR1J5Wlc0NlcyOHVhbk40S0NKa2FYWWlMSHRqYkdGemMwNWhiV1U2SW5OMFlYUmZYMnhoWW1Wc0lpeGphR2xzWkhKbGJqcDFmU2tzYnk1'
    || 'cWMzaHpLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbk4wWVhSZlgzWmhiSFZsSWl4amFHbHNaSEpsYmpwYlpDeGhQMjh1YW5ONEtDSnpjR0Z1SWl4N1kyeGhj'
    || 'M05PWVcxbE9pSnpkR0YwWDE5MWJtbDBJaXhqYUdsc1pISmxianBoZlNrNmJuVnNiRjE5S1N4blAyOHVhbk40S0NKa2FYWWlMSHRqYkdGemMwNWhiV1U2SW5O'
    || 'MFlYUmZYM04xWWlJc1kyaHBiR1J5Wlc0NlozMHBPbTUxYkd4ZGZTbDlablZ1WTNScGIyNGdSbVVvZTNScGRHeGxPblVzYUdsdWREcGtMR05vYVd4a2NtVnVP'
    || 'bUVzZDJsa1pUcG5mU2w3Y21WMGRYSnVJRzh1YW5ONGN5Z2ljMlZqZEdsdmJpSXNlMk5zWVhOelRtRnRaVG9pWTJGeVpDSXJLR2MvSWlCallYSmtMUzEzYVdS'
    || 'bElqb2lJaWtzSW1SaGRHRXRiMjVsYzJodmRDSTZJbU5oY21RaUxHTm9hV3hrY21WdU9sdHZMbXB6ZUhNb0ltaGxZV1JsY2lJc2UyTnNZWE56VG1GdFpUb2lZ'
    || 'MkZ5WkY5ZmFHVmhaQ0lzWTJocGJHUnlaVzQ2VzI4dWFuTjRLQ0pvTWlJc2UyTm9hV3hrY21WdU9uVjlLU3hrUDI4dWFuTjRLQ0p3SWl4N1kyeGhjM05PWVcx'
    || 'bE9pSmpZWEprWDE5b2FXNTBJaXhqYUdsc1pISmxianBrZlNrNmJuVnNiRjE5S1N4aFhYMHBmV1oxYm1OMGFXOXVJRXhsS0h0d1lXNWxiRHAxTEhkb1pXNU5h'
    || 'WE56YVc1bk9tUXNibTkwUW5WcGJIUkNiRzlqYXpwaExHTm9hV3hrY21WdU9tZDlLWHRwWmlnaGRTbHlaWFIxY200Z1lUOXZMbXB6ZUNodkxrWnlZV2R0Wlc1'
    || 'MExIdGphR2xzWkhKbGJqcGhmU2s2Ynk1cWMzaHpLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbkJoYm1Wc0xXNXZkR0oxYVd4MElpd2laR0YwWVMxdmJtVnph'
    || 'RzkwSWpvaWNHRnVaV3d0Ym05MFluVnBiSFFpTEdOb2FXeGtjbVZ1T2x0dkxtcHplQ2dpYzNSeWIyNW5JaXg3WTJocGJHUnlaVzQ2SWxSb2FYTWdjblZ1SUdS'
    || 'cFpDQnViM1FnWW5WcGJHUWdkR2hwY3lCd1lYSjBMaUo5S1N4dkxtcHplQ2dpY0NJc2UyTm9hV3hrY21WdU9tUS9QeUpVYUdVZ2MyTnlhWEIwSUhKaGJpQnBi'
    || 'aUJwZEhNZ1pHVm1ZWFZzZEN3Z2NtVmhaQzF2Ym14NUlHMXZaR1VzSUhkb2FXTm9JR2x1YzNCbFkzUnpJSGx2ZFhJZ1lXTmpiM1Z1ZENCM2FYUm9iM1YwSUdO'
    || 'eVpXRjBhVzVuSUdGdWVYUm9hVzVuTGlCR2FXeHNJR2x1SUhSb1pTQnpaWFIwYVc1bmN5QmhkQ0IwYUdVZ2RHOXdJRzltSUhSb1pTQnpZM0pwY0hRZ1lXNWtJ'
    || 'SEoxYmlCcGRDQmhaMkZwYmlCMGJ5QmlkV2xzWkNCMGFHbHpMaUo5S1YxOUtUdHBaaWg0YmloMUtTbHlaWFIxY200Z1lUOXZMbXB6ZUNodkxrWnlZV2R0Wlc1'
    || 'MExIdGphR2xzWkhKbGJqcGhmU2s2Ynk1cWMzaHpLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbkJoYm1Wc0xXNXZkR0oxYVd4MElpd2laR0YwWVMxdmJtVnph'
    || 'RzkwSWpvaWNHRnVaV3d0Ym05MFluVnBiSFFpTEdOb2FXeGtjbVZ1T2x0dkxtcHplQ2dpYzNSeWIyNW5JaXg3WTJocGJHUnlaVzQ2SWxSb2FYTWdjR0Z5ZENC'
    || 'b1lYTWdibTkwSUdKbFpXNGdZblZwYkhRZ2VXVjBMaUo5S1N4dkxtcHplQ2dpY0NJc2UyTm9hV3hrY21WdU9tUS9QeUpVYUdseklISjFiaUJrYVdRZ2JtOTBJ'
    || 'R055WldGMFpTQjBhR1VnYjJKcVpXTjBjeUIwYUdseklHTmhjbVFnY21WaFpITXVJRVpwYkd3Z2FXNGdkR2hsSUhObGRIUnBibWR6SUdGMElIUm9aU0IwYjNB'
    || 'Z2IyWWdkR2hsSUhOamNtbHdkQ0JoYm1RZ2NuVnVJR2wwSUdGbllXbHVMaUo5S1N4dkxtcHplQ2dpY0NJc2UyTnNZWE56VG1GdFpUb2ljR0Z1Wld3dGJtOTBZ'
    || 'blZwYkhSZlgyRnNkQ0lzWTJocGJHUnlaVzQ2SjBsbUlIbHZkU0JsZUhCbFkzUmxaQ0JwZENCMGJ5QmxlR2x6ZEN3Z2RHaGxJSE5oYldVZ1UyNXZkMlpzWVd0'
    || 'bElHVnljbTl5SUdOdmRtVnljeUFpYm05MElHRjFkR2h2Y21sNlpXUWlJT0tBbENCNWIzVWdiV0Y1SUdKbElHMXBjM05wYm1jZ1lTQm5jbUZ1ZENCeVlYUm9a'
    || 'WElnZEdoaGJpQmhJR0oxYVd4a0xpZDlLVjE5S1R0cFppaDViaWgxS1NseVpYUjFjbTRnYnk1cWMzaHpLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbkJoYm1W'
    || 'c0xXVnljbTl5SWl3aVpHRjBZUzF2Ym1WemFHOTBJam9pY0dGdVpXd3RaWEp5YjNJaUxHTm9hV3hrY21WdU9sdHZMbXB6ZUNnaWMzUnliMjVuSWl4N1kyaHBi'
    || 'R1J5Wlc0NklsUm9hWE1nY1hWbGNua2daR2xrSUc1dmRDQnlkVzR1SW4wcExHOHVhbk40S0NKamIyUmxJaXg3WTJocGJHUnlaVzQ2ZFM1bGNuSnZjbjBwWFgw'
    || 'cE8ybG1LQ0YxTG5KdmQzTXViR1Z1WjNSb0tYSmxkSFZ5YmlCdkxtcHplQ2dpY0NJc2UyTnNZWE56VG1GdFpUb2ljR0Z1Wld3dFpXMXdkSGtpTENKa1lYUmhM'
    || 'Vzl1WlhOb2IzUWlPaUp3WVc1bGJDMWxiWEIwZVNJc1kyaHBiR1J5Wlc0NklsUm9aU0J4ZFdWeWVTQnlZVzRnWVc1a0lISmxkSFZ5Ym1Wa0lHNXZJSEp2ZDNN'
    || 'dUluMHBPMk52Ym5OMElIZzlVMk1vZFNrN2NtVjBkWEp1SUc4dWFuTjRjeWh2TGtaeVlXZHRaVzUwTEh0amFHbHNaSEpsYmpwYmVEOXZMbXB6ZUhNb0luQWlM'
    || 'SHRqYkdGemMwNWhiV1U2SW5CaGJtVnNMWFJ5ZFc1aklpd2laR0YwWVMxdmJtVnphRzkwSWpvaWNHRnVaV3d0ZEhKMWJtTmhkR1ZrSWl4amFHbHNaSEpsYmpw'
    || 'YklsTm9iM2RwYm1jZ2RHaGxJR1pwY25OMElDSXNXU2g0S1N3aUlISnZkM011SUZSb2FYTWdjWFZsY25rZ2NtVjBkWEp1WldRZ2JXOXlaU3dnYzI4Z1lXNTVJ'
    || 'SFJ2ZEdGc0lHOXVJSFJvYVhNZ1kyRnlaQ0JwY3lCaElHWnNiMjl5TENCdWIzUWdZU0JqYjNWdWRDNGlYWDBwT201MWJHd3NaMTE5S1gxbWRXNWpkR2x2YmlC'
    || 'VGJpaDdjbTkzY3pwMUxHTnZiSE02WkN4dFlYZzZZU3h2YmxCcFkyczZaeXhoWTNScGRtVTZlSDBwZTJOdmJuTjBJRU05WVQ5MUxuTnNhV05sS0RBc1lTazZk'
    || 'VHR5WlhSMWNtNGdieTVxYzNoektDSmthWFlpTEh0amJHRnpjMDVoYldVNkluUmhZbXhsTFhkeVlYQWlMR05vYVd4a2NtVnVPbHR2TG1wemVITW9JblJoWW14'
    || 'bElpeDdZMnhoYzNOT1lXMWxPbWMvSW5SaFlteGxMUzF3YVdOcklqb2lJaXhqYUdsc1pISmxianBiYnk1cWMzZ29JblJvWldGa0lpeDdZMmhwYkdSeVpXNDZi'
    || 'eTVxYzNnb0luUnlJaXg3WTJocGJHUnlaVzQ2WkM1dFlYQW9VejArYnk1cWMzZ29JblJvSWl4N1kyeGhjM05PWVcxbE9sTXVZV3hwWjI0OVBUMGljbWxuYUhR'
    || 'aVB5SnlJam9pSWl4amFHbHNaSEpsYmpwVExteGhZbVZzUHo5VExtdGxlWDBzVXk1clpYa3BLWDBwZlNrc2J5NXFjM2dvSW5SaWIyUjVJaXg3WTJocGJHUnla'
    || 'VzQ2UXk1dFlYQW9LRk1zZHlrOVBtOHVhbk40S0NKMGNpSXNlMk5zWVhOelRtRnRaVHBuSmlaM1BUMDllRDhpZEhJdExXOXVJam9pSWl4dmJrTnNhV05yT21j'
    || 'L0tDazlQbWNvVXl4M0tUcDJiMmxrSURBc2RHRmlTVzVrWlhnNlp6OHdPblp2YVdRZ01Dd2lZWEpwWVMxelpXeGxZM1JsWkNJNlp6OTNQVDA5ZURwMmIybGtJ'
    || 'REFzYjI1TFpYbEViM2R1T21jL0tGODlQbnNvWHk1clpYazlQVDBpUlc1MFpYSWlmSHhmTG10bGVUMDlQU0lnSWlrbUppaGZMbkJ5WlhabGJuUkVaV1poZFd4'
    || 'MEtDa3NaeWhUTEhjcEtYMHBPblp2YVdRZ01DeGphR2xzWkhKbGJqcGtMbTFoY0NoZlBUNXZMbXB6ZUNnaWRHUWlMSHRqYkdGemMwNWhiV1U2WHk1aGJHbG5i'
    || 'ajA5UFNKeWFXZG9kQ0kvSW5JaU9pSWlMR05vYVd4a2NtVnVPbDh1Y21WdVpHVnlQMTh1Y21WdVpHVnlLRk5iWHk1clpYbGRMRk1wT2s5aktGTmJYeTVyWlhs'
    || 'ZEtYMHNYeTVyWlhrcEtYMHNkeWtwZlNsZGZTa3NZU1ltZFM1c1pXNW5kR2crWVQ5dkxtcHplSE1vSW5BaUxIdGpiR0Z6YzA1aGJXVTZJblJoWW14bExXMXZj'
    || 'bVVpTEdOb2FXeGtjbVZ1T2x0WktIVXViR1Z1WjNSb0xXRXBMQ0lnYlc5eVpTQnliM2NvY3lrZ2JtOTBJSE5vYjNkdUlsMTlLVHB1ZFd4c1hYMHBmV1oxYm1O'
    || 'MGFXOXVJRTlqS0hVcGUybG1LSFU5UFc1MWJHd3BjbVYwZFhKdUlHOHVhbk40S0NKemNHRnVJaXg3WTJ4aGMzTk9ZVzFsT2lKdWRXeHNJaXhqYUdsc1pISmxi'
    || 'am9pVGxWTVRDSjlLVHRqYjI1emRDQmtQWHAwS0hVcE8zSmxkSFZ5YmlCa0lUMDliblZzYkQ5WktHUXBPbE4wY21sdVp5aDFLWDFtZFc1amRHbHZiaUIxY3lo'
    || 'N1pHRjBZVHAxTEhWdWFYUTZaQ3h0WVhnNllYMHBlMk52Ym5OMElHYzlZVDkxTG5Oc2FXTmxLREFzWVNrNmRTeDRQVTFoZEdndWJXRjRLQzR1TG1jdWJXRndL'
    || 'RU05UGtNdWRtRnNkV1VwTERBcGZId3hPM0psZEhWeWJpQnZMbXB6ZUNnaVpHbDJJaXg3WTJ4aGMzTk9ZVzFsT2lKaVlYSnpJaXhqYUdsc1pISmxianBuTG0x'
    || 'aGNDaERQVDV2TG1wemVITW9JbVJwZGlJc2UyTnNZWE56VG1GdFpUb2lZbUZ5SWl4amFHbHNaSEpsYmpwYmJ5NXFjM2dvSW1ScGRpSXNlMk5zWVhOelRtRnRa'
    || 'VG9pWW1GeVgxOXNZV0psYkNJc2RHbDBiR1U2UXk1c1lXSmxiQ3hqYUdsc1pISmxianBETG14aFltVnNmU2tzYnk1cWMzZ29JbVJwZGlJc2UyTnNZWE56VG1G'
    || 'dFpUb2lZbUZ5WDE5MGNtRmpheUlzWTJocGJHUnlaVzQ2Ynk1cWMzZ29JbVJwZGlJc2UyTnNZWE56VG1GdFpUb2lZbUZ5WDE5bWFXeHNJaXNvUXk1MGIyNWxQ'
    || 'eUlnWW1GeVgxOW1hV3hzTFMwaUswTXVkRzl1WlRvaUlpa3NjM1I1YkdVNmUzZHBaSFJvT2sxaGRHZ3ViV0Y0S0RFc1F5NTJZV3gxWlM5NEtqRXdNQ2tySWlV'
    || 'aWZYMHBmU2tzYnk1cWMzaHpLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbUpoY2w5ZmRtRnNkV1VpTEdOb2FXeGtjbVZ1T2x0WktFTXVkbUZzZFdVcExHUS9Q'
    || 'eUlpWFgwcFhYMHNReTVzWVdKbGJDa3BmU2w5Wm5WdVkzUnBiMjRnVFdNb2UzQmpkRHAxTEd4aFltVnNPbVFzYjJZNllTeDBiMjVsT21kOUtYdGpiMjV6ZENC'
    || 'NFBVMWhkR2d1YldGNEtEQXNUV0YwYUM1dGFXNG9NVEF3TEhVcEtUdHlaWFIxY200Z2J5NXFjM2h6S0NKa2FYWWlMSHRqYkdGemMwNWhiV1U2SW0xbGRHVnlM'
    || 'WEp2ZHlJc1kyaHBiR1J5Wlc0NlcyOHVhbk40Y3lnaVpHbDJJaXg3WTJ4aGMzTk9ZVzFsT2lKdFpYUmxjaTF5YjNkZlgyaGxZV1FpTEdOb2FXeGtjbVZ1T2x0'
    || 'dkxtcHplQ2dpYzNCaGJpSXNlMk5zWVhOelRtRnRaVG9pYldWMFpYSXRjbTkzWDE5c1lXSmxiQ0lzWTJocGJHUnlaVzQ2WkgwcExHOHVhbk40Y3lnaWMzQmhi'
    || 'aUlzZTJOc1lYTnpUbUZ0WlRvaWJXVjBaWEl0Y205M1gxOTJZV3gxWlNJc1kyaHBiR1J5Wlc0NlczZ3VkRzlHYVhobFpDZ3hLU3dpSlNJc1lUOXZMbXB6ZUNn'
    || 'aWMzQmhiaUlzZTJOc1lYTnpUbUZ0WlRvaWJXVjBaWEl0Y205M1gxOXZaaUlzWTJocGJHUnlaVzQ2WVgwcE9tNTFiR3hkZlNsZGZTa3NieTVxYzNnb0ltUnBk'
    || 'aUlzZTJOc1lYTnpUbUZ0WlRvaWJXVjBaWElpTEdOb2FXeGtjbVZ1T204dWFuTjRLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbTFsZEdWeVgxOW1hV3hzSWlz'
    || 'b1p6OGlJRzFsZEdWeVgxOW1hV3hzTFMwaUsyYzZJaUlwTEhOMGVXeGxPbnQzYVdSMGFEcDRLeUlsSW4xOUtYMHBYWDBwZldaMWJtTjBhVzl1SUVSaktIdHdZ'
    || 'M1E2ZFN4MGIyNWxPbVI5S1h0amIyNXpkQ0JoUFUxaGRHZ3ViV0Y0S0RBc1RXRjBhQzV0YVc0b01UQXdMSFVwS1R0eVpYUjFjbTRnYnk1cWMzaHpLQ0prYVhZ'
    || 'aUxIdGpiR0Z6YzA1aGJXVTZJbTFsZEdWeUlHMWxkR1Z5TFMxalpXeHNJaXhqYUdsc1pISmxianBiYnk1cWMzZ29JbVJwZGlJc2UyTnNZWE56VG1GdFpUb2li'
    || 'V1YwWlhKZlgyWnBiR3dpS3loa1B5SWdiV1YwWlhKZlgyWnBiR3d0TFNJclpEb2lJaWtzYzNSNWJHVTZlM2RwWkhSb09tRXJJaVVpZlgwcExHOHVhbk40Y3ln'
    || 'aWMzQmhiaUlzZTJOc1lYTnpUbUZ0WlRvaWJXVjBaWEpmWDNSbGVIUWlMR05vYVd4a2NtVnVPbHRoTG5SdlJtbDRaV1FvTVNrc0lpVWlYWDBwWFgwcGZXWjFi'
    || 'bU4wYVc5dUlISnVLSHRqYUdsc1pISmxianAxTEhSdmJtVTZaSDBwZTNKbGRIVnliaUJ2TG1wemVDZ2ljM0JoYmlJc2UyTnNZWE56VG1GdFpUb2ljR2xzYkNJ'
    || 'cktHUS9JaUJ3YVd4c0xTMGlLMlE2SWlJcExHTm9hV3hrY21WdU9uVjlLWDFtZFc1amRHbHZiaUJRWXloN2RHbDBiR1U2ZFN4amFHbHNaSEpsYmpwa2ZTbDdj'
    || 'bVYwZFhKdUlHOHVhbk40Y3lnaVpHbDJJaXg3WTJ4aGMzTk9ZVzFsT2lKallYWmxZWFFpTENKa1lYUmhMVzl1WlhOb2IzUWlPaUpqWVhabFlYUWlMR05vYVd4'
    || 'a2NtVnVPbHR2TG1wemVDZ2ljM1J5YjI1bklpeDdZMmhwYkdSeVpXNDZkWDBwTEc4dWFuTjRLQ0p3SWl4N1kyaHBiR1J5Wlc0NlpIMHBYWDBwZldaMWJtTjBh'
    || 'Vzl1SUZsdUtIdGphR2xzWkhKbGJqcDFmU2w3Y21WMGRYSnVJRzh1YW5ONEtDSmthWFlpTEh0amJHRnpjMDVoYldVNkltMWxkR2h2WkNJc0ltUmhkR0V0YjI1'
    || 'bGMyaHZkQ0k2SW0xbGRHaHZaQ0lzWTJocGJHUnlaVzQ2ZFgwcGZXWjFibU4wYVc5dUlFeGpLSHQyWVd4MVpUcDFMRzVoT21Rc2JtOXVaVHBoTEhScGRHeGxP'
    || 'bWQ5S1h0eVpYUjFjbTRnWkQ5dkxtcHplQ2dpYzNCaGJpSXNlMk5zWVhOelRtRnRaVG9pWTJWc2JDMHRibUVpTEhScGRHeGxPbWMvUHlKdWIzUWdZWEJ3Ykds'
    || 'allXSnNaVHNnWlhoamJIVmtaV1FnWm5KdmJTQjBhR1VnYzJOdmNtVWlMR05vYVd4a2NtVnVPaUpPTDBFaWZTazZZWHg4ZFQwOVBXNTFiR3g4ZkhVOVBUMTJi'
    || 'MmxrSURCOGZIVTlQVDBpSWo5dkxtcHplQ2dpYzNCaGJpSXNlMk5zWVhOelRtRnRaVG9pWTJWc2JDMHRibTl1WlNJc2RHbDBiR1U2Wno4L0ltNXZibVVnY0hK'
    || 'bGMyVnVkQ0lzWTJocGJHUnlaVzQ2SXVLQWxDSjlLVHB2TG1wemVDaHZMa1p5WVdkdFpXNTBMSHRqYUdsc1pISmxianAwZVhCbGIyWWdkVDA5SW01MWJXSmxj'
    || 'aUkvZFM1MGIweHZZMkZzWlZOMGNtbHVaeWdpWlc0dFZWTWlLVHAxZlNsOVpuVnVZM1JwYjI0Z1NXTW9lM3BsY204NmRTeHViMjVsT21Rc2JtRTZZWDBwZTNK'
    || 'bGRIVnliaUJ2TG1wemVITW9JbVJwZGlJc2UyTnNZWE56VG1GdFpUb2liV1YwYUc5a0lpd2laR0YwWVMxdmJtVnphRzkwSWpvaVpXMXdkSGt0YkdWblpXNWtJ'
    || 'aXhqYUdsc1pISmxianBiZFQ5dkxtcHplSE1vSW1ScGRpSXNlMk5vYVd4a2NtVnVPbHR2TG1wemVDZ2ljM1J5YjI1bklpeDdZMmhwYkdSeVpXNDZJakFpZlNr'
    || 'c0lpRGlnSlFnSWl4MVhYMHBPbTUxYkd3c1pEOXZMbXB6ZUhNb0ltUnBkaUlzZTJOb2FXeGtjbVZ1T2x0dkxtcHplQ2dpYzNSeWIyNW5JaXg3WTJocGJHUnla'
    || 'VzQ2SXVLQWxDSjlLU3dpSU9LQWxDQWlMR1JkZlNrNmJuVnNiQ3hoUDI4dWFuTjRjeWdpWkdsMklpeDdZMmhwYkdSeVpXNDZXMjh1YW5ONEtDSnpkSEp2Ym1j'
    || 'aUxIdGphR2xzWkhKbGJqb2lUaTlCSW4wcExDSWc0b0NVSUNJc1lWMTlLVHB1ZFd4c1hYMHBmV052Ym5OMElHSnNQVnNpVTBGTlVFeEZJaXdpVEVsTlNWUkZS'
    || 'Q0lzSWxCU1QwUlZRMVJKVDA0aVhTeGhjejE3VTBGTlVFeEZPaUpUWldWa1pXUWdaR0YwWVNEaWdKUWdjMkZtWlNCMGJ5QnlkVzRnY21Wd1pXRjBaV1JzZVN3'
    || 'Z2NISnZkbVZ6SUhSb1pTQnphR0Z3WlNCM2FYUm9iM1YwSUhSdmRXTm9hVzVuSUdGdWVYUm9hVzVuSUhKbFlXd3VJaXhNU1UxSlZFVkVPaUpaYjNWeUlHUmhk'
    || 'R0VzSUdSbGJHbGlaWEpoZEdWc2VTQmliM1Z1WkdWa0lPS0FsQ0JoSUhOMVluTmxkQ3dnWVNCallYQXNJRzl5SUdFZ2MybHVaMnhsSUc5aWFtVmpkQzRpTEZC'
    || 'U1QwUlZRMVJKVDA0NklsbHZkWElnWkdGMFlTd2dZWFFnWm5Wc2JDQnpZMjl3WlM0Z1VtVmhaQ0IwYUdVZ2RXNWtieUJzYVc1bElHSmxabTl5WlNCNWIzVWdj'
    || 'blZ1SUdsMExpSjlPMloxYm1OMGFXOXVJRUZqS0h0aFkzUnBiMjV6T25WOUtYdGpiMjV6ZEZ0a0xHRmRQVUYwTG5WelpWTjBZWFJsS0NFeEtTeG5QWHQ5TzJa'
    || 'dmNpaGpiMjV6ZENCVElHOW1JSFVwZTJOdmJuTjBJSGM5VTNSeWFXNW5LRk11VkVsRlVqOC9JbEJTVDBSVlExUkpUMDRpS1M1MGIxVndjR1Z5UTJGelpTZ3BP'
    || 'eWhuVzNkZFB6OG9aMXQzWFQxYlhTa3BMbkIxYzJnb1V5bDlZMjl1YzNRZ2VEMTFMbXhsYm1kMGFDeERQV0pzTG1acGJIUmxjaWhUUFQ1N2RtRnlJSGM3Y21W'
    || 'MGRYSnVLSGM5WjF0VFhTazlQVzUxYkd3L2RtOXBaQ0F3T25jdWJHVnVaM1JvZlNrdWJXRndLRk05UGloN2RHbGxjanBUTEdOdmRXNTBPbWRiVTEwdWJHVnVa'
    || 'M1JvZlNrcE8zSmxkSFZ5YmlCdkxtcHplSE1vYnk1R2NtRm5iV1Z1ZEN4N1kyaHBiR1J5Wlc0NlcyOHVhbk40Y3lnaVluVjBkRzl1SWl4N2RIbHdaVG9pWW5W'
    || 'MGRHOXVJaXhqYkdGemMwNWhiV1U2SW1GamRDMXpkVzF0WVhKNUlpeHZia05zYVdOck9pZ3BQVDVoS0ZNOVBpRlRLU3dpWVhKcFlTMWxlSEJoYm1SbFpDSTZa'
    || 'Q3hqYUdsc1pISmxianBiYnk1cWMzaHpLQ0p6Y0dGdUlpeDdZMnhoYzNOT1lXMWxPaUpoWTNRdGMzVnRiV0Z5ZVY5ZlkyOTFiblFpTEdOb2FXeGtjbVZ1T2x0'
    || 'WktIZ3BMQ0lnWVdOMGFXOXVJaXg0UFQwOU1UOGlJam9pY3lKZGZTa3NReTV0WVhBb0tIdDBhV1Z5T2xNc1kyOTFiblE2ZDMwcFBUNXZMbXB6ZUhNb0luTndZ'
    || 'VzRpTEh0amJHRnpjMDVoYldVNkltRmpkQzF6ZFcxdFlYSjVYMTkwYVdWeUlpeGphR2xzWkhKbGJqcGJVeXdpSUNJc2QxMTlMRk1wS1N4dkxtcHplQ2dpYzNa'
    || 'bklpeDdZMnhoYzNOT1lXMWxPaUpoWTNRdGMzVnRiV0Z5ZVY5ZlkyaGxkbkp2YmlJcktHUS9JaUJoWTNRdGMzVnRiV0Z5ZVY5ZlkyaGxkbkp2YmkwdGIzQmxi'
    || 'aUk2SWlJcExIZHBaSFJvT2lJeE5DSXNhR1ZwWjJoME9pSXhOQ0lzZG1sbGQwSnZlRG9pTUNBd0lERTJJREUySWl4bWFXeHNPaUp1YjI1bElpd2lZWEpwWVMx'
    || 'b2FXUmtaVzRpT2lKMGNuVmxJaXhqYUdsc1pISmxianB2TG1wemVDZ2ljR0YwYUNJc2UyUTZJazAwSURac05DQTBJRFF0TkNJc2MzUnliMnRsT2lKamRYSnla'
    || 'VzUwUTI5c2IzSWlMSE4wY205clpWZHBaSFJvT2lJeExqVWlMSE4wY205clpVeHBibVZqWVhBNkluSnZkVzVrSWl4emRISnZhMlZNYVc1bGFtOXBiam9pY205'
    || 'MWJtUWlmU2w5S1YxOUtTeGtQMjh1YW5ONGN5aHZMa1p5WVdkdFpXNTBMSHRqYUdsc1pISmxianBiWW13dWJXRndLRk05UG50amIyNXpkQ0IzUFdkYlUxMDdj'
    || 'bVYwZFhKdUlYZDhmQ0YzTG14bGJtZDBhRDl1ZFd4c09tOHVhbk40Y3loQmRDNUdjbUZuYldWdWRDeDdZMmhwYkdSeVpXNDZXMjh1YW5ONEtDSndJaXg3WTJ4'
    || 'aGMzTk9ZVzFsT2lKaFkzUmZYM1JwWlhJaUxHTm9hV3hrY21WdU9sTjlLU3h2TG1wemVDZ2ljQ0lzZTJOc1lYTnpUbUZ0WlRvaVlXTjBYMTkwYVdWeUxXUmxj'
    || 'Mk1pTEdOb2FXeGtjbVZ1T21GelcxTmRQejhpSW4wcExHOHVhbk40S0NKa2FYWWlMSHRqYkdGemMwNWhiV1U2SW1GamRGOWZaM0pwWkNJc1kyaHBiR1J5Wlc0'
    || 'NmR5NXRZWEFvWHowK2J5NXFjM2h6S0NKa2FYWWlMSHRqYkdGemMwNWhiV1U2SW1GamRGOWZZMkZ5WkNJc1kyaHBiR1J5Wlc0NlcyOHVhbk40S0NKa2FYWWlM'
    || 'SHRqYkdGemMwNWhiV1U2SW1GamRGOWZZMjlrWlNJc1kyaHBiR1J5Wlc0NlUzUnlhVzVuS0Y4dVEwOUVSU2w5S1N4dkxtcHplQ2dpWkdsMklpeDdZMnhoYzNO'
    || 'T1lXMWxPaUpoWTNSZlgyeGhZbVZzSWl4amFHbHNaSEpsYmpwVGRISnBibWNvWHk1TVFVSkZURDgvWHk1RFQwUkZLWDBwTEc4dWFuTjRLQ0prYVhZaUxIdGpi'
    || 'R0Z6YzA1aGJXVTZJbUZqZEY5ZlpXWm1aV04wSWl4amFHbHNaSEpsYmpwVGRISnBibWNvWHk1RlJrWkZRMVEvUHlMaWdKUWlLWDBwTEc4dWFuTjRjeWdpWkds'
    || 'MklpeDdZMnhoYzNOT1lXMWxPaUpoWTNSZlgyMWxkR0VpTEdOb2FXeGtjbVZ1T2x0dkxtcHplSE1vSW5Od1lXNGlMSHRqYUdsc1pISmxianBiSW40aUxFWmpL'
    || 'Rjh1UlZOVVgwTlNSVVJKVkZNcExDSWdZM0psWkdsMGN5SmRmU2tzYnk1cWMzaHpLQ0p6Y0dGdUlpeDdZMmhwYkdSeVpXNDZXMWtvWHk1VFZFRlVSVTFGVGxS'
    || 'VEtTd2lJSE4wYlhRaUxHVnBLRjh1VTFSQlZFVk5SVTVVVXlrOVBUMHhQeUlpT2lKeklsMTlLU3hmTGxWT1JFOWZVMVJCVkVWTlJVNVVVejl2TG1wemVDZ2lj'
    || 'M0JoYmlJc2UyTnNZWE56VG1GdFpUb2lZV04wWDE5MWJtUnZJaXhqYUdsc1pISmxiam9pZFc1a2J5QmhkbUZwYkdGaWJHVWlmU2s2Ynk1cWMzZ29Jbk53WVc0'
    || 'aUxIdGpiR0Z6YzA1aGJXVTZJbUZqZEY5ZmJtOTFibVJ2SWl4amFHbHNaSEpsYmpvaWJtOGdZWFYwYnkxMWJtUnZJbjBwWFgwcExHVnBLRjh1VkVsTlJWTmZV'
    || 'bFZPS1Q0d1AyOHVhbk40Y3lnaVpHbDJJaXg3WTJ4aGMzTk9ZVzFsT2lKaFkzUmZYM0oxYm5NaUxHTm9hV3hrY21WdU9sc2lVblZ1SUNJc1dTaGZMbFJKVFVW'
    || 'VFgxSlZUaWtzSW5naUxHVnBLRjh1VkVsTlJWTmZWVTVFVDA1RktUNHdQMkFzSUhWdVpHOXVaU0FrZTFrb1h5NVVTVTFGVTE5VlRrUlBUa1VwZlhoZ09pSWlY'
    || 'WDBwT201MWJHeGRmU3hUZEhKcGJtY29YeTVEVDBSRktTa3BmU2xkZlN4VEtYMHBMRzh1YW5ONEtDSndJaXg3WTJ4aGMzTk9ZVzFsT2lKaFkzUmZYMlp2YjNR'
    || 'aUxHTm9hV3hrY21WdU9pSlVhR1VnWTI5dWRISnZiSE1nWm05eUlIUm9aWE5sSUdGamRHbHZibk1nWVhKbElHSmxiRzkzSUhSb1pTQmtZWE5vWW05aGNtUWc0'
    || 'b0NVSUhOamNtOXNiQ0J3WVhOMElIUm9aU0JqYUdGeWRITWdkRzhnWm1sdVpDQjBhR1VnWW5WMGRHOXVjeUJoYm1RZ1kyOXVabWx5YldGMGFXOXVJSE4wWlhB'
    || 'dUluMHBYWDBwT201MWJHeGRmU2w5Wm5WdVkzUnBiMjRnZW1Nb2UzTmxkSFJwYm1jNmRYMHBlM0psZEhWeWJpQnZMbXB6ZUhNb0ltUnBkaUlzZTJOc1lYTnpU'
    || 'bUZ0WlRvaWJtOTBlV1YwSUhCaGJtVnNMVzV2ZEdKMWFXeDBJaXdpWkdGMFlTMXZibVZ6YUc5MElqb2ljR0Z1Wld3dGJtOTBZblZwYkhRaUxHTm9hV3hrY21W'
    || 'dU9sdHZMbXB6ZUNnaWMzUnliMjVuSWl4N1kyaHBiR1J5Wlc0NklrNXZJR0ZqZEdsdmJuTWdkMlZ5WlNCeVpXZHBjM1JsY21Wa0lHSjVJSFJvYVhNZ2NuVnVM'
    || 'aUo5S1N4dkxtcHplSE1vSW5BaUxIdGpiR0Z6YzA1aGJXVTZJbTV2ZEhsbGRGOWZkMmg1SWl4amFHbHNaSEpsYmpwYklsUm9hWE1nYzJOeWFYQjBJSGRoY3lC'
    || 'eWRXNGdkMmwwYUNBaUxHOHVhbk40Y3lnaVkyOWtaU0lzZTJOb2FXeGtjbVZ1T2x0MUxDSWdQU0JHUVV4VFJTSmRmU2tzSWl3Z2QyaHBZMmdnYVhNZ2RHaGxJ'
    || 'R1JsWm1GMWJIUTZJR2wwSUdsdWMzQmxZM1J6SUhSb1pTQmhZMk52ZFc1MElHRnVaQ0JpZFdsc1pITWdkbWxsZDNNc0lHRnVaQ0J5WldkcGMzUmxjbk1nYm05'
    || 'MGFHbHVaeUIwYUdGMElHTnZkV3hrSUdOb1lXNW5aU0JoYm5sMGFHbHVaeTRnVTJWMElDSXNieTVxYzNoektDSmpiMlJsSWl4N1kyaHBiR1J5Wlc0NlczVXNJ'
    || 'aUE5SUZSU1ZVVWlYWDBwTENJZ1lXNWtJSEoxYmlCcGRDQmhaMkZwYmlCMGJ5Qm1hV3hzSUhSb2FYTWdjR0ZuWlNCcGJpNGlYWDBwTEc4dWFuTjRLQ0p3SWl4'
    || 'N1kyeGhjM05PWVcxbE9pSnViM1I1WlhSZlgzZG9ZWFFpTEdOb2FXeGtjbVZ1T2lKUGJtTmxJR2wwSUdseklHWnBiR3hsWkNCcGJpd2daWFpsY25rZ1lXTjBh'
    || 'Vzl1SUdGd2NHVmhjbk1nYUdWeVpTQjFibVJsY2lCdmJtVWdiMllnZEdoeVpXVWdkR2xsY25NNkluMHBMRzh1YW5ONEtDSnZiQ0lzZTJOc1lYTnpUbUZ0WlRv'
    || 'aWJtOTBlV1YwWDE5MGFXVnljeUlzWTJocGJHUnlaVzQ2WW13dWJXRndLR1E5UG04dWFuTjRjeWdpYkdraUxIdGphR2xzWkhKbGJqcGJieTVxYzNnb0luTndZ'
    || 'VzRpTEh0amJHRnpjMDVoYldVNkltNXZkSGxsZEY5ZmRHbGxjaUlzWTJocGJHUnlaVzQ2WkgwcExHOHVhbk40S0NKemNHRnVJaXg3WTJ4aGMzTk9ZVzFsT2lK'
    || 'dWIzUjVaWFJmWDNScFpYSXRaR1Z6WXlJc1kyaHBiR1J5Wlc0NllYTmJaRjE5S1YxOUxHUXBLWDBwTEc4dWFuTjRLQ0p3SWl4N1kyeGhjM05PWVcxbE9pSnVi'
    || 'M1I1WlhSZlgyWnZiM1FpTEdOb2FXeGtjbVZ1T2lKRllXTm9JRzl1WlNCemRHRjBaWE1nYVhSeklHVnpkR2x0WVhSbFpDQmpjbVZrYVhSekxDQm9iM2NnYldG'
    || 'dWVTQnpkR0YwWlcxbGJuUnpJR2wwSUhKMWJuTXNJR0Z1WkNCM2FHVjBhR1Z5SUdsMElHTmhiaUJpWlNCMWJtUnZibVVnNG9DVUlHSmxabTl5WlNCaGJubGli'
    || 'MlI1SUhCeVpYTnpaWE1nWVc1NWRHaHBibWN1SW4wcFhYMHBmV1oxYm1OMGFXOXVJRlZqS0h0c2IyYzZkWDBwZTJOdmJuTjBXMlFzWVYwOVFYUXVkWE5sVTNS'
    || 'aGRHVW9JVEVwTEdjOWRTNXNaVzVuZEdnc2VEMTFMbVpwYkhSbGNpaFRQVDU3WTI5dWMzUWdkejFUZEhKcGJtY29VeTVUVkVGVVZWTS9QeUlpS1M1MGIxVndj'
    || 'R1Z5UTJGelpTZ3BPM0psZEhWeWJpQjNQVDA5SWtSUFRrVWlmSHgzUFQwOUlsVk9SRTlPUlNKOUtTNXNaVzVuZEdnc1F6MTFMbVpwYkhSbGNpaFRQVDVUZEhK'
    || 'cGJtY29VeTVUVkVGVVZWTS9QeUlpS1M1MGIxVndjR1Z5UTJGelpTZ3BQVDA5SWtaQlNVeEZSQ0lwTG14bGJtZDBhRHR5WlhSMWNtNGdieTVxYzNoektHOHVS'
    || 'bkpoWjIxbGJuUXNlMk5vYVd4a2NtVnVPbHR2TG1wemVITW9JbUoxZEhSdmJpSXNlM1I1Y0dVNkltSjFkSFJ2YmlJc1kyeGhjM05PWVcxbE9pSmhZM1F0YzNW'
    || 'dGJXRnllU0lzYjI1RGJHbGphem9vS1QwK1lTaFRQVDRoVXlrc0ltRnlhV0V0Wlhod1lXNWtaV1FpT21Rc1kyaHBiR1J5Wlc0NlcyOHVhbk40Y3lnaWMzQmhi'
    || 'aUlzZTJOc1lYTnpUbUZ0WlRvaVlXTjBMWE4xYlcxaGNubGZYMk52ZFc1MElpeGphR2xzWkhKbGJqcGJXU2huS1N3aUlITjBaWEFpTEdjOVBUMHhQeUlpT2lK'
    || 'eklsMTlLU3h2TG1wemVITW9Jbk53WVc0aUxIdGphR2xzWkhKbGJqcGJlQ3dpSUdOdmJYQnNaWFJsWkNJc1F6NHdQMkFzSUNSN1EzMGdabUZwYkdWa1lEb2lJ'
    || 'bDE5S1N4dkxtcHplQ2dpYzNabklpeDdZMnhoYzNOT1lXMWxPaUpoWTNRdGMzVnRiV0Z5ZVY5ZlkyaGxkbkp2YmlJcktHUS9JaUJoWTNRdGMzVnRiV0Z5ZVY5'
    || 'ZlkyaGxkbkp2YmkwdGIzQmxiaUk2SWlJcExIZHBaSFJvT2lJeE5DSXNhR1ZwWjJoME9pSXhOQ0lzZG1sbGQwSnZlRG9pTUNBd0lERTJJREUySWl4bWFXeHNP'
    || 'aUp1YjI1bElpd2lZWEpwWVMxb2FXUmtaVzRpT2lKMGNuVmxJaXhqYUdsc1pISmxianB2TG1wemVDZ2ljR0YwYUNJc2UyUTZJazAwSURac05DQTBJRFF0TkNJ'
    || 'c2MzUnliMnRsT2lKamRYSnlaVzUwUTI5c2IzSWlMSE4wY205clpWZHBaSFJvT2lJeExqVWlMSE4wY205clpVeHBibVZqWVhBNkluSnZkVzVrSWl4emRISnZh'
    || 'MlZNYVc1bGFtOXBiam9pY205MWJtUWlmU2w5S1YxOUtTeGtQMjh1YW5ONEtGTnVMSHR5YjNkek9uVXNZMjlzY3pwYmUydGxlVG9pUTA5RVJTSXNiR0ZpWld3'
    || 'NklrRmpkR2x2YmlKOUxIdHJaWGs2SWxOVVFWUlZVeUlzYkdGaVpXdzZJbE4wWVhSMWN5SXNjbVZ1WkdWeU9sTTlQbnRqYjI1emRDQjNQVk4wY21sdVp5aFRQ'
    || 'ejhpSWlrc1h6MTNQVDA5SWtSUFRrVWlmSHgzUFQwOUlsVk9SRTlPUlNJL0ltZHZiMlFpT25jOVBUMGlSa0ZKVEVWRUlqOGlZbUZrSWpvaWQyRnliaUk3Y21W'
    || 'MGRYSnVJRzh1YW5ONEtISnVMSHQwYjI1bE9sOHNZMmhwYkdSeVpXNDZkM3g4SXVLQWxDSjlLWDE5TEh0clpYazZJbE5VUVZSRlRVVk9WRk5mVWxWT0lpeHNZ'
    || 'V0psYkRvaVUzUnRkSE1pTEdGc2FXZHVPaUp5YVdkb2RDSjlMSHRyWlhrNklsTlVRVkpVUlVSZlFWUWlMR3hoWW1Wc09pSlRkR0Z5ZEdWa0lpeHlaVzVrWlhJ'
    || 'NlV6MCtVejlUZEhKcGJtY29VeWt1YzJ4cFkyVW9NQ3d4T1NrdWNtVndiR0ZqWlNnaVZDSXNJaUFpS1RvaTRvQ1VJbjBzZTJ0bGVUb2lSa2xPU1ZOSVJVUmZR'
    || 'VlFpTEd4aFltVnNPaUpHYVc1cGMyaGxaQ0lzY21WdVpHVnlPbE05UGxNL1UzUnlhVzVuS0ZNcExuTnNhV05sS0RBc01Ua3BMbkpsY0d4aFkyVW9JbFFpTENJ'
    || 'Z0lpazZJdUtBbENKOUxIdHJaWGs2SWtWU1VrOVNJaXhzWVdKbGJEb2lSWEp5YjNJaUxISmxibVJsY2pwVFBUNVRQMjh1YW5ONEtDSnpjR0Z1SWl4N2RHbDBi'
    || 'R1U2VTNSeWFXNW5LRk1wTEdOb2FXeGtjbVZ1T2xOMGNtbHVaeWhUS1M1emJHbGpaU2d3TERZd0tYMHBPaUxpZ0pRaWZWMTlLVHB1ZFd4c1hYMHBmV1oxYm1O'
    || 'MGFXOXVJRVpqS0hVcGUybG1LSFU5UFc1MWJHd3BjbVYwZFhKdUl1S0FsQ0k3ZEhKNWUzSmxkSFZ5YmlCT2RXMWlaWElvZFNrdWRHOUdhWGhsWkNnektTNXla'
    || 'WEJzWVdObEtDOHdLeVF2TENJaUtTNXlaWEJzWVdObEtDOWNMaVF2TENJaUtYeDhJakFpZldOaGRHTm9lM0psZEhWeWJpQlRkSEpwYm1jb2RTbDlmV1oxYm1O'
    || 'MGFXOXVJR1ZwS0hVcGUzSmxkSFZ5YmlCMGVYQmxiMllnZFQwOUltNTFiV0psY2lJL2RUcE9kVzFpWlhJb2RTbDhmREI5Wm5WdVkzUnBiMjRnVjJNb2UzQnZh'
    || 'VzUwY3pwMUxIZHBaSFJvT21ROU1qWXdMR2hsYVdkb2REcGhQVFEyZlNsN1kyOXVjM1FnWnoxMUxtMWhjQ2hPUFQ1T2RXMWlaWElvVGlsOGZEQXBPMmxtS0dj'
    || 'dWJHVnVaM1JvUERJcGNtVjBkWEp1SUc4dWFuTjRLQ0p3SWl4N1kyeGhjM05PWVcxbE9pSndZVzVsYkMxbGJYQjBlU0lzSW1SaGRHRXRiMjVsYzJodmRDSTZJ'
    || 'bkJoYm1Wc0xXVnRjSFI1SWl4amFHbHNaSEpsYmpvaVRtOTBJR1Z1YjNWbmFDQm9hWE4wYjNKNUlIUnZJR1J5WVhjZ1lTQjBjbVZ1WkM0aWZTazdZMjl1YzNR'
    || 'Z2VEMU5ZWFJvTG0xcGJpZ3VMaTVuS1N4VFBVMWhkR2d1YldGNEtDNHVMbWNwTFhoOGZERXNkejFPUFQ1T0x5aG5MbXhsYm1kMGFDMHhLU29vWkMwMEtTc3lM'
    || 'Rjg5VGowK1lTMDBMU2hPTFhncEwxTXFLR0V0TVRBcExFdzlaeTV0WVhBb0tFNHNUeWs5UG1Ba2UwOC9Ja3dpT2lKTkluMGtlM2NvVHlrdWRHOUdhWGhsWkNn'
    || 'eEtYMHNKSHRmS0U0cExuUnZSbWw0WldRb01TbDlZQ2t1YW05cGJpZ2lJQ0lwTzNKbGRIVnliaUJ2TG1wemVITW9Jbk4yWnlJc2UyTnNZWE56VG1GdFpUb2lj'
    || 'M0JoY21zaUxIZHBaSFJvT21Rc2FHVnBaMmgwT21Fc2RtbGxkMEp2ZURwZ01DQXdJQ1I3WkgwZ0pIdGhmV0FzSW1GeWFXRXRhR2xrWkdWdUlqb2lkSEoxWlNJ'
    || 'c1kyaHBiR1J5Wlc0NlcyOHVhbk40S0NKd1lYUm9JaXg3WTJ4aGMzTk9ZVzFsT2lKemNHRnlhMTlmWVhKbFlTSXNaRHBnSkh0TWZTQk1KSHQzS0djdWJHVnVa'
    || 'M1JvTFRFcExuUnZSbWw0WldRb01TbDlMQ1I3WVgwZ1RDUjdkeWd3S1M1MGIwWnBlR1ZrS0RFcGZTd2tlMkY5SUZwZ2ZTa3NieTVxYzNnb0luQmhkR2dpTEh0'
    || 'amJHRnpjMDVoYldVNkluTndZWEpyWDE5c2FXNWxJaXhrT2t4OUtTeHZMbXB6ZUNnaVkybHlZMnhsSWl4N1kyeGhjM05PWVcxbE9pSnpjR0Z5YTE5ZlpHOTBJ'
    || 'aXhqZURwM0tHY3ViR1Z1WjNSb0xURXBMR041T2w4b1oxdG5MbXhsYm1kMGFDMHhYU2tzY2pvaU1pNDJJbjBwWFgwcGZXTnZibk4wSUNSalBYdE5SVlE2SXVL'
    || 'Y2t5SXNUazlVWDAxRlZEb2k0cHlYSWl4UVJVNUVTVTVIT2lMaWdKUWlMQ0pPTDBFaU9pTGlsNHNpZlN4amN6MTdUVVZVT2lKTlJWUWlMRTVQVkY5TlJWUTZJ'
    || 'azVQVkNCTlJWUWlMRkJGVGtSSlRrYzZJbEJGVGtSSlRrY2lMQ0pPTDBFaU9pSk9MMEVpZlN4MGFUMTdUVVZVT2lKdFpYUWlMRTVQVkY5TlJWUTZJbTV2ZEcx'
    || 'bGRDSXNVRVZPUkVsT1J6b2ljR1Z1WkdsdVp5SXNJazR2UVNJNkltNWhJbjA3Wm5WdVkzUnBiMjRnVm1Nb2UzWTZkU3h2Yms5d1pXNDZaSDBwZTJOdmJuTjBJ'
    || 'R0U5ZFM1MlpYSmthV04wUFQwOUlrNVBWRjlOUlZRaVB5SmlZV1FpT25VdWRtVnlaR2xqZEQwOVBTSk5SVlFpUHlKbmIyOWtJanAxTG5abGNtUnBZM1E5UFQw'
    || 'aVRVVlVYMWRKVkVoZlVFVk9SRWxPUnlJL0luZGhjbTRpT2lKcFpHeGxJaXhuUFhVdWRXNWhkbUZwYkdGaWJHVS9JbEJQUXlCemRXTmpaWE56T2lCdWIzUWdZ'
    || 'blZwYkhRaU9uVXVkbVZ5WkdsamREMDlQU0pPVDFSZlVsVk9JajhpVUU5RElITjFZMk5sYzNNNklHNXZkQ0J6WTI5eVpXUWlPbUJRVDBNZ2MzVmpZMlZ6Y3pv'
    || 'Z0pIdDFMbTFsZEgwZ2IyWWdKSHQxTG5OamIzSmxaSDBnWTNKcGRHVnlhV0VnYldWMFlDc29kUzV3Wlc1a2FXNW5QMkFzSUNSN2RTNXdaVzVrYVc1bmZTQnda'
    || 'VzVrYVc1bllEb2lJaWtzZUQxdkxtcHplSE1vYnk1R2NtRm5iV1Z1ZEN4N1kyaHBiR1J5Wlc0NlcyOHVhbk40S0NKemNHRnVJaXg3WTJ4aGMzTk9ZVzFsT2lK'
    || 'd2IyTXRZMmhwY0Y5ZmJuVnRJaXhqYUdsc1pISmxianAxTG5WdVlYWmhhV3hoWW14bGZIeDFMblpsY21ScFkzUTlQVDBpVGs5VVgxSlZUaUkvSXVLQWxDSTZZ'
    || 'Q1I3ZFM1dFpYUjlMeVI3ZFM1elkyOXlaV1I5WUgwcExHOHVhbk40S0NKemNHRnVJaXg3WTJ4aGMzTk9ZVzFsT2lKd2IyTXRZMmhwY0Y5ZmQyOXlaQ0lzWTJo'
    || 'cGJHUnlaVzQ2ZFM1MWJtRjJZV2xzWVdKc1pUOGlibTkwSUdKMWFXeDBJanAxTG5abGNtUnBZM1E5UFQwaVRrOVVYMUpWVGlJL0ltNXZkQ0J6WTI5eVpXUWlP'
    || 'aUp0WlhRaWZTa3NkUzV1YjNSTlpYUS9ieTVxYzNoektDSnpjR0Z1SWl4N1kyeGhjM05PWVcxbE9pSndiMk10WTJocGNGOWZabXhoWnlJc1kyaHBiR1J5Wlc0'
    || 'NlczVXVibTkwVFdWMExDSWdabUZwYkdWa0lsMTlLVHB1ZFd4c0xIVXVjR1Z1WkdsdVp5WW1JWFV1Ym05MFRXVjBQMjh1YW5ONGN5Z2ljM0JoYmlJc2UyTnNZ'
    || 'WE56VG1GdFpUb2ljRzlqTFdOb2FYQmZYMlpzWVdjaUxHTm9hV3hrY21WdU9sdDFMbkJsYm1ScGJtY3NJaUJ3Wlc1a2FXNW5JbDE5S1RwdWRXeHNYWDBwTzNK'
    || 'bGRIVnliaUJrUDI4dWFuTjRLQ0ppZFhSMGIyNGlMSHQwZVhCbE9pSmlkWFIwYjI0aUxDSmtZWFJoTFhCdll5STZkUzUyWlhKa2FXTjBMR05zWVhOelRtRnRa'
    || 'VG9pY0c5akxXTm9hWEFnY0c5akxXTm9hWEF0TFNJcllTeHZia05zYVdOck9tUXNJbUZ5YVdFdGJHRmlaV3dpT21jc2RHbDBiR1U2Wnl4amFHbHNaSEpsYmpw'
    || 'NGZTazZieTVxYzNnb0luTndZVzRpTEhzaVpHRjBZUzF3YjJNaU9uVXVkbVZ5WkdsamRDeGpiR0Z6YzA1aGJXVTZJbkJ2WXkxamFHbHdJSEJ2WXkxamFHbHdM'
    || 'UzBpSzJFcklpQndiMk10WTJocGNDMHRjM1JoZEdsaklpd2lZWEpwWVMxc1lXSmxiQ0k2Wnl4MGFYUnNaVHBuTEdOb2FXeGtjbVZ1T25oOUtYMW1kVzVqZEds'
    || 'dmJpQmtjeWg3WTNKcGRHVnlhV0U2ZFN4Mk9tUXNjR0Z1Wld3NllTeDJaWEprYVdOMFVHRnVaV3c2WjMwcGUzWmhjaUJETzJOdmJuTjBJSGc5S0NoRFBYVXVa'
    || 'bWx1WkNoVFBUNVRMbU52YlhCaGNtRmlhV3hwZEhrcEtUMDliblZzYkQ5MmIybGtJREE2UXk1amIyMXdZWEpoWW1sc2FYUjVLVDgvSWlJN2NtVjBkWEp1SUc4'
    || 'dWFuTjRjeWh2TGtaeVlXZHRaVzUwTEh0amFHbHNaSEpsYmpwYmJ5NXFjM2dvUm1Vc2UzUnBkR3hsT2lKV1pYSmthV04wSWl4M2FXUmxPaUV3TEdocGJuUTZJ'
    || 'a052ZFc1MFpXUWdabkp2YlNCMGFHVWdZM0pwZEdWeWFXRWdZbVZzYjNjdUlFNHZRU0JqY21sMFpYSnBZU0JoY21VZ1pYaGpiSFZrWldRZ1puSnZiU0IwYUdV'
    || 'Z1pHVnViMjFwYm1GMGIzSXVJaXhqYUdsc1pISmxianB2TG1wemVDaE1aU3g3Y0dGdVpXdzZaejgvWVN4M2FHVnVUV2x6YzJsdVp6cHZMbXB6ZUNodkxrWnlZ'
    || 'V2R0Wlc1MExIdGphR2xzWkhKbGJqb2lWR2hsSUhCc1lXNGdjM1JsY0NCaWRXbHNaSE1nZEdobElITmpiM0psWTJGeVpDQjJhV1YzY3k0Z1JtbHNiQ0JwYmlC'
    || 'MGFHVWdjMlYwZEdsdVozTWdZWFFnZEdobElIUnZjQ0J2WmlCMGFHVWdjMk55YVhCMElHRnVaQ0J5ZFc0Z2FYUWdZV2RoYVc0Z2RHOGdhR0YyWlNCMGFHbHpJ'
    || 'RkJQUXlCelkyOXlaV1F1SW4wcExHTm9hV3hrY21WdU9tOHVhbk40Y3lnaVpHbDJJaXg3WTJ4aGMzTk9ZVzFsT2lKd2IyTmZYM1psY21ScFkzUWdjRzlqWDE5'
    || 'MlpYSmthV04wTFMwaUt5aGtMblpsY21ScFkzUTlQVDBpVGs5VVgwMUZWQ0kvSW1KaFpDSTZaQzUyWlhKa2FXTjBQVDA5SWsxRlZDSS9JbWR2YjJRaU9tUXVk'
    || 'bVZ5WkdsamREMDlQU0pOUlZSZlYwbFVTRjlRUlU1RVNVNUhJajhpZDJGeWJpSTZJbWxrYkdVaUtTeGphR2xzWkhKbGJqcGJieTVxYzNnb0ltUnBkaUlzZTJO'
    || 'c1lYTnpUbUZ0WlRvaWNHOWpYMTlvWldGa2JHbHVaU0lzWTJocGJHUnlaVzQ2WkM1b1pXRmtiR2x1WlgwcExHOHVhbk40S0NKd0lpeDdZMnhoYzNOT1lXMWxP'
    || 'aUp3YjJOZlgzSmxZV1FpTEdOb2FXeGtjbVZ1T21RdWNtVmhaRlJvYVhOOUtTeHZMbXB6ZUNnaVpHbDJJaXg3WTJ4aGMzTk9ZVzFsT2lKd2IyTmZYM1JoYkd4'
    || 'NUlpeGphR2xzWkhKbGJqcGJJazFGVkNJc0lrNVBWRjlOUlZRaUxDSlFSVTVFU1U1SElpd2lUaTlCSWwwdWJXRndLRk05UG50amIyNXpkQ0IzUFZNOVBUMGlU'
    || 'VVZVSWo5a0xtMWxkRHBUUFQwOUlrNVBWRjlOUlZRaVAyUXVibTkwVFdWME9sTTlQVDBpVUVWT1JFbE9SeUkvWkM1d1pXNWthVzVuT21RdWJtRTdjbVYwZFhK'
    || 'dUlHOHVhbk40Y3lnaWMzQmhiaUlzZTJOc1lYTnpUbUZ0WlRvaWNHOWpYMTkwYVdOcklIQnZZMTlmZEdsamF5MHRJaXQwYVZ0VFhTeGphR2xzWkhKbGJqcGJi'
    || 'eTVxYzNnb0ltSWlMSHRqYUdsc1pISmxianAzZlNrc0lpQWlMR056VzFOZFhYMHNVeWw5S1gwcFhYMHBmU2w5S1N4dkxtcHplQ2hHWlN4N2RHbDBiR1U2SWtO'
    || 'eWFYUmxjbWxoSWl4M2FXUmxPaUV3TEdocGJuUTZJa1ZoWTJnZ2RHRnlaMlYwSUdseklHUmxjbWwyWldRZ1puSnZiU0I1YjNWeUlHRmpZMjkxYm5Rc0lHRnVa'
    || 'Q0JsWVdOb0lISnZkeUJ6YUc5M2N5QjBhR1VnWVhKcGRHaHRaWFJwWXlCaVpXaHBibVFnYVhSeklITjBZWFJsTGlJc1kyaHBiR1J5Wlc0NmJ5NXFjM2dvVEdV'
    || 'c2UzQmhibVZzT21Fc2QyaGxiazFwYzNOcGJtYzZieTVxYzNnb2J5NUdjbUZuYldWdWRDeDdZMmhwYkdSeVpXNDZJazV2SUdOeWFYUmxjbWxoSUdoaGRtVWdZ'
    || 'bVZsYmlCelkyOXlaV1FnWW1WallYVnpaU0IwYUdVZ2RtbGxkM01nZEdobGVTQnlaV0ZrSUhkbGNtVWdibTkwSUdKMWFXeDBJR0o1SUhSb2FYTWdjblZ1TGlK'
    || 'OUtTeGphR2xzWkhKbGJqcHZMbXB6ZUhNb0ltUnBkaUlzZTJOc1lYTnpUbUZ0WlRvaWNHOWpJaXhqYUdsc1pISmxianBiZFM1dFlYQW9VejArYnk1cWMzaHpL'
    || 'Q0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbkJ2WXkxeWIzY2djRzlqTFhKdmR5MHRJaXQwYVZ0VExuTjBZWFJsWFN4amFHbHNaSEpsYmpwYmJ5NXFjM2dvSW1S'
    || 'cGRpSXNlMk5zWVhOelRtRnRaVG9pY0c5akxYSnZkMTlmYldGeWF5SXNJbUZ5YVdFdGFHbGtaR1Z1SWpvaWRISjFaU0lzWTJocGJHUnlaVzQ2SkdOYlV5NXpk'
    || 'R0YwWlYxOUtTeHZMbXB6ZUhNb0ltUnBkaUlzZTJOc1lYTnpUbUZ0WlRvaWNHOWpMWEp2ZDE5ZlltOWtlU0lzWTJocGJHUnlaVzQ2VzI4dWFuTjRjeWdpWkds'
    || 'MklpeDdZMnhoYzNOT1lXMWxPaUp3YjJNdGNtOTNYMTkwYjNBaUxHTm9hV3hrY21WdU9sdHZMbXB6ZUNnaWMzQmhiaUlzZTJOc1lYTnpUbUZ0WlRvaWNHOWpM'
    || 'WEp2ZDE5ZmJHRmlaV3dpTEdOb2FXeGtjbVZ1T2xNdWJHRmlaV3g4ZkZNdVkyOWtaWDBwTEc4dWFuTjRLQ0p6Y0dGdUlpeDdZMnhoYzNOT1lXMWxPaUp3YjJN'
    || 'dGNtOTNYMTl6ZEdGMFpTQndiMk10Y205M1gxOXpkR0YwWlMwdElpdDBhVnRUTG5OMFlYUmxYU3hqYUdsc1pISmxianBqYzF0VExuTjBZWFJsWFgwcFhYMHBM'
    || 'Rk11ZDJoNVAyOHVhbk40S0NKd0lpeDdZMnhoYzNOT1lXMWxPaUp3YjJNdGNtOTNYMTkzYUhraUxHTm9hV3hrY21WdU9sTXVkMmg1ZlNrNmJuVnNiQ3hUTG1G'
    || 'eWFYUm9iV1YwYVdNL2J5NXFjM2dvSW5BaUxIdGpiR0Z6YzA1aGJXVTZJbkJ2WXkxeWIzZGZYMjFoZEdnaUxHTm9hV3hrY21WdU9tOHVhbk40S0NKamIyUmxJ'
    || 'aXg3WTJocGJHUnlaVzQ2VXk1aGNtbDBhRzFsZEdsamZTbDlLVHB2TG1wemVDZ2ljQ0lzZTJOc1lYTnpUbUZ0WlRvaWNHOWpMWEp2ZDE5ZmJXRjBhQ0J3YjJN'
    || 'dGNtOTNYMTl0WVhSb0xTMXViMjVsSWl4amFHbHNaSEpsYmpwdkxtcHplSE1vSW5Od1lXNGlMSHRqYUdsc1pISmxianBiSW5SaGNtZGxkQ0FpTEZNdWRHRnla'
    || 'MlYwUFQwOWJuVnNiRDhpNG9DVUlqcFpLRk11ZEdGeVoyVjBLU3hUTG5WdWFYUnpQeUlnSWl0VExuVnVhWFJ6T2lJaUxDSWd3cmNnWVdOMGRXRnNJRzV2ZENC'
    || 'aGRtRnBiR0ZpYkdVaVhYMHBmU2tzVXk1M2FIbE9iM1EvYnk1cWMzZ29JbkFpTEh0amJHRnpjMDVoYldVNkluQnZZeTF5YjNkZlgzQmxibVFpTEdOb2FXeGtj'
    || 'bVZ1T2xNdWQyaDVUbTkwZlNrNmJuVnNiQ3hUTG5KbGMyOXNkbVZ6VjJobGJqOXZMbXB6ZUhNb0luQWlMSHRqYkdGemMwNWhiV1U2SW5Cdll5MXliM2RmWDNk'
    || 'b1pXNGlMR05vYVd4a2NtVnVPbHNpVW1WemIyeDJaWE1nZDJobGJqb2dJaXhUTG5KbGMyOXNkbVZ6VjJobGJsMTlLVHB1ZFd4c0xHOHVhbk40Y3lnaVpHd2lM'
    || 'SHRqYkdGemMwNWhiV1U2SW5Cdll5MXliM2RmWDIxbGRHRWlMR05vYVd4a2NtVnVPbHR2TG1wemVITW9JbVJwZGlJc2UyTm9hV3hrY21WdU9sdHZMbXB6ZUNn'
    || 'aVpIUWlMSHRqYUdsc1pISmxiam9pU0c5M0lIUm9aU0IwWVhKblpYUWdkMkZ6SUhObGRDSjlLU3h2TG1wemVDZ2laR1FpTEh0amFHbHNaSEpsYmpwVExtUmxj'
    || 'bWwyWVhScGIyNThmRzh1YW5ONEtDSmxiU0lzZTJOb2FXeGtjbVZ1T2lKT2IzUWdjM1JoZEdWa0lPS0FsQ0IwY21WaGRDQjBhR2x6SUhSaGNtZGxkQ0JoY3lC'
    || 'MWJtVjRjR3hoYVc1bFpDNGlmU2w5S1YxOUtTeFRMbUpoYzJselAyOHVhbk40Y3lnaVpHbDJJaXg3WTJocGJHUnlaVzQ2VzI4dWFuTjRLQ0prZENJc2UyTm9h'
    || 'V3hrY21WdU9pSkNZWE5wY3lCdlppQjBhR1VnWVdOMGRXRnNJbjBwTEc4dWFuTjRLQ0prWkNJc2UyTm9hV3hrY21WdU9tOHVhbk40S0NKamIyUmxJaXg3WTJo'
    || 'cGJHUnlaVzQ2VXk1aVlYTnBjMzBwZlNsZGZTazZiblZzYkYxOUtWMTlLVjE5TEZNdVkyOWtaU2twTEhnL2J5NXFjM2dvSW5BaUxIdGpiR0Z6YzA1aGJXVTZJ'
    || 'bkJ2WTE5ZmJtOTBaU0lzWTJocGJHUnlaVzQ2ZUgwcE9tNTFiR3hkZlNsOUtYMHBYWDBwZldaMWJtTjBhVzl1SUVoaktIVXNaQ2w3WTI5dWMzUWdZVDExTG1O'
    || 'MWMzUnZiV2w2WVhScGIyNC9QM3Q5TEdjOUtHRXVjR0Z1Wld4elB6OWJYU2t1YldGd0tFTTlQaWg3YVdRNlF5NXBaQ3hzWVdKbGJEcERMblJwZEd4bExHbGpi'
    || 'MjQ2SW5SaFlteGxJaXh3WVc1bGJITTZXME11YVdSZExISmxibVJsY2pvb0tUMCtieTVxYzNnb1puTXNlM0JoZVd4dllXUTZkU3h6Y0dWak9rTjlLWDBwS1N4'
    || 'NFBXRXVjMlZqZEdsdmJsOXZjbVJsY2o4L1cxMDdjbVYwZFhKdVd5NHVMbVFzTGk0dVoxMHViV0Z3S0VNOVBudDJZWElnVXp0eVpYUjFjbTU3TGk0dVF5eHNZ'
    || 'V0psYkRwRExtbGtQVDA5SW5CdlkxOXpkV05qWlhOeklqOURMbXhoWW1Wc09pZ29VejFoTG5ObFkzUnBiMjVmYkdGaVpXeHpLVDA5Ym5Wc2JEOTJiMmxrSURB'
    || 'NlUxdERMbWxrWFNrL1AwTXViR0ZpWld4OWZTa3VjMjl5ZENnb1F5eFRLVDArZTJOdmJuTjBJSGM5ZUM1cGJtUmxlRTltS0VNdWFXUXBMRjg5ZUM1cGJtUmxl'
    || 'RTltS0ZNdWFXUXBPM0psZEhWeWJpaDNQREEvZUM1c1pXNW5kR2c2ZHlrdEtGODhNRDk0TG14bGJtZDBhRHBmS1gwcGZXWjFibU4wYVc5dUlHWnpLSHR3WVhs'
    || 'c2IyRmtPblVzYzNCbFl6cGtmU2w3ZG1GeUlFdzdZMjl1YzNRZ1lUMTFMbkJoYm1Wc2MxdGtMbWxrWFN4blBXRW1KaUY1YmloaEtUOWhMbkp2ZDNNNlcxMHNl'
    || 'RDFuTG0xaGNDaE9QVDU2ZENoT0xsWkJURlZGS1Nrc1F6MTRMbVYyWlhKNUtFNDlQazRoUFQxdWRXeHNLU3hUUFUxaGRHZ3ViV2x1S0RBc0xpNHVlQzV0WVhB'
    || 'b1RqMCtUajgvTUNrcExGODlUV0YwYUM1dFlYZ29NQ3d1TGk1NExtMWhjQ2hPUFQ1T1B6OHdLU2t0VTN4OE1UdHlaWFIxY200Z2J5NXFjM2dvSW5ObFkzUnBi'
    || 'MjRpTEh0emRIbHNaVHA3WjNKcFpFTnZiSFZ0YmpvaU1TQXZJQzB4SWl4dGFXNVhhV1IwYURvd2ZTd2laR0YwWVMxdmJtVnphRzkwSWpvaVkzVnpkRzl0TFhC'
    || 'aGJtVnNJaXhqYUdsc1pISmxianB2TG1wemVDaE1aU3g3Y0dGdVpXdzZZU3hqYUdsc1pISmxianBrTG10cGJtUTlQVDBpZEdGaWJHVWlQMjh1YW5ONEtGTnVM'
    || 'SHR5YjNkek9tY3NiV0Y0T21RdWJHbHRhWFFzWTI5c2N6cFBZbXBsWTNRdWEyVjVjeWhuV3pCZFB6OTdmU2t1YldGd0tFNDlQaWg3YTJWNU9rNTlLU2w5S1Rw'
    || 'RFAyUXVhMmx1WkQwOVBTSnRaWFJ5YVdNaVAyY3ViR1Z1WjNSb0lUMDlNWHg4WVNZbUlYbHVLR0VwSmlaaExuUnlkVzVqWVhSbFpEOXZMbXB6ZUNnaWNDSXNl'
    || 'M0p2YkdVNkltRnNaWEowSWl4amFHbHNaSEpsYmpvaVFTQnRaWFJ5YVdNZ2RtbGxkeUJ0ZFhOMElISmxkSFZ5YmlCbGVHRmpkR3g1SUc5dVpTQnliM2N1SW4w'
    || 'cE9tOHVhbk40Y3lnaVpHd2lMSHRqYUdsc1pISmxianBiYnk1cWMzZ29JbVIwSWl4N1kyaHBiR1J5Wlc0NlUzUnlhVzVuS0Nnb1REMW5XekJkS1QwOWJuVnNi'
    || 'RDkyYjJsa0lEQTZUQzVNUVVKRlRDay9QeUlpS1gwcExHOHVhbk40S0NKa1pDSXNlM04wZVd4bE9udG1iMjUwVTJsNlpUb3pOaXh0WVhKbmFXNDZJamh3ZUNB'
    || 'd0lpeG1iMjUwVm1GeWFXRnVkRTUxYldWeWFXTTZJblJoWW5Wc1lYSXRiblZ0Y3lKOUxHTm9hV3hrY21WdU9sa29lRnN3WFNsOUtWMTlLVHB2TG1wemVDZ2la'
    || 'R2wySWl4N2MzUjViR1U2ZTJScGMzQnNZWGs2SW1keWFXUWlMR2RoY0RveE1uMHNZMmhwYkdSeVpXNDZaeTV0WVhBb0tFNHNUeWs5UG50amIyNXpkQ0JHUFho'
    || 'YlQxMC9QekFzU3owdFV5OWZLakV3TUN4SFBTaEdMVk1wTDE4cU1UQXdPM0psZEhWeWJpQnZMbXB6ZUhNb0ltUnBkaUlzZTNOMGVXeGxPbnRrYVhOd2JHRjVP'
    || 'aUpuY21sa0lpeG5jbWxrVkdWdGNHeGhkR1ZEYjJ4MWJXNXpPaUp0YVc1dFlYZ29NVEF3Y0hnc0lERm1jaWtnYldsdWJXRjRLRGd3Y0hnc0lETm1jaWtnYlds'
    || 'dWJXRjRLRFl3Y0hnc0lERm1jaWtpTEdkaGNEb3hNaXhoYkdsbmJrbDBaVzF6T2lKalpXNTBaWElpZlN4amFHbHNaSEpsYmpwYmJ5NXFjM2dvSW5Od1lXNGlM'
    || 'SHR6ZEhsc1pUcDdiM1psY21ac2IzZFhjbUZ3T2lKaGJubDNhR1Z5WlNKOUxHTm9hV3hrY21WdU9sTjBjbWx1WnloT0xreEJRa1ZNUHo4aUlpbDlLU3h2TG1w'
    || 'emVITW9JbVJwZGlJc2UzSnZiR1U2SW1sdFp5SXNJbUZ5YVdFdGJHRmlaV3dpT21Ba2UxTjBjbWx1WnloT0xreEJRa1ZNS1gwNklDUjdXU2hHS1gxZ0xITjBl'
    || 'V3hsT250b1pXbG5hSFE2TWpJc2NHOXphWFJwYjI0NkluSmxiR0YwYVhabElpeGlZV05yWjNKdmRXNWtPaUoyWVhJb0xTMXNhVzVsTENBalpUUmxOMlZqS1NK'
    || 'OUxHTm9hV3hrY21WdU9sdHZMbXB6ZUNnaVpHbDJJaXg3YzNSNWJHVTZlM0J2YzJsMGFXOXVPaUpoWW5OdmJIVjBaU0lzYkdWbWREcGdKSHROWVhSb0xtMXBi'
    || 'aWhMTEVjcGZTVmdMSGRwWkhSb09tQWtlMDFoZEdndVlXSnpLRWN0U3lsOUpXQXNhR1ZwWjJoME9pSXhNREFsSWl4aVlXTnJaM0p2ZFc1a09pSjJZWElvTFMx'
    || 'aFkyTmxiblFzSUNNeE5qYzVZVFVwSW4xOUtTeHZMbXB6ZUNnaVpHbDJJaXg3YzNSNWJHVTZlM0J2YzJsMGFXOXVPaUpoWW5OdmJIVjBaU0lzYkdWbWREcGdK'
    || 'SHRMZlNWZ0xIZHBaSFJvT2pFc2FHVnBaMmgwT2lJeE1EQWxJaXhpWVdOclozSnZkVzVrT2lKMllYSW9MUzFwYm1zc0lDTXhOekl4TW1JcEluMTlLVjE5S1N4'
    || 'dkxtcHplQ2dpYzNCaGJpSXNlM04wZVd4bE9udDBaWGgwUVd4cFoyNDZJbkpwWjJoMElpeG1iMjUwVm1GeWFXRnVkRTUxYldWeWFXTTZJblJoWW5Wc1lYSXRi'
    || 'blZ0Y3lKOUxHTm9hV3hrY21WdU9sa29SaWw5S1YxOUxFOHBmU2w5S1RwdkxtcHplQ2dpY0NJc2UzSnZiR1U2SW1Gc1pYSjBJaXhqYUdsc1pISmxiam9pVmtG'
    || 'TVZVVWdiWFZ6ZENCaVpTQnVkVzFsY21sakxpQk9ieUJqYUdGeWRDQjNZWE1nWkhKaGQyNHVJbjBwZlNsOUtYMW1kVzVqZEdsdmJpQkNZeWgxS1h0MllYSWda'
    || 'eXg0TzJOdmJuTjBJR1E5S0djOWRUMDliblZzYkQ5MmIybGtJREE2ZFM1aWRXbHNaR1Z5WDNWeWJDazlQVzUxYkd3L2RtOXBaQ0F3T21jdWJXRjBZMmdvTDE1'
    || 'b2RIUndjenBjTDF3dllYQndYQzV6Ym05M1pteGhhMlZjTG1OdmJWd3ZLRnRoTFhwQkxWb3dMVGxmTFYwcktWd3ZLRnRoTFhwQkxWb3dMVGxmTFYwcktWd3ZJ'
    || 'MXd2YzNSeVpXRnRiR2wwTFdGd2NITmNMMXRCTFZvd0xUbGZYU3RjTGx0QkxWb3dMVGxmWFN0Y0xsdEJMVm93TFRsZlhTc2tMeWtzWVQwb2VEMTFQVDF1ZFd4'
    || 'c1AzWnZhV1FnTURwMUxuWnBaWGRsY2w5MWNtd3BQVDF1ZFd4c1AzWnZhV1FnTURwNExtMWhkR05vS0M5ZWFIUjBjSE02WEM5Y0wyRndjRnd1YzI1dmQyWnNZ'
    || 'V3RsWEM1amIyMWNMM04wY21WaGJXeHBkRnd2S0Z0aExYcEJMVm93TFRsZkxWMHJLVnd2S0Z0aExYcEJMVm93TFRsZkxWMHJLVnd2STF3dllYQndjMXd2VzJF'
    || 'dGVrRXRXakF0T1Y4dFhTc2tMeWs3Y21WMGRYSnVJV1I4ZkNGaGZIeGtXekZkSVQwOVlWc3hYWHg4WkZzeVhTRTlQV0ZiTWwwL2JuVnNiRHBiZTJ4aFltVnNP'
    || 'aUpCY0hBZ2IyNXNlU0lzYUhKbFpqcDFMblpwWlhkbGNsOTFjbXg5TEh0c1lXSmxiRG9pVTJodmR5QlRibTkzYzJsbmFIUWlMR2h5WldZNmRTNWlkV2xzWkdW'
    || 'eVgzVnliSDFkZldaMWJtTjBhVzl1SUZGaktIdHVZWFpwWjJGMGFXOXVPblY5S1h0amIyNXpkQ0JrUFV0c0xuVnpaVkpsWmlodWRXeHNLU3hoUFVKaktIVXBP'
    || 'M0psZEhWeWJpQkxiQzUxYzJWRlptWmxZM1FvS0NrOVBudGpiMjV6ZENCblBYZzlQbnRrTG1OMWNuSmxiblFtSmlGa0xtTjFjbkpsYm5RdVkyOXVkR0ZwYm5N'
    || 'b2VDNTBZWEpuWlhRcEppWW9aQzVqZFhKeVpXNTBMbTl3Wlc0OUlURXBmVHR5WlhSMWNtNGdaRzlqZFcxbGJuUXVZV1JrUlhabGJuUk1hWE4wWlc1bGNpZ2lj'
    || 'RzlwYm5SbGNtUnZkMjRpTEdjcExDZ3BQVDVrYjJOMWJXVnVkQzV5WlcxdmRtVkZkbVZ1ZEV4cGMzUmxibVZ5S0NKd2IybHVkR1Z5Wkc5M2JpSXNaeWw5TEZ0'
    || 'ZEtTeGhQMjh1YW5ONGN5Z2laR1YwWVdsc2N5SXNlMk5zWVhOelRtRnRaVG9pWVhCd0xYWnBaWGN0YldWdWRTSXNjbVZtT21Rc0ltUmhkR0V0YjI1bGMyaHZk'
    || 'Q0k2SW5acFpYY3RiV1Z1ZFNJc2IyNUxaWGxFYjNkdU9tYzlQbnQyWVhJZ2VDeERPMmN1YTJWNVBUMDlJa1Z6WTJGd1pTSW1KaWdvZUQxa0xtTjFjbkpsYm5R'
    || 'cElUMXVkV3hzSmlaNExtOXdaVzRwSmlZb1p5NXdjbVYyWlc1MFJHVm1ZWFZzZENncExHUXVZM1Z5Y21WdWRDNXZjR1Z1UFNFeExDaERQV1F1WTNWeWNtVnVk'
    || 'QzV4ZFdWeWVWTmxiR1ZqZEc5eUtDSnpkVzF0WVhKNUlpa3BQVDF1ZFd4c2ZIeERMbVp2WTNWektDa3BmU3hqYUdsc1pISmxianBiYnk1cWMzZ29Jbk4xYlcx'
    || 'aGNua2lMSHNpWVhKcFlTMXNZV0psYkNJNklrRndjQ0IyYVdWM0lHOXdkR2x2Ym5NaUxIUnBkR3hsT2lKQmNIQWdkbWxsZHlCdmNIUnBiMjV6SWl4amFHbHNa'
    || 'SEpsYmpwdkxtcHplQ2dpYzNabklpeDdkbWxsZDBKdmVEb2lNQ0F3SURJMElESTBJaXgzYVdSMGFEb2lNakFpTEdobGFXZG9kRG9pTWpBaUxHWnBiR3c2SW01'
    || 'dmJtVWlMSE4wY205clpUb2lZM1Z5Y21WdWRFTnZiRzl5SWl4emRISnZhMlZYYVdSMGFEb2lNUzQySWl4emRISnZhMlZNYVc1bFkyRndPaUp5YjNWdVpDSXNj'
    || 'M1J5YjJ0bFRHbHVaV3B2YVc0NkluSnZkVzVrSWl3aVlYSnBZUzFvYVdSa1pXNGlPaUowY25WbElpeGphR2xzWkhKbGJqcHZMbXB6ZUNnaWNHRjBhQ0lzZTJR'
    || 'NklrMDRJRE5JTTNZMWJURXpMVFZvTlhZMVRUTWdNVFoyTldnMWJURXpMVFYyTldndE5TSjlLWDBwZlNrc2J5NXFjM2dvSW1ScGRpSXNlMk5zWVhOelRtRnRa'
    || 'VG9pWVhCd0xYWnBaWGN0YjNCMGFXOXVjeUlzWTJocGJHUnlaVzQ2WVM1dFlYQW9aejArYnk1cWMzZ29JbUVpTEh0b2NtVm1PbWN1YUhKbFppeDBZWEpuWlhR'
    || 'NklsOWliR0Z1YXlJc2NtVnNPaUp1YjI5d1pXNWxjaUJ1YjNKbFptVnljbVZ5SWl3aVlYSnBZUzFzWVdKbGJDSTZZQ1I3Wnk1c1lXSmxiSDBnS0c5d1pXNXpJ'
    || 'R2x1SUdFZ2JtVjNJSFJoWWlsZ0xHOXVRMnhwWTJzNktDazlQbnRrTG1OMWNuSmxiblFtSmloa0xtTjFjbkpsYm5RdWIzQmxiajBoTVNsOUxHTm9hV3hrY21W'
    || 'dU9tY3ViR0ZpWld4OUxHY3ViR0ZpWld3cEtYMHBYWDBwT201MWJHeDlZMjl1YzNRZ2JtazlJbkJ2WTE5emRXTmpaWE56SWp0bWRXNWpkR2x2YmlCSFl5aDdj'
    || 'R0Y1Ykc5aFpEcDFMSE5sWTNScGIyNXpPbVFzYzNWaWRHbDBiR1U2WVN4amFHbHNaSEpsYmpwbmZTbDdkbUZ5SUhabExFMWxMSGhsTEdObExHUmxPMk52Ym5O'
    || 'MElIZzlkUzVqYjI1MFpYaDBQejk3ZlN4VFBWTjBjbWx1WnloNExrMVBSRVUvUHlJaUtTNTBiMVZ3Y0dWeVEyRnpaU2dwUFQwOUlsTkJUVkJNUlNJc2R6MG9L'
    || 'SFpsUFhVdVkzVnpkRzl0YVhwaGRHbHZiaWs5UFc1MWJHdy9kbTlwWkNBd09uWmxMblJwZEd4bEtUOC9VM1J5YVc1bktIZ3VVMDlNVlZSSlQwNC9QeUpUYm05'
    || 'M1pteGhhMlVnYzI5c2RYUnBiMjRpS1N4ZlBWOWpLSFVwTEV3OWIzTW9kU2tzVGoxN2FXUTZibWtzYkdGaVpXdzZJbEJQUXlCemRXTmpaWE56SWl4a1pYTmpP'
    || 'aUpVWVhKblpYUnpMQ0JoYm1RZ2QyaGxkR2hsY2lCMGFHVjVJR0Z5WlNCdFpYUWlMR2xqYjI0Nlh5NTJaWEprYVdOMFBUMDlJazVQVkY5TlJWUWlQeUozWVhK'
    || 'dUlqb2lZMmhsWTJzaUxHSmhaR2RsT2w4dWRXNWhkbUZwYkdGaWJHVjhmRjh1ZG1WeVpHbGpkRDA5UFNKT1QxUmZVbFZPSWo5MmIybGtJREE2WUNSN1h5NXRa'
    || 'WFI5THlSN1h5NXpZMjl5WldSOVlDeGlZV1JuWlZSdmJtVTZYeTUyWlhKa2FXTjBQVDA5SWs1UFZGOU5SVlFpUHlKaVlXUWlPbDh1ZG1WeVpHbGpkRDA5UFNK'
    || 'TlJWUWlQeUpuYjI5a0lqcGZMblpsY21ScFkzUTlQVDBpVFVWVVgxZEpWRWhmVUVWT1JFbE9SeUkvSW5kaGNtNGlPaUpwWkd4bElpeHdZVzVsYkhNNld5Sndi'
    || 'Mk5mYzJOdmNtVmpZWEprSWl3aWNHOWpYM1psY21ScFkzUWlYU3h5Wlc1a1pYSTZLQ2s5UG04dWFuTjRLR1J6TEh0amNtbDBaWEpwWVRwTUxIWTZYeXh3WVc1'
    || 'bGJEcDFMbkJoYm1Wc2N5NXdiMk5mYzJOdmNtVmpZWEprTEhabGNtUnBZM1JRWVc1bGJEcDFMbkJoYm1Wc2N5NXdiMk5mZG1WeVpHbGpkSDBwZlN4UFBXUW1K'
    || 'bVF1YkdWdVozUm9QMGhqS0hVc1pDNXpiMjFsS0hKbFBUNXlaUzVwWkQwOVBXNXBLVDlrT2xzdUxpNWtMRTVkS1RwMmIybGtJREFzUmowb1RXVTlkUzVqZFhO'
    || 'MGIyMXBlbUYwYVc5dUtUMDliblZzYkQ5MmIybGtJREE2VFdVdVpHVm1ZWFZzZEY5elpXTjBhVzl1TEVzOUtDaDRaVDFQUFQxdWRXeHNQM1p2YVdRZ01EcFBM'
    || 'bVpwYm1Rb2NtVTlQbkpsTG1sa1BUMDlSaWtwUFQxdWRXeHNQM1p2YVdRZ01EcDRaUzVwWkNrL1B5Z29ZMlU5VHowOWJuVnNiRDkyYjJsa0lEQTZUMXN3WFNr'
    || 'OVBXNTFiR3cvZG05cFpDQXdPbU5sTG1sa0tUOC9JaUlzVzBjc1ZsMDlRWFF1ZFhObFUzUmhkR1VvU3lrc1VUMG9UejA5Ym5Wc2JEOTJiMmxrSURBNlR5NW1h'
    || 'VzVrS0hKbFBUNXlaUzVwWkQwOVBVY3BLVDgvS0U4OVBXNTFiR3cvZG05cFpDQXdPazliTUYwcE8ybG1LSFV1Wm1GMFlXd3BjbVYwZFhKdUlHOHVhbk40S0NK'
    || 'a2FYWWlMSHRqYkdGemMwNWhiV1U2SW1Gd2NDQmhjSEF0TFc1dmJtRjJJaXhqYUdsc1pISmxianB2TG1wemVITW9JbVJwZGlJc2UyTnNZWE56VG1GdFpUb2la'
    || 'bUYwWVd3aUxDSmtZWFJoTFc5dVpYTm9iM1FpT2lKbVlYUmhiQ0lzWTJocGJHUnlaVzQ2VzI4dWFuTjRLQ0pvTVNJc2UyTm9hV3hrY21WdU9pSlVhR2x6SUdG'
    || 'd2NDQmpZVzV1YjNRZ2MyaHZkeUJoYm5sMGFHbHVaeUo5S1N4dkxtcHplQ2dpWTI5a1pTSXNlMk5vYVd4a2NtVnVPblV1Wm1GMFlXeDlLVjE5S1gwcE8yTnZi'
    || 'bk4wSUZGbFBTRWhUeVltVHk1c1pXNW5kR2crTUN4clpUMXZMbXB6ZUhNb2J5NUdjbUZuYldWdWRDeDdZMmhwYkdSeVpXNDZXMU0vYnk1cWMzZ29JbVJwZGlJ'
    || 'c2UyTnNZWE56VG1GdFpUb2lZbUZ1Ym1WeUlHSmhibTVsY2kwdGMyRnRjR3hsSWl3aVpHRjBZUzF2Ym1WemFHOTBJam9pYzJGdGNHeGxMV0poYm01bGNpSXNZ'
    || 'MmhwYkdSeVpXNDZJbE5CVFZCTVJTQkVRVlJCSU9LQWxDQjBhR1Z6WlNCdWRXMWlaWEp6SUdOdmJXVWdabkp2YlNCelpXVmtaV1FnWm1sNGRIVnlaWE1zSUc1'
    || 'dmRDQm1jbTl0SUhsdmRYSWdZV05qYjNWdWRDSjlLVHB1ZFd4c0xHOHVhbk40Y3lnaWFHVmhaR1Z5SWl4N1kyeGhjM05PWVcxbE9pSmhjSEJmWDJobFlXUWlM'
    || 'R05vYVd4a2NtVnVPbHR2TG1wemVITW9JbVJwZGlJc2UyTm9hV3hrY21WdU9sdHZMbXB6ZUNnaWFERWlMSHRqYUdsc1pISmxianBSUDFFdWJHRmlaV3c2ZDMw'
    || 'cExHOHVhbk40Y3lnaWNDSXNlMk5zWVhOelRtRnRaVG9pWVhCd1gxOXpkV0lpTEdOb2FXeGtjbVZ1T2xzaVluVnBiSFFnYVc0Z0lpeHZMbXB6ZUNnaVkyOWta'
    || 'U0lzZTJOb2FXeGtjbVZ1T2xOMGNtbHVaeWg0TGtKVlNVeFVYMGxPUHo4aTRvQ1VJaWw5S1N4NExsZEpUa1JQVjE5RVFWbFRQMjh1YW5ONGN5aHZMa1p5WVdk'
    || 'dFpXNTBMSHRqYUdsc1pISmxianBiSWlEQ3R5QWlMRk4wY21sdVp5aDRMbGRKVGtSUFYxOUVRVmxUS1N3aUxXUmhlU0IzYVc1a2IzY2lYWDBwT201MWJHd3Nl'
    || 'QzVDVlVsTVZGOUJWRDl2TG1wemVITW9ieTVHY21GbmJXVnVkQ3g3WTJocGJHUnlaVzQ2V3lJZ3dyY2dJaXhUZEhKcGJtY29lQzVDVlVsTVZGOUJWQ2t1YzJ4'
    || 'cFkyVW9NQ3d4T1NrdWNtVndiR0ZqWlNnaVZDSXNJaUFpS1YxOUtUcHVkV3hzWFgwcFhYMHBMRzh1YW5ONGN5Z2laR2wySWl4N1kyeGhjM05PWVcxbE9pSmhj'
    || 'SEJmWDJobFlXUnlhV2RvZENJc1kyaHBiR1J5Wlc0NlcyOHVhbk40S0ZaakxIdDJPbDhzYjI1UGNHVnVPbEZsUHlncFBUNVdLRzVwS1RwMmIybGtJREI5S1N4'
    || 'dkxtcHplQ2hZWXl4N2NHRjViRzloWkRwMWZTa3NieTVxYzNnb1VXTXNlMjVoZG1sbllYUnBiMjQ2ZFM1dVlYWnBaMkYwYVc5dWZTbGRmU2xkZlNrc2J5NXFj'
    || 'M2dvV21Nc2UzQmhlV3h2WVdRNmRYMHBMSFV1WTNWemRHOXRhWHBoZEdsdmJsOWxjbkp2Y2o5dkxtcHplQ2dpY0NJc2UzSnZiR1U2SW1Gc1pYSjBJaXhqYkdG'
    || 'emMwNWhiV1U2SW5CaGJtVnNMV1Z5Y205eUlpeGphR2xzWkhKbGJqcDFMbU4xYzNSdmJXbDZZWFJwYjI1ZlpYSnliM0o5S1RwdWRXeHNYWDBwTzJsbUtDRlJa'
    || 'U2x5WlhSMWNtNGdieTVxYzNnb0ltUnBkaUlzZTJOc1lYTnpUbUZ0WlRvaVlYQndJR0Z3Y0MwdGJtOXVZWFlpTEdOb2FXeGtjbVZ1T204dWFuTjRjeWdpWkds'
    || 'MklpeDdZMnhoYzNOT1lXMWxPaUp0WVdsdUlpeGphR2xzWkhKbGJqcGJhMlVzYnk1cWMzaHpLQ0p0WVdsdUlpeDdZMnhoYzNOT1lXMWxPaUpuY21sa0lpd2la'
    || 'R0YwWVMxdmJtVnphRzkwSWpvaWMyVmpkR2x2YmlJc0ltUmhkR0V0YzJWamRHbHZiaUk2SW5OcGJtZHNaU0lzWTJocGJHUnlaVzQ2VzJjc0tDZ29aR1U5ZFM1'
    || 'amRYTjBiMjFwZW1GMGFXOXVLVDA5Ym5Wc2JEOTJiMmxrSURBNlpHVXVjR0Z1Wld4ektUOC9XMTBwTG0xaGNDaHlaVDArYnk1cWMzaHpLRUYwTGtaeVlXZHRa'
    || 'VzUwTEh0amFHbHNaSEpsYmpwYmJ5NXFjM2dvSW1neUlpeDdjM1I1YkdVNmUyZHlhV1JEYjJ4MWJXNDZJakVnTHlBdE1TSjlMR05vYVd4a2NtVnVPbkpsTG5S'
    || 'cGRHeGxmU2tzYnk1cWMzZ29abk1zZTNCaGVXeHZZV1E2ZFN4emNHVmpPbkpsZlNsZGZTeHlaUzVwWkNrcExHOHVhbk40S0dSekxIdGpjbWwwWlhKcFlUcE1M'
    || 'SFk2WHl4d1lXNWxiRHAxTG5CaGJtVnNjeTV3YjJOZmMyTnZjbVZqWVhKa0xIWmxjbVJwWTNSUVlXNWxiRHAxTG5CaGJtVnNjeTV3YjJOZmRtVnlaR2xqZEgw'
    || 'cFhYMHBMRzh1YW5ONEtFdGpMSHQ5S1YxOUtYMHBPMk52Ym5OMElHcGxQVTh1YldGd0tISmxQVDRvZXk0dUxuSmxMSE4wWVhSMWN6cHlaUzV6ZEdGMGRYTS9Q'
    || 'MWxqS0hVc2NtVXBmU2twTzNKbGRIVnliaUJ2TG1wemVITW9JbVJwZGlJc2UyTnNZWE56VG1GdFpUb2lZWEJ3SWl4amFHbHNaSEpsYmpwYmJ5NXFjM2dvVW1N'
    || 'c2UzTnZiSFYwYVc5dU9uY3NjM1ZpZEdsMGJHVTZZU3h6WldOMGFXOXVjenBxWlN4aFkzUnBkbVU2Unl4dmJsQnBZMnM2Vml4bWIyOTBPbTh1YW5ONEtHOHVS'
    || 'bkpoWjIxbGJuUXNlMk5vYVd4a2NtVnVPaUpFWVhSaElHTnZiV1Z6SUdaeWIyMGdkbWxsZDNNZ2FXNGdkR2hwY3lCelkyaGxiV0V1SUZKbFlXUnpJRzFoZVNC'
    || 'aVpTQnlaWFZ6WldRZ1ptOXlJRE13SUhObFkyOXVaSE1nZDJsMGFHbHVJSGx2ZFhJZ2MyVnpjMmx2YmpzZ1VtVm1jbVZ6YUNCa1lYUmhJR1psZEdOb1pYTWdZ'
    || 'V2RoYVc0dUluMHBmU2tzYnk1cWMzaHpLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbTFoYVc0aUxHTm9hV3hrY21WdU9sdHJaU3h2TG1wemVDZ2liV0ZwYmlJ'
    || 'c2UyTnNZWE56VG1GdFpUb2laM0pwWkNCeWRpSXNJbVJoZEdFdGIyNWxjMmh2ZENJNkluTmxZM1JwYjI0aUxDSmtZWFJoTFhObFkzUnBiMjRpT2tjc1kyaHBi'
    || 'R1J5Wlc0NlVUOVJMbkpsYm1SbGNpZ3BPbTUxYkd4OUxFY3BYWDBwWFgwcGZXWjFibU4wYVc5dUlGbGpLSFVzWkNsN1kyOXVjM1FnWVQxa0xuQmhibVZzY3o4'
    || 'L1cxMDdhV1lvWVM1emIyMWxLR2M5UG5sdUtIVXVjR0Z1Wld4elcyZGRLU1ltSVhodUtIVXVjR0Z1Wld4elcyZGRLU2twY21WMGRYSnVJbUpoWkNJN2FXWW9Z'
    || 'UzV6YjIxbEtHYzlQbmh1S0hVdWNHRnVaV3h6VzJkZEtTa3BjbVYwZFhKdUltbHVabThpZldaMWJtTjBhVzl1SUV0aktDbDdjbVYwZFhKdUlHOHVhbk40S0NK'
    || 'bWIyOTBaWElpTEh0amJHRnpjMDVoYldVNkltRndjRjlmWm05dmRDSXNjM1I1YkdVNmUyMWhjbWRwYmxSdmNEb3lNQ3htYjI1MFUybDZaVG94TVM0MUxHTnZi'
    || 'Rzl5T2lKMllYSW9MUzFrYVcwcEluMHNZMmhwYkdSeVpXNDZJa1JoZEdFZ1kyOXRaWE1nWm5KdmJTQjJhV1YzY3lCcGJpQjBhR2x6SUhOamFHVnRZUzRnVW1W'
    || 'aFpITWdiV0Y1SUdKbElISmxkWE5sWkNCbWIzSWdNekFnYzJWamIyNWtjeUIzYVhSb2FXNGdlVzkxY2lCelpYTnphVzl1T3lCU1pXWnlaWE5vSUdSaGRHRWda'
    || 'bVYwWTJobGN5QmhaMkZwYmk0aWZTbDlablZ1WTNScGIyNGdXR01vZTNCaGVXeHZZV1E2ZFgwcGUzWmhjaUJUTzJOdmJuTjBJR1E5YTJNb2RTNWpiMjUwWlho'
    || 'MEtTeGJZU3huWFQxQmRDNTFjMlZUZEdGMFpTaHVkV3hzS1N4NFBTZ29VejFrTG1acGJtUW9kejArZHk1emRHRjBaVDA5UFNKamRYSnlaVzUwSWlrcFBUMXVk'
    || 'V3hzUDNadmFXUWdNRHBUTG1sa0tUOC9iblZzYkN4RFBXRS9aQzVtYVc1a0tIYzlQbmN1YVdROVBUMWhLVHB1ZFd4c08zSmxkSFZ5YmlCdkxtcHplSE1vSW1S'
    || 'cGRpSXNlMk5zWVhOelRtRnRaVG9pY0doaGMyVWlMR05vYVd4a2NtVnVPbHR2TG1wemVDZ2laR2wySWl4N1kyeGhjM05PWVcxbE9pSndhR0Z6WlY5ZmNtRnBi'
    || 'Q0lzY205c1pUb2laM0p2ZFhBaUxDSmhjbWxoTFd4aFltVnNJam9pUkdWd2JHOTViV1Z1ZENCd2FHRnpaU0lzWTJocGJHUnlaVzQ2WkM1dFlYQW9kejArYnk1'
    || 'cWMzaHpLQ0ppZFhSMGIyNGlMSHQwZVhCbE9pSmlkWFIwYjI0aUxDSmtZWFJoTFhCb1lYTmxJanAzTG1sa0xHTnNZWE56VG1GdFpUb2ljR2hoYzJWZlgySjBi'
    || 'aUJ3YUdGelpWOWZZblJ1TFMwaUszY3VjM1JoZEdVcktHRTlQVDEzTG1sa1B5SWdhWE10YjNCbGJpSTZJaUlwTENKaGNtbGhMV04xY25KbGJuUWlPbmN1YzNS'
    || 'aGRHVTlQVDBpWTNWeWNtVnVkQ0kvSW5OMFpYQWlPblp2YVdRZ01Dd2lZWEpwWVMxbGVIQmhibVJsWkNJNllUMDlQWGN1YVdRc2IyNURiR2xqYXpvb0tUMCta'
    || 'eWhoUFQwOWR5NXBaRDl1ZFd4c09uY3VhV1FwTEdOb2FXeGtjbVZ1T2x0dkxtcHplQ2dpYzNCaGJpSXNlMk5zWVhOelRtRnRaVG9pY0doaGMyVmZYMnhoWW1W'
    || 'c0lpeGphR2xzWkhKbGJqcDNMbXhoWW1Wc2ZTa3NieTVxYzNnb0luTndZVzRpTEh0amJHRnpjMDVoYldVNkluQm9ZWE5sWDE5bWFXZDFjbVVpTEdOb2FXeGtj'
    || 'bVZ1T25jdVptbG5kWEpsZlNrc2R5NXRiMjVsZVQ5dkxtcHplQ2dpYzNCaGJpSXNlMk5zWVhOelRtRnRaVG9pY0doaGMyVmZYMjF2Ym1WNUlpeGphR2xzWkhK'
    || 'bGJqcDNMbTF2Ym1WNWZTazZiblZzYkYxOUxIY3VhV1FwS1gwcExFTS9ieTVxYzNoektDSmthWFlpTEh0amJHRnpjMDVoYldVNkluQm9ZWE5sWDE5a1pYUmhh'
    || 'V3dpTEdOb2FXeGtjbVZ1T2x0dkxtcHplQ2dpY0NJc2UyTnNZWE56VG1GdFpUb2ljR2hoYzJWZlgySnNkWEppSWl4amFHbHNaSEpsYmpwRExtSnNkWEppZlNr'
    || 'c2J5NXFjM2h6S0NKd0lpeDdZMnhoYzNOT1lXMWxPaUp3YUdGelpWOWZZbUZ6YVhNaUxHTm9hV3hrY21WdU9sdHZMbXB6ZUNnaWMzUnliMjVuSWl4N1kyaHBi'
    || 'R1J5Wlc0NlF5NW1hV2QxY21WOUtTeERMbTF2Ym1WNVAyOHVhbk40Y3lodkxrWnlZV2R0Wlc1MExIdGphR2xzWkhKbGJqcGJJaUFvSWl4RExtMXZibVY1TENJ'
    || 'cElsMTlLVHB1ZFd4c0xDSWc0b0NVSUNJc1F5NWlZWE5wYzExOUtTeERMbWxrUFQwOWVEOXZMbXB6ZUNnaWNDSXNlMk5zWVhOelRtRnRaVG9pY0doaGMyVmZY'
    || 'M2RvWlhKbElpeGphR2xzWkhKbGJqb2lWR2hwY3lCaWRXbHNaQ0JwY3lCcGJpQjBhR2x6SUhCb1lYTmxMaUo5S1RwdkxtcHplSE1vSW5BaUxIdGpiR0Z6YzA1'
    || 'aGJXVTZJbkJvWVhObFgxOW9iM2NpTEdOb2FXeGtjbVZ1T2xzaVZHOGdiVzkyWlNCb1pYSmxMQ0J6WlhRZ2RHaHBjeUJwYmlCMGFHVWdjMk55YVhCMElHRnVa'
    || 'Q0J5ZFc0Z2FYUWdZV2RoYVc0Nklpd2lJQ0lzYnk1cWMzZ29JbU52WkdVaUxIdGphR2xzWkhKbGJqcERMbk5sZEhScGJtZDlLVjE5S1YxOUtUcHVkV3hzWFgw'
    || 'cGZXWjFibU4wYVc5dUlGcGpLSHR3WVhsc2IyRmtPblY5S1h0amIyNXpkQ0JrUFU5aWFtVmpkQzVyWlhsektIVXVjR0Z1Wld4ektTNW1hV3gwWlhJb2VEMCtl'
    || 'Q0U5UFNKamIyNTBaWGgwSWlrc1lUMWtMbVpwYkhSbGNpaDRQVDU0YmloMUxuQmhibVZzYzF0NFhTa3BMR2M5WkM1bWFXeDBaWElvZUQwK2VXNG9kUzV3WVc1'
    || 'bGJITmJlRjBwSmlZaGVHNG9kUzV3WVc1bGJITmJlRjBwS1R0eVpYUjFjbTRoWVM1c1pXNW5kR2dtSmlGbkxteGxibWQwYUQ5dWRXeHNPbTh1YW5ONGN5aHZM'
    || 'a1p5WVdkdFpXNTBMSHRqYUdsc1pISmxianBiWnk1c1pXNW5kR2cvYnk1cWMzaHpLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbUpoYm01bGNpQmlZVzV1WlhJ'
    || 'dExXWmhhV3dpTEdOb2FXeGtjbVZ1T2x0bkxteGxibWQwYUN3aUlHOW1JQ0lzWkM1c1pXNW5kR2dzSWlCd1lXNWxiSE1nWkdsa0lHNXZkQ0JzYjJGa0lDZ2lM'
    || 'R2N1YW05cGJpZ2lMQ0FpS1N3aUtTNGdWR2hsSUc1MWJXSmxjbk1nWW1Wc2IzY2dZWEpsSUdsdVkyOXRjR3hsZEdVdUlsMTlLVHB1ZFd4c0xHRXViR1Z1WjNS'
    || 'b1AyOHVhbk40Y3lnaVpHbDJJaXg3WTJ4aGMzTk9ZVzFsT2lKaVlXNXVaWElnWW1GdWJtVnlMUzFwYm1adklpeGphR2xzWkhKbGJqcGJZUzVzWlc1bmRHZ3NJ'
    || 'aUJ2WmlBaUxHUXViR1Z1WjNSb0xDSWdjMlZqZEdsdmJuTWdkMlZ5WlNCdWIzUWdZblZwYkhRZ1lua2dkR2hwY3lCeWRXNGdLQ0lzWVM1cWIybHVLQ0lzSUNJ'
    || 'cExDSXBMaUJVYUdGMElHbHpJR1Y0Y0dWamRHVmtJRzl1SUdFZ1pHbHpZMjkyWlhKNUxXOXViSGtnY25WdUlPS0FsQ0JsWVdOb0lHTmhjbVFnYzJGNWN5QjNh'
    || 'R2xqYUNCelpYUjBhVzVuSUdacGJHeHpJR2wwSUdsdUxpSmRmU2s2Ym5Wc2JGMTlLWDFtZFc1amRHbHZiaUJ4WXloMUtYdGpiMjV6ZENCa1BXUnZZM1Z0Wlc1'
    || 'MExtZGxkRVZzWlcxbGJuUkNlVWxrS0NKeWIyOTBJaWs3YVdZb0lXUXBlMk52Ym5OdmJHVXVaWEp5YjNJb0ltOXVaWE5vYjNRZ1ZVazZJRzV2SUNOeWIyOTBJ'
    || 'R1ZzWlcxbGJuUWdkRzhnYlc5MWJuUWdhVzUwYnlJcE8zSmxkSFZ5Ym4xamIyNXpkQ0JoUFhoaktDazdkbU11WTNKbFlYUmxVbTl2ZENoa0tTNXlaVzVrWlhJ'
    || 'b2J5NXFjM2dvYnk1R2NtRm5iV1Z1ZEN4N1kyaHBiR1J5Wlc0NmRTaGhLWDBwS1gxbWRXNWpkR2x2YmlCS1l5aDdjMlZuYldWdWRITTZkU3hvWldsbmFIUTZa'
    || 'RDB5TW4wcGUyTnZibk4wSUdFOWUyZHZiMlE2SW5aaGNpZ3RMV2R2YjJRcElpeDNZWEp1T2lKMllYSW9MUzEzWVhKdUtTSXNZbUZrT2lKMllYSW9MUzFpWVdR'
    || 'cElpeGhZMk5sYm5RNkluWmhjaWd0TFdGalkyVnVkQ2tpTEhOcmVUb2lkbUZ5S0MwdGMydDVLU0lzWkdsdE9pSjJZWElvTFMxa2FXMHBJbjBzWnoxMUxuSmxa'
    || 'SFZqWlNnb2VDeERLVDArZUN0TllYUm9MbTFoZUNnd0xFTXVkbUZzZFdVcExEQXBPM0psZEhWeWJpQm5QVDA5TUQ5dWRXeHNPbTh1YW5ONEtDSmthWFlpTEh0'
    || 'amJHRnpjMDVoYldVNkluTmpZV3hsTFdKaGNpSXNjM1I1YkdVNmUyaGxhV2RvZERwa2ZTeHliMnhsT2lKcGJXY2lMQ0poY21saExXeGhZbVZzSWpwMUxtMWhj'
    || 'Q2g0UFQ1Z0pIdDRMbXhoWW1Wc1B6OGlJbjA2SUNSN2VDNTJZV3gxWlgxZ0tTNXFiMmx1S0NJc0lDSXBMR05vYVd4a2NtVnVPblV1YldGd0tDaDRMRU1wUFQ1'
    || 'N1kyOXVjM1FnVXoxTllYUm9MbTFoZUNnd0xIZ3VkbUZzZFdVcEwyY3FNVEF3TzJsbUtGTTlQVDB3S1hKbGRIVnliaUJ1ZFd4c08yTnZibk4wSUhjOWVDNTBi'
    || 'MjVsUDJGYmVDNTBiMjVsWFQ4L2VDNTBiMjVsT2lKMllYSW9MUzFoWTJObGJuUXBJanR5WlhSMWNtNGdieTVxYzNnb0ltUnBkaUlzZTJOc1lYTnpUbUZ0WlRv'
    || 'aWMyTmhiR1V0WW1GeVgxOXpaV2NpTEhOMGVXeGxPbnQzYVdSMGFEcGdKSHRUZlNWZ0xHSmhZMnRuY205MWJtUTZkMzBzZEdsMGJHVTZlQzVzWVdKbGJEOWdK'
    || 'SHQ0TG14aFltVnNmVG9nSkh0NExuWmhiSFZsZldBNlUzUnlhVzVuS0hndWRtRnNkV1VwTEdOb2FXeGtjbVZ1T25ndWJHRmlaV3dtSmxNK09EOXZMbXB6ZUNn'
    || 'aWMzQmhiaUlzZTJOc1lYTnpUbUZ0WlRvaWMyTmhiR1V0WW1GeVgxOXNZV0psYkNJc1kyaHBiR1J5Wlc0NmVDNXNZV0psYkgwcE9tNTFiR3g5TEVNcGZTbDlL'
    || 'WDFqYjI1emRDQnhQWFU5UGs1MWJXSmxjaWgxUHo4d0tTeGlZejE3UjBWT01sOVZVRWRTUVVSRk9pSmlZV1FpTEVGRVFWQlVTVlpGWDBOQlRrUkpSRUZVUlRv'
    || 'aVltRmtJaXhTUlVSVlEwVmZRVlZVVDE5VFZWTlFSVTVFT2lKM1lYSnVJaXhCUkVSZlVrVlRUMVZTUTBWZlRVOU9TVlJQVWpvaWQyRnliaUlzVDBzNkltZHZi'
    || 'MlFpZlN4TGJqMTFQVDV4S0hVdVExSkZSRWxVVTE5VlUwVkVLVDA5UFRBbUpuRW9kUzVCUTFSSlZrVmZSRUZaVXlrOVBUMHdPMloxYm1OMGFXOXVJR1ZrS0h0'
    || 'd09uVjlLWHRqYjI1emRDQmtQVTlsS0hVc0luTmhkbWx1WjNNaUtTeGhQV1F1Y21Wa2RXTmxLQ2hXTEZFcFBUNVdLM0VvVVM1RlUxUmZVMEZXU1U1SFUxOURV'
    || 'a1ZFU1ZSVEtTd3dLU3huUFU5bEtIVXNJbk53Wlc1a0lpa3VjbVZrZFdObEtDaFdMRkVwUFQ1V0szRW9VUzVEVWtWRVNWUlRYMVZUUlVRcExEQXBMSGc5WkM1'
    || 'bWFXeDBaWElvVmowK1UzUnlhVzVuS0ZZdVVrVkRUMDFOUlU1RVFWUkpUMDRwSVQwOUlrOUxJaVltSVV0dUtGWXBLUzVzWlc1bmRHZ3NRejFrTG1acGJIUmxj'
    || 'aWhMYmlrdWJHVnVaM1JvTEZNOWRTNWpiMjUwWlhoMFB6OTdmU3gzUFhFb1V5NVhTVTVFVDFkZlJFRlpVeWw4Zkc1MWJHd3NYejFQWlNoMUxDSjNhRjlrY21s'
    || 'c2JDSXBMRXc5WHk1c1pXNW5kR2crTUQ5Zld6QmRPbTUxYkd3c1RqMU1QM0VvVEM1QlEwTlVYMVJQVkVGTVgwTlNSVVJKVkZNcE9qQXNUejFNUDNFb1RDNVhT'
    || 'RjlRUTFRcE9qQXNSajFNUDFOMGNtbHVaeWhNTGxkQlVrVklUMVZUUlY5T1FVMUZLVHB1ZFd4c0xFczlYeTVtYVd4MFpYSW9WajArY1NoV0xsZElYMUpCVGtz'
    || 'cFBUMDlNU2tzUnoxTExuSmxaSFZqWlNnb1ZpeFJLVDArVml0eEtGRXVVVjlVU1UxRlgxQkRWQ2tzTUNrN2NtVjBkWEp1SUc4dWFuTjRLRVpsTEh0MGFYUnNa'
    || 'VG9pVjJoaGRDQjBhR2x6SUdadmRXNWtJaXgzYVdSbE9pRXdMR2hwYm5RNllGTmhkbWx1WjNNZ2FHVnlaU0JoY21VZ1VGSlBTa1ZEVkVWRUlHWnliMjBnZDJG'
    || 'eVpXaHZkWE5sSUhObGRIUnBibWR6SUdGdVpDQjFjMkZuWlNCd1lYUjBaWEp1Y3l3S0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnSUc1dmRDQnRaV0Z6ZFhKbFpDNGdR'
    || 'WEJ3YkhrZ1lTQmphR0Z1WjJVc0lIUm9aVzRnY21WamIzSmtJSFJvWlNCdFpXRnpkWEpsWkNCbWFXZDFjbVVnYVc0S0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnSUZO'
    || 'QlZrbE9SMU5mVUZKUFNrVkRWRWxQVGxNZ1ltVm1iM0psSUhGMWIzUnBibWNnWVNCdWRXMWlaWElnZEc4Z1lXNTViMjVsTG1Bc1kyaHBiR1J5Wlc0NmJ5NXFj'
    || 'M2h6S0V4bExIdHdZVzVsYkRwMUxuQmhibVZzY3k1ellYWnBibWR6TEdOb2FXeGtjbVZ1T2x0dkxtcHplSE1vSW1ScGRpSXNlMk5zWVhOelRtRnRaVG9pYzNS'
    || 'aGRDMXliM2NpTEdOb2FXeGtjbVZ1T2x0dkxtcHplQ2hEZEN4N2JHRmlaV3c2SWtOeVpXUnBkSE1nZFhObFpDSXNkbUZzZFdVNldTaE5ZWFJvTG5KdmRXNWtL'
    || 'R2NwS1N4emRXSTZkejlnYjNabGNpQWtlM2Q5SUdSaGVYTmdPaUp2ZG1WeUlIUm9aU0JrYVhOamIzWmxjbmtnZDJsdVpHOTNJbjBwTEc4dWFuTjRLRU4wTEh0'
    || 'c1lXSmxiRG9pVUhKdmFtVmpkR1ZrSUhOaGRtbHVaeUlzZG1Gc2RXVTZJdUtKcENBaUsxa29UV0YwYUM1eWIzVnVaQ2hoS1Nrc2RXNXBkRG9pSUdOeUlpeDBi'
    || 'MjVsT21FK01EOGlaMjl2WkNJNmRtOXBaQ0F3TEhOMVlqb2lWVkJRUlZJZ1FrOVZUa1FzSUdGdVpDQndjbTlxWldOMFpXUWdjbUYwYUdWeUlIUm9ZVzRnYldW'
    || 'aGMzVnlaV1FpZlNrc2J5NXFjM2dvUTNRc2UyeGhZbVZzT2lKWFlYSmxhRzkxYzJWeklIUnZJR0ZqZENCdmJpSXNkbUZzZFdVNmVDeDBiMjVsT25nL0luZGhj'
    || 'bTRpT2lKbmIyOWtJaXh6ZFdJNllHOW1JQ1I3WkM1c1pXNW5kR2d0UTMwZ2RHaGhkQ0J5WVc0Z1pIVnlhVzVuSUhSb1pTQjNhVzVrYjNkZ2ZTa3NieTVxYzNn'
    || 'b1EzUXNlMnhoWW1Wc09pSlRhR0Z5WlNCdlppQnpjR1Z1WkNJc2RtRnNkV1U2Wno0d1B5TGlpYVFnSWl0WktFMWhkR2d1Y205MWJtUW9ZUzluS2pGbE15a3ZN'
    || 'VEFwT2lMaWdKUWlMSFZ1YVhRNklpVWlMSE4xWWpvaWRYQndaWEl0WW05MWJtUWdjMkYyYVc1bklDOGdZM0psWkdsMGN5QjFjMlZrSW4wcFhYMHBMRVltSms4'
    || 'K01EOXZMbXB6ZUhNb2J5NUdjbUZuYldWdWRDeDdZMmhwYkdSeVpXNDZXMjh1YW5ONEtFMWpMSHR3WTNRNlR5eHNZV0psYkRwZ0pIdEdmU0J6YUdGeVpTQnZa'
    || 'aUJoWTJOdmRXNTBJR055WldScGRITmdMRzltT21Ba2Uxa29UV0YwYUM1eWIzVnVaQ2h4S0V3dVYwaGZRMUpGUkVsVVV5a3BLWDBnYjJZZ0pIdFpLRTFoZEdn'
    || 'dWNtOTFibVFvVGlrcGZTQmpjbUFzZEc5dVpUcFBQalV3UHlKaVlXUWlPazgrTWpVL0luZGhjbTRpT25admFXUWdNSDBwTEc4dWFuTjRjeWhaYml4N1kyaHBi'
    || 'R1J5Wlc0Nld5SkRiMjVqWlc1MGNtRjBhVzl1SUdaeWIyMGdWMEZTUlVoUFZWTkZYMDFGVkVWU1NVNUhYMGhKVTFSUFVsa2diM1psY2lCMGFHVWdaR2x6WTI5'
    || 'MlpYSjVJSGRwYm1SdmR5NGlMRWMrTUQ5Z0lFbDBjeUIwYjNBZ0pIdExMbXhsYm1kMGFIMGdjWFZsY25rZ2NHRjBkR1Z5YmlSN1N5NXNaVzVuZEdnOVBUMHhQ'
    || 'eUlpT2lKekluMGdZV05qYjNWdWRDQm1iM0lnSkh0SExuUnZSbWw0WldRb01TbDlKU0J2WmlCMGFHRjBJSGRoY21Wb2IzVnpaU2R6SUdWc1lYQnpaV1FnZEds'
    || 'dFpTNGdUM0JsYmlCMGFHVWdaSEpwYkd3Z1ltVnNiM2NnZEc4Z2MyVmxJSFJvWlcwdVlEb2lJbDE5S1YxOUtUcHVkV3hzTEc4dWFuTjRjeWhRWXl4N2RHbDBi'
    || 'R1U2SWxSb1pYTmxJSE5oZG1sdVozTWdZWEpsSUdFZ1kyVnBiR2x1Wnl3Z2JtOTBJR0VnWm05eVpXTmhjM1F1SWl4amFHbHNaSEpsYmpwYklrRndjR3g1SUdF'
    || 'Z1kyaGhibWRsTENCMGFHVnVJSEpsWVdRZ2RHaGxJRzFsWVhOMWNtVmtJR1pwWjNWeVpTQm1jbTl0SUNJc2J5NXFjM2dvSW1OdlpHVWlMSHRqYUdsc1pISmxi'
    || 'am9pVTBGV1NVNUhVMTlRVWs5S1JVTlVTVTlPVXlKOUtTd2lJR0psWm05eVpTQnhkVzkwYVc1bklHbDBMaUpkZlNsZGZTbDlLWDFtZFc1amRHbHZiaUIwWkNo'
    || 'N2NEcDFmU2w3WTI5dWMzUWdaRDFQWlNoMUxDSmphSFZ5YmlJcExHRTlUMlVvZFN3aWMyRjJhVzVuY3lJcE8ybG1LQ0ZrTG14bGJtZDBhSHg4SVdFdWJHVnVa'
    || 'M1JvS1hKbGRIVnliaUJ1ZFd4c08yTnZibk4wSUdjOWJtVjNJRTFoY0NoaExtMWhjQ2hrWlQwK1cxTjBjbWx1Wnloa1pTNVhRVkpGU0U5VlUwVmZUa0ZOUlNr'
    || 'c1pHVmRLU2tzZUQxa0xtWnBibVFvWkdVOVBudGpiMjV6ZENCeVpUMW5MbWRsZENoVGRISnBibWNvWkdVdVYwRlNSVWhQVlZORlgwNUJUVVVwS1R0eVpYUjFj'
    || 'bTRnY21VbUpuRW9aR1V1VWtWVFZVMUZVMTlRUlZKZlJFRlpLVDR3SmlaeEtISmxMa0ZWVkU5ZlUxVlRVRVZPUkY5VFJVTlRLVDQyTUgwcE8ybG1LQ0Y0S1hK'
    || 'bGRIVnliaUJ1ZFd4c08yTnZibk4wSUVNOVUzUnlhVzVuS0hndVYwRlNSVWhQVlZORlgwNUJUVVVwTEZNOVp5NW5aWFFvUXlrc2R6MXhLSGd1VWtWVFZVMUZV'
    || 'MTlRUlZKZlJFRlpLU3hmUFhFb1V5NUJWVlJQWDFOVlUxQkZUa1JmVTBWRFV5a3NURDAyTUN4T1BYRW9VeTVGVTFSZlUwRldTVTVIVTE5RFVrVkVTVlJUS1N4'
    || 'UFBUWTRNQ3hHUFRFMkxFczlNVFFzUnoxTEt6UXNWajFISzBZck1USXNVVDFXS3pRc1VXVTlVU3RHS3pRc2EyVTlUV0YwYUM1dGFXNG9NVEFzVFdGMGFDNXRZ'
    || 'WGdvTkN4TllYUm9Mbkp2ZFc1a0tIY3ZOVEFwS1Nrc2FtVTlUeW91TURRc2RtVTlLRTh0YTJVcWFtVXBMMnRsTEUxbFBYWmxLaWhNTDE4cE8yWjFibU4wYVc5'
    || 'dUlIaGxLR1JsTEhKbEtYdGpiMjV6ZENCS1pUMWJYVHRzWlhRZ1ltVTlNRHRtYjNJb2JHVjBJQ1JsUFRBN0pHVThhMlU3SkdVckt5bEtaUzV3ZFhOb0tHOHVh'
    || 'bk40S0NKeVpXTjBJaXg3ZURwaVpTeDVPbVJsTEhkcFpIUm9PbXBsTEdobGFXZG9kRHBHTEdacGJHdzZJblpoY2lndExXRmpZMlZ1ZENraUxISjRPakY5TEdC'
    || 'aEpIc2taWDFnS1Nrc1ltVXJQV3BsTEhKbFBqRW1Ka3BsTG5CMWMyZ29ieTVxYzNnb0luSmxZM1FpTEh0NE9tSmxMSGs2WkdVc2QybGtkR2c2VFdGMGFDNXRh'
    || 'VzRvY21Vc1R5MWlaU2tzYUdWcFoyaDBPa1lzWm1sc2JEb2lkbUZ5S0MwdGMzVnlabUZqWlMwektTSXNjM1J5YjJ0bE9pSjJZWElvTFMxc2FXNWxMVElwSWl4'
    || 'emRISnZhMlZYYVdSMGFEb3VOU3h6ZEhKdmEyVkVZWE5vWVhKeVlYazZJak1zTWlJc2NuZzZNWDBzWUdra2V5UmxmV0FwS1N4aVpTczljbVU3Y21WMGRYSnVJ'
    || 'RXBsZldOdmJuTjBJR05sUFd0bEtpaHFaU3ROWlNrN2NtVjBkWEp1SUc4dWFuTjRLRVpsTEh0MGFYUnNaVHBnVTNWemNHVnVaQ0J3WVhSMFpYSnVPaUFrZTBO'
    || 'OVlDeDNhV1JsT2lFd0xHaHBiblE2WUZOamFHVnRZWFJwWXlCdlppQitKSHROWVhSb0xuSnZkVzVrS0hjcGZTQnlaWE4xYldWekwyUmhlU0JoZENBa2UxOTlj'
    || 'eUJoZFhSdkxYTjFjM0JsYm1RdUlFVmhZMmdnWkdGemFHVmtJR0pzYjJOcklHbHpJR2xrYkdVZ2RHbHRaU0JpYVd4c1pXUWdZWFFnZEdobElHMXBibWx0ZFcw'
    || 'Z2FXNWpjbVZ0Wlc1MExpQlVhR1VnYkc5M1pYSWdjM1J5YVhBZ2MyaHZkM01nZDJoaGRDQWtlMHg5Y3lCM2IzVnNaQ0JzYjI5cklHeHBhMlV1WUN4amFHbHNa'
    || 'SEpsYmpwdkxtcHplSE1vVEdVc2UzQmhibVZzT25VdWNHRnVaV3h6TG1Ob2RYSnVMR05vYVd4a2NtVnVPbHR2TG1wemVITW9Jbk4yWnlJc2UzWnBaWGRDYjNn'
    || 'NllEQWdNQ0FrZTA5OUlDUjdVV1Y5WUN4M2FXUjBhRG9pTVRBd0pTSXNjM1I1YkdVNmUyMWhlRmRwWkhSb09rOHNaR2x6Y0d4aGVUb2lZbXh2WTJzaWZTeGph'
    || 'R2xzWkhKbGJqcGJieTVxYzNoektDSjBaWGgwSWl4N2VEb3dMSGs2U3l4emRIbHNaVHA3Wm05dWRGTnBlbVU2TVRFc1ptbHNiRG9pZG1GeUtDMHRaR2x0S1NK'
    || 'OUxHTm9hV3hrY21WdU9sc2lRM1Z5Y21WdWREb2dJaXhmTENKeklHRjFkRzh0YzNWemNHVnVaQ0pkZlNrc2VHVW9SeXgyWlNrc2J5NXFjM2h6S0NKMFpYaDBJ'
    || 'aXg3ZURvd0xIazZWaXh6ZEhsc1pUcDdabTl1ZEZOcGVtVTZNVEVzWm1sc2JEb2lkbUZ5S0MwdFpHbHRLU0o5TEdOb2FXeGtjbVZ1T2xzaVVtVmpiMjF0Wlc1'
    || 'a1pXUTZJQ0lzVEN3aWN5SmRmU2tzZUdVb1VTeE5aU2tzVHkxalpUNDBKaVp2TG1wemVDZ2ljbVZqZENJc2UzZzZZMlVzZVRwUkxIZHBaSFJvT2s4dFkyVXNh'
    || 'R1ZwWjJoME9rWXNabWxzYkRvaWRtRnlLQzB0WjI5dlpDa2lMRzl3WVdOcGRIazZMakUxTEhKNE9qRjlLU3hQTFdObFBqVXdKaVp2TG1wemVDZ2lkR1Y0ZENJ'
    || 'c2UzZzZZMlVyS0U4dFkyVXBMeklzZVRwUkswWXZNaXMwTEhSbGVIUkJibU5vYjNJNkltMXBaR1JzWlNJc2MzUjViR1U2ZTJadmJuUlRhWHBsT2pFeExHWnBi'
    || 'R3c2SW5aaGNpZ3RMV2R2YjJRcEluMHNZMmhwYkdSeVpXNDZJbWxrYkdVZ2RHbHRaU0J6WVhabFpDSjlLVjE5S1N4dkxtcHplSE1vV1c0c2UyTm9hV3hrY21W'
    || 'dU9sc2lVMk5vWlcxaGRHbGpMQ0J1YjNRZ1lTQnlaV052Y21SbFpDQjBjbUZqWlM0Z0lpeE5ZWFJvTG5KdmRXNWtLSGNwTENJZ2NtVnpkVzFsY3k5a1lYa2dZ'
    || 'WFFnSWl4ZkxDSnpJRDBnZmlJc1RXRjBhQzV5YjNWdVpDaDNLbDh2TXpZd01Da3NJaUJvY25NdlpHRjVJR0pwYkd4aFlteGxJR2xrYkdVdUlFRjBJQ0lzVEN3'
    || 'aWN6b2dmaUlzVFdGMGFDNXliM1Z1WkNoM0trd3ZNell3TUNrc0lpQm9jbk11SUZOaGRtbHVaeUJqWldsc2FXNW5PaUFpTEZrb1RXRjBhQzV5YjNWdVpDaE9L'
    || 'akV3S1M4eE1Da3NJaUJqY21Wa2FYUnpMaUpkZlNsZGZTbDlLWDFtZFc1amRHbHZiaUJ1WkNoN2NEcDFmU2w3WTI5dWMzUWdaRDFQWlNoMUxDSnpZWFpwYm1k'
    || 'eklpa3VabWxzZEdWeUtIYzlQaUZMYmloM0tTazdhV1lvSVdRdWJHVnVaM1JvS1hKbGRIVnliaUJ1ZFd4c08yTnZibk4wSUdFOWJtVjNJRTFoY0R0bWIzSW9Z'
    || 'Mjl1YzNRZ2R5QnZaaUJrS1h0amIyNXpkQ0JmUFZOMGNtbHVaeWgzTGxKRlEwOU5UVVZPUkVGVVNVOU9QejhpVDBzaUtUdGhMbk5sZENoZkxDaGhMbWRsZENo'
    || 'ZktUOC9NQ2tyY1NoM0xrTlNSVVJKVkZOZlZWTkZSQ2twZldOdmJuTjBJR2M5V3lKU1JVUlZRMFZmUVZWVVQxOVRWVk5RUlU1RUlpd2lRVVJCVUZSSlZrVmZR'
    || 'MEZPUkVsRVFWUkZJaXdpUjBWT01sOVZVRWRTUVVSRklpd2lRVVJFWDFKRlUwOVZVa05GWDAxUFRrbFVUMUlpTENKUFN5SmRMSGc5ZTFKRlJGVkRSVjlCVlZS'
    || 'UFgxTlZVMUJGVGtRNkluZGhjbTRpTEVGRVFWQlVTVlpGWDBOQlRrUkpSRUZVUlRvaVltRmtJaXhIUlU0eVgxVlFSMUpCUkVVNkltSmhaQ0lzUVVSRVgxSkZV'
    || 'MDlWVWtORlgwMVBUa2xVVDFJNkltRmpZMlZ1ZENJc1QwczZJbVJwYlNKOUxFTTllMUpGUkZWRFJWOUJWVlJQWDFOVlUxQkZUa1E2SWxKbFpIVmpaU0J6ZFhO'
    || 'd1pXNWtJaXhCUkVGUVZFbFdSVjlEUVU1RVNVUkJWRVU2SWtGa1lYQjBhWFpsSWl4SFJVNHlYMVZRUjFKQlJFVTZJa2RsYmpJaUxFRkVSRjlTUlZOUFZWSkRS'
    || 'VjlOVDA1SlZFOVNPaUpCWkdRZ2JXOXVhWFJ2Y2lJc1QwczZJazlMSW4wc1V6MW5MbVpwYkhSbGNpaDNQVDRvWVM1blpYUW9keWsvUHpBcFBqQXBMbTFoY0No'
    || 'M1BUNG9lM1poYkhWbE9tRXVaMlYwS0hjcExIUnZibVU2ZUZ0M1hTeHNZV0psYkRwRFczZGRQejkzZlNrcE8zSmxkSFZ5YmlCVExteGxibWQwYUQ5dkxtcHpl'
    || 'Q2hHWlN4N2RHbDBiR1U2SWtac1pXVjBJR055WldScGRITWdZbmtnY21WamIyMXRaVzVrWVhScGIyNGlMSGRwWkdVNklUQXNZMmhwYkdSeVpXNDZieTVxYzNo'
    || 'ektFeGxMSHR3WVc1bGJEcDFMbkJoYm1Wc2N5NXpZWFpwYm1kekxHTm9hV3hrY21WdU9sdHZMbXB6ZUNoS1l5eDdjMlZuYldWdWRITTZVeXhvWldsbmFIUTZN'
    || 'alI5S1N4dkxtcHplQ2dpWkdsMklpeDdjM1I1YkdVNmUyUnBjM0JzWVhrNkltWnNaWGdpTEdkaGNEb3hNaXh0WVhKbmFXNVViM0E2Tml4bWJHVjRWM0poY0Rv'
    || 'aWQzSmhjQ0o5TEdOb2FXeGtjbVZ1T2xNdWJXRndLSGM5UG04dWFuTjRjeWdpYzNCaGJpSXNlM04wZVd4bE9udG1iMjUwVTJsNlpUb3hNU3hqYjJ4dmNqb2lk'
    || 'bUZ5S0MwdFpHbHRLU0o5TEdOb2FXeGtjbVZ1T2x0M0xteGhZbVZzTENJNklDSXNXU2hOWVhSb0xuSnZkVzVrS0hjdWRtRnNkV1VwS1N3aUlHTnlJbDE5TEhj'
    || 'dWJHRmlaV3dwS1gwcFhYMHBmU2s2Ym5Wc2JIMWpiMjV6ZENCWFpUMTdaSEpwYkd3NmUyUnBjM0JzWVhrNkltWnNaWGdpTEdac1pYaEVhWEpsWTNScGIyNDZJ'
    || 'bU52YkhWdGJpSXNaMkZ3T2lJeWNIZ2lMRzFoY21kcGJsUnZjRG9pT0hCNEluMHNjbTkzT250a2FYTndiR0Y1T2lKbWJHVjRJaXhoYkdsbmJrbDBaVzF6T2lK'
    || 'alpXNTBaWElpTEdkaGNEb2lPSEI0SWl4M2FXUjBhRG9pTVRBd0pTSXNjR0ZrWkdsdVp6b2lObkI0SURod2VDSXNZbTl5WkdWeU9pSXhjSGdnYzI5c2FXUWdk'
    || 'bUZ5S0MwdFltOXlaR1Z5S1NJc1ltOXlaR1Z5VW1Ga2FYVnpPaUkwY0hnaUxHSmhZMnRuY205MWJtUTZJblpoY2lndExYTjFjbVpoWTJVdE1pa2lMR04xY25O'
    || 'dmNqb2ljRzlwYm5SbGNpSXNabTl1ZEVaaGJXbHNlVG9pYVc1b1pYSnBkQ0lzWm05dWRGTnBlbVU2SWpFemNIZ2lMSFJsZUhSQmJHbG5iam9pYkdWbWRDSXNZ'
    || 'MjlzYjNJNkltbHVhR1Z5YVhRaWZTeHliM2RQY0dWdU9udGlZV05yWjNKdmRXNWtPaUoyWVhJb0xTMXpkWEptWVdObExURXBJaXhpYjNKa1pYSkRiMnh2Y2pv'
    || 'aWRtRnlLQzB0WVdOalpXNTBLU0o5TEdGeWNtOTNPbnQzYVdSMGFEb2lNVEp3ZUNJc1pteGxlRk5vY21sdWF6b3dMR1p2Ym5SVGFYcGxPaUl4TVhCNElpeGpi'
    || 'Mnh2Y2pvaWRtRnlLQzB0ZEdWNGRDMHlLU0o5TEc1aGJXVTZlMlpzWlhnNklqRWdNU0JoZFhSdklpeG1iMjUwVjJWcFoyaDBPall3TUN4dGFXNVhhV1IwYURv'
    || 'd0xHOTJaWEptYkc5M09pSm9hV1JrWlc0aUxIUmxlSFJQZG1WeVpteHZkem9pWld4c2FYQnphWE1pTEhkb2FYUmxVM0JoWTJVNkltNXZkM0poY0NKOUxHSmhj'
    || 'bGR5WVhBNmUyWnNaWGc2SWpBZ01DQXhNakJ3ZUNJc2FHVnBaMmgwT2lJMmNIZ2lMR0poWTJ0bmNtOTFibVE2SW5aaGNpZ3RMWE4xY21aaFkyVXRNeWtpTEdK'
    || 'dmNtUmxjbEpoWkdsMWN6b2lNM0I0SWl4dmRtVnlabXh2ZHpvaWFHbGtaR1Z1SW4wc1ltRnlPbnRvWldsbmFIUTZJakV3TUNVaUxHSmhZMnRuY205MWJtUTZJ'
    || 'blpoY2lndExXRmpZMlZ1ZENraUxHSnZjbVJsY2xKaFpHbDFjem9pTTNCNEluMHNZM0k2ZTJac1pYZzZJakFnTUNCaGRYUnZJaXhtYjI1MFZtRnlhV0Z1ZEU1'
    || 'MWJXVnlhV002SW5SaFluVnNZWEl0Ym5WdGN5SXNkR1Y0ZEVGc2FXZHVPaUp5YVdkb2RDSXNiV2x1VjJsa2RHZzZJamN5Y0hnaUxHWnZiblJUYVhwbE9pSXhN'
    || 'bkI0SW4wc2NHTjBPbnRtYkdWNE9pSXdJREFnTkRCd2VDSXNabTl1ZEZaaGNtbGhiblJPZFcxbGNtbGpPaUowWVdKMWJHRnlMVzUxYlhNaUxIUmxlSFJCYkds'
    || 'bmJqb2ljbWxuYUhRaUxHWnZiblJUYVhwbE9pSXhNbkI0SWl4amIyeHZjam9pZG1GeUtDMHRkR1Y0ZEMweUtTSjlMSEYxWlhKcFpYTTZlMjFoY21kcGJqb2lN'
    || 'Q0F3SURSd2VDQXlNSEI0SWl4d1lXUmthVzVuT2lJNGNIZ2dNQ0EwY0hnaWZTeHdZWFIwWlhKdU9udG1iMjUwVTJsNlpUb2lNVEZ3ZUNJc2QyOXlaRUp5WldG'
    || 'ck9pSmljbVZoYXkxaGJHd2lMR052Ykc5eU9pSjJZWElvTFMxMFpYaDBMVElwSWl4bWIyNTBSbUZ0YVd4NU9pSjJZWElvTFMxdGIyNXZLU0lzYldGNFYybGtk'
    || 'R2c2SWpNeU1IQjRJaXhrYVhOd2JHRjVPaUpwYm14cGJtVXRZbXh2WTJzaUxHOTJaWEptYkc5M09pSm9hV1JrWlc0aUxIUmxlSFJQZG1WeVpteHZkem9pWld4'
    || 'c2FYQnphWE1pTEhkb2FYUmxVM0JoWTJVNkltNXZkM0poY0NKOUxISmxjM1E2ZTJadmJuUlRhWHBsT2lJeE1uQjRJaXhqYjJ4dmNqb2lkbUZ5S0MwdGRHVjRk'
    || 'QzB5S1NJc2NHRmtaR2x1WnpvaU5uQjRJRGh3ZUNJc1ltOXlaR1Z5Vkc5d09pSXhjSGdnYzI5c2FXUWdkbUZ5S0MwdFltOXlaR1Z5S1NJc2JXRnlaMmx1Vkc5'
    || 'd09pSTBjSGdpZlN4bGJYQjBlVHA3Wm05dWRGTnBlbVU2SWpFeWNIZ2lMR052Ykc5eU9pSjJZWElvTFMxMFpYaDBMVElwSWl4d1lXUmthVzVuT2lJMGNIZ2dN'
    || 'Q0F3SURJd2NIZ2lmU3h3WVhKMGFXRnNPbnRrYVhOd2JHRjVPaUppYkc5amF5SXNabTl1ZEZOcGVtVTZJakV4Y0hnaUxHTnZiRzl5T2lKMllYSW9MUzEwWlho'
    || 'MExUSXBJaXh0WVhKbmFXNVViM0E2SWpKd2VDSjlmVHRtZFc1amRHbHZiaUJ5WkNoN2NEcDFmU2w3WTI5dWMzUWdaRDFQWlNoMUxDSjNhRjlrY21sc2JDSXBM'
    || 'RnRoTEdkZFBVRjBMblZ6WlZOMFlYUmxLRzUxYkd3cExIZzlXMTBzUXoxdVpYY2dVMlYwTzJadmNpaGpiMjV6ZENCT0lHOW1JR1FwZTJOdmJuTjBJRTg5VTNS'
    || 'eWFXNW5LRTR1VjBGU1JVaFBWVk5GWDA1QlRVVXBPME11YUdGektFOHBmSHdvUXk1aFpHUW9UeWtzZUM1d2RYTm9LSHR1WVcxbE9rOHNZM0psWkdsMGN6cHhL'
    || 'RTR1VjBoZlExSkZSRWxVVXlrc2NHTjBPbkVvVGk1WFNGOVFRMVFwTEhGMVpYSnBaWE02VzExOUtTa3NUaTVSWDFKQlRrc2hQVDF1ZFd4c0ppWk9MbEZmVWtG'
    || 'T1N5RTlQWFp2YVdRZ01DWW1lRnQ0TG14bGJtZDBhQzB4WFM1eGRXVnlhV1Z6TG5CMWMyZ29UaWw5WTI5dWMzUWdVejFrTG14bGJtZDBhRDR3UDNFb1pGc3dY'
    || 'UzVCUTBOVVgxUlBWRUZNWDBOU1JVUkpWRk1wT2pBc2R6MTRMbkpsWkhWalpTZ29UaXhQS1QwK1RpdFBMbU55WldScGRITXNNQ2tzWHoxVExYY3NURDFUUGpB'
    || 'L1h5OVRLakV3TURvd08zSmxkSFZ5YmlCNExteGxibWQwYUQ5dkxtcHplQ2hHWlN4N2RHbDBiR1U2SWxkb1pYSmxJSFJvWlNCamNtVmthWFJ6SUdkdkxDQmhi'
    || 'bVFnZDJoaGRDQnlkVzV6SUhSb1pYSmxJaXgzYVdSbE9pRXdMR2hwYm5RNllFTnNhV05ySUdFZ2QyRnlaV2h2ZFhObElIUnZJSE5sWlNCcGRITWdkRzl3SUhG'
    || 'MVpYSjVJSEJoZEhSbGNtNXpJR0o1SUdWc1lYQnpaV1FnZEdsdFpTNEtJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ0lFTnlaV1JwZENCaGRIUnlhV0oxZEdsdmJpQmhk'
    || 'Q0IwYUdVZ2NYVmxjbmtnYkdWMlpXd2dhWE1nWlhOMGFXMWhkR1ZrSUhCeWIzQnZjblJwYjI1aGJDQjBid29nSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdaV3hoY0hO'
    || 'bFpDQjBhVzFsTENCdWIzUWdiV1ZoYzNWeVpXUWdaR2x5WldOMGJIa3VZQ3hqYUdsc1pISmxianB2TG1wemVITW9UR1VzZTNCaGJtVnNPblV1Y0dGdVpXeHpM'
    || 'bmRvWDJSeWFXeHNMR05vYVd4a2NtVnVPbHR2TG1wemVITW9JbkFpTEh0amJHRnpjMDVoYldVNkltNXZkR1VpTEdOb2FXeGtjbVZ1T2x0dkxtcHplSE1vSW5O'
    || 'MGNtOXVaeUlzZTJOb2FXeGtjbVZ1T2x0WktFMWhkR2d1Y205MWJtUW9VeWtwTENJZ1kzSmxaR2wwY3lKZGZTa3NJaUJoWTNKdmMzTWdkR2hsSUdScGMyTnZk'
    || 'bVZ5ZVNCM2FXNWtiM2N1SUZSdmNDQWlMSGd1YkdWdVozUm9MQ0lnZDJGeVpXaHZkWE5sSWl4NExteGxibWQwYUQwOVBURS9JaUk2SW5NaUxDSWdjMmh2ZDI0'
    || 'c0lHTnZkbVZ5YVc1bklDSXNLREV3TUMxTUtTNTBiMFpwZUdWa0tERXBMQ0lsSUc5bUlIUm9aU0IwYjNSaGJDNGlYWDBwTEc4dWFuTjRLRmx1TEh0amFHbHNa'
    || 'SEpsYmpvaVEzSmxaR2wwY3lCbWNtOXRJRmRCVWtWSVQxVlRSVjlOUlZSRlVrbE9SMTlJU1ZOVVQxSlpMaUJRWVhSMFpYSnVjeUJtY205dElGRlZSVkpaWDBo'
    || 'SlUxUlBVbGtzSUhKaGJtdGxaQ0JpZVNCbGVHVmpkWFJwYjI0Z2RHbHRaU3dnYkdsMFpYSmhiSE1nYm05eWJXRnNhWE5sWkM0aWZTa3NieTVxYzNoektDSmth'
    || 'WFlpTEh0emRIbHNaVHBYWlM1a2NtbHNiQ3hqYUdsc1pISmxianBiZUM1dFlYQW9UajArZTJOdmJuTjBJRTg5WVQwOVBVNHVibUZ0WlR0eVpYUjFjbTRnYnk1'
    || 'cWMzaHpLQ0prYVhZaUxIdGphR2xzWkhKbGJqcGJieTVxYzNoektDSmlkWFIwYjI0aUxIdHpkSGxzWlRwN0xpNHVWMlV1Y205M0xDNHVMazgvVjJVdWNtOTNU'
    || 'M0JsYmpwN2ZYMHNiMjVEYkdsamF6b29LVDArWnloUFAyNTFiR3c2VGk1dVlXMWxLU3dpWVhKcFlTMWxlSEJoYm1SbFpDSTZUeXhqYUdsc1pISmxianBiYnk1'
    || 'cWMzZ29Jbk53WVc0aUxIdHpkSGxzWlRwWFpTNWhjbkp2ZHl4amFHbHNaSEpsYmpwUFB5TGlscjRpT2lMaWxyZ2lmU2tzYnk1cWMzZ29Jbk53WVc0aUxIdHpk'
    || 'SGxzWlRwWFpTNXVZVzFsTEdOb2FXeGtjbVZ1T2s0dWJtRnRaWDBwTEc4dWFuTjRLQ0p6Y0dGdUlpeDdjM1I1YkdVNlYyVXVZbUZ5VjNKaGNDeGphR2xzWkhK'
    || 'bGJqcHZMbXB6ZUNnaWMzQmhiaUlzZTNOMGVXeGxPbnN1TGk1WFpTNWlZWElzZDJsa2RHZzZUV0YwYUM1dFlYZ29NaXhPTG5CamRDa3JJaVVpZlgwcGZTa3Ni'
    || 'eTVxYzNoektDSnpjR0Z1SWl4N2MzUjViR1U2VjJVdVkzSXNZMmhwYkdSeVpXNDZXMWtvVFdGMGFDNXliM1Z1WkNoT0xtTnlaV1JwZEhNcU1UQXdLUzh4TURB'
    || 'cExDSWdZM0lpWFgwcExHOHVhbk40Y3lnaWMzQmhiaUlzZTNOMGVXeGxPbGRsTG5CamRDeGphR2xzWkhKbGJqcGJUaTV3WTNRc0lpVWlYWDBwWFgwcExFOG1K'
    || 'azR1Y1hWbGNtbGxjeTVzWlc1bmRHZytNRDl2TG1wemVDZ2laR2wySWl4N2MzUjViR1U2VjJVdWNYVmxjbWxsY3l4amFHbHNaSEpsYmpvb0tDazlQbnRqYjI1'
    || 'emRDQkdQVTR1Y1hWbGNtbGxjeTV6YjIxbEtFczlQbkVvU3k1VlRreEJRa1ZNVEVWRUtUNHdKaVp4S0VzdVZVNU1RVUpGVEV4RlJDaytQWEVvU3k1RldFVkRW'
    || 'VlJKVDA1VEtTazdjbVYwZFhKdUlHOHVhbk40Y3lodkxrWnlZV2R0Wlc1MExIdGphR2xzWkhKbGJqcGJieTVxYzNnb1UyNHNlM0p2ZDNNNlRpNXhkV1Z5YVdW'
    || 'ekxHTnZiSE02VzN0clpYazZJbEZWUlZKWlgxUlpVRVVpTEd4aFltVnNPaUpVZVhCbElpeHlaVzVrWlhJNlN6MCtieTVxYzNnb2NtNHNlMk5vYVd4a2NtVnVP'
    || 'bE4wY21sdVp5aExLWDBwZlN4N2EyVjVPaUpGV0VWRFZWUkpUMDVUSWl4c1lXSmxiRG9pUlhobFkzVjBhVzl1Y3lJc1lXeHBaMjQ2SW5KcFoyaDBJbjBzZTJ0'
    || 'bGVUb2lWRTlVUVV4ZlUwVkRUMDVFVXlJc2JHRmlaV3c2SWtWc1lYQnpaV1FnS0hNcElpeGhiR2xuYmpvaWNtbG5hSFFpZlN4N2EyVjVPaUpSWDFSSlRVVmZV'
    || 'RU5VSWl4c1lXSmxiRG9pSlNCdlppQlhTQ0IwYVcxbElpeGhiR2xuYmpvaWNtbG5hSFFpTEhKbGJtUmxjanBMUFQ1dkxtcHplQ2hFWXl4N2NHTjBPbkVvU3lr'
    || 'c2RHOXVaVHB4S0VzcFBqTXdQeUozWVhKdUlqcDJiMmxrSURCOUtYMHNlMnRsZVRvaVVWVkZVbGxmVUVGVVZFVlNUaUlzYkdGaVpXdzZJbEJoZEhSbGNtNGdL'
    || 'R1pwY25OMElERXdNQ0JqYUdGeWN5a2lMSEpsYm1SbGNqb29TeXhIS1QwK2UyTnZibk4wSUZZOWNTaEhMbFZPVEVGQ1JVeE1SVVFwTEZFOWNTaEhMa1ZZUlVO'
    || 'VlZFbFBUbE1wTzNKbGRIVnliaUJXUGpBbUpsWStQVkUvYnk1cWMzZ29UR01zZTNaaGJIVmxPbTUxYkd3c2JtRTZJVEFzZEdsMGJHVTZJblJsZUhRZ2JtOTBJ'
    || 'SEpsZEdGcGJtVmtJbjBwT2xZK01EOXZMbXB6ZUhNb2J5NUdjbUZuYldWdWRDeDdZMmhwYkdSeVpXNDZXMjh1YW5ONEtDSmpiMlJsSWl4N2MzUjViR1U2VjJV'
    || 'dWNHRjBkR1Z5Yml4MGFYUnNaVHBUZEhKcGJtY29SeTVSVlVWU1dWOVFRVlJVUlZKT0tTeGphR2xzWkhKbGJqcFRkSEpwYm1jb1J5NVJWVVZTV1Y5UVFWUlVS'
    || 'VkpPS1gwcExHOHVhbk40Y3lnaWMzQmhiaUlzZTNOMGVXeGxPbGRsTG5CaGNuUnBZV3dzWTJocGJHUnlaVzQ2VzFrb1Zpa3NJaUJ2WmlBaUxGa29VU2tzSWlC'
    || 'bGVHVmpkWFJwYjI1eklHaGhaQ0J1YnlCMFpYaDBJSEpsZEdGcGJtVmtJbDE5S1YxOUtUcHZMbXB6ZUNnaVkyOWtaU0lzZTNOMGVXeGxPbGRsTG5CaGRIUmxj'
    || 'bTRzZEdsMGJHVTZVM1J5YVc1bktFY3VVVlZGVWxsZlVFRlVWRVZTVGlrc1kyaHBiR1J5Wlc0NlUzUnlhVzVuS0VjdVVWVkZVbGxmVUVGVVZFVlNUaWw5S1gx'
    || 'OVhYMHBMRVkvYnk1cWMzZ29TV01zZTI1aE9pSnhkV1Z5ZVNCMFpYaDBJSGRoY3lCdWIzUWdjbVYwWVdsdVpXUWdhVzRnVVZWRlVsbGZTRWxUVkU5U1dTQm1i'
    || 'M0lnZEdobGMyVWdaWGhsWTNWMGFXOXVjenNnWld4aGNITmxaQ0IwYVcxbElHRnVaQ0JqYjNWdWRDQmhjbVVnYzNScGJHd2dhMjV2ZDI0aWZTazZiblZzYkN4'
    || 'dkxtcHplQ2haYml4N1kyaHBiR1J5Wlc0NklpVWdiMllnVjBnZ2RHbHRaU0E5SUhGMVpYSjVJSEJoZEhSbGNtNGdaV3hoY0hObFpDQXZJSGRoY21Wb2IzVnpa'
    || 'U0IwYjNSaGJDQmxiR0Z3YzJWa0xpQlVhR2x6SUdseklHRWdkR2x0WlNCemFHRnlaU3dnYm05MElHRWdZM0psWkdsMElITm9ZWEpsTGlCVGJtOTNabXhoYTJV'
    || 'Z1pHOWxjeUJ1YjNRZ1pYaHdiM05sSUhCbGNpMXhkV1Z5ZVNCamNtVmthWFJ6SUdsdUlGRlZSVkpaWDBoSlUxUlBVbGt1SW4wcFhYMHBmU2tvS1gwcE9rOC9i'
    || 'eTVxYzNnb0luQWlMSHR6ZEhsc1pUcFhaUzVsYlhCMGVTeGphR2xzWkhKbGJqb2lUbThnY1hWbGNua2djR0YwZEdWeWJuTWdjbVZqYjNKa1pXUWdabTl5SUhS'
    || 'b2FYTWdkMkZ5WldodmRYTmxMaUo5S1RwdWRXeHNYWDBzVGk1dVlXMWxLWDBwTEY4K01EOXZMbXB6ZUhNb0ltUnBkaUlzZTNOMGVXeGxPbGRsTG5KbGMzUXNZ'
    || 'MmhwYkdSeVpXNDZXMWtvVFdGMGFDNXliM1Z1WkNoZktqRXdNQ2t2TVRBd0tTd2lJR055WldScGRITWdZV055YjNOeklISmxiV0ZwYm1sdVp5QjNZWEpsYUc5'
    || 'MWMyVnpJQ2dpTEV3dWRHOUdhWGhsWkNneEtTd2lKU0J2WmlCaFkyTnZkVzUwS1NKZGZTazZiblZzYkYxOUtWMTlLWDBwT204dWFuTjRLRVpsTEh0MGFYUnNa'
    || 'VG9pVjJobGNtVWdkR2hsSUdOeVpXUnBkSE1nWjI4c0lHRnVaQ0IzYUdGMElISjFibk1nZEdobGNtVWlMSGRwWkdVNklUQXNZMmhwYkdSeVpXNDZieTVxYzNn'
    || 'b1RHVXNlM0JoYm1Wc09uVXVjR0Z1Wld4ekxuZG9YMlJ5YVd4c0xHTm9hV3hrY21WdU9tOHVhbk40S0NKd0lpeDdZMnhoYzNOT1lXMWxPaUp3WVc1bGJDMWxi'
    || 'WEIwZVNJc1kyaHBiR1J5Wlc0NklrNXZJR1J5YVd4c0lIUnlaV1VnWkdGMFlTQmhkbUZwYkdGaWJHVXVJbjBwZlNsOUtYMW1kVzVqZEdsdmJpQnNaQ2g3Y0Rw'
    || 'MWZTbDdZMjl1YzNRZ1pEMVBaU2gxTENKellYWnBibWR6SWlrc1lUMWtMbVpwYkhSbGNpaDRQVDRoUzI0b2VDa3BMR2M5WkM1bWFXeDBaWElvUzI0cE8zSmxk'
    || 'SFZ5YmlCbkxtWnBiSFJsY2loNFBUNTRMbEpGVTA5VlVrTkZYMDFQVGtsVVQxSTlQVDBpSW54OGVDNVNSVk5QVlZKRFJWOU5UMDVKVkU5U1BUMDliblZzYkh4'
    || 'OGVDNVNSVk5QVlZKRFJWOU5UMDVKVkU5U1BUMDlJbTUxYkd3aUtTeHZMbXB6ZUNoR1pTeDdkR2wwYkdVNklsQmxjaUIzWVhKbGFHOTFjMlVpTEhkcFpHVTZJ'
    || 'VEFzYUdsdWREcGdSMFZPUlZKQlZFbFBUaUJpYkdGdWF5QnRaV0Z1Y3lCSFpXNHhMaUJYU0Y5VVdWQkZJR0pzWVc1cklHMWxZVzV6SUZOVVFVNUVRVkpFTGlC'
    || 'Q2IzUm9JR0Z5WlFvZ0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnY21WaFpDQm1jbTl0SUZOSVQxY2dWMEZTUlVoUFZWTkZVeUJoZENCaWRXbHNaQ0IwYVcxbExDQnVi'
    || 'M1FnWjNWbGMzTmxaQzVnTEdOb2FXeGtjbVZ1T204dWFuTjRjeWhNWlN4N2NHRnVaV3c2ZFM1d1lXNWxiSE11YzJGMmFXNW5jeXhqYUdsc1pISmxianBiWVM1'
    || 'c1pXNW5kR2crTUQ5dkxtcHplSE1vYnk1R2NtRm5iV1Z1ZEN4N1kyaHBiR1J5Wlc0NlcyOHVhbk40Y3lnaWFETWlMSHRqYkdGemMwNWhiV1U2SW5OMVlpSXNZ'
    || 'MmhwYkdSeVpXNDZXeUpYWVhKbGFHOTFjMlZ6SUhSb1lYUWdjbUZ1SUdSMWNtbHVaeUIwYUdVZ2QybHVaRzkzSU9LQWxDQWlMRmtvWVM1c1pXNW5kR2dwTENJ'
    || 'Z2IyWWdJaXhaS0dRdWJHVnVaM1JvS1YxOUtTeHZMbXB6ZUNoVGJpeDdjbTkzY3pwaExHMWhlRG95TlN4amIyeHpPbHQ3YTJWNU9pSlhRVkpGU0U5VlUwVmZU'
    || 'a0ZOUlNJc2JHRmlaV3c2SWxkaGNtVm9iM1Z6WlNKOUxIdHJaWGs2SWxkSVgxTkpXa1VpTEd4aFltVnNPaUpUYVhwbEluMHNlMnRsZVRvaVIwVk9SVkpCVkVs'
    || 'UFRpSXNiR0ZpWld3NklrZGxiaUlzY21WdVpHVnlPbmc5UG5nOVBUMGlJbng4ZUQwOVBXNTFiR3g4ZkhnOVBUMTJiMmxrSURBL2J5NXFjM2dvY200c2UzUnZi'
    || 'bVU2SW5kaGNtNGlMR05vYVd4a2NtVnVPaUl4SW4wcE9sTjBjbWx1WnloNEtYMHNlMnRsZVRvaVFWVlVUMTlUVlZOUVJVNUVYMU5GUTFNaUxHeGhZbVZzT2lK'
    || 'QmRYUnZMWE4xYzNBZ0tITXBJaXhoYkdsbmJqb2ljbWxuYUhRaWZTeDdhMlY1T2lKU1JWTlBWVkpEUlY5TlQwNUpWRTlTSWl4c1lXSmxiRG9pVFc5dWFYUnZj'
    || 'aUlzY21WdVpHVnlPbmc5UG5nOVBUMGlJbng4ZUQwOVBXNTFiR3g4ZkhnOVBUMGliblZzYkNJL2J5NXFjM2dvY200c2UzUnZibVU2SW5kaGNtNGlMR05vYVd4'
    || 'a2NtVnVPaUp1YjI1bEluMHBPbE4wY21sdVp5aDRLWDBzZTJ0bGVUb2lRMUpGUkVsVVUxOVZVMFZFSWl4c1lXSmxiRG9pUTNKbFpHbDBjeUlzWVd4cFoyNDZJ'
    || 'bkpwWjJoMEluMHNlMnRsZVRvaVFWWkhYMUpGVTFWTlJWTmZVRVZTWDBSQldTSXNiR0ZpWld3NklsSmxjM1Z0WlhNdlpHRjVJaXhoYkdsbmJqb2ljbWxuYUhR'
    || 'aWZTeDdhMlY1T2lKU1JVTlBUVTFGVGtSQlZFbFBUaUlzYkdGaVpXdzZJbEpsWTI5dGJXVnVaR0YwYVc5dUlpeHlaVzVrWlhJNmVEMCtieTVxYzNnb2NtNHNl'
    || 'M1J2Ym1VNlltTmJVM1J5YVc1bktIZ3BYVDgvSW5kaGNtNGlMR05vYVd4a2NtVnVPbE4wY21sdVp5aDRLWDBwZlN4N2EyVjVPaUpGVTFSZlUwRldTVTVIVTE5'
    || 'RFVrVkVTVlJUSWl4c1lXSmxiRG9pVTJGMmFXNW5JR0YwSUcxdmMzUWlMR0ZzYVdkdU9pSnlhV2RvZENKOVhYMHBYWDBwT204dWFuTjRLQ0p3SWl4N1kyeGhj'
    || 'M05PWVcxbE9pSnViM1JsSWl4amFHbHNaSEpsYmpvaVRtOGdkMkZ5WldodmRYTmxJR2x1SUhSb2FYTWdZV05qYjNWdWRDQnlZVzRnWVc1NWRHaHBibWNnWkhW'
    || 'eWFXNW5JSFJvWlNCM2FXNWtiM2NzSUhOdklIUm9aWEpsSUdseklHNXZkR2hwYm1jZ2FHVnlaU0IwYnlCMGRXNWxMaUo5S1N4bkxteGxibWQwYUQ0d1AyOHVh'
    || 'bk40Y3loWmJpeDdZMmhwYkdSeVpXNDZXMWtvWnk1c1pXNW5kR2dwTENJZ2FXUnNaU0IzWVhKbGFHOTFjMlVpTEdjdWJHVnVaM1JvUFQwOU1UOGlJam9pY3lJ'
    || 'c0lpQmxlR05zZFdSbFpDQm1jbTl0SUhKbFkyOXRiV1Z1WkdGMGFXOXVjeUJpZFhRZ2FXNWpiSFZrWldRZ2FXNGdkR2hsSUNJc1dTaGtMbXhsYm1kMGFDa3NJ'
    || 'aUJwYm5abGJuUnZjbmtnWTI5MWJuUXVJbDE5S1RwdWRXeHNYWDBwZlNsOVpuVnVZM1JwYjI0Z2FXUW9lM0E2ZFgwcGUyTnZibk4wSUdROVQyVW9kU3dpWkdG'
    || 'cGJIbGZZM0psWkdsMGN5SXBMR0U5WkM1dFlYQW9lRDArY1NoNExrTlNSVVJKVkZOZlZWTkZSQ2twTEdjOVlTNXlaV1IxWTJVb0tIZ3NReWs5UG5nclF5d3dL'
    || 'VHR5WlhSMWNtNGdieTVxYzNnb1JtVXNlM1JwZEd4bE9pSkRjbVZrYVhRZ1kyOXVjM1Z0Y0hScGIyNGdiM1psY2lCMGFXMWxJaXhvYVc1ME9tQlBibVVnY0c5'
    || 'cGJuUWdjR1Z5SUdSaGVTd2djM1Z0YldWa0lHRmpjbTl6Y3lCaGJHd2dkMkZ5WldodmRYTmxjeTRnVkdobElITm9ZWEJsSUcxaGRIUmxjbk1nYlc5eVpRb2dJ'
    || 'Q0FnSUNBZ0lDQWdJQ0FnSUNBZ2RHaGhiaUIwYUdVZ1lXSnpiMngxZEdVZ2RtRnNkV1U2SUdFZ2NtbHphVzVuSUhSaGFXd2diV1ZoYm5NZ2MyOXRaWFJvYVc1'
    || 'bklHNWxkeUJwY3lCeWRXNXVhVzVuTG1Bc1kyaHBiR1J5Wlc0NmJ5NXFjM2h6S0V4bExIdHdZVzVsYkRwMUxuQmhibVZzY3k1a1lXbHNlVjlqY21Wa2FYUnpM'
    || 'R05vYVd4a2NtVnVPbHR2TG1wemVITW9JbVJwZGlJc2UyTnNZWE56VG1GdFpUb2ljM1JoZEMxeWIzY2lMR05vYVd4a2NtVnVPbHR2TG1wemVDaERkQ3g3YkdG'
    || 'aVpXdzZJa1JoZVhNZ2MyaHZkMjRpTEhaaGJIVmxPbVF1YkdWdVozUm9mU2tzYnk1cWMzZ29RM1FzZTJ4aFltVnNPaUpVYjNSaGJDQmpjbVZrYVhSeklpeDJZ'
    || 'V3gxWlRwWktFMWhkR2d1Y205MWJtUW9aeWtwTEhOMVlqb2lZV055YjNOeklHRnNiQ0IzWVhKbGFHOTFjMlZ6TENCaGJHd2daR0Y1Y3lKOUtTeHZMbXB6ZUNo'
    || 'RGRDeDdiR0ZpWld3NklrUmhhV3g1SUdGMlpYSmhaMlVpTEhaaGJIVmxPbVF1YkdWdVozUm9QMWtvVFdGMGFDNXliM1Z1WkNobkwyUXViR1Z1WjNSb0tTazZJ'
    || 'dUtBbENJc2RXNXBkRG9pSUdOeUlpeHpkV0k2SW0xbFlXNGdiM1psY2lCMGFHVWdkMmx1Wkc5M0luMHBYWDBwTEc4dWFuTjRLRmRqTEh0d2IybHVkSE02WVN4'
    || 'M2FXUjBhRG8xTkRBc2FHVnBaMmgwT2pVMGZTbGRmU2w5S1gxbWRXNWpkR2x2YmlCdlpDaDdjRHAxZlNsN1kyOXVjM1FnWkQxUFpTaDFMQ0p6Y0dWdVpDSXBM'
    || 'R0U5WkM1eVpXUjFZMlVvS0V3c1RpazlQa3dyY1NoT0xrTlNSVVJKVkZOZlZWTkZSQ2tzTUNrc1p6MHVNREVzZUQxa0xtWnBiSFJsY2loTVBUNWhQRDB3Zkh4'
    || 'eEtFd3VRMUpGUkVsVVUxOVZVMFZFS1M5aFBqMW5LU3hEUFdRdVptbHNkR1Z5S0V3OVBpRW9ZVHc5TUh4OGNTaE1Ma05TUlVSSlZGTmZWVk5GUkNrdllUNDla'
    || 'eWtwTEZNOVF5NXlaV1IxWTJVb0tFd3NUaWs5UGt3cmNTaE9Ma05TUlVSSlZGTmZWVk5GUkNrc01Da3NkejFrTG5KbFpIVmpaU2dvVEN4T0tUMCtjU2hPTGtO'
    || 'U1JVUkpWRk5mVlZORlJDaytjU2hNTGtOU1JVUkpWRk5mVlZORlJDay9UanBNTEdSYk1GMC9QM3Q5S1N4ZlBXRStNRDl4S0hjOVBXNTFiR3cvZG05cFpDQXdP'
    || 'bmN1UTFKRlJFbFVVMTlWVTBWRUtTOWhLakV3TURvd08zSmxkSFZ5YmlCdkxtcHplQ2hHWlN4N2RHbDBiR1U2SWtOeVpXUnBkQ0JrYVhOMGNtbGlkWFJwYjI0'
    || 'aUxHaHBiblE2WUVOdmJYQjFkR1VnWVc1a0lHTnNiM1ZrSUhObGNuWnBZMlZ6SUhObGNHRnlZWFJsWkN3Z1ltVmpZWFZ6WlNCaElIZGhjbVZvYjNWelpTQjNh'
    || 'Rzl6WlNCamIzTjBJR2x6Q2lBZ0lDQWdJQ0FnSUNBZ0lDQWdJQ0J0YjNOMGJIa2dZMnh2ZFdRZ2MyVnlkbWxqWlhNZ2JtVmxaSE1nWVNCa2FXWm1aWEpsYm5R'
    || 'Z1ptbDRMbUFzWTJocGJHUnlaVzQ2Ynk1cWMzaHpLRXhsTEh0d1lXNWxiRHAxTG5CaGJtVnNjeTV6Y0dWdVpDeGphR2xzWkhKbGJqcGJaQzVzWlc1bmRHZytN'
    || 'Q1ltWVQ0d1AyOHVhbk40Y3lnaWNDSXNlMk5zWVhOelRtRnRaVG9pYm05MFpTSXNZMmhwYkdSeVpXNDZXMjh1YW5ONEtDSnpkSEp2Ym1jaUxIdGphR2xzWkhK'
    || 'bGJqcFRkSEpwYm1jb0tIYzlQVzUxYkd3L2RtOXBaQ0F3T25jdVYwRlNSVWhQVlZORlgwNUJUVVVwUHo4aTRvQ1VJaWw5S1N3aU9pQWlMRjh1ZEc5R2FYaGxa'
    || 'Q2d4S1N3aUpTQnZaaUFpTEZrb1RXRjBhQzV5YjNWdVpDaGhLU2tzSWlCamNtVmthWFJ6TGlCVGRHRnlkQ0JvWlhKbExpSmRmU2s2Ym5Wc2JDeHZMbXB6ZUNo'
    || 'MWN5eDdiV0Y0T2pFeUxIVnVhWFE2SWlCamNpSXNaR0YwWVRwNExtMWhjQ2hNUFQ0b2UyeGhZbVZzT2xOMGNtbHVaeWhNTGxkQlVrVklUMVZUUlY5T1FVMUZL'
    || 'U3gyWVd4MVpUcHhLRXd1UTFKRlJFbFVVMTlWVTBWRUtYMHBLWDBwTEVNdWJHVnVaM1JvUGpBL2J5NXFjM2h6S0NKd0lpeDdZMnhoYzNOT1lXMWxPaUowWVdK'
    || 'c1pTMXRiM0psSWl4amFHbHNaSEpsYmpwYldTaERMbXhsYm1kMGFDa3NJaUJtZFhKMGFHVnlJSGRoY21Wb2IzVnpaU0lzUXk1c1pXNW5kR2c5UFQweFB5SWlP'
    || 'aUp6SWl3aUlIVnVaR1Z5SURFbElHOW1JSFJ2ZEdGc0lITndaVzVrTENBaUxGa29UV0YwYUM1eWIzVnVaQ2hUS2pFd01Da3ZNVEF3S1N3aUlHTnlaV1JwZEhN'
    || 'Z1kyOXRZbWx1WldRdUlsMTlLVHB1ZFd4c1hYMHBmU2w5Wm5WdVkzUnBiMjRnYzJRb2UzQTZkWDBwZTJOdmJuTjBJR1E5VDJVb2RTd2lZMmgxY200aUtUdHla'
    || 'WFIxY200Z2J5NXFjM2dvUm1Vc2UzUnBkR3hsT2lKU1pYTjFiV1VnWTJoMWNtNGlMR2hwYm5RNllFRWdkMkZ5WldodmRYTmxJSEpsYzNWdGFXNW5JR1J2ZW1W'
    || 'dWN5QnZaaUIwYVcxbGN5QmhJR1JoZVNCd1lYbHpJSFJvWlNCdGFXNXBiWFZ0SUdKcGJHeHBibWNLSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJR2x1WTNKbGJXVnVk'
    || 'Q0JsWVdOb0lIUnBiV1V1SUZSb2FYTWdhWE1nZEdobElFRmtZWEIwYVhabElFTnZiWEIxZEdVZ2MybG5ibUZzTG1Bc1kyaHBiR1J5Wlc0NmJ5NXFjM2dvVEdV'
    || 'c2UzQmhibVZzT25VdWNHRnVaV3h6TG1Ob2RYSnVMR05vYVd4a2NtVnVPbTh1YW5ONEtIVnpMSHR0WVhnNk1USXNkVzVwZERvaUwyUmhlU0lzWkdGMFlUcGtM'
    || 'bTFoY0NoaFBUNG9lMnhoWW1Wc09sTjBjbWx1WnloaExsZEJVa1ZJVDFWVFJWOU9RVTFGS1N4MllXeDFaVHB4S0dFdVVrVlRWVTFGVTE5UVJWSmZSRUZaS1N4'
    || 'MGIyNWxPbkVvWVM1U1JWTlZUVVZUWDFCRlVsOUVRVmtwUGpVL0ltSmhaQ0k2ZG05cFpDQXdmU2twZlNsOUtYMHBmV1oxYm1OMGFXOXVJSFZrS0h0d09uVjlL'
    || 'WHRqYjI1emRDQmtQVTlsS0hVc0luQnlaWE56ZFhKbElpazdjbVYwZFhKdUlHOHVhbk40S0VabExIdDBhWFJzWlRvaVVYVmxkV1ZwYm1jZ1lXNWtJSE53YVd4'
    || 'c0lPS0FsQ0IwYUdVZ1kyOTFiblJsY2kxbGRtbGtaVzVqWlNJc2QybGtaVG9oTUN4b2FXNTBPbUJTWldGa0lIUm9hWE1nUWtWR1QxSkZJSE5vY21sdWEybHVa'
    || 'eUJoYm5sMGFHbHVaeTRnUVNCM1lYSmxhRzkxYzJVZ2RHaGhkQ0J4ZFdWMVpYTWdiM0lnYzNCcGJHeHpDaUFnSUNBZ0lDQWdJQ0FnSUNBZ0lDQjBieUJ5Wlcx'
    || 'dmRHVWdjM1J2Y21GblpTQnBjeUJoYkhKbFlXUjVJSFJ2YnlCemJXRnNiQ3dnWVc1a0lHTjFkSFJwYm1jZ2FYUWdablZ5ZEdobGNpQjBkWEp1Y3lCaENpQWdJ'
    || 'Q0FnSUNBZ0lDQWdJQ0FnSUNCamIzTjBJSE5oZG1sdVp5QnBiblJ2SUdFZ2MyeHZkMlZ5SUhCcGNHVnNhVzVsTG1Bc1kyaHBiR1J5Wlc0NmJ5NXFjM2dvVEdV'
    || 'c2UzQmhibVZzT25VdWNHRnVaV3h6TG5CeVpYTnpkWEpsTEdOb2FXeGtjbVZ1T204dWFuTjRLRk51TEh0eWIzZHpPbVFzYldGNE9qRTFMR052YkhNNlczdHJa'
    || 'WGs2SWxkQlVrVklUMVZUUlY5T1FVMUZJaXhzWVdKbGJEb2lWMkZ5WldodmRYTmxJbjBzZTJ0bGVUb2lVVlZGVWtsRlV5SXNiR0ZpWld3NklsRjFaWEpwWlhN'
    || 'aUxHRnNhV2R1T2lKeWFXZG9kQ0o5TEh0clpYazZJbEZWUlZWRlJGOVRSVU5QVGtSVElpeHNZV0psYkRvaVVYVmxkV1ZrSUNoektTSXNZV3hwWjI0NkluSnBa'
    || 'MmgwSW4wc2UydGxlVG9pVTFCSlRFeGZURTlEUVV4ZlIwSWlMR3hoWW1Wc09pSlRjR2xzYkNCc2IyTmhiQ0FvUjBJcElpeGhiR2xuYmpvaWNtbG5hSFFpZlN4'
    || 'N2EyVjVPaUpUVUVsTVRGOVNSVTFQVkVWZlIwSWlMR3hoWW1Wc09pSlRjR2xzYkNCeVpXMXZkR1VnS0VkQ0tTSXNZV3hwWjI0NkluSnBaMmgwSWl4eVpXNWta'
    || 'WEk2WVQwK2NTaGhLVDR3UDI4dWFuTjRLSEp1TEh0MGIyNWxPaUppWVdRaUxHTm9hV3hrY21WdU9sa29ZU2w5S1RwWktHRXBmVjE5S1gwcGZTbDlablZ1WTNS'
    || 'cGIyNGdZV1FvZTNBNmRYMHBlMk52Ym5OMElHUTlUMlVvZFN3aWNISnZhbVZqZEdsdmJuTWlLU3hoUFdRdVptbHNkR1Z5S0djOVBtY3VUVVZCVTFWU1JVUmZV'
    || 'MEZXU1U1SFUxOURVa1ZFU1ZSVElUMDliblZzYkNZbVp5NU5SVUZUVlZKRlJGOVRRVlpKVGtkVFgwTlNSVVJKVkZNaFBUMTJiMmxrSURBcExteGxibWQwYUR0'
    || 'eVpYUjFjbTRnYnk1cWMzZ29SbVVzZTNScGRHeGxPaUpRY205cVpXTjBaV1FnZG5NZ2JXVmhjM1Z5WldRaUxIZHBaR1U2SVRBc2FHbHVkRHBnVkdobElHMWxZ'
    || 'WE4xY21Wa0lHTnZiSFZ0YmlCemRHRjVjeUJsYlhCMGVTQjFiblJwYkNCemIyMWxiMjVsSUdGd2NHeHBaWE1nWVNCamFHRnVaMlVnWVc1a0NpQWdJQ0FnSUNB'
    || 'Z0lDQWdJQ0FnSUNCeVpXTnZjbVJ6SUhSb1pTQnZkWFJqYjIxbExpQlVhR0YwSUdseklIUm9aU0J3YjJsdWRDQnZaaUIwYUdVZ2RHRmliR1U2SUdsMElHMWhh'
    || 'MlZ6SUhSb1pTQm5ZWEFLSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJR0psZEhkbFpXNGdZU0J3Y205cVpXTjBhVzl1SUdGdVpDQmhJSEpsYzNWc2RDQjJhWE5wWW14'
    || 'bElHbHVjM1JsWVdRZ2IyWWdiR1YwZEdsdVp5QjBhR1VLSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJSEJ5YjJwbFkzUnBiMjRnWW1WamIyMWxJSFJvWlNCemRHOXll'
    || 'UzVnTEdOb2FXeGtjbVZ1T204dWFuTjRjeWhNWlN4N2NHRnVaV3c2ZFM1d1lXNWxiSE11Y0hKdmFtVmpkR2x2Ym5Nc1kyaHBiR1J5Wlc0NlcyOHVhbk40Y3ln'
    || 'aVpHbDJJaXg3WTJ4aGMzTk9ZVzFsT2lKemRHRjBMWEp2ZHlJc1kyaHBiR1J5Wlc0NlcyOHVhbk40S0VOMExIdHNZV0psYkRvaVVISnZhbVZqZEdsdmJuTWdj'
    || 'bVZqYjNKa1pXUWlMSFpoYkhWbE9tUXViR1Z1WjNSb2ZTa3NieTVxYzNnb1EzUXNlMnhoWW1Wc09pSk5aV0Z6ZFhKbFpDQnpieUJtWVhJaUxIWmhiSFZsT21F'
    || 'c2RHOXVaVHBoUHlKbmIyOWtJam9pZDJGeWJpSXNjM1ZpT21FL2RtOXBaQ0F3T2lKdWIzUm9hVzVuSUdGd2NHeHBaV1FnWVc1a0lHMWxZWE4xY21Wa0lIbGxk'
    || 'Q0o5S1YxOUtTeHZMbXB6ZUNoVGJpeDdjbTkzY3pwa0xHMWhlRG95TlN4amIyeHpPbHQ3YTJWNU9pSlhRVkpGU0U5VlUwVmZUa0ZOUlNJc2JHRmlaV3c2SWxk'
    || 'aGNtVm9iM1Z6WlNKOUxIdHJaWGs2SWxKRlEwOU5UVVZPUkVGVVNVOU9JaXhzWVdKbGJEb2lVbVZqYjIxdFpXNWtZWFJwYjI0aWZTeDdhMlY1T2lKUVVrOUtS'
    || 'VU5VUlVSZlUwRldTVTVIVTE5RFVrVkVTVlJUSWl4c1lXSmxiRG9pVUhKdmFtVmpkR1ZrSWl4aGJHbG5iam9pY21sbmFIUWlmU3g3YTJWNU9pSk5SVUZUVlZK'
    || 'RlJGOVRRVlpKVGtkVFgwTlNSVVJKVkZNaUxHeGhZbVZzT2lKTlpXRnpkWEpsWkNJc1lXeHBaMjQ2SW5KcFoyaDBJaXh5Wlc1a1pYSTZaejArWnowOWJuVnNi'
    || 'RDl2TG1wemVDaHliaXg3ZEc5dVpUb2lkMkZ5YmlJc1kyaHBiR1J5Wlc0NkltNXZkQ0J0WldGemRYSmxaQ0o5S1RwWktHY3BmU3g3YTJWNU9pSkJVRkJNU1VW'
    || 'RVgwRlVJaXhzWVdKbGJEb2lRWEJ3YkdsbFpDSjlYWDBwWFgwcGZTbDlablZ1WTNScGIyNGdZMlFvZTNBNmRYMHBlMk52Ym5OMElHUTlXM3RwWkRvaWMzQmxi'
    || 'bVFpTEd4aFltVnNPaUpUY0dWdVpDQmhibVFnYzJGMmFXNW5jeUlzWkdWell6b2lRM0psWkdsMGN5d2dZMjl1WTJWdWRISmhkR2x2Yml3Z2NISnZhbVZqZEds'
    || 'dmJuTWlMR2xqYjI0NkltOTJaWEoyYVdWM0lpeHdZVzVsYkhNNld5SnpZWFpwYm1keklpd2ljM0JsYm1RaUxDSmtZV2xzZVY5amNtVmthWFJ6SWl3aWQyaGZa'
    || 'SEpwYkd3aUxDSmphSFZ5YmlKZExISmxibVJsY2pvb0tUMCtieTVxYzNoektHOHVSbkpoWjIxbGJuUXNlMk5vYVd4a2NtVnVPbHR2TG1wemVDaGxaQ3g3Y0Rw'
    || 'MWZTa3NieTVxYzNnb2RHUXNlM0E2ZFgwcExHOHVhbk40S0c1a0xIdHdPblY5S1N4dkxtcHplQ2h5WkN4N2NEcDFmU2tzYnk1cWMzZ29hV1FzZTNBNmRYMHBM'
    || 'Rzh1YW5ONEtHOWtMSHR3T25WOUtWMTlLWDBzZTJsa09pSnlaV052SWl4c1lXSmxiRG9pVW1WamIyMXRaVzVrWVhScGIyNXpJaXhrWlhOak9pSlhhR0YwSUhS'
    || 'dklHTm9ZVzVuWlNJc2FXTnZiam9pYzNCaGNtc2lMSEJoYm1Wc2N6cGJJbk5oZG1sdVozTWlYU3h5Wlc1a1pYSTZLQ2s5UG04dWFuTjRLR3hrTEh0d09uVjlL'
    || 'WDBzZTJsa09pSmphSFZ5YmlJc2JHRmlaV3c2SWxOMWMzQmxibVFnWTJoMWNtNGlMR1JsYzJNNklsSmxjM1Z0WlNCamVXTnNaWE1pTEdsamIyNDZJbU5zYjJO'
    || 'cklpeHdZVzVsYkhNNld5SmphSFZ5YmlKZExISmxibVJsY2pvb0tUMCtieTVxYzNnb2MyUXNlM0E2ZFgwcGZTeDdhV1E2SW5CeVpYTnpkWEpsSWl4c1lXSmxi'
    || 'RG9pVUhKbGMzTjFjbVVpTEdSbGMyTTZJbEYxWlhWbGFXNW5JR0Z1WkNCemNHbHNiQ0lzYVdOdmJqb2lkMkZ5YmlJc2NHRnVaV3h6T2xzaWNISmxjM04xY21V'
    || 'aVhTeHlaVzVrWlhJNktDazlQbTh1YW5ONEtIVmtMSHR3T25WOUtYMHNlMmxrT2lKd2NtOXFaV04wYVc5dWN5SXNiR0ZpWld3NklsQnliMnBsWTNSbFpDQnpZ'
    || 'WFpwYm1keklpeGtaWE5qT2lKUVpYSWdkMkZ5WldodmRYTmxJaXhwWTI5dU9pSnRiMjVsZVNJc2NHRnVaV3h6T2xzaWNISnZhbVZqZEdsdmJuTWlYU3h5Wlc1'
    || 'a1pYSTZLQ2s5UG04dWFuTjRLR0ZrTEh0d09uVjlLWDBzZTJsa09pSmhZM1JwYjI1eklpeHNZV0psYkRvaVYyaGhkQ0IwYUdseklHTmhiaUJrYnlJc1pHVnpZ'
    || 'em9pUVdOMGFXOXVjeUJoYm1RZ2FHbHpkRzl5ZVNJc2FXTnZiam9pWm14dmR5SXNjR0Z1Wld4ek9sc2lZV04wYVc5dWN5SXNJbUZqZEdsdmJsOXNiMmNpWFN4'
    || 'eVpXNWtaWEk2S0NrOVBtOHVhbk40Y3lodkxrWnlZV2R0Wlc1MExIdGphR2xzWkhKbGJqcGJieTVxYzNnb1JtVXNlM1JwZEd4bE9pSkJkbUZwYkdGaWJHVWdZ'
    || 'V04wYVc5dWN5SXNkMmxrWlRvaE1DeG9hVzUwT21CRllXTm9JR0ZqZEdsdmJpQnBjeUJoSUdOb1lXNW5aU0IwYUdseklITnZiSFYwYVc5dUlHTmhiaUJ0WVd0'
    || 'bElIUnZJSGx2ZFhJZ1lXTmpiM1Z1ZEM0Z1ZHaGxDaUFnSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnSUNCaWRYUjBiMjV6SUdGeVpTQmlaV3h2ZHlCMGFHVWda'
    || 'R0Z6YUdKdllYSmtJR2x1SUhSb1pTQlRkSEpsWVcxc2FYUWdhRzl6ZEM1Z0xHTm9hV3hrY21WdU9tOHVhbk40S0V4bExIdHdZVzVsYkRwMUxuQmhibVZzY3k1'
    || 'aFkzUnBiMjV6TEc1dmRFSjFhV3gwUW14dlkyczZieTVxYzNnb2VtTXNlM05sZEhScGJtYzZJa05QVTFSRlJrWmZRVXhNVDFkZlFVTlVTVTlPVXlKOUtTeGph'
    || 'R2xzWkhKbGJqcHZMbXB6ZUNoQll5eDdZV04wYVc5dWN6cFBaU2gxTENKaFkzUnBiMjV6SWlsOUtYMHBmU2tzYnk1cWMzZ29SbVVzZTNScGRHeGxPaUpTWldO'
    || 'bGJuUWdjblZ1Y3lJc2QybGtaVG9oTUN4b2FXNTBPaUpVYUdVZ2JHRnpkQ0JoWTNScGIyNXpJR1Y0WldOMWRHVmtJRzl5SUhWdVpHOXVaU3dnZDJsMGFDQjBh'
    || 'VzFsYzNSaGJYQnpJR0Z1WkNCemRHRjBkWE11SWl4amFHbHNaSEpsYmpwdkxtcHplQ2hNWlN4N2NHRnVaV3c2ZFM1d1lXNWxiSE11WVdOMGFXOXVYMnh2Wnl4'
    || 'M2FHVnVUV2x6YzJsdVp6b2lUbThnWVdOMGFXOXVJR3h2WnlCbGVHbHpkSE1nZVdWMElPS0FsQ0J1YjNSb2FXNW5JR2hoY3lCaVpXVnVJSEoxYmk0aUxHTm9h'
    || 'V3hrY21WdU9tOHVhbk40S0ZWakxIdHNiMmM2VDJVb2RTd2lZV04wYVc5dVgyeHZaeUlwZlNsOUtYMHBYWDBwZlYwN2NtVjBkWEp1SUc4dWFuTjRLRWRqTEh0'
    || 'd1lYbHNiMkZrT25Vc2MzVmlkR2wwYkdVNklsZGhjbVZvYjNWelpTQmpiM04wSWl4elpXTjBhVzl1Y3pwa2ZTbDljV01vZFQwK2J5NXFjM2dvWTJRc2UzQTZk'
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
    || 'YjNkeVlYQTdjR0ZrWkdsdVp6b3dJRFJ3ZUgwSyIKU09MVVRJT05fTkFNRSA9ICJXYXJlaG91c2UgQ29zdCBFZmZpY2llbmN5IgpHTE9CQUxfTkFNRSA9ICJf'
    || 'X0NPU1RFRkZfREFUQV9fIgpBUFBfT0JKRUNUID0gIkNPU1RFRkZfQVBQIgoKaW1wb3J0IGpzb24KaW1wb3J0IHJlCgoKZGVmIHZhbGlkYXRlX2N1c3RvbWl6'
    || 'YXRpb24ocmF3KToKICAgIGlmIGlzaW5zdGFuY2UocmF3LCBzdHIpOgogICAgICAgIHJhdyA9IGpzb24ubG9hZHMocmF3KQogICAgaWYgbm90IGlzaW5zdGFu'
    || 'Y2UocmF3LCBkaWN0KToKICAgICAgICByYWlzZSBWYWx1ZUVycm9yKCJDdXN0b21pemF0aW9uIG11c3QgYmUgYSBKU09OIG9iamVjdCIpCiAgICBhbGxvd2Vk'
    || 'ID0geyJ2ZXJzaW9uIiwgInRpdGxlIiwgImRlZmF1bHRfc2VjdGlvbiIsICJzZWN0aW9uX2xhYmVscyIsICJzZWN0aW9uX29yZGVyIiwgInBhbmVscyJ9CiAg'
    || 'ICB1bmtub3duID0gc2V0KHJhdykgLSBhbGxvd2VkCiAgICBpZiB1bmtub3duOgogICAgICAgIHJhaXNlIFZhbHVlRXJyb3IoIlVua25vd24gY3VzdG9taXph'
    || 'dGlvbiBrZXlzOiAiICsgIiwgIi5qb2luKHNvcnRlZCh1bmtub3duKSkpCiAgICBpZiByYXcuZ2V0KCJ2ZXJzaW9uIiwgMSkgIT0gMToKICAgICAgICByYWlz'
    || 'ZSBWYWx1ZUVycm9yKCJPbmx5IGN1c3RvbWl6YXRpb24gdmVyc2lvbiAxIGlzIHN1cHBvcnRlZCIpCgogICAgZGVmIHRleHQodmFsdWUsIGxpbWl0KToKICAg'
    || 'ICAgICBpZiBub3QgaXNpbnN0YW5jZSh2YWx1ZSwgc3RyKSBvciBub3QgdmFsdWUuc3RyaXAoKSBvciBsZW4odmFsdWUpID4gbGltaXQ6CiAgICAgICAgICAg'
    || 'IHJhaXNlIFZhbHVlRXJyb3IoIkV4cGVjdGVkIG5vbmVtcHR5IHRleHQgb2YgYXQgbW9zdCAiICsgc3RyKGxpbWl0KSArICIgY2hhcmFjdGVycyIpCiAgICAg'
    || 'ICAgcmV0dXJuIHZhbHVlCgogICAgZGVmIHNlY3Rpb24odmFsdWUpOgogICAgICAgIHZhbHVlID0gdGV4dCh2YWx1ZSwgODApCiAgICAgICAgaWYgbm90IHJl'
    || 'LmZ1bGxtYXRjaChyIlthLXpdW2EtejAtOV9dKiIsIHZhbHVlKToKICAgICAgICAgICAgcmFpc2UgVmFsdWVFcnJvcigiSW52YWxpZCBzZWN0aW9uIElEOiAi'
    || 'ICsgdmFsdWUpCiAgICAgICAgcmV0dXJuIHZhbHVlCgogICAgcmVzdWx0ID0geyJ2ZXJzaW9uIjogMSwgInNlY3Rpb25fbGFiZWxzIjoge30sICJzZWN0aW9u'
    || 'X29yZGVyIjogW10sICJwYW5lbHMiOiBbXX0KICAgIGlmICJ0aXRsZSIgaW4gcmF3OgogICAgICAgIHJlc3VsdFsidGl0bGUiXSA9IHRleHQocmF3WyJ0aXRs'
    || 'ZSJdLCAxMjApCiAgICBpZiAiZGVmYXVsdF9zZWN0aW9uIiBpbiByYXc6CiAgICAgICAgcmVzdWx0WyJkZWZhdWx0X3NlY3Rpb24iXSA9IHNlY3Rpb24ocmF3'
    || 'WyJkZWZhdWx0X3NlY3Rpb24iXSkKICAgIGxhYmVscyA9IHJhdy5nZXQoInNlY3Rpb25fbGFiZWxzIiwge30pCiAgICBpZiBub3QgaXNpbnN0YW5jZShsYWJl'
    || 'bHMsIGRpY3QpIG9yIGxlbihsYWJlbHMpID4gMzA6CiAgICAgICAgcmFpc2UgVmFsdWVFcnJvcigic2VjdGlvbl9sYWJlbHMgbXVzdCBjb250YWluIGF0IG1v'
    || 'c3QgMzAgZW50cmllcyIpCiAgICBmb3Iga2V5LCB2YWx1ZSBpbiBsYWJlbHMuaXRlbXMoKToKICAgICAgICBrZXkgPSBzZWN0aW9uKGtleSkKICAgICAgICBp'
    || 'ZiBrZXkgPT0gInBvY19zdWNjZXNzIjoKICAgICAgICAgICAgcmFpc2UgVmFsdWVFcnJvcigiUE9DIHN1Y2Nlc3MgY2Fubm90IGJlIHJlbmFtZWQiKQogICAg'
    || 'ICAgIHJlc3VsdFsic2VjdGlvbl9sYWJlbHMiXVtrZXldID0gdGV4dCh2YWx1ZSwgODApCiAgICBvcmRlciA9IHJhdy5nZXQoInNlY3Rpb25fb3JkZXIiLCBb'
    || 'XSkKICAgIGlmIG5vdCBpc2luc3RhbmNlKG9yZGVyLCBsaXN0KSBvciBsZW4ob3JkZXIpID4gMzA6CiAgICAgICAgcmFpc2UgVmFsdWVFcnJvcigic2VjdGlv'
    || 'bl9vcmRlciBtdXN0IGJlIGEgbGlzdCBvZiBhdCBtb3N0IDMwIHNlY3Rpb24gSURzIikKICAgIHJlc3VsdFsic2VjdGlvbl9vcmRlciJdID0gW3NlY3Rpb24o'
    || 'dmFsdWUpIGZvciB2YWx1ZSBpbiBvcmRlcl0KICAgIGlmIGxlbihzZXQocmVzdWx0WyJzZWN0aW9uX29yZGVyIl0pKSAhPSBsZW4ob3JkZXIpOgogICAgICAg'
    || 'IHJhaXNlIFZhbHVlRXJyb3IoInNlY3Rpb25fb3JkZXIgY29udGFpbnMgZHVwbGljYXRlcyIpCiAgICBwYW5lbHMgPSByYXcuZ2V0KCJwYW5lbHMiLCBbXSkK'
    || 'ICAgIGlmIG5vdCBpc2luc3RhbmNlKHBhbmVscywgbGlzdCkgb3IgbGVuKHBhbmVscykgPiA2OgogICAgICAgIHJhaXNlIFZhbHVlRXJyb3IoIkF0IG1vc3Qg'
    || 'c2l4IGN1c3RvbSBwYW5lbHMgYXJlIHN1cHBvcnRlZCIpCiAgICB1c2VkID0gc2V0KCkKICAgIGZvciBwYW5lbCBpbiBwYW5lbHM6CiAgICAgICAgaWYgbm90'
    || 'IGlzaW5zdGFuY2UocGFuZWwsIGRpY3QpIG9yIHNldChwYW5lbCkgLSB7ImlkIiwgInRpdGxlIiwgInZpZXciLCAia2luZCIsICJsaW1pdCJ9OgogICAgICAg'
    || 'ICAgICByYWlzZSBWYWx1ZUVycm9yKCJJbnZhbGlkIHBhbmVsIGZpZWxkcyIpCiAgICAgICAgcGFuZWxfaWQgPSBzZWN0aW9uKHBhbmVsLmdldCgiaWQiKSkK'
    || 'ICAgICAgICBpZiBub3QgcGFuZWxfaWQuc3RhcnRzd2l0aCgiY3VzdG9tXyIpIG9yIHBhbmVsX2lkIGluIHVzZWQ6CiAgICAgICAgICAgIHJhaXNlIFZhbHVl'
    || 'RXJyb3IoIlBhbmVsIElEcyBtdXN0IGJlIHVuaXF1ZSBhbmQgc3RhcnQgd2l0aCBjdXN0b21fIikKICAgICAgICB1c2VkLmFkZChwYW5lbF9pZCkKICAgICAg'
    || 'ICB2aWV3ID0gdGV4dChwYW5lbC5nZXQoInZpZXciKSwgMTI4KQogICAgICAgIGlmIG5vdCByZS5mdWxsbWF0Y2gociJWX0NVU1RPTV9bQS1aMC05X10rIiwg'
    || 'dmlldyk6CiAgICAgICAgICAgIHJhaXNlIFZhbHVlRXJyb3IoIlBhbmVsIHZpZXdzIG11c3QgYmUgdW5xdWFsaWZpZWQgVl9DVVNUT01fKiBpZGVudGlmaWVy'
    || 'cyIpCiAgICAgICAga2luZCA9IHBhbmVsLmdldCgia2luZCIsICJ0YWJsZSIpCiAgICAgICAgaWYga2luZCBub3QgaW4geyJ0YWJsZSIsICJiYXIiLCAibWV0'
    || 'cmljIn06CiAgICAgICAgICAgIHJhaXNlIFZhbHVlRXJyb3IoIlBhbmVsIGtpbmQgbXVzdCBiZSB0YWJsZSwgYmFyLCBvciBtZXRyaWMiKQogICAgICAgIGxp'
    || 'bWl0ID0gcGFuZWwuZ2V0KCJsaW1pdCIsIDEwMCkKICAgICAgICBpZiB0eXBlKGxpbWl0KSBpcyBub3QgaW50IG9yIG5vdCAxIDw9IGxpbWl0IDw9IDIwMDoK'
    || 'ICAgICAgICAgICAgcmFpc2UgVmFsdWVFcnJvcigiUGFuZWwgbGltaXQgbXVzdCBiZSBhbiBpbnRlZ2VyIGZyb20gMSB0byAyMDAiKQogICAgICAgIHJlc3Vs'
    || 'dFsicGFuZWxzIl0uYXBwZW5kKHsiaWQiOiBwYW5lbF9pZCwgInRpdGxlIjogdGV4dChwYW5lbC5nZXQoInRpdGxlIiksIDEyMCksCiAgICAgICAgICAgICAg'
    || 'ICAgICAgICAgICAgICAgICAgICJ2aWV3IjogdmlldywgImtpbmQiOiBraW5kLCAibGltaXQiOiBsaW1pdH0pCiAgICByZXR1cm4gcmVzdWx0CgoKZGVmIGxv'
    || 'YWRfY3VzdG9taXphdGlvbihzZXNzaW9uLCB0YXJnZXQpOgogICAgdHJ5OgogICAgICAgIHJlY29yZHMgPSBzZXNzaW9uLnNxbCgiU0VMRUNUIENPTkZJRyBG'
    || 'Uk9NICIgKyB0YXJnZXQgKwogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAiLkFQUF9DVVNUT01JWkFUSU9OIFdIRVJFIElEID0gJ2RlZmF1bHQnIiku'
    || 'bGltaXQoMikuY29sbGVjdCgpCiAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGV4YzoKICAgICAgICByZXR1cm4ge30sIHt9LCAiQ3VzdG9taXphdGlvbiB1bmF2'
    || 'YWlsYWJsZTogIiArIHN0cihleGMpCiAgICBpZiBub3QgcmVjb3JkczoKICAgICAgICByZXR1cm4ge30sIHt9LCBOb25lCiAgICBpZiBsZW4ocmVjb3Jkcykg'
    || 'IT0gMToKICAgICAgICByZXR1cm4ge30sIHt9LCAiQ3VzdG9taXphdGlvbiByZWplY3RlZDogZXhwZWN0ZWQgZXhhY3RseSBvbmUgZGVmYXVsdCByb3ciCiAg'
    || 'ICB0cnk6CiAgICAgICAgY29uZmlnID0gdmFsaWRhdGVfY3VzdG9taXphdGlvbihyZWNvcmRzWzBdWyJDT05GSUciXSkKICAgIGV4Y2VwdCAoVmFsdWVFcnJv'
    || 'ciwgVHlwZUVycm9yLCBLZXlFcnJvcikgYXMgZXhjOgogICAgICAgIHJldHVybiB7fSwge30sICJDdXN0b21pemF0aW9uIHJlamVjdGVkOiAiICsgc3RyKGV4'
    || 'YykKICAgIHBhbmVscyA9IHt9CiAgICBmb3Igc3BlYyBpbiBjb25maWdbInBhbmVscyJdOgogICAgICAgIHRyeToKICAgICAgICAgICAgcm93cyA9IFtyb3cu'
    || 'YXNfZGljdCgpIGZvciByb3cgaW4gc2Vzc2lvbi5zcWwoCiAgICAgICAgICAgICAgICAiU0VMRUNUICogRlJPTSAiICsgdGFyZ2V0ICsgIi4iICsgc3BlY1si'
    || 'dmlldyJdICsgIiBPUkRFUiBCWSAxIgogICAgICAgICAgICApLmxpbWl0KHNwZWNbImxpbWl0Il0gKyAxKS5jb2xsZWN0KCldCiAgICAgICAgICAgIGlmIHNw'
    || 'ZWNbImtpbmQiXSBpbiB7ImJhciIsICJtZXRyaWMifSBhbmQgcm93czoKICAgICAgICAgICAgICAgIGlmIG5vdCB7IkxBQkVMIiwgIlZBTFVFIn0uaXNzdWJz'
    || 'ZXQocm93c1swXSk6CiAgICAgICAgICAgICAgICAgICAgcmFpc2UgVmFsdWVFcnJvcigiQmFyIGFuZCBtZXRyaWMgdmlld3MgbXVzdCBleHBvc2UgTEFCRUwg'
    || 'YW5kIFZBTFVFIGNvbHVtbnMiKQogICAgICAgICAgICByZXN1bHQgPSB7InJvd3MiOiBqc29uLmxvYWRzKGpzb24uZHVtcHMocm93c1s6c3BlY1sibGltaXQi'
    || 'XV0sIGRlZmF1bHQ9c3RyKSl9CiAgICAgICAgICAgIGlmIGxlbihyb3dzKSA+IHNwZWNbImxpbWl0Il06CiAgICAgICAgICAgICAgICByZXN1bHRbInRydW5j'
    || 'YXRlZCJdID0gc3BlY1sibGltaXQiXQogICAgICAgICAgICBwYW5lbHNbc3BlY1siaWQiXV0gPSByZXN1bHQKICAgICAgICBleGNlcHQgRXhjZXB0aW9uIGFz'
    || 'IGV4YzoKICAgICAgICAgICAgcGFuZWxzW3NwZWNbImlkIl1dID0geyJlcnJvciI6IHN0cihleGMpfQogICAgcmV0dXJuIGNvbmZpZywgcGFuZWxzLCBOb25l'
    || 'CgoKIyBGSVJTVCBTdHJlYW1saXQgY2FsbCwgYmVmb3JlIGFueXRoaW5nIGVsc2UgY2FuIGJlY29tZSBvbmUuIFN0cmVhbWxpdCdzICJtYWdpYyIKIyByZW5k'
    || 'ZXJzIGFueSBiYXJlIHRvcC1sZXZlbCBleHByZXNzaW9uIC0tIGluY2x1ZGluZyBhIG1vZHVsZSBkb2NzdHJpbmcgLS0gYXMKIyBtYXJrZG93biwgYW5kIHRo'
    || 'YXQgY291bnRzIGFzIGEgU3RyZWFtbGl0IGNvbW1hbmQsIGFmdGVyIHdoaWNoIHNldF9wYWdlX2NvbmZpZwojIHJhaXNlcyBTdHJlYW1saXRBUElFeGNlcHRp'
    || 'b24gYW5kIHRoZSBwYWdlIGlzIGEgdHJhY2ViYWNrLgojCiMgVGhhdCBpcyBub3QgYSBoeXBvdGhldGljYWwuIFRoaXMgaG9zdCB1c2VkIHRvIGNhbGwgc2V0'
    || 'X3BhZ2VfY29uZmlnIGJlbG93IHRoZQojIHBhbmVsIHNwbGljZTsgc3BsaWNpbmcgYSBwYW5lbHMucHkgdGhhdCBvcGVuZWQgd2l0aCBhIGRvY3N0cmluZyBy'
    || 'ZW5kZXJlZCB0aGUKIyBkb2NzdHJpbmcgYXMgcGFnZSBwcm9zZSwgYW5kIHRoZSBhcHAgc2hpcHBlZCBhcyBhbiBleGNlcHRpb24uIE5vdGhpbmcgaW4gdGhl'
    || 'CiMgcGlwZWxpbmUgY2F1Z2h0IGl0LCBiZWNhdXNlIG5vdGhpbmcgZXhlY3V0ZWQgdGhpcyBmaWxlIG91dHNpZGUgU25vd2ZsYWtlIC0tCiMgZ2F1bnRsZXQg'
    || 'c3RlcCAxMCBwYXJzZXMgUEFORUxTIG91dCBvZiBpdCBhbmQgcnVucyB0aGUgU1FMIGl0c2VsZi4gYnVuZGxlLnB5IG5vdwojIGV4ZWN1dGVzIHRoaXMgbW9k'
    || 'dWxlIGFnYWluc3Qgc3R1YmJlZCBzdHJlYW1saXQvc25vd3BhcmsgbW9kdWxlcyBhbmQgYXNzZXJ0cwojIHNldF9wYWdlX2NvbmZpZyBpcyB0aGUgZmlyc3Qg'
    || 'Y2FsbCwgd2hpY2ggaXMgdGhlIG9ubHkgY2hlY2sgdGhhdCB3b3VsZCBoYXZlLgpzdC5zZXRfcGFnZV9jb25maWcocGFnZV90aXRsZT1TT0xVVElPTl9OQU1F'
    || 'LCBsYXlvdXQ9IndpZGUiKQoKIyDilIDilIAgTWFrZSBTdHJlYW1saXQgZ2V0IG91dCBvZiB0aGUgd2F5IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU'
    || 'gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU'
    || 'gAojIFRoZSBhcHAgaXMgb25lIGZ1bGwtYmxlZWQgUmVhY3QgcGFnZSBpbnNpZGUgY29tcG9uZW50cy5odG1sLiBXaXRob3V0IHRoaXMsCiMgU3RyZWFtbGl0'
    || 'IGZyYW1lcyBpdCBpbiBpdHMgb3duIGNocm9tZTogYSBkYXJrIHBhZ2UgYmFja2dyb3VuZCBhcm91bmQgdGhlCiMgaWZyYW1lLCB+NnJlbSBvZiB0b3AgcGFk'
    || 'ZGluZywgYSBjZW50cmVkIG1heC13aWR0aCBibG9jayBjb250YWluZXIsIGFuZCB0aGUKIyB0b29sYmFyL2Zvb3Rlci4gVGhlIHJlc3VsdCByZWFkcyBhcyBh'
    || 'IHNtYWxsIHdpbmRvdyBmbG9hdGluZyBpbiBhIGJsYWNrIGJvcmRlciwKIyB3aGljaCBpcyBleGFjdGx5IGhvdyBpdCBzaGlwcGVkIGFuZCB3aGF0IHRoZSBm'
    || 'aXJzdCBzY3JlZW5zaG90IHNob3dlZC4KIwojIElubGluZSBDU1MgdGhyb3VnaCBzdC5tYXJrZG93biBpcyB0aGUgc3VwcG9ydGVkIHJvdXRlIC0tIFNub3dm'
    || 'bGFrZSdzIEN1c3RvbSBVSQojIHJlbGVhc2Ugbm90ZXMgbmFtZSAiQ3VzdG9tIEhUTUwgYW5kIENTUyB1c2luZyB1bnNhZmVfYWxsb3dfaHRtbD1UcnVlIGlu'
    || 'CiMgc3QubWFya2Rvd24iIGV4cGxpY2l0bHkuIEl0IGlzIE5PVCBhIENTUCBwcm9ibGVtOiB0aGUgQ1NQIGJsb2NrcyBleHRlcm5hbAojIHJlc291cmNlcyBh'
    || 'bmQgZXZhbCgpLCBub3QgYW4gaW5saW5lIDxzdHlsZT4uCiMKIyBUaGlzIG11c3QgY29tZSBBRlRFUiBzZXRfcGFnZV9jb25maWcgKHdoaWNoIGhhcyB0byBi'
    || 'ZSB0aGUgZmlyc3QgU3RyZWFtbGl0IGNhbGwpCiMgYW5kIEJFRk9SRSB0aGUgY29tcG9uZW50LCBvciB0aGUgcGFnZSBwYWludHMgZGFyayBhbmQgdGhlbiBy'
    || 'ZWZsb3dzLgpzdC5tYXJrZG93bigKICAgICIiIgogICAgPHN0eWxlPgogICAgICAvKiBLaWxsIHRoZSBkYXJrIGNhbnZhcyBhbmQgdGhlIHBhZGRpbmcgdGhh'
    || 'dCBjcmVhdGVzIHRoZSAid2luZG93ZWQiIGxvb2suICovCiAgICAgIC5zdEFwcCwgW2RhdGEtdGVzdGlkPSJzdEFwcFZpZXdDb250YWluZXIiXSwgW2RhdGEt'
    || 'dGVzdGlkPSJzdE1haW4iXSB7CiAgICAgICAgICBiYWNrZ3JvdW5kOiAjZjhmOGY4ICFpbXBvcnRhbnQ7CiAgICAgIH0KICAgICAgW2RhdGEtdGVzdGlkPSJz'
    || 'dEhlYWRlciJdLCBbZGF0YS10ZXN0aWQ9InN0VG9vbGJhciJdLCBmb290ZXIgeyBkaXNwbGF5OiBub25lICFpbXBvcnRhbnQ7IH0KICAgICAgLyogQSBwYWdl'
    || 'IG1hcmdpbiByYXRoZXIgdGhhbiB6ZXJvOiB0aGUgY29tcG9uZW50IGtlZXBzIGl0cyBvd24gaW50ZXJuYWwKICAgICAgICAgcGFkZGluZywgYW5kIHRoaXMg'
    || 'bGluZXMgdGhlIHByb21vdGlvbiBiYXIgdXAgd2l0aCB0aGUgY2FyZHMgaW5zaWRlIGl0LiAqLwogICAgICAuYmxvY2stY29udGFpbmVyLCBbZGF0YS10ZXN0'
    || 'aWQ9InN0TWFpbkJsb2NrQ29udGFpbmVyIl0gewogICAgICAgICAgcGFkZGluZzogMCAwIDIycHggIWltcG9ydGFudDsgbWF4LXdpZHRoOiAxMDAlICFpbXBv'
    || 'cnRhbnQ7CiAgICAgIH0KICAgICAgLyogTk9UIGBbZGF0YS10ZXN0aWQ9InN0VmVydGljYWxCbG9jayJdIHsgZ2FwOiAwIH1gLiBUaGF0IHdhcyBoZXJlIHRv'
    || 'IGNsb3NlCiAgICAgICAgIHRoZSBzdHJpcCBhYm92ZSB0aGUgY29tcG9uZW50LCBhbmQgaXQgYWxzbyBjb2xsYXBzZWQgdGhlIGZsZXggZ2FwIHRoYXQKICAg'
    || 'ICAgICAgU3RyZWFtbGl0IHVzZXMgdG8gc3BhY2UgZXZlcnkgd2lkZ2V0IC0tIHdoaWNoIGRyZXcgZWFjaCBjYXB0aW9uIG9mIHRoZQogICAgICAgICBwcm9t'
    || 'b3Rpb24gYmFyIGRpcmVjdGx5IG9uIHRvcCBvZiB0aGUgbmV4dCBvbmUuIFNjb3BlIGl0IHRvIHRoZSBibG9jayB0aGF0CiAgICAgICAgIGFjdHVhbGx5IGhv'
    || 'bGRzIHRoZSBpZnJhbWUuICovCiAgICAgIFtkYXRhLXRlc3RpZD0ic3RWZXJ0aWNhbEJsb2NrIl06aGFzKD4gW2RhdGEtdGVzdGlkPSJzdElGcmFtZSJdKSB7'
    || 'IGdhcDogMCAhaW1wb3J0YW50OyB9CiAgICAgIC8qIFRoZSBjb21wb25lbnQgaWZyYW1lIHNob3VsZCBiZSB0aGUgd2hvbGUgcGFnZSwgbm90IGEgY2VudHJl'
    || 'ZCBjYXJkLiAqLwogICAgICBbZGF0YS10ZXN0aWQ9InN0SUZyYW1lIl0sIGlmcmFtZSB7IHdpZHRoOiAxMDAlICFpbXBvcnRhbnQ7IGJvcmRlcjogMCAhaW1w'
    || 'b3J0YW50OyB9CiAgICAgIGlmcmFtZVtzcmNkb2MqPSJkYXRhLW9uZXNob3QtZGFzaGJvYXJkIl0gewogICAgICAgICAgaGVpZ2h0OiBjYWxjKDEwMGR2aCAt'
    || 'IDEwMHB4KSAhaW1wb3J0YW50OwogICAgICAgICAgbWluLWhlaWdodDogNDgwcHg7CiAgICAgIH0KICAgICAgW2RhdGEtdGVzdGlkPSJzdE1haW4iXSB7IG92'
    || 'ZXJmbG93OiBhdXRvOyB9CgogICAgICAvKiDilIDilIAgcHJvbW90aW9uIGJhciDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi'
    || 'lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi'
    || 'lIDilIDilIDilIDilIDilIDilIDilIAKICAgICAgICAgTmF0aXZlIFN0cmVhbWxpdCB3aWRnZXRzLCBkcmFnZ2VkIGFzIGNsb3NlIHRvIHRoZSBSZWFjdCBk'
    || 'ZXNpZ24gc3lzdGVtIGFzCiAgICAgICAgIENTUyBhbGxvd3MuIFRoZXkgY2Fubm90IGxpdmUgaW5zaWRlIHRoZSBjb21wb25lbnQgKHNlZSBwcm9tb3Rpb25f'
    || 'YmFyKSwKICAgICAgICAgc28gdGhlIHNlYW0gaXMgcmVhbDsgdGhpcyBuYXJyb3dzIGl0LiBGb250IGFuZCBjb2xvdXIgb25seSAtLSBtYXJnaW5zIGFuZAog'
    || 'ICAgICAgICBsaW5lLWhlaWdodCBhcmUgU3RyZWFtbGl0J3MgYnVzaW5lc3MsIGFuZCBvdmVycmlkaW5nIHRoZW0gaXMgd2hhdCBicm9rZQogICAgICAgICB0'
    || 'aGUgbGF5b3V0IHRoZSBmaXJzdCB0aW1lLiAqLwogICAgICBbZGF0YS10ZXN0aWQ9InN0Q2FwdGlvbkNvbnRhaW5lciJdIHAgewogICAgICAgICAgZm9udC1z'
    || 'aXplOiAxMnB4ICFpbXBvcnRhbnQ7IGNvbG9yOiAjNmI2YjZiICFpbXBvcnRhbnQ7CiAgICAgIH0KICAgICAgLnN0QnV0dG9uIGJ1dHRvbiwKICAgICAgW2Rh'
    || 'dGEtdGVzdGlkPSJzdEJhc2VCdXR0b24tc2Vjb25kYXJ5Il0sCiAgICAgIFtkYXRhLXRlc3RpZD0ic3RCYXNlQnV0dG9uLXByaW1hcnkiXSB7CiAgICAgICAg'
    || 'ICBib3JkZXItcmFkaXVzOiAxMHB4ICFpbXBvcnRhbnQ7IGJvcmRlcjogMXB4IHNvbGlkICNlNWU1ZTcgIWltcG9ydGFudDsKICAgICAgICAgIGJhY2tncm91'
    || 'bmQ6ICNmZmZmZmYgIWltcG9ydGFudDsgY29sb3I6ICMwYTIzNDIgIWltcG9ydGFudDsKICAgICAgICAgIGZvbnQtd2VpZ2h0OiA2NTAgIWltcG9ydGFudDsg'
    || 'Zm9udC1zaXplOiAxMi41cHggIWltcG9ydGFudDsKICAgICAgICAgIHBhZGRpbmc6IDhweCAxNHB4ICFpbXBvcnRhbnQ7CiAgICAgICAgICBib3gtc2hhZG93'
    || 'OiAwIDFweCAzcHggcmdiYSgwLDAsMCwuMDYpLCAwIDJweCAxMnB4IHJnYmEoMCwwLDAsLjA0KSAhaW1wb3J0YW50OwogICAgICAgICAgdHJhbnNpdGlvbjog'
    || 'Ym94LXNoYWRvdyAyMDBtcyBjdWJpYy1iZXppZXIoLjIyLDEsLjM2LDEpICFpbXBvcnRhbnQ7CiAgICAgIH0KICAgICAgLnN0QnV0dG9uIGJ1dHRvbjpob3Zl'
    || 'cjpub3QoOmRpc2FibGVkKSwKICAgICAgW2RhdGEtdGVzdGlkPSJzdEJhc2VCdXR0b24tc2Vjb25kYXJ5Il06aG92ZXI6bm90KDpkaXNhYmxlZCkgewogICAg'
    || 'ICAgICAgYm9yZGVyLWNvbG9yOiAjMDA4NGQ0ICFpbXBvcnRhbnQ7IGNvbG9yOiAjMDA4NGQ0ICFpbXBvcnRhbnQ7CiAgICAgICAgICBib3gtc2hhZG93OiAw'
    || 'IDJweCA4cHggcmdiYSgwLDAsMCwuMDgpLCAwIDhweCAyNHB4IHJnYmEoMCwwLDAsLjA2KSAhaW1wb3J0YW50OwogICAgICB9CiAgICAgIC5zdEJ1dHRvbiBi'
    || 'dXR0b246ZGlzYWJsZWQgeyBvcGFjaXR5OiAuNDUgIWltcG9ydGFudDsgfQogICAgICBbZGF0YS10ZXN0aWQ9InN0QmFzZUJ1dHRvbi1wcmltYXJ5Il0sIC5z'
    || 'dEJ1dHRvbiBidXR0b25ba2luZD0icHJpbWFyeSJdIHsKICAgICAgICAgIGJhY2tncm91bmQ6ICMwMDg0ZDQgIWltcG9ydGFudDsgYm9yZGVyLWNvbG9yOiAj'
    || 'MDA4NGQ0ICFpbXBvcnRhbnQ7CiAgICAgICAgICBjb2xvcjogI2ZmZmZmZiAhaW1wb3J0YW50OwogICAgICB9CiAgICAgIGhyIHsgYm9yZGVyLWNvbG9yOiAj'
    || 'ZTVlNWU3ICFpbXBvcnRhbnQ7IH0KICAgIDwvc3R5bGU+CiAgICAiIiIsCiAgICB1bnNhZmVfYWxsb3dfaHRtbD1UcnVlLAopCgpST1dfQ0FQID0gNTAwMCAg'
    || 'ICMgYSBwYW5lbCB0aGF0IHdvdWxkIHJldHVybiBtb3JlIGlzIHRydW5jYXRlZCwgYW5kIHNheXMgc28KCiMg4pSA4pSAIFRoZSBzb2x1dGlvbidzIHBhbmVs'
    || 'cyDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi'
    || 'lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKIyBQQU5FTFMgbWFwcyBhIHBhbmVs'
    || 'IG5hbWUgdG8gdGhlIFNRTCB0aGF0IGZpbGxzIGl0LiB7dGd0fSBpcyB0aGlzIGFwcCdzIG93bgojIHNjaGVtYSwgcmVzb2x2ZWQgYXQgcnVudGltZSByYXRo'
    || 'ZXIgdGhhbiBiYWtlZCBpbiBhdCBidW5kbGUgdGltZSwgYmVjYXVzZSB0aGUKIyBidW5kbGUgaXMgYnVpbHQgYmVmb3JlIGFueW9uZSBoYXMgY2hvc2VuIGEg'
    || 'dGFyZ2V0IHNjaGVtYS4KIwojIEV2ZXJ5IHNvbHV0aW9uIGRlY2xhcmVzIGEgcGFuZWwgbmFtZWQgYGNvbnRleHRgIHNlbGVjdGluZyBWX0JVSUxEX0NPTlRF'
    || 'WFQ6IHRoZQojIHNoZWxsIHJlYWRzIE1PREUgZnJvbSBpdCB0byBkZWNpZGUgd2hldGhlciB0byBzaG93IHRoZSBTQU1QTEUgYmFubmVyLCBhbmQgYQojIG1p'
    || 'c3NpbmcgTU9ERSBtZWFucyBzZWVkZWQgbnVtYmVycyBjb3VsZCByZW5kZXIgdW5sYWJlbGxlZC4KIwojIEdhdW50bGV0IHN0ZXAgMTAgcGFyc2VzIHRoaXMg'
    || 'ZGljdCBzdGF0aWNhbGx5IGFuZCBydW5zIGVhY2ggcXVlcnkgYWdhaW5zdCB0aGUKIyByZWFsIGJ1aWx0IHNjaGVtYSwgd2hpY2ggaXMgdGhlIG9ubHkgdGVz'
    || 'dCB0aGVzZSBxdWVyaWVzIGdldCAtLSB0aGV5IGxpdmUgaW4gYQojIHB5dGhvbiBmaWxlIHRoYXQgbmV2ZXIgZXhlY3V0ZXMgb3V0c2lkZSBTbm93Zmxha2Uu'
    || 'CiMKIyBBIHBhbmVsIG1heSBjYXJyeSA6bmFtZSBQTEFDRUhPTERFUlMgbmFtaW5nIGEgY29udHJvbCBkZWNsYXJlZCBpbiBDT05UUk9MUwojIGJlbG93LiBU'
    || 'aGV5IGFyZSByZXBsYWNlZCB3aXRoIHBvc2l0aW9uYWwgYmluZHMgYXQgcXVlcnkgdGltZSwgbmV2ZXIgYnkgc3RyaW5nCiMgaW50ZXJwb2xhdGlvbiAtLSBz'
    || 'ZWUgcmVzb2x2ZV9wYW5lbF9zcWwoKS4gT25seSBERUNMQVJFRCBuYW1lcyBhcmUgZWxpZ2libGUsIHNvIGEKIyBgOjpWQVJDSEFSYCBjYXN0IG9yIGFueSBv'
    || 'dGhlciBzdHJheSBjb2xvbiBjYW4gbmV2ZXIgYmUgbWlzdGFrZW4gZm9yIG9uZS4KIwojIENPTlRST0xTIGRlZmF1bHRzIHRvIGVtcHR5IEhFUkUsIGFib3Zl'
    || 'IHRoZSBzcGxpY2UsIHNvIHRoYXQgYSBzb2x1dGlvbidzIG93bgojIGBDT05UUk9MUyA9IFsuLi5dYCBpbiBwYW5lbHMucHkgKHNwbGljZWQgaW4gYmVsb3cp'
    || 'IG92ZXJyaWRlcyBpdCwgYW5kIGEgc29sdXRpb24KIyB0aGF0IGRlY2xhcmVzIG5vbmUga2VlcHMgZXhhY3RseSB0b2RheSdzIGJlaGF2aW91cjogbm8gd2lk'
    || 'Z2V0cywgbm8gYmluZHMsIGFuZCBhCiMgcGFuZWwgcXVlcnkgYnl0ZS1pZGVudGljYWwgdG8gd2hhdCBpdCB3YXMgYmVmb3JlIHRoaXMgbWVjaGFuaXNtIGV4'
    || 'aXN0ZWQuCiMKIyBFYWNoIGNvbnRyb2wgaXMgYSBsaXRlcmFsIGRpY3QsIGJlY2F1c2UgYnVuZGxlLnB5IHJlYWRzIHRoZXNlIHN0YXRpY2FsbHkgZm9yIHRo'
    || 'ZQojIHNhbWUgcmVhc29uIGl0IHJlYWRzIFBBTkVMUyBzdGF0aWNhbGx5IC0tIHN0ZXAgMTAgbmVlZHMgdGhlIERFRkFVTFRTIHRvIGJlIGFibGUKIyB0byBl'
    || 'eGVjdXRlIGEgcGFyYW1ldGVyaXNlZCBwYW5lbCBhdCBhbGw6CiMgICB7ImtleSI6ICJtZXRybyIsICAgICAgICAjIHRoZSA6bmFtZSB1c2VkIGluIHBhbmVs'
    || 'IFNRTCwgYW5kIHRoZSBzZXNzaW9uX3N0YXRlIGtleQojICAgICJsYWJlbCI6ICJNZXRybyIsICAgICAgIyB3aGF0IHRoZSB3aWRnZXQgaXMgY2FsbGVkIG9u'
    || 'IHNjcmVlbgojICAgICJraW5kIjogInNlbGVjdCIsICAgICAgIyBzZWxlY3QgfCBzbGlkZXIgfCBudW1iZXIgfCB0ZXh0CiMgICAgImRlZmF1bHQiOiBOb25l'
    || 'LCAgICAgICAjIHZhbHVlIHVzZWQgYmVmb3JlIHRoZSB1c2VyIHRvdWNoZXMgYW55dGhpbmcsIGFuZCB0aGUKIyAgICAgICAgICAgICAgICAgICAgICAgICAg'
    || 'ICMgdmFsdWUgc3RlcCAxMCBiaW5kcyB3aGVuIGl0IHJ1bnMgdGhlIHBhbmVsCiMgICAgIm9wdGlvbnNfc3FsIjogIlNFTEVDVCBESVNUSU5DVCBNRVRSTyBG'
    || 'Uk9NIHt0Z3R9LlZfWCBPUkRFUiBCWSAxIiwgICMgc2VsZWN0IG9ubHkKIyAgICAib3B0aW9ucyI6IFsiQSIsICJCIl0sICMgc2VsZWN0IG9ubHksIHdoZW4g'
    || 'dGhlIGxpc3QgaXMgZml4ZWQgcmF0aGVyIHRoYW4gcXVlcmllZAojICAgICJtaW4iOiAwLCAibWF4IjogMTAwLCAic3RlcCI6IDEsICAgIyBzbGlkZXIvbnVt'
    || 'YmVyIG9ubHkKIyAgICAiaGVscCI6ICIuLi4ifSAgICAgICAgICMgb3B0aW9uYWwgb25lLWxpbmUgZXhwbGFuYXRpb24gdW5kZXIgdGhlIHdpZGdldApDT05U'
    || 'Uk9MUyA9IFtdClBBTkVMUyA9IHsKICAgICMgVGhlIHNoZWxsIHJlYWRzIE1PREUgZnJvbSBoZXJlIGZvciB0aGUgU0FNUExFIGJhbm5lci4gUmVxdWlyZWQg'
    || 'aW4gZXZlcnkKICAgICMgc29sdXRpb24uCiAgICAiY29udGV4dCI6ICJTRUxFQ1QgKiBGUk9NIHt0Z3R9LlZfQlVJTERfQ09OVEVYVCIsCgogICAgIyBUaGUg'
    || 'cmVjb21tZW5kYXRpb24gcGVyIHdhcmVob3VzZSwgd29yc3QgZmlyc3QuIEVTVF9TQVZJTkdTX0NSRURJVFMgaXMgb3ZlcgogICAgIyB0aGUgZGlzY292ZXJ5'
    || 'IHdpbmRvdywgbm90IHBlciBkYXkgLS0gdGhlIGNvbHVtbiBsYWJlbCBzYXlzIHNvLgogICAgInNhdmluZ3MiOiAoCiAgICAgICAgIlNFTEVDVCBXQVJFSE9V'
    || 'U0VfTkFNRSwgV0hfU0laRSwgR0VORVJBVElPTiwgV0hfVFlQRSwgQVVUT19TVVNQRU5EX1NFQ1MsICIKICAgICAgICAiUkVTT1VSQ0VfTU9OSVRPUiwgQ1JF'
    || 'RElUU19VU0VELCBBQ1RJVkVfREFZUywgVE9UQUxfUkVTVU1FUywgIgogICAgICAgICJBVkdfUkVTVU1FU19QRVJfREFZLCBSRUNPTU1FTkRBVElPTiwgRVNU'
    || 'X1NBVklOR1NfQ1JFRElUUyAiCiAgICAgICAgIkZST00ge3RndH0uVl9XSF9TQVZJTkdTX1NVTU1BUlkgIgogICAgICAgICJPUkRFUiBCWSBFU1RfU0FWSU5H'
    || 'U19DUkVESVRTIERFU0MsIENSRURJVFNfVVNFRCBERVNDIgogICAgKSwKCiAgICAjIFdoZXJlIHRoZSBjcmVkaXRzIGFjdHVhbGx5IGdvLiBPcmRlcmVkIGJ5'
    || 'IHNwZW5kIHNvIHRoZSBwYWdlIG9wZW5zIG9uIHRoZQogICAgIyB3YXJlaG91c2VzIHdvcnRoIGFyZ3VpbmcgYWJvdXQuCiAgICAic3BlbmQiOiAoCiAgICAg'
    || 'ICAgIlNFTEVDVCBXQVJFSE9VU0VfTkFNRSwgUk9VTkQoU1VNKENSRURJVFNfVVNFRCksIDIpIEFTIENSRURJVFNfVVNFRCwgIgogICAgICAgICJST1VORChT'
    || 'VU0oQ1JFRElUU19DT01QVVRFKSwgMikgQVMgQ1JFRElUU19DT01QVVRFLCAiCiAgICAgICAgIlJPVU5EKFNVTShDUkVESVRTX0NMT1VEKSwgMikgQVMgQ1JF'
    || 'RElUU19DTE9VRCwgIgogICAgICAgICJDT1VOVChESVNUSU5DVCBEQVkpIEFTIERBWVNfQUNUSVZFICIKICAgICAgICAiRlJPTSB7dGd0fS5WX1dIX0NSRURJ'
    || 'VF9DT05TVU1QVElPTiBHUk9VUCBCWSAxICIKICAgICAgICAiT1JERVIgQlkgQ1JFRElUU19VU0VEIERFU0MgTElNSVQgMjAiCiAgICApLAoKICAgICMgRGFp'
    || 'bHkgY3JlZGl0IHRvdGFsIGFjcm9zcyBhbGwgd2FyZWhvdXNlcywgZm9yIHRoZSB0cmVuZCBzcGFya2xpbmUuIENhcHBlZAogICAgIyBhdCA2MCBkYXlzIHNv'
    || 'IHRoZSBjaGFydCBzdGF5cyByZWFkYWJsZSBhbmQgdGhlIHBheWxvYWQgc3RheXMgc21hbGwuCiAgICAiZGFpbHlfY3JlZGl0cyI6ICgKICAgICAgICAiU0VM'
    || 'RUNUIERBWSwgUk9VTkQoU1VNKENSRURJVFNfVVNFRCksIDIpIEFTIENSRURJVFNfVVNFRCAiCiAgICAgICAgIkZST00ge3RndH0uVl9XSF9DUkVESVRfQ09O'
    || 'U1VNUFRJT04gR1JPVVAgQlkgMSAiCiAgICAgICAgIk9SREVSIEJZIERBWSBMSU1JVCA2MCIKICAgICksCgogICAgIyBSZXN1bWUgY2h1cm4gaXMgdGhlIEFk'
    || 'YXB0aXZlIHNpZ25hbDogYSB3YXJlaG91c2UgYm91bmNpbmcgYXdha2UgZG96ZW5zIG9mCiAgICAjIHRpbWVzIGEgZGF5IGlzIHBheWluZyB0aGUgbWluaW11'
    || 'bSBiaWxsaW5nIGluY3JlbWVudCBvdmVyIGFuZCBvdmVyLgogICAgImNodXJuIjogKAogICAgICAgICJTRUxFQ1QgV0FSRUhPVVNFX05BTUUsIFNVTShSRVNV'
    || 'TUVTKSBBUyBSRVNVTUVTLCBTVU0oU1VTUEVORFMpIEFTIFNVU1BFTkRTLCAiCiAgICAgICAgIkNPVU5UKERJU1RJTkNUIERBWSkgQVMgREFZUywgIgogICAg'
    || 'ICAgICJST1VORChESVYwKFNVTShSRVNVTUVTKSwgTlVMTElGKENPVU5UKERJU1RJTkNUIERBWSksIDApKSwgMSkgQVMgUkVTVU1FU19QRVJfREFZICIKICAg'
    || 'ICAgICAiRlJPTSB7dGd0fS5WX1dIX0NIVVJOIEdST1VQIEJZIDEgIgogICAgICAgICJPUkRFUiBCWSBSRVNVTUVTX1BFUl9EQVkgREVTQyBMSU1JVCAyMCIK'
    || 'ICAgICksCgogICAgIyBRdWV1ZWluZyBhbmQgc3BpbGw6IHRoZSBjb3VudGVyLWV2aWRlbmNlLiBJdCBpcyB3aGF0IHN0b3BzICJzaHJpbmsKICAgICMgZXZl'
    || 'cnl0aGluZyIgYmVpbmcgdGhlIHJlY29tbWVuZGF0aW9uLCBhbmQgYSBjb3N0IHBhZ2Ugd2l0aG91dCBpdCBpcyBhIHBhZ2UKICAgICMgdGhhdCB3aWxsIGV2'
    || 'ZW50dWFsbHkgc2xvdyBzb21lb25lJ3MgcGlwZWxpbmUgZG93bi4KICAgICJwcmVzc3VyZSI6ICgKICAgICAgICAiU0VMRUNUIFdBUkVIT1VTRV9OQU1FLCBT'
    || 'VU0oUVVFUllfQ09VTlQpIEFTIFFVRVJJRVMsICIKICAgICAgICAiUk9VTkQoU1VNKFFVRVVFRF9TRUNPTkRTKSwgMSkgQVMgUVVFVUVEX1NFQ09ORFMsICIK'
    || 'ICAgICAgICAiUk9VTkQoU1VNKFNQSUxMX0xPQ0FMX0dCKSwgMikgQVMgU1BJTExfTE9DQUxfR0IsICIKICAgICAgICAiUk9VTkQoU1VNKFNQSUxMX1JFTU9U'
    || 'RV9HQiksIDIpIEFTIFNQSUxMX1JFTU9URV9HQiAiCiAgICAgICAgIkZST00ge3RndH0uVl9XSF9QUkVTU1VSRSBHUk9VUCBCWSAxICIKICAgICAgICAiT1JE'
    || 'RVIgQlkgUVVFVUVEX1NFQ09ORFMgREVTQywgU1BJTExfUkVNT1RFX0dCIERFU0MgTElNSVQgMjAiCiAgICApLAoKICAgICMgUHJvamVjdGVkIHZzIG1lYXN1'
    || 'cmVkLCBzaWRlIGJ5IHNpZGUgYW5kIG1vc3RseSBlbXB0eSBvbiBwdXJwb3NlLgogICAgInByb2plY3Rpb25zIjogKAogICAgICAgICJTRUxFQ1QgV0FSRUhP'
    || 'VVNFX05BTUUsIFJFQ09NTUVOREFUSU9OLCBQUk9KRUNURURfU0FWSU5HU19DUkVESVRTLCAiCiAgICAgICAgIk1FQVNVUkVEX1NBVklOR1NfQ1JFRElUUywg'
    || 'QVBQTElFRF9BVCwgTUVBU1VSRURfQVQsIE5PVEVTICIKICAgICAgICAiRlJPTSB7dGd0fS5TQVZJTkdTX1BST0pFQ1RJT05TICIKICAgICAgICAiT1JERVIg'
    || 'QlkgUFJPSkVDVEVEX1NBVklOR1NfQ1JFRElUUyBERVNDIgogICAgKSwKCiAgICAjIFByZWNvbXB1dGVkIGRyaWxsIHRyZWU6IHRvcCB3YXJlaG91c2VzIC0+'
    || 'IHRvcCBxdWVyeSBwYXR0ZXJucyBwZXIgd2FyZWhvdXNlLgogICAgIyBNYXRlcmlhbGl6ZWQgYXMgYSB0YWJsZSBhdCBidWlsZCB0aW1lIHNvIHRoaXMgcmVh'
    || 'ZCBpcyBjaGVhcC4KICAgICJ3aF9kcmlsbCI6ICgKICAgICAgICAiU0VMRUNUIFdIX1JBTkssIFdBUkVIT1VTRV9OQU1FLCBXSF9DUkVESVRTLCBXSF9QQ1Qs'
    || 'ICIKICAgICAgICAiQUNDVF9UT1RBTF9DUkVESVRTLCBRX1JBTkssIFFVRVJZX1RZUEUsIFFVRVJZX1BBVFRFUk4sICIKICAgICAgICAiRVhFQ1VUSU9OUywg'
    || 'VU5MQUJFTExFRCwgVE9UQUxfU0VDT05EUywgUV9USU1FX1BDVCAiCiAgICAgICAgIkZST00ge3RndH0uV0hfRFJJTExfVFJFRSBPUkRFUiBCWSBXSF9SQU5L'
    || 'LCBRX1JBTksiCiAgICApLAp9CgpIRUlHSFQgPSAxODAwCgojIOKUgOKUgCBTaGFyZWQgYWN0aW9uIHBhbmVscyDilIDilIDilIDilIDilIDilIDilIDilIDi'
    || 'lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi'
    || 'lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKIyBFdmVyeSBidWlsZCB3aXRoIHRoZSBhY3Rpb24gZnJhbWV3b3JrIGNyZWF0ZXMg'
    || 'Vl9BQ1RJT05TIGFuZCBBQ1RJT05fTE9HOyBidWlsZHMKIyB3aXRob3V0IGl0IHNpbXBseSBwcm9kdWNlIGEgImRvZXMgbm90IGV4aXN0IiBlcnJvciwgd2hp'
    || 'Y2ggdGhlIFJlYWN0IHNoZWxsCiMgcmVuZGVycyBhcyB0aGUgc3RhbmRhcmQgbm90LWJ1aWx0IHN0YXRlLiBBZGRlZCBoZXJlIHJhdGhlciB0aGFuIGluIGV2'
    || 'ZXJ5CiMgcGFuZWxzLnB5IHNvIGEgbmV3IHNvbHV0aW9uIGdldHMgdGhlbSBmb3IgZnJlZS4KUEFORUxTWyJhY3Rpb25zIl0gPSAoCiAgICAiU0VMRUNUIENP'
    || 'REUsIExBQkVMLCBUSUVSLCBFRkZFQ1QsIEVTVF9DUkVESVRTLCBTVEFURU1FTlRTLCAiCiAgICAiVU5ET19TVEFURU1FTlRTLCBUSU1FU19SVU4sIFRJTUVT'
    || 'X1VORE9ORSBGUk9NIHt0Z3R9LlZfQUNUSU9OUyIKKQpQQU5FTFNbImFjdGlvbl9sb2ciXSA9ICgKICAgICJTRUxFQ1QgQ09ERSwgU1RBVFVTLCBTVEFURU1F'
    || 'TlRTX1JVTiwgU1RBUlRFRF9BVCwgRklOSVNIRURfQVQsIEVSUk9SICIKICAgICJGUk9NIHt0Z3R9LkFDVElPTl9MT0cgT1JERVIgQlkgU1RBUlRFRF9BVCBE'
    || 'RVNDIExJTUlUIDEwIgopCgojIOKUgOKUgCBTaGFyZWQgUE9DIHN1Y2Nlc3MgcGFuZWxzIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU'
    || 'gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU'
    || 'gOKUgOKUgOKUgOKUgAojIEJvdGggdmlld3MgYXJlIGNyZWF0ZWQgYnkgZXZlcnkgYnVpbGQsIGluY2x1ZGluZyBidWlsZHMgd2hvc2Ugc29sdXRpb24KIyBk'
    || 'ZWNsYXJlZCBubyBjcml0ZXJpYSAtLSB0aG9zZSBnZXQgdGhlIHNpbmdsZSAiTk8gU1VDQ0VTUyBDUklURVJJQSBERUNMQVJFRCIKIyByb3cgcmF0aGVyIHRo'
    || 'YW4gYW4gZW1wdHkgcmVzdWx0LCBzbyB0aGUgdGFiIG5ldmVyIHJlbmRlcnMgYmxhbmsgYW5kIGJsYW5rIGlzCiMgbmV2ZXIgbWlzdGFrZW4gZm9yIHplcm8u'
    || 'CiMKIyBSZWFkaW5nIFZfUE9DX1NDT1JFQ0FSRCByZS1leGVjdXRlcyB0aGUgdGFyZ2V0IGFuZCBhY3R1YWwgc2NhbGFycyBpbmxpbmVkIGludG8KIyBpdCwg'
    || 'c28gdGhlc2UgdHdvIHF1ZXJpZXMgYXJlIGhvdyB0aGUgbnVtYmVycyBzdGF5IGxpdmUuIFRoYXQgYWxzbyBtZWFucyB0aGV5CiMgYXJlIHRoZSBtb3N0IGV4'
    || 'cGVuc2l2ZSBwYW5lbHMgaGVyZSwgYW5kIHRoZSBvbmx5IG9uZXMgd2hvc2UgY29zdCBzY2FsZXMgd2l0aAojIHRoZSBjcml0ZXJpYSBhIHNvbHV0aW9uIGRl'
    || 'Y2xhcmVzLgpQQU5FTFNbInBvY19zY29yZWNhcmQiXSA9ICgKICAgICJTRUxFQ1QgQ09ERSwgTEFCRUwsIFdIWV9JVF9NQVRURVJTLCBUQVJHRVQsIEFDVFVB'
    || 'TCwgVU5JVFMsIENPTVBBUkUsIEJBU0lTLCAiCiAgICAiVEFSR0VUX0RFUklWQVRJT04sIFNUQVRFLCBXSFlfTk9UX0VWQUxVQVRFRCwgUkVTT0xWRVNfV0hF'
    || 'TiwgQVJJVEhNRVRJQywgIgogICAgIkNPTVBBUkFCSUxJVFkgRlJPTSB7dGd0fS5WX1BPQ19TQ09SRUNBUkQgIgogICAgIyBOT1RfTUVUIGZpcnN0LiBBIHNj'
    || 'b3JlY2FyZCBzb3J0ZWQgYnkgY29kZSBidXJpZXMgdGhlIG9uZSByb3cgdGhlIHJlYWRlcgogICAgIyBtb3N0IG5lZWRzLCBhbmQgUEVORElORyBzb3J0aW5n'
    || 'IGFib3ZlIGEgZmFpbHVyZSByZWFkcyBhcyByZWFzc3VyYW5jZS4KICAgICJPUkRFUiBCWSBDQVNFIFNUQVRFIFdIRU4gJ05PVF9NRVQnIFRIRU4gMCBXSEVO'
    || 'ICdQRU5ESU5HJyBUSEVOIDEgIgogICAgIldIRU4gJ01FVCcgVEhFTiAyIEVMU0UgMyBFTkQsIENPREUiCikKUEFORUxTWyJwb2NfdmVyZGljdCJdID0gKAog'
    || 'ICAgIlNFTEVDVCBNRVQsIE5PVF9NRVQsIFBFTkRJTkcsIE5BLCBTQ09SRUQsIEhFQURMSU5FLCBWRVJESUNULCBSRUFEX1RISVMgIgogICAgIkZST00ge3Rn'
    || 'dH0uVl9QT0NfVkVSRElDVCIKKQoKCmRlZiB0YXJnZXRfc2NoZW1hKHNlc3Npb24pIC0+IHN0cjoKICAgICIiIlRoZSBzY2hlbWEgdGhpcyBTdHJlYW1saXQg'
    || 'b2JqZWN0IGxpdmVzIGluLgoKICAgIFN0cmVhbWxpdCBpbiBTbm93Zmxha2UgcnVucyB3aXRoIHRoZSBhcHAncyBvd24gZGF0YWJhc2UgYW5kIHNjaGVtYSBj'
    || 'dXJyZW50LAogICAgc28gdGhpcyBpcyByZWxpYWJsZSBhbmQgbmVlZHMgbm8gYnVpbGQtdGltZSBzdWJzdGl0dXRpb24uIFF1b3RlZCBpZGVudGlmaWVycwog'
    || 'ICAgY29tZSBiYWNrIHdpdGggcXVvdGVzIGFscmVhZHksIHdoaWNoIGlzIHdoeSB0aGV5IGFyZSBzdHJpcHBlZC4KICAgICIiIgogICAgY2FjaGVkID0gc3Qu'
    || 'c2Vzc2lvbl9zdGF0ZS5nZXQoIm9uZXNob3RfdGFyZ2V0X3NjaGVtYSIpCiAgICBpZiBjYWNoZWQ6CiAgICAgICAgcmV0dXJuIGNhY2hlZAogICAgcm93ID0g'
    || 'c2Vzc2lvbi5zcWwoCiAgICAgICAgIlNFTEVDVCBDVVJSRU5UX0RBVEFCQVNFKCkgQVMgRCwgQ1VSUkVOVF9TQ0hFTUEoKSBBUyBTIikuY29sbGVjdCgpWzBd'
    || 'CiAgICBkYiwgc2MgPSAocm93WyJEIl0gb3IgIiIpLnN0cmlwKCciJyksIChyb3dbIlMiXSBvciAiIikuc3RyaXAoJyInKQogICAgdGFyZ2V0ID0gZGIgKyAi'
    || 'LiIgKyBzYwogICAgc3Quc2Vzc2lvbl9zdGF0ZVsib25lc2hvdF90YXJnZXRfc2NoZW1hIl0gPSB0YXJnZXQKICAgIHJldHVybiB0YXJnZXQKCgpkZWYgYXBw'
    || 'X25hdmlnYXRpb24oc2Vzc2lvbiwgdGFyZ2V0KToKICAgIGNhY2hlX2tleSA9ICJvbmVzaG90X3ZpZXdlcjoiICsgdGFyZ2V0ICsgIi4iICsgQVBQX09CSkVD'
    || 'VAogICAgaWYgY2FjaGVfa2V5IG5vdCBpbiBzdC5zZXNzaW9uX3N0YXRlOgogICAgICAgIHRyeToKICAgICAgICAgICAgaWYgbm90IHJlLmZ1bGxtYXRjaChy'
    || 'IltBLVphLXowLTlfXStcLltBLVphLXowLTlfXSsiLCB0YXJnZXQpIG9yIG5vdCByZS5mdWxsbWF0Y2gociJbQS1aYS16MC05X10rIiwgQVBQX09CSkVDVCk6'
    || 'CiAgICAgICAgICAgICAgICByZXR1cm4ge30KICAgICAgICAgICAgYWNjb3VudCA9IHNlc3Npb24uc3FsKCJTRUxFQ1QgQ1VSUkVOVF9PUkdBTklaQVRJT05f'
    || 'TkFNRSgpIEFTIE9SRywgQ1VSUkVOVF9BQ0NPVU5UX05BTUUoKSBBUyBBQ0NPVU5UIikuY29sbGVjdCgpWzBdCiAgICAgICAgICAgIGFwcHMgPSBzZXNzaW9u'
    || 'LnNxbCgiU0hPVyBTVFJFQU1MSVRTIElOIFNDSEVNQSAiICsgdGFyZ2V0KS5jb2xsZWN0KCkKICAgICAgICAgICAgYXBwID0gbmV4dCgocm93LmFzX2RpY3Qo'
    || 'KSBmb3Igcm93IGluIGFwcHMgaWYgc3RyKHJvdy5hc19kaWN0KCkuZ2V0KCJuYW1lIiwgIiIpKS51cHBlcigpID09IEFQUF9PQkpFQ1QudXBwZXIoKSksIE5v'
    || 'bmUpCiAgICAgICAgICAgIHBhcnRzID0gW3N0cihhY2NvdW50WyJPUkciXSkubG93ZXIoKSwgc3RyKGFjY291bnRbIkFDQ09VTlQiXSkubG93ZXIoKSwgc3Ry'
    || 'KChhcHAgb3Ige30pLmdldCgidXJsX2lkIiwgIiIpKV0KICAgICAgICAgICAgaWYgbm90IGFsbChyZS5mdWxsbWF0Y2gociJbQS1aYS16MC05Xy1dKyIsIHZh'
    || 'bHVlKSBmb3IgdmFsdWUgaW4gcGFydHMpOgogICAgICAgICAgICAgICAgcmV0dXJuIHt9CiAgICAgICAgICAgIHN0LnNlc3Npb25fc3RhdGVbY2FjaGVfa2V5'
    || 'XSA9ICJodHRwczovL2FwcC5zbm93Zmxha2UuY29tL3N0cmVhbWxpdC8iICsgcGFydHNbMF0gKyAiLyIgKyBwYXJ0c1sxXSArICIvIy9hcHBzLyIgKyBwYXJ0'
    || 'c1syXQogICAgICAgICAgICBzdC5zZXNzaW9uX3N0YXRlW2NhY2hlX2tleSArICI6YnVpbGRlciJdID0gImh0dHBzOi8vYXBwLnNub3dmbGFrZS5jb20vIiAr'
    || 'IHBhcnRzWzBdICsgIi8iICsgcGFydHNbMV0gKyAiLyMvc3RyZWFtbGl0LWFwcHMvIiArIHRhcmdldCArICIuIiArIEFQUF9PQkpFQ1QKICAgICAgICBleGNl'
    || 'cHQgRXhjZXB0aW9uOgogICAgICAgICAgICByZXR1cm4ge30KICAgIHJldHVybiB7InZpZXdlcl91cmwiOiBzdC5zZXNzaW9uX3N0YXRlW2NhY2hlX2tleV0s'
    || 'ICJidWlsZGVyX3VybCI6IHN0LnNlc3Npb25fc3RhdGUuZ2V0KGNhY2hlX2tleSArICI6YnVpbGRlciIsICIiKX0KCgpkZWYgaW52YWxpZGF0ZV9wYW5lbF9j'
    || 'YWNoZSgpOgogICAgc3Quc2Vzc2lvbl9zdGF0ZS5wb3AoIm9uZXNob3RfcGFuZWxfY2FjaGUiLCBOb25lKQoKCmRlZiBjYWNoZWRfcGFuZWwoc2Vzc2lvbiwg'
    || 'c3FsLCBiaW5kcywgdHRsPTMwKToKICAgIGVudHJpZXMgPSBzdC5zZXNzaW9uX3N0YXRlLnNldGRlZmF1bHQoIm9uZXNob3RfcGFuZWxfY2FjaGUiLCB7fSkK'
    || 'ICAgIGtleSA9IGpzb24uZHVtcHMoW3NxbCwgYmluZHNdLCBzb3J0X2tleXM9VHJ1ZSwgZGVmYXVsdD1zdHIpCiAgICBub3cgPSBtb25vdG9uaWMoKQogICAg'
    || 'ZW50cnkgPSBlbnRyaWVzLmdldChrZXkpCiAgICBpZiBlbnRyeSBhbmQgbm93IC0gZW50cnlbMF0gPCB0dGw6CiAgICAgICAgcmV0dXJuIGNvcHkuZGVlcGNv'
    || 'cHkoZW50cnlbMV0pCiAgICBmcmFtZSA9IHNlc3Npb24uc3FsKHNxbCwgcGFyYW1zPWJpbmRzKSBpZiBiaW5kcyBlbHNlIHNlc3Npb24uc3FsKHNxbCkKICAg'
    || 'IHJvd3MgPSBbcm93LmFzX2RpY3QoKSBmb3Igcm93IGluIGZyYW1lLmxpbWl0KFJPV19DQVAgKyAxKS5jb2xsZWN0KCldCiAgICBwYW5lbCA9IHsicm93cyI6'
    || 'IGpzb24ubG9hZHMoanNvbi5kdW1wcyhyb3dzWzpST1dfQ0FQXSwgZGVmYXVsdD1zdHIpKX0KICAgIGlmIGxlbihyb3dzKSA+IFJPV19DQVA6CiAgICAgICAg'
    || 'cGFuZWxbInRydW5jYXRlZCJdID0gUk9XX0NBUAogICAgZW50cmllc1trZXldID0gKG5vdywgcGFuZWwpCiAgICB3aGlsZSBsZW4oZW50cmllcykgPiA4MDoK'
    || 'ICAgICAgICBlbnRyaWVzLnBvcChuZXh0KGl0ZXIoZW50cmllcykpKQogICAgcmV0dXJuIGNvcHkuZGVlcGNvcHkocGFuZWwpCgoKZGVmIHJlc29sdmVfcGFu'
    || 'ZWxfc3FsKHNxbDogc3RyLCBwYXJhbXM6IGRpY3QpOgogICAgIiIiKHNxbF93aXRoX3Bvc2l0aW9uYWxfYmluZHMsIGJpbmRzKSBmb3Igb25lIHBhbmVsLgoK'
    || 'ICAgIEJJTkRTLCBOT1QgSU5URVJQT0xBVElPTi4gQSBjb250cm9sJ3MgdmFsdWUgaXMgY2hvc2VuIGJ5IHdob2V2ZXIgaXMgbG9va2luZyBhdAogICAgdGhl'
    || 'IHBhZ2UsIHNvIHBhc3RpbmcgaXQgaW50byB0aGUgU1FMIHRleHQgd291bGQgYmUgYW4gaW5qZWN0aW9uIGhvbGUgaW4gYSBxdWVyeQogICAgdGhhdCBydW5z'
    || 'IHdpdGggdGhlIGFwcCBvd25lcidzIHByaXZpbGVnZXMuIEV2ZXJ5IHZhbHVlIGxlYXZlcyBoZXJlIGFzIGEgYD9gLgoKICAgIE9OTFkgREVDTEFSRUQgTkFN'
    || 'RVMgQVJFIEVMSUdJQkxFLiBUaGUgcGF0dGVybiBpcyBidWlsdCBmcm9tIHRoZSBrZXlzIG9mIGBwYXJhbXNgCiAgICByYXRoZXIgdGhhbiBmcm9tIGEgZ2Vu'
    || 'ZXJpYyBgOlxcdytgLCB3aGljaCBpcyB3aGF0IG1ha2VzIGA6OlZBUkNIQVJgIHNhZmU6IHRoZQogICAgc2Vjb25kIGNvbG9uIG9mIGEgY2FzdCBjYW5ub3Qg'
    || 'YmVnaW4gYSBkZWNsYXJlZCBuYW1lLCBhbmQgdGhlIG5lZ2F0aXZlIGxvb2tiZWhpbmQKICAgIHJlZnVzZXMgaXQgYSBzZWNvbmQgdGltZS4gQW55dGhpbmcg'
    || 'ZWxzZSBjb2xvbi1zaGFwZWQgaW4gYSBwYW5lbCAtLSBhIHN0YWdlIHBhdGgsCiAgICBhIEpTT04gdHJhdmVyc2FsIC0tIGlzIGxlZnQgdW50b3VjaGVkIGJl'
    || 'Y2F1c2UgaXQgd2FzIG5ldmVyIGRlY2xhcmVkLgoKICAgIExvbmdlc3QgbmFtZSBmaXJzdCBzbyB0aGF0IGRlY2xhcmluZyBib3RoIGBtZXRyb2AgYW5kIGBt'
    || 'ZXRyb19jb2RlYCBjYW5ub3QgaGF2ZQogICAgdGhlIHNob3J0ZXIgb25lIGVhdCB0aGUgZnJvbnQgb2YgdGhlIGxvbmdlci4KCiAgICBUSElTIEZVTkNUSU9O'
    || 'IElTIERVUExJQ0FURUQgaW4gaGFybmVzcy9idW5kbGUucHkuIEl0IGhhcyB0byBiZTogdGhpcyBmaWxlIGlzCiAgICBzdGFuZGFsb25lIGNvZGUgdGhhdCBy'
    || 'dW5zIGluc2lkZSBTbm93Zmxha2UgYW5kIGNhbm5vdCBpbXBvcnQgdGhlIGhhcm5lc3MsIHdoaWxlCiAgICBnYXVudGxldCBzdGVwIDEwIGFuZCB0aGUgcmVu'
    || 'ZGVyIGNoZWNrIG5lZWQgdGhlIGlkZW50aWNhbCBzdWJzdGl0dXRpb24gdG8gdGVzdAogICAgd2hhdCB0aGUgYXBwIHdpbGwgcmVhbGx5IHJ1bi4gSWYgeW91'
    || 'IGNoYW5nZSBvbmUsIGNoYW5nZSBib3RoIC0tIHRoZSBwYWlyIGlzCiAgICBjb3ZlcmVkIGJ5IGEgdGVzdCBpbiBidW5kbGUucHkgdGhhdCBjb21wYXJlcyB0'
    || 'aGVtLgogICAgIiIiCiAgICBpZiBub3QgcGFyYW1zOgogICAgICAgIHJldHVybiBzcWwsIFtdCiAgICBuYW1lcyA9IHNvcnRlZChwYXJhbXMsIGtleT1sZW4s'
    || 'IHJldmVyc2U9VHJ1ZSkKICAgIHBhdCA9IHJlLmNvbXBpbGUociIoPzwhOik6KCIgKyAifCIuam9pbihyZS5lc2NhcGUobikgZm9yIG4gaW4gbmFtZXMpICsg'
    || 'ciIpXGIiKQogICAgYmluZHMgPSBbXQoKICAgIGRlZiBzdWIobSk6CiAgICAgICAgYmluZHMuYXBwZW5kKHBhcmFtc1ttLmdyb3VwKDEpXSkKICAgICAgICBy'
    || 'ZXR1cm4gIj8iCgogICAgcmV0dXJuIHBhdC5zdWIoc3ViLCBzcWwpLCBiaW5kcwoKCmRlZiBydW5fcGFuZWxzKHNlc3Npb24sIHRndDogc3RyLCBwYXJhbXM6'
    || 'IGRpY3QgPSBOb25lKSAtPiBkaWN0OgogICAgIiIiUnVuIGV2ZXJ5IHBhbmVsLCBvbmUgZmFpbHVyZSBjb3N0aW5nIG9uZSBwYW5lbC4KCiAgICBGZXRjaGVz'
    || 'IFJPV19DQVAgKyAxIHJvd3Mgc28gdGhhdCBoaXR0aW5nIHRoZSBjYXAgaXMgREVURUNUQUJMRS4gU2VsZWN0aW5nCiAgICBleGFjdGx5IFJPV19DQVAgaXMg'
    || 'aW5kaXN0aW5ndWlzaGFibGUgZnJvbSAidGhlIGFuc3dlciBoYXBwZW5lZCB0byBiZSA1MDAwIiwKICAgIGFuZCBhIGNhcmQgdGhhdCBjb3VudHMgcm93cyBj'
    || 'bGllbnQtc2lkZSB0byBwcm9kdWNlIGEgaGVhZGxpbmUgLS0gIjQxMiB0YWJsZXMKICAgIGFyZSBlbGlnaWJsZSIgLS0gd291bGQgdGhlbiByZXBvcnQgdGhl'
    || 'IGNhcCBhcyBpZiBpdCB3ZXJlIHRoZSB0b3RhbC4gVGhlIGV4dHJhCiAgICByb3cgaXMgZHJvcHBlZCBiZWZvcmUgdGhlIHBheWxvYWQgaXMgYnVpbHQ7IG9u'
    || 'bHkgdGhlIGZsYWcgc3Vydml2ZXMuCgogICAgYHBhcmFtc2AgY2FycmllcyB0aGUgY3VycmVudCB2YWx1ZSBvZiBldmVyeSBkZWNsYXJlZCBjb250cm9sLiBU'
    || 'aGlzIHJ1bnMgb24gRVZFUlkKICAgIFN0cmVhbWxpdCByZXJ1biwgd2hpY2ggaXMgdGhlIHdob2xlIHJlYXNvbiBhIGNvbnRyb2wgY2FuIGNoYW5nZSB3aGF0'
    || 'IHRoZSBSZWFjdAogICAgcGFnZSBzaG93czogdGhlIGlmcmFtZSBjYW5ub3QgcmUtcXVlcnksIGJ1dCB0aGUgaG9zdCByZS1xdWVyaWVzIGZvciBpdCBhbmQg'
    || 'aGFuZHMKICAgIGRvd24gYSBmcmVzaCBwYXlsb2FkLiBBIHNvbHV0aW9uIHRoYXQgZGVjbGFyZXMgbm8gY29udHJvbHMgcGFzc2VzIGFuIGVtcHR5IGRpY3QK'
    || 'ICAgIGFuZCB0YWtlcyB0aGUgbm8tYmluZHMgcGF0aCBiZWxvdywgc28gaXRzIHF1ZXJ5IGlzIHVuY2hhbmdlZC4KICAgICIiIgogICAgcGFyYW1zID0gcGFy'
    || 'YW1zIG9yIHt9CiAgICBvdXQgPSB7fQogICAgZm9yIG5hbWUsIHNxbCBpbiBQQU5FTFMuaXRlbXMoKToKICAgICAgICB0cnk6CiAgICAgICAgICAgIHEsIGJp'
    || 'bmRzID0gcmVzb2x2ZV9wYW5lbF9zcWwoc3FsLnJlcGxhY2UoInt0Z3R9IiwgdGd0KSwgcGFyYW1zKQogICAgICAgICAgICAjIFRoZSBuby1iaW5kcyBjYWxs'
    || 'IGlzIGtlcHQgZGlzdGluY3QgcmF0aGVyIHRoYW4gYWx3YXlzIHBhc3NpbmcKICAgICAgICAgICAgIyBwYXJhbXM9W106IGV2ZXJ5IGV4aXN0aW5nIHBhbmVs'
    || 'IGdvZXMgZG93biB0aGlzIHBhdGggdW50b3VjaGVkLCBzbyB0aGlzCiAgICAgICAgICAgICMgbWVjaGFuaXNtIGNhbm5vdCByZWdyZXNzIGEgc29sdXRpb24g'
    || 'dGhhdCBuZXZlciBvcHRlZCBpbnRvIGl0LgogICAgICAgICAgICBvdXRbbmFtZV0gPSBjYWNoZWRfcGFuZWwoc2Vzc2lvbiwgcSwgYmluZHMpCiAgICAgICAg'
    || 'ZXhjZXB0IEV4Y2VwdGlvbiBhcyBleGM6CiAgICAgICAgICAgIG91dFtuYW1lXSA9IHsiZXJyb3IiOiB0eXBlKGV4YykuX19uYW1lX18gKyAiOiAiICsgc3Ry'
    || 'KGV4YylbOjQwMF19CiAgICByZXR1cm4gb3V0CgoKZGVmIGJ1aWxkX2h0bWwocGF5bG9hZDogZGljdCkgLT4gc3RyOgogICAganMgPSBiYXNlNjQuYjY0ZGVj'
    || 'b2RlKEFQUF9KU19CNjQpLmRlY29kZSgidXRmLTgiKQogICAgY3NzID0gYmFzZTY0LmI2NGRlY29kZShBUFBfQ1NTX0I2NCkuZGVjb2RlKCJ1dGYtOCIpCiAg'
    || 'ICBkYXRhID0ganNvbi5kdW1wcyhwYXlsb2FkKQogICAgIyBUaGUgb25seSBlc2NhcGUgdGhhdCBtYXR0ZXJzIHdoZW4gaW5saW5pbmcgaW50byA8c2NyaXB0'
    || 'PjogdGhlIHNlcXVlbmNlCiAgICAjIDwvc2NyaXB0IHdvdWxkIGVuZCB0aGUgdGFnIGVhcmx5LiBJdCBjYW4gYXBwZWFyIGluIEpTIG9ubHkgaW5zaWRlIGEg'
    || 'c3RyaW5nCiAgICAjIG9yIGEgY29tbWVudCwgc28gbmV1dHJhbGlzaW5nIGl0IGNhbm5vdCBjaGFuZ2UgYmVoYXZpb3VyLgogICAganMgPSBqcy5yZXBsYWNl'
    || 'KCI8L3NjcmlwdCIsICI8XFwvc2NyaXB0IikKICAgIGRhdGEgPSBkYXRhLnJlcGxhY2UoIjwvIiwgIjxcXC8iKQogICAgcmV0dXJuICgKICAgICAgICAiPCFk'
    || 'b2N0eXBlIGh0bWw+PGh0bWw+PGhlYWQ+PG1ldGEgY2hhcnNldD0ndXRmLTgnPjxzdHlsZT4iICsgY3NzCiAgICAgICAgKyAiPC9zdHlsZT48L2hlYWQ+PGJv'
    || 'ZHkgZGF0YS1vbmVzaG90LWRhc2hib2FyZD48ZGl2IGlkPSdyb290Jz48L2Rpdj4iCiAgICAgICAgKyAiPHNjcmlwdD53aW5kb3dbIiArIGpzb24uZHVtcHMo'
    || 'R0xPQkFMX05BTUUpICsgIl0gPSAiICsgZGF0YSArICI7PC9zY3JpcHQ+IgogICAgICAgICsgIjxzY3JpcHQ+IiArIGpzICsgIjwvc2NyaXB0PjwvYm9keT48'
    || 'L2h0bWw+IgogICAgKQoKClRJRVJfT1JERVIgPSBbIlNBTVBMRSIsICJMSU1JVEVEIiwgIlBST0RVQ1RJT04iXQpUSUVSX0JMVVJCID0gewogICAgIlNBTVBM'
    || 'RSI6ICAgICAiU2VlZGVkIGRhdGEuIFNhZmUgdG8gcnVuIHJlcGVhdGVkbHk7IHByb3ZlcyB0aGUgc2hhcGUgd2l0aG91dCAiCiAgICAgICAgICAgICAgICAg'
    || 'ICJ0b3VjaGluZyBhbnl0aGluZyByZWFsLiIsCiAgICAiTElNSVRFRCI6ICAgICJZb3VyIGRhdGEsIGRlbGliZXJhdGVseSBib3VuZGVkIOKAlCBhIHN1YnNl'
    || 'dCwgYSBjYXAsIG9yIGEgc2luZ2xlICIKICAgICAgICAgICAgICAgICAgIm9iamVjdC4gTWVhbnQgdG8gYmUgcmV2ZXJzaWJsZS4iLAogICAgIlBST0RVQ1RJ'
    || 'T04iOiAiWW91ciBkYXRhLCBhdCBmdWxsIHNjb3BlLiBSZWFkIHRoZSB1bmRvIGxpbmUgYmVmb3JlIHlvdSBydW4gaXQuIiwKfQoKCmRlZiBmbXRfY3JlZGl0'
    || 'cyh2KSAtPiBzdHI6CiAgICAiIiIwLjAyLCBub3QgMC4wMjAwMDAuCgogICAgRVNUX0NSRURJVFMgaXMgTlVNQkVSKDM4LDYpIHNvIHRoYXQgZnJhY3Rpb25h'
    || 'bCBjcmVkaXRzIHN1cnZpdmUgdGhlIHJvdW5kIHRyaXAsCiAgICBhbmQgc3RyKCkgb24gYSBEZWNpbWFsIGtlZXBzIGV2ZXJ5IHRyYWlsaW5nIHplcm8uIFNp'
    || 'eCBkZWNpbWFsIHBsYWNlcyBpbiBhCiAgICBidXR0b24gY2FwdGlvbiByZWFkcyBhcyBhIG1hY2hpbmUgdGFsa2luZyB0byBpdHNlbGYuCiAgICAiIiIKICAg'
    || 'IGlmIHYgaXMgTm9uZToKICAgICAgICByZXR1cm4gIlx1MjAxNCIKICAgIHRyeToKICAgICAgICBzID0gZiJ7ZmxvYXQodik6LjNmfSIucnN0cmlwKCIwIiku'
    || 'cnN0cmlwKCIuIikKICAgICAgICByZXR1cm4gcyBvciAiMCIKICAgIGV4Y2VwdCAoVHlwZUVycm9yLCBWYWx1ZUVycm9yKToKICAgICAgICByZXR1cm4gc3Ry'
    || 'KHYpCgoKZGVmIGxvYWRfcnVsZV9jb25maWcoc2Vzc2lvbiwgdGd0OiBzdHIpOgogICAgIiIiKCh0aWVyLCBhbGxvd19yZWFsLCBhbGxvd19zYW1wbGUpLCBy'
    || 'b3dzKSBmb3IgYSBzb2x1dGlvbiB3aXRoIGEgdHVuYWJsZSBydWxlCiAgICBzZXQsIGVsc2UgKCgiIiwgRmFsc2UsIEZhbHNlKSwgW10pLgoKICAgIFdIWSBU'
    || 'SElTIFJFQURTIFRJRVIgQU5EIE5PVCBNT0RFLiBJdCB1c2VkIHRvIHJldHVybiBNT0RFLCBhbmQgY29uZmlnX2JhciBnYXRlZAogICAgb24gYG1vZGUgaW4g'
    || 'KCJQT0MiLCAiUFJPRFVDVElPTiIpYC4gTU9ERSBjYW4gb25seSBldmVyIGhvbGQgRElTQ09WRVIgb3IgU0FNUExFCiAgICAtLSB0aG9zZSBhcmUgdGhlIG9u'
    || 'bHkgdHdvIHZhbHVlcyB0aGUgc2V0dGluZ3MgdGVtcGxhdGUgZGVmaW5lcywgYW5kCiAgICAwMF9zZXR0aW5nc19hbmRfYmxvY2swIGRvY3VtZW50cyB0aGVt'
    || 'IGFzIGEgREFUQSBTT1VSQ0Ugc3dpdGNoOiBESVNDT1ZFUiByZWFkcwogICAgeW91ciBhY2NvdW50LCBTQU1QTEUgc2VlZHMgZml4dHVyZXMgaW5zdGVhZC4g'
    || 'IlBPQyIgd2FzIG5ldmVyIGEgcmVhY2hhYmxlIHZhbHVlLAogICAgc28gdGhlIGNvbnRyb2xzIHdlcmUgZGVhZCBpbiBldmVyeSBzb2x1dGlvbiwgaW4gZXZl'
    || 'cnkgbW9kZSwgYW5kCiAgICBTRVRfUlVMRV9DT05GSUcgLyBSRUJVSUxEX1JFU09MVVRJT04gLyBSRVNFVF9SVUxFX0RFRkFVTFRTIGNvdWxkIG5vdCBiZSBy'
    || 'ZWFjaGVkCiAgICBmcm9tIHRoZSBhcHAgYXQgYWxsLgoKICAgIFRoZSBnYXRlIHdhcyB3cml0dGVuIGFnYWluc3QgYSBESVNDT1ZFUiAtPiBQT0MgLT4gUFJP'
    || 'RFVDVElPTiBtYXR1cml0eSBsYWRkZXIKICAgIHRoYXQgd2FzIG5ldmVyIGltcGxlbWVudGVkLiBUaGUgbGFkZGVyIHRoYXQgZG9lcyBleGlzdCBpcyBUSUVS'
    || 'CiAgICAoU0FNUExFIC8gTElNSVRFRCAvIFBST0RVQ1RJT04pLCB3aGljaCBpcyB3aGF0IGdvdmVybnMgaG93IG11Y2ggcmVhbCBkYXRhIHRoZQogICAgYnVp'
    || 'bGQgaXMgYWxsb3dlZCB0byB0b3VjaC4gU28gdGhlIGdhdGUgbm93IHJlYWRzIFRJRVIsIGFuZCByZXVzZXMgdGhlIFNBTUUgdHdvCiAgICBhdXRob3Jpc2F0'
    || 'aW9ucyBwcm9tb3Rpb25fYmFyIHJlYWRzIC0tIEFMTE9XX0FDVElPTlMgZm9yIExJTUlURUQgYW5kIFBST0RVQ1RJT04sCiAgICBBTExPV19TQU1QTEVfQUNU'
    || 'SU9OUyBmb3IgU0FNUExFLiBUaGF0IGlzIGRlbGliZXJhdGU6IGEgdGhyZXNob2xkIGNoYW5nZSBjb3N0cyBhCiAgICBSRUJVSUxEX1JFU09MVVRJT04gY2Fs'
    || 'bCwgd2hpY2ggaXMgYW4gYWN0aW9uLCBzbyBpZiB0aGUgdHdvIHN1cmZhY2VzIGRpc2FncmVlZAogICAgYWJvdXQgd2hhdCBpcyBsaXZlIG9uZSBvZiB0aGVt'
    || 'IHdvdWxkIGJlIGx5aW5nLgoKICAgIE5PIFBFUi1TT0xVVElPTiBGTEFHLCBBTkQgVEhBVCBJUyBUSEUgV0hPTEUgU0FGRVRZIEFSR1VNRU5ULiBUaGlzIGdh'
    || 'dGVzIG9uCiAgICB3aGV0aGVyIFZfUlVMRV9DT05GSUcgZXhpc3RzLCBleGFjdGx5IGFzIGxvYWRfYWN0aW9ucygpIGdhdGVzIG9uIFZfQUNUSU9OUy4KICAg'
    || 'IFR3ZW50eS1maXZlIG9mIHRoZSB0d2VudHktc2V2ZW4gc29sdXRpb25zIGRvIG5vdCBkZWZpbmUgdGhhdCB2aWV3LCBzbyBmb3IgdGhlbQogICAgdGhpcyBy'
    || 'ZXR1cm5zICgoIiIsIEZhbHNlLCBGYWxzZSksIFtdKSBvbiB0aGUgZmlyc3QgZXhjZXB0aW9uIGFuZCBjb25maWdfYmFyKCkKICAgIGRyYXdzIG5vdGhpbmcg'
    || 'LS0gbm8gbmV3IHNldHRpbmcgdG8gc2V0IHdyb25nLCBubyBzZWNvbmQgY29kZSBwYXRoIHRocm91Z2ggdGhlCiAgICBzaGVsbCwgYW5kIG5vIHdheSBmb3Ig'
    || 'YSBzb2x1dGlvbiB0aGF0IG5ldmVyIG9wdGVkIGluIHRvIGdyb3cgYSBjb250cm9sIHN1cmZhY2UKICAgIGJ5IGFjY2lkZW50LgoKICAgIFRoZSBnYXRlIGNv'
    || 'bWVzIGJhY2sgd2l0aCB0aGUgcm93cyBiZWNhdXNlIHRoZSBjYWxsZXIgbmVlZHMgYm90aCB0byBkZWNpZGUKICAgIGFueXRoaW5nLCBhbmQgcmVhZGluZyBp'
    || 'dCB0d2ljZSBpbnZpdGVzIHRoZSB0d28gcmVhZHMgdG8gZGlzYWdyZWUgYWNyb3NzIGEgcmVydW4uCiAgICAiIiIKICAgIHRyeToKICAgICAgICByb3dzID0g'
    || 'W3IuYXNfZGljdCgpIGZvciByIGluIHNlc3Npb24uc3FsKAogICAgICAgICAgICAiU0VMRUNUIFJVTEVfSUQsIEdST1VQX0xBQkVMLCBQTEFJTl9MQUJFTCwg'
    || 'UExBSU5fREVTQywgSVNfQUNUSVZFLCAiCiAgICAgICAgICAgICJJU19NT0RJRklFRCwgVEhSRVNIT0xELCBUSFJFU0hPTERfRURJVEFCTEUsIExJTktTLCBT'
    || 'T0xFX0xJTktTICIKICAgICAgICAgICAgIkZST00gIiArIHRndCArICIuVl9SVUxFX0NPTkZJRyBPUkRFUiBCWSBHUk9VUF9TRVEsIFJVTEVfU0VRIikuY29s'
    || 'bGVjdCgpXQogICAgZXhjZXB0IEV4Y2VwdGlvbjoKICAgICAgICByZXR1cm4gKCIiLCBGYWxzZSwgRmFsc2UpLCBbXQogICAgIyBSZWFkIGRlZmVuc2l2ZWx5'
    || 'IGFuZCBmYWlsIENMT1NFRCBvbiBlYWNoIG9uZSBpbmRlcGVuZGVudGx5LiBBIHJ1bGUgc2V0IHdob3NlCiAgICAjIHRpZXIgb3IgYXV0aG9yaXNhdGlvbiBj'
    || 'YW5ub3QgYmUgZXN0YWJsaXNoZWQgaXMgdHJlYXRlZCBhcyByZWFkLW9ubHksIGJlY2F1c2UKICAgICMgdGhlIGZhaWx1cmUgZGlyZWN0aW9uIG1hdHRlcnM6'
    || 'IGd1ZXNzaW5nICJsaXZlIiBoZXJlIHdvdWxkIGFybSBjb250cm9scyB0aGF0CiAgICAjIGNhbGwgYSByZWJ1aWxkIG9uIGEgYnVpbGQgd2Uga25vdyBub3Ro'
    || 'aW5nIGFib3V0LgogICAgdHJ5OgogICAgICAgIHRpZXIgPSBzdHIoc2Vzc2lvbi5zcWwoCiAgICAgICAgICAgICJTRUxFQ1QgVElFUiBGUk9NICIgKyB0Z3Qg'
    || 'KyAiLlZfQlVJTERfQ09OVEVYVCIpLmNvbGxlY3QoKVswXVswXQogICAgICAgICAgICBvciAiIikudXBwZXIoKQogICAgZXhjZXB0IEV4Y2VwdGlvbjoKICAg'
    || 'ICAgICB0aWVyID0gIiIKICAgIHRyeToKICAgICAgICBhbGxvd19yZWFsID0gYm9vbChzZXNzaW9uLnNxbCgKICAgICAgICAgICAgIlNFTEVDVCBBQ1RJT05T'
    || 'X0VOQUJMRUQgRlJPTSAiICsgdGd0ICsgIi5WX0JVSUxEX0NPTlRFWFQiKS5jb2xsZWN0KClbMF1bMF0pCiAgICBleGNlcHQgRXhjZXB0aW9uOgogICAgICAg'
    || 'IGFsbG93X3JlYWwgPSBGYWxzZQogICAgdHJ5OgogICAgICAgIGFsbG93X3NhbXBsZSA9IGJvb2woc2Vzc2lvbi5zcWwoCiAgICAgICAgICAgICJTRUxFQ1Qg'
    || 'Q09BTEVTQ0UoU0FNUExFX0FDVElPTlNfRU5BQkxFRCwgRkFMU0UpIEZST00gIiArIHRndAogICAgICAgICAgICArICIuVl9CVUlMRF9DT05URVhUIikuY29s'
    || 'bGVjdCgpWzBdWzBdKQogICAgZXhjZXB0IEV4Y2VwdGlvbjoKICAgICAgICBhbGxvd19zYW1wbGUgPSBGYWxzZQogICAgcmV0dXJuICh0aWVyLCBhbGxvd19y'
    || 'ZWFsLCBhbGxvd19zYW1wbGUpLCByb3dzCgoKZGVmIGNvbmZpZ19iYXIoc2Vzc2lvbiwgdGd0OiBzdHIpIC0+IE5vbmU6CiAgICAiIiJUaGUgdHVuYWJsZSBy'
    || 'dWxlIHNldDogcmVhZC1vbmx5IHVudGlsIHRoZSBidWlsZCBpcyBhdXRob3Jpc2VkIHRvIGFjdC4KCiAgICBTdHJlYW1saXQgcmF0aGVyIHRoYW4gUmVhY3Qg'
    || 'Zm9yIHRoZSBzYW1lIHBoeXNpY2FsIHJlYXNvbiBwcm9tb3Rpb25fYmFyIGlzIC0tCiAgICBjb21wb25lbnRzLmh0bWwgaXMgYSBzYW5kYm94ZWQgY3Jvc3Mt'
    || 'b3JpZ2luIGlmcmFtZSB3aXRoIG5vIFNub3dmbGFrZSBzZXNzaW9uLAogICAgc28gYSBSZWFjdCBzbGlkZXIgY2Fubm90IGNhbGwgYSBwcm9jZWR1cmUuIFRo'
    || 'ZSBSZWFjdCBwYWdlIHNob3dzIHRoZSBydWxlcyBhbmQKICAgIHdoYXQgZWFjaCBvbmUgY29udHJpYnV0ZXM7IHRoaXMgaXMgd2hlcmUgdGhleSBjaGFuZ2Uu'
    || 'CgogICAgV0hZIFJFQUQtT05MWSBSQVRIRVIgVEhBTiBISURERU4uIFdoZW4gdGhlIGJ1aWxkIGlzIG5vdCBhdXRob3Jpc2VkIHRvIHJ1bgogICAgYWN0aW9u'
    || 'cywgdGhlIHJ1bGUgc2V0IGlzIHN0aWxsIHRoZSBwYXJ0IHdvcnRoIHNlZWluZyAtLSB0dW5hYmxlIG1hdGNoaW5nIGlzIHRoZQogICAgcHJvZHVjdC4gSGlk'
    || 'aW5nIHRoZSBwYW5lbCB3b3VsZCBtaXNyZXByZXNlbnQgaXQuIEFybWluZyBpdCB3b3VsZCBiZSB3b3JzZTogYXQKICAgIFNBTVBMRSB0aWVyIGEgcmVhZGVy'
    || 'IHdvdWxkIHR1bmUgdGhyZXNob2xkcyBhZ2FpbnN0IHNlZWRlZCByb3dzIGFuZCByZWFkIHRoZQogICAgcmVzdWx0IGFzIHRoZWlyIG93biBkYXRhLiBTbyB0'
    || 'aGUgdmFsdWVzIGFsd2F5cyByZW5kZXIsIGxhYmVsbGVkIGFzIGEgcHJlc2V0IHdoZW4KICAgIHRoZXkgY2Fubm90IGJlIGNoYW5nZWQsIGFuZCB0aGUgY29u'
    || 'dHJvbHMgYXJyaXZlIHdpdGggdGhlIGF1dGhvcmlzYXRpb24gdGhhdCBtYWtlcwogICAgdGhlbSBtZWFuIHNvbWV0aGluZy4KICAgICIiIgogICAgKHRpZXIs'
    || 'IGFsbG93X3JlYWwsIGFsbG93X3NhbXBsZSksIHJvd3MgPSBsb2FkX3J1bGVfY29uZmlnKHNlc3Npb24sIHRndCkKICAgIGlmIG5vdCByb3dzOgogICAgICAg'
    || 'IHJldHVybgoKICAgICMgVGhlIFNBTUUgc3BsaXQgcHJvbW90aW9uX2JhciBhcHBsaWVzLCBmb3IgdGhlIHNhbWUgcmVhc29uOiBTQU1QTEUgcnVucyBhZ2Fp'
    || 'bnN0CiAgICAjIHNlZWRlZCByb3dzIHRoaXMgc2NyaXB0IGNyZWF0ZWQsIGV2ZXJ5dGhpbmcgZWxzZSB0b3VjaGVzIHRoZSBjdXN0b21lcidzIG93bgogICAg'
    || 'IyBvYmplY3RzLiBBcHBseWluZyBhIHRocmVzaG9sZCBjYWxscyBSRUJVSUxEX1JFU09MVVRJT04sIHNvIGl0IGFuc3dlcnMgdG8gdGhlCiAgICAjIGFjdGlv'
    || 'biBhdXRob3Jpc2F0aW9ucyByYXRoZXIgdGhhbiB0byBhIHNlY29uZCwgcGFyYWxsZWwgbm90aW9uIG9mICJsaXZlIi4KICAgIGxpdmUgPSBhbGxvd19zYW1w'
    || 'bGUgaWYgdGllciA9PSAiU0FNUExFIiBlbHNlIGFsbG93X3JlYWwKICAgIHN0LmNhcHRpb24oIk1BVENISU5HIFJVTEVTIiArICgiIiBpZiBsaXZlIGVsc2Ug'
    || 'IiBcdTAwYjcgUFJFU0VULCBOT1QgWUVUIFRVTkFCTEUiKSkKICAgIGlmIG5vdCBsaXZlOgogICAgICAgIHdoeSA9ICgKICAgICAgICAgICAgIkFjdGlvbnMg'
    || 'YXJlIHN3aXRjaGVkIG9mZiBmb3IgdGhpcyBidWlsZCwgc28gdGhlc2UgYXJlIHRoZSBwcmVzZXQgcnVsZXMgIgogICAgICAgICAgICAiYXMgc2hpcHBlZC4g'
    || 'VGhleSBhcmUgc2hvd24gYmVjYXVzZSB0aGUgcnVsZSBzZXQgaXMgdGhlIHBhcnQgd29ydGggIgogICAgICAgICAgICAic2VlaW5nLCBhbmQgdGhleSBhcmUg'
    || 'bm90IGVkaXRhYmxlIGJlY2F1c2UgYXBwbHlpbmcgYSBjaGFuZ2UgY2FsbHMgYSAiCiAgICAgICAgICAgICJyZWJ1aWxkLiIpCiAgICAgICAgaWYgdGllciA9'
    || 'PSAiU0FNUExFIjoKICAgICAgICAgICAgd2h5ID0gKAogICAgICAgICAgICAgICAgIlRoaXMgYnVpbGQgcmFuIGF0IFNBTVBMRSB0aWVyLCBzbyB0aGVzZSBh'
    || 'cmUgdGhlIHByZXNldCBydWxlcyAiCiAgICAgICAgICAgICAgICAicnVubmluZyBvdmVyIHRoZSBidW5kbGVkIHNhbXBsZSByb3dzLiBUaGV5IGFyZSBzaG93'
    || 'biBiZWNhdXNlIHRoZSAiCiAgICAgICAgICAgICAgICAicnVsZSBzZXQgaXMgdGhlIHBhcnQgd29ydGggc2VlaW5nLCBhbmQgdGhleSBhcmUgbm90IGVkaXRh'
    || 'YmxlICIKICAgICAgICAgICAgICAgICJiZWNhdXNlIHR1bmluZyBhIHRocmVzaG9sZCBhZ2FpbnN0IHNlZWRlZCBkYXRhIHdvdWxkIHByb2R1Y2UgYSAiCiAg'
    || 'ICAgICAgICAgICAgICAibnVtYmVyIHRoYXQgZGVzY3JpYmVzIHRoZSBmaXh0dXJlIHJhdGhlciB0aGFuIHlvdXIgYWNjb3VudC4iKQogICAgICAgIGVsaWYg'
    || 'bm90IHRpZXI6CiAgICAgICAgICAgIHdoeSA9ICgKICAgICAgICAgICAgICAgICJUaGlzIGJ1aWxkJ3MgdGllciBjb3VsZCBub3QgYmUgcmVhZCwgc28gdGhl'
    || 'IGNvbnRyb2xzIHN0YXkgIgogICAgICAgICAgICAgICAgInJlYWQtb25seSByYXRoZXIgdGhhbiBhcm1pbmcgYSByZWJ1aWxkIGFnYWluc3QgYSBidWlsZCB3'
    || 'ZSBjYW5ub3QgIgogICAgICAgICAgICAgICAgImlkZW50aWZ5LiBUaGUgdmFsdWVzIGJlbG93IGFyZSB0aGUgcnVsZXMgYXMgc2hpcHBlZC4iKQogICAgICAg'
    || 'IHN0LmNhcHRpb24od2h5ICsgIiBFbmFibGUgYWN0aW9ucyBhbmQgcmUtcnVuIGF0IExJTUlURUQgb3IgUFJPRFVDVElPTiB0aWVyICIKICAgICAgICAgICAg'
    || 'ICAgICAgICAgICAgICJhbmQgdGhlIGNvbnRyb2xzIGJlbG93IGJlY29tZSBsaXZlLiIpCgogICAgZGlydHkgPSBhbnkoYm9vbChyLmdldCgiSVNfTU9ESUZJ'
    || 'RUQiKSkgZm9yIHIgaW4gcm93cykKICAgIGF0X3Jpc2sgPSBzdW0oaW50KHIuZ2V0KCJTT0xFX0xJTktTIikgb3IgMCkKICAgICAgICAgICAgICAgICAgZm9y'
    || 'IHIgaW4gcm93cyBpZiBub3QgYm9vbChyLmdldCgiSVNfQUNUSVZFIikpKQogICAgaWYgZGlydHk6CiAgICAgICAgc3QuY2FwdGlvbigiQ0hBTkdFRCBGUk9N'
    || 'IERFRkFVTFRTIFx1MDBiNyByZWJ1aWxkIHRvIGFwcGx5IikKICAgIGlmIGF0X3Jpc2s6CiAgICAgICAgc3QuY2FwdGlvbigiRXN0aW1hdGVkIGltcGFjdDog'
    || 'YWJvdXQgIiArIGYie2F0X3Jpc2s6LH0iCiAgICAgICAgICAgICAgICAgICArICIgY29ubmVjdGlvbnMgd291bGQgYmUgcmVtb3ZlZCwgYmVjYXVzZSB0aGV5'
    || 'IGFyZSBoZWxkIGJ5IGEgIgogICAgICAgICAgICAgICAgICAgICAicnVsZSB0aGF0IGlzIGN1cnJlbnRseSBzd2l0Y2hlZCBvZmYuIikKCiAgICBncm91cCA9'
    || 'IE5vbmUKICAgIGZvciByIGluIHJvd3M6CiAgICAgICAgZyA9IHN0cihyLmdldCgiR1JPVVBfTEFCRUwiKSBvciAiIikKICAgICAgICBpZiBnICE9IGdyb3Vw'
    || 'OgogICAgICAgICAgICBncm91cCA9IGcKICAgICAgICAgICAgc3QuY2FwdGlvbihnLnVwcGVyKCkpCiAgICAgICAgcmlkID0gc3RyKHIuZ2V0KCJSVUxFX0lE'
    || 'Iikgb3IgIiIpCiAgICAgICAgbGFiZWwgPSBzdHIoci5nZXQoIlBMQUlOX0xBQkVMIikgb3IgcmlkKQogICAgICAgIGFjdGl2ZSA9IGJvb2woci5nZXQoIklT'
    || 'X0FDVElWRSIpKQogICAgICAgIHRociA9IHIuZ2V0KCJUSFJFU0hPTEQiKQogICAgICAgIGVkaXRhYmxlID0gYm9vbChyLmdldCgiVEhSRVNIT0xEX0VESVRB'
    || 'QkxFIikpIGFuZCB0aHIgaXMgbm90IE5vbmUKICAgICAgICBsaW5rcyA9IGludChyLmdldCgiTElOS1MiKSBvciAwKQogICAgICAgIHNvbGUgPSBpbnQoci5n'
    || 'ZXQoIlNPTEVfTElOS1MiKSBvciAwKQoKICAgICAgICBjMSwgYzIsIGMzID0gc3QuY29sdW1ucyhbMywgMiwgMl0pCiAgICAgICAgd2l0aCBjMToKICAgICAg'
    || 'ICAgICAgaWYgbGl2ZToKICAgICAgICAgICAgICAgIG5ld19hY3RpdmUgPSBzdC50b2dnbGUobGFiZWwsIHZhbHVlPWFjdGl2ZSwga2V5PSJyYV8iICsgcmlk'
    || 'KQogICAgICAgICAgICBlbHNlOgogICAgICAgICAgICAgICAgc3QuY2FwdGlvbigoIk9OICAiIGlmIGFjdGl2ZSBlbHNlICJPRkYgIikgKyBsYWJlbCkKICAg'
    || 'ICAgICAgICAgICAgIG5ld19hY3RpdmUgPSBhY3RpdmUKICAgICAgICAgICAgaWYgci5nZXQoIlBMQUlOX0RFU0MiKToKICAgICAgICAgICAgICAgIHN0LmNh'
    || 'cHRpb24oc3RyKHJbIlBMQUlOX0RFU0MiXSkpCiAgICAgICAgd2l0aCBjMjoKICAgICAgICAgICAgbmV3X3RociA9IHRocgogICAgICAgICAgICBpZiBlZGl0'
    || 'YWJsZToKICAgICAgICAgICAgICAgIGlmIGxpdmU6CiAgICAgICAgICAgICAgICAgICAgbmV3X3RociA9IHN0LnNsaWRlcigKICAgICAgICAgICAgICAgICAg'
    || 'ICAgICAgIkhvdyBzaW1pbGFyIGlzIGNsb3NlIGVub3VnaCIsIG1pbl92YWx1ZT01MCwgbWF4X3ZhbHVlPTEwMCwKICAgICAgICAgICAgICAgICAgICAgICAg'
    || 'dmFsdWU9aW50KHJvdW5kKGZsb2F0KHRocikgKiAxMDApKSwgc3RlcD0xLCBrZXk9InJ0XyIgKyByaWQsCiAgICAgICAgICAgICAgICAgICAgICAgIGhlbHA9'
    || 'ImhpZ2hlciBpcyBzdHJpY3RlciBcdTIwMTQgZmV3ZXIsIHNhZmVyIG1hdGNoZXMiKQogICAgICAgICAgICAgICAgICAgIG5ld190aHIgPSBuZXdfdGhyIC8g'
    || 'MTAwLjAKICAgICAgICAgICAgICAgIGVsc2U6CiAgICAgICAgICAgICAgICAgICAgc3QuY2FwdGlvbigic2ltaWxhcml0eSAiICsgc3RyKGludChyb3VuZChm'
    || 'bG9hdCh0aHIpICogMTAwKSkpICsgIiUiKQogICAgICAgIHdpdGggYzM6CiAgICAgICAgICAgIHN0LmNhcHRpb24oZiJ7bGlua3M6LH0iICsgIiBjb25uZWN0'
    || 'aW9ucyBtYWRlIikKICAgICAgICAgICAgaWYgc29sZToKICAgICAgICAgICAgICAgIHN0LmNhcHRpb24oZiJ7c29sZTosfSIgKyAiIHdvdWxkIGJlIGxvc3Qg'
    || 'd2l0aG91dCBpdCIpCgogICAgICAgICMgT25lIENBTEwgcGVyIGNoYW5nZWQgcnVsZSwgYW5kIG9ubHkgb24gYSByZWFsIGNoYW5nZS4gV3JpdGluZyBvbiBl'
    || 'dmVyeQogICAgICAgICMgcmVydW4gd291bGQgaXNzdWUgYSBwcm9jZWR1cmUgY2FsbCBwZXIgcnVsZSBwZXIgcmVwYWludCwgd2hpY2ggaXMgYm90aCBhCiAg'
    || 'ICAgICAgIyBjb3N0IGFuZCBhIGZhbHNlIGF1ZGl0IHRyYWlsIC0tIHRoZSBjb25maWcgaGlzdG9yeSB3b3VsZCByZWNvcmQgZWRpdHMKICAgICAgICAjIG5v'
    || 'Ym9keSBtYWRlLgogICAgICAgIGlmIGxpdmUgYW5kIChuZXdfYWN0aXZlICE9IGFjdGl2ZSBvcgogICAgICAgICAgICAgICAgICAgICAoZWRpdGFibGUgYW5k'
    || 'IG5ld190aHIgaXMgbm90IE5vbmUgYW5kIHRociBpcyBub3QgTm9uZQogICAgICAgICAgICAgICAgICAgICAgYW5kIGFicyhmbG9hdChuZXdfdGhyKSAtIGZs'
    || 'b2F0KHRocikpID4gMWUtOSkpOgogICAgICAgICAgICB0cnk6CiAgICAgICAgICAgICAgICBzZXNzaW9uLnNxbCgiQ0FMTCAiICsgdGd0ICsgIi5TRVRfUlVM'
    || 'RV9DT05GSUcoPywgPywgPykiLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgcGFyYW1zPVtyaWQsIGJvb2wobmV3X2FjdGl2ZSksCiAgICAgICAgICAg'
    || 'ICAgICAgICAgICAgICAgICAgICAgICAgIGZsb2F0KG5ld190aHIpIGlmIG5ld190aHIgaXMgbm90IE5vbmUgZWxzZSBOb25lXSkuY29sbGVjdCgpCiAgICAg'
    || 'ICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZXhjOgogICAgICAgICAgICAgICAgc3QuZXJyb3IoIkNvdWxkIG5vdCBzYXZlICIgKyByaWQgKyAiOiAiICsg'
    || 'c3RyKGV4YyksCiAgICAgICAgICAgICAgICAgICAgICAgICBpY29uPSI6bWF0ZXJpYWwvZXJyb3I6IikKICAgICAgICAgICAgZWxzZToKICAgICAgICAgICAg'
    || 'ICAgIGludmFsaWRhdGVfcGFuZWxfY2FjaGUoKQogICAgICAgICAgICAgICAgc3QucmVydW4oKQoKICAgIGlmIG5vdCBsaXZlOgogICAgICAgIHN0LmRpdmlk'
    || 'ZXIoKQogICAgICAgIHJldHVybgoKICAgIGIxLCBiMiA9IHN0LmNvbHVtbnMoWzEsIDFdKQogICAgd2l0aCBiMToKICAgICAgICBpZiBzdC5idXR0b24oIlJl'
    || 'c3RvcmUgZGVmYXVsdHMiLCBrZXk9ImNmZ19yZXNldCIpOgogICAgICAgICAgICB0cnk6CiAgICAgICAgICAgICAgICBvdXQgPSBzZXNzaW9uLnNxbCgiQ0FM'
    || 'TCAiICsgdGd0ICsgIi5SRVNFVF9SVUxFX0RFRkFVTFRTKCkiKS5jb2xsZWN0KClbMF1bMF0KICAgICAgICAgICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBleGM6'
    || 'CiAgICAgICAgICAgICAgICBvdXQgPSAiRkFJTEVEIHRvIHJlc3RvcmUgZGVmYXVsdHM6ICIgKyBzdHIoZXhjKQogICAgICAgICAgICBzdC5zZXNzaW9uX3N0'
    || 'YXRlWyJjZmdfcmVzdWx0Il0gPSBzdHIob3V0KQogICAgICAgICAgICBpbnZhbGlkYXRlX3BhbmVsX2NhY2hlKCkKICAgICAgICAgICAgc3QucmVydW4oKQog'
    || 'ICAgd2l0aCBiMjoKICAgICAgICBpZiBzdC5idXR0b24oIlJlYnVpbGQgcmVjb3JkcyIsIGtleT0iY2ZnX3JlYnVpbGQiLCB0eXBlPSJwcmltYXJ5Iik6CiAg'
    || 'ICAgICAgICAgIHRyeToKICAgICAgICAgICAgICAgIG91dCA9IHNlc3Npb24uc3FsKCJDQUxMICIgKyB0Z3QgKyAiLlJFQlVJTERfUkVTT0xVVElPTigpIiku'
    || 'Y29sbGVjdCgpWzBdWzBdCiAgICAgICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZXhjOgogICAgICAgICAgICAgICAgb3V0ID0gIkZBSUxFRCB0byByZWJ1'
    || 'aWxkOiAiICsgc3RyKGV4YykKICAgICAgICAgICAgc3Quc2Vzc2lvbl9zdGF0ZVsiY2ZnX3Jlc3VsdCJdID0gc3RyKG91dCkKICAgICAgICAgICAgaW52YWxp'
    || 'ZGF0ZV9wYW5lbF9jYWNoZSgpCiAgICAgICAgICAgIHN0LnJlcnVuKCkKCiAgICBtc2cgPSBzdHIoc3Quc2Vzc2lvbl9zdGF0ZS5nZXQoImNmZ19yZXN1bHQi'
    || 'KSBvciAiIikKICAgIGlmIG1zZzoKICAgICAgICBpZiBtc2cuc3RhcnRzd2l0aCgiRE9ORSIpIG9yIG1zZy5zdGFydHN3aXRoKCJSRUJVSUxUIikgb3IgbXNn'
    || 'LnN0YXJ0c3dpdGgoIlJFU1RPUkVEIik6CiAgICAgICAgICAgIHN0LnN1Y2Nlc3MobXNnLCBpY29uPSI6bWF0ZXJpYWwvY2hlY2s6IikKICAgICAgICBlbGlm'
    || 'IG1zZy5zdGFydHN3aXRoKCJSRUZVU0VEIik6CiAgICAgICAgICAgIHN0Lndhcm5pbmcobXNnLCBpY29uPSI6bWF0ZXJpYWwvYmxvY2s6IikKICAgICAgICBl'
    || 'bHNlOgogICAgICAgICAgICBzdC5lcnJvcihtc2csIGljb249IjptYXRlcmlhbC9lcnJvcjoiKQogICAgc3QuZGl2aWRlcigpCgoKZGVmIGxvYWRfYWN0aW9u'
    || 'cyhzZXNzaW9uLCB0Z3Q6IHN0cik6CiAgICAiIiIoKGFsbG93X3JlYWwsIGFsbG93X3NhbXBsZSksIHJvd3MpLiBSZXR1cm5zICgoRmFsc2UsIEZhbHNlKSwg'
    || 'W10pIGZvciBhbnkKICAgIGJ1aWxkIHdpdGhvdXQgdGhlIGZyYW1ld29yay4KCiAgICBXcmFwcGVkIGJlY2F1c2UgYSBzY2hlbWEgYnVpbHQgYnkgYW4gb2xk'
    || 'ZXIgYXJ0aWZhY3QgaGFzIG5vIFZfQUNUSU9OUywgYW5kIHRoZQogICAgYXBwIG11c3Qgc3RpbGwgd29yayBhZ2FpbnN0IGl0IHJhdGhlciB0aGFuIHNob3dp'
    || 'bmcgYSB0cmFjZWJhY2sgd2hlcmUgdGhlCiAgICBwcm9tb3Rpb24gYmFyIHdvdWxkIGJlLgogICAgIiIiCiAgICB0cnk6CiAgICAgICAgcm93cyA9IFtyLmFz'
    || 'X2RpY3QoKSBmb3IgciBpbiBzZXNzaW9uLnNxbCgKICAgICAgICAgICAgIlNFTEVDVCBDT0RFLCBMQUJFTCwgVElFUiwgRUZGRUNULCBVTkRPLCBFU1RfQ1JF'
    || 'RElUUywgRVNUX0JBU0lTLCAiCiAgICAgICAgICAgICJTVEFURU1FTlRTLCBVTkRPX1NUQVRFTUVOVFMsIFRJTUVTX1JVTiwgVElNRVNfVU5ET05FLCBMQVNU'
    || 'X1JVTl9BVCBGUk9NICIgKyB0Z3QgKyAiLlZfQUNUSU9OUyIpLmNvbGxlY3QoKV0KICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgcmV0dXJuIChGYWxz'
    || 'ZSwgRmFsc2UpLCBbXQogICAgIyBUd28gYXV0aG9yaXNhdGlvbnMsIG5vdCBvbmUuIEFMTE9XX0FDVElPTlMgZ292ZXJucyBMSU1JVEVEIGFuZCBQUk9EVUNU'
    || 'SU9OIC0tCiAgICAjIGFueXRoaW5nIHRoYXQgcmVhZHMgb3Igd3JpdGVzIHJlYWwgZGF0YS4gQUxMT1dfU0FNUExFX0FDVElPTlMgZ292ZXJucyBTQU1QTEUs'
    || 'CiAgICAjIGFuZCBkZWZhdWx0cyBUUlVFLCBzbyBhIGZyZXNobHkgaW5zdGFsbGVkIGFwcCBoYXMgc29tZXRoaW5nIHRoYXQgd29ya3MuCiAgICAjCiAgICAj'
    || 'IFRoaXMgbWlycm9ycyBSVU5fQUNUSU9OIHJhdGhlciB0aGFuIGRlY2lkaW5nIGFueXRoaW5nOiB0aGUgcHJvY2VkdXJlIGVuZm9yY2VzCiAgICAjIHRoZSBz'
    || 'YW1lIHNwbGl0IHNlcnZlci1zaWRlIGFuZCByZWZ1c2VzIHJlZ2FyZGxlc3Mgb2Ygd2hhdCB0aGlzIHJldHVybnMuIElmIHRoZQogICAgIyB0d28gZXZlciBk'
    || 'aXNhZ3JlZSB0aGUgcHJvYyB3aW5zLCB3aGljaCBpcyB0aGUgY29ycmVjdCBkaXJlY3Rpb24gLS0gYSBkaXNhYmxlZAogICAgIyBidXR0b24gaXMgYSBudWlz'
    || 'YW5jZSwgYSBidXR0b24gdGhhdCBhcHBlYXJzIGxpdmUgYW5kIHRoZW4gcmVmdXNlcyBpcyBhIGxpZS4KICAgICMgU0FNUExFX0FDVElPTlNfRU5BQkxFRCBp'
    || 'cyByZWFkIGRlZmVuc2l2ZWx5IGJlY2F1c2UgYSBzY2hlbWEgYnVpbHQgYnkgYW4gb2xkZXIKICAgICMgZmlsZSB3aWxsIG5vdCBoYXZlIHRoZSBjb2x1bW4u'
    || 'CiAgICB0cnk6CiAgICAgICAgZW5hYmxlZCA9IGJvb2woc2Vzc2lvbi5zcWwoCiAgICAgICAgICAgICJTRUxFQ1QgQUNUSU9OU19FTkFCTEVEIEZST00gIiAr'
    || 'IHRndCArICIuVl9CVUlMRF9DT05URVhUIgogICAgICAgICkuY29sbGVjdCgpWzBdWzBdKQogICAgZXhjZXB0IEV4Y2VwdGlvbjoKICAgICAgICBlbmFibGVk'
    || 'ID0gRmFsc2UKICAgIHRyeToKICAgICAgICBzYW1wbGVfZW5hYmxlZCA9IGJvb2woc2Vzc2lvbi5zcWwoCiAgICAgICAgICAgICJTRUxFQ1QgQ09BTEVTQ0Uo'
    || 'U0FNUExFX0FDVElPTlNfRU5BQkxFRCwgRkFMU0UpIEZST00gIiArIHRndCArICIuVl9CVUlMRF9DT05URVhUIgogICAgICAgICkuY29sbGVjdCgpWzBdWzBd'
    || 'KQogICAgZXhjZXB0IEV4Y2VwdGlvbjoKICAgICAgICBzYW1wbGVfZW5hYmxlZCA9IEZhbHNlCiAgICByZXR1cm4gKGVuYWJsZWQsIHNhbXBsZV9lbmFibGVk'
    || 'KSwgcm93cwoKCmRlZiBsb2FkX3ByZWZpeChzZXNzaW9uLCB0Z3Q6IHN0cikgLT4gc3RyOgogICAgIiIiVGhlIHBlci1zb2x1dGlvbiBzZXR0aW5nIHByZWZp'
    || 'eCwgb3IgJycgaWYgdGhpcyBidWlsZCBwcmVkYXRlcyB0aGUgY29sdW1uLgoKICAgIEtlcHQgc2VwYXJhdGUgZnJvbSBsb2FkX2FjdGlvbnMgcmF0aGVyIHRo'
    || 'YW4gd2lkZW5pbmcgaXRzIHJldHVybiwgYmVjYXVzZQogICAgZXZlcnkgY2FsbGVyIG9mIHRoYXQgcGFpci1vZi10dXBsZXMgc2lnbmF0dXJlIHdvdWxkIGhh'
    || 'dmUgdG8gY2hhbmdlIGFuZCBub25lCiAgICBvZiB0aGVtIHdhbnQgdGhlIHByZWZpeC4gVGhpcyBleGlzdHMgc28gdGhlIGFwcCBjYW4gcHJpbnQgdGhlIGxp'
    || 'bmUgeW91IHdvdWxkCiAgICBhY3R1YWxseSBlZGl0IGluc3RlYWQgb2YgYSBzZXR0aW5nIG5hbWUgdGhhdCBhcHBlYXJzIGluIG5vIGZpbGUuCiAgICAiIiIK'
    || 'ICAgIHRyeToKICAgICAgICByZXR1cm4gc3RyKHNlc3Npb24uc3FsKAogICAgICAgICAgICAiU0VMRUNUIFNFVFRJTkdfUFJFRklYIEZST00gIiArIHRndCAr'
    || 'ICIuVl9CVUlMRF9DT05URVhUIgogICAgICAgICkuY29sbGVjdCgpWzBdWzBdIG9yICIiKQogICAgZXhjZXB0IEV4Y2VwdGlvbjoKICAgICAgICByZXR1cm4g'
    || 'IiIKCgpkZWYgbG9hZF9oZWFkbGluZShzZXNzaW9uLCB0Z3Q6IHN0cik6CiAgICAiIiJUaGUgb25lLWxpbmUgbW9udGhseSBydW4gcmF0ZSwgb3IgTm9uZS4K'
    || 'CiAgICBXcmFwcGVkIGZvciB0aGUgc2FtZSByZWFzb24gbG9hZF9hY3Rpb25zIGlzOiBhIHNjaGVtYSBidWlsdCBieSBhbiBvbGRlcgogICAgYXJ0aWZhY3Qg'
    || 'aGFzIG5vIFZfUlVOX1JBVEVfSEVBRExJTkUsIGFuZCB0aGUgYXBwIG11c3Qgc3RpbGwgd29yayBhZ2FpbnN0IGl0CiAgICByYXRoZXIgdGhhbiBzaG93aW5n'
    || 'IGEgdHJhY2ViYWNrIHdoZXJlIHRoZSBzdGFuZGluZyBjb3N0IHdvdWxkIGJlLgoKICAgIFRoaXMgaXMgdGhlIG9ubHkgc3VyZmFjZSB0aGF0IHByaW50cyBp'
    || 'dC4gVGhlIHZpZXcgaGFzIGV4aXN0ZWQgZm9yIGV2ZXJ5CiAgICBidWlsZCBmb3IgYSB3aGlsZSBhbmQgd2FzIHJlYWQgYnkgbm90aGluZyBidXQgdGhlIHRl'
    || 'c3QgaGFybmVzcywgc28gdGhlCiAgICBzZW50ZW5jZSB3cml0dGVuIGZvciB0aGUgYXBwIHRvIHByaW50IHdhcyBwcmludGVkIGJ5IG5vYm9keS4KICAgICIi'
    || 'IgogICAgdHJ5OgogICAgICAgIHJvd3MgPSBzZXNzaW9uLnNxbCgKICAgICAgICAgICAgIlNFTEVDVCBIRUFETElORSwgRVNUX0NSRURJVFNfUEVSX01PTlRI'
    || 'IEZST00gIiArIHRndCArICIuVl9SVU5fUkFURV9IRUFETElORSIKICAgICAgICApLmNvbGxlY3QoKQogICAgZXhjZXB0IEV4Y2VwdGlvbjoKICAgICAgICBy'
    || 'ZXR1cm4gTm9uZQogICAgaWYgbm90IHJvd3M6CiAgICAgICAgcmV0dXJuIE5vbmUKICAgIHIgPSByb3dzWzBdLmFzX2RpY3QoKQogICAgcmV0dXJuIChzdHIo'
    || 'ci5nZXQoIkhFQURMSU5FIikgb3IgIiIpLCByLmdldCgiRVNUX0NSRURJVFNfUEVSX01PTlRIIikpCgoKZGVmIGxvYWRfYWN0aW9uX3BhcmFtcyhzZXNzaW9u'
    || 'LCB0Z3Q6IHN0cik6CiAgICAiIiJ7YWN0aW9uX2NvZGU6IFtwYXJhbSBkaWN0LCAuLi5dfS4gRW1wdHkgZGljdCBmb3IgYW55IGJ1aWxkIHdpdGhvdXQgcGFy'
    || 'YW1zLgoKICAgIFdyYXBwZWQgZm9yIHRoZSBzYW1lIHJlYXNvbiBsb2FkX2FjdGlvbnMgaXM6IGEgc2NoZW1hIGJ1aWx0IGJ5IGFuIG9sZGVyIGFydGlmYWN0'
    || 'CiAgICBoYXMgbm8gVl9BQ1RJT05fUEFSQU1TLCBhbmQgdGhlIGFwcCBtdXN0IGtlZXAgd29ya2luZyBhZ2FpbnN0IGl0IHJhdGhlciB0aGFuCiAgICBzaG93'
    || 'aW5nIGEgdHJhY2ViYWNrIHdoZXJlIHRoZSBwcm9tb3Rpb24gYmFyIHdvdWxkIGJlLiBBbiBlbXB0eSByZXN1bHQgaXMgdGhlCiAgICBub3JtYWwgY2FzZSAt'
    || 'LSBtb3N0IGFjdGlvbnMgdGFrZSBubyBwYXJhbWV0ZXJzIGFuZCByZW5kZXIgZXhhY3RseSBhcyBiZWZvcmUuCgogICAgRGVsaWJlcmF0ZWx5IE5PVCBmb2xk'
    || 'ZWQgaW50byBsb2FkX2FjdGlvbnMuIFRoYXQgZnVuY3Rpb24ncyBTRUxFQ1QgbGlzdCBpcyBpdHMKICAgIGNvbXBhdGliaWxpdHkgY29udHJhY3Qgd2l0aCBv'
    || 'bGRlciBzY2hlbWFzOyBhZGRpbmcgYSBjb2x1bW4gdG8gaXQgd291bGQgbWFrZSBldmVyeQogICAgYnVpbGQgd2l0aG91dCB0aGF0IGNvbHVtbiBmYWxsIGlu'
    || 'dG8gdGhlIGV4Y2VwdCBicmFuY2ggYW5kIGxvc2UgaXRzIHdob2xlIGFjdGlvbgogICAgYmFyLiBBIHNlcGFyYXRlLCBzZXBhcmF0ZWx5LXdyYXBwZWQgcmVh'
    || 'ZCBkZWdyYWRlcyB0byAibm8gcGFyYW1ldGVycyIgaW5zdGVhZC4KICAgICIiIgogICAgdHJ5OgogICAgICAgIHJvd3MgPSBbci5hc19kaWN0KCkgZm9yIHIg'
    || 'aW4gc2Vzc2lvbi5zcWwoCiAgICAgICAgICAgICJTRUxFQ1QgQ09ERSwgT1JESU5BTCwgUEFSQU1fTkFNRSwgTEFCRUwsIEtJTkQsIE9QVElPTlNfU1FMLCBP'
    || 'UFRJT05TLCAiCiAgICAgICAgICAgICJNSU5fVkFMVUUsIE1BWF9WQUxVRSwgSEVMUCBGUk9NICIgKyB0Z3QgKyAiLlZfQUNUSU9OX1BBUkFNUyAiCiAgICAg'
    || 'ICAgICAgICJPUkRFUiBCWSBDT0RFLCBPUkRJTkFMIikuY29sbGVjdCgpXQogICAgZXhjZXB0IEV4Y2VwdGlvbjoKICAgICAgICByZXR1cm4ge30KICAgIG91'
    || 'dCA9IHt9CiAgICBmb3IgciBpbiByb3dzOgogICAgICAgIG91dC5zZXRkZWZhdWx0KHN0cihyLmdldCgiQ09ERSIpIG9yICIiKSwgW10pLmFwcGVuZChyKQog'
    || 'ICAgcmV0dXJuIG91dAoKCmRlZiBhY3Rpb25fcGFyYW1fb3B0aW9ucyhzZXNzaW9uLCBwKSAtPiBsaXN0OgogICAgIiIiVGhlIGNob2ljZXMgdG8gT0ZGRVIg'
    || 'Zm9yIG9uZSBwYXJhbWV0ZXIuIERpc3BsYXkgb25seS4KCiAgICBUaGlzIGxpc3QgaXMgd2hhdCB0aGUgd2lkZ2V0IHNob3dzOyBpdCBpcyBOT1Qgd2hhdCBh'
    || 'dXRob3Jpc2VzIHRoZSB2YWx1ZS4gVGhlCiAgICBwcm9jZWR1cmUgcmUtcnVucyB0aGUgcmVnaXN0cnkncyBvd24gYWxsb3dlZF9zcWwgd2hlbiBpdCB2YWxp'
    || 'ZGF0ZXMsIHNvIGEgc3RhbGUgb3IKICAgIHRhbXBlcmVkIGxpc3QgaGVyZSBjYW5ub3Qgd2lkZW4gd2hhdCBhbiBhY3Rpb24gd2lsbCBhY2NlcHQgLS0gaXQg'
    || 'Y2FuIG9ubHkgZmFpbCB0bwogICAgb2ZmZXIgc29tZXRoaW5nIHRoZSBwcm9jZWR1cmUgd291bGQgaGF2ZSBwZXJtaXR0ZWQuIFRoYXQgYXN5bW1ldHJ5IGlz'
    || 'IGRlbGliZXJhdGU6CiAgICB0aGUgYXBwIGlzIGFsbG93ZWQgdG8gYmUgd3JvbmcgaW4gdGhlIGRpcmVjdGlvbiBvZiBvZmZlcmluZyB0b28gbGl0dGxlLgog'
    || 'ICAgIiIiCiAgICBvcHRzID0gcC5nZXQoIk9QVElPTlMiKQogICAgaWYgb3B0czoKICAgICAgICB0cnk6CiAgICAgICAgICAgIHJldHVybiBbc3RyKHYpIGZv'
    || 'ciB2IGluIChqc29uLmxvYWRzKG9wdHMpIGlmIGlzaW5zdGFuY2Uob3B0cywgc3RyKSBlbHNlIG9wdHMpXQogICAgICAgIGV4Y2VwdCBFeGNlcHRpb246CiAg'
    || 'ICAgICAgICAgIHBhc3MKICAgIHNxbCA9IHN0cihwLmdldCgiT1BUSU9OU19TUUwiKSBvciAiIikuc3RyaXAoKQogICAgaWYgbm90IHNxbDoKICAgICAgICBy'
    || 'ZXR1cm4gW10KICAgIHRyeToKICAgICAgICByZXR1cm4gW3N0cihyWzBdKSBmb3IgciBpbiBzZXNzaW9uLnNxbCgKICAgICAgICAgICAgIlNFTEVDVCBBTExP'
    || 'V0VEX1ZBTFVFIEZST00gKCIgKyBzcWwgKyAiKSBMSU1JVCAiICsgc3RyKFJPV19DQVApKS5jb2xsZWN0KCldCiAgICBleGNlcHQgRXhjZXB0aW9uOgogICAg'
    || 'ICAgICMgQSBicm9rZW4gb3B0aW9ucyBxdWVyeSBtdXN0IG5vdCB0YWtlIHRoZSB3aG9sZSBwcm9tb3Rpb24gYmFyIGRvd24gd2l0aCBpdC4KICAgICAgICAj'
    || 'IFJldHVybmluZyBub3RoaW5nIGxlYXZlcyB0aGUgZmllbGQgZW1wdHksIHRoZSBSdW4gYnV0dG9uIGRpc2FibGVkLCBhbmQgdGhlCiAgICAgICAgIyByZXN0'
    || 'IG9mIHRoZSBhY3Rpb25zIHVzYWJsZS4KICAgICAgICByZXR1cm4gW10KCgpkZWYgYWN0aW9uX3BhcmFtX3ZhbHVlcyhzZXNzaW9uLCBjb2RlOiBzdHIsIHBh'
    || 'cmFtczogbGlzdCk6CiAgICAiIiJSZW5kZXIgb25lIHdpZGdldCBwZXIgcGFyYW1ldGVyIGFuZCByZXR1cm4gKHZhbHVlcyBkaWN0LCBhbGxfc3VwcGxpZWQp'
    || 'LgoKICAgIFBsYWNlZCBJTlNJREUgdGhlIGFybWVkIGNvbmZpcm1hdGlvbiBibG9jayBieSB0aGUgY2FsbGVyLCBub3Qgb24gdGhlIGFjdGlvbiBjYXJkLgog'
    || 'ICAgVHdvIHJlYXNvbnMuIFRoZSB2YWx1ZXMgbXVzdCBub3QgYmUgYWJsZSB0byBjaGFuZ2UgYmV0d2VlbiBhcm1pbmcgYW5kIGNvbmZpcm1pbmcKICAgIC0t'
    || 'IHRoZSB0eXBlZCBjb2RlIGNvbmZpcm1zIGEgc3BlY2lmaWMgY2hhbmdlLCBzbyB0aGUgY2hhbmdlIGhhcyB0byBiZSBzZXR0bGVkCiAgICBiZWZvcmUgaXQg'
    || 'aXMgdHlwZWQuIEFuZCBpdCBrZWVwcyB0aGUgdHlwZWQgY29uZmlybWF0aW9uIGFzIHRoZSBnZW51aW5lIGxhc3Qgc3RlcAogICAgcmF0aGVyIHRoYW4gb25l'
    || 'IGZpZWxkIGFtb25nIHNldmVyYWwuCiAgICAiIiIKICAgIHZhbHMgPSB7fQogICAgbWlzc2luZyA9IEZhbHNlCiAgICBmb3IgcCBpbiBwYXJhbXM6CiAgICAg'
    || 'ICAgbmFtZSA9IHN0cihwLmdldCgiUEFSQU1fTkFNRSIpIG9yICIiKQogICAgICAgIGxhYmVsID0gc3RyKHAuZ2V0KCJMQUJFTCIpIG9yIG5hbWUpCiAgICAg'
    || 'ICAga2luZCA9IHN0cihwLmdldCgiS0lORCIpIG9yICJJREVOVCIpLnVwcGVyKCkKICAgICAgICBrZXkgPSAicGFyYW1fIiArIGNvZGUgKyAiXyIgKyBuYW1l'
    || 'CiAgICAgICAgaGVscF90eHQgPSBzdHIocC5nZXQoIkhFTFAiKSBvciAiIikgb3IgTm9uZQogICAgICAgIGlmIGtpbmQgPT0gIk5VTUJFUiI6CiAgICAgICAg'
    || 'ICAgIGxvID0gcC5nZXQoIk1JTl9WQUxVRSIpCiAgICAgICAgICAgIGhpID0gcC5nZXQoIk1BWF9WQUxVRSIpCiAgICAgICAgICAgIHYgPSBzdC5udW1iZXJf'
    || 'aW5wdXQoCiAgICAgICAgICAgICAgICBsYWJlbCwga2V5PWtleSwgaGVscD1oZWxwX3R4dCwKICAgICAgICAgICAgICAgIG1pbl92YWx1ZT1mbG9hdChsbykg'
    || 'aWYgbG8gaXMgbm90IE5vbmUgZWxzZSBOb25lLAogICAgICAgICAgICAgICAgbWF4X3ZhbHVlPWZsb2F0KGhpKSBpZiBoaSBpcyBub3QgTm9uZSBlbHNlIE5v'
    || 'bmUsCiAgICAgICAgICAgICAgICB2YWx1ZT1mbG9hdChsbykgaWYgbG8gaXMgbm90IE5vbmUgZWxzZSAwLjAsCiAgICAgICAgICAgICAgICBzdGVwPTEuMCkK'
    || 'ICAgICAgICAgICAgIyBFbWl0IHdob2xlIG51bWJlcnMgd2l0aG91dCBhIHRyYWlsaW5nIC4wOiBBUkNISVZFX0ZPUl9EQVlTID0gOTAuMCBpcyBub3QKICAg'
    || 'ICAgICAgICAgIyB2YWxpZCBpbiB0aGUgRERMIGNsYXVzZSB0aGlzIGxhbmRzIGluLgogICAgICAgICAgICB2YWxzW25hbWVdID0gc3RyKGludCh2KSkgaWYg'
    || 'ZmxvYXQodikuaXNfaW50ZWdlcigpIGVsc2Ugc3RyKHYpCiAgICAgICAgICAgIGNvbnRpbnVlCiAgICAgICAgY2hvaWNlcyA9IGFjdGlvbl9wYXJhbV9vcHRp'
    || 'b25zKHNlc3Npb24sIHApCiAgICAgICAgaWYgY2hvaWNlczoKICAgICAgICAgICAgIyBpbmRleD1Ob25lIHNvIG5vdGhpbmcgaXMgcHJlLXNlbGVjdGVkLiBB'
    || 'IHByZS1maWxsZWQgdGFyZ2V0IGlzIGhvdyBzb21lb25lCiAgICAgICAgICAgICMgcnVucyBhIGNoYW5nZSBhZ2FpbnN0IHdoYXRldmVyIGhhcHBlbmVkIHRv'
    || 'IHNvcnQgZmlyc3QuCiAgICAgICAgICAgIHYgPSBzdC5zZWxlY3Rib3gobGFiZWwsIGNob2ljZXMsIGluZGV4PU5vbmUsIGtleT1rZXksIGhlbHA9aGVscF90'
    || 'eHQsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgcGxhY2Vob2xkZXI9IkNob29zZSAiICsgbGFiZWwubG93ZXIoKSkKICAgICAgICAgICAgaWYgdiBp'
    || 'cyBOb25lOgogICAgICAgICAgICAgICAgbWlzc2luZyA9IFRydWUKICAgICAgICAgICAgZWxzZToKICAgICAgICAgICAgICAgIHZhbHNbbmFtZV0gPSBzdHIo'
    || 'dikKICAgICAgICBlbGlmIHAuZ2V0KCJGUkVFRk9STSIpOgogICAgICAgICAgICAjIEEgbmFtZSBiZWluZyBDUkVBVEVEIGNhbm5vdCBiZSBjaGVja2VkIGFn'
    || 'YWluc3QgYSBsaXN0IG9mIHRoaW5ncyB0aGF0CiAgICAgICAgICAgICMgYWxyZWFkeSBleGlzdCwgc28gdGhpcyBvbmUgaXMgdHlwZWQuIEl0IGlzIG5vdCB1'
    || 'bnZhbGlkYXRlZDogdGhlIHByb2NlZHVyZQogICAgICAgICAgICAjIHN0aWxsIGFwcGxpZXMgdGhlIGlkZW50aWZpZXIgc2hhcGUgZ2F0ZSwgc28gYW55dGhp'
    || 'bmcgY2FycnlpbmcgYSBxdW90ZSwgYQogICAgICAgICAgICAjIHNwYWNlIG9yIGEgc3RhdGVtZW50IHRlcm1pbmF0b3IgaXMgcmVmdXNlZCBzZXJ2ZXItc2lk'
    || 'ZS4KICAgICAgICAgICAgdiA9IHN0LnRleHRfaW5wdXQobGFiZWwsIGtleT1rZXksIGhlbHA9aGVscF90eHQpCiAgICAgICAgICAgIGlmIG5vdCBzdHIodiBv'
    || 'ciAiIikuc3RyaXAoKToKICAgICAgICAgICAgICAgIG1pc3NpbmcgPSBUcnVlCiAgICAgICAgICAgIGVsc2U6CiAgICAgICAgICAgICAgICB2YWxzW25hbWVd'
    || 'ID0gc3RyKHYpLnN0cmlwKCkKICAgICAgICBlbHNlOgogICAgICAgICAgICBzdC5jYXB0aW9uKGxhYmVsICsgIiDigJQgbm8gcGVybWl0dGVkIHZhbHVlcyBh'
    || 'cmUgYXZhaWxhYmxlIGZvciB0aGlzIGJ1aWxkLCAiCiAgICAgICAgICAgICAgICAgICAgICAgInNvIHRoaXMgYWN0aW9uIGNhbm5vdCBydW4uIE5vdGhpbmcg'
    || 'aXMgc3dpdGNoZWQgb2ZmOyB0aGVyZSBpcyAiCiAgICAgICAgICAgICAgICAgICAgICAgInNpbXBseSBub3RoaW5nIGl0IGNvdWxkIGxlZ2FsbHkgYmUgcG9p'
    || 'bnRlZCBhdC4iKQogICAgICAgICAgICBtaXNzaW5nID0gVHJ1ZQogICAgcmV0dXJuIHZhbHMsIG5vdCBtaXNzaW5nCgoKZGVmIHByb21vdGlvbl9iYXIoc2Vz'
    || 'c2lvbiwgdGd0OiBzdHIpIC0+IE5vbmU6CiAgICAiIiJUaGUgb25lIHBsYWNlIGluIHRoZSBhcHAgdGhhdCBjYW4gY2hhbmdlIHRoZSBhY2NvdW50LgoKICAg'
    || 'IE5hdGl2ZSBTdHJlYW1saXQgcmF0aGVyIHRoYW4gcGFydCBvZiB0aGUgUmVhY3QgcGFnZSwgYW5kIG5vdCBieSBwcmVmZXJlbmNlOgogICAgdGhlIGJ1bmRs'
    || 'ZSBydW5zIGluc2lkZSBjb21wb25lbnRzLmh0bWwsIHdoaWNoIGlzIGEgc2FuZGJveGVkIGNyb3NzLW9yaWdpbgogICAgaWZyYW1lIHdpdGggbm8gU25vd2Zs'
    || 'YWtlIHNlc3Npb24sIHNvIGEgUmVhY3QgYnV0dG9uIHBoeXNpY2FsbHkgY2Fubm90IGV4ZWN1dGUKICAgIGFueXRoaW5nLiBUaGUgYmlkaXJlY3Rpb25hbCBh'
    || 'bHRlcm5hdGl2ZSAoc3QuY29tcG9uZW50cy52MikgbmVlZHMgU3RyZWFtbGl0CiAgICAxLjU3KywgYW5kIHdhcmVob3VzZSBydW50aW1lcyBjYXAgYXQgMS41'
    || 'Mi4yLiBTbyB0aGUgZGlzcGxheSBpcyBSZWFjdCBhbmQgdGhlCiAgICBjb250cm9scyBhcmUgU3RyZWFtbGl0LCBzdHlsZWQgdG8gc2l0IHdpdGggaXQuCgog'
    || 'ICAgRGVsaWJlcmF0ZWx5IHVzZXMgbm8gc3QubWFya2Rvd246IHRoZSBob3N0IGNoZWNrIHRyZWF0cyBzdHJheSBtYXJrZG93biBhcwogICAgcGFnZSBjb250'
    || 'ZW50IGxlYWtpbmcgb3V0c2lkZSB0aGUgY29tcG9uZW50LCB3aGljaCBpcyBob3cgYSBzcGxpY2VkIGRvY3N0cmluZwogICAgb25jZSBzaGlwcGVkIHRoZSB3'
    || 'aG9sZSBhcHAgYXMgYSB0cmFjZWJhY2suIFdpZGdldHMgYXJlIGludGVudGlvbmFsIGFuZAogICAgZXhlbXB0OyBwcm9zZSBpcyBub3QuCiAgICAiIiIKICAg'
    || 'IChhbGxvd19yZWFsLCBhbGxvd19zYW1wbGUpLCByb3dzID0gbG9hZF9hY3Rpb25zKHNlc3Npb24sIHRndCkKCiAgICAjIFRoZSBzdGFuZGluZyBjb3N0IHBy'
    || 'aW50cyB3aGV0aGVyIG9yIG5vdCB0aGlzIGJ1aWxkIHJlZ2lzdGVyZWQgYW55IGFjdGlvbnMsCiAgICAjIGFuZCBCRUZPUkUgdGhlbSwgYmVjYXVzZSBpdCBp'
    || 'cyB0aGUgcmVjdXJyaW5nIG51bWJlci4gRWFjaCBidXR0b24gYmVsb3cKICAgICMgY29zdHMgc29tZXRoaW5nIE9OQ0U7IHRoaXMgaXMgd2hhdCB0aGUgYnVp'
    || 'bGQgY29zdHMgZXZlcnkgbW9udGggaWYgbm9ib2R5CiAgICAjIHRvdWNoZXMgaXQgYWdhaW4uIERlbGliZXJhdGVseSBub3Qgc3VtbWVkIHdpdGggdGhlIHBl'
    || 'ci1hY3Rpb24gZXN0aW1hdGVzIC0tCiAgICAjIG9uZSBpcyBQUk9KRUNURUQgYW5kIHRoZSBvdGhlciBpcyBtZWFzdXJlZCwgYW5kIGFkZGluZyB0aGVtIHdv'
    || 'dWxkIGludmVudCBhCiAgICAjIGZpZ3VyZSB0aGF0IG1lYW5zIG5vdGhpbmcuCiAgICBobCA9IGxvYWRfaGVhZGxpbmUoc2Vzc2lvbiwgdGd0KQogICAgaWYg'
    || 'aGwgaXMgbm90IE5vbmUgYW5kIGhsWzBdOgogICAgICAgIHN0LmNhcHRpb24oIldIQVQgVEhJUyBDT1NUUyBUTyBMRUFWRSBSVU5OSU5HIikKICAgICAgICBz'
    || 'dC5jYXB0aW9uKGhsWzBdKQoKICAgIGlmIG5vdCByb3dzOgogICAgICAgIHJldHVybgoKICAgIHN0LmNhcHRpb24oIldIQVQgVEhJUyBDQU4gRE8gTkVYVCIp'
    || 'CiAgICAjIE9ubHkgd2FybiBhYm91dCB3aGF0IGlzIGFjdHVhbGx5IHN3aXRjaGVkIG9mZi4gQW5ub3VuY2luZyAidGhlc2UgYXJlIHN3aXRjaGVkCiAgICAj'
    || 'IG9mZiIgb3ZlciBhIGxpc3QgY29udGFpbmluZyBsaXZlIFNBTVBMRSBidXR0b25zIGlzIHdvcnNlIHRoYW4gc2lsZW5jZTogdGhlCiAgICAjIHJlYWRlciBi'
    || 'ZWxpZXZlcyBpdCBhbmQgc3RvcHMgdHJ5aW5nLgogICAgaWYgbm90IGFsbG93X3JlYWwgYW5kIG5vdCBhbGxvd19zYW1wbGU6CiAgICAgICAgcGZ4ID0gbG9h'
    || 'ZF9wcmVmaXgoc2Vzc2lvbiwgdGd0KQogICAgICAgICMgTmFtZSB0aGUgbGluZSwgbm90IHRoZSBzZXR0aW5nLiAicmUtcnVuIHdpdGggQUxMT1dfQUNUSU9O'
    || 'UyA9IFRSVUUiIHNlbnQKICAgICAgICAjIHRoZSByZWFkZXIgbG9va2luZyBmb3IgYSBzZXR0aW5nIHRoYXQgYXBwZWFycyBpbiBubyBmaWxlIHVuZGVyIHRo'
    || 'YXQKICAgICAgICAjIG5hbWUsIHdoaWNoIGlzIGhvdyBhIHB1c2gtYnV0dG9uIGRlcGxveW1lbnQgY2FtZSB0byBsb29rIGxpa2UgaXQgbmVlZGVkCiAgICAg'
    || 'ICAgIyBhIHRlcm1pbmFsIHNlc3Npb24gYW5kIHNvbWUgZ3Vlc3N3b3JrLgogICAgICAgIGFybSA9ICgiU0VUICIgKyBwZnggKyAiX0FMTE9XX0FDVElPTlMg'
    || 'PSBUUlVFOyIpIGlmIHBmeCBlbHNlICJBTExPV19BQ1RJT05TID0gVFJVRSIKICAgICAgICBzdC5pbmZvKAogICAgICAgICAgICAiVGhlc2UgYXJlIHN3aXRj'
    || 'aGVkIG9mZi4gVGhpcyBidWlsZCB3YXMgY3JlYXRlZCB3aXRoICIKICAgICAgICAgICAgIkFMTE9XX0FDVElPTlMgPSBGQUxTRSwgc28gdGhlIGJ1dHRvbnMg'
    || 'YmVsb3cgYXJlIGluZXJ0IGFuZCB0aGUgIgogICAgICAgICAgICAicHJvY2VkdXJlIGJlaGluZCB0aGVtIHJlZnVzZXMuIEV2ZXJ5dGhpbmcgZWFjaCBvbmUg'
    || 'd291bGQgZG8sIGFuZCAiCiAgICAgICAgICAgICJ3aGF0IGl0IHdvdWxkIGNvc3QsIGlzIGxpc3RlZCBhbnl3YXkg4oCUIHRvIGFybSB0aGVtLCBjaGFuZ2Ug'
    || 'dGhlICIKICAgICAgICAgICAgImxpbmUgbmVhciB0aGUgdG9wIG9mIHRoZSBzY3JpcHQgeW91IGFscmVhZHkgcmFuIHRvICIKICAgICAgICAgICAgKyBhcm0g'
    || 'KyAiIGFuZCBydW4gdGhhdCBmaWxlIGFnYWluLiBUaGVyZSBpcyBub3RoaW5nIGVsc2UgdG8gdHlwZTogIgogICAgICAgICAgICAidGhlIGZpbGUgaXMgdGhl'
    || 'IG9ubHkgcGxhY2UgdGhpcyBpcyBzd2l0Y2hlZCBvbiwgYW5kIHJ1bm5pbmcgaXQgaXMgIgogICAgICAgICAgICAidGhlIHdob2xlIHByb2NlZHVyZS4iLAog'
    || 'ICAgICAgICAgICBpY29uPSI6bWF0ZXJpYWwvbG9jazoiKQoKICAgIGJ5X3RpZXIgPSB7fQogICAgZm9yIHIgaW4gcm93czoKICAgICAgICBieV90aWVyLnNl'
    || 'dGRlZmF1bHQoc3RyKHIuZ2V0KCJUSUVSIikgb3IgIlBST0RVQ1RJT04iKS51cHBlcigpLCBbXSkuYXBwZW5kKHIpCgogICAgZm9yIHRpZXIgaW4gVElFUl9P'
    || 'UkRFUjoKICAgICAgICBncm91cCA9IGJ5X3RpZXIuZ2V0KHRpZXIsIFtdKQogICAgICAgIGlmIG5vdCBncm91cDoKICAgICAgICAgICAgY29udGludWUKICAg'
    || 'ICAgICAjIFNBTVBMRSBydW5zIG9uIHNlZWRlZCBkYXRhIHRoaXMgc2NyaXB0IGNyZWF0ZWQsIHNvIGl0IGFuc3dlcnMgdG8KICAgICAgICAjIEFMTE9XX1NB'
    || 'TVBMRV9BQ1RJT05TLiBFdmVyeXRoaW5nIGVsc2UgdG91Y2hlcyB0aGUgY3VzdG9tZXIncyBvd24gb2JqZWN0cwogICAgICAgICMgYW5kIGFuc3dlcnMgdG8g'
    || 'QUxMT1dfQUNUSU9OUy4gVW5rbm93biB0aWVycyB0YWtlIHRoZSBzdHJpY3RlciBnYXRlLgogICAgICAgIHRpZXJfZW5hYmxlZCA9IGFsbG93X3NhbXBsZSBp'
    || 'ZiB0aWVyID09ICJTQU1QTEUiIGVsc2UgYWxsb3dfcmVhbAogICAgICAgIHN0LmNhcHRpb24odGllciArICIg4oCUICIgKyBUSUVSX0JMVVJCLmdldCh0aWVy'
    || 'LCAiIikKICAgICAgICAgICAgICAgICAgICsgKCIiIGlmIHRpZXJfZW5hYmxlZCBlbHNlCiAgICAgICAgICAgICAgICAgICAgICAiICDCtyAgc3dpdGNoZWQg'
    || 'b2ZmIGluIHRoZSBmaWxlIikpCiAgICAgICAgY29scyA9IHN0LmNvbHVtbnMobGVuKGdyb3VwKSkKICAgICAgICBmb3IgY29sLCByIGluIHppcChjb2xzLCBn'
    || 'cm91cCk6CiAgICAgICAgICAgIHdpdGggY29sOgogICAgICAgICAgICAgICAgY29kZSA9IHN0cihyLmdldCgiQ09ERSIpIG9yICIiKQogICAgICAgICAgICAg'
    || 'ICAgZXN0ID0gci5nZXQoIkVTVF9DUkVESVRTIikKICAgICAgICAgICAgICAgICMgVGhyZWUgbGluZXMgYW5kIGEgYnV0dG9uLCBub3QgZml2ZSBsaW5lcyBh'
    || 'bmQgYSBidXR0b24uIFRoZQogICAgICAgICAgICAgICAgIyBlc3RpbWF0ZSBhbmQgaXRzIGJhc2lzIHN0aWxsIHRyYXZlbCBXSVRIIHRoZSBjb250cm9sIC0t'
    || 'IGEgYnV0dG9uCiAgICAgICAgICAgICAgICAjIHRoYXQgY2hhbmdlcyBwcm9kdWN0aW9uIHdpdGhvdXQgc2F5aW5nIHdoYXQgaXQgY29zdHMgaXMgdGhlIHRo'
    || 'aW5nCiAgICAgICAgICAgICAgICAjIHRoaXMgcmVwbyBleGlzdHMgdG8gYXZvaWQgLS0gYnV0IGBiYXNpc2AgYW5kIGB1bmRvYCBiZWxvbmcgaW4gdGhlCiAg'
    || 'ICAgICAgICAgICAgICAjIHRvb2x0aXAuIFJlbmRlcmVkIGFzIGNvbHVtbnMgb2YgYm9keSB0ZXh0IHRoZXkgd2VyZSBmb3VyIGxpbmVzIG9mCiAgICAgICAg'
    || 'ICAgICAgICAjIHByb3NlIGVhY2gsIGFuZCB0aGUgcmVhZGVyIHN0b3BwZWQgYmVmb3JlIHRoZSBidXR0b24uCiAgICAgICAgICAgICAgICBzdC5jYXB0aW9u'
    || 'KCIqKiIgKyBzdHIoci5nZXQoIkxBQkVMIikgb3IgY29kZSkgKyAiKioiKQogICAgICAgICAgICAgICAgc3QuY2FwdGlvbigifiIgKyBmbXRfY3JlZGl0cyhl'
    || 'c3QpICsgIiBjcmVkaXRzIMK3ICIKICAgICAgICAgICAgICAgICAgICAgICAgICAgKyBzdHIoci5nZXQoIlNUQVRFTUVOVFMiKSBvciAwKSArICIgc3RhdGVt'
    || 'ZW50KHMpIgogICAgICAgICAgICAgICAgICAgICAgICAgICArICgiIMK3IHJ1biAiICsgc3RyKHJbIlRJTUVTX1JVTiJdKSArICJ4IGFscmVhZHkiCiAgICAg'
    || 'ICAgICAgICAgICAgICAgICAgICAgICAgIGlmIHIuZ2V0KCJUSU1FU19SVU4iKSBlbHNlICIiKSkKICAgICAgICAgICAgICAgIHN0LmNhcHRpb24oc3RyKHIu'
    || 'Z2V0KCJFRkZFQ1QiKSBvciAibm90IHN0YXRlZCIpKQogICAgICAgICAgICAgICAgaWYgc3QuYnV0dG9uKCJSdW4gIiArIGNvZGUsIGtleT0iYXJtXyIgKyBj'
    || 'b2RlLCBkaXNhYmxlZD1ub3QgdGllcl9lbmFibGVkLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgIHVzZV9jb250YWluZXJfd2lkdGg9VHJ1ZSwKICAg'
    || 'ICAgICAgICAgICAgICAgICAgICAgICAgICBoZWxwPSJFc3RpbWF0ZSBiYXNpczogIiArIHN0cihyLmdldCgiRVNUX0JBU0lTIikgb3IgIm5vdCBzdGF0ZWQi'
    || 'KQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgKyAiXG5cblRvIHVuZG86ICIgKyBzdHIoci5nZXQoIlVORE8iKSBvciAibm90IHN0YXRlZCIp'
    || 'KToKICAgICAgICAgICAgICAgICAgICBzdC5zZXNzaW9uX3N0YXRlWyJhcm1lZCJdID0gY29kZQogICAgICAgICAgICAgICAgICAgIHN0LnNlc3Npb25fc3Rh'
    || 'dGUucG9wKCJyZXN1bHRfIiArIGNvZGUsIE5vbmUpCiAgICAgICAgICAgICAgICAjIFVuZG8gYXBwZWFycyBvbmx5IG9uY2UgdGhlIGFjdGlvbiBoYXMgYWN0'
    || 'dWFsbHkgY29tcGxldGVkLCBiZWNhdXNlCiAgICAgICAgICAgICAgICAjIFVORE9fQUNUSU9OIHJlZnVzZXMgb3RoZXJ3aXNlIGFuZCBhIGJ1dHRvbiB3aG9z'
    || 'ZSBvbmx5IG91dGNvbWUgaXMgYQogICAgICAgICAgICAgICAgIyByZWZ1c2FsIHRlYWNoZXMgdGhlIHJlYWRlciB0byBkaXN0cnVzdCBhbGwgb2YgdGhlbS4g'
    || 'QW4gYWN0aW9uIHdpdGgKICAgICAgICAgICAgICAgICMgbm8gcmV2ZXJzZSBzdGF0ZW1lbnRzIG5ldmVyIHNob3dzIG9uZSBhdCBhbGwgLS0gc2F5aW5nICJu'
    || 'b3QKICAgICAgICAgICAgICAgICMgcmV2ZXJzaWJsZSIgcGxhaW5seSBiZWF0cyBvZmZlcmluZyBhIGNvbnRyb2wgdGhhdCBjYW5ub3Qgd29yay4KICAgICAg'
    || 'ICAgICAgICAgIGlmIHIuZ2V0KCJVTkRPX1NUQVRFTUVOVFMiKSBhbmQgci5nZXQoIlRJTUVTX1JVTiIpOgogICAgICAgICAgICAgICAgICAgIGlmIHN0LmJ1'
    || 'dHRvbigiVW5kbyAiICsgY29kZSwga2V5PSJ1bmRvYXJtXyIgKyBjb2RlLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBkaXNhYmxlZD1ub3Qg'
    || 'dGllcl9lbmFibGVkLCB1c2VfY29udGFpbmVyX3dpZHRoPVRydWUsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGhlbHA9IlJ1bnMgIiArIHN0'
    || 'cihyWyJVTkRPX1NUQVRFTUVOVFMiXSkKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICArICIgcmV2ZXJzZSBzdGF0ZW1lbnQocykuICIg'
    || 'KyBzdHIoci5nZXQoIlVORE8iKSBvciAiIikpOgogICAgICAgICAgICAgICAgICAgICAgICBzdC5zZXNzaW9uX3N0YXRlWyJhcm1lZCJdID0gY29kZQogICAg'
    || 'ICAgICAgICAgICAgICAgICAgICBzdC5zZXNzaW9uX3N0YXRlWyJhcm1lZF91bmRvIl0gPSBUcnVlCiAgICAgICAgICAgICAgICAgICAgICAgIHN0LnNlc3Np'
    || 'b25fc3RhdGUucG9wKCJyZXN1bHRfIiArIGNvZGUsIE5vbmUpCiAgICAgICAgICAgICAgICBlbGlmIHIuZ2V0KCJUSU1FU19SVU4iKSBhbmQgbm90IHIuZ2V0'
    || 'KCJVTkRPX1NUQVRFTUVOVFMiKToKICAgICAgICAgICAgICAgICAgICBzdC5jYXB0aW9uKCJObyBhdXRvbWF0aWMgdW5kbyDigJQgc2VlIHRoZSB1bmRvIG5v'
    || 'dGUgaW4gdGhlIHRvb2x0aXAuIikKICAgICAgICAgICAgICAgIGlmIHIuZ2V0KCJUSU1FU19VTkRPTkUiKToKICAgICAgICAgICAgICAgICAgICBzdC5jYXB0'
    || 'aW9uKCJVbmRvbmUgIiArIHN0cihyWyJUSU1FU19VTkRPTkUiXSkgKyAieCIpCgogICAgYXJtZWQgPSBzdC5zZXNzaW9uX3N0YXRlLmdldCgiYXJtZWQiKQog'
    || 'ICAgdW5kb2luZyA9IGJvb2woc3Quc2Vzc2lvbl9zdGF0ZS5nZXQoImFybWVkX3VuZG8iKSkKICAgICMgUmVzb2x2ZSB0aGUgQVJNRUQgYWN0aW9uJ3Mgb3du'
    || 'IHRpZXIuIERlbGliZXJhdGVseSBub3QgYHRpZXJfZW5hYmxlZGAgZnJvbSB0aGUKICAgICMgbG9vcCBhYm92ZTogdGhhdCB2YXJpYWJsZSBob2xkcyB3aGlj'
    || 'aGV2ZXIgdGllciBoYXBwZW5lZCB0byBiZSByZW5kZXJlZCBsYXN0LAogICAgIyBzbyByZXVzaW5nIGl0IGhlcmUgd291bGQgZ2F0ZSB0aGUgY29uZmlybWF0'
    || 'aW9uIG9uIGFuIHVucmVsYXRlZCBhY3Rpb24uIERlZmF1bHQKICAgICMgdG8gdGhlIHN0cmljdGVyIGZsYWcgd2hlbiB0aGUgY29kZSBjYW5ub3QgYmUgZm91'
    || 'bmQuCiAgICBhcm1lZF90aWVyID0gIlBST0RVQ1RJT04iCiAgICBmb3IgciBpbiByb3dzOgogICAgICAgIGlmIHN0cihyLmdldCgiQ09ERSIpIG9yICIiKSA9'
    || 'PSBzdHIoYXJtZWQgb3IgIiIpOgogICAgICAgICAgICBhcm1lZF90aWVyID0gc3RyKHIuZ2V0KCJUSUVSIikgb3IgIlBST0RVQ1RJT04iKS51cHBlcigpCiAg'
    || 'ICAgICAgICAgIGJyZWFrCiAgICBhcm1lZF9lbmFibGVkID0gYWxsb3dfc2FtcGxlIGlmIGFybWVkX3RpZXIgPT0gIlNBTVBMRSIgZWxzZSBhbGxvd19yZWFs'
    || 'CiAgICBpZiBhcm1lZCBhbmQgYXJtZWRfZW5hYmxlZDoKICAgICAgICBzdC5jYXB0aW9uKCgiQ09ORklSTSBVTkRPIE9GICIgaWYgdW5kb2luZyBlbHNlICJD'
    || 'T05GSVJNICIpICsgYXJtZWQpCiAgICAgICAgIyBQYXJhbWV0ZXJzIGFyZSBjaG9zZW4gSEVSRSwgYmVmb3JlIHRoZSBjb2RlIGlzIHR5cGVkLCBhbmQgb25s'
    || 'eSBmb3IgYSBmb3J3YXJkCiAgICAgICAgIyBydW4uIEFuIHVuZG8gdGFrZXMgbm9uZSBieSBkZXNpZ246IFJVTl9BQ1RJT04gcmVzb2x2ZWQgYW5kIHNuYXBz'
    || 'aG90dGVkIHRoZQogICAgICAgICMgcmV2ZXJzZSBzdGF0ZW1lbnRzIHdoZW4gdGhlIGFjdGlvbiByYW4sIHNvIFVORE9fQUNUSU9OIHJlcGxheXMgdGhhdCBl'
    || 'eGFjdAogICAgICAgICMgdGV4dC4gT2ZmZXJpbmcgdGhlIHZhbHVlcyBhZ2FpbiB3b3VsZCBpbnZpdGUgcmV2ZXJzaW5nIGEgZGlmZmVyZW50IHRhcmdldAog'
    || 'ICAgICAgICMgdGhhbiB0aGUgb25lIHRoYXQgd2FzIGNoYW5nZWQsIHdoaWNoIGlzIHdvcnNlIHRoYW4gaGF2aW5nIG5vIHVuZG8uCiAgICAgICAgcHZhbHMs'
    || 'IHByZWFkeSA9IHt9LCBUcnVlCiAgICAgICAgaWYgbm90IHVuZG9pbmc6CiAgICAgICAgICAgIGFwYXJhbXMgPSBsb2FkX2FjdGlvbl9wYXJhbXMoc2Vzc2lv'
    || 'biwgdGd0KS5nZXQoYXJtZWQsIFtdKQogICAgICAgICAgICBpZiBhcGFyYW1zOgogICAgICAgICAgICAgICAgc3QuY2FwdGlvbigiQ2hvb3NlIHdoYXQgaXQg'
    || 'cnVucyBhZ2FpbnN0LiBUaGVzZSBhcmUgdGhlIG9ubHkgdmFsdWVzIHRoaXMgIgogICAgICAgICAgICAgICAgICAgICAgICAgICAiYnVpbGQgZGlzY292ZXJl'
    || 'ZCBmb3IgaXQsIGFuZCB0aGUgcHJvY2VkdXJlIHJlLWNoZWNrcyB5b3VyICIKICAgICAgICAgICAgICAgICAgICAgICAgICAgImNob2ljZSBhZ2FpbnN0IHRo'
    || 'YXQgc2FtZSBsaXN0IGJlZm9yZSBpdCBydW5zIGFueXRoaW5nLiIpCiAgICAgICAgICAgICAgICBwdmFscywgcHJlYWR5ID0gYWN0aW9uX3BhcmFtX3ZhbHVl'
    || 'cyhzZXNzaW9uLCBhcm1lZCwgYXBhcmFtcykKICAgICAgICBzdC5jYXB0aW9uKCJUeXBlIHRoZSBhY3Rpb24gY29kZSBleGFjdGx5LiBUaGlzIGlzIHRoZSBs'
    || 'YXN0IHN0ZXAgYmVmb3JlIGl0IHJ1bnMuIgogICAgICAgICAgICAgICAgICAgKyAoIiBUaGlzIFJFVkVSU0VTIHRoZSBhY3Rpb247IHJldmVyc2luZyBhIG1h'
    || 'c2tpbmcgcG9saWN5IGV4cG9zZXMgIgogICAgICAgICAgICAgICAgICAgICAgInRoZSBjb2x1bW4gYWdhaW4sIHNvIGl0IGlzIGEgY2hhbmdlIGxpa2UgYW55'
    || 'IG90aGVyLiIKICAgICAgICAgICAgICAgICAgICAgIGlmIHVuZG9pbmcgZWxzZSAiIikpCiAgICAgICAgdHlwZWQgPSBzdC50ZXh0X2lucHV0KCJDb25maXJt'
    || 'YXRpb24iLCBrZXk9ImNvbmZpcm1fIiArIGFybWVkLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICBsYWJlbF92aXNpYmlsaXR5PSJjb2xsYXBzZWQi'
    || 'LCBwbGFjZWhvbGRlcj1hcm1lZCkKICAgICAgICBjMSwgYzIgPSBzdC5jb2x1bW5zKFsxLCA0XSkKICAgICAgICB3aXRoIGMxOgogICAgICAgICAgICAjIERp'
    || 'c2FibGVkIHVudGlsIGV2ZXJ5IHBhcmFtZXRlciBoYXMgYSB2YWx1ZS4gVGhlIHByb2NlZHVyZSByZWZ1c2VzIGEKICAgICAgICAgICAgIyBtaXNzaW5nIG9u'
    || 'ZSBhbnl3YXkgLS0gdGhpcyBvbmx5IGF2b2lkcyB0ZWFjaGluZyB0aGUgcmVhZGVyIHRoYXQgdGhlCiAgICAgICAgICAgICMgYnV0dG9uIHByb2R1Y2VzIHJl'
    || 'ZnVzYWxzLgogICAgICAgICAgICBnbyA9IHN0LmJ1dHRvbigiUnVuIGl0Iiwga2V5PSJnb18iICsgYXJtZWQsIHR5cGU9InByaW1hcnkiLAogICAgICAgICAg'
    || 'ICAgICAgICAgICAgICAgICBkaXNhYmxlZD1ub3QgcHJlYWR5KQogICAgICAgIHdpdGggYzI6CiAgICAgICAgICAgIGlmIHN0LmJ1dHRvbigiQ2FuY2VsIiwg'
    || 'a2V5PSJjYW5jZWxfIiArIGFybWVkKToKICAgICAgICAgICAgICAgIHN0LnNlc3Npb25fc3RhdGUucG9wKCJhcm1lZCIsIE5vbmUpCiAgICAgICAgICAgICAg'
    || 'ICBzdC5zZXNzaW9uX3N0YXRlLnBvcCgiYXJtZWRfdW5kbyIsIE5vbmUpCiAgICAgICAgICAgICAgICBnbyA9IEZhbHNlCiAgICAgICAgaWYgZ286CiAgICAg'
    || 'ICAgICAgICMgVGhlIHR5cGVkIHZhbHVlIGlzIHBhc3NlZCBhcyBhIEJJTkQsIG5ldmVyIGNvbmNhdGVuYXRlZC4gSXQgaXMKICAgICAgICAgICAgIyBhdHRh'
    || 'Y2tlci1jb250cm9sbGVkIHRleHQgZ29pbmcgaW50byBhIHByb2NlZHVyZSBjYWxsLCBhbmQgdGhlCiAgICAgICAgICAgICMgcHJvY2VkdXJlIGNvbXBhcmVz'
    || 'IGl0IHRvIHRoZSBjb2RlIHJhdGhlciB0aGFuIGV4ZWN1dGluZyBpdCAtLSBidXQKICAgICAgICAgICAgIyBiaW5kaW5nIGlzIHdoYXQgbWFrZXMgdGhhdCB0'
    || 'cnVlIHJlZ2FyZGxlc3Mgb2Ygd2hhdCB3YXMgdHlwZWQuCiAgICAgICAgICAgICMKICAgICAgICAgICAgIyBUaGUgcGFyYW1ldGVyIHZhbHVlcyBhcmUgYm91'
    || 'bmQgdG9vLCBhcyBvbmUgSlNPTiBzdHJpbmcuIFRoZXkgY2Fubm90IGJlCiAgICAgICAgICAgICMgYm91bmQgYXMgYW4gT0JKRUNUIC0tIGFuZCBKU09OIHRl'
    || 'eHQgaXMgd2hhdCBVTkRPX1NOQVBTSE9UIGFscmVhZHkgdXNlcywKICAgICAgICAgICAgIyBmb3IgdGhlIGRvY3VtZW50ZWQgcmVhc29uIHRoYXQgYW4gQVJS'
    || 'QVkgYmluZCBpcyBmcmFnaWxlIHdoaWxlCiAgICAgICAgICAgICMgVE9fSlNPTi9QQVJTRV9KU09OIHJvdW5kLXRyaXBzIGV4YWN0bHkuIEJpbmRpbmcgaXMg'
    || 'bm90IHdoYXQgbWFrZXMgdGhlbQogICAgICAgICAgICAjIHNhZmU6IHRoZSBwcm9jZWR1cmUgdmFsaWRhdGVzIGV2ZXJ5IHZhbHVlIGFnYWluc3QgdGhlIHJl'
    || 'Z2lzdHJ5J3Mgb3duCiAgICAgICAgICAgICMgYWxsb3dlZCBsaXN0IGJlZm9yZSBpbnRlcnBvbGF0aW5nIGFueSBvZiB0aGVtLiBCaW5kaW5nIGp1c3QgbWVh'
    || 'bnMgdGhlCiAgICAgICAgICAgICMgY2FsbCBpdHNlbGYgY2Fubm90IGJlIGJyb2tlbiBieSB3aGF0IHdhcyBjaG9zZW4uCiAgICAgICAgICAgICMKICAgICAg'
    || 'ICAgICAgIyBBbiBhY3Rpb24gd2l0aCBubyBwYXJhbWV0ZXJzIHRha2VzIHRoZSBUV08tQVJHVU1FTlQgcGF0aCwgdW5jaGFuZ2VkLCBzbwogICAgICAgICAg'
    || 'ICAjIGV2ZXJ5IGV4aXN0aW5nIHNvbHV0aW9uIGNhbGxzIGV4YWN0bHkgd2hhdCBpdCBjYWxsZWQgYmVmb3JlLgogICAgICAgICAgICBpZiBwdmFsczoKICAg'
    || 'ICAgICAgICAgICAgIHByb2MgPSAiLlJVTl9BQ1RJT04oPywgPywgPykiCiAgICAgICAgICAgICAgICBhcmdzID0gW2FybWVkLCB0eXBlZCwganNvbi5kdW1w'
    || 'cyhwdmFscyldCiAgICAgICAgICAgIGVsc2U6CiAgICAgICAgICAgICAgICBwcm9jID0gIi5VTkRPX0FDVElPTig/LCA/KSIgaWYgdW5kb2luZyBlbHNlICIu'
    || 'UlVOX0FDVElPTig/LCA/KSIKICAgICAgICAgICAgICAgIGFyZ3MgPSBbYXJtZWQsIHR5cGVkXQogICAgICAgICAgICB0cnk6CiAgICAgICAgICAgICAgICBv'
    || 'dXQgPSBzZXNzaW9uLnNxbCgiQ0FMTCAiICsgdGd0ICsgcHJvYywKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHBhcmFtcz1hcmdzKS5jb2xs'
    || 'ZWN0KClbMF1bMF0KICAgICAgICAgICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBleGM6CiAgICAgICAgICAgICAgICBvdXQgPSAiRkFJTEVEIHRvIGNhbGwgIiAr'
    || 'IHByb2Muc3BsaXQoIigiKVswXS5zdHJpcCgiLiIpICsgIjogIiArIHN0cihleGMpCiAgICAgICAgICAgIHN0LnNlc3Npb25fc3RhdGVbInJlc3VsdF8iICsg'
    || 'YXJtZWRdID0gc3RyKG91dCkKICAgICAgICAgICAgc3Quc2Vzc2lvbl9zdGF0ZS5wb3AoImFybWVkIiwgTm9uZSkKICAgICAgICAgICAgc3Quc2Vzc2lvbl9z'
    || 'dGF0ZS5wb3AoImFybWVkX3VuZG8iLCBOb25lKQogICAgICAgICAgICBpbnZhbGlkYXRlX3BhbmVsX2NhY2hlKCkKICAgICAgICAgICAgc3QucmVydW4oKQoK'
    || 'ICAgIGZvciBrIGluIFtrIGZvciBrIGluIHN0LnNlc3Npb25fc3RhdGUgaWYgc3RyKGspLnN0YXJ0c3dpdGgoInJlc3VsdF8iKV06CiAgICAgICAgbXNnID0g'
    || 'c3RyKHN0LnNlc3Npb25fc3RhdGVba10pCiAgICAgICAgaWYgbXNnLnN0YXJ0c3dpdGgoIkRPTkUiKSBvciBtc2cuc3RhcnRzd2l0aCgiVU5ET05FIik6CiAg'
    || 'ICAgICAgICAgIHN0LnN1Y2Nlc3MobXNnLCBpY29uPSI6bWF0ZXJpYWwvY2hlY2s6IikKICAgICAgICBlbGlmIG1zZy5zdGFydHN3aXRoKCJQQVJUSUFMTFkg'
    || 'VU5ET05FIik6CiAgICAgICAgICAgICMgTm90IGFuIGVycm9yIGFuZCBub3QgYSBzdWNjZXNzOiBzb21lIG9mIHRoZSBhY2NvdW50IGNhbWUgYmFjayBhbmQg'
    || 'c29tZQogICAgICAgICAgICAjIGRpZCBub3QsIGFuZCB0aGUgcmVhZGVyIGhhcyB0byBrbm93IHdoaWNoIHdpdGhvdXQgZ3Vlc3NpbmcuCiAgICAgICAgICAg'
    || 'IHN0Lndhcm5pbmcobXNnLCBpY29uPSI6bWF0ZXJpYWwvd2FybmluZzoiKQogICAgICAgIGVsaWYgbXNnLnN0YXJ0c3dpdGgoIlJFRlVTRUQiKToKICAgICAg'
    || 'ICAgICAgc3Qud2FybmluZyhtc2csIGljb249IjptYXRlcmlhbC9ibG9jazoiKQogICAgICAgIGVsc2U6CiAgICAgICAgICAgIHN0LmVycm9yKG1zZywgaWNv'
    || 'bj0iOm1hdGVyaWFsL2Vycm9yOiIpCiAgICBzdC5kaXZpZGVyKCkKCgpkZWYgbG9hZF9hZ2VudChzZXNzaW9uLCB0Z3Q6IHN0cik6CiAgICAiIiJUaGUgZGVj'
    || 'bGFyZWQgYWdlbnQsIG9yIE5vbmUuCgogICAgR2F0ZXMgb24gd2hldGhlciB0aGUgc29sdXRpb24gYnVpbHQgVl9BR0VOVF9DSEFULCBleGFjdGx5IGFzIGxv'
    || 'YWRfYWN0aW9ucyBnYXRlcwogICAgb24gVl9BQ1RJT05TIGFuZCBsb2FkX3J1bGVfY29uZmlnIG9uIFZfUlVMRV9DT05GSUcuIFNpeCBzb2x1dGlvbnMgYWxy'
    || 'ZWFkeSBidWlsZAogICAgYW4gYWdlbnQgcHJvY2VkdXJlIHRoYXQgbm90aGluZyBjb3VsZCByZWFjaCAtLSBBU0tfR09WRVJOQU5DRSwKICAgIERJQUdOT1NF'
    || 'X0ZBSUxVUkUsIEVYUExBSU5fUFJJVkFDWV9CTE9DSywgQVNTRVNTX01JR1JBVElPTiBhbmQgZnJpZW5kcyB3ZXJlCiAgICBjYWxsYWJsZSBvbmx5IGZyb20g'
    || 'YSB3b3Jrc2hlZXQuIERlY2xhcmluZyBvbmUgdmlldyBub3cgc3VyZmFjZXMgaXQuCgogICAgQSBzb2x1dGlvbiB3aG9zZSBhZ2VudCBkZXBlbmRzIG9uIENv'
    || 'cnRleCBiZWluZyBhdmFpbGFibGUgbXVzdCBjcmVhdGUgdGhpcyB2aWV3CiAgICBpbnNpZGUgdGhlIHNhbWUgYXZhaWxhYmlsaXR5IGNoZWNrIHRoYXQgY3Jl'
    || 'YXRlcyB0aGUgcHJvY2VkdXJlLCBzbyB0aGF0IHRoZSBjaGF0CiAgICBuZXZlciBhcHBlYXJzIGZvciBhIGJ1aWxkIHdoZXJlIHRoZSBtb2RlbCB3YXMgdW5y'
    || 'ZWFjaGFibGUuCiAgICAiIiIKICAgIHRyeToKICAgICAgICByb3dzID0gW3IuYXNfZGljdCgpIGZvciByIGluIHNlc3Npb24uc3FsKAogICAgICAgICAgICAi'
    || 'U0VMRUNUIEFHRU5UX0xBQkVMLCBQUk9DX05BTUUsIFBMQUNFSE9MREVSLCBCTFVSQiAiCiAgICAgICAgICAgICJGUk9NICIgKyB0Z3QgKyAiLlZfQUdFTlRf'
    || 'Q0hBVCIpLmNvbGxlY3QoKV0KICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgcmV0dXJuIE5vbmUKICAgIGlmIG5vdCByb3dzOgogICAgICAgIHJldHVy'
    || 'biBOb25lCiAgICBhID0gcm93c1swXQogICAgIyBUaGUgcHJvY2VkdXJlIE5BTUUgY2Fubm90IGJlIGEgYmluZCAtLSBpdCBpcyBhbiBpZGVudGlmaWVyLCBz'
    || 'byBpdCBoYXMgdG8gYmUKICAgICMgY29uY2F0ZW5hdGVkIGludG8gdGhlIENBTEwuIEl0IGNvbWVzIGZyb20gYSB2aWV3IHRoaXMgYnVpbGQgY3JlYXRlZCBy'
    || 'YXRoZXIKICAgICMgdGhhbiBmcm9tIGFueXRoaW5nIGEgcmVhZGVyIHR5cGVkLCBidXQgaXQgaXMgdmFsaWRhdGVkIGFueXdheTogYSB2aWV3IGlzIGEKICAg'
    || 'ICMgdGhpbmcgc29tZW9uZSBjYW4gbGF0ZXIgQUxURVIsIGFuZCB0aGUgY29zdCBvZiBiZWluZyB3cm9uZyBoZXJlIGlzIGFyYml0cmFyeQogICAgIyBTUUwg'
    || 'cnVubmluZyBhcyB0aGUgYXBwIG93bmVyLiBUaGUgcXVlc3Rpb24gaXRzZWxmIElTIGJvdW5kLgogICAgcHJvYyA9IHN0cihhLmdldCgiUFJPQ19OQU1FIikg'
    || 'b3IgIiIpCiAgICBpZiBub3QgcmUuZnVsbG1hdGNoKHIiW0EtWmEtel9dW0EtWmEtejAtOV9dKiIsIHByb2MpOgogICAgICAgIHJldHVybiBOb25lCiAgICBh'
    || 'WyJQUk9DX05BTUUiXSA9IHByb2MKICAgIHJldHVybiBhCgoKZGVmIGFnZW50X2JhcihzZXNzaW9uLCB0Z3Q6IHN0cikgLT4gTm9uZToKICAgICIiIkFzayB0'
    || 'aGUgc29sdXRpb24ncyBvd24gYWdlbnQgYSBxdWVzdGlvbiwgaW4gdGhlIGFwcC4KCiAgICBCRVRXRUVOIHRoZSBydWxlcyBhbmQgdGhlIGFjdGlvbnMsIHdo'
    || 'aWNoIGlzIHRoZSByZWFkaW5nIG9yZGVyIHRoZSBwYWdlIGFscmVhZHkKICAgIGFyZ3VlcyBmb3I6IHRoZSBkYXNoYm9hcmQgc2F5cyB3aGF0IGlzIHRydWUs'
    || 'IGNvbmZpZ19iYXIgdHVuZXMgaG93IGl0IHdhcwogICAgZGVjaWRlZCwgdGhpcyBleHBsYWlucyBpdCBpbiB3b3JkcywgYW5kIHByb21vdGlvbl9iYXIgYWN0'
    || 'cyBvbiBpdC4gQW4gYW5zd2VyIGlzCiAgICBtb3N0IHVzZWZ1bCBpbW1lZGlhdGVseSBiZWZvcmUgdGhlIGRlY2lzaW9uIGl0IGluZm9ybXMuCgogICAgc3Qu'
    || 'Y2hhdF9pbnB1dCByYXRoZXIgdGhhbiBhIFJlYWN0IGNoYXQgYm94IGZvciB0aGUgdXN1YWwgcmVhc29uIC0tIHRoZSBidW5kbGUKICAgIHJ1bnMgaW4gYSBz'
    || 'YW5kYm94ZWQgaWZyYW1lIHdpdGggbm8gc2Vzc2lvbiBhbmQgY2Fubm90IGNhbGwgYSBwcm9jZWR1cmUuCgogICAgSElTVE9SWSBJUyBQRVIgU0VTU0lPTiBB'
    || 'TkQgTk9UIFBFUlNJU1RFRC4gTm90aGluZyBoZXJlIHdyaXRlcyB0byB0aGUgYWNjb3VudDoKICAgIGEgcXVlc3Rpb24gY29zdHMgYSBzbWFsbCBhbW91bnQg'
    || 'b2YgQ29ydGV4IGNyZWRpdCBhbmQgcmV0dXJucyBhIHN0cmluZy4gVGhhdCBpcwogICAgYWxzbyB3aHkgdGhpcyBpcyBub3QgdGllci1nYXRlZCB0aGUgd2F5'
    || 'IGFuIGFjdGlvbiBpcyAtLSB0aGVyZSBpcyBub3RoaW5nIHRvCiAgICB1bmRvIC0tIGJ1dCB0aGUgY29zdCBpcyBzdGF0ZWQgcmF0aGVyIHRoYW4gbGVmdCBh'
    || 'cyBhIHN1cnByaXNlLgogICAgIiIiCiAgICBhID0gbG9hZF9hZ2VudChzZXNzaW9uLCB0Z3QpCiAgICBpZiBub3QgYToKICAgICAgICByZXR1cm4KCiAgICBz'
    || 'dC5jYXB0aW9uKHN0cihhLmdldCgiQUdFTlRfTEFCRUwiKSBvciAiQVNLIFRIRSBBR0VOVCIpLnVwcGVyKCkpCiAgICBibHVyYiA9IHN0cihhLmdldCgiQkxV'
    || 'UkIiKSBvciAiIikKICAgIGlmIGJsdXJiOgogICAgICAgIHN0LmNhcHRpb24oYmx1cmIgKyAiIEVhY2ggcXVlc3Rpb24gY2FsbHMgYSBDb3J0ZXggbW9kZWws'
    || 'IHNvIGl0IGNvc3RzIGEgIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgInNtYWxsIGFtb3VudCBvZiBjcmVkaXQgYW5kIHRha2VzIGEgZmV3IHNlY29u'
    || 'ZHMuIikKCiAgICBoaXN0X2tleSA9ICJhZ2VudF9oaXN0IgogICAgaWYgaGlzdF9rZXkgbm90IGluIHN0LnNlc3Npb25fc3RhdGU6CiAgICAgICAgc3Quc2Vz'
    || 'c2lvbl9zdGF0ZVtoaXN0X2tleV0gPSBbXQoKICAgIGZvciBxLCBhbnMgaW4gc3Quc2Vzc2lvbl9zdGF0ZVtoaXN0X2tleV06CiAgICAgICAgd2l0aCBzdC5j'
    || 'aGF0X21lc3NhZ2UoInVzZXIiKToKICAgICAgICAgICAgc3Qud3JpdGUocSkKICAgICAgICB3aXRoIHN0LmNoYXRfbWVzc2FnZSgiYXNzaXN0YW50Iik6CiAg'
    || 'ICAgICAgICAgIHN0LndyaXRlKGFucykKCiAgICBhc2tlZCA9IHN0LmNoYXRfaW5wdXQoc3RyKGEuZ2V0KCJQTEFDRUhPTERFUiIpIG9yICJBc2sgYSBxdWVz'
    || 'dGlvbiIpLAogICAgICAgICAgICAgICAgICAgICAgICAgIGtleT0iYWdlbnRfcSIpCiAgICBpZiBhc2tlZDoKICAgICAgICB3aXRoIHN0LnNwaW5uZXIoIkFz'
    || 'a2luZyB0aGUgYWdlbnQuLi4iKToKICAgICAgICAgICAgdHJ5OgogICAgICAgICAgICAgICAgIyBUaGUgcXVlc3Rpb24gaXMgQk9VTkQuIENvbmNhdGVuYXRp'
    || 'bmcgaXQgd291bGQgbGV0IHdoYXRldmVyCiAgICAgICAgICAgICAgICAjIHNvbWVib2R5IHR5cGVzIGVuZCB1cCBhcyBTUUwgcnVubmluZyB3aXRoIHRoZSBh'
    || 'cHAgb3duZXIncyByaWdodHMuCiAgICAgICAgICAgICAgICBvdXQgPSBzZXNzaW9uLnNxbCgKICAgICAgICAgICAgICAgICAgICAiQ0FMTCAiICsgdGd0ICsg'
    || 'Ii4iICsgYVsiUFJPQ19OQU1FIl0gKyAiKD8pIiwKICAgICAgICAgICAgICAgICAgICBwYXJhbXM9W2Fza2VkXSkuY29sbGVjdCgpWzBdWzBdCiAgICAgICAg'
    || 'ICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZXhjOgogICAgICAgICAgICAgICAgIyBSZXBvcnQgdGhlIGZhaWx1cmUgYXMgdGhlIGFuc3dlciByYXRoZXIgdGhh'
    || 'biBzd2FsbG93aW5nIGl0LiBBCiAgICAgICAgICAgICAgICAjIGNoYXQgdGhhdCBzaWxlbnRseSByZXR1cm5zIG5vdGhpbmcgcmVhZHMgYXMgInRoZSBhZ2Vu'
    || 'dCBoYWQgbm8KICAgICAgICAgICAgICAgICMgb3BpbmlvbiIsIHdoaWNoIGlzIGEgY2xhaW0gYWJvdXQgdGhlIHF1ZXN0aW9uIHJhdGhlciB0aGFuIGFib3V0'
    || 'CiAgICAgICAgICAgICAgICAjIHRoZSBjYWxsIHRoYXQgZmFpbGVkLgogICAgICAgICAgICAgICAgb3V0ID0gKCJUaGUgYWdlbnQgY291bGQgbm90IGFuc3dl'
    || 'cjogIiArIHR5cGUoZXhjKS5fX25hbWVfXyArICI6ICIKICAgICAgICAgICAgICAgICAgICAgICArIHN0cihleGMpWzozMDBdKQogICAgICAgIHN0LnNlc3Np'
    || 'b25fc3RhdGVbaGlzdF9rZXldLmFwcGVuZCgoYXNrZWQsIHN0cihvdXQpKSkKICAgICAgICBzdC5yZXJ1bigpCiAgICBzdC5kaXZpZGVyKCkKCgpkZWYgY29u'
    || 'dHJvbF92YWx1ZXMoc2Vzc2lvbiwgdGd0OiBzdHIpIC0+IGRpY3Q6CiAgICAiIiJSZW5kZXIgdGhlIGRlY2xhcmVkIGNvbnRyb2xzIGFuZCByZXR1cm4ge25h'
    || 'bWU6IGN1cnJlbnQgdmFsdWV9LgoKICAgIEFCT1ZFIFRIRSBEQVNIQk9BUkQsIHVubGlrZSBjb25maWdfYmFyIGFuZCBwcm9tb3Rpb25fYmFyLCBhbmQgdGhl'
    || 'IGRpZmZlcmVuY2UgaXMKICAgIHRoZSBwb2ludC4gVGhlc2UgY29udHJvbHMgZGVjaWRlIFdIQVQgVEhFIFBBR0UgSVMgQUJPVVQgLS0gd2hpY2ggbWV0cm8s'
    || 'IHdoaWNoCiAgICB3aW5kb3csIHdoaWNoIG1pbmltdW0gc2NvcmUgLS0gc28gdGhleSBiZWxvbmcgd2hlcmUgeW91IHdvdWxkIGxvb2sgYmVmb3JlCiAgICBy'
    || 'ZWFkaW5nLiBjb25maWdfYmFyIHR1bmVzIHRoZSBydWxlcyBiZWhpbmQgdGhlIG51bWJlcnMgYW5kIHByb21vdGlvbl9iYXIgYWN0cyBvbgogICAgdGhlbSwg'
    || 'd2hpY2ggaXMgd2h5IGJvdGggb2YgdGhvc2Ugc2l0IHVuZGVybmVhdGguCgogICAgV2lkZ2V0cywgbm90IFJlYWN0LCBmb3IgdGhlIHNhbWUgcGh5c2ljYWwg'
    || 'cmVhc29uIGV2ZXJ5dGhpbmcgZWxzZSBoZXJlIGlzOiB0aGUKICAgIGJ1bmRsZSBydW5zIGluIGEgc2FuZGJveGVkIGlmcmFtZSB3aXRoIG5vIHNlc3Npb24s'
    || 'IHNvIGEgUmVhY3Qgc2VsZWN0Ym94IGNhbm5vdAogICAgcmUtcXVlcnkuIFRoaXMgaXMgd2hlcmUgdGhlIGNob29zaW5nIGhhcHBlbnM7IHRoZSBwYWdlIGJl'
    || 'bG93IHJlLXJlbmRlcnMgZnJvbSBhCiAgICBwYXlsb2FkIHRoZSBob3N0IGZldGNoZXMgYWdhaW4gb24gdGhlIHJlc3VsdGluZyByZXJ1bi4KCiAgICBTb2x1'
    || 'dGlvbnMgdGhhdCBkZWNsYXJlIG5vIGNvbnRyb2xzIGRyYXcgTk9USElORyAtLSBubyBoZWFkZXIsIG5vIGV4cGFuZGVyLCBubwogICAgZW1wdHkgcm93LiBT'
    || 'YW1lIGFyZ3VtZW50IGFzIGxvYWRfcnVsZV9jb25maWcgZ2F0aW5nIG9uIFZfUlVMRV9DT05GSUc6IGEgc29sdXRpb24KICAgIHRoYXQgbmV2ZXIgb3B0ZWQg'
    || 'aW4gbXVzdCBub3QgZ3JvdyBhIGNvbnRyb2wgc3VyZmFjZSBieSBhY2NpZGVudC4KCiAgICBBIGZhaWxlZCBvcHRpb25zIHF1ZXJ5IGNvc3RzIHRoYXQgT05F'
    || 'IGNvbnRyb2wgaXRzIGxpc3QgYW5kIG5vdGhpbmcgZWxzZSwgYW5kIGl0CiAgICBzYXlzIHNvLiBGYWxsaW5nIGJhY2sgdG8gYSBzaWxlbnQgZW1wdHkgc2Vs'
    || 'ZWN0Ym94IHdvdWxkIHJlYWQgYXMgInRoZXJlIGFyZSBubwogICAgbWV0cm9zIiwgYSBjbGFpbSBhYm91dCB0aGUgY3VzdG9tZXIncyBkYXRhIHJhdGhlciB0'
    || 'aGFuIGFib3V0IG91ciBxdWVyeS4KICAgICIiIgogICAgaWYgbm90IENPTlRST0xTOgogICAgICAgIHJldHVybiB7fQogICAgcGFyYW1zID0ge30KICAgIGNv'
    || 'bHMgPSBzdC5jb2x1bW5zKG1pbihsZW4oQ09OVFJPTFMpLCA0KSkKICAgIGZvciBpLCBzcGVjIGluIGVudW1lcmF0ZShDT05UUk9MUyk6CiAgICAgICAga2V5'
    || 'ID0gc3RyKHNwZWMuZ2V0KCJrZXkiKSBvciAiIikKICAgICAgICBpZiBub3Qga2V5OgogICAgICAgICAgICBjb250aW51ZQogICAgICAgIGxhYmVsID0gc3Ry'
    || 'KHNwZWMuZ2V0KCJsYWJlbCIpIG9yIGtleSkKICAgICAgICBraW5kID0gc3RyKHNwZWMuZ2V0KCJraW5kIikgb3IgInRleHQiKS5sb3dlcigpCiAgICAgICAg'
    || 'ZGVmYXVsdCA9IHNwZWMuZ2V0KCJkZWZhdWx0IikKICAgICAgICBoZWxwX3R4dCA9IHNwZWMuZ2V0KCJoZWxwIikgb3IgTm9uZQogICAgICAgIHdrZXkgPSAi'
    || 'Y3RsXyIgKyBrZXkKICAgICAgICB3aXRoIGNvbHNbaSAlIGxlbihjb2xzKV06CiAgICAgICAgICAgIGlmIGtpbmQgPT0gInNlbGVjdCI6CiAgICAgICAgICAg'
    || 'ICAgICBvcHRpb25zID0gc3BlYy5nZXQoIm9wdGlvbnMiKQogICAgICAgICAgICAgICAgaWYgbm90IG9wdGlvbnMgYW5kIHNwZWMuZ2V0KCJvcHRpb25zX3Nx'
    || 'bCIpOgogICAgICAgICAgICAgICAgICAgIHRyeToKICAgICAgICAgICAgICAgICAgICAgICAgb3B0aW9ucyA9IFsKICAgICAgICAgICAgICAgICAgICAgICAg'
    || 'ICAgIHJbMF0gZm9yIHIgaW4gc2Vzc2lvbi5zcWwoCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgc3RyKHNwZWNbIm9wdGlvbnNfc3FsIl0pLnJl'
    || 'cGxhY2UoInt0Z3R9IiwgdGd0KQogICAgICAgICAgICAgICAgICAgICAgICAgICAgKS5saW1pdCgxMDAwKS5jb2xsZWN0KCldCiAgICAgICAgICAgICAgICAg'
    || 'ICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBleGM6CiAgICAgICAgICAgICAgICAgICAgICAgIHN0LmNhcHRpb24obGFiZWwgKyAiIFx1MDBiNyBjb3VsZCBub3Qg'
    || 'bG9hZCBjaG9pY2VzOiAiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgKyB0eXBlKGV4YykuX19uYW1lX18pCiAgICAgICAgICAgICAgICAg'
    || 'ICAgICAgIG9wdGlvbnMgPSBbXQogICAgICAgICAgICAgICAgb3B0aW9ucyA9IFtvIGZvciBvIGluIChvcHRpb25zIG9yIFtdKSBpZiBvIGlzIG5vdCBOb25l'
    || 'XQogICAgICAgICAgICAgICAgaWYgbm90IG9wdGlvbnM6CiAgICAgICAgICAgICAgICAgICAgIyBOb3RoaW5nIHRvIGNob29zZSBmcm9tIGlzIG5vdCB0aGUg'
    || 'c2FtZSBhcyBhbiBlbXB0eSBjaG9pY2UuCiAgICAgICAgICAgICAgICAgICAgIyBCaW5kIHRoZSBkZWZhdWx0IHNvIHRoZSBwYW5lbCBzdGlsbCBydW5zIGFu'
    || 'ZCBzdGlsbCBzYXlzIHdoYXQKICAgICAgICAgICAgICAgICAgICAjIGl0IHJhbiB3aXRoLgogICAgICAgICAgICAgICAgICAgIHBhcmFtc1trZXldID0gZGVm'
    || 'YXVsdAogICAgICAgICAgICAgICAgICAgIHN0LmNhcHRpb24obGFiZWwgKyAiIFx1MDBiNyBubyBjaG9pY2VzIGF2YWlsYWJsZSIpCiAgICAgICAgICAgICAg'
    || 'ICAgICAgY29udGludWUKICAgICAgICAgICAgICAgIGlkeCA9IG9wdGlvbnMuaW5kZXgoZGVmYXVsdCkgaWYgZGVmYXVsdCBpbiBvcHRpb25zIGVsc2UgMAog'
    || 'ICAgICAgICAgICAgICAgcGFyYW1zW2tleV0gPSBzdC5zZWxlY3Rib3gobGFiZWwsIG9wdGlvbnMsIGluZGV4PWlkeCwga2V5PXdrZXksCiAgICAgICAgICAg'
    || 'ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBoZWxwPWhlbHBfdHh0KQogICAgICAgICAgICBlbGlmIGtpbmQgPT0gInNsaWRlciI6CiAgICAgICAg'
    || 'ICAgICAgICBsbyA9IHNwZWMuZ2V0KCJtaW4iLCAwKQogICAgICAgICAgICAgICAgaGkgPSBzcGVjLmdldCgibWF4IiwgMTAwKQogICAgICAgICAgICAgICAg'
    || 'cGFyYW1zW2tleV0gPSBzdC5zbGlkZXIoCiAgICAgICAgICAgICAgICAgICAgbGFiZWwsIG1pbl92YWx1ZT1sbywgbWF4X3ZhbHVlPWhpLAogICAgICAgICAg'
    || 'ICAgICAgICAgIHZhbHVlPWRlZmF1bHQgaWYgZGVmYXVsdCBpcyBub3QgTm9uZSBlbHNlIGxvLAogICAgICAgICAgICAgICAgICAgIHN0ZXA9c3BlYy5nZXQo'
    || 'InN0ZXAiLCAxKSwga2V5PXdrZXksIGhlbHA9aGVscF90eHQpCiAgICAgICAgICAgIGVsaWYga2luZCA9PSAibnVtYmVyIjoKICAgICAgICAgICAgICAgIHBh'
    || 'cmFtc1trZXldID0gc3QubnVtYmVyX2lucHV0KAogICAgICAgICAgICAgICAgICAgIGxhYmVsLCB2YWx1ZT1kZWZhdWx0IGlmIGRlZmF1bHQgaXMgbm90IE5v'
    || 'bmUgZWxzZSAwLAogICAgICAgICAgICAgICAgICAgIG1pbl92YWx1ZT1zcGVjLmdldCgibWluIiksIG1heF92YWx1ZT1zcGVjLmdldCgibWF4IiksCiAgICAg'
    || 'ICAgICAgICAgICAgICAgc3RlcD1zcGVjLmdldCgic3RlcCIsIDEpLCBrZXk9d2tleSwgaGVscD1oZWxwX3R4dCkKICAgICAgICAgICAgZWxzZToKICAgICAg'
    || 'ICAgICAgICAgIHBhcmFtc1trZXldID0gc3QudGV4dF9pbnB1dCgKICAgICAgICAgICAgICAgICAgICBsYWJlbCwgdmFsdWU9IiIgaWYgZGVmYXVsdCBpcyBO'
    || 'b25lIGVsc2Ugc3RyKGRlZmF1bHQpLAogICAgICAgICAgICAgICAgICAgIGtleT13a2V5LCBoZWxwPWhlbHBfdHh0KQogICAgcmV0dXJuIHBhcmFtcwoKCmRl'
    || 'ZiBtYWluKCkgLT4gTm9uZToKICAgIHRyeToKICAgICAgICBzZXNzaW9uID0gZ2V0X2FjdGl2ZV9zZXNzaW9uKCkKICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMg'
    || 'ZXhjOgogICAgICAgICMgTm8gc2Vzc2lvbiBtZWFucyB0aGUgYXBwIGNhbm5vdCBxdWVyeSBhbnl0aGluZy4gU2F5IHRoYXQgcGxhaW5seQogICAgICAgICMg'
    || 'aW5zdGVhZCBvZiByZW5kZXJpbmcgZW1wdHkgcGFuZWxzIHRoYXQgbG9vayBsaWtlIHJlYWwgemVyb2VzLgogICAgICAgIGNvbXBvbmVudHMuaHRtbChidWls'
    || 'ZF9odG1sKHsiY29udGV4dCI6IHt9LCAicGFuZWxzIjoge30sCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJmYXRhbCI6ICJObyBhY3Rp'
    || 'dmUgU25vd2ZsYWtlIHNlc3Npb246ICIgKyBzdHIoZXhjKX0pLAogICAgICAgICAgICAgICAgICAgICAgICBoZWlnaHQ9NDAwLCBzY3JvbGxpbmc9RmFsc2Up'
    || 'CiAgICAgICAgcmV0dXJuCgogICAgdGd0ID0gdGFyZ2V0X3NjaGVtYShzZXNzaW9uKQogICAgbmF2aWdhdGlvbiA9IGFwcF9uYXZpZ2F0aW9uKHNlc3Npb24s'
    || 'IHRndCkKICAgICMgQkVGT1JFIHJ1bl9wYW5lbHMsIGJlY2F1c2UgdGhlaXIgdmFsdWVzIGFyZSB3aGF0IHRoZSBwYW5lbHMgYXJlIGZpbHRlcmVkIGJ5Lgog'
    || 'ICAgcGFyYW1zID0gY29udHJvbF92YWx1ZXMoc2Vzc2lvbiwgdGd0KQogICAgcGFuZWxzID0gcnVuX3BhbmVscyhzZXNzaW9uLCB0Z3QsIHBhcmFtcykKICAg'
    || 'IGN1c3RvbWl6YXRpb24sIGN1c3RvbV9wYW5lbHMsIGN1c3RvbWl6YXRpb25fZXJyb3IgPSBsb2FkX2N1c3RvbWl6YXRpb24oc2Vzc2lvbiwgdGd0KQogICAg'
    || 'cGFuZWxzLnVwZGF0ZShjdXN0b21fcGFuZWxzKQogICAgIyBUaGUgc2hlbGwncyBNT0RFIGJhbm5lciBhbmQgYnVpbGQgcHJvdmVuYW5jZSBjb21lIGZyb20g'
    || 'dGhlIGBjb250ZXh0YCBwYW5lbC4KICAgICMgSWYgaXQgZmFpbGVkLCBzYXkgc28gdGhyb3VnaCB0aGUgbm9ybWFsIGNvbnRleHQgZmllbGRzIHJhdGhlciB0'
    || 'aGFuIGxlYXZpbmcKICAgICMgTU9ERSBibGFuayAtLSBhIHBhZ2Ugd2l0aCBubyBtb2RlIGJhZGdlIGlzIGEgcGFnZSB0aGF0IGNvdWxkIGJlIHNob3dpbmcK'
    || 'ICAgICMgc2VlZGVkIG51bWJlcnMgd2l0aCBub3RoaW5nIHRvIHNheSBzby4KICAgIGN0eCA9IHt9CiAgICBnb3QgPSBwYW5lbHMuZ2V0KCJjb250ZXh0Iiwg'
    || 'e30pCiAgICBpZiAicm93cyIgaW4gZ290IGFuZCBnb3RbInJvd3MiXToKICAgICAgICBjdHggPSBnb3RbInJvd3MiXVswXQogICAgZWxzZToKICAgICAgICBj'
    || 'dHggPSB7IlNPTFVUSU9OIjogU09MVVRJT05fTkFNRSwgIkJVSUxUX0lOIjogdGd0LCAiTU9ERSI6ICJVTktOT1dOIn0KCiAgICBjb21wb25lbnRzLmh0bWwo'
    || 'YnVpbGRfaHRtbCh7ImNvbnRleHQiOiBjdHgsICJwYW5lbHMiOiBwYW5lbHMsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgImN1c3RvbWl6YXRp'
    || 'b24iOiBjdXN0b21pemF0aW9uLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJjdXN0b21pemF0aW9uX2Vycm9yIjogY3VzdG9taXphdGlvbl9l'
    || 'cnJvciwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAibmF2aWdhdGlvbiI6IG5hdmlnYXRpb259KSwKICAgICAgICAgICAgICAgICAgICBoZWln'
    || 'aHQ9MTgwMCwgc2Nyb2xsaW5nPVRydWUpCgogICAgaWYgc3QuYnV0dG9uKCJSZWZyZXNoIGRhdGEiLCBrZXk9InJlZnJlc2hfcGFuZWxfZGF0YSIpOgogICAg'
    || 'ICAgIGludmFsaWRhdGVfcGFuZWxfY2FjaGUoKQogICAgICAgIGlmIGhhc2F0dHIoc3QsICJyZXJ1biIpOgogICAgICAgICAgICBzdC5yZXJ1bigpCiAgICAg'
    || 'ICAgZWxzZToKICAgICAgICAgICAgc3QuZXhwZXJpbWVudGFsX3JlcnVuKCkKCiAgICAjIEFGVEVSIHRoZSBkYXNoYm9hcmQgYW5kIEJFRk9SRSB0aGUgcHJv'
    || 'bW90aW9uIGJhci4gVGhlIG9yZGVyIGlzIGFuIGFyZ3VtZW50OgogICAgIyB0aGUgcnVsZXMgZXhwbGFpbiB0aGUgbnVtYmVycyBpbW1lZGlhdGVseSBhYm92'
    || 'ZSB0aGVtLCBhbmQgdGhlIHByb21vdGlvbiBiYXIKICAgICMgaXMgdGhlICJ3aGF0IGRvIEkgZG8gYWJvdXQgdGhpcyIgdGhhdCBzaG91bGQgY29tZSBsYXN0'
    || 'LiBBIHJlYWRlciB3aG8gY2hhbmdlcwogICAgIyBhIHRocmVzaG9sZCBoZXJlIGlzIHN0aWxsIHJlYWRpbmcgdGhlIGRhc2hib2FyZDsgYSByZWFkZXIgYXQg'
    || 'dGhlIHByb21vdGlvbgogICAgIyBiYXIgaGFzIGZpbmlzaGVkLiBTb2x1dGlvbnMgd2l0aG91dCBWX1JVTEVfQ09ORklHIGRyYXcgbm90aGluZyBhdCBhbGwu'
    || 'CiAgICBjb25maWdfYmFyKHNlc3Npb24sIHRndCkKCiAgICAjIEJFVFdFRU4gdGhlIHJ1bGVzIGFuZCB0aGUgYWN0aW9ucy4gVGhlIGFnZW50IGV4cGxhaW5z'
    || 'IHdoYXQgdGhlIG51bWJlcnMgbWVhbgogICAgIyBhbmQgaXMgbW9zdCB1c2VmdWwgaW1tZWRpYXRlbHkgYmVmb3JlIHRoZSBkZWNpc2lvbiBpdCBpbmZvcm1z'
    || 'OyBzb2x1dGlvbnMgdGhhdAogICAgIyBkZWNsYXJlIG5vIFZfQUdFTlRfQ0hBVCBkcmF3IG5vdGhpbmcgYXQgYWxsLgogICAgYWdlbnRfYmFyKHNlc3Npb24s'
    || 'IHRndCkKCiAgICAjIEFGVEVSIHRoZSBkYXNoYm9hcmQsIG5vdCBiZWZvcmUuIFRoZSBwcm9tb3Rpb24gYmFyIGlzIHRoZSBhbnN3ZXIgdG8gIndoYXQgZG8K'
    || 'ICAgICMgSSBkbyBhYm91dCB0aGlzPyIsIGFuZCB0aGF0IHF1ZXN0aW9uIG9ubHkgbWFrZXMgc2Vuc2Ugb25jZSB0aGUgbnVtYmVycyBhYm92ZQogICAgIyBp'
    || 'dCBoYXZlIGJlZW4gcmVhZC4gUHV0dGluZyBpdCBvbiB0b3Agd291bGQgYWxzbyBwdXNoIHRoZSB3aG9sZSBkYXNoYm9hcmQKICAgICMgYmVsb3cgdGhlIGZv'
    || 'bGQgb24gYSBsYXB0b3AuCiAgICBwcm9tb3Rpb25fYmFyKHNlc3Npb24sIHRndCkKCgptYWluKCkK';

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
    'CREATE OR REPLACE STREAMLIT ' || :tgt || '.COSTEFF_APP '
 || 'ROOT_LOCATION = ''@' || :tgt || '.APP_STAGE'' MAIN_FILE = ''streamlit_app.py'' '
 || 'QUERY_WAREHOUSE = ' || :wh || ' COMMENT = ''Warehouse Cost Efficiency — generated from account discovery''');

  -- The app runs on the app warehouse whenever someone opens it. Auto-suspend
  -- makes this small, but it is not zero and the operator should see it.
  cost_day    := :cost_day + 0.10;
  cost_detail := ARRAY_APPEND(:cost_detail,
    'Streamlit app on ' || :wh || ' ~0.10 credits/day. ASSUMES an XS warehouse, '
 || 'auto-suspend 60s, and roughly 20 page views/day. Heavier use scales this linearly.');
  dials       := ARRAY_APPEND(:dials,
    'Point COSTEFF_APP_WAREHOUSE at an XS warehouse to cut app cost');
  -- Only claim the app exists when this snippet is present. The template used to
  -- print "OPEN THE APP" unconditionally, which told operators to open a
  -- Streamlit object that was never created for solutions built without a UI.
  -- Two independent reviewers caught it; it now lives with the code that
  -- actually creates the app.
  notes       := ARRAY_APPEND(:notes,
    'OPEN THE APP after building: Snowsight > Projects > Streamlit > COSTEFF_APP');
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
                 || 'deterministic refusal from ' || 'COSTEFF' || '_MIN_FILL_PCT = ' || :min_fill
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
   || 'columns. Set COSTEFF_PROFILE = TRUE and re-run to close it.');
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
    override_asked := (SELECT TRY_CAST($COSTEFF_OVERRIDE_REVIEW::VARCHAR AS BOOLEAN));
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
    || 'SOLUTION: Warehouse Cost Efficiency' || CHR(10)
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
        || 'COSTEFF_APPROVE is TRUE. To build anyway set COSTEFF_OVERRIDE_REVIEW = TRUE; '
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
             || 'COSTEFF_BUDGET_CREDITS = ' || :budget || '. Nothing was created.' AS statement
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
    approved := (SELECT TRY_CAST($COSTEFF_APPROVE::VARCHAR AS BOOLEAN));
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
   || 'COSTEFF_OVERRIDE_REVIEW = TRUE, so the build proceeded anyway. The verdict and '
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
       '# ' || 'Warehouse Cost Efficiency' || ' — discovery packet' || CHR(10) || CHR(10)
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
      'solution', 'Warehouse Cost Efficiency', 'run_id', :run_id, 'tier', :tier,
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
             COALESCE(NULLIF(:headline, ''), 'Warehouse Cost Efficiency') AS statement
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
                 'no ceiling set (COSTEFF_BUDGET_CREDITS = 0)')
      UNION ALL SELECT 5, 'REVIEW',
             :review_verdict || ' (' || :review_status || ') · '
             || ARRAY_SIZE(:review_findings) || ' finding(s)'
      UNION ALL SELECT 6, 'WHY THE GATE IS CLOSED',
             CASE WHEN :gate_closed_by = 'DETERMINISTIC CHECK' THEN :hard_block
                  WHEN :gate_closed_by = 'REVIEW VERDICT'
                    THEN 'The review returned DO_NOT_PROCEED. Read the findings above. '
                      || 'To build anyway set COSTEFF_OVERRIDE_REVIEW = TRUE.'
                  ELSE 'COSTEFF_APPROVE is FALSE. Nothing was created.' END
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
   || 'LET r_task RESULTSET := (SELECT TARGET_FQN FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ''TASK''); FOR t_rec IN r_task DO BEGIN EXECUTE IMMEDIATE ''ALTER TASK IF EXISTS '' || t_rec.TARGET_FQN || '' SUSPEND''; EXECUTE IMMEDIATE ''DROP TASK IF EXISTS '' || t_rec.TARGET_FQN; detached := :detached + 1; EXCEPTION WHEN OTHER THEN failed := :failed + 1; failed_items := ARRAY_APPEND(:failed_items, t_rec.TARGET_FQN || '': '' || SQLERRM); END; END FOR; DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ''TASK''; LET r_wh RESULTSET := (SELECT TARGET_FQN, ARTIFACT, ARGUMENTS FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ''WAREHOUSE_SETTING''); FOR wh_rec IN r_wh DO BEGIN EXECUTE IMMEDIATE ''ALTER WAREHOUSE '' || wh_rec.TARGET_FQN || '' SET '' || wh_rec.ARTIFACT || '' = '' || wh_rec.ARGUMENTS; detached := :detached + 1; EXCEPTION WHEN OTHER THEN failed := :failed + 1; failed_items := ARRAY_APPEND(:failed_items, wh_rec.TARGET_FQN || '': '' || SQLERRM); END; END FOR; LET r_fx RESULTSET := (SELECT TARGET_FQN FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ''FIXTURE_WAREHOUSE''); FOR fx_rec IN r_fx DO BEGIN EXECUTE IMMEDIATE ''DROP WAREHOUSE IF EXISTS '' || fx_rec.TARGET_FQN; detached := :detached + 1; EXCEPTION WHEN OTHER THEN failed := :failed + 1; failed_items := ARRAY_APPEND(:failed_items, fx_rec.TARGET_FQN || '': '' || SQLERRM); END; END FOR; DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE KIND IN (''WAREHOUSE_SETTING'', ''FIXTURE_WAREHOUSE''); '
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
