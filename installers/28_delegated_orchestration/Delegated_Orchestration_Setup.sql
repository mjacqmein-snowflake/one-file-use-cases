-- ─────────────────────────────────────────────────────────────────────────────
-- Zero-Privilege Orchestration
-- SETTINGS  ·  the only part of this file intended to be edited
-- ─────────────────────────────────────────────────────────────────────────────

-- The gate. Nothing is created while this is FALSE.
SET DELEG_APPROVE = FALSE;

SET DELEG_VERBOSE_OUTPUT = FALSE;


-- Where to build. Blank means the database currently in use.
SET DELEG_TARGET_DB = '';
SET DELEG_SCHEMA    = 'DELEGATED_ORCHESTRATION';

-- Blank means the warehouse currently in use.
SET DELEG_APP_WAREHOUSE = '';

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
SET DELEG_KEEP_APP_WARM  = FALSE;
SET DELEG_WARM_WAREHOUSE = 'ONESHOT_APP_WH';

-- How long a viewer's own app session survives idling, in minutes, 5 to 240.
-- Higher means someone returning to the tab reconnects to a live session instead
-- of waiting for a new one to start.
--
-- CAVEAT WORTH KNOWING: the account-level WebSocket timeout, about 15 minutes by
-- default, can close the connection before this timer expires, and only Snowflake
-- Support can raise it. Setting 240 here is therefore an upper bound and not a
-- guarantee.
SET DELEG_APP_SLEEP_MINUTES = 240;

-- How far back discovery and the views look.
SET DELEG_WINDOW_DAYS = 14;

-- DISCOVER reads your account and reports what it found.
-- SAMPLE seeds representative data instead, and the app says so on every page.
-- Never demo SAMPLE numbers as if they were the customer's.
SET DELEG_MODE = 'DISCOVER';

-- Credit ceiling for steady-state cost. 0 means no ceiling. When the plan's own
-- estimate exceeds this, Block 3 refuses to plan and tells you what to turn down.
SET DELEG_BUDGET_CREDITS = 0;

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
SET DELEG_DEPLOY_TIER = 'DISCOVER';

-- Names this run in QUERY_TAG so its statements can be found in history later.
-- Blank generates one. Set it yourself only if you are correlating with your own
-- observability.
SET DELEG_RUN_ID = '';

-- Warehouse the LIMITED and PRODUCTION tiers create for their own work. Blank
-- derives a name from the schema. It is XSMALL with a 60-second auto-suspend and
-- it is dropped by TEARDOWN.
SET DELEG_MEASURE_WAREHOUSE = '';

-- Credit quota for the resource monitor on that warehouse. This is a REAL
-- ceiling: the warehouse suspends when it is reached.
--
-- Read what it does NOT cover before you rely on it. A resource monitor governs
-- WAREHOUSES only. It cannot cap serverless features or AI-services tokens --
-- Snowflake's own documentation says to use a BUDGET for those. So on a solution
-- that spends most of its credits on AI, this number is not the ceiling you think
-- it is, and Block 0 prints exactly which categories it does and does not cover.
SET DELEG_CREDIT_CAP = 5;

-- Dollars per credit, for the readable version of every credit figure. Your rate
-- is on your contract; the default is a list-price placeholder, not your price.
SET DELEG_COST_PER_CREDIT = 3;

-- Ratio of output tokens to input tokens, used only to ESTIMATE AI spend before
-- it happens. AI_COUNT_TOKENS counts input tokens and cannot see output tokens,
-- so without this the estimate is systematically low. After a run the real split
-- is measured and the estimate is graded against it.
SET DELEG_OUTPUT_TOKEN_RATIO = 0.5;

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
SET DELEG_PROFILE = FALSE;

-- A column must be at least this percent non-null to be used. Below it, the plan
-- downgrades or refuses the thing that depended on it, and prints why.
SET DELEG_MIN_FILL_PCT = 60;

-- Internal. Do not edit. Block 2 publishes its statistics here in chunks.
SET DELEG_PROFILE_N = 0;

-- ─────────────────────────────────────────────────────────────────────────────
-- REVIEW
-- ─────────────────────────────────────────────────────────────────────────────

-- Block 3 asks the model to review the finished plan against what discovery and
-- the profile actually found, and returns PROCEED, CAVEAT or DO_NOT_PROCEED.
--
-- DO_NOT_PROCEED closes the gate even when DELEG_APPROVE is TRUE. Setting this to
-- TRUE overrides that. It is your call to make and the override is recorded in the
-- output, in the packet and in REVIEW_LOG, because "we were told not to and did it
-- anyway" is a thing your own audit should be able to see.
SET DELEG_OVERRIDE_REVIEW = FALSE;

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
SET DELEG_NOTIFICATION_INTEGRATION = '';


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
SET DELEG_ALLOW_ACTIONS = FALSE;

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
SET DELEG_ALLOW_SAMPLE_ACTIONS = TRUE;

-- Model used to read your discovery results and adapt the plan. Deliberately the
-- strongest available rather than the cheapest: this call decides which of your
-- objects get used and how, and a weaker model gets those judgements wrong in
-- ways that are hard to spot. It runs ONCE per plan, so the cost is negligible.
-- Verified available in this account: claude-opus-5, claude-opus-4-6,
-- openai-gpt-5.2, openai-gpt-5, claude-4-sonnet, mistral-large2.
SET DELEG_MODEL = 'claude-opus-5';

-- Internal. Do not edit. Block 1 publishes its findings here in chunks, because
-- one session variable caps at 16,384 bytes.
SET DELEG_SIGNALS_N = 0;

-- ── Orchestrator role ───────────────────────────────────────────────────────
-- The restricted role your external orchestrator authenticates as -- the Astro,
-- Airflow, Dagster or Control-M service role. This is the role that must end up
-- holding NO privileges on source or target data.
--
-- BLANK MEANS REPORTING ONLY. Discovery still inventories your dbt projects,
-- notebooks, tasks and the anti-patterns it can see, and it still lists the
-- roles that LOOK like orchestrators so you can pick one. It computes no
-- remediation, because a remediation for a role nobody named is a guess.
SET DELEG_ORCHESTRATOR_ROLE = '';

-- ── Execution role ──────────────────────────────────────────────────────────
-- The privileged role that OWNS the tasks and therefore supplies the rights the
-- dbt run executes with. Blank means adopt: this build looks for the role that
-- already owns your dbt project objects and proposes that one, rather than
-- inventing a role your access model has never seen.
SET DELEG_EXEC_ROLE = '';

-- ── Projects in scope ───────────────────────────────────────────────────────
-- Comma-separated fully qualified dbt project objects (DATABASE.SCHEMA.PROJECT).
-- Blank means every dbt project object this role can see.
SET DELEG_PROJECTS = '';

-- ── Delegation mode ─────────────────────────────────────────────────────────
-- OPERATE   the orchestrator triggers the task directly with EXECUTE TASK. It
--           needs OPERATE and MONITOR on that one task, and nothing else.
-- HANDSHAKE the orchestrator inserts a request row and reads a status row. It
--           needs no task privileges at all -- a triggered task on a stream over
--           the request table fires the run. Tighter, at the cost of a trigger
--           interval floor of 30 seconds and a run_id you have to correlate.
SET DELEG_DELEGATION_MODE = 'OPERATE';

-- ── Role creation ───────────────────────────────────────────────────────────
-- FALSE (default) means ADOPTION: this build will propose grants on roles that
-- already exist and will never issue CREATE ROLE. Teardown then removes only the
-- grants it made.
--
-- Setting this TRUE lets the PRODUCTION tier create the execution role if it is
-- missing. Understand what that means for teardown: a role is an account-level
-- object, so a role this build created and your team then started depending on
-- is a role teardown will drop.
SET DELEG_CREATE_ROLES = FALSE;

-- ── Drift monitor cadence ───────────────────────────────────────────────────
-- Minutes between re-derivations of the orchestrator's privilege reach. This is
-- the standing workload and the only thing here that recurs.
-- The dial: doubling this halves the monitor's credit consumption.
SET DELEG_DRIFT_CADENCE_MINUTES = 1440;


-- ─────────────────────────────────────────────────────────────────────────────
-- BLOCK 0 · PRE-FLIGHT
-- Answers only the questions that decide whether the rest can run.
-- Creates nothing. Reads no business data.
-- ─────────────────────────────────────────────────────────────────────────────
EXECUTE IMMEDIATE $$
DECLARE
  res RESULTSET;
BEGIN
  LET db   STRING := COALESCE(NULLIF($DELEG_TARGET_DB::VARCHAR, ''), CURRENT_DATABASE());
  LET wh   STRING := COALESCE(NULLIF($DELEG_APP_WAREHOUSE::VARCHAR, ''), CURRENT_WAREHOUSE());
  LET sch  STRING := $DELEG_SCHEMA::VARCHAR;
  LET mode STRING := UPPER(COALESCE($DELEG_MODE::VARCHAR, 'DISCOVER'));
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
      COALESCE(NULLIF($DELEG_MODEL::VARCHAR, ''), 'claude-opus-5'), 'Reply with OK.'));
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
  LET tier      STRING := UPPER(COALESCE(NULLIF($DELEG_DEPLOY_TIER::VARCHAR, ''), 'DISCOVER'));
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
  LET ni       STRING := COALESCE(NULLIF($DELEG_NOTIFICATION_INTEGRATION::VARCHAR, ''), '');
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
    profile_on := (SELECT TRY_CAST($DELEG_PROFILE::VARCHAR AS BOOLEAN));
  EXCEPTION WHEN OTHER THEN profile_on := FALSE;
  END;
  LET cap NUMBER(38,2) := COALESCE((SELECT TRY_CAST($DELEG_CREDIT_CAP::VARCHAR AS NUMBER)), 0);


  LET approved BOOLEAN := FALSE;
  BEGIN
    approved := (SELECT TRY_CAST($DELEG_APPROVE::VARCHAR AS BOOLEAN));
  EXCEPTION WHEN OTHER THEN approved := FALSE;
  END;


  res := (
    SELECT 1 AS step, 'TARGET DATABASE' AS check_name,
           COALESCE(:db, 'NONE SELECTED') AS finding,
           IFF(:db IS NULL, 'Run USE DATABASE, or set DELEG_TARGET_DB.',
               IFF(:db_ok, '', 'Grant CREATE SCHEMA on this database, or point at one you own.')) AS fix
    UNION ALL SELECT 2, 'CREATE SCHEMA', IFF(:db_ok, 'AUTHORIZED', 'NOT AUTHORIZED'),
           IFF(:db_ok, '', 'GRANT CREATE SCHEMA ON DATABASE ' || COALESCE(:db, '<db>') || ' TO ROLE ' || CURRENT_ROLE())
    UNION ALL SELECT 3, 'WAREHOUSE', COALESCE(:wh, 'NONE SELECTED'),
           IFF(:wh IS NULL, 'Run USE WAREHOUSE, or set DELEG_APP_WAREHOUSE.', '')
    UNION ALL SELECT 4, 'ACCOUNT_USAGE', IFF(:au_ok, 'READABLE', 'NOT READABLE'),
           IFF(:au_ok, '', 'GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE ' || CURRENT_ROLE())
    UNION ALL SELECT 5, 'CORTEX (' || COALESCE(NULLIF($DELEG_MODEL::VARCHAR, ''), 'claude-opus-5')
           || ')', IFF(:cortex_ok, 'AVAILABLE', 'NOT AVAILABLE'),
           IFF(:cortex_ok, '', 'GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE ' || CURRENT_ROLE()
               || ' — without it the agent is skipped and the dashboard still builds.')
    UNION ALL SELECT 6, 'EXISTING SCHEMA', IFF(:existing > 0, :db || '.' || :sch || ' ALREADY EXISTS', 'not present'),
           IFF(:existing > 0, 'A previous build is there. Re-running updates it in place; CALL ' || :db || '.' || :sch || '.TEARDOWN() removes it.', '')
    UNION ALL SELECT 7, 'MODE', :mode,
           IFF(:mode = 'SAMPLE', 'Seeded data. The app will label every page SAMPLE DATA. Do not present these numbers as the customer''s.', 'Reads this account.')
    UNION ALL SELECT 8, 'GATE', IFF(:approved, 'OPEN — Block 3 will build', 'CLOSED — nothing will be created'),
           IFF(:approved, 'Review the plan below before you let this run.', 'To build: set DELEG_APPROVE = TRUE and run the file again.')
    UNION ALL SELECT 9, 'DEPLOY TIER', :tier,
           CASE :tier
             WHEN 'DISCOVER' THEN 'Costs below are ARITHMETIC ESTIMATES. Nothing is measured at this tier. Set DELEG_DEPLOY_TIER = ''LIMITED'' to get a real number.'
             WHEN 'LIMITED' THEN 'Builds on its own capped warehouse so credits can be measured and attributed to this run.'
             WHEN 'PRODUCTION' THEN 'Full scope plus monitor, budget, tags, error notification and an operations view.'
             ELSE 'Unrecognised tier — treated as DISCOVER. Use DISCOVER, LIMITED or PRODUCTION.'
           END
    UNION ALL SELECT 10, 'PROFILE', IFF(:profile_on, 'ON — will sample the columns the plan uses',
                                        'OFF — column populated-ness will NOT be checked'),
           IFF(:profile_on,
               'Reads a sample of named columns only. Emits aggregates: null rate, distinct count, row count, type, and min/max for DATE columns only.',
               'This is the gap that lets a plan build on a column that exists and is empty. Set DELEG_PROFILE = TRUE to close it. The review will return CAVEAT rather than PROCEED while it is off.')
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
  LET w    INT    := COALESCE((SELECT TRY_CAST($DELEG_WINDOW_DAYS::VARCHAR AS INT)), 14);
  LET db   STRING := COALESCE(NULLIF($DELEG_TARGET_DB::VARCHAR, ''), CURRENT_DATABASE());
  LET mode STRING := UPPER(COALESCE($DELEG_MODE::VARCHAR, 'DISCOVER'));
  LET sig  OBJECT := OBJECT_CONSTRUCT();
  LET cnt  OBJECT := OBJECT_CONSTRUCT();


  -- ── Probes ────────────────────────────────────────────────────────────────
  -- One BEGIN/EXCEPTION per signal. Copy the shape; do not merge them, because
  -- a merged probe turns one unreadable view into a dead run.
  --
  -- Every probe reads METADATA ONLY and each has its own exception block, so one
  -- missing privilege costs one panel rather than the whole run.

  -- ── Probe: dbt project objects in the account ──────────────────────────────
  -- SHOW is used rather than ACCOUNT_USAGE because ACCOUNT_USAGE has a latency of
  -- up to two hours and a project deployed this morning is exactly the one
  -- somebody is asking about.
  BEGIN
    EXECUTE IMMEDIATE 'SHOW DBT PROJECTS IN ACCOUNT';
    LET np INT := (SELECT COUNT(*) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    sig := OBJECT_INSERT(:sig, 'dbt_projects', IFF(:np > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'dbt_projects', :np, TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'dbt_projects', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'dbt_projects', 0, TRUE);
  END;

  -- ── Probe: tasks that execute a dbt project or a notebook ─────────────────
  -- These are the delegation points that already exist. Their OWNER is the whole
  -- question, because the owner is what the run executes as.
  BEGIN
    LET nt INT := (SELECT COUNT(*) FROM SNOWFLAKE.ACCOUNT_USAGE.TASKS
                   WHERE DELETED IS NULL
                     AND (DEFINITION ILIKE '%EXECUTE DBT PROJECT%'
                       OR DEFINITION ILIKE '%EXECUTE NOTEBOOK%'));
    sig := OBJECT_INSERT(:sig, 'deleg_tasks', IFF(:nt > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'deleg_tasks', :nt, TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'deleg_tasks', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'deleg_tasks', 0, TRUE);
  END;

  -- ── Probe: EXECUTE AS USER on a delegation task ────────────────────────────
  -- A task carrying EXECUTE NOTEBOOK and configured EXECUTE AS USER does not
  -- error at creation. It fails when it runs, which is how it survives review.
  -- EXECUTE_AS_USER_ID is populated only for EXECUTE AS USER tasks; an owner's
  -- rights task leaves it NULL.
  BEGIN
    LET nau INT := (SELECT COUNT(*) FROM SNOWFLAKE.ACCOUNT_USAGE.TASKS
                    WHERE DELETED IS NULL
                      AND (DEFINITION ILIKE '%EXECUTE DBT PROJECT%'
                        OR DEFINITION ILIKE '%EXECUTE NOTEBOOK%')
                      AND EXECUTE_AS_USER_ID IS NOT NULL);
    sig := OBJECT_INSERT(:sig, 'as_user_tasks', 'AVAILABLE', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'as_user_tasks', :nau, TRUE);
  EXCEPTION WHEN OTHER THEN
    -- Reports UNKNOWN rather than zero on failure, because zero here would read
    -- as "no anti-patterns found".
    sig := OBJECT_INSERT(:sig, 'as_user_tasks', 'UNKNOWN', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'as_user_tasks', 0, TRUE);
  END;

  -- ── Probe: stored procedures attempting NPO execution ─────────────────────
  -- The workaround that cannot work. Finding these is how you know a team has
  -- already hit the wall and built around it.
  BEGIN
    LET nsp INT := (SELECT COUNT(*) FROM SNOWFLAKE.ACCOUNT_USAGE.PROCEDURES
                    WHERE DELETED IS NULL
                      AND (PROCEDURE_DEFINITION ILIKE '%EXECUTE DBT PROJECT%'
                        OR PROCEDURE_DEFINITION ILIKE '%EXECUTE NOTEBOOK%'));
    sig := OBJECT_INSERT(:sig, 'proc_attempts', IFF(:nsp > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'proc_attempts', :nsp, TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'proc_attempts', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'proc_attempts', 0, TRUE);
  END;

  -- ── Probe: roles that behave like orchestrators ────────────────────────────
  -- Derived from what roles actually DID, not from what they are called. A role
  -- named SVC_ETL that has never executed anything is a weaker signal than an
  -- unremarkably named role that issues EXECUTE TASK every twenty minutes.
  BEGIN
    LET nor INT := (SELECT COUNT(DISTINCT ROLE_NAME)
                    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
                    WHERE START_TIME >= DATEADD(day, -:w, CURRENT_TIMESTAMP())
                      AND (QUERY_TEXT ILIKE '%EXECUTE DBT PROJECT%'
                        OR QUERY_TEXT ILIKE '%EXECUTE NOTEBOOK%'
                        OR QUERY_TEXT ILIKE '%EXECUTE TASK%'));
    sig := OBJECT_INSERT(:sig, 'orchestrator_roles', IFF(:nor > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'orchestrator_roles', :nor, TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'orchestrator_roles', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'orchestrator_roles', 0, TRUE);
  END;

  -- ── Probe: the named orchestrator role, and its data reach ────────────────
  -- The reach number is the one that matters. It counts DISTINCT relations the
  -- role can read or write through the entire role graph, not just its direct
  -- grants, because inheritance is how these roles quietly become wide.
  LET orch_role STRING := UPPER(COALESCE(NULLIF(TRIM($DELEG_ORCHESTRATOR_ROLE::VARCHAR), ''), ''));
  IF (:orch_role = '') THEN
    sig := OBJECT_INSERT(:sig, 'orch_named', 'BLANK', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'orch_reach', 0, TRUE);
  ELSE
    BEGIN
      LET exists_n INT := (SELECT COUNT(*) FROM SNOWFLAKE.ACCOUNT_USAGE.ROLES
                           WHERE DELETED_ON IS NULL AND UPPER(NAME) = :orch_role);
      IF (:exists_n = 0) THEN
        sig := OBJECT_INSERT(:sig, 'orch_named', 'NOT FOUND', TRUE);
        cnt := OBJECT_INSERT(:cnt, 'orch_reach', 0, TRUE);
      ELSE
        -- Direct grants plus everything inherited through granted roles. The
        -- recursive walk is bounded by the role graph, which is small.
        LET reach INT := (
          WITH RECURSIVE r AS (
            SELECT :orch_role AS RN
            UNION ALL
            SELECT UPPER(g.NAME)
            FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES g
            JOIN r ON UPPER(g.GRANTEE_NAME) = r.RN
            WHERE g.GRANTED_ON = 'ROLE' AND g.GRANTED_TO = 'ROLE'
              AND g.PRIVILEGE = 'USAGE' AND g.DELETED_ON IS NULL
          )
          SELECT COUNT(DISTINCT g.TABLE_CATALOG || '.' || g.TABLE_SCHEMA || '.' || g.NAME)
          FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES g
          JOIN r ON UPPER(g.GRANTEE_NAME) = r.RN
          WHERE g.DELETED_ON IS NULL
            AND g.GRANTED_ON IN ('TABLE', 'VIEW', 'MATERIALIZED_VIEW', 'DYNAMIC_TABLE')
            AND g.PRIVILEGE IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'OWNERSHIP'));
        sig := OBJECT_INSERT(:sig, 'orch_named', 'FOUND', TRUE);
        cnt := OBJECT_INSERT(:cnt, 'orch_reach', COALESCE(:reach, 0), TRUE);
      END IF;
    EXCEPTION WHEN OTHER THEN
      sig := OBJECT_INSERT(:sig, 'orch_named', 'NO ACCESS', TRUE);
      cnt := OBJECT_INSERT(:cnt, 'orch_reach', 0, TRUE);
    END;
  END IF;
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
      , 'orchestrator_role', :orch_role
      , 'orch_state', COALESCE(GET(:sig, 'orch_named')::STRING, 'BLANK')
      , 'orch_reach_relations', COALESCE(GET(:cnt, 'orch_reach')::INT, 0)
      , 'dbt_project_n', COALESCE(GET(:cnt, 'dbt_projects')::INT, 0)
      , 'as_user_task_n', COALESCE(GET(:cnt, 'as_user_tasks')::INT, 0)
      , 'as_user_task_state', COALESCE(GET(:sig, 'as_user_tasks')::STRING, 'UNKNOWN')
      , 'proc_attempt_n', COALESCE(GET(:cnt, 'proc_attempts')::INT, 0)
      , 'delegation_mode', UPPER(COALESCE(NULLIF(TRIM($DELEG_DELEGATION_MODE::VARCHAR), ''), 'OPERATE'))
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
    EXECUTE IMMEDIATE 'SET DELEG_SIGNALS_' || (:ci + 1)
                   || ' = ''' || :piece || '''';
    ci := :ci + 1;
  END WHILE;
  EXECUTE IMMEDIATE 'SET DELEG_SIGNALS_N = ' || :nchunks;

  -- Prove the handoff survived rather than assuming it did.
  IF ((SELECT COALESCE(TRY_CAST(GETVARIABLE('DELEG_SIGNALS_N') AS INT), 0)) <> :nchunks) THEN
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
  
  LET db      STRING := COALESCE(NULLIF($DELEG_TARGET_DB::VARCHAR, ''), CURRENT_DATABASE());
  LET min_fill NUMBER(38,2) := COALESCE((SELECT TRY_CAST($DELEG_MIN_FILL_PCT::VARCHAR AS NUMBER)), 60);
  LET sample_rows INT := 10000;
  LET prof_on BOOLEAN := FALSE;
  BEGIN
    prof_on := (SELECT TRY_CAST($DELEG_PROFILE::VARCHAR AS BOOLEAN));
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
                   'Set DELEG_PROFILE = TRUE to check whether the columns this plan '
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
                      || :min_fill || '% floor set by DELEG_MIN_FILL_PCT.'
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
    EXECUTE IMMEDIATE 'SET DELEG_PROFILE_' || (:pi + 1) || ' = ''' || :piece || '''';
    pi := :pi + 1;
  END WHILE;
  EXECUTE IMMEDIATE 'SET DELEG_PROFILE_N = ' || :nchunks;

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
  -- 'DELEG_SIGNALS_' || :i with "argument 0 ... needs to be constant".
  LET nchunks INT := COALESCE((SELECT TRY_CAST(GETVARIABLE('DELEG_SIGNALS_N') AS INT)), 0);
  IF (:nchunks = 0) THEN
    res := (SELECT 0 AS step, 'BLOCKED' AS action,
                   'Block 1 has not run in this session. Run the file top to bottom.' AS statement);
    RETURN TABLE(res);
  END IF;

  LET buf STRING :=
       COALESCE(GETVARIABLE('DELEG_SIGNALS_1'), '')
    || COALESCE(GETVARIABLE('DELEG_SIGNALS_2'), '')
    || COALESCE(GETVARIABLE('DELEG_SIGNALS_3'), '')
    || COALESCE(GETVARIABLE('DELEG_SIGNALS_4'), '')
    || COALESCE(GETVARIABLE('DELEG_SIGNALS_5'), '')
    || COALESCE(GETVARIABLE('DELEG_SIGNALS_6'), '')
    || COALESCE(GETVARIABLE('DELEG_SIGNALS_7'), '')
    || COALESCE(GETVARIABLE('DELEG_SIGNALS_8'), '');

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
  LET db     STRING  := COALESCE(NULLIF($DELEG_TARGET_DB::VARCHAR, ''), CURRENT_DATABASE());
  LET sch    STRING  := $DELEG_SCHEMA::VARCHAR;
  LET wh     STRING  := COALESCE(NULLIF($DELEG_APP_WAREHOUSE::VARCHAR, ''), CURRENT_WAREHOUSE());
  LET budget NUMBER  := COALESCE((SELECT TRY_CAST($DELEG_BUDGET_CREDITS::VARCHAR AS NUMBER)), 0);

  -- ── Reassemble the profile handoff ────────────────────────────────────────
  -- Optional: Block 2 only publishes when its own gate is open. Absent is not
  -- the same as clean, and the difference is carried explicitly in :prof_status
  -- so nothing downstream can read "no findings" out of "never looked".
  LET pchunks INT := COALESCE((SELECT TRY_CAST(GETVARIABLE('DELEG_PROFILE_N') AS INT)), 0);
  LET prof        VARIANT := NULL;
  LET prof_status STRING  := 'NOT RUN';
  IF (:pchunks > 0) THEN
    LET pbuf STRING :=
         COALESCE(GETVARIABLE('DELEG_PROFILE_1'), '')
      || COALESCE(GETVARIABLE('DELEG_PROFILE_2'), '')
      || COALESCE(GETVARIABLE('DELEG_PROFILE_3'), '')
      || COALESCE(GETVARIABLE('DELEG_PROFILE_4'), '');
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
  LET run_id STRING := COALESCE(NULLIF($DELEG_RUN_ID::VARCHAR, ''), UUID_STRING());
  LET tier   STRING := UPPER(COALESCE(NULLIF($DELEG_DEPLOY_TIER::VARCHAR, ''), 'DISCOVER'));
  IF (:tier NOT IN ('DISCOVER', 'LIMITED', 'PRODUCTION')) THEN
    tier := 'DISCOVER';
  END IF;
  LET qtag STRING := TO_JSON(OBJECT_CONSTRUCT(
      'oneshot', 'Zero-Privilege Orchestration', 'prefix', 'DELEG', 'run_id', :run_id, 'tier', :tier));
  LET tag_status STRING := 'NOT SET';
  BEGIN
    EXECUTE IMMEDIATE 'ALTER SESSION SET QUERY_TAG = ''' || REPLACE(:qtag, '''', '''''') || '''';
    tag_status := 'SET';
  EXCEPTION WHEN OTHER THEN
    tag_status := 'REFUSED (' || SQLERRM || ') - warehouse credits for this run '
               || 'cannot be attributed by tag and will read NOT_ATTRIBUTABLE';
  END;

  -- The warehouse the measured tiers build on, and the cap over it.
  LET meas_wh STRING := COALESCE(NULLIF($DELEG_MEASURE_WAREHOUSE::VARCHAR, ''),
                                 LEFT(:sch, 80) || '_ONESHOT_WH');
  LET credit_cap NUMBER(38,2) := COALESCE((SELECT TRY_CAST($DELEG_CREDIT_CAP::VARCHAR AS NUMBER)), 0);
  LET rate NUMBER(38,4) := COALESCE((SELECT TRY_CAST($DELEG_COST_PER_CREDIT::VARCHAR AS NUMBER)), 3);
  LET out_ratio NUMBER(38,4) := COALESCE((SELECT TRY_CAST($DELEG_OUTPUT_TOKEN_RATIO::VARCHAR AS NUMBER)), 0.5);
  LET min_fill NUMBER(38,2) := COALESCE((SELECT TRY_CAST($DELEG_MIN_FILL_PCT::VARCHAR AS NUMBER)), 60);
  LET notif STRING := COALESCE(NULLIF($DELEG_NOTIFICATION_INTEGRATION::VARCHAR, ''), '');

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
                   'No database selected. Run USE DATABASE or set DELEG_TARGET_DB.' AS statement);
    RETURN TABLE(res);
  END IF;
  IF (:wh IS NULL) THEN
    res := (SELECT 0 AS step, 'BLOCKED' AS action,
                   'No warehouse selected. Run USE WAREHOUSE or set DELEG_APP_WAREHOUSE.' AS statement);
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
    (SELECT TRY_CAST($DELEG_ALLOW_ACTIONS::VARCHAR AS BOOLEAN)), FALSE);

  -- SAMPLE tier, governed separately and defaulting TRUE. Kept as its own variable
  -- rather than folded into :allow_actions so that the two authorisations stay
  -- distinguishable everywhere downstream -- the build context records both, and
  -- RUN_ACTION picks the one matching the action's own TIER. COALESCE to TRUE here
  -- because a build produced by an OLDER file that has no DELEG_ALLOW_SAMPLE_ACTIONS
  -- line should still get the new default rather than silently disarming.
  LET allow_sample_actions BOOLEAN := COALESCE(
    (SELECT TRY_CAST($DELEG_ALLOW_SAMPLE_ACTIONS::VARCHAR AS BOOLEAN)), TRUE);

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
  LET adapt_model  STRING  := COALESCE(NULLIF($DELEG_MODEL::VARCHAR, ''), 'claude-opus-5');

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
    (SELECT TRY_CAST($DELEG_KEEP_APP_WARM::VARCHAR AS BOOLEAN)), FALSE);
  LET warm_wh STRING := UPPER(TRIM(COALESCE(
    NULLIF($DELEG_WARM_WAREHOUSE::VARCHAR, ''), 'ONESHOT_APP_WH')));
  -- An explicitly named app warehouse is an instruction, not a default, so
  -- warming leaves it alone rather than silently rehoming the app somewhere else.
  LET wh_named BOOLEAN := (NULLIF($DELEG_APP_WAREHOUSE::VARCHAR, '') IS NOT NULL);
  LET warm_status STRING := 'OFF';

  IF (:warm_on AND :wh_named) THEN
    warm_status := 'DECLINED_EXPLICIT_WAREHOUSE';
    notes := ARRAY_APPEND(:notes,
      'APP WARMING SKIPPED: DELEG_APP_WAREHOUSE names ' || :wh || ' explicitly, so '
   || 'the app stays there rather than being moved to ' || :warm_wh || '. Clear '
   || 'DELEG_APP_WAREHOUSE to let warming manage the app warehouse, or set '
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
   || 'because they all share this warehouse. Set DELEG_KEEP_APP_WARM = FALSE to '
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
      'APP WARMING DEGRADED: DELEG_KEEP_APP_WARM is TRUE but ' || CURRENT_ROLE()
   || ' cannot create a warehouse, so the app stays on ' || :wh || ' and first '
   || 'loads pay for the package cache being rebuilt after every suspend. To fix, '
   || 'either GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE ' || CURRENT_ROLE()
   || ', or have an administrator run: CREATE WAREHOUSE ' || :warm_wh
   || ' WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = NULL AUTO_RESUME = TRUE; then set '
   || 'DELEG_APP_WAREHOUSE = ''' || :warm_wh || '''.');
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
    (SELECT TRY_CAST($DELEG_APP_SLEEP_MINUTES::VARCHAR AS INT)), 240);
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
   || 'COMMENT = ''oneshot Zero-Privilege Orchestration run ' || :run_id || ' - dropped by TEARDOWN''');
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
 || 'CURRENT_TIMESTAMP() AS BUILT_AT, ''Zero-Privilege Orchestration'' AS SOLUTION, '
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
 || '''DELEG'' AS SETTING_PREFIX');

  -- ══════════════════════════════════════════════════════════════════════════
  -- ZERO-PRIVILEGE ORCHESTRATION — the arithmetic
  -- ══════════════════════════════════════════════════════════════════════════
  -- A task runs with the privileges of the role that OWNS it, even when a
  -- different role triggers it. That makes the task the owner's-rights boundary
  -- a stored procedure cannot be, and it is why the orchestrator can hold
  -- OPERATE on one object and nothing else.
  --
  -- The task is not the substance. The substance is the subtraction: privileges
  -- the work genuinely requires, derived from each dbt project's own declared
  -- sources and target, taken away from what the orchestrator role can actually
  -- reach through the whole role graph. What is left over is revocable, and it
  -- is named one row at a time so a security architect reads a list rather than
  -- a claim.

  -- ── 2a. Settings, and the three ways this refuses ─────────────────────────
  -- Every refusal DEGRADES: the schema is still created, the views still exist,
  -- and no statement raises. A refusal that errors teaches the reader nothing
  -- and takes the rest of the report down with it.
  LET deleg_orch_role STRING := '';
  BEGIN
    deleg_orch_role := UPPER(COALESCE(NULLIF(TRIM($DELEG_ORCHESTRATOR_ROLE::VARCHAR), ''), ''));
  EXCEPTION WHEN OTHER THEN deleg_orch_role := '';
  END;

  LET deleg_exec_role STRING := '';
  BEGIN
    deleg_exec_role := UPPER(COALESCE(NULLIF(TRIM($DELEG_EXEC_ROLE::VARCHAR), ''), ''));
  EXCEPTION WHEN OTHER THEN deleg_exec_role := '';
  END;

  LET deleg_proj_setting STRING := '';
  BEGIN
    deleg_proj_setting := COALESCE(NULLIF(TRIM($DELEG_PROJECTS::VARCHAR), ''), '');
  EXCEPTION WHEN OTHER THEN deleg_proj_setting := '';
  END;

  -- OPERATE is the default. Anything unrecognised falls back to OPERATE rather
  -- than silently building the handshake plumbing, because the handshake path
  -- creates a request table and a triggered task and a typo should not.
  LET deleg_mode STRING := 'OPERATE';
  BEGIN
    deleg_mode := UPPER(COALESCE(NULLIF(TRIM($DELEG_DELEGATION_MODE::VARCHAR), ''), 'OPERATE'));
    IF (:deleg_mode NOT IN ('OPERATE', 'HANDSHAKE')) THEN
      notes := ARRAY_APPEND(:notes,
        'DELEG_DELEGATION_MODE was set to ' || :deleg_mode || ', which is not a mode this '
     || 'solution knows. Falling back to OPERATE. The two values are OPERATE '
     || '(the orchestrator triggers the graph with EXECUTE TASK) and HANDSHAKE '
     || '(the orchestrator inserts a request row and reads a status row).');
      deleg_mode := 'OPERATE';
    END IF;
  EXCEPTION WHEN OTHER THEN deleg_mode := 'OPERATE';
  END;

  LET deleg_create_roles BOOLEAN := FALSE;
  BEGIN
    deleg_create_roles := COALESCE((SELECT TRY_CAST($DELEG_CREATE_ROLES::VARCHAR AS BOOLEAN)), FALSE);
  EXCEPTION WHEN OTHER THEN deleg_create_roles := FALSE;
  END;

  -- A customer can SET the cadence to 0, and 0 divides into the runs-per-month
  -- arithmetic below. Guarded here, once, rather than at each of the three
  -- places that divide by it -- and the substitution is REPORTED, because
  -- quietly running daily when someone asked for zero is its own surprise.
  LET deleg_cadence_raw NUMBER(38,4) := NULL;
  BEGIN
    deleg_cadence_raw := (SELECT TRY_CAST($DELEG_DRIFT_CADENCE_MINUTES::VARCHAR AS NUMBER));
  EXCEPTION WHEN OTHER THEN deleg_cadence_raw := NULL;
  END;
  LET deleg_cadence_min NUMBER(38,4) := 1440;
  IF (:deleg_cadence_raw IS NULL OR :deleg_cadence_raw <= 0) THEN
    deleg_cadence_min := 1440;
    notes := ARRAY_APPEND(:notes,
      'DELEG_DRIFT_CADENCE_MINUTES was ' || COALESCE(:deleg_cadence_raw::STRING, 'blank')
   || ', which cannot be a cadence -- a zero or negative interval divides into '
   || 'the run-rate arithmetic and produces either an error or an infinity. '
   || 'Using 1440 minutes (daily) instead. Set a positive number of minutes to '
   || 'choose your own.');
  ELSE
    deleg_cadence_min := :deleg_cadence_raw;
  END IF;

  -- probes.sql already resolved this to BLANK / NOT FOUND / FOUND / NO ACCESS.
  -- Read from :sig, never :cnt -- probes writes orch_named to the sig side ONLY
  -- (probes.sql:92, :99, :120, :124) and orch_reach to the cnt side ONLY
  -- (:93, :100, :121). Reading the wrong side returns NULL and every branch
  -- below falls through.
  LET deleg_orch_state STRING := UPPER(COALESCE(:sig:orch_named::STRING, 'BLANK'));
  LET deleg_reach_n INT := COALESCE(:cnt:orch_reach::INT, 0);

  -- Anti-patterns are countable at plan time: probes already read them. The
  -- three counts are different failure modes and are summed only for the
  -- headline; the view below keeps them apart.
  LET deleg_task_ap_n  INT := COALESCE(:cnt:deleg_tasks::INT, 0);
  LET deleg_asuser_n   INT := COALESCE(:cnt:as_user_tasks::INT, 0);
  LET deleg_proc_ap_n  INT := COALESCE(:cnt:proc_attempts::INT, 0);
  LET deleg_antipattern_n INT := :deleg_asuser_n + :deleg_proc_ap_n;

  -- The refusal reason, carried once and reused by the headline, the notes and
  -- V_DELEG_FINDINGS so all three agree.
  LET deleg_refusal STRING := '';

  IF (:deleg_orch_state = 'BLANK') THEN
    deleg_refusal := 'no orchestrator role was named, so this run is reporting only';
    notes := ARRAY_APPEND(:notes,
      'REPORTING ONLY: no orchestrator role was named, so no remediation was '
   || 'computed. DELEG_ORCHESTRATOR_ROLE is blank and a remediation for a role '
   || 'nobody named is a guess. Everything below is inventory -- the dbt '
   || 'projects, the tasks and procedures that already delegate, and the '
   || 'anti-patterns among them. Set DELEG_ORCHESTRATOR_ROLE to the service '
   || 'role your Airflow, Astro, Dagster or Control-M installation '
   || 'authenticates as, and re-run, and the excess-privilege list fills in. '
   || 'The excess count is reported as 0 because none was derived, not because '
   || 'the role is clean.');
  ELSEIF (:deleg_orch_state = 'NOT FOUND') THEN
    deleg_refusal := 'the configured orchestrator role ' || :deleg_orch_role
                  || ' was not found in this account';
    notes := ARRAY_APPEND(:notes,
      'REFUSED: role ' || :deleg_orch_role || ' is not found in this account. '
   || 'ACCOUNT_USAGE.ROLES has no undeleted row with that name, so there is no '
   || 'role graph to walk and no reach to subtract from. This is reported '
   || 'rather than answered with zero excess privileges, which would read as a '
   || 'clean PASS for a role that does not exist. Check DELEG_ORCHESTRATOR_ROLE '
   || 'for a typo, or for a role that was dropped after the pipeline was built.');
  ELSEIF (:deleg_orch_state = 'NO ACCESS') THEN
    deleg_refusal := 'this role cannot read the account role graph, so the '
                  || 'orchestrator reach could not be derived';
    notes := ARRAY_APPEND(:notes,
      'MISSING PRIVILEGE, not a clean result: the role graph walk failed. It '
   || 'needs SELECT on SNOWFLAKE.ACCOUNT_USAGE.ROLES and '
   || 'SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES, which is normally reached by '
   || 'granting the database role SNOWFLAKE.OBJECT_VIEWER, or by using a role '
   || 'that already has IMPORTED PRIVILEGES on the SNOWFLAKE database. Until '
   || 'then the reach number is unknown and the excess list is empty because '
   || 'nothing could be read -- reported as a finding rather than faked.');
  END IF;

  -- ── 2b. What the work actually requires: parse each dbt project ───────────
  -- Which projects are in scope. Blank means every project this role can see.
  -- SHOW rather than ACCOUNT_USAGE for the same reason probes.sql gives: a
  -- project deployed this morning is exactly the one somebody is asking about,
  -- and ACCOUNT_USAGE lags up to two hours behind it.
  LET deleg_all_proj ARRAY := ARRAY_CONSTRUCT();
  LET deleg_owner_guess STRING := '';
  BEGIN
    EXECUTE IMMEDIATE 'SHOW DBT PROJECTS IN ACCOUNT';
    deleg_all_proj := (
      SELECT COALESCE(ARRAY_AGG(UPPER("database_name") || '.' || UPPER("schema_name")
                                || '.' || UPPER("name")), ARRAY_CONSTRUCT())
      FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    -- Adoption: the role that already owns the project objects is the honest
    -- proposal for the execution role, because it is the role whose rights the
    -- dbt run has been executing with all along.
    deleg_owner_guess := (
      SELECT COALESCE(UPPER(MAX("owner")), '')
      FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
  EXCEPTION WHEN OTHER THEN
    deleg_all_proj := ARRAY_CONSTRUCT();
    deleg_owner_guess := '';
    notes := ARRAY_APPEND(:notes,
      'SHOW DBT PROJECTS IN ACCOUNT could not be read, so no dbt project object '
   || 'is in scope and no required-privilege set was derived. The task and '
   || 'procedure anti-patterns below do not depend on it and are still reported.');
  END;

  IF (:deleg_exec_role = '') THEN
    deleg_exec_role := :deleg_owner_guess;
    IF (:deleg_exec_role <> '') THEN
      notes := ARRAY_APPEND(:notes,
        'ADOPTED execution role ' || :deleg_exec_role || ': DELEG_EXEC_ROLE is '
     || 'blank, and that is the role which already owns the dbt project objects '
     || 'in this account. Owning the delegation task means the run executes '
     || 'with that role''''s rights, so adopting it changes nothing about what '
     || 'the pipeline can reach -- it only changes who is allowed to start it. '
     || 'Name a different role in DELEG_EXEC_ROLE if that is not the one you '
     || 'want supplying the rights.');
    END IF;
  END IF;

  -- The requested set, resolved against what exists. A name in the setting that
  -- matches no project object is the third refusal path.
  LET deleg_scope ARRAY := ARRAY_CONSTRUCT();
  IF (:deleg_proj_setting = '') THEN
    deleg_scope := :deleg_all_proj;
  ELSE
    LET rq ARRAY := (SELECT ARRAY_AGG(UPPER(TRIM(VALUE::STRING)))
                     FROM TABLE(FLATTEN(input => SPLIT(:deleg_proj_setting, ',')))
                     WHERE TRIM(VALUE::STRING) <> '');
    LET ri INT := 0;
    WHILE (:ri < COALESCE(ARRAY_SIZE(:rq), 0)) DO
      LET rname STRING := GET(:rq, :ri)::STRING;
      IF (ARRAY_CONTAINS(:rname::VARIANT, :deleg_all_proj)) THEN
        deleg_scope := ARRAY_APPEND(:deleg_scope, :rname);
      ELSE
        notes := ARRAY_APPEND(:notes,
          'Project ' || :rname || ' could not be resolved: it is not among the '
       || 'dbt project objects this role can see, so its declared sources and '
       || 'target could not be read and no required-privilege set was derived '
       || 'for it. Nothing was guessed in its place. The task and procedure '
       || 'anti-patterns below are independent of the project parse and are '
       || 'still reported. Check the name is fully qualified as '
       || 'DATABASE.SCHEMA.PROJECT and that this role has USAGE on both.');
      END IF;
      ri := :ri + 1;
    END WHILE;
  END IF;
  LET deleg_proj_n INT := COALESCE(ARRAY_SIZE(:deleg_scope), 0);

  IF (:deleg_proj_n = 0 AND :deleg_proj_setting = '') THEN
    notes := ARRAY_APPEND(:notes,
      'No dbt project object is visible to this role, so the required-privilege '
   || 'set has no declared sources or target to be derived from and none is '
   || 'claimed. This is the honest answer for an account that orchestrates '
   || 'notebooks or procedures rather than dbt: the anti-pattern inventory and '
   || 'the orchestrator reach below are still computed, and the delegation '
   || 'boundary still applies -- there is simply nothing to subtract yet.');
  END IF;

  -- Where the project files get staged so their text can be read. A dbt project
  -- URI cannot be selected directly: a SELECT on the snow-slash-slash-dbt form
  -- fails with "Domain DBT_PROJECT is not supported by SnowURL". The working
  -- sequence is COPY FILES INTO a stage of our own, then SELECT from the stage
  -- with a file format that reads the whole file as one raw field.
  --
  -- Both live in this build''s own schema, so DROP SCHEMA CASCADE at teardown
  -- reclaims them and neither needs a registry row.
  --
  -- FIELD_DELIMITER and RECORD_DELIMITER are both NONE on purpose: a dbt model
  -- is SQL and a profile is YAML, and both contain commas and newlines that a
  -- normal CSV format would split on. NONE for both makes the entire file
  -- arrive as a single value, which is what the pattern match below needs.
  LET deleg_fmt   STRING := :tgt || '.DELEG_RAW_TEXT';
  LET deleg_stage STRING := :tgt || '.DELEG_DBT_FILES';

  stmts := ARRAY_APPEND(:stmts,
    'CREATE FILE FORMAT IF NOT EXISTS ' || :deleg_fmt || ' TYPE = CSV '
 || 'FIELD_DELIMITER = NONE RECORD_DELIMITER = NONE '
 || 'FIELD_OPTIONALLY_ENCLOSED_BY = NONE ESCAPE_UNENCLOSED_FIELD = NONE '
 || 'COMPRESSION = NONE '
 || 'COMMENT = ' || CHAR(39) || 'Reads a whole dbt project file as one raw '
 || 'value. Delimiters are NONE because model SQL and profile YAML both '
 || 'contain commas and newlines.' || CHAR(39));

  stmts := ARRAY_APPEND(:stmts,
    'CREATE STAGE IF NOT EXISTS ' || :deleg_stage
 || ' FILE_FORMAT = ' || :deleg_fmt
 || ' COMMENT = ' || CHAR(39) || 'Staging copy of each dbt project in scope. '
 || 'Read once to derive the privileges the work requires; never written back.'
 || CHAR(39));

  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE TABLE ' || :tgt || '.DELEG_PROJECT_FILES ('
 || 'PROJECT_FQN VARCHAR, FILE_PATH VARCHAR, FILE_TEXT VARCHAR, '
 || 'READ_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()) '
 || 'COMMENT = ' || CHAR(39) || 'Raw text of every file in each dbt project in '
 || 'scope. The required-privilege set is derived from this and from nothing '
 || 'else, so the derivation is auditable against the project itself.'
 || CHAR(39));

  -- One COPY and one INSERT per project, each on its own so a project this role
  -- cannot read costs one project rather than the whole parse. RUN_ACTION and
  -- the build loop stop at the first failure, so a project that raises here
  -- would take the build with it -- which is why the resolvability check above
  -- happens at plan time against SHOW output rather than being discovered by a
  -- COPY that fails.
  LET pi INT := 0;
  LET deleg_parsed_n INT := 0;
  WHILE (:pi < :deleg_proj_n) DO
    LET pfqn STRING := GET(:deleg_scope, :pi)::STRING;
    -- A stage sub-path per project, derived from the name rather than the index,
    -- so re-running with a different project list does not shuffle which folder
    -- holds which project.
    LET pkey STRING := REPLACE(:pfqn, '.', '__');
    stmts := ARRAY_APPEND(:stmts,
      'COPY FILES INTO @' || :deleg_stage || '/' || :pkey || '/ '
   || 'FROM ' || CHAR(39) || 'snow://dbt/' || :pfqn || '/versions/live/' || CHAR(39));
    stmts := ARRAY_APPEND(:stmts,
      'INSERT INTO ' || :tgt || '.DELEG_PROJECT_FILES '
   || '(PROJECT_FQN, FILE_PATH, FILE_TEXT) '
   || 'SELECT ' || CHAR(39) || :pfqn || CHAR(39) || ', METADATA$FILENAME, $1 '
   || 'FROM @' || :deleg_stage || '/' || :pkey || '/ '
   || '(FILE_FORMAT => ' || CHAR(39) || :deleg_fmt || CHAR(39) || ')');
    deleg_parsed_n := :deleg_parsed_n + 1;
    pi := :pi + 1;
  END WHILE;

  -- ── The required-privilege set ────────────────────────────────────────────
  -- Two kinds of row, because a dbt project needs two different things.
  --
  --   SOURCE  a relation the project reads. Named fully qualified in model SQL,
  --           which is the only form that can be matched from text without
  --           compiling the project. A ref() to another model in the same
  --           project resolves at dbt compile time to a relation inside the
  --           TARGET namespace, so it is covered by the target row rather than
  --           missed -- but a source() macro pointing outside the target is NOT
  --           found by this parse, and the view says so rather than implying
  --           the list is complete.
  --   TARGET  the database and schema the project materialises into, read from
  --           the project''s own profile. The execution role needs CREATE on it.
  --           The orchestrator needs nothing on it, which is the whole point.
  --
  -- The pattern uses POSIX classes and bracketed literals throughout and no
  -- backslash escapes, because a backslash inside a Snowflake string literal is
  -- itself an escape and the pattern that arrives at the regex engine is not
  -- the one that was written.
  LET rx_rel STRING := '[A-Za-z_][A-Za-z0-9_$]*[.][A-Za-z_][A-Za-z0-9_$]*[.][A-Za-z_][A-Za-z0-9_$]*';

  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE VIEW ' || :tgt || '.V_DELEG_REQUIRED_PRIVILEGES '
 || 'COMMENT = ' || CHAR(39) || 'Privileges the dbt work genuinely requires, '
 || 'derived from each project' || CHAR(39) || CHAR(39) || 's own files. '
 || 'Fully-qualified relations in model SQL become SOURCE rows; the profile'
 || CHAR(39) || CHAR(39) || 's database and schema become a TARGET row. This is '
 || 'a text derivation over declared project content, not a compile: a '
 || 'source macro naming a relation outside the target namespace is not found '
 || 'by it.' || CHAR(39) || ' AS '
 || 'WITH src AS ('
 || '  SELECT f.PROJECT_FQN, f.FILE_PATH, '
 || '    UPPER(s.VALUE::VARCHAR) AS RELATION_FQN '
 || '  FROM ' || :tgt || '.DELEG_PROJECT_FILES f, '
 || '    LATERAL FLATTEN(input => REGEXP_SUBSTR_ALL(f.FILE_TEXT, '
 || CHAR(39) || '(from|join)[[:space:]]+(' || :rx_rel || ')' || CHAR(39)
 || ', 1, 1, ' || CHAR(39) || 'is' || CHAR(39) || ', 2)) s '
 || '  WHERE f.FILE_TEXT IS NOT NULL'
 || '), tgt AS ('
 || '  SELECT PROJECT_FQN, FILE_PATH, '
 || '    UPPER(REGEXP_SUBSTR(FILE_TEXT, ' || CHAR(39)
 || 'database:[[:space:]]*[^[:space:]]+' || CHAR(39) || ')) AS D_RAW, '
 || '    UPPER(REGEXP_SUBSTR(FILE_TEXT, ' || CHAR(39)
 || 'schema:[[:space:]]*[^[:space:]]+' || CHAR(39) || ')) AS S_RAW '
 || '  FROM ' || :tgt || '.DELEG_PROJECT_FILES '
 || '  WHERE FILE_PATH ILIKE ' || CHAR(39) || '%profiles.yml' || CHAR(39)
 || ') '
 || 'SELECT PROJECT_FQN, ' || CHAR(39) || 'SOURCE' || CHAR(39) || ' AS ROLE_NEED, '
 || 'RELATION_FQN AS OBJECT_FQN, ' || CHAR(39) || 'SELECT' || CHAR(39) || ' AS PRIVILEGE, '
 || CHAR(39) || 'read by ' || CHAR(39) || ' || FILE_PATH AS DERIVED_FROM '
 || 'FROM src '
 || 'WHERE SPLIT_PART(RELATION_FQN, ' || CHAR(39) || '.' || CHAR(39)
 || ', 1) NOT IN (' || CHAR(39) || 'SNOWFLAKE' || CHAR(39) || ', '
 || CHAR(39) || 'INFORMATION_SCHEMA' || CHAR(39) || ') '
 || 'UNION '
 || 'SELECT PROJECT_FQN, ' || CHAR(39) || 'TARGET' || CHAR(39) || ', '
 || 'TRIM(SPLIT_PART(D_RAW, ' || CHAR(39) || ':' || CHAR(39) || ', 2)) || '
 || CHAR(39) || '.' || CHAR(39) || ' || TRIM(SPLIT_PART(S_RAW, ' || CHAR(39)
 || ':' || CHAR(39) || ', 2)), '
 || CHAR(39) || 'CREATE TABLE, CREATE VIEW' || CHAR(39) || ', '
 || CHAR(39) || 'materialisation target declared in ' || CHAR(39) || ' || FILE_PATH '
 || 'FROM tgt '
 || 'WHERE D_RAW IS NOT NULL AND S_RAW IS NOT NULL');

  -- ── 2c. V_DELEG_ANTIPATTERNS ──────────────────────────────────────────────
  -- Three distinct ways the owner''s-rights boundary is already broken. Same
  -- ACCOUNT_USAGE sources and predicates probes.sql:22-66 validated, promoted
  -- from counts to rows because the count alone tells you there is a problem
  -- and not which object has it.
  --
  -- The first is the trap this solution exists to catch: a task that runs a dbt
  -- project or a notebook AND is owned by the orchestrator role. The DDL is
  -- identical to the compliant version. The only difference is who ran it, and
  -- that is invisible from the outside.
  --
  -- Detection is a text match over definitions, so it inherits ACCOUNT_USAGE''s
  -- lag of up to two hours and will also match a commented-out reference. It
  -- finds what it finds; it is not a completeness claim.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE VIEW ' || :tgt || '.V_DELEG_ANTIPATTERNS '
 || 'COMMENT = ' || CHAR(39) || 'Owner' || CHAR(39) || CHAR(39) || 's-rights '
 || 'boundary violations visible in ACCOUNT_USAGE. Text match over definitions, '
 || 'so it lags up to two hours and matches commented-out references too. Not a '
 || 'completeness claim.' || CHAR(39) || ' AS '
 || 'SELECT ' || CHAR(39) || 'TASK_OWNED_BY_ORCHESTRATOR' || CHAR(39) || ' AS FINDING, '
 || 'TASK_DATABASE || ' || CHAR(39) || '.' || CHAR(39) || ' || TASK_SCHEMA || '
 || CHAR(39) || '.' || CHAR(39) || ' || TASK_NAME AS OBJECT_FQN, '
 || 'TASK_OWNER AS OWNED_BY, '
 || CHAR(39) || 'This task executes a dbt project or a notebook and is owned by '
 || 'the orchestrator role, so the run carries the orchestrator'
 || CHAR(39) || CHAR(39) || 's rights and the delegation boundary does not '
 || 'exist. Recreate it as the execution role.' || CHAR(39) || ' AS WHY, '
 || CHAR(39) || 'HIGH' || CHAR(39) || ' AS SEVERITY '
 || 'FROM SNOWFLAKE.ACCOUNT_USAGE.TASKS '
 || 'WHERE DELETED IS NULL '
 || '  AND (DEFINITION ILIKE ' || CHAR(39) || '%EXECUTE DBT PROJECT%' || CHAR(39)
 || '   OR DEFINITION ILIKE ' || CHAR(39) || '%EXECUTE NOTEBOOK%' || CHAR(39) || ') '
 || '  AND ' || CHAR(39) || :deleg_orch_role || CHAR(39) || ' <> ' || CHAR(39) || CHAR(39)
 || '  AND UPPER(TASK_OWNER) = ' || CHAR(39) || :deleg_orch_role || CHAR(39) || ' '
 || 'UNION ALL '
 || 'SELECT ' || CHAR(39) || 'TASK_RUNS_AS_USER' || CHAR(39) || ', '
 || 'TASK_DATABASE || ' || CHAR(39) || '.' || CHAR(39) || ' || TASK_SCHEMA || '
 || CHAR(39) || '.' || CHAR(39) || ' || TASK_NAME, TASK_OWNER, '
 || CHAR(39) || 'This task is configured EXECUTE AS USER, which does not error '
 || 'at creation and fails when it runs -- which is how it survives review. An '
 || 'owner' || CHAR(39) || CHAR(39) || 's-rights task leaves EXECUTE_AS_USER_ID '
 || 'NULL.' || CHAR(39) || ', '
 || CHAR(39) || 'HIGH' || CHAR(39) || ' '
 || 'FROM SNOWFLAKE.ACCOUNT_USAGE.TASKS '
 || 'WHERE DELETED IS NULL '
 || '  AND (DEFINITION ILIKE ' || CHAR(39) || '%EXECUTE DBT PROJECT%' || CHAR(39)
 || '   OR DEFINITION ILIKE ' || CHAR(39) || '%EXECUTE NOTEBOOK%' || CHAR(39) || ') '
 || '  AND EXECUTE_AS_USER_ID IS NOT NULL '
 || 'UNION ALL '
 || 'SELECT ' || CHAR(39) || 'PROCEDURE_WRAPPER_ATTEMPT' || CHAR(39) || ', '
 || 'PROCEDURE_CATALOG || ' || CHAR(39) || '.' || CHAR(39) || ' || PROCEDURE_SCHEMA || '
 || CHAR(39) || '.' || CHAR(39) || ' || PROCEDURE_NAME, PROCEDURE_OWNER, '
 || CHAR(39) || 'This procedure attempts EXECUTE DBT PROJECT or EXECUTE '
 || 'NOTEBOOK. Both enforce caller' || CHAR(39) || CHAR(39) || 's rights and a '
 || 'procedure cannot launder that into owner' || CHAR(39) || CHAR(39) || 's '
 || 'rights, so this is the workaround that cannot work. Finding one means a '
 || 'team has already hit the wall and built around it.' || CHAR(39) || ', '
 || CHAR(39) || 'MEDIUM' || CHAR(39) || ' '
 || 'FROM SNOWFLAKE.ACCOUNT_USAGE.PROCEDURES '
 || 'WHERE DELETED IS NULL '
 || '  AND (PROCEDURE_DEFINITION ILIKE ' || CHAR(39) || '%EXECUTE DBT PROJECT%' || CHAR(39)
 || '   OR PROCEDURE_DEFINITION ILIKE ' || CHAR(39) || '%EXECUTE NOTEBOOK%' || CHAR(39) || ')');

  -- ── V_DELEG_ORCHESTRATOR_REACH ────────────────────────────────────────────
  -- The recursive role-graph walk probes.sql:104-119 reduced to a scalar,
  -- promoted here to the ROWS -- because the remediation subtracts them and a
  -- count cannot be subtracted from a set.
  --
  -- Inheritance is how these roles quietly become wide: the direct grants on a
  -- service role are usually defensible and the inherited ones are what nobody
  -- recomputed after a 2am fix.
  --
  -- The role-name literal guards the recursion. With no role named, the anchor
  -- is the empty string, nothing joins to it, and the view returns zero rows
  -- and still reads cleanly -- which is what makes the blank default do nothing
  -- rather than fail.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE VIEW ' || :tgt || '.V_DELEG_ORCHESTRATOR_REACH '
 || 'COMMENT = ' || CHAR(39) || 'Every relation the orchestrator role can read '
 || 'or write, through the whole role graph rather than its direct grants only. '
 || 'Zero rows when no orchestrator role is named.' || CHAR(39) || ' AS '
 || 'WITH RECURSIVE r AS ('
 || '  SELECT ' || CHAR(39) || :deleg_orch_role || CHAR(39) || ' AS RN, 0 AS HOPS'
 || '  UNION ALL'
 || '  SELECT UPPER(g.NAME), r.HOPS + 1'
 || '  FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES g'
 || '  JOIN r ON UPPER(g.GRANTEE_NAME) = r.RN'
 || '  WHERE g.GRANTED_ON = ' || CHAR(39) || 'ROLE' || CHAR(39)
 || '    AND g.GRANTED_TO = ' || CHAR(39) || 'ROLE' || CHAR(39)
 || '    AND g.PRIVILEGE = ' || CHAR(39) || 'USAGE' || CHAR(39)
 || '    AND g.DELETED_ON IS NULL'
 || ') '
 || 'SELECT g.TABLE_CATALOG || ' || CHAR(39) || '.' || CHAR(39)
 || ' || g.TABLE_SCHEMA || ' || CHAR(39) || '.' || CHAR(39)
 || ' || g.NAME AS RELATION_FQN, '
 || 'g.GRANTED_ON AS OBJECT_TYPE, '
 || 'g.PRIVILEGE AS PRIVILEGE, '
 || 'g.GRANTEE_NAME AS GRANTED_TO_ROLE, '
 || 'MIN(r.HOPS) OVER (PARTITION BY g.GRANTEE_NAME) AS HOPS_FROM_ORCHESTRATOR, '
 || 'CASE WHEN UPPER(g.GRANTEE_NAME) = ' || CHAR(39) || :deleg_orch_role || CHAR(39)
 || '  THEN ' || CHAR(39) || 'DIRECT' || CHAR(39)
 || '  ELSE ' || CHAR(39) || 'INHERITED via ' || CHAR(39) || ' || g.GRANTEE_NAME '
 || 'END AS HOW '
 || 'FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES g '
 || 'JOIN r ON UPPER(g.GRANTEE_NAME) = r.RN '
 || 'WHERE g.DELETED_ON IS NULL '
 || '  AND ' || CHAR(39) || :deleg_orch_role || CHAR(39) || ' <> ' || CHAR(39) || CHAR(39)
 || '  AND g.GRANTED_ON IN (' || CHAR(39) || 'TABLE' || CHAR(39) || ', '
 || CHAR(39) || 'VIEW' || CHAR(39) || ', ' || CHAR(39) || 'MATERIALIZED_VIEW' || CHAR(39)
 || ', ' || CHAR(39) || 'DYNAMIC_TABLE' || CHAR(39) || ') '
 || '  AND g.PRIVILEGE IN (' || CHAR(39) || 'SELECT' || CHAR(39) || ', '
 || CHAR(39) || 'INSERT' || CHAR(39) || ', ' || CHAR(39) || 'UPDATE' || CHAR(39)
 || ', ' || CHAR(39) || 'DELETE' || CHAR(39) || ', ' || CHAR(39) || 'TRUNCATE' || CHAR(39)
 || ', ' || CHAR(39) || 'OWNERSHIP' || CHAR(39) || ')');

  -- ── V_DELEG_REMEDIATION ───────────────────────────────────────────────────
  -- Reach minus required, one row per excess grant, carrying the exact REVOKE
  -- text. This is the deliverable. A remediation that cannot show the excess it
  -- removes is a claim, and a security architect does not sign claims.
  --
  -- It carries THREE things, not one, because grants without the orchestrator
  -- side of the contract is half a deliverable:
  --   REVOKE_SQL     what to take away.
  --   TRIGGER_SQL    how the orchestrator starts the run once the grant is gone
  --                  -- EXECUTE TASK on the graph ROOT, with USING CONFIG
  --                  carrying the orchestrator''s own run id so no control table
  --                  and no mapping layer is needed to correlate.
  --   POLL_SQL       how it watches. INFORMATION_SCHEMA.TASK_HISTORY, filtered
  --                  on GRAPH_RUN_GROUP_ID, which is ONE poll for the whole
  --                  graph rather than one per task.
  --
  -- ACCOUNT_USAGE.TASK_HISTORY carries the same columns and is NOT used here.
  -- It lags, and a customer polling it against a five-minute end-to-end target
  -- would miss the target on the lag alone. The table function is
  -- near-real-time. That substitution is the single most expensive mistake
  -- available in this pattern, so the generated SQL never offers it.
  LET deleg_graph_root STRING := :tgt || '.TASK_DELEG_RUN_ROOT';
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE VIEW ' || :tgt || '.V_DELEG_REMEDIATION '
 || 'COMMENT = ' || CHAR(39) || 'Excess privileges on the orchestrator role, '
 || 'with the REVOKE that removes each one and the trigger and poll SQL that '
 || 'replaces it. Zero rows is a PASS, not an empty view.' || CHAR(39) || ' AS '
 || 'WITH reach AS ('
 || '  SELECT RELATION_FQN, OBJECT_TYPE, PRIVILEGE, GRANTED_TO_ROLE, HOW'
 || '  FROM ' || :tgt || '.V_DELEG_ORCHESTRATOR_REACH'
 || '), req AS ('
 || '  SELECT OBJECT_FQN, ROLE_NEED FROM ' || :tgt || '.V_DELEG_REQUIRED_PRIVILEGES'
 || ') '
 || 'SELECT r.RELATION_FQN, r.OBJECT_TYPE, r.PRIVILEGE, r.GRANTED_TO_ROLE, r.HOW, '
 || CHAR(39) || 'REVOKE ' || CHAR(39) || ' || r.PRIVILEGE || ' || CHAR(39)
 || ' ON ' || CHAR(39) || ' || REPLACE(r.OBJECT_TYPE, ' || CHAR(39) || '_' || CHAR(39)
 || ', ' || CHAR(39) || ' ' || CHAR(39) || ') || ' || CHAR(39) || ' ' || CHAR(39)
 || ' || r.RELATION_FQN || ' || CHAR(39) || ' FROM ROLE ' || CHAR(39)
 || ' || r.GRANTED_TO_ROLE || ' || CHAR(39) || ';' || CHAR(39) || ' AS REVOKE_SQL, '
 -- The trigger call. CHR(39) rather than a doubled literal inside the view text
 -- so the JSON in USING CONFIG survives being nested three quote levels deep.
 || CHAR(39) || 'EXECUTE TASK ' || :deleg_graph_root
 || ' USING CONFIG = ' || CHAR(39) || ' || CHR(39) || '
 || CHAR(39) || '{"orchestrator_run_id":"<your run id>"}' || CHAR(39)
 || ' || CHR(39) || ' || CHAR(39) || ';' || CHAR(39) || ' AS TRIGGER_SQL, '
 || CHAR(39) || 'SELECT STATE, RETURN_VALUE, ERROR_CODE, ERROR_MESSAGE, '
 || 'SCHEDULED_TIME, COMPLETED_TIME FROM TABLE(' || :db
 || '.INFORMATION_SCHEMA.TASK_HISTORY()) WHERE GRAPH_RUN_GROUP_ID = '
 || CHAR(39) || ' || CHR(39) || ' || CHAR(39) || '<group id from the trigger>'
 || CHAR(39) || ' || CHR(39) || ' || CHAR(39) || ' ORDER BY SCHEDULED_TIME;'
 || CHAR(39) || ' AS POLL_SQL, '
 || CHAR(39) || 'Reachable through the role graph and not required by any dbt '
 || 'project in scope. The orchestrator needs OPERATE on the graph root and '
 || 'nothing on the data.' || CHAR(39) || ' AS WHY '
 || 'FROM reach r '
 || 'WHERE NOT EXISTS ('
 || '  SELECT 1 FROM req q'
 || '  WHERE q.OBJECT_FQN = r.RELATION_FQN'
 || '     OR (q.ROLE_NEED = ' || CHAR(39) || 'TARGET' || CHAR(39)
 || '         AND r.RELATION_FQN LIKE q.OBJECT_FQN || ' || CHAR(39) || '.%' || CHAR(39) || '))');

  -- ── 2d. The delegation graph — the object the OPERATE grant targets ───────
  -- A TASK GRAPH, not one task per dbt command. This is a latency decision and
  -- it is the reason this shape exists.
  --
  -- One orchestrator poll per Snowflake task is what makes this pattern fail
  -- its SLA: at a 45-second poll interval a four-step pipeline spends three
  -- minutes waiting for polls that Snowflake did not need. Chaining the steps
  -- with AFTER means Snowflake schedules each child the moment its parent
  -- succeeds, with no polling between hops. The orchestrator triggers the root
  -- once and polls once on GRAPH_RUN_GROUP_ID. N polls collapse to 1 and the
  -- interval becomes the customer''s dial rather than ours.
  --
  -- A single-command project is the degenerate case of the same emitter, not a
  -- different code path.
  --
  -- The root carries NO SCHEDULE. It is triggered on demand with EXECUTE TASK,
  -- which is the entire point -- so the graph has no cadence of its own and
  -- costs nothing until the orchestrator starts a run.
  LET deleg_task_fqn STRING := :tgt || '.TASK_PRIVILEGE_DRIFT_MONITOR';
  LET standing_live_deleg BOOLEAN := (:tier = 'PRODUCTION');
  LET deleg_graph_built BOOLEAN := FALSE;
  LET deleg_graph_steps INT := 0;
  LET deleg_graph_proj STRING := '';

  IF (:deleg_proj_n > 0) THEN
    deleg_graph_proj := GET(:deleg_scope, 0)::STRING;
    deleg_graph_built := TRUE;

    -- Root: dbt run. Body is EXECUTE DBT PROJECT and nothing else, which is
    -- also the honest limitation -- a task whose body is only EXECUTE DBT
    -- PROJECT cannot ALSO call SYSTEM$SET_RETURN_VALUE, so a dbt-level success
    -- payload needs the finalizer below. That cost is real and is stated rather
    -- than implied away.
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE TASK ' || :deleg_graph_root
   || ' WAREHOUSE = ' || :wh
   || ' COMMENT = ' || CHAR(39) || 'Delegation graph ROOT. Triggered on demand '
   || 'with EXECUTE TASK USING CONFIG; no schedule, so it costs nothing until '
   || 'the orchestrator starts a run. Owned by the execution role, which is '
   || 'what supplies the rights the dbt run executes with.' || CHAR(39)
   || ' AS EXECUTE DBT PROJECT ' || :deleg_graph_proj
   || ' args=' || CHAR(39) || 'run' || CHAR(39));
    deleg_graph_steps := 1;

    -- Child: dbt test, AFTER the run. The AFTER is the latency fix -- no poll
    -- happens between these two.
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE TASK ' || :tgt || '.TASK_DELEG_RUN_TEST'
   || ' WAREHOUSE = ' || :wh
   || ' AFTER ' || :deleg_graph_root
   || ' COMMENT = ' || CHAR(39) || 'Second dbt command in the same graph run. '
   || 'Scheduled by Snowflake the moment the root succeeds, so the orchestrator '
   || 'does not poll between the two.' || CHAR(39)
   || ' AS EXECUTE DBT PROJECT ' || :deleg_graph_proj
   || ' args=' || CHAR(39) || 'test' || CHAR(39));
    deleg_graph_steps := 2;

    -- Finalizer. This exists ONLY because the two tasks above cannot set a
    -- return value: their bodies are single EXECUTE DBT PROJECT statements.
    -- The orchestrator reads RETURN_VALUE for the graph out of TASK_HISTORY.
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE TASK ' || :tgt || '.TASK_DELEG_RUN_FINALIZE'
   || ' WAREHOUSE = ' || :wh
   || ' AFTER ' || :tgt || '.TASK_DELEG_RUN_TEST'
   || ' COMMENT = ' || CHAR(39) || 'Sets the graph return value. Needed because '
   || 'a task whose body is only EXECUTE DBT PROJECT cannot also call '
   || 'SYSTEM$SET_RETURN_VALUE. The orchestrator reads RETURN_VALUE from '
   || 'INFORMATION_SCHEMA.TASK_HISTORY for its own GRAPH_RUN_GROUP_ID.'
   || CHAR(39)
   || ' AS CALL SYSTEM$SET_RETURN_VALUE(' || CHAR(39) || 'DBT_GRAPH_COMPLETE'
   || CHAR(39) || ')');
    deleg_graph_steps := 3;

    -- Children first, root last. A graph root validates the whole DAG when it
    -- resumes, so resuming the root before its children is how you get a graph
    -- that starts and then has nothing downstream of it.
    stmts := ARRAY_APPEND(:stmts,
      'ALTER TASK ' || :tgt || '.TASK_DELEG_RUN_TEST RESUME');
    stmts := ARRAY_APPEND(:stmts,
      'ALTER TASK ' || :tgt || '.TASK_DELEG_RUN_FINALIZE RESUME');

    -- Below PRODUCTION the children are suspended too, so the graph cannot
    -- propagate even if somebody triggers the root by hand. Same gate 02 and 13
    -- apply to their standing objects, for the same reason: a tier below
    -- PRODUCTION must leave nothing on the account that can run.
    IF (NOT :standing_live_deleg) THEN
      stmts := ARRAY_APPEND(:stmts,
        'ALTER TASK ' || :tgt || '.TASK_DELEG_RUN_FINALIZE SUSPEND');
      stmts := ARRAY_APPEND(:stmts,
        'ALTER TASK ' || :tgt || '.TASK_DELEG_RUN_TEST SUSPEND');
      notes := ARRAY_APPEND(:notes,
        'The delegation graph (TASK_DELEG_RUN_ROOT, then TASK_DELEG_RUN_TEST, '
     || 'then TASK_DELEG_RUN_FINALIZE) was created and then SUSPENDED, because '
     || 'this run is ' || :tier || ' tier. The root never carries a schedule in '
     || 'any tier -- it is triggered on demand -- so nothing recurs either way; '
     || 'suspending the children means a hand-triggered root cannot propagate. '
     || 'Re-run with DELEG_DEPLOY_TIER = PRODUCTION to leave the graph able to '
     || 'run.');
    ELSE
      notes := ARRAY_APPEND(:notes,
        'The delegation graph is LIVE and waiting to be triggered. It is three '
     || 'tasks chained with AFTER, not three independently polled tasks: your '
     || 'orchestrator issues one EXECUTE TASK on TASK_DELEG_RUN_ROOT with '
     || 'USING CONFIG carrying its own run id, then polls ONCE on '
     || 'GRAPH_RUN_GROUP_ID. Read V_DELEG_REMEDIATION for the exact trigger and '
     || 'poll statements. The root has no schedule, so it costs nothing until '
     || 'you trigger it.');
    END IF;
  ELSE
    notes := ARRAY_APPEND(:notes,
      'No delegation graph was created, because no dbt project object is in '
   || 'scope for it to run. There is nothing to grant OPERATE on and nothing to '
   || 'trigger, so proposing a grant would be proposing one against an object '
   || 'that does not exist. The anti-pattern inventory and the orchestrator '
   || 'reach are unaffected and are reported below.');
  END IF;

  -- ── HANDSHAKE mode ────────────────────────────────────────────────────────
  -- Retained, not cut. The objection that a stored procedure "returns success
  -- or failure directly" is an argument FOR a status table: it returns exactly
  -- that, and the request row carries the orchestrator''s own run id natively.
  --
  -- It triggers the graph ROOT and nothing else. A triggered task per dbt
  -- command would re-stack the very latency the graph shape removes, at a
  -- 30-second floor per hop.
  IF (:deleg_mode = 'HANDSHAKE' AND :deleg_graph_built) THEN
    stmts := ARRAY_APPEND(:stmts,
      'CREATE TABLE IF NOT EXISTS ' || :tgt || '.DELEG_RUN_REQUEST ('
   || 'ORCHESTRATOR_RUN_ID VARCHAR, REQUESTED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()) '
   || 'COMMENT = ' || CHAR(39) || 'The orchestrator inserts one row here and '
   || 'needs no task privilege at all. Its own run id is the correlation key.'
   || CHAR(39));
    stmts := ARRAY_APPEND(:stmts,
      'CREATE TABLE IF NOT EXISTS ' || :tgt || '.DELEG_RUN_STATUS ('
   || 'ORCHESTRATOR_RUN_ID VARCHAR, GRAPH_STATE VARCHAR, '
   || 'DISPATCHED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()) '
   || 'COMMENT = ' || CHAR(39) || 'What the orchestrator reads back. This is the '
   || 'success-or-failure a procedure would have returned, on a row it can '
   || 'find by its own run id.' || CHAR(39));
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE STREAM ' || :tgt || '.DELEG_REQUEST_STREAM ON TABLE '
   || :tgt || '.DELEG_RUN_REQUEST');
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE PROCEDURE ' || :tgt || '.DELEG_DISPATCH() '
   || 'RETURNS VARCHAR LANGUAGE SQL AS BEGIN '
   || 'INSERT INTO ' || :tgt || '.DELEG_RUN_STATUS (ORCHESTRATOR_RUN_ID, GRAPH_STATE) '
   || 'SELECT ORCHESTRATOR_RUN_ID, ' || CHAR(39) || 'DISPATCHED' || CHAR(39)
   || ' FROM ' || :tgt || '.DELEG_REQUEST_STREAM WHERE METADATA$ACTION = '
   || CHAR(39) || 'INSERT' || CHAR(39) || '; '
   || 'EXECUTE TASK ' || :deleg_graph_root || '; '
   || 'RETURN ' || CHAR(39) || 'DISPATCHED' || CHAR(39) || '; END');
    -- 30 SECOND is the floor settings_extra.sql promises, and the WHEN clause
    -- means a poll with no request row costs a metadata check rather than a run.
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE TASK ' || :tgt || '.TASK_DELEG_HANDSHAKE'
   || ' WAREHOUSE = ' || :wh
   || ' SCHEDULE = ' || CHAR(39) || '30 SECOND' || CHAR(39)
   || ' WHEN SYSTEM$STREAM_HAS_DATA(' || CHAR(39) || :tgt
   || '.DELEG_REQUEST_STREAM' || CHAR(39) || ')'
   || ' COMMENT = ' || CHAR(39) || 'Fires the delegation graph ROOT when a '
   || 'request row lands. Triggers the root only -- a triggered task per dbt '
   || 'command would re-stack the latency the graph shape removes.' || CHAR(39)
   || ' AS CALL ' || :tgt || '.DELEG_DISPATCH()');
    stmts := ARRAY_APPEND(:stmts,
      'ALTER TASK ' || :tgt || '.TASK_DELEG_HANDSHAKE RESUME');
    IF (NOT :standing_live_deleg) THEN
      stmts := ARRAY_APPEND(:stmts,
        'ALTER TASK ' || :tgt || '.TASK_DELEG_HANDSHAKE SUSPEND');
    END IF;
    notes := ARRAY_APPEND(:notes,
      'HANDSHAKE mode: the orchestrator inserts a row into DELEG_RUN_REQUEST '
   || 'carrying its own run id and reads DELEG_RUN_STATUS back. It needs no '
   || 'task privilege at all, which is tighter than OPERATE. The cost is a '
   || '30-second trigger floor -- TASK_DELEG_HANDSHAKE checks the stream on '
   || 'that interval, so a request waits up to 30 seconds before the graph '
   || 'starts. If your end-to-end target has no room for that, use OPERATE and '
   || 'grant OPERATE on the graph root only.');
    dials := ARRAY_APPEND(:dials,
      'DELEG_DELEGATION_MODE HANDSHAKE -> OPERATE removes TASK_DELEG_HANDSHAKE entirely, '
   || 'which removes both its 30-second trigger floor and its polling cost. '
   || 'HANDSHAKE buys a tighter privilege set with latency.');
  ELSEIF (:deleg_mode = 'HANDSHAKE' AND NOT :deleg_graph_built) THEN
    notes := ARRAY_APPEND(:notes,
      'DELEG_DELEGATION_MODE is HANDSHAKE but no delegation graph exists to hand off to, '
   || 'so the request table, stream and trigger task were not created. A '
   || 'handshake with nothing on the other side of it is plumbing, not a '
   || 'boundary.');
  END IF;

  -- ── The standing workload: TASK_PRIVILEGE_DRIFT_MONITOR ───────────────────
  -- Least privilege on a service role decays silently. Someone grants a role to
  -- fix a broken run at 2am and nobody recomputes the blast radius afterwards.
  -- Re-deriving it means walking the whole role graph against every project''s
  -- declared sources and target, which no team does by hand after go-live.

  -- Credits per hour read off the actual warehouse rather than assumed. The
  -- fallback states that 1 credit/hour is a LOWER bound, because an unreadable
  -- warehouse size that silently becomes 1 understates every figure below it.
  LET deleg_wh_size    STRING := 'UNKNOWN';
  LET deleg_wh_cph     NUMBER(38,2) := 1.0;
  LET deleg_wh_rate_ok BOOLEAN := FALSE;
  BEGIN
    EXECUTE IMMEDIATE 'SHOW WAREHOUSES LIKE ' || CHAR(39) || :wh || CHAR(39);
    deleg_wh_size := (SELECT UPPER(COALESCE(MAX("size"), 'UNKNOWN'))
                      FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    deleg_wh_cph := CASE :deleg_wh_size
        WHEN 'X-SMALL'  THEN 1   WHEN 'XSMALL'    THEN 1
        WHEN 'SMALL'    THEN 2
        WHEN 'MEDIUM'   THEN 4
        WHEN 'LARGE'    THEN 8
        WHEN 'X-LARGE'  THEN 16  WHEN 'XLARGE'    THEN 16
        WHEN '2X-LARGE' THEN 32  WHEN 'XXLARGE'   THEN 32
        WHEN '3X-LARGE' THEN 64  WHEN 'XXXLARGE'  THEN 64
        WHEN '4X-LARGE' THEN 128 WHEN 'XXXXLARGE' THEN 128
        ELSE 1 END;
    deleg_wh_rate_ok := (:deleg_wh_cph > 1 OR :deleg_wh_size IN ('X-SMALL', 'XSMALL'));
  EXCEPTION WHEN OTHER THEN
    deleg_wh_size := 'UNREADABLE'; deleg_wh_cph := 1.0; deleg_wh_rate_ok := FALSE;
  END;

  stmts := ARRAY_APPEND(:stmts,
    'CREATE TABLE IF NOT EXISTS ' || :tgt || '.DELEG_DRIFT_HISTORY ('
 || 'SNAPSHOT_AT TIMESTAMP_NTZ, ORCHESTRATOR_ROLE VARCHAR, '
 || 'REACH_RELATIONS INT, REQUIRED_RELATIONS INT, EXCESS_RELATIONS INT, '
 || 'ANTIPATTERNS INT) '
 || 'COMMENT = ' || CHAR(39) || 'One row per drift snapshot. The point is the '
 || 'series: a reach number that grows between snapshots is a grant nobody '
 || 'recomputed the blast radius for.' || CHAR(39));

  -- The task body is this exact call, so timing the call the build makes below
  -- is the honest measurement of the task and costs nothing extra.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE PROCEDURE ' || :tgt || '.DELEG_DRIFT_SNAPSHOT() '
 || 'RETURNS VARCHAR LANGUAGE SQL AS BEGIN '
 || 'INSERT INTO ' || :tgt || '.DELEG_DRIFT_HISTORY '
 || '(SNAPSHOT_AT, ORCHESTRATOR_ROLE, REACH_RELATIONS, REQUIRED_RELATIONS, '
 || 'EXCESS_RELATIONS, ANTIPATTERNS) SELECT CURRENT_TIMESTAMP(), '
 || CHAR(39) || :deleg_orch_role || CHAR(39) || ', '
 || '(SELECT COUNT(DISTINCT RELATION_FQN) FROM ' || :tgt || '.V_DELEG_ORCHESTRATOR_REACH), '
 || '(SELECT COUNT(DISTINCT OBJECT_FQN) FROM ' || :tgt || '.V_DELEG_REQUIRED_PRIVILEGES), '
 || '(SELECT COUNT(*) FROM ' || :tgt || '.V_DELEG_REMEDIATION), '
 || '(SELECT COUNT(*) FROM ' || :tgt || '.V_DELEG_ANTIPATTERNS); '
 || 'RETURN ' || CHAR(39) || 'DRIFT SNAPSHOT COMPLETE' || CHAR(39) || '; END');

  -- Called once here so the duration below is measured rather than asserted,
  -- and so RESUME is proven against a body that actually works.
  stmts := ARRAY_APPEND(:stmts, 'CALL ' || :tgt || '.DELEG_DRIFT_SNAPSHOT()');

  LET deleg_cadence_lbl STRING :=
    :deleg_cadence_min || ' minute schedule'
    || IFF(:standing_live_deleg, '', ', SUSPENDED at ' || :tier || ' tier');
  LET runs_per_month_deleg NUMBER(38,4) :=
    IFF(:standing_live_deleg, ROUND(30.4 * 1440.0 / :deleg_cadence_min, 4), 0);
  LET gate_basis_deleg STRING := IFF(:standing_live_deleg,
      'Left RUNNING because this build is PRODUCTION tier -- this is a charge '
        || 'you will see.',
      'SUSPENDED by this build because the tier is ' || :tier || ', not '
        || 'PRODUCTION, so runs/month is 0 and nothing recurs. At PRODUCTION the '
        || 'same task would fire '
        || ROUND(30.4 * 1440.0 / :deleg_cadence_min, 4) || ' times a month.');

  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE TASK ' || :deleg_task_fqn
 || ' WAREHOUSE = ' || :wh
 || ' SCHEDULE = ' || CHAR(39) || ROUND(:deleg_cadence_min)::INT::STRING || ' MINUTE' || CHAR(39)
 || ' COMMENT = ' || CHAR(39) || 'Re-derives the orchestrator'
 || CHAR(39) || CHAR(39) || 's privilege reach against every dbt project'
 || CHAR(39) || CHAR(39) || 's declared sources and target, so drift shows up '
 || 'as a row instead of as an incident.' || CHAR(39)
 || ' AS CALL ' || :tgt || '.DELEG_DRIFT_SNAPSHOT()');

  -- Snowflake creates tasks suspended, so a build that only CREATEs one has
  -- installed nothing. RESUME here proves the install; the gate below suspends
  -- it again when the tier is not PRODUCTION.
  stmts := ARRAY_APPEND(:stmts, 'ALTER TASK ' || :deleg_task_fqn || ' RESUME');
  IF (NOT :standing_live_deleg) THEN
    stmts := ARRAY_APPEND(:stmts, 'ALTER TASK ' || :deleg_task_fqn || ' SUSPEND');
    notes := ARRAY_APPEND(:notes,
      'TASK_PRIVILEGE_DRIFT_MONITOR was created, exercised once and then '
   || 'SUSPENDED, because this run is ' || :tier || ' tier. Nothing recurs and '
   || 'nothing bills. Re-run with DELEG_DEPLOY_TIER = PRODUCTION to re-derive '
   || 'the reach every ' || :deleg_cadence_min || ' minutes.');
  ELSE
    notes := ARRAY_APPEND(:notes,
      'TASK_PRIVILEGE_DRIFT_MONITOR is RUNNING every ' || :deleg_cadence_min
   || ' minutes. It re-derives the orchestrator reach and writes a row to '
   || 'DELEG_DRIFT_HISTORY, so a grant made at 2am shows up as a rising reach '
   || 'number rather than as an incident six months later. Read '
   || 'V_MONTHLY_RUN_RATE for what that costs and TEARDOWN() to stop it.');
  END IF;

  -- Floor the measurement at THIS build''s start. QUERY_HISTORY_BY_SESSION is
  -- the true history of the session, so a re-run into the same schema would
  -- otherwise average in the previous run''s calls -- true history of a
  -- statement, false history of the object being priced. Declared here rather
  -- than borrowed: 13_governance records that copying 02''s measurement pattern
  -- without declaring this made the whole plan block fail to compile with
  -- "invalid identifier".
  LET build_floor_utc STRING := (
    SELECT TO_CHAR(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP()),
                   'YYYY-MM-DD HH24:MI:SS.FF3'));

  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE TABLE ' || :tgt || '.DELEG_RUN_COST '
 || 'COMMENT = ' || CHAR(39) || 'Measured elapsed time of '
 || 'DELEG_DRIFT_SNAPSHOT(), which is the body of '
 || 'TASK_PRIVILEGE_DRIFT_MONITOR. Source of SECONDS_PER_RUN.' || CHAR(39) || ' AS '
 || 'SELECT COUNT(*) AS RUNS_OBSERVED, '
 || 'ROUND(AVG(TOTAL_ELAPSED_TIME) / 1000.0, 3) AS AVG_SECONDS '
 || 'FROM TABLE(' || :db || '.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(RESULT_LIMIT => 10000)) '
 || 'WHERE QUERY_TYPE = ' || CHAR(39) || 'CALL' || CHAR(39) || ' '
 || 'AND EXECUTION_STATUS = ' || CHAR(39) || 'SUCCESS' || CHAR(39) || ' '
 || 'AND QUERY_TEXT ILIKE ' || CHAR(39) || '%' || :tgt || '.DELEG_DRIFT_SNAPSHOT()%' || CHAR(39) || ' '
 || 'AND CONVERT_TIMEZONE(' || CHAR(39) || 'UTC' || CHAR(39) || ', START_TIME)::TIMESTAMP_NTZ >= '
 || CHAR(39) || :build_floor_utc || CHAR(39) || '::TIMESTAMP_NTZ');

  -- FIXED, not scaled by volume, and the BASIS says why: the monitor reads
  -- grant and task METADATA, so its runtime tracks how many roles and grants
  -- the account has and is independent of the row counts in the tables those
  -- grants cover. A customer with 100x our rows does not make this slower.
  stmts := ARRAY_APPEND(:stmts,
    'INSERT INTO ' || :tgt || '.STANDING_WORKLOAD '
 || '(KIND, OBJECT_NAME, CADENCE, RUNS_PER_MONTH, SECONDS_PER_RUN, '
 || ' WAREHOUSE_CREDITS_PER_HOUR, MEASURED_INPUT, BASIS, INSTALLED_AT) '
 || 'SELECT ' || CHAR(39) || 'TASK' || CHAR(39) || ', '
 || CHAR(39) || 'TASK_PRIVILEGE_DRIFT_MONITOR' || CHAR(39) || ', '
 || CHAR(39) || :deleg_cadence_lbl || CHAR(39) || ', '
 || :runs_per_month_deleg || ', '
 || 'COALESCE(r.AVG_SECONDS, 1.0), '
 || :deleg_wh_cph || ', '
 || 'CASE WHEN r.AVG_SECONDS IS NOT NULL '
 || '  THEN ' || CHAR(39) || 'TOTAL_ELAPSED_TIME averaged over ' || CHAR(39)
 || '    || r.RUNS_OBSERVED || ' || CHAR(39) || ' DELEG_DRIFT_SNAPSHOT() '
 || 'call(s) this build made; the task body is that exact call' || CHAR(39)
 || '  ELSE ' || CHAR(39) || 'no DELEG_DRIFT_SNAPSHOT() call was readable in '
 || 'this session' || CHAR(39) || CHAR(39) || 's query history, so this uses the '
 || '1-warehouse-second floor stated in the plan' || CHAR(39) || ' END, '
 || CHAR(39) || '43800 minutes a month over a ' || :deleg_cadence_min
 || ' minute schedule = ' || :runs_per_month_deleg || ' runs, times measured '
 || 'seconds per snapshot, at ' || :deleg_wh_cph || ' credits/hour ('
 || IFF(:deleg_wh_rate_ok, :wh || ' is ' || :deleg_wh_size,
        'size of ' || :wh || ' unreadable, so 1 credit/hour is a LOWER bound')
 || '). FIXED scaling: the snapshot reads grant and task METADATA, so its '
 || 'runtime follows the number of roles and grants in the account and not the '
 || 'row counts in the tables those grants cover. ' || :gate_basis_deleg
 || CHAR(39) || ', CURRENT_TIMESTAMP() '
 || 'FROM ' || :tgt || '.DELEG_RUN_COST r');

  -- The delegation graph is registered as a VOLUME-driven component: RUNS_PER_
  -- MONTH is NULL because the orchestrator sets the trigger frequency, not this
  -- build, and inventing a cadence for it would be quoting our guess as their
  -- bill. SECONDS_PER_RUN is still carried so the reader can multiply it by
  -- their own cadence, which is the whole "the interval is your dial" claim
  -- made checkable.
  IF (:deleg_graph_built) THEN
    stmts := ARRAY_APPEND(:stmts,
      'INSERT INTO ' || :tgt || '.STANDING_WORKLOAD '
   || '(KIND, OBJECT_NAME, CADENCE, RUNS_PER_MONTH, SECONDS_PER_RUN, '
   || ' WAREHOUSE_CREDITS_PER_HOUR, MEASURED_INPUT, BASIS, INSTALLED_AT) '
   || 'SELECT ' || CHAR(39) || 'TASK' || CHAR(39) || ', '
   || CHAR(39) || 'TASK_DELEG_RUN_ROOT' || CHAR(39) || ', '
   || CHAR(39) || 'on demand, no schedule -- triggered by EXECUTE TASK'
   || IFF(:standing_live_deleg, '', ', SUSPENDED at ' || :tier || ' tier')
   || CHAR(39) || ', '
   || 'NULL, NULL, ' || :deleg_wh_cph || ', '
   || CHAR(39) || 'not measured: the graph has not run, and it cannot be run '
   || 'from here without executing the customer' || CHAR(39) || CHAR(39)
   || 's dbt project' || CHAR(39) || ', '
   || CHAR(39) || 'VOLUME-DRIVEN, deliberately not projected. The root carries '
   || 'no schedule, so it costs nothing until your orchestrator triggers it, '
   || 'and the trigger frequency is yours and not ours -- a runs-per-month here '
   || 'would be our guess printed as your bill. ' || :deleg_graph_steps
   || ' tasks per triggered run (EXECUTE DBT PROJECT run, then test, then a '
   || 'finalizer that sets the return value), all on ' || :wh || ' at '
   || :deleg_wh_cph || ' credits/hour. Because the steps are chained with AFTER '
   || 'rather than polled independently, the run costs the dbt work plus three '
   || 'task overheads and no orchestrator wait between hops. '
   || :gate_basis_deleg || CHAR(39) || ', CURRENT_TIMESTAMP()');
  END IF;

  -- ── V_DELEG_FINDINGS — the summary a reader opens first ───────────────────
  -- Created LAST because it reads everything above it, and Snowflake validates
  -- a view at CREATE time rather than binding it late: naming a table that does
  -- not exist yet fails the build outright rather than at first read.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE VIEW ' || :tgt || '.V_DELEG_FINDINGS '
 || 'COMMENT = ' || CHAR(39) || 'Open this first. The arithmetic, the refusal '
 || 'reason if there is one, and what to read next.' || CHAR(39) || ' AS '
 || 'SELECT 1 AS SEQ, ' || CHAR(39) || 'ORCHESTRATOR ROLE' || CHAR(39) || ' AS FINDING, '
 || CHAR(39) || IFF(:deleg_orch_role = '', 'none named -- reporting only', :deleg_orch_role)
 || CHAR(39) || ' AS VALUE, '
 || CHAR(39) || 'resolved state: ' || :deleg_orch_state || CHAR(39) || ' AS DETAIL '
 || 'UNION ALL SELECT 2, ' || CHAR(39) || 'REFUSAL REASON' || CHAR(39) || ', '
 || CHAR(39) || IFF(:deleg_refusal = '', 'none -- the arithmetic below was derived',
                    REPLACE(:deleg_refusal, CHAR(39), CHAR(39) || CHAR(39)))
 || CHAR(39) || ', '
 || CHAR(39) || 'A refusal is reported, never answered with a zero that reads '
 || 'as a clean pass.' || CHAR(39)
 || ' UNION ALL SELECT 3, ' || CHAR(39) || 'RELATIONS THE ORCHESTRATOR CAN REACH'
 || CHAR(39) || ', (SELECT COUNT(DISTINCT RELATION_FQN)::VARCHAR FROM ' || :tgt
 || '.V_DELEG_ORCHESTRATOR_REACH), '
 || CHAR(39) || 'Through the whole role graph, not direct grants only. '
 || 'Inheritance is how a service role quietly becomes wide.' || CHAR(39)
 || ' UNION ALL SELECT 4, ' || CHAR(39) || 'RELATIONS THE WORK REQUIRES' || CHAR(39)
 || ', (SELECT COUNT(DISTINCT OBJECT_FQN)::VARCHAR FROM ' || :tgt
 || '.V_DELEG_REQUIRED_PRIVILEGES), '
 || CHAR(39) || 'Derived from each dbt project' || CHAR(39) || CHAR(39)
 || 's own declared sources and target. Text derivation over project files, not '
 || 'a compile.' || CHAR(39)
 || ' UNION ALL SELECT 5, ' || CHAR(39) || 'EXCESS -- REVOCABLE TODAY' || CHAR(39)
 || ', (SELECT COUNT(*)::VARCHAR FROM ' || :tgt || '.V_DELEG_REMEDIATION), '
 || CHAR(39) || 'Reach minus required. Zero is a PASS. Every row carries its own '
 || 'REVOKE statement plus the trigger and poll SQL that replaces it.' || CHAR(39)
 || ' UNION ALL SELECT 6, ' || CHAR(39) || 'OWNER RIGHTS ANTI-PATTERNS' || CHAR(39)
 || ', (SELECT COUNT(*)::VARCHAR FROM ' || :tgt || '.V_DELEG_ANTIPATTERNS), '
 || CHAR(39) || 'Text match over ACCOUNT_USAGE definitions, so it lags up to two '
 || 'hours and matches commented-out references. What it finds is real; the '
 || 'absence of a finding is not proof.' || CHAR(39)
 || ' UNION ALL SELECT 7, ' || CHAR(39) || 'DBT PROJECTS PARSED' || CHAR(39) || ', '
 || CHAR(39) || :deleg_parsed_n || ' of ' || :deleg_proj_n || CHAR(39) || ', '
 || CHAR(39) || 'A project that could not be resolved is named in the notes and '
 || 'is excluded, never guessed at.' || CHAR(39)
 || ' UNION ALL SELECT 8, ' || CHAR(39) || 'DELEGATION GRAPH' || CHAR(39) || ', '
 || CHAR(39) || IFF(:deleg_graph_built,
        'TASK_DELEG_RUN_ROOT plus ' || (:deleg_graph_steps - 1) || ' AFTER child task(s)',
        'not created -- no dbt project in scope') || CHAR(39) || ', '
 || CHAR(39) || 'One EXECUTE TASK on the root and ONE poll on '
 || 'GRAPH_RUN_GROUP_ID covers the whole graph. Read TRIGGER_SQL and POLL_SQL '
 || 'in V_DELEG_REMEDIATION.' || CHAR(39)
 || ' ORDER BY SEQ');

  -- ── The contract variables success_criteria.sql reads ─────────────────────
  -- These are the ONLY channel from this file to that one. Both splice into the
  -- same procedure body with this file first, which is what puts them in scope.
  --
  -- required and excess are read back from the views this build just declared,
  -- guarded, because the views do not exist until the statements above execute.
  -- On the first build that read fails and both report 0 WITH the reason
  -- recorded -- never presented as a clean result. On any subsequent build,
  -- and after MEASURE(), they carry the real numbers. The views themselves are
  -- always correct; it is only this plan-time preview that has to wait.
  LET deleg_required_n INT := 0;
  LET deleg_excess_n INT := 0;
  LET deleg_preview_ok BOOLEAN := FALSE;
  BEGIN
    EXECUTE IMMEDIATE
      'SELECT (SELECT COUNT(DISTINCT OBJECT_FQN) FROM ' || :tgt
   || '.V_DELEG_REQUIRED_PRIVILEGES), (SELECT COUNT(*) FROM ' || :tgt
   || '.V_DELEG_REMEDIATION)';
    LET pv RESULTSET := (SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    FOR prow IN pv DO
      deleg_required_n := COALESCE(prow.$1::INT, 0);
      deleg_excess_n := COALESCE(prow.$2::INT, 0);
      deleg_preview_ok := TRUE;
    END FOR;
  EXCEPTION WHEN OTHER THEN
    deleg_required_n := 0;
    deleg_excess_n := 0;
    deleg_preview_ok := FALSE;
  END;

  IF (NOT :deleg_preview_ok) THEN
    notes := ARRAY_APPEND(:notes,
      'The required-privilege and excess counts read 0 in THIS output because '
   || 'the views that compute them are created by the statements below and did '
   || 'not exist when this summary was assembled. That is a reporting order, '
   || 'not a result: after the build, '
   || :tgt || '.V_DELEG_FINDINGS and V_DELEG_REMEDIATION carry the real '
   || 'numbers, and a second run of this script prints them here too. A zero '
   || 'in this position is never a claim that the orchestrator role is clean.');
  END IF;

  -- Excess is floored at 0 rather than allowed to go negative. A required set
  -- larger than the reach means the orchestrator cannot reach something the
  -- work needs, which is a different finding and not a negative excess.
  IF (:deleg_excess_n < 0) THEN
    deleg_excess_n := 0;
  END IF;

  -- ── 2e. Cost model, every number with a dial next to it ──────────────────
  -- The drift monitor is the only thing here with a cadence of its own.
  LET deleg_monitor_credits NUMBER(38,6) :=
    ROUND(:runs_per_month_deleg * 1.0 * :deleg_wh_cph / 3600.0 / 30.4, 6);
  cost_day := :cost_day + :deleg_monitor_credits;
  cost_detail := ARRAY_APPEND(:cost_detail,
    'TASK_PRIVILEGE_DRIFT_MONITOR: ' || :runs_per_month_deleg || ' runs/month '
 || '(a ' || :deleg_cadence_min || ' minute cadence) x measured seconds per '
 || 'snapshot x ' || :deleg_wh_cph || ' credits/hour = ~'
 || :deleg_monitor_credits || ' credits/day'
 || IFF(:standing_live_deleg, '',
        ' -- reported as 0 because the tier is ' || :tier
     || ' and this build suspended the task'));
  dials := ARRAY_APPEND(:dials,
    'DELEG_DRIFT_CADENCE_MINUTES ' || :deleg_cadence_min || ' -> doubling it '
 || 'halves the monitor'''''''' consumption; the only thing you lose is how '
 || 'soon a new grant shows up as drift');

  -- The one-off parse. Stage copy plus one read per project. It scales with the
  -- number of projects in scope, which is why DELEG_PROJECTS is its dial.
  LET deleg_parse_credits NUMBER(38,6) := ROUND(0.01 * GREATEST(:deleg_proj_n, 1), 6);
  cost_once := :cost_once + :deleg_parse_credits;
  cost_detail := ARRAY_APPEND(:cost_detail,
    'One-off dbt project parse: ' || :deleg_proj_n || ' project(s) in scope, '
 || 'each a COPY FILES from its live version plus one read of the staged text, '
 || 'at ~0.01 credits per project = ~' || :deleg_parse_credits || ' credits '
 || 'once. Project files are small; the cost is statement overhead rather than '
 || 'data.');
  dials := ARRAY_APPEND(:dials,
    'DELEG_PROJECTS blank means every dbt project this role can see ('
 || :deleg_proj_n || ' here) -> name one or two fully qualified projects to cut '
 || 'both the one-off parse and the delegation graph down to what you are '
 || 'actually delegating');

  -- The delegation graph has no cadence and therefore no credits/day. It gets a
  -- cost line anyway, because "it costs nothing" is only true until somebody
  -- triggers it and a reader is entitled to the per-run figure.
  IF (:deleg_graph_built) THEN
    cost_detail := ARRAY_APPEND(:cost_detail,
      'Delegation graph: ' || :deleg_graph_steps || ' tasks per triggered run, '
   || 'no schedule, so 0 credits/day standing. Each triggered run costs the dbt '
   || 'work itself plus ' || :deleg_graph_steps || ' task overheads on ' || :wh
   || ' at ' || :deleg_wh_cph || ' credits/hour. Not added to credits/day '
   || 'because the trigger frequency is your orchestrator'''''''' and not ours '
   || '-- multiply the per-run figure in STANDING_WORKLOAD by your own cadence.');
  END IF;

  IF (:deleg_mode = 'HANDSHAKE' AND :deleg_graph_built) THEN
    LET deleg_hs_credits NUMBER(38,6) :=
      IFF(:standing_live_deleg, ROUND(2880.0 * 1.0 * :deleg_wh_cph / 3600.0, 6), 0);
    cost_day := :cost_day + :deleg_hs_credits;
    cost_detail := ARRAY_APPEND(:cost_detail,
      'TASK_DELEG_HANDSHAKE: a 30-second trigger interval is 2880 stream checks '
   || 'a day. A check with no request row skips without starting the warehouse, '
   || 'so the figure below is an UPPER bound that assumes every check does a '
   || 'warehouse-second of work: ~' || :deleg_hs_credits || ' credits/day at '
   || :deleg_wh_cph || ' credits/hour'
   || IFF(:standing_live_deleg, '. Your real figure will be lower.',
          ' -- reported as 0 because the tier is ' || :tier
       || ' and this build suspended the task.'));
  END IF;

  -- ── 2f. Actions ───────────────────────────────────────────────────────────
  -- Every account-level statement -- every GRANT, every REVOKE, and any CREATE
  -- ROLE -- is PRODUCTION tier only and never runs at DISCOVER, LIMITED or
  -- SAMPLE. Everything below PRODUCTION touches only objects this build owns.

  -- SAMPLE. Proves the register-attach-detach cycle against a task this build
  -- created and a role that already exists, putting nothing on anything the
  -- customer owns. The grant is MONITOR on our own drift monitor, which conveys
  -- no data access at all.
  LET s_reg STRING :=
      'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
   || '(TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) SELECT ' || CHAR(39)
   || :deleg_task_fqn || CHAR(39) || ', ' || CHAR(39) || 'PUBLIC' || CHAR(39)
   || ', ' || CHAR(39) || 'MONITOR' || CHAR(39) || ', ' || CHAR(39)
   || 'ROLE_GRANT' || CHAR(39)
   || ' WHERE NOT EXISTS (SELECT 1 FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
   || 'WHERE TARGET_FQN = ' || CHAR(39) || :deleg_task_fqn || CHAR(39)
   || ' AND ARGUMENTS = ' || CHAR(39) || 'MONITOR' || CHAR(39)
   || ' AND KIND = ' || CHAR(39) || 'ROLE_GRANT' || CHAR(39) || ')';
  actions := ARRAY_APPEND(:actions, OBJECT_CONSTRUCT(
    'code',   'DELEG_DEMO',
    'label',  'Prove the grant is registered and reversible, on our own task',
    'tier',   'SAMPLE',
    'effect', 'Grants MONITOR on ' || :deleg_task_fqn || ' -- a task THIS build '
           || 'created -- to the PUBLIC role, after recording it in the '
           || 'attachment registry. MONITOR conveys no data access. Nothing you '
           || 'own is touched. The point is to watch the registry row appear '
           || 'and then watch TEARDOWN() reverse it, before you press either of '
           || 'the PRODUCTION buttons.',
    'undo',   'CALL ' || :tgt || '.TEARDOWN() revokes it and deletes the '
           || 'registry row, in that order.',
    'est',    0.001,
    'basis',  'Two metadata statements against one task object this build owns. '
           || 'A GRANT writes no data and reads none, so the cost is statement '
           || 'overhead.',
    'sql',    ARRAY_CONSTRUCT(:s_reg,
      'GRANT MONITOR ON TASK ' || :deleg_task_fqn || ' TO ROLE PUBLIC'),
    'undo_sql', ARRAY_CONSTRUCT(
      'REVOKE MONITOR ON TASK ' || :deleg_task_fqn || ' FROM ROLE PUBLIC',
      'DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE TARGET_FQN = '
   || CHAR(39) || :deleg_task_fqn || CHAR(39) || ' AND ARGUMENTS = ' || CHAR(39)
   || 'MONITOR' || CHAR(39) || ' AND KIND = ' || CHAR(39) || 'ROLE_GRANT' || CHAR(39))
  ));

  -- PRODUCTION. The delegation grant itself: OPERATE and MONITOR on the ONE
  -- graph root, and nothing else anywhere. This is the whole claim of the
  -- solution reduced to two statements.
  IF (:deleg_graph_built AND :deleg_orch_state = 'FOUND') THEN
    LET g_sql  ARRAY := ARRAY_CONSTRUCT();
    LET g_undo ARRAY := ARRAY_CONSTRUCT();
    LET gi INT := 0;
    LET gpriv ARRAY := ARRAY_CONSTRUCT('OPERATE', 'MONITOR');
    WHILE (:gi < 2) DO
      LET gp STRING := GET(:gpriv, :gi)::STRING;
      -- Register BEFORE granting. If the GRANT succeeds and the registry
      -- INSERT then fails, teardown does not know about the grant and it leaks
      -- into the customer''s account for good. The other order leaves a
      -- registry row for a grant never made, and teardown reports one noisy
      -- failure. Noise is recoverable; a silent leak on someone else''s account
      -- is not.
      g_sql := ARRAY_APPEND(:g_sql,
          'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
       || '(TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) SELECT ' || CHAR(39)
       || :deleg_graph_root || CHAR(39) || ', ' || CHAR(39) || :deleg_orch_role
       || CHAR(39) || ', ' || CHAR(39) || :gp || CHAR(39) || ', ' || CHAR(39)
       || 'ROLE_GRANT' || CHAR(39)
       || ' WHERE NOT EXISTS (SELECT 1 FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
       || 'WHERE TARGET_FQN = ' || CHAR(39) || :deleg_graph_root || CHAR(39)
       || ' AND ARGUMENTS = ' || CHAR(39) || :gp || CHAR(39)
       || ' AND KIND = ' || CHAR(39) || 'ROLE_GRANT' || CHAR(39) || ')');
      g_sql := ARRAY_APPEND(:g_sql,
          'GRANT ' || :gp || ' ON TASK ' || :deleg_graph_root
       || ' TO ROLE ' || :deleg_orch_role);
      -- The mirror: REVOKE first, THEN forget the recording. Deleting first
      -- would destroy the only evidence of what still needs revoking if the
      -- REVOKE then failed.
      g_undo := ARRAY_APPEND(:g_undo,
          'REVOKE ' || :gp || ' ON TASK ' || :deleg_graph_root
       || ' FROM ROLE ' || :deleg_orch_role);
      g_undo := ARRAY_APPEND(:g_undo,
          'DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE TARGET_FQN = '
       || CHAR(39) || :deleg_graph_root || CHAR(39) || ' AND ARGUMENTS = '
       || CHAR(39) || :gp || CHAR(39) || ' AND KIND = ' || CHAR(39)
       || 'ROLE_GRANT' || CHAR(39));
      gi := :gi + 1;
    END WHILE;

    actions := ARRAY_APPEND(:actions, OBJECT_CONSTRUCT(
      'code',   'DELEG_GRANT_OPERATE',
      'label',  'Let ' || :deleg_orch_role || ' start the run, and nothing else',
      'tier',   'PRODUCTION',
      'effect', 'Grants OPERATE and MONITOR on ' || :deleg_graph_root || ' to '
             || :deleg_orch_role || '. That is two grants on one task object. It '
             || 'conveys no privilege on any source or target relation, because '
             || 'the run executes with the rights of the role that OWNS the '
             || 'task. Your orchestrator then triggers it with EXECUTE TASK '
             || 'USING CONFIG carrying its own run id, and polls ONCE on '
             || 'GRAPH_RUN_GROUP_ID in INFORMATION_SCHEMA.TASK_HISTORY -- one '
             || 'poll for the whole graph, not one per dbt command. Both '
             || 'statements are copy-ready in V_DELEG_REMEDIATION. Each grant is '
             || 'registered before it is made.',
      'undo',   'CALL ' || :tgt || '.TEARDOWN(), or REVOKE OPERATE and MONITOR '
             || 'ON TASK ' || :deleg_graph_root || ' FROM ROLE ' || :deleg_orch_role || '.',
      'est',    0.002,
      'basis',  '4 statements: 2 registry writes and 2 GRANTs on one task. All '
             || 'metadata, no data read or written. Derived from the 1 '
             || 'delegation graph root discovered above, not from a constant.',
      'sql',    :g_sql,
      'undo_sql', :g_undo
    ));
  ELSEIF (:deleg_graph_built AND :deleg_orch_state <> 'FOUND') THEN
    notes := ARRAY_APPEND(:notes,
      'No OPERATE grant is offered, because the orchestrator role is '
   || :deleg_orch_state || '. The delegation graph exists and is ready; naming '
   || 'a resolvable role in DELEG_ORCHESTRATOR_ROLE is the only thing between '
   || 'this build and a one-button delegation grant.');
  END IF;

  -- PRODUCTION. The revocation. Built from V_DELEG_REMEDIATION at run time
  -- rather than baked in here, because the excess list is what the views
  -- compute and a list frozen at plan time would revoke yesterday''s answer.
  IF (:deleg_orch_state = 'FOUND') THEN
    actions := ARRAY_APPEND(:actions, OBJECT_CONSTRUCT(
      'code',   'DELEG_REVOKE_EXCESS',
      'label',  'Revoke the excess privileges V_DELEG_REMEDIATION names',
      'tier',   'PRODUCTION',
      'effect', 'Writes one registry row per excess grant on ' || :deleg_orch_role
             || ', then revokes it. The list is read from V_DELEG_REMEDIATION at '
             || 'the moment you press this, so it revokes what is excess NOW and '
             || 'not what was excess when this plan was printed. Read the view '
             || 'first: every row carries the relation, the privilege, whether '
             || 'it is direct or inherited, and the exact REVOKE. An INHERITED '
             || 'row is revoked from the role that actually holds the grant, '
             || 'which may be a role other than ' || :deleg_orch_role
             || ' and may affect other members of it -- that is the one thing to '
             || 'check by hand before pressing this.',
      'undo',   'CALL ' || :tgt || '.TEARDOWN() re-grants every privilege it '
             || 'recorded, from the registry rows this action wrote.',
      'est',    ROUND(0.001 * GREATEST(:deleg_reach_n, 1), 4),
      'basis',  'Up to ' || :deleg_reach_n || ' reachable relation-privilege '
             || 'pairs were measured on this role graph, and the excess subset '
             || 'is what gets revoked -- 2 metadata statements each. Derived '
             || 'from the measured reach, not a constant. The real count is the '
             || 'row count of V_DELEG_REMEDIATION at press time.',
      'sql',    ARRAY_CONSTRUCT(
        'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
     || '(TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) '
     || 'SELECT RELATION_FQN, GRANTED_TO_ROLE, PRIVILEGE, ' || CHAR(39)
     || 'ROLE_GRANT' || CHAR(39) || ' FROM ' || :tgt || '.V_DELEG_REMEDIATION r '
     || 'WHERE NOT EXISTS (SELECT 1 FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY x '
     || 'WHERE x.TARGET_FQN = r.RELATION_FQN AND x.ARGUMENTS = r.PRIVILEGE '
     || 'AND x.KIND = ' || CHAR(39) || 'ROLE_GRANT' || CHAR(39) || ')',
        -- One EXECUTE IMMEDIATE per row, driven off the view. A cursor rather
        -- than a generated list for the same reason the effect text gives: the
        -- list must be current at press time.
        'EXECUTE IMMEDIATE ' || CHAR(39) || 'BEGIN LET c CURSOR FOR SELECT '
     || 'REVOKE_SQL FROM ' || :tgt || '.V_DELEG_REMEDIATION; FOR r IN c DO '
     || 'EXECUTE IMMEDIATE r.REVOKE_SQL; END FOR; RETURN ' || CHAR(39) || CHAR(39)
     || 'REVOKED' || CHAR(39) || CHAR(39) || '; END' || CHAR(39)),
      'undo_sql', ARRAY_CONSTRUCT(
        'EXECUTE IMMEDIATE ' || CHAR(39) || 'BEGIN LET c CURSOR FOR SELECT '
     || 'ARGUMENTS, TARGET_FQN, ARTIFACT FROM ' || :tgt
     || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ' || CHAR(39) || CHAR(39)
     || 'ROLE_GRANT' || CHAR(39) || CHAR(39) || '; FOR r IN c DO EXECUTE '
     || 'IMMEDIATE ' || CHAR(39) || CHAR(39) || 'GRANT ' || CHAR(39) || CHAR(39)
     || ' || r.ARGUMENTS || ' || CHAR(39) || CHAR(39) || ' ON TABLE '
     || CHAR(39) || CHAR(39) || ' || r.TARGET_FQN || ' || CHAR(39) || CHAR(39)
     || ' TO ROLE ' || CHAR(39) || CHAR(39) || ' || r.ARTIFACT; END FOR; RETURN '
     || CHAR(39) || CHAR(39) || 'RESTORED' || CHAR(39) || CHAR(39) || '; END'
     || CHAR(39))
    ));
  END IF;

  -- CREATE ROLE is offered ONLY when the operator asked for it AND the tier is
  -- PRODUCTION. It defaults off, meaning adoption: propose grants on roles that
  -- already exist and never invent one. A role is an account-level object, so a
  -- role this build creates is a role TEARDOWN() drops -- which is exactly why
  -- it takes two deliberate settings to reach.
  IF (:deleg_create_roles AND :deleg_exec_role = '' AND :deleg_graph_built) THEN
    notes := ARRAY_APPEND(:notes,
      'DELEG_CREATE_ROLES is TRUE and no execution role could be adopted, so a '
   || 'PRODUCTION action is offered that CREATES one. Understand the teardown '
   || 'consequence before pressing it: a role is an account-level object, and a '
   || 'role this build created that your team then starts depending on is a '
   || 'role TEARDOWN() will DROP.');
    actions := ARRAY_APPEND(:actions, OBJECT_CONSTRUCT(
      'code',   'DELEG_CREATE_EXEC_ROLE',
      'label',  'Create the execution role DELEG_EXEC (account-level, dropped by teardown)',
      'tier',   'PRODUCTION',
      'effect', 'Creates the account-level role DELEG_EXEC and records it in the '
             || 'attachment registry so teardown can reverse it. Nothing is '
             || 'granted to it here -- you decide what rights the dbt run '
             || 'executes with. This exists only because no role owning a dbt '
             || 'project object could be adopted.',
      'undo',   'CALL ' || :tgt || '.TEARDOWN() DROPS the role. That is '
             || 'destructive and account-level: if your team has started '
             || 'granting things to DELEG_EXEC, teardown removes it anyway.',
      'est',    0.001,
      'basis',  'Two metadata statements. Offered because 0 role owning a dbt '
             || 'project object was discoverable and ' || :deleg_proj_n
             || ' project(s) are in scope needing one.',
      'sql',    ARRAY_CONSTRUCT(
        'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
     || '(TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) SELECT ' || CHAR(39)
     || 'DELEG_EXEC' || CHAR(39) || ', ' || CHAR(39) || 'DELEG_EXEC' || CHAR(39)
     || ', ' || CHAR(39) || CHAR(39) || ', ' || CHAR(39) || 'ROLE' || CHAR(39)
     || ' WHERE NOT EXISTS (SELECT 1 FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
     || 'WHERE TARGET_FQN = ' || CHAR(39) || 'DELEG_EXEC' || CHAR(39)
     || ' AND KIND = ' || CHAR(39) || 'ROLE' || CHAR(39) || ')',
        'CREATE ROLE IF NOT EXISTS DELEG_EXEC'),
      'undo_sql', ARRAY_CONSTRUCT(
        'DROP ROLE IF EXISTS DELEG_EXEC',
        'DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE TARGET_FQN = '
     || CHAR(39) || 'DELEG_EXEC' || CHAR(39) || ' AND KIND = ' || CHAR(39)
     || 'ROLE' || CHAR(39))
    ));
  ELSEIF (NOT :deleg_create_roles) THEN
    notes := ARRAY_APPEND(:notes,
      'ADOPTION MODE: DELEG_CREATE_ROLES is FALSE, so this build issues no '
   || 'CREATE ROLE at any tier and proposes grants only on roles your account '
   || 'already has. Teardown therefore removes grants and never a role.');
  END IF;

  -- ── 2i. Headline and the standing limitations ────────────────────────────
  IF (:deleg_refusal <> '') THEN
    headline := 'Inventory only: ' || :deleg_refusal || '. '
      || :deleg_antipattern_n || ' owner-rights anti-pattern(s) and '
      || :deleg_task_ap_n || ' existing delegation task(s) are reported anyway, '
      || 'and no excess-privilege claim is made from a role graph that was not '
      || 'walked.';
  ELSEIF (:deleg_graph_built) THEN
    headline := 'A delegation graph ' || :deleg_orch_role || ' can start and '
      || 'cannot read: one EXECUTE TASK, one poll, and OPERATE on a single task '
      || 'instead of grants on your source and target tables. '
      || :deleg_reach_n || ' relation(s) are currently reachable by that role '
      || 'through the whole role graph; V_DELEG_REMEDIATION names the excess '
      || 'with the REVOKE, the trigger call and the poll query for each.';
  ELSE
    headline := 'Owner-rights inventory for ' || :deleg_orch_role || ': '
      || :deleg_reach_n || ' relation(s) reachable through the role graph and '
      || :deleg_antipattern_n || ' anti-pattern(s) found, with no delegation '
      || 'graph built because no dbt project object is in scope to run.';
  END IF;

  notes := ARRAY_APPEND(:notes,
    'HOW THE REQUIRED SET IS DERIVED, AND WHAT IT MISSES. Each project in scope '
 || 'is copied out of its live version into ' || :deleg_stage || ' and read as '
 || 'text. Fully-qualified relations after FROM or JOIN in model SQL become '
 || 'SOURCE rows; the database and schema in the project profile become the '
 || 'TARGET row. A source macro naming a relation outside the target namespace '
 || 'is NOT found by a text pass -- it resolves when dbt compiles, which this '
 || 'build does not do. So V_DELEG_REQUIRED_PRIVILEGES is a floor on what the '
 || 'work requires, which means V_DELEG_REMEDIATION can over-report excess and '
 || 'never under-report it. Read a REVOKE before you run it.');

  notes := ARRAY_APPEND(:notes,
    'WHY THE POLL SQL USES INFORMATION_SCHEMA AND NOT ACCOUNT_USAGE. Both '
 || 'expose CONFIG, GRAPH_RUN_GROUP_ID, RUN_ID, RETURN_VALUE and STATE, so the '
 || 'correlation works against either. ACCOUNT_USAGE.TASK_HISTORY lags, and a '
 || 'five-minute end-to-end target can be missed on that lag alone while every '
 || 'task in the graph has already finished. Every generated poll statement in '
 || 'V_DELEG_REMEDIATION uses the INFORMATION_SCHEMA table function, which is '
 || 'near-real-time. Do not substitute the other one.');

  notes := ARRAY_APPEND(:notes,
    'THE RETURN VALUE COSTS AN EXTRA TASK. A task whose body is only EXECUTE '
 || 'DBT PROJECT cannot also call SYSTEM$SET_RETURN_VALUE, so a dbt-level '
 || 'success payload needs the finalizer task at the end of the graph. That is '
 || 'one more task object and one more hop, and it is stated here rather than '
 || 'implied to be free. Without it the orchestrator still gets STATE, '
 || 'ERROR_CODE and ERROR_MESSAGE per task from TASK_HISTORY -- it just does '
 || 'not get a dbt-shaped result.');
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
-- What would make this delegation POC a success, measured against bars derived
-- from THIS account's own role graph and its own dbt projects rather than from a
-- least-privilege framework.
--
-- EVERY CRITERION IS GATED ON THE SLOT IT READS. When no orchestrator role is
-- named, when no dbt project object is visible, or when the ACCOUNT_USAGE views
-- the anti-pattern scan needs cannot be read, the criteria that depend on those
-- inputs are declared N/A with the reason -- never scored zero, because a zero
-- here would read as a clean result.
--
-- WHAT IS DELIBERATELY NOT HERE. There is no "no owner's-rights anti-pattern
-- exists anywhere in the account" claim. The scan is a text match over
-- ACCOUNT_USAGE definitions, so it inherits that view's lag of up to two hours
-- and it counts a commented-out reference as a hit. It finds what it finds.
-- There is also no criterion asserting the orchestrator cannot read source data,
-- because proving that requires authenticating as that role -- see
-- DELEG_BOUNDARY_HOLDS, which says so rather than assuming it.

-- ── Excess privileges removed ─────────────────────────────────────────────────
IF (:deleg_orch_state = 'FOUND') THEN
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'DELEG_EXCESS_REMOVED',
    'label', 'The orchestrator role reaches nothing beyond what the work requires',
    'why', 'This is the whole deliverable. A security team does not sign a claim '
        || 'that a service role is least-privileged; it signs a difference it can '
        || 'read. Every row in the remediation view is a grant the orchestrator '
        || 'holds that no dbt project in scope actually needs.',
    'compare', '<=',
    'units', 'excess grants',
    'basis', 'BY_QUERY_ID',
    'target_sql', 'SELECT 0',
    'actual_sql', 'SELECT COUNT(*) FROM ' || :tgt || '.V_DELEG_REMEDIATION',
    'target_derivation', 'Zero, where the bar is derived by subtracting the '
        || 'relations the dbt projects in scope declare from the relations '
        || :deleg_orch_role || ' can reach through the full role graph -- this '
        || 'account''s own grants, not a framework''s idea of least privilege. A '
        || 'role that is already clean returns zero rows, and that is a pass.'));
ELSEIF (:deleg_orch_state = 'NO ACCESS') THEN
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'DELEG_EXCESS_REMOVED',
    'label', 'The orchestrator role reaches nothing beyond what the work requires',
    'why', 'The difference between what a role can reach and what the work needs '
        || 'is the deliverable, and it cannot be computed from outside the role graph.',
    'compare', '<=',
    'units', 'excess grants',
    'basis', 'BY_QUERY_ID',
    'target_derivation', 'Would be this account''s own role graph minus the '
        || 'declared requirements of the dbt projects in scope. Neither side could '
        || 'be read.',
    'na_reason', 'The role graph could not be read. This role needs IMPORTED '
        || 'PRIVILEGES on SNOWFLAKE, specifically SELECT on '
        || 'SNOWFLAKE.ACCOUNT_USAGE.ROLES and '
        || 'SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES. Without them the reach side '
        || 'of the subtraction does not exist, and reporting zero excess grants '
        || 'from an unreadable graph would be the most misleading result this '
        || 'solution could produce.'));
ELSE
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'DELEG_EXCESS_REMOVED',
    'label', 'The orchestrator role reaches nothing beyond what the work requires',
    'why', 'A remediation is only meaningful against a named role. Computed '
        || 'against no role, or against a role that does not exist, it is a guess '
        || 'dressed as a finding.',
    'compare', '<=',
    'units', 'excess grants',
    'basis', 'BY_QUERY_ID',
    'target_derivation', 'Would be derived by subtracting the declared '
        || 'requirements of the dbt projects in scope from the relations the '
        || 'orchestrator role can reach through the full role graph.',
    'na_reason', 'DELEG_ORCHESTRATOR_ROLE is '
        || IFF(:deleg_orch_state = 'BLANK', 'blank, so no role was named.',
               'set to ' || :deleg_orch_role || ', which does not exist in this '
               || 'account.')
        || ' Set it to the role your orchestrator authenticates as and re-run. '
        || 'Reporting zero excess privileges for a role nobody named would read '
        || 'as a pass.'));
END IF;

-- ── Required-privilege set actually derived ───────────────────────────────────
-- The honest half of the subtraction. If a project's files could not be read,
-- the requirement side is incomplete and the excess figure above is a floor.
IF (:deleg_proj_n > 0) THEN
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'DELEG_REQUIRED_SET_DERIVED',
    'label', 'Every dbt project in scope had its sources and targets parsed',
    'why', 'The required-privilege set is subtracted from the orchestrator''s '
        || 'reach, so a project that could not be parsed makes the excess figure '
        || 'a floor rather than an answer. This criterion is what stops the '
        || 'remediation from looking complete when it is not.',
    'compare', '>=',
    'units', 'projects parsed',
    'basis', 'BY_QUERY_ID',
    'target_sql', 'SELECT ' || :deleg_proj_n,
    'actual_sql', 'SELECT ' || :deleg_parsed_n,
    'target_derivation', 'The number of dbt project objects in scope, currently '
        || :deleg_proj_n || '. Parsed so far: ' || :deleg_parsed_n || '. A project '
        || 'whose files cannot be staged and read is reported short rather than '
        || 'assumed to require nothing.'));
ELSE
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'DELEG_REQUIRED_SET_DERIVED',
    'label', 'Every dbt project in scope had its sources and targets parsed',
    'why', 'Without a project there is nothing to derive a required-privilege '
        || 'set from, and inventing one would be inventing the answer.',
    'compare', '>=',
    'units', 'projects parsed',
    'basis', 'BY_QUERY_ID',
    'target_derivation', 'Would be the count of dbt project objects in scope.',
    'na_reason', 'No dbt project object was visible to this role. Either the '
        || 'account has none, or DELEG_PROJECTS names one that could not be '
        || 'resolved. The task and procedure anti-pattern findings do not depend '
        || 'on the project parse and are still reported.'));
END IF;

-- ── No owner's-rights anti-patterns remain ───────────────────────────────────
-- Gated on the two ACCOUNT_USAGE probes this reads. probes.sql reports UNKNOWN
-- rather than zero when the task scan fails, precisely because a zero here would
-- read as "no anti-patterns found".
IF (COALESCE(GET(:sig, 'as_user_tasks')::STRING, 'UNKNOWN') NOT IN ('UNKNOWN', 'NO ACCESS')
    AND COALESCE(GET(:sig, 'proc_attempts')::STRING, 'NO ACCESS') != 'NO ACCESS') THEN
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'DELEG_NO_ANTIPATTERNS',
    'label', 'No delegation object is configured to run as the caller',
    'why', 'Ownership is the whole game and it is invisible from the outside. If '
        || 'the orchestrator calls a procedure that CREATES the task, the task is '
        || 'owned by the orchestrator''s role and the wall is still there one step '
        || 'further along -- the same DDL, run by a different role, produces a '
        || 'compliant pipeline or a wide-open one. A task set EXECUTE AS USER does '
        || 'not error at creation; it fails when it runs, which is how it survives '
        || 'review.',
    'compare', '<=',
    'units', 'anti-pattern rows',
    'basis', 'BY_QUERY_ID',
    'target_sql', 'SELECT 0',
    'actual_sql', 'SELECT COUNT(*) FROM ' || :tgt || '.V_DELEG_ANTIPATTERNS',
    'target_derivation', 'Zero rows in this account''s own task and procedure '
        || 'definitions. The scan is a text match over ACCOUNT_USAGE definitions, '
        || 'so it lags by up to two hours and counts a commented-out reference as '
        || 'a hit. It reports what it can see and does not claim to be exhaustive.'));
ELSE
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'DELEG_NO_ANTIPATTERNS',
    'label', 'No delegation object is configured to run as the caller',
    'why', 'A task configured EXECUTE AS USER, or a procedure attempting either '
        || 'delegation verb, is the failure this solution exists to catch.',
    'compare', '<=',
    'units', 'anti-pattern rows',
    'basis', 'BY_QUERY_ID',
    'target_derivation', 'Would be zero rows across this account''s task and '
        || 'procedure definitions.',
    'na_reason', 'The anti-pattern scan could not read '
        || 'SNOWFLAKE.ACCOUNT_USAGE.TASKS or SNOWFLAKE.ACCOUNT_USAGE.PROCEDURES, '
        || 'so it found nothing because it could see nothing. Grant this role '
        || 'access to those views and re-run. A count of zero from an unreadable '
        || 'scan would read as a clean account.'));
END IF;

-- ── The delegation boundary itself ───────────────────────────────────────────
-- Declared, not asserted. Proving the orchestrator cannot reach a source table
-- means issuing a SELECT while authenticated AS that role, which this build
-- cannot do and must not pretend to have done.
success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
  'code', 'DELEG_BOUNDARY_HOLDS',
  'label', 'The orchestrator can start the run and still reach no source or target relation',
  'why', 'A task runs with the privileges of the role that OWNS it even when a '
      || 'different role triggers it, which is why the task is the owner''s-rights '
      || 'boundary a stored procedure cannot be. The claim is only worth something '
      || 'if somebody tries to cross the boundary and fails.',
  'compare', '<=',
  'units', 'readable relations',
  'basis', 'BY_QUERY_ID',
  'target_sql', 'SELECT 0',
  'target_derivation', 'Zero relations readable by the orchestrator role in '
      || IFF(:deleg_mode = 'HANDSHAKE',
             'HANDSHAKE mode, where it holds no task privilege at all and only '
             || 'inserts a request row and reads a status row.',
             'OPERATE mode, where it holds OPERATE and MONITOR on one task and '
             || 'nothing else.')
      || ' The bar is zero because the required-privilege arithmetic showed the '
      || 'run does not need the orchestrator to hold any data grant.',
  'pending_reason', 'This build cannot measure it. Verifying that a role cannot '
      || 'read a relation means running the query AS that role, and this session '
      || 'is not authenticated as '
      || IFF(:deleg_orch_role = '', 'the orchestrator role', :deleg_orch_role)
      || '. Reporting it as met from this side would be asserting the one thing '
      || 'the customer is being asked to trust.',
  'resolves_when', 'Someone authenticates as the orchestrator role, runs '
      || 'USE SECONDARY ROLES NONE, then triggers the delegation graph and '
      || 'attempts a direct SELECT on a source relation. The trigger must succeed '
      || 'and the SELECT must fail. V_DELEG_REMEDIATION carries both statements.'));

-- ── End-to-end latency of one real graph run ─────────────────────────────────
-- MEASURED, never asserted -- a customer rejected this pattern on latency
-- arithmetic that was correct for the topology they assumed, so a number this
-- solution merely claims is worth nothing here. Always declared, so a build that
-- has not run the graph shows PENDING rather than silently dropping the promise.
success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
  'code', 'DELEG_GRAPH_LATENCY',
  'label', 'One delegation graph run completes end to end inside the latency bar',
  'why', 'Chaining the steps with AFTER means Snowflake schedules each child on '
      || 'parent success with no polling between hops, so the orchestrator '
      || 'triggers the root once and polls once on GRAPH_RUN_GROUP_ID. One task '
      || 'per dbt command polled independently stacks one poll interval per hop, '
      || 'which is how this pattern gets rejected for solving the privilege '
      || 'problem and creating an SLA problem instead.',
  'compare', '<=',
  'units', 'seconds',
  'basis', 'BY_TIME_WINDOW',
  'target_sql', 'SELECT 300',
  'actual_sql', 'SELECT DATEDIFF(second, MIN(QUERY_START_TIME), MAX(COMPLETED_TIME)) '
      || 'FROM TABLE(' || :db || '.INFORMATION_SCHEMA.TASK_HISTORY('
      || 'SCHEDULED_TIME_RANGE_START => ''' || TO_VARCHAR(CURRENT_TIMESTAMP(),
             'YYYY-MM-DD HH24:MI:SS.FF3 TZHTZM') || '''::TIMESTAMP_LTZ)) '
      || 'WHERE SCHEMA_NAME = ''' || :sch || ''' '
      || 'AND NAME != ''TASK_PRIVILEGE_DRIFT_MONITOR'' '
      || 'AND GRAPH_RUN_GROUP_ID IS NOT NULL AND COMPLETED_TIME IS NOT NULL '
      || 'GROUP BY GRAPH_RUN_GROUP_ID ORDER BY MAX(COMPLETED_TIME) DESC LIMIT 1',
  'target_derivation', '300 seconds is the five-minute end-to-end bar the '
      || 'customer review that produced this design was measuring against. It is '
      || 'not a Snowflake default and this build did not derive it from your '
      || 'account -- if your SLA differs, edit this criterion. The measurement is '
      || 'wall clock across one whole graph run in the '
      || :sch || ' schema, from the first task''s query start to the last task''s '
      || 'completion, floored at this build so a re-run into the same schema '
      || 'cannot average in an earlier run. The drift monitor is excluded by name '
      || 'so its own runs cannot stand in for a delegation run. Read from '
      || 'INFORMATION_SCHEMA.TASK_HISTORY, which is near-real-time, and not from '
      || 'ACCOUNT_USAGE.TASK_HISTORY, whose lag would blow a five-minute bar on '
      || 'its own.',
  'pending_reason', 'No graph run has completed in this schema since the build. '
      || 'Below PRODUCTION tier the delegation graph is created and then '
      || 'suspended, so there is nothing to measure -- an absence of a run, not a '
      || 'latency of zero and not a failure.',
  'resolves_when', 'The graph root is triggered with EXECUTE TASK ... USING '
      || 'CONFIG and the run completes, then MEASURE() is called in this schema. '
      || 'At PRODUCTION tier the graph is left running and the first scheduled '
      || 'run fills this in.'));

-- ── Cost ──────────────────────────────────────────────────────────────────────
IF (:credit_cap > 0) THEN
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'DELEG_COST_IN_BUDGET',
    'label', 'Measured steady-state cost stays inside your credit cap',
    'why', 'A POC that cannot state its own running cost cannot be approved for '
        || 'production, and a projection is not a measurement.',
    'compare', '<=',
    'units', 'credits',
    'basis', 'BY_TAG',
    'target_sql', 'SELECT ' || :credit_cap,
    'actual_sql', 'SELECT SUM(CREDITS) FROM ' || :tgt || '.V_COST_LINES '
        || 'WHERE LABEL = ''MEASURED'' AND STATUS = ''LANDED''',
    'target_derivation', 'Your DELEG_CREDIT_CAP setting, currently '
        || :credit_cap || ' credits.',
    'pending_reason', 'Warehouse credits reach ACCOUNT_USAGE on a delay, so '
        || 'nothing has been attributed to this run yet. This is an absence of '
        || 'data, not a cost of zero and not a failure.',
    'resolves_when', 'credits land in ACCOUNT_USAGE, typically within 8 hours -- '
        || 'call MEASURE() in this schema after that to fill it in'));
ELSE
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'DELEG_COST_IN_BUDGET',
    'label', 'Measured steady-state cost stays inside your credit cap',
    'why', 'A POC that cannot state its own running cost cannot be approved for '
        || 'production.',
    'compare', '<=',
    'units', 'credits',
    'basis', 'BY_TAG',
    'target_derivation', 'No cap was set, so there is no bar to derive.',
    'na_reason', 'DELEG_CREDIT_CAP is 0, so no ceiling was declared for this run. '
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
   || 'COMMENT = ''Cost attribution for Zero-Privilege Orchestration. Query '
   || 'ACCOUNT_USAGE.TAG_REFERENCES to find everything this deployment owns.''');
    stmts := ARRAY_APPEND(:stmts,
      'ALTER SCHEMA ' || :tgt || ' SET TAG ' || :tgt || '.ONESHOT_SOLUTION = '
   || '''Zero-Privilege Orchestration''');
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
     || '.ONESHOT_SOLUTION = ''Zero-Privilege Orchestration''');
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
        'FAILURE NOTIFICATION SKIPPED: DELEG_NOTIFICATION_INTEGRATION is blank, so '
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
 || '      RETURN ''REFUSED. This build was created with DELEG_ALLOW_SAMPLE_ACTIONS = '
 || 'FALSE, so even the seeded-data actions are inert. Re-run the script with it set '
 || 'to TRUE to arm them.''; '
 || '    END IF; '
 || '  ELSE '
 || '    enabled := (SELECT ACTIONS_ENABLED FROM ' || :tgt || '.V_BUILD_CONTEXT LIMIT 1); '
 || '    IF (NOT COALESCE(:enabled, FALSE)) THEN '
 || '      RETURN ''REFUSED. '' || :tier || '' actions touch real data and this build was '
 || 'created with DELEG_ALLOW_ACTIONS = FALSE, so nothing in the app can change '
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
 || '      RETURN ''REFUSED. This build was created with DELEG_ALLOW_SAMPLE_ACTIONS = FALSE.''; '
 || '    END IF; '
 || '  ELSE '
 || '    enabled := (SELECT ACTIONS_ENABLED FROM ' || :tgt || '.V_BUILD_CONTEXT LIMIT 1); '
 || '    IF (NOT COALESCE(:enabled, FALSE)) THEN '
 || '      RETURN ''REFUSED. This build was created with DELEG_ALLOW_ACTIONS = FALSE.''; '
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
          'DELEG_ALLOW_ACTIONS is TRUE, so they are ARMED: a user of the dashboard can '
       || 'run them after typing the action code to confirm. Every attempt is recorded '
       || 'in ACTION_LOG.',
          'DELEG_ALLOW_ACTIONS is FALSE, so every button is inert and RUN_ACTION refuses. '
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
  -- ui-sources sha256:5bcc8f08c36a6469
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
    || 'aWsvZFM1a1pXWmhkV3gwT25WOWRtRnlJRWhzUFh0bGVIQnZjblJ6T250OWZTeFhiajE3ZlN4V2JEMTdaWGh3YjNKMGN6cDdmWDBzUWoxN2ZUc3ZLaW9LSUNv'
    || 'Z1FHeHBZMlZ1YzJVZ1VtVmhZM1FLSUNvZ2NtVmhZM1F1Y0hKdlpIVmpkR2x2Ymk1dGFXNHVhbk1LSUNvS0lDb2dRMjl3ZVhKcFoyaDBJQ2hqS1NCR1lXTmxZ'
    || 'bTl2YXl3Z1NXNWpMaUJoYm1RZ2FYUnpJR0ZtWm1sc2FXRjBaWE11Q2lBcUNpQXFJRlJvYVhNZ2MyOTFjbU5sSUdOdlpHVWdhWE1nYkdsalpXNXpaV1FnZFc1'
    || 'a1pYSWdkR2hsSUUxSlZDQnNhV05sYm5ObElHWnZkVzVrSUdsdUlIUm9aUW9nS2lCTVNVTkZUbE5GSUdacGJHVWdhVzRnZEdobElISnZiM1FnWkdseVpXTjBi'
    || 'M0o1SUc5bUlIUm9hWE1nYzI5MWNtTmxJSFJ5WldVdUNpQXFMM1poY2lCWWJ6dG1kVzVqZEdsdmJpQjFZeWdwZTJsbUtGaHZLWEpsZEhWeWJpQkNPMWh2UFRF'
    || 'N2RtRnlJSFU5VTNsdFltOXNMbVp2Y2lnaWNtVmhZM1F1Wld4bGJXVnVkQ0lwTEdROVUzbHRZbTlzTG1admNpZ2ljbVZoWTNRdWNHOXlkR0ZzSWlrc1l6MVRl'
    || 'VzFpYjJ3dVptOXlLQ0p5WldGamRDNW1jbUZuYldWdWRDSXBMSGc5VTNsdFltOXNMbVp2Y2lnaWNtVmhZM1F1YzNSeWFXTjBYMjF2WkdVaUtTeEZQVk41YldK'
    || 'dmJDNW1iM0lvSW5KbFlXTjBMbkJ5YjJacGJHVnlJaWtzVkQxVGVXMWliMnd1Wm05eUtDSnlaV0ZqZEM1d2NtOTJhV1JsY2lJcExIazlVM2x0WW05c0xtWnZj'
    || 'aWdpY21WaFkzUXVZMjl1ZEdWNGRDSXBMRTQ5VTNsdFltOXNMbVp2Y2lnaWNtVmhZM1F1Wm05eWQyRnlaRjl5WldZaUtTeHFQVk41YldKdmJDNW1iM0lvSW5K'
    || 'bFlXTjBMbk4xYzNCbGJuTmxJaWtzUnoxVGVXMWliMnd1Wm05eUtDSnlaV0ZqZEM1dFpXMXZJaWtzVEQxVGVXMWliMnd1Wm05eUtDSnlaV0ZqZEM1c1lYcDVJ'
    || 'aWtzUmoxVGVXMWliMnd1YVhSbGNtRjBiM0k3Wm5WdVkzUnBiMjRnVmlob0tYdHlaWFIxY200Z2FEMDlQVzUxYkd4OGZIUjVjR1Z2WmlCb0lUMGliMkpxWldO'
    || 'MElqOXVkV3hzT2lob1BVWW1KbWhiUmwxOGZHaGJJa0JBYVhSbGNtRjBiM0lpWFN4MGVYQmxiMllnYUQwOUltWjFibU4wYVc5dUlqOW9PbTUxYkd3cGZYWmhj'
    || 'aUIxWlQxN2FYTk5iM1Z1ZEdWa09tWjFibU4wYVc5dUtDbDdjbVYwZFhKdUlURjlMR1Z1Y1hWbGRXVkdiM0pqWlZWd1pHRjBaVHBtZFc1amRHbHZiaWdwZTMw'
    || 'c1pXNXhkV1YxWlZKbGNHeGhZMlZUZEdGMFpUcG1kVzVqZEdsdmJpZ3BlMzBzWlc1eGRXVjFaVk5sZEZOMFlYUmxPbVoxYm1OMGFXOXVLQ2w3Zlgwc1NqMVBZ'
    || 'bXBsWTNRdVlYTnphV2R1TEdJOWUzMDdablZ1WTNScGIyNGdXU2hvTEY4c1Z5bDdkR2hwY3k1d2NtOXdjejFvTEhSb2FYTXVZMjl1ZEdWNGREMWZMSFJvYVhN'
    || 'dWNtVm1jejFpTEhSb2FYTXVkWEJrWVhSbGNqMVhmSHgxWlgxWkxuQnliM1J2ZEhsd1pTNXBjMUpsWVdOMFEyOXRjRzl1Wlc1MFBYdDlMRmt1Y0hKdmRHOTBl'
    || 'WEJsTG5ObGRGTjBZWFJsUFdaMWJtTjBhVzl1S0dnc1h5bDdhV1lvZEhsd1pXOW1JR2doUFNKdlltcGxZM1FpSmlaMGVYQmxiMllnYUNFOUltWjFibU4wYVc5'
    || 'dUlpWW1hQ0U5Ym5Wc2JDbDBhSEp2ZHlCRmNuSnZjaWdpYzJWMFUzUmhkR1VvTGk0dUtUb2dkR0ZyWlhNZ1lXNGdiMkpxWldOMElHOW1JSE4wWVhSbElIWmhj'
    || 'bWxoWW14bGN5QjBieUIxY0dSaGRHVWdiM0lnWVNCbWRXNWpkR2x2YmlCM2FHbGphQ0J5WlhSMWNtNXpJR0Z1SUc5aWFtVmpkQ0J2WmlCemRHRjBaU0IyWVhK'
    || 'cFlXSnNaWE11SWlrN2RHaHBjeTUxY0dSaGRHVnlMbVZ1Y1hWbGRXVlRaWFJUZEdGMFpTaDBhR2x6TEdnc1h5d2ljMlYwVTNSaGRHVWlLWDBzV1M1d2NtOTBi'
    || 'M1I1Y0dVdVptOXlZMlZWY0dSaGRHVTlablZ1WTNScGIyNG9hQ2w3ZEdocGN5NTFjR1JoZEdWeUxtVnVjWFZsZFdWR2IzSmpaVlZ3WkdGMFpTaDBhR2x6TEdn'
    || 'c0ltWnZjbU5sVlhCa1lYUmxJaWw5TzJaMWJtTjBhVzl1SUdKbEtDbDdmV0psTG5CeWIzUnZkSGx3WlQxWkxuQnliM1J2ZEhsd1pUdG1kVzVqZEdsdmJpQkNa'
    || 'U2hvTEY4c1Z5bDdkR2hwY3k1d2NtOXdjejFvTEhSb2FYTXVZMjl1ZEdWNGREMWZMSFJvYVhNdWNtVm1jejFpTEhSb2FYTXVkWEJrWVhSbGNqMVhmSHgxWlgx'
    || 'MllYSWdVV1U5UW1VdWNISnZkRzkwZVhCbFBXNWxkeUJpWlR0UlpTNWpiMjV6ZEhKMVkzUnZjajFDWlN4S0tGRmxMRmt1Y0hKdmRHOTBlWEJsS1N4UlpTNXBj'
    || 'MUIxY21WU1pXRmpkRU52YlhCdmJtVnVkRDBoTUR0MllYSWdaMlU5UVhKeVlYa3VhWE5CY25KaGVTeDZaVDFQWW1wbFkzUXVjSEp2ZEc5MGVYQmxMbWhoYzA5'
    || 'M2JsQnliM0JsY25SNUxIZGxQWHRqZFhKeVpXNTBPbTUxYkd4OUxFNWxQWHRyWlhrNklUQXNjbVZtT2lFd0xGOWZjMlZzWmpvaE1DeGZYM052ZFhKalpUb2hN'
    || 'SDA3Wm5WdVkzUnBiMjRnVUdVb2FDeGZMRmNwZTNaaGNpQlJMRmc5ZTMwc1dqMXVkV3hzTEc1bFBXNTFiR3c3YVdZb1h5RTliblZzYkNsbWIzSW9VU0JwYmlC'
    || 'ZkxuSmxaaUU5UFhadmFXUWdNQ1ltS0c1bFBWOHVjbVZtS1N4ZkxtdGxlU0U5UFhadmFXUWdNQ1ltS0ZvOUlpSXJYeTVyWlhrcExGOHBlbVV1WTJGc2JDaGZM'
    || 'RkVwSmlZaFRtVXVhR0Z6VDNkdVVISnZjR1Z5ZEhrb1VTa21KaWhZVzFGZFBWOWJVVjBwTzNaaGNpQmxaVDFoY21kMWJXVnVkSE11YkdWdVozUm9MVEk3YVdZ'
    || 'b1pXVTlQVDB4S1ZndVkyaHBiR1J5Wlc0OVZ6dGxiSE5sSUdsbUtERThaV1VwZTJadmNpaDJZWElnYjJVOVFYSnlZWGtvWldVcExFdGxQVEE3UzJVOFpXVTdT'
    || 'MlVyS3lsdlpWdExaVjA5WVhKbmRXMWxiblJ6VzB0bEt6SmRPMWd1WTJocGJHUnlaVzQ5YjJWOWFXWW9hQ1ltYUM1a1pXWmhkV3gwVUhKdmNITXBabTl5S0ZF'
    || 'Z2FXNGdaV1U5YUM1a1pXWmhkV3gwVUhKdmNITXNaV1VwV0Z0UlhUMDlQWFp2YVdRZ01DWW1LRmhiVVYwOVpXVmJVVjBwTzNKbGRIVnlibnNrSkhSNWNHVnZa'
    || 'anAxTEhSNWNHVTZhQ3hyWlhrNldpeHlaV1k2Ym1Vc2NISnZjSE02V0N4ZmIzZHVaWEk2ZDJVdVkzVnljbVZ1ZEgxOVpuVnVZM1JwYjI0Z1pHVW9hQ3hmS1h0'
    || 'eVpYUjFjbTU3SkNSMGVYQmxiMlk2ZFN4MGVYQmxPbWd1ZEhsd1pTeHJaWGs2WHl4eVpXWTZhQzV5WldZc2NISnZjSE02YUM1d2NtOXdjeXhmYjNkdVpYSTZh'
    || 'QzVmYjNkdVpYSjlmV1oxYm1OMGFXOXVJR3QwS0dncGUzSmxkSFZ5YmlCMGVYQmxiMllnYUQwOUltOWlhbVZqZENJbUptZ2hQVDF1ZFd4c0ppWm9MaVFrZEhs'
    || 'd1pXOW1QVDA5ZFgxbWRXNWpkR2x2YmlCMGJpaG9LWHQyWVhJZ1h6MTdJajBpT2lJOU1DSXNJam9pT2lJOU1pSjlPM0psZEhWeWJpSWtJaXRvTG5KbGNHeGhZ'
    || 'MlVvTDFzOU9sMHZaeXhtZFc1amRHbHZiaWhYS1h0eVpYUjFjbTRnWDF0WFhYMHBmWFpoY2lCbmREMHZYQzhyTDJjN1puVnVZM1JwYjI0Z1IyVW9hQ3hmS1h0'
    || 'eVpYUjFjbTRnZEhsd1pXOW1JR2c5UFNKdlltcGxZM1FpSmlab0lUMDliblZzYkNZbWFDNXJaWGtoUFc1MWJHdy9kRzRvSWlJcmFDNXJaWGtwT2w4dWRHOVRk'
    || 'SEpwYm1jb016WXBmV1oxYm1OMGFXOXVJSFYwS0dnc1h5eFhMRkVzV0NsN2RtRnlJRm85ZEhsd1pXOW1JR2c3S0ZvOVBUMGlkVzVrWldacGJtVmtJbng4V2ow'
    || 'OVBTSmliMjlzWldGdUlpa21KaWhvUFc1MWJHd3BPM1poY2lCdVpUMGhNVHRwWmlob1BUMDliblZzYkNsdVpUMGhNRHRsYkhObElITjNhWFJqYUNoYUtYdGpZ'
    || 'WE5sSW5OMGNtbHVaeUk2WTJGelpTSnVkVzFpWlhJaU9tNWxQU0V3TzJKeVpXRnJPMk5oYzJVaWIySnFaV04wSWpwemQybDBZMmdvYUM0a0pIUjVjR1Z2Wmls'
    || 'N1kyRnpaU0IxT21OaGMyVWdaRHB1WlQwaE1IMTlhV1lvYm1VcGNtVjBkWEp1SUc1bFBXZ3NXRDFZS0c1bEtTeG9QVkU5UFQwaUlqOGlMaUlyUjJVb2JtVXNN'
    || 'Q2s2VVN4blpTaFlLVDhvVnowaUlpeG9JVDF1ZFd4c0ppWW9WejFvTG5KbGNHeGhZMlVvWjNRc0lpUW1MeUlwS3lJdklpa3NkWFFvV0N4ZkxGY3NJaUlzWm5W'
    || 'dVkzUnBiMjRvUzJVcGUzSmxkSFZ5YmlCTFpYMHBLVHBZSVQxdWRXeHNKaVlvYTNRb1dDa21KaWhZUFdSbEtGZ3NWeXNvSVZndWEyVjVmSHh1WlNZbWJtVXVh'
    || 'MlY1UFQwOVdDNXJaWGsvSWlJNktDSWlLMWd1YTJWNUtTNXlaWEJzWVdObEtHZDBMQ0lrSmk4aUtTc2lMeUlwSzJncEtTeGZMbkIxYzJnb1dDa3BMREU3YVdZ'
    || 'b2JtVTlNQ3hSUFZFOVBUMGlJajhpTGlJNlVTc2lPaUlzWjJVb2FDa3BabTl5S0haaGNpQmxaVDB3TzJWbFBHZ3ViR1Z1WjNSb08yVmxLeXNwZTFvOWFGdGxa'
    || 'VjA3ZG1GeUlHOWxQVkVyUjJVb1dpeGxaU2s3Ym1VclBYVjBLRm9zWHl4WExHOWxMRmdwZldWc2MyVWdhV1lvYjJVOVZpaG9LU3gwZVhCbGIyWWdiMlU5UFNK'
    || 'bWRXNWpkR2x2YmlJcFptOXlLR2c5YjJVdVkyRnNiQ2hvS1N4bFpUMHdPeUVvV2oxb0xtNWxlSFFvS1NrdVpHOXVaVHNwV2oxYUxuWmhiSFZsTEc5bFBWRXJS'
    || 'MlVvV2l4bFpTc3JLU3h1WlNzOWRYUW9XaXhmTEZjc2IyVXNXQ2s3Wld4elpTQnBaaWhhUFQwOUltOWlhbVZqZENJcGRHaHliM2NnWHoxVGRISnBibWNvYUNr'
    || 'c1JYSnliM0lvSWs5aWFtVmpkSE1nWVhKbElHNXZkQ0IyWVd4cFpDQmhjeUJoSUZKbFlXTjBJR05vYVd4a0lDaG1iM1Z1WkRvZ0lpc29YejA5UFNKYmIySnFa'
    || 'V04wSUU5aWFtVmpkRjBpUHlKdlltcGxZM1FnZDJsMGFDQnJaWGx6SUhzaUswOWlhbVZqZEM1clpYbHpLR2dwTG1wdmFXNG9JaXdnSWlrckluMGlPbDhwS3lJ'
    || 'cExpQkpaaUI1YjNVZ2JXVmhiblFnZEc4Z2NtVnVaR1Z5SUdFZ1kyOXNiR1ZqZEdsdmJpQnZaaUJqYUdsc1pISmxiaXdnZFhObElHRnVJR0Z5Y21GNUlHbHVj'
    || 'M1JsWVdRdUlpazdjbVYwZFhKdUlHNWxmV1oxYm1OMGFXOXVJSGwwS0dnc1h5eFhLWHRwWmlob1BUMXVkV3hzS1hKbGRIVnliaUJvTzNaaGNpQlJQVnRkTEZn'
    || 'OU1EdHlaWFIxY200Z2RYUW9hQ3hSTENJaUxDSWlMR1oxYm1OMGFXOXVLRm9wZTNKbGRIVnliaUJmTG1OaGJHd29WeXhhTEZnckt5bDlLU3hSZldaMWJtTjBh'
    || 'Vzl1SUVabEtHZ3BlMmxtS0dndVgzTjBZWFIxY3owOVBTMHhLWHQyWVhJZ1h6MW9MbDl5WlhOMWJIUTdYejFmS0Nrc1h5NTBhR1Z1S0daMWJtTjBhVzl1S0Zj'
    || 'cGV5aG9MbDl6ZEdGMGRYTTlQVDB3Zkh4b0xsOXpkR0YwZFhNOVBUMHRNU2ttSmlob0xsOXpkR0YwZFhNOU1TeG9MbDl5WlhOMWJIUTlWeWw5TEdaMWJtTjBh'
    || 'Vzl1S0ZjcGV5aG9MbDl6ZEdGMGRYTTlQVDB3Zkh4b0xsOXpkR0YwZFhNOVBUMHRNU2ttSmlob0xsOXpkR0YwZFhNOU1peG9MbDl5WlhOMWJIUTlWeWw5S1N4'
    || 'b0xsOXpkR0YwZFhNOVBUMHRNU1ltS0dndVgzTjBZWFIxY3owd0xHZ3VYM0psYzNWc2REMWZLWDFwWmlob0xsOXpkR0YwZFhNOVBUMHhLWEpsZEhWeWJpQm9M'
    || 'bDl5WlhOMWJIUXVaR1ZtWVhWc2REdDBhSEp2ZHlCb0xsOXlaWE4xYkhSOWRtRnlJR1psUFh0amRYSnlaVzUwT201MWJHeDlMRkk5ZTNSeVlXNXphWFJwYjI0'
    || 'NmJuVnNiSDBzSkQxN1VtVmhZM1JEZFhKeVpXNTBSR2x6Y0dGMFkyaGxjanBtWlN4U1pXRmpkRU4xY25KbGJuUkNZWFJqYUVOdmJtWnBaenBTTEZKbFlXTjBR'
    || 'M1Z5Y21WdWRFOTNibVZ5T25kbGZUdG1kVzVqZEdsdmJpQk5LQ2w3ZEdoeWIzY2dSWEp5YjNJb0ltRmpkQ2d1TGk0cElHbHpJRzV2ZENCemRYQndiM0owWldR'
    || 'Z2FXNGdjSEp2WkhWamRHbHZiaUJpZFdsc1pITWdiMllnVW1WaFkzUXVJaWw5Y21WMGRYSnVJRUl1UTJocGJHUnlaVzQ5ZTIxaGNEcDVkQ3htYjNKRllXTm9P'
    || 'bVoxYm1OMGFXOXVLR2dzWHl4WEtYdDVkQ2hvTEdaMWJtTjBhVzl1S0NsN1h5NWhjSEJzZVNoMGFHbHpMR0Z5WjNWdFpXNTBjeWw5TEZjcGZTeGpiM1Z1ZERw'
    || 'bWRXNWpkR2x2Ymlob0tYdDJZWElnWHowd08zSmxkSFZ5YmlCNWRDaG9MR1oxYm1OMGFXOXVLQ2w3WHlzcmZTa3NYMzBzZEc5QmNuSmhlVHBtZFc1amRHbHZi'
    || 'aWhvS1h0eVpYUjFjbTRnZVhRb2FDeG1kVzVqZEdsdmJpaGZLWHR5WlhSMWNtNGdYMzBwZkh4YlhYMHNiMjVzZVRwbWRXNWpkR2x2Ymlob0tYdHBaaWdoYTNR'
    || 'b2FDa3BkR2h5YjNjZ1JYSnliM0lvSWxKbFlXTjBMa05vYVd4a2NtVnVMbTl1YkhrZ1pYaHdaV04wWldRZ2RHOGdjbVZqWldsMlpTQmhJSE5wYm1kc1pTQlNa'
    || 'V0ZqZENCbGJHVnRaVzUwSUdOb2FXeGtMaUlwTzNKbGRIVnliaUJvZlgwc1FpNURiMjF3YjI1bGJuUTlXU3hDTGtaeVlXZHRaVzUwUFdNc1FpNVFjbTltYVd4'
    || 'bGNqMUZMRUl1VUhWeVpVTnZiWEJ2Ym1WdWREMUNaU3hDTGxOMGNtbGpkRTF2WkdVOWVDeENMbE4xYzNCbGJuTmxQV29zUWk1ZlgxTkZRMUpGVkY5SlRsUkZV'
    || 'azVCVEZOZlJFOWZUazlVWDFWVFJWOVBVbDlaVDFWZlYwbE1URjlDUlY5R1NWSkZSRDBrTEVJdVlXTjBQVTBzUWk1amJHOXVaVVZzWlcxbGJuUTlablZ1WTNS'
    || 'cGIyNG9hQ3hmTEZjcGUybG1LR2c5UFc1MWJHd3BkR2h5YjNjZ1JYSnliM0lvSWxKbFlXTjBMbU5zYjI1bFJXeGxiV1Z1ZENndUxpNHBPaUJVYUdVZ1lYSm5k'
    || 'VzFsYm5RZ2JYVnpkQ0JpWlNCaElGSmxZV04wSUdWc1pXMWxiblFzSUdKMWRDQjViM1VnY0dGemMyVmtJQ0lyYUNzaUxpSXBPM1poY2lCUlBVb29lMzBzYUM1'
    || 'd2NtOXdjeWtzV0Qxb0xtdGxlU3hhUFdndWNtVm1MRzVsUFdndVgyOTNibVZ5TzJsbUtGOGhQVzUxYkd3cGUybG1LRjh1Y21WbUlUMDlkbTlwWkNBd0ppWW9X'
    || 'ajFmTG5KbFppeHVaVDEzWlM1amRYSnlaVzUwS1N4ZkxtdGxlU0U5UFhadmFXUWdNQ1ltS0ZnOUlpSXJYeTVyWlhrcExHZ3VkSGx3WlNZbWFDNTBlWEJsTG1S'
    || 'bFptRjFiSFJRY205d2N5bDJZWElnWldVOWFDNTBlWEJsTG1SbFptRjFiSFJRY205d2N6dG1iM0lvYjJVZ2FXNGdYeWw2WlM1allXeHNLRjhzYjJVcEppWWhU'
    || 'bVV1YUdGelQzZHVVSEp2Y0dWeWRIa29iMlVwSmlZb1VWdHZaVjA5WDF0dlpWMDlQVDEyYjJsa0lEQW1KbVZsSVQwOWRtOXBaQ0F3UDJWbFcyOWxYVHBmVzI5'
    || 'bFhTbDlkbUZ5SUc5bFBXRnlaM1Z0Wlc1MGN5NXNaVzVuZEdndE1qdHBaaWh2WlQwOVBURXBVUzVqYUdsc1pISmxiajFYTzJWc2MyVWdhV1lvTVR4dlpTbDda'
    || 'V1U5UVhKeVlYa29iMlVwTzJadmNpaDJZWElnUzJVOU1EdExaVHh2WlR0TFpTc3JLV1ZsVzB0bFhUMWhjbWQxYldWdWRITmJTMlVyTWwwN1VTNWphR2xzWkhK'
    || 'bGJqMWxaWDF5WlhSMWNtNTdKQ1IwZVhCbGIyWTZkU3gwZVhCbE9tZ3VkSGx3WlN4clpYazZXQ3h5WldZNldpeHdjbTl3Y3pwUkxGOXZkMjVsY2pwdVpYMTlM'
    || 'RUl1WTNKbFlYUmxRMjl1ZEdWNGREMW1kVzVqZEdsdmJpaG9LWHR5WlhSMWNtNGdhRDE3SkNSMGVYQmxiMlk2ZVN4ZlkzVnljbVZ1ZEZaaGJIVmxPbWdzWDJO'
    || 'MWNuSmxiblJXWVd4MVpUSTZhQ3hmZEdoeVpXRmtRMjkxYm5RNk1DeFFjbTkyYVdSbGNqcHVkV3hzTEVOdmJuTjFiV1Z5T201MWJHd3NYMlJsWm1GMWJIUldZ'
    || 'V3gxWlRwdWRXeHNMRjluYkc5aVlXeE9ZVzFsT201MWJHeDlMR2d1VUhKdmRtbGtaWEk5ZXlRa2RIbHdaVzltT2xRc1gyTnZiblJsZUhRNmFIMHNhQzVEYjI1'
    || 'emRXMWxjajFvZlN4Q0xtTnlaV0YwWlVWc1pXMWxiblE5VUdVc1FpNWpjbVZoZEdWR1lXTjBiM0o1UFdaMWJtTjBhVzl1S0dncGUzWmhjaUJmUFZCbExtSnBi'
    || 'bVFvYm5Wc2JDeG9LVHR5WlhSMWNtNGdYeTUwZVhCbFBXZ3NYMzBzUWk1amNtVmhkR1ZTWldZOVpuVnVZM1JwYjI0b0tYdHlaWFIxY201N1kzVnljbVZ1ZERw'
    || 'dWRXeHNmWDBzUWk1bWIzSjNZWEprVW1WbVBXWjFibU4wYVc5dUtHZ3BlM0psZEhWeWJuc2tKSFI1Y0dWdlpqcE9MSEpsYm1SbGNqcG9mWDBzUWk1cGMxWmhi'
    || 'R2xrUld4bGJXVnVkRDFyZEN4Q0xteGhlbms5Wm5WdVkzUnBiMjRvYUNsN2NtVjBkWEp1ZXlRa2RIbHdaVzltT2t3c1gzQmhlV3h2WVdRNmUxOXpkR0YwZFhN'
    || 'NkxURXNYM0psYzNWc2REcG9mU3hmYVc1cGREcEdaWDE5TEVJdWJXVnRiejFtZFc1amRHbHZiaWhvTEY4cGUzSmxkSFZ5Ym5za0pIUjVjR1Z2WmpwSExIUjVj'
    || 'R1U2YUN4amIyMXdZWEpsT2w4OVBUMTJiMmxrSURBL2JuVnNiRHBmZlgwc1FpNXpkR0Z5ZEZSeVlXNXphWFJwYjI0OVpuVnVZM1JwYjI0b2FDbDdkbUZ5SUY4'
    || 'OVVpNTBjbUZ1YzJsMGFXOXVPMUl1ZEhKaGJuTnBkR2x2YmoxN2ZUdDBjbmw3YUNncGZXWnBibUZzYkhsN1VpNTBjbUZ1YzJsMGFXOXVQVjk5ZlN4Q0xuVnVj'
    || 'M1JoWW14bFgyRmpkRDFOTEVJdWRYTmxRMkZzYkdKaFkyczlablZ1WTNScGIyNG9hQ3hmS1h0eVpYUjFjbTRnWm1VdVkzVnljbVZ1ZEM1MWMyVkRZV3hzWW1G'
    || 'amF5aG9MRjhwZlN4Q0xuVnpaVU52Ym5SbGVIUTlablZ1WTNScGIyNG9hQ2w3Y21WMGRYSnVJR1psTG1OMWNuSmxiblF1ZFhObFEyOXVkR1Y0ZENob0tYMHNR'
    || 'aTUxYzJWRVpXSjFaMVpoYkhWbFBXWjFibU4wYVc5dUtDbDdmU3hDTG5WelpVUmxabVZ5Y21Wa1ZtRnNkV1U5Wm5WdVkzUnBiMjRvYUNsN2NtVjBkWEp1SUda'
    || 'bExtTjFjbkpsYm5RdWRYTmxSR1ZtWlhKeVpXUldZV3gxWlNob0tYMHNRaTUxYzJWRlptWmxZM1E5Wm5WdVkzUnBiMjRvYUN4ZktYdHlaWFIxY200Z1ptVXVZ'
    || 'M1Z5Y21WdWRDNTFjMlZGWm1abFkzUW9hQ3hmS1gwc1FpNTFjMlZKWkQxbWRXNWpkR2x2YmlncGUzSmxkSFZ5YmlCbVpTNWpkWEp5Wlc1MExuVnpaVWxrS0Ns'
    || 'OUxFSXVkWE5sU1cxd1pYSmhkR2wyWlVoaGJtUnNaVDFtZFc1amRHbHZiaWhvTEY4c1Z5bDdjbVYwZFhKdUlHWmxMbU4xY25KbGJuUXVkWE5sU1cxd1pYSmhk'
    || 'R2wyWlVoaGJtUnNaU2hvTEY4c1Z5bDlMRUl1ZFhObFNXNXpaWEowYVc5dVJXWm1aV04wUFdaMWJtTjBhVzl1S0dnc1h5bDdjbVYwZFhKdUlHWmxMbU4xY25K'
    || 'bGJuUXVkWE5sU1c1elpYSjBhVzl1UldabVpXTjBLR2dzWHlsOUxFSXVkWE5sVEdGNWIzVjBSV1ptWldOMFBXWjFibU4wYVc5dUtHZ3NYeWw3Y21WMGRYSnVJ'
    || 'R1psTG1OMWNuSmxiblF1ZFhObFRHRjViM1YwUldabVpXTjBLR2dzWHlsOUxFSXVkWE5sVFdWdGJ6MW1kVzVqZEdsdmJpaG9MRjhwZTNKbGRIVnliaUJtWlM1'
    || 'amRYSnlaVzUwTG5WelpVMWxiVzhvYUN4ZktYMHNRaTUxYzJWU1pXUjFZMlZ5UFdaMWJtTjBhVzl1S0dnc1h5eFhLWHR5WlhSMWNtNGdabVV1WTNWeWNtVnVk'
    || 'QzUxYzJWU1pXUjFZMlZ5S0dnc1h5eFhLWDBzUWk1MWMyVlNaV1k5Wm5WdVkzUnBiMjRvYUNsN2NtVjBkWEp1SUdabExtTjFjbkpsYm5RdWRYTmxVbVZtS0dn'
    || 'cGZTeENMblZ6WlZOMFlYUmxQV1oxYm1OMGFXOXVLR2dwZTNKbGRIVnliaUJtWlM1amRYSnlaVzUwTG5WelpWTjBZWFJsS0dncGZTeENMblZ6WlZONWJtTkZl'
    || 'SFJsY201aGJGTjBiM0psUFdaMWJtTjBhVzl1S0dnc1h5eFhLWHR5WlhSMWNtNGdabVV1WTNWeWNtVnVkQzUxYzJWVGVXNWpSWGgwWlhKdVlXeFRkRzl5WlNo'
    || 'b0xGOHNWeWw5TEVJdWRYTmxWSEpoYm5OcGRHbHZiajFtZFc1amRHbHZiaWdwZTNKbGRIVnliaUJtWlM1amRYSnlaVzUwTG5WelpWUnlZVzV6YVhScGIyNG9L'
    || 'WDBzUWk1MlpYSnphVzl1UFNJeE9DNHpMakVpTEVKOWRtRnlJRnB2TzJaMWJtTjBhVzl1SUZkc0tDbDdjbVYwZFhKdUlGcHZmSHdvV204OU1TeFdiQzVsZUhC'
    || 'dmNuUnpQWFZqS0NrcExGWnNMbVY0Y0c5eWRITjlMeW9xQ2lBcUlFQnNhV05sYm5ObElGSmxZV04wQ2lBcUlISmxZV04wTFdwemVDMXlkVzUwYVcxbExuQnli'
    || 'MlIxWTNScGIyNHViV2x1TG1wekNpQXFDaUFxSUVOdmNIbHlhV2RvZENBb1l5a2dSbUZqWldKdmIyc3NJRWx1WXk0Z1lXNWtJR2wwY3lCaFptWnBiR2xoZEdW'
    || 'ekxnb2dLZ29nS2lCVWFHbHpJSE52ZFhKalpTQmpiMlJsSUdseklHeHBZMlZ1YzJWa0lIVnVaR1Z5SUhSb1pTQk5TVlFnYkdsalpXNXpaU0JtYjNWdVpDQnBi'
    || 'aUIwYUdVS0lDb2dURWxEUlU1VFJTQm1hV3hsSUdsdUlIUm9aU0J5YjI5MElHUnBjbVZqZEc5eWVTQnZaaUIwYUdseklITnZkWEpqWlNCMGNtVmxMZ29nS2k5'
    || 'MllYSWdjVzg3Wm5WdVkzUnBiMjRnWVdNb0tYdHBaaWh4YnlseVpYUjFjbTRnVjI0N2NXODlNVHQyWVhJZ2RUMVhiQ2dwTEdROVUzbHRZbTlzTG1admNpZ2lj'
    || 'bVZoWTNRdVpXeGxiV1Z1ZENJcExHTTlVM2x0WW05c0xtWnZjaWdpY21WaFkzUXVabkpoWjIxbGJuUWlLU3g0UFU5aWFtVmpkQzV3Y205MGIzUjVjR1V1YUdG'
    || 'elQzZHVVSEp2Y0dWeWRIa3NSVDExTGw5ZlUwVkRVa1ZVWDBsT1ZFVlNUa0ZNVTE5RVQxOU9UMVJmVlZORlgwOVNYMWxQVlY5WFNVeE1YMEpGWDBaSlVrVkVM'
    || 'bEpsWVdOMFEzVnljbVZ1ZEU5M2JtVnlMRlE5ZTJ0bGVUb2hNQ3h5WldZNklUQXNYMTl6Wld4bU9pRXdMRjlmYzI5MWNtTmxPaUV3ZlR0bWRXNWpkR2x2YmlC'
    || 'NUtFNHNhaXhIS1h0MllYSWdUQ3hHUFh0OUxGWTliblZzYkN4MVpUMXVkV3hzTzBjaFBUMTJiMmxrSURBbUppaFdQU0lpSzBjcExHb3VhMlY1SVQwOWRtOXBa'
    || 'Q0F3SmlZb1ZqMGlJaXRxTG10bGVTa3NhaTV5WldZaFBUMTJiMmxrSURBbUppaDFaVDFxTG5KbFppazdabTl5S0V3Z2FXNGdhaWw0TG1OaGJHd29haXhNS1NZ'
    || 'bUlWUXVhR0Z6VDNkdVVISnZjR1Z5ZEhrb1RDa21KaWhHVzB4ZFBXcGJURjBwTzJsbUtFNG1KazR1WkdWbVlYVnNkRkJ5YjNCektXWnZjaWhNSUdsdUlHbzlU'
    || 'aTVrWldaaGRXeDBVSEp2Y0hNc2FpbEdXMHhkUFQwOWRtOXBaQ0F3SmlZb1JsdE1YVDFxVzB4ZEtUdHlaWFIxY201N0pDUjBlWEJsYjJZNlpDeDBlWEJsT2s0'
    || 'c2EyVjVPbFlzY21WbU9uVmxMSEJ5YjNCek9rWXNYMjkzYm1WeU9rVXVZM1Z5Y21WdWRIMTljbVYwZFhKdUlGZHVMa1p5WVdkdFpXNTBQV01zVjI0dWFuTjRQ'
    || 'WGtzVjI0dWFuTjRjejE1TEZkdWZYWmhjaUJLYnp0bWRXNWpkR2x2YmlCall5Z3BlM0psZEhWeWJpQktiM3g4S0VwdlBURXNTR3d1Wlhod2IzSjBjejFoWXln'
    || 'cEtTeEliQzVsZUhCdmNuUnpmWFpoY2lCdlBXTmpLQ2tzUW13OVYyd29LVHRqYjI1emRDQk5kRDF6WXloQ2JDazdkbUZ5SUV4eVBYdDlMRkZzUFh0bGVIQnZj'
    || 'blJ6T250OWZTeEVaVDE3ZlN4SGJEMTdaWGh3YjNKMGN6cDdmWDBzUzJ3OWUzMDdMeW9xQ2lBcUlFQnNhV05sYm5ObElGSmxZV04wQ2lBcUlITmphR1ZrZFd4'
    || 'bGNpNXdjbTlrZFdOMGFXOXVMbTFwYmk1cWN3b2dLZ29nS2lCRGIzQjVjbWxuYUhRZ0tHTXBJRVpoWTJWaWIyOXJMQ0JKYm1NdUlHRnVaQ0JwZEhNZ1lXWm1h'
    || 'V3hwWVhSbGN5NEtJQ29LSUNvZ1ZHaHBjeUJ6YjNWeVkyVWdZMjlrWlNCcGN5QnNhV05sYm5ObFpDQjFibVJsY2lCMGFHVWdUVWxVSUd4cFkyVnVjMlVnWm05'
    || 'MWJtUWdhVzRnZEdobENpQXFJRXhKUTBWT1UwVWdabWxzWlNCcGJpQjBhR1VnY205dmRDQmthWEpsWTNSdmNua2diMllnZEdocGN5QnpiM1Z5WTJVZ2RISmxa'
    || 'UzRLSUNvdmRtRnlJR0p2TzJaMWJtTjBhVzl1SUdSaktDbDdjbVYwZFhKdUlHSnZmSHdvWW04OU1Td29ablZ1WTNScGIyNG9kU2w3Wm5WdVkzUnBiMjRnWkNo'
    || 'U0xDUXBlM1poY2lCTlBWSXViR1Z1WjNSb08xSXVjSFZ6YUNna0tUdGxPbVp2Y2lnN01EeE5PeWw3ZG1GeUlHZzlUUzB4UGo0K01TeGZQVkpiYUYwN2FXWW9N'
    || 'RHhGS0Y4c0pDa3BVbHRvWFQwa0xGSmJUVjA5WHl4TlBXZzdaV3h6WlNCaWNtVmhheUJsZlgxbWRXNWpkR2x2YmlCaktGSXBlM0psZEhWeWJpQlNMbXhsYm1k'
    || 'MGFEMDlQVEEvYm5Wc2JEcFNXekJkZldaMWJtTjBhVzl1SUhnb1VpbDdhV1lvVWk1c1pXNW5kR2c5UFQwd0tYSmxkSFZ5YmlCdWRXeHNPM1poY2lBa1BWSmJN'
    || 'RjBzVFQxU0xuQnZjQ2dwTzJsbUtFMGhQVDBrS1h0U1d6QmRQVTA3WlRwbWIzSW9kbUZ5SUdnOU1DeGZQVkl1YkdWdVozUm9MRmM5WHo0K1BqRTdhRHhYT3ls'
    || 'N2RtRnlJRkU5TWlvb2FDc3hLUzB4TEZnOVVsdFJYU3hhUFZFck1TeHVaVDFTVzFwZE8ybG1LREErUlNoWUxFMHBLVm84WHlZbU1ENUZLRzVsTEZncFB5aFNX'
    || 'MmhkUFc1bExGSmJXbDA5VFN4b1BWb3BPaWhTVzJoZFBWZ3NVbHRSWFQxTkxHZzlVU2s3Wld4elpTQnBaaWhhUEY4bUpqQStSU2h1WlN4TktTbFNXMmhkUFc1'
    || 'bExGSmJXbDA5VFN4b1BWbzdaV3h6WlNCaWNtVmhheUJsZlgxeVpYUjFjbTRnSkgxbWRXNWpkR2x2YmlCRktGSXNKQ2w3ZG1GeUlFMDlVaTV6YjNKMFNXNWta'
    || 'WGd0SkM1emIzSjBTVzVrWlhnN2NtVjBkWEp1SUUwaFBUMHdQMDA2VWk1cFpDMGtMbWxrZldsbUtIUjVjR1Z2WmlCd1pYSm1iM0p0WVc1alpUMDlJbTlpYW1W'
    || 'amRDSW1KblI1Y0dWdlppQndaWEptYjNKdFlXNWpaUzV1YjNjOVBTSm1kVzVqZEdsdmJpSXBlM1poY2lCVVBYQmxjbVp2Y20xaGJtTmxPM1V1ZFc1emRHRmli'
    || 'R1ZmYm05M1BXWjFibU4wYVc5dUtDbDdjbVYwZFhKdUlGUXVibTkzS0NsOWZXVnNjMlY3ZG1GeUlIazlSR0YwWlN4T1BYa3VibTkzS0NrN2RTNTFibk4wWVdK'
    || 'c1pWOXViM2M5Wm5WdVkzUnBiMjRvS1h0eVpYUjFjbTRnZVM1dWIzY29LUzFPZlgxMllYSWdhajFiWFN4SFBWdGRMRXc5TVN4R1BXNTFiR3dzVmowekxIVmxQ'
    || 'U0V4TEVvOUlURXNZajBoTVN4WlBYUjVjR1Z2WmlCelpYUlVhVzFsYjNWMFBUMGlablZ1WTNScGIyNGlQM05sZEZScGJXVnZkWFE2Ym5Wc2JDeGlaVDEwZVhC'
    || 'bGIyWWdZMnhsWVhKVWFXMWxiM1YwUFQwaVpuVnVZM1JwYjI0aVAyTnNaV0Z5VkdsdFpXOTFkRHB1ZFd4c0xFSmxQWFI1Y0dWdlppQnpaWFJKYlcxbFpHbGhk'
    || 'R1U4SW5VaVAzTmxkRWx0YldWa2FXRjBaVHB1ZFd4c08zUjVjR1Z2WmlCdVlYWnBaMkYwYjNJOEluVWlKaVp1WVhacFoyRjBiM0l1YzJOb1pXUjFiR2x1WnlF'
    || 'OVBYWnZhV1FnTUNZbWJtRjJhV2RoZEc5eUxuTmphR1ZrZFd4cGJtY3VhWE5KYm5CMWRGQmxibVJwYm1jaFBUMTJiMmxrSURBbUptNWhkbWxuWVhSdmNpNXpZ'
    || 'MmhsWkhWc2FXNW5MbWx6U1c1d2RYUlFaVzVrYVc1bkxtSnBibVFvYm1GMmFXZGhkRzl5TG5OamFHVmtkV3hwYm1jcE8yWjFibU4wYVc5dUlGRmxLRklwZTJa'
    || 'dmNpaDJZWElnSkQxaktFY3BPeVFoUFQxdWRXeHNPeWw3YVdZb0pDNWpZV3hzWW1GamF6MDlQVzUxYkd3cGVDaEhLVHRsYkhObElHbG1LQ1F1YzNSaGNuUlVh'
    || 'VzFsUEQxU0tYZ29SeWtzSkM1emIzSjBTVzVrWlhnOUpDNWxlSEJwY21GMGFXOXVWR2x0WlN4a0tHb3NKQ2s3Wld4elpTQmljbVZoYXpza1BXTW9SeWw5Zlda'
    || 'MWJtTjBhVzl1SUdkbEtGSXBlMmxtS0dJOUlURXNVV1VvVWlrc0lVb3BhV1lvWXlocUtTRTlQVzUxYkd3cFNqMGhNQ3hHWlNoNlpTazdaV3h6Wlh0MllYSWdK'
    || 'RDFqS0VjcE95UWhQVDF1ZFd4c0ppWm1aU2huWlN3a0xuTjBZWEowVkdsdFpTMVNLWDE5Wm5WdVkzUnBiMjRnZW1Vb1Vpd2tLWHRLUFNFeExHSW1KaWhpUFNF'
    || 'eExHSmxLRkJsS1N4UVpUMHRNU2tzZFdVOUlUQTdkbUZ5SUUwOVZqdDBjbmw3Wm05eUtGRmxLQ1FwTEVZOVl5aHFLVHRHSVQwOWJuVnNiQ1ltS0NFb1JpNWxl'
    || 'SEJwY21GMGFXOXVWR2x0WlQ0a0tYeDhVaVltSVhSdUtDa3BPeWw3ZG1GeUlHZzlSaTVqWVd4c1ltRmphenRwWmloMGVYQmxiMllnYUQwOUltWjFibU4wYVc5'
    || 'dUlpbDdSaTVqWVd4c1ltRmphejF1ZFd4c0xGWTlSaTV3Y21sdmNtbDBlVXhsZG1Wc08zWmhjaUJmUFdnb1JpNWxlSEJwY21GMGFXOXVWR2x0WlR3OUpDazdK'
    || 'RDExTG5WdWMzUmhZbXhsWDI1dmR5Z3BMSFI1Y0dWdlppQmZQVDBpWm5WdVkzUnBiMjRpUDBZdVkyRnNiR0poWTJzOVh6cEdQVDA5WXlocUtTWW1lQ2hxS1N4'
    || 'UlpTZ2tLWDFsYkhObElIZ29haWs3UmoxaktHb3BmV2xtS0VZaFBUMXVkV3hzS1haaGNpQlhQU0V3TzJWc2MyVjdkbUZ5SUZFOVl5aEhLVHRSSVQwOWJuVnNi'
    || 'Q1ltWm1Vb1oyVXNVUzV6ZEdGeWRGUnBiV1V0SkNrc1Z6MGhNWDF5WlhSMWNtNGdWMzFtYVc1aGJHeDVlMFk5Ym5Wc2JDeFdQVTBzZFdVOUlURjlmWFpoY2lC'
    || 'M1pUMGhNU3hPWlQxdWRXeHNMRkJsUFMweExHUmxQVFVzYTNROUxURTdablZ1WTNScGIyNGdkRzRvS1h0eVpYUjFjbTRoS0hVdWRXNXpkR0ZpYkdWZmJtOTNL'
    || 'Q2t0YTNROFpHVXBmV1oxYm1OMGFXOXVJR2QwS0NsN2FXWW9UbVVoUFQxdWRXeHNLWHQyWVhJZ1VqMTFMblZ1YzNSaFlteGxYMjV2ZHlncE8ydDBQVkk3ZG1G'
    || 'eUlDUTlJVEE3ZEhKNWV5UTlUbVVvSVRBc1VpbDlabWx1WVd4c2VYc2tQMGRsS0NrNktIZGxQU0V4TEU1bFBXNTFiR3dwZlgxbGJITmxJSGRsUFNFeGZYWmhj'
    || 'aUJIWlR0cFppaDBlWEJsYjJZZ1FtVTlQU0ptZFc1amRHbHZiaUlwUjJVOVpuVnVZM1JwYjI0b0tYdENaU2huZENsOU8yVnNjMlVnYVdZb2RIbHdaVzltSUUx'
    || 'bGMzTmhaMlZEYUdGdWJtVnNQQ0oxSWlsN2RtRnlJSFYwUFc1bGR5Qk5aWE56WVdkbFEyaGhibTVsYkN4NWREMTFkQzV3YjNKME1qdDFkQzV3YjNKME1TNXZi'
    || 'bTFsYzNOaFoyVTlaM1FzUjJVOVpuVnVZM1JwYjI0b0tYdDVkQzV3YjNOMFRXVnpjMkZuWlNodWRXeHNLWDE5Wld4elpTQkhaVDFtZFc1amRHbHZiaWdwZTFr'
    || 'b1ozUXNNQ2w5TzJaMWJtTjBhVzl1SUVabEtGSXBlMDVsUFZJc2QyVjhmQ2gzWlQwaE1DeEhaU2dwS1gxbWRXNWpkR2x2YmlCbVpTaFNMQ1FwZTFCbFBWa29a'
    || 'blZ1WTNScGIyNG9LWHRTS0hVdWRXNXpkR0ZpYkdWZmJtOTNLQ2twZlN3a0tYMTFMblZ1YzNSaFlteGxYMGxrYkdWUWNtbHZjbWwwZVQwMUxIVXVkVzV6ZEdG'
    || 'aWJHVmZTVzF0WldScFlYUmxVSEpwYjNKcGRIazlNU3gxTG5WdWMzUmhZbXhsWDB4dmQxQnlhVzl5YVhSNVBUUXNkUzUxYm5OMFlXSnNaVjlPYjNKdFlXeFFj'
    || 'bWx2Y21sMGVUMHpMSFV1ZFc1emRHRmliR1ZmVUhKdlptbHNhVzVuUFc1MWJHd3NkUzUxYm5OMFlXSnNaVjlWYzJWeVFteHZZMnRwYm1kUWNtbHZjbWwwZVQw'
    || 'eUxIVXVkVzV6ZEdGaWJHVmZZMkZ1WTJWc1EyRnNiR0poWTJzOVpuVnVZM1JwYjI0b1VpbDdVaTVqWVd4c1ltRmphejF1ZFd4c2ZTeDFMblZ1YzNSaFlteGxY'
    || 'Mk52Ym5ScGJuVmxSWGhsWTNWMGFXOXVQV1oxYm1OMGFXOXVLQ2w3U254OGRXVjhmQ2hLUFNFd0xFWmxLSHBsS1NsOUxIVXVkVzV6ZEdGaWJHVmZabTl5WTJW'
    || 'R2NtRnRaVkpoZEdVOVpuVnVZM1JwYjI0b1VpbDdNRDVTZkh3eE1qVThVajlqYjI1emIyeGxMbVZ5Y205eUtDSm1iM0pqWlVaeVlXMWxVbUYwWlNCMFlXdGxj'
    || 'eUJoSUhCdmMybDBhWFpsSUdsdWRDQmlaWFIzWldWdUlEQWdZVzVrSURFeU5Td2dabTl5WTJsdVp5Qm1jbUZ0WlNCeVlYUmxjeUJvYVdkb1pYSWdkR2hoYmlB'
    || 'eE1qVWdabkJ6SUdseklHNXZkQ0J6ZFhCd2IzSjBaV1FpS1Rwa1pUMHdQRkkvVFdGMGFDNW1iRzl2Y2lneFpUTXZVaWs2Tlgwc2RTNTFibk4wWVdKc1pWOW5a'
    || 'WFJEZFhKeVpXNTBVSEpwYjNKcGRIbE1aWFpsYkQxbWRXNWpkR2x2YmlncGUzSmxkSFZ5YmlCV2ZTeDFMblZ1YzNSaFlteGxYMmRsZEVacGNuTjBRMkZzYkdK'
    || 'aFkydE9iMlJsUFdaMWJtTjBhVzl1S0NsN2NtVjBkWEp1SUdNb2FpbDlMSFV1ZFc1emRHRmliR1ZmYm1WNGREMW1kVzVqZEdsdmJpaFNLWHR6ZDJsMFkyZ29W'
    || 'aWw3WTJGelpTQXhPbU5oYzJVZ01qcGpZWE5sSURNNmRtRnlJQ1E5TXp0aWNtVmhhenRrWldaaGRXeDBPaVE5Vm4xMllYSWdUVDFXTzFZOUpEdDBjbmw3Y21W'
    || 'MGRYSnVJRklvS1gxbWFXNWhiR3g1ZTFZOVRYMTlMSFV1ZFc1emRHRmliR1ZmY0dGMWMyVkZlR1ZqZFhScGIyNDlablZ1WTNScGIyNG9LWHQ5TEhVdWRXNXpk'
    || 'R0ZpYkdWZmNtVnhkV1Z6ZEZCaGFXNTBQV1oxYm1OMGFXOXVLQ2w3ZlN4MUxuVnVjM1JoWW14bFgzSjFibGRwZEdoUWNtbHZjbWwwZVQxbWRXNWpkR2x2Ymlo'
    || 'U0xDUXBlM04zYVhSamFDaFNLWHRqWVhObElERTZZMkZ6WlNBeU9tTmhjMlVnTXpwallYTmxJRFE2WTJGelpTQTFPbUp5WldGck8yUmxabUYxYkhRNlVqMHpm'
    || 'WFpoY2lCTlBWWTdWajFTTzNSeWVYdHlaWFIxY200Z0pDZ3BmV1pwYm1Gc2JIbDdWajFOZlgwc2RTNTFibk4wWVdKc1pWOXpZMmhsWkhWc1pVTmhiR3hpWVdO'
    || 'clBXWjFibU4wYVc5dUtGSXNKQ3hOS1h0MllYSWdhRDExTG5WdWMzUmhZbXhsWDI1dmR5Z3BPM04zYVhSamFDaDBlWEJsYjJZZ1RUMDlJbTlpYW1WamRDSW1K'
    || 'azBoUFQxdWRXeHNQeWhOUFUwdVpHVnNZWGtzVFQxMGVYQmxiMllnVFQwOUltNTFiV0psY2lJbUpqQThUVDlvSzAwNmFDazZUVDFvTEZJcGUyTmhjMlVnTVRw'
    || 'MllYSWdYejB0TVR0aWNtVmhhenRqWVhObElESTZYejB5TlRBN1luSmxZV3M3WTJGelpTQTFPbDg5TVRBM016YzBNVGd5TXp0aWNtVmhhenRqWVhObElEUTZY'
    || 'ejB4WlRRN1luSmxZV3M3WkdWbVlYVnNkRHBmUFRWbE0zMXlaWFIxY200Z1h6MU5LMThzVWoxN2FXUTZUQ3NyTEdOaGJHeGlZV05yT2lRc2NISnBiM0pwZEhs'
    || 'TVpYWmxiRHBTTEhOMFlYSjBWR2x0WlRwTkxHVjRjR2x5WVhScGIyNVVhVzFsT2w4c2MyOXlkRWx1WkdWNE9pMHhmU3hOUG1nL0tGSXVjMjl5ZEVsdVpHVjRQ'
    || 'VTBzWkNoSExGSXBMR01vYWlrOVBUMXVkV3hzSmlaU1BUMDlZeWhIS1NZbUtHSS9LR0psS0ZCbEtTeFFaVDB0TVNrNllqMGhNQ3htWlNoblpTeE5MV2dwS1Nr'
    || 'NktGSXVjMjl5ZEVsdVpHVjRQVjhzWkNocUxGSXBMRXA4ZkhWbGZId29TajBoTUN4R1pTaDZaU2twS1N4U2ZTeDFMblZ1YzNSaFlteGxYM05vYjNWc1pGbHBa'
    || 'V3hrUFhSdUxIVXVkVzV6ZEdGaWJHVmZkM0poY0VOaGJHeGlZV05yUFdaMWJtTjBhVzl1S0ZJcGUzWmhjaUFrUFZZN2NtVjBkWEp1SUdaMWJtTjBhVzl1S0Ns'
    || 'N2RtRnlJRTA5Vmp0V1BTUTdkSEo1ZTNKbGRIVnliaUJTTG1Gd2NHeDVLSFJvYVhNc1lYSm5kVzFsYm5SektYMW1hVzVoYkd4NWUxWTlUWDE5ZlgwcEtFdHNL'
    || 'U2tzUzJ4OWRtRnlJR1Z6TzJaMWJtTjBhVzl1SUdaaktDbDdjbVYwZFhKdUlHVnpmSHdvWlhNOU1TeEhiQzVsZUhCdmNuUnpQV1JqS0NrcExFZHNMbVY0Y0c5'
    || 'eWRITjlMeW9xQ2lBcUlFQnNhV05sYm5ObElGSmxZV04wQ2lBcUlISmxZV04wTFdSdmJTNXdjbTlrZFdOMGFXOXVMbTFwYmk1cWN3b2dLZ29nS2lCRGIzQjVj'
    || 'bWxuYUhRZ0tHTXBJRVpoWTJWaWIyOXJMQ0JKYm1NdUlHRnVaQ0JwZEhNZ1lXWm1hV3hwWVhSbGN5NEtJQ29LSUNvZ1ZHaHBjeUJ6YjNWeVkyVWdZMjlrWlNC'
    || 'cGN5QnNhV05sYm5ObFpDQjFibVJsY2lCMGFHVWdUVWxVSUd4cFkyVnVjMlVnWm05MWJtUWdhVzRnZEdobENpQXFJRXhKUTBWT1UwVWdabWxzWlNCcGJpQjBh'
    || 'R1VnY205dmRDQmthWEpsWTNSdmNua2diMllnZEdocGN5QnpiM1Z5WTJVZ2RISmxaUzRLSUNvdmRtRnlJSFJ6TzJaMWJtTjBhVzl1SUhCaktDbDdhV1lvZEhN'
    || 'cGNtVjBkWEp1SUVSbE8zUnpQVEU3ZG1GeUlIVTlWMndvS1N4a1BXWmpLQ2s3Wm5WdVkzUnBiMjRnWXlobEtYdG1iM0lvZG1GeUlIUTlJbWgwZEhCek9pOHZj'
    || 'bVZoWTNScWN5NXZjbWN2Wkc5amN5OWxjbkp2Y2kxa1pXTnZaR1Z5TG1oMGJXdy9hVzUyWVhKcFlXNTBQU0lyWlN4dVBURTdianhoY21kMWJXVnVkSE11YkdW'
    || 'dVozUm9PMjRyS3lsMEt6MGlKbUZ5WjNOYlhUMGlLMlZ1WTI5a1pWVlNTVU52YlhCdmJtVnVkQ2hoY21kMWJXVnVkSE5iYmwwcE8zSmxkSFZ5YmlKTmFXNXBa'
    || 'bWxsWkNCU1pXRmpkQ0JsY25KdmNpQWpJaXRsS3lJN0lIWnBjMmwwSUNJcmRDc2lJR1p2Y2lCMGFHVWdablZzYkNCdFpYTnpZV2RsSUc5eUlIVnpaU0IwYUdV'
    || 'Z2JtOXVMVzFwYm1sbWFXVmtJR1JsZGlCbGJuWnBjbTl1YldWdWRDQm1iM0lnWm5Wc2JDQmxjbkp2Y25NZ1lXNWtJR0ZrWkdsMGFXOXVZV3dnYUdWc2NHWjFi'
    || 'Q0IzWVhKdWFXNW5jeTRpZlhaaGNpQjRQVzVsZHlCVFpYUXNSVDE3ZlR0bWRXNWpkR2x2YmlCVUtHVXNkQ2w3ZVNobExIUXBMSGtvWlNzaVEyRndkSFZ5WlNJ'
    || 'c2RDbDlablZ1WTNScGIyNGdlU2hsTEhRcGUyWnZjaWhGVzJWZFBYUXNaVDB3TzJVOGRDNXNaVzVuZEdnN1pTc3JLWGd1WVdSa0tIUmJaVjBwZlhaaGNpQk9Q'
    || 'U0VvZEhsd1pXOW1JSGRwYm1SdmR6NGlkU0o4ZkhSNWNHVnZaaUIzYVc1a2IzY3VaRzlqZFcxbGJuUStJblVpZkh4MGVYQmxiMllnZDJsdVpHOTNMbVJ2WTNW'
    || 'dFpXNTBMbU55WldGMFpVVnNaVzFsYm5RK0luVWlLU3hxUFU5aWFtVmpkQzV3Y205MGIzUjVjR1V1YUdGelQzZHVVSEp2Y0dWeWRIa3NSejB2WGxzNlFTMWFY'
    || 'MkV0ZWx4MU1EQkRNQzFjZFRBd1JEWmNkVEF3UkRndFhIVXdNRVkyWEhVd01FWTRMVngxTURKR1JseDFNRE0zTUMxY2RUQXpOMFJjZFRBek4wWXRYSFV4Umta'
    || 'R1hIVXlNREJETFZ4MU1qQXdSRngxTWpBM01DMWNkVEl4T0VaY2RUSkRNREF0WEhVeVJrVkdYSFV6TURBeExWeDFSRGRHUmx4MVJqa3dNQzFjZFVaRVEwWmNk'
    || 'VVpFUmpBdFhIVkdSa1pFWFZzNlFTMWFYMkV0ZWx4MU1EQkRNQzFjZFRBd1JEWmNkVEF3UkRndFhIVXdNRVkyWEhVd01FWTRMVngxTURKR1JseDFNRE0zTUMx'
    || 'Y2RUQXpOMFJjZFRBek4wWXRYSFV4UmtaR1hIVXlNREJETFZ4MU1qQXdSRngxTWpBM01DMWNkVEl4T0VaY2RUSkRNREF0WEhVeVJrVkdYSFV6TURBeExWeDFS'
    || 'RGRHUmx4MVJqa3dNQzFjZFVaRVEwWmNkVVpFUmpBdFhIVkdSa1pFWEMwdU1DMDVYSFV3TUVJM1hIVXdNekF3TFZ4MU1ETTJSbHgxTWpBelJpMWNkVEl3TkRC'
    || 'ZEtpUXZMRXc5ZTMwc1JqMTdmVHRtZFc1amRHbHZiaUJXS0dVcGUzSmxkSFZ5YmlCcUxtTmhiR3dvUml4bEtUOGhNRHBxTG1OaGJHd29UQ3hsS1Q4aE1UcEhM'
    || 'blJsYzNRb1pTay9SbHRsWFQwaE1Eb29URnRsWFQwaE1Dd2hNU2w5Wm5WdVkzUnBiMjRnZFdVb1pTeDBMRzRzY2lsN2FXWW9iaUU5UFc1MWJHd21KbTR1ZEhs'
    || 'd1pUMDlQVEFwY21WMGRYSnVJVEU3YzNkcGRHTm9LSFI1Y0dWdlppQjBLWHRqWVhObEltWjFibU4wYVc5dUlqcGpZWE5sSW5ONWJXSnZiQ0k2Y21WMGRYSnVJ'
    || 'VEE3WTJGelpTSmliMjlzWldGdUlqcHlaWFIxY200Z2NqOGhNVHB1SVQwOWJuVnNiRDhoYmk1aFkyTmxjSFJ6UW05dmJHVmhibk02S0dVOVpTNTBiMHh2ZDJW'
    || 'eVEyRnpaU2dwTG5Oc2FXTmxLREFzTlNrc1pTRTlQU0prWVhSaExTSW1KbVVoUFQwaVlYSnBZUzBpS1R0a1pXWmhkV3gwT25KbGRIVnliaUV4ZlgxbWRXNWpk'
    || 'R2x2YmlCS0tHVXNkQ3h1TEhJcGUybG1LSFE5UFQxdWRXeHNmSHgwZVhCbGIyWWdkRDRpZFNKOGZIVmxLR1VzZEN4dUxISXBLWEpsZEhWeWJpRXdPMmxtS0hJ'
    || 'cGNtVjBkWEp1SVRFN2FXWW9iaUU5UFc1MWJHd3BjM2RwZEdOb0tHNHVkSGx3WlNsN1kyRnpaU0F6T25KbGRIVnliaUYwTzJOaGMyVWdORHB5WlhSMWNtNGdk'
    || 'RDA5UFNFeE8yTmhjMlVnTlRweVpYUjFjbTRnYVhOT1lVNG9kQ2s3WTJGelpTQTJPbkpsZEhWeWJpQnBjMDVoVGloMEtYeDhNVDUwZlhKbGRIVnliaUV4Zlda'
    || 'MWJtTjBhVzl1SUdJb1pTeDBMRzRzY2l4c0xHa3NjeWw3ZEdocGN5NWhZMk5sY0hSelFtOXZiR1ZoYm5NOWREMDlQVEo4ZkhROVBUMHpmSHgwUFQwOU5DeDBh'
    || 'R2x6TG1GMGRISnBZblYwWlU1aGJXVTljaXgwYUdsekxtRjBkSEpwWW5WMFpVNWhiV1Z6Y0dGalpUMXNMSFJvYVhNdWJYVnpkRlZ6WlZCeWIzQmxjblI1UFc0'
    || 'c2RHaHBjeTV3Y205d1pYSjBlVTVoYldVOVpTeDBhR2x6TG5SNWNHVTlkQ3gwYUdsekxuTmhibWwwYVhwbFZWSk1QV2tzZEdocGN5NXlaVzF2ZG1WRmJYQjBl'
    || 'Vk4wY21sdVp6MXpmWFpoY2lCWlBYdDlPeUpqYUdsc1pISmxiaUJrWVc1blpYSnZkWE5zZVZObGRFbHVibVZ5U0ZSTlRDQmtaV1poZFd4MFZtRnNkV1VnWkdW'
    || 'bVlYVnNkRU5vWldOclpXUWdhVzV1WlhKSVZFMU1JSE4xY0hCeVpYTnpRMjl1ZEdWdWRFVmthWFJoWW14bFYyRnlibWx1WnlCemRYQndjbVZ6YzBoNVpISmhk'
    || 'R2x2YmxkaGNtNXBibWNnYzNSNWJHVWlMbk53YkdsMEtDSWdJaWt1Wm05eVJXRmphQ2htZFc1amRHbHZiaWhsS1h0WlcyVmRQVzVsZHlCaUtHVXNNQ3doTVN4'
    || 'bExHNTFiR3dzSVRFc0lURXBmU2tzVzFzaVlXTmpaWEIwUTJoaGNuTmxkQ0lzSW1GalkyVndkQzFqYUdGeWMyVjBJbDBzV3lKamJHRnpjMDVoYldVaUxDSmpi'
    || 'R0Z6Y3lKZExGc2lhSFJ0YkVadmNpSXNJbVp2Y2lKZExGc2lhSFIwY0VWeGRXbDJJaXdpYUhSMGNDMWxjWFZwZGlKZFhTNW1iM0pGWVdOb0tHWjFibU4wYVc5'
    || 'dUtHVXBlM1poY2lCMFBXVmJNRjA3V1Z0MFhUMXVaWGNnWWloMExERXNJVEVzWlZzeFhTeHVkV3hzTENFeExDRXhLWDBwTEZzaVkyOXVkR1Z1ZEVWa2FYUmhZ'
    || 'bXhsSWl3aVpISmhaMmRoWW14bElpd2ljM0JsYkd4RGFHVmpheUlzSW5aaGJIVmxJbDB1Wm05eVJXRmphQ2htZFc1amRHbHZiaWhsS1h0WlcyVmRQVzVsZHlC'
    || 'aUtHVXNNaXdoTVN4bExuUnZURzkzWlhKRFlYTmxLQ2tzYm5Wc2JDd2hNU3doTVNsOUtTeGJJbUYxZEc5U1pYWmxjbk5sSWl3aVpYaDBaWEp1WVd4U1pYTnZk'
    || 'WEpqWlhOU1pYRjFhWEpsWkNJc0ltWnZZM1Z6WVdKc1pTSXNJbkJ5WlhObGNuWmxRV3h3YUdFaVhTNW1iM0pGWVdOb0tHWjFibU4wYVc5dUtHVXBlMWxiWlYw'
    || 'OWJtVjNJR0lvWlN3eUxDRXhMR1VzYm5Wc2JDd2hNU3doTVNsOUtTd2lZV3hzYjNkR2RXeHNVMk55WldWdUlHRnplVzVqSUdGMWRHOUdiMk4xY3lCaGRYUnZV'
    || 'R3hoZVNCamIyNTBjbTlzY3lCa1pXWmhkV3gwSUdSbFptVnlJR1JwYzJGaWJHVmtJR1JwYzJGaWJHVlFhV04wZFhKbFNXNVFhV04wZFhKbElHUnBjMkZpYkdW'
    || 'U1pXMXZkR1ZRYkdGNVltRmpheUJtYjNKdFRtOVdZV3hwWkdGMFpTQm9hV1JrWlc0Z2JHOXZjQ0J1YjAxdlpIVnNaU0J1YjFaaGJHbGtZWFJsSUc5d1pXNGdj'
    || 'R3hoZVhOSmJteHBibVVnY21WaFpFOXViSGtnY21WeGRXbHlaV1FnY21WMlpYSnpaV1FnYzJOdmNHVmtJSE5sWVcxc1pYTnpJR2wwWlcxVFkyOXdaU0l1YzNC'
    || 'c2FYUW9JaUFpS1M1bWIzSkZZV05vS0daMWJtTjBhVzl1S0dVcGUxbGJaVjA5Ym1WM0lHSW9aU3d6TENFeExHVXVkRzlNYjNkbGNrTmhjMlVvS1N4dWRXeHNM'
    || 'Q0V4TENFeEtYMHBMRnNpWTJobFkydGxaQ0lzSW0xMWJIUnBjR3hsSWl3aWJYVjBaV1FpTENKelpXeGxZM1JsWkNKZExtWnZja1ZoWTJnb1puVnVZM1JwYjI0'
    || 'b1pTbDdXVnRsWFQxdVpYY2dZaWhsTERNc0lUQXNaU3h1ZFd4c0xDRXhMQ0V4S1gwcExGc2lZMkZ3ZEhWeVpTSXNJbVJ2ZDI1c2IyRmtJbDB1Wm05eVJXRmph'
    || 'Q2htZFc1amRHbHZiaWhsS1h0WlcyVmRQVzVsZHlCaUtHVXNOQ3doTVN4bExHNTFiR3dzSVRFc0lURXBmU2tzV3lKamIyeHpJaXdpY205M2N5SXNJbk5wZW1V'
    || 'aUxDSnpjR0Z1SWwwdVptOXlSV0ZqYUNobWRXNWpkR2x2YmlobEtYdFpXMlZkUFc1bGR5QmlLR1VzTml3aE1TeGxMRzUxYkd3c0lURXNJVEVwZlNrc1d5Snli'
    || 'M2RUY0dGdUlpd2ljM1JoY25RaVhTNW1iM0pGWVdOb0tHWjFibU4wYVc5dUtHVXBlMWxiWlYwOWJtVjNJR0lvWlN3MUxDRXhMR1V1ZEc5TWIzZGxja05oYzJV'
    || 'b0tTeHVkV3hzTENFeExDRXhLWDBwTzNaaGNpQmlaVDB2VzF3dE9sMG9XMkV0ZWwwcEwyYzdablZ1WTNScGIyNGdRbVVvWlNsN2NtVjBkWEp1SUdWYk1WMHVk'
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
    || 'R3hwYm1zZ2VDMW9aV2xuYUhRaUxuTndiR2wwS0NJZ0lpa3VabTl5UldGamFDaG1kVzVqZEdsdmJpaGxLWHQyWVhJZ2REMWxMbkpsY0d4aFkyVW9ZbVVzUW1V'
    || 'cE8xbGJkRjA5Ym1WM0lHSW9kQ3d4TENFeExHVXNiblZzYkN3aE1Td2hNU2w5S1N3aWVHeHBibXM2WVdOMGRXRjBaU0I0YkdsdWF6cGhjbU55YjJ4bElIaHNh'
    || 'VzVyT25KdmJHVWdlR3hwYm1zNmMyaHZkeUI0YkdsdWF6cDBhWFJzWlNCNGJHbHVhenAwZVhCbElpNXpjR3hwZENnaUlDSXBMbVp2Y2tWaFkyZ29ablZ1WTNS'
    || 'cGIyNG9aU2w3ZG1GeUlIUTlaUzV5WlhCc1lXTmxLR0psTEVKbEtUdFpXM1JkUFc1bGR5QmlLSFFzTVN3aE1TeGxMQ0pvZEhSd09pOHZkM2QzTG5jekxtOXla'
    || 'eTh4T1RrNUwzaHNhVzVySWl3aE1Td2hNU2w5S1N4YkluaHRiRHBpWVhObElpd2llRzFzT214aGJtY2lMQ0o0Yld3NmMzQmhZMlVpWFM1bWIzSkZZV05vS0da'
    || 'MWJtTjBhVzl1S0dVcGUzWmhjaUIwUFdVdWNtVndiR0ZqWlNoaVpTeENaU2s3V1Z0MFhUMXVaWGNnWWloMExERXNJVEVzWlN3aWFIUjBjRG92TDNkM2R5NTNN'
    || 'eTV2Y21jdldFMU1MekU1T1RndmJtRnRaWE53WVdObElpd2hNU3doTVNsOUtTeGJJblJoWWtsdVpHVjRJaXdpWTNKdmMzTlBjbWxuYVc0aVhTNW1iM0pGWVdO'
    || 'b0tHWjFibU4wYVc5dUtHVXBlMWxiWlYwOWJtVjNJR0lvWlN3eExDRXhMR1V1ZEc5TWIzZGxja05oYzJVb0tTeHVkV3hzTENFeExDRXhLWDBwTEZrdWVHeHBi'
    || 'bXRJY21WbVBXNWxkeUJpS0NKNGJHbHVhMGh5WldZaUxERXNJVEVzSW5oc2FXNXJPbWh5WldZaUxDSm9kSFJ3T2k4dmQzZDNMbmN6TG05eVp5OHhPVGs1TDNo'
    || 'c2FXNXJJaXdoTUN3aE1Ta3NXeUp6Y21NaUxDSm9jbVZtSWl3aVlXTjBhVzl1SWl3aVptOXliVUZqZEdsdmJpSmRMbVp2Y2tWaFkyZ29ablZ1WTNScGIyNG9a'
    || 'U2w3V1Z0bFhUMXVaWGNnWWlobExERXNJVEVzWlM1MGIweHZkMlZ5UTJGelpTZ3BMRzUxYkd3c0lUQXNJVEFwZlNrN1puVnVZM1JwYjI0Z1VXVW9aU3gwTEc0'
    || 'c2NpbDdkbUZ5SUd3OVdTNW9ZWE5QZDI1UWNtOXdaWEowZVNoMEtUOVpXM1JkT201MWJHdzdLR3doUFQxdWRXeHNQMnd1ZEhsd1pTRTlQVEE2Y254OElTZ3lQ'
    || 'SFF1YkdWdVozUm9LWHg4ZEZzd1hTRTlQU0p2SWlZbWRGc3dYU0U5UFNKUElueDhkRnN4WFNFOVBTSnVJaVltZEZzeFhTRTlQU0pPSWlrbUppaEtLSFFzYml4'
    || 'c0xISXBKaVlvYmoxdWRXeHNLU3h5Zkh4c1BUMDliblZzYkQ5V0tIUXBKaVlvYmowOVBXNTFiR3cvWlM1eVpXMXZkbVZCZEhSeWFXSjFkR1VvZENrNlpTNXpa'
    || 'WFJCZEhSeWFXSjFkR1VvZEN3aUlpdHVLU2s2YkM1dGRYTjBWWE5sVUhKdmNHVnlkSGsvWlZ0c0xuQnliM0JsY25SNVRtRnRaVjA5YmowOVBXNTFiR3cvYkM1'
    || 'MGVYQmxQVDA5TXo4aE1Ub2lJanB1T2loMFBXd3VZWFIwY21saWRYUmxUbUZ0WlN4eVBXd3VZWFIwY21saWRYUmxUbUZ0WlhOd1lXTmxMRzQ5UFQxdWRXeHNQ'
    || 'MlV1Y21WdGIzWmxRWFIwY21saWRYUmxLSFFwT2loc1BXd3VkSGx3WlN4dVBXdzlQVDB6Zkh4c1BUMDlOQ1ltYmowOVBTRXdQeUlpT2lJaUsyNHNjajlsTG5O'
    || 'bGRFRjBkSEpwWW5WMFpVNVRLSElzZEN4dUtUcGxMbk5sZEVGMGRISnBZblYwWlNoMExHNHBLU2twZlhaaGNpQm5aVDExTGw5ZlUwVkRVa1ZVWDBsT1ZFVlNU'
    || 'a0ZNVTE5RVQxOU9UMVJmVlZORlgwOVNYMWxQVlY5WFNVeE1YMEpGWDBaSlVrVkVMSHBsUFZONWJXSnZiQzVtYjNJb0luSmxZV04wTG1Wc1pXMWxiblFpS1N4'
    || 'M1pUMVRlVzFpYjJ3dVptOXlLQ0p5WldGamRDNXdiM0owWVd3aUtTeE9aVDFUZVcxaWIyd3VabTl5S0NKeVpXRmpkQzVtY21GbmJXVnVkQ0lwTEZCbFBWTjVi'
    || 'V0p2YkM1bWIzSW9JbkpsWVdOMExuTjBjbWxqZEY5dGIyUmxJaWtzWkdVOVUzbHRZbTlzTG1admNpZ2ljbVZoWTNRdWNISnZabWxzWlhJaUtTeHJkRDFUZVcx'
    || 'aWIyd3VabTl5S0NKeVpXRmpkQzV3Y205MmFXUmxjaUlwTEhSdVBWTjViV0p2YkM1bWIzSW9JbkpsWVdOMExtTnZiblJsZUhRaUtTeG5kRDFUZVcxaWIyd3Va'
    || 'bTl5S0NKeVpXRmpkQzVtYjNKM1lYSmtYM0psWmlJcExFZGxQVk41YldKdmJDNW1iM0lvSW5KbFlXTjBMbk4xYzNCbGJuTmxJaWtzZFhROVUzbHRZbTlzTG1a'
    || 'dmNpZ2ljbVZoWTNRdWMzVnpjR1Z1YzJWZmJHbHpkQ0lwTEhsMFBWTjViV0p2YkM1bWIzSW9JbkpsWVdOMExtMWxiVzhpS1N4R1pUMVRlVzFpYjJ3dVptOXlL'
    || 'Q0p5WldGamRDNXNZWHA1SWlrc1ptVTlVM2x0WW05c0xtWnZjaWdpY21WaFkzUXViMlptYzJOeVpXVnVJaWtzVWoxVGVXMWliMnd1YVhSbGNtRjBiM0k3Wm5W'
    || 'dVkzUnBiMjRnSkNobEtYdHlaWFIxY200Z1pUMDlQVzUxYkd4OGZIUjVjR1Z2WmlCbElUMGliMkpxWldOMElqOXVkV3hzT2lobFBWSW1KbVZiVWwxOGZHVmJJ'
    || 'a0JBYVhSbGNtRjBiM0lpWFN4MGVYQmxiMllnWlQwOUltWjFibU4wYVc5dUlqOWxPbTUxYkd3cGZYWmhjaUJOUFU5aWFtVmpkQzVoYzNOcFoyNHNhRHRtZFc1'
    || 'amRHbHZiaUJmS0dVcGUybG1LR2c5UFQxMmIybGtJREFwZEhKNWUzUm9jbTkzSUVWeWNtOXlLQ2w5WTJGMFkyZ29iaWw3ZG1GeUlIUTliaTV6ZEdGamF5NTBj'
    || 'bWx0S0NrdWJXRjBZMmdvTDF4dUtDQXFLR0YwSUNrL0tTOHBPMmc5ZENZbWRGc3hYWHg4SWlKOWNtVjBkWEp1WUFwZ0syZ3JaWDEyWVhJZ1Z6MGhNVHRtZFc1'
    || 'amRHbHZiaUJSS0dVc2RDbDdhV1lvSVdWOGZGY3BjbVYwZFhKdUlpSTdWejBoTUR0MllYSWdiajFGY25KdmNpNXdjbVZ3WVhKbFUzUmhZMnRVY21GalpUdEZj'
    || 'bkp2Y2k1d2NtVndZWEpsVTNSaFkydFVjbUZqWlQxMmIybGtJREE3ZEhKNWUybG1LSFFwYVdZb2REMW1kVzVqZEdsdmJpZ3BlM1JvY205M0lFVnljbTl5S0Ns'
    || 'OUxFOWlhbVZqZEM1a1pXWnBibVZRY205d1pYSjBlU2gwTG5CeWIzUnZkSGx3WlN3aWNISnZjSE1pTEh0elpYUTZablZ1WTNScGIyNG9LWHQwYUhKdmR5QkZj'
    || 'bkp2Y2lncGZYMHBMSFI1Y0dWdlppQlNaV1pzWldOMFBUMGliMkpxWldOMElpWW1VbVZtYkdWamRDNWpiMjV6ZEhKMVkzUXBlM1J5ZVh0U1pXWnNaV04wTG1O'
    || 'dmJuTjBjblZqZENoMExGdGRLWDFqWVhSamFDaG5LWHQyWVhJZ2NqMW5mVkpsWm14bFkzUXVZMjl1YzNSeWRXTjBLR1VzVzEwc2RDbDlaV3h6Wlh0MGNubDdk'
    || 'QzVqWVd4c0tDbDlZMkYwWTJnb1p5bDdjajFuZldVdVkyRnNiQ2gwTG5CeWIzUnZkSGx3WlNsOVpXeHpaWHQwY25sN2RHaHliM2NnUlhKeWIzSW9LWDFqWVhS'
    || 'amFDaG5LWHR5UFdkOVpTZ3BmWDFqWVhSamFDaG5LWHRwWmlobkppWnlKaVowZVhCbGIyWWdaeTV6ZEdGamF6MDlJbk4wY21sdVp5SXBlMlp2Y2loMllYSWdi'
    || 'RDFuTG5OMFlXTnJMbk53YkdsMEtHQUtZQ2tzYVQxeUxuTjBZV05yTG5Od2JHbDBLR0FLWUNrc2N6MXNMbXhsYm1kMGFDMHhMR0U5YVM1c1pXNW5kR2d0TVRz'
    || 'eFBEMXpKaVl3UEQxaEppWnNXM05kSVQwOWFWdGhYVHNwWVMwdE8yWnZjaWc3TVR3OWN5WW1NRHc5WVR0ekxTMHNZUzB0S1dsbUtHeGJjMTBoUFQxcFcyRmRL'
    || 'WHRwWmloeklUMDlNWHg4WVNFOVBURXBaRzhnYVdZb2N5MHRMR0V0TFN3d1BtRjhmR3hiYzEwaFBUMXBXMkZkS1h0MllYSWdaajFnQ21BcmJGdHpYUzV5WlhC'
    || 'c1lXTmxLQ0lnWVhRZ2JtVjNJQ0lzSWlCaGRDQWlLVHR5WlhSMWNtNGdaUzVrYVhOd2JHRjVUbUZ0WlNZbVppNXBibU5zZFdSbGN5Z2lQR0Z1YjI1NWJXOTFj'
    || 'ejRpS1NZbUtHWTlaaTV5WlhCc1lXTmxLQ0k4WVc1dmJubHRiM1Z6UGlJc1pTNWthWE53YkdGNVRtRnRaU2twTEdaOWQyaHBiR1VvTVR3OWN5WW1NRHc5WVNr'
    || 'N1luSmxZV3Q5ZlgxbWFXNWhiR3g1ZTFjOUlURXNSWEp5YjNJdWNISmxjR0Z5WlZOMFlXTnJWSEpoWTJVOWJuMXlaWFIxY200b1pUMWxQMlV1WkdsemNHeGhl'
    || 'VTVoYldWOGZHVXVibUZ0WlRvaUlpay9YeWhsS1RvaUluMW1kVzVqZEdsdmJpQllLR1VwZTNOM2FYUmphQ2hsTG5SaFp5bDdZMkZ6WlNBMU9uSmxkSFZ5YmlC'
    || 'ZktHVXVkSGx3WlNrN1kyRnpaU0F4TmpweVpYUjFjbTRnWHlnaVRHRjZlU0lwTzJOaGMyVWdNVE02Y21WMGRYSnVJRjhvSWxOMWMzQmxibk5sSWlrN1kyRnpa'
    || 'U0F4T1RweVpYUjFjbTRnWHlnaVUzVnpjR1Z1YzJWTWFYTjBJaWs3WTJGelpTQXdPbU5oYzJVZ01qcGpZWE5sSURFMU9uSmxkSFZ5YmlCbFBWRW9aUzUwZVhC'
    || 'bExDRXhLU3hsTzJOaGMyVWdNVEU2Y21WMGRYSnVJR1U5VVNobExuUjVjR1V1Y21WdVpHVnlMQ0V4S1N4bE8yTmhjMlVnTVRweVpYUjFjbTRnWlQxUktHVXVk'
    || 'SGx3WlN3aE1Da3NaVHRrWldaaGRXeDBPbkpsZEhWeWJpSWlmWDFtZFc1amRHbHZiaUJhS0dVcGUybG1LR1U5UFc1MWJHd3BjbVYwZFhKdUlHNTFiR3c3YVdZ'
    || 'b2RIbHdaVzltSUdVOVBTSm1kVzVqZEdsdmJpSXBjbVYwZFhKdUlHVXVaR2x6Y0d4aGVVNWhiV1Y4ZkdVdWJtRnRaWHg4Ym5Wc2JEdHBaaWgwZVhCbGIyWWda'
    || 'VDA5SW5OMGNtbHVaeUlwY21WMGRYSnVJR1U3YzNkcGRHTm9LR1VwZTJOaGMyVWdUbVU2Y21WMGRYSnVJa1p5WVdkdFpXNTBJanRqWVhObElIZGxPbkpsZEhW'
    || 'eWJpSlFiM0owWVd3aU8yTmhjMlVnWkdVNmNtVjBkWEp1SWxCeWIyWnBiR1Z5SWp0allYTmxJRkJsT25KbGRIVnliaUpUZEhKcFkzUk5iMlJsSWp0allYTmxJ'
    || 'RWRsT25KbGRIVnliaUpUZFhOd1pXNXpaU0k3WTJGelpTQjFkRHB5WlhSMWNtNGlVM1Z6Y0dWdWMyVk1hWE4wSW4xcFppaDBlWEJsYjJZZ1pUMDlJbTlpYW1W'
    || 'amRDSXBjM2RwZEdOb0tHVXVKQ1IwZVhCbGIyWXBlMk5oYzJVZ2RHNDZjbVYwZFhKdUtHVXVaR2x6Y0d4aGVVNWhiV1Y4ZkNKRGIyNTBaWGgwSWlrcklpNURi'
    || 'MjV6ZFcxbGNpSTdZMkZ6WlNCcmREcHlaWFIxY200b1pTNWZZMjl1ZEdWNGRDNWthWE53YkdGNVRtRnRaWHg4SWtOdmJuUmxlSFFpS1NzaUxsQnliM1pwWkdW'
    || 'eUlqdGpZWE5sSUdkME9uWmhjaUIwUFdVdWNtVnVaR1Z5TzNKbGRIVnliaUJsUFdVdVpHbHpjR3hoZVU1aGJXVXNaWHg4S0dVOWRDNWthWE53YkdGNVRtRnRa'
    || 'WHg4ZEM1dVlXMWxmSHdpSWl4bFBXVWhQVDBpSWo4aVJtOXlkMkZ5WkZKbFppZ2lLMlVySWlraU9pSkdiM0ozWVhKa1VtVm1JaWtzWlR0allYTmxJSGwwT25K'
    || 'bGRIVnliaUIwUFdVdVpHbHpjR3hoZVU1aGJXVjhmRzUxYkd3c2RDRTlQVzUxYkd3L2REcGFLR1V1ZEhsd1pTbDhmQ0pOWlcxdklqdGpZWE5sSUVabE9uUTla'
    || 'UzVmY0dGNWJHOWhaQ3hsUFdVdVgybHVhWFE3ZEhKNWUzSmxkSFZ5YmlCYUtHVW9kQ2twZldOaGRHTm9lMzE5Y21WMGRYSnVJRzUxYkd4OVpuVnVZM1JwYjI0'
    || 'Z2JtVW9aU2w3ZG1GeUlIUTlaUzUwZVhCbE8zTjNhWFJqYUNobExuUmhaeWw3WTJGelpTQXlORHB5WlhSMWNtNGlRMkZqYUdVaU8yTmhjMlVnT1RweVpYUjFj'
    || 'bTRvZEM1a2FYTndiR0Y1VG1GdFpYeDhJa052Ym5SbGVIUWlLU3NpTGtOdmJuTjFiV1Z5SWp0allYTmxJREV3T25KbGRIVnliaWgwTGw5amIyNTBaWGgwTG1S'
    || 'cGMzQnNZWGxPWVcxbGZId2lRMjl1ZEdWNGRDSXBLeUl1VUhKdmRtbGtaWElpTzJOaGMyVWdNVGc2Y21WMGRYSnVJa1JsYUhsa2NtRjBaV1JHY21GbmJXVnVk'
    || 'Q0k3WTJGelpTQXhNVHB5WlhSMWNtNGdaVDEwTG5KbGJtUmxjaXhsUFdVdVpHbHpjR3hoZVU1aGJXVjhmR1V1Ym1GdFpYeDhJaUlzZEM1a2FYTndiR0Y1VG1G'
    || 'dFpYeDhLR1VoUFQwaUlqOGlSbTl5ZDJGeVpGSmxaaWdpSzJVcklpa2lPaUpHYjNKM1lYSmtVbVZtSWlrN1kyRnpaU0EzT25KbGRIVnliaUpHY21GbmJXVnVk'
    || 'Q0k3WTJGelpTQTFPbkpsZEhWeWJpQjBPMk5oYzJVZ05EcHlaWFIxY200aVVHOXlkR0ZzSWp0allYTmxJRE02Y21WMGRYSnVJbEp2YjNRaU8yTmhjMlVnTmpw'
    || 'eVpYUjFjbTRpVkdWNGRDSTdZMkZ6WlNBeE5qcHlaWFIxY200Z1dpaDBLVHRqWVhObElEZzZjbVYwZFhKdUlIUTlQVDFRWlQ4aVUzUnlhV04wVFc5a1pTSTZJ'
    || 'azF2WkdVaU8yTmhjMlVnTWpJNmNtVjBkWEp1SWs5bVpuTmpjbVZsYmlJN1kyRnpaU0F4TWpweVpYUjFjbTRpVUhKdlptbHNaWElpTzJOaGMyVWdNakU2Y21W'
    || 'MGRYSnVJbE5qYjNCbElqdGpZWE5sSURFek9uSmxkSFZ5YmlKVGRYTndaVzV6WlNJN1kyRnpaU0F4T1RweVpYUjFjbTRpVTNWemNHVnVjMlZNYVhOMElqdGpZ'
    || 'WE5sSURJMU9uSmxkSFZ5YmlKVWNtRmphVzVuVFdGeWEyVnlJanRqWVhObElERTZZMkZ6WlNBd09tTmhjMlVnTVRjNlkyRnpaU0F5T21OaGMyVWdNVFE2WTJG'
    || 'elpTQXhOVHBwWmloMGVYQmxiMllnZEQwOUltWjFibU4wYVc5dUlpbHlaWFIxY200Z2RDNWthWE53YkdGNVRtRnRaWHg4ZEM1dVlXMWxmSHh1ZFd4c08ybG1L'
    || 'SFI1Y0dWdlppQjBQVDBpYzNSeWFXNW5JaWx5WlhSMWNtNGdkSDF5WlhSMWNtNGdiblZzYkgxbWRXNWpkR2x2YmlCbFpTaGxLWHR6ZDJsMFkyZ29kSGx3Wlc5'
    || 'bUlHVXBlMk5oYzJVaVltOXZiR1ZoYmlJNlkyRnpaU0p1ZFcxaVpYSWlPbU5oYzJVaWMzUnlhVzVuSWpwallYTmxJblZ1WkdWbWFXNWxaQ0k2Y21WMGRYSnVJ'
    || 'R1U3WTJGelpTSnZZbXBsWTNRaU9uSmxkSFZ5YmlCbE8yUmxabUYxYkhRNmNtVjBkWEp1SWlKOWZXWjFibU4wYVc5dUlHOWxLR1VwZTNaaGNpQjBQV1V1ZEhs'
    || 'd1pUdHlaWFIxY200b1pUMWxMbTV2WkdWT1lXMWxLU1ltWlM1MGIweHZkMlZ5UTJGelpTZ3BQVDA5SW1sdWNIVjBJaVltS0hROVBUMGlZMmhsWTJ0aWIzZ2lm'
    || 'SHgwUFQwOUluSmhaR2x2SWlsOVpuVnVZM1JwYjI0Z1MyVW9aU2w3ZG1GeUlIUTliMlVvWlNrL0ltTm9aV05yWldRaU9pSjJZV3gxWlNJc2JqMVBZbXBsWTNR'
    || 'dVoyVjBUM2R1VUhKdmNHVnlkSGxFWlhOamNtbHdkRzl5S0dVdVkyOXVjM1J5ZFdOMGIzSXVjSEp2ZEc5MGVYQmxMSFFwTEhJOUlpSXJaVnQwWFR0cFppZ2ha'
    || 'UzVvWVhOUGQyNVFjbTl3WlhKMGVTaDBLU1ltZEhsd1pXOW1JRzQ4SW5VaUppWjBlWEJsYjJZZ2JpNW5aWFE5UFNKbWRXNWpkR2x2YmlJbUpuUjVjR1Z2WmlC'
    || 'dUxuTmxkRDA5SW1aMWJtTjBhVzl1SWlsN2RtRnlJR3c5Ymk1blpYUXNhVDF1TG5ObGREdHlaWFIxY200Z1QySnFaV04wTG1SbFptbHVaVkJ5YjNCbGNuUjVL'
    || 'R1VzZEN4N1kyOXVabWxuZFhKaFlteGxPaUV3TEdkbGREcG1kVzVqZEdsdmJpZ3BlM0psZEhWeWJpQnNMbU5oYkd3b2RHaHBjeWw5TEhObGREcG1kVzVqZEds'
    || 'dmJpaHpLWHR5UFNJaUszTXNhUzVqWVd4c0tIUm9hWE1zY3lsOWZTa3NUMkpxWldOMExtUmxabWx1WlZCeWIzQmxjblI1S0dVc2RDeDdaVzUxYldWeVlXSnNa'
    || 'VHB1TG1WdWRXMWxjbUZpYkdWOUtTeDdaMlYwVm1Gc2RXVTZablZ1WTNScGIyNG9LWHR5WlhSMWNtNGdjbjBzYzJWMFZtRnNkV1U2Wm5WdVkzUnBiMjRvY3ls'
    || 'N2NqMGlJaXR6ZlN4emRHOXdWSEpoWTJ0cGJtYzZablZ1WTNScGIyNG9LWHRsTGw5MllXeDFaVlJ5WVdOclpYSTliblZzYkN4a1pXeGxkR1VnWlZ0MFhYMTlm'
    || 'WDFtZFc1amRHbHZiaUJQY2lobEtYdGxMbDkyWVd4MVpWUnlZV05yWlhKOGZDaGxMbDkyWVd4MVpWUnlZV05yWlhJOVMyVW9aU2twZldaMWJtTjBhVzl1SUhC'
    || 'ektHVXBlMmxtS0NGbEtYSmxkSFZ5YmlFeE8zWmhjaUIwUFdVdVgzWmhiSFZsVkhKaFkydGxjanRwWmlnaGRDbHlaWFIxY200aE1EdDJZWElnYmoxMExtZGxk'
    || 'RlpoYkhWbEtDa3NjajBpSWp0eVpYUjFjbTRnWlNZbUtISTliMlVvWlNrL1pTNWphR1ZqYTJWa1B5SjBjblZsSWpvaVptRnNjMlVpT21VdWRtRnNkV1VwTEdV'
    || 'OWNpeGxJVDA5Ymo4b2RDNXpaWFJXWVd4MVpTaGxLU3doTUNrNklURjlablZ1WTNScGIyNGdVSElvWlNsN2FXWW9aVDFsZkh3b2RIbHdaVzltSUdSdlkzVnRa'
    || 'VzUwUENKMUlqOWtiMk4xYldWdWREcDJiMmxrSURBcExIUjVjR1Z2WmlCbFBpSjFJaWx5WlhSMWNtNGdiblZzYkR0MGNubDdjbVYwZFhKdUlHVXVZV04wYVha'
    || 'bFJXeGxiV1Z1ZEh4OFpTNWliMlI1ZldOaGRHTm9lM0psZEhWeWJpQmxMbUp2WkhsOWZXWjFibU4wYVc5dUlIUnBLR1VzZENsN2RtRnlJRzQ5ZEM1amFHVmph'
    || 'MlZrTzNKbGRIVnliaUJOS0h0OUxIUXNlMlJsWm1GMWJIUkRhR1ZqYTJWa09uWnZhV1FnTUN4a1pXWmhkV3gwVm1Gc2RXVTZkbTlwWkNBd0xIWmhiSFZsT25a'
    || 'dmFXUWdNQ3hqYUdWamEyVmtPbTQvUDJVdVgzZHlZWEJ3WlhKVGRHRjBaUzVwYm1sMGFXRnNRMmhsWTJ0bFpIMHBmV1oxYm1OMGFXOXVJR2h6S0dVc2RDbDdk'
    || 'bUZ5SUc0OWRDNWtaV1poZFd4MFZtRnNkV1U5UFc1MWJHdy9JaUk2ZEM1a1pXWmhkV3gwVm1Gc2RXVXNjajEwTG1Ob1pXTnJaV1FoUFc1MWJHdy9kQzVqYUdW'
    || 'amEyVmtPblF1WkdWbVlYVnNkRU5vWldOclpXUTdiajFsWlNoMExuWmhiSFZsSVQxdWRXeHNQM1F1ZG1Gc2RXVTZiaWtzWlM1ZmQzSmhjSEJsY2xOMFlYUmxQ'
    || 'WHRwYm1sMGFXRnNRMmhsWTJ0bFpEcHlMR2x1YVhScFlXeFdZV3gxWlRwdUxHTnZiblJ5YjJ4c1pXUTZkQzUwZVhCbFBUMDlJbU5vWldOclltOTRJbng4ZEM1'
    || 'MGVYQmxQVDA5SW5KaFpHbHZJajkwTG1Ob1pXTnJaV1FoUFc1MWJHdzZkQzUyWVd4MVpTRTliblZzYkgxOVpuVnVZM1JwYjI0Z2JYTW9aU3gwS1h0MFBYUXVZ'
    || 'MmhsWTJ0bFpDeDBJVDF1ZFd4c0ppWlJaU2hsTENKamFHVmphMlZrSWl4MExDRXhLWDFtZFc1amRHbHZiaUJ1YVNobExIUXBlMjF6S0dVc2RDazdkbUZ5SUc0'
    || 'OVpXVW9kQzUyWVd4MVpTa3NjajEwTG5SNWNHVTdhV1lvYmlFOWJuVnNiQ2x5UFQwOUltNTFiV0psY2lJL0tHNDlQVDB3SmlabExuWmhiSFZsUFQwOUlpSjhm'
    || 'R1V1ZG1Gc2RXVWhQVzRwSmlZb1pTNTJZV3gxWlQwaUlpdHVLVHBsTG5aaGJIVmxJVDA5SWlJcmJpWW1LR1V1ZG1Gc2RXVTlJaUlyYmlrN1pXeHpaU0JwWmlo'
    || 'eVBUMDlJbk4xWW0xcGRDSjhmSEk5UFQwaWNtVnpaWFFpS1h0bExuSmxiVzkyWlVGMGRISnBZblYwWlNnaWRtRnNkV1VpS1R0eVpYUjFjbTU5ZEM1b1lYTlBk'
    || 'MjVRY205d1pYSjBlU2dpZG1Gc2RXVWlLVDl5YVNobExIUXVkSGx3WlN4dUtUcDBMbWhoYzA5M2JsQnliM0JsY25SNUtDSmtaV1poZFd4MFZtRnNkV1VpS1NZ'
    || 'bWNta29aU3gwTG5SNWNHVXNaV1VvZEM1a1pXWmhkV3gwVm1Gc2RXVXBLU3gwTG1Ob1pXTnJaV1E5UFc1MWJHd21KblF1WkdWbVlYVnNkRU5vWldOclpXUWhQ'
    || 'VzUxYkd3bUppaGxMbVJsWm1GMWJIUkRhR1ZqYTJWa1BTRWhkQzVrWldaaGRXeDBRMmhsWTJ0bFpDbDlablZ1WTNScGIyNGdkbk1vWlN4MExHNHBlMmxtS0hR'
    || 'dWFHRnpUM2R1VUhKdmNHVnlkSGtvSW5aaGJIVmxJaWw4ZkhRdWFHRnpUM2R1VUhKdmNHVnlkSGtvSW1SbFptRjFiSFJXWVd4MVpTSXBLWHQyWVhJZ2NqMTBM'
    || 'blI1Y0dVN2FXWW9JU2h5SVQwOUluTjFZbTFwZENJbUpuSWhQVDBpY21WelpYUWlmSHgwTG5aaGJIVmxJVDA5ZG05cFpDQXdKaVowTG5aaGJIVmxJVDA5Ym5W'
    || 'c2JDa3BjbVYwZFhKdU8zUTlJaUlyWlM1ZmQzSmhjSEJsY2xOMFlYUmxMbWx1YVhScFlXeFdZV3gxWlN4dWZIeDBQVDA5WlM1MllXeDFaWHg4S0dVdWRtRnNk'
    || 'V1U5ZENrc1pTNWtaV1poZFd4MFZtRnNkV1U5ZEgxdVBXVXVibUZ0WlN4dUlUMDlJaUltSmlobExtNWhiV1U5SWlJcExHVXVaR1ZtWVhWc2RFTm9aV05yWldR'
    || 'OUlTRmxMbDkzY21Gd2NHVnlVM1JoZEdVdWFXNXBkR2xoYkVOb1pXTnJaV1FzYmlFOVBTSWlKaVlvWlM1dVlXMWxQVzRwZldaMWJtTjBhVzl1SUhKcEtHVXNk'
    || 'Q3h1S1hzb2RDRTlQU0p1ZFcxaVpYSWlmSHhRY2lobExtOTNibVZ5Ukc5amRXMWxiblFwSVQwOVpTa21KaWh1UFQxdWRXeHNQMlV1WkdWbVlYVnNkRlpoYkhW'
    || 'bFBTSWlLMlV1WDNkeVlYQndaWEpUZEdGMFpTNXBibWwwYVdGc1ZtRnNkV1U2WlM1a1pXWmhkV3gwVm1Gc2RXVWhQVDBpSWl0dUppWW9aUzVrWldaaGRXeDBW'
    || 'bUZzZFdVOUlpSXJiaWtwZlhaaGNpQlJiajFCY25KaGVTNXBjMEZ5Y21GNU8yWjFibU4wYVc5dUlIbHVLR1VzZEN4dUxISXBlMmxtS0dVOVpTNXZjSFJwYjI1'
    || 'ekxIUXBlM1E5ZTMwN1ptOXlLSFpoY2lCc1BUQTdiRHh1TG14bGJtZDBhRHRzS3lzcGRGc2lKQ0lyYmx0c1hWMDlJVEE3Wm05eUtHNDlNRHR1UEdVdWJHVnVa'
    || 'M1JvTzI0ckt5bHNQWFF1YUdGelQzZHVVSEp2Y0dWeWRIa29JaVFpSzJWYmJsMHVkbUZzZFdVcExHVmJibDB1YzJWc1pXTjBaV1FoUFQxc0ppWW9aVnR1WFM1'
    || 'elpXeGxZM1JsWkQxc0tTeHNKaVp5SmlZb1pWdHVYUzVrWldaaGRXeDBVMlZzWldOMFpXUTlJVEFwZldWc2MyVjdabTl5S0c0OUlpSXJaV1VvYmlrc2REMXVk'
    || 'V3hzTEd3OU1EdHNQR1V1YkdWdVozUm9PMndyS3lsN2FXWW9aVnRzWFM1MllXeDFaVDA5UFc0cGUyVmJiRjB1YzJWc1pXTjBaV1E5SVRBc2NpWW1LR1ZiYkYw'
    || 'dVpHVm1ZWFZzZEZObGJHVmpkR1ZrUFNFd0tUdHlaWFIxY201OWRDRTlQVzUxYkd4OGZHVmJiRjB1WkdsellXSnNaV1I4ZkNoMFBXVmJiRjBwZlhRaFBUMXVk'
    || 'V3hzSmlZb2RDNXpaV3hsWTNSbFpEMGhNQ2w5ZldaMWJtTjBhVzl1SUd4cEtHVXNkQ2w3YVdZb2RDNWtZVzVuWlhKdmRYTnNlVk5sZEVsdWJtVnlTRlJOVENF'
    || 'OWJuVnNiQ2wwYUhKdmR5QkZjbkp2Y2loaktEa3hLU2s3Y21WMGRYSnVJRTBvZTMwc2RDeDdkbUZzZFdVNmRtOXBaQ0F3TEdSbFptRjFiSFJXWVd4MVpUcDJi'
    || 'MmxrSURBc1kyaHBiR1J5Wlc0NklpSXJaUzVmZDNKaGNIQmxjbE4wWVhSbExtbHVhWFJwWVd4V1lXeDFaWDBwZldaMWJtTjBhVzl1SUdkektHVXNkQ2w3ZG1G'
    || 'eUlHNDlkQzUyWVd4MVpUdHBaaWh1UFQxdWRXeHNLWHRwWmlodVBYUXVZMmhwYkdSeVpXNHNkRDEwTG1SbFptRjFiSFJXWVd4MVpTeHVJVDF1ZFd4c0tYdHBa'
    || 'aWgwSVQxdWRXeHNLWFJvY205M0lFVnljbTl5S0dNb09USXBLVHRwWmloUmJpaHVLU2w3YVdZb01UeHVMbXhsYm1kMGFDbDBhSEp2ZHlCRmNuSnZjaWhqS0Rr'
    || 'ektTazdiajF1V3pCZGZYUTlibjEwUFQxdWRXeHNKaVlvZEQwaUlpa3NiajEwZldVdVgzZHlZWEJ3WlhKVGRHRjBaVDE3YVc1cGRHbGhiRlpoYkhWbE9tVmxL'
    || 'RzRwZlgxbWRXNWpkR2x2YmlCNWN5aGxMSFFwZTNaaGNpQnVQV1ZsS0hRdWRtRnNkV1VwTEhJOVpXVW9kQzVrWldaaGRXeDBWbUZzZFdVcE8yNGhQVzUxYkd3'
    || 'bUppaHVQU0lpSzI0c2JpRTlQV1V1ZG1Gc2RXVW1KaWhsTG5aaGJIVmxQVzRwTEhRdVpHVm1ZWFZzZEZaaGJIVmxQVDF1ZFd4c0ppWmxMbVJsWm1GMWJIUldZ'
    || 'V3gxWlNFOVBXNG1KaWhsTG1SbFptRjFiSFJXWVd4MVpUMXVLU2tzY2lFOWJuVnNiQ1ltS0dVdVpHVm1ZWFZzZEZaaGJIVmxQU0lpSzNJcGZXWjFibU4wYVc5'
    || 'dUlIaHpLR1VwZTNaaGNpQjBQV1V1ZEdWNGRFTnZiblJsYm5RN2REMDlQV1V1WDNkeVlYQndaWEpUZEdGMFpTNXBibWwwYVdGc1ZtRnNkV1VtSm5RaFBUMGlJ'
    || 'aVltZENFOVBXNTFiR3dtSmlobExuWmhiSFZsUFhRcGZXWjFibU4wYVc5dUlIZHpLR1VwZTNOM2FYUmphQ2hsS1h0allYTmxJbk4yWnlJNmNtVjBkWEp1SW1o'
    || 'MGRIQTZMeTkzZDNjdWR6TXViM0puTHpJd01EQXZjM1puSWp0allYTmxJbTFoZEdnaU9uSmxkSFZ5YmlKb2RIUndPaTh2ZDNkM0xuY3pMbTl5Wnk4eE9UazRM'
    || 'MDFoZEdndlRXRjBhRTFNSWp0a1pXWmhkV3gwT25KbGRIVnliaUpvZEhSd09pOHZkM2QzTG5jekxtOXlaeTh4T1RrNUwzaG9kRzFzSW4xOVpuVnVZM1JwYjI0'
    || 'Z2FXa29aU3gwS1h0eVpYUjFjbTRnWlQwOWJuVnNiSHg4WlQwOVBTSm9kSFJ3T2k4dmQzZDNMbmN6TG05eVp5OHhPVGs1TDNob2RHMXNJajkzY3loMEtUcGxQ'
    || 'VDA5SW1oMGRIQTZMeTkzZDNjdWR6TXViM0puTHpJd01EQXZjM1puSWlZbWREMDlQU0ptYjNKbGFXZHVUMkpxWldOMElqOGlhSFIwY0RvdkwzZDNkeTUzTXk1'
    || 'dmNtY3ZNVGs1T1M5NGFIUnRiQ0k2WlgxMllYSWdUWElzWDNNOUtHWjFibU4wYVc5dUtHVXBlM0psZEhWeWJpQjBlWEJsYjJZZ1RWTkJjSEE4SW5VaUppWk5V'
    || 'MEZ3Y0M1bGVHVmpWVzV6WVdabFRHOWpZV3hHZFc1amRHbHZiajltZFc1amRHbHZiaWgwTEc0c2NpeHNLWHROVTBGd2NDNWxlR1ZqVlc1ellXWmxURzlqWVd4'
    || 'R2RXNWpkR2x2YmlobWRXNWpkR2x2YmlncGUzSmxkSFZ5YmlCbEtIUXNiaXh5TEd3cGZTbDlPbVY5S1NobWRXNWpkR2x2YmlobExIUXBlMmxtS0dVdWJtRnRa'
    || 'WE53WVdObFZWSkpJVDA5SW1oMGRIQTZMeTkzZDNjdWR6TXViM0puTHpJd01EQXZjM1puSW54OEltbHVibVZ5U0ZSTlRDSnBiaUJsS1dVdWFXNXVaWEpJVkUx'
    || 'TVBYUTdaV3h6Wlh0bWIzSW9UWEk5VFhKOGZHUnZZM1Z0Wlc1MExtTnlaV0YwWlVWc1pXMWxiblFvSW1ScGRpSXBMRTF5TG1sdWJtVnlTRlJOVEQwaVBITjJa'
    || 'ejRpSzNRdWRtRnNkV1ZQWmlncExuUnZVM1J5YVc1bktDa3JJand2YzNablBpSXNkRDFOY2k1bWFYSnpkRU5vYVd4a08yVXVabWx5YzNSRGFHbHNaRHNwWlM1'
    || 'eVpXMXZkbVZEYUdsc1pDaGxMbVpwY25OMFEyaHBiR1FwTzJadmNpZzdkQzVtYVhKemRFTm9hV3hrT3lsbExtRndjR1Z1WkVOb2FXeGtLSFF1Wm1seWMzUkRh'
    || 'R2xzWkNsOWZTazdablZ1WTNScGIyNGdSMjRvWlN4MEtYdHBaaWgwS1h0MllYSWdiajFsTG1acGNuTjBRMmhwYkdRN2FXWW9iaVltYmowOVBXVXViR0Z6ZEVO'
    || 'b2FXeGtKaVp1TG01dlpHVlVlWEJsUFQwOU15bDdiaTV1YjJSbFZtRnNkV1U5ZER0eVpYUjFjbTU5ZldVdWRHVjRkRU52Ym5SbGJuUTlkSDEyWVhJZ1MyNDll'
    || 'MkZ1YVcxaGRHbHZia2wwWlhKaGRHbHZia052ZFc1ME9pRXdMR0Z6Y0dWamRGSmhkR2x2T2lFd0xHSnZjbVJsY2tsdFlXZGxUM1YwYzJWME9pRXdMR0p2Y21S'
    || 'bGNrbHRZV2RsVTJ4cFkyVTZJVEFzWW05eVpHVnlTVzFoWjJWWGFXUjBhRG9oTUN4aWIzaEdiR1Y0T2lFd0xHSnZlRVpzWlhoSGNtOTFjRG9oTUN4aWIzaFBj'
    || 'bVJwYm1Gc1IzSnZkWEE2SVRBc1kyOXNkVzF1UTI5MWJuUTZJVEFzWTI5c2RXMXVjem9oTUN4bWJHVjRPaUV3TEdac1pYaEhjbTkzT2lFd0xHWnNaWGhRYjNO'
    || 'cGRHbDJaVG9oTUN4bWJHVjRVMmh5YVc1ck9pRXdMR1pzWlhoT1pXZGhkR2wyWlRvaE1DeG1iR1Y0VDNKa1pYSTZJVEFzWjNKcFpFRnlaV0U2SVRBc1ozSnBa'
    || 'Rkp2ZHpvaE1DeG5jbWxrVW05M1JXNWtPaUV3TEdkeWFXUlNiM2RUY0dGdU9pRXdMR2R5YVdSU2IzZFRkR0Z5ZERvaE1DeG5jbWxrUTI5c2RXMXVPaUV3TEdk'
    || 'eWFXUkRiMngxYlc1RmJtUTZJVEFzWjNKcFpFTnZiSFZ0YmxOd1lXNDZJVEFzWjNKcFpFTnZiSFZ0YmxOMFlYSjBPaUV3TEdadmJuUlhaV2xuYUhRNklUQXNi'
    || 'R2x1WlVOc1lXMXdPaUV3TEd4cGJtVklaV2xuYUhRNklUQXNiM0JoWTJsMGVUb2hNQ3h2Y21SbGNqb2hNQ3h2Y25Cb1lXNXpPaUV3TEhSaFlsTnBlbVU2SVRB'
    || 'c2QybGtiM2R6T2lFd0xIcEpibVJsZURvaE1DeDZiMjl0T2lFd0xHWnBiR3hQY0dGamFYUjVPaUV3TEdac2IyOWtUM0JoWTJsMGVUb2hNQ3h6ZEc5d1QzQmhZ'
    || 'MmwwZVRvaE1DeHpkSEp2YTJWRVlYTm9ZWEp5WVhrNklUQXNjM1J5YjJ0bFJHRnphRzltWm5ObGREb2hNQ3h6ZEhKdmEyVk5hWFJsY214cGJXbDBPaUV3TEhO'
    || 'MGNtOXJaVTl3WVdOcGRIazZJVEFzYzNSeWIydGxWMmxrZEdnNklUQjlMR3hrUFZzaVYyVmlhMmwwSWl3aWJYTWlMQ0pOYjNvaUxDSlBJbDA3VDJKcVpXTjBM'
    || 'bXRsZVhNb1MyNHBMbVp2Y2tWaFkyZ29ablZ1WTNScGIyNG9aU2w3YkdRdVptOXlSV0ZqYUNobWRXNWpkR2x2YmloMEtYdDBQWFFyWlM1amFHRnlRWFFvTUNr'
    || 'dWRHOVZjSEJsY2tOaGMyVW9LU3RsTG5OMVluTjBjbWx1WnlneEtTeExibHQwWFQxTGJsdGxYWDBwZlNrN1puVnVZM1JwYjI0Z1UzTW9aU3gwTEc0cGUzSmxk'
    || 'SFZ5YmlCMFBUMXVkV3hzZkh4MGVYQmxiMllnZEQwOUltSnZiMnhsWVc0aWZIeDBQVDA5SWlJL0lpSTZibng4ZEhsd1pXOW1JSFFoUFNKdWRXMWlaWElpZkh4'
    || 'MFBUMDlNSHg4UzI0dWFHRnpUM2R1VUhKdmNHVnlkSGtvWlNrbUprdHVXMlZkUHlnaUlpdDBLUzUwY21sdEtDazZkQ3NpY0hnaWZXWjFibU4wYVc5dUlFVnpL'
    || 'R1VzZENsN1pUMWxMbk4wZVd4bE8yWnZjaWgyWVhJZ2JpQnBiaUIwS1dsbUtIUXVhR0Z6VDNkdVVISnZjR1Z5ZEhrb2Jpa3BlM1poY2lCeVBXNHVhVzVrWlho'
    || 'UFppZ2lMUzBpS1QwOVBUQXNiRDFUY3lodUxIUmJibDBzY2lrN2JqMDlQU0ptYkc5aGRDSW1KaWh1UFNKamMzTkdiRzloZENJcExISS9aUzV6WlhSUWNtOXda'
    || 'WEowZVNodUxHd3BPbVZiYmwwOWJIMTlkbUZ5SUdsa1BVMG9lMjFsYm5WcGRHVnRPaUV3ZlN4N1lYSmxZVG9oTUN4aVlYTmxPaUV3TEdKeU9pRXdMR052YkRv'
    || 'aE1DeGxiV0psWkRvaE1DeG9jam9oTUN4cGJXYzZJVEFzYVc1d2RYUTZJVEFzYTJWNVoyVnVPaUV3TEd4cGJtczZJVEFzYldWMFlUb2hNQ3h3WVhKaGJUb2hN'
    || 'Q3h6YjNWeVkyVTZJVEFzZEhKaFkyczZJVEFzZDJKeU9pRXdmU2s3Wm5WdVkzUnBiMjRnYjJrb1pTeDBLWHRwWmloMEtYdHBaaWhwWkZ0bFhTWW1LSFF1WTJo'
    || 'cGJHUnlaVzRoUFc1MWJHeDhmSFF1WkdGdVoyVnliM1Z6YkhsVFpYUkpibTVsY2toVVRVd2hQVzUxYkd3cEtYUm9jbTkzSUVWeWNtOXlLR01vTVRNM0xHVXBL'
    || 'VHRwWmloMExtUmhibWRsY205MWMyeDVVMlYwU1c1dVpYSklWRTFNSVQxdWRXeHNLWHRwWmloMExtTm9hV3hrY21WdUlUMXVkV3hzS1hSb2NtOTNJRVZ5Y205'
    || 'eUtHTW9OakFwS1R0cFppaDBlWEJsYjJZZ2RDNWtZVzVuWlhKdmRYTnNlVk5sZEVsdWJtVnlTRlJOVENFOUltOWlhbVZqZENKOGZDRW9JbDlmYUhSdGJDSnBi'
    || 'aUIwTG1SaGJtZGxjbTkxYzJ4NVUyVjBTVzV1WlhKSVZFMU1LU2wwYUhKdmR5QkZjbkp2Y2loaktEWXhLU2w5YVdZb2RDNXpkSGxzWlNFOWJuVnNiQ1ltZEhs'
    || 'd1pXOW1JSFF1YzNSNWJHVWhQU0p2WW1wbFkzUWlLWFJvY205M0lFVnljbTl5S0dNb05qSXBLWDE5Wm5WdVkzUnBiMjRnYzJrb1pTeDBLWHRwWmlobExtbHVa'
    || 'R1Y0VDJZb0lpMGlLVDA5UFMweEtYSmxkSFZ5YmlCMGVYQmxiMllnZEM1cGN6MDlJbk4wY21sdVp5STdjM2RwZEdOb0tHVXBlMk5oYzJVaVlXNXViM1JoZEds'
    || 'dmJpMTRiV3dpT21OaGMyVWlZMjlzYjNJdGNISnZabWxzWlNJNlkyRnpaU0ptYjI1MExXWmhZMlVpT21OaGMyVWlabTl1ZEMxbVlXTmxMWE55WXlJNlkyRnpa'
    || 'U0ptYjI1MExXWmhZMlV0ZFhKcElqcGpZWE5sSW1admJuUXRabUZqWlMxbWIzSnRZWFFpT21OaGMyVWlabTl1ZEMxbVlXTmxMVzVoYldVaU9tTmhjMlVpYlds'
    || 'emMybHVaeTFuYkhsd2FDSTZjbVYwZFhKdUlURTdaR1ZtWVhWc2REcHlaWFIxY200aE1IMTlkbUZ5SUhWcFBXNTFiR3c3Wm5WdVkzUnBiMjRnWVdrb1pTbDdj'
    || 'bVYwZFhKdUlHVTlaUzUwWVhKblpYUjhmR1V1YzNKalJXeGxiV1Z1ZEh4OGQybHVaRzkzTEdVdVkyOXljbVZ6Y0c5dVpHbHVaMVZ6WlVWc1pXMWxiblFtSmlo'
    || 'bFBXVXVZMjl5Y21WemNHOXVaR2x1WjFWelpVVnNaVzFsYm5RcExHVXVibTlrWlZSNWNHVTlQVDB6UDJVdWNHRnlaVzUwVG05a1pUcGxmWFpoY2lCamFUMXVk'
    || 'V3hzTEhodVBXNTFiR3dzZDI0OWJuVnNiRHRtZFc1amRHbHZiaUJyY3lobEtYdHBaaWhsUFcxeUtHVXBLWHRwWmloMGVYQmxiMllnWTJraFBTSm1kVzVqZEds'
    || 'dmJpSXBkR2h5YjNjZ1JYSnliM0lvWXlneU9EQXBLVHQyWVhJZ2REMWxMbk4wWVhSbFRtOWtaVHQwSmlZb2REMXViQ2gwS1N4amFTaGxMbk4wWVhSbFRtOWta'
    || 'U3hsTG5SNWNHVXNkQ2twZlgxbWRXNWpkR2x2YmlCT2N5aGxLWHQ0Ymo5M2JqOTNiaTV3ZFhOb0tHVXBPbmR1UFZ0bFhUcDRiajFsZldaMWJtTjBhVzl1SUdw'
    || 'ektDbDdhV1lvZUc0cGUzWmhjaUJsUFhodUxIUTlkMjQ3YVdZb2QyNDllRzQ5Ym5Wc2JDeHJjeWhsS1N4MEtXWnZjaWhsUFRBN1pUeDBMbXhsYm1kMGFEdGxL'
    || 'eXNwYTNNb2RGdGxYU2w5ZldaMWJtTjBhVzl1SUVOektHVXNkQ2w3Y21WMGRYSnVJR1VvZENsOVpuVnVZM1JwYjI0Z1ZITW9LWHQ5ZG1GeUlHUnBQU0V4TzJa'
    || 'MWJtTjBhVzl1SUZKektHVXNkQ3h1S1h0cFppaGthU2x5WlhSMWNtNGdaU2gwTEc0cE8yUnBQU0V3TzNSeWVYdHlaWFIxY200Z1EzTW9aU3gwTEc0cGZXWnBi'
    || 'bUZzYkhsN1pHazlJVEVzS0hodUlUMDliblZzYkh4OGQyNGhQVDF1ZFd4c0tTWW1LRlJ6S0Nrc2FuTW9LU2w5ZldaMWJtTjBhVzl1SUZsdUtHVXNkQ2w3ZG1G'
    || 'eUlHNDlaUzV6ZEdGMFpVNXZaR1U3YVdZb2JqMDlQVzUxYkd3cGNtVjBkWEp1SUc1MWJHdzdkbUZ5SUhJOWJtd29iaWs3YVdZb2NqMDlQVzUxYkd3cGNtVjBk'
    || 'WEp1SUc1MWJHdzdiajF5VzNSZE8yVTZjM2RwZEdOb0tIUXBlMk5oYzJVaWIyNURiR2xqYXlJNlkyRnpaU0p2YmtOc2FXTnJRMkZ3ZEhWeVpTSTZZMkZ6WlNK'
    || 'dmJrUnZkV0pzWlVOc2FXTnJJanBqWVhObEltOXVSRzkxWW14bFEyeHBZMnREWVhCMGRYSmxJanBqWVhObEltOXVUVzkxYzJWRWIzZHVJanBqWVhObEltOXVU'
    || 'VzkxYzJWRWIzZHVRMkZ3ZEhWeVpTSTZZMkZ6WlNKdmJrMXZkWE5sVFc5MlpTSTZZMkZ6WlNKdmJrMXZkWE5sVFc5MlpVTmhjSFIxY21VaU9tTmhjMlVpYjI1'
    || 'TmIzVnpaVlZ3SWpwallYTmxJbTl1VFc5MWMyVlZjRU5oY0hSMWNtVWlPbU5oYzJVaWIyNU5iM1Z6WlVWdWRHVnlJam9vY2owaGNpNWthWE5oWW14bFpDbDhm'
    || 'Q2hsUFdVdWRIbHdaU3h5UFNFb1pUMDlQU0ppZFhSMGIyNGlmSHhsUFQwOUltbHVjSFYwSW54OFpUMDlQU0p6Wld4bFkzUWlmSHhsUFQwOUluUmxlSFJoY21W'
    || 'aElpa3BMR1U5SVhJN1luSmxZV3NnWlR0a1pXWmhkV3gwT21VOUlURjlhV1lvWlNseVpYUjFjbTRnYm5Wc2JEdHBaaWh1SmlaMGVYQmxiMllnYmlFOUltWjFi'
    || 'bU4wYVc5dUlpbDBhSEp2ZHlCRmNuSnZjaWhqS0RJek1TeDBMSFI1Y0dWdlppQnVLU2s3Y21WMGRYSnVJRzU5ZG1GeUlHWnBQU0V4TzJsbUtFNHBkSEo1ZTNa'
    || 'aGNpQlliajE3ZlR0UFltcGxZM1F1WkdWbWFXNWxVSEp2Y0dWeWRIa29XRzRzSW5CaGMzTnBkbVVpTEh0blpYUTZablZ1WTNScGIyNG9LWHRtYVQwaE1IMTlL'
    || 'U3gzYVc1a2IzY3VZV1JrUlhabGJuUk1hWE4wWlc1bGNpZ2lkR1Z6ZENJc1dHNHNXRzRwTEhkcGJtUnZkeTV5WlcxdmRtVkZkbVZ1ZEV4cGMzUmxibVZ5S0NK'
    || 'MFpYTjBJaXhZYml4WWJpbDlZMkYwWTJoN1ptazlJVEY5Wm5WdVkzUnBiMjRnYjJRb1pTeDBMRzRzY2l4c0xHa3NjeXhoTEdZcGUzWmhjaUJuUFVGeWNtRjVM'
    || 'bkJ5YjNSdmRIbHdaUzV6YkdsalpTNWpZV3hzS0dGeVozVnRaVzUwY3l3ektUdDBjbmw3ZEM1aGNIQnNlU2h1TEdjcGZXTmhkR05vS0ZNcGUzUm9hWE11YjI1'
    || 'RmNuSnZjaWhUS1gxOWRtRnlJRnB1UFNFeExFbHlQVzUxYkd3c1JISTlJVEVzY0drOWJuVnNiQ3h6WkQxN2IyNUZjbkp2Y2pwbWRXNWpkR2x2YmlobEtYdGFi'
    || 'ajBoTUN4SmNqMWxmWDA3Wm5WdVkzUnBiMjRnZFdRb1pTeDBMRzRzY2l4c0xHa3NjeXhoTEdZcGUxcHVQU0V4TEVseVBXNTFiR3dzYjJRdVlYQndiSGtvYzJR'
    || 'c1lYSm5kVzFsYm5SektYMW1kVzVqZEdsdmJpQmhaQ2hsTEhRc2JpeHlMR3dzYVN4ekxHRXNaaWw3YVdZb2RXUXVZWEJ3Ykhrb2RHaHBjeXhoY21kMWJXVnVk'
    || 'SE1wTEZwdUtYdHBaaWhhYmlsN2RtRnlJR2M5U1hJN1dtNDlJVEVzU1hJOWJuVnNiSDFsYkhObElIUm9jbTkzSUVWeWNtOXlLR01vTVRrNEtTazdSSEo4ZkNo'
    || 'RWNqMGhNQ3h3YVQxbktYMTlablZ1WTNScGIyNGdibTRvWlNsN2RtRnlJSFE5WlN4dVBXVTdhV1lvWlM1aGJIUmxjbTVoZEdVcFptOXlLRHQwTG5KbGRIVnli'
    || 'anNwZEQxMExuSmxkSFZ5Ymp0bGJITmxlMlU5ZER0a2J5QjBQV1VzS0hRdVpteGhaM01tTkRBNU9Da2hQVDB3SmlZb2JqMTBMbkpsZEhWeWJpa3NaVDEwTG5K'
    || 'bGRIVnlianQzYUdsc1pTaGxLWDF5WlhSMWNtNGdkQzUwWVdjOVBUMHpQMjQ2Ym5Wc2JIMW1kVzVqZEdsdmJpQk1jeWhsS1h0cFppaGxMblJoWnowOVBURXpL'
    || 'WHQyWVhJZ2REMWxMbTFsYlc5cGVtVmtVM1JoZEdVN2FXWW9kRDA5UFc1MWJHd21KaWhsUFdVdVlXeDBaWEp1WVhSbExHVWhQVDF1ZFd4c0ppWW9kRDFsTG0x'
    || 'bGJXOXBlbVZrVTNSaGRHVXBLU3gwSVQwOWJuVnNiQ2x5WlhSMWNtNGdkQzVrWldoNVpISmhkR1ZrZlhKbGRIVnliaUJ1ZFd4c2ZXWjFibU4wYVc5dUlFOXpL'
    || 'R1VwZTJsbUtHNXVLR1VwSVQwOVpTbDBhSEp2ZHlCRmNuSnZjaWhqS0RFNE9Da3BmV1oxYm1OMGFXOXVJR05rS0dVcGUzWmhjaUIwUFdVdVlXeDBaWEp1WVhS'
    || 'bE8ybG1LQ0YwS1h0cFppaDBQVzV1S0dVcExIUTlQVDF1ZFd4c0tYUm9jbTkzSUVWeWNtOXlLR01vTVRnNEtTazdjbVYwZFhKdUlIUWhQVDFsUDI1MWJHdzZa'
    || 'WDFtYjNJb2RtRnlJRzQ5WlN4eVBYUTdPeWw3ZG1GeUlHdzliaTV5WlhSMWNtNDdhV1lvYkQwOVBXNTFiR3dwWW5KbFlXczdkbUZ5SUdrOWJDNWhiSFJsY201'
    || 'aGRHVTdhV1lvYVQwOVBXNTFiR3dwZTJsbUtISTliQzV5WlhSMWNtNHNjaUU5UFc1MWJHd3BlMjQ5Y2p0amIyNTBhVzUxWlgxaWNtVmhhMzFwWmloc0xtTm9h'
    || 'V3hrUFQwOWFTNWphR2xzWkNsN1ptOXlLR2s5YkM1amFHbHNaRHRwT3lsN2FXWW9hVDA5UFc0cGNtVjBkWEp1SUU5ektHd3BMR1U3YVdZb2FUMDlQWElwY21W'
    || 'MGRYSnVJRTl6S0d3cExIUTdhVDFwTG5OcFlteHBibWQ5ZEdoeWIzY2dSWEp5YjNJb1l5Z3hPRGdwS1gxcFppaHVMbkpsZEhWeWJpRTlQWEl1Y21WMGRYSnVL'
    || 'VzQ5YkN4eVBXazdaV3h6Wlh0bWIzSW9kbUZ5SUhNOUlURXNZVDFzTG1Ob2FXeGtPMkU3S1h0cFppaGhQVDA5YmlsN2N6MGhNQ3h1UFd3c2NqMXBPMkp5WldG'
    || 'cmZXbG1LR0U5UFQxeUtYdHpQU0V3TEhJOWJDeHVQV2s3WW5KbFlXdDlZVDFoTG5OcFlteHBibWQ5YVdZb0lYTXBlMlp2Y2loaFBXa3VZMmhwYkdRN1lUc3Bl'
    || 'MmxtS0dFOVBUMXVLWHR6UFNFd0xHNDlhU3h5UFd3N1luSmxZV3Q5YVdZb1lUMDlQWElwZTNNOUlUQXNjajFwTEc0OWJEdGljbVZoYTMxaFBXRXVjMmxpYkds'
    || 'dVozMXBaaWdoY3lsMGFISnZkeUJGY25KdmNpaGpLREU0T1NrcGZYMXBaaWh1TG1Gc2RHVnlibUYwWlNFOVBYSXBkR2h5YjNjZ1JYSnliM0lvWXlneE9UQXBL'
    || 'WDFwWmlodUxuUmhaeUU5UFRNcGRHaHliM2NnUlhKeWIzSW9ZeWd4T0RncEtUdHlaWFIxY200Z2JpNXpkR0YwWlU1dlpHVXVZM1Z5Y21WdWREMDlQVzQvWlRw'
    || 'MGZXWjFibU4wYVc5dUlGQnpLR1VwZTNKbGRIVnliaUJsUFdOa0tHVXBMR1VoUFQxdWRXeHNQMDF6S0dVcE9tNTFiR3g5Wm5WdVkzUnBiMjRnVFhNb1pTbDdh'
    || 'V1lvWlM1MFlXYzlQVDAxZkh4bExuUmhaejA5UFRZcGNtVjBkWEp1SUdVN1ptOXlLR1U5WlM1amFHbHNaRHRsSVQwOWJuVnNiRHNwZTNaaGNpQjBQVTF6S0dV'
    || 'cE8ybG1LSFFoUFQxdWRXeHNLWEpsZEhWeWJpQjBPMlU5WlM1emFXSnNhVzVuZlhKbGRIVnliaUJ1ZFd4c2ZYWmhjaUJKY3oxa0xuVnVjM1JoWW14bFgzTmph'
    || 'R1ZrZFd4bFEyRnNiR0poWTJzc1JITTlaQzUxYm5OMFlXSnNaVjlqWVc1alpXeERZV3hzWW1GamF5eGtaRDFrTG5WdWMzUmhZbXhsWDNOb2IzVnNaRmxwWld4'
    || 'a0xHWmtQV1F1ZFc1emRHRmliR1ZmY21WeGRXVnpkRkJoYVc1MExHaGxQV1F1ZFc1emRHRmliR1ZmYm05M0xIQmtQV1F1ZFc1emRHRmliR1ZmWjJWMFEzVnlj'
    || 'bVZ1ZEZCeWFXOXlhWFI1VEdWMlpXd3NhR2s5WkM1MWJuTjBZV0pzWlY5SmJXMWxaR2xoZEdWUWNtbHZjbWwwZVN4NmN6MWtMblZ1YzNSaFlteGxYMVZ6WlhK'
    || 'Q2JHOWphMmx1WjFCeWFXOXlhWFI1TEhweVBXUXVkVzV6ZEdGaWJHVmZUbTl5YldGc1VISnBiM0pwZEhrc2FHUTlaQzUxYm5OMFlXSnNaVjlNYjNkUWNtbHZj'
    || 'bWwwZVN4R2N6MWtMblZ1YzNSaFlteGxYMGxrYkdWUWNtbHZjbWwwZVN4R2NqMXVkV3hzTEhoMFBXNTFiR3c3Wm5WdVkzUnBiMjRnYldRb1pTbDdhV1lvZUhR'
    || 'bUpuUjVjR1Z2WmlCNGRDNXZia052YlcxcGRFWnBZbVZ5VW05dmREMDlJbVoxYm1OMGFXOXVJaWwwY25sN2VIUXViMjVEYjIxdGFYUkdhV0psY2xKdmIzUW9S'
    || 'bklzWlN4MmIybGtJREFzS0dVdVkzVnljbVZ1ZEM1bWJHRm5jeVl4TWpncFBUMDlNVEk0S1gxallYUmphSHQ5ZlhaaGNpQmhkRDFOWVhSb0xtTnNlak15UDAx'
    || 'aGRHZ3VZMng2TXpJNmVXUXNkbVE5VFdGMGFDNXNiMmNzWjJROVRXRjBhQzVNVGpJN1puVnVZM1JwYjI0Z2VXUW9aU2w3Y21WMGRYSnVJR1UrUGo0OU1DeGxQ'
    || 'VDA5TUQ4ek1qb3pNUzBvZG1Rb1pTa3ZaMlI4TUNsOE1IMTJZWElnUVhJOU5qUXNWWEk5TkRFNU5ETXdORHRtZFc1amRHbHZiaUJ4YmlobEtYdHpkMmwwWTJn'
    || 'b1pTWXRaU2w3WTJGelpTQXhPbkpsZEhWeWJpQXhPMk5oYzJVZ01qcHlaWFIxY200Z01qdGpZWE5sSURRNmNtVjBkWEp1SURRN1kyRnpaU0E0T25KbGRIVnli'
    || 'aUE0TzJOaGMyVWdNVFk2Y21WMGRYSnVJREUyTzJOaGMyVWdNekk2Y21WMGRYSnVJRE15TzJOaGMyVWdOalE2WTJGelpTQXhNamc2WTJGelpTQXlOVFk2WTJG'
    || 'elpTQTFNVEk2WTJGelpTQXhNREkwT21OaGMyVWdNakEwT0RwallYTmxJRFF3T1RZNlkyRnpaU0E0TVRreU9tTmhjMlVnTVRZek9EUTZZMkZ6WlNBek1qYzJP'
    || 'RHBqWVhObElEWTFOVE0yT21OaGMyVWdNVE14TURjeU9tTmhjMlVnTWpZeU1UUTBPbU5oYzJVZ05USTBNamc0T21OaGMyVWdNVEEwT0RVM05qcGpZWE5sSURJ'
    || 'd09UY3hOVEk2Y21WMGRYSnVJR1VtTkRFNU5ESTBNRHRqWVhObElEUXhPVFF6TURRNlkyRnpaU0E0TXpnNE5qQTRPbU5oYzJVZ01UWTNOemN5TVRZNlkyRnpa'
    || 'U0F6TXpVMU5EUXpNanBqWVhObElEWTNNVEE0T0RZME9uSmxkSFZ5YmlCbEpqRXpNREF5TXpReU5EdGpZWE5sSURFek5ESXhOemN5T0RweVpYUjFjbTRnTVRN'
    || 'ME1qRTNOekk0TzJOaGMyVWdNalk0TkRNMU5EVTJPbkpsZEhWeWJpQXlOamcwTXpVME5UWTdZMkZ6WlNBMU16WTROekE1TVRJNmNtVjBkWEp1SURVek5qZzNN'
    || 'RGt4TWp0allYTmxJREV3TnpNM05ERTRNalE2Y21WMGRYSnVJREV3TnpNM05ERTRNalE3WkdWbVlYVnNkRHB5WlhSMWNtNGdaWDE5Wm5WdVkzUnBiMjRnSkhJ'
    || 'b1pTeDBLWHQyWVhJZ2JqMWxMbkJsYm1ScGJtZE1ZVzVsY3p0cFppaHVQVDA5TUNseVpYUjFjbTRnTUR0MllYSWdjajB3TEd3OVpTNXpkWE53Wlc1a1pXUk1Z'
    || 'VzVsY3l4cFBXVXVjR2x1WjJWa1RHRnVaWE1zY3oxdUpqSTJPRFF6TlRRMU5UdHBaaWh6SVQwOU1DbDdkbUZ5SUdFOWN5WitiRHRoSVQwOU1EOXlQWEZ1S0dF'
    || 'cE9paHBKajF6TEdraFBUMHdKaVlvY2oxeGJpaHBLU2twZldWc2MyVWdjejF1Sm41c0xITWhQVDB3UDNJOWNXNG9jeWs2YVNFOVBUQW1KaWh5UFhGdUtHa3BL'
    || 'VHRwWmloeVBUMDlNQ2x5WlhSMWNtNGdNRHRwWmloMElUMDlNQ1ltZENFOVBYSW1KaWgwSm13cFBUMDlNQ1ltS0d3OWNpWXRjaXhwUFhRbUxYUXNiRDQ5YVh4'
    || 'OGJEMDlQVEUySmlZb2FTWTBNVGswTWpRd0tTRTlQVEFwS1hKbGRIVnliaUIwTzJsbUtDaHlKalFwSVQwOU1DWW1LSEo4UFc0bU1UWXBMSFE5WlM1bGJuUmhi'
    || 'bWRzWldSTVlXNWxjeXgwSVQwOU1DbG1iM0lvWlQxbExtVnVkR0Z1WjJ4bGJXVnVkSE1zZENZOWNqc3dQSFE3S1c0OU16RXRZWFFvZENrc2JEMHhQRHh1TEhK'
    || 'OFBXVmJibDBzZENZOWZtdzdjbVYwZFhKdUlISjlablZ1WTNScGIyNGdlR1FvWlN4MEtYdHpkMmwwWTJnb1pTbDdZMkZ6WlNBeE9tTmhjMlVnTWpwallYTmxJ'
    || 'RFE2Y21WMGRYSnVJSFFyTWpVd08yTmhjMlVnT0RwallYTmxJREUyT21OaGMyVWdNekk2WTJGelpTQTJORHBqWVhObElERXlPRHBqWVhObElESTFOanBqWVhO'
    || 'bElEVXhNanBqWVhObElERXdNalE2WTJGelpTQXlNRFE0T21OaGMyVWdOREE1TmpwallYTmxJRGd4T1RJNlkyRnpaU0F4TmpNNE5EcGpZWE5sSURNeU56WTRP'
    || 'bU5oYzJVZ05qVTFNelk2WTJGelpTQXhNekV3TnpJNlkyRnpaU0F5TmpJeE5EUTZZMkZ6WlNBMU1qUXlPRGc2WTJGelpTQXhNRFE0TlRjMk9tTmhjMlVnTWpB'
    || 'NU56RTFNanB5WlhSMWNtNGdkQ3MxWlRNN1kyRnpaU0EwTVRrME16QTBPbU5oYzJVZ09ETTRPRFl3T0RwallYTmxJREUyTnpjM01qRTJPbU5oYzJVZ016TTFO'
    || 'VFEwTXpJNlkyRnpaU0EyTnpFd09EZzJORHB5WlhSMWNtNHRNVHRqWVhObElERXpOREl4TnpjeU9EcGpZWE5sSURJMk9EUXpOVFExTmpwallYTmxJRFV6Tmpn'
    || 'M01Ea3hNanBqWVhObElERXdOek0zTkRFNE1qUTZjbVYwZFhKdUxURTdaR1ZtWVhWc2REcHlaWFIxY200dE1YMTlablZ1WTNScGIyNGdkMlFvWlN4MEtYdG1i'
    || 'M0lvZG1GeUlHNDlaUzV6ZFhOd1pXNWtaV1JNWVc1bGN5eHlQV1V1Y0dsdVoyVmtUR0Z1WlhNc2JEMWxMbVY0Y0dseVlYUnBiMjVVYVcxbGN5eHBQV1V1Y0dW'
    || 'dVpHbHVaMHhoYm1Wek96QThhVHNwZTNaaGNpQnpQVE14TFdGMEtHa3BMR0U5TVR3OGN5eG1QV3hiYzEwN1pqMDlQUzB4UHlnb1lTWnVLVDA5UFRCOGZDaGhK'
    || 'bklwSVQwOU1Da21KaWhzVzNOZFBYaGtLR0VzZENrcE9tWThQWFFtSmlobExtVjRjR2x5WldSTVlXNWxjM3c5WVNrc2FTWTlmbUY5ZldaMWJtTjBhVzl1SUcx'
    || 'cEtHVXBlM0psZEhWeWJpQmxQV1V1Y0dWdVpHbHVaMHhoYm1WekppMHhNRGN6TnpReE9ESTFMR1VoUFQwd1AyVTZaU1l4TURjek56UXhPREkwUHpFd056TTNO'
    || 'REU0TWpRNk1IMW1kVzVqZEdsdmJpQkJjeWdwZTNaaGNpQmxQVUZ5TzNKbGRIVnliaUJCY2p3OFBURXNLRUZ5SmpReE9UUXlOREFwUFQwOU1DWW1LRUZ5UFRZ'
    || 'MEtTeGxmV1oxYm1OMGFXOXVJSFpwS0dVcGUyWnZjaWgyWVhJZ2REMWJYU3h1UFRBN016RStianR1S3lzcGRDNXdkWE5vS0dVcE8zSmxkSFZ5YmlCMGZXWjFi'
    || 'bU4wYVc5dUlFcHVLR1VzZEN4dUtYdGxMbkJsYm1ScGJtZE1ZVzVsYzN3OWRDeDBJVDA5TlRNMk9EY3dPVEV5SmlZb1pTNXpkWE53Wlc1a1pXUk1ZVzVsY3ow'
    || 'd0xHVXVjR2x1WjJWa1RHRnVaWE05TUNrc1pUMWxMbVYyWlc1MFZHbHRaWE1zZEQwek1TMWhkQ2gwS1N4bFczUmRQVzU5Wm5WdVkzUnBiMjRnWDJRb1pTeDBL'
    || 'WHQyWVhJZ2JqMWxMbkJsYm1ScGJtZE1ZVzVsY3laK2REdGxMbkJsYm1ScGJtZE1ZVzVsY3oxMExHVXVjM1Z6Y0dWdVpHVmtUR0Z1WlhNOU1DeGxMbkJwYm1k'
    || 'bFpFeGhibVZ6UFRBc1pTNWxlSEJwY21Wa1RHRnVaWE1tUFhRc1pTNXRkWFJoWW14bFVtVmhaRXhoYm1WekpqMTBMR1V1Wlc1MFlXNW5iR1ZrVEdGdVpYTW1Q'
    || 'WFFzZEQxbExtVnVkR0Z1WjJ4bGJXVnVkSE03ZG1GeUlISTlaUzVsZG1WdWRGUnBiV1Z6TzJadmNpaGxQV1V1Wlhod2FYSmhkR2x2YmxScGJXVnpPekE4Ympz'
    || 'cGUzWmhjaUJzUFRNeExXRjBLRzRwTEdrOU1UdzhiRHQwVzJ4ZFBUQXNjbHRzWFQwdE1TeGxXMnhkUFMweExHNG1QWDVwZlgxbWRXNWpkR2x2YmlCbmFTaGxM'
    || 'SFFwZTNaaGNpQnVQV1V1Wlc1MFlXNW5iR1ZrVEdGdVpYTjhQWFE3Wm05eUtHVTlaUzVsYm5SaGJtZHNaVzFsYm5Sek8yNDdLWHQyWVhJZ2NqMHpNUzFoZENo'
    || 'dUtTeHNQVEU4UEhJN2JDWjBmR1ZiY2wwbWRDWW1LR1ZiY2wxOFBYUXBMRzRtUFg1c2ZYMTJZWElnZEdVOU1EdG1kVzVqZEdsdmJpQlZjeWhsS1h0eVpYUjFj'
    || 'bTRnWlNZOUxXVXNNVHhsUHpROFpUOG9aU1l5TmpnME16VTBOVFVwSVQwOU1EOHhOam8xTXpZNE56QTVNVEk2TkRveGZYWmhjaUFrY3l4NWFTeEljeXhXY3l4'
    || 'WGN5eDRhVDBoTVN4SWNqMWJYU3g2ZEQxdWRXeHNMRVowUFc1MWJHd3NRWFE5Ym5Wc2JDeGliajF1WlhjZ1RXRndMR1Z5UFc1bGR5Qk5ZWEFzVlhROVcxMHNV'
    || 'MlE5SW0xdmRYTmxaRzkzYmlCdGIzVnpaWFZ3SUhSdmRXTm9ZMkZ1WTJWc0lIUnZkV05vWlc1a0lIUnZkV05vYzNSaGNuUWdZWFY0WTJ4cFkyc2daR0pzWTJ4'
    || 'cFkyc2djRzlwYm5SbGNtTmhibU5sYkNCd2IybHVkR1Z5Wkc5M2JpQndiMmx1ZEdWeWRYQWdaSEpoWjJWdVpDQmtjbUZuYzNSaGNuUWdaSEp2Y0NCamIyMXdi'
    || 'M05wZEdsdmJtVnVaQ0JqYjIxd2IzTnBkR2x2Ym5OMFlYSjBJR3RsZVdSdmQyNGdhMlY1Y0hKbGMzTWdhMlY1ZFhBZ2FXNXdkWFFnZEdWNGRFbHVjSFYwSUdO'
    || 'dmNIa2dZM1YwSUhCaGMzUmxJR05zYVdOcklHTm9ZVzVuWlNCamIyNTBaWGgwYldWdWRTQnlaWE5sZENCemRXSnRhWFFpTG5Od2JHbDBLQ0lnSWlrN1puVnVZ'
    || 'M1JwYjI0Z1FuTW9aU3gwS1h0emQybDBZMmdvWlNsN1kyRnpaU0ptYjJOMWMybHVJanBqWVhObEltWnZZM1Z6YjNWMElqcDZkRDF1ZFd4c08ySnlaV0ZyTzJO'
    || 'aGMyVWlaSEpoWjJWdWRHVnlJanBqWVhObEltUnlZV2RzWldGMlpTSTZSblE5Ym5Wc2JEdGljbVZoYXp0allYTmxJbTF2ZFhObGIzWmxjaUk2WTJGelpTSnRi'
    || 'M1Z6Wlc5MWRDSTZRWFE5Ym5Wc2JEdGljbVZoYXp0allYTmxJbkJ2YVc1MFpYSnZkbVZ5SWpwallYTmxJbkJ2YVc1MFpYSnZkWFFpT21KdUxtUmxiR1YwWlNo'
    || 'MExuQnZhVzUwWlhKSlpDazdZbkpsWVdzN1kyRnpaU0puYjNSd2IybHVkR1Z5WTJGd2RIVnlaU0k2WTJGelpTSnNiM04wY0c5cGJuUmxjbU5oY0hSMWNtVWlP'
    || 'bVZ5TG1SbGJHVjBaU2gwTG5CdmFXNTBaWEpKWkNsOWZXWjFibU4wYVc5dUlIUnlLR1VzZEN4dUxISXNiQ3hwS1h0eVpYUjFjbTRnWlQwOVBXNTFiR3g4ZkdV'
    || 'dWJtRjBhWFpsUlhabGJuUWhQVDFwUHlobFBYdGliRzlqYTJWa1QyNDZkQ3hrYjIxRmRtVnVkRTVoYldVNmJpeGxkbVZ1ZEZONWMzUmxiVVpzWVdkek9uSXNi'
    || 'bUYwYVhabFJYWmxiblE2YVN4MFlYSm5aWFJEYjI1MFlXbHVaWEp6T2x0c1hYMHNkQ0U5UFc1MWJHd21KaWgwUFcxeUtIUXBMSFFoUFQxdWRXeHNKaVo1YVNo'
    || 'MEtTa3NaU2s2S0dVdVpYWmxiblJUZVhOMFpXMUdiR0ZuYzN3OWNpeDBQV1V1ZEdGeVoyVjBRMjl1ZEdGcGJtVnljeXhzSVQwOWJuVnNiQ1ltZEM1cGJtUmxl'
    || 'RTltS0d3cFBUMDlMVEVtSm5RdWNIVnphQ2hzS1N4bEtYMW1kVzVqZEdsdmJpQkZaQ2hsTEhRc2JpeHlMR3dwZTNOM2FYUmphQ2gwS1h0allYTmxJbVp2WTNW'
    || 'emFXNGlPbkpsZEhWeWJpQjZkRDEwY2loNmRDeGxMSFFzYml4eUxHd3BMQ0V3TzJOaGMyVWlaSEpoWjJWdWRHVnlJanB5WlhSMWNtNGdSblE5ZEhJb1JuUXNa'
    || 'U3gwTEc0c2NpeHNLU3doTUR0allYTmxJbTF2ZFhObGIzWmxjaUk2Y21WMGRYSnVJRUYwUFhSeUtFRjBMR1VzZEN4dUxISXNiQ2tzSVRBN1kyRnpaU0p3YjJs'
    || 'dWRHVnliM1psY2lJNmRtRnlJR2s5YkM1d2IybHVkR1Z5U1dRN2NtVjBkWEp1SUdKdUxuTmxkQ2hwTEhSeUtHSnVMbWRsZENocEtYeDhiblZzYkN4bExIUXNi'
    || 'aXh5TEd3cEtTd2hNRHRqWVhObEltZHZkSEJ2YVc1MFpYSmpZWEIwZFhKbElqcHlaWFIxY200Z2FUMXNMbkJ2YVc1MFpYSkpaQ3hsY2k1elpYUW9hU3gwY2lo'
    || 'bGNpNW5aWFFvYVNsOGZHNTFiR3dzWlN4MExHNHNjaXhzS1Nrc0lUQjljbVYwZFhKdUlURjlablZ1WTNScGIyNGdVWE1vWlNsN2RtRnlJSFE5Y200b1pTNTBZ'
    || 'WEpuWlhRcE8ybG1LSFFoUFQxdWRXeHNLWHQyWVhJZ2JqMXViaWgwS1R0cFppaHVJVDA5Ym5Wc2JDbDdhV1lvZEQxdUxuUmhaeXgwUFQwOU1UTXBlMmxtS0hR'
    || 'OVRITW9iaWtzZENFOVBXNTFiR3dwZTJVdVlteHZZMnRsWkU5dVBYUXNWM01vWlM1d2NtbHZjbWwwZVN4bWRXNWpkR2x2YmlncGUwaHpLRzRwZlNrN2NtVjBk'
    || 'WEp1ZlgxbGJITmxJR2xtS0hROVBUMHpKaVp1TG5OMFlYUmxUbTlrWlM1amRYSnlaVzUwTG0xbGJXOXBlbVZrVTNSaGRHVXVhWE5FWldoNVpISmhkR1ZrS1h0'
    || 'bExtSnNiMk5yWldSUGJqMXVMblJoWnowOVBUTS9iaTV6ZEdGMFpVNXZaR1V1WTI5dWRHRnBibVZ5U1c1bWJ6cHVkV3hzTzNKbGRIVnlibjE5ZldVdVlteHZZ'
    || 'MnRsWkU5dVBXNTFiR3g5Wm5WdVkzUnBiMjRnVm5Jb1pTbDdhV1lvWlM1aWJHOWphMlZrVDI0aFBUMXVkV3hzS1hKbGRIVnliaUV4TzJadmNpaDJZWElnZEQx'
    || 'bExuUmhjbWRsZEVOdmJuUmhhVzVsY25NN01EeDBMbXhsYm1kMGFEc3BlM1poY2lCdVBWOXBLR1V1Wkc5dFJYWmxiblJPWVcxbExHVXVaWFpsYm5SVGVYTjBa'
    || 'VzFHYkdGbmN5eDBXekJkTEdVdWJtRjBhWFpsUlhabGJuUXBPMmxtS0c0OVBUMXVkV3hzS1h0dVBXVXVibUYwYVhabFJYWmxiblE3ZG1GeUlISTlibVYzSUc0'
    || 'dVkyOXVjM1J5ZFdOMGIzSW9iaTUwZVhCbExHNHBPM1ZwUFhJc2JpNTBZWEpuWlhRdVpHbHpjR0YwWTJoRmRtVnVkQ2h5S1N4MWFUMXVkV3hzZldWc2MyVWdj'
    || 'bVYwZFhKdUlIUTliWElvYmlrc2RDRTlQVzUxYkd3bUpubHBLSFFwTEdVdVlteHZZMnRsWkU5dVBXNHNJVEU3ZEM1emFHbG1kQ2dwZlhKbGRIVnliaUV3Zlda'
    || 'MWJtTjBhVzl1SUVkektHVXNkQ3h1S1h0V2NpaGxLU1ltYmk1a1pXeGxkR1VvZENsOVpuVnVZM1JwYjI0Z2EyUW9LWHQ0YVQwaE1TeDZkQ0U5UFc1MWJHd21K'
    || 'bFp5S0hwMEtTWW1LSHAwUFc1MWJHd3BMRVowSVQwOWJuVnNiQ1ltVm5Jb1JuUXBKaVlvUm5ROWJuVnNiQ2tzUVhRaFBUMXVkV3hzSmlaV2NpaEJkQ2ttSmlo'
    || 'QmREMXVkV3hzS1N4aWJpNW1iM0pGWVdOb0tFZHpLU3hsY2k1bWIzSkZZV05vS0VkektYMW1kVzVqZEdsdmJpQnVjaWhsTEhRcGUyVXVZbXh2WTJ0bFpFOXVQ'
    || 'VDA5ZENZbUtHVXVZbXh2WTJ0bFpFOXVQVzUxYkd3c2VHbDhmQ2g0YVQwaE1DeGtMblZ1YzNSaFlteGxYM05qYUdWa2RXeGxRMkZzYkdKaFkyc29aQzUxYm5O'
    || 'MFlXSnNaVjlPYjNKdFlXeFFjbWx2Y21sMGVTeHJaQ2twS1gxbWRXNWpkR2x2YmlCeWNpaGxLWHRtZFc1amRHbHZiaUIwS0d3cGUzSmxkSFZ5YmlCdWNpaHNM'
    || 'R1VwZldsbUtEQThTSEl1YkdWdVozUm9LWHR1Y2loSWNsc3dYU3hsS1R0bWIzSW9kbUZ5SUc0OU1UdHVQRWh5TG14bGJtZDBhRHR1S3lzcGUzWmhjaUJ5UFVo'
    || 'eVcyNWRPM0l1WW14dlkydGxaRTl1UFQwOVpTWW1LSEl1WW14dlkydGxaRTl1UFc1MWJHd3BmWDFtYjNJb2VuUWhQVDF1ZFd4c0ppWnVjaWg2ZEN4bEtTeEdk'
    || 'Q0U5UFc1MWJHd21KbTV5S0VaMExHVXBMRUYwSVQwOWJuVnNiQ1ltYm5Jb1FYUXNaU2tzWW00dVptOXlSV0ZqYUNoMEtTeGxjaTVtYjNKRllXTm9LSFFwTEc0'
    || 'OU1EdHVQRlYwTG14bGJtZDBhRHR1S3lzcGNqMVZkRnR1WFN4eUxtSnNiMk5yWldSUGJqMDlQV1VtSmloeUxtSnNiMk5yWldSUGJqMXVkV3hzS1R0bWIzSW9P'
    || 'ekE4VlhRdWJHVnVaM1JvSmlZb2JqMVZkRnN3WFN4dUxtSnNiMk5yWldSUGJqMDlQVzUxYkd3cE95bFJjeWh1S1N4dUxtSnNiMk5yWldSUGJqMDlQVzUxYkd3'
    || 'bUpsVjBMbk5vYVdaMEtDbDlkbUZ5SUY5dVBXZGxMbEpsWVdOMFEzVnljbVZ1ZEVKaGRHTm9RMjl1Wm1sbkxGZHlQU0V3TzJaMWJtTjBhVzl1SUU1a0tHVXNk'
    || 'Q3h1TEhJcGUzWmhjaUJzUFhSbExHazlYMjR1ZEhKaGJuTnBkR2x2Ymp0ZmJpNTBjbUZ1YzJsMGFXOXVQVzUxYkd3N2RISjVlM1JsUFRFc2Qya29aU3gwTEc0'
    || 'c2NpbDlabWx1WVd4c2VYdDBaVDFzTEY5dUxuUnlZVzV6YVhScGIyNDlhWDE5Wm5WdVkzUnBiMjRnYW1Rb1pTeDBMRzRzY2lsN2RtRnlJR3c5ZEdVc2FUMWZi'
    || 'aTUwY21GdWMybDBhVzl1TzE5dUxuUnlZVzV6YVhScGIyNDliblZzYkR0MGNubDdkR1U5TkN4M2FTaGxMSFFzYml4eUtYMW1hVzVoYkd4NWUzUmxQV3dzWDI0'
    || 'dWRISmhibk5wZEdsdmJqMXBmWDFtZFc1amRHbHZiaUIzYVNobExIUXNiaXh5S1h0cFppaFhjaWw3ZG1GeUlHdzlYMmtvWlN4MExHNHNjaWs3YVdZb2JEMDlQ'
    || 'VzUxYkd3cFFXa29aU3gwTEhJc1FuSXNiaWtzUW5Nb1pTeHlLVHRsYkhObElHbG1LRVZrS0d3c1pTeDBMRzRzY2lrcGNpNXpkRzl3VUhKdmNHRm5ZWFJwYjI0'
    || 'b0tUdGxiSE5sSUdsbUtFSnpLR1VzY2lrc2RDWTBKaVl0TVR4VFpDNXBibVJsZUU5bUtHVXBLWHRtYjNJb08yd2hQVDF1ZFd4c095bDdkbUZ5SUdrOWJYSW9i'
    || 'Q2s3YVdZb2FTRTlQVzUxYkd3bUppUnpLR2twTEdrOVgya29aU3gwTEc0c2Npa3NhVDA5UFc1MWJHd21Ka0ZwS0dVc2RDeHlMRUp5TEc0cExHazlQVDFzS1dK'
    || 'eVpXRnJPMnc5YVgxc0lUMDliblZzYkNZbWNpNXpkRzl3VUhKdmNHRm5ZWFJwYjI0b0tYMWxiSE5sSUVGcEtHVXNkQ3h5TEc1MWJHd3NiaWw5ZlhaaGNpQkNj'
    || 'ajF1ZFd4c08yWjFibU4wYVc5dUlGOXBLR1VzZEN4dUxISXBlMmxtS0VKeVBXNTFiR3dzWlQxaGFTaHlLU3hsUFhKdUtHVXBMR1VoUFQxdWRXeHNLV2xtS0hR'
    || 'OWJtNG9aU2tzZEQwOVBXNTFiR3dwWlQxdWRXeHNPMlZzYzJVZ2FXWW9iajEwTG5SaFp5eHVQVDA5TVRNcGUybG1LR1U5VEhNb2RDa3NaU0U5UFc1MWJHd3Bj'
    || 'bVYwZFhKdUlHVTdaVDF1ZFd4c2ZXVnNjMlVnYVdZb2JqMDlQVE1wZTJsbUtIUXVjM1JoZEdWT2IyUmxMbU4xY25KbGJuUXViV1Z0YjJsNlpXUlRkR0YwWlM1'
    || 'cGMwUmxhSGxrY21GMFpXUXBjbVYwZFhKdUlIUXVkR0ZuUFQwOU16OTBMbk4wWVhSbFRtOWtaUzVqYjI1MFlXbHVaWEpKYm1adk9tNTFiR3c3WlQxdWRXeHNm'
    || 'V1ZzYzJVZ2RDRTlQV1VtSmlobFBXNTFiR3dwTzNKbGRIVnliaUJDY2oxbExHNTFiR3g5Wm5WdVkzUnBiMjRnUzNNb1pTbDdjM2RwZEdOb0tHVXBlMk5oYzJV'
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
    || 'aU9uSmxkSFZ5YmlBME8yTmhjMlVpYldWemMyRm5aU0k2YzNkcGRHTm9LSEJrS0NrcGUyTmhjMlVnYUdrNmNtVjBkWEp1SURFN1kyRnpaU0I2Y3pweVpYUjFj'
    || 'bTRnTkR0allYTmxJSHB5T21OaGMyVWdhR1E2Y21WMGRYSnVJREUyTzJOaGMyVWdSbk02Y21WMGRYSnVJRFV6TmpnM01Ea3hNanRrWldaaGRXeDBPbkpsZEhW'
    || 'eWJpQXhObjFrWldaaGRXeDBPbkpsZEhWeWJpQXhObjE5ZG1GeUlDUjBQVzUxYkd3c1UyazliblZzYkN4UmNqMXVkV3hzTzJaMWJtTjBhVzl1SUZsektDbDdh'
    || 'V1lvVVhJcGNtVjBkWEp1SUZGeU8zWmhjaUJsTEhROVUya3NiajEwTG14bGJtZDBhQ3h5TEd3OUluWmhiSFZsSW1sdUlDUjBQeVIwTG5aaGJIVmxPaVIwTG5S'
    || 'bGVIUkRiMjUwWlc1MExHazliQzVzWlc1bmRHZzdabTl5S0dVOU1EdGxQRzRtSm5SYlpWMDlQVDFzVzJWZE8yVXJLeWs3ZG1GeUlITTliaTFsTzJadmNpaHlQ'
    || 'VEU3Y2p3OWN5WW1kRnR1TFhKZFBUMDliRnRwTFhKZE8zSXJLeWs3Y21WMGRYSnVJRkZ5UFd3dWMyeHBZMlVvWlN3eFBISS9NUzF5T25admFXUWdNQ2w5Wm5W'
    || 'dVkzUnBiMjRnUjNJb1pTbDdkbUZ5SUhROVpTNXJaWGxEYjJSbE8zSmxkSFZ5YmlKamFHRnlRMjlrWlNKcGJpQmxQeWhsUFdVdVkyaGhja052WkdVc1pUMDlQ'
    || 'VEFtSm5ROVBUMHhNeVltS0dVOU1UTXBLVHBsUFhRc1pUMDlQVEV3SmlZb1pUMHhNeWtzTXpJOFBXVjhmR1U5UFQweE16OWxPakI5Wm5WdVkzUnBiMjRnUzNJ'
    || 'b0tYdHlaWFIxY200aE1IMW1kVzVqZEdsdmJpQlljeWdwZTNKbGRIVnliaUV4ZldaMWJtTjBhVzl1SUZsbEtHVXBlMloxYm1OMGFXOXVJSFFvYml4eUxHd3Nh'
    || 'U3h6S1h0MGFHbHpMbDl5WldGamRFNWhiV1U5Yml4MGFHbHpMbDkwWVhKblpYUkpibk4wUFd3c2RHaHBjeTUwZVhCbFBYSXNkR2hwY3k1dVlYUnBkbVZGZG1W'
    || 'dWREMXBMSFJvYVhNdWRHRnlaMlYwUFhNc2RHaHBjeTVqZFhKeVpXNTBWR0Z5WjJWMFBXNTFiR3c3Wm05eUtIWmhjaUJoSUdsdUlHVXBaUzVvWVhOUGQyNVFj'
    || 'bTl3WlhKMGVTaGhLU1ltS0c0OVpWdGhYU3gwYUdselcyRmRQVzQvYmlocEtUcHBXMkZkS1R0eVpYUjFjbTRnZEdocGN5NXBjMFJsWm1GMWJIUlFjbVYyWlc1'
    || 'MFpXUTlLR2t1WkdWbVlYVnNkRkJ5WlhabGJuUmxaQ0U5Ym5Wc2JEOXBMbVJsWm1GMWJIUlFjbVYyWlc1MFpXUTZhUzV5WlhSMWNtNVdZV3gxWlQwOVBTRXhL'
    || 'VDlMY2pwWWN5eDBhR2x6TG1selVISnZjR0ZuWVhScGIyNVRkRzl3Y0dWa1BWaHpMSFJvYVhOOWNtVjBkWEp1SUUwb2RDNXdjbTkwYjNSNWNHVXNlM0J5Wlha'
    || 'bGJuUkVaV1poZFd4ME9tWjFibU4wYVc5dUtDbDdkR2hwY3k1a1pXWmhkV3gwVUhKbGRtVnVkR1ZrUFNFd08zWmhjaUJ1UFhSb2FYTXVibUYwYVhabFJYWmxi'
    || 'blE3YmlZbUtHNHVjSEpsZG1WdWRFUmxabUYxYkhRL2JpNXdjbVYyWlc1MFJHVm1ZWFZzZENncE9uUjVjR1Z2WmlCdUxuSmxkSFZ5YmxaaGJIVmxJVDBpZFc1'
    || 'cmJtOTNiaUltSmlodUxuSmxkSFZ5YmxaaGJIVmxQU0V4S1N4MGFHbHpMbWx6UkdWbVlYVnNkRkJ5WlhabGJuUmxaRDFMY2lsOUxITjBiM0JRY205d1lXZGhk'
    || 'R2x2YmpwbWRXNWpkR2x2YmlncGUzWmhjaUJ1UFhSb2FYTXVibUYwYVhabFJYWmxiblE3YmlZbUtHNHVjM1J2Y0ZCeWIzQmhaMkYwYVc5dVAyNHVjM1J2Y0ZC'
    || 'eWIzQmhaMkYwYVc5dUtDazZkSGx3Wlc5bUlHNHVZMkZ1WTJWc1FuVmlZbXhsSVQwaWRXNXJibTkzYmlJbUppaHVMbU5oYm1ObGJFSjFZbUpzWlQwaE1Da3Nk'
    || 'R2hwY3k1cGMxQnliM0JoWjJGMGFXOXVVM1J2Y0hCbFpEMUxjaWw5TEhCbGNuTnBjM1E2Wm5WdVkzUnBiMjRvS1h0OUxHbHpVR1Z5YzJsemRHVnVkRHBMY24w'
    || 'cExIUjlkbUZ5SUZOdVBYdGxkbVZ1ZEZCb1lYTmxPakFzWW5WaVlteGxjem93TEdOaGJtTmxiR0ZpYkdVNk1DeDBhVzFsVTNSaGJYQTZablZ1WTNScGIyNG9a'
    || 'U2w3Y21WMGRYSnVJR1V1ZEdsdFpWTjBZVzF3Zkh4RVlYUmxMbTV2ZHlncGZTeGtaV1poZFd4MFVISmxkbVZ1ZEdWa09qQXNhWE5VY25WemRHVmtPakI5TEVW'
    || 'cFBWbGxLRk51S1N4c2NqMU5LSHQ5TEZOdUxIdDJhV1YzT2pBc1pHVjBZV2xzT2pCOUtTeERaRDFaWlNoc2Npa3NhMmtzVG1rc2FYSXNXWEk5VFNoN2ZTeHNj'
    || 'aXg3YzJOeVpXVnVXRG93TEhOamNtVmxibGs2TUN4amJHbGxiblJZT2pBc1kyeHBaVzUwV1Rvd0xIQmhaMlZZT2pBc2NHRm5aVms2TUN4amRISnNTMlY1T2pB'
    || 'c2MyaHBablJMWlhrNk1DeGhiSFJMWlhrNk1DeHRaWFJoUzJWNU9qQXNaMlYwVFc5a2FXWnBaWEpUZEdGMFpUcERhU3hpZFhSMGIyNDZNQ3hpZFhSMGIyNXpP'
    || 'akFzY21Wc1lYUmxaRlJoY21kbGREcG1kVzVqZEdsdmJpaGxLWHR5WlhSMWNtNGdaUzV5Wld4aGRHVmtWR0Z5WjJWMFBUMDlkbTlwWkNBd1AyVXVabkp2YlVW'
    || 'c1pXMWxiblE5UFQxbExuTnlZMFZzWlcxbGJuUS9aUzUwYjBWc1pXMWxiblE2WlM1bWNtOXRSV3hsYldWdWREcGxMbkpsYkdGMFpXUlVZWEpuWlhSOUxHMXZk'
    || 'bVZ0Wlc1MFdEcG1kVzVqZEdsdmJpaGxLWHR5WlhSMWNtNGliVzkyWlcxbGJuUllJbWx1SUdVL1pTNXRiM1psYldWdWRGZzZLR1VoUFQxcGNpWW1LR2x5Smla'
    || 'bExuUjVjR1U5UFQwaWJXOTFjMlZ0YjNabElqOG9hMms5WlM1elkzSmxaVzVZTFdseUxuTmpjbVZsYmxnc1RtazlaUzV6WTNKbFpXNVpMV2x5TG5OamNtVmxi'
    || 'bGtwT2s1cFBXdHBQVEFzYVhJOVpTa3NhMmtwZlN4dGIzWmxiV1Z1ZEZrNlpuVnVZM1JwYjI0b1pTbDdjbVYwZFhKdUltMXZkbVZ0Wlc1MFdTSnBiaUJsUDJV'
    || 'dWJXOTJaVzFsYm5SWk9rNXBmWDBwTEZwelBWbGxLRmx5S1N4VVpEMU5LSHQ5TEZseUxIdGtZWFJoVkhKaGJuTm1aWEk2TUgwcExGSmtQVmxsS0ZSa0tTeE1a'
    || 'RDFOS0h0OUxHeHlMSHR5Wld4aGRHVmtWR0Z5WjJWME9qQjlLU3hxYVQxWlpTaE1aQ2tzVDJROVRTaDdmU3hUYml4N1lXNXBiV0YwYVc5dVRtRnRaVG93TEdW'
    || 'c1lYQnpaV1JVYVcxbE9qQXNjSE5sZFdSdlJXeGxiV1Z1ZERvd2ZTa3NVR1E5V1dVb1QyUXBMRTFrUFUwb2UzMHNVMjRzZTJOc2FYQmliMkZ5WkVSaGRHRTZa'
    || 'blZ1WTNScGIyNG9aU2w3Y21WMGRYSnVJbU5zYVhCaWIyRnlaRVJoZEdFaWFXNGdaVDlsTG1Oc2FYQmliMkZ5WkVSaGRHRTZkMmx1Wkc5M0xtTnNhWEJpYjJG'
    || 'eVpFUmhkR0Y5ZlNrc1NXUTlXV1VvVFdRcExFUmtQVTBvZTMwc1UyNHNlMlJoZEdFNk1IMHBMSEZ6UFZsbEtFUmtLU3g2WkQxN1JYTmpPaUpGYzJOaGNHVWlM'
    || 'Rk53WVdObFltRnlPaUlnSWl4TVpXWjBPaUpCY25KdmQweGxablFpTEZWd09pSkJjbkp2ZDFWd0lpeFNhV2RvZERvaVFYSnliM2RTYVdkb2RDSXNSRzkzYmpv'
    || 'aVFYSnliM2RFYjNkdUlpeEVaV3c2SWtSbGJHVjBaU0lzVjJsdU9pSlBVeUlzVFdWdWRUb2lRMjl1ZEdWNGRFMWxiblVpTEVGd2NITTZJa052Ym5SbGVIUk5a'
    || 'VzUxSWl4VFkzSnZiR3c2SWxOamNtOXNiRXh2WTJzaUxFMXZlbEJ5YVc1MFlXSnNaVXRsZVRvaVZXNXBaR1Z1ZEdsbWFXVmtJbjBzUm1ROWV6ZzZJa0poWTJ0'
    || 'emNHRmpaU0lzT1RvaVZHRmlJaXd4TWpvaVEyeGxZWElpTERFek9pSkZiblJsY2lJc01UWTZJbE5vYVdaMElpd3hOem9pUTI5dWRISnZiQ0lzTVRnNklrRnNk'
    || 'Q0lzTVRrNklsQmhkWE5sSWl3eU1Eb2lRMkZ3YzB4dlkyc2lMREkzT2lKRmMyTmhjR1VpTERNeU9pSWdJaXd6TXpvaVVHRm5aVlZ3SWl3ek5Eb2lVR0ZuWlVS'
    || 'dmQyNGlMRE0xT2lKRmJtUWlMRE0yT2lKSWIyMWxJaXd6TnpvaVFYSnliM2RNWldaMElpd3pPRG9pUVhKeWIzZFZjQ0lzTXprNklrRnljbTkzVW1sbmFIUWlM'
    || 'RFF3T2lKQmNuSnZkMFJ2ZDI0aUxEUTFPaUpKYm5ObGNuUWlMRFEyT2lKRVpXeGxkR1VpTERFeE1qb2lSakVpTERFeE16b2lSaklpTERFeE5Eb2lSak1pTERF'
    || 'eE5Ub2lSalFpTERFeE5qb2lSalVpTERFeE56b2lSallpTERFeE9Eb2lSamNpTERFeE9Ub2lSamdpTERFeU1Eb2lSamtpTERFeU1Ub2lSakV3SWl3eE1qSTZJ'
    || 'a1l4TVNJc01USXpPaUpHTVRJaUxERTBORG9pVG5WdFRHOWpheUlzTVRRMU9pSlRZM0p2Ykd4TWIyTnJJaXd5TWpRNklrMWxkR0VpZlN4QlpEMTdRV3gwT2lK'
    || 'aGJIUkxaWGtpTEVOdmJuUnliMnc2SW1OMGNteExaWGtpTEUxbGRHRTZJbTFsZEdGTFpYa2lMRk5vYVdaME9pSnphR2xtZEV0bGVTSjlPMloxYm1OMGFXOXVJ'
    || 'RlZrS0dVcGUzWmhjaUIwUFhSb2FYTXVibUYwYVhabFJYWmxiblE3Y21WMGRYSnVJSFF1WjJWMFRXOWthV1pwWlhKVGRHRjBaVDkwTG1kbGRFMXZaR2xtYVdW'
    || 'eVUzUmhkR1VvWlNrNktHVTlRV1JiWlYwcFB5RWhkRnRsWFRvaE1YMW1kVzVqZEdsdmJpQkRhU2dwZTNKbGRIVnliaUJWWkgxMllYSWdKR1E5VFNoN2ZTeHNj'
    || 'aXg3YTJWNU9tWjFibU4wYVc5dUtHVXBlMmxtS0dVdWEyVjVLWHQyWVhJZ2REMTZaRnRsTG10bGVWMThmR1V1YTJWNU8ybG1LSFFoUFQwaVZXNXBaR1Z1ZEds'
    || 'bWFXVmtJaWx5WlhSMWNtNGdkSDF5WlhSMWNtNGdaUzUwZVhCbFBUMDlJbXRsZVhCeVpYTnpJajhvWlQxSGNpaGxLU3hsUFQwOU1UTS9Ja1Z1ZEdWeUlqcFRk'
    || 'SEpwYm1jdVpuSnZiVU5vWVhKRGIyUmxLR1VwS1RwbExuUjVjR1U5UFQwaWEyVjVaRzkzYmlKOGZHVXVkSGx3WlQwOVBTSnJaWGwxY0NJL1JtUmJaUzVyWlhs'
    || 'RGIyUmxYWHg4SWxWdWFXUmxiblJwWm1sbFpDSTZJaUo5TEdOdlpHVTZNQ3hzYjJOaGRHbHZiam93TEdOMGNteExaWGs2TUN4emFHbG1kRXRsZVRvd0xHRnNk'
    || 'RXRsZVRvd0xHMWxkR0ZMWlhrNk1DeHlaWEJsWVhRNk1DeHNiMk5oYkdVNk1DeG5aWFJOYjJScFptbGxjbE4wWVhSbE9rTnBMR05vWVhKRGIyUmxPbVoxYm1O'
    || 'MGFXOXVLR1VwZTNKbGRIVnliaUJsTG5SNWNHVTlQVDBpYTJWNWNISmxjM01pUDBkeUtHVXBPakI5TEd0bGVVTnZaR1U2Wm5WdVkzUnBiMjRvWlNsN2NtVjBk'
    || 'WEp1SUdVdWRIbHdaVDA5UFNKclpYbGtiM2R1SW54OFpTNTBlWEJsUFQwOUltdGxlWFZ3SWo5bExtdGxlVU52WkdVNk1IMHNkMmhwWTJnNlpuVnVZM1JwYjI0'
    || 'b1pTbDdjbVYwZFhKdUlHVXVkSGx3WlQwOVBTSnJaWGx3Y21WemN5SS9SM0lvWlNrNlpTNTBlWEJsUFQwOUltdGxlV1J2ZDI0aWZIeGxMblI1Y0dVOVBUMGlh'
    || 'MlY1ZFhBaVAyVXVhMlY1UTI5a1pUb3dmWDBwTEVoa1BWbGxLQ1JrS1N4V1pEMU5LSHQ5TEZseUxIdHdiMmx1ZEdWeVNXUTZNQ3gzYVdSMGFEb3dMR2hsYVdk'
    || 'b2REb3dMSEJ5WlhOemRYSmxPakFzZEdGdVoyVnVkR2xoYkZCeVpYTnpkWEpsT2pBc2RHbHNkRmc2TUN4MGFXeDBXVG93TEhSM2FYTjBPakFzY0c5cGJuUmxj'
    || 'bFI1Y0dVNk1DeHBjMUJ5YVcxaGNuazZNSDBwTEVwelBWbGxLRlprS1N4WFpEMU5LSHQ5TEd4eUxIdDBiM1ZqYUdWek9qQXNkR0Z5WjJWMFZHOTFZMmhsY3pv'
    || 'd0xHTm9ZVzVuWldSVWIzVmphR1Z6T2pBc1lXeDBTMlY1T2pBc2JXVjBZVXRsZVRvd0xHTjBjbXhMWlhrNk1DeHphR2xtZEV0bGVUb3dMR2RsZEUxdlpHbG1h'
    || 'V1Z5VTNSaGRHVTZRMmw5S1N4Q1pEMVpaU2hYWkNrc1VXUTlUU2g3ZlN4VGJpeDdjSEp2Y0dWeWRIbE9ZVzFsT2pBc1pXeGhjSE5sWkZScGJXVTZNQ3h3YzJW'
    || 'MVpHOUZiR1Z0Wlc1ME9qQjlLU3hIWkQxWlpTaFJaQ2tzUzJROVRTaDdmU3haY2l4N1pHVnNkR0ZZT21aMWJtTjBhVzl1S0dVcGUzSmxkSFZ5YmlKa1pXeDBZ'
    || 'VmdpYVc0Z1pUOWxMbVJsYkhSaFdEb2lkMmhsWld4RVpXeDBZVmdpYVc0Z1pUOHRaUzUzYUdWbGJFUmxiSFJoV0Rvd2ZTeGtaV3gwWVZrNlpuVnVZM1JwYjI0'
    || 'b1pTbDdjbVYwZFhKdUltUmxiSFJoV1NKcGJpQmxQMlV1WkdWc2RHRlpPaUozYUdWbGJFUmxiSFJoV1NKcGJpQmxQeTFsTG5kb1pXVnNSR1ZzZEdGWk9pSjNh'
    || 'R1ZsYkVSbGJIUmhJbWx1SUdVL0xXVXVkMmhsWld4RVpXeDBZVG93ZlN4a1pXeDBZVm82TUN4a1pXeDBZVTF2WkdVNk1IMHBMRmxrUFZsbEtFdGtLU3hZWkQx'
    || 'Yk9Td3hNeXd5Tnl3ek1sMHNWR2s5VGlZbUlrTnZiWEJ2YzJsMGFXOXVSWFpsYm5RaWFXNGdkMmx1Wkc5M0xHOXlQVzUxYkd3N1RpWW1JbVJ2WTNWdFpXNTBU'
    || 'VzlrWlNKcGJpQmtiMk4xYldWdWRDWW1LRzl5UFdSdlkzVnRaVzUwTG1SdlkzVnRaVzUwVFc5a1pTazdkbUZ5SUZwa1BVNG1KaUpVWlhoMFJYWmxiblFpYVc0'
    || 'Z2QybHVaRzkzSmlZaGIzSXNZbk05VGlZbUtDRlVhWHg4YjNJbUpqZzhiM0ltSmpFeFBqMXZjaWtzWlhVOUlpQWlMSFIxUFNFeE8yWjFibU4wYVc5dUlHNTFL'
    || 'R1VzZENsN2MzZHBkR05vS0dVcGUyTmhjMlVpYTJWNWRYQWlPbkpsZEhWeWJpQllaQzVwYm1SbGVFOW1LSFF1YTJWNVEyOWtaU2toUFQwdE1UdGpZWE5sSW10'
    || 'bGVXUnZkMjRpT25KbGRIVnliaUIwTG10bGVVTnZaR1VoUFQweU1qazdZMkZ6WlNKclpYbHdjbVZ6Y3lJNlkyRnpaU0p0YjNWelpXUnZkMjRpT21OaGMyVWla'
    || 'bTlqZFhOdmRYUWlPbkpsZEhWeWJpRXdPMlJsWm1GMWJIUTZjbVYwZFhKdUlURjlmV1oxYm1OMGFXOXVJSEoxS0dVcGUzSmxkSFZ5YmlCbFBXVXVaR1YwWVds'
    || 'c0xIUjVjR1Z2WmlCbFBUMGliMkpxWldOMElpWW1JbVJoZEdFaWFXNGdaVDlsTG1SaGRHRTZiblZzYkgxMllYSWdSVzQ5SVRFN1puVnVZM1JwYjI0Z2NXUW9a'
    || 'U3gwS1h0emQybDBZMmdvWlNsN1kyRnpaU0pqYjIxd2IzTnBkR2x2Ym1WdVpDSTZjbVYwZFhKdUlISjFLSFFwTzJOaGMyVWlhMlY1Y0hKbGMzTWlPbkpsZEhW'
    || 'eWJpQjBMbmRvYVdOb0lUMDlNekkvYm5Wc2JEb29kSFU5SVRBc1pYVXBPMk5oYzJVaWRHVjRkRWx1Y0hWMElqcHlaWFIxY200Z1pUMTBMbVJoZEdFc1pUMDlQ'
    || 'V1YxSmlaMGRUOXVkV3hzT21VN1pHVm1ZWFZzZERweVpYUjFjbTRnYm5Wc2JIMTlablZ1WTNScGIyNGdTbVFvWlN4MEtYdHBaaWhGYmlseVpYUjFjbTRnWlQw'
    || 'OVBTSmpiMjF3YjNOcGRHbHZibVZ1WkNKOGZDRlVhU1ltYm5Vb1pTeDBLVDhvWlQxWmN5Z3BMRkZ5UFZOcFBTUjBQVzUxYkd3c1JXNDlJVEVzWlNrNmJuVnNi'
    || 'RHR6ZDJsMFkyZ29aU2w3WTJGelpTSndZWE4wWlNJNmNtVjBkWEp1SUc1MWJHdzdZMkZ6WlNKclpYbHdjbVZ6Y3lJNmFXWW9JU2gwTG1OMGNteExaWGw4ZkhR'
    || 'dVlXeDBTMlY1Zkh4MExtMWxkR0ZMWlhrcGZIeDBMbU4wY214TFpYa21KblF1WVd4MFMyVjVLWHRwWmloMExtTm9ZWEltSmpFOGRDNWphR0Z5TG14bGJtZDBh'
    || 'Q2x5WlhSMWNtNGdkQzVqYUdGeU8ybG1LSFF1ZDJocFkyZ3BjbVYwZFhKdUlGTjBjbWx1Wnk1bWNtOXRRMmhoY2tOdlpHVW9kQzUzYUdsamFDbDljbVYwZFhK'
    || 'dUlHNTFiR3c3WTJGelpTSmpiMjF3YjNOcGRHbHZibVZ1WkNJNmNtVjBkWEp1SUdKekppWjBMbXh2WTJGc1pTRTlQU0pyYnlJL2JuVnNiRHAwTG1SaGRHRTda'
    || 'R1ZtWVhWc2REcHlaWFIxY200Z2JuVnNiSDE5ZG1GeUlHSmtQWHRqYjJ4dmNqb2hNQ3hrWVhSbE9pRXdMR1JoZEdWMGFXMWxPaUV3TENKa1lYUmxkR2x0WlMx'
    || 'c2IyTmhiQ0k2SVRBc1pXMWhhV3c2SVRBc2JXOXVkR2c2SVRBc2JuVnRZbVZ5T2lFd0xIQmhjM04zYjNKa09pRXdMSEpoYm1kbE9pRXdMSE5sWVhKamFEb2hN'
    || 'Q3gwWld3NklUQXNkR1Y0ZERvaE1DeDBhVzFsT2lFd0xIVnliRG9oTUN4M1pXVnJPaUV3ZlR0bWRXNWpkR2x2YmlCc2RTaGxLWHQyWVhJZ2REMWxKaVpsTG01'
    || 'dlpHVk9ZVzFsSmlabExtNXZaR1ZPWVcxbExuUnZURzkzWlhKRFlYTmxLQ2s3Y21WMGRYSnVJSFE5UFQwaWFXNXdkWFFpUHlFaFltUmJaUzUwZVhCbFhUcDBQ'
    || 'VDA5SW5SbGVIUmhjbVZoSW4xbWRXNWpkR2x2YmlCcGRTaGxMSFFzYml4eUtYdE9jeWh5S1N4MFBXSnlLSFFzSW05dVEyaGhibWRsSWlrc01EeDBMbXhsYm1k'
    || 'MGFDWW1LRzQ5Ym1WM0lFVnBLQ0p2YmtOb1lXNW5aU0lzSW1Ob1lXNW5aU0lzYm5Wc2JDeHVMSElwTEdVdWNIVnphQ2g3WlhabGJuUTZiaXhzYVhOMFpXNWxj'
    || 'bk02ZEgwcEtYMTJZWElnYzNJOWJuVnNiQ3gxY2oxdWRXeHNPMloxYm1OMGFXOXVJR1ZtS0dVcGUwVjFLR1VzTUNsOVpuVnVZM1JwYjI0Z1dISW9aU2w3ZG1G'
    || 'eUlIUTlWRzRvWlNrN2FXWW9jSE1vZENrcGNtVjBkWEp1SUdWOVpuVnVZM1JwYjI0Z2RHWW9aU3gwS1h0cFppaGxQVDA5SW1Ob1lXNW5aU0lwY21WMGRYSnVJ'
    || 'SFI5ZG1GeUlHOTFQU0V4TzJsbUtFNHBlM1poY2lCU2FUdHBaaWhPS1h0MllYSWdUR2s5SW05dWFXNXdkWFFpYVc0Z1pHOWpkVzFsYm5RN2FXWW9JVXhwS1h0'
    || 'MllYSWdjM1U5Wkc5amRXMWxiblF1WTNKbFlYUmxSV3hsYldWdWRDZ2laR2wySWlrN2MzVXVjMlYwUVhSMGNtbGlkWFJsS0NKdmJtbHVjSFYwSWl3aWNtVjBk'
    || 'WEp1T3lJcExFeHBQWFI1Y0dWdlppQnpkUzV2Ym1sdWNIVjBQVDBpWm5WdVkzUnBiMjRpZlZKcFBVeHBmV1ZzYzJVZ1VtazlJVEU3YjNVOVVta21KaWdoWkc5'
    || 'amRXMWxiblF1Wkc5amRXMWxiblJOYjJSbGZIdzVQR1J2WTNWdFpXNTBMbVJ2WTNWdFpXNTBUVzlrWlNsOVpuVnVZM1JwYjI0Z2RYVW9LWHR6Y2lZbUtITnlM'
    || 'bVJsZEdGamFFVjJaVzUwS0NKdmJuQnliM0JsY25SNVkyaGhibWRsSWl4aGRTa3NkWEk5YzNJOWJuVnNiQ2w5Wm5WdVkzUnBiMjRnWVhVb1pTbDdhV1lvWlM1'
    || 'd2NtOXdaWEowZVU1aGJXVTlQVDBpZG1Gc2RXVWlKaVpZY2loMWNpa3BlM1poY2lCMFBWdGRPMmwxS0hRc2RYSXNaU3hoYVNobEtTa3NVbk1vWldZc2RDbDlm'
    || 'V1oxYm1OMGFXOXVJRzVtS0dVc2RDeHVLWHRsUFQwOUltWnZZM1Z6YVc0aVB5aDFkU2dwTEhOeVBYUXNkWEk5Yml4emNpNWhkSFJoWTJoRmRtVnVkQ2dpYjI1'
    || 'd2NtOXdaWEowZVdOb1lXNW5aU0lzWVhVcEtUcGxQVDA5SW1adlkzVnpiM1YwSWlZbWRYVW9LWDFtZFc1amRHbHZiaUJ5WmlobEtYdHBaaWhsUFQwOUluTmxi'
    || 'R1ZqZEdsdmJtTm9ZVzVuWlNKOGZHVTlQVDBpYTJWNWRYQWlmSHhsUFQwOUltdGxlV1J2ZDI0aUtYSmxkSFZ5YmlCWWNpaDFjaWw5Wm5WdVkzUnBiMjRnYkdZ'
    || 'b1pTeDBLWHRwWmlobFBUMDlJbU5zYVdOcklpbHlaWFIxY200Z1dISW9kQ2w5Wm5WdVkzUnBiMjRnYjJZb1pTeDBLWHRwWmlobFBUMDlJbWx1Y0hWMElueDha'
    || 'VDA5UFNKamFHRnVaMlVpS1hKbGRIVnliaUJZY2loMEtYMW1kVzVqZEdsdmJpQnpaaWhsTEhRcGUzSmxkSFZ5YmlCbFBUMDlkQ1ltS0dVaFBUMHdmSHd4TDJV'
    || 'OVBUMHhMM1FwZkh4bElUMDlaU1ltZENFOVBYUjlkbUZ5SUdOMFBYUjVjR1Z2WmlCUFltcGxZM1F1YVhNOVBTSm1kVzVqZEdsdmJpSS9UMkpxWldOMExtbHpP'
    || 'bk5tTzJaMWJtTjBhVzl1SUdGeUtHVXNkQ2w3YVdZb1kzUW9aU3gwS1NseVpYUjFjbTRoTUR0cFppaDBlWEJsYjJZZ1pTRTlJbTlpYW1WamRDSjhmR1U5UFQx'
    || 'dWRXeHNmSHgwZVhCbGIyWWdkQ0U5SW05aWFtVmpkQ0o4ZkhROVBUMXVkV3hzS1hKbGRIVnliaUV4TzNaaGNpQnVQVTlpYW1WamRDNXJaWGx6S0dVcExISTlU'
    || 'MkpxWldOMExtdGxlWE1vZENrN2FXWW9iaTVzWlc1bmRHZ2hQVDF5TG14bGJtZDBhQ2x5WlhSMWNtNGhNVHRtYjNJb2NqMHdPM0k4Ymk1c1pXNW5kR2c3Y2lz'
    || 'cktYdDJZWElnYkQxdVczSmRPMmxtS0NGcUxtTmhiR3dvZEN4c0tYeDhJV04wS0dWYmJGMHNkRnRzWFNrcGNtVjBkWEp1SVRGOWNtVjBkWEp1SVRCOVpuVnVZ'
    || 'M1JwYjI0Z1kzVW9aU2w3Wm05eUtEdGxKaVpsTG1acGNuTjBRMmhwYkdRN0tXVTlaUzVtYVhKemRFTm9hV3hrTzNKbGRIVnliaUJsZldaMWJtTjBhVzl1SUdS'
    || 'MUtHVXNkQ2w3ZG1GeUlHNDlZM1VvWlNrN1pUMHdPMlp2Y2loMllYSWdjanR1T3lsN2FXWW9iaTV1YjJSbFZIbHdaVDA5UFRNcGUybG1LSEk5WlN0dUxuUmxl'
    || 'SFJEYjI1MFpXNTBMbXhsYm1kMGFDeGxQRDEwSmlaeVBqMTBLWEpsZEhWeWJudHViMlJsT200c2IyWm1jMlYwT25RdFpYMDdaVDF5ZldVNmUyWnZjaWc3Ympz'
    || 'cGUybG1LRzR1Ym1WNGRGTnBZbXhwYm1jcGUyNDliaTV1WlhoMFUybGliR2x1Wnp0aWNtVmhheUJsZlc0OWJpNXdZWEpsYm5ST2IyUmxmVzQ5ZG05cFpDQXdm'
    || 'VzQ5WTNVb2JpbDlmV1oxYm1OMGFXOXVJR1oxS0dVc2RDbDdjbVYwZFhKdUlHVW1KblEvWlQwOVBYUS9JVEE2WlNZbVpTNXViMlJsVkhsd1pUMDlQVE0vSVRF'
    || 'NmRDWW1kQzV1YjJSbFZIbHdaVDA5UFRNL1puVW9aU3gwTG5CaGNtVnVkRTV2WkdVcE9pSmpiMjUwWVdsdWN5SnBiaUJsUDJVdVkyOXVkR0ZwYm5Nb2RDazZa'
    || 'UzVqYjIxd1lYSmxSRzlqZFcxbGJuUlFiM05wZEdsdmJqOGhJU2hsTG1OdmJYQmhjbVZFYjJOMWJXVnVkRkJ2YzJsMGFXOXVLSFFwSmpFMktUb2hNVG9oTVgx'
    || 'bWRXNWpkR2x2YmlCd2RTZ3BlMlp2Y2loMllYSWdaVDEzYVc1a2IzY3NkRDFRY2lncE8zUWdhVzV6ZEdGdVkyVnZaaUJsTGtoVVRVeEpSbkpoYldWRmJHVnRa'
    || 'VzUwT3lsN2RISjVlM1poY2lCdVBYUjVjR1Z2WmlCMExtTnZiblJsYm5SWGFXNWtiM2N1Ykc5allYUnBiMjR1YUhKbFpqMDlJbk4wY21sdVp5SjlZMkYwWTJo'
    || 'N2JqMGhNWDFwWmlodUtXVTlkQzVqYjI1MFpXNTBWMmx1Wkc5M08yVnNjMlVnWW5KbFlXczdkRDFRY2lobExtUnZZM1Z0Wlc1MEtYMXlaWFIxY200Z2RIMW1k'
    || 'VzVqZEdsdmJpQlBhU2hsS1h0MllYSWdkRDFsSmlabExtNXZaR1ZPWVcxbEppWmxMbTV2WkdWT1lXMWxMblJ2VEc5M1pYSkRZWE5sS0NrN2NtVjBkWEp1SUhR'
    || 'bUppaDBQVDA5SW1sdWNIVjBJaVltS0dVdWRIbHdaVDA5UFNKMFpYaDBJbng4WlM1MGVYQmxQVDA5SW5ObFlYSmphQ0o4ZkdVdWRIbHdaVDA5UFNKMFpXd2lm'
    || 'SHhsTG5SNWNHVTlQVDBpZFhKc0lueDhaUzUwZVhCbFBUMDlJbkJoYzNOM2IzSmtJaWw4ZkhROVBUMGlkR1Y0ZEdGeVpXRWlmSHhsTG1OdmJuUmxiblJGWkds'
    || 'MFlXSnNaVDA5UFNKMGNuVmxJaWw5Wm5WdVkzUnBiMjRnZFdZb1pTbDdkbUZ5SUhROWNIVW9LU3h1UFdVdVptOWpkWE5sWkVWc1pXMHNjajFsTG5ObGJHVmpk'
    || 'R2x2YmxKaGJtZGxPMmxtS0hRaFBUMXVKaVp1SmladUxtOTNibVZ5Ukc5amRXMWxiblFtSm1aMUtHNHViM2R1WlhKRWIyTjFiV1Z1ZEM1a2IyTjFiV1Z1ZEVW'
    || 'c1pXMWxiblFzYmlrcGUybG1LSEloUFQxdWRXeHNKaVpQYVNodUtTbDdhV1lvZEQxeUxuTjBZWEowTEdVOWNpNWxibVFzWlQwOVBYWnZhV1FnTUNZbUtHVTlk'
    || 'Q2tzSW5ObGJHVmpkR2x2YmxOMFlYSjBJbWx1SUc0cGJpNXpaV3hsWTNScGIyNVRkR0Z5ZEQxMExHNHVjMlZzWldOMGFXOXVSVzVrUFUxaGRHZ3ViV2x1S0dV'
    || 'c2JpNTJZV3gxWlM1c1pXNW5kR2dwTzJWc2MyVWdhV1lvWlQwb2REMXVMbTkzYm1WeVJHOWpkVzFsYm5SOGZHUnZZM1Z0Wlc1MEtTWW1kQzVrWldaaGRXeDBW'
    || 'bWxsZDN4OGQybHVaRzkzTEdVdVoyVjBVMlZzWldOMGFXOXVLWHRsUFdVdVoyVjBVMlZzWldOMGFXOXVLQ2s3ZG1GeUlHdzliaTUwWlhoMFEyOXVkR1Z1ZEM1'
    || 'c1pXNW5kR2dzYVQxTllYUm9MbTFwYmloeUxuTjBZWEowTEd3cE8zSTljaTVsYm1ROVBUMTJiMmxrSURBL2FUcE5ZWFJvTG0xcGJpaHlMbVZ1WkN4c0tTd2ha'
    || 'UzVsZUhSbGJtUW1KbWsrY2lZbUtHdzljaXh5UFdrc2FUMXNLU3hzUFdSMUtHNHNhU2s3ZG1GeUlITTlaSFVvYml4eUtUdHNKaVp6SmlZb1pTNXlZVzVuWlVO'
    || 'dmRXNTBJVDA5TVh4OFpTNWhibU5vYjNKT2IyUmxJVDA5YkM1dWIyUmxmSHhsTG1GdVkyaHZjazltWm5ObGRDRTlQV3d1YjJabWMyVjBmSHhsTG1adlkzVnpU'
    || 'bTlrWlNFOVBYTXVibTlrWlh4OFpTNW1iMk4xYzA5bVpuTmxkQ0U5UFhNdWIyWm1jMlYwS1NZbUtIUTlkQzVqY21WaGRHVlNZVzVuWlNncExIUXVjMlYwVTNS'
    || 'aGNuUW9iQzV1YjJSbExHd3ViMlptYzJWMEtTeGxMbkpsYlc5MlpVRnNiRkpoYm1kbGN5Z3BMR2srY2o4b1pTNWhaR1JTWVc1blpTaDBLU3hsTG1WNGRHVnVa'
    || 'Q2h6TG01dlpHVXNjeTV2Wm1aelpYUXBLVG9vZEM1elpYUkZibVFvY3k1dWIyUmxMSE11YjJabWMyVjBLU3hsTG1Ga1pGSmhibWRsS0hRcEtTbDlmV1p2Y2lo'
    || 'MFBWdGRMR1U5Ymp0bFBXVXVjR0Z5Wlc1MFRtOWtaVHNwWlM1dWIyUmxWSGx3WlQwOVBURW1KblF1Y0hWemFDaDdaV3hsYldWdWREcGxMR3hsWm5RNlpTNXpZ'
    || 'M0p2Ykd4TVpXWjBMSFJ2Y0RwbExuTmpjbTlzYkZSdmNIMHBPMlp2Y2loMGVYQmxiMllnYmk1bWIyTjFjejA5SW1aMWJtTjBhVzl1SWlZbWJpNW1iMk4xY3ln'
    || 'cExHNDlNRHR1UEhRdWJHVnVaM1JvTzI0ckt5bGxQWFJiYmwwc1pTNWxiR1Z0Wlc1MExuTmpjbTlzYkV4bFpuUTlaUzVzWldaMExHVXVaV3hsYldWdWRDNXpZ'
    || 'M0p2Ykd4VWIzQTlaUzUwYjNCOWZYWmhjaUJoWmoxT0ppWWlaRzlqZFcxbGJuUk5iMlJsSW1sdUlHUnZZM1Z0Wlc1MEppWXhNVDQ5Wkc5amRXMWxiblF1Wkc5'
    || 'amRXMWxiblJOYjJSbExHdHVQVzUxYkd3c1VHazliblZzYkN4amNqMXVkV3hzTEUxcFBTRXhPMloxYm1OMGFXOXVJR2gxS0dVc2RDeHVLWHQyWVhJZ2NqMXVM'
    || 'bmRwYm1SdmR6MDlQVzQvYmk1a2IyTjFiV1Z1ZERwdUxtNXZaR1ZVZVhCbFBUMDlPVDl1T200dWIzZHVaWEpFYjJOMWJXVnVkRHROYVh4OGEyNDlQVzUxYkd4'
    || 'OGZHdHVJVDA5VUhJb2NpbDhmQ2h5UFd0dUxDSnpaV3hsWTNScGIyNVRkR0Z5ZENKcGJpQnlKaVpQYVNoeUtUOXlQWHR6ZEdGeWREcHlMbk5sYkdWamRHbHZi'
    || 'bE4wWVhKMExHVnVaRHB5TG5ObGJHVmpkR2x2YmtWdVpIMDZLSEk5S0hJdWIzZHVaWEpFYjJOMWJXVnVkQ1ltY2k1dmQyNWxja1J2WTNWdFpXNTBMbVJsWm1G'
    || 'MWJIUldhV1YzZkh4M2FXNWtiM2NwTG1kbGRGTmxiR1ZqZEdsdmJpZ3BMSEk5ZTJGdVkyaHZjazV2WkdVNmNpNWhibU5vYjNKT2IyUmxMR0Z1WTJodmNrOW1a'
    || 'bk5sZERweUxtRnVZMmh2Y2s5bVpuTmxkQ3htYjJOMWMwNXZaR1U2Y2k1bWIyTjFjMDV2WkdVc1ptOWpkWE5QWm1aelpYUTZjaTVtYjJOMWMwOW1abk5sZEgw'
    || 'cExHTnlKaVpoY2loamNpeHlLWHg4S0dOeVBYSXNjajFpY2loUWFTd2liMjVUWld4bFkzUWlLU3d3UEhJdWJHVnVaM1JvSmlZb2REMXVaWGNnUldrb0ltOXVV'
    || 'MlZzWldOMElpd2ljMlZzWldOMElpeHVkV3hzTEhRc2Jpa3NaUzV3ZFhOb0tIdGxkbVZ1ZERwMExHeHBjM1JsYm1WeWN6cHlmU2tzZEM1MFlYSm5aWFE5YTI0'
    || 'cEtTbDlablZ1WTNScGIyNGdXbklvWlN4MEtYdDJZWElnYmoxN2ZUdHlaWFIxY200Z2JsdGxMblJ2VEc5M1pYSkRZWE5sS0NsZFBYUXVkRzlNYjNkbGNrTmhj'
    || 'MlVvS1N4dVd5SlhaV0pyYVhRaUsyVmRQU0ozWldKcmFYUWlLM1FzYmxzaVRXOTZJaXRsWFQwaWJXOTZJaXQwTEc1OWRtRnlJRTV1UFh0aGJtbHRZWFJwYjI1'
    || 'bGJtUTZXbklvSWtGdWFXMWhkR2x2YmlJc0lrRnVhVzFoZEdsdmJrVnVaQ0lwTEdGdWFXMWhkR2x2Ym1sMFpYSmhkR2x2YmpwYWNpZ2lRVzVwYldGMGFXOXVJ'
    || 'aXdpUVc1cGJXRjBhVzl1U1hSbGNtRjBhVzl1SWlrc1lXNXBiV0YwYVc5dWMzUmhjblE2V25Jb0lrRnVhVzFoZEdsdmJpSXNJa0Z1YVcxaGRHbHZibE4wWVhK'
    || 'MElpa3NkSEpoYm5OcGRHbHZibVZ1WkRwYWNpZ2lWSEpoYm5OcGRHbHZiaUlzSWxSeVlXNXphWFJwYjI1RmJtUWlLWDBzU1drOWUzMHNiWFU5ZTMwN1RpWW1L'
    || 'RzExUFdSdlkzVnRaVzUwTG1OeVpXRjBaVVZzWlcxbGJuUW9JbVJwZGlJcExuTjBlV3hsTENKQmJtbHRZWFJwYjI1RmRtVnVkQ0pwYmlCM2FXNWtiM2Q4ZkNo'
    || 'a1pXeGxkR1VnVG00dVlXNXBiV0YwYVc5dVpXNWtMbUZ1YVcxaGRHbHZiaXhrWld4bGRHVWdUbTR1WVc1cGJXRjBhVzl1YVhSbGNtRjBhVzl1TG1GdWFXMWhk'
    || 'R2x2Yml4a1pXeGxkR1VnVG00dVlXNXBiV0YwYVc5dWMzUmhjblF1WVc1cGJXRjBhVzl1S1N3aVZISmhibk5wZEdsdmJrVjJaVzUwSW1sdUlIZHBibVJ2ZDN4'
    || 'OFpHVnNaWFJsSUU1dUxuUnlZVzV6YVhScGIyNWxibVF1ZEhKaGJuTnBkR2x2YmlrN1puVnVZM1JwYjI0Z2NYSW9aU2w3YVdZb1NXbGJaVjBwY21WMGRYSnVJ'
    || 'RWxwVzJWZE8ybG1LQ0ZPYmx0bFhTbHlaWFIxY200Z1pUdDJZWElnZEQxT2JsdGxYU3h1TzJadmNpaHVJR2x1SUhRcGFXWW9kQzVvWVhOUGQyNVFjbTl3WlhK'
    || 'MGVTaHVLU1ltYmlCcGJpQnRkU2x5WlhSMWNtNGdTV2xiWlYwOWRGdHVYVHR5WlhSMWNtNGdaWDEyWVhJZ2RuVTljWElvSW1GdWFXMWhkR2x2Ym1WdVpDSXBM'
    || 'R2QxUFhGeUtDSmhibWx0WVhScGIyNXBkR1Z5WVhScGIyNGlLU3g1ZFQxeGNpZ2lZVzVwYldGMGFXOXVjM1JoY25RaUtTeDRkVDF4Y2lnaWRISmhibk5wZEds'
    || 'dmJtVnVaQ0lwTEhkMVBXNWxkeUJOWVhBc1gzVTlJbUZpYjNKMElHRjFlRU5zYVdOcklHTmhibU5sYkNCallXNVFiR0Y1SUdOaGJsQnNZWGxVYUhKdmRXZG9J'
    || 'R05zYVdOcklHTnNiM05sSUdOdmJuUmxlSFJOWlc1MUlHTnZjSGtnWTNWMElHUnlZV2NnWkhKaFowVnVaQ0JrY21GblJXNTBaWElnWkhKaFowVjRhWFFnWkhK'
    || 'aFoweGxZWFpsSUdSeVlXZFBkbVZ5SUdSeVlXZFRkR0Z5ZENCa2NtOXdJR1IxY21GMGFXOXVRMmhoYm1kbElHVnRjSFJwWldRZ1pXNWpjbmx3ZEdWa0lHVnVa'
    || 'R1ZrSUdWeWNtOXlJR2R2ZEZCdmFXNTBaWEpEWVhCMGRYSmxJR2x1Y0hWMElHbHVkbUZzYVdRZ2EyVjVSRzkzYmlCclpYbFFjbVZ6Y3lCclpYbFZjQ0JzYjJG'
    || 'a0lHeHZZV1JsWkVSaGRHRWdiRzloWkdWa1RXVjBZV1JoZEdFZ2JHOWhaRk4wWVhKMElHeHZjM1JRYjJsdWRHVnlRMkZ3ZEhWeVpTQnRiM1Z6WlVSdmQyNGdi'
    || 'VzkxYzJWTmIzWmxJRzF2ZFhObFQzVjBJRzF2ZFhObFQzWmxjaUJ0YjNWelpWVndJSEJoYzNSbElIQmhkWE5sSUhCc1lYa2djR3hoZVdsdVp5QndiMmx1ZEdW'
    || 'eVEyRnVZMlZzSUhCdmFXNTBaWEpFYjNkdUlIQnZhVzUwWlhKTmIzWmxJSEJ2YVc1MFpYSlBkWFFnY0c5cGJuUmxjazkyWlhJZ2NHOXBiblJsY2xWd0lIQnli'
    || 'MmR5WlhOeklISmhkR1ZEYUdGdVoyVWdjbVZ6WlhRZ2NtVnphWHBsSUhObFpXdGxaQ0J6WldWcmFXNW5JSE4wWVd4c1pXUWdjM1ZpYldsMElITjFjM0JsYm1R'
    || 'Z2RHbHRaVlZ3WkdGMFpTQjBiM1ZqYUVOaGJtTmxiQ0IwYjNWamFFVnVaQ0IwYjNWamFGTjBZWEowSUhadmJIVnRaVU5vWVc1blpTQnpZM0p2Ykd3Z2RHOW5a'
    || 'MnhsSUhSdmRXTm9UVzkyWlNCM1lXbDBhVzVuSUhkb1pXVnNJaTV6Y0d4cGRDZ2lJQ0lwTzJaMWJtTjBhVzl1SUVoMEtHVXNkQ2w3ZDNVdWMyVjBLR1VzZENr'
    || 'c1ZDaDBMRnRsWFNsOVptOXlLSFpoY2lCRWFUMHdPMFJwUEY5MUxteGxibWQwYUR0RWFTc3JLWHQyWVhJZ2VtazlYM1ZiUkdsZExHTm1QWHBwTG5SdlRHOTNa'
    || 'WEpEWVhObEtDa3NaR1k5ZW1sYk1GMHVkRzlWY0hCbGNrTmhjMlVvS1N0NmFTNXpiR2xqWlNneEtUdElkQ2hqWml3aWIyNGlLMlJtS1gxSWRDaDJkU3dpYjI1'
    || 'QmJtbHRZWFJwYjI1RmJtUWlLU3hJZENobmRTd2liMjVCYm1sdFlYUnBiMjVKZEdWeVlYUnBiMjRpS1N4SWRDaDVkU3dpYjI1QmJtbHRZWFJwYjI1VGRHRnlk'
    || 'Q0lwTEVoMEtDSmtZbXhqYkdsamF5SXNJbTl1Ukc5MVlteGxRMnhwWTJzaUtTeElkQ2dpWm05amRYTnBiaUlzSW05dVJtOWpkWE1pS1N4SWRDZ2labTlqZFhO'
    || 'dmRYUWlMQ0p2YmtKc2RYSWlLU3hJZENoNGRTd2liMjVVY21GdWMybDBhVzl1Ulc1a0lpa3NlU2dpYjI1TmIzVnpaVVZ1ZEdWeUlpeGJJbTF2ZFhObGIzVjBJ'
    || 'aXdpYlc5MWMyVnZkbVZ5SWwwcExIa29JbTl1VFc5MWMyVk1aV0YyWlNJc1d5SnRiM1Z6Wlc5MWRDSXNJbTF2ZFhObGIzWmxjaUpkS1N4NUtDSnZibEJ2YVc1'
    || 'MFpYSkZiblJsY2lJc1d5SndiMmx1ZEdWeWIzVjBJaXdpY0c5cGJuUmxjbTkyWlhJaVhTa3NlU2dpYjI1UWIybHVkR1Z5VEdWaGRtVWlMRnNpY0c5cGJuUmxj'
    || 'bTkxZENJc0luQnZhVzUwWlhKdmRtVnlJbDBwTEZRb0ltOXVRMmhoYm1kbElpd2lZMmhoYm1kbElHTnNhV05ySUdadlkzVnphVzRnWm05amRYTnZkWFFnYVc1'
    || 'd2RYUWdhMlY1Wkc5M2JpQnJaWGwxY0NCelpXeGxZM1JwYjI1amFHRnVaMlVpTG5Od2JHbDBLQ0lnSWlrcExGUW9JbTl1VTJWc1pXTjBJaXdpWm05amRYTnZk'
    || 'WFFnWTI5dWRHVjRkRzFsYm5VZ1pISmhaMlZ1WkNCbWIyTjFjMmx1SUd0bGVXUnZkMjRnYTJWNWRYQWdiVzkxYzJWa2IzZHVJRzF2ZFhObGRYQWdjMlZzWldO'
    || 'MGFXOXVZMmhoYm1kbElpNXpjR3hwZENnaUlDSXBLU3hVS0NKdmJrSmxabTl5WlVsdWNIVjBJaXhiSW1OdmJYQnZjMmwwYVc5dVpXNWtJaXdpYTJWNWNISmxj'
    || 'M01pTENKMFpYaDBTVzV3ZFhRaUxDSndZWE4wWlNKZEtTeFVLQ0p2YmtOdmJYQnZjMmwwYVc5dVJXNWtJaXdpWTI5dGNHOXphWFJwYjI1bGJtUWdabTlqZFhO'
    || 'dmRYUWdhMlY1Wkc5M2JpQnJaWGx3Y21WemN5QnJaWGwxY0NCdGIzVnpaV1J2ZDI0aUxuTndiR2wwS0NJZ0lpa3BMRlFvSW05dVEyOXRjRzl6YVhScGIyNVRk'
    || 'R0Z5ZENJc0ltTnZiWEJ2YzJsMGFXOXVjM1JoY25RZ1ptOWpkWE52ZFhRZ2EyVjVaRzkzYmlCclpYbHdjbVZ6Y3lCclpYbDFjQ0J0YjNWelpXUnZkMjRpTG5O'
    || 'd2JHbDBLQ0lnSWlrcExGUW9JbTl1UTI5dGNHOXphWFJwYjI1VmNHUmhkR1VpTENKamIyMXdiM05wZEdsdmJuVndaR0YwWlNCbWIyTjFjMjkxZENCclpYbGti'
    || 'M2R1SUd0bGVYQnlaWE56SUd0bGVYVndJRzF2ZFhObFpHOTNiaUl1YzNCc2FYUW9JaUFpS1NrN2RtRnlJR1J5UFNKaFltOXlkQ0JqWVc1d2JHRjVJR05oYm5C'
    || 'c1lYbDBhSEp2ZFdkb0lHUjFjbUYwYVc5dVkyaGhibWRsSUdWdGNIUnBaV1FnWlc1amNubHdkR1ZrSUdWdVpHVmtJR1Z5Y205eUlHeHZZV1JsWkdSaGRHRWdi'
    || 'RzloWkdWa2JXVjBZV1JoZEdFZ2JHOWhaSE4wWVhKMElIQmhkWE5sSUhCc1lYa2djR3hoZVdsdVp5QndjbTluY21WemN5QnlZWFJsWTJoaGJtZGxJSEpsYzJs'
    || 'NlpTQnpaV1ZyWldRZ2MyVmxhMmx1WnlCemRHRnNiR1ZrSUhOMWMzQmxibVFnZEdsdFpYVndaR0YwWlNCMmIyeDFiV1ZqYUdGdVoyVWdkMkZwZEdsdVp5SXVj'
    || 'M0JzYVhRb0lpQWlLU3htWmoxdVpYY2dVMlYwS0NKallXNWpaV3dnWTJ4dmMyVWdhVzUyWVd4cFpDQnNiMkZrSUhOamNtOXNiQ0IwYjJkbmJHVWlMbk53Ykds'
    || 'MEtDSWdJaWt1WTI5dVkyRjBLR1J5S1NrN1puVnVZM1JwYjI0Z1UzVW9aU3gwTEc0cGUzWmhjaUJ5UFdVdWRIbHdaWHg4SW5WdWEyNXZkMjR0WlhabGJuUWlP'
    || 'MlV1WTNWeWNtVnVkRlJoY21kbGREMXVMR0ZrS0hJc2RDeDJiMmxrSURBc1pTa3NaUzVqZFhKeVpXNTBWR0Z5WjJWMFBXNTFiR3g5Wm5WdVkzUnBiMjRnUlhV'
    || 'b1pTeDBLWHQwUFNoMEpqUXBJVDA5TUR0bWIzSW9kbUZ5SUc0OU1EdHVQR1V1YkdWdVozUm9PMjRyS3lsN2RtRnlJSEk5WlZ0dVhTeHNQWEl1WlhabGJuUTdj'
    || 'ajF5TG14cGMzUmxibVZ5Y3p0bE9udDJZWElnYVQxMmIybGtJREE3YVdZb2RDbG1iM0lvZG1GeUlITTljaTVzWlc1bmRHZ3RNVHN3UEQxek8zTXRMU2w3ZG1G'
    || 'eUlHRTljbHR6WFN4bVBXRXVhVzV6ZEdGdVkyVXNaejFoTG1OMWNuSmxiblJVWVhKblpYUTdhV1lvWVQxaExteHBjM1JsYm1WeUxHWWhQVDFwSmlac0xtbHpV'
    || 'SEp2Y0dGbllYUnBiMjVUZEc5d2NHVmtLQ2twWW5KbFlXc2daVHRUZFNoc0xHRXNaeWtzYVQxbWZXVnNjMlVnWm05eUtITTlNRHR6UEhJdWJHVnVaM1JvTzNN'
    || 'ckt5bDdhV1lvWVQxeVczTmRMR1k5WVM1cGJuTjBZVzVqWlN4blBXRXVZM1Z5Y21WdWRGUmhjbWRsZEN4aFBXRXViR2x6ZEdWdVpYSXNaaUU5UFdrbUptd3Vh'
    || 'WE5RY205d1lXZGhkR2x2YmxOMGIzQndaV1FvS1NsaWNtVmhheUJsTzFOMUtHd3NZU3huS1N4cFBXWjlmWDFwWmloRWNpbDBhSEp2ZHlCbFBYQnBMRVJ5UFNF'
    || 'eExIQnBQVzUxYkd3c1pYMW1kVzVqZEdsdmJpQnNaU2hsTEhRcGUzWmhjaUJ1UFhSYlFtbGRPMjQ5UFQxMmIybGtJREFtSmlodVBYUmJRbWxkUFc1bGR5QlRa'
    || 'WFFwTzNaaGNpQnlQV1VySWw5ZlluVmlZbXhsSWp0dUxtaGhjeWh5S1h4OEtHdDFLSFFzWlN3eUxDRXhLU3h1TG1Ga1pDaHlLU2w5Wm5WdVkzUnBiMjRnUm1r'
    || 'b1pTeDBMRzRwZTNaaGNpQnlQVEE3ZENZbUtISjhQVFFwTEd0MUtHNHNaU3h5TEhRcGZYWmhjaUJLY2owaVgzSmxZV04wVEdsemRHVnVhVzVuSWl0TllYUm9M'
    || 'bkpoYm1SdmJTZ3BMblJ2VTNSeWFXNW5LRE0yS1M1emJHbGpaU2d5S1R0bWRXNWpkR2x2YmlCbWNpaGxLWHRwWmlnaFpWdEtjbDBwZTJWYlNuSmRQU0V3TEhn'
    || 'dVptOXlSV0ZqYUNobWRXNWpkR2x2YmlodUtYdHVJVDA5SW5ObGJHVmpkR2x2Ym1Ob1lXNW5aU0ltSmlobVppNW9ZWE1vYmlsOGZFWnBLRzRzSVRFc1pTa3NS'
    || 'bWtvYml3aE1DeGxLU2w5S1R0MllYSWdkRDFsTG01dlpHVlVlWEJsUFQwOU9UOWxPbVV1YjNkdVpYSkViMk4xYldWdWREdDBQVDA5Ym5Wc2JIeDhkRnRLY2wx'
    || 'OGZDaDBXMHB5WFQwaE1DeEdhU2dpYzJWc1pXTjBhVzl1WTJoaGJtZGxJaXdoTVN4MEtTbDlmV1oxYm1OMGFXOXVJR3QxS0dVc2RDeHVMSElwZTNOM2FYUmph'
    || 'Q2hMY3loMEtTbDdZMkZ6WlNBeE9uWmhjaUJzUFU1a08ySnlaV0ZyTzJOaGMyVWdORHBzUFdwa08ySnlaV0ZyTzJSbFptRjFiSFE2YkQxM2FYMXVQV3d1WW1s'
    || 'dVpDaHVkV3hzTEhRc2JpeGxLU3hzUFhadmFXUWdNQ3doWm1sOGZIUWhQVDBpZEc5MVkyaHpkR0Z5ZENJbUpuUWhQVDBpZEc5MVkyaHRiM1psSWlZbWRDRTlQ'
    || 'U0ozYUdWbGJDSjhmQ2hzUFNFd0tTeHlQMndoUFQxMmIybGtJREEvWlM1aFpHUkZkbVZ1ZEV4cGMzUmxibVZ5S0hRc2JpeDdZMkZ3ZEhWeVpUb2hNQ3h3WVhO'
    || 'emFYWmxPbXg5S1RwbExtRmtaRVYyWlc1MFRHbHpkR1Z1WlhJb2RDeHVMQ0V3S1Rwc0lUMDlkbTlwWkNBd1AyVXVZV1JrUlhabGJuUk1hWE4wWlc1bGNpaDBM'
    || 'RzRzZTNCaGMzTnBkbVU2YkgwcE9tVXVZV1JrUlhabGJuUk1hWE4wWlc1bGNpaDBMRzRzSVRFcGZXWjFibU4wYVc5dUlFRnBLR1VzZEN4dUxISXNiQ2w3ZG1G'
    || 'eUlHazljanRwWmlnb2RDWXhLVDA5UFRBbUppaDBKaklwUFQwOU1DWW1jaUU5UFc1MWJHd3BaVHBtYjNJb096c3BlMmxtS0hJOVBUMXVkV3hzS1hKbGRIVnli'
    || 'anQyWVhJZ2N6MXlMblJoWnp0cFppaHpQVDA5TTN4OGN6MDlQVFFwZTNaaGNpQmhQWEl1YzNSaGRHVk9iMlJsTG1OdmJuUmhhVzVsY2tsdVptODdhV1lvWVQw'
    || 'OVBXeDhmR0V1Ym05a1pWUjVjR1U5UFQwNEppWmhMbkJoY21WdWRFNXZaR1U5UFQxc0tXSnlaV0ZyTzJsbUtITTlQVDAwS1dadmNpaHpQWEl1Y21WMGRYSnVP'
    || 'M01oUFQxdWRXeHNPeWw3ZG1GeUlHWTljeTUwWVdjN2FXWW9LR1k5UFQwemZIeG1QVDA5TkNrbUppaG1QWE11YzNSaGRHVk9iMlJsTG1OdmJuUmhhVzVsY2ts'
    || 'dVptOHNaajA5UFd4OGZHWXVibTlrWlZSNWNHVTlQVDA0SmlabUxuQmhjbVZ1ZEU1dlpHVTlQVDFzS1NseVpYUjFjbTQ3Y3oxekxuSmxkSFZ5Ym4xbWIzSW9P'
    || 'MkVoUFQxdWRXeHNPeWw3YVdZb2N6MXliaWhoS1N4elBUMDliblZzYkNseVpYUjFjbTQ3YVdZb1pqMXpMblJoWnl4bVBUMDlOWHg4WmowOVBUWXBlM0k5YVQx'
    || 'ek8yTnZiblJwYm5WbElHVjlZVDFoTG5CaGNtVnVkRTV2WkdWOWZYSTljaTV5WlhSMWNtNTlVbk1vWm5WdVkzUnBiMjRvS1h0MllYSWdaejFwTEZNOVlXa29i'
    || 'aWtzYXoxYlhUdGxPbnQyWVhJZ2R6MTNkUzVuWlhRb1pTazdhV1lvZHlFOVBYWnZhV1FnTUNsN2RtRnlJRTg5Uldrc1NUMWxPM04zYVhSamFDaGxLWHRqWVhO'
    || 'bEltdGxlWEJ5WlhOeklqcHBaaWhIY2lodUtUMDlQVEFwWW5KbFlXc2daVHRqWVhObEltdGxlV1J2ZDI0aU9tTmhjMlVpYTJWNWRYQWlPazg5U0dRN1luSmxZ'
    || 'V3M3WTJGelpTSm1iMk4xYzJsdUlqcEpQU0ptYjJOMWN5SXNUejFxYVR0aWNtVmhhenRqWVhObEltWnZZM1Z6YjNWMElqcEpQU0ppYkhWeUlpeFBQV3BwTzJK'
    || 'eVpXRnJPMk5oYzJVaVltVm1iM0psWW14MWNpSTZZMkZ6WlNKaFpuUmxjbUpzZFhJaU9rODlhbWs3WW5KbFlXczdZMkZ6WlNKamJHbGpheUk2YVdZb2JpNWlk'
    || 'WFIwYjI0OVBUMHlLV0p5WldGcklHVTdZMkZ6WlNKaGRYaGpiR2xqYXlJNlkyRnpaU0prWW14amJHbGpheUk2WTJGelpTSnRiM1Z6WldSdmQyNGlPbU5oYzJV'
    || 'aWJXOTFjMlZ0YjNabElqcGpZWE5sSW0xdmRYTmxkWEFpT21OaGMyVWliVzkxYzJWdmRYUWlPbU5oYzJVaWJXOTFjMlZ2ZG1WeUlqcGpZWE5sSW1OdmJuUmxl'
    || 'SFJ0Wlc1MUlqcFBQVnB6TzJKeVpXRnJPMk5oYzJVaVpISmhaeUk2WTJGelpTSmtjbUZuWlc1a0lqcGpZWE5sSW1SeVlXZGxiblJsY2lJNlkyRnpaU0prY21G'
    || 'blpYaHBkQ0k2WTJGelpTSmtjbUZuYkdWaGRtVWlPbU5oYzJVaVpISmhaMjkyWlhJaU9tTmhjMlVpWkhKaFozTjBZWEowSWpwallYTmxJbVJ5YjNBaU9rODlV'
    || 'bVE3WW5KbFlXczdZMkZ6WlNKMGIzVmphR05oYm1ObGJDSTZZMkZ6WlNKMGIzVmphR1Z1WkNJNlkyRnpaU0owYjNWamFHMXZkbVVpT21OaGMyVWlkRzkxWTJo'
    || 'emRHRnlkQ0k2VHoxQ1pEdGljbVZoYXp0allYTmxJSFoxT21OaGMyVWdaM1U2WTJGelpTQjVkVHBQUFZCa08ySnlaV0ZyTzJOaGMyVWdlSFU2VHoxSFpEdGlj'
    || 'bVZoYXp0allYTmxJbk5qY205c2JDSTZUejFEWkR0aWNtVmhhenRqWVhObEluZG9aV1ZzSWpwUFBWbGtPMkp5WldGck8yTmhjMlVpWTI5d2VTSTZZMkZ6WlNK'
    || 'amRYUWlPbU5oYzJVaWNHRnpkR1VpT2s4OVNXUTdZbkpsWVdzN1kyRnpaU0puYjNSd2IybHVkR1Z5WTJGd2RIVnlaU0k2WTJGelpTSnNiM04wY0c5cGJuUmxj'
    || 'bU5oY0hSMWNtVWlPbU5oYzJVaWNHOXBiblJsY21OaGJtTmxiQ0k2WTJGelpTSndiMmx1ZEdWeVpHOTNiaUk2WTJGelpTSndiMmx1ZEdWeWJXOTJaU0k2WTJG'
    || 'elpTSndiMmx1ZEdWeWIzVjBJanBqWVhObEluQnZhVzUwWlhKdmRtVnlJanBqWVhObEluQnZhVzUwWlhKMWNDSTZUejFLYzMxMllYSWdSRDBvZENZMEtTRTlQ'
    || 'VEFzYldVOUlVUW1KbVU5UFQwaWMyTnliMnhzSWl4dFBVUS9keUU5UFc1MWJHdy9keXNpUTJGd2RIVnlaU0k2Ym5Wc2JEcDNPMFE5VzEwN1ptOXlLSFpoY2lC'
    || 'd1BXY3NkanR3SVQwOWJuVnNiRHNwZTNZOWNEdDJZWElnUXoxMkxuTjBZWFJsVG05a1pUdHBaaWgyTG5SaFp6MDlQVFVtSmtNaFBUMXVkV3hzSmlZb2RqMURM'
    || 'RzBoUFQxdWRXeHNKaVlvUXoxWmJpaHdMRzBwTEVNaFBXNTFiR3dtSmtRdWNIVnphQ2h3Y2lod0xFTXNkaWtwS1Nrc2JXVXBZbkpsWVdzN2NEMXdMbkpsZEhW'
    || 'eWJuMHdQRVF1YkdWdVozUm9KaVlvZHoxdVpYY2dUeWgzTEVrc2JuVnNiQ3h1TEZNcExHc3VjSFZ6YUNoN1pYWmxiblE2ZHl4c2FYTjBaVzVsY25NNlJIMHBL'
    || 'WDE5YVdZb0tIUW1OeWs5UFQwd0tYdGxPbnRwWmloM1BXVTlQVDBpYlc5MWMyVnZkbVZ5SW54OFpUMDlQU0p3YjJsdWRHVnliM1psY2lJc1R6MWxQVDA5SW0x'
    || 'dmRYTmxiM1YwSW54OFpUMDlQU0p3YjJsdWRHVnliM1YwSWl4M0ppWnVJVDA5ZFdrbUppaEpQVzR1Y21Wc1lYUmxaRlJoY21kbGRIeDhiaTVtY205dFJXeGxi'
    || 'V1Z1ZENrbUppaHliaWhKS1h4OFNWdE9kRjBwS1dKeVpXRnJJR1U3YVdZb0tFOThmSGNwSmlZb2R6MVRMbmRwYm1SdmR6MDlQVk0vVXpvb2R6MVRMbTkzYm1W'
    || 'eVJHOWpkVzFsYm5RcFAzY3VaR1ZtWVhWc2RGWnBaWGQ4ZkhjdWNHRnlaVzUwVjJsdVpHOTNPbmRwYm1SdmR5eFBQeWhKUFc0dWNtVnNZWFJsWkZSaGNtZGxk'
    || 'SHg4Ymk1MGIwVnNaVzFsYm5Rc1R6MW5MRWs5U1Q5eWJpaEpLVHB1ZFd4c0xFa2hQVDF1ZFd4c0ppWW9iV1U5Ym00b1NTa3NTU0U5UFcxbGZIeEpMblJoWnlF'
    || 'OVBUVW1Ka2t1ZEdGbklUMDlOaWttSmloSlBXNTFiR3dwS1Rvb1R6MXVkV3hzTEVrOVp5a3NUeUU5UFVrcEtYdHBaaWhFUFZwekxFTTlJbTl1VFc5MWMyVk1a'
    || 'V0YyWlNJc2JUMGliMjVOYjNWelpVVnVkR1Z5SWl4d1BTSnRiM1Z6WlNJc0tHVTlQVDBpY0c5cGJuUmxjbTkxZENKOGZHVTlQVDBpY0c5cGJuUmxjbTkyWlhJ'
    || 'aUtTWW1LRVE5U25Nc1F6MGliMjVRYjJsdWRHVnlUR1ZoZG1VaUxHMDlJbTl1VUc5cGJuUmxja1Z1ZEdWeUlpeHdQU0p3YjJsdWRHVnlJaWtzYldVOVR6MDli'
    || 'blZzYkQ5M09sUnVLRThwTEhZOVNUMDliblZzYkQ5M09sUnVLRWtwTEhjOWJtVjNJRVFvUXl4d0t5SnNaV0YyWlNJc1R5eHVMRk1wTEhjdWRHRnlaMlYwUFcx'
    || 'bExIY3VjbVZzWVhSbFpGUmhjbWRsZEQxMkxFTTliblZzYkN4eWJpaFRLVDA5UFdjbUppaEVQVzVsZHlCRUtHMHNjQ3NpWlc1MFpYSWlMRWtzYml4VEtTeEVM'
    || 'blJoY21kbGREMTJMRVF1Y21Wc1lYUmxaRlJoY21kbGREMXRaU3hEUFVRcExHMWxQVU1zVHlZbVNTbDBPbnRtYjNJb1JEMVBMRzA5U1N4d1BUQXNkajFFTzNZ'
    || 'N2RqMXFiaWgyS1Nsd0t5czdabTl5S0hZOU1DeERQVzA3UXp0RFBXcHVLRU1wS1hZckt6dG1iM0lvT3pBOGNDMTJPeWxFUFdwdUtFUXBMSEF0TFR0bWIzSW9P'
    || 'ekE4ZGkxd095bHRQV3B1S0cwcExIWXRMVHRtYjNJb08zQXRMVHNwZTJsbUtFUTlQVDF0Zkh4dElUMDliblZzYkNZbVJEMDlQVzB1WVd4MFpYSnVZWFJsS1dK'
    || 'eVpXRnJJSFE3UkQxcWJpaEVLU3h0UFdwdUtHMHBmVVE5Ym5Wc2JIMWxiSE5sSUVROWJuVnNiRHRQSVQwOWJuVnNiQ1ltVG5Vb2F5eDNMRThzUkN3aE1Ta3NT'
    || 'U0U5UFc1MWJHd21KbTFsSVQwOWJuVnNiQ1ltVG5Vb2F5eHRaU3hKTEVRc0lUQXBmWDFsT250cFppaDNQV2MvVkc0b1p5azZkMmx1Wkc5M0xFODlkeTV1YjJS'
    || 'bFRtRnRaU1ltZHk1dWIyUmxUbUZ0WlM1MGIweHZkMlZ5UTJGelpTZ3BMRTg5UFQwaWMyVnNaV04wSW54OFR6MDlQU0pwYm5CMWRDSW1KbmN1ZEhsd1pUMDlQ'
    || 'U0ptYVd4bElpbDJZWElnZWoxMFpqdGxiSE5sSUdsbUtHeDFLSGNwS1dsbUtHOTFLWG85YjJZN1pXeHpaWHQ2UFhKbU8zWmhjaUJCUFc1bWZXVnNjMlVvVHox'
    || 'M0xtNXZaR1ZPWVcxbEtTWW1UeTUwYjB4dmQyVnlRMkZ6WlNncFBUMDlJbWx1Y0hWMElpWW1LSGN1ZEhsd1pUMDlQU0pqYUdWamEySnZlQ0o4ZkhjdWRIbHda'
    || 'VDA5UFNKeVlXUnBieUlwSmlZb2VqMXNaaWs3YVdZb2VpWW1LSG85ZWlobExHY3BLU2w3YVhVb2F5eDZMRzRzVXlrN1luSmxZV3NnWlgxQkppWkJLR1VzZHl4'
    || 'bktTeGxQVDA5SW1adlkzVnpiM1YwSWlZbUtFRTlkeTVmZDNKaGNIQmxjbE4wWVhSbEtTWW1RUzVqYjI1MGNtOXNiR1ZrSmlaM0xuUjVjR1U5UFQwaWJuVnRZ'
    || 'bVZ5SWlZbWNta29keXdpYm5WdFltVnlJaXgzTG5aaGJIVmxLWDF6ZDJsMFkyZ29RVDFuUDFSdUtHY3BPbmRwYm1SdmR5eGxLWHRqWVhObEltWnZZM1Z6YVc0'
    || 'aU9paHNkU2hCS1h4OFFTNWpiMjUwWlc1MFJXUnBkR0ZpYkdVOVBUMGlkSEoxWlNJcEppWW9hMjQ5UVN4UWFUMW5MR055UFc1MWJHd3BPMkp5WldGck8yTmhj'
    || 'MlVpWm05amRYTnZkWFFpT21OeVBWQnBQV3R1UFc1MWJHdzdZbkpsWVdzN1kyRnpaU0p0YjNWelpXUnZkMjRpT2sxcFBTRXdPMkp5WldGck8yTmhjMlVpWTI5'
    || 'dWRHVjRkRzFsYm5VaU9tTmhjMlVpYlc5MWMyVjFjQ0k2WTJGelpTSmtjbUZuWlc1a0lqcE5hVDBoTVN4b2RTaHJMRzRzVXlrN1luSmxZV3M3WTJGelpTSnpa'
    || 'V3hsWTNScGIyNWphR0Z1WjJVaU9tbG1LR0ZtS1dKeVpXRnJPMk5oYzJVaWEyVjVaRzkzYmlJNlkyRnpaU0pyWlhsMWNDSTZhSFVvYXl4dUxGTXBmWFpoY2lC'
    || 'Vk8ybG1LRlJwS1dVNmUzTjNhWFJqYUNobEtYdGpZWE5sSW1OdmJYQnZjMmwwYVc5dWMzUmhjblFpT25aaGNpQklQU0p2YmtOdmJYQnZjMmwwYVc5dVUzUmhj'
    || 'blFpTzJKeVpXRnJJR1U3WTJGelpTSmpiMjF3YjNOcGRHbHZibVZ1WkNJNlNEMGliMjVEYjIxd2IzTnBkR2x2YmtWdVpDSTdZbkpsWVdzZ1pUdGpZWE5sSW1O'
    || 'dmJYQnZjMmwwYVc5dWRYQmtZWFJsSWpwSVBTSnZia052YlhCdmMybDBhVzl1VlhCa1lYUmxJanRpY21WaGF5QmxmVWc5ZG05cFpDQXdmV1ZzYzJVZ1JXNC9i'
    || 'blVvWlN4dUtTWW1LRWc5SW05dVEyOXRjRzl6YVhScGIyNUZibVFpS1RwbFBUMDlJbXRsZVdSdmQyNGlKaVp1TG10bGVVTnZaR1U5UFQweU1qa21KaWhJUFNK'
    || 'dmJrTnZiWEJ2YzJsMGFXOXVVM1JoY25RaUtUdElKaVlvWW5NbUptNHViRzlqWVd4bElUMDlJbXR2SWlZbUtFVnVmSHhJSVQwOUltOXVRMjl0Y0c5emFYUnBi'
    || 'MjVUZEdGeWRDSS9TRDA5UFNKdmJrTnZiWEJ2YzJsMGFXOXVSVzVrSWlZbVJXNG1KaWhWUFZsektDa3BPaWdrZEQxVExGTnBQU0oyWVd4MVpTSnBiaUFrZEQ4'
    || 'a2RDNTJZV3gxWlRva2RDNTBaWGgwUTI5dWRHVnVkQ3hGYmowaE1Da3BMRUU5WW5Jb1p5eElLU3d3UEVFdWJHVnVaM1JvSmlZb1NEMXVaWGNnY1hNb1NDeGxM'
    || 'RzUxYkd3c2JpeFRLU3hyTG5CMWMyZ29lMlYyWlc1ME9rZ3NiR2x6ZEdWdVpYSnpPa0Y5S1N4VlAwZ3VaR0YwWVQxVk9paFZQWEoxS0c0cExGVWhQVDF1ZFd4'
    || 'c0ppWW9TQzVrWVhSaFBWVXBLU2twTENoVlBWcGtQM0ZrS0dVc2JpazZTbVFvWlN4dUtTa21KaWhuUFdKeUtHY3NJbTl1UW1WbWIzSmxTVzV3ZFhRaUtTd3dQ'
    || 'R2N1YkdWdVozUm9KaVlvVXoxdVpYY2djWE1vSW05dVFtVm1iM0psU1c1d2RYUWlMQ0ppWldadmNtVnBibkIxZENJc2JuVnNiQ3h1TEZNcExHc3VjSFZ6YUNo'
    || 'N1pYWmxiblE2VXl4c2FYTjBaVzVsY25NNlozMHBMRk11WkdGMFlUMVZLU2w5UlhVb2F5eDBLWDBwZldaMWJtTjBhVzl1SUhCeUtHVXNkQ3h1S1h0eVpYUjFj'
    || 'bTU3YVc1emRHRnVZMlU2WlN4c2FYTjBaVzVsY2pwMExHTjFjbkpsYm5SVVlYSm5aWFE2Ym4xOVpuVnVZM1JwYjI0Z1luSW9aU3gwS1h0bWIzSW9kbUZ5SUc0'
    || 'OWRDc2lRMkZ3ZEhWeVpTSXNjajFiWFR0bElUMDliblZzYkRzcGUzWmhjaUJzUFdVc2FUMXNMbk4wWVhSbFRtOWtaVHRzTG5SaFp6MDlQVFVtSm1raFBUMXVk'
    || 'V3hzSmlZb2JEMXBMR2s5V1c0b1pTeHVLU3hwSVQxdWRXeHNKaVp5TG5WdWMyaHBablFvY0hJb1pTeHBMR3dwS1N4cFBWbHVLR1VzZENrc2FTRTliblZzYkNZ'
    || 'bWNpNXdkWE5vS0hCeUtHVXNhU3hzS1NrcExHVTlaUzV5WlhSMWNtNTljbVYwZFhKdUlISjlablZ1WTNScGIyNGdhbTRvWlNsN2FXWW9aVDA5UFc1MWJHd3Bj'
    || 'bVYwZFhKdUlHNTFiR3c3Wkc4Z1pUMWxMbkpsZEhWeWJqdDNhR2xzWlNobEppWmxMblJoWnlFOVBUVXBPM0psZEhWeWJpQmxmSHh1ZFd4c2ZXWjFibU4wYVc5'
    || 'dUlFNTFLR1VzZEN4dUxISXNiQ2w3Wm05eUtIWmhjaUJwUFhRdVgzSmxZV04wVG1GdFpTeHpQVnRkTzI0aFBUMXVkV3hzSmladUlUMDljanNwZTNaaGNpQmhQ'
    || 'VzRzWmoxaExtRnNkR1Z5Ym1GMFpTeG5QV0V1YzNSaGRHVk9iMlJsTzJsbUtHWWhQVDF1ZFd4c0ppWm1QVDA5Y2lsaWNtVmhhenRoTG5SaFp6MDlQVFVtSm1j'
    || 'aFBUMXVkV3hzSmlZb1lUMW5MR3cvS0dZOVdXNG9iaXhwS1N4bUlUMXVkV3hzSmlaekxuVnVjMmhwWm5Rb2NISW9iaXhtTEdFcEtTazZiSHg4S0dZOVdXNG9i'
    || 'aXhwS1N4bUlUMXVkV3hzSmlaekxuQjFjMmdvY0hJb2JpeG1MR0VwS1NrcExHNDliaTV5WlhSMWNtNTljeTVzWlc1bmRHZ2hQVDB3SmlabExuQjFjMmdvZTJW'
    || 'MlpXNTBPblFzYkdsemRHVnVaWEp6T25OOUtYMTJZWElnY0dZOUwxeHlYRzQvTDJjc2FHWTlMMXgxTURBd01IeGNkVVpHUmtRdlp6dG1kVzVqZEdsdmJpQnFk'
    || 'U2hsS1h0eVpYUjFjbTRvZEhsd1pXOW1JR1U5UFNKemRISnBibWNpUDJVNklpSXJaU2t1Y21Wd2JHRmpaU2h3Wml4Z0NtQXBMbkpsY0d4aFkyVW9hR1lzSWlJ'
    || 'cGZXWjFibU4wYVc5dUlHVnNLR1VzZEN4dUtYdHBaaWgwUFdwMUtIUXBMR3AxS0dVcElUMDlkQ1ltYmlsMGFISnZkeUJGY25KdmNpaGpLRFF5TlNrcGZXWjFi'
    || 'bU4wYVc5dUlIUnNLQ2w3ZlhaaGNpQlZhVDF1ZFd4c0xDUnBQVzUxYkd3N1puVnVZM1JwYjI0Z1NHa29aU3gwS1h0eVpYUjFjbTRnWlQwOVBTSjBaWGgwWVhK'
    || 'bFlTSjhmR1U5UFQwaWJtOXpZM0pwY0hRaWZIeDBlWEJsYjJZZ2RDNWphR2xzWkhKbGJqMDlJbk4wY21sdVp5SjhmSFI1Y0dWdlppQjBMbU5vYVd4a2NtVnVQ'
    || 'VDBpYm5WdFltVnlJbng4ZEhsd1pXOW1JSFF1WkdGdVoyVnliM1Z6YkhsVFpYUkpibTVsY2toVVRVdzlQU0p2WW1wbFkzUWlKaVowTG1SaGJtZGxjbTkxYzJ4'
    || 'NVUyVjBTVzV1WlhKSVZFMU1JVDA5Ym5Wc2JDWW1kQzVrWVc1blpYSnZkWE5zZVZObGRFbHVibVZ5U0ZSTlRDNWZYMmgwYld3aFBXNTFiR3g5ZG1GeUlGWnBQ'
    || 'WFI1Y0dWdlppQnpaWFJVYVcxbGIzVjBQVDBpWm5WdVkzUnBiMjRpUDNObGRGUnBiV1Z2ZFhRNmRtOXBaQ0F3TEcxbVBYUjVjR1Z2WmlCamJHVmhjbFJwYldW'
    || 'dmRYUTlQU0ptZFc1amRHbHZiaUkvWTJ4bFlYSlVhVzFsYjNWME9uWnZhV1FnTUN4RGRUMTBlWEJsYjJZZ1VISnZiV2x6WlQwOUltWjFibU4wYVc5dUlqOVFj'
    || 'bTl0YVhObE9uWnZhV1FnTUN4MlpqMTBlWEJsYjJZZ2NYVmxkV1ZOYVdOeWIzUmhjMnM5UFNKbWRXNWpkR2x2YmlJL2NYVmxkV1ZOYVdOeWIzUmhjMnM2ZEhs'
    || 'd1pXOW1JRU4xUENKMUlqOW1kVzVqZEdsdmJpaGxLWHR5WlhSMWNtNGdRM1V1Y21WemIyeDJaU2h1ZFd4c0tTNTBhR1Z1S0dVcExtTmhkR05vS0dkbUtYMDZW'
    || 'bWs3Wm5WdVkzUnBiMjRnWjJZb1pTbDdjMlYwVkdsdFpXOTFkQ2htZFc1amRHbHZiaWdwZTNSb2NtOTNJR1Y5S1gxbWRXNWpkR2x2YmlCWGFTaGxMSFFwZTNa'
    || 'aGNpQnVQWFFzY2owd08yUnZlM1poY2lCc1BXNHVibVY0ZEZOcFlteHBibWM3YVdZb1pTNXlaVzF2ZG1WRGFHbHNaQ2h1S1N4c0ppWnNMbTV2WkdWVWVYQmxQ'
    || 'VDA5T0NscFppaHVQV3d1WkdGMFlTeHVQVDA5SWk4a0lpbDdhV1lvY2owOVBUQXBlMlV1Y21WdGIzWmxRMmhwYkdRb2JDa3NjbklvZENrN2NtVjBkWEp1ZlhJ'
    || 'dExYMWxiSE5sSUc0aFBUMGlKQ0ltSm00aFBUMGlKRDhpSmladUlUMDlJaVFoSW54OGNpc3JPMjQ5YkgxM2FHbHNaU2h1S1R0eWNpaDBLWDFtZFc1amRHbHZi'
    || 'aUJXZENobEtYdG1iM0lvTzJVaFBXNTFiR3c3WlQxbExtNWxlSFJUYVdKc2FXNW5LWHQyWVhJZ2REMWxMbTV2WkdWVWVYQmxPMmxtS0hROVBUMHhmSHgwUFQw'
    || 'OU15bGljbVZoYXp0cFppaDBQVDA5T0NsN2FXWW9kRDFsTG1SaGRHRXNkRDA5UFNJa0lueDhkRDA5UFNJa0lTSjhmSFE5UFQwaUpEOGlLV0p5WldGck8ybG1L'
    || 'SFE5UFQwaUx5UWlLWEpsZEhWeWJpQnVkV3hzZlgxeVpYUjFjbTRnWlgxbWRXNWpkR2x2YmlCVWRTaGxLWHRsUFdVdWNISmxkbWx2ZFhOVGFXSnNhVzVuTzJa'
    || 'dmNpaDJZWElnZEQwd08yVTdLWHRwWmlobExtNXZaR1ZVZVhCbFBUMDlPQ2w3ZG1GeUlHNDlaUzVrWVhSaE8ybG1LRzQ5UFQwaUpDSjhmRzQ5UFQwaUpDRWlm'
    || 'SHh1UFQwOUlpUS9JaWw3YVdZb2REMDlQVEFwY21WMGRYSnVJR1U3ZEMwdGZXVnNjMlVnYmowOVBTSXZKQ0ltSm5RckszMWxQV1V1Y0hKbGRtbHZkWE5UYVdK'
    || 'c2FXNW5mWEpsZEhWeWJpQnVkV3hzZlhaaGNpQkRiajFOWVhSb0xuSmhibVJ2YlNncExuUnZVM1J5YVc1bktETTJLUzV6YkdsalpTZ3lLU3gzZEQwaVgxOXla'
    || 'V0ZqZEVacFltVnlKQ0lyUTI0c2FISTlJbDlmY21WaFkzUlFjbTl3Y3lRaUswTnVMRTUwUFNKZlgzSmxZV04wUTI5dWRHRnBibVZ5SkNJclEyNHNRbWs5SWw5'
    || 'ZmNtVmhZM1JGZG1WdWRITWtJaXREYml4NVpqMGlYMTl5WldGamRFeHBjM1JsYm1WeWN5UWlLME51TEhobVBTSmZYM0psWVdOMFNHRnVaR3hsY3lRaUswTnVP'
    || 'MloxYm1OMGFXOXVJSEp1S0dVcGUzWmhjaUIwUFdWYmQzUmRPMmxtS0hRcGNtVjBkWEp1SUhRN1ptOXlLSFpoY2lCdVBXVXVjR0Z5Wlc1MFRtOWtaVHR1T3ls'
    || 'N2FXWW9kRDF1VzA1MFhYeDhibHQzZEYwcGUybG1LRzQ5ZEM1aGJIUmxjbTVoZEdVc2RDNWphR2xzWkNFOVBXNTFiR3g4Zkc0aFBUMXVkV3hzSmladUxtTm9h'
    || 'V3hrSVQwOWJuVnNiQ2xtYjNJb1pUMVVkU2hsS1R0bElUMDliblZzYkRzcGUybG1LRzQ5WlZ0M2RGMHBjbVYwZFhKdUlHNDdaVDFVZFNobEtYMXlaWFIxY200'
    || 'Z2RIMWxQVzRzYmoxbExuQmhjbVZ1ZEU1dlpHVjljbVYwZFhKdUlHNTFiR3g5Wm5WdVkzUnBiMjRnYlhJb1pTbDdjbVYwZFhKdUlHVTlaVnQzZEYxOGZHVmJU'
    || 'blJkTENGbGZIeGxMblJoWnlFOVBUVW1KbVV1ZEdGbklUMDlOaVltWlM1MFlXY2hQVDB4TXlZbVpTNTBZV2NoUFQwelAyNTFiR3c2WlgxbWRXNWpkR2x2YmlC'
    || 'VWJpaGxLWHRwWmlobExuUmhaejA5UFRWOGZHVXVkR0ZuUFQwOU5pbHlaWFIxY200Z1pTNXpkR0YwWlU1dlpHVTdkR2h5YjNjZ1JYSnliM0lvWXlnek15a3Bm'
    || 'V1oxYm1OMGFXOXVJRzVzS0dVcGUzSmxkSFZ5YmlCbFcyaHlYWHg4Ym5Wc2JIMTJZWElnVVdrOVcxMHNVbTQ5TFRFN1puVnVZM1JwYjI0Z1YzUW9aU2w3Y21W'
    || 'MGRYSnVlMk4xY25KbGJuUTZaWDE5Wm5WdVkzUnBiMjRnYVdVb1pTbDdNRDVTYm54OEtHVXVZM1Z5Y21WdWREMVJhVnRTYmwwc1VXbGJVbTVkUFc1MWJHd3NV'
    || 'bTR0TFNsOVpuVnVZM1JwYjI0Z2NtVW9aU3gwS1h0U2Jpc3JMRkZwVzFKdVhUMWxMbU4xY25KbGJuUXNaUzVqZFhKeVpXNTBQWFI5ZG1GeUlFSjBQWHQ5TEZS'
    || 'bFBWZDBLRUowS1N4QlpUMVhkQ2doTVNrc2JHNDlRblE3Wm5WdVkzUnBiMjRnVEc0b1pTeDBLWHQyWVhJZ2JqMWxMblI1Y0dVdVkyOXVkR1Y0ZEZSNWNHVnpP'
    || 'MmxtS0NGdUtYSmxkSFZ5YmlCQ2REdDJZWElnY2oxbExuTjBZWFJsVG05a1pUdHBaaWh5SmlaeUxsOWZjbVZoWTNSSmJuUmxjbTVoYkUxbGJXOXBlbVZrVlc1'
    || 'dFlYTnJaV1JEYUdsc1pFTnZiblJsZUhROVBUMTBLWEpsZEhWeWJpQnlMbDlmY21WaFkzUkpiblJsY201aGJFMWxiVzlwZW1Wa1RXRnphMlZrUTJocGJHUkRi'
    || 'MjUwWlhoME8zWmhjaUJzUFh0OUxHazdabTl5S0drZ2FXNGdiaWxzVzJsZFBYUmJhVjA3Y21WMGRYSnVJSEltSmlobFBXVXVjM1JoZEdWT2IyUmxMR1V1WDE5'
    || 'eVpXRmpkRWx1ZEdWeWJtRnNUV1Z0YjJsNlpXUlZibTFoYzJ0bFpFTm9hV3hrUTI5dWRHVjRkRDEwTEdVdVgxOXlaV0ZqZEVsdWRHVnlibUZzVFdWdGIybDZa'
    || 'V1JOWVhOclpXUkRhR2xzWkVOdmJuUmxlSFE5YkNrc2JIMW1kVzVqZEdsdmJpQlZaU2hsS1h0eVpYUjFjbTRnWlQxbExtTm9hV3hrUTI5dWRHVjRkRlI1Y0dW'
    || 'ekxHVWhQVzUxYkd4OVpuVnVZM1JwYjI0Z2Ntd29LWHRwWlNoQlpTa3NhV1VvVkdVcGZXWjFibU4wYVc5dUlGSjFLR1VzZEN4dUtYdHBaaWhVWlM1amRYSnla'
    || 'VzUwSVQwOVFuUXBkR2h5YjNjZ1JYSnliM0lvWXlneE5qZ3BLVHR5WlNoVVpTeDBLU3h5WlNoQlpTeHVLWDFtZFc1amRHbHZiaUJNZFNobExIUXNiaWw3ZG1G'
    || 'eUlISTlaUzV6ZEdGMFpVNXZaR1U3YVdZb2REMTBMbU5vYVd4a1EyOXVkR1Y0ZEZSNWNHVnpMSFI1Y0dWdlppQnlMbWRsZEVOb2FXeGtRMjl1ZEdWNGRDRTlJ'
    || 'bVoxYm1OMGFXOXVJaWx5WlhSMWNtNGdianR5UFhJdVoyVjBRMmhwYkdSRGIyNTBaWGgwS0NrN1ptOXlLSFpoY2lCc0lHbHVJSElwYVdZb0lTaHNJR2x1SUhR'
    || 'cEtYUm9jbTkzSUVWeWNtOXlLR01vTVRBNExHNWxLR1VwZkh3aVZXNXJibTkzYmlJc2JDa3BPM0psZEhWeWJpQk5LSHQ5TEc0c2NpbDlablZ1WTNScGIyNGdi'
    || 'R3dvWlNsN2NtVjBkWEp1SUdVOUtHVTlaUzV6ZEdGMFpVNXZaR1VwSmlabExsOWZjbVZoWTNSSmJuUmxjbTVoYkUxbGJXOXBlbVZrVFdWeVoyVmtRMmhwYkdS'
    || 'RGIyNTBaWGgwZkh4Q2RDeHNiajFVWlM1amRYSnlaVzUwTEhKbEtGUmxMR1VwTEhKbEtFRmxMRUZsTG1OMWNuSmxiblFwTENFd2ZXWjFibU4wYVc5dUlFOTFL'
    || 'R1VzZEN4dUtYdDJZWElnY2oxbExuTjBZWFJsVG05a1pUdHBaaWdoY2lsMGFISnZkeUJGY25KdmNpaGpLREUyT1NrcE8yNC9LR1U5VEhVb1pTeDBMR3h1S1N4'
    || 'eUxsOWZjbVZoWTNSSmJuUmxjbTVoYkUxbGJXOXBlbVZrVFdWeVoyVmtRMmhwYkdSRGIyNTBaWGgwUFdVc2FXVW9RV1VwTEdsbEtGUmxLU3h5WlNoVVpTeGxL'
    || 'U2s2YVdVb1FXVXBMSEpsS0VGbExHNHBmWFpoY2lCcWREMXVkV3hzTEdsc1BTRXhMRWRwUFNFeE8yWjFibU4wYVc5dUlGQjFLR1VwZTJwMFBUMDliblZzYkQ5'
    || 'cWREMWJaVjA2YW5RdWNIVnphQ2hsS1gxbWRXNWpkR2x2YmlCM1ppaGxLWHRwYkQwaE1DeFFkU2hsS1gxbWRXNWpkR2x2YmlCUmRDZ3BlMmxtS0NGSGFTWW1h'
    || 'blFoUFQxdWRXeHNLWHRIYVQwaE1EdDJZWElnWlQwd0xIUTlkR1U3ZEhKNWUzWmhjaUJ1UFdwME8yWnZjaWgwWlQweE8yVThiaTVzWlc1bmRHZzdaU3NyS1h0'
    || 'MllYSWdjajF1VzJWZE8yUnZJSEk5Y2lnaE1DazdkMmhwYkdVb2NpRTlQVzUxYkd3cGZXcDBQVzUxYkd3c2FXdzlJVEY5WTJGMFkyZ29iQ2w3ZEdoeWIzY2dh'
    || 'blFoUFQxdWRXeHNKaVlvYW5ROWFuUXVjMnhwWTJVb1pTc3hLU2tzU1hNb2FHa3NVWFFwTEd4OVptbHVZV3hzZVh0MFpUMTBMRWRwUFNFeGZYMXlaWFIxY200'
    || 'Z2JuVnNiSDEyWVhJZ1QyNDlXMTBzVUc0OU1DeHZiRDF1ZFd4c0xITnNQVEFzWlhROVcxMHNkSFE5TUN4dmJqMXVkV3hzTEVOMFBURXNWSFE5SWlJN1puVnVZ'
    || 'M1JwYjI0Z2MyNG9aU3gwS1h0UGJsdFFiaXNyWFQxemJDeFBibHRRYmlzclhUMXZiQ3h2YkQxbExITnNQWFI5Wm5WdVkzUnBiMjRnVFhVb1pTeDBMRzRwZTJW'
    || 'MFczUjBLeXRkUFVOMExHVjBXM1IwS3l0ZFBWUjBMR1YwVzNSMEt5dGRQVzl1TEc5dVBXVTdkbUZ5SUhJOVEzUTdaVDFVZER0MllYSWdiRDB6TWkxaGRDaHlL'
    || 'UzB4TzNJbVBYNG9NVHc4YkNrc2JpczlNVHQyWVhJZ2FUMHpNaTFoZENoMEtTdHNPMmxtS0RNd1BHa3BlM1poY2lCelBXd3RiQ1UxTzJrOUtISW1LREU4UEhN'
    || 'cExURXBMblJ2VTNSeWFXNW5LRE15S1N4eVBqNDljeXhzTFQxekxFTjBQVEU4UERNeUxXRjBLSFFwSzJ4OGJqdzhiSHh5TEZSMFBXa3JaWDFsYkhObElFTjBQ'
    || 'VEU4UEdsOGJqdzhiSHh5TEZSMFBXVjlablZ1WTNScGIyNGdTMmtvWlNsN1pTNXlaWFIxY200aFBUMXVkV3hzSmlZb2MyNG9aU3d4S1N4TmRTaGxMREVzTUNr'
    || 'cGZXWjFibU4wYVc5dUlGbHBLR1VwZTJadmNpZzdaVDA5UFc5c095bHZiRDFQYmxzdExWQnVYU3hQYmx0UWJsMDliblZzYkN4emJEMVBibHN0TFZCdVhTeFBi'
    || 'bHRRYmwwOWJuVnNiRHRtYjNJb08yVTlQVDF2YmpzcGIyNDlaWFJiTFMxMGRGMHNaWFJiZEhSZFBXNTFiR3dzVkhROVpYUmJMUzEwZEYwc1pYUmJkSFJkUFc1'
    || 'MWJHd3NRM1E5WlhSYkxTMTBkRjBzWlhSYmRIUmRQVzUxYkd4OWRtRnlJRmhsUFc1MWJHd3NXbVU5Ym5Wc2JDeHpaVDBoTVN4a2REMXVkV3hzTzJaMWJtTjBh'
    || 'Vzl1SUVsMUtHVXNkQ2w3ZG1GeUlHNDlhWFFvTlN4dWRXeHNMRzUxYkd3c01DazdiaTVsYkdWdFpXNTBWSGx3WlQwaVJFVk1SVlJGUkNJc2JpNXpkR0YwWlU1'
    || 'dlpHVTlkQ3h1TG5KbGRIVnliajFsTEhROVpTNWtaV3hsZEdsdmJuTXNkRDA5UFc1MWJHdy9LR1V1WkdWc1pYUnBiMjV6UFZ0dVhTeGxMbVpzWVdkemZEMHhO'
    || 'aWs2ZEM1d2RYTm9LRzRwZldaMWJtTjBhVzl1SUVSMUtHVXNkQ2w3YzNkcGRHTm9LR1V1ZEdGbktYdGpZWE5sSURVNmRtRnlJRzQ5WlM1MGVYQmxPM0psZEhW'
    || 'eWJpQjBQWFF1Ym05a1pWUjVjR1VoUFQweGZIeHVMblJ2VEc5M1pYSkRZWE5sS0NraFBUMTBMbTV2WkdWT1lXMWxMblJ2VEc5M1pYSkRZWE5sS0NrL2JuVnNi'
    || 'RHAwTEhRaFBUMXVkV3hzUHlobExuTjBZWFJsVG05a1pUMTBMRmhsUFdVc1dtVTlWblFvZEM1bWFYSnpkRU5vYVd4a0tTd2hNQ2s2SVRFN1kyRnpaU0EyT25K'
    || 'bGRIVnliaUIwUFdVdWNHVnVaR2x1WjFCeWIzQnpQVDA5SWlKOGZIUXVibTlrWlZSNWNHVWhQVDB6UDI1MWJHdzZkQ3gwSVQwOWJuVnNiRDhvWlM1emRHRjBa'
    || 'VTV2WkdVOWRDeFlaVDFsTEZwbFBXNTFiR3dzSVRBcE9pRXhPMk5oYzJVZ01UTTZjbVYwZFhKdUlIUTlkQzV1YjJSbFZIbHdaU0U5UFRnL2JuVnNiRHAwTEhR'
    || 'aFBUMXVkV3hzUHlodVBXOXVJVDA5Ym5Wc2JEOTdhV1E2UTNRc2IzWmxjbVpzYjNjNlZIUjlPbTUxYkd3c1pTNXRaVzF2YVhwbFpGTjBZWFJsUFh0a1pXaDVa'
    || 'SEpoZEdWa09uUXNkSEpsWlVOdmJuUmxlSFE2Yml4eVpYUnllVXhoYm1VNk1UQTNNemMwTVRneU5IMHNiajFwZENneE9DeHVkV3hzTEc1MWJHd3NNQ2tzYmk1'
    || 'emRHRjBaVTV2WkdVOWRDeHVMbkpsZEhWeWJqMWxMR1V1WTJocGJHUTliaXhZWlQxbExGcGxQVzUxYkd3c0lUQXBPaUV4TzJSbFptRjFiSFE2Y21WMGRYSnVJ'
    || 'VEY5ZldaMWJtTjBhVzl1SUZocEtHVXBlM0psZEhWeWJpaGxMbTF2WkdVbU1Ta2hQVDB3SmlZb1pTNW1iR0ZuY3lZeE1qZ3BQVDA5TUgxbWRXNWpkR2x2YmlC'
    || 'YWFTaGxLWHRwWmloelpTbDdkbUZ5SUhROVdtVTdhV1lvZENsN2RtRnlJRzQ5ZER0cFppZ2hSSFVvWlN4MEtTbDdhV1lvV0drb1pTa3BkR2h5YjNjZ1JYSnli'
    || 'M0lvWXlnME1UZ3BLVHQwUFZaMEtHNHVibVY0ZEZOcFlteHBibWNwTzNaaGNpQnlQVmhsTzNRbUprUjFLR1VzZENrL1NYVW9jaXh1S1Rvb1pTNW1iR0ZuY3ox'
    || 'bExtWnNZV2R6SmkwME1EazNmRElzYzJVOUlURXNXR1U5WlNsOWZXVnNjMlY3YVdZb1dHa29aU2twZEdoeWIzY2dSWEp5YjNJb1l5ZzBNVGdwS1R0bExtWnNZ'
    || 'V2R6UFdVdVpteGhaM01tTFRRd09UZDhNaXh6WlQwaE1TeFlaVDFsZlgxOVpuVnVZM1JwYjI0Z2VuVW9aU2w3Wm05eUtHVTlaUzV5WlhSMWNtNDdaU0U5UFc1'
    || 'MWJHd21KbVV1ZEdGbklUMDlOU1ltWlM1MFlXY2hQVDB6SmlabExuUmhaeUU5UFRFek95bGxQV1V1Y21WMGRYSnVPMWhsUFdWOVpuVnVZM1JwYjI0Z2RXd29a'
    || 'U2w3YVdZb1pTRTlQVmhsS1hKbGRIVnliaUV4TzJsbUtDRnpaU2x5WlhSMWNtNGdlblVvWlNrc2MyVTlJVEFzSVRFN2RtRnlJSFE3YVdZb0tIUTlaUzUwWVdj'
    || 'aFBUMHpLU1ltSVNoMFBXVXVkR0ZuSVQwOU5Ta21KaWgwUFdVdWRIbHdaU3gwUFhRaFBUMGlhR1ZoWkNJbUpuUWhQVDBpWW05a2VTSW1KaUZJYVNobExuUjVj'
    || 'R1VzWlM1dFpXMXZhWHBsWkZCeWIzQnpLU2tzZENZbUtIUTlXbVVwS1h0cFppaFlhU2hsS1NsMGFISnZkeUJHZFNncExFVnljbTl5S0dNb05ERTRLU2s3Wm05'
    || 'eUtEdDBPeWxKZFNobExIUXBMSFE5Vm5Rb2RDNXVaWGgwVTJsaWJHbHVaeWw5YVdZb2VuVW9aU2tzWlM1MFlXYzlQVDB4TXlsN2FXWW9aVDFsTG0xbGJXOXBl'
    || 'bVZrVTNSaGRHVXNaVDFsSVQwOWJuVnNiRDlsTG1SbGFIbGtjbUYwWldRNmJuVnNiQ3doWlNsMGFISnZkeUJGY25KdmNpaGpLRE14TnlrcE8yVTZlMlp2Y2lo'
    || 'bFBXVXVibVY0ZEZOcFlteHBibWNzZEQwd08yVTdLWHRwWmlobExtNXZaR1ZVZVhCbFBUMDlPQ2w3ZG1GeUlHNDlaUzVrWVhSaE8ybG1LRzQ5UFQwaUx5UWlL'
    || 'WHRwWmloMFBUMDlNQ2w3V21VOVZuUW9aUzV1WlhoMFUybGliR2x1WnlrN1luSmxZV3NnWlgxMExTMTlaV3h6WlNCdUlUMDlJaVFpSmladUlUMDlJaVFoSWlZ'
    || 'bWJpRTlQU0lrUHlKOGZIUXJLMzFsUFdVdWJtVjRkRk5wWW14cGJtZDlXbVU5Ym5Wc2JIMTlaV3h6WlNCYVpUMVlaVDlXZENobExuTjBZWFJsVG05a1pTNXVa'
    || 'WGgwVTJsaWJHbHVaeWs2Ym5Wc2JEdHlaWFIxY200aE1IMW1kVzVqZEdsdmJpQkdkU2dwZTJadmNpaDJZWElnWlQxYVpUdGxPeWxsUFZaMEtHVXVibVY0ZEZO'
    || 'cFlteHBibWNwZldaMWJtTjBhVzl1SUUxdUtDbDdXbVU5V0dVOWJuVnNiQ3h6WlQwaE1YMW1kVzVqZEdsdmJpQnhhU2hsS1h0a2REMDlQVzUxYkd3L1pIUTlX'
    || 'MlZkT21SMExuQjFjMmdvWlNsOWRtRnlJRjltUFdkbExsSmxZV04wUTNWeWNtVnVkRUpoZEdOb1EyOXVabWxuTzJaMWJtTjBhVzl1SUhaeUtHVXNkQ3h1S1h0'
    || 'cFppaGxQVzR1Y21WbUxHVWhQVDF1ZFd4c0ppWjBlWEJsYjJZZ1pTRTlJbVoxYm1OMGFXOXVJaVltZEhsd1pXOW1JR1VoUFNKdlltcGxZM1FpS1h0cFppaHVM'
    || 'bDl2ZDI1bGNpbDdhV1lvYmoxdUxsOXZkMjVsY2l4dUtYdHBaaWh1TG5SaFp5RTlQVEVwZEdoeWIzY2dSWEp5YjNJb1l5Z3pNRGtwS1R0MllYSWdjajF1TG5O'
    || 'MFlYUmxUbTlrWlgxcFppZ2hjaWwwYUhKdmR5QkZjbkp2Y2loaktERTBOeXhsS1NrN2RtRnlJR3c5Y2l4cFBTSWlLMlU3Y21WMGRYSnVJSFFoUFQxdWRXeHNK'
    || 'aVowTG5KbFppRTlQVzUxYkd3bUpuUjVjR1Z2WmlCMExuSmxaajA5SW1aMWJtTjBhVzl1SWlZbWRDNXlaV1l1WDNOMGNtbHVaMUpsWmowOVBXay9kQzV5WldZ'
    || 'NktIUTlablZ1WTNScGIyNG9jeWw3ZG1GeUlHRTliQzV5Wldaek8zTTlQVDF1ZFd4c1AyUmxiR1YwWlNCaFcybGRPbUZiYVYwOWMzMHNkQzVmYzNSeWFXNW5V'
    || 'bVZtUFdrc2RDbDlhV1lvZEhsd1pXOW1JR1VoUFNKemRISnBibWNpS1hSb2NtOTNJRVZ5Y205eUtHTW9NamcwS1NrN2FXWW9JVzR1WDI5M2JtVnlLWFJvY205'
    || 'M0lFVnljbTl5S0dNb01qa3dMR1VwS1gxeVpYUjFjbTRnWlgxbWRXNWpkR2x2YmlCaGJDaGxMSFFwZTNSb2NtOTNJR1U5VDJKcVpXTjBMbkJ5YjNSdmRIbHda'
    || 'UzUwYjFOMGNtbHVaeTVqWVd4c0tIUXBMRVZ5Y205eUtHTW9NekVzWlQwOVBTSmJiMkpxWldOMElFOWlhbVZqZEYwaVB5SnZZbXBsWTNRZ2QybDBhQ0JyWlhs'
    || 'eklIc2lLMDlpYW1WamRDNXJaWGx6S0hRcExtcHZhVzRvSWl3Z0lpa3JJbjBpT21VcEtYMW1kVzVqZEdsdmJpQkJkU2hsS1h0MllYSWdkRDFsTGw5cGJtbDBP'
    || 'M0psZEhWeWJpQjBLR1V1WDNCaGVXeHZZV1FwZldaMWJtTjBhVzl1SUZWMUtHVXBlMloxYm1OMGFXOXVJSFFvYlN4d0tYdHBaaWhsS1h0MllYSWdkajF0TG1S'
    || 'bGJHVjBhVzl1Y3p0MlBUMDliblZzYkQ4b2JTNWtaV3hsZEdsdmJuTTlXM0JkTEcwdVpteGhaM044UFRFMktUcDJMbkIxYzJnb2NDbDlmV1oxYm1OMGFXOXVJ'
    || 'RzRvYlN4d0tYdHBaaWdoWlNseVpYUjFjbTRnYm5Wc2JEdG1iM0lvTzNBaFBUMXVkV3hzT3lsMEtHMHNjQ2tzY0Qxd0xuTnBZbXhwYm1jN2NtVjBkWEp1SUc1'
    || 'MWJHeDlablZ1WTNScGIyNGdjaWh0TEhBcGUyWnZjaWh0UFc1bGR5Qk5ZWEE3Y0NFOVBXNTFiR3c3S1hBdWEyVjVJVDA5Ym5Wc2JEOXRMbk5sZENod0xtdGxl'
    || 'U3h3S1RwdExuTmxkQ2h3TG1sdVpHVjRMSEFwTEhBOWNDNXphV0pzYVc1bk8zSmxkSFZ5YmlCdGZXWjFibU4wYVc5dUlHd29iU3h3S1h0eVpYUjFjbTRnYlQx'
    || 'aWRDaHRMSEFwTEcwdWFXNWtaWGc5TUN4dExuTnBZbXhwYm1jOWJuVnNiQ3h0ZldaMWJtTjBhVzl1SUdrb2JTeHdMSFlwZTNKbGRIVnliaUJ0TG1sdVpHVjRQ'
    || 'WFlzWlQ4b2RqMXRMbUZzZEdWeWJtRjBaU3gySVQwOWJuVnNiRDhvZGoxMkxtbHVaR1Y0TEhZOGNEOG9iUzVtYkdGbmMzdzlNaXh3S1RwMktUb29iUzVtYkdG'
    || 'bmMzdzlNaXh3S1NrNktHMHVabXhoWjNOOFBURXdORGcxTnpZc2NDbDlablZ1WTNScGIyNGdjeWh0S1h0eVpYUjFjbTRnWlNZbWJTNWhiSFJsY201aGRHVTlQ'
    || 'VDF1ZFd4c0ppWW9iUzVtYkdGbmMzdzlNaWtzYlgxbWRXNWpkR2x2YmlCaEtHMHNjQ3gyTEVNcGUzSmxkSFZ5YmlCd1BUMDliblZzYkh4OGNDNTBZV2NoUFQw'
    || 'MlB5aHdQVmR2S0hZc2JTNXRiMlJsTEVNcExIQXVjbVYwZFhKdVBXMHNjQ2s2S0hBOWJDaHdMSFlwTEhBdWNtVjBkWEp1UFcwc2NDbDlablZ1WTNScGIyNGda'
    || 'aWh0TEhBc2RpeERLWHQyWVhJZ2VqMTJMblI1Y0dVN2NtVjBkWEp1SUhvOVBUMU9aVDlUS0cwc2NDeDJMbkJ5YjNCekxtTm9hV3hrY21WdUxFTXNkaTVyWlhr'
    || 'cE9uQWhQVDF1ZFd4c0ppWW9jQzVsYkdWdFpXNTBWSGx3WlQwOVBYcDhmSFI1Y0dWdlppQjZQVDBpYjJKcVpXTjBJaVltZWlFOVBXNTFiR3dtSm5vdUpDUjBl'
    || 'WEJsYjJZOVBUMUdaU1ltUVhVb2VpazlQVDF3TG5SNWNHVXBQeWhEUFd3b2NDeDJMbkJ5YjNCektTeERMbkpsWmoxMmNpaHRMSEFzZGlrc1F5NXlaWFIxY200'
    || 'OWJTeERLVG9vUXoxTmJDaDJMblI1Y0dVc2RpNXJaWGtzZGk1d2NtOXdjeXh1ZFd4c0xHMHViVzlrWlN4REtTeERMbkpsWmoxMmNpaHRMSEFzZGlrc1F5NXla'
    || 'WFIxY200OWJTeERLWDFtZFc1amRHbHZiaUJuS0cwc2NDeDJMRU1wZTNKbGRIVnliaUJ3UFQwOWJuVnNiSHg4Y0M1MFlXY2hQVDAwZkh4d0xuTjBZWFJsVG05'
    || 'a1pTNWpiMjUwWVdsdVpYSkpibVp2SVQwOWRpNWpiMjUwWVdsdVpYSkpibVp2Zkh4d0xuTjBZWFJsVG05a1pTNXBiWEJzWlcxbGJuUmhkR2x2YmlFOVBYWXVh'
    || 'VzF3YkdWdFpXNTBZWFJwYjI0L0tIQTlRbThvZGl4dExtMXZaR1VzUXlrc2NDNXlaWFIxY200OWJTeHdLVG9vY0Qxc0tIQXNkaTVqYUdsc1pISmxibng4VzEw'
    || 'cExIQXVjbVYwZFhKdVBXMHNjQ2w5Wm5WdVkzUnBiMjRnVXlodExIQXNkaXhETEhvcGUzSmxkSFZ5YmlCd1BUMDliblZzYkh4OGNDNTBZV2NoUFQwM1B5aHdQ'
    || 'VzF1S0hZc2JTNXRiMlJsTEVNc2Vpa3NjQzV5WlhSMWNtNDliU3h3S1Rvb2NEMXNLSEFzZGlrc2NDNXlaWFIxY200OWJTeHdLWDFtZFc1amRHbHZiaUJyS0cw'
    || 'c2NDeDJLWHRwWmloMGVYQmxiMllnY0QwOUluTjBjbWx1WnlJbUpuQWhQVDBpSW54OGRIbHdaVzltSUhBOVBTSnVkVzFpWlhJaUtYSmxkSFZ5YmlCd1BWZHZL'
    || 'Q0lpSzNBc2JTNXRiMlJsTEhZcExIQXVjbVYwZFhKdVBXMHNjRHRwWmloMGVYQmxiMllnY0QwOUltOWlhbVZqZENJbUpuQWhQVDF1ZFd4c0tYdHpkMmwwWTJn'
    || 'b2NDNGtKSFI1Y0dWdlppbDdZMkZ6WlNCNlpUcHlaWFIxY200Z2RqMU5iQ2h3TG5SNWNHVXNjQzVyWlhrc2NDNXdjbTl3Y3l4dWRXeHNMRzB1Ylc5a1pTeDJL'
    || 'U3gyTG5KbFpqMTJjaWh0TEc1MWJHd3NjQ2tzZGk1eVpYUjFjbTQ5YlN4Mk8yTmhjMlVnZDJVNmNtVjBkWEp1SUhBOVFtOG9jQ3h0TG0xdlpHVXNkaWtzY0M1'
    || 'eVpYUjFjbTQ5YlN4d08yTmhjMlVnUm1VNmRtRnlJRU05Y0M1ZmFXNXBkRHR5WlhSMWNtNGdheWh0TEVNb2NDNWZjR0Y1Ykc5aFpDa3NkaWw5YVdZb1VXNG9j'
    || 'Q2w4ZkNRb2NDa3BjbVYwZFhKdUlIQTliVzRvY0N4dExtMXZaR1VzZGl4dWRXeHNLU3h3TG5KbGRIVnliajF0TEhBN1lXd29iU3h3S1gxeVpYUjFjbTRnYm5W'
    || 'c2JIMW1kVzVqZEdsdmJpQjNLRzBzY0N4MkxFTXBlM1poY2lCNlBYQWhQVDF1ZFd4c1AzQXVhMlY1T201MWJHdzdhV1lvZEhsd1pXOW1JSFk5UFNKemRISnBi'
    || 'bWNpSmlaMklUMDlJaUo4ZkhSNWNHVnZaaUIyUFQwaWJuVnRZbVZ5SWlseVpYUjFjbTRnZWlFOVBXNTFiR3cvYm5Wc2JEcGhLRzBzY0N3aUlpdDJMRU1wTzJs'
    || 'bUtIUjVjR1Z2WmlCMlBUMGliMkpxWldOMElpWW1kaUU5UFc1MWJHd3BlM04zYVhSamFDaDJMaVFrZEhsd1pXOW1LWHRqWVhObElIcGxPbkpsZEhWeWJpQjJM'
    || 'bXRsZVQwOVBYby9aaWh0TEhBc2RpeERLVHB1ZFd4c08yTmhjMlVnZDJVNmNtVjBkWEp1SUhZdWEyVjVQVDA5ZWo5bktHMHNjQ3gyTEVNcE9tNTFiR3c3WTJG'
    || 'elpTQkdaVHB5WlhSMWNtNGdlajEyTGw5cGJtbDBMSGNvYlN4d0xIb29kaTVmY0dGNWJHOWhaQ2tzUXlsOWFXWW9VVzRvZGlsOGZDUW9kaWtwY21WMGRYSnVJ'
    || 'SG9oUFQxdWRXeHNQMjUxYkd3NlV5aHRMSEFzZGl4RExHNTFiR3dwTzJGc0tHMHNkaWw5Y21WMGRYSnVJRzUxYkd4OVpuVnVZM1JwYjI0Z1R5aHRMSEFzZGl4'
    || 'RExIb3BlMmxtS0hSNWNHVnZaaUJEUFQwaWMzUnlhVzVuSWlZbVF5RTlQU0lpZkh4MGVYQmxiMllnUXowOUltNTFiV0psY2lJcGNtVjBkWEp1SUcwOWJTNW5a'
    || 'WFFvZGlsOGZHNTFiR3dzWVNod0xHMHNJaUlyUXl4NktUdHBaaWgwZVhCbGIyWWdRejA5SW05aWFtVmpkQ0ltSmtNaFBUMXVkV3hzS1h0emQybDBZMmdvUXk0'
    || 'a0pIUjVjR1Z2WmlsN1kyRnpaU0I2WlRweVpYUjFjbTRnYlQxdExtZGxkQ2hETG10bGVUMDlQVzUxYkd3L2RqcERMbXRsZVNsOGZHNTFiR3dzWmlod0xHMHNR'
    || 'eXg2S1R0allYTmxJSGRsT25KbGRIVnliaUJ0UFcwdVoyVjBLRU11YTJWNVBUMDliblZzYkQ5Mk9rTXVhMlY1S1h4OGJuVnNiQ3huS0hBc2JTeERMSG9wTzJO'
    || 'aGMyVWdSbVU2ZG1GeUlFRTlReTVmYVc1cGREdHlaWFIxY200Z1R5aHRMSEFzZGl4QktFTXVYM0JoZVd4dllXUXBMSG9wZldsbUtGRnVLRU1wZkh3a0tFTXBL'
    || 'WEpsZEhWeWJpQnRQVzB1WjJWMEtIWXBmSHh1ZFd4c0xGTW9jQ3h0TEVNc2VpeHVkV3hzS1R0aGJDaHdMRU1wZlhKbGRIVnliaUJ1ZFd4c2ZXWjFibU4wYVc5'
    || 'dUlFa29iU3h3TEhZc1F5bDdabTl5S0haaGNpQjZQVzUxYkd3c1FUMXVkV3hzTEZVOWNDeElQWEE5TUN4RlpUMXVkV3hzTzFVaFBUMXVkV3hzSmlaSVBIWXVi'
    || 'R1Z1WjNSb08wZ3JLeWw3VlM1cGJtUmxlRDVJUHloRlpUMVZMRlU5Ym5Wc2JDazZSV1U5VlM1emFXSnNhVzVuTzNaaGNpQnhQWGNvYlN4VkxIWmJTRjBzUXlr'
    || 'N2FXWW9jVDA5UFc1MWJHd3BlMVU5UFQxdWRXeHNKaVlvVlQxRlpTazdZbkpsWVd0OVpTWW1WU1ltY1M1aGJIUmxjbTVoZEdVOVBUMXVkV3hzSmlaMEtHMHNW'
    || 'U2tzY0QxcEtIRXNjQ3hJS1N4QlBUMDliblZzYkQ5NlBYRTZRUzV6YVdKc2FXNW5QWEVzUVQxeExGVTlSV1Y5YVdZb1NEMDlQWFl1YkdWdVozUm9LWEpsZEhW'
    || 'eWJpQnVLRzBzVlNrc2MyVW1Kbk51S0cwc1NDa3NlanRwWmloVlBUMDliblZzYkNsN1ptOXlLRHRJUEhZdWJHVnVaM1JvTzBnckt5bFZQV3NvYlN4MlcwaGRM'
    || 'RU1wTEZVaFBUMXVkV3hzSmlZb2NEMXBLRlVzY0N4SUtTeEJQVDA5Ym5Wc2JEOTZQVlU2UVM1emFXSnNhVzVuUFZVc1FUMVZLVHR5WlhSMWNtNGdjMlVtSm5O'
    || 'dUtHMHNTQ2tzZW4xbWIzSW9WVDF5S0cwc1ZTazdTRHgyTG14bGJtZDBhRHRJS3lzcFJXVTlUeWhWTEcwc1NDeDJXMGhkTEVNcExFVmxJVDA5Ym5Wc2JDWW1L'
    || 'R1VtSmtWbExtRnNkR1Z5Ym1GMFpTRTlQVzUxYkd3bUpsVXVaR1ZzWlhSbEtFVmxMbXRsZVQwOVBXNTFiR3cvU0RwRlpTNXJaWGtwTEhBOWFTaEZaU3h3TEVn'
    || 'cExFRTlQVDF1ZFd4c1AzbzlSV1U2UVM1emFXSnNhVzVuUFVWbExFRTlSV1VwTzNKbGRIVnliaUJsSmlaVkxtWnZja1ZoWTJnb1puVnVZM1JwYjI0b1pXNHBl'
    || 'M0psZEhWeWJpQjBLRzBzWlc0cGZTa3NjMlVtSm5OdUtHMHNTQ2tzZW4xbWRXNWpkR2x2YmlCRUtHMHNjQ3gyTEVNcGUzWmhjaUI2UFNRb2RpazdhV1lvZEhs'
    || 'd1pXOW1JSG9oUFNKbWRXNWpkR2x2YmlJcGRHaHliM2NnUlhKeWIzSW9ZeWd4TlRBcEtUdHBaaWgyUFhvdVkyRnNiQ2gyS1N4MlBUMXVkV3hzS1hSb2NtOTNJ'
    || 'RVZ5Y205eUtHTW9NVFV4S1NrN1ptOXlLSFpoY2lCQlBYbzliblZzYkN4VlBYQXNTRDF3UFRBc1JXVTliblZzYkN4eFBYWXVibVY0ZENncE8xVWhQVDF1ZFd4'
    || 'c0ppWWhjUzVrYjI1bE8wZ3JLeXh4UFhZdWJtVjRkQ2dwS1h0VkxtbHVaR1Y0UGtnL0tFVmxQVlVzVlQxdWRXeHNLVHBGWlQxVkxuTnBZbXhwYm1jN2RtRnlJ'
    || 'R1Z1UFhjb2JTeFZMSEV1ZG1Gc2RXVXNReWs3YVdZb1pXNDlQVDF1ZFd4c0tYdFZQVDA5Ym5Wc2JDWW1LRlU5UldVcE8ySnlaV0ZyZldVbUpsVW1KbVZ1TG1G'
    || 'c2RHVnlibUYwWlQwOVBXNTFiR3dtSm5Rb2JTeFZLU3h3UFdrb1pXNHNjQ3hJS1N4QlBUMDliblZzYkQ5NlBXVnVPa0V1YzJsaWJHbHVaejFsYml4QlBXVnVM'
    || 'RlU5UldWOWFXWW9jUzVrYjI1bEtYSmxkSFZ5YmlCdUtHMHNWU2tzYzJVbUpuTnVLRzBzU0Nrc2VqdHBaaWhWUFQwOWJuVnNiQ2w3Wm05eUtEc2hjUzVrYjI1'
    || 'bE8wZ3JLeXh4UFhZdWJtVjRkQ2dwS1hFOWF5aHRMSEV1ZG1Gc2RXVXNReWtzY1NFOVBXNTFiR3dtSmlod1BXa29jU3h3TEVncExFRTlQVDF1ZFd4c1Azbzlj'
    || 'VHBCTG5OcFlteHBibWM5Y1N4QlBYRXBPM0psZEhWeWJpQnpaU1ltYzI0b2JTeElLU3g2ZldadmNpaFZQWElvYlN4VktUc2hjUzVrYjI1bE8wZ3JLeXh4UFhZ'
    || 'dWJtVjRkQ2dwS1hFOVR5aFZMRzBzU0N4eExuWmhiSFZsTEVNcExIRWhQVDF1ZFd4c0ppWW9aU1ltY1M1aGJIUmxjbTVoZEdVaFBUMXVkV3hzSmlaVkxtUmxi'
    || 'R1YwWlNoeExtdGxlVDA5UFc1MWJHdy9TRHB4TG10bGVTa3NjRDFwS0hFc2NDeElLU3hCUFQwOWJuVnNiRDk2UFhFNlFTNXphV0pzYVc1blBYRXNRVDF4S1R0'
    || 'eVpYUjFjbTRnWlNZbVZTNW1iM0pGWVdOb0tHWjFibU4wYVc5dUtHVndLWHR5WlhSMWNtNGdkQ2h0TEdWd0tYMHBMSE5sSmlaemJpaHRMRWdwTEhwOVpuVnVZ'
    || 'M1JwYjI0Z2JXVW9iU3h3TEhZc1F5bDdhV1lvZEhsd1pXOW1JSFk5UFNKdlltcGxZM1FpSmlaMklUMDliblZzYkNZbWRpNTBlWEJsUFQwOVRtVW1Kbll1YTJW'
    || 'NVBUMDliblZzYkNZbUtIWTlkaTV3Y205d2N5NWphR2xzWkhKbGJpa3NkSGx3Wlc5bUlIWTlQU0p2WW1wbFkzUWlKaVoySVQwOWJuVnNiQ2w3YzNkcGRHTm9L'
    || 'SFl1SkNSMGVYQmxiMllwZTJOaGMyVWdlbVU2WlRwN1ptOXlLSFpoY2lCNlBYWXVhMlY1TEVFOWNEdEJJVDA5Ym5Wc2JEc3BlMmxtS0VFdWEyVjVQVDA5ZWls'
    || 'N2FXWW9lajEyTG5SNWNHVXNlajA5UFU1bEtYdHBaaWhCTG5SaFp6MDlQVGNwZTI0b2JTeEJMbk5wWW14cGJtY3BMSEE5YkNoQkxIWXVjSEp2Y0hNdVkyaHBi'
    || 'R1J5Wlc0cExIQXVjbVYwZFhKdVBXMHNiVDF3TzJKeVpXRnJJR1Y5ZldWc2MyVWdhV1lvUVM1bGJHVnRaVzUwVkhsd1pUMDlQWHA4ZkhSNWNHVnZaaUI2UFQw'
    || 'aWIySnFaV04wSWlZbWVpRTlQVzUxYkd3bUpub3VKQ1IwZVhCbGIyWTlQVDFHWlNZbVFYVW9laWs5UFQxQkxuUjVjR1VwZTI0b2JTeEJMbk5wWW14cGJtY3BM'
    || 'SEE5YkNoQkxIWXVjSEp2Y0hNcExIQXVjbVZtUFhaeUtHMHNRU3gyS1N4d0xuSmxkSFZ5YmoxdExHMDljRHRpY21WaGF5QmxmVzRvYlN4QktUdGljbVZoYTMx'
    || 'bGJITmxJSFFvYlN4QktUdEJQVUV1YzJsaWJHbHVaMzEyTG5SNWNHVTlQVDFPWlQ4b2NEMXRiaWgyTG5CeWIzQnpMbU5vYVd4a2NtVnVMRzB1Ylc5a1pTeERM'
    || 'SFl1YTJWNUtTeHdMbkpsZEhWeWJqMXRMRzA5Y0NrNktFTTlUV3dvZGk1MGVYQmxMSFl1YTJWNUxIWXVjSEp2Y0hNc2JuVnNiQ3h0TG0xdlpHVXNReWtzUXk1'
    || 'eVpXWTlkbklvYlN4d0xIWXBMRU11Y21WMGRYSnVQVzBzYlQxREtYMXlaWFIxY200Z2N5aHRLVHRqWVhObElIZGxPbVU2ZTJadmNpaEJQWFl1YTJWNU8zQWhQ'
    || 'VDF1ZFd4c095bDdhV1lvY0M1clpYazlQVDFCS1dsbUtIQXVkR0ZuUFQwOU5DWW1jQzV6ZEdGMFpVNXZaR1V1WTI5dWRHRnBibVZ5U1c1bWJ6MDlQWFl1WTI5'
    || 'dWRHRnBibVZ5U1c1bWJ5WW1jQzV6ZEdGMFpVNXZaR1V1YVcxd2JHVnRaVzUwWVhScGIyNDlQVDEyTG1sdGNHeGxiV1Z1ZEdGMGFXOXVLWHR1S0cwc2NDNXph'
    || 'V0pzYVc1bktTeHdQV3dvY0N4MkxtTm9hV3hrY21WdWZIeGJYU2tzY0M1eVpYUjFjbTQ5YlN4dFBYQTdZbkpsWVdzZ1pYMWxiSE5sZTI0b2JTeHdLVHRpY21W'
    || 'aGEzMWxiSE5sSUhRb2JTeHdLVHR3UFhBdWMybGliR2x1WjMxd1BVSnZLSFlzYlM1dGIyUmxMRU1wTEhBdWNtVjBkWEp1UFcwc2JUMXdmWEpsZEhWeWJpQnpL'
    || 'RzBwTzJOaGMyVWdSbVU2Y21WMGRYSnVJRUU5ZGk1ZmFXNXBkQ3h0WlNodExIQXNRU2gyTGw5d1lYbHNiMkZrS1N4REtYMXBaaWhSYmloMktTbHlaWFIxY200'
    || 'Z1NTaHRMSEFzZGl4REtUdHBaaWdrS0hZcEtYSmxkSFZ5YmlCRUtHMHNjQ3gyTEVNcE8yRnNLRzBzZGlsOWNtVjBkWEp1SUhSNWNHVnZaaUIyUFQwaWMzUnlh'
    || 'VzVuSWlZbWRpRTlQU0lpZkh4MGVYQmxiMllnZGowOUltNTFiV0psY2lJL0tIWTlJaUlyZGl4d0lUMDliblZzYkNZbWNDNTBZV2M5UFQwMlB5aHVLRzBzY0M1'
    || 'emFXSnNhVzVuS1N4d1BXd29jQ3gyS1N4d0xuSmxkSFZ5YmoxdExHMDljQ2s2S0c0b2JTeHdLU3h3UFZkdktIWXNiUzV0YjJSbExFTXBMSEF1Y21WMGRYSnVQ'
    || 'VzBzYlQxd0tTeHpLRzBwS1RwdUtHMHNjQ2w5Y21WMGRYSnVJRzFsZlhaaGNpQkpiajFWZFNnaE1Da3NKSFU5VlhVb0lURXBMR05zUFZkMEtHNTFiR3dwTEdS'
    || 'c1BXNTFiR3dzUkc0OWJuVnNiQ3hLYVQxdWRXeHNPMloxYm1OMGFXOXVJR0pwS0NsN1NtazlSRzQ5Wkd3OWJuVnNiSDFtZFc1amRHbHZiaUJsYnlobEtYdDJZ'
    || 'WElnZEQxamJDNWpkWEp5Wlc1ME8ybGxLR05zS1N4bExsOWpkWEp5Wlc1MFZtRnNkV1U5ZEgxbWRXNWpkR2x2YmlCMGJ5aGxMSFFzYmlsN1ptOXlLRHRsSVQw'
    || 'OWJuVnNiRHNwZTNaaGNpQnlQV1V1WVd4MFpYSnVZWFJsTzJsbUtDaGxMbU5vYVd4a1RHRnVaWE1tZENraFBUMTBQeWhsTG1Ob2FXeGtUR0Z1WlhOOFBYUXNj'
    || 'aUU5UFc1MWJHd21KaWh5TG1Ob2FXeGtUR0Z1WlhOOFBYUXBLVHB5SVQwOWJuVnNiQ1ltS0hJdVkyaHBiR1JNWVc1bGN5WjBLU0U5UFhRbUppaHlMbU5vYVd4'
    || 'a1RHRnVaWE44UFhRcExHVTlQVDF1S1dKeVpXRnJPMlU5WlM1eVpYUjFjbTU5ZldaMWJtTjBhVzl1SUhwdUtHVXNkQ2w3Wkd3OVpTeEthVDFFYmoxdWRXeHNM'
    || 'R1U5WlM1a1pYQmxibVJsYm1OcFpYTXNaU0U5UFc1MWJHd21KbVV1Wm1seWMzUkRiMjUwWlhoMElUMDliblZzYkNZbUtDaGxMbXhoYm1WekpuUXBJVDA5TUNZ'
    || 'bUtDUmxQU0V3S1N4bExtWnBjbk4wUTI5dWRHVjRkRDF1ZFd4c0tYMW1kVzVqZEdsdmJpQnVkQ2hsS1h0MllYSWdkRDFsTGw5amRYSnlaVzUwVm1Gc2RXVTdh'
    || 'V1lvU21raFBUMWxLV2xtS0dVOWUyTnZiblJsZUhRNlpTeHRaVzF2YVhwbFpGWmhiSFZsT25Rc2JtVjRkRHB1ZFd4c2ZTeEViajA5UFc1MWJHd3BlMmxtS0dS'
    || 'c1BUMDliblZzYkNsMGFISnZkeUJGY25KdmNpaGpLRE13T0NrcE8wUnVQV1VzWkd3dVpHVndaVzVrWlc1amFXVnpQWHRzWVc1bGN6b3dMR1pwY25OMFEyOXVk'
    || 'R1Y0ZERwbGZYMWxiSE5sSUVSdVBVUnVMbTVsZUhROVpUdHlaWFIxY200Z2RIMTJZWElnZFc0OWJuVnNiRHRtZFc1amRHbHZiaUJ1YnlobEtYdDFiajA5UFc1'
    || 'MWJHdy9kVzQ5VzJWZE9uVnVMbkIxYzJnb1pTbDlablZ1WTNScGIyNGdTSFVvWlN4MExHNHNjaWw3ZG1GeUlHdzlkQzVwYm5SbGNteGxZWFpsWkR0eVpYUjFj'
    || 'bTRnYkQwOVBXNTFiR3cvS0c0dWJtVjRkRDF1TEc1dktIUXBLVG9vYmk1dVpYaDBQV3d1Ym1WNGRDeHNMbTVsZUhROWJpa3NkQzVwYm5SbGNteGxZWFpsWkQx'
    || 'dUxGSjBLR1VzY2lsOVpuVnVZM1JwYjI0Z1VuUW9aU3gwS1h0bExteGhibVZ6ZkQxME8zWmhjaUJ1UFdVdVlXeDBaWEp1WVhSbE8yWnZjaWh1SVQwOWJuVnNi'
    || 'Q1ltS0c0dWJHRnVaWE44UFhRcExHNDlaU3hsUFdVdWNtVjBkWEp1TzJVaFBUMXVkV3hzT3lsbExtTm9hV3hrVEdGdVpYTjhQWFFzYmoxbExtRnNkR1Z5Ym1G'
    || 'MFpTeHVJVDA5Ym5Wc2JDWW1LRzR1WTJocGJHUk1ZVzVsYzN3OWRDa3NiajFsTEdVOVpTNXlaWFIxY200N2NtVjBkWEp1SUc0dWRHRm5QVDA5TXo5dUxuTjBZ'
    || 'WFJsVG05a1pUcHVkV3hzZlhaaGNpQkhkRDBoTVR0bWRXNWpkR2x2YmlCeWJ5aGxLWHRsTG5Wd1pHRjBaVkYxWlhWbFBYdGlZWE5sVTNSaGRHVTZaUzV0Wlcx'
    || 'dmFYcGxaRk4wWVhSbExHWnBjbk4wUW1GelpWVndaR0YwWlRwdWRXeHNMR3hoYzNSQ1lYTmxWWEJrWVhSbE9tNTFiR3dzYzJoaGNtVmtPbnR3Wlc1a2FXNW5P'
    || 'bTUxYkd3c2FXNTBaWEpzWldGMlpXUTZiblZzYkN4c1lXNWxjem93ZlN4bFptWmxZM1J6T201MWJHeDlmV1oxYm1OMGFXOXVJRloxS0dVc2RDbDdaVDFsTG5W'
    || 'd1pHRjBaVkYxWlhWbExIUXVkWEJrWVhSbFVYVmxkV1U5UFQxbEppWW9kQzUxY0dSaGRHVlJkV1YxWlQxN1ltRnpaVk4wWVhSbE9tVXVZbUZ6WlZOMFlYUmxM'
    || 'R1pwY25OMFFtRnpaVlZ3WkdGMFpUcGxMbVpwY25OMFFtRnpaVlZ3WkdGMFpTeHNZWE4wUW1GelpWVndaR0YwWlRwbExteGhjM1JDWVhObFZYQmtZWFJsTEhO'
    || 'b1lYSmxaRHBsTG5Ob1lYSmxaQ3hsWm1abFkzUnpPbVV1WldabVpXTjBjMzBwZldaMWJtTjBhVzl1SUV4MEtHVXNkQ2w3Y21WMGRYSnVlMlYyWlc1MFZHbHRa'
    || 'VHBsTEd4aGJtVTZkQ3gwWVdjNk1DeHdZWGxzYjJGa09tNTFiR3dzWTJGc2JHSmhZMnM2Ym5Wc2JDeHVaWGgwT201MWJHeDlmV1oxYm1OMGFXOXVJRXQwS0dV'
    || 'c2RDeHVLWHQyWVhJZ2NqMWxMblZ3WkdGMFpWRjFaWFZsTzJsbUtISTlQVDF1ZFd4c0tYSmxkSFZ5YmlCdWRXeHNPMmxtS0hJOWNpNXphR0Z5WldRc0tFc21N'
    || 'aWtoUFQwd0tYdDJZWElnYkQxeUxuQmxibVJwYm1jN2NtVjBkWEp1SUd3OVBUMXVkV3hzUDNRdWJtVjRkRDEwT2loMExtNWxlSFE5YkM1dVpYaDBMR3d1Ym1W'
    || 'NGREMTBLU3h5TG5CbGJtUnBibWM5ZEN4U2RDaGxMRzRwZlhKbGRIVnliaUJzUFhJdWFXNTBaWEpzWldGMlpXUXNiRDA5UFc1MWJHdy9LSFF1Ym1WNGREMTBM'
    || 'RzV2S0hJcEtUb29kQzV1WlhoMFBXd3VibVY0ZEN4c0xtNWxlSFE5ZENrc2NpNXBiblJsY214bFlYWmxaRDEwTEZKMEtHVXNiaWw5Wm5WdVkzUnBiMjRnWm13'
    || 'b1pTeDBMRzRwZTJsbUtIUTlkQzUxY0dSaGRHVlJkV1YxWlN4MElUMDliblZzYkNZbUtIUTlkQzV6YUdGeVpXUXNLRzRtTkRFNU5ESTBNQ2toUFQwd0tTbDdk'
    || 'bUZ5SUhJOWRDNXNZVzVsY3p0eUpqMWxMbkJsYm1ScGJtZE1ZVzVsY3l4dWZEMXlMSFF1YkdGdVpYTTliaXhuYVNobExHNHBmWDFtZFc1amRHbHZiaUJYZFNo'
    || 'bExIUXBlM1poY2lCdVBXVXVkWEJrWVhSbFVYVmxkV1VzY2oxbExtRnNkR1Z5Ym1GMFpUdHBaaWh5SVQwOWJuVnNiQ1ltS0hJOWNpNTFjR1JoZEdWUmRXVjFa'
    || 'U3h1UFQwOWNpa3BlM1poY2lCc1BXNTFiR3dzYVQxdWRXeHNPMmxtS0c0OWJpNW1hWEp6ZEVKaGMyVlZjR1JoZEdVc2JpRTlQVzUxYkd3cGUyUnZlM1poY2lC'
    || 'elBYdGxkbVZ1ZEZScGJXVTZiaTVsZG1WdWRGUnBiV1VzYkdGdVpUcHVMbXhoYm1Vc2RHRm5PbTR1ZEdGbkxIQmhlV3h2WVdRNmJpNXdZWGxzYjJGa0xHTmhi'
    || 'R3hpWVdOck9tNHVZMkZzYkdKaFkyc3NibVY0ZERwdWRXeHNmVHRwUFQwOWJuVnNiRDlzUFdrOWN6cHBQV2t1Ym1WNGREMXpMRzQ5Ymk1dVpYaDBmWGRvYVd4'
    || 'bEtHNGhQVDF1ZFd4c0tUdHBQVDA5Ym5Wc2JEOXNQV2s5ZERwcFBXa3VibVY0ZEQxMGZXVnNjMlVnYkQxcFBYUTdiajE3WW1GelpWTjBZWFJsT25JdVltRnpa'
    || 'Vk4wWVhSbExHWnBjbk4wUW1GelpWVndaR0YwWlRwc0xHeGhjM1JDWVhObFZYQmtZWFJsT21rc2MyaGhjbVZrT25JdWMyaGhjbVZrTEdWbVptVmpkSE02Y2k1'
    || 'bFptWmxZM1J6ZlN4bExuVndaR0YwWlZGMVpYVmxQVzQ3Y21WMGRYSnVmV1U5Ymk1c1lYTjBRbUZ6WlZWd1pHRjBaU3hsUFQwOWJuVnNiRDl1TG1acGNuTjBR'
    || 'bUZ6WlZWd1pHRjBaVDEwT21VdWJtVjRkRDEwTEc0dWJHRnpkRUpoYzJWVmNHUmhkR1U5ZEgxbWRXNWpkR2x2YmlCd2JDaGxMSFFzYml4eUtYdDJZWElnYkQx'
    || 'bExuVndaR0YwWlZGMVpYVmxPMGQwUFNFeE8zWmhjaUJwUFd3dVptbHljM1JDWVhObFZYQmtZWFJsTEhNOWJDNXNZWE4wUW1GelpWVndaR0YwWlN4aFBXd3Vj'
    || 'MmhoY21Wa0xuQmxibVJwYm1jN2FXWW9ZU0U5UFc1MWJHd3BlMnd1YzJoaGNtVmtMbkJsYm1ScGJtYzliblZzYkR0MllYSWdaajFoTEdjOVppNXVaWGgwTzJZ'
    || 'dWJtVjRkRDF1ZFd4c0xITTlQVDF1ZFd4c1AyazlaenB6TG01bGVIUTlaeXh6UFdZN2RtRnlJRk05WlM1aGJIUmxjbTVoZEdVN1V5RTlQVzUxYkd3bUppaFRQ'
    || 'Vk11ZFhCa1lYUmxVWFZsZFdVc1lUMVRMbXhoYzNSQ1lYTmxWWEJrWVhSbExHRWhQVDF6SmlZb1lUMDlQVzUxYkd3L1V5NW1hWEp6ZEVKaGMyVlZjR1JoZEdV'
    || 'OVp6cGhMbTVsZUhROVp5eFRMbXhoYzNSQ1lYTmxWWEJrWVhSbFBXWXBLWDFwWmlocElUMDliblZzYkNsN2RtRnlJR3M5YkM1aVlYTmxVM1JoZEdVN2N6MHdM'
    || 'Rk05WnoxbVBXNTFiR3dzWVQxcE8yUnZlM1poY2lCM1BXRXViR0Z1WlN4UFBXRXVaWFpsYm5SVWFXMWxPMmxtS0NoeUpuY3BQVDA5ZHlsN1V5RTlQVzUxYkd3'
    || 'bUppaFRQVk11Ym1WNGREMTdaWFpsYm5SVWFXMWxPazhzYkdGdVpUb3dMSFJoWnpwaExuUmhaeXh3WVhsc2IyRmtPbUV1Y0dGNWJHOWhaQ3hqWVd4c1ltRmph'
    || 'enBoTG1OaGJHeGlZV05yTEc1bGVIUTZiblZzYkgwcE8yVTZlM1poY2lCSlBXVXNSRDFoTzNOM2FYUmphQ2gzUFhRc1R6MXVMRVF1ZEdGbktYdGpZWE5sSURF'
    || 'NmFXWW9TVDFFTG5CaGVXeHZZV1FzZEhsd1pXOW1JRWs5UFNKbWRXNWpkR2x2YmlJcGUyczlTUzVqWVd4c0tFOHNheXgzS1R0aWNtVmhheUJsZldzOVNUdGlj'
    || 'bVZoYXlCbE8yTmhjMlVnTXpwSkxtWnNZV2R6UFVrdVpteGhaM01tTFRZMU5UTTNmREV5T0R0allYTmxJREE2YVdZb1NUMUVMbkJoZVd4dllXUXNkejEwZVhC'
    || 'bGIyWWdTVDA5SW1aMWJtTjBhVzl1SWo5SkxtTmhiR3dvVHl4ckxIY3BPa2tzZHowOWJuVnNiQ2xpY21WaGF5QmxPMnM5VFNoN2ZTeHJMSGNwTzJKeVpXRnJJ'
    || 'R1U3WTJGelpTQXlPa2QwUFNFd2ZYMWhMbU5oYkd4aVlXTnJJVDA5Ym5Wc2JDWW1ZUzVzWVc1bElUMDlNQ1ltS0dVdVpteGhaM044UFRZMExIYzliQzVsWm1a'
    || 'bFkzUnpMSGM5UFQxdWRXeHNQMnd1WldabVpXTjBjejFiWVYwNmR5NXdkWE5vS0dFcEtYMWxiSE5sSUU4OWUyVjJaVzUwVkdsdFpUcFBMR3hoYm1VNmR5eDBZ'
    || 'V2M2WVM1MFlXY3NjR0Y1Ykc5aFpEcGhMbkJoZVd4dllXUXNZMkZzYkdKaFkyczZZUzVqWVd4c1ltRmpheXh1WlhoME9tNTFiR3g5TEZNOVBUMXVkV3hzUHlo'
    || 'blBWTTlUeXhtUFdzcE9sTTlVeTV1WlhoMFBVOHNjM3c5ZHp0cFppaGhQV0V1Ym1WNGRDeGhQVDA5Ym5Wc2JDbDdhV1lvWVQxc0xuTm9ZWEpsWkM1d1pXNWth'
    || 'VzVuTEdFOVBUMXVkV3hzS1dKeVpXRnJPM2M5WVN4aFBYY3VibVY0ZEN4M0xtNWxlSFE5Ym5Wc2JDeHNMbXhoYzNSQ1lYTmxWWEJrWVhSbFBYY3NiQzV6YUdG'
    || 'eVpXUXVjR1Z1WkdsdVp6MXVkV3hzZlgxM2FHbHNaU2doTUNrN2FXWW9VejA5UFc1MWJHd21KaWhtUFdzcExHd3VZbUZ6WlZOMFlYUmxQV1lzYkM1bWFYSnpk'
    || 'RUpoYzJWVmNHUmhkR1U5Wnl4c0xteGhjM1JDWVhObFZYQmtZWFJsUFZNc2REMXNMbk5vWVhKbFpDNXBiblJsY214bFlYWmxaQ3gwSVQwOWJuVnNiQ2w3YkQx'
    || 'ME8yUnZJSE44UFd3dWJHRnVaU3hzUFd3dWJtVjRkRHQzYUdsc1pTaHNJVDA5ZENsOVpXeHpaU0JwUFQwOWJuVnNiQ1ltS0d3dWMyaGhjbVZrTG14aGJtVnpQ'
    || 'VEFwTzJSdWZEMXpMR1V1YkdGdVpYTTljeXhsTG0xbGJXOXBlbVZrVTNSaGRHVTlhMzE5Wm5WdVkzUnBiMjRnUW5Vb1pTeDBMRzRwZTJsbUtHVTlkQzVsWm1a'
    || 'bFkzUnpMSFF1WldabVpXTjBjejF1ZFd4c0xHVWhQVDF1ZFd4c0tXWnZjaWgwUFRBN2REeGxMbXhsYm1kMGFEdDBLeXNwZTNaaGNpQnlQV1ZiZEYwc2JEMXlM'
    || 'bU5oYkd4aVlXTnJPMmxtS0d3aFBUMXVkV3hzS1h0cFppaHlMbU5oYkd4aVlXTnJQVzUxYkd3c2NqMXVMSFI1Y0dWdlppQnNJVDBpWm5WdVkzUnBiMjRpS1hS'
    || 'b2NtOTNJRVZ5Y205eUtHTW9NVGt4TEd3cEtUdHNMbU5oYkd3b2NpbDlmWDEyWVhJZ1ozSTllMzBzWDNROVYzUW9aM0lwTEhseVBWZDBLR2R5S1N4NGNqMVhk'
    || 'Q2huY2lrN1puVnVZM1JwYjI0Z1lXNG9aU2w3YVdZb1pUMDlQV2R5S1hSb2NtOTNJRVZ5Y205eUtHTW9NVGMwS1NrN2NtVjBkWEp1SUdWOVpuVnVZM1JwYjI0'
    || 'Z2JHOG9aU3gwS1h0emQybDBZMmdvY21Vb2VISXNkQ2tzY21Vb2VYSXNaU2tzY21Vb1gzUXNaM0lwTEdVOWRDNXViMlJsVkhsd1pTeGxLWHRqWVhObElEazZZ'
    || 'MkZ6WlNBeE1UcDBQU2gwUFhRdVpHOWpkVzFsYm5SRmJHVnRaVzUwS1Q5MExtNWhiV1Z6Y0dGalpWVlNTVHBwYVNodWRXeHNMQ0lpS1R0aWNtVmhhenRrWlda'
    || 'aGRXeDBPbVU5WlQwOVBUZy9kQzV3WVhKbGJuUk9iMlJsT25Rc2REMWxMbTVoYldWemNHRmpaVlZTU1h4OGJuVnNiQ3hsUFdVdWRHRm5UbUZ0WlN4MFBXbHBL'
    || 'SFFzWlNsOWFXVW9YM1FwTEhKbEtGOTBMSFFwZldaMWJtTjBhVzl1SUVadUtDbDdhV1VvWDNRcExHbGxLSGx5S1N4cFpTaDRjaWw5Wm5WdVkzUnBiMjRnVVhV'
    || 'b1pTbDdZVzRvZUhJdVkzVnljbVZ1ZENrN2RtRnlJSFE5WVc0b1gzUXVZM1Z5Y21WdWRDa3NiajFwYVNoMExHVXVkSGx3WlNrN2RDRTlQVzRtSmloeVpTaDVj'
    || 'aXhsS1N4eVpTaGZkQ3h1S1NsOVpuVnVZM1JwYjI0Z2FXOG9aU2w3ZVhJdVkzVnljbVZ1ZEQwOVBXVW1KaWhwWlNoZmRDa3NhV1VvZVhJcEtYMTJZWElnWVdV'
    || 'OVYzUW9NQ2s3Wm5WdVkzUnBiMjRnYUd3b1pTbDdabTl5S0haaGNpQjBQV1U3ZENFOVBXNTFiR3c3S1h0cFppaDBMblJoWnowOVBURXpLWHQyWVhJZ2JqMTBM'
    || 'bTFsYlc5cGVtVmtVM1JoZEdVN2FXWW9iaUU5UFc1MWJHd21KaWh1UFc0dVpHVm9lV1J5WVhSbFpDeHVQVDA5Ym5Wc2JIeDhiaTVrWVhSaFBUMDlJaVEvSW54'
    || 'OGJpNWtZWFJoUFQwOUlpUWhJaWtwY21WMGRYSnVJSFI5Wld4elpTQnBaaWgwTG5SaFp6MDlQVEU1SmlaMExtMWxiVzlwZW1Wa1VISnZjSE11Y21WMlpXRnNU'
    || 'M0prWlhJaFBUMTJiMmxrSURBcGUybG1LQ2gwTG1ac1lXZHpKakV5T0NraFBUMHdLWEpsZEhWeWJpQjBmV1ZzYzJVZ2FXWW9kQzVqYUdsc1pDRTlQVzUxYkd3'
    || 'cGUzUXVZMmhwYkdRdWNtVjBkWEp1UFhRc2REMTBMbU5vYVd4a08yTnZiblJwYm5WbGZXbG1LSFE5UFQxbEtXSnlaV0ZyTzJadmNpZzdkQzV6YVdKc2FXNW5Q'
    || 'VDA5Ym5Wc2JEc3BlMmxtS0hRdWNtVjBkWEp1UFQwOWJuVnNiSHg4ZEM1eVpYUjFjbTQ5UFQxbEtYSmxkSFZ5YmlCdWRXeHNPM1E5ZEM1eVpYUjFjbTU5ZEM1'
    || 'emFXSnNhVzVuTG5KbGRIVnliajEwTG5KbGRIVnliaXgwUFhRdWMybGliR2x1WjMxeVpYUjFjbTRnYm5Wc2JIMTJZWElnYjI4OVcxMDdablZ1WTNScGIyNGdj'
    || 'MjhvS1h0bWIzSW9kbUZ5SUdVOU1EdGxQRzl2TG14bGJtZDBhRHRsS3lzcGIyOWJaVjB1WDNkdmNtdEpibEJ5YjJkeVpYTnpWbVZ5YzJsdmJsQnlhVzFoY25r'
    || 'OWJuVnNiRHR2Ynk1c1pXNW5kR2c5TUgxMllYSWdiV3c5WjJVdVVtVmhZM1JEZFhKeVpXNTBSR2x6Y0dGMFkyaGxjaXgxYnoxblpTNVNaV0ZqZEVOMWNuSmxi'
    || 'blJDWVhSamFFTnZibVpwWnl4amJqMHdMR05sUFc1MWJHd3NlV1U5Ym5Wc2JDeGZaVDF1ZFd4c0xIWnNQU0V4TEhkeVBTRXhMRjl5UFRBc1UyWTlNRHRtZFc1'
    || 'amRHbHZiaUJTWlNncGUzUm9jbTkzSUVWeWNtOXlLR01vTXpJeEtTbDlablZ1WTNScGIyNGdZVzhvWlN4MEtYdHBaaWgwUFQwOWJuVnNiQ2x5WlhSMWNtNGhN'
    || 'VHRtYjNJb2RtRnlJRzQ5TUR0dVBIUXViR1Z1WjNSb0ppWnVQR1V1YkdWdVozUm9PMjRyS3lscFppZ2hZM1FvWlZ0dVhTeDBXMjVkS1NseVpYUjFjbTRoTVR0'
    || 'eVpYUjFjbTRoTUgxbWRXNWpkR2x2YmlCamJ5aGxMSFFzYml4eUxHd3NhU2w3YVdZb1kyNDlhU3hqWlQxMExIUXViV1Z0YjJsNlpXUlRkR0YwWlQxdWRXeHNM'
    || 'SFF1ZFhCa1lYUmxVWFZsZFdVOWJuVnNiQ3gwTG14aGJtVnpQVEFzYld3dVkzVnljbVZ1ZEQxbFBUMDliblZzYkh4OFpTNXRaVzF2YVhwbFpGTjBZWFJsUFQw'
    || 'OWJuVnNiRDlxWmpwRFppeGxQVzRvY2l4c0tTeDNjaWw3YVQwd08yUnZlMmxtS0hkeVBTRXhMRjl5UFRBc01qVThQV2twZEdoeWIzY2dSWEp5YjNJb1l5Z3pN'
    || 'REVwS1R0cEt6MHhMRjlsUFhsbFBXNTFiR3dzZEM1MWNHUmhkR1ZSZFdWMVpUMXVkV3hzTEcxc0xtTjFjbkpsYm5ROVZHWXNaVDF1S0hJc2JDbDlkMmhwYkdV'
    || 'b2QzSXBmV2xtS0cxc0xtTjFjbkpsYm5ROWVHd3NkRDE1WlNFOVBXNTFiR3dtSm5sbExtNWxlSFFoUFQxdWRXeHNMR051UFRBc1gyVTllV1U5WTJVOWJuVnNi'
    || 'Q3gyYkQwaE1TeDBLWFJvY205M0lFVnljbTl5S0dNb016QXdLU2s3Y21WMGRYSnVJR1Y5Wm5WdVkzUnBiMjRnWm04b0tYdDJZWElnWlQxZmNpRTlQVEE3Y21W'
    || 'MGRYSnVJRjl5UFRBc1pYMW1kVzVqZEdsdmJpQlRkQ2dwZTNaaGNpQmxQWHR0WlcxdmFYcGxaRk4wWVhSbE9tNTFiR3dzWW1GelpWTjBZWFJsT201MWJHd3NZ'
    || 'bUZ6WlZGMVpYVmxPbTUxYkd3c2NYVmxkV1U2Ym5Wc2JDeHVaWGgwT201MWJHeDlPM0psZEhWeWJpQmZaVDA5UFc1MWJHdy9ZMlV1YldWdGIybDZaV1JUZEdG'
    || 'MFpUMWZaVDFsT2w5bFBWOWxMbTVsZUhROVpTeGZaWDFtZFc1amRHbHZiaUJ5ZENncGUybG1LSGxsUFQwOWJuVnNiQ2w3ZG1GeUlHVTlZMlV1WVd4MFpYSnVZ'
    || 'WFJsTzJVOVpTRTlQVzUxYkd3L1pTNXRaVzF2YVhwbFpGTjBZWFJsT201MWJHeDlaV3h6WlNCbFBYbGxMbTVsZUhRN2RtRnlJSFE5WDJVOVBUMXVkV3hzUDJO'
    || 'bExtMWxiVzlwZW1Wa1UzUmhkR1U2WDJVdWJtVjRkRHRwWmloMElUMDliblZzYkNsZlpUMTBMSGxsUFdVN1pXeHpaWHRwWmlobFBUMDliblZzYkNsMGFISnZk'
    || 'eUJGY25KdmNpaGpLRE14TUNrcE8zbGxQV1VzWlQxN2JXVnRiMmw2WldSVGRHRjBaVHA1WlM1dFpXMXZhWHBsWkZOMFlYUmxMR0poYzJWVGRHRjBaVHA1WlM1'
    || 'aVlYTmxVM1JoZEdVc1ltRnpaVkYxWlhWbE9ubGxMbUpoYzJWUmRXVjFaU3h4ZFdWMVpUcDVaUzV4ZFdWMVpTeHVaWGgwT201MWJHeDlMRjlsUFQwOWJuVnNi'
    || 'RDlqWlM1dFpXMXZhWHBsWkZOMFlYUmxQVjlsUFdVNlgyVTlYMlV1Ym1WNGREMWxmWEpsZEhWeWJpQmZaWDFtZFc1amRHbHZiaUJUY2lobExIUXBlM0psZEhW'
    || 'eWJpQjBlWEJsYjJZZ2REMDlJbVoxYm1OMGFXOXVJajkwS0dVcE9uUjlablZ1WTNScGIyNGdjRzhvWlNsN2RtRnlJSFE5Y25Rb0tTeHVQWFF1Y1hWbGRXVTdh'
    || 'V1lvYmowOVBXNTFiR3dwZEdoeWIzY2dSWEp5YjNJb1l5Z3pNVEVwS1R0dUxteGhjM1JTWlc1a1pYSmxaRkpsWkhWalpYSTlaVHQyWVhJZ2NqMTVaU3hzUFhJ'
    || 'dVltRnpaVkYxWlhWbExHazliaTV3Wlc1a2FXNW5PMmxtS0draFBUMXVkV3hzS1h0cFppaHNJVDA5Ym5Wc2JDbDdkbUZ5SUhNOWJDNXVaWGgwTzJ3dWJtVjRk'
    || 'RDFwTG01bGVIUXNhUzV1WlhoMFBYTjljaTVpWVhObFVYVmxkV1U5YkQxcExHNHVjR1Z1WkdsdVp6MXVkV3hzZldsbUtHd2hQVDF1ZFd4c0tYdHBQV3d1Ym1W'
    || 'NGRDeHlQWEl1WW1GelpWTjBZWFJsTzNaaGNpQmhQWE05Ym5Wc2JDeG1QVzUxYkd3c1p6MXBPMlJ2ZTNaaGNpQlRQV2N1YkdGdVpUdHBaaWdvWTI0bVV5azlQ'
    || 'VDFUS1dZaFBUMXVkV3hzSmlZb1pqMW1MbTVsZUhROWUyeGhibVU2TUN4aFkzUnBiMjQ2Wnk1aFkzUnBiMjRzYUdGelJXRm5aWEpUZEdGMFpUcG5MbWhoYzBW'
    || 'aFoyVnlVM1JoZEdVc1pXRm5aWEpUZEdGMFpUcG5MbVZoWjJWeVUzUmhkR1VzYm1WNGREcHVkV3hzZlNrc2NqMW5MbWhoYzBWaFoyVnlVM1JoZEdVL1p5NWxZ'
    || 'V2RsY2xOMFlYUmxPbVVvY2l4bkxtRmpkR2x2YmlrN1pXeHpaWHQyWVhJZ2F6MTdiR0Z1WlRwVExHRmpkR2x2YmpwbkxtRmpkR2x2Yml4b1lYTkZZV2RsY2xO'
    || 'MFlYUmxPbWN1YUdGelJXRm5aWEpUZEdGMFpTeGxZV2RsY2xOMFlYUmxPbWN1WldGblpYSlRkR0YwWlN4dVpYaDBPbTUxYkd4OU8yWTlQVDF1ZFd4c1B5aGhQ'
    || 'V1k5YXl4elBYSXBPbVk5Wmk1dVpYaDBQV3NzWTJVdWJHRnVaWE44UFZNc1pHNThQVk45WnoxbkxtNWxlSFI5ZDJocGJHVW9aeUU5UFc1MWJHd21KbWNoUFQx'
    || 'cEtUdG1QVDA5Ym5Wc2JEOXpQWEk2Wmk1dVpYaDBQV0VzWTNRb2NpeDBMbTFsYlc5cGVtVmtVM1JoZEdVcGZId29KR1U5SVRBcExIUXViV1Z0YjJsNlpXUlRk'
    || 'R0YwWlQxeUxIUXVZbUZ6WlZOMFlYUmxQWE1zZEM1aVlYTmxVWFZsZFdVOVppeHVMbXhoYzNSU1pXNWtaWEpsWkZOMFlYUmxQWEo5YVdZb1pUMXVMbWx1ZEdW'
    || 'eWJHVmhkbVZrTEdVaFBUMXVkV3hzS1h0c1BXVTdaRzhnYVQxc0xteGhibVVzWTJVdWJHRnVaWE44UFdrc1pHNThQV2tzYkQxc0xtNWxlSFE3ZDJocGJHVW9i'
    || 'Q0U5UFdVcGZXVnNjMlVnYkQwOVBXNTFiR3dtSmlodUxteGhibVZ6UFRBcE8zSmxkSFZ5Ymx0MExtMWxiVzlwZW1Wa1UzUmhkR1VzYmk1a2FYTndZWFJqYUYx'
    || 'OVpuVnVZM1JwYjI0Z2FHOG9aU2w3ZG1GeUlIUTljblFvS1N4dVBYUXVjWFZsZFdVN2FXWW9iajA5UFc1MWJHd3BkR2h5YjNjZ1JYSnliM0lvWXlnek1URXBL'
    || 'VHR1TG14aGMzUlNaVzVrWlhKbFpGSmxaSFZqWlhJOVpUdDJZWElnY2oxdUxtUnBjM0JoZEdOb0xHdzliaTV3Wlc1a2FXNW5MR2s5ZEM1dFpXMXZhWHBsWkZO'
    || 'MFlYUmxPMmxtS0d3aFBUMXVkV3hzS1h0dUxuQmxibVJwYm1jOWJuVnNiRHQyWVhJZ2N6MXNQV3d1Ym1WNGREdGtieUJwUFdVb2FTeHpMbUZqZEdsdmJpa3Nj'
    || 'ejF6TG01bGVIUTdkMmhwYkdVb2N5RTlQV3dwTzJOMEtHa3NkQzV0WlcxdmFYcGxaRk4wWVhSbEtYeDhLQ1JsUFNFd0tTeDBMbTFsYlc5cGVtVmtVM1JoZEdV'
    || 'OWFTeDBMbUpoYzJWUmRXVjFaVDA5UFc1MWJHd21KaWgwTG1KaGMyVlRkR0YwWlQxcEtTeHVMbXhoYzNSU1pXNWtaWEpsWkZOMFlYUmxQV2w5Y21WMGRYSnVX'
    || 'MmtzY2wxOVpuVnVZM1JwYjI0Z1IzVW9LWHQ5Wm5WdVkzUnBiMjRnUzNVb1pTeDBLWHQyWVhJZ2JqMWpaU3h5UFhKMEtDa3NiRDEwS0Nrc2FUMGhZM1FvY2k1'
    || 'dFpXMXZhWHBsWkZOMFlYUmxMR3dwTzJsbUtHa21KaWh5TG0xbGJXOXBlbVZrVTNSaGRHVTliQ3drWlQwaE1Da3NjajF5TG5GMVpYVmxMRzF2S0ZwMUxtSnBi'
    || 'bVFvYm5Wc2JDeHVMSElzWlNrc1cyVmRLU3h5TG1kbGRGTnVZWEJ6YUc5MElUMDlkSHg4YVh4OFgyVWhQVDF1ZFd4c0ppWmZaUzV0WlcxdmFYcGxaRk4wWVhS'
    || 'bExuUmhaeVl4S1h0cFppaHVMbVpzWVdkemZEMHlNRFE0TEVWeUtEa3NXSFV1WW1sdVpDaHVkV3hzTEc0c2NpeHNMSFFwTEhadmFXUWdNQ3h1ZFd4c0tTeFRa'
    || 'VDA5UFc1MWJHd3BkR2h5YjNjZ1JYSnliM0lvWXlnek5Ea3BLVHNvWTI0bU16QXBJVDA5TUh4OFdYVW9iaXgwTEd3cGZYSmxkSFZ5YmlCc2ZXWjFibU4wYVc5'
    || 'dUlGbDFLR1VzZEN4dUtYdGxMbVpzWVdkemZEMHhOak00TkN4bFBYdG5aWFJUYm1Gd2MyaHZkRHAwTEhaaGJIVmxPbTU5TEhROVkyVXVkWEJrWVhSbFVYVmxk'
    || 'V1VzZEQwOVBXNTFiR3cvS0hROWUyeGhjM1JGWm1abFkzUTZiblZzYkN4emRHOXlaWE02Ym5Wc2JIMHNZMlV1ZFhCa1lYUmxVWFZsZFdVOWRDeDBMbk4wYjNK'
    || 'bGN6MWJaVjBwT2lodVBYUXVjM1J2Y21WekxHNDlQVDF1ZFd4c1AzUXVjM1J2Y21WelBWdGxYVHB1TG5CMWMyZ29aU2twZldaMWJtTjBhVzl1SUZoMUtHVXNk'
    || 'Q3h1TEhJcGUzUXVkbUZzZFdVOWJpeDBMbWRsZEZOdVlYQnphRzkwUFhJc2NYVW9kQ2ttSmtwMUtHVXBmV1oxYm1OMGFXOXVJRnAxS0dVc2RDeHVLWHR5WlhS'
    || 'MWNtNGdiaWhtZFc1amRHbHZiaWdwZTNGMUtIUXBKaVpLZFNobEtYMHBmV1oxYm1OMGFXOXVJSEYxS0dVcGUzWmhjaUIwUFdVdVoyVjBVMjVoY0hOb2IzUTda'
    || 'VDFsTG5aaGJIVmxPM1J5ZVh0MllYSWdiajEwS0NrN2NtVjBkWEp1SVdOMEtHVXNiaWw5WTJGMFkyaDdjbVYwZFhKdUlUQjlmV1oxYm1OMGFXOXVJRXAxS0dV'
    || 'cGUzWmhjaUIwUFZKMEtHVXNNU2s3ZENFOVBXNTFiR3dtSm0xMEtIUXNaU3d4TEMweEtYMW1kVzVqZEdsdmJpQmlkU2hsS1h0MllYSWdkRDFUZENncE8zSmxk'
    || 'SFZ5YmlCMGVYQmxiMllnWlQwOUltWjFibU4wYVc5dUlpWW1LR1U5WlNncEtTeDBMbTFsYlc5cGVtVmtVM1JoZEdVOWRDNWlZWE5sVTNSaGRHVTlaU3hsUFh0'
    || 'd1pXNWthVzVuT201MWJHd3NhVzUwWlhKc1pXRjJaV1E2Ym5Wc2JDeHNZVzVsY3pvd0xHUnBjM0JoZEdOb09tNTFiR3dzYkdGemRGSmxibVJsY21Wa1VtVmtk'
    || 'V05sY2pwVGNpeHNZWE4wVW1WdVpHVnlaV1JUZEdGMFpUcGxmU3gwTG5GMVpYVmxQV1VzWlQxbExtUnBjM0JoZEdOb1BVNW1MbUpwYm1Rb2JuVnNiQ3hqWlN4'
    || 'bEtTeGJkQzV0WlcxdmFYcGxaRk4wWVhSbExHVmRmV1oxYm1OMGFXOXVJRVZ5S0dVc2RDeHVMSElwZTNKbGRIVnliaUJsUFh0MFlXYzZaU3hqY21WaGRHVTZk'
    || 'Q3hrWlhOMGNtOTVPbTRzWkdWd2N6cHlMRzVsZUhRNmJuVnNiSDBzZEQxalpTNTFjR1JoZEdWUmRXVjFaU3gwUFQwOWJuVnNiRDhvZEQxN2JHRnpkRVZtWm1W'
    || 'amREcHVkV3hzTEhOMGIzSmxjenB1ZFd4c2ZTeGpaUzUxY0dSaGRHVlJkV1YxWlQxMExIUXViR0Z6ZEVWbVptVmpkRDFsTG01bGVIUTlaU2s2S0c0OWRDNXNZ'
    || 'WE4wUldabVpXTjBMRzQ5UFQxdWRXeHNQM1F1YkdGemRFVm1abVZqZEQxbExtNWxlSFE5WlRvb2NqMXVMbTVsZUhRc2JpNXVaWGgwUFdVc1pTNXVaWGgwUFhJ'
    || 'c2RDNXNZWE4wUldabVpXTjBQV1VwS1N4bGZXWjFibU4wYVc5dUlHVmhLQ2w3Y21WMGRYSnVJSEowS0NrdWJXVnRiMmw2WldSVGRHRjBaWDFtZFc1amRHbHZi'
    || 'aUJuYkNobExIUXNiaXh5S1h0MllYSWdiRDFUZENncE8yTmxMbVpzWVdkemZEMWxMR3d1YldWdGIybDZaV1JUZEdGMFpUMUZjaWd4ZkhRc2JpeDJiMmxrSURB'
    || 'c2NqMDlQWFp2YVdRZ01EOXVkV3hzT25JcGZXWjFibU4wYVc5dUlIbHNLR1VzZEN4dUxISXBlM1poY2lCc1BYSjBLQ2s3Y2oxeVBUMDlkbTlwWkNBd1AyNTFi'
    || 'R3c2Y2p0MllYSWdhVDEyYjJsa0lEQTdhV1lvZVdVaFBUMXVkV3hzS1h0MllYSWdjejE1WlM1dFpXMXZhWHBsWkZOMFlYUmxPMmxtS0drOWN5NWtaWE4wY205'
    || 'NUxISWhQVDF1ZFd4c0ppWmhieWh5TEhNdVpHVndjeWtwZTJ3dWJXVnRiMmw2WldSVGRHRjBaVDFGY2loMExHNHNhU3h5S1R0eVpYUjFjbTU5ZldObExtWnNZ'
    || 'V2R6ZkQxbExHd3ViV1Z0YjJsNlpXUlRkR0YwWlQxRmNpZ3hmSFFzYml4cExISXBmV1oxYm1OMGFXOXVJSFJoS0dVc2RDbDdjbVYwZFhKdUlHZHNLRGd6T1RB'
    || 'Mk5UWXNPQ3hsTEhRcGZXWjFibU4wYVc5dUlHMXZLR1VzZENsN2NtVjBkWEp1SUhsc0tESXdORGdzT0N4bExIUXBmV1oxYm1OMGFXOXVJRzVoS0dVc2RDbDdj'
    || 'bVYwZFhKdUlIbHNLRFFzTWl4bExIUXBmV1oxYm1OMGFXOXVJSEpoS0dVc2RDbDdjbVYwZFhKdUlIbHNLRFFzTkN4bExIUXBmV1oxYm1OMGFXOXVJR3hoS0dV'
    || 'c2RDbDdhV1lvZEhsd1pXOW1JSFE5UFNKbWRXNWpkR2x2YmlJcGNtVjBkWEp1SUdVOVpTZ3BMSFFvWlNrc1puVnVZM1JwYjI0b0tYdDBLRzUxYkd3cGZUdHBa'
    || 'aWgwSVQxdWRXeHNLWEpsZEhWeWJpQmxQV1VvS1N4MExtTjFjbkpsYm5ROVpTeG1kVzVqZEdsdmJpZ3BlM1F1WTNWeWNtVnVkRDF1ZFd4c2ZYMW1kVzVqZEds'
    || 'dmJpQnBZU2hsTEhRc2JpbDdjbVYwZFhKdUlHNDliaUU5Ym5Wc2JEOXVMbU52Ym1OaGRDaGJaVjBwT201MWJHd3NlV3dvTkN3MExHeGhMbUpwYm1Rb2JuVnNi'
    || 'Q3gwTEdVcExHNHBmV1oxYm1OMGFXOXVJSFp2S0NsN2ZXWjFibU4wYVc5dUlHOWhLR1VzZENsN2RtRnlJRzQ5Y25Rb0tUdDBQWFE5UFQxMmIybGtJREEvYm5W'
    || 'c2JEcDBPM1poY2lCeVBXNHViV1Z0YjJsNlpXUlRkR0YwWlR0eVpYUjFjbTRnY2lFOVBXNTFiR3dtSm5RaFBUMXVkV3hzSmlaaGJ5aDBMSEpiTVYwcFAzSmJN'
    || 'RjA2S0c0dWJXVnRiMmw2WldSVGRHRjBaVDFiWlN4MFhTeGxLWDFtZFc1amRHbHZiaUJ6WVNobExIUXBlM1poY2lCdVBYSjBLQ2s3ZEQxMFBUMDlkbTlwWkNB'
    || 'd1AyNTFiR3c2ZER0MllYSWdjajF1TG0xbGJXOXBlbVZrVTNSaGRHVTdjbVYwZFhKdUlISWhQVDF1ZFd4c0ppWjBJVDA5Ym5Wc2JDWW1ZVzhvZEN4eVd6RmRL'
    || 'VDl5V3pCZE9paGxQV1VvS1N4dUxtMWxiVzlwZW1Wa1UzUmhkR1U5VzJVc2RGMHNaU2w5Wm5WdVkzUnBiMjRnZFdFb1pTeDBMRzRwZTNKbGRIVnliaWhqYmlZ'
    || 'eU1TazlQVDB3UHlobExtSmhjMlZUZEdGMFpTWW1LR1V1WW1GelpWTjBZWFJsUFNFeExDUmxQU0V3S1N4bExtMWxiVzlwZW1Wa1UzUmhkR1U5YmlrNktHTjBL'
    || 'RzRzZENsOGZDaHVQVUZ6S0Nrc1kyVXViR0Z1WlhOOFBXNHNaRzU4UFc0c1pTNWlZWE5sVTNSaGRHVTlJVEFwTEhRcGZXWjFibU4wYVc5dUlFVm1LR1VzZENs'
    || 'N2RtRnlJRzQ5ZEdVN2RHVTliaUU5UFRBbUpqUStiajl1T2pRc1pTZ2hNQ2s3ZG1GeUlISTlkVzh1ZEhKaGJuTnBkR2x2Ymp0MWJ5NTBjbUZ1YzJsMGFXOXVQ'
    || 'WHQ5TzNSeWVYdGxLQ0V4S1N4MEtDbDlabWx1WVd4c2VYdDBaVDF1TEhWdkxuUnlZVzV6YVhScGIyNDljbjE5Wm5WdVkzUnBiMjRnWVdFb0tYdHlaWFIxY200'
    || 'Z2NuUW9LUzV0WlcxdmFYcGxaRk4wWVhSbGZXWjFibU4wYVc5dUlHdG1LR1VzZEN4dUtYdDJZWElnY2oxeGRDaGxLVHRwWmlodVBYdHNZVzVsT25Jc1lXTjBh'
    || 'Vzl1T200c2FHRnpSV0ZuWlhKVGRHRjBaVG9oTVN4bFlXZGxjbE4wWVhSbE9tNTFiR3dzYm1WNGREcHVkV3hzZlN4allTaGxLU2xrWVNoMExHNHBPMlZzYzJV'
    || 'Z2FXWW9iajFJZFNobExIUXNiaXh5S1N4dUlUMDliblZzYkNsN2RtRnlJR3c5U1dVb0tUdHRkQ2h1TEdVc2NpeHNLU3htWVNodUxIUXNjaWw5ZldaMWJtTjBh'
    || 'Vzl1SUU1bUtHVXNkQ3h1S1h0MllYSWdjajF4ZENobEtTeHNQWHRzWVc1bE9uSXNZV04wYVc5dU9tNHNhR0Z6UldGblpYSlRkR0YwWlRvaE1TeGxZV2RsY2xO'
    || 'MFlYUmxPbTUxYkd3c2JtVjRkRHB1ZFd4c2ZUdHBaaWhqWVNobEtTbGtZU2gwTEd3cE8yVnNjMlY3ZG1GeUlHazlaUzVoYkhSbGNtNWhkR1U3YVdZb1pTNXNZ'
    || 'VzVsY3owOVBUQW1KaWhwUFQwOWJuVnNiSHg4YVM1c1lXNWxjejA5UFRBcEppWW9hVDEwTG14aGMzUlNaVzVrWlhKbFpGSmxaSFZqWlhJc2FTRTlQVzUxYkd3'
    || 'cEtYUnllWHQyWVhJZ2N6MTBMbXhoYzNSU1pXNWtaWEpsWkZOMFlYUmxMR0U5YVNoekxHNHBPMmxtS0d3dWFHRnpSV0ZuWlhKVGRHRjBaVDBoTUN4c0xtVmha'
    || 'MlZ5VTNSaGRHVTlZU3hqZENoaExITXBLWHQyWVhJZ1pqMTBMbWx1ZEdWeWJHVmhkbVZrTzJZOVBUMXVkV3hzUHloc0xtNWxlSFE5YkN4dWJ5aDBLU2s2S0d3'
    || 'dWJtVjRkRDFtTG01bGVIUXNaaTV1WlhoMFBXd3BMSFF1YVc1MFpYSnNaV0YyWldROWJEdHlaWFIxY201OWZXTmhkR05vZTMxbWFXNWhiR3g1ZTMxdVBVaDFL'
    || 'R1VzZEN4c0xISXBMRzRoUFQxdWRXeHNKaVlvYkQxSlpTZ3BMRzEwS0c0c1pTeHlMR3dwTEdaaEtHNHNkQ3h5S1NsOWZXWjFibU4wYVc5dUlHTmhLR1VwZTNa'
    || 'aGNpQjBQV1V1WVd4MFpYSnVZWFJsTzNKbGRIVnliaUJsUFQwOVkyVjhmSFFoUFQxdWRXeHNKaVowUFQwOVkyVjlablZ1WTNScGIyNGdaR0VvWlN4MEtYdDNj'
    || 'ajEyYkQwaE1EdDJZWElnYmoxbExuQmxibVJwYm1jN2JqMDlQVzUxYkd3L2RDNXVaWGgwUFhRNktIUXVibVY0ZEQxdUxtNWxlSFFzYmk1dVpYaDBQWFFwTEdV'
    || 'dWNHVnVaR2x1WnoxMGZXWjFibU4wYVc5dUlHWmhLR1VzZEN4dUtYdHBaaWdvYmlZME1UazBNalF3S1NFOVBUQXBlM1poY2lCeVBYUXViR0Z1WlhNN2NpWTla'
    || 'UzV3Wlc1a2FXNW5UR0Z1WlhNc2JudzljaXgwTG14aGJtVnpQVzRzWjJrb1pTeHVLWDE5ZG1GeUlIaHNQWHR5WldGa1EyOXVkR1Y0ZERwdWRDeDFjMlZEWVd4'
    || 'c1ltRmphenBTWlN4MWMyVkRiMjUwWlhoME9sSmxMSFZ6WlVWbVptVmpkRHBTWlN4MWMyVkpiWEJsY21GMGFYWmxTR0Z1Wkd4bE9sSmxMSFZ6WlVsdWMyVnlk'
    || 'R2x2YmtWbVptVmpkRHBTWlN4MWMyVk1ZWGx2ZFhSRlptWmxZM1E2VW1Vc2RYTmxUV1Z0YnpwU1pTeDFjMlZTWldSMVkyVnlPbEpsTEhWelpWSmxaanBTWlN4'
    || 'MWMyVlRkR0YwWlRwU1pTeDFjMlZFWldKMVoxWmhiSFZsT2xKbExIVnpaVVJsWm1WeWNtVmtWbUZzZFdVNlVtVXNkWE5sVkhKaGJuTnBkR2x2YmpwU1pTeDFj'
    || 'MlZOZFhSaFlteGxVMjkxY21ObE9sSmxMSFZ6WlZONWJtTkZlSFJsY201aGJGTjBiM0psT2xKbExIVnpaVWxrT2xKbExIVnVjM1JoWW14bFgybHpUbVYzVW1W'
    || 'amIyNWphV3hsY2pvaE1YMHNhbVk5ZTNKbFlXUkRiMjUwWlhoME9tNTBMSFZ6WlVOaGJHeGlZV05yT21aMWJtTjBhVzl1S0dVc2RDbDdjbVYwZFhKdUlGTjBL'
    || 'Q2t1YldWdGIybDZaV1JUZEdGMFpUMWJaU3gwUFQwOWRtOXBaQ0F3UDI1MWJHdzZkRjBzWlgwc2RYTmxRMjl1ZEdWNGREcHVkQ3gxYzJWRlptWmxZM1E2ZEdF'
    || 'c2RYTmxTVzF3WlhKaGRHbDJaVWhoYm1Sc1pUcG1kVzVqZEdsdmJpaGxMSFFzYmlsN2NtVjBkWEp1SUc0OWJpRTliblZzYkQ5dUxtTnZibU5oZENoYlpWMHBP'
    || 'bTUxYkd3c1oyd29OREU1TkRNd09DdzBMR3hoTG1KcGJtUW9iblZzYkN4MExHVXBMRzRwZlN4MWMyVk1ZWGx2ZFhSRlptWmxZM1E2Wm5WdVkzUnBiMjRvWlN4'
    || 'MEtYdHlaWFIxY200Z1oyd29OREU1TkRNd09DdzBMR1VzZENsOUxIVnpaVWx1YzJWeWRHbHZia1ZtWm1WamREcG1kVzVqZEdsdmJpaGxMSFFwZTNKbGRIVnli'
    || 'aUJuYkNnMExESXNaU3gwS1gwc2RYTmxUV1Z0YnpwbWRXNWpkR2x2YmlobExIUXBlM1poY2lCdVBWTjBLQ2s3Y21WMGRYSnVJSFE5ZEQwOVBYWnZhV1FnTUQ5'
    || 'dWRXeHNPblFzWlQxbEtDa3NiaTV0WlcxdmFYcGxaRk4wWVhSbFBWdGxMSFJkTEdWOUxIVnpaVkpsWkhWalpYSTZablZ1WTNScGIyNG9aU3gwTEc0cGUzWmhj'
    || 'aUJ5UFZOMEtDazdjbVYwZFhKdUlIUTliaUU5UFhadmFXUWdNRDl1S0hRcE9uUXNjaTV0WlcxdmFYcGxaRk4wWVhSbFBYSXVZbUZ6WlZOMFlYUmxQWFFzWlQx'
    || 'N2NHVnVaR2x1WnpwdWRXeHNMR2x1ZEdWeWJHVmhkbVZrT201MWJHd3NiR0Z1WlhNNk1DeGthWE53WVhSamFEcHVkV3hzTEd4aGMzUlNaVzVrWlhKbFpGSmxa'
    || 'SFZqWlhJNlpTeHNZWE4wVW1WdVpHVnlaV1JUZEdGMFpUcDBmU3h5TG5GMVpYVmxQV1VzWlQxbExtUnBjM0JoZEdOb1BXdG1MbUpwYm1Rb2JuVnNiQ3hqWlN4'
    || 'bEtTeGJjaTV0WlcxdmFYcGxaRk4wWVhSbExHVmRmU3gxYzJWU1pXWTZablZ1WTNScGIyNG9aU2w3ZG1GeUlIUTlVM1FvS1R0eVpYUjFjbTRnWlQxN1kzVnlj'
    || 'bVZ1ZERwbGZTeDBMbTFsYlc5cGVtVmtVM1JoZEdVOVpYMHNkWE5sVTNSaGRHVTZZblVzZFhObFJHVmlkV2RXWVd4MVpUcDJieXgxYzJWRVpXWmxjbkpsWkZa'
    || 'aGJIVmxPbVoxYm1OMGFXOXVLR1VwZTNKbGRIVnliaUJUZENncExtMWxiVzlwZW1Wa1UzUmhkR1U5Wlgwc2RYTmxWSEpoYm5OcGRHbHZianBtZFc1amRHbHZi'
    || 'aWdwZTNaaGNpQmxQV0oxS0NFeEtTeDBQV1ZiTUYwN2NtVjBkWEp1SUdVOVJXWXVZbWx1WkNodWRXeHNMR1ZiTVYwcExGTjBLQ2t1YldWdGIybDZaV1JUZEdG'
    || 'MFpUMWxMRnQwTEdWZGZTeDFjMlZOZFhSaFlteGxVMjkxY21ObE9tWjFibU4wYVc5dUtDbDdmU3gxYzJWVGVXNWpSWGgwWlhKdVlXeFRkRzl5WlRwbWRXNWpk'
    || 'R2x2YmlobExIUXNiaWw3ZG1GeUlISTlZMlVzYkQxVGRDZ3BPMmxtS0hObEtYdHBaaWh1UFQwOWRtOXBaQ0F3S1hSb2NtOTNJRVZ5Y205eUtHTW9OREEzS1Nr'
    || 'N2JqMXVLQ2w5Wld4elpYdHBaaWh1UFhRb0tTeFRaVDA5UFc1MWJHd3BkR2h5YjNjZ1JYSnliM0lvWXlnek5Ea3BLVHNvWTI0bU16QXBJVDA5TUh4OFdYVW9j'
    || 'aXgwTEc0cGZXd3ViV1Z0YjJsNlpXUlRkR0YwWlQxdU8zWmhjaUJwUFh0MllXeDFaVHB1TEdkbGRGTnVZWEJ6YUc5ME9uUjlPM0psZEhWeWJpQnNMbkYxWlhW'
    || 'bFBXa3NkR0VvV25VdVltbHVaQ2h1ZFd4c0xISXNhU3hsS1N4YlpWMHBMSEl1Wm14aFozTjhQVEl3TkRnc1JYSW9PU3hZZFM1aWFXNWtLRzUxYkd3c2NpeHBM'
    || 'RzRzZENrc2RtOXBaQ0F3TEc1MWJHd3BMRzU5TEhWelpVbGtPbVoxYm1OMGFXOXVLQ2w3ZG1GeUlHVTlVM1FvS1N4MFBWTmxMbWxrWlc1MGFXWnBaWEpRY21W'
    || 'bWFYZzdhV1lvYzJVcGUzWmhjaUJ1UFZSMExISTlRM1E3Ymowb2NpWitLREU4UERNeUxXRjBLSElwTFRFcEtTNTBiMU4wY21sdVp5Z3pNaWtyYml4MFBTSTZJ'
    || 'aXQwS3lKU0lpdHVMRzQ5WDNJckt5d3dQRzRtSmloMEt6MGlTQ0lyYmk1MGIxTjBjbWx1Wnlnek1pa3BMSFFyUFNJNkluMWxiSE5sSUc0OVUyWXJLeXgwUFNJ'
    || 'NklpdDBLeUp5SWl0dUxuUnZVM1J5YVc1bktETXlLU3NpT2lJN2NtVjBkWEp1SUdVdWJXVnRiMmw2WldSVGRHRjBaVDEwZlN4MWJuTjBZV0pzWlY5cGMwNWxk'
    || 'MUpsWTI5dVkybHNaWEk2SVRGOUxFTm1QWHR5WldGa1EyOXVkR1Y0ZERwdWRDeDFjMlZEWVd4c1ltRmphenB2WVN4MWMyVkRiMjUwWlhoME9tNTBMSFZ6WlVW'
    || 'bVptVmpkRHB0Ynl4MWMyVkpiWEJsY21GMGFYWmxTR0Z1Wkd4bE9tbGhMSFZ6WlVsdWMyVnlkR2x2YmtWbVptVmpkRHB1WVN4MWMyVk1ZWGx2ZFhSRlptWmxZ'
    || 'M1E2Y21Fc2RYTmxUV1Z0YnpwellTeDFjMlZTWldSMVkyVnlPbkJ2TEhWelpWSmxaanBsWVN4MWMyVlRkR0YwWlRwbWRXNWpkR2x2YmlncGUzSmxkSFZ5YmlC'
    || 'd2J5aFRjaWw5TEhWelpVUmxZblZuVm1Gc2RXVTZkbThzZFhObFJHVm1aWEp5WldSV1lXeDFaVHBtZFc1amRHbHZiaWhsS1h0MllYSWdkRDF5ZENncE8zSmxk'
    || 'SFZ5YmlCMVlTaDBMSGxsTG0xbGJXOXBlbVZrVTNSaGRHVXNaU2w5TEhWelpWUnlZVzV6YVhScGIyNDZablZ1WTNScGIyNG9LWHQyWVhJZ1pUMXdieWhUY2ls'
    || 'Yk1GMHNkRDF5ZENncExtMWxiVzlwZW1Wa1UzUmhkR1U3Y21WMGRYSnVXMlVzZEYxOUxIVnpaVTExZEdGaWJHVlRiM1Z5WTJVNlIzVXNkWE5sVTNsdVkwVjRk'
    || 'R1Z5Ym1Gc1UzUnZjbVU2UzNVc2RYTmxTV1E2WVdFc2RXNXpkR0ZpYkdWZmFYTk9aWGRTWldOdmJtTnBiR1Z5T2lFeGZTeFVaajE3Y21WaFpFTnZiblJsZUhR'
    || 'NmJuUXNkWE5sUTJGc2JHSmhZMnM2YjJFc2RYTmxRMjl1ZEdWNGREcHVkQ3gxYzJWRlptWmxZM1E2Ylc4c2RYTmxTVzF3WlhKaGRHbDJaVWhoYm1Sc1pUcHBZ'
    || 'U3gxYzJWSmJuTmxjblJwYjI1RlptWmxZM1E2Ym1Fc2RYTmxUR0Y1YjNWMFJXWm1aV04wT25KaExIVnpaVTFsYlc4NmMyRXNkWE5sVW1Wa2RXTmxjanBvYnl4'
    || 'MWMyVlNaV1k2WldFc2RYTmxVM1JoZEdVNlpuVnVZM1JwYjI0b0tYdHlaWFIxY200Z2FHOG9VM0lwZlN4MWMyVkVaV0oxWjFaaGJIVmxPblp2TEhWelpVUmxa'
    || 'bVZ5Y21Wa1ZtRnNkV1U2Wm5WdVkzUnBiMjRvWlNsN2RtRnlJSFE5Y25Rb0tUdHlaWFIxY200Z2VXVTlQVDF1ZFd4c1AzUXViV1Z0YjJsNlpXUlRkR0YwWlQx'
    || 'bE9uVmhLSFFzZVdVdWJXVnRiMmw2WldSVGRHRjBaU3hsS1gwc2RYTmxWSEpoYm5OcGRHbHZianBtZFc1amRHbHZiaWdwZTNaaGNpQmxQV2h2S0ZOeUtWc3dY'
    || 'U3gwUFhKMEtDa3ViV1Z0YjJsNlpXUlRkR0YwWlR0eVpYUjFjbTViWlN4MFhYMHNkWE5sVFhWMFlXSnNaVk52ZFhKalpUcEhkU3gxYzJWVGVXNWpSWGgwWlhK'
    || 'dVlXeFRkRzl5WlRwTGRTeDFjMlZKWkRwaFlTeDFibk4wWVdKc1pWOXBjMDVsZDFKbFkyOXVZMmxzWlhJNklURjlPMloxYm1OMGFXOXVJR1owS0dVc2RDbDdh'
    || 'V1lvWlNZbVpTNWtaV1poZFd4MFVISnZjSE1wZTNROVRTaDdmU3gwS1N4bFBXVXVaR1ZtWVhWc2RGQnliM0J6TzJadmNpaDJZWElnYmlCcGJpQmxLWFJiYmww'
    || 'OVBUMTJiMmxrSURBbUppaDBXMjVkUFdWYmJsMHBPM0psZEhWeWJpQjBmWEpsZEhWeWJpQjBmV1oxYm1OMGFXOXVJR2R2S0dVc2RDeHVMSElwZTNROVpTNXRa'
    || 'VzF2YVhwbFpGTjBZWFJsTEc0OWJpaHlMSFFwTEc0OWJqMDliblZzYkQ5ME9rMG9lMzBzZEN4dUtTeGxMbTFsYlc5cGVtVmtVM1JoZEdVOWJpeGxMbXhoYm1W'
    || 'elBUMDlNQ1ltS0dVdWRYQmtZWFJsVVhWbGRXVXVZbUZ6WlZOMFlYUmxQVzRwZlhaaGNpQjNiRDE3YVhOTmIzVnVkR1ZrT21aMWJtTjBhVzl1S0dVcGUzSmxk'
    || 'SFZ5YmlobFBXVXVYM0psWVdOMFNXNTBaWEp1WVd4ektUOXViaWhsS1QwOVBXVTZJVEY5TEdWdWNYVmxkV1ZUWlhSVGRHRjBaVHBtZFc1amRHbHZiaWhsTEhR'
    || 'c2JpbDdaVDFsTGw5eVpXRmpkRWx1ZEdWeWJtRnNjenQyWVhJZ2NqMUpaU2dwTEd3OWNYUW9aU2tzYVQxTWRDaHlMR3dwTzJrdWNHRjViRzloWkQxMExHNGhQ'
    || 'VzUxYkd3bUppaHBMbU5oYkd4aVlXTnJQVzRwTEhROVMzUW9aU3hwTEd3cExIUWhQVDF1ZFd4c0ppWW9iWFFvZEN4bExHd3NjaWtzWm13b2RDeGxMR3dwS1gw'
    || 'c1pXNXhkV1YxWlZKbGNHeGhZMlZUZEdGMFpUcG1kVzVqZEdsdmJpaGxMSFFzYmlsN1pUMWxMbDl5WldGamRFbHVkR1Z5Ym1Gc2N6dDJZWElnY2oxSlpTZ3BM'
    || 'R3c5Y1hRb1pTa3NhVDFNZENoeUxHd3BPMmt1ZEdGblBURXNhUzV3WVhsc2IyRmtQWFFzYmlFOWJuVnNiQ1ltS0drdVkyRnNiR0poWTJzOWJpa3NkRDFMZENo'
    || 'bExHa3NiQ2tzZENFOVBXNTFiR3dtSmlodGRDaDBMR1VzYkN4eUtTeG1iQ2gwTEdVc2JDa3BmU3hsYm5GMVpYVmxSbTl5WTJWVmNHUmhkR1U2Wm5WdVkzUnBi'
    || 'MjRvWlN4MEtYdGxQV1V1WDNKbFlXTjBTVzUwWlhKdVlXeHpPM1poY2lCdVBVbGxLQ2tzY2oxeGRDaGxLU3hzUFV4MEtHNHNjaWs3YkM1MFlXYzlNaXgwSVQx'
    || 'dWRXeHNKaVlvYkM1allXeHNZbUZqYXoxMEtTeDBQVXQwS0dVc2JDeHlLU3gwSVQwOWJuVnNiQ1ltS0cxMEtIUXNaU3h5TEc0cExHWnNLSFFzWlN4eUtTbDlm'
    || 'VHRtZFc1amRHbHZiaUJ3WVNobExIUXNiaXh5TEd3c2FTeHpLWHR5WlhSMWNtNGdaVDFsTG5OMFlYUmxUbTlrWlN4MGVYQmxiMllnWlM1emFHOTFiR1JEYjIx'
    || 'd2IyNWxiblJWY0dSaGRHVTlQU0ptZFc1amRHbHZiaUkvWlM1emFHOTFiR1JEYjIxd2IyNWxiblJWY0dSaGRHVW9jaXhwTEhNcE9uUXVjSEp2ZEc5MGVYQmxK'
    || 'aVowTG5CeWIzUnZkSGx3WlM1cGMxQjFjbVZTWldGamRFTnZiWEJ2Ym1WdWREOGhZWElvYml4eUtYeDhJV0Z5S0d3c2FTazZJVEI5Wm5WdVkzUnBiMjRnYUdF'
    || 'b1pTeDBMRzRwZTNaaGNpQnlQU0V4TEd3OVFuUXNhVDEwTG1OdmJuUmxlSFJVZVhCbE8zSmxkSFZ5YmlCMGVYQmxiMllnYVQwOUltOWlhbVZqZENJbUpta2hQ'
    || 'VDF1ZFd4c1AyazliblFvYVNrNktHdzlWV1VvZENrL2JHNDZWR1V1WTNWeWNtVnVkQ3h5UFhRdVkyOXVkR1Y0ZEZSNWNHVnpMR2s5S0hJOWNpRTliblZzYkNr'
    || 'L1RHNG9aU3hzS1RwQ2RDa3NkRDF1WlhjZ2RDaHVMR2twTEdVdWJXVnRiMmw2WldSVGRHRjBaVDEwTG5OMFlYUmxJVDA5Ym5Wc2JDWW1kQzV6ZEdGMFpTRTlQ'
    || 'WFp2YVdRZ01EOTBMbk4wWVhSbE9tNTFiR3dzZEM1MWNHUmhkR1Z5UFhkc0xHVXVjM1JoZEdWT2IyUmxQWFFzZEM1ZmNtVmhZM1JKYm5SbGNtNWhiSE05WlN4'
    || 'eUppWW9aVDFsTG5OMFlYUmxUbTlrWlN4bExsOWZjbVZoWTNSSmJuUmxjbTVoYkUxbGJXOXBlbVZrVlc1dFlYTnJaV1JEYUdsc1pFTnZiblJsZUhROWJDeGxM'
    || 'bDlmY21WaFkzUkpiblJsY201aGJFMWxiVzlwZW1Wa1RXRnphMlZrUTJocGJHUkRiMjUwWlhoMFBXa3BMSFI5Wm5WdVkzUnBiMjRnYldFb1pTeDBMRzRzY2ls'
    || 'N1pUMTBMbk4wWVhSbExIUjVjR1Z2WmlCMExtTnZiWEJ2Ym1WdWRGZHBiR3hTWldObGFYWmxVSEp2Y0hNOVBTSm1kVzVqZEdsdmJpSW1KblF1WTI5dGNHOXVa'
    || 'VzUwVjJsc2JGSmxZMlZwZG1WUWNtOXdjeWh1TEhJcExIUjVjR1Z2WmlCMExsVk9VMEZHUlY5amIyMXdiMjVsYm5SWGFXeHNVbVZqWldsMlpWQnliM0J6UFQw'
    || 'aVpuVnVZM1JwYjI0aUppWjBMbFZPVTBGR1JWOWpiMjF3YjI1bGJuUlhhV3hzVW1WalpXbDJaVkJ5YjNCektHNHNjaWtzZEM1emRHRjBaU0U5UFdVbUpuZHNM'
    || 'bVZ1Y1hWbGRXVlNaWEJzWVdObFUzUmhkR1VvZEN4MExuTjBZWFJsTEc1MWJHd3BmV1oxYm1OMGFXOXVJSGx2S0dVc2RDeHVMSElwZTNaaGNpQnNQV1V1YzNS'
    || 'aGRHVk9iMlJsTzJ3dWNISnZjSE05Yml4c0xuTjBZWFJsUFdVdWJXVnRiMmw2WldSVGRHRjBaU3hzTG5KbFpuTTllMzBzY204b1pTazdkbUZ5SUdrOWRDNWpi'
    || 'MjUwWlhoMFZIbHdaVHQwZVhCbGIyWWdhVDA5SW05aWFtVmpkQ0ltSm1raFBUMXVkV3hzUDJ3dVkyOXVkR1Y0ZEQxdWRDaHBLVG9vYVQxVlpTaDBLVDlzYmpw'
    || 'VVpTNWpkWEp5Wlc1MExHd3VZMjl1ZEdWNGREMU1iaWhsTEdrcEtTeHNMbk4wWVhSbFBXVXViV1Z0YjJsNlpXUlRkR0YwWlN4cFBYUXVaMlYwUkdWeWFYWmxa'
    || 'Rk4wWVhSbFJuSnZiVkJ5YjNCekxIUjVjR1Z2WmlCcFBUMGlablZ1WTNScGIyNGlKaVlvWjI4b1pTeDBMR2tzYmlrc2JDNXpkR0YwWlQxbExtMWxiVzlwZW1W'
    || 'a1UzUmhkR1VwTEhSNWNHVnZaaUIwTG1kbGRFUmxjbWwyWldSVGRHRjBaVVp5YjIxUWNtOXdjejA5SW1aMWJtTjBhVzl1SW54OGRIbHdaVzltSUd3dVoyVjBV'
    || 'MjVoY0hOb2IzUkNaV1p2Y21WVmNHUmhkR1U5UFNKbWRXNWpkR2x2YmlKOGZIUjVjR1Z2WmlCc0xsVk9VMEZHUlY5amIyMXdiMjVsYm5SWGFXeHNUVzkxYm5R'
    || 'aFBTSm1kVzVqZEdsdmJpSW1KblI1Y0dWdlppQnNMbU52YlhCdmJtVnVkRmRwYkd4TmIzVnVkQ0U5SW1aMWJtTjBhVzl1SW54OEtIUTliQzV6ZEdGMFpTeDBl'
    || 'WEJsYjJZZ2JDNWpiMjF3YjI1bGJuUlhhV3hzVFc5MWJuUTlQU0ptZFc1amRHbHZiaUltSm13dVkyOXRjRzl1Wlc1MFYybHNiRTF2ZFc1MEtDa3NkSGx3Wlc5'
    || 'bUlHd3VWVTVUUVVaRlgyTnZiWEJ2Ym1WdWRGZHBiR3hOYjNWdWREMDlJbVoxYm1OMGFXOXVJaVltYkM1VlRsTkJSa1ZmWTI5dGNHOXVaVzUwVjJsc2JFMXZk'
    || 'VzUwS0Nrc2RDRTlQV3d1YzNSaGRHVW1KbmRzTG1WdWNYVmxkV1ZTWlhCc1lXTmxVM1JoZEdVb2JDeHNMbk4wWVhSbExHNTFiR3dwTEhCc0tHVXNiaXhzTEhJ'
    || 'cExHd3VjM1JoZEdVOVpTNXRaVzF2YVhwbFpGTjBZWFJsS1N4MGVYQmxiMllnYkM1amIyMXdiMjVsYm5SRWFXUk5iM1Z1ZEQwOUltWjFibU4wYVc5dUlpWW1L'
    || 'R1V1Wm14aFozTjhQVFF4T1RRek1EZ3BmV1oxYm1OMGFXOXVJRUZ1S0dVc2RDbDdkSEo1ZTNaaGNpQnVQU0lpTEhJOWREdGtieUJ1S3oxWUtISXBMSEk5Y2k1'
    || 'eVpYUjFjbTQ3ZDJocGJHVW9jaWs3ZG1GeUlHdzlibjFqWVhSamFDaHBLWHRzUFdBS1JYSnliM0lnWjJWdVpYSmhkR2x1WnlCemRHRmphem9nWUN0cExtMWxj'
    || 'M05oWjJVcllBcGdLMmt1YzNSaFkydDljbVYwZFhKdWUzWmhiSFZsT21Vc2MyOTFjbU5sT25Rc2MzUmhZMnM2YkN4a2FXZGxjM1E2Ym5Wc2JIMTlablZ1WTNS'
    || 'cGIyNGdlRzhvWlN4MExHNHBlM0psZEhWeWJudDJZV3gxWlRwbExITnZkWEpqWlRwdWRXeHNMSE4wWVdOck9tNC9QMjUxYkd3c1pHbG5aWE4wT25RL1AyNTFi'
    || 'R3g5ZldaMWJtTjBhVzl1SUhkdktHVXNkQ2w3ZEhKNWUyTnZibk52YkdVdVpYSnliM0lvZEM1MllXeDFaU2w5WTJGMFkyZ29iaWw3YzJWMFZHbHRaVzkxZENo'
    || 'bWRXNWpkR2x2YmlncGUzUm9jbTkzSUc1OUtYMTlkbUZ5SUZKbVBYUjVjR1Z2WmlCWFpXRnJUV0Z3UFQwaVpuVnVZM1JwYjI0aVAxZGxZV3ROWVhBNlRXRndP'
    || 'MloxYm1OMGFXOXVJSFpoS0dVc2RDeHVLWHR1UFV4MEtDMHhMRzRwTEc0dWRHRm5QVE1zYmk1d1lYbHNiMkZrUFh0bGJHVnRaVzUwT201MWJHeDlPM1poY2lC'
    || 'eVBYUXVkbUZzZFdVN2NtVjBkWEp1SUc0dVkyRnNiR0poWTJzOVpuVnVZM1JwYjI0b0tYdERiSHg4S0VOc1BTRXdMRVJ2UFhJcExIZHZLR1VzZENsOUxHNTla'
    || 'blZ1WTNScGIyNGdaMkVvWlN4MExHNHBlMjQ5VEhRb0xURXNiaWtzYmk1MFlXYzlNenQyWVhJZ2NqMWxMblI1Y0dVdVoyVjBSR1Z5YVhabFpGTjBZWFJsUm5K'
    || 'dmJVVnljbTl5TzJsbUtIUjVjR1Z2WmlCeVBUMGlablZ1WTNScGIyNGlLWHQyWVhJZ2JEMTBMblpoYkhWbE8yNHVjR0Y1Ykc5aFpEMW1kVzVqZEdsdmJpZ3Bl'
    || 'M0psZEhWeWJpQnlLR3dwZlN4dUxtTmhiR3hpWVdOclBXWjFibU4wYVc5dUtDbDdkMjhvWlN4MEtYMTlkbUZ5SUdrOVpTNXpkR0YwWlU1dlpHVTdjbVYwZFhK'
    || 'dUlHa2hQVDF1ZFd4c0ppWjBlWEJsYjJZZ2FTNWpiMjF3YjI1bGJuUkVhV1JEWVhSamFEMDlJbVoxYm1OMGFXOXVJaVltS0c0dVkyRnNiR0poWTJzOVpuVnVZ'
    || 'M1JwYjI0b0tYdDNieWhsTEhRcExIUjVjR1Z2WmlCeUlUMGlablZ1WTNScGIyNGlKaVlvV0hROVBUMXVkV3hzUDFoMFBXNWxkeUJUWlhRb1czUm9hWE5kS1Rw'
    || 'WWRDNWhaR1FvZEdocGN5a3BPM1poY2lCelBYUXVjM1JoWTJzN2RHaHBjeTVqYjIxd2IyNWxiblJFYVdSRFlYUmphQ2gwTG5aaGJIVmxMSHRqYjIxd2IyNWxi'
    || 'blJUZEdGamF6cHpJVDA5Ym5Wc2JEOXpPaUlpZlNsOUtTeHVmV1oxYm1OMGFXOXVJSGxoS0dVc2RDeHVLWHQyWVhJZ2NqMWxMbkJwYm1kRFlXTm9aVHRwWmlo'
    || 'eVBUMDliblZzYkNsN2NqMWxMbkJwYm1kRFlXTm9aVDF1WlhjZ1VtWTdkbUZ5SUd3OWJtVjNJRk5sZER0eUxuTmxkQ2gwTEd3cGZXVnNjMlVnYkQxeUxtZGxk'
    || 'Q2gwS1N4c1BUMDlkbTlwWkNBd0ppWW9iRDF1WlhjZ1UyVjBMSEl1YzJWMEtIUXNiQ2twTzJ3dWFHRnpLRzRwZkh3b2JDNWhaR1FvYmlrc1pUMVhaaTVpYVc1'
    || 'a0tHNTFiR3dzWlN4MExHNHBMSFF1ZEdobGJpaGxMR1VwS1gxbWRXNWpkR2x2YmlCNFlTaGxLWHRrYjN0MllYSWdkRHRwWmlnb2REMWxMblJoWnowOVBURXpL'
    || 'U1ltS0hROVpTNXRaVzF2YVhwbFpGTjBZWFJsTEhROWRDRTlQVzUxYkd3L2RDNWtaV2g1WkhKaGRHVmtJVDA5Ym5Wc2JEb2hNQ2tzZENseVpYUjFjbTRnWlR0'
    || 'bFBXVXVjbVYwZFhKdWZYZG9hV3hsS0dVaFBUMXVkV3hzS1R0eVpYUjFjbTRnYm5Wc2JIMW1kVzVqZEdsdmJpQjNZU2hsTEhRc2JpeHlMR3dwZTNKbGRIVnli'
    || 'aWhsTG0xdlpHVW1NU2s5UFQwd1B5aGxQVDA5ZEQ5bExtWnNZV2R6ZkQwMk5UVXpOam9vWlM1bWJHRm5jM3c5TVRJNExHNHVabXhoWjNOOFBURXpNVEEzTWl4'
    || 'dUxtWnNZV2R6SmowdE5USTRNRFVzYmk1MFlXYzlQVDB4SmlZb2JpNWhiSFJsY201aGRHVTlQVDF1ZFd4c1AyNHVkR0ZuUFRFM09paDBQVXgwS0MweExERXBM'
    || 'SFF1ZEdGblBUSXNTM1FvYml4MExERXBLU2tzYmk1c1lXNWxjM3c5TVNrc1pTazZLR1V1Wm14aFozTjhQVFkxTlRNMkxHVXViR0Z1WlhNOWJDeGxLWDEyWVhJ'
    || 'Z1RHWTlaMlV1VW1WaFkzUkRkWEp5Wlc1MFQzZHVaWElzSkdVOUlURTdablZ1WTNScGIyNGdUV1VvWlN4MExHNHNjaWw3ZEM1amFHbHNaRDFsUFQwOWJuVnNi'
    || 'RDhrZFNoMExHNTFiR3dzYml4eUtUcEpiaWgwTEdVdVkyaHBiR1FzYml4eUtYMW1kVzVqZEdsdmJpQmZZU2hsTEhRc2JpeHlMR3dwZTI0OWJpNXlaVzVrWlhJ'
    || 'N2RtRnlJR2s5ZEM1eVpXWTdjbVYwZFhKdUlIcHVLSFFzYkNrc2NqMWpieWhsTEhRc2JpeHlMR2tzYkNrc2JqMW1ieWdwTEdVaFBUMXVkV3hzSmlZaEpHVS9L'
    || 'SFF1ZFhCa1lYUmxVWFZsZFdVOVpTNTFjR1JoZEdWUmRXVjFaU3gwTG1ac1lXZHpKajB0TWpBMU15eGxMbXhoYm1WekpqMStiQ3hQZENobExIUXNiQ2twT2lo'
    || 'elpTWW1iaVltUzJrb2RDa3NkQzVtYkdGbmMzdzlNU3hOWlNobExIUXNjaXhzS1N4MExtTm9hV3hrS1gxbWRXNWpkR2x2YmlCVFlTaGxMSFFzYml4eUxHd3Bl'
    || 'MmxtS0dVOVBUMXVkV3hzS1h0MllYSWdhVDF1TG5SNWNHVTdjbVYwZFhKdUlIUjVjR1Z2WmlCcFBUMGlablZ1WTNScGIyNGlKaVloVm04b2FTa21KbWt1WkdW'
    || 'bVlYVnNkRkJ5YjNCelBUMDlkbTlwWkNBd0ppWnVMbU52YlhCaGNtVTlQVDF1ZFd4c0ppWnVMbVJsWm1GMWJIUlFjbTl3Y3owOVBYWnZhV1FnTUQ4b2RDNTBZ'
    || 'V2M5TVRVc2RDNTBlWEJsUFdrc1JXRW9aU3gwTEdrc2NpeHNLU2s2S0dVOVRXd29iaTUwZVhCbExHNTFiR3dzY2l4MExIUXViVzlrWlN4c0tTeGxMbkpsWmox'
    || 'MExuSmxaaXhsTG5KbGRIVnliajEwTEhRdVkyaHBiR1E5WlNsOWFXWW9hVDFsTG1Ob2FXeGtMQ2hsTG14aGJtVnpKbXdwUFQwOU1DbDdkbUZ5SUhNOWFTNXRa'
    || 'VzF2YVhwbFpGQnliM0J6TzJsbUtHNDliaTVqYjIxd1lYSmxMRzQ5YmlFOVBXNTFiR3cvYmpwaGNpeHVLSE1zY2lrbUptVXVjbVZtUFQwOWRDNXlaV1lwY21W'
    || 'MGRYSnVJRTkwS0dVc2RDeHNLWDF5WlhSMWNtNGdkQzVtYkdGbmMzdzlNU3hsUFdKMEtHa3NjaWtzWlM1eVpXWTlkQzV5WldZc1pTNXlaWFIxY200OWRDeDBM'
    || 'bU5vYVd4a1BXVjlablZ1WTNScGIyNGdSV0VvWlN4MExHNHNjaXhzS1h0cFppaGxJVDA5Ym5Wc2JDbDdkbUZ5SUdrOVpTNXRaVzF2YVhwbFpGQnliM0J6TzJs'
    || 'bUtHRnlLR2tzY2lrbUptVXVjbVZtUFQwOWRDNXlaV1lwYVdZb0pHVTlJVEVzZEM1d1pXNWthVzVuVUhKdmNITTljajFwTENobExteGhibVZ6Sm13cElUMDlN'
    || 'Q2tvWlM1bWJHRm5jeVl4TXpFd056SXBJVDA5TUNZbUtDUmxQU0V3S1R0bGJITmxJSEpsZEhWeWJpQjBMbXhoYm1WelBXVXViR0Z1WlhNc1QzUW9aU3gwTEd3'
    || 'cGZYSmxkSFZ5YmlCZmJ5aGxMSFFzYml4eUxHd3BmV1oxYm1OMGFXOXVJR3RoS0dVc2RDeHVLWHQyWVhJZ2NqMTBMbkJsYm1ScGJtZFFjbTl3Y3l4c1BYSXVZ'
    || 'MmhwYkdSeVpXNHNhVDFsSVQwOWJuVnNiRDlsTG0xbGJXOXBlbVZrVTNSaGRHVTZiblZzYkR0cFppaHlMbTF2WkdVOVBUMGlhR2xrWkdWdUlpbHBaaWdvZEM1'
    || 'dGIyUmxKakVwUFQwOU1DbDBMbTFsYlc5cGVtVmtVM1JoZEdVOWUySmhjMlZNWVc1bGN6b3dMR05oWTJobFVHOXZiRHB1ZFd4c0xIUnlZVzV6YVhScGIyNXpP'
    || 'bTUxYkd4OUxISmxLQ1J1TEhGbEtTeHhaWHc5Ymp0bGJITmxlMmxtS0NodUpqRXdOek0zTkRFNE1qUXBQVDA5TUNseVpYUjFjbTRnWlQxcElUMDliblZzYkQ5'
    || 'cExtSmhjMlZNWVc1bGMzeHVPbTRzZEM1c1lXNWxjejEwTG1Ob2FXeGtUR0Z1WlhNOU1UQTNNemMwTVRneU5DeDBMbTFsYlc5cGVtVmtVM1JoZEdVOWUySmhj'
    || 'MlZNWVc1bGN6cGxMR05oWTJobFVHOXZiRHB1ZFd4c0xIUnlZVzV6YVhScGIyNXpPbTUxYkd4OUxIUXVkWEJrWVhSbFVYVmxkV1U5Ym5Wc2JDeHlaU2drYml4'
    || 'eFpTa3NjV1Y4UFdVc2JuVnNiRHQwTG0xbGJXOXBlbVZrVTNSaGRHVTllMkpoYzJWTVlXNWxjem93TEdOaFkyaGxVRzl2YkRwdWRXeHNMSFJ5WVc1emFYUnBi'
    || 'MjV6T201MWJHeDlMSEk5YVNFOVBXNTFiR3cvYVM1aVlYTmxUR0Z1WlhNNmJpeHlaU2drYml4eFpTa3NjV1Y4UFhKOVpXeHpaU0JwSVQwOWJuVnNiRDhvY2ox'
    || 'cExtSmhjMlZNWVc1bGMzeHVMSFF1YldWdGIybDZaV1JUZEdGMFpUMXVkV3hzS1RweVBXNHNjbVVvSkc0c2NXVXBMSEZsZkQxeU8zSmxkSFZ5YmlCTlpTaGxM'
    || 'SFFzYkN4dUtTeDBMbU5vYVd4a2ZXWjFibU4wYVc5dUlFNWhLR1VzZENsN2RtRnlJRzQ5ZEM1eVpXWTdLR1U5UFQxdWRXeHNKaVp1SVQwOWJuVnNiSHg4WlNF'
    || 'OVBXNTFiR3dtSm1VdWNtVm1JVDA5YmlrbUppaDBMbVpzWVdkemZEMDFNVElzZEM1bWJHRm5jM3c5TWpBNU56RTFNaWw5Wm5WdVkzUnBiMjRnWDI4b1pTeDBM'
    || 'RzRzY2l4c0tYdDJZWElnYVQxVlpTaHVLVDlzYmpwVVpTNWpkWEp5Wlc1ME8zSmxkSFZ5YmlCcFBVeHVLSFFzYVNrc2VtNG9kQ3hzS1N4dVBXTnZLR1VzZEN4'
    || 'dUxISXNhU3hzS1N4eVBXWnZLQ2tzWlNFOVBXNTFiR3dtSmlFa1pUOG9kQzUxY0dSaGRHVlJkV1YxWlQxbExuVndaR0YwWlZGMVpYVmxMSFF1Wm14aFozTW1Q'
    || 'UzB5TURVekxHVXViR0Z1WlhNbVBYNXNMRTkwS0dVc2RDeHNLU2s2S0hObEppWnlKaVpMYVNoMEtTeDBMbVpzWVdkemZEMHhMRTFsS0dVc2RDeHVMR3dwTEhR'
    || 'dVkyaHBiR1FwZldaMWJtTjBhVzl1SUdwaEtHVXNkQ3h1TEhJc2JDbDdhV1lvVldVb2Jpa3BlM1poY2lCcFBTRXdPMnhzS0hRcGZXVnNjMlVnYVQwaE1UdHBa'
    || 'aWg2YmloMExHd3BMSFF1YzNSaGRHVk9iMlJsUFQwOWJuVnNiQ2xUYkNobExIUXBMR2hoS0hRc2JpeHlLU3g1YnloMExHNHNjaXhzS1N4eVBTRXdPMlZzYzJV'
    || 'Z2FXWW9aVDA5UFc1MWJHd3BlM1poY2lCelBYUXVjM1JoZEdWT2IyUmxMR0U5ZEM1dFpXMXZhWHBsWkZCeWIzQnpPM011Y0hKdmNITTlZVHQyWVhJZ1pqMXpM'
    || 'bU52Ym5SbGVIUXNaejF1TG1OdmJuUmxlSFJVZVhCbE8zUjVjR1Z2WmlCblBUMGliMkpxWldOMElpWW1aeUU5UFc1MWJHdy9aejF1ZENobktUb29aejFWWlNo'
    || 'dUtUOXNianBVWlM1amRYSnlaVzUwTEdjOVRHNG9kQ3huS1NrN2RtRnlJRk05Ymk1blpYUkVaWEpwZG1Wa1UzUmhkR1ZHY205dFVISnZjSE1zYXoxMGVYQmxi'
    || 'MllnVXowOUltWjFibU4wYVc5dUlueDhkSGx3Wlc5bUlITXVaMlYwVTI1aGNITm9iM1JDWldadmNtVlZjR1JoZEdVOVBTSm1kVzVqZEdsdmJpSTdhM3g4ZEhs'
    || 'd1pXOW1JSE11VlU1VFFVWkZYMk52YlhCdmJtVnVkRmRwYkd4U1pXTmxhWFpsVUhKdmNITWhQU0ptZFc1amRHbHZiaUltSm5SNWNHVnZaaUJ6TG1OdmJYQnZi'
    || 'bVZ1ZEZkcGJHeFNaV05sYVhabFVISnZjSE1oUFNKbWRXNWpkR2x2YmlKOGZDaGhJVDA5Y254OFppRTlQV2NwSmladFlTaDBMSE1zY2l4bktTeEhkRDBoTVR0'
    || 'MllYSWdkejEwTG0xbGJXOXBlbVZrVTNSaGRHVTdjeTV6ZEdGMFpUMTNMSEJzS0hRc2NpeHpMR3dwTEdZOWRDNXRaVzF2YVhwbFpGTjBZWFJsTEdFaFBUMXlm'
    || 'SHgzSVQwOVpueDhRV1V1WTNWeWNtVnVkSHg4UjNRL0tIUjVjR1Z2WmlCVFBUMGlablZ1WTNScGIyNGlKaVlvWjI4b2RDeHVMRk1zY2lrc1pqMTBMbTFsYlc5'
    || 'cGVtVmtVM1JoZEdVcExDaGhQVWQwZkh4d1lTaDBMRzRzWVN4eUxIY3NaaXhuS1NrL0tHdDhmSFI1Y0dWdlppQnpMbFZPVTBGR1JWOWpiMjF3YjI1bGJuUlhh'
    || 'V3hzVFc5MWJuUWhQU0ptZFc1amRHbHZiaUltSm5SNWNHVnZaaUJ6TG1OdmJYQnZibVZ1ZEZkcGJHeE5iM1Z1ZENFOUltWjFibU4wYVc5dUlueDhLSFI1Y0dW'
    || 'dlppQnpMbU52YlhCdmJtVnVkRmRwYkd4TmIzVnVkRDA5SW1aMWJtTjBhVzl1SWlZbWN5NWpiMjF3YjI1bGJuUlhhV3hzVFc5MWJuUW9LU3gwZVhCbGIyWWdj'
    || 'eTVWVGxOQlJrVmZZMjl0Y0c5dVpXNTBWMmxzYkUxdmRXNTBQVDBpWm5WdVkzUnBiMjRpSmlaekxsVk9VMEZHUlY5amIyMXdiMjVsYm5SWGFXeHNUVzkxYm5R'
    || 'b0tTa3NkSGx3Wlc5bUlITXVZMjl0Y0c5dVpXNTBSR2xrVFc5MWJuUTlQU0ptZFc1amRHbHZiaUltSmloMExtWnNZV2R6ZkQwME1UazBNekE0S1NrNktIUjVj'
    || 'R1Z2WmlCekxtTnZiWEJ2Ym1WdWRFUnBaRTF2ZFc1MFBUMGlablZ1WTNScGIyNGlKaVlvZEM1bWJHRm5jM3c5TkRFNU5ETXdPQ2tzZEM1dFpXMXZhWHBsWkZC'
    || 'eWIzQnpQWElzZEM1dFpXMXZhWHBsWkZOMFlYUmxQV1lwTEhNdWNISnZjSE05Y2l4ekxuTjBZWFJsUFdZc2N5NWpiMjUwWlhoMFBXY3NjajFoS1Rvb2RIbHda'
    || 'VzltSUhNdVkyOXRjRzl1Wlc1MFJHbGtUVzkxYm5ROVBTSm1kVzVqZEdsdmJpSW1KaWgwTG1ac1lXZHpmRDAwTVRrME16QTRLU3h5UFNFeEtYMWxiSE5sZTNN'
    || 'OWRDNXpkR0YwWlU1dlpHVXNWblVvWlN4MEtTeGhQWFF1YldWdGIybDZaV1JRY205d2N5eG5QWFF1ZEhsd1pUMDlQWFF1Wld4bGJXVnVkRlI1Y0dVL1lUcG1k'
    || 'Q2gwTG5SNWNHVXNZU2tzY3k1d2NtOXdjejFuTEdzOWRDNXdaVzVrYVc1blVISnZjSE1zZHoxekxtTnZiblJsZUhRc1pqMXVMbU52Ym5SbGVIUlVlWEJsTEhS'
    || 'NWNHVnZaaUJtUFQwaWIySnFaV04wSWlZbVppRTlQVzUxYkd3L1pqMXVkQ2htS1Rvb1pqMVZaU2h1S1Q5c2JqcFVaUzVqZFhKeVpXNTBMR1k5VEc0b2RDeG1L'
    || 'U2s3ZG1GeUlFODliaTVuWlhSRVpYSnBkbVZrVTNSaGRHVkdjbTl0VUhKdmNITTdLRk05ZEhsd1pXOW1JRTg5UFNKbWRXNWpkR2x2YmlKOGZIUjVjR1Z2WmlC'
    || 'ekxtZGxkRk51WVhCemFHOTBRbVZtYjNKbFZYQmtZWFJsUFQwaVpuVnVZM1JwYjI0aUtYeDhkSGx3Wlc5bUlITXVWVTVUUVVaRlgyTnZiWEJ2Ym1WdWRGZHBi'
    || 'R3hTWldObGFYWmxVSEp2Y0hNaFBTSm1kVzVqZEdsdmJpSW1KblI1Y0dWdlppQnpMbU52YlhCdmJtVnVkRmRwYkd4U1pXTmxhWFpsVUhKdmNITWhQU0ptZFc1'
    || 'amRHbHZiaUo4ZkNoaElUMDlhM3g4ZHlFOVBXWXBKaVp0WVNoMExITXNjaXhtS1N4SGREMGhNU3gzUFhRdWJXVnRiMmw2WldSVGRHRjBaU3h6TG5OMFlYUmxQ'
    || 'WGNzY0d3b2RDeHlMSE1zYkNrN2RtRnlJRWs5ZEM1dFpXMXZhWHBsWkZOMFlYUmxPMkVoUFQxcmZIeDNJVDA5U1h4OFFXVXVZM1Z5Y21WdWRIeDhSM1EvS0hS'
    || 'NWNHVnZaaUJQUFQwaVpuVnVZM1JwYjI0aUppWW9aMjhvZEN4dUxFOHNjaWtzU1QxMExtMWxiVzlwZW1Wa1UzUmhkR1VwTENoblBVZDBmSHh3WVNoMExHNHNa'
    || 'eXh5TEhjc1NTeG1LWHg4SVRFcFB5aFRmSHgwZVhCbGIyWWdjeTVWVGxOQlJrVmZZMjl0Y0c5dVpXNTBWMmxzYkZWd1pHRjBaU0U5SW1aMWJtTjBhVzl1SWlZ'
    || 'bWRIbHdaVzltSUhNdVkyOXRjRzl1Wlc1MFYybHNiRlZ3WkdGMFpTRTlJbVoxYm1OMGFXOXVJbng4S0hSNWNHVnZaaUJ6TG1OdmJYQnZibVZ1ZEZkcGJHeFZj'
    || 'R1JoZEdVOVBTSm1kVzVqZEdsdmJpSW1Kbk11WTI5dGNHOXVaVzUwVjJsc2JGVndaR0YwWlNoeUxFa3NaaWtzZEhsd1pXOW1JSE11VlU1VFFVWkZYMk52YlhC'
    || 'dmJtVnVkRmRwYkd4VmNHUmhkR1U5UFNKbWRXNWpkR2x2YmlJbUpuTXVWVTVUUVVaRlgyTnZiWEJ2Ym1WdWRGZHBiR3hWY0dSaGRHVW9jaXhKTEdZcEtTeDBl'
    || 'WEJsYjJZZ2N5NWpiMjF3YjI1bGJuUkVhV1JWY0dSaGRHVTlQU0ptZFc1amRHbHZiaUltSmloMExtWnNZV2R6ZkQwMEtTeDBlWEJsYjJZZ2N5NW5aWFJUYm1G'
    || 'd2MyaHZkRUpsWm05eVpWVndaR0YwWlQwOUltWjFibU4wYVc5dUlpWW1LSFF1Wm14aFozTjhQVEV3TWpRcEtUb29kSGx3Wlc5bUlITXVZMjl0Y0c5dVpXNTBS'
    || 'R2xrVlhCa1lYUmxJVDBpWm5WdVkzUnBiMjRpZkh4aFBUMDlaUzV0WlcxdmFYcGxaRkJ5YjNCekppWjNQVDA5WlM1dFpXMXZhWHBsWkZOMFlYUmxmSHdvZEM1'
    || 'bWJHRm5jM3c5TkNrc2RIbHdaVzltSUhNdVoyVjBVMjVoY0hOb2IzUkNaV1p2Y21WVmNHUmhkR1VoUFNKbWRXNWpkR2x2YmlKOGZHRTlQVDFsTG0xbGJXOXBl'
    || 'bVZrVUhKdmNITW1KbmM5UFQxbExtMWxiVzlwZW1Wa1UzUmhkR1Y4ZkNoMExtWnNZV2R6ZkQweE1ESTBLU3gwTG0xbGJXOXBlbVZrVUhKdmNITTljaXgwTG0x'
    || 'bGJXOXBlbVZrVTNSaGRHVTlTU2tzY3k1d2NtOXdjejF5TEhNdWMzUmhkR1U5U1N4ekxtTnZiblJsZUhROVppeHlQV2NwT2loMGVYQmxiMllnY3k1amIyMXdi'
    || 'MjVsYm5SRWFXUlZjR1JoZEdVaFBTSm1kVzVqZEdsdmJpSjhmR0U5UFQxbExtMWxiVzlwZW1Wa1VISnZjSE1tSm5jOVBUMWxMbTFsYlc5cGVtVmtVM1JoZEdW'
    || 'OGZDaDBMbVpzWVdkemZEMDBLU3gwZVhCbGIyWWdjeTVuWlhSVGJtRndjMmh2ZEVKbFptOXlaVlZ3WkdGMFpTRTlJbVoxYm1OMGFXOXVJbng4WVQwOVBXVXVi'
    || 'V1Z0YjJsNlpXUlFjbTl3Y3lZbWR6MDlQV1V1YldWdGIybDZaV1JUZEdGMFpYeDhLSFF1Wm14aFozTjhQVEV3TWpRcExISTlJVEVwZlhKbGRIVnliaUJUYnlo'
    || 'bExIUXNiaXh5TEdrc2JDbDlablZ1WTNScGIyNGdVMjhvWlN4MExHNHNjaXhzTEdrcGUwNWhLR1VzZENrN2RtRnlJSE05S0hRdVpteGhaM01tTVRJNEtTRTlQ'
    || 'VEE3YVdZb0lYSW1KaUZ6S1hKbGRIVnliaUJzSmlaUGRTaDBMRzRzSVRFcExFOTBLR1VzZEN4cEtUdHlQWFF1YzNSaGRHVk9iMlJsTEV4bUxtTjFjbkpsYm5R'
    || 'OWREdDJZWElnWVQxekppWjBlWEJsYjJZZ2JpNW5aWFJFWlhKcGRtVmtVM1JoZEdWR2NtOXRSWEp5YjNJaFBTSm1kVzVqZEdsdmJpSS9iblZzYkRweUxuSmxi'
    || 'bVJsY2lncE8zSmxkSFZ5YmlCMExtWnNZV2R6ZkQweExHVWhQVDF1ZFd4c0ppWnpQeWgwTG1Ob2FXeGtQVWx1S0hRc1pTNWphR2xzWkN4dWRXeHNMR2twTEhR'
    || 'dVkyaHBiR1E5U1c0b2RDeHVkV3hzTEdFc2FTa3BPazFsS0dVc2RDeGhMR2twTEhRdWJXVnRiMmw2WldSVGRHRjBaVDF5TG5OMFlYUmxMR3dtSms5MUtIUXNi'
    || 'aXdoTUNrc2RDNWphR2xzWkgxbWRXNWpkR2x2YmlCRFlTaGxLWHQyWVhJZ2REMWxMbk4wWVhSbFRtOWtaVHQwTG5CbGJtUnBibWREYjI1MFpYaDBQMUoxS0dV'
    || 'c2RDNXdaVzVrYVc1blEyOXVkR1Y0ZEN4MExuQmxibVJwYm1kRGIyNTBaWGgwSVQwOWRDNWpiMjUwWlhoMEtUcDBMbU52Ym5SbGVIUW1KbEoxS0dVc2RDNWpi'
    || 'MjUwWlhoMExDRXhLU3hzYnlobExIUXVZMjl1ZEdGcGJtVnlTVzVtYnlsOVpuVnVZM1JwYjI0Z1ZHRW9aU3gwTEc0c2NpeHNLWHR5WlhSMWNtNGdUVzRvS1N4'
    || 'eGFTaHNLU3gwTG1ac1lXZHpmRDB5TlRZc1RXVW9aU3gwTEc0c2Npa3NkQzVqYUdsc1pIMTJZWElnUlc4OWUyUmxhSGxrY21GMFpXUTZiblZzYkN4MGNtVmxR'
    || 'Mjl1ZEdWNGREcHVkV3hzTEhKbGRISjVUR0Z1WlRvd2ZUdG1kVzVqZEdsdmJpQnJieWhsS1h0eVpYUjFjbTU3WW1GelpVeGhibVZ6T21Vc1kyRmphR1ZRYjI5'
    || 'c09tNTFiR3dzZEhKaGJuTnBkR2x2Ym5NNmJuVnNiSDE5Wm5WdVkzUnBiMjRnVW1Fb1pTeDBMRzRwZTNaaGNpQnlQWFF1Y0dWdVpHbHVaMUJ5YjNCekxHdzlZ'
    || 'V1V1WTNWeWNtVnVkQ3hwUFNFeExITTlLSFF1Wm14aFozTW1NVEk0S1NFOVBUQXNZVHRwWmlnb1lUMXpLWHg4S0dFOVpTRTlQVzUxYkd3bUptVXViV1Z0YjJs'
    || 'NlpXUlRkR0YwWlQwOVBXNTFiR3cvSVRFNktHd21NaWtoUFQwd0tTeGhQeWhwUFNFd0xIUXVabXhoWjNNbVBTMHhNamtwT2lobFBUMDliblZzYkh4OFpTNXRa'
    || 'VzF2YVhwbFpGTjBZWFJsSVQwOWJuVnNiQ2ttSmloc2ZEMHhLU3h5WlNoaFpTeHNKakVwTEdVOVBUMXVkV3hzS1hKbGRIVnliaUJhYVNoMEtTeGxQWFF1YldW'
    || 'dGIybDZaV1JUZEdGMFpTeGxJVDA5Ym5Wc2JDWW1LR1U5WlM1a1pXaDVaSEpoZEdWa0xHVWhQVDF1ZFd4c0tUOG9LSFF1Ylc5a1pTWXhLVDA5UFRBL2RDNXNZ'
    || 'VzVsY3oweE9tVXVaR0YwWVQwOVBTSWtJU0kvZEM1c1lXNWxjejA0T25RdWJHRnVaWE05TVRBM016YzBNVGd5TkN4dWRXeHNLVG9vY3oxeUxtTm9hV3hrY21W'
    || 'dUxHVTljaTVtWVd4c1ltRmpheXhwUHloeVBYUXViVzlrWlN4cFBYUXVZMmhwYkdRc2N6MTdiVzlrWlRvaWFHbGtaR1Z1SWl4amFHbHNaSEpsYmpwemZTd29j'
    || 'aVl4S1QwOVBUQW1KbWtoUFQxdWRXeHNQeWhwTG1Ob2FXeGtUR0Z1WlhNOU1DeHBMbkJsYm1ScGJtZFFjbTl3Y3oxektUcHBQVWxzS0hNc2Npd3dMRzUxYkd3'
    || 'cExHVTliVzRvWlN4eUxHNHNiblZzYkNrc2FTNXlaWFIxY200OWRDeGxMbkpsZEhWeWJqMTBMR2t1YzJsaWJHbHVaejFsTEhRdVkyaHBiR1E5YVN4MExtTm9h'
    || 'V3hrTG0xbGJXOXBlbVZrVTNSaGRHVTlhMjhvYmlrc2RDNXRaVzF2YVhwbFpGTjBZWFJsUFVWdkxHVXBPazV2S0hRc2N5a3BPMmxtS0d3OVpTNXRaVzF2YVhw'
    || 'bFpGTjBZWFJsTEd3aFBUMXVkV3hzSmlZb1lUMXNMbVJsYUhsa2NtRjBaV1FzWVNFOVBXNTFiR3dwS1hKbGRIVnliaUJQWmlobExIUXNjeXh5TEdFc2JDeHVL'
    || 'VHRwWmlocEtYdHBQWEl1Wm1Gc2JHSmhZMnNzY3oxMExtMXZaR1VzYkQxbExtTm9hV3hrTEdFOWJDNXphV0pzYVc1bk8zWmhjaUJtUFh0dGIyUmxPaUpvYVdS'
    || 'a1pXNGlMR05vYVd4a2NtVnVPbkl1WTJocGJHUnlaVzU5TzNKbGRIVnliaWh6SmpFcFBUMDlNQ1ltZEM1amFHbHNaQ0U5UFd3L0tISTlkQzVqYUdsc1pDeHlM'
    || 'bU5vYVd4a1RHRnVaWE05TUN4eUxuQmxibVJwYm1kUWNtOXdjejFtTEhRdVpHVnNaWFJwYjI1elBXNTFiR3dwT2loeVBXSjBLR3dzWmlrc2NpNXpkV0owY21W'
    || 'bFJteGhaM005YkM1emRXSjBjbVZsUm14aFozTW1NVFEyT0RBd05qUXBMR0VoUFQxdWRXeHNQMms5WW5Rb1lTeHBLVG9vYVQxdGJpaHBMSE1zYml4dWRXeHNL'
    || 'U3hwTG1ac1lXZHpmRDB5S1N4cExuSmxkSFZ5YmoxMExISXVjbVYwZFhKdVBYUXNjaTV6YVdKc2FXNW5QV2tzZEM1amFHbHNaRDF5TEhJOWFTeHBQWFF1WTJo'
    || 'cGJHUXNjejFsTG1Ob2FXeGtMbTFsYlc5cGVtVmtVM1JoZEdVc2N6MXpQVDA5Ym5Wc2JEOXJieWh1S1RwN1ltRnpaVXhoYm1Wek9uTXVZbUZ6WlV4aGJtVnpm'
    || 'RzRzWTJGamFHVlFiMjlzT201MWJHd3NkSEpoYm5OcGRHbHZibk02Y3k1MGNtRnVjMmwwYVc5dWMzMHNhUzV0WlcxdmFYcGxaRk4wWVhSbFBYTXNhUzVqYUds'
    || 'c1pFeGhibVZ6UFdVdVkyaHBiR1JNWVc1bGN5WitiaXgwTG0xbGJXOXBlbVZrVTNSaGRHVTlSVzhzY24xeVpYUjFjbTRnYVQxbExtTm9hV3hrTEdVOWFTNXph'
    || 'V0pzYVc1bkxISTlZblFvYVN4N2JXOWtaVG9pZG1semFXSnNaU0lzWTJocGJHUnlaVzQ2Y2k1amFHbHNaSEpsYm4wcExDaDBMbTF2WkdVbU1TazlQVDB3SmlZ'
    || 'b2NpNXNZVzVsY3oxdUtTeHlMbkpsZEhWeWJqMTBMSEl1YzJsaWJHbHVaejF1ZFd4c0xHVWhQVDF1ZFd4c0ppWW9iajEwTG1SbGJHVjBhVzl1Y3l4dVBUMDli'
    || 'blZzYkQ4b2RDNWtaV3hsZEdsdmJuTTlXMlZkTEhRdVpteGhaM044UFRFMktUcHVMbkIxYzJnb1pTa3BMSFF1WTJocGJHUTljaXgwTG0xbGJXOXBlbVZrVTNS'
    || 'aGRHVTliblZzYkN4eWZXWjFibU4wYVc5dUlFNXZLR1VzZENsN2NtVjBkWEp1SUhROVNXd29lMjF2WkdVNkluWnBjMmxpYkdVaUxHTm9hV3hrY21WdU9uUjlM'
    || 'R1V1Ylc5a1pTd3dMRzUxYkd3cExIUXVjbVYwZFhKdVBXVXNaUzVqYUdsc1pEMTBmV1oxYm1OMGFXOXVJRjlzS0dVc2RDeHVMSElwZTNKbGRIVnliaUJ5SVQw'
    || 'OWJuVnNiQ1ltY1drb2Npa3NTVzRvZEN4bExtTm9hV3hrTEc1MWJHd3NiaWtzWlQxT2J5aDBMSFF1Y0dWdVpHbHVaMUJ5YjNCekxtTm9hV3hrY21WdUtTeGxM'
    || 'bVpzWVdkemZEMHlMSFF1YldWdGIybDZaV1JUZEdGMFpUMXVkV3hzTEdWOVpuVnVZM1JwYjI0Z1QyWW9aU3gwTEc0c2NpeHNMR2tzY3lsN2FXWW9iaWx5WlhS'
    || 'MWNtNGdkQzVtYkdGbmN5WXlOVFkvS0hRdVpteGhaM01tUFMweU5UY3NjajE0YnloRmNuSnZjaWhqS0RReU1pa3BLU3hmYkNobExIUXNjeXh5S1NrNmRDNXRa'
    || 'VzF2YVhwbFpGTjBZWFJsSVQwOWJuVnNiRDhvZEM1amFHbHNaRDFsTG1Ob2FXeGtMSFF1Wm14aFozTjhQVEV5T0N4dWRXeHNLVG9vYVQxeUxtWmhiR3hpWVdO'
    || 'ckxHdzlkQzV0YjJSbExISTlTV3dvZTIxdlpHVTZJblpwYzJsaWJHVWlMR05vYVd4a2NtVnVPbkl1WTJocGJHUnlaVzU5TEd3c01DeHVkV3hzS1N4cFBXMXVL'
    || 'R2tzYkN4ekxHNTFiR3dwTEdrdVpteGhaM044UFRJc2NpNXlaWFIxY200OWRDeHBMbkpsZEhWeWJqMTBMSEl1YzJsaWJHbHVaejFwTEhRdVkyaHBiR1E5Y2l3'
    || 'b2RDNXRiMlJsSmpFcElUMDlNQ1ltU1c0b2RDeGxMbU5vYVd4a0xHNTFiR3dzY3lrc2RDNWphR2xzWkM1dFpXMXZhWHBsWkZOMFlYUmxQV3R2S0hNcExIUXVi'
    || 'V1Z0YjJsNlpXUlRkR0YwWlQxRmJ5eHBLVHRwWmlnb2RDNXRiMlJsSmpFcFBUMDlNQ2x5WlhSMWNtNGdYMndvWlN4MExITXNiblZzYkNrN2FXWW9iQzVrWVhS'
    || 'aFBUMDlJaVFoSWlsN2FXWW9jajFzTG01bGVIUlRhV0pzYVc1bkppWnNMbTVsZUhSVGFXSnNhVzVuTG1SaGRHRnpaWFFzY2lsMllYSWdZVDF5TG1SbmMzUTdj'
    || 'bVYwZFhKdUlISTlZU3hwUFVWeWNtOXlLR01vTkRFNUtTa3NjajE0YnlocExISXNkbTlwWkNBd0tTeGZiQ2hsTEhRc2N5eHlLWDFwWmloaFBTaHpKbVV1WTJo'
    || 'cGJHUk1ZVzVsY3lraFBUMHdMQ1JsZkh4aEtYdHBaaWh5UFZObExISWhQVDF1ZFd4c0tYdHpkMmwwWTJnb2N5WXRjeWw3WTJGelpTQTBPbXc5TWp0aWNtVmhh'
    || 'enRqWVhObElERTJPbXc5T0R0aWNtVmhhenRqWVhObElEWTBPbU5oYzJVZ01USTRPbU5oYzJVZ01qVTJPbU5oYzJVZ05URXlPbU5oYzJVZ01UQXlORHBqWVhO'
    || 'bElESXdORGc2WTJGelpTQTBNRGsyT21OaGMyVWdPREU1TWpwallYTmxJREUyTXpnME9tTmhjMlVnTXpJM05qZzZZMkZ6WlNBMk5UVXpOanBqWVhObElERXpN'
    || 'VEEzTWpwallYTmxJREkyTWpFME5EcGpZWE5sSURVeU5ESTRPRHBqWVhObElERXdORGcxTnpZNlkyRnpaU0F5TURrM01UVXlPbU5oYzJVZ05ERTVORE13TkRw'
    || 'allYTmxJRGd6T0RnMk1EZzZZMkZ6WlNBeE5qYzNOekl4TmpwallYTmxJRE16TlRVME5ETXlPbU5oYzJVZ05qY3hNRGc0TmpRNmJEMHpNanRpY21WaGF6dGpZ'
    || 'WE5sSURVek5qZzNNRGt4TWpwc1BUSTJPRFF6TlRRMU5qdGljbVZoYXp0a1pXWmhkV3gwT213OU1IMXNQU2hzSmloeUxuTjFjM0JsYm1SbFpFeGhibVZ6ZkhN'
    || 'cEtTRTlQVEEvTURwc0xHd2hQVDB3Smlac0lUMDlhUzV5WlhSeWVVeGhibVVtSmlocExuSmxkSEo1VEdGdVpUMXNMRkowS0dVc2JDa3NiWFFvY2l4bExHd3NM'
    || 'VEVwS1gxeVpYUjFjbTRnU0c4b0tTeHlQWGh2S0VWeWNtOXlLR01vTkRJeEtTa3BMRjlzS0dVc2RDeHpMSElwZlhKbGRIVnliaUJzTG1SaGRHRTlQVDBpSkQ4'
    || 'aVB5aDBMbVpzWVdkemZEMHhNamdzZEM1amFHbHNaRDFsTG1Ob2FXeGtMSFE5UW1ZdVltbHVaQ2h1ZFd4c0xHVXBMR3d1WDNKbFlXTjBVbVYwY25rOWRDeHVk'
    || 'V3hzS1Rvb1pUMXBMblJ5WldWRGIyNTBaWGgwTEZwbFBWWjBLR3d1Ym1WNGRGTnBZbXhwYm1jcExGaGxQWFFzYzJVOUlUQXNaSFE5Ym5Wc2JDeGxJVDA5Ym5W'
    || 'c2JDWW1LR1YwVzNSMEt5dGRQVU4wTEdWMFczUjBLeXRkUFZSMExHVjBXM1IwS3l0ZFBXOXVMRU4wUFdVdWFXUXNWSFE5WlM1dmRtVnlabXh2ZHl4dmJqMTBL'
    || 'U3gwUFU1dktIUXNjaTVqYUdsc1pISmxiaWtzZEM1bWJHRm5jM3c5TkRBNU5peDBLWDFtZFc1amRHbHZiaUJNWVNobExIUXNiaWw3WlM1c1lXNWxjM3c5ZER0'
    || 'MllYSWdjajFsTG1Gc2RHVnlibUYwWlR0eUlUMDliblZzYkNZbUtISXViR0Z1WlhOOFBYUXBMSFJ2S0dVdWNtVjBkWEp1TEhRc2JpbDlablZ1WTNScGIyNGdh'
    || 'bThvWlN4MExHNHNjaXhzS1h0MllYSWdhVDFsTG0xbGJXOXBlbVZrVTNSaGRHVTdhVDA5UFc1MWJHdy9aUzV0WlcxdmFYcGxaRk4wWVhSbFBYdHBjMEpoWTJ0'
    || 'M1lYSmtjenAwTEhKbGJtUmxjbWx1WnpwdWRXeHNMSEpsYm1SbGNtbHVaMU4wWVhKMFZHbHRaVG93TEd4aGMzUTZjaXgwWVdsc09tNHNkR0ZwYkUxdlpHVTZi'
    || 'SDA2S0drdWFYTkNZV05yZDJGeVpITTlkQ3hwTG5KbGJtUmxjbWx1WnoxdWRXeHNMR2t1Y21WdVpHVnlhVzVuVTNSaGNuUlVhVzFsUFRBc2FTNXNZWE4wUFhJ'
    || 'c2FTNTBZV2xzUFc0c2FTNTBZV2xzVFc5a1pUMXNLWDFtZFc1amRHbHZiaUJQWVNobExIUXNiaWw3ZG1GeUlISTlkQzV3Wlc1a2FXNW5VSEp2Y0hNc2JEMXlM'
    || 'bkpsZG1WaGJFOXlaR1Z5TEdrOWNpNTBZV2xzTzJsbUtFMWxLR1VzZEN4eUxtTm9hV3hrY21WdUxHNHBMSEk5WVdVdVkzVnljbVZ1ZEN3b2NpWXlLU0U5UFRB'
    || 'cGNqMXlKakY4TWl4MExtWnNZV2R6ZkQweE1qZzdaV3h6Wlh0cFppaGxJVDA5Ym5Wc2JDWW1LR1V1Wm14aFozTW1NVEk0S1NFOVBUQXBaVHBtYjNJb1pUMTBM'
    || 'bU5vYVd4a08yVWhQVDF1ZFd4c095bDdhV1lvWlM1MFlXYzlQVDB4TXlsbExtMWxiVzlwZW1Wa1UzUmhkR1VoUFQxdWRXeHNKaVpNWVNobExHNHNkQ2s3Wld4'
    || 'elpTQnBaaWhsTG5SaFp6MDlQVEU1S1V4aEtHVXNiaXgwS1R0bGJITmxJR2xtS0dVdVkyaHBiR1FoUFQxdWRXeHNLWHRsTG1Ob2FXeGtMbkpsZEhWeWJqMWxM'
    || 'R1U5WlM1amFHbHNaRHRqYjI1MGFXNTFaWDFwWmlobFBUMDlkQ2xpY21WaGF5QmxPMlp2Y2lnN1pTNXphV0pzYVc1blBUMDliblZzYkRzcGUybG1LR1V1Y21W'
    || 'MGRYSnVQVDA5Ym5Wc2JIeDhaUzV5WlhSMWNtNDlQVDEwS1dKeVpXRnJJR1U3WlQxbExuSmxkSFZ5Ym4xbExuTnBZbXhwYm1jdWNtVjBkWEp1UFdVdWNtVjBk'
    || 'WEp1TEdVOVpTNXphV0pzYVc1bmZYSW1QVEY5YVdZb2NtVW9ZV1VzY2lrc0tIUXViVzlrWlNZeEtUMDlQVEFwZEM1dFpXMXZhWHBsWkZOMFlYUmxQVzUxYkd3'
    || 'N1pXeHpaU0J6ZDJsMFkyZ29iQ2w3WTJGelpTSm1iM0ozWVhKa2N5STZabTl5S0c0OWRDNWphR2xzWkN4c1BXNTFiR3c3YmlFOVBXNTFiR3c3S1dVOWJpNWhi'
    || 'SFJsY201aGRHVXNaU0U5UFc1MWJHd21KbWhzS0dVcFBUMDliblZzYkNZbUtHdzliaWtzYmoxdUxuTnBZbXhwYm1jN2JqMXNMRzQ5UFQxdWRXeHNQeWhzUFhR'
    || 'dVkyaHBiR1FzZEM1amFHbHNaRDF1ZFd4c0tUb29iRDF1TG5OcFlteHBibWNzYmk1emFXSnNhVzVuUFc1MWJHd3BMR3B2S0hRc0lURXNiQ3h1TEdrcE8ySnla'
    || 'V0ZyTzJOaGMyVWlZbUZqYTNkaGNtUnpJanBtYjNJb2JqMXVkV3hzTEd3OWRDNWphR2xzWkN4MExtTm9hV3hrUFc1MWJHdzdiQ0U5UFc1MWJHdzdLWHRwWmlo'
    || 'bFBXd3VZV3gwWlhKdVlYUmxMR1VoUFQxdWRXeHNKaVpvYkNobEtUMDlQVzUxYkd3cGUzUXVZMmhwYkdROWJEdGljbVZoYTMxbFBXd3VjMmxpYkdsdVp5eHNM'
    || 'bk5wWW14cGJtYzliaXh1UFd3c2JEMWxmV3B2S0hRc0lUQXNiaXh1ZFd4c0xHa3BPMkp5WldGck8yTmhjMlVpZEc5blpYUm9aWElpT21wdktIUXNJVEVzYm5W'
    || 'c2JDeHVkV3hzTEhadmFXUWdNQ2s3WW5KbFlXczdaR1ZtWVhWc2REcDBMbTFsYlc5cGVtVmtVM1JoZEdVOWJuVnNiSDF5WlhSMWNtNGdkQzVqYUdsc1pIMW1k'
    || 'VzVqZEdsdmJpQlRiQ2hsTEhRcGV5aDBMbTF2WkdVbU1TazlQVDB3SmlabElUMDliblZzYkNZbUtHVXVZV3gwWlhKdVlYUmxQVzUxYkd3c2RDNWhiSFJsY201'
    || 'aGRHVTliblZzYkN4MExtWnNZV2R6ZkQweUtYMW1kVzVqZEdsdmJpQlBkQ2hsTEhRc2JpbDdhV1lvWlNFOVBXNTFiR3dtSmloMExtUmxjR1Z1WkdWdVkybGxj'
    || 'ejFsTG1SbGNHVnVaR1Z1WTJsbGN5a3NaRzU4UFhRdWJHRnVaWE1zS0c0bWRDNWphR2xzWkV4aGJtVnpLVDA5UFRBcGNtVjBkWEp1SUc1MWJHdzdhV1lvWlNF'
    || 'OVBXNTFiR3dtSm5RdVkyaHBiR1FoUFQxbExtTm9hV3hrS1hSb2NtOTNJRVZ5Y205eUtHTW9NVFV6S1NrN2FXWW9kQzVqYUdsc1pDRTlQVzUxYkd3cGUyWnZj'
    || 'aWhsUFhRdVkyaHBiR1FzYmoxaWRDaGxMR1V1Y0dWdVpHbHVaMUJ5YjNCektTeDBMbU5vYVd4a1BXNHNiaTV5WlhSMWNtNDlkRHRsTG5OcFlteHBibWNoUFQx'
    || 'dWRXeHNPeWxsUFdVdWMybGliR2x1Wnl4dVBXNHVjMmxpYkdsdVp6MWlkQ2hsTEdVdWNHVnVaR2x1WjFCeWIzQnpLU3h1TG5KbGRIVnliajEwTzI0dWMybGli'
    || 'R2x1WnoxdWRXeHNmWEpsZEhWeWJpQjBMbU5vYVd4a2ZXWjFibU4wYVc5dUlGQm1LR1VzZEN4dUtYdHpkMmwwWTJnb2RDNTBZV2NwZTJOaGMyVWdNenBEWVNo'
    || 'MEtTeE5iaWdwTzJKeVpXRnJPMk5oYzJVZ05UcFJkU2gwS1R0aWNtVmhhenRqWVhObElERTZWV1VvZEM1MGVYQmxLU1ltYkd3b2RDazdZbkpsWVdzN1kyRnpa'
    || 'U0EwT214dktIUXNkQzV6ZEdGMFpVNXZaR1V1WTI5dWRHRnBibVZ5U1c1bWJ5azdZbkpsWVdzN1kyRnpaU0F4TURwMllYSWdjajEwTG5SNWNHVXVYMk52Ym5S'
    || 'bGVIUXNiRDEwTG0xbGJXOXBlbVZrVUhKdmNITXVkbUZzZFdVN2NtVW9ZMndzY2k1ZlkzVnljbVZ1ZEZaaGJIVmxLU3h5TGw5amRYSnlaVzUwVm1Gc2RXVTli'
    || 'RHRpY21WaGF6dGpZWE5sSURFek9tbG1LSEk5ZEM1dFpXMXZhWHBsWkZOMFlYUmxMSEloUFQxdWRXeHNLWEpsZEhWeWJpQnlMbVJsYUhsa2NtRjBaV1FoUFQx'
    || 'dWRXeHNQeWh5WlNoaFpTeGhaUzVqZFhKeVpXNTBKakVwTEhRdVpteGhaM044UFRFeU9DeHVkV3hzS1Rvb2JpWjBMbU5vYVd4a0xtTm9hV3hrVEdGdVpYTXBJ'
    || 'VDA5TUQ5U1lTaGxMSFFzYmlrNktISmxLR0ZsTEdGbExtTjFjbkpsYm5RbU1Ta3NaVDFQZENobExIUXNiaWtzWlNFOVBXNTFiR3cvWlM1emFXSnNhVzVuT201'
    || 'MWJHd3BPM0psS0dGbExHRmxMbU4xY25KbGJuUW1NU2s3WW5KbFlXczdZMkZ6WlNBeE9UcHBaaWh5UFNodUpuUXVZMmhwYkdSTVlXNWxjeWtoUFQwd0xDaGxM'
    || 'bVpzWVdkekpqRXlPQ2toUFQwd0tYdHBaaWh5S1hKbGRIVnliaUJQWVNobExIUXNiaWs3ZEM1bWJHRm5jM3c5TVRJNGZXbG1LR3c5ZEM1dFpXMXZhWHBsWkZO'
    || 'MFlYUmxMR3doUFQxdWRXeHNKaVlvYkM1eVpXNWtaWEpwYm1jOWJuVnNiQ3hzTG5SaGFXdzliblZzYkN4c0xteGhjM1JGWm1abFkzUTliblZzYkNrc2NtVW9Z'
    || 'V1VzWVdVdVkzVnljbVZ1ZENrc2NpbGljbVZoYXp0eVpYUjFjbTRnYm5Wc2JEdGpZWE5sSURJeU9tTmhjMlVnTWpNNmNtVjBkWEp1SUhRdWJHRnVaWE05TUN4'
    || 'cllTaGxMSFFzYmlsOWNtVjBkWEp1SUU5MEtHVXNkQ3h1S1gxMllYSWdVR0VzUTI4c1RXRXNTV0U3VUdFOVpuVnVZM1JwYjI0b1pTeDBLWHRtYjNJb2RtRnlJ'
    || 'RzQ5ZEM1amFHbHNaRHR1SVQwOWJuVnNiRHNwZTJsbUtHNHVkR0ZuUFQwOU5YeDhiaTUwWVdjOVBUMDJLV1V1WVhCd1pXNWtRMmhwYkdRb2JpNXpkR0YwWlU1'
    || 'dlpHVXBPMlZzYzJVZ2FXWW9iaTUwWVdjaFBUMDBKaVp1TG1Ob2FXeGtJVDA5Ym5Wc2JDbDdiaTVqYUdsc1pDNXlaWFIxY200OWJpeHVQVzR1WTJocGJHUTdZ'
    || 'Mjl1ZEdsdWRXVjlhV1lvYmowOVBYUXBZbkpsWVdzN1ptOXlLRHR1TG5OcFlteHBibWM5UFQxdWRXeHNPeWw3YVdZb2JpNXlaWFIxY200OVBUMXVkV3hzZkh4'
    || 'dUxuSmxkSFZ5YmowOVBYUXBjbVYwZFhKdU8yNDliaTV5WlhSMWNtNTliaTV6YVdKc2FXNW5MbkpsZEhWeWJqMXVMbkpsZEhWeWJpeHVQVzR1YzJsaWJHbHVa'
    || 'MzE5TEVOdlBXWjFibU4wYVc5dUtDbDdmU3hOWVQxbWRXNWpkR2x2YmlobExIUXNiaXh5S1h0MllYSWdiRDFsTG0xbGJXOXBlbVZrVUhKdmNITTdhV1lvYkNF'
    || 'OVBYSXBlMlU5ZEM1emRHRjBaVTV2WkdVc1lXNG9YM1F1WTNWeWNtVnVkQ2s3ZG1GeUlHazliblZzYkR0emQybDBZMmdvYmlsN1kyRnpaU0pwYm5CMWRDSTZi'
    || 'RDEwYVNobExHd3BMSEk5ZEdrb1pTeHlLU3hwUFZ0ZE8ySnlaV0ZyTzJOaGMyVWljMlZzWldOMElqcHNQVTBvZTMwc2JDeDdkbUZzZFdVNmRtOXBaQ0F3ZlNr'
    || 'c2NqMU5LSHQ5TEhJc2UzWmhiSFZsT25admFXUWdNSDBwTEdrOVcxMDdZbkpsWVdzN1kyRnpaU0owWlhoMFlYSmxZU0k2YkQxc2FTaGxMR3dwTEhJOWJHa29a'
    || 'U3h5S1N4cFBWdGRPMkp5WldGck8yUmxabUYxYkhRNmRIbHdaVzltSUd3dWIyNURiR2xqYXlFOUltWjFibU4wYVc5dUlpWW1kSGx3Wlc5bUlISXViMjVEYkds'
    || 'amF6MDlJbVoxYm1OMGFXOXVJaVltS0dVdWIyNWpiR2xqYXoxMGJDbDliMmtvYml4eUtUdDJZWElnY3p0dVBXNTFiR3c3Wm05eUtHY2dhVzRnYkNscFppZ2hj'
    || 'aTVvWVhOUGQyNVFjbTl3WlhKMGVTaG5LU1ltYkM1b1lYTlBkMjVRY205d1pYSjBlU2huS1NZbWJGdG5YU0U5Ym5Wc2JDbHBaaWhuUFQwOUluTjBlV3hsSWls'
    || 'N2RtRnlJR0U5YkZ0blhUdG1iM0lvY3lCcGJpQmhLV0V1YUdGelQzZHVVSEp2Y0dWeWRIa29jeWttSmlodWZId29iajE3ZlNrc2JsdHpYVDBpSWlsOVpXeHpa'
    || 'U0JuSVQwOUltUmhibWRsY205MWMyeDVVMlYwU1c1dVpYSklWRTFNSWlZbVp5RTlQU0pqYUdsc1pISmxiaUltSm1jaFBUMGljM1Z3Y0hKbGMzTkRiMjUwWlc1'
    || 'MFJXUnBkR0ZpYkdWWFlYSnVhVzVuSWlZbVp5RTlQU0p6ZFhCd2NtVnpjMGg1WkhKaGRHbHZibGRoY201cGJtY2lKaVpuSVQwOUltRjFkRzlHYjJOMWN5SW1K'
    || 'aWhGTG1oaGMwOTNibEJ5YjNCbGNuUjVLR2NwUDJsOGZDaHBQVnRkS1Rvb2FUMXBmSHhiWFNrdWNIVnphQ2huTEc1MWJHd3BLVHRtYjNJb1p5QnBiaUJ5S1h0'
    || 'MllYSWdaajF5VzJkZE8ybG1LR0U5YkNFOWJuVnNiRDlzVzJkZE9uWnZhV1FnTUN4eUxtaGhjMDkzYmxCeWIzQmxjblI1S0djcEppWm1JVDA5WVNZbUtHWWhQ'
    || 'VzUxYkd4OGZHRWhQVzUxYkd3cEtXbG1LR2M5UFQwaWMzUjViR1VpS1dsbUtHRXBlMlp2Y2loeklHbHVJR0VwSVdFdWFHRnpUM2R1VUhKdmNHVnlkSGtvY3ls'
    || 'OGZHWW1KbVl1YUdGelQzZHVVSEp2Y0dWeWRIa29jeWw4ZkNodWZId29iajE3ZlNrc2JsdHpYVDBpSWlrN1ptOXlLSE1nYVc0Z1ppbG1MbWhoYzA5M2JsQnli'
    || 'M0JsY25SNUtITXBKaVpoVzNOZElUMDlabHR6WFNZbUtHNThmQ2h1UFh0OUtTeHVXM05kUFdaYmMxMHBmV1ZzYzJVZ2JueDhLR2w4ZkNocFBWdGRLU3hwTG5C'
    || 'MWMyZ29aeXh1S1Nrc2JqMW1PMlZzYzJVZ1p6MDlQU0prWVc1blpYSnZkWE5zZVZObGRFbHVibVZ5U0ZSTlRDSS9LR1k5Wmo5bUxsOWZhSFJ0YkRwMmIybGtJ'
    || 'REFzWVQxaFAyRXVYMTlvZEcxc09uWnZhV1FnTUN4bUlUMXVkV3hzSmlaaElUMDlaaVltS0drOWFYeDhXMTBwTG5CMWMyZ29aeXhtS1NrNlp6MDlQU0pqYUds'
    || 'c1pISmxiaUkvZEhsd1pXOW1JR1loUFNKemRISnBibWNpSmlaMGVYQmxiMllnWmlFOUltNTFiV0psY2lKOGZDaHBQV2w4ZkZ0ZEtTNXdkWE5vS0djc0lpSXJa'
    || 'aWs2WnlFOVBTSnpkWEJ3Y21WemMwTnZiblJsYm5SRlpHbDBZV0pzWlZkaGNtNXBibWNpSmlabklUMDlJbk4xY0hCeVpYTnpTSGxrY21GMGFXOXVWMkZ5Ym1s'
    || 'dVp5SW1KaWhGTG1oaGMwOTNibEJ5YjNCbGNuUjVLR2NwUHlobUlUMXVkV3hzSmlablBUMDlJbTl1VTJOeWIyeHNJaVltYkdVb0luTmpjbTlzYkNJc1pTa3Nh'
    || 'WHg4WVQwOVBXWjhmQ2hwUFZ0ZEtTazZLR2s5YVh4OFcxMHBMbkIxYzJnb1p5eG1LU2w5YmlZbUtHazlhWHg4VzEwcExuQjFjMmdvSW5OMGVXeGxJaXh1S1R0'
    || 'MllYSWdaejFwT3loMExuVndaR0YwWlZGMVpYVmxQV2NwSmlZb2RDNW1iR0ZuYzN3OU5DbDlmU3hKWVQxbWRXNWpkR2x2YmlobExIUXNiaXh5S1h0dUlUMDlj'
    || 'aVltS0hRdVpteGhaM044UFRRcGZUdG1kVzVqZEdsdmJpQnJjaWhsTEhRcGUybG1LQ0Z6WlNsemQybDBZMmdvWlM1MFlXbHNUVzlrWlNsN1kyRnpaU0pvYVdS'
    || 'a1pXNGlPblE5WlM1MFlXbHNPMlp2Y2loMllYSWdiajF1ZFd4c08zUWhQVDF1ZFd4c095bDBMbUZzZEdWeWJtRjBaU0U5UFc1MWJHd21KaWh1UFhRcExIUTlk'
    || 'QzV6YVdKc2FXNW5PMjQ5UFQxdWRXeHNQMlV1ZEdGcGJEMXVkV3hzT200dWMybGliR2x1WnoxdWRXeHNPMkp5WldGck8yTmhjMlVpWTI5c2JHRndjMlZrSWpw'
    || 'dVBXVXVkR0ZwYkR0bWIzSW9kbUZ5SUhJOWJuVnNiRHR1SVQwOWJuVnNiRHNwYmk1aGJIUmxjbTVoZEdVaFBUMXVkV3hzSmlZb2NqMXVLU3h1UFc0dWMybGli'
    || 'R2x1Wnp0eVBUMDliblZzYkQ5MGZIeGxMblJoYVd3OVBUMXVkV3hzUDJVdWRHRnBiRDF1ZFd4c09tVXVkR0ZwYkM1emFXSnNhVzVuUFc1MWJHdzZjaTV6YVdK'
    || 'c2FXNW5QVzUxYkd4OWZXWjFibU4wYVc5dUlFeGxLR1VwZTNaaGNpQjBQV1V1WVd4MFpYSnVZWFJsSVQwOWJuVnNiQ1ltWlM1aGJIUmxjbTVoZEdVdVkyaHBi'
    || 'R1E5UFQxbExtTm9hV3hrTEc0OU1DeHlQVEE3YVdZb2RDbG1iM0lvZG1GeUlHdzlaUzVqYUdsc1pEdHNJVDA5Ym5Wc2JEc3Bibnc5YkM1c1lXNWxjM3hzTG1O'
    || 'b2FXeGtUR0Z1WlhNc2NudzliQzV6ZFdKMGNtVmxSbXhoWjNNbU1UUTJPREF3TmpRc2NudzliQzVtYkdGbmN5WXhORFk0TURBMk5DeHNMbkpsZEhWeWJqMWxM'
    || 'R3c5YkM1emFXSnNhVzVuTzJWc2MyVWdabTl5S0d3OVpTNWphR2xzWkR0c0lUMDliblZzYkRzcGJudzliQzVzWVc1bGMzeHNMbU5vYVd4a1RHRnVaWE1zY253'
    || 'OWJDNXpkV0owY21WbFJteGhaM01zY253OWJDNW1iR0ZuY3l4c0xuSmxkSFZ5YmoxbExHdzliQzV6YVdKc2FXNW5PM0psZEhWeWJpQmxMbk4xWW5SeVpXVkdi'
    || 'R0ZuYzN3OWNpeGxMbU5vYVd4a1RHRnVaWE05Yml4MGZXWjFibU4wYVc5dUlFMW1LR1VzZEN4dUtYdDJZWElnY2oxMExuQmxibVJwYm1kUWNtOXdjenR6ZDJs'
    || 'MFkyZ29XV2tvZENrc2RDNTBZV2NwZTJOaGMyVWdNanBqWVhObElERTJPbU5oYzJVZ01UVTZZMkZ6WlNBd09tTmhjMlVnTVRFNlkyRnpaU0EzT21OaGMyVWdP'
    || 'RHBqWVhObElERXlPbU5oYzJVZ09UcGpZWE5sSURFME9uSmxkSFZ5YmlCTVpTaDBLU3h1ZFd4c08yTmhjMlVnTVRweVpYUjFjbTRnVldVb2RDNTBlWEJsS1NZ'
    || 'bWNtd29LU3hNWlNoMEtTeHVkV3hzTzJOaGMyVWdNenB5WlhSMWNtNGdjajEwTG5OMFlYUmxUbTlrWlN4R2JpZ3BMR2xsS0VGbEtTeHBaU2hVWlNrc2MyOG9L'
    || 'U3h5TG5CbGJtUnBibWREYjI1MFpYaDBKaVlvY2k1amIyNTBaWGgwUFhJdWNHVnVaR2x1WjBOdmJuUmxlSFFzY2k1d1pXNWthVzVuUTI5dWRHVjRkRDF1ZFd4'
    || 'c0tTd29aVDA5UFc1MWJHeDhmR1V1WTJocGJHUTlQVDF1ZFd4c0tTWW1LSFZzS0hRcFAzUXVabXhoWjNOOFBUUTZaVDA5UFc1MWJHeDhmR1V1YldWdGIybDZa'
    || 'V1JUZEdGMFpTNXBjMFJsYUhsa2NtRjBaV1FtSmloMExtWnNZV2R6SmpJMU5pazlQVDB3Zkh3b2RDNW1iR0ZuYzN3OU1UQXlOQ3hrZENFOVBXNTFiR3dtSmlo'
    || 'QmJ5aGtkQ2tzWkhROWJuVnNiQ2twS1N4RGJ5aGxMSFFwTEV4bEtIUXBMRzUxYkd3N1kyRnpaU0ExT21sdktIUXBPM1poY2lCc1BXRnVLSGh5TG1OMWNuSmxi'
    || 'blFwTzJsbUtHNDlkQzUwZVhCbExHVWhQVDF1ZFd4c0ppWjBMbk4wWVhSbFRtOWtaU0U5Ym5Wc2JDbE5ZU2hsTEhRc2JpeHlMR3dwTEdVdWNtVm1JVDA5ZEM1'
    || 'eVpXWW1KaWgwTG1ac1lXZHpmRDAxTVRJc2RDNW1iR0ZuYzN3OU1qQTVOekUxTWlrN1pXeHpaWHRwWmlnaGNpbDdhV1lvZEM1emRHRjBaVTV2WkdVOVBUMXVk'
    || 'V3hzS1hSb2NtOTNJRVZ5Y205eUtHTW9NVFkyS1NrN2NtVjBkWEp1SUV4bEtIUXBMRzUxYkd4OWFXWW9aVDFoYmloZmRDNWpkWEp5Wlc1MEtTeDFiQ2gwS1Ns'
    || 'N2NqMTBMbk4wWVhSbFRtOWtaU3h1UFhRdWRIbHdaVHQyWVhJZ2FUMTBMbTFsYlc5cGVtVmtVSEp2Y0hNN2MzZHBkR05vS0hKYmQzUmRQWFFzY2x0b2NsMDlh'
    || 'U3hsUFNoMExtMXZaR1VtTVNraFBUMHdMRzRwZTJOaGMyVWlaR2xoYkc5bklqcHNaU2dpWTJGdVkyVnNJaXh5S1N4c1pTZ2lZMnh2YzJVaUxISXBPMkp5WldG'
    || 'ck8yTmhjMlVpYVdaeVlXMWxJanBqWVhObEltOWlhbVZqZENJNlkyRnpaU0psYldKbFpDSTZiR1VvSW14dllXUWlMSElwTzJKeVpXRnJPMk5oYzJVaWRtbGta'
    || 'VzhpT21OaGMyVWlZWFZrYVc4aU9tWnZjaWhzUFRBN2JEeGtjaTVzWlc1bmRHZzdiQ3NyS1d4bEtHUnlXMnhkTEhJcE8ySnlaV0ZyTzJOaGMyVWljMjkxY21O'
    || 'bElqcHNaU2dpWlhKeWIzSWlMSElwTzJKeVpXRnJPMk5oYzJVaWFXMW5JanBqWVhObEltbHRZV2RsSWpwallYTmxJbXhwYm1zaU9teGxLQ0psY25KdmNpSXNj'
    || 'aWtzYkdVb0lteHZZV1FpTEhJcE8ySnlaV0ZyTzJOaGMyVWlaR1YwWVdsc2N5STZiR1VvSW5SdloyZHNaU0lzY2lrN1luSmxZV3M3WTJGelpTSnBibkIxZENJ'
    || 'NmFITW9jaXhwS1N4c1pTZ2lhVzUyWVd4cFpDSXNjaWs3WW5KbFlXczdZMkZ6WlNKelpXeGxZM1FpT25JdVgzZHlZWEJ3WlhKVGRHRjBaVDE3ZDJGelRYVnNk'
    || 'R2x3YkdVNklTRnBMbTExYkhScGNHeGxmU3hzWlNnaWFXNTJZV3hwWkNJc2NpazdZbkpsWVdzN1kyRnpaU0owWlhoMFlYSmxZU0k2WjNNb2NpeHBLU3hzWlNn'
    || 'aWFXNTJZV3hwWkNJc2NpbDliMmtvYml4cEtTeHNQVzUxYkd3N1ptOXlLSFpoY2lCeklHbHVJR2twYVdZb2FTNW9ZWE5QZDI1UWNtOXdaWEowZVNoektTbDdk'
    || 'bUZ5SUdFOWFWdHpYVHR6UFQwOUltTm9hV3hrY21WdUlqOTBlWEJsYjJZZ1lUMDlJbk4wY21sdVp5SS9jaTUwWlhoMFEyOXVkR1Z1ZENFOVBXRW1KaWhwTG5O'
    || 'MWNIQnlaWE56U0hsa2NtRjBhVzl1VjJGeWJtbHVaeUU5UFNFd0ppWmxiQ2h5TG5SbGVIUkRiMjUwWlc1MExHRXNaU2tzYkQxYkltTm9hV3hrY21WdUlpeGhY'
    || 'U2s2ZEhsd1pXOW1JR0U5UFNKdWRXMWlaWElpSmlaeUxuUmxlSFJEYjI1MFpXNTBJVDA5SWlJcllTWW1LR2t1YzNWd2NISmxjM05JZVdSeVlYUnBiMjVYWVhK'
    || 'dWFXNW5JVDA5SVRBbUptVnNLSEl1ZEdWNGRFTnZiblJsYm5Rc1lTeGxLU3hzUFZzaVkyaHBiR1J5Wlc0aUxDSWlLMkZkS1RwRkxtaGhjMDkzYmxCeWIzQmxj'
    || 'blI1S0hNcEppWmhJVDF1ZFd4c0ppWnpQVDA5SW05dVUyTnliMnhzSWlZbWJHVW9Jbk5qY205c2JDSXNjaWw5YzNkcGRHTm9LRzRwZTJOaGMyVWlhVzV3ZFhR'
    || 'aU9rOXlLSElwTEhaektISXNhU3doTUNrN1luSmxZV3M3WTJGelpTSjBaWGgwWVhKbFlTSTZUM0lvY2lrc2VITW9jaWs3WW5KbFlXczdZMkZ6WlNKelpXeGxZ'
    || 'M1FpT21OaGMyVWliM0IwYVc5dUlqcGljbVZoYXp0a1pXWmhkV3gwT25SNWNHVnZaaUJwTG05dVEyeHBZMnM5UFNKbWRXNWpkR2x2YmlJbUppaHlMbTl1WTJ4'
    || 'cFkyczlkR3dwZlhJOWJDeDBMblZ3WkdGMFpWRjFaWFZsUFhJc2NpRTlQVzUxYkd3bUppaDBMbVpzWVdkemZEMDBLWDFsYkhObGUzTTliQzV1YjJSbFZIbHda'
    || 'VDA5UFRrL2JEcHNMbTkzYm1WeVJHOWpkVzFsYm5Rc1pUMDlQU0pvZEhSd09pOHZkM2QzTG5jekxtOXlaeTh4T1RrNUwzaG9kRzFzSWlZbUtHVTlkM01vYmlr'
    || 'cExHVTlQVDBpYUhSMGNEb3ZMM2QzZHk1M015NXZjbWN2TVRrNU9TOTRhSFJ0YkNJL2JqMDlQU0p6WTNKcGNIUWlQeWhsUFhNdVkzSmxZWFJsUld4bGJXVnVk'
    || 'Q2dpWkdsMklpa3NaUzVwYm01bGNraFVUVXc5SWp4elkzSnBjSFErUEZ3dmMyTnlhWEIwUGlJc1pUMWxMbkpsYlc5MlpVTm9hV3hrS0dVdVptbHljM1JEYUds'
    || 'c1pDa3BPblI1Y0dWdlppQnlMbWx6UFQwaWMzUnlhVzVuSWo5bFBYTXVZM0psWVhSbFJXeGxiV1Z1ZENodUxIdHBjenB5TG1semZTazZLR1U5Y3k1amNtVmhk'
    || 'R1ZGYkdWdFpXNTBLRzRwTEc0OVBUMGljMlZzWldOMElpWW1LSE05WlN4eUxtMTFiSFJwY0d4bFAzTXViWFZzZEdsd2JHVTlJVEE2Y2k1emFYcGxKaVlvY3k1'
    || 'emFYcGxQWEl1YzJsNlpTa3BLVHBsUFhNdVkzSmxZWFJsUld4bGJXVnVkRTVUS0dVc2Jpa3NaVnQzZEYwOWRDeGxXMmh5WFQxeUxGQmhLR1VzZEN3aE1Td2hN'
    || 'U2tzZEM1emRHRjBaVTV2WkdVOVpUdGxPbnR6ZDJsMFkyZ29jejF6YVNodUxISXBMRzRwZTJOaGMyVWlaR2xoYkc5bklqcHNaU2dpWTJGdVkyVnNJaXhsS1N4'
    || 'c1pTZ2lZMnh2YzJVaUxHVXBMR3c5Y2p0aWNtVmhhenRqWVhObEltbG1jbUZ0WlNJNlkyRnpaU0p2WW1wbFkzUWlPbU5oYzJVaVpXMWlaV1FpT214bEtDSnNi'
    || 'MkZrSWl4bEtTeHNQWEk3WW5KbFlXczdZMkZ6WlNKMmFXUmxieUk2WTJGelpTSmhkV1JwYnlJNlptOXlLR3c5TUR0c1BHUnlMbXhsYm1kMGFEdHNLeXNwYkdV'
    || 'b1pISmJiRjBzWlNrN2JEMXlPMkp5WldGck8yTmhjMlVpYzI5MWNtTmxJanBzWlNnaVpYSnliM0lpTEdVcExHdzljanRpY21WaGF6dGpZWE5sSW1sdFp5STZZ'
    || 'MkZ6WlNKcGJXRm5aU0k2WTJGelpTSnNhVzVySWpwc1pTZ2laWEp5YjNJaUxHVXBMR3hsS0NKc2IyRmtJaXhsS1N4c1BYSTdZbkpsWVdzN1kyRnpaU0prWlhS'
    || 'aGFXeHpJanBzWlNnaWRHOW5aMnhsSWl4bEtTeHNQWEk3WW5KbFlXczdZMkZ6WlNKcGJuQjFkQ0k2YUhNb1pTeHlLU3hzUFhScEtHVXNjaWtzYkdVb0ltbHVk'
    || 'bUZzYVdRaUxHVXBPMkp5WldGck8yTmhjMlVpYjNCMGFXOXVJanBzUFhJN1luSmxZV3M3WTJGelpTSnpaV3hsWTNRaU9tVXVYM2R5WVhCd1pYSlRkR0YwWlQx'
    || 'N2QyRnpUWFZzZEdsd2JHVTZJU0Z5TG0xMWJIUnBjR3hsZlN4c1BVMG9lMzBzY2l4N2RtRnNkV1U2ZG05cFpDQXdmU2tzYkdVb0ltbHVkbUZzYVdRaUxHVXBP'
    || 'Mkp5WldGck8yTmhjMlVpZEdWNGRHRnlaV0VpT21kektHVXNjaWtzYkQxc2FTaGxMSElwTEd4bEtDSnBiblpoYkdsa0lpeGxLVHRpY21WaGF6dGtaV1poZFd4'
    || 'ME9tdzljbjF2YVNodUxHd3BMR0U5YkR0bWIzSW9hU0JwYmlCaEtXbG1LR0V1YUdGelQzZHVVSEp2Y0dWeWRIa29hU2twZTNaaGNpQm1QV0ZiYVYwN2FUMDlQ'
    || 'U0p6ZEhsc1pTSS9SWE1vWlN4bUtUcHBQVDA5SW1SaGJtZGxjbTkxYzJ4NVUyVjBTVzV1WlhKSVZFMU1JajhvWmoxbVAyWXVYMTlvZEcxc09uWnZhV1FnTUN4'
    || 'bUlUMXVkV3hzSmlaZmN5aGxMR1lwS1RwcFBUMDlJbU5vYVd4a2NtVnVJajkwZVhCbGIyWWdaajA5SW5OMGNtbHVaeUkvS0c0aFBUMGlkR1Y0ZEdGeVpXRWlm'
    || 'SHhtSVQwOUlpSXBKaVpIYmlobExHWXBPblI1Y0dWdlppQm1QVDBpYm5WdFltVnlJaVltUjI0b1pTd2lJaXRtS1RwcElUMDlJbk4xY0hCeVpYTnpRMjl1ZEdW'
    || 'dWRFVmthWFJoWW14bFYyRnlibWx1WnlJbUpta2hQVDBpYzNWd2NISmxjM05JZVdSeVlYUnBiMjVYWVhKdWFXNW5JaVltYVNFOVBTSmhkWFJ2Um05amRYTWlK'
    || 'aVlvUlM1b1lYTlBkMjVRY205d1pYSjBlU2hwS1Q5bUlUMXVkV3hzSmlacFBUMDlJbTl1VTJOeWIyeHNJaVltYkdVb0luTmpjbTlzYkNJc1pTazZaaUU5Ym5W'
    || 'c2JDWW1VV1VvWlN4cExHWXNjeWtwZlhOM2FYUmphQ2h1S1h0allYTmxJbWx1Y0hWMElqcFBjaWhsS1N4MmN5aGxMSElzSVRFcE8ySnlaV0ZyTzJOaGMyVWlk'
    || 'R1Y0ZEdGeVpXRWlPazl5S0dVcExIaHpLR1VwTzJKeVpXRnJPMk5oYzJVaWIzQjBhVzl1SWpweUxuWmhiSFZsSVQxdWRXeHNKaVpsTG5ObGRFRjBkSEpwWW5W'
    || 'MFpTZ2lkbUZzZFdVaUxDSWlLMlZsS0hJdWRtRnNkV1VwS1R0aWNtVmhhenRqWVhObEluTmxiR1ZqZENJNlpTNXRkV3gwYVhCc1pUMGhJWEl1YlhWc2RHbHdi'
    || 'R1VzYVQxeUxuWmhiSFZsTEdraFBXNTFiR3cvZVc0b1pTd2hJWEl1YlhWc2RHbHdiR1VzYVN3aE1TazZjaTVrWldaaGRXeDBWbUZzZFdVaFBXNTFiR3dtSm5s'
    || 'dUtHVXNJU0Z5TG0xMWJIUnBjR3hsTEhJdVpHVm1ZWFZzZEZaaGJIVmxMQ0V3S1R0aWNtVmhhenRrWldaaGRXeDBPblI1Y0dWdlppQnNMbTl1UTJ4cFkyczlQ'
    || 'U0ptZFc1amRHbHZiaUltSmlobExtOXVZMnhwWTJzOWRHd3BmWE4zYVhSamFDaHVLWHRqWVhObEltSjFkSFJ2YmlJNlkyRnpaU0pwYm5CMWRDSTZZMkZ6WlNK'
    || 'elpXeGxZM1FpT21OaGMyVWlkR1Y0ZEdGeVpXRWlPbkk5SVNGeUxtRjFkRzlHYjJOMWN6dGljbVZoYXlCbE8yTmhjMlVpYVcxbklqcHlQU0V3TzJKeVpXRnJJ'
    || 'R1U3WkdWbVlYVnNkRHB5UFNFeGZYMXlKaVlvZEM1bWJHRm5jM3c5TkNsOWRDNXlaV1loUFQxdWRXeHNKaVlvZEM1bWJHRm5jM3c5TlRFeUxIUXVabXhoWjNO'
    || 'OFBUSXdPVGN4TlRJcGZYSmxkSFZ5YmlCTVpTaDBLU3h1ZFd4c08yTmhjMlVnTmpwcFppaGxKaVowTG5OMFlYUmxUbTlrWlNFOWJuVnNiQ2xKWVNobExIUXNa'
    || 'UzV0WlcxdmFYcGxaRkJ5YjNCekxISXBPMlZzYzJWN2FXWW9kSGx3Wlc5bUlISWhQU0p6ZEhKcGJtY2lKaVowTG5OMFlYUmxUbTlrWlQwOVBXNTFiR3dwZEdo'
    || 'eWIzY2dSWEp5YjNJb1l5Z3hOallwS1R0cFppaHVQV0Z1S0hoeUxtTjFjbkpsYm5RcExHRnVLRjkwTG1OMWNuSmxiblFwTEhWc0tIUXBLWHRwWmloeVBYUXVj'
    || 'M1JoZEdWT2IyUmxMRzQ5ZEM1dFpXMXZhWHBsWkZCeWIzQnpMSEpiZDNSZFBYUXNLR2s5Y2k1dWIyUmxWbUZzZFdVaFBUMXVLU1ltS0dVOVdHVXNaU0U5UFc1'
    || 'MWJHd3BLWE4zYVhSamFDaGxMblJoWnlsN1kyRnpaU0F6T21Wc0tISXVibTlrWlZaaGJIVmxMRzRzS0dVdWJXOWtaU1l4S1NFOVBUQXBPMkp5WldGck8yTmhj'
    || 'MlVnTlRwbExtMWxiVzlwZW1Wa1VISnZjSE11YzNWd2NISmxjM05JZVdSeVlYUnBiMjVYWVhKdWFXNW5JVDA5SVRBbUptVnNLSEl1Ym05a1pWWmhiSFZsTEc0'
    || 'c0tHVXViVzlrWlNZeEtTRTlQVEFwZldrbUppaDBMbVpzWVdkemZEMDBLWDFsYkhObElISTlLRzR1Ym05a1pWUjVjR1U5UFQwNVAyNDZiaTV2ZDI1bGNrUnZZ'
    || 'M1Z0Wlc1MEtTNWpjbVZoZEdWVVpYaDBUbTlrWlNoeUtTeHlXM2QwWFQxMExIUXVjM1JoZEdWT2IyUmxQWEo5Y21WMGRYSnVJRXhsS0hRcExHNTFiR3c3WTJG'
    || 'elpTQXhNenBwWmlocFpTaGhaU2tzY2oxMExtMWxiVzlwZW1Wa1UzUmhkR1VzWlQwOVBXNTFiR3g4ZkdVdWJXVnRiMmw2WldSVGRHRjBaU0U5UFc1MWJHd21K'
    || 'bVV1YldWdGIybDZaV1JUZEdGMFpTNWtaV2g1WkhKaGRHVmtJVDA5Ym5Wc2JDbDdhV1lvYzJVbUpscGxJVDA5Ym5Wc2JDWW1LSFF1Ylc5a1pTWXhLU0U5UFRB'
    || 'bUppaDBMbVpzWVdkekpqRXlPQ2s5UFQwd0tVWjFLQ2tzVFc0b0tTeDBMbVpzWVdkemZEMDVPRFUyTUN4cFBTRXhPMlZzYzJVZ2FXWW9hVDExYkNoMEtTeHlJ'
    || 'VDA5Ym5Wc2JDWW1jaTVrWldoNVpISmhkR1ZrSVQwOWJuVnNiQ2w3YVdZb1pUMDlQVzUxYkd3cGUybG1LQ0ZwS1hSb2NtOTNJRVZ5Y205eUtHTW9NekU0S1Nr'
    || 'N2FXWW9hVDEwTG0xbGJXOXBlbVZrVTNSaGRHVXNhVDFwSVQwOWJuVnNiRDlwTG1SbGFIbGtjbUYwWldRNmJuVnNiQ3doYVNsMGFISnZkeUJGY25KdmNpaGpL'
    || 'RE14TnlrcE8ybGJkM1JkUFhSOVpXeHpaU0JOYmlncExDaDBMbVpzWVdkekpqRXlPQ2s5UFQwd0ppWW9kQzV0WlcxdmFYcGxaRk4wWVhSbFBXNTFiR3dwTEhR'
    || 'dVpteGhaM044UFRRN1RHVW9kQ2tzYVQwaE1YMWxiSE5sSUdSMElUMDliblZzYkNZbUtFRnZLR1IwS1N4a2REMXVkV3hzS1N4cFBTRXdPMmxtS0NGcEtYSmxk'
    || 'SFZ5YmlCMExtWnNZV2R6SmpZMU5UTTJQM1E2Ym5Wc2JIMXlaWFIxY200b2RDNW1iR0ZuY3lZeE1qZ3BJVDA5TUQ4b2RDNXNZVzVsY3oxdUxIUXBPaWh5UFhJ'
    || 'aFBUMXVkV3hzTEhJaFBUMG9aU0U5UFc1MWJHd21KbVV1YldWdGIybDZaV1JUZEdGMFpTRTlQVzUxYkd3cEppWnlKaVlvZEM1amFHbHNaQzVtYkdGbmMzdzlP'
    || 'REU1TWl3b2RDNXRiMlJsSmpFcElUMDlNQ1ltS0dVOVBUMXVkV3hzZkh3b1lXVXVZM1Z5Y21WdWRDWXhLU0U5UFRBL2VHVTlQVDB3SmlZb2VHVTlNeWs2U0c4'
    || 'b0tTa3BMSFF1ZFhCa1lYUmxVWFZsZFdVaFBUMXVkV3hzSmlZb2RDNW1iR0ZuYzN3OU5Da3NUR1VvZENrc2JuVnNiQ2s3WTJGelpTQTBPbkpsZEhWeWJpQkdi'
    || 'aWdwTEVOdktHVXNkQ2tzWlQwOVBXNTFiR3dtSm1aeUtIUXVjM1JoZEdWT2IyUmxMbU52Ym5SaGFXNWxja2x1Wm04cExFeGxLSFFwTEc1MWJHdzdZMkZ6WlNB'
    || 'eE1EcHlaWFIxY200Z1pXOG9kQzUwZVhCbExsOWpiMjUwWlhoMEtTeE1aU2gwS1N4dWRXeHNPMk5oYzJVZ01UYzZjbVYwZFhKdUlGVmxLSFF1ZEhsd1pTa21K'
    || 'bkpzS0Nrc1RHVW9kQ2tzYm5Wc2JEdGpZWE5sSURFNU9tbG1LR2xsS0dGbEtTeHBQWFF1YldWdGIybDZaV1JUZEdGMFpTeHBQVDA5Ym5Wc2JDbHlaWFIxY200'
    || 'Z1RHVW9kQ2tzYm5Wc2JEdHBaaWh5UFNoMExtWnNZV2R6SmpFeU9Da2hQVDB3TEhNOWFTNXlaVzVrWlhKcGJtY3NjejA5UFc1MWJHd3BhV1lvY2lscmNpaHBM'
    || 'Q0V4S1R0bGJITmxlMmxtS0hobElUMDlNSHg4WlNFOVBXNTFiR3dtSmlobExtWnNZV2R6SmpFeU9Da2hQVDB3S1dadmNpaGxQWFF1WTJocGJHUTdaU0U5UFc1'
    || 'MWJHdzdLWHRwWmloelBXaHNLR1VwTEhNaFBUMXVkV3hzS1h0bWIzSW9kQzVtYkdGbmMzdzlNVEk0TEd0eUtHa3NJVEVwTEhJOWN5NTFjR1JoZEdWUmRXVjFa'
    || 'U3h5SVQwOWJuVnNiQ1ltS0hRdWRYQmtZWFJsVVhWbGRXVTljaXgwTG1ac1lXZHpmRDAwS1N4MExuTjFZblJ5WldWR2JHRm5jejB3TEhJOWJpeHVQWFF1WTJo'
    || 'cGJHUTdiaUU5UFc1MWJHdzdLV2s5Yml4bFBYSXNhUzVtYkdGbmN5WTlNVFEyT0RBd05qWXNjejFwTG1Gc2RHVnlibUYwWlN4elBUMDliblZzYkQ4b2FTNWph'
    || 'R2xzWkV4aGJtVnpQVEFzYVM1c1lXNWxjejFsTEdrdVkyaHBiR1E5Ym5Wc2JDeHBMbk4xWW5SeVpXVkdiR0ZuY3owd0xHa3ViV1Z0YjJsNlpXUlFjbTl3Y3ox'
    || 'dWRXeHNMR2t1YldWdGIybDZaV1JUZEdGMFpUMXVkV3hzTEdrdWRYQmtZWFJsVVhWbGRXVTliblZzYkN4cExtUmxjR1Z1WkdWdVkybGxjejF1ZFd4c0xHa3Vj'
    || 'M1JoZEdWT2IyUmxQVzUxYkd3cE9paHBMbU5vYVd4a1RHRnVaWE05Y3k1amFHbHNaRXhoYm1WekxHa3ViR0Z1WlhNOWN5NXNZVzVsY3l4cExtTm9hV3hrUFhN'
    || 'dVkyaHBiR1FzYVM1emRXSjBjbVZsUm14aFozTTlNQ3hwTG1SbGJHVjBhVzl1Y3oxdWRXeHNMR2t1YldWdGIybDZaV1JRY205d2N6MXpMbTFsYlc5cGVtVmtV'
    || 'SEp2Y0hNc2FTNXRaVzF2YVhwbFpGTjBZWFJsUFhNdWJXVnRiMmw2WldSVGRHRjBaU3hwTG5Wd1pHRjBaVkYxWlhWbFBYTXVkWEJrWVhSbFVYVmxkV1VzYVM1'
    || 'MGVYQmxQWE11ZEhsd1pTeGxQWE11WkdWd1pXNWtaVzVqYVdWekxHa3VaR1Z3Wlc1a1pXNWphV1Z6UFdVOVBUMXVkV3hzUDI1MWJHdzZlMnhoYm1Wek9tVXVi'
    || 'R0Z1WlhNc1ptbHljM1JEYjI1MFpYaDBPbVV1Wm1seWMzUkRiMjUwWlhoMGZTa3NiajF1TG5OcFlteHBibWM3Y21WMGRYSnVJSEpsS0dGbExHRmxMbU4xY25K'
    || 'bGJuUW1NWHd5S1N4MExtTm9hV3hrZldVOVpTNXphV0pzYVc1bmZXa3VkR0ZwYkNFOVBXNTFiR3dtSm1obEtDaytTRzRtSmloMExtWnNZV2R6ZkQweE1qZ3Nj'
    || 'ajBoTUN4cmNpaHBMQ0V4S1N4MExteGhibVZ6UFRReE9UUXpNRFFwZldWc2MyVjdhV1lvSVhJcGFXWW9aVDFvYkNoektTeGxJVDA5Ym5Wc2JDbDdhV1lvZEM1'
    || 'bWJHRm5jM3c5TVRJNExISTlJVEFzYmoxbExuVndaR0YwWlZGMVpYVmxMRzRoUFQxdWRXeHNKaVlvZEM1MWNHUmhkR1ZSZFdWMVpUMXVMSFF1Wm14aFozTjhQ'
    || 'VFFwTEd0eUtHa3NJVEFwTEdrdWRHRnBiRDA5UFc1MWJHd21KbWt1ZEdGcGJFMXZaR1U5UFQwaWFHbGtaR1Z1SWlZbUlYTXVZV3gwWlhKdVlYUmxKaVloYzJV'
    || 'cGNtVjBkWEp1SUV4bEtIUXBMRzUxYkd4OVpXeHpaU0F5S21obEtDa3RhUzV5Wlc1a1pYSnBibWRUZEdGeWRGUnBiV1UrU0c0bUptNGhQVDB4TURjek56UXhP'
    || 'REkwSmlZb2RDNW1iR0ZuYzN3OU1USTRMSEk5SVRBc2EzSW9hU3doTVNrc2RDNXNZVzVsY3owME1UazBNekEwS1R0cExtbHpRbUZqYTNkaGNtUnpQeWh6TG5O'
    || 'cFlteHBibWM5ZEM1amFHbHNaQ3gwTG1Ob2FXeGtQWE1wT2lodVBXa3ViR0Z6ZEN4dUlUMDliblZzYkQ5dUxuTnBZbXhwYm1jOWN6cDBMbU5vYVd4a1BYTXNh'
    || 'UzVzWVhOMFBYTXBmWEpsZEhWeWJpQnBMblJoYVd3aFBUMXVkV3hzUHloMFBXa3VkR0ZwYkN4cExuSmxibVJsY21sdVp6MTBMR2t1ZEdGcGJEMTBMbk5wWW14'
    || 'cGJtY3NhUzV5Wlc1a1pYSnBibWRUZEdGeWRGUnBiV1U5YUdVb0tTeDBMbk5wWW14cGJtYzliblZzYkN4dVBXRmxMbU4xY25KbGJuUXNjbVVvWVdVc2NqOXVK'
    || 'akY4TWpwdUpqRXBMSFFwT2loTVpTaDBLU3h1ZFd4c0tUdGpZWE5sSURJeU9tTmhjMlVnTWpNNmNtVjBkWEp1SUNSdktDa3NjajEwTG0xbGJXOXBlbVZrVTNS'
    || 'aGRHVWhQVDF1ZFd4c0xHVWhQVDF1ZFd4c0ppWmxMbTFsYlc5cGVtVmtVM1JoZEdVaFBUMXVkV3hzSVQwOWNpWW1LSFF1Wm14aFozTjhQVGd4T1RJcExISW1K'
    || 'aWgwTG0xdlpHVW1NU2toUFQwd1B5aHhaU1l4TURjek56UXhPREkwS1NFOVBUQW1KaWhNWlNoMEtTeDBMbk4xWW5SeVpXVkdiR0ZuY3lZMkppWW9kQzVtYkdG'
    || 'bmMzdzlPREU1TWlrcE9reGxLSFFwTEc1MWJHdzdZMkZ6WlNBeU5EcHlaWFIxY200Z2JuVnNiRHRqWVhObElESTFPbkpsZEhWeWJpQnVkV3hzZlhSb2NtOTNJ'
    || 'RVZ5Y205eUtHTW9NVFUyTEhRdWRHRm5LU2w5Wm5WdVkzUnBiMjRnU1dZb1pTeDBLWHR6ZDJsMFkyZ29XV2tvZENrc2RDNTBZV2NwZTJOaGMyVWdNVHB5WlhS'
    || 'MWNtNGdWV1VvZEM1MGVYQmxLU1ltY213b0tTeGxQWFF1Wm14aFozTXNaU1kyTlRVek5qOG9kQzVtYkdGbmN6MWxKaTAyTlRVek4zd3hNamdzZENrNmJuVnNi'
    || 'RHRqWVhObElETTZjbVYwZFhKdUlFWnVLQ2tzYVdVb1FXVXBMR2xsS0ZSbEtTeHpieWdwTEdVOWRDNW1iR0ZuY3l3b1pTWTJOVFV6TmlraFBUMHdKaVlvWlNZ'
    || 'eE1qZ3BQVDA5TUQ4b2RDNW1iR0ZuY3oxbEppMDJOVFV6TjN3eE1qZ3NkQ2s2Ym5Wc2JEdGpZWE5sSURVNmNtVjBkWEp1SUdsdktIUXBMRzUxYkd3N1kyRnpa'
    || 'U0F4TXpwcFppaHBaU2hoWlNrc1pUMTBMbTFsYlc5cGVtVmtVM1JoZEdVc1pTRTlQVzUxYkd3bUptVXVaR1ZvZVdSeVlYUmxaQ0U5UFc1MWJHd3BlMmxtS0hR'
    || 'dVlXeDBaWEp1WVhSbFBUMDliblZzYkNsMGFISnZkeUJGY25KdmNpaGpLRE0wTUNrcE8wMXVLQ2w5Y21WMGRYSnVJR1U5ZEM1bWJHRm5jeXhsSmpZMU5UTTJQ'
    || 'eWgwTG1ac1lXZHpQV1VtTFRZMU5UTTNmREV5T0N4MEtUcHVkV3hzTzJOaGMyVWdNVGs2Y21WMGRYSnVJR2xsS0dGbEtTeHVkV3hzTzJOaGMyVWdORHB5WlhS'
    || 'MWNtNGdSbTRvS1N4dWRXeHNPMk5oYzJVZ01UQTZjbVYwZFhKdUlHVnZLSFF1ZEhsd1pTNWZZMjl1ZEdWNGRDa3NiblZzYkR0allYTmxJREl5T21OaGMyVWdN'
    || 'ak02Y21WMGRYSnVJQ1J2S0Nrc2JuVnNiRHRqWVhObElESTBPbkpsZEhWeWJpQnVkV3hzTzJSbFptRjFiSFE2Y21WMGRYSnVJRzUxYkd4OWZYWmhjaUJGYkQw'
    || 'aE1TeFBaVDBoTVN4RVpqMTBlWEJsYjJZZ1YyVmhhMU5sZEQwOUltWjFibU4wYVc5dUlqOVhaV0ZyVTJWME9sTmxkQ3hRUFc1MWJHdzdablZ1WTNScGIyNGdW'
    || 'VzRvWlN4MEtYdDJZWElnYmoxbExuSmxaanRwWmlodUlUMDliblZzYkNscFppaDBlWEJsYjJZZ2JqMDlJbVoxYm1OMGFXOXVJaWwwY25sN2JpaHVkV3hzS1gx'
    || 'allYUmphQ2h5S1h0d1pTaGxMSFFzY2lsOVpXeHpaU0J1TG1OMWNuSmxiblE5Ym5Wc2JIMW1kVzVqZEdsdmJpQlVieWhsTEhRc2JpbDdkSEo1ZTI0b0tYMWpZ'
    || 'WFJqYUNoeUtYdHdaU2hsTEhRc2NpbDlmWFpoY2lCRVlUMGhNVHRtZFc1amRHbHZiaUI2WmlobExIUXBlMmxtS0ZWcFBWZHlMR1U5Y0hVb0tTeFBhU2hsS1Ns'
    || 'N2FXWW9Jbk5sYkdWamRHbHZibE4wWVhKMEltbHVJR1VwZG1GeUlHNDllM04wWVhKME9tVXVjMlZzWldOMGFXOXVVM1JoY25Rc1pXNWtPbVV1YzJWc1pXTjBh'
    || 'Vzl1Ulc1a2ZUdGxiSE5sSUdVNmUyNDlLRzQ5WlM1dmQyNWxja1J2WTNWdFpXNTBLU1ltYmk1a1pXWmhkV3gwVm1sbGQzeDhkMmx1Wkc5M08zWmhjaUJ5UFc0'
    || 'dVoyVjBVMlZzWldOMGFXOXVKaVp1TG1kbGRGTmxiR1ZqZEdsdmJpZ3BPMmxtS0hJbUpuSXVjbUZ1WjJWRGIzVnVkQ0U5UFRBcGUyNDljaTVoYm1Ob2IzSk9i'
    || 'MlJsTzNaaGNpQnNQWEl1WVc1amFHOXlUMlptYzJWMExHazljaTVtYjJOMWMwNXZaR1U3Y2oxeUxtWnZZM1Z6VDJabWMyVjBPM1J5ZVh0dUxtNXZaR1ZVZVhC'
    || 'bExHa3VibTlrWlZSNWNHVjlZMkYwWTJoN2JqMXVkV3hzTzJKeVpXRnJJR1Y5ZG1GeUlITTlNQ3hoUFMweExHWTlMVEVzWnowd0xGTTlNQ3hyUFdVc2R6MXVk'
    || 'V3hzTzNRNlptOXlLRHM3S1h0bWIzSW9kbUZ5SUU4N2F5RTlQVzU4Zkd3aFBUMHdKaVpyTG01dlpHVlVlWEJsSVQwOU0zeDhLR0U5Y3l0c0tTeHJJVDA5YVh4'
    || 'OGNpRTlQVEFtSm1zdWJtOWtaVlI1Y0dVaFBUMHpmSHdvWmoxekszSXBMR3N1Ym05a1pWUjVjR1U5UFQwekppWW9jeXM5YXk1dWIyUmxWbUZzZFdVdWJHVnVa'
    || 'M1JvS1N3b1R6MXJMbVpwY25OMFEyaHBiR1FwSVQwOWJuVnNiRHNwZHoxckxHczlUenRtYjNJb096c3BlMmxtS0dzOVBUMWxLV0p5WldGcklIUTdhV1lvZHow'
    || 'OVBXNG1KaXNyWnowOVBXd21KaWhoUFhNcExIYzlQVDFwSmlZcksxTTlQVDF5SmlZb1pqMXpLU3dvVHoxckxtNWxlSFJUYVdKc2FXNW5LU0U5UFc1MWJHd3BZ'
    || 'bkpsWVdzN2F6MTNMSGM5YXk1d1lYSmxiblJPYjJSbGZXczlUMzF1UFdFOVBUMHRNWHg4WmowOVBTMHhQMjUxYkd3NmUzTjBZWEowT21Fc1pXNWtPbVo5ZldW'
    || 'c2MyVWdiajF1ZFd4c2ZXNDlibng4ZTNOMFlYSjBPakFzWlc1a09qQjlmV1ZzYzJVZ2JqMXVkV3hzTzJadmNpZ2thVDE3Wm05amRYTmxaRVZzWlcwNlpTeHpa'
    || 'V3hsWTNScGIyNVNZVzVuWlRwdWZTeFhjajBoTVN4UVBYUTdVQ0U5UFc1MWJHdzdLV2xtS0hROVVDeGxQWFF1WTJocGJHUXNLSFF1YzNWaWRISmxaVVpzWVdk'
    || 'ekpqRXdNamdwSVQwOU1DWW1aU0U5UFc1MWJHd3BaUzV5WlhSMWNtNDlkQ3hRUFdVN1pXeHpaU0JtYjNJb08xQWhQVDF1ZFd4c095bDdkRDFRTzNSeWVYdDJZ'
    || 'WElnU1QxMExtRnNkR1Z5Ym1GMFpUdHBaaWdvZEM1bWJHRm5jeVl4TURJMEtTRTlQVEFwYzNkcGRHTm9LSFF1ZEdGbktYdGpZWE5sSURBNlkyRnpaU0F4TVRw'
    || 'allYTmxJREUxT21KeVpXRnJPMk5oYzJVZ01UcHBaaWhKSVQwOWJuVnNiQ2w3ZG1GeUlFUTlTUzV0WlcxdmFYcGxaRkJ5YjNCekxHMWxQVWt1YldWdGIybDZa'
    || 'V1JUZEdGMFpTeHRQWFF1YzNSaGRHVk9iMlJsTEhBOWJTNW5aWFJUYm1Gd2MyaHZkRUpsWm05eVpWVndaR0YwWlNoMExtVnNaVzFsYm5SVWVYQmxQVDA5ZEM1'
    || 'MGVYQmxQMFE2Wm5Rb2RDNTBlWEJsTEVRcExHMWxLVHR0TGw5ZmNtVmhZM1JKYm5SbGNtNWhiRk51WVhCemFHOTBRbVZtYjNKbFZYQmtZWFJsUFhCOVluSmxZ'
    || 'V3M3WTJGelpTQXpPblpoY2lCMlBYUXVjM1JoZEdWT2IyUmxMbU52Ym5SaGFXNWxja2x1Wm04N2RpNXViMlJsVkhsd1pUMDlQVEUvZGk1MFpYaDBRMjl1ZEdW'
    || 'dWREMGlJanAyTG01dlpHVlVlWEJsUFQwOU9TWW1kaTVrYjJOMWJXVnVkRVZzWlcxbGJuUW1Kbll1Y21WdGIzWmxRMmhwYkdRb2RpNWtiMk4xYldWdWRFVnNa'
    || 'VzFsYm5RcE8ySnlaV0ZyTzJOaGMyVWdOVHBqWVhObElEWTZZMkZ6WlNBME9tTmhjMlVnTVRjNlluSmxZV3M3WkdWbVlYVnNkRHAwYUhKdmR5QkZjbkp2Y2lo'
    || 'aktERTJNeWtwZlgxallYUmphQ2hES1h0d1pTaDBMSFF1Y21WMGRYSnVMRU1wZldsbUtHVTlkQzV6YVdKc2FXNW5MR1VoUFQxdWRXeHNLWHRsTG5KbGRIVnli'
    || 'ajEwTG5KbGRIVnliaXhRUFdVN1luSmxZV3Q5VUQxMExuSmxkSFZ5Ym4xeVpYUjFjbTRnU1QxRVlTeEVZVDBoTVN4SmZXWjFibU4wYVc5dUlFNXlLR1VzZEN4'
    || 'dUtYdDJZWElnY2oxMExuVndaR0YwWlZGMVpYVmxPMmxtS0hJOWNpRTlQVzUxYkd3L2NpNXNZWE4wUldabVpXTjBPbTUxYkd3c2NpRTlQVzUxYkd3cGUzWmhj'
    || 'aUJzUFhJOWNpNXVaWGgwTzJSdmUybG1LQ2hzTG5SaFp5WmxLVDA5UFdVcGUzWmhjaUJwUFd3dVpHVnpkSEp2ZVR0c0xtUmxjM1J5YjNrOWRtOXBaQ0F3TEdr'
    || 'aFBUMTJiMmxrSURBbUpsUnZLSFFzYml4cEtYMXNQV3d1Ym1WNGRIMTNhR2xzWlNoc0lUMDljaWw5ZldaMWJtTjBhVzl1SUd0c0tHVXNkQ2w3YVdZb2REMTBM'
    || 'blZ3WkdGMFpWRjFaWFZsTEhROWRDRTlQVzUxYkd3L2RDNXNZWE4wUldabVpXTjBPbTUxYkd3c2RDRTlQVzUxYkd3cGUzWmhjaUJ1UFhROWRDNXVaWGgwTzJS'
    || 'dmUybG1LQ2h1TG5SaFp5WmxLVDA5UFdVcGUzWmhjaUJ5UFc0dVkzSmxZWFJsTzI0dVpHVnpkSEp2ZVQxeUtDbDliajF1TG01bGVIUjlkMmhwYkdVb2JpRTlQ'
    || 'WFFwZlgxbWRXNWpkR2x2YmlCU2J5aGxLWHQyWVhJZ2REMWxMbkpsWmp0cFppaDBJVDA5Ym5Wc2JDbDdkbUZ5SUc0OVpTNXpkR0YwWlU1dlpHVTdjM2RwZEdO'
    || 'b0tHVXVkR0ZuS1h0allYTmxJRFU2WlQxdU8ySnlaV0ZyTzJSbFptRjFiSFE2WlQxdWZYUjVjR1Z2WmlCMFBUMGlablZ1WTNScGIyNGlQM1FvWlNrNmRDNWpk'
    || 'WEp5Wlc1MFBXVjlmV1oxYm1OMGFXOXVJSHBoS0dVcGUzWmhjaUIwUFdVdVlXeDBaWEp1WVhSbE8zUWhQVDF1ZFd4c0ppWW9aUzVoYkhSbGNtNWhkR1U5Ym5W'
    || 'c2JDeDZZU2gwS1Nrc1pTNWphR2xzWkQxdWRXeHNMR1V1WkdWc1pYUnBiMjV6UFc1MWJHd3NaUzV6YVdKc2FXNW5QVzUxYkd3c1pTNTBZV2M5UFQwMUppWW9k'
    || 'RDFsTG5OMFlYUmxUbTlrWlN4MElUMDliblZzYkNZbUtHUmxiR1YwWlNCMFczZDBYU3hrWld4bGRHVWdkRnRvY2wwc1pHVnNaWFJsSUhSYlFtbGRMR1JsYkdW'
    || 'MFpTQjBXM2xtWFN4a1pXeGxkR1VnZEZ0NFpsMHBLU3hsTG5OMFlYUmxUbTlrWlQxdWRXeHNMR1V1Y21WMGRYSnVQVzUxYkd3c1pTNWtaWEJsYm1SbGJtTnBa'
    || 'WE05Ym5Wc2JDeGxMbTFsYlc5cGVtVmtVSEp2Y0hNOWJuVnNiQ3hsTG0xbGJXOXBlbVZrVTNSaGRHVTliblZzYkN4bExuQmxibVJwYm1kUWNtOXdjejF1ZFd4'
    || 'c0xHVXVjM1JoZEdWT2IyUmxQVzUxYkd3c1pTNTFjR1JoZEdWUmRXVjFaVDF1ZFd4c2ZXWjFibU4wYVc5dUlFWmhLR1VwZTNKbGRIVnliaUJsTG5SaFp6MDlQ'
    || 'VFY4ZkdVdWRHRm5QVDA5TTN4OFpTNTBZV2M5UFQwMGZXWjFibU4wYVc5dUlFRmhLR1VwZTJVNlptOXlLRHM3S1h0bWIzSW9PMlV1YzJsaWJHbHVaejA5UFc1'
    || 'MWJHdzdLWHRwWmlobExuSmxkSFZ5YmowOVBXNTFiR3g4ZkVaaEtHVXVjbVYwZFhKdUtTbHlaWFIxY200Z2JuVnNiRHRsUFdVdWNtVjBkWEp1ZldadmNpaGxM'
    || 'bk5wWW14cGJtY3VjbVYwZFhKdVBXVXVjbVYwZFhKdUxHVTlaUzV6YVdKc2FXNW5PMlV1ZEdGbklUMDlOU1ltWlM1MFlXY2hQVDAySmlabExuUmhaeUU5UFRF'
    || 'NE95bDdhV1lvWlM1bWJHRm5jeVl5Zkh4bExtTm9hV3hrUFQwOWJuVnNiSHg4WlM1MFlXYzlQVDAwS1dOdmJuUnBiblZsSUdVN1pTNWphR2xzWkM1eVpYUjFj'
    || 'bTQ5WlN4bFBXVXVZMmhwYkdSOWFXWW9JU2hsTG1ac1lXZHpKaklwS1hKbGRIVnliaUJsTG5OMFlYUmxUbTlrWlgxOVpuVnVZM1JwYjI0Z1RHOG9aU3gwTEc0'
    || 'cGUzWmhjaUJ5UFdVdWRHRm5PMmxtS0hJOVBUMDFmSHh5UFQwOU5pbGxQV1V1YzNSaGRHVk9iMlJsTEhRL2JpNXViMlJsVkhsd1pUMDlQVGcvYmk1d1lYSmxi'
    || 'blJPYjJSbExtbHVjMlZ5ZEVKbFptOXlaU2hsTEhRcE9tNHVhVzV6WlhKMFFtVm1iM0psS0dVc2RDazZLRzR1Ym05a1pWUjVjR1U5UFQwNFB5aDBQVzR1Y0dG'
    || 'eVpXNTBUbTlrWlN4MExtbHVjMlZ5ZEVKbFptOXlaU2hsTEc0cEtUb29kRDF1TEhRdVlYQndaVzVrUTJocGJHUW9aU2twTEc0OWJpNWZjbVZoWTNSU2IyOTBR'
    || 'Mjl1ZEdGcGJtVnlMRzRoUFc1MWJHeDhmSFF1YjI1amJHbGpheUU5UFc1MWJHeDhmQ2gwTG05dVkyeHBZMnM5ZEd3cEtUdGxiSE5sSUdsbUtISWhQVDAwSmlZ'
    || 'b1pUMWxMbU5vYVd4a0xHVWhQVDF1ZFd4c0tTbG1iM0lvVEc4b1pTeDBMRzRwTEdVOVpTNXphV0pzYVc1bk8yVWhQVDF1ZFd4c095bE1ieWhsTEhRc2Jpa3Na'
    || 'VDFsTG5OcFlteHBibWQ5Wm5WdVkzUnBiMjRnVDI4b1pTeDBMRzRwZTNaaGNpQnlQV1V1ZEdGbk8ybG1LSEk5UFQwMWZIeHlQVDA5TmlsbFBXVXVjM1JoZEdW'
    || 'T2IyUmxMSFEvYmk1cGJuTmxjblJDWldadmNtVW9aU3gwS1RwdUxtRndjR1Z1WkVOb2FXeGtLR1VwTzJWc2MyVWdhV1lvY2lFOVBUUW1KaWhsUFdVdVkyaHBi'
    || 'R1FzWlNFOVBXNTFiR3dwS1dadmNpaFBieWhsTEhRc2Jpa3NaVDFsTG5OcFlteHBibWM3WlNFOVBXNTFiR3c3S1U5dktHVXNkQ3h1S1N4bFBXVXVjMmxpYkds'
    || 'dVozMTJZWElnYW1VOWJuVnNiQ3h3ZEQwaE1UdG1kVzVqZEdsdmJpQlpkQ2hsTEhRc2JpbDdabTl5S0c0OWJpNWphR2xzWkR0dUlUMDliblZzYkRzcFZXRW9a'
    || 'U3gwTEc0cExHNDliaTV6YVdKc2FXNW5mV1oxYm1OMGFXOXVJRlZoS0dVc2RDeHVLWHRwWmloNGRDWW1kSGx3Wlc5bUlIaDBMbTl1UTI5dGJXbDBSbWxpWlhK'
    || 'VmJtMXZkVzUwUFQwaVpuVnVZM1JwYjI0aUtYUnllWHQ0ZEM1dmJrTnZiVzFwZEVacFltVnlWVzV0YjNWdWRDaEdjaXh1S1gxallYUmphSHQ5YzNkcGRHTm9L'
    || 'RzR1ZEdGbktYdGpZWE5sSURVNlQyVjhmRlZ1S0c0c2RDazdZMkZ6WlNBMk9uWmhjaUJ5UFdwbExHdzljSFE3YW1VOWJuVnNiQ3haZENobExIUXNiaWtzYW1V'
    || 'OWNpeHdkRDFzTEdwbElUMDliblZzYkNZbUtIQjBQeWhsUFdwbExHNDliaTV6ZEdGMFpVNXZaR1VzWlM1dWIyUmxWSGx3WlQwOVBUZy9aUzV3WVhKbGJuUk9i'
    || 'MlJsTG5KbGJXOTJaVU5vYVd4a0tHNHBPbVV1Y21WdGIzWmxRMmhwYkdRb2Jpa3BPbXBsTG5KbGJXOTJaVU5vYVd4a0tHNHVjM1JoZEdWT2IyUmxLU2s3WW5K'
    || 'bFlXczdZMkZ6WlNBeE9EcHFaU0U5UFc1MWJHd21KaWh3ZEQ4b1pUMXFaU3h1UFc0dWMzUmhkR1ZPYjJSbExHVXVibTlrWlZSNWNHVTlQVDA0UDFkcEtHVXVj'
    || 'R0Z5Wlc1MFRtOWtaU3h1S1RwbExtNXZaR1ZVZVhCbFBUMDlNU1ltVjJrb1pTeHVLU3h5Y2lobEtTazZWMmtvYW1Vc2JpNXpkR0YwWlU1dlpHVXBLVHRpY21W'
    || 'aGF6dGpZWE5sSURRNmNqMXFaU3hzUFhCMExHcGxQVzR1YzNSaGRHVk9iMlJsTG1OdmJuUmhhVzVsY2tsdVptOHNjSFE5SVRBc1dYUW9aU3gwTEc0cExHcGxQ'
    || 'WElzY0hROWJEdGljbVZoYXp0allYTmxJREE2WTJGelpTQXhNVHBqWVhObElERTBPbU5oYzJVZ01UVTZhV1lvSVU5bEppWW9jajF1TG5Wd1pHRjBaVkYxWlhW'
    || 'bExISWhQVDF1ZFd4c0ppWW9jajF5TG14aGMzUkZabVpsWTNRc2NpRTlQVzUxYkd3cEtTbDdiRDF5UFhJdWJtVjRkRHRrYjN0MllYSWdhVDFzTEhNOWFTNWta'
    || 'WE4wY205NU8yazlhUzUwWVdjc2N5RTlQWFp2YVdRZ01DWW1LQ2hwSmpJcElUMDlNSHg4S0drbU5Da2hQVDB3S1NZbVZHOG9iaXgwTEhNcExHdzliQzV1Wlho'
    || 'MGZYZG9hV3hsS0d3aFBUMXlLWDFaZENobExIUXNiaWs3WW5KbFlXczdZMkZ6WlNBeE9tbG1LQ0ZQWlNZbUtGVnVLRzRzZENrc2NqMXVMbk4wWVhSbFRtOWta'
    || 'U3gwZVhCbGIyWWdjaTVqYjIxd2IyNWxiblJYYVd4c1ZXNXRiM1Z1ZEQwOUltWjFibU4wYVc5dUlpa3BkSEo1ZTNJdWNISnZjSE05Ymk1dFpXMXZhWHBsWkZC'
    || 'eWIzQnpMSEl1YzNSaGRHVTliaTV0WlcxdmFYcGxaRk4wWVhSbExISXVZMjl0Y0c5dVpXNTBWMmxzYkZWdWJXOTFiblFvS1gxallYUmphQ2hoS1h0d1pTaHVM'
    || 'SFFzWVNsOVdYUW9aU3gwTEc0cE8ySnlaV0ZyTzJOaGMyVWdNakU2V1hRb1pTeDBMRzRwTzJKeVpXRnJPMk5oYzJVZ01qSTZiaTV0YjJSbEpqRS9LRTlsUFNo'
    || 'eVBVOWxLWHg4Ymk1dFpXMXZhWHBsWkZOMFlYUmxJVDA5Ym5Wc2JDeFpkQ2hsTEhRc2Jpa3NUMlU5Y2lrNldYUW9aU3gwTEc0cE8ySnlaV0ZyTzJSbFptRjFi'
    || 'SFE2V1hRb1pTeDBMRzRwZlgxbWRXNWpkR2x2YmlBa1lTaGxLWHQyWVhJZ2REMWxMblZ3WkdGMFpWRjFaWFZsTzJsbUtIUWhQVDF1ZFd4c0tYdGxMblZ3WkdG'
    || 'MFpWRjFaWFZsUFc1MWJHdzdkbUZ5SUc0OVpTNXpkR0YwWlU1dlpHVTdiajA5UFc1MWJHd21KaWh1UFdVdWMzUmhkR1ZPYjJSbFBXNWxkeUJFWmlrc2RDNW1i'
    || 'M0pGWVdOb0tHWjFibU4wYVc5dUtISXBlM1poY2lCc1BWRm1MbUpwYm1Rb2JuVnNiQ3hsTEhJcE8yNHVhR0Z6S0hJcGZId29iaTVoWkdRb2Npa3NjaTUwYUdW'
    || 'dUtHd3NiQ2twZlNsOWZXWjFibU4wYVc5dUlHaDBLR1VzZENsN2RtRnlJRzQ5ZEM1a1pXeGxkR2x2Ym5NN2FXWW9iaUU5UFc1MWJHd3BabTl5S0haaGNpQnlQ'
    || 'VEE3Y2p4dUxteGxibWQwYUR0eUt5c3BlM1poY2lCc1BXNWJjbDA3ZEhKNWUzWmhjaUJwUFdVc2N6MTBMR0U5Y3p0bE9tWnZjaWc3WVNFOVBXNTFiR3c3S1h0'
    || 'emQybDBZMmdvWVM1MFlXY3BlMk5oYzJVZ05UcHFaVDFoTG5OMFlYUmxUbTlrWlN4d2REMGhNVHRpY21WaGF5QmxPMk5oYzJVZ016cHFaVDFoTG5OMFlYUmxU'
    || 'bTlrWlM1amIyNTBZV2x1WlhKSmJtWnZMSEIwUFNFd08ySnlaV0ZySUdVN1kyRnpaU0EwT21wbFBXRXVjM1JoZEdWT2IyUmxMbU52Ym5SaGFXNWxja2x1Wm04'
    || 'c2NIUTlJVEE3WW5KbFlXc2daWDFoUFdFdWNtVjBkWEp1ZldsbUtHcGxQVDA5Ym5Wc2JDbDBhSEp2ZHlCRmNuSnZjaWhqS0RFMk1Da3BPMVZoS0drc2N5eHNL'
    || 'U3hxWlQxdWRXeHNMSEIwUFNFeE8zWmhjaUJtUFd3dVlXeDBaWEp1WVhSbE8yWWhQVDF1ZFd4c0ppWW9aaTV5WlhSMWNtNDliblZzYkNrc2JDNXlaWFIxY200'
    || 'OWJuVnNiSDFqWVhSamFDaG5LWHR3WlNoc0xIUXNaeWw5ZldsbUtIUXVjM1ZpZEhKbFpVWnNZV2R6SmpFeU9EVTBLV1p2Y2loMFBYUXVZMmhwYkdRN2RDRTlQ'
    || 'VzUxYkd3N0tVaGhLSFFzWlNrc2REMTBMbk5wWW14cGJtZDlablZ1WTNScGIyNGdTR0VvWlN4MEtYdDJZWElnYmoxbExtRnNkR1Z5Ym1GMFpTeHlQV1V1Wm14'
    || 'aFozTTdjM2RwZEdOb0tHVXVkR0ZuS1h0allYTmxJREE2WTJGelpTQXhNVHBqWVhObElERTBPbU5oYzJVZ01UVTZhV1lvYUhRb2RDeGxLU3hGZENobEtTeHlK'
    || 'alFwZTNSeWVYdE9jaWd6TEdVc1pTNXlaWFIxY200cExHdHNLRE1zWlNsOVkyRjBZMmdvUkNsN2NHVW9aU3hsTG5KbGRIVnliaXhFS1gxMGNubDdUbklvTlN4'
    || 'bExHVXVjbVYwZFhKdUtYMWpZWFJqYUNoRUtYdHdaU2hsTEdVdWNtVjBkWEp1TEVRcGZYMWljbVZoYXp0allYTmxJREU2YUhRb2RDeGxLU3hGZENobEtTeHlK'
    || 'alV4TWlZbWJpRTlQVzUxYkd3bUpsVnVLRzRzYmk1eVpYUjFjbTRwTzJKeVpXRnJPMk5oYzJVZ05UcHBaaWhvZENoMExHVXBMRVYwS0dVcExISW1OVEV5Smla'
    || 'dUlUMDliblZzYkNZbVZXNG9iaXh1TG5KbGRIVnliaWtzWlM1bWJHRm5jeVl6TWlsN2RtRnlJR3c5WlM1emRHRjBaVTV2WkdVN2RISjVlMGR1S0d3c0lpSXBm'
    || 'V05oZEdOb0tFUXBlM0JsS0dVc1pTNXlaWFIxY200c1JDbDlmV2xtS0hJbU5DWW1LR3c5WlM1emRHRjBaVTV2WkdVc2JDRTliblZzYkNrcGUzWmhjaUJwUFdV'
    || 'dWJXVnRiMmw2WldSUWNtOXdjeXh6UFc0aFBUMXVkV3hzUDI0dWJXVnRiMmw2WldSUWNtOXdjenBwTEdFOVpTNTBlWEJsTEdZOVpTNTFjR1JoZEdWUmRXVjFa'
    || 'VHRwWmlobExuVndaR0YwWlZGMVpYVmxQVzUxYkd3c1ppRTlQVzUxYkd3cGRISjVlMkU5UFQwaWFXNXdkWFFpSmlacExuUjVjR1U5UFQwaWNtRmthVzhpSmla'
    || 'cExtNWhiV1VoUFc1MWJHd21KbTF6S0d3c2FTa3NjMmtvWVN4ektUdDJZWElnWnoxemFTaGhMR2twTzJadmNpaHpQVEE3Y3p4bUxteGxibWQwYUR0ekt6MHlL'
    || 'WHQyWVhJZ1V6MW1XM05kTEdzOVpsdHpLekZkTzFNOVBUMGljM1I1YkdVaVAwVnpLR3dzYXlrNlV6MDlQU0prWVc1blpYSnZkWE5zZVZObGRFbHVibVZ5U0ZS'
    || 'TlRDSS9YM01vYkN4cktUcFRQVDA5SW1Ob2FXeGtjbVZ1SWo5SGJpaHNMR3NwT2xGbEtHd3NVeXhyTEdjcGZYTjNhWFJqYUNoaEtYdGpZWE5sSW1sdWNIVjBJ'
    || 'anB1YVNoc0xHa3BPMkp5WldGck8yTmhjMlVpZEdWNGRHRnlaV0VpT25sektHd3NhU2s3WW5KbFlXczdZMkZ6WlNKelpXeGxZM1FpT25aaGNpQjNQV3d1WDNk'
    || 'eVlYQndaWEpUZEdGMFpTNTNZWE5OZFd4MGFYQnNaVHRzTGw5M2NtRndjR1Z5VTNSaGRHVXVkMkZ6VFhWc2RHbHdiR1U5SVNGcExtMTFiSFJwY0d4bE8zWmhj'
    || 'aUJQUFdrdWRtRnNkV1U3VHlFOWJuVnNiRDk1Ymloc0xDRWhhUzV0ZFd4MGFYQnNaU3hQTENFeEtUcDNJVDA5SVNGcExtMTFiSFJwY0d4bEppWW9hUzVrWlda'
    || 'aGRXeDBWbUZzZFdVaFBXNTFiR3cvZVc0b2JDd2hJV2t1YlhWc2RHbHdiR1VzYVM1a1pXWmhkV3gwVm1Gc2RXVXNJVEFwT25sdUtHd3NJU0ZwTG0xMWJIUnBj'
    || 'R3hsTEdrdWJYVnNkR2x3YkdVL1cxMDZJaUlzSVRFcEtYMXNXMmh5WFQxcGZXTmhkR05vS0VRcGUzQmxLR1VzWlM1eVpYUjFjbTRzUkNsOWZXSnlaV0ZyTzJO'
    || 'aGMyVWdOanBwWmlob2RDaDBMR1VwTEVWMEtHVXBMSEltTkNsN2FXWW9aUzV6ZEdGMFpVNXZaR1U5UFQxdWRXeHNLWFJvY205M0lFVnljbTl5S0dNb01UWXlL'
    || 'U2s3YkQxbExuTjBZWFJsVG05a1pTeHBQV1V1YldWdGIybDZaV1JRY205d2N6dDBjbmw3YkM1dWIyUmxWbUZzZFdVOWFYMWpZWFJqYUNoRUtYdHdaU2hsTEdV'
    || 'dWNtVjBkWEp1TEVRcGZYMWljbVZoYXp0allYTmxJRE02YVdZb2FIUW9kQ3hsS1N4RmRDaGxLU3h5SmpRbUptNGhQVDF1ZFd4c0ppWnVMbTFsYlc5cGVtVmtV'
    || 'M1JoZEdVdWFYTkVaV2g1WkhKaGRHVmtLWFJ5ZVh0eWNpaDBMbU52Ym5SaGFXNWxja2x1Wm04cGZXTmhkR05vS0VRcGUzQmxLR1VzWlM1eVpYUjFjbTRzUkNs'
    || 'OVluSmxZV3M3WTJGelpTQTBPbWgwS0hRc1pTa3NSWFFvWlNrN1luSmxZV3M3WTJGelpTQXhNenBvZENoMExHVXBMRVYwS0dVcExHdzlaUzVqYUdsc1pDeHNM'
    || 'bVpzWVdkekpqZ3hPVEltSmlocFBXd3ViV1Z0YjJsNlpXUlRkR0YwWlNFOVBXNTFiR3dzYkM1emRHRjBaVTV2WkdVdWFYTklhV1JrWlc0OWFTd2hhWHg4YkM1'
    || 'aGJIUmxjbTVoZEdVaFBUMXVkV3hzSmlac0xtRnNkR1Z5Ym1GMFpTNXRaVzF2YVhwbFpGTjBZWFJsSVQwOWJuVnNiSHg4S0VsdlBXaGxLQ2twS1N4eUpqUW1K'
    || 'aVJoS0dVcE8ySnlaV0ZyTzJOaGMyVWdNakk2YVdZb1V6MXVJVDA5Ym5Wc2JDWW1iaTV0WlcxdmFYcGxaRk4wWVhSbElUMDliblZzYkN4bExtMXZaR1VtTVQ4'
    || 'b1QyVTlLR2M5VDJVcGZIeFRMR2gwS0hRc1pTa3NUMlU5WnlrNmFIUW9kQ3hsS1N4RmRDaGxLU3h5SmpneE9USXBlMmxtS0djOVpTNXRaVzF2YVhwbFpGTjBZ'
    || 'WFJsSVQwOWJuVnNiQ3dvWlM1emRHRjBaVTV2WkdVdWFYTklhV1JrWlc0OVp5a21KaUZUSmlZb1pTNXRiMlJsSmpFcElUMDlNQ2xtYjNJb1VEMWxMRk05WlM1'
    || 'amFHbHNaRHRUSVQwOWJuVnNiRHNwZTJadmNpaHJQVkE5VXp0UUlUMDliblZzYkRzcGUzTjNhWFJqYUNoM1BWQXNUejEzTG1Ob2FXeGtMSGN1ZEdGbktYdGpZ'
    || 'WE5sSURBNlkyRnpaU0F4TVRwallYTmxJREUwT21OaGMyVWdNVFU2VG5Jb05DeDNMSGN1Y21WMGRYSnVLVHRpY21WaGF6dGpZWE5sSURFNlZXNG9keXgzTG5K'
    || 'bGRIVnliaWs3ZG1GeUlFazlkeTV6ZEdGMFpVNXZaR1U3YVdZb2RIbHdaVzltSUVrdVkyOXRjRzl1Wlc1MFYybHNiRlZ1Ylc5MWJuUTlQU0ptZFc1amRHbHZi'
    || 'aUlwZTNJOWR5eHVQWGN1Y21WMGRYSnVPM1J5ZVh0MFBYSXNTUzV3Y205d2N6MTBMbTFsYlc5cGVtVmtVSEp2Y0hNc1NTNXpkR0YwWlQxMExtMWxiVzlwZW1W'
    || 'a1UzUmhkR1VzU1M1amIyMXdiMjVsYm5SWGFXeHNWVzV0YjNWdWRDZ3BmV05oZEdOb0tFUXBlM0JsS0hJc2JpeEVLWDE5WW5KbFlXczdZMkZ6WlNBMU9sVnVL'
    || 'SGNzZHk1eVpYUjFjbTRwTzJKeVpXRnJPMk5oYzJVZ01qSTZhV1lvZHk1dFpXMXZhWHBsWkZOMFlYUmxJVDA5Ym5Wc2JDbDdRbUVvYXlrN1kyOXVkR2x1ZFdW'
    || 'OWZVOGhQVDF1ZFd4c1B5aFBMbkpsZEhWeWJqMTNMRkE5VHlrNlFtRW9heWw5VXoxVExuTnBZbXhwYm1kOVpUcG1iM0lvVXoxdWRXeHNMR3M5WlRzN0tYdHBa'
    || 'aWhyTG5SaFp6MDlQVFVwZTJsbUtGTTlQVDF1ZFd4c0tYdFRQV3M3ZEhKNWUydzlheTV6ZEdGMFpVNXZaR1VzWno4b2FUMXNMbk4wZVd4bExIUjVjR1Z2WmlC'
    || 'cExuTmxkRkJ5YjNCbGNuUjVQVDBpWm5WdVkzUnBiMjRpUDJrdWMyVjBVSEp2Y0dWeWRIa29JbVJwYzNCc1lYa2lMQ0p1YjI1bElpd2lhVzF3YjNKMFlXNTBJ'
    || 'aWs2YVM1a2FYTndiR0Y1UFNKdWIyNWxJaWs2S0dFOWF5NXpkR0YwWlU1dlpHVXNaajFyTG0xbGJXOXBlbVZrVUhKdmNITXVjM1I1YkdVc2N6MW1JVDF1ZFd4'
    || 'c0ppWm1MbWhoYzA5M2JsQnliM0JsY25SNUtDSmthWE53YkdGNUlpay9aaTVrYVhOd2JHRjVPbTUxYkd3c1lTNXpkSGxzWlM1a2FYTndiR0Y1UFZOektDSmth'
    || 'WE53YkdGNUlpeHpLU2w5WTJGMFkyZ29SQ2w3Y0dVb1pTeGxMbkpsZEhWeWJpeEVLWDE5ZldWc2MyVWdhV1lvYXk1MFlXYzlQVDAyS1h0cFppaFRQVDA5Ym5W'
    || 'c2JDbDBjbmw3YXk1emRHRjBaVTV2WkdVdWJtOWtaVlpoYkhWbFBXYy9JaUk2YXk1dFpXMXZhWHBsWkZCeWIzQnpmV05oZEdOb0tFUXBlM0JsS0dVc1pTNXla'
    || 'WFIxY200c1JDbDlmV1ZzYzJVZ2FXWW9LR3N1ZEdGbklUMDlNakltSm1zdWRHRm5JVDA5TWpOOGZHc3ViV1Z0YjJsNlpXUlRkR0YwWlQwOVBXNTFiR3g4Zkdz'
    || 'OVBUMWxLU1ltYXk1amFHbHNaQ0U5UFc1MWJHd3BlMnN1WTJocGJHUXVjbVYwZFhKdVBXc3NhejFyTG1Ob2FXeGtPMk52Ym5ScGJuVmxmV2xtS0dzOVBUMWxL'
    || 'V0p5WldGcklHVTdabTl5S0R0ckxuTnBZbXhwYm1jOVBUMXVkV3hzT3lsN2FXWW9heTV5WlhSMWNtNDlQVDF1ZFd4c2ZIeHJMbkpsZEhWeWJqMDlQV1VwWW5K'
    || 'bFlXc2daVHRUUFQwOWF5WW1LRk05Ym5Wc2JDa3NhejFyTG5KbGRIVnlibjFUUFQwOWF5WW1LRk05Ym5Wc2JDa3NheTV6YVdKc2FXNW5MbkpsZEhWeWJqMXJM'
    || 'bkpsZEhWeWJpeHJQV3N1YzJsaWJHbHVaMzE5WW5KbFlXczdZMkZ6WlNBeE9UcG9kQ2gwTEdVcExFVjBLR1VwTEhJbU5DWW1KR0VvWlNrN1luSmxZV3M3WTJG'
    || 'elpTQXlNVHBpY21WaGF6dGtaV1poZFd4ME9taDBLSFFzWlNrc1JYUW9aU2w5ZldaMWJtTjBhVzl1SUVWMEtHVXBlM1poY2lCMFBXVXVabXhoWjNNN2FXWW9k'
    || 'Q1l5S1h0MGNubDdaVHA3Wm05eUtIWmhjaUJ1UFdVdWNtVjBkWEp1TzI0aFBUMXVkV3hzT3lsN2FXWW9SbUVvYmlrcGUzWmhjaUJ5UFc0N1luSmxZV3NnWlgx'
    || 'dVBXNHVjbVYwZFhKdWZYUm9jbTkzSUVWeWNtOXlLR01vTVRZd0tTbDljM2RwZEdOb0tISXVkR0ZuS1h0allYTmxJRFU2ZG1GeUlHdzljaTV6ZEdGMFpVNXZa'
    || 'R1U3Y2k1bWJHRm5jeVl6TWlZbUtFZHVLR3dzSWlJcExISXVabXhoWjNNbVBTMHpNeWs3ZG1GeUlHazlRV0VvWlNrN1QyOG9aU3hwTEd3cE8ySnlaV0ZyTzJO'
    || 'aGMyVWdNenBqWVhObElEUTZkbUZ5SUhNOWNpNXpkR0YwWlU1dlpHVXVZMjl1ZEdGcGJtVnlTVzVtYnl4aFBVRmhLR1VwTzB4dktHVXNZU3h6S1R0aWNtVmhh'
    || 'enRrWldaaGRXeDBPblJvY205M0lFVnljbTl5S0dNb01UWXhLU2w5ZldOaGRHTm9LR1lwZTNCbEtHVXNaUzV5WlhSMWNtNHNaaWw5WlM1bWJHRm5jeVk5TFRO'
    || 'OWRDWTBNRGsySmlZb1pTNW1iR0ZuY3lZOUxUUXdPVGNwZldaMWJtTjBhVzl1SUVabUtHVXNkQ3h1S1h0UVBXVXNWbUVvWlNsOVpuVnVZM1JwYjI0Z1ZtRW9a'
    || 'U3gwTEc0cGUyWnZjaWgyWVhJZ2NqMG9aUzV0YjJSbEpqRXBJVDA5TUR0UUlUMDliblZzYkRzcGUzWmhjaUJzUFZBc2FUMXNMbU5vYVd4a08ybG1LR3d1ZEdG'
    || 'blBUMDlNakltSm5JcGUzWmhjaUJ6UFd3dWJXVnRiMmw2WldSVGRHRjBaU0U5UFc1MWJHeDhmRVZzTzJsbUtDRnpLWHQyWVhJZ1lUMXNMbUZzZEdWeWJtRjBa'
    || 'U3htUFdFaFBUMXVkV3hzSmlaaExtMWxiVzlwZW1Wa1UzUmhkR1VoUFQxdWRXeHNmSHhQWlR0aFBVVnNPM1poY2lCblBVOWxPMmxtS0VWc1BYTXNLRTlsUFdZ'
    || 'cEppWWhaeWxtYjNJb1VEMXNPMUFoUFQxdWRXeHNPeWx6UFZBc1pqMXpMbU5vYVd4a0xITXVkR0ZuUFQwOU1qSW1Kbk11YldWdGIybDZaV1JUZEdGMFpTRTlQ'
    || 'VzUxYkd3L1VXRW9iQ2s2WmlFOVBXNTFiR3cvS0dZdWNtVjBkWEp1UFhNc1VEMW1LVHBSWVNoc0tUdG1iM0lvTzJraFBUMXVkV3hzT3lsUVBXa3NWbUVvYVNr'
    || 'c2FUMXBMbk5wWW14cGJtYzdVRDFzTEVWc1BXRXNUMlU5WjMxWFlTaGxLWDFsYkhObEtHd3VjM1ZpZEhKbFpVWnNZV2R6SmpnM056SXBJVDA5TUNZbWFTRTlQ'
    || 'VzUxYkd3L0tHa3VjbVYwZFhKdVBXd3NVRDFwS1RwWFlTaGxLWDE5Wm5WdVkzUnBiMjRnVjJFb1pTbDdabTl5S0R0UUlUMDliblZzYkRzcGUzWmhjaUIwUFZB'
    || 'N2FXWW9LSFF1Wm14aFozTW1PRGMzTWlraFBUMHdLWHQyWVhJZ2JqMTBMbUZzZEdWeWJtRjBaVHQwY25sN2FXWW9LSFF1Wm14aFozTW1PRGMzTWlraFBUMHdL'
    || 'WE4zYVhSamFDaDBMblJoWnlsN1kyRnpaU0F3T21OaGMyVWdNVEU2WTJGelpTQXhOVHBQWlh4OGEyd29OU3gwS1R0aWNtVmhhenRqWVhObElERTZkbUZ5SUhJ'
    || 'OWRDNXpkR0YwWlU1dlpHVTdhV1lvZEM1bWJHRm5jeVkwSmlZaFQyVXBhV1lvYmowOVBXNTFiR3dwY2k1amIyMXdiMjVsYm5SRWFXUk5iM1Z1ZENncE8yVnNj'
    || 'MlY3ZG1GeUlHdzlkQzVsYkdWdFpXNTBWSGx3WlQwOVBYUXVkSGx3WlQ5dUxtMWxiVzlwZW1Wa1VISnZjSE02Wm5Rb2RDNTBlWEJsTEc0dWJXVnRiMmw2WldS'
    || 'UWNtOXdjeWs3Y2k1amIyMXdiMjVsYm5SRWFXUlZjR1JoZEdVb2JDeHVMbTFsYlc5cGVtVmtVM1JoZEdVc2NpNWZYM0psWVdOMFNXNTBaWEp1WVd4VGJtRndj'
    || 'Mmh2ZEVKbFptOXlaVlZ3WkdGMFpTbDlkbUZ5SUdrOWRDNTFjR1JoZEdWUmRXVjFaVHRwSVQwOWJuVnNiQ1ltUW5Vb2RDeHBMSElwTzJKeVpXRnJPMk5oYzJV'
    || 'Z016cDJZWElnY3oxMExuVndaR0YwWlZGMVpYVmxPMmxtS0hNaFBUMXVkV3hzS1h0cFppaHVQVzUxYkd3c2RDNWphR2xzWkNFOVBXNTFiR3dwYzNkcGRHTm9L'
    || 'SFF1WTJocGJHUXVkR0ZuS1h0allYTmxJRFU2YmoxMExtTm9hV3hrTG5OMFlYUmxUbTlrWlR0aWNtVmhhenRqWVhObElERTZiajEwTG1Ob2FXeGtMbk4wWVhS'
    || 'bFRtOWtaWDFDZFNoMExITXNiaWw5WW5KbFlXczdZMkZ6WlNBMU9uWmhjaUJoUFhRdWMzUmhkR1ZPYjJSbE8ybG1LRzQ5UFQxdWRXeHNKaVowTG1ac1lXZHpK'
    || 'alFwZTI0OVlUdDJZWElnWmoxMExtMWxiVzlwZW1Wa1VISnZjSE03YzNkcGRHTm9LSFF1ZEhsd1pTbDdZMkZ6WlNKaWRYUjBiMjRpT21OaGMyVWlhVzV3ZFhR'
    || 'aU9tTmhjMlVpYzJWc1pXTjBJanBqWVhObEluUmxlSFJoY21WaElqcG1MbUYxZEc5R2IyTjFjeVltYmk1bWIyTjFjeWdwTzJKeVpXRnJPMk5oYzJVaWFXMW5J'
    || 'anBtTG5OeVl5WW1LRzR1YzNKalBXWXVjM0pqS1gxOVluSmxZV3M3WTJGelpTQTJPbUp5WldGck8yTmhjMlVnTkRwaWNtVmhhenRqWVhObElERXlPbUp5WldG'
    || 'ck8yTmhjMlVnTVRNNmFXWW9kQzV0WlcxdmFYcGxaRk4wWVhSbFBUMDliblZzYkNsN2RtRnlJR2M5ZEM1aGJIUmxjbTVoZEdVN2FXWW9aeUU5UFc1MWJHd3Bl'
    || 'M1poY2lCVFBXY3ViV1Z0YjJsNlpXUlRkR0YwWlR0cFppaFRJVDA5Ym5Wc2JDbDdkbUZ5SUdzOVV5NWtaV2g1WkhKaGRHVmtPMnNoUFQxdWRXeHNKaVp5Y2lo'
    || 'cktYMTlmV0p5WldGck8yTmhjMlVnTVRrNlkyRnpaU0F4TnpwallYTmxJREl4T21OaGMyVWdNakk2WTJGelpTQXlNenBqWVhObElESTFPbUp5WldGck8yUmxa'
    || 'bUYxYkhRNmRHaHliM2NnUlhKeWIzSW9ZeWd4TmpNcEtYMVBaWHg4ZEM1bWJHRm5jeVkxTVRJbUpsSnZLSFFwZldOaGRHTm9LSGNwZTNCbEtIUXNkQzV5WlhS'
    || 'MWNtNHNkeWw5ZldsbUtIUTlQVDFsS1h0UVBXNTFiR3c3WW5KbFlXdDlhV1lvYmoxMExuTnBZbXhwYm1jc2JpRTlQVzUxYkd3cGUyNHVjbVYwZFhKdVBYUXVj'
    || 'bVYwZFhKdUxGQTlianRpY21WaGEzMVFQWFF1Y21WMGRYSnVmWDFtZFc1amRHbHZiaUJDWVNobEtYdG1iM0lvTzFBaFBUMXVkV3hzT3lsN2RtRnlJSFE5VUR0'
    || 'cFppaDBQVDA5WlNsN1VEMXVkV3hzTzJKeVpXRnJmWFpoY2lCdVBYUXVjMmxpYkdsdVp6dHBaaWh1SVQwOWJuVnNiQ2w3Ymk1eVpYUjFjbTQ5ZEM1eVpYUjFj'
    || 'bTRzVUQxdU8ySnlaV0ZyZlZBOWRDNXlaWFIxY201OWZXWjFibU4wYVc5dUlGRmhLR1VwZTJadmNpZzdVQ0U5UFc1MWJHdzdLWHQyWVhJZ2REMVFPM1J5ZVh0'
    || 'emQybDBZMmdvZEM1MFlXY3BlMk5oYzJVZ01EcGpZWE5sSURFeE9tTmhjMlVnTVRVNmRtRnlJRzQ5ZEM1eVpYUjFjbTQ3ZEhKNWUydHNLRFFzZENsOVkyRjBZ'
    || 'MmdvWmlsN2NHVW9kQ3h1TEdZcGZXSnlaV0ZyTzJOaGMyVWdNVHAyWVhJZ2NqMTBMbk4wWVhSbFRtOWtaVHRwWmloMGVYQmxiMllnY2k1amIyMXdiMjVsYm5S'
    || 'RWFXUk5iM1Z1ZEQwOUltWjFibU4wYVc5dUlpbDdkbUZ5SUd3OWRDNXlaWFIxY200N2RISjVlM0l1WTI5dGNHOXVaVzUwUkdsa1RXOTFiblFvS1gxallYUmph'
    || 'Q2htS1h0d1pTaDBMR3dzWmlsOWZYWmhjaUJwUFhRdWNtVjBkWEp1TzNSeWVYdFNieWgwS1gxallYUmphQ2htS1h0d1pTaDBMR2tzWmlsOVluSmxZV3M3WTJG'
    || 'elpTQTFPblpoY2lCelBYUXVjbVYwZFhKdU8zUnllWHRTYnloMEtYMWpZWFJqYUNobUtYdHdaU2gwTEhNc1ppbDlmWDFqWVhSamFDaG1LWHR3WlNoMExIUXVj'
    || 'bVYwZFhKdUxHWXBmV2xtS0hROVBUMWxLWHRRUFc1MWJHdzdZbkpsWVd0OWRtRnlJR0U5ZEM1emFXSnNhVzVuTzJsbUtHRWhQVDF1ZFd4c0tYdGhMbkpsZEhW'
    || 'eWJqMTBMbkpsZEhWeWJpeFFQV0U3WW5KbFlXdDlVRDEwTG5KbGRIVnlibjE5ZG1GeUlFRm1QVTFoZEdndVkyVnBiQ3hPYkQxblpTNVNaV0ZqZEVOMWNuSmxi'
    || 'blJFYVhOd1lYUmphR1Z5TEZCdlBXZGxMbEpsWVdOMFEzVnljbVZ1ZEU5M2JtVnlMR3gwUFdkbExsSmxZV04wUTNWeWNtVnVkRUpoZEdOb1EyOXVabWxuTEVz'
    || 'OU1DeFRaVDF1ZFd4c0xIWmxQVzUxYkd3c1EyVTlNQ3h4WlQwd0xDUnVQVmQwS0RBcExIaGxQVEFzYW5JOWJuVnNiQ3hrYmowd0xHcHNQVEFzVFc4OU1DeERj'
    || 'ajF1ZFd4c0xFaGxQVzUxYkd3c1NXODlNQ3hJYmoweEx6QXNVSFE5Ym5Wc2JDeERiRDBoTVN4RWJ6MXVkV3hzTEZoMFBXNTFiR3dzVkd3OUlURXNXblE5Ym5W'
    || 'c2JDeFNiRDB3TEZSeVBUQXNlbTg5Ym5Wc2JDeE1iRDB0TVN4UGJEMHdPMloxYm1OMGFXOXVJRWxsS0NsN2NtVjBkWEp1S0VzbU5pa2hQVDB3UDJobEtDazZU'
    || 'R3doUFQwdE1UOU1iRHBNYkQxb1pTZ3BmV1oxYm1OMGFXOXVJSEYwS0dVcGUzSmxkSFZ5YmlobExtMXZaR1VtTVNrOVBUMHdQekU2S0VzbU1pa2hQVDB3Smla'
    || 'RFpTRTlQVEEvUTJVbUxVTmxPbDltTG5SeVlXNXphWFJwYjI0aFBUMXVkV3hzUHloUGJEMDlQVEFtSmloUGJEMUJjeWdwS1N4UGJDazZLR1U5ZEdVc1pTRTlQ'
    || 'VEI4ZkNobFBYZHBibVJ2ZHk1bGRtVnVkQ3hsUFdVOVBUMTJiMmxrSURBL01UWTZTM01vWlM1MGVYQmxLU2tzWlNsOVpuVnVZM1JwYjI0Z2JYUW9aU3gwTEc0'
    || 'c2NpbDdhV1lvTlRBOFZISXBkR2h5YjNjZ1ZISTlNQ3g2YnoxdWRXeHNMRVZ5Y205eUtHTW9NVGcxS1NrN1NtNG9aU3h1TEhJcExDZ29TeVl5S1QwOVBUQjhm'
    || 'R1VoUFQxVFpTa21KaWhsUFQwOVUyVW1KaWdvU3lZeUtUMDlQVEFtSmlocWJIdzliaWtzZUdVOVBUMDBKaVpLZENobExFTmxLU2tzVm1Vb1pTeHlLU3h1UFQw'
    || 'OU1TWW1TejA5UFRBbUppaDBMbTF2WkdVbU1TazlQVDB3SmlZb1NHNDlhR1VvS1NzMU1EQXNhV3dtSmxGMEtDa3BLWDFtZFc1amRHbHZiaUJXWlNobExIUXBl'
    || 'M1poY2lCdVBXVXVZMkZzYkdKaFkydE9iMlJsTzNka0tHVXNkQ2s3ZG1GeUlISTlKSElvWlN4bFBUMDlVMlUvUTJVNk1DazdhV1lvY2owOVBUQXBiaUU5UFc1'
    || 'MWJHd21Ka1J6S0c0cExHVXVZMkZzYkdKaFkydE9iMlJsUFc1MWJHd3NaUzVqWVd4c1ltRmphMUJ5YVc5eWFYUjVQVEE3Wld4elpTQnBaaWgwUFhJbUxYSXNa'
    || 'UzVqWVd4c1ltRmphMUJ5YVc5eWFYUjVJVDA5ZENsN2FXWW9iaUU5Ym5Wc2JDWW1SSE1vYmlrc2REMDlQVEVwWlM1MFlXYzlQVDB3UDNkbUtFdGhMbUpwYm1R'
    || 'b2JuVnNiQ3hsS1NrNlVIVW9TMkV1WW1sdVpDaHVkV3hzTEdVcEtTeDJaaWhtZFc1amRHbHZiaWdwZXloTEpqWXBQVDA5TUNZbVVYUW9LWDBwTEc0OWJuVnNi'
    || 'RHRsYkhObGUzTjNhWFJqYUNoVmN5aHlLU2w3WTJGelpTQXhPbTQ5YUdrN1luSmxZV3M3WTJGelpTQTBPbTQ5ZW5NN1luSmxZV3M3WTJGelpTQXhOanB1UFhw'
    || 'eU8ySnlaV0ZyTzJOaGMyVWdOVE0yT0Rjd09URXlPbTQ5Um5NN1luSmxZV3M3WkdWbVlYVnNkRHB1UFhweWZXNDlkR01vYml4SFlTNWlhVzVrS0c1MWJHd3Na'
    || 'U2twZldVdVkyRnNiR0poWTJ0UWNtbHZjbWwwZVQxMExHVXVZMkZzYkdKaFkydE9iMlJsUFc1OWZXWjFibU4wYVc5dUlFZGhLR1VzZENsN2FXWW9UR3c5TFRF'
    || 'c1QydzlNQ3dvU3lZMktTRTlQVEFwZEdoeWIzY2dSWEp5YjNJb1l5Z3pNamNwS1R0MllYSWdiajFsTG1OaGJHeGlZV05yVG05a1pUdHBaaWhXYmlncEppWmxM'
    || 'bU5oYkd4aVlXTnJUbTlrWlNFOVBXNHBjbVYwZFhKdUlHNTFiR3c3ZG1GeUlISTlKSElvWlN4bFBUMDlVMlUvUTJVNk1DazdhV1lvY2owOVBUQXBjbVYwZFhK'
    || 'dUlHNTFiR3c3YVdZb0tISW1NekFwSVQwOU1IeDhLSEltWlM1bGVIQnBjbVZrVEdGdVpYTXBJVDA5TUh4OGRDbDBQVkJzS0dVc2NpazdaV3h6Wlh0MFBYSTdk'
    || 'bUZ5SUd3OVN6dExmRDB5TzNaaGNpQnBQVmhoS0NrN0tGTmxJVDA5Wlh4OFEyVWhQVDEwS1NZbUtGQjBQVzUxYkd3c1NHNDlhR1VvS1NzMU1EQXNjRzRvWlN4'
    || 'MEtTazdaRzhnZEhKNWUwaG1LQ2s3WW5KbFlXdDlZMkYwWTJnb1lTbDdXV0VvWlN4aEtYMTNhR2xzWlNnaE1DazdZbWtvS1N4T2JDNWpkWEp5Wlc1MFBXa3NT'
    || 'ejFzTEhabElUMDliblZzYkQ5MFBUQTZLRk5sUFc1MWJHd3NRMlU5TUN4MFBYaGxLWDFwWmloMElUMDlNQ2w3YVdZb2REMDlQVEltSmloc1BXMXBLR1VwTEd3'
    || 'aFBUMHdKaVlvY2oxc0xIUTlSbThvWlN4c0tTa3BMSFE5UFQweEtYUm9jbTkzSUc0OWFuSXNjRzRvWlN3d0tTeEtkQ2hsTEhJcExGWmxLR1VzYUdVb0tTa3Ni'
    || 'anRwWmloMFBUMDlOaWxLZENobExISXBPMlZzYzJWN2FXWW9iRDFsTG1OMWNuSmxiblF1WVd4MFpYSnVZWFJsTENoeUpqTXdLVDA5UFRBbUppRlZaaWhzS1NZ'
    || 'bUtIUTlVR3dvWlN4eUtTeDBQVDA5TWlZbUtHazliV2tvWlNrc2FTRTlQVEFtSmloeVBXa3NkRDFHYnlobExHa3BLU2tzZEQwOVBURXBLWFJvY205M0lHNDlh'
    || 'bklzY0c0b1pTd3dLU3hLZENobExISXBMRlpsS0dVc2FHVW9LU2tzYmp0emQybDBZMmdvWlM1bWFXNXBjMmhsWkZkdmNtczliQ3hsTG1acGJtbHphR1ZrVEdG'
    || 'dVpYTTljaXgwS1h0allYTmxJREE2WTJGelpTQXhPblJvY205M0lFVnljbTl5S0dNb016UTFLU2s3WTJGelpTQXlPbWh1S0dVc1NHVXNVSFFwTzJKeVpXRnJP'
    || 'Mk5oYzJVZ016cHBaaWhLZENobExISXBMQ2h5SmpFek1EQXlNelF5TkNrOVBUMXlKaVlvZEQxSmJ5czFNREF0YUdVb0tTd3hNRHgwS1NsN2FXWW9KSElvWlN3'
    || 'd0tTRTlQVEFwWW5KbFlXczdhV1lvYkQxbExuTjFjM0JsYm1SbFpFeGhibVZ6TENoc0puSXBJVDA5Y2lsN1NXVW9LU3hsTG5CcGJtZGxaRXhoYm1WemZEMWxM'
    || 'bk4xYzNCbGJtUmxaRXhoYm1WekptdzdZbkpsWVd0OVpTNTBhVzFsYjNWMFNHRnVaR3hsUFZacEtHaHVMbUpwYm1Rb2JuVnNiQ3hsTEVobExGQjBLU3gwS1R0'
    || 'aWNtVmhhMzFvYmlobExFaGxMRkIwS1R0aWNtVmhhenRqWVhObElEUTZhV1lvU25Rb1pTeHlLU3dvY2lZME1UazBNalF3S1QwOVBYSXBZbkpsWVdzN1ptOXlL'
    || 'SFE5WlM1bGRtVnVkRlJwYldWekxHdzlMVEU3TUR4eU95bDdkbUZ5SUhNOU16RXRZWFFvY2lrN2FUMHhQRHh6TEhNOWRGdHpYU3h6UG13bUppaHNQWE1wTEhJ'
    || 'bVBYNXBmV2xtS0hJOWJDeHlQV2hsS0NrdGNpeHlQU2d4TWpBK2NqOHhNakE2TkRnd1BuSS9ORGd3T2pFd09EQStjajh4TURnd09qRTVNakErY2o4eE9USXdP'
    || 'ak5sTXo1eVB6TmxNem8wTXpJd1BuSS9ORE15TURveE9UWXdLa0ZtS0hJdk1UazJNQ2twTFhJc01UQThjaWw3WlM1MGFXMWxiM1YwU0dGdVpHeGxQVlpwS0do'
    || 'dUxtSnBibVFvYm5Wc2JDeGxMRWhsTEZCMEtTeHlLVHRpY21WaGEzMW9iaWhsTEVobExGQjBLVHRpY21WaGF6dGpZWE5sSURVNmFHNG9aU3hJWlN4UWRDazdZ'
    || 'bkpsWVdzN1pHVm1ZWFZzZERwMGFISnZkeUJGY25KdmNpaGpLRE15T1NrcGZYMTljbVYwZFhKdUlGWmxLR1VzYUdVb0tTa3NaUzVqWVd4c1ltRmphMDV2WkdV'
    || 'OVBUMXVQMGRoTG1KcGJtUW9iblZzYkN4bEtUcHVkV3hzZldaMWJtTjBhVzl1SUVadktHVXNkQ2w3ZG1GeUlHNDlRM0k3Y21WMGRYSnVJR1V1WTNWeWNtVnVk'
    || 'QzV0WlcxdmFYcGxaRk4wWVhSbExtbHpSR1ZvZVdSeVlYUmxaQ1ltS0hCdUtHVXNkQ2t1Wm14aFozTjhQVEkxTmlrc1pUMVFiQ2hsTEhRcExHVWhQVDB5SmlZ'
    || 'b2REMUlaU3hJWlQxdUxIUWhQVDF1ZFd4c0ppWkJieWgwS1Nrc1pYMW1kVzVqZEdsdmJpQkJieWhsS1h0SVpUMDlQVzUxYkd3L1NHVTlaVHBJWlM1d2RYTm9M'
    || 'bUZ3Y0d4NUtFaGxMR1VwZldaMWJtTjBhVzl1SUZWbUtHVXBlMlp2Y2loMllYSWdkRDFsT3pzcGUybG1LSFF1Wm14aFozTW1NVFl6T0RRcGUzWmhjaUJ1UFhR'
    || 'dWRYQmtZWFJsVVhWbGRXVTdhV1lvYmlFOVBXNTFiR3dtSmlodVBXNHVjM1J2Y21WekxHNGhQVDF1ZFd4c0tTbG1iM0lvZG1GeUlISTlNRHR5UEc0dWJHVnVa'
    || 'M1JvTzNJckt5bDdkbUZ5SUd3OWJsdHlYU3hwUFd3dVoyVjBVMjVoY0hOb2IzUTdiRDFzTG5aaGJIVmxPM1J5ZVh0cFppZ2hZM1FvYVNncExHd3BLWEpsZEhW'
    || 'eWJpRXhmV05oZEdOb2UzSmxkSFZ5YmlFeGZYMTlhV1lvYmoxMExtTm9hV3hrTEhRdWMzVmlkSEpsWlVac1lXZHpKakUyTXpnMEppWnVJVDA5Ym5Wc2JDbHVM'
    || 'bkpsZEhWeWJqMTBMSFE5Ymp0bGJITmxlMmxtS0hROVBUMWxLV0p5WldGck8yWnZjaWc3ZEM1emFXSnNhVzVuUFQwOWJuVnNiRHNwZTJsbUtIUXVjbVYwZFhK'
    || 'dVBUMDliblZzYkh4OGRDNXlaWFIxY200OVBUMWxLWEpsZEhWeWJpRXdPM1E5ZEM1eVpYUjFjbTU5ZEM1emFXSnNhVzVuTG5KbGRIVnliajEwTG5KbGRIVnli'
    || 'aXgwUFhRdWMybGliR2x1WjMxOWNtVjBkWEp1SVRCOVpuVnVZM1JwYjI0Z1NuUW9aU3gwS1h0bWIzSW9kQ1k5ZmsxdkxIUW1QWDVxYkN4bExuTjFjM0JsYm1S'
    || 'bFpFeGhibVZ6ZkQxMExHVXVjR2x1WjJWa1RHRnVaWE1tUFg1MExHVTlaUzVsZUhCcGNtRjBhVzl1VkdsdFpYTTdNRHgwT3lsN2RtRnlJRzQ5TXpFdFlYUW9k'
    || 'Q2tzY2oweFBEeHVPMlZiYmwwOUxURXNkQ1k5Zm5KOWZXWjFibU4wYVc5dUlFdGhLR1VwZTJsbUtDaExKallwSVQwOU1DbDBhSEp2ZHlCRmNuSnZjaWhqS0RN'
    || 'eU55a3BPMVp1S0NrN2RtRnlJSFE5SkhJb1pTd3dLVHRwWmlnb2RDWXhLVDA5UFRBcGNtVjBkWEp1SUZabEtHVXNhR1VvS1Nrc2JuVnNiRHQyWVhJZ2JqMVFi'
    || 'Q2hsTEhRcE8ybG1LR1V1ZEdGbklUMDlNQ1ltYmowOVBUSXBlM1poY2lCeVBXMXBLR1VwTzNJaFBUMHdKaVlvZEQxeUxHNDlSbThvWlN4eUtTbDlhV1lvYmow'
    || 'OVBURXBkR2h5YjNjZ2JqMXFjaXh3YmlobExEQXBMRXAwS0dVc2RDa3NWbVVvWlN4b1pTZ3BLU3h1TzJsbUtHNDlQVDAyS1hSb2NtOTNJRVZ5Y205eUtHTW9N'
    || 'elExS1NrN2NtVjBkWEp1SUdVdVptbHVhWE5vWldSWGIzSnJQV1V1WTNWeWNtVnVkQzVoYkhSbGNtNWhkR1VzWlM1bWFXNXBjMmhsWkV4aGJtVnpQWFFzYUc0'
    || 'b1pTeElaU3hRZENrc1ZtVW9aU3hvWlNncEtTeHVkV3hzZldaMWJtTjBhVzl1SUZWdktHVXNkQ2w3ZG1GeUlHNDlTenRMZkQweE8zUnllWHR5WlhSMWNtNGda'
    || 'U2gwS1gxbWFXNWhiR3g1ZTBzOWJpeExQVDA5TUNZbUtFaHVQV2hsS0Nrck5UQXdMR2xzSmlaUmRDZ3BLWDE5Wm5WdVkzUnBiMjRnWm00b1pTbDdXblFoUFQx'
    || 'dWRXeHNKaVphZEM1MFlXYzlQVDB3SmlZb1N5WTJLVDA5UFRBbUpsWnVLQ2s3ZG1GeUlIUTlTenRMZkQweE8zWmhjaUJ1UFd4MExuUnlZVzV6YVhScGIyNHNj'
    || 'ajEwWlR0MGNubDdhV1lvYkhRdWRISmhibk5wZEdsdmJqMXVkV3hzTEhSbFBURXNaU2x5WlhSMWNtNGdaU2dwZldacGJtRnNiSGw3ZEdVOWNpeHNkQzUwY21G'
    || 'dWMybDBhVzl1UFc0c1N6MTBMQ2hMSmpZcFBUMDlNQ1ltVVhRb0tYMTlablZ1WTNScGIyNGdKRzhvS1h0eFpUMGtiaTVqZFhKeVpXNTBMR2xsS0NSdUtYMW1k'
    || 'VzVqZEdsdmJpQndiaWhsTEhRcGUyVXVabWx1YVhOb1pXUlhiM0pyUFc1MWJHd3NaUzVtYVc1cGMyaGxaRXhoYm1WelBUQTdkbUZ5SUc0OVpTNTBhVzFsYjNW'
    || 'MFNHRnVaR3hsTzJsbUtHNGhQVDB0TVNZbUtHVXVkR2x0Wlc5MWRFaGhibVJzWlQwdE1TeHRaaWh1S1Nrc2RtVWhQVDF1ZFd4c0tXWnZjaWh1UFhabExuSmxk'
    || 'SFZ5Ymp0dUlUMDliblZzYkRzcGUzWmhjaUJ5UFc0N2MzZHBkR05vS0ZscEtISXBMSEl1ZEdGbktYdGpZWE5sSURFNmNqMXlMblI1Y0dVdVkyaHBiR1JEYjI1'
    || 'MFpYaDBWSGx3WlhNc2NpRTliblZzYkNZbWNtd29LVHRpY21WaGF6dGpZWE5sSURNNlJtNG9LU3hwWlNoQlpTa3NhV1VvVkdVcExITnZLQ2s3WW5KbFlXczdZ'
    || 'MkZ6WlNBMU9tbHZLSElwTzJKeVpXRnJPMk5oYzJVZ05EcEdiaWdwTzJKeVpXRnJPMk5oYzJVZ01UTTZhV1VvWVdVcE8ySnlaV0ZyTzJOaGMyVWdNVGs2YVdV'
    || 'b1lXVXBPMkp5WldGck8yTmhjMlVnTVRBNlpXOG9jaTUwZVhCbExsOWpiMjUwWlhoMEtUdGljbVZoYXp0allYTmxJREl5T21OaGMyVWdNak02Skc4b0tYMXVQ'
    || 'VzR1Y21WMGRYSnVmV2xtS0ZObFBXVXNkbVU5WlQxaWRDaGxMbU4xY25KbGJuUXNiblZzYkNrc1EyVTljV1U5ZEN4NFpUMHdMR3B5UFc1MWJHd3NUVzg5YW13'
    || 'OVpHNDlNQ3hJWlQxRGNqMXVkV3hzTEhWdUlUMDliblZzYkNsN1ptOXlLSFE5TUR0MFBIVnVMbXhsYm1kMGFEdDBLeXNwYVdZb2JqMTFibHQwWFN4eVBXNHVh'
    || 'VzUwWlhKc1pXRjJaV1FzY2lFOVBXNTFiR3dwZTI0dWFXNTBaWEpzWldGMlpXUTliblZzYkR0MllYSWdiRDF5TG01bGVIUXNhVDF1TG5CbGJtUnBibWM3YVdZ'
    || 'b2FTRTlQVzUxYkd3cGUzWmhjaUJ6UFdrdWJtVjRkRHRwTG01bGVIUTliQ3h5TG01bGVIUTljMzF1TG5CbGJtUnBibWM5Y24xMWJqMXVkV3hzZlhKbGRIVnli'
    || 'aUJsZldaMWJtTjBhVzl1SUZsaEtHVXNkQ2w3Wkc5N2RtRnlJRzQ5ZG1VN2RISjVlMmxtS0dKcEtDa3NiV3d1WTNWeWNtVnVkRDE0YkN4MmJDbDdabTl5S0ha'
    || 'aGNpQnlQV05sTG0xbGJXOXBlbVZrVTNSaGRHVTdjaUU5UFc1MWJHdzdLWHQyWVhJZ2JEMXlMbkYxWlhWbE8yd2hQVDF1ZFd4c0ppWW9iQzV3Wlc1a2FXNW5Q'
    || 'VzUxYkd3cExISTljaTV1WlhoMGZYWnNQU0V4ZldsbUtHTnVQVEFzWDJVOWVXVTlZMlU5Ym5Wc2JDeDNjajBoTVN4ZmNqMHdMRkJ2TG1OMWNuSmxiblE5Ym5W'
    || 'c2JDeHVQVDA5Ym5Wc2JIeDhiaTV5WlhSMWNtNDlQVDF1ZFd4c0tYdDRaVDB4TEdweVBYUXNkbVU5Ym5Wc2JEdGljbVZoYTMxbE9udDJZWElnYVQxbExITTli'
    || 'aTV5WlhSMWNtNHNZVDF1TEdZOWREdHBaaWgwUFVObExHRXVabXhoWjNOOFBUTXlOelk0TEdZaFBUMXVkV3hzSmlaMGVYQmxiMllnWmowOUltOWlhbVZqZENJ'
    || 'bUpuUjVjR1Z2WmlCbUxuUm9aVzQ5UFNKbWRXNWpkR2x2YmlJcGUzWmhjaUJuUFdZc1V6MWhMR3M5VXk1MFlXYzdhV1lvS0ZNdWJXOWtaU1l4S1QwOVBUQW1K'
    || 'aWhyUFQwOU1IeDhhejA5UFRFeGZIeHJQVDA5TVRVcEtYdDJZWElnZHoxVExtRnNkR1Z5Ym1GMFpUdDNQeWhUTG5Wd1pHRjBaVkYxWlhWbFBYY3VkWEJrWVhS'
    || 'bFVYVmxkV1VzVXk1dFpXMXZhWHBsWkZOMFlYUmxQWGN1YldWdGIybDZaV1JUZEdGMFpTeFRMbXhoYm1WelBYY3ViR0Z1WlhNcE9paFRMblZ3WkdGMFpWRjFa'
    || 'WFZsUFc1MWJHd3NVeTV0WlcxdmFYcGxaRk4wWVhSbFBXNTFiR3dwZlhaaGNpQlBQWGhoS0hNcE8ybG1LRThoUFQxdWRXeHNLWHRQTG1ac1lXZHpKajB0TWpV'
    || 'M0xIZGhLRThzY3l4aExHa3NkQ2tzVHk1dGIyUmxKakVtSm5saEtHa3NaeXgwS1N4MFBVOHNaajFuTzNaaGNpQkpQWFF1ZFhCa1lYUmxVWFZsZFdVN2FXWW9T'
    || 'VDA5UFc1MWJHd3BlM1poY2lCRVBXNWxkeUJUWlhRN1JDNWhaR1FvWmlrc2RDNTFjR1JoZEdWUmRXVjFaVDFFZldWc2MyVWdTUzVoWkdRb1ppazdZbkpsWVdz'
    || 'Z1pYMWxiSE5sZTJsbUtDaDBKakVwUFQwOU1DbDdlV0VvYVN4bkxIUXBMRWh2S0NrN1luSmxZV3NnWlgxbVBVVnljbTl5S0dNb05ESTJLU2w5ZldWc2MyVWdh'
    || 'V1lvYzJVbUptRXViVzlrWlNZeEtYdDJZWElnYldVOWVHRW9jeWs3YVdZb2JXVWhQVDF1ZFd4c0tYc29iV1V1Wm14aFozTW1OalUxTXpZcFBUMDlNQ1ltS0cx'
    || 'bExtWnNZV2R6ZkQweU5UWXBMSGRoS0cxbExITXNZU3hwTEhRcExIRnBLRUZ1S0dZc1lTa3BPMkp5WldGcklHVjlmV2s5WmoxQmJpaG1MR0VwTEhobElUMDlO'
    || 'Q1ltS0hobFBUSXBMRU55UFQwOWJuVnNiRDlEY2oxYmFWMDZRM0l1Y0hWemFDaHBLU3hwUFhNN1pHOTdjM2RwZEdOb0tHa3VkR0ZuS1h0allYTmxJRE02YVM1'
    || 'bWJHRm5jM3c5TmpVMU16WXNkQ1k5TFhRc2FTNXNZVzVsYzN3OWREdDJZWElnYlQxMllTaHBMR1lzZENrN1YzVW9hU3h0S1R0aWNtVmhheUJsTzJOaGMyVWdN'
    || 'VHBoUFdZN2RtRnlJSEE5YVM1MGVYQmxMSFk5YVM1emRHRjBaVTV2WkdVN2FXWW9LR2t1Wm14aFozTW1NVEk0S1QwOVBUQW1KaWgwZVhCbGIyWWdjQzVuWlhS'
    || 'RVpYSnBkbVZrVTNSaGRHVkdjbTl0UlhKeWIzSTlQU0ptZFc1amRHbHZiaUo4ZkhZaFBUMXVkV3hzSmlaMGVYQmxiMllnZGk1amIyMXdiMjVsYm5SRWFXUkRZ'
    || 'WFJqYUQwOUltWjFibU4wYVc5dUlpWW1LRmgwUFQwOWJuVnNiSHg4SVZoMExtaGhjeWgyS1NrcEtYdHBMbVpzWVdkemZEMDJOVFV6Tml4MEpqMHRkQ3hwTG14'
    || 'aGJtVnpmRDEwTzNaaGNpQkRQV2RoS0drc1lTeDBLVHRYZFNocExFTXBPMkp5WldGcklHVjlmV2s5YVM1eVpYUjFjbTU5ZDJocGJHVW9hU0U5UFc1MWJHd3Bm'
    || 'WEZoS0c0cGZXTmhkR05vS0hvcGUzUTllaXgyWlQwOVBXNG1KbTRoUFQxdWRXeHNKaVlvZG1VOWJqMXVMbkpsZEhWeWJpazdZMjl1ZEdsdWRXVjlZbkpsWVd0'
    || 'OWQyaHBiR1VvSVRBcGZXWjFibU4wYVc5dUlGaGhLQ2w3ZG1GeUlHVTlUbXd1WTNWeWNtVnVkRHR5WlhSMWNtNGdUbXd1WTNWeWNtVnVkRDE0YkN4bFBUMDli'
    || 'blZzYkQ5NGJEcGxmV1oxYm1OMGFXOXVJRWh2S0NsN0tIaGxQVDA5TUh4OGVHVTlQVDB6Zkh4NFpUMDlQVElwSmlZb2VHVTlOQ2tzVTJVOVBUMXVkV3hzZkh3'
    || 'b1pHNG1Nalk0TkRNMU5EVTFLVDA5UFRBbUppaHFiQ1l5TmpnME16VTBOVFVwUFQwOU1IeDhTblFvVTJVc1EyVXBmV1oxYm1OMGFXOXVJRkJzS0dVc2RDbDdk'
    || 'bUZ5SUc0OVN6dExmRDB5TzNaaGNpQnlQVmhoS0NrN0tGTmxJVDA5Wlh4OFEyVWhQVDEwS1NZbUtGQjBQVzUxYkd3c2NHNG9aU3gwS1NrN1pHOGdkSEo1ZXlS'
    || 'bUtDazdZbkpsWVd0OVkyRjBZMmdvYkNsN1dXRW9aU3hzS1gxM2FHbHNaU2doTUNrN2FXWW9ZbWtvS1N4TFBXNHNUbXd1WTNWeWNtVnVkRDF5TEhabElUMDli'
    || 'blZzYkNsMGFISnZkeUJGY25KdmNpaGpLREkyTVNrcE8zSmxkSFZ5YmlCVFpUMXVkV3hzTEVObFBUQXNlR1Y5Wm5WdVkzUnBiMjRnSkdZb0tYdG1iM0lvTzNa'
    || 'bElUMDliblZzYkRzcFdtRW9kbVVwZldaMWJtTjBhVzl1SUVobUtDbDdabTl5S0R0MlpTRTlQVzUxYkd3bUppRmtaQ2dwT3lsYVlTaDJaU2w5Wm5WdVkzUnBi'
    || 'MjRnV21Fb1pTbDdkbUZ5SUhROVpXTW9aUzVoYkhSbGNtNWhkR1VzWlN4eFpTazdaUzV0WlcxdmFYcGxaRkJ5YjNCelBXVXVjR1Z1WkdsdVoxQnliM0J6TEhR'
    || 'OVBUMXVkV3hzUDNGaEtHVXBPblpsUFhRc1VHOHVZM1Z5Y21WdWREMXVkV3hzZldaMWJtTjBhVzl1SUhGaEtHVXBlM1poY2lCMFBXVTdaRzk3ZG1GeUlHNDlk'
    || 'QzVoYkhSbGNtNWhkR1U3YVdZb1pUMTBMbkpsZEhWeWJpd29kQzVtYkdGbmN5WXpNamMyT0NrOVBUMHdLWHRwWmlodVBVMW1LRzRzZEN4eFpTa3NiaUU5UFc1'
    || 'MWJHd3BlM1psUFc0N2NtVjBkWEp1ZlgxbGJITmxlMmxtS0c0OVNXWW9iaXgwS1N4dUlUMDliblZzYkNsN2JpNW1iR0ZuY3lZOU16STNOamNzZG1VOWJqdHla'
    || 'WFIxY201OWFXWW9aU0U5UFc1MWJHd3BaUzVtYkdGbmMzdzlNekkzTmpnc1pTNXpkV0owY21WbFJteGhaM005TUN4bExtUmxiR1YwYVc5dWN6MXVkV3hzTzJW'
    || 'c2MyVjdlR1U5Tml4MlpUMXVkV3hzTzNKbGRIVnlibjE5YVdZb2REMTBMbk5wWW14cGJtY3NkQ0U5UFc1MWJHd3BlM1psUFhRN2NtVjBkWEp1ZlhabFBYUTla'
    || 'WDEzYUdsc1pTaDBJVDA5Ym5Wc2JDazdlR1U5UFQwd0ppWW9lR1U5TlNsOVpuVnVZM1JwYjI0Z2FHNG9aU3gwTEc0cGUzWmhjaUJ5UFhSbExHdzliSFF1ZEhK'
    || 'aGJuTnBkR2x2Ymp0MGNubDdiSFF1ZEhKaGJuTnBkR2x2YmoxdWRXeHNMSFJsUFRFc1ZtWW9aU3gwTEc0c2NpbDlabWx1WVd4c2VYdHNkQzUwY21GdWMybDBh'
    || 'Vzl1UFd3c2RHVTljbjF5WlhSMWNtNGdiblZzYkgxbWRXNWpkR2x2YmlCV1ppaGxMSFFzYml4eUtYdGtieUJXYmlncE8zZG9hV3hsS0ZwMElUMDliblZzYkNr'
    || 'N2FXWW9LRXNtTmlraFBUMHdLWFJvY205M0lFVnljbTl5S0dNb016STNLU2s3YmoxbExtWnBibWx6YUdWa1YyOXlhenQyWVhJZ2JEMWxMbVpwYm1semFHVmtU'
    || 'R0Z1WlhNN2FXWW9iajA5UFc1MWJHd3BjbVYwZFhKdUlHNTFiR3c3YVdZb1pTNW1hVzVwYzJobFpGZHZjbXM5Ym5Wc2JDeGxMbVpwYm1semFHVmtUR0Z1WlhN'
    || 'OU1DeHVQVDA5WlM1amRYSnlaVzUwS1hSb2NtOTNJRVZ5Y205eUtHTW9NVGMzS1NrN1pTNWpZV3hzWW1GamEwNXZaR1U5Ym5Wc2JDeGxMbU5oYkd4aVlXTnJV'
    || 'SEpwYjNKcGRIazlNRHQyWVhJZ2FUMXVMbXhoYm1WemZHNHVZMmhwYkdSTVlXNWxjenRwWmloZlpDaGxMR2twTEdVOVBUMVRaU1ltS0habFBWTmxQVzUxYkd3'
    || 'c1EyVTlNQ2tzS0c0dWMzVmlkSEpsWlVac1lXZHpKakl3TmpRcFBUMDlNQ1ltS0c0dVpteGhaM01tTWpBMk5DazlQVDB3Zkh4VWJIeDhLRlJzUFNFd0xIUmpL'
    || 'SHB5TEdaMWJtTjBhVzl1S0NsN2NtVjBkWEp1SUZadUtDa3NiblZzYkgwcEtTeHBQU2h1TG1ac1lXZHpKakUxT1Rrd0tTRTlQVEFzS0c0dWMzVmlkSEpsWlVa'
    || 'c1lXZHpKakUxT1Rrd0tTRTlQVEI4ZkdrcGUyazliSFF1ZEhKaGJuTnBkR2x2Yml4c2RDNTBjbUZ1YzJsMGFXOXVQVzUxYkd3N2RtRnlJSE05ZEdVN2RHVTlN'
    || 'VHQyWVhJZ1lUMUxPMHQ4UFRRc1VHOHVZM1Z5Y21WdWREMXVkV3hzTEhwbUtHVXNiaWtzU0dFb2JpeGxLU3gxWmlna2FTa3NWM0k5SVNGVmFTd2thVDFWYVQx'
    || 'dWRXeHNMR1V1WTNWeWNtVnVkRDF1TEVabUtHNHBMR1prS0Nrc1N6MWhMSFJsUFhNc2JIUXVkSEpoYm5OcGRHbHZiajFwZldWc2MyVWdaUzVqZFhKeVpXNTBQ'
    || 'VzQ3YVdZb1ZHd21KaWhVYkQwaE1TeGFkRDFsTEZKc1BXd3BMR2s5WlM1d1pXNWthVzVuVEdGdVpYTXNhVDA5UFRBbUppaFlkRDF1ZFd4c0tTeHRaQ2h1TG5O'
    || 'MFlYUmxUbTlrWlNrc1ZtVW9aU3hvWlNncEtTeDBJVDA5Ym5Wc2JDbG1iM0lvY2oxbExtOXVVbVZqYjNabGNtRmliR1ZGY25KdmNpeHVQVEE3Ymp4MExteGxi'
    || 'bWQwYUR0dUt5c3BiRDEwVzI1ZExISW9iQzUyWVd4MVpTeDdZMjl0Y0c5dVpXNTBVM1JoWTJzNmJDNXpkR0ZqYXl4a2FXZGxjM1E2YkM1a2FXZGxjM1I5S1R0'
    || 'cFppaERiQ2wwYUhKdmR5QkRiRDBoTVN4bFBVUnZMRVJ2UFc1MWJHd3NaVHR5WlhSMWNtNG9VbXdtTVNraFBUMHdKaVpsTG5SaFp5RTlQVEFtSmxadUtDa3Nh'
    || 'VDFsTG5CbGJtUnBibWRNWVc1bGN5d29hU1l4S1NFOVBUQS9aVDA5UFhwdlAxUnlLeXM2S0ZSeVBUQXNlbTg5WlNrNlZISTlNQ3hSZENncExHNTFiR3g5Wm5W'
    || 'dVkzUnBiMjRnVm00b0tYdHBaaWhhZENFOVBXNTFiR3dwZTNaaGNpQmxQVlZ6S0ZKc0tTeDBQV3gwTG5SeVlXNXphWFJwYjI0c2JqMTBaVHQwY25sN2FXWW9i'
    || 'SFF1ZEhKaGJuTnBkR2x2YmoxdWRXeHNMSFJsUFRFMlBtVS9NVFk2WlN4YWREMDlQVzUxYkd3cGRtRnlJSEk5SVRFN1pXeHpaWHRwWmlobFBWcDBMRnAwUFc1'
    || 'MWJHd3NVbXc5TUN3b1N5WTJLU0U5UFRBcGRHaHliM2NnUlhKeWIzSW9ZeWd6TXpFcEtUdDJZWElnYkQxTE8yWnZjaWhMZkQwMExGQTlaUzVqZFhKeVpXNTBP'
    || 'MUFoUFQxdWRXeHNPeWw3ZG1GeUlHazlVQ3h6UFdrdVkyaHBiR1E3YVdZb0tGQXVabXhoWjNNbU1UWXBJVDA5TUNsN2RtRnlJR0U5YVM1a1pXeGxkR2x2Ym5N'
    || 'N2FXWW9ZU0U5UFc1MWJHd3BlMlp2Y2loMllYSWdaajB3TzJZOFlTNXNaVzVuZEdnN1ppc3JLWHQyWVhJZ1p6MWhXMlpkTzJadmNpaFFQV2M3VUNFOVBXNTFi'
    || 'R3c3S1h0MllYSWdVejFRTzNOM2FYUmphQ2hUTG5SaFp5bDdZMkZ6WlNBd09tTmhjMlVnTVRFNlkyRnpaU0F4TlRwT2NpZzRMRk1zYVNsOWRtRnlJR3M5VXk1'
    || 'amFHbHNaRHRwWmlocklUMDliblZzYkNsckxuSmxkSFZ5YmoxVExGQTlhenRsYkhObElHWnZjaWc3VUNFOVBXNTFiR3c3S1h0VFBWQTdkbUZ5SUhjOVV5NXph'
    || 'V0pzYVc1bkxFODlVeTV5WlhSMWNtNDdhV1lvZW1Fb1V5a3NVejA5UFdjcGUxQTliblZzYkR0aWNtVmhhMzFwWmloM0lUMDliblZzYkNsN2R5NXlaWFIxY200'
    || 'OVR5eFFQWGM3WW5KbFlXdDlVRDFQZlgxOWRtRnlJRWs5YVM1aGJIUmxjbTVoZEdVN2FXWW9TU0U5UFc1MWJHd3BlM1poY2lCRVBVa3VZMmhwYkdRN2FXWW9S'
    || 'Q0U5UFc1MWJHd3BlMGt1WTJocGJHUTliblZzYkR0a2IzdDJZWElnYldVOVJDNXphV0pzYVc1bk8wUXVjMmxpYkdsdVp6MXVkV3hzTEVROWJXVjlkMmhwYkdV'
    || 'b1JDRTlQVzUxYkd3cGZYMVFQV2w5ZldsbUtDaHBMbk4xWW5SeVpXVkdiR0ZuY3lZeU1EWTBLU0U5UFRBbUpuTWhQVDF1ZFd4c0tYTXVjbVYwZFhKdVBXa3NV'
    || 'RDF6TzJWc2MyVWdaVHBtYjNJb08xQWhQVDF1ZFd4c095bDdhV1lvYVQxUUxDaHBMbVpzWVdkekpqSXdORGdwSVQwOU1DbHpkMmwwWTJnb2FTNTBZV2NwZTJO'
    || 'aGMyVWdNRHBqWVhObElERXhPbU5oYzJVZ01UVTZUbklvT1N4cExHa3VjbVYwZFhKdUtYMTJZWElnYlQxcExuTnBZbXhwYm1jN2FXWW9iU0U5UFc1MWJHd3Bl'
    || 'MjB1Y21WMGRYSnVQV2t1Y21WMGRYSnVMRkE5YlR0aWNtVmhheUJsZlZBOWFTNXlaWFIxY201OWZYWmhjaUJ3UFdVdVkzVnljbVZ1ZER0bWIzSW9VRDF3TzFB'
    || 'aFBUMXVkV3hzT3lsN2N6MVFPM1poY2lCMlBYTXVZMmhwYkdRN2FXWW9LSE11YzNWaWRISmxaVVpzWVdkekpqSXdOalFwSVQwOU1DWW1kaUU5UFc1MWJHd3Bk'
    || 'aTV5WlhSMWNtNDljeXhRUFhZN1pXeHpaU0JsT21admNpaHpQWEE3VUNFOVBXNTFiR3c3S1h0cFppaGhQVkFzS0dFdVpteGhaM01tTWpBME9Da2hQVDB3S1hS'
    || 'eWVYdHpkMmwwWTJnb1lTNTBZV2NwZTJOaGMyVWdNRHBqWVhObElERXhPbU5oYzJVZ01UVTZhMndvT1N4aEtYMTlZMkYwWTJnb2VpbDdjR1VvWVN4aExuSmxk'
    || 'SFZ5Yml4NktYMXBaaWhoUFQwOWN5bDdVRDF1ZFd4c08ySnlaV0ZySUdWOWRtRnlJRU05WVM1emFXSnNhVzVuTzJsbUtFTWhQVDF1ZFd4c0tYdERMbkpsZEhW'
    || 'eWJqMWhMbkpsZEhWeWJpeFFQVU03WW5KbFlXc2daWDFRUFdFdWNtVjBkWEp1ZlgxcFppaExQV3dzVVhRb0tTeDRkQ1ltZEhsd1pXOW1JSGgwTG05dVVHOXpk'
    || 'RU52YlcxcGRFWnBZbVZ5VW05dmREMDlJbVoxYm1OMGFXOXVJaWwwY25sN2VIUXViMjVRYjNOMFEyOXRiV2wwUm1saVpYSlNiMjkwS0VaeUxHVXBmV05oZEdO'
    || 'b2UzMXlQU0V3ZlhKbGRIVnliaUJ5ZldacGJtRnNiSGw3ZEdVOWJpeHNkQzUwY21GdWMybDBhVzl1UFhSOWZYSmxkSFZ5YmlFeGZXWjFibU4wYVc5dUlFcGhL'
    || 'R1VzZEN4dUtYdDBQVUZ1S0c0c2RDa3NkRDEyWVNobExIUXNNU2tzWlQxTGRDaGxMSFFzTVNrc2REMUpaU2dwTEdVaFBUMXVkV3hzSmlZb1NtNG9aU3d4TEhR'
    || 'cExGWmxLR1VzZENrcGZXWjFibU4wYVc5dUlIQmxLR1VzZEN4dUtYdHBaaWhsTG5SaFp6MDlQVE1wU21Fb1pTeGxMRzRwTzJWc2MyVWdabTl5S0R0MElUMDli'
    || 'blZzYkRzcGUybG1LSFF1ZEdGblBUMDlNeWw3U21Fb2RDeGxMRzRwTzJKeVpXRnJmV1ZzYzJVZ2FXWW9kQzUwWVdjOVBUMHhLWHQyWVhJZ2NqMTBMbk4wWVhS'
    || 'bFRtOWtaVHRwWmloMGVYQmxiMllnZEM1MGVYQmxMbWRsZEVSbGNtbDJaV1JUZEdGMFpVWnliMjFGY25KdmNqMDlJbVoxYm1OMGFXOXVJbng4ZEhsd1pXOW1J'
    || 'SEl1WTI5dGNHOXVaVzUwUkdsa1EyRjBZMmc5UFNKbWRXNWpkR2x2YmlJbUppaFlkRDA5UFc1MWJHeDhmQ0ZZZEM1b1lYTW9jaWtwS1h0bFBVRnVLRzRzWlNr'
    || 'c1pUMW5ZU2gwTEdVc01Ta3NkRDFMZENoMExHVXNNU2tzWlQxSlpTZ3BMSFFoUFQxdWRXeHNKaVlvU200b2RDd3hMR1VwTEZabEtIUXNaU2twTzJKeVpXRnJm'
    || 'WDEwUFhRdWNtVjBkWEp1ZlgxbWRXNWpkR2x2YmlCWFppaGxMSFFzYmlsN2RtRnlJSEk5WlM1d2FXNW5RMkZqYUdVN2NpRTlQVzUxYkd3bUpuSXVaR1ZzWlhS'
    || 'bEtIUXBMSFE5U1dVb0tTeGxMbkJwYm1kbFpFeGhibVZ6ZkQxbExuTjFjM0JsYm1SbFpFeGhibVZ6Sm00c1UyVTlQVDFsSmlZb1EyVW1iaWs5UFQxdUppWW9l'
    || 'R1U5UFQwMGZIeDRaVDA5UFRNbUppaERaU1l4TXpBd01qTTBNalFwUFQwOVEyVW1KalV3TUQ1b1pTZ3BMVWx2UDNCdUtHVXNNQ2s2VFc5OFBXNHBMRlpsS0dV'
    || 'c2RDbDlablZ1WTNScGIyNGdZbUVvWlN4MEtYdDBQVDA5TUNZbUtDaGxMbTF2WkdVbU1TazlQVDB3UDNROU1Ub29kRDFWY2l4VmNqdzhQVEVzS0ZWeUpqRXpN'
    || 'REF5TXpReU5DazlQVDB3SmlZb1ZYSTlOREU1TkRNd05Da3BLVHQyWVhJZ2JqMUpaU2dwTzJVOVVuUW9aU3gwS1N4bElUMDliblZzYkNZbUtFcHVLR1VzZEN4'
    || 'dUtTeFdaU2hsTEc0cEtYMW1kVzVqZEdsdmJpQkNaaWhsS1h0MllYSWdkRDFsTG0xbGJXOXBlbVZrVTNSaGRHVXNiajB3TzNRaFBUMXVkV3hzSmlZb2JqMTBM'
    || 'bkpsZEhKNVRHRnVaU2tzWW1Fb1pTeHVLWDFtZFc1amRHbHZiaUJSWmlobExIUXBlM1poY2lCdVBUQTdjM2RwZEdOb0tHVXVkR0ZuS1h0allYTmxJREV6T25a'
    || 'aGNpQnlQV1V1YzNSaGRHVk9iMlJsTEd3OVpTNXRaVzF2YVhwbFpGTjBZWFJsTzJ3aFBUMXVkV3hzSmlZb2JqMXNMbkpsZEhKNVRHRnVaU2s3WW5KbFlXczdZ'
    || 'MkZ6WlNBeE9UcHlQV1V1YzNSaGRHVk9iMlJsTzJKeVpXRnJPMlJsWm1GMWJIUTZkR2h5YjNjZ1JYSnliM0lvWXlnek1UUXBLWDF5SVQwOWJuVnNiQ1ltY2k1'
    || 'a1pXeGxkR1VvZENrc1ltRW9aU3h1S1gxMllYSWdaV003WldNOVpuVnVZM1JwYjI0b1pTeDBMRzRwZTJsbUtHVWhQVDF1ZFd4c0tXbG1LR1V1YldWdGIybDZa'
    || 'V1JRY205d2N5RTlQWFF1Y0dWdVpHbHVaMUJ5YjNCemZIeEJaUzVqZFhKeVpXNTBLU1JsUFNFd08yVnNjMlY3YVdZb0tHVXViR0Z1WlhNbWJpazlQVDB3SmlZ'
    || 'b2RDNW1iR0ZuY3lZeE1qZ3BQVDA5TUNseVpYUjFjbTRnSkdVOUlURXNVR1lvWlN4MExHNHBPeVJsUFNobExtWnNZV2R6SmpFek1UQTNNaWtoUFQwd2ZXVnNj'
    || 'MlVnSkdVOUlURXNjMlVtSmloMExtWnNZV2R6SmpFd05EZzFOellwSVQwOU1DWW1UWFVvZEN4emJDeDBMbWx1WkdWNEtUdHpkMmwwWTJnb2RDNXNZVzVsY3ow'
    || 'd0xIUXVkR0ZuS1h0allYTmxJREk2ZG1GeUlISTlkQzUwZVhCbE8xTnNLR1VzZENrc1pUMTBMbkJsYm1ScGJtZFFjbTl3Y3p0MllYSWdiRDFNYmloMExGUmxM'
    || 'bU4xY25KbGJuUXBPM3B1S0hRc2Jpa3NiRDFqYnlodWRXeHNMSFFzY2l4bExHd3NiaWs3ZG1GeUlHazlabThvS1R0eVpYUjFjbTRnZEM1bWJHRm5jM3c5TVN4'
    || 'MGVYQmxiMllnYkQwOUltOWlhbVZqZENJbUptd2hQVDF1ZFd4c0ppWjBlWEJsYjJZZ2JDNXlaVzVrWlhJOVBTSm1kVzVqZEdsdmJpSW1KbXd1SkNSMGVYQmxi'
    || 'Mlk5UFQxMmIybGtJREEvS0hRdWRHRm5QVEVzZEM1dFpXMXZhWHBsWkZOMFlYUmxQVzUxYkd3c2RDNTFjR1JoZEdWUmRXVjFaVDF1ZFd4c0xGVmxLSElwUHlo'
    || 'cFBTRXdMR3hzS0hRcEtUcHBQU0V4TEhRdWJXVnRiMmw2WldSVGRHRjBaVDFzTG5OMFlYUmxJVDA5Ym5Wc2JDWW1iQzV6ZEdGMFpTRTlQWFp2YVdRZ01EOXNM'
    || 'bk4wWVhSbE9tNTFiR3dzY204b2RDa3NiQzUxY0dSaGRHVnlQWGRzTEhRdWMzUmhkR1ZPYjJSbFBXd3NiQzVmY21WaFkzUkpiblJsY201aGJITTlkQ3g1Ynlo'
    || 'MExISXNaU3h1S1N4MFBWTnZLRzUxYkd3c2RDeHlMQ0V3TEdrc2Jpa3BPaWgwTG5SaFp6MHdMSE5sSmlacEppWkxhU2gwS1N4TlpTaHVkV3hzTEhRc2JDeHVL'
    || 'U3gwUFhRdVkyaHBiR1FwTEhRN1kyRnpaU0F4TmpweVBYUXVaV3hsYldWdWRGUjVjR1U3WlRwN2MzZHBkR05vS0ZOc0tHVXNkQ2tzWlQxMExuQmxibVJwYm1k'
    || 'UWNtOXdjeXhzUFhJdVgybHVhWFFzY2oxc0tISXVYM0JoZVd4dllXUXBMSFF1ZEhsd1pUMXlMR3c5ZEM1MFlXYzlTMllvY2lrc1pUMW1kQ2h5TEdVcExHd3Bl'
    || 'Mk5oYzJVZ01EcDBQVjl2S0c1MWJHd3NkQ3h5TEdVc2JpazdZbkpsWVdzZ1pUdGpZWE5sSURFNmREMXFZU2h1ZFd4c0xIUXNjaXhsTEc0cE8ySnlaV0ZySUdV'
    || 'N1kyRnpaU0F4TVRwMFBWOWhLRzUxYkd3c2RDeHlMR1VzYmlrN1luSmxZV3NnWlR0allYTmxJREUwT25ROVUyRW9iblZzYkN4MExISXNablFvY2k1MGVYQmxM'
    || 'R1VwTEc0cE8ySnlaV0ZySUdWOWRHaHliM2NnUlhKeWIzSW9ZeWd6TURZc2Npd2lJaWtwZlhKbGRIVnliaUIwTzJOaGMyVWdNRHB5WlhSMWNtNGdjajEwTG5S'
    || 'NWNHVXNiRDEwTG5CbGJtUnBibWRRY205d2N5eHNQWFF1Wld4bGJXVnVkRlI1Y0dVOVBUMXlQMnc2Wm5Rb2NpeHNLU3hmYnlobExIUXNjaXhzTEc0cE8yTmhj'
    || 'MlVnTVRweVpYUjFjbTRnY2oxMExuUjVjR1VzYkQxMExuQmxibVJwYm1kUWNtOXdjeXhzUFhRdVpXeGxiV1Z1ZEZSNWNHVTlQVDF5UDJ3NlpuUW9jaXhzS1N4'
    || 'cVlTaGxMSFFzY2l4c0xHNHBPMk5oYzJVZ016cGxPbnRwWmloRFlTaDBLU3hsUFQwOWJuVnNiQ2wwYUhKdmR5QkZjbkp2Y2loaktETTROeWtwTzNJOWRDNXda'
    || 'VzVrYVc1blVISnZjSE1zYVQxMExtMWxiVzlwZW1Wa1UzUmhkR1VzYkQxcExtVnNaVzFsYm5Rc1ZuVW9aU3gwS1N4d2JDaDBMSElzYm5Wc2JDeHVLVHQyWVhJ'
    || 'Z2N6MTBMbTFsYlc5cGVtVmtVM1JoZEdVN2FXWW9jajF6TG1Wc1pXMWxiblFzYVM1cGMwUmxhSGxrY21GMFpXUXBhV1lvYVQxN1pXeGxiV1Z1ZERweUxHbHpS'
    || 'R1ZvZVdSeVlYUmxaRG9oTVN4allXTm9aVHB6TG1OaFkyaGxMSEJsYm1ScGJtZFRkWE53Wlc1elpVSnZkVzVrWVhKcFpYTTZjeTV3Wlc1a2FXNW5VM1Z6Y0dW'
    || 'dWMyVkNiM1Z1WkdGeWFXVnpMSFJ5WVc1emFYUnBiMjV6T25NdWRISmhibk5wZEdsdmJuTjlMSFF1ZFhCa1lYUmxVWFZsZFdVdVltRnpaVk4wWVhSbFBXa3Nk'
    || 'QzV0WlcxdmFYcGxaRk4wWVhSbFBXa3NkQzVtYkdGbmN5WXlOVFlwZTJ3OVFXNG9SWEp5YjNJb1l5ZzBNak1wS1N4MEtTeDBQVlJoS0dVc2RDeHlMRzRzYkNr'
    || 'N1luSmxZV3NnWlgxbGJITmxJR2xtS0hJaFBUMXNLWHRzUFVGdUtFVnljbTl5S0dNb05ESTBLU2tzZENrc2REMVVZU2hsTEhRc2NpeHVMR3dwTzJKeVpXRnJJ'
    || 'R1Y5Wld4elpTQm1iM0lvV21VOVZuUW9kQzV6ZEdGMFpVNXZaR1V1WTI5dWRHRnBibVZ5U1c1bWJ5NW1hWEp6ZEVOb2FXeGtLU3hZWlQxMExITmxQU0V3TEdS'
    || 'MFBXNTFiR3dzYmowa2RTaDBMRzUxYkd3c2NpeHVLU3gwTG1Ob2FXeGtQVzQ3YmpzcGJpNW1iR0ZuY3oxdUxtWnNZV2R6SmkwemZEUXdPVFlzYmoxdUxuTnBZ'
    || 'bXhwYm1jN1pXeHpaWHRwWmloTmJpZ3BMSEk5UFQxc0tYdDBQVTkwS0dVc2RDeHVLVHRpY21WaGF5QmxmVTFsS0dVc2RDeHlMRzRwZlhROWRDNWphR2xzWkgx'
    || 'eVpYUjFjbTRnZER0allYTmxJRFU2Y21WMGRYSnVJRkYxS0hRcExHVTlQVDF1ZFd4c0ppWmFhU2gwS1N4eVBYUXVkSGx3WlN4c1BYUXVjR1Z1WkdsdVoxQnli'
    || 'M0J6TEdrOVpTRTlQVzUxYkd3L1pTNXRaVzF2YVhwbFpGQnliM0J6T201MWJHd3NjejFzTG1Ob2FXeGtjbVZ1TEVocEtISXNiQ2svY3oxdWRXeHNPbWtoUFQx'
    || 'dWRXeHNKaVpJYVNoeUxHa3BKaVlvZEM1bWJHRm5jM3c5TXpJcExFNWhLR1VzZENrc1RXVW9aU3gwTEhNc2Jpa3NkQzVqYUdsc1pEdGpZWE5sSURZNmNtVjBk'
    || 'WEp1SUdVOVBUMXVkV3hzSmlaYWFTaDBLU3h1ZFd4c08yTmhjMlVnTVRNNmNtVjBkWEp1SUZKaEtHVXNkQ3h1S1R0allYTmxJRFE2Y21WMGRYSnVJR3h2S0hR'
    || 'c2RDNXpkR0YwWlU1dlpHVXVZMjl1ZEdGcGJtVnlTVzVtYnlrc2NqMTBMbkJsYm1ScGJtZFFjbTl3Y3l4bFBUMDliblZzYkQ5MExtTm9hV3hrUFVsdUtIUXNi'
    || 'blZzYkN4eUxHNHBPazFsS0dVc2RDeHlMRzRwTEhRdVkyaHBiR1E3WTJGelpTQXhNVHB5WlhSMWNtNGdjajEwTG5SNWNHVXNiRDEwTG5CbGJtUnBibWRRY205'
    || 'd2N5eHNQWFF1Wld4bGJXVnVkRlI1Y0dVOVBUMXlQMnc2Wm5Rb2NpeHNLU3hmWVNobExIUXNjaXhzTEc0cE8yTmhjMlVnTnpweVpYUjFjbTRnVFdVb1pTeDBM'
    || 'SFF1Y0dWdVpHbHVaMUJ5YjNCekxHNHBMSFF1WTJocGJHUTdZMkZ6WlNBNE9uSmxkSFZ5YmlCTlpTaGxMSFFzZEM1d1pXNWthVzVuVUhKdmNITXVZMmhwYkdS'
    || 'eVpXNHNiaWtzZEM1amFHbHNaRHRqWVhObElERXlPbkpsZEhWeWJpQk5aU2hsTEhRc2RDNXdaVzVrYVc1blVISnZjSE11WTJocGJHUnlaVzRzYmlrc2RDNWph'
    || 'R2xzWkR0allYTmxJREV3T21VNmUybG1LSEk5ZEM1MGVYQmxMbDlqYjI1MFpYaDBMR3c5ZEM1d1pXNWthVzVuVUhKdmNITXNhVDEwTG0xbGJXOXBlbVZrVUhK'
    || 'dmNITXNjejFzTG5aaGJIVmxMSEpsS0dOc0xISXVYMk4xY25KbGJuUldZV3gxWlNrc2NpNWZZM1Z5Y21WdWRGWmhiSFZsUFhNc2FTRTlQVzUxYkd3cGFXWW9Z'
    || 'M1FvYVM1MllXeDFaU3h6S1NsN2FXWW9hUzVqYUdsc1pISmxiajA5UFd3dVkyaHBiR1J5Wlc0bUppRkJaUzVqZFhKeVpXNTBLWHQwUFU5MEtHVXNkQ3h1S1R0'
    || 'aWNtVmhheUJsZlgxbGJITmxJR1p2Y2locFBYUXVZMmhwYkdRc2FTRTlQVzUxYkd3bUppaHBMbkpsZEhWeWJqMTBLVHRwSVQwOWJuVnNiRHNwZTNaaGNpQmhQ'
    || 'V2t1WkdWd1pXNWtaVzVqYVdWek8ybG1LR0VoUFQxdWRXeHNLWHR6UFdrdVkyaHBiR1E3Wm05eUtIWmhjaUJtUFdFdVptbHljM1JEYjI1MFpYaDBPMlloUFQx'
    || 'dWRXeHNPeWw3YVdZb1ppNWpiMjUwWlhoMFBUMDljaWw3YVdZb2FTNTBZV2M5UFQweEtYdG1QVXgwS0MweExHNG1MVzRwTEdZdWRHRm5QVEk3ZG1GeUlHYzlh'
    || 'UzUxY0dSaGRHVlJkV1YxWlR0cFppaG5JVDA5Ym5Wc2JDbDdaejFuTG5Ob1lYSmxaRHQyWVhJZ1V6MW5MbkJsYm1ScGJtYzdVejA5UFc1MWJHdy9aaTV1Wlho'
    || 'MFBXWTZLR1l1Ym1WNGREMVRMbTVsZUhRc1V5NXVaWGgwUFdZcExHY3VjR1Z1WkdsdVp6MW1mWDFwTG14aGJtVnpmRDF1TEdZOWFTNWhiSFJsY201aGRHVXNa'
    || 'aUU5UFc1MWJHd21KaWhtTG14aGJtVnpmRDF1S1N4MGJ5aHBMbkpsZEhWeWJpeHVMSFFwTEdFdWJHRnVaWE44UFc0N1luSmxZV3Q5WmoxbUxtNWxlSFI5ZldW'
    || 'c2MyVWdhV1lvYVM1MFlXYzlQVDB4TUNselBXa3VkSGx3WlQwOVBYUXVkSGx3WlQ5dWRXeHNPbWt1WTJocGJHUTdaV3h6WlNCcFppaHBMblJoWnowOVBURTRL'
    || 'WHRwWmloelBXa3VjbVYwZFhKdUxITTlQVDF1ZFd4c0tYUm9jbTkzSUVWeWNtOXlLR01vTXpReEtTazdjeTVzWVc1bGMzdzliaXhoUFhNdVlXeDBaWEp1WVhS'
    || 'bExHRWhQVDF1ZFd4c0ppWW9ZUzVzWVc1bGMzdzliaWtzZEc4b2N5eHVMSFFwTEhNOWFTNXphV0pzYVc1bmZXVnNjMlVnY3oxcExtTm9hV3hrTzJsbUtITWhQ'
    || 'VDF1ZFd4c0tYTXVjbVYwZFhKdVBXazdaV3h6WlNCbWIzSW9jejFwTzNNaFBUMXVkV3hzT3lsN2FXWW9jejA5UFhRcGUzTTliblZzYkR0aWNtVmhhMzFwWmlo'
    || 'cFBYTXVjMmxpYkdsdVp5eHBJVDA5Ym5Wc2JDbDdhUzV5WlhSMWNtNDljeTV5WlhSMWNtNHNjejFwTzJKeVpXRnJmWE05Y3k1eVpYUjFjbTU5YVQxemZVMWxL'
    || 'R1VzZEN4c0xtTm9hV3hrY21WdUxHNHBMSFE5ZEM1amFHbHNaSDF5WlhSMWNtNGdkRHRqWVhObElEazZjbVYwZFhKdUlHdzlkQzUwZVhCbExISTlkQzV3Wlc1'
    || 'a2FXNW5VSEp2Y0hNdVkyaHBiR1J5Wlc0c2VtNG9kQ3h1S1N4c1BXNTBLR3dwTEhJOWNpaHNLU3gwTG1ac1lXZHpmRDB4TEUxbEtHVXNkQ3h5TEc0cExIUXVZ'
    || 'MmhwYkdRN1kyRnpaU0F4TkRweVpYUjFjbTRnY2oxMExuUjVjR1VzYkQxbWRDaHlMSFF1Y0dWdVpHbHVaMUJ5YjNCektTeHNQV1owS0hJdWRIbHdaU3hzS1N4'
    || 'VFlTaGxMSFFzY2l4c0xHNHBPMk5oYzJVZ01UVTZjbVYwZFhKdUlFVmhLR1VzZEN4MExuUjVjR1VzZEM1d1pXNWthVzVuVUhKdmNITXNiaWs3WTJGelpTQXhO'
    || 'enB5WlhSMWNtNGdjajEwTG5SNWNHVXNiRDEwTG5CbGJtUnBibWRRY205d2N5eHNQWFF1Wld4bGJXVnVkRlI1Y0dVOVBUMXlQMnc2Wm5Rb2NpeHNLU3hUYkNo'
    || 'bExIUXBMSFF1ZEdGblBURXNWV1VvY2lrL0tHVTlJVEFzYkd3b2RDa3BPbVU5SVRFc2VtNG9kQ3h1S1N4b1lTaDBMSElzYkNrc2VXOG9kQ3h5TEd3c2Jpa3NV'
    || 'MjhvYm5Wc2JDeDBMSElzSVRBc1pTeHVLVHRqWVhObElERTVPbkpsZEhWeWJpQlBZU2hsTEhRc2JpazdZMkZ6WlNBeU1qcHlaWFIxY200Z2EyRW9aU3gwTEc0'
    || 'cGZYUm9jbTkzSUVWeWNtOXlLR01vTVRVMkxIUXVkR0ZuS1NsOU8yWjFibU4wYVc5dUlIUmpLR1VzZENsN2NtVjBkWEp1SUVsektHVXNkQ2w5Wm5WdVkzUnBi'
    || 'MjRnUjJZb1pTeDBMRzRzY2lsN2RHaHBjeTUwWVdjOVpTeDBhR2x6TG10bGVUMXVMSFJvYVhNdWMybGliR2x1WnoxMGFHbHpMbU5vYVd4a1BYUm9hWE11Y21W'
    || 'MGRYSnVQWFJvYVhNdWMzUmhkR1ZPYjJSbFBYUm9hWE11ZEhsd1pUMTBhR2x6TG1Wc1pXMWxiblJVZVhCbFBXNTFiR3dzZEdocGN5NXBibVJsZUQwd0xIUm9h'
    || 'WE11Y21WbVBXNTFiR3dzZEdocGN5NXdaVzVrYVc1blVISnZjSE05ZEN4MGFHbHpMbVJsY0dWdVpHVnVZMmxsY3oxMGFHbHpMbTFsYlc5cGVtVmtVM1JoZEdV'
    || 'OWRHaHBjeTUxY0dSaGRHVlJkV1YxWlQxMGFHbHpMbTFsYlc5cGVtVmtVSEp2Y0hNOWJuVnNiQ3gwYUdsekxtMXZaR1U5Y2l4MGFHbHpMbk4xWW5SeVpXVkdi'
    || 'R0ZuY3oxMGFHbHpMbVpzWVdkelBUQXNkR2hwY3k1a1pXeGxkR2x2Ym5NOWJuVnNiQ3gwYUdsekxtTm9hV3hrVEdGdVpYTTlkR2hwY3k1c1lXNWxjejB3TEhS'
    || 'b2FYTXVZV3gwWlhKdVlYUmxQVzUxYkd4OVpuVnVZM1JwYjI0Z2FYUW9aU3gwTEc0c2NpbDdjbVYwZFhKdUlHNWxkeUJIWmlobExIUXNiaXh5S1gxbWRXNWpk'
    || 'R2x2YmlCV2J5aGxLWHR5WlhSMWNtNGdaVDFsTG5CeWIzUnZkSGx3WlN3aEtDRmxmSHdoWlM1cGMxSmxZV04wUTI5dGNHOXVaVzUwS1gxbWRXNWpkR2x2YmlC'
    || 'TFppaGxLWHRwWmloMGVYQmxiMllnWlQwOUltWjFibU4wYVc5dUlpbHlaWFIxY200Z1ZtOG9aU2svTVRvd08ybG1LR1VoUFc1MWJHd3BlMmxtS0dVOVpTNGtK'
    || 'SFI1Y0dWdlppeGxQVDA5WjNRcGNtVjBkWEp1SURFeE8ybG1LR1U5UFQxNWRDbHlaWFIxY200Z01UUjljbVYwZFhKdUlESjlablZ1WTNScGIyNGdZblFvWlN4'
    || 'MEtYdDJZWElnYmoxbExtRnNkR1Z5Ym1GMFpUdHlaWFIxY200Z2JqMDlQVzUxYkd3L0tHNDlhWFFvWlM1MFlXY3NkQ3hsTG10bGVTeGxMbTF2WkdVcExHNHVa'
    || 'V3hsYldWdWRGUjVjR1U5WlM1bGJHVnRaVzUwVkhsd1pTeHVMblI1Y0dVOVpTNTBlWEJsTEc0dWMzUmhkR1ZPYjJSbFBXVXVjM1JoZEdWT2IyUmxMRzR1WVd4'
    || 'MFpYSnVZWFJsUFdVc1pTNWhiSFJsY201aGRHVTliaWs2S0c0dWNHVnVaR2x1WjFCeWIzQnpQWFFzYmk1MGVYQmxQV1V1ZEhsd1pTeHVMbVpzWVdkelBUQXNi'
    || 'aTV6ZFdKMGNtVmxSbXhoWjNNOU1DeHVMbVJsYkdWMGFXOXVjejF1ZFd4c0tTeHVMbVpzWVdkelBXVXVabXhoWjNNbU1UUTJPREF3TmpRc2JpNWphR2xzWkV4'
    || 'aGJtVnpQV1V1WTJocGJHUk1ZVzVsY3l4dUxteGhibVZ6UFdVdWJHRnVaWE1zYmk1amFHbHNaRDFsTG1Ob2FXeGtMRzR1YldWdGIybDZaV1JRY205d2N6MWxM'
    || 'bTFsYlc5cGVtVmtVSEp2Y0hNc2JpNXRaVzF2YVhwbFpGTjBZWFJsUFdVdWJXVnRiMmw2WldSVGRHRjBaU3h1TG5Wd1pHRjBaVkYxWlhWbFBXVXVkWEJrWVhS'
    || 'bFVYVmxkV1VzZEQxbExtUmxjR1Z1WkdWdVkybGxjeXh1TG1SbGNHVnVaR1Z1WTJsbGN6MTBQVDA5Ym5Wc2JEOXVkV3hzT250c1lXNWxjenAwTG14aGJtVnpM'
    || 'R1pwY25OMFEyOXVkR1Y0ZERwMExtWnBjbk4wUTI5dWRHVjRkSDBzYmk1emFXSnNhVzVuUFdVdWMybGliR2x1Wnl4dUxtbHVaR1Y0UFdVdWFXNWtaWGdzYmk1'
    || 'eVpXWTlaUzV5WldZc2JuMW1kVzVqZEdsdmJpQk5iQ2hsTEhRc2JpeHlMR3dzYVNsN2RtRnlJSE05TWp0cFppaHlQV1VzZEhsd1pXOW1JR1U5UFNKbWRXNWpk'
    || 'R2x2YmlJcFZtOG9aU2ttSmloelBURXBPMlZzYzJVZ2FXWW9kSGx3Wlc5bUlHVTlQU0p6ZEhKcGJtY2lLWE05TlR0bGJITmxJR1U2YzNkcGRHTm9LR1VwZTJO'
    || 'aGMyVWdUbVU2Y21WMGRYSnVJRzF1S0c0dVkyaHBiR1J5Wlc0c2JDeHBMSFFwTzJOaGMyVWdVR1U2Y3owNExHeDhQVGc3WW5KbFlXczdZMkZ6WlNCa1pUcHla'
    || 'WFIxY200Z1pUMXBkQ2d4TWl4dUxIUXNiSHd5S1N4bExtVnNaVzFsYm5SVWVYQmxQV1JsTEdVdWJHRnVaWE05YVN4bE8yTmhjMlVnUjJVNmNtVjBkWEp1SUdV'
    || 'OWFYUW9NVE1zYml4MExHd3BMR1V1Wld4bGJXVnVkRlI1Y0dVOVIyVXNaUzVzWVc1bGN6MXBMR1U3WTJGelpTQjFkRHB5WlhSMWNtNGdaVDFwZENneE9TeHVM'
    || 'SFFzYkNrc1pTNWxiR1Z0Wlc1MFZIbHdaVDExZEN4bExteGhibVZ6UFdrc1pUdGpZWE5sSUdabE9uSmxkSFZ5YmlCSmJDaHVMR3dzYVN4MEtUdGtaV1poZFd4'
    || 'ME9tbG1LSFI1Y0dWdlppQmxQVDBpYjJKcVpXTjBJaVltWlNFOVBXNTFiR3dwYzNkcGRHTm9LR1V1SkNSMGVYQmxiMllwZTJOaGMyVWdhM1E2Y3oweE1EdGlj'
    || 'bVZoYXlCbE8yTmhjMlVnZEc0NmN6MDVPMkp5WldGcklHVTdZMkZ6WlNCbmREcHpQVEV4TzJKeVpXRnJJR1U3WTJGelpTQjVkRHB6UFRFME8ySnlaV0ZySUdV'
    || 'N1kyRnpaU0JHWlRwelBURTJMSEk5Ym5Wc2JEdGljbVZoYXlCbGZYUm9jbTkzSUVWeWNtOXlLR01vTVRNd0xHVTlQVzUxYkd3L1pUcDBlWEJsYjJZZ1pTd2lJ'
    || 'aWtwZlhKbGRIVnliaUIwUFdsMEtITXNiaXgwTEd3cExIUXVaV3hsYldWdWRGUjVjR1U5WlN4MExuUjVjR1U5Y2l4MExteGhibVZ6UFdrc2RIMW1kVzVqZEds'
    || 'dmJpQnRiaWhsTEhRc2JpeHlLWHR5WlhSMWNtNGdaVDFwZENnM0xHVXNjaXgwS1N4bExteGhibVZ6UFc0c1pYMW1kVzVqZEdsdmJpQkpiQ2hsTEhRc2JpeHlL'
    || 'WHR5WlhSMWNtNGdaVDFwZENneU1peGxMSElzZENrc1pTNWxiR1Z0Wlc1MFZIbHdaVDFtWlN4bExteGhibVZ6UFc0c1pTNXpkR0YwWlU1dlpHVTllMmx6U0ds'
    || 'a1pHVnVPaUV4ZlN4bGZXWjFibU4wYVc5dUlGZHZLR1VzZEN4dUtYdHlaWFIxY200Z1pUMXBkQ2cyTEdVc2JuVnNiQ3gwS1N4bExteGhibVZ6UFc0c1pYMW1k'
    || 'VzVqZEdsdmJpQkNieWhsTEhRc2JpbDdjbVYwZFhKdUlIUTlhWFFvTkN4bExtTm9hV3hrY21WdUlUMDliblZzYkQ5bExtTm9hV3hrY21WdU9sdGRMR1V1YTJW'
    || 'NUxIUXBMSFF1YkdGdVpYTTliaXgwTG5OMFlYUmxUbTlrWlQxN1kyOXVkR0ZwYm1WeVNXNW1ienBsTG1OdmJuUmhhVzVsY2tsdVptOHNjR1Z1WkdsdVowTm9h'
    || 'V3hrY21WdU9tNTFiR3dzYVcxd2JHVnRaVzUwWVhScGIyNDZaUzVwYlhCc1pXMWxiblJoZEdsdmJuMHNkSDFtZFc1amRHbHZiaUJaWmlobExIUXNiaXh5TEd3'
    || 'cGUzUm9hWE11ZEdGblBYUXNkR2hwY3k1amIyNTBZV2x1WlhKSmJtWnZQV1VzZEdocGN5NW1hVzVwYzJobFpGZHZjbXM5ZEdocGN5NXdhVzVuUTJGamFHVTlk'
    || 'R2hwY3k1amRYSnlaVzUwUFhSb2FYTXVjR1Z1WkdsdVowTm9hV3hrY21WdVBXNTFiR3dzZEdocGN5NTBhVzFsYjNWMFNHRnVaR3hsUFMweExIUm9hWE11WTJG'
    || 'c2JHSmhZMnRPYjJSbFBYUm9hWE11Y0dWdVpHbHVaME52Ym5SbGVIUTlkR2hwY3k1amIyNTBaWGgwUFc1MWJHd3NkR2hwY3k1allXeHNZbUZqYTFCeWFXOXlh'
    || 'WFI1UFRBc2RHaHBjeTVsZG1WdWRGUnBiV1Z6UFhacEtEQXBMSFJvYVhNdVpYaHdhWEpoZEdsdmJsUnBiV1Z6UFhacEtDMHhLU3gwYUdsekxtVnVkR0Z1WjJ4'
    || 'bFpFeGhibVZ6UFhSb2FYTXVabWx1YVhOb1pXUk1ZVzVsY3oxMGFHbHpMbTExZEdGaWJHVlNaV0ZrVEdGdVpYTTlkR2hwY3k1bGVIQnBjbVZrVEdGdVpYTTlk'
    || 'R2hwY3k1d2FXNW5aV1JNWVc1bGN6MTBhR2x6TG5OMWMzQmxibVJsWkV4aGJtVnpQWFJvYVhNdWNHVnVaR2x1WjB4aGJtVnpQVEFzZEdocGN5NWxiblJoYm1k'
    || 'c1pXMWxiblJ6UFhacEtEQXBMSFJvYVhNdWFXUmxiblJwWm1sbGNsQnlaV1pwZUQxeUxIUm9hWE11YjI1U1pXTnZkbVZ5WVdKc1pVVnljbTl5UFd3c2RHaHBj'
    || 'eTV0ZFhSaFlteGxVMjkxY21ObFJXRm5aWEpJZVdSeVlYUnBiMjVFWVhSaFBXNTFiR3g5Wm5WdVkzUnBiMjRnVVc4b1pTeDBMRzRzY2l4c0xHa3NjeXhoTEdZ'
    || 'cGUzSmxkSFZ5YmlCbFBXNWxkeUJaWmlobExIUXNiaXhoTEdZcExIUTlQVDB4UHloMFBURXNhVDA5UFNFd0ppWW9kSHc5T0NrcE9uUTlNQ3hwUFdsMEtETXNi'
    || 'blZzYkN4dWRXeHNMSFFwTEdVdVkzVnljbVZ1ZEQxcExHa3VjM1JoZEdWT2IyUmxQV1VzYVM1dFpXMXZhWHBsWkZOMFlYUmxQWHRsYkdWdFpXNTBPbklzYVhO'
    || 'RVpXaDVaSEpoZEdWa09tNHNZMkZqYUdVNmJuVnNiQ3gwY21GdWMybDBhVzl1Y3pwdWRXeHNMSEJsYm1ScGJtZFRkWE53Wlc1elpVSnZkVzVrWVhKcFpYTTZi'
    || 'blZzYkgwc2NtOG9hU2tzWlgxbWRXNWpkR2x2YmlCWVppaGxMSFFzYmlsN2RtRnlJSEk5TXp4aGNtZDFiV1Z1ZEhNdWJHVnVaM1JvSmlaaGNtZDFiV1Z1ZEhO'
    || 'Yk0xMGhQVDEyYjJsa0lEQS9ZWEpuZFcxbGJuUnpXek5kT201MWJHdzdjbVYwZFhKdWV5UWtkSGx3Wlc5bU9uZGxMR3RsZVRweVBUMXVkV3hzUDI1MWJHdzZJ'
    || 'aUlyY2l4amFHbHNaSEpsYmpwbExHTnZiblJoYVc1bGNrbHVabTg2ZEN4cGJYQnNaVzFsYm5SaGRHbHZianB1ZlgxbWRXNWpkR2x2YmlCdVl5aGxLWHRwWmln'
    || 'aFpTbHlaWFIxY200Z1FuUTdaVDFsTGw5eVpXRmpkRWx1ZEdWeWJtRnNjenRsT250cFppaHViaWhsS1NFOVBXVjhmR1V1ZEdGbklUMDlNU2wwYUhKdmR5QkZj'
    || 'bkp2Y2loaktERTNNQ2twTzNaaGNpQjBQV1U3Wkc5N2MzZHBkR05vS0hRdWRHRm5LWHRqWVhObElETTZkRDEwTG5OMFlYUmxUbTlrWlM1amIyNTBaWGgwTzJK'
    || 'eVpXRnJJR1U3WTJGelpTQXhPbWxtS0ZWbEtIUXVkSGx3WlNrcGUzUTlkQzV6ZEdGMFpVNXZaR1V1WDE5eVpXRmpkRWx1ZEdWeWJtRnNUV1Z0YjJsNlpXUk5a'
    || 'WEpuWldSRGFHbHNaRU52Ym5SbGVIUTdZbkpsWVdzZ1pYMTlkRDEwTG5KbGRIVnlibjEzYUdsc1pTaDBJVDA5Ym5Wc2JDazdkR2h5YjNjZ1JYSnliM0lvWXln'
    || 'eE56RXBLWDFwWmlobExuUmhaejA5UFRFcGUzWmhjaUJ1UFdVdWRIbHdaVHRwWmloVlpTaHVLU2x5WlhSMWNtNGdUSFVvWlN4dUxIUXBmWEpsZEhWeWJpQjBm'
    || 'V1oxYm1OMGFXOXVJSEpqS0dVc2RDeHVMSElzYkN4cExITXNZU3htS1h0eVpYUjFjbTRnWlQxUmJ5aHVMSElzSVRBc1pTeHNMR2tzY3l4aExHWXBMR1V1WTI5'
    || 'dWRHVjRkRDF1WXlodWRXeHNLU3h1UFdVdVkzVnljbVZ1ZEN4eVBVbGxLQ2tzYkQxeGRDaHVLU3hwUFV4MEtISXNiQ2tzYVM1allXeHNZbUZqYXoxMFB6OXVk'
    || 'V3hzTEV0MEtHNHNhU3hzS1N4bExtTjFjbkpsYm5RdWJHRnVaWE05YkN4S2JpaGxMR3dzY2lrc1ZtVW9aU3h5S1N4bGZXWjFibU4wYVc5dUlFUnNLR1VzZEN4'
    || 'dUxISXBlM1poY2lCc1BYUXVZM1Z5Y21WdWRDeHBQVWxsS0Nrc2N6MXhkQ2hzS1R0eVpYUjFjbTRnYmoxdVl5aHVLU3gwTG1OdmJuUmxlSFE5UFQxdWRXeHNQ'
    || 'M1F1WTI5dWRHVjRkRDF1T25RdWNHVnVaR2x1WjBOdmJuUmxlSFE5Yml4MFBVeDBLR2tzY3lrc2RDNXdZWGxzYjJGa1BYdGxiR1Z0Wlc1ME9tVjlMSEk5Y2ow'
    || 'OVBYWnZhV1FnTUQ5dWRXeHNPbklzY2lFOVBXNTFiR3dtSmloMExtTmhiR3hpWVdOclBYSXBMR1U5UzNRb2JDeDBMSE1wTEdVaFBUMXVkV3hzSmlZb2JYUW9a'
    || 'U3hzTEhNc2FTa3NabXdvWlN4c0xITXBLU3h6ZldaMWJtTjBhVzl1SUhwc0tHVXBlMmxtS0dVOVpTNWpkWEp5Wlc1MExDRmxMbU5vYVd4a0tYSmxkSFZ5YmlC'
    || 'dWRXeHNPM04zYVhSamFDaGxMbU5vYVd4a0xuUmhaeWw3WTJGelpTQTFPbkpsZEhWeWJpQmxMbU5vYVd4a0xuTjBZWFJsVG05a1pUdGtaV1poZFd4ME9uSmxk'
    || 'SFZ5YmlCbExtTm9hV3hrTG5OMFlYUmxUbTlrWlgxOVpuVnVZM1JwYjI0Z2JHTW9aU3gwS1h0cFppaGxQV1V1YldWdGIybDZaV1JUZEdGMFpTeGxJVDA5Ym5W'
    || 'c2JDWW1aUzVrWldoNVpISmhkR1ZrSVQwOWJuVnNiQ2w3ZG1GeUlHNDlaUzV5WlhSeWVVeGhibVU3WlM1eVpYUnllVXhoYm1VOWJpRTlQVEFtSm00OGREOXVP'
    || 'blI5ZldaMWJtTjBhVzl1SUVkdktHVXNkQ2w3YkdNb1pTeDBLU3dvWlQxbExtRnNkR1Z5Ym1GMFpTa21KbXhqS0dVc2RDbDlablZ1WTNScGIyNGdXbVlvS1h0'
    || 'eVpYUjFjbTRnYm5Wc2JIMTJZWElnYVdNOWRIbHdaVzltSUhKbGNHOXlkRVZ5Y205eVBUMGlablZ1WTNScGIyNGlQM0psY0c5eWRFVnljbTl5T21aMWJtTjBh'
    || 'Vzl1S0dVcGUyTnZibk52YkdVdVpYSnliM0lvWlNsOU8yWjFibU4wYVc5dUlFdHZLR1VwZTNSb2FYTXVYMmx1ZEdWeWJtRnNVbTl2ZEQxbGZVWnNMbkJ5YjNS'
    || 'dmRIbHdaUzV5Wlc1a1pYSTlTMjh1Y0hKdmRHOTBlWEJsTG5KbGJtUmxjajFtZFc1amRHbHZiaWhsS1h0MllYSWdkRDEwYUdsekxsOXBiblJsY201aGJGSnZi'
    || 'M1E3YVdZb2REMDlQVzUxYkd3cGRHaHliM2NnUlhKeWIzSW9ZeWcwTURrcEtUdEViQ2hsTEhRc2JuVnNiQ3h1ZFd4c0tYMHNSbXd1Y0hKdmRHOTBlWEJsTG5W'
    || 'dWJXOTFiblE5UzI4dWNISnZkRzkwZVhCbExuVnViVzkxYm5ROVpuVnVZM1JwYjI0b0tYdDJZWElnWlQxMGFHbHpMbDlwYm5SbGNtNWhiRkp2YjNRN2FXWW9a'
    || 'U0U5UFc1MWJHd3BlM1JvYVhNdVgybHVkR1Z5Ym1Gc1VtOXZkRDF1ZFd4c08zWmhjaUIwUFdVdVkyOXVkR0ZwYm1WeVNXNW1ienRtYmlobWRXNWpkR2x2Ymln'
    || 'cGUwUnNLRzUxYkd3c1pTeHVkV3hzTEc1MWJHd3BmU2tzZEZ0T2RGMDliblZzYkgxOU8yWjFibU4wYVc5dUlFWnNLR1VwZTNSb2FYTXVYMmx1ZEdWeWJtRnNV'
    || 'bTl2ZEQxbGZVWnNMbkJ5YjNSdmRIbHdaUzUxYm5OMFlXSnNaVjl6WTJobFpIVnNaVWg1WkhKaGRHbHZiajFtZFc1amRHbHZiaWhsS1h0cFppaGxLWHQyWVhJ'
    || 'Z2REMVdjeWdwTzJVOWUySnNiMk5yWldSUGJqcHVkV3hzTEhSaGNtZGxkRHBsTEhCeWFXOXlhWFI1T25SOU8yWnZjaWgyWVhJZ2JqMHdPMjQ4VlhRdWJHVnVa'
    || 'M1JvSmlaMElUMDlNQ1ltZER4VmRGdHVYUzV3Y21sdmNtbDBlVHR1S3lzcE8xVjBMbk53YkdsalpTaHVMREFzWlNrc2JqMDlQVEFtSmxGektHVXBmWDA3Wm5W'
    || 'dVkzUnBiMjRnV1c4b1pTbDdjbVYwZFhKdUlTZ2haWHg4WlM1dWIyUmxWSGx3WlNFOVBURW1KbVV1Ym05a1pWUjVjR1VoUFQwNUppWmxMbTV2WkdWVWVYQmxJ'
    || 'VDA5TVRFcGZXWjFibU4wYVc5dUlFRnNLR1VwZTNKbGRIVnliaUVvSVdWOGZHVXVibTlrWlZSNWNHVWhQVDB4SmlabExtNXZaR1ZVZVhCbElUMDlPU1ltWlM1'
    || 'dWIyUmxWSGx3WlNFOVBURXhKaVlvWlM1dWIyUmxWSGx3WlNFOVBUaDhmR1V1Ym05a1pWWmhiSFZsSVQwOUlpQnlaV0ZqZEMxdGIzVnVkQzF3YjJsdWRDMTFi'
    || 'bk4wWVdKc1pTQWlLU2w5Wm5WdVkzUnBiMjRnYjJNb0tYdDlablZ1WTNScGIyNGdjV1lvWlN4MExHNHNjaXhzS1h0cFppaHNLWHRwWmloMGVYQmxiMllnY2ow'
    || 'OUltWjFibU4wYVc5dUlpbDdkbUZ5SUdrOWNqdHlQV1oxYm1OMGFXOXVLQ2w3ZG1GeUlHYzllbXdvY3lrN2FTNWpZV3hzS0djcGZYMTJZWElnY3oxeVl5aDBM'
    || 'SElzWlN3d0xHNTFiR3dzSVRFc0lURXNJaUlzYjJNcE8zSmxkSFZ5YmlCbExsOXlaV0ZqZEZKdmIzUkRiMjUwWVdsdVpYSTljeXhsVzA1MFhUMXpMbU4xY25K'
    || 'bGJuUXNabklvWlM1dWIyUmxWSGx3WlQwOVBUZy9aUzV3WVhKbGJuUk9iMlJsT21VcExHWnVLQ2tzYzMxbWIzSW9PMnc5WlM1c1lYTjBRMmhwYkdRN0tXVXVj'
    || 'bVZ0YjNabFEyaHBiR1FvYkNrN2FXWW9kSGx3Wlc5bUlISTlQU0ptZFc1amRHbHZiaUlwZTNaaGNpQmhQWEk3Y2oxbWRXNWpkR2x2YmlncGUzWmhjaUJuUFhw'
    || 'c0tHWXBPMkV1WTJGc2JDaG5LWDE5ZG1GeUlHWTlVVzhvWlN3d0xDRXhMRzUxYkd3c2JuVnNiQ3doTVN3aE1Td2lJaXh2WXlrN2NtVjBkWEp1SUdVdVgzSmxZ'
    || 'V04wVW05dmRFTnZiblJoYVc1bGNqMW1MR1ZiVG5SZFBXWXVZM1Z5Y21WdWRDeG1jaWhsTG01dlpHVlVlWEJsUFQwOU9EOWxMbkJoY21WdWRFNXZaR1U2WlNr'
    || 'c1ptNG9ablZ1WTNScGIyNG9LWHRFYkNoMExHWXNiaXh5S1gwcExHWjlablZ1WTNScGIyNGdWV3dvWlN4MExHNHNjaXhzS1h0MllYSWdhVDF1TGw5eVpXRmpk'
    || 'Rkp2YjNSRGIyNTBZV2x1WlhJN2FXWW9hU2w3ZG1GeUlITTlhVHRwWmloMGVYQmxiMllnYkQwOUltWjFibU4wYVc5dUlpbDdkbUZ5SUdFOWJEdHNQV1oxYm1O'
    || 'MGFXOXVLQ2w3ZG1GeUlHWTllbXdvY3lrN1lTNWpZV3hzS0dZcGZYMUViQ2gwTEhNc1pTeHNLWDFsYkhObElITTljV1lvYml4MExHVXNiQ3h5S1R0eVpYUjFj'
    || 'bTRnZW13b2N5bDlKSE05Wm5WdVkzUnBiMjRvWlNsN2MzZHBkR05vS0dVdWRHRm5LWHRqWVhObElETTZkbUZ5SUhROVpTNXpkR0YwWlU1dlpHVTdhV1lvZEM1'
    || 'amRYSnlaVzUwTG0xbGJXOXBlbVZrVTNSaGRHVXVhWE5FWldoNVpISmhkR1ZrS1h0MllYSWdiajF4YmloMExuQmxibVJwYm1kTVlXNWxjeWs3YmlFOVBUQW1K'
    || 'aWhuYVNoMExHNThNU2tzVm1Vb2RDeG9aU2dwS1N3b1N5WTJLVDA5UFRBbUppaEliajFvWlNncEt6VXdNQ3hSZENncEtTbDlZbkpsWVdzN1kyRnpaU0F4TXpw'
    || 'bWJpaG1kVzVqZEdsdmJpZ3BlM1poY2lCeVBWSjBLR1VzTVNrN2FXWW9jaUU5UFc1MWJHd3BlM1poY2lCc1BVbGxLQ2s3YlhRb2NpeGxMREVzYkNsOWZTa3NS'
    || 'MjhvWlN3eEtYMTlMSGxwUFdaMWJtTjBhVzl1S0dVcGUybG1LR1V1ZEdGblBUMDlNVE1wZTNaaGNpQjBQVkowS0dVc01UTTBNakUzTnpJNEtUdHBaaWgwSVQw'
    || 'OWJuVnNiQ2w3ZG1GeUlHNDlTV1VvS1R0dGRDaDBMR1VzTVRNME1qRTNOekk0TEc0cGZVZHZLR1VzTVRNME1qRTNOekk0S1gxOUxFaHpQV1oxYm1OMGFXOXVL'
    || 'R1VwZTJsbUtHVXVkR0ZuUFQwOU1UTXBlM1poY2lCMFBYRjBLR1VwTEc0OVVuUW9aU3gwS1R0cFppaHVJVDA5Ym5Wc2JDbDdkbUZ5SUhJOVNXVW9LVHR0ZENo'
    || 'dUxHVXNkQ3h5S1gxSGJ5aGxMSFFwZlgwc1ZuTTlablZ1WTNScGIyNG9LWHR5WlhSMWNtNGdkR1Y5TEZkelBXWjFibU4wYVc5dUtHVXNkQ2w3ZG1GeUlHNDlk'
    || 'R1U3ZEhKNWUzSmxkSFZ5YmlCMFpUMWxMSFFvS1gxbWFXNWhiR3g1ZTNSbFBXNTlmU3hqYVQxbWRXNWpkR2x2YmlobExIUXNiaWw3YzNkcGRHTm9LSFFwZTJO'
    || 'aGMyVWlhVzV3ZFhRaU9tbG1LRzVwS0dVc2Jpa3NkRDF1TG01aGJXVXNiaTUwZVhCbFBUMDlJbkpoWkdsdklpWW1kQ0U5Ym5Wc2JDbDdabTl5S0c0OVpUdHVM'
    || 'bkJoY21WdWRFNXZaR1U3S1c0OWJpNXdZWEpsYm5ST2IyUmxPMlp2Y2lodVBXNHVjWFZsY25sVFpXeGxZM1J2Y2tGc2JDZ2lhVzV3ZFhSYmJtRnRaVDBpSzBw'
    || 'VFQwNHVjM1J5YVc1bmFXWjVLQ0lpSzNRcEt5ZGRXM1I1Y0dVOUluSmhaR2x2SWwwbktTeDBQVEE3ZER4dUxteGxibWQwYUR0MEt5c3BlM1poY2lCeVBXNWJk'
    || 'RjA3YVdZb2NpRTlQV1VtSm5JdVptOXliVDA5UFdVdVptOXliU2w3ZG1GeUlHdzlibXdvY2lrN2FXWW9JV3dwZEdoeWIzY2dSWEp5YjNJb1l5ZzVNQ2twTzNC'
    || 'ektISXBMRzVwS0hJc2JDbDlmWDFpY21WaGF6dGpZWE5sSW5SbGVIUmhjbVZoSWpwNWN5aGxMRzRwTzJKeVpXRnJPMk5oYzJVaWMyVnNaV04wSWpwMFBXNHVk'
    || 'bUZzZFdVc2RDRTliblZzYkNZbWVXNG9aU3doSVc0dWJYVnNkR2x3YkdVc2RDd2hNU2w5ZlN4RGN6MVZieXhVY3oxbWJqdDJZWElnU21ZOWUzVnphVzVuUTJ4'
    || 'cFpXNTBSVzUwY25sUWIybHVkRG9oTVN4RmRtVnVkSE02VzIxeUxGUnVMRzVzTEU1ekxHcHpMRlZ2WFgwc1VuSTllMlpwYm1SR2FXSmxja0o1U0c5emRFbHVj'
    || 'M1JoYm1ObE9uSnVMR0oxYm1Sc1pWUjVjR1U2TUN4MlpYSnphVzl1T2lJeE9DNHpMakVpTEhKbGJtUmxjbVZ5VUdGamEyRm5aVTVoYldVNkluSmxZV04wTFdS'
    || 'dmJTSjlMR0ptUFh0aWRXNWtiR1ZVZVhCbE9sSnlMbUoxYm1Sc1pWUjVjR1VzZG1WeWMybHZianBTY2k1MlpYSnphVzl1TEhKbGJtUmxjbVZ5VUdGamEyRm5a'
    || 'VTVoYldVNlVuSXVjbVZ1WkdWeVpYSlFZV05yWVdkbFRtRnRaU3h5Wlc1a1pYSmxja052Ym1acFp6cFNjaTV5Wlc1a1pYSmxja052Ym1acFp5eHZkbVZ5Y21s'
    || 'a1pVaHZiMnRUZEdGMFpUcHVkV3hzTEc5MlpYSnlhV1JsU0c5dmExTjBZWFJsUkdWc1pYUmxVR0YwYURwdWRXeHNMRzkyWlhKeWFXUmxTRzl2YTFOMFlYUmxV'
    || 'bVZ1WVcxbFVHRjBhRHB1ZFd4c0xHOTJaWEp5YVdSbFVISnZjSE02Ym5Wc2JDeHZkbVZ5Y21sa1pWQnliM0J6UkdWc1pYUmxVR0YwYURwdWRXeHNMRzkyWlhK'
    || 'eWFXUmxVSEp2Y0hOU1pXNWhiV1ZRWVhSb09tNTFiR3dzYzJWMFJYSnliM0pJWVc1a2JHVnlPbTUxYkd3c2MyVjBVM1Z6Y0dWdWMyVklZVzVrYkdWeU9tNTFi'
    || 'R3dzYzJOb1pXUjFiR1ZWY0dSaGRHVTZiblZzYkN4amRYSnlaVzUwUkdsemNHRjBZMmhsY2xKbFpqcG5aUzVTWldGamRFTjFjbkpsYm5SRWFYTndZWFJqYUdW'
    || 'eUxHWnBibVJJYjNOMFNXNXpkR0Z1WTJWQ2VVWnBZbVZ5T21aMWJtTjBhVzl1S0dVcGUzSmxkSFZ5YmlCbFBWQnpLR1VwTEdVOVBUMXVkV3hzUDI1MWJHdzZa'
    || 'UzV6ZEdGMFpVNXZaR1Y5TEdacGJtUkdhV0psY2tKNVNHOXpkRWx1YzNSaGJtTmxPbEp5TG1acGJtUkdhV0psY2tKNVNHOXpkRWx1YzNSaGJtTmxmSHhhWml4'
    || 'bWFXNWtTRzl6ZEVsdWMzUmhibU5sYzBadmNsSmxabkpsYzJnNmJuVnNiQ3h6WTJobFpIVnNaVkpsWm5KbGMyZzZiblZzYkN4elkyaGxaSFZzWlZKdmIzUTZi'
    || 'blZzYkN4elpYUlNaV1p5WlhOb1NHRnVaR3hsY2pwdWRXeHNMR2RsZEVOMWNuSmxiblJHYVdKbGNqcHVkV3hzTEhKbFkyOXVZMmxzWlhKV1pYSnphVzl1T2lJ'
    || 'eE9DNHpMakV0Ym1WNGRDMW1NVE16T0dZNE1EZ3dMVEl3TWpRd05ESTJJbjA3YVdZb2RIbHdaVzltSUY5ZlVrVkJRMVJmUkVWV1ZFOVBURk5mUjB4UFFrRk1Y'
    || 'MGhQVDB0Zlh6d2lkU0lwZTNaaGNpQWtiRDFmWDFKRlFVTlVYMFJGVmxSUFQweFRYMGRNVDBKQlRGOUlUMDlMWDE4N2FXWW9JU1JzTG1selJHbHpZV0pzWldR'
    || 'bUppUnNMbk4xY0hCdmNuUnpSbWxpWlhJcGRISjVlMFp5UFNSc0xtbHVhbVZqZENoaVppa3NlSFE5Skd4OVkyRjBZMmg3ZlgxeVpYUjFjbTRnUkdVdVgxOVRS'
    || 'VU5TUlZSZlNVNVVSVkpPUVV4VFgwUlBYMDVQVkY5VlUwVmZUMUpmV1U5VlgxZEpURXhmUWtWZlJrbFNSVVE5U21Zc1JHVXVZM0psWVhSbFVHOXlkR0ZzUFda'
    || 'MWJtTjBhVzl1S0dVc2RDbDdkbUZ5SUc0OU1qeGhjbWQxYldWdWRITXViR1Z1WjNSb0ppWmhjbWQxYldWdWRITmJNbDBoUFQxMmIybGtJREEvWVhKbmRXMWxi'
    || 'blJ6V3pKZE9tNTFiR3c3YVdZb0lWbHZLSFFwS1hSb2NtOTNJRVZ5Y205eUtHTW9NakF3S1NrN2NtVjBkWEp1SUZobUtHVXNkQ3h1ZFd4c0xHNHBmU3hFWlM1'
    || 'amNtVmhkR1ZTYjI5MFBXWjFibU4wYVc5dUtHVXNkQ2w3YVdZb0lWbHZLR1VwS1hSb2NtOTNJRVZ5Y205eUtHTW9Nams1S1NrN2RtRnlJRzQ5SVRFc2NqMGlJ'
    || 'aXhzUFdsak8zSmxkSFZ5YmlCMElUMXVkV3hzSmlZb2RDNTFibk4wWVdKc1pWOXpkSEpwWTNSTmIyUmxQVDA5SVRBbUppaHVQU0V3S1N4MExtbGtaVzUwYVda'
    || 'cFpYSlFjbVZtYVhnaFBUMTJiMmxrSURBbUppaHlQWFF1YVdSbGJuUnBabWxsY2xCeVpXWnBlQ2tzZEM1dmJsSmxZMjkyWlhKaFlteGxSWEp5YjNJaFBUMTJi'
    || 'MmxrSURBbUppaHNQWFF1YjI1U1pXTnZkbVZ5WVdKc1pVVnljbTl5S1Nrc2REMVJieWhsTERFc0lURXNiblZzYkN4dWRXeHNMRzRzSVRFc2NpeHNLU3hsVzA1'
    || 'MFhUMTBMbU4xY25KbGJuUXNabklvWlM1dWIyUmxWSGx3WlQwOVBUZy9aUzV3WVhKbGJuUk9iMlJsT21VcExHNWxkeUJMYnloMEtYMHNSR1V1Wm1sdVpFUlBU'
    || 'VTV2WkdVOVpuVnVZM1JwYjI0b1pTbDdhV1lvWlQwOWJuVnNiQ2x5WlhSMWNtNGdiblZzYkR0cFppaGxMbTV2WkdWVWVYQmxQVDA5TVNseVpYUjFjbTRnWlR0'
    || 'MllYSWdkRDFsTGw5eVpXRmpkRWx1ZEdWeWJtRnNjenRwWmloMFBUMDlkbTlwWkNBd0tYUm9jbTkzSUhSNWNHVnZaaUJsTG5KbGJtUmxjajA5SW1aMWJtTjBh'
    || 'Vzl1SWo5RmNuSnZjaWhqS0RFNE9Da3BPaWhsUFU5aWFtVmpkQzVyWlhsektHVXBMbXB2YVc0b0lpd2lLU3hGY25KdmNpaGpLREkyT0N4bEtTa3BPM0psZEhW'
    || 'eWJpQmxQVkJ6S0hRcExHVTlaVDA5UFc1MWJHdy9iblZzYkRwbExuTjBZWFJsVG05a1pTeGxmU3hFWlM1bWJIVnphRk41Ym1NOVpuVnVZM1JwYjI0b1pTbDdj'
    || 'bVYwZFhKdUlHWnVLR1VwZlN4RVpTNW9lV1J5WVhSbFBXWjFibU4wYVc5dUtHVXNkQ3h1S1h0cFppZ2hRV3dvZENrcGRHaHliM2NnUlhKeWIzSW9ZeWd5TURB'
    || 'cEtUdHlaWFIxY200Z1ZXd29iblZzYkN4bExIUXNJVEFzYmlsOUxFUmxMbWg1WkhKaGRHVlNiMjkwUFdaMWJtTjBhVzl1S0dVc2RDeHVLWHRwWmlnaFdXOG9a'
    || 'U2twZEdoeWIzY2dSWEp5YjNJb1l5ZzBNRFVwS1R0MllYSWdjajF1SVQxdWRXeHNKaVp1TG1oNVpISmhkR1ZrVTI5MWNtTmxjM3g4Ym5Wc2JDeHNQU0V4TEdr'
    || 'OUlpSXNjejFwWXp0cFppaHVJVDF1ZFd4c0ppWW9iaTUxYm5OMFlXSnNaVjl6ZEhKcFkzUk5iMlJsUFQwOUlUQW1KaWhzUFNFd0tTeHVMbWxrWlc1MGFXWnBa'
    || 'WEpRY21WbWFYZ2hQVDEyYjJsa0lEQW1KaWhwUFc0dWFXUmxiblJwWm1sbGNsQnlaV1pwZUNrc2JpNXZibEpsWTI5MlpYSmhZbXhsUlhKeWIzSWhQVDEyYjJs'
    || 'a0lEQW1KaWh6UFc0dWIyNVNaV052ZG1WeVlXSnNaVVZ5Y205eUtTa3NkRDF5WXloMExHNTFiR3dzWlN3eExHNC9QMjUxYkd3c2JDd2hNU3hwTEhNcExHVmJU'
    || 'blJkUFhRdVkzVnljbVZ1ZEN4bWNpaGxLU3h5S1dadmNpaGxQVEE3WlR4eUxteGxibWQwYUR0bEt5c3BiajF5VzJWZExHdzliaTVmWjJWMFZtVnljMmx2Yml4'
    || 'c1BXd29iaTVmYzI5MWNtTmxLU3gwTG0xMWRHRmliR1ZUYjNWeVkyVkZZV2RsY2toNVpISmhkR2x2YmtSaGRHRTlQVzUxYkd3L2RDNXRkWFJoWW14bFUyOTFj'
    || 'bU5sUldGblpYSkllV1J5WVhScGIyNUVZWFJoUFZ0dUxHeGRPblF1YlhWMFlXSnNaVk52ZFhKalpVVmhaMlZ5U0hsa2NtRjBhVzl1UkdGMFlTNXdkWE5vS0c0'
    || 'c2JDazdjbVYwZFhKdUlHNWxkeUJHYkNoMEtYMHNSR1V1Y21WdVpHVnlQV1oxYm1OMGFXOXVLR1VzZEN4dUtYdHBaaWdoUVd3b2RDa3BkR2h5YjNjZ1JYSnli'
    || 'M0lvWXlneU1EQXBLVHR5WlhSMWNtNGdWV3dvYm5Wc2JDeGxMSFFzSVRFc2JpbDlMRVJsTG5WdWJXOTFiblJEYjIxd2IyNWxiblJCZEU1dlpHVTlablZ1WTNS'
    || 'cGIyNG9aU2w3YVdZb0lVRnNLR1VwS1hSb2NtOTNJRVZ5Y205eUtHTW9OREFwS1R0eVpYUjFjbTRnWlM1ZmNtVmhZM1JTYjI5MFEyOXVkR0ZwYm1WeVB5aG1i'
    || 'aWhtZFc1amRHbHZiaWdwZTFWc0tHNTFiR3dzYm5Wc2JDeGxMQ0V4TEdaMWJtTjBhVzl1S0NsN1pTNWZjbVZoWTNSU2IyOTBRMjl1ZEdGcGJtVnlQVzUxYkd3'
    || 'c1pWdE9kRjA5Ym5Wc2JIMHBmU2tzSVRBcE9pRXhmU3hFWlM1MWJuTjBZV0pzWlY5aVlYUmphR1ZrVlhCa1lYUmxjejFWYnl4RVpTNTFibk4wWVdKc1pWOXla'
    || 'VzVrWlhKVGRXSjBjbVZsU1c1MGIwTnZiblJoYVc1bGNqMW1kVzVqZEdsdmJpaGxMSFFzYml4eUtYdHBaaWdoUVd3b2Jpa3BkR2h5YjNjZ1JYSnliM0lvWXln'
    || 'eU1EQXBLVHRwWmlobFBUMXVkV3hzZkh4bExsOXlaV0ZqZEVsdWRHVnlibUZzY3owOVBYWnZhV1FnTUNsMGFISnZkeUJGY25KdmNpaGpLRE00S1NrN2NtVjBk'
    || 'WEp1SUZWc0tHVXNkQ3h1TENFeExISXBmU3hFWlM1MlpYSnphVzl1UFNJeE9DNHpMakV0Ym1WNGRDMW1NVE16T0dZNE1EZ3dMVEl3TWpRd05ESTJJaXhFWlgx'
    || 'MllYSWdibk03Wm5WdVkzUnBiMjRnYUdNb0tYdHBaaWh1Y3lseVpYUjFjbTRnVVd3dVpYaHdiM0owY3p0dWN6MHhPMloxYm1OMGFXOXVJSFVvS1h0cFppZ2hL'
    || 'SFI1Y0dWdlppQmZYMUpGUVVOVVgwUkZWbFJQVDB4VFgwZE1UMEpCVEY5SVQwOUxYMTgrSW5VaWZIeDBlWEJsYjJZZ1gxOVNSVUZEVkY5RVJWWlVUMDlNVTE5'
    || 'SFRFOUNRVXhmU0U5UFMxOWZMbU5vWldOclJFTkZJVDBpWm5WdVkzUnBiMjRpS1NsMGNubDdYMTlTUlVGRFZGOUVSVlpVVDA5TVUxOUhURTlDUVV4ZlNFOVBT'
    || 'MTlmTG1Ob1pXTnJSRU5GS0hVcGZXTmhkR05vS0dRcGUyTnZibk52YkdVdVpYSnliM0lvWkNsOWZYSmxkSFZ5YmlCMUtDa3NVV3d1Wlhod2IzSjBjejF3WXln'
    || 'cExGRnNMbVY0Y0c5eWRITjlkbUZ5SUhKek8yWjFibU4wYVc5dUlHMWpLQ2w3YVdZb2NuTXBjbVYwZFhKdUlFeHlPM0p6UFRFN2RtRnlJSFU5YUdNb0tUdHla'
    || 'WFIxY200Z1RISXVZM0psWVhSbFVtOXZkRDExTG1OeVpXRjBaVkp2YjNRc1RISXVhSGxrY21GMFpWSnZiM1E5ZFM1b2VXUnlZWFJsVW05dmRDeE1jbjEyWVhJ'
    || 'Z2RtTTliV01vS1R0amIyNXpkQ0JuWXowaVgxOUVSVXhGUjE5RVFWUkJYMThpTEhsalBYdGpiMjUwWlhoME9udDlMSEJoYm1Wc2N6cDdmU3htWVhSaGJEb2lU'
    || 'bThnWkdGMFlTQndZWGxzYjJGa0lIZGhjeUJwYm1wbFkzUmxaQzRnVkdocGN5QmlkV2xzWkNCdlppQjBhR1VnWVhCd0lHbHpJR0p5YjJ0bGJqc2djbVV0Y25W'
    || 'dUlHaGhjbTVsYzNNdVluVnVaR3hsSUdGdVpDQnlaV0oxYVd4a0xpSjlPMloxYm1OMGFXOXVJSGhqS0hVOVoyTXBlMk52Ym5OMElHUTlkMmx1Wkc5M1czVmRP'
    || 'MmxtS0NGa2ZIeDBlWEJsYjJZZ1pDRTlJbTlpYW1WamRDSXBjbVYwZFhKdUlIbGpPMk52Ym5OMElHTTlaRHR5WlhSMWNtNTdZMjl1ZEdWNGREcGpMbU52Ym5S'
    || 'bGVIUS9QM3Q5TEhCaGJtVnNjenBqTG5CaGJtVnNjejgvZTMwc1ptRjBZV3c2WXk1bVlYUmhiQ3hqZFhOMGIyMXBlbUYwYVc5dU9tTXVZM1Z6ZEc5dGFYcGhk'
    || 'R2x2Yml4amRYTjBiMjFwZW1GMGFXOXVYMlZ5Y205eU9tTXVZM1Z6ZEc5dGFYcGhkR2x2Ymw5bGNuSnZjaXh1WVhacFoyRjBhVzl1T21NdWJtRjJhV2RoZEds'
    || 'dmJuMTlablZ1WTNScGIyNGdkbTRvZFNsN2NtVjBkWEp1SVNGMUppWWlaWEp5YjNJaWFXNGdkWDFtZFc1amRHbHZiaUIzWXloMUtYdHlaWFIxY200Z2RTWW1J'
    || 'bkp2ZDNNaWFXNGdkU1ltZFM1MGNuVnVZMkYwWldRL2RTNTBjblZ1WTJGMFpXUTZNSDFtZFc1amRHbHZiaUJuYmloMUtYdHlaWFIxY200aGRYeDhJU2dpWlhK'
    || 'eWIzSWlhVzRnZFNrL0lURTZMMlJ2WlhNZ2JtOTBJR1Y0YVhOMElHOXlJRzV2ZENCaGRYUm9iM0pwZW1Wa0wya3VkR1Z6ZENoMUxtVnljbTl5S1gxbWRXNWpk'
    || 'R2x2YmlCdmRDaDFMR1FwZTJOdmJuTjBJR005ZFM1d1lXNWxiSE5iWkYwN2NtVjBkWEp1SUdNbUppSnliM2R6SW1sdUlHTS9ZeTV5YjNkek9sdGRmV1oxYm1O'
    || 'MGFXOXVJRWwwS0hVcGUybG1LSFI1Y0dWdlppQjFQVDBpYm5WdFltVnlJaWx5WlhSMWNtNGdUblZ0WW1WeUxtbHpSbWx1YVhSbEtIVXBQM1U2Ym5Wc2JEdHBa'
    || 'aWgwZVhCbGIyWWdkU0U5SW5OMGNtbHVaeUlwY21WMGRYSnVJRzUxYkd3N1kyOXVjM1FnWkQxMUxuUnlhVzBvS1R0cFppaGtQVDA5SWlKOGZDRXZYbHNyTFYw'
    || 'L0tGeGtLMXd1UDF4a0tueGNMbHhrS3lrb1cyVkZYVnNyTFYwL1hHUXJLVDhrTHk1MFpYTjBLR1FwS1hKbGRIVnliaUJ1ZFd4c08yTnZibk4wSUdNOVRuVnRZ'
    || 'bVZ5S0dRcE8zSmxkSFZ5YmlCT2RXMWlaWEl1YVhOR2FXNXBkR1VvWXlrL1l6cHVkV3hzZldaMWJtTjBhVzl1SUd0bEtIVXBlMmxtS0hVOVBXNTFiR3g4ZkhV'
    || 'OVBUMGlJaWx5WlhSMWNtNGk0b0NVSWp0amIyNXpkQ0JrUFVsMEtIVXBPMmxtS0dROVBUMXVkV3hzS1hKbGRIVnliaUJUZEhKcGJtY29kU2s3YVdZb1pEMDlQ'
    || 'VEFwY21WMGRYSnVJakFpTzJOdmJuTjBJR005VFdGMGFDNWhZbk1vWkNrN2FXWW9ZencxWlMwMEtYSmxkSFZ5YmlCa1BEQS9JajRnTFRBdU1EQXhJam9pUENB'
    || 'd0xqQXdNU0k3YkdWMElIZzdjbVYwZFhKdUlHTStQVEZsTXo5NFBUQTZZejQ5TVRBd1AzZzlNVHBqUGoweFAzZzlNanA0UFRNc1pDNTBiMHh2WTJGc1pWTjBj'
    || 'bWx1WnlnaVpXNHRWVk1pTEh0dGFXNXBiWFZ0Um5KaFkzUnBiMjVFYVdkcGRITTZNQ3h0WVhocGJYVnRSbkpoWTNScGIyNUVhV2RwZEhNNmVIMHBmV1oxYm1O'
    || 'MGFXOXVJRjlqS0hVcGUyTnZibk4wSUdROVUzUnlhVzVuS0hVL1B5SWlLUzUwYjFWd2NHVnlRMkZ6WlNncExuUnlhVzBvS1R0eVpYUjFjbTRnWkQwOVBTSk5S'
    || 'VlFpZkh4a1BUMDlJazVQVkY5TlJWUWlmSHhrUFQwOUlrNHZRU0kvWkRvaVVFVk9SRWxPUnlKOVkyOXVjM1FnYzNROWRUMCtkVDA5Ym5Wc2JEOGlJanBUZEhK'
    || 'cGJtY29kU2s3Wm5WdVkzUnBiMjRnYkhNb2RTbDdjbVYwZFhKdUlHOTBLSFVzSW5CdlkxOXpZMjl5WldOaGNtUWlLUzV0WVhBb1pEMCtLSHRqYjJSbE9uTjBL'
    || 'R1F1UTA5RVJTa3NiR0ZpWld3NmMzUW9aQzVNUVVKRlRDa3NkMmg1T25OMEtHUXVWMGhaWDBsVVgwMUJWRlJGVWxNcExIUmhjbWRsZERwa0xsUkJVa2RGVkQ4'
    || 'L2JuVnNiQ3hoWTNSMVlXdzZaQzVCUTFSVlFVdy9QMjUxYkd3c2RXNXBkSE02YzNRb1pDNVZUa2xVVXlrc1kyOXRjR0Z5WlRwemRDaGtMa05QVFZCQlVrVXBM'
    || 'R0poYzJsek9uTjBLR1F1UWtGVFNWTXBMR1JsY21sMllYUnBiMjQ2YzNRb1pDNVVRVkpIUlZSZlJFVlNTVlpCVkVsUFRpa3NjM1JoZEdVNlgyTW9aQzVUVkVG'
    || 'VVJTa3NkMmg1VG05ME9uTjBLR1F1VjBoWlgwNVBWRjlGVmtGTVZVRlVSVVFwTEhKbGMyOXNkbVZ6VjJobGJqcHpkQ2hrTGxKRlUwOU1Wa1ZUWDFkSVJVNHBM'
    || 'R0Z5YVhSb2JXVjBhV002YzNRb1pDNUJVa2xVU0UxRlZFbERLU3hqYjIxd1lYSmhZbWxzYVhSNU9uTjBLR1F1UTA5TlVFRlNRVUpKVEVsVVdTbDlLU2w5Wm5W'
    || 'dVkzUnBiMjRnVTJNb2RTbDdZMjl1YzNRZ1pEMTFMbkJoYm1Wc2N5NXdiMk5mYzJOdmNtVmpZWEprTEdNOWJITW9kU2s3YVdZb2RtNG9aQ2twY21WMGRYSnVl'
    || 'MjFsZERvd0xHNXZkRTFsZERvd0xIQmxibVJwYm1jNk1DeHVZVG93TEhOamIzSmxaRG93TEdobFlXUnNhVzVsT2lMaWdKUWlMSFpsY21ScFkzUTZJazVQVkY5'
    || 'U1ZVNGlMSEpsWVdSVWFHbHpPbWR1S0dRcFB5SlVhR1VnYzJOdmNtVmpZWEprSUhacFpYZHpJSGRsY21VZ2JtOTBJR0oxYVd4MElHSjVJSFJvYVhNZ2NuVnVM'
    || 'Q0J2Y2lCMGFHbHpJSEp2YkdVZ1kyRnVibTkwSUhObFpTQjBhR1Z0TGlCVGJtOTNabXhoYTJVZ1pHOWxjeUJ1YjNRZ1pHbHpkR2x1WjNWcGMyZ2dkR2hsSUhS'
    || 'M2J5NGlPaUpVYUdVZ2MyTnZjbVZqWVhKa0lIRjFaWEo1SUdaaGFXeGxaQ3dnYzI4Z2JtOTBhR2x1WnlCb1pYSmxJR2x6SUhOamIzSmxaQzRpTEhWdVlYWmhh'
    || 'V3hoWW14bE9tUXVaWEp5YjNKOU8yTnZibk4wSUhnOVl5NW1hV3gwWlhJb1ZqMCtWaTV6ZEdGMFpUMDlQU0pOUlZRaUtTNXNaVzVuZEdnc1JUMWpMbVpwYkhS'
    || 'bGNpaFdQVDVXTG5OMFlYUmxQVDA5SWs1UFZGOU5SVlFpS1M1c1pXNW5kR2dzVkQxakxtWnBiSFJsY2loV1BUNVdMbk4wWVhSbFBUMDlJbEJGVGtSSlRrY2lL'
    || 'UzVzWlc1bmRHZ3NlVDFqTG1acGJIUmxjaWhXUFQ1V0xuTjBZWFJsUFQwOUlrNHZRU0lwTG14bGJtZDBhQ3hPUFdNdWJHVnVaM1JvTFhrc2FqMU9QVDA5TUQ4'
    || 'aVRrOVVYMUpWVGlJNlJUNHdQeUpPVDFSZlRVVlVJanA0UFQwOU1EOGlVRVZPUkVsT1J5STZWRDR3UHlKTlJWUmZWMGxVU0Y5UVJVNUVTVTVISWpvaVRVVlVJ'
    || 'aXhIUFc5MEtIVXNJbkJ2WTE5MlpYSmthV04wSWlsYk1GMHNURDFIUDFOMGNtbHVaeWhITGxaRlVrUkpRMVEvUHlJaUtUb2lJaXhHUFNFaFRDWW1UQ0U5UFdv'
    || 'N2NtVjBkWEp1ZTIxbGREcDRMRzV2ZEUxbGREcEZMSEJsYm1ScGJtYzZWQ3h1WVRwNUxITmpiM0psWkRwT0xHaGxZV1JzYVc1bE9rNDlQVDB3UHlKdWIzUWdj'
    || 'Mk52Y21Wa0lqcGdKSHQ0ZlM4a2UwNTlJRzFsZEdBc2RtVnlaR2xqZERwcUxISmxZV1JVYUdsek9rWS9ZRlJvWlNCelkyOXlaV05oY21RZ2NtOTNjeUJoYm1R'
    || 'Z2RHaGxJSEp2Ykd3dGRYQWdkbWxsZHlCa2FYTmhaM0psWlNBb2NtOTNjeUJ6WVhrZ0pIdHFmU3dnVmw5UVQwTmZWa1ZTUkVsRFZDQnpZWGx6SUNSN1RIMHBM'
    || 'aUJVY25WemRDQnVaV2wwYUdWeUlIVnVkR2xzSUhSb1lYUWdhWE1nWlhod2JHRnBibVZrTG1BNlJ6OVRkSEpwYm1jb1J5NVNSVUZFWDFSSVNWTS9QeUlpS1Rv'
    || 'aUluMTlZMjl1YzNRZ1dXdzlXeUpFU1ZORFQxWkZVaUlzSWt4SlRVbFVSVVFpTENKUVVrOUVWVU5VU1U5T0lsMHNSV005ZTBSSlUwTlBWa1ZTT2lKRWFYTmpi'
    || 'M1psY25raUxFeEpUVWxVUlVRNklreHBiV2wwWldRZ2NuVnVJaXhRVWs5RVZVTlVTVTlPT2lKUWNtOWtkV04wYVc5dUluMHNhMk05ZTBSSlUwTlBWa1ZTT2lK'
    || 'U1pXRmtjeUIwYUdVZ1lXTmpiM1Z1ZENCaGJtUWdjbVZ3YjNKMGN5QjNhR0YwSUdsMElHWnZkVzVrTGlCQmJubDBhR2x1WnlCeVpXTjFjbkpwYm1jZ2FYTWdZ'
    || 'M0psWVhSbFpDd2djbVZtY21WemFHVmtJRzl1WTJVZ2MyOGdhWFJ6SUdOdmMzUWdZMkZ1SUdKbElHMWxZWE4xY21Wa0xDQjBhR1Z1SUhOMWMzQmxibVJsWkM0'
    || 'aUxFeEpUVWxVUlVRNklsUm9aU0J6WVcxbElHSjFhV3hrSUc5dUlHRnVJR2x6YjJ4aGRHVmtJSGRoY21Wb2IzVnpaU0IzYVhSb0lHRWdjbVZ6YjNWeVkyVWdi'
    || 'Vzl1YVhSdmNpQnZkbVZ5SUdsMExDQnpieUIwYUdVZ1kzSmxaR2wwY3lCcGRDQmlkWEp1Y3lCaGNtVWdZWFIwY21saWRYUmhZbXhsSUdGdVpDQmpZVzRnWW1V'
    || 'Z2NtVmhaQ0JpWVdOcklHWnliMjBnYldWMFpYSnBibWN1SUZSb2FYTWdhWE1nZEdobElHOXViSGtnY0doaGMyVWdkR2hoZENCd2NtOWtkV05sY3lCaElHMWxZ'
    || 'WE4xY21Wa0lHNTFiV0psY2k0aUxGQlNUMFJWUTFSSlQwNDZJa1oxYkd3Z2MyTnZjR1VzSUdGdVpDQjBhR1VnY21WamRYSnlhVzVuSUc5aWFtVmpkSE1nWVhK'
    || 'bElHeGxablFnY25WdWJtbHVaeTRnUVdSa2N5QjBhR1VnYjNCbGNtRjBhVzl1WVd3Z1puVnlibWwwZFhKbElHRWdjR3hoZEdadmNtMGdkR1ZoYlNCbGVIQmxZ'
    || 'M1J6T2lCdGIyNXBkRzl5TENCaWRXUm5aWFFzSUc5aWFtVmpkQ0IwWVdkekxDQmxjbkp2Y2lCdWIzUnBabWxqWVhScGIyNHNJSEpsWm5KbGMyZ2dVMHhCTENC'
    || 'aGJpQnZjR1Z5WVhScGIyNXpJSFpwWlhjdUluMDdablZ1WTNScGIyNGdhWE1vZFN4a0tYdHlaWFIxY200Z2RUMDlQVzUxYkd4OGZHUTlQVDF1ZFd4c2ZIeDFQ'
    || 'VDA5TUQ4aUlqb2lmaVFpSzJ0bEtIVXFaQ2w5Wm5WdVkzUnBiMjRnVG1Nb2RTbDdZMjl1YzNRZ1pEMVRkSEpwYm1jb2RTNVVTVVZTUHo4aUlpa3VkRzlWY0hC'
    || 'bGNrTmhjMlVvS1N4alBWbHNMbWx1WTJ4MVpHVnpLR1FwUDJRNklrUkpVME5QVmtWU0lpeDRQVmxzTG1sdVpHVjRUMllvWXlrc1JUMUpkQ2gxTGxKQlZFVmZV'
    || 'RVZTWDBOU1JVUkpWQ2tzVkQxSmRDaDFMa05TUlVSSlZGOURRVkFwTEhrOVNYUW9kUzVUVkVGT1JFbE9SMTlEVWtWRVNWUlRYMUJGVWw5TlQwNVVTQ2tzVGox'
    || 'SmRDaDFMbE5EU0VWRVZVeEZSRjlEVDAxUVQwNUZUbFJUS1Q4L01DeHFQVWwwS0hVdVZrOU1WVTFGWDBOUFRWQlBUa1ZPVkZNcFB6OHdMRWM5YWo0d1AyQWdL'
    || 'eUFrZTJwOUlIWnZiSFZ0WlMxa2NtbDJaVzVnT2lJaU8yeGxkQ0JNTEVZN1RqNHdKaVo1SVQwOWJuVnNiQ1ltZVQ0d1B5aE1QV0IrSkh0clpTaDVLWDBnWTNK'
    || 'bFpHbDBjeTl0YjI1MGFDUjdSMzFnTEVZOUluQnliMnBsWTNSbFpDQm1jbTl0SUhSb1pTQmpZV1JsYm1ObElIUm9hWE1nWW5WcGJHUWdjMlYwSUdGdVpDQjBh'
    || 'R1VnWkhWeVlYUnBiMjRnYVhRZ2JXVmhjM1Z5WldRdUlFNXZkQ0JoSUdKcGJHd3VJaXNvYWo0d1B5SWdWR2hsSUhadmJIVnRaUzFrY21sMlpXNGdZMjl0Y0c5'
    || 'dVpXNTBjeUJvWVhabElHNXZJRzF2Ym5Sb2JIa2dabWxuZFhKbElHRjBJR0ZzYkRzZ2RHaGxhWElnWTI5emRDQnpZMkZzWlhNZ2QybDBhQ0JvYjNjZ2JYVmph'
    || 'Q0JrWVhSaElIbHZkU0J6Wlc1a0xpSTZJaUlwS1RwT1BqQS9LRXc5WUNSN1RuMGdjMk5vWldSMWJHVmtJR052YlhCdmJtVnVkQ1I3VGowOVBURS9JaUk2SW5N'
    || 'aWZTUjdSMzFnTEVZOVl6MDlQU0pRVWs5RVZVTlVTVTlPSWo4aWNtVm5hWE4wWlhKbFpDQnZiaUJoSUhOamFHVmtkV3hsTENCaWRYUWdkR2hsSUhKbFkyOXla'
    || 'R1ZrSUdOaFpHVnVZMlVnYVhNZ2VtVnlieXdnYzI4Z2JtOGdiVzl1ZEdoc2VTQm1hV2QxY21VZ1kyRnVJR0psSUdSbGNtbDJaV1F1SUZSeVpXRjBJSFJvYVhN'
    || 'Z1lYTWdkVzVyYm05M2Jpd2dibTkwSUdGeklHWnlaV1V1SWpvaWRHaGxJSEpsWTNWeWNtbHVaeUJ2WW1wbFkzUnpJR0Z5WlNCcGJuTjBZV3hzWldRZ1lXNWtJ'
    || 'SE4xYzNCbGJtUmxaQ0JoZENCMGFHbHpJSFJwWlhJc0lITnZJRzV2SUdOaFpHVnVZMlVnYVhNZ2IyNGdjbVZqYjNKa0lIUnZJSEJ5YjJwbFkzUWdabkp2YlM0'
    || 'Z1ZHaHBjeUJwY3lCT1QxUWdlbVZ5YnlBdExTQmlkV2xzWkNCaGRDQlFVazlFVlVOVVNVOU9JSFJ2SUdkbGRDQjBhR1VnYldWaGMzVnlaV1FnYlc5dWRHaHNl'
    || 'U0JtYVdkMWNtVXVJaWs2YWo0d1B5aE1QV0FrZTJwOUlIWnZiSFZ0WlMxa2NtbDJaVzRnWTI5dGNHOXVaVzUwSkh0cVBUMDlNVDhpSWpvaWN5SjlZQ3hHUFNK'
    || 'dWJ5QmpZV1JsYm1ObExDQnpieUJ1YnlCdGIyNTBhR3g1SUhCeWIycGxZM1JwYjI0Z2FYTWdjRzl6YzJsaWJHVXVJRlJvYVhNZ2FYTWdUazlVSUhwbGNtOGdM'
    || 'UzBnZEdobElHTnZjM1FnYzJOaGJHVnpJSGRwZEdnZ2FHOTNJRzExWTJnZ1pHRjBZU0I1YjNVZ2MyVnVaQzRpS1Rvb1REMGlibTkwYUdsdVp5QnlaV04xY25K'
    || 'cGJtY2lMRVk5SW5Sb2FYTWdjMjlzZFhScGIyNGdhVzV6ZEdGc2JITWdibTkwYUdsdVp5QnZiaUJoSUhOamFHVmtkV3hsTGlCSmRDQmpiM04wY3lCemRHOXlZ'
    || 'V2RsSUhCc2RYTWdkMmhoZEdWMlpYSWdZMjl0Y0hWMFpTQjBhR1VnY0dWdmNHeGxJSEYxWlhKNWFXNW5JR2wwSUhWelpTNGlLVHRqYjI1emRDQldQWHRFU1ZO'
    || 'RFQxWkZVanA3Wm1sbmRYSmxPaUl3SUdOeVpXUnBkSE12Ylc5dWRHZ2lMRzF2Ym1WNU9pSWlMR0poYzJsek9pSnViM1JvYVc1bklHbHpJR3hsWm5RZ2NuVnVi'
    || 'bWx1Wnl3Z2MyOGdibTkwYUdsdVp5QnlaV04xY25NdUlGUm9aU0J2Ym1VdGRHbHRaU0J5WldGa0lHbDBjMlZzWmlCcGN5QmhJR2hoYm1SbWRXd2diMllnY1hW'
    || 'bGNtbGxjeTRpZlN4TVNVMUpWRVZFT250bWFXZDFjbVU2VkNZbVZENHdQMkRpaWFRZ0pIdHJaU2hVS1gwZ1kzSmxaR2wwY3lCdmJtVXRkR2x0WldBNkltNXZJ'
    || 'R05oY0NCelpYUWlMRzF2Ym1WNU9sUW1KbFErTUQ5cGN5aFVMRVVwT2lJaUxHSmhjMmx6T2xRbUpsUStNRDhpWVc0Z1pXNW1iM0pqWldRZ1kyVnBiR2x1Wnl3'
    || 'Z2JtOTBJR0Z1SUdWemRHbHRZWFJsT2lCaElISmxjMjkxY21ObElHMXZibWwwYjNJZ2MzVnpjR1Z1WkhNZ2RHaGxJSGRoY21Wb2IzVnpaU0IzYUdWdUlHbDBJ'
    || 'R2x6SUhKbFlXTm9aV1F1SUVsMElHZHZkbVZ5Ym5NZ1YwRlNSVWhQVlZORklHTnlaV1JwZEhNZ2IyNXNlU0F0TFNCdWIzUWdjMlZ5ZG1WeWJHVnpjeUJtWldG'
    || 'MGRYSmxjeUJoYm1RZ2JtOTBJRUZKSUhSdmEyVnVjeTRpT2lKRFVrVkVTVlJmUTBGUUlHbHpJREFzSUhOdklIUm9aWEpsSUdseklHNXZJR1Z1Wm05eVkyVmtJ'
    || 'R05sYVd4cGJtY2diMjRnZEdocGN5QnlkVzR1SW4wc1VGSlBSRlZEVkVsUFRqcDdabWxuZFhKbE9rd3NiVzl1WlhrNmFYTW9lU3hGS1N4aVlYTnBjenBHZlgw'
    || 'c2RXVTlVM1J5YVc1bktIVXVVMFZVVkVsT1IxOVFVa1ZHU1ZnL1B5SWlLUzUwY21sdEtDazdjbVYwZFhKdUlGbHNMbTFoY0Nnb1NpeGlLVDArS0h0cFpEcEtM'
    || 'R3hoWW1Wc09rVmpXMHBkTEhOMFlYUmxPbUk4ZUQ4aVpHOXVaU0k2WWowOVBYZy9JbU4xY25KbGJuUWlPaUpoYUdWaFpDSXNMaTR1Vmx0S1hTeGliSFZ5WWpw'
    || 'clkxdEtYU3h6WlhSMGFXNW5PblZsUDJCVFJWUWdKSHQxWlgxZlJFVlFURTlaWDFSSlJWSWdQU0FuSkh0S2ZTYzdZRHBnVTBWVUlEeHdjbVZtYVhnK1gwUkZV'
    || 'RXhQV1Y5VVNVVlNJRDBnSnlSN1NuMG5PMkI5S1NsOVpuVnVZM1JwYjI0Z2FtTW9lM05wZW1VNmRUMHhPU3hqYjJ4dmNqcGtQU0lqTWpsaU5XVTRJbjBwZTNK'
    || 'bGRIVnliaUJ2TG1wemVITW9Jbk4yWnlJc2UzZHBaSFJvT25Vc2FHVnBaMmgwT25Vc2RtbGxkMEp2ZURvaU1DQXdJRFF6TGpRZ05ETXVOU0lzWm1sc2JEcGtM'
    || 'SEp2YkdVNkltbHRaeUlzSW1GeWFXRXRiR0ZpWld3aU9pSlRibTkzWm14aGEyVWlMR05vYVd4a2NtVnVPbHR2TG1wemVDZ2ljR0YwYUNJc2UyUTZJazB6Tnk0'
    || 'eU5qTTNORFkxTERNekxqRXlPRGt3TmlCTU1qZ3VNRGczT1RZMU5Td3lOeTQ0TWpneE1qVWdRekkyTGpjNU9Ea3dNalVzTWpjdU1EZzFPVE00SURJMUxqRTFN'
    || 'RFEyTlRVc01qY3VOVEkzTXpRMElESTBMalF3TkRNM01UVXNNamd1T0RFMk5EQTJJRU15TkM0eE1UVXpNRGcxTERJNUxqTXlOREl4T1NBeU5DNHdNREl3TWpj'
    || 'MUxESTVMamc0TWpneE1pQXlOQzR3TlRZM01UVTFMRE13TGpReU5UYzRNU0JNTWpRdU1EVTJOekUxTlN3ME1DNDNPRFV4TlRZZ1F6STBMakExTmpjeE5UVXNO'
    || 'REl1TWpZMU5qSTFJREkxTGpJMU9UZ3pPVFVzTkRNdU5EWTROelVnTWpZdU56UTBNakUxTlN3ME15NDBOamczTlNCRE1qZ3VNakkwTmpnek5TdzBNeTQwTmpn'
    || 'M05TQXlPUzQwTWpjNE1EZzFMRFF5TGpJMk5UWXlOU0F5T1M0ME1qYzRNRGcxTERRd0xqYzROVEUxTmlCTU1qa3VOREkzT0RBNE5Td3pOQzQ0TWpneE1qVWdU'
    || 'RE0wTGpVMk9EUXpNelVzTXpjdU56azJPRGMxSUVNek5TNDROVGMwT1RZMUxETTRMalUwTWprMk9TQXpOeTQxTURrNE16azFMRE00TGpBNU56WTFOaUF6T0M0'
    || 'eU5USXdNamMxTERNMkxqZ3dPRFU1TkNCRE16Z3VPVGs0TVRJeE5Td3pOUzQxTVRrMU16RWdNemd1TlRVMk56RTFOU3d6TXk0NE56RXdPVFFnTXpjdU1qWXpO'
    || 'elEyTlN3ek15NHhNamc1TURZaWZTa3NieTVxYzNnb0luQmhkR2dpTEh0a09pSk5NVFF1TkRRek5ETXpOU3d5TVM0M05qazFNekVnUXpFMExqUTFPVEExT0RV'
    || 'c01qQXVPREV5TlNBeE15NDVOVFV4TlRJMUxERTVMamt5TVRnM05TQXhNeTR4TWpjd01qYzFMREU1TGpRME1UUXdOaUJNTXk0NU5URXlORFkwT1N3eE5DNHhO'
    || 'RFExTXpFZ1F6TXVOVFV5T0RBNE5Ea3NNVE11T1RFME1EWXlJRE11TURrMU56YzNORGtzTVRNdU56a3lPVFk1SURJdU5qTTROelEyTkRrc01UTXVOemt5T1RZ'
    || 'NUlFTXhMalk1TnpNek9UUTVMREV6TGpjNU1qazJPU0F3TGpneU1qTXpPVFE1TlN3eE5DNHlPVFk0TnpVZ01DNHpOVE0xT0RrME9UVXNNVFV1TVRBNU16YzFJ'
    || 'RU10TUM0ek56STVOekkxTURVc01UWXVNelkzTVRnNElEQXVNRFl3TmpJeE5EazFMREUzTGprNE1EUTJPU0F4TGpNeE9EUXpNelE1TERFNExqY3dOekF6TVNC'
    || 'TU5pNDJNRGMwT1RZME9Td3lNUzQzTlRjNE1USWdUREV1TXpFNE5ETXpORGtzTWpRdU9ERXlOU0JETUM0M01Ea3dOVGcwT1RVc01qVXVNVFkwTURZeUlEQXVN'
    || 'amN4TlRVNE5EazFMREkxTGpjek1EUTJPU0F3TGpBNU1UZzNNVFE1TlN3eU5pNDBNVEF4TlRZZ1F5MHdMakE1TVRjeU1qVXdOU3d5Tnk0d09EazRORFFnTUM0'
    || 'd01ESXdNamMwT1RRNU5pd3lOeTQ0TURBM09ERWdNQzR6TlRNMU9EazBPVFVzTWpndU5ERXdNVFUySUVNd0xqZ3lNak16T1RRNU5Td3lPUzR5TWpJMk5UWWdN'
    || 'UzQyT1Rjek16azBPU3d5T1M0M01qWTFOaklnTWk0Mk16UTRNemswT1N3eU9TNDNNalkxTmpJZ1F6TXVNRGsxTnpjM05Ea3NNamt1TnpJMk5UWXlJRE11TlRV'
    || 'eU9EQTRORGtzTWprdU5qQTFORFk1SURNdU9UVXhNalEyTkRrc01qa3VNemMxSUV3eE15NHhNamN3TWpjMUxESTBMakEzT0RFeU5TQkRNVE11T1RRM016TTVO'
    || 'U3d5TXk0Mk1ERTFOaklnTVRRdU5EVXhNalEyTlN3eU1pNDNNVGczTlNBeE5DNDBORE0wTXpNMUxESXhMamMyT1RVek1TSjlLU3h2TG1wemVDZ2ljR0YwYUNJ'
    || 'c2UyUTZJazAyTGpBek16STNOelE1TERFd0xqTTVNRFl5TlNCTU1UVXVNakE1TURVNE5Td3hOUzQyT0RjMUlFTXhOaTR5Tnprek56RTFMREUyTGpNd09EVTVO'
    || 'Q0F4Tnk0MU9UazJPRE0xTERFMkxqRXdOVFEyT1NBeE9DNDBORE0wTXpNMUxERTFMakk0TVRJMUlFTXhPQzQ1TnpnMU9EazFMREUwTGpjNE9UQTJNaUF4T1M0'
    || 'ek1UQTJNakUxTERFMExqQTROVGt6T0NBeE9TNHpNVEEyTWpFMUxERXpMak13TkRZNE9DQk1NVGt1TXpFd05qSXhOU3d5TGpZNE56VWdRekU1TGpNeE1EWXlN'
    || 'VFVzTVM0eU1ETXhNalVnTVRndU1UQTNORGsyTlN3d0lERTJMall5TnpBeU56VXNNQ0JETVRVdU1UUXlOalV5TlN3d0lERXpMamt6T1RVeU56VXNNUzR5TURN'
    || 'eE1qVWdNVE11T1RNNU5USTNOU3d5TGpZNE56VWdUREV6TGprek9UVXlOelVzT0M0M016QTBOamtnVERndU56STROVGc1TkRrc05TNDNNakkyTlRZZ1F6Y3VO'
    || 'RE01TlRJM05Ea3NOQzQ1TnpZMU5qSWdOUzQzT1RFd09EazBPU3cxTGpReE56azJPU0ExTGpBME5EazVOalE1TERZdU56QTNNRE14SUVNMExqSTVPRGt3TWpR'
    || 'NUxEY3VPVGsyTURrMElEUXVOelEwTWpFMU5Ea3NPUzQyTkRRMU16RWdOaTR3TXpNeU56YzBPU3d4TUM0ek9UQTJNalVpZlNrc2J5NXFjM2dvSW5CaGRHZ2lM'
    || 'SHRrT2lKTk1qWXVOalkyTURnNU5Td3lNaTR4T1RreU1Ua2dRekkyTGpZMk5qQTRPVFVzTWpJdU5EQXlNelEwSURJMkxqVTBPRGt3TWpVc01qSXVOamd6TlRr'
    || 'MElESTJMalF3TkRNM01UVXNNakl1T0RNeU1ETXhJRXd5TWk0M05qYzJOVEkxTERJMkxqUTJPRGMxSUVNeU1pNDJNak14TWpFMUxESTJMall4TXpJNE1TQXlN'
    || 'aTR6TXpjNU5qVTFMREkyTGpjek1EUTJPU0F5TWk0eE16UTRNemsxTERJMkxqY3pNRFEyT1NCTU1qRXVNakE1TURVNE5Td3lOaTQzTXpBME5qa2dRekl4TGpB'
    || 'd05Ua3pNelVzTWpZdU56TXdORFk1SURJd0xqY3lNRGMzTnpVc01qWXVOakV6TWpneElESXdMalUzTmpJME5qVXNNall1TkRZNE56VWdUREUyTGprek5UWXlN'
    || 'VFVzTWpJdU9ETXlNRE14SUVNeE5pNDNPVEV3T0RrMUxESXlMalk0TXpVNU5DQXhOaTQyTnpNNU1ESTFMREl5TGpRd01qTTBOQ0F4Tmk0Mk56TTVNREkxTERJ'
    || 'eUxqRTVPVEl4T1NCTU1UWXVOamN6T1RBeU5Td3lNUzR5TnpNME16Z2dRekUyTGpZM016a3dNalVzTWpFdU1EWTJOREEySURFMkxqYzVNVEE0T1RVc01qQXVO'
    || 'emcxTVRVMklERTJMamt6TlRZeU1UVXNNakF1TmpRd05qSTFJRXd5TUM0MU56WXlORFkxTERFM0lFTXlNQzQzTWpBM056YzFMREUyTGpnMU5UUTJPU0F5TVM0'
    || 'd01EVTVNek0xTERFMkxqY3pPREk0TVNBeU1TNHlNRGt3TlRnMUxERTJMamN6T0RJNE1TQk1Nakl1TVRNME9ETTVOU3d4Tmk0M016Z3lPREVnUXpJeUxqTXpO'
    || 'emsyTlRVc01UWXVOek00TWpneElESXlMall5TXpFeU1UVXNNVFl1T0RVMU5EWTVJREl5TGpjMk56WTFNalVzTVRjZ1RESTJMalF3TkRNM01UVXNNakF1TmpR'
    || 'd05qSTFJRU15Tmk0MU5EZzVNREkxTERJd0xqYzROVEUxTmlBeU5pNDJOall3T0RrMUxESXhMakEyTmpRd05pQXlOaTQyTmpZd09EazFMREl4TGpJM016UXpP'
    || 'Q0JNTWpZdU5qWTJNRGc1TlN3eU1pNHhPVGt5TVRrZ1dpQk5Nak11TkRFNU9UazJOU3d5TVM0M05UTTVNRFlnVERJekxqUXhPVGs1TmpVc01qRXVOekUwT0RR'
    || 'MElFTXlNeTQwTVRrNU9UWTFMREl4TGpVMk5qUXdOaUF5TXk0ek16UXdOVGcxTERJeExqTTFPVE0zTlNBeU15NHlNamcxT0RrMUxESXhMakkxSUV3eU1pNHhO'
    || 'VFF6TnpFMUxESXdMakUzT1RZNE9DQkRNakl1TURRNE9UQXlOU3d5TUM0d056QXpNVElnTWpFdU9EUXhPRGN4TlN3eE9TNDVPRFF6TnpVZ01qRXVOamc1TlRJ'
    || 'M05Td3hPUzQ1T0RRek56VWdUREl4TGpZMU1EUTJOVFVzTVRrdU9UZzBNemMxSUVNeU1TNDFNREl3TWpjMUxERTVMams0TkRNM05TQXlNUzR5T1RRNU9UWTFM'
    || 'REl3TGpBM01ETXhNaUF5TVM0eE9EVTJNakUxTERJd0xqRTNPVFk0T0NCTU1qQXVNVEUxTXpBNE5Td3lNUzR5TlNCRE1qQXVNREE1T0RNNU5Td3lNUzR6TlRV'
    || 'ME5qa2dNVGt1T1RJek9UQXlOU3d5TVM0MU5qSTFJREU1TGpreU16a3dNalVzTWpFdU56RTBPRFEwSUV3eE9TNDVNak01TURJMUxESXhMamMxTXprd05pQkRN'
    || 'VGt1T1RJek9UQXlOU3d5TVM0NU1EWXlOU0F5TUM0d01EazRNemsxTERJeUxqRXhNekk0TVNBeU1DNHhNVFV6TURnMUxESXlMakl4T0RjMUlFd3lNUzR4T0RV'
    || 'Mk1qRTFMREl6TGpJNU1qazJPU0JETWpFdU1qazBPVGsyTlN3eU15NHpPVGcwTXpnZ01qRXVOVEF5TURJM05Td3lNeTQwT0RRek56VWdNakV1TmpVd05EWTFO'
    || 'U3d5TXk0ME9EUXpOelVnVERJeExqWTRPVFV5TnpVc01qTXVORGcwTXpjMUlFTXlNUzQ0TkRFNE56RTFMREl6TGpRNE5ETTNOU0F5TWk0d05EZzVNREkxTERJ'
    || 'ekxqTTVPRFF6T0NBeU1pNHhOVFF6TnpFMUxESXpMakk1TWprMk9TQk1Nak11TWpJNE5UZzVOU3d5TWk0eU1UZzNOU0JETWpNdU16TTBNRFU0TlN3eU1pNHhN'
    || 'VE15T0RFZ01qTXVOREU1T1RrMk5Td3lNUzQ1TURZeU5TQXlNeTQwTVRrNU9UWTFMREl4TGpjMU16a3dOaUJhSW4wcExHOHVhbk40S0NKd1lYUm9JaXg3WkRv'
    || 'aVRUSTRMakE0TnprMk5UVXNNVFV1TmpnM05TQk1NemN1TWpZek56UTJOU3d4TUM0ek9UQTJNalVnUXpNNExqVTFNamd3T0RVc09TNDJORGcwTXpnZ016Z3VP'
    || 'VGs0TVRJeE5TdzNMams1TmpBNU5DQXpPQzR5TlRJd01qYzFMRFl1TnpBM01ETXhJRU16Tnk0MU1EVTVNek0xTERVdU5ERTNPVFk1SURNMUxqZzFOelE1TmpV'
    || 'c05DNDVOelkxTmpJZ016UXVOVFk0TkRNek5TdzFMamN5TWpZMU5pQk1Namt1TkRJM09EQTROU3c0TGpZNU1UUXdOaUJNTWprdU5ESTNPREE0TlN3eUxqWTRO'
    || 'elVnUXpJNUxqUXlOemd3T0RVc01TNHlNRE14TWpVZ01qZ3VNakkwTmpnek5Td3ROUzQyT0RRek5ERTRPV1V0TVRRZ01qWXVOelEwTWpFMU5Td3ROUzQyT0RR'
    || 'ek5ERTRPV1V0TVRRZ1F6STFMakkxT1Rnek9UVXNMVFV1TmpnME16UXhPRGxsTFRFMElESTBMakExTmpjeE5UVXNNUzR5TURNeE1qVWdNalF1TURVMk56RTFO'
    || 'U3d5TGpZNE56VWdUREkwTGpBMU5qY3hOVFVzTVRNdU1Ea3pOelVnUXpJMExqQXdOVGt6TXpVc01UTXVOak15T0RFeUlESTBMakV4TVRRd01qVXNNVFF1TVRr'
    || 'MU16RXlJREkwTGpRd05ETTNNVFVzTVRRdU56QXpNVEkxSUVNeU5TNHhOVEEwTmpVMUxERTFMams1TWpFNE9DQXlOaTQzT1RnNU1ESTFMREUyTGpRek16VTVO'
    || 'Q0F5T0M0d09EYzVOalUxTERFMUxqWTROelVpZlNrc2J5NXFjM2dvSW5CaGRHZ2lMSHRrT2lKTk1UY3VNRFE0T1RBeU5Td3lOeTQxTVRVMk1qVWdRekUyTGpR'
    || 'ek9UVXlOelVzTWpjdU16azRORE00SURFMUxqYzROekU0TXpVc01qY3VORGsyTURrMElERTFMakl3T1RBMU9EVXNNamN1T0RJNE1USTFJRXcyTGpBek16STNO'
    || 'elE1TERNekxqRXlPRGt3TmlCRE5DNDNORFF5TVRVME9Td3pNeTQ0TnpFd09UUWdOQzR5T1RnNU1ESTBPU3d6TlM0MU1UazFNekVnTlM0d05EUTVPVFkwT1N3'
    || 'ek5pNDRNRGcxT1RRZ1F6VXVOemt4TURnNU5Ea3NNemd1TVRBeE5UWXlJRGN1TkRNNU5USTNORGtzTXpndU5UUXlPVFk1SURndU56STROVGc1TkRrc016Y3VO'
    || 'emsyT0RjMUlFd3hNeTQ1TXprMU1qYzFMRE0wTGpjNE9UQTJNaUJNTVRNdU9UTTVOVEkzTlN3ME1DNDNPRFV4TlRZZ1F6RXpMamt6T1RVeU56VXNOREl1TWpZ'
    || 'MU5qSTFJREUxTGpFME1qWTFNalVzTkRNdU5EWTROelVnTVRZdU5qSTNNREkzTlN3ME15NDBOamczTlNCRE1UZ3VNVEEzTkRrMk5TdzBNeTQwTmpnM05TQXhP'
    || 'UzR6TVRBMk1qRTFMRFF5TGpJMk5UWXlOU0F4T1M0ek1UQTJNakUxTERRd0xqYzROVEUxTmlCTU1Ua3VNekV3TmpJeE5Td3pNQzR4TmpjNU5qa2dRekU1TGpN'
    || 'eE1EWXlNVFVzTWpndU9ESTRNVEkxSURFNExqTXpNREUxTWpVc01qY3VOekU0TnpVZ01UY3VNRFE0T1RBeU5Td3lOeTQxTVRVMk1qVWlmU2tzYnk1cWMzZ29J'
    || 'bkJoZEdnaUxIdGtPaUpOTkRJdU9UazRNVEl4TlN3eE5TNHdOemd4TWpVZ1F6UXlMakkxTlRrek16VXNNVE11TnpnMU1UVTJJRFF3TGpZd016VTRPVFVzTVRN'
    || 'dU16UXpOelVnTXprdU16RTBOVEkzTlN3eE5DNHdPRGs0TkRRZ1RETXdMakV6T0RjME5qVXNNVGt1TXpnMk56RTVJRU15T1M0eU5UazRNemsxTERFNUxqZzVO'
    || 'RFV6TVNBeU9DNDNOelUwTmpVMUxESXdMamd5TkRJeE9TQXlPQzQzT1RFd09EazFMREl4TGpjMk9UVXpNU0JETWpndU56Z3pNamMzTlN3eU1pNDNNVEE1TXpn'
    || 'Z01qa3VNalkzTmpVeU5Td3lNeTQyTWpnNU1EWWdNekF1TVRNNE56UTJOU3d5TkM0eE1qZzVNRFlnVERNNUxqTXhORFV5TnpVc01qa3VOREk1TmpnNElFTTBN'
    || 'QzQyTURNMU9EazFMRE13TGpFM01UZzNOU0EwTWk0eU5USXdNamMxTERJNUxqY3pNRFEyT1NBME1pNDVPVGd4TWpFMUxESTRMalEwTVRRd05pQkRORE11TnpR'
    || 'ME1qRTFOU3d5Tnk0eE5USXpORFFnTkRNdU1qazRPVEF5TlN3eU5TNDFNRE01TURZZ05ESXVNREE1T0RNNU5Td3lOQzQzTlRjNE1USWdURE0yTGpneE5EVXlO'
    || 'elVzTWpFdU56VTNPREV5SUV3ME1pNHdNRGs0TXprMUxERTRMamMxTnpneE1pQkRORE11TXpBeU9EQTROU3d4T0M0d01UVTJNalVnTkRNdU56UTBNakUxTlN3'
    || 'eE5pNHpOamN4T0RnZ05ESXVPVGs0TVRJeE5Td3hOUzR3TnpneE1qVWlmU2xkZlNsOVkyOXVjM1FnUTJNOWUyOTJaWEoyYVdWM09tOHVhbk40Y3lodkxrWnlZ'
    || 'V2R0Wlc1MExIdGphR2xzWkhKbGJqcGJieTVxYzNnb0luSmxZM1FpTEh0NE9pSXlJaXg1T2lJeUlpeDNhV1IwYURvaU5TNDFJaXhvWldsbmFIUTZJalV1TlNJ'
    || 'c2NuZzZJakV1TWlKOUtTeHZMbXB6ZUNnaWNtVmpkQ0lzZTNnNklqZ3VOU0lzZVRvaU1pSXNkMmxrZEdnNklqVXVOU0lzYUdWcFoyaDBPaUkxTGpVaUxISjRP'
    || 'aUl4TGpJaWZTa3NieTVxYzNnb0luSmxZM1FpTEh0NE9pSXlJaXg1T2lJNExqVWlMSGRwWkhSb09pSTFMalVpTEdobGFXZG9kRG9pTlM0MUlpeHllRG9pTVM0'
    || 'eUluMHBMRzh1YW5ONEtDSnlaV04wSWl4N2VEb2lPQzQxSWl4NU9pSTRMalVpTEhkcFpIUm9PaUkxTGpVaUxHaGxhV2RvZERvaU5TNDFJaXh5ZURvaU1TNHlJ'
    || 'bjBwWFgwcExIQmxiM0JzWlRwdkxtcHplSE1vYnk1R2NtRm5iV1Z1ZEN4N1kyaHBiR1J5Wlc0NlcyOHVhbk40S0NKamFYSmpiR1VpTEh0amVEb2lOaUlzWTNr'
    || 'NklqVXVOU0lzY2pvaU1pNDBJbjBwTEc4dWFuTjRLQ0p3WVhSb0lpeDdaRG9pVFRJZ01UTXVOV013TFRJdU1pQXhMamd0TXk0MklEUXRNeTQyY3pRZ01TNDBJ'
    || 'RFFnTXk0MkluMHBMRzh1YW5ONEtDSndZWFJvSWl4N1pEb2lUVEV4SURRdU1tRXlMaklnTWk0eUlEQWdNQ0F4SURBZ05DNHpUVEV4TGpZZ01UTXVOV013TFRF'
    || 'dU55MHVOeTB5TGprdE1TNDRMVE11TkNKOUtWMTlLU3h6WldkdFpXNTBjenB2TG1wemVITW9ieTVHY21GbmJXVnVkQ3g3WTJocGJHUnlaVzQ2VzI4dWFuTjRL'
    || 'Q0pqYVhKamJHVWlMSHRqZURvaU5pSXNZM2s2SWpZaUxISTZJak11TmlKOUtTeHZMbXB6ZUNnaVkybHlZMnhsSWl4N1kzZzZJakV3SWl4amVUb2lNVEFpTEhJ'
    || 'NklqTXVOaUo5S1YxOUtTeHBaR1Z1ZEdsMGVUcHZMbXB6ZUhNb2J5NUdjbUZuYldWdWRDeDdZMmhwYkdSeVpXNDZXMjh1YW5ONEtDSndZWFJvSWl4N1pEb2lU'
    || 'VGdnTW1FeklETWdNQ0F3SURFZ015QXpkakVpZlNrc2J5NXFjM2dvSW5CaGRHZ2lMSHRrT2lKTk5TQTJWalZoTXlBeklEQWdNQ0F4SURFdE1pNHlJbjBwTEc4'
    || 'dWFuTjRLQ0p3WVhSb0lpeDdaRG9pVFRRdU5TQTNMalZqTUNBeklERWdOQzQxSURNdU5TQTJMalVpZlNrc2J5NXFjM2dvSW5CaGRHZ2lMSHRrT2lKTk9DQTJk'
    || 'ak11TlNKOUtTeHZMbXB6ZUNnaWNHRjBhQ0lzZTJRNklrMHhNUzQxSURjdU5XTXdJREl0TGpRZ015NHpMVEV1TWlBMExqUWlmU2xkZlNrc1kyOTJaWEpoWjJV'
    || 'NmJ5NXFjM2h6S0c4dVJuSmhaMjFsYm5Rc2UyTm9hV3hrY21WdU9sdHZMbXB6ZUNnaVkybHlZMnhsSWl4N1kzZzZJamdpTEdONU9pSTRJaXh5T2lJMkluMHBM'
    || 'Rzh1YW5ONEtDSndZWFJvSWl4N1pEb2lUVGdnTW1FMklEWWdNQ0F3SURFZ01DQXhNaUlzWm1sc2JEb2lZM1Z5Y21WdWRFTnZiRzl5SWl4emRISnZhMlU2SW01'
    || 'dmJtVWlMRzl3WVdOcGRIazZJaTR5TWlKOUtTeHZMbXB6ZUNnaWNHRjBhQ0lzZTJRNklrMDRJRFF1TlhZekxqVnNNaTQxSURFdU5pSjlLVjE5S1N4dGIyNWxl'
    || 'VHB2TG1wemVITW9ieTVHY21GbmJXVnVkQ3g3WTJocGJHUnlaVzQ2VzI4dWFuTjRLQ0p3WVhSb0lpeDdaRG9pVFRnZ01TNDRkakV5TGpRaWZTa3NieTVxYzNn'
    || 'b0luQmhkR2dpTEh0a09pSk5NVEVnTkM0Mll6QXRNUzR4TFRFdU15MHhMamt0TXkweExqbHpMVE1nTGpndE15QXhMamxqTUNBeExqSWdNUzR5SURFdU55QXpJ'
    || 'REl1TW5NeklERWdNeUF5TGpOak1DQXhMakl0TVM0eklESXRNeUF5Y3kwekxTNDRMVE10TWlKOUtWMTlLU3h6YUdsbGJHUTZieTVxYzNoektHOHVSbkpoWjIx'
    || 'bGJuUXNlMk5vYVd4a2NtVnVPbHR2TG1wemVDZ2ljR0YwYUNJc2UyUTZJazA0SURFdU9DQXpJRE11T0hZMFl6QWdNeUF5TGpFZ05TNDBJRFVnTmk0MElESXVP'
    || 'UzB4SURVdE15NDBJRFV0Tmk0MGRpMDBXaUo5S1N4dkxtcHplQ2dpY0dGMGFDSXNlMlE2SWswMklEZ3VNV3d4TGpZZ01TNDJUREV3TGpRZ05pNDJJbjBwWFgw'
    || 'cExIUmhZbXhsT204dWFuTjRjeWh2TGtaeVlXZHRaVzUwTEh0amFHbHNaSEpsYmpwYmJ5NXFjM2dvSW5KbFkzUWlMSHQ0T2lJeUlpeDVPaUl5TGpnaUxIZHBa'
    || 'SFJvT2lJeE1pSXNhR1ZwWjJoME9pSXhNQzQwSWl4eWVEb2lNUzQwSW4wcExHOHVhbk40S0NKd1lYUm9JaXg3WkRvaVRUSWdOaTR6YURFeVRUWXVOQ0EyTGpO'
    || 'Mk5pNDVJbjBwWFgwcExHWnNiM2M2Ynk1cWMzaHpLRzh1Um5KaFoyMWxiblFzZTJOb2FXeGtjbVZ1T2x0dkxtcHplQ2dpY21WamRDSXNlM2c2SWpFdU5pSXNl'
    || 'VG9pTlM0NElpeDNhV1IwYURvaU5DSXNhR1ZwWjJoME9pSTBMalFpTEhKNE9pSXhMakVpZlNrc2J5NXFjM2dvSW5KbFkzUWlMSHQ0T2lJeE1DNDBJaXg1T2lJ'
    || 'eUxqUWlMSGRwWkhSb09pSTBJaXhvWldsbmFIUTZJalF1TkNJc2NuZzZJakV1TVNKOUtTeHZMbXB6ZUNnaWNtVmpkQ0lzZTNnNklqRXdMalFpTEhrNklqa3VN'
    || 'aUlzZDJsa2RHZzZJalFpTEdobGFXZG9kRG9pTkM0MElpeHllRG9pTVM0eEluMHBMRzh1YW5ONEtDSndZWFJvSWl4N1pEb2lUVFV1TmlBNGFESXVNbUV4TGpJ'
    || 'Z01TNHlJREFnTUNBd0lERXVNaTB4TGpKV05DNDJhREV1TkUwMUxqWWdPR2d5TGpKaE1TNHlJREV1TWlBd0lEQWdNU0F4TGpJZ01TNHlkakl1TW1neExqUWlm'
    || 'U2xkZlNrc1kyaGxZMnM2Ynk1cWMzaHpLRzh1Um5KaFoyMWxiblFzZTJOb2FXeGtjbVZ1T2x0dkxtcHplQ2dpWTJseVkyeGxJaXg3WTNnNklqZ2lMR041T2lJ'
    || 'NElpeHlPaUkySW4wcExHOHVhbk40S0NKd1lYUm9JaXg3WkRvaVRUVXVOQ0E0TGpJZ055NHlJREV3YkRNdU5DMHpMamNpZlNsZGZTa3NkMkZ5YmpwdkxtcHpl'
    || 'SE1vYnk1R2NtRm5iV1Z1ZEN4N1kyaHBiR1J5Wlc0NlcyOHVhbk40S0NKd1lYUm9JaXg3WkRvaVRUZ2dNaTQwSURFdU9TQXhNMmd4TWk0eVREZ2dNaTQwV2lK'
    || 'OUtTeHZMbXB6ZUNnaWNHRjBhQ0lzZTJRNklrMDRJRFl1TkhZelRUZ2dNVEV1TTNZdU1TSjlLVjE5S1N4emNHRnlhenB2TG1wemVITW9ieTVHY21GbmJXVnVk'
    || 'Q3g3WTJocGJHUnlaVzQ2VzI4dWFuTjRLQ0p3WVhSb0lpeDdaRG9pVFRJZ01URXVOR3d6TGpJdE15NDJJREl1TkNBeUlEUXVOQzAxSW4wcExHOHVhbk40S0NK'
    || 'd1lYUm9JaXg3WkRvaVRURXlJRFF1T0dndE1pNDJUVEV5SURRdU9IWXlMallpZlNsZGZTa3NZMnh2WTJzNmJ5NXFjM2h6S0c4dVJuSmhaMjFsYm5Rc2UyTm9h'
    || 'V3hrY21WdU9sdHZMbXB6ZUNnaVkybHlZMnhsSWl4N1kzZzZJamdpTEdONU9pSTRJaXh5T2lJMkluMHBMRzh1YW5ONEtDSndZWFJvSWl4N1pEb2lUVGdnTkM0'
    || 'MlZqaHNNaTQySURFdU55SjlLVjE5S1N4c1lYbGxjbk02Ynk1cWMzaHpLRzh1Um5KaFoyMWxiblFzZTJOb2FXeGtjbVZ1T2x0dkxtcHplQ2dpY0dGMGFDSXNl'
    || 'MlE2SWswNElERXVPU0F5SURWc05pQXpMakZNTVRRZ05TQTRJREV1T1ZvaWZTa3NieTVxYzNnb0luQmhkR2dpTEh0a09pSk5NaUE0TGpRZ09DQXhNUzQxYkRZ'
    || 'dE15NHhUVElnTVRFdU5DQTRJREUwTGpWc05pMHpMakVpZlNsZGZTbDlPMloxYm1OMGFXOXVJRlJqS0h0dVlXMWxPblVzYzJsNlpUcGtQVEUxZlNsN2NtVjBk'
    || 'WEp1SUc4dWFuTjRLQ0p6ZG1jaUxIdDNhV1IwYURwa0xHaGxhV2RvZERwa0xIWnBaWGRDYjNnNklqQWdNQ0F4TmlBeE5pSXNabWxzYkRvaWJtOXVaU0lzYzNS'
    || 'eWIydGxPaUpqZFhKeVpXNTBRMjlzYjNJaUxITjBjbTlyWlZkcFpIUm9PaUl4TGpVMUlpeHpkSEp2YTJWTWFXNWxZMkZ3T2lKeWIzVnVaQ0lzYzNSeWIydGxU'
    || 'R2x1WldwdmFXNDZJbkp2ZFc1a0lpd2lZWEpwWVMxb2FXUmtaVzRpT2lKMGNuVmxJaXhqYUdsc1pISmxianBEWTF0MVhYMHBmV1oxYm1OMGFXOXVJRkpqS0h0'
    || 'emIyeDFkR2x2YmpwMUxITjFZblJwZEd4bE9tUXNjMlZqZEdsdmJuTTZZeXhoWTNScGRtVTZlQ3h2YmxCcFkyczZSU3htYjI5ME9sUjlLWHRqYjI1emRDQjVQ'
    || 'VXc5UGt3dWRHOU1iM2RsY2tOaGMyVW9LUzV5WlhCc1lXTmxLQzliWG1FdGVqQXRPVjByTDJjc0lpSXBMRTQ5ZVNoMUtTeHFQV1EvZVNoa0tUb2lJaXhIUFNF'
    || 'aGFpWW1JVTR1YVc1amJIVmtaWE1vYWlrbUppRnFMbWx1WTJ4MVpHVnpLRTRwTzNKbGRIVnliaUJ2TG1wemVITW9JbUZ6YVdSbElpeDdZMnhoYzNOT1lXMWxP'
    || 'aUp6YVdSbElpeGphR2xzWkhKbGJqcGJieTVxYzNoektDSmthWFlpTEh0amJHRnpjMDVoYldVNkluTnBaR1ZmWDJKeVlXNWtJaXhqYUdsc1pISmxianBiYnk1'
    || 'cWMzZ29hbU1zZTNOcGVtVTZNako5S1N4dkxtcHplSE1vSW1ScGRpSXNlM04wZVd4bE9udHRhVzVYYVdSMGFEb3dmU3hqYUdsc1pISmxianBiYnk1cWMzZ29J'
    || 'bVJwZGlJc2UyTnNZWE56VG1GdFpUb2ljMmxrWlY5ZmQyOXlaRzFoY21zaUxHTm9hV3hrY21WdU9uVjlLU3hIUDI4dWFuTjRLQ0prYVhZaUxIdGpiR0Z6YzA1'
    || 'aGJXVTZJbk5wWkdWZlgzTjFZaUlzWTJocGJHUnlaVzQ2WkgwcE9tNTFiR3hkZlNsZGZTa3NieTVxYzNnb0ltNWhkaUlzZTJOc1lYTnpUbUZ0WlRvaWJtRjJJ'
    || 'aXhqYUdsc1pISmxianBqTG0xaGNDZ29UQ3hHS1QwK2UyTnZibk4wSUZZOVJqNHdQMk5iUmkweFhTNW5jbTkxY0RwMmIybGtJREFzZFdVOVRDNW5jbTkxY0NZ'
    || 'bVRDNW5jbTkxY0NFOVBWWS9UQzVuY205MWNEcHVkV3hzTEVvOWJ5NXFjM2h6S0NKaWRYUjBiMjRpTEh0amJHRnpjMDVoYldVNkltNWhkbDlmYVhSbGJTSXJL'
    || 'RXd1WjNKdmRYQS9JaUJ1WVhaZlgybDBaVzB0TFhOMVlpSTZJaUlwS3loTUxtbGtQVDA5ZUQ4aUlHNWhkbDlmYVhSbGJTMHRiMjRpT2lJaUtTd2laR0YwWVMx'
    || 'dmJtVnphRzkwSWpvaWJtRjJMV2wwWlcwaUxDSmtZWFJoTFhObFkzUnBiMjRpT2t3dWFXUXNiMjVEYkdsamF6b29LVDArUlNoTUxtbGtLU3dpWVhKcFlTMWpk'
    || 'WEp5Wlc1MElqcE1MbWxrUFQwOWVEOGljR0ZuWlNJNmRtOXBaQ0F3TEdOb2FXeGtjbVZ1T2x0dkxtcHplQ2hVWXl4N2JtRnRaVHBNTG1samIyNC9QeUp2ZG1W'
    || 'eWRtbGxkeUo5S1N4dkxtcHplSE1vSW5Od1lXNGlMSHR6ZEhsc1pUcDdiV2x1VjJsa2RHZzZNQ3htYkdWNE9qRjlMR05vYVd4a2NtVnVPbHR2TG1wemVDZ2lj'
    || 'M0JoYmlJc2UyTnNZWE56VG1GdFpUb2libUYyWDE5c1lXSmxiQ0lzWTJocGJHUnlaVzQ2VEM1c1lXSmxiSDBwTEV3dVpHVnpZejl2TG1wemVDZ2ljM0JoYmlJ'
    || 'c2UyTnNZWE56VG1GdFpUb2libUYyWDE5a1pYTmpJaXhqYUdsc1pISmxianBNTG1SbGMyTjlLVHB1ZFd4c1hYMHBMRXd1WW1Ga1oyVS9ieTVxYzNnb0luTndZ'
    || 'VzRpTEh0amJHRnpjMDVoYldVNkltNWhkbDlmWW1Ga1oyVWdibUYyWDE5aVlXUm5aUzB0SWlzb1RDNWlZV1JuWlZSdmJtVS9QeUpwWkd4bElpa3NZMmhwYkdS'
    || 'eVpXNDZUQzVpWVdSblpYMHBPbTUxYkd3c1RDNXpkR0YwZFhNL2J5NXFjM2dvSW5Od1lXNGlMSHRqYkdGemMwNWhiV1U2SW01aGRsOWZaRzkwSUc1aGRsOWZa'
    || 'RzkwTFMwaUswd3VjM1JoZEhWemZTazZiblZzYkYxOUxFd3VhV1FwTzNKbGRIVnliaUIxWlQ5dkxtcHplSE1vVFhRdVJuSmhaMjFsYm5Rc2UyTm9hV3hrY21W'
    || 'dU9sdHZMbXB6ZUNnaWFESWlMSHRqYkdGemMwNWhiV1U2SW01aGRsOWZaM0p2ZFhBaUxHTm9hV3hrY21WdU9rd3VaM0p2ZFhCOUtTeEtYWDBzSW1jNklpdEdL'
    || 'VHBLZlNsOUtTeFVQMjh1YW5ONEtDSmthWFlpTEh0amJHRnpjMDVoYldVNkluTnBaR1ZmWDJadmIzUWlMR05vYVd4a2NtVnVPbFI5S1RwdWRXeHNYWDBwZlda'
    || 'MWJtTjBhVzl1SUVKdUtIdHNZV0psYkRwMUxIWmhiSFZsT21Rc2RXNXBkRHBqTEhOMVlqcDRMSFJ2Ym1VNlJYMHBlM0psZEhWeWJpQnZMbXB6ZUhNb0ltUnBk'
    || 'aUlzZTJOc1lYTnpUbUZ0WlRvaWMzUmhkQ0lyS0VVL0lpQnpkR0YwTFMwaUswVTZJaUlwTENKa1lYUmhMVzl1WlhOb2IzUWlPaUp6ZEdGMElpeGphR2xzWkhK'
    || 'bGJqcGJieTVxYzNnb0ltUnBkaUlzZTJOc1lYTnpUbUZ0WlRvaWMzUmhkRjlmYkdGaVpXd2lMR05vYVd4a2NtVnVPblY5S1N4dkxtcHplSE1vSW1ScGRpSXNl'
    || 'Mk5zWVhOelRtRnRaVG9pYzNSaGRGOWZkbUZzZFdVaUxHTm9hV3hrY21WdU9sdGtMR00vYnk1cWMzZ29Jbk53WVc0aUxIdGpiR0Z6YzA1aGJXVTZJbk4wWVhS'
    || 'ZlgzVnVhWFFpTEdOb2FXeGtjbVZ1T21OOUtUcHVkV3hzWFgwcExIZy9ieTVxYzNnb0ltUnBkaUlzZTJOc1lYTnpUbUZ0WlRvaWMzUmhkRjlmYzNWaUlpeGph'
    || 'R2xzWkhKbGJqcDRmU2s2Ym5Wc2JGMTlLWDFtZFc1amRHbHZiaUJYWlNoN2RHbDBiR1U2ZFN4b2FXNTBPbVFzWTJocGJHUnlaVzQ2WXl4M2FXUmxPbmg5S1h0'
    || 'eVpYUjFjbTRnYnk1cWMzaHpLQ0p6WldOMGFXOXVJaXg3WTJ4aGMzTk9ZVzFsT2lKallYSmtJaXNvZUQ4aUlHTmhjbVF0TFhkcFpHVWlPaUlpS1N3aVpHRjBZ'
    || 'UzF2Ym1WemFHOTBJam9pWTJGeVpDSXNZMmhwYkdSeVpXNDZXMjh1YW5ONGN5Z2lhR1ZoWkdWeUlpeDdZMnhoYzNOT1lXMWxPaUpqWVhKa1gxOW9aV0ZrSWl4'
    || 'amFHbHNaSEpsYmpwYmJ5NXFjM2dvSW1neUlpeDdZMmhwYkdSeVpXNDZkWDBwTEdRL2J5NXFjM2dvSW5BaUxIdGpiR0Z6YzA1aGJXVTZJbU5oY21SZlgyaHBi'
    || 'blFpTEdOb2FXeGtjbVZ1T21SOUtUcHVkV3hzWFgwcExHTmRmU2w5Wm5WdVkzUnBiMjRnU21Vb2UzQmhibVZzT25Vc2QyaGxiazFwYzNOcGJtYzZaQ3h1YjNS'
    || 'Q2RXbHNkRUpzYjJOck9tTXNZMmhwYkdSeVpXNDZlSDBwZTJsbUtDRjFLWEpsZEhWeWJpQmpQMjh1YW5ONEtHOHVSbkpoWjIxbGJuUXNlMk5vYVd4a2NtVnVP'
    || 'bU45S1RwdkxtcHplSE1vSW1ScGRpSXNlMk5zWVhOelRtRnRaVG9pY0dGdVpXd3RibTkwWW5WcGJIUWlMQ0prWVhSaExXOXVaWE5vYjNRaU9pSndZVzVsYkMx'
    || 'dWIzUmlkV2xzZENJc1kyaHBiR1J5Wlc0NlcyOHVhbk40S0NKemRISnZibWNpTEh0amFHbHNaSEpsYmpvaVZHaHBjeUJ5ZFc0Z1pHbGtJRzV2ZENCaWRXbHNa'
    || 'Q0IwYUdseklIQmhjblF1SW4wcExHOHVhbk40S0NKd0lpeDdZMmhwYkdSeVpXNDZaRDgvSWxSb1pTQnpZM0pwY0hRZ2NtRnVJR2x1SUdsMGN5QmtaV1poZFd4'
    || 'MExDQnlaV0ZrTFc5dWJIa2diVzlrWlN3Z2QyaHBZMmdnYVc1emNHVmpkSE1nZVc5MWNpQmhZMk52ZFc1MElIZHBkR2h2ZFhRZ1kzSmxZWFJwYm1jZ1lXNTVk'
    || 'R2hwYm1jdUlFWnBiR3dnYVc0Z2RHaGxJSE5sZEhScGJtZHpJR0YwSUhSb1pTQjBiM0FnYjJZZ2RHaGxJSE5qY21sd2RDQmhibVFnY25WdUlHbDBJR0ZuWVds'
    || 'dUlIUnZJR0oxYVd4a0lIUm9hWE11SW4wcFhYMHBPMmxtS0dkdUtIVXBLWEpsZEhWeWJpQmpQMjh1YW5ONEtHOHVSbkpoWjIxbGJuUXNlMk5vYVd4a2NtVnVP'
    || 'bU45S1RwdkxtcHplSE1vSW1ScGRpSXNlMk5zWVhOelRtRnRaVG9pY0dGdVpXd3RibTkwWW5WcGJIUWlMQ0prWVhSaExXOXVaWE5vYjNRaU9pSndZVzVsYkMx'
    || 'dWIzUmlkV2xzZENJc1kyaHBiR1J5Wlc0NlcyOHVhbk40S0NKemRISnZibWNpTEh0amFHbHNaSEpsYmpvaVZHaHBjeUJ3WVhKMElHaGhjeUJ1YjNRZ1ltVmxi'
    || 'aUJpZFdsc2RDQjVaWFF1SW4wcExHOHVhbk40S0NKd0lpeDdZMmhwYkdSeVpXNDZaRDgvSWxSb2FYTWdjblZ1SUdScFpDQnViM1FnWTNKbFlYUmxJSFJvWlNC'
    || 'dlltcGxZM1J6SUhSb2FYTWdZMkZ5WkNCeVpXRmtjeTRnUm1sc2JDQnBiaUIwYUdVZ2MyVjBkR2x1WjNNZ1lYUWdkR2hsSUhSdmNDQnZaaUIwYUdVZ2MyTnlh'
    || 'WEIwSUdGdVpDQnlkVzRnYVhRZ1lXZGhhVzR1SW4wcExHOHVhbk40S0NKd0lpeDdZMnhoYzNOT1lXMWxPaUp3WVc1bGJDMXViM1JpZFdsc2RGOWZZV3gwSWl4'
    || 'amFHbHNaSEpsYmpvblNXWWdlVzkxSUdWNGNHVmpkR1ZrSUdsMElIUnZJR1Y0YVhOMExDQjBhR1VnYzJGdFpTQlRibTkzWm14aGEyVWdaWEp5YjNJZ1kyOTJa'
    || 'WEp6SUNKdWIzUWdZWFYwYUc5eWFYcGxaQ0lnNG9DVUlIbHZkU0J0WVhrZ1ltVWdiV2x6YzJsdVp5QmhJR2R5WVc1MElISmhkR2hsY2lCMGFHRnVJR0VnWW5W'
    || 'cGJHUXVKMzBwWFgwcE8ybG1LSFp1S0hVcEtYSmxkSFZ5YmlCdkxtcHplSE1vSW1ScGRpSXNlMk5zWVhOelRtRnRaVG9pY0dGdVpXd3RaWEp5YjNJaUxDSmtZ'
    || 'WFJoTFc5dVpYTm9iM1FpT2lKd1lXNWxiQzFsY25KdmNpSXNZMmhwYkdSeVpXNDZXMjh1YW5ONEtDSnpkSEp2Ym1jaUxIdGphR2xzWkhKbGJqb2lWR2hwY3lC'
    || 'eGRXVnllU0JrYVdRZ2JtOTBJSEoxYmk0aWZTa3NieTVxYzNnb0ltTnZaR1VpTEh0amFHbHNaSEpsYmpwMUxtVnljbTl5ZlNsZGZTazdhV1lvSVhVdWNtOTNj'
    || 'eTVzWlc1bmRHZ3BjbVYwZFhKdUlHOHVhbk40S0NKd0lpeDdZMnhoYzNOT1lXMWxPaUp3WVc1bGJDMWxiWEIwZVNJc0ltUmhkR0V0YjI1bGMyaHZkQ0k2SW5C'
    || 'aGJtVnNMV1Z0Y0hSNUlpeGphR2xzWkhKbGJqb2lWR2hsSUhGMVpYSjVJSEpoYmlCaGJtUWdjbVYwZFhKdVpXUWdibThnY205M2N5NGlmU2s3WTI5dWMzUWdS'
    || 'VDEzWXloMUtUdHlaWFIxY200Z2J5NXFjM2h6S0c4dVJuSmhaMjFsYm5Rc2UyTm9hV3hrY21WdU9sdEZQMjh1YW5ONGN5Z2ljQ0lzZTJOc1lYTnpUbUZ0WlRv'
    || 'aWNHRnVaV3d0ZEhKMWJtTWlMQ0prWVhSaExXOXVaWE5vYjNRaU9pSndZVzVsYkMxMGNuVnVZMkYwWldRaUxHTm9hV3hrY21WdU9sc2lVMmh2ZDJsdVp5QjBh'
    || 'R1VnWm1seWMzUWdJaXhyWlNoRktTd2lJSEp2ZDNNdUlGUm9hWE1nY1hWbGNua2djbVYwZFhKdVpXUWdiVzl5WlN3Z2MyOGdZVzU1SUhSdmRHRnNJRzl1SUhS'
    || 'b2FYTWdZMkZ5WkNCcGN5QmhJR1pzYjI5eUxDQnViM1FnWVNCamIzVnVkQzRpWFgwcE9tNTFiR3dzZUYxOUtYMW1kVzVqZEdsdmJpQkVkQ2g3Y205M2N6cDFM'
    || 'R052YkhNNlpDeHRZWGc2WXl4dmJsQnBZMnM2ZUN4aFkzUnBkbVU2UlgwcGUyTnZibk4wSUZROVl6OTFMbk5zYVdObEtEQXNZeWs2ZFR0eVpYUjFjbTRnYnk1'
    || 'cWMzaHpLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJblJoWW14bExYZHlZWEFpTEdOb2FXeGtjbVZ1T2x0dkxtcHplSE1vSW5SaFlteGxJaXg3WTJ4aGMzTk9Z'
    || 'VzFsT25nL0luUmhZbXhsTFMxd2FXTnJJam9pSWl4amFHbHNaSEpsYmpwYmJ5NXFjM2dvSW5Sb1pXRmtJaXg3WTJocGJHUnlaVzQ2Ynk1cWMzZ29JblJ5SWl4'
    || 'N1kyaHBiR1J5Wlc0NlpDNXRZWEFvZVQwK2J5NXFjM2dvSW5Sb0lpeDdZMnhoYzNOT1lXMWxPbmt1WVd4cFoyNDlQVDBpY21sbmFIUWlQeUp5SWpvaUlpeGph'
    || 'R2xzWkhKbGJqcDVMbXhoWW1Wc1B6OTVMbXRsZVgwc2VTNXJaWGtwS1gwcGZTa3NieTVxYzNnb0luUmliMlI1SWl4N1kyaHBiR1J5Wlc0NlZDNXRZWEFvS0hr'
    || 'c1RpazlQbTh1YW5ONEtDSjBjaUlzZTJOc1lYTnpUbUZ0WlRwNEppWk9QVDA5UlQ4aWRISXRMVzl1SWpvaUlpeHZia05zYVdOck9uZy9LQ2s5UG5nb2VTeE9L'
    || 'VHAyYjJsa0lEQXNkR0ZpU1c1a1pYZzZlRDh3T25admFXUWdNQ3dpWVhKcFlTMXpaV3hsWTNSbFpDSTZlRDlPUFQwOVJUcDJiMmxrSURBc2IyNUxaWGxFYjNk'
    || 'dU9uZy9LR285UG5zb2FpNXJaWGs5UFQwaVJXNTBaWElpZkh4cUxtdGxlVDA5UFNJZ0lpa21KaWhxTG5CeVpYWmxiblJFWldaaGRXeDBLQ2tzZUNoNUxFNHBL'
    || 'WDBwT25admFXUWdNQ3hqYUdsc1pISmxianBrTG0xaGNDaHFQVDV2TG1wemVDZ2lkR1FpTEh0amJHRnpjMDVoYldVNmFpNWhiR2xuYmowOVBTSnlhV2RvZENJ'
    || 'L0luSWlPaUlpTEdOb2FXeGtjbVZ1T21vdWNtVnVaR1Z5UDJvdWNtVnVaR1Z5S0hsYmFpNXJaWGxkTEhrcE9reGpLSGxiYWk1clpYbGRLWDBzYWk1clpYa3BL'
    || 'WDBzVGlrcGZTbGRmU2tzWXlZbWRTNXNaVzVuZEdnK1l6OXZMbXB6ZUhNb0luQWlMSHRqYkdGemMwNWhiV1U2SW5SaFlteGxMVzF2Y21VaUxHTm9hV3hrY21W'
    || 'dU9sdHJaU2gxTG14bGJtZDBhQzFqS1N3aUlHMXZjbVVnY205M0tITXBJRzV2ZENCemFHOTNiaUpkZlNrNmJuVnNiRjE5S1gxbWRXNWpkR2x2YmlCTVl5aDFL'
    || 'WHRwWmloMVBUMXVkV3hzS1hKbGRIVnliaUJ2TG1wemVDZ2ljM0JoYmlJc2UyTnNZWE56VG1GdFpUb2liblZzYkNJc1kyaHBiR1J5Wlc0NklrNVZURXdpZlNr'
    || 'N1kyOXVjM1FnWkQxSmRDaDFLVHR5WlhSMWNtNGdaQ0U5UFc1MWJHdy9hMlVvWkNrNlUzUnlhVzVuS0hVcGZXWjFibU4wYVc5dUlFOWpLSHR3WTNRNmRTeHNZ'
    || 'V0psYkRwa0xHOW1PbU1zZEc5dVpUcDRmU2w3WTI5dWMzUWdSVDFOWVhSb0xtMWhlQ2d3TEUxaGRHZ3ViV2x1S0RFd01DeDFLU2s3Y21WMGRYSnVJRzh1YW5O'
    || 'NGN5Z2laR2wySWl4N1kyeGhjM05PWVcxbE9pSnRaWFJsY2kxeWIzY2lMR05vYVd4a2NtVnVPbHR2TG1wemVITW9JbVJwZGlJc2UyTnNZWE56VG1GdFpUb2li'
    || 'V1YwWlhJdGNtOTNYMTlvWldGa0lpeGphR2xzWkhKbGJqcGJieTVxYzNnb0luTndZVzRpTEh0amJHRnpjMDVoYldVNkltMWxkR1Z5TFhKdmQxOWZiR0ZpWld3'
    || 'aUxHTm9hV3hrY21WdU9tUjlLU3h2TG1wemVITW9Jbk53WVc0aUxIdGpiR0Z6YzA1aGJXVTZJbTFsZEdWeUxYSnZkMTlmZG1Gc2RXVWlMR05vYVd4a2NtVnVP'
    || 'bHRGTG5SdlJtbDRaV1FvTVNrc0lpVWlMR00vYnk1cWMzZ29Jbk53WVc0aUxIdGpiR0Z6YzA1aGJXVTZJbTFsZEdWeUxYSnZkMTlmYjJZaUxHTm9hV3hrY21W'
    || 'dU9tTjlLVHB1ZFd4c1hYMHBYWDBwTEc4dWFuTjRLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbTFsZEdWeUlpeGphR2xzWkhKbGJqcHZMbXB6ZUNnaVpHbDJJ'
    || 'aXg3WTJ4aGMzTk9ZVzFsT2lKdFpYUmxjbDlmWm1sc2JDSXJLSGcvSWlCdFpYUmxjbDlmWm1sc2JDMHRJaXQ0T2lJaUtTeHpkSGxzWlRwN2QybGtkR2c2UlNz'
    || 'aUpTSjlmU2w5S1YxOUtYMW1kVzVqZEdsdmJpQnZjeWg3WTJocGJHUnlaVzQ2ZFN4MGIyNWxPbVI5S1h0eVpYUjFjbTRnYnk1cWMzZ29Jbk53WVc0aUxIdGpi'
    || 'R0Z6YzA1aGJXVTZJbkJwYkd3aUt5aGtQeUlnY0dsc2JDMHRJaXRrT2lJaUtTeGphR2xzWkhKbGJqcDFmU2w5Wm5WdVkzUnBiMjRnVUdNb2UyRTZkU3hpT21R'
    || 'c1ltOTBhRHBqTEhWdWFYUTZlSDBwZTJOdmJuTjBJRVU5VFdGMGFDNXRZWGdvZFM1dUxHUXViaXd4S1N4VVBYazlQbnRqYjI1emRDQk9QWGt1Ymo0d1AyTXZl'
    || 'UzV1S2pFd01Eb3dPM0psZEhWeWJpQnZMbXB6ZUhNb0ltUnBkaUlzZTJOc1lYTnpUbUZ0WlRvaWIzWnNYMTl6YVdSbElpeGphR2xzWkhKbGJqcGJieTVxYzNo'
    || 'ektDSmthWFlpTEh0amJHRnpjMDVoYldVNkltOTJiRjlmYUdWaFpDSXNZMmhwYkdSeVpXNDZXMjh1YW5ONEtDSnpjR0Z1SWl4N1kyeGhjM05PWVcxbE9pSnZk'
    || 'bXhmWDI1aGJXVWlMR05vYVd4a2NtVnVPbmt1YkdGaVpXeDlLU3h2TG1wemVDZ2ljM0JoYmlJc2UyTnNZWE56VG1GdFpUb2liM1pzWDE5dUlpeGphR2xzWkhK'
    || 'bGJqcHJaU2g1TG00cGZTbGRmU2tzZVM1emRXSS9ieTVxYzNnb0ltUnBkaUlzZTJOc1lYTnpUbUZ0WlRvaWIzWnNYMTl6ZFdJaUxHTm9hV3hrY21WdU9ua3Vj'
    || 'M1ZpZlNrNmJuVnNiQ3h2TG1wemVDZ2laR2wySWl4N1kyeGhjM05PWVcxbE9pSnZkbXhmWDNSeVlXTnJJaXh6ZEhsc1pUcDdkMmxrZEdnNmVTNXVMMFVxTVRB'
    || 'd0t5SWxJbjBzWTJocGJHUnlaVzQ2Ynk1cWMzZ29JbVJwZGlJc2UyTnNZWE56VG1GdFpUb2liM1pzWDE5aWIzUm9JaXh6ZEhsc1pUcDdkMmxrZEdnNlRXRjBh'
    || 'QzV0YVc0b01UQXdMRTRwS3lJbEluMTlLWDBwTEc4dWFuTjRLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbTkyYkY5ZmNtRjBaU0lzWTJocGJHUnlaVzQ2ZVM1'
    || 'dVBqQS9ieTVxYzNoektHOHVSbkpoWjIxbGJuUXNlMk5vYVd4a2NtVnVPbHRPTG5SdlJtbDRaV1FvTVNrc0lpVWdiMllnSWl4NUxteGhZbVZzTG5SdlRHOTNa'
    || 'WEpEWVhObEtDa3NJaUJ0WVhSamFHVmtJbDE5S1RwdkxtcHplSE1vYnk1R2NtRm5iV1Z1ZEN4N1kyaHBiR1J5Wlc0Nld5SnVieUFpTEhrdWJHRmlaV3d1ZEc5'
    || 'TWIzZGxja05oYzJVb0tTd2lJSFJ2SUcxaGRHTm9JR0ZuWVdsdWMzUWlYWDBwZlNsZGZTeDVMbXhoWW1Wc0tYMDdjbVYwZFhKdUlHOHVhbk40Y3lnaVpHbDJJ'
    || 'aXg3WTJ4aGMzTk9ZVzFsT2lKdmRtd2lMR05vYVd4a2NtVnVPbHR2TG1wemVITW9JbVJwZGlJc2UyTnNZWE56VG1GdFpUb2liM1pzWDE5bWFXZDFjbVVpTEdO'
    || 'b2FXeGtjbVZ1T2x0VUtIVXBMRlFvWkNsZGZTa3NieTVxYzNoektDSmthWFlpTEh0amJHRnpjMDVoYldVNkltOTJiRjlmYldsa0lpeGphR2xzWkhKbGJqcGJi'
    || 'eTVxYzNnb0ltUnBkaUlzZTJOc1lYTnpUbUZ0WlRvaWIzWnNYMTl0YVdRdGJpSXNZMmhwYkdSeVpXNDZhMlVvWXlsOUtTeHZMbXB6ZUhNb0ltUnBkaUlzZTJO'
    || 'c1lYTnpUbUZ0WlRvaWIzWnNYMTl0YVdRdGJHRmlJaXhqYUdsc1pISmxianBiSW0xaGRHTm9aV1FpTEhnL0lpQWlLM2c2SWlJc2J5NXFjM2dvSW1KeUlpeDdm'
    || 'U2tzSW1sdUlHSnZkR2dnY0c5d2RXeGhkR2x2Ym5NaVhYMHBYWDBwWFgwcGZXWjFibU4wYVc5dUlFMWpLSHQwYVhSc1pUcDFMR05vYVd4a2NtVnVPbVI5S1h0'
    || 'eVpYUjFjbTRnYnk1cWMzaHpLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbU5oZG1WaGRDSXNJbVJoZEdFdGIyNWxjMmh2ZENJNkltTmhkbVZoZENJc1kyaHBi'
    || 'R1J5Wlc0NlcyOHVhbk40S0NKemRISnZibWNpTEh0amFHbHNaSEpsYmpwMWZTa3NieTVxYzNnb0luQWlMSHRqYUdsc1pISmxianBrZlNsZGZTbDlablZ1WTNS'
    || 'cGIyNGdjM01vZTJOb2FXeGtjbVZ1T25WOUtYdHlaWFIxY200Z2J5NXFjM2dvSW1ScGRpSXNlMk5zWVhOelRtRnRaVG9pYldWMGFHOWtJaXdpWkdGMFlTMXZi'
    || 'bVZ6YUc5MElqb2liV1YwYUc5a0lpeGphR2xzWkhKbGJqcDFmU2w5WTI5dWMzUWdXR3c5V3lKVFFVMVFURVVpTENKTVNVMUpWRVZFSWl3aVVGSlBSRlZEVkVs'
    || 'UFRpSmRMSFZ6UFh0VFFVMVFURVU2SWxObFpXUmxaQ0JrWVhSaElPS0FsQ0J6WVdabElIUnZJSEoxYmlCeVpYQmxZWFJsWkd4NUxDQndjbTkyWlhNZ2RHaGxJ'
    || 'SE5vWVhCbElIZHBkR2h2ZFhRZ2RHOTFZMmhwYm1jZ1lXNTVkR2hwYm1jZ2NtVmhiQzRpTEV4SlRVbFVSVVE2SWxsdmRYSWdaR0YwWVN3Z1pHVnNhV0psY21G'
    || 'MFpXeDVJR0p2ZFc1a1pXUWc0b0NVSUdFZ2MzVmljMlYwTENCaElHTmhjQ3dnYjNJZ1lTQnphVzVuYkdVZ2IySnFaV04wTGlJc1VGSlBSRlZEVkVsUFRqb2lX'
    || 'VzkxY2lCa1lYUmhMQ0JoZENCbWRXeHNJSE5qYjNCbExpQlNaV0ZrSUhSb1pTQjFibVJ2SUd4cGJtVWdZbVZtYjNKbElIbHZkU0J5ZFc0Z2FYUXVJbjA3Wm5W'
    || 'dVkzUnBiMjRnU1dNb2UyRmpkR2x2Ym5NNmRYMHBlMk52Ym5OMFcyUXNZMTA5VFhRdWRYTmxVM1JoZEdVb0lURXBMSGc5ZTMwN1ptOXlLR052Ym5OMElIa2di'
    || 'MllnZFNsN1kyOXVjM1FnVGoxVGRISnBibWNvZVM1VVNVVlNQejhpVUZKUFJGVkRWRWxQVGlJcExuUnZWWEJ3WlhKRFlYTmxLQ2s3S0hoYlRsMC9QeWg0VzA1'
    || 'ZFBWdGRLU2t1Y0hWemFDaDVLWDFqYjI1emRDQkZQWFV1YkdWdVozUm9MRlE5V0d3dVptbHNkR1Z5S0hrOVBudDJZWElnVGp0eVpYUjFjbTRvVGoxNFczbGRL'
    || 'VDA5Ym5Wc2JEOTJiMmxrSURBNlRpNXNaVzVuZEdoOUtTNXRZWEFvZVQwK0tIdDBhV1Z5T25rc1kyOTFiblE2ZUZ0NVhTNXNaVzVuZEdoOUtTazdjbVYwZFhK'
    || 'dUlHOHVhbk40Y3lodkxrWnlZV2R0Wlc1MExIdGphR2xzWkhKbGJqcGJieTVxYzNoektDSmlkWFIwYjI0aUxIdDBlWEJsT2lKaWRYUjBiMjRpTEdOc1lYTnpU'
    || 'bUZ0WlRvaVlXTjBMWE4xYlcxaGNua2lMRzl1UTJ4cFkyczZLQ2s5UG1Nb2VUMCtJWGtwTENKaGNtbGhMV1Y0Y0dGdVpHVmtJanBrTEdOb2FXeGtjbVZ1T2x0'
    || 'dkxtcHplSE1vSW5Od1lXNGlMSHRqYkdGemMwNWhiV1U2SW1GamRDMXpkVzF0WVhKNVgxOWpiM1Z1ZENJc1kyaHBiR1J5Wlc0NlcydGxLRVVwTENJZ1lXTjBh'
    || 'Vzl1SWl4RlBUMDlNVDhpSWpvaWN5SmRmU2tzVkM1dFlYQW9LSHQwYVdWeU9ua3NZMjkxYm5RNlRuMHBQVDV2TG1wemVITW9Jbk53WVc0aUxIdGpiR0Z6YzA1'
    || 'aGJXVTZJbUZqZEMxemRXMXRZWEo1WDE5MGFXVnlJaXhqYUdsc1pISmxianBiZVN3aUlDSXNUbDE5TEhrcEtTeHZMbXB6ZUNnaWMzWm5JaXg3WTJ4aGMzTk9Z'
    || 'VzFsT2lKaFkzUXRjM1Z0YldGeWVWOWZZMmhsZG5KdmJpSXJLR1EvSWlCaFkzUXRjM1Z0YldGeWVWOWZZMmhsZG5KdmJpMHRiM0JsYmlJNklpSXBMSGRwWkhS'
    || 'b09pSXhOQ0lzYUdWcFoyaDBPaUl4TkNJc2RtbGxkMEp2ZURvaU1DQXdJREUySURFMklpeG1hV3hzT2lKdWIyNWxJaXdpWVhKcFlTMW9hV1JrWlc0aU9pSjBj'
    || 'blZsSWl4amFHbHNaSEpsYmpwdkxtcHplQ2dpY0dGMGFDSXNlMlE2SWswMElEWnNOQ0EwSURRdE5DSXNjM1J5YjJ0bE9pSmpkWEp5Wlc1MFEyOXNiM0lpTEhO'
    || 'MGNtOXJaVmRwWkhSb09pSXhMalVpTEhOMGNtOXJaVXhwYm1WallYQTZJbkp2ZFc1a0lpeHpkSEp2YTJWTWFXNWxhbTlwYmpvaWNtOTFibVFpZlNsOUtWMTlL'
    || 'U3hrUDI4dWFuTjRjeWh2TGtaeVlXZHRaVzUwTEh0amFHbHNaSEpsYmpwYldHd3ViV0Z3S0hrOVBudGpiMjV6ZENCT1BYaGJlVjA3Y21WMGRYSnVJVTU4ZkNG'
    || 'T0xteGxibWQwYUQ5dWRXeHNPbTh1YW5ONGN5aE5kQzVHY21GbmJXVnVkQ3g3WTJocGJHUnlaVzQ2VzI4dWFuTjRLQ0p3SWl4N1kyeGhjM05PWVcxbE9pSmhZ'
    || 'M1JmWDNScFpYSWlMR05vYVd4a2NtVnVPbmw5S1N4dkxtcHplQ2dpY0NJc2UyTnNZWE56VG1GdFpUb2lZV04wWDE5MGFXVnlMV1JsYzJNaUxHTm9hV3hrY21W'
    || 'dU9uVnpXM2xkUHo4aUluMHBMRzh1YW5ONEtDSmthWFlpTEh0amJHRnpjMDVoYldVNkltRmpkRjlmWjNKcFpDSXNZMmhwYkdSeVpXNDZUaTV0WVhBb2FqMCti'
    || 'eTVxYzNoektDSmthWFlpTEh0amJHRnpjMDVoYldVNkltRmpkRjlmWTJGeVpDSXNZMmhwYkdSeVpXNDZXMjh1YW5ONEtDSmthWFlpTEh0amJHRnpjMDVoYldV'
    || 'NkltRmpkRjlmWTI5a1pTSXNZMmhwYkdSeVpXNDZVM1J5YVc1bktHb3VRMDlFUlNsOUtTeHZMbXB6ZUNnaVpHbDJJaXg3WTJ4aGMzTk9ZVzFsT2lKaFkzUmZY'
    || 'MnhoWW1Wc0lpeGphR2xzWkhKbGJqcFRkSEpwYm1jb2FpNU1RVUpGVEQ4L2FpNURUMFJGS1gwcExHOHVhbk40S0NKa2FYWWlMSHRqYkdGemMwNWhiV1U2SW1G'
    || 'amRGOWZaV1ptWldOMElpeGphR2xzWkhKbGJqcFRkSEpwYm1jb2FpNUZSa1pGUTFRL1B5TGlnSlFpS1gwcExHOHVhbk40Y3lnaVpHbDJJaXg3WTJ4aGMzTk9Z'
    || 'VzFsT2lKaFkzUmZYMjFsZEdFaUxHTm9hV3hrY21WdU9sdHZMbXB6ZUhNb0luTndZVzRpTEh0amFHbHNaSEpsYmpwYkluNGlMRVpqS0dvdVJWTlVYME5TUlVS'
    || 'SlZGTXBMQ0lnWTNKbFpHbDBjeUpkZlNrc2J5NXFjM2h6S0NKemNHRnVJaXg3WTJocGJHUnlaVzQ2VzJ0bEtHb3VVMVJCVkVWTlJVNVVVeWtzSWlCemRHMTBJ'
    || 'aXhhYkNocUxsTlVRVlJGVFVWT1ZGTXBQVDA5TVQ4aUlqb2ljeUpkZlNrc2FpNVZUa1JQWDFOVVFWUkZUVVZPVkZNL2J5NXFjM2dvSW5Od1lXNGlMSHRqYkdG'
    || 'emMwNWhiV1U2SW1GamRGOWZkVzVrYnlJc1kyaHBiR1J5Wlc0NkluVnVaRzhnWVhaaGFXeGhZbXhsSW4wcE9tOHVhbk40S0NKemNHRnVJaXg3WTJ4aGMzTk9Z'
    || 'VzFsT2lKaFkzUmZYMjV2ZFc1a2J5SXNZMmhwYkdSeVpXNDZJbTV2SUdGMWRHOHRkVzVrYnlKOUtWMTlLU3hhYkNocUxsUkpUVVZUWDFKVlRpaytNRDl2TG1w'
    || 'emVITW9JbVJwZGlJc2UyTnNZWE56VG1GdFpUb2lZV04wWDE5eWRXNXpJaXhqYUdsc1pISmxianBiSWxKMWJpQWlMR3RsS0dvdVZFbE5SVk5mVWxWT0tTd2ll'
    || 'Q0lzV213b2FpNVVTVTFGVTE5VlRrUlBUa1VwUGpBL1lDd2dkVzVrYjI1bElDUjdhMlVvYWk1VVNVMUZVMTlWVGtSUFRrVXBmWGhnT2lJaVhYMHBPbTUxYkd4'
    || 'ZGZTeFRkSEpwYm1jb2FpNURUMFJGS1NrcGZTbGRmU3g1S1gwcExHOHVhbk40S0NKd0lpeDdZMnhoYzNOT1lXMWxPaUpoWTNSZlgyWnZiM1FpTEdOb2FXeGtj'
    || 'bVZ1T2lKVWFHVWdZMjl1ZEhKdmJITWdabTl5SUhSb1pYTmxJR0ZqZEdsdmJuTWdZWEpsSUdKbGJHOTNJSFJvWlNCa1lYTm9ZbTloY21RZzRvQ1VJSE5qY205'
    || 'c2JDQndZWE4wSUhSb1pTQmphR0Z5ZEhNZ2RHOGdabWx1WkNCMGFHVWdZblYwZEc5dWN5QmhibVFnWTI5dVptbHliV0YwYVc5dUlITjBaWEF1SW4wcFhYMHBP'
    || 'bTUxYkd4ZGZTbDlablZ1WTNScGIyNGdSR01vZTNObGRIUnBibWM2ZFgwcGUzSmxkSFZ5YmlCdkxtcHplSE1vSW1ScGRpSXNlMk5zWVhOelRtRnRaVG9pYm05'
    || 'MGVXVjBJSEJoYm1Wc0xXNXZkR0oxYVd4MElpd2laR0YwWVMxdmJtVnphRzkwSWpvaWNHRnVaV3d0Ym05MFluVnBiSFFpTEdOb2FXeGtjbVZ1T2x0dkxtcHpl'
    || 'Q2dpYzNSeWIyNW5JaXg3WTJocGJHUnlaVzQ2SWs1dklHRmpkR2x2Ym5NZ2QyVnlaU0J5WldkcGMzUmxjbVZrSUdKNUlIUm9hWE1nY25WdUxpSjlLU3h2TG1w'
    || 'emVITW9JbkFpTEh0amJHRnpjMDVoYldVNkltNXZkSGxsZEY5ZmQyaDVJaXhqYUdsc1pISmxianBiSWxSb2FYTWdjMk55YVhCMElIZGhjeUJ5ZFc0Z2QybDBh'
    || 'Q0FpTEc4dWFuTjRjeWdpWTI5a1pTSXNlMk5vYVd4a2NtVnVPbHQxTENJZ1BTQkdRVXhUUlNKZGZTa3NJaXdnZDJocFkyZ2dhWE1nZEdobElHUmxabUYxYkhR'
    || 'NklHbDBJR2x1YzNCbFkzUnpJSFJvWlNCaFkyTnZkVzUwSUdGdVpDQmlkV2xzWkhNZ2RtbGxkM01zSUdGdVpDQnlaV2RwYzNSbGNuTWdibTkwYUdsdVp5QjBh'
    || 'R0YwSUdOdmRXeGtJR05vWVc1blpTQmhibmwwYUdsdVp5NGdVMlYwSUNJc2J5NXFjM2h6S0NKamIyUmxJaXg3WTJocGJHUnlaVzQ2VzNVc0lpQTlJRlJTVlVV'
    || 'aVhYMHBMQ0lnWVc1a0lISjFiaUJwZENCaFoyRnBiaUIwYnlCbWFXeHNJSFJvYVhNZ2NHRm5aU0JwYmk0aVhYMHBMRzh1YW5ONEtDSndJaXg3WTJ4aGMzTk9Z'
    || 'VzFsT2lKdWIzUjVaWFJmWDNkb1lYUWlMR05vYVd4a2NtVnVPaUpQYm1ObElHbDBJR2x6SUdacGJHeGxaQ0JwYml3Z1pYWmxjbmtnWVdOMGFXOXVJR0Z3Y0dW'
    || 'aGNuTWdhR1Z5WlNCMWJtUmxjaUJ2Ym1VZ2IyWWdkR2h5WldVZ2RHbGxjbk02SW4wcExHOHVhbk40S0NKdmJDSXNlMk5zWVhOelRtRnRaVG9pYm05MGVXVjBY'
    || 'MTkwYVdWeWN5SXNZMmhwYkdSeVpXNDZXR3d1YldGd0tHUTlQbTh1YW5ONGN5Z2liR2tpTEh0amFHbHNaSEpsYmpwYmJ5NXFjM2dvSW5Od1lXNGlMSHRqYkdG'
    || 'emMwNWhiV1U2SW01dmRIbGxkRjlmZEdsbGNpSXNZMmhwYkdSeVpXNDZaSDBwTEc4dWFuTjRLQ0p6Y0dGdUlpeDdZMnhoYzNOT1lXMWxPaUp1YjNSNVpYUmZY'
    || 'M1JwWlhJdFpHVnpZeUlzWTJocGJHUnlaVzQ2ZFhOYlpGMTlLVjE5TEdRcEtYMHBMRzh1YW5ONEtDSndJaXg3WTJ4aGMzTk9ZVzFsT2lKdWIzUjVaWFJmWDJa'
    || 'dmIzUWlMR05vYVd4a2NtVnVPaUpGWVdOb0lHOXVaU0J6ZEdGMFpYTWdhWFJ6SUdWemRHbHRZWFJsWkNCamNtVmthWFJ6TENCb2IzY2diV0Z1ZVNCemRHRjBa'
    || 'VzFsYm5SeklHbDBJSEoxYm5Nc0lHRnVaQ0IzYUdWMGFHVnlJR2wwSUdOaGJpQmlaU0IxYm1SdmJtVWc0b0NVSUdKbFptOXlaU0JoYm5saWIyUjVJSEJ5WlhO'
    || 'elpYTWdZVzU1ZEdocGJtY3VJbjBwWFgwcGZXWjFibU4wYVc5dUlIcGpLSHRzYjJjNmRYMHBlMk52Ym5OMFcyUXNZMTA5VFhRdWRYTmxVM1JoZEdVb0lURXBM'
    || 'SGc5ZFM1c1pXNW5kR2dzUlQxMUxtWnBiSFJsY2loNVBUNTdZMjl1YzNRZ1RqMVRkSEpwYm1jb2VTNVRWRUZVVlZNL1B5SWlLUzUwYjFWd2NHVnlRMkZ6WlNn'
    || 'cE8zSmxkSFZ5YmlCT1BUMDlJa1JQVGtVaWZIeE9QVDA5SWxWT1JFOU9SU0o5S1M1c1pXNW5kR2dzVkQxMUxtWnBiSFJsY2loNVBUNVRkSEpwYm1jb2VTNVRW'
    || 'RUZVVlZNL1B5SWlLUzUwYjFWd2NHVnlRMkZ6WlNncFBUMDlJa1pCU1V4RlJDSXBMbXhsYm1kMGFEdHlaWFIxY200Z2J5NXFjM2h6S0c4dVJuSmhaMjFsYm5R'
    || 'c2UyTm9hV3hrY21WdU9sdHZMbXB6ZUhNb0ltSjFkSFJ2YmlJc2UzUjVjR1U2SW1KMWRIUnZiaUlzWTJ4aGMzTk9ZVzFsT2lKaFkzUXRjM1Z0YldGeWVTSXNi'
    || 'MjVEYkdsamF6b29LVDArWXloNVBUNGhlU2tzSW1GeWFXRXRaWGh3WVc1a1pXUWlPbVFzWTJocGJHUnlaVzQ2VzI4dWFuTjRjeWdpYzNCaGJpSXNlMk5zWVhO'
    || 'elRtRnRaVG9pWVdOMExYTjFiVzFoY25sZlgyTnZkVzUwSWl4amFHbHNaSEpsYmpwYmEyVW9lQ2tzSWlCemRHVndJaXg0UFQwOU1UOGlJam9pY3lKZGZTa3Ni'
    || 'eTVxYzNoektDSnpjR0Z1SWl4N1kyaHBiR1J5Wlc0NlcwVXNJaUJqYjIxd2JHVjBaV1FpTEZRK01EOWdMQ0FrZTFSOUlHWmhhV3hsWkdBNklpSmRmU2tzYnk1'
    || 'cWMzZ29Jbk4yWnlJc2UyTnNZWE56VG1GdFpUb2lZV04wTFhOMWJXMWhjbmxmWDJOb1pYWnliMjRpS3loa1B5SWdZV04wTFhOMWJXMWhjbmxmWDJOb1pYWnli'
    || 'MjR0TFc5d1pXNGlPaUlpS1N4M2FXUjBhRG9pTVRRaUxHaGxhV2RvZERvaU1UUWlMSFpwWlhkQ2IzZzZJakFnTUNBeE5pQXhOaUlzWm1sc2JEb2libTl1WlNJ'
    || 'c0ltRnlhV0V0YUdsa1pHVnVJam9pZEhKMVpTSXNZMmhwYkdSeVpXNDZieTVxYzNnb0luQmhkR2dpTEh0a09pSk5OQ0EyYkRRZ05DQTBMVFFpTEhOMGNtOXJa'
    || 'VG9pWTNWeWNtVnVkRU52Ykc5eUlpeHpkSEp2YTJWWGFXUjBhRG9pTVM0MUlpeHpkSEp2YTJWTWFXNWxZMkZ3T2lKeWIzVnVaQ0lzYzNSeWIydGxUR2x1Wldw'
    || 'dmFXNDZJbkp2ZFc1a0luMHBmU2xkZlNrc1pEOXZMbXB6ZUNoRWRDeDdjbTkzY3pwMUxHTnZiSE02VzN0clpYazZJa05QUkVVaUxHeGhZbVZzT2lKQlkzUnBi'
    || 'MjRpZlN4N2EyVjVPaUpUVkVGVVZWTWlMR3hoWW1Wc09pSlRkR0YwZFhNaUxISmxibVJsY2pwNVBUNTdZMjl1YzNRZ1RqMVRkSEpwYm1jb2VUOC9JaUlwTEdv'
    || 'OVRqMDlQU0pFVDA1RklueDhUajA5UFNKVlRrUlBUa1VpUHlKbmIyOWtJanBPUFQwOUlrWkJTVXhGUkNJL0ltSmhaQ0k2SW5kaGNtNGlPM0psZEhWeWJpQnZM'
    || 'bXB6ZUNodmN5eDdkRzl1WlRwcUxHTm9hV3hrY21WdU9rNThmQ0xpZ0pRaWZTbDlmU3g3YTJWNU9pSlRWRUZVUlUxRlRsUlRYMUpWVGlJc2JHRmlaV3c2SWxO'
    || 'MGJYUnpJaXhoYkdsbmJqb2ljbWxuYUhRaWZTeDdhMlY1T2lKVFZFRlNWRVZFWDBGVUlpeHNZV0psYkRvaVUzUmhjblJsWkNJc2NtVnVaR1Z5T25rOVBuay9V'
    || 'M1J5YVc1bktIa3BMbk5zYVdObEtEQXNNVGtwTG5KbGNHeGhZMlVvSWxRaUxDSWdJaWs2SXVLQWxDSjlMSHRyWlhrNklrWkpUa2xUU0VWRVgwRlVJaXhzWVdK'
    || 'bGJEb2lSbWx1YVhOb1pXUWlMSEpsYm1SbGNqcDVQVDU1UDFOMGNtbHVaeWg1S1M1emJHbGpaU2d3TERFNUtTNXlaWEJzWVdObEtDSlVJaXdpSUNJcE9pTGln'
    || 'SlFpZlN4N2EyVjVPaUpGVWxKUFVpSXNiR0ZpWld3NklrVnljbTl5SWl4eVpXNWtaWEk2ZVQwK2VUOXZMbXB6ZUNnaWMzQmhiaUlzZTNScGRHeGxPbE4wY21s'
    || 'dVp5aDVLU3hqYUdsc1pISmxianBUZEhKcGJtY29lU2t1YzJ4cFkyVW9NQ3cyTUNsOUtUb2k0b0NVSW4xZGZTazZiblZzYkYxOUtYMW1kVzVqZEdsdmJpQkdZ'
    || 'eWgxS1h0cFppaDFQVDF1ZFd4c0tYSmxkSFZ5YmlMaWdKUWlPM1J5ZVh0eVpYUjFjbTRnVG5WdFltVnlLSFVwTG5SdlJtbDRaV1FvTXlrdWNtVndiR0ZqWlNn'
    || 'dk1Dc2tMeXdpSWlrdWNtVndiR0ZqWlNndlhDNGtMeXdpSWlsOGZDSXdJbjFqWVhSamFIdHlaWFIxY200Z1UzUnlhVzVuS0hVcGZYMW1kVzVqZEdsdmJpQmFi'
    || 'Q2gxS1h0eVpYUjFjbTRnZEhsd1pXOW1JSFU5UFNKdWRXMWlaWElpUDNVNlRuVnRZbVZ5S0hVcGZId3dmV1oxYm1OMGFXOXVJRUZqS0h0d2IybHVkSE02ZFN4'
    || 'M2FXUjBhRHBrUFRJMk1DeG9aV2xuYUhRNll6MDBObjBwZTJOdmJuTjBJSGc5ZFM1dFlYQW9URDArVG5WdFltVnlLRXdwZkh3d0tUdHBaaWg0TG14bGJtZDBh'
    || 'RHd5S1hKbGRIVnliaUJ2TG1wemVDZ2ljQ0lzZTJOc1lYTnpUbUZ0WlRvaWNHRnVaV3d0Wlcxd2RIa2lMQ0prWVhSaExXOXVaWE5vYjNRaU9pSndZVzVsYkMx'
    || 'bGJYQjBlU0lzWTJocGJHUnlaVzQ2SWs1dmRDQmxibTkxWjJnZ2FHbHpkRzl5ZVNCMGJ5QmtjbUYzSUdFZ2RISmxibVF1SW4wcE8yTnZibk4wSUVVOVRXRjBh'
    || 'QzV0YVc0b0xpNHVlQ2tzZVQxTllYUm9MbTFoZUNndUxpNTRLUzFGZkh3eExFNDlURDArVEM4b2VDNXNaVzVuZEdndE1Ta3FLR1F0TkNrck1peHFQVXc5UG1N'
    || 'dE5DMG9UQzFGS1M5NUtpaGpMVEV3S1N4SFBYZ3ViV0Z3S0NoTUxFWXBQVDVnSkh0R1B5Sk1Jam9pVFNKOUpIdE9LRVlwTG5SdlJtbDRaV1FvTVNsOUxDUjdh'
    || 'aWhNS1M1MGIwWnBlR1ZrS0RFcGZXQXBMbXB2YVc0b0lpQWlLVHR5WlhSMWNtNGdieTVxYzNoektDSnpkbWNpTEh0amJHRnpjMDVoYldVNkluTndZWEpySWl4'
    || 'M2FXUjBhRHBrTEdobGFXZG9kRHBqTEhacFpYZENiM2c2WURBZ01DQWtlMlI5SUNSN1kzMWdMQ0poY21saExXaHBaR1JsYmlJNkluUnlkV1VpTEdOb2FXeGtj'
    || 'bVZ1T2x0dkxtcHplQ2dpY0dGMGFDSXNlMk5zWVhOelRtRnRaVG9pYzNCaGNtdGZYMkZ5WldFaUxHUTZZQ1I3UjMwZ1RDUjdUaWg0TG14bGJtZDBhQzB4S1M1'
    || 'MGIwWnBlR1ZrS0RFcGZTd2tlMk45SUV3a2UwNG9NQ2t1ZEc5R2FYaGxaQ2d4S1gwc0pIdGpmU0JhWUgwcExHOHVhbk40S0NKd1lYUm9JaXg3WTJ4aGMzTk9Z'
    || 'VzFsT2lKemNHRnlhMTlmYkdsdVpTSXNaRHBIZlNrc2J5NXFjM2dvSW1OcGNtTnNaU0lzZTJOc1lYTnpUbUZ0WlRvaWMzQmhjbXRmWDJSdmRDSXNZM2c2VGlo'
    || 'NExteGxibWQwYUMweEtTeGplVHBxS0hoYmVDNXNaVzVuZEdndE1WMHBMSEk2SWpJdU5pSjlLVjE5S1gxbWRXNWpkR2x2YmlCVll5aDdjM1JoWjJWek9uVjlL'
    || 'WHR5WlhSMWNtNGdieTVxYzNnb0ltUnBkaUlzZTJOc1lYTnpUbUZ0WlRvaVpteHZkeUlzY205c1pUb2lhVzFuSWl3aVlYSnBZUzFzWVdKbGJDSTZJa1JoZEdF'
    || 'Z1pteHZkem9nSWl0MUxtMWhjQ2hrUFQ1a0xteGhZbVZzS1M1cWIybHVLQ0lnZEdobGJpQWlLU3hqYUdsc1pISmxianAxTG0xaGNDZ29aQ3hqS1QwK2J5NXFj'
    || 'M2h6S0UxMExrWnlZV2R0Wlc1MExIdGphR2xzWkhKbGJqcGJieTVxYzNoektDSmthWFlpTEh0amJHRnpjMDVoYldVNkltWnNiM2RmWDJKdmVDSXJLR1F1Ykds'
    || 'MlpUOGlJR1pzYjNkZlgySnZlQzB0YjI0aU9pSWlLU3hqYUdsc1pISmxianBiYnk1cWMzZ29JbVJwZGlJc2UyTnNZWE56VG1GdFpUb2labXh2ZDE5ZmJHRmlJ'
    || 'aXhqYUdsc1pISmxianBrTG14aFltVnNmU2tzWkM1emRXSS9ieTVxYzNnb0ltUnBkaUlzZTJOc1lYTnpUbUZ0WlRvaVpteHZkMTlmYzNWaUlpeGphR2xzWkhK'
    || 'bGJqcGtMbk4xWW4wcE9tNTFiR3hkZlNrc1l6eDFMbXhsYm1kMGFDMHhQMjh1YW5ONEtDSmthWFlpTEh0amJHRnpjMDVoYldVNkltWnNiM2RmWDJ4cGJtc2lL'
    || 'eWhrTG14cGRtVW1KblZiWXlzeFhTNXNhWFpsUHlJZ1pteHZkMTlmYkdsdWF5MHRiMjRpT2lJaUtYMHBPbTUxYkd4ZGZTeGtMbXhoWW1Wc0tTbDlLWDFqYjI1'
    || 'emRDQWtZejE3VFVWVU9pTGluSk1pTEU1UFZGOU5SVlE2SXVLY2x5SXNVRVZPUkVsT1J6b2k0b0NVSWl3aVRpOUJJam9pNHBlTEluMHNZWE05ZTAxRlZEb2lU'
    || 'VVZVSWl4T1QxUmZUVVZVT2lKT1QxUWdUVVZVSWl4UVJVNUVTVTVIT2lKUVJVNUVTVTVISWl3aVRpOUJJam9pVGk5QkluMHNjV3c5ZTAxRlZEb2liV1YwSWl4'
    || 'T1QxUmZUVVZVT2lKdWIzUnRaWFFpTEZCRlRrUkpUa2M2SW5CbGJtUnBibWNpTENKT0wwRWlPaUp1WVNKOU8yWjFibU4wYVc5dUlFaGpLSHQyT25Vc2IyNVBj'
    || 'R1Z1T21SOUtYdGpiMjV6ZENCalBYVXVkbVZ5WkdsamREMDlQU0pPVDFSZlRVVlVJajhpWW1Ga0lqcDFMblpsY21ScFkzUTlQVDBpVFVWVUlqOGlaMjl2WkNJ'
    || 'NmRTNTJaWEprYVdOMFBUMDlJazFGVkY5WFNWUklYMUJGVGtSSlRrY2lQeUozWVhKdUlqb2lhV1JzWlNJc2VEMTFMblZ1WVhaaGFXeGhZbXhsUHlKUVQwTWdj'
    || 'M1ZqWTJWemN6b2dibTkwSUdKMWFXeDBJanAxTG5abGNtUnBZM1E5UFQwaVRrOVVYMUpWVGlJL0lsQlBReUJ6ZFdOalpYTnpPaUJ1YjNRZ2MyTnZjbVZrSWpw'
    || 'Z1VFOURJSE4xWTJObGMzTTZJQ1I3ZFM1dFpYUjlJRzltSUNSN2RTNXpZMjl5WldSOUlHTnlhWFJsY21saElHMWxkR0FyS0hVdWNHVnVaR2x1Wno5Z0xDQWtl'
    || 'M1V1Y0dWdVpHbHVaMzBnY0dWdVpHbHVaMkE2SWlJcExFVTlieTVxYzNoektHOHVSbkpoWjIxbGJuUXNlMk5vYVd4a2NtVnVPbHR2TG1wemVDZ2ljM0JoYmlJ'
    || 'c2UyTnNZWE56VG1GdFpUb2ljRzlqTFdOb2FYQmZYMjUxYlNJc1kyaHBiR1J5Wlc0NmRTNTFibUYyWVdsc1lXSnNaWHg4ZFM1MlpYSmthV04wUFQwOUlrNVBW'
    || 'RjlTVlU0aVB5TGlnSlFpT21Ba2UzVXViV1YwZlM4a2UzVXVjMk52Y21Wa2ZXQjlLU3h2TG1wemVDZ2ljM0JoYmlJc2UyTnNZWE56VG1GdFpUb2ljRzlqTFdO'
    || 'b2FYQmZYM2R2Y21RaUxHTm9hV3hrY21WdU9uVXVkVzVoZG1GcGJHRmliR1UvSW01dmRDQmlkV2xzZENJNmRTNTJaWEprYVdOMFBUMDlJazVQVkY5U1ZVNGlQ'
    || 'eUp1YjNRZ2MyTnZjbVZrSWpvaWJXVjBJbjBwTEhVdWJtOTBUV1YwUDI4dWFuTjRjeWdpYzNCaGJpSXNlMk5zWVhOelRtRnRaVG9pY0c5akxXTm9hWEJmWDJa'
    || 'c1lXY2lMR05vYVd4a2NtVnVPbHQxTG01dmRFMWxkQ3dpSUdaaGFXeGxaQ0pkZlNrNmJuVnNiQ3gxTG5CbGJtUnBibWNtSmlGMUxtNXZkRTFsZEQ5dkxtcHpl'
    || 'SE1vSW5Od1lXNGlMSHRqYkdGemMwNWhiV1U2SW5Cdll5MWphR2x3WDE5bWJHRm5JaXhqYUdsc1pISmxianBiZFM1d1pXNWthVzVuTENJZ2NHVnVaR2x1WnlK'
    || 'ZGZTazZiblZzYkYxOUtUdHlaWFIxY200Z1pEOXZMbXB6ZUNnaVluVjBkRzl1SWl4N2RIbHdaVG9pWW5WMGRHOXVJaXdpWkdGMFlTMXdiMk1pT25VdWRtVnla'
    || 'R2xqZEN4amJHRnpjMDVoYldVNkluQnZZeTFqYUdsd0lIQnZZeTFqYUdsd0xTMGlLMk1zYjI1RGJHbGphenBrTENKaGNtbGhMV3hoWW1Wc0lqcDRMSFJwZEd4'
    || 'bE9uZ3NZMmhwYkdSeVpXNDZSWDBwT204dWFuTjRLQ0p6Y0dGdUlpeDdJbVJoZEdFdGNHOWpJanAxTG5abGNtUnBZM1FzWTJ4aGMzTk9ZVzFsT2lKd2IyTXRZ'
    || 'MmhwY0NCd2IyTXRZMmhwY0MwdElpdGpLeUlnY0c5akxXTm9hWEF0TFhOMFlYUnBZeUlzSW1GeWFXRXRiR0ZpWld3aU9uZ3NkR2wwYkdVNmVDeGphR2xzWkhK'
    || 'bGJqcEZmU2w5Wm5WdVkzUnBiMjRnWTNNb2UyTnlhWFJsY21saE9uVXNkanBrTEhCaGJtVnNPbU1zZG1WeVpHbGpkRkJoYm1Wc09uaDlLWHQyWVhJZ1ZEdGpi'
    || 'MjV6ZENCRlBTZ29WRDExTG1acGJtUW9lVDArZVM1amIyMXdZWEpoWW1sc2FYUjVLU2s5UFc1MWJHdy9kbTlwWkNBd09sUXVZMjl0Y0dGeVlXSnBiR2wwZVNr'
    || 'L1B5SWlPM0psZEhWeWJpQnZMbXB6ZUhNb2J5NUdjbUZuYldWdWRDeDdZMmhwYkdSeVpXNDZXMjh1YW5ONEtGZGxMSHQwYVhSc1pUb2lWbVZ5WkdsamRDSXNk'
    || 'MmxrWlRvaE1DeG9hVzUwT2lKRGIzVnVkR1ZrSUdaeWIyMGdkR2hsSUdOeWFYUmxjbWxoSUdKbGJHOTNMaUJPTDBFZ1kzSnBkR1Z5YVdFZ1lYSmxJR1Y0WTJ4'
    || 'MVpHVmtJR1p5YjIwZ2RHaGxJR1JsYm05dGFXNWhkRzl5TGlJc1kyaHBiR1J5Wlc0NmJ5NXFjM2dvU21Vc2UzQmhibVZzT25nL1AyTXNkMmhsYmsxcGMzTnBi'
    || 'bWM2Ynk1cWMzZ29ieTVHY21GbmJXVnVkQ3g3WTJocGJHUnlaVzQ2SWxSb1pTQndiR0Z1SUhOMFpYQWdZblZwYkdSeklIUm9aU0J6WTI5eVpXTmhjbVFnZG1s'
    || 'bGQzTXVJRVpwYkd3Z2FXNGdkR2hsSUhObGRIUnBibWR6SUdGMElIUm9aU0IwYjNBZ2IyWWdkR2hsSUhOamNtbHdkQ0JoYm1RZ2NuVnVJR2wwSUdGbllXbHVJ'
    || 'SFJ2SUdoaGRtVWdkR2hwY3lCUVQwTWdjMk52Y21Wa0xpSjlLU3hqYUdsc1pISmxianB2TG1wemVITW9JbVJwZGlJc2UyTnNZWE56VG1GdFpUb2ljRzlqWDE5'
    || 'MlpYSmthV04wSUhCdlkxOWZkbVZ5WkdsamRDMHRJaXNvWkM1MlpYSmthV04wUFQwOUlrNVBWRjlOUlZRaVB5SmlZV1FpT21RdWRtVnlaR2xqZEQwOVBTSk5S'
    || 'VlFpUHlKbmIyOWtJanBrTG5abGNtUnBZM1E5UFQwaVRVVlVYMWRKVkVoZlVFVk9SRWxPUnlJL0luZGhjbTRpT2lKcFpHeGxJaWtzWTJocGJHUnlaVzQ2VzI4'
    || 'dWFuTjRLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbkJ2WTE5ZmFHVmhaR3hwYm1VaUxHTm9hV3hrY21WdU9tUXVhR1ZoWkd4cGJtVjlLU3h2TG1wemVDZ2lj'
    || 'Q0lzZTJOc1lYTnpUbUZ0WlRvaWNHOWpYMTl5WldGa0lpeGphR2xzWkhKbGJqcGtMbkpsWVdSVWFHbHpmU2tzYnk1cWMzZ29JbVJwZGlJc2UyTnNZWE56VG1G'
    || 'dFpUb2ljRzlqWDE5MFlXeHNlU0lzWTJocGJHUnlaVzQ2V3lKTlJWUWlMQ0pPVDFSZlRVVlVJaXdpVUVWT1JFbE9SeUlzSWs0dlFTSmRMbTFoY0NoNVBUNTdZ'
    || 'Mjl1YzNRZ1RqMTVQVDA5SWsxRlZDSS9aQzV0WlhRNmVUMDlQU0pPVDFSZlRVVlVJajlrTG01dmRFMWxkRHA1UFQwOUlsQkZUa1JKVGtjaVAyUXVjR1Z1Wkds'
    || 'dVp6cGtMbTVoTzNKbGRIVnliaUJ2TG1wemVITW9Jbk53WVc0aUxIdGpiR0Z6YzA1aGJXVTZJbkJ2WTE5ZmRHbGpheUJ3YjJOZlgzUnBZMnN0TFNJcmNXeGJl'
    || 'VjBzWTJocGJHUnlaVzQ2VzI4dWFuTjRLQ0ppSWl4N1kyaHBiR1J5Wlc0NlRuMHBMQ0lnSWl4aGMxdDVYVjE5TEhrcGZTbDlLVjE5S1gwcGZTa3NieTVxYzNn'
    || 'b1YyVXNlM1JwZEd4bE9pSkRjbWwwWlhKcFlTSXNkMmxrWlRvaE1DeG9hVzUwT2lKRllXTm9JSFJoY21kbGRDQnBjeUJrWlhKcGRtVmtJR1p5YjIwZ2VXOTFj'
    || 'aUJoWTJOdmRXNTBMQ0JoYm1RZ1pXRmphQ0J5YjNjZ2MyaHZkM01nZEdobElHRnlhWFJvYldWMGFXTWdZbVZvYVc1a0lHbDBjeUJ6ZEdGMFpTNGlMR05vYVd4'
    || 'a2NtVnVPbTh1YW5ONEtFcGxMSHR3WVc1bGJEcGpMSGRvWlc1TmFYTnphVzVuT204dWFuTjRLRzh1Um5KaFoyMWxiblFzZTJOb2FXeGtjbVZ1T2lKT2J5Qmpj'
    || 'bWwwWlhKcFlTQm9ZWFpsSUdKbFpXNGdjMk52Y21Wa0lHSmxZMkYxYzJVZ2RHaGxJSFpwWlhkeklIUm9aWGtnY21WaFpDQjNaWEpsSUc1dmRDQmlkV2xzZENC'
    || 'aWVTQjBhR2x6SUhKMWJpNGlmU2tzWTJocGJHUnlaVzQ2Ynk1cWMzaHpLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbkJ2WXlJc1kyaHBiR1J5Wlc0NlczVXVi'
    || 'V0Z3S0hrOVBtOHVhbk40Y3lnaVpHbDJJaXg3WTJ4aGMzTk9ZVzFsT2lKd2IyTXRjbTkzSUhCdll5MXliM2N0TFNJcmNXeGJlUzV6ZEdGMFpWMHNZMmhwYkdS'
    || 'eVpXNDZXMjh1YW5ONEtDSmthWFlpTEh0amJHRnpjMDVoYldVNkluQnZZeTF5YjNkZlgyMWhjbXNpTENKaGNtbGhMV2hwWkdSbGJpSTZJblJ5ZFdVaUxHTm9h'
    || 'V3hrY21WdU9pUmpXM2t1YzNSaGRHVmRmU2tzYnk1cWMzaHpLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbkJ2WXkxeWIzZGZYMkp2WkhraUxHTm9hV3hrY21W'
    || 'dU9sdHZMbXB6ZUhNb0ltUnBkaUlzZTJOc1lYTnpUbUZ0WlRvaWNHOWpMWEp2ZDE5ZmRHOXdJaXhqYUdsc1pISmxianBiYnk1cWMzZ29Jbk53WVc0aUxIdGpi'
    || 'R0Z6YzA1aGJXVTZJbkJ2WXkxeWIzZGZYMnhoWW1Wc0lpeGphR2xzWkhKbGJqcDVMbXhoWW1Wc2ZIeDVMbU52WkdWOUtTeHZMbXB6ZUNnaWMzQmhiaUlzZTJO'
    || 'c1lYTnpUbUZ0WlRvaWNHOWpMWEp2ZDE5ZmMzUmhkR1VnY0c5akxYSnZkMTlmYzNSaGRHVXRMU0lyY1d4YmVTNXpkR0YwWlYwc1kyaHBiR1J5Wlc0NllYTmJl'
    || 'UzV6ZEdGMFpWMTlLVjE5S1N4NUxuZG9lVDl2TG1wemVDZ2ljQ0lzZTJOc1lYTnpUbUZ0WlRvaWNHOWpMWEp2ZDE5ZmQyaDVJaXhqYUdsc1pISmxianA1TG5k'
    || 'b2VYMHBPbTUxYkd3c2VTNWhjbWwwYUcxbGRHbGpQMjh1YW5ONEtDSndJaXg3WTJ4aGMzTk9ZVzFsT2lKd2IyTXRjbTkzWDE5dFlYUm9JaXhqYUdsc1pISmxi'
    || 'anB2TG1wemVDZ2lZMjlrWlNJc2UyTm9hV3hrY21WdU9ua3VZWEpwZEdodFpYUnBZMzBwZlNrNmJ5NXFjM2dvSW5BaUxIdGpiR0Z6YzA1aGJXVTZJbkJ2WXkx'
    || 'eWIzZGZYMjFoZEdnZ2NHOWpMWEp2ZDE5ZmJXRjBhQzB0Ym05dVpTSXNZMmhwYkdSeVpXNDZieTVxYzNoektDSnpjR0Z1SWl4N1kyaHBiR1J5Wlc0Nld5SjBZ'
    || 'WEpuWlhRZ0lpeDVMblJoY21kbGREMDlQVzUxYkd3L0l1S0FsQ0k2YTJVb2VTNTBZWEpuWlhRcExIa3VkVzVwZEhNL0lpQWlLM2t1ZFc1cGRITTZJaUlzSWlE'
    || 'Q3R5QmhZM1IxWVd3Z2JtOTBJR0YyWVdsc1lXSnNaU0pkZlNsOUtTeDVMbmRvZVU1dmREOXZMbXB6ZUNnaWNDSXNlMk5zWVhOelRtRnRaVG9pY0c5akxYSnZk'
    || 'MTlmY0dWdVpDSXNZMmhwYkdSeVpXNDZlUzUzYUhsT2IzUjlLVHB1ZFd4c0xIa3VjbVZ6YjJ4MlpYTlhhR1Z1UDI4dWFuTjRjeWdpY0NJc2UyTnNZWE56VG1G'
    || 'dFpUb2ljRzlqTFhKdmQxOWZkMmhsYmlJc1kyaHBiR1J5Wlc0Nld5SlNaWE52YkhabGN5QjNhR1Z1T2lBaUxIa3VjbVZ6YjJ4MlpYTlhhR1Z1WFgwcE9tNTFi'
    || 'R3dzYnk1cWMzaHpLQ0prYkNJc2UyTnNZWE56VG1GdFpUb2ljRzlqTFhKdmQxOWZiV1YwWVNJc1kyaHBiR1J5Wlc0NlcyOHVhbk40Y3lnaVpHbDJJaXg3WTJo'
    || 'cGJHUnlaVzQ2VzI4dWFuTjRLQ0prZENJc2UyTm9hV3hrY21WdU9pSkliM2NnZEdobElIUmhjbWRsZENCM1lYTWdjMlYwSW4wcExHOHVhbk40S0NKa1pDSXNl'
    || 'Mk5vYVd4a2NtVnVPbmt1WkdWeWFYWmhkR2x2Ym54OGJ5NXFjM2dvSW1WdElpeDdZMmhwYkdSeVpXNDZJazV2ZENCemRHRjBaV1FnNG9DVUlIUnlaV0YwSUhS'
    || 'b2FYTWdkR0Z5WjJWMElHRnpJSFZ1Wlhod2JHRnBibVZrTGlKOUtYMHBYWDBwTEhrdVltRnphWE0vYnk1cWMzaHpLQ0prYVhZaUxIdGphR2xzWkhKbGJqcGJi'
    || 'eTVxYzNnb0ltUjBJaXg3WTJocGJHUnlaVzQ2SWtKaGMybHpJRzltSUhSb1pTQmhZM1IxWVd3aWZTa3NieTVxYzNnb0ltUmtJaXg3WTJocGJHUnlaVzQ2Ynk1'
    || 'cWMzZ29JbU52WkdVaUxIdGphR2xzWkhKbGJqcDVMbUpoYzJsemZTbDlLVjE5S1RwdWRXeHNYWDBwWFgwcFhYMHNlUzVqYjJSbEtTa3NSVDl2TG1wemVDZ2lj'
    || 'Q0lzZTJOc1lYTnpUbUZ0WlRvaWNHOWpYMTl1YjNSbElpeGphR2xzWkhKbGJqcEZmU2s2Ym5Wc2JGMTlLWDBwZlNsZGZTbDlablZ1WTNScGIyNGdWbU1vZFN4'
    || 'a0tYdGpiMjV6ZENCalBYVXVZM1Z6ZEc5dGFYcGhkR2x2Ymo4L2UzMHNlRDBvWXk1d1lXNWxiSE0vUDF0ZEtTNXRZWEFvVkQwK0tIdHBaRHBVTG1sa0xHeGhZ'
    || 'bVZzT2xRdWRHbDBiR1VzYVdOdmJqb2lkR0ZpYkdVaUxIQmhibVZzY3pwYlZDNXBaRjBzY21WdVpHVnlPaWdwUFQ1dkxtcHplQ2hrY3l4N2NHRjViRzloWkRw'
    || 'MUxITndaV002VkgwcGZTa3BMRVU5WXk1elpXTjBhVzl1WDI5eVpHVnlQejliWFR0eVpYUjFjbTViTGk0dVpDd3VMaTU0WFM1dFlYQW9WRDArZTNaaGNpQjVP'
    || 'M0psZEhWeWJuc3VMaTVVTEd4aFltVnNPbFF1YVdROVBUMGljRzlqWDNOMVkyTmxjM01pUDFRdWJHRmlaV3c2S0NoNVBXTXVjMlZqZEdsdmJsOXNZV0psYkhN'
    || 'cFBUMXVkV3hzUDNadmFXUWdNRHA1VzFRdWFXUmRLVDgvVkM1c1lXSmxiSDE5S1M1emIzSjBLQ2hVTEhrcFBUNTdZMjl1YzNRZ1RqMUZMbWx1WkdWNFQyWW9W'
    || 'QzVwWkNrc2FqMUZMbWx1WkdWNFQyWW9lUzVwWkNrN2NtVjBkWEp1S0U0OE1EOUZMbXhsYm1kMGFEcE9LUzBvYWp3d1AwVXViR1Z1WjNSb09tb3BmU2w5Wm5W'
    || 'dVkzUnBiMjRnWkhNb2UzQmhlV3h2WVdRNmRTeHpjR1ZqT21SOUtYdDJZWElnUnp0amIyNXpkQ0JqUFhVdWNHRnVaV3h6VzJRdWFXUmRMSGc5WXlZbUlYWnVL'
    || 'R01wUDJNdWNtOTNjenBiWFN4RlBYZ3ViV0Z3S0V3OVBrbDBLRXd1VmtGTVZVVXBLU3hVUFVVdVpYWmxjbmtvVEQwK1RDRTlQVzUxYkd3cExIazlUV0YwYUM1'
    || 'dGFXNG9NQ3d1TGk1RkxtMWhjQ2hNUFQ1TVB6OHdLU2tzYWoxTllYUm9MbTFoZUNnd0xDNHVMa1V1YldGd0tFdzlQa3cvUHpBcEtTMTVmSHd4TzNKbGRIVnli'
    || 'aUJ2TG1wemVDZ2ljMlZqZEdsdmJpSXNlM04wZVd4bE9udG5jbWxrUTI5c2RXMXVPaUl4SUM4Z0xURWlMRzFwYmxkcFpIUm9PakI5TENKa1lYUmhMVzl1WlhO'
    || 'b2IzUWlPaUpqZFhOMGIyMHRjR0Z1Wld3aUxHTm9hV3hrY21WdU9tOHVhbk40S0VwbExIdHdZVzVsYkRwakxHTm9hV3hrY21WdU9tUXVhMmx1WkQwOVBTSjBZ'
    || 'V0pzWlNJL2J5NXFjM2dvUkhRc2UzSnZkM002ZUN4dFlYZzZaQzVzYVcxcGRDeGpiMnh6T2s5aWFtVmpkQzVyWlhsektIaGJNRjAvUDN0OUtTNXRZWEFvVEQw'
    || 'K0tIdHJaWGs2VEgwcEtYMHBPbFEvWkM1cmFXNWtQVDA5SW0xbGRISnBZeUkvZUM1c1pXNW5kR2doUFQweGZIeGpKaVloZG00b1l5a21KbU11ZEhKMWJtTmhk'
    || 'R1ZrUDI4dWFuTjRLQ0p3SWl4N2NtOXNaVG9pWVd4bGNuUWlMR05vYVd4a2NtVnVPaUpCSUcxbGRISnBZeUIyYVdWM0lHMTFjM1FnY21WMGRYSnVJR1Y0WVdO'
    || 'MGJIa2diMjVsSUhKdmR5NGlmU2s2Ynk1cWMzaHpLQ0prYkNJc2UyTm9hV3hrY21WdU9sdHZMbXB6ZUNnaVpIUWlMSHRqYUdsc1pISmxianBUZEhKcGJtY29L'
    || 'Q2hIUFhoYk1GMHBQVDF1ZFd4c1AzWnZhV1FnTURwSExreEJRa1ZNS1Q4L0lpSXBmU2tzYnk1cWMzZ29JbVJrSWl4N2MzUjViR1U2ZTJadmJuUlRhWHBsT2pN'
    || 'MkxHMWhjbWRwYmpvaU9IQjRJREFpTEdadmJuUldZWEpwWVc1MFRuVnRaWEpwWXpvaWRHRmlkV3hoY2kxdWRXMXpJbjBzWTJocGJHUnlaVzQ2YTJVb1JWc3dY'
    || 'U2w5S1YxOUtUcHZMbXB6ZUNnaVpHbDJJaXg3YzNSNWJHVTZlMlJwYzNCc1lYazZJbWR5YVdRaUxHZGhjRG94TW4wc1kyaHBiR1J5Wlc0NmVDNXRZWEFvS0V3'
    || 'c1JpazlQbnRqYjI1emRDQldQVVZiUmwwL1B6QXNkV1U5TFhrdmFpb3hNREFzU2owb1ZpMTVLUzlxS2pFd01EdHlaWFIxY200Z2J5NXFjM2h6S0NKa2FYWWlM'
    || 'SHR6ZEhsc1pUcDdaR2x6Y0d4aGVUb2laM0pwWkNJc1ozSnBaRlJsYlhCc1lYUmxRMjlzZFcxdWN6b2liV2x1YldGNEtERXdNSEI0TENBeFpuSXBJRzFwYm0x'
    || 'aGVDZzRNSEI0TENBelpuSXBJRzFwYm0xaGVDZzJNSEI0TENBeFpuSXBJaXhuWVhBNk1USXNZV3hwWjI1SmRHVnRjem9pWTJWdWRHVnlJbjBzWTJocGJHUnla'
    || 'VzQ2VzI4dWFuTjRLQ0p6Y0dGdUlpeDdjM1I1YkdVNmUyOTJaWEptYkc5M1YzSmhjRG9pWVc1NWQyaGxjbVVpZlN4amFHbHNaSEpsYmpwVGRISnBibWNvVEM1'
    || 'TVFVSkZURDgvSWlJcGZTa3NieTVxYzNoektDSmthWFlpTEh0eWIyeGxPaUpwYldjaUxDSmhjbWxoTFd4aFltVnNJanBnSkh0VGRISnBibWNvVEM1TVFVSkZU'
    || 'Q2w5T2lBa2UydGxLRllwZldBc2MzUjViR1U2ZTJobGFXZG9kRG95TWl4d2IzTnBkR2x2YmpvaWNtVnNZWFJwZG1VaUxHSmhZMnRuY205MWJtUTZJblpoY2ln'
    || 'dExXeHBibVVzSUNObE5HVTNaV01wSW4wc1kyaHBiR1J5Wlc0NlcyOHVhbk40S0NKa2FYWWlMSHR6ZEhsc1pUcDdjRzl6YVhScGIyNDZJbUZpYzI5c2RYUmxJ'
    || 'aXhzWldaME9tQWtlMDFoZEdndWJXbHVLSFZsTEVvcGZTVmdMSGRwWkhSb09tQWtlMDFoZEdndVlXSnpLRW90ZFdVcGZTVmdMR2hsYVdkb2REb2lNVEF3SlNJ'
    || 'c1ltRmphMmR5YjNWdVpEb2lkbUZ5S0MwdFlXTmpaVzUwTENBak1UWTNPV0UxS1NKOWZTa3NieTVxYzNnb0ltUnBkaUlzZTNOMGVXeGxPbnR3YjNOcGRHbHZi'
    || 'am9pWVdKemIyeDFkR1VpTEd4bFpuUTZZQ1I3ZFdWOUpXQXNkMmxrZEdnNk1TeG9aV2xuYUhRNklqRXdNQ1VpTEdKaFkydG5jbTkxYm1RNkluWmhjaWd0TFds'
    || 'dWF5d2dJekUzTWpFeVlpa2lmWDBwWFgwcExHOHVhbk40S0NKemNHRnVJaXg3YzNSNWJHVTZlM1JsZUhSQmJHbG5iam9pY21sbmFIUWlMR1p2Ym5SV1lYSnBZ'
    || 'VzUwVG5WdFpYSnBZem9pZEdGaWRXeGhjaTF1ZFcxekluMHNZMmhwYkdSeVpXNDZhMlVvVmlsOUtWMTlMRVlwZlNsOUtUcHZMbXB6ZUNnaWNDSXNlM0p2YkdV'
    || 'NkltRnNaWEowSWl4amFHbHNaSEpsYmpvaVZrRk1WVVVnYlhWemRDQmlaU0J1ZFcxbGNtbGpMaUJPYnlCamFHRnlkQ0IzWVhNZ1pISmhkMjR1SW4wcGZTbDlL'
    || 'WDFtZFc1amRHbHZiaUJYWXloMUtYdDJZWElnZUN4Rk8yTnZibk4wSUdROUtIZzlkVDA5Ym5Wc2JEOTJiMmxrSURBNmRTNWlkV2xzWkdWeVgzVnliQ2s5UFc1'
    || 'MWJHdy9kbTlwWkNBd09uZ3ViV0YwWTJnb0wxNW9kSFJ3Y3pwY0wxd3ZZWEJ3WEM1emJtOTNabXhoYTJWY0xtTnZiVnd2S0Z0aExYcEJMVm93TFRsZkxWMHJL'
    || 'Vnd2S0Z0aExYcEJMVm93TFRsZkxWMHJLVnd2STF3dmMzUnlaV0Z0YkdsMExXRndjSE5jTDF0QkxWb3dMVGxmWFN0Y0xsdEJMVm93TFRsZlhTdGNMbHRCTFZv'
    || 'd0xUbGZYU3NrTHlrc1l6MG9SVDExUFQxdWRXeHNQM1p2YVdRZ01EcDFMblpwWlhkbGNsOTFjbXdwUFQxdWRXeHNQM1p2YVdRZ01EcEZMbTFoZEdOb0tDOWVh'
    || 'SFIwY0hNNlhDOWNMMkZ3Y0Z3dWMyNXZkMlpzWVd0bFhDNWpiMjFjTDNOMGNtVmhiV3hwZEZ3dktGdGhMWHBCTFZvd0xUbGZMVjByS1Z3dktGdGhMWHBCTFZv'
    || 'd0xUbGZMVjByS1Z3dkkxd3ZZWEJ3YzF3dlcyRXRla0V0V2pBdE9WOHRYU3NrTHlrN2NtVjBkWEp1SVdSOGZDRmpmSHhrV3pGZElUMDlZMXN4WFh4OFpGc3lY'
    || 'U0U5UFdOYk1sMC9iblZzYkRwYmUyeGhZbVZzT2lKQmNIQWdiMjVzZVNJc2FISmxaanAxTG5acFpYZGxjbDkxY214OUxIdHNZV0psYkRvaVUyaHZkeUJUYm05'
    || 'M2MybG5hSFFpTEdoeVpXWTZkUzVpZFdsc1pHVnlYM1Z5YkgxZGZXWjFibU4wYVc5dUlFSmpLSHR1WVhacFoyRjBhVzl1T25WOUtYdGpiMjV6ZENCa1BVSnNM'
    || 'blZ6WlZKbFppaHVkV3hzS1N4alBWZGpLSFVwTzNKbGRIVnliaUJDYkM1MWMyVkZabVpsWTNRb0tDazlQbnRqYjI1emRDQjRQVVU5UG50a0xtTjFjbkpsYm5R'
    || 'bUppRmtMbU4xY25KbGJuUXVZMjl1ZEdGcGJuTW9SUzUwWVhKblpYUXBKaVlvWkM1amRYSnlaVzUwTG05d1pXNDlJVEVwZlR0eVpYUjFjbTRnWkc5amRXMWxi'
    || 'blF1WVdSa1JYWmxiblJNYVhOMFpXNWxjaWdpY0c5cGJuUmxjbVJ2ZDI0aUxIZ3BMQ2dwUFQ1a2IyTjFiV1Z1ZEM1eVpXMXZkbVZGZG1WdWRFeHBjM1JsYm1W'
    || 'eUtDSndiMmx1ZEdWeVpHOTNiaUlzZUNsOUxGdGRLU3hqUDI4dWFuTjRjeWdpWkdWMFlXbHNjeUlzZTJOc1lYTnpUbUZ0WlRvaVlYQndMWFpwWlhjdGJXVnVk'
    || 'U0lzY21WbU9tUXNJbVJoZEdFdGIyNWxjMmh2ZENJNkluWnBaWGN0YldWdWRTSXNiMjVMWlhsRWIzZHVPbmc5UG50MllYSWdSU3hVTzNndWEyVjVQVDA5SWtW'
    || 'elkyRndaU0ltSmlnb1JUMWtMbU4xY25KbGJuUXBJVDF1ZFd4c0ppWkZMbTl3Wlc0cEppWW9lQzV3Y21WMlpXNTBSR1ZtWVhWc2RDZ3BMR1F1WTNWeWNtVnVk'
    || 'QzV2Y0dWdVBTRXhMQ2hVUFdRdVkzVnljbVZ1ZEM1eGRXVnllVk5sYkdWamRHOXlLQ0p6ZFcxdFlYSjVJaWtwUFQxdWRXeHNmSHhVTG1adlkzVnpLQ2twZlN4'
    || 'amFHbHNaSEpsYmpwYmJ5NXFjM2dvSW5OMWJXMWhjbmtpTEhzaVlYSnBZUzFzWVdKbGJDSTZJa0Z3Y0NCMmFXVjNJRzl3ZEdsdmJuTWlMSFJwZEd4bE9pSkJj'
    || 'SEFnZG1sbGR5QnZjSFJwYjI1eklpeGphR2xzWkhKbGJqcHZMbXB6ZUNnaWMzWm5JaXg3ZG1sbGQwSnZlRG9pTUNBd0lESTBJREkwSWl4M2FXUjBhRG9pTWpB'
    || 'aUxHaGxhV2RvZERvaU1qQWlMR1pwYkd3NkltNXZibVVpTEhOMGNtOXJaVG9pWTNWeWNtVnVkRU52Ykc5eUlpeHpkSEp2YTJWWGFXUjBhRG9pTVM0MklpeHpk'
    || 'SEp2YTJWTWFXNWxZMkZ3T2lKeWIzVnVaQ0lzYzNSeWIydGxUR2x1WldwdmFXNDZJbkp2ZFc1a0lpd2lZWEpwWVMxb2FXUmtaVzRpT2lKMGNuVmxJaXhqYUds'
    || 'c1pISmxianB2TG1wemVDZ2ljR0YwYUNJc2UyUTZJazA0SUROSU0zWTFiVEV6TFRWb05YWTFUVE1nTVRaMk5XZzFiVEV6TFRWMk5XZ3ROU0o5S1gwcGZTa3Ni'
    || 'eTVxYzNnb0ltUnBkaUlzZTJOc1lYTnpUbUZ0WlRvaVlYQndMWFpwWlhjdGIzQjBhVzl1Y3lJc1kyaHBiR1J5Wlc0Nll5NXRZWEFvZUQwK2J5NXFjM2dvSW1F'
    || 'aUxIdG9jbVZtT25ndWFISmxaaXgwWVhKblpYUTZJbDlpYkdGdWF5SXNjbVZzT2lKdWIyOXdaVzVsY2lCdWIzSmxabVZ5Y21WeUlpd2lZWEpwWVMxc1lXSmxi'
    || 'Q0k2WUNSN2VDNXNZV0psYkgwZ0tHOXdaVzV6SUdsdUlHRWdibVYzSUhSaFlpbGdMRzl1UTJ4cFkyczZLQ2s5UG50a0xtTjFjbkpsYm5RbUppaGtMbU4xY25K'
    || 'bGJuUXViM0JsYmowaE1TbDlMR05vYVd4a2NtVnVPbmd1YkdGaVpXeDlMSGd1YkdGaVpXd3BLWDBwWFgwcE9tNTFiR3g5WTI5dWMzUWdTbXc5SW5CdlkxOXpk'
    || 'V05qWlhOeklqdG1kVzVqZEdsdmJpQlJZeWg3Y0dGNWJHOWhaRHAxTEhObFkzUnBiMjV6T21Rc2MzVmlkR2wwYkdVNll5eGphR2xzWkhKbGJqcDRmU2w3ZG1G'
    || 'eUlHZGxMSHBsTEhkbExFNWxMRkJsTzJOdmJuTjBJRVU5ZFM1amIyNTBaWGgwUHo5N2ZTeDVQVk4wY21sdVp5aEZMazFQUkVVL1B5SWlLUzUwYjFWd2NHVnlR'
    || 'MkZ6WlNncFBUMDlJbE5CVFZCTVJTSXNUajBvS0dkbFBYVXVZM1Z6ZEc5dGFYcGhkR2x2YmlrOVBXNTFiR3cvZG05cFpDQXdPbWRsTG5ScGRHeGxLVDgvVTNS'
    || 'eWFXNW5LRVV1VTA5TVZWUkpUMDQvUHlKVGJtOTNabXhoYTJVZ2MyOXNkWFJwYjI0aUtTeHFQVk5qS0hVcExFYzliSE1vZFNrc1REMTdhV1E2U213c2JHRmla'
    || 'V3c2SWxCUFF5QnpkV05qWlhOeklpeGtaWE5qT2lKVVlYSm5aWFJ6TENCaGJtUWdkMmhsZEdobGNpQjBhR1Y1SUdGeVpTQnRaWFFpTEdsamIyNDZhaTUyWlhK'
    || 'a2FXTjBQVDA5SWs1UFZGOU5SVlFpUHlKM1lYSnVJam9pWTJobFkyc2lMR0poWkdkbE9tb3VkVzVoZG1GcGJHRmliR1Y4ZkdvdWRtVnlaR2xqZEQwOVBTSk9U'
    || 'MVJmVWxWT0lqOTJiMmxrSURBNllDUjdhaTV0WlhSOUx5UjdhaTV6WTI5eVpXUjlZQ3hpWVdSblpWUnZibVU2YWk1MlpYSmthV04wUFQwOUlrNVBWRjlOUlZR'
    || 'aVB5SmlZV1FpT21vdWRtVnlaR2xqZEQwOVBTSk5SVlFpUHlKbmIyOWtJanBxTG5abGNtUnBZM1E5UFQwaVRVVlVYMWRKVkVoZlVFVk9SRWxPUnlJL0luZGhj'
    || 'bTRpT2lKcFpHeGxJaXh3WVc1bGJITTZXeUp3YjJOZmMyTnZjbVZqWVhKa0lpd2ljRzlqWDNabGNtUnBZM1FpWFN4eVpXNWtaWEk2S0NrOVBtOHVhbk40S0dO'
    || 'ekxIdGpjbWwwWlhKcFlUcEhMSFk2YWl4d1lXNWxiRHAxTG5CaGJtVnNjeTV3YjJOZmMyTnZjbVZqWVhKa0xIWmxjbVJwWTNSUVlXNWxiRHAxTG5CaGJtVnNj'
    || 'eTV3YjJOZmRtVnlaR2xqZEgwcGZTeEdQV1FtSm1RdWJHVnVaM1JvUDFaaktIVXNaQzV6YjIxbEtHUmxQVDVrWlM1cFpEMDlQVXBzS1Q5a09sc3VMaTVrTEV4'
    || 'ZEtUcDJiMmxrSURBc1ZqMG9lbVU5ZFM1amRYTjBiMjFwZW1GMGFXOXVLVDA5Ym5Wc2JEOTJiMmxrSURBNmVtVXVaR1ZtWVhWc2RGOXpaV04wYVc5dUxIVmxQ'
    || 'U2dvZDJVOVJqMDliblZzYkQ5MmIybGtJREE2Umk1bWFXNWtLR1JsUFQ1a1pTNXBaRDA5UFZZcEtUMDliblZzYkQ5MmIybGtJREE2ZDJVdWFXUXBQejhvS0U1'
    || 'bFBVWTlQVzUxYkd3L2RtOXBaQ0F3T2taYk1GMHBQVDF1ZFd4c1AzWnZhV1FnTURwT1pTNXBaQ2svUHlJaUxGdEtMR0pkUFUxMExuVnpaVk4wWVhSbEtIVmxL'
    || 'U3haUFNoR1BUMXVkV3hzUDNadmFXUWdNRHBHTG1acGJtUW9aR1U5UG1SbExtbGtQVDA5U2lrcFB6OG9SajA5Ym5Wc2JEOTJiMmxrSURBNlJsc3dYU2s3YVdZ'
    || 'b2RTNW1ZWFJoYkNseVpYUjFjbTRnYnk1cWMzZ29JbVJwZGlJc2UyTnNZWE56VG1GdFpUb2lZWEJ3SUdGd2NDMHRibTl1WVhZaUxHTm9hV3hrY21WdU9tOHVh'
    || 'bk40Y3lnaVpHbDJJaXg3WTJ4aGMzTk9ZVzFsT2lKbVlYUmhiQ0lzSW1SaGRHRXRiMjVsYzJodmRDSTZJbVpoZEdGc0lpeGphR2xzWkhKbGJqcGJieTVxYzNn'
    || 'b0ltZ3hJaXg3WTJocGJHUnlaVzQ2SWxSb2FYTWdZWEJ3SUdOaGJtNXZkQ0J6YUc5M0lHRnVlWFJvYVc1bkluMHBMRzh1YW5ONEtDSmpiMlJsSWl4N1kyaHBi'
    || 'R1J5Wlc0NmRTNW1ZWFJoYkgwcFhYMHBmU2s3WTI5dWMzUWdZbVU5SVNGR0ppWkdMbXhsYm1kMGFENHdMRUpsUFc4dWFuTjRjeWh2TGtaeVlXZHRaVzUwTEh0'
    || 'amFHbHNaSEpsYmpwYmVUOXZMbXB6ZUNnaVpHbDJJaXg3WTJ4aGMzTk9ZVzFsT2lKaVlXNXVaWElnWW1GdWJtVnlMUzF6WVcxd2JHVWlMQ0prWVhSaExXOXVa'
    || 'WE5vYjNRaU9pSnpZVzF3YkdVdFltRnVibVZ5SWl4amFHbHNaSEpsYmpvaVUwRk5VRXhGSUVSQlZFRWc0b0NVSUhSb1pYTmxJRzUxYldKbGNuTWdZMjl0WlNC'
    || 'bWNtOXRJSE5sWldSbFpDQm1hWGgwZFhKbGN5d2dibTkwSUdaeWIyMGdlVzkxY2lCaFkyTnZkVzUwSW4wcE9tNTFiR3dzYnk1cWMzaHpLQ0pvWldGa1pYSWlM'
    || 'SHRqYkdGemMwNWhiV1U2SW1Gd2NGOWZhR1ZoWkNJc1kyaHBiR1J5Wlc0NlcyOHVhbk40Y3lnaVpHbDJJaXg3WTJocGJHUnlaVzQ2VzI4dWFuTjRLQ0pvTVNJ'
    || 'c2UyTm9hV3hrY21WdU9say9XUzVzWVdKbGJEcE9mU2tzYnk1cWMzaHpLQ0p3SWl4N1kyeGhjM05PWVcxbE9pSmhjSEJmWDNOMVlpSXNZMmhwYkdSeVpXNDZX'
    || 'eUppZFdsc2RDQnBiaUFpTEc4dWFuTjRLQ0pqYjJSbElpeDdZMmhwYkdSeVpXNDZVM1J5YVc1bktFVXVRbFZKVEZSZlNVNC9QeUxpZ0pRaUtYMHBMRVV1VjBs'
    || 'T1JFOVhYMFJCV1ZNL2J5NXFjM2h6S0c4dVJuSmhaMjFsYm5Rc2UyTm9hV3hrY21WdU9sc2lJTUszSUNJc1UzUnlhVzVuS0VVdVYwbE9SRTlYWDBSQldWTXBM'
    || 'Q0l0WkdGNUlIZHBibVJ2ZHlKZGZTazZiblZzYkN4RkxrSlZTVXhVWDBGVVAyOHVhbk40Y3lodkxrWnlZV2R0Wlc1MExIdGphR2xzWkhKbGJqcGJJaURDdHlB'
    || 'aUxGTjBjbWx1WnloRkxrSlZTVXhVWDBGVUtTNXpiR2xqWlNnd0xERTVLUzV5WlhCc1lXTmxLQ0pVSWl3aUlDSXBYWDBwT201MWJHeGRmU2xkZlNrc2J5NXFj'
    || 'M2h6S0NKa2FYWWlMSHRqYkdGemMwNWhiV1U2SW1Gd2NGOWZhR1ZoWkhKcFoyaDBJaXhqYUdsc1pISmxianBiYnk1cWMzZ29TR01zZTNZNmFpeHZiazl3Wlc0'
    || 'NlltVS9LQ2s5UG1Jb1Ntd3BPblp2YVdRZ01IMHBMRzh1YW5ONEtGbGpMSHR3WVhsc2IyRmtPblY5S1N4dkxtcHplQ2hDWXl4N2JtRjJhV2RoZEdsdmJqcDFM'
    || 'bTVoZG1sbllYUnBiMjU5S1YxOUtWMTlLU3h2TG1wemVDaFlZeXg3Y0dGNWJHOWhaRHAxZlNrc2RTNWpkWE4wYjIxcGVtRjBhVzl1WDJWeWNtOXlQMjh1YW5O'
    || 'NEtDSndJaXg3Y205c1pUb2lZV3hsY25RaUxHTnNZWE56VG1GdFpUb2ljR0Z1Wld3dFpYSnliM0lpTEdOb2FXeGtjbVZ1T25VdVkzVnpkRzl0YVhwaGRHbHZi'
    || 'bDlsY25KdmNuMHBPbTUxYkd4ZGZTazdhV1lvSVdKbEtYSmxkSFZ5YmlCdkxtcHplQ2dpWkdsMklpeDdZMnhoYzNOT1lXMWxPaUpoY0hBZ1lYQndMUzF1YjI1'
    || 'aGRpSXNZMmhwYkdSeVpXNDZieTVxYzNoektDSmthWFlpTEh0amJHRnpjMDVoYldVNkltMWhhVzRpTEdOb2FXeGtjbVZ1T2x0Q1pTeHZMbXB6ZUhNb0ltMWhh'
    || 'VzRpTEh0amJHRnpjMDVoYldVNkltZHlhV1FpTENKa1lYUmhMVzl1WlhOb2IzUWlPaUp6WldOMGFXOXVJaXdpWkdGMFlTMXpaV04wYVc5dUlqb2ljMmx1WjJ4'
    || 'bElpeGphR2xzWkhKbGJqcGJlQ3dvS0NoUVpUMTFMbU4xYzNSdmJXbDZZWFJwYjI0cFBUMXVkV3hzUDNadmFXUWdNRHBRWlM1d1lXNWxiSE1wUHo5YlhTa3Vi'
    || 'V0Z3S0dSbFBUNXZMbXB6ZUhNb1RYUXVSbkpoWjIxbGJuUXNlMk5vYVd4a2NtVnVPbHR2TG1wemVDZ2lhRElpTEh0emRIbHNaVHA3WjNKcFpFTnZiSFZ0Ympv'
    || 'aU1TQXZJQzB4SW4wc1kyaHBiR1J5Wlc0NlpHVXVkR2wwYkdWOUtTeHZMbXB6ZUNoa2N5eDdjR0Y1Ykc5aFpEcDFMSE53WldNNlpHVjlLVjE5TEdSbExtbGtL'
    || 'U2tzYnk1cWMzZ29ZM01zZTJOeWFYUmxjbWxoT2tjc2RqcHFMSEJoYm1Wc09uVXVjR0Z1Wld4ekxuQnZZMTl6WTI5eVpXTmhjbVFzZG1WeVpHbGpkRkJoYm1W'
    || 'c09uVXVjR0Z1Wld4ekxuQnZZMTkyWlhKa2FXTjBmU2xkZlNrc2J5NXFjM2dvUzJNc2UzMHBYWDBwZlNrN1kyOXVjM1FnVVdVOVJpNXRZWEFvWkdVOVBpaDdM'
    || 'aTR1WkdVc2MzUmhkSFZ6T21SbExuTjBZWFIxY3o4L1IyTW9kU3hrWlNsOUtTazdjbVYwZFhKdUlHOHVhbk40Y3lnaVpHbDJJaXg3WTJ4aGMzTk9ZVzFsT2lK'
    || 'aGNIQWlMR05vYVd4a2NtVnVPbHR2TG1wemVDaFNZeXg3YzI5c2RYUnBiMjQ2VGl4emRXSjBhWFJzWlRwakxITmxZM1JwYjI1ek9sRmxMR0ZqZEdsMlpUcEtM'
    || 'Rzl1VUdsamF6cGlMR1p2YjNRNmJ5NXFjM2dvYnk1R2NtRm5iV1Z1ZEN4N1kyaHBiR1J5Wlc0NklrUmhkR0VnWTI5dFpYTWdabkp2YlNCMmFXVjNjeUJwYmlC'
    || 'MGFHbHpJSE5qYUdWdFlTNGdVbVZoWkhNZ2JXRjVJR0psSUhKbGRYTmxaQ0JtYjNJZ016QWdjMlZqYjI1a2N5QjNhWFJvYVc0Z2VXOTFjaUJ6WlhOemFXOXVP'
    || 'eUJTWldaeVpYTm9JR1JoZEdFZ1ptVjBZMmhsY3lCaFoyRnBiaTRpZlNsOUtTeHZMbXB6ZUhNb0ltUnBkaUlzZTJOc1lYTnpUbUZ0WlRvaWJXRnBiaUlzWTJo'
    || 'cGJHUnlaVzQ2VzBKbExHOHVhbk40S0NKdFlXbHVJaXg3WTJ4aGMzTk9ZVzFsT2lKbmNtbGtJSEoySWl3aVpHRjBZUzF2Ym1WemFHOTBJam9pYzJWamRHbHZi'
    || 'aUlzSW1SaGRHRXRjMlZqZEdsdmJpSTZTaXhqYUdsc1pISmxianBaUDFrdWNtVnVaR1Z5S0NrNmJuVnNiSDBzU2lsZGZTbGRmU2w5Wm5WdVkzUnBiMjRnUjJN'
    || 'b2RTeGtLWHRqYjI1emRDQmpQV1F1Y0dGdVpXeHpQejliWFR0cFppaGpMbk52YldVb2VEMCtkbTRvZFM1d1lXNWxiSE5iZUYwcEppWWhaMjRvZFM1d1lXNWxi'
    || 'SE5iZUYwcEtTbHlaWFIxY200aVltRmtJanRwWmloakxuTnZiV1VvZUQwK1oyNG9kUzV3WVc1bGJITmJlRjBwS1NseVpYUjFjbTRpYVc1bWJ5SjlablZ1WTNS'
    || 'cGIyNGdTMk1vS1h0eVpYUjFjbTRnYnk1cWMzZ29JbVp2YjNSbGNpSXNlMk5zWVhOelRtRnRaVG9pWVhCd1gxOW1iMjkwSWl4emRIbHNaVHA3YldGeVoybHVW'
    || 'Rzl3T2pJd0xHWnZiblJUYVhwbE9qRXhMalVzWTI5c2IzSTZJblpoY2lndExXUnBiU2tpZlN4amFHbHNaSEpsYmpvaVJHRjBZU0JqYjIxbGN5Qm1jbTl0SUha'
    || 'cFpYZHpJR2x1SUhSb2FYTWdjMk5vWlcxaExpQlNaV0ZrY3lCdFlYa2dZbVVnY21WMWMyVmtJR1p2Y2lBek1DQnpaV052Ym1SeklIZHBkR2hwYmlCNWIzVnlJ'
    || 'SE5sYzNOcGIyNDdJRkpsWm5KbGMyZ2daR0YwWVNCbVpYUmphR1Z6SUdGbllXbHVMaUo5S1gxbWRXNWpkR2x2YmlCWll5aDdjR0Y1Ykc5aFpEcDFmU2w3ZG1G'
    || 'eUlIazdZMjl1YzNRZ1pEMU9ZeWgxTG1OdmJuUmxlSFFwTEZ0akxIaGRQVTEwTG5WelpWTjBZWFJsS0c1MWJHd3BMRVU5S0NoNVBXUXVabWx1WkNoT1BUNU9M'
    || 'bk4wWVhSbFBUMDlJbU4xY25KbGJuUWlLU2s5UFc1MWJHdy9kbTlwWkNBd09ua3VhV1FwUHo5dWRXeHNMRlE5WXo5a0xtWnBibVFvVGowK1RpNXBaRDA5UFdN'
    || 'cE9tNTFiR3c3Y21WMGRYSnVJRzh1YW5ONGN5Z2laR2wySWl4N1kyeGhjM05PWVcxbE9pSndhR0Z6WlNJc1kyaHBiR1J5Wlc0NlcyOHVhbk40S0NKa2FYWWlM'
    || 'SHRqYkdGemMwNWhiV1U2SW5Cb1lYTmxYMTl5WVdsc0lpeHliMnhsT2lKbmNtOTFjQ0lzSW1GeWFXRXRiR0ZpWld3aU9pSkVaWEJzYjNsdFpXNTBJSEJvWVhO'
    || 'bElpeGphR2xzWkhKbGJqcGtMbTFoY0NoT1BUNXZMbXB6ZUhNb0ltSjFkSFJ2YmlJc2UzUjVjR1U2SW1KMWRIUnZiaUlzSW1SaGRHRXRjR2hoYzJVaU9rNHVh'
    || 'V1FzWTJ4aGMzTk9ZVzFsT2lKd2FHRnpaVjlmWW5SdUlIQm9ZWE5sWDE5aWRHNHRMU0lyVGk1emRHRjBaU3NvWXowOVBVNHVhV1EvSWlCcGN5MXZjR1Z1SWpv'
    || 'aUlpa3NJbUZ5YVdFdFkzVnljbVZ1ZENJNlRpNXpkR0YwWlQwOVBTSmpkWEp5Wlc1MElqOGljM1JsY0NJNmRtOXBaQ0F3TENKaGNtbGhMV1Y0Y0dGdVpHVmtJ'
    || 'anBqUFQwOVRpNXBaQ3h2YmtOc2FXTnJPaWdwUFQ1NEtHTTlQVDFPTG1sa1AyNTFiR3c2VGk1cFpDa3NZMmhwYkdSeVpXNDZXMjh1YW5ONEtDSnpjR0Z1SWl4'
    || 'N1kyeGhjM05PWVcxbE9pSndhR0Z6WlY5ZmJHRmlaV3dpTEdOb2FXeGtjbVZ1T2s0dWJHRmlaV3g5S1N4dkxtcHplQ2dpYzNCaGJpSXNlMk5zWVhOelRtRnRa'
    || 'VG9pY0doaGMyVmZYMlpwWjNWeVpTSXNZMmhwYkdSeVpXNDZUaTVtYVdkMWNtVjlLU3hPTG0xdmJtVjVQMjh1YW5ONEtDSnpjR0Z1SWl4N1kyeGhjM05PWVcx'
    || 'bE9pSndhR0Z6WlY5ZmJXOXVaWGtpTEdOb2FXeGtjbVZ1T2s0dWJXOXVaWGw5S1RwdWRXeHNYWDBzVGk1cFpDa3BmU2tzVkQ5dkxtcHplSE1vSW1ScGRpSXNl'
    || 'Mk5zWVhOelRtRnRaVG9pY0doaGMyVmZYMlJsZEdGcGJDSXNZMmhwYkdSeVpXNDZXMjh1YW5ONEtDSndJaXg3WTJ4aGMzTk9ZVzFsT2lKd2FHRnpaVjlmWW14'
    || 'MWNtSWlMR05vYVd4a2NtVnVPbFF1WW14MWNtSjlLU3h2TG1wemVITW9JbkFpTEh0amJHRnpjMDVoYldVNkluQm9ZWE5sWDE5aVlYTnBjeUlzWTJocGJHUnla'
    || 'VzQ2VzI4dWFuTjRLQ0p6ZEhKdmJtY2lMSHRqYUdsc1pISmxianBVTG1acFozVnlaWDBwTEZRdWJXOXVaWGsvYnk1cWMzaHpLRzh1Um5KaFoyMWxiblFzZTJO'
    || 'b2FXeGtjbVZ1T2xzaUlDZ2lMRlF1Ylc5dVpYa3NJaWtpWFgwcE9tNTFiR3dzSWlEaWdKUWdJaXhVTG1KaGMybHpYWDBwTEZRdWFXUTlQVDFGUDI4dWFuTjRL'
    || 'Q0p3SWl4N1kyeGhjM05PWVcxbE9pSndhR0Z6WlY5ZmQyaGxjbVVpTEdOb2FXeGtjbVZ1T2lKVWFHbHpJR0oxYVd4a0lHbHpJR2x1SUhSb2FYTWdjR2hoYzJV'
    || 'dUluMHBPbTh1YW5ONGN5Z2ljQ0lzZTJOc1lYTnpUbUZ0WlRvaWNHaGhjMlZmWDJodmR5SXNZMmhwYkdSeVpXNDZXeUpVYnlCdGIzWmxJR2hsY21Vc0lITmxk'
    || 'Q0IwYUdseklHbHVJSFJvWlNCelkzSnBjSFFnWVc1a0lISjFiaUJwZENCaFoyRnBiam9pTENJZ0lpeHZMbXB6ZUNnaVkyOWtaU0lzZTJOb2FXeGtjbVZ1T2xR'
    || 'dWMyVjBkR2x1WjMwcFhYMHBYWDBwT201MWJHeGRmU2w5Wm5WdVkzUnBiMjRnV0dNb2UzQmhlV3h2WVdRNmRYMHBlMk52Ym5OMElHUTlUMkpxWldOMExtdGxl'
    || 'WE1vZFM1d1lXNWxiSE1wTG1acGJIUmxjaWhGUFQ1RklUMDlJbU52Ym5SbGVIUWlLU3hqUFdRdVptbHNkR1Z5S0VVOVBtZHVLSFV1Y0dGdVpXeHpXMFZkS1Nr'
    || 'c2VEMWtMbVpwYkhSbGNpaEZQVDUyYmloMUxuQmhibVZzYzF0RlhTa21KaUZuYmloMUxuQmhibVZzYzF0RlhTa3BPM0psZEhWeWJpRmpMbXhsYm1kMGFDWW1J'
    || 'WGd1YkdWdVozUm9QMjUxYkd3NmJ5NXFjM2h6S0c4dVJuSmhaMjFsYm5Rc2UyTm9hV3hrY21WdU9sdDRMbXhsYm1kMGFEOXZMbXB6ZUhNb0ltUnBkaUlzZTJO'
    || 'c1lYTnpUbUZ0WlRvaVltRnVibVZ5SUdKaGJtNWxjaTB0Wm1GcGJDSXNZMmhwYkdSeVpXNDZXM2d1YkdWdVozUm9MQ0lnYjJZZ0lpeGtMbXhsYm1kMGFDd2lJ'
    || 'SEJoYm1Wc2N5QmthV1FnYm05MElHeHZZV1FnS0NJc2VDNXFiMmx1S0NJc0lDSXBMQ0lwTGlCVWFHVWdiblZ0WW1WeWN5QmlaV3h2ZHlCaGNtVWdhVzVqYjIx'
    || 'd2JHVjBaUzRpWFgwcE9tNTFiR3dzWXk1c1pXNW5kR2cvYnk1cWMzaHpLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbUpoYm01bGNpQmlZVzV1WlhJdExXbHVa'
    || 'bThpTEdOb2FXeGtjbVZ1T2x0akxteGxibWQwYUN3aUlHOW1JQ0lzWkM1c1pXNW5kR2dzSWlCelpXTjBhVzl1Y3lCM1pYSmxJRzV2ZENCaWRXbHNkQ0JpZVNC'
    || 'MGFHbHpJSEoxYmlBb0lpeGpMbXB2YVc0b0lpd2dJaWtzSWlrdUlGUm9ZWFFnYVhNZ1pYaHdaV04wWldRZ2IyNGdZU0JrYVhOamIzWmxjbmt0YjI1c2VTQnlk'
    || 'VzRnNG9DVUlHVmhZMmdnWTJGeVpDQnpZWGx6SUhkb2FXTm9JSE5sZEhScGJtY2dabWxzYkhNZ2FYUWdhVzR1SWwxOUtUcHVkV3hzWFgwcGZXWjFibU4wYVc5'
    || 'dUlGcGpLSFVwZTJOdmJuTjBJR1E5Wkc5amRXMWxiblF1WjJWMFJXeGxiV1Z1ZEVKNVNXUW9Jbkp2YjNRaUtUdHBaaWdoWkNsN1kyOXVjMjlzWlM1bGNuSnZj'
    || 'aWdpYjI1bGMyaHZkQ0JWU1RvZ2JtOGdJM0p2YjNRZ1pXeGxiV1Z1ZENCMGJ5QnRiM1Z1ZENCcGJuUnZJaWs3Y21WMGRYSnVmV052Ym5OMElHTTllR01vS1R0'
    || 'Mll5NWpjbVZoZEdWU2IyOTBLR1FwTG5KbGJtUmxjaWh2TG1wemVDaHZMa1p5WVdkdFpXNTBMSHRqYUdsc1pISmxianAxS0dNcGZTa3BmV1oxYm1OMGFXOXVJ'
    || 'SFowS0hVcGUyTnZibk4wSUdROWRIbHdaVzltSUhVOVBTSnVkVzFpWlhJaVAzVTZUblZ0WW1WeUtIVXBPM0psZEhWeWJpQk9kVzFpWlhJdWFYTkdhVzVwZEdV'
    || 'b1pDay9aRG93ZldOdmJuTjBJR0pzUFc4dWFuTjRjeWh2TGtaeVlXZHRaVzUwTEh0amFHbHNaSEpsYmpwYklsTmxkQ0FpTEc4dWFuTjRLQ0pqYjJSbElpeDdZ'
    || 'MmhwYkdSeVpXNDZJa1JGVEVWSFgwOVNRMGhGVTFSU1FWUlBVbDlTVDB4RkluMHBMQ0lnZEc4Z2RHaGxJSEp2YkdVZ2VXOTFjaUJ2Y21Ob1pYTjBjbUYwYjNJ'
    || 'Z1lYVjBhR1Z1ZEdsallYUmxjeUJoY3lEaWdKUWdkR2hsSUVGemRISnZMQ0JCYVhKbWJHOTNMQ0JFWVdkemRHVnlJRzl5SUVOdmJuUnliMnd0VFNCelpYSjJh'
    || 'V05sSUhKdmJHVWc0b0NVSUhSb1pXNGdjblZ1SUhSb1pTQnpZM0pwY0hRZ1lXZGhhVzR1SUVKc1lXNXJJR2x6SUhKbGNHOXlkR2x1WnlCdmJteDVPaUIwYUdV'
    || 'Z2FXNTJaVzUwYjNKNUlHSmxiRzkzSUdseklITjBhV3hzSUhKbFlXd3NJR0oxZENCdWJ5QnlaVzFsWkdsaGRHbHZiaUJqWVc0Z1ltVWdZMjl0Y0hWMFpXUWda'
    || 'bTl5SUdFZ2NtOXNaU0J1YjJKdlpIa2dibUZ0WldRdUlsMTlLU3hsYVQxMVBUNTdZMjl1YzNRZ1pEMVRkSEpwYm1jb2RTa3VjM0JzYVhRb0lpNGlLVHR5WlhS'
    || 'MWNtNGdaQzVzWlc1bmRHZytNajlrTG5Oc2FXTmxLQzB5S1M1cWIybHVLQ0l1SWlrNlUzUnlhVzVuS0hVcGZUdG1kVzVqZEdsdmJpQm1jeWgxS1h0amIyNXpk'
    || 'Q0JrUFc5MEtIVXNJbUZ5YVhSb2JXVjBhV01pS1Zzd1hUOC9lMzBzWXoxMmRDaGtMbEpGUVVOSVgwNHBMSGc5ZG5Rb1pDNVNSVkZWU1ZKRlJGOU9LU3hGUFha'
    || 'MEtHUXVRazlVU0Y5T0tTeFVQWFowS0dRdVJWaERSVk5UWDA0cExIazlVM1J5YVc1bktHUXVUMUpEU0VWVFZGSkJWRTlTWDFKUFRFVS9QeUlpS1N4T1BWTjBj'
    || 'bWx1Wnloa0xrOVNRMGhmVTFSQlZFVmZSRVZVUVVsTVB6OGlJaWtzYWoxT0xtbHVZMngxWkdWektDSTZJaWsvVGk1emNHeHBkQ2dpT2lJcExuQnZjQ2dwTG5S'
    || 'eWFXMG9LVG9pUWt4QlRrc2lMRWM5ZVNFOVBTSWlKaVloTDE1dWIyNWxMMmt1ZEdWemRDaDVLVHR5WlhSMWNtNTdjbVZoWTJnNll5eHlaWEYxYVhKbFpEcDRM'
    || 'R0p2ZEdnNlJTeGxlR05sYzNNNlZDeHliMnhsT25rc2MzUmhkR1U2YWl4dVlXMWxaRHBITEdGelZYTmxjanAyZENoa0xrRlRYMVZUUlZKZlRpa3NjSEp2WTNN'
    || 'NmRuUW9aQzVRVWs5RFgwRlVWRVZOVUZSZlRpa3NiM2R1WldSQ2VVOXlZMmc2ZG5Rb1pDNVBWMDVGUkY5Q1dWOVBVa05JWDA0cGZYMW1kVzVqZEdsdmJpQnhZ'
    || 'eWg3Y0RwMWZTbDdZMjl1YzNRZ1pEMW1jeWgxS1N4N2JtRnRaV1E2WXl4emRHRjBaVHA0ZlQxa0xFVTlaQzV5WldGamFENHdQMDFoZEdndWNtOTFibVFvWkM1'
    || 'aWIzUm9MMlF1Y21WaFkyZ3FNVEF3S1RwdWRXeHNPM0psZEhWeWJpQnZMbXB6ZUhNb2J5NUdjbUZuYldWdWRDeDdZMmhwYkdSeVpXNDZXMjh1YW5ONEtGZGxM'
    || 'SHQwYVhSc1pUb2lVbVZoWTJnZ2JXbHVkWE1nY21WeGRXbHlaV1FpTEhkcFpHVTZJVEFzYUdsdWREcGdVbVZzWVhScGIyNXpJSFJvWlNCdmNtTm9aWE4wY21G'
    || 'MGIzSWdjbTlzWlNCallXNGdjbVZoWTJnZ2RHaHliM1ZuYUNCMGFHVWdkMmh2YkdVS0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ2NtOXNaU0JuY21Gd2FDd2dZ'
    || 'V2RoYVc1emRDQjBhR1VnY21Wc1lYUnBiMjV6SUhSb1pTQmtZblFnZDI5eWF5QmhZM1IxWVd4c2VRb2dJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ0lDQmtaV05zWVhK'
    || 'bGN5NGdWR2hsSUdScFptWmxjbVZ1WTJVZ2FYTWdjbVYyYjJOaFlteGxMbUFzWTJocGJHUnlaVzQ2Ynk1cWMzaHpLRXBsTEh0d1lXNWxiRHAxTG5CaGJtVnNj'
    || 'eTVoY21sMGFHMWxkR2xqTEhkb1pXNU5hWE56YVc1bk9tTS9ieTVxYzNoektHOHVSbkpoWjIxbGJuUXNlMk5vYVd4a2NtVnVPbHNpVkdobElHRnlhWFJvYldW'
    || 'MGFXTWdhR0Z6SUc1dmRDQmlaV1Z1SUdKMWFXeDBJSGxsZEM0Z1ZHaHBjeUJwY3lCaElHUnBjMk52ZG1WeWVTMXZibXg1SUhKMWJpd2djMjhnZEdobElIWnBa'
    || 'WGR6SUhSb1pTQmpiM1Z1ZEhNZ1kyOXRaU0JtY205dElHUnZJRzV2ZENCbGVHbHpkQzRnVTJWMElDSXNieTVxYzNnb0ltTnZaR1VpTEh0amFHbHNaSEpsYmpv'
    || 'aVJFVk1SVWRmUVZCUVVrOVdSU0o5S1N3aUlIUnZJaXdpSUNJc2J5NXFjM2dvSW1OdlpHVWlMSHRqYUdsc1pISmxiam9pVkZKVlJTSjlLU3dpSUdGdVpDQnlk'
    || 'VzRnZEdobElITmpjbWx3ZENCaFoyRnBiaTRpWFgwcE9tSnNMR05vYVd4a2NtVnVPbHR2TG1wemVDaFFZeXg3WVRwN2JHRmlaV3c2SW5KbGJHRjBhVzl1Y3lC'
    || 'eVpXRmphR0ZpYkdVaUxHNDZaQzV5WldGamFDeHpkV0k2WXo5a0xuSnZiR1U2SW01dklISnZiR1VnYm1GdFpXUWlmU3hpT250c1lXSmxiRG9pY21Wc1lYUnBi'
    || 'MjV6SUhKbGNYVnBjbVZrSWl4dU9tUXVjbVZ4ZFdseVpXUXNjM1ZpT2lKa1pXTnNZWEpsWkNCaWVTQjBhR1VnWkdKMElIQnliMnBsWTNSekluMHNZbTkwYURw'
    || 'a0xtSnZkR2dzZFc1cGREb2ljbVZzWVhScGIyNXpJbjBwTEc4dWFuTjRjeWdpWkdsMklpeDdZMnhoYzNOT1lXMWxPaUp6ZEdGMExYSnZkeUlzWTJocGJHUnla'
    || 'VzQ2VzI4dWFuTjRLRUp1TEh0c1lXSmxiRG9pUlhoalpYTnpJSEpsWVdOb0lpeDJZV3gxWlRwa0xtVjRZMlZ6Y3l4MWJtbDBPaUp5Wld4aGRHbHZibk1pTEhS'
    || 'dmJtVTZaQzVsZUdObGMzTStNRDhpWW1Ga0lqb2laMjl2WkNJc2MzVmlPbVF1WlhoalpYTnpQakEvSW5KbFlXTm9ZV0pzWlNCaGJtUWdibTkwSUhKbGNYVnBj'
    || 'bVZrSU9LQWxDQnlaWFp2YTJVZ2RHaGxjMlVpT2lKdWIzUm9hVzVuSUhKbFlXTm9ZV0pzWlNCaVpYbHZibVFnZDJoaGRDQjBhR1VnZDI5eWF5QnVaV1ZrY3lK'
    || 'OUtTeHZMbXB6ZUNoQ2JpeDdiR0ZpWld3NklsSmxjMjlzZG1Wa0lITjBZWFJsSWl4MllXeDFaVHA0TEhSdmJtVTZlRDA5UFNKR1QxVk9SQ0kvSW1kdmIyUWlP'
    || 'aUozWVhKdUlpeHpkV0k2ZUQwOVBTSk9UeUJCUTBORlUxTWlQeUpCUTBOUFZVNVVYMVZUUVVkRklHZHlZVzUwY3lCM1pYSmxJRzV2ZENCeVpXRmtZV0pzWlN3'
    || 'Z2MyOGdkR2hwY3lCcGN5QjFibXR1YjNkdUlISmhkR2hsY2lCMGFHRnVJSHBsY204aU9pSm9iM2NnZEdobElHNWhiV1ZrSUhKdmJHVWdjbVZ6YjJ4MlpXUWda'
    || 'SFZ5YVc1bklHUnBjMk52ZG1WeWVTSjlLU3hGSVQwOWJuVnNiQ1ltYnk1cWMzZ29RbTRzZTJ4aFltVnNPaUpTWldGamFDQjBhR1VnZDI5eWF5QnFkWE4wYVda'
    || 'cFpYTWlMSFpoYkhWbE9rVXNkVzVwZERvaUpTSXNkRzl1WlRwRlBqZ3dQeUpuYjI5a0lqb2lkMkZ5YmlJc2MzVmlPaUowYUdVZ2NtVnpkQ0JwY3lCcGJtaGxj'
    || 'bWwwWVc1alpTQnViMkp2WkhrZ2NtVmpiMjF3ZFhSbFpDSjlLVjE5S1N4a0xtVjRZMlZ6Y3o0d0ppWnZMbXB6ZUNoUFl5eDdjR04wT2sxaGRHZ3VjbTkxYm1R'
    || 'b1pDNWxlR05sYzNNdlRXRjBhQzV0WVhnb01TeGtMbkpsWVdOb0tTb3hNREFwTEd4aFltVnNPaUpTWldGamFDQjBhR0YwSUdseklHNXZkQ0J5WlhGMWFYSmxa'
    || 'Q0lzYjJZNkltOW1JR1YyWlhKNWRHaHBibWNnZEdocGN5QnliMnhsSUdOaGJpQjBiM1ZqYUNJc2RHOXVaVG9pWW1Ga0luMHBYWDBwZlNrc2J5NXFjM2dvVjJV'
    || 'c2UzUnBkR3hsT2lKWGFHRjBJSFJvWlNCaWRXbHNaQ0JqYjI1amJIVmtaV1FpTEhkcFpHVTZJVEFzYUdsdWREcGdWM0pwZEhSbGJpQmllU0IwYUdVZ2MyTnlh'
    || 'WEIwSUdsMGMyVnNaaXdnYVc1amJIVmthVzVuSUhSb1pTQnlaV1oxYzJGc0lISmxZWE52YmlCM2FHVnVDaUFnSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJSFJvWlhK'
    || 'bElHbHpJRzl1WlM0Z1UyaHZkMjRnZG1WeVltRjBhVzBnYzI4Z2RHaGxJR0Z3Y0NCaGJtUWdkR2hsSUhOamNtbHdkQ0JqWVc1dWIzUUtJQ0FnSUNBZ0lDQWdJ'
    || 'Q0FnSUNBZ0lDQWdaR2x6WVdkeVpXVXVZQ3hqYUdsc1pISmxianB2TG1wemVDaEtaU3g3Y0dGdVpXdzZkUzV3WVc1bGJITXVabWx1WkdsdVozTXNZMmhwYkdS'
    || 'eVpXNDZieTVxYzNnb1JIUXNlM0p2ZDNNNmIzUW9kU3dpWm1sdVpHbHVaM01pS1N4dFlYZzZNVElzWTI5c2N6cGJlMnRsZVRvaVJrbE9SRWxPUnlJc2JHRmla'
    || 'V3c2SWtacGJtUnBibWNpZlN4N2EyVjVPaUpXUVV4VlJTSXNiR0ZpWld3NklsWmhiSFZsSW4wc2UydGxlVG9pUkVWVVFVbE1JaXhzWVdKbGJEb2lWMmg1SUds'
    || 'MElHbHpJSEJvY21GelpXUWdkR2hwY3lCM1lYa2lmVjE5S1gwcGZTbGRmU2w5Wm5WdVkzUnBiMjRnU21Nb2UzQTZkWDBwZTNKbGRIVnliaUJ2TG1wemVITW9i'
    || 'eTVHY21GbmJXVnVkQ3g3WTJocGJHUnlaVzQ2VzI4dWFuTjRjeWhYWlN4N2RHbDBiR1U2SWtodmR5QmhJSEoxYmlCcGN5QjBjbWxuWjJWeVpXUWdZVzVrSUhk'
    || 'aGRHTm9aV1FpTEhkcFpHVTZJVEFzYUdsdWREcGdUMjVsSUhSeWFXZG5aWElzSUc5dVpTQndiMnhzTENCeVpXZGhjbVJzWlhOeklHOW1JR2h2ZHlCdFlXNTVJ'
    || 'R1JpZENCamIyMXRZVzVrY3lCMGFHVUtJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdaM0poY0dnZ1kyOXVkR0ZwYm5NdVlDeGphR2xzWkhKbGJqcGJieTVxYzNn'
    || 'b1ZXTXNlM04wWVdkbGN6cGJlMnhoWW1Wc09pSlBjbU5vWlhOMGNtRjBiM0lpTEhOMVlqb2lSVmhGUTFWVVJTQlVRVk5MSUM0dUxpQlZVMGxPUnlCRFQwNUdT'
    || 'VWNpTEd4cGRtVTZJVEI5TEh0c1lXSmxiRG9pUjNKaGNHZ2djbTl2ZENJc2MzVmlPaUpGV0VWRFZWUkZJRVJDVkNCUVVrOUtSVU5VTENCdmQyNWxjaWR6SUhK'
    || 'cFoyaDBjeUo5TEh0c1lXSmxiRG9pUVVaVVJWSWdZMmhwYkdSeVpXNGlMSE4xWWpvaWJtOGdjRzlzYkdsdVp5QmlaWFIzWldWdUlHaHZjSE1pZlN4N2JHRmla'
    || 'V3c2SWs5dVpTQndiMnhzSWl4emRXSTZJa2RTUVZCSVgxSlZUbDlIVWs5VlVGOUpSQ0JwYmlCSlRrWlBVazFCVkVsUFRsOVRRMGhGVFVFaWZWMTlLU3h2TG1w'
    || 'emVITW9jM01zZTJOb2FXeGtjbVZ1T2x0dkxtcHplQ2dpY0NJc2UyTm9hV3hrY21WdU9pSlVhR1VnYjNKamFHVnpkSEpoZEc5eUlIQmhjM05sY3lCcGRITWdi'
    || 'M2R1SUhKMWJpQnBaQ0JwYmlCM2FYUm9JSFJvWlNCMGNtbG5aMlZ5TENCemJ5QnBkQ0J3YjJ4c2N5Qm1iM0lnWVc0Z2FXUmxiblJwWm1sbGNpQnBkQ0JoYkhK'
    || 'bFlXUjVJR3R1YjNkeklPS0FsQ0J1YnlCamIyNTBjbTlzSUhSaFlteGxJR0Z1WkNCdWJ5QnRZWEJ3YVc1bklHeGhlV1Z5TGlCRGFHbHNaSEpsYmlCemRHRnlk'
    || 'Q0IwYUdVZ2JXOXRaVzUwSUhSb1pXbHlJSEJoY21WdWRDQnpkV05qWldWa2N5d2djMjhnWVdSa2FXNW5JR1JpZENCamIyMXRZVzVrY3lCaFpHUnpJSGR2Y21z'
    || 'Z1luVjBJRzV2ZENCd2IyeHNhVzVuSUdodmNITXVJbjBwTEc4dWFuTjRjeWdpY0NJc2UyTm9hV3hrY21WdU9sc2lVRzlzYkNCMGFHVWdJaXh2TG1wemVDZ2lZ'
    || 'MjlrWlNJc2UyTm9hV3hrY21WdU9pSkpUa1pQVWsxQlZFbFBUbDlUUTBoRlRVRXVWRUZUUzE5SVNWTlVUMUpaSW4wcExDSWdkR0ZpYkdVZ1puVnVZM1JwYjI0'
    || 'c0lHNXZkQ0FpTEc4dWFuTjRLQ0pqYjJSbElpeDdZMmhwYkdSeVpXNDZJa0ZEUTA5VlRsUmZWVk5CUjBVdVZFRlRTMTlJU1ZOVVQxSlpJbjBwTENJdUlGUm9a'
    || 'U0JoWTJOdmRXNTBMWFZ6WVdkbElIWnBaWGNnYkdGbmN5Qm1ZWElnWlc1dmRXZG9JSFJ2SUcxcGMzTWdZU0JtYVhabExXMXBiblYwWlNCMFlYSm5aWFFnYjI0'
    || 'Z2FYUnpJRzkzYmk0aVhYMHBMQ0V4WFgwcFhYMHBMRzh1YW5ONEtGZGxMSHQwYVhSc1pUb2lRMjl3ZVNCMGFHbHpJRzkxZENJc2QybGtaVG9oTUN4b2FXNTBP'
    || 'bUJVYUdVZ1ozSmhiblJ6SUdGeVpTQm9ZV3htSUhSb1pTQmtaV3hwZG1WeVlXSnNaUzRnVkdobElIUnlhV2RuWlhJZ1kyRnNiQ0JoYm1RZ2RHaGxDaUFnSUNB'
    || 'Z0lDQWdJQ0FnSUNBZ0lDQWdJSEJ2Ykd3Z2NYVmxjbmtnWVhKbElIUm9aU0J2ZEdobGNpQm9ZV3htTG1Bc1kyaHBiR1J5Wlc0NmJ5NXFjM2dvU21Vc2UzQmhi'
    || 'bVZzT25VdWNHRnVaV3h6TG5KbGJXVmthV0YwYVc5dUxIZG9aVzVOYVhOemFXNW5PbUpzTEdOb2FXeGtjbVZ1T204dWFuTjRLRVIwTEh0eWIzZHpPbTkwS0hV'
    || 'c0luSmxiV1ZrYVdGMGFXOXVJaWtzYldGNE9qUXdMR052YkhNNlczdHJaWGs2SWxkSVdTSXNiR0ZpWld3NklsZG9lU0o5TEh0clpYazZJbEpGVms5TFJWOVRV'
    || 'VXdpTEd4aFltVnNPaUpTWlhadmEyVWlMSEpsYm1SbGNqcGpQVDV2TG1wemVDZ2lZMjlrWlNJc2UyTm9hV3hrY21WdU9sTjBjbWx1WnloaktYMHBmU3g3YTJW'
    || 'NU9pSlVVa2xIUjBWU1gxTlJUQ0lzYkdGaVpXdzZJbFJ5YVdkblpYSWlMSEpsYm1SbGNqcGpQVDV2TG1wemVDZ2lZMjlrWlNJc2UyTm9hV3hrY21WdU9sTjBj'
    || 'bWx1WnloaktYMHBmU3g3YTJWNU9pSlFUMHhNWDFOUlRDSXNiR0ZpWld3NklsQnZiR3dpTEhKbGJtUmxjanBqUFQ1dkxtcHplQ2dpWTI5a1pTSXNlMk5vYVd4'
    || 'a2NtVnVPbE4wY21sdVp5aGpLWDBwZlYxOUtYMHBmU2xkZlNsOVpuVnVZM1JwYjI0Z1ltTW9lM0E2ZFgwcGUyTnZibk4wSUdROWIzUW9kU3dpWVc1MGFYQmhk'
    || 'SFJsY201eklpa3NZejFtY3loMUtTeDRQV011WVhOVmMyVnlMRVU5WXk1d2NtOWpjenR5WlhSMWNtNGdieTVxYzNnb2J5NUdjbUZuYldWdWRDeDdZMmhwYkdS'
    || 'eVpXNDZieTVxYzNnb1YyVXNlM1JwZEd4bE9pSlhhR1Z5WlNCMGFHVWdZbTkxYm1SaGNua2dhWE1nWVd4eVpXRmtlU0JpY205clpXNGlMSGRwWkdVNklUQXNh'
    || 'R2x1ZERwZ1ZHVjRkQ0J0WVhSamFHbHVaeUJ2ZG1WeUlHOWlhbVZqZENCa1pXWnBibWwwYVc5dWN5QnBiaUJCUTBOUFZVNVVYMVZUUVVkRkxDQnpieUJwZEFv'
    || 'Z0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnSUNCc1lXZHpJSFZ3SUhSdklIUjNieUJvYjNWeWN5QmhibVFnYldGMFkyaGxjeUJqYjIxdFpXNTBaV1F0YjNWMElISmxa'
    || 'bVZ5Wlc1alpYTXVDaUFnSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJRTV2ZENCaElHTnZiWEJzWlhSbGJtVnpjeUJqYkdGcGJTNWdMR05vYVd4a2NtVnVPbTh1YW5O'
    || 'NGN5aEtaU3g3Y0dGdVpXdzZkUzV3WVc1bGJITXVZVzUwYVhCaGRIUmxjbTV6TEhkb1pXNU5hWE56YVc1bk9pSk9ieUIyYVc5c1lYUnBiMjV6SUhacGMybGli'
    || 'R1VnNG9DVUlIZG9hV05vSUdseklHRWdabWx1WkdsdVp5d2dibTkwSUdFZ2NISnZiMll1SWl4amFHbHNaSEpsYmpwYmJ5NXFjM2h6S0NKa2FYWWlMSHRqYkdG'
    || 'emMwNWhiV1U2SW5OMFlYUXRjbTkzSWl4amFHbHNaSEpsYmpwYmJ5NXFjM2dvUW00c2UyeGhZbVZzT2lKVVlYTnJjeUJ6WlhRZ1JWaEZRMVZVUlNCQlV5QlZV'
    || 'MFZTSWl4MllXeDFaVHA0TEhSdmJtVTZlRDR3UHlKaVlXUWlPaUpuYjI5a0lpeHpkV0k2SW1aaGFXeHpJR0YwSUhKMWJpQjBhVzFsTENCdWIzUWdZWFFnWTNK'
    || 'bFlYUnBiMjRnNG9DVUlIZG9hV05vSUdseklHaHZkeUJwZENCemRYSjJhWFpsY3lCeVpYWnBaWGNpZlNrc2J5NXFjM2dvUW00c2UyeGhZbVZzT2lKUWNtOWpa'
    || 'V1IxY21WeklHRjBkR1Z0Y0hScGJtY2dUbEJQSUdWNFpXTjFkR2x2YmlJc2RtRnNkV1U2UlN4MGIyNWxPa1UrTUQ4aWQyRnliaUk2SW1kdmIyUWlMSE4xWWpv'
    || 'aWRHaGxJSGR2Y210aGNtOTFibVFnZEdoaGRDQmpZVzV1YjNRZ2QyOXlhenNnWm1sdVpHbHVaeUJ2Ym1VZ2JXVmhibk1nWVNCMFpXRnRJR0ZzY21WaFpIa2dh'
    || 'R2wwSUhSb1pTQjNZV3hzSW4wcFhYMHBMRzh1YW5ONEtFUjBMSHR5YjNkek9tUXNiV0Y0T2pJMUxHTnZiSE02VzN0clpYazZJbE5GVmtWU1NWUlpJaXhzWVdK'
    || 'bGJEb2lVMlYyWlhKcGRIa2lMSEpsYm1SbGNqcFVQVDV2TG1wemVDaHZjeXg3ZEc5dVpUcFRkSEpwYm1jb1ZDazlQVDBpU0VsSFNDSS9JbUpoWkNJNkluZGhj'
    || 'bTRpTEdOb2FXeGtjbVZ1T2xOMGNtbHVaeWhVS1gwcGZTeDdhMlY1T2lKR1NVNUVTVTVISWl4c1lXSmxiRG9pUm1sdVpHbHVaeUo5TEh0clpYazZJazlDU2tW'
    || 'RFZGOUdVVTRpTEd4aFltVnNPaUpQWW1wbFkzUWlMSEpsYm1SbGNqcFVQVDV2TG1wemVDZ2lZMjlrWlNJc2UyTm9hV3hrY21WdU9tVnBLRk4wY21sdVp5aFVL'
    || 'U2w5S1gwc2UydGxlVG9pVDFkT1JVUmZRbGtpTEd4aFltVnNPaUpQZDI1bFpDQmllU0o5TEh0clpYazZJbGRJV1NJc2JHRmlaV3c2SWxkb2VTQnBkQ0J0WVhS'
    || 'MFpYSnpJbjFkZlNsZGZTbDlLWDBwZldaMWJtTjBhVzl1SUdWa0tIdHdPblY5S1h0eVpYUjFjbTRnYnk1cWMzaHpLRzh1Um5KaFoyMWxiblFzZTJOb2FXeGtj'
    || 'bVZ1T2x0dkxtcHplQ2hYWlN4N2RHbDBiR1U2SWtodmR5QjBhR1VnY205c1pTQm5iM1FnZEdobGNtVWlMSGRwWkdVNklUQXNhR2x1ZERwZ1NHOXdjeUJtY205'
    || 'dElIUm9aU0J2Y21Ob1pYTjBjbUYwYjNJZ2NtOXNaUzRnV21WeWJ5QnBjeUJoSUdScGNtVmpkQ0JuY21GdWREc0tJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdZ'
    || 'VzU1ZEdocGJtY2dhR2xuYUdWeUlHbHpJR2x1YUdWeWFYUmhibU5sTENCM2FHbGphQ0JwY3lCb2IzY2dZU0J6WlhKMmFXTmxJSEp2YkdVS0lDQWdJQ0FnSUNB'
    || 'Z0lDQWdJQ0FnSUNBZ2NYVnBaWFJzZVNCaVpXTnZiV1Z6SUhkcFpHVXVZQ3hqYUdsc1pISmxianB2TG1wemVDaEtaU3g3Y0dGdVpXdzZkUzV3WVc1bGJITXVj'
    || 'bVZoWTJnc2QyaGxiazFwYzNOcGJtYzZZbXdzWTJocGJHUnlaVzQ2Ynk1cWMzZ29SSFFzZTNKdmQzTTZiM1FvZFN3aWNtVmhZMmdpS1N4dFlYZzZOREFzWTI5'
    || 'c2N6cGJlMnRsZVRvaVNFOVFVMTlHVWs5TlgwOVNRMGhGVTFSU1FWUlBVaUlzYkdGaVpXdzZJa2h2Y0hNaWZTeDdhMlY1T2lKU1JVeEJWRWxQVGw5R1VVNGlM'
    || 'R3hoWW1Wc09pSlNaV3hoZEdsdmJpSXNjbVZ1WkdWeU9tUTlQbTh1YW5ONEtDSmpiMlJsSWl4N1kyaHBiR1J5Wlc0NlpXa29VM1J5YVc1bktHUXBLWDBwZlN4'
    || 'N2EyVjVPaUpRVWtsV1NVeEZSMFVpTEd4aFltVnNPaUpRY21sMmFXeGxaMlVpZlN4N2EyVjVPaUpIVWtGT1ZFVkVYMVJQWDFKUFRFVWlMR3hoWW1Wc09pSkhj'
    || 'bUZ1ZEdWa0lIUnZJbjBzZTJ0bGVUb2lTRTlYSWl4c1lXSmxiRG9pU0c5M0luMWRmU2w5S1gwcExHOHVhbk40S0ZkbExIdDBhWFJzWlRvaVYyaGhkQ0IwYUdV'
    || 'Z2QyOXlheUJoWTNSMVlXeHNlU0JrWldOc1lYSmxjeUlzZDJsa1pUb2hNQ3hvYVc1ME9tQkVaWEpwZG1Wa0lHWnliMjBnWldGamFDQmtZblFnY0hKdmFtVmpk'
    || 'Q2R6SUc5M2JpQnpiM1Z5WTJWeklHRnVaQ0IwWVhKblpYUXVJRlJvYVhNZ2FYTUtJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdkR2hsSUdac2IyOXlJSFJvWlNC'
    || 'bGVHTmxjM01nYVhNZ2JXVmhjM1Z5WldRZ1lXZGhhVzV6ZEN3Z2JtOTBJR0VnWjNWbGMzTXVZQ3hqYUdsc1pISmxianB2TG1wemVDaEtaU3g3Y0dGdVpXdzZk'
    || 'UzV3WVc1bGJITXVjbVZ4ZFdseVpXUXNZMmhwYkdSeVpXNDZieTVxYzNnb1JIUXNlM0p2ZDNNNmIzUW9kU3dpY21WeGRXbHlaV1FpS1N4dFlYZzZOREFzWTI5'
    || 'c2N6cGJlMnRsZVRvaVQwSktSVU5VWDBaUlRpSXNiR0ZpWld3NklsSmxiR0YwYVc5dUlpeHlaVzVrWlhJNlpEMCtieTVxYzNnb0ltTnZaR1VpTEh0amFHbHNa'
    || 'SEpsYmpwbGFTaFRkSEpwYm1jb1pDa3BmU2w5TEh0clpYazZJbEJTU1ZaSlRFVkhSU0lzYkdGaVpXdzZJbEJ5YVhacGJHVm5aU0o5TEh0clpYazZJbEpQVEVW'
    || 'ZlRrVkZSQ0lzYkdGaVpXdzZJbEp2YkdVZ2RHaGhkQ0J1WldWa2N5QnBkQ0o5TEh0clpYazZJa1JGVWtsV1JVUmZSbEpQVFNJc2JHRmlaV3c2SWtSbGNtbDJa'
    || 'V1FnWm5KdmJTSjlYWDBwZlNsOUtWMTlLWDFtZFc1amRHbHZiaUIwWkNoN2NEcDFmU2w3WTI5dWMzUWdaRDF2ZENoMUxDSmtjbWxtZENJcExHTTlaQzV0WVhB'
    || 'b2VUMCtkblFvZVM1RldFTkZVMU5mVWtWTVFWUkpUMDVUS1Nrc2VEMWtMbXhsYm1kMGFEOWtXMlF1YkdWdVozUm9MVEZkT25admFXUWdNQ3hGUFdRdWJHVnVa'
    || 'M1JvUDJSYk1GMDZkbTlwWkNBd0xGUTllQ1ltUlNZbWRuUW9lQzVGV0VORlUxTmZVa1ZNUVZSSlQwNVRLVDUyZENoRkxrVllRMFZUVTE5U1JVeEJWRWxQVGxN'
    || 'cE8zSmxkSFZ5YmlCdkxtcHplQ2hYWlN4N2RHbDBiR1U2SWtWNFkyVnpjeUJ5WldGamFDQnZkbVZ5SUhScGJXVWlMSGRwWkdVNklUQXNhR2x1ZERwZ1QyNWxJ'
    || 'SEp2ZHlCd1pYSWdaSEpwWm5RZ1kyaGxZMnN1SUZSb1pTQnpaWEpwWlhNZ2FYTWdkR2hsSUhCdmFXNTBPaUJzWldGemRDQndjbWwyYVd4bFoyVUtJQ0FnSUNB'
    || 'Z0lDQWdJQ0FnSUNBZ0lHUmxZMkY1Y3lCeGRXbGxkR3g1SUhkb1pXNGdjMjl0WldKdlpIa2daM0poYm5SeklHRWdjbTlzWlNCaGRDQXlZVzBnZEc4Z1ptbDRJ'
    || 'R0VLSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJR0p5YjJ0bGJpQnlkVzR1WUN4amFHbHNaSEpsYmpwdkxtcHplSE1vU21Vc2UzQmhibVZzT25VdWNHRnVaV3h6TG1S'
    || 'eWFXWjBMSGRvWlc1TmFYTnphVzVuT21CT2J5QnpibUZ3YzJodmRITWdlV1YwTGlCVWFHVWdaSEpwWm5RZ2JXOXVhWFJ2Y2lCM2NtbDBaWE1nYjI1bElISnZk'
    || 'd29nSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnSUNCd1pYSWdjblZ1SUdGdVpDQnZibXg1SUdsdWMzUmhiR3h6SUdGMElGQlNUMFJWUTFS'
    || 'SlQwNGdkR2xsY2k1Z0xHTm9hV3hrY21WdU9sdGpMbXhsYm1kMGFENHhQMjh1YW5ONGN5aHZMa1p5WVdkdFpXNTBMSHRqYUdsc1pISmxianBiYnk1cWMzZ29R'
    || 'V01zZTNCdmFXNTBjenBqZlNrc1ZDWW1ieTVxYzNnb1RXTXNlMk5vYVd4a2NtVnVPaUpGZUdObGMzTWdjbVZoWTJnZ2FHRnpJR2R5YjNkdUlITnBibU5sSUhS'
    || 'b1pTQm1hWEp6ZENCemJtRndjMmh2ZEM0Z1UyOXRaWFJvYVc1bklIZGhjeUJuY21GdWRHVmtJSFJvWVhRZ2JtOWliMlI1SUhKbFkyOXRjSFYwWldRZ2RHaGxJ'
    || 'R0pzWVhOMElISmhaR2wxY3lCbWIzSXVJbjBwWFgwcE9tOHVhbk40S0NKd0lpeDdZMnhoYzNOT1lXMWxPaUp3WVc1bGJDMWxiWEIwZVNJc1kyaHBiR1J5Wlc0'
    || 'NklrOXVaU0J6Ym1Gd2MyaHZkQ0J6YnlCbVlYSWc0b0NVSUdFZ2MyVnlhV1Z6SUc1bFpXUnpJR0YwSUd4bFlYTjBJSFIzYnk0Z1ZHaHBjeUJwY3lCMGFHVWdh'
    || 'Rzl1WlhOMElITjBZWFJsSUc5bUlHRWdabkpsYzJoc2VTQmlkV2xzZENCa1pXMXZMQ0J1YjNRZ1lTQmljbTlyWlc0Z2NHRnVaV3d1SW4wcExHOHVhbk40S0VS'
    || 'MExIdHliM2R6T21Rc2JXRjRPakl3TEdOdmJITTZXM3RyWlhrNklsTk9RVkJUU0U5VVgwRlVJaXhzWVdKbGJEb2lUMkp6WlhKMlpXUWlmU3g3YTJWNU9pSlBV'
    || 'a05JUlZOVVVrRlVUMUpmVWs5TVJTSXNiR0ZpWld3NklsSnZiR1VpZlN4N2EyVjVPaUpTUlVGRFNGOVNSVXhCVkVsUFRsTWlMR3hoWW1Wc09pSlNaV0ZqYUNK'
    || 'OUxIdHJaWGs2SWxKRlVWVkpVa1ZFWDFKRlRFRlVTVTlPVXlJc2JHRmlaV3c2SWxKbGNYVnBjbVZrSW4wc2UydGxlVG9pUlZoRFJWTlRYMUpGVEVGVVNVOU9V'
    || 'eUlzYkdGaVpXdzZJa1Y0WTJWemN5SjlMSHRyWlhrNklrRk9WRWxRUVZSVVJWSk9VeUlzYkdGaVpXdzZJbFpwYjJ4aGRHbHZibk1pZlYxOUtWMTlLWDBwZlda'
    || 'MWJtTjBhVzl1SUc1a0tDbDdjbVYwZFhKdUlHOHVhbk40S0ZkbExIdDBhWFJzWlRvaVYyaGhkQ0IwYUdseklIQnliM1psY3l3Z1lXNWtJSGRvWVhRZ2FYUWda'
    || 'RzlsY3lCdWIzUWlMSGRwWkdVNklUQXNZMmhwYkdSeVpXNDZieTVxYzNoektITnpMSHRqYUdsc1pISmxianBiYnk1cWMzaHpLQ0p3SWl4N1kyaHBiR1J5Wlc0'
    || 'NlcyOHVhbk40S0NKemRISnZibWNpTEh0amFHbHNaSEpsYmpvaVNYUWdaRzlsY3lCd2NtOTJaU0IwYUdVZ1lYSnBkR2h0WlhScFl5NGlmU2tzSWlCU1pXRmph'
    || 'Q0JwY3lCM1lXeHJaV1FnZEdoeWIzVm5hQ0IwYUdVZ1puVnNiQ0J5YjJ4bElHZHlZWEJvSUdsdVkyeDFaR2x1WnlCcGJtaGxjbWwwWVc1alpTd2dZVzVrSUhK'
    || 'bGNYVnBjbVZrSUhCeWFYWnBiR1ZuWlhNZ1kyOXRaU0JtY205dElHVmhZMmdnWkdKMElIQnliMnBsWTNRbmN5QnZkMjRnWkdWamJHRnlaV1FnYzI5MWNtTmxj'
    || 'eUJoYm1RZ2RHRnlaMlYwSUhKaGRHaGxjaUIwYUdGdUlHWnliMjBnWVNCdVlXMWxMVzFoZEdOb2FXNW5JR2hsZFhKcGMzUnBZeTRpWFgwcExHOHVhbk40Y3ln'
    || 'aWNDSXNlMk5vYVd4a2NtVnVPbHR2TG1wemVDZ2ljM1J5YjI1bklpeDdZMmhwYkdSeVpXNDZJa2wwSUdSdlpYTWdibTkwSUhCeWIzWmxJR0VnY25WdUlHTmhj'
    || 'bkpwWlhNZ2RHaGxJR1Y0WldOMWRHbHZiaUJ5YjJ4bEozTWdjbWxuYUhSekxpSjlLU3dpSUZSb1lYUWdhWE1nWVNCd2NtOXdaWEowZVNCdlppQmhJSEoxYml3'
    || 'Z2JtOTBJRzltSUdFZ2RtbGxkeXdnWVc1a0lIUm9hWE1nWVhCd0lISjFibk1nWVhNZ2FYUnpJRzkzYm1WeUxpQlVhR1VnWjJGMWJuUnNaWFFuY3lCcGMyOXNZ'
    || 'WFJwYjI0Z1kyaGxZMnR6SUhCeWIzWmxJR2wwSUdKNUlITjNhWFJqYUdsdVp5QnliMnhsSU9LQWxDQjBhR1VnYzJWeWRtbGpaU0J5YjJ4bElHMTFjM1FnWm1G'
    || 'cGJDQmhJQ0lzYnk1cWMzZ29JbU52WkdVaUxIdGphR2xzWkhKbGJqb2lVMFZNUlVOVUluMHBMQ0lnWVc1a0lITjBhV3hzSUhOMVkyTmxaV1FnWVhRZ0lpeHZM'
    || 'bXB6ZUNnaVkyOWtaU0lzZTJOb2FXeGtjbVZ1T2lKRldFVkRWVlJGSUZSQlUwc2lmU2tzSWk0aVhYMHBMRzh1YW5ONGN5Z2ljQ0lzZTJOb2FXeGtjbVZ1T2x0'
    || 'dkxtcHplQ2dpYzNSeWIyNW5JaXg3WTJocGJHUnlaVzQ2SWxSb1pTQjJhVzlzWVhScGIyNGdjR0Z1Wld3Z2FYTWdibTkwSUdFZ1kyOXRjR3hsZEdWdVpYTnpJ'
    || 'R05zWVdsdExpSjlLU3dpSUVsMElHMWhkR05vWlhNZ2RHVjRkQ0JwYmlBaUxHOHVhbk40S0NKamIyUmxJaXg3WTJocGJHUnlaVzQ2SWtGRFEwOVZUbFJmVlZO'
    || 'QlIwVWlmU2tzSWlCa1pXWnBibWwwYVc5dWN5d2djMjhnYVhRZ2JHRm5jeUIxY0NCMGJ5QjBkMjhnYUc5MWNuTWdZVzVrSUhkcGJHd2diV0YwWTJnZ1lTQmpi'
    || 'MjF0Wlc1MFpXUXRiM1YwSUhKbFptVnlaVzVqWlM0aVhYMHBMRzh1YW5ONGN5Z2ljQ0lzZTJOb2FXeGtjbVZ1T2x0dkxtcHplSE1vSW5OMGNtOXVaeUlzZTJO'
    || 'b2FXeGtjbVZ1T2xzaVFTQjBZWE5ySUhkb2IzTmxJR0p2WkhrZ2FYTWdiMjVzZVNBaUxHOHVhbk40S0NKamIyUmxJaXg3WTJocGJHUnlaVzQ2SWtWWVJVTlZW'
    || 'RVVnUkVKVUlGQlNUMHBGUTFRaWZTa3NJbU5oYm01dmRDQmhiSE52SUhObGRDQmhJSEpsZEhWeWJpQjJZV3gxWlM0aVhYMHBMQ0lnUjJWMGRHbHVaeUJoSUdS'
    || 'aWRDMXphR0Z3WldRZ2NtVnpkV3gwSUdKaFkyc2dibVZsWkhNZ1lTQm1hVzVoYkdsNlpYSWdkR0Z6YXlCaGRDQjBhR1VnWlc1a0lHOW1JSFJvWlNCbmNtRndh'
    || 'Q0RpZ0pRZ2IyNWxJRzF2Y21VZ2IySnFaV04wSUdGdVpDQnZibVVnYlc5eVpTQm9iM0FzSUhOMFlYUmxaQ0J5WVhSb1pYSWdkR2hoYmlCcGJYQnNhV1ZrSUhS'
    || 'dklHSmxJR1p5WldVdUlsMTlLVjE5S1gwcGZXWjFibU4wYVc5dUlISmtLSHR3T25WOUtYdGpiMjV6ZENCa1BWdDdhV1E2SW1GeWFYUm9iV1YwYVdNaUxHeGhZ'
    || 'bVZzT2lKVWFHVWdZWEpwZEdodFpYUnBZeUlzWkdWell6b2lVbVZoWTJnZ2JXbHVkWE1nY21WeGRXbHlaV1FpTEdsamIyNDZJbk5vYVdWc1pDSXNjR0Z1Wld4'
    || 'ek9sc2lZWEpwZEdodFpYUnBZeUlzSW1acGJtUnBibWR6SWwwc2NtVnVaR1Z5T2lncFBUNXZMbXB6ZUNoeFl5eDdjRHAxZlNsOUxIdHBaRG9pZEc5d2IyeHZa'
    || 'M2tpTEd4aFltVnNPaUpVY21sbloyVnlJR0Z1WkNCd2IyeHNJaXhrWlhOak9pSlBibVVnYUc5d0xDQnViM1FnVGlJc2FXTnZiam9pWm14dmR5SXNjR0Z1Wld4'
    || 'ek9sc2ljbVZ0WldScFlYUnBiMjRpWFN4eVpXNWtaWEk2S0NrOVBtOHVhbk40S0VwakxIdHdPblY5S1gwc2UybGtPaUoyYVc5c1lYUnBiMjV6SWl4c1lXSmxi'
    || 'RG9pUW05MWJtUmhjbmtnZG1sdmJHRjBhVzl1Y3lJc1pHVnpZem9pUVd4eVpXRmtlU0JpY205clpXNGlMR2xqYjI0NkluZGhjbTRpTEhCaGJtVnNjenBiSW1G'
    || 'dWRHbHdZWFIwWlhKdWN5SmRMSEpsYm1SbGNqb29LVDArYnk1cWMzZ29ZbU1zZTNBNmRYMHBmU3g3YVdRNkluSmxZV05vSWl4c1lXSmxiRG9pU0c5M0lHbDBJ'
    || 'R2R2ZENCMGFHVnlaU0lzWkdWell6b2lTVzVvWlhKcGRHRnVZMlVzSUdodmNDQmllU0JvYjNBaUxHbGpiMjQ2SW5SaFlteGxJaXh3WVc1bGJITTZXeUp5WldG'
    || 'amFDSXNJbkpsY1hWcGNtVmtJbDBzY21WdVpHVnlPaWdwUFQ1dkxtcHplQ2hsWkN4N2NEcDFmU2w5TEh0cFpEb2laSEpwWm5RaUxHeGhZbVZzT2lKRWNtbG1k'
    || 'Q0lzWkdWell6b2lUR1ZoYzNRZ2NISnBkbWxzWldkbElHUmxZMkY1Y3lJc2FXTnZiam9pYkdGNVpYSnpJaXh3WVc1bGJITTZXeUprY21sbWRDSmRMSEpsYm1S'
    || 'bGNqb29LVDArYnk1cWMzZ29kR1FzZTNBNmRYMHBmU3g3YVdRNklteHBiV2wwY3lJc2JHRmlaV3c2SWxkb1lYUWdkR2hwY3lCd2NtOTJaWE1pTEdSbGMyTTZJ'
    || 'a0Z1WkNCM2FHRjBJR2wwSUdSdlpYTWdibTkwSWl4cFkyOXVPaUozWVhKdUlpeHlaVzVrWlhJNktDazlQbTh1YW5ONEtHNWtMSHQ5S1gwc2UybGtPaUpoWTNS'
    || 'cGIyNXpJaXhzWVdKbGJEb2lWMmhoZENCMGFHbHpJR05oYmlCa2J5SXNaR1Z6WXpvaVFXTjBhVzl1Y3lCaGJtUWdhR2x6ZEc5eWVTSXNhV052YmpvaVpteHZk'
    || 'eUlzY0dGdVpXeHpPbHNpWVdOMGFXOXVjeUlzSW1GamRHbHZibDlzYjJjaVhTeHlaVzVrWlhJNktDazlQbTh1YW5ONGN5aHZMa1p5WVdkdFpXNTBMSHRqYUds'
    || 'c1pISmxianBiYnk1cWMzZ29WMlVzZTNScGRHeGxPaUpCZG1GcGJHRmliR1VnWVdOMGFXOXVjeUlzZDJsa1pUb2hNQ3hvYVc1ME9tQkZZV05vSUdGamRHbHZi'
    || 'aUJwY3lCaElHTm9ZVzVuWlNCMGFHbHpJSE52YkhWMGFXOXVJR05oYmlCdFlXdGxJSFJ2SUhsdmRYSUtJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnSUdG'
    || 'alkyOTFiblF1WUN4amFHbHNaSEpsYmpwdkxtcHplQ2hLWlN4N2NHRnVaV3c2ZFM1d1lXNWxiSE11WVdOMGFXOXVjeXh1YjNSQ2RXbHNkRUpzYjJOck9tOHVh'
    || 'bk40S0VSakxIdHpaWFIwYVc1bk9pSkVSVXhGUjE5QlRFeFBWMTlCUTFSSlQwNVRJbjBwTEdOb2FXeGtjbVZ1T204dWFuTjRLRWxqTEh0aFkzUnBiMjV6T205'
    || 'MEtIVXNJbUZqZEdsdmJuTWlLWDBwZlNsOUtTeHZMbXB6ZUNoWFpTeDdkR2wwYkdVNklsSmxZMlZ1ZENCeWRXNXpJaXgzYVdSbE9pRXdMR2hwYm5RNllGUm9a'
    || 'U0JzWVhOMElHRmpkR2x2Ym5NZ1pYaGxZM1YwWldRZ2IzSWdkVzVrYjI1bExDQjNhWFJvSUhScGJXVnpkR0Z0Y0hNZ1lXNWtDaUFnSUNBZ0lDQWdJQ0FnSUNB'
    || 'Z0lDQWdJQ0FnSUNCemRHRjBkWE11WUN4amFHbHNaSEpsYmpwdkxtcHplQ2hLWlN4N2NHRnVaV3c2ZFM1d1lXNWxiSE11WVdOMGFXOXVYMnh2Wnl4M2FHVnVU'
    || 'V2x6YzJsdVp6b2lUbThnWVdOMGFXOXVJR3h2WnlCbGVHbHpkSE1nZVdWMElPS0FsQ0J1YjNSb2FXNW5JR2hoY3lCaVpXVnVJSEoxYmk0aUxHTm9hV3hrY21W'
    || 'dU9tOHVhbk40S0hwakxIdHNiMmM2YjNRb2RTd2lZV04wYVc5dVgyeHZaeUlwZlNsOUtYMHBYWDBwZlYwN2NtVjBkWEp1SUc4dWFuTjRLRkZqTEh0d1lYbHNi'
    || 'MkZrT25Vc2MzVmlkR2wwYkdVNklscGxjbTh0Y0hKcGRtbHNaV2RsSUc5eVkyaGxjM1J5WVhScGIyNGlMSE5sWTNScGIyNXpPbVI5S1gxYVl5aDFQVDV2TG1w'
    || 'emVDaHlaQ3g3Y0RwMWZTa3BmU2tvS1RzSyIKQVBQX0NTU19CNjQgPSAiTG1Gd2NDMTJhV1YzTFcxbGJuVjdjRzl6YVhScGIyNDZjbVZzWVhScGRtVTdabXhs'
    || 'ZURwdWIyNWxPMjFoY21kcGJpMXNaV1owT21GMWRHODdZMjlzYjNJNmRtRnlLQzB0Ym1GMmVTd2dJekE1TVdZek5pbDlMbUZ3Y0MxMmFXVjNMVzFsYm5VK2Mz'
    || 'VnRiV0Z5ZVh0a2FYTndiR0Y1T21ac1pYZzdZV3hwWjI0dGFYUmxiWE02WTJWdWRHVnlPMnAxYzNScFpua3RZMjl1ZEdWdWREcGpaVzUwWlhJN2QybGtkR2c2'
    || 'TXpad2VEdG9aV2xuYUhRNk16WndlRHR3WVdSa2FXNW5PakE3WW05eVpHVnlPakE3WW05eVpHVnlMWEpoWkdsMWN6bzFjSGc3WTNWeWMyOXlPbkJ2YVc1MFpY'
    || 'STdiR2x6ZEMxemRIbHNaVHB1YjI1bGZTNWhjSEF0ZG1sbGR5MXRaVzUxUG5OMWJXMWhjbms2T2kxM1pXSnJhWFF0WkdWMFlXbHNjeTF0WVhKclpYSjdaR2x6'
    || 'Y0d4aGVUcHViMjVsZlM1aGNIQXRkbWxsZHkxdFpXNTFQbk4xYlcxaGNuazZhRzkyWlhJc0xtRndjQzEyYVdWM0xXMWxiblZiYjNCbGJsMCtjM1Z0YldGeWVY'
    || 'dGlZV05yWjNKdmRXNWtPblpoY2lndExYTjFjbVpoWTJVdE1pd2dJMll6WmpObU5DbDlMbUZ3Y0MxMmFXVjNMVzFsYm5VK2MzVnRiV0Z5ZVRwbWIyTjFjeTEy'
    || 'YVhOcFlteGxMQzVoY0hBdGRtbGxkeTF2Y0hScGIyNXpQbUU2Wm05amRYTXRkbWx6YVdKc1pYdHZkWFJzYVc1bE9qSndlQ0J6YjJ4cFpDQjJZWElvTFMxaFky'
    || 'TmxiblFzSUNNd01EZzBaRFFwTzI5MWRHeHBibVV0YjJabWMyVjBPakp3ZUgwdVlYQndMWFpwWlhjdGIzQjBhVzl1YzN0d2IzTnBkR2x2YmpwaFluTnZiSFYw'
    || 'WlR0NkxXbHVaR1Y0T2pNd08zSnBaMmgwT2pBN2RHOXdPbU5oYkdNb01UQXdKU0FySURad2VDazdkMmxrZEdnNk1UYzBjSGc3YldGNExYZHBaSFJvT21OaGJH'
    || 'TW9NVEF3ZG5jZ0xTQXpNbkI0S1R0a2FYTndiR0Y1T21keWFXUTdaMkZ3T2pKd2VEdHdZV1JrYVc1bk9qVndlRHRpYjNKa1pYSTZNWEI0SUhOdmJHbGtJSFpo'
    || 'Y2lndExXeHBibVVzSUNObE1tVXlaVFlwTzJKdmNtUmxjaTF5WVdScGRYTTZObkI0TzJKaFkydG5jbTkxYm1RNkkyWm1aanRpYjNndGMyaGhaRzkzT2pBZ05u'
    || 'QjRJREU0Y0hnZ0l6QTVNV1l6TmpGbWZTNWhjSEF0ZG1sbGR5MXZjSFJwYjI1elBtRjdaR2x6Y0d4aGVUcGliRzlqYXp0d1lXUmthVzVuT2psd2VDQXhNSEI0'
    || 'TzJOdmJHOXlPbWx1YUdWeWFYUTdabTl1ZERwcGJtaGxjbWwwTzJadmJuUXRjMmw2WlRveE0zQjRPMnhwYm1VdGFHVnBaMmgwT2pFdU5UdDBaWGgwTFdSbFky'
    || 'OXlZWFJwYjI0NmJtOXVaVHRpYjNKa1pYSXRjbUZrYVhWek9qTndlSDB1WVhCd0xYWnBaWGN0YjNCMGFXOXVjejVoT21odmRtVnllMkpoWTJ0bmNtOTFibVE2'
    || 'ZG1GeUtDMHRjM1Z5Wm1GalpTMHlMQ0FqWmpObU0yWTBLWDA2Y205dmRIc3RMV0puT2lBalpqaG1PR1k0T3kwdGMzVnlabUZqWlRvZ0kyWm1abVptWmpzdExY'
    || 'TjFjbVpoWTJVdE1qb2dJMll6WmpObU5Ec3RMWE4xY21aaFkyVXRNem9nSTJWaVpXSmxaRHN0TFd4cGJtVTZJQ05sTldVMVpUYzdMUzFzYVc1bExUSTZJQ05r'
    || 'Tm1RMlpEazdMUzEwWlhoME9pQWpNVEV4TVRFeE95MHRiWFYwWldRNklDTTJZalppTm1JN0xTMWthVzA2SUNOaE0yRXpZVE03TFMxaFkyTmxiblE2SUNNd01E'
    || 'ZzBaRFE3TFMxdVlYWjVPaUFqTUdFeU16UXlPeTB0YzJ0NU9pQWpNamxpTldVNE95MHRaMjl2WkRvZ0l6RTJZVE0wWVRzdExYZGhjbTQ2SUNObU5UbGxNR0k3'
    || 'TFMxaVlXUTZJQ05sT0RBd01XTTdMUzEyYVc5c1pYUTZJQ00zWXpOaFpXUTdMUzFuYjI5a0xYZGhjMmc2SUhKblltRW9NaklzSURFMk15d2dOelFzSUM0d09D'
    || 'azdMUzEzWVhKdUxYZGhjMmc2SUhKblltRW9NalExTENBeE5UZ3NJREV4TENBdU1TazdMUzFpWVdRdGQyRnphRG9nY21kaVlTZ3lNeklzSURBc0lESTRMQ0F1'
    || 'TURjcE95MHRZV05qWlc1MExYZGhjMmc2SUhKblltRW9NQ3dnTVRNeUxDQXlNVElzSUM0d055azdMUzF5WVdScGRYTTZJREV5Y0hnN0xTMXlZV1JwZFhNdGJH'
    || 'YzZJREUyY0hnN0xTMXlZV1JwZFhNdGVHdzZJREl3Y0hnN0xTMXphQzFqWVhKa09pQXdJREZ3ZUNBemNIZ2djbWRpWVNnd0xDQXdMQ0F3TENBdU1EWXBMQ0F3'
    || 'SURKd2VDQXhNbkI0SUhKblltRW9NQ3dnTUN3Z01Dd2dMakEwS1RzdExYTm9MVzFrT2lBd0lESndlQ0E0Y0hnZ2NtZGlZU2d3TENBd0xDQXdMQ0F1TURncExD'
    || 'QXdJRGh3ZUNBeU5IQjRJSEpuWW1Fb01Dd2dNQ3dnTUN3Z0xqQTJLVHN0TFhOb0xXaHZkbVZ5T2lBd0lEUndlQ0F4Tm5CNElISm5ZbUVvTUN3Z01Dd2dNQ3dn'
    || 'TGpFcExDQXdJREV5Y0hnZ016WndlQ0J5WjJKaEtEQXNJREFzSURBc0lDNHdOeWs3TFMxbFlYTmxPaUJqZFdKcFl5MWlaWHBwWlhJb0xqSXlMQ0F4TENBdU16'
    || 'WXNJREVwT3kwdGMybGtaV0poY2kxM09pQXlNelp3ZUgwcWUySnZlQzF6YVhwcGJtYzZZbTl5WkdWeUxXSnZlSDFvZEcxc0xHSnZaSGw3YldGeVoybHVPakE3'
    || 'Y0dGa1pHbHVaem93TzJKaFkydG5jbTkxYm1RNmRtRnlLQzB0WW1jcE8yTnZiRzl5T25aaGNpZ3RMWFJsZUhRcE8yWnZiblF0Wm1GdGFXeDVPaTFoY0hCc1pT'
    || 'MXplWE4wWlcwc1FteHBibXROWVdOVGVYTjBaVzFHYjI1MExGTmxaMjlsSUZWSkxFaGxiSFpsZEdsallTQk9aWFZsTEVGeWFXRnNMSE5oYm5NdGMyVnlhV1k3'
    || 'Wm05dWRDMXphWHBsT2pFMGNIZzdiR2x1WlMxb1pXbG5hSFE2TVM0MU95MTNaV0pyYVhRdFptOXVkQzF6Ylc5dmRHaHBibWM2WVc1MGFXRnNhV0Z6WldRN0xX'
    || 'MXZlaTF2YzNndFptOXVkQzF6Ylc5dmRHaHBibWM2WjNKaGVYTmpZV3hsZlM1aGNIQjdaR2x6Y0d4aGVUcG5jbWxrTzJkeWFXUXRkR1Z0Y0d4aGRHVXRZMjlz'
    || 'ZFcxdWN6cDJZWElvTFMxemFXUmxZbUZ5TFhjcElHMXBibTFoZUNnd0xERm1jaWs3WjJGd09qQTdiV2x1TFdobGFXZG9kRG94TURBbGZTNWhjSEF0TFc1dmJt'
    || 'RjJlMmR5YVdRdGRHVnRjR3hoZEdVdFkyOXNkVzF1Y3pwdGFXNXRZWGdvTUN3eFpuSXBmUzV6YVdSbGUzQnZjMmwwYVc5dU9uTjBhV05yZVR0MGIzQTZNRHRo'
    || 'YkdsbmJpMXpaV3htT25OMFlYSjBPM0JoWkdScGJtYzZNakJ3ZUNBeE5IQjRJREU0Y0hnN1ltOXlaR1Z5TFhKcFoyaDBPakZ3ZUNCemIyeHBaQ0IyWVhJb0xT'
    || 'MXNhVzVsS1R0aVlXTnJaM0p2ZFc1a09uWmhjaWd0TFhOMWNtWmhZMlVwTzIxcGJpMW9aV2xuYUhRNk1UQXdkbWg5TG5OcFpHVmZYMkp5WVc1a2UyUnBjM0Jz'
    || 'WVhrNlpteGxlRHRoYkdsbmJpMXBkR1Z0Y3pwalpXNTBaWEk3WjJGd09qbHdlRHR3WVdSa2FXNW5PakFnTm5CNElERTJjSGg5TG5OcFpHVmZYMkp5WVc1a0lI'
    || 'TjJaM3RtYkdWNE9tNXZibVY5TG5OcFpHVmZYM2R2Y21SdFlYSnJlMlp2Ym5RdGMybDZaVG94TTNCNE8yWnZiblF0ZDJWcFoyaDBPamN3TUR0c1pYUjBaWEl0'
    || 'YzNCaFkybHVaem90TGpBeFpXMDdZMjlzYjNJNmRtRnlLQzB0Ym1GMmVTazdiR2x1WlMxb1pXbG5hSFE2TVM0eE5YMHVjMmxrWlY5ZmMzVmllMlp2Ym5RdGMy'
    || 'bDZaVG94TVhCNE8yWnZiblF0ZDJWcFoyaDBPalV3TUR0amIyeHZjanAyWVhJb0xTMWthVzBwTzJ4bGRIUmxjaTF6Y0dGamFXNW5PaTR3TW1WdGZTNXVZWFo3'
    || 'WkdsemNHeGhlVHBtYkdWNE8yWnNaWGd0WkdseVpXTjBhVzl1T21OdmJIVnRianRuWVhBNk1uQjRmUzV1WVhaZlgybDBaVzE3WkdsemNHeGhlVHBtYkdWNE8y'
    || 'RnNhV2R1TFdsMFpXMXpPbVpzWlhndGMzUmhjblE3WjJGd09qbHdlRHR3WVdSa2FXNW5Pamh3ZUNBNWNIZzdZbTl5WkdWeUxYSmhaR2wxY3pvNWNIZzdZbTl5'
    || 'WkdWeU9qQTdZbUZqYTJkeWIzVnVaRHB1YjI1bE8zZHBaSFJvT2pFd01DVTdkR1Y0ZEMxaGJHbG5ianBzWldaME8yTjFjbk52Y2pwd2IybHVkR1Z5TzJOdmJH'
    || 'OXlPblpoY2lndExXMTFkR1ZrS1R0MGNtRnVjMmwwYVc5dU9tSmhZMnRuY205MWJtUWdMakUwY3lCMllYSW9MUzFsWVhObEtTeGpiMnh2Y2lBdU1UUnpJSFpo'
    || 'Y2lndExXVmhjMlVwTzJadmJuUTZhVzVvWlhKcGRIMHVibUYyWDE5cGRHVnRPbWh2ZG1WeWUySmhZMnRuY205MWJtUTZkbUZ5S0MwdGMzVnlabUZqWlMweUtU'
    || 'dGpiMnh2Y2pwMllYSW9MUzEwWlhoMEtYMHVibUYyWDE5cGRHVnRJSE4yWjN0bWJHVjRPbTV2Ym1VN2JXRnlaMmx1TFhSdmNEb3hjSGg5TG01aGRsOWZiR0Zp'
    || 'Wld4N1ptOXVkQzF6YVhwbE9qRXlMalZ3ZUR0bWIyNTBMWGRsYVdkb2REbzJNREE3WkdsemNHeGhlVHBpYkc5amF6dHNhVzVsTFdobGFXZG9kRG94TGpNMWZT'
    || 'NXVZWFpmWDJSbGMyTjdabTl1ZEMxemFYcGxPakV4Y0hnN1kyOXNiM0k2ZG1GeUtDMHRaR2x0S1R0a2FYTndiR0Y1T21Kc2IyTnJPMnhwYm1VdGFHVnBaMmgw'
    || 'T2pFdU0zMHVibUYyWDE5cGRHVnRMUzF2Ym50aVlXTnJaM0p2ZFc1a09uWmhjaWd0TFdGalkyVnVkQzEzWVhOb0tUdGpiMnh2Y2pwMllYSW9MUzFoWTJObGJu'
    || 'UXBmUzV1WVhaZlgybDBaVzB0TFc5dUlDNXVZWFpmWDJ4aFltVnNlMk52Ykc5eU9uWmhjaWd0TFdGalkyVnVkQ2w5TG01aGRsOWZhWFJsYlMwdGIyNGdMbTVo'
    || 'ZGw5ZlpHVnpZM3RqYjJ4dmNqcDJZWElvTFMxaFkyTmxiblFwTzI5d1lXTnBkSGs2TGpkOUxtNWhkbDlmWkc5MGUzZHBaSFJvT2pad2VEdG9aV2xuYUhRNk5u'
    || 'QjRPMkp2Y21SbGNpMXlZV1JwZFhNNk5UQWxPMjFoY21kcGJqbzFjSGdnTUNBd0lHRjFkRzg3Wm14bGVEcHViMjVsZlM1dVlYWmZYMlJ2ZEMwdFltRmtlMkpo'
    || 'WTJ0bmNtOTFibVE2ZG1GeUtDMHRZbUZrS1gwdWJtRjJYMTlrYjNRdExYZGhjbTU3WW1GamEyZHliM1Z1WkRwMllYSW9MUzEzWVhKdUtYMHVibUYyWDE5a2Iz'
    || 'UXRMV2x1Wm05N1ltRmphMmR5YjNWdVpEcDJZWElvTFMxemEza3BmUzV1WVhaZlgyZHliM1Z3ZTIxaGNtZHBiam94TlhCNElEQWdNM0I0TzNCaFpHUnBibWM2'
    || 'TUNBNWNIZzdabTl1ZEMxemFYcGxPakV4Y0hnN1ptOXVkQzEzWldsbmFIUTZOekF3TzNSbGVIUXRkSEpoYm5ObWIzSnRPblZ3Y0dWeVkyRnpaVHRzWlhSMFpY'
    || 'SXRjM0JoWTJsdVp6b3VNRFJsYlR0amIyeHZjanAyWVhJb0xTMXRkWFJsWkNrN2JHbHVaUzFvWldsbmFIUTZNUzR6ZlM1dVlYWmZYMmR5YjNWd09tWnBjbk4w'
    || 'TFdOb2FXeGtlMjFoY21kcGJpMTBiM0E2TVhCNGZTNXVZWFpmWDJsMFpXMHRMWE4xWW50d1lXUmthVzVuTFd4bFpuUTZNakp3ZUgwdWMybGtaVjlmWm05dmRI'
    || 'dHRZWEpuYVc0dGRHOXdPakU0Y0hnN2NHRmtaR2x1WnpveE1YQjRJRGh3ZUNBd08ySnZjbVJsY2kxMGIzQTZNWEI0SUhOdmJHbGtJSFpoY2lndExXeHBibVVw'
    || 'TzJadmJuUXRjMmw2WlRveE1YQjRPMk52Ykc5eU9uWmhjaWd0TFdScGJTazdiR2x1WlMxb1pXbG5hSFE2TVM0ME5YMHViV0ZwYm50d1lXUmthVzVuT2pJeWNI'
    || 'Z2dNalp3ZUNBek1IQjRPMjFwYmkxM2FXUjBhRG93ZlM1aGNIQmZYMmhsWVdSN1pHbHpjR3hoZVRwbWJHVjRPMkZzYVdkdUxXbDBaVzF6T21ac1pYZ3RjM1Jo'
    || 'Y25RN2FuVnpkR2xtZVMxamIyNTBaVzUwT25Od1lXTmxMV0psZEhkbFpXNDdaMkZ3T2pFNGNIZzdiV0Z5WjJsdUxXSnZkSFJ2YlRveE9IQjRPMlpzWlhndGQz'
    || 'SmhjRHAzY21Gd2ZTNWhjSEJmWDJobFlXUStLbnR0YVc0dGQybGtkR2c2TUR0dFlYZ3RkMmxrZEdnNk1UQXdKWDB1WVhCd1gxOW9aV0ZrY21sbmFIUjdiV2x1'
    || 'TFhkcFpIUm9PakE3YldGNExYZHBaSFJvT2pFd01DVTdaR2x6Y0d4aGVUcG1iR1Y0TzJGc2FXZHVMV2wwWlcxek9tWnNaWGd0YzNSaGNuUTdaMkZ3T2pFd2NI'
    || 'ZzdabXhsZUMxM2NtRndPbmR5WVhCOUxtRndjRjlmYUdWaFpDQm9NWHR0WVhKbmFXNDZNRHRtYjI1MExYTnBlbVU2TWpGd2VEdG1iMjUwTFhkbGFXZG9kRG8z'
    || 'TURBN2JHVjBkR1Z5TFhOd1lXTnBibWM2TFM0d01tVnRPMk52Ykc5eU9uWmhjaWd0TFc1aGRua3BPMnhwYm1VdGFHVnBaMmgwT2pFdU1uMHVZWEJ3WDE5emRX'
    || 'SjdiV0Z5WjJsdU9qVndlQ0F3SURBN1ptOXVkQzF6YVhwbE9qRXljSGc3WTI5c2IzSTZkbUZ5S0MwdGJYVjBaV1FwZlM1aGNIQmZYM04xWWlCamIyUmxlMkpo'
    || 'WTJ0bmNtOTFibVE2ZG1GeUtDMHRjM1Z5Wm1GalpTMHlLVHRpYjNKa1pYSTZNWEI0SUhOdmJHbGtJSFpoY2lndExXeHBibVVwTzNCaFpHUnBibWM2TVhCNElE'
    || 'WndlRHRpYjNKa1pYSXRjbUZrYVhWek9qVndlRHRtYjI1MExYTnBlbVU2TVRGd2VEdGpiMnh2Y2pwMllYSW9MUzF1WVhaNUtYMHVjR2hoYzJWN1pteGxlRHB1'
    || 'YjI1bE8yUnBjM0JzWVhrNlpteGxlRHRtYkdWNExXUnBjbVZqZEdsdmJqcGpiMngxYlc0N1lXeHBaMjR0YVhSbGJYTTZabXhsZUMxbGJtUTdaMkZ3T2pod2VE'
    || 'dHRZWGd0ZDJsa2RHZzZNVEF3SlgwdWNHaGhjMlZmWDNKaGFXeDdaR2x6Y0d4aGVUcHBibXhwYm1VdFpteGxlRHRoYkdsbmJpMXBkR1Z0Y3pwemRISmxkR05v'
    || 'TzJKdmNtUmxjam94Y0hnZ2MyOXNhV1FnZG1GeUtDMHRiR2x1WlNrN1ltOXlaR1Z5TFhKaFpHbDFjenAyWVhJb0xTMXlZV1JwZFhNcE8ySmhZMnRuY205MWJt'
    || 'UTZkbUZ5S0MwdGMzVnlabUZqWlNrN2IzWmxjbVpzYjNjNmFHbGtaR1Z1TzIxaGVDMTNhV1IwYURveE1EQWxmUzV3YUdGelpWOWZZblJ1ZXkxM1pXSnJhWFF0'
    || 'WVhCd1pXRnlZVzVqWlRwdWIyNWxPeTF0YjNvdFlYQndaV0Z5WVc1alpUcHViMjVsTzJGd2NHVmhjbUZ1WTJVNmJtOXVaVHRpWVdOclozSnZkVzVrT201dmJt'
    || 'VTdZbTl5WkdWeU9qQTdZbTl5WkdWeUxXeGxablE2TVhCNElITnZiR2xrSUhaaGNpZ3RMV3hwYm1VcE8yUnBjM0JzWVhrNlpteGxlRHRtYkdWNExXUnBjbVZq'
    || 'ZEdsdmJqcGpiMngxYlc0N1lXeHBaMjR0YVhSbGJYTTZabXhsZUMxemRHRnlkRHRuWVhBNk1uQjRPM0JoWkdScGJtYzZOM0I0SURFeWNIZzdZM1Z5YzI5eU9u'
    || 'QnZhVzUwWlhJN2RHVjRkQzFoYkdsbmJqcHNaV1owTzJadmJuUTZhVzVvWlhKcGREdGpiMnh2Y2pwMllYSW9MUzF0ZFhSbFpDazdiV2x1TFhkcFpIUm9PakI5'
    || 'TG5Cb1lYTmxYMTlpZEc0NlptbHljM1F0WTJocGJHUjdZbTl5WkdWeUxXeGxablE2TUgwdWNHaGhjMlZmWDJKMGJqcG9iM1psY250aVlXTnJaM0p2ZFc1a09u'
    || 'WmhjaWd0TFhOMWNtWmhZMlV0TWlsOUxuQm9ZWE5sWDE5aWRHNDZabTlqZFhNdGRtbHphV0pzWlh0dmRYUnNhVzVsT2pKd2VDQnpiMnhwWkNCMllYSW9MUzFo'
    || 'WTJObGJuUXBPMjkxZEd4cGJtVXRiMlptYzJWME9pMHljSGg5TG5Cb1lYTmxYMTlzWVdKbGJIdG1iMjUwTFhOcGVtVTZNVEZ3ZUR0bWIyNTBMWGRsYVdkb2RE'
    || 'bzJNREE3YkdWMGRHVnlMWE53WVdOcGJtYzZMakEwWlcwN2RHVjRkQzEwY21GdWMyWnZjbTA2ZFhCd1pYSmpZWE5sTzNkb2FYUmxMWE53WVdObE9tNXZkM0po'
    || 'Y0gwdWNHaGhjMlZmWDJacFozVnlaWHRtYjI1MExYTnBlbVU2TVRKd2VEdG1iMjUwTFhkbGFXZG9kRG8xTURBN2QyaHBkR1V0YzNCaFkyVTZibTl5YldGc08y'
    || 'OTJaWEptYkc5M0xYZHlZWEE2WVc1NWQyaGxjbVY5TG5Cb1lYTmxYMTl0YjI1bGVYdG1iMjUwTFhOcGVtVTZNVEZ3ZUR0amIyeHZjanAyWVhJb0xTMXRkWFJs'
    || 'WkNrN2QyaHBkR1V0YzNCaFkyVTZibTkzY21Gd2ZTNXdhR0Z6WlY5ZlluUnVMUzFqZFhKeVpXNTBlMkpoWTJ0bmNtOTFibVE2ZG1GeUtDMHRZV05qWlc1MExY'
    || 'ZGhjMmdwTzJOdmJHOXlPblpoY2lndExXNWhkbmtwZlM1d2FHRnpaVjlmWW5SdUxTMWpkWEp5Wlc1MElDNXdhR0Z6WlY5ZmJHRmlaV3g3WTI5c2IzSTZkbUZ5'
    || 'S0MwdFlXTmpaVzUwS1gwdWNHaGhjMlZmWDJKMGJpMHRZM1Z5Y21WdWRDQXVjR2hoYzJWZlgyWnBaM1Z5Wlh0amIyeHZjanAyWVhJb0xTMTBaWGgwS1R0bWIy'
    || 'NTBMWGRsYVdkb2REbzJNREI5TG5Cb1lYTmxYMTlpZEc0dExXUnZibVVnTG5Cb1lYTmxYMTlzWVdKbGJDd3VjR2hoYzJWZlgySjBiaTB0WVdobFlXUWdMbkJv'
    || 'WVhObFgxOXNZV0psYkN3dWNHaGhjMlZmWDJKMGJpMHRZV2hsWVdRZ0xuQm9ZWE5sWDE5bWFXZDFjbVY3WTI5c2IzSTZkbUZ5S0MwdGJYVjBaV1FwZlM1d2FH'
    || 'RnpaVjlmWW5SdUxtbHpMVzl3Wlc1N1ltRmphMmR5YjNWdVpEcDJZWElvTFMxemRYSm1ZV05sTFRNcGZTNXdhR0Z6WlY5ZlluUnVMUzFqZFhKeVpXNTBMbWx6'
    || 'TFc5d1pXNTdZbUZqYTJkeWIzVnVaRHAyWVhJb0xTMWhZMk5sYm5RdGQyRnphQ2w5TG5Cb1lYTmxYMTlrWlhSaGFXeDdiV0Y0TFhkcFpIUm9PalF6TUhCNE8z'
    || 'UmxlSFF0WVd4cFoyNDZiR1ZtZER0aVlXTnJaM0p2ZFc1a09uWmhjaWd0TFhOMWNtWmhZMlV0TWlrN1ltOXlaR1Z5T2pGd2VDQnpiMnhwWkNCMllYSW9MUzFz'
    || 'YVc1bEtUdGliM0prWlhJdGNtRmthWFZ6T25aaGNpZ3RMWEpoWkdsMWN5azdjR0ZrWkdsdVp6b3hNSEI0SURFeWNIaDlMbkJvWVhObFgxOWtaWFJoYVd3Z2NI'
    || 'dHRZWEpuYVc0Nk1DQXdJRFp3ZUR0bWIyNTBMWE5wZW1VNk1URXVOWEI0TzJ4cGJtVXRhR1ZwWjJoME9qRXVOWDB1Y0doaGMyVmZYMlJsZEdGcGJDQndPbXho'
    || 'YzNRdFkyaHBiR1I3YldGeVoybHVMV0p2ZEhSdmJUb3dmUzV3YUdGelpWOWZZbXgxY21KN1kyOXNiM0k2ZG1GeUtDMHRkR1Y0ZENsOUxuQm9ZWE5sWDE5aVlY'
    || 'TnBjM3RqYjJ4dmNqcDJZWElvTFMxdGRYUmxaQ2w5TG5Cb1lYTmxYMTlpWVhOcGN5QnpkSEp2Ym1kN1kyOXNiM0k2ZG1GeUtDMHRkR1Y0ZENrN1ptOXVkQzEz'
    || 'WldsbmFIUTZOakF3ZlM1d2FHRnpaVjlmZDJobGNtVjdZMjlzYjNJNmRtRnlLQzB0WVdOalpXNTBLVHRtYjI1MExYZGxhV2RvZERvMk1EQjlMbkJvWVhObFgx'
    || 'OW9iM2Q3WTI5c2IzSTZkbUZ5S0MwdGJYVjBaV1FwZlM1d2FHRnpaVjlmYUc5M0lHTnZaR1Y3WW1GamEyZHliM1Z1WkRwMllYSW9MUzF6ZFhKbVlXTmxLVHRp'
    || 'YjNKa1pYSTZNWEI0SUhOdmJHbGtJSFpoY2lndExXeHBibVVwTzNCaFpHUnBibWM2TVhCNElEWndlRHRpYjNKa1pYSXRjbUZrYVhWek9qVndlRHRtYjI1MExY'
    || 'TnBlbVU2TVRGd2VEdGpiMnh2Y2pwMllYSW9MUzF1WVhaNUtUdDNhR2wwWlMxemNHRmpaVHB1YjNkeVlYQjlRRzFsWkdsaEtHMWhlQzEzYVdSMGFEbzNNakJ3'
    || 'ZUNsN0xtRndjSHRuY21sa0xYUmxiWEJzWVhSbExXTnZiSFZ0Ym5NNmJXbHViV0Y0S0RBc01XWnlLWDB1YzJsa1pYdHdiM05wZEdsdmJqcHpkR0YwYVdNN2JX'
    || 'bHVMV2hsYVdkb2REb3dPM0JoWkdScGJtYzZNVEp3ZUR0aWIzSmtaWEl0Y21sbmFIUTZNRHRpYjNKa1pYSXRZbTkwZEc5dE9qRndlQ0J6YjJ4cFpDQjJZWElv'
    || 'TFMxc2FXNWxLWDB1YzJsa1pTQXVibUYyZTJac1pYZ3RaR2x5WldOMGFXOXVPbkp2ZHp0bWJHVjRMWGR5WVhBNmQzSmhjSDB1YzJsa1pTQXVibUYyWDE5cGRH'
    || 'VnRlM2RwWkhSb09tRjFkRzg3Wm14bGVEb3hJREVnTVRRd2NIaDlMbk5wWkdVZ0xtNWhkbDlmWjNKdmRYQjdabXhsZUMxaVlYTnBjem94TURBbGZTNXphV1Js'
    || 'WDE5bWIyOTBlMlJwYzNCc1lYazZibTl1WlgwdWJXRnBibnR3WVdSa2FXNW5PakUyY0hoOUxtRndjRjlmYUdWaFpIdG1iR1Y0TFdScGNtVmpkR2x2YmpwamIy'
    || 'eDFiVzU5TG5Cb1lYTmxlMkZzYVdkdUxXbDBaVzF6T21ac1pYZ3RjM1JoY25RN2QybGtkR2c2TVRBd0pYMHVjR2hoYzJWZlgzSmhhV3g3ZDJsa2RHZzZNVEF3'
    || 'SlgwdWNHaGhjMlZmWDJKMGJudG1iR1Y0T2pFZ01TQXdmWDB1WjNKcFpIdGthWE53YkdGNU9tZHlhV1E3WjJGd09qRTBjSGc3WjNKcFpDMTBaVzF3YkdGMFpT'
    || 'MWpiMngxYlc1ek9uSmxjR1ZoZENoaGRYUnZMV1pwZEN4dGFXNXRZWGdvYldsdUtETXpNSEI0TERFd01DVXBMREZtY2lrcE8yRnNhV2R1TFdsMFpXMXpPbk4w'
    || 'WVhKMGZTNWlZVzV1WlhKN1ltOXlaR1Z5TFhKaFpHbDFjem93SUhaaGNpZ3RMWEpoWkdsMWN5a2dkbUZ5S0MwdGNtRmthWFZ6S1NBd08zQmhaR1JwYm1jNk9I'
    || 'QjRJREV6Y0hnN2JXRnlaMmx1TFdKdmRIUnZiVG94TW5CNE8yWnZiblF0YzJsNlpUb3hNaTQxY0hnN1ptOXVkQzEzWldsbmFIUTZOVEF3TzJ4cGJtVXRhR1Zw'
    || 'WjJoME9qRXVORFU3WW05eVpHVnlMV3hsWm5RNk0zQjRJSE52Ykdsa0lIUnlZVzV6Y0dGeVpXNTBmUzVpWVc1dVpYSXRMWE5oYlhCc1pYdGlZV05yWjNKdmRX'
    || 'NWtPaU5tTlRsbE1HSXdaVHRpYjNKa1pYSXRiR1ZtZEMxamIyeHZjanAyWVhJb0xTMTNZWEp1S1R0amIyeHZjam9qT0dFMU5qQXdPMlp2Ym5RdGQyVnBaMmgw'
    || 'T2pZd01IMHVZbUZ1Ym1WeUxTMW1ZV2xzZTJKaFkydG5jbTkxYm1RNkkyVTRNREF4WXpCa08ySnZjbVJsY2kxc1pXWjBMV052Ykc5eU9uWmhjaWd0TFdKaFpD'
    || 'azdZMjlzYjNJNkkyRXpNREF4TkR0bWIyNTBMWGRsYVdkb2REbzJNREI5TG1KaGJtNWxjaTB0YVc1bWIzdGlZV05yWjNKdmRXNWtPaU13TURnMFpEUXdaRHRp'
    || 'YjNKa1pYSXRiR1ZtZEMxamIyeHZjanAyWVhJb0xTMWhZMk5sYm5RcE8yTnZiRzl5T2lNd01EVmhPVEY5TG1OaGNtUjdZbUZqYTJkeWIzVnVaRHAyWVhJb0xT'
    || 'MXpkWEptWVdObEtUdGliM0prWlhJNk1YQjRJSE52Ykdsa0lIWmhjaWd0TFd4cGJtVXBPMkp2Y21SbGNpMXlZV1JwZFhNNmRtRnlLQzB0Y21Ga2FYVnpLVHR3'
    || 'WVdSa2FXNW5PakUyY0hnZ01UaHdlQ0F4T0hCNE8ySnZlQzF6YUdGa2IzYzZkbUZ5S0MwdGMyZ3RZMkZ5WkNrN2RISmhibk5wZEdsdmJqcGliM2d0YzJoaFpH'
    || 'OTNJQzR5Y3lCMllYSW9MUzFsWVhObEtYMHVZMkZ5WkRwb2IzWmxjbnRpYjNndGMyaGhaRzkzT25aaGNpZ3RMWE5vTFcxa0tYMHVZMkZ5WkMwdGQybGtaWHRu'
    || 'Y21sa0xXTnZiSFZ0YmpveElDOGdMVEY5TG1OaGNtUmZYMmhsWVdSN2JXRnlaMmx1TFdKdmRIUnZiVG94TkhCNGZTNWpZWEprWDE5b1pXRmtJR2d5ZTIxaGNt'
    || 'ZHBiam93TzJadmJuUXRjMmw2WlRveE1YQjRPMlp2Ym5RdGQyVnBaMmgwT2pjd01EdDBaWGgwTFhSeVlXNXpabTl5YlRwMWNIQmxjbU5oYzJVN2JHVjBkR1Z5'
    || 'TFhOd1lXTnBibWM2TGpBMFpXMDdZMjlzYjNJNmRtRnlLQzB0WkdsdEtYMHVZMkZ5WkY5ZmFHbHVkSHR0WVhKbmFXNDZObkI0SURBZ01EdG1iMjUwTFhOcGVt'
    || 'VTZNVEp3ZUR0amIyeHZjanAyWVhJb0xTMXRkWFJsWkNrN2JHbHVaUzFvWldsbmFIUTZNUzQxZlM1dWIzUmxlMjFoY21kcGJqb3dJREFnT1hCNE8yWnZiblF0'
    || 'YzJsNlpUb3hNM0I0TzJ4cGJtVXRhR1ZwWjJoME9qRXVOanRqYjJ4dmNqcDJZWElvTFMxdGRYUmxaQ2w5TG01dmRHVTZiR0Z6ZEMxamFHbHNaSHR0WVhKbmFX'
    || 'NHRZbTkwZEc5dE9qQjlMbk4xWW50dFlYSm5hVzQ2TVRod2VDQXdJRGx3ZUR0bWIyNTBMWE5wZW1VNk1URndlRHRtYjI1MExYZGxhV2RvZERvM01EQTdkR1Y0'
    || 'ZEMxMGNtRnVjMlp2Y20wNmRYQndaWEpqWVhObE8yeGxkSFJsY2kxemNHRmphVzVuT2k0d05HVnRPMk52Ykc5eU9uWmhjaWd0TFdScGJTbDlMbk4wWVhRdGNt'
    || 'OTNlMlJwYzNCc1lYazZaM0pwWkR0bllYQTZNVEZ3ZUR0bmNtbGtMWFJsYlhCc1lYUmxMV052YkhWdGJuTTZjbVZ3WldGMEtHRjFkRzh0Wm1sMExHMXBibTFo'
    || 'ZUNneE5EaHdlQ3d4Wm5JcEtYMHVjM1JoZEh0aVlXTnJaM0p2ZFc1a09uWmhjaWd0TFhOMWNtWmhZMlVwTzJKdmNtUmxjam94Y0hnZ2MyOXNhV1FnZG1GeUtD'
    || 'MHRiR2x1WlNrN1ltOXlaR1Z5TFhKaFpHbDFjenAyWVhJb0xTMXlZV1JwZFhNcE8zQmhaR1JwYm1jNk1UTndlQ0F4TlhCNElERTBjSGg5TG5OMFlYUmZYMnho'
    || 'WW1Wc2UyWnZiblF0YzJsNlpUb3hNWEI0TzJadmJuUXRkMlZwWjJoME9qWXdNRHQwWlhoMExYUnlZVzV6Wm05eWJUcDFjSEJsY21OaGMyVTdiR1YwZEdWeUxY'
    || 'TndZV05wYm1jNkxqQTBaVzA3WTI5c2IzSTZkbUZ5S0MwdFpHbHRLWDB1YzNSaGRGOWZkbUZzZFdWN1ptOXVkQzF6YVhwbE9qTXdjSGc3Wm05dWRDMTNaV2xu'
    || 'YUhRNk56QXdPMjFoY21kcGJpMTBiM0E2TkhCNE8yeHBibVV0YUdWcFoyaDBPakV1TURnN2JHVjBkR1Z5TFhOd1lXTnBibWM2TFM0d01qVmxiVHRtYjI1MExY'
    || 'WmhjbWxoYm5RdGJuVnRaWEpwWXpwMFlXSjFiR0Z5TFc1MWJYTTdZMjlzYjNJNmRtRnlLQzB0Ym1GMmVTbDlMbk4wWVhSZlgzVnVhWFI3Wm05dWRDMXphWHBs'
    || 'T2pFMGNIZzdZMjlzYjNJNmRtRnlLQzB0WkdsdEtUdHRZWEpuYVc0dGJHVm1kRG96Y0hnN1ptOXVkQzEzWldsbmFIUTZOVEF3TzJ4bGRIUmxjaTF6Y0dGamFX'
    || 'NW5PakI5TG5OMFlYUmZYM04xWW50bWIyNTBMWE5wZW1VNk1URXVOWEI0TzJOdmJHOXlPblpoY2lndExXMTFkR1ZrS1R0dFlYSm5hVzR0ZEc5d09qUndlRHRz'
    || 'YVc1bExXaGxhV2RvZERveExqUjlMbk4wWVhRdExXZHZiMlFnTG5OMFlYUmZYM1poYkhWbGUyTnZiRzl5T25aaGNpZ3RMV2R2YjJRcGZTNXpkR0YwTFMxM1lY'
    || 'SnVJQzV6ZEdGMFgxOTJZV3gxWlh0amIyeHZjam9qWWpnM016QmhmUzV6ZEdGMExTMWlZV1FnTG5OMFlYUmZYM1poYkhWbGUyTnZiRzl5T25aaGNpZ3RMV0po'
    || 'WkNsOUxuTjBZWFF0TFdkdmIyUjdZbTl5WkdWeUxXTnZiRzl5T2lNeE5tRXpOR0UwWkR0aVlXTnJaM0p2ZFc1a09uWmhjaWd0TFdkdmIyUXRkMkZ6YUNsOUxu'
    || 'TjBZWFF0TFhkaGNtNTdZbTl5WkdWeUxXTnZiRzl5T2lObU5UbGxNR0kxTnp0aVlXTnJaM0p2ZFc1a09uWmhjaWd0TFhkaGNtNHRkMkZ6YUNsOUxuTjBZWFF0'
    || 'TFdKaFpIdGliM0prWlhJdFkyOXNiM0k2STJVNE1EQXhZelEzTzJKaFkydG5jbTkxYm1RNmRtRnlLQzB0WW1Ga0xYZGhjMmdwZlM1MFlXSnNaUzEzY21Gd2Uy'
    || 'OTJaWEptYkc5M0xYZzZZWFYwYnp0dFlYSm5hVzR0ZEc5d09qRXljSGc3WW1GamEyZHliM1Z1WkRwc2FXNWxZWEl0WjNKaFpHbGxiblFvZEc4Z2NtbG5hSFFz'
    || 'ZG1GeUtDMHRjM1Z5Wm1GalpTa3NjbWRpWVNneU5UVXNNalUxTERJMU5Td3dLU2tnYkdWbWRDQXZJREl3Y0hnZ01UQXdKU0J1YnkxeVpYQmxZWFFnYkc5allX'
    || 'd3NiR2x1WldGeUxXZHlZV1JwWlc1MEtIUnZJR3hsWm5Rc2RtRnlLQzB0YzNWeVptRmpaU2tzY21kaVlTZ3lOVFVzTWpVMUxESTFOU3d3S1NrZ2NtbG5hSFFn'
    || 'THlBeU1IQjRJREV3TUNVZ2JtOHRjbVZ3WldGMElHeHZZMkZzTEd4cGJtVmhjaTFuY21Ga2FXVnVkQ2gwYnlCeWFXZG9kQ3dqTVRFeE1URXhNV0VzSXpFeE1U'
    || 'QXBJR3hsWm5RZ0x5QXhNWEI0SURFd01DVWdibTh0Y21Wd1pXRjBJSE5qY205c2JDeHNhVzVsWVhJdFozSmhaR2xsYm5Rb2RHOGdiR1ZtZEN3ak1URXhNVEV4'
    || 'TVdFc0l6RXhNVEFwSUhKcFoyaDBJQzhnTVRGd2VDQXhNREFsSUc1dkxYSmxjR1ZoZENCelkzSnZiR3g5ZEdGaWJHVjdkMmxrZEdnNk1UQXdKVHRpYjNKa1pY'
    || 'SXRZMjlzYkdGd2MyVTZZMjlzYkdGd2MyVTdabTl1ZEMxemFYcGxPakV5TGpWd2VIMTBhR1ZoWkNCMGFIdDBaWGgwTFdGc2FXZHVPbXhsWm5RN1ptOXVkQzF6'
    || 'YVhwbE9qRXhjSGc3Wm05dWRDMTNaV2xuYUhRNk56QXdPM1JsZUhRdGRISmhibk5tYjNKdE9uVndjR1Z5WTJGelpUdHNaWFIwWlhJdGMzQmhZMmx1WnpvdU1E'
    || 'UmxiVHRqYjJ4dmNqcDJZWElvTFMxa2FXMHBPM0JoWkdScGJtYzZOM0I0SURFd2NIZzdZbTl5WkdWeUxXSnZkSFJ2YlRveGNIZ2djMjlzYVdRZ2RtRnlLQzB0'
    || 'YkdsdVpTazdZbUZqYTJkeWIzVnVaRHAyWVhJb0xTMXpkWEptWVdObExUSXBPM2RvYVhSbExYTndZV05sT201dmQzSmhjRHR3YjNOcGRHbHZianB6ZEdsamEz'
    || 'azdkRzl3T2pCOWRHaGxZV1FnZEdnNlptbHljM1F0WTJocGJHUjdZbTl5WkdWeUxYUnZjQzFzWldaMExYSmhaR2wxY3pvM2NIaDlkR2hsWVdRZ2RHZzZiR0Z6'
    || 'ZEMxamFHbHNaSHRpYjNKa1pYSXRkRzl3TFhKcFoyaDBMWEpoWkdsMWN6bzNjSGg5ZEdKdlpIa2dkR1I3Y0dGa1pHbHVaem80Y0hnZ01UQndlRHRpYjNKa1pY'
    || 'SXRZbTkwZEc5dE9qRndlQ0J6YjJ4cFpDQjJZWElvTFMxc2FXNWxLVHRqYjJ4dmNqcDJZWElvTFMxMFpYaDBLVHQyWlhKMGFXTmhiQzFoYkdsbmJqcDBiM0I5'
    || 'ZEdKdlpIa2dkSEk2YkdGemRDMWphR2xzWkNCMFpIdGliM0prWlhJdFltOTBkRzl0T2pCOWRHSnZaSGtnZEhJNmFHOTJaWElnZEdSN1ltRmphMmR5YjNWdVpE'
    || 'cDJZWElvTFMxemRYSm1ZV05sTFRJcGZYUmtMbklzZEdndWNudDBaWGgwTFdGc2FXZHVPbkpwWjJoME8yWnZiblF0ZG1GeWFXRnVkQzF1ZFcxbGNtbGpPblJo'
    || 'WW5Wc1lYSXRiblZ0YzMwdWJuVnNiSHRqYjJ4dmNqcDJZWElvTFMxa2FXMHBPMlp2Ym5RdGMzUjViR1U2YVhSaGJHbGpmUzUwWVdKc1pTMXRiM0psZTIxaGNt'
    || 'ZHBiam81Y0hnZ01DQXdPMlp2Ym5RdGMybDZaVG94TVM0MWNIZzdZMjlzYjNJNmRtRnlLQzB0WkdsdEtYMHVZbUZ5YzN0a2FYTndiR0Y1T21ac1pYZzdabXhs'
    || 'ZUMxa2FYSmxZM1JwYjI0NlkyOXNkVzF1TzJkaGNEbzRjSGc3YldGeVoybHVMWFJ2Y0RvMGNIaDlMbUpoY250a2FYTndiR0Y1T21keWFXUTdaM0pwWkMxMFpX'
    || 'MXdiR0YwWlMxamIyeDFiVzV6T20xcGJtMWhlQ2d4TkRCd2VDd3pNQ1VwSURGbWNpQTNPSEI0TzJGc2FXZHVMV2wwWlcxek9tTmxiblJsY2p0bllYQTZNVEZ3'
    || 'ZUR0bWIyNTBMWE5wZW1VNk1USndlSDB1WW1GeVgxOXNZV0psYkh0amIyeHZjanAyWVhJb0xTMXRkWFJsWkNrN1ptOXVkQzEzWldsbmFIUTZOVEF3TzJ4cGJt'
    || 'VXRhR1ZwWjJoME9qRXVNenR2ZG1WeVpteHZkeTEzY21Gd09tRnVlWGRvWlhKbE8zZHZjbVF0WW5KbFlXczZZbkpsWVdzdGQyOXlaRHRrYVhOd2JHRjVPaTEz'
    || 'WldKcmFYUXRZbTk0T3kxM1pXSnJhWFF0WW05NExXOXlhV1Z1ZERwMlpYSjBhV05oYkRzdGQyVmlhMmwwTFd4cGJtVXRZMnhoYlhBNk1qdHZkbVZ5Wm14dmR6'
    || 'cG9hV1JrWlc1OUxtSmhjbDlmZEhKaFkydDdZbUZqYTJkeWIzVnVaRHAyWVhJb0xTMXpkWEptWVdObExUTXBPMkp2Y21SbGNpMXlZV1JwZFhNNk5YQjRPMmhs'
    || 'YVdkb2REb3hPSEI0TzI5MlpYSm1iRzkzT21ocFpHUmxibjB1WW1GeVgxOW1hV3hzZTJobGFXZG9kRG94TURBbE8ySmhZMnRuY205MWJtUTZkbUZ5S0MwdFlX'
    || 'TmpaVzUwS1R0aWIzSmtaWEl0Y21Ga2FYVnpPalZ3ZUgwdVltRnlYMTltYVd4c0xTMW5iMjlrZTJKaFkydG5jbTkxYm1RNmRtRnlLQzB0WjI5dlpDbDlMbUpo'
    || 'Y2w5ZlptbHNiQzB0ZDJGeWJudGlZV05yWjNKdmRXNWtPblpoY2lndExYZGhjbTRwZlM1aVlYSmZYMlpwYkd3dExXSmhaSHRpWVdOclozSnZkVzVrT25aaGNp'
    || 'Z3RMV0poWkNsOUxtSmhjbDlmZG1Gc2RXVjdkR1Y0ZEMxaGJHbG5ianB5YVdkb2REdG1iMjUwTFhaaGNtbGhiblF0Ym5WdFpYSnBZenAwWVdKMWJHRnlMVzUx'
    || 'YlhNN1kyOXNiM0k2ZG1GeUtDMHRkR1Y0ZENrN1ptOXVkQzEzWldsbmFIUTZOakF3ZlM1dFpYUmxjbnR3YjNOcGRHbHZianB5Wld4aGRHbDJaVHRpWVdOcloz'
    || 'SnZkVzVrT25aaGNpZ3RMWE4xY21aaFkyVXRNeWs3WW05eVpHVnlMWEpoWkdsMWN6bzFjSGc3YUdWcFoyaDBPakl3Y0hnN2IzWmxjbVpzYjNjNmFHbGtaR1Z1'
    || 'TzIxcGJpMTNhV1IwYURvNU5uQjRmUzV0WlhSbGNsOWZabWxzYkh0b1pXbG5hSFE2TVRBd0pUdGlZV05yWjNKdmRXNWtPblpoY2lndExXRmpZMlZ1ZENsOUxt'
    || 'MWxkR1Z5WDE5bWFXeHNMUzFuYjI5a2UySmhZMnRuY205MWJtUTZkbUZ5S0MwdFoyOXZaQ2w5TG0xbGRHVnlYMTltYVd4c0xTMTNZWEp1ZTJKaFkydG5jbTkx'
    || 'Ym1RNmRtRnlLQzB0ZDJGeWJpbDlMbTFsZEdWeVgxOW1hV3hzTFMxaVlXUjdZbUZqYTJkeWIzVnVaRHAyWVhJb0xTMWlZV1FwZlM1dFpYUmxjbDlmZEdWNGRI'
    || 'dHdiM05wZEdsdmJqcGhZbk52YkhWMFpUdDBiM0E2TUR0eWFXZG9kRG93TzJKdmRIUnZiVG93TzJ4bFpuUTZNRHRrYVhOd2JHRjVPbVpzWlhnN1lXeHBaMjR0'
    || 'YVhSbGJYTTZZMlZ1ZEdWeU8ycDFjM1JwWm5rdFkyOXVkR1Z1ZERwalpXNTBaWEk3Wm05dWRDMXphWHBsT2pFeGNIZzdabTl1ZEMxM1pXbG5hSFE2TnpBd08y'
    || 'TnZiRzl5T25aaGNpZ3RMVzVoZG5rcE8yWnZiblF0ZG1GeWFXRnVkQzF1ZFcxbGNtbGpPblJoWW5Wc1lYSXRiblZ0YzMwdWJXVjBaWEl0Y205M2UyUnBjM0Jz'
    || 'WVhrNlpteGxlRHRtYkdWNExXUnBjbVZqZEdsdmJqcGpiMngxYlc0N1oyRndPalp3ZUR0dFlYSm5hVzQ2TkhCNElEQWdNVFJ3ZUgwdWJXVjBaWEl0Y205M1gx'
    || 'OW9aV0ZrZTJScGMzQnNZWGs2Wm14bGVEdGhiR2xuYmkxcGRHVnRjenBpWVhObGJHbHVaVHRxZFhOMGFXWjVMV052Ym5SbGJuUTZjM0JoWTJVdFltVjBkMlZs'
    || 'Ymp0bllYQTZNVEp3ZUR0bWIyNTBMWE5wZW1VNk1USndlSDB1YldWMFpYSXRjbTkzWDE5c1lXSmxiSHRqYjJ4dmNqcDJZWElvTFMxdGRYUmxaQ2s3Wm05dWRD'
    || 'MTNaV2xuYUhRNk5UQXdmUzV0WlhSbGNpMXliM2RmWDNaaGJIVmxlMk52Ykc5eU9uWmhjaWd0TFhSbGVIUXBPMlp2Ym5RdGQyVnBaMmgwT2pZd01EdG1iMjUw'
    || 'TFhaaGNtbGhiblF0Ym5WdFpYSnBZenAwWVdKMWJHRnlMVzUxYlhNN2QyaHBkR1V0YzNCaFkyVTZibTkzY21Gd2ZTNXRaWFJsY2kxeWIzZGZYMjltZTJOdmJH'
    || 'OXlPblpoY2lndExXMTFkR1ZrS1R0bWIyNTBMWGRsYVdkb2REbzBNREE3YldGeVoybHVMV3hsWm5RNk4zQjRPMlp2Ym5RdGMybDZaVG94TVhCNE8yeGxkSFJs'
    || 'Y2kxemNHRmphVzVuT2k0d01XVnRmUzV0WlhSbGNpMXliM2NnTG0xbGRHVnllMmhsYVdkb2REb3hNSEI0TzJKdmNtUmxjaTF5WVdScGRYTTZNM0I0TzIxcGJp'
    || 'MTNhV1IwYURvd2ZTNXRaWFJsY2kwdFkyVnNiSHRvWldsbmFIUTZNVGR3ZUR0aWIzSmtaWEl0Y21Ga2FYVnpPak53ZUR0dGFXNHRkMmxrZEdnNk56aHdlSDB1'
    || 'YjNac2UyUnBjM0JzWVhrNlozSnBaRHRuY21sa0xYUmxiWEJzWVhSbExXTnZiSFZ0Ym5NNmJXbHViV0Y0S0RBc01XWnlLU0JoZFhSdk8yZGhjRG95TW5CNE8y'
    || 'RnNhV2R1TFdsMFpXMXpPbU5sYm5SbGNqdHRZWEpuYVc0dGRHOXdPalJ3ZUgwdWIzWnNYMTltYVdkMWNtVjdaR2x6Y0d4aGVUcG1iR1Y0TzJac1pYZ3RaR2x5'
    || 'WldOMGFXOXVPbU52YkhWdGJqdG5ZWEE2TVRad2VEdHRhVzR0ZDJsa2RHZzZNSDB1YjNac1gxOXphV1JsZTIxcGJpMTNhV1IwYURvd2ZTNXZkbXhmWDJobFlX'
    || 'UjdaR2x6Y0d4aGVUcG1iR1Y0TzJGc2FXZHVMV2wwWlcxek9tSmhjMlZzYVc1bE8ycDFjM1JwWm5rdFkyOXVkR1Z1ZERwemNHRmpaUzFpWlhSM1pXVnVPMmRo'
    || 'Y0RveE1uQjRPMlp2Ym5RdGMybDZaVG94TW5CNE8yMWhjbWRwYmkxaWIzUjBiMjA2TlhCNGZTNXZkbXhmWDI1aGJXVjdZMjlzYjNJNmRtRnlLQzB0YlhWMFpX'
    || 'UXBPMlp2Ym5RdGQyVnBaMmgwT2pVd01IMHViM1pzWDE5dWUyTnZiRzl5T25aaGNpZ3RMVzVoZG5rcE8yWnZiblF0ZDJWcFoyaDBPamN3TUR0bWIyNTBMWFpo'
    || 'Y21saGJuUXRiblZ0WlhKcFl6cDBZV0oxYkdGeUxXNTFiWE03Wm05dWRDMXphWHBsT2pFMWNIaDlMbTkyYkY5ZmRISmhZMnQ3YUdWcFoyaDBPakl5Y0hnN1lt'
    || 'RmphMmR5YjNWdVpEcDJZWElvTFMxemRYSm1ZV05sTFRNcE8ySnZjbVJsY2kxeVlXUnBkWE02TTNCNE8yOTJaWEptYkc5M09taHBaR1JsYmp0dGFXNHRkMmxr'
    || 'ZEdnNk0zQjRmUzV2ZG14ZlgySnZkR2g3YUdWcFoyaDBPakV3TUNVN1ltRmphMmR5YjNWdVpEcDJZWElvTFMxaFkyTmxiblFwTzJKdmNtUmxjaTF5WVdScGRY'
    || 'TTZNM0I0SURBZ01DQXpjSGg5TG05MmJGOWZjbUYwWlh0dFlYSm5hVzR0ZEc5d09qVndlRHRtYjI1MExYTnBlbVU2TVRGd2VEdGpiMnh2Y2pwMllYSW9MUzF0'
    || 'ZFhSbFpDazdabTl1ZEMxMllYSnBZVzUwTFc1MWJXVnlhV002ZEdGaWRXeGhjaTF1ZFcxemZTNXZkbXhmWDIxcFpIdG1iR1Y0T201dmJtVTdkR1Y0ZEMxaGJH'
    || 'bG5ianB5YVdkb2REdHdZV1JrYVc1bkxXeGxablE2TWpCd2VEdGliM0prWlhJdGJHVm1kRG94Y0hnZ2MyOXNhV1FnZG1GeUtDMHRiR2x1WlNsOUxtOTJiRjlm'
    || 'Yldsa0xXNTdabTl1ZEMxemFYcGxPak13Y0hnN1ptOXVkQzEzWldsbmFIUTZOekF3TzJ4cGJtVXRhR1ZwWjJoME9qRXVNRFU3WTI5c2IzSTZkbUZ5S0MwdFlX'
    || 'TmpaVzUwS1R0c1pYUjBaWEl0YzNCaFkybHVaem90TGpBeU5XVnRPMlp2Ym5RdGRtRnlhV0Z1ZEMxdWRXMWxjbWxqT25SaFluVnNZWEl0Ym5WdGMzMHViM1pz'
    || 'WDE5dGFXUXRiR0ZpZTJadmJuUXRjMmw2WlRveE1YQjRPMk52Ykc5eU9uWmhjaWd0TFcxMWRHVmtLVHR0WVhKbmFXNHRkRzl3T2pWd2VEdHNhVzVsTFdobGFX'
    || 'ZG9kRG94TGpNMWZVQnRaV1JwWVNodFlYZ3RkMmxrZEdnNk9UQXdjSGdwZXk1dmRteDdaM0pwWkMxMFpXMXdiR0YwWlMxamIyeDFiVzV6T20xcGJtMWhlQ2d3'
    || 'TERGbWNpbDlMbTkyYkY5ZmJXbGtlM1JsZUhRdFlXeHBaMjQ2YkdWbWREdHdZV1JrYVc1bk9qRXljSGdnTUNBd08ySnZjbVJsY2kxc1pXWjBPakE3WW05eVpH'
    || 'VnlMWFJ2Y0RveGNIZ2djMjlzYVdRZ2RtRnlLQzB0YkdsdVpTbDlmUzV3YVd4c2UyUnBjM0JzWVhrNmFXNXNhVzVsTFdKc2IyTnJPMlp2Ym5RdGMybDZaVG94'
    || 'TVhCNE8yWnZiblF0ZDJWcFoyaDBPamN3TUR0d1lXUmthVzVuT2pKd2VDQTRjSGc3WW05eVpHVnlMWEpoWkdsMWN6bzVPVGx3ZUR0aWIzSmtaWEk2TVhCNElI'
    || 'TnZiR2xrSUhaaGNpZ3RMV3hwYm1VdE1pazdZMjlzYjNJNmRtRnlLQzB0YlhWMFpXUXBPMnhsZEhSbGNpMXpjR0ZqYVc1bk9pNHdNbVZ0TzNkb2FYUmxMWE53'
    || 'WVdObE9tNXZkM0poY0gwdWNHbHNiQzB0WjI5dlpIdGpiMnh2Y2pwMllYSW9MUzFuYjI5a0tUdGliM0prWlhJdFkyOXNiM0k2SXpFMllUTTBZVFkyTzJKaFky'
    || 'dG5jbTkxYm1RNmRtRnlLQzB0WjI5dlpDMTNZWE5vS1gwdWNHbHNiQzB0ZDJGeWJudGpiMnh2Y2pvallUZzJZVEExTzJKdmNtUmxjaTFqYjJ4dmNqb2paalU1'
    || 'WlRCaU56TTdZbUZqYTJkeWIzVnVaRHAyWVhJb0xTMTNZWEp1TFhkaGMyZ3BmUzV3YVd4c0xTMWlZV1I3WTI5c2IzSTZkbUZ5S0MwdFltRmtLVHRpYjNKa1pY'
    || 'SXRZMjlzYjNJNkkyVTRNREF4WXpZeE8ySmhZMnRuY205MWJtUTZkbUZ5S0MwdFltRmtMWGRoYzJncGZTNXdZV2x5ZTJKdmNtUmxjam94Y0hnZ2MyOXNhV1Fn'
    || 'ZG1GeUtDMHRiR2x1WlNrN1ltOXlaR1Z5TFhKaFpHbDFjem80Y0hnN2NHRmtaR2x1WnpveE1YQjRJREV6Y0hnZ01USndlRHRpWVdOclozSnZkVzVrT25aaGNp'
    || 'Z3RMWE4xY21aaFkyVXBPMjFoY21kcGJpMWliM1IwYjIwNk1UQndlSDB1Y0dGcGNsOWZhR1ZoWkh0a2FYTndiR0Y1T21ac1pYZzdZV3hwWjI0dGFYUmxiWE02'
    || 'WTJWdWRHVnlPMmRoY0RveE1IQjRPMlpzWlhndGQzSmhjRHAzY21Gd08yMWhjbWRwYmkxaWIzUjBiMjA2T1hCNGZTNXdZV2x5WDE5cFpITjdabTl1ZEMxemFY'
    || 'cGxPakV4TGpWd2VEdGpiMnh2Y2pwMllYSW9MUzF0ZFhSbFpDazdabTl1ZEMxM1pXbG5hSFE2TlRBd08yOTJaWEptYkc5M0xYZHlZWEE2WVc1NWQyaGxjbVY5'
    || 'TG5CaGFYSmZYM1p6ZTJOdmJHOXlPblpoY2lndExXUnBiU2s3Y0dGa1pHbHVaem93SUROd2VIMHVjR0ZwY2w5ZmNtOTNjM3RrYVhOd2JHRjVPbVpzWlhnN1pt'
    || 'eGxlQzFrYVhKbFkzUnBiMjQ2WTI5c2RXMXVPMmRoY0RveGNIaDlMbkJoYVhKZlgzSnZkM3RrYVhOd2JHRjVPbWR5YVdRN1ozSnBaQzEwWlcxd2JHRjBaUzFq'
    || 'YjJ4MWJXNXpPall5Y0hnZ2JXbHViV0Y0S0RBc01XWnlLU0F4T0hCNElHMXBibTFoZUNnd0xERm1jaWs3WjJGd09qbHdlRHRoYkdsbmJpMXBkR1Z0Y3pwaVlY'
    || 'TmxiR2x1WlR0bWIyNTBMWE5wZW1VNk1USndlRHR3WVdSa2FXNW5PalJ3ZUNBMmNIZzdZbTl5WkdWeUxYSmhaR2wxY3pvMGNIaDlMbkJoYVhKZlgyeGhZbVZz'
    || 'ZTJadmJuUXRjMmw2WlRveE1YQjRPMlp2Ym5RdGQyVnBaMmgwT2pZd01EdDBaWGgwTFhSeVlXNXpabTl5YlRwMWNIQmxjbU5oYzJVN2JHVjBkR1Z5TFhOd1lX'
    || 'TnBibWM2TGpBMFpXMDdZMjlzYjNJNmRtRnlLQzB0WkdsdEtYMHVjR0ZwY2w5ZmRtRnNlMjkyWlhKbWJHOTNMWGR5WVhBNllXNTVkMmhsY21VN1kyOXNiM0k2'
    || 'ZG1GeUtDMHRkR1Y0ZENsOUxuQmhhWEpmWDIxaGNtdDdkR1Y0ZEMxaGJHbG5ianBqWlc1MFpYSTdabTl1ZEMxM1pXbG5hSFE2TnpBd08yWnZiblF0ZG1GeWFX'
    || 'RnVkQzF1ZFcxbGNtbGpPblJoWW5Wc1lYSXRiblZ0YzMwdWNHRnBjbDlmY205M0xTMWthV1ptZTJKaFkydG5jbTkxYm1RNmRtRnlLQzB0ZDJGeWJpMTNZWE5v'
    || 'S1gwdWNHRnBjbDlmY205M0xTMWthV1ptSUM1d1lXbHlYMTl0WVhKcmUyTnZiRzl5T2lOaE9EWmhNRFY5TG5CaGFYSmZYM0p2ZHkwdGMyRnRaU0F1Y0dGcGNs'
    || 'OWZiV0Z5YTN0amIyeHZjanAyWVhJb0xTMWthVzBwZlM1dWIzUmxjM3R0WVhKbmFXNDZNRHR3WVdSa2FXNW5MV3hsWm5RNk1UbHdlSDB1Ym05MFpYTWdiR2w3'
    || 'YldGeVoybHVPakFnTUNBeE1IQjRPMnhwYm1VdGFHVnBaMmgwT2pFdU5qdGpiMnh2Y2pwMllYSW9MUzF0ZFhSbFpDazdabTl1ZEMxemFYcGxPakV5TGpWd2VI'
    || 'MHVibTkwWlhNZ2JHa2djM1J5YjI1bmUyTnZiRzl5T25aaGNpZ3RMWFJsZUhRcE8yWnZiblF0ZDJWcFoyaDBPall3TUgwdWJtOTBaWE1nYkdrNmJHRnpkQzFq'
    || 'YUdsc1pIdHRZWEpuYVc0dFltOTBkRzl0T2pCOUxtNXZkR1Z6SUdOdlpHVjdZbUZqYTJkeWIzVnVaRHAyWVhJb0xTMXpkWEptWVdObExUSXBPMkp2Y21SbGNq'
    || 'b3hjSGdnYzI5c2FXUWdkbUZ5S0MwdGJHbHVaU2s3Y0dGa1pHbHVaem94Y0hnZ05YQjRPMkp2Y21SbGNpMXlZV1JwZFhNNk5IQjRPMlp2Ym5RdGMybDZaVG94'
    || 'TVM0MWNIZzdZMjlzYjNJNmRtRnlLQzB0Ym1GMmVTbDlMbkJoYm1Wc0xXVnljbTl5ZTJKaFkydG5jbTkxYm1RNmRtRnlLQzB0WW1Ga0xYZGhjMmdwTzJKdmNt'
    || 'Umxjam94Y0hnZ2MyOXNhV1FnY21kaVlTZ3lNeklzTUN3eU9Dd3VNeklwTzJKdmNtUmxjaTF5WVdScGRYTTZkbUZ5S0MwdGNtRmthWFZ6S1R0d1lXUmthVzVu'
    || 'T2pFeGNIZ2dNVE53ZUR0bWIyNTBMWE5wZW1VNk1USXVOWEI0ZlM1d1lXNWxiQzFsY25KdmNpQnpkSEp2Ym1kN1pHbHpjR3hoZVRwaWJHOWphenRqYjJ4dmNq'
    || 'cDJZWElvTFMxaVlXUXBPMjFoY21kcGJpMWliM1IwYjIwNk5YQjRmUzV3WVc1bGJDMWxjbkp2Y2lCamIyUmxlMk52Ykc5eU9pTTRaakF3TVRRN2QyOXlaQzFp'
    || 'Y21WaGF6cGljbVZoYXkxM2IzSmtPM2RvYVhSbExYTndZV05sT25CeVpTMTNjbUZ3TzJadmJuUXRjMmw2WlRveE1TNDFjSGg5TG5CaGJtVnNMV1Z0Y0hSNUxD'
    || 'NXdZVzVsYkMxdGFYTnphVzVuZTJOdmJHOXlPblpoY2lndExXMTFkR1ZrS1R0bWIyNTBMWE5wZW1VNk1USXVOWEI0TzIxaGNtZHBiam93ZlM1d1lXNWxiQzEw'
    || 'Y25WdVkzdGlZV05yWjNKdmRXNWtPblpoY2lndExYZGhjbTR0ZDJGemFDazdZbTl5WkdWeU9qRndlQ0J6YjJ4cFpDQnlaMkpoS0RJME5Td3hOVGdzTVRFc0xq'
    || 'UXBPMkp2Y21SbGNpMXlZV1JwZFhNNk5IQjRPM0JoWkdScGJtYzZPSEI0SURFeGNIZzdiV0Z5WjJsdU9qQWdNQ0F4TVhCNE8yWnZiblF0YzJsNlpUb3hNUzQx'
    || 'Y0hnN1kyOXNiM0k2SXpoaE5UWXdNRHRzYVc1bExXaGxhV2RvZERveExqVjlMbU5oZG1WaGRIdGlZV05yWjNKdmRXNWtPblpoY2lndExYZGhjbTR0ZDJGemFD'
    || 'azdZbTl5WkdWeU9qRndlQ0J6YjJ4cFpDQnlaMkpoS0RJME5Td3hOVGdzTVRFc0xqUXBPMkp2Y21SbGNpMXlZV1JwZFhNNmRtRnlLQzB0Y21Ga2FYVnpLVHR3'
    || 'WVdSa2FXNW5PakV4Y0hnZ01UTndlRHR0WVhKbmFXNDZNVEp3ZUNBd0lEQTdabTl1ZEMxemFYcGxPakV5TGpWd2VIMHVZMkYyWldGMElITjBjbTl1WjN0a2FY'
    || 'TndiR0Y1T21Kc2IyTnJPMk52Ykc5eU9pTTRZVFUyTURBN2JXRnlaMmx1TFdKdmRIUnZiVG8xY0hnN1ptOXVkQzEzWldsbmFIUTZOekF3ZlM1allYWmxZWFFn'
    || 'Y0h0dFlYSm5hVzQ2TUR0amIyeHZjanAyWVhJb0xTMXRkWFJsWkNrN2JHbHVaUzFvWldsbmFIUTZNUzQyZlM1d1lXNWxiQzF1YjNSaWRXbHNkSHRpWVdOcloz'
    || 'SnZkVzVrT25aaGNpZ3RMV0ZqWTJWdWRDMTNZWE5vS1R0aWIzSmtaWEk2TVhCNElITnZiR2xrSUhKblltRW9NQ3d4TXpJc01qRXlMQzR6S1R0aWIzSmtaWEl0'
    || 'Y21Ga2FYVnpPblpoY2lndExYSmhaR2wxY3lrN2NHRmtaR2x1WnpveE1uQjRJREUwY0hnN1ptOXVkQzF6YVhwbE9qRXlMalZ3ZUgwdWNHRnVaV3d0Ym05MFlu'
    || 'VnBiSFFnYzNSeWIyNW5lMlJwYzNCc1lYazZZbXh2WTJzN1kyOXNiM0k2ZG1GeUtDMHRZV05qWlc1MEtUdHRZWEpuYVc0dFltOTBkRzl0T2pWd2VIMHVjR0Z1'
    || 'Wld3dGJtOTBZblZwYkhRZ2NIdHRZWEpuYVc0Nk1EdGpiMnh2Y2pwMllYSW9MUzF0ZFhSbFpDazdiR2x1WlMxb1pXbG5hSFE2TVM0MmZTNXdZVzVsYkMxdWIz'
    || 'UmlkV2xzZEY5ZllXeDBlMjFoY21kcGJpMTBiM0E2T0hCNElXbHRjRzl5ZEdGdWREdG1iMjUwTFhOcGVtVTZNVEV1TlhCNE8yOXdZV05wZEhrNkxqbDlMbTV2'
    || 'ZEhsbGRIdGlZV05yWjNKdmRXNWtPblpoY2lndExYTjFjbVpoWTJVdE1pazdZbTl5WkdWeU9qRndlQ0J6YjJ4cFpDQjJZWElvTFMxc2FXNWxLVHRpYjNKa1pY'
    || 'SXRjbUZrYVhWek9uWmhjaWd0TFhKaFpHbDFjeWs3Y0dGa1pHbHVaem94TlhCNElERTNjSGdnTVRad2VEdG1iMjUwTFhOcGVtVTZNVEl1TlhCNGZTNXViM1I1'
    || 'WlhRK2MzUnliMjVuZTJScGMzQnNZWGs2WW14dlkyczdZMjlzYjNJNmRtRnlLQzB0Ym1GMmVTazdabTl1ZEMxemFYcGxPakV6TGpWd2VEdHRZWEpuYVc0dFlt'
    || 'OTBkRzl0T2pkd2VIMHVibTkwZVdWMElIQjdiV0Z5WjJsdU9qQTdZMjlzYjNJNmRtRnlLQzB0YlhWMFpXUXBPMnhwYm1VdGFHVnBaMmgwT2pFdU5uMHVibTkw'
    || 'ZVdWMElHTnZaR1Y3WW1GamEyZHliM1Z1WkRwMllYSW9MUzF6ZFhKbVlXTmxLVHRpYjNKa1pYSTZNWEI0SUhOdmJHbGtJSFpoY2lndExXeHBibVV0TWlrN2NH'
    || 'RmtaR2x1WnpveGNIZ2dOWEI0TzJKdmNtUmxjaTF5WVdScGRYTTZOSEI0TzJadmJuUXRjMmw2WlRveE1TNDFjSGc3WTI5c2IzSTZkbUZ5S0MwdGJtRjJlU2s3'
    || 'ZDJocGRHVXRjM0JoWTJVNmJtOTNjbUZ3ZlM1dWIzUjVaWFJmWDNkb1lYUjdiV0Z5WjJsdUxYUnZjRG94TTNCNElXbHRjRzl5ZEdGdWREdGpiMnh2Y2pwMllY'
    || 'SW9MUzEwWlhoMEtTRnBiWEJ2Y25SaGJuUTdabTl1ZEMxM1pXbG5hSFE2TlRBd2ZTNXViM1I1WlhSZlgzUnBaWEp6ZTIxaGNtZHBiam81Y0hnZ01DQXdPM0Jo'
    || 'WkdScGJtYzZNRHRzYVhOMExYTjBlV3hsT201dmJtVTdaR2x6Y0d4aGVUcG1iR1Y0TzJac1pYZ3RaR2x5WldOMGFXOXVPbU52YkhWdGJqdG5ZWEE2T0hCNGZT'
    || 'NXViM1I1WlhSZlgzUnBaWEp6SUd4cGUyUnBjM0JzWVhrNlozSnBaRHRuY21sa0xYUmxiWEJzWVhSbExXTnZiSFZ0Ym5NNk9UWndlQ0J0YVc1dFlYZ29NQ3d4'
    || 'Wm5JcE8yZGhjRG94TW5CNE8yRnNhV2R1TFdsMFpXMXpPbUpoYzJWc2FXNWxPM0JoWkdScGJtY3RiR1ZtZERveE1YQjRPMkp2Y21SbGNpMXNaV1owT2pKd2VD'
    || 'QnpiMnhwWkNCMllYSW9MUzFzYVc1bExUSXBmUzV1YjNSNVpYUmZYM1JwWlhKN1ptOXVkQzF6YVhwbE9qRXhjSGc3Wm05dWRDMTNaV2xuYUhRNk56QXdPMnhs'
    || 'ZEhSbGNpMXpjR0ZqYVc1bk9pNHdOR1Z0TzNSbGVIUXRkSEpoYm5ObWIzSnRPblZ3Y0dWeVkyRnpaVHRqYjJ4dmNqcDJZWElvTFMxa2FXMHBmUzV1YjNSNVpY'
    || 'UmZYM1JwWlhJdFpHVnpZM3RqYjJ4dmNqcDJZWElvTFMxdGRYUmxaQ2s3YkdsdVpTMW9aV2xuYUhRNk1TNDFPMlp2Ym5RdGMybDZaVG94TW5CNGZTNXViM1I1'
    || 'WlhSZlgyWnZiM1I3YldGeVoybHVMWFJ2Y0RveE0zQjRJV2x0Y0c5eWRHRnVkRHR3WVdSa2FXNW5MWFJ2Y0RveE1YQjRPMkp2Y21SbGNpMTBiM0E2TVhCNElI'
    || 'TnZiR2xrSUhaaGNpZ3RMV3hwYm1VcE8yWnZiblF0YzJsNlpUb3hNUzQxY0hoOUxtWmhkR0ZzZTJKaFkydG5jbTkxYm1RNmRtRnlLQzB0WW1Ga0xYZGhjMmdw'
    || 'TzJKdmNtUmxjam94Y0hnZ2MyOXNhV1FnY21kaVlTZ3lNeklzTUN3eU9Dd3VNellwTzJKdmNtUmxjaTF5WVdScGRYTTZkbUZ5S0MwdGNtRmthWFZ6TFd4bktU'
    || 'dHdZV1JrYVc1bk9qSXdjSGdnTWpKd2VEdHRZWEpuYVc0Nk1qUndlSDB1Wm1GMFlXd2dhREY3YldGeVoybHVPakFnTUNBNWNIZzdabTl1ZEMxemFYcGxPakUz'
    || 'Y0hnN1kyOXNiM0k2ZG1GeUtDMHRZbUZrS1gwdVptRjBZV3dnWTI5a1pYdGpiMnh2Y2pvak9HWXdNREUwTzNkb2FYUmxMWE53WVdObE9uQnlaUzEzY21Gd08y'
    || 'WnZiblF0YzJsNlpUb3hNbkI0ZlM1a2IyNTFkSHRrYVhOd2JHRjVPbVpzWlhnN1lXeHBaMjR0YVhSbGJYTTZZMlZ1ZEdWeU8yZGhjRG94T0hCNGZTNWtiMjUx'
    || 'ZEY5ZlptbG5lMlpzWlhnNmJtOXVaWDB1Wkc5dWRYUmZYMnRsZVh0a2FYTndiR0Y1T21ac1pYZzdabXhsZUMxa2FYSmxZM1JwYjI0NlkyOXNkVzF1TzJkaGNE'
    || 'bzNjSGc3YldsdUxYZHBaSFJvT2pCOUxtUnZiblYwWDE5eWIzZDdaR2x6Y0d4aGVUcG1iR1Y0TzJGc2FXZHVMV2wwWlcxek9tTmxiblJsY2p0bllYQTZPSEI0'
    || 'TzJadmJuUXRjMmw2WlRveE1uQjRmUzVrYjI1MWRGOWZjM2Q3ZDJsa2RHZzZPWEI0TzJobGFXZG9kRG81Y0hnN1ltOXlaR1Z5TFhKaFpHbDFjem96Y0hnN1pt'
    || 'eGxlRHB1YjI1bGZTNWtiMjUxZEY5ZmJHRmllMk52Ykc5eU9uWmhjaWd0TFcxMWRHVmtLVHR2ZG1WeVpteHZkenBvYVdSa1pXNDdkR1Y0ZEMxdmRtVnlabXh2'
    || 'ZHpwbGJHeHBjSE5wY3p0M2FHbDBaUzF6Y0dGalpUcHViM2R5WVhCOUxtUnZiblYwWDE5MllXeDdZMjlzYjNJNmRtRnlLQzB0ZEdWNGRDazdabTl1ZEMxM1pX'
    || 'bG5hSFE2TmpBd08yWnZiblF0ZG1GeWFXRnVkQzF1ZFcxbGNtbGpPblJoWW5Wc1lYSXRiblZ0Y3p0dFlYSm5hVzR0YkdWbWREcGhkWFJ2ZlM1a2IyNTFkRjlm'
    || 'WTJWdWRHVnllMlp2Ym5RdGRtRnlhV0Z1ZEMxdWRXMWxjbWxqT25SaFluVnNZWEl0Ym5WdGMzMHVjM0JoY210N1pHbHpjR3hoZVRwaWJHOWphMzB1YzNCaGNt'
    || 'dGZYMnhwYm1WN1ptbHNiRHB1YjI1bE8zTjBjbTlyWlRwMllYSW9MUzFoWTJObGJuUXBPM04wY205clpTMTNhV1IwYURveU8zTjBjbTlyWlMxc2FXNWxZMkZ3'
    || 'T25KdmRXNWtPM04wY205clpTMXNhVzVsYW05cGJqcHliM1Z1WkgwdWMzQmhjbXRmWDJGeVpXRjdabWxzYkRwMllYSW9MUzFoWTJObGJuUXRkMkZ6YUNrN2Mz'
    || 'UnliMnRsT201dmJtVjlMbk53WVhKclgxOWtiM1I3Wm1sc2JEcDJZWElvTFMxaFkyTmxiblFwZlM1bWJHOTNlMlJwYzNCc1lYazZabXhsZUR0aGJHbG5iaTFw'
    || 'ZEdWdGN6cHpkSEpsZEdOb08yMWhjbWRwYmkxMGIzQTZObkI0ZlM1bWJHOTNYMTlpYjNoN1pteGxlRG94SURFZ01EdHRhVzR0ZDJsa2RHZzZNRHQwWlhoMExX'
    || 'RnNhV2R1T21ObGJuUmxjanRpWVdOclozSnZkVzVrT25aaGNpZ3RMWE4xY21aaFkyVXBPMkp2Y21SbGNqb3hjSGdnYzI5c2FXUWdkbUZ5S0MwdGJHbHVaUzB5'
    || 'S1R0aWIzSmtaWEl0Y21Ga2FYVnpPakV3Y0hnN2NHRmtaR2x1WnpveE1YQjRJREV3Y0hoOUxtWnNiM2RmWDJKdmVDMHRiMjU3WW1GamEyZHliM1Z1WkRwMllY'
    || 'SW9MUzFoWTJObGJuUXRkMkZ6YUNrN1ltOXlaR1Z5TFdOdmJHOXlPblpoY2lndExXRmpZMlZ1ZENsOUxtWnNiM2RmWDJ4aFludG1iMjUwTFhOcGVtVTZNVEV1'
    || 'TlhCNE8yWnZiblF0ZDJWcFoyaDBPall3TUR0amIyeHZjanAyWVhJb0xTMXVZWFo1S1R0c2FXNWxMV2hsYVdkb2REb3hMak03YjNabGNtWnNiM2N0ZDNKaGNE'
    || 'cGhibmwzYUdWeVpYMHVabXh2ZDE5ZmMzVmllMlp2Ym5RdGMybDZaVG94TVhCNE8yTnZiRzl5T25aaGNpZ3RMV1JwYlNrN2JXRnlaMmx1TFhSdmNEb3pjSGc3'
    || 'YkdsdVpTMW9aV2xuYUhRNk1TNHpmUzVtYkc5M1gxOXNhVzVyZTJac1pYZzZNQ0F3SURJMGNIZzdZV3hwWjI0dGMyVnNaanBqWlc1MFpYSTdhR1ZwWjJoME9q'
    || 'SndlRHRpWVdOclozSnZkVzVrT25aaGNpZ3RMV3hwYm1VdE1pazdZbTl5WkdWeUxYSmhaR2wxY3pveWNIaDlMbVpzYjNkZlgyeHBibXN0TFc5dWUySmhZMnRu'
    || 'Y205MWJtUXRhVzFoWjJVNmJHbHVaV0Z5TFdkeVlXUnBaVzUwS0Rrd1pHVm5MSFpoY2lndExYTnJlU2tnTUNBME5TVXNkSEpoYm5Od1lYSmxiblFnTkRVbElE'
    || 'RXdNQ1VwTzJKaFkydG5jbTkxYm1RdGMybDZaVG94TTNCNElESndlRHRpWVdOclozSnZkVzVrTFhKbGNHVmhkRHB5WlhCbFlYUXRlRHRpWVdOclozSnZkVzVr'
    || 'TFdOdmJHOXlPblJ5WVc1emNHRnlaVzUwZlM1aFkzUmZYM1JwWlhKN2JXRnlaMmx1T2pFMmNIZ2dNQ0F5Y0hnN1ptOXVkQzF6YVhwbE9qRXhjSGc3Wm05dWRD'
    || 'MTNaV2xuYUhRNk56QXdPM1JsZUhRdGRISmhibk5tYjNKdE9uVndjR1Z5WTJGelpUdHNaWFIwWlhJdGMzQmhZMmx1WnpvdU1EUmxiVHRqYjJ4dmNqcDJZWElv'
    || 'TFMxdGRYUmxaQ2w5TG1GamRGOWZkR2xsY2kxa1pYTmplMjFoY21kcGJqb3dJREFnTVRCd2VEdG1iMjUwTFhOcGVtVTZNVEp3ZUR0amIyeHZjanAyWVhJb0xT'
    || 'MXRkWFJsWkNrN2JHbHVaUzFvWldsbmFIUTZNUzQxZlM1aFkzUmZYMmR5YVdSN1pHbHpjR3hoZVRwbmNtbGtPMmRoY0RveE1IQjRPMmR5YVdRdGRHVnRjR3ho'
    || 'ZEdVdFkyOXNkVzF1Y3pweVpYQmxZWFFvWVhWMGJ5MW1hWFFzYldsdWJXRjRLREkwTUhCNExERm1jaWtwTzIxaGNtZHBiaTFpYjNSMGIyMDZNVFJ3ZUgwdVlX'
    || 'TjBYMTlqWVhKa2UySmhZMnRuY205MWJtUTZkbUZ5S0MwdGMzVnlabUZqWlMweUtUdGliM0prWlhJNk1YQjRJSE52Ykdsa0lIWmhjaWd0TFd4cGJtVXBPMkp2'
    || 'Y21SbGNpMXlZV1JwZFhNNmRtRnlLQzB0Y21Ga2FYVnpLVHR3WVdSa2FXNW5PakV5Y0hnZ01UUndlSDB1WVdOMFgxOWpiMlJsZTJadmJuUXRjMmw2WlRveE1Y'
    || 'QjRPMlp2Ym5RdGQyVnBaMmgwT2pjd01EdDBaWGgwTFhSeVlXNXpabTl5YlRwMWNIQmxjbU5oYzJVN2JHVjBkR1Z5TFhOd1lXTnBibWM2TGpBMFpXMDdZMjlz'
    || 'YjNJNmRtRnlLQzB0WVdOalpXNTBLVHR0WVhKbmFXNHRZbTkwZEc5dE9qTndlSDB1WVdOMFgxOXNZV0psYkh0bWIyNTBMWE5wZW1VNk1UTndlRHRtYjI1MExY'
    || 'ZGxhV2RvZERvMk1EQTdZMjlzYjNJNmRtRnlLQzB0Ym1GMmVTazdiR2x1WlMxb1pXbG5hSFE2TVM0emZTNWhZM1JmWDJWbVptVmpkSHRtYjI1MExYTnBlbVU2'
    || 'TVRKd2VEdGpiMnh2Y2pwMllYSW9MUzF0ZFhSbFpDazdiV0Z5WjJsdUxYUnZjRG8wY0hnN2JHbHVaUzFvWldsbmFIUTZNUzQwTlgwdVlXTjBYMTl0WlhSaGUy'
    || 'UnBjM0JzWVhrNlpteGxlRHRtYkdWNExYZHlZWEE2ZDNKaGNEdG5ZWEE2Tm5CNElERXljSGc3YldGeVoybHVMWFJ2Y0RvNGNIZzdabTl1ZEMxemFYcGxPakV4'
    || 'Y0hnN1kyOXNiM0k2ZG1GeUtDMHRiWFYwWldRcGZTNWhZM1JmWDNWdVpHOTdZMjlzYjNJNmRtRnlLQzB0WjI5dlpDazdabTl1ZEMxM1pXbG5hSFE2TmpBd2ZT'
    || 'NWhZM1JmWDI1dmRXNWtiM3RqYjJ4dmNqcDJZWElvTFMxa2FXMHBmUzVoWTNSZlgzSjFibk43Wm05dWRDMXphWHBsT2pFeGNIZzdZMjlzYjNJNmRtRnlLQzB0'
    || 'YlhWMFpXUXBPMjFoY21kcGJpMTBiM0E2Tm5CNE8yWnZiblF0ZDJWcFoyaDBPalV3TUgwdVlXTjBYMTltYjI5MGUyMWhjbWRwYmpveE5IQjRJREFnTUR0bWIy'
    || 'NTBMWE5wZW1VNk1USndlRHRqYjJ4dmNqcDJZWElvTFMxdGRYUmxaQ2s3YkdsdVpTMW9aV2xuYUhRNk1TNDFOVHRpYjNKa1pYSXRkRzl3T2pGd2VDQnpiMnhw'
    || 'WkNCMllYSW9MUzFzYVc1bEtUdHdZV1JrYVc1bkxYUnZjRG94TW5CNGZTNXlkbnR2Y0dGamFYUjVPakE3ZEhKaGJuTm1iM0p0T25SeVlXNXpiR0YwWlZrb04z'
    || 'QjRLVHRoYm1sdFlYUnBiMjQ2Y25acGJpQXVOVEp6SUhaaGNpZ3RMV1ZoYzJVcElHWnZjbmRoY21SemZVQnJaWGxtY21GdFpYTWdjblpwYm50MGIzdHZjR0Zq'
    || 'YVhSNU9qRTdkSEpoYm5ObWIzSnRPbTV2Ym1WOWZVQnRaV1JwWVNod2NtVm1aWEp6TFhKbFpIVmpaV1F0Ylc5MGFXOXVPbkpsWkhWalpTbDdLbnRoYm1sdFlY'
    || 'UnBiMjQ2Ym05dVpTRnBiWEJ2Y25SaGJuUTdkSEpoYm5OcGRHbHZianB1YjI1bElXbHRjRzl5ZEdGdWRIMHVjblo3YjNCaFkybDBlVG94TzNSeVlXNXpabTl5'
    || 'YlRwdWIyNWxmWDB1WVhCd1gxOW9aV0ZrY21sbmFIUjdabXhsZURwdWIyNWxPMlJwYzNCc1lYazZabXhsZUR0bWJHVjRMV1JwY21WamRHbHZianBqYjJ4MWJX'
    || 'NDdZV3hwWjI0dGFYUmxiWE02Wm14bGVDMWxibVE3WjJGd09qaHdlSDB1Y0c5akxXTm9hWEI3WkdsemNHeGhlVHBwYm14cGJtVXRabXhsZUR0aGJHbG5iaTFw'
    || 'ZEdWdGN6cGlZWE5sYkdsdVpUdG5ZWEE2TjNCNE8zQmhaR1JwYm1jNk5uQjRJREV4Y0hnN1ltOXlaR1Z5TFhKaFpHbDFjenAyWVhJb0xTMXlZV1JwZFhNcE8y'
    || 'SnZjbVJsY2pveGNIZ2djMjlzYVdRZ2RtRnlLQzB0YkdsdVpTazdZbUZqYTJkeWIzVnVaRHAyWVhJb0xTMXpkWEptWVdObEtUdG1iMjUwT21sdWFHVnlhWFE3'
    || 'WTNWeWMyOXlPbkJ2YVc1MFpYSTdkMmhwZEdVdGMzQmhZMlU2Ym05M2NtRndPM1J5WVc1emFYUnBiMjQ2WW1GamEyZHliM1Z1WkNBdU1USnpJR1ZoYzJVc1lt'
    || 'OXlaR1Z5TFdOdmJHOXlJQzR4TW5NZ1pXRnpaWDB1Y0c5akxXTm9hWEE2YUc5MlpYSjdZbUZqYTJkeWIzVnVaRHAyWVhJb0xTMXpkWEptWVdObExUSXBPMkp2'
    || 'Y21SbGNpMWpiMnh2Y2pwMllYSW9MUzFzYVc1bExUSXBmUzV3YjJNdFkyaHBjQzB0YzNSaGRHbGplMk4xY25OdmNqcGtaV1poZFd4MGZTNXdiMk10WTJocGND'
    || 'MHRjM1JoZEdsak9taHZkbVZ5ZTJKaFkydG5jbTkxYm1RNmRtRnlLQzB0YzNWeVptRmpaU2s3WW05eVpHVnlMV052Ykc5eU9uWmhjaWd0TFd4cGJtVXBmUzV3'
    || 'YjJNdFkyaHBjRHBtYjJOMWN5MTJhWE5wWW14bGUyOTFkR3hwYm1VNk1uQjRJSE52Ykdsa0lIWmhjaWd0TFdGalkyVnVkQ2s3YjNWMGJHbHVaUzF2Wm1aelpY'
    || 'UTZNbkI0ZlM1d2IyTXRZMmhwY0Y5ZmJuVnRlMlp2Ym5RdGMybDZaVG94TlhCNE8yWnZiblF0ZDJWcFoyaDBPamN3TUR0bWIyNTBMWFpoY21saGJuUXRiblZ0'
    || 'WlhKcFl6cDBZV0oxYkdGeUxXNTFiWE03YkdWMGRHVnlMWE53WVdOcGJtYzZMUzR3TVdWdGZTNXdiMk10WTJocGNGOWZkMjl5Wkh0bWIyNTBMWE5wZW1VNk1U'
    || 'RndlRHRtYjI1MExYZGxhV2RvZERvMk1EQTdkR1Y0ZEMxMGNtRnVjMlp2Y20wNmRYQndaWEpqWVhObE8yeGxkSFJsY2kxemNHRmphVzVuT2k0d05HVnRPMk52'
    || 'Ykc5eU9uWmhjaWd0TFcxMWRHVmtLWDB1Y0c5akxXTm9hWEJmWDJac1lXZDdabTl1ZEMxemFYcGxPakV4Y0hnN1ptOXVkQzEzWldsbmFIUTZOakF3TzNSbGVI'
    || 'UXRkSEpoYm5ObWIzSnRPblZ3Y0dWeVkyRnpaVHRzWlhSMFpYSXRjM0JoWTJsdVp6b3VNRFJsYlR0d1lXUmthVzVuTFd4bFpuUTZOM0I0TzIxaGNtZHBiaTFz'
    || 'WldaME9qRndlRHRpYjNKa1pYSXRiR1ZtZERveGNIZ2djMjlzYVdRZ2RtRnlLQzB0YkdsdVpTazdZMjlzYjNJNmRtRnlLQzB0YlhWMFpXUXBmUzV3YjJNdFky'
    || 'aHBjQzB0WjI5dlpIdGliM0prWlhJdFkyOXNiM0k2SXpFMllUTTBZVFU1TzJKaFkydG5jbTkxYm1RNmRtRnlLQzB0WjI5dlpDMTNZWE5vS1gwdWNHOWpMV05v'
    || 'YVhBdExXZHZiMlFnTG5Cdll5MWphR2x3WDE5dWRXMTdZMjlzYjNJNmRtRnlLQzB0WjI5dlpDbDlMbkJ2WXkxamFHbHdMUzEzWVhKdWUySnZjbVJsY2kxamIy'
    || 'eHZjam9qWmpVNVpUQmlOalk3WW1GamEyZHliM1Z1WkRwMllYSW9MUzEzWVhKdUxYZGhjMmdwZlM1d2IyTXRZMmhwY0MwdGQyRnliaUF1Y0c5akxXTm9hWEJm'
    || 'WDI1MWJYdGpiMnh2Y2pvallURTJNakEzZlM1d2IyTXRZMmhwY0MwdFltRmtlMkp2Y21SbGNpMWpiMnh2Y2pvalpUZ3dNREZqTlRrN1ltRmphMmR5YjNWdVpE'
    || 'cDJZWElvTFMxaVlXUXRkMkZ6YUNsOUxuQnZZeTFqYUdsd0xTMWlZV1FnTG5Cdll5MWphR2x3WDE5dWRXMTdZMjlzYjNJNmRtRnlLQzB0WW1Ga0tYMHVjRzlq'
    || 'TFdOb2FYQXRMV2xrYkdVZ0xuQnZZeTFqYUdsd1gxOXVkVzE3WTI5c2IzSTZkbUZ5S0MwdGJYVjBaV1FwZlM1dVlYWmZYMkpoWkdkbGUyWnNaWGc2Ym05dVpU'
    || 'dHRZWEpuYVc0dGJHVm1kRHBoZFhSdk8zQmhaR1JwYm1jNk1YQjRJRFp3ZUR0aWIzSmtaWEl0Y21Ga2FYVnpPakl3Y0hnN1ptOXVkQzF6YVhwbE9qRXhjSGc3'
    || 'Wm05dWRDMTNaV2xuYUhRNk56QXdPMlp2Ym5RdGRtRnlhV0Z1ZEMxdWRXMWxjbWxqT25SaFluVnNZWEl0Ym5WdGN6dGliM0prWlhJNk1YQjRJSE52Ykdsa0lI'
    || 'WmhjaWd0TFd4cGJtVXBPMkpoWTJ0bmNtOTFibVE2ZG1GeUtDMHRjM1Z5Wm1GalpTMHlLVHRqYjJ4dmNqcDJZWElvTFMxdGRYUmxaQ2w5TG01aGRsOWZZbUZr'
    || 'WjJVdExXZHZiMlI3WTI5c2IzSTZkbUZ5S0MwdFoyOXZaQ2s3WW05eVpHVnlMV052Ykc5eU9pTXhObUV6TkdFMU9UdGlZV05yWjNKdmRXNWtPblpoY2lndExX'
    || 'ZHZiMlF0ZDJGemFDbDlMbTVoZGw5ZlltRmtaMlV0TFhkaGNtNTdZMjlzYjNJNkkyRXhOakl3Tnp0aWIzSmtaWEl0WTI5c2IzSTZJMlkxT1dVd1lqWTJPMkpo'
    || 'WTJ0bmNtOTFibVE2ZG1GeUtDMHRkMkZ5YmkxM1lYTm9LWDB1Ym1GMlgxOWlZV1JuWlMwdFltRmtlMk52Ykc5eU9uWmhjaWd0TFdKaFpDazdZbTl5WkdWeUxX'
    || 'TnZiRzl5T2lObE9EQXdNV00xT1R0aVlXTnJaM0p2ZFc1a09uWmhjaWd0TFdKaFpDMTNZWE5vS1gwdWJtRjJYMTlpWVdSblpTMHRhV1JzWlh0amIyeHZjanAy'
    || 'WVhJb0xTMXRkWFJsWkNsOUxtNWhkbDlmWW1Ga1oyVXJMbTVoZGw5ZlpHOTBlMjFoY21kcGJpMXNaV1owT2pad2VIMHVjRzlqZTJScGMzQnNZWGs2Wm14bGVE'
    || 'dG1iR1Y0TFdScGNtVmpkR2x2YmpwamIyeDFiVzQ3WjJGd09qRXljSGg5TG5CdlkxOWZkbVZ5WkdsamRIdGliM0prWlhJNk1uQjRJSE52Ykdsa0lIWmhjaWd0'
    || 'TFd4cGJtVXBPMkp2Y21SbGNpMXlZV1JwZFhNNmRtRnlLQzB0Y21Ga2FYVnpLVHRpWVdOclozSnZkVzVrT25aaGNpZ3RMWE4xY21aaFkyVXBPM0JoWkdScGJt'
    || 'YzZNVFZ3ZUNBeE4zQjRmUzV3YjJOZlgzWmxjbVJwWTNRdExXZHZiMlI3WW05eVpHVnlMV052Ykc5eU9pTXhObUV6TkdFM016dGlZV05yWjNKdmRXNWtPblpo'
    || 'Y2lndExXZHZiMlF0ZDJGemFDbDlMbkJ2WTE5ZmRtVnlaR2xqZEMwdGQyRnlibnRpYjNKa1pYSXRZMjlzYjNJNkkyWTFPV1V3WWpjek8ySmhZMnRuY205MWJt'
    || 'UTZkbUZ5S0MwdGQyRnliaTEzWVhOb0tYMHVjRzlqWDE5MlpYSmthV04wTFMxaVlXUjdZbTl5WkdWeUxXTnZiRzl5T2lObE9EQXdNV00xT1R0aVlXTnJaM0p2'
    || 'ZFc1a09uWmhjaWd0TFdKaFpDMTNZWE5vS1gwdWNHOWpYMTkyWlhKa2FXTjBMUzFwWkd4bGUySnZjbVJsY2kxamIyeHZjanAyWVhJb0xTMXNhVzVsTFRJcGZT'
    || 'NXdiMk5mWDJobFlXUnNhVzVsZTJadmJuUXRjMmw2WlRvek1IQjRPMlp2Ym5RdGQyVnBaMmgwT2pjd01EdHNaWFIwWlhJdGMzQmhZMmx1WnpvdExqQXlOV1Z0'
    || 'TzJadmJuUXRkbUZ5YVdGdWRDMXVkVzFsY21sak9uUmhZblZzWVhJdGJuVnRjenRqYjJ4dmNqcDJZWElvTFMxdVlYWjVLVHRzYVc1bExXaGxhV2RvZERveExq'
    || 'RjlMbkJ2WTE5ZmNtVmhaSHR0WVhKbmFXNDZObkI0SURBZ01EdG1iMjUwTFhOcGVtVTZNVEl1TlhCNE8yTnZiRzl5T25aaGNpZ3RMVzExZEdWa0tUdHNhVzVs'
    || 'TFdobGFXZG9kRG94TGpWOUxuQnZZMTlmZEdGc2JIbDdaR2x6Y0d4aGVUcG1iR1Y0TzJac1pYZ3RkM0poY0RwM2NtRndPMmRoY0RveE5IQjRPMjFoY21kcGJp'
    || 'MTBiM0E2TVRKd2VIMHVjRzlqWDE5MGFXTnJlMlp2Ym5RdGMybDZaVG94TVhCNE8yWnZiblF0ZDJWcFoyaDBPall3TUR0MFpYaDBMWFJ5WVc1elptOXliVHAx'
    || 'Y0hCbGNtTmhjMlU3YkdWMGRHVnlMWE53WVdOcGJtYzZMakEwWlcwN1kyOXNiM0k2ZG1GeUtDMHRiWFYwWldRcGZTNXdiMk5mWDNScFkyc2dZbnRtYjI1MExY'
    || 'TnBlbVU2TVROd2VEdG1iMjUwTFhkbGFXZG9kRG8zTURBN1ptOXVkQzEyWVhKcFlXNTBMVzUxYldWeWFXTTZkR0ZpZFd4aGNpMXVkVzF6TzIxaGNtZHBiaTF5'
    || 'YVdkb2REb3pjSGg5TG5CdlkxOWZkR2xqYXkwdGJXVjBJR0o3WTI5c2IzSTZkbUZ5S0MwdFoyOXZaQ2w5TG5CdlkxOWZkR2xqYXkwdGJtOTBiV1YwSUdKN1ky'
    || 'OXNiM0k2ZG1GeUtDMHRZbUZrS1gwdWNHOWpYMTkwYVdOckxTMXdaVzVrYVc1bklHSjdZMjlzYjNJNmRtRnlLQzB0YlhWMFpXUXBmUzV3YjJOZlgzUnBZMnN0'
    || 'TFc1aElHSjdZMjlzYjNJNmRtRnlLQzB0WkdsdEtYMHVjRzlqTFhKdmQzdGthWE53YkdGNU9tWnNaWGc3WjJGd09qRXljSGc3Y0dGa1pHbHVaem94TkhCNElE'
    || 'RTJjSGc3WW05eVpHVnlPakZ3ZUNCemIyeHBaQ0IyWVhJb0xTMXNhVzVsS1R0aWIzSmtaWEl0Y21Ga2FYVnpPblpoY2lndExYSmhaR2wxY3lrN1ltRmphMmR5'
    || 'YjNWdVpEcDJZWElvTFMxemRYSm1ZV05sS1gwdWNHOWpMWEp2ZHkwdGJtOTBiV1YwZTJKaFkydG5jbTkxYm1RNmRtRnlLQzB0WW1Ga0xYZGhjMmdwTzJKdmNt'
    || 'UmxjaTFqYjJ4dmNqb2paVGd3TURGak16aDlMbkJ2WXkxeWIzY3RMVzFsZEh0aVlXTnJaM0p2ZFc1a09uWmhjaWd0TFhOMWNtWmhZMlVwZlM1d2IyTXRjbTkz'
    || 'TFMxdVlYdHZjR0ZqYVhSNU9pNDNNbjB1Y0c5akxYSnZkMTlmYldGeWEzdG1iR1Y0T201dmJtVTdkMmxrZEdnNk1qSndlRHRvWldsbmFIUTZNakp3ZUR0aWIz'
    || 'SmtaWEl0Y21Ga2FYVnpPalV3SlR0a2FYTndiR0Y1T21keWFXUTdjR3hoWTJVdGFYUmxiWE02WTJWdWRHVnlPMlp2Ym5RdGMybDZaVG94TTNCNE8yWnZiblF0'
    || 'ZDJWcFoyaDBPamN3TUR0c2FXNWxMV2hsYVdkb2REb3hmUzV3YjJNdGNtOTNMUzF0WlhRZ0xuQnZZeTF5YjNkZlgyMWhjbXQ3WW1GamEyZHliM1Z1WkRwMllY'
    || 'SW9MUzFuYjI5a0xYZGhjMmdwTzJOdmJHOXlPblpoY2lndExXZHZiMlFwZlM1d2IyTXRjbTkzTFMxdWIzUnRaWFFnTG5Cdll5MXliM2RmWDIxaGNtdDdZbUZq'
    || 'YTJkeWIzVnVaRG9qWlRnd01ERmpNakU3WTI5c2IzSTZkbUZ5S0MwdFltRmtLWDB1Y0c5akxYSnZkeTB0Y0dWdVpHbHVaeUF1Y0c5akxYSnZkMTlmYldGeWEz'
    || 'dGlZV05yWjNKdmRXNWtPblpoY2lndExYTjFjbVpoWTJVdE15azdZMjlzYjNJNmRtRnlLQzB0YlhWMFpXUXBmUzV3YjJNdGNtOTNMUzF1WVNBdWNHOWpMWEp2'
    || 'ZDE5ZmJXRnlhM3RpWVdOclozSnZkVzVrT25SeVlXNXpjR0Z5Wlc1ME8yTnZiRzl5T25aaGNpZ3RMV1JwYlNrN1ltOTRMWE5vWVdSdmR6cHBibk5sZENBd0lE'
    || 'QWdNQ0F4Y0hnZ2RtRnlLQzB0YkdsdVpTMHlLWDB1Y0c5akxYSnZkMTlmWW05a2VYdHRhVzR0ZDJsa2RHZzZNRHRtYkdWNE9qRjlMbkJ2WXkxeWIzZGZYM1J2'
    || 'Y0h0a2FYTndiR0Y1T21ac1pYZzdZV3hwWjI0dGFYUmxiWE02WW1GelpXeHBibVU3WjJGd09qRXdjSGc3YW5WemRHbG1lUzFqYjI1MFpXNTBPbk53WVdObExX'
    || 'SmxkSGRsWlc1OUxuQnZZeTF5YjNkZlgyeGhZbVZzZTJadmJuUXRjMmw2WlRveE15NDFjSGc3Wm05dWRDMTNaV2xuYUhRNk5qQXdPMk52Ykc5eU9uWmhjaWd0'
    || 'TFc1aGRua3BPMnhwYm1VdGFHVnBaMmgwT2pFdU16VjlMbkJ2WXkxeWIzZGZYM04wWVhSbGUyWnNaWGc2Ym05dVpUdG1iMjUwTFhOcGVtVTZNVEZ3ZUR0bWIy'
    || 'NTBMWGRsYVdkb2REbzNNREE3ZEdWNGRDMTBjbUZ1YzJadmNtMDZkWEJ3WlhKallYTmxPMnhsZEhSbGNpMXpjR0ZqYVc1bk9pNHdOR1Z0ZlM1d2IyTXRjbTkz'
    || 'WDE5emRHRjBaUzB0YldWMGUyTnZiRzl5T25aaGNpZ3RMV2R2YjJRcGZTNXdiMk10Y205M1gxOXpkR0YwWlMwdGJtOTBiV1YwZTJOdmJHOXlPblpoY2lndExX'
    || 'SmhaQ2w5TG5Cdll5MXliM2RmWDNOMFlYUmxMUzF3Wlc1a2FXNW5lMk52Ykc5eU9uWmhjaWd0TFcxMWRHVmtLWDB1Y0c5akxYSnZkMTlmYzNSaGRHVXRMVzVo'
    || 'ZTJOdmJHOXlPblpoY2lndExXUnBiU2w5TG5Cdll5MXliM2RmWDNkb2VYdHRZWEpuYVc0Nk5YQjRJREFnTUR0bWIyNTBMWE5wZW1VNk1USndlRHRqYjJ4dmNq'
    || 'cDJZWElvTFMxdGRYUmxaQ2s3YkdsdVpTMW9aV2xuYUhRNk1TNDFmUzV3YjJNdGNtOTNYMTl0WVhSb2UyMWhjbWRwYmpvNGNIZ2dNQ0F3ZlM1d2IyTXRjbTkz'
    || 'WDE5dFlYUm9JR052WkdWN1pHbHpjR3hoZVRwcGJteHBibVV0WW14dlkyczdjR0ZrWkdsdVp6b3pjSGdnT0hCNE8ySnZjbVJsY2kxeVlXUnBkWE02TlhCNE8y'
    || 'SmhZMnRuY205MWJtUTZkbUZ5S0MwdGMzVnlabUZqWlMweUtUdGliM0prWlhJNk1YQjRJSE52Ykdsa0lIWmhjaWd0TFd4cGJtVXBPMlp2Ym5RdGMybDZaVG94'
    || 'TW5CNE8yWnZiblF0ZG1GeWFXRnVkQzF1ZFcxbGNtbGpPblJoWW5Wc1lYSXRiblZ0Y3p0amIyeHZjanAyWVhJb0xTMXVZWFo1S1gwdWNHOWpMWEp2ZDE5ZmJX'
    || 'RjBhQzB0Ym05dVpYdG1iMjUwTFhOcGVtVTZNVEV1TlhCNE8yTnZiRzl5T25aaGNpZ3RMV1JwYlNrN1ptOXVkQzF6ZEhsc1pUcHBkR0ZzYVdOOUxuQnZZeTF5'
    || 'YjNkZlgzQmxibVI3YldGeVoybHVPamR3ZUNBd0lEQTdabTl1ZEMxemFYcGxPakV5Y0hnN1kyOXNiM0k2ZG1GeUtDMHRkR1Y0ZENrN2JHbHVaUzFvWldsbmFI'
    || 'UTZNUzQxZlM1d2IyTXRjbTkzWDE5M2FHVnVlMjFoY21kcGJqbzBjSGdnTUNBd08yWnZiblF0YzJsNlpUb3hNWEI0TzJOdmJHOXlPblpoY2lndExXMTFkR1Zr'
    || 'S1R0bWIyNTBMWGRsYVdkb2REbzJNREI5TG5Cdll5MXliM2RmWDIxbGRHRjdiV0Z5WjJsdU9qRXdjSGdnTUNBd08zQmhaR1JwYm1jdGRHOXdPamx3ZUR0aWIz'
    || 'SmtaWEl0ZEc5d09qRndlQ0J6YjJ4cFpDQjJZWElvTFMxc2FXNWxLVHRrYVhOd2JHRjVPbWR5YVdRN1oyRndPamh3ZUNBeU1IQjRPMmR5YVdRdGRHVnRjR3ho'
    || 'ZEdVdFkyOXNkVzF1Y3pveFpuSjlRRzFsWkdsaEtHMXBiaTEzYVdSMGFEbzVNREJ3ZUNsN0xuQnZZeTF5YjNkZlgyMWxkR0Y3WjNKcFpDMTBaVzF3YkdGMFpT'
    || 'MWpiMngxYlc1ek9qTm1jaUF4Wm5KOWZTNXdiMk10Y205M1gxOXRaWFJoSUdSMGUyWnZiblF0YzJsNlpUb3hNWEI0TzJadmJuUXRkMlZwWjJoME9qWXdNRHQw'
    || 'WlhoMExYUnlZVzV6Wm05eWJUcDFjSEJsY21OaGMyVTdiR1YwZEdWeUxYTndZV05wYm1jNkxqQTBaVzA3WTI5c2IzSTZkbUZ5S0MwdFpHbHRLVHR0WVhKbmFX'
    || 'NHRZbTkwZEc5dE9qSndlSDB1Y0c5akxYSnZkMTlmYldWMFlTQmtaSHR0WVhKbmFXNDZNRHRtYjI1MExYTnBlbVU2TVRFdU5YQjRPMk52Ykc5eU9uWmhjaWd0'
    || 'TFcxMWRHVmtLVHRzYVc1bExXaGxhV2RvZERveExqVjlMbkJ2WXkxeWIzZGZYMjFsZEdFZ1pHUWdZMjlrWlh0bWIyNTBMWE5wZW1VNk1URndlRHRqYjJ4dmNq'
    || 'cDJZWElvTFMxdVlYWjVLWDB1Y0c5algxOXViM1JsZTIxaGNtZHBiam95Y0hnZ01DQXdPM0JoWkdScGJtYzZNVEJ3ZUNBeE0zQjRPMkp2Y21SbGNpMXlZV1Jw'
    || 'ZFhNNmRtRnlLQzB0Y21Ga2FYVnpLVHRpWVdOclozSnZkVzVrT25aaGNpZ3RMWE4xY21aaFkyVXRNaWs3WW05eVpHVnlPakZ3ZUNCemIyeHBaQ0IyWVhJb0xT'
    || 'MXNhVzVsS1R0bWIyNTBMWE5wZW1VNk1URndlRHRqYjJ4dmNqcDJZWElvTFMxdGRYUmxaQ2s3YkdsdVpTMW9aV2xuYUhRNk1TNDFOWDB1Y0c5akxXVnRjSFI1'
    || 'ZTNCaFpHUnBibWM2TWpCd2VEdGliM0prWlhJdGNtRmthWFZ6T25aaGNpZ3RMWEpoWkdsMWN5azdZbTl5WkdWeU9qRndlQ0JrWVhOb1pXUWdkbUZ5S0MwdGJH'
    || 'bHVaUzB5S1R0aVlXTnJaM0p2ZFc1a09uWmhjaWd0TFhOMWNtWmhZMlVwZlM1d2IyTXRaVzF3ZEhrZ2FETjdiV0Z5WjJsdU9qQTdabTl1ZEMxemFYcGxPakUw'
    || 'Y0hnN1kyOXNiM0k2ZG1GeUtDMHRibUYyZVNsOUxuQnZZeTFsYlhCMGVTQndlMjFoY21kcGJqbzJjSGdnTUNBeE1IQjRPMlp2Ym5RdGMybDZaVG94TWk0MWNI'
    || 'ZzdZMjlzYjNJNmRtRnlLQzB0YlhWMFpXUXBPMnhwYm1VdGFHVnBaMmgwT2pFdU5YMHVjRzlqTFdWdGNIUjVJR052WkdWN1pHbHpjR3hoZVRwaWJHOWphenR3'
    || 'WVdSa2FXNW5Pamh3ZUNBeE1IQjRPMkp2Y21SbGNpMXlZV1JwZFhNNk5uQjRPMkpoWTJ0bmNtOTFibVE2ZG1GeUtDMHRjM1Z5Wm1GalpTMHlLVHRpYjNKa1pY'
    || 'STZNWEI0SUhOdmJHbGtJSFpoY2lndExXeHBibVVwTzJadmJuUXRjMmw2WlRveE1YQjRPMk52Ykc5eU9uWmhjaWd0TFhSbGVIUXBPM2RvYVhSbExYTndZV05s'
    || 'T25CeVpTMTNjbUZ3TzNkdmNtUXRZbkpsWVdzNlluSmxZV3N0ZDI5eVpIMHVhVzV6Y0dWamRIdGthWE53YkdGNU9tZHlhV1E3WjNKcFpDMTBaVzF3YkdGMFpT'
    || 'MWpiMngxYlc1ek9tMXBibTFoZUNnd0xERm1jaWtnTXpBd2NIZzdaMkZ3T2pFMmNIZzdZV3hwWjI0dGFYUmxiWE02YzNSaGNuUjlMbWx1YzNCbFkzUmZYMnhw'
    || 'YzNSN2JXbHVMWGRwWkhSb09qQjlMbWx1YzNCbFkzUmZYMlJsZEdGcGJIdGlZV05yWjNKdmRXNWtPblpoY2lndExYTjFjbVpoWTJVdE1pazdZbTl5WkdWeU9q'
    || 'RndlQ0J6YjJ4cFpDQjJZWElvTFMxc2FXNWxLVHRpYjNKa1pYSXRjbUZrYVhWek9uWmhjaWd0TFhKaFpHbDFjeWs3Y0dGa1pHbHVaem94TkhCNElERTFjSGdn'
    || 'TVRWd2VIMHVhVzV6Y0dWamRGOWZkR2wwYkdWN2JXRnlaMmx1T2pBZ01DQXhNSEI0TzJadmJuUXRjMmw2WlRveE5IQjRPMlp2Ym5RdGQyVnBaMmgwT2pZd01E'
    || 'dGpiMnh2Y2pwMllYSW9MUzEwWlhoMEtUdHZkbVZ5Wm14dmR5MTNjbUZ3T21GdWVYZG9aWEpsZlM1cGJuTndaV04wWDE5bWFXVnNaSE43WkdsemNHeGhlVHBu'
    || 'Y21sa08yZHlhV1F0ZEdWdGNHeGhkR1V0WTI5c2RXMXVjenBoZFhSdklHMXBibTFoZUNnd0xERm1jaWs3WjJGd09qZHdlQ0F4TW5CNE8yMWhjbWRwYmpvd2ZT'
    || 'NXBibk53WldOMFgxOW1hV1ZzWkhNZ1pIUjdabTl1ZEMxemFYcGxPakV4Y0hnN1ptOXVkQzEzWldsbmFIUTZOakF3TzNSbGVIUXRkSEpoYm5ObWIzSnRPblZ3'
    || 'Y0dWeVkyRnpaVHRzWlhSMFpYSXRjM0JoWTJsdVp6b3VNRFJsYlR0amIyeHZjanAyWVhJb0xTMWthVzBwTzNkb2FYUmxMWE53WVdObE9tNXZkM0poY0gwdWFX'
    || 'NXpjR1ZqZEY5ZlptbGxiR1J6SUdSa2UyMWhjbWRwYmpvd08yWnZiblF0YzJsNlpUb3hNaTQxY0hnN1kyOXNiM0k2ZG1GeUtDMHRkR1Y0ZENrN1ptOXVkQzEy'
    || 'WVhKcFlXNTBMVzUxYldWeWFXTTZkR0ZpZFd4aGNpMXVkVzF6TzI5MlpYSm1iRzkzTFhkeVlYQTZZVzU1ZDJobGNtVjlMbWx1YzNCbFkzUmZYMjV2ZEdWN2JX'
    || 'RnlaMmx1T2pFeWNIZ2dNQ0F3TzJadmJuUXRjMmw2WlRveE1TNDFjSGc3WTI5c2IzSTZkbUZ5S0MwdGJYVjBaV1FwTzJ4cGJtVXRhR1ZwWjJoME9qRXVOWDB1'
    || 'ZEdGaWJHVXRMWEJwWTJzZ2RHSnZaSGtnZEhKN1kzVnljMjl5T25CdmFXNTBaWEo5TG5SaFlteGxMUzF3YVdOcklIUmliMlI1SUhSeU9taHZkbVZ5ZTJKaFky'
    || 'dG5jbTkxYm1RNmRtRnlLQzB0YzNWeVptRmpaUzB5S1gwdWRHRmliR1V0TFhCcFkyc2dkR0p2WkhrZ2RISXVkSEl0TFc5dWUySmhZMnRuY205MWJtUTZkbUZ5'
    || 'S0MwdFlXTmpaVzUwTFhkaGMyZ3BmUzUwWVdKc1pTMHRjR2xqYXlCMFltOWtlU0IwY2pwbWIyTjFjeTEyYVhOcFlteGxlMjkxZEd4cGJtVTZNbkI0SUhOdmJH'
    || 'bGtJSFpoY2lndExXRmpZMlZ1ZENrN2IzVjBiR2x1WlMxdlptWnpaWFE2TFRKd2VIMHVjMlZuWDE5aVlYSjdaR2x6Y0d4aGVUcHBibXhwYm1VdFpteGxlRHRu'
    || 'WVhBNk1uQjRPM0JoWkdScGJtYzZNbkI0TzIxaGNtZHBiaTFpYjNSMGIyMDZNVEp3ZUR0aVlXTnJaM0p2ZFc1a09uWmhjaWd0TFhOMWNtWmhZMlV0TWlrN1lt'
    || 'OXlaR1Z5T2pGd2VDQnpiMnhwWkNCMllYSW9MUzFzYVc1bEtUdGliM0prWlhJdGNtRmthWFZ6T2pod2VIMHVjMlZuWDE5aWRHNTdMWGRsWW10cGRDMWhjSEJs'
    || 'WVhKaGJtTmxPbTV2Ym1VN0xXMXZlaTFoY0hCbFlYSmhibU5sT201dmJtVTdZWEJ3WldGeVlXNWpaVHB1YjI1bE8ySnZjbVJsY2pvd08ySmhZMnRuY205MWJt'
    || 'UTZkSEpoYm5Od1lYSmxiblE3WTNWeWMyOXlPbkJ2YVc1MFpYSTdjR0ZrWkdsdVp6bzFjSGdnTVRGd2VEdGliM0prWlhJdGNtRmthWFZ6T2pad2VEdG1iMjUw'
    || 'T21sdWFHVnlhWFE3Wm05dWRDMXphWHBsT2pFeWNIZzdabTl1ZEMxM1pXbG5hSFE2TlRBd08yTnZiRzl5T25aaGNpZ3RMVzExZEdWa0tYMHVjMlZuWDE5aWRH'
    || 'NHRMVzl1ZTJKaFkydG5jbTkxYm1RNmRtRnlLQzB0YzNWeVptRmpaU2s3WTI5c2IzSTZkbUZ5S0MwdGRHVjRkQ2s3WW05NExYTm9ZV1J2ZHpwMllYSW9MUzF6'
    || 'YUMxallYSmtLWDB1YzJWblgxOWlkRzQ2Wm05amRYTXRkbWx6YVdKc1pYdHZkWFJzYVc1bE9qSndlQ0J6YjJ4cFpDQjJZWElvTFMxaFkyTmxiblFwTzI5MWRH'
    || 'eHBibVV0YjJabWMyVjBPakZ3ZUgwdWRISmxibVI3WW1GamEyZHliM1Z1WkRwMllYSW9MUzF6ZFhKbVlXTmxLVHRpYjNKa1pYSTZNWEI0SUhOdmJHbGtJSFpo'
    || 'Y2lndExXeHBibVVwTzJKdmNtUmxjaTF5WVdScGRYTTZkbUZ5S0MwdGNtRmthWFZ6S1R0d1lXUmthVzVuT2pFemNIZ2dNVFZ3ZUNBeE5IQjRPMlJwYzNCc1lY'
    || 'azZabXhsZUR0aGJHbG5iaTFwZEdWdGN6cG1iR1Y0TFdWdVpEdHFkWE4wYVdaNUxXTnZiblJsYm5RNmMzQmhZMlV0WW1WMGQyVmxianRuWVhBNk1UUndlSDB1'
    || 'ZEhKbGJtUmZYMmhsWVdSN2JXbHVMWGRwWkhSb09qQjlMblJ5Wlc1a1gxOXpjR0Z5YTN0a2FYTndiR0Y1T21ac1pYZzdabXhsZUMxa2FYSmxZM1JwYjI0Nlky'
    || 'OXNkVzF1TzJGc2FXZHVMV2wwWlcxek9tWnNaWGd0Wlc1a08yZGhjRG96Y0hnN1pteGxlRHB1YjI1bGZTNTBjbVZ1WkY5ZmQybHVlMlp2Ym5RdGMybDZaVG94'
    || 'TVhCNE8yeGxkSFJsY2kxemNHRmphVzVuT2k0d05HVnRPM1JsZUhRdGRISmhibk5tYjNKdE9uVndjR1Z5WTJGelpUdGpiMnh2Y2pwMllYSW9MUzFrYVcwcGZT'
    || 'NTBjbVZ1WkY5ZmJtOXVaWHRtYjI1MExYTnBlbVU2TVRFdU5YQjRPMk52Ykc5eU9uWmhjaWd0TFdScGJTazdabTl1ZEMxemRIbHNaVHB1YjNKdFlXeDlMblJ5'
    || 'Wlc1a0xTMW5iMjlrSUM1emRHRjBYMTkyWVd4MVpYdGpiMnh2Y2pwMllYSW9MUzFuYjI5a0tYMHVkSEpsYm1RdExYZGhjbTRnTG5OMFlYUmZYM1poYkhWbGUy'
    || 'TnZiRzl5T25aaGNpZ3RMWGRoY200cGZTNTBjbVZ1WkMwdFltRmtJQzV6ZEdGMFgxOTJZV3gxWlh0amIyeHZjanAyWVhJb0xTMWlZV1FwZlVCdFpXUnBZU2h0'
    || 'WVhndGQybGtkR2c2TVRFd01IQjRLWHN1YVc1emNHVmpkSHRuY21sa0xYUmxiWEJzWVhSbExXTnZiSFZ0Ym5NNmJXbHViV0Y0S0RBc01XWnlLWDE5TG05MmJG'
    || 'OWZjM1ZpZTJadmJuUXRjMmw2WlRveE1YQjRPMnhwYm1VdGFHVnBaMmgwT2pFdU16VTdZMjlzYjNJNmRtRnlLQzB0WkdsdEtUdHRZWEpuYVc0Nk1uQjRJREFn'
    || 'Tm5CNE8yOTJaWEptYkc5M0xYZHlZWEE2WVc1NWQyaGxjbVU3Wm05dWRDMTJZWEpwWVc1MExXNTFiV1Z5YVdNNmRHRmlkV3hoY2kxdWRXMXpmUzV3WVc1bGJD'
    || 'MWxjbkp2Y2kwdFlYVjRlMjFoY21kcGJpMTBiM0E2TVRCd2VEdHdZV1JrYVc1bk9qaHdlQ0F4TUhCNE8yWnZiblF0YzJsNlpUb3hNbkI0ZlM1d1lXNWxiQzFs'
    || 'Y25KdmNpMHRZWFY0SUhCN2JXRnlaMmx1T2pSd2VDQXdJRFp3ZUgwdWNHRnVaV3d0ZEhKMWJtTXRMV0YxZUN3dWNHRnVaV3d0Ym05MFluVnBiSFF0TFdGMWVI'
    || 'dHRZWEpuYVc0dGRHOXdPakV3Y0hnN1ptOXVkQzF6YVhwbE9qRXljSGg5TG1SbFpteHBjM1I3YldGeVoybHVMWFJ2Y0RveWNIaDlMbVJsWm14cGMzUmZYMmhs'
    || 'WVdSN1ptOXVkQzF6YVhwbE9qRXhjSGc3Wm05dWRDMTNaV2xuYUhRNk56QXdPM1JsZUhRdGRISmhibk5tYjNKdE9uVndjR1Z5WTJGelpUdHNaWFIwWlhJdGMz'
    || 'QmhZMmx1WnpvdU1EUmxiVHRqYjJ4dmNqcDJZWElvTFMxa2FXMHBPM0JoWkdScGJtY3RZbTkwZEc5dE9qaHdlRHR0WVhKbmFXNHRZbTkwZEc5dE9qRXdjSGc3'
    || 'WW05eVpHVnlMV0p2ZEhSdmJUb3hjSGdnYzI5c2FXUWdkbUZ5S0MwdGJHbHVaU2w5TG1SbFpteHBjM1JmWDJkeWFXUjdaR2x6Y0d4aGVUcG5jbWxrTzJOdmJI'
    || 'VnRiaTFuWVhBNk16UndlSDB1WkdWbWJHbHpkRjlmWjNKcFpDMHRNWHRuY21sa0xYUmxiWEJzWVhSbExXTnZiSFZ0Ym5NNk1XWnlmUzVrWldac2FYTjBYMTlu'
    || 'Y21sa0xTMHllMmR5YVdRdGRHVnRjR3hoZEdVdFkyOXNkVzF1Y3pveFpuSWdNV1p5ZlVCdFpXUnBZU2h0WVhndGQybGtkR2c2T1RBd2NIZ3BleTVrWldac2FY'
    || 'TjBYMTluY21sa0xTMHllMmR5YVdRdGRHVnRjR3hoZEdVdFkyOXNkVzF1Y3pveFpuSjlmUzVrWldac2FYTjBYMTl5YjNkN1pHbHpjR3hoZVRwbmNtbGtPMmR5'
    || 'YVdRdGRHVnRjR3hoZEdVdFkyOXNkVzF1Y3pveFpuSWdZWFYwYnp0bmNtbGtMWFJsYlhCc1lYUmxMV0Z5WldGek9pSnNZV0psYkNCMllXeDFaU0lnSW01dmRH'
    || 'VWdibTkwWlNJN1lXeHBaMjR0YVhSbGJYTTZZbUZ6Wld4cGJtVTdZMjlzZFcxdUxXZGhjRG94Tm5CNE8zQmhaR1JwYm1jNk5YQjRJREE3YldsdUxXaGxhV2Rv'
    || 'ZERveU5IQjRPMkp2Y21SbGNpMWliM1IwYjIwNk1YQjRJSE52Ykdsa0lIWmhjaWd0TFd4cGJtVXRjMjltZEN3Z2NtZGlZU2d4Tnl3eE55d3hOeXd1TURVcEtY'
    || 'MHVaR1ZtYkdsemRGOWZjbTkzT214aGMzUXRZMmhwYkdSN1ltOXlaR1Z5TFdKdmRIUnZiVG93ZlM1a1pXWnNhWE4wWDE5c1lXSmxiSHRuY21sa0xXRnlaV0U2'
    || 'YkdGaVpXdzdabTl1ZEMxemFYcGxPakV5TGpWd2VEdGpiMnh2Y2pwMllYSW9MUzF0ZFhSbFpDbDlMbVJsWm14cGMzUmZYM1poYkhWbGUyZHlhV1F0WVhKbFlU'
    || 'cDJZV3gxWlR0bWIyNTBMWE5wZW1VNk1USXVOWEI0TzJadmJuUXRkMlZwWjJoME9qWXdNRHRqYjJ4dmNqcDJZWElvTFMxMFpYaDBLVHQwWlhoMExXRnNhV2R1'
    || 'T25KcFoyaDBPMlp2Ym5RdGRtRnlhV0Z1ZEMxdWRXMWxjbWxqT25SaFluVnNZWEl0Ym5WdGMzMHVaR1ZtYkdsemRGOWZkbUZzZFdVdExXZHZiMlI3WTI5c2Iz'
    || 'STZkbUZ5S0MwdFoyOXZaQ2w5TG1SbFpteHBjM1JmWDNaaGJIVmxMUzEzWVhKdWUyTnZiRzl5T2lOaU9EY3pNR0Y5TG1SbFpteHBjM1JmWDNaaGJIVmxMUzFp'
    || 'WVdSN1kyOXNiM0k2ZG1GeUtDMHRZbUZrS1gwdVpHVm1iR2x6ZEY5ZmJtOTBaWHRuY21sa0xXRnlaV0U2Ym05MFpUdG1iMjUwTFhOcGVtVTZNVEZ3ZUR0amIy'
    || 'eHZjanAyWVhJb0xTMWthVzBwTzJ4cGJtVXRhR1ZwWjJoME9qRXVORFU3YldGeVoybHVMWFJ2Y0RveWNIaDlMbTFsZEdodlpIdG1iMjUwTFhOcGVtVTZNVEZ3'
    || 'ZUR0amIyeHZjanAyWVhJb0xTMWthVzBwTzJ4cGJtVXRhR1ZwWjJoME9qRXVOVHR0WVhKbmFXNHRkRzl3T2pod2VIMHViV1YwYUc5a0lITjBjbTl1WjN0amIy'
    || 'eHZjanAyWVhJb0xTMXRkWFJsWkNrN1ptOXVkQzEzWldsbmFIUTZOekF3ZlM1alpXeHNMUzF1WVh0bWIyNTBMWE5wZW1VNk1URndlRHRtYjI1MExYZGxhV2Rv'
    || 'ZERvM01EQTdiR1YwZEdWeUxYTndZV05wYm1jNkxqQXpaVzA3WTI5c2IzSTZkbUZ5S0MwdGJYVjBaV1FwTzJOMWNuTnZjanBvWld4d2ZTNWpaV3hzTFMxdWIy'
    || 'NWxlMk52Ykc5eU9uWmhjaWd0TFdScGJTazdZM1Z5YzI5eU9taGxiSEI5TG1GamRDMXpkVzF0WVhKNWUyUnBjM0JzWVhrNlpteGxlRHRoYkdsbmJpMXBkR1Z0'
    || 'Y3pwalpXNTBaWEk3WjJGd09qRXdjSGc3Wm14bGVDMTNjbUZ3T25keVlYQTdjR0ZrWkdsdVp6b3hNSEI0SURFMGNIZzdZbTl5WkdWeU9qRndlQ0J6YjJ4cFpD'
    || 'QjJZWElvTFMxc2FXNWxLVHRpYjNKa1pYSXRjbUZrYVhWek9uWmhjaWd0TFhKaFpHbDFjeWs3WW1GamEyZHliM1Z1WkRwMllYSW9MUzF6ZFhKbVlXTmxMVElw'
    || 'TzJOMWNuTnZjanB3YjJsdWRHVnlPMlp2Ym5RdGMybDZaVG94TWk0MWNIZzdZMjlzYjNJNmRtRnlLQzB0YlhWMFpXUXBPMnhwYm1VdGFHVnBaMmgwT2pFdU5I'
    || 'MHVZV04wTFhOMWJXMWhjbms2YUc5MlpYSjdZbUZqYTJkeWIzVnVaRHAyWVhJb0xTMXpkWEptWVdObEtUdGliM0prWlhJdFkyOXNiM0k2ZG1GeUtDMHRiR2x1'
    || 'WlMweUtYMHVZV04wTFhOMWJXMWhjbms2Wm05amRYTXRkbWx6YVdKc1pYdHZkWFJzYVc1bE9qSndlQ0J6YjJ4cFpDQjJZWElvTFMxaFkyTmxiblFwTzI5MWRH'
    || 'eHBibVV0YjJabWMyVjBPakp3ZUgwdVlXTjBMWE4xYlcxaGNubGZYMk52ZFc1MGUyWnZiblF0ZDJWcFoyaDBPamN3TUR0amIyeHZjanAyWVhJb0xTMXVZWFo1'
    || 'S1gwdVlXTjBMWE4xYlcxaGNubGZYM1JwWlhKN1ptOXVkQzF6YVhwbE9qRXhjSGc3Wm05dWRDMTNaV2xuYUhRNk5qQXdPM1JsZUhRdGRISmhibk5tYjNKdE9u'
    || 'VndjR1Z5WTJGelpUdHNaWFIwWlhJdGMzQmhZMmx1WnpvdU1EUmxiVHR3WVdSa2FXNW5PakZ3ZUNBM2NIZzdZbTl5WkdWeUxYSmhaR2wxY3pvMGNIZzdZbUZq'
    || 'YTJkeWIzVnVaRHAyWVhJb0xTMXpkWEptWVdObEtUdGliM0prWlhJNk1YQjRJSE52Ykdsa0lIWmhjaWd0TFd4cGJtVXBPMk52Ykc5eU9uWmhjaWd0TFdScGJT'
    || 'bDlMbUZqZEMxemRXMXRZWEo1WDE5amFHVjJjbTl1ZTIxaGNtZHBiaTFzWldaME9tRjFkRzg3Wm14bGVEcHViMjVsTzNSeVlXNXphWFJwYjI0NmRISmhibk5t'
    || 'YjNKdElDNHljeUIyWVhJb0xTMWxZWE5sS1R0amIyeHZjanAyWVhJb0xTMWthVzBwZlM1aFkzUXRjM1Z0YldGeWVWOWZZMmhsZG5KdmJpMHRiM0JsYm50MGNt'
    || 'RnVjMlp2Y20wNmNtOTBZWFJsS0RFNE1HUmxaeWw5TG1SeWFXeHNMWEp2ZDE5ZmRHOW5aMnhsZXkxM1pXSnJhWFF0WVhCd1pXRnlZVzVqWlRwdWIyNWxPeTF0'
    || 'YjNvdFlYQndaV0Z5WVc1alpUcHViMjVsTzJGd2NHVmhjbUZ1WTJVNmJtOXVaVHRpYjNKa1pYSTZNRHRpWVdOclozSnZkVzVrT25SeVlXNXpjR0Z5Wlc1ME8y'
    || 'TjFjbk52Y2pwd2IybHVkR1Z5TzJScGMzQnNZWGs2Wm14bGVEdGhiR2xuYmkxcGRHVnRjenBqWlc1MFpYSTdaMkZ3T2pod2VEdDNhV1IwYURveE1EQWxPM0Jo'
    || 'WkdScGJtYzZPSEI0SURFd2NIZzdkR1Y0ZEMxaGJHbG5ianBzWldaME8yWnZiblE2YVc1b1pYSnBkRHRqYjJ4dmNqcHBibWhsY21sME8ySnZjbVJsY2kxeVlX'
    || 'UnBkWE02Tm5CNGZTNWtjbWxzYkMxeWIzZGZYM1J2WjJkc1pUcG9iM1psY250aVlXTnJaM0p2ZFc1a09uWmhjaWd0TFhOMWNtWmhZMlV0TWlsOUxtUnlhV3hz'
    || 'TFhKdmQxOWZkRzluWjJ4bE9tWnZZM1Z6TFhacGMybGliR1Y3YjNWMGJHbHVaVG95Y0hnZ2MyOXNhV1FnZG1GeUtDMHRZV05qWlc1MEtUdHZkWFJzYVc1bExX'
    || 'OW1abk5sZERvdE1uQjRmUzVrY21sc2JDMXliM2RmWDJOb1pYWnliMjU3Wm14bGVEcHViMjVsTzNSeVlXNXphWFJwYjI0NmRISmhibk5tYjNKdElDNHhObk1n'
    || 'ZG1GeUtDMHRaV0Z6WlNrN1kyOXNiM0k2ZG1GeUtDMHRaR2x0S1gwdVpISnBiR3d0Y205M1gxOWphR1YyY205dUxTMXZjR1Z1ZTNSeVlXNXpabTl5YlRweWIz'
    || 'UmhkR1VvT1RCa1pXY3BmUzVrY21sc2JDMXliM2RmWDJOb2FXeGtjbVZ1ZTI5MlpYSm1iRzkzT21ocFpHUmxianQwY21GdWMybDBhVzl1T20xaGVDMW9aV2xu'
    || 'YUhRZ0xqSnpJSFpoY2lndExXVmhjMlVwTzNCaFpHUnBibWN0YkdWbWREb3hPSEI0ZlM1b2IzWmxjaTFrWlhSaGFXeDdjRzl6YVhScGIyNDZabWw0WldRN2Vp'
    || 'MXBibVJsZURvNU1EQTdjRzlwYm5SbGNpMWxkbVZ1ZEhNNmJtOXVaVHRpWVdOclozSnZkVzVrT25aaGNpZ3RMWE4xY21aaFkyVXBPMkp2Y21SbGNqb3hjSGdn'
    || 'YzI5c2FXUWdkbUZ5S0MwdGJHbHVaUzB5S1R0aWIzSmtaWEl0Y21Ga2FYVnpPamh3ZUR0d1lXUmthVzVuT2pod2VDQXhNWEI0TzJKdmVDMXphR0ZrYjNjNmRt'
    || 'RnlLQzB0YzJndGJXUXBPMlp2Ym5RdGMybDZaVG94TW5CNE8yTnZiRzl5T25aaGNpZ3RMWFJsZUhRcE8yeHBibVV0YUdWcFoyaDBPakV1TkRVN2JXRjRMWGRw'
    || 'WkhSb09qSTRNSEI0TzNkb2FYUmxMWE53WVdObE9tNXZjbTFoYkgwdWMyTmhiR1V0WW1GeWUyUnBjM0JzWVhrNlpteGxlRHQzYVdSMGFEb3hNREFsTzJobGFX'
    || 'ZG9kRG95TW5CNE8ySnZjbVJsY2kxeVlXUnBkWE02TkhCNE8yOTJaWEptYkc5M09taHBaR1JsYm4wdWMyTmhiR1V0WW1GeVgxOXpaV2Q3YldsdUxYZHBaSFJv'
    || 'T2pKd2VEdHdiM05wZEdsdmJqcHlaV3hoZEdsMlpYMHVjMk5oYkdVdFltRnlYMTl6WldjNlptbHljM1F0WTJocGJHUjdZbTl5WkdWeUxYSmhaR2wxY3pvMGNI'
    || 'Z2dNQ0F3SURSd2VIMHVjMk5oYkdVdFltRnlYMTl6WldjNmJHRnpkQzFqYUdsc1pIdGliM0prWlhJdGNtRmthWFZ6T2pBZ05IQjRJRFJ3ZUNBd2ZTNXpZMkZz'
    || 'WlMxaVlYSmZYMnhoWW1Wc2UzQnZjMmwwYVc5dU9tRmljMjlzZFhSbE8zUnZjRG93TzNKcFoyaDBPakE3WW05MGRHOXRPakE3YkdWbWREb3dPMlJwYzNCc1lY'
    || 'azZabXhsZUR0aGJHbG5iaTFwZEdWdGN6cGpaVzUwWlhJN2FuVnpkR2xtZVMxamIyNTBaVzUwT21ObGJuUmxjanRtYjI1MExYTnBlbVU2TVRGd2VEdG1iMjUw'
    || 'TFhkbGFXZG9kRG8yTURBN1kyOXNiM0k2STJabVpqdHZkbVZ5Wm14dmR6cG9hV1JrWlc0N2RHVjRkQzF2ZG1WeVpteHZkenBsYkd4cGNITnBjenQzYUdsMFpT'
    || 'MXpjR0ZqWlRwdWIzZHlZWEE3Y0dGa1pHbHVaem93SURSd2VIMEsiClNPTFVUSU9OX05BTUUgPSAiWmVyby1Qcml2aWxlZ2UgT3JjaGVzdHJhdGlvbiIKR0xP'
    || 'QkFMX05BTUUgPSAiX19ERUxFR19EQVRBX18iCkFQUF9PQkpFQ1QgPSAiREVMRUdBVEVEX09SQ0hFU1RSQVRJT05fQVBQIgoKaW1wb3J0IGpzb24KaW1wb3J0'
    || 'IHJlCgoKZGVmIHZhbGlkYXRlX2N1c3RvbWl6YXRpb24ocmF3KToKICAgIGlmIGlzaW5zdGFuY2UocmF3LCBzdHIpOgogICAgICAgIHJhdyA9IGpzb24ubG9h'
    || 'ZHMocmF3KQogICAgaWYgbm90IGlzaW5zdGFuY2UocmF3LCBkaWN0KToKICAgICAgICByYWlzZSBWYWx1ZUVycm9yKCJDdXN0b21pemF0aW9uIG11c3QgYmUg'
    || 'YSBKU09OIG9iamVjdCIpCiAgICBhbGxvd2VkID0geyJ2ZXJzaW9uIiwgInRpdGxlIiwgImRlZmF1bHRfc2VjdGlvbiIsICJzZWN0aW9uX2xhYmVscyIsICJz'
    || 'ZWN0aW9uX29yZGVyIiwgInBhbmVscyJ9CiAgICB1bmtub3duID0gc2V0KHJhdykgLSBhbGxvd2VkCiAgICBpZiB1bmtub3duOgogICAgICAgIHJhaXNlIFZh'
    || 'bHVlRXJyb3IoIlVua25vd24gY3VzdG9taXphdGlvbiBrZXlzOiAiICsgIiwgIi5qb2luKHNvcnRlZCh1bmtub3duKSkpCiAgICBpZiByYXcuZ2V0KCJ2ZXJz'
    || 'aW9uIiwgMSkgIT0gMToKICAgICAgICByYWlzZSBWYWx1ZUVycm9yKCJPbmx5IGN1c3RvbWl6YXRpb24gdmVyc2lvbiAxIGlzIHN1cHBvcnRlZCIpCgogICAg'
    || 'ZGVmIHRleHQodmFsdWUsIGxpbWl0KToKICAgICAgICBpZiBub3QgaXNpbnN0YW5jZSh2YWx1ZSwgc3RyKSBvciBub3QgdmFsdWUuc3RyaXAoKSBvciBsZW4o'
    || 'dmFsdWUpID4gbGltaXQ6CiAgICAgICAgICAgIHJhaXNlIFZhbHVlRXJyb3IoIkV4cGVjdGVkIG5vbmVtcHR5IHRleHQgb2YgYXQgbW9zdCAiICsgc3RyKGxp'
    || 'bWl0KSArICIgY2hhcmFjdGVycyIpCiAgICAgICAgcmV0dXJuIHZhbHVlCgogICAgZGVmIHNlY3Rpb24odmFsdWUpOgogICAgICAgIHZhbHVlID0gdGV4dCh2'
    || 'YWx1ZSwgODApCiAgICAgICAgaWYgbm90IHJlLmZ1bGxtYXRjaChyIlthLXpdW2EtejAtOV9dKiIsIHZhbHVlKToKICAgICAgICAgICAgcmFpc2UgVmFsdWVF'
    || 'cnJvcigiSW52YWxpZCBzZWN0aW9uIElEOiAiICsgdmFsdWUpCiAgICAgICAgcmV0dXJuIHZhbHVlCgogICAgcmVzdWx0ID0geyJ2ZXJzaW9uIjogMSwgInNl'
    || 'Y3Rpb25fbGFiZWxzIjoge30sICJzZWN0aW9uX29yZGVyIjogW10sICJwYW5lbHMiOiBbXX0KICAgIGlmICJ0aXRsZSIgaW4gcmF3OgogICAgICAgIHJlc3Vs'
    || 'dFsidGl0bGUiXSA9IHRleHQocmF3WyJ0aXRsZSJdLCAxMjApCiAgICBpZiAiZGVmYXVsdF9zZWN0aW9uIiBpbiByYXc6CiAgICAgICAgcmVzdWx0WyJkZWZh'
    || 'dWx0X3NlY3Rpb24iXSA9IHNlY3Rpb24ocmF3WyJkZWZhdWx0X3NlY3Rpb24iXSkKICAgIGxhYmVscyA9IHJhdy5nZXQoInNlY3Rpb25fbGFiZWxzIiwge30p'
    || 'CiAgICBpZiBub3QgaXNpbnN0YW5jZShsYWJlbHMsIGRpY3QpIG9yIGxlbihsYWJlbHMpID4gMzA6CiAgICAgICAgcmFpc2UgVmFsdWVFcnJvcigic2VjdGlv'
    || 'bl9sYWJlbHMgbXVzdCBjb250YWluIGF0IG1vc3QgMzAgZW50cmllcyIpCiAgICBmb3Iga2V5LCB2YWx1ZSBpbiBsYWJlbHMuaXRlbXMoKToKICAgICAgICBr'
    || 'ZXkgPSBzZWN0aW9uKGtleSkKICAgICAgICBpZiBrZXkgPT0gInBvY19zdWNjZXNzIjoKICAgICAgICAgICAgcmFpc2UgVmFsdWVFcnJvcigiUE9DIHN1Y2Nl'
    || 'c3MgY2Fubm90IGJlIHJlbmFtZWQiKQogICAgICAgIHJlc3VsdFsic2VjdGlvbl9sYWJlbHMiXVtrZXldID0gdGV4dCh2YWx1ZSwgODApCiAgICBvcmRlciA9'
    || 'IHJhdy5nZXQoInNlY3Rpb25fb3JkZXIiLCBbXSkKICAgIGlmIG5vdCBpc2luc3RhbmNlKG9yZGVyLCBsaXN0KSBvciBsZW4ob3JkZXIpID4gMzA6CiAgICAg'
    || 'ICAgcmFpc2UgVmFsdWVFcnJvcigic2VjdGlvbl9vcmRlciBtdXN0IGJlIGEgbGlzdCBvZiBhdCBtb3N0IDMwIHNlY3Rpb24gSURzIikKICAgIHJlc3VsdFsi'
    || 'c2VjdGlvbl9vcmRlciJdID0gW3NlY3Rpb24odmFsdWUpIGZvciB2YWx1ZSBpbiBvcmRlcl0KICAgIGlmIGxlbihzZXQocmVzdWx0WyJzZWN0aW9uX29yZGVy'
    || 'Il0pKSAhPSBsZW4ob3JkZXIpOgogICAgICAgIHJhaXNlIFZhbHVlRXJyb3IoInNlY3Rpb25fb3JkZXIgY29udGFpbnMgZHVwbGljYXRlcyIpCiAgICBwYW5l'
    || 'bHMgPSByYXcuZ2V0KCJwYW5lbHMiLCBbXSkKICAgIGlmIG5vdCBpc2luc3RhbmNlKHBhbmVscywgbGlzdCkgb3IgbGVuKHBhbmVscykgPiA2OgogICAgICAg'
    || 'IHJhaXNlIFZhbHVlRXJyb3IoIkF0IG1vc3Qgc2l4IGN1c3RvbSBwYW5lbHMgYXJlIHN1cHBvcnRlZCIpCiAgICB1c2VkID0gc2V0KCkKICAgIGZvciBwYW5l'
    || 'bCBpbiBwYW5lbHM6CiAgICAgICAgaWYgbm90IGlzaW5zdGFuY2UocGFuZWwsIGRpY3QpIG9yIHNldChwYW5lbCkgLSB7ImlkIiwgInRpdGxlIiwgInZpZXci'
    || 'LCAia2luZCIsICJsaW1pdCJ9OgogICAgICAgICAgICByYWlzZSBWYWx1ZUVycm9yKCJJbnZhbGlkIHBhbmVsIGZpZWxkcyIpCiAgICAgICAgcGFuZWxfaWQg'
    || 'PSBzZWN0aW9uKHBhbmVsLmdldCgiaWQiKSkKICAgICAgICBpZiBub3QgcGFuZWxfaWQuc3RhcnRzd2l0aCgiY3VzdG9tXyIpIG9yIHBhbmVsX2lkIGluIHVz'
    || 'ZWQ6CiAgICAgICAgICAgIHJhaXNlIFZhbHVlRXJyb3IoIlBhbmVsIElEcyBtdXN0IGJlIHVuaXF1ZSBhbmQgc3RhcnQgd2l0aCBjdXN0b21fIikKICAgICAg'
    || 'ICB1c2VkLmFkZChwYW5lbF9pZCkKICAgICAgICB2aWV3ID0gdGV4dChwYW5lbC5nZXQoInZpZXciKSwgMTI4KQogICAgICAgIGlmIG5vdCByZS5mdWxsbWF0'
    || 'Y2gociJWX0NVU1RPTV9bQS1aMC05X10rIiwgdmlldyk6CiAgICAgICAgICAgIHJhaXNlIFZhbHVlRXJyb3IoIlBhbmVsIHZpZXdzIG11c3QgYmUgdW5xdWFs'
    || 'aWZpZWQgVl9DVVNUT01fKiBpZGVudGlmaWVycyIpCiAgICAgICAga2luZCA9IHBhbmVsLmdldCgia2luZCIsICJ0YWJsZSIpCiAgICAgICAgaWYga2luZCBu'
    || 'b3QgaW4geyJ0YWJsZSIsICJiYXIiLCAibWV0cmljIn06CiAgICAgICAgICAgIHJhaXNlIFZhbHVlRXJyb3IoIlBhbmVsIGtpbmQgbXVzdCBiZSB0YWJsZSwg'
    || 'YmFyLCBvciBtZXRyaWMiKQogICAgICAgIGxpbWl0ID0gcGFuZWwuZ2V0KCJsaW1pdCIsIDEwMCkKICAgICAgICBpZiB0eXBlKGxpbWl0KSBpcyBub3QgaW50'
    || 'IG9yIG5vdCAxIDw9IGxpbWl0IDw9IDIwMDoKICAgICAgICAgICAgcmFpc2UgVmFsdWVFcnJvcigiUGFuZWwgbGltaXQgbXVzdCBiZSBhbiBpbnRlZ2VyIGZy'
    || 'b20gMSB0byAyMDAiKQogICAgICAgIHJlc3VsdFsicGFuZWxzIl0uYXBwZW5kKHsiaWQiOiBwYW5lbF9pZCwgInRpdGxlIjogdGV4dChwYW5lbC5nZXQoInRp'
    || 'dGxlIiksIDEyMCksCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJ2aWV3IjogdmlldywgImtpbmQiOiBraW5kLCAibGltaXQiOiBsaW1pdH0p'
    || 'CiAgICByZXR1cm4gcmVzdWx0CgoKZGVmIGxvYWRfY3VzdG9taXphdGlvbihzZXNzaW9uLCB0YXJnZXQpOgogICAgdHJ5OgogICAgICAgIHJlY29yZHMgPSBz'
    || 'ZXNzaW9uLnNxbCgiU0VMRUNUIENPTkZJRyBGUk9NICIgKyB0YXJnZXQgKwogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAiLkFQUF9DVVNUT01JWkFU'
    || 'SU9OIFdIRVJFIElEID0gJ2RlZmF1bHQnIikubGltaXQoMikuY29sbGVjdCgpCiAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGV4YzoKICAgICAgICByZXR1cm4g'
    || 'e30sIHt9LCAiQ3VzdG9taXphdGlvbiB1bmF2YWlsYWJsZTogIiArIHN0cihleGMpCiAgICBpZiBub3QgcmVjb3JkczoKICAgICAgICByZXR1cm4ge30sIHt9'
    || 'LCBOb25lCiAgICBpZiBsZW4ocmVjb3JkcykgIT0gMToKICAgICAgICByZXR1cm4ge30sIHt9LCAiQ3VzdG9taXphdGlvbiByZWplY3RlZDogZXhwZWN0ZWQg'
    || 'ZXhhY3RseSBvbmUgZGVmYXVsdCByb3ciCiAgICB0cnk6CiAgICAgICAgY29uZmlnID0gdmFsaWRhdGVfY3VzdG9taXphdGlvbihyZWNvcmRzWzBdWyJDT05G'
    || 'SUciXSkKICAgIGV4Y2VwdCAoVmFsdWVFcnJvciwgVHlwZUVycm9yLCBLZXlFcnJvcikgYXMgZXhjOgogICAgICAgIHJldHVybiB7fSwge30sICJDdXN0b21p'
    || 'emF0aW9uIHJlamVjdGVkOiAiICsgc3RyKGV4YykKICAgIHBhbmVscyA9IHt9CiAgICBmb3Igc3BlYyBpbiBjb25maWdbInBhbmVscyJdOgogICAgICAgIHRy'
    || 'eToKICAgICAgICAgICAgcm93cyA9IFtyb3cuYXNfZGljdCgpIGZvciByb3cgaW4gc2Vzc2lvbi5zcWwoCiAgICAgICAgICAgICAgICAiU0VMRUNUICogRlJP'
    || 'TSAiICsgdGFyZ2V0ICsgIi4iICsgc3BlY1sidmlldyJdICsgIiBPUkRFUiBCWSAxIgogICAgICAgICAgICApLmxpbWl0KHNwZWNbImxpbWl0Il0gKyAxKS5j'
    || 'b2xsZWN0KCldCiAgICAgICAgICAgIGlmIHNwZWNbImtpbmQiXSBpbiB7ImJhciIsICJtZXRyaWMifSBhbmQgcm93czoKICAgICAgICAgICAgICAgIGlmIG5v'
    || 'dCB7IkxBQkVMIiwgIlZBTFVFIn0uaXNzdWJzZXQocm93c1swXSk6CiAgICAgICAgICAgICAgICAgICAgcmFpc2UgVmFsdWVFcnJvcigiQmFyIGFuZCBtZXRy'
    || 'aWMgdmlld3MgbXVzdCBleHBvc2UgTEFCRUwgYW5kIFZBTFVFIGNvbHVtbnMiKQogICAgICAgICAgICByZXN1bHQgPSB7InJvd3MiOiBqc29uLmxvYWRzKGpz'
    || 'b24uZHVtcHMocm93c1s6c3BlY1sibGltaXQiXV0sIGRlZmF1bHQ9c3RyKSl9CiAgICAgICAgICAgIGlmIGxlbihyb3dzKSA+IHNwZWNbImxpbWl0Il06CiAg'
    || 'ICAgICAgICAgICAgICByZXN1bHRbInRydW5jYXRlZCJdID0gc3BlY1sibGltaXQiXQogICAgICAgICAgICBwYW5lbHNbc3BlY1siaWQiXV0gPSByZXN1bHQK'
    || 'ICAgICAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGV4YzoKICAgICAgICAgICAgcGFuZWxzW3NwZWNbImlkIl1dID0geyJlcnJvciI6IHN0cihleGMpfQogICAg'
    || 'cmV0dXJuIGNvbmZpZywgcGFuZWxzLCBOb25lCgoKIyBGSVJTVCBTdHJlYW1saXQgY2FsbCwgYmVmb3JlIGFueXRoaW5nIGVsc2UgY2FuIGJlY29tZSBvbmUu'
    || 'IFN0cmVhbWxpdCdzICJtYWdpYyIKIyByZW5kZXJzIGFueSBiYXJlIHRvcC1sZXZlbCBleHByZXNzaW9uIC0tIGluY2x1ZGluZyBhIG1vZHVsZSBkb2NzdHJp'
    || 'bmcgLS0gYXMKIyBtYXJrZG93biwgYW5kIHRoYXQgY291bnRzIGFzIGEgU3RyZWFtbGl0IGNvbW1hbmQsIGFmdGVyIHdoaWNoIHNldF9wYWdlX2NvbmZpZwoj'
    || 'IHJhaXNlcyBTdHJlYW1saXRBUElFeGNlcHRpb24gYW5kIHRoZSBwYWdlIGlzIGEgdHJhY2ViYWNrLgojCiMgVGhhdCBpcyBub3QgYSBoeXBvdGhldGljYWwu'
    || 'IFRoaXMgaG9zdCB1c2VkIHRvIGNhbGwgc2V0X3BhZ2VfY29uZmlnIGJlbG93IHRoZQojIHBhbmVsIHNwbGljZTsgc3BsaWNpbmcgYSBwYW5lbHMucHkgdGhh'
    || 'dCBvcGVuZWQgd2l0aCBhIGRvY3N0cmluZyByZW5kZXJlZCB0aGUKIyBkb2NzdHJpbmcgYXMgcGFnZSBwcm9zZSwgYW5kIHRoZSBhcHAgc2hpcHBlZCBhcyBh'
    || 'biBleGNlcHRpb24uIE5vdGhpbmcgaW4gdGhlCiMgcGlwZWxpbmUgY2F1Z2h0IGl0LCBiZWNhdXNlIG5vdGhpbmcgZXhlY3V0ZWQgdGhpcyBmaWxlIG91dHNp'
    || 'ZGUgU25vd2ZsYWtlIC0tCiMgZ2F1bnRsZXQgc3RlcCAxMCBwYXJzZXMgUEFORUxTIG91dCBvZiBpdCBhbmQgcnVucyB0aGUgU1FMIGl0c2VsZi4gYnVuZGxl'
    || 'LnB5IG5vdwojIGV4ZWN1dGVzIHRoaXMgbW9kdWxlIGFnYWluc3Qgc3R1YmJlZCBzdHJlYW1saXQvc25vd3BhcmsgbW9kdWxlcyBhbmQgYXNzZXJ0cwojIHNl'
    || 'dF9wYWdlX2NvbmZpZyBpcyB0aGUgZmlyc3QgY2FsbCwgd2hpY2ggaXMgdGhlIG9ubHkgY2hlY2sgdGhhdCB3b3VsZCBoYXZlLgpzdC5zZXRfcGFnZV9jb25m'
    || 'aWcocGFnZV90aXRsZT1TT0xVVElPTl9OQU1FLCBsYXlvdXQ9IndpZGUiKQoKIyDilIDilIAgTWFrZSBTdHJlYW1saXQgZ2V0IG91dCBvZiB0aGUgd2F5IOKU'
    || 'gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU'
    || 'gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAojIFRoZSBhcHAgaXMgb25lIGZ1bGwtYmxlZWQgUmVhY3QgcGFnZSBpbnNpZGUgY29tcG9uZW50cy5odG1s'
    || 'LiBXaXRob3V0IHRoaXMsCiMgU3RyZWFtbGl0IGZyYW1lcyBpdCBpbiBpdHMgb3duIGNocm9tZTogYSBkYXJrIHBhZ2UgYmFja2dyb3VuZCBhcm91bmQgdGhl'
    || 'CiMgaWZyYW1lLCB+NnJlbSBvZiB0b3AgcGFkZGluZywgYSBjZW50cmVkIG1heC13aWR0aCBibG9jayBjb250YWluZXIsIGFuZCB0aGUKIyB0b29sYmFyL2Zv'
    || 'b3Rlci4gVGhlIHJlc3VsdCByZWFkcyBhcyBhIHNtYWxsIHdpbmRvdyBmbG9hdGluZyBpbiBhIGJsYWNrIGJvcmRlciwKIyB3aGljaCBpcyBleGFjdGx5IGhv'
    || 'dyBpdCBzaGlwcGVkIGFuZCB3aGF0IHRoZSBmaXJzdCBzY3JlZW5zaG90IHNob3dlZC4KIwojIElubGluZSBDU1MgdGhyb3VnaCBzdC5tYXJrZG93biBpcyB0'
    || 'aGUgc3VwcG9ydGVkIHJvdXRlIC0tIFNub3dmbGFrZSdzIEN1c3RvbSBVSQojIHJlbGVhc2Ugbm90ZXMgbmFtZSAiQ3VzdG9tIEhUTUwgYW5kIENTUyB1c2lu'
    || 'ZyB1bnNhZmVfYWxsb3dfaHRtbD1UcnVlIGluCiMgc3QubWFya2Rvd24iIGV4cGxpY2l0bHkuIEl0IGlzIE5PVCBhIENTUCBwcm9ibGVtOiB0aGUgQ1NQIGJs'
    || 'b2NrcyBleHRlcm5hbAojIHJlc291cmNlcyBhbmQgZXZhbCgpLCBub3QgYW4gaW5saW5lIDxzdHlsZT4uCiMKIyBUaGlzIG11c3QgY29tZSBBRlRFUiBzZXRf'
    || 'cGFnZV9jb25maWcgKHdoaWNoIGhhcyB0byBiZSB0aGUgZmlyc3QgU3RyZWFtbGl0IGNhbGwpCiMgYW5kIEJFRk9SRSB0aGUgY29tcG9uZW50LCBvciB0aGUg'
    || 'cGFnZSBwYWludHMgZGFyayBhbmQgdGhlbiByZWZsb3dzLgpzdC5tYXJrZG93bigKICAgICIiIgogICAgPHN0eWxlPgogICAgICAvKiBLaWxsIHRoZSBkYXJr'
    || 'IGNhbnZhcyBhbmQgdGhlIHBhZGRpbmcgdGhhdCBjcmVhdGVzIHRoZSAid2luZG93ZWQiIGxvb2suICovCiAgICAgIC5zdEFwcCwgW2RhdGEtdGVzdGlkPSJz'
    || 'dEFwcFZpZXdDb250YWluZXIiXSwgW2RhdGEtdGVzdGlkPSJzdE1haW4iXSB7CiAgICAgICAgICBiYWNrZ3JvdW5kOiAjZjhmOGY4ICFpbXBvcnRhbnQ7CiAg'
    || 'ICAgIH0KICAgICAgW2RhdGEtdGVzdGlkPSJzdEhlYWRlciJdLCBbZGF0YS10ZXN0aWQ9InN0VG9vbGJhciJdLCBmb290ZXIgeyBkaXNwbGF5OiBub25lICFp'
    || 'bXBvcnRhbnQ7IH0KICAgICAgLyogQSBwYWdlIG1hcmdpbiByYXRoZXIgdGhhbiB6ZXJvOiB0aGUgY29tcG9uZW50IGtlZXBzIGl0cyBvd24gaW50ZXJuYWwK'
    || 'ICAgICAgICAgcGFkZGluZywgYW5kIHRoaXMgbGluZXMgdGhlIHByb21vdGlvbiBiYXIgdXAgd2l0aCB0aGUgY2FyZHMgaW5zaWRlIGl0LiAqLwogICAgICAu'
    || 'YmxvY2stY29udGFpbmVyLCBbZGF0YS10ZXN0aWQ9InN0TWFpbkJsb2NrQ29udGFpbmVyIl0gewogICAgICAgICAgcGFkZGluZzogMCAwIDIycHggIWltcG9y'
    || 'dGFudDsgbWF4LXdpZHRoOiAxMDAlICFpbXBvcnRhbnQ7CiAgICAgIH0KICAgICAgLyogTk9UIGBbZGF0YS10ZXN0aWQ9InN0VmVydGljYWxCbG9jayJdIHsg'
    || 'Z2FwOiAwIH1gLiBUaGF0IHdhcyBoZXJlIHRvIGNsb3NlCiAgICAgICAgIHRoZSBzdHJpcCBhYm92ZSB0aGUgY29tcG9uZW50LCBhbmQgaXQgYWxzbyBjb2xs'
    || 'YXBzZWQgdGhlIGZsZXggZ2FwIHRoYXQKICAgICAgICAgU3RyZWFtbGl0IHVzZXMgdG8gc3BhY2UgZXZlcnkgd2lkZ2V0IC0tIHdoaWNoIGRyZXcgZWFjaCBj'
    || 'YXB0aW9uIG9mIHRoZQogICAgICAgICBwcm9tb3Rpb24gYmFyIGRpcmVjdGx5IG9uIHRvcCBvZiB0aGUgbmV4dCBvbmUuIFNjb3BlIGl0IHRvIHRoZSBibG9j'
    || 'ayB0aGF0CiAgICAgICAgIGFjdHVhbGx5IGhvbGRzIHRoZSBpZnJhbWUuICovCiAgICAgIFtkYXRhLXRlc3RpZD0ic3RWZXJ0aWNhbEJsb2NrIl06aGFzKD4g'
    || 'W2RhdGEtdGVzdGlkPSJzdElGcmFtZSJdKSB7IGdhcDogMCAhaW1wb3J0YW50OyB9CiAgICAgIC8qIFRoZSBjb21wb25lbnQgaWZyYW1lIHNob3VsZCBiZSB0'
    || 'aGUgd2hvbGUgcGFnZSwgbm90IGEgY2VudHJlZCBjYXJkLiAqLwogICAgICBbZGF0YS10ZXN0aWQ9InN0SUZyYW1lIl0sIGlmcmFtZSB7IHdpZHRoOiAxMDAl'
    || 'ICFpbXBvcnRhbnQ7IGJvcmRlcjogMCAhaW1wb3J0YW50OyB9CiAgICAgIGlmcmFtZVtzcmNkb2MqPSJkYXRhLW9uZXNob3QtZGFzaGJvYXJkIl0gewogICAg'
    || 'ICAgICAgaGVpZ2h0OiBjYWxjKDEwMGR2aCAtIDEwMHB4KSAhaW1wb3J0YW50OwogICAgICAgICAgbWluLWhlaWdodDogNDgwcHg7CiAgICAgIH0KICAgICAg'
    || 'W2RhdGEtdGVzdGlkPSJzdE1haW4iXSB7IG92ZXJmbG93OiBhdXRvOyB9CgogICAgICAvKiDilIDilIAgcHJvbW90aW9uIGJhciDilIDilIDilIDilIDilIDi'
    || 'lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi'
    || 'lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKICAgICAgICAgTmF0aXZlIFN0cmVhbWxpdCB3aWRnZXRzLCBkcmFn'
    || 'Z2VkIGFzIGNsb3NlIHRvIHRoZSBSZWFjdCBkZXNpZ24gc3lzdGVtIGFzCiAgICAgICAgIENTUyBhbGxvd3MuIFRoZXkgY2Fubm90IGxpdmUgaW5zaWRlIHRo'
    || 'ZSBjb21wb25lbnQgKHNlZSBwcm9tb3Rpb25fYmFyKSwKICAgICAgICAgc28gdGhlIHNlYW0gaXMgcmVhbDsgdGhpcyBuYXJyb3dzIGl0LiBGb250IGFuZCBj'
    || 'b2xvdXIgb25seSAtLSBtYXJnaW5zIGFuZAogICAgICAgICBsaW5lLWhlaWdodCBhcmUgU3RyZWFtbGl0J3MgYnVzaW5lc3MsIGFuZCBvdmVycmlkaW5nIHRo'
    || 'ZW0gaXMgd2hhdCBicm9rZQogICAgICAgICB0aGUgbGF5b3V0IHRoZSBmaXJzdCB0aW1lLiAqLwogICAgICBbZGF0YS10ZXN0aWQ9InN0Q2FwdGlvbkNvbnRh'
    || 'aW5lciJdIHAgewogICAgICAgICAgZm9udC1zaXplOiAxMnB4ICFpbXBvcnRhbnQ7IGNvbG9yOiAjNmI2YjZiICFpbXBvcnRhbnQ7CiAgICAgIH0KICAgICAg'
    || 'LnN0QnV0dG9uIGJ1dHRvbiwKICAgICAgW2RhdGEtdGVzdGlkPSJzdEJhc2VCdXR0b24tc2Vjb25kYXJ5Il0sCiAgICAgIFtkYXRhLXRlc3RpZD0ic3RCYXNl'
    || 'QnV0dG9uLXByaW1hcnkiXSB7CiAgICAgICAgICBib3JkZXItcmFkaXVzOiAxMHB4ICFpbXBvcnRhbnQ7IGJvcmRlcjogMXB4IHNvbGlkICNlNWU1ZTcgIWlt'
    || 'cG9ydGFudDsKICAgICAgICAgIGJhY2tncm91bmQ6ICNmZmZmZmYgIWltcG9ydGFudDsgY29sb3I6ICMwYTIzNDIgIWltcG9ydGFudDsKICAgICAgICAgIGZv'
    || 'bnQtd2VpZ2h0OiA2NTAgIWltcG9ydGFudDsgZm9udC1zaXplOiAxMi41cHggIWltcG9ydGFudDsKICAgICAgICAgIHBhZGRpbmc6IDhweCAxNHB4ICFpbXBv'
    || 'cnRhbnQ7CiAgICAgICAgICBib3gtc2hhZG93OiAwIDFweCAzcHggcmdiYSgwLDAsMCwuMDYpLCAwIDJweCAxMnB4IHJnYmEoMCwwLDAsLjA0KSAhaW1wb3J0'
    || 'YW50OwogICAgICAgICAgdHJhbnNpdGlvbjogYm94LXNoYWRvdyAyMDBtcyBjdWJpYy1iZXppZXIoLjIyLDEsLjM2LDEpICFpbXBvcnRhbnQ7CiAgICAgIH0K'
    || 'ICAgICAgLnN0QnV0dG9uIGJ1dHRvbjpob3Zlcjpub3QoOmRpc2FibGVkKSwKICAgICAgW2RhdGEtdGVzdGlkPSJzdEJhc2VCdXR0b24tc2Vjb25kYXJ5Il06'
    || 'aG92ZXI6bm90KDpkaXNhYmxlZCkgewogICAgICAgICAgYm9yZGVyLWNvbG9yOiAjMDA4NGQ0ICFpbXBvcnRhbnQ7IGNvbG9yOiAjMDA4NGQ0ICFpbXBvcnRh'
    || 'bnQ7CiAgICAgICAgICBib3gtc2hhZG93OiAwIDJweCA4cHggcmdiYSgwLDAsMCwuMDgpLCAwIDhweCAyNHB4IHJnYmEoMCwwLDAsLjA2KSAhaW1wb3J0YW50'
    || 'OwogICAgICB9CiAgICAgIC5zdEJ1dHRvbiBidXR0b246ZGlzYWJsZWQgeyBvcGFjaXR5OiAuNDUgIWltcG9ydGFudDsgfQogICAgICBbZGF0YS10ZXN0aWQ9'
    || 'InN0QmFzZUJ1dHRvbi1wcmltYXJ5Il0sIC5zdEJ1dHRvbiBidXR0b25ba2luZD0icHJpbWFyeSJdIHsKICAgICAgICAgIGJhY2tncm91bmQ6ICMwMDg0ZDQg'
    || 'IWltcG9ydGFudDsgYm9yZGVyLWNvbG9yOiAjMDA4NGQ0ICFpbXBvcnRhbnQ7CiAgICAgICAgICBjb2xvcjogI2ZmZmZmZiAhaW1wb3J0YW50OwogICAgICB9'
    || 'CiAgICAgIGhyIHsgYm9yZGVyLWNvbG9yOiAjZTVlNWU3ICFpbXBvcnRhbnQ7IH0KICAgIDwvc3R5bGU+CiAgICAiIiIsCiAgICB1bnNhZmVfYWxsb3dfaHRt'
    || 'bD1UcnVlLAopCgpST1dfQ0FQID0gNTAwMCAgICMgYSBwYW5lbCB0aGF0IHdvdWxkIHJldHVybiBtb3JlIGlzIHRydW5jYXRlZCwgYW5kIHNheXMgc28KCiMg'
    || '4pSA4pSAIFRoZSBzb2x1dGlvbidzIHBhbmVscyDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi'
    || 'lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi'
    || 'lIDilIAKIyBQQU5FTFMgbWFwcyBhIHBhbmVsIG5hbWUgdG8gdGhlIFNRTCB0aGF0IGZpbGxzIGl0LiB7dGd0fSBpcyB0aGlzIGFwcCdzIG93bgojIHNjaGVt'
    || 'YSwgcmVzb2x2ZWQgYXQgcnVudGltZSByYXRoZXIgdGhhbiBiYWtlZCBpbiBhdCBidW5kbGUgdGltZSwgYmVjYXVzZSB0aGUKIyBidW5kbGUgaXMgYnVpbHQg'
    || 'YmVmb3JlIGFueW9uZSBoYXMgY2hvc2VuIGEgdGFyZ2V0IHNjaGVtYS4KIwojIEV2ZXJ5IHNvbHV0aW9uIGRlY2xhcmVzIGEgcGFuZWwgbmFtZWQgYGNvbnRl'
    || 'eHRgIHNlbGVjdGluZyBWX0JVSUxEX0NPTlRFWFQ6IHRoZQojIHNoZWxsIHJlYWRzIE1PREUgZnJvbSBpdCB0byBkZWNpZGUgd2hldGhlciB0byBzaG93IHRo'
    || 'ZSBTQU1QTEUgYmFubmVyLCBhbmQgYQojIG1pc3NpbmcgTU9ERSBtZWFucyBzZWVkZWQgbnVtYmVycyBjb3VsZCByZW5kZXIgdW5sYWJlbGxlZC4KIwojIEdh'
    || 'dW50bGV0IHN0ZXAgMTAgcGFyc2VzIHRoaXMgZGljdCBzdGF0aWNhbGx5IGFuZCBydW5zIGVhY2ggcXVlcnkgYWdhaW5zdCB0aGUKIyByZWFsIGJ1aWx0IHNj'
    || 'aGVtYSwgd2hpY2ggaXMgdGhlIG9ubHkgdGVzdCB0aGVzZSBxdWVyaWVzIGdldCAtLSB0aGV5IGxpdmUgaW4gYQojIHB5dGhvbiBmaWxlIHRoYXQgbmV2ZXIg'
    || 'ZXhlY3V0ZXMgb3V0c2lkZSBTbm93Zmxha2UuCiMKIyBBIHBhbmVsIG1heSBjYXJyeSA6bmFtZSBQTEFDRUhPTERFUlMgbmFtaW5nIGEgY29udHJvbCBkZWNs'
    || 'YXJlZCBpbiBDT05UUk9MUwojIGJlbG93LiBUaGV5IGFyZSByZXBsYWNlZCB3aXRoIHBvc2l0aW9uYWwgYmluZHMgYXQgcXVlcnkgdGltZSwgbmV2ZXIgYnkg'
    || 'c3RyaW5nCiMgaW50ZXJwb2xhdGlvbiAtLSBzZWUgcmVzb2x2ZV9wYW5lbF9zcWwoKS4gT25seSBERUNMQVJFRCBuYW1lcyBhcmUgZWxpZ2libGUsIHNvIGEK'
    || 'IyBgOjpWQVJDSEFSYCBjYXN0IG9yIGFueSBvdGhlciBzdHJheSBjb2xvbiBjYW4gbmV2ZXIgYmUgbWlzdGFrZW4gZm9yIG9uZS4KIwojIENPTlRST0xTIGRl'
    || 'ZmF1bHRzIHRvIGVtcHR5IEhFUkUsIGFib3ZlIHRoZSBzcGxpY2UsIHNvIHRoYXQgYSBzb2x1dGlvbidzIG93bgojIGBDT05UUk9MUyA9IFsuLi5dYCBpbiBw'
    || 'YW5lbHMucHkgKHNwbGljZWQgaW4gYmVsb3cpIG92ZXJyaWRlcyBpdCwgYW5kIGEgc29sdXRpb24KIyB0aGF0IGRlY2xhcmVzIG5vbmUga2VlcHMgZXhhY3Rs'
    || 'eSB0b2RheSdzIGJlaGF2aW91cjogbm8gd2lkZ2V0cywgbm8gYmluZHMsIGFuZCBhCiMgcGFuZWwgcXVlcnkgYnl0ZS1pZGVudGljYWwgdG8gd2hhdCBpdCB3'
    || 'YXMgYmVmb3JlIHRoaXMgbWVjaGFuaXNtIGV4aXN0ZWQuCiMKIyBFYWNoIGNvbnRyb2wgaXMgYSBsaXRlcmFsIGRpY3QsIGJlY2F1c2UgYnVuZGxlLnB5IHJl'
    || 'YWRzIHRoZXNlIHN0YXRpY2FsbHkgZm9yIHRoZQojIHNhbWUgcmVhc29uIGl0IHJlYWRzIFBBTkVMUyBzdGF0aWNhbGx5IC0tIHN0ZXAgMTAgbmVlZHMgdGhl'
    || 'IERFRkFVTFRTIHRvIGJlIGFibGUKIyB0byBleGVjdXRlIGEgcGFyYW1ldGVyaXNlZCBwYW5lbCBhdCBhbGw6CiMgICB7ImtleSI6ICJtZXRybyIsICAgICAg'
    || 'ICAjIHRoZSA6bmFtZSB1c2VkIGluIHBhbmVsIFNRTCwgYW5kIHRoZSBzZXNzaW9uX3N0YXRlIGtleQojICAgICJsYWJlbCI6ICJNZXRybyIsICAgICAgIyB3'
    || 'aGF0IHRoZSB3aWRnZXQgaXMgY2FsbGVkIG9uIHNjcmVlbgojICAgICJraW5kIjogInNlbGVjdCIsICAgICAgIyBzZWxlY3QgfCBzbGlkZXIgfCBudW1iZXIg'
    || 'fCB0ZXh0CiMgICAgImRlZmF1bHQiOiBOb25lLCAgICAgICAjIHZhbHVlIHVzZWQgYmVmb3JlIHRoZSB1c2VyIHRvdWNoZXMgYW55dGhpbmcsIGFuZCB0aGUK'
    || 'IyAgICAgICAgICAgICAgICAgICAgICAgICAgICMgdmFsdWUgc3RlcCAxMCBiaW5kcyB3aGVuIGl0IHJ1bnMgdGhlIHBhbmVsCiMgICAgIm9wdGlvbnNfc3Fs'
    || 'IjogIlNFTEVDVCBESVNUSU5DVCBNRVRSTyBGUk9NIHt0Z3R9LlZfWCBPUkRFUiBCWSAxIiwgICMgc2VsZWN0IG9ubHkKIyAgICAib3B0aW9ucyI6IFsiQSIs'
    || 'ICJCIl0sICMgc2VsZWN0IG9ubHksIHdoZW4gdGhlIGxpc3QgaXMgZml4ZWQgcmF0aGVyIHRoYW4gcXVlcmllZAojICAgICJtaW4iOiAwLCAibWF4IjogMTAw'
    || 'LCAic3RlcCI6IDEsICAgIyBzbGlkZXIvbnVtYmVyIG9ubHkKIyAgICAiaGVscCI6ICIuLi4ifSAgICAgICAgICMgb3B0aW9uYWwgb25lLWxpbmUgZXhwbGFu'
    || 'YXRpb24gdW5kZXIgdGhlIHdpZGdldApDT05UUk9MUyA9IFtdClBBTkVMUyA9IHsKICAgICMgVGhlIHNoZWxsIHJlYWRzIE1PREUgYW5kIFRJRVIgZnJvbSBo'
    || 'ZXJlIC0tIE1PREUgZm9yIHRoZSBTQU1QTEUgYmFubmVyLCBUSUVSCiAgICAjIGZvciB0aGUgRElTQ09WRVIvTElNSVRFRC9QUk9EVUNUSU9OIGxhZGRlci4g'
    || 'UmVxdWlyZWQgaW4gZXZlcnkgc29sdXRpb24uCiAgICAiY29udGV4dCI6ICJTRUxFQ1QgKiBGUk9NIHt0Z3R9LlZfQlVJTERfQ09OVEVYVCIsCgogICAgIyBU'
    || 'SEUgTEVBRC4gT25lIHJvdywgYWxyZWFkeSBhZ2dyZWdhdGVkLCBzbyB0aGUgaGVhZGxpbmUgc3Vydml2ZXMgdGhlIHJvdyBjYXAuCiAgICAjIEJPVEhfTiBp'
    || 'cyB0aGUgaW50ZXJzZWN0aW9uOiByZWxhdGlvbnMgdGhlIG9yY2hlc3RyYXRvciBjYW4gcmVhY2ggQU5EIHRoZQogICAgIyB3b3JrIGFjdHVhbGx5IHJlcXVp'
    || 'cmVzLiBFWENFU1NfTiBpcyB0aGUgd2hvbGUgcG9pbnQgb2YgdGhlIHNvbHV0aW9uLgogICAgImFyaXRobWV0aWMiOiAoCiAgICAgICAgIldJVEggcmVhY2gg'
    || 'QVMgKFNFTEVDVCBESVNUSU5DVCBSRUxBVElPTl9GUU4gQVMgRlFOICIKICAgICAgICAiICAgICAgICAgICAgICAgRlJPTSB7dGd0fS5WX0RFTEVHX09SQ0hF'
    || 'U1RSQVRPUl9SRUFDSCksICIKICAgICAgICAiICAgICByZXEgQVMgKFNFTEVDVCBESVNUSU5DVCBPQkpFQ1RfRlFOIEFTIEZRTiAiCiAgICAgICAgIiAgICAg'
    || 'ICAgICAgICBGUk9NIHt0Z3R9LlZfREVMRUdfUkVRVUlSRURfUFJJVklMRUdFUykgIgogICAgICAgICJTRUxFQ1QgKFNFTEVDVCBDT1VOVCgqKSBGUk9NIHJl'
    || 'YWNoKSBBUyBSRUFDSF9OLCAiCiAgICAgICAgIiAgICAgICAoU0VMRUNUIENPVU5UKCopIEZST00gcmVxKSBBUyBSRVFVSVJFRF9OLCAiCiAgICAgICAgIiAg'
    || 'ICAgICAoU0VMRUNUIENPVU5UKCopIEZST00gcmVhY2ggSU5ORVIgSk9JTiByZXEgVVNJTkcgKEZRTikpIEFTIEJPVEhfTiwgIgogICAgICAgICIgICAgICAg'
    || 'KFNFTEVDVCBDT1VOVCgqKSBGUk9NIHJlYWNoIFdIRVJFIEZRTiBOT1QgSU4gIgogICAgICAgICIgICAgICAgICAgIChTRUxFQ1QgRlFOIEZST00gcmVxKSkg'
    || 'QVMgRVhDRVNTX04sICIKICAgICAgICAjIFNvdXJjZWQgaGVyZSByYXRoZXIgdGhhbiBmcm9tIGEgZGlzY292ZXJ5IGhhbmRvZmYuIFRoZSBQYXlsb2FkIHR5'
    || 'cGUgdGhlCiAgICAgICAgIyBzaGVsbCBoYW5kcyB0aGUgYXBwIGhhcyBleGFjdGx5IHRocmVlIGZpZWxkcyAtLSBjb250ZXh0LCBwYW5lbHMsIGZhdGFsIC0t'
    || 'CiAgICAgICAgIyBzbyBhbnl0aGluZyByZWFkIG9mZiBhIGZvdXJ0aCBpcyBzaWxlbnRseSB1bmRlZmluZWQgZm9yZXZlci4gVGhlc2UgY29tZQogICAgICAg'
    || 'ICMgZnJvbSB0aGUgdmlld3MsIHdoaWNoIGlzIHRoZSBzYW1lIHBsYWNlIHRoZSBudW1iZXJzIGNvbWUgZnJvbS4KICAgICAgICAiICAgICAgIChTRUxFQ1Qg'
    || 'TUFYKFZBTFVFKSBGUk9NIHt0Z3R9LlZfREVMRUdfRklORElOR1MgV0hFUkUgU0VRID0gMSkgIgogICAgICAgICIgICAgICAgICAgIEFTIE9SQ0hFU1RSQVRP'
    || 'Ul9ST0xFLCAiCiAgICAgICAgIiAgICAgICAoU0VMRUNUIE1BWChERVRBSUwpIEZST00ge3RndH0uVl9ERUxFR19GSU5ESU5HUyBXSEVSRSBTRVEgPSAxKSAi'
    || 'CiAgICAgICAgIiAgICAgICAgICAgQVMgT1JDSF9TVEFURV9ERVRBSUwsICIKICAgICAgICAiICAgICAgIChTRUxFQ1QgQ09VTlQoKikgRlJPTSB7dGd0fS5W'
    || 'X0RFTEVHX0FOVElQQVRURVJOUyAiCiAgICAgICAgIiAgICAgICAgICAgV0hFUkUgRklORElORyA9ICdUQVNLX1JVTlNfQVNfVVNFUicpIEFTIEFTX1VTRVJf'
    || 'TiwgIgogICAgICAgICIgICAgICAgKFNFTEVDVCBDT1VOVCgqKSBGUk9NIHt0Z3R9LlZfREVMRUdfQU5USVBBVFRFUk5TICIKICAgICAgICAiICAgICAgICAg'
    || 'ICBXSEVSRSBGSU5ESU5HID0gJ1BST0NFRFVSRV9BVFRFTVBUU19OUE8nKSBBUyBQUk9DX0FUVEVNUFRfTiwgIgogICAgICAgICIgICAgICAgKFNFTEVDVCBD'
    || 'T1VOVCgqKSBGUk9NIHt0Z3R9LlZfREVMRUdfQU5USVBBVFRFUk5TICIKICAgICAgICAiICAgICAgICAgICBXSEVSRSBGSU5ESU5HID0gJ1RBU0tfT1dORURf'
    || 'QllfT1JDSEVTVFJBVE9SJykgQVMgT1dORURfQllfT1JDSF9OIgogICAgKSwKCiAgICAjIFRoZSBzdW1tYXJ5IHRoZSBidWlsZCBpdHNlbGYgd3JpdGVzLCBp'
    || 'bmNsdWRpbmcgdGhlIHJlZnVzYWwgcmVhc29uIHdoZW4gdGhlcmUKICAgICMgaXMgb25lLiBTaG93biB2ZXJiYXRpbSByYXRoZXIgdGhhbiByZS1kZXJpdmVk'
    || 'LCBzbyB0aGUgYXBwIGFuZCB0aGUgb25lLWZpbGUKICAgICMgc2NyaXB0IGNhbm5vdCBkaXNhZ3JlZSBhYm91dCB3aGF0IGhhcHBlbmVkLgogICAgImZpbmRp'
    || 'bmdzIjogIlNFTEVDVCAqIEZST00ge3RndH0uVl9ERUxFR19GSU5ESU5HUyBPUkRFUiBCWSBTRVEiLAoKICAgICMgRm9yIHJlYWRpbmcsIG5vdCBjb3VudGlu'
    || 'Zy4gSE9QU19GUk9NX09SQ0hFU1RSQVRPUiBpcyB0aGUgY29sdW1uIHRoYXQgdGVhY2hlcwogICAgIyB0aGUgbGVzc29uOiBpbmhlcml0YW5jZSwgbm90IGRp'
    || 'cmVjdCBncmFudHMsIGlzIGhvdyBhIHNlcnZpY2Ugcm9sZSBnb2VzIHdpZGUuCiAgICAicmVhY2giOiAoCiAgICAgICAgIlNFTEVDVCBSRUxBVElPTl9GUU4s'
    || 'IFBSSVZJTEVHRSwgT0JKRUNUX1RZUEUsIEdSQU5URURfVE9fUk9MRSwgIgogICAgICAgICJIT1BTX0ZST01fT1JDSEVTVFJBVE9SLCBIT1cgIgogICAgICAg'
    || 'ICJGUk9NIHt0Z3R9LlZfREVMRUdfT1JDSEVTVFJBVE9SX1JFQUNIICIKICAgICAgICAiT1JERVIgQlkgSE9QU19GUk9NX09SQ0hFU1RSQVRPUiBERVNDLCBS'
    || 'RUxBVElPTl9GUU4iCiAgICApLAoKICAgICMgV2hhdCB0aGUgZGJ0IHByb2plY3RzIHRoZW1zZWx2ZXMgZGVjbGFyZSB0aGV5IHRvdWNoLiBUaGlzIGlzIHRo'
    || 'ZSBmbG9vciB0aGUKICAgICMgZXhjZXNzIGlzIG1lYXN1cmVkIGFnYWluc3QuCiAgICAicmVxdWlyZWQiOiAoCiAgICAgICAgIlNFTEVDVCBPQkpFQ1RfRlFO'
    || 'LCBQUklWSUxFR0UsIFJPTEVfTkVFRCwgREVSSVZFRF9GUk9NICIKICAgICAgICAiRlJPTSB7dGd0fS5WX0RFTEVHX1JFUVVJUkVEX1BSSVZJTEVHRVMgT1JE'
    || 'RVIgQlkgT0JKRUNUX0ZRTiIKICAgICksCgogICAgIyBPd25lcidzLXJpZ2h0cyBib3VuZGFyeSB2aW9sYXRpb25zLiBPcmRlcmVkIHNvIEhJR0ggbGFuZHMg'
    || 'Zmlyc3Qgd2l0aG91dCB0aGUKICAgICMgYXBwIHJlLXNvcnRpbmcuCiAgICAiYW50aXBhdHRlcm5zIjogKAogICAgICAgICJTRUxFQ1QgRklORElORywgT0JK'
    || 'RUNUX0ZRTiwgT1dORURfQlksIFNFVkVSSVRZLCBXSFkgIgogICAgICAgICJGUk9NIHt0Z3R9LlZfREVMRUdfQU5USVBBVFRFUk5TICIKICAgICAgICAiT1JE'
    || 'RVIgQlkgREVDT0RFKFNFVkVSSVRZLCAnSElHSCcsIDEsICdNRURJVU0nLCAyLCAzKSwgT0JKRUNUX0ZRTiIKICAgICksCgogICAgIyBUaGUgY29weS1vdXQu'
    || 'IENhcnJpZXMgdGhlIFJFVk9LRSB0ZXh0LCB0aGUgRVhFQ1VURSBUQVNLIC4uLiBVU0lORyBDT05GSUcKICAgICMgdHJpZ2dlciBjYWxsIGFuZCB0aGUgSU5G'
    || 'T1JNQVRJT05fU0NIRU1BIHBvbGwgcXVlcnkgdG9nZXRoZXIsIGJlY2F1c2UgZ3JhbnRzCiAgICAjIHdpdGhvdXQgdGhlIHRyaWdnZXIvcG9sbCBjb250cmFj'
    || 'dCBpcyBoYWxmIGEgZGVsaXZlcmFibGUuCiAgICAicmVtZWRpYXRpb24iOiAiU0VMRUNUICogRlJPTSB7dGd0fS5WX0RFTEVHX1JFTUVESUFUSU9OIiwKCiAg'
    || 'ICAjIFRoZSBzdGFuZGluZyB3b3JrbG9hZCdzIG93biBvdXRwdXQuIEVtcHR5IG9uIGEgZnJlc2ggYnVpbGQsIHdoaWNoIGlzIGhvbmVzdAogICAgIyByYXRo'
    || 'ZXIgdGhhbiBhIGdhcCAtLSBvbmUgcm93IGxhbmRzIHBlciBkcmlmdCBjaGVjay4gVGhlIHBvaW50IGlzIHRoZSBTRVJJRVM6CiAgICAjIGEgcmVhY2ggbnVt'
    || 'YmVyIHRoYXQgZ3Jvd3MgYmV0d2VlbiBzbmFwc2hvdHMgaXMgYSBncmFudCBub2JvZHkgcmVjb21wdXRlZCB0aGUKICAgICMgYmxhc3QgcmFkaXVzIGZvci4K'
    || 'ICAgICJkcmlmdCI6ICgKICAgICAgICAiU0VMRUNUIFNOQVBTSE9UX0FULCBPUkNIRVNUUkFUT1JfUk9MRSwgUkVBQ0hfUkVMQVRJT05TLCAiCiAgICAgICAg'
    || 'IlJFUVVJUkVEX1JFTEFUSU9OUywgRVhDRVNTX1JFTEFUSU9OUywgQU5USVBBVFRFUk5TICIKICAgICAgICAiRlJPTSB7dGd0fS5ERUxFR19EUklGVF9ISVNU'
    || 'T1JZIE9SREVSIEJZIFNOQVBTSE9UX0FUIgogICAgKSwKCiAgICAjIEFjdGlvbnMgdGhpcyBzb2x1dGlvbiBjYW4gdGFrZSBhZ2FpbnN0IHRoZSBhY2NvdW50'
    || 'LCBhbmQgd2hhdCBpdCBoYXMgdGFrZW4uCiAgICAiYWN0aW9ucyI6ICJTRUxFQ1QgKiBGUk9NIHt0Z3R9LkFDVElPTl9SRUdJU1RSWSBPUkRFUiBCWSBDT0RF'
    || 'IiwKICAgICJhY3Rpb25fbG9nIjogKAogICAgICAgICJTRUxFQ1QgUkFOX0FULCBDT0RFLCBPVVRDT01FLCBERVRBSUwgRlJPTSB7dGd0fS5BQ1RJT05fTE9H'
    || 'ICIKICAgICAgICAiT1JERVIgQlkgUkFOX0FUIERFU0MiCiAgICApLAp9CgojIFRhbGxlciB0aGFuIHRoZSBnb3Zlcm5hbmNlIGFwcDogdGhlIGFyaXRobWV0'
    || 'aWMgcGFuZWwgYW5kIHRoZSB0b3BvbG9neSBkaWFncmFtCiMgYm90aCBuZWVkIHZlcnRpY2FsIHJvb20sIGFuZCB0aGUgcmVtZWRpYXRpb24gU1FMIGlzIHJl'
    || 'YWQgcmF0aGVyIHRoYW4gc2tpbW1lZC4KSEVJR0hUID0gMTUwMAoKIyDilIDilIAgU2hhcmVkIGFjdGlvbiBwYW5lbHMg4pSA4pSA4pSA4pSA4pSA4pSA4pSA'
    || '4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA'
    || '4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACiMgRXZlcnkgYnVpbGQgd2l0aCB0aGUgYWN0aW9uIGZyYW1ld29yayBjcmVh'
    || 'dGVzIFZfQUNUSU9OUyBhbmQgQUNUSU9OX0xPRzsgYnVpbGRzCiMgd2l0aG91dCBpdCBzaW1wbHkgcHJvZHVjZSBhICJkb2VzIG5vdCBleGlzdCIgZXJyb3Is'
    || 'IHdoaWNoIHRoZSBSZWFjdCBzaGVsbAojIHJlbmRlcnMgYXMgdGhlIHN0YW5kYXJkIG5vdC1idWlsdCBzdGF0ZS4gQWRkZWQgaGVyZSByYXRoZXIgdGhhbiBp'
    || 'biBldmVyeQojIHBhbmVscy5weSBzbyBhIG5ldyBzb2x1dGlvbiBnZXRzIHRoZW0gZm9yIGZyZWUuClBBTkVMU1siYWN0aW9ucyJdID0gKAogICAgIlNFTEVD'
    || 'VCBDT0RFLCBMQUJFTCwgVElFUiwgRUZGRUNULCBFU1RfQ1JFRElUUywgU1RBVEVNRU5UUywgIgogICAgIlVORE9fU1RBVEVNRU5UUywgVElNRVNfUlVOLCBU'
    || 'SU1FU19VTkRPTkUgRlJPTSB7dGd0fS5WX0FDVElPTlMiCikKUEFORUxTWyJhY3Rpb25fbG9nIl0gPSAoCiAgICAiU0VMRUNUIENPREUsIFNUQVRVUywgU1RB'
    || 'VEVNRU5UU19SVU4sIFNUQVJURURfQVQsIEZJTklTSEVEX0FULCBFUlJPUiAiCiAgICAiRlJPTSB7dGd0fS5BQ1RJT05fTE9HIE9SREVSIEJZIFNUQVJURURf'
    || 'QVQgREVTQyBMSU1JVCAxMCIKKQoKIyDilIDilIAgU2hhcmVkIFBPQyBzdWNjZXNzIHBhbmVscyDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi'
    || 'lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi'
    || 'lIDilIDilIDilIDilIDilIAKIyBCb3RoIHZpZXdzIGFyZSBjcmVhdGVkIGJ5IGV2ZXJ5IGJ1aWxkLCBpbmNsdWRpbmcgYnVpbGRzIHdob3NlIHNvbHV0aW9u'
    || 'CiMgZGVjbGFyZWQgbm8gY3JpdGVyaWEgLS0gdGhvc2UgZ2V0IHRoZSBzaW5nbGUgIk5PIFNVQ0NFU1MgQ1JJVEVSSUEgREVDTEFSRUQiCiMgcm93IHJhdGhl'
    || 'ciB0aGFuIGFuIGVtcHR5IHJlc3VsdCwgc28gdGhlIHRhYiBuZXZlciByZW5kZXJzIGJsYW5rIGFuZCBibGFuayBpcwojIG5ldmVyIG1pc3Rha2VuIGZvciB6'
    || 'ZXJvLgojCiMgUmVhZGluZyBWX1BPQ19TQ09SRUNBUkQgcmUtZXhlY3V0ZXMgdGhlIHRhcmdldCBhbmQgYWN0dWFsIHNjYWxhcnMgaW5saW5lZCBpbnRvCiMg'
    || 'aXQsIHNvIHRoZXNlIHR3byBxdWVyaWVzIGFyZSBob3cgdGhlIG51bWJlcnMgc3RheSBsaXZlLiBUaGF0IGFsc28gbWVhbnMgdGhleQojIGFyZSB0aGUgbW9z'
    || 'dCBleHBlbnNpdmUgcGFuZWxzIGhlcmUsIGFuZCB0aGUgb25seSBvbmVzIHdob3NlIGNvc3Qgc2NhbGVzIHdpdGgKIyB0aGUgY3JpdGVyaWEgYSBzb2x1dGlv'
    || 'biBkZWNsYXJlcy4KUEFORUxTWyJwb2Nfc2NvcmVjYXJkIl0gPSAoCiAgICAiU0VMRUNUIENPREUsIExBQkVMLCBXSFlfSVRfTUFUVEVSUywgVEFSR0VULCBB'
    || 'Q1RVQUwsIFVOSVRTLCBDT01QQVJFLCBCQVNJUywgIgogICAgIlRBUkdFVF9ERVJJVkFUSU9OLCBTVEFURSwgV0hZX05PVF9FVkFMVUFURUQsIFJFU09MVkVT'
    || 'X1dIRU4sIEFSSVRITUVUSUMsICIKICAgICJDT01QQVJBQklMSVRZIEZST00ge3RndH0uVl9QT0NfU0NPUkVDQVJEICIKICAgICMgTk9UX01FVCBmaXJzdC4g'
    || 'QSBzY29yZWNhcmQgc29ydGVkIGJ5IGNvZGUgYnVyaWVzIHRoZSBvbmUgcm93IHRoZSByZWFkZXIKICAgICMgbW9zdCBuZWVkcywgYW5kIFBFTkRJTkcgc29y'
    || 'dGluZyBhYm92ZSBhIGZhaWx1cmUgcmVhZHMgYXMgcmVhc3N1cmFuY2UuCiAgICAiT1JERVIgQlkgQ0FTRSBTVEFURSBXSEVOICdOT1RfTUVUJyBUSEVOIDAg'
    || 'V0hFTiAnUEVORElORycgVEhFTiAxICIKICAgICJXSEVOICdNRVQnIFRIRU4gMiBFTFNFIDMgRU5ELCBDT0RFIgopClBBTkVMU1sicG9jX3ZlcmRpY3QiXSA9'
    || 'ICgKICAgICJTRUxFQ1QgTUVULCBOT1RfTUVULCBQRU5ESU5HLCBOQSwgU0NPUkVELCBIRUFETElORSwgVkVSRElDVCwgUkVBRF9USElTICIKICAgICJGUk9N'
    || 'IHt0Z3R9LlZfUE9DX1ZFUkRJQ1QiCikKCgpkZWYgdGFyZ2V0X3NjaGVtYShzZXNzaW9uKSAtPiBzdHI6CiAgICAiIiJUaGUgc2NoZW1hIHRoaXMgU3RyZWFt'
    || 'bGl0IG9iamVjdCBsaXZlcyBpbi4KCiAgICBTdHJlYW1saXQgaW4gU25vd2ZsYWtlIHJ1bnMgd2l0aCB0aGUgYXBwJ3Mgb3duIGRhdGFiYXNlIGFuZCBzY2hl'
    || 'bWEgY3VycmVudCwKICAgIHNvIHRoaXMgaXMgcmVsaWFibGUgYW5kIG5lZWRzIG5vIGJ1aWxkLXRpbWUgc3Vic3RpdHV0aW9uLiBRdW90ZWQgaWRlbnRpZmll'
    || 'cnMKICAgIGNvbWUgYmFjayB3aXRoIHF1b3RlcyBhbHJlYWR5LCB3aGljaCBpcyB3aHkgdGhleSBhcmUgc3RyaXBwZWQuCiAgICAiIiIKICAgIGNhY2hlZCA9'
    || 'IHN0LnNlc3Npb25fc3RhdGUuZ2V0KCJvbmVzaG90X3RhcmdldF9zY2hlbWEiKQogICAgaWYgY2FjaGVkOgogICAgICAgIHJldHVybiBjYWNoZWQKICAgIHJv'
    || 'dyA9IHNlc3Npb24uc3FsKAogICAgICAgICJTRUxFQ1QgQ1VSUkVOVF9EQVRBQkFTRSgpIEFTIEQsIENVUlJFTlRfU0NIRU1BKCkgQVMgUyIpLmNvbGxlY3Qo'
    || 'KVswXQogICAgZGIsIHNjID0gKHJvd1siRCJdIG9yICIiKS5zdHJpcCgnIicpLCAocm93WyJTIl0gb3IgIiIpLnN0cmlwKCciJykKICAgIHRhcmdldCA9IGRi'
    || 'ICsgIi4iICsgc2MKICAgIHN0LnNlc3Npb25fc3RhdGVbIm9uZXNob3RfdGFyZ2V0X3NjaGVtYSJdID0gdGFyZ2V0CiAgICByZXR1cm4gdGFyZ2V0CgoKZGVm'
    || 'IGFwcF9uYXZpZ2F0aW9uKHNlc3Npb24sIHRhcmdldCk6CiAgICBjYWNoZV9rZXkgPSAib25lc2hvdF92aWV3ZXI6IiArIHRhcmdldCArICIuIiArIEFQUF9P'
    || 'QkpFQ1QKICAgIGlmIGNhY2hlX2tleSBub3QgaW4gc3Quc2Vzc2lvbl9zdGF0ZToKICAgICAgICB0cnk6CiAgICAgICAgICAgIGlmIG5vdCByZS5mdWxsbWF0'
    || 'Y2gociJbQS1aYS16MC05X10rXC5bQS1aYS16MC05X10rIiwgdGFyZ2V0KSBvciBub3QgcmUuZnVsbG1hdGNoKHIiW0EtWmEtejAtOV9dKyIsIEFQUF9PQkpF'
    || 'Q1QpOgogICAgICAgICAgICAgICAgcmV0dXJuIHt9CiAgICAgICAgICAgIGFjY291bnQgPSBzZXNzaW9uLnNxbCgiU0VMRUNUIENVUlJFTlRfT1JHQU5JWkFU'
    || 'SU9OX05BTUUoKSBBUyBPUkcsIENVUlJFTlRfQUNDT1VOVF9OQU1FKCkgQVMgQUNDT1VOVCIpLmNvbGxlY3QoKVswXQogICAgICAgICAgICBhcHBzID0gc2Vz'
    || 'c2lvbi5zcWwoIlNIT1cgU1RSRUFNTElUUyBJTiBTQ0hFTUEgIiArIHRhcmdldCkuY29sbGVjdCgpCiAgICAgICAgICAgIGFwcCA9IG5leHQoKHJvdy5hc19k'
    || 'aWN0KCkgZm9yIHJvdyBpbiBhcHBzIGlmIHN0cihyb3cuYXNfZGljdCgpLmdldCgibmFtZSIsICIiKSkudXBwZXIoKSA9PSBBUFBfT0JKRUNULnVwcGVyKCkp'
    || 'LCBOb25lKQogICAgICAgICAgICBwYXJ0cyA9IFtzdHIoYWNjb3VudFsiT1JHIl0pLmxvd2VyKCksIHN0cihhY2NvdW50WyJBQ0NPVU5UIl0pLmxvd2VyKCks'
    || 'IHN0cigoYXBwIG9yIHt9KS5nZXQoInVybF9pZCIsICIiKSldCiAgICAgICAgICAgIGlmIG5vdCBhbGwocmUuZnVsbG1hdGNoKHIiW0EtWmEtejAtOV8tXSsi'
    || 'LCB2YWx1ZSkgZm9yIHZhbHVlIGluIHBhcnRzKToKICAgICAgICAgICAgICAgIHJldHVybiB7fQogICAgICAgICAgICBzdC5zZXNzaW9uX3N0YXRlW2NhY2hl'
    || 'X2tleV0gPSAiaHR0cHM6Ly9hcHAuc25vd2ZsYWtlLmNvbS9zdHJlYW1saXQvIiArIHBhcnRzWzBdICsgIi8iICsgcGFydHNbMV0gKyAiLyMvYXBwcy8iICsg'
    || 'cGFydHNbMl0KICAgICAgICAgICAgc3Quc2Vzc2lvbl9zdGF0ZVtjYWNoZV9rZXkgKyAiOmJ1aWxkZXIiXSA9ICJodHRwczovL2FwcC5zbm93Zmxha2UuY29t'
    || 'LyIgKyBwYXJ0c1swXSArICIvIiArIHBhcnRzWzFdICsgIi8jL3N0cmVhbWxpdC1hcHBzLyIgKyB0YXJnZXQgKyAiLiIgKyBBUFBfT0JKRUNUCiAgICAgICAg'
    || 'ZXhjZXB0IEV4Y2VwdGlvbjoKICAgICAgICAgICAgcmV0dXJuIHt9CiAgICByZXR1cm4geyJ2aWV3ZXJfdXJsIjogc3Quc2Vzc2lvbl9zdGF0ZVtjYWNoZV9r'
    || 'ZXldLCAiYnVpbGRlcl91cmwiOiBzdC5zZXNzaW9uX3N0YXRlLmdldChjYWNoZV9rZXkgKyAiOmJ1aWxkZXIiLCAiIil9CgoKZGVmIGludmFsaWRhdGVfcGFu'
    || 'ZWxfY2FjaGUoKToKICAgIHN0LnNlc3Npb25fc3RhdGUucG9wKCJvbmVzaG90X3BhbmVsX2NhY2hlIiwgTm9uZSkKCgpkZWYgY2FjaGVkX3BhbmVsKHNlc3Np'
    || 'b24sIHNxbCwgYmluZHMsIHR0bD0zMCk6CiAgICBlbnRyaWVzID0gc3Quc2Vzc2lvbl9zdGF0ZS5zZXRkZWZhdWx0KCJvbmVzaG90X3BhbmVsX2NhY2hlIiwg'
    || 'e30pCiAgICBrZXkgPSBqc29uLmR1bXBzKFtzcWwsIGJpbmRzXSwgc29ydF9rZXlzPVRydWUsIGRlZmF1bHQ9c3RyKQogICAgbm93ID0gbW9ub3RvbmljKCkK'
    || 'ICAgIGVudHJ5ID0gZW50cmllcy5nZXQoa2V5KQogICAgaWYgZW50cnkgYW5kIG5vdyAtIGVudHJ5WzBdIDwgdHRsOgogICAgICAgIHJldHVybiBjb3B5LmRl'
    || 'ZXBjb3B5KGVudHJ5WzFdKQogICAgZnJhbWUgPSBzZXNzaW9uLnNxbChzcWwsIHBhcmFtcz1iaW5kcykgaWYgYmluZHMgZWxzZSBzZXNzaW9uLnNxbChzcWwp'
    || 'CiAgICByb3dzID0gW3Jvdy5hc19kaWN0KCkgZm9yIHJvdyBpbiBmcmFtZS5saW1pdChST1dfQ0FQICsgMSkuY29sbGVjdCgpXQogICAgcGFuZWwgPSB7InJv'
    || 'd3MiOiBqc29uLmxvYWRzKGpzb24uZHVtcHMocm93c1s6Uk9XX0NBUF0sIGRlZmF1bHQ9c3RyKSl9CiAgICBpZiBsZW4ocm93cykgPiBST1dfQ0FQOgogICAg'
    || 'ICAgIHBhbmVsWyJ0cnVuY2F0ZWQiXSA9IFJPV19DQVAKICAgIGVudHJpZXNba2V5XSA9IChub3csIHBhbmVsKQogICAgd2hpbGUgbGVuKGVudHJpZXMpID4g'
    || 'ODA6CiAgICAgICAgZW50cmllcy5wb3AobmV4dChpdGVyKGVudHJpZXMpKSkKICAgIHJldHVybiBjb3B5LmRlZXBjb3B5KHBhbmVsKQoKCmRlZiByZXNvbHZl'
    || 'X3BhbmVsX3NxbChzcWw6IHN0ciwgcGFyYW1zOiBkaWN0KToKICAgICIiIihzcWxfd2l0aF9wb3NpdGlvbmFsX2JpbmRzLCBiaW5kcykgZm9yIG9uZSBwYW5l'
    || 'bC4KCiAgICBCSU5EUywgTk9UIElOVEVSUE9MQVRJT04uIEEgY29udHJvbCdzIHZhbHVlIGlzIGNob3NlbiBieSB3aG9ldmVyIGlzIGxvb2tpbmcgYXQKICAg'
    || 'IHRoZSBwYWdlLCBzbyBwYXN0aW5nIGl0IGludG8gdGhlIFNRTCB0ZXh0IHdvdWxkIGJlIGFuIGluamVjdGlvbiBob2xlIGluIGEgcXVlcnkKICAgIHRoYXQg'
    || 'cnVucyB3aXRoIHRoZSBhcHAgb3duZXIncyBwcml2aWxlZ2VzLiBFdmVyeSB2YWx1ZSBsZWF2ZXMgaGVyZSBhcyBhIGA/YC4KCiAgICBPTkxZIERFQ0xBUkVE'
    || 'IE5BTUVTIEFSRSBFTElHSUJMRS4gVGhlIHBhdHRlcm4gaXMgYnVpbHQgZnJvbSB0aGUga2V5cyBvZiBgcGFyYW1zYAogICAgcmF0aGVyIHRoYW4gZnJvbSBh'
    || 'IGdlbmVyaWMgYDpcXHcrYCwgd2hpY2ggaXMgd2hhdCBtYWtlcyBgOjpWQVJDSEFSYCBzYWZlOiB0aGUKICAgIHNlY29uZCBjb2xvbiBvZiBhIGNhc3QgY2Fu'
    || 'bm90IGJlZ2luIGEgZGVjbGFyZWQgbmFtZSwgYW5kIHRoZSBuZWdhdGl2ZSBsb29rYmVoaW5kCiAgICByZWZ1c2VzIGl0IGEgc2Vjb25kIHRpbWUuIEFueXRo'
    || 'aW5nIGVsc2UgY29sb24tc2hhcGVkIGluIGEgcGFuZWwgLS0gYSBzdGFnZSBwYXRoLAogICAgYSBKU09OIHRyYXZlcnNhbCAtLSBpcyBsZWZ0IHVudG91Y2hl'
    || 'ZCBiZWNhdXNlIGl0IHdhcyBuZXZlciBkZWNsYXJlZC4KCiAgICBMb25nZXN0IG5hbWUgZmlyc3Qgc28gdGhhdCBkZWNsYXJpbmcgYm90aCBgbWV0cm9gIGFu'
    || 'ZCBgbWV0cm9fY29kZWAgY2Fubm90IGhhdmUKICAgIHRoZSBzaG9ydGVyIG9uZSBlYXQgdGhlIGZyb250IG9mIHRoZSBsb25nZXIuCgogICAgVEhJUyBGVU5D'
    || 'VElPTiBJUyBEVVBMSUNBVEVEIGluIGhhcm5lc3MvYnVuZGxlLnB5LiBJdCBoYXMgdG8gYmU6IHRoaXMgZmlsZSBpcwogICAgc3RhbmRhbG9uZSBjb2RlIHRo'
    || 'YXQgcnVucyBpbnNpZGUgU25vd2ZsYWtlIGFuZCBjYW5ub3QgaW1wb3J0IHRoZSBoYXJuZXNzLCB3aGlsZQogICAgZ2F1bnRsZXQgc3RlcCAxMCBhbmQgdGhl'
    || 'IHJlbmRlciBjaGVjayBuZWVkIHRoZSBpZGVudGljYWwgc3Vic3RpdHV0aW9uIHRvIHRlc3QKICAgIHdoYXQgdGhlIGFwcCB3aWxsIHJlYWxseSBydW4uIElm'
    || 'IHlvdSBjaGFuZ2Ugb25lLCBjaGFuZ2UgYm90aCAtLSB0aGUgcGFpciBpcwogICAgY292ZXJlZCBieSBhIHRlc3QgaW4gYnVuZGxlLnB5IHRoYXQgY29tcGFy'
    || 'ZXMgdGhlbS4KICAgICIiIgogICAgaWYgbm90IHBhcmFtczoKICAgICAgICByZXR1cm4gc3FsLCBbXQogICAgbmFtZXMgPSBzb3J0ZWQocGFyYW1zLCBrZXk9'
    || 'bGVuLCByZXZlcnNlPVRydWUpCiAgICBwYXQgPSByZS5jb21waWxlKHIiKD88ITopOigiICsgInwiLmpvaW4ocmUuZXNjYXBlKG4pIGZvciBuIGluIG5hbWVz'
    || 'KSArIHIiKVxiIikKICAgIGJpbmRzID0gW10KCiAgICBkZWYgc3ViKG0pOgogICAgICAgIGJpbmRzLmFwcGVuZChwYXJhbXNbbS5ncm91cCgxKV0pCiAgICAg'
    || 'ICAgcmV0dXJuICI/IgoKICAgIHJldHVybiBwYXQuc3ViKHN1Yiwgc3FsKSwgYmluZHMKCgpkZWYgcnVuX3BhbmVscyhzZXNzaW9uLCB0Z3Q6IHN0ciwgcGFy'
    || 'YW1zOiBkaWN0ID0gTm9uZSkgLT4gZGljdDoKICAgICIiIlJ1biBldmVyeSBwYW5lbCwgb25lIGZhaWx1cmUgY29zdGluZyBvbmUgcGFuZWwuCgogICAgRmV0'
    || 'Y2hlcyBST1dfQ0FQICsgMSByb3dzIHNvIHRoYXQgaGl0dGluZyB0aGUgY2FwIGlzIERFVEVDVEFCTEUuIFNlbGVjdGluZwogICAgZXhhY3RseSBST1dfQ0FQ'
    || 'IGlzIGluZGlzdGluZ3Vpc2hhYmxlIGZyb20gInRoZSBhbnN3ZXIgaGFwcGVuZWQgdG8gYmUgNTAwMCIsCiAgICBhbmQgYSBjYXJkIHRoYXQgY291bnRzIHJv'
    || 'd3MgY2xpZW50LXNpZGUgdG8gcHJvZHVjZSBhIGhlYWRsaW5lIC0tICI0MTIgdGFibGVzCiAgICBhcmUgZWxpZ2libGUiIC0tIHdvdWxkIHRoZW4gcmVwb3J0'
    || 'IHRoZSBjYXAgYXMgaWYgaXQgd2VyZSB0aGUgdG90YWwuIFRoZSBleHRyYQogICAgcm93IGlzIGRyb3BwZWQgYmVmb3JlIHRoZSBwYXlsb2FkIGlzIGJ1aWx0'
    || 'OyBvbmx5IHRoZSBmbGFnIHN1cnZpdmVzLgoKICAgIGBwYXJhbXNgIGNhcnJpZXMgdGhlIGN1cnJlbnQgdmFsdWUgb2YgZXZlcnkgZGVjbGFyZWQgY29udHJv'
    || 'bC4gVGhpcyBydW5zIG9uIEVWRVJZCiAgICBTdHJlYW1saXQgcmVydW4sIHdoaWNoIGlzIHRoZSB3aG9sZSByZWFzb24gYSBjb250cm9sIGNhbiBjaGFuZ2Ug'
    || 'd2hhdCB0aGUgUmVhY3QKICAgIHBhZ2Ugc2hvd3M6IHRoZSBpZnJhbWUgY2Fubm90IHJlLXF1ZXJ5LCBidXQgdGhlIGhvc3QgcmUtcXVlcmllcyBmb3IgaXQg'
    || 'YW5kIGhhbmRzCiAgICBkb3duIGEgZnJlc2ggcGF5bG9hZC4gQSBzb2x1dGlvbiB0aGF0IGRlY2xhcmVzIG5vIGNvbnRyb2xzIHBhc3NlcyBhbiBlbXB0eSBk'
    || 'aWN0CiAgICBhbmQgdGFrZXMgdGhlIG5vLWJpbmRzIHBhdGggYmVsb3csIHNvIGl0cyBxdWVyeSBpcyB1bmNoYW5nZWQuCiAgICAiIiIKICAgIHBhcmFtcyA9'
    || 'IHBhcmFtcyBvciB7fQogICAgb3V0ID0ge30KICAgIGZvciBuYW1lLCBzcWwgaW4gUEFORUxTLml0ZW1zKCk6CiAgICAgICAgdHJ5OgogICAgICAgICAgICBx'
    || 'LCBiaW5kcyA9IHJlc29sdmVfcGFuZWxfc3FsKHNxbC5yZXBsYWNlKCJ7dGd0fSIsIHRndCksIHBhcmFtcykKICAgICAgICAgICAgIyBUaGUgbm8tYmluZHMg'
    || 'Y2FsbCBpcyBrZXB0IGRpc3RpbmN0IHJhdGhlciB0aGFuIGFsd2F5cyBwYXNzaW5nCiAgICAgICAgICAgICMgcGFyYW1zPVtdOiBldmVyeSBleGlzdGluZyBw'
    || 'YW5lbCBnb2VzIGRvd24gdGhpcyBwYXRoIHVudG91Y2hlZCwgc28gdGhpcwogICAgICAgICAgICAjIG1lY2hhbmlzbSBjYW5ub3QgcmVncmVzcyBhIHNvbHV0'
    || 'aW9uIHRoYXQgbmV2ZXIgb3B0ZWQgaW50byBpdC4KICAgICAgICAgICAgb3V0W25hbWVdID0gY2FjaGVkX3BhbmVsKHNlc3Npb24sIHEsIGJpbmRzKQogICAg'
    || 'ICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZXhjOgogICAgICAgICAgICBvdXRbbmFtZV0gPSB7ImVycm9yIjogdHlwZShleGMpLl9fbmFtZV9fICsgIjogIiAr'
    || 'IHN0cihleGMpWzo0MDBdfQogICAgcmV0dXJuIG91dAoKCmRlZiBidWlsZF9odG1sKHBheWxvYWQ6IGRpY3QpIC0+IHN0cjoKICAgIGpzID0gYmFzZTY0LmI2'
    || 'NGRlY29kZShBUFBfSlNfQjY0KS5kZWNvZGUoInV0Zi04IikKICAgIGNzcyA9IGJhc2U2NC5iNjRkZWNvZGUoQVBQX0NTU19CNjQpLmRlY29kZSgidXRmLTgi'
    || 'KQogICAgZGF0YSA9IGpzb24uZHVtcHMocGF5bG9hZCkKICAgICMgVGhlIG9ubHkgZXNjYXBlIHRoYXQgbWF0dGVycyB3aGVuIGlubGluaW5nIGludG8gPHNj'
    || 'cmlwdD46IHRoZSBzZXF1ZW5jZQogICAgIyA8L3NjcmlwdCB3b3VsZCBlbmQgdGhlIHRhZyBlYXJseS4gSXQgY2FuIGFwcGVhciBpbiBKUyBvbmx5IGluc2lk'
    || 'ZSBhIHN0cmluZwogICAgIyBvciBhIGNvbW1lbnQsIHNvIG5ldXRyYWxpc2luZyBpdCBjYW5ub3QgY2hhbmdlIGJlaGF2aW91ci4KICAgIGpzID0ganMucmVw'
    || 'bGFjZSgiPC9zY3JpcHQiLCAiPFxcL3NjcmlwdCIpCiAgICBkYXRhID0gZGF0YS5yZXBsYWNlKCI8LyIsICI8XFwvIikKICAgIHJldHVybiAoCiAgICAgICAg'
    || 'IjwhZG9jdHlwZSBodG1sPjxodG1sPjxoZWFkPjxtZXRhIGNoYXJzZXQ9J3V0Zi04Jz48c3R5bGU+IiArIGNzcwogICAgICAgICsgIjwvc3R5bGU+PC9oZWFk'
    || 'Pjxib2R5IGRhdGEtb25lc2hvdC1kYXNoYm9hcmQ+PGRpdiBpZD0ncm9vdCc+PC9kaXY+IgogICAgICAgICsgIjxzY3JpcHQ+d2luZG93WyIgKyBqc29uLmR1'
    || 'bXBzKEdMT0JBTF9OQU1FKSArICJdID0gIiArIGRhdGEgKyAiOzwvc2NyaXB0PiIKICAgICAgICArICI8c2NyaXB0PiIgKyBqcyArICI8L3NjcmlwdD48L2Jv'
    || 'ZHk+PC9odG1sPiIKICAgICkKCgpUSUVSX09SREVSID0gWyJTQU1QTEUiLCAiTElNSVRFRCIsICJQUk9EVUNUSU9OIl0KVElFUl9CTFVSQiA9IHsKICAgICJT'
    || 'QU1QTEUiOiAgICAgIlNlZWRlZCBkYXRhLiBTYWZlIHRvIHJ1biByZXBlYXRlZGx5OyBwcm92ZXMgdGhlIHNoYXBlIHdpdGhvdXQgIgogICAgICAgICAgICAg'
    || 'ICAgICAidG91Y2hpbmcgYW55dGhpbmcgcmVhbC4iLAogICAgIkxJTUlURUQiOiAgICAiWW91ciBkYXRhLCBkZWxpYmVyYXRlbHkgYm91bmRlZCDigJQgYSBz'
    || 'dWJzZXQsIGEgY2FwLCBvciBhIHNpbmdsZSAiCiAgICAgICAgICAgICAgICAgICJvYmplY3QuIE1lYW50IHRvIGJlIHJldmVyc2libGUuIiwKICAgICJQUk9E'
    || 'VUNUSU9OIjogIllvdXIgZGF0YSwgYXQgZnVsbCBzY29wZS4gUmVhZCB0aGUgdW5kbyBsaW5lIGJlZm9yZSB5b3UgcnVuIGl0LiIsCn0KCgpkZWYgZm10X2Ny'
    || 'ZWRpdHModikgLT4gc3RyOgogICAgIiIiMC4wMiwgbm90IDAuMDIwMDAwLgoKICAgIEVTVF9DUkVESVRTIGlzIE5VTUJFUigzOCw2KSBzbyB0aGF0IGZyYWN0'
    || 'aW9uYWwgY3JlZGl0cyBzdXJ2aXZlIHRoZSByb3VuZCB0cmlwLAogICAgYW5kIHN0cigpIG9uIGEgRGVjaW1hbCBrZWVwcyBldmVyeSB0cmFpbGluZyB6ZXJv'
    || 'LiBTaXggZGVjaW1hbCBwbGFjZXMgaW4gYQogICAgYnV0dG9uIGNhcHRpb24gcmVhZHMgYXMgYSBtYWNoaW5lIHRhbGtpbmcgdG8gaXRzZWxmLgogICAgIiIi'
    || 'CiAgICBpZiB2IGlzIE5vbmU6CiAgICAgICAgcmV0dXJuICJcdTIwMTQiCiAgICB0cnk6CiAgICAgICAgcyA9IGYie2Zsb2F0KHYpOi4zZn0iLnJzdHJpcCgi'
    || 'MCIpLnJzdHJpcCgiLiIpCiAgICAgICAgcmV0dXJuIHMgb3IgIjAiCiAgICBleGNlcHQgKFR5cGVFcnJvciwgVmFsdWVFcnJvcik6CiAgICAgICAgcmV0dXJu'
    || 'IHN0cih2KQoKCmRlZiBsb2FkX3J1bGVfY29uZmlnKHNlc3Npb24sIHRndDogc3RyKToKICAgICIiIigodGllciwgYWxsb3dfcmVhbCwgYWxsb3dfc2FtcGxl'
    || 'KSwgcm93cykgZm9yIGEgc29sdXRpb24gd2l0aCBhIHR1bmFibGUgcnVsZQogICAgc2V0LCBlbHNlICgoIiIsIEZhbHNlLCBGYWxzZSksIFtdKS4KCiAgICBX'
    || 'SFkgVEhJUyBSRUFEUyBUSUVSIEFORCBOT1QgTU9ERS4gSXQgdXNlZCB0byByZXR1cm4gTU9ERSwgYW5kIGNvbmZpZ19iYXIgZ2F0ZWQKICAgIG9uIGBtb2Rl'
    || 'IGluICgiUE9DIiwgIlBST0RVQ1RJT04iKWAuIE1PREUgY2FuIG9ubHkgZXZlciBob2xkIERJU0NPVkVSIG9yIFNBTVBMRQogICAgLS0gdGhvc2UgYXJlIHRo'
    || 'ZSBvbmx5IHR3byB2YWx1ZXMgdGhlIHNldHRpbmdzIHRlbXBsYXRlIGRlZmluZXMsIGFuZAogICAgMDBfc2V0dGluZ3NfYW5kX2Jsb2NrMCBkb2N1bWVudHMg'
    || 'dGhlbSBhcyBhIERBVEEgU09VUkNFIHN3aXRjaDogRElTQ09WRVIgcmVhZHMKICAgIHlvdXIgYWNjb3VudCwgU0FNUExFIHNlZWRzIGZpeHR1cmVzIGluc3Rl'
    || 'YWQuICJQT0MiIHdhcyBuZXZlciBhIHJlYWNoYWJsZSB2YWx1ZSwKICAgIHNvIHRoZSBjb250cm9scyB3ZXJlIGRlYWQgaW4gZXZlcnkgc29sdXRpb24sIGlu'
    || 'IGV2ZXJ5IG1vZGUsIGFuZAogICAgU0VUX1JVTEVfQ09ORklHIC8gUkVCVUlMRF9SRVNPTFVUSU9OIC8gUkVTRVRfUlVMRV9ERUZBVUxUUyBjb3VsZCBub3Qg'
    || 'YmUgcmVhY2hlZAogICAgZnJvbSB0aGUgYXBwIGF0IGFsbC4KCiAgICBUaGUgZ2F0ZSB3YXMgd3JpdHRlbiBhZ2FpbnN0IGEgRElTQ09WRVIgLT4gUE9DIC0+'
    || 'IFBST0RVQ1RJT04gbWF0dXJpdHkgbGFkZGVyCiAgICB0aGF0IHdhcyBuZXZlciBpbXBsZW1lbnRlZC4gVGhlIGxhZGRlciB0aGF0IGRvZXMgZXhpc3QgaXMg'
    || 'VElFUgogICAgKFNBTVBMRSAvIExJTUlURUQgLyBQUk9EVUNUSU9OKSwgd2hpY2ggaXMgd2hhdCBnb3Zlcm5zIGhvdyBtdWNoIHJlYWwgZGF0YSB0aGUKICAg'
    || 'IGJ1aWxkIGlzIGFsbG93ZWQgdG8gdG91Y2guIFNvIHRoZSBnYXRlIG5vdyByZWFkcyBUSUVSLCBhbmQgcmV1c2VzIHRoZSBTQU1FIHR3bwogICAgYXV0aG9y'
    || 'aXNhdGlvbnMgcHJvbW90aW9uX2JhciByZWFkcyAtLSBBTExPV19BQ1RJT05TIGZvciBMSU1JVEVEIGFuZCBQUk9EVUNUSU9OLAogICAgQUxMT1dfU0FNUExF'
    || 'X0FDVElPTlMgZm9yIFNBTVBMRS4gVGhhdCBpcyBkZWxpYmVyYXRlOiBhIHRocmVzaG9sZCBjaGFuZ2UgY29zdHMgYQogICAgUkVCVUlMRF9SRVNPTFVUSU9O'
    || 'IGNhbGwsIHdoaWNoIGlzIGFuIGFjdGlvbiwgc28gaWYgdGhlIHR3byBzdXJmYWNlcyBkaXNhZ3JlZWQKICAgIGFib3V0IHdoYXQgaXMgbGl2ZSBvbmUgb2Yg'
    || 'dGhlbSB3b3VsZCBiZSBseWluZy4KCiAgICBOTyBQRVItU09MVVRJT04gRkxBRywgQU5EIFRIQVQgSVMgVEhFIFdIT0xFIFNBRkVUWSBBUkdVTUVOVC4gVGhp'
    || 'cyBnYXRlcyBvbgogICAgd2hldGhlciBWX1JVTEVfQ09ORklHIGV4aXN0cywgZXhhY3RseSBhcyBsb2FkX2FjdGlvbnMoKSBnYXRlcyBvbiBWX0FDVElPTlMu'
    || 'CiAgICBUd2VudHktZml2ZSBvZiB0aGUgdHdlbnR5LXNldmVuIHNvbHV0aW9ucyBkbyBub3QgZGVmaW5lIHRoYXQgdmlldywgc28gZm9yIHRoZW0KICAgIHRo'
    || 'aXMgcmV0dXJucyAoKCIiLCBGYWxzZSwgRmFsc2UpLCBbXSkgb24gdGhlIGZpcnN0IGV4Y2VwdGlvbiBhbmQgY29uZmlnX2JhcigpCiAgICBkcmF3cyBub3Ro'
    || 'aW5nIC0tIG5vIG5ldyBzZXR0aW5nIHRvIHNldCB3cm9uZywgbm8gc2Vjb25kIGNvZGUgcGF0aCB0aHJvdWdoIHRoZQogICAgc2hlbGwsIGFuZCBubyB3YXkg'
    || 'Zm9yIGEgc29sdXRpb24gdGhhdCBuZXZlciBvcHRlZCBpbiB0byBncm93IGEgY29udHJvbCBzdXJmYWNlCiAgICBieSBhY2NpZGVudC4KCiAgICBUaGUgZ2F0'
    || 'ZSBjb21lcyBiYWNrIHdpdGggdGhlIHJvd3MgYmVjYXVzZSB0aGUgY2FsbGVyIG5lZWRzIGJvdGggdG8gZGVjaWRlCiAgICBhbnl0aGluZywgYW5kIHJlYWRp'
    || 'bmcgaXQgdHdpY2UgaW52aXRlcyB0aGUgdHdvIHJlYWRzIHRvIGRpc2FncmVlIGFjcm9zcyBhIHJlcnVuLgogICAgIiIiCiAgICB0cnk6CiAgICAgICAgcm93'
    || 'cyA9IFtyLmFzX2RpY3QoKSBmb3IgciBpbiBzZXNzaW9uLnNxbCgKICAgICAgICAgICAgIlNFTEVDVCBSVUxFX0lELCBHUk9VUF9MQUJFTCwgUExBSU5fTEFC'
    || 'RUwsIFBMQUlOX0RFU0MsIElTX0FDVElWRSwgIgogICAgICAgICAgICAiSVNfTU9ESUZJRUQsIFRIUkVTSE9MRCwgVEhSRVNIT0xEX0VESVRBQkxFLCBMSU5L'
    || 'UywgU09MRV9MSU5LUyAiCiAgICAgICAgICAgICJGUk9NICIgKyB0Z3QgKyAiLlZfUlVMRV9DT05GSUcgT1JERVIgQlkgR1JPVVBfU0VRLCBSVUxFX1NFUSIp'
    || 'LmNvbGxlY3QoKV0KICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgcmV0dXJuICgiIiwgRmFsc2UsIEZhbHNlKSwgW10KICAgICMgUmVhZCBkZWZlbnNp'
    || 'dmVseSBhbmQgZmFpbCBDTE9TRUQgb24gZWFjaCBvbmUgaW5kZXBlbmRlbnRseS4gQSBydWxlIHNldCB3aG9zZQogICAgIyB0aWVyIG9yIGF1dGhvcmlzYXRp'
    || 'b24gY2Fubm90IGJlIGVzdGFibGlzaGVkIGlzIHRyZWF0ZWQgYXMgcmVhZC1vbmx5LCBiZWNhdXNlCiAgICAjIHRoZSBmYWlsdXJlIGRpcmVjdGlvbiBtYXR0'
    || 'ZXJzOiBndWVzc2luZyAibGl2ZSIgaGVyZSB3b3VsZCBhcm0gY29udHJvbHMgdGhhdAogICAgIyBjYWxsIGEgcmVidWlsZCBvbiBhIGJ1aWxkIHdlIGtub3cg'
    || 'bm90aGluZyBhYm91dC4KICAgIHRyeToKICAgICAgICB0aWVyID0gc3RyKHNlc3Npb24uc3FsKAogICAgICAgICAgICAiU0VMRUNUIFRJRVIgRlJPTSAiICsg'
    || 'dGd0ICsgIi5WX0JVSUxEX0NPTlRFWFQiKS5jb2xsZWN0KClbMF1bMF0KICAgICAgICAgICAgb3IgIiIpLnVwcGVyKCkKICAgIGV4Y2VwdCBFeGNlcHRpb246'
    || 'CiAgICAgICAgdGllciA9ICIiCiAgICB0cnk6CiAgICAgICAgYWxsb3dfcmVhbCA9IGJvb2woc2Vzc2lvbi5zcWwoCiAgICAgICAgICAgICJTRUxFQ1QgQUNU'
    || 'SU9OU19FTkFCTEVEIEZST00gIiArIHRndCArICIuVl9CVUlMRF9DT05URVhUIikuY29sbGVjdCgpWzBdWzBdKQogICAgZXhjZXB0IEV4Y2VwdGlvbjoKICAg'
    || 'ICAgICBhbGxvd19yZWFsID0gRmFsc2UKICAgIHRyeToKICAgICAgICBhbGxvd19zYW1wbGUgPSBib29sKHNlc3Npb24uc3FsKAogICAgICAgICAgICAiU0VM'
    || 'RUNUIENPQUxFU0NFKFNBTVBMRV9BQ1RJT05TX0VOQUJMRUQsIEZBTFNFKSBGUk9NICIgKyB0Z3QKICAgICAgICAgICAgKyAiLlZfQlVJTERfQ09OVEVYVCIp'
    || 'LmNvbGxlY3QoKVswXVswXSkKICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgYWxsb3dfc2FtcGxlID0gRmFsc2UKICAgIHJldHVybiAodGllciwgYWxs'
    || 'b3dfcmVhbCwgYWxsb3dfc2FtcGxlKSwgcm93cwoKCmRlZiBjb25maWdfYmFyKHNlc3Npb24sIHRndDogc3RyKSAtPiBOb25lOgogICAgIiIiVGhlIHR1bmFi'
    || 'bGUgcnVsZSBzZXQ6IHJlYWQtb25seSB1bnRpbCB0aGUgYnVpbGQgaXMgYXV0aG9yaXNlZCB0byBhY3QuCgogICAgU3RyZWFtbGl0IHJhdGhlciB0aGFuIFJl'
    || 'YWN0IGZvciB0aGUgc2FtZSBwaHlzaWNhbCByZWFzb24gcHJvbW90aW9uX2JhciBpcyAtLQogICAgY29tcG9uZW50cy5odG1sIGlzIGEgc2FuZGJveGVkIGNy'
    || 'b3NzLW9yaWdpbiBpZnJhbWUgd2l0aCBubyBTbm93Zmxha2Ugc2Vzc2lvbiwKICAgIHNvIGEgUmVhY3Qgc2xpZGVyIGNhbm5vdCBjYWxsIGEgcHJvY2VkdXJl'
    || 'LiBUaGUgUmVhY3QgcGFnZSBzaG93cyB0aGUgcnVsZXMgYW5kCiAgICB3aGF0IGVhY2ggb25lIGNvbnRyaWJ1dGVzOyB0aGlzIGlzIHdoZXJlIHRoZXkgY2hh'
    || 'bmdlLgoKICAgIFdIWSBSRUFELU9OTFkgUkFUSEVSIFRIQU4gSElEREVOLiBXaGVuIHRoZSBidWlsZCBpcyBub3QgYXV0aG9yaXNlZCB0byBydW4KICAgIGFj'
    || 'dGlvbnMsIHRoZSBydWxlIHNldCBpcyBzdGlsbCB0aGUgcGFydCB3b3J0aCBzZWVpbmcgLS0gdHVuYWJsZSBtYXRjaGluZyBpcyB0aGUKICAgIHByb2R1Y3Qu'
    || 'IEhpZGluZyB0aGUgcGFuZWwgd291bGQgbWlzcmVwcmVzZW50IGl0LiBBcm1pbmcgaXQgd291bGQgYmUgd29yc2U6IGF0CiAgICBTQU1QTEUgdGllciBhIHJl'
    || 'YWRlciB3b3VsZCB0dW5lIHRocmVzaG9sZHMgYWdhaW5zdCBzZWVkZWQgcm93cyBhbmQgcmVhZCB0aGUKICAgIHJlc3VsdCBhcyB0aGVpciBvd24gZGF0YS4g'
    || 'U28gdGhlIHZhbHVlcyBhbHdheXMgcmVuZGVyLCBsYWJlbGxlZCBhcyBhIHByZXNldCB3aGVuCiAgICB0aGV5IGNhbm5vdCBiZSBjaGFuZ2VkLCBhbmQgdGhl'
    || 'IGNvbnRyb2xzIGFycml2ZSB3aXRoIHRoZSBhdXRob3Jpc2F0aW9uIHRoYXQgbWFrZXMKICAgIHRoZW0gbWVhbiBzb21ldGhpbmcuCiAgICAiIiIKICAgICh0'
    || 'aWVyLCBhbGxvd19yZWFsLCBhbGxvd19zYW1wbGUpLCByb3dzID0gbG9hZF9ydWxlX2NvbmZpZyhzZXNzaW9uLCB0Z3QpCiAgICBpZiBub3Qgcm93czoKICAg'
    || 'ICAgICByZXR1cm4KCiAgICAjIFRoZSBTQU1FIHNwbGl0IHByb21vdGlvbl9iYXIgYXBwbGllcywgZm9yIHRoZSBzYW1lIHJlYXNvbjogU0FNUExFIHJ1bnMg'
    || 'YWdhaW5zdAogICAgIyBzZWVkZWQgcm93cyB0aGlzIHNjcmlwdCBjcmVhdGVkLCBldmVyeXRoaW5nIGVsc2UgdG91Y2hlcyB0aGUgY3VzdG9tZXIncyBvd24K'
    || 'ICAgICMgb2JqZWN0cy4gQXBwbHlpbmcgYSB0aHJlc2hvbGQgY2FsbHMgUkVCVUlMRF9SRVNPTFVUSU9OLCBzbyBpdCBhbnN3ZXJzIHRvIHRoZQogICAgIyBh'
    || 'Y3Rpb24gYXV0aG9yaXNhdGlvbnMgcmF0aGVyIHRoYW4gdG8gYSBzZWNvbmQsIHBhcmFsbGVsIG5vdGlvbiBvZiAibGl2ZSIuCiAgICBsaXZlID0gYWxsb3df'
    || 'c2FtcGxlIGlmIHRpZXIgPT0gIlNBTVBMRSIgZWxzZSBhbGxvd19yZWFsCiAgICBzdC5jYXB0aW9uKCJNQVRDSElORyBSVUxFUyIgKyAoIiIgaWYgbGl2ZSBl'
    || 'bHNlICIgXHUwMGI3IFBSRVNFVCwgTk9UIFlFVCBUVU5BQkxFIikpCiAgICBpZiBub3QgbGl2ZToKICAgICAgICB3aHkgPSAoCiAgICAgICAgICAgICJBY3Rp'
    || 'b25zIGFyZSBzd2l0Y2hlZCBvZmYgZm9yIHRoaXMgYnVpbGQsIHNvIHRoZXNlIGFyZSB0aGUgcHJlc2V0IHJ1bGVzICIKICAgICAgICAgICAgImFzIHNoaXBw'
    || 'ZWQuIFRoZXkgYXJlIHNob3duIGJlY2F1c2UgdGhlIHJ1bGUgc2V0IGlzIHRoZSBwYXJ0IHdvcnRoICIKICAgICAgICAgICAgInNlZWluZywgYW5kIHRoZXkg'
    || 'YXJlIG5vdCBlZGl0YWJsZSBiZWNhdXNlIGFwcGx5aW5nIGEgY2hhbmdlIGNhbGxzIGEgIgogICAgICAgICAgICAicmVidWlsZC4iKQogICAgICAgIGlmIHRp'
    || 'ZXIgPT0gIlNBTVBMRSI6CiAgICAgICAgICAgIHdoeSA9ICgKICAgICAgICAgICAgICAgICJUaGlzIGJ1aWxkIHJhbiBhdCBTQU1QTEUgdGllciwgc28gdGhl'
    || 'c2UgYXJlIHRoZSBwcmVzZXQgcnVsZXMgIgogICAgICAgICAgICAgICAgInJ1bm5pbmcgb3ZlciB0aGUgYnVuZGxlZCBzYW1wbGUgcm93cy4gVGhleSBhcmUg'
    || 'c2hvd24gYmVjYXVzZSB0aGUgIgogICAgICAgICAgICAgICAgInJ1bGUgc2V0IGlzIHRoZSBwYXJ0IHdvcnRoIHNlZWluZywgYW5kIHRoZXkgYXJlIG5vdCBl'
    || 'ZGl0YWJsZSAiCiAgICAgICAgICAgICAgICAiYmVjYXVzZSB0dW5pbmcgYSB0aHJlc2hvbGQgYWdhaW5zdCBzZWVkZWQgZGF0YSB3b3VsZCBwcm9kdWNlIGEg'
    || 'IgogICAgICAgICAgICAgICAgIm51bWJlciB0aGF0IGRlc2NyaWJlcyB0aGUgZml4dHVyZSByYXRoZXIgdGhhbiB5b3VyIGFjY291bnQuIikKICAgICAgICBl'
    || 'bGlmIG5vdCB0aWVyOgogICAgICAgICAgICB3aHkgPSAoCiAgICAgICAgICAgICAgICAiVGhpcyBidWlsZCdzIHRpZXIgY291bGQgbm90IGJlIHJlYWQsIHNv'
    || 'IHRoZSBjb250cm9scyBzdGF5ICIKICAgICAgICAgICAgICAgICJyZWFkLW9ubHkgcmF0aGVyIHRoYW4gYXJtaW5nIGEgcmVidWlsZCBhZ2FpbnN0IGEgYnVp'
    || 'bGQgd2UgY2Fubm90ICIKICAgICAgICAgICAgICAgICJpZGVudGlmeS4gVGhlIHZhbHVlcyBiZWxvdyBhcmUgdGhlIHJ1bGVzIGFzIHNoaXBwZWQuIikKICAg'
    || 'ICAgICBzdC5jYXB0aW9uKHdoeSArICIgRW5hYmxlIGFjdGlvbnMgYW5kIHJlLXJ1biBhdCBMSU1JVEVEIG9yIFBST0RVQ1RJT04gdGllciAiCiAgICAgICAg'
    || 'ICAgICAgICAgICAgICAgICAiYW5kIHRoZSBjb250cm9scyBiZWxvdyBiZWNvbWUgbGl2ZS4iKQoKICAgIGRpcnR5ID0gYW55KGJvb2woci5nZXQoIklTX01P'
    || 'RElGSUVEIikpIGZvciByIGluIHJvd3MpCiAgICBhdF9yaXNrID0gc3VtKGludChyLmdldCgiU09MRV9MSU5LUyIpIG9yIDApCiAgICAgICAgICAgICAgICAg'
    || 'IGZvciByIGluIHJvd3MgaWYgbm90IGJvb2woci5nZXQoIklTX0FDVElWRSIpKSkKICAgIGlmIGRpcnR5OgogICAgICAgIHN0LmNhcHRpb24oIkNIQU5HRUQg'
    || 'RlJPTSBERUZBVUxUUyBcdTAwYjcgcmVidWlsZCB0byBhcHBseSIpCiAgICBpZiBhdF9yaXNrOgogICAgICAgIHN0LmNhcHRpb24oIkVzdGltYXRlZCBpbXBh'
    || 'Y3Q6IGFib3V0ICIgKyBmInthdF9yaXNrOix9IgogICAgICAgICAgICAgICAgICAgKyAiIGNvbm5lY3Rpb25zIHdvdWxkIGJlIHJlbW92ZWQsIGJlY2F1c2Ug'
    || 'dGhleSBhcmUgaGVsZCBieSBhICIKICAgICAgICAgICAgICAgICAgICAgInJ1bGUgdGhhdCBpcyBjdXJyZW50bHkgc3dpdGNoZWQgb2ZmLiIpCgogICAgZ3Jv'
    || 'dXAgPSBOb25lCiAgICBmb3IgciBpbiByb3dzOgogICAgICAgIGcgPSBzdHIoci5nZXQoIkdST1VQX0xBQkVMIikgb3IgIiIpCiAgICAgICAgaWYgZyAhPSBn'
    || 'cm91cDoKICAgICAgICAgICAgZ3JvdXAgPSBnCiAgICAgICAgICAgIHN0LmNhcHRpb24oZy51cHBlcigpKQogICAgICAgIHJpZCA9IHN0cihyLmdldCgiUlVM'
    || 'RV9JRCIpIG9yICIiKQogICAgICAgIGxhYmVsID0gc3RyKHIuZ2V0KCJQTEFJTl9MQUJFTCIpIG9yIHJpZCkKICAgICAgICBhY3RpdmUgPSBib29sKHIuZ2V0'
    || 'KCJJU19BQ1RJVkUiKSkKICAgICAgICB0aHIgPSByLmdldCgiVEhSRVNIT0xEIikKICAgICAgICBlZGl0YWJsZSA9IGJvb2woci5nZXQoIlRIUkVTSE9MRF9F'
    || 'RElUQUJMRSIpKSBhbmQgdGhyIGlzIG5vdCBOb25lCiAgICAgICAgbGlua3MgPSBpbnQoci5nZXQoIkxJTktTIikgb3IgMCkKICAgICAgICBzb2xlID0gaW50'
    || 'KHIuZ2V0KCJTT0xFX0xJTktTIikgb3IgMCkKCiAgICAgICAgYzEsIGMyLCBjMyA9IHN0LmNvbHVtbnMoWzMsIDIsIDJdKQogICAgICAgIHdpdGggYzE6CiAg'
    || 'ICAgICAgICAgIGlmIGxpdmU6CiAgICAgICAgICAgICAgICBuZXdfYWN0aXZlID0gc3QudG9nZ2xlKGxhYmVsLCB2YWx1ZT1hY3RpdmUsIGtleT0icmFfIiAr'
    || 'IHJpZCkKICAgICAgICAgICAgZWxzZToKICAgICAgICAgICAgICAgIHN0LmNhcHRpb24oKCJPTiAgIiBpZiBhY3RpdmUgZWxzZSAiT0ZGICIpICsgbGFiZWwp'
    || 'CiAgICAgICAgICAgICAgICBuZXdfYWN0aXZlID0gYWN0aXZlCiAgICAgICAgICAgIGlmIHIuZ2V0KCJQTEFJTl9ERVNDIik6CiAgICAgICAgICAgICAgICBz'
    || 'dC5jYXB0aW9uKHN0cihyWyJQTEFJTl9ERVNDIl0pKQogICAgICAgIHdpdGggYzI6CiAgICAgICAgICAgIG5ld190aHIgPSB0aHIKICAgICAgICAgICAgaWYg'
    || 'ZWRpdGFibGU6CiAgICAgICAgICAgICAgICBpZiBsaXZlOgogICAgICAgICAgICAgICAgICAgIG5ld190aHIgPSBzdC5zbGlkZXIoCiAgICAgICAgICAgICAg'
    || 'ICAgICAgICAgICJIb3cgc2ltaWxhciBpcyBjbG9zZSBlbm91Z2giLCBtaW5fdmFsdWU9NTAsIG1heF92YWx1ZT0xMDAsCiAgICAgICAgICAgICAgICAgICAg'
    || 'ICAgIHZhbHVlPWludChyb3VuZChmbG9hdCh0aHIpICogMTAwKSksIHN0ZXA9MSwga2V5PSJydF8iICsgcmlkLAogICAgICAgICAgICAgICAgICAgICAgICBo'
    || 'ZWxwPSJoaWdoZXIgaXMgc3RyaWN0ZXIgXHUyMDE0IGZld2VyLCBzYWZlciBtYXRjaGVzIikKICAgICAgICAgICAgICAgICAgICBuZXdfdGhyID0gbmV3X3Ro'
    || 'ciAvIDEwMC4wCiAgICAgICAgICAgICAgICBlbHNlOgogICAgICAgICAgICAgICAgICAgIHN0LmNhcHRpb24oInNpbWlsYXJpdHkgIiArIHN0cihpbnQocm91'
    || 'bmQoZmxvYXQodGhyKSAqIDEwMCkpKSArICIlIikKICAgICAgICB3aXRoIGMzOgogICAgICAgICAgICBzdC5jYXB0aW9uKGYie2xpbmtzOix9IiArICIgY29u'
    || 'bmVjdGlvbnMgbWFkZSIpCiAgICAgICAgICAgIGlmIHNvbGU6CiAgICAgICAgICAgICAgICBzdC5jYXB0aW9uKGYie3NvbGU6LH0iICsgIiB3b3VsZCBiZSBs'
    || 'b3N0IHdpdGhvdXQgaXQiKQoKICAgICAgICAjIE9uZSBDQUxMIHBlciBjaGFuZ2VkIHJ1bGUsIGFuZCBvbmx5IG9uIGEgcmVhbCBjaGFuZ2UuIFdyaXRpbmcg'
    || 'b24gZXZlcnkKICAgICAgICAjIHJlcnVuIHdvdWxkIGlzc3VlIGEgcHJvY2VkdXJlIGNhbGwgcGVyIHJ1bGUgcGVyIHJlcGFpbnQsIHdoaWNoIGlzIGJvdGgg'
    || 'YQogICAgICAgICMgY29zdCBhbmQgYSBmYWxzZSBhdWRpdCB0cmFpbCAtLSB0aGUgY29uZmlnIGhpc3Rvcnkgd291bGQgcmVjb3JkIGVkaXRzCiAgICAgICAg'
    || 'IyBub2JvZHkgbWFkZS4KICAgICAgICBpZiBsaXZlIGFuZCAobmV3X2FjdGl2ZSAhPSBhY3RpdmUgb3IKICAgICAgICAgICAgICAgICAgICAgKGVkaXRhYmxl'
    || 'IGFuZCBuZXdfdGhyIGlzIG5vdCBOb25lIGFuZCB0aHIgaXMgbm90IE5vbmUKICAgICAgICAgICAgICAgICAgICAgIGFuZCBhYnMoZmxvYXQobmV3X3Rocikg'
    || 'LSBmbG9hdCh0aHIpKSA+IDFlLTkpKToKICAgICAgICAgICAgdHJ5OgogICAgICAgICAgICAgICAgc2Vzc2lvbi5zcWwoIkNBTEwgIiArIHRndCArICIuU0VU'
    || 'X1JVTEVfQ09ORklHKD8sID8sID8pIiwKICAgICAgICAgICAgICAgICAgICAgICAgICAgIHBhcmFtcz1bcmlkLCBib29sKG5ld19hY3RpdmUpLAogICAgICAg'
    || 'ICAgICAgICAgICAgICAgICAgICAgICAgICAgICBmbG9hdChuZXdfdGhyKSBpZiBuZXdfdGhyIGlzIG5vdCBOb25lIGVsc2UgTm9uZV0pLmNvbGxlY3QoKQog'
    || 'ICAgICAgICAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGV4YzoKICAgICAgICAgICAgICAgIHN0LmVycm9yKCJDb3VsZCBub3Qgc2F2ZSAiICsgcmlkICsgIjog'
    || 'IiArIHN0cihleGMpLAogICAgICAgICAgICAgICAgICAgICAgICAgaWNvbj0iOm1hdGVyaWFsL2Vycm9yOiIpCiAgICAgICAgICAgIGVsc2U6CiAgICAgICAg'
    || 'ICAgICAgICBpbnZhbGlkYXRlX3BhbmVsX2NhY2hlKCkKICAgICAgICAgICAgICAgIHN0LnJlcnVuKCkKCiAgICBpZiBub3QgbGl2ZToKICAgICAgICBzdC5k'
    || 'aXZpZGVyKCkKICAgICAgICByZXR1cm4KCiAgICBiMSwgYjIgPSBzdC5jb2x1bW5zKFsxLCAxXSkKICAgIHdpdGggYjE6CiAgICAgICAgaWYgc3QuYnV0dG9u'
    || 'KCJSZXN0b3JlIGRlZmF1bHRzIiwga2V5PSJjZmdfcmVzZXQiKToKICAgICAgICAgICAgdHJ5OgogICAgICAgICAgICAgICAgb3V0ID0gc2Vzc2lvbi5zcWwo'
    || 'IkNBTEwgIiArIHRndCArICIuUkVTRVRfUlVMRV9ERUZBVUxUUygpIikuY29sbGVjdCgpWzBdWzBdCiAgICAgICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMg'
    || 'ZXhjOgogICAgICAgICAgICAgICAgb3V0ID0gIkZBSUxFRCB0byByZXN0b3JlIGRlZmF1bHRzOiAiICsgc3RyKGV4YykKICAgICAgICAgICAgc3Quc2Vzc2lv'
    || 'bl9zdGF0ZVsiY2ZnX3Jlc3VsdCJdID0gc3RyKG91dCkKICAgICAgICAgICAgaW52YWxpZGF0ZV9wYW5lbF9jYWNoZSgpCiAgICAgICAgICAgIHN0LnJlcnVu'
    || 'KCkKICAgIHdpdGggYjI6CiAgICAgICAgaWYgc3QuYnV0dG9uKCJSZWJ1aWxkIHJlY29yZHMiLCBrZXk9ImNmZ19yZWJ1aWxkIiwgdHlwZT0icHJpbWFyeSIp'
    || 'OgogICAgICAgICAgICB0cnk6CiAgICAgICAgICAgICAgICBvdXQgPSBzZXNzaW9uLnNxbCgiQ0FMTCAiICsgdGd0ICsgIi5SRUJVSUxEX1JFU09MVVRJT04o'
    || 'KSIpLmNvbGxlY3QoKVswXVswXQogICAgICAgICAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGV4YzoKICAgICAgICAgICAgICAgIG91dCA9ICJGQUlMRUQgdG8g'
    || 'cmVidWlsZDogIiArIHN0cihleGMpCiAgICAgICAgICAgIHN0LnNlc3Npb25fc3RhdGVbImNmZ19yZXN1bHQiXSA9IHN0cihvdXQpCiAgICAgICAgICAgIGlu'
    || 'dmFsaWRhdGVfcGFuZWxfY2FjaGUoKQogICAgICAgICAgICBzdC5yZXJ1bigpCgogICAgbXNnID0gc3RyKHN0LnNlc3Npb25fc3RhdGUuZ2V0KCJjZmdfcmVz'
    || 'dWx0Iikgb3IgIiIpCiAgICBpZiBtc2c6CiAgICAgICAgaWYgbXNnLnN0YXJ0c3dpdGgoIkRPTkUiKSBvciBtc2cuc3RhcnRzd2l0aCgiUkVCVUlMVCIpIG9y'
    || 'IG1zZy5zdGFydHN3aXRoKCJSRVNUT1JFRCIpOgogICAgICAgICAgICBzdC5zdWNjZXNzKG1zZywgaWNvbj0iOm1hdGVyaWFsL2NoZWNrOiIpCiAgICAgICAg'
    || 'ZWxpZiBtc2cuc3RhcnRzd2l0aCgiUkVGVVNFRCIpOgogICAgICAgICAgICBzdC53YXJuaW5nKG1zZywgaWNvbj0iOm1hdGVyaWFsL2Jsb2NrOiIpCiAgICAg'
    || 'ICAgZWxzZToKICAgICAgICAgICAgc3QuZXJyb3IobXNnLCBpY29uPSI6bWF0ZXJpYWwvZXJyb3I6IikKICAgIHN0LmRpdmlkZXIoKQoKCmRlZiBsb2FkX2Fj'
    || 'dGlvbnMoc2Vzc2lvbiwgdGd0OiBzdHIpOgogICAgIiIiKChhbGxvd19yZWFsLCBhbGxvd19zYW1wbGUpLCByb3dzKS4gUmV0dXJucyAoKEZhbHNlLCBGYWxz'
    || 'ZSksIFtdKSBmb3IgYW55CiAgICBidWlsZCB3aXRob3V0IHRoZSBmcmFtZXdvcmsuCgogICAgV3JhcHBlZCBiZWNhdXNlIGEgc2NoZW1hIGJ1aWx0IGJ5IGFu'
    || 'IG9sZGVyIGFydGlmYWN0IGhhcyBubyBWX0FDVElPTlMsIGFuZCB0aGUKICAgIGFwcCBtdXN0IHN0aWxsIHdvcmsgYWdhaW5zdCBpdCByYXRoZXIgdGhhbiBz'
    || 'aG93aW5nIGEgdHJhY2ViYWNrIHdoZXJlIHRoZQogICAgcHJvbW90aW9uIGJhciB3b3VsZCBiZS4KICAgICIiIgogICAgdHJ5OgogICAgICAgIHJvd3MgPSBb'
    || 'ci5hc19kaWN0KCkgZm9yIHIgaW4gc2Vzc2lvbi5zcWwoCiAgICAgICAgICAgICJTRUxFQ1QgQ09ERSwgTEFCRUwsIFRJRVIsIEVGRkVDVCwgVU5ETywgRVNU'
    || 'X0NSRURJVFMsIEVTVF9CQVNJUywgIgogICAgICAgICAgICAiU1RBVEVNRU5UUywgVU5ET19TVEFURU1FTlRTLCBUSU1FU19SVU4sIFRJTUVTX1VORE9ORSwg'
    || 'TEFTVF9SVU5fQVQgRlJPTSAiICsgdGd0ICsgIi5WX0FDVElPTlMiKS5jb2xsZWN0KCldCiAgICBleGNlcHQgRXhjZXB0aW9uOgogICAgICAgIHJldHVybiAo'
    || 'RmFsc2UsIEZhbHNlKSwgW10KICAgICMgVHdvIGF1dGhvcmlzYXRpb25zLCBub3Qgb25lLiBBTExPV19BQ1RJT05TIGdvdmVybnMgTElNSVRFRCBhbmQgUFJP'
    || 'RFVDVElPTiAtLQogICAgIyBhbnl0aGluZyB0aGF0IHJlYWRzIG9yIHdyaXRlcyByZWFsIGRhdGEuIEFMTE9XX1NBTVBMRV9BQ1RJT05TIGdvdmVybnMgU0FN'
    || 'UExFLAogICAgIyBhbmQgZGVmYXVsdHMgVFJVRSwgc28gYSBmcmVzaGx5IGluc3RhbGxlZCBhcHAgaGFzIHNvbWV0aGluZyB0aGF0IHdvcmtzLgogICAgIwog'
    || 'ICAgIyBUaGlzIG1pcnJvcnMgUlVOX0FDVElPTiByYXRoZXIgdGhhbiBkZWNpZGluZyBhbnl0aGluZzogdGhlIHByb2NlZHVyZSBlbmZvcmNlcwogICAgIyB0'
    || 'aGUgc2FtZSBzcGxpdCBzZXJ2ZXItc2lkZSBhbmQgcmVmdXNlcyByZWdhcmRsZXNzIG9mIHdoYXQgdGhpcyByZXR1cm5zLiBJZiB0aGUKICAgICMgdHdvIGV2'
    || 'ZXIgZGlzYWdyZWUgdGhlIHByb2Mgd2lucywgd2hpY2ggaXMgdGhlIGNvcnJlY3QgZGlyZWN0aW9uIC0tIGEgZGlzYWJsZWQKICAgICMgYnV0dG9uIGlzIGEg'
    || 'bnVpc2FuY2UsIGEgYnV0dG9uIHRoYXQgYXBwZWFycyBsaXZlIGFuZCB0aGVuIHJlZnVzZXMgaXMgYSBsaWUuCiAgICAjIFNBTVBMRV9BQ1RJT05TX0VOQUJM'
    || 'RUQgaXMgcmVhZCBkZWZlbnNpdmVseSBiZWNhdXNlIGEgc2NoZW1hIGJ1aWx0IGJ5IGFuIG9sZGVyCiAgICAjIGZpbGUgd2lsbCBub3QgaGF2ZSB0aGUgY29s'
    || 'dW1uLgogICAgdHJ5OgogICAgICAgIGVuYWJsZWQgPSBib29sKHNlc3Npb24uc3FsKAogICAgICAgICAgICAiU0VMRUNUIEFDVElPTlNfRU5BQkxFRCBGUk9N'
    || 'ICIgKyB0Z3QgKyAiLlZfQlVJTERfQ09OVEVYVCIKICAgICAgICApLmNvbGxlY3QoKVswXVswXSkKICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgZW5h'
    || 'YmxlZCA9IEZhbHNlCiAgICB0cnk6CiAgICAgICAgc2FtcGxlX2VuYWJsZWQgPSBib29sKHNlc3Npb24uc3FsKAogICAgICAgICAgICAiU0VMRUNUIENPQUxF'
    || 'U0NFKFNBTVBMRV9BQ1RJT05TX0VOQUJMRUQsIEZBTFNFKSBGUk9NICIgKyB0Z3QgKyAiLlZfQlVJTERfQ09OVEVYVCIKICAgICAgICApLmNvbGxlY3QoKVsw'
    || 'XVswXSkKICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgc2FtcGxlX2VuYWJsZWQgPSBGYWxzZQogICAgcmV0dXJuIChlbmFibGVkLCBzYW1wbGVfZW5h'
    || 'YmxlZCksIHJvd3MKCgpkZWYgbG9hZF9wcmVmaXgoc2Vzc2lvbiwgdGd0OiBzdHIpIC0+IHN0cjoKICAgICIiIlRoZSBwZXItc29sdXRpb24gc2V0dGluZyBw'
    || 'cmVmaXgsIG9yICcnIGlmIHRoaXMgYnVpbGQgcHJlZGF0ZXMgdGhlIGNvbHVtbi4KCiAgICBLZXB0IHNlcGFyYXRlIGZyb20gbG9hZF9hY3Rpb25zIHJhdGhl'
    || 'ciB0aGFuIHdpZGVuaW5nIGl0cyByZXR1cm4sIGJlY2F1c2UKICAgIGV2ZXJ5IGNhbGxlciBvZiB0aGF0IHBhaXItb2YtdHVwbGVzIHNpZ25hdHVyZSB3b3Vs'
    || 'ZCBoYXZlIHRvIGNoYW5nZSBhbmQgbm9uZQogICAgb2YgdGhlbSB3YW50IHRoZSBwcmVmaXguIFRoaXMgZXhpc3RzIHNvIHRoZSBhcHAgY2FuIHByaW50IHRo'
    || 'ZSBsaW5lIHlvdSB3b3VsZAogICAgYWN0dWFsbHkgZWRpdCBpbnN0ZWFkIG9mIGEgc2V0dGluZyBuYW1lIHRoYXQgYXBwZWFycyBpbiBubyBmaWxlLgogICAg'
    || 'IiIiCiAgICB0cnk6CiAgICAgICAgcmV0dXJuIHN0cihzZXNzaW9uLnNxbCgKICAgICAgICAgICAgIlNFTEVDVCBTRVRUSU5HX1BSRUZJWCBGUk9NICIgKyB0'
    || 'Z3QgKyAiLlZfQlVJTERfQ09OVEVYVCIKICAgICAgICApLmNvbGxlY3QoKVswXVswXSBvciAiIikKICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgcmV0'
    || 'dXJuICIiCgoKZGVmIGxvYWRfaGVhZGxpbmUoc2Vzc2lvbiwgdGd0OiBzdHIpOgogICAgIiIiVGhlIG9uZS1saW5lIG1vbnRobHkgcnVuIHJhdGUsIG9yIE5v'
    || 'bmUuCgogICAgV3JhcHBlZCBmb3IgdGhlIHNhbWUgcmVhc29uIGxvYWRfYWN0aW9ucyBpczogYSBzY2hlbWEgYnVpbHQgYnkgYW4gb2xkZXIKICAgIGFydGlm'
    || 'YWN0IGhhcyBubyBWX1JVTl9SQVRFX0hFQURMSU5FLCBhbmQgdGhlIGFwcCBtdXN0IHN0aWxsIHdvcmsgYWdhaW5zdCBpdAogICAgcmF0aGVyIHRoYW4gc2hv'
    || 'd2luZyBhIHRyYWNlYmFjayB3aGVyZSB0aGUgc3RhbmRpbmcgY29zdCB3b3VsZCBiZS4KCiAgICBUaGlzIGlzIHRoZSBvbmx5IHN1cmZhY2UgdGhhdCBwcmlu'
    || 'dHMgaXQuIFRoZSB2aWV3IGhhcyBleGlzdGVkIGZvciBldmVyeQogICAgYnVpbGQgZm9yIGEgd2hpbGUgYW5kIHdhcyByZWFkIGJ5IG5vdGhpbmcgYnV0IHRo'
    || 'ZSB0ZXN0IGhhcm5lc3MsIHNvIHRoZQogICAgc2VudGVuY2Ugd3JpdHRlbiBmb3IgdGhlIGFwcCB0byBwcmludCB3YXMgcHJpbnRlZCBieSBub2JvZHkuCiAg'
    || 'ICAiIiIKICAgIHRyeToKICAgICAgICByb3dzID0gc2Vzc2lvbi5zcWwoCiAgICAgICAgICAgICJTRUxFQ1QgSEVBRExJTkUsIEVTVF9DUkVESVRTX1BFUl9N'
    || 'T05USCBGUk9NICIgKyB0Z3QgKyAiLlZfUlVOX1JBVEVfSEVBRExJTkUiCiAgICAgICAgKS5jb2xsZWN0KCkKICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAg'
    || 'ICAgcmV0dXJuIE5vbmUKICAgIGlmIG5vdCByb3dzOgogICAgICAgIHJldHVybiBOb25lCiAgICByID0gcm93c1swXS5hc19kaWN0KCkKICAgIHJldHVybiAo'
    || 'c3RyKHIuZ2V0KCJIRUFETElORSIpIG9yICIiKSwgci5nZXQoIkVTVF9DUkVESVRTX1BFUl9NT05USCIpKQoKCmRlZiBsb2FkX2FjdGlvbl9wYXJhbXMoc2Vz'
    || 'c2lvbiwgdGd0OiBzdHIpOgogICAgIiIie2FjdGlvbl9jb2RlOiBbcGFyYW0gZGljdCwgLi4uXX0uIEVtcHR5IGRpY3QgZm9yIGFueSBidWlsZCB3aXRob3V0'
    || 'IHBhcmFtcy4KCiAgICBXcmFwcGVkIGZvciB0aGUgc2FtZSByZWFzb24gbG9hZF9hY3Rpb25zIGlzOiBhIHNjaGVtYSBidWlsdCBieSBhbiBvbGRlciBhcnRp'
    || 'ZmFjdAogICAgaGFzIG5vIFZfQUNUSU9OX1BBUkFNUywgYW5kIHRoZSBhcHAgbXVzdCBrZWVwIHdvcmtpbmcgYWdhaW5zdCBpdCByYXRoZXIgdGhhbgogICAg'
    || 'c2hvd2luZyBhIHRyYWNlYmFjayB3aGVyZSB0aGUgcHJvbW90aW9uIGJhciB3b3VsZCBiZS4gQW4gZW1wdHkgcmVzdWx0IGlzIHRoZQogICAgbm9ybWFsIGNh'
    || 'c2UgLS0gbW9zdCBhY3Rpb25zIHRha2Ugbm8gcGFyYW1ldGVycyBhbmQgcmVuZGVyIGV4YWN0bHkgYXMgYmVmb3JlLgoKICAgIERlbGliZXJhdGVseSBOT1Qg'
    || 'Zm9sZGVkIGludG8gbG9hZF9hY3Rpb25zLiBUaGF0IGZ1bmN0aW9uJ3MgU0VMRUNUIGxpc3QgaXMgaXRzCiAgICBjb21wYXRpYmlsaXR5IGNvbnRyYWN0IHdp'
    || 'dGggb2xkZXIgc2NoZW1hczsgYWRkaW5nIGEgY29sdW1uIHRvIGl0IHdvdWxkIG1ha2UgZXZlcnkKICAgIGJ1aWxkIHdpdGhvdXQgdGhhdCBjb2x1bW4gZmFs'
    || 'bCBpbnRvIHRoZSBleGNlcHQgYnJhbmNoIGFuZCBsb3NlIGl0cyB3aG9sZSBhY3Rpb24KICAgIGJhci4gQSBzZXBhcmF0ZSwgc2VwYXJhdGVseS13cmFwcGVk'
    || 'IHJlYWQgZGVncmFkZXMgdG8gIm5vIHBhcmFtZXRlcnMiIGluc3RlYWQuCiAgICAiIiIKICAgIHRyeToKICAgICAgICByb3dzID0gW3IuYXNfZGljdCgpIGZv'
    || 'ciByIGluIHNlc3Npb24uc3FsKAogICAgICAgICAgICAiU0VMRUNUIENPREUsIE9SRElOQUwsIFBBUkFNX05BTUUsIExBQkVMLCBLSU5ELCBPUFRJT05TX1NR'
    || 'TCwgT1BUSU9OUywgIgogICAgICAgICAgICAiTUlOX1ZBTFVFLCBNQVhfVkFMVUUsIEhFTFAgRlJPTSAiICsgdGd0ICsgIi5WX0FDVElPTl9QQVJBTVMgIgog'
    || 'ICAgICAgICAgICAiT1JERVIgQlkgQ09ERSwgT1JESU5BTCIpLmNvbGxlY3QoKV0KICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgcmV0dXJuIHt9CiAg'
    || 'ICBvdXQgPSB7fQogICAgZm9yIHIgaW4gcm93czoKICAgICAgICBvdXQuc2V0ZGVmYXVsdChzdHIoci5nZXQoIkNPREUiKSBvciAiIiksIFtdKS5hcHBlbmQo'
    || 'cikKICAgIHJldHVybiBvdXQKCgpkZWYgYWN0aW9uX3BhcmFtX29wdGlvbnMoc2Vzc2lvbiwgcCkgLT4gbGlzdDoKICAgICIiIlRoZSBjaG9pY2VzIHRvIE9G'
    || 'RkVSIGZvciBvbmUgcGFyYW1ldGVyLiBEaXNwbGF5IG9ubHkuCgogICAgVGhpcyBsaXN0IGlzIHdoYXQgdGhlIHdpZGdldCBzaG93czsgaXQgaXMgTk9UIHdo'
    || 'YXQgYXV0aG9yaXNlcyB0aGUgdmFsdWUuIFRoZQogICAgcHJvY2VkdXJlIHJlLXJ1bnMgdGhlIHJlZ2lzdHJ5J3Mgb3duIGFsbG93ZWRfc3FsIHdoZW4gaXQg'
    || 'dmFsaWRhdGVzLCBzbyBhIHN0YWxlIG9yCiAgICB0YW1wZXJlZCBsaXN0IGhlcmUgY2Fubm90IHdpZGVuIHdoYXQgYW4gYWN0aW9uIHdpbGwgYWNjZXB0IC0t'
    || 'IGl0IGNhbiBvbmx5IGZhaWwgdG8KICAgIG9mZmVyIHNvbWV0aGluZyB0aGUgcHJvY2VkdXJlIHdvdWxkIGhhdmUgcGVybWl0dGVkLiBUaGF0IGFzeW1tZXRy'
    || 'eSBpcyBkZWxpYmVyYXRlOgogICAgdGhlIGFwcCBpcyBhbGxvd2VkIHRvIGJlIHdyb25nIGluIHRoZSBkaXJlY3Rpb24gb2Ygb2ZmZXJpbmcgdG9vIGxpdHRs'
    || 'ZS4KICAgICIiIgogICAgb3B0cyA9IHAuZ2V0KCJPUFRJT05TIikKICAgIGlmIG9wdHM6CiAgICAgICAgdHJ5OgogICAgICAgICAgICByZXR1cm4gW3N0cih2'
    || 'KSBmb3IgdiBpbiAoanNvbi5sb2FkcyhvcHRzKSBpZiBpc2luc3RhbmNlKG9wdHMsIHN0cikgZWxzZSBvcHRzKV0KICAgICAgICBleGNlcHQgRXhjZXB0aW9u'
    || 'OgogICAgICAgICAgICBwYXNzCiAgICBzcWwgPSBzdHIocC5nZXQoIk9QVElPTlNfU1FMIikgb3IgIiIpLnN0cmlwKCkKICAgIGlmIG5vdCBzcWw6CiAgICAg'
    || 'ICAgcmV0dXJuIFtdCiAgICB0cnk6CiAgICAgICAgcmV0dXJuIFtzdHIoclswXSkgZm9yIHIgaW4gc2Vzc2lvbi5zcWwoCiAgICAgICAgICAgICJTRUxFQ1Qg'
    || 'QUxMT1dFRF9WQUxVRSBGUk9NICgiICsgc3FsICsgIikgTElNSVQgIiArIHN0cihST1dfQ0FQKSkuY29sbGVjdCgpXQogICAgZXhjZXB0IEV4Y2VwdGlvbjoK'
    || 'ICAgICAgICAjIEEgYnJva2VuIG9wdGlvbnMgcXVlcnkgbXVzdCBub3QgdGFrZSB0aGUgd2hvbGUgcHJvbW90aW9uIGJhciBkb3duIHdpdGggaXQuCiAgICAg'
    || 'ICAgIyBSZXR1cm5pbmcgbm90aGluZyBsZWF2ZXMgdGhlIGZpZWxkIGVtcHR5LCB0aGUgUnVuIGJ1dHRvbiBkaXNhYmxlZCwgYW5kIHRoZQogICAgICAgICMg'
    || 'cmVzdCBvZiB0aGUgYWN0aW9ucyB1c2FibGUuCiAgICAgICAgcmV0dXJuIFtdCgoKZGVmIGFjdGlvbl9wYXJhbV92YWx1ZXMoc2Vzc2lvbiwgY29kZTogc3Ry'
    || 'LCBwYXJhbXM6IGxpc3QpOgogICAgIiIiUmVuZGVyIG9uZSB3aWRnZXQgcGVyIHBhcmFtZXRlciBhbmQgcmV0dXJuICh2YWx1ZXMgZGljdCwgYWxsX3N1cHBs'
    || 'aWVkKS4KCiAgICBQbGFjZWQgSU5TSURFIHRoZSBhcm1lZCBjb25maXJtYXRpb24gYmxvY2sgYnkgdGhlIGNhbGxlciwgbm90IG9uIHRoZSBhY3Rpb24gY2Fy'
    || 'ZC4KICAgIFR3byByZWFzb25zLiBUaGUgdmFsdWVzIG11c3Qgbm90IGJlIGFibGUgdG8gY2hhbmdlIGJldHdlZW4gYXJtaW5nIGFuZCBjb25maXJtaW5nCiAg'
    || 'ICAtLSB0aGUgdHlwZWQgY29kZSBjb25maXJtcyBhIHNwZWNpZmljIGNoYW5nZSwgc28gdGhlIGNoYW5nZSBoYXMgdG8gYmUgc2V0dGxlZAogICAgYmVmb3Jl'
    || 'IGl0IGlzIHR5cGVkLiBBbmQgaXQga2VlcHMgdGhlIHR5cGVkIGNvbmZpcm1hdGlvbiBhcyB0aGUgZ2VudWluZSBsYXN0IHN0ZXAKICAgIHJhdGhlciB0aGFu'
    || 'IG9uZSBmaWVsZCBhbW9uZyBzZXZlcmFsLgogICAgIiIiCiAgICB2YWxzID0ge30KICAgIG1pc3NpbmcgPSBGYWxzZQogICAgZm9yIHAgaW4gcGFyYW1zOgog'
    || 'ICAgICAgIG5hbWUgPSBzdHIocC5nZXQoIlBBUkFNX05BTUUiKSBvciAiIikKICAgICAgICBsYWJlbCA9IHN0cihwLmdldCgiTEFCRUwiKSBvciBuYW1lKQog'
    || 'ICAgICAgIGtpbmQgPSBzdHIocC5nZXQoIktJTkQiKSBvciAiSURFTlQiKS51cHBlcigpCiAgICAgICAga2V5ID0gInBhcmFtXyIgKyBjb2RlICsgIl8iICsg'
    || 'bmFtZQogICAgICAgIGhlbHBfdHh0ID0gc3RyKHAuZ2V0KCJIRUxQIikgb3IgIiIpIG9yIE5vbmUKICAgICAgICBpZiBraW5kID09ICJOVU1CRVIiOgogICAg'
    || 'ICAgICAgICBsbyA9IHAuZ2V0KCJNSU5fVkFMVUUiKQogICAgICAgICAgICBoaSA9IHAuZ2V0KCJNQVhfVkFMVUUiKQogICAgICAgICAgICB2ID0gc3QubnVt'
    || 'YmVyX2lucHV0KAogICAgICAgICAgICAgICAgbGFiZWwsIGtleT1rZXksIGhlbHA9aGVscF90eHQsCiAgICAgICAgICAgICAgICBtaW5fdmFsdWU9ZmxvYXQo'
    || 'bG8pIGlmIGxvIGlzIG5vdCBOb25lIGVsc2UgTm9uZSwKICAgICAgICAgICAgICAgIG1heF92YWx1ZT1mbG9hdChoaSkgaWYgaGkgaXMgbm90IE5vbmUgZWxz'
    || 'ZSBOb25lLAogICAgICAgICAgICAgICAgdmFsdWU9ZmxvYXQobG8pIGlmIGxvIGlzIG5vdCBOb25lIGVsc2UgMC4wLAogICAgICAgICAgICAgICAgc3RlcD0x'
    || 'LjApCiAgICAgICAgICAgICMgRW1pdCB3aG9sZSBudW1iZXJzIHdpdGhvdXQgYSB0cmFpbGluZyAuMDogQVJDSElWRV9GT1JfREFZUyA9IDkwLjAgaXMgbm90'
    || 'CiAgICAgICAgICAgICMgdmFsaWQgaW4gdGhlIERETCBjbGF1c2UgdGhpcyBsYW5kcyBpbi4KICAgICAgICAgICAgdmFsc1tuYW1lXSA9IHN0cihpbnQodikp'
    || 'IGlmIGZsb2F0KHYpLmlzX2ludGVnZXIoKSBlbHNlIHN0cih2KQogICAgICAgICAgICBjb250aW51ZQogICAgICAgIGNob2ljZXMgPSBhY3Rpb25fcGFyYW1f'
    || 'b3B0aW9ucyhzZXNzaW9uLCBwKQogICAgICAgIGlmIGNob2ljZXM6CiAgICAgICAgICAgICMgaW5kZXg9Tm9uZSBzbyBub3RoaW5nIGlzIHByZS1zZWxlY3Rl'
    || 'ZC4gQSBwcmUtZmlsbGVkIHRhcmdldCBpcyBob3cgc29tZW9uZQogICAgICAgICAgICAjIHJ1bnMgYSBjaGFuZ2UgYWdhaW5zdCB3aGF0ZXZlciBoYXBwZW5l'
    || 'ZCB0byBzb3J0IGZpcnN0LgogICAgICAgICAgICB2ID0gc3Quc2VsZWN0Ym94KGxhYmVsLCBjaG9pY2VzLCBpbmRleD1Ob25lLCBrZXk9a2V5LCBoZWxwPWhl'
    || 'bHBfdHh0LAogICAgICAgICAgICAgICAgICAgICAgICAgICAgIHBsYWNlaG9sZGVyPSJDaG9vc2UgIiArIGxhYmVsLmxvd2VyKCkpCiAgICAgICAgICAgIGlm'
    || 'IHYgaXMgTm9uZToKICAgICAgICAgICAgICAgIG1pc3NpbmcgPSBUcnVlCiAgICAgICAgICAgIGVsc2U6CiAgICAgICAgICAgICAgICB2YWxzW25hbWVdID0g'
    || 'c3RyKHYpCiAgICAgICAgZWxpZiBwLmdldCgiRlJFRUZPUk0iKToKICAgICAgICAgICAgIyBBIG5hbWUgYmVpbmcgQ1JFQVRFRCBjYW5ub3QgYmUgY2hlY2tl'
    || 'ZCBhZ2FpbnN0IGEgbGlzdCBvZiB0aGluZ3MgdGhhdAogICAgICAgICAgICAjIGFscmVhZHkgZXhpc3QsIHNvIHRoaXMgb25lIGlzIHR5cGVkLiBJdCBpcyBu'
    || 'b3QgdW52YWxpZGF0ZWQ6IHRoZSBwcm9jZWR1cmUKICAgICAgICAgICAgIyBzdGlsbCBhcHBsaWVzIHRoZSBpZGVudGlmaWVyIHNoYXBlIGdhdGUsIHNvIGFu'
    || 'eXRoaW5nIGNhcnJ5aW5nIGEgcXVvdGUsIGEKICAgICAgICAgICAgIyBzcGFjZSBvciBhIHN0YXRlbWVudCB0ZXJtaW5hdG9yIGlzIHJlZnVzZWQgc2VydmVy'
    || 'LXNpZGUuCiAgICAgICAgICAgIHYgPSBzdC50ZXh0X2lucHV0KGxhYmVsLCBrZXk9a2V5LCBoZWxwPWhlbHBfdHh0KQogICAgICAgICAgICBpZiBub3Qgc3Ry'
    || 'KHYgb3IgIiIpLnN0cmlwKCk6CiAgICAgICAgICAgICAgICBtaXNzaW5nID0gVHJ1ZQogICAgICAgICAgICBlbHNlOgogICAgICAgICAgICAgICAgdmFsc1tu'
    || 'YW1lXSA9IHN0cih2KS5zdHJpcCgpCiAgICAgICAgZWxzZToKICAgICAgICAgICAgc3QuY2FwdGlvbihsYWJlbCArICIg4oCUIG5vIHBlcm1pdHRlZCB2YWx1'
    || 'ZXMgYXJlIGF2YWlsYWJsZSBmb3IgdGhpcyBidWlsZCwgIgogICAgICAgICAgICAgICAgICAgICAgICJzbyB0aGlzIGFjdGlvbiBjYW5ub3QgcnVuLiBOb3Ro'
    || 'aW5nIGlzIHN3aXRjaGVkIG9mZjsgdGhlcmUgaXMgIgogICAgICAgICAgICAgICAgICAgICAgICJzaW1wbHkgbm90aGluZyBpdCBjb3VsZCBsZWdhbGx5IGJl'
    || 'IHBvaW50ZWQgYXQuIikKICAgICAgICAgICAgbWlzc2luZyA9IFRydWUKICAgIHJldHVybiB2YWxzLCBub3QgbWlzc2luZwoKCmRlZiBwcm9tb3Rpb25fYmFy'
    || 'KHNlc3Npb24sIHRndDogc3RyKSAtPiBOb25lOgogICAgIiIiVGhlIG9uZSBwbGFjZSBpbiB0aGUgYXBwIHRoYXQgY2FuIGNoYW5nZSB0aGUgYWNjb3VudC4K'
    || 'CiAgICBOYXRpdmUgU3RyZWFtbGl0IHJhdGhlciB0aGFuIHBhcnQgb2YgdGhlIFJlYWN0IHBhZ2UsIGFuZCBub3QgYnkgcHJlZmVyZW5jZToKICAgIHRoZSBi'
    || 'dW5kbGUgcnVucyBpbnNpZGUgY29tcG9uZW50cy5odG1sLCB3aGljaCBpcyBhIHNhbmRib3hlZCBjcm9zcy1vcmlnaW4KICAgIGlmcmFtZSB3aXRoIG5vIFNu'
    || 'b3dmbGFrZSBzZXNzaW9uLCBzbyBhIFJlYWN0IGJ1dHRvbiBwaHlzaWNhbGx5IGNhbm5vdCBleGVjdXRlCiAgICBhbnl0aGluZy4gVGhlIGJpZGlyZWN0aW9u'
    || 'YWwgYWx0ZXJuYXRpdmUgKHN0LmNvbXBvbmVudHMudjIpIG5lZWRzIFN0cmVhbWxpdAogICAgMS41NyssIGFuZCB3YXJlaG91c2UgcnVudGltZXMgY2FwIGF0'
    || 'IDEuNTIuMi4gU28gdGhlIGRpc3BsYXkgaXMgUmVhY3QgYW5kIHRoZQogICAgY29udHJvbHMgYXJlIFN0cmVhbWxpdCwgc3R5bGVkIHRvIHNpdCB3aXRoIGl0'
    || 'LgoKICAgIERlbGliZXJhdGVseSB1c2VzIG5vIHN0Lm1hcmtkb3duOiB0aGUgaG9zdCBjaGVjayB0cmVhdHMgc3RyYXkgbWFya2Rvd24gYXMKICAgIHBhZ2Ug'
    || 'Y29udGVudCBsZWFraW5nIG91dHNpZGUgdGhlIGNvbXBvbmVudCwgd2hpY2ggaXMgaG93IGEgc3BsaWNlZCBkb2NzdHJpbmcKICAgIG9uY2Ugc2hpcHBlZCB0'
    || 'aGUgd2hvbGUgYXBwIGFzIGEgdHJhY2ViYWNrLiBXaWRnZXRzIGFyZSBpbnRlbnRpb25hbCBhbmQKICAgIGV4ZW1wdDsgcHJvc2UgaXMgbm90LgogICAgIiIi'
    || 'CiAgICAoYWxsb3dfcmVhbCwgYWxsb3dfc2FtcGxlKSwgcm93cyA9IGxvYWRfYWN0aW9ucyhzZXNzaW9uLCB0Z3QpCgogICAgIyBUaGUgc3RhbmRpbmcgY29z'
    || 'dCBwcmludHMgd2hldGhlciBvciBub3QgdGhpcyBidWlsZCByZWdpc3RlcmVkIGFueSBhY3Rpb25zLAogICAgIyBhbmQgQkVGT1JFIHRoZW0sIGJlY2F1c2Ug'
    || 'aXQgaXMgdGhlIHJlY3VycmluZyBudW1iZXIuIEVhY2ggYnV0dG9uIGJlbG93CiAgICAjIGNvc3RzIHNvbWV0aGluZyBPTkNFOyB0aGlzIGlzIHdoYXQgdGhl'
    || 'IGJ1aWxkIGNvc3RzIGV2ZXJ5IG1vbnRoIGlmIG5vYm9keQogICAgIyB0b3VjaGVzIGl0IGFnYWluLiBEZWxpYmVyYXRlbHkgbm90IHN1bW1lZCB3aXRoIHRo'
    || 'ZSBwZXItYWN0aW9uIGVzdGltYXRlcyAtLQogICAgIyBvbmUgaXMgUFJPSkVDVEVEIGFuZCB0aGUgb3RoZXIgaXMgbWVhc3VyZWQsIGFuZCBhZGRpbmcgdGhl'
    || 'bSB3b3VsZCBpbnZlbnQgYQogICAgIyBmaWd1cmUgdGhhdCBtZWFucyBub3RoaW5nLgogICAgaGwgPSBsb2FkX2hlYWRsaW5lKHNlc3Npb24sIHRndCkKICAg'
    || 'IGlmIGhsIGlzIG5vdCBOb25lIGFuZCBobFswXToKICAgICAgICBzdC5jYXB0aW9uKCJXSEFUIFRISVMgQ09TVFMgVE8gTEVBVkUgUlVOTklORyIpCiAgICAg'
    || 'ICAgc3QuY2FwdGlvbihobFswXSkKCiAgICBpZiBub3Qgcm93czoKICAgICAgICByZXR1cm4KCiAgICBzdC5jYXB0aW9uKCJXSEFUIFRISVMgQ0FOIERPIE5F'
    || 'WFQiKQogICAgIyBPbmx5IHdhcm4gYWJvdXQgd2hhdCBpcyBhY3R1YWxseSBzd2l0Y2hlZCBvZmYuIEFubm91bmNpbmcgInRoZXNlIGFyZSBzd2l0Y2hlZAog'
    || 'ICAgIyBvZmYiIG92ZXIgYSBsaXN0IGNvbnRhaW5pbmcgbGl2ZSBTQU1QTEUgYnV0dG9ucyBpcyB3b3JzZSB0aGFuIHNpbGVuY2U6IHRoZQogICAgIyByZWFk'
    || 'ZXIgYmVsaWV2ZXMgaXQgYW5kIHN0b3BzIHRyeWluZy4KICAgIGlmIG5vdCBhbGxvd19yZWFsIGFuZCBub3QgYWxsb3dfc2FtcGxlOgogICAgICAgIHBmeCA9'
    || 'IGxvYWRfcHJlZml4KHNlc3Npb24sIHRndCkKICAgICAgICAjIE5hbWUgdGhlIGxpbmUsIG5vdCB0aGUgc2V0dGluZy4gInJlLXJ1biB3aXRoIEFMTE9XX0FD'
    || 'VElPTlMgPSBUUlVFIiBzZW50CiAgICAgICAgIyB0aGUgcmVhZGVyIGxvb2tpbmcgZm9yIGEgc2V0dGluZyB0aGF0IGFwcGVhcnMgaW4gbm8gZmlsZSB1bmRl'
    || 'ciB0aGF0CiAgICAgICAgIyBuYW1lLCB3aGljaCBpcyBob3cgYSBwdXNoLWJ1dHRvbiBkZXBsb3ltZW50IGNhbWUgdG8gbG9vayBsaWtlIGl0IG5lZWRlZAog'
    || 'ICAgICAgICMgYSB0ZXJtaW5hbCBzZXNzaW9uIGFuZCBzb21lIGd1ZXNzd29yay4KICAgICAgICBhcm0gPSAoIlNFVCAiICsgcGZ4ICsgIl9BTExPV19BQ1RJ'
    || 'T05TID0gVFJVRTsiKSBpZiBwZnggZWxzZSAiQUxMT1dfQUNUSU9OUyA9IFRSVUUiCiAgICAgICAgc3QuaW5mbygKICAgICAgICAgICAgIlRoZXNlIGFyZSBz'
    || 'd2l0Y2hlZCBvZmYuIFRoaXMgYnVpbGQgd2FzIGNyZWF0ZWQgd2l0aCAiCiAgICAgICAgICAgICJBTExPV19BQ1RJT05TID0gRkFMU0UsIHNvIHRoZSBidXR0'
    || 'b25zIGJlbG93IGFyZSBpbmVydCBhbmQgdGhlICIKICAgICAgICAgICAgInByb2NlZHVyZSBiZWhpbmQgdGhlbSByZWZ1c2VzLiBFdmVyeXRoaW5nIGVhY2gg'
    || 'b25lIHdvdWxkIGRvLCBhbmQgIgogICAgICAgICAgICAid2hhdCBpdCB3b3VsZCBjb3N0LCBpcyBsaXN0ZWQgYW55d2F5IOKAlCB0byBhcm0gdGhlbSwgY2hh'
    || 'bmdlIHRoZSAiCiAgICAgICAgICAgICJsaW5lIG5lYXIgdGhlIHRvcCBvZiB0aGUgc2NyaXB0IHlvdSBhbHJlYWR5IHJhbiB0byAiCiAgICAgICAgICAgICsg'
    || 'YXJtICsgIiBhbmQgcnVuIHRoYXQgZmlsZSBhZ2Fpbi4gVGhlcmUgaXMgbm90aGluZyBlbHNlIHRvIHR5cGU6ICIKICAgICAgICAgICAgInRoZSBmaWxlIGlz'
    || 'IHRoZSBvbmx5IHBsYWNlIHRoaXMgaXMgc3dpdGNoZWQgb24sIGFuZCBydW5uaW5nIGl0IGlzICIKICAgICAgICAgICAgInRoZSB3aG9sZSBwcm9jZWR1cmUu'
    || 'IiwKICAgICAgICAgICAgaWNvbj0iOm1hdGVyaWFsL2xvY2s6IikKCiAgICBieV90aWVyID0ge30KICAgIGZvciByIGluIHJvd3M6CiAgICAgICAgYnlfdGll'
    || 'ci5zZXRkZWZhdWx0KHN0cihyLmdldCgiVElFUiIpIG9yICJQUk9EVUNUSU9OIikudXBwZXIoKSwgW10pLmFwcGVuZChyKQoKICAgIGZvciB0aWVyIGluIFRJ'
    || 'RVJfT1JERVI6CiAgICAgICAgZ3JvdXAgPSBieV90aWVyLmdldCh0aWVyLCBbXSkKICAgICAgICBpZiBub3QgZ3JvdXA6CiAgICAgICAgICAgIGNvbnRpbnVl'
    || 'CiAgICAgICAgIyBTQU1QTEUgcnVucyBvbiBzZWVkZWQgZGF0YSB0aGlzIHNjcmlwdCBjcmVhdGVkLCBzbyBpdCBhbnN3ZXJzIHRvCiAgICAgICAgIyBBTExP'
    || 'V19TQU1QTEVfQUNUSU9OUy4gRXZlcnl0aGluZyBlbHNlIHRvdWNoZXMgdGhlIGN1c3RvbWVyJ3Mgb3duIG9iamVjdHMKICAgICAgICAjIGFuZCBhbnN3ZXJz'
    || 'IHRvIEFMTE9XX0FDVElPTlMuIFVua25vd24gdGllcnMgdGFrZSB0aGUgc3RyaWN0ZXIgZ2F0ZS4KICAgICAgICB0aWVyX2VuYWJsZWQgPSBhbGxvd19zYW1w'
    || 'bGUgaWYgdGllciA9PSAiU0FNUExFIiBlbHNlIGFsbG93X3JlYWwKICAgICAgICBzdC5jYXB0aW9uKHRpZXIgKyAiIOKAlCAiICsgVElFUl9CTFVSQi5nZXQo'
    || 'dGllciwgIiIpCiAgICAgICAgICAgICAgICAgICArICgiIiBpZiB0aWVyX2VuYWJsZWQgZWxzZQogICAgICAgICAgICAgICAgICAgICAgIiAgwrcgIHN3aXRj'
    || 'aGVkIG9mZiBpbiB0aGUgZmlsZSIpKQogICAgICAgIGNvbHMgPSBzdC5jb2x1bW5zKGxlbihncm91cCkpCiAgICAgICAgZm9yIGNvbCwgciBpbiB6aXAoY29s'
    || 'cywgZ3JvdXApOgogICAgICAgICAgICB3aXRoIGNvbDoKICAgICAgICAgICAgICAgIGNvZGUgPSBzdHIoci5nZXQoIkNPREUiKSBvciAiIikKICAgICAgICAg'
    || 'ICAgICAgIGVzdCA9IHIuZ2V0KCJFU1RfQ1JFRElUUyIpCiAgICAgICAgICAgICAgICAjIFRocmVlIGxpbmVzIGFuZCBhIGJ1dHRvbiwgbm90IGZpdmUgbGlu'
    || 'ZXMgYW5kIGEgYnV0dG9uLiBUaGUKICAgICAgICAgICAgICAgICMgZXN0aW1hdGUgYW5kIGl0cyBiYXNpcyBzdGlsbCB0cmF2ZWwgV0lUSCB0aGUgY29udHJv'
    || 'bCAtLSBhIGJ1dHRvbgogICAgICAgICAgICAgICAgIyB0aGF0IGNoYW5nZXMgcHJvZHVjdGlvbiB3aXRob3V0IHNheWluZyB3aGF0IGl0IGNvc3RzIGlzIHRo'
    || 'ZSB0aGluZwogICAgICAgICAgICAgICAgIyB0aGlzIHJlcG8gZXhpc3RzIHRvIGF2b2lkIC0tIGJ1dCBgYmFzaXNgIGFuZCBgdW5kb2AgYmVsb25nIGluIHRo'
    || 'ZQogICAgICAgICAgICAgICAgIyB0b29sdGlwLiBSZW5kZXJlZCBhcyBjb2x1bW5zIG9mIGJvZHkgdGV4dCB0aGV5IHdlcmUgZm91ciBsaW5lcyBvZgogICAg'
    || 'ICAgICAgICAgICAgIyBwcm9zZSBlYWNoLCBhbmQgdGhlIHJlYWRlciBzdG9wcGVkIGJlZm9yZSB0aGUgYnV0dG9uLgogICAgICAgICAgICAgICAgc3QuY2Fw'
    || 'dGlvbigiKioiICsgc3RyKHIuZ2V0KCJMQUJFTCIpIG9yIGNvZGUpICsgIioqIikKICAgICAgICAgICAgICAgIHN0LmNhcHRpb24oIn4iICsgZm10X2NyZWRp'
    || 'dHMoZXN0KSArICIgY3JlZGl0cyDCtyAiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICsgc3RyKHIuZ2V0KCJTVEFURU1FTlRTIikgb3IgMCkgKyAiIHN0'
    || 'YXRlbWVudChzKSIKICAgICAgICAgICAgICAgICAgICAgICAgICAgKyAoIiDCtyBydW4gIiArIHN0cihyWyJUSU1FU19SVU4iXSkgKyAieCBhbHJlYWR5Igog'
    || 'ICAgICAgICAgICAgICAgICAgICAgICAgICAgICBpZiByLmdldCgiVElNRVNfUlVOIikgZWxzZSAiIikpCiAgICAgICAgICAgICAgICBzdC5jYXB0aW9uKHN0'
    || 'cihyLmdldCgiRUZGRUNUIikgb3IgIm5vdCBzdGF0ZWQiKSkKICAgICAgICAgICAgICAgIGlmIHN0LmJ1dHRvbigiUnVuICIgKyBjb2RlLCBrZXk9ImFybV8i'
    || 'ICsgY29kZSwgZGlzYWJsZWQ9bm90IHRpZXJfZW5hYmxlZCwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICB1c2VfY29udGFpbmVyX3dpZHRoPVRydWUs'
    || 'CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgaGVscD0iRXN0aW1hdGUgYmFzaXM6ICIgKyBzdHIoci5nZXQoIkVTVF9CQVNJUyIpIG9yICJub3Qgc3Rh'
    || 'dGVkIikKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICsgIlxuXG5UbyB1bmRvOiAiICsgc3RyKHIuZ2V0KCJVTkRPIikgb3IgIm5vdCBzdGF0'
    || 'ZWQiKSk6CiAgICAgICAgICAgICAgICAgICAgc3Quc2Vzc2lvbl9zdGF0ZVsiYXJtZWQiXSA9IGNvZGUKICAgICAgICAgICAgICAgICAgICBzdC5zZXNzaW9u'
    || 'X3N0YXRlLnBvcCgicmVzdWx0XyIgKyBjb2RlLCBOb25lKQogICAgICAgICAgICAgICAgIyBVbmRvIGFwcGVhcnMgb25seSBvbmNlIHRoZSBhY3Rpb24gaGFz'
    || 'IGFjdHVhbGx5IGNvbXBsZXRlZCwgYmVjYXVzZQogICAgICAgICAgICAgICAgIyBVTkRPX0FDVElPTiByZWZ1c2VzIG90aGVyd2lzZSBhbmQgYSBidXR0b24g'
    || 'd2hvc2Ugb25seSBvdXRjb21lIGlzIGEKICAgICAgICAgICAgICAgICMgcmVmdXNhbCB0ZWFjaGVzIHRoZSByZWFkZXIgdG8gZGlzdHJ1c3QgYWxsIG9mIHRo'
    || 'ZW0uIEFuIGFjdGlvbiB3aXRoCiAgICAgICAgICAgICAgICAjIG5vIHJldmVyc2Ugc3RhdGVtZW50cyBuZXZlciBzaG93cyBvbmUgYXQgYWxsIC0tIHNheWlu'
    || 'ZyAibm90CiAgICAgICAgICAgICAgICAjIHJldmVyc2libGUiIHBsYWlubHkgYmVhdHMgb2ZmZXJpbmcgYSBjb250cm9sIHRoYXQgY2Fubm90IHdvcmsuCiAg'
    || 'ICAgICAgICAgICAgICBpZiByLmdldCgiVU5ET19TVEFURU1FTlRTIikgYW5kIHIuZ2V0KCJUSU1FU19SVU4iKToKICAgICAgICAgICAgICAgICAgICBpZiBz'
    || 'dC5idXR0b24oIlVuZG8gIiArIGNvZGUsIGtleT0idW5kb2FybV8iICsgY29kZSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgZGlzYWJsZWQ9'
    || 'bm90IHRpZXJfZW5hYmxlZCwgdXNlX2NvbnRhaW5lcl93aWR0aD1UcnVlLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBoZWxwPSJSdW5zICIg'
    || 'KyBzdHIoclsiVU5ET19TVEFURU1FTlRTIl0pCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgKyAiIHJldmVyc2Ugc3RhdGVtZW50KHMp'
    || 'LiAiICsgc3RyKHIuZ2V0KCJVTkRPIikgb3IgIiIpKToKICAgICAgICAgICAgICAgICAgICAgICAgc3Quc2Vzc2lvbl9zdGF0ZVsiYXJtZWQiXSA9IGNvZGUK'
    || 'ICAgICAgICAgICAgICAgICAgICAgICAgc3Quc2Vzc2lvbl9zdGF0ZVsiYXJtZWRfdW5kbyJdID0gVHJ1ZQogICAgICAgICAgICAgICAgICAgICAgICBzdC5z'
    || 'ZXNzaW9uX3N0YXRlLnBvcCgicmVzdWx0XyIgKyBjb2RlLCBOb25lKQogICAgICAgICAgICAgICAgZWxpZiByLmdldCgiVElNRVNfUlVOIikgYW5kIG5vdCBy'
    || 'LmdldCgiVU5ET19TVEFURU1FTlRTIik6CiAgICAgICAgICAgICAgICAgICAgc3QuY2FwdGlvbigiTm8gYXV0b21hdGljIHVuZG8g4oCUIHNlZSB0aGUgdW5k'
    || 'byBub3RlIGluIHRoZSB0b29sdGlwLiIpCiAgICAgICAgICAgICAgICBpZiByLmdldCgiVElNRVNfVU5ET05FIik6CiAgICAgICAgICAgICAgICAgICAgc3Qu'
    || 'Y2FwdGlvbigiVW5kb25lICIgKyBzdHIoclsiVElNRVNfVU5ET05FIl0pICsgIngiKQoKICAgIGFybWVkID0gc3Quc2Vzc2lvbl9zdGF0ZS5nZXQoImFybWVk'
    || 'IikKICAgIHVuZG9pbmcgPSBib29sKHN0LnNlc3Npb25fc3RhdGUuZ2V0KCJhcm1lZF91bmRvIikpCiAgICAjIFJlc29sdmUgdGhlIEFSTUVEIGFjdGlvbidz'
    || 'IG93biB0aWVyLiBEZWxpYmVyYXRlbHkgbm90IGB0aWVyX2VuYWJsZWRgIGZyb20gdGhlCiAgICAjIGxvb3AgYWJvdmU6IHRoYXQgdmFyaWFibGUgaG9sZHMg'
    || 'd2hpY2hldmVyIHRpZXIgaGFwcGVuZWQgdG8gYmUgcmVuZGVyZWQgbGFzdCwKICAgICMgc28gcmV1c2luZyBpdCBoZXJlIHdvdWxkIGdhdGUgdGhlIGNvbmZp'
    || 'cm1hdGlvbiBvbiBhbiB1bnJlbGF0ZWQgYWN0aW9uLiBEZWZhdWx0CiAgICAjIHRvIHRoZSBzdHJpY3RlciBmbGFnIHdoZW4gdGhlIGNvZGUgY2Fubm90IGJl'
    || 'IGZvdW5kLgogICAgYXJtZWRfdGllciA9ICJQUk9EVUNUSU9OIgogICAgZm9yIHIgaW4gcm93czoKICAgICAgICBpZiBzdHIoci5nZXQoIkNPREUiKSBvciAi'
    || 'IikgPT0gc3RyKGFybWVkIG9yICIiKToKICAgICAgICAgICAgYXJtZWRfdGllciA9IHN0cihyLmdldCgiVElFUiIpIG9yICJQUk9EVUNUSU9OIikudXBwZXIo'
    || 'KQogICAgICAgICAgICBicmVhawogICAgYXJtZWRfZW5hYmxlZCA9IGFsbG93X3NhbXBsZSBpZiBhcm1lZF90aWVyID09ICJTQU1QTEUiIGVsc2UgYWxsb3df'
    || 'cmVhbAogICAgaWYgYXJtZWQgYW5kIGFybWVkX2VuYWJsZWQ6CiAgICAgICAgc3QuY2FwdGlvbigoIkNPTkZJUk0gVU5ETyBPRiAiIGlmIHVuZG9pbmcgZWxz'
    || 'ZSAiQ09ORklSTSAiKSArIGFybWVkKQogICAgICAgICMgUGFyYW1ldGVycyBhcmUgY2hvc2VuIEhFUkUsIGJlZm9yZSB0aGUgY29kZSBpcyB0eXBlZCwgYW5k'
    || 'IG9ubHkgZm9yIGEgZm9yd2FyZAogICAgICAgICMgcnVuLiBBbiB1bmRvIHRha2VzIG5vbmUgYnkgZGVzaWduOiBSVU5fQUNUSU9OIHJlc29sdmVkIGFuZCBz'
    || 'bmFwc2hvdHRlZCB0aGUKICAgICAgICAjIHJldmVyc2Ugc3RhdGVtZW50cyB3aGVuIHRoZSBhY3Rpb24gcmFuLCBzbyBVTkRPX0FDVElPTiByZXBsYXlzIHRo'
    || 'YXQgZXhhY3QKICAgICAgICAjIHRleHQuIE9mZmVyaW5nIHRoZSB2YWx1ZXMgYWdhaW4gd291bGQgaW52aXRlIHJldmVyc2luZyBhIGRpZmZlcmVudCB0YXJn'
    || 'ZXQKICAgICAgICAjIHRoYW4gdGhlIG9uZSB0aGF0IHdhcyBjaGFuZ2VkLCB3aGljaCBpcyB3b3JzZSB0aGFuIGhhdmluZyBubyB1bmRvLgogICAgICAgIHB2'
    || 'YWxzLCBwcmVhZHkgPSB7fSwgVHJ1ZQogICAgICAgIGlmIG5vdCB1bmRvaW5nOgogICAgICAgICAgICBhcGFyYW1zID0gbG9hZF9hY3Rpb25fcGFyYW1zKHNl'
    || 'c3Npb24sIHRndCkuZ2V0KGFybWVkLCBbXSkKICAgICAgICAgICAgaWYgYXBhcmFtczoKICAgICAgICAgICAgICAgIHN0LmNhcHRpb24oIkNob29zZSB3aGF0'
    || 'IGl0IHJ1bnMgYWdhaW5zdC4gVGhlc2UgYXJlIHRoZSBvbmx5IHZhbHVlcyB0aGlzICIKICAgICAgICAgICAgICAgICAgICAgICAgICAgImJ1aWxkIGRpc2Nv'
    || 'dmVyZWQgZm9yIGl0LCBhbmQgdGhlIHByb2NlZHVyZSByZS1jaGVja3MgeW91ciAiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICJjaG9pY2UgYWdhaW5z'
    || 'dCB0aGF0IHNhbWUgbGlzdCBiZWZvcmUgaXQgcnVucyBhbnl0aGluZy4iKQogICAgICAgICAgICAgICAgcHZhbHMsIHByZWFkeSA9IGFjdGlvbl9wYXJhbV92'
    || 'YWx1ZXMoc2Vzc2lvbiwgYXJtZWQsIGFwYXJhbXMpCiAgICAgICAgc3QuY2FwdGlvbigiVHlwZSB0aGUgYWN0aW9uIGNvZGUgZXhhY3RseS4gVGhpcyBpcyB0'
    || 'aGUgbGFzdCBzdGVwIGJlZm9yZSBpdCBydW5zLiIKICAgICAgICAgICAgICAgICAgICsgKCIgVGhpcyBSRVZFUlNFUyB0aGUgYWN0aW9uOyByZXZlcnNpbmcg'
    || 'YSBtYXNraW5nIHBvbGljeSBleHBvc2VzICIKICAgICAgICAgICAgICAgICAgICAgICJ0aGUgY29sdW1uIGFnYWluLCBzbyBpdCBpcyBhIGNoYW5nZSBsaWtl'
    || 'IGFueSBvdGhlci4iCiAgICAgICAgICAgICAgICAgICAgICBpZiB1bmRvaW5nIGVsc2UgIiIpKQogICAgICAgIHR5cGVkID0gc3QudGV4dF9pbnB1dCgiQ29u'
    || 'ZmlybWF0aW9uIiwga2V5PSJjb25maXJtXyIgKyBhcm1lZCwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgbGFiZWxfdmlzaWJpbGl0eT0iY29sbGFw'
    || 'c2VkIiwgcGxhY2Vob2xkZXI9YXJtZWQpCiAgICAgICAgYzEsIGMyID0gc3QuY29sdW1ucyhbMSwgNF0pCiAgICAgICAgd2l0aCBjMToKICAgICAgICAgICAg'
    || 'IyBEaXNhYmxlZCB1bnRpbCBldmVyeSBwYXJhbWV0ZXIgaGFzIGEgdmFsdWUuIFRoZSBwcm9jZWR1cmUgcmVmdXNlcyBhCiAgICAgICAgICAgICMgbWlzc2lu'
    || 'ZyBvbmUgYW55d2F5IC0tIHRoaXMgb25seSBhdm9pZHMgdGVhY2hpbmcgdGhlIHJlYWRlciB0aGF0IHRoZQogICAgICAgICAgICAjIGJ1dHRvbiBwcm9kdWNl'
    || 'cyByZWZ1c2Fscy4KICAgICAgICAgICAgZ28gPSBzdC5idXR0b24oIlJ1biBpdCIsIGtleT0iZ29fIiArIGFybWVkLCB0eXBlPSJwcmltYXJ5IiwKICAgICAg'
    || 'ICAgICAgICAgICAgICAgICAgICAgZGlzYWJsZWQ9bm90IHByZWFkeSkKICAgICAgICB3aXRoIGMyOgogICAgICAgICAgICBpZiBzdC5idXR0b24oIkNhbmNl'
    || 'bCIsIGtleT0iY2FuY2VsXyIgKyBhcm1lZCk6CiAgICAgICAgICAgICAgICBzdC5zZXNzaW9uX3N0YXRlLnBvcCgiYXJtZWQiLCBOb25lKQogICAgICAgICAg'
    || 'ICAgICAgc3Quc2Vzc2lvbl9zdGF0ZS5wb3AoImFybWVkX3VuZG8iLCBOb25lKQogICAgICAgICAgICAgICAgZ28gPSBGYWxzZQogICAgICAgIGlmIGdvOgog'
    || 'ICAgICAgICAgICAjIFRoZSB0eXBlZCB2YWx1ZSBpcyBwYXNzZWQgYXMgYSBCSU5ELCBuZXZlciBjb25jYXRlbmF0ZWQuIEl0IGlzCiAgICAgICAgICAgICMg'
    || 'YXR0YWNrZXItY29udHJvbGxlZCB0ZXh0IGdvaW5nIGludG8gYSBwcm9jZWR1cmUgY2FsbCwgYW5kIHRoZQogICAgICAgICAgICAjIHByb2NlZHVyZSBjb21w'
    || 'YXJlcyBpdCB0byB0aGUgY29kZSByYXRoZXIgdGhhbiBleGVjdXRpbmcgaXQgLS0gYnV0CiAgICAgICAgICAgICMgYmluZGluZyBpcyB3aGF0IG1ha2VzIHRo'
    || 'YXQgdHJ1ZSByZWdhcmRsZXNzIG9mIHdoYXQgd2FzIHR5cGVkLgogICAgICAgICAgICAjCiAgICAgICAgICAgICMgVGhlIHBhcmFtZXRlciB2YWx1ZXMgYXJl'
    || 'IGJvdW5kIHRvbywgYXMgb25lIEpTT04gc3RyaW5nLiBUaGV5IGNhbm5vdCBiZQogICAgICAgICAgICAjIGJvdW5kIGFzIGFuIE9CSkVDVCAtLSBhbmQgSlNP'
    || 'TiB0ZXh0IGlzIHdoYXQgVU5ET19TTkFQU0hPVCBhbHJlYWR5IHVzZXMsCiAgICAgICAgICAgICMgZm9yIHRoZSBkb2N1bWVudGVkIHJlYXNvbiB0aGF0IGFu'
    || 'IEFSUkFZIGJpbmQgaXMgZnJhZ2lsZSB3aGlsZQogICAgICAgICAgICAjIFRPX0pTT04vUEFSU0VfSlNPTiByb3VuZC10cmlwcyBleGFjdGx5LiBCaW5kaW5n'
    || 'IGlzIG5vdCB3aGF0IG1ha2VzIHRoZW0KICAgICAgICAgICAgIyBzYWZlOiB0aGUgcHJvY2VkdXJlIHZhbGlkYXRlcyBldmVyeSB2YWx1ZSBhZ2FpbnN0IHRo'
    || 'ZSByZWdpc3RyeSdzIG93bgogICAgICAgICAgICAjIGFsbG93ZWQgbGlzdCBiZWZvcmUgaW50ZXJwb2xhdGluZyBhbnkgb2YgdGhlbS4gQmluZGluZyBqdXN0'
    || 'IG1lYW5zIHRoZQogICAgICAgICAgICAjIGNhbGwgaXRzZWxmIGNhbm5vdCBiZSBicm9rZW4gYnkgd2hhdCB3YXMgY2hvc2VuLgogICAgICAgICAgICAjCiAg'
    || 'ICAgICAgICAgICMgQW4gYWN0aW9uIHdpdGggbm8gcGFyYW1ldGVycyB0YWtlcyB0aGUgVFdPLUFSR1VNRU5UIHBhdGgsIHVuY2hhbmdlZCwgc28KICAgICAg'
    || 'ICAgICAgIyBldmVyeSBleGlzdGluZyBzb2x1dGlvbiBjYWxscyBleGFjdGx5IHdoYXQgaXQgY2FsbGVkIGJlZm9yZS4KICAgICAgICAgICAgaWYgcHZhbHM6'
    || 'CiAgICAgICAgICAgICAgICBwcm9jID0gIi5SVU5fQUNUSU9OKD8sID8sID8pIgogICAgICAgICAgICAgICAgYXJncyA9IFthcm1lZCwgdHlwZWQsIGpzb24u'
    || 'ZHVtcHMocHZhbHMpXQogICAgICAgICAgICBlbHNlOgogICAgICAgICAgICAgICAgcHJvYyA9ICIuVU5ET19BQ1RJT04oPywgPykiIGlmIHVuZG9pbmcgZWxz'
    || 'ZSAiLlJVTl9BQ1RJT04oPywgPykiCiAgICAgICAgICAgICAgICBhcmdzID0gW2FybWVkLCB0eXBlZF0KICAgICAgICAgICAgdHJ5OgogICAgICAgICAgICAg'
    || 'ICAgb3V0ID0gc2Vzc2lvbi5zcWwoIkNBTEwgIiArIHRndCArIHByb2MsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBwYXJhbXM9YXJncyku'
    || 'Y29sbGVjdCgpWzBdWzBdCiAgICAgICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZXhjOgogICAgICAgICAgICAgICAgb3V0ID0gIkZBSUxFRCB0byBjYWxs'
    || 'ICIgKyBwcm9jLnNwbGl0KCIoIilbMF0uc3RyaXAoIi4iKSArICI6ICIgKyBzdHIoZXhjKQogICAgICAgICAgICBzdC5zZXNzaW9uX3N0YXRlWyJyZXN1bHRf'
    || 'IiArIGFybWVkXSA9IHN0cihvdXQpCiAgICAgICAgICAgIHN0LnNlc3Npb25fc3RhdGUucG9wKCJhcm1lZCIsIE5vbmUpCiAgICAgICAgICAgIHN0LnNlc3Np'
    || 'b25fc3RhdGUucG9wKCJhcm1lZF91bmRvIiwgTm9uZSkKICAgICAgICAgICAgaW52YWxpZGF0ZV9wYW5lbF9jYWNoZSgpCiAgICAgICAgICAgIHN0LnJlcnVu'
    || 'KCkKCiAgICBmb3IgayBpbiBbayBmb3IgayBpbiBzdC5zZXNzaW9uX3N0YXRlIGlmIHN0cihrKS5zdGFydHN3aXRoKCJyZXN1bHRfIildOgogICAgICAgIG1z'
    || 'ZyA9IHN0cihzdC5zZXNzaW9uX3N0YXRlW2tdKQogICAgICAgIGlmIG1zZy5zdGFydHN3aXRoKCJET05FIikgb3IgbXNnLnN0YXJ0c3dpdGgoIlVORE9ORSIp'
    || 'OgogICAgICAgICAgICBzdC5zdWNjZXNzKG1zZywgaWNvbj0iOm1hdGVyaWFsL2NoZWNrOiIpCiAgICAgICAgZWxpZiBtc2cuc3RhcnRzd2l0aCgiUEFSVElB'
    || 'TExZIFVORE9ORSIpOgogICAgICAgICAgICAjIE5vdCBhbiBlcnJvciBhbmQgbm90IGEgc3VjY2Vzczogc29tZSBvZiB0aGUgYWNjb3VudCBjYW1lIGJhY2sg'
    || 'YW5kIHNvbWUKICAgICAgICAgICAgIyBkaWQgbm90LCBhbmQgdGhlIHJlYWRlciBoYXMgdG8ga25vdyB3aGljaCB3aXRob3V0IGd1ZXNzaW5nLgogICAgICAg'
    || 'ICAgICBzdC53YXJuaW5nKG1zZywgaWNvbj0iOm1hdGVyaWFsL3dhcm5pbmc6IikKICAgICAgICBlbGlmIG1zZy5zdGFydHN3aXRoKCJSRUZVU0VEIik6CiAg'
    || 'ICAgICAgICAgIHN0Lndhcm5pbmcobXNnLCBpY29uPSI6bWF0ZXJpYWwvYmxvY2s6IikKICAgICAgICBlbHNlOgogICAgICAgICAgICBzdC5lcnJvcihtc2cs'
    || 'IGljb249IjptYXRlcmlhbC9lcnJvcjoiKQogICAgc3QuZGl2aWRlcigpCgoKZGVmIGxvYWRfYWdlbnQoc2Vzc2lvbiwgdGd0OiBzdHIpOgogICAgIiIiVGhl'
    || 'IGRlY2xhcmVkIGFnZW50LCBvciBOb25lLgoKICAgIEdhdGVzIG9uIHdoZXRoZXIgdGhlIHNvbHV0aW9uIGJ1aWx0IFZfQUdFTlRfQ0hBVCwgZXhhY3RseSBh'
    || 'cyBsb2FkX2FjdGlvbnMgZ2F0ZXMKICAgIG9uIFZfQUNUSU9OUyBhbmQgbG9hZF9ydWxlX2NvbmZpZyBvbiBWX1JVTEVfQ09ORklHLiBTaXggc29sdXRpb25z'
    || 'IGFscmVhZHkgYnVpbGQKICAgIGFuIGFnZW50IHByb2NlZHVyZSB0aGF0IG5vdGhpbmcgY291bGQgcmVhY2ggLS0gQVNLX0dPVkVSTkFOQ0UsCiAgICBESUFH'
    || 'Tk9TRV9GQUlMVVJFLCBFWFBMQUlOX1BSSVZBQ1lfQkxPQ0ssIEFTU0VTU19NSUdSQVRJT04gYW5kIGZyaWVuZHMgd2VyZQogICAgY2FsbGFibGUgb25seSBm'
    || 'cm9tIGEgd29ya3NoZWV0LiBEZWNsYXJpbmcgb25lIHZpZXcgbm93IHN1cmZhY2VzIGl0LgoKICAgIEEgc29sdXRpb24gd2hvc2UgYWdlbnQgZGVwZW5kcyBv'
    || 'biBDb3J0ZXggYmVpbmcgYXZhaWxhYmxlIG11c3QgY3JlYXRlIHRoaXMgdmlldwogICAgaW5zaWRlIHRoZSBzYW1lIGF2YWlsYWJpbGl0eSBjaGVjayB0aGF0'
    || 'IGNyZWF0ZXMgdGhlIHByb2NlZHVyZSwgc28gdGhhdCB0aGUgY2hhdAogICAgbmV2ZXIgYXBwZWFycyBmb3IgYSBidWlsZCB3aGVyZSB0aGUgbW9kZWwgd2Fz'
    || 'IHVucmVhY2hhYmxlLgogICAgIiIiCiAgICB0cnk6CiAgICAgICAgcm93cyA9IFtyLmFzX2RpY3QoKSBmb3IgciBpbiBzZXNzaW9uLnNxbCgKICAgICAgICAg'
    || 'ICAgIlNFTEVDVCBBR0VOVF9MQUJFTCwgUFJPQ19OQU1FLCBQTEFDRUhPTERFUiwgQkxVUkIgIgogICAgICAgICAgICAiRlJPTSAiICsgdGd0ICsgIi5WX0FH'
    || 'RU5UX0NIQVQiKS5jb2xsZWN0KCldCiAgICBleGNlcHQgRXhjZXB0aW9uOgogICAgICAgIHJldHVybiBOb25lCiAgICBpZiBub3Qgcm93czoKICAgICAgICBy'
    || 'ZXR1cm4gTm9uZQogICAgYSA9IHJvd3NbMF0KICAgICMgVGhlIHByb2NlZHVyZSBOQU1FIGNhbm5vdCBiZSBhIGJpbmQgLS0gaXQgaXMgYW4gaWRlbnRpZmll'
    || 'ciwgc28gaXQgaGFzIHRvIGJlCiAgICAjIGNvbmNhdGVuYXRlZCBpbnRvIHRoZSBDQUxMLiBJdCBjb21lcyBmcm9tIGEgdmlldyB0aGlzIGJ1aWxkIGNyZWF0'
    || 'ZWQgcmF0aGVyCiAgICAjIHRoYW4gZnJvbSBhbnl0aGluZyBhIHJlYWRlciB0eXBlZCwgYnV0IGl0IGlzIHZhbGlkYXRlZCBhbnl3YXk6IGEgdmlldyBpcyBh'
    || 'CiAgICAjIHRoaW5nIHNvbWVvbmUgY2FuIGxhdGVyIEFMVEVSLCBhbmQgdGhlIGNvc3Qgb2YgYmVpbmcgd3JvbmcgaGVyZSBpcyBhcmJpdHJhcnkKICAgICMg'
    || 'U1FMIHJ1bm5pbmcgYXMgdGhlIGFwcCBvd25lci4gVGhlIHF1ZXN0aW9uIGl0c2VsZiBJUyBib3VuZC4KICAgIHByb2MgPSBzdHIoYS5nZXQoIlBST0NfTkFN'
    || 'RSIpIG9yICIiKQogICAgaWYgbm90IHJlLmZ1bGxtYXRjaChyIltBLVphLXpfXVtBLVphLXowLTlfXSoiLCBwcm9jKToKICAgICAgICByZXR1cm4gTm9uZQog'
    || 'ICAgYVsiUFJPQ19OQU1FIl0gPSBwcm9jCiAgICByZXR1cm4gYQoKCmRlZiBhZ2VudF9iYXIoc2Vzc2lvbiwgdGd0OiBzdHIpIC0+IE5vbmU6CiAgICAiIiJB'
    || 'c2sgdGhlIHNvbHV0aW9uJ3Mgb3duIGFnZW50IGEgcXVlc3Rpb24sIGluIHRoZSBhcHAuCgogICAgQkVUV0VFTiB0aGUgcnVsZXMgYW5kIHRoZSBhY3Rpb25z'
    || 'LCB3aGljaCBpcyB0aGUgcmVhZGluZyBvcmRlciB0aGUgcGFnZSBhbHJlYWR5CiAgICBhcmd1ZXMgZm9yOiB0aGUgZGFzaGJvYXJkIHNheXMgd2hhdCBpcyB0'
    || 'cnVlLCBjb25maWdfYmFyIHR1bmVzIGhvdyBpdCB3YXMKICAgIGRlY2lkZWQsIHRoaXMgZXhwbGFpbnMgaXQgaW4gd29yZHMsIGFuZCBwcm9tb3Rpb25fYmFy'
    || 'IGFjdHMgb24gaXQuIEFuIGFuc3dlciBpcwogICAgbW9zdCB1c2VmdWwgaW1tZWRpYXRlbHkgYmVmb3JlIHRoZSBkZWNpc2lvbiBpdCBpbmZvcm1zLgoKICAg'
    || 'IHN0LmNoYXRfaW5wdXQgcmF0aGVyIHRoYW4gYSBSZWFjdCBjaGF0IGJveCBmb3IgdGhlIHVzdWFsIHJlYXNvbiAtLSB0aGUgYnVuZGxlCiAgICBydW5zIGlu'
    || 'IGEgc2FuZGJveGVkIGlmcmFtZSB3aXRoIG5vIHNlc3Npb24gYW5kIGNhbm5vdCBjYWxsIGEgcHJvY2VkdXJlLgoKICAgIEhJU1RPUlkgSVMgUEVSIFNFU1NJ'
    || 'T04gQU5EIE5PVCBQRVJTSVNURUQuIE5vdGhpbmcgaGVyZSB3cml0ZXMgdG8gdGhlIGFjY291bnQ6CiAgICBhIHF1ZXN0aW9uIGNvc3RzIGEgc21hbGwgYW1v'
    || 'dW50IG9mIENvcnRleCBjcmVkaXQgYW5kIHJldHVybnMgYSBzdHJpbmcuIFRoYXQgaXMKICAgIGFsc28gd2h5IHRoaXMgaXMgbm90IHRpZXItZ2F0ZWQgdGhl'
    || 'IHdheSBhbiBhY3Rpb24gaXMgLS0gdGhlcmUgaXMgbm90aGluZyB0bwogICAgdW5kbyAtLSBidXQgdGhlIGNvc3QgaXMgc3RhdGVkIHJhdGhlciB0aGFuIGxl'
    || 'ZnQgYXMgYSBzdXJwcmlzZS4KICAgICIiIgogICAgYSA9IGxvYWRfYWdlbnQoc2Vzc2lvbiwgdGd0KQogICAgaWYgbm90IGE6CiAgICAgICAgcmV0dXJuCgog'
    || 'ICAgc3QuY2FwdGlvbihzdHIoYS5nZXQoIkFHRU5UX0xBQkVMIikgb3IgIkFTSyBUSEUgQUdFTlQiKS51cHBlcigpKQogICAgYmx1cmIgPSBzdHIoYS5nZXQo'
    || 'IkJMVVJCIikgb3IgIiIpCiAgICBpZiBibHVyYjoKICAgICAgICBzdC5jYXB0aW9uKGJsdXJiICsgIiBFYWNoIHF1ZXN0aW9uIGNhbGxzIGEgQ29ydGV4IG1v'
    || 'ZGVsLCBzbyBpdCBjb3N0cyBhICIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICJzbWFsbCBhbW91bnQgb2YgY3JlZGl0IGFuZCB0YWtlcyBhIGZldyBz'
    || 'ZWNvbmRzLiIpCgogICAgaGlzdF9rZXkgPSAiYWdlbnRfaGlzdCIKICAgIGlmIGhpc3Rfa2V5IG5vdCBpbiBzdC5zZXNzaW9uX3N0YXRlOgogICAgICAgIHN0'
    || 'LnNlc3Npb25fc3RhdGVbaGlzdF9rZXldID0gW10KCiAgICBmb3IgcSwgYW5zIGluIHN0LnNlc3Npb25fc3RhdGVbaGlzdF9rZXldOgogICAgICAgIHdpdGgg'
    || 'c3QuY2hhdF9tZXNzYWdlKCJ1c2VyIik6CiAgICAgICAgICAgIHN0LndyaXRlKHEpCiAgICAgICAgd2l0aCBzdC5jaGF0X21lc3NhZ2UoImFzc2lzdGFudCIp'
    || 'OgogICAgICAgICAgICBzdC53cml0ZShhbnMpCgogICAgYXNrZWQgPSBzdC5jaGF0X2lucHV0KHN0cihhLmdldCgiUExBQ0VIT0xERVIiKSBvciAiQXNrIGEg'
    || 'cXVlc3Rpb24iKSwKICAgICAgICAgICAgICAgICAgICAgICAgICBrZXk9ImFnZW50X3EiKQogICAgaWYgYXNrZWQ6CiAgICAgICAgd2l0aCBzdC5zcGlubmVy'
    || 'KCJBc2tpbmcgdGhlIGFnZW50Li4uIik6CiAgICAgICAgICAgIHRyeToKICAgICAgICAgICAgICAgICMgVGhlIHF1ZXN0aW9uIGlzIEJPVU5ELiBDb25jYXRl'
    || 'bmF0aW5nIGl0IHdvdWxkIGxldCB3aGF0ZXZlcgogICAgICAgICAgICAgICAgIyBzb21lYm9keSB0eXBlcyBlbmQgdXAgYXMgU1FMIHJ1bm5pbmcgd2l0aCB0'
    || 'aGUgYXBwIG93bmVyJ3MgcmlnaHRzLgogICAgICAgICAgICAgICAgb3V0ID0gc2Vzc2lvbi5zcWwoCiAgICAgICAgICAgICAgICAgICAgIkNBTEwgIiArIHRn'
    || 'dCArICIuIiArIGFbIlBST0NfTkFNRSJdICsgIig/KSIsCiAgICAgICAgICAgICAgICAgICAgcGFyYW1zPVthc2tlZF0pLmNvbGxlY3QoKVswXVswXQogICAg'
    || 'ICAgICAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGV4YzoKICAgICAgICAgICAgICAgICMgUmVwb3J0IHRoZSBmYWlsdXJlIGFzIHRoZSBhbnN3ZXIgcmF0aGVy'
    || 'IHRoYW4gc3dhbGxvd2luZyBpdC4gQQogICAgICAgICAgICAgICAgIyBjaGF0IHRoYXQgc2lsZW50bHkgcmV0dXJucyBub3RoaW5nIHJlYWRzIGFzICJ0aGUg'
    || 'YWdlbnQgaGFkIG5vCiAgICAgICAgICAgICAgICAjIG9waW5pb24iLCB3aGljaCBpcyBhIGNsYWltIGFib3V0IHRoZSBxdWVzdGlvbiByYXRoZXIgdGhhbiBh'
    || 'Ym91dAogICAgICAgICAgICAgICAgIyB0aGUgY2FsbCB0aGF0IGZhaWxlZC4KICAgICAgICAgICAgICAgIG91dCA9ICgiVGhlIGFnZW50IGNvdWxkIG5vdCBh'
    || 'bnN3ZXI6ICIgKyB0eXBlKGV4YykuX19uYW1lX18gKyAiOiAiCiAgICAgICAgICAgICAgICAgICAgICAgKyBzdHIoZXhjKVs6MzAwXSkKICAgICAgICBzdC5z'
    || 'ZXNzaW9uX3N0YXRlW2hpc3Rfa2V5XS5hcHBlbmQoKGFza2VkLCBzdHIob3V0KSkpCiAgICAgICAgc3QucmVydW4oKQogICAgc3QuZGl2aWRlcigpCgoKZGVm'
    || 'IGNvbnRyb2xfdmFsdWVzKHNlc3Npb24sIHRndDogc3RyKSAtPiBkaWN0OgogICAgIiIiUmVuZGVyIHRoZSBkZWNsYXJlZCBjb250cm9scyBhbmQgcmV0dXJu'
    || 'IHtuYW1lOiBjdXJyZW50IHZhbHVlfS4KCiAgICBBQk9WRSBUSEUgREFTSEJPQVJELCB1bmxpa2UgY29uZmlnX2JhciBhbmQgcHJvbW90aW9uX2JhciwgYW5k'
    || 'IHRoZSBkaWZmZXJlbmNlIGlzCiAgICB0aGUgcG9pbnQuIFRoZXNlIGNvbnRyb2xzIGRlY2lkZSBXSEFUIFRIRSBQQUdFIElTIEFCT1VUIC0tIHdoaWNoIG1l'
    || 'dHJvLCB3aGljaAogICAgd2luZG93LCB3aGljaCBtaW5pbXVtIHNjb3JlIC0tIHNvIHRoZXkgYmVsb25nIHdoZXJlIHlvdSB3b3VsZCBsb29rIGJlZm9yZQog'
    || 'ICAgcmVhZGluZy4gY29uZmlnX2JhciB0dW5lcyB0aGUgcnVsZXMgYmVoaW5kIHRoZSBudW1iZXJzIGFuZCBwcm9tb3Rpb25fYmFyIGFjdHMgb24KICAgIHRo'
    || 'ZW0sIHdoaWNoIGlzIHdoeSBib3RoIG9mIHRob3NlIHNpdCB1bmRlcm5lYXRoLgoKICAgIFdpZGdldHMsIG5vdCBSZWFjdCwgZm9yIHRoZSBzYW1lIHBoeXNp'
    || 'Y2FsIHJlYXNvbiBldmVyeXRoaW5nIGVsc2UgaGVyZSBpczogdGhlCiAgICBidW5kbGUgcnVucyBpbiBhIHNhbmRib3hlZCBpZnJhbWUgd2l0aCBubyBzZXNz'
    || 'aW9uLCBzbyBhIFJlYWN0IHNlbGVjdGJveCBjYW5ub3QKICAgIHJlLXF1ZXJ5LiBUaGlzIGlzIHdoZXJlIHRoZSBjaG9vc2luZyBoYXBwZW5zOyB0aGUgcGFn'
    || 'ZSBiZWxvdyByZS1yZW5kZXJzIGZyb20gYQogICAgcGF5bG9hZCB0aGUgaG9zdCBmZXRjaGVzIGFnYWluIG9uIHRoZSByZXN1bHRpbmcgcmVydW4uCgogICAg'
    || 'U29sdXRpb25zIHRoYXQgZGVjbGFyZSBubyBjb250cm9scyBkcmF3IE5PVEhJTkcgLS0gbm8gaGVhZGVyLCBubyBleHBhbmRlciwgbm8KICAgIGVtcHR5IHJv'
    || 'dy4gU2FtZSBhcmd1bWVudCBhcyBsb2FkX3J1bGVfY29uZmlnIGdhdGluZyBvbiBWX1JVTEVfQ09ORklHOiBhIHNvbHV0aW9uCiAgICB0aGF0IG5ldmVyIG9w'
    || 'dGVkIGluIG11c3Qgbm90IGdyb3cgYSBjb250cm9sIHN1cmZhY2UgYnkgYWNjaWRlbnQuCgogICAgQSBmYWlsZWQgb3B0aW9ucyBxdWVyeSBjb3N0cyB0aGF0'
    || 'IE9ORSBjb250cm9sIGl0cyBsaXN0IGFuZCBub3RoaW5nIGVsc2UsIGFuZCBpdAogICAgc2F5cyBzby4gRmFsbGluZyBiYWNrIHRvIGEgc2lsZW50IGVtcHR5'
    || 'IHNlbGVjdGJveCB3b3VsZCByZWFkIGFzICJ0aGVyZSBhcmUgbm8KICAgIG1ldHJvcyIsIGEgY2xhaW0gYWJvdXQgdGhlIGN1c3RvbWVyJ3MgZGF0YSByYXRo'
    || 'ZXIgdGhhbiBhYm91dCBvdXIgcXVlcnkuCiAgICAiIiIKICAgIGlmIG5vdCBDT05UUk9MUzoKICAgICAgICByZXR1cm4ge30KICAgIHBhcmFtcyA9IHt9CiAg'
    || 'ICBjb2xzID0gc3QuY29sdW1ucyhtaW4obGVuKENPTlRST0xTKSwgNCkpCiAgICBmb3IgaSwgc3BlYyBpbiBlbnVtZXJhdGUoQ09OVFJPTFMpOgogICAgICAg'
    || 'IGtleSA9IHN0cihzcGVjLmdldCgia2V5Iikgb3IgIiIpCiAgICAgICAgaWYgbm90IGtleToKICAgICAgICAgICAgY29udGludWUKICAgICAgICBsYWJlbCA9'
    || 'IHN0cihzcGVjLmdldCgibGFiZWwiKSBvciBrZXkpCiAgICAgICAga2luZCA9IHN0cihzcGVjLmdldCgia2luZCIpIG9yICJ0ZXh0IikubG93ZXIoKQogICAg'
    || 'ICAgIGRlZmF1bHQgPSBzcGVjLmdldCgiZGVmYXVsdCIpCiAgICAgICAgaGVscF90eHQgPSBzcGVjLmdldCgiaGVscCIpIG9yIE5vbmUKICAgICAgICB3a2V5'
    || 'ID0gImN0bF8iICsga2V5CiAgICAgICAgd2l0aCBjb2xzW2kgJSBsZW4oY29scyldOgogICAgICAgICAgICBpZiBraW5kID09ICJzZWxlY3QiOgogICAgICAg'
    || 'ICAgICAgICAgb3B0aW9ucyA9IHNwZWMuZ2V0KCJvcHRpb25zIikKICAgICAgICAgICAgICAgIGlmIG5vdCBvcHRpb25zIGFuZCBzcGVjLmdldCgib3B0aW9u'
    || 'c19zcWwiKToKICAgICAgICAgICAgICAgICAgICB0cnk6CiAgICAgICAgICAgICAgICAgICAgICAgIG9wdGlvbnMgPSBbCiAgICAgICAgICAgICAgICAgICAg'
    || 'ICAgICAgICByWzBdIGZvciByIGluIHNlc3Npb24uc3FsKAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHN0cihzcGVjWyJvcHRpb25zX3NxbCJd'
    || 'KS5yZXBsYWNlKCJ7dGd0fSIsIHRndCkKICAgICAgICAgICAgICAgICAgICAgICAgICAgICkubGltaXQoMTAwMCkuY29sbGVjdCgpXQogICAgICAgICAgICAg'
    || 'ICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZXhjOgogICAgICAgICAgICAgICAgICAgICAgICBzdC5jYXB0aW9uKGxhYmVsICsgIiBcdTAwYjcgY291bGQg'
    || 'bm90IGxvYWQgY2hvaWNlczogIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICsgdHlwZShleGMpLl9fbmFtZV9fKQogICAgICAgICAgICAg'
    || 'ICAgICAgICAgICBvcHRpb25zID0gW10KICAgICAgICAgICAgICAgIG9wdGlvbnMgPSBbbyBmb3IgbyBpbiAob3B0aW9ucyBvciBbXSkgaWYgbyBpcyBub3Qg'
    || 'Tm9uZV0KICAgICAgICAgICAgICAgIGlmIG5vdCBvcHRpb25zOgogICAgICAgICAgICAgICAgICAgICMgTm90aGluZyB0byBjaG9vc2UgZnJvbSBpcyBub3Qg'
    || 'dGhlIHNhbWUgYXMgYW4gZW1wdHkgY2hvaWNlLgogICAgICAgICAgICAgICAgICAgICMgQmluZCB0aGUgZGVmYXVsdCBzbyB0aGUgcGFuZWwgc3RpbGwgcnVu'
    || 'cyBhbmQgc3RpbGwgc2F5cyB3aGF0CiAgICAgICAgICAgICAgICAgICAgIyBpdCByYW4gd2l0aC4KICAgICAgICAgICAgICAgICAgICBwYXJhbXNba2V5XSA9'
    || 'IGRlZmF1bHQKICAgICAgICAgICAgICAgICAgICBzdC5jYXB0aW9uKGxhYmVsICsgIiBcdTAwYjcgbm8gY2hvaWNlcyBhdmFpbGFibGUiKQogICAgICAgICAg'
    || 'ICAgICAgICAgIGNvbnRpbnVlCiAgICAgICAgICAgICAgICBpZHggPSBvcHRpb25zLmluZGV4KGRlZmF1bHQpIGlmIGRlZmF1bHQgaW4gb3B0aW9ucyBlbHNl'
    || 'IDAKICAgICAgICAgICAgICAgIHBhcmFtc1trZXldID0gc3Quc2VsZWN0Ym94KGxhYmVsLCBvcHRpb25zLCBpbmRleD1pZHgsIGtleT13a2V5LAogICAgICAg'
    || 'ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgaGVscD1oZWxwX3R4dCkKICAgICAgICAgICAgZWxpZiBraW5kID09ICJzbGlkZXIiOgogICAg'
    || 'ICAgICAgICAgICAgbG8gPSBzcGVjLmdldCgibWluIiwgMCkKICAgICAgICAgICAgICAgIGhpID0gc3BlYy5nZXQoIm1heCIsIDEwMCkKICAgICAgICAgICAg'
    || 'ICAgIHBhcmFtc1trZXldID0gc3Quc2xpZGVyKAogICAgICAgICAgICAgICAgICAgIGxhYmVsLCBtaW5fdmFsdWU9bG8sIG1heF92YWx1ZT1oaSwKICAgICAg'
    || 'ICAgICAgICAgICAgICB2YWx1ZT1kZWZhdWx0IGlmIGRlZmF1bHQgaXMgbm90IE5vbmUgZWxzZSBsbywKICAgICAgICAgICAgICAgICAgICBzdGVwPXNwZWMu'
    || 'Z2V0KCJzdGVwIiwgMSksIGtleT13a2V5LCBoZWxwPWhlbHBfdHh0KQogICAgICAgICAgICBlbGlmIGtpbmQgPT0gIm51bWJlciI6CiAgICAgICAgICAgICAg'
    || 'ICBwYXJhbXNba2V5XSA9IHN0Lm51bWJlcl9pbnB1dCgKICAgICAgICAgICAgICAgICAgICBsYWJlbCwgdmFsdWU9ZGVmYXVsdCBpZiBkZWZhdWx0IGlzIG5v'
    || 'dCBOb25lIGVsc2UgMCwKICAgICAgICAgICAgICAgICAgICBtaW5fdmFsdWU9c3BlYy5nZXQoIm1pbiIpLCBtYXhfdmFsdWU9c3BlYy5nZXQoIm1heCIpLAog'
    || 'ICAgICAgICAgICAgICAgICAgIHN0ZXA9c3BlYy5nZXQoInN0ZXAiLCAxKSwga2V5PXdrZXksIGhlbHA9aGVscF90eHQpCiAgICAgICAgICAgIGVsc2U6CiAg'
    || 'ICAgICAgICAgICAgICBwYXJhbXNba2V5XSA9IHN0LnRleHRfaW5wdXQoCiAgICAgICAgICAgICAgICAgICAgbGFiZWwsIHZhbHVlPSIiIGlmIGRlZmF1bHQg'
    || 'aXMgTm9uZSBlbHNlIHN0cihkZWZhdWx0KSwKICAgICAgICAgICAgICAgICAgICBrZXk9d2tleSwgaGVscD1oZWxwX3R4dCkKICAgIHJldHVybiBwYXJhbXMK'
    || 'CgpkZWYgbWFpbigpIC0+IE5vbmU6CiAgICB0cnk6CiAgICAgICAgc2Vzc2lvbiA9IGdldF9hY3RpdmVfc2Vzc2lvbigpCiAgICBleGNlcHQgRXhjZXB0aW9u'
    || 'IGFzIGV4YzoKICAgICAgICAjIE5vIHNlc3Npb24gbWVhbnMgdGhlIGFwcCBjYW5ub3QgcXVlcnkgYW55dGhpbmcuIFNheSB0aGF0IHBsYWlubHkKICAgICAg'
    || 'ICAjIGluc3RlYWQgb2YgcmVuZGVyaW5nIGVtcHR5IHBhbmVscyB0aGF0IGxvb2sgbGlrZSByZWFsIHplcm9lcy4KICAgICAgICBjb21wb25lbnRzLmh0bWwo'
    || 'YnVpbGRfaHRtbCh7ImNvbnRleHQiOiB7fSwgInBhbmVscyI6IHt9LAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAiZmF0YWwiOiAiTm8g'
    || 'YWN0aXZlIFNub3dmbGFrZSBzZXNzaW9uOiAiICsgc3RyKGV4Yyl9KSwKICAgICAgICAgICAgICAgICAgICAgICAgaGVpZ2h0PTQwMCwgc2Nyb2xsaW5nPUZh'
    || 'bHNlKQogICAgICAgIHJldHVybgoKICAgIHRndCA9IHRhcmdldF9zY2hlbWEoc2Vzc2lvbikKICAgIG5hdmlnYXRpb24gPSBhcHBfbmF2aWdhdGlvbihzZXNz'
    || 'aW9uLCB0Z3QpCiAgICAjIEJFRk9SRSBydW5fcGFuZWxzLCBiZWNhdXNlIHRoZWlyIHZhbHVlcyBhcmUgd2hhdCB0aGUgcGFuZWxzIGFyZSBmaWx0ZXJlZCBi'
    || 'eS4KICAgIHBhcmFtcyA9IGNvbnRyb2xfdmFsdWVzKHNlc3Npb24sIHRndCkKICAgIHBhbmVscyA9IHJ1bl9wYW5lbHMoc2Vzc2lvbiwgdGd0LCBwYXJhbXMp'
    || 'CiAgICBjdXN0b21pemF0aW9uLCBjdXN0b21fcGFuZWxzLCBjdXN0b21pemF0aW9uX2Vycm9yID0gbG9hZF9jdXN0b21pemF0aW9uKHNlc3Npb24sIHRndCkK'
    || 'ICAgIHBhbmVscy51cGRhdGUoY3VzdG9tX3BhbmVscykKICAgICMgVGhlIHNoZWxsJ3MgTU9ERSBiYW5uZXIgYW5kIGJ1aWxkIHByb3ZlbmFuY2UgY29tZSBm'
    || 'cm9tIHRoZSBgY29udGV4dGAgcGFuZWwuCiAgICAjIElmIGl0IGZhaWxlZCwgc2F5IHNvIHRocm91Z2ggdGhlIG5vcm1hbCBjb250ZXh0IGZpZWxkcyByYXRo'
    || 'ZXIgdGhhbiBsZWF2aW5nCiAgICAjIE1PREUgYmxhbmsgLS0gYSBwYWdlIHdpdGggbm8gbW9kZSBiYWRnZSBpcyBhIHBhZ2UgdGhhdCBjb3VsZCBiZSBzaG93'
    || 'aW5nCiAgICAjIHNlZWRlZCBudW1iZXJzIHdpdGggbm90aGluZyB0byBzYXkgc28uCiAgICBjdHggPSB7fQogICAgZ290ID0gcGFuZWxzLmdldCgiY29udGV4'
    || 'dCIsIHt9KQogICAgaWYgInJvd3MiIGluIGdvdCBhbmQgZ290WyJyb3dzIl06CiAgICAgICAgY3R4ID0gZ290WyJyb3dzIl1bMF0KICAgIGVsc2U6CiAgICAg'
    || 'ICAgY3R4ID0geyJTT0xVVElPTiI6IFNPTFVUSU9OX05BTUUsICJCVUlMVF9JTiI6IHRndCwgIk1PREUiOiAiVU5LTk9XTiJ9CgogICAgY29tcG9uZW50cy5o'
    || 'dG1sKGJ1aWxkX2h0bWwoeyJjb250ZXh0IjogY3R4LCAicGFuZWxzIjogcGFuZWxzLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJjdXN0b21p'
    || 'emF0aW9uIjogY3VzdG9taXphdGlvbiwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAiY3VzdG9taXphdGlvbl9lcnJvciI6IGN1c3RvbWl6YXRp'
    || 'b25fZXJyb3IsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIm5hdmlnYXRpb24iOiBuYXZpZ2F0aW9ufSksCiAgICAgICAgICAgICAgICAgICAg'
    || 'aGVpZ2h0PTE1MDAsIHNjcm9sbGluZz1UcnVlKQoKICAgIGlmIHN0LmJ1dHRvbigiUmVmcmVzaCBkYXRhIiwga2V5PSJyZWZyZXNoX3BhbmVsX2RhdGEiKToK'
    || 'ICAgICAgICBpbnZhbGlkYXRlX3BhbmVsX2NhY2hlKCkKICAgICAgICBpZiBoYXNhdHRyKHN0LCAicmVydW4iKToKICAgICAgICAgICAgc3QucmVydW4oKQog'
    || 'ICAgICAgIGVsc2U6CiAgICAgICAgICAgIHN0LmV4cGVyaW1lbnRhbF9yZXJ1bigpCgogICAgIyBBRlRFUiB0aGUgZGFzaGJvYXJkIGFuZCBCRUZPUkUgdGhl'
    || 'IHByb21vdGlvbiBiYXIuIFRoZSBvcmRlciBpcyBhbiBhcmd1bWVudDoKICAgICMgdGhlIHJ1bGVzIGV4cGxhaW4gdGhlIG51bWJlcnMgaW1tZWRpYXRlbHkg'
    || 'YWJvdmUgdGhlbSwgYW5kIHRoZSBwcm9tb3Rpb24gYmFyCiAgICAjIGlzIHRoZSAid2hhdCBkbyBJIGRvIGFib3V0IHRoaXMiIHRoYXQgc2hvdWxkIGNvbWUg'
    || 'bGFzdC4gQSByZWFkZXIgd2hvIGNoYW5nZXMKICAgICMgYSB0aHJlc2hvbGQgaGVyZSBpcyBzdGlsbCByZWFkaW5nIHRoZSBkYXNoYm9hcmQ7IGEgcmVhZGVy'
    || 'IGF0IHRoZSBwcm9tb3Rpb24KICAgICMgYmFyIGhhcyBmaW5pc2hlZC4gU29sdXRpb25zIHdpdGhvdXQgVl9SVUxFX0NPTkZJRyBkcmF3IG5vdGhpbmcgYXQg'
    || 'YWxsLgogICAgY29uZmlnX2JhcihzZXNzaW9uLCB0Z3QpCgogICAgIyBCRVRXRUVOIHRoZSBydWxlcyBhbmQgdGhlIGFjdGlvbnMuIFRoZSBhZ2VudCBleHBs'
    || 'YWlucyB3aGF0IHRoZSBudW1iZXJzIG1lYW4KICAgICMgYW5kIGlzIG1vc3QgdXNlZnVsIGltbWVkaWF0ZWx5IGJlZm9yZSB0aGUgZGVjaXNpb24gaXQgaW5m'
    || 'b3Jtczsgc29sdXRpb25zIHRoYXQKICAgICMgZGVjbGFyZSBubyBWX0FHRU5UX0NIQVQgZHJhdyBub3RoaW5nIGF0IGFsbC4KICAgIGFnZW50X2JhcihzZXNz'
    || 'aW9uLCB0Z3QpCgogICAgIyBBRlRFUiB0aGUgZGFzaGJvYXJkLCBub3QgYmVmb3JlLiBUaGUgcHJvbW90aW9uIGJhciBpcyB0aGUgYW5zd2VyIHRvICJ3aGF0'
    || 'IGRvCiAgICAjIEkgZG8gYWJvdXQgdGhpcz8iLCBhbmQgdGhhdCBxdWVzdGlvbiBvbmx5IG1ha2VzIHNlbnNlIG9uY2UgdGhlIG51bWJlcnMgYWJvdmUKICAg'
    || 'ICMgaXQgaGF2ZSBiZWVuIHJlYWQuIFB1dHRpbmcgaXQgb24gdG9wIHdvdWxkIGFsc28gcHVzaCB0aGUgd2hvbGUgZGFzaGJvYXJkCiAgICAjIGJlbG93IHRo'
    || 'ZSBmb2xkIG9uIGEgbGFwdG9wLgogICAgcHJvbW90aW9uX2JhcihzZXNzaW9uLCB0Z3QpCgoKbWFpbigpCg==';

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
    'CREATE OR REPLACE STREAMLIT ' || :tgt || '.DELEGATED_ORCHESTRATION_APP '
 || 'ROOT_LOCATION = ''@' || :tgt || '.APP_STAGE'' MAIN_FILE = ''streamlit_app.py'' '
 || 'QUERY_WAREHOUSE = ' || :wh || ' COMMENT = ''Zero-Privilege Orchestration — generated from account discovery''');

  -- The app runs on the app warehouse whenever someone opens it. Auto-suspend
  -- makes this small, but it is not zero and the operator should see it.
  cost_day    := :cost_day + 0.10;
  cost_detail := ARRAY_APPEND(:cost_detail,
    'Streamlit app on ' || :wh || ' ~0.10 credits/day. ASSUMES an XS warehouse, '
 || 'auto-suspend 60s, and roughly 20 page views/day. Heavier use scales this linearly.');
  dials       := ARRAY_APPEND(:dials,
    'Point DELEG_APP_WAREHOUSE at an XS warehouse to cut app cost');
  -- Only claim the app exists when this snippet is present. The template used to
  -- print "OPEN THE APP" unconditionally, which told operators to open a
  -- Streamlit object that was never created for solutions built without a UI.
  -- Two independent reviewers caught it; it now lives with the code that
  -- actually creates the app.
  notes       := ARRAY_APPEND(:notes,
    'OPEN THE APP after building: Snowsight > Projects > Streamlit > DELEGATED_ORCHESTRATION_APP');
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
                 || 'deterministic refusal from ' || 'DELEG' || '_MIN_FILL_PCT = ' || :min_fill
                 || ', not a judgement call, and it stands whether or not the model '
                 || 'review runs.';
    ELSEIF (:n_dead > 0) THEN
      notes := ARRAY_APPEND(:notes,
        'PROFILE: ' || :n_dead || ' column(s) are entirely empty or sit on an empty '
     || 'table, and ' || ARRAY_SIZE(:unusable) || ' in total fell below the '
     || :min_fill || '% floor. Anything depending on them is downgraded and named '
     || 'below. The plan continues on what is left.');
    END IF;
  ELSEIF (:prof_status NOT IN ('SYNTHETIC_INPUTS','BOUNDED_VALIDATED')) THEN
    notes := ARRAY_APPEND(:notes,
      'PROFILE ' || :prof_status || ': column populated-ness was NOT checked, so '
   || 'nothing in this plan knows whether the columns it reads contain anything. '
   || 'This is the failure mode that produces a clean-looking dashboard over blank '
   || 'columns. Set DELEG_PROFILE = TRUE and re-run to close it.');
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
    override_asked := (SELECT TRY_CAST($DELEG_OVERRIDE_REVIEW::VARCHAR AS BOOLEAN));
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
    || 'SOLUTION: Zero-Privilege Orchestration' || CHR(10)
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
        || 'DELEG_APPROVE is TRUE. To build anyway set DELEG_OVERRIDE_REVIEW = TRUE; '
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
             || 'DELEG_BUDGET_CREDITS = ' || :budget || '. Nothing was created.' AS statement
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
    approved := (SELECT TRY_CAST($DELEG_APPROVE::VARCHAR AS BOOLEAN));
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
   || 'DELEG_OVERRIDE_REVIEW = TRUE, so the build proceeded anyway. The verdict and '
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
       '# ' || 'Zero-Privilege Orchestration' || ' — discovery packet' || CHR(10) || CHR(10)
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
      'solution', 'Zero-Privilege Orchestration', 'run_id', :run_id, 'tier', :tier,
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
    IF (NOT $DELEG_VERBOSE_OUTPUT::BOOLEAN) THEN
      res := (SELECT IFF(:hard_block <> '' OR (:review_verdict = 'DO_NOT_PROCEED' AND NOT :override_asked), 'BLOCKED', 'READY_TO_BUILD') AS STATUS,
        NULL::VARCHAR AS OPEN_APP_URL,
        :mode AS DATA_MODE,
        :tgt AS DESTINATION,
        :cost_once AS ESTIMATED_BUILD_CREDITS,
        :cost_day AS ESTIMATED_DAILY_CREDITS,
        IFF(:hard_block <> '', :hard_block, IFF(:review_verdict = 'DO_NOT_PROCEED' AND NOT :override_asked, TO_JSON(:review_findings), 'Review the cost and discovery packet, then set DELEG_APPROVE = TRUE and rerun. Set DELEG_VERBOSE_OUTPUT = TRUE for the full plan.')) AS NEXT_ACTION,
        :review_verdict AS REVIEW_STATUS,
        :review_findings AS REVIEW_FINDINGS,
        :pk_json AS DISCOVERY_PACKET);
      RETURN TABLE(res);
    END IF;
    res := (
      SELECT -1 AS step, 'WHAT THIS GIVES YOU' AS action,
             COALESCE(NULLIF(:headline, ''), 'Zero-Privilege Orchestration') AS statement
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
                 'no ceiling set (DELEG_BUDGET_CREDITS = 0)')
      UNION ALL SELECT 5, 'REVIEW',
             :review_verdict || ' (' || :review_status || ') · '
             || ARRAY_SIZE(:review_findings) || ' finding(s)'
      UNION ALL SELECT 6, 'WHY THE GATE IS CLOSED',
             CASE WHEN :gate_closed_by = 'DETERMINISTIC CHECK' THEN :hard_block
                  WHEN :gate_closed_by = 'REVIEW VERDICT'
                    THEN 'The review returned DO_NOT_PROCEED. Read the findings above. '
                      || 'To build anyway set DELEG_OVERRIDE_REVIEW = TRUE.'
                  ELSE 'DELEG_APPROVE is FALSE. Nothing was created.' END
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
   || 'LET r_rgrant RESULTSET := (SELECT TARGET_FQN, ARTIFACT, ARGUMENTS FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ''ROLE_GRANT''); FOR rg_rec IN r_rgrant DO BEGIN EXECUTE IMMEDIATE ''REVOKE '' || rg_rec.ARGUMENTS || '' ON '' || rg_rec.TARGET_FQN || '' FROM ROLE '' || rg_rec.ARTIFACT; detached := :detached + 1; EXCEPTION WHEN OTHER THEN failed := :failed + 1; failed_items := ARRAY_APPEND(:failed_items, rg_rec.TARGET_FQN || '' / '' || COALESCE(rg_rec.ARGUMENTS, '''') || '': '' || SQLERRM); END; END FOR; DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ''ROLE_GRANT''; LET r_role RESULTSET := (SELECT TARGET_FQN FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ''ROLE''); FOR role_rec IN r_role DO BEGIN EXECUTE IMMEDIATE ''DROP ROLE IF EXISTS '' || role_rec.TARGET_FQN; detached := :detached + 1; EXCEPTION WHEN OTHER THEN failed := :failed + 1; failed_items := ARRAY_APPEND(:failed_items, role_rec.TARGET_FQN || '': '' || SQLERRM); END; END FOR; DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ''ROLE'';'
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

  LET receipt_failures ARRAY := (SELECT COALESCE(ARRAY_AGG(OBJECT_CONSTRUCT('statement', VALUE:stmt, 'error', VALUE:error)), ARRAY_CONSTRUCT()) FROM TABLE(FLATTEN(INPUT => :log)) WHERE VALUE:status::STRING = 'FAILED');
  LET receipt_app_name STRING := 'DELEGATED_ORCHESTRATION_APP';
  LET receipt_app_exists BOOLEAN := FALSE;
  LET receipt_workspace_exists BOOLEAN := FALSE;
  LET receipt_base_url STRING := 'https://app.snowflake.com/' || LOWER(CURRENT_ORGANIZATION_NAME()) || '/' || LOWER(CURRENT_ACCOUNT_NAME());
  IF (ARRAY_SIZE(:receipt_failures) = 0 AND :receipt_app_name <> '') THEN
    BEGIN
      EXECUTE IMMEDIATE 'SHOW STREAMLITS IN SCHEMA ' || :tgt;
      receipt_app_exists := (SELECT COUNT(*) = 1 FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "name" = :receipt_app_name);
      IF (NOT :receipt_app_exists) THEN
        receipt_failures := ARRAY_APPEND(:receipt_failures, OBJECT_CONSTRUCT('statement', 'Verify deployed app', 'error', 'Expected Streamlit app was not found.'));
      END IF;
    EXCEPTION WHEN OTHER THEN
      receipt_failures := ARRAY_APPEND(:receipt_failures, OBJECT_CONSTRUCT('statement', 'Verify deployed app', 'error', SQLERRM));
    END;
    IF (:receipt_app_exists) THEN
      BEGIN
        EXECUTE IMMEDIATE 'SHOW WORKSPACES IN SCHEMA ' || :tgt;
        receipt_workspace_exists := (SELECT COUNT(*) = 1 FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "name" = 'ONESHOT_SOURCE' AND "comment" = 'oneshot-source:28_delegated_orchestration');
      EXCEPTION WHEN OTHER THEN
        receipt_workspace_exists := FALSE;
      END;
    END IF;
  END IF;
  IF (NOT $DELEG_VERBOSE_OUTPUT::BOOLEAN) THEN
    res := (SELECT
      CASE WHEN ARRAY_SIZE(:receipt_failures) > 0 THEN 'BUILD_FAILED' WHEN :receipt_app_name = '' THEN 'READY_NO_APP' ELSE 'READY' END AS STATUS,
      IFF(:receipt_app_exists AND ARRAY_SIZE(:receipt_failures) = 0, :receipt_base_url || '/#/streamlit-apps/' || :tgt || '.' || :receipt_app_name, NULL) AS OPEN_APP_URL,
      IFF(:receipt_workspace_exists AND ARRAY_SIZE(:receipt_failures) = 0, :receipt_base_url || '/#/workspaces/ws/' || :db || '/' || :sch || '/ONESHOT_SOURCE/streamlit_app.py', NULL) AS EDIT_SOURCE_URL,
      :mode AS DATA_MODE,
      :tgt AS DESTINATION,
      :review_verdict AS REVIEW_STATUS,
      :review_findings AS REVIEW_FINDINGS,
      IFF(ARRAY_SIZE(:receipt_failures) > 0, TO_JSON(:receipt_failures), IFF(:receipt_app_name = '', 'This solution creates SQL objects, not a Streamlit app.', 'Open OPEN_APP_URL using a role with access to the app.')) AS NEXT_ACTION,
      'SELECT * FROM ' || :tgt || '.BUILD_STATEMENT_LOG WHERE RUN_ID = ''' || :run_id || ''' ORDER BY SEQ;' AS DIAGNOSTICS,
      'CALL ' || :tgt || '.TEARDOWN();' AS REMOVE_DEMO);
    RETURN TABLE(res);
  END IF;

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
