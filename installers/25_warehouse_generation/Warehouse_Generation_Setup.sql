-- ─────────────────────────────────────────────────────────────────────────────
-- Warehouse Generation — Gen2 and Adaptive
-- SETTINGS  ·  the only part of this file intended to be edited
-- ─────────────────────────────────────────────────────────────────────────────

-- The gate. Nothing is created while this is FALSE.
SET WHGEN_APPROVE = FALSE;

SET WHGEN_VERBOSE_OUTPUT = FALSE;


-- Where to build. Blank means the database currently in use.
SET WHGEN_TARGET_DB = '';
SET WHGEN_SCHEMA    = 'WAREHOUSE_GENERATION';

-- Blank means the warehouse currently in use.
SET WHGEN_APP_WAREHOUSE = '';

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
SET WHGEN_KEEP_APP_WARM  = FALSE;
SET WHGEN_WARM_WAREHOUSE = 'ONESHOT_APP_WH';

-- How long a viewer's own app session survives idling, in minutes, 5 to 240.
-- Higher means someone returning to the tab reconnects to a live session instead
-- of waiting for a new one to start.
--
-- CAVEAT WORTH KNOWING: the account-level WebSocket timeout, about 15 minutes by
-- default, can close the connection before this timer expires, and only Snowflake
-- Support can raise it. Setting 240 here is therefore an upper bound and not a
-- guarantee.
SET WHGEN_APP_SLEEP_MINUTES = 240;

-- How far back discovery and the views look.
SET WHGEN_WINDOW_DAYS = 14;

-- DISCOVER reads your account and reports what it found.
-- SAMPLE seeds representative data instead, and the app says so on every page.
-- Never demo SAMPLE numbers as if they were the customer's.
SET WHGEN_MODE = 'DISCOVER';

-- Credit ceiling for steady-state cost. 0 means no ceiling. When the plan's own
-- estimate exceeds this, Block 3 refuses to plan and tells you what to turn down.
SET WHGEN_BUDGET_CREDITS = 0;

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
SET WHGEN_DEPLOY_TIER = 'DISCOVER';

-- Names this run in QUERY_TAG so its statements can be found in history later.
-- Blank generates one. Set it yourself only if you are correlating with your own
-- observability.
SET WHGEN_RUN_ID = '';

-- Warehouse the LIMITED and PRODUCTION tiers create for their own work. Blank
-- derives a name from the schema. It is XSMALL with a 60-second auto-suspend and
-- it is dropped by TEARDOWN.
SET WHGEN_MEASURE_WAREHOUSE = '';

-- Credit quota for the resource monitor on that warehouse. This is a REAL
-- ceiling: the warehouse suspends when it is reached.
--
-- Read what it does NOT cover before you rely on it. A resource monitor governs
-- WAREHOUSES only. It cannot cap serverless features or AI-services tokens --
-- Snowflake's own documentation says to use a BUDGET for those. So on a solution
-- that spends most of its credits on AI, this number is not the ceiling you think
-- it is, and Block 0 prints exactly which categories it does and does not cover.
SET WHGEN_CREDIT_CAP = 5;

-- Dollars per credit, for the readable version of every credit figure. Your rate
-- is on your contract; the default is a list-price placeholder, not your price.
SET WHGEN_COST_PER_CREDIT = 3;

-- Ratio of output tokens to input tokens, used only to ESTIMATE AI spend before
-- it happens. AI_COUNT_TOKENS counts input tokens and cannot see output tokens,
-- so without this the estimate is systematically low. After a run the real split
-- is measured and the estimate is graded against it.
SET WHGEN_OUTPUT_TOKEN_RATIO = 0.5;

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
SET WHGEN_PROFILE = FALSE;

-- A column must be at least this percent non-null to be used. Below it, the plan
-- downgrades or refuses the thing that depended on it, and prints why.
SET WHGEN_MIN_FILL_PCT = 60;

-- Internal. Do not edit. Block 2 publishes its statistics here in chunks.
SET WHGEN_PROFILE_N = 0;

-- ─────────────────────────────────────────────────────────────────────────────
-- REVIEW
-- ─────────────────────────────────────────────────────────────────────────────

-- Block 3 asks the model to review the finished plan against what discovery and
-- the profile actually found, and returns PROCEED, CAVEAT or DO_NOT_PROCEED.
--
-- DO_NOT_PROCEED closes the gate even when WHGEN_APPROVE is TRUE. Setting this to
-- TRUE overrides that. It is your call to make and the override is recorded in the
-- output, in the packet and in REVIEW_LOG, because "we were told not to and did it
-- anyway" is a thing your own audit should be able to see.
SET WHGEN_OVERRIDE_REVIEW = FALSE;

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
SET WHGEN_NOTIFICATION_INTEGRATION = '';


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
SET WHGEN_ALLOW_ACTIONS = FALSE;

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
SET WHGEN_ALLOW_SAMPLE_ACTIONS = TRUE;

-- Model used to read your discovery results and adapt the plan. Deliberately the
-- strongest available rather than the cheapest: this call decides which of your
-- objects get used and how, and a weaker model gets those judgements wrong in
-- ways that are hard to spot. It runs ONCE per plan, so the cost is negligible.
-- Verified available in this account: claude-opus-5, claude-opus-4-6,
-- openai-gpt-5.2, openai-gpt-5, claude-4-sonnet, mistral-large2.
SET WHGEN_MODEL = 'claude-opus-5';

-- Internal. Do not edit. Block 1 publishes its findings here in chunks, because
-- one session variable caps at 16,384 bytes.
SET WHGEN_SIGNALS_N = 0;

-- ── Gen2 rate premium ────────────────────────────────────────────────────────
-- Gen2 bills at a HIGHER per-second rate than Gen1 for the same warehouse size.
-- 0 means "infer it from the account's own region": AWS and GCP are 1.35x, Azure
-- is 1.25x. Those figures are published in the Snowflake Service Consumption
-- Table rather than in the SQL reference, so they cannot be read out of the
-- account -- which is exactly why this is a setting you can correct.
--
-- Set it to your own contracted figure if it differs. Every verdict, every
-- break-even bar and every worst-case number in this solution is computed from
-- this one value, so overriding it re-derives the whole analysis.
SET WHGEN_RATE_MULTIPLIER = 0;

-- ── Scope for warehouse changes ──────────────────────────────────────────────
-- Comma-separated warehouse names this BUILD may ALTER. BLANK MEANS NOTHING IS
-- ALTERED: discovery still runs, the fleet is still snapshotted, and every
-- verdict is still produced -- no warehouse is touched.
--
-- The buttons in the app are the intended way to act on this. This setting
-- exists so the same change can be driven from the script itself, and so the
-- test harness can exercise the ALTER path rather than reporting green on a
-- code path it never ran.
SET WHGEN_WAREHOUSES = '';

-- ── Scope for Query Acceleration changes ─────────────────────────────────────
-- Comma-separated warehouse names this BUILD may switch Query Acceleration on
-- for, at scale factor 2. BLANK MEANS NOTHING IS CHANGED, which is the shipped
-- default.
--
-- Separate from WHGEN_WAREHOUSES on purpose. Converting a warehouse to Gen2 and
-- enabling QAS on it are two different cost decisions -- Gen2 changes the rate the
-- warehouse bills at, QAS adds a second, separately-billed serverless line -- and
-- one setting that did both would make it impossible to consent to one without
-- the other.
--
-- It also exists because QAS_VERDICT can only reach RECOMMENDED when Snowflake has
-- actually marked queries eligible, which never happens in a fresh sandbox. So
-- without this list the QAS ALTER path is one no test can reach, which is the same
-- way the equivalent path in 11_cost_efficiency stayed unexercised while every
-- check reported green.
SET WHGEN_QAS_WAREHOUSES = '';

-- ── Noise floor ──────────────────────────────────────────────────────────────
-- Warehouses below this many credits over the discovery window are reported but
-- never recommended. Converting a warehouse that spent 0.4 credits in two weeks
-- cannot save or cost anything material, and a verdict list padded with them
-- buries the warehouses that matter.
SET WHGEN_MIN_CREDITS = 5;


-- ─────────────────────────────────────────────────────────────────────────────
-- BLOCK 0 · PRE-FLIGHT
-- Answers only the questions that decide whether the rest can run.
-- Creates nothing. Reads no business data.
-- ─────────────────────────────────────────────────────────────────────────────
EXECUTE IMMEDIATE $$
DECLARE
  res RESULTSET;
BEGIN
  LET db   STRING := COALESCE(NULLIF($WHGEN_TARGET_DB::VARCHAR, ''), CURRENT_DATABASE());
  LET wh   STRING := COALESCE(NULLIF($WHGEN_APP_WAREHOUSE::VARCHAR, ''), CURRENT_WAREHOUSE());
  LET sch  STRING := $WHGEN_SCHEMA::VARCHAR;
  LET mode STRING := UPPER(COALESCE($WHGEN_MODE::VARCHAR, 'DISCOVER'));
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
      COALESCE(NULLIF($WHGEN_MODEL::VARCHAR, ''), 'claude-opus-5'), 'Reply with OK.'));
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
  LET tier      STRING := UPPER(COALESCE(NULLIF($WHGEN_DEPLOY_TIER::VARCHAR, ''), 'DISCOVER'));
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
  LET ni       STRING := COALESCE(NULLIF($WHGEN_NOTIFICATION_INTEGRATION::VARCHAR, ''), '');
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
    profile_on := (SELECT TRY_CAST($WHGEN_PROFILE::VARCHAR AS BOOLEAN));
  EXCEPTION WHEN OTHER THEN profile_on := FALSE;
  END;
  LET cap NUMBER(38,2) := COALESCE((SELECT TRY_CAST($WHGEN_CREDIT_CAP::VARCHAR AS NUMBER)), 0);


  LET approved BOOLEAN := FALSE;
  BEGIN
    approved := (SELECT TRY_CAST($WHGEN_APPROVE::VARCHAR AS BOOLEAN));
  EXCEPTION WHEN OTHER THEN approved := FALSE;
  END;


  res := (
    SELECT 1 AS step, 'TARGET DATABASE' AS check_name,
           COALESCE(:db, 'NONE SELECTED') AS finding,
           IFF(:db IS NULL, 'Run USE DATABASE, or set WHGEN_TARGET_DB.',
               IFF(:db_ok, '', 'Grant CREATE SCHEMA on this database, or point at one you own.')) AS fix
    UNION ALL SELECT 2, 'CREATE SCHEMA', IFF(:db_ok, 'AUTHORIZED', 'NOT AUTHORIZED'),
           IFF(:db_ok, '', 'GRANT CREATE SCHEMA ON DATABASE ' || COALESCE(:db, '<db>') || ' TO ROLE ' || CURRENT_ROLE())
    UNION ALL SELECT 3, 'WAREHOUSE', COALESCE(:wh, 'NONE SELECTED'),
           IFF(:wh IS NULL, 'Run USE WAREHOUSE, or set WHGEN_APP_WAREHOUSE.', '')
    UNION ALL SELECT 4, 'ACCOUNT_USAGE', IFF(:au_ok, 'READABLE', 'NOT READABLE'),
           IFF(:au_ok, '', 'GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE ' || CURRENT_ROLE())
    UNION ALL SELECT 5, 'CORTEX (' || COALESCE(NULLIF($WHGEN_MODEL::VARCHAR, ''), 'claude-opus-5')
           || ')', IFF(:cortex_ok, 'AVAILABLE', 'NOT AVAILABLE'),
           IFF(:cortex_ok, '', 'GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE ' || CURRENT_ROLE()
               || ' — without it the agent is skipped and the dashboard still builds.')
    UNION ALL SELECT 6, 'EXISTING SCHEMA', IFF(:existing > 0, :db || '.' || :sch || ' ALREADY EXISTS', 'not present'),
           IFF(:existing > 0, 'A previous build is there. Re-running updates it in place; CALL ' || :db || '.' || :sch || '.TEARDOWN() removes it.', '')
    UNION ALL SELECT 7, 'MODE', :mode,
           IFF(:mode = 'SAMPLE', 'Seeded data. The app will label every page SAMPLE DATA. Do not present these numbers as the customer''s.', 'Reads this account.')
    UNION ALL SELECT 8, 'GATE', IFF(:approved, 'OPEN — Block 3 will build', 'CLOSED — nothing will be created'),
           IFF(:approved, 'Review the plan below before you let this run.', 'To build: set WHGEN_APPROVE = TRUE and run the file again.')
    UNION ALL SELECT 9, 'DEPLOY TIER', :tier,
           CASE :tier
             WHEN 'DISCOVER' THEN 'Costs below are ARITHMETIC ESTIMATES. Nothing is measured at this tier. Set WHGEN_DEPLOY_TIER = ''LIMITED'' to get a real number.'
             WHEN 'LIMITED' THEN 'Builds on its own capped warehouse so credits can be measured and attributed to this run.'
             WHEN 'PRODUCTION' THEN 'Full scope plus monitor, budget, tags, error notification and an operations view.'
             ELSE 'Unrecognised tier — treated as DISCOVER. Use DISCOVER, LIMITED or PRODUCTION.'
           END
    UNION ALL SELECT 10, 'PROFILE', IFF(:profile_on, 'ON — will sample the columns the plan uses',
                                        'OFF — column populated-ness will NOT be checked'),
           IFF(:profile_on,
               'Reads a sample of named columns only. Emits aggregates: null rate, distinct count, row count, type, and min/max for DATE columns only.',
               'This is the gap that lets a plan build on a column that exists and is empty. Set WHGEN_PROFILE = TRUE to close it. The review will return CAVEAT rather than PROCEED while it is off.')
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
  LET w    INT    := COALESCE((SELECT TRY_CAST($WHGEN_WINDOW_DAYS::VARCHAR AS INT)), 14);
  LET db   STRING := COALESCE(NULLIF($WHGEN_TARGET_DB::VARCHAR, ''), CURRENT_DATABASE());
  LET mode STRING := UPPER(COALESCE($WHGEN_MODE::VARCHAR, 'DISCOVER'));
  LET sig  OBJECT := OBJECT_CONSTRUCT();
  LET cnt  OBJECT := OBJECT_CONSTRUCT();


  -- ── Probes ────────────────────────────────────────────────────────────────
  -- One BEGIN/EXCEPTION per signal. Copy the shape; do not merge them, because
  -- a merged probe turns one unreadable view into a dead run.
  --
  -- Probe: warehouse fleet via SHOW WAREHOUSES. Metadata only -- this is what
  -- makes generation, type and size readable at all: the generation of a
  -- warehouse is NOT exposed in any INFORMATION_SCHEMA view, and ACCOUNT_USAGE
  -- has no warehouse-generation column either. SHOW is the only source.
  BEGIN
    EXECUTE IMMEDIATE 'SHOW WAREHOUSES';
    LET wh_count INT := (SELECT COUNT(*) AS N FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    sig := OBJECT_INSERT(:sig, 'warehouses', IFF(:wh_count > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'warehouses', :wh_count, TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'warehouses', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'warehouses', 0, TRUE);
  END;

  -- Probe: how many of those are Gen1 STANDARD warehouses at a Gen2-eligible
  -- size. This is the addressable base, and it is reported separately from the
  -- fleet count because "you have 40 warehouses" and "9 of them can move" are
  -- different facts and only the second one is actionable.
  --
  -- Gen2 does not exist for 5X-Large or 6X-Large, and the GENERATION clause
  -- applies only to STANDARD warehouses -- Snowpark-optimized, INTERACTIVE and
  -- ADAPTIVE are all out. A warehouse outside those bounds is not a candidate
  -- however old it is.
  BEGIN
    EXECUTE IMMEDIATE 'SHOW WAREHOUSES';
    LET gen1_count INT := (
      SELECT COUNT(*) AS N FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
      WHERE COALESCE("generation", '') NOT IN ('2')
        AND UPPER(COALESCE("type", '')) = 'STANDARD'
        AND UPPER(COALESCE("size", '')) NOT IN ('5X-LARGE', '6X-LARGE'));
    sig := OBJECT_INSERT(:sig, 'gen1_eligible',
                         IFF(:gen1_count > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'gen1_eligible', :gen1_count, TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'gen1_eligible', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'gen1_eligible', 0, TRUE);
  END;

  -- Probe: credit consumption. Without this there is no spend to weigh a
  -- conversion against and the whole analysis is unquantified.
  BEGIN
    LET cr_rows INT := (SELECT COUNT(*) FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
                        WHERE START_TIME >= DATEADD(day, -:w, CURRENT_TIMESTAMP()));
    sig := OBJECT_INSERT(:sig, 'credit_history', IFF(:cr_rows > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'credit_history', :cr_rows, TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'credit_history', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'credit_history', 0, TRUE);
  END;

  -- Probe: query history. This is the workload-shape evidence -- what share of
  -- each warehouse's execution time is the kind of work Gen2 is documented to
  -- improve (table scans, DELETE, UPDATE, MERGE), how much it spills, how much
  -- it queues. Without it a Gen2 verdict is a coin toss on the customer's bill,
  -- and the plan degrades to reporting eligibility only, loudly.
  BEGIN
    LET qh_rows INT := (SELECT COUNT(*) FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
                        WHERE START_TIME >= DATEADD(day, -:w, CURRENT_TIMESTAMP()));
    sig := OBJECT_INSERT(:sig, 'query_history', IFF(:qh_rows > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'query_history', :qh_rows, TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'query_history', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'query_history', 0, TRUE);
  END;

  -- Probe: query-acceleration eligibility.
  --
  -- This exists because of an asymmetry that costs clients money silently.
  -- Snowflake enables QAS by default when a warehouse is CREATED as Gen2 (scale
  -- factor 2). It does NOT enable it when an existing Gen1 warehouse is ALTERed
  -- to Gen2 -- which is exactly what this solution's own conversion does. So
  -- every warehouse converted here lands in a different configuration from a
  -- natively-created Gen2 warehouse, and nothing said so until this probe.
  --
  -- QUERY_ACCELERATION_ELIGIBLE is the only place Snowflake states which queries
  -- it would actually accelerate, and it is ENTERPRISE-ONLY. On Standard Edition
  -- this probe reports NO ACCESS, and the QAS verdict downstream degrades to
  -- NO_EVIDENCE rather than recommending a feature the account cannot use.
  BEGIN
    LET qa_rows INT := (SELECT COUNT(*) FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ACCELERATION_ELIGIBLE
                        WHERE START_TIME >= DATEADD(day, -:w, CURRENT_TIMESTAMP()));
    sig := OBJECT_INSERT(:sig, 'qas_eligible', IFF(:qa_rows > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'qas_eligible', :qa_rows, TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'qas_eligible', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'qas_eligible', 0, TRUE);
  END;

  -- Probe: how many warehouses already run QAS. Read separately from the fleet
  -- snapshot because "4 of 66 have it on, and all 4 were created as Gen2" is the
  -- fact that makes the create-versus-alter asymmetry visible on the client's own
  -- estate rather than as a documentation claim.
  BEGIN
    EXECUTE IMMEDIATE 'SHOW WAREHOUSES';
    LET qas_on INT := (SELECT COUNT(*) AS N FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
                       WHERE LOWER(COALESCE("enable_query_acceleration", 'false')::VARCHAR)
                             IN ('true', 't', '1'));
    sig := OBJECT_INSERT(:sig, 'qas_enabled', IFF(:qas_on > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'qas_enabled', :qas_on, TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'qas_enabled', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'qas_enabled', 0, TRUE);
  END;

  -- Probe: warehouse events, for the burstiness that decides Adaptive candidacy.
  BEGIN
    LET ev_rows INT := (SELECT COUNT(*) FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_EVENTS_HISTORY
                        WHERE TIMESTAMP >= DATEADD(day, -:w, CURRENT_TIMESTAMP()));
    sig := OBJECT_INSERT(:sig, 'wh_events', IFF(:ev_rows > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'wh_events', :ev_rows, TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'wh_events', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'wh_events', 0, TRUE);
  END;

  -- Probe: region, which sets the Gen2 rate premium and gates both features.
  --
  -- CURRENT_REGION() returns something like PUBLIC.AWS_US_EAST_2, so the cloud
  -- is the segment after the region-group prefix. The premium differs by cloud
  -- (Azure is lower), and Gen2 is unavailable in a short list of regions, so
  -- getting this wrong mis-states every number downstream.
  BEGIN
    LET reg STRING := (SELECT CURRENT_REGION());
    LET cloud STRING := CASE
        WHEN UPPER(:reg) LIKE '%AWS%'   THEN 'AWS'
        WHEN UPPER(:reg) LIKE '%AZURE%' THEN 'AZURE'
        WHEN UPPER(:reg) LIKE '%GCP%'   THEN 'GCP'
        ELSE 'UNKNOWN' END;
    sig := OBJECT_INSERT(:sig, 'region', IFF(:cloud = 'UNKNOWN', 'EMPTY', 'AVAILABLE'), TRUE);
    sig := OBJECT_INSERT(:sig, 'cloud', :cloud, TRUE);
    sig := OBJECT_INSERT(:sig, 'region_name', :reg, TRUE);
    cnt := OBJECT_INSERT(:cnt, 'region', 1, TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'region', 'NO ACCESS', TRUE);
    sig := OBJECT_INSERT(:sig, 'cloud', 'UNKNOWN', TRUE);
    sig := OBJECT_INSERT(:sig, 'region_name', 'UNREADABLE', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'region', 0, TRUE);
  END;

  -- Probe: is this account plausibly Enterprise Edition or higher, which is a
  -- hard requirement for Adaptive Warehouses?
  --
  -- This is INFERRED and labelled as such, because edition is not reliably
  -- readable from inside a child account: SNOWFLAKE.ORGANIZATION_USAGE.ACCOUNTS
  -- returned zero rows on the account this was written against, and there is no
  -- CURRENT_EDITION() function. The inference used is multi-cluster warehouses,
  -- which are an Enterprise feature -- so a warehouse with MAX_CLUSTER_COUNT
  -- above 1 proves Enterprise or higher.
  --
  -- The inference is one-directional and the plan treats it that way: finding
  -- one proves Enterprise, finding none proves NOTHING. The Adaptive action is
  -- offered either way and its own ALTER is the authoritative test -- Snowflake
  -- refuses with a clear message if the edition or region does not support it,
  -- which is a better answer than this solution guessing.
  BEGIN
    EXECUTE IMMEDIATE 'SHOW WAREHOUSES';
    LET mcw INT := (SELECT COUNT(*) AS N FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
                    WHERE COALESCE("max_cluster_count", 1)::INT > 1);
    sig := OBJECT_INSERT(:sig, 'edition_hint',
                         IFF(:mcw > 0, 'ENTERPRISE_OR_HIGHER', 'UNKNOWN'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'multi_cluster_warehouses', :mcw, TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'edition_hint', 'UNKNOWN', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'multi_cluster_warehouses', 0, TRUE);
  END;

  -- Probe: does the account already run any Gen2 or Adaptive warehouse? If so
  -- there is an empirical anchor for the rate premium on this very account, and
  -- more importantly there is a team that has already done this once.
  BEGIN
    EXECUTE IMMEDIATE 'SHOW WAREHOUSES';
    LET g2 INT := (SELECT COUNT(*) AS N FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
                   WHERE COALESCE("generation", '') = '2');
    EXECUTE IMMEDIATE 'SHOW WAREHOUSES';
    LET ad INT := (SELECT COUNT(*) AS N FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
                   WHERE UPPER(COALESCE("type", '')) = 'ADAPTIVE');
    sig := OBJECT_INSERT(:sig, 'existing_gen2', IFF(:g2 > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    sig := OBJECT_INSERT(:sig, 'existing_adaptive', IFF(:ad > 0, 'AVAILABLE', 'EMPTY'), TRUE);
    cnt := OBJECT_INSERT(:cnt, 'existing_gen2', :g2, TRUE);
    cnt := OBJECT_INSERT(:cnt, 'existing_adaptive', :ad, TRUE);
  EXCEPTION WHEN OTHER THEN
    sig := OBJECT_INSERT(:sig, 'existing_gen2', 'NO ACCESS', TRUE);
    sig := OBJECT_INSERT(:sig, 'existing_adaptive', 'NO ACCESS', TRUE);
    cnt := OBJECT_INSERT(:cnt, 'existing_gen2', 0, TRUE);
    cnt := OBJECT_INSERT(:cnt, 'existing_adaptive', 0, TRUE);
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
      , 'gen1_eligible_count', COALESCE(GET(:cnt, 'gen1_eligible')::NUMBER, 0)
      , 'existing_gen2_count', COALESCE(GET(:cnt, 'existing_gen2')::NUMBER, 0)
      , 'existing_adaptive_count', COALESCE(GET(:cnt, 'existing_adaptive')::NUMBER, 0)
      , 'multi_cluster_count', COALESCE(GET(:cnt, 'multi_cluster_warehouses')::NUMBER, 0)
      , 'cloud', COALESCE(GET(:sig, 'cloud')::VARCHAR, 'UNKNOWN')
      , 'region_name', COALESCE(GET(:sig, 'region_name')::VARCHAR, 'UNREADABLE')
      , 'edition_hint', COALESCE(GET(:sig, 'edition_hint')::VARCHAR, 'UNKNOWN')
      , 'credit_history_rows', COALESCE(GET(:cnt, 'credit_history')::NUMBER, 0)
      , 'query_history_rows', COALESCE(GET(:cnt, 'query_history')::NUMBER, 0)
      , 'wh_events_rows', COALESCE(GET(:cnt, 'wh_events')::NUMBER, 0)
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
    EXECUTE IMMEDIATE 'SET WHGEN_SIGNALS_' || (:ci + 1)
                   || ' = ''' || :piece || '''';
    ci := :ci + 1;
  END WHILE;
  EXECUTE IMMEDIATE 'SET WHGEN_SIGNALS_N = ' || :nchunks;

  -- Prove the handoff survived rather than assuming it did.
  IF ((SELECT COALESCE(TRY_CAST(GETVARIABLE('WHGEN_SIGNALS_N') AS INT), 0)) <> :nchunks) THEN
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
  
  LET db      STRING := COALESCE(NULLIF($WHGEN_TARGET_DB::VARCHAR, ''), CURRENT_DATABASE());
  LET min_fill NUMBER(38,2) := COALESCE((SELECT TRY_CAST($WHGEN_MIN_FILL_PCT::VARCHAR AS NUMBER)), 60);
  LET sample_rows INT := 10000;
  LET prof_on BOOLEAN := FALSE;
  BEGIN
    prof_on := (SELECT TRY_CAST($WHGEN_PROFILE::VARCHAR AS BOOLEAN));
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
                   'Set WHGEN_PROFILE = TRUE to check whether the columns this plan '
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
                      || :min_fill || '% floor set by WHGEN_MIN_FILL_PCT.'
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
    EXECUTE IMMEDIATE 'SET WHGEN_PROFILE_' || (:pi + 1) || ' = ''' || :piece || '''';
    pi := :pi + 1;
  END WHILE;
  EXECUTE IMMEDIATE 'SET WHGEN_PROFILE_N = ' || :nchunks;

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
  -- 'WHGEN_SIGNALS_' || :i with "argument 0 ... needs to be constant".
  LET nchunks INT := COALESCE((SELECT TRY_CAST(GETVARIABLE('WHGEN_SIGNALS_N') AS INT)), 0);
  IF (:nchunks = 0) THEN
    res := (SELECT 0 AS step, 'BLOCKED' AS action,
                   'Block 1 has not run in this session. Run the file top to bottom.' AS statement);
    RETURN TABLE(res);
  END IF;

  LET buf STRING :=
       COALESCE(GETVARIABLE('WHGEN_SIGNALS_1'), '')
    || COALESCE(GETVARIABLE('WHGEN_SIGNALS_2'), '')
    || COALESCE(GETVARIABLE('WHGEN_SIGNALS_3'), '')
    || COALESCE(GETVARIABLE('WHGEN_SIGNALS_4'), '')
    || COALESCE(GETVARIABLE('WHGEN_SIGNALS_5'), '')
    || COALESCE(GETVARIABLE('WHGEN_SIGNALS_6'), '')
    || COALESCE(GETVARIABLE('WHGEN_SIGNALS_7'), '')
    || COALESCE(GETVARIABLE('WHGEN_SIGNALS_8'), '');

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
  LET db     STRING  := COALESCE(NULLIF($WHGEN_TARGET_DB::VARCHAR, ''), CURRENT_DATABASE());
  LET sch    STRING  := $WHGEN_SCHEMA::VARCHAR;
  LET wh     STRING  := COALESCE(NULLIF($WHGEN_APP_WAREHOUSE::VARCHAR, ''), CURRENT_WAREHOUSE());
  LET budget NUMBER  := COALESCE((SELECT TRY_CAST($WHGEN_BUDGET_CREDITS::VARCHAR AS NUMBER)), 0);

  -- ── Reassemble the profile handoff ────────────────────────────────────────
  -- Optional: Block 2 only publishes when its own gate is open. Absent is not
  -- the same as clean, and the difference is carried explicitly in :prof_status
  -- so nothing downstream can read "no findings" out of "never looked".
  LET pchunks INT := COALESCE((SELECT TRY_CAST(GETVARIABLE('WHGEN_PROFILE_N') AS INT)), 0);
  LET prof        VARIANT := NULL;
  LET prof_status STRING  := 'NOT RUN';
  IF (:pchunks > 0) THEN
    LET pbuf STRING :=
         COALESCE(GETVARIABLE('WHGEN_PROFILE_1'), '')
      || COALESCE(GETVARIABLE('WHGEN_PROFILE_2'), '')
      || COALESCE(GETVARIABLE('WHGEN_PROFILE_3'), '')
      || COALESCE(GETVARIABLE('WHGEN_PROFILE_4'), '');
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
  LET run_id STRING := COALESCE(NULLIF($WHGEN_RUN_ID::VARCHAR, ''), UUID_STRING());
  LET tier   STRING := UPPER(COALESCE(NULLIF($WHGEN_DEPLOY_TIER::VARCHAR, ''), 'DISCOVER'));
  IF (:tier NOT IN ('DISCOVER', 'LIMITED', 'PRODUCTION')) THEN
    tier := 'DISCOVER';
  END IF;
  LET qtag STRING := TO_JSON(OBJECT_CONSTRUCT(
      'oneshot', 'Warehouse Generation — Gen2 and Adaptive', 'prefix', 'WHGEN', 'run_id', :run_id, 'tier', :tier));
  LET tag_status STRING := 'NOT SET';
  BEGIN
    EXECUTE IMMEDIATE 'ALTER SESSION SET QUERY_TAG = ''' || REPLACE(:qtag, '''', '''''') || '''';
    tag_status := 'SET';
  EXCEPTION WHEN OTHER THEN
    tag_status := 'REFUSED (' || SQLERRM || ') - warehouse credits for this run '
               || 'cannot be attributed by tag and will read NOT_ATTRIBUTABLE';
  END;

  -- The warehouse the measured tiers build on, and the cap over it.
  LET meas_wh STRING := COALESCE(NULLIF($WHGEN_MEASURE_WAREHOUSE::VARCHAR, ''),
                                 LEFT(:sch, 80) || '_ONESHOT_WH');
  LET credit_cap NUMBER(38,2) := COALESCE((SELECT TRY_CAST($WHGEN_CREDIT_CAP::VARCHAR AS NUMBER)), 0);
  LET rate NUMBER(38,4) := COALESCE((SELECT TRY_CAST($WHGEN_COST_PER_CREDIT::VARCHAR AS NUMBER)), 3);
  LET out_ratio NUMBER(38,4) := COALESCE((SELECT TRY_CAST($WHGEN_OUTPUT_TOKEN_RATIO::VARCHAR AS NUMBER)), 0.5);
  LET min_fill NUMBER(38,2) := COALESCE((SELECT TRY_CAST($WHGEN_MIN_FILL_PCT::VARCHAR AS NUMBER)), 60);
  LET notif STRING := COALESCE(NULLIF($WHGEN_NOTIFICATION_INTEGRATION::VARCHAR, ''), '');

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
                   'No database selected. Run USE DATABASE or set WHGEN_TARGET_DB.' AS statement);
    RETURN TABLE(res);
  END IF;
  IF (:wh IS NULL) THEN
    res := (SELECT 0 AS step, 'BLOCKED' AS action,
                   'No warehouse selected. Run USE WAREHOUSE or set WHGEN_APP_WAREHOUSE.' AS statement);
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
    (SELECT TRY_CAST($WHGEN_ALLOW_ACTIONS::VARCHAR AS BOOLEAN)), FALSE);

  -- SAMPLE tier, governed separately and defaulting TRUE. Kept as its own variable
  -- rather than folded into :allow_actions so that the two authorisations stay
  -- distinguishable everywhere downstream -- the build context records both, and
  -- RUN_ACTION picks the one matching the action's own TIER. COALESCE to TRUE here
  -- because a build produced by an OLDER file that has no WHGEN_ALLOW_SAMPLE_ACTIONS
  -- line should still get the new default rather than silently disarming.
  LET allow_sample_actions BOOLEAN := COALESCE(
    (SELECT TRY_CAST($WHGEN_ALLOW_SAMPLE_ACTIONS::VARCHAR AS BOOLEAN)), TRUE);

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
  LET adapt_model  STRING  := COALESCE(NULLIF($WHGEN_MODEL::VARCHAR, ''), 'claude-opus-5');

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
    (SELECT TRY_CAST($WHGEN_KEEP_APP_WARM::VARCHAR AS BOOLEAN)), FALSE);
  LET warm_wh STRING := UPPER(TRIM(COALESCE(
    NULLIF($WHGEN_WARM_WAREHOUSE::VARCHAR, ''), 'ONESHOT_APP_WH')));
  -- An explicitly named app warehouse is an instruction, not a default, so
  -- warming leaves it alone rather than silently rehoming the app somewhere else.
  LET wh_named BOOLEAN := (NULLIF($WHGEN_APP_WAREHOUSE::VARCHAR, '') IS NOT NULL);
  LET warm_status STRING := 'OFF';

  IF (:warm_on AND :wh_named) THEN
    warm_status := 'DECLINED_EXPLICIT_WAREHOUSE';
    notes := ARRAY_APPEND(:notes,
      'APP WARMING SKIPPED: WHGEN_APP_WAREHOUSE names ' || :wh || ' explicitly, so '
   || 'the app stays there rather than being moved to ' || :warm_wh || '. Clear '
   || 'WHGEN_APP_WAREHOUSE to let warming manage the app warehouse, or set '
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
   || 'because they all share this warehouse. Set WHGEN_KEEP_APP_WARM = FALSE to '
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
      'APP WARMING DEGRADED: WHGEN_KEEP_APP_WARM is TRUE but ' || CURRENT_ROLE()
   || ' cannot create a warehouse, so the app stays on ' || :wh || ' and first '
   || 'loads pay for the package cache being rebuilt after every suspend. To fix, '
   || 'either GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE ' || CURRENT_ROLE()
   || ', or have an administrator run: CREATE WAREHOUSE ' || :warm_wh
   || ' WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = NULL AUTO_RESUME = TRUE; then set '
   || 'WHGEN_APP_WAREHOUSE = ''' || :warm_wh || '''.');
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
    (SELECT TRY_CAST($WHGEN_APP_SLEEP_MINUTES::VARCHAR AS INT)), 240);
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
   || 'COMMENT = ''oneshot Warehouse Generation — Gen2 and Adaptive run ' || :run_id || ' - dropped by TEARDOWN''');
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
 || 'CURRENT_TIMESTAMP() AS BUILT_AT, ''Warehouse Generation — Gen2 and Adaptive'' AS SOLUTION, '
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
 || '''WHGEN'' AS SETTING_PREFIX');

  -- ── Warehouse Generation Plan ───────────────────────────────────────────────
  --
  -- The one fact that shapes everything below: Gen2 bills at a HIGHER per-second
  -- rate than Gen1 for the same size. So a Gen1 warehouse moving to Gen2 gets
  -- cheaper ONLY if its runtime falls by more than the rate premium. At 1.35x the
  -- workload has to finish 25.93% faster just to break even; below that the same
  -- work costs more. "Upgrade the fleet to Gen2" is therefore not a savings
  -- recommendation, and this solution refuses to make it.

  -- ── The rate premium ────────────────────────────────────────────────────────
  -- Read from the setting when the client has supplied their own figure,
  -- otherwise inferred from the account's own cloud. AWS and GCP are 1.35x,
  -- Azure is 1.25x. These live in the Snowflake Service Consumption Table, not
  -- in anything queryable, so the value is declared rather than measured and the
  -- economics view says exactly that.
  LET cloud STRING := COALESCE(:sig:cloud::STRING, 'UNKNOWN');
  LET mult_setting NUMBER(38,4) := 0;
  BEGIN
    mult_setting := COALESCE((SELECT $WHGEN_RATE_MULTIPLIER::NUMBER(38,4)), 0);
  EXCEPTION WHEN OTHER THEN
    mult_setting := 0;
  END;

  LET mult NUMBER(38,4) := CASE
      WHEN :mult_setting > 0 THEN :mult_setting
      WHEN :cloud = 'AZURE'  THEN 1.25
      WHEN :cloud IN ('AWS', 'GCP') THEN 1.35
      -- An unknown cloud takes the HIGHER premium. The conservative direction
      -- here is the one that makes conversions look worse, because the failure
      -- that costs a client money is recommending a conversion that does not pay
      -- for itself, not declining one that would have.
      ELSE 1.35 END;

  LET mult_source STRING := CASE
      WHEN :mult_setting > 0 THEN 'WHGEN_RATE_MULTIPLIER setting, supplied by you'
      WHEN :cloud = 'UNKNOWN' THEN 'cloud not readable from CURRENT_REGION(), so the '
        || 'higher AWS/GCP premium was assumed -- set WHGEN_RATE_MULTIPLIER to correct it'
      ELSE 'published Gen2 rate for ' || :cloud
        || ' (Snowflake Service Consumption Table), inferred from CURRENT_REGION() = '
        || COALESCE(:sig:region_name::STRING, 'UNREADABLE') END;

  -- The break-even bar. This is arithmetic, not an estimate: at a rate premium
  -- of m, runtime must fall to 1/m of its former self, so the required reduction
  -- is (1 - 1/m).
  LET breakeven_pct NUMBER(38,2) := ROUND((1 - 1 / :mult) * 100, 2);

  LET min_credits NUMBER(38,4) := 5;
  BEGIN
    min_credits := COALESCE((SELECT $WHGEN_MIN_CREDITS::NUMBER(38,4)), 5);
  EXCEPTION WHEN OTHER THEN
    min_credits := 5;
  END;

  -- Per-size Gen1 credit rate, used to convert credits into billed warehouse
  -- seconds. Reused verbatim in several statements below, so it is built once.
  -- Both spellings of every size appear because SHOW WAREHOUSES reports
  -- 'X-Small' while ACCOUNT_USAGE reports 'XSMALL', and a solution that handles
  -- only one of them silently rates half the fleet at 1 credit/hour.
  LET size_rate STRING :=
      'CASE UPPER(REPLACE(WH_SIZE, ''-'', '''')) '
   || 'WHEN ''XSMALL'' THEN 1 WHEN ''SMALL'' THEN 2 WHEN ''MEDIUM'' THEN 4 '
   || 'WHEN ''LARGE'' THEN 8 WHEN ''XLARGE'' THEN 16 WHEN ''2XLARGE'' THEN 32 '
   || 'WHEN ''3XLARGE'' THEN 64 WHEN ''4XLARGE'' THEN 128 '
   || 'WHEN ''5XLARGE'' THEN 256 WHEN ''6XLARGE'' THEN 512 ELSE NULL END';

  -- ── The fleet snapshot ──────────────────────────────────────────────────────
  -- SHOW WAREHOUSES is the only place generation is exposed. Snapshotted as a
  -- table so every view below reads a consistent picture, and so the verdict a
  -- client screenshots is reproducible rather than shifting under them.
  LET demo_wh STRING := :sch || '_DEMO_WH';

  IF (:sig:warehouses::STRING = 'AVAILABLE') THEN
    stmts := ARRAY_APPEND(:stmts,
      'BEGIN SHOW WAREHOUSES; '
   || 'CREATE OR REPLACE TABLE ' || :tgt || '.WH_FLEET AS '
   || 'SELECT "name" AS WAREHOUSE_NAME, "size" AS WH_SIZE, '
   || 'UPPER(COALESCE("type", '''')) AS WH_TYPE, '
   || 'COALESCE("generation", '''') AS GENERATION, '
   || 'COALESCE("resource_constraint", '''') AS RESOURCE_CONSTRAINT, '
   || 'COALESCE("max_cluster_count", 1)::INT AS MAX_CLUSTERS, '
   || 'COALESCE("auto_suspend", 0)::INT AS AUTO_SUSPEND_SECS, '
   || 'COALESCE("enable_query_acceleration", ''false'')::VARCHAR AS QAS_ENABLED, '
   -- Captured so the QAS undo can restore the prior scale factor rather than
   -- guessing one. A warehouse with QAS off still carries a factor, and putting
   -- back the wrong number is a silent config change dressed up as a rollback.
   || 'COALESCE("query_acceleration_max_scale_factor", 0)::INT AS QAS_SCALE_FACTOR, '
   || 'CURRENT_TIMESTAMP() AS SNAPSHOT_AT '
   || 'FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) '
   -- Two warehouses are excluded because this tooling created them, and a
   -- warehouse that exists to host the script is not part of the estate the
   -- script is judging.
   --
   -- <schema>_DEMO_WH is the throwaway the SAMPLE action converts. <schema>_ONESHOT_WH
   -- is the warehouse the deployment harness creates to run the build and the app.
   -- Leaving the latter in was a real defect rather than an aesthetic one: it does
   -- not exist during the FIRST build and does during the second, so the fleet grew
   -- by one row on a re-run and the idempotence check correctly failed with
   -- CONVERSION_BASELINE 103 -> 104.
   || 'WHERE "name" NOT IN (' || CHAR(39) || :demo_wh || CHAR(39) || ', '
   || CHAR(39) || :sch || '_ONESHOT_WH' || CHAR(39) || '); END');
    cost_once := :cost_once + 0.01;
    cost_detail := ARRAY_APPEND(:cost_detail,
      'WH_FLEET snapshot ~0.01 credits (SHOW WAREHOUSES is metadata, no warehouse compute)');

    -- Register any gauntlet fixture warehouses so teardown drops them.
    stmts := ARRAY_APPEND(:stmts,
      'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY (TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) '
   || 'SELECT w.WAREHOUSE_NAME, ''WAREHOUSE'', ''FIXTURE'', ''FIXTURE_WAREHOUSE'' '
   || 'FROM ' || :tgt || '.WH_FLEET w '
   || 'WHERE w.WAREHOUSE_NAME LIKE ''GAUNTLET!_WHGEN!_%'' ESCAPE ''!'' '
   || 'AND NOT EXISTS (SELECT 1 FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY r '
   || 'WHERE r.TARGET_FQN = w.WAREHOUSE_NAME AND r.KIND = ''FIXTURE_WAREHOUSE'')');
  END IF;

  -- ── The economics, stated once and cited everywhere ─────────────────────────
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE VIEW ' || :tgt || '.V_GEN2_ECONOMICS AS SELECT '
 || CHAR(39) || :cloud || CHAR(39) || ' AS CLOUD, '
 || CHAR(39) || COALESCE(:sig:region_name::STRING, 'UNREADABLE') || CHAR(39) || ' AS REGION, '
 || :mult || '::NUMBER(38,4) AS GEN2_RATE_MULTIPLIER, '
 || :breakeven_pct || '::NUMBER(38,2) AS REQUIRED_SPEEDUP_PCT, '
 || CHAR(39) || :mult_source || CHAR(39) || ' AS MULTIPLIER_SOURCE, '
 || CHAR(39) || 'Gen2 costs ' || :mult || 'x the credits per hour of Gen1 for the same '
 || 'size, so the same work must finish at least ' || :breakeven_pct || '% faster to '
 || 'cost the same. Below that, converting raises the bill. This is arithmetic on '
 || 'the multiplier, not a projection.' || CHAR(39) || ' AS HOW_TO_READ_IT');
  cost_detail := ARRAY_APPEND(:cost_detail,
    'V_GEN2_ECONOMICS is a constant row, no scan cost');

  -- ── Workload shape per warehouse ────────────────────────────────────────────
  -- Three measured quantities decide whether Gen2 can pay for itself:
  --
  -- 1. UTILISATION. Billed warehouse seconds come from credits and the size's
  --    published rate, which already accounts for multi-cluster. Query seconds
  --    come from EXECUTION_TIME. The ratio is how much of what you pay for is
  --    actually executing. Gen2's premium applies to every billed second
  --    including idle ones, so a warehouse that is mostly idle gets strictly
  --    more expensive -- there is no runtime to shorten.
  --
  --    The ratio can exceed 1 on a concurrent warehouse, because several queries
  --    execute in the same wall-clock second. That is not an error, it is a
  --    well-packed warehouse, and it is the best possible Gen2 candidate.
  --
  -- 2. FAVOURABLE SHARE. The share of execution time spent on the work Snowflake
  --    documents Gen2 as improving: table scans, DELETE, UPDATE, MERGE. A
  --    warehouse whose time goes to tiny lookups has little for Gen2 to speed up.
  --    Scan-heavy is taken as a SELECT reading at least 1 GB; below that the
  --    query is not scan-bound and the faster hardware has less to work with.
  --
  -- 3. PRESSURE. Spill and queueing are direct evidence the warehouse is short of
  --    resource, which is the condition Gen2's faster hardware and higher
  --    concurrency actually relieve.
  IF (:sig:credit_history::STRING = 'AVAILABLE' AND :sig:warehouses::STRING = 'AVAILABLE') THEN
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE VIEW ' || :tgt || '.V_WH_WORKLOAD AS '
   || 'WITH credits AS ('
   -- Aggregate the DAILY totals, not the raw metering columns. The subquery below
   -- has already collapsed the hourly rows to one row per warehouse per day, so
   -- CREDITS_USED does not exist at this level -- reaching for it here is what made
   -- this view fail to compile with "invalid identifier CREDITS_USED", which took
   -- every downstream verdict, panel and action with it.
   || 'SELECT WAREHOUSE_NAME, SUM(DAILY_CREDITS) AS CREDITS_USED, '
   || 'COUNT(*) AS ACTIVE_DAYS, '
   -- Daily spread is the burstiness input for Adaptive. STDDEV over the daily
   -- totals rather than over the hourly rows: an overnight batch warehouse looks
   -- wildly variable by hour and is perfectly regular by day.
   || 'STDDEV(DAILY_CREDITS) AS DAILY_STDDEV, AVG(DAILY_CREDITS) AS DAILY_MEAN '
   || 'FROM (SELECT WAREHOUSE_NAME, DATE_TRUNC(''day'', START_TIME) AS D, '
   || 'SUM(CREDITS_USED) AS DAILY_CREDITS '
   || 'FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY '
   || 'WHERE START_TIME >= ' || :since || ' GROUP BY 1, 2) '
   || 'GROUP BY 1'
   || '), '
   || 'q AS ('
   || 'SELECT WAREHOUSE_NAME, '
   || 'COUNT(*) AS QUERY_COUNT, '
   || 'SUM(EXECUTION_TIME) / 1000.0 AS QUERY_SECONDS, '
   -- The favourable set. INSERT and COPY are included because both are
   -- write-path work that the delete/update/merge improvements cover, and
   -- CREATE_TABLE_AS_SELECT is a scan plus a write.
   || 'SUM(CASE WHEN QUERY_TYPE IN (''MERGE'', ''UPDATE'', ''DELETE'', ''INSERT'', '
   || '''COPY'', ''CREATE_TABLE_AS_SELECT'', ''UNLOAD'') '
   || 'OR (QUERY_TYPE = ''SELECT'' AND BYTES_SCANNED >= POWER(1024, 3)) '
   || 'THEN EXECUTION_TIME ELSE 0 END) / 1000.0 AS FAVOURABLE_SECONDS, '
   || 'SUM(QUEUED_OVERLOAD_TIME) / 1000.0 AS QUEUED_SECONDS, '
   || 'SUM(BYTES_SPILLED_TO_LOCAL_STORAGE) / POWER(1024, 3) AS SPILL_LOCAL_GB, '
   || 'SUM(BYTES_SPILLED_TO_REMOTE_STORAGE) / POWER(1024, 3) AS SPILL_REMOTE_GB, '
   || 'SUM(BYTES_SCANNED) / POWER(1024, 4) AS SCANNED_TB '
   || 'FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY '
   || 'WHERE START_TIME >= ' || :since || ' '
   || 'AND WAREHOUSE_NAME IS NOT NULL '
   -- A NULL warehouse size means the statement ran without warehouse compute
   -- (DESCRIBE, SHOW, LIST). Counting those inflates the query count and drags
   -- the favourable share down with work that costs nothing to begin with.
   || 'AND WAREHOUSE_SIZE IS NOT NULL '
   || 'GROUP BY 1'
   || ') '
   || 'SELECT f.WAREHOUSE_NAME, f.WH_SIZE, f.WH_TYPE, f.GENERATION, '
   || 'f.MAX_CLUSTERS, f.AUTO_SUSPEND_SECS, '
   || 'ROUND(COALESCE(c.CREDITS_USED, 0), 3) AS CREDITS_USED, '
   || 'COALESCE(c.ACTIVE_DAYS, 0) AS ACTIVE_DAYS, '
   || 'ROUND(DIV0(COALESCE(c.CREDITS_USED, 0), NULLIF(c.ACTIVE_DAYS, 0)), 3) AS CREDITS_PER_DAY, '
   || 'ROUND(DIV0(COALESCE(c.CREDITS_USED, 0) * 3600.0, '
   || 'NULLIF(' || REPLACE(:size_rate, 'WH_SIZE', 'f.WH_SIZE') || ', 0)), 1) AS BILLED_SECONDS, '
   || 'ROUND(COALESCE(q.QUERY_SECONDS, 0), 1) AS QUERY_SECONDS, '
   || 'ROUND(DIV0(COALESCE(q.QUERY_SECONDS, 0) * ' || REPLACE(:size_rate, 'WH_SIZE', 'f.WH_SIZE')
   || ', NULLIF(COALESCE(c.CREDITS_USED, 0) * 3600.0, 0)), 3) AS UTILISATION, '
   || 'ROUND(DIV0(COALESCE(q.FAVOURABLE_SECONDS, 0), '
   || 'NULLIF(COALESCE(q.QUERY_SECONDS, 0), 0)), 3) AS FAVOURABLE_SHARE, '
   || 'COALESCE(q.QUERY_COUNT, 0) AS QUERY_COUNT, '
   || 'ROUND(COALESCE(q.QUEUED_SECONDS, 0), 1) AS QUEUED_SECONDS, '
   || 'ROUND(COALESCE(q.SPILL_LOCAL_GB, 0), 2) AS SPILL_LOCAL_GB, '
   || 'ROUND(COALESCE(q.SPILL_REMOTE_GB, 0), 2) AS SPILL_REMOTE_GB, '
   || 'ROUND(COALESCE(q.SCANNED_TB, 0), 3) AS SCANNED_TB, '
   || 'ROUND(DIV0(COALESCE(c.DAILY_STDDEV, 0), NULLIF(c.DAILY_MEAN, 0)), 3) AS DAILY_CV, '
   -- Carried through so the verdict can judge QAS without re-reading the fleet.
   || 'f.QAS_ENABLED, f.QAS_SCALE_FACTOR '
   || 'FROM ' || :tgt || '.WH_FLEET f '
   || 'LEFT JOIN credits c ON f.WAREHOUSE_NAME = c.WAREHOUSE_NAME '
   || 'LEFT JOIN q ON f.WAREHOUSE_NAME = q.WAREHOUSE_NAME');
    cost_day    := :cost_day + 0.06;
    cost_detail := ARRAY_APPEND(:cost_detail,
      'V_WH_WORKLOAD scans QUERY_HISTORY and WAREHOUSE_METERING_HISTORY on every '
   || 'read ~0.06 credits/day');
    dials := ARRAY_APPEND(:dials,
      'WINDOW_DAYS ' || :w || ' -> 7 roughly halves the V_WH_WORKLOAD scan (~0.03 credits/day)');
  END IF;

  -- ── Query-acceleration eligibility, measured rather than assumed ────────────
  -- Snowflake will not say "this warehouse would be 20% faster with QAS". What it
  -- will say, per query, is how much of that query's execution time it could have
  -- offloaded. Summed per warehouse and divided by total execution time, that is
  -- the closest thing to an honest expected benefit, and it comes from the
  -- account's own queries rather than from a brochure.
  --
  -- UPPER_LIMIT_SCALE_FACTOR is carried because it is Snowflake's own ceiling on
  -- useful parallelism for that workload. Setting a factor above it buys nothing
  -- and raises the spend cap, so the action below never exceeds it.
  IF (:sig:qas_eligible::STRING = 'AVAILABLE') THEN
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE VIEW ' || :tgt || '.V_QAS_ELIGIBILITY AS '
   || 'SELECT WAREHOUSE_NAME, '
   || 'COUNT(*) AS ELIGIBLE_QUERIES, '
   -- ELIGIBLE_QUERY_ACCELERATION_TIME is seconds of execution time that QAS could
   -- have offloaded. It is NOT a saving: the offloaded work still runs, on
   -- separately-billed serverless compute.
   || 'ROUND(SUM(ELIGIBLE_QUERY_ACCELERATION_TIME), 1) AS ELIGIBLE_SECONDS, '
   || 'MAX(UPPER_LIMIT_SCALE_FACTOR) AS UPPER_LIMIT_SCALE_FACTOR '
   || 'FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ACCELERATION_ELIGIBLE '
   || 'WHERE START_TIME >= ' || :since || ' '
   || 'AND WAREHOUSE_NAME IS NOT NULL '
   || 'GROUP BY 1');
    cost_day    := :cost_day + 0.02;
    cost_detail := ARRAY_APPEND(:cost_detail,
      'V_QAS_ELIGIBILITY scans QUERY_ACCELERATION_ELIGIBLE ~0.02 credits/day');
  END IF;

  -- ── The verdict ─────────────────────────────────────────────────────────────
  -- Four outcomes, and only one of them is "convert this". The thresholds are
  -- JUDGEMENT, stated as such in the view, and they are deliberately set so that
  -- the default answer on thin evidence is PILOT_ONLY rather than GO. A verdict
  -- engine whose default is "yes" is a sales tool, not an analysis.
  IF (:sig:credit_history::STRING = 'AVAILABLE' AND :sig:warehouses::STRING = 'AVAILABLE') THEN
    -- The QAS half of the verdict only exists if the eligibility view was built.
    -- Held in variables so the view compiles either way: with evidence it judges,
    -- and without it it says NO_EVIDENCE rather than recommending a feature it
    -- cannot see the case for. QUERY_ACCELERATION_ELIGIBLE is Enterprise-only, so
    -- the second branch is a real account state, not a defensive nicety.
    --
    -- Why QAS belongs in a Gen2 verdict at all: Snowflake enables QAS by default
    -- when a warehouse is CREATED as Gen2, and does NOT when an existing Gen1
    -- warehouse is ALTERed to Gen2 -- which is what the conversion below does. So
    -- every warehouse this solution converts lands in a different configuration
    -- from a natively-created Gen2 warehouse, and nothing said so until now.
    LET qas_share STRING := 'ROUND(DIV0(COALESCE(qe.ELIGIBLE_SECONDS, 0), '
                         || 'NULLIF(w.QUERY_SECONDS, 0)), 3)';
    LET qas_is_on STRING := 'LOWER(COALESCE(w.QAS_ENABLED, ''false'')) '
                         || 'IN (''true'', ''t'', ''1'')';
    LET qas_cols  STRING := '';
    LET qas_join  STRING := '';

    IF (:sig:qas_eligible::STRING = 'AVAILABLE') THEN
      qas_join := ' LEFT JOIN ' || :tgt || '.V_QAS_ELIGIBILITY qe '
               || 'ON qe.WAREHOUSE_NAME = w.WAREHOUSE_NAME';
      qas_cols :=
         'w.QAS_ENABLED, w.QAS_SCALE_FACTOR, '
      || 'COALESCE(qe.ELIGIBLE_QUERIES, 0) AS QAS_ELIGIBLE_QUERIES, '
      || 'COALESCE(qe.ELIGIBLE_SECONDS, 0) AS QAS_ELIGIBLE_SECONDS, '
      || :qas_share || ' AS QAS_ELIGIBLE_SHARE, '
      -- Scale factor 2 is Snowflake's own default when it auto-enables QAS on a
      -- newly created Gen2 warehouse, and it is the conservative choice: the factor
      -- is a CEILING on billable QAS compute, not a target. Never propose above
      -- Snowflake's own stated ceiling for the workload.
      || 'LEAST(2, GREATEST(COALESCE(qe.UPPER_LIMIT_SCALE_FACTOR, 2), 1)) '
      || 'AS QAS_PROPOSED_SCALE_FACTOR, '
      || 'CASE '
      || 'WHEN w.WH_TYPE <> ''STANDARD'' THEN ''INELIGIBLE_TYPE'' '
      || 'WHEN ' || :qas_is_on || ' THEN ''ON'' '
      || 'WHEN COALESCE(qe.ELIGIBLE_SECONDS, 0) = 0 THEN ''NOT_WORTH_IT'' '
      || 'WHEN ' || :qas_share || ' >= 0.10 THEN ''RECOMMENDED'' '
      || 'ELSE ''NOT_WORTH_IT'' END AS QAS_VERDICT, '
      || 'CASE '
      || 'WHEN w.WH_TYPE <> ''STANDARD'' THEN ''Query acceleration is governed by '
      || 'the warehouse type here, not by this setting.'' '
      || 'WHEN ' || :qas_is_on || ' THEN ''Already on, at scale factor '' '
      || '|| w.QAS_SCALE_FACTOR || ''. Nothing to do.'' '
      || 'WHEN COALESCE(qe.ELIGIBLE_SECONDS, 0) = 0 THEN ''Snowflake marked none of '
      || 'this warehouse''''s queries eligible for acceleration in the window, so '
      || 'enabling it would add a separately-billed service that never engages.'' '
      || 'WHEN ' || :qas_share || ' >= 0.10 THEN ''Snowflake marked '' '
      || '|| COALESCE(qe.ELIGIBLE_QUERIES, 0) || '' queries eligible, covering '' '
      || '|| ROUND(' || :qas_share || ' * 100, 1) || ''% of execution time ('' '
      || '|| COALESCE(qe.ELIGIBLE_SECONDS, 0) || ''s). A warehouse CREATED as Gen2 '
      || 'gets QAS by default; converting one by ALTER does not, so this is the '
      || 'setting the conversion left behind. It is NOT a saving -- the offloaded '
      || 'work bills as serverless QAS credits. It is a way to shorten wall-clock '
      || 'on exactly the scan-heavy work that has to get faster for the Gen2 rate '
      || 'premium to pay for itself.'' '
      || 'ELSE ''Only '' || ROUND(' || :qas_share || ' * 100, 1) || ''% of execution '
      || 'time is eligible, below the 10% floor. The separately-billed QAS credits '
      || 'are unlikely to be repaid by that little.'' END AS QAS_WHY, '
      || CHAR(39) || 'The 10% eligible-share floor is judgement, not measurement. '
      || 'QAS bills serverless credits of its own, so the floor is set where the '
      || 'offload is large enough to plausibly repay them.' || CHAR(39)
      || ' AS QAS_THRESHOLD_IS_JUDGEMENT, ';
    ELSE
      qas_cols :=
         'w.QAS_ENABLED, w.QAS_SCALE_FACTOR, '
      || 'NULL::INT AS QAS_ELIGIBLE_QUERIES, '
      || 'NULL::NUMBER(38,1) AS QAS_ELIGIBLE_SECONDS, '
      || 'NULL::NUMBER(38,3) AS QAS_ELIGIBLE_SHARE, '
      || 'NULL::INT AS QAS_PROPOSED_SCALE_FACTOR, '
      || 'CASE WHEN w.WH_TYPE <> ''STANDARD'' THEN ''INELIGIBLE_TYPE'' '
      || 'WHEN ' || :qas_is_on || ' THEN ''ON'' '
      || 'ELSE ''NO_EVIDENCE'' END AS QAS_VERDICT, '
      || 'CASE WHEN w.WH_TYPE <> ''STANDARD'' THEN ''Query acceleration is governed '
      || 'by the warehouse type here, not by this setting.'' '
      || 'WHEN ' || :qas_is_on || ' THEN ''Already on, at scale factor '' '
      || '|| w.QAS_SCALE_FACTOR || ''. Nothing to do.'' '
      || 'ELSE ''SNOWFLAKE.ACCOUNT_USAGE.QUERY_ACCELERATION_ELIGIBLE was not '
      || 'readable, so there is no evidence either way -- it is an Enterprise '
      || 'Edition view. Worth checking by hand, because converting to Gen2 by '
      || 'ALTER does not enable QAS even though creating a Gen2 warehouse does.'' '
      || 'END AS QAS_WHY, '
      || CHAR(39) || 'No QAS eligibility evidence was readable on this account, so '
      || 'no QAS recommendation is made.' || CHAR(39)
      || ' AS QAS_THRESHOLD_IS_JUDGEMENT, ';
    END IF;

    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE VIEW ' || :tgt || '.V_GEN2_VERDICT AS '
   || 'SELECT w.WAREHOUSE_NAME, w.WH_SIZE, w.WH_TYPE, w.GENERATION, '
   || 'w.CREDITS_USED, w.CREDITS_PER_DAY, w.UTILISATION, w.FAVOURABLE_SHARE, '
   || 'w.QUEUED_SECONDS, w.SPILL_LOCAL_GB + w.SPILL_REMOTE_GB AS SPILL_GB, '
   || 'w.QUERY_COUNT, '
   || :qas_cols
   || :breakeven_pct || '::NUMBER(38,2) AS REQUIRED_SPEEDUP_PCT, '
   -- The number that reframes the whole conversation. If Gen2 delivers no
   -- speedup at all on this warehouse, this is what it adds to the bill per day.
   -- It is the downside a client is accepting when they press the button, and it
   -- is computed from their own measured spend rather than assumed away.
   || 'ROUND(w.CREDITS_PER_DAY * (' || :mult || ' - 1), 3) AS WORST_CASE_EXTRA_CREDITS_PER_DAY, '
   || 'CASE '
   -- Eligibility first. These are not judgements, they are what Snowflake
   -- supports, and a warehouse that fails them cannot be converted at all.
   || 'WHEN w.GENERATION = ''2'' THEN ''ALREADY_GEN2'' '
   || 'WHEN w.WH_TYPE <> ''STANDARD'' THEN ''INELIGIBLE_TYPE'' '
   || 'WHEN UPPER(REPLACE(w.WH_SIZE, ''-'', '''')) IN (''5XLARGE'', ''6XLARGE'') '
   || '  THEN ''INELIGIBLE_SIZE'' '
   || 'WHEN w.CREDITS_USED < ' || :min_credits || ' THEN ''IMMATERIAL'' '
   -- Then the economics. Idle-dominated first, because it is the case where
   -- conversion is not a gamble but a straight loss.
   || 'WHEN w.UTILISATION < 0.20 THEN ''AVOID'' '
   || 'WHEN w.FAVOURABLE_SHARE < 0.30 THEN ''AVOID'' '
   || 'WHEN w.UTILISATION >= 0.50 AND w.FAVOURABLE_SHARE >= 0.60 '
   || '  AND (w.QUEUED_SECONDS > 0 OR w.SPILL_LOCAL_GB + w.SPILL_REMOTE_GB > 0) '
   || '  THEN ''STRONG'' '
   || 'WHEN w.UTILISATION >= 0.35 AND w.FAVOURABLE_SHARE >= 0.45 THEN ''LIKELY'' '
   || 'ELSE ''PILOT_ONLY'' END AS VERDICT, '
   || 'CASE '
   || 'WHEN w.GENERATION = ''2'' THEN ''Already Gen2. Nothing to do.'' '
   || 'WHEN w.WH_TYPE <> ''STANDARD'' THEN ''The GENERATION clause applies only to '
   || 'STANDARD warehouses, so a '' || w.WH_TYPE || '' warehouse cannot be converted.'' '
   || 'WHEN UPPER(REPLACE(w.WH_SIZE, ''-'', '''')) IN (''5XLARGE'', ''6XLARGE'') '
   || '  THEN ''Gen2 is not available at '' || w.WH_SIZE || ''.'' '
   || 'WHEN w.CREDITS_USED < ' || :min_credits || ' THEN ''Spent '' || w.CREDITS_USED '
   || '  || '' credits in the window, below the '' || ' || :min_credits || ' || '' credit '
   || 'floor. Converting it can neither save nor cost anything worth measuring.'' '
   || 'WHEN w.UTILISATION < 0.20 THEN ''Only '' || ROUND(w.UTILISATION * 100, 1) '
   || '  || ''% of the billed time is executing queries, so this warehouse is paying '
   || 'mostly for idle. The Gen2 premium applies to idle seconds too and there is no '
   || 'runtime to shorten, so converting raises the bill with near-certainty. Fix the '
   || 'idle first -- auto-suspend, or fewer warehouses.'' '
   || 'WHEN w.FAVOURABLE_SHARE < 0.30 THEN ''Only '' || ROUND(w.FAVOURABLE_SHARE * 100, 1) '
   || '  || ''% of execution time is the scan-heavy or DML work Gen2 is documented to '
   || 'improve. Too little to clear a '' || ' || :breakeven_pct || ' || ''% bar.'' '
   || 'WHEN w.UTILISATION >= 0.50 AND w.FAVOURABLE_SHARE >= 0.60 '
   || '  AND (w.QUEUED_SECONDS > 0 OR w.SPILL_LOCAL_GB + w.SPILL_REMOTE_GB > 0) '
   || '  THEN ''Busy ('' || ROUND(w.UTILISATION * 100, 1) || ''% of billed time '
   || 'executing), dominated by scan and DML work ('' '
   || '  || ROUND(w.FAVOURABLE_SHARE * 100, 1) || ''%), and already under resource '
   || 'pressure -- '' || ROUND(w.QUEUED_SECONDS, 0) || ''s queued, '' '
   || '  || ROUND(w.SPILL_LOCAL_GB + w.SPILL_REMOTE_GB, 1) || '' GB spilled. This is the '
   || 'shape Gen2 is built for. Convert it, then check the outcome view.'' '
   || 'WHEN w.UTILISATION >= 0.35 AND w.FAVOURABLE_SHARE >= 0.45 '
   || '  THEN ''Reasonably busy and reasonably scan-heavy, but with no queueing or '
   || 'spill there is no evidence it is short of resource. Worth converting and '
   || 'measuring; do not assume the '' || ' || :breakeven_pct || ' || ''% speedup.'' '
   || 'ELSE ''Eligible, but the evidence is too thin to predict which side of the '
   || 'break-even it lands on. Convert it as a measured pilot, not as a rollout.'' '
   || 'END AS WHY, '
   || CHAR(39) || 'Thresholds (0.20/0.30/0.35/0.45/0.50/0.60) are judgement, not '
   || 'measurement. They are set so thin evidence yields PILOT_ONLY rather than a '
   || 'recommendation to convert.' || CHAR(39) || ' AS THRESHOLDS_ARE_JUDGEMENT '
   || 'FROM ' || :tgt || '.V_WH_WORKLOAD w' || :qas_join);
    cost_day    := :cost_day + 0.02;
    cost_detail := ARRAY_APPEND(:cost_detail,
      'V_GEN2_VERDICT reads V_WH_WORKLOAD ~0.02 credits/day');
  END IF;

  -- ── Adaptive candidacy, judged separately ───────────────────────────────────
  -- Adaptive is not "Gen2 but more so". It removes size, multi-cluster, QAS and
  -- suspend policy from your hands and bills per query, which is a good trade for
  -- bursty mixed workloads and a bad one for anything latency-critical. The docs
  -- are explicit about the exclusions, and they are the first thing checked here.
  IF (:sig:credit_history::STRING = 'AVAILABLE' AND :sig:warehouses::STRING = 'AVAILABLE') THEN
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE VIEW ' || :tgt || '.V_ADAPTIVE_VERDICT AS '
   || 'SELECT w.WAREHOUSE_NAME, w.WH_SIZE, w.WH_TYPE, w.CREDITS_USED, '
   || 'w.CREDITS_PER_DAY, w.DAILY_CV, w.MAX_CLUSTERS, w.QUEUED_SECONDS, '
   || 'w.UTILISATION, w.QUERY_COUNT, '
   || 'CASE '
   || 'WHEN w.WH_TYPE = ''ADAPTIVE'' THEN ''ALREADY_ADAPTIVE'' '
   -- Conversion to or from Snowpark-optimized and INTERACTIVE is unsupported, as
   -- is any conversion involving X5/X6-Large.
   || 'WHEN w.WH_TYPE <> ''STANDARD'' THEN ''UNSUPPORTED_CONVERSION'' '
   || 'WHEN UPPER(REPLACE(w.WH_SIZE, ''-'', '''')) IN (''5XLARGE'', ''6XLARGE'') '
   || '  THEN ''UNSUPPORTED_SIZE'' '
   || 'WHEN w.CREDITS_USED < ' || :min_credits || ' THEN ''IMMATERIAL'' '
   -- Burstiness and queueing are the two signals that a fixed size is the wrong
   -- shape for the workload. Either alone is enough to be worth a pilot.
   || 'WHEN w.DAILY_CV >= 0.60 AND w.QUEUED_SECONDS > 0 THEN ''STRONG'' '
   || 'WHEN w.DAILY_CV >= 0.60 OR w.QUEUED_SECONDS > 0 OR w.MAX_CLUSTERS > 1 '
   || '  THEN ''LIKELY'' '
   || 'WHEN w.UTILISATION >= 0.60 AND w.DAILY_CV < 0.30 THEN ''KEEP_STANDARD'' '
   || 'ELSE ''PILOT_ONLY'' END AS VERDICT, '
   || 'CASE '
   || 'WHEN w.WH_TYPE = ''ADAPTIVE'' THEN ''Already an Adaptive Warehouse.'' '
   || 'WHEN w.WH_TYPE <> ''STANDARD'' THEN ''Converting to or from a '' || w.WH_TYPE '
   || '  || '' warehouse is not a supported Adaptive conversion path.'' '
   || 'WHEN UPPER(REPLACE(w.WH_SIZE, ''-'', '''')) IN (''5XLARGE'', ''6XLARGE'') '
   || '  THEN ''Converting to or from '' || w.WH_SIZE || '' is not supported.'' '
   || 'WHEN w.CREDITS_USED < ' || :min_credits || ' THEN ''Too small to matter.'' '
   || 'WHEN w.DAILY_CV >= 0.60 AND w.QUEUED_SECONDS > 0 '
   || '  THEN ''Day-to-day spend swings hard (CV '' || w.DAILY_CV || '') AND it queues '
   || '('' || ROUND(w.QUEUED_SECONDS, 0) || ''s). A fixed size is wrong for this '
   || 'workload in both directions at once -- too small at peak, paid-for at trough. '
   || 'This is the clearest Adaptive case there is.'' '
   || 'WHEN w.DAILY_CV >= 0.60 THEN ''Spend swings day to day (CV '' || w.DAILY_CV '
   || '  || ''), which per-query allocation handles better than one fixed size.'' '
   || 'WHEN w.QUEUED_SECONDS > 0 THEN ''Queues for '' || ROUND(w.QUEUED_SECONDS, 0) '
   || '  || ''s in the window, so concurrency is the constraint. Adaptive routes '
   || 'against a shared pool instead of one fixed cluster count.'' '
   || 'WHEN w.MAX_CLUSTERS > 1 THEN ''Already multi-cluster, so someone has already '
   || 'decided the load varies. Adaptive removes the need to tune the cluster '
   || 'settings by hand.'' '
   || 'WHEN w.UTILISATION >= 0.60 AND w.DAILY_CV < 0.30 '
   || '  THEN ''Steady and well-utilised. Predictable everyday analytics is the case '
   || 'the docs say to keep on standard Gen2, where you keep direct control of size.'' '
   || 'ELSE ''No strong burstiness signal either way. Pilot it if you want the '
   || 'operational simplicity; do not expect a cost change.'' '
   || 'END AS WHY, '
   || CHAR(39) || 'Adaptive requires Enterprise Edition or higher and is available '
   || 'only in selected regions. This account reports: '
   || COALESCE(:sig:edition_hint::STRING, 'UNKNOWN')
   || '. That is INFERRED from multi-cluster usage, not read from the account -- '
   || 'edition is not queryable here. The ALTER itself is the real test and will '
   || 'refuse with a clear message if unsupported.' || CHAR(39) || ' AS ELIGIBILITY_NOTE, '
   || CHAR(39) || 'Adaptive bills per query rather than per warehouse-second, so a '
   || 'before-and-after on credits is the only way to know what it did to your '
   || 'cost. Nothing here predicts that number.' || CHAR(39) || ' AS COST_MODEL_NOTE '
   || 'FROM ' || :tgt || '.V_WH_WORKLOAD w');
    cost_day    := :cost_day + 0.02;
    cost_detail := ARRAY_APPEND(:cost_detail,
      'V_ADAPTIVE_VERDICT reads V_WH_WORKLOAD ~0.02 credits/day');
  END IF;

  -- ── The baseline, captured BEFORE anything is converted ─────────────────────
  -- This is the part that makes the rest defensible. A conversion with no
  -- before-picture cannot be evaluated afterwards, and "it feels faster" is what
  -- fills the vacuum. Every warehouse in the fleet gets a row now, so whichever
  -- ones get converted later have something to be measured against.
  --
  -- It is a TABLE, not a view, on purpose: a view would re-derive the "before"
  -- window after the change and compare the new behaviour against itself.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE TABLE IF NOT EXISTS ' || :tgt || '.CONVERSION_BASELINE ('
 || 'WAREHOUSE_NAME VARCHAR, WH_SIZE VARCHAR, GENERATION_BEFORE VARCHAR, '
 || 'WH_TYPE_BEFORE VARCHAR, AUTO_SUSPEND_BEFORE INT, '
 || 'WINDOW_DAYS INT, WINDOW_START TIMESTAMP_NTZ, WINDOW_END TIMESTAMP_NTZ, '
 || 'CREDITS_USED NUMBER(38,4), CREDITS_PER_DAY NUMBER(38,4), '
 || 'QUERY_SECONDS NUMBER(38,2), QUERY_COUNT NUMBER(38,0), '
 || 'SECONDS_PER_QUERY NUMBER(38,4), UTILISATION NUMBER(38,4), '
 || 'FAVOURABLE_SHARE NUMBER(38,4), CAPTURED_AT TIMESTAMP_NTZ, '
 || 'LABEL VARCHAR, BASIS VARCHAR)');

  IF (:sig:credit_history::STRING = 'AVAILABLE' AND :sig:warehouses::STRING = 'AVAILABLE') THEN
    -- One row per warehouse per build. Re-running the script re-captures the
    -- baseline for the CURRENT window, which is correct -- but it must not
    -- overwrite the row a conversion is already being measured against, so rows
    -- for warehouses that have a recorded GENERATION change are left alone.
    stmts := ARRAY_APPEND(:stmts,
      'DELETE FROM ' || :tgt || '.CONVERSION_BASELINE '
   || 'WHERE WAREHOUSE_NAME NOT IN ('
   || 'SELECT TARGET_FQN FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
   || 'WHERE KIND = ''WAREHOUSE_SETTING'')');
    stmts := ARRAY_APPEND(:stmts,
      'INSERT INTO ' || :tgt || '.CONVERSION_BASELINE '
   || '(WAREHOUSE_NAME, WH_SIZE, GENERATION_BEFORE, WH_TYPE_BEFORE, '
   || ' AUTO_SUSPEND_BEFORE, WINDOW_DAYS, WINDOW_START, WINDOW_END, '
   || ' CREDITS_USED, CREDITS_PER_DAY, QUERY_SECONDS, QUERY_COUNT, '
   || ' SECONDS_PER_QUERY, UTILISATION, FAVOURABLE_SHARE, CAPTURED_AT, LABEL, BASIS) '
   || 'SELECT w.WAREHOUSE_NAME, w.WH_SIZE, w.GENERATION, w.WH_TYPE, '
   || 'w.AUTO_SUSPEND_SECS, ' || :w || ', '
   || 'DATEADD(day, -' || :w || ', CURRENT_TIMESTAMP())::TIMESTAMP_NTZ, '
   || 'CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, '
   || 'w.CREDITS_USED, w.CREDITS_PER_DAY, w.QUERY_SECONDS, w.QUERY_COUNT, '
   -- Seconds per query is the metric a conversion should actually move. Credits
   -- per day moves with how much work arrived, which the conversion does not
   -- control; time per query is closer to the thing Gen2 claims to change.
   || 'ROUND(DIV0(w.QUERY_SECONDS, NULLIF(w.QUERY_COUNT, 0)), 4), '
   || 'w.UTILISATION, w.FAVOURABLE_SHARE, CURRENT_TIMESTAMP(), '
   || '''MEASURED'', ''BY_TIME_WINDOW'' '
   || 'FROM ' || :tgt || '.V_WH_WORKLOAD w '
   || 'WHERE NOT EXISTS (SELECT 1 FROM ' || :tgt || '.CONVERSION_BASELINE b '
   || 'WHERE b.WAREHOUSE_NAME = w.WAREHOUSE_NAME)');
    cost_once := :cost_once + 0.03;
    cost_detail := ARRAY_APPEND(:cost_detail,
      'CONVERSION_BASELINE capture ~0.03 credits one-time (reads V_WH_WORKLOAD once)');
  END IF;

  -- ── The outcome view: what the conversion actually did ──────────────────────
  -- Deliberately NOT called a savings view. It reports an OBSERVED DELTA with the
  -- basis stated, because attributing a credit difference to the conversion
  -- assumes nothing else about the workload moved, and in a live account
  -- something always did. The delta is the evidence; the attribution is the
  -- reader's judgement, and the view says so in a column rather than in a
  -- footnote nobody reads.
  IF (:sig:credit_history::STRING = 'AVAILABLE') THEN
    stmts := ARRAY_APPEND(:stmts,
      'CREATE OR REPLACE VIEW ' || :tgt || '.V_CONVERSION_OUTCOME AS '
   || 'WITH after AS ('
   || 'SELECT m.WAREHOUSE_NAME, '
   || 'SUM(m.CREDITS_USED) AS CREDITS_USED, '
   || 'COUNT(DISTINCT DATE_TRUNC(''day'', m.START_TIME)) AS DAYS_SINCE '
   || 'FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY m '
   || 'JOIN ' || :tgt || '.ATTACHED_OBJECT_REGISTRY r '
   || '  ON r.TARGET_FQN = m.WAREHOUSE_NAME AND r.KIND = ''WAREHOUSE_SETTING'' '
   || 'WHERE m.START_TIME::TIMESTAMP_NTZ > r.ATTACHED_AT '
   || 'GROUP BY 1'
   || '), '
   || 'aq AS ('
   || 'SELECT q.WAREHOUSE_NAME, '
   || 'SUM(q.EXECUTION_TIME) / 1000.0 AS QUERY_SECONDS, '
   || 'COUNT(*) AS QUERY_COUNT '
   || 'FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY q '
   || 'JOIN ' || :tgt || '.ATTACHED_OBJECT_REGISTRY r '
   || '  ON r.TARGET_FQN = q.WAREHOUSE_NAME AND r.KIND = ''WAREHOUSE_SETTING'' '
   || 'WHERE q.START_TIME::TIMESTAMP_NTZ > r.ATTACHED_AT AND q.WAREHOUSE_SIZE IS NOT NULL '
   || 'GROUP BY 1'
   || ') '
   || 'SELECT b.WAREHOUSE_NAME, b.WH_SIZE, '
   || 'b.GENERATION_BEFORE, r.ARTIFACT AS CHANGED_SETTING, r.ATTACHED_AT AS CHANGED_AT, '
   || 'b.CREDITS_PER_DAY AS BEFORE_CREDITS_PER_DAY, '
   || 'ROUND(DIV0(a.CREDITS_USED, NULLIF(a.DAYS_SINCE, 0)), 3) AS AFTER_CREDITS_PER_DAY, '
   || 'b.SECONDS_PER_QUERY AS BEFORE_SECONDS_PER_QUERY, '
   || 'ROUND(DIV0(aq.QUERY_SECONDS, NULLIF(aq.QUERY_COUNT, 0)), 4) AS AFTER_SECONDS_PER_QUERY, '
   -- The speedup actually achieved, against the bar it had to clear. These two
   -- columns side by side are the entire point of the solution.
   || 'ROUND((1 - DIV0(DIV0(aq.QUERY_SECONDS, NULLIF(aq.QUERY_COUNT, 0)), '
   || 'NULLIF(b.SECONDS_PER_QUERY, 0))) * 100, 2) AS OBSERVED_SPEEDUP_PCT, '
   || :breakeven_pct || '::NUMBER(38,2) AS REQUIRED_SPEEDUP_PCT, '
   || 'ROUND(DIV0(a.CREDITS_USED, NULLIF(a.DAYS_SINCE, 0)) - b.CREDITS_PER_DAY, 3) '
   || '  AS OBSERVED_DELTA_CREDITS_PER_DAY, '
   || 'a.DAYS_SINCE AS DAYS_OBSERVED, '
   || 'CASE '
   -- Under three days the daily rate is dominated by whichever day the change
   -- landed on. Calling a regression on one day of data would be exactly the
   -- kind of number this solution exists to stop.
   || 'WHEN COALESCE(a.DAYS_SINCE, 0) < 3 THEN ''TOO_EARLY'' '
   || 'WHEN DIV0(a.CREDITS_USED, NULLIF(a.DAYS_SINCE, 0)) > b.CREDITS_PER_DAY * 1.05 '
   || '  THEN ''COSTING_MORE'' '
   || 'WHEN DIV0(a.CREDITS_USED, NULLIF(a.DAYS_SINCE, 0)) < b.CREDITS_PER_DAY * 0.95 '
   || '  THEN ''COSTING_LESS'' '
   || 'ELSE ''NO_MATERIAL_CHANGE'' END AS OUTCOME, '
   || CHAR(39) || 'OBSERVED_DELTA_CREDITS_PER_DAY is a difference between two '
   || 'measured windows, not a saving. It attributes nothing: if the workload grew '
   || 'or shrank over the same period, that is in this number too. Read it with '
   || 'OBSERVED_SPEEDUP_PCT, which is far less sensitive to volume.'
   || CHAR(39) || ' AS HOW_TO_READ_IT, '
   || '''MEASURED'' AS LABEL, ''BY_TIME_WINDOW'' AS BASIS '
   || 'FROM ' || :tgt || '.CONVERSION_BASELINE b '
   || 'JOIN ' || :tgt || '.ATTACHED_OBJECT_REGISTRY r '
   || '  ON r.TARGET_FQN = b.WAREHOUSE_NAME AND r.KIND = ''WAREHOUSE_SETTING'' '
   || 'LEFT JOIN after a ON a.WAREHOUSE_NAME = b.WAREHOUSE_NAME '
   || 'LEFT JOIN aq ON aq.WAREHOUSE_NAME = b.WAREHOUSE_NAME');
    cost_day    := :cost_day + 0.04;
    cost_detail := ARRAY_APPEND(:cost_detail,
      'V_CONVERSION_OUTCOME scans metering and query history for converted '
   || 'warehouses only ~0.04 credits/day');
  END IF;

  -- ── A throwaway warehouse for the SAMPLE action ─────────────────────────────
  -- The SAMPLE tier must have something to convert that is not the customer's.
  -- Created here rather than inside the action because CREATE WAREHOUSE makes the
  -- new warehouse the session's CURRENT warehouse; when an undo then dropped it,
  -- every later statement in that session failed with "No active warehouse
  -- selected" -- including the UPDATE that closes the action log. Created here the
  -- hijack is harmless, and the action only flips a setting on it.
  --
  -- GENERATION = '1' is the whole point. Gen2 is the default for new standard
  -- warehouses since the 2026_03 bundle, so omitting this clause produces a Gen2
  -- warehouse and the demo would convert Gen2 to Gen2 while appearing to work.
  -- INITIALLY_SUSPENDED, and it never runs a query, so it bills nothing.
  IF (:sig:warehouses::STRING = 'AVAILABLE') THEN
    stmts := ARRAY_APPEND(:stmts,
      'CREATE WAREHOUSE IF NOT EXISTS ' || :demo_wh || ' WAREHOUSE_SIZE = XSMALL '
   || 'GENERATION = ''1'' AUTO_SUSPEND = 60 INITIALLY_SUSPENDED = TRUE COMMENT = '
   || CHAR(39) || 'Throwaway Gen1 warehouse for the ' || :sch || ' SAMPLE action. '
   || 'Never runs a query, so it bills nothing. Dropped by TEARDOWN().' || CHAR(39));
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

  -- ── Plan-time facts for the buttons ─────────────────────────────────────────
  -- The buttons need to name real warehouses and real counts, and the views that
  -- hold the verdict do not exist yet -- this build has not run. So the verdict is
  -- recomputed here, at plan time, from the same inputs against SHOW WAREHOUSES
  -- and ACCOUNT_USAGE in a single statement.
  --
  -- It is the same arithmetic as V_GEN2_VERDICT. Keeping the two in step matters:
  -- if the button says nine warehouses and the table shows seven, the reader stops
  -- trusting both. The success criteria below assert they agree.
  LET vf OBJECT := OBJECT_CONSTRUCT();
  IF (:sig:warehouses::STRING = 'AVAILABLE' AND :sig:credit_history::STRING = 'AVAILABLE') THEN
    BEGIN
      SHOW WAREHOUSES;
      SELECT OBJECT_CONSTRUCT(
               'affirmative_n', COUNT_IF(VERDICT IN ('STRONG', 'LIKELY')),
               'strong_n',      COUNT_IF(VERDICT = 'STRONG'),
               'avoid_n',       COUNT_IF(VERDICT = 'AVOID'),
               'eligible_n',    COUNT_IF(VERDICT NOT IN ('ALREADY_GEN2',
                                  'INELIGIBLE_TYPE', 'INELIGIBLE_SIZE')),
               'affirmative_credits_per_day',
                 ROUND(SUM(IFF(VERDICT IN ('STRONG', 'LIKELY'), CREDITS_PER_DAY, 0)), 3),
               'worst_case_extra_per_day',
                 ROUND(SUM(IFF(VERDICT IN ('STRONG', 'LIKELY'), CREDITS_PER_DAY, 0))
                       * (:mult - 1), 3),
               -- Deterministic pick, and NOT MAX_BY: MAX_BY breaks ties
               -- arbitrarily, so two warehouses on identical spend would let the
               -- caption name one and the ALTER change the other. Zero-padding the
               -- credits makes a lexicographic MAX order by spend then by name.
               'pilot', SPLIT_PART(MAX(IFF(VERDICT IN ('STRONG', 'LIKELY'),
                          LPAD(ROUND(CREDITS_PER_DAY * 1000)::VARCHAR, 18, '0')
                            || '|' || WAREHOUSE_NAME, '')), '|', 2),
               'adaptive_n', COUNT_IF(ADAPTIVE_VERDICT IN ('STRONG', 'LIKELY')),
               'adaptive_pilot', SPLIT_PART(MAX(IFF(ADAPTIVE_VERDICT IN ('STRONG', 'LIKELY'),
                          LPAD(ROUND(CREDITS_PER_DAY * 1000)::VARCHAR, 18, '0')
                            || '|' || WAREHOUSE_NAME, '')), '|', 2)
             ) INTO :vf
      FROM (
        SELECT f.WAREHOUSE_NAME, f.CREDITS_PER_DAY,
               CASE
                 WHEN f.GENERATION = '2' THEN 'ALREADY_GEN2'
                 WHEN f.WH_TYPE <> 'STANDARD' THEN 'INELIGIBLE_TYPE'
                 WHEN f.SIZE_KEY IN ('5XLARGE', '6XLARGE') THEN 'INELIGIBLE_SIZE'
                 WHEN f.CREDITS_USED < :min_credits THEN 'IMMATERIAL'
                 WHEN f.UTILISATION < 0.20 THEN 'AVOID'
                 WHEN f.FAVOURABLE_SHARE < 0.30 THEN 'AVOID'
                 WHEN f.UTILISATION >= 0.50 AND f.FAVOURABLE_SHARE >= 0.60
                      AND (f.QUEUED_SECONDS > 0 OR f.SPILL_GB > 0) THEN 'STRONG'
                 WHEN f.UTILISATION >= 0.35 AND f.FAVOURABLE_SHARE >= 0.45 THEN 'LIKELY'
                 ELSE 'PILOT_ONLY' END AS VERDICT,
               CASE
                 WHEN f.WH_TYPE = 'ADAPTIVE' THEN 'ALREADY_ADAPTIVE'
                 WHEN f.WH_TYPE <> 'STANDARD' THEN 'UNSUPPORTED_CONVERSION'
                 WHEN f.SIZE_KEY IN ('5XLARGE', '6XLARGE') THEN 'UNSUPPORTED_SIZE'
                 WHEN f.CREDITS_USED < :min_credits THEN 'IMMATERIAL'
                 WHEN f.DAILY_CV >= 0.60 AND f.QUEUED_SECONDS > 0 THEN 'STRONG'
                 WHEN f.DAILY_CV >= 0.60 OR f.QUEUED_SECONDS > 0 OR f.MAX_CLUSTERS > 1
                      THEN 'LIKELY'
                 ELSE 'PILOT_ONLY' END AS ADAPTIVE_VERDICT
        FROM (
          SELECT s."name" AS WAREHOUSE_NAME,
                 UPPER(REPLACE(s."size", '-', '')) AS SIZE_KEY,
                 UPPER(COALESCE(s."type", '')) AS WH_TYPE,
                 COALESCE(s."generation", '') AS GENERATION,
                 COALESCE(s."max_cluster_count", 1)::INT AS MAX_CLUSTERS,
                 COALESCE(c.CREDITS_USED, 0) AS CREDITS_USED,
                 DIV0(COALESCE(c.CREDITS_USED, 0), NULLIF(c.ACTIVE_DAYS, 0)) AS CREDITS_PER_DAY,
                 DIV0(COALESCE(c.DAILY_STDDEV, 0), NULLIF(c.DAILY_MEAN, 0)) AS DAILY_CV,
                 DIV0(COALESCE(q.QUERY_SECONDS, 0)
                      * CASE UPPER(REPLACE(s."size", '-', ''))
                          WHEN 'XSMALL' THEN 1 WHEN 'SMALL' THEN 2 WHEN 'MEDIUM' THEN 4
                          WHEN 'LARGE' THEN 8 WHEN 'XLARGE' THEN 16 WHEN '2XLARGE' THEN 32
                          WHEN '3XLARGE' THEN 64 WHEN '4XLARGE' THEN 128
                          WHEN '5XLARGE' THEN 256 WHEN '6XLARGE' THEN 512 ELSE NULL END,
                      NULLIF(COALESCE(c.CREDITS_USED, 0) * 3600.0, 0)) AS UTILISATION,
                 DIV0(COALESCE(q.FAVOURABLE_SECONDS, 0),
                      NULLIF(COALESCE(q.QUERY_SECONDS, 0), 0)) AS FAVOURABLE_SHARE,
                 COALESCE(q.QUEUED_SECONDS, 0) AS QUEUED_SECONDS,
                 COALESCE(q.SPILL_GB, 0) AS SPILL_GB
          FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) s
          LEFT JOIN (
            SELECT WAREHOUSE_NAME, SUM(DAILY_CREDITS) AS CREDITS_USED,
                   COUNT(*) AS ACTIVE_DAYS,
                   STDDEV(DAILY_CREDITS) AS DAILY_STDDEV, AVG(DAILY_CREDITS) AS DAILY_MEAN
            FROM (SELECT WAREHOUSE_NAME, DATE_TRUNC('day', START_TIME) AS D,
                         SUM(CREDITS_USED) AS DAILY_CREDITS
                  FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
                  WHERE START_TIME >= DATEADD(day, -:w, CURRENT_TIMESTAMP())
                  GROUP BY 1, 2)
            GROUP BY 1) c ON c.WAREHOUSE_NAME = s."name"
          LEFT JOIN (
            SELECT WAREHOUSE_NAME,
                   SUM(EXECUTION_TIME) / 1000.0 AS QUERY_SECONDS,
                   SUM(CASE WHEN QUERY_TYPE IN ('MERGE', 'UPDATE', 'DELETE', 'INSERT',
                                                'COPY', 'CREATE_TABLE_AS_SELECT', 'UNLOAD')
                             OR (QUERY_TYPE = 'SELECT' AND BYTES_SCANNED >= POWER(1024, 3))
                            THEN EXECUTION_TIME ELSE 0 END) / 1000.0 AS FAVOURABLE_SECONDS,
                   SUM(QUEUED_OVERLOAD_TIME) / 1000.0 AS QUEUED_SECONDS,
                   SUM(BYTES_SPILLED_TO_LOCAL_STORAGE + BYTES_SPILLED_TO_REMOTE_STORAGE)
                     / POWER(1024, 3) AS SPILL_GB
            FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
            WHERE START_TIME >= DATEADD(day, -:w, CURRENT_TIMESTAMP())
              AND WAREHOUSE_NAME IS NOT NULL AND WAREHOUSE_SIZE IS NOT NULL
            GROUP BY 1) q ON q.WAREHOUSE_NAME = s."name"
          WHERE s."name" <> :demo_wh
        ) f
      );
    EXCEPTION WHEN OTHER THEN
      vf := OBJECT_CONSTRUCT();
    END;
    cost_once := :cost_once + 0.03;
    cost_detail := ARRAY_APPEND(:cost_detail,
      'Plan-time verdict recompute ~0.03 credits (one pass over metering and query '
   || 'history, so the buttons can name real warehouses before anything is built)');
  END IF;

  LET affirm_n   INT    := COALESCE(:vf:affirmative_n::INT, 0);
  LET strong_n   INT    := COALESCE(:vf:strong_n::INT, 0);
  LET avoid_n    INT    := COALESCE(:vf:avoid_n::INT, 0);
  LET pilot_wh   STRING := COALESCE(:vf:pilot::STRING, '');
  LET adapt_n    INT    := COALESCE(:vf:adaptive_n::INT, 0);
  LET adapt_wh   STRING := COALESCE(:vf:adaptive_pilot::STRING, '');
  LET affirm_cpd NUMBER(38,6) := COALESCE(:vf:affirmative_credits_per_day::NUMBER(38,6), 0);
  LET worst_cpd  NUMBER(38,6) := COALESCE(:vf:worst_case_extra_per_day::NUMBER(38,6), 0);

  -- ── QAS candidate count, deliberately in its OWN exception block ─────────────
  -- Not folded into the recompute above, and that is the whole point:
  -- QUERY_ACCELERATION_ELIGIBLE is Enterprise-only, so a single unreadable view
  -- inside that statement would empty `vf` and silently zero affirm_n, strong_n and
  -- the pilot name -- taking the Gen2 buttons out on every Standard Edition account.
  -- One isolated failure costs one button, which is the same rule the probes follow.
  LET qas_n    INT           := 0;
  LET qas_secs NUMBER(38,1)  := 0;
  IF (:sig:qas_eligible::STRING = 'AVAILABLE' AND :sig:warehouses::STRING = 'AVAILABLE') THEN
    BEGIN
      SHOW WAREHOUSES;
      SELECT COUNT(*), COALESCE(ROUND(SUM(ELIGIBLE_SECONDS), 1), 0)
        INTO :qas_n, :qas_secs
      FROM (
        SELECT s."name" AS WAREHOUSE_NAME,
               COALESCE(e.ELIGIBLE_SECONDS, 0) AS ELIGIBLE_SECONDS
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) s
        LEFT JOIN (
          SELECT WAREHOUSE_NAME,
                 SUM(ELIGIBLE_QUERY_ACCELERATION_TIME) AS ELIGIBLE_SECONDS
          FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ACCELERATION_ELIGIBLE
          WHERE START_TIME >= DATEADD(day, -:w, CURRENT_TIMESTAMP())
            AND WAREHOUSE_NAME IS NOT NULL
          GROUP BY 1) e ON e.WAREHOUSE_NAME = s."name"
        LEFT JOIN (
          SELECT WAREHOUSE_NAME, SUM(EXECUTION_TIME) / 1000.0 AS QUERY_SECONDS
          FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
          WHERE START_TIME >= DATEADD(day, -:w, CURRENT_TIMESTAMP())
            AND WAREHOUSE_NAME IS NOT NULL AND WAREHOUSE_SIZE IS NOT NULL
          GROUP BY 1) q ON q.WAREHOUSE_NAME = s."name"
        WHERE s."name" <> :demo_wh
          -- The same three tests the view applies, in the same order.
          AND UPPER(COALESCE(s."type", '')) = 'STANDARD'
          AND LOWER(COALESCE(s."enable_query_acceleration", 'false')::VARCHAR)
              NOT IN ('true', 't', '1')
          AND DIV0(COALESCE(e.ELIGIBLE_SECONDS, 0),
                   NULLIF(COALESCE(q.QUERY_SECONDS, 0), 0)) >= 0.10
      );
    EXCEPTION WHEN OTHER THEN
      qas_n    := 0;
      qas_secs := 0;
    END;
    cost_once := :cost_once + 0.02;
    cost_detail := ARRAY_APPEND(:cost_detail,
      'Plan-time QAS candidate count ~0.02 credits (one pass over '
   || 'QUERY_ACCELERATION_ELIGIBLE and query history)');
  END IF;

  -- ── Reusable SQL for recording and restoring a generation change ────────────
  -- Recording the PRIOR generation is what makes the change reversible, and the
  -- literal '1' rather than the observed value is deliberate: SHOW WAREHOUSES
  -- reports a blank generation for warehouses that predate the column, and
  -- restoring `SET GENERATION = ` would be a syntax error. A standard warehouse
  -- that is not Gen2 is a Gen1 warehouse, so that is what gets recorded.
  --
  -- The NOT EXISTS guard stops a second press from recording '2' as the original
  -- and turning the undo into a no-op.
  LET reg_gen STRING :=
      'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
   || '(TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) '
   || 'SELECT v.WAREHOUSE_NAME, ''GENERATION'', CHAR(39) || ''1'' || CHAR(39), '
   || '''WAREHOUSE_SETTING'' FROM ' || :tgt || '.V_GEN2_VERDICT v '
   || 'WHERE v.VERDICT IN (''STRONG'', ''LIKELY'') '
   || 'AND NOT EXISTS (SELECT 1 FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY r '
   || 'WHERE r.TARGET_FQN = v.WAREHOUSE_NAME AND r.ARTIFACT = ''GENERATION'')';

  LET undo_gen ARRAY := ARRAY_CONSTRUCT(
      'BEGIN LET c CURSOR FOR SELECT TARGET_FQN, ARGUMENTS FROM ' || :tgt
   || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ' || CHAR(39) || 'WAREHOUSE_SETTING'
   || CHAR(39) || ' AND ARTIFACT = ' || CHAR(39) || 'GENERATION' || CHAR(39) || '; '
   || 'FOR r IN c DO '
   || 'EXECUTE IMMEDIATE ' || CHAR(39) || 'ALTER WAREHOUSE "' || CHAR(39)
   || ' || r.TARGET_FQN || ' || CHAR(39) || '" SET GENERATION = ' || CHAR(39)
   || ' || r.ARGUMENTS; '
   || 'END FOR; END',
      -- Dropping the recording matters. Leaving the rows means the NOT EXISTS
      -- guard on the next press treats Gen2 as the original value, and the
      -- conversion becomes permanent without anyone choosing that.
      'DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
   || 'WHERE KIND = ' || CHAR(39) || 'WAREHOUSE_SETTING' || CHAR(39)
   || ' AND ARTIFACT = ' || CHAR(39) || 'GENERATION' || CHAR(39));

  -- ── SAMPLE: prove the mechanism on a warehouse that is not yours ────────────
  IF (:sig:warehouses::STRING = 'AVAILABLE') THEN
    actions := ARRAY_APPEND(:actions, OBJECT_CONSTRUCT(
      'code',   'GEN2_DEMO',
      'label',  'Convert a throwaway Gen1 warehouse to Gen2, then put it back',
      'tier',   'SAMPLE',
      'effect', 'Records the generation of ' || :demo_wh || ' -- a suspended Gen1 '
             || 'warehouse this script created for exactly this purpose -- and sets '
             || 'GENERATION = 2. None of your warehouses are touched. Press Undo to '
             || 'watch it return to Gen1, which is the same undo the real conversions '
             || 'use.',
      'undo',   'Undo restores the recorded generation. TEARDOWN() drops the warehouse.',
      'est',    0.01,
      'basis',  'Two ALTER WAREHOUSE statements. ALTER is metadata-only and the '
             || 'warehouse is suspended throughout, so nothing runs and nothing bills.',
      'sql',    ARRAY_CONSTRUCT(
        'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
     || '(TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) SELECT ' || CHAR(39) || :demo_wh
     || CHAR(39) || ', ' || CHAR(39) || 'GENERATION' || CHAR(39) || ', '
     || 'CHAR(39) || ' || CHAR(39) || '1' || CHAR(39) || ' || CHAR(39), '
     || CHAR(39) || 'WAREHOUSE_SETTING' || CHAR(39)
     || ' WHERE NOT EXISTS (SELECT 1 FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
     || 'WHERE TARGET_FQN = ' || CHAR(39) || :demo_wh || CHAR(39)
     || ' AND ARTIFACT = ' || CHAR(39) || 'GENERATION' || CHAR(39) || ')',
        'ALTER WAREHOUSE ' || :demo_wh || ' SET GENERATION = ''2'''),
      'undo_sql', ARRAY_CONSTRUCT(
        'ALTER WAREHOUSE ' || :demo_wh || ' SET GENERATION = ''1''',
        'DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE TARGET_FQN = '
     || CHAR(39) || :demo_wh || CHAR(39) || ' AND ARTIFACT = '
     || CHAR(39) || 'GENERATION' || CHAR(39))
    ));
  END IF;

  -- ── LIMITED: the measured pilot, one warehouse ──────────────────────────────
  -- This is the action that should actually get pressed first, and the one the
  -- whole solution is arranged around. One warehouse, named on the button, with a
  -- baseline already captured and an outcome view waiting for it.
  IF (:pilot_wh <> '') THEN
    actions := ARRAY_APPEND(:actions, OBJECT_CONSTRUCT(
      'code',   'GEN2_PILOT',
      'label',  'Pilot Gen2 on ' || :pilot_wh,
      'tier',   'LIMITED',
      'effect', 'Sets GENERATION = 2 on ' || :pilot_wh || ' and nothing else. Its '
             || 'baseline was captured by this build, so V_CONVERSION_OUTCOME will '
             || 'show the speedup it actually achieved against the '
             || :breakeven_pct || '% it has to beat -- give it at least three days '
             || 'before reading, and the view says TOO_EARLY until then. Cheapest '
             || 'moment to press this is while the warehouse is idle: converting a '
             || 'RUNNING warehouse bills BOTH generations until in-flight queries '
             || 'drain.',
      'undo',   'Reversible. Undo restores Gen1, and Snowflake supports moving from '
             || 'Gen2 back to Gen1 directly on a running or suspended warehouse.',
      'est',    0.01,
      'basis',  'One ALTER WAREHOUSE, metadata-only. The cost that follows is the '
             || 'workload itself at the Gen2 rate, which is what the pilot exists to '
             || 'measure -- currently ' || ROUND(:affirm_cpd, 3) || ' credits/day '
             || 'across all affirmative candidates.',
      'sql',    ARRAY_CONSTRUCT(
        'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
     || '(TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) SELECT ' || CHAR(39) || :pilot_wh
     || CHAR(39) || ', ' || CHAR(39) || 'GENERATION' || CHAR(39) || ', '
     || 'CHAR(39) || ' || CHAR(39) || '1' || CHAR(39) || ' || CHAR(39), '
     || CHAR(39) || 'WAREHOUSE_SETTING' || CHAR(39)
     || ' WHERE NOT EXISTS (SELECT 1 FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
     || 'WHERE TARGET_FQN = ' || CHAR(39) || :pilot_wh || CHAR(39)
     || ' AND ARTIFACT = ' || CHAR(39) || 'GENERATION' || CHAR(39) || ')',
        'ALTER WAREHOUSE "' || :pilot_wh || '" SET GENERATION = ''2'''),
      'undo_sql', ARRAY_CONSTRUCT(
        'ALTER WAREHOUSE "' || :pilot_wh || '" SET GENERATION = ''1''',
        'DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE TARGET_FQN = '
     || CHAR(39) || :pilot_wh || CHAR(39) || ' AND ARTIFACT = '
     || CHAR(39) || 'GENERATION' || CHAR(39))
    ));
  END IF;

  -- ── PRODUCTION: the affirmative cohort, and only the affirmative cohort ─────
  -- Never "all Gen1 warehouses". AVOID, PILOT_ONLY, IMMATERIAL and every
  -- ineligible verdict are excluded by the same view the reader is looking at, so
  -- the button and the table cannot disagree.
  --
  -- No EXCEPTION handler on the loop, on purpose: a button that swallows a failed
  -- ALTER and reports DONE is worse than one that stops. RUN_ACTION logs the
  -- failure and halts, leaving a partial cohort that the registry can still undo.
  IF (:affirm_n > 0) THEN
    actions := ARRAY_APPEND(:actions, OBJECT_CONSTRUCT(
      'code',   'GEN2_COHORT',
      'label',  'Convert the ' || :affirm_n || ' warehouse(s) the evidence supports',
      'tier',   'PRODUCTION',
      'effect', 'Sets GENERATION = 2 on every warehouse whose verdict is STRONG or '
             || 'LIKELY -- ' || :strong_n || ' STRONG, ' || (:affirm_n - :strong_n)
              || ' LIKELY. Warehouses marked AVOID are deliberately left alone: '
              || :avoid_n || ' of them, where converting would raise the bill rather '
              || 'than lower it. Press this while the fleet is quiet -- a RUNNING '
              || 'warehouse bills both generations until its in-flight queries drain. '
              -- Stated here rather than left as a surprise. A client who presses this
              -- and then reads Snowflake's Gen2 page will find that new Gen2
              -- warehouses get QAS and wonder why theirs did not.
              || 'Note: this does NOT enable Query Acceleration. Snowflake enables QAS '
              || 'automatically on a warehouse CREATED as Gen2, but not on one ALTERed '
              || 'to Gen2, so these warehouses will differ from a natively-created Gen2 '
              || 'warehouse. That is judged separately by QAS_VERDICT and offered as its '
              || 'own action, because QAS bills serverless credits of its own and should '
              || 'not ride along inside a different consent.',

      'undo',   'Reversible: Undo restores every recorded generation, and so does '
             || 'CALL ' || :tgt || '.TEARDOWN().',
      'est',    ROUND(0.01 * :affirm_n, 3),
      'basis',  :affirm_n || ' ALTER WAREHOUSE statements, metadata-only, so applying '
             || 'it is ~' || ROUND(0.01 * :affirm_n, 3) || ' credits. The number that '
             || 'matters is not that one: these warehouses currently spend '
             || ROUND(:affirm_cpd, 3) || ' credits/day, and if Gen2 delivers NO '
             || 'speedup at all on them it adds about ' || ROUND(:worst_cpd, 3)
             || ' credits/day. That is the downside you are accepting. The upside is '
             || 'anything faster than ' || :breakeven_pct || '%.',
      'sql',    ARRAY_CONSTRUCT(
        :reg_gen,
        'BEGIN LET c CURSOR FOR SELECT WAREHOUSE_NAME FROM ' || :tgt
     || '.V_GEN2_VERDICT WHERE VERDICT IN (''STRONG'', ''LIKELY''); '
     || 'FOR r IN c DO '
     || 'EXECUTE IMMEDIATE ''ALTER WAREHOUSE "'' || r.WAREHOUSE_NAME '
     || '|| ''" SET GENERATION = ''''2''''''; '
     || 'END FOR; END'),
      'undo_sql', :undo_gen
    ));
  END IF;

  -- ── Query Acceleration, judged and offered separately ───────────────────────
  -- Deliberately NOT folded into GEN2_COHORT. QAS bills serverless credits of its
  -- own, so bundling it into the Gen2 consent would slip a second cost change past
  -- the client inside the first one -- which is the exact failure this solution
  -- exists to prevent on the Gen2 decision itself.
  --
  -- The registry entry records the PRIOR values so the undo restores them. Both
  -- clauses ride in ARGUMENTS because the shared teardown branch emits
  -- `ALTER WAREHOUSE <name> SET <ARTIFACT> = <ARGUMENTS>`, which is the same trick
  -- the Adaptive action uses to put back size and cluster counts in one statement.
  LET reg_qas STRING :=
      'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
   || '(TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) '
   || 'SELECT v.WAREHOUSE_NAME, ''ENABLE_QUERY_ACCELERATION'', '
   -- FALSE is the value being restored, and the prior scale factor goes back with
   -- it. Leaving the factor out would restore QAS-off but silently keep whatever
   -- factor this action set, which is a config change disguised as a rollback.
   || '''FALSE QUERY_ACCELERATION_MAX_SCALE_FACTOR = '' || '
   || 'GREATEST(COALESCE(v.QAS_SCALE_FACTOR, 8), 1), '
   || '''WAREHOUSE_SETTING'' FROM ' || :tgt || '.V_GEN2_VERDICT v '
   || 'WHERE v.QAS_VERDICT = ''RECOMMENDED'' '
   || 'AND NOT EXISTS (SELECT 1 FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY r '
   || 'WHERE r.TARGET_FQN = v.WAREHOUSE_NAME '
   || 'AND r.ARTIFACT = ''ENABLE_QUERY_ACCELERATION'')';

  LET undo_qas ARRAY := ARRAY_CONSTRUCT(
      'BEGIN LET c CURSOR FOR SELECT TARGET_FQN, ARGUMENTS FROM ' || :tgt
   || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ' || CHAR(39) || 'WAREHOUSE_SETTING'
   || CHAR(39) || ' AND ARTIFACT = ' || CHAR(39) || 'ENABLE_QUERY_ACCELERATION'
   || CHAR(39) || '; '
   || 'FOR r IN c DO '
   || 'EXECUTE IMMEDIATE ' || CHAR(39) || 'ALTER WAREHOUSE "' || CHAR(39)
   || ' || r.TARGET_FQN || ' || CHAR(39) || '" SET ENABLE_QUERY_ACCELERATION = '
   || CHAR(39) || ' || r.ARGUMENTS; '
   || 'END FOR; END',
      -- Same reasoning as the generation undo: leaving the rows behind makes the
      -- NOT EXISTS guard treat QAS-on as the original state, and the change becomes
      -- permanent without anyone choosing that.
      'DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
   || 'WHERE KIND = ' || CHAR(39) || 'WAREHOUSE_SETTING' || CHAR(39)
   || ' AND ARTIFACT = ' || CHAR(39) || 'ENABLE_QUERY_ACCELERATION' || CHAR(39));

  -- SAMPLE: prove the mechanism on the throwaway warehouse, not on theirs.
  IF (:sig:warehouses::STRING = 'AVAILABLE') THEN
    actions := ARRAY_APPEND(:actions, OBJECT_CONSTRUCT(
      'code',   'QAS_DEMO',
      'label',  'Turn Query Acceleration on for a throwaway warehouse, then put it back',
      'tier',   'SAMPLE',
      'effect', 'Sets ENABLE_QUERY_ACCELERATION = TRUE and '
             || 'QUERY_ACCELERATION_MAX_SCALE_FACTOR = 2 on ' || :demo_wh || ', the '
             || 'suspended warehouse this script created for its own demonstrations. '
             || 'None of your warehouses are touched.',
      'undo',   'Undo restores the recorded setting. TEARDOWN() drops the warehouse.',
      'est',    0.01,
      'basis',  'Two ALTER WAREHOUSE statements. ALTER is metadata-only and the '
             || 'warehouse is suspended throughout, so no QAS compute is ever '
             || 'requested and nothing bills.',
      'sql',    ARRAY_CONSTRUCT(
        'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
     || '(TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) SELECT ' || CHAR(39) || :demo_wh
     || CHAR(39) || ', ''ENABLE_QUERY_ACCELERATION'', ''FALSE'', ''WAREHOUSE_SETTING'' '
     || 'WHERE NOT EXISTS (SELECT 1 FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
     || 'WHERE TARGET_FQN = ' || CHAR(39) || :demo_wh || CHAR(39)
     || ' AND ARTIFACT = ''ENABLE_QUERY_ACCELERATION'')',
        'ALTER WAREHOUSE ' || :demo_wh || ' SET ENABLE_QUERY_ACCELERATION = TRUE '
     || 'QUERY_ACCELERATION_MAX_SCALE_FACTOR = 2'),
      'undo_sql', ARRAY_CONSTRUCT(
        'ALTER WAREHOUSE ' || :demo_wh || ' SET ENABLE_QUERY_ACCELERATION = FALSE',
        'DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE TARGET_FQN = '
     || CHAR(39) || :demo_wh || CHAR(39)
     || ' AND ARTIFACT = ''ENABLE_QUERY_ACCELERATION''')
    ));
  END IF;

  -- PRODUCTION: enable it where the account's own queries say it would engage.
  IF (:qas_n > 0) THEN
    actions := ARRAY_APPEND(:actions, OBJECT_CONSTRUCT(
      'code',   'QAS_ENABLE',
      'label',  'Enable Query Acceleration on the ' || :qas_n || ' warehouse(s) with eligible work',
      'tier',   'PRODUCTION',
      'effect', 'Sets ENABLE_QUERY_ACCELERATION = TRUE on every warehouse whose '
             || 'QAS_VERDICT is RECOMMENDED, at the scale factor in '
             || 'QAS_PROPOSED_SCALE_FACTOR -- capped at 2, which is what Snowflake '
             || 'itself uses when it enables QAS on a newly created Gen2 warehouse, '
             || 'and never above the ceiling Snowflake reported for that workload. '
             || 'Warehouses where none of the queries were eligible are left alone.',
      'undo',   'Reversible: Undo restores ENABLE_QUERY_ACCELERATION and the prior '
             || 'scale factor, and so does CALL ' || :tgt || '.TEARDOWN().',
      'est',    ROUND(0.01 * :qas_n, 3),
      'basis',  :qas_n || ' ALTER WAREHOUSE statements, metadata-only, ~'
             || ROUND(0.01 * :qas_n, 3) || ' credits to apply. What it costs after '
             || 'that is NOT metadata and NOT zero: QAS runs the offloaded work on '
             || 'separate serverless compute, billed on its own line. Snowflake '
             || 'marked ' || ROUND(:qas_secs, 0) || ' seconds of execution time '
             || 'across these warehouses as eligible in the last ' || :w || ' days, '
             || 'which is the work that would move to that line. So this is not a '
             || 'saving -- it is a wall-clock reduction on scan-heavy work, bought '
             || 'with QAS credits. It earns its place here because that same '
             || 'wall-clock reduction is what the Gen2 rate premium needs in order '
             || 'to pay for itself. Watch the QUERY_ACCELERATION_HISTORY view and '
             || 'the credits line after you press it.',
      'sql',    ARRAY_CONSTRUCT(
        :reg_qas,
        'BEGIN LET c CURSOR FOR SELECT WAREHOUSE_NAME, QAS_PROPOSED_SCALE_FACTOR '
     || 'FROM ' || :tgt || '.V_GEN2_VERDICT WHERE QAS_VERDICT = ''RECOMMENDED''; '
     || 'FOR r IN c DO '
     || 'EXECUTE IMMEDIATE ''ALTER WAREHOUSE "'' || r.WAREHOUSE_NAME '
     || '|| ''" SET ENABLE_QUERY_ACCELERATION = TRUE '
     || 'QUERY_ACCELERATION_MAX_SCALE_FACTOR = '' || r.QAS_PROPOSED_SCALE_FACTOR; '
     || 'END FOR; END'),
      'undo_sql', :undo_qas
    ));
  END IF;

  -- ── LIMITED: one Adaptive pilot ─────────────────────────────────────────────
  -- Adaptive nulls the size, the cluster counts and the suspend policy when it
  -- converts, so the undo has to put all of them back explicitly -- verified by
  -- round-tripping a warehouse before this was written. The restore clause is
  -- carried in ARGUMENTS so the shared teardown branch, which emits
  -- `ALTER WAREHOUSE <name> SET <ARTIFACT> = <ARGUMENTS>`, reconstructs the whole
  -- statement without needing a special case.
  IF (:adapt_wh <> '') THEN
    LET adapt_restore STRING := '';
    BEGIN
      EXECUTE IMMEDIATE 'SHOW WAREHOUSES LIKE ''' || :adapt_wh || '''';
      SELECT CHAR(39) || 'STANDARD' || CHAR(39)
          || ' WAREHOUSE_SIZE = ' || REPLACE(UPPER("size"), '-', '')
          || ' GENERATION = ' || CHAR(39) || COALESCE(NULLIF("generation", ''), '1') || CHAR(39)
          || ' AUTO_SUSPEND = ' || COALESCE("auto_suspend"::VARCHAR, '60')
        INTO :adapt_restore
      FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    EXCEPTION WHEN OTHER THEN
      adapt_restore := '';
    END;

    -- No restore clause means no honest undo, so the action is not offered. A
    -- button whose undo is a guess is worse than no button.
    IF (:adapt_restore <> '') THEN
      actions := ARRAY_APPEND(:actions, OBJECT_CONSTRUCT(
        'code',   'ADAPTIVE_PILOT',
        'label',  'Pilot an Adaptive Warehouse on ' || :adapt_wh,
        'tier',   'LIMITED',
        'effect', 'Converts ' || :adapt_wh || ' to an Adaptive Warehouse. Snowflake '
               || 'then owns its size, cluster count, Query Acceleration and suspend '
               || 'policy, and bills per query instead of per warehouse-second. '
               || 'Requires Enterprise Edition or higher and a supported region -- '
               || 'this account reports ' || COALESCE(:sig:edition_hint::STRING, 'UNKNOWN')
               || ', which is inferred rather than read, so the ALTER is the real '
               || 'test and will refuse clearly if unsupported. No downtime.',
        'undo',   'Reversible, and verified by round-trip: Undo restores type '
               || 'STANDARD with the size, generation and auto-suspend recorded '
               || 'before the change (' || :adapt_restore || ').',
        'est',    0.01,
        'basis',  'One ALTER WAREHOUSE, metadata-only. What happens to cost after '
               || 'that cannot be projected -- Adaptive bills per query, so the only '
               || 'honest answer is the before-and-after in V_CONVERSION_OUTCOME. '
               || :adapt_wh || ' currently spends what CONVERSION_BASELINE recorded '
               || 'for it.',
        'sql',    ARRAY_CONSTRUCT(
          'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
       || '(TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) SELECT ' || CHAR(39) || :adapt_wh
       || CHAR(39) || ', ' || CHAR(39) || 'WAREHOUSE_TYPE' || CHAR(39) || ', '
       || CHAR(39) || :adapt_restore || CHAR(39) || ', '
       || CHAR(39) || 'WAREHOUSE_SETTING' || CHAR(39)
       || ' WHERE NOT EXISTS (SELECT 1 FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
       || 'WHERE TARGET_FQN = ' || CHAR(39) || :adapt_wh || CHAR(39)
       || ' AND ARTIFACT = ' || CHAR(39) || 'WAREHOUSE_TYPE' || CHAR(39) || ')',
          'ALTER WAREHOUSE "' || :adapt_wh || '" SET WAREHOUSE_TYPE = ''ADAPTIVE'''),
        'undo_sql', ARRAY_CONSTRUCT(
          'ALTER WAREHOUSE "' || :adapt_wh || '" SET WAREHOUSE_TYPE = ' || :adapt_restore,
          'DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE TARGET_FQN = '
       || CHAR(39) || :adapt_wh || CHAR(39) || ' AND ARTIFACT = '
       || CHAR(39) || 'WAREHOUSE_TYPE' || CHAR(39))
      ));
    END IF;
  END IF;

  -- ── The named-list ALTER path ───────────────────────────────────────────────
  -- WHGEN_WAREHOUSES names warehouses this build may convert directly, by name,
  -- regardless of verdict -- because naming a warehouse in the settings block is
  -- an explicit instruction and it is not this script's place to overrule it.
  -- Blank means nothing is altered, which is the shipped default.
  --
  -- This has to exist as a real code path rather than only as buttons. It is how
  -- the test harness exercises an actual conversion: without it, the single most
  -- important statement in the solution is one no test ever runs, which is exactly
  -- how the equivalent path in 11_cost_efficiency stayed unexercised while every
  -- check reported green.
  LET wh_list STRING := '';
  BEGIN
    wh_list := COALESCE((SELECT NULLIF($WHGEN_WAREHOUSES::VARCHAR, '')), '');
  EXCEPTION WHEN OTHER THEN
    wh_list := '';
  END;

  IF (:wh_list <> '' AND :sig:warehouses::STRING = 'AVAILABLE') THEN
    -- Record the prior generation first, or the change is not reversible. Only
    -- STANDARD warehouses at a Gen2-eligible size are touched even when named:
    -- an ALTER that Snowflake will refuse is not worth attempting, and silently
    -- skipping it is better than failing the build on a name someone mistyped.
    stmts := ARRAY_APPEND(:stmts,
      'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
   || '(TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) '
   || 'SELECT f.WAREHOUSE_NAME, ''GENERATION'', CHAR(39) || ''1'' || CHAR(39), '
   || '''WAREHOUSE_SETTING'' FROM ' || :tgt || '.WH_FLEET f '
   || 'WHERE COALESCE(f.GENERATION, '''') NOT IN (''2'') '
   || 'AND f.WH_TYPE = ''STANDARD'' '
   || 'AND UPPER(REPLACE(f.WH_SIZE, ''-'', '''')) NOT IN (''5XLARGE'', ''6XLARGE'') '
   || 'AND f.WAREHOUSE_NAME IN (SELECT TRIM(VALUE) FROM TABLE(SPLIT_TO_TABLE('''
   || :wh_list || ''', '','')))'
   || ' AND NOT EXISTS (SELECT 1 FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY r '
   || 'WHERE r.TARGET_FQN = f.WAREHOUSE_NAME AND r.ARTIFACT = ''GENERATION'')');

    stmts := ARRAY_APPEND(:stmts,
      'BEGIN '
   || 'LET cur CURSOR FOR SELECT WAREHOUSE_NAME FROM ' || :tgt || '.WH_FLEET '
   || 'WHERE COALESCE(GENERATION, '''') NOT IN (''2'') '
   || 'AND WH_TYPE = ''STANDARD'' '
   || 'AND UPPER(REPLACE(WH_SIZE, ''-'', '''')) NOT IN (''5XLARGE'', ''6XLARGE'') '
   || 'AND WAREHOUSE_NAME IN (SELECT TRIM(VALUE) FROM TABLE(SPLIT_TO_TABLE('''
   || :wh_list || ''', '',''))); '
   || 'FOR rec IN cur DO '
   || 'EXECUTE IMMEDIATE ''ALTER WAREHOUSE "'' || rec.WAREHOUSE_NAME '
   || '|| ''" SET GENERATION = ''''2''''''; '
   || 'END FOR; END');

    cost_once := :cost_once + 0.02;
    cost_detail := ARRAY_APPEND(:cost_detail,
      'ALTER WAREHOUSE for the names in WHGEN_WAREHOUSES ~0.02 credits one-time. '
   || 'Metadata-only; what it changes is the RATE the workload bills at afterwards.');
    dials := ARRAY_APPEND(:dials,
      'Clear WHGEN_WAREHOUSES to convert nothing during the build and use the '
   || 'buttons instead');
  END IF;

  -- ── The named-list QAS path ─────────────────────────────────────────────────
  -- Same reasoning as the block above, for the same reason, and it is needed more
  -- here: QAS_VERDICT reaches RECOMMENDED only when Snowflake has marked real
  -- queries eligible, which a fresh sandbox never has. Without this list the QAS
  -- ALTER is unreachable by any test, and an untested ALTER that ships is how the
  -- 11_cost_efficiency defect happened.
  --
  -- The prior value is recorded before the change, exactly as the button does, so
  -- the same undo and the same TEARDOWN branch restore it.
  LET qas_list STRING := '';
  BEGIN
    qas_list := COALESCE((SELECT NULLIF($WHGEN_QAS_WAREHOUSES::VARCHAR, '')), '');
  EXCEPTION WHEN OTHER THEN
    qas_list := '';
  END;

  IF (:qas_list <> '' AND :sig:warehouses::STRING = 'AVAILABLE') THEN
    stmts := ARRAY_APPEND(:stmts,
      'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY '
   || '(TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) '
   || 'SELECT f.WAREHOUSE_NAME, ''ENABLE_QUERY_ACCELERATION'', '
   || '''FALSE QUERY_ACCELERATION_MAX_SCALE_FACTOR = '' || '
   || 'GREATEST(COALESCE(f.QAS_SCALE_FACTOR, 8), 1), '
   || '''WAREHOUSE_SETTING'' FROM ' || :tgt || '.WH_FLEET f '
   -- Only STANDARD warehouses: on an Adaptive warehouse the type governs
   -- acceleration and the ALTER would be refused or meaningless.
   || 'WHERE f.WH_TYPE = ''STANDARD'' '
   || 'AND LOWER(COALESCE(f.QAS_ENABLED, ''false'')) NOT IN (''true'', ''t'', ''1'') '
   || 'AND f.WAREHOUSE_NAME IN (SELECT TRIM(VALUE) FROM TABLE(SPLIT_TO_TABLE('''
   || :qas_list || ''', '','')))'
   || ' AND NOT EXISTS (SELECT 1 FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY r '
   || 'WHERE r.TARGET_FQN = f.WAREHOUSE_NAME '
   || 'AND r.ARTIFACT = ''ENABLE_QUERY_ACCELERATION'')');

    stmts := ARRAY_APPEND(:stmts,
      'BEGIN '
   || 'LET cur CURSOR FOR SELECT WAREHOUSE_NAME FROM ' || :tgt || '.WH_FLEET '
   || 'WHERE WH_TYPE = ''STANDARD'' '
   || 'AND LOWER(COALESCE(QAS_ENABLED, ''false'')) NOT IN (''true'', ''t'', ''1'') '
   || 'AND WAREHOUSE_NAME IN (SELECT TRIM(VALUE) FROM TABLE(SPLIT_TO_TABLE('''
   || :qas_list || ''', '',''))); '
   || 'FOR rec IN cur DO '
   || 'EXECUTE IMMEDIATE ''ALTER WAREHOUSE "'' || rec.WAREHOUSE_NAME '
   || '|| ''" SET ENABLE_QUERY_ACCELERATION = TRUE '
   || 'QUERY_ACCELERATION_MAX_SCALE_FACTOR = 2''; '
   || 'END FOR; END');

    cost_once := :cost_once + 0.02;
    cost_detail := ARRAY_APPEND(:cost_detail,
      'ALTER WAREHOUSE for the names in WHGEN_QAS_WAREHOUSES ~0.02 credits '
   || 'one-time. Metadata-only, but unlike the Gen2 ALTER this one opens a SECOND '
   || 'billing line: from here on, eligible queries on those warehouses consume '
   || 'serverless QAS credits on top of the warehouse credits. Scale factor 2 caps '
   || 'how much.');
    dials := ARRAY_APPEND(:dials,
      'Clear WHGEN_QAS_WAREHOUSES to change no acceleration setting during the '
   || 'build and use the buttons instead');
  END IF;

  -- ══════════════════════════════════════════════════════════════════════════
  -- STANDING WORKLOAD — TASK_GEN2_WATCH
  -- ══════════════════════════════════════════════════════════════════════════
  -- Gen2 costs more per second. A conversion that does not speed the workload up
  -- raises the bill quietly and forever, and nobody goes back to check: the ALTER
  -- succeeded, so it looks done. This task is the check.

  -- Credit rate read off the actual app warehouse, never assumed. The 4x error
  -- this repo has already shipped once came from assuming X-Small.
  LET gw_size    STRING := 'UNKNOWN';
  LET gw_cph     NUMBER(38,2) := 1.0;
  LET gw_rate_ok BOOLEAN := FALSE;
  BEGIN
    EXECUTE IMMEDIATE 'SHOW WAREHOUSES LIKE ''' || :wh || '''';
    gw_size := (SELECT UPPER(COALESCE(MAX("size"), 'UNKNOWN'))
                FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    gw_cph := CASE REPLACE(:gw_size, '-', '')
        WHEN 'XSMALL' THEN 1   WHEN 'SMALL'  THEN 2
        WHEN 'MEDIUM' THEN 4   WHEN 'LARGE'  THEN 8
        WHEN 'XLARGE' THEN 16  WHEN '2XLARGE' THEN 32
        WHEN '3XLARGE' THEN 64 WHEN '4XLARGE' THEN 128
        WHEN '5XLARGE' THEN 256 WHEN '6XLARGE' THEN 512
        ELSE 1 END;
    gw_rate_ok := (:gw_cph > 1 OR REPLACE(:gw_size, '-', '') = 'XSMALL');
  EXCEPTION WHEN OTHER THEN
    gw_size := 'UNREADABLE'; gw_cph := 1.0; gw_rate_ok := FALSE;
  END;

  LET gw_task_fqn STRING := :tgt || '.TASK_GEN2_WATCH';

  -- A table rather than a view, because the point is to keep a HISTORY of the
  -- verdict on each conversion. A view would only ever show today's answer, and
  -- "it was fine last week" is the observation that identifies a regression.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE TABLE IF NOT EXISTS ' || :tgt || '.CONVERSION_WATCH_LOG ('
 || 'CHECKED_AT TIMESTAMP_NTZ, WAREHOUSE_NAME VARCHAR, CHANGED_AT TIMESTAMP_NTZ, '
 || 'DAYS_OBSERVED NUMBER(38,0), '
 || 'BEFORE_CREDITS_PER_DAY NUMBER(38,4), AFTER_CREDITS_PER_DAY NUMBER(38,4), '
 || 'OBSERVED_DELTA_CREDITS_PER_DAY NUMBER(38,4), '
 || 'OBSERVED_SPEEDUP_PCT NUMBER(38,2), REQUIRED_SPEEDUP_PCT NUMBER(38,2), '
 || 'OUTCOME VARCHAR, LABEL VARCHAR, BASIS VARCHAR)');

  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE PROCEDURE ' || :tgt || '.GEN2_WATCH() '
 || 'RETURNS VARCHAR LANGUAGE SQL AS BEGIN '
 || 'INSERT INTO ' || :tgt || '.CONVERSION_WATCH_LOG '
 || '(CHECKED_AT, WAREHOUSE_NAME, CHANGED_AT, DAYS_OBSERVED, '
 || ' BEFORE_CREDITS_PER_DAY, AFTER_CREDITS_PER_DAY, OBSERVED_DELTA_CREDITS_PER_DAY, '
 || ' OBSERVED_SPEEDUP_PCT, REQUIRED_SPEEDUP_PCT, OUTCOME, LABEL, BASIS) '
 || 'SELECT CURRENT_TIMESTAMP(), WAREHOUSE_NAME, CHANGED_AT, DAYS_OBSERVED, '
 || 'BEFORE_CREDITS_PER_DAY, AFTER_CREDITS_PER_DAY, OBSERVED_DELTA_CREDITS_PER_DAY, '
 || 'OBSERVED_SPEEDUP_PCT, REQUIRED_SPEEDUP_PCT, OUTCOME, LABEL, BASIS '
 || 'FROM ' || :tgt || '.V_CONVERSION_OUTCOME; '
 || 'RETURN ''GEN2_WATCH COMPLETE''; END');

  -- The rollback list. This is the output a client team would not build for
  -- itself, and it is the only thing in the solution that names a conversion as
  -- a mistake.
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE VIEW ' || :tgt || '.V_ROLLBACK_CANDIDATES AS '
 || 'SELECT WAREHOUSE_NAME, CHANGED_AT, DAYS_OBSERVED, '
 || 'BEFORE_CREDITS_PER_DAY, AFTER_CREDITS_PER_DAY, '
 || 'OBSERVED_DELTA_CREDITS_PER_DAY, OBSERVED_SPEEDUP_PCT, REQUIRED_SPEEDUP_PCT, '
 || 'ROUND(OBSERVED_DELTA_CREDITS_PER_DAY * 365, 1) AS ANNUALISED_DELTA_CREDITS, '
 || CHAR(39) || 'Converting this warehouse did not pay for the rate premium. '
 || 'ALTER WAREHOUSE <name> SET GENERATION = ' || CHAR(39) || CHAR(39) || '1'
 || CHAR(39) || CHAR(39) || ' puts it back, or press Undo on the action that '
 || 'converted it.' || CHAR(39) || ' AS WHAT_TO_DO, '
 || 'LABEL, BASIS '
 || 'FROM ' || :tgt || '.V_CONVERSION_OUTCOME '
 || 'WHERE OUTCOME = ''COSTING_MORE'' '
 || 'ORDER BY OBSERVED_DELTA_CREDITS_PER_DAY DESC');
  cost_day    := :cost_day + 0.01;
  cost_detail := ARRAY_APPEND(:cost_detail,
    'V_ROLLBACK_CANDIDATES reads V_CONVERSION_OUTCOME ~0.01 credits/day');

  stmts := ARRAY_APPEND(:stmts,
    'DELETE FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY WHERE KIND = ''TASK''');
  stmts := ARRAY_APPEND(:stmts,
    'INSERT INTO ' || :tgt || '.ATTACHED_OBJECT_REGISTRY (TARGET_FQN, ARTIFACT, ARGUMENTS, KIND) '
 || 'SELECT ''' || :gw_task_fqn || ''', ''TASK_GEN2_WATCH'', '
 || '''USING CRON 0 7 * * 1 UTC'', ''TASK''');

  -- SUSPEND before replacing. Snowflake refuses to CREATE OR REPLACE a started
  -- task, and at PRODUCTION tier the previous build deliberately leaves this one
  -- running -- so a re-run would hit that refusal on a script whose whole promise
  -- is that it can be re-run.
  stmts := ARRAY_APPEND(:stmts, 'ALTER TASK IF EXISTS ' || :gw_task_fqn || ' SUSPEND');
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE TASK ' || :gw_task_fqn || ' WAREHOUSE = ' || :wh
 || ' SCHEDULE = ''USING CRON 0 7 * * 1 UTC'''
 || ' COMMENT = ''Re-measures every warehouse this solution converted against its '
 || 'pre-change baseline, and records any that are now costing more.'''
 || ' AS CALL ' || :tgt || '.GEN2_WATCH()');
  stmts := ARRAY_APPEND(:stmts, 'ALTER TASK ' || :gw_task_fqn || ' RESUME');

  -- PRODUCTION tier is the consent. Below it the task exists and is suspended, and
  -- the run rate below says so rather than reporting a charge for something this
  -- build just switched off.
  LET standing_live BOOLEAN := (:tier = 'PRODUCTION');
  LET runs_per_month NUMBER(38,4) := IFF(:standing_live, 4.34, 0);
  LET cadence_label STRING := 'weekly on Monday at 07:00 UTC'
    || IFF(:standing_live, '', ', SUSPENDED at ' || :tier || ' tier');
  LET gate_basis STRING := IFF(:standing_live,
      'Left RUNNING because this build is PRODUCTION tier — this is a charge you will see.',
      'SUSPENDED by this build because the tier is ' || :tier || ', not PRODUCTION. '
        || 'At PRODUCTION the same task would fire 4.34 times a month.');

  IF (NOT :standing_live) THEN
    stmts := ARRAY_APPEND(:stmts, 'ALTER TASK ' || :gw_task_fqn || ' SUSPEND');
  END IF;

  -- Floor the measurement at this build's start, or a re-run into the same schema
  -- averages in the previous run's calls: a true history of the statement, a false
  -- history of the object being priced.
  LET build_floor_utc STRING := (
    SELECT TO_CHAR(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP()),
                   'YYYY-MM-DD HH24:MI:SS.FF3'));
  stmts := ARRAY_APPEND(:stmts,
    'CREATE OR REPLACE TABLE ' || :tgt || '.GEN2WATCH_RUN_COST '
 || 'COMMENT = ''Measured elapsed time of GEN2_WATCH(), the body of TASK_GEN2_WATCH.'' AS '
 || 'SELECT COUNT(*) AS RUNS_OBSERVED, '
 || 'ROUND(AVG(TOTAL_ELAPSED_TIME) / 1000.0, 3) AS AVG_SECONDS '
 -- Qualified with the target DATABASE on purpose: an unqualified
 -- INFORMATION_SCHEMA resolves against whatever database the session happens to
 -- be in, which is not guaranteed on a re-run.
 || 'FROM TABLE(' || :db || '.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION('
 || 'RESULT_LIMIT => 10000)) '
 || 'WHERE QUERY_TYPE = ''CALL'' AND EXECUTION_STATUS = ''SUCCESS'' '
 || 'AND QUERY_TEXT ILIKE ''%' || :tgt || '.GEN2_WATCH()%'' '
 || 'AND CONVERT_TIMEZONE(''UTC'', START_TIME)::TIMESTAMP_NTZ >= '''
 || :build_floor_utc || '''::TIMESTAMP_NTZ');

  -- The build calls the procedure once so SECONDS_PER_RUN is measured rather than
  -- guessed. The task body IS this call, so timing it is honest and it also proves
  -- the procedure runs before anything schedules it.
  stmts := ARRAY_APPEND(:stmts, 'CALL ' || :tgt || '.GEN2_WATCH()');

  stmts := ARRAY_APPEND(:stmts,
    'INSERT INTO ' || :tgt || '.STANDING_WORKLOAD '
 || '(KIND, OBJECT_NAME, CADENCE, RUNS_PER_MONTH, SECONDS_PER_RUN, '
 || ' WAREHOUSE_CREDITS_PER_HOUR, MEASURED_INPUT, BASIS, INSTALLED_AT) '
 || 'SELECT ''TASK'', ''TASK_GEN2_WATCH'', '
 || '  ''' || :cadence_label || ''', '
 || '  ' || :runs_per_month || ', '
 || '  COALESCE(r.AVG_SECONDS, 1.0), '
 || '  ' || :gw_cph || ', '
 || '  CASE WHEN r.AVG_SECONDS IS NOT NULL '
 || '    THEN ''TOTAL_ELAPSED_TIME averaged over '' || r.RUNS_OBSERVED '
 || '      || '' GEN2_WATCH() call(s) this build made; the task body is that exact call'' '
 || '    ELSE ''no GEN2_WATCH() call was readable in this session''''s query history, '
 || 'so this uses the 1-warehouse-second floor stated in the plan'' END, '
 || '  ''CRON 0 7 * * 1 UTC = weekly = 4.34 runs/month, times measured seconds per '
 || 'run, at ' || :gw_cph || ' credits/hour ('
 || IFF(:gw_rate_ok, :wh || ' is ' || :gw_size,
        'size of ' || :wh || ' unreadable, so 1 credit/hour is a LOWER bound')
 || '). ' || :gate_basis || ''', '
 || '  CURRENT_TIMESTAMP() '
 || 'FROM ' || :tgt || '.GEN2WATCH_RUN_COST r');
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
-- The honest shape for a generation-change solution, and it is deliberately not
-- the shape a cost solution usually takes.
--
-- There is no "credits saved" line here, and there cannot be one before a
-- conversion happens. Gen2 costs MORE per second; whether that turns into a
-- saving depends on how much faster the workload finishes, which is a property of
-- the workload and is unknown until it runs on Gen2. Any percentage put here
-- would be ours rather than theirs, and it would be the single most quotable
-- number on the page.
--
-- So the base is the spend EXPOSED to the decision -- a fact -- and the value
-- line is explicitly two-sided: the same base times a speedup the client
-- supplies, against the rate premium they are certain to pay.

value_inputs := ARRAY_APPEND(:value_inputs, OBJECT_CONSTRUCT(
  'name', 'expected_speedup',
  'value', 0, 'default', 0, 'units', 'fraction of runtime removed',
  'description', 'How much faster you expect the affirmative warehouses to finish '
              || 'on Gen2, as a fraction -- 0.30 means 30% faster. The default is '
              || 'ZERO on purpose: nobody knows this number before the pilot, and a '
              || 'friendly default here would be the one figure everyone quoted. '
              || 'Run the pilot, read OBSERVED_SPEEDUP_PCT, put that number here.'));
value_inputs := ARRAY_APPEND(:value_inputs, OBJECT_CONSTRUCT(
  'name', 'credit_price',
  'value', 3, 'default', 3, 'units', 'currency per credit',
  'description', 'Your contracted price per credit. The 3 is list-price shorthand '
              || 'and is almost certainly not your rate; it is on your contract.'));
value_inputs := ARRAY_APPEND(:value_inputs, OBJECT_CONSTRUCT(
  'name', 'days_per_year',
  'value', 365, 'default', 365, 'units', 'days',
  'description', 'Annualisation factor. Lower it if the affirmative warehouses only '
              || 'run on business days.'));

-- Measured at BUILD time from the view this solution just created, so the number
-- is this account's own consumption rather than an assumption.
value_base := ARRAY_APPEND(:value_base, OBJECT_CONSTRUCT(
  'metric', 'exposed_credits_per_day',
  'units', 'credits/day',
  'sql', 'SELECT ROUND(COALESCE(SUM(CREDITS_PER_DAY), 0), 4) FROM ' || :tgt
      || '.V_GEN2_VERDICT WHERE VERDICT IN (''STRONG'', ''LIKELY'')',
  'derivation', 'Current credits per day on the warehouses whose verdict is STRONG '
             || 'or LIKELY, read from ACCOUNT_USAGE metering over the discovery '
             || 'window. This is the spend the decision applies to -- not a saving, '
             || 'and not a projection.'));

-- The certain cost. This is the only side of the trade that can be computed in
-- advance, and it is a cost rather than a benefit, which is why it is stated as
-- its own base metric rather than netted into the line above.
value_base := ARRAY_APPEND(:value_base, OBJECT_CONSTRUCT(
  'metric', 'rate_premium_credits_per_day',
  'units', 'credits/day',
  'sql', 'SELECT ROUND(COALESCE(SUM(WORST_CASE_EXTRA_CREDITS_PER_DAY), 0), 4) FROM '
      || :tgt || '.V_GEN2_VERDICT WHERE VERDICT IN (''STRONG'', ''LIKELY'')',
  'derivation', 'The affirmative warehouses'' current credits/day times '
             || '(multiplier - 1). This is what converting them costs if the '
             || 'workload does not get any faster, and it is the downside of the '
             || 'decision expressed in credits rather than in adjectives.'));

-- Declared UNMEASURABLE before the pilot, and it is the more important of the
-- three. The whole point of the solution is that this cannot be known in advance.
value_base := ARRAY_APPEND(:value_base, OBJECT_CONSTRUCT(
  'metric', 'realised_speedup',
  'units', 'percent of runtime removed',
  'measurable', FALSE,
  'derivation', 'Would come from comparing seconds-per-query on the same warehouse '
             || 'before and after conversion.',
  'why_not', 'No Gen2 measurement exists for a warehouse that has never run on '
          || 'Gen2. Snowflake publishes no fixed improvement percentage because the '
          || 'answer depends on the query mix, and this solution refuses to supply '
          || 'one. CONVERSION_BASELINE holds the before-picture and '
          || 'V_CONVERSION_OUTCOME fills this in once a conversion has been live for '
          || 'at least three days.'));

value_lines := ARRAY_APPEND(:value_lines, OBJECT_CONSTRUCT(
  'line', 'Compute reclaimed if the speedup you entered is real',
  'base_metric', 'exposed_credits_per_day',
  'rate_input', 'expected_speedup',
  'value_input', 'credit_price',
  -- The base is per DAY, so without this the annual figure is a daily one and the
  -- comparison against the premium below is out by 365.
  'annualise_input', 'days_per_year',
  'horizon', 'per year, at your credit price'));
value_lines := ARRAY_APPEND(:value_lines, OBJECT_CONSTRUCT(
  'line', 'Rate premium you pay regardless',
  'base_metric', 'rate_premium_credits_per_day',
  'value_input', 'credit_price',
  'annualise_input', 'days_per_year',
  'horizon', 'per year, at your credit price'));
value_lines := ARRAY_APPEND(:value_lines, OBJECT_CONSTRUCT(
  'line', 'Speedup actually achieved',
  'base_metric', 'realised_speedup',
  'value_input', 'credit_price',
  'annualise_input', 'days_per_year',
  'horizon', 'unmeasurable until a conversion has been live'));

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
-- What would make this a success, measured against bars derived from THIS account.
--
-- EVERY CRITERION IS GATED ON THE SIGNAL IT READS, because a criterion scored
-- against a view that was never built is worse than no criterion.
--
-- WHAT IS DELIBERATELY NOT HERE: there is no "N credits saved" criterion. Gen2
-- costs more per second, so a saving is not available in advance at any confidence
-- and claiming one as a success bar would make the bar itself the fabrication.

-- ── Coverage: every warehouse in the fleet gets a verdict ─────────────────────
IF (:sig:warehouses::STRING = 'AVAILABLE' AND :sig:credit_history::STRING = 'AVAILABLE') THEN
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'WHGEN_FLEET_COVERED',
    'label', 'Every warehouse in the fleet receives a Gen2 verdict',
    'why', 'A verdict list that silently drops warehouses understates the estate, and '
        || 'the one it drops is as likely to be the biggest spender as the smallest. '
        || 'If the join between the fleet snapshot and the workload metrics loses '
        || 'rows, this fails.',
    'compare', '=',
    'units', 'warehouses',
    'basis', 'BY_QUERY_ID',
    'target_sql', 'SELECT COUNT(*) FROM ' || :tgt || '.WH_FLEET',
    'actual_sql', 'SELECT COUNT(*) FROM ' || :tgt || '.V_GEN2_VERDICT',
    'target_derivation', 'The row count of WH_FLEET, a snapshot of SHOW WAREHOUSES '
        || 'taken at build time. Equality: every warehouse appears, including the ones '
        || 'whose verdict is ALREADY_GEN2 or INELIGIBLE.'));

  -- ── The button and the table must agree ────────────────────────────────────
  -- The verdict is computed twice: once at plan time so the buttons can name real
  -- warehouses before anything exists, and once in the view. If those two
  -- disagree, the reader is looking at one number and pressing another, and both
  -- lose credibility at once. This is the criterion that catches drift between
  -- them.
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'WHGEN_PLAN_MATCHES_VIEW',
    'label', 'The count on the conversion button matches the count in the verdict view',
    'why', 'The plan recomputes the verdict before the views exist, so the button can '
        || 'name real warehouses. Two implementations of one rule drift. If the button '
        || 'offers to convert nine warehouses and the table shows seven, the reader '
        || 'stops trusting the page -- correctly.',
    'compare', '=',
    'units', 'affirmative warehouses',
    'basis', 'BY_QUERY_ID',
    'target_sql', 'SELECT ' || :affirm_n,
    'actual_sql', 'SELECT COUNT(*) FROM ' || :tgt || '.V_GEN2_VERDICT '
        || 'WHERE VERDICT IN (''STRONG'', ''LIKELY'')',
    'target_derivation', 'The affirmative count the plan computed at plan time, which '
        || 'is the number printed on the PRODUCTION button: ' || :affirm_n || '.'));

  -- ── Every verdict is grounded in measured inputs ───────────────────────────
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'WHGEN_VERDICTS_GROUNDED',
    'label', 'No warehouse is recommended for conversion without measured workload evidence',
    'why', 'A Gen2 recommendation with no utilisation and no favourable-share behind '
        || 'it is the naive "convert every Gen1 warehouse" recommendation wearing a '
        || 'verdict column, and on an idle-heavy warehouse it raises the bill. This '
        || 'checks that every affirmative verdict has both signals present.',
    'compare', '=',
    'units', 'ungrounded affirmative verdicts',
    'basis', 'BY_QUERY_ID',
    'target_sql', 'SELECT 0',
    'actual_sql', 'SELECT COUNT(*) FROM ' || :tgt || '.V_GEN2_VERDICT '
        || 'WHERE VERDICT IN (''STRONG'', ''LIKELY'') '
        || 'AND (UTILISATION IS NULL OR FAVOURABLE_SHARE IS NULL '
        || 'OR QUERY_COUNT = 0)',
    'target_derivation', 'Zero. An affirmative verdict on a warehouse with no query '
        || 'history is not a verdict, it is a guess.'));
END IF;

-- ── The baseline exists before any conversion ────────────────────────────────
IF (:sig:credit_history::STRING = 'AVAILABLE') THEN
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'WHGEN_BASELINE_BEFORE_CHANGE',
    'label', 'Every converted warehouse has a baseline captured before it was converted',
    'why', 'This is the criterion the whole solution rests on. A conversion with no '
        || 'before-picture can never be evaluated, and what fills that vacuum is '
        || 'someone saying it feels faster. If a warehouse appears in the change '
        || 'registry with no baseline row, the outcome view cannot score it.',
    'compare', '=',
    'units', 'conversions missing a baseline',
    'basis', 'BY_QUERY_ID',
    'target_sql', 'SELECT 0',
    'actual_sql', 'SELECT COUNT(*) FROM ' || :tgt || '.ATTACHED_OBJECT_REGISTRY r '
        || 'WHERE r.KIND = ''WAREHOUSE_SETTING'' '
        || 'AND NOT EXISTS (SELECT 1 FROM ' || :tgt || '.CONVERSION_BASELINE b '
        || 'WHERE b.WAREHOUSE_NAME = r.TARGET_FQN)',
    'target_derivation', 'Zero. Every row in the registry recording a warehouse '
        || 'setting change must have a matching CONVERSION_BASELINE row.'));

  -- ── The outcome: pending on purpose, and it says why ──────────────────────
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'WHGEN_SPEEDUP_BEATS_BREAKEVEN',
    'label', 'Converted warehouses achieved more than the ' || :breakeven_pct
        || '% speedup Gen2 needs to pay for itself',
    'why', 'This is the only success criterion that matters, and it cannot be scored '
        || 'until a conversion has been live long enough to measure. Everything else '
        || 'in this solution is setup for this one number.',
    'compare', '>=',
    'units', 'percent of runtime removed',
    'basis', 'BY_TIME_WINDOW',
    'target_sql', 'SELECT ' || :breakeven_pct,
    'actual_sql', 'SELECT ROUND(AVG(OBSERVED_SPEEDUP_PCT), 2) FROM ' || :tgt
        || '.V_CONVERSION_OUTCOME WHERE OUTCOME <> ''TOO_EARLY''',
    'target_derivation', 'The break-even bar for this account''s cloud: '
        || :breakeven_pct || '%, which is (1 - 1/' || :mult || ') expressed as a '
        || 'percentage. Not a benchmark and not a target Snowflake published -- it is '
        || 'the point at which the rate premium is exactly paid for.',
    'pending_reason', 'No conversion has been live for three days yet, so every row '
        || 'in the outcome view reads TOO_EARLY and the average is over an empty set. '
        || 'That is an absence of data, not a speedup of zero and not a failure.',
    'resolves_when', 'Press the pilot action, wait at least three days for metering '
        || 'and query history to accumulate on the converted warehouse, then re-read '
        || 'V_CONVERSION_OUTCOME. TASK_GEN2_WATCH does this weekly on its own at '
        || 'PRODUCTION tier.'));
END IF;

-- ── Cost ──────────────────────────────────────────────────────────────────────
IF (:credit_cap > 0) THEN
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'WHGEN_COST_IN_BUDGET',
    'label', 'Measured steady-state cost stays inside your credit cap',
    'why', 'A POC that cannot state its own running cost cannot be approved for '
        || 'production, and a projection is not a measurement.',
    'compare', '<=',
    'units', 'credits',
    'basis', 'BY_TAG',
    'target_sql', 'SELECT ' || :credit_cap,
    'actual_sql', 'SELECT SUM(CREDITS) FROM ' || :tgt || '.V_COST_LINES '
        || 'WHERE LABEL = ''MEASURED'' AND STATUS = ''LANDED''',
    'target_derivation', 'Your WHGEN_CREDIT_CAP setting, currently '
        || :credit_cap || ' credits.',
    'pending_reason', 'Warehouse credits reach ACCOUNT_USAGE on a delay, so nothing '
        || 'has been attributed to this run yet. This is an absence of data, not a '
        || 'cost of zero.',
    'resolves_when', 'credits land in ACCOUNT_USAGE, typically within 8 hours -- call '
        || 'MEASURE() in this schema after that to fill it in'));
ELSE
  success_criteria := ARRAY_APPEND(:success_criteria, OBJECT_CONSTRUCT(
    'code', 'WHGEN_COST_IN_BUDGET',
    'label', 'Measured steady-state cost stays inside your credit cap',
    'why', 'A POC that cannot state its own running cost cannot be approved for '
        || 'production.',
    'compare', '<=',
    'units', 'credits',
    'basis', 'BY_TAG',
    'target_derivation', 'No cap was set, so there is no bar to derive.',
    'na_reason', 'WHGEN_CREDIT_CAP is 0, so no ceiling was declared for this run. Set '
        || 'it and re-run to have this criterion scored. Picking a default ceiling '
        || 'here would invent a standard you did not choose.'));
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
   || 'COMMENT = ''Cost attribution for Warehouse Generation — Gen2 and Adaptive. Query '
   || 'ACCOUNT_USAGE.TAG_REFERENCES to find everything this deployment owns.''');
    stmts := ARRAY_APPEND(:stmts,
      'ALTER SCHEMA ' || :tgt || ' SET TAG ' || :tgt || '.ONESHOT_SOLUTION = '
   || '''Warehouse Generation — Gen2 and Adaptive''');
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
     || '.ONESHOT_SOLUTION = ''Warehouse Generation — Gen2 and Adaptive''');
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
        'FAILURE NOTIFICATION SKIPPED: WHGEN_NOTIFICATION_INTEGRATION is blank, so '
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
 || '      RETURN ''REFUSED. This build was created with WHGEN_ALLOW_SAMPLE_ACTIONS = '
 || 'FALSE, so even the seeded-data actions are inert. Re-run the script with it set '
 || 'to TRUE to arm them.''; '
 || '    END IF; '
 || '  ELSE '
 || '    enabled := (SELECT ACTIONS_ENABLED FROM ' || :tgt || '.V_BUILD_CONTEXT LIMIT 1); '
 || '    IF (NOT COALESCE(:enabled, FALSE)) THEN '
 || '      RETURN ''REFUSED. '' || :tier || '' actions touch real data and this build was '
 || 'created with WHGEN_ALLOW_ACTIONS = FALSE, so nothing in the app can change '
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
 || '      RETURN ''REFUSED. This build was created with WHGEN_ALLOW_SAMPLE_ACTIONS = FALSE.''; '
 || '    END IF; '
 || '  ELSE '
 || '    enabled := (SELECT ACTIONS_ENABLED FROM ' || :tgt || '.V_BUILD_CONTEXT LIMIT 1); '
 || '    IF (NOT COALESCE(:enabled, FALSE)) THEN '
 || '      RETURN ''REFUSED. This build was created with WHGEN_ALLOW_ACTIONS = FALSE.''; '
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
          'WHGEN_ALLOW_ACTIONS is TRUE, so they are ARMED: a user of the dashboard can '
       || 'run them after typing the action code to confirm. Every attempt is recorded '
       || 'in ACTION_LOG.',
          'WHGEN_ALLOW_ACTIONS is FALSE, so every button is inert and RUN_ACTION refuses. '
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
  -- ui-sources sha256:1c1313a75f8ceb43
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
    || 'MSBhcyBjb21wb25lbnRzCgpBUFBfSlNfQjY0ID0gIktHWjFibU4wYVc5dUtDbDdJblZ6WlNCemRISnBZM1FpTzJaMWJtTjBhVzl1SUdOaktIVXBlM0psZEhW'
    || 'eWJpQjFKaVoxTGw5ZlpYTk5iMlIxYkdVbUprOWlhbVZqZEM1d2NtOTBiM1I1Y0dVdWFHRnpUM2R1VUhKdmNHVnlkSGt1WTJGc2JDaDFMQ0prWldaaGRXeDBJ'
    || 'aWsvZFM1a1pXWmhkV3gwT25WOWRtRnlJRmxzUFh0bGVIQnZjblJ6T250OWZTeFpiajE3ZlN4SGJEMTdaWGh3YjNKMGN6cDdmWDBzV2oxN2ZUc3ZLaW9LSUNv'
    || 'Z1FHeHBZMlZ1YzJVZ1VtVmhZM1FLSUNvZ2NtVmhZM1F1Y0hKdlpIVmpkR2x2Ymk1dGFXNHVhbk1LSUNvS0lDb2dRMjl3ZVhKcFoyaDBJQ2hqS1NCR1lXTmxZ'
    || 'bTl2YXl3Z1NXNWpMaUJoYm1RZ2FYUnpJR0ZtWm1sc2FXRjBaWE11Q2lBcUNpQXFJRlJvYVhNZ2MyOTFjbU5sSUdOdlpHVWdhWE1nYkdsalpXNXpaV1FnZFc1'
    || 'a1pYSWdkR2hsSUUxSlZDQnNhV05sYm5ObElHWnZkVzVrSUdsdUlIUm9aUW9nS2lCTVNVTkZUbE5GSUdacGJHVWdhVzRnZEdobElISnZiM1FnWkdseVpXTjBi'
    || 'M0o1SUc5bUlIUm9hWE1nYzI5MWNtTmxJSFJ5WldVdUNpQXFMM1poY2lCaWJ6dG1kVzVqZEdsdmJpQmtZeWdwZTJsbUtHSnZLWEpsZEhWeWJpQmFPMkp2UFRF'
    || 'N2RtRnlJSFU5VTNsdFltOXNMbVp2Y2lnaWNtVmhZM1F1Wld4bGJXVnVkQ0lwTEdNOVUzbHRZbTlzTG1admNpZ2ljbVZoWTNRdWNHOXlkR0ZzSWlrc1lUMVRl'
    || 'VzFpYjJ3dVptOXlLQ0p5WldGamRDNW1jbUZuYldWdWRDSXBMRzA5VTNsdFltOXNMbVp2Y2lnaWNtVmhZM1F1YzNSeWFXTjBYMjF2WkdVaUtTeEZQVk41YldK'
    || 'dmJDNW1iM0lvSW5KbFlXTjBMbkJ5YjJacGJHVnlJaWtzVkQxVGVXMWliMnd1Wm05eUtDSnlaV0ZqZEM1d2NtOTJhV1JsY2lJcExIZzlVM2x0WW05c0xtWnZj'
    || 'aWdpY21WaFkzUXVZMjl1ZEdWNGRDSXBMR285VTNsdFltOXNMbVp2Y2lnaWNtVmhZM1F1Wm05eWQyRnlaRjl5WldZaUtTeFRQVk41YldKdmJDNW1iM0lvSW5K'
    || 'bFlXTjBMbk4xYzNCbGJuTmxJaWtzVVQxVGVXMWliMnd1Wm05eUtDSnlaV0ZqZEM1dFpXMXZJaWtzVWoxVGVXMWliMnd1Wm05eUtDSnlaV0ZqZEM1c1lYcDVJ'
    || 'aWtzZWoxVGVXMWliMnd1YVhSbGNtRjBiM0k3Wm5WdVkzUnBiMjRnU0Nob0tYdHlaWFIxY200Z2FEMDlQVzUxYkd4OGZIUjVjR1Z2WmlCb0lUMGliMkpxWldO'
    || 'MElqOXVkV3hzT2lob1BYb21KbWhiZWwxOGZHaGJJa0JBYVhSbGNtRjBiM0lpWFN4MGVYQmxiMllnYUQwOUltWjFibU4wYVc5dUlqOW9PbTUxYkd3cGZYWmhj'
    || 'aUJsWlQxN2FYTk5iM1Z1ZEdWa09tWjFibU4wYVc5dUtDbDdjbVYwZFhKdUlURjlMR1Z1Y1hWbGRXVkdiM0pqWlZWd1pHRjBaVHBtZFc1amRHbHZiaWdwZTMw'
    || 'c1pXNXhkV1YxWlZKbGNHeGhZMlZUZEdGMFpUcG1kVzVqZEdsdmJpZ3BlMzBzWlc1eGRXVjFaVk5sZEZOMFlYUmxPbVoxYm1OMGFXOXVLQ2w3Zlgwc1lqMVBZ'
    || 'bXBsWTNRdVlYTnphV2R1TEVvOWUzMDdablZ1WTNScGIyNGdSeWhvTEhjc1dDbDdkR2hwY3k1d2NtOXdjejFvTEhSb2FYTXVZMjl1ZEdWNGREMTNMSFJvYVhN'
    || 'dWNtVm1jejFLTEhSb2FYTXVkWEJrWVhSbGNqMVlmSHhsWlgxSExuQnliM1J2ZEhsd1pTNXBjMUpsWVdOMFEyOXRjRzl1Wlc1MFBYdDlMRWN1Y0hKdmRHOTBl'
    || 'WEJsTG5ObGRGTjBZWFJsUFdaMWJtTjBhVzl1S0dnc2R5bDdhV1lvZEhsd1pXOW1JR2doUFNKdlltcGxZM1FpSmlaMGVYQmxiMllnYUNFOUltWjFibU4wYVc5'
    || 'dUlpWW1hQ0U5Ym5Wc2JDbDBhSEp2ZHlCRmNuSnZjaWdpYzJWMFUzUmhkR1VvTGk0dUtUb2dkR0ZyWlhNZ1lXNGdiMkpxWldOMElHOW1JSE4wWVhSbElIWmhj'
    || 'bWxoWW14bGN5QjBieUIxY0dSaGRHVWdiM0lnWVNCbWRXNWpkR2x2YmlCM2FHbGphQ0J5WlhSMWNtNXpJR0Z1SUc5aWFtVmpkQ0J2WmlCemRHRjBaU0IyWVhK'
    || 'cFlXSnNaWE11SWlrN2RHaHBjeTUxY0dSaGRHVnlMbVZ1Y1hWbGRXVlRaWFJUZEdGMFpTaDBhR2x6TEdnc2R5d2ljMlYwVTNSaGRHVWlLWDBzUnk1d2NtOTBi'
    || 'M1I1Y0dVdVptOXlZMlZWY0dSaGRHVTlablZ1WTNScGIyNG9hQ2w3ZEdocGN5NTFjR1JoZEdWeUxtVnVjWFZsZFdWR2IzSmpaVlZ3WkdGMFpTaDBhR2x6TEdn'
    || 'c0ltWnZjbU5sVlhCa1lYUmxJaWw5TzJaMWJtTjBhVzl1SUhSbEtDbDdmWFJsTG5CeWIzUnZkSGx3WlQxSExuQnliM1J2ZEhsd1pUdG1kVzVqZEdsdmJpQlRa'
    || 'U2hvTEhjc1dDbDdkR2hwY3k1d2NtOXdjejFvTEhSb2FYTXVZMjl1ZEdWNGREMTNMSFJvYVhNdWNtVm1jejFLTEhSb2FYTXVkWEJrWVhSbGNqMVlmSHhsWlgx'
    || 'MllYSWdRajFUWlM1d2NtOTBiM1I1Y0dVOWJtVjNJSFJsTzBJdVkyOXVjM1J5ZFdOMGIzSTlVMlVzWWloQ0xFY3VjSEp2ZEc5MGVYQmxLU3hDTG1selVIVnla'
    || 'VkpsWVdOMFEyOXRjRzl1Wlc1MFBTRXdPM1poY2lCTFBVRnljbUY1TG1selFYSnlZWGtzYW1VOVQySnFaV04wTG5CeWIzUnZkSGx3WlM1b1lYTlBkMjVRY205'
    || 'd1pYSjBlU3hoWlQxN1kzVnljbVZ1ZERwdWRXeHNmU3hqWlQxN2EyVjVPaUV3TEhKbFpqb2hNQ3hmWDNObGJHWTZJVEFzWDE5emIzVnlZMlU2SVRCOU8yWjFi'
    || 'bU4wYVc5dUlHZGxLR2dzZHl4WUtYdDJZWElnY1N4eVpUMTdmU3hzWlQxdWRXeHNMR1JsUFc1MWJHdzdhV1lvZHlFOWJuVnNiQ2xtYjNJb2NTQnBiaUIzTG5K'
    || 'bFppRTlQWFp2YVdRZ01DWW1LR1JsUFhjdWNtVm1LU3gzTG10bGVTRTlQWFp2YVdRZ01DWW1LR3hsUFNJaUszY3VhMlY1S1N4M0tXcGxMbU5oYkd3b2R5eHhL'
    || 'U1ltSVdObExtaGhjMDkzYmxCeWIzQmxjblI1S0hFcEppWW9jbVZiY1YwOWQxdHhYU2s3ZG1GeUlITmxQV0Z5WjNWdFpXNTBjeTVzWlc1bmRHZ3RNanRwWmlo'
    || 'elpUMDlQVEVwY21VdVkyaHBiR1J5Wlc0OVdEdGxiSE5sSUdsbUtERThjMlVwZTJadmNpaDJZWElnYldVOVFYSnlZWGtvYzJVcExHSmxQVEE3WW1VOGMyVTdZ'
    || 'bVVyS3lsdFpWdGlaVjA5WVhKbmRXMWxiblJ6VzJKbEt6SmRPM0psTG1Ob2FXeGtjbVZ1UFcxbGZXbG1LR2dtSm1ndVpHVm1ZWFZzZEZCeWIzQnpLV1p2Y2lo'
    || 'eElHbHVJSE5sUFdndVpHVm1ZWFZzZEZCeWIzQnpMSE5sS1hKbFczRmRQVDA5ZG05cFpDQXdKaVlvY21WYmNWMDljMlZiY1YwcE8zSmxkSFZ5Ym5za0pIUjVj'
    || 'R1Z2WmpwMUxIUjVjR1U2YUN4clpYazZiR1VzY21WbU9tUmxMSEJ5YjNCek9uSmxMRjl2ZDI1bGNqcGhaUzVqZFhKeVpXNTBmWDFtZFc1amRHbHZiaUJ2WlNo'
    || 'b0xIY3BlM0psZEhWeWJuc2tKSFI1Y0dWdlpqcDFMSFI1Y0dVNmFDNTBlWEJsTEd0bGVUcDNMSEpsWmpwb0xuSmxaaXh3Y205d2N6cG9MbkJ5YjNCekxGOXZk'
    || 'MjVsY2pwb0xsOXZkMjVsY24xOVpuVnVZM1JwYjI0Z2JIUW9hQ2w3Y21WMGRYSnVJSFI1Y0dWdlppQm9QVDBpYjJKcVpXTjBJaVltYUNFOVBXNTFiR3dtSm1n'
    || 'dUpDUjBlWEJsYjJZOVBUMTFmV1oxYm1OMGFXOXVJRzl1S0dncGUzWmhjaUIzUFhzaVBTSTZJajB3SWl3aU9pSTZJajB5SW4wN2NtVjBkWEp1SWlRaUsyZ3Vj'
    || 'bVZ3YkdGalpTZ3ZXejA2WFM5bkxHWjFibU4wYVc5dUtGZ3BlM0psZEhWeWJpQjNXMWhkZlNsOWRtRnlJRjkwUFM5Y0x5c3ZaenRtZFc1amRHbHZiaUJLWlNo'
    || 'b0xIY3BlM0psZEhWeWJpQjBlWEJsYjJZZ2FEMDlJbTlpYW1WamRDSW1KbWdoUFQxdWRXeHNKaVpvTG10bGVTRTliblZzYkQ5dmJpZ2lJaXRvTG10bGVTazZk'
    || 'eTUwYjFOMGNtbHVaeWd6TmlsOVpuVnVZM1JwYjI0Z1puUW9hQ3gzTEZnc2NTeHlaU2w3ZG1GeUlHeGxQWFI1Y0dWdlppQm9PeWhzWlQwOVBTSjFibVJsWm1s'
    || 'dVpXUWlmSHhzWlQwOVBTSmliMjlzWldGdUlpa21KaWhvUFc1MWJHd3BPM1poY2lCa1pUMGhNVHRwWmlob1BUMDliblZzYkNsa1pUMGhNRHRsYkhObElITjNh'
    || 'WFJqYUNoc1pTbDdZMkZ6WlNKemRISnBibWNpT21OaGMyVWliblZ0WW1WeUlqcGtaVDBoTUR0aWNtVmhhenRqWVhObEltOWlhbVZqZENJNmMzZHBkR05vS0dn'
    || 'dUpDUjBlWEJsYjJZcGUyTmhjMlVnZFRwallYTmxJR002WkdVOUlUQjlmV2xtS0dSbEtYSmxkSFZ5YmlCa1pUMW9MSEpsUFhKbEtHUmxLU3hvUFhFOVBUMGlJ'
    || 'ajhpTGlJclNtVW9aR1VzTUNrNmNTeExLSEpsS1Q4b1dEMGlJaXhvSVQxdWRXeHNKaVlvV0Qxb0xuSmxjR3hoWTJVb1gzUXNJaVFtTHlJcEt5SXZJaWtzWm5R'
    || 'b2NtVXNkeXhZTENJaUxHWjFibU4wYVc5dUtHSmxLWHR5WlhSMWNtNGdZbVY5S1NrNmNtVWhQVzUxYkd3bUppaHNkQ2h5WlNrbUppaHlaVDF2WlNoeVpTeFlL'
    || 'eWdoY21VdWEyVjVmSHhrWlNZbVpHVXVhMlY1UFQwOWNtVXVhMlY1UHlJaU9pZ2lJaXR5WlM1clpYa3BMbkpsY0d4aFkyVW9YM1FzSWlRbUx5SXBLeUl2SWlr'
    || 'cmFDa3BMSGN1Y0hWemFDaHlaU2twTERFN2FXWW9aR1U5TUN4eFBYRTlQVDBpSWo4aUxpSTZjU3NpT2lJc1N5aG9LU2xtYjNJb2RtRnlJSE5sUFRBN2MyVThh'
    || 'QzVzWlc1bmRHZzdjMlVyS3lsN2JHVTlhRnR6WlYwN2RtRnlJRzFsUFhFclNtVW9iR1VzYzJVcE8yUmxLejFtZENoc1pTeDNMRmdzYldVc2NtVXBmV1ZzYzJV'
    || 'Z2FXWW9iV1U5U0Nob0tTeDBlWEJsYjJZZ2JXVTlQU0ptZFc1amRHbHZiaUlwWm05eUtHZzliV1V1WTJGc2JDaG9LU3h6WlQwd095RW9iR1U5YUM1dVpYaDBL'
    || 'Q2twTG1SdmJtVTdLV3hsUFd4bExuWmhiSFZsTEcxbFBYRXJTbVVvYkdVc2MyVXJLeWtzWkdVclBXWjBLR3hsTEhjc1dDeHRaU3h5WlNrN1pXeHpaU0JwWmlo'
    || 'c1pUMDlQU0p2WW1wbFkzUWlLWFJvY205M0lIYzlVM1J5YVc1bktHZ3BMRVZ5Y205eUtDSlBZbXBsWTNSeklHRnlaU0J1YjNRZ2RtRnNhV1FnWVhNZ1lTQlNa'
    || 'V0ZqZENCamFHbHNaQ0FvWm05MWJtUTZJQ0lyS0hjOVBUMGlXMjlpYW1WamRDQlBZbXBsWTNSZElqOGliMkpxWldOMElIZHBkR2dnYTJWNWN5QjdJaXRQWW1w'
    || 'bFkzUXVhMlY1Y3lob0tTNXFiMmx1S0NJc0lDSXBLeUo5SWpwM0tTc2lLUzRnU1dZZ2VXOTFJRzFsWVc1MElIUnZJSEpsYm1SbGNpQmhJR052Ykd4bFkzUnBi'
    || 'MjRnYjJZZ1kyaHBiR1J5Wlc0c0lIVnpaU0JoYmlCaGNuSmhlU0JwYm5OMFpXRmtMaUlwTzNKbGRIVnliaUJrWlgxbWRXNWpkR2x2YmlCVGRDaG9MSGNzV0Ns'
    || 'N2FXWW9hRDA5Ym5Wc2JDbHlaWFIxY200Z2FEdDJZWElnY1QxYlhTeHlaVDB3TzNKbGRIVnliaUJtZENob0xIRXNJaUlzSWlJc1puVnVZM1JwYjI0b2JHVXBl'
    || 'M0psZEhWeWJpQjNMbU5oYkd3b1dDeHNaU3h5WlNzcktYMHBMSEY5Wm5WdVkzUnBiMjRnVVdVb2FDbDdhV1lvYUM1ZmMzUmhkSFZ6UFQwOUxURXBlM1poY2lC'
    || 'M1BXZ3VYM0psYzNWc2REdDNQWGNvS1N4M0xuUm9aVzRvWm5WdVkzUnBiMjRvV0NsN0tHZ3VYM04wWVhSMWN6MDlQVEI4ZkdndVgzTjBZWFIxY3owOVBTMHhL'
    || 'U1ltS0dndVgzTjBZWFIxY3oweExHZ3VYM0psYzNWc2REMVlLWDBzWm5WdVkzUnBiMjRvV0NsN0tHZ3VYM04wWVhSMWN6MDlQVEI4ZkdndVgzTjBZWFIxY3ow'
    || 'OVBTMHhLU1ltS0dndVgzTjBZWFIxY3oweUxHZ3VYM0psYzNWc2REMVlLWDBwTEdndVgzTjBZWFIxY3owOVBTMHhKaVlvYUM1ZmMzUmhkSFZ6UFRBc2FDNWZj'
    || 'bVZ6ZFd4MFBYY3BmV2xtS0dndVgzTjBZWFIxY3owOVBURXBjbVYwZFhKdUlHZ3VYM0psYzNWc2RDNWtaV1poZFd4ME8zUm9jbTkzSUdndVgzSmxjM1ZzZEgx'
    || 'MllYSWdSV1U5ZTJOMWNuSmxiblE2Ym5Wc2JIMHNSRDE3ZEhKaGJuTnBkR2x2YmpwdWRXeHNmU3drUFh0U1pXRmpkRU4xY25KbGJuUkVhWE53WVhSamFHVnlP'
    || 'a1ZsTEZKbFlXTjBRM1Z5Y21WdWRFSmhkR05vUTI5dVptbG5Pa1FzVW1WaFkzUkRkWEp5Wlc1MFQzZHVaWEk2WVdWOU8yWjFibU4wYVc5dUlFd29LWHQwYUhK'
    || 'dmR5QkZjbkp2Y2lnaVlXTjBLQzR1TGlrZ2FYTWdibTkwSUhOMWNIQnZjblJsWkNCcGJpQndjbTlrZFdOMGFXOXVJR0oxYVd4a2N5QnZaaUJTWldGamRDNGlL'
    || 'WDF5WlhSMWNtNGdXaTVEYUdsc1pISmxiajE3YldGd09sTjBMR1p2Y2tWaFkyZzZablZ1WTNScGIyNG9hQ3gzTEZncGUxTjBLR2dzWm5WdVkzUnBiMjRvS1h0'
    || 'M0xtRndjR3g1S0hSb2FYTXNZWEpuZFcxbGJuUnpLWDBzV0NsOUxHTnZkVzUwT21aMWJtTjBhVzl1S0dncGUzWmhjaUIzUFRBN2NtVjBkWEp1SUZOMEtHZ3Na'
    || 'blZ1WTNScGIyNG9LWHQzS3l0OUtTeDNmU3gwYjBGeWNtRjVPbVoxYm1OMGFXOXVLR2dwZTNKbGRIVnliaUJUZENob0xHWjFibU4wYVc5dUtIY3BlM0psZEhW'
    || 'eWJpQjNmU2w4ZkZ0ZGZTeHZibXg1T21aMWJtTjBhVzl1S0dncGUybG1LQ0ZzZENob0tTbDBhSEp2ZHlCRmNuSnZjaWdpVW1WaFkzUXVRMmhwYkdSeVpXNHVi'
    || 'MjVzZVNCbGVIQmxZM1JsWkNCMGJ5QnlaV05sYVhabElHRWdjMmx1WjJ4bElGSmxZV04wSUdWc1pXMWxiblFnWTJocGJHUXVJaWs3Y21WMGRYSnVJR2g5ZlN4'
    || 'YUxrTnZiWEJ2Ym1WdWREMUhMRm91Um5KaFoyMWxiblE5WVN4YUxsQnliMlpwYkdWeVBVVXNXaTVRZFhKbFEyOXRjRzl1Wlc1MFBWTmxMRm91VTNSeWFXTjBU'
    || 'VzlrWlQxdExGb3VVM1Z6Y0dWdWMyVTlVeXhhTGw5ZlUwVkRVa1ZVWDBsT1ZFVlNUa0ZNVTE5RVQxOU9UMVJmVlZORlgwOVNYMWxQVlY5WFNVeE1YMEpGWDBa'
    || 'SlVrVkVQU1FzV2k1aFkzUTlUQ3hhTG1Oc2IyNWxSV3hsYldWdWREMW1kVzVqZEdsdmJpaG9MSGNzV0NsN2FXWW9hRDA5Ym5Wc2JDbDBhSEp2ZHlCRmNuSnZj'
    || 'aWdpVW1WaFkzUXVZMnh2Ym1WRmJHVnRaVzUwS0M0dUxpazZJRlJvWlNCaGNtZDFiV1Z1ZENCdGRYTjBJR0psSUdFZ1VtVmhZM1FnWld4bGJXVnVkQ3dnWW5W'
    || 'MElIbHZkU0J3WVhOelpXUWdJaXRvS3lJdUlpazdkbUZ5SUhFOVlpaDdmU3hvTG5CeWIzQnpLU3h5WlQxb0xtdGxlU3hzWlQxb0xuSmxaaXhrWlQxb0xsOXZk'
    || 'MjVsY2p0cFppaDNJVDF1ZFd4c0tYdHBaaWgzTG5KbFppRTlQWFp2YVdRZ01DWW1LR3hsUFhjdWNtVm1MR1JsUFdGbExtTjFjbkpsYm5RcExIY3VhMlY1SVQw'
    || 'OWRtOXBaQ0F3SmlZb2NtVTlJaUlyZHk1clpYa3BMR2d1ZEhsd1pTWW1hQzUwZVhCbExtUmxabUYxYkhSUWNtOXdjeWwyWVhJZ2MyVTlhQzUwZVhCbExtUmxa'
    || 'bUYxYkhSUWNtOXdjenRtYjNJb2JXVWdhVzRnZHlscVpTNWpZV3hzS0hjc2JXVXBKaVloWTJVdWFHRnpUM2R1VUhKdmNHVnlkSGtvYldVcEppWW9jVnR0WlYw'
    || 'OWQxdHRaVjA5UFQxMmIybGtJREFtSm5ObElUMDlkbTlwWkNBd1AzTmxXMjFsWFRwM1cyMWxYU2w5ZG1GeUlHMWxQV0Z5WjNWdFpXNTBjeTVzWlc1bmRHZ3RN'
    || 'anRwWmlodFpUMDlQVEVwY1M1amFHbHNaSEpsYmoxWU8yVnNjMlVnYVdZb01UeHRaU2w3YzJVOVFYSnlZWGtvYldVcE8yWnZjaWgyWVhJZ1ltVTlNRHRpWlR4'
    || 'dFpUdGlaU3NyS1hObFcySmxYVDFoY21kMWJXVnVkSE5iWW1Vck1sMDdjUzVqYUdsc1pISmxiajF6WlgxeVpYUjFjbTU3SkNSMGVYQmxiMlk2ZFN4MGVYQmxP'
    || 'bWd1ZEhsd1pTeHJaWGs2Y21Vc2NtVm1PbXhsTEhCeWIzQnpPbkVzWDI5M2JtVnlPbVJsZlgwc1dpNWpjbVZoZEdWRGIyNTBaWGgwUFdaMWJtTjBhVzl1S0dn'
    || 'cGUzSmxkSFZ5YmlCb1BYc2tKSFI1Y0dWdlpqcDRMRjlqZFhKeVpXNTBWbUZzZFdVNmFDeGZZM1Z5Y21WdWRGWmhiSFZsTWpwb0xGOTBhSEpsWVdSRGIzVnVk'
    || 'RG93TEZCeWIzWnBaR1Z5T201MWJHd3NRMjl1YzNWdFpYSTZiblZzYkN4ZlpHVm1ZWFZzZEZaaGJIVmxPbTUxYkd3c1gyZHNiMkpoYkU1aGJXVTZiblZzYkgw'
    || 'c2FDNVFjbTkyYVdSbGNqMTdKQ1IwZVhCbGIyWTZWQ3hmWTI5dWRHVjRkRHBvZlN4b0xrTnZibk4xYldWeVBXaDlMRm91WTNKbFlYUmxSV3hsYldWdWREMW5a'
    || 'U3hhTG1OeVpXRjBaVVpoWTNSdmNuazlablZ1WTNScGIyNG9hQ2w3ZG1GeUlIYzlaMlV1WW1sdVpDaHVkV3hzTEdncE8zSmxkSFZ5YmlCM0xuUjVjR1U5YUN4'
    || 'M2ZTeGFMbU55WldGMFpWSmxaajFtZFc1amRHbHZiaWdwZTNKbGRIVnlibnRqZFhKeVpXNTBPbTUxYkd4OWZTeGFMbVp2Y25kaGNtUlNaV1k5Wm5WdVkzUnBi'
    || 'MjRvYUNsN2NtVjBkWEp1ZXlRa2RIbHdaVzltT21vc2NtVnVaR1Z5T21oOWZTeGFMbWx6Vm1Gc2FXUkZiR1Z0Wlc1MFBXeDBMRm91YkdGNmVUMW1kVzVqZEds'
    || 'dmJpaG9LWHR5WlhSMWNtNTdKQ1IwZVhCbGIyWTZVaXhmY0dGNWJHOWhaRHA3WDNOMFlYUjFjem90TVN4ZmNtVnpkV3gwT21oOUxGOXBibWwwT2xGbGZYMHNX'
    || 'aTV0WlcxdlBXWjFibU4wYVc5dUtHZ3NkeWw3Y21WMGRYSnVleVFrZEhsd1pXOW1PbEVzZEhsd1pUcG9MR052YlhCaGNtVTZkejA5UFhadmFXUWdNRDl1ZFd4'
    || 'c09uZDlmU3hhTG5OMFlYSjBWSEpoYm5OcGRHbHZiajFtZFc1amRHbHZiaWhvS1h0MllYSWdkejFFTG5SeVlXNXphWFJwYjI0N1JDNTBjbUZ1YzJsMGFXOXVQ'
    || 'WHQ5TzNSeWVYdG9LQ2w5Wm1sdVlXeHNlWHRFTG5SeVlXNXphWFJwYjI0OWQzMTlMRm91ZFc1emRHRmliR1ZmWVdOMFBVd3NXaTUxYzJWRFlXeHNZbUZqYXox'
    || 'bWRXNWpkR2x2Ymlob0xIY3BlM0psZEhWeWJpQkZaUzVqZFhKeVpXNTBMblZ6WlVOaGJHeGlZV05yS0dnc2R5bDlMRm91ZFhObFEyOXVkR1Y0ZEQxbWRXNWpk'
    || 'R2x2Ymlob0tYdHlaWFIxY200Z1JXVXVZM1Z5Y21WdWRDNTFjMlZEYjI1MFpYaDBLR2dwZlN4YUxuVnpaVVJsWW5WblZtRnNkV1U5Wm5WdVkzUnBiMjRvS1h0'
    || 'OUxGb3VkWE5sUkdWbVpYSnlaV1JXWVd4MVpUMW1kVzVqZEdsdmJpaG9LWHR5WlhSMWNtNGdSV1V1WTNWeWNtVnVkQzUxYzJWRVpXWmxjbkpsWkZaaGJIVmxL'
    || 'R2dwZlN4YUxuVnpaVVZtWm1WamREMW1kVzVqZEdsdmJpaG9MSGNwZTNKbGRIVnliaUJGWlM1amRYSnlaVzUwTG5WelpVVm1abVZqZENob0xIY3BmU3hhTG5W'
    || 'elpVbGtQV1oxYm1OMGFXOXVLQ2w3Y21WMGRYSnVJRVZsTG1OMWNuSmxiblF1ZFhObFNXUW9LWDBzV2k1MWMyVkpiWEJsY21GMGFYWmxTR0Z1Wkd4bFBXWjFi'
    || 'bU4wYVc5dUtHZ3NkeXhZS1h0eVpYUjFjbTRnUldVdVkzVnljbVZ1ZEM1MWMyVkpiWEJsY21GMGFYWmxTR0Z1Wkd4bEtHZ3NkeXhZS1gwc1dpNTFjMlZKYm5O'
    || 'bGNuUnBiMjVGWm1abFkzUTlablZ1WTNScGIyNG9hQ3gzS1h0eVpYUjFjbTRnUldVdVkzVnljbVZ1ZEM1MWMyVkpibk5sY25ScGIyNUZabVpsWTNRb2FDeDNL'
    || 'WDBzV2k1MWMyVk1ZWGx2ZFhSRlptWmxZM1E5Wm5WdVkzUnBiMjRvYUN4M0tYdHlaWFIxY200Z1JXVXVZM1Z5Y21WdWRDNTFjMlZNWVhsdmRYUkZabVpsWTNR'
    || 'b2FDeDNLWDBzV2k1MWMyVk5aVzF2UFdaMWJtTjBhVzl1S0dnc2R5bDdjbVYwZFhKdUlFVmxMbU4xY25KbGJuUXVkWE5sVFdWdGJ5aG9MSGNwZlN4YUxuVnpa'
    || 'VkpsWkhWalpYSTlablZ1WTNScGIyNG9hQ3gzTEZncGUzSmxkSFZ5YmlCRlpTNWpkWEp5Wlc1MExuVnpaVkpsWkhWalpYSW9hQ3gzTEZncGZTeGFMblZ6WlZK'
    || 'bFpqMW1kVzVqZEdsdmJpaG9LWHR5WlhSMWNtNGdSV1V1WTNWeWNtVnVkQzUxYzJWU1pXWW9hQ2w5TEZvdWRYTmxVM1JoZEdVOVpuVnVZM1JwYjI0b2FDbDdj'
    || 'bVYwZFhKdUlFVmxMbU4xY25KbGJuUXVkWE5sVTNSaGRHVW9hQ2w5TEZvdWRYTmxVM2x1WTBWNGRHVnlibUZzVTNSdmNtVTlablZ1WTNScGIyNG9hQ3gzTEZn'
    || 'cGUzSmxkSFZ5YmlCRlpTNWpkWEp5Wlc1MExuVnpaVk41Ym1ORmVIUmxjbTVoYkZOMGIzSmxLR2dzZHl4WUtYMHNXaTUxYzJWVWNtRnVjMmwwYVc5dVBXWjFi'
    || 'bU4wYVc5dUtDbDdjbVYwZFhKdUlFVmxMbU4xY25KbGJuUXVkWE5sVkhKaGJuTnBkR2x2YmlncGZTeGFMblpsY25OcGIyNDlJakU0TGpNdU1TSXNXbjEyWVhJ'
    || 'Z1pYTTdablZ1WTNScGIyNGdTMndvS1h0eVpYUjFjbTRnWlhOOGZDaGxjejB4TEVkc0xtVjRjRzl5ZEhNOVpHTW9LU2tzUjJ3dVpYaHdiM0owYzMwdktpb0tJ'
    || 'Q29nUUd4cFkyVnVjMlVnVW1WaFkzUUtJQ29nY21WaFkzUXRhbk40TFhKMWJuUnBiV1V1Y0hKdlpIVmpkR2x2Ymk1dGFXNHVhbk1LSUNvS0lDb2dRMjl3ZVhK'
    || 'cFoyaDBJQ2hqS1NCR1lXTmxZbTl2YXl3Z1NXNWpMaUJoYm1RZ2FYUnpJR0ZtWm1sc2FXRjBaWE11Q2lBcUNpQXFJRlJvYVhNZ2MyOTFjbU5sSUdOdlpHVWdh'
    || 'WE1nYkdsalpXNXpaV1FnZFc1a1pYSWdkR2hsSUUxSlZDQnNhV05sYm5ObElHWnZkVzVrSUdsdUlIUm9aUW9nS2lCTVNVTkZUbE5GSUdacGJHVWdhVzRnZEdo'
    || 'bElISnZiM1FnWkdseVpXTjBiM0o1SUc5bUlIUm9hWE1nYzI5MWNtTmxJSFJ5WldVdUNpQXFMM1poY2lCMGN6dG1kVzVqZEdsdmJpQm1ZeWdwZTJsbUtIUnpL'
    || 'WEpsZEhWeWJpQlpianQwY3oweE8zWmhjaUIxUFV0c0tDa3NZejFUZVcxaWIyd3VabTl5S0NKeVpXRmpkQzVsYkdWdFpXNTBJaWtzWVQxVGVXMWliMnd1Wm05'
    || 'eUtDSnlaV0ZqZEM1bWNtRm5iV1Z1ZENJcExHMDlUMkpxWldOMExuQnliM1J2ZEhsd1pTNW9ZWE5QZDI1UWNtOXdaWEowZVN4RlBYVXVYMTlUUlVOU1JWUmZT'
    || 'VTVVUlZKT1FVeFRYMFJQWDA1UFZGOVZVMFZmVDFKZldVOVZYMWRKVEV4ZlFrVmZSa2xTUlVRdVVtVmhZM1JEZFhKeVpXNTBUM2R1WlhJc1ZEMTdhMlY1T2lF'
    || 'd0xISmxaam9oTUN4ZlgzTmxiR1k2SVRBc1gxOXpiM1Z5WTJVNklUQjlPMloxYm1OMGFXOXVJSGdvYWl4VExGRXBlM1poY2lCU0xIbzllMzBzU0QxdWRXeHNM'
    || 'R1ZsUFc1MWJHdzdVU0U5UFhadmFXUWdNQ1ltS0VnOUlpSXJVU2tzVXk1clpYa2hQVDEyYjJsa0lEQW1KaWhJUFNJaUsxTXVhMlY1S1N4VExuSmxaaUU5UFha'
    || 'dmFXUWdNQ1ltS0dWbFBWTXVjbVZtS1R0bWIzSW9VaUJwYmlCVEtXMHVZMkZzYkNoVExGSXBKaVloVkM1b1lYTlBkMjVRY205d1pYSjBlU2hTS1NZbUtIcGJV'
    || 'bDA5VTF0U1hTazdhV1lvYWlZbWFpNWtaV1poZFd4MFVISnZjSE1wWm05eUtGSWdhVzRnVXoxcUxtUmxabUYxYkhSUWNtOXdjeXhUS1hwYlVsMDlQVDEyYjJs'
    || 'a0lEQW1KaWg2VzFKZFBWTmJVbDBwTzNKbGRIVnlibnNrSkhSNWNHVnZaanBqTEhSNWNHVTZhaXhyWlhrNlNDeHlaV1k2WldVc2NISnZjSE02ZWl4ZmIzZHVa'
    || 'WEk2UlM1amRYSnlaVzUwZlgxeVpYUjFjbTRnV1c0dVJuSmhaMjFsYm5ROVlTeFpiaTVxYzNnOWVDeFpiaTVxYzNoelBYZ3NXVzU5ZG1GeUlHNXpPMloxYm1O'
    || 'MGFXOXVJSEJqS0NsN2NtVjBkWEp1SUc1emZId29ibk05TVN4WmJDNWxlSEJ2Y25SelBXWmpLQ2twTEZsc0xtVjRjRzl5ZEhOOWRtRnlJRzg5Y0dNb0tTeFli'
    || 'RDFMYkNncE8yTnZibk4wSUhGbFBXTmpLRmhzS1R0MllYSWdVSEk5ZTMwc1dtdzllMlY0Y0c5eWRITTZlMzE5TENSbFBYdDlMSEZzUFh0bGVIQnZjblJ6T250'
    || 'OWZTeEtiRDE3ZlRzdktpb0tJQ29nUUd4cFkyVnVjMlVnVW1WaFkzUUtJQ29nYzJOb1pXUjFiR1Z5TG5CeWIyUjFZM1JwYjI0dWJXbHVMbXB6Q2lBcUNpQXFJ'
    || 'RU52Y0hseWFXZG9kQ0FvWXlrZ1JtRmpaV0p2YjJzc0lFbHVZeTRnWVc1a0lHbDBjeUJoWm1acGJHbGhkR1Z6TGdvZ0tnb2dLaUJVYUdseklITnZkWEpqWlNC'
    || 'amIyUmxJR2x6SUd4cFkyVnVjMlZrSUhWdVpHVnlJSFJvWlNCTlNWUWdiR2xqWlc1elpTQm1iM1Z1WkNCcGJpQjBhR1VLSUNvZ1RFbERSVTVUUlNCbWFXeGxJ'
    || 'R2x1SUhSb1pTQnliMjkwSUdScGNtVmpkRzl5ZVNCdlppQjBhR2x6SUhOdmRYSmpaU0IwY21WbExnb2dLaTkyWVhJZ2NuTTdablZ1WTNScGIyNGdhR01vS1h0'
    || 'eVpYUjFjbTRnY25OOGZDaHljejB4TENobWRXNWpkR2x2YmloMUtYdG1kVzVqZEdsdmJpQmpLRVFzSkNsN2RtRnlJRXc5UkM1c1pXNW5kR2c3UkM1d2RYTm9L'
    || 'Q1FwTzJVNlptOXlLRHN3UEV3N0tYdDJZWElnYUQxTUxURStQajR4TEhjOVJGdG9YVHRwWmlnd1BFVW9keXdrS1NsRVcyaGRQU1FzUkZ0TVhUMTNMRXc5YUR0'
    || 'bGJITmxJR0p5WldGcklHVjlmV1oxYm1OMGFXOXVJR0VvUkNsN2NtVjBkWEp1SUVRdWJHVnVaM1JvUFQwOU1EOXVkV3hzT2tSYk1GMTlablZ1WTNScGIyNGdi'
    || 'U2hFS1h0cFppaEVMbXhsYm1kMGFEMDlQVEFwY21WMGRYSnVJRzUxYkd3N2RtRnlJQ1E5UkZzd1hTeE1QVVF1Y0c5d0tDazdhV1lvVENFOVBTUXBlMFJiTUYw'
    || 'OVREdGxPbVp2Y2loMllYSWdhRDB3TEhjOVJDNXNaVzVuZEdnc1dEMTNQajQrTVR0b1BGZzdLWHQyWVhJZ2NUMHlLaWhvS3pFcExURXNjbVU5UkZ0eFhTeHNa'
    || 'VDF4S3pFc1pHVTlSRnRzWlYwN2FXWW9NRDVGS0hKbExFd3BLV3hsUEhjbUpqQStSU2hrWlN4eVpTay9LRVJiYUYwOVpHVXNSRnRzWlYwOVRDeG9QV3hsS1Rv'
    || 'b1JGdG9YVDF5WlN4RVczRmRQVXdzYUQxeEtUdGxiSE5sSUdsbUtHeGxQSGNtSmpBK1JTaGtaU3hNS1NsRVcyaGRQV1JsTEVSYmJHVmRQVXdzYUQxc1pUdGxi'
    || 'SE5sSUdKeVpXRnJJR1Y5ZlhKbGRIVnliaUFrZldaMWJtTjBhVzl1SUVVb1JDd2tLWHQyWVhJZ1REMUVMbk52Y25SSmJtUmxlQzBrTG5OdmNuUkpibVJsZUR0'
    || 'eVpYUjFjbTRnVENFOVBUQS9URHBFTG1sa0xTUXVhV1I5YVdZb2RIbHdaVzltSUhCbGNtWnZjbTFoYm1ObFBUMGliMkpxWldOMElpWW1kSGx3Wlc5bUlIQmxj'
    || 'bVp2Y20xaGJtTmxMbTV2ZHowOUltWjFibU4wYVc5dUlpbDdkbUZ5SUZROWNHVnlabTl5YldGdVkyVTdkUzUxYm5OMFlXSnNaVjl1YjNjOVpuVnVZM1JwYjI0'
    || 'b0tYdHlaWFIxY200Z1ZDNXViM2NvS1gxOVpXeHpaWHQyWVhJZ2VEMUVZWFJsTEdvOWVDNXViM2NvS1R0MUxuVnVjM1JoWW14bFgyNXZkejFtZFc1amRHbHZi'
    || 'aWdwZTNKbGRIVnliaUI0TG01dmR5Z3BMV3A5ZlhaaGNpQlRQVnRkTEZFOVcxMHNVajB4TEhvOWJuVnNiQ3hJUFRNc1pXVTlJVEVzWWowaE1TeEtQU0V4TEVj'
    || 'OWRIbHdaVzltSUhObGRGUnBiV1Z2ZFhROVBTSm1kVzVqZEdsdmJpSS9jMlYwVkdsdFpXOTFkRHB1ZFd4c0xIUmxQWFI1Y0dWdlppQmpiR1ZoY2xScGJXVnZk'
    || 'WFE5UFNKbWRXNWpkR2x2YmlJL1kyeGxZWEpVYVcxbGIzVjBPbTUxYkd3c1UyVTlkSGx3Wlc5bUlITmxkRWx0YldWa2FXRjBaVHdpZFNJL2MyVjBTVzF0WldS'
    || 'cFlYUmxPbTUxYkd3N2RIbHdaVzltSUc1aGRtbG5ZWFJ2Y2p3aWRTSW1KbTVoZG1sbllYUnZjaTV6WTJobFpIVnNhVzVuSVQwOWRtOXBaQ0F3SmladVlYWnBa'
    || 'MkYwYjNJdWMyTm9aV1IxYkdsdVp5NXBjMGx1Y0hWMFVHVnVaR2x1WnlFOVBYWnZhV1FnTUNZbWJtRjJhV2RoZEc5eUxuTmphR1ZrZFd4cGJtY3VhWE5KYm5C'
    || 'MWRGQmxibVJwYm1jdVltbHVaQ2h1WVhacFoyRjBiM0l1YzJOb1pXUjFiR2x1WnlrN1puVnVZM1JwYjI0Z1FpaEVLWHRtYjNJb2RtRnlJQ1E5WVNoUktUc2tJ'
    || 'VDA5Ym5Wc2JEc3BlMmxtS0NRdVkyRnNiR0poWTJzOVBUMXVkV3hzS1cwb1VTazdaV3h6WlNCcFppZ2tMbk4wWVhKMFZHbHRaVHc5UkNsdEtGRXBMQ1F1YzI5'
    || 'eWRFbHVaR1Y0UFNRdVpYaHdhWEpoZEdsdmJsUnBiV1VzWXloVExDUXBPMlZzYzJVZ1luSmxZV3M3SkQxaEtGRXBmWDFtZFc1amRHbHZiaUJMS0VRcGUybG1L'
    || 'RW85SVRFc1FpaEVLU3doWWlscFppaGhLRk1wSVQwOWJuVnNiQ2xpUFNFd0xGRmxLR3BsS1R0bGJITmxlM1poY2lBa1BXRW9VU2s3SkNFOVBXNTFiR3dtSmtW'
    || 'bEtFc3NKQzV6ZEdGeWRGUnBiV1V0UkNsOWZXWjFibU4wYVc5dUlHcGxLRVFzSkNsN1lqMGhNU3hLSmlZb1NqMGhNU3gwWlNoblpTa3NaMlU5TFRFcExHVmxQ'
    || 'U0V3TzNaaGNpQk1QVWc3ZEhKNWUyWnZjaWhDS0NRcExIbzlZU2hUS1R0NklUMDliblZzYkNZbUtDRW9laTVsZUhCcGNtRjBhVzl1VkdsdFpUNGtLWHg4UkNZ'
    || 'bUlXOXVLQ2twT3lsN2RtRnlJR2c5ZWk1allXeHNZbUZqYXp0cFppaDBlWEJsYjJZZ2FEMDlJbVoxYm1OMGFXOXVJaWw3ZWk1allXeHNZbUZqYXoxdWRXeHNM'
    || 'RWc5ZWk1d2NtbHZjbWwwZVV4bGRtVnNPM1poY2lCM1BXZ29laTVsZUhCcGNtRjBhVzl1VkdsdFpUdzlKQ2s3SkQxMUxuVnVjM1JoWW14bFgyNXZkeWdwTEhS'
    || 'NWNHVnZaaUIzUFQwaVpuVnVZM1JwYjI0aVAzb3VZMkZzYkdKaFkyczlkenA2UFQwOVlTaFRLU1ltYlNoVEtTeENLQ1FwZldWc2MyVWdiU2hUS1R0NlBXRW9V'
    || 'eWw5YVdZb2VpRTlQVzUxYkd3cGRtRnlJRmc5SVRBN1pXeHpaWHQyWVhJZ2NUMWhLRkVwTzNFaFBUMXVkV3hzSmlaRlpTaExMSEV1YzNSaGNuUlVhVzFsTFNR'
    || 'cExGZzlJVEY5Y21WMGRYSnVJRmg5Wm1sdVlXeHNlWHQ2UFc1MWJHd3NTRDFNTEdWbFBTRXhmWDEyWVhJZ1lXVTlJVEVzWTJVOWJuVnNiQ3huWlQwdE1TeHZa'
    || 'VDAxTEd4MFBTMHhPMloxYm1OMGFXOXVJRzl1S0NsN2NtVjBkWEp1SVNoMUxuVnVjM1JoWW14bFgyNXZkeWdwTFd4MFBHOWxLWDFtZFc1amRHbHZiaUJmZENn'
    || 'cGUybG1LR05sSVQwOWJuVnNiQ2w3ZG1GeUlFUTlkUzUxYm5OMFlXSnNaVjl1YjNjb0tUdHNkRDFFTzNaaGNpQWtQU0V3TzNSeWVYc2tQV05sS0NFd0xFUXBm'
    || 'V1pwYm1Gc2JIbDdKRDlLWlNncE9paGhaVDBoTVN4alpUMXVkV3hzS1gxOVpXeHpaU0JoWlQwaE1YMTJZWElnU21VN2FXWW9kSGx3Wlc5bUlGTmxQVDBpWm5W'
    || 'dVkzUnBiMjRpS1VwbFBXWjFibU4wYVc5dUtDbDdVMlVvWDNRcGZUdGxiSE5sSUdsbUtIUjVjR1Z2WmlCTlpYTnpZV2RsUTJoaGJtNWxiRHdpZFNJcGUzWmhj'
    || 'aUJtZEQxdVpYY2dUV1Z6YzJGblpVTm9ZVzV1Wld3c1UzUTlablF1Y0c5eWRESTdablF1Y0c5eWRERXViMjV0WlhOellXZGxQVjkwTEVwbFBXWjFibU4wYVc5'
    || 'dUtDbDdVM1F1Y0c5emRFMWxjM05oWjJVb2JuVnNiQ2w5ZldWc2MyVWdTbVU5Wm5WdVkzUnBiMjRvS1h0SEtGOTBMREFwZlR0bWRXNWpkR2x2YmlCUlpTaEVL'
    || 'WHRqWlQxRUxHRmxmSHdvWVdVOUlUQXNTbVVvS1NsOVpuVnVZM1JwYjI0Z1JXVW9SQ3drS1h0blpUMUhLR1oxYm1OMGFXOXVLQ2w3UkNoMUxuVnVjM1JoWW14'
    || 'bFgyNXZkeWdwS1gwc0pDbDlkUzUxYm5OMFlXSnNaVjlKWkd4bFVISnBiM0pwZEhrOU5TeDFMblZ1YzNSaFlteGxYMGx0YldWa2FXRjBaVkJ5YVc5eWFYUjVQ'
    || 'VEVzZFM1MWJuTjBZV0pzWlY5TWIzZFFjbWx2Y21sMGVUMDBMSFV1ZFc1emRHRmliR1ZmVG05eWJXRnNVSEpwYjNKcGRIazlNeXgxTG5WdWMzUmhZbXhsWDFC'
    || 'eWIyWnBiR2x1WnoxdWRXeHNMSFV1ZFc1emRHRmliR1ZmVlhObGNrSnNiMk5yYVc1blVISnBiM0pwZEhrOU1peDFMblZ1YzNSaFlteGxYMk5oYm1ObGJFTmhi'
    || 'R3hpWVdOclBXWjFibU4wYVc5dUtFUXBlMFF1WTJGc2JHSmhZMnM5Ym5Wc2JIMHNkUzUxYm5OMFlXSnNaVjlqYjI1MGFXNTFaVVY0WldOMWRHbHZiajFtZFc1'
    || 'amRHbHZiaWdwZTJKOGZHVmxmSHdvWWowaE1DeFJaU2hxWlNrcGZTeDFMblZ1YzNSaFlteGxYMlp2Y21ObFJuSmhiV1ZTWVhSbFBXWjFibU4wYVc5dUtFUXBl'
    || 'ekErUkh4OE1USTFQRVEvWTI5dWMyOXNaUzVsY25KdmNpZ2labTl5WTJWR2NtRnRaVkpoZEdVZ2RHRnJaWE1nWVNCd2IzTnBkR2wyWlNCcGJuUWdZbVYwZDJW'
    || 'bGJpQXdJR0Z1WkNBeE1qVXNJR1p2Y21OcGJtY2dabkpoYldVZ2NtRjBaWE1nYUdsbmFHVnlJSFJvWVc0Z01USTFJR1p3Y3lCcGN5QnViM1FnYzNWd2NHOXlk'
    || 'R1ZrSWlrNmIyVTlNRHhFUDAxaGRHZ3VabXh2YjNJb01XVXpMMFFwT2pWOUxIVXVkVzV6ZEdGaWJHVmZaMlYwUTNWeWNtVnVkRkJ5YVc5eWFYUjVUR1YyWld3'
    || 'OVpuVnVZM1JwYjI0b0tYdHlaWFIxY200Z1NIMHNkUzUxYm5OMFlXSnNaVjluWlhSR2FYSnpkRU5oYkd4aVlXTnJUbTlrWlQxbWRXNWpkR2x2YmlncGUzSmxk'
    || 'SFZ5YmlCaEtGTXBmU3gxTG5WdWMzUmhZbXhsWDI1bGVIUTlablZ1WTNScGIyNG9SQ2w3YzNkcGRHTm9LRWdwZTJOaGMyVWdNVHBqWVhObElESTZZMkZ6WlNB'
    || 'ek9uWmhjaUFrUFRNN1luSmxZV3M3WkdWbVlYVnNkRG9rUFVoOWRtRnlJRXc5U0R0SVBTUTdkSEo1ZTNKbGRIVnliaUJFS0NsOVptbHVZV3hzZVh0SVBVeDlm'
    || 'U3gxTG5WdWMzUmhZbXhsWDNCaGRYTmxSWGhsWTNWMGFXOXVQV1oxYm1OMGFXOXVLQ2w3ZlN4MUxuVnVjM1JoWW14bFgzSmxjWFZsYzNSUVlXbHVkRDFtZFc1'
    || 'amRHbHZiaWdwZTMwc2RTNTFibk4wWVdKc1pWOXlkVzVYYVhSb1VISnBiM0pwZEhrOVpuVnVZM1JwYjI0b1JDd2tLWHR6ZDJsMFkyZ29SQ2w3WTJGelpTQXhP'
    || 'bU5oYzJVZ01qcGpZWE5sSURNNlkyRnpaU0EwT21OaGMyVWdOVHBpY21WaGF6dGtaV1poZFd4ME9rUTlNMzEyWVhJZ1REMUlPMGc5UkR0MGNubDdjbVYwZFhK'
    || 'dUlDUW9LWDFtYVc1aGJHeDVlMGc5VEgxOUxIVXVkVzV6ZEdGaWJHVmZjMk5vWldSMWJHVkRZV3hzWW1GamF6MW1kVzVqZEdsdmJpaEVMQ1FzVENsN2RtRnlJ'
    || 'R2c5ZFM1MWJuTjBZV0pzWlY5dWIzY29LVHR6ZDJsMFkyZ29kSGx3Wlc5bUlFdzlQU0p2WW1wbFkzUWlKaVpNSVQwOWJuVnNiRDhvVEQxTUxtUmxiR0Y1TEV3'
    || 'OWRIbHdaVzltSUV3OVBTSnVkVzFpWlhJaUppWXdQRXcvYUN0TU9tZ3BPa3c5YUN4RUtYdGpZWE5sSURFNmRtRnlJSGM5TFRFN1luSmxZV3M3WTJGelpTQXlP'
    || 'bmM5TWpVd08ySnlaV0ZyTzJOaGMyVWdOVHAzUFRFd056TTNOREU0TWpNN1luSmxZV3M3WTJGelpTQTBPbmM5TVdVME8ySnlaV0ZyTzJSbFptRjFiSFE2ZHow'
    || 'MVpUTjljbVYwZFhKdUlIYzlUQ3QzTEVROWUybGtPbElyS3l4allXeHNZbUZqYXpva0xIQnlhVzl5YVhSNVRHVjJaV3c2UkN4emRHRnlkRlJwYldVNlRDeGxl'
    || 'SEJwY21GMGFXOXVWR2x0WlRwM0xITnZjblJKYm1SbGVEb3RNWDBzVEQ1b1B5aEVMbk52Y25SSmJtUmxlRDFNTEdNb1VTeEVLU3hoS0ZNcFBUMDliblZzYkNZ'
    || 'bVJEMDlQV0VvVVNrbUppaEtQeWgwWlNoblpTa3NaMlU5TFRFcE9rbzlJVEFzUldVb1N5eE1MV2dwS1NrNktFUXVjMjl5ZEVsdVpHVjRQWGNzWXloVExFUXBM'
    || 'R0o4ZkdWbGZId29ZajBoTUN4UlpTaHFaU2twS1N4RWZTeDFMblZ1YzNSaFlteGxYM05vYjNWc1pGbHBaV3hrUFc5dUxIVXVkVzV6ZEdGaWJHVmZkM0poY0VO'
    || 'aGJHeGlZV05yUFdaMWJtTjBhVzl1S0VRcGUzWmhjaUFrUFVnN2NtVjBkWEp1SUdaMWJtTjBhVzl1S0NsN2RtRnlJRXc5U0R0SVBTUTdkSEo1ZTNKbGRIVnli'
    || 'aUJFTG1Gd2NHeDVLSFJvYVhNc1lYSm5kVzFsYm5SektYMW1hVzVoYkd4NWUwZzlUSDE5ZlgwcEtFcHNLU2tzU214OWRtRnlJR3h6TzJaMWJtTjBhVzl1SUcx'
    || 'aktDbDdjbVYwZFhKdUlHeHpmSHdvYkhNOU1TeHhiQzVsZUhCdmNuUnpQV2hqS0NrcExIRnNMbVY0Y0c5eWRITjlMeW9xQ2lBcUlFQnNhV05sYm5ObElGSmxZ'
    || 'V04wQ2lBcUlISmxZV04wTFdSdmJTNXdjbTlrZFdOMGFXOXVMbTFwYmk1cWN3b2dLZ29nS2lCRGIzQjVjbWxuYUhRZ0tHTXBJRVpoWTJWaWIyOXJMQ0JKYm1N'
    || 'dUlHRnVaQ0JwZEhNZ1lXWm1hV3hwWVhSbGN5NEtJQ29LSUNvZ1ZHaHBjeUJ6YjNWeVkyVWdZMjlrWlNCcGN5QnNhV05sYm5ObFpDQjFibVJsY2lCMGFHVWdU'
    || 'VWxVSUd4cFkyVnVjMlVnWm05MWJtUWdhVzRnZEdobENpQXFJRXhKUTBWT1UwVWdabWxzWlNCcGJpQjBhR1VnY205dmRDQmthWEpsWTNSdmNua2diMllnZEdo'
    || 'cGN5QnpiM1Z5WTJVZ2RISmxaUzRLSUNvdmRtRnlJR2x6TzJaMWJtTjBhVzl1SUhaaktDbDdhV1lvYVhNcGNtVjBkWEp1SUNSbE8ybHpQVEU3ZG1GeUlIVTlT'
    || 'MndvS1N4alBXMWpLQ2s3Wm5WdVkzUnBiMjRnWVNobEtYdG1iM0lvZG1GeUlIUTlJbWgwZEhCek9pOHZjbVZoWTNScWN5NXZjbWN2Wkc5amN5OWxjbkp2Y2kx'
    || 'a1pXTnZaR1Z5TG1oMGJXdy9hVzUyWVhKcFlXNTBQU0lyWlN4dVBURTdianhoY21kMWJXVnVkSE11YkdWdVozUm9PMjRyS3lsMEt6MGlKbUZ5WjNOYlhUMGlL'
    || 'MlZ1WTI5a1pWVlNTVU52YlhCdmJtVnVkQ2hoY21kMWJXVnVkSE5iYmwwcE8zSmxkSFZ5YmlKTmFXNXBabWxsWkNCU1pXRmpkQ0JsY25KdmNpQWpJaXRsS3lJ'
    || 'N0lIWnBjMmwwSUNJcmRDc2lJR1p2Y2lCMGFHVWdablZzYkNCdFpYTnpZV2RsSUc5eUlIVnpaU0IwYUdVZ2JtOXVMVzFwYm1sbWFXVmtJR1JsZGlCbGJuWnBj'
    || 'bTl1YldWdWRDQm1iM0lnWm5Wc2JDQmxjbkp2Y25NZ1lXNWtJR0ZrWkdsMGFXOXVZV3dnYUdWc2NHWjFiQ0IzWVhKdWFXNW5jeTRpZlhaaGNpQnRQVzVsZHlC'
    || 'VFpYUXNSVDE3ZlR0bWRXNWpkR2x2YmlCVUtHVXNkQ2w3ZUNobExIUXBMSGdvWlNzaVEyRndkSFZ5WlNJc2RDbDlablZ1WTNScGIyNGdlQ2hsTEhRcGUyWnZj'
    || 'aWhGVzJWZFBYUXNaVDB3TzJVOGRDNXNaVzVuZEdnN1pTc3JLVzB1WVdSa0tIUmJaVjBwZlhaaGNpQnFQU0VvZEhsd1pXOW1JSGRwYm1SdmR6NGlkU0o4ZkhS'
    || 'NWNHVnZaaUIzYVc1a2IzY3VaRzlqZFcxbGJuUStJblVpZkh4MGVYQmxiMllnZDJsdVpHOTNMbVJ2WTNWdFpXNTBMbU55WldGMFpVVnNaVzFsYm5RK0luVWlL'
    || 'U3hUUFU5aWFtVmpkQzV3Y205MGIzUjVjR1V1YUdGelQzZHVVSEp2Y0dWeWRIa3NVVDB2WGxzNlFTMWFYMkV0ZWx4MU1EQkRNQzFjZFRBd1JEWmNkVEF3UkRn'
    || 'dFhIVXdNRVkyWEhVd01FWTRMVngxTURKR1JseDFNRE0zTUMxY2RUQXpOMFJjZFRBek4wWXRYSFV4UmtaR1hIVXlNREJETFZ4MU1qQXdSRngxTWpBM01DMWNk'
    || 'VEl4T0VaY2RUSkRNREF0WEhVeVJrVkdYSFV6TURBeExWeDFSRGRHUmx4MVJqa3dNQzFjZFVaRVEwWmNkVVpFUmpBdFhIVkdSa1pFWFZzNlFTMWFYMkV0ZWx4'
    || 'MU1EQkRNQzFjZFRBd1JEWmNkVEF3UkRndFhIVXdNRVkyWEhVd01FWTRMVngxTURKR1JseDFNRE0zTUMxY2RUQXpOMFJjZFRBek4wWXRYSFV4UmtaR1hIVXlN'
    || 'REJETFZ4MU1qQXdSRngxTWpBM01DMWNkVEl4T0VaY2RUSkRNREF0WEhVeVJrVkdYSFV6TURBeExWeDFSRGRHUmx4MVJqa3dNQzFjZFVaRVEwWmNkVVpFUmpB'
    || 'dFhIVkdSa1pFWEMwdU1DMDVYSFV3TUVJM1hIVXdNekF3TFZ4MU1ETTJSbHgxTWpBelJpMWNkVEl3TkRCZEtpUXZMRkk5ZTMwc2VqMTdmVHRtZFc1amRHbHZi'
    || 'aUJJS0dVcGUzSmxkSFZ5YmlCVExtTmhiR3dvZWl4bEtUOGhNRHBUTG1OaGJHd29VaXhsS1Q4aE1UcFJMblJsYzNRb1pTay9lbHRsWFQwaE1Eb29VbHRsWFQw'
    || 'aE1Dd2hNU2w5Wm5WdVkzUnBiMjRnWldVb1pTeDBMRzRzY2lsN2FXWW9iaUU5UFc1MWJHd21KbTR1ZEhsd1pUMDlQVEFwY21WMGRYSnVJVEU3YzNkcGRHTm9L'
    || 'SFI1Y0dWdlppQjBLWHRqWVhObEltWjFibU4wYVc5dUlqcGpZWE5sSW5ONWJXSnZiQ0k2Y21WMGRYSnVJVEE3WTJGelpTSmliMjlzWldGdUlqcHlaWFIxY200'
    || 'Z2NqOGhNVHB1SVQwOWJuVnNiRDhoYmk1aFkyTmxjSFJ6UW05dmJHVmhibk02S0dVOVpTNTBiMHh2ZDJWeVEyRnpaU2dwTG5Oc2FXTmxLREFzTlNrc1pTRTlQ'
    || 'U0prWVhSaExTSW1KbVVoUFQwaVlYSnBZUzBpS1R0a1pXWmhkV3gwT25KbGRIVnliaUV4ZlgxbWRXNWpkR2x2YmlCaUtHVXNkQ3h1TEhJcGUybG1LSFE5UFQx'
    || 'dWRXeHNmSHgwZVhCbGIyWWdkRDRpZFNKOGZHVmxLR1VzZEN4dUxISXBLWEpsZEhWeWJpRXdPMmxtS0hJcGNtVjBkWEp1SVRFN2FXWW9iaUU5UFc1MWJHd3Bj'
    || 'M2RwZEdOb0tHNHVkSGx3WlNsN1kyRnpaU0F6T25KbGRIVnliaUYwTzJOaGMyVWdORHB5WlhSMWNtNGdkRDA5UFNFeE8yTmhjMlVnTlRweVpYUjFjbTRnYVhO'
    || 'T1lVNG9kQ2s3WTJGelpTQTJPbkpsZEhWeWJpQnBjMDVoVGloMEtYeDhNVDUwZlhKbGRIVnliaUV4ZldaMWJtTjBhVzl1SUVvb1pTeDBMRzRzY2l4c0xHa3Nj'
    || 'eWw3ZEdocGN5NWhZMk5sY0hSelFtOXZiR1ZoYm5NOWREMDlQVEo4ZkhROVBUMHpmSHgwUFQwOU5DeDBhR2x6TG1GMGRISnBZblYwWlU1aGJXVTljaXgwYUds'
    || 'ekxtRjBkSEpwWW5WMFpVNWhiV1Z6Y0dGalpUMXNMSFJvYVhNdWJYVnpkRlZ6WlZCeWIzQmxjblI1UFc0c2RHaHBjeTV3Y205d1pYSjBlVTVoYldVOVpTeDBh'
    || 'R2x6TG5SNWNHVTlkQ3gwYUdsekxuTmhibWwwYVhwbFZWSk1QV2tzZEdocGN5NXlaVzF2ZG1WRmJYQjBlVk4wY21sdVp6MXpmWFpoY2lCSFBYdDlPeUpqYUds'
    || 'c1pISmxiaUJrWVc1blpYSnZkWE5zZVZObGRFbHVibVZ5U0ZSTlRDQmtaV1poZFd4MFZtRnNkV1VnWkdWbVlYVnNkRU5vWldOclpXUWdhVzV1WlhKSVZFMU1J'
    || 'SE4xY0hCeVpYTnpRMjl1ZEdWdWRFVmthWFJoWW14bFYyRnlibWx1WnlCemRYQndjbVZ6YzBoNVpISmhkR2x2YmxkaGNtNXBibWNnYzNSNWJHVWlMbk53Ykds'
    || 'MEtDSWdJaWt1Wm05eVJXRmphQ2htZFc1amRHbHZiaWhsS1h0SFcyVmRQVzVsZHlCS0tHVXNNQ3doTVN4bExHNTFiR3dzSVRFc0lURXBmU2tzVzFzaVlXTmpa'
    || 'WEIwUTJoaGNuTmxkQ0lzSW1GalkyVndkQzFqYUdGeWMyVjBJbDBzV3lKamJHRnpjMDVoYldVaUxDSmpiR0Z6Y3lKZExGc2lhSFJ0YkVadmNpSXNJbVp2Y2lK'
    || 'ZExGc2lhSFIwY0VWeGRXbDJJaXdpYUhSMGNDMWxjWFZwZGlKZFhTNW1iM0pGWVdOb0tHWjFibU4wYVc5dUtHVXBlM1poY2lCMFBXVmJNRjA3UjF0MFhUMXVa'
    || 'WGNnU2loMExERXNJVEVzWlZzeFhTeHVkV3hzTENFeExDRXhLWDBwTEZzaVkyOXVkR1Z1ZEVWa2FYUmhZbXhsSWl3aVpISmhaMmRoWW14bElpd2ljM0JsYkd4'
    || 'RGFHVmpheUlzSW5aaGJIVmxJbDB1Wm05eVJXRmphQ2htZFc1amRHbHZiaWhsS1h0SFcyVmRQVzVsZHlCS0tHVXNNaXdoTVN4bExuUnZURzkzWlhKRFlYTmxL'
    || 'Q2tzYm5Wc2JDd2hNU3doTVNsOUtTeGJJbUYxZEc5U1pYWmxjbk5sSWl3aVpYaDBaWEp1WVd4U1pYTnZkWEpqWlhOU1pYRjFhWEpsWkNJc0ltWnZZM1Z6WVdK'
    || 'c1pTSXNJbkJ5WlhObGNuWmxRV3h3YUdFaVhTNW1iM0pGWVdOb0tHWjFibU4wYVc5dUtHVXBlMGRiWlYwOWJtVjNJRW9vWlN3eUxDRXhMR1VzYm5Wc2JDd2hN'
    || 'U3doTVNsOUtTd2lZV3hzYjNkR2RXeHNVMk55WldWdUlHRnplVzVqSUdGMWRHOUdiMk4xY3lCaGRYUnZVR3hoZVNCamIyNTBjbTlzY3lCa1pXWmhkV3gwSUdS'
    || 'bFptVnlJR1JwYzJGaWJHVmtJR1JwYzJGaWJHVlFhV04wZFhKbFNXNVFhV04wZFhKbElHUnBjMkZpYkdWU1pXMXZkR1ZRYkdGNVltRmpheUJtYjNKdFRtOVdZ'
    || 'V3hwWkdGMFpTQm9hV1JrWlc0Z2JHOXZjQ0J1YjAxdlpIVnNaU0J1YjFaaGJHbGtZWFJsSUc5d1pXNGdjR3hoZVhOSmJteHBibVVnY21WaFpFOXViSGtnY21W'
    || 'eGRXbHlaV1FnY21WMlpYSnpaV1FnYzJOdmNHVmtJSE5sWVcxc1pYTnpJR2wwWlcxVFkyOXdaU0l1YzNCc2FYUW9JaUFpS1M1bWIzSkZZV05vS0daMWJtTjBh'
    || 'Vzl1S0dVcGUwZGJaVjA5Ym1WM0lFb29aU3d6TENFeExHVXVkRzlNYjNkbGNrTmhjMlVvS1N4dWRXeHNMQ0V4TENFeEtYMHBMRnNpWTJobFkydGxaQ0lzSW0x'
    || 'MWJIUnBjR3hsSWl3aWJYVjBaV1FpTENKelpXeGxZM1JsWkNKZExtWnZja1ZoWTJnb1puVnVZM1JwYjI0b1pTbDdSMXRsWFQxdVpYY2dTaWhsTERNc0lUQXNa'
    || 'U3h1ZFd4c0xDRXhMQ0V4S1gwcExGc2lZMkZ3ZEhWeVpTSXNJbVJ2ZDI1c2IyRmtJbDB1Wm05eVJXRmphQ2htZFc1amRHbHZiaWhsS1h0SFcyVmRQVzVsZHlC'
    || 'S0tHVXNOQ3doTVN4bExHNTFiR3dzSVRFc0lURXBmU2tzV3lKamIyeHpJaXdpY205M2N5SXNJbk5wZW1VaUxDSnpjR0Z1SWwwdVptOXlSV0ZqYUNobWRXNWpk'
    || 'R2x2YmlobEtYdEhXMlZkUFc1bGR5QktLR1VzTml3aE1TeGxMRzUxYkd3c0lURXNJVEVwZlNrc1d5SnliM2RUY0dGdUlpd2ljM1JoY25RaVhTNW1iM0pGWVdO'
    || 'b0tHWjFibU4wYVc5dUtHVXBlMGRiWlYwOWJtVjNJRW9vWlN3MUxDRXhMR1V1ZEc5TWIzZGxja05oYzJVb0tTeHVkV3hzTENFeExDRXhLWDBwTzNaaGNpQjBa'
    || 'VDB2VzF3dE9sMG9XMkV0ZWwwcEwyYzdablZ1WTNScGIyNGdVMlVvWlNsN2NtVjBkWEp1SUdWYk1WMHVkRzlWY0hCbGNrTmhjMlVvS1gwaVlXTmpaVzUwTFdo'
    || 'bGFXZG9kQ0JoYkdsbmJtMWxiblF0WW1GelpXeHBibVVnWVhKaFltbGpMV1p2Y20wZ1ltRnpaV3hwYm1VdGMyaHBablFnWTJGd0xXaGxhV2RvZENCamJHbHdM'
    || 'WEJoZEdnZ1kyeHBjQzF5ZFd4bElHTnZiRzl5TFdsdWRHVnljRzlzWVhScGIyNGdZMjlzYjNJdGFXNTBaWEp3YjJ4aGRHbHZiaTFtYVd4MFpYSnpJR052Ykc5'
    || 'eUxYQnliMlpwYkdVZ1kyOXNiM0l0Y21WdVpHVnlhVzVuSUdSdmJXbHVZVzUwTFdKaGMyVnNhVzVsSUdWdVlXSnNaUzFpWVdOclozSnZkVzVrSUdacGJHd3Ri'
    || 'M0JoWTJsMGVTQm1hV3hzTFhKMWJHVWdabXh2YjJRdFkyOXNiM0lnWm14dmIyUXRiM0JoWTJsMGVTQm1iMjUwTFdaaGJXbHNlU0JtYjI1MExYTnBlbVVnWm05'
    || 'dWRDMXphWHBsTFdGa2FuVnpkQ0JtYjI1MExYTjBjbVYwWTJnZ1ptOXVkQzF6ZEhsc1pTQm1iMjUwTFhaaGNtbGhiblFnWm05dWRDMTNaV2xuYUhRZ1oyeDVj'
    || 'R2d0Ym1GdFpTQm5iSGx3YUMxdmNtbGxiblJoZEdsdmJpMW9iM0pwZW05dWRHRnNJR2RzZVhCb0xXOXlhV1Z1ZEdGMGFXOXVMWFpsY25ScFkyRnNJR2h2Y21s'
    || 'NkxXRmtkaTE0SUdodmNtbDZMVzl5YVdkcGJpMTRJR2x0WVdkbExYSmxibVJsY21sdVp5QnNaWFIwWlhJdGMzQmhZMmx1WnlCc2FXZG9kR2x1WnkxamIyeHZj'
    || 'aUJ0WVhKclpYSXRaVzVrSUcxaGNtdGxjaTF0YVdRZ2JXRnlhMlZ5TFhOMFlYSjBJRzkyWlhKc2FXNWxMWEJ2YzJsMGFXOXVJRzkyWlhKc2FXNWxMWFJvYVdO'
    || 'cmJtVnpjeUJ3WVdsdWRDMXZjbVJsY2lCd1lXNXZjMlV0TVNCd2IybHVkR1Z5TFdWMlpXNTBjeUJ5Wlc1a1pYSnBibWN0YVc1MFpXNTBJSE5vWVhCbExYSmxi'
    || 'bVJsY21sdVp5QnpkRzl3TFdOdmJHOXlJSE4wYjNBdGIzQmhZMmwwZVNCemRISnBhMlYwYUhKdmRXZG9MWEJ2YzJsMGFXOXVJSE4wY21sclpYUm9jbTkxWjJn'
    || 'dGRHaHBZMnR1WlhOeklITjBjbTlyWlMxa1lYTm9ZWEp5WVhrZ2MzUnliMnRsTFdSaGMyaHZabVp6WlhRZ2MzUnliMnRsTFd4cGJtVmpZWEFnYzNSeWIydGxM'
    || 'V3hwYm1WcWIybHVJSE4wY205clpTMXRhWFJsY214cGJXbDBJSE4wY205clpTMXZjR0ZqYVhSNUlITjBjbTlyWlMxM2FXUjBhQ0IwWlhoMExXRnVZMmh2Y2lC'
    || 'MFpYaDBMV1JsWTI5eVlYUnBiMjRnZEdWNGRDMXlaVzVrWlhKcGJtY2dkVzVrWlhKc2FXNWxMWEJ2YzJsMGFXOXVJSFZ1WkdWeWJHbHVaUzEwYUdsamEyNWxj'
    || 'M01nZFc1cFkyOWtaUzFpYVdScElIVnVhV052WkdVdGNtRnVaMlVnZFc1cGRITXRjR1Z5TFdWdElIWXRZV3h3YUdGaVpYUnBZeUIyTFdoaGJtZHBibWNnZGkx'
    || 'cFpHVnZaM0poY0docFl5QjJMVzFoZEdobGJXRjBhV05oYkNCMlpXTjBiM0l0WldabVpXTjBJSFpsY25RdFlXUjJMWGtnZG1WeWRDMXZjbWxuYVc0dGVDQjJa'
    || 'WEowTFc5eWFXZHBiaTE1SUhkdmNtUXRjM0JoWTJsdVp5QjNjbWwwYVc1bkxXMXZaR1VnZUcxc2JuTTZlR3hwYm1zZ2VDMW9aV2xuYUhRaUxuTndiR2wwS0NJ'
    || 'Z0lpa3VabTl5UldGamFDaG1kVzVqZEdsdmJpaGxLWHQyWVhJZ2REMWxMbkpsY0d4aFkyVW9kR1VzVTJVcE8wZGJkRjA5Ym1WM0lFb29kQ3d4TENFeExHVXNi'
    || 'blZzYkN3aE1Td2hNU2w5S1N3aWVHeHBibXM2WVdOMGRXRjBaU0I0YkdsdWF6cGhjbU55YjJ4bElIaHNhVzVyT25KdmJHVWdlR3hwYm1zNmMyaHZkeUI0Ykds'
    || 'dWF6cDBhWFJzWlNCNGJHbHVhenAwZVhCbElpNXpjR3hwZENnaUlDSXBMbVp2Y2tWaFkyZ29ablZ1WTNScGIyNG9aU2w3ZG1GeUlIUTlaUzV5WlhCc1lXTmxL'
    || 'SFJsTEZObEtUdEhXM1JkUFc1bGR5QktLSFFzTVN3aE1TeGxMQ0pvZEhSd09pOHZkM2QzTG5jekxtOXlaeTh4T1RrNUwzaHNhVzVySWl3aE1Td2hNU2w5S1N4'
    || 'YkluaHRiRHBpWVhObElpd2llRzFzT214aGJtY2lMQ0o0Yld3NmMzQmhZMlVpWFM1bWIzSkZZV05vS0daMWJtTjBhVzl1S0dVcGUzWmhjaUIwUFdVdWNtVndi'
    || 'R0ZqWlNoMFpTeFRaU2s3UjF0MFhUMXVaWGNnU2loMExERXNJVEVzWlN3aWFIUjBjRG92TDNkM2R5NTNNeTV2Y21jdldFMU1MekU1T1RndmJtRnRaWE53WVdO'
    || 'bElpd2hNU3doTVNsOUtTeGJJblJoWWtsdVpHVjRJaXdpWTNKdmMzTlBjbWxuYVc0aVhTNW1iM0pGWVdOb0tHWjFibU4wYVc5dUtHVXBlMGRiWlYwOWJtVjNJ'
    || 'RW9vWlN3eExDRXhMR1V1ZEc5TWIzZGxja05oYzJVb0tTeHVkV3hzTENFeExDRXhLWDBwTEVjdWVHeHBibXRJY21WbVBXNWxkeUJLS0NKNGJHbHVhMGh5WldZ'
    || 'aUxERXNJVEVzSW5oc2FXNXJPbWh5WldZaUxDSm9kSFJ3T2k4dmQzZDNMbmN6TG05eVp5OHhPVGs1TDNoc2FXNXJJaXdoTUN3aE1Ta3NXeUp6Y21NaUxDSm9j'
    || 'bVZtSWl3aVlXTjBhVzl1SWl3aVptOXliVUZqZEdsdmJpSmRMbVp2Y2tWaFkyZ29ablZ1WTNScGIyNG9aU2w3UjF0bFhUMXVaWGNnU2lobExERXNJVEVzWlM1'
    || 'MGIweHZkMlZ5UTJGelpTZ3BMRzUxYkd3c0lUQXNJVEFwZlNrN1puVnVZM1JwYjI0Z1FpaGxMSFFzYml4eUtYdDJZWElnYkQxSExtaGhjMDkzYmxCeWIzQmxj'
    || 'blI1S0hRcFAwZGJkRjA2Ym5Wc2JEc29iQ0U5UFc1MWJHdy9iQzUwZVhCbElUMDlNRHB5Zkh3aEtESThkQzVzWlc1bmRHZ3BmSHgwV3pCZElUMDlJbThpSmla'
    || 'MFd6QmRJVDA5SWs4aWZIeDBXekZkSVQwOUltNGlKaVowV3pGZElUMDlJazRpS1NZbUtHSW9kQ3h1TEd3c2Npa21KaWh1UFc1MWJHd3BMSEo4Zkd3OVBUMXVk'
    || 'V3hzUDBnb2RDa21KaWh1UFQwOWJuVnNiRDlsTG5KbGJXOTJaVUYwZEhKcFluVjBaU2gwS1RwbExuTmxkRUYwZEhKcFluVjBaU2gwTENJaUsyNHBLVHBzTG0x'
    || 'MWMzUlZjMlZRY205d1pYSjBlVDlsVzJ3dWNISnZjR1Z5ZEhsT1lXMWxYVDF1UFQwOWJuVnNiRDlzTG5SNWNHVTlQVDB6UHlFeE9pSWlPbTQ2S0hROWJDNWhk'
    || 'SFJ5YVdKMWRHVk9ZVzFsTEhJOWJDNWhkSFJ5YVdKMWRHVk9ZVzFsYzNCaFkyVXNiajA5UFc1MWJHdy9aUzV5WlcxdmRtVkJkSFJ5YVdKMWRHVW9kQ2s2S0d3'
    || 'OWJDNTBlWEJsTEc0OWJEMDlQVE44Zkd3OVBUMDBKaVp1UFQwOUlUQS9JaUk2SWlJcmJpeHlQMlV1YzJWMFFYUjBjbWxpZFhSbFRsTW9jaXgwTEc0cE9tVXVj'
    || 'MlYwUVhSMGNtbGlkWFJsS0hRc2Jpa3BLU2w5ZG1GeUlFczlkUzVmWDFORlExSkZWRjlKVGxSRlVrNUJURk5mUkU5ZlRrOVVYMVZUUlY5UFVsOVpUMVZmVjBs'
    || 'TVRGOUNSVjlHU1ZKRlJDeHFaVDFUZVcxaWIyd3VabTl5S0NKeVpXRmpkQzVsYkdWdFpXNTBJaWtzWVdVOVUzbHRZbTlzTG1admNpZ2ljbVZoWTNRdWNHOXlk'
    || 'R0ZzSWlrc1kyVTlVM2x0WW05c0xtWnZjaWdpY21WaFkzUXVabkpoWjIxbGJuUWlLU3huWlQxVGVXMWliMnd1Wm05eUtDSnlaV0ZqZEM1emRISnBZM1JmYlc5'
    || 'a1pTSXBMRzlsUFZONWJXSnZiQzVtYjNJb0luSmxZV04wTG5CeWIyWnBiR1Z5SWlrc2JIUTlVM2x0WW05c0xtWnZjaWdpY21WaFkzUXVjSEp2ZG1sa1pYSWlL'
    || 'U3h2YmoxVGVXMWliMnd1Wm05eUtDSnlaV0ZqZEM1amIyNTBaWGgwSWlrc1gzUTlVM2x0WW05c0xtWnZjaWdpY21WaFkzUXVabTl5ZDJGeVpGOXlaV1lpS1N4'
    || 'S1pUMVRlVzFpYjJ3dVptOXlLQ0p5WldGamRDNXpkWE53Wlc1elpTSXBMR1owUFZONWJXSnZiQzVtYjNJb0luSmxZV04wTG5OMWMzQmxibk5sWDJ4cGMzUWlL'
    || 'U3hUZEQxVGVXMWliMnd1Wm05eUtDSnlaV0ZqZEM1dFpXMXZJaWtzVVdVOVUzbHRZbTlzTG1admNpZ2ljbVZoWTNRdWJHRjZlU0lwTEVWbFBWTjViV0p2YkM1'
    || 'bWIzSW9JbkpsWVdOMExtOW1abk5qY21WbGJpSXBMRVE5VTNsdFltOXNMbWwwWlhKaGRHOXlPMloxYm1OMGFXOXVJQ1FvWlNsN2NtVjBkWEp1SUdVOVBUMXVk'
    || 'V3hzZkh4MGVYQmxiMllnWlNFOUltOWlhbVZqZENJL2JuVnNiRG9vWlQxRUppWmxXMFJkZkh4bFd5SkFRR2wwWlhKaGRHOXlJbDBzZEhsd1pXOW1JR1U5UFNK'
    || 'bWRXNWpkR2x2YmlJL1pUcHVkV3hzS1gxMllYSWdURDFQWW1wbFkzUXVZWE56YVdkdUxHZzdablZ1WTNScGIyNGdkeWhsS1h0cFppaG9QVDA5ZG05cFpDQXdL'
    || 'WFJ5ZVh0MGFISnZkeUJGY25KdmNpZ3BmV05oZEdOb0tHNHBlM1poY2lCMFBXNHVjM1JoWTJzdWRISnBiU2dwTG0xaGRHTm9LQzljYmlnZ0tpaGhkQ0FwUHlr'
    || 'dktUdG9QWFFtSm5SYk1WMThmQ0lpZlhKbGRIVnlibUFLWUN0b0syVjlkbUZ5SUZnOUlURTdablZ1WTNScGIyNGdjU2hsTEhRcGUybG1LQ0ZsZkh4WUtYSmxk'
    || 'SFZ5YmlJaU8xZzlJVEE3ZG1GeUlHNDlSWEp5YjNJdWNISmxjR0Z5WlZOMFlXTnJWSEpoWTJVN1JYSnliM0l1Y0hKbGNHRnlaVk4wWVdOclZISmhZMlU5ZG05'
    || 'cFpDQXdPM1J5ZVh0cFppaDBLV2xtS0hROVpuVnVZM1JwYjI0b0tYdDBhSEp2ZHlCRmNuSnZjaWdwZlN4UFltcGxZM1F1WkdWbWFXNWxVSEp2Y0dWeWRIa29k'
    || 'QzV3Y205MGIzUjVjR1VzSW5CeWIzQnpJaXg3YzJWME9tWjFibU4wYVc5dUtDbDdkR2h5YjNjZ1JYSnliM0lvS1gxOUtTeDBlWEJsYjJZZ1VtVm1iR1ZqZEQw'
    || 'OUltOWlhbVZqZENJbUpsSmxabXhsWTNRdVkyOXVjM1J5ZFdOMEtYdDBjbmw3VW1WbWJHVmpkQzVqYjI1emRISjFZM1FvZEN4YlhTbDlZMkYwWTJnb2VTbDdk'
    || 'bUZ5SUhJOWVYMVNaV1pzWldOMExtTnZibk4wY25WamRDaGxMRnRkTEhRcGZXVnNjMlY3ZEhKNWUzUXVZMkZzYkNncGZXTmhkR05vS0hrcGUzSTllWDFsTG1O'
    || 'aGJHd29kQzV3Y205MGIzUjVjR1VwZldWc2MyVjdkSEo1ZTNSb2NtOTNJRVZ5Y205eUtDbDlZMkYwWTJnb2VTbDdjajE1ZldVb0tYMTlZMkYwWTJnb2VTbDdh'
    || 'V1lvZVNZbWNpWW1kSGx3Wlc5bUlIa3VjM1JoWTJzOVBTSnpkSEpwYm1jaUtYdG1iM0lvZG1GeUlHdzllUzV6ZEdGamF5NXpjR3hwZENoZ0NtQXBMR2s5Y2k1'
    || 'emRHRmpheTV6Y0d4cGRDaGdDbUFwTEhNOWJDNXNaVzVuZEdndE1TeGtQV2t1YkdWdVozUm9MVEU3TVR3OWN5WW1NRHc5WkNZbWJGdHpYU0U5UFdsYlpGMDdL'
    || 'V1F0TFR0bWIzSW9PekU4UFhNbUpqQThQV1E3Y3kwdExHUXRMU2xwWmloc1czTmRJVDA5YVZ0a1hTbDdhV1lvY3lFOVBURjhmR1FoUFQweEtXUnZJR2xtS0hN'
    || 'dExTeGtMUzBzTUQ1a2ZIeHNXM05kSVQwOWFWdGtYU2w3ZG1GeUlHWTlZQXBnSzJ4YmMxMHVjbVZ3YkdGalpTZ2lJR0YwSUc1bGR5QWlMQ0lnWVhRZ0lpazdj'
    || 'bVYwZFhKdUlHVXVaR2x6Y0d4aGVVNWhiV1VtSm1ZdWFXNWpiSFZrWlhNb0lqeGhibTl1ZVcxdmRYTStJaWttSmlobVBXWXVjbVZ3YkdGalpTZ2lQR0Z1YjI1'
    || 'NWJXOTFjejRpTEdVdVpHbHpjR3hoZVU1aGJXVXBLU3htZlhkb2FXeGxLREU4UFhNbUpqQThQV1FwTzJKeVpXRnJmWDE5Wm1sdVlXeHNlWHRZUFNFeExFVnlj'
    || 'bTl5TG5CeVpYQmhjbVZUZEdGamExUnlZV05sUFc1OWNtVjBkWEp1S0dVOVpUOWxMbVJwYzNCc1lYbE9ZVzFsZkh4bExtNWhiV1U2SWlJcFAzY29aU2s2SWlK'
    || 'OVpuVnVZM1JwYjI0Z2NtVW9aU2w3YzNkcGRHTm9LR1V1ZEdGbktYdGpZWE5sSURVNmNtVjBkWEp1SUhjb1pTNTBlWEJsS1R0allYTmxJREUyT25KbGRIVnli'
    || 'aUIzS0NKTVlYcDVJaWs3WTJGelpTQXhNenB5WlhSMWNtNGdkeWdpVTNWemNHVnVjMlVpS1R0allYTmxJREU1T25KbGRIVnliaUIzS0NKVGRYTndaVzV6WlV4'
    || 'cGMzUWlLVHRqWVhObElEQTZZMkZ6WlNBeU9tTmhjMlVnTVRVNmNtVjBkWEp1SUdVOWNTaGxMblI1Y0dVc0lURXBMR1U3WTJGelpTQXhNVHB5WlhSMWNtNGda'
    || 'VDF4S0dVdWRIbHdaUzV5Wlc1a1pYSXNJVEVwTEdVN1kyRnpaU0F4T25KbGRIVnliaUJsUFhFb1pTNTBlWEJsTENFd0tTeGxPMlJsWm1GMWJIUTZjbVYwZFhK'
    || 'dUlpSjlmV1oxYm1OMGFXOXVJR3hsS0dVcGUybG1LR1U5UFc1MWJHd3BjbVYwZFhKdUlHNTFiR3c3YVdZb2RIbHdaVzltSUdVOVBTSm1kVzVqZEdsdmJpSXBj'
    || 'bVYwZFhKdUlHVXVaR2x6Y0d4aGVVNWhiV1Y4ZkdVdWJtRnRaWHg4Ym5Wc2JEdHBaaWgwZVhCbGIyWWdaVDA5SW5OMGNtbHVaeUlwY21WMGRYSnVJR1U3YzNk'
    || 'cGRHTm9LR1VwZTJOaGMyVWdZMlU2Y21WMGRYSnVJa1p5WVdkdFpXNTBJanRqWVhObElHRmxPbkpsZEhWeWJpSlFiM0owWVd3aU8yTmhjMlVnYjJVNmNtVjBk'
    || 'WEp1SWxCeWIyWnBiR1Z5SWp0allYTmxJR2RsT25KbGRIVnliaUpUZEhKcFkzUk5iMlJsSWp0allYTmxJRXBsT25KbGRIVnliaUpUZFhOd1pXNXpaU0k3WTJG'
    || 'elpTQm1kRHB5WlhSMWNtNGlVM1Z6Y0dWdWMyVk1hWE4wSW4xcFppaDBlWEJsYjJZZ1pUMDlJbTlpYW1WamRDSXBjM2RwZEdOb0tHVXVKQ1IwZVhCbGIyWXBl'
    || 'Mk5oYzJVZ2IyNDZjbVYwZFhKdUtHVXVaR2x6Y0d4aGVVNWhiV1Y4ZkNKRGIyNTBaWGgwSWlrcklpNURiMjV6ZFcxbGNpSTdZMkZ6WlNCc2REcHlaWFIxY200'
    || 'b1pTNWZZMjl1ZEdWNGRDNWthWE53YkdGNVRtRnRaWHg4SWtOdmJuUmxlSFFpS1NzaUxsQnliM1pwWkdWeUlqdGpZWE5sSUY5ME9uWmhjaUIwUFdVdWNtVnVa'
    || 'R1Z5TzNKbGRIVnliaUJsUFdVdVpHbHpjR3hoZVU1aGJXVXNaWHg4S0dVOWRDNWthWE53YkdGNVRtRnRaWHg4ZEM1dVlXMWxmSHdpSWl4bFBXVWhQVDBpSWo4'
    || 'aVJtOXlkMkZ5WkZKbFppZ2lLMlVySWlraU9pSkdiM0ozWVhKa1VtVm1JaWtzWlR0allYTmxJRk4wT25KbGRIVnliaUIwUFdVdVpHbHpjR3hoZVU1aGJXVjhm'
    || 'RzUxYkd3c2RDRTlQVzUxYkd3L2REcHNaU2hsTG5SNWNHVXBmSHdpVFdWdGJ5STdZMkZ6WlNCUlpUcDBQV1V1WDNCaGVXeHZZV1FzWlQxbExsOXBibWwwTzNS'
    || 'eWVYdHlaWFIxY200Z2JHVW9aU2gwS1NsOVkyRjBZMmg3ZlgxeVpYUjFjbTRnYm5Wc2JIMW1kVzVqZEdsdmJpQmtaU2hsS1h0MllYSWdkRDFsTG5SNWNHVTdj'
    || 'M2RwZEdOb0tHVXVkR0ZuS1h0allYTmxJREkwT25KbGRIVnliaUpEWVdOb1pTSTdZMkZ6WlNBNU9uSmxkSFZ5YmloMExtUnBjM0JzWVhsT1lXMWxmSHdpUTI5'
    || 'dWRHVjRkQ0lwS3lJdVEyOXVjM1Z0WlhJaU8yTmhjMlVnTVRBNmNtVjBkWEp1S0hRdVgyTnZiblJsZUhRdVpHbHpjR3hoZVU1aGJXVjhmQ0pEYjI1MFpYaDBJ'
    || 'aWtySWk1UWNtOTJhV1JsY2lJN1kyRnpaU0F4T0RweVpYUjFjbTRpUkdWb2VXUnlZWFJsWkVaeVlXZHRaVzUwSWp0allYTmxJREV4T25KbGRIVnliaUJsUFhR'
    || 'dWNtVnVaR1Z5TEdVOVpTNWthWE53YkdGNVRtRnRaWHg4WlM1dVlXMWxmSHdpSWl4MExtUnBjM0JzWVhsT1lXMWxmSHdvWlNFOVBTSWlQeUpHYjNKM1lYSmtV'
    || 'bVZtS0NJclpTc2lLU0k2SWtadmNuZGhjbVJTWldZaUtUdGpZWE5sSURjNmNtVjBkWEp1SWtaeVlXZHRaVzUwSWp0allYTmxJRFU2Y21WMGRYSnVJSFE3WTJG'
    || 'elpTQTBPbkpsZEhWeWJpSlFiM0owWVd3aU8yTmhjMlVnTXpweVpYUjFjbTRpVW05dmRDSTdZMkZ6WlNBMk9uSmxkSFZ5YmlKVVpYaDBJanRqWVhObElERTJP'
    || 'bkpsZEhWeWJpQnNaU2gwS1R0allYTmxJRGc2Y21WMGRYSnVJSFE5UFQxblpUOGlVM1J5YVdOMFRXOWtaU0k2SWsxdlpHVWlPMk5oYzJVZ01qSTZjbVYwZFhK'
    || 'dUlrOW1abk5qY21WbGJpSTdZMkZ6WlNBeE1qcHlaWFIxY200aVVISnZabWxzWlhJaU8yTmhjMlVnTWpFNmNtVjBkWEp1SWxOamIzQmxJanRqWVhObElERXpP'
    || 'bkpsZEhWeWJpSlRkWE53Wlc1elpTSTdZMkZ6WlNBeE9UcHlaWFIxY200aVUzVnpjR1Z1YzJWTWFYTjBJanRqWVhObElESTFPbkpsZEhWeWJpSlVjbUZqYVc1'
    || 'blRXRnlhMlZ5SWp0allYTmxJREU2WTJGelpTQXdPbU5oYzJVZ01UYzZZMkZ6WlNBeU9tTmhjMlVnTVRRNlkyRnpaU0F4TlRwcFppaDBlWEJsYjJZZ2REMDlJ'
    || 'bVoxYm1OMGFXOXVJaWx5WlhSMWNtNGdkQzVrYVhOd2JHRjVUbUZ0Wlh4OGRDNXVZVzFsZkh4dWRXeHNPMmxtS0hSNWNHVnZaaUIwUFQwaWMzUnlhVzVuSWls'
    || 'eVpYUjFjbTRnZEgxeVpYUjFjbTRnYm5Wc2JIMW1kVzVqZEdsdmJpQnpaU2hsS1h0emQybDBZMmdvZEhsd1pXOW1JR1VwZTJOaGMyVWlZbTl2YkdWaGJpSTZZ'
    || 'MkZ6WlNKdWRXMWlaWElpT21OaGMyVWljM1J5YVc1bklqcGpZWE5sSW5WdVpHVm1hVzVsWkNJNmNtVjBkWEp1SUdVN1kyRnpaU0p2WW1wbFkzUWlPbkpsZEhW'
    || 'eWJpQmxPMlJsWm1GMWJIUTZjbVYwZFhKdUlpSjlmV1oxYm1OMGFXOXVJRzFsS0dVcGUzWmhjaUIwUFdVdWRIbHdaVHR5WlhSMWNtNG9aVDFsTG01dlpHVk9Z'
    || 'VzFsS1NZbVpTNTBiMHh2ZDJWeVEyRnpaU2dwUFQwOUltbHVjSFYwSWlZbUtIUTlQVDBpWTJobFkydGliM2dpZkh4MFBUMDlJbkpoWkdsdklpbDlablZ1WTNS'
    || 'cGIyNGdZbVVvWlNsN2RtRnlJSFE5YldVb1pTay9JbU5vWldOclpXUWlPaUoyWVd4MVpTSXNiajFQWW1wbFkzUXVaMlYwVDNkdVVISnZjR1Z5ZEhsRVpYTmpj'
    || 'bWx3ZEc5eUtHVXVZMjl1YzNSeWRXTjBiM0l1Y0hKdmRHOTBlWEJsTEhRcExISTlJaUlyWlZ0MFhUdHBaaWdoWlM1b1lYTlBkMjVRY205d1pYSjBlU2gwS1NZ'
    || 'bWRIbHdaVzltSUc0OEluVWlKaVowZVhCbGIyWWdiaTVuWlhROVBTSm1kVzVqZEdsdmJpSW1KblI1Y0dWdlppQnVMbk5sZEQwOUltWjFibU4wYVc5dUlpbDdk'
    || 'bUZ5SUd3OWJpNW5aWFFzYVQxdUxuTmxkRHR5WlhSMWNtNGdUMkpxWldOMExtUmxabWx1WlZCeWIzQmxjblI1S0dVc2RDeDdZMjl1Wm1sbmRYSmhZbXhsT2lF'
    || 'd0xHZGxkRHBtZFc1amRHbHZiaWdwZTNKbGRIVnliaUJzTG1OaGJHd29kR2hwY3lsOUxITmxkRHBtZFc1amRHbHZiaWh6S1h0eVBTSWlLM01zYVM1allXeHNL'
    || 'SFJvYVhNc2N5bDlmU2tzVDJKcVpXTjBMbVJsWm1sdVpWQnliM0JsY25SNUtHVXNkQ3g3Wlc1MWJXVnlZV0pzWlRwdUxtVnVkVzFsY21GaWJHVjlLU3g3WjJW'
    || 'MFZtRnNkV1U2Wm5WdVkzUnBiMjRvS1h0eVpYUjFjbTRnY24wc2MyVjBWbUZzZFdVNlpuVnVZM1JwYjI0b2N5bDdjajBpSWl0emZTeHpkRzl3VkhKaFkydHBi'
    || 'bWM2Wm5WdVkzUnBiMjRvS1h0bExsOTJZV3gxWlZSeVlXTnJaWEk5Ym5Wc2JDeGtaV3hsZEdVZ1pWdDBYWDE5ZlgxbWRXNWpkR2x2YmlCTmNpaGxLWHRsTGw5'
    || 'MllXeDFaVlJ5WVdOclpYSjhmQ2hsTGw5MllXeDFaVlJ5WVdOclpYSTlZbVVvWlNrcGZXWjFibU4wYVc5dUlIWnpLR1VwZTJsbUtDRmxLWEpsZEhWeWJpRXhP'
    || 'M1poY2lCMFBXVXVYM1poYkhWbFZISmhZMnRsY2p0cFppZ2hkQ2x5WlhSMWNtNGhNRHQyWVhJZ2JqMTBMbWRsZEZaaGJIVmxLQ2tzY2owaUlqdHlaWFIxY200'
    || 'Z1pTWW1LSEk5YldVb1pTay9aUzVqYUdWamEyVmtQeUowY25WbElqb2labUZzYzJVaU9tVXVkbUZzZFdVcExHVTljaXhsSVQwOWJqOG9kQzV6WlhSV1lXeDFa'
    || 'U2hsS1N3aE1DazZJVEY5Wm5WdVkzUnBiMjRnZW5Jb1pTbDdhV1lvWlQxbGZId29kSGx3Wlc5bUlHUnZZM1Z0Wlc1MFBDSjFJajlrYjJOMWJXVnVkRHAyYjJs'
    || 'a0lEQXBMSFI1Y0dWdlppQmxQaUoxSWlseVpYUjFjbTRnYm5Wc2JEdDBjbmw3Y21WMGRYSnVJR1V1WVdOMGFYWmxSV3hsYldWdWRIeDhaUzVpYjJSNWZXTmhk'
    || 'R05vZTNKbGRIVnliaUJsTG1KdlpIbDlmV1oxYm1OMGFXOXVJR2xwS0dVc2RDbDdkbUZ5SUc0OWRDNWphR1ZqYTJWa08zSmxkSFZ5YmlCTUtIdDlMSFFzZTJS'
    || 'bFptRjFiSFJEYUdWamEyVmtPblp2YVdRZ01DeGtaV1poZFd4MFZtRnNkV1U2ZG05cFpDQXdMSFpoYkhWbE9uWnZhV1FnTUN4amFHVmphMlZrT200L1AyVXVY'
    || 'M2R5WVhCd1pYSlRkR0YwWlM1cGJtbDBhV0ZzUTJobFkydGxaSDBwZldaMWJtTjBhVzl1SUdkektHVXNkQ2w3ZG1GeUlHNDlkQzVrWldaaGRXeDBWbUZzZFdV'
    || 'OVBXNTFiR3cvSWlJNmRDNWtaV1poZFd4MFZtRnNkV1VzY2oxMExtTm9aV05yWldRaFBXNTFiR3cvZEM1amFHVmphMlZrT25RdVpHVm1ZWFZzZEVOb1pXTnJa'
    || 'V1E3YmoxelpTaDBMblpoYkhWbElUMXVkV3hzUDNRdWRtRnNkV1U2Ymlrc1pTNWZkM0poY0hCbGNsTjBZWFJsUFh0cGJtbDBhV0ZzUTJobFkydGxaRHB5TEds'
    || 'dWFYUnBZV3hXWVd4MVpUcHVMR052Ym5SeWIyeHNaV1E2ZEM1MGVYQmxQVDA5SW1Ob1pXTnJZbTk0SW54OGRDNTBlWEJsUFQwOUluSmhaR2x2SWo5MExtTm9a'
    || 'V05yWldRaFBXNTFiR3c2ZEM1MllXeDFaU0U5Ym5Wc2JIMTlablZ1WTNScGIyNGdlWE1vWlN4MEtYdDBQWFF1WTJobFkydGxaQ3gwSVQxdWRXeHNKaVpDS0dV'
    || 'c0ltTm9aV05yWldRaUxIUXNJVEVwZldaMWJtTjBhVzl1SUc5cEtHVXNkQ2w3ZVhNb1pTeDBLVHQyWVhJZ2JqMXpaU2gwTG5aaGJIVmxLU3h5UFhRdWRIbHda'
    || 'VHRwWmlodUlUMXVkV3hzS1hJOVBUMGliblZ0WW1WeUlqOG9iajA5UFRBbUptVXVkbUZzZFdVOVBUMGlJbng4WlM1MllXeDFaU0U5YmlrbUppaGxMblpoYkhW'
    || 'bFBTSWlLMjRwT21VdWRtRnNkV1VoUFQwaUlpdHVKaVlvWlM1MllXeDFaVDBpSWl0dUtUdGxiSE5sSUdsbUtISTlQVDBpYzNWaWJXbDBJbng4Y2owOVBTSnla'
    || 'WE5sZENJcGUyVXVjbVZ0YjNabFFYUjBjbWxpZFhSbEtDSjJZV3gxWlNJcE8zSmxkSFZ5Ym4xMExtaGhjMDkzYmxCeWIzQmxjblI1S0NKMllXeDFaU0lwUDNO'
    || 'cEtHVXNkQzUwZVhCbExHNHBPblF1YUdGelQzZHVVSEp2Y0dWeWRIa29JbVJsWm1GMWJIUldZV3gxWlNJcEppWnphU2hsTEhRdWRIbHdaU3h6WlNoMExtUmxa'
    || 'bUYxYkhSV1lXeDFaU2twTEhRdVkyaGxZMnRsWkQwOWJuVnNiQ1ltZEM1a1pXWmhkV3gwUTJobFkydGxaQ0U5Ym5Wc2JDWW1LR1V1WkdWbVlYVnNkRU5vWldO'
    || 'clpXUTlJU0YwTG1SbFptRjFiSFJEYUdWamEyVmtLWDFtZFc1amRHbHZiaUI0Y3lobExIUXNiaWw3YVdZb2RDNW9ZWE5QZDI1UWNtOXdaWEowZVNnaWRtRnNk'
    || 'V1VpS1h4OGRDNW9ZWE5QZDI1UWNtOXdaWEowZVNnaVpHVm1ZWFZzZEZaaGJIVmxJaWtwZTNaaGNpQnlQWFF1ZEhsd1pUdHBaaWdoS0hJaFBUMGljM1ZpYlds'
    || 'MElpWW1jaUU5UFNKeVpYTmxkQ0o4ZkhRdWRtRnNkV1VoUFQxMmIybGtJREFtSm5RdWRtRnNkV1VoUFQxdWRXeHNLU2x5WlhSMWNtNDdkRDBpSWl0bExsOTNj'
    || 'bUZ3Y0dWeVUzUmhkR1V1YVc1cGRHbGhiRlpoYkhWbExHNThmSFE5UFQxbExuWmhiSFZsZkh3b1pTNTJZV3gxWlQxMEtTeGxMbVJsWm1GMWJIUldZV3gxWlQx'
    || 'MGZXNDlaUzV1WVcxbExHNGhQVDBpSWlZbUtHVXVibUZ0WlQwaUlpa3NaUzVrWldaaGRXeDBRMmhsWTJ0bFpEMGhJV1V1WDNkeVlYQndaWEpUZEdGMFpTNXBi'
    || 'bWwwYVdGc1EyaGxZMnRsWkN4dUlUMDlJaUltSmlobExtNWhiV1U5YmlsOVpuVnVZM1JwYjI0Z2Mya29aU3gwTEc0cGV5aDBJVDA5SW01MWJXSmxjaUo4Zkhw'
    || 'eUtHVXViM2R1WlhKRWIyTjFiV1Z1ZENraFBUMWxLU1ltS0c0OVBXNTFiR3cvWlM1a1pXWmhkV3gwVm1Gc2RXVTlJaUlyWlM1ZmQzSmhjSEJsY2xOMFlYUmxM'
    || 'bWx1YVhScFlXeFdZV3gxWlRwbExtUmxabUYxYkhSV1lXeDFaU0U5UFNJaUsyNG1KaWhsTG1SbFptRjFiSFJXWVd4MVpUMGlJaXR1S1NsOWRtRnlJRWR1UFVG'
    || 'eWNtRjVMbWx6UVhKeVlYazdablZ1WTNScGIyNGdYMjRvWlN4MExHNHNjaWw3YVdZb1pUMWxMbTl3ZEdsdmJuTXNkQ2w3ZEQxN2ZUdG1iM0lvZG1GeUlHdzlN'
    || 'RHRzUEc0dWJHVnVaM1JvTzJ3ckt5bDBXeUlrSWl0dVcyeGRYVDBoTUR0bWIzSW9iajB3TzI0OFpTNXNaVzVuZEdnN2Jpc3JLV3c5ZEM1b1lYTlBkMjVRY205'
    || 'd1pYSjBlU2dpSkNJclpWdHVYUzUyWVd4MVpTa3NaVnR1WFM1elpXeGxZM1JsWkNFOVBXd21KaWhsVzI1ZExuTmxiR1ZqZEdWa1BXd3BMR3dtSm5JbUppaGxX'
    || 'MjVkTG1SbFptRjFiSFJUWld4bFkzUmxaRDBoTUNsOVpXeHpaWHRtYjNJb2JqMGlJaXR6WlNodUtTeDBQVzUxYkd3c2JEMHdPMnc4WlM1c1pXNW5kR2c3YkNz'
    || 'cktYdHBaaWhsVzJ4ZExuWmhiSFZsUFQwOWJpbDdaVnRzWFM1elpXeGxZM1JsWkQwaE1DeHlKaVlvWlZ0c1hTNWtaV1poZFd4MFUyVnNaV04wWldROUlUQXBP'
    || 'M0psZEhWeWJuMTBJVDA5Ym5Wc2JIeDhaVnRzWFM1a2FYTmhZbXhsWkh4OEtIUTlaVnRzWFNsOWRDRTlQVzUxYkd3bUppaDBMbk5sYkdWamRHVmtQU0V3S1gx'
    || 'OVpuVnVZM1JwYjI0Z2RXa29aU3gwS1h0cFppaDBMbVJoYm1kbGNtOTFjMng1VTJWMFNXNXVaWEpJVkUxTUlUMXVkV3hzS1hSb2NtOTNJRVZ5Y205eUtHRW9P'
    || 'VEVwS1R0eVpYUjFjbTRnVENoN2ZTeDBMSHQyWVd4MVpUcDJiMmxrSURBc1pHVm1ZWFZzZEZaaGJIVmxPblp2YVdRZ01DeGphR2xzWkhKbGJqb2lJaXRsTGw5'
    || 'M2NtRndjR1Z5VTNSaGRHVXVhVzVwZEdsaGJGWmhiSFZsZlNsOVpuVnVZM1JwYjI0Z1JYTW9aU3gwS1h0MllYSWdiajEwTG5aaGJIVmxPMmxtS0c0OVBXNTFi'
    || 'R3dwZTJsbUtHNDlkQzVqYUdsc1pISmxiaXgwUFhRdVpHVm1ZWFZzZEZaaGJIVmxMRzRoUFc1MWJHd3BlMmxtS0hRaFBXNTFiR3dwZEdoeWIzY2dSWEp5YjNJ'
    || 'b1lTZzVNaWtwTzJsbUtFZHVLRzRwS1h0cFppZ3hQRzR1YkdWdVozUm9LWFJvY205M0lFVnljbTl5S0dFb09UTXBLVHR1UFc1Yk1GMTlkRDF1ZlhROVBXNTFi'
    || 'R3dtSmloMFBTSWlLU3h1UFhSOVpTNWZkM0poY0hCbGNsTjBZWFJsUFh0cGJtbDBhV0ZzVm1Gc2RXVTZjMlVvYmlsOWZXWjFibU4wYVc5dUlGOXpLR1VzZENs'
    || 'N2RtRnlJRzQ5YzJVb2RDNTJZV3gxWlNrc2NqMXpaU2gwTG1SbFptRjFiSFJXWVd4MVpTazdiaUU5Ym5Wc2JDWW1LRzQ5SWlJcmJpeHVJVDA5WlM1MllXeDFa'
    || 'U1ltS0dVdWRtRnNkV1U5Ymlrc2RDNWtaV1poZFd4MFZtRnNkV1U5UFc1MWJHd21KbVV1WkdWbVlYVnNkRlpoYkhWbElUMDliaVltS0dVdVpHVm1ZWFZzZEZa'
    || 'aGJIVmxQVzRwS1N4eUlUMXVkV3hzSmlZb1pTNWtaV1poZFd4MFZtRnNkV1U5SWlJcmNpbDlablZ1WTNScGIyNGdVM01vWlNsN2RtRnlJSFE5WlM1MFpYaDBR'
    || 'Mjl1ZEdWdWREdDBQVDA5WlM1ZmQzSmhjSEJsY2xOMFlYUmxMbWx1YVhScFlXeFdZV3gxWlNZbWRDRTlQU0lpSmlaMElUMDliblZzYkNZbUtHVXVkbUZzZFdV'
    || 'OWRDbDlablZ1WTNScGIyNGdkM01vWlNsN2MzZHBkR05vS0dVcGUyTmhjMlVpYzNabklqcHlaWFIxY200aWFIUjBjRG92TDNkM2R5NTNNeTV2Y21jdk1qQXdN'
    || 'Qzl6ZG1jaU8yTmhjMlVpYldGMGFDSTZjbVYwZFhKdUltaDBkSEE2THk5M2QzY3Vkek11YjNKbkx6RTVPVGd2VFdGMGFDOU5ZWFJvVFV3aU8yUmxabUYxYkhR'
    || 'NmNtVjBkWEp1SW1oMGRIQTZMeTkzZDNjdWR6TXViM0puTHpFNU9Ua3ZlR2gwYld3aWZYMW1kVzVqZEdsdmJpQmhhU2hsTEhRcGUzSmxkSFZ5YmlCbFBUMXVk'
    || 'V3hzZkh4bFBUMDlJbWgwZEhBNkx5OTNkM2N1ZHpNdWIzSm5MekU1T1RrdmVHaDBiV3dpUDNkektIUXBPbVU5UFQwaWFIUjBjRG92TDNkM2R5NTNNeTV2Y21j'
    || 'dk1qQXdNQzl6ZG1jaUppWjBQVDA5SW1admNtVnBaMjVQWW1wbFkzUWlQeUpvZEhSd09pOHZkM2QzTG5jekxtOXlaeTh4T1RrNUwzaG9kRzFzSWpwbGZYWmhj'
    || 'aUJWY2l4cmN6MG9ablZ1WTNScGIyNG9aU2w3Y21WMGRYSnVJSFI1Y0dWdlppQk5VMEZ3Y0R3aWRTSW1KazFUUVhCd0xtVjRaV05WYm5OaFptVk1iMk5oYkVa'
    || 'MWJtTjBhVzl1UDJaMWJtTjBhVzl1S0hRc2JpeHlMR3dwZTAxVFFYQndMbVY0WldOVmJuTmhabVZNYjJOaGJFWjFibU4wYVc5dUtHWjFibU4wYVc5dUtDbDdj'
    || 'bVYwZFhKdUlHVW9kQ3h1TEhJc2JDbDlLWDA2WlgwcEtHWjFibU4wYVc5dUtHVXNkQ2w3YVdZb1pTNXVZVzFsYzNCaFkyVlZVa2toUFQwaWFIUjBjRG92TDNk'
    || 'M2R5NTNNeTV2Y21jdk1qQXdNQzl6ZG1jaWZId2lhVzV1WlhKSVZFMU1JbWx1SUdVcFpTNXBibTVsY2toVVRVdzlkRHRsYkhObGUyWnZjaWhWY2oxVmNueDha'
    || 'RzlqZFcxbGJuUXVZM0psWVhSbFJXeGxiV1Z1ZENnaVpHbDJJaWtzVlhJdWFXNXVaWEpJVkUxTVBTSThjM1puUGlJcmRDNTJZV3gxWlU5bUtDa3VkRzlUZEhK'
    || 'cGJtY29LU3NpUEM5emRtYytJaXgwUFZWeUxtWnBjbk4wUTJocGJHUTdaUzVtYVhKemRFTm9hV3hrT3lsbExuSmxiVzkyWlVOb2FXeGtLR1V1Wm1seWMzUkRh'
    || 'R2xzWkNrN1ptOXlLRHQwTG1acGNuTjBRMmhwYkdRN0tXVXVZWEJ3Wlc1a1EyaHBiR1FvZEM1bWFYSnpkRU5vYVd4a0tYMTlLVHRtZFc1amRHbHZiaUJMYmlo'
    || 'bExIUXBlMmxtS0hRcGUzWmhjaUJ1UFdVdVptbHljM1JEYUdsc1pEdHBaaWh1SmladVBUMDlaUzVzWVhOMFEyaHBiR1FtSm00dWJtOWtaVlI1Y0dVOVBUMHpL'
    || 'WHR1TG01dlpHVldZV3gxWlQxME8zSmxkSFZ5Ym4xOVpTNTBaWGgwUTI5dWRHVnVkRDEwZlhaaGNpQlliajE3WVc1cGJXRjBhVzl1U1hSbGNtRjBhVzl1UTI5'
    || 'MWJuUTZJVEFzWVhOd1pXTjBVbUYwYVc4NklUQXNZbTl5WkdWeVNXMWhaMlZQZFhSelpYUTZJVEFzWW05eVpHVnlTVzFoWjJWVGJHbGpaVG9oTUN4aWIzSmta'
    || 'WEpKYldGblpWZHBaSFJvT2lFd0xHSnZlRVpzWlhnNklUQXNZbTk0Um14bGVFZHliM1Z3T2lFd0xHSnZlRTl5WkdsdVlXeEhjbTkxY0RvaE1DeGpiMngxYlc1'
    || 'RGIzVnVkRG9oTUN4amIyeDFiVzV6T2lFd0xHWnNaWGc2SVRBc1pteGxlRWR5YjNjNklUQXNabXhsZUZCdmMybDBhWFpsT2lFd0xHWnNaWGhUYUhKcGJtczZJ'
    || 'VEFzWm14bGVFNWxaMkYwYVhabE9pRXdMR1pzWlhoUGNtUmxjam9oTUN4bmNtbGtRWEpsWVRvaE1DeG5jbWxrVW05M09pRXdMR2R5YVdSU2IzZEZibVE2SVRB'
    || 'c1ozSnBaRkp2ZDFOd1lXNDZJVEFzWjNKcFpGSnZkMU4wWVhKME9pRXdMR2R5YVdSRGIyeDFiVzQ2SVRBc1ozSnBaRU52YkhWdGJrVnVaRG9oTUN4bmNtbGtR'
    || 'MjlzZFcxdVUzQmhiam9oTUN4bmNtbGtRMjlzZFcxdVUzUmhjblE2SVRBc1ptOXVkRmRsYVdkb2REb2hNQ3hzYVc1bFEyeGhiWEE2SVRBc2JHbHVaVWhsYVdk'
    || 'b2REb2hNQ3h2Y0dGamFYUjVPaUV3TEc5eVpHVnlPaUV3TEc5eWNHaGhibk02SVRBc2RHRmlVMmw2WlRvaE1DeDNhV1J2ZDNNNklUQXNla2x1WkdWNE9pRXdM'
    || 'SHB2YjIwNklUQXNabWxzYkU5d1lXTnBkSGs2SVRBc1pteHZiMlJQY0dGamFYUjVPaUV3TEhOMGIzQlBjR0ZqYVhSNU9pRXdMSE4wY205clpVUmhjMmhoY25K'
    || 'aGVUb2hNQ3h6ZEhKdmEyVkVZWE5vYjJabWMyVjBPaUV3TEhOMGNtOXJaVTFwZEdWeWJHbHRhWFE2SVRBc2MzUnliMnRsVDNCaFkybDBlVG9oTUN4emRISnZh'
    || 'MlZYYVdSMGFEb2hNSDBzWm1ROVd5SlhaV0pyYVhRaUxDSnRjeUlzSWsxdmVpSXNJazhpWFR0UFltcGxZM1F1YTJWNWN5aFliaWt1Wm05eVJXRmphQ2htZFc1'
    || 'amRHbHZiaWhsS1h0bVpDNW1iM0pGWVdOb0tHWjFibU4wYVc5dUtIUXBlM1E5ZEN0bExtTm9ZWEpCZENnd0tTNTBiMVZ3Y0dWeVEyRnpaU2dwSzJVdWMzVmlj'
    || 'M1J5YVc1bktERXBMRmh1VzNSZFBWaHVXMlZkZlNsOUtUdG1kVzVqZEdsdmJpQnFjeWhsTEhRc2JpbDdjbVYwZFhKdUlIUTlQVzUxYkd4OGZIUjVjR1Z2WmlC'
    || 'MFBUMGlZbTl2YkdWaGJpSjhmSFE5UFQwaUlqOGlJanB1Zkh4MGVYQmxiMllnZENFOUltNTFiV0psY2lKOGZIUTlQVDB3Zkh4WWJpNW9ZWE5QZDI1UWNtOXda'
    || 'WEowZVNobEtTWW1XRzViWlYwL0tDSWlLM1FwTG5SeWFXMG9LVHAwS3lKd2VDSjlablZ1WTNScGIyNGdUbk1vWlN4MEtYdGxQV1V1YzNSNWJHVTdabTl5S0ha'
    || 'aGNpQnVJR2x1SUhRcGFXWW9kQzVvWVhOUGQyNVFjbTl3WlhKMGVTaHVLU2w3ZG1GeUlISTliaTVwYm1SbGVFOW1LQ0l0TFNJcFBUMDlNQ3hzUFdwektHNHNk'
    || 'RnR1WFN4eUtUdHVQVDA5SW1ac2IyRjBJaVltS0c0OUltTnpjMFpzYjJGMElpa3NjajlsTG5ObGRGQnliM0JsY25SNUtHNHNiQ2s2WlZ0dVhUMXNmWDEyWVhJ'
    || 'Z2NHUTlUQ2g3YldWdWRXbDBaVzA2SVRCOUxIdGhjbVZoT2lFd0xHSmhjMlU2SVRBc1luSTZJVEFzWTI5c09pRXdMR1Z0WW1Wa09pRXdMR2h5T2lFd0xHbHRa'
    || 'em9oTUN4cGJuQjFkRG9oTUN4clpYbG5aVzQ2SVRBc2JHbHVhem9oTUN4dFpYUmhPaUV3TEhCaGNtRnRPaUV3TEhOdmRYSmpaVG9oTUN4MGNtRmphem9oTUN4'
    || 'M1luSTZJVEI5S1R0bWRXNWpkR2x2YmlCamFTaGxMSFFwZTJsbUtIUXBlMmxtS0hCa1cyVmRKaVlvZEM1amFHbHNaSEpsYmlFOWJuVnNiSHg4ZEM1a1lXNW5a'
    || 'WEp2ZFhOc2VWTmxkRWx1Ym1WeVNGUk5UQ0U5Ym5Wc2JDa3BkR2h5YjNjZ1JYSnliM0lvWVNneE16Y3NaU2twTzJsbUtIUXVaR0Z1WjJWeWIzVnpiSGxUWlhS'
    || 'SmJtNWxja2hVVFV3aFBXNTFiR3dwZTJsbUtIUXVZMmhwYkdSeVpXNGhQVzUxYkd3cGRHaHliM2NnUlhKeWIzSW9ZU2cyTUNrcE8ybG1LSFI1Y0dWdlppQjBM'
    || 'bVJoYm1kbGNtOTFjMng1VTJWMFNXNXVaWEpJVkUxTUlUMGliMkpxWldOMElueDhJU2dpWDE5b2RHMXNJbWx1SUhRdVpHRnVaMlZ5YjNWemJIbFRaWFJKYm01'
    || 'bGNraFVUVXdwS1hSb2NtOTNJRVZ5Y205eUtHRW9OakVwS1gxcFppaDBMbk4wZVd4bElUMXVkV3hzSmlaMGVYQmxiMllnZEM1emRIbHNaU0U5SW05aWFtVmpk'
    || 'Q0lwZEdoeWIzY2dSWEp5YjNJb1lTZzJNaWtwZlgxbWRXNWpkR2x2YmlCa2FTaGxMSFFwZTJsbUtHVXVhVzVrWlhoUFppZ2lMU0lwUFQwOUxURXBjbVYwZFhK'
    || 'dUlIUjVjR1Z2WmlCMExtbHpQVDBpYzNSeWFXNW5JanR6ZDJsMFkyZ29aU2w3WTJGelpTSmhibTV2ZEdGMGFXOXVMWGh0YkNJNlkyRnpaU0pqYjJ4dmNpMXdj'
    || 'bTltYVd4bElqcGpZWE5sSW1admJuUXRabUZqWlNJNlkyRnpaU0ptYjI1MExXWmhZMlV0YzNKaklqcGpZWE5sSW1admJuUXRabUZqWlMxMWNta2lPbU5oYzJV'
    || 'aVptOXVkQzFtWVdObExXWnZjbTFoZENJNlkyRnpaU0ptYjI1MExXWmhZMlV0Ym1GdFpTSTZZMkZ6WlNKdGFYTnphVzVuTFdkc2VYQm9JanB5WlhSMWNtNGhN'
    || 'VHRrWldaaGRXeDBPbkpsZEhWeWJpRXdmWDEyWVhJZ1ptazliblZzYkR0bWRXNWpkR2x2YmlCd2FTaGxLWHR5WlhSMWNtNGdaVDFsTG5SaGNtZGxkSHg4WlM1'
    || 'emNtTkZiR1Z0Wlc1MGZIeDNhVzVrYjNjc1pTNWpiM0p5WlhOd2IyNWthVzVuVlhObFJXeGxiV1Z1ZENZbUtHVTlaUzVqYjNKeVpYTndiMjVrYVc1blZYTmxS'
    || 'V3hsYldWdWRDa3NaUzV1YjJSbFZIbHdaVDA5UFRNL1pTNXdZWEpsYm5ST2IyUmxPbVY5ZG1GeUlHaHBQVzUxYkd3c1UyNDliblZzYkN4M2JqMXVkV3hzTzJa'
    || 'MWJtTjBhVzl1SUVOektHVXBlMmxtS0dVOVozSW9aU2twZTJsbUtIUjVjR1Z2WmlCb2FTRTlJbVoxYm1OMGFXOXVJaWwwYUhKdmR5QkZjbkp2Y2loaEtESTRN'
    || 'Q2twTzNaaGNpQjBQV1V1YzNSaGRHVk9iMlJsTzNRbUppaDBQWE5zS0hRcExHaHBLR1V1YzNSaGRHVk9iMlJsTEdVdWRIbHdaU3gwS1NsOWZXWjFibU4wYVc5'
    || 'dUlGUnpLR1VwZTFOdVAzZHVQM2R1TG5CMWMyZ29aU2s2ZDI0OVcyVmRPbE51UFdWOVpuVnVZM1JwYjI0Z1VuTW9LWHRwWmloVGJpbDdkbUZ5SUdVOVUyNHNk'
    || 'RDEzYmp0cFppaDNiajFUYmoxdWRXeHNMRU56S0dVcExIUXBabTl5S0dVOU1EdGxQSFF1YkdWdVozUm9PMlVyS3lsRGN5aDBXMlZkS1gxOVpuVnVZM1JwYjI0'
    || 'Z1JITW9aU3gwS1h0eVpYUjFjbTRnWlNoMEtYMW1kVzVqZEdsdmJpQlBjeWdwZTMxMllYSWdiV2s5SVRFN1puVnVZM1JwYjI0Z1VITW9aU3gwTEc0cGUybG1L'
    || 'RzFwS1hKbGRIVnliaUJsS0hRc2JpazdiV2s5SVRBN2RISjVlM0psZEhWeWJpQkVjeWhsTEhRc2JpbDlabWx1WVd4c2VYdHRhVDBoTVN3b1UyNGhQVDF1ZFd4'
    || 'c2ZIeDNiaUU5UFc1MWJHd3BKaVlvVDNNb0tTeFNjeWdwS1gxOVpuVnVZM1JwYjI0Z1dtNG9aU3gwS1h0MllYSWdiajFsTG5OMFlYUmxUbTlrWlR0cFppaHVQ'
    || 'VDA5Ym5Wc2JDbHlaWFIxY200Z2JuVnNiRHQyWVhJZ2NqMXpiQ2h1S1R0cFppaHlQVDA5Ym5Wc2JDbHlaWFIxY200Z2JuVnNiRHR1UFhKYmRGMDdaVHB6ZDJs'
    || 'MFkyZ29kQ2w3WTJGelpTSnZia05zYVdOcklqcGpZWE5sSW05dVEyeHBZMnREWVhCMGRYSmxJanBqWVhObEltOXVSRzkxWW14bFEyeHBZMnNpT21OaGMyVWli'
    || 'MjVFYjNWaWJHVkRiR2xqYTBOaGNIUjFjbVVpT21OaGMyVWliMjVOYjNWelpVUnZkMjRpT21OaGMyVWliMjVOYjNWelpVUnZkMjVEWVhCMGRYSmxJanBqWVhO'
    || 'bEltOXVUVzkxYzJWTmIzWmxJanBqWVhObEltOXVUVzkxYzJWTmIzWmxRMkZ3ZEhWeVpTSTZZMkZ6WlNKdmJrMXZkWE5sVlhBaU9tTmhjMlVpYjI1TmIzVnpa'
    || 'VlZ3UTJGd2RIVnlaU0k2WTJGelpTSnZiazF2ZFhObFJXNTBaWElpT2loeVBTRnlMbVJwYzJGaWJHVmtLWHg4S0dVOVpTNTBlWEJsTEhJOUlTaGxQVDA5SW1K'
    || 'MWRIUnZiaUo4ZkdVOVBUMGlhVzV3ZFhRaWZIeGxQVDA5SW5ObGJHVmpkQ0o4ZkdVOVBUMGlkR1Y0ZEdGeVpXRWlLU2tzWlQwaGNqdGljbVZoYXlCbE8yUmxa'
    || 'bUYxYkhRNlpUMGhNWDFwWmlobEtYSmxkSFZ5YmlCdWRXeHNPMmxtS0c0bUpuUjVjR1Z2WmlCdUlUMGlablZ1WTNScGIyNGlLWFJvY205M0lFVnljbTl5S0dF'
    || 'b01qTXhMSFFzZEhsd1pXOW1JRzRwS1R0eVpYUjFjbTRnYm4xMllYSWdkbWs5SVRFN2FXWW9haWwwY25sN2RtRnlJSEZ1UFh0OU8wOWlhbVZqZEM1a1pXWnBi'
    || 'bVZRY205d1pYSjBlU2h4Yml3aWNHRnpjMmwyWlNJc2UyZGxkRHBtZFc1amRHbHZiaWdwZTNacFBTRXdmWDBwTEhkcGJtUnZkeTVoWkdSRmRtVnVkRXhwYzNS'
    || 'bGJtVnlLQ0owWlhOMElpeHhiaXh4Ymlrc2QybHVaRzkzTG5KbGJXOTJaVVYyWlc1MFRHbHpkR1Z1WlhJb0luUmxjM1FpTEhGdUxIRnVLWDFqWVhSamFIdDJh'
    || 'VDBoTVgxbWRXNWpkR2x2YmlCb1pDaGxMSFFzYml4eUxHd3NhU3h6TEdRc1ppbDdkbUZ5SUhrOVFYSnlZWGt1Y0hKdmRHOTBlWEJsTG5Oc2FXTmxMbU5oYkd3'
    || 'b1lYSm5kVzFsYm5SekxETXBPM1J5ZVh0MExtRndjR3g1S0c0c2VTbDlZMkYwWTJnb2F5bDdkR2hwY3k1dmJrVnljbTl5S0dzcGZYMTJZWElnU200OUlURXNS'
    || 'bkk5Ym5Wc2JDeFhjajBoTVN4bmFUMXVkV3hzTEcxa1BYdHZia1Z5Y205eU9tWjFibU4wYVc5dUtHVXBlMHB1UFNFd0xFWnlQV1Y5ZlR0bWRXNWpkR2x2YmlC'
    || 'MlpDaGxMSFFzYml4eUxHd3NhU3h6TEdRc1ppbDdTbTQ5SVRFc1JuSTliblZzYkN4b1pDNWhjSEJzZVNodFpDeGhjbWQxYldWdWRITXBmV1oxYm1OMGFXOXVJ'
    || 'R2RrS0dVc2RDeHVMSElzYkN4cExITXNaQ3htS1h0cFppaDJaQzVoY0hCc2VTaDBhR2x6TEdGeVozVnRaVzUwY3lrc1NtNHBlMmxtS0VwdUtYdDJZWElnZVQx'
    || 'R2NqdEtiajBoTVN4R2NqMXVkV3hzZldWc2MyVWdkR2h5YjNjZ1JYSnliM0lvWVNneE9UZ3BLVHRYY254OEtGZHlQU0V3TEdkcFBYa3BmWDFtZFc1amRHbHZi'
    || 'aUJ6YmlobEtYdDJZWElnZEQxbExHNDlaVHRwWmlobExtRnNkR1Z5Ym1GMFpTbG1iM0lvTzNRdWNtVjBkWEp1T3lsMFBYUXVjbVYwZFhKdU8yVnNjMlY3WlQx'
    || 'ME8yUnZJSFE5WlN3b2RDNW1iR0ZuY3lZME1EazRLU0U5UFRBbUppaHVQWFF1Y21WMGRYSnVLU3hsUFhRdWNtVjBkWEp1TzNkb2FXeGxLR1VwZlhKbGRIVnli'
    || 'aUIwTG5SaFp6MDlQVE0vYmpwdWRXeHNmV1oxYm1OMGFXOXVJRXh6S0dVcGUybG1LR1V1ZEdGblBUMDlNVE1wZTNaaGNpQjBQV1V1YldWdGIybDZaV1JUZEdG'
    || 'MFpUdHBaaWgwUFQwOWJuVnNiQ1ltS0dVOVpTNWhiSFJsY201aGRHVXNaU0U5UFc1MWJHd21KaWgwUFdVdWJXVnRiMmw2WldSVGRHRjBaU2twTEhRaFBUMXVk'
    || 'V3hzS1hKbGRIVnliaUIwTG1SbGFIbGtjbUYwWldSOWNtVjBkWEp1SUc1MWJHeDlablZ1WTNScGIyNGdTWE1vWlNsN2FXWW9jMjRvWlNraFBUMWxLWFJvY205'
    || 'M0lFVnljbTl5S0dFb01UZzRLU2w5Wm5WdVkzUnBiMjRnZVdRb1pTbDdkbUZ5SUhROVpTNWhiSFJsY201aGRHVTdhV1lvSVhRcGUybG1LSFE5YzI0b1pTa3Nk'
    || 'RDA5UFc1MWJHd3BkR2h5YjNjZ1JYSnliM0lvWVNneE9EZ3BLVHR5WlhSMWNtNGdkQ0U5UFdVL2JuVnNiRHBsZldadmNpaDJZWElnYmoxbExISTlkRHM3S1h0'
    || 'MllYSWdiRDF1TG5KbGRIVnlianRwWmloc1BUMDliblZzYkNsaWNtVmhhenQyWVhJZ2FUMXNMbUZzZEdWeWJtRjBaVHRwWmlocFBUMDliblZzYkNsN2FXWW9j'
    || 'ajFzTG5KbGRIVnliaXh5SVQwOWJuVnNiQ2w3YmoxeU8yTnZiblJwYm5WbGZXSnlaV0ZyZldsbUtHd3VZMmhwYkdROVBUMXBMbU5vYVd4a0tYdG1iM0lvYVQx'
    || 'c0xtTm9hV3hrTzJrN0tYdHBaaWhwUFQwOWJpbHlaWFIxY200Z1NYTW9iQ2tzWlR0cFppaHBQVDA5Y2lseVpYUjFjbTRnU1hNb2JDa3NkRHRwUFdrdWMybGli'
    || 'R2x1WjMxMGFISnZkeUJGY25KdmNpaGhLREU0T0NrcGZXbG1LRzR1Y21WMGRYSnVJVDA5Y2k1eVpYUjFjbTRwYmoxc0xISTlhVHRsYkhObGUyWnZjaWgyWVhJ'
    || 'Z2N6MGhNU3hrUFd3dVkyaHBiR1E3WkRzcGUybG1LR1E5UFQxdUtYdHpQU0V3TEc0OWJDeHlQV2s3WW5KbFlXdDlhV1lvWkQwOVBYSXBlM005SVRBc2NqMXNM'
    || 'RzQ5YVR0aWNtVmhhMzFrUFdRdWMybGliR2x1WjMxcFppZ2hjeWw3Wm05eUtHUTlhUzVqYUdsc1pEdGtPeWw3YVdZb1pEMDlQVzRwZTNNOUlUQXNiajFwTEhJ'
    || 'OWJEdGljbVZoYTMxcFppaGtQVDA5Y2lsN2N6MGhNQ3h5UFdrc2JqMXNPMkp5WldGcmZXUTlaQzV6YVdKc2FXNW5mV2xtS0NGektYUm9jbTkzSUVWeWNtOXlL'
    || 'R0VvTVRnNUtTbDlmV2xtS0c0dVlXeDBaWEp1WVhSbElUMDljaWwwYUhKdmR5QkZjbkp2Y2loaEtERTVNQ2twZldsbUtHNHVkR0ZuSVQwOU15bDBhSEp2ZHlC'
    || 'RmNuSnZjaWhoS0RFNE9Da3BPM0psZEhWeWJpQnVMbk4wWVhSbFRtOWtaUzVqZFhKeVpXNTBQVDA5Ymo5bE9uUjlablZ1WTNScGIyNGdRWE1vWlNsN2NtVjBk'
    || 'WEp1SUdVOWVXUW9aU2tzWlNFOVBXNTFiR3cvVFhNb1pTazZiblZzYkgxbWRXNWpkR2x2YmlCTmN5aGxLWHRwWmlobExuUmhaejA5UFRWOGZHVXVkR0ZuUFQw'
    || 'OU5pbHlaWFIxY200Z1pUdG1iM0lvWlQxbExtTm9hV3hrTzJVaFBUMXVkV3hzT3lsN2RtRnlJSFE5VFhNb1pTazdhV1lvZENFOVBXNTFiR3dwY21WMGRYSnVJ'
    || 'SFE3WlQxbExuTnBZbXhwYm1kOWNtVjBkWEp1SUc1MWJHeDlkbUZ5SUhwelBXTXVkVzV6ZEdGaWJHVmZjMk5vWldSMWJHVkRZV3hzWW1GamF5eFZjejFqTG5W'
    || 'dWMzUmhZbXhsWDJOaGJtTmxiRU5oYkd4aVlXTnJMSGhrUFdNdWRXNXpkR0ZpYkdWZmMyaHZkV3hrV1dsbGJHUXNSV1E5WXk1MWJuTjBZV0pzWlY5eVpYRjFa'
    || 'WE4wVUdGcGJuUXNkMlU5WXk1MWJuTjBZV0pzWlY5dWIzY3NYMlE5WXk1MWJuTjBZV0pzWlY5blpYUkRkWEp5Wlc1MFVISnBiM0pwZEhsTVpYWmxiQ3g1YVQx'
    || 'akxuVnVjM1JoWW14bFgwbHRiV1ZrYVdGMFpWQnlhVzl5YVhSNUxFWnpQV011ZFc1emRHRmliR1ZmVlhObGNrSnNiMk5yYVc1blVISnBiM0pwZEhrc1ZuSTlZ'
    || 'eTUxYm5OMFlXSnNaVjlPYjNKdFlXeFFjbWx2Y21sMGVTeFRaRDFqTG5WdWMzUmhZbXhsWDB4dmQxQnlhVzl5YVhSNUxGZHpQV011ZFc1emRHRmliR1ZmU1dS'
    || 'c1pWQnlhVzl5YVhSNUxFSnlQVzUxYkd3c2QzUTliblZzYkR0bWRXNWpkR2x2YmlCM1pDaGxLWHRwWmloM2RDWW1kSGx3Wlc5bUlIZDBMbTl1UTI5dGJXbDBS'
    || 'bWxpWlhKU2IyOTBQVDBpWm5WdVkzUnBiMjRpS1hSeWVYdDNkQzV2YmtOdmJXMXBkRVpwWW1WeVVtOXZkQ2hDY2l4bExIWnZhV1FnTUN3b1pTNWpkWEp5Wlc1'
    || 'MExtWnNZV2R6SmpFeU9DazlQVDB4TWpncGZXTmhkR05vZTMxOWRtRnlJSEIwUFUxaGRHZ3VZMng2TXpJL1RXRjBhQzVqYkhvek1qcE9aQ3hyWkQxTllYUm9M'
    || 'bXh2Wnl4cVpEMU5ZWFJvTGt4T01qdG1kVzVqZEdsdmJpQk9aQ2hsS1h0eVpYUjFjbTRnWlQ0K1BqMHdMR1U5UFQwd1B6TXlPak14TFNoclpDaGxLUzlxWkh3'
    || 'd0tYd3dmWFpoY2lCSWNqMDJOQ3drY2owME1UazBNekEwTzJaMWJtTjBhVzl1SUdKdUtHVXBlM04zYVhSamFDaGxKaTFsS1h0allYTmxJREU2Y21WMGRYSnVJ'
    || 'REU3WTJGelpTQXlPbkpsZEhWeWJpQXlPMk5oYzJVZ05EcHlaWFIxY200Z05EdGpZWE5sSURnNmNtVjBkWEp1SURnN1kyRnpaU0F4TmpweVpYUjFjbTRnTVRZ'
    || 'N1kyRnpaU0F6TWpweVpYUjFjbTRnTXpJN1kyRnpaU0EyTkRwallYTmxJREV5T0RwallYTmxJREkxTmpwallYTmxJRFV4TWpwallYTmxJREV3TWpRNlkyRnpa'
    || 'U0F5TURRNE9tTmhjMlVnTkRBNU5qcGpZWE5sSURneE9USTZZMkZ6WlNBeE5qTTRORHBqWVhObElETXlOelk0T21OaGMyVWdOalUxTXpZNlkyRnpaU0F4TXpF'
    || 'd056STZZMkZ6WlNBeU5qSXhORFE2WTJGelpTQTFNalF5T0RnNlkyRnpaU0F4TURRNE5UYzJPbU5oYzJVZ01qQTVOekUxTWpweVpYUjFjbTRnWlNZME1UazBN'
    || 'alF3TzJOaGMyVWdOREU1TkRNd05EcGpZWE5sSURnek9EZzJNRGc2WTJGelpTQXhOamMzTnpJeE5qcGpZWE5sSURNek5UVTBORE15T21OaGMyVWdOamN4TURn'
    || 'NE5qUTZjbVYwZFhKdUlHVW1NVE13TURJek5ESTBPMk5oYzJVZ01UTTBNakUzTnpJNE9uSmxkSFZ5YmlBeE16UXlNVGMzTWpnN1kyRnpaU0F5TmpnME16VTBO'
    || 'VFk2Y21WMGRYSnVJREkyT0RRek5UUTFOanRqWVhObElEVXpOamczTURreE1qcHlaWFIxY200Z05UTTJPRGN3T1RFeU8yTmhjMlVnTVRBM016YzBNVGd5TkRw'
    || 'eVpYUjFjbTRnTVRBM016YzBNVGd5TkR0a1pXWmhkV3gwT25KbGRIVnliaUJsZlgxbWRXNWpkR2x2YmlCUmNpaGxMSFFwZTNaaGNpQnVQV1V1Y0dWdVpHbHVa'
    || 'MHhoYm1Wek8ybG1LRzQ5UFQwd0tYSmxkSFZ5YmlBd08zWmhjaUJ5UFRBc2JEMWxMbk4xYzNCbGJtUmxaRXhoYm1WekxHazlaUzV3YVc1blpXUk1ZVzVsY3l4'
    || 'elBXNG1Nalk0TkRNMU5EVTFPMmxtS0hNaFBUMHdLWHQyWVhJZ1pEMXpKbjVzTzJRaFBUMHdQM0k5WW00b1pDazZLR2ttUFhNc2FTRTlQVEFtSmloeVBXSnVL'
    || 'R2twS1NsOVpXeHpaU0J6UFc0bWZtd3NjeUU5UFRBL2NqMWliaWh6S1RwcElUMDlNQ1ltS0hJOVltNG9hU2twTzJsbUtISTlQVDB3S1hKbGRIVnliaUF3TzJs'
    || 'bUtIUWhQVDB3SmlaMElUMDljaVltS0hRbWJDazlQVDB3SmlZb2JEMXlKaTF5TEdrOWRDWXRkQ3hzUGoxcGZIeHNQVDA5TVRZbUppaHBKalF4T1RReU5EQXBJ'
    || 'VDA5TUNrcGNtVjBkWEp1SUhRN2FXWW9LSEltTkNraFBUMHdKaVlvY253OWJpWXhOaWtzZEQxbExtVnVkR0Z1WjJ4bFpFeGhibVZ6TEhRaFBUMHdLV1p2Y2lo'
    || 'bFBXVXVaVzUwWVc1bmJHVnRaVzUwY3l4MEpqMXlPekE4ZERzcGJqMHpNUzF3ZENoMEtTeHNQVEU4UEc0c2NudzlaVnR1WFN4MEpqMStiRHR5WlhSMWNtNGdj'
    || 'bjFtZFc1amRHbHZiaUJEWkNobExIUXBlM04zYVhSamFDaGxLWHRqWVhObElERTZZMkZ6WlNBeU9tTmhjMlVnTkRweVpYUjFjbTRnZENzeU5UQTdZMkZ6WlNB'
    || 'NE9tTmhjMlVnTVRZNlkyRnpaU0F6TWpwallYTmxJRFkwT21OaGMyVWdNVEk0T21OaGMyVWdNalUyT21OaGMyVWdOVEV5T21OaGMyVWdNVEF5TkRwallYTmxJ'
    || 'REl3TkRnNlkyRnpaU0EwTURrMk9tTmhjMlVnT0RFNU1qcGpZWE5sSURFMk16ZzBPbU5oYzJVZ016STNOamc2WTJGelpTQTJOVFV6TmpwallYTmxJREV6TVRB'
    || 'M01qcGpZWE5sSURJMk1qRTBORHBqWVhObElEVXlOREk0T0RwallYTmxJREV3TkRnMU56WTZZMkZ6WlNBeU1EazNNVFV5T25KbGRIVnliaUIwS3pWbE16dGpZ'
    || 'WE5sSURReE9UUXpNRFE2WTJGelpTQTRNemc0TmpBNE9tTmhjMlVnTVRZM056Y3lNVFk2WTJGelpTQXpNelUxTkRRek1qcGpZWE5sSURZM01UQTRPRFkwT25K'
    || 'bGRIVnliaTB4TzJOaGMyVWdNVE0wTWpFM056STRPbU5oYzJVZ01qWTRORE0xTkRVMk9tTmhjMlVnTlRNMk9EY3dPVEV5T21OaGMyVWdNVEEzTXpjME1UZ3lO'
    || 'RHB5WlhSMWNtNHRNVHRrWldaaGRXeDBPbkpsZEhWeWJpMHhmWDFtZFc1amRHbHZiaUJVWkNobExIUXBlMlp2Y2loMllYSWdiajFsTG5OMWMzQmxibVJsWkV4'
    || 'aGJtVnpMSEk5WlM1d2FXNW5aV1JNWVc1bGN5eHNQV1V1Wlhod2FYSmhkR2x2YmxScGJXVnpMR2s5WlM1d1pXNWthVzVuVEdGdVpYTTdNRHhwT3lsN2RtRnlJ'
    || 'SE05TXpFdGNIUW9hU2tzWkQweFBEeHpMR1k5YkZ0elhUdG1QVDA5TFRFL0tDaGtKbTRwUFQwOU1IeDhLR1FtY2lraFBUMHdLU1ltS0d4YmMxMDlRMlFvWkN4'
    || 'MEtTazZaanc5ZENZbUtHVXVaWGh3YVhKbFpFeGhibVZ6ZkQxa0tTeHBKajErWkgxOVpuVnVZM1JwYjI0Z2VHa29aU2w3Y21WMGRYSnVJR1U5WlM1d1pXNWth'
    || 'VzVuVEdGdVpYTW1MVEV3TnpNM05ERTRNalVzWlNFOVBUQS9aVHBsSmpFd056TTNOREU0TWpRL01UQTNNemMwTVRneU5Eb3dmV1oxYm1OMGFXOXVJRlp6S0Ns'
    || 'N2RtRnlJR1U5U0hJN2NtVjBkWEp1SUVoeVBEdzlNU3dvU0hJbU5ERTVOREkwTUNrOVBUMHdKaVlvU0hJOU5qUXBMR1Y5Wm5WdVkzUnBiMjRnUldrb1pTbDda'
    || 'bTl5S0haaGNpQjBQVnRkTEc0OU1Ec3pNVDV1TzI0ckt5bDBMbkIxYzJnb1pTazdjbVYwZFhKdUlIUjlablZ1WTNScGIyNGdaWElvWlN4MExHNHBlMlV1Y0dW'
    || 'dVpHbHVaMHhoYm1WemZEMTBMSFFoUFQwMU16WTROekE1TVRJbUppaGxMbk4xYzNCbGJtUmxaRXhoYm1WelBUQXNaUzV3YVc1blpXUk1ZVzVsY3owd0tTeGxQ'
    || 'V1V1WlhabGJuUlVhVzFsY3l4MFBUTXhMWEIwS0hRcExHVmJkRjA5Ym4xbWRXNWpkR2x2YmlCU1pDaGxMSFFwZTNaaGNpQnVQV1V1Y0dWdVpHbHVaMHhoYm1W'
    || 'ekpuNTBPMlV1Y0dWdVpHbHVaMHhoYm1WelBYUXNaUzV6ZFhOd1pXNWtaV1JNWVc1bGN6MHdMR1V1Y0dsdVoyVmtUR0Z1WlhNOU1DeGxMbVY0Y0dseVpXUk1Z'
    || 'VzVsY3lZOWRDeGxMbTExZEdGaWJHVlNaV0ZrVEdGdVpYTW1QWFFzWlM1bGJuUmhibWRzWldSTVlXNWxjeVk5ZEN4MFBXVXVaVzUwWVc1bmJHVnRaVzUwY3p0'
    || 'MllYSWdjajFsTG1WMlpXNTBWR2x0WlhNN1ptOXlLR1U5WlM1bGVIQnBjbUYwYVc5dVZHbHRaWE03TUR4dU95bDdkbUZ5SUd3OU16RXRjSFFvYmlrc2FUMHhQ'
    || 'RHhzTzNSYmJGMDlNQ3h5VzJ4ZFBTMHhMR1ZiYkYwOUxURXNiaVk5Zm1sOWZXWjFibU4wYVc5dUlGOXBLR1VzZENsN2RtRnlJRzQ5WlM1bGJuUmhibWRzWldS'
    || 'TVlXNWxjM3c5ZER0bWIzSW9aVDFsTG1WdWRHRnVaMnhsYldWdWRITTdianNwZTNaaGNpQnlQVE14TFhCMEtHNHBMR3c5TVR3OGNqdHNKblI4WlZ0eVhTWjBK'
    || 'aVlvWlZ0eVhYdzlkQ2tzYmlZOWZteDlmWFpoY2lCMVpUMHdPMloxYm1OMGFXOXVJRUp6S0dVcGUzSmxkSFZ5YmlCbEpqMHRaU3d4UEdVL05EeGxQeWhsSmpJ'
    || 'Mk9EUXpOVFExTlNraFBUMHdQekUyT2pVek5qZzNNRGt4TWpvME9qRjlkbUZ5SUVoekxGTnBMQ1J6TEZGekxGbHpMSGRwUFNFeExGbHlQVnRkTEZWMFBXNTFi'
    || 'R3dzUm5ROWJuVnNiQ3hYZEQxdWRXeHNMSFJ5UFc1bGR5Qk5ZWEFzYm5JOWJtVjNJRTFoY0N4V2REMWJYU3hFWkQwaWJXOTFjMlZrYjNkdUlHMXZkWE5sZFhB'
    || 'Z2RHOTFZMmhqWVc1alpXd2dkRzkxWTJobGJtUWdkRzkxWTJoemRHRnlkQ0JoZFhoamJHbGpheUJrWW14amJHbGpheUJ3YjJsdWRHVnlZMkZ1WTJWc0lIQnZh'
    || 'VzUwWlhKa2IzZHVJSEJ2YVc1MFpYSjFjQ0JrY21GblpXNWtJR1J5WVdkemRHRnlkQ0JrY205d0lHTnZiWEJ2YzJsMGFXOXVaVzVrSUdOdmJYQnZjMmwwYVc5'
    || 'dWMzUmhjblFnYTJWNVpHOTNiaUJyWlhsd2NtVnpjeUJyWlhsMWNDQnBibkIxZENCMFpYaDBTVzV3ZFhRZ1kyOXdlU0JqZFhRZ2NHRnpkR1VnWTJ4cFkyc2dZ'
    || 'MmhoYm1kbElHTnZiblJsZUhSdFpXNTFJSEpsYzJWMElITjFZbTFwZENJdWMzQnNhWFFvSWlBaUtUdG1kVzVqZEdsdmJpQkhjeWhsTEhRcGUzTjNhWFJqYUNo'
    || 'bEtYdGpZWE5sSW1adlkzVnphVzRpT21OaGMyVWlabTlqZFhOdmRYUWlPbFYwUFc1MWJHdzdZbkpsWVdzN1kyRnpaU0prY21GblpXNTBaWElpT21OaGMyVWla'
    || 'SEpoWjJ4bFlYWmxJanBHZEQxdWRXeHNPMkp5WldGck8yTmhjMlVpYlc5MWMyVnZkbVZ5SWpwallYTmxJbTF2ZFhObGIzVjBJanBYZEQxdWRXeHNPMkp5WldG'
    || 'ck8yTmhjMlVpY0c5cGJuUmxjbTkyWlhJaU9tTmhjMlVpY0c5cGJuUmxjbTkxZENJNmRISXVaR1ZzWlhSbEtIUXVjRzlwYm5SbGNrbGtLVHRpY21WaGF6dGpZ'
    || 'WE5sSW1kdmRIQnZhVzUwWlhKallYQjBkWEpsSWpwallYTmxJbXh2YzNSd2IybHVkR1Z5WTJGd2RIVnlaU0k2Ym5JdVpHVnNaWFJsS0hRdWNHOXBiblJsY2ts'
    || 'a0tYMTlablZ1WTNScGIyNGdjbklvWlN4MExHNHNjaXhzTEdrcGUzSmxkSFZ5YmlCbFBUMDliblZzYkh4OFpTNXVZWFJwZG1WRmRtVnVkQ0U5UFdrL0tHVTll'
    || 'MkpzYjJOclpXUlBianAwTEdSdmJVVjJaVzUwVG1GdFpUcHVMR1YyWlc1MFUzbHpkR1Z0Um14aFozTTZjaXh1WVhScGRtVkZkbVZ1ZERwcExIUmhjbWRsZEVO'
    || 'dmJuUmhhVzVsY25NNlcyeGRmU3gwSVQwOWJuVnNiQ1ltS0hROVozSW9kQ2tzZENFOVBXNTFiR3dtSmxOcEtIUXBLU3hsS1Rvb1pTNWxkbVZ1ZEZONWMzUmxi'
    || 'VVpzWVdkemZEMXlMSFE5WlM1MFlYSm5aWFJEYjI1MFlXbHVaWEp6TEd3aFBUMXVkV3hzSmlaMExtbHVaR1Y0VDJZb2JDazlQVDB0TVNZbWRDNXdkWE5vS0d3'
    || 'cExHVXBmV1oxYm1OMGFXOXVJRTlrS0dVc2RDeHVMSElzYkNsN2MzZHBkR05vS0hRcGUyTmhjMlVpWm05amRYTnBiaUk2Y21WMGRYSnVJRlYwUFhKeUtGVjBM'
    || 'R1VzZEN4dUxISXNiQ2tzSVRBN1kyRnpaU0prY21GblpXNTBaWElpT25KbGRIVnliaUJHZEQxeWNpaEdkQ3hsTEhRc2JpeHlMR3dwTENFd08yTmhjMlVpYlc5'
    || 'MWMyVnZkbVZ5SWpweVpYUjFjbTRnVjNROWNuSW9WM1FzWlN4MExHNHNjaXhzS1N3aE1EdGpZWE5sSW5CdmFXNTBaWEp2ZG1WeUlqcDJZWElnYVQxc0xuQnZh'
    || 'VzUwWlhKSlpEdHlaWFIxY200Z2RISXVjMlYwS0drc2NuSW9kSEl1WjJWMEtHa3BmSHh1ZFd4c0xHVXNkQ3h1TEhJc2JDa3BMQ0V3TzJOaGMyVWlaMjkwY0c5'
    || 'cGJuUmxjbU5oY0hSMWNtVWlPbkpsZEhWeWJpQnBQV3d1Y0c5cGJuUmxja2xrTEc1eUxuTmxkQ2hwTEhKeUtHNXlMbWRsZENocEtYeDhiblZzYkN4bExIUXNi'
    || 'aXh5TEd3cEtTd2hNSDF5WlhSMWNtNGhNWDFtZFc1amRHbHZiaUJMY3lobEtYdDJZWElnZEQxMWJpaGxMblJoY21kbGRDazdhV1lvZENFOVBXNTFiR3dwZTNa'
    || 'aGNpQnVQWE51S0hRcE8ybG1LRzRoUFQxdWRXeHNLWHRwWmloMFBXNHVkR0ZuTEhROVBUMHhNeWw3YVdZb2REMU1jeWh1S1N4MElUMDliblZzYkNsN1pTNWli'
    || 'RzlqYTJWa1QyNDlkQ3haY3lobExuQnlhVzl5YVhSNUxHWjFibU4wYVc5dUtDbDdKSE1vYmlsOUtUdHlaWFIxY201OWZXVnNjMlVnYVdZb2REMDlQVE1tSm00'
    || 'dWMzUmhkR1ZPYjJSbExtTjFjbkpsYm5RdWJXVnRiMmw2WldSVGRHRjBaUzVwYzBSbGFIbGtjbUYwWldRcGUyVXVZbXh2WTJ0bFpFOXVQVzR1ZEdGblBUMDlN'
    || 'ejl1TG5OMFlYUmxUbTlrWlM1amIyNTBZV2x1WlhKSmJtWnZPbTUxYkd3N2NtVjBkWEp1ZlgxOVpTNWliRzlqYTJWa1QyNDliblZzYkgxbWRXNWpkR2x2YmlC'
    || 'SGNpaGxLWHRwWmlobExtSnNiMk5yWldSUGJpRTlQVzUxYkd3cGNtVjBkWEp1SVRFN1ptOXlLSFpoY2lCMFBXVXVkR0Z5WjJWMFEyOXVkR0ZwYm1WeWN6c3dQ'
    || 'SFF1YkdWdVozUm9PeWw3ZG1GeUlHNDlhbWtvWlM1a2IyMUZkbVZ1ZEU1aGJXVXNaUzVsZG1WdWRGTjVjM1JsYlVac1lXZHpMSFJiTUYwc1pTNXVZWFJwZG1W'
    || 'RmRtVnVkQ2s3YVdZb2JqMDlQVzUxYkd3cGUyNDlaUzV1WVhScGRtVkZkbVZ1ZER0MllYSWdjajF1WlhjZ2JpNWpiMjV6ZEhKMVkzUnZjaWh1TG5SNWNHVXNi'
    || 'aWs3Wm1rOWNpeHVMblJoY21kbGRDNWthWE53WVhSamFFVjJaVzUwS0hJcExHWnBQVzUxYkd4OVpXeHpaU0J5WlhSMWNtNGdkRDFuY2lodUtTeDBJVDA5Ym5W'
    || 'c2JDWW1VMmtvZENrc1pTNWliRzlqYTJWa1QyNDliaXdoTVR0MExuTm9hV1owS0NsOWNtVjBkWEp1SVRCOVpuVnVZM1JwYjI0Z1dITW9aU3gwTEc0cGUwZHlL'
    || 'R1VwSmladUxtUmxiR1YwWlNoMEtYMW1kVzVqZEdsdmJpQlFaQ2dwZTNkcFBTRXhMRlYwSVQwOWJuVnNiQ1ltUjNJb1ZYUXBKaVlvVlhROWJuVnNiQ2tzUm5R'
    || 'aFBUMXVkV3hzSmlaSGNpaEdkQ2ttSmloR2REMXVkV3hzS1N4WGRDRTlQVzUxYkd3bUprZHlLRmQwS1NZbUtGZDBQVzUxYkd3cExIUnlMbVp2Y2tWaFkyZ29X'
    || 'SE1wTEc1eUxtWnZja1ZoWTJnb1dITXBmV1oxYm1OMGFXOXVJR3h5S0dVc2RDbDdaUzVpYkc5amEyVmtUMjQ5UFQxMEppWW9aUzVpYkc5amEyVmtUMjQ5Ym5W'
    || 'c2JDeDNhWHg4S0hkcFBTRXdMR011ZFc1emRHRmliR1ZmYzJOb1pXUjFiR1ZEWVd4c1ltRmpheWhqTG5WdWMzUmhZbXhsWDA1dmNtMWhiRkJ5YVc5eWFYUjVM'
    || 'RkJrS1NrcGZXWjFibU4wYVc5dUlHbHlLR1VwZTJaMWJtTjBhVzl1SUhRb2JDbDdjbVYwZFhKdUlHeHlLR3dzWlNsOWFXWW9NRHhaY2k1c1pXNW5kR2dwZTJ4'
    || 'eUtGbHlXekJkTEdVcE8yWnZjaWgyWVhJZ2JqMHhPMjQ4V1hJdWJHVnVaM1JvTzI0ckt5bDdkbUZ5SUhJOVdYSmJibDA3Y2k1aWJHOWphMlZrVDI0OVBUMWxK'
    || 'aVlvY2k1aWJHOWphMlZrVDI0OWJuVnNiQ2w5ZldadmNpaFZkQ0U5UFc1MWJHd21KbXh5S0ZWMExHVXBMRVowSVQwOWJuVnNiQ1ltYkhJb1JuUXNaU2tzVjNR'
    || 'aFBUMXVkV3hzSmlac2NpaFhkQ3hsS1N4MGNpNW1iM0pGWVdOb0tIUXBMRzV5TG1admNrVmhZMmdvZENrc2JqMHdPMjQ4Vm5RdWJHVnVaM1JvTzI0ckt5bHlQ'
    || 'VlowVzI1ZExISXVZbXh2WTJ0bFpFOXVQVDA5WlNZbUtISXVZbXh2WTJ0bFpFOXVQVzUxYkd3cE8yWnZjaWc3TUR4V2RDNXNaVzVuZEdnbUppaHVQVlowV3pC'
    || 'ZExHNHVZbXh2WTJ0bFpFOXVQVDA5Ym5Wc2JDazdLVXR6S0c0cExHNHVZbXh2WTJ0bFpFOXVQVDA5Ym5Wc2JDWW1WblF1YzJocFpuUW9LWDEyWVhJZ2EyNDlT'
    || 'eTVTWldGamRFTjFjbkpsYm5SQ1lYUmphRU52Ym1acFp5eExjajBoTUR0bWRXNWpkR2x2YmlCTVpDaGxMSFFzYml4eUtYdDJZWElnYkQxMVpTeHBQV3R1TG5S'
    || 'eVlXNXphWFJwYjI0N2EyNHVkSEpoYm5OcGRHbHZiajF1ZFd4c08zUnllWHQxWlQweExHdHBLR1VzZEN4dUxISXBmV1pwYm1Gc2JIbDdkV1U5YkN4cmJpNTBj'
    || 'bUZ1YzJsMGFXOXVQV2w5ZldaMWJtTjBhVzl1SUVsa0tHVXNkQ3h1TEhJcGUzWmhjaUJzUFhWbExHazlhMjR1ZEhKaGJuTnBkR2x2Ymp0cmJpNTBjbUZ1YzJs'
    || 'MGFXOXVQVzUxYkd3N2RISjVlM1ZsUFRRc2Eya29aU3gwTEc0c2NpbDlabWx1WVd4c2VYdDFaVDFzTEd0dUxuUnlZVzV6YVhScGIyNDlhWDE5Wm5WdVkzUnBi'
    || 'MjRnYTJrb1pTeDBMRzRzY2lsN2FXWW9TM0lwZTNaaGNpQnNQV3BwS0dVc2RDeHVMSElwTzJsbUtHdzlQVDF1ZFd4c0tVSnBLR1VzZEN4eUxGaHlMRzRwTEVk'
    || 'ektHVXNjaWs3Wld4elpTQnBaaWhQWkNoc0xHVXNkQ3h1TEhJcEtYSXVjM1J2Y0ZCeWIzQmhaMkYwYVc5dUtDazdaV3h6WlNCcFppaEhjeWhsTEhJcExIUW1O'
    || 'Q1ltTFRFOFJHUXVhVzVrWlhoUFppaGxLU2w3Wm05eUtEdHNJVDA5Ym5Wc2JEc3BlM1poY2lCcFBXZHlLR3dwTzJsbUtHa2hQVDF1ZFd4c0ppWkljeWhwS1N4'
    || 'cFBXcHBLR1VzZEN4dUxISXBMR2s5UFQxdWRXeHNKaVpDYVNobExIUXNjaXhZY2l4dUtTeHBQVDA5YkNsaWNtVmhhenRzUFdsOWJDRTlQVzUxYkd3bUpuSXVj'
    || 'M1J2Y0ZCeWIzQmhaMkYwYVc5dUtDbDlaV3h6WlNCQ2FTaGxMSFFzY2l4dWRXeHNMRzRwZlgxMllYSWdXSEk5Ym5Wc2JEdG1kVzVqZEdsdmJpQnFhU2hsTEhR'
    || 'c2JpeHlLWHRwWmloWWNqMXVkV3hzTEdVOWNHa29jaWtzWlQxMWJpaGxLU3hsSVQwOWJuVnNiQ2xwWmloMFBYTnVLR1VwTEhROVBUMXVkV3hzS1dVOWJuVnNi'
    || 'RHRsYkhObElHbG1LRzQ5ZEM1MFlXY3NiajA5UFRFektYdHBaaWhsUFV4ektIUXBMR1VoUFQxdWRXeHNLWEpsZEhWeWJpQmxPMlU5Ym5Wc2JIMWxiSE5sSUds'
    || 'bUtHNDlQVDB6S1h0cFppaDBMbk4wWVhSbFRtOWtaUzVqZFhKeVpXNTBMbTFsYlc5cGVtVmtVM1JoZEdVdWFYTkVaV2g1WkhKaGRHVmtLWEpsZEhWeWJpQjBM'
    || 'blJoWnowOVBUTS9kQzV6ZEdGMFpVNXZaR1V1WTI5dWRHRnBibVZ5U1c1bWJ6cHVkV3hzTzJVOWJuVnNiSDFsYkhObElIUWhQVDFsSmlZb1pUMXVkV3hzS1R0'
    || 'eVpYUjFjbTRnV0hJOVpTeHVkV3hzZldaMWJtTjBhVzl1SUZwektHVXBlM04zYVhSamFDaGxLWHRqWVhObEltTmhibU5sYkNJNlkyRnpaU0pqYkdsamF5STZZ'
    || 'MkZ6WlNKamJHOXpaU0k2WTJGelpTSmpiMjUwWlhoMGJXVnVkU0k2WTJGelpTSmpiM0I1SWpwallYTmxJbU4xZENJNlkyRnpaU0poZFhoamJHbGpheUk2WTJG'
    || 'elpTSmtZbXhqYkdsamF5STZZMkZ6WlNKa2NtRm5aVzVrSWpwallYTmxJbVJ5WVdkemRHRnlkQ0k2WTJGelpTSmtjbTl3SWpwallYTmxJbVp2WTNWemFXNGlP'
    || 'bU5oYzJVaVptOWpkWE52ZFhRaU9tTmhjMlVpYVc1d2RYUWlPbU5oYzJVaWFXNTJZV3hwWkNJNlkyRnpaU0pyWlhsa2IzZHVJanBqWVhObEltdGxlWEJ5WlhO'
    || 'eklqcGpZWE5sSW10bGVYVndJanBqWVhObEltMXZkWE5sWkc5M2JpSTZZMkZ6WlNKdGIzVnpaWFZ3SWpwallYTmxJbkJoYzNSbElqcGpZWE5sSW5CaGRYTmxJ'
    || 'anBqWVhObEluQnNZWGtpT21OaGMyVWljRzlwYm5SbGNtTmhibU5sYkNJNlkyRnpaU0p3YjJsdWRHVnlaRzkzYmlJNlkyRnpaU0p3YjJsdWRHVnlkWEFpT21O'
    || 'aGMyVWljbUYwWldOb1lXNW5aU0k2WTJGelpTSnlaWE5sZENJNlkyRnpaU0p5WlhOcGVtVWlPbU5oYzJVaWMyVmxhMlZrSWpwallYTmxJbk4xWW0xcGRDSTZZ'
    || 'MkZ6WlNKMGIzVmphR05oYm1ObGJDSTZZMkZ6WlNKMGIzVmphR1Z1WkNJNlkyRnpaU0owYjNWamFITjBZWEowSWpwallYTmxJblp2YkhWdFpXTm9ZVzVuWlNJ'
    || 'NlkyRnpaU0pqYUdGdVoyVWlPbU5oYzJVaWMyVnNaV04wYVc5dVkyaGhibWRsSWpwallYTmxJblJsZUhSSmJuQjFkQ0k2WTJGelpTSmpiMjF3YjNOcGRHbHZi'
    || 'bk4wWVhKMElqcGpZWE5sSW1OdmJYQnZjMmwwYVc5dVpXNWtJanBqWVhObEltTnZiWEJ2YzJsMGFXOXVkWEJrWVhSbElqcGpZWE5sSW1KbFptOXlaV0pzZFhJ'
    || 'aU9tTmhjMlVpWVdaMFpYSmliSFZ5SWpwallYTmxJbUpsWm05eVpXbHVjSFYwSWpwallYTmxJbUpzZFhJaU9tTmhjMlVpWm5Wc2JITmpjbVZsYm1Ob1lXNW5a'
    || 'U0k2WTJGelpTSm1iMk4xY3lJNlkyRnpaU0pvWVhOb1kyaGhibWRsSWpwallYTmxJbkJ2Y0hOMFlYUmxJanBqWVhObEluTmxiR1ZqZENJNlkyRnpaU0p6Wld4'
    || 'bFkzUnpkR0Z5ZENJNmNtVjBkWEp1SURFN1kyRnpaU0prY21GbklqcGpZWE5sSW1SeVlXZGxiblJsY2lJNlkyRnpaU0prY21GblpYaHBkQ0k2WTJGelpTSmtj'
    || 'bUZuYkdWaGRtVWlPbU5oYzJVaVpISmhaMjkyWlhJaU9tTmhjMlVpYlc5MWMyVnRiM1psSWpwallYTmxJbTF2ZFhObGIzVjBJanBqWVhObEltMXZkWE5sYjNa'
    || 'bGNpSTZZMkZ6WlNKd2IybHVkR1Z5Ylc5MlpTSTZZMkZ6WlNKd2IybHVkR1Z5YjNWMElqcGpZWE5sSW5CdmFXNTBaWEp2ZG1WeUlqcGpZWE5sSW5OamNtOXNi'
    || 'Q0k2WTJGelpTSjBiMmRuYkdVaU9tTmhjMlVpZEc5MVkyaHRiM1psSWpwallYTmxJbmRvWldWc0lqcGpZWE5sSW0xdmRYTmxaVzUwWlhJaU9tTmhjMlVpYlc5'
    || 'MWMyVnNaV0YyWlNJNlkyRnpaU0p3YjJsdWRHVnlaVzUwWlhJaU9tTmhjMlVpY0c5cGJuUmxjbXhsWVhabElqcHlaWFIxY200Z05EdGpZWE5sSW0xbGMzTmha'
    || 'MlVpT25OM2FYUmphQ2hmWkNncEtYdGpZWE5sSUhscE9uSmxkSFZ5YmlBeE8yTmhjMlVnUm5NNmNtVjBkWEp1SURRN1kyRnpaU0JXY2pwallYTmxJRk5rT25K'
    || 'bGRIVnliaUF4Tmp0allYTmxJRmR6T25KbGRIVnliaUExTXpZNE56QTVNVEk3WkdWbVlYVnNkRHB5WlhSMWNtNGdNVFo5WkdWbVlYVnNkRHB5WlhSMWNtNGdN'
    || 'VFo5ZlhaaGNpQkNkRDF1ZFd4c0xFNXBQVzUxYkd3c1duSTliblZzYkR0bWRXNWpkR2x2YmlCeGN5Z3BlMmxtS0ZweUtYSmxkSFZ5YmlCYWNqdDJZWElnWlN4'
    || 'MFBVNXBMRzQ5ZEM1c1pXNW5kR2dzY2l4c1BTSjJZV3gxWlNKcGJpQkNkRDlDZEM1MllXeDFaVHBDZEM1MFpYaDBRMjl1ZEdWdWRDeHBQV3d1YkdWdVozUm9P'
    || 'Mlp2Y2lobFBUQTdaVHh1SmlaMFcyVmRQVDA5YkZ0bFhUdGxLeXNwTzNaaGNpQnpQVzR0WlR0bWIzSW9jajB4TzNJOFBYTW1KblJiYmkxeVhUMDlQV3hiYVMx'
    || 'eVhUdHlLeXNwTzNKbGRIVnliaUJhY2oxc0xuTnNhV05sS0dVc01UeHlQekV0Y2pwMmIybGtJREFwZldaMWJtTjBhVzl1SUhGeUtHVXBlM1poY2lCMFBXVXVh'
    || 'MlY1UTI5a1pUdHlaWFIxY200aVkyaGhja052WkdVaWFXNGdaVDhvWlQxbExtTm9ZWEpEYjJSbExHVTlQVDB3SmlaMFBUMDlNVE1tSmlobFBURXpLU2s2WlQx'
    || 'MExHVTlQVDB4TUNZbUtHVTlNVE1wTERNeVBEMWxmSHhsUFQwOU1UTS9aVG93ZldaMWJtTjBhVzl1SUVweUtDbDdjbVYwZFhKdUlUQjlablZ1WTNScGIyNGdT'
    || 'bk1vS1h0eVpYUjFjbTRoTVgxbWRXNWpkR2x2YmlCbGRDaGxLWHRtZFc1amRHbHZiaUIwS0c0c2NpeHNMR2tzY3lsN2RHaHBjeTVmY21WaFkzUk9ZVzFsUFc0'
    || 'c2RHaHBjeTVmZEdGeVoyVjBTVzV6ZEQxc0xIUm9hWE11ZEhsd1pUMXlMSFJvYVhNdWJtRjBhWFpsUlhabGJuUTlhU3gwYUdsekxuUmhjbWRsZEQxekxIUm9h'
    || 'WE11WTNWeWNtVnVkRlJoY21kbGREMXVkV3hzTzJadmNpaDJZWElnWkNCcGJpQmxLV1V1YUdGelQzZHVVSEp2Y0dWeWRIa29aQ2ttSmlodVBXVmJaRjBzZEdo'
    || 'cGMxdGtYVDF1UDI0b2FTazZhVnRrWFNrN2NtVjBkWEp1SUhSb2FYTXVhWE5FWldaaGRXeDBVSEpsZG1WdWRHVmtQU2hwTG1SbFptRjFiSFJRY21WMlpXNTBa'
    || 'V1FoUFc1MWJHdy9hUzVrWldaaGRXeDBVSEpsZG1WdWRHVmtPbWt1Y21WMGRYSnVWbUZzZFdVOVBUMGhNU2svU25JNlNuTXNkR2hwY3k1cGMxQnliM0JoWjJG'
    || 'MGFXOXVVM1J2Y0hCbFpEMUtjeXgwYUdsemZYSmxkSFZ5YmlCTUtIUXVjSEp2ZEc5MGVYQmxMSHR3Y21WMlpXNTBSR1ZtWVhWc2REcG1kVzVqZEdsdmJpZ3Bl'
    || 'M1JvYVhNdVpHVm1ZWFZzZEZCeVpYWmxiblJsWkQwaE1EdDJZWElnYmoxMGFHbHpMbTVoZEdsMlpVVjJaVzUwTzI0bUppaHVMbkJ5WlhabGJuUkVaV1poZFd4'
    || 'MFAyNHVjSEpsZG1WdWRFUmxabUYxYkhRb0tUcDBlWEJsYjJZZ2JpNXlaWFIxY201V1lXeDFaU0U5SW5WdWEyNXZkMjRpSmlZb2JpNXlaWFIxY201V1lXeDFa'
    || 'VDBoTVNrc2RHaHBjeTVwYzBSbFptRjFiSFJRY21WMlpXNTBaV1E5U25JcGZTeHpkRzl3VUhKdmNHRm5ZWFJwYjI0NlpuVnVZM1JwYjI0b0tYdDJZWElnYmox'
    || 'MGFHbHpMbTVoZEdsMlpVVjJaVzUwTzI0bUppaHVMbk4wYjNCUWNtOXdZV2RoZEdsdmJqOXVMbk4wYjNCUWNtOXdZV2RoZEdsdmJpZ3BPblI1Y0dWdlppQnVM'
    || 'bU5oYm1ObGJFSjFZbUpzWlNFOUluVnVhMjV2ZDI0aUppWW9iaTVqWVc1alpXeENkV0ppYkdVOUlUQXBMSFJvYVhNdWFYTlFjbTl3WVdkaGRHbHZibE4wYjNC'
    || 'd1pXUTlTbklwZlN4d1pYSnphWE4wT21aMWJtTjBhVzl1S0NsN2ZTeHBjMUJsY25OcGMzUmxiblE2U25KOUtTeDBmWFpoY2lCcWJqMTdaWFpsYm5SUWFHRnpa'
    || 'VG93TEdKMVltSnNaWE02TUN4allXNWpaV3hoWW14bE9qQXNkR2x0WlZOMFlXMXdPbVoxYm1OMGFXOXVLR1VwZTNKbGRIVnliaUJsTG5ScGJXVlRkR0Z0Y0h4'
    || 'OFJHRjBaUzV1YjNjb0tYMHNaR1ZtWVhWc2RGQnlaWFpsYm5SbFpEb3dMR2x6VkhKMWMzUmxaRG93ZlN4RGFUMWxkQ2hxYmlrc2IzSTlUQ2g3ZlN4cWJpeDdk'
    || 'bWxsZHpvd0xHUmxkR0ZwYkRvd2ZTa3NRV1E5WlhRb2IzSXBMRlJwTEZKcExITnlMR0p5UFV3b2UzMHNiM0lzZTNOamNtVmxibGc2TUN4elkzSmxaVzVaT2pB'
    || 'c1kyeHBaVzUwV0Rvd0xHTnNhV1Z1ZEZrNk1DeHdZV2RsV0Rvd0xIQmhaMlZaT2pBc1kzUnliRXRsZVRvd0xITm9hV1owUzJWNU9qQXNZV3gwUzJWNU9qQXNi'
    || 'V1YwWVV0bGVUb3dMR2RsZEUxdlpHbG1hV1Z5VTNSaGRHVTZUMmtzWW5WMGRHOXVPakFzWW5WMGRHOXVjem93TEhKbGJHRjBaV1JVWVhKblpYUTZablZ1WTNS'
    || 'cGIyNG9aU2w3Y21WMGRYSnVJR1V1Y21Wc1lYUmxaRlJoY21kbGREMDlQWFp2YVdRZ01EOWxMbVp5YjIxRmJHVnRaVzUwUFQwOVpTNXpjbU5GYkdWdFpXNTBQ'
    || 'MlV1ZEc5RmJHVnRaVzUwT21VdVpuSnZiVVZzWlcxbGJuUTZaUzV5Wld4aGRHVmtWR0Z5WjJWMGZTeHRiM1psYldWdWRGZzZablZ1WTNScGIyNG9aU2w3Y21W'
    || 'MGRYSnVJbTF2ZG1WdFpXNTBXQ0pwYmlCbFAyVXViVzkyWlcxbGJuUllPaWhsSVQwOWMzSW1KaWh6Y2lZbVpTNTBlWEJsUFQwOUltMXZkWE5sYlc5MlpTSS9L'
    || 'RlJwUFdVdWMyTnlaV1Z1V0MxemNpNXpZM0psWlc1WUxGSnBQV1V1YzJOeVpXVnVXUzF6Y2k1elkzSmxaVzVaS1RwU2FUMVVhVDB3TEhOeVBXVXBMRlJwS1gw'
    || 'c2JXOTJaVzFsYm5SWk9tWjFibU4wYVc5dUtHVXBlM0psZEhWeWJpSnRiM1psYldWdWRGa2lhVzRnWlQ5bExtMXZkbVZ0Wlc1MFdUcFNhWDE5S1N4aWN6MWxk'
    || 'Q2hpY2lrc1RXUTlUQ2g3ZlN4aWNpeDdaR0YwWVZSeVlXNXpabVZ5T2pCOUtTeDZaRDFsZENoTlpDa3NWV1E5VENoN2ZTeHZjaXg3Y21Wc1lYUmxaRlJoY21k'
    || 'bGREb3dmU2tzUkdrOVpYUW9WV1FwTEVaa1BVd29lMzBzYW00c2UyRnVhVzFoZEdsdmJrNWhiV1U2TUN4bGJHRndjMlZrVkdsdFpUb3dMSEJ6WlhWa2IwVnNa'
    || 'VzFsYm5RNk1IMHBMRmRrUFdWMEtFWmtLU3hXWkQxTUtIdDlMR3B1TEh0amJHbHdZbTloY21SRVlYUmhPbVoxYm1OMGFXOXVLR1VwZTNKbGRIVnliaUpqYkds'
    || 'd1ltOWhjbVJFWVhSaEltbHVJR1UvWlM1amJHbHdZbTloY21SRVlYUmhPbmRwYm1SdmR5NWpiR2x3WW05aGNtUkVZWFJoZlgwcExFSmtQV1YwS0Zaa0tTeEla'
    || 'RDFNS0h0OUxHcHVMSHRrWVhSaE9qQjlLU3hsZFQxbGRDaElaQ2tzSkdROWUwVnpZem9pUlhOallYQmxJaXhUY0dGalpXSmhjam9pSUNJc1RHVm1kRG9pUVhK'
    || 'eWIzZE1aV1owSWl4VmNEb2lRWEp5YjNkVmNDSXNVbWxuYUhRNklrRnljbTkzVW1sbmFIUWlMRVJ2ZDI0NklrRnljbTkzUkc5M2JpSXNSR1ZzT2lKRVpXeGxk'
    || 'R1VpTEZkcGJqb2lUMU1pTEUxbGJuVTZJa052Ym5SbGVIUk5aVzUxSWl4QmNIQnpPaUpEYjI1MFpYaDBUV1Z1ZFNJc1UyTnliMnhzT2lKVFkzSnZiR3hNYjJO'
    || 'cklpeE5iM3BRY21sdWRHRmliR1ZMWlhrNklsVnVhV1JsYm5ScFptbGxaQ0o5TEZGa1BYczRPaUpDWVdOcmMzQmhZMlVpTERrNklsUmhZaUlzTVRJNklrTnNa'
    || 'V0Z5SWl3eE16b2lSVzUwWlhJaUxERTJPaUpUYUdsbWRDSXNNVGM2SWtOdmJuUnliMndpTERFNE9pSkJiSFFpTERFNU9pSlFZWFZ6WlNJc01qQTZJa05oY0hO'
    || 'TWIyTnJJaXd5TnpvaVJYTmpZWEJsSWl3ek1qb2lJQ0lzTXpNNklsQmhaMlZWY0NJc016UTZJbEJoWjJWRWIzZHVJaXd6TlRvaVJXNWtJaXd6TmpvaVNHOXRa'
    || 'U0lzTXpjNklrRnljbTkzVEdWbWRDSXNNemc2SWtGeWNtOTNWWEFpTERNNU9pSkJjbkp2ZDFKcFoyaDBJaXcwTURvaVFYSnliM2RFYjNkdUlpdzBOVG9pU1c1'
    || 'elpYSjBJaXcwTmpvaVJHVnNaWFJsSWl3eE1USTZJa1l4SWl3eE1UTTZJa1l5SWl3eE1UUTZJa1l6SWl3eE1UVTZJa1kwSWl3eE1UWTZJa1kxSWl3eE1UYzZJ'
    || 'a1kySWl3eE1UZzZJa1kzSWl3eE1UazZJa1k0SWl3eE1qQTZJa1k1SWl3eE1qRTZJa1l4TUNJc01USXlPaUpHTVRFaUxERXlNem9pUmpFeUlpd3hORFE2SWs1'
    || 'MWJVeHZZMnNpTERFME5Ub2lVMk55YjJ4c1RHOWpheUlzTWpJME9pSk5aWFJoSW4wc1dXUTllMEZzZERvaVlXeDBTMlY1SWl4RGIyNTBjbTlzT2lKamRISnNT'
    || 'MlY1SWl4TlpYUmhPaUp0WlhSaFMyVjVJaXhUYUdsbWREb2ljMmhwWm5STFpYa2lmVHRtZFc1amRHbHZiaUJIWkNobEtYdDJZWElnZEQxMGFHbHpMbTVoZEds'
    || 'MlpVVjJaVzUwTzNKbGRIVnliaUIwTG1kbGRFMXZaR2xtYVdWeVUzUmhkR1UvZEM1blpYUk5iMlJwWm1sbGNsTjBZWFJsS0dVcE9paGxQVmxrVzJWZEtUOGhJ'
    || 'WFJiWlYwNklURjlablZ1WTNScGIyNGdUMmtvS1h0eVpYUjFjbTRnUjJSOWRtRnlJRXRrUFV3b2UzMHNiM0lzZTJ0bGVUcG1kVzVqZEdsdmJpaGxLWHRwWmlo'
    || 'bExtdGxlU2w3ZG1GeUlIUTlKR1JiWlM1clpYbGRmSHhsTG10bGVUdHBaaWgwSVQwOUlsVnVhV1JsYm5ScFptbGxaQ0lwY21WMGRYSnVJSFI5Y21WMGRYSnVJ'
    || 'R1V1ZEhsd1pUMDlQU0pyWlhsd2NtVnpjeUkvS0dVOWNYSW9aU2tzWlQwOVBURXpQeUpGYm5SbGNpSTZVM1J5YVc1bkxtWnliMjFEYUdGeVEyOWtaU2hsS1Nr'
    || 'NlpTNTBlWEJsUFQwOUltdGxlV1J2ZDI0aWZIeGxMblI1Y0dVOVBUMGlhMlY1ZFhBaVAxRmtXMlV1YTJWNVEyOWtaVjE4ZkNKVmJtbGtaVzUwYVdacFpXUWlP'
    || 'aUlpZlN4amIyUmxPakFzYkc5allYUnBiMjQ2TUN4amRISnNTMlY1T2pBc2MyaHBablJMWlhrNk1DeGhiSFJMWlhrNk1DeHRaWFJoUzJWNU9qQXNjbVZ3WldG'
    || 'ME9qQXNiRzlqWVd4bE9qQXNaMlYwVFc5a2FXWnBaWEpUZEdGMFpUcFBhU3hqYUdGeVEyOWtaVHBtZFc1amRHbHZiaWhsS1h0eVpYUjFjbTRnWlM1MGVYQmxQ'
    || 'VDA5SW10bGVYQnlaWE56SWo5eGNpaGxLVG93ZlN4clpYbERiMlJsT21aMWJtTjBhVzl1S0dVcGUzSmxkSFZ5YmlCbExuUjVjR1U5UFQwaWEyVjVaRzkzYmlK'
    || 'OGZHVXVkSGx3WlQwOVBTSnJaWGwxY0NJL1pTNXJaWGxEYjJSbE9qQjlMSGRvYVdOb09tWjFibU4wYVc5dUtHVXBlM0psZEhWeWJpQmxMblI1Y0dVOVBUMGlh'
    || 'MlY1Y0hKbGMzTWlQM0Z5S0dVcE9tVXVkSGx3WlQwOVBTSnJaWGxrYjNkdUlueDhaUzUwZVhCbFBUMDlJbXRsZVhWd0lqOWxMbXRsZVVOdlpHVTZNSDE5S1N4'
    || 'WVpEMWxkQ2hMWkNrc1dtUTlUQ2g3ZlN4aWNpeDdjRzlwYm5SbGNrbGtPakFzZDJsa2RHZzZNQ3hvWldsbmFIUTZNQ3h3Y21WemMzVnlaVG93TEhSaGJtZGxi'
    || 'blJwWVd4UWNtVnpjM1Z5WlRvd0xIUnBiSFJZT2pBc2RHbHNkRms2TUN4MGQybHpkRG93TEhCdmFXNTBaWEpVZVhCbE9qQXNhWE5RY21sdFlYSjVPakI5S1N4'
    || 'MGRUMWxkQ2hhWkNrc2NXUTlUQ2g3ZlN4dmNpeDdkRzkxWTJobGN6b3dMSFJoY21kbGRGUnZkV05vWlhNNk1DeGphR0Z1WjJWa1ZHOTFZMmhsY3pvd0xHRnNk'
    || 'RXRsZVRvd0xHMWxkR0ZMWlhrNk1DeGpkSEpzUzJWNU9qQXNjMmhwWm5STFpYazZNQ3huWlhSTmIyUnBabWxsY2xOMFlYUmxPazlwZlNrc1NtUTlaWFFvY1dR'
    || 'cExHSmtQVXdvZTMwc2FtNHNlM0J5YjNCbGNuUjVUbUZ0WlRvd0xHVnNZWEJ6WldSVWFXMWxPakFzY0hObGRXUnZSV3hsYldWdWREb3dmU2tzWldZOVpYUW9Z'
    || 'bVFwTEhSbVBVd29lMzBzWW5Jc2UyUmxiSFJoV0RwbWRXNWpkR2x2YmlobEtYdHlaWFIxY200aVpHVnNkR0ZZSW1sdUlHVS9aUzVrWld4MFlWZzZJbmRvWldW'
    || 'c1JHVnNkR0ZZSW1sdUlHVS9MV1V1ZDJobFpXeEVaV3gwWVZnNk1IMHNaR1ZzZEdGWk9tWjFibU4wYVc5dUtHVXBlM0psZEhWeWJpSmtaV3gwWVZraWFXNGda'
    || 'VDlsTG1SbGJIUmhXVG9pZDJobFpXeEVaV3gwWVZraWFXNGdaVDh0WlM1M2FHVmxiRVJsYkhSaFdUb2lkMmhsWld4RVpXeDBZU0pwYmlCbFB5MWxMbmRvWldW'
    || 'c1JHVnNkR0U2TUgwc1pHVnNkR0ZhT2pBc1pHVnNkR0ZOYjJSbE9qQjlLU3h1WmoxbGRDaDBaaWtzY21ZOVd6a3NNVE1zTWpjc016SmRMRkJwUFdvbUppSkRi'
    || 'MjF3YjNOcGRHbHZia1YyWlc1MEltbHVJSGRwYm1SdmR5eDFjajF1ZFd4c08yb21KaUprYjJOMWJXVnVkRTF2WkdVaWFXNGdaRzlqZFcxbGJuUW1KaWgxY2ox'
    || 'a2IyTjFiV1Z1ZEM1a2IyTjFiV1Z1ZEUxdlpHVXBPM1poY2lCc1pqMXFKaVlpVkdWNGRFVjJaVzUwSW1sdUlIZHBibVJ2ZHlZbUlYVnlMRzUxUFdvbUppZ2hV'
    || 'R2w4ZkhWeUppWTRQSFZ5SmlZeE1UNDlkWElwTEhKMVBTSWdJaXhzZFQwaE1UdG1kVzVqZEdsdmJpQnBkU2hsTEhRcGUzTjNhWFJqYUNobEtYdGpZWE5sSW10'
    || 'bGVYVndJanB5WlhSMWNtNGdjbVl1YVc1a1pYaFBaaWgwTG10bGVVTnZaR1VwSVQwOUxURTdZMkZ6WlNKclpYbGtiM2R1SWpweVpYUjFjbTRnZEM1clpYbERi'
    || 'MlJsSVQwOU1qSTVPMk5oYzJVaWEyVjVjSEpsYzNNaU9tTmhjMlVpYlc5MWMyVmtiM2R1SWpwallYTmxJbVp2WTNWemIzVjBJanB5WlhSMWNtNGhNRHRrWlda'
    || 'aGRXeDBPbkpsZEhWeWJpRXhmWDFtZFc1amRHbHZiaUJ2ZFNobEtYdHlaWFIxY200Z1pUMWxMbVJsZEdGcGJDeDBlWEJsYjJZZ1pUMDlJbTlpYW1WamRDSW1K'
    || 'aUprWVhSaEltbHVJR1UvWlM1a1lYUmhPbTUxYkd4OWRtRnlJRTV1UFNFeE8yWjFibU4wYVc5dUlHOW1LR1VzZENsN2MzZHBkR05vS0dVcGUyTmhjMlVpWTI5'
    || 'dGNHOXphWFJwYjI1bGJtUWlPbkpsZEhWeWJpQnZkU2gwS1R0allYTmxJbXRsZVhCeVpYTnpJanB5WlhSMWNtNGdkQzUzYUdsamFDRTlQVE15UDI1MWJHdzZL'
    || 'R3gxUFNFd0xISjFLVHRqWVhObEluUmxlSFJKYm5CMWRDSTZjbVYwZFhKdUlHVTlkQzVrWVhSaExHVTlQVDF5ZFNZbWJIVS9iblZzYkRwbE8yUmxabUYxYkhR'
    || 'NmNtVjBkWEp1SUc1MWJHeDlmV1oxYm1OMGFXOXVJSE5tS0dVc2RDbDdhV1lvVG00cGNtVjBkWEp1SUdVOVBUMGlZMjl0Y0c5emFYUnBiMjVsYm1RaWZId2hV'
    || 'R2ttSm1sMUtHVXNkQ2svS0dVOWNYTW9LU3hhY2oxT2FUMUNkRDF1ZFd4c0xFNXVQU0V4TEdVcE9tNTFiR3c3YzNkcGRHTm9LR1VwZTJOaGMyVWljR0Z6ZEdV'
    || 'aU9uSmxkSFZ5YmlCdWRXeHNPMk5oYzJVaWEyVjVjSEpsYzNNaU9tbG1LQ0VvZEM1amRISnNTMlY1Zkh4MExtRnNkRXRsZVh4OGRDNXRaWFJoUzJWNUtYeDhk'
    || 'QzVqZEhKc1MyVjVKaVowTG1Gc2RFdGxlU2w3YVdZb2RDNWphR0Z5SmlZeFBIUXVZMmhoY2k1c1pXNW5kR2dwY21WMGRYSnVJSFF1WTJoaGNqdHBaaWgwTG5k'
    || 'b2FXTm9LWEpsZEhWeWJpQlRkSEpwYm1jdVpuSnZiVU5vWVhKRGIyUmxLSFF1ZDJocFkyZ3BmWEpsZEhWeWJpQnVkV3hzTzJOaGMyVWlZMjl0Y0c5emFYUnBi'
    || 'MjVsYm1RaU9uSmxkSFZ5YmlCdWRTWW1kQzVzYjJOaGJHVWhQVDBpYTI4aVAyNTFiR3c2ZEM1a1lYUmhPMlJsWm1GMWJIUTZjbVYwZFhKdUlHNTFiR3g5Zlha'
    || 'aGNpQjFaajE3WTI5c2IzSTZJVEFzWkdGMFpUb2hNQ3hrWVhSbGRHbHRaVG9oTUN3aVpHRjBaWFJwYldVdGJHOWpZV3dpT2lFd0xHVnRZV2xzT2lFd0xHMXZi'
    || 'blJvT2lFd0xHNTFiV0psY2pvaE1DeHdZWE56ZDI5eVpEb2hNQ3h5WVc1blpUb2hNQ3h6WldGeVkyZzZJVEFzZEdWc09pRXdMSFJsZUhRNklUQXNkR2x0WlRv'
    || 'aE1DeDFjbXc2SVRBc2QyVmxhem9oTUgwN1puVnVZM1JwYjI0Z2MzVW9aU2w3ZG1GeUlIUTlaU1ltWlM1dWIyUmxUbUZ0WlNZbVpTNXViMlJsVG1GdFpTNTBi'
    || 'MHh2ZDJWeVEyRnpaU2dwTzNKbGRIVnliaUIwUFQwOUltbHVjSFYwSWo4aElYVm1XMlV1ZEhsd1pWMDZkRDA5UFNKMFpYaDBZWEpsWVNKOVpuVnVZM1JwYjI0'
    || 'Z2RYVW9aU3gwTEc0c2NpbDdWSE1vY2lrc2REMXNiQ2gwTENKdmJrTm9ZVzVuWlNJcExEQThkQzVzWlc1bmRHZ21KaWh1UFc1bGR5QkRhU2dpYjI1RGFHRnVa'
    || 'MlVpTENKamFHRnVaMlVpTEc1MWJHd3NiaXh5S1N4bExuQjFjMmdvZTJWMlpXNTBPbTRzYkdsemRHVnVaWEp6T25SOUtTbDlkbUZ5SUdGeVBXNTFiR3dzWTNJ'
    || 'OWJuVnNiRHRtZFc1amRHbHZiaUJoWmlobEtYdE9kU2hsTERBcGZXWjFibU4wYVc5dUlHVnNLR1VwZTNaaGNpQjBQVTl1S0dVcE8ybG1LSFp6S0hRcEtYSmxk'
    || 'SFZ5YmlCbGZXWjFibU4wYVc5dUlHTm1LR1VzZENsN2FXWW9aVDA5UFNKamFHRnVaMlVpS1hKbGRIVnliaUIwZlhaaGNpQmhkVDBoTVR0cFppaHFLWHQyWVhJ'
    || 'Z1RHazdhV1lvYWlsN2RtRnlJRWxwUFNKdmJtbHVjSFYwSW1sdUlHUnZZM1Z0Wlc1ME8ybG1LQ0ZKYVNsN2RtRnlJR04xUFdSdlkzVnRaVzUwTG1OeVpXRjBa'
    || 'VVZzWlcxbGJuUW9JbVJwZGlJcE8yTjFMbk5sZEVGMGRISnBZblYwWlNnaWIyNXBibkIxZENJc0luSmxkSFZ5YmpzaUtTeEphVDEwZVhCbGIyWWdZM1V1YjI1'
    || 'cGJuQjFkRDA5SW1aMWJtTjBhVzl1SW4xTWFUMUphWDFsYkhObElFeHBQU0V4TzJGMVBVeHBKaVlvSVdSdlkzVnRaVzUwTG1SdlkzVnRaVzUwVFc5a1pYeDhP'
    || 'VHhrYjJOMWJXVnVkQzVrYjJOMWJXVnVkRTF2WkdVcGZXWjFibU4wYVc5dUlHUjFLQ2w3WVhJbUppaGhjaTVrWlhSaFkyaEZkbVZ1ZENnaWIyNXdjbTl3WlhK'
    || 'MGVXTm9ZVzVuWlNJc1puVXBMR055UFdGeVBXNTFiR3dwZldaMWJtTjBhVzl1SUdaMUtHVXBlMmxtS0dVdWNISnZjR1Z5ZEhsT1lXMWxQVDA5SW5aaGJIVmxJ'
    || 'aVltWld3b1kzSXBLWHQyWVhJZ2REMWJYVHQxZFNoMExHTnlMR1VzY0drb1pTa3BMRkJ6S0dGbUxIUXBmWDFtZFc1amRHbHZiaUJrWmlobExIUXNiaWw3WlQw'
    || 'OVBTSm1iMk4xYzJsdUlqOG9aSFVvS1N4aGNqMTBMR055UFc0c1lYSXVZWFIwWVdOb1JYWmxiblFvSW05dWNISnZjR1Z5ZEhsamFHRnVaMlVpTEdaMUtTazZa'
    || 'VDA5UFNKbWIyTjFjMjkxZENJbUptUjFLQ2w5Wm5WdVkzUnBiMjRnWm1Zb1pTbDdhV1lvWlQwOVBTSnpaV3hsWTNScGIyNWphR0Z1WjJVaWZIeGxQVDA5SW10'
    || 'bGVYVndJbng4WlQwOVBTSnJaWGxrYjNkdUlpbHlaWFIxY200Z1pXd29ZM0lwZldaMWJtTjBhVzl1SUhCbUtHVXNkQ2w3YVdZb1pUMDlQU0pqYkdsamF5SXBj'
    || 'bVYwZFhKdUlHVnNLSFFwZldaMWJtTjBhVzl1SUdobUtHVXNkQ2w3YVdZb1pUMDlQU0pwYm5CMWRDSjhmR1U5UFQwaVkyaGhibWRsSWlseVpYUjFjbTRnWld3'
    || 'b2RDbDlablZ1WTNScGIyNGdiV1lvWlN4MEtYdHlaWFIxY200Z1pUMDlQWFFtSmlobElUMDlNSHg4TVM5bFBUMDlNUzkwS1h4OFpTRTlQV1VtSm5RaFBUMTBm'
    || 'WFpoY2lCb2REMTBlWEJsYjJZZ1QySnFaV04wTG1selBUMGlablZ1WTNScGIyNGlQMDlpYW1WamRDNXBjenB0Wmp0bWRXNWpkR2x2YmlCa2NpaGxMSFFwZTJs'
    || 'bUtHaDBLR1VzZENrcGNtVjBkWEp1SVRBN2FXWW9kSGx3Wlc5bUlHVWhQU0p2WW1wbFkzUWlmSHhsUFQwOWJuVnNiSHg4ZEhsd1pXOW1JSFFoUFNKdlltcGxZ'
    || 'M1FpZkh4MFBUMDliblZzYkNseVpYUjFjbTRoTVR0MllYSWdiajFQWW1wbFkzUXVhMlY1Y3lobEtTeHlQVTlpYW1WamRDNXJaWGx6S0hRcE8ybG1LRzR1YkdW'
    || 'dVozUm9JVDA5Y2k1c1pXNW5kR2dwY21WMGRYSnVJVEU3Wm05eUtISTlNRHR5UEc0dWJHVnVaM1JvTzNJckt5bDdkbUZ5SUd3OWJsdHlYVHRwWmlnaFV5NWpZ'
    || 'V3hzS0hRc2JDbDhmQ0ZvZENobFcyeGRMSFJiYkYwcEtYSmxkSFZ5YmlFeGZYSmxkSFZ5YmlFd2ZXWjFibU4wYVc5dUlIQjFLR1VwZTJadmNpZzdaU1ltWlM1'
    || 'bWFYSnpkRU5vYVd4a095bGxQV1V1Wm1seWMzUkRhR2xzWkR0eVpYUjFjbTRnWlgxbWRXNWpkR2x2YmlCb2RTaGxMSFFwZTNaaGNpQnVQWEIxS0dVcE8yVTlN'
    || 'RHRtYjNJb2RtRnlJSEk3YmpzcGUybG1LRzR1Ym05a1pWUjVjR1U5UFQwektYdHBaaWh5UFdVcmJpNTBaWGgwUTI5dWRHVnVkQzVzWlc1bmRHZ3NaVHc5ZENZ'
    || 'bWNqNDlkQ2x5WlhSMWNtNTdibTlrWlRwdUxHOW1abk5sZERwMExXVjlPMlU5Y24xbE9udG1iM0lvTzI0N0tYdHBaaWh1TG01bGVIUlRhV0pzYVc1bktYdHVQ'
    || 'VzR1Ym1WNGRGTnBZbXhwYm1jN1luSmxZV3NnWlgxdVBXNHVjR0Z5Wlc1MFRtOWtaWDF1UFhadmFXUWdNSDF1UFhCMUtHNHBmWDFtZFc1amRHbHZiaUJ0ZFNo'
    || 'bExIUXBlM0psZEhWeWJpQmxKaVowUDJVOVBUMTBQeUV3T21VbUptVXVibTlrWlZSNWNHVTlQVDB6UHlFeE9uUW1KblF1Ym05a1pWUjVjR1U5UFQwelAyMTFL'
    || 'R1VzZEM1d1lYSmxiblJPYjJSbEtUb2lZMjl1ZEdGcGJuTWlhVzRnWlQ5bExtTnZiblJoYVc1ektIUXBPbVV1WTI5dGNHRnlaVVJ2WTNWdFpXNTBVRzl6YVhS'
    || 'cGIyNC9JU0VvWlM1amIyMXdZWEpsUkc5amRXMWxiblJRYjNOcGRHbHZiaWgwS1NZeE5pazZJVEU2SVRGOVpuVnVZM1JwYjI0Z2RuVW9LWHRtYjNJb2RtRnlJ'
    || 'R1U5ZDJsdVpHOTNMSFE5ZW5Jb0tUdDBJR2x1YzNSaGJtTmxiMllnWlM1SVZFMU1TVVp5WVcxbFJXeGxiV1Z1ZERzcGUzUnllWHQyWVhJZ2JqMTBlWEJsYjJZ'
    || 'Z2RDNWpiMjUwWlc1MFYybHVaRzkzTG14dlkyRjBhVzl1TG1oeVpXWTlQU0p6ZEhKcGJtY2lmV05oZEdOb2UyNDlJVEY5YVdZb2JpbGxQWFF1WTI5dWRHVnVk'
    || 'RmRwYm1SdmR6dGxiSE5sSUdKeVpXRnJPM1E5ZW5Jb1pTNWtiMk4xYldWdWRDbDljbVYwZFhKdUlIUjlablZ1WTNScGIyNGdRV2tvWlNsN2RtRnlJSFE5WlNZ'
    || 'bVpTNXViMlJsVG1GdFpTWW1aUzV1YjJSbFRtRnRaUzUwYjB4dmQyVnlRMkZ6WlNncE8zSmxkSFZ5YmlCMEppWW9kRDA5UFNKcGJuQjFkQ0ltSmlobExuUjVj'
    || 'R1U5UFQwaWRHVjRkQ0o4ZkdVdWRIbHdaVDA5UFNKelpXRnlZMmdpZkh4bExuUjVjR1U5UFQwaWRHVnNJbng4WlM1MGVYQmxQVDA5SW5WeWJDSjhmR1V1ZEhs'
    || 'd1pUMDlQU0p3WVhOemQyOXlaQ0lwZkh4MFBUMDlJblJsZUhSaGNtVmhJbng4WlM1amIyNTBaVzUwUldScGRHRmliR1U5UFQwaWRISjFaU0lwZldaMWJtTjBh'
    || 'Vzl1SUhabUtHVXBlM1poY2lCMFBYWjFLQ2tzYmoxbExtWnZZM1Z6WldSRmJHVnRMSEk5WlM1elpXeGxZM1JwYjI1U1lXNW5aVHRwWmloMElUMDliaVltYmlZ'
    || 'bWJpNXZkMjVsY2tSdlkzVnRaVzUwSmladGRTaHVMbTkzYm1WeVJHOWpkVzFsYm5RdVpHOWpkVzFsYm5SRmJHVnRaVzUwTEc0cEtYdHBaaWh5SVQwOWJuVnNi'
    || 'Q1ltUVdrb2Jpa3BlMmxtS0hROWNpNXpkR0Z5ZEN4bFBYSXVaVzVrTEdVOVBUMTJiMmxrSURBbUppaGxQWFFwTENKelpXeGxZM1JwYjI1VGRHRnlkQ0pwYmlC'
    || 'dUtXNHVjMlZzWldOMGFXOXVVM1JoY25ROWRDeHVMbk5sYkdWamRHbHZia1Z1WkQxTllYUm9MbTFwYmlobExHNHVkbUZzZFdVdWJHVnVaM1JvS1R0bGJITmxJ'
    || 'R2xtS0dVOUtIUTliaTV2ZDI1bGNrUnZZM1Z0Wlc1MGZIeGtiMk4xYldWdWRDa21KblF1WkdWbVlYVnNkRlpwWlhkOGZIZHBibVJ2ZHl4bExtZGxkRk5sYkdW'
    || 'amRHbHZiaWw3WlQxbExtZGxkRk5sYkdWamRHbHZiaWdwTzNaaGNpQnNQVzR1ZEdWNGRFTnZiblJsYm5RdWJHVnVaM1JvTEdrOVRXRjBhQzV0YVc0b2NpNXpk'
    || 'R0Z5ZEN4c0tUdHlQWEl1Wlc1a1BUMDlkbTlwWkNBd1AyazZUV0YwYUM1dGFXNG9jaTVsYm1Rc2JDa3NJV1V1WlhoMFpXNWtKaVpwUG5JbUppaHNQWElzY2ox'
    || 'cExHazliQ2tzYkQxb2RTaHVMR2twTzNaaGNpQnpQV2gxS0c0c2NpazdiQ1ltY3lZbUtHVXVjbUZ1WjJWRGIzVnVkQ0U5UFRGOGZHVXVZVzVqYUc5eVRtOWta'
    || 'U0U5UFd3dWJtOWtaWHg4WlM1aGJtTm9iM0pQWm1aelpYUWhQVDFzTG05bVpuTmxkSHg4WlM1bWIyTjFjMDV2WkdVaFBUMXpMbTV2WkdWOGZHVXVabTlqZFhO'
    || 'UFptWnpaWFFoUFQxekxtOW1abk5sZENrbUppaDBQWFF1WTNKbFlYUmxVbUZ1WjJVb0tTeDBMbk5sZEZOMFlYSjBLR3d1Ym05a1pTeHNMbTltWm5ObGRDa3Na'
    || 'UzV5WlcxdmRtVkJiR3hTWVc1blpYTW9LU3hwUG5JL0tHVXVZV1JrVW1GdVoyVW9kQ2tzWlM1bGVIUmxibVFvY3k1dWIyUmxMSE11YjJabWMyVjBLU2s2S0hR'
    || 'dWMyVjBSVzVrS0hNdWJtOWtaU3h6TG05bVpuTmxkQ2tzWlM1aFpHUlNZVzVuWlNoMEtTa3BmWDFtYjNJb2REMWJYU3hsUFc0N1pUMWxMbkJoY21WdWRFNXZa'
    || 'R1U3S1dVdWJtOWtaVlI1Y0dVOVBUMHhKaVowTG5CMWMyZ29lMlZzWlcxbGJuUTZaU3hzWldaME9tVXVjMk55YjJ4c1RHVm1kQ3gwYjNBNlpTNXpZM0p2Ykd4'
    || 'VWIzQjlLVHRtYjNJb2RIbHdaVzltSUc0dVptOWpkWE05UFNKbWRXNWpkR2x2YmlJbUptNHVabTlqZFhNb0tTeHVQVEE3Ymp4MExteGxibWQwYUR0dUt5c3Ba'
    || 'VDEwVzI1ZExHVXVaV3hsYldWdWRDNXpZM0p2Ykd4TVpXWjBQV1V1YkdWbWRDeGxMbVZzWlcxbGJuUXVjMk55YjJ4c1ZHOXdQV1V1ZEc5d2ZYMTJZWElnWjJZ'
    || 'OWFpWW1JbVJ2WTNWdFpXNTBUVzlrWlNKcGJpQmtiMk4xYldWdWRDWW1NVEUrUFdSdlkzVnRaVzUwTG1SdlkzVnRaVzUwVFc5a1pTeERiajF1ZFd4c0xFMXBQ'
    || 'VzUxYkd3c1puSTliblZzYkN4NmFUMGhNVHRtZFc1amRHbHZiaUJuZFNobExIUXNiaWw3ZG1GeUlISTliaTUzYVc1a2IzYzlQVDF1UDI0dVpHOWpkVzFsYm5R'
    || 'NmJpNXViMlJsVkhsd1pUMDlQVGsvYmpwdUxtOTNibVZ5Ukc5amRXMWxiblE3ZW1sOGZFTnVQVDF1ZFd4c2ZIeERiaUU5UFhweUtISXBmSHdvY2oxRGJpd2lj'
    || 'MlZzWldOMGFXOXVVM1JoY25RaWFXNGdjaVltUVdrb2Npay9jajE3YzNSaGNuUTZjaTV6Wld4bFkzUnBiMjVUZEdGeWRDeGxibVE2Y2k1elpXeGxZM1JwYjI1'
    || 'RmJtUjlPaWh5UFNoeUxtOTNibVZ5Ukc5amRXMWxiblFtSm5JdWIzZHVaWEpFYjJOMWJXVnVkQzVrWldaaGRXeDBWbWxsZDN4OGQybHVaRzkzS1M1blpYUlRa'
    || 'V3hsWTNScGIyNG9LU3h5UFh0aGJtTm9iM0pPYjJSbE9uSXVZVzVqYUc5eVRtOWtaU3hoYm1Ob2IzSlBabVp6WlhRNmNpNWhibU5vYjNKUFptWnpaWFFzWm05'
    || 'amRYTk9iMlJsT25JdVptOWpkWE5PYjJSbExHWnZZM1Z6VDJabWMyVjBPbkl1Wm05amRYTlBabVp6WlhSOUtTeG1jaVltWkhJb1puSXNjaWw4ZkNobWNqMXlM'
    || 'SEk5Ykd3b1RXa3NJbTl1VTJWc1pXTjBJaWtzTUR4eUxteGxibWQwYUNZbUtIUTlibVYzSUVOcEtDSnZibE5sYkdWamRDSXNJbk5sYkdWamRDSXNiblZzYkN4'
    || 'MExHNHBMR1V1Y0hWemFDaDdaWFpsYm5RNmRDeHNhWE4wWlc1bGNuTTZjbjBwTEhRdWRHRnlaMlYwUFVOdUtTa3BmV1oxYm1OMGFXOXVJSFJzS0dVc2RDbDdk'
    || 'bUZ5SUc0OWUzMDdjbVYwZFhKdUlHNWJaUzUwYjB4dmQyVnlRMkZ6WlNncFhUMTBMblJ2VEc5M1pYSkRZWE5sS0Nrc2Jsc2lWMlZpYTJsMElpdGxYVDBpZDJW'
    || 'aWEybDBJaXQwTEc1YklrMXZlaUlyWlYwOUltMXZlaUlyZEN4dWZYWmhjaUJVYmoxN1lXNXBiV0YwYVc5dVpXNWtPblJzS0NKQmJtbHRZWFJwYjI0aUxDSkJi'
    || 'bWx0WVhScGIyNUZibVFpS1N4aGJtbHRZWFJwYjI1cGRHVnlZWFJwYjI0NmRHd29Ja0Z1YVcxaGRHbHZiaUlzSWtGdWFXMWhkR2x2YmtsMFpYSmhkR2x2YmlJ'
    || 'cExHRnVhVzFoZEdsdmJuTjBZWEowT25Sc0tDSkJibWx0WVhScGIyNGlMQ0pCYm1sdFlYUnBiMjVUZEdGeWRDSXBMSFJ5WVc1emFYUnBiMjVsYm1RNmRHd29J'
    || 'bFJ5WVc1emFYUnBiMjRpTENKVWNtRnVjMmwwYVc5dVJXNWtJaWw5TEZWcFBYdDlMSGwxUFh0OU8yb21KaWg1ZFQxa2IyTjFiV1Z1ZEM1amNtVmhkR1ZGYkdW'
    || 'dFpXNTBLQ0prYVhZaUtTNXpkSGxzWlN3aVFXNXBiV0YwYVc5dVJYWmxiblFpYVc0Z2QybHVaRzkzZkh3b1pHVnNaWFJsSUZSdUxtRnVhVzFoZEdsdmJtVnVa'
    || 'QzVoYm1sdFlYUnBiMjRzWkdWc1pYUmxJRlJ1TG1GdWFXMWhkR2x2Ym1sMFpYSmhkR2x2Ymk1aGJtbHRZWFJwYjI0c1pHVnNaWFJsSUZSdUxtRnVhVzFoZEds'
    || 'dmJuTjBZWEowTG1GdWFXMWhkR2x2Ymlrc0lsUnlZVzV6YVhScGIyNUZkbVZ1ZENKcGJpQjNhVzVrYjNkOGZHUmxiR1YwWlNCVWJpNTBjbUZ1YzJsMGFXOXVa'
    || 'VzVrTG5SeVlXNXphWFJwYjI0cE8yWjFibU4wYVc5dUlHNXNLR1VwZTJsbUtGVnBXMlZkS1hKbGRIVnliaUJWYVZ0bFhUdHBaaWdoVkc1YlpWMHBjbVYwZFhK'
    || 'dUlHVTdkbUZ5SUhROVZHNWJaVjBzYmp0bWIzSW9iaUJwYmlCMEtXbG1LSFF1YUdGelQzZHVVSEp2Y0dWeWRIa29iaWttSm00Z2FXNGdlWFVwY21WMGRYSnVJ'
    || 'RlZwVzJWZFBYUmJibDA3Y21WMGRYSnVJR1Y5ZG1GeUlIaDFQVzVzS0NKaGJtbHRZWFJwYjI1bGJtUWlLU3hGZFQxdWJDZ2lZVzVwYldGMGFXOXVhWFJsY21G'
    || 'MGFXOXVJaWtzWDNVOWJtd29JbUZ1YVcxaGRHbHZibk4wWVhKMElpa3NVM1U5Ym13b0luUnlZVzV6YVhScGIyNWxibVFpS1N4M2RUMXVaWGNnVFdGd0xHdDFQ'
    || 'U0poWW05eWRDQmhkWGhEYkdsamF5QmpZVzVqWld3Z1kyRnVVR3hoZVNCallXNVFiR0Y1VkdoeWIzVm5hQ0JqYkdsamF5QmpiRzl6WlNCamIyNTBaWGgwVFdW'
    || 'dWRTQmpiM0I1SUdOMWRDQmtjbUZuSUdSeVlXZEZibVFnWkhKaFowVnVkR1Z5SUdSeVlXZEZlR2wwSUdSeVlXZE1aV0YyWlNCa2NtRm5UM1psY2lCa2NtRm5V'
    || 'M1JoY25RZ1pISnZjQ0JrZFhKaGRHbHZia05vWVc1blpTQmxiWEIwYVdWa0lHVnVZM0o1Y0hSbFpDQmxibVJsWkNCbGNuSnZjaUJuYjNSUWIybHVkR1Z5UTJG'
    || 'd2RIVnlaU0JwYm5CMWRDQnBiblpoYkdsa0lHdGxlVVJ2ZDI0Z2EyVjVVSEpsYzNNZ2EyVjVWWEFnYkc5aFpDQnNiMkZrWldSRVlYUmhJR3h2WVdSbFpFMWxk'
    || 'R0ZrWVhSaElHeHZZV1JUZEdGeWRDQnNiM04wVUc5cGJuUmxja05oY0hSMWNtVWdiVzkxYzJWRWIzZHVJRzF2ZFhObFRXOTJaU0J0YjNWelpVOTFkQ0J0YjNW'
    || 'elpVOTJaWElnYlc5MWMyVlZjQ0J3WVhOMFpTQndZWFZ6WlNCd2JHRjVJSEJzWVhscGJtY2djRzlwYm5SbGNrTmhibU5sYkNCd2IybHVkR1Z5Ukc5M2JpQndi'
    || 'Mmx1ZEdWeVRXOTJaU0J3YjJsdWRHVnlUM1YwSUhCdmFXNTBaWEpQZG1WeUlIQnZhVzUwWlhKVmNDQndjbTluY21WemN5QnlZWFJsUTJoaGJtZGxJSEpsYzJW'
    || 'MElISmxjMmw2WlNCelpXVnJaV1FnYzJWbGEybHVaeUJ6ZEdGc2JHVmtJSE4xWW0xcGRDQnpkWE53Wlc1a0lIUnBiV1ZWY0dSaGRHVWdkRzkxWTJoRFlXNWpa'
    || 'V3dnZEc5MVkyaEZibVFnZEc5MVkyaFRkR0Z5ZENCMmIyeDFiV1ZEYUdGdVoyVWdjMk55YjJ4c0lIUnZaMmRzWlNCMGIzVmphRTF2ZG1VZ2QyRnBkR2x1WnlC'
    || 'M2FHVmxiQ0l1YzNCc2FYUW9JaUFpS1R0bWRXNWpkR2x2YmlCSWRDaGxMSFFwZTNkMUxuTmxkQ2hsTEhRcExGUW9kQ3hiWlYwcGZXWnZjaWgyWVhJZ1JtazlN'
    || 'RHRHYVR4cmRTNXNaVzVuZEdnN1Jta3JLeWw3ZG1GeUlGZHBQV3QxVzBacFhTeDVaajFYYVM1MGIweHZkMlZ5UTJGelpTZ3BMSGhtUFZkcFd6QmRMblJ2VlhC'
    || 'd1pYSkRZWE5sS0NrclYya3VjMnhwWTJVb01TazdTSFFvZVdZc0ltOXVJaXQ0WmlsOVNIUW9lSFVzSW05dVFXNXBiV0YwYVc5dVJXNWtJaWtzU0hRb1JYVXNJ'
    || 'bTl1UVc1cGJXRjBhVzl1U1hSbGNtRjBhVzl1SWlrc1NIUW9YM1VzSW05dVFXNXBiV0YwYVc5dVUzUmhjblFpS1N4SWRDZ2laR0pzWTJ4cFkyc2lMQ0p2YmtS'
    || 'dmRXSnNaVU5zYVdOcklpa3NTSFFvSW1adlkzVnphVzRpTENKdmJrWnZZM1Z6SWlrc1NIUW9JbVp2WTNWemIzVjBJaXdpYjI1Q2JIVnlJaWtzU0hRb1UzVXNJ'
    || 'bTl1VkhKaGJuTnBkR2x2YmtWdVpDSXBMSGdvSW05dVRXOTFjMlZGYm5SbGNpSXNXeUp0YjNWelpXOTFkQ0lzSW0xdmRYTmxiM1psY2lKZEtTeDRLQ0p2Ymsx'
    || 'dmRYTmxUR1ZoZG1VaUxGc2liVzkxYzJWdmRYUWlMQ0p0YjNWelpXOTJaWElpWFNrc2VDZ2liMjVRYjJsdWRHVnlSVzUwWlhJaUxGc2ljRzlwYm5SbGNtOTFk'
    || 'Q0lzSW5CdmFXNTBaWEp2ZG1WeUlsMHBMSGdvSW05dVVHOXBiblJsY2t4bFlYWmxJaXhiSW5CdmFXNTBaWEp2ZFhRaUxDSndiMmx1ZEdWeWIzWmxjaUpkS1N4'
    || 'VUtDSnZia05vWVc1blpTSXNJbU5vWVc1blpTQmpiR2xqYXlCbWIyTjFjMmx1SUdadlkzVnpiM1YwSUdsdWNIVjBJR3RsZVdSdmQyNGdhMlY1ZFhBZ2MyVnNa'
    || 'V04wYVc5dVkyaGhibWRsSWk1emNHeHBkQ2dpSUNJcEtTeFVLQ0p2YmxObGJHVmpkQ0lzSW1adlkzVnpiM1YwSUdOdmJuUmxlSFJ0Wlc1MUlHUnlZV2RsYm1R'
    || 'Z1ptOWpkWE5wYmlCclpYbGtiM2R1SUd0bGVYVndJRzF2ZFhObFpHOTNiaUJ0YjNWelpYVndJSE5sYkdWamRHbHZibU5vWVc1blpTSXVjM0JzYVhRb0lpQWlL'
    || 'U2tzVkNnaWIyNUNaV1p2Y21WSmJuQjFkQ0lzV3lKamIyMXdiM05wZEdsdmJtVnVaQ0lzSW10bGVYQnlaWE56SWl3aWRHVjRkRWx1Y0hWMElpd2ljR0Z6ZEdV'
    || 'aVhTa3NWQ2dpYjI1RGIyMXdiM05wZEdsdmJrVnVaQ0lzSW1OdmJYQnZjMmwwYVc5dVpXNWtJR1p2WTNWemIzVjBJR3RsZVdSdmQyNGdhMlY1Y0hKbGMzTWdh'
    || 'MlY1ZFhBZ2JXOTFjMlZrYjNkdUlpNXpjR3hwZENnaUlDSXBLU3hVS0NKdmJrTnZiWEJ2YzJsMGFXOXVVM1JoY25RaUxDSmpiMjF3YjNOcGRHbHZibk4wWVhK'
    || 'MElHWnZZM1Z6YjNWMElHdGxlV1J2ZDI0Z2EyVjVjSEpsYzNNZ2EyVjVkWEFnYlc5MWMyVmtiM2R1SWk1emNHeHBkQ2dpSUNJcEtTeFVLQ0p2YmtOdmJYQnZj'
    || 'MmwwYVc5dVZYQmtZWFJsSWl3aVkyOXRjRzl6YVhScGIyNTFjR1JoZEdVZ1ptOWpkWE52ZFhRZ2EyVjVaRzkzYmlCclpYbHdjbVZ6Y3lCclpYbDFjQ0J0YjNW'
    || 'elpXUnZkMjRpTG5Od2JHbDBLQ0lnSWlrcE8zWmhjaUJ3Y2owaVlXSnZjblFnWTJGdWNHeGhlU0JqWVc1d2JHRjVkR2h5YjNWbmFDQmtkWEpoZEdsdmJtTm9Z'
    || 'VzVuWlNCbGJYQjBhV1ZrSUdWdVkzSjVjSFJsWkNCbGJtUmxaQ0JsY25KdmNpQnNiMkZrWldSa1lYUmhJR3h2WVdSbFpHMWxkR0ZrWVhSaElHeHZZV1J6ZEdG'
    || 'eWRDQndZWFZ6WlNCd2JHRjVJSEJzWVhscGJtY2djSEp2WjNKbGMzTWdjbUYwWldOb1lXNW5aU0J5WlhOcGVtVWdjMlZsYTJWa0lITmxaV3RwYm1jZ2MzUmhi'
    || 'R3hsWkNCemRYTndaVzVrSUhScGJXVjFjR1JoZEdVZ2RtOXNkVzFsWTJoaGJtZGxJSGRoYVhScGJtY2lMbk53YkdsMEtDSWdJaWtzUldZOWJtVjNJRk5sZENn'
    || 'aVkyRnVZMlZzSUdOc2IzTmxJR2x1ZG1Gc2FXUWdiRzloWkNCelkzSnZiR3dnZEc5bloyeGxJaTV6Y0d4cGRDZ2lJQ0lwTG1OdmJtTmhkQ2h3Y2lrcE8yWjFi'
    || 'bU4wYVc5dUlHcDFLR1VzZEN4dUtYdDJZWElnY2oxbExuUjVjR1Y4ZkNKMWJtdHViM2R1TFdWMlpXNTBJanRsTG1OMWNuSmxiblJVWVhKblpYUTliaXhuWkNo'
    || 'eUxIUXNkbTlwWkNBd0xHVXBMR1V1WTNWeWNtVnVkRlJoY21kbGREMXVkV3hzZldaMWJtTjBhVzl1SUU1MUtHVXNkQ2w3ZEQwb2RDWTBLU0U5UFRBN1ptOXlL'
    || 'SFpoY2lCdVBUQTdianhsTG14bGJtZDBhRHR1S3lzcGUzWmhjaUJ5UFdWYmJsMHNiRDF5TG1WMlpXNTBPM0k5Y2k1c2FYTjBaVzVsY25NN1pUcDdkbUZ5SUdr'
    || 'OWRtOXBaQ0F3TzJsbUtIUXBabTl5S0haaGNpQnpQWEl1YkdWdVozUm9MVEU3TUR3OWN6dHpMUzBwZTNaaGNpQmtQWEpiYzEwc1pqMWtMbWx1YzNSaGJtTmxM'
    || 'SGs5WkM1amRYSnlaVzUwVkdGeVoyVjBPMmxtS0dROVpDNXNhWE4wWlc1bGNpeG1JVDA5YVNZbWJDNXBjMUJ5YjNCaFoyRjBhVzl1VTNSdmNIQmxaQ2dwS1dK'
    || 'eVpXRnJJR1U3YW5Vb2JDeGtMSGtwTEdrOVpuMWxiSE5sSUdadmNpaHpQVEE3Y3p4eUxteGxibWQwYUR0ekt5c3BlMmxtS0dROWNsdHpYU3htUFdRdWFXNXpk'
    || 'R0Z1WTJVc2VUMWtMbU4xY25KbGJuUlVZWEpuWlhRc1pEMWtMbXhwYzNSbGJtVnlMR1loUFQxcEppWnNMbWx6VUhKdmNHRm5ZWFJwYjI1VGRHOXdjR1ZrS0Nr'
    || 'cFluSmxZV3NnWlR0cWRTaHNMR1FzZVNrc2FUMW1mWDE5YVdZb1YzSXBkR2h5YjNjZ1pUMW5hU3hYY2owaE1TeG5hVDF1ZFd4c0xHVjlablZ1WTNScGIyNGdj'
    || 'R1VvWlN4MEtYdDJZWElnYmoxMFcwdHBYVHR1UFQwOWRtOXBaQ0F3SmlZb2JqMTBXMHRwWFQxdVpYY2dVMlYwS1R0MllYSWdjajFsS3lKZlgySjFZbUpzWlNJ'
    || 'N2JpNW9ZWE1vY2lsOGZDaERkU2gwTEdVc01pd2hNU2tzYmk1aFpHUW9jaWtwZldaMWJtTjBhVzl1SUZacEtHVXNkQ3h1S1h0MllYSWdjajB3TzNRbUppaHlm'
    || 'RDAwS1N4RGRTaHVMR1VzY2l4MEtYMTJZWElnY213OUlsOXlaV0ZqZEV4cGMzUmxibWx1WnlJclRXRjBhQzV5WVc1a2IyMG9LUzUwYjFOMGNtbHVaeWd6Tmlr'
    || 'dWMyeHBZMlVvTWlrN1puVnVZM1JwYjI0Z2FISW9aU2w3YVdZb0lXVmJjbXhkS1h0bFczSnNYVDBoTUN4dExtWnZja1ZoWTJnb1puVnVZM1JwYjI0b2JpbDdi'
    || 'aUU5UFNKelpXeGxZM1JwYjI1amFHRnVaMlVpSmlZb1JXWXVhR0Z6S0c0cGZIeFdhU2h1TENFeExHVXBMRlpwS0c0c0lUQXNaU2twZlNrN2RtRnlJSFE5WlM1'
    || 'dWIyUmxWSGx3WlQwOVBUay9aVHBsTG05M2JtVnlSRzlqZFcxbGJuUTdkRDA5UFc1MWJHeDhmSFJiY214ZGZId29kRnR5YkYwOUlUQXNWbWtvSW5ObGJHVmpk'
    || 'R2x2Ym1Ob1lXNW5aU0lzSVRFc2RDa3BmWDFtZFc1amRHbHZiaUJEZFNobExIUXNiaXh5S1h0emQybDBZMmdvV25Nb2RDa3BlMk5oYzJVZ01UcDJZWElnYkQx'
    || 'TVpEdGljbVZoYXp0allYTmxJRFE2YkQxSlpEdGljbVZoYXp0a1pXWmhkV3gwT213OWEybDliajFzTG1KcGJtUW9iblZzYkN4MExHNHNaU2tzYkQxMmIybGtJ'
    || 'REFzSVhacGZIeDBJVDA5SW5SdmRXTm9jM1JoY25RaUppWjBJVDA5SW5SdmRXTm9iVzkyWlNJbUpuUWhQVDBpZDJobFpXd2lmSHdvYkQwaE1Da3NjajlzSVQw'
    || 'OWRtOXBaQ0F3UDJVdVlXUmtSWFpsYm5STWFYTjBaVzVsY2loMExHNHNlMk5oY0hSMWNtVTZJVEFzY0dGemMybDJaVHBzZlNrNlpTNWhaR1JGZG1WdWRFeHBj'
    || 'M1JsYm1WeUtIUXNiaXdoTUNrNmJDRTlQWFp2YVdRZ01EOWxMbUZrWkVWMlpXNTBUR2x6ZEdWdVpYSW9kQ3h1TEh0d1lYTnphWFpsT214OUtUcGxMbUZrWkVW'
    || 'MlpXNTBUR2x6ZEdWdVpYSW9kQ3h1TENFeEtYMW1kVzVqZEdsdmJpQkNhU2hsTEhRc2JpeHlMR3dwZTNaaGNpQnBQWEk3YVdZb0tIUW1NU2s5UFQwd0ppWW9k'
    || 'Q1l5S1QwOVBUQW1KbkloUFQxdWRXeHNLV1U2Wm05eUtEczdLWHRwWmloeVBUMDliblZzYkNseVpYUjFjbTQ3ZG1GeUlITTljaTUwWVdjN2FXWW9jejA5UFRO'
    || 'OGZITTlQVDAwS1h0MllYSWdaRDF5TG5OMFlYUmxUbTlrWlM1amIyNTBZV2x1WlhKSmJtWnZPMmxtS0dROVBUMXNmSHhrTG01dlpHVlVlWEJsUFQwOU9DWW1a'
    || 'QzV3WVhKbGJuUk9iMlJsUFQwOWJDbGljbVZoYXp0cFppaHpQVDA5TkNsbWIzSW9jejF5TG5KbGRIVnlianR6SVQwOWJuVnNiRHNwZTNaaGNpQm1QWE11ZEdG'
    || 'bk8ybG1LQ2htUFQwOU0zeDhaajA5UFRRcEppWW9aajF6TG5OMFlYUmxUbTlrWlM1amIyNTBZV2x1WlhKSmJtWnZMR1k5UFQxc2ZIeG1MbTV2WkdWVWVYQmxQ'
    || 'VDA5T0NZbVppNXdZWEpsYm5ST2IyUmxQVDA5YkNrcGNtVjBkWEp1TzNNOWN5NXlaWFIxY201OVptOXlLRHRrSVQwOWJuVnNiRHNwZTJsbUtITTlkVzRvWkNr'
    || 'c2N6MDlQVzUxYkd3cGNtVjBkWEp1TzJsbUtHWTljeTUwWVdjc1pqMDlQVFY4ZkdZOVBUMDJLWHR5UFdrOWN6dGpiMjUwYVc1MVpTQmxmV1E5WkM1d1lYSmxi'
    || 'blJPYjJSbGZYMXlQWEl1Y21WMGRYSnVmVkJ6S0daMWJtTjBhVzl1S0NsN2RtRnlJSGs5YVN4clBYQnBLRzRwTEU0OVcxMDdaVHA3ZG1GeUlGODlkM1V1WjJW'
    || 'MEtHVXBPMmxtS0Y4aFBUMTJiMmxrSURBcGUzWmhjaUJQUFVOcExFazlaVHR6ZDJsMFkyZ29aU2w3WTJGelpTSnJaWGx3Y21WemN5STZhV1lvY1hJb2JpazlQ'
    || 'VDB3S1dKeVpXRnJJR1U3WTJGelpTSnJaWGxrYjNkdUlqcGpZWE5sSW10bGVYVndJanBQUFZoa08ySnlaV0ZyTzJOaGMyVWlabTlqZFhOcGJpSTZTVDBpWm05'
    || 'amRYTWlMRTg5UkdrN1luSmxZV3M3WTJGelpTSm1iMk4xYzI5MWRDSTZTVDBpWW14MWNpSXNUejFFYVR0aWNtVmhhenRqWVhObEltSmxabTl5WldKc2RYSWlP'
    || 'bU5oYzJVaVlXWjBaWEppYkhWeUlqcFBQVVJwTzJKeVpXRnJPMk5oYzJVaVkyeHBZMnNpT21sbUtHNHVZblYwZEc5dVBUMDlNaWxpY21WaGF5QmxPMk5oYzJV'
    || 'aVlYVjRZMnhwWTJzaU9tTmhjMlVpWkdKc1kyeHBZMnNpT21OaGMyVWliVzkxYzJWa2IzZHVJanBqWVhObEltMXZkWE5sYlc5MlpTSTZZMkZ6WlNKdGIzVnpa'
    || 'WFZ3SWpwallYTmxJbTF2ZFhObGIzVjBJanBqWVhObEltMXZkWE5sYjNabGNpSTZZMkZ6WlNKamIyNTBaWGgwYldWdWRTSTZUejFpY3p0aWNtVmhhenRqWVhO'
    || 'bEltUnlZV2NpT21OaGMyVWlaSEpoWjJWdVpDSTZZMkZ6WlNKa2NtRm5aVzUwWlhJaU9tTmhjMlVpWkhKaFoyVjRhWFFpT21OaGMyVWlaSEpoWjJ4bFlYWmxJ'
    || 'anBqWVhObEltUnlZV2R2ZG1WeUlqcGpZWE5sSW1SeVlXZHpkR0Z5ZENJNlkyRnpaU0prY205d0lqcFBQWHBrTzJKeVpXRnJPMk5oYzJVaWRHOTFZMmhqWVc1'
    || 'alpXd2lPbU5oYzJVaWRHOTFZMmhsYm1RaU9tTmhjMlVpZEc5MVkyaHRiM1psSWpwallYTmxJblJ2ZFdOb2MzUmhjblFpT2s4OVNtUTdZbkpsWVdzN1kyRnpa'
    || 'U0I0ZFRwallYTmxJRVYxT21OaGMyVWdYM1U2VHoxWFpEdGljbVZoYXp0allYTmxJRk4xT2s4OVpXWTdZbkpsWVdzN1kyRnpaU0p6WTNKdmJHd2lPazg5UVdR'
    || 'N1luSmxZV3M3WTJGelpTSjNhR1ZsYkNJNlR6MXVaanRpY21WaGF6dGpZWE5sSW1OdmNIa2lPbU5oYzJVaVkzVjBJanBqWVhObEluQmhjM1JsSWpwUFBVSmtP'
    || 'Mkp5WldGck8yTmhjMlVpWjI5MGNHOXBiblJsY21OaGNIUjFjbVVpT21OaGMyVWliRzl6ZEhCdmFXNTBaWEpqWVhCMGRYSmxJanBqWVhObEluQnZhVzUwWlhK'
    || 'allXNWpaV3dpT21OaGMyVWljRzlwYm5SbGNtUnZkMjRpT21OaGMyVWljRzlwYm5SbGNtMXZkbVVpT21OaGMyVWljRzlwYm5SbGNtOTFkQ0k2WTJGelpTSndi'
    || 'Mmx1ZEdWeWIzWmxjaUk2WTJGelpTSndiMmx1ZEdWeWRYQWlPazg5ZEhWOWRtRnlJRTA5S0hRbU5Da2hQVDB3TEd0bFBTRk5KaVpsUFQwOUluTmpjbTlzYkNJ'
    || 'c2RqMU5QMThoUFQxdWRXeHNQMThySWtOaGNIUjFjbVVpT201MWJHdzZYenROUFZ0ZE8yWnZjaWgyWVhJZ2NEMTVMR2M3Y0NFOVBXNTFiR3c3S1h0blBYQTdk'
    || 'bUZ5SUVNOVp5NXpkR0YwWlU1dlpHVTdhV1lvWnk1MFlXYzlQVDAxSmlaRElUMDliblZzYkNZbUtHYzlReXgySVQwOWJuVnNiQ1ltS0VNOVdtNG9jQ3gyS1N4'
    || 'RElUMXVkV3hzSmlaTkxuQjFjMmdvYlhJb2NDeERMR2NwS1NrcExHdGxLV0p5WldGck8zQTljQzV5WlhSMWNtNTlNRHhOTG14bGJtZDBhQ1ltS0Y4OWJtVjNJ'
    || 'RThvWHl4SkxHNTFiR3dzYml4cktTeE9MbkIxYzJnb2UyVjJaVzUwT2w4c2JHbHpkR1Z1WlhKek9rMTlLU2w5ZldsbUtDaDBKamNwUFQwOU1DbDdaVHA3YVdZ'
    || 'b1h6MWxQVDA5SW0xdmRYTmxiM1psY2lKOGZHVTlQVDBpY0c5cGJuUmxjbTkyWlhJaUxFODlaVDA5UFNKdGIzVnpaVzkxZENKOGZHVTlQVDBpY0c5cGJuUmxj'
    || 'bTkxZENJc1h5WW1iaUU5UFdacEppWW9TVDF1TG5KbGJHRjBaV1JVWVhKblpYUjhmRzR1Wm5KdmJVVnNaVzFsYm5RcEppWW9kVzRvU1NsOGZFbGJWSFJkS1Ns'
    || 'aWNtVmhheUJsTzJsbUtDaFBmSHhmS1NZbUtGODlheTUzYVc1a2IzYzlQVDFyUDJzNktGODlheTV2ZDI1bGNrUnZZM1Z0Wlc1MEtUOWZMbVJsWm1GMWJIUldh'
    || 'V1YzZkh4ZkxuQmhjbVZ1ZEZkcGJtUnZkenAzYVc1a2IzY3NUejhvU1QxdUxuSmxiR0YwWldSVVlYSm5aWFI4Zkc0dWRHOUZiR1Z0Wlc1MExFODllU3hKUFVr'
    || 'L2RXNG9TU2s2Ym5Wc2JDeEpJVDA5Ym5Wc2JDWW1LR3RsUFhOdUtFa3BMRWtoUFQxclpYeDhTUzUwWVdjaFBUMDFKaVpKTG5SaFp5RTlQVFlwSmlZb1NUMXVk'
    || 'V3hzS1NrNktFODliblZzYkN4SlBYa3BMRThoUFQxSktTbDdhV1lvVFQxaWN5eERQU0p2YmsxdmRYTmxUR1ZoZG1VaUxIWTlJbTl1VFc5MWMyVkZiblJsY2lJ'
    || 'c2NEMGliVzkxYzJVaUxDaGxQVDA5SW5CdmFXNTBaWEp2ZFhRaWZIeGxQVDA5SW5CdmFXNTBaWEp2ZG1WeUlpa21KaWhOUFhSMUxFTTlJbTl1VUc5cGJuUmxj'
    || 'a3hsWVhabElpeDJQU0p2YmxCdmFXNTBaWEpGYm5SbGNpSXNjRDBpY0c5cGJuUmxjaUlwTEd0bFBVODlQVzUxYkd3L1h6cFBiaWhQS1N4blBVazlQVzUxYkd3'
    || 'L1h6cFBiaWhKS1N4ZlBXNWxkeUJOS0VNc2NDc2liR1ZoZG1VaUxFOHNiaXhyS1N4ZkxuUmhjbWRsZEQxclpTeGZMbkpsYkdGMFpXUlVZWEpuWlhROVp5eERQ'
    || 'VzUxYkd3c2RXNG9heWs5UFQxNUppWW9UVDF1WlhjZ1RTaDJMSEFySW1WdWRHVnlJaXhKTEc0c2F5a3NUUzUwWVhKblpYUTlaeXhOTG5KbGJHRjBaV1JVWVhK'
    || 'blpYUTlhMlVzUXoxTktTeHJaVDFETEU4bUpra3BkRHA3Wm05eUtFMDlUeXgyUFVrc2NEMHdMR2M5VFR0bk8yYzlVbTRvWnlrcGNDc3JPMlp2Y2loblBUQXNR'
    || 'ejEyTzBNN1F6MVNiaWhES1Nsbkt5czdabTl5S0Rzd1BIQXRaenNwVFQxU2JpaE5LU3h3TFMwN1ptOXlLRHN3UEdjdGNEc3BkajFTYmloMktTeG5MUzA3Wm05'
    || 'eUtEdHdMUzA3S1h0cFppaE5QVDA5ZG54OGRpRTlQVzUxYkd3bUprMDlQVDEyTG1Gc2RHVnlibUYwWlNsaWNtVmhheUIwTzAwOVVtNG9UU2tzZGoxU2JpaDJL'
    || 'WDFOUFc1MWJHeDlaV3h6WlNCTlBXNTFiR3c3VHlFOVBXNTFiR3dtSmxSMUtFNHNYeXhQTEUwc0lURXBMRWtoUFQxdWRXeHNKaVpyWlNFOVBXNTFiR3dtSmxS'
    || 'MUtFNHNhMlVzU1N4TkxDRXdLWDE5WlRwN2FXWW9YejE1UDA5dUtIa3BPbmRwYm1SdmR5eFBQVjh1Ym05a1pVNWhiV1VtSmw4dWJtOWtaVTVoYldVdWRHOU1i'
    || 'M2RsY2tOaGMyVW9LU3hQUFQwOUluTmxiR1ZqZENKOGZFODlQVDBpYVc1d2RYUWlKaVpmTG5SNWNHVTlQVDBpWm1sc1pTSXBkbUZ5SUVZOVkyWTdaV3h6WlNC'
    || 'cFppaHpkU2hmS1NscFppaGhkU2xHUFdobU8yVnNjMlY3UmoxbVpqdDJZWElnVnoxa1puMWxiSE5sS0U4OVh5NXViMlJsVG1GdFpTa21Kazh1ZEc5TWIzZGxj'
    || 'a05oYzJVb0tUMDlQU0pwYm5CMWRDSW1KaWhmTG5SNWNHVTlQVDBpWTJobFkydGliM2dpZkh4ZkxuUjVjR1U5UFQwaWNtRmthVzhpS1NZbUtFWTljR1lwTzJs'
    || 'bUtFWW1KaWhHUFVZb1pTeDVLU2twZTNWMUtFNHNSaXh1TEdzcE8ySnlaV0ZySUdWOVZ5WW1WeWhsTEY4c2VTa3NaVDA5UFNKbWIyTjFjMjkxZENJbUppaFhQ'
    || 'Vjh1WDNkeVlYQndaWEpUZEdGMFpTa21KbGN1WTI5dWRISnZiR3hsWkNZbVh5NTBlWEJsUFQwOUltNTFiV0psY2lJbUpuTnBLRjhzSW01MWJXSmxjaUlzWHk1'
    || 'MllXeDFaU2w5YzNkcGRHTm9LRmM5ZVQ5UGJpaDVLVHAzYVc1a2IzY3NaU2w3WTJGelpTSm1iMk4xYzJsdUlqb29jM1VvVnlsOGZGY3VZMjl1ZEdWdWRFVmth'
    || 'WFJoWW14bFBUMDlJblJ5ZFdVaUtTWW1LRU51UFZjc1RXazllU3htY2oxdWRXeHNLVHRpY21WaGF6dGpZWE5sSW1adlkzVnpiM1YwSWpwbWNqMU5hVDFEYmox'
    || 'dWRXeHNPMkp5WldGck8yTmhjMlVpYlc5MWMyVmtiM2R1SWpwNmFUMGhNRHRpY21WaGF6dGpZWE5sSW1OdmJuUmxlSFJ0Wlc1MUlqcGpZWE5sSW0xdmRYTmxk'
    || 'WEFpT21OaGMyVWlaSEpoWjJWdVpDSTZlbWs5SVRFc1ozVW9UaXh1TEdzcE8ySnlaV0ZyTzJOaGMyVWljMlZzWldOMGFXOXVZMmhoYm1kbElqcHBaaWhuWmls'
    || 'aWNtVmhhenRqWVhObEltdGxlV1J2ZDI0aU9tTmhjMlVpYTJWNWRYQWlPbWQxS0U0c2JpeHJLWDEyWVhJZ1ZqdHBaaWhRYVNsbE9udHpkMmwwWTJnb1pTbDdZ'
    || 'MkZ6WlNKamIyMXdiM05wZEdsdmJuTjBZWEowSWpwMllYSWdXVDBpYjI1RGIyMXdiM05wZEdsdmJsTjBZWEowSWp0aWNtVmhheUJsTzJOaGMyVWlZMjl0Y0c5'
    || 'emFYUnBiMjVsYm1RaU9sazlJbTl1UTI5dGNHOXphWFJwYjI1RmJtUWlPMkp5WldGcklHVTdZMkZ6WlNKamIyMXdiM05wZEdsdmJuVndaR0YwWlNJNldUMGli'
    || 'MjVEYjIxd2IzTnBkR2x2YmxWd1pHRjBaU0k3WW5KbFlXc2daWDFaUFhadmFXUWdNSDFsYkhObElFNXVQMmwxS0dVc2Jpa21KaWhaUFNKdmJrTnZiWEJ2YzJs'
    || 'MGFXOXVSVzVrSWlrNlpUMDlQU0pyWlhsa2IzZHVJaVltYmk1clpYbERiMlJsUFQwOU1qSTVKaVlvV1QwaWIyNURiMjF3YjNOcGRHbHZibE4wWVhKMElpazdX'
    || 'U1ltS0c1MUppWnVMbXh2WTJGc1pTRTlQU0pyYnlJbUppaE9ibng4V1NFOVBTSnZia052YlhCdmMybDBhVzl1VTNSaGNuUWlQMWs5UFQwaWIyNURiMjF3YjNO'
    || 'cGRHbHZia1Z1WkNJbUprNXVKaVlvVmoxeGN5Z3BLVG9vUW5ROWF5eE9hVDBpZG1Gc2RXVWlhVzRnUW5RL1FuUXVkbUZzZFdVNlFuUXVkR1Y0ZEVOdmJuUmxi'
    || 'blFzVG00OUlUQXBLU3hYUFd4c0tIa3NXU2tzTUR4WExteGxibWQwYUNZbUtGazlibVYzSUdWMUtGa3NaU3h1ZFd4c0xHNHNheWtzVGk1d2RYTm9LSHRsZG1W'
    || 'dWREcFpMR3hwYzNSbGJtVnljenBYZlNrc1ZqOVpMbVJoZEdFOVZqb29WajF2ZFNodUtTeFdJVDA5Ym5Wc2JDWW1LRmt1WkdGMFlUMVdLU2twS1N3b1ZqMXNa'
    || 'ajl2WmlobExHNHBPbk5tS0dVc2Jpa3BKaVlvZVQxc2JDaDVMQ0p2YmtKbFptOXlaVWx1Y0hWMElpa3NNRHg1TG14bGJtZDBhQ1ltS0dzOWJtVjNJR1YxS0NK'
    || 'dmJrSmxabTl5WlVsdWNIVjBJaXdpWW1WbWIzSmxhVzV3ZFhRaUxHNTFiR3dzYml4cktTeE9MbkIxYzJnb2UyVjJaVzUwT21zc2JHbHpkR1Z1WlhKek9ubDlL'
    || 'U3hyTG1SaGRHRTlWaWtwZlU1MUtFNHNkQ2w5S1gxbWRXNWpkR2x2YmlCdGNpaGxMSFFzYmlsN2NtVjBkWEp1ZTJsdWMzUmhibU5sT21Vc2JHbHpkR1Z1WlhJ'
    || 'NmRDeGpkWEp5Wlc1MFZHRnlaMlYwT201OWZXWjFibU4wYVc5dUlHeHNLR1VzZENsN1ptOXlLSFpoY2lCdVBYUXJJa05oY0hSMWNtVWlMSEk5VzEwN1pTRTlQ'
    || 'VzUxYkd3N0tYdDJZWElnYkQxbExHazliQzV6ZEdGMFpVNXZaR1U3YkM1MFlXYzlQVDAxSmlacElUMDliblZzYkNZbUtHdzlhU3hwUFZwdUtHVXNiaWtzYVNF'
    || 'OWJuVnNiQ1ltY2k1MWJuTm9hV1owS0cxeUtHVXNhU3hzS1Nrc2FUMWFiaWhsTEhRcExHa2hQVzUxYkd3bUpuSXVjSFZ6YUNodGNpaGxMR2tzYkNrcEtTeGxQ'
    || 'V1V1Y21WMGRYSnVmWEpsZEhWeWJpQnlmV1oxYm1OMGFXOXVJRkp1S0dVcGUybG1LR1U5UFQxdWRXeHNLWEpsZEhWeWJpQnVkV3hzTzJSdklHVTlaUzV5WlhS'
    || 'MWNtNDdkMmhwYkdVb1pTWW1aUzUwWVdjaFBUMDFLVHR5WlhSMWNtNGdaWHg4Ym5Wc2JIMW1kVzVqZEdsdmJpQlVkU2hsTEhRc2JpeHlMR3dwZTJadmNpaDJZ'
    || 'WElnYVQxMExsOXlaV0ZqZEU1aGJXVXNjejFiWFR0dUlUMDliblZzYkNZbWJpRTlQWEk3S1h0MllYSWdaRDF1TEdZOVpDNWhiSFJsY201aGRHVXNlVDFrTG5O'
    || 'MFlYUmxUbTlrWlR0cFppaG1JVDA5Ym5Wc2JDWW1aajA5UFhJcFluSmxZV3M3WkM1MFlXYzlQVDAxSmlaNUlUMDliblZzYkNZbUtHUTllU3hzUHlobVBWcHVL'
    || 'RzRzYVNrc1ppRTliblZzYkNZbWN5NTFibk5vYVdaMEtHMXlLRzRzWml4a0tTa3BPbXg4ZkNobVBWcHVLRzRzYVNrc1ppRTliblZzYkNZbWN5NXdkWE5vS0cx'
    || 'eUtHNHNaaXhrS1NrcEtTeHVQVzR1Y21WMGRYSnVmWE11YkdWdVozUm9JVDA5TUNZbVpTNXdkWE5vS0h0bGRtVnVkRHAwTEd4cGMzUmxibVZ5Y3pwemZTbDlk'
    || 'bUZ5SUY5bVBTOWNjbHh1UHk5bkxGTm1QUzljZFRBd01EQjhYSFZHUmtaRUwyYzdablZ1WTNScGIyNGdVblVvWlNsN2NtVjBkWEp1S0hSNWNHVnZaaUJsUFQw'
    || 'aWMzUnlhVzVuSWo5bE9pSWlLMlVwTG5KbGNHeGhZMlVvWDJZc1lBcGdLUzV5WlhCc1lXTmxLRk5tTENJaUtYMW1kVzVqZEdsdmJpQnBiQ2hsTEhRc2JpbDdh'
    || 'V1lvZEQxU2RTaDBLU3hTZFNobEtTRTlQWFFtSm00cGRHaHliM2NnUlhKeWIzSW9ZU2cwTWpVcEtYMW1kVzVqZEdsdmJpQnZiQ2dwZTMxMllYSWdTR2s5Ym5W'
    || 'c2JDd2thVDF1ZFd4c08yWjFibU4wYVc5dUlGRnBLR1VzZENsN2NtVjBkWEp1SUdVOVBUMGlkR1Y0ZEdGeVpXRWlmSHhsUFQwOUltNXZjMk55YVhCMElueDhk'
    || 'SGx3Wlc5bUlIUXVZMmhwYkdSeVpXNDlQU0p6ZEhKcGJtY2lmSHgwZVhCbGIyWWdkQzVqYUdsc1pISmxiajA5SW01MWJXSmxjaUo4ZkhSNWNHVnZaaUIwTG1S'
    || 'aGJtZGxjbTkxYzJ4NVUyVjBTVzV1WlhKSVZFMU1QVDBpYjJKcVpXTjBJaVltZEM1a1lXNW5aWEp2ZFhOc2VWTmxkRWx1Ym1WeVNGUk5UQ0U5UFc1MWJHd21K'
    || 'blF1WkdGdVoyVnliM1Z6YkhsVFpYUkpibTVsY2toVVRVd3VYMTlvZEcxc0lUMXVkV3hzZlhaaGNpQlphVDEwZVhCbGIyWWdjMlYwVkdsdFpXOTFkRDA5SW1a'
    || 'MWJtTjBhVzl1SWo5elpYUlVhVzFsYjNWME9uWnZhV1FnTUN4M1pqMTBlWEJsYjJZZ1kyeGxZWEpVYVcxbGIzVjBQVDBpWm5WdVkzUnBiMjRpUDJOc1pXRnlW'
    || 'R2x0Wlc5MWREcDJiMmxrSURBc1JIVTlkSGx3Wlc5bUlGQnliMjFwYzJVOVBTSm1kVzVqZEdsdmJpSS9VSEp2YldselpUcDJiMmxrSURBc2EyWTlkSGx3Wlc5'
    || 'bUlIRjFaWFZsVFdsamNtOTBZWE5yUFQwaVpuVnVZM1JwYjI0aVAzRjFaWFZsVFdsamNtOTBZWE5yT25SNWNHVnZaaUJFZFR3aWRTSS9ablZ1WTNScGIyNG9a'
    || 'U2w3Y21WMGRYSnVJRVIxTG5KbGMyOXNkbVVvYm5Wc2JDa3VkR2hsYmlobEtTNWpZWFJqYUNocVppbDlPbGxwTzJaMWJtTjBhVzl1SUdwbUtHVXBlM05sZEZS'
    || 'cGJXVnZkWFFvWm5WdVkzUnBiMjRvS1h0MGFISnZkeUJsZlNsOVpuVnVZM1JwYjI0Z1Iya29aU3gwS1h0MllYSWdiajEwTEhJOU1EdGtiM3QyWVhJZ2JEMXVM'
    || 'bTVsZUhSVGFXSnNhVzVuTzJsbUtHVXVjbVZ0YjNabFEyaHBiR1FvYmlrc2JDWW1iQzV1YjJSbFZIbHdaVDA5UFRncGFXWW9iajFzTG1SaGRHRXNiajA5UFNJ'
    || 'dkpDSXBlMmxtS0hJOVBUMHdLWHRsTG5KbGJXOTJaVU5vYVd4a0tHd3BMR2x5S0hRcE8zSmxkSFZ5Ym4xeUxTMTlaV3h6WlNCdUlUMDlJaVFpSmladUlUMDlJ'
    || 'aVEvSWlZbWJpRTlQU0lrSVNKOGZISXJLenR1UFd4OWQyaHBiR1VvYmlrN2FYSW9kQ2w5Wm5WdVkzUnBiMjRnSkhRb1pTbDdabTl5S0R0bElUMXVkV3hzTzJV'
    || 'OVpTNXVaWGgwVTJsaWJHbHVaeWw3ZG1GeUlIUTlaUzV1YjJSbFZIbHdaVHRwWmloMFBUMDlNWHg4ZEQwOVBUTXBZbkpsWVdzN2FXWW9kRDA5UFRncGUybG1L'
    || 'SFE5WlM1a1lYUmhMSFE5UFQwaUpDSjhmSFE5UFQwaUpDRWlmSHgwUFQwOUlpUS9JaWxpY21WaGF6dHBaaWgwUFQwOUlpOGtJaWx5WlhSMWNtNGdiblZzYkgx'
    || 'OWNtVjBkWEp1SUdWOVpuVnVZM1JwYjI0Z1QzVW9aU2w3WlQxbExuQnlaWFpwYjNWelUybGliR2x1Wnp0bWIzSW9kbUZ5SUhROU1EdGxPeWw3YVdZb1pTNXVi'
    || 'MlJsVkhsd1pUMDlQVGdwZTNaaGNpQnVQV1V1WkdGMFlUdHBaaWh1UFQwOUlpUWlmSHh1UFQwOUlpUWhJbng4YmowOVBTSWtQeUlwZTJsbUtIUTlQVDB3S1hK'
    || 'bGRIVnliaUJsTzNRdExYMWxiSE5sSUc0OVBUMGlMeVFpSmlaMEt5dDlaVDFsTG5CeVpYWnBiM1Z6VTJsaWJHbHVaMzF5WlhSMWNtNGdiblZzYkgxMllYSWdS'
    || 'RzQ5VFdGMGFDNXlZVzVrYjIwb0tTNTBiMU4wY21sdVp5Z3pOaWt1YzJ4cFkyVW9NaWtzYTNROUlsOWZjbVZoWTNSR2FXSmxjaVFpSzBSdUxIWnlQU0pmWDNK'
    || 'bFlXTjBVSEp2Y0hNa0lpdEViaXhVZEQwaVgxOXlaV0ZqZEVOdmJuUmhhVzVsY2lRaUswUnVMRXRwUFNKZlgzSmxZV04wUlhabGJuUnpKQ0lyUkc0c1RtWTlJ'
    || 'bDlmY21WaFkzUk1hWE4wWlc1bGNuTWtJaXRFYml4RFpqMGlYMTl5WldGamRFaGhibVJzWlhNa0lpdEVianRtZFc1amRHbHZiaUIxYmlobEtYdDJZWElnZEQx'
    || 'bFcydDBYVHRwWmloMEtYSmxkSFZ5YmlCME8yWnZjaWgyWVhJZ2JqMWxMbkJoY21WdWRFNXZaR1U3YmpzcGUybG1LSFE5Ymx0VWRGMThmRzViYTNSZEtYdHBa'
    || 'aWh1UFhRdVlXeDBaWEp1WVhSbExIUXVZMmhwYkdRaFBUMXVkV3hzZkh4dUlUMDliblZzYkNZbWJpNWphR2xzWkNFOVBXNTFiR3dwWm05eUtHVTlUM1VvWlNr'
    || 'N1pTRTlQVzUxYkd3N0tYdHBaaWh1UFdWYmEzUmRLWEpsZEhWeWJpQnVPMlU5VDNVb1pTbDljbVYwZFhKdUlIUjlaVDF1TEc0OVpTNXdZWEpsYm5ST2IyUmxm'
    || 'WEpsZEhWeWJpQnVkV3hzZldaMWJtTjBhVzl1SUdkeUtHVXBlM0psZEhWeWJpQmxQV1ZiYTNSZGZIeGxXMVIwWFN3aFpYeDhaUzUwWVdjaFBUMDFKaVpsTG5S'
    || 'aFp5RTlQVFltSm1VdWRHRm5JVDA5TVRNbUptVXVkR0ZuSVQwOU16OXVkV3hzT21WOVpuVnVZM1JwYjI0Z1QyNG9aU2w3YVdZb1pTNTBZV2M5UFQwMWZIeGxM'
    || 'blJoWnowOVBUWXBjbVYwZFhKdUlHVXVjM1JoZEdWT2IyUmxPM1JvY205M0lFVnljbTl5S0dFb016TXBLWDFtZFc1amRHbHZiaUJ6YkNobEtYdHlaWFIxY200'
    || 'Z1pWdDJjbDE4Zkc1MWJHeDlkbUZ5SUZocFBWdGRMRkJ1UFMweE8yWjFibU4wYVc5dUlGRjBLR1VwZTNKbGRIVnlibnRqZFhKeVpXNTBPbVY5ZldaMWJtTjBh'
    || 'Vzl1SUdobEtHVXBlekErVUc1OGZDaGxMbU4xY25KbGJuUTlXR2xiVUc1ZExGaHBXMUJ1WFQxdWRXeHNMRkJ1TFMwcGZXWjFibU4wYVc5dUlHWmxLR1VzZENs'
    || 'N1VHNHJLeXhZYVZ0UWJsMDlaUzVqZFhKeVpXNTBMR1V1WTNWeWNtVnVkRDEwZlhaaGNpQlpkRDE3ZlN4VlpUMVJkQ2haZENrc1dXVTlVWFFvSVRFcExHRnVQ'
    || 'VmwwTzJaMWJtTjBhVzl1SUV4dUtHVXNkQ2w3ZG1GeUlHNDlaUzUwZVhCbExtTnZiblJsZUhSVWVYQmxjenRwWmlnaGJpbHlaWFIxY200Z1dYUTdkbUZ5SUhJ'
    || 'OVpTNXpkR0YwWlU1dlpHVTdhV1lvY2lZbWNpNWZYM0psWVdOMFNXNTBaWEp1WVd4TlpXMXZhWHBsWkZWdWJXRnphMlZrUTJocGJHUkRiMjUwWlhoMFBUMDlk'
    || 'Q2x5WlhSMWNtNGdjaTVmWDNKbFlXTjBTVzUwWlhKdVlXeE5aVzF2YVhwbFpFMWhjMnRsWkVOb2FXeGtRMjl1ZEdWNGREdDJZWElnYkQxN2ZTeHBPMlp2Y2lo'
    || 'cElHbHVJRzRwYkZ0cFhUMTBXMmxkTzNKbGRIVnliaUJ5SmlZb1pUMWxMbk4wWVhSbFRtOWtaU3hsTGw5ZmNtVmhZM1JKYm5SbGNtNWhiRTFsYlc5cGVtVmtW'
    || 'VzV0WVhOclpXUkRhR2xzWkVOdmJuUmxlSFE5ZEN4bExsOWZjbVZoWTNSSmJuUmxjbTVoYkUxbGJXOXBlbVZrVFdGemEyVmtRMmhwYkdSRGIyNTBaWGgwUFd3'
    || 'cExHeDlablZ1WTNScGIyNGdSMlVvWlNsN2NtVjBkWEp1SUdVOVpTNWphR2xzWkVOdmJuUmxlSFJVZVhCbGN5eGxJVDF1ZFd4c2ZXWjFibU4wYVc5dUlIVnNL'
    || 'Q2w3YUdVb1dXVXBMR2hsS0ZWbEtYMW1kVzVqZEdsdmJpQlFkU2hsTEhRc2JpbDdhV1lvVldVdVkzVnljbVZ1ZENFOVBWbDBLWFJvY205M0lFVnljbTl5S0dF'
    || 'b01UWTRLU2s3Wm1Vb1ZXVXNkQ2tzWm1Vb1dXVXNiaWw5Wm5WdVkzUnBiMjRnVEhVb1pTeDBMRzRwZTNaaGNpQnlQV1V1YzNSaGRHVk9iMlJsTzJsbUtIUTlk'
    || 'QzVqYUdsc1pFTnZiblJsZUhSVWVYQmxjeXgwZVhCbGIyWWdjaTVuWlhSRGFHbHNaRU52Ym5SbGVIUWhQU0ptZFc1amRHbHZiaUlwY21WMGRYSnVJRzQ3Y2ox'
    || 'eUxtZGxkRU5vYVd4a1EyOXVkR1Y0ZENncE8yWnZjaWgyWVhJZ2JDQnBiaUJ5S1dsbUtDRW9iQ0JwYmlCMEtTbDBhSEp2ZHlCRmNuSnZjaWhoS0RFd09DeGta'
    || 'U2hsS1h4OElsVnVhMjV2ZDI0aUxHd3BLVHR5WlhSMWNtNGdUQ2g3ZlN4dUxISXBmV1oxYm1OMGFXOXVJR0ZzS0dVcGUzSmxkSFZ5YmlCbFBTaGxQV1V1YzNS'
    || 'aGRHVk9iMlJsS1NZbVpTNWZYM0psWVdOMFNXNTBaWEp1WVd4TlpXMXZhWHBsWkUxbGNtZGxaRU5vYVd4a1EyOXVkR1Y0ZEh4OFdYUXNZVzQ5VldVdVkzVnlj'
    || 'bVZ1ZEN4bVpTaFZaU3hsS1N4bVpTaFpaU3haWlM1amRYSnlaVzUwS1N3aE1IMW1kVzVqZEdsdmJpQkpkU2hsTEhRc2JpbDdkbUZ5SUhJOVpTNXpkR0YwWlU1'
    || 'dlpHVTdhV1lvSVhJcGRHaHliM2NnUlhKeWIzSW9ZU2d4TmprcEtUdHVQeWhsUFV4MUtHVXNkQ3hoYmlrc2NpNWZYM0psWVdOMFNXNTBaWEp1WVd4TlpXMXZh'
    || 'WHBsWkUxbGNtZGxaRU5vYVd4a1EyOXVkR1Y0ZEQxbExHaGxLRmxsS1N4b1pTaFZaU2tzWm1Vb1ZXVXNaU2twT21obEtGbGxLU3htWlNoWlpTeHVLWDEyWVhJ'
    || 'Z1VuUTliblZzYkN4amJEMGhNU3hhYVQwaE1UdG1kVzVqZEdsdmJpQkJkU2hsS1h0U2REMDlQVzUxYkd3L1VuUTlXMlZkT2xKMExuQjFjMmdvWlNsOVpuVnVZ'
    || 'M1JwYjI0Z1ZHWW9aU2w3WTJ3OUlUQXNRWFVvWlNsOVpuVnVZM1JwYjI0Z1IzUW9LWHRwWmlnaFdta21KbEowSVQwOWJuVnNiQ2w3V21rOUlUQTdkbUZ5SUdV'
    || 'OU1DeDBQWFZsTzNSeWVYdDJZWElnYmoxU2REdG1iM0lvZFdVOU1UdGxQRzR1YkdWdVozUm9PMlVyS3lsN2RtRnlJSEk5Ymx0bFhUdGtieUJ5UFhJb0lUQXBP'
    || 'M2RvYVd4bEtISWhQVDF1ZFd4c0tYMVNkRDF1ZFd4c0xHTnNQU0V4ZldOaGRHTm9LR3dwZTNSb2NtOTNJRkowSVQwOWJuVnNiQ1ltS0ZKMFBWSjBMbk5zYVdO'
    || 'bEtHVXJNU2twTEhwektIbHBMRWQwS1N4c2ZXWnBibUZzYkhsN2RXVTlkQ3hhYVQwaE1YMTljbVYwZFhKdUlHNTFiR3g5ZG1GeUlFbHVQVnRkTEVGdVBUQXNa'
    || 'R3c5Ym5Wc2JDeG1iRDB3TEdsMFBWdGRMRzkwUFRBc1kyNDliblZzYkN4RWREMHhMRTkwUFNJaU8yWjFibU4wYVc5dUlHUnVLR1VzZENsN1NXNWJRVzRySzEw'
    || 'OVptd3NTVzViUVc0cksxMDlaR3dzWkd3OVpTeG1iRDEwZldaMWJtTjBhVzl1SUUxMUtHVXNkQ3h1S1h0cGRGdHZkQ3NyWFQxRWRDeHBkRnR2ZENzclhUMVBk'
    || 'Q3hwZEZ0dmRDc3JYVDFqYml4amJqMWxPM1poY2lCeVBVUjBPMlU5VDNRN2RtRnlJR3c5TXpJdGNIUW9jaWt0TVR0eUpqMStLREU4UEd3cExHNHJQVEU3ZG1G'
    || 'eUlHazlNekl0Y0hRb2RDa3JiRHRwWmlnek1EeHBLWHQyWVhJZ2N6MXNMV3dsTlR0cFBTaHlKaWd4UER4ektTMHhLUzUwYjFOMGNtbHVaeWd6TWlrc2NqNCtQ'
    || 'WE1zYkMwOWN5eEVkRDB4UER3ek1pMXdkQ2gwS1N0c2ZHNDhQR3g4Y2l4UGREMXBLMlY5Wld4elpTQkVkRDB4UER4cGZHNDhQR3g4Y2l4UGREMWxmV1oxYm1O'
    || 'MGFXOXVJSEZwS0dVcGUyVXVjbVYwZFhKdUlUMDliblZzYkNZbUtHUnVLR1VzTVNrc1RYVW9aU3d4TERBcEtYMW1kVzVqZEdsdmJpQkthU2hsS1h0bWIzSW9P'
    || 'MlU5UFQxa2JEc3BaR3c5U1c1YkxTMUJibDBzU1c1YlFXNWRQVzUxYkd3c1ptdzlTVzViTFMxQmJsMHNTVzViUVc1ZFBXNTFiR3c3Wm05eUtEdGxQVDA5WTI0'
    || 'N0tXTnVQV2wwV3kwdGIzUmRMR2wwVzI5MFhUMXVkV3hzTEU5MFBXbDBXeTB0YjNSZExHbDBXMjkwWFQxdWRXeHNMRVIwUFdsMFd5MHRiM1JkTEdsMFcyOTBY'
    || 'VDF1ZFd4c2ZYWmhjaUIwZEQxdWRXeHNMRzUwUFc1MWJHd3NkbVU5SVRFc2JYUTliblZzYkR0bWRXNWpkR2x2YmlCNmRTaGxMSFFwZTNaaGNpQnVQV04wS0RV'
    || 'c2JuVnNiQ3h1ZFd4c0xEQXBPMjR1Wld4bGJXVnVkRlI1Y0dVOUlrUkZURVZVUlVRaUxHNHVjM1JoZEdWT2IyUmxQWFFzYmk1eVpYUjFjbTQ5WlN4MFBXVXVa'
    || 'R1ZzWlhScGIyNXpMSFE5UFQxdWRXeHNQeWhsTG1SbGJHVjBhVzl1Y3oxYmJsMHNaUzVtYkdGbmMzdzlNVFlwT25RdWNIVnphQ2h1S1gxbWRXNWpkR2x2YmlC'
    || 'VmRTaGxMSFFwZTNOM2FYUmphQ2hsTG5SaFp5bDdZMkZ6WlNBMU9uWmhjaUJ1UFdVdWRIbHdaVHR5WlhSMWNtNGdkRDEwTG01dlpHVlVlWEJsSVQwOU1YeDhi'
    || 'aTUwYjB4dmQyVnlRMkZ6WlNncElUMDlkQzV1YjJSbFRtRnRaUzUwYjB4dmQyVnlRMkZ6WlNncFAyNTFiR3c2ZEN4MElUMDliblZzYkQ4b1pTNXpkR0YwWlU1'
    || 'dlpHVTlkQ3gwZEQxbExHNTBQU1IwS0hRdVptbHljM1JEYUdsc1pDa3NJVEFwT2lFeE8yTmhjMlVnTmpweVpYUjFjbTRnZEQxbExuQmxibVJwYm1kUWNtOXdj'
    || 'ejA5UFNJaWZIeDBMbTV2WkdWVWVYQmxJVDA5TXo5dWRXeHNPblFzZENFOVBXNTFiR3cvS0dVdWMzUmhkR1ZPYjJSbFBYUXNkSFE5WlN4dWREMXVkV3hzTENF'
    || 'd0tUb2hNVHRqWVhObElERXpPbkpsZEhWeWJpQjBQWFF1Ym05a1pWUjVjR1VoUFQwNFAyNTFiR3c2ZEN4MElUMDliblZzYkQ4b2JqMWpiaUU5UFc1MWJHdy9l'
    || 'MmxrT2tSMExHOTJaWEptYkc5M09rOTBmVHB1ZFd4c0xHVXViV1Z0YjJsNlpXUlRkR0YwWlQxN1pHVm9lV1J5WVhSbFpEcDBMSFJ5WldWRGIyNTBaWGgwT200'
    || 'c2NtVjBjbmxNWVc1bE9qRXdOek0zTkRFNE1qUjlMRzQ5WTNRb01UZ3NiblZzYkN4dWRXeHNMREFwTEc0dWMzUmhkR1ZPYjJSbFBYUXNiaTV5WlhSMWNtNDla'
    || 'U3hsTG1Ob2FXeGtQVzRzZEhROVpTeHVkRDF1ZFd4c0xDRXdLVG9oTVR0a1pXWmhkV3gwT25KbGRIVnliaUV4ZlgxbWRXNWpkR2x2YmlCaWFTaGxLWHR5WlhS'
    || 'MWNtNG9aUzV0YjJSbEpqRXBJVDA5TUNZbUtHVXVabXhoWjNNbU1USTRLVDA5UFRCOVpuVnVZM1JwYjI0Z1pXOG9aU2w3YVdZb2RtVXBlM1poY2lCMFBXNTBP'
    || 'MmxtS0hRcGUzWmhjaUJ1UFhRN2FXWW9JVlYxS0dVc2RDa3BlMmxtS0dKcEtHVXBLWFJvY205M0lFVnljbTl5S0dFb05ERTRLU2s3ZEQwa2RDaHVMbTVsZUhS'
    || 'VGFXSnNhVzVuS1R0MllYSWdjajEwZER0MEppWlZkU2hsTEhRcFAzcDFLSElzYmlrNktHVXVabXhoWjNNOVpTNW1iR0ZuY3lZdE5EQTVOM3d5TEhabFBTRXhM'
    || 'SFIwUFdVcGZYMWxiSE5sZTJsbUtHSnBLR1VwS1hSb2NtOTNJRVZ5Y205eUtHRW9OREU0S1NrN1pTNW1iR0ZuY3oxbExtWnNZV2R6SmkwME1EazNmRElzZG1V'
    || 'OUlURXNkSFE5WlgxOWZXWjFibU4wYVc5dUlFWjFLR1VwZTJadmNpaGxQV1V1Y21WMGRYSnVPMlVoUFQxdWRXeHNKaVpsTG5SaFp5RTlQVFVtSm1VdWRHRm5J'
    || 'VDA5TXlZbVpTNTBZV2NoUFQweE16c3BaVDFsTG5KbGRIVnlianQwZEQxbGZXWjFibU4wYVc5dUlIQnNLR1VwZTJsbUtHVWhQVDEwZENseVpYUjFjbTRoTVR0'
    || 'cFppZ2hkbVVwY21WMGRYSnVJRVoxS0dVcExIWmxQU0V3TENFeE8zWmhjaUIwTzJsbUtDaDBQV1V1ZEdGbklUMDlNeWttSmlFb2REMWxMblJoWnlFOVBUVXBK'
    || 'aVlvZEQxbExuUjVjR1VzZEQxMElUMDlJbWhsWVdRaUppWjBJVDA5SW1KdlpIa2lKaVloVVdrb1pTNTBlWEJsTEdVdWJXVnRiMmw2WldSUWNtOXdjeWtwTEhR'
    || 'bUppaDBQVzUwS1NsN2FXWW9ZbWtvWlNrcGRHaHliM2NnVjNVb0tTeEZjbkp2Y2loaEtEUXhPQ2twTzJadmNpZzdkRHNwZW5Vb1pTeDBLU3gwUFNSMEtIUXVi'
    || 'bVY0ZEZOcFlteHBibWNwZldsbUtFWjFLR1VwTEdVdWRHRm5QVDA5TVRNcGUybG1LR1U5WlM1dFpXMXZhWHBsWkZOMFlYUmxMR1U5WlNFOVBXNTFiR3cvWlM1'
    || 'a1pXaDVaSEpoZEdWa09tNTFiR3dzSVdVcGRHaHliM2NnUlhKeWIzSW9ZU2d6TVRjcEtUdGxPbnRtYjNJb1pUMWxMbTVsZUhSVGFXSnNhVzVuTEhROU1EdGxP'
    || 'eWw3YVdZb1pTNXViMlJsVkhsd1pUMDlQVGdwZTNaaGNpQnVQV1V1WkdGMFlUdHBaaWh1UFQwOUlpOGtJaWw3YVdZb2REMDlQVEFwZTI1MFBTUjBLR1V1Ym1W'
    || 'NGRGTnBZbXhwYm1jcE8ySnlaV0ZySUdWOWRDMHRmV1ZzYzJVZ2JpRTlQU0lrSWlZbWJpRTlQU0lrSVNJbUptNGhQVDBpSkQ4aWZIeDBLeXQ5WlQxbExtNWxl'
    || 'SFJUYVdKc2FXNW5mVzUwUFc1MWJHeDlmV1ZzYzJVZ2JuUTlkSFEvSkhRb1pTNXpkR0YwWlU1dlpHVXVibVY0ZEZOcFlteHBibWNwT201MWJHdzdjbVYwZFhK'
    || 'dUlUQjlablZ1WTNScGIyNGdWM1VvS1h0bWIzSW9kbUZ5SUdVOWJuUTdaVHNwWlQwa2RDaGxMbTVsZUhSVGFXSnNhVzVuS1gxbWRXNWpkR2x2YmlCTmJpZ3Bl'
    || 'MjUwUFhSMFBXNTFiR3dzZG1VOUlURjlablZ1WTNScGIyNGdkRzhvWlNsN2JYUTlQVDF1ZFd4c1AyMTBQVnRsWFRwdGRDNXdkWE5vS0dVcGZYWmhjaUJTWmox'
    || 'TExsSmxZV04wUTNWeWNtVnVkRUpoZEdOb1EyOXVabWxuTzJaMWJtTjBhVzl1SUhseUtHVXNkQ3h1S1h0cFppaGxQVzR1Y21WbUxHVWhQVDF1ZFd4c0ppWjBl'
    || 'WEJsYjJZZ1pTRTlJbVoxYm1OMGFXOXVJaVltZEhsd1pXOW1JR1VoUFNKdlltcGxZM1FpS1h0cFppaHVMbDl2ZDI1bGNpbDdhV1lvYmoxdUxsOXZkMjVsY2l4'
    || 'dUtYdHBaaWh1TG5SaFp5RTlQVEVwZEdoeWIzY2dSWEp5YjNJb1lTZ3pNRGtwS1R0MllYSWdjajF1TG5OMFlYUmxUbTlrWlgxcFppZ2hjaWwwYUhKdmR5QkZj'
    || 'bkp2Y2loaEtERTBOeXhsS1NrN2RtRnlJR3c5Y2l4cFBTSWlLMlU3Y21WMGRYSnVJSFFoUFQxdWRXeHNKaVowTG5KbFppRTlQVzUxYkd3bUpuUjVjR1Z2WmlC'
    || 'MExuSmxaajA5SW1aMWJtTjBhVzl1SWlZbWRDNXlaV1l1WDNOMGNtbHVaMUpsWmowOVBXay9kQzV5WldZNktIUTlablZ1WTNScGIyNG9jeWw3ZG1GeUlHUTli'
    || 'QzV5Wldaek8zTTlQVDF1ZFd4c1AyUmxiR1YwWlNCa1cybGRPbVJiYVYwOWMzMHNkQzVmYzNSeWFXNW5VbVZtUFdrc2RDbDlhV1lvZEhsd1pXOW1JR1VoUFNK'
    || 'emRISnBibWNpS1hSb2NtOTNJRVZ5Y205eUtHRW9NamcwS1NrN2FXWW9JVzR1WDI5M2JtVnlLWFJvY205M0lFVnljbTl5S0dFb01qa3dMR1VwS1gxeVpYUjFj'
    || 'bTRnWlgxbWRXNWpkR2x2YmlCb2JDaGxMSFFwZTNSb2NtOTNJR1U5VDJKcVpXTjBMbkJ5YjNSdmRIbHdaUzUwYjFOMGNtbHVaeTVqWVd4c0tIUXBMRVZ5Y205'
    || 'eUtHRW9NekVzWlQwOVBTSmJiMkpxWldOMElFOWlhbVZqZEYwaVB5SnZZbXBsWTNRZ2QybDBhQ0JyWlhseklIc2lLMDlpYW1WamRDNXJaWGx6S0hRcExtcHZh'
    || 'VzRvSWl3Z0lpa3JJbjBpT21VcEtYMW1kVzVqZEdsdmJpQldkU2hsS1h0MllYSWdkRDFsTGw5cGJtbDBPM0psZEhWeWJpQjBLR1V1WDNCaGVXeHZZV1FwZlda'
    || 'MWJtTjBhVzl1SUVKMUtHVXBlMloxYm1OMGFXOXVJSFFvZGl4d0tYdHBaaWhsS1h0MllYSWdaejEyTG1SbGJHVjBhVzl1Y3p0blBUMDliblZzYkQ4b2RpNWta'
    || 'V3hsZEdsdmJuTTlXM0JkTEhZdVpteGhaM044UFRFMktUcG5MbkIxYzJnb2NDbDlmV1oxYm1OMGFXOXVJRzRvZGl4d0tYdHBaaWdoWlNseVpYUjFjbTRnYm5W'
    || 'c2JEdG1iM0lvTzNBaFBUMXVkV3hzT3lsMEtIWXNjQ2tzY0Qxd0xuTnBZbXhwYm1jN2NtVjBkWEp1SUc1MWJHeDlablZ1WTNScGIyNGdjaWgyTEhBcGUyWnZj'
    || 'aWgyUFc1bGR5Qk5ZWEE3Y0NFOVBXNTFiR3c3S1hBdWEyVjVJVDA5Ym5Wc2JEOTJMbk5sZENod0xtdGxlU3h3S1RwMkxuTmxkQ2h3TG1sdVpHVjRMSEFwTEhB'
    || 'OWNDNXphV0pzYVc1bk8zSmxkSFZ5YmlCMmZXWjFibU4wYVc5dUlHd29kaXh3S1h0eVpYUjFjbTRnZGoxMGJpaDJMSEFwTEhZdWFXNWtaWGc5TUN4MkxuTnBZ'
    || 'bXhwYm1jOWJuVnNiQ3gyZldaMWJtTjBhVzl1SUdrb2RpeHdMR2NwZTNKbGRIVnliaUIyTG1sdVpHVjRQV2NzWlQ4b1p6MTJMbUZzZEdWeWJtRjBaU3huSVQw'
    || 'OWJuVnNiRDhvWnoxbkxtbHVaR1Y0TEdjOGNEOG9kaTVtYkdGbmMzdzlNaXh3S1RwbktUb29kaTVtYkdGbmMzdzlNaXh3S1NrNktIWXVabXhoWjNOOFBURXdO'
    || 'RGcxTnpZc2NDbDlablZ1WTNScGIyNGdjeWgyS1h0eVpYUjFjbTRnWlNZbWRpNWhiSFJsY201aGRHVTlQVDF1ZFd4c0ppWW9kaTVtYkdGbmMzdzlNaWtzZG4x'
    || 'bWRXNWpkR2x2YmlCa0tIWXNjQ3huTEVNcGUzSmxkSFZ5YmlCd1BUMDliblZzYkh4OGNDNTBZV2NoUFQwMlB5aHdQVWR2S0djc2RpNXRiMlJsTEVNcExIQXVj'
    || 'bVYwZFhKdVBYWXNjQ2s2S0hBOWJDaHdMR2NwTEhBdWNtVjBkWEp1UFhZc2NDbDlablZ1WTNScGIyNGdaaWgyTEhBc1p5eERLWHQyWVhJZ1JqMW5MblI1Y0dV'
    || 'N2NtVjBkWEp1SUVZOVBUMWpaVDlyS0hZc2NDeG5MbkJ5YjNCekxtTm9hV3hrY21WdUxFTXNaeTVyWlhrcE9uQWhQVDF1ZFd4c0ppWW9jQzVsYkdWdFpXNTBW'
    || 'SGx3WlQwOVBVWjhmSFI1Y0dWdlppQkdQVDBpYjJKcVpXTjBJaVltUmlFOVBXNTFiR3dtSmtZdUpDUjBlWEJsYjJZOVBUMVJaU1ltVm5Vb1JpazlQVDF3TG5S'
    || 'NWNHVXBQeWhEUFd3b2NDeG5MbkJ5YjNCektTeERMbkpsWmoxNWNpaDJMSEFzWnlrc1F5NXlaWFIxY200OWRpeERLVG9vUXoxVmJDaG5MblI1Y0dVc1p5NXJa'
    || 'WGtzWnk1d2NtOXdjeXh1ZFd4c0xIWXViVzlrWlN4REtTeERMbkpsWmoxNWNpaDJMSEFzWnlrc1F5NXlaWFIxY200OWRpeERLWDFtZFc1amRHbHZiaUI1S0hZ'
    || 'c2NDeG5MRU1wZTNKbGRIVnliaUJ3UFQwOWJuVnNiSHg4Y0M1MFlXY2hQVDAwZkh4d0xuTjBZWFJsVG05a1pTNWpiMjUwWVdsdVpYSkpibVp2SVQwOVp5NWpi'
    || 'MjUwWVdsdVpYSkpibVp2Zkh4d0xuTjBZWFJsVG05a1pTNXBiWEJzWlcxbGJuUmhkR2x2YmlFOVBXY3VhVzF3YkdWdFpXNTBZWFJwYjI0L0tIQTlTMjhvWnl4'
    || 'MkxtMXZaR1VzUXlrc2NDNXlaWFIxY200OWRpeHdLVG9vY0Qxc0tIQXNaeTVqYUdsc1pISmxibng4VzEwcExIQXVjbVYwZFhKdVBYWXNjQ2w5Wm5WdVkzUnBi'
    || 'MjRnYXloMkxIQXNaeXhETEVZcGUzSmxkSFZ5YmlCd1BUMDliblZzYkh4OGNDNTBZV2NoUFQwM1B5aHdQWGh1S0djc2RpNXRiMlJsTEVNc1Jpa3NjQzV5WlhS'
    || 'MWNtNDlkaXh3S1Rvb2NEMXNLSEFzWnlrc2NDNXlaWFIxY200OWRpeHdLWDFtZFc1amRHbHZiaUJPS0hZc2NDeG5LWHRwWmloMGVYQmxiMllnY0QwOUluTjBj'
    || 'bWx1WnlJbUpuQWhQVDBpSW54OGRIbHdaVzltSUhBOVBTSnVkVzFpWlhJaUtYSmxkSFZ5YmlCd1BVZHZLQ0lpSzNBc2RpNXRiMlJsTEdjcExIQXVjbVYwZFhK'
    || 'dVBYWXNjRHRwWmloMGVYQmxiMllnY0QwOUltOWlhbVZqZENJbUpuQWhQVDF1ZFd4c0tYdHpkMmwwWTJnb2NDNGtKSFI1Y0dWdlppbDdZMkZ6WlNCcVpUcHla'
    || 'WFIxY200Z1p6MVZiQ2h3TG5SNWNHVXNjQzVyWlhrc2NDNXdjbTl3Y3l4dWRXeHNMSFl1Ylc5a1pTeG5LU3huTG5KbFpqMTVjaWgyTEc1MWJHd3NjQ2tzWnk1'
    || 'eVpYUjFjbTQ5ZGl4bk8yTmhjMlVnWVdVNmNtVjBkWEp1SUhBOVMyOG9jQ3gyTG0xdlpHVXNaeWtzY0M1eVpYUjFjbTQ5ZGl4d08yTmhjMlVnVVdVNmRtRnlJ'
    || 'RU05Y0M1ZmFXNXBkRHR5WlhSMWNtNGdUaWgyTEVNb2NDNWZjR0Y1Ykc5aFpDa3NaeWw5YVdZb1IyNG9jQ2w4ZkNRb2NDa3BjbVYwZFhKdUlIQTllRzRvY0N4'
    || 'MkxtMXZaR1VzWnl4dWRXeHNLU3h3TG5KbGRIVnliajEyTEhBN2FHd29kaXh3S1gxeVpYUjFjbTRnYm5Wc2JIMW1kVzVqZEdsdmJpQmZLSFlzY0N4bkxFTXBl'
    || 'M1poY2lCR1BYQWhQVDF1ZFd4c1AzQXVhMlY1T201MWJHdzdhV1lvZEhsd1pXOW1JR2M5UFNKemRISnBibWNpSmlabklUMDlJaUo4ZkhSNWNHVnZaaUJuUFQw'
    || 'aWJuVnRZbVZ5SWlseVpYUjFjbTRnUmlFOVBXNTFiR3cvYm5Wc2JEcGtLSFlzY0N3aUlpdG5MRU1wTzJsbUtIUjVjR1Z2WmlCblBUMGliMkpxWldOMElpWW1a'
    || 'eUU5UFc1MWJHd3BlM04zYVhSamFDaG5MaVFrZEhsd1pXOW1LWHRqWVhObElHcGxPbkpsZEhWeWJpQm5MbXRsZVQwOVBVWS9aaWgyTEhBc1p5eERLVHB1ZFd4'
    || 'c08yTmhjMlVnWVdVNmNtVjBkWEp1SUdjdWEyVjVQVDA5Umo5NUtIWXNjQ3huTEVNcE9tNTFiR3c3WTJGelpTQlJaVHB5WlhSMWNtNGdSajFuTGw5cGJtbDBM'
    || 'RjhvZGl4d0xFWW9aeTVmY0dGNWJHOWhaQ2tzUXlsOWFXWW9SMjRvWnlsOGZDUW9aeWtwY21WMGRYSnVJRVloUFQxdWRXeHNQMjUxYkd3NmF5aDJMSEFzWnl4'
    || 'RExHNTFiR3dwTzJoc0tIWXNaeWw5Y21WMGRYSnVJRzUxYkd4OVpuVnVZM1JwYjI0Z1R5aDJMSEFzWnl4RExFWXBlMmxtS0hSNWNHVnZaaUJEUFQwaWMzUnlh'
    || 'VzVuSWlZbVF5RTlQU0lpZkh4MGVYQmxiMllnUXowOUltNTFiV0psY2lJcGNtVjBkWEp1SUhZOWRpNW5aWFFvWnlsOGZHNTFiR3dzWkNod0xIWXNJaUlyUXl4'
    || 'R0tUdHBaaWgwZVhCbGIyWWdRejA5SW05aWFtVmpkQ0ltSmtNaFBUMXVkV3hzS1h0emQybDBZMmdvUXk0a0pIUjVjR1Z2WmlsN1kyRnpaU0JxWlRweVpYUjFj'
    || 'bTRnZGoxMkxtZGxkQ2hETG10bGVUMDlQVzUxYkd3L1p6cERMbXRsZVNsOGZHNTFiR3dzWmlod0xIWXNReXhHS1R0allYTmxJR0ZsT25KbGRIVnliaUIyUFhZ'
    || 'dVoyVjBLRU11YTJWNVBUMDliblZzYkQ5bk9rTXVhMlY1S1h4OGJuVnNiQ3g1S0hBc2RpeERMRVlwTzJOaGMyVWdVV1U2ZG1GeUlGYzlReTVmYVc1cGREdHla'
    || 'WFIxY200Z1R5aDJMSEFzWnl4WEtFTXVYM0JoZVd4dllXUXBMRVlwZldsbUtFZHVLRU1wZkh3a0tFTXBLWEpsZEhWeWJpQjJQWFl1WjJWMEtHY3BmSHh1ZFd4'
    || 'c0xHc29jQ3gyTEVNc1JpeHVkV3hzS1R0b2JDaHdMRU1wZlhKbGRIVnliaUJ1ZFd4c2ZXWjFibU4wYVc5dUlFa29kaXh3TEdjc1F5bDdabTl5S0haaGNpQkdQ'
    || 'VzUxYkd3c1Z6MXVkV3hzTEZZOWNDeFpQWEE5TUN4UVpUMXVkV3hzTzFZaFBUMXVkV3hzSmlaWlBHY3ViR1Z1WjNSb08xa3JLeWw3Vmk1cGJtUmxlRDVaUHlo'
    || 'UVpUMVdMRlk5Ym5Wc2JDazZVR1U5Vmk1emFXSnNhVzVuTzNaaGNpQnBaVDFmS0hZc1ZpeG5XMWxkTEVNcE8ybG1LR2xsUFQwOWJuVnNiQ2w3VmowOVBXNTFi'
    || 'R3dtSmloV1BWQmxLVHRpY21WaGEzMWxKaVpXSmlacFpTNWhiSFJsY201aGRHVTlQVDF1ZFd4c0ppWjBLSFlzVmlrc2NEMXBLR2xsTEhBc1dTa3NWejA5UFc1'
    || 'MWJHdy9SajFwWlRwWExuTnBZbXhwYm1jOWFXVXNWejFwWlN4V1BWQmxmV2xtS0ZrOVBUMW5MbXhsYm1kMGFDbHlaWFIxY200Z2JpaDJMRllwTEhabEppWmti'
    || 'aWgyTEZrcExFWTdhV1lvVmowOVBXNTFiR3dwZTJadmNpZzdXVHhuTG14bGJtZDBhRHRaS3lzcFZqMU9LSFlzWjF0WlhTeERLU3hXSVQwOWJuVnNiQ1ltS0hB'
    || 'OWFTaFdMSEFzV1Nrc1Z6MDlQVzUxYkd3L1JqMVdPbGN1YzJsaWJHbHVaejFXTEZjOVZpazdjbVYwZFhKdUlIWmxKaVprYmloMkxGa3BMRVo5Wm05eUtGWTlj'
    || 'aWgyTEZZcE8xazhaeTVzWlc1bmRHZzdXU3NyS1ZCbFBVOG9WaXgyTEZrc1oxdFpYU3hES1N4UVpTRTlQVzUxYkd3bUppaGxKaVpRWlM1aGJIUmxjbTVoZEdV'
    || 'aFBUMXVkV3hzSmlaV0xtUmxiR1YwWlNoUVpTNXJaWGs5UFQxdWRXeHNQMWs2VUdVdWEyVjVLU3h3UFdrb1VHVXNjQ3haS1N4WFBUMDliblZzYkQ5R1BWQmxP'
    || 'bGN1YzJsaWJHbHVaejFRWlN4WFBWQmxLVHR5WlhSMWNtNGdaU1ltVmk1bWIzSkZZV05vS0daMWJtTjBhVzl1S0c1dUtYdHlaWFIxY200Z2RDaDJMRzV1S1gw'
    || 'cExIWmxKaVprYmloMkxGa3BMRVo5Wm5WdVkzUnBiMjRnVFNoMkxIQXNaeXhES1h0MllYSWdSajBrS0djcE8ybG1LSFI1Y0dWdlppQkdJVDBpWm5WdVkzUnBi'
    || 'MjRpS1hSb2NtOTNJRVZ5Y205eUtHRW9NVFV3S1NrN2FXWW9aejFHTG1OaGJHd29aeWtzWnowOWJuVnNiQ2wwYUhKdmR5QkZjbkp2Y2loaEtERTFNU2twTzJa'
    || 'dmNpaDJZWElnVnoxR1BXNTFiR3dzVmoxd0xGazljRDB3TEZCbFBXNTFiR3dzYVdVOVp5NXVaWGgwS0NrN1ZpRTlQVzUxYkd3bUppRnBaUzVrYjI1bE8xa3JL'
    || 'eXhwWlQxbkxtNWxlSFFvS1NsN1ZpNXBibVJsZUQ1WlB5aFFaVDFXTEZZOWJuVnNiQ2s2VUdVOVZpNXphV0pzYVc1bk8zWmhjaUJ1YmoxZktIWXNWaXhwWlM1'
    || 'MllXeDFaU3hES1R0cFppaHViajA5UFc1MWJHd3BlMVk5UFQxdWRXeHNKaVlvVmoxUVpTazdZbkpsWVd0OVpTWW1WaVltYm00dVlXeDBaWEp1WVhSbFBUMDli'
    || 'blZzYkNZbWRDaDJMRllwTEhBOWFTaHViaXh3TEZrcExGYzlQVDF1ZFd4c1AwWTlibTQ2Vnk1emFXSnNhVzVuUFc1dUxGYzlibTRzVmoxUVpYMXBaaWhwWlM1'
    || 'a2IyNWxLWEpsZEhWeWJpQnVLSFlzVmlrc2RtVW1KbVJ1S0hZc1dTa3NSanRwWmloV1BUMDliblZzYkNsN1ptOXlLRHNoYVdVdVpHOXVaVHRaS3lzc2FXVTla'
    || 'eTV1WlhoMEtDa3BhV1U5VGloMkxHbGxMblpoYkhWbExFTXBMR2xsSVQwOWJuVnNiQ1ltS0hBOWFTaHBaU3h3TEZrcExGYzlQVDF1ZFd4c1AwWTlhV1U2Vnk1'
    || 'emFXSnNhVzVuUFdsbExGYzlhV1VwTzNKbGRIVnliaUIyWlNZbVpHNG9kaXhaS1N4R2ZXWnZjaWhXUFhJb2RpeFdLVHNoYVdVdVpHOXVaVHRaS3lzc2FXVTla'
    || 'eTV1WlhoMEtDa3BhV1U5VHloV0xIWXNXU3hwWlM1MllXeDFaU3hES1N4cFpTRTlQVzUxYkd3bUppaGxKaVpwWlM1aGJIUmxjbTVoZEdVaFBUMXVkV3hzSmla'
    || 'V0xtUmxiR1YwWlNocFpTNXJaWGs5UFQxdWRXeHNQMWs2YVdVdWEyVjVLU3h3UFdrb2FXVXNjQ3haS1N4WFBUMDliblZzYkQ5R1BXbGxPbGN1YzJsaWJHbHVa'
    || 'ejFwWlN4WFBXbGxLVHR5WlhSMWNtNGdaU1ltVmk1bWIzSkZZV05vS0daMWJtTjBhVzl1S0hWd0tYdHlaWFIxY200Z2RDaDJMSFZ3S1gwcExIWmxKaVprYmlo'
    || 'MkxGa3BMRVo5Wm5WdVkzUnBiMjRnYTJVb2RpeHdMR2NzUXlsN2FXWW9kSGx3Wlc5bUlHYzlQU0p2WW1wbFkzUWlKaVpuSVQwOWJuVnNiQ1ltWnk1MGVYQmxQ'
    || 'VDA5WTJVbUptY3VhMlY1UFQwOWJuVnNiQ1ltS0djOVp5NXdjbTl3Y3k1amFHbHNaSEpsYmlrc2RIbHdaVzltSUdjOVBTSnZZbXBsWTNRaUppWm5JVDA5Ym5W'
    || 'c2JDbDdjM2RwZEdOb0tHY3VKQ1IwZVhCbGIyWXBlMk5oYzJVZ2FtVTZaVHA3Wm05eUtIWmhjaUJHUFdjdWEyVjVMRmM5Y0R0WElUMDliblZzYkRzcGUybG1L'
    || 'RmN1YTJWNVBUMDlSaWw3YVdZb1JqMW5MblI1Y0dVc1JqMDlQV05sS1h0cFppaFhMblJoWnowOVBUY3BlMjRvZGl4WExuTnBZbXhwYm1jcExIQTliQ2hYTEdj'
    || 'dWNISnZjSE11WTJocGJHUnlaVzRwTEhBdWNtVjBkWEp1UFhZc2RqMXdPMkp5WldGcklHVjlmV1ZzYzJVZ2FXWW9WeTVsYkdWdFpXNTBWSGx3WlQwOVBVWjhm'
    || 'SFI1Y0dWdlppQkdQVDBpYjJKcVpXTjBJaVltUmlFOVBXNTFiR3dtSmtZdUpDUjBlWEJsYjJZOVBUMVJaU1ltVm5Vb1JpazlQVDFYTG5SNWNHVXBlMjRvZGl4'
    || 'WExuTnBZbXhwYm1jcExIQTliQ2hYTEdjdWNISnZjSE1wTEhBdWNtVm1QWGx5S0hZc1Z5eG5LU3h3TG5KbGRIVnliajEyTEhZOWNEdGljbVZoYXlCbGZXNG9k'
    || 'aXhYS1R0aWNtVmhhMzFsYkhObElIUW9kaXhYS1R0WFBWY3VjMmxpYkdsdVozMW5MblI1Y0dVOVBUMWpaVDhvY0QxNGJpaG5MbkJ5YjNCekxtTm9hV3hrY21W'
    || 'dUxIWXViVzlrWlN4RExHY3VhMlY1S1N4d0xuSmxkSFZ5YmoxMkxIWTljQ2s2S0VNOVZXd29aeTUwZVhCbExHY3VhMlY1TEdjdWNISnZjSE1zYm5Wc2JDeDJM'
    || 'bTF2WkdVc1F5a3NReTV5WldZOWVYSW9kaXh3TEdjcExFTXVjbVYwZFhKdVBYWXNkajFES1gxeVpYUjFjbTRnY3loMktUdGpZWE5sSUdGbE9tVTZlMlp2Y2lo'
    || 'WFBXY3VhMlY1TzNBaFBUMXVkV3hzT3lsN2FXWW9jQzVyWlhrOVBUMVhLV2xtS0hBdWRHRm5QVDA5TkNZbWNDNXpkR0YwWlU1dlpHVXVZMjl1ZEdGcGJtVnlT'
    || 'VzVtYnowOVBXY3VZMjl1ZEdGcGJtVnlTVzVtYnlZbWNDNXpkR0YwWlU1dlpHVXVhVzF3YkdWdFpXNTBZWFJwYjI0OVBUMW5MbWx0Y0d4bGJXVnVkR0YwYVc5'
    || 'dUtYdHVLSFlzY0M1emFXSnNhVzVuS1N4d1BXd29jQ3huTG1Ob2FXeGtjbVZ1Zkh4YlhTa3NjQzV5WlhSMWNtNDlkaXgyUFhBN1luSmxZV3NnWlgxbGJITmxl'
    || 'MjRvZGl4d0tUdGljbVZoYTMxbGJITmxJSFFvZGl4d0tUdHdQWEF1YzJsaWJHbHVaMzF3UFV0dktHY3NkaTV0YjJSbExFTXBMSEF1Y21WMGRYSnVQWFlzZGox'
    || 'd2ZYSmxkSFZ5YmlCektIWXBPMk5oYzJVZ1VXVTZjbVYwZFhKdUlGYzlaeTVmYVc1cGRDeHJaU2gyTEhBc1Z5aG5MbDl3WVhsc2IyRmtLU3hES1gxcFppaEhi'
    || 'aWhuS1NseVpYUjFjbTRnU1NoMkxIQXNaeXhES1R0cFppZ2tLR2NwS1hKbGRIVnliaUJOS0hZc2NDeG5MRU1wTzJoc0tIWXNaeWw5Y21WMGRYSnVJSFI1Y0dW'
    || 'dlppQm5QVDBpYzNSeWFXNW5JaVltWnlFOVBTSWlmSHgwZVhCbGIyWWdaejA5SW01MWJXSmxjaUkvS0djOUlpSXJaeXh3SVQwOWJuVnNiQ1ltY0M1MFlXYzlQ'
    || 'VDAyUHlodUtIWXNjQzV6YVdKc2FXNW5LU3h3UFd3b2NDeG5LU3h3TG5KbGRIVnliajEyTEhZOWNDazZLRzRvZGl4d0tTeHdQVWR2S0djc2RpNXRiMlJsTEVN'
    || 'cExIQXVjbVYwZFhKdVBYWXNkajF3S1N4ektIWXBLVHB1S0hZc2NDbDljbVYwZFhKdUlHdGxmWFpoY2lCNmJqMUNkU2doTUNrc1NIVTlRblVvSVRFcExHMXNQ'
    || 'VkYwS0c1MWJHd3BMSFpzUFc1MWJHd3NWVzQ5Ym5Wc2JDeHViejF1ZFd4c08yWjFibU4wYVc5dUlISnZLQ2w3Ym04OVZXNDlkbXc5Ym5Wc2JIMW1kVzVqZEds'
    || 'dmJpQnNieWhsS1h0MllYSWdkRDF0YkM1amRYSnlaVzUwTzJobEtHMXNLU3hsTGw5amRYSnlaVzUwVm1Gc2RXVTlkSDFtZFc1amRHbHZiaUJwYnlobExIUXNi'
    || 'aWw3Wm05eUtEdGxJVDA5Ym5Wc2JEc3BlM1poY2lCeVBXVXVZV3gwWlhKdVlYUmxPMmxtS0NobExtTm9hV3hrVEdGdVpYTW1kQ2toUFQxMFB5aGxMbU5vYVd4'
    || 'a1RHRnVaWE44UFhRc2NpRTlQVzUxYkd3bUppaHlMbU5vYVd4a1RHRnVaWE44UFhRcEtUcHlJVDA5Ym5Wc2JDWW1LSEl1WTJocGJHUk1ZVzVsY3laMEtTRTlQ'
    || 'WFFtSmloeUxtTm9hV3hrVEdGdVpYTjhQWFFwTEdVOVBUMXVLV0p5WldGck8yVTlaUzV5WlhSMWNtNTlmV1oxYm1OMGFXOXVJRVp1S0dVc2RDbDdkbXc5WlN4'
    || 'dWJ6MVZiajF1ZFd4c0xHVTlaUzVrWlhCbGJtUmxibU5wWlhNc1pTRTlQVzUxYkd3bUptVXVabWx5YzNSRGIyNTBaWGgwSVQwOWJuVnNiQ1ltS0NobExteGhi'
    || 'bVZ6Sm5RcElUMDlNQ1ltS0V0bFBTRXdLU3hsTG1acGNuTjBRMjl1ZEdWNGREMXVkV3hzS1gxbWRXNWpkR2x2YmlCemRDaGxLWHQyWVhJZ2REMWxMbDlqZFhK'
    || 'eVpXNTBWbUZzZFdVN2FXWW9ibThoUFQxbEtXbG1LR1U5ZTJOdmJuUmxlSFE2WlN4dFpXMXZhWHBsWkZaaGJIVmxPblFzYm1WNGREcHVkV3hzZlN4VmJqMDlQ'
    || 'VzUxYkd3cGUybG1LSFpzUFQwOWJuVnNiQ2wwYUhKdmR5QkZjbkp2Y2loaEtETXdPQ2twTzFWdVBXVXNkbXd1WkdWd1pXNWtaVzVqYVdWelBYdHNZVzVsY3pv'
    || 'd0xHWnBjbk4wUTI5dWRHVjRkRHBsZlgxbGJITmxJRlZ1UFZWdUxtNWxlSFE5WlR0eVpYUjFjbTRnZEgxMllYSWdabTQ5Ym5Wc2JEdG1kVzVqZEdsdmJpQnZi'
    || 'eWhsS1h0bWJqMDlQVzUxYkd3L1ptNDlXMlZkT21adUxuQjFjMmdvWlNsOVpuVnVZM1JwYjI0Z0pIVW9aU3gwTEc0c2NpbDdkbUZ5SUd3OWRDNXBiblJsY214'
    || 'bFlYWmxaRHR5WlhSMWNtNGdiRDA5UFc1MWJHdy9LRzR1Ym1WNGREMXVMRzl2S0hRcEtUb29iaTV1WlhoMFBXd3VibVY0ZEN4c0xtNWxlSFE5Ymlrc2RDNXBi'
    || 'blJsY214bFlYWmxaRDF1TEZCMEtHVXNjaWw5Wm5WdVkzUnBiMjRnVUhRb1pTeDBLWHRsTG14aGJtVnpmRDEwTzNaaGNpQnVQV1V1WVd4MFpYSnVZWFJsTzJa'
    || 'dmNpaHVJVDA5Ym5Wc2JDWW1LRzR1YkdGdVpYTjhQWFFwTEc0OVpTeGxQV1V1Y21WMGRYSnVPMlVoUFQxdWRXeHNPeWxsTG1Ob2FXeGtUR0Z1WlhOOFBYUXNi'
    || 'ajFsTG1Gc2RHVnlibUYwWlN4dUlUMDliblZzYkNZbUtHNHVZMmhwYkdSTVlXNWxjM3c5ZENrc2JqMWxMR1U5WlM1eVpYUjFjbTQ3Y21WMGRYSnVJRzR1ZEdG'
    || 'blBUMDlNejl1TG5OMFlYUmxUbTlrWlRwdWRXeHNmWFpoY2lCTGREMGhNVHRtZFc1amRHbHZiaUJ6YnlobEtYdGxMblZ3WkdGMFpWRjFaWFZsUFh0aVlYTmxV'
    || 'M1JoZEdVNlpTNXRaVzF2YVhwbFpGTjBZWFJsTEdacGNuTjBRbUZ6WlZWd1pHRjBaVHB1ZFd4c0xHeGhjM1JDWVhObFZYQmtZWFJsT201MWJHd3NjMmhoY21W'
    || 'a09udHdaVzVrYVc1bk9tNTFiR3dzYVc1MFpYSnNaV0YyWldRNmJuVnNiQ3hzWVc1bGN6b3dmU3hsWm1abFkzUnpPbTUxYkd4OWZXWjFibU4wYVc5dUlGRjFL'
    || 'R1VzZENsN1pUMWxMblZ3WkdGMFpWRjFaWFZsTEhRdWRYQmtZWFJsVVhWbGRXVTlQVDFsSmlZb2RDNTFjR1JoZEdWUmRXVjFaVDE3WW1GelpWTjBZWFJsT21V'
    || 'dVltRnpaVk4wWVhSbExHWnBjbk4wUW1GelpWVndaR0YwWlRwbExtWnBjbk4wUW1GelpWVndaR0YwWlN4c1lYTjBRbUZ6WlZWd1pHRjBaVHBsTG14aGMzUkNZ'
    || 'WE5sVlhCa1lYUmxMSE5vWVhKbFpEcGxMbk5vWVhKbFpDeGxabVpsWTNSek9tVXVaV1ptWldOMGMzMHBmV1oxYm1OMGFXOXVJRXgwS0dVc2RDbDdjbVYwZFhK'
    || 'dWUyVjJaVzUwVkdsdFpUcGxMR3hoYm1VNmRDeDBZV2M2TUN4d1lYbHNiMkZrT201MWJHd3NZMkZzYkdKaFkyczZiblZzYkN4dVpYaDBPbTUxYkd4OWZXWjFi'
    || 'bU4wYVc5dUlGaDBLR1VzZEN4dUtYdDJZWElnY2oxbExuVndaR0YwWlZGMVpYVmxPMmxtS0hJOVBUMXVkV3hzS1hKbGRIVnliaUJ1ZFd4c08ybG1LSEk5Y2k1'
    || 'emFHRnlaV1FzS0c1bEpqSXBJVDA5TUNsN2RtRnlJR3c5Y2k1d1pXNWthVzVuTzNKbGRIVnliaUJzUFQwOWJuVnNiRDkwTG01bGVIUTlkRG9vZEM1dVpYaDBQ'
    || 'V3d1Ym1WNGRDeHNMbTVsZUhROWRDa3NjaTV3Wlc1a2FXNW5QWFFzVUhRb1pTeHVLWDF5WlhSMWNtNGdiRDF5TG1sdWRHVnliR1ZoZG1Wa0xHdzlQVDF1ZFd4'
    || 'c1B5aDBMbTVsZUhROWRDeHZieWh5S1NrNktIUXVibVY0ZEQxc0xtNWxlSFFzYkM1dVpYaDBQWFFwTEhJdWFXNTBaWEpzWldGMlpXUTlkQ3hRZENobExHNHBm'
    || 'V1oxYm1OMGFXOXVJR2RzS0dVc2RDeHVLWHRwWmloMFBYUXVkWEJrWVhSbFVYVmxkV1VzZENFOVBXNTFiR3dtSmloMFBYUXVjMmhoY21Wa0xDaHVKalF4T1RR'
    || 'eU5EQXBJVDA5TUNrcGUzWmhjaUJ5UFhRdWJHRnVaWE03Y2lZOVpTNXdaVzVrYVc1blRHRnVaWE1zYm53OWNpeDBMbXhoYm1WelBXNHNYMmtvWlN4dUtYMTla'
    || 'blZ1WTNScGIyNGdXWFVvWlN4MEtYdDJZWElnYmoxbExuVndaR0YwWlZGMVpYVmxMSEk5WlM1aGJIUmxjbTVoZEdVN2FXWW9jaUU5UFc1MWJHd21KaWh5UFhJ'
    || 'dWRYQmtZWFJsVVhWbGRXVXNiajA5UFhJcEtYdDJZWElnYkQxdWRXeHNMR2s5Ym5Wc2JEdHBaaWh1UFc0dVptbHljM1JDWVhObFZYQmtZWFJsTEc0aFBUMXVk'
    || 'V3hzS1h0a2IzdDJZWElnY3oxN1pYWmxiblJVYVcxbE9tNHVaWFpsYm5SVWFXMWxMR3hoYm1VNmJpNXNZVzVsTEhSaFp6cHVMblJoWnl4d1lYbHNiMkZrT200'
    || 'dWNHRjViRzloWkN4allXeHNZbUZqYXpwdUxtTmhiR3hpWVdOckxHNWxlSFE2Ym5Wc2JIMDdhVDA5UFc1MWJHdy9iRDFwUFhNNmFUMXBMbTVsZUhROWN5eHVQ'
    || 'VzR1Ym1WNGRIMTNhR2xzWlNodUlUMDliblZzYkNrN2FUMDlQVzUxYkd3L2JEMXBQWFE2YVQxcExtNWxlSFE5ZEgxbGJITmxJR3c5YVQxME8yNDllMkpoYzJW'
    || 'VGRHRjBaVHB5TG1KaGMyVlRkR0YwWlN4bWFYSnpkRUpoYzJWVmNHUmhkR1U2YkN4c1lYTjBRbUZ6WlZWd1pHRjBaVHBwTEhOb1lYSmxaRHB5TG5Ob1lYSmxa'
    || 'Q3hsWm1abFkzUnpPbkl1WldabVpXTjBjMzBzWlM1MWNHUmhkR1ZSZFdWMVpUMXVPM0psZEhWeWJuMWxQVzR1YkdGemRFSmhjMlZWY0dSaGRHVXNaVDA5UFc1'
    || 'MWJHdy9iaTVtYVhKemRFSmhjMlZWY0dSaGRHVTlkRHBsTG01bGVIUTlkQ3h1TG14aGMzUkNZWE5sVlhCa1lYUmxQWFI5Wm5WdVkzUnBiMjRnZVd3b1pTeDBM'
    || 'RzRzY2lsN2RtRnlJR3c5WlM1MWNHUmhkR1ZSZFdWMVpUdExkRDBoTVR0MllYSWdhVDFzTG1acGNuTjBRbUZ6WlZWd1pHRjBaU3h6UFd3dWJHRnpkRUpoYzJW'
    || 'VmNHUmhkR1VzWkQxc0xuTm9ZWEpsWkM1d1pXNWthVzVuTzJsbUtHUWhQVDF1ZFd4c0tYdHNMbk5vWVhKbFpDNXdaVzVrYVc1blBXNTFiR3c3ZG1GeUlHWTla'
    || 'Q3g1UFdZdWJtVjRkRHRtTG01bGVIUTliblZzYkN4elBUMDliblZzYkQ5cFBYazZjeTV1WlhoMFBYa3NjejFtTzNaaGNpQnJQV1V1WVd4MFpYSnVZWFJsTzJz'
    || 'aFBUMXVkV3hzSmlZb2F6MXJMblZ3WkdGMFpWRjFaWFZsTEdROWF5NXNZWE4wUW1GelpWVndaR0YwWlN4a0lUMDljeVltS0dROVBUMXVkV3hzUDJzdVptbHlj'
    || 'M1JDWVhObFZYQmtZWFJsUFhrNlpDNXVaWGgwUFhrc2F5NXNZWE4wUW1GelpWVndaR0YwWlQxbUtTbDlhV1lvYVNFOVBXNTFiR3dwZTNaaGNpQk9QV3d1WW1G'
    || 'elpWTjBZWFJsTzNNOU1DeHJQWGs5WmoxdWRXeHNMR1E5YVR0a2IzdDJZWElnWHoxa0xteGhibVVzVHoxa0xtVjJaVzUwVkdsdFpUdHBaaWdvY2laZktUMDlQ'
    || 'VjhwZTJzaFBUMXVkV3hzSmlZb2F6MXJMbTVsZUhROWUyVjJaVzUwVkdsdFpUcFBMR3hoYm1VNk1DeDBZV2M2WkM1MFlXY3NjR0Y1Ykc5aFpEcGtMbkJoZVd4'
    || 'dllXUXNZMkZzYkdKaFkyczZaQzVqWVd4c1ltRmpheXh1WlhoME9tNTFiR3g5S1R0bE9udDJZWElnU1QxbExFMDlaRHR6ZDJsMFkyZ29YejEwTEU4OWJpeE5M'
    || 'blJoWnlsN1kyRnpaU0F4T21sbUtFazlUUzV3WVhsc2IyRmtMSFI1Y0dWdlppQkpQVDBpWm5WdVkzUnBiMjRpS1h0T1BVa3VZMkZzYkNoUExFNHNYeWs3WW5K'
    || 'bFlXc2daWDFPUFVrN1luSmxZV3NnWlR0allYTmxJRE02U1M1bWJHRm5jejFKTG1ac1lXZHpKaTAyTlRVek4zd3hNamc3WTJGelpTQXdPbWxtS0VrOVRTNXdZ'
    || 'WGxzYjJGa0xGODlkSGx3Wlc5bUlFazlQU0ptZFc1amRHbHZiaUkvU1M1allXeHNLRThzVGl4ZktUcEpMRjg5UFc1MWJHd3BZbkpsWVdzZ1pUdE9QVXdvZTMw'
    || 'c1RpeGZLVHRpY21WaGF5QmxPMk5oYzJVZ01qcExkRDBoTUgxOVpDNWpZV3hzWW1GamF5RTlQVzUxYkd3bUptUXViR0Z1WlNFOVBUQW1KaWhsTG1ac1lXZHpm'
    || 'RDAyTkN4ZlBXd3VaV1ptWldOMGN5eGZQVDA5Ym5Wc2JEOXNMbVZtWm1WamRITTlXMlJkT2w4dWNIVnphQ2hrS1NsOVpXeHpaU0JQUFh0bGRtVnVkRlJwYldV'
    || 'NlR5eHNZVzVsT2w4c2RHRm5PbVF1ZEdGbkxIQmhlV3h2WVdRNlpDNXdZWGxzYjJGa0xHTmhiR3hpWVdOck9tUXVZMkZzYkdKaFkyc3NibVY0ZERwdWRXeHNm'
    || 'U3hyUFQwOWJuVnNiRDhvZVQxclBVOHNaajFPS1RwclBXc3VibVY0ZEQxUExITjhQVjg3YVdZb1pEMWtMbTVsZUhRc1pEMDlQVzUxYkd3cGUybG1LR1E5YkM1'
    || 'emFHRnlaV1F1Y0dWdVpHbHVaeXhrUFQwOWJuVnNiQ2xpY21WaGF6dGZQV1FzWkQxZkxtNWxlSFFzWHk1dVpYaDBQVzUxYkd3c2JDNXNZWE4wUW1GelpWVnda'
    || 'R0YwWlQxZkxHd3VjMmhoY21Wa0xuQmxibVJwYm1jOWJuVnNiSDE5ZDJocGJHVW9JVEFwTzJsbUtHczlQVDF1ZFd4c0ppWW9aajFPS1N4c0xtSmhjMlZUZEdG'
    || 'MFpUMW1MR3d1Wm1seWMzUkNZWE5sVlhCa1lYUmxQWGtzYkM1c1lYTjBRbUZ6WlZWd1pHRjBaVDFyTEhROWJDNXphR0Z5WldRdWFXNTBaWEpzWldGMlpXUXNk'
    || 'Q0U5UFc1MWJHd3BlMnc5ZER0a2J5QnpmRDFzTG14aGJtVXNiRDFzTG01bGVIUTdkMmhwYkdVb2JDRTlQWFFwZldWc2MyVWdhVDA5UFc1MWJHd21KaWhzTG5O'
    || 'b1lYSmxaQzVzWVc1bGN6MHdLVHR0Ym53OWN5eGxMbXhoYm1WelBYTXNaUzV0WlcxdmFYcGxaRk4wWVhSbFBVNTlmV1oxYm1OMGFXOXVJRWQxS0dVc2RDeHVL'
    || 'WHRwWmlobFBYUXVaV1ptWldOMGN5eDBMbVZtWm1WamRITTliblZzYkN4bElUMDliblZzYkNsbWIzSW9kRDB3TzNROFpTNXNaVzVuZEdnN2RDc3JLWHQyWVhJ'
    || 'Z2NqMWxXM1JkTEd3OWNpNWpZV3hzWW1GamF6dHBaaWhzSVQwOWJuVnNiQ2w3YVdZb2NpNWpZV3hzWW1GamF6MXVkV3hzTEhJOWJpeDBlWEJsYjJZZ2JDRTlJ'
    || 'bVoxYm1OMGFXOXVJaWwwYUhKdmR5QkZjbkp2Y2loaEtERTVNU3hzS1NrN2JDNWpZV3hzS0hJcGZYMTlkbUZ5SUhoeVBYdDlMR3AwUFZGMEtIaHlLU3hGY2ox'
    || 'UmRDaDRjaWtzWDNJOVVYUW9lSElwTzJaMWJtTjBhVzl1SUhCdUtHVXBlMmxtS0dVOVBUMTRjaWwwYUhKdmR5QkZjbkp2Y2loaEtERTNOQ2twTzNKbGRIVnli'
    || 'aUJsZldaMWJtTjBhVzl1SUhWdktHVXNkQ2w3YzNkcGRHTm9LR1psS0Y5eUxIUXBMR1psS0VWeUxHVXBMR1psS0dwMExIaHlLU3hsUFhRdWJtOWtaVlI1Y0dV'
    || 'c1pTbDdZMkZ6WlNBNU9tTmhjMlVnTVRFNmREMG9kRDEwTG1SdlkzVnRaVzUwUld4bGJXVnVkQ2svZEM1dVlXMWxjM0JoWTJWVlVrazZZV2tvYm5Wc2JDd2lJ'
    || 'aWs3WW5KbFlXczdaR1ZtWVhWc2REcGxQV1U5UFQwNFAzUXVjR0Z5Wlc1MFRtOWtaVHAwTEhROVpTNXVZVzFsYzNCaFkyVlZVa2w4Zkc1MWJHd3NaVDFsTG5S'
    || 'aFowNWhiV1VzZEQxaGFTaDBMR1VwZldobEtHcDBLU3htWlNocWRDeDBLWDFtZFc1amRHbHZiaUJYYmlncGUyaGxLR3AwS1N4b1pTaEZjaWtzYUdVb1gzSXBm'
    || 'V1oxYm1OMGFXOXVJRXQxS0dVcGUzQnVLRjl5TG1OMWNuSmxiblFwTzNaaGNpQjBQWEJ1S0dwMExtTjFjbkpsYm5RcExHNDlZV2tvZEN4bExuUjVjR1VwTzNR'
    || 'aFBUMXVKaVlvWm1Vb1JYSXNaU2tzWm1Vb2FuUXNiaWtwZldaMWJtTjBhVzl1SUdGdktHVXBlMFZ5TG1OMWNuSmxiblE5UFQxbEppWW9hR1VvYW5RcExHaGxL'
    || 'RVZ5S1NsOWRtRnlJSGxsUFZGMEtEQXBPMloxYm1OMGFXOXVJSGhzS0dVcGUyWnZjaWgyWVhJZ2REMWxPM1FoUFQxdWRXeHNPeWw3YVdZb2RDNTBZV2M5UFQw'
    || 'eE15bDdkbUZ5SUc0OWRDNXRaVzF2YVhwbFpGTjBZWFJsTzJsbUtHNGhQVDF1ZFd4c0ppWW9iajF1TG1SbGFIbGtjbUYwWldRc2JqMDlQVzUxYkd4OGZHNHVa'
    || 'R0YwWVQwOVBTSWtQeUo4Zkc0dVpHRjBZVDA5UFNJa0lTSXBLWEpsZEhWeWJpQjBmV1ZzYzJVZ2FXWW9kQzUwWVdjOVBUMHhPU1ltZEM1dFpXMXZhWHBsWkZC'
    || 'eWIzQnpMbkpsZG1WaGJFOXlaR1Z5SVQwOWRtOXBaQ0F3S1h0cFppZ29kQzVtYkdGbmN5WXhNamdwSVQwOU1DbHlaWFIxY200Z2RIMWxiSE5sSUdsbUtIUXVZ'
    || 'MmhwYkdRaFBUMXVkV3hzS1h0MExtTm9hV3hrTG5KbGRIVnliajEwTEhROWRDNWphR2xzWkR0amIyNTBhVzUxWlgxcFppaDBQVDA5WlNsaWNtVmhhenRtYjNJ'
    || 'b08zUXVjMmxpYkdsdVp6MDlQVzUxYkd3N0tYdHBaaWgwTG5KbGRIVnliajA5UFc1MWJHeDhmSFF1Y21WMGRYSnVQVDA5WlNseVpYUjFjbTRnYm5Wc2JEdDBQ'
    || 'WFF1Y21WMGRYSnVmWFF1YzJsaWJHbHVaeTV5WlhSMWNtNDlkQzV5WlhSMWNtNHNkRDEwTG5OcFlteHBibWQ5Y21WMGRYSnVJRzUxYkd4OWRtRnlJR052UFZ0'
    || 'ZE8yWjFibU4wYVc5dUlHWnZLQ2w3Wm05eUtIWmhjaUJsUFRBN1pUeGpieTVzWlc1bmRHZzdaU3NyS1dOdlcyVmRMbDkzYjNKclNXNVFjbTluY21WemMxWmxj'
    || 'bk5wYjI1UWNtbHRZWEo1UFc1MWJHdzdZMjh1YkdWdVozUm9QVEI5ZG1GeUlFVnNQVXN1VW1WaFkzUkRkWEp5Wlc1MFJHbHpjR0YwWTJobGNpeHdiejFMTGxK'
    || 'bFlXTjBRM1Z5Y21WdWRFSmhkR05vUTI5dVptbG5MR2h1UFRBc2VHVTliblZzYkN4VVpUMXVkV3hzTEVSbFBXNTFiR3dzWDJ3OUlURXNVM0k5SVRFc2QzSTlN'
    || 'Q3hFWmowd08yWjFibU4wYVc5dUlFWmxLQ2w3ZEdoeWIzY2dSWEp5YjNJb1lTZ3pNakVwS1gxbWRXNWpkR2x2YmlCb2J5aGxMSFFwZTJsbUtIUTlQVDF1ZFd4'
    || 'c0tYSmxkSFZ5YmlFeE8yWnZjaWgyWVhJZ2JqMHdPMjQ4ZEM1c1pXNW5kR2dtSm00OFpTNXNaVzVuZEdnN2Jpc3JLV2xtS0NGb2RDaGxXMjVkTEhSYmJsMHBL'
    || 'WEpsZEhWeWJpRXhPM0psZEhWeWJpRXdmV1oxYm1OMGFXOXVJRzF2S0dVc2RDeHVMSElzYkN4cEtYdHBaaWhvYmoxcExIaGxQWFFzZEM1dFpXMXZhWHBsWkZO'
    || 'MFlYUmxQVzUxYkd3c2RDNTFjR1JoZEdWUmRXVjFaVDF1ZFd4c0xIUXViR0Z1WlhNOU1DeEZiQzVqZFhKeVpXNTBQV1U5UFQxdWRXeHNmSHhsTG0xbGJXOXBl'
    || 'bVZrVTNSaGRHVTlQVDF1ZFd4c1AwbG1Pa0ZtTEdVOWJpaHlMR3dwTEZOeUtYdHBQVEE3Wkc5N2FXWW9VM0k5SVRFc2QzSTlNQ3d5TlR3OWFTbDBhSEp2ZHlC'
    || 'RmNuSnZjaWhoS0RNd01Ta3BPMmtyUFRFc1JHVTlWR1U5Ym5Wc2JDeDBMblZ3WkdGMFpWRjFaWFZsUFc1MWJHd3NSV3d1WTNWeWNtVnVkRDFOWml4bFBXNG9j'
    || 'aXhzS1gxM2FHbHNaU2hUY2lsOWFXWW9SV3d1WTNWeWNtVnVkRDFyYkN4MFBWUmxJVDA5Ym5Wc2JDWW1WR1V1Ym1WNGRDRTlQVzUxYkd3c2FHNDlNQ3hFWlQx'
    || 'VVpUMTRaVDF1ZFd4c0xGOXNQU0V4TEhRcGRHaHliM2NnUlhKeWIzSW9ZU2d6TURBcEtUdHlaWFIxY200Z1pYMW1kVzVqZEdsdmJpQjJieWdwZTNaaGNpQmxQ'
    || 'WGR5SVQwOU1EdHlaWFIxY200Z2QzSTlNQ3hsZldaMWJtTjBhVzl1SUU1MEtDbDdkbUZ5SUdVOWUyMWxiVzlwZW1Wa1UzUmhkR1U2Ym5Wc2JDeGlZWE5sVTNS'
    || 'aGRHVTZiblZzYkN4aVlYTmxVWFZsZFdVNmJuVnNiQ3h4ZFdWMVpUcHVkV3hzTEc1bGVIUTZiblZzYkgwN2NtVjBkWEp1SUVSbFBUMDliblZzYkQ5NFpTNXRa'
    || 'VzF2YVhwbFpGTjBZWFJsUFVSbFBXVTZSR1U5UkdVdWJtVjRkRDFsTEVSbGZXWjFibU4wYVc5dUlIVjBLQ2w3YVdZb1ZHVTlQVDF1ZFd4c0tYdDJZWElnWlQx'
    || 'NFpTNWhiSFJsY201aGRHVTdaVDFsSVQwOWJuVnNiRDlsTG0xbGJXOXBlbVZrVTNSaGRHVTZiblZzYkgxbGJITmxJR1U5VkdVdWJtVjRkRHQyWVhJZ2REMUVa'
    || 'VDA5UFc1MWJHdy9lR1V1YldWdGIybDZaV1JUZEdGMFpUcEVaUzV1WlhoME8ybG1LSFFoUFQxdWRXeHNLVVJsUFhRc1ZHVTlaVHRsYkhObGUybG1LR1U5UFQx'
    || 'dWRXeHNLWFJvY205M0lFVnljbTl5S0dFb016RXdLU2s3VkdVOVpTeGxQWHR0WlcxdmFYcGxaRk4wWVhSbE9sUmxMbTFsYlc5cGVtVmtVM1JoZEdVc1ltRnpa'
    || 'Vk4wWVhSbE9sUmxMbUpoYzJWVGRHRjBaU3hpWVhObFVYVmxkV1U2VkdVdVltRnpaVkYxWlhWbExIRjFaWFZsT2xSbExuRjFaWFZsTEc1bGVIUTZiblZzYkgw'
    || 'c1JHVTlQVDF1ZFd4c1AzaGxMbTFsYlc5cGVtVmtVM1JoZEdVOVJHVTlaVHBFWlQxRVpTNXVaWGgwUFdWOWNtVjBkWEp1SUVSbGZXWjFibU4wYVc5dUlHdHlL'
    || 'R1VzZENsN2NtVjBkWEp1SUhSNWNHVnZaaUIwUFQwaVpuVnVZM1JwYjI0aVAzUW9aU2s2ZEgxbWRXNWpkR2x2YmlCbmJ5aGxLWHQyWVhJZ2REMTFkQ2dwTEc0'
    || 'OWRDNXhkV1YxWlR0cFppaHVQVDA5Ym5Wc2JDbDBhSEp2ZHlCRmNuSnZjaWhoS0RNeE1Ta3BPMjR1YkdGemRGSmxibVJsY21Wa1VtVmtkV05sY2oxbE8zWmhj'
    || 'aUJ5UFZSbExHdzljaTVpWVhObFVYVmxkV1VzYVQxdUxuQmxibVJwYm1jN2FXWW9hU0U5UFc1MWJHd3BlMmxtS0d3aFBUMXVkV3hzS1h0MllYSWdjejFzTG01'
    || 'bGVIUTdiQzV1WlhoMFBXa3VibVY0ZEN4cExtNWxlSFE5YzMxeUxtSmhjMlZSZFdWMVpUMXNQV2tzYmk1d1pXNWthVzVuUFc1MWJHeDlhV1lvYkNFOVBXNTFi'
    || 'R3dwZTJrOWJDNXVaWGgwTEhJOWNpNWlZWE5sVTNSaGRHVTdkbUZ5SUdROWN6MXVkV3hzTEdZOWJuVnNiQ3g1UFdrN1pHOTdkbUZ5SUdzOWVTNXNZVzVsTzJs'
    || 'bUtDaG9iaVpyS1QwOVBXc3BaaUU5UFc1MWJHd21KaWhtUFdZdWJtVjRkRDE3YkdGdVpUb3dMR0ZqZEdsdmJqcDVMbUZqZEdsdmJpeG9ZWE5GWVdkbGNsTjBZ'
    || 'WFJsT25rdWFHRnpSV0ZuWlhKVGRHRjBaU3hsWVdkbGNsTjBZWFJsT25rdVpXRm5aWEpUZEdGMFpTeHVaWGgwT201MWJHeDlLU3h5UFhrdWFHRnpSV0ZuWlhK'
    || 'VGRHRjBaVDk1TG1WaFoyVnlVM1JoZEdVNlpTaHlMSGt1WVdOMGFXOXVLVHRsYkhObGUzWmhjaUJPUFh0c1lXNWxPbXNzWVdOMGFXOXVPbmt1WVdOMGFXOXVM'
    || 'R2hoYzBWaFoyVnlVM1JoZEdVNmVTNW9ZWE5GWVdkbGNsTjBZWFJsTEdWaFoyVnlVM1JoZEdVNmVTNWxZV2RsY2xOMFlYUmxMRzVsZUhRNmJuVnNiSDA3Wmow'
    || 'OVBXNTFiR3cvS0dROVpqMU9MSE05Y2lrNlpqMW1MbTVsZUhROVRpeDRaUzVzWVc1bGMzdzlheXh0Ym53OWEzMTVQWGt1Ym1WNGRIMTNhR2xzWlNoNUlUMDli'
    || 'blZzYkNZbWVTRTlQV2twTzJZOVBUMXVkV3hzUDNNOWNqcG1MbTVsZUhROVpDeG9kQ2h5TEhRdWJXVnRiMmw2WldSVGRHRjBaU2w4ZkNoTFpUMGhNQ2tzZEM1'
    || 'dFpXMXZhWHBsWkZOMFlYUmxQWElzZEM1aVlYTmxVM1JoZEdVOWN5eDBMbUpoYzJWUmRXVjFaVDFtTEc0dWJHRnpkRkpsYm1SbGNtVmtVM1JoZEdVOWNuMXBa'
    || 'aWhsUFc0dWFXNTBaWEpzWldGMlpXUXNaU0U5UFc1MWJHd3BlMnc5WlR0a2J5QnBQV3d1YkdGdVpTeDRaUzVzWVc1bGMzdzlhU3h0Ym53OWFTeHNQV3d1Ym1W'
    || 'NGREdDNhR2xzWlNoc0lUMDlaU2w5Wld4elpTQnNQVDA5Ym5Wc2JDWW1LRzR1YkdGdVpYTTlNQ2s3Y21WMGRYSnVXM1F1YldWdGIybDZaV1JUZEdGMFpTeHVM'
    || 'bVJwYzNCaGRHTm9YWDFtZFc1amRHbHZiaUI1YnlobEtYdDJZWElnZEQxMWRDZ3BMRzQ5ZEM1eGRXVjFaVHRwWmlodVBUMDliblZzYkNsMGFISnZkeUJGY25K'
    || 'dmNpaGhLRE14TVNrcE8yNHViR0Z6ZEZKbGJtUmxjbVZrVW1Wa2RXTmxjajFsTzNaaGNpQnlQVzR1WkdsemNHRjBZMmdzYkQxdUxuQmxibVJwYm1jc2FUMTBM'
    || 'bTFsYlc5cGVtVmtVM1JoZEdVN2FXWW9iQ0U5UFc1MWJHd3BlMjR1Y0dWdVpHbHVaejF1ZFd4c08zWmhjaUJ6UFd3OWJDNXVaWGgwTzJSdklHazlaU2hwTEhN'
    || 'dVlXTjBhVzl1S1N4elBYTXVibVY0ZER0M2FHbHNaU2h6SVQwOWJDazdhSFFvYVN4MExtMWxiVzlwZW1Wa1UzUmhkR1VwZkh3b1MyVTlJVEFwTEhRdWJXVnRi'
    || 'Mmw2WldSVGRHRjBaVDFwTEhRdVltRnpaVkYxWlhWbFBUMDliblZzYkNZbUtIUXVZbUZ6WlZOMFlYUmxQV2twTEc0dWJHRnpkRkpsYm1SbGNtVmtVM1JoZEdV'
    || 'OWFYMXlaWFIxY201YmFTeHlYWDFtZFc1amRHbHZiaUJZZFNncGUzMW1kVzVqZEdsdmJpQmFkU2hsTEhRcGUzWmhjaUJ1UFhobExISTlkWFFvS1N4c1BYUW9L'
    || 'U3hwUFNGb2RDaHlMbTFsYlc5cGVtVmtVM1JoZEdVc2JDazdhV1lvYVNZbUtISXViV1Z0YjJsNlpXUlRkR0YwWlQxc0xFdGxQU0V3S1N4eVBYSXVjWFZsZFdV'
    || 'c2VHOG9ZblV1WW1sdVpDaHVkV3hzTEc0c2NpeGxLU3hiWlYwcExISXVaMlYwVTI1aGNITm9iM1FoUFQxMGZIeHBmSHhFWlNFOVBXNTFiR3dtSmtSbExtMWxi'
    || 'VzlwZW1Wa1UzUmhkR1V1ZEdGbkpqRXBlMmxtS0c0dVpteGhaM044UFRJd05EZ3NhbklvT1N4S2RTNWlhVzVrS0c1MWJHd3NiaXh5TEd3c2RDa3NkbTlwWkNB'
    || 'd0xHNTFiR3dwTEU5bFBUMDliblZzYkNsMGFISnZkeUJGY25KdmNpaGhLRE0wT1NrcE95aG9iaVl6TUNraFBUMHdmSHh4ZFNodUxIUXNiQ2w5Y21WMGRYSnVJ'
    || 'R3g5Wm5WdVkzUnBiMjRnY1hVb1pTeDBMRzRwZTJVdVpteGhaM044UFRFMk16ZzBMR1U5ZTJkbGRGTnVZWEJ6YUc5ME9uUXNkbUZzZFdVNmJuMHNkRDE0WlM1'
    || 'MWNHUmhkR1ZSZFdWMVpTeDBQVDA5Ym5Wc2JEOG9kRDE3YkdGemRFVm1abVZqZERwdWRXeHNMSE4wYjNKbGN6cHVkV3hzZlN4NFpTNTFjR1JoZEdWUmRXVjFa'
    || 'VDEwTEhRdWMzUnZjbVZ6UFZ0bFhTazZLRzQ5ZEM1emRHOXlaWE1zYmowOVBXNTFiR3cvZEM1emRHOXlaWE05VzJWZE9tNHVjSFZ6YUNobEtTbDlablZ1WTNS'
    || 'cGIyNGdTblVvWlN4MExHNHNjaWw3ZEM1MllXeDFaVDF1TEhRdVoyVjBVMjVoY0hOb2IzUTljaXhsWVNoMEtTWW1kR0VvWlNsOVpuVnVZM1JwYjI0Z1luVW9a'
    || 'U3gwTEc0cGUzSmxkSFZ5YmlCdUtHWjFibU4wYVc5dUtDbDdaV0VvZENrbUpuUmhLR1VwZlNsOVpuVnVZM1JwYjI0Z1pXRW9aU2w3ZG1GeUlIUTlaUzVuWlhS'
    || 'VGJtRndjMmh2ZER0bFBXVXVkbUZzZFdVN2RISjVlM1poY2lCdVBYUW9LVHR5WlhSMWNtNGhhSFFvWlN4dUtYMWpZWFJqYUh0eVpYUjFjbTRoTUgxOVpuVnVZ'
    || 'M1JwYjI0Z2RHRW9aU2w3ZG1GeUlIUTlVSFFvWlN3eEtUdDBJVDA5Ym5Wc2JDWW1lSFFvZEN4bExERXNMVEVwZldaMWJtTjBhVzl1SUc1aEtHVXBlM1poY2lC'
    || 'MFBVNTBLQ2s3Y21WMGRYSnVJSFI1Y0dWdlppQmxQVDBpWm5WdVkzUnBiMjRpSmlZb1pUMWxLQ2twTEhRdWJXVnRiMmw2WldSVGRHRjBaVDEwTG1KaGMyVlRk'
    || 'R0YwWlQxbExHVTllM0JsYm1ScGJtYzZiblZzYkN4cGJuUmxjbXhsWVhabFpEcHVkV3hzTEd4aGJtVnpPakFzWkdsemNHRjBZMmc2Ym5Wc2JDeHNZWE4wVW1W'
    || 'dVpHVnlaV1JTWldSMVkyVnlPbXR5TEd4aGMzUlNaVzVrWlhKbFpGTjBZWFJsT21WOUxIUXVjWFZsZFdVOVpTeGxQV1V1WkdsemNHRjBZMmc5VEdZdVltbHVa'
    || 'Q2h1ZFd4c0xIaGxMR1VwTEZ0MExtMWxiVzlwZW1Wa1UzUmhkR1VzWlYxOVpuVnVZM1JwYjI0Z2FuSW9aU3gwTEc0c2NpbDdjbVYwZFhKdUlHVTllM1JoWnpw'
    || 'bExHTnlaV0YwWlRwMExHUmxjM1J5YjNrNmJpeGtaWEJ6T25Jc2JtVjRkRHB1ZFd4c2ZTeDBQWGhsTG5Wd1pHRjBaVkYxWlhWbExIUTlQVDF1ZFd4c1B5aDBQ'
    || 'WHRzWVhOMFJXWm1aV04wT201MWJHd3NjM1J2Y21Wek9tNTFiR3g5TEhobExuVndaR0YwWlZGMVpYVmxQWFFzZEM1c1lYTjBSV1ptWldOMFBXVXVibVY0ZEQx'
    || 'bEtUb29iajEwTG14aGMzUkZabVpsWTNRc2JqMDlQVzUxYkd3L2RDNXNZWE4wUldabVpXTjBQV1V1Ym1WNGREMWxPaWh5UFc0dWJtVjRkQ3h1TG01bGVIUTla'
    || 'U3hsTG01bGVIUTljaXgwTG14aGMzUkZabVpsWTNROVpTa3BMR1Y5Wm5WdVkzUnBiMjRnY21Fb0tYdHlaWFIxY200Z2RYUW9LUzV0WlcxdmFYcGxaRk4wWVhS'
    || 'bGZXWjFibU4wYVc5dUlGTnNLR1VzZEN4dUxISXBlM1poY2lCc1BVNTBLQ2s3ZUdVdVpteGhaM044UFdVc2JDNXRaVzF2YVhwbFpGTjBZWFJsUFdweUtERjhk'
    || 'Q3h1TEhadmFXUWdNQ3h5UFQwOWRtOXBaQ0F3UDI1MWJHdzZjaWw5Wm5WdVkzUnBiMjRnZDJ3b1pTeDBMRzRzY2lsN2RtRnlJR3c5ZFhRb0tUdHlQWEk5UFQx'
    || 'MmIybGtJREEvYm5Wc2JEcHlPM1poY2lCcFBYWnZhV1FnTUR0cFppaFVaU0U5UFc1MWJHd3BlM1poY2lCelBWUmxMbTFsYlc5cGVtVmtVM1JoZEdVN2FXWW9h'
    || 'VDF6TG1SbGMzUnliM2tzY2lFOVBXNTFiR3dtSm1odktISXNjeTVrWlhCektTbDdiQzV0WlcxdmFYcGxaRk4wWVhSbFBXcHlLSFFzYml4cExISXBPM0psZEhW'
    || 'eWJuMTllR1V1Wm14aFozTjhQV1VzYkM1dFpXMXZhWHBsWkZOMFlYUmxQV3B5S0RGOGRDeHVMR2tzY2lsOVpuVnVZM1JwYjI0Z2JHRW9aU3gwS1h0eVpYUjFj'
    || 'bTRnVTJ3b09ETTVNRFkxTml3NExHVXNkQ2w5Wm5WdVkzUnBiMjRnZUc4b1pTeDBLWHR5WlhSMWNtNGdkMndvTWpBME9DdzRMR1VzZENsOVpuVnVZM1JwYjI0'
    || 'Z2FXRW9aU3gwS1h0eVpYUjFjbTRnZDJ3b05Dd3lMR1VzZENsOVpuVnVZM1JwYjI0Z2IyRW9aU3gwS1h0eVpYUjFjbTRnZDJ3b05DdzBMR1VzZENsOVpuVnVZ'
    || 'M1JwYjI0Z2MyRW9aU3gwS1h0cFppaDBlWEJsYjJZZ2REMDlJbVoxYm1OMGFXOXVJaWx5WlhSMWNtNGdaVDFsS0Nrc2RDaGxLU3htZFc1amRHbHZiaWdwZTNR'
    || 'b2JuVnNiQ2w5TzJsbUtIUWhQVzUxYkd3cGNtVjBkWEp1SUdVOVpTZ3BMSFF1WTNWeWNtVnVkRDFsTEdaMWJtTjBhVzl1S0NsN2RDNWpkWEp5Wlc1MFBXNTFi'
    || 'R3g5ZldaMWJtTjBhVzl1SUhWaEtHVXNkQ3h1S1h0eVpYUjFjbTRnYmoxdUlUMXVkV3hzUDI0dVkyOXVZMkYwS0Z0bFhTazZiblZzYkN4M2JDZzBMRFFzYzJF'
    || 'dVltbHVaQ2h1ZFd4c0xIUXNaU2tzYmlsOVpuVnVZM1JwYjI0Z1JXOG9LWHQ5Wm5WdVkzUnBiMjRnWVdFb1pTeDBLWHQyWVhJZ2JqMTFkQ2dwTzNROWREMDlQ'
    || 'WFp2YVdRZ01EOXVkV3hzT25RN2RtRnlJSEk5Ymk1dFpXMXZhWHBsWkZOMFlYUmxPM0psZEhWeWJpQnlJVDA5Ym5Wc2JDWW1kQ0U5UFc1MWJHd21KbWh2S0hR'
    || 'c2Nsc3hYU2svY2xzd1hUb29iaTV0WlcxdmFYcGxaRk4wWVhSbFBWdGxMSFJkTEdVcGZXWjFibU4wYVc5dUlHTmhLR1VzZENsN2RtRnlJRzQ5ZFhRb0tUdDBQ'
    || 'WFE5UFQxMmIybGtJREEvYm5Wc2JEcDBPM1poY2lCeVBXNHViV1Z0YjJsNlpXUlRkR0YwWlR0eVpYUjFjbTRnY2lFOVBXNTFiR3dtSm5RaFBUMXVkV3hzSmla'
    || 'b2J5aDBMSEpiTVYwcFAzSmJNRjA2S0dVOVpTZ3BMRzR1YldWdGIybDZaV1JUZEdGMFpUMWJaU3gwWFN4bEtYMW1kVzVqZEdsdmJpQmtZU2hsTEhRc2JpbDdj'
    || 'bVYwZFhKdUtHaHVKakl4S1QwOVBUQS9LR1V1WW1GelpWTjBZWFJsSmlZb1pTNWlZWE5sVTNSaGRHVTlJVEVzUzJVOUlUQXBMR1V1YldWdGIybDZaV1JUZEdG'
    || 'MFpUMXVLVG9vYUhRb2JpeDBLWHg4S0c0OVZuTW9LU3g0WlM1c1lXNWxjM3c5Yml4dGJudzliaXhsTG1KaGMyVlRkR0YwWlQwaE1Da3NkQ2w5Wm5WdVkzUnBi'
    || 'MjRnVDJZb1pTeDBLWHQyWVhJZ2JqMTFaVHQxWlQxdUlUMDlNQ1ltTkQ1dVAyNDZOQ3hsS0NFd0tUdDJZWElnY2oxd2J5NTBjbUZ1YzJsMGFXOXVPM0J2TG5S'
    || 'eVlXNXphWFJwYjI0OWUzMDdkSEo1ZTJVb0lURXBMSFFvS1gxbWFXNWhiR3g1ZTNWbFBXNHNjRzh1ZEhKaGJuTnBkR2x2YmoxeWZYMW1kVzVqZEdsdmJpQm1Z'
    || 'U2dwZTNKbGRIVnliaUIxZENncExtMWxiVzlwZW1Wa1UzUmhkR1Y5Wm5WdVkzUnBiMjRnVUdZb1pTeDBMRzRwZTNaaGNpQnlQV0owS0dVcE8ybG1LRzQ5ZTJ4'
    || 'aGJtVTZjaXhoWTNScGIyNDZiaXhvWVhORllXZGxjbE4wWVhSbE9pRXhMR1ZoWjJWeVUzUmhkR1U2Ym5Wc2JDeHVaWGgwT201MWJHeDlMSEJoS0dVcEtXaGhL'
    || 'SFFzYmlrN1pXeHpaU0JwWmlodVBTUjFLR1VzZEN4dUxISXBMRzRoUFQxdWRXeHNLWHQyWVhJZ2JEMUlaU2dwTzNoMEtHNHNaU3h5TEd3cExHMWhLRzRzZEN4'
    || 'eUtYMTlablZ1WTNScGIyNGdUR1lvWlN4MExHNHBlM1poY2lCeVBXSjBLR1VwTEd3OWUyeGhibVU2Y2l4aFkzUnBiMjQ2Yml4b1lYTkZZV2RsY2xOMFlYUmxP'
    || 'aUV4TEdWaFoyVnlVM1JoZEdVNmJuVnNiQ3h1WlhoME9tNTFiR3g5TzJsbUtIQmhLR1VwS1doaEtIUXNiQ2s3Wld4elpYdDJZWElnYVQxbExtRnNkR1Z5Ym1G'
    || 'MFpUdHBaaWhsTG14aGJtVnpQVDA5TUNZbUtHazlQVDF1ZFd4c2ZIeHBMbXhoYm1WelBUMDlNQ2ttSmlocFBYUXViR0Z6ZEZKbGJtUmxjbVZrVW1Wa2RXTmxj'
    || 'aXhwSVQwOWJuVnNiQ2twZEhKNWUzWmhjaUJ6UFhRdWJHRnpkRkpsYm1SbGNtVmtVM1JoZEdVc1pEMXBLSE1zYmlrN2FXWW9iQzVvWVhORllXZGxjbE4wWVhS'
    || 'bFBTRXdMR3d1WldGblpYSlRkR0YwWlQxa0xHaDBLR1FzY3lrcGUzWmhjaUJtUFhRdWFXNTBaWEpzWldGMlpXUTdaajA5UFc1MWJHdy9LR3d1Ym1WNGREMXNM'
    || 'Rzl2S0hRcEtUb29iQzV1WlhoMFBXWXVibVY0ZEN4bUxtNWxlSFE5YkNrc2RDNXBiblJsY214bFlYWmxaRDFzTzNKbGRIVnlibjE5WTJGMFkyaDdmV1pwYm1G'
    || 'c2JIbDdmVzQ5SkhVb1pTeDBMR3dzY2lrc2JpRTlQVzUxYkd3bUppaHNQVWhsS0Nrc2VIUW9iaXhsTEhJc2JDa3NiV0VvYml4MExISXBLWDE5Wm5WdVkzUnBi'
    || 'MjRnY0dFb1pTbDdkbUZ5SUhROVpTNWhiSFJsY201aGRHVTdjbVYwZFhKdUlHVTlQVDE0Wlh4OGRDRTlQVzUxYkd3bUpuUTlQVDE0WlgxbWRXNWpkR2x2YmlC'
    || 'b1lTaGxMSFFwZTFOeVBWOXNQU0V3TzNaaGNpQnVQV1V1Y0dWdVpHbHVaenR1UFQwOWJuVnNiRDkwTG01bGVIUTlkRG9vZEM1dVpYaDBQVzR1Ym1WNGRDeHVM'
    || 'bTVsZUhROWRDa3NaUzV3Wlc1a2FXNW5QWFI5Wm5WdVkzUnBiMjRnYldFb1pTeDBMRzRwZTJsbUtDaHVKalF4T1RReU5EQXBJVDA5TUNsN2RtRnlJSEk5ZEM1'
    || 'c1lXNWxjenR5SmoxbExuQmxibVJwYm1kTVlXNWxjeXh1ZkQxeUxIUXViR0Z1WlhNOWJpeGZhU2hsTEc0cGZYMTJZWElnYTJ3OWUzSmxZV1JEYjI1MFpYaDBP'
    || 'bk4wTEhWelpVTmhiR3hpWVdOck9rWmxMSFZ6WlVOdmJuUmxlSFE2Um1Vc2RYTmxSV1ptWldOME9rWmxMSFZ6WlVsdGNHVnlZWFJwZG1WSVlXNWtiR1U2Um1V'
    || 'c2RYTmxTVzV6WlhKMGFXOXVSV1ptWldOME9rWmxMSFZ6WlV4aGVXOTFkRVZtWm1WamREcEdaU3gxYzJWTlpXMXZPa1psTEhWelpWSmxaSFZqWlhJNlJtVXNk'
    || 'WE5sVW1WbU9rWmxMSFZ6WlZOMFlYUmxPa1psTEhWelpVUmxZblZuVm1Gc2RXVTZSbVVzZFhObFJHVm1aWEp5WldSV1lXeDFaVHBHWlN4MWMyVlVjbUZ1YzJs'
    || 'MGFXOXVPa1psTEhWelpVMTFkR0ZpYkdWVGIzVnlZMlU2Um1Vc2RYTmxVM2x1WTBWNGRHVnlibUZzVTNSdmNtVTZSbVVzZFhObFNXUTZSbVVzZFc1emRHRmli'
    || 'R1ZmYVhOT1pYZFNaV052Ym1OcGJHVnlPaUV4ZlN4SlpqMTdjbVZoWkVOdmJuUmxlSFE2YzNRc2RYTmxRMkZzYkdKaFkyczZablZ1WTNScGIyNG9aU3gwS1h0'
    || 'eVpYUjFjbTRnVG5Rb0tTNXRaVzF2YVhwbFpGTjBZWFJsUFZ0bExIUTlQVDEyYjJsa0lEQS9iblZzYkRwMFhTeGxmU3gxYzJWRGIyNTBaWGgwT25OMExIVnpa'
    || 'VVZtWm1WamREcHNZU3gxYzJWSmJYQmxjbUYwYVhabFNHRnVaR3hsT21aMWJtTjBhVzl1S0dVc2RDeHVLWHR5WlhSMWNtNGdiajF1SVQxdWRXeHNQMjR1WTI5'
    || 'dVkyRjBLRnRsWFNrNmJuVnNiQ3hUYkNnME1UazBNekE0TERRc2MyRXVZbWx1WkNodWRXeHNMSFFzWlNrc2JpbDlMSFZ6WlV4aGVXOTFkRVZtWm1WamREcG1k'
    || 'VzVqZEdsdmJpaGxMSFFwZTNKbGRIVnliaUJUYkNnME1UazBNekE0TERRc1pTeDBLWDBzZFhObFNXNXpaWEowYVc5dVJXWm1aV04wT21aMWJtTjBhVzl1S0dV'
    || 'c2RDbDdjbVYwZFhKdUlGTnNLRFFzTWl4bExIUXBmU3gxYzJWTlpXMXZPbVoxYm1OMGFXOXVLR1VzZENsN2RtRnlJRzQ5VG5Rb0tUdHlaWFIxY200Z2REMTBQ'
    || 'VDA5ZG05cFpDQXdQMjUxYkd3NmRDeGxQV1VvS1N4dUxtMWxiVzlwZW1Wa1UzUmhkR1U5VzJVc2RGMHNaWDBzZFhObFVtVmtkV05sY2pwbWRXNWpkR2x2Ymlo'
    || 'bExIUXNiaWw3ZG1GeUlISTlUblFvS1R0eVpYUjFjbTRnZEQxdUlUMDlkbTlwWkNBd1AyNG9kQ2s2ZEN4eUxtMWxiVzlwZW1Wa1UzUmhkR1U5Y2k1aVlYTmxV'
    || 'M1JoZEdVOWRDeGxQWHR3Wlc1a2FXNW5PbTUxYkd3c2FXNTBaWEpzWldGMlpXUTZiblZzYkN4c1lXNWxjem93TEdScGMzQmhkR05vT201MWJHd3NiR0Z6ZEZK'
    || 'bGJtUmxjbVZrVW1Wa2RXTmxjanBsTEd4aGMzUlNaVzVrWlhKbFpGTjBZWFJsT25SOUxISXVjWFZsZFdVOVpTeGxQV1V1WkdsemNHRjBZMmc5VUdZdVltbHVa'
    || 'Q2h1ZFd4c0xIaGxMR1VwTEZ0eUxtMWxiVzlwZW1Wa1UzUmhkR1VzWlYxOUxIVnpaVkpsWmpwbWRXNWpkR2x2YmlobEtYdDJZWElnZEQxT2RDZ3BPM0psZEhW'
    || 'eWJpQmxQWHRqZFhKeVpXNTBPbVY5TEhRdWJXVnRiMmw2WldSVGRHRjBaVDFsZlN4MWMyVlRkR0YwWlRwdVlTeDFjMlZFWldKMVoxWmhiSFZsT2tWdkxIVnpa'
    || 'VVJsWm1WeWNtVmtWbUZzZFdVNlpuVnVZM1JwYjI0b1pTbDdjbVYwZFhKdUlFNTBLQ2t1YldWdGIybDZaV1JUZEdGMFpUMWxmU3gxYzJWVWNtRnVjMmwwYVc5'
    || 'dU9tWjFibU4wYVc5dUtDbDdkbUZ5SUdVOWJtRW9JVEVwTEhROVpWc3dYVHR5WlhSMWNtNGdaVDFQWmk1aWFXNWtLRzUxYkd3c1pWc3hYU2tzVG5Rb0tTNXRa'
    || 'VzF2YVhwbFpGTjBZWFJsUFdVc1czUXNaVjE5TEhWelpVMTFkR0ZpYkdWVGIzVnlZMlU2Wm5WdVkzUnBiMjRvS1h0OUxIVnpaVk41Ym1ORmVIUmxjbTVoYkZO'
    || 'MGIzSmxPbVoxYm1OMGFXOXVLR1VzZEN4dUtYdDJZWElnY2oxNFpTeHNQVTUwS0NrN2FXWW9kbVVwZTJsbUtHNDlQVDEyYjJsa0lEQXBkR2h5YjNjZ1JYSnli'
    || 'M0lvWVNnME1EY3BLVHR1UFc0b0tYMWxiSE5sZTJsbUtHNDlkQ2dwTEU5bFBUMDliblZzYkNsMGFISnZkeUJGY25KdmNpaGhLRE0wT1NrcE95aG9iaVl6TUNr'
    || 'aFBUMHdmSHh4ZFNoeUxIUXNiaWw5YkM1dFpXMXZhWHBsWkZOMFlYUmxQVzQ3ZG1GeUlHazllM1poYkhWbE9tNHNaMlYwVTI1aGNITm9iM1E2ZEgwN2NtVjBk'
    || 'WEp1SUd3dWNYVmxkV1U5YVN4c1lTaGlkUzVpYVc1a0tHNTFiR3dzY2l4cExHVXBMRnRsWFNrc2NpNW1iR0ZuYzN3OU1qQTBPQ3hxY2lnNUxFcDFMbUpwYm1R'
    || 'b2JuVnNiQ3h5TEdrc2JpeDBLU3gyYjJsa0lEQXNiblZzYkNrc2JuMHNkWE5sU1dRNlpuVnVZM1JwYjI0b0tYdDJZWElnWlQxT2RDZ3BMSFE5VDJVdWFXUmxi'
    || 'blJwWm1sbGNsQnlaV1pwZUR0cFppaDJaU2w3ZG1GeUlHNDlUM1FzY2oxRWREdHVQU2h5Sm40b01UdzhNekl0Y0hRb2Npa3RNU2twTG5SdlUzUnlhVzVuS0RN'
    || 'eUtTdHVMSFE5SWpvaUszUXJJbElpSzI0c2JqMTNjaXNyTERBOGJpWW1LSFFyUFNKSUlpdHVMblJ2VTNSeWFXNW5LRE15S1Nrc2RDczlJam9pZldWc2MyVWdi'
    || 'ajFFWmlzckxIUTlJam9pSzNRckluSWlLMjR1ZEc5VGRISnBibWNvTXpJcEt5STZJanR5WlhSMWNtNGdaUzV0WlcxdmFYcGxaRk4wWVhSbFBYUjlMSFZ1YzNS'
    || 'aFlteGxYMmx6VG1WM1VtVmpiMjVqYVd4bGNqb2hNWDBzUVdZOWUzSmxZV1JEYjI1MFpYaDBPbk4wTEhWelpVTmhiR3hpWVdOck9tRmhMSFZ6WlVOdmJuUmxl'
    || 'SFE2YzNRc2RYTmxSV1ptWldOME9uaHZMSFZ6WlVsdGNHVnlZWFJwZG1WSVlXNWtiR1U2ZFdFc2RYTmxTVzV6WlhKMGFXOXVSV1ptWldOME9tbGhMSFZ6WlV4'
    || 'aGVXOTFkRVZtWm1WamREcHZZU3gxYzJWTlpXMXZPbU5oTEhWelpWSmxaSFZqWlhJNloyOHNkWE5sVW1WbU9uSmhMSFZ6WlZOMFlYUmxPbVoxYm1OMGFXOXVL'
    || 'Q2w3Y21WMGRYSnVJR2R2S0d0eUtYMHNkWE5sUkdWaWRXZFdZV3gxWlRwRmJ5eDFjMlZFWldabGNuSmxaRlpoYkhWbE9tWjFibU4wYVc5dUtHVXBlM1poY2lC'
    || 'MFBYVjBLQ2s3Y21WMGRYSnVJR1JoS0hRc1ZHVXViV1Z0YjJsNlpXUlRkR0YwWlN4bEtYMHNkWE5sVkhKaGJuTnBkR2x2YmpwbWRXNWpkR2x2YmlncGUzWmhj'
    || 'aUJsUFdkdktHdHlLVnN3WFN4MFBYVjBLQ2t1YldWdGIybDZaV1JUZEdGMFpUdHlaWFIxY201YlpTeDBYWDBzZFhObFRYVjBZV0pzWlZOdmRYSmpaVHBZZFN4'
    || 'MWMyVlRlVzVqUlhoMFpYSnVZV3hUZEc5eVpUcGFkU3gxYzJWSlpEcG1ZU3gxYm5OMFlXSnNaVjlwYzA1bGQxSmxZMjl1WTJsc1pYSTZJVEY5TEUxbVBYdHla'
    || 'V0ZrUTI5dWRHVjRkRHB6ZEN4MWMyVkRZV3hzWW1GamF6cGhZU3gxYzJWRGIyNTBaWGgwT25OMExIVnpaVVZtWm1WamREcDRieXgxYzJWSmJYQmxjbUYwYVha'
    || 'bFNHRnVaR3hsT25WaExIVnpaVWx1YzJWeWRHbHZia1ZtWm1WamREcHBZU3gxYzJWTVlYbHZkWFJGWm1abFkzUTZiMkVzZFhObFRXVnRienBqWVN4MWMyVlNa'
    || 'V1IxWTJWeU9ubHZMSFZ6WlZKbFpqcHlZU3gxYzJWVGRHRjBaVHBtZFc1amRHbHZiaWdwZTNKbGRIVnliaUI1YnlocmNpbDlMSFZ6WlVSbFluVm5WbUZzZFdV'
    || 'NlJXOHNkWE5sUkdWbVpYSnlaV1JXWVd4MVpUcG1kVzVqZEdsdmJpaGxLWHQyWVhJZ2REMTFkQ2dwTzNKbGRIVnliaUJVWlQwOVBXNTFiR3cvZEM1dFpXMXZh'
    || 'WHBsWkZOMFlYUmxQV1U2WkdFb2RDeFVaUzV0WlcxdmFYcGxaRk4wWVhSbExHVXBmU3gxYzJWVWNtRnVjMmwwYVc5dU9tWjFibU4wYVc5dUtDbDdkbUZ5SUdV'
    || 'OWVXOG9hM0lwV3pCZExIUTlkWFFvS1M1dFpXMXZhWHBsWkZOMFlYUmxPM0psZEhWeWJsdGxMSFJkZlN4MWMyVk5kWFJoWW14bFUyOTFjbU5sT2xoMUxIVnpa'
    || 'Vk41Ym1ORmVIUmxjbTVoYkZOMGIzSmxPbHAxTEhWelpVbGtPbVpoTEhWdWMzUmhZbXhsWDJselRtVjNVbVZqYjI1amFXeGxjam9oTVgwN1puVnVZM1JwYjI0'
    || 'Z2RuUW9aU3gwS1h0cFppaGxKaVpsTG1SbFptRjFiSFJRY205d2N5bDdkRDFNS0h0OUxIUXBMR1U5WlM1a1pXWmhkV3gwVUhKdmNITTdabTl5S0haaGNpQnVJ'
    || 'R2x1SUdVcGRGdHVYVDA5UFhadmFXUWdNQ1ltS0hSYmJsMDlaVnR1WFNrN2NtVjBkWEp1SUhSOWNtVjBkWEp1SUhSOVpuVnVZM1JwYjI0Z1gyOG9aU3gwTEc0'
    || 'c2NpbDdkRDFsTG0xbGJXOXBlbVZrVTNSaGRHVXNiajF1S0hJc2RDa3NiajF1UFQxdWRXeHNQM1E2VENoN2ZTeDBMRzRwTEdVdWJXVnRiMmw2WldSVGRHRjBa'
    || 'VDF1TEdVdWJHRnVaWE05UFQwd0ppWW9aUzUxY0dSaGRHVlJkV1YxWlM1aVlYTmxVM1JoZEdVOWJpbDlkbUZ5SUdwc1BYdHBjMDF2ZFc1MFpXUTZablZ1WTNS'
    || 'cGIyNG9aU2w3Y21WMGRYSnVLR1U5WlM1ZmNtVmhZM1JKYm5SbGNtNWhiSE1wUDNOdUtHVXBQVDA5WlRvaE1YMHNaVzV4ZFdWMVpWTmxkRk4wWVhSbE9tWjFi'
    || 'bU4wYVc5dUtHVXNkQ3h1S1h0bFBXVXVYM0psWVdOMFNXNTBaWEp1WVd4ek8zWmhjaUJ5UFVobEtDa3NiRDFpZENobEtTeHBQVXgwS0hJc2JDazdhUzV3WVhs'
    || 'c2IyRmtQWFFzYmlFOWJuVnNiQ1ltS0drdVkyRnNiR0poWTJzOWJpa3NkRDFZZENobExHa3NiQ2tzZENFOVBXNTFiR3dtSmloNGRDaDBMR1VzYkN4eUtTeG5i'
    || 'Q2gwTEdVc2JDa3BmU3hsYm5GMVpYVmxVbVZ3YkdGalpWTjBZWFJsT21aMWJtTjBhVzl1S0dVc2RDeHVLWHRsUFdVdVgzSmxZV04wU1c1MFpYSnVZV3h6TzNa'
    || 'aGNpQnlQVWhsS0Nrc2JEMWlkQ2hsS1N4cFBVeDBLSElzYkNrN2FTNTBZV2M5TVN4cExuQmhlV3h2WVdROWRDeHVJVDF1ZFd4c0ppWW9hUzVqWVd4c1ltRmph'
    || 'ejF1S1N4MFBWaDBLR1VzYVN4c0tTeDBJVDA5Ym5Wc2JDWW1LSGgwS0hRc1pTeHNMSElwTEdkc0tIUXNaU3hzS1NsOUxHVnVjWFZsZFdWR2IzSmpaVlZ3WkdG'
    || 'MFpUcG1kVzVqZEdsdmJpaGxMSFFwZTJVOVpTNWZjbVZoWTNSSmJuUmxjbTVoYkhNN2RtRnlJRzQ5U0dVb0tTeHlQV0owS0dVcExHdzlUSFFvYml4eUtUdHNM'
    || 'blJoWnoweUxIUWhQVzUxYkd3bUppaHNMbU5oYkd4aVlXTnJQWFFwTEhROVdIUW9aU3hzTEhJcExIUWhQVDF1ZFd4c0ppWW9lSFFvZEN4bExISXNiaWtzWjJ3'
    || 'b2RDeGxMSElwS1gxOU8yWjFibU4wYVc5dUlIWmhLR1VzZEN4dUxISXNiQ3hwTEhNcGUzSmxkSFZ5YmlCbFBXVXVjM1JoZEdWT2IyUmxMSFI1Y0dWdlppQmxM'
    || 'bk5vYjNWc1pFTnZiWEJ2Ym1WdWRGVndaR0YwWlQwOUltWjFibU4wYVc5dUlqOWxMbk5vYjNWc1pFTnZiWEJ2Ym1WdWRGVndaR0YwWlNoeUxHa3NjeWs2ZEM1'
    || 'd2NtOTBiM1I1Y0dVbUpuUXVjSEp2ZEc5MGVYQmxMbWx6VUhWeVpWSmxZV04wUTI5dGNHOXVaVzUwUHlGa2NpaHVMSElwZkh3aFpISW9iQ3hwS1RvaE1IMW1k'
    || 'VzVqZEdsdmJpQm5ZU2hsTEhRc2JpbDdkbUZ5SUhJOUlURXNiRDFaZEN4cFBYUXVZMjl1ZEdWNGRGUjVjR1U3Y21WMGRYSnVJSFI1Y0dWdlppQnBQVDBpYjJK'
    || 'cVpXTjBJaVltYVNFOVBXNTFiR3cvYVQxemRDaHBLVG9vYkQxSFpTaDBLVDloYmpwVlpTNWpkWEp5Wlc1MExISTlkQzVqYjI1MFpYaDBWSGx3WlhNc2FUMG9j'
    || 'ajF5SVQxdWRXeHNLVDlNYmlobExHd3BPbGwwS1N4MFBXNWxkeUIwS0c0c2FTa3NaUzV0WlcxdmFYcGxaRk4wWVhSbFBYUXVjM1JoZEdVaFBUMXVkV3hzSmla'
    || 'MExuTjBZWFJsSVQwOWRtOXBaQ0F3UDNRdWMzUmhkR1U2Ym5Wc2JDeDBMblZ3WkdGMFpYSTlhbXdzWlM1emRHRjBaVTV2WkdVOWRDeDBMbDl5WldGamRFbHVk'
    || 'R1Z5Ym1Gc2N6MWxMSEltSmlobFBXVXVjM1JoZEdWT2IyUmxMR1V1WDE5eVpXRmpkRWx1ZEdWeWJtRnNUV1Z0YjJsNlpXUlZibTFoYzJ0bFpFTm9hV3hrUTI5'
    || 'dWRHVjRkRDFzTEdVdVgxOXlaV0ZqZEVsdWRHVnlibUZzVFdWdGIybDZaV1JOWVhOclpXUkRhR2xzWkVOdmJuUmxlSFE5YVNrc2RIMW1kVzVqZEdsdmJpQjVZ'
    || 'U2hsTEhRc2JpeHlLWHRsUFhRdWMzUmhkR1VzZEhsd1pXOW1JSFF1WTI5dGNHOXVaVzUwVjJsc2JGSmxZMlZwZG1WUWNtOXdjejA5SW1aMWJtTjBhVzl1SWlZ'
    || 'bWRDNWpiMjF3YjI1bGJuUlhhV3hzVW1WalpXbDJaVkJ5YjNCektHNHNjaWtzZEhsd1pXOW1JSFF1VlU1VFFVWkZYMk52YlhCdmJtVnVkRmRwYkd4U1pXTmxh'
    || 'WFpsVUhKdmNITTlQU0ptZFc1amRHbHZiaUltSm5RdVZVNVRRVVpGWDJOdmJYQnZibVZ1ZEZkcGJHeFNaV05sYVhabFVISnZjSE1vYml4eUtTeDBMbk4wWVhS'
    || 'bElUMDlaU1ltYW13dVpXNXhkV1YxWlZKbGNHeGhZMlZUZEdGMFpTaDBMSFF1YzNSaGRHVXNiblZzYkNsOVpuVnVZM1JwYjI0Z1UyOG9aU3gwTEc0c2NpbDdk'
    || 'bUZ5SUd3OVpTNXpkR0YwWlU1dlpHVTdiQzV3Y205d2N6MXVMR3d1YzNSaGRHVTlaUzV0WlcxdmFYcGxaRk4wWVhSbExHd3VjbVZtY3oxN2ZTeHpieWhsS1R0'
    || 'MllYSWdhVDEwTG1OdmJuUmxlSFJVZVhCbE8zUjVjR1Z2WmlCcFBUMGliMkpxWldOMElpWW1hU0U5UFc1MWJHdy9iQzVqYjI1MFpYaDBQWE4wS0drcE9paHBQ'
    || 'VWRsS0hRcFAyRnVPbFZsTG1OMWNuSmxiblFzYkM1amIyNTBaWGgwUFV4dUtHVXNhU2twTEd3dWMzUmhkR1U5WlM1dFpXMXZhWHBsWkZOMFlYUmxMR2s5ZEM1'
    || 'blpYUkVaWEpwZG1Wa1UzUmhkR1ZHY205dFVISnZjSE1zZEhsd1pXOW1JR2s5UFNKbWRXNWpkR2x2YmlJbUppaGZieWhsTEhRc2FTeHVLU3hzTG5OMFlYUmxQ'
    || 'V1V1YldWdGIybDZaV1JUZEdGMFpTa3NkSGx3Wlc5bUlIUXVaMlYwUkdWeWFYWmxaRk4wWVhSbFJuSnZiVkJ5YjNCelBUMGlablZ1WTNScGIyNGlmSHgwZVhC'
    || 'bGIyWWdiQzVuWlhSVGJtRndjMmh2ZEVKbFptOXlaVlZ3WkdGMFpUMDlJbVoxYm1OMGFXOXVJbng4ZEhsd1pXOW1JR3d1VlU1VFFVWkZYMk52YlhCdmJtVnVk'
    || 'RmRwYkd4TmIzVnVkQ0U5SW1aMWJtTjBhVzl1SWlZbWRIbHdaVzltSUd3dVkyOXRjRzl1Wlc1MFYybHNiRTF2ZFc1MElUMGlablZ1WTNScGIyNGlmSHdvZEQx'
    || 'c0xuTjBZWFJsTEhSNWNHVnZaaUJzTG1OdmJYQnZibVZ1ZEZkcGJHeE5iM1Z1ZEQwOUltWjFibU4wYVc5dUlpWW1iQzVqYjIxd2IyNWxiblJYYVd4c1RXOTFi'
    || 'blFvS1N4MGVYQmxiMllnYkM1VlRsTkJSa1ZmWTI5dGNHOXVaVzUwVjJsc2JFMXZkVzUwUFQwaVpuVnVZM1JwYjI0aUppWnNMbFZPVTBGR1JWOWpiMjF3YjI1'
    || 'bGJuUlhhV3hzVFc5MWJuUW9LU3gwSVQwOWJDNXpkR0YwWlNZbWFtd3VaVzV4ZFdWMVpWSmxjR3hoWTJWVGRHRjBaU2hzTEd3dWMzUmhkR1VzYm5Wc2JDa3Nl'
    || 'V3dvWlN4dUxHd3NjaWtzYkM1emRHRjBaVDFsTG0xbGJXOXBlbVZrVTNSaGRHVXBMSFI1Y0dWdlppQnNMbU52YlhCdmJtVnVkRVJwWkUxdmRXNTBQVDBpWm5W'
    || 'dVkzUnBiMjRpSmlZb1pTNW1iR0ZuYzN3OU5ERTVORE13T0NsOVpuVnVZM1JwYjI0Z1ZtNG9aU3gwS1h0MGNubDdkbUZ5SUc0OUlpSXNjajEwTzJSdklHNHJQ'
    || 'WEpsS0hJcExISTljaTV5WlhSMWNtNDdkMmhwYkdVb2NpazdkbUZ5SUd3OWJuMWpZWFJqYUNocEtYdHNQV0FLUlhKeWIzSWdaMlZ1WlhKaGRHbHVaeUJ6ZEdG'
    || 'amF6b2dZQ3RwTG0xbGMzTmhaMlVyWUFwZ0sya3VjM1JoWTJ0OWNtVjBkWEp1ZTNaaGJIVmxPbVVzYzI5MWNtTmxPblFzYzNSaFkyczZiQ3hrYVdkbGMzUTZi'
    || 'blZzYkgxOVpuVnVZM1JwYjI0Z2QyOG9aU3gwTEc0cGUzSmxkSFZ5Ym50MllXeDFaVHBsTEhOdmRYSmpaVHB1ZFd4c0xITjBZV05yT200L1AyNTFiR3dzWkds'
    || 'blpYTjBPblEvUDI1MWJHeDlmV1oxYm1OMGFXOXVJR3R2S0dVc2RDbDdkSEo1ZTJOdmJuTnZiR1V1WlhKeWIzSW9kQzUyWVd4MVpTbDlZMkYwWTJnb2JpbDdj'
    || 'MlYwVkdsdFpXOTFkQ2htZFc1amRHbHZiaWdwZTNSb2NtOTNJRzU5S1gxOWRtRnlJSHBtUFhSNWNHVnZaaUJYWldGclRXRndQVDBpWm5WdVkzUnBiMjRpUDFk'
    || 'bFlXdE5ZWEE2VFdGd08yWjFibU4wYVc5dUlIaGhLR1VzZEN4dUtYdHVQVXgwS0MweExHNHBMRzR1ZEdGblBUTXNiaTV3WVhsc2IyRmtQWHRsYkdWdFpXNTBP'
    || 'bTUxYkd4OU8zWmhjaUJ5UFhRdWRtRnNkV1U3Y21WMGRYSnVJRzR1WTJGc2JHSmhZMnM5Wm5WdVkzUnBiMjRvS1h0UWJIeDhLRkJzUFNFd0xFWnZQWElwTEd0'
    || 'dktHVXNkQ2w5TEc1OVpuVnVZM1JwYjI0Z1JXRW9aU3gwTEc0cGUyNDlUSFFvTFRFc2Jpa3NiaTUwWVdjOU16dDJZWElnY2oxbExuUjVjR1V1WjJWMFJHVnlh'
    || 'WFpsWkZOMFlYUmxSbkp2YlVWeWNtOXlPMmxtS0hSNWNHVnZaaUJ5UFQwaVpuVnVZM1JwYjI0aUtYdDJZWElnYkQxMExuWmhiSFZsTzI0dWNHRjViRzloWkQx'
    || 'bWRXNWpkR2x2YmlncGUzSmxkSFZ5YmlCeUtHd3BmU3h1TG1OaGJHeGlZV05yUFdaMWJtTjBhVzl1S0NsN2EyOG9aU3gwS1gxOWRtRnlJR2s5WlM1emRHRjBa'
    || 'VTV2WkdVN2NtVjBkWEp1SUdraFBUMXVkV3hzSmlaMGVYQmxiMllnYVM1amIyMXdiMjVsYm5SRWFXUkRZWFJqYUQwOUltWjFibU4wYVc5dUlpWW1LRzR1WTJG'
    || 'c2JHSmhZMnM5Wm5WdVkzUnBiMjRvS1h0cmJ5aGxMSFFwTEhSNWNHVnZaaUJ5SVQwaVpuVnVZM1JwYjI0aUppWW9jWFE5UFQxdWRXeHNQM0YwUFc1bGR5QlRa'
    || 'WFFvVzNSb2FYTmRLVHB4ZEM1aFpHUW9kR2hwY3lrcE8zWmhjaUJ6UFhRdWMzUmhZMnM3ZEdocGN5NWpiMjF3YjI1bGJuUkVhV1JEWVhSamFDaDBMblpoYkhW'
    || 'bExIdGpiMjF3YjI1bGJuUlRkR0ZqYXpweklUMDliblZzYkQ5ek9pSWlmU2w5S1N4dWZXWjFibU4wYVc5dUlGOWhLR1VzZEN4dUtYdDJZWElnY2oxbExuQnBi'
    || 'bWREWVdOb1pUdHBaaWh5UFQwOWJuVnNiQ2w3Y2oxbExuQnBibWREWVdOb1pUMXVaWGNnZW1ZN2RtRnlJR3c5Ym1WM0lGTmxkRHR5TG5ObGRDaDBMR3dwZldW'
    || 'c2MyVWdiRDF5TG1kbGRDaDBLU3hzUFQwOWRtOXBaQ0F3SmlZb2JEMXVaWGNnVTJWMExISXVjMlYwS0hRc2JDa3BPMnd1YUdGektHNHBmSHdvYkM1aFpHUW9i'
    || 'aWtzWlQxeFppNWlhVzVrS0c1MWJHd3NaU3gwTEc0cExIUXVkR2hsYmlobExHVXBLWDFtZFc1amRHbHZiaUJUWVNobEtYdGtiM3QyWVhJZ2REdHBaaWdvZEQx'
    || 'bExuUmhaejA5UFRFektTWW1LSFE5WlM1dFpXMXZhWHBsWkZOMFlYUmxMSFE5ZENFOVBXNTFiR3cvZEM1a1pXaDVaSEpoZEdWa0lUMDliblZzYkRvaE1Da3Nk'
    || 'Q2x5WlhSMWNtNGdaVHRsUFdVdWNtVjBkWEp1Zlhkb2FXeGxLR1VoUFQxdWRXeHNLVHR5WlhSMWNtNGdiblZzYkgxbWRXNWpkR2x2YmlCM1lTaGxMSFFzYml4'
    || 'eUxHd3BlM0psZEhWeWJpaGxMbTF2WkdVbU1TazlQVDB3UHlobFBUMDlkRDlsTG1ac1lXZHpmRDAyTlRVek5qb29aUzVtYkdGbmMzdzlNVEk0TEc0dVpteGha'
    || 'M044UFRFek1UQTNNaXh1TG1ac1lXZHpKajB0TlRJNE1EVXNiaTUwWVdjOVBUMHhKaVlvYmk1aGJIUmxjbTVoZEdVOVBUMXVkV3hzUDI0dWRHRm5QVEUzT2lo'
    || 'MFBVeDBLQzB4TERFcExIUXVkR0ZuUFRJc1dIUW9iaXgwTERFcEtTa3NiaTVzWVc1bGMzdzlNU2tzWlNrNktHVXVabXhoWjNOOFBUWTFOVE0yTEdVdWJHRnVa'
    || 'WE05YkN4bEtYMTJZWElnVldZOVN5NVNaV0ZqZEVOMWNuSmxiblJQZDI1bGNpeExaVDBoTVR0bWRXNWpkR2x2YmlCQ1pTaGxMSFFzYml4eUtYdDBMbU5vYVd4'
    || 'a1BXVTlQVDF1ZFd4c1AwaDFLSFFzYm5Wc2JDeHVMSElwT25wdUtIUXNaUzVqYUdsc1pDeHVMSElwZldaMWJtTjBhVzl1SUd0aEtHVXNkQ3h1TEhJc2JDbDdi'
    || 'ajF1TG5KbGJtUmxjanQyWVhJZ2FUMTBMbkpsWmp0eVpYUjFjbTRnUm00b2RDeHNLU3h5UFcxdktHVXNkQ3h1TEhJc2FTeHNLU3h1UFhadktDa3NaU0U5UFc1'
    || 'MWJHd21KaUZMWlQ4b2RDNTFjR1JoZEdWUmRXVjFaVDFsTG5Wd1pHRjBaVkYxWlhWbExIUXVabXhoWjNNbVBTMHlNRFV6TEdVdWJHRnVaWE1tUFg1c0xFbDBL'
    || 'R1VzZEN4c0tTazZLSFpsSmladUppWnhhU2gwS1N4MExtWnNZV2R6ZkQweExFSmxLR1VzZEN4eUxHd3BMSFF1WTJocGJHUXBmV1oxYm1OMGFXOXVJR3BoS0dV'
    || 'c2RDeHVMSElzYkNsN2FXWW9aVDA5UFc1MWJHd3BlM1poY2lCcFBXNHVkSGx3WlR0eVpYUjFjbTRnZEhsd1pXOW1JR2s5UFNKbWRXNWpkR2x2YmlJbUppRlpi'
    || 'eWhwS1NZbWFTNWtaV1poZFd4MFVISnZjSE05UFQxMmIybGtJREFtSm00dVkyOXRjR0Z5WlQwOVBXNTFiR3dtSm00dVpHVm1ZWFZzZEZCeWIzQnpQVDA5ZG05'
    || 'cFpDQXdQeWgwTG5SaFp6MHhOU3gwTG5SNWNHVTlhU3hPWVNobExIUXNhU3h5TEd3cEtUb29aVDFWYkNodUxuUjVjR1VzYm5Wc2JDeHlMSFFzZEM1dGIyUmxM'
    || 'R3dwTEdVdWNtVm1QWFF1Y21WbUxHVXVjbVYwZFhKdVBYUXNkQzVqYUdsc1pEMWxLWDFwWmlocFBXVXVZMmhwYkdRc0tHVXViR0Z1WlhNbWJDazlQVDB3S1h0'
    || 'MllYSWdjejFwTG0xbGJXOXBlbVZrVUhKdmNITTdhV1lvYmoxdUxtTnZiWEJoY21Vc2JqMXVJVDA5Ym5Wc2JEOXVPbVJ5TEc0b2N5eHlLU1ltWlM1eVpXWTlQ'
    || 'VDEwTG5KbFppbHlaWFIxY200Z1NYUW9aU3gwTEd3cGZYSmxkSFZ5YmlCMExtWnNZV2R6ZkQweExHVTlkRzRvYVN4eUtTeGxMbkpsWmoxMExuSmxaaXhsTG5K'
    || 'bGRIVnliajEwTEhRdVkyaHBiR1E5WlgxbWRXNWpkR2x2YmlCT1lTaGxMSFFzYml4eUxHd3BlMmxtS0dVaFBUMXVkV3hzS1h0MllYSWdhVDFsTG0xbGJXOXBl'
    || 'bVZrVUhKdmNITTdhV1lvWkhJb2FTeHlLU1ltWlM1eVpXWTlQVDEwTG5KbFppbHBaaWhMWlQwaE1TeDBMbkJsYm1ScGJtZFFjbTl3Y3oxeVBXa3NLR1V1YkdG'
    || 'dVpYTW1iQ2toUFQwd0tTaGxMbVpzWVdkekpqRXpNVEEzTWlraFBUMHdKaVlvUzJVOUlUQXBPMlZzYzJVZ2NtVjBkWEp1SUhRdWJHRnVaWE05WlM1c1lXNWxj'
    || 'eXhKZENobExIUXNiQ2w5Y21WMGRYSnVJR3B2S0dVc2RDeHVMSElzYkNsOVpuVnVZM1JwYjI0Z1EyRW9aU3gwTEc0cGUzWmhjaUJ5UFhRdWNHVnVaR2x1WjFC'
    || 'eWIzQnpMR3c5Y2k1amFHbHNaSEpsYml4cFBXVWhQVDF1ZFd4c1AyVXViV1Z0YjJsNlpXUlRkR0YwWlRwdWRXeHNPMmxtS0hJdWJXOWtaVDA5UFNKb2FXUmta'
    || 'VzRpS1dsbUtDaDBMbTF2WkdVbU1TazlQVDB3S1hRdWJXVnRiMmw2WldSVGRHRjBaVDE3WW1GelpVeGhibVZ6T2pBc1kyRmphR1ZRYjI5c09tNTFiR3dzZEhK'
    || 'aGJuTnBkR2x2Ym5NNmJuVnNiSDBzWm1Vb1NHNHNjblFwTEhKMGZEMXVPMlZzYzJWN2FXWW9LRzRtTVRBM016YzBNVGd5TkNrOVBUMHdLWEpsZEhWeWJpQmxQ'
    || 'V2toUFQxdWRXeHNQMmt1WW1GelpVeGhibVZ6Zkc0NmJpeDBMbXhoYm1WelBYUXVZMmhwYkdSTVlXNWxjejB4TURjek56UXhPREkwTEhRdWJXVnRiMmw2WldS'
    || 'VGRHRjBaVDE3WW1GelpVeGhibVZ6T21Vc1kyRmphR1ZRYjI5c09tNTFiR3dzZEhKaGJuTnBkR2x2Ym5NNmJuVnNiSDBzZEM1MWNHUmhkR1ZSZFdWMVpUMXVk'
    || 'V3hzTEdabEtFaHVMSEowS1N4eWRIdzlaU3h1ZFd4c08zUXViV1Z0YjJsNlpXUlRkR0YwWlQxN1ltRnpaVXhoYm1Wek9qQXNZMkZqYUdWUWIyOXNPbTUxYkd3'
    || 'c2RISmhibk5wZEdsdmJuTTZiblZzYkgwc2NqMXBJVDA5Ym5Wc2JEOXBMbUpoYzJWTVlXNWxjenB1TEdabEtFaHVMSEowS1N4eWRIdzljbjFsYkhObElHa2hQ'
    || 'VDF1ZFd4c1B5aHlQV2t1WW1GelpVeGhibVZ6Zkc0c2RDNXRaVzF2YVhwbFpGTjBZWFJsUFc1MWJHd3BPbkk5Yml4bVpTaEliaXh5ZENrc2NuUjhQWEk3Y21W'
    || 'MGRYSnVJRUpsS0dVc2RDeHNMRzRwTEhRdVkyaHBiR1I5Wm5WdVkzUnBiMjRnVkdFb1pTeDBLWHQyWVhJZ2JqMTBMbkpsWmpzb1pUMDlQVzUxYkd3bUptNGhQ'
    || 'VDF1ZFd4c2ZIeGxJVDA5Ym5Wc2JDWW1aUzV5WldZaFBUMXVLU1ltS0hRdVpteGhaM044UFRVeE1peDBMbVpzWVdkemZEMHlNRGszTVRVeUtYMW1kVzVqZEds'
    || 'dmJpQnFieWhsTEhRc2JpeHlMR3dwZTNaaGNpQnBQVWRsS0c0cFAyRnVPbFZsTG1OMWNuSmxiblE3Y21WMGRYSnVJR2s5VEc0b2RDeHBLU3hHYmloMExHd3BM'
    || 'RzQ5Ylc4b1pTeDBMRzRzY2l4cExHd3BMSEk5ZG04b0tTeGxJVDA5Ym5Wc2JDWW1JVXRsUHloMExuVndaR0YwWlZGMVpYVmxQV1V1ZFhCa1lYUmxVWFZsZFdV'
    || 'c2RDNW1iR0ZuY3lZOUxUSXdOVE1zWlM1c1lXNWxjeVk5Zm13c1NYUW9aU3gwTEd3cEtUb29kbVVtSm5JbUpuRnBLSFFwTEhRdVpteGhaM044UFRFc1FtVW9a'
    || 'U3gwTEc0c2JDa3NkQzVqYUdsc1pDbDlablZ1WTNScGIyNGdVbUVvWlN4MExHNHNjaXhzS1h0cFppaEhaU2h1S1NsN2RtRnlJR2s5SVRBN1lXd29kQ2w5Wld4'
    || 'elpTQnBQU0V4TzJsbUtFWnVLSFFzYkNrc2RDNXpkR0YwWlU1dlpHVTlQVDF1ZFd4c0tVTnNLR1VzZENrc1oyRW9kQ3h1TEhJcExGTnZLSFFzYml4eUxHd3BM'
    || 'SEk5SVRBN1pXeHpaU0JwWmlobFBUMDliblZzYkNsN2RtRnlJSE05ZEM1emRHRjBaVTV2WkdVc1pEMTBMbTFsYlc5cGVtVmtVSEp2Y0hNN2N5NXdjbTl3Y3ox'
    || 'a08zWmhjaUJtUFhNdVkyOXVkR1Y0ZEN4NVBXNHVZMjl1ZEdWNGRGUjVjR1U3ZEhsd1pXOW1JSGs5UFNKdlltcGxZM1FpSmlaNUlUMDliblZzYkQ5NVBYTjBL'
    || 'SGtwT2loNVBVZGxLRzRwUDJGdU9sVmxMbU4xY25KbGJuUXNlVDFNYmloMExIa3BLVHQyWVhJZ2F6MXVMbWRsZEVSbGNtbDJaV1JUZEdGMFpVWnliMjFRY205'
    || 'd2N5eE9QWFI1Y0dWdlppQnJQVDBpWm5WdVkzUnBiMjRpZkh4MGVYQmxiMllnY3k1blpYUlRibUZ3YzJodmRFSmxabTl5WlZWd1pHRjBaVDA5SW1aMWJtTjBh'
    || 'Vzl1SWp0T2ZIeDBlWEJsYjJZZ2N5NVZUbE5CUmtWZlkyOXRjRzl1Wlc1MFYybHNiRkpsWTJWcGRtVlFjbTl3Y3lFOUltWjFibU4wYVc5dUlpWW1kSGx3Wlc5'
    || 'bUlITXVZMjl0Y0c5dVpXNTBWMmxzYkZKbFkyVnBkbVZRY205d2N5RTlJbVoxYm1OMGFXOXVJbng4S0dRaFBUMXlmSHhtSVQwOWVTa21KbmxoS0hRc2N5eHlM'
    || 'SGtwTEV0MFBTRXhPM1poY2lCZlBYUXViV1Z0YjJsNlpXUlRkR0YwWlR0ekxuTjBZWFJsUFY4c2VXd29kQ3h5TEhNc2JDa3NaajEwTG0xbGJXOXBlbVZrVTNS'
    || 'aGRHVXNaQ0U5UFhKOGZGOGhQVDFtZkh4WlpTNWpkWEp5Wlc1MGZIeExkRDhvZEhsd1pXOW1JR3M5UFNKbWRXNWpkR2x2YmlJbUppaGZieWgwTEc0c2F5eHlL'
    || 'U3htUFhRdWJXVnRiMmw2WldSVGRHRjBaU2tzS0dROVMzUjhmSFpoS0hRc2JpeGtMSElzWHl4bUxIa3BLVDhvVG54OGRIbHdaVzltSUhNdVZVNVRRVVpGWDJO'
    || 'dmJYQnZibVZ1ZEZkcGJHeE5iM1Z1ZENFOUltWjFibU4wYVc5dUlpWW1kSGx3Wlc5bUlITXVZMjl0Y0c5dVpXNTBWMmxzYkUxdmRXNTBJVDBpWm5WdVkzUnBi'
    || 'MjRpZkh3b2RIbHdaVzltSUhNdVkyOXRjRzl1Wlc1MFYybHNiRTF2ZFc1MFBUMGlablZ1WTNScGIyNGlKaVp6TG1OdmJYQnZibVZ1ZEZkcGJHeE5iM1Z1ZENn'
    || 'cExIUjVjR1Z2WmlCekxsVk9VMEZHUlY5amIyMXdiMjVsYm5SWGFXeHNUVzkxYm5ROVBTSm1kVzVqZEdsdmJpSW1Kbk11VlU1VFFVWkZYMk52YlhCdmJtVnVk'
    || 'RmRwYkd4TmIzVnVkQ2dwS1N4MGVYQmxiMllnY3k1amIyMXdiMjVsYm5SRWFXUk5iM1Z1ZEQwOUltWjFibU4wYVc5dUlpWW1LSFF1Wm14aFozTjhQVFF4T1RR'
    || 'ek1EZ3BLVG9vZEhsd1pXOW1JSE11WTI5dGNHOXVaVzUwUkdsa1RXOTFiblE5UFNKbWRXNWpkR2x2YmlJbUppaDBMbVpzWVdkemZEMDBNVGswTXpBNEtTeDBM'
    || 'bTFsYlc5cGVtVmtVSEp2Y0hNOWNpeDBMbTFsYlc5cGVtVmtVM1JoZEdVOVppa3NjeTV3Y205d2N6MXlMSE11YzNSaGRHVTlaaXh6TG1OdmJuUmxlSFE5ZVN4'
    || 'eVBXUXBPaWgwZVhCbGIyWWdjeTVqYjIxd2IyNWxiblJFYVdSTmIzVnVkRDA5SW1aMWJtTjBhVzl1SWlZbUtIUXVabXhoWjNOOFBUUXhPVFF6TURncExISTlJ'
    || 'VEVwZldWc2MyVjdjejEwTG5OMFlYUmxUbTlrWlN4UmRTaGxMSFFwTEdROWRDNXRaVzF2YVhwbFpGQnliM0J6TEhrOWRDNTBlWEJsUFQwOWRDNWxiR1Z0Wlc1'
    || 'MFZIbHdaVDlrT25aMEtIUXVkSGx3WlN4a0tTeHpMbkJ5YjNCelBYa3NUajEwTG5CbGJtUnBibWRRY205d2N5eGZQWE11WTI5dWRHVjRkQ3htUFc0dVkyOXVk'
    || 'R1Y0ZEZSNWNHVXNkSGx3Wlc5bUlHWTlQU0p2WW1wbFkzUWlKaVptSVQwOWJuVnNiRDltUFhOMEtHWXBPaWhtUFVkbEtHNHBQMkZ1T2xWbExtTjFjbkpsYm5R'
    || 'c1pqMU1iaWgwTEdZcEtUdDJZWElnVHoxdUxtZGxkRVJsY21sMlpXUlRkR0YwWlVaeWIyMVFjbTl3Y3pzb2F6MTBlWEJsYjJZZ1R6MDlJbVoxYm1OMGFXOXVJ'
    || 'bng4ZEhsd1pXOW1JSE11WjJWMFUyNWhjSE5vYjNSQ1pXWnZjbVZWY0dSaGRHVTlQU0ptZFc1amRHbHZiaUlwZkh4MGVYQmxiMllnY3k1VlRsTkJSa1ZmWTI5'
    || 'dGNHOXVaVzUwVjJsc2JGSmxZMlZwZG1WUWNtOXdjeUU5SW1aMWJtTjBhVzl1SWlZbWRIbHdaVzltSUhNdVkyOXRjRzl1Wlc1MFYybHNiRkpsWTJWcGRtVlFj'
    || 'bTl3Y3lFOUltWjFibU4wYVc5dUlueDhLR1FoUFQxT2ZIeGZJVDA5WmlrbUpubGhLSFFzY3l4eUxHWXBMRXQwUFNFeExGODlkQzV0WlcxdmFYcGxaRk4wWVhS'
    || 'bExITXVjM1JoZEdVOVh5eDViQ2gwTEhJc2N5eHNLVHQyWVhJZ1NUMTBMbTFsYlc5cGVtVmtVM1JoZEdVN1pDRTlQVTU4ZkY4aFBUMUpmSHhaWlM1amRYSnla'
    || 'VzUwZkh4TGREOG9kSGx3Wlc5bUlFODlQU0ptZFc1amRHbHZiaUltSmloZmJ5aDBMRzRzVHl4eUtTeEpQWFF1YldWdGIybDZaV1JUZEdGMFpTa3NLSGs5UzNS'
    || 'OGZIWmhLSFFzYml4NUxISXNYeXhKTEdZcGZId2hNU2svS0d0OGZIUjVjR1Z2WmlCekxsVk9VMEZHUlY5amIyMXdiMjVsYm5SWGFXeHNWWEJrWVhSbElUMGla'
    || 'blZ1WTNScGIyNGlKaVowZVhCbGIyWWdjeTVqYjIxd2IyNWxiblJYYVd4c1ZYQmtZWFJsSVQwaVpuVnVZM1JwYjI0aWZId29kSGx3Wlc5bUlITXVZMjl0Y0c5'
    || 'dVpXNTBWMmxzYkZWd1pHRjBaVDA5SW1aMWJtTjBhVzl1SWlZbWN5NWpiMjF3YjI1bGJuUlhhV3hzVlhCa1lYUmxLSElzU1N4bUtTeDBlWEJsYjJZZ2N5NVZU'
    || 'bE5CUmtWZlkyOXRjRzl1Wlc1MFYybHNiRlZ3WkdGMFpUMDlJbVoxYm1OMGFXOXVJaVltY3k1VlRsTkJSa1ZmWTI5dGNHOXVaVzUwVjJsc2JGVndaR0YwWlNo'
    || 'eUxFa3NaaWtwTEhSNWNHVnZaaUJ6TG1OdmJYQnZibVZ1ZEVScFpGVndaR0YwWlQwOUltWjFibU4wYVc5dUlpWW1LSFF1Wm14aFozTjhQVFFwTEhSNWNHVnZa'
    || 'aUJ6TG1kbGRGTnVZWEJ6YUc5MFFtVm1iM0psVlhCa1lYUmxQVDBpWm5WdVkzUnBiMjRpSmlZb2RDNW1iR0ZuYzN3OU1UQXlOQ2twT2loMGVYQmxiMllnY3k1'
    || 'amIyMXdiMjVsYm5SRWFXUlZjR1JoZEdVaFBTSm1kVzVqZEdsdmJpSjhmR1E5UFQxbExtMWxiVzlwZW1Wa1VISnZjSE1tSmw4OVBUMWxMbTFsYlc5cGVtVmtV'
    || 'M1JoZEdWOGZDaDBMbVpzWVdkemZEMDBLU3gwZVhCbGIyWWdjeTVuWlhSVGJtRndjMmh2ZEVKbFptOXlaVlZ3WkdGMFpTRTlJbVoxYm1OMGFXOXVJbng4WkQw'
    || 'OVBXVXViV1Z0YjJsNlpXUlFjbTl3Y3lZbVh6MDlQV1V1YldWdGIybDZaV1JUZEdGMFpYeDhLSFF1Wm14aFozTjhQVEV3TWpRcExIUXViV1Z0YjJsNlpXUlFj'
    || 'bTl3Y3oxeUxIUXViV1Z0YjJsNlpXUlRkR0YwWlQxSktTeHpMbkJ5YjNCelBYSXNjeTV6ZEdGMFpUMUpMSE11WTI5dWRHVjRkRDFtTEhJOWVTazZLSFI1Y0dW'
    || 'dlppQnpMbU52YlhCdmJtVnVkRVJwWkZWd1pHRjBaU0U5SW1aMWJtTjBhVzl1SW54OFpEMDlQV1V1YldWdGIybDZaV1JRY205d2N5WW1YejA5UFdVdWJXVnRi'
    || 'Mmw2WldSVGRHRjBaWHg4S0hRdVpteGhaM044UFRRcExIUjVjR1Z2WmlCekxtZGxkRk51WVhCemFHOTBRbVZtYjNKbFZYQmtZWFJsSVQwaVpuVnVZM1JwYjI0'
    || 'aWZIeGtQVDA5WlM1dFpXMXZhWHBsWkZCeWIzQnpKaVpmUFQwOVpTNXRaVzF2YVhwbFpGTjBZWFJsZkh3b2RDNW1iR0ZuYzN3OU1UQXlOQ2tzY2owaE1TbDlj'
    || 'bVYwZFhKdUlFNXZLR1VzZEN4dUxISXNhU3hzS1gxbWRXNWpkR2x2YmlCT2J5aGxMSFFzYml4eUxHd3NhU2w3VkdFb1pTeDBLVHQyWVhJZ2N6MG9kQzVtYkdG'
    || 'bmN5WXhNamdwSVQwOU1EdHBaaWdoY2lZbUlYTXBjbVYwZFhKdUlHd21Ka2wxS0hRc2Jpd2hNU2tzU1hRb1pTeDBMR2twTzNJOWRDNXpkR0YwWlU1dlpHVXNW'
    || 'V1l1WTNWeWNtVnVkRDEwTzNaaGNpQmtQWE1tSm5SNWNHVnZaaUJ1TG1kbGRFUmxjbWwyWldSVGRHRjBaVVp5YjIxRmNuSnZjaUU5SW1aMWJtTjBhVzl1SWo5'
    || 'dWRXeHNPbkl1Y21WdVpHVnlLQ2s3Y21WMGRYSnVJSFF1Wm14aFozTjhQVEVzWlNFOVBXNTFiR3dtSm5NL0tIUXVZMmhwYkdROWVtNG9kQ3hsTG1Ob2FXeGtM'
    || 'RzUxYkd3c2FTa3NkQzVqYUdsc1pEMTZiaWgwTEc1MWJHd3NaQ3hwS1NrNlFtVW9aU3gwTEdRc2FTa3NkQzV0WlcxdmFYcGxaRk4wWVhSbFBYSXVjM1JoZEdV'
    || 'c2JDWW1TWFVvZEN4dUxDRXdLU3gwTG1Ob2FXeGtmV1oxYm1OMGFXOXVJRVJoS0dVcGUzWmhjaUIwUFdVdWMzUmhkR1ZPYjJSbE8zUXVjR1Z1WkdsdVowTnZi'
    || 'blJsZUhRL1VIVW9aU3gwTG5CbGJtUnBibWREYjI1MFpYaDBMSFF1Y0dWdVpHbHVaME52Ym5SbGVIUWhQVDEwTG1OdmJuUmxlSFFwT25RdVkyOXVkR1Y0ZENZ'
    || 'bVVIVW9aU3gwTG1OdmJuUmxlSFFzSVRFcExIVnZLR1VzZEM1amIyNTBZV2x1WlhKSmJtWnZLWDFtZFc1amRHbHZiaUJQWVNobExIUXNiaXh5TEd3cGUzSmxk'
    || 'SFZ5YmlCTmJpZ3BMSFJ2S0d3cExIUXVabXhoWjNOOFBUSTFOaXhDWlNobExIUXNiaXh5S1N4MExtTm9hV3hrZlhaaGNpQkRiejE3WkdWb2VXUnlZWFJsWkRw'
    || 'dWRXeHNMSFJ5WldWRGIyNTBaWGgwT201MWJHd3NjbVYwY25sTVlXNWxPakI5TzJaMWJtTjBhVzl1SUZSdktHVXBlM0psZEhWeWJudGlZWE5sVEdGdVpYTTZa'
    || 'U3hqWVdOb1pWQnZiMnc2Ym5Wc2JDeDBjbUZ1YzJsMGFXOXVjenB1ZFd4c2ZYMW1kVzVqZEdsdmJpQlFZU2hsTEhRc2JpbDdkbUZ5SUhJOWRDNXdaVzVrYVc1'
    || 'blVISnZjSE1zYkQxNVpTNWpkWEp5Wlc1MExHazlJVEVzY3owb2RDNW1iR0ZuY3lZeE1qZ3BJVDA5TUN4a08ybG1LQ2hrUFhNcGZId29aRDFsSVQwOWJuVnNi'
    || 'Q1ltWlM1dFpXMXZhWHBsWkZOMFlYUmxQVDA5Ym5Wc2JEOGhNVG9vYkNZeUtTRTlQVEFwTEdRL0tHazlJVEFzZEM1bWJHRm5jeVk5TFRFeU9TazZLR1U5UFQx'
    || 'dWRXeHNmSHhsTG0xbGJXOXBlbVZrVTNSaGRHVWhQVDF1ZFd4c0tTWW1LR3g4UFRFcExHWmxLSGxsTEd3bU1Ta3NaVDA5UFc1MWJHd3BjbVYwZFhKdUlHVnZL'
    || 'SFFwTEdVOWRDNXRaVzF2YVhwbFpGTjBZWFJsTEdVaFBUMXVkV3hzSmlZb1pUMWxMbVJsYUhsa2NtRjBaV1FzWlNFOVBXNTFiR3dwUHlnb2RDNXRiMlJsSmpF'
    || 'cFBUMDlNRDkwTG14aGJtVnpQVEU2WlM1a1lYUmhQVDA5SWlRaElqOTBMbXhoYm1WelBUZzZkQzVzWVc1bGN6MHhNRGN6TnpReE9ESTBMRzUxYkd3cE9paHpQ'
    || 'WEl1WTJocGJHUnlaVzRzWlQxeUxtWmhiR3hpWVdOckxHay9LSEk5ZEM1dGIyUmxMR2s5ZEM1amFHbHNaQ3h6UFh0dGIyUmxPaUpvYVdSa1pXNGlMR05vYVd4'
    || 'a2NtVnVPbk45TENoeUpqRXBQVDA5TUNZbWFTRTlQVzUxYkd3L0tHa3VZMmhwYkdSTVlXNWxjejB3TEdrdWNHVnVaR2x1WjFCeWIzQnpQWE1wT21rOVJtd29j'
    || 'eXh5TERBc2JuVnNiQ2tzWlQxNGJpaGxMSElzYml4dWRXeHNLU3hwTG5KbGRIVnliajEwTEdVdWNtVjBkWEp1UFhRc2FTNXphV0pzYVc1blBXVXNkQzVqYUds'
    || 'c1pEMXBMSFF1WTJocGJHUXViV1Z0YjJsNlpXUlRkR0YwWlQxVWJ5aHVLU3gwTG0xbGJXOXBlbVZrVTNSaGRHVTlRMjhzWlNrNlVtOG9kQ3h6S1NrN2FXWW9i'
    || 'RDFsTG0xbGJXOXBlbVZrVTNSaGRHVXNiQ0U5UFc1MWJHd21KaWhrUFd3dVpHVm9lV1J5WVhSbFpDeGtJVDA5Ym5Wc2JDa3BjbVYwZFhKdUlFWm1LR1VzZEN4'
    || 'ekxISXNaQ3hzTEc0cE8ybG1LR2twZTJrOWNpNW1ZV3hzWW1GamF5eHpQWFF1Ylc5a1pTeHNQV1V1WTJocGJHUXNaRDFzTG5OcFlteHBibWM3ZG1GeUlHWTll'
    || 'MjF2WkdVNkltaHBaR1JsYmlJc1kyaHBiR1J5Wlc0NmNpNWphR2xzWkhKbGJuMDdjbVYwZFhKdUtITW1NU2s5UFQwd0ppWjBMbU5vYVd4a0lUMDliRDhvY2ox'
    || 'MExtTm9hV3hrTEhJdVkyaHBiR1JNWVc1bGN6MHdMSEl1Y0dWdVpHbHVaMUJ5YjNCelBXWXNkQzVrWld4bGRHbHZibk05Ym5Wc2JDazZLSEk5ZEc0b2JDeG1L'
    || 'U3h5TG5OMVluUnlaV1ZHYkdGbmN6MXNMbk4xWW5SeVpXVkdiR0ZuY3lZeE5EWTRNREEyTkNrc1pDRTlQVzUxYkd3L2FUMTBiaWhrTEdrcE9paHBQWGh1S0dr'
    || 'c2N5eHVMRzUxYkd3cExHa3VabXhoWjNOOFBUSXBMR2t1Y21WMGRYSnVQWFFzY2k1eVpYUjFjbTQ5ZEN4eUxuTnBZbXhwYm1jOWFTeDBMbU5vYVd4a1BYSXNj'
    || 'ajFwTEdrOWRDNWphR2xzWkN4elBXVXVZMmhwYkdRdWJXVnRiMmw2WldSVGRHRjBaU3h6UFhNOVBUMXVkV3hzUDFSdktHNHBPbnRpWVhObFRHRnVaWE02Y3k1'
    || 'aVlYTmxUR0Z1WlhOOGJpeGpZV05vWlZCdmIydzZiblZzYkN4MGNtRnVjMmwwYVc5dWN6cHpMblJ5WVc1emFYUnBiMjV6ZlN4cExtMWxiVzlwZW1Wa1UzUmhk'
    || 'R1U5Y3l4cExtTm9hV3hrVEdGdVpYTTlaUzVqYUdsc1pFeGhibVZ6Sm41dUxIUXViV1Z0YjJsNlpXUlRkR0YwWlQxRGJ5eHlmWEpsZEhWeWJpQnBQV1V1WTJo'
    || 'cGJHUXNaVDFwTG5OcFlteHBibWNzY2oxMGJpaHBMSHR0YjJSbE9pSjJhWE5wWW14bElpeGphR2xzWkhKbGJqcHlMbU5vYVd4a2NtVnVmU2tzS0hRdWJXOWta'
    || 'U1l4S1QwOVBUQW1KaWh5TG14aGJtVnpQVzRwTEhJdWNtVjBkWEp1UFhRc2NpNXphV0pzYVc1blBXNTFiR3dzWlNFOVBXNTFiR3dtSmlodVBYUXVaR1ZzWlhS'
    || 'cGIyNXpMRzQ5UFQxdWRXeHNQeWgwTG1SbGJHVjBhVzl1Y3oxYlpWMHNkQzVtYkdGbmMzdzlNVFlwT200dWNIVnphQ2hsS1Nrc2RDNWphR2xzWkQxeUxIUXVi'
    || 'V1Z0YjJsNlpXUlRkR0YwWlQxdWRXeHNMSEo5Wm5WdVkzUnBiMjRnVW04b1pTeDBLWHR5WlhSMWNtNGdkRDFHYkNoN2JXOWtaVG9pZG1semFXSnNaU0lzWTJo'
    || 'cGJHUnlaVzQ2ZEgwc1pTNXRiMlJsTERBc2JuVnNiQ2tzZEM1eVpYUjFjbTQ5WlN4bExtTm9hV3hrUFhSOVpuVnVZM1JwYjI0Z1Rtd29aU3gwTEc0c2NpbDdj'
    || 'bVYwZFhKdUlISWhQVDF1ZFd4c0ppWjBieWh5S1N4NmJpaDBMR1V1WTJocGJHUXNiblZzYkN4dUtTeGxQVkp2S0hRc2RDNXdaVzVrYVc1blVISnZjSE11WTJo'
    || 'cGJHUnlaVzRwTEdVdVpteGhaM044UFRJc2RDNXRaVzF2YVhwbFpGTjBZWFJsUFc1MWJHd3NaWDFtZFc1amRHbHZiaUJHWmlobExIUXNiaXh5TEd3c2FTeHpL'
    || 'WHRwWmlodUtYSmxkSFZ5YmlCMExtWnNZV2R6SmpJMU5qOG9kQzVtYkdGbmN5WTlMVEkxTnl4eVBYZHZLRVZ5Y205eUtHRW9OREl5S1NrcExFNXNLR1VzZEN4'
    || 'ekxISXBLVHAwTG0xbGJXOXBlbVZrVTNSaGRHVWhQVDF1ZFd4c1B5aDBMbU5vYVd4a1BXVXVZMmhwYkdRc2RDNW1iR0ZuYzN3OU1USTRMRzUxYkd3cE9paHBQ'
    || 'WEl1Wm1Gc2JHSmhZMnNzYkQxMExtMXZaR1VzY2oxR2JDaDdiVzlrWlRvaWRtbHphV0pzWlNJc1kyaHBiR1J5Wlc0NmNpNWphR2xzWkhKbGJuMHNiQ3d3TEc1'
    || 'MWJHd3BMR2s5ZUc0b2FTeHNMSE1zYm5Wc2JDa3NhUzVtYkdGbmMzdzlNaXh5TG5KbGRIVnliajEwTEdrdWNtVjBkWEp1UFhRc2NpNXphV0pzYVc1blBXa3Nk'
    || 'QzVqYUdsc1pEMXlMQ2gwTG0xdlpHVW1NU2toUFQwd0ppWjZiaWgwTEdVdVkyaHBiR1FzYm5Wc2JDeHpLU3gwTG1Ob2FXeGtMbTFsYlc5cGVtVmtVM1JoZEdV'
    || 'OVZHOG9jeWtzZEM1dFpXMXZhWHBsWkZOMFlYUmxQVU52TEdrcE8ybG1LQ2gwTG0xdlpHVW1NU2s5UFQwd0tYSmxkSFZ5YmlCT2JDaGxMSFFzY3l4dWRXeHNL'
    || 'VHRwWmloc0xtUmhkR0U5UFQwaUpDRWlLWHRwWmloeVBXd3VibVY0ZEZOcFlteHBibWNtSm13dWJtVjRkRk5wWW14cGJtY3VaR0YwWVhObGRDeHlLWFpoY2lC'
    || 'a1BYSXVaR2R6ZER0eVpYUjFjbTRnY2oxa0xHazlSWEp5YjNJb1lTZzBNVGtwS1N4eVBYZHZLR2tzY2l4MmIybGtJREFwTEU1c0tHVXNkQ3h6TEhJcGZXbG1L'
    || 'R1E5S0hNbVpTNWphR2xzWkV4aGJtVnpLU0U5UFRBc1MyVjhmR1FwZTJsbUtISTlUMlVzY2lFOVBXNTFiR3dwZTNOM2FYUmphQ2h6SmkxektYdGpZWE5sSURR'
    || 'NmJEMHlPMkp5WldGck8yTmhjMlVnTVRZNmJEMDRPMkp5WldGck8yTmhjMlVnTmpRNlkyRnpaU0F4TWpnNlkyRnpaU0F5TlRZNlkyRnpaU0ExTVRJNlkyRnpa'
    || 'U0F4TURJME9tTmhjMlVnTWpBME9EcGpZWE5sSURRd09UWTZZMkZ6WlNBNE1Ua3lPbU5oYzJVZ01UWXpPRFE2WTJGelpTQXpNamMyT0RwallYTmxJRFkxTlRN'
    || 'Mk9tTmhjMlVnTVRNeE1EY3lPbU5oYzJVZ01qWXlNVFEwT21OaGMyVWdOVEkwTWpnNE9tTmhjMlVnTVRBME9EVTNOanBqWVhObElESXdPVGN4TlRJNlkyRnpa'
    || 'U0EwTVRrME16QTBPbU5oYzJVZ09ETTRPRFl3T0RwallYTmxJREUyTnpjM01qRTJPbU5oYzJVZ016TTFOVFEwTXpJNlkyRnpaU0EyTnpFd09EZzJORHBzUFRN'
    || 'eU8ySnlaV0ZyTzJOaGMyVWdOVE0yT0Rjd09URXlPbXc5TWpZNE5ETTFORFUyTzJKeVpXRnJPMlJsWm1GMWJIUTZiRDB3Zld3OUtHd21LSEl1YzNWemNHVnVa'
    || 'R1ZrVEdGdVpYTjhjeWtwSVQwOU1EOHdPbXdzYkNFOVBUQW1KbXdoUFQxcExuSmxkSEo1VEdGdVpTWW1LR2t1Y21WMGNubE1ZVzVsUFd3c1VIUW9aU3hzS1N4'
    || 'NGRDaHlMR1VzYkN3dE1Ta3BmWEpsZEhWeWJpQlJieWdwTEhJOWQyOG9SWEp5YjNJb1lTZzBNakVwS1Nrc1Rtd29aU3gwTEhNc2NpbDljbVYwZFhKdUlHd3Va'
    || 'R0YwWVQwOVBTSWtQeUkvS0hRdVpteGhaM044UFRFeU9DeDBMbU5vYVd4a1BXVXVZMmhwYkdRc2REMUtaaTVpYVc1a0tHNTFiR3dzWlNrc2JDNWZjbVZoWTNS'
    || 'U1pYUnllVDEwTEc1MWJHd3BPaWhsUFdrdWRISmxaVU52Ym5SbGVIUXNiblE5SkhRb2JDNXVaWGgwVTJsaWJHbHVaeWtzZEhROWRDeDJaVDBoTUN4dGREMXVk'
    || 'V3hzTEdVaFBUMXVkV3hzSmlZb2FYUmJiM1FySzEwOVJIUXNhWFJiYjNRcksxMDlUM1FzYVhSYmIzUXJLMTA5WTI0c1JIUTlaUzVwWkN4UGREMWxMbTkyWlhK'
    || 'bWJHOTNMR051UFhRcExIUTlVbThvZEN4eUxtTm9hV3hrY21WdUtTeDBMbVpzWVdkemZEMDBNRGsyTEhRcGZXWjFibU4wYVc5dUlFeGhLR1VzZEN4dUtYdGxM'
    || 'bXhoYm1WemZEMTBPM1poY2lCeVBXVXVZV3gwWlhKdVlYUmxPM0loUFQxdWRXeHNKaVlvY2k1c1lXNWxjM3c5ZENrc2FXOG9aUzV5WlhSMWNtNHNkQ3h1S1gx'
    || 'bWRXNWpkR2x2YmlCRWJ5aGxMSFFzYml4eUxHd3BlM1poY2lCcFBXVXViV1Z0YjJsNlpXUlRkR0YwWlR0cFBUMDliblZzYkQ5bExtMWxiVzlwZW1Wa1UzUmhk'
    || 'R1U5ZTJselFtRmphM2RoY21Sek9uUXNjbVZ1WkdWeWFXNW5PbTUxYkd3c2NtVnVaR1Z5YVc1blUzUmhjblJVYVcxbE9qQXNiR0Z6ZERweUxIUmhhV3c2Yml4'
    || 'MFlXbHNUVzlrWlRwc2ZUb29hUzVwYzBKaFkydDNZWEprY3oxMExHa3VjbVZ1WkdWeWFXNW5QVzUxYkd3c2FTNXlaVzVrWlhKcGJtZFRkR0Z5ZEZScGJXVTlN'
    || 'Q3hwTG14aGMzUTljaXhwTG5SaGFXdzliaXhwTG5SaGFXeE5iMlJsUFd3cGZXWjFibU4wYVc5dUlFbGhLR1VzZEN4dUtYdDJZWElnY2oxMExuQmxibVJwYm1k'
    || 'UWNtOXdjeXhzUFhJdWNtVjJaV0ZzVDNKa1pYSXNhVDF5TG5SaGFXdzdhV1lvUW1Vb1pTeDBMSEl1WTJocGJHUnlaVzRzYmlrc2NqMTVaUzVqZFhKeVpXNTBM'
    || 'Q2h5SmpJcElUMDlNQ2x5UFhJbU1Yd3lMSFF1Wm14aFozTjhQVEV5T0R0bGJITmxlMmxtS0dVaFBUMXVkV3hzSmlZb1pTNW1iR0ZuY3lZeE1qZ3BJVDA5TUNs'
    || 'bE9tWnZjaWhsUFhRdVkyaHBiR1E3WlNFOVBXNTFiR3c3S1h0cFppaGxMblJoWnowOVBURXpLV1V1YldWdGIybDZaV1JUZEdGMFpTRTlQVzUxYkd3bUpreGhL'
    || 'R1VzYml4MEtUdGxiSE5sSUdsbUtHVXVkR0ZuUFQwOU1Ua3BUR0VvWlN4dUxIUXBPMlZzYzJVZ2FXWW9aUzVqYUdsc1pDRTlQVzUxYkd3cGUyVXVZMmhwYkdR'
    || 'dWNtVjBkWEp1UFdVc1pUMWxMbU5vYVd4a08yTnZiblJwYm5WbGZXbG1LR1U5UFQxMEtXSnlaV0ZySUdVN1ptOXlLRHRsTG5OcFlteHBibWM5UFQxdWRXeHNP'
    || 'eWw3YVdZb1pTNXlaWFIxY200OVBUMXVkV3hzZkh4bExuSmxkSFZ5YmowOVBYUXBZbkpsWVdzZ1pUdGxQV1V1Y21WMGRYSnVmV1V1YzJsaWJHbHVaeTV5WlhS'
    || 'MWNtNDlaUzV5WlhSMWNtNHNaVDFsTG5OcFlteHBibWQ5Y2lZOU1YMXBaaWhtWlNoNVpTeHlLU3dvZEM1dGIyUmxKakVwUFQwOU1DbDBMbTFsYlc5cGVtVmtV'
    || 'M1JoZEdVOWJuVnNiRHRsYkhObElITjNhWFJqYUNoc0tYdGpZWE5sSW1admNuZGhjbVJ6SWpwbWIzSW9iajEwTG1Ob2FXeGtMR3c5Ym5Wc2JEdHVJVDA5Ym5W'
    || 'c2JEc3BaVDF1TG1Gc2RHVnlibUYwWlN4bElUMDliblZzYkNZbWVHd29aU2s5UFQxdWRXeHNKaVlvYkQxdUtTeHVQVzR1YzJsaWJHbHVaenR1UFd3c2JqMDlQ'
    || 'VzUxYkd3L0tHdzlkQzVqYUdsc1pDeDBMbU5vYVd4a1BXNTFiR3dwT2loc1BXNHVjMmxpYkdsdVp5eHVMbk5wWW14cGJtYzliblZzYkNrc1JHOG9kQ3doTVN4'
    || 'c0xHNHNhU2s3WW5KbFlXczdZMkZ6WlNKaVlXTnJkMkZ5WkhNaU9tWnZjaWh1UFc1MWJHd3NiRDEwTG1Ob2FXeGtMSFF1WTJocGJHUTliblZzYkR0c0lUMDli'
    || 'blZzYkRzcGUybG1LR1U5YkM1aGJIUmxjbTVoZEdVc1pTRTlQVzUxYkd3bUpuaHNLR1VwUFQwOWJuVnNiQ2w3ZEM1amFHbHNaRDFzTzJKeVpXRnJmV1U5YkM1'
    || 'emFXSnNhVzVuTEd3dWMybGliR2x1WnoxdUxHNDliQ3hzUFdWOVJHOG9kQ3doTUN4dUxHNTFiR3dzYVNrN1luSmxZV3M3WTJGelpTSjBiMmRsZEdobGNpSTZS'
    || 'RzhvZEN3aE1TeHVkV3hzTEc1MWJHd3NkbTlwWkNBd0tUdGljbVZoYXp0a1pXWmhkV3gwT25RdWJXVnRiMmw2WldSVGRHRjBaVDF1ZFd4c2ZYSmxkSFZ5YmlC'
    || 'MExtTm9hV3hrZldaMWJtTjBhVzl1SUVOc0tHVXNkQ2w3S0hRdWJXOWtaU1l4S1QwOVBUQW1KbVVoUFQxdWRXeHNKaVlvWlM1aGJIUmxjbTVoZEdVOWJuVnNi'
    || 'Q3gwTG1Gc2RHVnlibUYwWlQxdWRXeHNMSFF1Wm14aFozTjhQVElwZldaMWJtTjBhVzl1SUVsMEtHVXNkQ3h1S1h0cFppaGxJVDA5Ym5Wc2JDWW1LSFF1WkdW'
    || 'd1pXNWtaVzVqYVdWelBXVXVaR1Z3Wlc1a1pXNWphV1Z6S1N4dGJudzlkQzVzWVc1bGN5d29iaVowTG1Ob2FXeGtUR0Z1WlhNcFBUMDlNQ2x5WlhSMWNtNGdi'
    || 'blZzYkR0cFppaGxJVDA5Ym5Wc2JDWW1kQzVqYUdsc1pDRTlQV1V1WTJocGJHUXBkR2h5YjNjZ1JYSnliM0lvWVNneE5UTXBLVHRwWmloMExtTm9hV3hrSVQw'
    || 'OWJuVnNiQ2w3Wm05eUtHVTlkQzVqYUdsc1pDeHVQWFJ1S0dVc1pTNXdaVzVrYVc1blVISnZjSE1wTEhRdVkyaHBiR1E5Yml4dUxuSmxkSFZ5YmoxME8yVXVj'
    || 'MmxpYkdsdVp5RTlQVzUxYkd3N0tXVTlaUzV6YVdKc2FXNW5MRzQ5Ymk1emFXSnNhVzVuUFhSdUtHVXNaUzV3Wlc1a2FXNW5VSEp2Y0hNcExHNHVjbVYwZFhK'
    || 'dVBYUTdiaTV6YVdKc2FXNW5QVzUxYkd4OWNtVjBkWEp1SUhRdVkyaHBiR1I5Wm5WdVkzUnBiMjRnVjJZb1pTeDBMRzRwZTNOM2FYUmphQ2gwTG5SaFp5bDdZ'
    || 'MkZ6WlNBek9rUmhLSFFwTEUxdUtDazdZbkpsWVdzN1kyRnpaU0ExT2t0MUtIUXBPMkp5WldGck8yTmhjMlVnTVRwSFpTaDBMblI1Y0dVcEppWmhiQ2gwS1R0'
    || 'aWNtVmhhenRqWVhObElEUTZkVzhvZEN4MExuTjBZWFJsVG05a1pTNWpiMjUwWVdsdVpYSkpibVp2S1R0aWNtVmhhenRqWVhObElERXdPblpoY2lCeVBYUXVk'
    || 'SGx3WlM1ZlkyOXVkR1Y0ZEN4c1BYUXViV1Z0YjJsNlpXUlFjbTl3Y3k1MllXeDFaVHRtWlNodGJDeHlMbDlqZFhKeVpXNTBWbUZzZFdVcExISXVYMk4xY25K'
    || 'bGJuUldZV3gxWlQxc08ySnlaV0ZyTzJOaGMyVWdNVE02YVdZb2NqMTBMbTFsYlc5cGVtVmtVM1JoZEdVc2NpRTlQVzUxYkd3cGNtVjBkWEp1SUhJdVpHVm9l'
    || 'V1J5WVhSbFpDRTlQVzUxYkd3L0tHWmxLSGxsTEhsbExtTjFjbkpsYm5RbU1Ta3NkQzVtYkdGbmMzdzlNVEk0TEc1MWJHd3BPaWh1Sm5RdVkyaHBiR1F1WTJo'
    || 'cGJHUk1ZVzVsY3lraFBUMHdQMUJoS0dVc2RDeHVLVG9vWm1Vb2VXVXNlV1V1WTNWeWNtVnVkQ1l4S1N4bFBVbDBLR1VzZEN4dUtTeGxJVDA5Ym5Wc2JEOWxM'
    || 'bk5wWW14cGJtYzZiblZzYkNrN1ptVW9lV1VzZVdVdVkzVnljbVZ1ZENZeEtUdGljbVZoYXp0allYTmxJREU1T21sbUtISTlLRzRtZEM1amFHbHNaRXhoYm1W'
    || 'ektTRTlQVEFzS0dVdVpteGhaM01tTVRJNEtTRTlQVEFwZTJsbUtISXBjbVYwZFhKdUlFbGhLR1VzZEN4dUtUdDBMbVpzWVdkemZEMHhNamg5YVdZb2JEMTBM'
    || 'bTFsYlc5cGVtVmtVM1JoZEdVc2JDRTlQVzUxYkd3bUppaHNMbkpsYm1SbGNtbHVaejF1ZFd4c0xHd3VkR0ZwYkQxdWRXeHNMR3d1YkdGemRFVm1abVZqZEQx'
    || 'dWRXeHNLU3htWlNoNVpTeDVaUzVqZFhKeVpXNTBLU3h5S1dKeVpXRnJPM0psZEhWeWJpQnVkV3hzTzJOaGMyVWdNakk2WTJGelpTQXlNenB5WlhSMWNtNGdk'
    || 'QzVzWVc1bGN6MHdMRU5oS0dVc2RDeHVLWDF5WlhSMWNtNGdTWFFvWlN4MExHNHBmWFpoY2lCQllTeFBieXhOWVN4NllUdEJZVDFtZFc1amRHbHZiaWhsTEhR'
    || 'cGUyWnZjaWgyWVhJZ2JqMTBMbU5vYVd4a08yNGhQVDF1ZFd4c095bDdhV1lvYmk1MFlXYzlQVDAxZkh4dUxuUmhaejA5UFRZcFpTNWhjSEJsYm1SRGFHbHNa'
    || 'Q2h1TG5OMFlYUmxUbTlrWlNrN1pXeHpaU0JwWmlodUxuUmhaeUU5UFRRbUptNHVZMmhwYkdRaFBUMXVkV3hzS1h0dUxtTm9hV3hrTG5KbGRIVnliajF1TEc0'
    || 'OWJpNWphR2xzWkR0amIyNTBhVzUxWlgxcFppaHVQVDA5ZENsaWNtVmhhenRtYjNJb08yNHVjMmxpYkdsdVp6MDlQVzUxYkd3N0tYdHBaaWh1TG5KbGRIVnli'
    || 'ajA5UFc1MWJHeDhmRzR1Y21WMGRYSnVQVDA5ZENseVpYUjFjbTQ3YmoxdUxuSmxkSFZ5Ym4xdUxuTnBZbXhwYm1jdWNtVjBkWEp1UFc0dWNtVjBkWEp1TEc0'
    || 'OWJpNXphV0pzYVc1bmZYMHNUMjg5Wm5WdVkzUnBiMjRvS1h0OUxFMWhQV1oxYm1OMGFXOXVLR1VzZEN4dUxISXBlM1poY2lCc1BXVXViV1Z0YjJsNlpXUlFj'
    || 'bTl3Y3p0cFppaHNJVDA5Y2lsN1pUMTBMbk4wWVhSbFRtOWtaU3h3YmlocWRDNWpkWEp5Wlc1MEtUdDJZWElnYVQxdWRXeHNPM04zYVhSamFDaHVLWHRqWVhO'
    || 'bEltbHVjSFYwSWpwc1BXbHBLR1VzYkNrc2NqMXBhU2hsTEhJcExHazlXMTA3WW5KbFlXczdZMkZ6WlNKelpXeGxZM1FpT213OVRDaDdmU3hzTEh0MllXeDFa'
    || 'VHAyYjJsa0lEQjlLU3h5UFV3b2UzMHNjaXg3ZG1Gc2RXVTZkbTlwWkNBd2ZTa3NhVDFiWFR0aWNtVmhhenRqWVhObEluUmxlSFJoY21WaElqcHNQWFZwS0dV'
    || 'c2JDa3NjajExYVNobExISXBMR2s5VzEwN1luSmxZV3M3WkdWbVlYVnNkRHAwZVhCbGIyWWdiQzV2YmtOc2FXTnJJVDBpWm5WdVkzUnBiMjRpSmlaMGVYQmxi'
    || 'MllnY2k1dmJrTnNhV05yUFQwaVpuVnVZM1JwYjI0aUppWW9aUzV2Ym1Oc2FXTnJQVzlzS1gxamFTaHVMSElwTzNaaGNpQnpPMjQ5Ym5Wc2JEdG1iM0lvZVNC'
    || 'cGJpQnNLV2xtS0NGeUxtaGhjMDkzYmxCeWIzQmxjblI1S0hrcEppWnNMbWhoYzA5M2JsQnliM0JsY25SNUtIa3BKaVpzVzNsZElUMXVkV3hzS1dsbUtIazlQ'
    || 'VDBpYzNSNWJHVWlLWHQyWVhJZ1pEMXNXM2xkTzJadmNpaHpJR2x1SUdRcFpDNW9ZWE5QZDI1UWNtOXdaWEowZVNoektTWW1LRzU4ZkNodVBYdDlLU3h1VzNO'
    || 'ZFBTSWlLWDFsYkhObElIa2hQVDBpWkdGdVoyVnliM1Z6YkhsVFpYUkpibTVsY2toVVRVd2lKaVo1SVQwOUltTm9hV3hrY21WdUlpWW1lU0U5UFNKemRYQndj'
    || 'bVZ6YzBOdmJuUmxiblJGWkdsMFlXSnNaVmRoY201cGJtY2lKaVo1SVQwOUluTjFjSEJ5WlhOelNIbGtjbUYwYVc5dVYyRnlibWx1WnlJbUpua2hQVDBpWVhW'
    || 'MGIwWnZZM1Z6SWlZbUtFVXVhR0Z6VDNkdVVISnZjR1Z5ZEhrb2VTay9hWHg4S0drOVcxMHBPaWhwUFdsOGZGdGRLUzV3ZFhOb0tIa3NiblZzYkNrcE8yWnZj'
    || 'aWg1SUdsdUlISXBlM1poY2lCbVBYSmJlVjA3YVdZb1pEMXNJVDF1ZFd4c1AyeGJlVjA2ZG05cFpDQXdMSEl1YUdGelQzZHVVSEp2Y0dWeWRIa29lU2ttSm1Z'
    || 'aFBUMWtKaVlvWmlFOWJuVnNiSHg4WkNFOWJuVnNiQ2twYVdZb2VUMDlQU0p6ZEhsc1pTSXBhV1lvWkNsN1ptOXlLSE1nYVc0Z1pDa2haQzVvWVhOUGQyNVFj'
    || 'bTl3WlhKMGVTaHpLWHg4WmlZbVppNW9ZWE5QZDI1UWNtOXdaWEowZVNoektYeDhLRzU4ZkNodVBYdDlLU3h1VzNOZFBTSWlLVHRtYjNJb2N5QnBiaUJtS1dZ'
    || 'dWFHRnpUM2R1VUhKdmNHVnlkSGtvY3lrbUptUmJjMTBoUFQxbVczTmRKaVlvYm54OEtHNDllMzBwTEc1YmMxMDlabHR6WFNsOVpXeHpaU0J1Zkh3b2FYeDhL'
    || 'R2s5VzEwcExHa3VjSFZ6YUNoNUxHNHBLU3h1UFdZN1pXeHpaU0I1UFQwOUltUmhibWRsY205MWMyeDVVMlYwU1c1dVpYSklWRTFNSWo4b1pqMW1QMll1WDE5'
    || 'b2RHMXNPblp2YVdRZ01DeGtQV1EvWkM1ZlgyaDBiV3c2ZG05cFpDQXdMR1loUFc1MWJHd21KbVFoUFQxbUppWW9hVDFwZkh4YlhTa3VjSFZ6YUNoNUxHWXBL'
    || 'VHA1UFQwOUltTm9hV3hrY21WdUlqOTBlWEJsYjJZZ1ppRTlJbk4wY21sdVp5SW1KblI1Y0dWdlppQm1JVDBpYm5WdFltVnlJbng4S0drOWFYeDhXMTBwTG5C'
    || 'MWMyZ29lU3dpSWl0bUtUcDVJVDA5SW5OMWNIQnlaWE56UTI5dWRHVnVkRVZrYVhSaFlteGxWMkZ5Ym1sdVp5SW1KbmtoUFQwaWMzVndjSEpsYzNOSWVXUnlZ'
    || 'WFJwYjI1WFlYSnVhVzVuSWlZbUtFVXVhR0Z6VDNkdVVISnZjR1Z5ZEhrb2VTay9LR1loUFc1MWJHd21Kbms5UFQwaWIyNVRZM0p2Ykd3aUppWndaU2dpYzJO'
    || 'eWIyeHNJaXhsS1N4cGZIeGtQVDA5Wm54OEtHazlXMTBwS1Rvb2FUMXBmSHhiWFNrdWNIVnphQ2g1TEdZcEtYMXVKaVlvYVQxcGZIeGJYU2t1Y0hWemFDZ2lj'
    || 'M1I1YkdVaUxHNHBPM1poY2lCNVBXazdLSFF1ZFhCa1lYUmxVWFZsZFdVOWVTa21KaWgwTG1ac1lXZHpmRDAwS1gxOUxIcGhQV1oxYm1OMGFXOXVLR1VzZEN4'
    || 'dUxISXBlMjRoUFQxeUppWW9kQzVtYkdGbmMzdzlOQ2w5TzJaMWJtTjBhVzl1SUU1eUtHVXNkQ2w3YVdZb0lYWmxLWE4zYVhSamFDaGxMblJoYVd4TmIyUmxL'
    || 'WHRqWVhObEltaHBaR1JsYmlJNmREMWxMblJoYVd3N1ptOXlLSFpoY2lCdVBXNTFiR3c3ZENFOVBXNTFiR3c3S1hRdVlXeDBaWEp1WVhSbElUMDliblZzYkNZ'
    || 'bUtHNDlkQ2tzZEQxMExuTnBZbXhwYm1jN2JqMDlQVzUxYkd3L1pTNTBZV2xzUFc1MWJHdzZiaTV6YVdKc2FXNW5QVzUxYkd3N1luSmxZV3M3WTJGelpTSmpi'
    || 'MnhzWVhCelpXUWlPbTQ5WlM1MFlXbHNPMlp2Y2loMllYSWdjajF1ZFd4c08yNGhQVDF1ZFd4c095bHVMbUZzZEdWeWJtRjBaU0U5UFc1MWJHd21KaWh5UFc0'
    || 'cExHNDliaTV6YVdKc2FXNW5PM0k5UFQxdWRXeHNQM1I4ZkdVdWRHRnBiRDA5UFc1MWJHdy9aUzUwWVdsc1BXNTFiR3c2WlM1MFlXbHNMbk5wWW14cGJtYzli'
    || 'blZzYkRweUxuTnBZbXhwYm1jOWJuVnNiSDE5Wm5WdVkzUnBiMjRnVjJVb1pTbDdkbUZ5SUhROVpTNWhiSFJsY201aGRHVWhQVDF1ZFd4c0ppWmxMbUZzZEdW'
    || 'eWJtRjBaUzVqYUdsc1pEMDlQV1V1WTJocGJHUXNiajB3TEhJOU1EdHBaaWgwS1dadmNpaDJZWElnYkQxbExtTm9hV3hrTzJ3aFBUMXVkV3hzT3lsdWZEMXNM'
    || 'bXhoYm1WemZHd3VZMmhwYkdSTVlXNWxjeXh5ZkQxc0xuTjFZblJ5WldWR2JHRm5jeVl4TkRZNE1EQTJOQ3h5ZkQxc0xtWnNZV2R6SmpFME5qZ3dNRFkwTEd3'
    || 'dWNtVjBkWEp1UFdVc2JEMXNMbk5wWW14cGJtYzdaV3h6WlNCbWIzSW9iRDFsTG1Ob2FXeGtPMndoUFQxdWRXeHNPeWx1ZkQxc0xteGhibVZ6Zkd3dVkyaHBi'
    || 'R1JNWVc1bGN5eHlmRDFzTG5OMVluUnlaV1ZHYkdGbmN5eHlmRDFzTG1ac1lXZHpMR3d1Y21WMGRYSnVQV1VzYkQxc0xuTnBZbXhwYm1jN2NtVjBkWEp1SUdV'
    || 'dWMzVmlkSEpsWlVac1lXZHpmRDF5TEdVdVkyaHBiR1JNWVc1bGN6MXVMSFI5Wm5WdVkzUnBiMjRnVm1Zb1pTeDBMRzRwZTNaaGNpQnlQWFF1Y0dWdVpHbHVa'
    || 'MUJ5YjNCek8zTjNhWFJqYUNoS2FTaDBLU3gwTG5SaFp5bDdZMkZ6WlNBeU9tTmhjMlVnTVRZNlkyRnpaU0F4TlRwallYTmxJREE2WTJGelpTQXhNVHBqWVhO'
    || 'bElEYzZZMkZ6WlNBNE9tTmhjMlVnTVRJNlkyRnpaU0E1T21OaGMyVWdNVFE2Y21WMGRYSnVJRmRsS0hRcExHNTFiR3c3WTJGelpTQXhPbkpsZEhWeWJpQkha'
    || 'U2gwTG5SNWNHVXBKaVoxYkNncExGZGxLSFFwTEc1MWJHdzdZMkZ6WlNBek9uSmxkSFZ5YmlCeVBYUXVjM1JoZEdWT2IyUmxMRmR1S0Nrc2FHVW9XV1VwTEdo'
    || 'bEtGVmxLU3htYnlncExISXVjR1Z1WkdsdVowTnZiblJsZUhRbUppaHlMbU52Ym5SbGVIUTljaTV3Wlc1a2FXNW5RMjl1ZEdWNGRDeHlMbkJsYm1ScGJtZERi'
    || 'MjUwWlhoMFBXNTFiR3dwTENobFBUMDliblZzYkh4OFpTNWphR2xzWkQwOVBXNTFiR3dwSmlZb2NHd29kQ2svZEM1bWJHRm5jM3c5TkRwbFBUMDliblZzYkh4'
    || 'OFpTNXRaVzF2YVhwbFpGTjBZWFJsTG1selJHVm9lV1J5WVhSbFpDWW1LSFF1Wm14aFozTW1NalUyS1QwOVBUQjhmQ2gwTG1ac1lXZHpmRDB4TURJMExHMTBJ'
    || 'VDA5Ym5Wc2JDWW1LRUp2S0cxMEtTeHRkRDF1ZFd4c0tTa3BMRTl2S0dVc2RDa3NWMlVvZENrc2JuVnNiRHRqWVhObElEVTZZVzhvZENrN2RtRnlJR3c5Y0c0'
    || 'b1gzSXVZM1Z5Y21WdWRDazdhV1lvYmoxMExuUjVjR1VzWlNFOVBXNTFiR3dtSm5RdWMzUmhkR1ZPYjJSbElUMXVkV3hzS1UxaEtHVXNkQ3h1TEhJc2JDa3Na'
    || 'UzV5WldZaFBUMTBMbkpsWmlZbUtIUXVabXhoWjNOOFBUVXhNaXgwTG1ac1lXZHpmRDB5TURrM01UVXlLVHRsYkhObGUybG1LQ0Z5S1h0cFppaDBMbk4wWVhS'
    || 'bFRtOWtaVDA5UFc1MWJHd3BkR2h5YjNjZ1JYSnliM0lvWVNneE5qWXBLVHR5WlhSMWNtNGdWMlVvZENrc2JuVnNiSDFwWmlobFBYQnVLR3AwTG1OMWNuSmxi'
    || 'blFwTEhCc0tIUXBLWHR5UFhRdWMzUmhkR1ZPYjJSbExHNDlkQzUwZVhCbE8zWmhjaUJwUFhRdWJXVnRiMmw2WldSUWNtOXdjenR6ZDJsMFkyZ29jbHRyZEYw'
    || 'OWRDeHlXM1p5WFQxcExHVTlLSFF1Ylc5a1pTWXhLU0U5UFRBc2JpbDdZMkZ6WlNKa2FXRnNiMmNpT25CbEtDSmpZVzVqWld3aUxISXBMSEJsS0NKamJHOXpa'
    || 'U0lzY2lrN1luSmxZV3M3WTJGelpTSnBabkpoYldVaU9tTmhjMlVpYjJKcVpXTjBJanBqWVhObEltVnRZbVZrSWpwd1pTZ2liRzloWkNJc2NpazdZbkpsWVdz'
    || 'N1kyRnpaU0oyYVdSbGJ5STZZMkZ6WlNKaGRXUnBieUk2Wm05eUtHdzlNRHRzUEhCeUxteGxibWQwYUR0c0t5c3BjR1VvY0hKYmJGMHNjaWs3WW5KbFlXczdZ'
    || 'MkZ6WlNKemIzVnlZMlVpT25CbEtDSmxjbkp2Y2lJc2NpazdZbkpsWVdzN1kyRnpaU0pwYldjaU9tTmhjMlVpYVcxaFoyVWlPbU5oYzJVaWJHbHVheUk2Y0dV'
    || 'b0ltVnljbTl5SWl4eUtTeHdaU2dpYkc5aFpDSXNjaWs3WW5KbFlXczdZMkZ6WlNKa1pYUmhhV3h6SWpwd1pTZ2lkRzluWjJ4bElpeHlLVHRpY21WaGF6dGpZ'
    || 'WE5sSW1sdWNIVjBJanBuY3loeUxHa3BMSEJsS0NKcGJuWmhiR2xrSWl4eUtUdGljbVZoYXp0allYTmxJbk5sYkdWamRDSTZjaTVmZDNKaGNIQmxjbE4wWVhS'
    || 'bFBYdDNZWE5OZFd4MGFYQnNaVG9oSVdrdWJYVnNkR2x3YkdWOUxIQmxLQ0pwYm5aaGJHbGtJaXh5S1R0aWNtVmhhenRqWVhObEluUmxlSFJoY21WaElqcEZj'
    || 'eWh5TEdrcExIQmxLQ0pwYm5aaGJHbGtJaXh5S1gxamFTaHVMR2twTEd3OWJuVnNiRHRtYjNJb2RtRnlJSE1nYVc0Z2FTbHBaaWhwTG1oaGMwOTNibEJ5YjNC'
    || 'bGNuUjVLSE1wS1h0MllYSWdaRDFwVzNOZE8zTTlQVDBpWTJocGJHUnlaVzRpUDNSNWNHVnZaaUJrUFQwaWMzUnlhVzVuSWo5eUxuUmxlSFJEYjI1MFpXNTBJ'
    || 'VDA5WkNZbUtHa3VjM1Z3Y0hKbGMzTkllV1J5WVhScGIyNVhZWEp1YVc1bklUMDlJVEFtSm1sc0tISXVkR1Y0ZEVOdmJuUmxiblFzWkN4bEtTeHNQVnNpWTJo'
    || 'cGJHUnlaVzRpTEdSZEtUcDBlWEJsYjJZZ1pEMDlJbTUxYldKbGNpSW1Kbkl1ZEdWNGRFTnZiblJsYm5RaFBUMGlJaXRrSmlZb2FTNXpkWEJ3Y21WemMwaDVa'
    || 'SEpoZEdsdmJsZGhjbTVwYm1jaFBUMGhNQ1ltYVd3b2NpNTBaWGgwUTI5dWRHVnVkQ3hrTEdVcExHdzlXeUpqYUdsc1pISmxiaUlzSWlJclpGMHBPa1V1YUdG'
    || 'elQzZHVVSEp2Y0dWeWRIa29jeWttSm1RaFBXNTFiR3dtSm5NOVBUMGliMjVUWTNKdmJHd2lKaVp3WlNnaWMyTnliMnhzSWl4eUtYMXpkMmwwWTJnb2JpbDdZ'
    || 'MkZ6WlNKcGJuQjFkQ0k2VFhJb2Npa3NlSE1vY2l4cExDRXdLVHRpY21WaGF6dGpZWE5sSW5SbGVIUmhjbVZoSWpwTmNpaHlLU3hUY3loeUtUdGljbVZoYXp0'
    || 'allYTmxJbk5sYkdWamRDSTZZMkZ6WlNKdmNIUnBiMjRpT21KeVpXRnJPMlJsWm1GMWJIUTZkSGx3Wlc5bUlHa3ViMjVEYkdsamF6MDlJbVoxYm1OMGFXOXVJ'
    || 'aVltS0hJdWIyNWpiR2xqYXoxdmJDbDljajFzTEhRdWRYQmtZWFJsVVhWbGRXVTljaXh5SVQwOWJuVnNiQ1ltS0hRdVpteGhaM044UFRRcGZXVnNjMlY3Y3ox'
    || 'c0xtNXZaR1ZVZVhCbFBUMDlPVDlzT213dWIzZHVaWEpFYjJOMWJXVnVkQ3hsUFQwOUltaDBkSEE2THk5M2QzY3Vkek11YjNKbkx6RTVPVGt2ZUdoMGJXd2lK'
    || 'aVlvWlQxM2N5aHVLU2tzWlQwOVBTSm9kSFJ3T2k4dmQzZDNMbmN6TG05eVp5OHhPVGs1TDNob2RHMXNJajl1UFQwOUluTmpjbWx3ZENJL0tHVTljeTVqY21W'
    || 'aGRHVkZiR1Z0Wlc1MEtDSmthWFlpS1N4bExtbHVibVZ5U0ZSTlREMGlQSE5qY21sd2RENDhYQzl6WTNKcGNIUStJaXhsUFdVdWNtVnRiM1psUTJocGJHUW9a'
    || 'UzVtYVhKemRFTm9hV3hrS1NrNmRIbHdaVzltSUhJdWFYTTlQU0p6ZEhKcGJtY2lQMlU5Y3k1amNtVmhkR1ZGYkdWdFpXNTBLRzRzZTJsek9uSXVhWE45S1Rv'
    || 'b1pUMXpMbU55WldGMFpVVnNaVzFsYm5Rb2Jpa3NiajA5UFNKelpXeGxZM1FpSmlZb2N6MWxMSEl1YlhWc2RHbHdiR1UvY3k1dGRXeDBhWEJzWlQwaE1EcHlM'
    || 'bk5wZW1VbUppaHpMbk5wZW1VOWNpNXphWHBsS1NrcE9tVTljeTVqY21WaGRHVkZiR1Z0Wlc1MFRsTW9aU3h1S1N4bFcydDBYVDEwTEdWYmRuSmRQWElzUVdF'
    || 'b1pTeDBMQ0V4TENFeEtTeDBMbk4wWVhSbFRtOWtaVDFsTzJVNmUzTjNhWFJqYUNoelBXUnBLRzRzY2lrc2JpbDdZMkZ6WlNKa2FXRnNiMmNpT25CbEtDSmpZ'
    || 'VzVqWld3aUxHVXBMSEJsS0NKamJHOXpaU0lzWlNrc2JEMXlPMkp5WldGck8yTmhjMlVpYVdaeVlXMWxJanBqWVhObEltOWlhbVZqZENJNlkyRnpaU0psYldK'
    || 'bFpDSTZjR1VvSW14dllXUWlMR1VwTEd3OWNqdGljbVZoYXp0allYTmxJblpwWkdWdklqcGpZWE5sSW1GMVpHbHZJanBtYjNJb2JEMHdPMnc4Y0hJdWJHVnVa'
    || 'M1JvTzJ3ckt5bHdaU2h3Y2x0c1hTeGxLVHRzUFhJN1luSmxZV3M3WTJGelpTSnpiM1Z5WTJVaU9uQmxLQ0psY25KdmNpSXNaU2tzYkQxeU8ySnlaV0ZyTzJO'
    || 'aGMyVWlhVzFuSWpwallYTmxJbWx0WVdkbElqcGpZWE5sSW14cGJtc2lPbkJsS0NKbGNuSnZjaUlzWlNrc2NHVW9JbXh2WVdRaUxHVXBMR3c5Y2p0aWNtVmhh'
    || 'enRqWVhObEltUmxkR0ZwYkhNaU9uQmxLQ0owYjJkbmJHVWlMR1VwTEd3OWNqdGljbVZoYXp0allYTmxJbWx1Y0hWMElqcG5jeWhsTEhJcExHdzlhV2tvWlN4'
    || 'eUtTeHdaU2dpYVc1MllXeHBaQ0lzWlNrN1luSmxZV3M3WTJGelpTSnZjSFJwYjI0aU9tdzljanRpY21WaGF6dGpZWE5sSW5ObGJHVmpkQ0k2WlM1ZmQzSmhj'
    || 'SEJsY2xOMFlYUmxQWHQzWVhOTmRXeDBhWEJzWlRvaElYSXViWFZzZEdsd2JHVjlMR3c5VENoN2ZTeHlMSHQyWVd4MVpUcDJiMmxrSURCOUtTeHdaU2dpYVc1'
    || 'MllXeHBaQ0lzWlNrN1luSmxZV3M3WTJGelpTSjBaWGgwWVhKbFlTSTZSWE1vWlN4eUtTeHNQWFZwS0dVc2Npa3NjR1VvSW1sdWRtRnNhV1FpTEdVcE8ySnla'
    || 'V0ZyTzJSbFptRjFiSFE2YkQxeWZXTnBLRzRzYkNrc1pEMXNPMlp2Y2locElHbHVJR1FwYVdZb1pDNW9ZWE5QZDI1UWNtOXdaWEowZVNocEtTbDdkbUZ5SUdZ'
    || 'OVpGdHBYVHRwUFQwOUluTjBlV3hsSWo5T2N5aGxMR1lwT21rOVBUMGlaR0Z1WjJWeWIzVnpiSGxUWlhSSmJtNWxja2hVVFV3aVB5aG1QV1kvWmk1ZlgyaDBi'
    || 'V3c2ZG05cFpDQXdMR1loUFc1MWJHd21KbXR6S0dVc1ppa3BPbWs5UFQwaVkyaHBiR1J5Wlc0aVAzUjVjR1Z2WmlCbVBUMGljM1J5YVc1bklqOG9iaUU5UFNK'
    || 'MFpYaDBZWEpsWVNKOGZHWWhQVDBpSWlrbUprdHVLR1VzWmlrNmRIbHdaVzltSUdZOVBTSnVkVzFpWlhJaUppWkxiaWhsTENJaUsyWXBPbWtoUFQwaWMzVndj'
    || 'SEpsYzNORGIyNTBaVzUwUldScGRHRmliR1ZYWVhKdWFXNW5JaVltYVNFOVBTSnpkWEJ3Y21WemMwaDVaSEpoZEdsdmJsZGhjbTVwYm1jaUppWnBJVDA5SW1G'
    || 'MWRHOUdiMk4xY3lJbUppaEZMbWhoYzA5M2JsQnliM0JsY25SNUtHa3BQMlloUFc1MWJHd21KbWs5UFQwaWIyNVRZM0p2Ykd3aUppWndaU2dpYzJOeWIyeHNJ'
    || 'aXhsS1RwbUlUMXVkV3hzSmlaQ0tHVXNhU3htTEhNcEtYMXpkMmwwWTJnb2JpbDdZMkZ6WlNKcGJuQjFkQ0k2VFhJb1pTa3NlSE1vWlN4eUxDRXhLVHRpY21W'
    || 'aGF6dGpZWE5sSW5SbGVIUmhjbVZoSWpwTmNpaGxLU3hUY3lobEtUdGljbVZoYXp0allYTmxJbTl3ZEdsdmJpSTZjaTUyWVd4MVpTRTliblZzYkNZbVpTNXpa'
    || 'WFJCZEhSeWFXSjFkR1VvSW5aaGJIVmxJaXdpSWl0elpTaHlMblpoYkhWbEtTazdZbkpsWVdzN1kyRnpaU0p6Wld4bFkzUWlPbVV1YlhWc2RHbHdiR1U5SVNG'
    || 'eUxtMTFiSFJwY0d4bExHazljaTUyWVd4MVpTeHBJVDF1ZFd4c1AxOXVLR1VzSVNGeUxtMTFiSFJwY0d4bExHa3NJVEVwT25JdVpHVm1ZWFZzZEZaaGJIVmxJ'
    || 'VDF1ZFd4c0ppWmZiaWhsTENFaGNpNXRkV3gwYVhCc1pTeHlMbVJsWm1GMWJIUldZV3gxWlN3aE1DazdZbkpsWVdzN1pHVm1ZWFZzZERwMGVYQmxiMllnYkM1'
    || 'dmJrTnNhV05yUFQwaVpuVnVZM1JwYjI0aUppWW9aUzV2Ym1Oc2FXTnJQVzlzS1gxemQybDBZMmdvYmlsN1kyRnpaU0ppZFhSMGIyNGlPbU5oYzJVaWFXNXdk'
    || 'WFFpT21OaGMyVWljMlZzWldOMElqcGpZWE5sSW5SbGVIUmhjbVZoSWpweVBTRWhjaTVoZFhSdlJtOWpkWE03WW5KbFlXc2daVHRqWVhObEltbHRaeUk2Y2ow'
    || 'aE1EdGljbVZoYXlCbE8yUmxabUYxYkhRNmNqMGhNWDE5Y2lZbUtIUXVabXhoWjNOOFBUUXBmWFF1Y21WbUlUMDliblZzYkNZbUtIUXVabXhoWjNOOFBUVXhN'
    || 'aXgwTG1ac1lXZHpmRDB5TURrM01UVXlLWDF5WlhSMWNtNGdWMlVvZENrc2JuVnNiRHRqWVhObElEWTZhV1lvWlNZbWRDNXpkR0YwWlU1dlpHVWhQVzUxYkd3'
    || 'cGVtRW9aU3gwTEdVdWJXVnRiMmw2WldSUWNtOXdjeXh5S1R0bGJITmxlMmxtS0hSNWNHVnZaaUJ5SVQwaWMzUnlhVzVuSWlZbWRDNXpkR0YwWlU1dlpHVTlQ'
    || 'VDF1ZFd4c0tYUm9jbTkzSUVWeWNtOXlLR0VvTVRZMktTazdhV1lvYmoxd2JpaGZjaTVqZFhKeVpXNTBLU3h3YmlocWRDNWpkWEp5Wlc1MEtTeHdiQ2gwS1Ns'
    || 'N2FXWW9jajEwTG5OMFlYUmxUbTlrWlN4dVBYUXViV1Z0YjJsNlpXUlFjbTl3Y3l4eVcydDBYVDEwTENocFBYSXVibTlrWlZaaGJIVmxJVDA5YmlrbUppaGxQ'
    || 'WFIwTEdVaFBUMXVkV3hzS1NsemQybDBZMmdvWlM1MFlXY3BlMk5oYzJVZ016cHBiQ2h5TG01dlpHVldZV3gxWlN4dUxDaGxMbTF2WkdVbU1Ta2hQVDB3S1R0'
    || 'aWNtVmhhenRqWVhObElEVTZaUzV0WlcxdmFYcGxaRkJ5YjNCekxuTjFjSEJ5WlhOelNIbGtjbUYwYVc5dVYyRnlibWx1WnlFOVBTRXdKaVpwYkNoeUxtNXZa'
    || 'R1ZXWVd4MVpTeHVMQ2hsTG0xdlpHVW1NU2toUFQwd0tYMXBKaVlvZEM1bWJHRm5jM3c5TkNsOVpXeHpaU0J5UFNodUxtNXZaR1ZVZVhCbFBUMDlPVDl1T200'
    || 'dWIzZHVaWEpFYjJOMWJXVnVkQ2t1WTNKbFlYUmxWR1Y0ZEU1dlpHVW9jaWtzY2x0cmRGMDlkQ3gwTG5OMFlYUmxUbTlrWlQxeWZYSmxkSFZ5YmlCWFpTaDBL'
    || 'U3h1ZFd4c08yTmhjMlVnTVRNNmFXWW9hR1VvZVdVcExISTlkQzV0WlcxdmFYcGxaRk4wWVhSbExHVTlQVDF1ZFd4c2ZIeGxMbTFsYlc5cGVtVmtVM1JoZEdV'
    || 'aFBUMXVkV3hzSmlabExtMWxiVzlwZW1Wa1UzUmhkR1V1WkdWb2VXUnlZWFJsWkNFOVBXNTFiR3dwZTJsbUtIWmxKaVp1ZENFOVBXNTFiR3dtSmloMExtMXZa'
    || 'R1VtTVNraFBUMHdKaVlvZEM1bWJHRm5jeVl4TWpncFBUMDlNQ2xYZFNncExFMXVLQ2tzZEM1bWJHRm5jM3c5T1RnMU5qQXNhVDBoTVR0bGJITmxJR2xtS0dr'
    || 'OWNHd29kQ2tzY2lFOVBXNTFiR3dtSm5JdVpHVm9lV1J5WVhSbFpDRTlQVzUxYkd3cGUybG1LR1U5UFQxdWRXeHNLWHRwWmlnaGFTbDBhSEp2ZHlCRmNuSnZj'
    || 'aWhoS0RNeE9Da3BPMmxtS0drOWRDNXRaVzF2YVhwbFpGTjBZWFJsTEdrOWFTRTlQVzUxYkd3L2FTNWtaV2g1WkhKaGRHVmtPbTUxYkd3c0lXa3BkR2h5YjNj'
    || 'Z1JYSnliM0lvWVNnek1UY3BLVHRwVzJ0MFhUMTBmV1ZzYzJVZ1RXNG9LU3dvZEM1bWJHRm5jeVl4TWpncFBUMDlNQ1ltS0hRdWJXVnRiMmw2WldSVGRHRjBa'
    || 'VDF1ZFd4c0tTeDBMbVpzWVdkemZEMDBPMWRsS0hRcExHazlJVEY5Wld4elpTQnRkQ0U5UFc1MWJHd21KaWhDYnlodGRDa3NiWFE5Ym5Wc2JDa3NhVDBoTUR0'
    || 'cFppZ2hhU2x5WlhSMWNtNGdkQzVtYkdGbmN5WTJOVFV6Tmo5ME9tNTFiR3g5Y21WMGRYSnVLSFF1Wm14aFozTW1NVEk0S1NFOVBUQS9LSFF1YkdGdVpYTTli'
    || 'aXgwS1Rvb2NqMXlJVDA5Ym5Wc2JDeHlJVDA5S0dVaFBUMXVkV3hzSmlabExtMWxiVzlwZW1Wa1UzUmhkR1VoUFQxdWRXeHNLU1ltY2lZbUtIUXVZMmhwYkdR'
    || 'dVpteGhaM044UFRneE9USXNLSFF1Ylc5a1pTWXhLU0U5UFRBbUppaGxQVDA5Ym5Wc2JIeDhLSGxsTG1OMWNuSmxiblFtTVNraFBUMHdQMUpsUFQwOU1DWW1L'
    || 'RkpsUFRNcE9sRnZLQ2twS1N4MExuVndaR0YwWlZGMVpYVmxJVDA5Ym5Wc2JDWW1LSFF1Wm14aFozTjhQVFFwTEZkbEtIUXBMRzUxYkd3cE8yTmhjMlVnTkRw'
    || 'eVpYUjFjbTRnVjI0b0tTeFBieWhsTEhRcExHVTlQVDF1ZFd4c0ppWm9jaWgwTG5OMFlYUmxUbTlrWlM1amIyNTBZV2x1WlhKSmJtWnZLU3hYWlNoMEtTeHVk'
    || 'V3hzTzJOaGMyVWdNVEE2Y21WMGRYSnVJR3h2S0hRdWRIbHdaUzVmWTI5dWRHVjRkQ2tzVjJVb2RDa3NiblZzYkR0allYTmxJREUzT25KbGRIVnliaUJIWlNo'
    || 'MExuUjVjR1VwSmlaMWJDZ3BMRmRsS0hRcExHNTFiR3c3WTJGelpTQXhPVHBwWmlob1pTaDVaU2tzYVQxMExtMWxiVzlwZW1Wa1UzUmhkR1VzYVQwOVBXNTFi'
    || 'R3dwY21WMGRYSnVJRmRsS0hRcExHNTFiR3c3YVdZb2NqMG9kQzVtYkdGbmN5WXhNamdwSVQwOU1DeHpQV2t1Y21WdVpHVnlhVzVuTEhNOVBUMXVkV3hzS1ds'
    || 'bUtISXBUbklvYVN3aE1TazdaV3h6Wlh0cFppaFNaU0U5UFRCOGZHVWhQVDF1ZFd4c0ppWW9aUzVtYkdGbmN5WXhNamdwSVQwOU1DbG1iM0lvWlQxMExtTm9h'
    || 'V3hrTzJVaFBUMXVkV3hzT3lsN2FXWW9jejE0YkNobEtTeHpJVDA5Ym5Wc2JDbDdabTl5S0hRdVpteGhaM044UFRFeU9DeE9jaWhwTENFeEtTeHlQWE11ZFhC'
    || 'a1lYUmxVWFZsZFdVc2NpRTlQVzUxYkd3bUppaDBMblZ3WkdGMFpWRjFaWFZsUFhJc2RDNW1iR0ZuYzN3OU5Da3NkQzV6ZFdKMGNtVmxSbXhoWjNNOU1DeHlQ'
    || 'VzRzYmoxMExtTm9hV3hrTzI0aFBUMXVkV3hzT3lscFBXNHNaVDF5TEdrdVpteGhaM01tUFRFME5qZ3dNRFkyTEhNOWFTNWhiSFJsY201aGRHVXNjejA5UFc1'
    || 'MWJHdy9LR2t1WTJocGJHUk1ZVzVsY3owd0xHa3ViR0Z1WlhNOVpTeHBMbU5vYVd4a1BXNTFiR3dzYVM1emRXSjBjbVZsUm14aFozTTlNQ3hwTG0xbGJXOXBl'
    || 'bVZrVUhKdmNITTliblZzYkN4cExtMWxiVzlwZW1Wa1UzUmhkR1U5Ym5Wc2JDeHBMblZ3WkdGMFpWRjFaWFZsUFc1MWJHd3NhUzVrWlhCbGJtUmxibU5wWlhN'
    || 'OWJuVnNiQ3hwTG5OMFlYUmxUbTlrWlQxdWRXeHNLVG9vYVM1amFHbHNaRXhoYm1WelBYTXVZMmhwYkdSTVlXNWxjeXhwTG14aGJtVnpQWE11YkdGdVpYTXNh'
    || 'UzVqYUdsc1pEMXpMbU5vYVd4a0xHa3VjM1ZpZEhKbFpVWnNZV2R6UFRBc2FTNWtaV3hsZEdsdmJuTTliblZzYkN4cExtMWxiVzlwZW1Wa1VISnZjSE05Y3k1'
    || 'dFpXMXZhWHBsWkZCeWIzQnpMR2t1YldWdGIybDZaV1JUZEdGMFpUMXpMbTFsYlc5cGVtVmtVM1JoZEdVc2FTNTFjR1JoZEdWUmRXVjFaVDF6TG5Wd1pHRjBa'
    || 'VkYxWlhWbExHa3VkSGx3WlQxekxuUjVjR1VzWlQxekxtUmxjR1Z1WkdWdVkybGxjeXhwTG1SbGNHVnVaR1Z1WTJsbGN6MWxQVDA5Ym5Wc2JEOXVkV3hzT250'
    || 'c1lXNWxjenBsTG14aGJtVnpMR1pwY25OMFEyOXVkR1Y0ZERwbExtWnBjbk4wUTI5dWRHVjRkSDBwTEc0OWJpNXphV0pzYVc1bk8zSmxkSFZ5YmlCbVpTaDVa'
    || 'U3g1WlM1amRYSnlaVzUwSmpGOE1pa3NkQzVqYUdsc1pIMWxQV1V1YzJsaWJHbHVaMzFwTG5SaGFXd2hQVDF1ZFd4c0ppWjNaU2dwUGlSdUppWW9kQzVtYkdG'
    || 'bmMzdzlNVEk0TEhJOUlUQXNUbklvYVN3aE1Ta3NkQzVzWVc1bGN6MDBNVGswTXpBMEtYMWxiSE5sZTJsbUtDRnlLV2xtS0dVOWVHd29jeWtzWlNFOVBXNTFi'
    || 'R3dwZTJsbUtIUXVabXhoWjNOOFBURXlPQ3h5UFNFd0xHNDlaUzUxY0dSaGRHVlJkV1YxWlN4dUlUMDliblZzYkNZbUtIUXVkWEJrWVhSbFVYVmxkV1U5Yml4'
    || 'MExtWnNZV2R6ZkQwMEtTeE9jaWhwTENFd0tTeHBMblJoYVd3OVBUMXVkV3hzSmlacExuUmhhV3hOYjJSbFBUMDlJbWhwWkdSbGJpSW1KaUZ6TG1Gc2RHVnli'
    || 'bUYwWlNZbUlYWmxLWEpsZEhWeWJpQlhaU2gwS1N4dWRXeHNmV1ZzYzJVZ01pcDNaU2dwTFdrdWNtVnVaR1Z5YVc1blUzUmhjblJVYVcxbFBpUnVKaVp1SVQw'
    || 'OU1UQTNNemMwTVRneU5DWW1LSFF1Wm14aFozTjhQVEV5T0N4eVBTRXdMRTV5S0drc0lURXBMSFF1YkdGdVpYTTlOREU1TkRNd05DazdhUzVwYzBKaFkydDNZ'
    || 'WEprY3o4b2N5NXphV0pzYVc1blBYUXVZMmhwYkdRc2RDNWphR2xzWkQxektUb29iajFwTG14aGMzUXNiaUU5UFc1MWJHdy9iaTV6YVdKc2FXNW5QWE02ZEM1'
    || 'amFHbHNaRDF6TEdrdWJHRnpkRDF6S1gxeVpYUjFjbTRnYVM1MFlXbHNJVDA5Ym5Wc2JEOG9kRDFwTG5SaGFXd3NhUzV5Wlc1a1pYSnBibWM5ZEN4cExuUmhh'
    || 'V3c5ZEM1emFXSnNhVzVuTEdrdWNtVnVaR1Z5YVc1blUzUmhjblJVYVcxbFBYZGxLQ2tzZEM1emFXSnNhVzVuUFc1MWJHd3NiajE1WlM1amRYSnlaVzUwTEda'
    || 'bEtIbGxMSEkvYmlZeGZESTZiaVl4S1N4MEtUb29WMlVvZENrc2JuVnNiQ2s3WTJGelpTQXlNanBqWVhObElESXpPbkpsZEhWeWJpQWtieWdwTEhJOWRDNXRa'
    || 'VzF2YVhwbFpGTjBZWFJsSVQwOWJuVnNiQ3hsSVQwOWJuVnNiQ1ltWlM1dFpXMXZhWHBsWkZOMFlYUmxJVDA5Ym5Wc2JDRTlQWEltSmloMExtWnNZV2R6ZkQw'
    || 'NE1Ua3lLU3h5SmlZb2RDNXRiMlJsSmpFcElUMDlNRDhvY25RbU1UQTNNemMwTVRneU5Da2hQVDB3SmlZb1YyVW9kQ2tzZEM1emRXSjBjbVZsUm14aFozTW1O'
    || 'aVltS0hRdVpteGhaM044UFRneE9USXBLVHBYWlNoMEtTeHVkV3hzTzJOaGMyVWdNalE2Y21WMGRYSnVJRzUxYkd3N1kyRnpaU0F5TlRweVpYUjFjbTRnYm5W'
    || 'c2JIMTBhSEp2ZHlCRmNuSnZjaWhoS0RFMU5peDBMblJoWnlrcGZXWjFibU4wYVc5dUlFSm1LR1VzZENsN2MzZHBkR05vS0VwcEtIUXBMSFF1ZEdGbktYdGpZ'
    || 'WE5sSURFNmNtVjBkWEp1SUVkbEtIUXVkSGx3WlNrbUpuVnNLQ2tzWlQxMExtWnNZV2R6TEdVbU5qVTFNelkvS0hRdVpteGhaM005WlNZdE5qVTFNemQ4TVRJ'
    || 'NExIUXBPbTUxYkd3N1kyRnpaU0F6T25KbGRIVnliaUJYYmlncExHaGxLRmxsS1N4b1pTaFZaU2tzWm04b0tTeGxQWFF1Wm14aFozTXNLR1VtTmpVMU16WXBJ'
    || 'VDA5TUNZbUtHVW1NVEk0S1QwOVBUQS9LSFF1Wm14aFozTTlaU1l0TmpVMU16ZDhNVEk0TEhRcE9tNTFiR3c3WTJGelpTQTFPbkpsZEhWeWJpQmhieWgwS1N4'
    || 'dWRXeHNPMk5oYzJVZ01UTTZhV1lvYUdVb2VXVXBMR1U5ZEM1dFpXMXZhWHBsWkZOMFlYUmxMR1VoUFQxdWRXeHNKaVpsTG1SbGFIbGtjbUYwWldRaFBUMXVk'
    || 'V3hzS1h0cFppaDBMbUZzZEdWeWJtRjBaVDA5UFc1MWJHd3BkR2h5YjNjZ1JYSnliM0lvWVNnek5EQXBLVHROYmlncGZYSmxkSFZ5YmlCbFBYUXVabXhoWjNN'
    || 'c1pTWTJOVFV6Tmo4b2RDNW1iR0ZuY3oxbEppMDJOVFV6TjN3eE1qZ3NkQ2s2Ym5Wc2JEdGpZWE5sSURFNU9uSmxkSFZ5YmlCb1pTaDVaU2tzYm5Wc2JEdGpZ'
    || 'WE5sSURRNmNtVjBkWEp1SUZkdUtDa3NiblZzYkR0allYTmxJREV3T25KbGRIVnliaUJzYnloMExuUjVjR1V1WDJOdmJuUmxlSFFwTEc1MWJHdzdZMkZ6WlNB'
    || 'eU1qcGpZWE5sSURJek9uSmxkSFZ5YmlBa2J5Z3BMRzUxYkd3N1kyRnpaU0F5TkRweVpYUjFjbTRnYm5Wc2JEdGtaV1poZFd4ME9uSmxkSFZ5YmlCdWRXeHNm'
    || 'WDEyWVhJZ1ZHdzlJVEVzVm1VOUlURXNTR1k5ZEhsd1pXOW1JRmRsWVd0VFpYUTlQU0ptZFc1amRHbHZiaUkvVjJWaGExTmxkRHBUWlhRc1VEMXVkV3hzTzJa'
    || 'MWJtTjBhVzl1SUVKdUtHVXNkQ2w3ZG1GeUlHNDlaUzV5WldZN2FXWW9iaUU5UFc1MWJHd3BhV1lvZEhsd1pXOW1JRzQ5UFNKbWRXNWpkR2x2YmlJcGRISjVl'
    || 'MjRvYm5Wc2JDbDlZMkYwWTJnb2NpbDdYMlVvWlN4MExISXBmV1ZzYzJVZ2JpNWpkWEp5Wlc1MFBXNTFiR3g5Wm5WdVkzUnBiMjRnVUc4b1pTeDBMRzRwZTNS'
    || 'eWVYdHVLQ2w5WTJGMFkyZ29jaWw3WDJVb1pTeDBMSElwZlgxMllYSWdWV0U5SVRFN1puVnVZM1JwYjI0Z0pHWW9aU3gwS1h0cFppaElhVDFMY2l4bFBYWjFL'
    || 'Q2tzUVdrb1pTa3BlMmxtS0NKelpXeGxZM1JwYjI1VGRHRnlkQ0pwYmlCbEtYWmhjaUJ1UFh0emRHRnlkRHBsTG5ObGJHVmpkR2x2YmxOMFlYSjBMR1Z1WkRw'
    || 'bExuTmxiR1ZqZEdsdmJrVnVaSDA3Wld4elpTQmxPbnR1UFNodVBXVXViM2R1WlhKRWIyTjFiV1Z1ZENrbUptNHVaR1ZtWVhWc2RGWnBaWGQ4ZkhkcGJtUnZk'
    || 'enQyWVhJZ2NqMXVMbWRsZEZObGJHVmpkR2x2YmlZbWJpNW5aWFJUWld4bFkzUnBiMjRvS1R0cFppaHlKaVp5TG5KaGJtZGxRMjkxYm5RaFBUMHdLWHR1UFhJ'
    || 'dVlXNWphRzl5VG05a1pUdDJZWElnYkQxeUxtRnVZMmh2Y2s5bVpuTmxkQ3hwUFhJdVptOWpkWE5PYjJSbE8zSTljaTVtYjJOMWMwOW1abk5sZER0MGNubDdi'
    || 'aTV1YjJSbFZIbHdaU3hwTG01dlpHVlVlWEJsZldOaGRHTm9lMjQ5Ym5Wc2JEdGljbVZoYXlCbGZYWmhjaUJ6UFRBc1pEMHRNU3htUFMweExIazlNQ3hyUFRB'
    || 'c1RqMWxMRjg5Ym5Wc2JEdDBPbVp2Y2lnN095bDdabTl5S0haaGNpQlBPMDRoUFQxdWZIeHNJVDA5TUNZbVRpNXViMlJsVkhsd1pTRTlQVE44ZkNoa1BYTXJi'
    || 'Q2tzVGlFOVBXbDhmSEloUFQwd0ppWk9MbTV2WkdWVWVYQmxJVDA5TTN4OEtHWTljeXR5S1N4T0xtNXZaR1ZVZVhCbFBUMDlNeVltS0hNclBVNHVibTlrWlZa'
    || 'aGJIVmxMbXhsYm1kMGFDa3NLRTg5VGk1bWFYSnpkRU5vYVd4a0tTRTlQVzUxYkd3N0tWODlUaXhPUFU4N1ptOXlLRHM3S1h0cFppaE9QVDA5WlNsaWNtVmhh'
    || 'eUIwTzJsbUtGODlQVDF1SmlZckszazlQVDFzSmlZb1pEMXpLU3hmUFQwOWFTWW1LeXRyUFQwOWNpWW1LR1k5Y3lrc0tFODlUaTV1WlhoMFUybGliR2x1Wnlr'
    || 'aFBUMXVkV3hzS1dKeVpXRnJPMDQ5WHl4ZlBVNHVjR0Z5Wlc1MFRtOWtaWDFPUFU5OWJqMWtQVDA5TFRGOGZHWTlQVDB0TVQ5dWRXeHNPbnR6ZEdGeWREcGtM'
    || 'R1Z1WkRwbWZYMWxiSE5sSUc0OWJuVnNiSDF1UFc1OGZIdHpkR0Z5ZERvd0xHVnVaRG93ZlgxbGJITmxJRzQ5Ym5Wc2JEdG1iM0lvSkdrOWUyWnZZM1Z6WldS'
    || 'RmJHVnRPbVVzYzJWc1pXTjBhVzl1VW1GdVoyVTZibjBzUzNJOUlURXNVRDEwTzFBaFBUMXVkV3hzT3lscFppaDBQVkFzWlQxMExtTm9hV3hrTENoMExuTjFZ'
    || 'blJ5WldWR2JHRm5jeVl4TURJNEtTRTlQVEFtSm1VaFBUMXVkV3hzS1dVdWNtVjBkWEp1UFhRc1VEMWxPMlZzYzJVZ1ptOXlLRHRRSVQwOWJuVnNiRHNwZTNR'
    || 'OVVEdDBjbmw3ZG1GeUlFazlkQzVoYkhSbGNtNWhkR1U3YVdZb0tIUXVabXhoWjNNbU1UQXlOQ2toUFQwd0tYTjNhWFJqYUNoMExuUmhaeWw3WTJGelpTQXdP'
    || 'bU5oYzJVZ01URTZZMkZ6WlNBeE5UcGljbVZoYXp0allYTmxJREU2YVdZb1NTRTlQVzUxYkd3cGUzWmhjaUJOUFVrdWJXVnRiMmw2WldSUWNtOXdjeXhyWlQx'
    || 'SkxtMWxiVzlwZW1Wa1UzUmhkR1VzZGoxMExuTjBZWFJsVG05a1pTeHdQWFl1WjJWMFUyNWhjSE5vYjNSQ1pXWnZjbVZWY0dSaGRHVW9kQzVsYkdWdFpXNTBW'
    || 'SGx3WlQwOVBYUXVkSGx3WlQ5Tk9uWjBLSFF1ZEhsd1pTeE5LU3hyWlNrN2RpNWZYM0psWVdOMFNXNTBaWEp1WVd4VGJtRndjMmh2ZEVKbFptOXlaVlZ3WkdG'
    || 'MFpUMXdmV0p5WldGck8yTmhjMlVnTXpwMllYSWdaejEwTG5OMFlYUmxUbTlrWlM1amIyNTBZV2x1WlhKSmJtWnZPMmN1Ym05a1pWUjVjR1U5UFQweFAyY3Vk'
    || 'R1Y0ZEVOdmJuUmxiblE5SWlJNlp5NXViMlJsVkhsd1pUMDlQVGttSm1jdVpHOWpkVzFsYm5SRmJHVnRaVzUwSmlabkxuSmxiVzkyWlVOb2FXeGtLR2N1Wkc5'
    || 'amRXMWxiblJGYkdWdFpXNTBLVHRpY21WaGF6dGpZWE5sSURVNlkyRnpaU0EyT21OaGMyVWdORHBqWVhObElERTNPbUp5WldGck8yUmxabUYxYkhRNmRHaHli'
    || 'M2NnUlhKeWIzSW9ZU2d4TmpNcEtYMTlZMkYwWTJnb1F5bDdYMlVvZEN4MExuSmxkSFZ5Yml4REtYMXBaaWhsUFhRdWMybGliR2x1Wnl4bElUMDliblZzYkNs'
    || 'N1pTNXlaWFIxY200OWRDNXlaWFIxY200c1VEMWxPMkp5WldGcmZWQTlkQzV5WlhSMWNtNTljbVYwZFhKdUlFazlWV0VzVldFOUlURXNTWDFtZFc1amRHbHZi'
    || 'aUJEY2lobExIUXNiaWw3ZG1GeUlISTlkQzUxY0dSaGRHVlJkV1YxWlR0cFppaHlQWEloUFQxdWRXeHNQM0l1YkdGemRFVm1abVZqZERwdWRXeHNMSEloUFQx'
    || 'dWRXeHNLWHQyWVhJZ2JEMXlQWEl1Ym1WNGREdGtiM3RwWmlnb2JDNTBZV2NtWlNrOVBUMWxLWHQyWVhJZ2FUMXNMbVJsYzNSeWIzazdiQzVrWlhOMGNtOTVQ'
    || 'WFp2YVdRZ01DeHBJVDA5ZG05cFpDQXdKaVpRYnloMExHNHNhU2w5YkQxc0xtNWxlSFI5ZDJocGJHVW9iQ0U5UFhJcGZYMW1kVzVqZEdsdmJpQlNiQ2hsTEhR'
    || 'cGUybG1LSFE5ZEM1MWNHUmhkR1ZSZFdWMVpTeDBQWFFoUFQxdWRXeHNQM1F1YkdGemRFVm1abVZqZERwdWRXeHNMSFFoUFQxdWRXeHNLWHQyWVhJZ2JqMTBQ'
    || 'WFF1Ym1WNGREdGtiM3RwWmlnb2JpNTBZV2NtWlNrOVBUMWxLWHQyWVhJZ2NqMXVMbU55WldGMFpUdHVMbVJsYzNSeWIzazljaWdwZlc0OWJpNXVaWGgwZlhk'
    || 'b2FXeGxLRzRoUFQxMEtYMTlablZ1WTNScGIyNGdURzhvWlNsN2RtRnlJSFE5WlM1eVpXWTdhV1lvZENFOVBXNTFiR3dwZTNaaGNpQnVQV1V1YzNSaGRHVk9i'
    || 'MlJsTzNOM2FYUmphQ2hsTG5SaFp5bDdZMkZ6WlNBMU9tVTlianRpY21WaGF6dGtaV1poZFd4ME9tVTlibjEwZVhCbGIyWWdkRDA5SW1aMWJtTjBhVzl1SWo5'
    || 'MEtHVXBPblF1WTNWeWNtVnVkRDFsZlgxbWRXNWpkR2x2YmlCR1lTaGxLWHQyWVhJZ2REMWxMbUZzZEdWeWJtRjBaVHQwSVQwOWJuVnNiQ1ltS0dVdVlXeDBa'
    || 'WEp1WVhSbFBXNTFiR3dzUm1Fb2RDa3BMR1V1WTJocGJHUTliblZzYkN4bExtUmxiR1YwYVc5dWN6MXVkV3hzTEdVdWMybGliR2x1WnoxdWRXeHNMR1V1ZEdG'
    || 'blBUMDlOU1ltS0hROVpTNXpkR0YwWlU1dlpHVXNkQ0U5UFc1MWJHd21KaWhrWld4bGRHVWdkRnRyZEYwc1pHVnNaWFJsSUhSYmRuSmRMR1JsYkdWMFpTQjBX'
    || 'MHRwWFN4a1pXeGxkR1VnZEZ0T1psMHNaR1ZzWlhSbElIUmJRMlpkS1Nrc1pTNXpkR0YwWlU1dlpHVTliblZzYkN4bExuSmxkSFZ5YmoxdWRXeHNMR1V1WkdW'
    || 'd1pXNWtaVzVqYVdWelBXNTFiR3dzWlM1dFpXMXZhWHBsWkZCeWIzQnpQVzUxYkd3c1pTNXRaVzF2YVhwbFpGTjBZWFJsUFc1MWJHd3NaUzV3Wlc1a2FXNW5V'
    || 'SEp2Y0hNOWJuVnNiQ3hsTG5OMFlYUmxUbTlrWlQxdWRXeHNMR1V1ZFhCa1lYUmxVWFZsZFdVOWJuVnNiSDFtZFc1amRHbHZiaUJYWVNobEtYdHlaWFIxY200'
    || 'Z1pTNTBZV2M5UFQwMWZIeGxMblJoWnowOVBUTjhmR1V1ZEdGblBUMDlOSDFtZFc1amRHbHZiaUJXWVNobEtYdGxPbVp2Y2lnN095bDdabTl5S0R0bExuTnBZ'
    || 'bXhwYm1jOVBUMXVkV3hzT3lsN2FXWW9aUzV5WlhSMWNtNDlQVDF1ZFd4c2ZIeFhZU2hsTG5KbGRIVnliaWtwY21WMGRYSnVJRzUxYkd3N1pUMWxMbkpsZEhW'
    || 'eWJuMW1iM0lvWlM1emFXSnNhVzVuTG5KbGRIVnliajFsTG5KbGRIVnliaXhsUFdVdWMybGliR2x1Wnp0bExuUmhaeUU5UFRVbUptVXVkR0ZuSVQwOU5pWW1a'
    || 'UzUwWVdjaFBUMHhPRHNwZTJsbUtHVXVabXhoWjNNbU1ueDhaUzVqYUdsc1pEMDlQVzUxYkd4OGZHVXVkR0ZuUFQwOU5DbGpiMjUwYVc1MVpTQmxPMlV1WTJo'
    || 'cGJHUXVjbVYwZFhKdVBXVXNaVDFsTG1Ob2FXeGtmV2xtS0NFb1pTNW1iR0ZuY3lZeUtTbHlaWFIxY200Z1pTNXpkR0YwWlU1dlpHVjlmV1oxYm1OMGFXOXVJ'
    || 'RWx2S0dVc2RDeHVLWHQyWVhJZ2NqMWxMblJoWnp0cFppaHlQVDA5Tlh4OGNqMDlQVFlwWlQxbExuTjBZWFJsVG05a1pTeDBQMjR1Ym05a1pWUjVjR1U5UFQw'
    || 'NFAyNHVjR0Z5Wlc1MFRtOWtaUzVwYm5ObGNuUkNaV1p2Y21Vb1pTeDBLVHB1TG1sdWMyVnlkRUpsWm05eVpTaGxMSFFwT2lodUxtNXZaR1ZVZVhCbFBUMDlP'
    || 'RDhvZEQxdUxuQmhjbVZ1ZEU1dlpHVXNkQzVwYm5ObGNuUkNaV1p2Y21Vb1pTeHVLU2s2S0hROWJpeDBMbUZ3Y0dWdVpFTm9hV3hrS0dVcEtTeHVQVzR1WDNK'
    || 'bFlXTjBVbTl2ZEVOdmJuUmhhVzVsY2l4dUlUMXVkV3hzZkh4MExtOXVZMnhwWTJzaFBUMXVkV3hzZkh3b2RDNXZibU5zYVdOclBXOXNLU2s3Wld4elpTQnBa'
    || 'aWh5SVQwOU5DWW1LR1U5WlM1amFHbHNaQ3hsSVQwOWJuVnNiQ2twWm05eUtFbHZLR1VzZEN4dUtTeGxQV1V1YzJsaWJHbHVaenRsSVQwOWJuVnNiRHNwU1c4'
    || 'b1pTeDBMRzRwTEdVOVpTNXphV0pzYVc1bmZXWjFibU4wYVc5dUlFRnZLR1VzZEN4dUtYdDJZWElnY2oxbExuUmhaenRwWmloeVBUMDlOWHg4Y2owOVBUWXBa'
    || 'VDFsTG5OMFlYUmxUbTlrWlN4MFAyNHVhVzV6WlhKMFFtVm1iM0psS0dVc2RDazZiaTVoY0hCbGJtUkRhR2xzWkNobEtUdGxiSE5sSUdsbUtISWhQVDAwSmlZ'
    || 'b1pUMWxMbU5vYVd4a0xHVWhQVDF1ZFd4c0tTbG1iM0lvUVc4b1pTeDBMRzRwTEdVOVpTNXphV0pzYVc1bk8yVWhQVDF1ZFd4c095bEJieWhsTEhRc2Jpa3Na'
    || 'VDFsTG5OcFlteHBibWQ5ZG1GeUlFRmxQVzUxYkd3c1ozUTlJVEU3Wm5WdVkzUnBiMjRnV25Rb1pTeDBMRzRwZTJadmNpaHVQVzR1WTJocGJHUTdiaUU5UFc1'
    || 'MWJHdzdLVUpoS0dVc2RDeHVLU3h1UFc0dWMybGliR2x1WjMxbWRXNWpkR2x2YmlCQ1lTaGxMSFFzYmlsN2FXWW9kM1FtSm5SNWNHVnZaaUIzZEM1dmJrTnZi'
    || 'VzFwZEVacFltVnlWVzV0YjNWdWREMDlJbVoxYm1OMGFXOXVJaWwwY25sN2QzUXViMjVEYjIxdGFYUkdhV0psY2xWdWJXOTFiblFvUW5Jc2JpbDlZMkYwWTJo'
    || 'N2ZYTjNhWFJqYUNodUxuUmhaeWw3WTJGelpTQTFPbFpsZkh4Q2JpaHVMSFFwTzJOaGMyVWdOanAyWVhJZ2NqMUJaU3hzUFdkME8wRmxQVzUxYkd3c1duUW9a'
    || 'U3gwTEc0cExFRmxQWElzWjNROWJDeEJaU0U5UFc1MWJHd21KaWhuZEQ4b1pUMUJaU3h1UFc0dWMzUmhkR1ZPYjJSbExHVXVibTlrWlZSNWNHVTlQVDA0UDJV'
    || 'dWNHRnlaVzUwVG05a1pTNXlaVzF2ZG1WRGFHbHNaQ2h1S1RwbExuSmxiVzkyWlVOb2FXeGtLRzRwS1RwQlpTNXlaVzF2ZG1WRGFHbHNaQ2h1TG5OMFlYUmxU'
    || 'bTlrWlNrcE8ySnlaV0ZyTzJOaGMyVWdNVGc2UVdVaFBUMXVkV3hzSmlZb1ozUS9LR1U5UVdVc2JqMXVMbk4wWVhSbFRtOWtaU3hsTG01dlpHVlVlWEJsUFQw'
    || 'OU9EOUhhU2hsTG5CaGNtVnVkRTV2WkdVc2JpazZaUzV1YjJSbFZIbHdaVDA5UFRFbUprZHBLR1VzYmlrc2FYSW9aU2twT2tkcEtFRmxMRzR1YzNSaGRHVk9i'
    || 'MlJsS1NrN1luSmxZV3M3WTJGelpTQTBPbkk5UVdVc2JEMW5kQ3hCWlQxdUxuTjBZWFJsVG05a1pTNWpiMjUwWVdsdVpYSkpibVp2TEdkMFBTRXdMRnAwS0dV'
    || 'c2RDeHVLU3hCWlQxeUxHZDBQV3c3WW5KbFlXczdZMkZ6WlNBd09tTmhjMlVnTVRFNlkyRnpaU0F4TkRwallYTmxJREUxT21sbUtDRldaU1ltS0hJOWJpNTFj'
    || 'R1JoZEdWUmRXVjFaU3h5SVQwOWJuVnNiQ1ltS0hJOWNpNXNZWE4wUldabVpXTjBMSEloUFQxdWRXeHNLU2twZTJ3OWNqMXlMbTVsZUhRN1pHOTdkbUZ5SUdr'
    || 'OWJDeHpQV2t1WkdWemRISnZlVHRwUFdrdWRHRm5MSE1oUFQxMmIybGtJREFtSmlnb2FTWXlLU0U5UFRCOGZDaHBKalFwSVQwOU1Da21KbEJ2S0c0c2RDeHpL'
    || 'U3hzUFd3dWJtVjRkSDEzYUdsc1pTaHNJVDA5Y2lsOVduUW9aU3gwTEc0cE8ySnlaV0ZyTzJOaGMyVWdNVHBwWmlnaFZtVW1KaWhDYmlodUxIUXBMSEk5Ymk1'
    || 'emRHRjBaVTV2WkdVc2RIbHdaVzltSUhJdVkyOXRjRzl1Wlc1MFYybHNiRlZ1Ylc5MWJuUTlQU0ptZFc1amRHbHZiaUlwS1hSeWVYdHlMbkJ5YjNCelBXNHVi'
    || 'V1Z0YjJsNlpXUlFjbTl3Y3l4eUxuTjBZWFJsUFc0dWJXVnRiMmw2WldSVGRHRjBaU3h5TG1OdmJYQnZibVZ1ZEZkcGJHeFZibTF2ZFc1MEtDbDlZMkYwWTJn'
    || 'b1pDbDdYMlVvYml4MExHUXBmVnAwS0dVc2RDeHVLVHRpY21WaGF6dGpZWE5sSURJeE9scDBLR1VzZEN4dUtUdGljbVZoYXp0allYTmxJREl5T200dWJXOWta'
    || 'U1l4UHloV1pUMG9jajFXWlNsOGZHNHViV1Z0YjJsNlpXUlRkR0YwWlNFOVBXNTFiR3dzV25Rb1pTeDBMRzRwTEZabFBYSXBPbHAwS0dVc2RDeHVLVHRpY21W'
    || 'aGF6dGtaV1poZFd4ME9scDBLR1VzZEN4dUtYMTlablZ1WTNScGIyNGdTR0VvWlNsN2RtRnlJSFE5WlM1MWNHUmhkR1ZSZFdWMVpUdHBaaWgwSVQwOWJuVnNi'
    || 'Q2w3WlM1MWNHUmhkR1ZSZFdWMVpUMXVkV3hzTzNaaGNpQnVQV1V1YzNSaGRHVk9iMlJsTzI0OVBUMXVkV3hzSmlZb2JqMWxMbk4wWVhSbFRtOWtaVDF1Wlhj'
    || 'Z1NHWXBMSFF1Wm05eVJXRmphQ2htZFc1amRHbHZiaWh5S1h0MllYSWdiRDFpWmk1aWFXNWtLRzUxYkd3c1pTeHlLVHR1TG1oaGN5aHlLWHg4S0c0dVlXUmtL'
    || 'SElwTEhJdWRHaGxiaWhzTEd3cEtYMHBmWDFtZFc1amRHbHZiaUI1ZENobExIUXBlM1poY2lCdVBYUXVaR1ZzWlhScGIyNXpPMmxtS0c0aFBUMXVkV3hzS1da'
    || 'dmNpaDJZWElnY2owd08zSThiaTVzWlc1bmRHZzdjaXNyS1h0MllYSWdiRDF1VzNKZE8zUnllWHQyWVhJZ2FUMWxMSE05ZEN4a1BYTTdaVHBtYjNJb08yUWhQ'
    || 'VDF1ZFd4c095bDdjM2RwZEdOb0tHUXVkR0ZuS1h0allYTmxJRFU2UVdVOVpDNXpkR0YwWlU1dlpHVXNaM1E5SVRFN1luSmxZV3NnWlR0allYTmxJRE02UVdV'
    || 'OVpDNXpkR0YwWlU1dlpHVXVZMjl1ZEdGcGJtVnlTVzVtYnl4bmREMGhNRHRpY21WaGF5QmxPMk5oYzJVZ05EcEJaVDFrTG5OMFlYUmxUbTlrWlM1amIyNTBZ'
    || 'V2x1WlhKSmJtWnZMR2QwUFNFd08ySnlaV0ZySUdWOVpEMWtMbkpsZEhWeWJuMXBaaWhCWlQwOVBXNTFiR3dwZEdoeWIzY2dSWEp5YjNJb1lTZ3hOakFwS1R0'
    || 'Q1lTaHBMSE1zYkNrc1FXVTliblZzYkN4bmREMGhNVHQyWVhJZ1pqMXNMbUZzZEdWeWJtRjBaVHRtSVQwOWJuVnNiQ1ltS0dZdWNtVjBkWEp1UFc1MWJHd3BM'
    || 'R3d1Y21WMGRYSnVQVzUxYkd4OVkyRjBZMmdvZVNsN1gyVW9iQ3gwTEhrcGZYMXBaaWgwTG5OMVluUnlaV1ZHYkdGbmN5WXhNamcxTkNsbWIzSW9kRDEwTG1O'
    || 'b2FXeGtPM1FoUFQxdWRXeHNPeWtrWVNoMExHVXBMSFE5ZEM1emFXSnNhVzVuZldaMWJtTjBhVzl1SUNSaEtHVXNkQ2w3ZG1GeUlHNDlaUzVoYkhSbGNtNWhk'
    || 'R1VzY2oxbExtWnNZV2R6TzNOM2FYUmphQ2hsTG5SaFp5bDdZMkZ6WlNBd09tTmhjMlVnTVRFNlkyRnpaU0F4TkRwallYTmxJREUxT21sbUtIbDBLSFFzWlNr'
    || 'c1EzUW9aU2tzY2lZMEtYdDBjbmw3UTNJb015eGxMR1V1Y21WMGRYSnVLU3hTYkNnekxHVXBmV05oZEdOb0tFMHBlMTlsS0dVc1pTNXlaWFIxY200c1RTbDlk'
    || 'SEo1ZTBOeUtEVXNaU3hsTG5KbGRIVnliaWw5WTJGMFkyZ29UU2w3WDJVb1pTeGxMbkpsZEhWeWJpeE5LWDE5WW5KbFlXczdZMkZ6WlNBeE9ubDBLSFFzWlNr'
    || 'c1EzUW9aU2tzY2lZMU1USW1KbTRoUFQxdWRXeHNKaVpDYmlodUxHNHVjbVYwZFhKdUtUdGljbVZoYXp0allYTmxJRFU2YVdZb2VYUW9kQ3hsS1N4RGRDaGxL'
    || 'U3h5SmpVeE1pWW1iaUU5UFc1MWJHd21Ka0p1S0c0c2JpNXlaWFIxY200cExHVXVabXhoWjNNbU16SXBlM1poY2lCc1BXVXVjM1JoZEdWT2IyUmxPM1J5ZVh0'
    || 'TGJpaHNMQ0lpS1gxallYUmphQ2hOS1h0ZlpTaGxMR1V1Y21WMGRYSnVMRTBwZlgxcFppaHlKalFtSmloc1BXVXVjM1JoZEdWT2IyUmxMR3doUFc1MWJHd3BL'
    || 'WHQyWVhJZ2FUMWxMbTFsYlc5cGVtVmtVSEp2Y0hNc2N6MXVJVDA5Ym5Wc2JEOXVMbTFsYlc5cGVtVmtVSEp2Y0hNNmFTeGtQV1V1ZEhsd1pTeG1QV1V1ZFhC'
    || 'a1lYUmxVWFZsZFdVN2FXWW9aUzUxY0dSaGRHVlJkV1YxWlQxdWRXeHNMR1loUFQxdWRXeHNLWFJ5ZVh0a1BUMDlJbWx1Y0hWMElpWW1hUzUwZVhCbFBUMDlJ'
    || 'bkpoWkdsdklpWW1hUzV1WVcxbElUMXVkV3hzSmlaNWN5aHNMR2twTEdScEtHUXNjeWs3ZG1GeUlIazlaR2tvWkN4cEtUdG1iM0lvY3owd08zTThaaTVzWlc1'
    || 'bmRHZzdjeXM5TWlsN2RtRnlJR3M5Wmx0elhTeE9QV1piY3lzeFhUdHJQVDA5SW5OMGVXeGxJajlPY3loc0xFNHBPbXM5UFQwaVpHRnVaMlZ5YjNWemJIbFRa'
    || 'WFJKYm01bGNraFVUVXdpUDJ0ektHd3NUaWs2YXowOVBTSmphR2xzWkhKbGJpSS9TMjRvYkN4T0tUcENLR3dzYXl4T0xIa3BmWE4zYVhSamFDaGtLWHRqWVhO'
    || 'bEltbHVjSFYwSWpwdmFTaHNMR2twTzJKeVpXRnJPMk5oYzJVaWRHVjRkR0Z5WldFaU9sOXpLR3dzYVNrN1luSmxZV3M3WTJGelpTSnpaV3hsWTNRaU9uWmhj'
    || 'aUJmUFd3dVgzZHlZWEJ3WlhKVGRHRjBaUzUzWVhOTmRXeDBhWEJzWlR0c0xsOTNjbUZ3Y0dWeVUzUmhkR1V1ZDJGelRYVnNkR2x3YkdVOUlTRnBMbTExYkhS'
    || 'cGNHeGxPM1poY2lCUFBXa3VkbUZzZFdVN1R5RTliblZzYkQ5ZmJpaHNMQ0VoYVM1dGRXeDBhWEJzWlN4UExDRXhLVHBmSVQwOUlTRnBMbTExYkhScGNHeGxK'
    || 'aVlvYVM1a1pXWmhkV3gwVm1Gc2RXVWhQVzUxYkd3L1gyNG9iQ3doSVdrdWJYVnNkR2x3YkdVc2FTNWtaV1poZFd4MFZtRnNkV1VzSVRBcE9sOXVLR3dzSVNG'
    || 'cExtMTFiSFJwY0d4bExHa3ViWFZzZEdsd2JHVS9XMTA2SWlJc0lURXBLWDFzVzNaeVhUMXBmV05oZEdOb0tFMHBlMTlsS0dVc1pTNXlaWFIxY200c1RTbDlm'
    || 'V0p5WldGck8yTmhjMlVnTmpwcFppaDVkQ2gwTEdVcExFTjBLR1VwTEhJbU5DbDdhV1lvWlM1emRHRjBaVTV2WkdVOVBUMXVkV3hzS1hSb2NtOTNJRVZ5Y205'
    || 'eUtHRW9NVFl5S1NrN2JEMWxMbk4wWVhSbFRtOWtaU3hwUFdVdWJXVnRiMmw2WldSUWNtOXdjenQwY25sN2JDNXViMlJsVm1Gc2RXVTlhWDFqWVhSamFDaE5L'
    || 'WHRmWlNobExHVXVjbVYwZFhKdUxFMHBmWDFpY21WaGF6dGpZWE5sSURNNmFXWW9lWFFvZEN4bEtTeERkQ2hsS1N4eUpqUW1KbTRoUFQxdWRXeHNKaVp1TG0x'
    || 'bGJXOXBlbVZrVTNSaGRHVXVhWE5FWldoNVpISmhkR1ZrS1hSeWVYdHBjaWgwTG1OdmJuUmhhVzVsY2tsdVptOHBmV05oZEdOb0tFMHBlMTlsS0dVc1pTNXla'
    || 'WFIxY200c1RTbDlZbkpsWVdzN1kyRnpaU0EwT25sMEtIUXNaU2tzUTNRb1pTazdZbkpsWVdzN1kyRnpaU0F4TXpwNWRDaDBMR1VwTEVOMEtHVXBMR3c5WlM1'
    || 'amFHbHNaQ3hzTG1ac1lXZHpKamd4T1RJbUppaHBQV3d1YldWdGIybDZaV1JUZEdGMFpTRTlQVzUxYkd3c2JDNXpkR0YwWlU1dlpHVXVhWE5JYVdSa1pXNDlh'
    || 'U3doYVh4OGJDNWhiSFJsY201aGRHVWhQVDF1ZFd4c0ppWnNMbUZzZEdWeWJtRjBaUzV0WlcxdmFYcGxaRk4wWVhSbElUMDliblZzYkh4OEtGVnZQWGRsS0Nr'
    || 'cEtTeHlKalFtSmtoaEtHVXBPMkp5WldGck8yTmhjMlVnTWpJNmFXWW9hejF1SVQwOWJuVnNiQ1ltYmk1dFpXMXZhWHBsWkZOMFlYUmxJVDA5Ym5Wc2JDeGxM'
    || 'bTF2WkdVbU1UOG9WbVU5S0hrOVZtVXBmSHhyTEhsMEtIUXNaU2tzVm1VOWVTazZlWFFvZEN4bEtTeERkQ2hsS1N4eUpqZ3hPVElwZTJsbUtIazlaUzV0Wlcx'
    || 'dmFYcGxaRk4wWVhSbElUMDliblZzYkN3b1pTNXpkR0YwWlU1dlpHVXVhWE5JYVdSa1pXNDllU2ttSmlGckppWW9aUzV0YjJSbEpqRXBJVDA5TUNsbWIzSW9V'
    || 'RDFsTEdzOVpTNWphR2xzWkR0cklUMDliblZzYkRzcGUyWnZjaWhPUFZBOWF6dFFJVDA5Ym5Wc2JEc3BlM04zYVhSamFDaGZQVkFzVHoxZkxtTm9hV3hrTEY4'
    || 'dWRHRm5LWHRqWVhObElEQTZZMkZ6WlNBeE1UcGpZWE5sSURFME9tTmhjMlVnTVRVNlEzSW9OQ3hmTEY4dWNtVjBkWEp1S1R0aWNtVmhhenRqWVhObElERTZR'
    || 'bTRvWHl4ZkxuSmxkSFZ5YmlrN2RtRnlJRWs5WHk1emRHRjBaVTV2WkdVN2FXWW9kSGx3Wlc5bUlFa3VZMjl0Y0c5dVpXNTBWMmxzYkZWdWJXOTFiblE5UFNK'
    || 'bWRXNWpkR2x2YmlJcGUzSTlYeXh1UFY4dWNtVjBkWEp1TzNSeWVYdDBQWElzU1M1d2NtOXdjejEwTG0xbGJXOXBlbVZrVUhKdmNITXNTUzV6ZEdGMFpUMTBM'
    || 'bTFsYlc5cGVtVmtVM1JoZEdVc1NTNWpiMjF3YjI1bGJuUlhhV3hzVlc1dGIzVnVkQ2dwZldOaGRHTm9LRTBwZTE5bEtISXNiaXhOS1gxOVluSmxZV3M3WTJG'
    || 'elpTQTFPa0p1S0Y4c1h5NXlaWFIxY200cE8ySnlaV0ZyTzJOaGMyVWdNakk2YVdZb1h5NXRaVzF2YVhwbFpGTjBZWFJsSVQwOWJuVnNiQ2w3UjJFb1RpazdZ'
    || 'Mjl1ZEdsdWRXVjlmVThoUFQxdWRXeHNQeWhQTG5KbGRIVnliajFmTEZBOVR5azZSMkVvVGlsOWF6MXJMbk5wWW14cGJtZDlaVHBtYjNJb2F6MXVkV3hzTEU0'
    || 'OVpUczdLWHRwWmloT0xuUmhaejA5UFRVcGUybG1LR3M5UFQxdWRXeHNLWHRyUFU0N2RISjVlMnc5VGk1emRHRjBaVTV2WkdVc2VUOG9hVDFzTG5OMGVXeGxM'
    || 'SFI1Y0dWdlppQnBMbk5sZEZCeWIzQmxjblI1UFQwaVpuVnVZM1JwYjI0aVAya3VjMlYwVUhKdmNHVnlkSGtvSW1ScGMzQnNZWGtpTENKdWIyNWxJaXdpYVcx'
    || 'd2IzSjBZVzUwSWlrNmFTNWthWE53YkdGNVBTSnViMjVsSWlrNktHUTlUaTV6ZEdGMFpVNXZaR1VzWmoxT0xtMWxiVzlwZW1Wa1VISnZjSE11YzNSNWJHVXNj'
    || 'ejFtSVQxdWRXeHNKaVptTG1oaGMwOTNibEJ5YjNCbGNuUjVLQ0prYVhOd2JHRjVJaWsvWmk1a2FYTndiR0Y1T201MWJHd3NaQzV6ZEhsc1pTNWthWE53YkdG'
    || 'NVBXcHpLQ0prYVhOd2JHRjVJaXh6S1NsOVkyRjBZMmdvVFNsN1gyVW9aU3hsTG5KbGRIVnliaXhOS1gxOWZXVnNjMlVnYVdZb1RpNTBZV2M5UFQwMktYdHBa'
    || 'aWhyUFQwOWJuVnNiQ2wwY25sN1RpNXpkR0YwWlU1dlpHVXVibTlrWlZaaGJIVmxQWGsvSWlJNlRpNXRaVzF2YVhwbFpGQnliM0J6ZldOaGRHTm9LRTBwZTE5'
    || 'bEtHVXNaUzV5WlhSMWNtNHNUU2w5ZldWc2MyVWdhV1lvS0U0dWRHRm5JVDA5TWpJbUprNHVkR0ZuSVQwOU1qTjhmRTR1YldWdGIybDZaV1JUZEdGMFpUMDlQ'
    || 'VzUxYkd4OGZFNDlQVDFsS1NZbVRpNWphR2xzWkNFOVBXNTFiR3dwZTA0dVkyaHBiR1F1Y21WMGRYSnVQVTRzVGoxT0xtTm9hV3hrTzJOdmJuUnBiblZsZlds'
    || 'bUtFNDlQVDFsS1dKeVpXRnJJR1U3Wm05eUtEdE9Mbk5wWW14cGJtYzlQVDF1ZFd4c095bDdhV1lvVGk1eVpYUjFjbTQ5UFQxdWRXeHNmSHhPTG5KbGRIVnli'
    || 'ajA5UFdVcFluSmxZV3NnWlR0clBUMDlUaVltS0dzOWJuVnNiQ2tzVGoxT0xuSmxkSFZ5Ym4xclBUMDlUaVltS0dzOWJuVnNiQ2tzVGk1emFXSnNhVzVuTG5K'
    || 'bGRIVnliajFPTG5KbGRIVnliaXhPUFU0dWMybGliR2x1WjMxOVluSmxZV3M3WTJGelpTQXhPVHA1ZENoMExHVXBMRU4wS0dVcExISW1OQ1ltU0dFb1pTazdZ'
    || 'bkpsWVdzN1kyRnpaU0F5TVRwaWNtVmhhenRrWldaaGRXeDBPbmwwS0hRc1pTa3NRM1FvWlNsOWZXWjFibU4wYVc5dUlFTjBLR1VwZTNaaGNpQjBQV1V1Wm14'
    || 'aFozTTdhV1lvZENZeUtYdDBjbmw3WlRwN1ptOXlLSFpoY2lCdVBXVXVjbVYwZFhKdU8yNGhQVDF1ZFd4c095bDdhV1lvVjJFb2Jpa3BlM1poY2lCeVBXNDdZ'
    || 'bkpsWVdzZ1pYMXVQVzR1Y21WMGRYSnVmWFJvY205M0lFVnljbTl5S0dFb01UWXdLU2w5YzNkcGRHTm9LSEl1ZEdGbktYdGpZWE5sSURVNmRtRnlJR3c5Y2k1'
    || 'emRHRjBaVTV2WkdVN2NpNW1iR0ZuY3lZek1pWW1LRXR1S0d3c0lpSXBMSEl1Wm14aFozTW1QUzB6TXlrN2RtRnlJR2s5Vm1Fb1pTazdRVzhvWlN4cExHd3BP'
    || 'Mkp5WldGck8yTmhjMlVnTXpwallYTmxJRFE2ZG1GeUlITTljaTV6ZEdGMFpVNXZaR1V1WTI5dWRHRnBibVZ5U1c1bWJ5eGtQVlpoS0dVcE8wbHZLR1VzWkN4'
    || 'ektUdGljbVZoYXp0a1pXWmhkV3gwT25Sb2NtOTNJRVZ5Y205eUtHRW9NVFl4S1NsOWZXTmhkR05vS0dZcGUxOWxLR1VzWlM1eVpYUjFjbTRzWmlsOVpTNW1i'
    || 'R0ZuY3lZOUxUTjlkQ1kwTURrMkppWW9aUzVtYkdGbmN5WTlMVFF3T1RjcGZXWjFibU4wYVc5dUlGRm1LR1VzZEN4dUtYdFFQV1VzVVdFb1pTbDlablZ1WTNS'
    || 'cGIyNGdVV0VvWlN4MExHNHBlMlp2Y2loMllYSWdjajBvWlM1dGIyUmxKakVwSVQwOU1EdFFJVDA5Ym5Wc2JEc3BlM1poY2lCc1BWQXNhVDFzTG1Ob2FXeGtP'
    || 'MmxtS0d3dWRHRm5QVDA5TWpJbUpuSXBlM1poY2lCelBXd3ViV1Z0YjJsNlpXUlRkR0YwWlNFOVBXNTFiR3g4ZkZSc08ybG1LQ0Z6S1h0MllYSWdaRDFzTG1G'
    || 'c2RHVnlibUYwWlN4bVBXUWhQVDF1ZFd4c0ppWmtMbTFsYlc5cGVtVmtVM1JoZEdVaFBUMXVkV3hzZkh4V1pUdGtQVlJzTzNaaGNpQjVQVlpsTzJsbUtGUnNQ'
    || 'WE1zS0ZabFBXWXBKaVloZVNsbWIzSW9VRDFzTzFBaFBUMXVkV3hzT3lselBWQXNaajF6TG1Ob2FXeGtMSE11ZEdGblBUMDlNakltSm5NdWJXVnRiMmw2WldS'
    || 'VGRHRjBaU0U5UFc1MWJHdy9TMkVvYkNrNlppRTlQVzUxYkd3L0tHWXVjbVYwZFhKdVBYTXNVRDFtS1RwTFlTaHNLVHRtYjNJb08ya2hQVDF1ZFd4c095bFFQ'
    || 'V2tzVVdFb2FTa3NhVDFwTG5OcFlteHBibWM3VUQxc0xGUnNQV1FzVm1VOWVYMVpZU2hsS1gxbGJITmxLR3d1YzNWaWRISmxaVVpzWVdkekpqZzNOeklwSVQw'
    || 'OU1DWW1hU0U5UFc1MWJHdy9LR2t1Y21WMGRYSnVQV3dzVUQxcEtUcFpZU2hsS1gxOVpuVnVZM1JwYjI0Z1dXRW9aU2w3Wm05eUtEdFFJVDA5Ym5Wc2JEc3Bl'
    || 'M1poY2lCMFBWQTdhV1lvS0hRdVpteGhaM01tT0RjM01pa2hQVDB3S1h0MllYSWdiajEwTG1Gc2RHVnlibUYwWlR0MGNubDdhV1lvS0hRdVpteGhaM01tT0Rj'
    || 'M01pa2hQVDB3S1hOM2FYUmphQ2gwTG5SaFp5bDdZMkZ6WlNBd09tTmhjMlVnTVRFNlkyRnpaU0F4TlRwV1pYeDhVbXdvTlN4MEtUdGljbVZoYXp0allYTmxJ'
    || 'REU2ZG1GeUlISTlkQzV6ZEdGMFpVNXZaR1U3YVdZb2RDNW1iR0ZuY3lZMEppWWhWbVVwYVdZb2JqMDlQVzUxYkd3cGNpNWpiMjF3YjI1bGJuUkVhV1JOYjNW'
    || 'dWRDZ3BPMlZzYzJWN2RtRnlJR3c5ZEM1bGJHVnRaVzUwVkhsd1pUMDlQWFF1ZEhsd1pUOXVMbTFsYlc5cGVtVmtVSEp2Y0hNNmRuUW9kQzUwZVhCbExHNHVi'
    || 'V1Z0YjJsNlpXUlFjbTl3Y3lrN2NpNWpiMjF3YjI1bGJuUkVhV1JWY0dSaGRHVW9iQ3h1TG0xbGJXOXBlbVZrVTNSaGRHVXNjaTVmWDNKbFlXTjBTVzUwWlhK'
    || 'dVlXeFRibUZ3YzJodmRFSmxabTl5WlZWd1pHRjBaU2w5ZG1GeUlHazlkQzUxY0dSaGRHVlJkV1YxWlR0cElUMDliblZzYkNZbVIzVW9kQ3hwTEhJcE8ySnla'
    || 'V0ZyTzJOaGMyVWdNenAyWVhJZ2N6MTBMblZ3WkdGMFpWRjFaWFZsTzJsbUtITWhQVDF1ZFd4c0tYdHBaaWh1UFc1MWJHd3NkQzVqYUdsc1pDRTlQVzUxYkd3'
    || 'cGMzZHBkR05vS0hRdVkyaHBiR1F1ZEdGbktYdGpZWE5sSURVNmJqMTBMbU5vYVd4a0xuTjBZWFJsVG05a1pUdGljbVZoYXp0allYTmxJREU2YmoxMExtTm9h'
    || 'V3hrTG5OMFlYUmxUbTlrWlgxSGRTaDBMSE1zYmlsOVluSmxZV3M3WTJGelpTQTFPblpoY2lCa1BYUXVjM1JoZEdWT2IyUmxPMmxtS0c0OVBUMXVkV3hzSmla'
    || 'MExtWnNZV2R6SmpRcGUyNDlaRHQyWVhJZ1pqMTBMbTFsYlc5cGVtVmtVSEp2Y0hNN2MzZHBkR05vS0hRdWRIbHdaU2w3WTJGelpTSmlkWFIwYjI0aU9tTmhj'
    || 'MlVpYVc1d2RYUWlPbU5oYzJVaWMyVnNaV04wSWpwallYTmxJblJsZUhSaGNtVmhJanBtTG1GMWRHOUdiMk4xY3lZbWJpNW1iMk4xY3lncE8ySnlaV0ZyTzJO'
    || 'aGMyVWlhVzFuSWpwbUxuTnlZeVltS0c0dWMzSmpQV1l1YzNKaktYMTlZbkpsWVdzN1kyRnpaU0EyT21KeVpXRnJPMk5oYzJVZ05EcGljbVZoYXp0allYTmxJ'
    || 'REV5T21KeVpXRnJPMk5oYzJVZ01UTTZhV1lvZEM1dFpXMXZhWHBsWkZOMFlYUmxQVDA5Ym5Wc2JDbDdkbUZ5SUhrOWRDNWhiSFJsY201aGRHVTdhV1lvZVNF'
    || 'OVBXNTFiR3dwZTNaaGNpQnJQWGt1YldWdGIybDZaV1JUZEdGMFpUdHBaaWhySVQwOWJuVnNiQ2w3ZG1GeUlFNDlheTVrWldoNVpISmhkR1ZrTzA0aFBUMXVk'
    || 'V3hzSmlacGNpaE9LWDE5ZldKeVpXRnJPMk5oYzJVZ01UazZZMkZ6WlNBeE56cGpZWE5sSURJeE9tTmhjMlVnTWpJNlkyRnpaU0F5TXpwallYTmxJREkxT21K'
    || 'eVpXRnJPMlJsWm1GMWJIUTZkR2h5YjNjZ1JYSnliM0lvWVNneE5qTXBLWDFXWlh4OGRDNW1iR0ZuY3lZMU1USW1Ka3h2S0hRcGZXTmhkR05vS0Y4cGUxOWxL'
    || 'SFFzZEM1eVpYUjFjbTRzWHlsOWZXbG1LSFE5UFQxbEtYdFFQVzUxYkd3N1luSmxZV3Q5YVdZb2JqMTBMbk5wWW14cGJtY3NiaUU5UFc1MWJHd3BlMjR1Y21W'
    || 'MGRYSnVQWFF1Y21WMGRYSnVMRkE5Ymp0aWNtVmhhMzFRUFhRdWNtVjBkWEp1ZlgxbWRXNWpkR2x2YmlCSFlTaGxLWHRtYjNJb08xQWhQVDF1ZFd4c095bDdk'
    || 'bUZ5SUhROVVEdHBaaWgwUFQwOVpTbDdVRDF1ZFd4c08ySnlaV0ZyZlhaaGNpQnVQWFF1YzJsaWJHbHVaenRwWmlodUlUMDliblZzYkNsN2JpNXlaWFIxY200'
    || 'OWRDNXlaWFIxY200c1VEMXVPMkp5WldGcmZWQTlkQzV5WlhSMWNtNTlmV1oxYm1OMGFXOXVJRXRoS0dVcGUyWnZjaWc3VUNFOVBXNTFiR3c3S1h0MllYSWdk'
    || 'RDFRTzNSeWVYdHpkMmwwWTJnb2RDNTBZV2NwZTJOaGMyVWdNRHBqWVhObElERXhPbU5oYzJVZ01UVTZkbUZ5SUc0OWRDNXlaWFIxY200N2RISjVlMUpzS0RR'
    || 'c2RDbDlZMkYwWTJnb1ppbDdYMlVvZEN4dUxHWXBmV0p5WldGck8yTmhjMlVnTVRwMllYSWdjajEwTG5OMFlYUmxUbTlrWlR0cFppaDBlWEJsYjJZZ2NpNWpi'
    || 'MjF3YjI1bGJuUkVhV1JOYjNWdWREMDlJbVoxYm1OMGFXOXVJaWw3ZG1GeUlHdzlkQzV5WlhSMWNtNDdkSEo1ZTNJdVkyOXRjRzl1Wlc1MFJHbGtUVzkxYm5R'
    || 'b0tYMWpZWFJqYUNobUtYdGZaU2gwTEd3c1ppbDlmWFpoY2lCcFBYUXVjbVYwZFhKdU8zUnllWHRNYnloMEtYMWpZWFJqYUNobUtYdGZaU2gwTEdrc1ppbDlZ'
    || 'bkpsWVdzN1kyRnpaU0ExT25aaGNpQnpQWFF1Y21WMGRYSnVPM1J5ZVh0TWJ5aDBLWDFqWVhSamFDaG1LWHRmWlNoMExITXNaaWw5ZlgxallYUmphQ2htS1h0'
    || 'ZlpTaDBMSFF1Y21WMGRYSnVMR1lwZldsbUtIUTlQVDFsS1h0UVBXNTFiR3c3WW5KbFlXdDlkbUZ5SUdROWRDNXphV0pzYVc1bk8ybG1LR1FoUFQxdWRXeHNL'
    || 'WHRrTG5KbGRIVnliajEwTG5KbGRIVnliaXhRUFdRN1luSmxZV3Q5VUQxMExuSmxkSFZ5Ym4xOWRtRnlJRmxtUFUxaGRHZ3VZMlZwYkN4RWJEMUxMbEpsWVdO'
    || 'MFEzVnljbVZ1ZEVScGMzQmhkR05vWlhJc1RXODlTeTVTWldGamRFTjFjbkpsYm5SUGQyNWxjaXhoZEQxTExsSmxZV04wUTNWeWNtVnVkRUpoZEdOb1EyOXVa'
    || 'bWxuTEc1bFBUQXNUMlU5Ym5Wc2JDeE9aVDF1ZFd4c0xFMWxQVEFzY25ROU1DeEliajFSZENnd0tTeFNaVDB3TEZSeVBXNTFiR3dzYlc0OU1DeFBiRDB3TEhw'
    || 'dlBUQXNVbkk5Ym5Wc2JDeFlaVDF1ZFd4c0xGVnZQVEFzSkc0OU1TOHdMRUYwUFc1MWJHd3NVR3c5SVRFc1JtODliblZzYkN4eGREMXVkV3hzTEV4c1BTRXhM'
    || 'RXAwUFc1MWJHd3NTV3c5TUN4RWNqMHdMRmR2UFc1MWJHd3NRV3c5TFRFc1RXdzlNRHRtZFc1amRHbHZiaUJJWlNncGUzSmxkSFZ5YmlodVpTWTJLU0U5UFRB'
    || 'L2QyVW9LVHBCYkNFOVBTMHhQMEZzT2tGc1BYZGxLQ2w5Wm5WdVkzUnBiMjRnWW5Rb1pTbDdjbVYwZFhKdUtHVXViVzlrWlNZeEtUMDlQVEEvTVRvb2JtVW1N'
    || 'aWtoUFQwd0ppWk5aU0U5UFRBL1RXVW1MVTFsT2xKbUxuUnlZVzV6YVhScGIyNGhQVDF1ZFd4c1B5aE5iRDA5UFRBbUppaE5iRDFXY3lncEtTeE5iQ2s2S0dV'
    || 'OWRXVXNaU0U5UFRCOGZDaGxQWGRwYm1SdmR5NWxkbVZ1ZEN4bFBXVTlQVDEyYjJsa0lEQS9NVFk2V25Nb1pTNTBlWEJsS1Nrc1pTbDlablZ1WTNScGIyNGdl'
    || 'SFFvWlN4MExHNHNjaWw3YVdZb05UQThSSElwZEdoeWIzY2dSSEk5TUN4WGJ6MXVkV3hzTEVWeWNtOXlLR0VvTVRnMUtTazdaWElvWlN4dUxISXBMQ2dvYm1V'
    || 'bU1pazlQVDB3Zkh4bElUMDlUMlVwSmlZb1pUMDlQVTlsSmlZb0tHNWxKaklwUFQwOU1DWW1LRTlzZkQxdUtTeFNaVDA5UFRRbUptVnVLR1VzVFdVcEtTeGFa'
    || 'U2hsTEhJcExHNDlQVDB4SmladVpUMDlQVEFtSmloMExtMXZaR1VtTVNrOVBUMHdKaVlvSkc0OWQyVW9LU3MxTURBc1kyd21Ka2QwS0NrcEtYMW1kVzVqZEds'
    || 'dmJpQmFaU2hsTEhRcGUzWmhjaUJ1UFdVdVkyRnNiR0poWTJ0T2IyUmxPMVJrS0dVc2RDazdkbUZ5SUhJOVVYSW9aU3hsUFQwOVQyVS9UV1U2TUNrN2FXWW9j'
    || 'ajA5UFRBcGJpRTlQVzUxYkd3bUpsVnpLRzRwTEdVdVkyRnNiR0poWTJ0T2IyUmxQVzUxYkd3c1pTNWpZV3hzWW1GamExQnlhVzl5YVhSNVBUQTdaV3h6WlNC'
    || 'cFppaDBQWEltTFhJc1pTNWpZV3hzWW1GamExQnlhVzl5YVhSNUlUMDlkQ2w3YVdZb2JpRTliblZzYkNZbVZYTW9iaWtzZEQwOVBURXBaUzUwWVdjOVBUMHdQ'
    || 'MVJtS0ZwaExtSnBibVFvYm5Wc2JDeGxLU2s2UVhVb1dtRXVZbWx1WkNodWRXeHNMR1VwS1N4clppaG1kVzVqZEdsdmJpZ3BleWh1WlNZMktUMDlQVEFtSmtk'
    || 'MEtDbDlLU3h1UFc1MWJHdzdaV3h6Wlh0emQybDBZMmdvUW5Nb2Npa3BlMk5oYzJVZ01UcHVQWGxwTzJKeVpXRnJPMk5oYzJVZ05EcHVQVVp6TzJKeVpXRnJP'
    || 'Mk5oYzJVZ01UWTZiajFXY2p0aWNtVmhhenRqWVhObElEVXpOamczTURreE1qcHVQVmR6TzJKeVpXRnJPMlJsWm1GMWJIUTZiajFXY24xdVBXeGpLRzRzV0dF'
    || 'dVltbHVaQ2h1ZFd4c0xHVXBLWDFsTG1OaGJHeGlZV05yVUhKcGIzSnBkSGs5ZEN4bExtTmhiR3hpWVdOclRtOWtaVDF1ZlgxbWRXNWpkR2x2YmlCWVlTaGxM'
    || 'SFFwZTJsbUtFRnNQUzB4TEUxc1BUQXNLRzVsSmpZcElUMDlNQ2wwYUhKdmR5QkZjbkp2Y2loaEtETXlOeWtwTzNaaGNpQnVQV1V1WTJGc2JHSmhZMnRPYjJS'
    || 'bE8ybG1LRkZ1S0NrbUptVXVZMkZzYkdKaFkydE9iMlJsSVQwOWJpbHlaWFIxY200Z2JuVnNiRHQyWVhJZ2NqMVJjaWhsTEdVOVBUMVBaVDlOWlRvd0tUdHBa'
    || 'aWh5UFQwOU1DbHlaWFIxY200Z2JuVnNiRHRwWmlnb2NpWXpNQ2toUFQwd2ZId29jaVpsTG1WNGNHbHlaV1JNWVc1bGN5a2hQVDB3Zkh4MEtYUTllbXdvWlN4'
    || 'eUtUdGxiSE5sZTNROWNqdDJZWElnYkQxdVpUdHVaWHc5TWp0MllYSWdhVDFLWVNncE95aFBaU0U5UFdWOGZFMWxJVDA5ZENrbUppaEJkRDF1ZFd4c0xDUnVQ'
    || 'WGRsS0Nrck5UQXdMR2R1S0dVc2RDa3BPMlJ2SUhSeWVYdFlaaWdwTzJKeVpXRnJmV05oZEdOb0tHUXBlM0ZoS0dVc1pDbDlkMmhwYkdVb0lUQXBPM0p2S0Nr'
    || 'c1JHd3VZM1Z5Y21WdWREMXBMRzVsUFd3c1RtVWhQVDF1ZFd4c1AzUTlNRG9vVDJVOWJuVnNiQ3hOWlQwd0xIUTlVbVVwZldsbUtIUWhQVDB3S1h0cFppaDBQ'
    || 'VDA5TWlZbUtHdzllR2tvWlNrc2JDRTlQVEFtSmloeVBXd3NkRDFXYnlobExHd3BLU2tzZEQwOVBURXBkR2h5YjNjZ2JqMVVjaXhuYmlobExEQXBMR1Z1S0dV'
    || 'c2Npa3NXbVVvWlN4M1pTZ3BLU3h1TzJsbUtIUTlQVDAyS1dWdUtHVXNjaWs3Wld4elpYdHBaaWhzUFdVdVkzVnljbVZ1ZEM1aGJIUmxjbTVoZEdVc0tISW1N'
    || 'ekFwUFQwOU1DWW1JVWRtS0d3cEppWW9kRDE2YkNobExISXBMSFE5UFQweUppWW9hVDE0YVNobEtTeHBJVDA5TUNZbUtISTlhU3gwUFZadktHVXNhU2twS1N4'
    || 'MFBUMDlNU2twZEdoeWIzY2diajFVY2l4bmJpaGxMREFwTEdWdUtHVXNjaWtzV21Vb1pTeDNaU2dwS1N4dU8zTjNhWFJqYUNobExtWnBibWx6YUdWa1YyOXlh'
    || 'ejFzTEdVdVptbHVhWE5vWldSTVlXNWxjejF5TEhRcGUyTmhjMlVnTURwallYTmxJREU2ZEdoeWIzY2dSWEp5YjNJb1lTZ3pORFVwS1R0allYTmxJREk2ZVc0'
    || 'b1pTeFlaU3hCZENrN1luSmxZV3M3WTJGelpTQXpPbWxtS0dWdUtHVXNjaWtzS0hJbU1UTXdNREl6TkRJMEtUMDlQWEltSmloMFBWVnZLelV3TUMxM1pTZ3BM'
    || 'REV3UEhRcEtYdHBaaWhSY2lobExEQXBJVDA5TUNsaWNtVmhhenRwWmloc1BXVXVjM1Z6Y0dWdVpHVmtUR0Z1WlhNc0tHd21jaWtoUFQxeUtYdElaU2dwTEdV'
    || 'dWNHbHVaMlZrVEdGdVpYTjhQV1V1YzNWemNHVnVaR1ZrVEdGdVpYTW1iRHRpY21WaGEzMWxMblJwYldWdmRYUklZVzVrYkdVOVdXa29lVzR1WW1sdVpDaHVk'
    || 'V3hzTEdVc1dHVXNRWFFwTEhRcE8ySnlaV0ZyZlhsdUtHVXNXR1VzUVhRcE8ySnlaV0ZyTzJOaGMyVWdORHBwWmlobGJpaGxMSElwTENoeUpqUXhPVFF5TkRB'
    || 'cFBUMDljaWxpY21WaGF6dG1iM0lvZEQxbExtVjJaVzUwVkdsdFpYTXNiRDB0TVRzd1BISTdLWHQyWVhJZ2N6MHpNUzF3ZENoeUtUdHBQVEU4UEhNc2N6MTBX'
    || 'M05kTEhNK2JDWW1LR3c5Y3lrc2NpWTlmbWw5YVdZb2NqMXNMSEk5ZDJVb0tTMXlMSEk5S0RFeU1ENXlQekV5TURvME9EQStjajgwT0RBNk1UQTRNRDV5UHpF'
    || 'd09EQTZNVGt5TUQ1eVB6RTVNakE2TTJVelBuSS9NMlV6T2pRek1qQStjajgwTXpJd09qRTVOakFxV1dZb2NpOHhPVFl3S1NrdGNpd3hNRHh5S1h0bExuUnBi'
    || 'V1Z2ZFhSSVlXNWtiR1U5V1drb2VXNHVZbWx1WkNodWRXeHNMR1VzV0dVc1FYUXBMSElwTzJKeVpXRnJmWGx1S0dVc1dHVXNRWFFwTzJKeVpXRnJPMk5oYzJV'
    || 'Z05UcDViaWhsTEZobExFRjBLVHRpY21WaGF6dGtaV1poZFd4ME9uUm9jbTkzSUVWeWNtOXlLR0VvTXpJNUtTbDlmWDF5WlhSMWNtNGdXbVVvWlN4M1pTZ3BL'
    || 'U3hsTG1OaGJHeGlZV05yVG05a1pUMDlQVzQvV0dFdVltbHVaQ2h1ZFd4c0xHVXBPbTUxYkd4OVpuVnVZM1JwYjI0Z1ZtOG9aU3gwS1h0MllYSWdiajFTY2p0'
    || 'eVpYUjFjbTRnWlM1amRYSnlaVzUwTG0xbGJXOXBlbVZrVTNSaGRHVXVhWE5FWldoNVpISmhkR1ZrSmlZb1oyNG9aU3gwS1M1bWJHRm5jM3c5TWpVMktTeGxQ'
    || 'WHBzS0dVc2RDa3NaU0U5UFRJbUppaDBQVmhsTEZobFBXNHNkQ0U5UFc1MWJHd21Ka0p2S0hRcEtTeGxmV1oxYm1OMGFXOXVJRUp2S0dVcGUxaGxQVDA5Ym5W'
    || 'c2JEOVlaVDFsT2xobExuQjFjMmd1WVhCd2JIa29XR1VzWlNsOVpuVnVZM1JwYjI0Z1IyWW9aU2w3Wm05eUtIWmhjaUIwUFdVN095bDdhV1lvZEM1bWJHRm5j'
    || 'eVl4TmpNNE5DbDdkbUZ5SUc0OWRDNTFjR1JoZEdWUmRXVjFaVHRwWmlodUlUMDliblZzYkNZbUtHNDliaTV6ZEc5eVpYTXNiaUU5UFc1MWJHd3BLV1p2Y2lo'
    || 'MllYSWdjajB3TzNJOGJpNXNaVzVuZEdnN2Npc3JLWHQyWVhJZ2JEMXVXM0pkTEdrOWJDNW5aWFJUYm1Gd2MyaHZkRHRzUFd3dWRtRnNkV1U3ZEhKNWUybG1L'
    || 'Q0ZvZENocEtDa3NiQ2twY21WMGRYSnVJVEY5WTJGMFkyaDdjbVYwZFhKdUlURjlmWDFwWmlodVBYUXVZMmhwYkdRc2RDNXpkV0owY21WbFJteGhaM01tTVRZ'
    || 'ek9EUW1KbTRoUFQxdWRXeHNLVzR1Y21WMGRYSnVQWFFzZEQxdU8yVnNjMlY3YVdZb2REMDlQV1VwWW5KbFlXczdabTl5S0R0MExuTnBZbXhwYm1jOVBUMXVk'
    || 'V3hzT3lsN2FXWW9kQzV5WlhSMWNtNDlQVDF1ZFd4c2ZIeDBMbkpsZEhWeWJqMDlQV1VwY21WMGRYSnVJVEE3ZEQxMExuSmxkSFZ5Ym4xMExuTnBZbXhwYm1j'
    || 'dWNtVjBkWEp1UFhRdWNtVjBkWEp1TEhROWRDNXphV0pzYVc1bmZYMXlaWFIxY200aE1IMW1kVzVqZEdsdmJpQmxiaWhsTEhRcGUyWnZjaWgwSmoxK2VtOHNk'
    || 'Q1k5Zms5c0xHVXVjM1Z6Y0dWdVpHVmtUR0Z1WlhOOFBYUXNaUzV3YVc1blpXUk1ZVzVsY3lZOWZuUXNaVDFsTG1WNGNHbHlZWFJwYjI1VWFXMWxjenN3UEhR'
    || 'N0tYdDJZWElnYmowek1TMXdkQ2gwS1N4eVBURThQRzQ3WlZ0dVhUMHRNU3gwSmoxK2NuMTlablZ1WTNScGIyNGdXbUVvWlNsN2FXWW9LRzVsSmpZcElUMDlN'
    || 'Q2wwYUhKdmR5QkZjbkp2Y2loaEtETXlOeWtwTzFGdUtDazdkbUZ5SUhROVVYSW9aU3d3S1R0cFppZ29kQ1l4S1QwOVBUQXBjbVYwZFhKdUlGcGxLR1VzZDJV'
    || 'b0tTa3NiblZzYkR0MllYSWdiajE2YkNobExIUXBPMmxtS0dVdWRHRm5JVDA5TUNZbWJqMDlQVElwZTNaaGNpQnlQWGhwS0dVcE8zSWhQVDB3SmlZb2REMXlM'
    || 'RzQ5Vm04b1pTeHlLU2w5YVdZb2JqMDlQVEVwZEdoeWIzY2diajFVY2l4bmJpaGxMREFwTEdWdUtHVXNkQ2tzV21Vb1pTeDNaU2dwS1N4dU8ybG1LRzQ5UFQw'
    || 'MktYUm9jbTkzSUVWeWNtOXlLR0VvTXpRMUtTazdjbVYwZFhKdUlHVXVabWx1YVhOb1pXUlhiM0pyUFdVdVkzVnljbVZ1ZEM1aGJIUmxjbTVoZEdVc1pTNW1h'
    || 'VzVwYzJobFpFeGhibVZ6UFhRc2VXNG9aU3hZWlN4QmRDa3NXbVVvWlN4M1pTZ3BLU3h1ZFd4c2ZXWjFibU4wYVc5dUlFaHZLR1VzZENsN2RtRnlJRzQ5Ym1V'
    || 'N2JtVjhQVEU3ZEhKNWUzSmxkSFZ5YmlCbEtIUXBmV1pwYm1Gc2JIbDdibVU5Yml4dVpUMDlQVEFtSmlna2JqMTNaU2dwS3pVd01DeGpiQ1ltUjNRb0tTbDlm'
    || 'V1oxYm1OMGFXOXVJSFp1S0dVcGUwcDBJVDA5Ym5Wc2JDWW1TblF1ZEdGblBUMDlNQ1ltS0c1bEpqWXBQVDA5TUNZbVVXNG9LVHQyWVhJZ2REMXVaVHR1Wlh3'
    || 'OU1UdDJZWElnYmoxaGRDNTBjbUZ1YzJsMGFXOXVMSEk5ZFdVN2RISjVlMmxtS0dGMExuUnlZVzV6YVhScGIyNDliblZzYkN4MVpUMHhMR1VwY21WMGRYSnVJ'
    || 'R1VvS1gxbWFXNWhiR3g1ZTNWbFBYSXNZWFF1ZEhKaGJuTnBkR2x2YmoxdUxHNWxQWFFzS0c1bEpqWXBQVDA5TUNZbVIzUW9LWDE5Wm5WdVkzUnBiMjRnSkc4'
    || 'b0tYdHlkRDFJYmk1amRYSnlaVzUwTEdobEtFaHVLWDFtZFc1amRHbHZiaUJuYmlobExIUXBlMlV1Wm1sdWFYTm9aV1JYYjNKclBXNTFiR3dzWlM1bWFXNXBj'
    || 'MmhsWkV4aGJtVnpQVEE3ZG1GeUlHNDlaUzUwYVcxbGIzVjBTR0Z1Wkd4bE8ybG1LRzRoUFQwdE1TWW1LR1V1ZEdsdFpXOTFkRWhoYm1Sc1pUMHRNU3gzWmlo'
    || 'dUtTa3NUbVVoUFQxdWRXeHNLV1p2Y2lodVBVNWxMbkpsZEhWeWJqdHVJVDA5Ym5Wc2JEc3BlM1poY2lCeVBXNDdjM2RwZEdOb0tFcHBLSElwTEhJdWRHRm5L'
    || 'WHRqWVhObElERTZjajF5TG5SNWNHVXVZMmhwYkdSRGIyNTBaWGgwVkhsd1pYTXNjaUU5Ym5Wc2JDWW1kV3dvS1R0aWNtVmhhenRqWVhObElETTZWMjRvS1N4'
    || 'b1pTaFpaU2tzYUdVb1ZXVXBMR1p2S0NrN1luSmxZV3M3WTJGelpTQTFPbUZ2S0hJcE8ySnlaV0ZyTzJOaGMyVWdORHBYYmlncE8ySnlaV0ZyTzJOaGMyVWdN'
    || 'VE02YUdVb2VXVXBPMkp5WldGck8yTmhjMlVnTVRrNmFHVW9lV1VwTzJKeVpXRnJPMk5oYzJVZ01UQTZiRzhvY2k1MGVYQmxMbDlqYjI1MFpYaDBLVHRpY21W'
    || 'aGF6dGpZWE5sSURJeU9tTmhjMlVnTWpNNkpHOG9LWDF1UFc0dWNtVjBkWEp1ZldsbUtFOWxQV1VzVG1VOVpUMTBiaWhsTG1OMWNuSmxiblFzYm5Wc2JDa3NU'
    || 'V1U5Y25ROWRDeFNaVDB3TEZSeVBXNTFiR3dzZW04OVQydzliVzQ5TUN4WVpUMVNjajF1ZFd4c0xHWnVJVDA5Ym5Wc2JDbDdabTl5S0hROU1EdDBQR1p1TG14'
    || 'bGJtZDBhRHQwS3lzcGFXWW9iajFtYmx0MFhTeHlQVzR1YVc1MFpYSnNaV0YyWldRc2NpRTlQVzUxYkd3cGUyNHVhVzUwWlhKc1pXRjJaV1E5Ym5Wc2JEdDJZ'
    || 'WElnYkQxeUxtNWxlSFFzYVQxdUxuQmxibVJwYm1jN2FXWW9hU0U5UFc1MWJHd3BlM1poY2lCelBXa3VibVY0ZER0cExtNWxlSFE5YkN4eUxtNWxlSFE5YzMx'
    || 'dUxuQmxibVJwYm1jOWNuMW1iajF1ZFd4c2ZYSmxkSFZ5YmlCbGZXWjFibU4wYVc5dUlIRmhLR1VzZENsN1pHOTdkbUZ5SUc0OVRtVTdkSEo1ZTJsbUtISnZL'
    || 'Q2tzUld3dVkzVnljbVZ1ZEQxcmJDeGZiQ2w3Wm05eUtIWmhjaUJ5UFhobExtMWxiVzlwZW1Wa1UzUmhkR1U3Y2lFOVBXNTFiR3c3S1h0MllYSWdiRDF5TG5G'
    || 'MVpYVmxPMndoUFQxdWRXeHNKaVlvYkM1d1pXNWthVzVuUFc1MWJHd3BMSEk5Y2k1dVpYaDBmVjlzUFNFeGZXbG1LR2h1UFRBc1JHVTlWR1U5ZUdVOWJuVnNi'
    || 'Q3hUY2owaE1TeDNjajB3TEUxdkxtTjFjbkpsYm5ROWJuVnNiQ3h1UFQwOWJuVnNiSHg4Ymk1eVpYUjFjbTQ5UFQxdWRXeHNLWHRTWlQweExGUnlQWFFzVG1V'
    || 'OWJuVnNiRHRpY21WaGEzMWxPbnQyWVhJZ2FUMWxMSE05Ymk1eVpYUjFjbTRzWkQxdUxHWTlkRHRwWmloMFBVMWxMR1F1Wm14aFozTjhQVE15TnpZNExHWWhQ'
    || 'VDF1ZFd4c0ppWjBlWEJsYjJZZ1pqMDlJbTlpYW1WamRDSW1KblI1Y0dWdlppQm1MblJvWlc0OVBTSm1kVzVqZEdsdmJpSXBlM1poY2lCNVBXWXNhejFrTEU0'
    || 'OWF5NTBZV2M3YVdZb0tHc3ViVzlrWlNZeEtUMDlQVEFtSmloT1BUMDlNSHg4VGowOVBURXhmSHhPUFQwOU1UVXBLWHQyWVhJZ1h6MXJMbUZzZEdWeWJtRjBa'
    || 'VHRmUHlockxuVndaR0YwWlZGMVpYVmxQVjh1ZFhCa1lYUmxVWFZsZFdVc2F5NXRaVzF2YVhwbFpGTjBZWFJsUFY4dWJXVnRiMmw2WldSVGRHRjBaU3hyTG14'
    || 'aGJtVnpQVjh1YkdGdVpYTXBPaWhyTG5Wd1pHRjBaVkYxWlhWbFBXNTFiR3dzYXk1dFpXMXZhWHBsWkZOMFlYUmxQVzUxYkd3cGZYWmhjaUJQUFZOaEtITXBP'
    || 'MmxtS0U4aFBUMXVkV3hzS1h0UExtWnNZV2R6SmowdE1qVTNMSGRoS0U4c2N5eGtMR2tzZENrc1R5NXRiMlJsSmpFbUpsOWhLR2tzZVN4MEtTeDBQVThzWmox'
    || 'NU8zWmhjaUJKUFhRdWRYQmtZWFJsVVhWbGRXVTdhV1lvU1QwOVBXNTFiR3dwZTNaaGNpQk5QVzVsZHlCVFpYUTdUUzVoWkdRb1ppa3NkQzUxY0dSaGRHVlJk'
    || 'V1YxWlQxTmZXVnNjMlVnU1M1aFpHUW9aaWs3WW5KbFlXc2daWDFsYkhObGUybG1LQ2gwSmpFcFBUMDlNQ2w3WDJFb2FTeDVMSFFwTEZGdktDazdZbkpsWVdz'
    || 'Z1pYMW1QVVZ5Y205eUtHRW9OREkyS1NsOWZXVnNjMlVnYVdZb2RtVW1KbVF1Ylc5a1pTWXhLWHQyWVhJZ2EyVTlVMkVvY3lrN2FXWW9hMlVoUFQxdWRXeHNL'
    || 'WHNvYTJVdVpteGhaM01tTmpVMU16WXBQVDA5TUNZbUtHdGxMbVpzWVdkemZEMHlOVFlwTEhkaEtHdGxMSE1zWkN4cExIUXBMSFJ2S0ZadUtHWXNaQ2twTzJK'
    || 'eVpXRnJJR1Y5ZldrOVpqMVdiaWhtTEdRcExGSmxJVDA5TkNZbUtGSmxQVElwTEZKeVBUMDliblZzYkQ5U2NqMWJhVjA2VW5JdWNIVnphQ2hwS1N4cFBYTTda'
    || 'Rzk3YzNkcGRHTm9LR2t1ZEdGbktYdGpZWE5sSURNNmFTNW1iR0ZuYzN3OU5qVTFNellzZENZOUxYUXNhUzVzWVc1bGMzdzlkRHQyWVhJZ2RqMTRZU2hwTEdZ'
    || 'c2RDazdXWFVvYVN4MktUdGljbVZoYXlCbE8yTmhjMlVnTVRwa1BXWTdkbUZ5SUhBOWFTNTBlWEJsTEdjOWFTNXpkR0YwWlU1dlpHVTdhV1lvS0drdVpteGha'
    || 'M01tTVRJNEtUMDlQVEFtSmloMGVYQmxiMllnY0M1blpYUkVaWEpwZG1Wa1UzUmhkR1ZHY205dFJYSnliM0k5UFNKbWRXNWpkR2x2YmlKOGZHY2hQVDF1ZFd4'
    || 'c0ppWjBlWEJsYjJZZ1p5NWpiMjF3YjI1bGJuUkVhV1JEWVhSamFEMDlJbVoxYm1OMGFXOXVJaVltS0hGMFBUMDliblZzYkh4OElYRjBMbWhoY3lobktTa3BL'
    || 'WHRwTG1ac1lXZHpmRDAyTlRVek5peDBKajB0ZEN4cExteGhibVZ6ZkQxME8zWmhjaUJEUFVWaEtHa3NaQ3gwS1R0WmRTaHBMRU1wTzJKeVpXRnJJR1Y5Zldr'
    || 'OWFTNXlaWFIxY201OWQyaHBiR1VvYVNFOVBXNTFiR3dwZldWaktHNHBmV05oZEdOb0tFWXBlM1E5Uml4T1pUMDlQVzRtSm00aFBUMXVkV3hzSmlZb1RtVTli'
    || 'ajF1TG5KbGRIVnliaWs3WTI5dWRHbHVkV1Y5WW5KbFlXdDlkMmhwYkdVb0lUQXBmV1oxYm1OMGFXOXVJRXBoS0NsN2RtRnlJR1U5Ukd3dVkzVnljbVZ1ZER0'
    || 'eVpYUjFjbTRnUkd3dVkzVnljbVZ1ZEQxcmJDeGxQVDA5Ym5Wc2JEOXJiRHBsZldaMWJtTjBhVzl1SUZGdktDbDdLRkpsUFQwOU1IeDhVbVU5UFQwemZIeFNa'
    || 'VDA5UFRJcEppWW9VbVU5TkNrc1QyVTlQVDF1ZFd4c2ZId29iVzRtTWpZNE5ETTFORFUxS1QwOVBUQW1KaWhQYkNZeU5qZzBNelUwTlRVcFBUMDlNSHg4Wlc0'
    || 'b1QyVXNUV1VwZldaMWJtTjBhVzl1SUhwc0tHVXNkQ2w3ZG1GeUlHNDlibVU3Ym1WOFBUSTdkbUZ5SUhJOVNtRW9LVHNvVDJVaFBUMWxmSHhOWlNFOVBYUXBK'
    || 'aVlvUVhROWJuVnNiQ3huYmlobExIUXBLVHRrYnlCMGNubDdTMllvS1R0aWNtVmhhMzFqWVhSamFDaHNLWHR4WVNobExHd3BmWGRvYVd4bEtDRXdLVHRwWmlo'
    || 'eWJ5Z3BMRzVsUFc0c1JHd3VZM1Z5Y21WdWREMXlMRTVsSVQwOWJuVnNiQ2wwYUhKdmR5QkZjbkp2Y2loaEtESTJNU2twTzNKbGRIVnliaUJQWlQxdWRXeHNM'
    || 'RTFsUFRBc1VtVjlablZ1WTNScGIyNGdTMllvS1h0bWIzSW9PMDVsSVQwOWJuVnNiRHNwWW1Fb1RtVXBmV1oxYm1OMGFXOXVJRmhtS0NsN1ptOXlLRHRPWlNF'
    || 'OVBXNTFiR3dtSmlGNFpDZ3BPeWxpWVNoT1pTbDlablZ1WTNScGIyNGdZbUVvWlNsN2RtRnlJSFE5Y21Nb1pTNWhiSFJsY201aGRHVXNaU3h5ZENrN1pTNXRa'
    || 'VzF2YVhwbFpGQnliM0J6UFdVdWNHVnVaR2x1WjFCeWIzQnpMSFE5UFQxdWRXeHNQMlZqS0dVcE9rNWxQWFFzVFc4dVkzVnljbVZ1ZEQxdWRXeHNmV1oxYm1O'
    || 'MGFXOXVJR1ZqS0dVcGUzWmhjaUIwUFdVN1pHOTdkbUZ5SUc0OWRDNWhiSFJsY201aGRHVTdhV1lvWlQxMExuSmxkSFZ5Yml3b2RDNW1iR0ZuY3lZek1qYzJP'
    || 'Q2s5UFQwd0tYdHBaaWh1UFZabUtHNHNkQ3h5ZENrc2JpRTlQVzUxYkd3cGUwNWxQVzQ3Y21WMGRYSnVmWDFsYkhObGUybG1LRzQ5UW1Zb2JpeDBLU3h1SVQw'
    || 'OWJuVnNiQ2w3Ymk1bWJHRm5jeVk5TXpJM05qY3NUbVU5Ymp0eVpYUjFjbTU5YVdZb1pTRTlQVzUxYkd3cFpTNW1iR0ZuYzN3OU16STNOamdzWlM1emRXSjBj'
    || 'bVZsUm14aFozTTlNQ3hsTG1SbGJHVjBhVzl1Y3oxdWRXeHNPMlZzYzJWN1VtVTlOaXhPWlQxdWRXeHNPM0psZEhWeWJuMTlhV1lvZEQxMExuTnBZbXhwYm1j'
    || 'c2RDRTlQVzUxYkd3cGUwNWxQWFE3Y21WMGRYSnVmVTVsUFhROVpYMTNhR2xzWlNoMElUMDliblZzYkNrN1VtVTlQVDB3SmlZb1VtVTlOU2w5Wm5WdVkzUnBi'
    || 'MjRnZVc0b1pTeDBMRzRwZTNaaGNpQnlQWFZsTEd3OVlYUXVkSEpoYm5OcGRHbHZianQwY25sN1lYUXVkSEpoYm5OcGRHbHZiajF1ZFd4c0xIVmxQVEVzV21Z'
    || 'b1pTeDBMRzRzY2lsOVptbHVZV3hzZVh0aGRDNTBjbUZ1YzJsMGFXOXVQV3dzZFdVOWNuMXlaWFIxY200Z2JuVnNiSDFtZFc1amRHbHZiaUJhWmlobExIUXNi'
    || 'aXh5S1h0a2J5QlJiaWdwTzNkb2FXeGxLRXAwSVQwOWJuVnNiQ2s3YVdZb0tHNWxKallwSVQwOU1DbDBhSEp2ZHlCRmNuSnZjaWhoS0RNeU55a3BPMjQ5WlM1'
    || 'bWFXNXBjMmhsWkZkdmNtczdkbUZ5SUd3OVpTNW1hVzVwYzJobFpFeGhibVZ6TzJsbUtHNDlQVDF1ZFd4c0tYSmxkSFZ5YmlCdWRXeHNPMmxtS0dVdVptbHVh'
    || 'WE5vWldSWGIzSnJQVzUxYkd3c1pTNW1hVzVwYzJobFpFeGhibVZ6UFRBc2JqMDlQV1V1WTNWeWNtVnVkQ2wwYUhKdmR5QkZjbkp2Y2loaEtERTNOeWtwTzJV'
    || 'dVkyRnNiR0poWTJ0T2IyUmxQVzUxYkd3c1pTNWpZV3hzWW1GamExQnlhVzl5YVhSNVBUQTdkbUZ5SUdrOWJpNXNZVzVsYzN4dUxtTm9hV3hrVEdGdVpYTTdh'
    || 'V1lvVW1Rb1pTeHBLU3hsUFQwOVQyVW1KaWhPWlQxUFpUMXVkV3hzTEUxbFBUQXBMQ2h1TG5OMVluUnlaV1ZHYkdGbmN5WXlNRFkwS1QwOVBUQW1KaWh1TG1a'
    || 'c1lXZHpKakl3TmpRcFBUMDlNSHg4VEd4OGZDaE1iRDBoTUN4c1l5aFdjaXhtZFc1amRHbHZiaWdwZTNKbGRIVnliaUJSYmlncExHNTFiR3g5S1Nrc2FUMG9i'
    || 'aTVtYkdGbmN5WXhOVGs1TUNraFBUMHdMQ2h1TG5OMVluUnlaV1ZHYkdGbmN5WXhOVGs1TUNraFBUMHdmSHhwS1h0cFBXRjBMblJ5WVc1emFYUnBiMjRzWVhR'
    || 'dWRISmhibk5wZEdsdmJqMXVkV3hzTzNaaGNpQnpQWFZsTzNWbFBURTdkbUZ5SUdROWJtVTdibVY4UFRRc1RXOHVZM1Z5Y21WdWREMXVkV3hzTENSbUtHVXNi'
    || 'aWtzSkdFb2JpeGxLU3gyWmlna2FTa3NTM0k5SVNGSWFTd2thVDFJYVQxdWRXeHNMR1V1WTNWeWNtVnVkRDF1TEZGbUtHNHBMRVZrS0Nrc2JtVTlaQ3gxWlQx'
    || 'ekxHRjBMblJ5WVc1emFYUnBiMjQ5YVgxbGJITmxJR1V1WTNWeWNtVnVkRDF1TzJsbUtFeHNKaVlvVEd3OUlURXNTblE5WlN4SmJEMXNLU3hwUFdVdWNHVnVa'
    || 'R2x1WjB4aGJtVnpMR2s5UFQwd0ppWW9jWFE5Ym5Wc2JDa3NkMlFvYmk1emRHRjBaVTV2WkdVcExGcGxLR1VzZDJVb0tTa3NkQ0U5UFc1MWJHd3BabTl5S0hJ'
    || 'OVpTNXZibEpsWTI5MlpYSmhZbXhsUlhKeWIzSXNiajB3TzI0OGRDNXNaVzVuZEdnN2Jpc3JLV3c5ZEZ0dVhTeHlLR3d1ZG1Gc2RXVXNlMk52YlhCdmJtVnVk'
    || 'Rk4wWVdOck9td3VjM1JoWTJzc1pHbG5aWE4wT213dVpHbG5aWE4wZlNrN2FXWW9VR3dwZEdoeWIzY2dVR3c5SVRFc1pUMUdieXhHYnoxdWRXeHNMR1U3Y21W'
    || 'MGRYSnVLRWxzSmpFcElUMDlNQ1ltWlM1MFlXY2hQVDB3SmlaUmJpZ3BMR2s5WlM1d1pXNWthVzVuVEdGdVpYTXNLR2ttTVNraFBUMHdQMlU5UFQxWGJ6OUVj'
    || 'aXNyT2loRWNqMHdMRmR2UFdVcE9rUnlQVEFzUjNRb0tTeHVkV3hzZldaMWJtTjBhVzl1SUZGdUtDbDdhV1lvU25RaFBUMXVkV3hzS1h0MllYSWdaVDFDY3lo'
    || 'SmJDa3NkRDFoZEM1MGNtRnVjMmwwYVc5dUxHNDlkV1U3ZEhKNWUybG1LR0YwTG5SeVlXNXphWFJwYjI0OWJuVnNiQ3gxWlQweE5qNWxQekUyT21Vc1NuUTlQ'
    || 'VDF1ZFd4c0tYWmhjaUJ5UFNFeE8yVnNjMlY3YVdZb1pUMUtkQ3hLZEQxdWRXeHNMRWxzUFRBc0tHNWxKallwSVQwOU1DbDBhSEp2ZHlCRmNuSnZjaWhoS0RN'
    || 'ek1Ta3BPM1poY2lCc1BXNWxPMlp2Y2lodVpYdzlOQ3hRUFdVdVkzVnljbVZ1ZER0UUlUMDliblZzYkRzcGUzWmhjaUJwUFZBc2N6MXBMbU5vYVd4a08ybG1L'
    || 'Q2hRTG1ac1lXZHpKakUyS1NFOVBUQXBlM1poY2lCa1BXa3VaR1ZzWlhScGIyNXpPMmxtS0dRaFBUMXVkV3hzS1h0bWIzSW9kbUZ5SUdZOU1EdG1QR1F1YkdW'
    || 'dVozUm9PMllyS3lsN2RtRnlJSGs5WkZ0bVhUdG1iM0lvVUQxNU8xQWhQVDF1ZFd4c095bDdkbUZ5SUdzOVVEdHpkMmwwWTJnb2F5NTBZV2NwZTJOaGMyVWdN'
    || 'RHBqWVhObElERXhPbU5oYzJVZ01UVTZRM0lvT0N4ckxHa3BmWFpoY2lCT1BXc3VZMmhwYkdRN2FXWW9UaUU5UFc1MWJHd3BUaTV5WlhSMWNtNDlheXhRUFU0'
    || 'N1pXeHpaU0JtYjNJb08xQWhQVDF1ZFd4c095bDdhejFRTzNaaGNpQmZQV3N1YzJsaWJHbHVaeXhQUFdzdWNtVjBkWEp1TzJsbUtFWmhLR3NwTEdzOVBUMTVL'
    || 'WHRRUFc1MWJHdzdZbkpsWVd0OWFXWW9YeUU5UFc1MWJHd3BlMTh1Y21WMGRYSnVQVThzVUQxZk8ySnlaV0ZyZlZBOVQzMTlmWFpoY2lCSlBXa3VZV3gwWlhK'
    || 'dVlYUmxPMmxtS0VraFBUMXVkV3hzS1h0MllYSWdUVDFKTG1Ob2FXeGtPMmxtS0UwaFBUMXVkV3hzS1h0SkxtTm9hV3hrUFc1MWJHdzdaRzk3ZG1GeUlHdGxQ'
    || 'VTB1YzJsaWJHbHVaenROTG5OcFlteHBibWM5Ym5Wc2JDeE5QV3RsZlhkb2FXeGxLRTBoUFQxdWRXeHNLWDE5VUQxcGZYMXBaaWdvYVM1emRXSjBjbVZsUm14'
    || 'aFozTW1NakEyTkNraFBUMHdKaVp6SVQwOWJuVnNiQ2x6TG5KbGRIVnliajFwTEZBOWN6dGxiSE5sSUdVNlptOXlLRHRRSVQwOWJuVnNiRHNwZTJsbUtHazlV'
    || 'Q3dvYVM1bWJHRm5jeVl5TURRNEtTRTlQVEFwYzNkcGRHTm9LR2t1ZEdGbktYdGpZWE5sSURBNlkyRnpaU0F4TVRwallYTmxJREUxT2tOeUtEa3NhU3hwTG5K'
    || 'bGRIVnliaWw5ZG1GeUlIWTlhUzV6YVdKc2FXNW5PMmxtS0hZaFBUMXVkV3hzS1h0MkxuSmxkSFZ5YmoxcExuSmxkSFZ5Yml4UVBYWTdZbkpsWVdzZ1pYMVFQ'
    || 'V2t1Y21WMGRYSnVmWDEyWVhJZ2NEMWxMbU4xY25KbGJuUTdabTl5S0ZBOWNEdFFJVDA5Ym5Wc2JEc3BlM005VUR0MllYSWdaejF6TG1Ob2FXeGtPMmxtS0No'
    || 'ekxuTjFZblJ5WldWR2JHRm5jeVl5TURZMEtTRTlQVEFtSm1jaFBUMXVkV3hzS1djdWNtVjBkWEp1UFhNc1VEMW5PMlZzYzJVZ1pUcG1iM0lvY3oxd08xQWhQ'
    || 'VDF1ZFd4c095bDdhV1lvWkQxUUxDaGtMbVpzWVdkekpqSXdORGdwSVQwOU1DbDBjbmw3YzNkcGRHTm9LR1F1ZEdGbktYdGpZWE5sSURBNlkyRnpaU0F4TVRw'
    || 'allYTmxJREUxT2xKc0tEa3NaQ2w5ZldOaGRHTm9LRVlwZTE5bEtHUXNaQzV5WlhSMWNtNHNSaWw5YVdZb1pEMDlQWE1wZTFBOWJuVnNiRHRpY21WaGF5Qmxm'
    || 'WFpoY2lCRFBXUXVjMmxpYkdsdVp6dHBaaWhESVQwOWJuVnNiQ2w3UXk1eVpYUjFjbTQ5WkM1eVpYUjFjbTRzVUQxRE8ySnlaV0ZySUdWOVVEMWtMbkpsZEhW'
    || 'eWJuMTlhV1lvYm1VOWJDeEhkQ2dwTEhkMEppWjBlWEJsYjJZZ2QzUXViMjVRYjNOMFEyOXRiV2wwUm1saVpYSlNiMjkwUFQwaVpuVnVZM1JwYjI0aUtYUnll'
    || 'WHQzZEM1dmJsQnZjM1JEYjIxdGFYUkdhV0psY2xKdmIzUW9RbklzWlNsOVkyRjBZMmg3ZlhJOUlUQjljbVYwZFhKdUlISjlabWx1WVd4c2VYdDFaVDF1TEdG'
    || 'MExuUnlZVzV6YVhScGIyNDlkSDE5Y21WMGRYSnVJVEY5Wm5WdVkzUnBiMjRnZEdNb1pTeDBMRzRwZTNROVZtNG9iaXgwS1N4MFBYaGhLR1VzZEN3eEtTeGxQ'
    || 'VmgwS0dVc2RDd3hLU3gwUFVobEtDa3NaU0U5UFc1MWJHd21KaWhsY2lobExERXNkQ2tzV21Vb1pTeDBLU2w5Wm5WdVkzUnBiMjRnWDJVb1pTeDBMRzRwZTJs'
    || 'bUtHVXVkR0ZuUFQwOU15bDBZeWhsTEdVc2JpazdaV3h6WlNCbWIzSW9PM1FoUFQxdWRXeHNPeWw3YVdZb2RDNTBZV2M5UFQwektYdDBZeWgwTEdVc2JpazdZ'
    || 'bkpsWVd0OVpXeHpaU0JwWmloMExuUmhaejA5UFRFcGUzWmhjaUJ5UFhRdWMzUmhkR1ZPYjJSbE8ybG1LSFI1Y0dWdlppQjBMblI1Y0dVdVoyVjBSR1Z5YVha'
    || 'bFpGTjBZWFJsUm5KdmJVVnljbTl5UFQwaVpuVnVZM1JwYjI0aWZIeDBlWEJsYjJZZ2NpNWpiMjF3YjI1bGJuUkVhV1JEWVhSamFEMDlJbVoxYm1OMGFXOXVJ'
    || 'aVltS0hGMFBUMDliblZzYkh4OElYRjBMbWhoY3loeUtTa3BlMlU5Vm00b2JpeGxLU3hsUFVWaEtIUXNaU3d4S1N4MFBWaDBLSFFzWlN3eEtTeGxQVWhsS0Nr'
    || 'c2RDRTlQVzUxYkd3bUppaGxjaWgwTERFc1pTa3NXbVVvZEN4bEtTazdZbkpsWVd0OWZYUTlkQzV5WlhSMWNtNTlmV1oxYm1OMGFXOXVJSEZtS0dVc2RDeHVL'
    || 'WHQyWVhJZ2NqMWxMbkJwYm1kRFlXTm9aVHR5SVQwOWJuVnNiQ1ltY2k1a1pXeGxkR1VvZENrc2REMUlaU2dwTEdVdWNHbHVaMlZrVEdGdVpYTjhQV1V1YzNW'
    || 'emNHVnVaR1ZrVEdGdVpYTW1iaXhQWlQwOVBXVW1KaWhOWlNadUtUMDlQVzRtSmloU1pUMDlQVFI4ZkZKbFBUMDlNeVltS0UxbEpqRXpNREF5TXpReU5DazlQ'
    || 'VDFOWlNZbU5UQXdQbmRsS0NrdFZXOC9aMjRvWlN3d0tUcDZiM3c5Ymlrc1dtVW9aU3gwS1gxbWRXNWpkR2x2YmlCdVl5aGxMSFFwZTNROVBUMHdKaVlvS0dV'
    || 'dWJXOWtaU1l4S1QwOVBUQS9kRDB4T2loMFBTUnlMQ1J5UER3OU1Td29KSEltTVRNd01ESXpOREkwS1QwOVBUQW1KaWdrY2owME1UazBNekEwS1NrcE8zWmhj'
    || 'aUJ1UFVobEtDazdaVDFRZENobExIUXBMR1VoUFQxdWRXeHNKaVlvWlhJb1pTeDBMRzRwTEZwbEtHVXNiaWtwZldaMWJtTjBhVzl1SUVwbUtHVXBlM1poY2lC'
    || 'MFBXVXViV1Z0YjJsNlpXUlRkR0YwWlN4dVBUQTdkQ0U5UFc1MWJHd21KaWh1UFhRdWNtVjBjbmxNWVc1bEtTeHVZeWhsTEc0cGZXWjFibU4wYVc5dUlHSm1L'
    || 'R1VzZENsN2RtRnlJRzQ5TUR0emQybDBZMmdvWlM1MFlXY3BlMk5oYzJVZ01UTTZkbUZ5SUhJOVpTNXpkR0YwWlU1dlpHVXNiRDFsTG0xbGJXOXBlbVZrVTNS'
    || 'aGRHVTdiQ0U5UFc1MWJHd21KaWh1UFd3dWNtVjBjbmxNWVc1bEtUdGljbVZoYXp0allYTmxJREU1T25JOVpTNXpkR0YwWlU1dlpHVTdZbkpsWVdzN1pHVm1Z'
    || 'WFZzZERwMGFISnZkeUJGY25KdmNpaGhLRE14TkNrcGZYSWhQVDF1ZFd4c0ppWnlMbVJsYkdWMFpTaDBLU3h1WXlobExHNHBmWFpoY2lCeVl6dHlZejFtZFc1'
    || 'amRHbHZiaWhsTEhRc2JpbDdhV1lvWlNFOVBXNTFiR3dwYVdZb1pTNXRaVzF2YVhwbFpGQnliM0J6SVQwOWRDNXdaVzVrYVc1blVISnZjSE44ZkZsbExtTjFj'
    || 'bkpsYm5RcFMyVTlJVEE3Wld4elpYdHBaaWdvWlM1c1lXNWxjeVp1S1QwOVBUQW1KaWgwTG1ac1lXZHpKakV5T0NrOVBUMHdLWEpsZEhWeWJpQkxaVDBoTVN4'
    || 'WFppaGxMSFFzYmlrN1MyVTlLR1V1Wm14aFozTW1NVE14TURjeUtTRTlQVEI5Wld4elpTQkxaVDBoTVN4MlpTWW1LSFF1Wm14aFozTW1NVEEwT0RVM05pa2hQ'
    || 'VDB3SmlaTmRTaDBMR1pzTEhRdWFXNWtaWGdwTzNOM2FYUmphQ2gwTG14aGJtVnpQVEFzZEM1MFlXY3BlMk5oYzJVZ01qcDJZWElnY2oxMExuUjVjR1U3UTJ3'
    || 'b1pTeDBLU3hsUFhRdWNHVnVaR2x1WjFCeWIzQnpPM1poY2lCc1BVeHVLSFFzVldVdVkzVnljbVZ1ZENrN1JtNG9kQ3h1S1N4c1BXMXZLRzUxYkd3c2RDeHlM'
    || 'R1VzYkN4dUtUdDJZWElnYVQxMmJ5Z3BPM0psZEhWeWJpQjBMbVpzWVdkemZEMHhMSFI1Y0dWdlppQnNQVDBpYjJKcVpXTjBJaVltYkNFOVBXNTFiR3dtSm5S'
    || 'NWNHVnZaaUJzTG5KbGJtUmxjajA5SW1aMWJtTjBhVzl1SWlZbWJDNGtKSFI1Y0dWdlpqMDlQWFp2YVdRZ01EOG9kQzUwWVdjOU1TeDBMbTFsYlc5cGVtVmtV'
    || 'M1JoZEdVOWJuVnNiQ3gwTG5Wd1pHRjBaVkYxWlhWbFBXNTFiR3dzUjJVb2Npay9LR2s5SVRBc1lXd29kQ2twT21rOUlURXNkQzV0WlcxdmFYcGxaRk4wWVhS'
    || 'bFBXd3VjM1JoZEdVaFBUMXVkV3hzSmlac0xuTjBZWFJsSVQwOWRtOXBaQ0F3UDJ3dWMzUmhkR1U2Ym5Wc2JDeHpieWgwS1N4c0xuVndaR0YwWlhJOWFtd3Nk'
    || 'QzV6ZEdGMFpVNXZaR1U5YkN4c0xsOXlaV0ZqZEVsdWRHVnlibUZzY3oxMExGTnZLSFFzY2l4bExHNHBMSFE5VG04b2JuVnNiQ3gwTEhJc0lUQXNhU3h1S1Nr'
    || 'NktIUXVkR0ZuUFRBc2RtVW1KbWttSm5GcEtIUXBMRUpsS0c1MWJHd3NkQ3hzTEc0cExIUTlkQzVqYUdsc1pDa3NkRHRqWVhObElERTJPbkk5ZEM1bGJHVnRa'
    || 'VzUwVkhsd1pUdGxPbnR6ZDJsMFkyZ29RMndvWlN4MEtTeGxQWFF1Y0dWdVpHbHVaMUJ5YjNCekxHdzljaTVmYVc1cGRDeHlQV3dvY2k1ZmNHRjViRzloWkNr'
    || 'c2RDNTBlWEJsUFhJc2JEMTBMblJoWnoxMGNDaHlLU3hsUFhaMEtISXNaU2tzYkNsN1kyRnpaU0F3T25ROWFtOG9iblZzYkN4MExISXNaU3h1S1R0aWNtVmhh'
    || 'eUJsTzJOaGMyVWdNVHAwUFZKaEtHNTFiR3dzZEN4eUxHVXNiaWs3WW5KbFlXc2daVHRqWVhObElERXhPblE5YTJFb2JuVnNiQ3gwTEhJc1pTeHVLVHRpY21W'
    || 'aGF5QmxPMk5oYzJVZ01UUTZkRDFxWVNodWRXeHNMSFFzY2l4MmRDaHlMblI1Y0dVc1pTa3NiaWs3WW5KbFlXc2daWDEwYUhKdmR5QkZjbkp2Y2loaEtETXdO'
    || 'aXh5TENJaUtTbDljbVYwZFhKdUlIUTdZMkZ6WlNBd09uSmxkSFZ5YmlCeVBYUXVkSGx3WlN4c1BYUXVjR1Z1WkdsdVoxQnliM0J6TEd3OWRDNWxiR1Z0Wlc1'
    || 'MFZIbHdaVDA5UFhJL2JEcDJkQ2h5TEd3cExHcHZLR1VzZEN4eUxHd3NiaWs3WTJGelpTQXhPbkpsZEhWeWJpQnlQWFF1ZEhsd1pTeHNQWFF1Y0dWdVpHbHVa'
    || 'MUJ5YjNCekxHdzlkQzVsYkdWdFpXNTBWSGx3WlQwOVBYSS9iRHAyZENoeUxHd3BMRkpoS0dVc2RDeHlMR3dzYmlrN1kyRnpaU0F6T21VNmUybG1LRVJoS0hR'
    || 'cExHVTlQVDF1ZFd4c0tYUm9jbTkzSUVWeWNtOXlLR0VvTXpnM0tTazdjajEwTG5CbGJtUnBibWRRY205d2N5eHBQWFF1YldWdGIybDZaV1JUZEdGMFpTeHNQ'
    || 'V2t1Wld4bGJXVnVkQ3hSZFNobExIUXBMSGxzS0hRc2NpeHVkV3hzTEc0cE8zWmhjaUJ6UFhRdWJXVnRiMmw2WldSVGRHRjBaVHRwWmloeVBYTXVaV3hsYldW'
    || 'dWRDeHBMbWx6UkdWb2VXUnlZWFJsWkNscFppaHBQWHRsYkdWdFpXNTBPbklzYVhORVpXaDVaSEpoZEdWa09pRXhMR05oWTJobE9uTXVZMkZqYUdVc2NHVnVa'
    || 'R2x1WjFOMWMzQmxibk5sUW05MWJtUmhjbWxsY3pwekxuQmxibVJwYm1kVGRYTndaVzV6WlVKdmRXNWtZWEpwWlhNc2RISmhibk5wZEdsdmJuTTZjeTUwY21G'
    || 'dWMybDBhVzl1YzMwc2RDNTFjR1JoZEdWUmRXVjFaUzVpWVhObFUzUmhkR1U5YVN4MExtMWxiVzlwZW1Wa1UzUmhkR1U5YVN4MExtWnNZV2R6SmpJMU5pbDdi'
    || 'RDFXYmloRmNuSnZjaWhoS0RReU15a3BMSFFwTEhROVQyRW9aU3gwTEhJc2JpeHNLVHRpY21WaGF5QmxmV1ZzYzJVZ2FXWW9jaUU5UFd3cGUydzlWbTRvUlhK'
    || 'eWIzSW9ZU2cwTWpRcEtTeDBLU3gwUFU5aEtHVXNkQ3h5TEc0c2JDazdZbkpsWVdzZ1pYMWxiSE5sSUdadmNpaHVkRDBrZENoMExuTjBZWFJsVG05a1pTNWpi'
    || 'MjUwWVdsdVpYSkpibVp2TG1acGNuTjBRMmhwYkdRcExIUjBQWFFzZG1VOUlUQXNiWFE5Ym5Wc2JDeHVQVWgxS0hRc2JuVnNiQ3h5TEc0cExIUXVZMmhwYkdR'
    || 'OWJqdHVPeWx1TG1ac1lXZHpQVzR1Wm14aFozTW1MVE44TkRBNU5peHVQVzR1YzJsaWJHbHVaenRsYkhObGUybG1LRTF1S0Nrc2NqMDlQV3dwZTNROVNYUW9a'
    || 'U3gwTEc0cE8ySnlaV0ZySUdWOVFtVW9aU3gwTEhJc2JpbDlkRDEwTG1Ob2FXeGtmWEpsZEhWeWJpQjBPMk5oYzJVZ05UcHlaWFIxY200Z1MzVW9kQ2tzWlQw'
    || 'OVBXNTFiR3dtSm1WdktIUXBMSEk5ZEM1MGVYQmxMR3c5ZEM1d1pXNWthVzVuVUhKdmNITXNhVDFsSVQwOWJuVnNiRDlsTG0xbGJXOXBlbVZrVUhKdmNITTZi'
    || 'blZzYkN4elBXd3VZMmhwYkdSeVpXNHNVV2tvY2l4c0tUOXpQVzUxYkd3NmFTRTlQVzUxYkd3bUpsRnBLSElzYVNrbUppaDBMbVpzWVdkemZEMHpNaWtzVkdF'
    || 'b1pTeDBLU3hDWlNobExIUXNjeXh1S1N4MExtTm9hV3hrTzJOaGMyVWdOanB5WlhSMWNtNGdaVDA5UFc1MWJHd21KbVZ2S0hRcExHNTFiR3c3WTJGelpTQXhN'
    || 'enB5WlhSMWNtNGdVR0VvWlN4MExHNHBPMk5oYzJVZ05EcHlaWFIxY200Z2RXOG9kQ3gwTG5OMFlYUmxUbTlrWlM1amIyNTBZV2x1WlhKSmJtWnZLU3h5UFhR'
    || 'dWNHVnVaR2x1WjFCeWIzQnpMR1U5UFQxdWRXeHNQM1F1WTJocGJHUTllbTRvZEN4dWRXeHNMSElzYmlrNlFtVW9aU3gwTEhJc2Jpa3NkQzVqYUdsc1pEdGpZ'
    || 'WE5sSURFeE9uSmxkSFZ5YmlCeVBYUXVkSGx3WlN4c1BYUXVjR1Z1WkdsdVoxQnliM0J6TEd3OWRDNWxiR1Z0Wlc1MFZIbHdaVDA5UFhJL2JEcDJkQ2h5TEd3'
    || 'cExHdGhLR1VzZEN4eUxHd3NiaWs3WTJGelpTQTNPbkpsZEhWeWJpQkNaU2hsTEhRc2RDNXdaVzVrYVc1blVISnZjSE1zYmlrc2RDNWphR2xzWkR0allYTmxJ'
    || 'RGc2Y21WMGRYSnVJRUpsS0dVc2RDeDBMbkJsYm1ScGJtZFFjbTl3Y3k1amFHbHNaSEpsYml4dUtTeDBMbU5vYVd4a08yTmhjMlVnTVRJNmNtVjBkWEp1SUVK'
    || 'bEtHVXNkQ3gwTG5CbGJtUnBibWRRY205d2N5NWphR2xzWkhKbGJpeHVLU3gwTG1Ob2FXeGtPMk5oYzJVZ01UQTZaVHA3YVdZb2NqMTBMblI1Y0dVdVgyTnZi'
    || 'blJsZUhRc2JEMTBMbkJsYm1ScGJtZFFjbTl3Y3l4cFBYUXViV1Z0YjJsNlpXUlFjbTl3Y3l4elBXd3VkbUZzZFdVc1ptVW9iV3dzY2k1ZlkzVnljbVZ1ZEZa'
    || 'aGJIVmxLU3h5TGw5amRYSnlaVzUwVm1Gc2RXVTljeXhwSVQwOWJuVnNiQ2xwWmlob2RDaHBMblpoYkhWbExITXBLWHRwWmlocExtTm9hV3hrY21WdVBUMDli'
    || 'QzVqYUdsc1pISmxiaVltSVZsbExtTjFjbkpsYm5RcGUzUTlTWFFvWlN4MExHNHBPMkp5WldGcklHVjlmV1ZzYzJVZ1ptOXlLR2s5ZEM1amFHbHNaQ3hwSVQw'
    || 'OWJuVnNiQ1ltS0drdWNtVjBkWEp1UFhRcE8ya2hQVDF1ZFd4c095bDdkbUZ5SUdROWFTNWtaWEJsYm1SbGJtTnBaWE03YVdZb1pDRTlQVzUxYkd3cGUzTTlh'
    || 'UzVqYUdsc1pEdG1iM0lvZG1GeUlHWTlaQzVtYVhKemRFTnZiblJsZUhRN1ppRTlQVzUxYkd3N0tYdHBaaWhtTG1OdmJuUmxlSFE5UFQxeUtYdHBaaWhwTG5S'
    || 'aFp6MDlQVEVwZTJZOVRIUW9MVEVzYmlZdGJpa3NaaTUwWVdjOU1qdDJZWElnZVQxcExuVndaR0YwWlZGMVpYVmxPMmxtS0hraFBUMXVkV3hzS1h0NVBYa3Vj'
    || 'MmhoY21Wa08zWmhjaUJyUFhrdWNHVnVaR2x1Wnp0clBUMDliblZzYkQ5bUxtNWxlSFE5Wmpvb1ppNXVaWGgwUFdzdWJtVjRkQ3hyTG01bGVIUTlaaWtzZVM1'
    || 'd1pXNWthVzVuUFdaOWZXa3ViR0Z1WlhOOFBXNHNaajFwTG1Gc2RHVnlibUYwWlN4bUlUMDliblZzYkNZbUtHWXViR0Z1WlhOOFBXNHBMR2x2S0drdWNtVjBk'
    || 'WEp1TEc0c2RDa3NaQzVzWVc1bGMzdzlianRpY21WaGEzMW1QV1l1Ym1WNGRIMTlaV3h6WlNCcFppaHBMblJoWnowOVBURXdLWE05YVM1MGVYQmxQVDA5ZEM1'
    || 'MGVYQmxQMjUxYkd3NmFTNWphR2xzWkR0bGJITmxJR2xtS0drdWRHRm5QVDA5TVRncGUybG1LSE05YVM1eVpYUjFjbTRzY3owOVBXNTFiR3dwZEdoeWIzY2dS'
    || 'WEp5YjNJb1lTZ3pOREVwS1R0ekxteGhibVZ6ZkQxdUxHUTljeTVoYkhSbGNtNWhkR1VzWkNFOVBXNTFiR3dtSmloa0xteGhibVZ6ZkQxdUtTeHBieWh6TEc0'
    || 'c2RDa3NjejFwTG5OcFlteHBibWQ5Wld4elpTQnpQV2t1WTJocGJHUTdhV1lvY3lFOVBXNTFiR3dwY3k1eVpYUjFjbTQ5YVR0bGJITmxJR1p2Y2loelBXazdj'
    || 'eUU5UFc1MWJHdzdLWHRwWmloelBUMDlkQ2w3Y3oxdWRXeHNPMkp5WldGcmZXbG1LR2s5Y3k1emFXSnNhVzVuTEdraFBUMXVkV3hzS1h0cExuSmxkSFZ5Ymox'
    || 'ekxuSmxkSFZ5Yml4elBXazdZbkpsWVd0OWN6MXpMbkpsZEhWeWJuMXBQWE45UW1Vb1pTeDBMR3d1WTJocGJHUnlaVzRzYmlrc2REMTBMbU5vYVd4a2ZYSmxk'
    || 'SFZ5YmlCME8yTmhjMlVnT1RweVpYUjFjbTRnYkQxMExuUjVjR1VzY2oxMExuQmxibVJwYm1kUWNtOXdjeTVqYUdsc1pISmxiaXhHYmloMExHNHBMR3c5YzNR'
    || 'b2JDa3NjajF5S0d3cExIUXVabXhoWjNOOFBURXNRbVVvWlN4MExISXNiaWtzZEM1amFHbHNaRHRqWVhObElERTBPbkpsZEhWeWJpQnlQWFF1ZEhsd1pTeHNQ'
    || 'WFowS0hJc2RDNXdaVzVrYVc1blVISnZjSE1wTEd3OWRuUW9jaTUwZVhCbExHd3BMR3BoS0dVc2RDeHlMR3dzYmlrN1kyRnpaU0F4TlRweVpYUjFjbTRnVG1F'
    || 'b1pTeDBMSFF1ZEhsd1pTeDBMbkJsYm1ScGJtZFFjbTl3Y3l4dUtUdGpZWE5sSURFM09uSmxkSFZ5YmlCeVBYUXVkSGx3WlN4c1BYUXVjR1Z1WkdsdVoxQnli'
    || 'M0J6TEd3OWRDNWxiR1Z0Wlc1MFZIbHdaVDA5UFhJL2JEcDJkQ2h5TEd3cExFTnNLR1VzZENrc2RDNTBZV2M5TVN4SFpTaHlLVDhvWlQwaE1DeGhiQ2gwS1Nr'
    || 'NlpUMGhNU3hHYmloMExHNHBMR2RoS0hRc2NpeHNLU3hUYnloMExISXNiQ3h1S1N4T2J5aHVkV3hzTEhRc2Npd2hNQ3hsTEc0cE8yTmhjMlVnTVRrNmNtVjBk'
    || 'WEp1SUVsaEtHVXNkQ3h1S1R0allYTmxJREl5T25KbGRIVnliaUJEWVNobExIUXNiaWw5ZEdoeWIzY2dSWEp5YjNJb1lTZ3hOVFlzZEM1MFlXY3BLWDA3Wm5W'
    || 'dVkzUnBiMjRnYkdNb1pTeDBLWHR5WlhSMWNtNGdlbk1vWlN4MEtYMW1kVzVqZEdsdmJpQmxjQ2hsTEhRc2JpeHlLWHQwYUdsekxuUmhaejFsTEhSb2FYTXVh'
    || 'MlY1UFc0c2RHaHBjeTV6YVdKc2FXNW5QWFJvYVhNdVkyaHBiR1E5ZEdocGN5NXlaWFIxY200OWRHaHBjeTV6ZEdGMFpVNXZaR1U5ZEdocGN5NTBlWEJsUFhS'
    || 'b2FYTXVaV3hsYldWdWRGUjVjR1U5Ym5Wc2JDeDBhR2x6TG1sdVpHVjRQVEFzZEdocGN5NXlaV1k5Ym5Wc2JDeDBhR2x6TG5CbGJtUnBibWRRY205d2N6MTBM'
    || 'SFJvYVhNdVpHVndaVzVrWlc1amFXVnpQWFJvYVhNdWJXVnRiMmw2WldSVGRHRjBaVDEwYUdsekxuVndaR0YwWlZGMVpYVmxQWFJvYVhNdWJXVnRiMmw2WldS'
    || 'UWNtOXdjejF1ZFd4c0xIUm9hWE11Ylc5a1pUMXlMSFJvYVhNdWMzVmlkSEpsWlVac1lXZHpQWFJvYVhNdVpteGhaM005TUN4MGFHbHpMbVJsYkdWMGFXOXVj'
    || 'ejF1ZFd4c0xIUm9hWE11WTJocGJHUk1ZVzVsY3oxMGFHbHpMbXhoYm1WelBUQXNkR2hwY3k1aGJIUmxjbTVoZEdVOWJuVnNiSDFtZFc1amRHbHZiaUJqZENo'
    || 'bExIUXNiaXh5S1h0eVpYUjFjbTRnYm1WM0lHVndLR1VzZEN4dUxISXBmV1oxYm1OMGFXOXVJRmx2S0dVcGUzSmxkSFZ5YmlCbFBXVXVjSEp2ZEc5MGVYQmxM'
    || 'Q0VvSVdWOGZDRmxMbWx6VW1WaFkzUkRiMjF3YjI1bGJuUXBmV1oxYm1OMGFXOXVJSFJ3S0dVcGUybG1LSFI1Y0dWdlppQmxQVDBpWm5WdVkzUnBiMjRpS1hK'
    || 'bGRIVnliaUJaYnlobEtUOHhPakE3YVdZb1pTRTliblZzYkNsN2FXWW9aVDFsTGlRa2RIbHdaVzltTEdVOVBUMWZkQ2x5WlhSMWNtNGdNVEU3YVdZb1pUMDlQ'
    || 'Vk4wS1hKbGRIVnliaUF4TkgxeVpYUjFjbTRnTW4xbWRXNWpkR2x2YmlCMGJpaGxMSFFwZTNaaGNpQnVQV1V1WVd4MFpYSnVZWFJsTzNKbGRIVnliaUJ1UFQw'
    || 'OWJuVnNiRDhvYmoxamRDaGxMblJoWnl4MExHVXVhMlY1TEdVdWJXOWtaU2tzYmk1bGJHVnRaVzUwVkhsd1pUMWxMbVZzWlcxbGJuUlVlWEJsTEc0dWRIbHda'
    || 'VDFsTG5SNWNHVXNiaTV6ZEdGMFpVNXZaR1U5WlM1emRHRjBaVTV2WkdVc2JpNWhiSFJsY201aGRHVTlaU3hsTG1Gc2RHVnlibUYwWlQxdUtUb29iaTV3Wlc1'
    || 'a2FXNW5VSEp2Y0hNOWRDeHVMblI1Y0dVOVpTNTBlWEJsTEc0dVpteGhaM005TUN4dUxuTjFZblJ5WldWR2JHRm5jejB3TEc0dVpHVnNaWFJwYjI1elBXNTFi'
    || 'R3dwTEc0dVpteGhaM005WlM1bWJHRm5jeVl4TkRZNE1EQTJOQ3h1TG1Ob2FXeGtUR0Z1WlhNOVpTNWphR2xzWkV4aGJtVnpMRzR1YkdGdVpYTTlaUzVzWVc1'
    || 'bGN5eHVMbU5vYVd4a1BXVXVZMmhwYkdRc2JpNXRaVzF2YVhwbFpGQnliM0J6UFdVdWJXVnRiMmw2WldSUWNtOXdjeXh1TG0xbGJXOXBlbVZrVTNSaGRHVTla'
    || 'UzV0WlcxdmFYcGxaRk4wWVhSbExHNHVkWEJrWVhSbFVYVmxkV1U5WlM1MWNHUmhkR1ZSZFdWMVpTeDBQV1V1WkdWd1pXNWtaVzVqYVdWekxHNHVaR1Z3Wlc1'
    || 'a1pXNWphV1Z6UFhROVBUMXVkV3hzUDI1MWJHdzZlMnhoYm1Wek9uUXViR0Z1WlhNc1ptbHljM1JEYjI1MFpYaDBPblF1Wm1seWMzUkRiMjUwWlhoMGZTeHVM'
    || 'bk5wWW14cGJtYzlaUzV6YVdKc2FXNW5MRzR1YVc1a1pYZzlaUzVwYm1SbGVDeHVMbkpsWmoxbExuSmxaaXh1ZldaMWJtTjBhVzl1SUZWc0tHVXNkQ3h1TEhJ'
    || 'c2JDeHBLWHQyWVhJZ2N6MHlPMmxtS0hJOVpTeDBlWEJsYjJZZ1pUMDlJbVoxYm1OMGFXOXVJaWxaYnlobEtTWW1LSE05TVNrN1pXeHpaU0JwWmloMGVYQmxi'
    || 'MllnWlQwOUluTjBjbWx1WnlJcGN6MDFPMlZzYzJVZ1pUcHpkMmwwWTJnb1pTbDdZMkZ6WlNCalpUcHlaWFIxY200Z2VHNG9iaTVqYUdsc1pISmxiaXhzTEdr'
    || 'c2RDazdZMkZ6WlNCblpUcHpQVGdzYkh3OU9EdGljbVZoYXp0allYTmxJRzlsT25KbGRIVnliaUJsUFdOMEtERXlMRzRzZEN4c2ZESXBMR1V1Wld4bGJXVnVk'
    || 'RlI1Y0dVOWIyVXNaUzVzWVc1bGN6MXBMR1U3WTJGelpTQktaVHB5WlhSMWNtNGdaVDFqZENneE15eHVMSFFzYkNrc1pTNWxiR1Z0Wlc1MFZIbHdaVDFLWlN4'
    || 'bExteGhibVZ6UFdrc1pUdGpZWE5sSUdaME9uSmxkSFZ5YmlCbFBXTjBLREU1TEc0c2RDeHNLU3hsTG1Wc1pXMWxiblJVZVhCbFBXWjBMR1V1YkdGdVpYTTlh'
    || 'U3hsTzJOaGMyVWdSV1U2Y21WMGRYSnVJRVpzS0c0c2JDeHBMSFFwTzJSbFptRjFiSFE2YVdZb2RIbHdaVzltSUdVOVBTSnZZbXBsWTNRaUppWmxJVDA5Ym5W'
    || 'c2JDbHpkMmwwWTJnb1pTNGtKSFI1Y0dWdlppbDdZMkZ6WlNCc2REcHpQVEV3TzJKeVpXRnJJR1U3WTJGelpTQnZianB6UFRrN1luSmxZV3NnWlR0allYTmxJ'
    || 'RjkwT25NOU1URTdZbkpsWVdzZ1pUdGpZWE5sSUZOME9uTTlNVFE3WW5KbFlXc2daVHRqWVhObElGRmxPbk05TVRZc2NqMXVkV3hzTzJKeVpXRnJJR1Y5ZEdo'
    || 'eWIzY2dSWEp5YjNJb1lTZ3hNekFzWlQwOWJuVnNiRDlsT25SNWNHVnZaaUJsTENJaUtTbDljbVYwZFhKdUlIUTlZM1FvY3l4dUxIUXNiQ2tzZEM1bGJHVnRa'
    || 'VzUwVkhsd1pUMWxMSFF1ZEhsd1pUMXlMSFF1YkdGdVpYTTlhU3gwZldaMWJtTjBhVzl1SUhodUtHVXNkQ3h1TEhJcGUzSmxkSFZ5YmlCbFBXTjBLRGNzWlN4'
    || 'eUxIUXBMR1V1YkdGdVpYTTliaXhsZldaMWJtTjBhVzl1SUVac0tHVXNkQ3h1TEhJcGUzSmxkSFZ5YmlCbFBXTjBLREl5TEdVc2NpeDBLU3hsTG1Wc1pXMWxi'
    || 'blJVZVhCbFBVVmxMR1V1YkdGdVpYTTliaXhsTG5OMFlYUmxUbTlrWlQxN2FYTklhV1JrWlc0NklURjlMR1Y5Wm5WdVkzUnBiMjRnUjI4b1pTeDBMRzRwZTNK'
    || 'bGRIVnliaUJsUFdOMEtEWXNaU3h1ZFd4c0xIUXBMR1V1YkdGdVpYTTliaXhsZldaMWJtTjBhVzl1SUV0dktHVXNkQ3h1S1h0eVpYUjFjbTRnZEQxamRDZzBM'
    || 'R1V1WTJocGJHUnlaVzRoUFQxdWRXeHNQMlV1WTJocGJHUnlaVzQ2VzEwc1pTNXJaWGtzZENrc2RDNXNZVzVsY3oxdUxIUXVjM1JoZEdWT2IyUmxQWHRqYjI1'
    || 'MFlXbHVaWEpKYm1adk9tVXVZMjl1ZEdGcGJtVnlTVzVtYnl4d1pXNWthVzVuUTJocGJHUnlaVzQ2Ym5Wc2JDeHBiWEJzWlcxbGJuUmhkR2x2YmpwbExtbHRj'
    || 'R3hsYldWdWRHRjBhVzl1ZlN4MGZXWjFibU4wYVc5dUlHNXdLR1VzZEN4dUxISXNiQ2w3ZEdocGN5NTBZV2M5ZEN4MGFHbHpMbU52Ym5SaGFXNWxja2x1Wm04'
    || 'OVpTeDBhR2x6TG1acGJtbHphR1ZrVjI5eWF6MTBhR2x6TG5CcGJtZERZV05vWlQxMGFHbHpMbU4xY25KbGJuUTlkR2hwY3k1d1pXNWthVzVuUTJocGJHUnla'
    || 'VzQ5Ym5Wc2JDeDBhR2x6TG5ScGJXVnZkWFJJWVc1a2JHVTlMVEVzZEdocGN5NWpZV3hzWW1GamEwNXZaR1U5ZEdocGN5NXdaVzVrYVc1blEyOXVkR1Y0ZEQx'
    || 'MGFHbHpMbU52Ym5SbGVIUTliblZzYkN4MGFHbHpMbU5oYkd4aVlXTnJVSEpwYjNKcGRIazlNQ3gwYUdsekxtVjJaVzUwVkdsdFpYTTlSV2tvTUNrc2RHaHBj'
    || 'eTVsZUhCcGNtRjBhVzl1VkdsdFpYTTlSV2tvTFRFcExIUm9hWE11Wlc1MFlXNW5iR1ZrVEdGdVpYTTlkR2hwY3k1bWFXNXBjMmhsWkV4aGJtVnpQWFJvYVhN'
    || 'dWJYVjBZV0pzWlZKbFlXUk1ZVzVsY3oxMGFHbHpMbVY0Y0dseVpXUk1ZVzVsY3oxMGFHbHpMbkJwYm1kbFpFeGhibVZ6UFhSb2FYTXVjM1Z6Y0dWdVpHVmtU'
    || 'R0Z1WlhNOWRHaHBjeTV3Wlc1a2FXNW5UR0Z1WlhNOU1DeDBhR2x6TG1WdWRHRnVaMnhsYldWdWRITTlSV2tvTUNrc2RHaHBjeTVwWkdWdWRHbG1hV1Z5VUhK'
    || 'bFptbDRQWElzZEdocGN5NXZibEpsWTI5MlpYSmhZbXhsUlhKeWIzSTliQ3gwYUdsekxtMTFkR0ZpYkdWVGIzVnlZMlZGWVdkbGNraDVaSEpoZEdsdmJrUmhk'
    || 'R0U5Ym5Wc2JIMW1kVzVqZEdsdmJpQllieWhsTEhRc2JpeHlMR3dzYVN4ekxHUXNaaWw3Y21WMGRYSnVJR1U5Ym1WM0lHNXdLR1VzZEN4dUxHUXNaaWtzZEQw'
    || 'OVBURS9LSFE5TVN4cFBUMDlJVEFtSmloMGZEMDRLU2s2ZEQwd0xHazlZM1FvTXl4dWRXeHNMRzUxYkd3c2RDa3NaUzVqZFhKeVpXNTBQV2tzYVM1emRHRjBa'
    || 'VTV2WkdVOVpTeHBMbTFsYlc5cGVtVmtVM1JoZEdVOWUyVnNaVzFsYm5RNmNpeHBjMFJsYUhsa2NtRjBaV1E2Yml4allXTm9aVHB1ZFd4c0xIUnlZVzV6YVhS'
    || 'cGIyNXpPbTUxYkd3c2NHVnVaR2x1WjFOMWMzQmxibk5sUW05MWJtUmhjbWxsY3pwdWRXeHNmU3h6YnlocEtTeGxmV1oxYm1OMGFXOXVJSEp3S0dVc2RDeHVL'
    || 'WHQyWVhJZ2NqMHpQR0Z5WjNWdFpXNTBjeTVzWlc1bmRHZ21KbUZ5WjNWdFpXNTBjMXN6WFNFOVBYWnZhV1FnTUQ5aGNtZDFiV1Z1ZEhOYk0xMDZiblZzYkR0'
    || 'eVpYUjFjbTU3SkNSMGVYQmxiMlk2WVdVc2EyVjVPbkk5UFc1MWJHdy9iblZzYkRvaUlpdHlMR05vYVd4a2NtVnVPbVVzWTI5dWRHRnBibVZ5U1c1bWJ6cDBM'
    || 'R2x0Y0d4bGJXVnVkR0YwYVc5dU9tNTlmV1oxYm1OMGFXOXVJR2xqS0dVcGUybG1LQ0ZsS1hKbGRIVnliaUJaZER0bFBXVXVYM0psWVdOMFNXNTBaWEp1WVd4'
    || 'ek8yVTZlMmxtS0hOdUtHVXBJVDA5Wlh4OFpTNTBZV2NoUFQweEtYUm9jbTkzSUVWeWNtOXlLR0VvTVRjd0tTazdkbUZ5SUhROVpUdGtiM3R6ZDJsMFkyZ29k'
    || 'QzUwWVdjcGUyTmhjMlVnTXpwMFBYUXVjM1JoZEdWT2IyUmxMbU52Ym5SbGVIUTdZbkpsWVdzZ1pUdGpZWE5sSURFNmFXWW9SMlVvZEM1MGVYQmxLU2w3ZEQx'
    || 'MExuTjBZWFJsVG05a1pTNWZYM0psWVdOMFNXNTBaWEp1WVd4TlpXMXZhWHBsWkUxbGNtZGxaRU5vYVd4a1EyOXVkR1Y0ZER0aWNtVmhheUJsZlgxMFBYUXVj'
    || 'bVYwZFhKdWZYZG9hV3hsS0hRaFBUMXVkV3hzS1R0MGFISnZkeUJGY25KdmNpaGhLREUzTVNrcGZXbG1LR1V1ZEdGblBUMDlNU2w3ZG1GeUlHNDlaUzUwZVhC'
    || 'bE8ybG1LRWRsS0c0cEtYSmxkSFZ5YmlCTWRTaGxMRzRzZENsOWNtVjBkWEp1SUhSOVpuVnVZM1JwYjI0Z2IyTW9aU3gwTEc0c2NpeHNMR2tzY3l4a0xHWXBl'
    || 'M0psZEhWeWJpQmxQVmh2S0c0c2Npd2hNQ3hsTEd3c2FTeHpMR1FzWmlrc1pTNWpiMjUwWlhoMFBXbGpLRzUxYkd3cExHNDlaUzVqZFhKeVpXNTBMSEk5U0dV'
    || 'b0tTeHNQV0owS0c0cExHazlUSFFvY2l4c0tTeHBMbU5oYkd4aVlXTnJQWFEvUDI1MWJHd3NXSFFvYml4cExHd3BMR1V1WTNWeWNtVnVkQzVzWVc1bGN6MXNM'
    || 'R1Z5S0dVc2JDeHlLU3hhWlNobExISXBMR1Y5Wm5WdVkzUnBiMjRnVjJ3b1pTeDBMRzRzY2lsN2RtRnlJR3c5ZEM1amRYSnlaVzUwTEdrOVNHVW9LU3h6UFdK'
    || 'MEtHd3BPM0psZEhWeWJpQnVQV2xqS0c0cExIUXVZMjl1ZEdWNGREMDlQVzUxYkd3L2RDNWpiMjUwWlhoMFBXNDZkQzV3Wlc1a2FXNW5RMjl1ZEdWNGREMXVM'
    || 'SFE5VEhRb2FTeHpLU3gwTG5CaGVXeHZZV1E5ZTJWc1pXMWxiblE2Wlgwc2NqMXlQVDA5ZG05cFpDQXdQMjUxYkd3NmNpeHlJVDA5Ym5Wc2JDWW1LSFF1WTJG'
    || 'c2JHSmhZMnM5Y2lrc1pUMVlkQ2hzTEhRc2N5a3NaU0U5UFc1MWJHd21KaWg0ZENobExHd3NjeXhwS1N4bmJDaGxMR3dzY3lrcExITjlablZ1WTNScGIyNGdW'
    || 'bXdvWlNsN2FXWW9aVDFsTG1OMWNuSmxiblFzSVdVdVkyaHBiR1FwY21WMGRYSnVJRzUxYkd3N2MzZHBkR05vS0dVdVkyaHBiR1F1ZEdGbktYdGpZWE5sSURV'
    || 'NmNtVjBkWEp1SUdVdVkyaHBiR1F1YzNSaGRHVk9iMlJsTzJSbFptRjFiSFE2Y21WMGRYSnVJR1V1WTJocGJHUXVjM1JoZEdWT2IyUmxmWDFtZFc1amRHbHZi'
    || 'aUJ6WXlobExIUXBlMmxtS0dVOVpTNXRaVzF2YVhwbFpGTjBZWFJsTEdVaFBUMXVkV3hzSmlabExtUmxhSGxrY21GMFpXUWhQVDF1ZFd4c0tYdDJZWElnYmox'
    || 'bExuSmxkSEo1VEdGdVpUdGxMbkpsZEhKNVRHRnVaVDF1SVQwOU1DWW1iangwUDI0NmRIMTlablZ1WTNScGIyNGdXbThvWlN4MEtYdHpZeWhsTEhRcExDaGxQ'
    || 'V1V1WVd4MFpYSnVZWFJsS1NZbWMyTW9aU3gwS1gxbWRXNWpkR2x2YmlCc2NDZ3BlM0psZEhWeWJpQnVkV3hzZlhaaGNpQjFZejEwZVhCbGIyWWdjbVZ3YjNK'
    || 'MFJYSnliM0k5UFNKbWRXNWpkR2x2YmlJL2NtVndiM0owUlhKeWIzSTZablZ1WTNScGIyNG9aU2w3WTI5dWMyOXNaUzVsY25KdmNpaGxLWDA3Wm5WdVkzUnBi'
    || 'MjRnY1c4b1pTbDdkR2hwY3k1ZmFXNTBaWEp1WVd4U2IyOTBQV1Y5UW13dWNISnZkRzkwZVhCbExuSmxibVJsY2oxeGJ5NXdjbTkwYjNSNWNHVXVjbVZ1WkdW'
    || 'eVBXWjFibU4wYVc5dUtHVXBlM1poY2lCMFBYUm9hWE11WDJsdWRHVnlibUZzVW05dmREdHBaaWgwUFQwOWJuVnNiQ2wwYUhKdmR5QkZjbkp2Y2loaEtEUXdP'
    || 'U2twTzFkc0tHVXNkQ3h1ZFd4c0xHNTFiR3dwZlN4Q2JDNXdjbTkwYjNSNWNHVXVkVzV0YjNWdWREMXhieTV3Y205MGIzUjVjR1V1ZFc1dGIzVnVkRDFtZFc1'
    || 'amRHbHZiaWdwZTNaaGNpQmxQWFJvYVhNdVgybHVkR1Z5Ym1Gc1VtOXZkRHRwWmlobElUMDliblZzYkNsN2RHaHBjeTVmYVc1MFpYSnVZV3hTYjI5MFBXNTFi'
    || 'R3c3ZG1GeUlIUTlaUzVqYjI1MFlXbHVaWEpKYm1adk8zWnVLR1oxYm1OMGFXOXVLQ2w3VjJ3b2JuVnNiQ3hsTEc1MWJHd3NiblZzYkNsOUtTeDBXMVIwWFQx'
    || 'dWRXeHNmWDA3Wm5WdVkzUnBiMjRnUW13b1pTbDdkR2hwY3k1ZmFXNTBaWEp1WVd4U2IyOTBQV1Y5UW13dWNISnZkRzkwZVhCbExuVnVjM1JoWW14bFgzTmph'
    || 'R1ZrZFd4bFNIbGtjbUYwYVc5dVBXWjFibU4wYVc5dUtHVXBlMmxtS0dVcGUzWmhjaUIwUFZGektDazdaVDE3WW14dlkydGxaRTl1T201MWJHd3NkR0Z5WjJW'
    || 'ME9tVXNjSEpwYjNKcGRIazZkSDA3Wm05eUtIWmhjaUJ1UFRBN2JqeFdkQzVzWlc1bmRHZ21KblFoUFQwd0ppWjBQRlowVzI1ZExuQnlhVzl5YVhSNU8yNHJL'
    || 'eWs3Vm5RdWMzQnNhV05sS0c0c01DeGxLU3h1UFQwOU1DWW1TM01vWlNsOWZUdG1kVzVqZEdsdmJpQktieWhsS1h0eVpYUjFjbTRoS0NGbGZIeGxMbTV2WkdW'
    || 'VWVYQmxJVDA5TVNZbVpTNXViMlJsVkhsd1pTRTlQVGttSm1VdWJtOWtaVlI1Y0dVaFBUMHhNU2w5Wm5WdVkzUnBiMjRnU0d3b1pTbDdjbVYwZFhKdUlTZ2ha'
    || 'WHg4WlM1dWIyUmxWSGx3WlNFOVBURW1KbVV1Ym05a1pWUjVjR1VoUFQwNUppWmxMbTV2WkdWVWVYQmxJVDA5TVRFbUppaGxMbTV2WkdWVWVYQmxJVDA5T0h4'
    || 'OFpTNXViMlJsVm1Gc2RXVWhQVDBpSUhKbFlXTjBMVzF2ZFc1MExYQnZhVzUwTFhWdWMzUmhZbXhsSUNJcEtYMW1kVzVqZEdsdmJpQmhZeWdwZTMxbWRXNWpk'
    || 'R2x2YmlCcGNDaGxMSFFzYml4eUxHd3BlMmxtS0d3cGUybG1LSFI1Y0dWdlppQnlQVDBpWm5WdVkzUnBiMjRpS1h0MllYSWdhVDF5TzNJOVpuVnVZM1JwYjI0'
    || 'b0tYdDJZWElnZVQxV2JDaHpLVHRwTG1OaGJHd29lU2w5ZlhaaGNpQnpQVzlqS0hRc2NpeGxMREFzYm5Wc2JDd2hNU3doTVN3aUlpeGhZeWs3Y21WMGRYSnVJ'
    || 'R1V1WDNKbFlXTjBVbTl2ZEVOdmJuUmhhVzVsY2oxekxHVmJWSFJkUFhNdVkzVnljbVZ1ZEN4b2NpaGxMbTV2WkdWVWVYQmxQVDA5T0Q5bExuQmhjbVZ1ZEU1'
    || 'dlpHVTZaU2tzZG00b0tTeHpmV1p2Y2lnN2JEMWxMbXhoYzNSRGFHbHNaRHNwWlM1eVpXMXZkbVZEYUdsc1pDaHNLVHRwWmloMGVYQmxiMllnY2owOUltWjFi'
    || 'bU4wYVc5dUlpbDdkbUZ5SUdROWNqdHlQV1oxYm1OMGFXOXVLQ2w3ZG1GeUlIazlWbXdvWmlrN1pDNWpZV3hzS0hrcGZYMTJZWElnWmoxWWJ5aGxMREFzSVRF'
    || 'c2JuVnNiQ3h1ZFd4c0xDRXhMQ0V4TENJaUxHRmpLVHR5WlhSMWNtNGdaUzVmY21WaFkzUlNiMjkwUTI5dWRHRnBibVZ5UFdZc1pWdFVkRjA5Wmk1amRYSnla'
    || 'VzUwTEdoeUtHVXVibTlrWlZSNWNHVTlQVDA0UDJVdWNHRnlaVzUwVG05a1pUcGxLU3gyYmlobWRXNWpkR2x2YmlncGUxZHNLSFFzWml4dUxISXBmU2tzWm4x'
    || 'bWRXNWpkR2x2YmlBa2JDaGxMSFFzYml4eUxHd3BlM1poY2lCcFBXNHVYM0psWVdOMFVtOXZkRU52Ym5SaGFXNWxjanRwWmlocEtYdDJZWElnY3oxcE8ybG1L'
    || 'SFI1Y0dWdlppQnNQVDBpWm5WdVkzUnBiMjRpS1h0MllYSWdaRDFzTzJ3OVpuVnVZM1JwYjI0b0tYdDJZWElnWmoxV2JDaHpLVHRrTG1OaGJHd29aaWw5ZlZk'
    || 'c0tIUXNjeXhsTEd3cGZXVnNjMlVnY3oxcGNDaHVMSFFzWlN4c0xISXBPM0psZEhWeWJpQldiQ2h6S1gxSWN6MW1kVzVqZEdsdmJpaGxLWHR6ZDJsMFkyZ29a'
    || 'UzUwWVdjcGUyTmhjMlVnTXpwMllYSWdkRDFsTG5OMFlYUmxUbTlrWlR0cFppaDBMbU4xY25KbGJuUXViV1Z0YjJsNlpXUlRkR0YwWlM1cGMwUmxhSGxrY21G'
    || 'MFpXUXBlM1poY2lCdVBXSnVLSFF1Y0dWdVpHbHVaMHhoYm1WektUdHVJVDA5TUNZbUtGOXBLSFFzYm53eEtTeGFaU2gwTEhkbEtDa3BMQ2h1WlNZMktUMDlQ'
    || 'VEFtSmlna2JqMTNaU2dwS3pVd01DeEhkQ2dwS1NsOVluSmxZV3M3WTJGelpTQXhNenAyYmlobWRXNWpkR2x2YmlncGUzWmhjaUJ5UFZCMEtHVXNNU2s3YVdZ'
    || 'b2NpRTlQVzUxYkd3cGUzWmhjaUJzUFVobEtDazdlSFFvY2l4bExERXNiQ2w5ZlNrc1dtOG9aU3d4S1gxOUxGTnBQV1oxYm1OMGFXOXVLR1VwZTJsbUtHVXVk'
    || 'R0ZuUFQwOU1UTXBlM1poY2lCMFBWQjBLR1VzTVRNME1qRTNOekk0S1R0cFppaDBJVDA5Ym5Wc2JDbDdkbUZ5SUc0OVNHVW9LVHQ0ZENoMExHVXNNVE0wTWpF'
    || 'M056STRMRzRwZlZwdktHVXNNVE0wTWpFM056STRLWDE5TENSelBXWjFibU4wYVc5dUtHVXBlMmxtS0dVdWRHRm5QVDA5TVRNcGUzWmhjaUIwUFdKMEtHVXBM'
    || 'RzQ5VUhRb1pTeDBLVHRwWmlodUlUMDliblZzYkNsN2RtRnlJSEk5U0dVb0tUdDRkQ2h1TEdVc2RDeHlLWDFhYnlobExIUXBmWDBzVVhNOVpuVnVZM1JwYjI0'
    || 'b0tYdHlaWFIxY200Z2RXVjlMRmx6UFdaMWJtTjBhVzl1S0dVc2RDbDdkbUZ5SUc0OWRXVTdkSEo1ZTNKbGRIVnliaUIxWlQxbExIUW9LWDFtYVc1aGJHeDVl'
    || 'M1ZsUFc1OWZTeG9hVDFtZFc1amRHbHZiaWhsTEhRc2JpbDdjM2RwZEdOb0tIUXBlMk5oYzJVaWFXNXdkWFFpT21sbUtHOXBLR1VzYmlrc2REMXVMbTVoYldV'
    || 'c2JpNTBlWEJsUFQwOUluSmhaR2x2SWlZbWRDRTliblZzYkNsN1ptOXlLRzQ5WlR0dUxuQmhjbVZ1ZEU1dlpHVTdLVzQ5Ymk1d1lYSmxiblJPYjJSbE8yWnZj'
    || 'aWh1UFc0dWNYVmxjbmxUWld4bFkzUnZja0ZzYkNnaWFXNXdkWFJiYm1GdFpUMGlLMHBUVDA0dWMzUnlhVzVuYVdaNUtDSWlLM1FwS3lkZFczUjVjR1U5SW5K'
    || 'aFpHbHZJbDBuS1N4MFBUQTdkRHh1TG14bGJtZDBhRHQwS3lzcGUzWmhjaUJ5UFc1YmRGMDdhV1lvY2lFOVBXVW1Kbkl1Wm05eWJUMDlQV1V1Wm05eWJTbDdk'
    || 'bUZ5SUd3OWMyd29jaWs3YVdZb0lXd3BkR2h5YjNjZ1JYSnliM0lvWVNnNU1Da3BPM1p6S0hJcExHOXBLSElzYkNsOWZYMWljbVZoYXp0allYTmxJblJsZUhS'
    || 'aGNtVmhJanBmY3lobExHNHBPMkp5WldGck8yTmhjMlVpYzJWc1pXTjBJanAwUFc0dWRtRnNkV1VzZENFOWJuVnNiQ1ltWDI0b1pTd2hJVzR1YlhWc2RHbHdi'
    || 'R1VzZEN3aE1TbDlmU3hFY3oxSWJ5eFBjejEyYmp0MllYSWdiM0E5ZTNWemFXNW5RMnhwWlc1MFJXNTBjbmxRYjJsdWREb2hNU3hGZG1WdWRITTZXMmR5TEU5'
    || 'dUxITnNMRlJ6TEZKekxFaHZYWDBzVDNJOWUyWnBibVJHYVdKbGNrSjVTRzl6ZEVsdWMzUmhibU5sT25WdUxHSjFibVJzWlZSNWNHVTZNQ3gyWlhKemFXOXVP'
    || 'aUl4T0M0ekxqRWlMSEpsYm1SbGNtVnlVR0ZqYTJGblpVNWhiV1U2SW5KbFlXTjBMV1J2YlNKOUxITndQWHRpZFc1a2JHVlVlWEJsT2s5eUxtSjFibVJzWlZS'
    || 'NWNHVXNkbVZ5YzJsdmJqcFBjaTUyWlhKemFXOXVMSEpsYm1SbGNtVnlVR0ZqYTJGblpVNWhiV1U2VDNJdWNtVnVaR1Z5WlhKUVlXTnJZV2RsVG1GdFpTeHla'
    || 'VzVrWlhKbGNrTnZibVpwWnpwUGNpNXlaVzVrWlhKbGNrTnZibVpwWnl4dmRtVnljbWxrWlVodmIydFRkR0YwWlRwdWRXeHNMRzkyWlhKeWFXUmxTRzl2YTFO'
    || 'MFlYUmxSR1ZzWlhSbFVHRjBhRHB1ZFd4c0xHOTJaWEp5YVdSbFNHOXZhMU4wWVhSbFVtVnVZVzFsVUdGMGFEcHVkV3hzTEc5MlpYSnlhV1JsVUhKdmNITTZi'
    || 'blZzYkN4dmRtVnljbWxrWlZCeWIzQnpSR1ZzWlhSbFVHRjBhRHB1ZFd4c0xHOTJaWEp5YVdSbFVISnZjSE5TWlc1aGJXVlFZWFJvT201MWJHd3NjMlYwUlhK'
    || 'eWIzSklZVzVrYkdWeU9tNTFiR3dzYzJWMFUzVnpjR1Z1YzJWSVlXNWtiR1Z5T201MWJHd3NjMk5vWldSMWJHVlZjR1JoZEdVNmJuVnNiQ3hqZFhKeVpXNTBS'
    || 'R2x6Y0dGMFkyaGxjbEpsWmpwTExsSmxZV04wUTNWeWNtVnVkRVJwYzNCaGRHTm9aWElzWm1sdVpFaHZjM1JKYm5OMFlXNWpaVUo1Um1saVpYSTZablZ1WTNS'
    || 'cGIyNG9aU2w3Y21WMGRYSnVJR1U5UVhNb1pTa3NaVDA5UFc1MWJHdy9iblZzYkRwbExuTjBZWFJsVG05a1pYMHNabWx1WkVacFltVnlRbmxJYjNOMFNXNXpk'
    || 'R0Z1WTJVNlQzSXVabWx1WkVacFltVnlRbmxJYjNOMFNXNXpkR0Z1WTJWOGZHeHdMR1pwYm1SSWIzTjBTVzV6ZEdGdVkyVnpSbTl5VW1WbWNtVnphRHB1ZFd4'
    || 'c0xITmphR1ZrZFd4bFVtVm1jbVZ6YURwdWRXeHNMSE5qYUdWa2RXeGxVbTl2ZERwdWRXeHNMSE5sZEZKbFpuSmxjMmhJWVc1a2JHVnlPbTUxYkd3c1oyVjBR'
    || 'M1Z5Y21WdWRFWnBZbVZ5T201MWJHd3NjbVZqYjI1amFXeGxjbFpsY25OcGIyNDZJakU0TGpNdU1TMXVaWGgwTFdZeE16TTRaamd3T0RBdE1qQXlOREEwTWpZ'
    || 'aWZUdHBaaWgwZVhCbGIyWWdYMTlTUlVGRFZGOUVSVlpVVDA5TVUxOUhURTlDUVV4ZlNFOVBTMTlmUENKMUlpbDdkbUZ5SUZGc1BWOWZVa1ZCUTFSZlJFVldW'
    || 'RTlQVEZOZlIweFBRa0ZNWDBoUFQwdGZYenRwWmlnaFVXd3VhWE5FYVhOaFlteGxaQ1ltVVd3dWMzVndjRzl5ZEhOR2FXSmxjaWwwY25sN1FuSTlVV3d1YVc1'
    || 'cVpXTjBLSE53S1N4M2REMVJiSDFqWVhSamFIdDlmWEpsZEhWeWJpQWtaUzVmWDFORlExSkZWRjlKVGxSRlVrNUJURk5mUkU5ZlRrOVVYMVZUUlY5UFVsOVpU'
    || 'MVZmVjBsTVRGOUNSVjlHU1ZKRlJEMXZjQ3drWlM1amNtVmhkR1ZRYjNKMFlXdzlablZ1WTNScGIyNG9aU3gwS1h0MllYSWdiajB5UEdGeVozVnRaVzUwY3k1'
    || 'c1pXNW5kR2dtSm1GeVozVnRaVzUwYzFzeVhTRTlQWFp2YVdRZ01EOWhjbWQxYldWdWRITmJNbDA2Ym5Wc2JEdHBaaWdoU204b2RDa3BkR2h5YjNjZ1JYSnli'
    || 'M0lvWVNneU1EQXBLVHR5WlhSMWNtNGdjbkFvWlN4MExHNTFiR3dzYmlsOUxDUmxMbU55WldGMFpWSnZiM1E5Wm5WdVkzUnBiMjRvWlN4MEtYdHBaaWdoU204'
    || 'b1pTa3BkR2h5YjNjZ1JYSnliM0lvWVNneU9Ua3BLVHQyWVhJZ2JqMGhNU3h5UFNJaUxHdzlkV003Y21WMGRYSnVJSFFoUFc1MWJHd21KaWgwTG5WdWMzUmhZ'
    || 'bXhsWDNOMGNtbGpkRTF2WkdVOVBUMGhNQ1ltS0c0OUlUQXBMSFF1YVdSbGJuUnBabWxsY2xCeVpXWnBlQ0U5UFhadmFXUWdNQ1ltS0hJOWRDNXBaR1Z1ZEds'
    || 'bWFXVnlVSEpsWm1sNEtTeDBMbTl1VW1WamIzWmxjbUZpYkdWRmNuSnZjaUU5UFhadmFXUWdNQ1ltS0d3OWRDNXZibEpsWTI5MlpYSmhZbXhsUlhKeWIzSXBL'
    || 'U3gwUFZodktHVXNNU3doTVN4dWRXeHNMRzUxYkd3c2Jpd2hNU3h5TEd3cExHVmJWSFJkUFhRdVkzVnljbVZ1ZEN4b2NpaGxMbTV2WkdWVWVYQmxQVDA5T0Q5'
    || 'bExuQmhjbVZ1ZEU1dlpHVTZaU2tzYm1WM0lIRnZLSFFwZlN3a1pTNW1hVzVrUkU5TlRtOWtaVDFtZFc1amRHbHZiaWhsS1h0cFppaGxQVDF1ZFd4c0tYSmxk'
    || 'SFZ5YmlCdWRXeHNPMmxtS0dVdWJtOWtaVlI1Y0dVOVBUMHhLWEpsZEhWeWJpQmxPM1poY2lCMFBXVXVYM0psWVdOMFNXNTBaWEp1WVd4ek8ybG1LSFE5UFQx'
    || 'MmIybGtJREFwZEdoeWIzY2dkSGx3Wlc5bUlHVXVjbVZ1WkdWeVBUMGlablZ1WTNScGIyNGlQMFZ5Y205eUtHRW9NVGc0S1NrNktHVTlUMkpxWldOMExtdGxl'
    || 'WE1vWlNrdWFtOXBiaWdpTENJcExFVnljbTl5S0dFb01qWTRMR1VwS1NrN2NtVjBkWEp1SUdVOVFYTW9kQ2tzWlQxbFBUMDliblZzYkQ5dWRXeHNPbVV1YzNS'
    || 'aGRHVk9iMlJsTEdWOUxDUmxMbVpzZFhOb1UzbHVZejFtZFc1amRHbHZiaWhsS1h0eVpYUjFjbTRnZG00b1pTbDlMQ1JsTG1oNVpISmhkR1U5Wm5WdVkzUnBi'
    || 'MjRvWlN4MExHNHBlMmxtS0NGSWJDaDBLU2wwYUhKdmR5QkZjbkp2Y2loaEtESXdNQ2twTzNKbGRIVnliaUFrYkNodWRXeHNMR1VzZEN3aE1DeHVLWDBzSkdV'
    || 'dWFIbGtjbUYwWlZKdmIzUTlablZ1WTNScGIyNG9aU3gwTEc0cGUybG1LQ0ZLYnlobEtTbDBhSEp2ZHlCRmNuSnZjaWhoS0RRd05Ta3BPM1poY2lCeVBXNGhQ'
    || 'VzUxYkd3bUptNHVhSGxrY21GMFpXUlRiM1Z5WTJWemZIeHVkV3hzTEd3OUlURXNhVDBpSWl4elBYVmpPMmxtS0c0aFBXNTFiR3dtSmlodUxuVnVjM1JoWW14'
    || 'bFgzTjBjbWxqZEUxdlpHVTlQVDBoTUNZbUtHdzlJVEFwTEc0dWFXUmxiblJwWm1sbGNsQnlaV1pwZUNFOVBYWnZhV1FnTUNZbUtHazliaTVwWkdWdWRHbG1h'
    || 'V1Z5VUhKbFptbDRLU3h1TG05dVVtVmpiM1psY21GaWJHVkZjbkp2Y2lFOVBYWnZhV1FnTUNZbUtITTliaTV2YmxKbFkyOTJaWEpoWW14bFJYSnliM0lwS1N4'
    || 'MFBXOWpLSFFzYm5Wc2JDeGxMREVzYmo4L2JuVnNiQ3hzTENFeExHa3NjeWtzWlZ0VWRGMDlkQzVqZFhKeVpXNTBMR2h5S0dVcExISXBabTl5S0dVOU1EdGxQ'
    || 'SEl1YkdWdVozUm9PMlVyS3lsdVBYSmJaVjBzYkQxdUxsOW5aWFJXWlhKemFXOXVMR3c5YkNodUxsOXpiM1Z5WTJVcExIUXViWFYwWVdKc1pWTnZkWEpqWlVW'
    || 'aFoyVnlTSGxrY21GMGFXOXVSR0YwWVQwOWJuVnNiRDkwTG0xMWRHRmliR1ZUYjNWeVkyVkZZV2RsY2toNVpISmhkR2x2YmtSaGRHRTlXMjRzYkYwNmRDNXRk'
    || 'WFJoWW14bFUyOTFjbU5sUldGblpYSkllV1J5WVhScGIyNUVZWFJoTG5CMWMyZ29iaXhzS1R0eVpYUjFjbTRnYm1WM0lFSnNLSFFwZlN3a1pTNXlaVzVrWlhJ'
    || 'OVpuVnVZM1JwYjI0b1pTeDBMRzRwZTJsbUtDRkliQ2gwS1NsMGFISnZkeUJGY25KdmNpaGhLREl3TUNrcE8zSmxkSFZ5YmlBa2JDaHVkV3hzTEdVc2RDd2hN'
    || 'U3h1S1gwc0pHVXVkVzV0YjNWdWRFTnZiWEJ2Ym1WdWRFRjBUbTlrWlQxbWRXNWpkR2x2YmlobEtYdHBaaWdoU0d3b1pTa3BkR2h5YjNjZ1JYSnliM0lvWVNn'
    || 'ME1Da3BPM0psZEhWeWJpQmxMbDl5WldGamRGSnZiM1JEYjI1MFlXbHVaWEkvS0hadUtHWjFibU4wYVc5dUtDbDdKR3dvYm5Wc2JDeHVkV3hzTEdVc0lURXNa'
    || 'blZ1WTNScGIyNG9LWHRsTGw5eVpXRmpkRkp2YjNSRGIyNTBZV2x1WlhJOWJuVnNiQ3hsVzFSMFhUMXVkV3hzZlNsOUtTd2hNQ2s2SVRGOUxDUmxMblZ1YzNS'
    || 'aFlteGxYMkpoZEdOb1pXUlZjR1JoZEdWelBVaHZMQ1JsTG5WdWMzUmhZbXhsWDNKbGJtUmxjbE4xWW5SeVpXVkpiblJ2UTI5dWRHRnBibVZ5UFdaMWJtTjBh'
    || 'Vzl1S0dVc2RDeHVMSElwZTJsbUtDRkliQ2h1S1NsMGFISnZkeUJGY25KdmNpaGhLREl3TUNrcE8ybG1LR1U5UFc1MWJHeDhmR1V1WDNKbFlXTjBTVzUwWlhK'
    || 'dVlXeHpQVDA5ZG05cFpDQXdLWFJvY205M0lFVnljbTl5S0dFb016Z3BLVHR5WlhSMWNtNGdKR3dvWlN4MExHNHNJVEVzY2lsOUxDUmxMblpsY25OcGIyNDlJ'
    || 'akU0TGpNdU1TMXVaWGgwTFdZeE16TTRaamd3T0RBdE1qQXlOREEwTWpZaUxDUmxmWFpoY2lCdmN6dG1kVzVqZEdsdmJpQm5ZeWdwZTJsbUtHOXpLWEpsZEhW'
    || 'eWJpQmFiQzVsZUhCdmNuUnpPMjl6UFRFN1puVnVZM1JwYjI0Z2RTZ3BlMmxtS0NFb2RIbHdaVzltSUY5ZlVrVkJRMVJmUkVWV1ZFOVBURk5mUjB4UFFrRk1Y'
    || 'MGhQVDB0Zlh6NGlkU0o4ZkhSNWNHVnZaaUJmWDFKRlFVTlVYMFJGVmxSUFQweFRYMGRNVDBKQlRGOUlUMDlMWDE4dVkyaGxZMnRFUTBVaFBTSm1kVzVqZEds'
    || 'dmJpSXBLWFJ5ZVh0ZlgxSkZRVU5VWDBSRlZsUlBUMHhUWDBkTVQwSkJURjlJVDA5TFgxOHVZMmhsWTJ0RVEwVW9kU2w5WTJGMFkyZ29ZeWw3WTI5dWMyOXNa'
    || 'UzVsY25KdmNpaGpLWDE5Y21WMGRYSnVJSFVvS1N4YWJDNWxlSEJ2Y25SelBYWmpLQ2tzV213dVpYaHdiM0owYzMxMllYSWdjM003Wm5WdVkzUnBiMjRnZVdN'
    || 'b0tYdHBaaWh6Y3lseVpYUjFjbTRnVUhJN2MzTTlNVHQyWVhJZ2RUMW5ZeWdwTzNKbGRIVnliaUJRY2k1amNtVmhkR1ZTYjI5MFBYVXVZM0psWVhSbFVtOXZk'
    || 'Q3hRY2k1b2VXUnlZWFJsVW05dmREMTFMbWg1WkhKaGRHVlNiMjkwTEZCeWZYWmhjaUI0WXoxNVl5Z3BPMk52Ym5OMElFVmpQU0pmWDFkSVIwVk9YMFJCVkVG'
    || 'Zlh5SXNYMk05ZTJOdmJuUmxlSFE2ZTMwc2NHRnVaV3h6T250OUxHWmhkR0ZzT2lKT2J5QmtZWFJoSUhCaGVXeHZZV1FnZDJGeklHbHVhbVZqZEdWa0xpQlVh'
    || 'R2x6SUdKMWFXeGtJRzltSUhSb1pTQmhjSEFnYVhNZ1luSnZhMlZ1T3lCeVpTMXlkVzRnYUdGeWJtVnpjeTVpZFc1a2JHVWdZVzVrSUhKbFluVnBiR1F1SW4w'
    || 'N1puVnVZM1JwYjI0Z1UyTW9kVDFGWXlsN1kyOXVjM1FnWXoxM2FXNWtiM2RiZFYwN2FXWW9JV044ZkhSNWNHVnZaaUJqSVQwaWIySnFaV04wSWlseVpYUjFj'
    || 'bTRnWDJNN1kyOXVjM1FnWVQxak8zSmxkSFZ5Ym50amIyNTBaWGgwT21FdVkyOXVkR1Y0ZEQ4L2UzMHNjR0Z1Wld4ek9tRXVjR0Z1Wld4elB6OTdmU3htWVhS'
    || 'aGJEcGhMbVpoZEdGc0xHTjFjM1J2YldsNllYUnBiMjQ2WVM1amRYTjBiMjFwZW1GMGFXOXVMR04xYzNSdmJXbDZZWFJwYjI1ZlpYSnliM0k2WVM1amRYTjBi'
    || 'MjFwZW1GMGFXOXVYMlZ5Y205eUxHNWhkbWxuWVhScGIyNDZZUzV1WVhacFoyRjBhVzl1ZlgxbWRXNWpkR2x2YmlCeWJpaDFLWHR5WlhSMWNtNGhJWFVtSmlK'
    || 'bGNuSnZjaUpwYmlCMWZXWjFibU4wYVc5dUlIVnpLSFVwZTNKbGRIVnliaUIxSmlZaWNtOTNjeUpwYmlCMUppWjFMblJ5ZFc1allYUmxaRDkxTG5SeWRXNWpZ'
    || 'WFJsWkRvd2ZXWjFibU4wYVc5dUlHeHVLSFVwZTNKbGRIVnliaUYxZkh3aEtDSmxjbkp2Y2lKcGJpQjFLVDhoTVRvdlpHOWxjeUJ1YjNRZ1pYaHBjM1FnYjNJ'
    || 'Z2JtOTBJR0YxZEdodmNtbDZaV1F2YVM1MFpYTjBLSFV1WlhKeWIzSXBmV1oxYm1OMGFXOXVJRU5sS0hVc1l5bDdZMjl1YzNRZ1lUMTFMbkJoYm1Wc2MxdGpY'
    || 'VHR5WlhSMWNtNGdZU1ltSW5KdmQzTWlhVzRnWVQ5aExuSnZkM002VzExOVpuVnVZM1JwYjI0Z1RYUW9kU2w3YVdZb2RIbHdaVzltSUhVOVBTSnVkVzFpWlhJ'
    || 'aUtYSmxkSFZ5YmlCT2RXMWlaWEl1YVhOR2FXNXBkR1VvZFNrL2RUcHVkV3hzTzJsbUtIUjVjR1Z2WmlCMUlUMGljM1J5YVc1bklpbHlaWFIxY200Z2JuVnNi'
    || 'RHRqYjI1emRDQmpQWFV1ZEhKcGJTZ3BPMmxtS0dNOVBUMGlJbng4SVM5ZVd5c3RYVDhvWEdRclhDNC9YR1FxZkZ3dVhHUXJLU2hiWlVWZFd5c3RYVDljWkNz'
    || 'cFB5UXZMblJsYzNRb1l5a3BjbVYwZFhKdUlHNTFiR3c3WTI5dWMzUWdZVDFPZFcxaVpYSW9ZeWs3Y21WMGRYSnVJRTUxYldKbGNpNXBjMFpwYm1sMFpTaGhL'
    || 'VDloT201MWJHeDlablZ1WTNScGIyNGdWU2gxS1h0cFppaDFQVDF1ZFd4c2ZIeDFQVDA5SWlJcGNtVjBkWEp1SXVLQWxDSTdZMjl1YzNRZ1l6MU5kQ2gxS1R0'
    || 'cFppaGpQVDA5Ym5Wc2JDbHlaWFIxY200Z1UzUnlhVzVuS0hVcE8ybG1LR005UFQwd0tYSmxkSFZ5YmlJd0lqdGpiMjV6ZENCaFBVMWhkR2d1WVdKektHTXBP'
    || 'MmxtS0dFOE5XVXROQ2x5WlhSMWNtNGdZend3UHlJK0lDMHdMakF3TVNJNklqd2dNQzR3TURFaU8yeGxkQ0J0TzNKbGRIVnliaUJoUGoweFpUTS9iVDB3T21F'
    || 'K1BURXdNRDl0UFRFNllUNDlNVDl0UFRJNmJUMHpMR011ZEc5TWIyTmhiR1ZUZEhKcGJtY29JbVZ1TFZWVElpeDdiV2x1YVcxMWJVWnlZV04wYVc5dVJHbG5h'
    || 'WFJ6T2pBc2JXRjRhVzExYlVaeVlXTjBhVzl1UkdsbmFYUnpPbTE5S1gxbWRXNWpkR2x2YmlCM1l5aDFLWHRqYjI1emRDQmpQVk4wY21sdVp5aDFQejhpSWlr'
    || 'dWRHOVZjSEJsY2tOaGMyVW9LUzUwY21sdEtDazdjbVYwZFhKdUlHTTlQVDBpVFVWVUlueDhZejA5UFNKT1QxUmZUVVZVSW54OFl6MDlQU0pPTDBFaVAyTTZJ'
    || 'bEJGVGtSSlRrY2lmV052Ym5OMElHUjBQWFU5UG5VOVBXNTFiR3cvSWlJNlUzUnlhVzVuS0hVcE8yWjFibU4wYVc5dUlHRnpLSFVwZTNKbGRIVnliaUJEWlNo'
    || 'MUxDSndiMk5mYzJOdmNtVmpZWEprSWlrdWJXRndLR005UGloN1kyOWtaVHBrZENoakxrTlBSRVVwTEd4aFltVnNPbVIwS0dNdVRFRkNSVXdwTEhkb2VUcGtk'
    || 'Q2hqTGxkSVdWOUpWRjlOUVZSVVJWSlRLU3gwWVhKblpYUTZZeTVVUVZKSFJWUS9QMjUxYkd3c1lXTjBkV0ZzT21NdVFVTlVWVUZNUHo5dWRXeHNMSFZ1YVhS'
    || 'ek9tUjBLR011VlU1SlZGTXBMR052YlhCaGNtVTZaSFFvWXk1RFQwMVFRVkpGS1N4aVlYTnBjenBrZENoakxrSkJVMGxUS1N4a1pYSnBkbUYwYVc5dU9tUjBL'
    || 'R011VkVGU1IwVlVYMFJGVWtsV1FWUkpUMDRwTEhOMFlYUmxPbmRqS0dNdVUxUkJWRVVwTEhkb2VVNXZkRHBrZENoakxsZElXVjlPVDFSZlJWWkJURlZCVkVW'
    || 'RUtTeHlaWE52YkhabGMxZG9aVzQ2WkhRb1l5NVNSVk5QVEZaRlUxOVhTRVZPS1N4aGNtbDBhRzFsZEdsak9tUjBLR011UVZKSlZFaE5SVlJKUXlrc1kyOXRj'
    || 'R0Z5WVdKcGJHbDBlVHBrZENoakxrTlBUVkJCVWtGQ1NVeEpWRmtwZlNrcGZXWjFibU4wYVc5dUlHdGpLSFVwZTJOdmJuTjBJR005ZFM1d1lXNWxiSE11Y0c5'
    || 'algzTmpiM0psWTJGeVpDeGhQV0Z6S0hVcE8ybG1LSEp1S0dNcEtYSmxkSFZ5Ym50dFpYUTZNQ3h1YjNSTlpYUTZNQ3h3Wlc1a2FXNW5PakFzYm1FNk1DeHpZ'
    || 'Mjl5WldRNk1DeG9aV0ZrYkdsdVpUb2k0b0NVSWl4MlpYSmthV04wT2lKT1QxUmZVbFZPSWl4eVpXRmtWR2hwY3pwc2JpaGpLVDhpVkdobElITmpiM0psWTJG'
    || 'eVpDQjJhV1YzY3lCM1pYSmxJRzV2ZENCaWRXbHNkQ0JpZVNCMGFHbHpJSEoxYml3Z2IzSWdkR2hwY3lCeWIyeGxJR05oYm01dmRDQnpaV1VnZEdobGJTNGdV'
    || 'MjV2ZDJac1lXdGxJR1J2WlhNZ2JtOTBJR1JwYzNScGJtZDFhWE5vSUhSb1pTQjBkMjh1SWpvaVZHaGxJSE5qYjNKbFkyRnlaQ0J4ZFdWeWVTQm1ZV2xzWldR'
    || 'c0lITnZJRzV2ZEdocGJtY2dhR1Z5WlNCcGN5QnpZMjl5WldRdUlpeDFibUYyWVdsc1lXSnNaVHBqTG1WeWNtOXlmVHRqYjI1emRDQnRQV0V1Wm1sc2RHVnlL'
    || 'RWc5UGtndWMzUmhkR1U5UFQwaVRVVlVJaWt1YkdWdVozUm9MRVU5WVM1bWFXeDBaWElvU0QwK1NDNXpkR0YwWlQwOVBTSk9UMVJmVFVWVUlpa3ViR1Z1WjNS'
    || 'b0xGUTlZUzVtYVd4MFpYSW9TRDArU0M1emRHRjBaVDA5UFNKUVJVNUVTVTVISWlrdWJHVnVaM1JvTEhnOVlTNW1hV3gwWlhJb1NEMCtTQzV6ZEdGMFpUMDlQ'
    || 'U0pPTDBFaUtTNXNaVzVuZEdnc2FqMWhMbXhsYm1kMGFDMTRMRk05YWowOVBUQS9JazVQVkY5U1ZVNGlPa1UrTUQ4aVRrOVVYMDFGVkNJNmJUMDlQVEEvSWxC'
    || 'RlRrUkpUa2NpT2xRK01EOGlUVVZVWDFkSlZFaGZVRVZPUkVsT1J5STZJazFGVkNJc1VUMURaU2gxTENKd2IyTmZkbVZ5WkdsamRDSXBXekJkTEZJOVVUOVRk'
    || 'SEpwYm1jb1VTNVdSVkpFU1VOVVB6OGlJaWs2SWlJc2VqMGhJVkltSmxJaFBUMVRPM0psZEhWeWJudHRaWFE2YlN4dWIzUk5aWFE2UlN4d1pXNWthVzVuT2xR'
    || 'c2JtRTZlQ3h6WTI5eVpXUTZhaXhvWldGa2JHbHVaVHBxUFQwOU1EOGlibTkwSUhOamIzSmxaQ0k2WUNSN2JYMHZKSHRxZlNCdFpYUmdMSFpsY21ScFkzUTZV'
    || 'eXh5WldGa1ZHaHBjenA2UDJCVWFHVWdjMk52Y21WallYSmtJSEp2ZDNNZ1lXNWtJSFJvWlNCeWIyeHNMWFZ3SUhacFpYY2daR2x6WVdkeVpXVWdLSEp2ZDNN'
    || 'Z2MyRjVJQ1I3VTMwc0lGWmZVRTlEWDFaRlVrUkpRMVFnYzJGNWN5QWtlMUo5S1M0Z1ZISjFjM1FnYm1WcGRHaGxjaUIxYm5ScGJDQjBhR0YwSUdseklHVjRj'
    || 'R3hoYVc1bFpDNWdPbEUvVTNSeWFXNW5LRkV1VWtWQlJGOVVTRWxUUHo4aUlpazZJaUo5ZldOdmJuTjBJR0pzUFZzaVJFbFRRMDlXUlZJaUxDSk1TVTFKVkVW'
    || 'RUlpd2lVRkpQUkZWRFZFbFBUaUpkTEdwalBYdEVTVk5EVDFaRlVqb2lSR2x6WTI5MlpYSjVJaXhNU1UxSlZFVkVPaUpNYVcxcGRHVmtJSEoxYmlJc1VGSlBS'
    || 'RlZEVkVsUFRqb2lVSEp2WkhWamRHbHZiaUo5TEU1alBYdEVTVk5EVDFaRlVqb2lVbVZoWkhNZ2RHaGxJR0ZqWTI5MWJuUWdZVzVrSUhKbGNHOXlkSE1nZDJo'
    || 'aGRDQnBkQ0JtYjNWdVpDNGdRVzU1ZEdocGJtY2djbVZqZFhKeWFXNW5JR2x6SUdOeVpXRjBaV1FzSUhKbFpuSmxjMmhsWkNCdmJtTmxJSE52SUdsMGN5Qmpi'
    || 'M04wSUdOaGJpQmlaU0J0WldGemRYSmxaQ3dnZEdobGJpQnpkWE53Wlc1a1pXUXVJaXhNU1UxSlZFVkVPaUpVYUdVZ2MyRnRaU0JpZFdsc1pDQnZiaUJoYmlC'
    || 'cGMyOXNZWFJsWkNCM1lYSmxhRzkxYzJVZ2QybDBhQ0JoSUhKbGMyOTFjbU5sSUcxdmJtbDBiM0lnYjNabGNpQnBkQ3dnYzI4Z2RHaGxJR055WldScGRITWdh'
    || 'WFFnWW5WeWJuTWdZWEpsSUdGMGRISnBZblYwWVdKc1pTQmhibVFnWTJGdUlHSmxJSEpsWVdRZ1ltRmpheUJtY205dElHMWxkR1Z5YVc1bkxpQlVhR2x6SUds'
    || 'eklIUm9aU0J2Ym14NUlIQm9ZWE5sSUhSb1lYUWdjSEp2WkhWalpYTWdZU0J0WldGemRYSmxaQ0J1ZFcxaVpYSXVJaXhRVWs5RVZVTlVTVTlPT2lKR2RXeHNJ'
    || 'SE5qYjNCbExDQmhibVFnZEdobElISmxZM1Z5Y21sdVp5QnZZbXBsWTNSeklHRnlaU0JzWldaMElISjFibTVwYm1jdUlFRmtaSE1nZEdobElHOXdaWEpoZEds'
    || 'dmJtRnNJR1oxY201cGRIVnlaU0JoSUhCc1lYUm1iM0p0SUhSbFlXMGdaWGh3WldOMGN6b2diVzl1YVhSdmNpd2dZblZrWjJWMExDQnZZbXBsWTNRZ2RHRm5j'
    || 'eXdnWlhKeWIzSWdibTkwYVdacFkyRjBhVzl1TENCeVpXWnlaWE5vSUZOTVFTd2dZVzRnYjNCbGNtRjBhVzl1Y3lCMmFXVjNMaUo5TzJaMWJtTjBhVzl1SUdO'
    || 'ektIVXNZeWw3Y21WMGRYSnVJSFU5UFQxdWRXeHNmSHhqUFQwOWJuVnNiSHg4ZFQwOVBUQS9JaUk2SW40a0lpdFZLSFVxWXlsOVpuVnVZM1JwYjI0Z1EyTW9k'
    || 'U2w3WTI5dWMzUWdZejFUZEhKcGJtY29kUzVVU1VWU1B6OGlJaWt1ZEc5VmNIQmxja05oYzJVb0tTeGhQV0pzTG1sdVkyeDFaR1Z6S0dNcFAyTTZJa1JKVTBO'
    || 'UFZrVlNJaXh0UFdKc0xtbHVaR1Y0VDJZb1lTa3NSVDFOZENoMUxsSkJWRVZmVUVWU1gwTlNSVVJKVkNrc1ZEMU5kQ2gxTGtOU1JVUkpWRjlEUVZBcExIZzlU'
    || 'WFFvZFM1VFZFRk9SRWxPUjE5RFVrVkVTVlJUWDFCRlVsOU5UMDVVU0Nrc2FqMU5kQ2gxTGxORFNFVkVWVXhGUkY5RFQwMVFUMDVGVGxSVEtUOC9NQ3hUUFUx'
    || 'MEtIVXVWazlNVlUxRlgwTlBUVkJQVGtWT1ZGTXBQejh3TEZFOVV6NHdQMkFnS3lBa2UxTjlJSFp2YkhWdFpTMWtjbWwyWlc1Z09pSWlPMnhsZENCU0xIbzdh'
    || 'ajR3SmlaNElUMDliblZzYkNZbWVENHdQeWhTUFdCK0pIdFZLSGdwZlNCamNtVmthWFJ6TDIxdmJuUm9KSHRSZldBc2VqMGljSEp2YW1WamRHVmtJR1p5YjIw'
    || 'Z2RHaGxJR05oWkdWdVkyVWdkR2hwY3lCaWRXbHNaQ0J6WlhRZ1lXNWtJSFJvWlNCa2RYSmhkR2x2YmlCcGRDQnRaV0Z6ZFhKbFpDNGdUbTkwSUdFZ1ltbHNi'
    || 'QzRpS3loVFBqQS9JaUJVYUdVZ2RtOXNkVzFsTFdSeWFYWmxiaUJqYjIxd2IyNWxiblJ6SUdoaGRtVWdibThnYlc5dWRHaHNlU0JtYVdkMWNtVWdZWFFnWVd4'
    || 'c095QjBhR1ZwY2lCamIzTjBJSE5qWVd4bGN5QjNhWFJvSUdodmR5QnRkV05vSUdSaGRHRWdlVzkxSUhObGJtUXVJam9pSWlrcE9tbytNRDhvVWoxZ0pIdHFm'
    || 'U0J6WTJobFpIVnNaV1FnWTI5dGNHOXVaVzUwSkh0cVBUMDlNVDhpSWpvaWN5SjlKSHRSZldBc2VqMWhQVDA5SWxCU1QwUlZRMVJKVDA0aVB5SnlaV2RwYzNS'
    || 'bGNtVmtJRzl1SUdFZ2MyTm9aV1IxYkdVc0lHSjFkQ0IwYUdVZ2NtVmpiM0prWldRZ1kyRmtaVzVqWlNCcGN5QjZaWEp2TENCemJ5QnVieUJ0YjI1MGFHeDVJ'
    || 'R1pwWjNWeVpTQmpZVzRnWW1VZ1pHVnlhWFpsWkM0Z1ZISmxZWFFnZEdocGN5QmhjeUIxYm10dWIzZHVMQ0J1YjNRZ1lYTWdabkpsWlM0aU9pSjBhR1VnY21W'
    || 'amRYSnlhVzVuSUc5aWFtVmpkSE1nWVhKbElHbHVjM1JoYkd4bFpDQmhibVFnYzNWemNHVnVaR1ZrSUdGMElIUm9hWE1nZEdsbGNpd2djMjhnYm04Z1kyRmta'
    || 'VzVqWlNCcGN5QnZiaUJ5WldOdmNtUWdkRzhnY0hKdmFtVmpkQ0JtY205dExpQlVhR2x6SUdseklFNVBWQ0I2WlhKdklDMHRJR0oxYVd4a0lHRjBJRkJTVDBS'
    || 'VlExUkpUMDRnZEc4Z1oyVjBJSFJvWlNCdFpXRnpkWEpsWkNCdGIyNTBhR3g1SUdacFozVnlaUzRpS1RwVFBqQS9LRkk5WUNSN1UzMGdkbTlzZFcxbExXUnlh'
    || 'WFpsYmlCamIyMXdiMjVsYm5Ra2UxTTlQVDB4UHlJaU9pSnpJbjFnTEhvOUltNXZJR05oWkdWdVkyVXNJSE52SUc1dklHMXZiblJvYkhrZ2NISnZhbVZqZEds'
    || 'dmJpQnBjeUJ3YjNOemFXSnNaUzRnVkdocGN5QnBjeUJPVDFRZ2VtVnlieUF0TFNCMGFHVWdZMjl6ZENCelkyRnNaWE1nZDJsMGFDQm9iM2NnYlhWamFDQmtZ'
    || 'WFJoSUhsdmRTQnpaVzVrTGlJcE9paFNQU0p1YjNSb2FXNW5JSEpsWTNWeWNtbHVaeUlzZWowaWRHaHBjeUJ6YjJ4MWRHbHZiaUJwYm5OMFlXeHNjeUJ1YjNS'
    || 'b2FXNW5JRzl1SUdFZ2MyTm9aV1IxYkdVdUlFbDBJR052YzNSeklITjBiM0poWjJVZ2NHeDFjeUIzYUdGMFpYWmxjaUJqYjIxd2RYUmxJSFJvWlNCd1pXOXdi'
    || 'R1VnY1hWbGNubHBibWNnYVhRZ2RYTmxMaUlwTzJOdmJuTjBJRWc5ZTBSSlUwTlBWa1ZTT250bWFXZDFjbVU2SWpBZ1kzSmxaR2wwY3k5dGIyNTBhQ0lzYlc5'
    || 'dVpYazZJaUlzWW1GemFYTTZJbTV2ZEdocGJtY2dhWE1nYkdWbWRDQnlkVzV1YVc1bkxDQnpieUJ1YjNSb2FXNW5JSEpsWTNWeWN5NGdWR2hsSUc5dVpTMTBh'
    || 'VzFsSUhKbFlXUWdhWFJ6Wld4bUlHbHpJR0VnYUdGdVpHWjFiQ0J2WmlCeGRXVnlhV1Z6TGlKOUxFeEpUVWxVUlVRNmUyWnBaM1Z5WlRwVUppWlVQakEvWU9L'
    || 'SnBDQWtlMVVvVkNsOUlHTnlaV1JwZEhNZ2IyNWxMWFJwYldWZ09pSnVieUJqWVhBZ2MyVjBJaXh0YjI1bGVUcFVKaVpVUGpBL1kzTW9WQ3hGS1RvaUlpeGlZ'
    || 'WE5wY3pwVUppWlVQakEvSW1GdUlHVnVabTl5WTJWa0lHTmxhV3hwYm1jc0lHNXZkQ0JoYmlCbGMzUnBiV0YwWlRvZ1lTQnlaWE52ZFhKalpTQnRiMjVwZEc5'
    || 'eUlITjFjM0JsYm1SeklIUm9aU0IzWVhKbGFHOTFjMlVnZDJobGJpQnBkQ0JwY3lCeVpXRmphR1ZrTGlCSmRDQm5iM1psY201eklGZEJVa1ZJVDFWVFJTQmpj'
    || 'bVZrYVhSeklHOXViSGtnTFMwZ2JtOTBJSE5sY25abGNteGxjM01nWm1WaGRIVnlaWE1nWVc1a0lHNXZkQ0JCU1NCMGIydGxibk11SWpvaVExSkZSRWxVWDBO'
    || 'QlVDQnBjeUF3TENCemJ5QjBhR1Z5WlNCcGN5QnVieUJsYm1admNtTmxaQ0JqWldsc2FXNW5JRzl1SUhSb2FYTWdjblZ1TGlKOUxGQlNUMFJWUTFSSlQwNDZl'
    || 'MlpwWjNWeVpUcFNMRzF2Ym1WNU9tTnpLSGdzUlNrc1ltRnphWE02ZW4xOUxHVmxQVk4wY21sdVp5aDFMbE5GVkZSSlRrZGZVRkpGUmtsWVB6OGlJaWt1ZEhK'
    || 'cGJTZ3BPM0psZEhWeWJpQmliQzV0WVhBb0tHSXNTaWs5UGloN2FXUTZZaXhzWVdKbGJEcHFZMXRpWFN4emRHRjBaVHBLUEcwL0ltUnZibVVpT2tvOVBUMXRQ'
    || 'eUpqZFhKeVpXNTBJam9pWVdobFlXUWlMQzR1TGtoYllsMHNZbXgxY21JNlRtTmJZbDBzYzJWMGRHbHVaenBsWlQ5Z1UwVlVJQ1I3WldWOVgwUkZVRXhQV1Y5'
    || 'VVNVVlNJRDBnSnlSN1luMG5PMkE2WUZORlZDQThjSEpsWm1sNFBsOUVSVkJNVDFsZlZFbEZVaUE5SUNja2UySjlKenRnZlNrcGZXWjFibU4wYVc5dUlGUmpL'
    || 'SHR6YVhwbE9uVTlNVGtzWTI5c2IzSTZZejBpSXpJNVlqVmxPQ0o5S1h0eVpYUjFjbTRnYnk1cWMzaHpLQ0p6ZG1jaUxIdDNhV1IwYURwMUxHaGxhV2RvZERw'
    || 'MUxIWnBaWGRDYjNnNklqQWdNQ0EwTXk0MElEUXpMalVpTEdacGJHdzZZeXh5YjJ4bE9pSnBiV2NpTENKaGNtbGhMV3hoWW1Wc0lqb2lVMjV2ZDJac1lXdGxJ'
    || 'aXhqYUdsc1pISmxianBiYnk1cWMzZ29JbkJoZEdnaUxIdGtPaUpOTXpjdU1qWXpOelEyTlN3ek15NHhNamc1TURZZ1RESTRMakE0TnprMk5UVXNNamN1T0RJ'
    || 'NE1USTFJRU15Tmk0M09UZzVNREkxTERJM0xqQTROVGt6T0NBeU5TNHhOVEEwTmpVMUxESTNMalV5TnpNME5DQXlOQzQwTURRek56RTFMREk0TGpneE5qUXdO'
    || 'aUJETWpRdU1URTFNekE0TlN3eU9TNHpNalF5TVRrZ01qUXVNREF5TURJM05Td3lPUzQ0T0RJNE1USWdNalF1TURVMk56RTFOU3d6TUM0ME1qVTNPREVnVERJ'
    || 'MExqQTFOamN4TlRVc05EQXVOemcxTVRVMklFTXlOQzR3TlRZM01UVTFMRFF5TGpJMk5UWXlOU0F5TlM0eU5UazRNemsxTERRekxqUTJPRGMxSURJMkxqYzBO'
    || 'REl4TlRVc05ETXVORFk0TnpVZ1F6STRMakl5TkRZNE16VXNORE11TkRZNE56VWdNamt1TkRJM09EQTROU3cwTWk0eU5qVTJNalVnTWprdU5ESTNPREE0TlN3'
    || 'ME1DNDNPRFV4TlRZZ1RESTVMalF5Tnpnd09EVXNNelF1T0RJNE1USTFJRXd6TkM0MU5qZzBNek0xTERNM0xqYzVOamczTlNCRE16VXVPRFUzTkRrMk5Td3pP'
    || 'QzQxTkRJNU5qa2dNemN1TlRBNU9ETTVOU3d6T0M0d09UYzJOVFlnTXpndU1qVXlNREkzTlN3ek5pNDRNRGcxT1RRZ1F6TTRMams1T0RFeU1UVXNNelV1TlRF'
    || 'NU5UTXhJRE00TGpVMU5qY3hOVFVzTXpNdU9EY3hNRGswSURNM0xqSTJNemMwTmpVc016TXVNVEk0T1RBMkluMHBMRzh1YW5ONEtDSndZWFJvSWl4N1pEb2lU'
    || 'VEUwTGpRME16UXpNelVzTWpFdU56WTVOVE14SUVNeE5DNDBOVGt3TlRnMUxESXdMamd4TWpVZ01UTXVPVFUxTVRVeU5Td3hPUzQ1TWpFNE56VWdNVE11TVRJ'
    || 'M01ESTNOU3d4T1M0ME5ERTBNRFlnVERNdU9UVXhNalEyTkRrc01UUXVNVFEwTlRNeElFTXpMalUxTWpnd09EUTVMREV6TGpreE5EQTJNaUF6TGpBNU5UYzNO'
    || 'elE1TERFekxqYzVNamsyT1NBeUxqWXpPRGMwTmpRNUxERXpMamM1TWprMk9TQkRNUzQyT1Rjek16azBPU3d4TXk0M09USTVOamtnTUM0NE1qSXpNemswT1RV'
    || 'c01UUXVNamsyT0RjMUlEQXVNelV6TlRnNU5EazFMREUxTGpFd09UTTNOU0JETFRBdU16Y3lPVGN5TlRBMUxERTJMak0yTnpFNE9DQXdMakEyTURZeU1UUTVO'
    || 'U3d4Tnk0NU9EQTBOamtnTVM0ek1UZzBNek0wT1N3eE9DNDNNRGN3TXpFZ1REWXVOakEzTkRrMk5Ea3NNakV1TnpVM09ERXlJRXd4TGpNeE9EUXpNelE1TERJ'
    || 'MExqZ3hNalVnUXpBdU56QTVNRFU0TkRrMUxESTFMakUyTkRBMk1pQXdMakkzTVRVMU9EUTVOU3d5TlM0M016QTBOamtnTUM0d09URTROekUwT1RVc01qWXVO'
    || 'REV3TVRVMklFTXRNQzR3T1RFM01qSTFNRFVzTWpjdU1EZzVPRFEwSURBdU1EQXlNREkzTkRrME9UWXNNamN1T0RBd056Z3hJREF1TXpVek5UZzVORGsxTERJ'
    || 'NExqUXhNREUxTmlCRE1DNDRNakl6TXprME9UVXNNamt1TWpJeU5qVTJJREV1TmprM016TTVORGtzTWprdU56STJOVFl5SURJdU5qTTBPRE01TkRrc01qa3VO'
    || 'ekkyTlRZeUlFTXpMakE1TlRjM056UTVMREk1TGpjeU5qVTJNaUF6TGpVMU1qZ3dPRFE1TERJNUxqWXdOVFEyT1NBekxqazFNVEkwTmpRNUxESTVMak0zTlNC'
    || 'TU1UTXVNVEkzTURJM05Td3lOQzR3TnpneE1qVWdRekV6TGprME56TXpPVFVzTWpNdU5qQXhOVFl5SURFMExqUTFNVEkwTmpVc01qSXVOekU0TnpVZ01UUXVO'
    || 'RFF6TkRNek5Td3lNUzQzTmprMU16RWlmU2tzYnk1cWMzZ29JbkJoZEdnaUxIdGtPaUpOTmk0d016TXlOemMwT1N3eE1DNHpPVEEyTWpVZ1RERTFMakl3T1RB'
    || 'MU9EVXNNVFV1TmpnM05TQkRNVFl1TWpjNU16Y3hOU3d4Tmk0ek1EZzFPVFFnTVRjdU5UazVOamd6TlN3eE5pNHhNRFUwTmprZ01UZ3VORFF6TkRNek5Td3hO'
    || 'UzR5T0RFeU5TQkRNVGd1T1RjNE5UZzVOU3d4TkM0M09Ea3dOaklnTVRrdU16RXdOakl4TlN3eE5DNHdPRFU1TXpnZ01Ua3VNekV3TmpJeE5Td3hNeTR6TURR'
    || 'Mk9EZ2dUREU1TGpNeE1EWXlNVFVzTWk0Mk9EYzFJRU14T1M0ek1UQTJNakUxTERFdU1qQXpNVEkxSURFNExqRXdOelE1TmpVc01DQXhOaTQyTWpjd01qYzFM'
    || 'REFnUXpFMUxqRTBNalkxTWpVc01DQXhNeTQ1TXprMU1qYzFMREV1TWpBek1USTFJREV6TGprek9UVXlOelVzTWk0Mk9EYzFJRXd4TXk0NU16azFNamMxTERn'
    || 'dU56TXdORFk1SUV3NExqY3lPRFU0T1RRNUxEVXVOekl5TmpVMklFTTNMalF6T1RVeU56UTVMRFF1T1RjMk5UWXlJRFV1TnpreE1EZzVORGtzTlM0ME1UYzVO'
    || 'amtnTlM0d05EUTVPVFkwT1N3MkxqY3dOekF6TVNCRE5DNHlPVGc1TURJME9TdzNMams1TmpBNU5DQTBMamMwTkRJeE5UUTVMRGt1TmpRME5UTXhJRFl1TURN'
    || 'ek1qYzNORGtzTVRBdU16a3dOakkxSW4wcExHOHVhbk40S0NKd1lYUm9JaXg3WkRvaVRUSTJMalkyTmpBNE9UVXNNakl1TVRrNU1qRTVJRU15Tmk0Mk5qWXdP'
    || 'RGsxTERJeUxqUXdNak0wTkNBeU5pNDFORGc1TURJMUxESXlMalk0TXpVNU5DQXlOaTQwTURRek56RTFMREl5TGpnek1qQXpNU0JNTWpJdU56WTNOalV5TlN3'
    || 'eU5pNDBOamczTlNCRE1qSXVOakl6TVRJeE5Td3lOaTQyTVRNeU9ERWdNakl1TXpNM09UWTFOU3d5Tmk0M016QTBOamtnTWpJdU1UTTBPRE01TlN3eU5pNDNN'
    || 'ekEwTmprZ1RESXhMakl3T1RBMU9EVXNNall1TnpNd05EWTVJRU15TVM0d01EVTVNek0xTERJMkxqY3pNRFEyT1NBeU1DNDNNakEzTnpjMUxESTJMall4TXpJ'
    || 'NE1TQXlNQzQxTnpZeU5EWTFMREkyTGpRMk9EYzFJRXd4Tmk0NU16VTJNakUxTERJeUxqZ3pNakF6TVNCRE1UWXVOemt4TURnNU5Td3lNaTQyT0RNMU9UUWdN'
    || 'VFl1Tmpjek9UQXlOU3d5TWk0ME1ESXpORFFnTVRZdU5qY3pPVEF5TlN3eU1pNHhPVGt5TVRrZ1RERTJMalkzTXprd01qVXNNakV1TWpjek5ETTRJRU14Tmk0'
    || 'Mk56TTVNREkxTERJeExqQTJOalF3TmlBeE5pNDNPVEV3T0RrMUxESXdMamM0TlRFMU5pQXhOaTQ1TXpVMk1qRTFMREl3TGpZME1EWXlOU0JNTWpBdU5UYzJN'
    || 'alEyTlN3eE55QkRNakF1TnpJd056YzNOU3d4Tmk0NE5UVTBOamtnTWpFdU1EQTFPVE16TlN3eE5pNDNNemd5T0RFZ01qRXVNakE1TURVNE5Td3hOaTQzTXpn'
    || 'eU9ERWdUREl5TGpFek5EZ3pPVFVzTVRZdU56TTRNamd4SUVNeU1pNHpNemM1TmpVMUxERTJMamN6T0RJNE1TQXlNaTQyTWpNeE1qRTFMREUyTGpnMU5UUTJP'
    || 'U0F5TWk0M05qYzJOVEkxTERFM0lFd3lOaTQwTURRek56RTFMREl3TGpZME1EWXlOU0JETWpZdU5UUTRPVEF5TlN3eU1DNDNPRFV4TlRZZ01qWXVOalkyTURn'
    || 'NU5Td3lNUzR3TmpZME1EWWdNall1TmpZMk1EZzVOU3d5TVM0eU56TTBNemdnVERJMkxqWTJOakE0T1RVc01qSXVNVGs1TWpFNUlGb2dUVEl6TGpReE9UazVO'
    || 'alVzTWpFdU56VXpPVEEySUV3eU15NDBNVGs1T1RZMUxESXhMamN4TkRnME5DQkRNak11TkRFNU9UazJOU3d5TVM0MU5qWTBNRFlnTWpNdU16TTBNRFU0TlN3'
    || 'eU1TNHpOVGt6TnpVZ01qTXVNakk0TlRnNU5Td3lNUzR5TlNCTU1qSXVNVFUwTXpjeE5Td3lNQzR4TnprMk9EZ2dRekl5TGpBME9Ea3dNalVzTWpBdU1EY3dN'
    || 'ekV5SURJeExqZzBNVGczTVRVc01Ua3VPVGcwTXpjMUlESXhMalk0T1RVeU56VXNNVGt1T1RnME16YzFJRXd5TVM0Mk5UQTBOalUxTERFNUxqazRORE0zTlNC'
    || 'RE1qRXVOVEF5TURJM05Td3hPUzQ1T0RRek56VWdNakV1TWprME9UazJOU3d5TUM0d056QXpNVElnTWpFdU1UZzFOakl4TlN3eU1DNHhOemsyT0RnZ1RESXdM'
    || 'akV4TlRNd09EVXNNakV1TWpVZ1F6SXdMakF3T1Rnek9UVXNNakV1TXpVMU5EWTVJREU1TGpreU16a3dNalVzTWpFdU5UWXlOU0F4T1M0NU1qTTVNREkxTERJ'
    || 'eExqY3hORGcwTkNCTU1Ua3VPVEl6T1RBeU5Td3lNUzQzTlRNNU1EWWdRekU1TGpreU16a3dNalVzTWpFdU9UQTJNalVnTWpBdU1EQTVPRE01TlN3eU1pNHhN'
    || 'VE15T0RFZ01qQXVNVEUxTXpBNE5Td3lNaTR5TVRnM05TQk1NakV1TVRnMU5qSXhOU3d5TXk0eU9USTVOamtnUXpJeExqSTVORGs1TmpVc01qTXVNems0TkRN'
    || 'NElESXhMalV3TWpBeU56VXNNak11TkRnME16YzFJREl4TGpZMU1EUTJOVFVzTWpNdU5EZzBNemMxSUV3eU1TNDJPRGsxTWpjMUxESXpMalE0TkRNM05TQkRN'
    || 'akV1T0RReE9EY3hOU3d5TXk0ME9EUXpOelVnTWpJdU1EUTRPVEF5TlN3eU15NHpPVGcwTXpnZ01qSXVNVFUwTXpjeE5Td3lNeTR5T1RJNU5qa2dUREl6TGpJ'
    || 'eU9EVTRPVFVzTWpJdU1qRTROelVnUXpJekxqTXpOREExT0RVc01qSXVNVEV6TWpneElESXpMalF4T1RrNU5qVXNNakV1T1RBMk1qVWdNak11TkRFNU9UazJO'
    || 'U3d5TVM0M05UTTVNRFlnV2lKOUtTeHZMbXB6ZUNnaWNHRjBhQ0lzZTJRNklrMHlPQzR3T0RjNU5qVTFMREUxTGpZNE56VWdURE0zTGpJMk16YzBOalVzTVRB'
    || 'dU16a3dOakkxSUVNek9DNDFOVEk0TURnMUxEa3VOalE0TkRNNElETTRMams1T0RFeU1UVXNOeTQ1T1RZd09UUWdNemd1TWpVeU1ESTNOU3cyTGpjd056QXpN'
    || 'U0JETXpjdU5UQTFPVE16TlN3MUxqUXhOemsyT1NBek5TNDROVGMwT1RZMUxEUXVPVGMyTlRZeUlETTBMalUyT0RRek16VXNOUzQzTWpJMk5UWWdUREk1TGpR'
    || 'eU56Z3dPRFVzT0M0Mk9URTBNRFlnVERJNUxqUXlOemd3T0RVc01pNDJPRGMxSUVNeU9TNDBNamM0TURnMUxERXVNakF6TVRJMUlESTRMakl5TkRZNE16VXNM'
    || 'VFV1TmpnME16UXhPRGxsTFRFMElESTJMamMwTkRJeE5UVXNMVFV1TmpnME16UXhPRGxsTFRFMElFTXlOUzR5TlRrNE16azFMQzAxTGpZNE5ETTBNVGc1WlMw'
    || 'eE5DQXlOQzR3TlRZM01UVTFMREV1TWpBek1USTFJREkwTGpBMU5qY3hOVFVzTWk0Mk9EYzFJRXd5TkM0d05UWTNNVFUxTERFekxqQTVNemMxSUVNeU5DNHdN'
    || 'RFU1TXpNMUxERXpMall6TWpneE1pQXlOQzR4TVRFME1ESTFMREUwTGpFNU5UTXhNaUF5TkM0ME1EUXpOekUxTERFMExqY3dNekV5TlNCRE1qVXVNVFV3TkRZ'
    || 'MU5Td3hOUzQ1T1RJeE9EZ2dNall1TnprNE9UQXlOU3d4Tmk0ME16TTFPVFFnTWpndU1EZzNPVFkxTlN3eE5TNDJPRGMxSW4wcExHOHVhbk40S0NKd1lYUm9J'
    || 'aXg3WkRvaVRURTNMakEwT0Rrd01qVXNNamN1TlRFMU5qSTFJRU14Tmk0ME16azFNamMxTERJM0xqTTVPRFF6T0NBeE5TNDNPRGN4T0RNMUxESTNMalE1TmpB'
    || 'NU5DQXhOUzR5TURrd05UZzFMREkzTGpneU9ERXlOU0JNTmk0d016TXlOemMwT1N3ek15NHhNamc1TURZZ1F6UXVOelEwTWpFMU5Ea3NNek11T0RjeE1EazBJ'
    || 'RFF1TWprNE9UQXlORGtzTXpVdU5URTVOVE14SURVdU1EUTBPVGsyTkRrc016WXVPREE0TlRrMElFTTFMamM1TVRBNE9UUTVMRE00TGpFd01UVTJNaUEzTGpR'
    || 'ek9UVXlOelE1TERNNExqVTBNamsyT1NBNExqY3lPRFU0T1RRNUxETTNMamM1TmpnM05TQk1NVE11T1RNNU5USTNOU3d6TkM0M09Ea3dOaklnVERFekxqa3pP'
    || 'VFV5TnpVc05EQXVOemcxTVRVMklFTXhNeTQ1TXprMU1qYzFMRFF5TGpJMk5UWXlOU0F4TlM0eE5ESTJOVEkxTERRekxqUTJPRGMxSURFMkxqWXlOekF5TnpV'
    || 'c05ETXVORFk0TnpVZ1F6RTRMakV3TnpRNU5qVXNORE11TkRZNE56VWdNVGt1TXpFd05qSXhOU3cwTWk0eU5qVTJNalVnTVRrdU16RXdOakl4TlN3ME1DNDNP'
    || 'RFV4TlRZZ1RERTVMak14TURZeU1UVXNNekF1TVRZM09UWTVJRU14T1M0ek1UQTJNakUxTERJNExqZ3lPREV5TlNBeE9DNHpNekF4TlRJMUxESTNMamN4T0Rj'
    || 'MUlERTNMakEwT0Rrd01qVXNNamN1TlRFMU5qSTFJbjBwTEc4dWFuTjRLQ0p3WVhSb0lpeDdaRG9pVFRReUxqazVPREV5TVRVc01UVXVNRGM0TVRJMUlFTTBN'
    || 'aTR5TlRVNU16TTFMREV6TGpjNE5URTFOaUEwTUM0Mk1ETTFPRGsxTERFekxqTTBNemMxSURNNUxqTXhORFV5TnpVc01UUXVNRGc1T0RRMElFd3pNQzR4TXpn'
    || 'M05EWTFMREU1TGpNNE5qY3hPU0JETWprdU1qVTVPRE01TlN3eE9TNDRPVFExTXpFZ01qZ3VOemMxTkRZMU5Td3lNQzQ0TWpReU1Ua2dNamd1TnpreE1EZzVO'
    || 'U3d5TVM0M05qazFNekVnUXpJNExqYzRNekkzTnpVc01qSXVOekV3T1RNNElESTVMakkyTnpZMU1qVXNNak11TmpJNE9UQTJJRE13TGpFek9EYzBOalVzTWpR'
    || 'dU1USTRPVEEySUV3ek9TNHpNVFExTWpjMUxESTVMalF5T1RZNE9DQkROREF1TmpBek5UZzVOU3d6TUM0eE56RTROelVnTkRJdU1qVXlNREkzTlN3eU9TNDNN'
    || 'ekEwTmprZ05ESXVPVGs0TVRJeE5Td3lPQzQwTkRFME1EWWdRelF6TGpjME5ESXhOVFVzTWpjdU1UVXlNelEwSURRekxqSTVPRGt3TWpVc01qVXVOVEF6T1RB'
    || 'MklEUXlMakF3T1Rnek9UVXNNalF1TnpVM09ERXlJRXd6Tmk0NE1UUTFNamMxTERJeExqYzFOemd4TWlCTU5ESXVNREE1T0RNNU5Td3hPQzQzTlRjNE1USWdR'
    || 'elF6TGpNd01qZ3dPRFVzTVRndU1ERTFOakkxSURRekxqYzBOREl4TlRVc01UWXVNelkzTVRnNElEUXlMams1T0RFeU1UVXNNVFV1TURjNE1USTFJbjBwWFgw'
    || 'cGZXTnZibk4wSUZKalBYdHZkbVZ5ZG1sbGR6cHZMbXB6ZUhNb2J5NUdjbUZuYldWdWRDeDdZMmhwYkdSeVpXNDZXMjh1YW5ONEtDSnlaV04wSWl4N2VEb2lN'
    || 'aUlzZVRvaU1pSXNkMmxrZEdnNklqVXVOU0lzYUdWcFoyaDBPaUkxTGpVaUxISjRPaUl4TGpJaWZTa3NieTVxYzNnb0luSmxZM1FpTEh0NE9pSTRMalVpTEhr'
    || 'NklqSWlMSGRwWkhSb09pSTFMalVpTEdobGFXZG9kRG9pTlM0MUlpeHllRG9pTVM0eUluMHBMRzh1YW5ONEtDSnlaV04wSWl4N2VEb2lNaUlzZVRvaU9DNDFJ'
    || 'aXgzYVdSMGFEb2lOUzQxSWl4b1pXbG5hSFE2SWpVdU5TSXNjbmc2SWpFdU1pSjlLU3h2TG1wemVDZ2ljbVZqZENJc2UzZzZJamd1TlNJc2VUb2lPQzQxSWl4'
    || 'M2FXUjBhRG9pTlM0MUlpeG9aV2xuYUhRNklqVXVOU0lzY25nNklqRXVNaUo5S1YxOUtTeHdaVzl3YkdVNmJ5NXFjM2h6S0c4dVJuSmhaMjFsYm5Rc2UyTm9h'
    || 'V3hrY21WdU9sdHZMbXB6ZUNnaVkybHlZMnhsSWl4N1kzZzZJallpTEdONU9pSTFMalVpTEhJNklqSXVOQ0o5S1N4dkxtcHplQ2dpY0dGMGFDSXNlMlE2SWsw'
    || 'eUlERXpMalZqTUMweUxqSWdNUzQ0TFRNdU5pQTBMVE11Tm5NMElERXVOQ0EwSURNdU5pSjlLU3h2TG1wemVDZ2ljR0YwYUNJc2UyUTZJazB4TVNBMExqSmhN'
    || 'aTR5SURJdU1pQXdJREFnTVNBd0lEUXVNMDB4TVM0MklERXpMalZqTUMweExqY3RMamN0TWk0NUxURXVPQzB6TGpRaWZTbGRmU2tzYzJWbmJXVnVkSE02Ynk1'
    || 'cWMzaHpLRzh1Um5KaFoyMWxiblFzZTJOb2FXeGtjbVZ1T2x0dkxtcHplQ2dpWTJseVkyeGxJaXg3WTNnNklqWWlMR041T2lJMklpeHlPaUl6TGpZaWZTa3Ni'
    || 'eTVxYzNnb0ltTnBjbU5zWlNJc2UyTjRPaUl4TUNJc1kzazZJakV3SWl4eU9pSXpMallpZlNsZGZTa3NhV1JsYm5ScGRIazZieTVxYzNoektHOHVSbkpoWjIx'
    || 'bGJuUXNlMk5vYVd4a2NtVnVPbHR2TG1wemVDZ2ljR0YwYUNJc2UyUTZJazA0SURKaE15QXpJREFnTUNBeElETWdNM1l4SW4wcExHOHVhbk40S0NKd1lYUm9J'
    || 'aXg3WkRvaVRUVWdObFkxWVRNZ015QXdJREFnTVNBeExUSXVNaUo5S1N4dkxtcHplQ2dpY0dGMGFDSXNlMlE2SWswMExqVWdOeTQxWXpBZ015QXhJRFF1TlNB'
    || 'ekxqVWdOaTQxSW4wcExHOHVhbk40S0NKd1lYUm9JaXg3WkRvaVRUZ2dObll6TGpVaWZTa3NieTVxYzNnb0luQmhkR2dpTEh0a09pSk5NVEV1TlNBM0xqVmpN'
    || 'Q0F5TFM0MElETXVNeTB4TGpJZ05DNDBJbjBwWFgwcExHTnZkbVZ5WVdkbE9tOHVhbk40Y3lodkxrWnlZV2R0Wlc1MExIdGphR2xzWkhKbGJqcGJieTVxYzNn'
    || 'b0ltTnBjbU5zWlNJc2UyTjRPaUk0SWl4amVUb2lPQ0lzY2pvaU5pSjlLU3h2TG1wemVDZ2ljR0YwYUNJc2UyUTZJazA0SURKaE5pQTJJREFnTUNBeElEQWdN'
    || 'VElpTEdacGJHdzZJbU4xY25KbGJuUkRiMnh2Y2lJc2MzUnliMnRsT2lKdWIyNWxJaXh2Y0dGamFYUjVPaUl1TWpJaWZTa3NieTVxYzNnb0luQmhkR2dpTEh0'
    || 'a09pSk5PQ0EwTGpWMk15NDFiREl1TlNBeExqWWlmU2xkZlNrc2JXOXVaWGs2Ynk1cWMzaHpLRzh1Um5KaFoyMWxiblFzZTJOb2FXeGtjbVZ1T2x0dkxtcHpl'
    || 'Q2dpY0dGMGFDSXNlMlE2SWswNElERXVPSFl4TWk0MEluMHBMRzh1YW5ONEtDSndZWFJvSWl4N1pEb2lUVEV4SURRdU5tTXdMVEV1TVMweExqTXRNUzQ1TFRN'
    || 'dE1TNDVjeTB6SUM0NExUTWdNUzQ1WXpBZ01TNHlJREV1TWlBeExqY2dNeUF5TGpKek15QXhJRE1nTWk0ell6QWdNUzR5TFRFdU15QXlMVE1nTW5NdE15MHVP'
    || 'QzB6TFRJaWZTbGRmU2tzYzJocFpXeGtPbTh1YW5ONGN5aHZMa1p5WVdkdFpXNTBMSHRqYUdsc1pISmxianBiYnk1cWMzZ29JbkJoZEdnaUxIdGtPaUpOT0NB'
    || 'eExqZ2dNeUF6TGpoMk5HTXdJRE1nTWk0eElEVXVOQ0ExSURZdU5DQXlMamt0TVNBMUxUTXVOQ0ExTFRZdU5IWXRORm9pZlNrc2J5NXFjM2dvSW5CaGRHZ2lM'
    || 'SHRrT2lKTk5pQTRMakZzTVM0MklERXVOa3d4TUM0MElEWXVOaUo5S1YxOUtTeDBZV0pzWlRwdkxtcHplSE1vYnk1R2NtRm5iV1Z1ZEN4N1kyaHBiR1J5Wlc0'
    || 'NlcyOHVhbk40S0NKeVpXTjBJaXg3ZURvaU1pSXNlVG9pTWk0NElpeDNhV1IwYURvaU1USWlMR2hsYVdkb2REb2lNVEF1TkNJc2NuZzZJakV1TkNKOUtTeHZM'
    || 'bXB6ZUNnaWNHRjBhQ0lzZTJRNklrMHlJRFl1TTJneE1rMDJMalFnTmk0emRqWXVPU0o5S1YxOUtTeG1iRzkzT204dWFuTjRjeWh2TGtaeVlXZHRaVzUwTEh0'
    || 'amFHbHNaSEpsYmpwYmJ5NXFjM2dvSW5KbFkzUWlMSHQ0T2lJeExqWWlMSGs2SWpVdU9DSXNkMmxrZEdnNklqUWlMR2hsYVdkb2REb2lOQzQwSWl4eWVEb2lN'
    || 'UzR4SW4wcExHOHVhbk40S0NKeVpXTjBJaXg3ZURvaU1UQXVOQ0lzZVRvaU1pNDBJaXgzYVdSMGFEb2lOQ0lzYUdWcFoyaDBPaUkwTGpRaUxISjRPaUl4TGpF'
    || 'aWZTa3NieTVxYzNnb0luSmxZM1FpTEh0NE9pSXhNQzQwSWl4NU9pSTVMaklpTEhkcFpIUm9PaUkwSWl4b1pXbG5hSFE2SWpRdU5DSXNjbmc2SWpFdU1TSjlL'
    || 'U3h2TG1wemVDZ2ljR0YwYUNJc2UyUTZJazAxTGpZZ09HZ3lMakpoTVM0eUlERXVNaUF3SURBZ01DQXhMakl0TVM0eVZqUXVObWd4TGpSTk5TNDJJRGhvTWk0'
    || 'eVlURXVNaUF4TGpJZ01DQXdJREVnTVM0eUlERXVNbll5TGpKb01TNDBJbjBwWFgwcExHTm9aV05yT204dWFuTjRjeWh2TGtaeVlXZHRaVzUwTEh0amFHbHNa'
    || 'SEpsYmpwYmJ5NXFjM2dvSW1OcGNtTnNaU0lzZTJONE9pSTRJaXhqZVRvaU9DSXNjam9pTmlKOUtTeHZMbXB6ZUNnaWNHRjBhQ0lzZTJRNklrMDFMalFnT0M0'
    || 'eUlEY3VNaUF4TUd3ekxqUXRNeTQzSW4wcFhYMHBMSGRoY200NmJ5NXFjM2h6S0c4dVJuSmhaMjFsYm5Rc2UyTm9hV3hrY21WdU9sdHZMbXB6ZUNnaWNHRjBh'
    || 'Q0lzZTJRNklrMDRJREl1TkNBeExqa2dNVE5vTVRJdU1rdzRJREl1TkZvaWZTa3NieTVxYzNnb0luQmhkR2dpTEh0a09pSk5PQ0EyTGpSMk0wMDRJREV4TGpO'
    || 'MkxqRWlmU2xkZlNrc2MzQmhjbXM2Ynk1cWMzaHpLRzh1Um5KaFoyMWxiblFzZTJOb2FXeGtjbVZ1T2x0dkxtcHplQ2dpY0dGMGFDSXNlMlE2SWsweUlERXhM'
    || 'alJzTXk0eUxUTXVOaUF5TGpRZ01pQTBMalF0TlNKOUtTeHZMbXB6ZUNnaWNHRjBhQ0lzZTJRNklrMHhNaUEwTGpob0xUSXVOazB4TWlBMExqaDJNaTQySW4w'
    || 'cFhYMHBMR05zYjJOck9tOHVhbk40Y3lodkxrWnlZV2R0Wlc1MExIdGphR2xzWkhKbGJqcGJieTVxYzNnb0ltTnBjbU5zWlNJc2UyTjRPaUk0SWl4amVUb2lP'
    || 'Q0lzY2pvaU5pSjlLU3h2TG1wemVDZ2ljR0YwYUNJc2UyUTZJazA0SURRdU5sWTRiREl1TmlBeExqY2lmU2xkZlNrc2JHRjVaWEp6T204dWFuTjRjeWh2TGta'
    || 'eVlXZHRaVzUwTEh0amFHbHNaSEpsYmpwYmJ5NXFjM2dvSW5CaGRHZ2lMSHRrT2lKTk9DQXhMamtnTWlBMWJEWWdNeTR4VERFMElEVWdPQ0F4TGpsYUluMHBM'
    || 'Rzh1YW5ONEtDSndZWFJvSWl4N1pEb2lUVElnT0M0MElEZ2dNVEV1Tld3MkxUTXVNVTB5SURFeExqUWdPQ0F4TkM0MWJEWXRNeTR4SW4wcFhYMHBmVHRtZFc1'
    || 'amRHbHZiaUJFWXloN2JtRnRaVHAxTEhOcGVtVTZZejB4TlgwcGUzSmxkSFZ5YmlCdkxtcHplQ2dpYzNabklpeDdkMmxrZEdnNll5eG9aV2xuYUhRNll5eDJh'
    || 'V1YzUW05NE9pSXdJREFnTVRZZ01UWWlMR1pwYkd3NkltNXZibVVpTEhOMGNtOXJaVG9pWTNWeWNtVnVkRU52Ykc5eUlpeHpkSEp2YTJWWGFXUjBhRG9pTVM0'
    || 'MU5TSXNjM1J5YjJ0bFRHbHVaV05oY0RvaWNtOTFibVFpTEhOMGNtOXJaVXhwYm1WcWIybHVPaUp5YjNWdVpDSXNJbUZ5YVdFdGFHbGtaR1Z1SWpvaWRISjFa'
    || 'U0lzWTJocGJHUnlaVzQ2VW1OYmRWMTlLWDFtZFc1amRHbHZiaUJQWXloN2MyOXNkWFJwYjI0NmRTeHpkV0owYVhSc1pUcGpMSE5sWTNScGIyNXpPbUVzWVdO'
    || 'MGFYWmxPbTBzYjI1UWFXTnJPa1VzWm05dmREcFVmU2w3WTI5dWMzUWdlRDFTUFQ1U0xuUnZURzkzWlhKRFlYTmxLQ2t1Y21Wd2JHRmpaU2d2VzE1aExYb3dM'
    || 'VGxkS3k5bkxDSWlLU3hxUFhnb2RTa3NVejFqUDNnb1l5azZJaUlzVVQwaElWTW1KaUZxTG1sdVkyeDFaR1Z6S0ZNcEppWWhVeTVwYm1Oc2RXUmxjeWhxS1R0'
    || 'eVpYUjFjbTRnYnk1cWMzaHpLQ0poYzJsa1pTSXNlMk5zWVhOelRtRnRaVG9pYzJsa1pTSXNZMmhwYkdSeVpXNDZXMjh1YW5ONGN5Z2laR2wySWl4N1kyeGhj'
    || 'M05PWVcxbE9pSnphV1JsWDE5aWNtRnVaQ0lzWTJocGJHUnlaVzQ2VzI4dWFuTjRLRlJqTEh0emFYcGxPakl5ZlNrc2J5NXFjM2h6S0NKa2FYWWlMSHR6ZEhs'
    || 'c1pUcDdiV2x1VjJsa2RHZzZNSDBzWTJocGJHUnlaVzQ2VzI4dWFuTjRLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbk5wWkdWZlgzZHZjbVJ0WVhKcklpeGph'
    || 'R2xzWkhKbGJqcDFmU2tzVVQ5dkxtcHplQ2dpWkdsMklpeDdZMnhoYzNOT1lXMWxPaUp6YVdSbFgxOXpkV0lpTEdOb2FXeGtjbVZ1T21OOUtUcHVkV3hzWFgw'
    || 'cFhYMHBMRzh1YW5ONEtDSnVZWFlpTEh0amJHRnpjMDVoYldVNkltNWhkaUlzWTJocGJHUnlaVzQ2WVM1dFlYQW9LRklzZWlrOVBudGpiMjV6ZENCSVBYbytN'
    || 'RDloVzNvdE1WMHVaM0p2ZFhBNmRtOXBaQ0F3TEdWbFBWSXVaM0p2ZFhBbUpsSXVaM0p2ZFhBaFBUMUlQMUl1WjNKdmRYQTZiblZzYkN4aVBXOHVhbk40Y3ln'
    || 'aVluVjBkRzl1SWl4N1kyeGhjM05PWVcxbE9pSnVZWFpmWDJsMFpXMGlLeWhTTG1keWIzVndQeUlnYm1GMlgxOXBkR1Z0TFMxemRXSWlPaUlpS1Nzb1VpNXBa'
    || 'RDA5UFcwL0lpQnVZWFpmWDJsMFpXMHRMVzl1SWpvaUlpa3NJbVJoZEdFdGIyNWxjMmh2ZENJNkltNWhkaTFwZEdWdElpd2laR0YwWVMxelpXTjBhVzl1SWpw'
    || 'U0xtbGtMRzl1UTJ4cFkyczZLQ2s5UGtVb1VpNXBaQ2tzSW1GeWFXRXRZM1Z5Y21WdWRDSTZVaTVwWkQwOVBXMC9JbkJoWjJVaU9uWnZhV1FnTUN4amFHbHNa'
    || 'SEpsYmpwYmJ5NXFjM2dvUkdNc2UyNWhiV1U2VWk1cFkyOXVQejhpYjNabGNuWnBaWGNpZlNrc2J5NXFjM2h6S0NKemNHRnVJaXg3YzNSNWJHVTZlMjFwYmxk'
    || 'cFpIUm9PakFzWm14bGVEb3hmU3hqYUdsc1pISmxianBiYnk1cWMzZ29Jbk53WVc0aUxIdGpiR0Z6YzA1aGJXVTZJbTVoZGw5ZmJHRmlaV3dpTEdOb2FXeGtj'
    || 'bVZ1T2xJdWJHRmlaV3g5S1N4U0xtUmxjMk0vYnk1cWMzZ29Jbk53WVc0aUxIdGpiR0Z6YzA1aGJXVTZJbTVoZGw5ZlpHVnpZeUlzWTJocGJHUnlaVzQ2VWk1'
    || 'a1pYTmpmU2s2Ym5Wc2JGMTlLU3hTTG1KaFpHZGxQMjh1YW5ONEtDSnpjR0Z1SWl4N1kyeGhjM05PWVcxbE9pSnVZWFpmWDJKaFpHZGxJRzVoZGw5ZlltRmta'
    || 'MlV0TFNJcktGSXVZbUZrWjJWVWIyNWxQejhpYVdSc1pTSXBMR05vYVd4a2NtVnVPbEl1WW1Ga1oyVjlLVHB1ZFd4c0xGSXVjM1JoZEhWelAyOHVhbk40S0NK'
    || 'emNHRnVJaXg3WTJ4aGMzTk9ZVzFsT2lKdVlYWmZYMlJ2ZENCdVlYWmZYMlJ2ZEMwdElpdFNMbk4wWVhSMWMzMHBPbTUxYkd4ZGZTeFNMbWxrS1R0eVpYUjFj'
    || 'bTRnWldVL2J5NXFjM2h6S0hGbExrWnlZV2R0Wlc1MExIdGphR2xzWkhKbGJqcGJieTVxYzNnb0ltZ3lJaXg3WTJ4aGMzTk9ZVzFsT2lKdVlYWmZYMmR5YjNW'
    || 'd0lpeGphR2xzWkhKbGJqcFNMbWR5YjNWd2ZTa3NZbDE5TENKbk9pSXJlaWs2WW4wcGZTa3NWRDl2TG1wemVDZ2laR2wySWl4N1kyeGhjM05PWVcxbE9pSnph'
    || 'V1JsWDE5bWIyOTBJaXhqYUdsc1pISmxianBVZlNrNmJuVnNiRjE5S1gxbWRXNWpkR2x2YmlCNlpTaDdiR0ZpWld3NmRTeDJZV3gxWlRwakxIVnVhWFE2WVN4'
    || 'emRXSTZiU3gwYjI1bE9rVjlLWHR5WlhSMWNtNGdieTVxYzNoektDSmthWFlpTEh0amJHRnpjMDVoYldVNkluTjBZWFFpS3loRlB5SWdjM1JoZEMwdElpdEZP'
    || 'aUlpS1N3aVpHRjBZUzF2Ym1WemFHOTBJam9pYzNSaGRDSXNZMmhwYkdSeVpXNDZXMjh1YW5ONEtDSmthWFlpTEh0amJHRnpjMDVoYldVNkluTjBZWFJmWDJ4'
    || 'aFltVnNJaXhqYUdsc1pISmxianAxZlNrc2J5NXFjM2h6S0NKa2FYWWlMSHRqYkdGemMwNWhiV1U2SW5OMFlYUmZYM1poYkhWbElpeGphR2xzWkhKbGJqcGJZ'
    || 'eXhoUDI4dWFuTjRLQ0p6Y0dGdUlpeDdZMnhoYzNOT1lXMWxPaUp6ZEdGMFgxOTFibWwwSWl4amFHbHNaSEpsYmpwaGZTazZiblZzYkYxOUtTeHRQMjh1YW5O'
    || 'NEtDSmthWFlpTEh0amJHRnpjMDVoYldVNkluTjBZWFJmWDNOMVlpSXNZMmhwYkdSeVpXNDZiWDBwT201MWJHeGRmU2w5Wm5WdVkzUnBiMjRnVEdVb2UzUnBk'
    || 'R3hsT25Vc2FHbHVkRHBqTEdOb2FXeGtjbVZ1T21Fc2QybGtaVHB0ZlNsN2NtVjBkWEp1SUc4dWFuTjRjeWdpYzJWamRHbHZiaUlzZTJOc1lYTnpUbUZ0WlRv'
    || 'aVkyRnlaQ0lyS0cwL0lpQmpZWEprTFMxM2FXUmxJam9pSWlrc0ltUmhkR0V0YjI1bGMyaHZkQ0k2SW1OaGNtUWlMR05vYVd4a2NtVnVPbHR2TG1wemVITW9J'
    || 'bWhsWVdSbGNpSXNlMk5zWVhOelRtRnRaVG9pWTJGeVpGOWZhR1ZoWkNJc1kyaHBiR1J5Wlc0NlcyOHVhbk40S0NKb01pSXNlMk5vYVd4a2NtVnVPblY5S1N4'
    || 'alAyOHVhbk40S0NKd0lpeDdZMnhoYzNOT1lXMWxPaUpqWVhKa1gxOW9hVzUwSWl4amFHbHNaSEpsYmpwamZTazZiblZzYkYxOUtTeGhYWDBwZldaMWJtTjBh'
    || 'Vzl1SUVsbEtIdHdZVzVsYkRwMUxIZG9aVzVOYVhOemFXNW5PbU1zYm05MFFuVnBiSFJDYkc5amF6cGhMR05vYVd4a2NtVnVPbTE5S1h0cFppZ2hkU2x5WlhS'
    || 'MWNtNGdZVDl2TG1wemVDaHZMa1p5WVdkdFpXNTBMSHRqYUdsc1pISmxianBoZlNrNmJ5NXFjM2h6S0NKa2FYWWlMSHRqYkdGemMwNWhiV1U2SW5CaGJtVnNM'
    || 'VzV2ZEdKMWFXeDBJaXdpWkdGMFlTMXZibVZ6YUc5MElqb2ljR0Z1Wld3dGJtOTBZblZwYkhRaUxHTm9hV3hrY21WdU9sdHZMbXB6ZUNnaWMzUnliMjVuSWl4'
    || 'N1kyaHBiR1J5Wlc0NklsUm9hWE1nY25WdUlHUnBaQ0J1YjNRZ1luVnBiR1FnZEdocGN5QndZWEowTGlKOUtTeHZMbXB6ZUNnaWNDSXNlMk5vYVd4a2NtVnVP'
    || 'bU0vUHlKVWFHVWdjMk55YVhCMElISmhiaUJwYmlCcGRITWdaR1ZtWVhWc2RDd2djbVZoWkMxdmJteDVJRzF2WkdVc0lIZG9hV05vSUdsdWMzQmxZM1J6SUhs'
    || 'dmRYSWdZV05qYjNWdWRDQjNhWFJvYjNWMElHTnlaV0YwYVc1bklHRnVlWFJvYVc1bkxpQkdhV3hzSUdsdUlIUm9aU0J6WlhSMGFXNW5jeUJoZENCMGFHVWdk'
    || 'Rzl3SUc5bUlIUm9aU0J6WTNKcGNIUWdZVzVrSUhKMWJpQnBkQ0JoWjJGcGJpQjBieUJpZFdsc1pDQjBhR2x6TGlKOUtWMTlLVHRwWmloc2JpaDFLU2x5WlhS'
    || 'MWNtNGdZVDl2TG1wemVDaHZMa1p5WVdkdFpXNTBMSHRqYUdsc1pISmxianBoZlNrNmJ5NXFjM2h6S0NKa2FYWWlMSHRqYkdGemMwNWhiV1U2SW5CaGJtVnNM'
    || 'VzV2ZEdKMWFXeDBJaXdpWkdGMFlTMXZibVZ6YUc5MElqb2ljR0Z1Wld3dGJtOTBZblZwYkhRaUxHTm9hV3hrY21WdU9sdHZMbXB6ZUNnaWMzUnliMjVuSWl4'
    || 'N1kyaHBiR1J5Wlc0NklsUm9hWE1nY0dGeWRDQm9ZWE1nYm05MElHSmxaVzRnWW5WcGJIUWdlV1YwTGlKOUtTeHZMbXB6ZUNnaWNDSXNlMk5vYVd4a2NtVnVP'
    || 'bU0vUHlKVWFHbHpJSEoxYmlCa2FXUWdibTkwSUdOeVpXRjBaU0IwYUdVZ2IySnFaV04wY3lCMGFHbHpJR05oY21RZ2NtVmhaSE11SUVacGJHd2dhVzRnZEdo'
    || 'bElITmxkSFJwYm1keklHRjBJSFJvWlNCMGIzQWdiMllnZEdobElITmpjbWx3ZENCaGJtUWdjblZ1SUdsMElHRm5ZV2x1TGlKOUtTeHZMbXB6ZUNnaWNDSXNl'
    || 'Mk5zWVhOelRtRnRaVG9pY0dGdVpXd3RibTkwWW5WcGJIUmZYMkZzZENJc1kyaHBiR1J5Wlc0NkowbG1JSGx2ZFNCbGVIQmxZM1JsWkNCcGRDQjBieUJsZUds'
    || 'emRDd2dkR2hsSUhOaGJXVWdVMjV2ZDJac1lXdGxJR1Z5Y205eUlHTnZkbVZ5Y3lBaWJtOTBJR0YxZEdodmNtbDZaV1FpSU9LQWxDQjViM1VnYldGNUlHSmxJ'
    || 'RzFwYzNOcGJtY2dZU0JuY21GdWRDQnlZWFJvWlhJZ2RHaGhiaUJoSUdKMWFXeGtMaWQ5S1YxOUtUdHBaaWh5YmloMUtTbHlaWFIxY200Z2J5NXFjM2h6S0NK'
    || 'a2FYWWlMSHRqYkdGemMwNWhiV1U2SW5CaGJtVnNMV1Z5Y205eUlpd2laR0YwWVMxdmJtVnphRzkwSWpvaWNHRnVaV3d0WlhKeWIzSWlMR05vYVd4a2NtVnVP'
    || 'bHR2TG1wemVDZ2ljM1J5YjI1bklpeDdZMmhwYkdSeVpXNDZJbFJvYVhNZ2NYVmxjbmtnWkdsa0lHNXZkQ0J5ZFc0dUluMHBMRzh1YW5ONEtDSmpiMlJsSWl4'
    || 'N1kyaHBiR1J5Wlc0NmRTNWxjbkp2Y24wcFhYMHBPMmxtS0NGMUxuSnZkM011YkdWdVozUm9LWEpsZEhWeWJpQnZMbXB6ZUNnaWNDSXNlMk5zWVhOelRtRnRa'
    || 'VG9pY0dGdVpXd3RaVzF3ZEhraUxDSmtZWFJoTFc5dVpYTm9iM1FpT2lKd1lXNWxiQzFsYlhCMGVTSXNZMmhwYkdSeVpXNDZJbFJvWlNCeGRXVnllU0J5WVc0'
    || 'Z1lXNWtJSEpsZEhWeWJtVmtJRzV2SUhKdmQzTXVJbjBwTzJOdmJuTjBJRVU5ZFhNb2RTazdjbVYwZFhKdUlHOHVhbk40Y3lodkxrWnlZV2R0Wlc1MExIdGph'
    || 'R2xzWkhKbGJqcGJSVDl2TG1wemVITW9JbkFpTEh0amJHRnpjMDVoYldVNkluQmhibVZzTFhSeWRXNWpJaXdpWkdGMFlTMXZibVZ6YUc5MElqb2ljR0Z1Wld3'
    || 'dGRISjFibU5oZEdWa0lpeGphR2xzWkhKbGJqcGJJbE5vYjNkcGJtY2dkR2hsSUdacGNuTjBJQ0lzVlNoRktTd2lJSEp2ZDNNdUlGUm9hWE1nY1hWbGNua2dj'
    || 'bVYwZFhKdVpXUWdiVzl5WlN3Z2MyOGdZVzU1SUhSdmRHRnNJRzl1SUhSb2FYTWdZMkZ5WkNCcGN5QmhJR1pzYjI5eUxDQnViM1FnWVNCamIzVnVkQzRpWFgw'
    || 'cE9tNTFiR3dzYlYxOUtYMW1kVzVqZEdsdmJpQjZkQ2g3Y205M2N6cDFMR052YkhNNll5eHRZWGc2WVN4dmJsQnBZMnM2YlN4aFkzUnBkbVU2UlgwcGUyTnZi'
    || 'bk4wSUZROVlUOTFMbk5zYVdObEtEQXNZU2s2ZFR0eVpYUjFjbTRnYnk1cWMzaHpLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJblJoWW14bExYZHlZWEFpTEdO'
    || 'b2FXeGtjbVZ1T2x0dkxtcHplSE1vSW5SaFlteGxJaXg3WTJ4aGMzTk9ZVzFsT20wL0luUmhZbXhsTFMxd2FXTnJJam9pSWl4amFHbHNaSEpsYmpwYmJ5NXFj'
    || 'M2dvSW5Sb1pXRmtJaXg3WTJocGJHUnlaVzQ2Ynk1cWMzZ29JblJ5SWl4N1kyaHBiR1J5Wlc0Nll5NXRZWEFvZUQwK2J5NXFjM2dvSW5Sb0lpeDdZMnhoYzNO'
    || 'T1lXMWxPbmd1WVd4cFoyNDlQVDBpY21sbmFIUWlQeUp5SWpvaUlpeGphR2xzWkhKbGJqcDRMbXhoWW1Wc1B6OTRMbXRsZVgwc2VDNXJaWGtwS1gwcGZTa3Ni'
    || 'eTVxYzNnb0luUmliMlI1SWl4N1kyaHBiR1J5Wlc0NlZDNXRZWEFvS0hnc2FpazlQbTh1YW5ONEtDSjBjaUlzZTJOc1lYTnpUbUZ0WlRwdEppWnFQVDA5UlQ4'
    || 'aWRISXRMVzl1SWpvaUlpeHZia05zYVdOck9tMC9LQ2s5UG0wb2VDeHFLVHAyYjJsa0lEQXNkR0ZpU1c1a1pYZzZiVDh3T25admFXUWdNQ3dpWVhKcFlTMXpa'
    || 'V3hsWTNSbFpDSTZiVDlxUFQwOVJUcDJiMmxrSURBc2IyNUxaWGxFYjNkdU9tMC9LRk05UG5zb1V5NXJaWGs5UFQwaVJXNTBaWElpZkh4VExtdGxlVDA5UFNJ'
    || 'Z0lpa21KaWhUTG5CeVpYWmxiblJFWldaaGRXeDBLQ2tzYlNoNExHb3BLWDBwT25admFXUWdNQ3hqYUdsc1pISmxianBqTG0xaGNDaFRQVDV2TG1wemVDZ2lk'
    || 'R1FpTEh0amJHRnpjMDVoYldVNlV5NWhiR2xuYmowOVBTSnlhV2RvZENJL0luSWlPaUlpTEdOb2FXeGtjbVZ1T2xNdWNtVnVaR1Z5UDFNdWNtVnVaR1Z5S0ho'
    || 'YlV5NXJaWGxkTEhncE9sQmpLSGhiVXk1clpYbGRLWDBzVXk1clpYa3BLWDBzYWlrcGZTbGRmU2tzWVNZbWRTNXNaVzVuZEdnK1lUOXZMbXB6ZUhNb0luQWlM'
    || 'SHRqYkdGemMwNWhiV1U2SW5SaFlteGxMVzF2Y21VaUxHTm9hV3hrY21WdU9sdFZLSFV1YkdWdVozUm9MV0VwTENJZ2JXOXlaU0J5YjNjb2N5a2dibTkwSUhO'
    || 'b2IzZHVJbDE5S1RwdWRXeHNYWDBwZldaMWJtTjBhVzl1SUZCaktIVXBlMmxtS0hVOVBXNTFiR3dwY21WMGRYSnVJRzh1YW5ONEtDSnpjR0Z1SWl4N1kyeGhj'
    || 'M05PWVcxbE9pSnVkV3hzSWl4amFHbHNaSEpsYmpvaVRsVk1UQ0o5S1R0amIyNXpkQ0JqUFUxMEtIVXBPM0psZEhWeWJpQmpJVDA5Ym5Wc2JEOVZLR01wT2xO'
    || 'MGNtbHVaeWgxS1gxbWRXNWpkR2x2YmlCRmRDaDdZMmhwYkdSeVpXNDZkU3gwYjI1bE9tTjlLWHR5WlhSMWNtNGdieTVxYzNnb0luTndZVzRpTEh0amJHRnpj'
    || 'MDVoYldVNkluQnBiR3dpS3loalB5SWdjR2xzYkMwdElpdGpPaUlpS1N4amFHbHNaSEpsYmpwMWZTbDlablZ1WTNScGIyNGdUSElvZTNScGRHeGxPblVzWTJo'
    || 'cGJHUnlaVzQ2WTMwcGUzSmxkSFZ5YmlCdkxtcHplSE1vSW1ScGRpSXNlMk5zWVhOelRtRnRaVG9pWTJGMlpXRjBJaXdpWkdGMFlTMXZibVZ6YUc5MElqb2lZ'
    || 'MkYyWldGMElpeGphR2xzWkhKbGJqcGJieTVxYzNnb0luTjBjbTl1WnlJc2UyTm9hV3hrY21WdU9uVjlLU3h2TG1wemVDZ2ljQ0lzZTJOb2FXeGtjbVZ1T21O'
    || 'OUtWMTlLWDFtZFc1amRHbHZiaUJGYmloN1kyaHBiR1J5Wlc0NmRYMHBlM0psZEhWeWJpQnZMbXB6ZUNnaVpHbDJJaXg3WTJ4aGMzTk9ZVzFsT2lKdFpYUm9i'
    || 'MlFpTENKa1lYUmhMVzl1WlhOb2IzUWlPaUp0WlhSb2IyUWlMR05vYVd4a2NtVnVPblY5S1gxbWRXNWpkR2x2YmlCTVl5aDdkbUZzZFdVNmRTeHVZVHBqTEc1'
    || 'dmJtVTZZU3gwYVhSc1pUcHRmU2w3Y21WMGRYSnVJR00vYnk1cWMzZ29Jbk53WVc0aUxIdGpiR0Z6YzA1aGJXVTZJbU5sYkd3dExXNWhJaXgwYVhSc1pUcHRQ'
    || 'ejhpYm05MElHRndjR3hwWTJGaWJHVTdJR1Y0WTJ4MVpHVmtJR1p5YjIwZ2RHaGxJSE5qYjNKbElpeGphR2xzWkhKbGJqb2lUaTlCSW4wcE9tRjhmSFU5UFQx'
    || 'dWRXeHNmSHgxUFQwOWRtOXBaQ0F3Zkh4MVBUMDlJaUkvYnk1cWMzZ29Jbk53WVc0aUxIdGpiR0Z6YzA1aGJXVTZJbU5sYkd3dExXNXZibVVpTEhScGRHeGxP'
    || 'bTAvUHlKdWIyNWxJSEJ5WlhObGJuUWlMR05vYVd4a2NtVnVPaUxpZ0pRaWZTazZieTVxYzNnb2J5NUdjbUZuYldWdWRDeDdZMmhwYkdSeVpXNDZkSGx3Wlc5'
    || 'bUlIVTlQU0p1ZFcxaVpYSWlQM1V1ZEc5TWIyTmhiR1ZUZEhKcGJtY29JbVZ1TFZWVElpazZkWDBwZldaMWJtTjBhVzl1SUVsaktIdHdZVzVsYkRwMUxIZG9Z'
    || 'WFE2WTMwcGUybG1LR3h1S0hVcEtYSmxkSFZ5YmlCdkxtcHplSE1vSW5BaUxIdGpiR0Z6YzA1aGJXVTZJbTV2ZEhsbGRDQndZVzVsYkMxdWIzUmlkV2xzZENC'
    || 'd1lXNWxiQzF1YjNSaWRXbHNkQzB0WVhWNElpd2laR0YwWVMxdmJtVnphRzkwSWpvaWNHRnVaV3d0Ym05MFluVnBiSFFpTEdOb2FXeGtjbVZ1T2x0akxDSTZJ'
    || 'SFJvWlNCemIzVnlZMlVnWm05eUlIUm9hWE1nZDJGeklHNXZkQ0JtYjNWdVpDd2diM0lnZEdocGN5QnliMnhsSUdOaGJtNXZkQ0J6WldVZ2FYUWc0b0NVSUZO'
    || 'dWIzZG1iR0ZyWlNCa2IyVnpJRzV2ZENCa2FYTjBhVzVuZFdsemFDQjBhR1VnZEhkdkxpQlVhR1VnWjJWdVpYSnBZeUIzYjNKa2FXNW5JR0ZpYjNabElHbHpJ'
    || 'SFJvWlNCbVlXeHNZbUZqYXpzZ2JtOTBhR2x1WnlCbGJITmxJRzl1SUhSb2FYTWdZMkZ5WkNCcGN5QmhabVpsWTNSbFpDNGlYWDBwTzJsbUtISnVLSFVwS1hK'
    || 'bGRIVnliaUJ2TG1wemVITW9JbVJwZGlJc2UyTnNZWE56VG1GdFpUb2ljR0Z1Wld3dFpYSnliM0lnY0dGdVpXd3RaWEp5YjNJdExXRjFlQ0lzSW1SaGRHRXRi'
    || 'MjVsYzJodmRDSTZJbkJoYm1Wc0xXVnljbTl5SWl4amFHbHNaSEpsYmpwYmJ5NXFjM2h6S0NKemRISnZibWNpTEh0amFHbHNaSEpsYmpwYll5d2lJR052ZFd4'
    || 'a0lHNXZkQ0JpWlNCeVpXRmtMaUpkZlNrc2J5NXFjM2dvSW5BaUxIdGphR2xzWkhKbGJqb2lSWFpsY25sMGFHbHVaeUJsYkhObElHOXVJSFJvYVhNZ1kyRnla'
    || 'Q0JwY3lCMWJtRm1abVZqZEdWa0lPS0FsQ0IwYUdseklIRjFaWEo1SUc5dWJIa2djM1Z3Y0d4cFpXUWdiR0ZpWld4c2FXNW5MQ0JoYm1RZ2RHaGxJR2RsYm1W'
    || 'eWFXTWdkMjl5WkdsdVp5QmhZbTkyWlNCcGN5QjBhR1VnWm1Gc2JHSmhZMnNzSUc1dmRDQmhJR05vYjJsalpTNGlmU2tzYnk1cWMzZ29JbU52WkdVaUxIdGph'
    || 'R2xzWkhKbGJqcDFMbVZ5Y205eWZTbGRmU2s3WTI5dWMzUWdZVDExY3loMUtUdHlaWFIxY200Z1lUOXZMbXB6ZUhNb0luQWlMSHRqYkdGemMwNWhiV1U2SW5C'
    || 'aGJtVnNMWFJ5ZFc1aklIQmhibVZzTFhSeWRXNWpMUzFoZFhnaUxDSmtZWFJoTFc5dVpYTm9iM1FpT2lKd1lXNWxiQzEwY25WdVkyRjBaV1FpTEdOb2FXeGtj'
    || 'bVZ1T2x0akxDSTZJSFJvYVhNZ2NYVmxjbmtnZDJGeklHTjFkQ0J2Wm1ZZ1lYUWdJaXhWS0dFcExDSWdjbTkzY3l3Z2MyOGdkR2hsSUd4aFltVnNiR2x1WnlC'
    || 'aFltOTJaU0J0WVhrZ1ltVWdhVzVqYjIxd2JHVjBaU0JsZG1WdUlIUm9iM1ZuYUNCMGFHVWdiV1ZoYzNWeVpXMWxiblJ6SUc5dUlIUm9hWE1nWTJGeVpDQmhj'
    || 'bVVnYm05MExpSmRmU2s2Ym5Wc2JIMWpiMjV6ZENCbGFUMWJJbE5CVFZCTVJTSXNJa3hKVFVsVVJVUWlMQ0pRVWs5RVZVTlVTVTlPSWwwc1pITTllMU5CVFZC'
    || 'TVJUb2lVMlZsWkdWa0lHUmhkR0VnNG9DVUlITmhabVVnZEc4Z2NuVnVJSEpsY0dWaGRHVmtiSGtzSUhCeWIzWmxjeUIwYUdVZ2MyaGhjR1VnZDJsMGFHOTFk'
    || 'Q0IwYjNWamFHbHVaeUJoYm5sMGFHbHVaeUJ5WldGc0xpSXNURWxOU1ZSRlJEb2lXVzkxY2lCa1lYUmhMQ0JrWld4cFltVnlZWFJsYkhrZ1ltOTFibVJsWkNE'
    || 'aWdKUWdZU0J6ZFdKelpYUXNJR0VnWTJGd0xDQnZjaUJoSUhOcGJtZHNaU0J2WW1wbFkzUXVJaXhRVWs5RVZVTlVTVTlPT2lKWmIzVnlJR1JoZEdFc0lHRjBJ'
    || 'R1oxYkd3Z2MyTnZjR1V1SUZKbFlXUWdkR2hsSUhWdVpHOGdiR2x1WlNCaVpXWnZjbVVnZVc5MUlISjFiaUJwZEM0aWZUdG1kVzVqZEdsdmJpQkJZeWg3WVdO'
    || 'MGFXOXVjenAxZlNsN1kyOXVjM1JiWXl4aFhUMXhaUzUxYzJWVGRHRjBaU2doTVNrc2JUMTdmVHRtYjNJb1kyOXVjM1FnZUNCdlppQjFLWHRqYjI1emRDQnFQ'
    || 'Vk4wY21sdVp5aDRMbFJKUlZJL1B5SlFVazlFVlVOVVNVOU9JaWt1ZEc5VmNIQmxja05oYzJVb0tUc29iVnRxWFQ4L0tHMWJhbDA5VzEwcEtTNXdkWE5vS0hn'
    || 'cGZXTnZibk4wSUVVOWRTNXNaVzVuZEdnc1ZEMWxhUzVtYVd4MFpYSW9lRDArZTNaaGNpQnFPM0psZEhWeWJpaHFQVzFiZUYwcFBUMXVkV3hzUDNadmFXUWdN'
    || 'RHBxTG14bGJtZDBhSDBwTG0xaGNDaDRQVDRvZTNScFpYSTZlQ3hqYjNWdWREcHRXM2hkTG14bGJtZDBhSDBwS1R0eVpYUjFjbTRnYnk1cWMzaHpLRzh1Um5K'
    || 'aFoyMWxiblFzZTJOb2FXeGtjbVZ1T2x0dkxtcHplSE1vSW1KMWRIUnZiaUlzZTNSNWNHVTZJbUoxZEhSdmJpSXNZMnhoYzNOT1lXMWxPaUpoWTNRdGMzVnRi'
    || 'V0Z5ZVNJc2IyNURiR2xqYXpvb0tUMCtZU2g0UFQ0aGVDa3NJbUZ5YVdFdFpYaHdZVzVrWldRaU9tTXNZMmhwYkdSeVpXNDZXMjh1YW5ONGN5Z2ljM0JoYmlJ'
    || 'c2UyTnNZWE56VG1GdFpUb2lZV04wTFhOMWJXMWhjbmxmWDJOdmRXNTBJaXhqYUdsc1pISmxianBiVlNoRktTd2lJR0ZqZEdsdmJpSXNSVDA5UFRFL0lpSTZJ'
    || 'bk1pWFgwcExGUXViV0Z3S0NoN2RHbGxjanA0TEdOdmRXNTBPbXA5S1QwK2J5NXFjM2h6S0NKemNHRnVJaXg3WTJ4aGMzTk9ZVzFsT2lKaFkzUXRjM1Z0YldG'
    || 'eWVWOWZkR2xsY2lJc1kyaHBiR1J5Wlc0NlczZ3NJaUFpTEdwZGZTeDRLU2tzYnk1cWMzZ29Jbk4yWnlJc2UyTnNZWE56VG1GdFpUb2lZV04wTFhOMWJXMWhj'
    || 'bmxmWDJOb1pYWnliMjRpS3loalB5SWdZV04wTFhOMWJXMWhjbmxmWDJOb1pYWnliMjR0TFc5d1pXNGlPaUlpS1N4M2FXUjBhRG9pTVRRaUxHaGxhV2RvZERv'
    || 'aU1UUWlMSFpwWlhkQ2IzZzZJakFnTUNBeE5pQXhOaUlzWm1sc2JEb2libTl1WlNJc0ltRnlhV0V0YUdsa1pHVnVJam9pZEhKMVpTSXNZMmhwYkdSeVpXNDZi'
    || 'eTVxYzNnb0luQmhkR2dpTEh0a09pSk5OQ0EyYkRRZ05DQTBMVFFpTEhOMGNtOXJaVG9pWTNWeWNtVnVkRU52Ykc5eUlpeHpkSEp2YTJWWGFXUjBhRG9pTVM0'
    || 'MUlpeHpkSEp2YTJWTWFXNWxZMkZ3T2lKeWIzVnVaQ0lzYzNSeWIydGxUR2x1WldwdmFXNDZJbkp2ZFc1a0luMHBmU2xkZlNrc1l6OXZMbXB6ZUhNb2J5NUdj'
    || 'bUZuYldWdWRDeDdZMmhwYkdSeVpXNDZXMlZwTG0xaGNDaDRQVDU3WTI5dWMzUWdhajF0VzNoZE8zSmxkSFZ5YmlGcWZId2hhaTVzWlc1bmRHZy9iblZzYkRw'
    || 'dkxtcHplSE1vY1dVdVJuSmhaMjFsYm5Rc2UyTm9hV3hrY21WdU9sdHZMbXB6ZUNnaWNDSXNlMk5zWVhOelRtRnRaVG9pWVdOMFgxOTBhV1Z5SWl4amFHbHNa'
    || 'SEpsYmpwNGZTa3NieTVxYzNnb0luQWlMSHRqYkdGemMwNWhiV1U2SW1GamRGOWZkR2xsY2kxa1pYTmpJaXhqYUdsc1pISmxianBrYzF0NFhUOC9JaUo5S1N4'
    || 'dkxtcHplQ2dpWkdsMklpeDdZMnhoYzNOT1lXMWxPaUpoWTNSZlgyZHlhV1FpTEdOb2FXeGtjbVZ1T21vdWJXRndLRk05UG04dWFuTjRjeWdpWkdsMklpeDdZ'
    || 'MnhoYzNOT1lXMWxPaUpoWTNSZlgyTmhjbVFpTEdOb2FXeGtjbVZ1T2x0dkxtcHplQ2dpWkdsMklpeDdZMnhoYzNOT1lXMWxPaUpoWTNSZlgyTnZaR1VpTEdO'
    || 'b2FXeGtjbVZ1T2xOMGNtbHVaeWhUTGtOUFJFVXBmU2tzYnk1cWMzZ29JbVJwZGlJc2UyTnNZWE56VG1GdFpUb2lZV04wWDE5c1lXSmxiQ0lzWTJocGJHUnla'
    || 'VzQ2VTNSeWFXNW5LRk11VEVGQ1JVdy9QMU11UTA5RVJTbDlLU3h2TG1wemVDZ2laR2wySWl4N1kyeGhjM05PWVcxbE9pSmhZM1JmWDJWbVptVmpkQ0lzWTJo'
    || 'cGJHUnlaVzQ2VTNSeWFXNW5LRk11UlVaR1JVTlVQejhpNG9DVUlpbDlLU3h2TG1wemVITW9JbVJwZGlJc2UyTnNZWE56VG1GdFpUb2lZV04wWDE5dFpYUmhJ'
    || 'aXhqYUdsc1pISmxianBiYnk1cWMzaHpLQ0p6Y0dGdUlpeDdZMmhwYkdSeVpXNDZXeUorSWl4Vll5aFRMa1ZUVkY5RFVrVkVTVlJUS1N3aUlHTnlaV1JwZEhN'
    || 'aVhYMHBMRzh1YW5ONGN5Z2ljM0JoYmlJc2UyTm9hV3hrY21WdU9sdFZLRk11VTFSQlZFVk5SVTVVVXlrc0lpQnpkRzEwSWl4MGFTaFRMbE5VUVZSRlRVVk9W'
    || 'Rk1wUFQwOU1UOGlJam9pY3lKZGZTa3NVeTVWVGtSUFgxTlVRVlJGVFVWT1ZGTS9ieTVxYzNnb0luTndZVzRpTEh0amJHRnpjMDVoYldVNkltRmpkRjlmZFc1'
    || 'a2J5SXNZMmhwYkdSeVpXNDZJblZ1Wkc4Z1lYWmhhV3hoWW14bEluMHBPbTh1YW5ONEtDSnpjR0Z1SWl4N1kyeGhjM05PWVcxbE9pSmhZM1JmWDI1dmRXNWti'
    || 'eUlzWTJocGJHUnlaVzQ2SW01dklHRjFkRzh0ZFc1a2J5SjlLVjE5S1N4MGFTaFRMbFJKVFVWVFgxSlZUaWsrTUQ5dkxtcHplSE1vSW1ScGRpSXNlMk5zWVhO'
    || 'elRtRnRaVG9pWVdOMFgxOXlkVzV6SWl4amFHbHNaSEpsYmpwYklsSjFiaUFpTEZVb1V5NVVTVTFGVTE5U1ZVNHBMQ0o0SWl4MGFTaFRMbFJKVFVWVFgxVk9S'
    || 'RTlPUlNrK01EOWdMQ0IxYm1SdmJtVWdKSHRWS0ZNdVZFbE5SVk5mVlU1RVQwNUZLWDE0WURvaUlsMTlLVHB1ZFd4c1hYMHNVM1J5YVc1bktGTXVRMDlFUlNr'
    || 'cEtYMHBYWDBzZUNsOUtTeHZMbXB6ZUNnaWNDSXNlMk5zWVhOelRtRnRaVG9pWVdOMFgxOW1iMjkwSWl4amFHbHNaSEpsYmpvaVZHaGxJR052Ym5SeWIyeHpJ'
    || 'R1p2Y2lCMGFHVnpaU0JoWTNScGIyNXpJR0Z5WlNCaVpXeHZkeUIwYUdVZ1pHRnphR0p2WVhKa0lPS0FsQ0J6WTNKdmJHd2djR0Z6ZENCMGFHVWdZMmhoY25S'
    || 'eklIUnZJR1pwYm1RZ2RHaGxJR0oxZEhSdmJuTWdZVzVrSUdOdmJtWnBjbTFoZEdsdmJpQnpkR1Z3TGlKOUtWMTlLVHB1ZFd4c1hYMHBmV1oxYm1OMGFXOXVJ'
    || 'RTFqS0h0elpYUjBhVzVuT25WOUtYdHlaWFIxY200Z2J5NXFjM2h6S0NKa2FYWWlMSHRqYkdGemMwNWhiV1U2SW01dmRIbGxkQ0J3WVc1bGJDMXViM1JpZFds'
    || 'c2RDSXNJbVJoZEdFdGIyNWxjMmh2ZENJNkluQmhibVZzTFc1dmRHSjFhV3gwSWl4amFHbHNaSEpsYmpwYmJ5NXFjM2dvSW5OMGNtOXVaeUlzZTJOb2FXeGtj'
    || 'bVZ1T2lKT2J5QmhZM1JwYjI1eklIZGxjbVVnY21WbmFYTjBaWEpsWkNCaWVTQjBhR2x6SUhKMWJpNGlmU2tzYnk1cWMzaHpLQ0p3SWl4N1kyeGhjM05PWVcx'
    || 'bE9pSnViM1I1WlhSZlgzZG9lU0lzWTJocGJHUnlaVzQ2V3lKVWFHbHpJSE5qY21sd2RDQjNZWE1nY25WdUlIZHBkR2dnSWl4dkxtcHplSE1vSW1OdlpHVWlM'
    || 'SHRqYUdsc1pISmxianBiZFN3aUlEMGdSa0ZNVTBVaVhYMHBMQ0lzSUhkb2FXTm9JR2x6SUhSb1pTQmtaV1poZFd4ME9pQnBkQ0JwYm5Od1pXTjBjeUIwYUdV'
    || 'Z1lXTmpiM1Z1ZENCaGJtUWdZblZwYkdSeklIWnBaWGR6TENCaGJtUWdjbVZuYVhOMFpYSnpJRzV2ZEdocGJtY2dkR2hoZENCamIzVnNaQ0JqYUdGdVoyVWdZ'
    || 'VzU1ZEdocGJtY3VJRk5sZENBaUxHOHVhbk40Y3lnaVkyOWtaU0lzZTJOb2FXeGtjbVZ1T2x0MUxDSWdQU0JVVWxWRklsMTlLU3dpSUdGdVpDQnlkVzRnYVhR'
    || 'Z1lXZGhhVzRnZEc4Z1ptbHNiQ0IwYUdseklIQmhaMlVnYVc0dUlsMTlLU3h2TG1wemVDZ2ljQ0lzZTJOc1lYTnpUbUZ0WlRvaWJtOTBlV1YwWDE5M2FHRjBJ'
    || 'aXhqYUdsc1pISmxiam9pVDI1alpTQnBkQ0JwY3lCbWFXeHNaV1FnYVc0c0lHVjJaWEo1SUdGamRHbHZiaUJoY0hCbFlYSnpJR2hsY21VZ2RXNWtaWElnYjI1'
    || 'bElHOW1JSFJvY21WbElIUnBaWEp6T2lKOUtTeHZMbXB6ZUNnaWIyd2lMSHRqYkdGemMwNWhiV1U2SW01dmRIbGxkRjlmZEdsbGNuTWlMR05vYVd4a2NtVnVP'
    || 'bVZwTG0xaGNDaGpQVDV2TG1wemVITW9JbXhwSWl4N1kyaHBiR1J5Wlc0NlcyOHVhbk40S0NKemNHRnVJaXg3WTJ4aGMzTk9ZVzFsT2lKdWIzUjVaWFJmWDNS'
    || 'cFpYSWlMR05vYVd4a2NtVnVPbU45S1N4dkxtcHplQ2dpYzNCaGJpSXNlMk5zWVhOelRtRnRaVG9pYm05MGVXVjBYMTkwYVdWeUxXUmxjMk1pTEdOb2FXeGtj'
    || 'bVZ1T21SelcyTmRmU2xkZlN4aktTbDlLU3h2TG1wemVDZ2ljQ0lzZTJOc1lYTnpUbUZ0WlRvaWJtOTBlV1YwWDE5bWIyOTBJaXhqYUdsc1pISmxiam9pUldG'
    || 'amFDQnZibVVnYzNSaGRHVnpJR2wwY3lCbGMzUnBiV0YwWldRZ1kzSmxaR2wwY3l3Z2FHOTNJRzFoYm5rZ2MzUmhkR1Z0Wlc1MGN5QnBkQ0J5ZFc1ekxDQmhi'
    || 'bVFnZDJobGRHaGxjaUJwZENCallXNGdZbVVnZFc1a2IyNWxJT0tBbENCaVpXWnZjbVVnWVc1NVltOWtlU0J3Y21WemMyVnpJR0Z1ZVhSb2FXNW5MaUo5S1Yx'
    || 'OUtYMW1kVzVqZEdsdmJpQjZZeWg3Ykc5bk9uVjlLWHRqYjI1emRGdGpMR0ZkUFhGbExuVnpaVk4wWVhSbEtDRXhLU3h0UFhVdWJHVnVaM1JvTEVVOWRTNW1h'
    || 'V3gwWlhJb2VEMCtlMk52Ym5OMElHbzlVM1J5YVc1bktIZ3VVMVJCVkZWVFB6OGlJaWt1ZEc5VmNIQmxja05oYzJVb0tUdHlaWFIxY200Z2FqMDlQU0pFVDA1'
    || 'RklueDhhajA5UFNKVlRrUlBUa1VpZlNrdWJHVnVaM1JvTEZROWRTNW1hV3gwWlhJb2VEMCtVM1J5YVc1bktIZ3VVMVJCVkZWVFB6OGlJaWt1ZEc5VmNIQmxj'
    || 'a05oYzJVb0tUMDlQU0pHUVVsTVJVUWlLUzVzWlc1bmRHZzdjbVYwZFhKdUlHOHVhbk40Y3lodkxrWnlZV2R0Wlc1MExIdGphR2xzWkhKbGJqcGJieTVxYzNo'
    || 'ektDSmlkWFIwYjI0aUxIdDBlWEJsT2lKaWRYUjBiMjRpTEdOc1lYTnpUbUZ0WlRvaVlXTjBMWE4xYlcxaGNua2lMRzl1UTJ4cFkyczZLQ2s5UG1Fb2VEMCtJ'
    || 'WGdwTENKaGNtbGhMV1Y0Y0dGdVpHVmtJanBqTEdOb2FXeGtjbVZ1T2x0dkxtcHplSE1vSW5Od1lXNGlMSHRqYkdGemMwNWhiV1U2SW1GamRDMXpkVzF0WVhK'
    || 'NVgxOWpiM1Z1ZENJc1kyaHBiR1J5Wlc0NlcxVW9iU2tzSWlCemRHVndJaXh0UFQwOU1UOGlJam9pY3lKZGZTa3NieTVxYzNoektDSnpjR0Z1SWl4N1kyaHBi'
    || 'R1J5Wlc0NlcwVXNJaUJqYjIxd2JHVjBaV1FpTEZRK01EOWdMQ0FrZTFSOUlHWmhhV3hsWkdBNklpSmRmU2tzYnk1cWMzZ29Jbk4yWnlJc2UyTnNZWE56VG1G'
    || 'dFpUb2lZV04wTFhOMWJXMWhjbmxmWDJOb1pYWnliMjRpS3loalB5SWdZV04wTFhOMWJXMWhjbmxmWDJOb1pYWnliMjR0TFc5d1pXNGlPaUlpS1N4M2FXUjBh'
    || 'RG9pTVRRaUxHaGxhV2RvZERvaU1UUWlMSFpwWlhkQ2IzZzZJakFnTUNBeE5pQXhOaUlzWm1sc2JEb2libTl1WlNJc0ltRnlhV0V0YUdsa1pHVnVJam9pZEhK'
    || 'MVpTSXNZMmhwYkdSeVpXNDZieTVxYzNnb0luQmhkR2dpTEh0a09pSk5OQ0EyYkRRZ05DQTBMVFFpTEhOMGNtOXJaVG9pWTNWeWNtVnVkRU52Ykc5eUlpeHpk'
    || 'SEp2YTJWWGFXUjBhRG9pTVM0MUlpeHpkSEp2YTJWTWFXNWxZMkZ3T2lKeWIzVnVaQ0lzYzNSeWIydGxUR2x1WldwdmFXNDZJbkp2ZFc1a0luMHBmU2xkZlNr'
    || 'c1l6OXZMbXB6ZUNoNmRDeDdjbTkzY3pwMUxHTnZiSE02VzN0clpYazZJa05QUkVVaUxHeGhZbVZzT2lKQlkzUnBiMjRpZlN4N2EyVjVPaUpUVkVGVVZWTWlM'
    || 'R3hoWW1Wc09pSlRkR0YwZFhNaUxISmxibVJsY2pwNFBUNTdZMjl1YzNRZ2FqMVRkSEpwYm1jb2VEOC9JaUlwTEZNOWFqMDlQU0pFVDA1RklueDhhajA5UFNK'
    || 'VlRrUlBUa1VpUHlKbmIyOWtJanBxUFQwOUlrWkJTVXhGUkNJL0ltSmhaQ0k2SW5kaGNtNGlPM0psZEhWeWJpQnZMbXB6ZUNoRmRDeDdkRzl1WlRwVExHTm9h'
    || 'V3hrY21WdU9tcDhmQ0xpZ0pRaWZTbDlmU3g3YTJWNU9pSlRWRUZVUlUxRlRsUlRYMUpWVGlJc2JHRmlaV3c2SWxOMGJYUnpJaXhoYkdsbmJqb2ljbWxuYUhR'
    || 'aWZTeDdhMlY1T2lKVFZFRlNWRVZFWDBGVUlpeHNZV0psYkRvaVUzUmhjblJsWkNJc2NtVnVaR1Z5T25nOVBuZy9VM1J5YVc1bktIZ3BMbk5zYVdObEtEQXNN'
    || 'VGtwTG5KbGNHeGhZMlVvSWxRaUxDSWdJaWs2SXVLQWxDSjlMSHRyWlhrNklrWkpUa2xUU0VWRVgwRlVJaXhzWVdKbGJEb2lSbWx1YVhOb1pXUWlMSEpsYm1S'
    || 'bGNqcDRQVDU0UDFOMGNtbHVaeWg0S1M1emJHbGpaU2d3TERFNUtTNXlaWEJzWVdObEtDSlVJaXdpSUNJcE9pTGlnSlFpZlN4N2EyVjVPaUpGVWxKUFVpSXNi'
    || 'R0ZpWld3NklrVnljbTl5SWl4eVpXNWtaWEk2ZUQwK2VEOXZMbXB6ZUNnaWMzQmhiaUlzZTNScGRHeGxPbE4wY21sdVp5aDRLU3hqYUdsc1pISmxianBUZEhK'
    || 'cGJtY29lQ2t1YzJ4cFkyVW9NQ3cyTUNsOUtUb2k0b0NVSW4xZGZTazZiblZzYkYxOUtYMW1kVzVqZEdsdmJpQlZZeWgxS1h0cFppaDFQVDF1ZFd4c0tYSmxk'
    || 'SFZ5YmlMaWdKUWlPM1J5ZVh0eVpYUjFjbTRnVG5WdFltVnlLSFVwTG5SdlJtbDRaV1FvTXlrdWNtVndiR0ZqWlNndk1Dc2tMeXdpSWlrdWNtVndiR0ZqWlNn'
    || 'dlhDNGtMeXdpSWlsOGZDSXdJbjFqWVhSamFIdHlaWFIxY200Z1UzUnlhVzVuS0hVcGZYMW1kVzVqZEdsdmJpQjBhU2gxS1h0eVpYUjFjbTRnZEhsd1pXOW1J'
    || 'SFU5UFNKdWRXMWlaWElpUDNVNlRuVnRZbVZ5S0hVcGZId3dmV052Ym5OMElFWmpQWHROUlZRNkl1S2NreUlzVGs5VVgwMUZWRG9pNHB5WElpeFFSVTVFU1U1'
    || 'SE9pTGlnSlFpTENKT0wwRWlPaUxpbDRzaWZTeG1jejE3VFVWVU9pSk5SVlFpTEU1UFZGOU5SVlE2SWs1UFZDQk5SVlFpTEZCRlRrUkpUa2M2SWxCRlRrUkpU'
    || 'a2NpTENKT0wwRWlPaUpPTDBFaWZTeHVhVDE3VFVWVU9pSnRaWFFpTEU1UFZGOU5SVlE2SW01dmRHMWxkQ0lzVUVWT1JFbE9Sem9pY0dWdVpHbHVaeUlzSWs0'
    || 'dlFTSTZJbTVoSW4wN1puVnVZM1JwYjI0Z1YyTW9lM1k2ZFN4dmJrOXdaVzQ2WTMwcGUyTnZibk4wSUdFOWRTNTJaWEprYVdOMFBUMDlJazVQVkY5TlJWUWlQ'
    || 'eUppWVdRaU9uVXVkbVZ5WkdsamREMDlQU0pOUlZRaVB5Sm5iMjlrSWpwMUxuWmxjbVJwWTNROVBUMGlUVVZVWDFkSlZFaGZVRVZPUkVsT1J5SS9JbmRoY200'
    || 'aU9pSnBaR3hsSWl4dFBYVXVkVzVoZG1GcGJHRmliR1UvSWxCUFF5QnpkV05qWlhOek9pQnViM1FnWW5WcGJIUWlPblV1ZG1WeVpHbGpkRDA5UFNKT1QxUmZV'
    || 'bFZPSWo4aVVFOURJSE4xWTJObGMzTTZJRzV2ZENCelkyOXlaV1FpT21CUVQwTWdjM1ZqWTJWemN6b2dKSHQxTG0xbGRIMGdiMllnSkh0MUxuTmpiM0psWkgw'
    || 'Z1kzSnBkR1Z5YVdFZ2JXVjBZQ3NvZFM1d1pXNWthVzVuUDJBc0lDUjdkUzV3Wlc1a2FXNW5mU0J3Wlc1a2FXNW5ZRG9pSWlrc1JUMXZMbXB6ZUhNb2J5NUdj'
    || 'bUZuYldWdWRDeDdZMmhwYkdSeVpXNDZXMjh1YW5ONEtDSnpjR0Z1SWl4N1kyeGhjM05PWVcxbE9pSndiMk10WTJocGNGOWZiblZ0SWl4amFHbHNaSEpsYmpw'
    || 'MUxuVnVZWFpoYVd4aFlteGxmSHgxTG5abGNtUnBZM1E5UFQwaVRrOVVYMUpWVGlJL0l1S0FsQ0k2WUNSN2RTNXRaWFI5THlSN2RTNXpZMjl5WldSOVlIMHBM'
    || 'Rzh1YW5ONEtDSnpjR0Z1SWl4N1kyeGhjM05PWVcxbE9pSndiMk10WTJocGNGOWZkMjl5WkNJc1kyaHBiR1J5Wlc0NmRTNTFibUYyWVdsc1lXSnNaVDhpYm05'
    || 'MElHSjFhV3gwSWpwMUxuWmxjbVJwWTNROVBUMGlUazlVWDFKVlRpSS9JbTV2ZENCelkyOXlaV1FpT2lKdFpYUWlmU2tzZFM1dWIzUk5aWFEvYnk1cWMzaHpL'
    || 'Q0p6Y0dGdUlpeDdZMnhoYzNOT1lXMWxPaUp3YjJNdFkyaHBjRjlmWm14aFp5SXNZMmhwYkdSeVpXNDZXM1V1Ym05MFRXVjBMQ0lnWm1GcGJHVmtJbDE5S1Rw'
    || 'dWRXeHNMSFV1Y0dWdVpHbHVaeVltSVhVdWJtOTBUV1YwUDI4dWFuTjRjeWdpYzNCaGJpSXNlMk5zWVhOelRtRnRaVG9pY0c5akxXTm9hWEJmWDJac1lXY2lM'
    || 'R05vYVd4a2NtVnVPbHQxTG5CbGJtUnBibWNzSWlCd1pXNWthVzVuSWwxOUtUcHVkV3hzWFgwcE8zSmxkSFZ5YmlCalAyOHVhbk40S0NKaWRYUjBiMjRpTEh0'
    || 'MGVYQmxPaUppZFhSMGIyNGlMQ0prWVhSaExYQnZZeUk2ZFM1MlpYSmthV04wTEdOc1lYTnpUbUZ0WlRvaWNHOWpMV05vYVhBZ2NHOWpMV05vYVhBdExTSXJZ'
    || 'U3h2YmtOc2FXTnJPbU1zSW1GeWFXRXRiR0ZpWld3aU9tMHNkR2wwYkdVNmJTeGphR2xzWkhKbGJqcEZmU2s2Ynk1cWMzZ29Jbk53WVc0aUxIc2laR0YwWVMx'
    || 'd2IyTWlPblV1ZG1WeVpHbGpkQ3hqYkdGemMwNWhiV1U2SW5Cdll5MWphR2x3SUhCdll5MWphR2x3TFMwaUsyRXJJaUJ3YjJNdFkyaHBjQzB0YzNSaGRHbGpJ'
    || 'aXdpWVhKcFlTMXNZV0psYkNJNmJTeDBhWFJzWlRwdExHTm9hV3hrY21WdU9rVjlLWDFtZFc1amRHbHZiaUJ3Y3loN1kzSnBkR1Z5YVdFNmRTeDJPbU1zY0dG'
    || 'dVpXdzZZU3gyWlhKa2FXTjBVR0Z1Wld3NmJYMHBlM1poY2lCVU8yTnZibk4wSUVVOUtDaFVQWFV1Wm1sdVpDaDRQVDU0TG1OdmJYQmhjbUZpYVd4cGRIa3BL'
    || 'VDA5Ym5Wc2JEOTJiMmxrSURBNlZDNWpiMjF3WVhKaFltbHNhWFI1S1Q4L0lpSTdjbVYwZFhKdUlHOHVhbk40Y3lodkxrWnlZV2R0Wlc1MExIdGphR2xzWkhK'
    || 'bGJqcGJieTVxYzNnb1RHVXNlM1JwZEd4bE9pSldaWEprYVdOMElpeDNhV1JsT2lFd0xHaHBiblE2SWtOdmRXNTBaV1FnWm5KdmJTQjBhR1VnWTNKcGRHVnlh'
    || 'V0VnWW1Wc2IzY3VJRTR2UVNCamNtbDBaWEpwWVNCaGNtVWdaWGhqYkhWa1pXUWdabkp2YlNCMGFHVWdaR1Z1YjIxcGJtRjBiM0l1SWl4amFHbHNaSEpsYmpw'
    || 'dkxtcHplQ2hKWlN4N2NHRnVaV3c2YlQ4L1lTeDNhR1Z1VFdsemMybHVaenB2TG1wemVDaHZMa1p5WVdkdFpXNTBMSHRqYUdsc1pISmxiam9pVkdobElIQnNZ'
    || 'VzRnYzNSbGNDQmlkV2xzWkhNZ2RHaGxJSE5qYjNKbFkyRnlaQ0IyYVdWM2N5NGdSbWxzYkNCcGJpQjBhR1VnYzJWMGRHbHVaM01nWVhRZ2RHaGxJSFJ2Y0NC'
    || 'dlppQjBhR1VnYzJOeWFYQjBJR0Z1WkNCeWRXNGdhWFFnWVdkaGFXNGdkRzhnYUdGMlpTQjBhR2x6SUZCUFF5QnpZMjl5WldRdUluMHBMR05vYVd4a2NtVnVP'
    || 'bTh1YW5ONGN5Z2laR2wySWl4N1kyeGhjM05PWVcxbE9pSndiMk5mWDNabGNtUnBZM1FnY0c5algxOTJaWEprYVdOMExTMGlLeWhqTG5abGNtUnBZM1E5UFQw'
    || 'aVRrOVVYMDFGVkNJL0ltSmhaQ0k2WXk1MlpYSmthV04wUFQwOUlrMUZWQ0kvSW1kdmIyUWlPbU11ZG1WeVpHbGpkRDA5UFNKTlJWUmZWMGxVU0Y5UVJVNUVT'
    || 'VTVISWo4aWQyRnliaUk2SW1sa2JHVWlLU3hqYUdsc1pISmxianBiYnk1cWMzZ29JbVJwZGlJc2UyTnNZWE56VG1GdFpUb2ljRzlqWDE5b1pXRmtiR2x1WlNJ'
    || 'c1kyaHBiR1J5Wlc0Nll5NW9aV0ZrYkdsdVpYMHBMRzh1YW5ONEtDSndJaXg3WTJ4aGMzTk9ZVzFsT2lKd2IyTmZYM0psWVdRaUxHTm9hV3hrY21WdU9tTXVj'
    || 'bVZoWkZSb2FYTjlLU3h2TG1wemVDZ2laR2wySWl4N1kyeGhjM05PWVcxbE9pSndiMk5mWDNSaGJHeDVJaXhqYUdsc1pISmxianBiSWsxRlZDSXNJazVQVkY5'
    || 'TlJWUWlMQ0pRUlU1RVNVNUhJaXdpVGk5QklsMHViV0Z3S0hnOVBudGpiMjV6ZENCcVBYZzlQVDBpVFVWVUlqOWpMbTFsZERwNFBUMDlJazVQVkY5TlJWUWlQ'
    || 'Mk11Ym05MFRXVjBPbmc5UFQwaVVFVk9SRWxPUnlJL1l5NXdaVzVrYVc1bk9tTXVibUU3Y21WMGRYSnVJRzh1YW5ONGN5Z2ljM0JoYmlJc2UyTnNZWE56VG1G'
    || 'dFpUb2ljRzlqWDE5MGFXTnJJSEJ2WTE5ZmRHbGpheTB0SWl0dWFWdDRYU3hqYUdsc1pISmxianBiYnk1cWMzZ29JbUlpTEh0amFHbHNaSEpsYmpwcWZTa3NJ'
    || 'aUFpTEdaelczaGRYWDBzZUNsOUtYMHBYWDBwZlNsOUtTeHZMbXB6ZUNoTVpTeDdkR2wwYkdVNklrTnlhWFJsY21saElpeDNhV1JsT2lFd0xHaHBiblE2SWtW'
    || 'aFkyZ2dkR0Z5WjJWMElHbHpJR1JsY21sMlpXUWdabkp2YlNCNWIzVnlJR0ZqWTI5MWJuUXNJR0Z1WkNCbFlXTm9JSEp2ZHlCemFHOTNjeUIwYUdVZ1lYSnBk'
    || 'R2h0WlhScFl5QmlaV2hwYm1RZ2FYUnpJSE4wWVhSbExpSXNZMmhwYkdSeVpXNDZieTVxYzNnb1NXVXNlM0JoYm1Wc09tRXNkMmhsYmsxcGMzTnBibWM2Ynk1'
    || 'cWMzZ29ieTVHY21GbmJXVnVkQ3g3WTJocGJHUnlaVzQ2SWs1dklHTnlhWFJsY21saElHaGhkbVVnWW1WbGJpQnpZMjl5WldRZ1ltVmpZWFZ6WlNCMGFHVWdk'
    || 'bWxsZDNNZ2RHaGxlU0J5WldGa0lIZGxjbVVnYm05MElHSjFhV3gwSUdKNUlIUm9hWE1nY25WdUxpSjlLU3hqYUdsc1pISmxianB2TG1wemVITW9JbVJwZGlJ'
    || 'c2UyTnNZWE56VG1GdFpUb2ljRzlqSWl4amFHbHNaSEpsYmpwYmRTNXRZWEFvZUQwK2J5NXFjM2h6S0NKa2FYWWlMSHRqYkdGemMwNWhiV1U2SW5Cdll5MXli'
    || 'M2NnY0c5akxYSnZkeTB0SWl0dWFWdDRMbk4wWVhSbFhTeGphR2xzWkhKbGJqcGJieTVxYzNnb0ltUnBkaUlzZTJOc1lYTnpUbUZ0WlRvaWNHOWpMWEp2ZDE5'
    || 'ZmJXRnlheUlzSW1GeWFXRXRhR2xrWkdWdUlqb2lkSEoxWlNJc1kyaHBiR1J5Wlc0NlJtTmJlQzV6ZEdGMFpWMTlLU3h2TG1wemVITW9JbVJwZGlJc2UyTnNZ'
    || 'WE56VG1GdFpUb2ljRzlqTFhKdmQxOWZZbTlrZVNJc1kyaHBiR1J5Wlc0NlcyOHVhbk40Y3lnaVpHbDJJaXg3WTJ4aGMzTk9ZVzFsT2lKd2IyTXRjbTkzWDE5'
    || 'MGIzQWlMR05vYVd4a2NtVnVPbHR2TG1wemVDZ2ljM0JoYmlJc2UyTnNZWE56VG1GdFpUb2ljRzlqTFhKdmQxOWZiR0ZpWld3aUxHTm9hV3hrY21WdU9uZ3Vi'
    || 'R0ZpWld4OGZIZ3VZMjlrWlgwcExHOHVhbk40S0NKemNHRnVJaXg3WTJ4aGMzTk9ZVzFsT2lKd2IyTXRjbTkzWDE5emRHRjBaU0J3YjJNdGNtOTNYMTl6ZEdG'
    || 'MFpTMHRJaXR1YVZ0NExuTjBZWFJsWFN4amFHbHNaSEpsYmpwbWMxdDRMbk4wWVhSbFhYMHBYWDBwTEhndWQyaDVQMjh1YW5ONEtDSndJaXg3WTJ4aGMzTk9Z'
    || 'VzFsT2lKd2IyTXRjbTkzWDE5M2FIa2lMR05vYVd4a2NtVnVPbmd1ZDJoNWZTazZiblZzYkN4NExtRnlhWFJvYldWMGFXTS9ieTVxYzNnb0luQWlMSHRqYkdG'
    || 'emMwNWhiV1U2SW5Cdll5MXliM2RmWDIxaGRHZ2lMR05vYVd4a2NtVnVPbTh1YW5ONEtDSmpiMlJsSWl4N1kyaHBiR1J5Wlc0NmVDNWhjbWwwYUcxbGRHbGpm'
    || 'U2w5S1RwdkxtcHplQ2dpY0NJc2UyTnNZWE56VG1GdFpUb2ljRzlqTFhKdmQxOWZiV0YwYUNCd2IyTXRjbTkzWDE5dFlYUm9MUzF1YjI1bElpeGphR2xzWkhK'
    || 'bGJqcHZMbXB6ZUhNb0luTndZVzRpTEh0amFHbHNaSEpsYmpwYkluUmhjbWRsZENBaUxIZ3VkR0Z5WjJWMFBUMDliblZzYkQ4aTRvQ1VJanBWS0hndWRHRnla'
    || 'MlYwS1N4NExuVnVhWFJ6UHlJZ0lpdDRMblZ1YVhSek9pSWlMQ0lnd3JjZ1lXTjBkV0ZzSUc1dmRDQmhkbUZwYkdGaWJHVWlYWDBwZlNrc2VDNTNhSGxPYjNR'
    || 'L2J5NXFjM2dvSW5BaUxIdGpiR0Z6YzA1aGJXVTZJbkJ2WXkxeWIzZGZYM0JsYm1RaUxHTm9hV3hrY21WdU9uZ3VkMmg1VG05MGZTazZiblZzYkN4NExuSmxj'
    || 'MjlzZG1WelYyaGxiajl2TG1wemVITW9JbkFpTEh0amJHRnpjMDVoYldVNkluQnZZeTF5YjNkZlgzZG9aVzRpTEdOb2FXeGtjbVZ1T2xzaVVtVnpiMngyWlhN'
    || 'Z2QyaGxiam9nSWl4NExuSmxjMjlzZG1WelYyaGxibDE5S1RwdWRXeHNMRzh1YW5ONGN5Z2laR3dpTEh0amJHRnpjMDVoYldVNkluQnZZeTF5YjNkZlgyMWxk'
    || 'R0VpTEdOb2FXeGtjbVZ1T2x0dkxtcHplSE1vSW1ScGRpSXNlMk5vYVd4a2NtVnVPbHR2TG1wemVDZ2laSFFpTEh0amFHbHNaSEpsYmpvaVNHOTNJSFJvWlNC'
    || 'MFlYSm5aWFFnZDJGeklITmxkQ0o5S1N4dkxtcHplQ2dpWkdRaUxIdGphR2xzWkhKbGJqcDRMbVJsY21sMllYUnBiMjU4Zkc4dWFuTjRLQ0psYlNJc2UyTm9h'
    || 'V3hrY21WdU9pSk9iM1FnYzNSaGRHVmtJT0tBbENCMGNtVmhkQ0IwYUdseklIUmhjbWRsZENCaGN5QjFibVY0Y0d4aGFXNWxaQzRpZlNsOUtWMTlLU3g0TG1K'
    || 'aGMybHpQMjh1YW5ONGN5Z2laR2wySWl4N1kyaHBiR1J5Wlc0NlcyOHVhbk40S0NKa2RDSXNlMk5vYVd4a2NtVnVPaUpDWVhOcGN5QnZaaUIwYUdVZ1lXTjBk'
    || 'V0ZzSW4wcExHOHVhbk40S0NKa1pDSXNlMk5vYVd4a2NtVnVPbTh1YW5ONEtDSmpiMlJsSWl4N1kyaHBiR1J5Wlc0NmVDNWlZWE5wYzMwcGZTbGRmU2s2Ym5W'
    || 'c2JGMTlLVjE5S1YxOUxIZ3VZMjlrWlNrcExFVS9ieTVxYzNnb0luQWlMSHRqYkdGemMwNWhiV1U2SW5CdlkxOWZibTkwWlNJc1kyaHBiR1J5Wlc0NlJYMHBP'
    || 'bTUxYkd4ZGZTbDlLWDBwWFgwcGZXWjFibU4wYVc5dUlGWmpLSFVzWXlsN1kyOXVjM1FnWVQxMUxtTjFjM1J2YldsNllYUnBiMjQvUDN0OUxHMDlLR0V1Y0dG'
    || 'dVpXeHpQejliWFNrdWJXRndLRlE5UGloN2FXUTZWQzVwWkN4c1lXSmxiRHBVTG5ScGRHeGxMR2xqYjI0NkluUmhZbXhsSWl4d1lXNWxiSE02VzFRdWFXUmRM'
    || 'SEpsYm1SbGNqb29LVDArYnk1cWMzZ29hSE1zZTNCaGVXeHZZV1E2ZFN4emNHVmpPbFI5S1gwcEtTeEZQV0V1YzJWamRHbHZibDl2Y21SbGNqOC9XMTA3Y21W'
    || 'MGRYSnVXeTR1TG1Nc0xpNHViVjB1YldGd0tGUTlQbnQyWVhJZ2VEdHlaWFIxY201N0xpNHVWQ3hzWVdKbGJEcFVMbWxrUFQwOUluQnZZMTl6ZFdOalpYTnpJ'
    || 'ajlVTG14aFltVnNPaWdvZUQxaExuTmxZM1JwYjI1ZmJHRmlaV3h6S1QwOWJuVnNiRDkyYjJsa0lEQTZlRnRVTG1sa1hTay9QMVF1YkdGaVpXeDlmU2t1YzI5'
    || 'eWRDZ29WQ3g0S1QwK2UyTnZibk4wSUdvOVJTNXBibVJsZUU5bUtGUXVhV1FwTEZNOVJTNXBibVJsZUU5bUtIZ3VhV1FwTzNKbGRIVnliaWhxUERBL1JTNXNa'
    || 'VzVuZEdnNmFpa3RLRk04TUQ5RkxteGxibWQwYURwVEtYMHBmV1oxYm1OMGFXOXVJR2h6S0h0d1lYbHNiMkZrT25Vc2MzQmxZenBqZlNsN2RtRnlJRkU3WTI5'
    || 'dWMzUWdZVDExTG5CaGJtVnNjMXRqTG1sa1hTeHRQV0VtSmlGeWJpaGhLVDloTG5KdmQzTTZXMTBzUlQxdExtMWhjQ2hTUFQ1TmRDaFNMbFpCVEZWRktTa3NW'
    || 'RDFGTG1WMlpYSjVLRkk5UGxJaFBUMXVkV3hzS1N4NFBVMWhkR2d1YldsdUtEQXNMaTR1UlM1dFlYQW9VajArVWo4L01Da3BMRk05VFdGMGFDNXRZWGdvTUN3'
    || 'dUxpNUZMbTFoY0NoU1BUNVNQejh3S1NrdGVIeDhNVHR5WlhSMWNtNGdieTVxYzNnb0luTmxZM1JwYjI0aUxIdHpkSGxzWlRwN1ozSnBaRU52YkhWdGJqb2lN'
    || 'U0F2SUMweElpeHRhVzVYYVdSMGFEb3dmU3dpWkdGMFlTMXZibVZ6YUc5MElqb2lZM1Z6ZEc5dExYQmhibVZzSWl4amFHbHNaSEpsYmpwdkxtcHplQ2hKWlN4'
    || 'N2NHRnVaV3c2WVN4amFHbHNaSEpsYmpwakxtdHBibVE5UFQwaWRHRmliR1VpUDI4dWFuTjRLSHAwTEh0eWIzZHpPbTBzYldGNE9tTXViR2x0YVhRc1kyOXNj'
    || 'enBQWW1wbFkzUXVhMlY1Y3lodFd6QmRQejk3ZlNrdWJXRndLRkk5UGloN2EyVjVPbEo5S1NsOUtUcFVQMk11YTJsdVpEMDlQU0p0WlhSeWFXTWlQMjB1YkdW'
    || 'dVozUm9JVDA5TVh4OFlTWW1JWEp1S0dFcEppWmhMblJ5ZFc1allYUmxaRDl2TG1wemVDZ2ljQ0lzZTNKdmJHVTZJbUZzWlhKMElpeGphR2xzWkhKbGJqb2lR'
    || 'U0J0WlhSeWFXTWdkbWxsZHlCdGRYTjBJSEpsZEhWeWJpQmxlR0ZqZEd4NUlHOXVaU0J5YjNjdUluMHBPbTh1YW5ONGN5Z2laR3dpTEh0amFHbHNaSEpsYmpw'
    || 'YmJ5NXFjM2dvSW1SMElpeDdZMmhwYkdSeVpXNDZVM1J5YVc1bktDZ29VVDF0V3pCZEtUMDliblZzYkQ5MmIybGtJREE2VVM1TVFVSkZUQ2svUHlJaUtYMHBM'
    || 'Rzh1YW5ONEtDSmtaQ0lzZTNOMGVXeGxPbnRtYjI1MFUybDZaVG96Tml4dFlYSm5hVzQ2SWpod2VDQXdJaXhtYjI1MFZtRnlhV0Z1ZEU1MWJXVnlhV002SW5S'
    || 'aFluVnNZWEl0Ym5WdGN5SjlMR05vYVd4a2NtVnVPbFVvUlZzd1hTbDlLVjE5S1RwdkxtcHplQ2dpWkdsMklpeDdjM1I1YkdVNmUyUnBjM0JzWVhrNkltZHlh'
    || 'V1FpTEdkaGNEb3hNbjBzWTJocGJHUnlaVzQ2YlM1dFlYQW9LRklzZWlrOVBudGpiMjV6ZENCSVBVVmJlbDAvUHpBc1pXVTlMWGd2VXlveE1EQXNZajBvU0Mx'
    || 'NEtTOVRLakV3TUR0eVpYUjFjbTRnYnk1cWMzaHpLQ0prYVhZaUxIdHpkSGxzWlRwN1pHbHpjR3hoZVRvaVozSnBaQ0lzWjNKcFpGUmxiWEJzWVhSbFEyOXNk'
    || 'VzF1Y3pvaWJXbHViV0Y0S0RFd01IQjRMQ0F4Wm5JcElHMXBibTFoZUNnNE1IQjRMQ0F6Wm5JcElHMXBibTFoZUNnMk1IQjRMQ0F4Wm5JcElpeG5ZWEE2TVRJ'
    || 'c1lXeHBaMjVKZEdWdGN6b2lZMlZ1ZEdWeUluMHNZMmhwYkdSeVpXNDZXMjh1YW5ONEtDSnpjR0Z1SWl4N2MzUjViR1U2ZTI5MlpYSm1iRzkzVjNKaGNEb2lZ'
    || 'VzU1ZDJobGNtVWlmU3hqYUdsc1pISmxianBUZEhKcGJtY29VaTVNUVVKRlREOC9JaUlwZlNrc2J5NXFjM2h6S0NKa2FYWWlMSHR5YjJ4bE9pSnBiV2NpTENK'
    || 'aGNtbGhMV3hoWW1Wc0lqcGdKSHRUZEhKcGJtY29VaTVNUVVKRlRDbDlPaUFrZTFVb1NDbDlZQ3h6ZEhsc1pUcDdhR1ZwWjJoME9qSXlMSEJ2YzJsMGFXOXVP'
    || 'aUp5Wld4aGRHbDJaU0lzWW1GamEyZHliM1Z1WkRvaWRtRnlLQzB0YkdsdVpTd2dJMlUwWlRkbFl5a2lmU3hqYUdsc1pISmxianBiYnk1cWMzZ29JbVJwZGlJ'
    || 'c2UzTjBlV3hsT250d2IzTnBkR2x2YmpvaVlXSnpiMngxZEdVaUxHeGxablE2WUNSN1RXRjBhQzV0YVc0b1pXVXNZaWw5SldBc2QybGtkR2c2WUNSN1RXRjBh'
    || 'QzVoWW5Nb1lpMWxaU2w5SldBc2FHVnBaMmgwT2lJeE1EQWxJaXhpWVdOclozSnZkVzVrT2lKMllYSW9MUzFoWTJObGJuUXNJQ014TmpjNVlUVXBJbjE5S1N4'
    || 'dkxtcHplQ2dpWkdsMklpeDdjM1I1YkdVNmUzQnZjMmwwYVc5dU9pSmhZbk52YkhWMFpTSXNiR1ZtZERwZ0pIdGxaWDBsWUN4M2FXUjBhRG94TEdobGFXZG9k'
    || 'RG9pTVRBd0pTSXNZbUZqYTJkeWIzVnVaRG9pZG1GeUtDMHRhVzVyTENBak1UY3lNVEppS1NKOWZTbGRmU2tzYnk1cWMzZ29Jbk53WVc0aUxIdHpkSGxzWlRw'
    || 'N2RHVjRkRUZzYVdkdU9pSnlhV2RvZENJc1ptOXVkRlpoY21saGJuUk9kVzFsY21sak9pSjBZV0oxYkdGeUxXNTFiWE1pZlN4amFHbHNaSEpsYmpwVktFZ3Bm'
    || 'U2xkZlN4NktYMHBmU2s2Ynk1cWMzZ29JbkFpTEh0eWIyeGxPaUpoYkdWeWRDSXNZMmhwYkdSeVpXNDZJbFpCVEZWRklHMTFjM1FnWW1VZ2JuVnRaWEpwWXk0'
    || 'Z1RtOGdZMmhoY25RZ2QyRnpJR1J5WVhkdUxpSjlLWDBwZlNsOVpuVnVZM1JwYjI0Z1FtTW9kU2w3ZG1GeUlHMHNSVHRqYjI1emRDQmpQU2h0UFhVOVBXNTFi'
    || 'R3cvZG05cFpDQXdPblV1WW5WcGJHUmxjbDkxY213cFBUMXVkV3hzUDNadmFXUWdNRHB0TG0xaGRHTm9LQzllYUhSMGNITTZYQzljTDJGd2NGd3VjMjV2ZDJa'
    || 'c1lXdGxYQzVqYjIxY0x5aGJZUzE2UVMxYU1DMDVYeTFkS3lsY0x5aGJZUzE2UVMxYU1DMDVYeTFkS3lsY0x5TmNMM04wY21WaGJXeHBkQzFoY0hCelhDOWJR'
    || 'UzFhTUMwNVgxMHJYQzViUVMxYU1DMDVYMTByWEM1YlFTMWFNQzA1WDEwckpDOHBMR0U5S0VVOWRUMDliblZzYkQ5MmIybGtJREE2ZFM1MmFXVjNaWEpmZFhK'
    || 'c0tUMDliblZzYkQ5MmIybGtJREE2UlM1dFlYUmphQ2d2WG1oMGRIQnpPbHd2WEM5aGNIQmNMbk51YjNkbWJHRnJaVnd1WTI5dFhDOXpkSEpsWVcxc2FYUmNM'
    || 'eWhiWVMxNlFTMWFNQzA1WHkxZEt5bGNMeWhiWVMxNlFTMWFNQzA1WHkxZEt5bGNMeU5jTDJGd2NITmNMMXRoTFhwQkxWb3dMVGxmTFYwckpDOHBPM0psZEhW'
    || 'eWJpRmpmSHdoWVh4OFkxc3hYU0U5UFdGYk1WMThmR05iTWwwaFBUMWhXekpkUDI1MWJHdzZXM3RzWVdKbGJEb2lRWEJ3SUc5dWJIa2lMR2h5WldZNmRTNTJh'
    || 'V1YzWlhKZmRYSnNmU3g3YkdGaVpXdzZJbE5vYjNjZ1UyNXZkM05wWjJoMElpeG9jbVZtT25VdVluVnBiR1JsY2w5MWNteDlYWDFtZFc1amRHbHZiaUJJWXlo'
    || 'N2JtRjJhV2RoZEdsdmJqcDFmU2w3WTI5dWMzUWdZejFZYkM1MWMyVlNaV1lvYm5Wc2JDa3NZVDFDWXloMUtUdHlaWFIxY200Z1dHd3VkWE5sUldabVpXTjBL'
    || 'Q2dwUFQ1N1kyOXVjM1FnYlQxRlBUNTdZeTVqZFhKeVpXNTBKaVloWXk1amRYSnlaVzUwTG1OdmJuUmhhVzV6S0VVdWRHRnlaMlYwS1NZbUtHTXVZM1Z5Y21W'
    || 'dWRDNXZjR1Z1UFNFeEtYMDdjbVYwZFhKdUlHUnZZM1Z0Wlc1MExtRmtaRVYyWlc1MFRHbHpkR1Z1WlhJb0luQnZhVzUwWlhKa2IzZHVJaXh0S1N3b0tUMCta'
    || 'RzlqZFcxbGJuUXVjbVZ0YjNabFJYWmxiblJNYVhOMFpXNWxjaWdpY0c5cGJuUmxjbVJ2ZDI0aUxHMHBmU3hiWFNrc1lUOXZMbXB6ZUhNb0ltUmxkR0ZwYkhN'
    || 'aUxIdGpiR0Z6YzA1aGJXVTZJbUZ3Y0MxMmFXVjNMVzFsYm5VaUxISmxaanBqTENKa1lYUmhMVzl1WlhOb2IzUWlPaUoyYVdWM0xXMWxiblVpTEc5dVMyVjVS'
    || 'RzkzYmpwdFBUNTdkbUZ5SUVVc1ZEdHRMbXRsZVQwOVBTSkZjMk5oY0dVaUppWW9LRVU5WXk1amRYSnlaVzUwS1NFOWJuVnNiQ1ltUlM1dmNHVnVLU1ltS0cw'
    || 'dWNISmxkbVZ1ZEVSbFptRjFiSFFvS1N4akxtTjFjbkpsYm5RdWIzQmxiajBoTVN3b1ZEMWpMbU4xY25KbGJuUXVjWFZsY25sVFpXeGxZM1J2Y2lnaWMzVnRi'
    || 'V0Z5ZVNJcEtUMDliblZzYkh4OFZDNW1iMk4xY3lncEtYMHNZMmhwYkdSeVpXNDZXMjh1YW5ONEtDSnpkVzF0WVhKNUlpeDdJbUZ5YVdFdGJHRmlaV3dpT2lK'
    || 'QmNIQWdkbWxsZHlCdmNIUnBiMjV6SWl4MGFYUnNaVG9pUVhCd0lIWnBaWGNnYjNCMGFXOXVjeUlzWTJocGJHUnlaVzQ2Ynk1cWMzZ29Jbk4yWnlJc2UzWnBa'
    || 'WGRDYjNnNklqQWdNQ0F5TkNBeU5DSXNkMmxrZEdnNklqSXdJaXhvWldsbmFIUTZJakl3SWl4bWFXeHNPaUp1YjI1bElpeHpkSEp2YTJVNkltTjFjbkpsYm5S'
    || 'RGIyeHZjaUlzYzNSeWIydGxWMmxrZEdnNklqRXVOaUlzYzNSeWIydGxUR2x1WldOaGNEb2ljbTkxYm1RaUxITjBjbTlyWlV4cGJtVnFiMmx1T2lKeWIzVnVa'
    || 'Q0lzSW1GeWFXRXRhR2xrWkdWdUlqb2lkSEoxWlNJc1kyaHBiR1J5Wlc0NmJ5NXFjM2dvSW5CaGRHZ2lMSHRrT2lKTk9DQXpTRE4yTlcweE15MDFhRFYyTlUw'
    || 'eklERTJkalZvTlcweE15MDFkalZvTFRVaWZTbDlLWDBwTEc4dWFuTjRLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbUZ3Y0MxMmFXVjNMVzl3ZEdsdmJuTWlM'
    || 'R05vYVd4a2NtVnVPbUV1YldGd0tHMDlQbTh1YW5ONEtDSmhJaXg3YUhKbFpqcHRMbWh5WldZc2RHRnlaMlYwT2lKZllteGhibXNpTEhKbGJEb2libTl2Y0dW'
    || 'dVpYSWdibTl5WldabGNuSmxjaUlzSW1GeWFXRXRiR0ZpWld3aU9tQWtlMjB1YkdGaVpXeDlJQ2h2Y0dWdWN5QnBiaUJoSUc1bGR5QjBZV0lwWUN4dmJrTnNh'
    || 'V05yT2lncFBUNTdZeTVqZFhKeVpXNTBKaVlvWXk1amRYSnlaVzUwTG05d1pXNDlJVEVwZlN4amFHbHNaSEpsYmpwdExteGhZbVZzZlN4dExteGhZbVZzS1Ns'
    || 'OUtWMTlLVHB1ZFd4c2ZXTnZibk4wSUhKcFBTSndiMk5mYzNWalkyVnpjeUk3Wm5WdVkzUnBiMjRnSkdNb2UzQmhlV3h2WVdRNmRTeHpaV04wYVc5dWN6cGpM'
    || 'SE4xWW5ScGRHeGxPbUVzWTJocGJHUnlaVzQ2YlgwcGUzWmhjaUJMTEdwbExHRmxMR05sTEdkbE8yTnZibk4wSUVVOWRTNWpiMjUwWlhoMFB6OTdmU3g0UFZO'
    || 'MGNtbHVaeWhGTGsxUFJFVS9QeUlpS1M1MGIxVndjR1Z5UTJGelpTZ3BQVDA5SWxOQlRWQk1SU0lzYWowb0tFczlkUzVqZFhOMGIyMXBlbUYwYVc5dUtUMDli'
    || 'blZzYkQ5MmIybGtJREE2U3k1MGFYUnNaU2svUDFOMGNtbHVaeWhGTGxOUFRGVlVTVTlPUHo4aVUyNXZkMlpzWVd0bElITnZiSFYwYVc5dUlpa3NVejFyWXlo'
    || 'MUtTeFJQV0Z6S0hVcExGSTllMmxrT25KcExHeGhZbVZzT2lKUVQwTWdjM1ZqWTJWemN5SXNaR1Z6WXpvaVZHRnlaMlYwY3l3Z1lXNWtJSGRvWlhSb1pYSWdk'
    || 'R2hsZVNCaGNtVWdiV1YwSWl4cFkyOXVPbE11ZG1WeVpHbGpkRDA5UFNKT1QxUmZUVVZVSWo4aWQyRnliaUk2SW1Ob1pXTnJJaXhpWVdSblpUcFRMblZ1WVha'
    || 'aGFXeGhZbXhsZkh4VExuWmxjbVJwWTNROVBUMGlUazlVWDFKVlRpSS9kbTlwWkNBd09tQWtlMU11YldWMGZTOGtlMU11YzJOdmNtVmtmV0FzWW1Ga1oyVlVi'
    || 'MjVsT2xNdWRtVnlaR2xqZEQwOVBTSk9UMVJmVFVWVUlqOGlZbUZrSWpwVExuWmxjbVJwWTNROVBUMGlUVVZVSWo4aVoyOXZaQ0k2VXk1MlpYSmthV04wUFQw'
    || 'OUlrMUZWRjlYU1ZSSVgxQkZUa1JKVGtjaVB5SjNZWEp1SWpvaWFXUnNaU0lzY0dGdVpXeHpPbHNpY0c5algzTmpiM0psWTJGeVpDSXNJbkJ2WTE5MlpYSmth'
    || 'V04wSWwwc2NtVnVaR1Z5T2lncFBUNXZMbXB6ZUNod2N5eDdZM0pwZEdWeWFXRTZVU3gyT2xNc2NHRnVaV3c2ZFM1d1lXNWxiSE11Y0c5algzTmpiM0psWTJG'
    || 'eVpDeDJaWEprYVdOMFVHRnVaV3c2ZFM1d1lXNWxiSE11Y0c5algzWmxjbVJwWTNSOUtYMHNlajFqSmlaakxteGxibWQwYUQ5V1l5aDFMR011YzI5dFpTaHZa'
    || 'VDArYjJVdWFXUTlQVDF5YVNrL1l6cGJMaTR1WXl4U1hTazZkbTlwWkNBd0xFZzlLR3BsUFhVdVkzVnpkRzl0YVhwaGRHbHZiaWs5UFc1MWJHdy9kbTlwWkNB'
    || 'd09tcGxMbVJsWm1GMWJIUmZjMlZqZEdsdmJpeGxaVDBvS0dGbFBYbzlQVzUxYkd3L2RtOXBaQ0F3T25vdVptbHVaQ2h2WlQwK2IyVXVhV1E5UFQxSUtTazlQ'
    || 'VzUxYkd3L2RtOXBaQ0F3T21GbExtbGtLVDgvS0NoalpUMTZQVDF1ZFd4c1AzWnZhV1FnTURwNld6QmRLVDA5Ym5Wc2JEOTJiMmxrSURBNlkyVXVhV1FwUHo4'
    || 'aUlpeGJZaXhLWFQxeFpTNTFjMlZUZEdGMFpTaGxaU2tzUnowb2VqMDliblZzYkQ5MmIybGtJREE2ZWk1bWFXNWtLRzlsUFQ1dlpTNXBaRDA5UFdJcEtUOC9L'
    || 'SG85UFc1MWJHdy9kbTlwWkNBd09ucGJNRjBwTzJsbUtIVXVabUYwWVd3cGNtVjBkWEp1SUc4dWFuTjRLQ0prYVhZaUxIdGpiR0Z6YzA1aGJXVTZJbUZ3Y0NC'
    || 'aGNIQXRMVzV2Ym1GMklpeGphR2xzWkhKbGJqcHZMbXB6ZUhNb0ltUnBkaUlzZTJOc1lYTnpUbUZ0WlRvaVptRjBZV3dpTENKa1lYUmhMVzl1WlhOb2IzUWlP'
    || 'aUptWVhSaGJDSXNZMmhwYkdSeVpXNDZXMjh1YW5ONEtDSm9NU0lzZTJOb2FXeGtjbVZ1T2lKVWFHbHpJR0Z3Y0NCallXNXViM1FnYzJodmR5QmhibmwwYUds'
    || 'dVp5SjlLU3h2TG1wemVDZ2lZMjlrWlNJc2UyTm9hV3hrY21WdU9uVXVabUYwWVd4OUtWMTlLWDBwTzJOdmJuTjBJSFJsUFNFaGVpWW1laTVzWlc1bmRHZytN'
    || 'Q3hUWlQxdkxtcHplSE1vYnk1R2NtRm5iV1Z1ZEN4N1kyaHBiR1J5Wlc0NlczZy9ieTVxYzNnb0ltUnBkaUlzZTJOc1lYTnpUbUZ0WlRvaVltRnVibVZ5SUdK'
    || 'aGJtNWxjaTB0YzJGdGNHeGxJaXdpWkdGMFlTMXZibVZ6YUc5MElqb2ljMkZ0Y0d4bExXSmhibTVsY2lJc1kyaHBiR1J5Wlc0NklsTkJUVkJNUlNCRVFWUkJJ'
    || 'T0tBbENCMGFHVnpaU0J1ZFcxaVpYSnpJR052YldVZ1puSnZiU0J6WldWa1pXUWdabWw0ZEhWeVpYTXNJRzV2ZENCbWNtOXRJSGx2ZFhJZ1lXTmpiM1Z1ZENK'
    || 'OUtUcHVkV3hzTEc4dWFuTjRjeWdpYUdWaFpHVnlJaXg3WTJ4aGMzTk9ZVzFsT2lKaGNIQmZYMmhsWVdRaUxHTm9hV3hrY21WdU9sdHZMbXB6ZUhNb0ltUnBk'
    || 'aUlzZTJOb2FXeGtjbVZ1T2x0dkxtcHplQ2dpYURFaUxIdGphR2xzWkhKbGJqcEhQMGN1YkdGaVpXdzZhbjBwTEc4dWFuTjRjeWdpY0NJc2UyTnNZWE56VG1G'
    || 'dFpUb2lZWEJ3WDE5emRXSWlMR05vYVd4a2NtVnVPbHNpWW5WcGJIUWdhVzRnSWl4dkxtcHplQ2dpWTI5a1pTSXNlMk5vYVd4a2NtVnVPbE4wY21sdVp5aEZM'
    || 'a0pWU1V4VVgwbE9QejhpNG9DVUlpbDlLU3hGTGxkSlRrUlBWMTlFUVZsVFAyOHVhbk40Y3lodkxrWnlZV2R0Wlc1MExIdGphR2xzWkhKbGJqcGJJaURDdHlB'
    || 'aUxGTjBjbWx1WnloRkxsZEpUa1JQVjE5RVFWbFRLU3dpTFdSaGVTQjNhVzVrYjNjaVhYMHBPbTUxYkd3c1JTNUNWVWxNVkY5QlZEOXZMbXB6ZUhNb2J5NUdj'
    || 'bUZuYldWdWRDeDdZMmhwYkdSeVpXNDZXeUlnd3JjZ0lpeFRkSEpwYm1jb1JTNUNWVWxNVkY5QlZDa3VjMnhwWTJVb01Dd3hPU2t1Y21Wd2JHRmpaU2dpVkNJ'
    || 'c0lpQWlLVjE5S1RwdWRXeHNYWDBwWFgwcExHOHVhbk40Y3lnaVpHbDJJaXg3WTJ4aGMzTk9ZVzFsT2lKaGNIQmZYMmhsWVdSeWFXZG9kQ0lzWTJocGJHUnla'
    || 'VzQ2VzI4dWFuTjRLRmRqTEh0Mk9sTXNiMjVQY0dWdU9uUmxQeWdwUFQ1S0tISnBLVHAyYjJsa0lEQjlLU3h2TG1wemVDaEhZeXg3Y0dGNWJHOWhaRHAxZlNr'
    || 'c2J5NXFjM2dvU0dNc2UyNWhkbWxuWVhScGIyNDZkUzV1WVhacFoyRjBhVzl1ZlNsZGZTbGRmU2tzYnk1cWMzZ29TMk1zZTNCaGVXeHZZV1E2ZFgwcExIVXVZ'
    || 'M1Z6ZEc5dGFYcGhkR2x2Ymw5bGNuSnZjajl2TG1wemVDZ2ljQ0lzZTNKdmJHVTZJbUZzWlhKMElpeGpiR0Z6YzA1aGJXVTZJbkJoYm1Wc0xXVnljbTl5SWl4'
    || 'amFHbHNaSEpsYmpwMUxtTjFjM1J2YldsNllYUnBiMjVmWlhKeWIzSjlLVHB1ZFd4c1hYMHBPMmxtS0NGMFpTbHlaWFIxY200Z2J5NXFjM2dvSW1ScGRpSXNl'
    || 'Mk5zWVhOelRtRnRaVG9pWVhCd0lHRndjQzB0Ym05dVlYWWlMR05vYVd4a2NtVnVPbTh1YW5ONGN5Z2laR2wySWl4N1kyeGhjM05PWVcxbE9pSnRZV2x1SWl4'
    || 'amFHbHNaSEpsYmpwYlUyVXNieTVxYzNoektDSnRZV2x1SWl4N1kyeGhjM05PWVcxbE9pSm5jbWxrSWl3aVpHRjBZUzF2Ym1WemFHOTBJam9pYzJWamRHbHZi'
    || 'aUlzSW1SaGRHRXRjMlZqZEdsdmJpSTZJbk5wYm1kc1pTSXNZMmhwYkdSeVpXNDZXMjBzS0Nnb1oyVTlkUzVqZFhOMGIyMXBlbUYwYVc5dUtUMDliblZzYkQ5'
    || 'MmIybGtJREE2WjJVdWNHRnVaV3h6S1Q4L1cxMHBMbTFoY0NodlpUMCtieTVxYzNoektIRmxMa1p5WVdkdFpXNTBMSHRqYUdsc1pISmxianBiYnk1cWMzZ29J'
    || 'bWd5SWl4N2MzUjViR1U2ZTJkeWFXUkRiMngxYlc0NklqRWdMeUF0TVNKOUxHTm9hV3hrY21WdU9tOWxMblJwZEd4bGZTa3NieTVxYzNnb2FITXNlM0JoZVd4'
    || 'dllXUTZkU3h6Y0dWak9tOWxmU2xkZlN4dlpTNXBaQ2twTEc4dWFuTjRLSEJ6TEh0amNtbDBaWEpwWVRwUkxIWTZVeXh3WVc1bGJEcDFMbkJoYm1Wc2N5NXdi'
    || 'Mk5mYzJOdmNtVmpZWEprTEhabGNtUnBZM1JRWVc1bGJEcDFMbkJoYm1Wc2N5NXdiMk5mZG1WeVpHbGpkSDBwWFgwcExHOHVhbk40S0ZsakxIdDlLVjE5S1gw'
    || 'cE8yTnZibk4wSUVJOWVpNXRZWEFvYjJVOVBpaDdMaTR1YjJVc2MzUmhkSFZ6T205bExuTjBZWFIxY3o4L1VXTW9kU3h2WlNsOUtTazdjbVYwZFhKdUlHOHVh'
    || 'bk40Y3lnaVpHbDJJaXg3WTJ4aGMzTk9ZVzFsT2lKaGNIQWlMR05vYVd4a2NtVnVPbHR2TG1wemVDaFBZeXg3YzI5c2RYUnBiMjQ2YWl4emRXSjBhWFJzWlRw'
    || 'aExITmxZM1JwYjI1ek9rSXNZV04wYVhabE9tSXNiMjVRYVdOck9rb3NabTl2ZERwdkxtcHplQ2h2TGtaeVlXZHRaVzUwTEh0amFHbHNaSEpsYmpvaVJHRjBZ'
    || 'U0JqYjIxbGN5Qm1jbTl0SUhacFpYZHpJR2x1SUhSb2FYTWdjMk5vWlcxaExpQlNaV0ZrY3lCdFlYa2dZbVVnY21WMWMyVmtJR1p2Y2lBek1DQnpaV052Ym1S'
    || 'eklIZHBkR2hwYmlCNWIzVnlJSE5sYzNOcGIyNDdJRkpsWm5KbGMyZ2daR0YwWVNCbVpYUmphR1Z6SUdGbllXbHVMaUo5S1gwcExHOHVhbk40Y3lnaVpHbDJJ'
    || 'aXg3WTJ4aGMzTk9ZVzFsT2lKdFlXbHVJaXhqYUdsc1pISmxianBiVTJVc2J5NXFjM2dvSW0xaGFXNGlMSHRqYkdGemMwNWhiV1U2SW1keWFXUWdjbllpTENK'
    || 'a1lYUmhMVzl1WlhOb2IzUWlPaUp6WldOMGFXOXVJaXdpWkdGMFlTMXpaV04wYVc5dUlqcGlMR05vYVd4a2NtVnVPa2MvUnk1eVpXNWtaWElvS1RwdWRXeHNm'
    || 'U3hpS1YxOUtWMTlLWDFtZFc1amRHbHZiaUJSWXloMUxHTXBlMk52Ym5OMElHRTlZeTV3WVc1bGJITS9QMXRkTzJsbUtHRXVjMjl0WlNodFBUNXliaWgxTG5C'
    || 'aGJtVnNjMXR0WFNrbUppRnNiaWgxTG5CaGJtVnNjMXR0WFNrcEtYSmxkSFZ5YmlKaVlXUWlPMmxtS0dFdWMyOXRaU2h0UFQ1c2JpaDFMbkJoYm1Wc2MxdHRY'
    || 'U2twS1hKbGRIVnliaUpwYm1adkluMW1kVzVqZEdsdmJpQlpZeWdwZTNKbGRIVnliaUJ2TG1wemVDZ2labTl2ZEdWeUlpeDdZMnhoYzNOT1lXMWxPaUpoY0hC'
    || 'ZlgyWnZiM1FpTEhOMGVXeGxPbnR0WVhKbmFXNVViM0E2TWpBc1ptOXVkRk5wZW1VNk1URXVOU3hqYjJ4dmNqb2lkbUZ5S0MwdFpHbHRLU0o5TEdOb2FXeGtj'
    || 'bVZ1T2lKRVlYUmhJR052YldWeklHWnliMjBnZG1sbGQzTWdhVzRnZEdocGN5QnpZMmhsYldFdUlGSmxZV1J6SUcxaGVTQmlaU0J5WlhWelpXUWdabTl5SURN'
    || 'd0lITmxZMjl1WkhNZ2QybDBhR2x1SUhsdmRYSWdjMlZ6YzJsdmJqc2dVbVZtY21WemFDQmtZWFJoSUdabGRHTm9aWE1nWVdkaGFXNHVJbjBwZldaMWJtTjBh'
    || 'Vzl1SUVkaktIdHdZWGxzYjJGa09uVjlLWHQyWVhJZ2VEdGpiMjV6ZENCalBVTmpLSFV1WTI5dWRHVjRkQ2tzVzJFc2JWMDljV1V1ZFhObFUzUmhkR1VvYm5W'
    || 'c2JDa3NSVDBvS0hnOVl5NW1hVzVrS0dvOVBtb3VjM1JoZEdVOVBUMGlZM1Z5Y21WdWRDSXBLVDA5Ym5Wc2JEOTJiMmxrSURBNmVDNXBaQ2svUDI1MWJHd3NW'
    || 'RDFoUDJNdVptbHVaQ2hxUFQ1cUxtbGtQVDA5WVNrNmJuVnNiRHR5WlhSMWNtNGdieTVxYzNoektDSmthWFlpTEh0amJHRnpjMDVoYldVNkluQm9ZWE5sSWl4'
    || 'amFHbHNaSEpsYmpwYmJ5NXFjM2dvSW1ScGRpSXNlMk5zWVhOelRtRnRaVG9pY0doaGMyVmZYM0poYVd3aUxISnZiR1U2SW1keWIzVndJaXdpWVhKcFlTMXNZ'
    || 'V0psYkNJNklrUmxjR3h2ZVcxbGJuUWdjR2hoYzJVaUxHTm9hV3hrY21WdU9tTXViV0Z3S0dvOVBtOHVhbk40Y3lnaVluVjBkRzl1SWl4N2RIbHdaVG9pWW5W'
    || 'MGRHOXVJaXdpWkdGMFlTMXdhR0Z6WlNJNmFpNXBaQ3hqYkdGemMwNWhiV1U2SW5Cb1lYTmxYMTlpZEc0Z2NHaGhjMlZmWDJKMGJpMHRJaXRxTG5OMFlYUmxL'
    || 'eWhoUFQwOWFpNXBaRDhpSUdsekxXOXdaVzRpT2lJaUtTd2lZWEpwWVMxamRYSnlaVzUwSWpwcUxuTjBZWFJsUFQwOUltTjFjbkpsYm5RaVB5SnpkR1Z3SWpw'
    || 'MmIybGtJREFzSW1GeWFXRXRaWGh3WVc1a1pXUWlPbUU5UFQxcUxtbGtMRzl1UTJ4cFkyczZLQ2s5UG0wb1lUMDlQV291YVdRL2JuVnNiRHBxTG1sa0tTeGph'
    || 'R2xzWkhKbGJqcGJieTVxYzNnb0luTndZVzRpTEh0amJHRnpjMDVoYldVNkluQm9ZWE5sWDE5c1lXSmxiQ0lzWTJocGJHUnlaVzQ2YWk1c1lXSmxiSDBwTEc4'
    || 'dWFuTjRLQ0p6Y0dGdUlpeDdZMnhoYzNOT1lXMWxPaUp3YUdGelpWOWZabWxuZFhKbElpeGphR2xzWkhKbGJqcHFMbVpwWjNWeVpYMHBMR291Ylc5dVpYay9i'
    || 'eTVxYzNnb0luTndZVzRpTEh0amJHRnpjMDVoYldVNkluQm9ZWE5sWDE5dGIyNWxlU0lzWTJocGJHUnlaVzQ2YWk1dGIyNWxlWDBwT201MWJHeGRmU3hxTG1s'
    || 'a0tTbDlLU3hVUDI4dWFuTjRjeWdpWkdsMklpeDdZMnhoYzNOT1lXMWxPaUp3YUdGelpWOWZaR1YwWVdsc0lpeGphR2xzWkhKbGJqcGJieTVxYzNnb0luQWlM'
    || 'SHRqYkdGemMwNWhiV1U2SW5Cb1lYTmxYMTlpYkhWeVlpSXNZMmhwYkdSeVpXNDZWQzVpYkhWeVluMHBMRzh1YW5ONGN5Z2ljQ0lzZTJOc1lYTnpUbUZ0WlRv'
    || 'aWNHaGhjMlZmWDJKaGMybHpJaXhqYUdsc1pISmxianBiYnk1cWMzZ29Jbk4wY205dVp5SXNlMk5vYVd4a2NtVnVPbFF1Wm1sbmRYSmxmU2tzVkM1dGIyNWxl'
    || 'VDl2TG1wemVITW9ieTVHY21GbmJXVnVkQ3g3WTJocGJHUnlaVzQ2V3lJZ0tDSXNWQzV0YjI1bGVTd2lLU0pkZlNrNmJuVnNiQ3dpSU9LQWxDQWlMRlF1WW1G'
    || 'emFYTmRmU2tzVkM1cFpEMDlQVVUvYnk1cWMzZ29JbkFpTEh0amJHRnpjMDVoYldVNkluQm9ZWE5sWDE5M2FHVnlaU0lzWTJocGJHUnlaVzQ2SWxSb2FYTWdZ'
    || 'blZwYkdRZ2FYTWdhVzRnZEdocGN5QndhR0Z6WlM0aWZTazZieTVxYzNoektDSndJaXg3WTJ4aGMzTk9ZVzFsT2lKd2FHRnpaVjlmYUc5M0lpeGphR2xzWkhK'
    || 'bGJqcGJJbFJ2SUcxdmRtVWdhR1Z5WlN3Z2MyVjBJSFJvYVhNZ2FXNGdkR2hsSUhOamNtbHdkQ0JoYm1RZ2NuVnVJR2wwSUdGbllXbHVPaUlzSWlBaUxHOHVh'
    || 'bk40S0NKamIyUmxJaXg3WTJocGJHUnlaVzQ2VkM1elpYUjBhVzVuZlNsZGZTbGRmU2s2Ym5Wc2JGMTlLWDFtZFc1amRHbHZiaUJMWXloN2NHRjViRzloWkRw'
    || 'MWZTbDdZMjl1YzNRZ1l6MVBZbXBsWTNRdWEyVjVjeWgxTG5CaGJtVnNjeWt1Wm1sc2RHVnlLRVU5UGtVaFBUMGlZMjl1ZEdWNGRDSXBMR0U5WXk1bWFXeDBa'
    || 'WElvUlQwK2JHNG9kUzV3WVc1bGJITmJSVjBwS1N4dFBXTXVabWxzZEdWeUtFVTlQbkp1S0hVdWNHRnVaV3h6VzBWZEtTWW1JV3h1S0hVdWNHRnVaV3h6VzBW'
    || 'ZEtTazdjbVYwZFhKdUlXRXViR1Z1WjNSb0ppWWhiUzVzWlc1bmRHZy9iblZzYkRwdkxtcHplSE1vYnk1R2NtRm5iV1Z1ZEN4N1kyaHBiR1J5Wlc0NlcyMHVi'
    || 'R1Z1WjNSb1AyOHVhbk40Y3lnaVpHbDJJaXg3WTJ4aGMzTk9ZVzFsT2lKaVlXNXVaWElnWW1GdWJtVnlMUzFtWVdsc0lpeGphR2xzWkhKbGJqcGJiUzVzWlc1'
    || 'bmRHZ3NJaUJ2WmlBaUxHTXViR1Z1WjNSb0xDSWdjR0Z1Wld4eklHUnBaQ0J1YjNRZ2JHOWhaQ0FvSWl4dExtcHZhVzRvSWl3Z0lpa3NJaWt1SUZSb1pTQnVk'
    || 'VzFpWlhKeklHSmxiRzkzSUdGeVpTQnBibU52YlhCc1pYUmxMaUpkZlNrNmJuVnNiQ3hoTG14bGJtZDBhRDl2TG1wemVITW9JbVJwZGlJc2UyTnNZWE56VG1G'
    || 'dFpUb2lZbUZ1Ym1WeUlHSmhibTVsY2kwdGFXNW1ieUlzWTJocGJHUnlaVzQ2VzJFdWJHVnVaM1JvTENJZ2IyWWdJaXhqTG14bGJtZDBhQ3dpSUhObFkzUnBi'
    || 'MjV6SUhkbGNtVWdibTkwSUdKMWFXeDBJR0o1SUhSb2FYTWdjblZ1SUNnaUxHRXVhbTlwYmlnaUxDQWlLU3dpS1M0Z1ZHaGhkQ0JwY3lCbGVIQmxZM1JsWkNC'
    || 'dmJpQmhJR1JwYzJOdmRtVnllUzF2Ym14NUlISjFiaURpZ0pRZ1pXRmphQ0JqWVhKa0lITmhlWE1nZDJocFkyZ2djMlYwZEdsdVp5Qm1hV3hzY3lCcGRDQnBi'
    || 'aTRpWFgwcE9tNTFiR3hkZlNsOVpuVnVZM1JwYjI0Z1dHTW9kU2w3WTI5dWMzUWdZejFrYjJOMWJXVnVkQzVuWlhSRmJHVnRaVzUwUW5sSlpDZ2ljbTl2ZENJ'
    || 'cE8ybG1LQ0ZqS1h0amIyNXpiMnhsTG1WeWNtOXlLQ0p2Ym1WemFHOTBJRlZKT2lCdWJ5QWpjbTl2ZENCbGJHVnRaVzUwSUhSdklHMXZkVzUwSUdsdWRHOGlL'
    || 'VHR5WlhSMWNtNTlZMjl1YzNRZ1lUMVRZeWdwTzNoakxtTnlaV0YwWlZKdmIzUW9ZeWt1Y21WdVpHVnlLRzh1YW5ONEtHOHVSbkpoWjIxbGJuUXNlMk5vYVd4'
    || 'a2NtVnVPblVvWVNsOUtTbDlablZ1WTNScGIyNGdiWE1vZTNnNmRTeDVPbU1zZG1semFXSnNaVHBoTEdOb2FXeGtjbVZ1T20xOUtYdGpiMjV6ZENCRlBYRmxM'
    || 'blZ6WlZKbFppaHVkV3hzS1N4YlZDeDRYVDF4WlM1MWMyVlRkR0YwWlNoN2JHVm1kRG93TEhSdmNEb3dmU2s3Y21WMGRYSnVJSEZsTG5WelpVVm1abVZqZENn'
    || 'b0tUMCtlMmxtS0NGaGZId2hSUzVqZFhKeVpXNTBLWEpsZEhWeWJqdGpiMjV6ZENCcVBVVXVZM1Z5Y21WdWRDeFRQV291YjJabWMyVjBWMmxrZEdnc1VUMXFM'
    || 'bTltWm5ObGRFaGxhV2RvZEN4U1BYZHBibVJ2ZHk1cGJtNWxjbGRwWkhSb0xIbzlkMmx1Wkc5M0xtbHVibVZ5U0dWcFoyaDBMRWc5ZFNzeE1pdFRQbEkvZFMx'
    || 'VExUZzZkU3N4TWl4bFpUMWpLemdyVVQ1NlAyTXRVUzAwT21Nck9EdDRLSHRzWldaME9rMWhkR2d1YldGNEtESXNTQ2tzZEc5d09rMWhkR2d1YldGNEtESXNa'
    || 'V1VwZlNsOUxGdDFMR01zWVYwcExHRS9ieTVxYzNnb0ltUnBkaUlzZTNKbFpqcEZMR05zWVhOelRtRnRaVG9pYUc5MlpYSXRaR1YwWVdsc0lpeHpkSGxzWlRw'
    || 'N2JHVm1kRHBVTG14bFpuUXNkRzl3T2xRdWRHOXdmU3hqYUdsc1pISmxianB0ZlNrNmJuVnNiSDFtZFc1amRHbHZiaUJhWXloN2MzVnRiV0Z5ZVRwMUxHTm9h'
    || 'V3hrY21WdU9tTXNaR1ZtWVhWc2RFOXdaVzQ2WVQwaE1YMHBlMk52Ym5OMFcyMHNSVjA5Y1dVdWRYTmxVM1JoZEdVb1lTazdjbVYwZFhKdUlHOHVhbk40Y3ln'
    || 'aVpHbDJJaXg3WTJocGJHUnlaVzQ2VzI4dWFuTjRjeWdpWW5WMGRHOXVJaXg3ZEhsd1pUb2lZblYwZEc5dUlpeGpiR0Z6YzA1aGJXVTZJbVJ5YVd4c0xYSnZk'
    || 'MTlmZEc5bloyeGxJaXh2YmtOc2FXTnJPaWdwUFQ1RktGUTlQaUZVS1N3aVlYSnBZUzFsZUhCaGJtUmxaQ0k2YlN4amFHbHNaSEpsYmpwYmJ5NXFjM2dvSW5O'
    || 'Mlp5SXNlMk5zWVhOelRtRnRaVG9pWkhKcGJHd3RjbTkzWDE5amFHVjJjbTl1SWlzb2JUOGlJR1J5YVd4c0xYSnZkMTlmWTJobGRuSnZiaTB0YjNCbGJpSTZJ'
    || 'aUlwTEhkcFpIUm9PaUl4TWlJc2FHVnBaMmgwT2lJeE1pSXNkbWxsZDBKdmVEb2lNQ0F3SURFMklERTJJaXhtYVd4c09pSnViMjVsSWl3aVlYSnBZUzFvYVdS'
    || 'a1pXNGlPaUowY25WbElpeGphR2xzWkhKbGJqcHZMbXB6ZUNnaWNHRjBhQ0lzZTJRNklrMDJJRFJzTkNBMExUUWdOQ0lzYzNSeWIydGxPaUpqZFhKeVpXNTBR'
    || 'MjlzYjNJaUxITjBjbTlyWlZkcFpIUm9PaUl4TGpVaUxITjBjbTlyWlV4cGJtVmpZWEE2SW5KdmRXNWtJaXh6ZEhKdmEyVk1hVzVsYW05cGJqb2ljbTkxYm1R'
    || 'aWZTbDlLU3gxWFgwcExHMC9ieTVxYzNnb0ltUnBkaUlzZTJOc1lYTnpUbUZ0WlRvaVpISnBiR3d0Y205M1gxOWphR2xzWkhKbGJpSXNZMmhwYkdSeVpXNDZZ'
    || 'MzBwT201MWJHeGRmU2w5WTI5dWMzUWdRVDExUFQ1T2RXMWlaWElvZFQ4L01Da3NTWEk5ZFQwK1lDUjdUV0YwYUM1eWIzVnVaQ2hCS0hVcEtqRmxNeWt2TVRC'
    || 'OUpXQXNRWEk5ZTFOVVVrOU9Sem9pWjI5dlpDSXNURWxMUlV4Wk9pSm5iMjlrSWl4UVNVeFBWRjlQVGt4Wk9pSjNZWEp1SWl4QlZrOUpSRG9pWW1Ga0lpeEJU'
    || 'RkpGUVVSWlgwZEZUakk2ZG05cFpDQXdMRkpGUTA5TlRVVk9SRVZFT2lKbmIyOWtJaXhPVDFSZlYwOVNWRWhmU1ZRNmRtOXBaQ0F3TEU1UFgwVldTVVJGVGtO'
    || 'Rk9pSjNZWEp1SWl4UFRqcDJiMmxrSURBc1FVeFNSVUZFV1Y5QlJFRlFWRWxXUlRwMmIybGtJREFzUzBWRlVGOVRWRUZPUkVGU1JEcDJiMmxrSURBc1NVNUZU'
    || 'RWxIU1VKTVJWOVVXVkJGT25admFXUWdNQ3hKVGtWTVNVZEpRa3hGWDFOSldrVTZkbTlwWkNBd0xGVk9VMVZRVUU5U1ZFVkVYME5QVGxaRlVsTkpUMDQ2ZG05'
    || 'cFpDQXdMRlZPVTFWUVVFOVNWRVZFWDFOSldrVTZkbTlwWkNBd0xFbE5UVUZVUlZKSlFVdzZkbTlwWkNBd2ZTeHNhVDE3UTA5VFZFbE9SMTlNUlZOVE9pSm5i'
    || 'MjlrSWl4RFQxTlVTVTVIWDAxUFVrVTZJbUpoWkNJc1RrOWZUVUZVUlZKSlFVeGZRMGhCVGtkRk9pSjNZWEp1SWl4VVQwOWZSVUZTVEZrNkluZGhjbTRpZlN4'
    || 'eFl6MWJJbE5VVWs5T1J5SXNJa3hKUzBWTVdTSmRPMloxYm1OMGFXOXVJRXBqS0h0d09uVjlLWHRqYjI1emRDQmpQVU5sS0hVc0ltZGxiaklpS1N4aFBVTmxL'
    || 'SFVzSW1WamIyNXZiV2xqY3lJcFd6QmRQejk3ZlN4dFBVRW9ZUzVTUlZGVlNWSkZSRjlUVUVWRlJGVlFYMUJEVkNrc1cwVXNWRjA5Y1dVdWRYTmxVM1JoZEdV'
    || 'b2JuVnNiQ2s3YVdZb0lXTXViR1Z1WjNSb2ZId2hiU2x5WlhSMWNtNGdiblZzYkR0amIyNXpkQ0I0UFZzdUxpNWpYUzVtYVd4MFpYSW9kR1U5UGxOMGNtbHVa'
    || 'eWgwWlM1V1JWSkVTVU5VS1NFOVBTSkJURkpGUVVSWlgwZEZUaklpS1M1emIzSjBLQ2gwWlN4VFpTazlQa0VvVTJVdVExSkZSRWxVVTE5UVJWSmZSRUZaS1Mx'
    || 'QktIUmxMa05TUlVSSlZGTmZVRVZTWDBSQldTa3BMbk5zYVdObEtEQXNNVEFwTzJsbUtDRjRMbXhsYm1kMGFDbHlaWFIxY200Z2JuVnNiRHRqYjI1emRDQnFQ'
    || 'VFk0TUN4VFBUSTJMRkU5TXl4U1BURXpNQ3hJUFdvdFVpMDNNQ3hsWlQxNExteGxibWQwYUNvb1V5dFJLU3N5T0N4aVBVMWhkR2d1YldGNEtERXdNQ3d1TGk1'
    || 'NExtMWhjQ2gwWlQwK1FTaDBaUzVHUVZaUFZWSkJRa3hGWDFOSVFWSkZLU294TURBcExDNHVMbmd1YldGd0tIUmxQVDVCS0hSbExsVlVTVXhKVTBGVVNVOU9L'
    || 'U294TURBcEtTeEtQWFJsUFQ1MFpTOWlLa2dzUnoxU0swb29iU2s3Y21WMGRYSnVJRzh1YW5ONEtFeGxMSHQwYVhSc1pUb2lRbkpsWVdzdFpYWmxiaUJqYUdG'
    || 'eWRDSXNkMmxrWlRvaE1DeG9hVzUwT21CRllXTm9JR0poY2lCemFHOTNjeUJtWVhadmRYSmhZbXhsSUhOb1lYSmxJQ2h6WTJGdUwwUk5UQ0IzYjNKcklFZGxi'
    || 'aklnYVcxd2NtOTJaWE1wSUdGbllXbHVjM1FnZEdobElDUjdiUzUwYjBacGVHVmtLREFwZlNVZ1luSmxZV3N0WlhabGJpQnNhVzVsTGlCQ1lYSnpJSEJoYzNR'
    || 'Z2RHaGxJR3hwYm1VZ1lYSmxJR052Ym5abGNuTnBiMjRnWTJGdVpHbGtZWFJsY3k1Z0xHTm9hV3hrY21WdU9tOHVhbk40S0VsbExIdHdZVzVsYkRwMUxuQmhi'
    || 'bVZzY3k1blpXNHlMR05vYVd4a2NtVnVPbTh1YW5ONGN5Z2laR2wySWl4N2MzUjViR1U2ZTNCdmMybDBhVzl1T2lKeVpXeGhkR2wyWlNKOUxHTm9hV3hrY21W'
    || 'dU9sdHZMbXB6ZUhNb0luTjJaeUlzZTNacFpYZENiM2c2WURBZ01DQWtlMnA5SUNSN1pXVjlZQ3gzYVdSMGFEb2lNVEF3SlNJc2MzUjViR1U2ZTIxaGVGZHBa'
    || 'SFJvT21vc1pHbHpjR3hoZVRvaVlteHZZMnNpZlN4dmJrMXZkWE5sVEdWaGRtVTZLQ2s5UGxRb2JuVnNiQ2tzWTJocGJHUnlaVzQ2VzI4dWFuTjRLQ0pzYVc1'
    || 'bElpeDdlREU2Unl4NU1Ub3dMSGd5T2tjc2VUSTZaV1V0TVRnc2MzUnliMnRsT2lKMllYSW9MUzFrYVcwcElpeHpkSEp2YTJWWGFXUjBhRG94TEhOMGNtOXJa'
    || 'VVJoYzJoaGNuSmhlVG9pTkN3ekluMHBMRzh1YW5ONGN5Z2lkR1Y0ZENJc2UzZzZSeXg1T21WbExUUXNkR1Y0ZEVGdVkyaHZjam9pYldsa1pHeGxJaXh6ZEhs'
    || 'c1pUcDdabTl1ZEZOcGVtVTZNVEVzWm1sc2JEb2lkbUZ5S0MwdFpHbHRLU0o5TEdOb2FXeGtjbVZ1T2x0dExuUnZSbWw0WldRb01Da3NJaVVnWW5KbFlXc3Ra'
    || 'WFpsYmlKZGZTa3NlQzV0WVhBb0tIUmxMRk5sS1QwK2UyTnZibk4wSUVJOVUyVXFLRk1yVVNrc1N6MUJLSFJsTGtaQlZrOVZVa0ZDVEVWZlUwaEJVa1VwS2pF'
    || 'd01DeHFaVDFCS0hSbExsVlVTVXhKVTBGVVNVOU9LU294TURBc1lXVTlVM1J5YVc1bktIUmxMbFpGVWtSSlExUXBMR05sUFVGeVcyRmxYU3huWlQxalpUMDlQ'
    || 'U0puYjI5a0lqOGlkbUZ5S0MwdFoyOXZaQ2tpT21ObFBUMDlJbUpoWkNJL0luWmhjaWd0TFdKaFpDa2lPbU5sUFQwOUluZGhjbTRpUHlKMllYSW9MUzEzWVhK'
    || 'dUtTSTZJblpoY2lndExXUnBiU2tpTzNKbGRIVnliaUJ2TG1wemVITW9JbWNpTEh0amFHbHNaSEpsYmpwYmJ5NXFjM2dvSW5SbGVIUWlMSHQ0T2xJdE5peDVP'
    || 'a0lyVXk4eUt6UXNkR1Y0ZEVGdVkyaHZjam9pWlc1a0lpeHpkSGxzWlRwN1ptOXVkRk5wZW1VNk1URXNabWxzYkRvaWRtRnlLQzB0ZEdWNGRDMHhLU0o5TEdO'
    || 'b2FXeGtjbVZ1T2xOMGNtbHVaeWgwWlM1WFFWSkZTRTlWVTBWZlRrRk5SU2t1YzJ4cFkyVW9NQ3d4TmlsOUtTeHZMbXB6ZUNnaWNtVmpkQ0lzZTNnNlVpeDVP'
    || 'a0lyTWl4M2FXUjBhRHBLS0dwbEtTeG9aV2xuYUhRNlV5MDBMR1pwYkd3NkluWmhjaWd0TFhOMWNtWmhZMlV0TXlraUxISjRPako5S1N4dkxtcHplQ2dpY21W'
    || 'amRDSXNlM2c2VWl4NU9rSXJOQ3gzYVdSMGFEcEtLRXNwTEdobGFXZG9kRHBUTFRnc1ptbHNiRHBuWlN4dmNHRmphWFI1T2k0NE5TeHllRG95TEc5dVRXOTFj'
    || 'MlZOYjNabE9tOWxQVDVVS0h0NE9tOWxMbU5zYVdWdWRGZ3NlVHB2WlM1amJHbGxiblJaTEhJNmRHVXNabUYyT2tzc2RYUnBiRHBxWlN4MlpYSmthV04wT21G'
    || 'bGZTa3NiMjVOYjNWelpVeGxZWFpsT2lncFBUNVVLRzUxYkd3cExITjBlV3hsT250amRYSnpiM0k2SW1SbFptRjFiSFFpZlgwcExHOHVhbk40Y3lnaWRHVjRk'
    || 'Q0lzZTNnNmFpMDBMSGs2UWl0VEx6SXJOQ3gwWlhoMFFXNWphRzl5T2lKbGJtUWlMSE4wZVd4bE9udG1iMjUwVTJsNlpUb3hNU3htYVd4c09pSjJZWElvTFMx'
    || 'a2FXMHBJbjBzWTJocGJHUnlaVzQ2VzFVb1RXRjBhQzV5YjNWdVpDaEJLSFJsTGtOU1JVUkpWRk5mVUVWU1gwUkJXU2txTVRBcEx6RXdLU3dpTDJRaVhYMHBY'
    || 'WDBzVTJVcGZTbGRmU2tzYnk1cWMzZ29iWE1zZTNnNktFVTlQVzUxYkd3L2RtOXBaQ0F3T2tVdWVDay9QekFzZVRvb1JUMDliblZzYkQ5MmIybGtJREE2UlM1'
    || 'NUtUOC9NQ3gyYVhOcFlteGxPa1VoUFc1MWJHd3NZMmhwYkdSeVpXNDZSU1ltYnk1cWMzaHpLQ0prYVhZaUxIdHpkSGxzWlRwN1ptOXVkRk5wZW1VNk1USXNi'
    || 'R2x1WlVobGFXZG9kRG94TGpZc2JXbHVWMmxrZEdnNk1UZ3dmU3hqYUdsc1pISmxianBiYnk1cWMzZ29JbVJwZGlJc2UzTjBlV3hsT250bWIyNTBWMlZwWjJo'
    || 'ME9qWXdNQ3h0WVhKbmFXNUNiM1IwYjIwNk1uMHNZMmhwYkdSeVpXNDZVM1J5YVc1bktFVXVjaTVYUVZKRlNFOVZVMFZmVGtGTlJTbDlLU3h2TG1wemVITW9J'
    || 'bVJwZGlJc2UyTm9hV3hrY21WdU9sdHZMbXB6ZUNnaWMzQmhiaUlzZTNOMGVXeGxPbnRqYjJ4dmNqb2lkbUZ5S0MwdFpHbHRLU0o5TEdOb2FXeGtjbVZ1T2lK'
    || 'R1lYWnZkWEpoWW14bElITm9ZWEpsSUNKOUtTeEZMbVpoZGk1MGIwWnBlR1ZrS0RFcExDSWxJbDE5S1N4dkxtcHplSE1vSW1ScGRpSXNlMk5vYVd4a2NtVnVP'
    || 'bHR2TG1wemVDZ2ljM0JoYmlJc2UzTjBlV3hsT250amIyeHZjam9pZG1GeUtDMHRaR2x0S1NKOUxHTm9hV3hrY21WdU9pSlZkR2xzYVhOaGRHbHZiaUFpZlNr'
    || 'c1JTNTFkR2xzTG5SdlJtbDRaV1FvTUNrc0lpVWlYWDBwTEc4dWFuTjRjeWdpWkdsMklpeDdZMmhwYkdSeVpXNDZXMjh1YW5ONEtDSnpjR0Z1SWl4N2MzUjVi'
    || 'R1U2ZTJOdmJHOXlPaUoyWVhJb0xTMWthVzBwSW4wc1kyaHBiR1J5Wlc0NklsWmxjbVJwWTNRZ0luMHBMRVV1ZG1WeVpHbGpkQzV5WlhCc1lXTmxLQzlmTDJj'
    || 'c0lpQWlLVjE5S1N4dkxtcHplSE1vSW1ScGRpSXNlMk5vYVd4a2NtVnVPbHR2TG1wemVDZ2ljM0JoYmlJc2UzTjBlV3hsT250amIyeHZjam9pZG1GeUtDMHRa'
    || 'R2x0S1NKOUxHTm9hV3hrY21WdU9pSkRjbVZrYVhSekwyUmhlU0FpZlNrc1ZTaEZMbkl1UTFKRlJFbFVVMTlRUlZKZlJFRlpLVjE5S1N4QktFVXVjaTVSVlVW'
    || 'VlJVUmZVMFZEVDA1RVV5aytNQ1ltYnk1cWMzaHpLQ0prYVhZaUxIdGphR2xzWkhKbGJqcGJieTVxYzNnb0luTndZVzRpTEh0emRIbHNaVHA3WTI5c2IzSTZJ'
    || 'blpoY2lndExXUnBiU2tpZlN4amFHbHNaSEpsYmpvaVVYVmxkV1ZrSUNKOUtTeFZLRVV1Y2k1UlZVVlZSVVJmVTBWRFQwNUVVeWtzSW5NaVhYMHBMRUVvUlM1'
    || 'eUxsTlFTVXhNWDBkQ0tUNHdKaVp2TG1wemVITW9JbVJwZGlJc2UyTm9hV3hrY21WdU9sdHZMbXB6ZUNnaWMzQmhiaUlzZTNOMGVXeGxPbnRqYjJ4dmNqb2lk'
    || 'bUZ5S0MwdFpHbHRLU0o5TEdOb2FXeGtjbVZ1T2lKVGNHbHNiQ0FpZlNrc1ZTaEZMbkl1VTFCSlRFeGZSMElwTENJZ1IwSWlYWDBwTEVFb1JTNXlMbEZWUlZK'
    || 'WlgwTlBWVTVVS1Q0d0ppWnZMbXB6ZUhNb0ltUnBkaUlzZTJOb2FXeGtjbVZ1T2x0dkxtcHplQ2dpYzNCaGJpSXNlM04wZVd4bE9udGpiMnh2Y2pvaWRtRnlL'
    || 'QzB0WkdsdEtTSjlMR05vYVd4a2NtVnVPaUpSZFdWeWFXVnpJQ0o5S1N4VktFVXVjaTVSVlVWU1dWOURUMVZPVkNsZGZTa3NSUzV5TGxkSVdTWW1ieTVxYzNn'
    || 'b0ltUnBkaUlzZTNOMGVXeGxPbnR0WVhKbmFXNVViM0E2TkN4amIyeHZjam9pZG1GeUtDMHRaR2x0S1NKOUxHTm9hV3hrY21WdU9sTjBjbWx1WnloRkxuSXVW'
    || 'MGhaS1gwcFhYMHBmU2xkZlNsOUtYMHBmV1oxYm1OMGFXOXVJR0pqS0h0d09uVjlLWHRqYjI1emRDQmpQVU5sS0hVc0ltOTFkR052YldVaUtTeGhQVU5sS0hV'
    || 'c0luZGhkR05vSWlrc1cyMHNSVjA5Y1dVdWRYTmxVM1JoZEdVb2JuVnNiQ2s3YVdZb0lXTXViR1Z1WjNSb0tYSmxkSFZ5YmlCdkxtcHplQ2hNWlN4N2RHbDBi'
    || 'R1U2SWtOdmJuWmxjbk5wYjI0Z2RHbHRaV3hwYm1VaUxIZHBaR1U2SVRBc1kyaHBiR1J5Wlc0NmJ5NXFjM2dvSW5BaUxIdGpiR0Z6YzA1aGJXVTZJbTExZEdW'
    || 'a0lpeHpkSGxzWlRwN1ptOXVkRk5wZW1VNk1USjlMR05vYVd4a2NtVnVPaUpPYjNSb2FXNW5JR052Ym5abGNuUmxaQ0I1WlhRZzRvQ1VJSFJvWlNCMGFXMWxi'
    || 'R2x1WlNCaVpXZHBibk1nZDJobGJpQmhJSGRoY21Wb2IzVnpaU0JwY3lCamFHRnVaMlZrTGlKOUtYMHBPMk52Ym5OMElGUTlibVYzSUUxaGNEdG1iM0lvWTI5'
    || 'dWMzUWdRaUJ2WmlCaktYdGpiMjV6ZENCTFBWTjBjbWx1WnloQ0xsZEJVa1ZJVDFWVFJWOU9RVTFGS1R0VUxtaGhjeWhMS1h4OFZDNXpaWFFvU3l4YlhTa3NW'
    || 'QzVuWlhRb1N5a3VjSFZ6YUNoN2QyZzZTeXhrWVhSbE9sTjBjbWx1WnloQ0xrTklRVTVIUlVSZlFWUS9QeUlpS1M1emJHbGpaU2d3TERFd0tTeHZkWFJqYjIx'
    || 'bE9sTjBjbWx1WnloQ0xrOVZWRU5QVFVVcExITnZkWEpqWlRvaVkyOXVkbVZ5YzJsdmJpSXNjM0JsWldSMWNEcEJLRUl1VDBKVFJWSldSVVJmVTFCRlJVUlZV'
    || 'RjlRUTFRcExISmxjWFZwY21Wa09rRW9RaTVTUlZGVlNWSkZSRjlUVUVWRlJGVlFYMUJEVkNrc1ltVm1iM0psUTNJNlFTaENMa0pGUms5U1JWOURVa1ZFU1ZS'
    || 'VFgxQkZVbDlFUVZrcExHRm1kR1Z5UTNJNlFTaENMa0ZHVkVWU1gwTlNSVVJKVkZOZlVFVlNYMFJCV1Nrc1pHVnNkR0ZEY2pwQktFSXVUMEpUUlZKV1JVUmZS'
    || 'RVZNVkVGZlExSkZSRWxVVTE5UVJWSmZSRUZaS1N4a1lYbHpPa0VvUWk1RVFWbFRYMDlDVTBWU1ZrVkVLU3hpWldadmNtVlRaV002UVNoQ0xrSkZSazlTUlY5'
    || 'VFJVTlBUa1JUWDFCRlVsOVJWVVZTV1Nrc1lXWjBaWEpUWldNNlFTaENMa0ZHVkVWU1gxTkZRMDlPUkZOZlVFVlNYMUZWUlZKWktYMHBmV1p2Y2loamIyNXpk'
    || 'Q0JDSUc5bUlHRXBlMk52Ym5OMElFczlVM1J5YVc1bktFSXVWMEZTUlVoUFZWTkZYMDVCVFVVcE8xUXVhR0Z6S0VzcGZIeFVMbk5sZENoTExGdGRLU3hVTG1k'
    || 'bGRDaExLUzV3ZFhOb0tIdDNhRHBMTEdSaGRHVTZVM1J5YVc1bktFSXVRMGhGUTB0RlJGOUJWRDgvSWlJcExuTnNhV05sS0RBc01UQXBMRzkxZEdOdmJXVTZV'
    || 'M1J5YVc1bktFSXVUMVZVUTA5TlJTa3NjMjkxY21ObE9pSjNZWFJqYUNJc2MzQmxaV1IxY0RwQktFSXVUMEpUUlZKV1JVUmZVMUJGUlVSVlVGOVFRMVFwTEhK'
    || 'bGNYVnBjbVZrT2tFb1FpNVNSVkZWU1ZKRlJGOVRVRVZGUkZWUVgxQkRWQ2tzWW1WbWIzSmxRM0k2UVNoQ0xrSkZSazlTUlY5RFVrVkVTVlJUWDFCRlVsOUVR'
    || 'VmtwTEdGbWRHVnlRM0k2UVNoQ0xrRkdWRVZTWDBOU1JVUkpWRk5mVUVWU1gwUkJXU2tzWkdGNWN6cEJLRUl1UkVGWlUxOVBRbE5GVWxaRlJDbDlLWDFqYjI1'
    || 'emRDQjRQVnN1TGk1VUxtVnVkSEpwWlhNb0tWMHNhajE0TG1ac1lYUk5ZWEFvS0Zzc1FsMHBQVDVDTG0xaGNDaExQVDVMTG1SaGRHVXBLUzVtYVd4MFpYSW9R'
    || 'bTl2YkdWaGJpa3VjMjl5ZENncE8ybG1LQ0ZxTG14bGJtZDBhQ2x5WlhSMWNtNGdiblZzYkR0amIyNXpkQ0JUUFdwYk1GMHNVVDFxVzJvdWJHVnVaM1JvTFRG'
    || 'ZExGSTlOamd3TEhvOU1qUXNTRDAwTEdWbFBURXpNQ3hpUFRFMkxFbzlVaTFsWlMxaUxFYzllQzVzWlc1bmRHZ3FLSG9yU0Nrck1qUXNkR1U5UWowK2UyTnZi'
    || 'bk4wSUVzOWJtVjNJRVJoZEdVb1V5a3VaMlYwVkdsdFpTZ3BMR0ZsUFc1bGR5QkVZWFJsS0ZFcExtZGxkRlJwYldVb0tTMUxmSHd4TzNKbGRIVnliaUJsWlNz'
    || 'b2JtVjNJRVJoZEdVb1Fpa3VaMlYwVkdsdFpTZ3BMVXNwTDJGbEtrcDlMRk5sUFh0RFQxTlVTVTVIWDB4RlUxTTZJblpoY2lndExXZHZiMlFwSWl4RFQxTlVT'
    || 'VTVIWDAxUFVrVTZJblpoY2lndExXSmhaQ2tpTEU1UFgwMUJWRVZTU1VGTVgwTklRVTVIUlRvaWRtRnlLQzB0ZDJGeWJpa2lMRlJQVDE5RlFWSk1XVG9pZG1G'
    || 'eUtDMHRaR2x0S1NKOU8zSmxkSFZ5YmlCdkxtcHplSE1vVEdVc2UzUnBkR3hsT2lKRGIyNTJaWEp6YVc5dUlIUnBiV1ZzYVc1bElpeDNhV1JsT2lFd0xHaHBi'
    || 'blE2SWtWaFkyZ2daRzkwSUdseklHRWdiV1ZoYzNWeVpXMWxiblE2SUhSb1pTQmpiMjUyWlhKemFXOXVJR1YyWlc1MElHOXlJR0VnZDJWbGEyeDVJSEpsTFdO'
    || 'b1pXTnJMaUJEYjJ4dmRYSWdjMmh2ZDNNZ2RHaGxJRzkxZEdOdmJXVWdZWFFnZEdoaGRDQndiMmx1ZEM0aUxHTm9hV3hrY21WdU9sdHZMbXB6ZUhNb1NXVXNl'
    || 'M0JoYm1Wc09uVXVjR0Z1Wld4ekxtOTFkR052YldVc1kyaHBiR1J5Wlc0NlcyOHVhbk40Y3lnaVpHbDJJaXg3YzNSNWJHVTZlM0J2YzJsMGFXOXVPaUp5Wld4'
    || 'aGRHbDJaU0o5TEdOb2FXeGtjbVZ1T2x0dkxtcHplSE1vSW5OMlp5SXNlM1pwWlhkQ2IzZzZZREFnTUNBa2UxSjlJQ1I3UjMxZ0xIZHBaSFJvT2lJeE1EQWxJ'
    || 'aXh6ZEhsc1pUcDdiV0Y0VjJsa2RHZzZVaXhrYVhOd2JHRjVPaUppYkc5amF5SjlMRzl1VFc5MWMyVk1aV0YyWlRvb0tUMCtSU2h1ZFd4c0tTeGphR2xzWkhK'
    || 'bGJqcGJlQzV0WVhBb0tGdENMRXRkTEdwbEtUMCtlMk52Ym5OMElHRmxQV3BsS2loNkswZ3BLM292TWl4alpUMWJMaTR1UzEwdWMyOXlkQ2dvWjJVc2IyVXBQ'
    || 'VDVuWlM1a1lYUmxMbXh2WTJGc1pVTnZiWEJoY21Vb2IyVXVaR0YwWlNrcE8zSmxkSFZ5YmlCdkxtcHplSE1vSW1jaUxIdGphR2xzWkhKbGJqcGJieTVxYzNn'
    || 'b0luUmxlSFFpTEh0NE9tVmxMVFlzZVRwaFpTczBMSFJsZUhSQmJtTm9iM0k2SW1WdVpDSXNjM1I1YkdVNmUyWnZiblJUYVhwbE9qRXhMR1pwYkd3NkluWmhj'
    || 'aWd0TFhSbGVIUXRNU2tpZlN4amFHbHNaSEpsYmpwQ0xuTnNhV05sS0RBc01UWXBmU2tzWTJVdWJHVnVaM1JvUGpFbUptOHVhbk40S0NKc2FXNWxJaXg3ZURF'
    || 'NmRHVW9ZMlZiTUYwdVpHRjBaU2tzZVRFNllXVXNlREk2ZEdVb1kyVmJZMlV1YkdWdVozUm9MVEZkTG1SaGRHVXBMSGt5T21GbExITjBjbTlyWlRvaWRtRnlL'
    || 'QzB0YkdsdVpTMHlLU0lzYzNSeWIydGxWMmxrZEdnNk1YMHBMR05sTG0xaGNDZ29aMlVzYjJVcFBUNXZMbXB6ZUNnaVkybHlZMnhsSWl4N1kzZzZkR1VvWjJV'
    || 'dVpHRjBaU2tzWTNrNllXVXNjanB2WlQwOVBUQS9OVG8wTEdacGJHdzZVMlZiWjJVdWIzVjBZMjl0WlYwL1B5SjJZWElvTFMxa2FXMHBJaXh6ZEhKdmEyVTZJ'
    || 'blpoY2lndExYTjFjbVpoWTJVcElpeHpkSEp2YTJWWGFXUjBhRG94TEhOMGVXeGxPbnRqZFhKemIzSTZJbVJsWm1GMWJIUWlmU3h2YmsxdmRYTmxUVzkyWlRw'
    || 'c2REMCtSU2g3ZURwc2RDNWpiR2xsYm5SWUxIazZiSFF1WTJ4cFpXNTBXU3hsZGpwblpYMHBMRzl1VFc5MWMyVk1aV0YyWlRvb0tUMCtSU2h1ZFd4c0tYMHNi'
    || 'MlVwS1YxOUxFSXBmU2tzYnk1cWMzZ29JblJsZUhRaUxIdDRPbVZsTEhrNlJ5MDBMSE4wZVd4bE9udG1iMjUwVTJsNlpUb3hNU3htYVd4c09pSjJZWElvTFMx'
    || 'a2FXMHBJbjBzWTJocGJHUnlaVzQ2VTMwcExHOHVhbk40S0NKMFpYaDBJaXg3ZURwU0xXSXNlVHBITFRRc2RHVjRkRUZ1WTJodmNqb2laVzVrSWl4emRIbHNa'
    || 'VHA3Wm05dWRGTnBlbVU2TVRFc1ptbHNiRG9pZG1GeUtDMHRaR2x0S1NKOUxHTm9hV3hrY21WdU9sRjlLVjE5S1N4dkxtcHplQ2h0Y3l4N2VEb29iVDA5Ym5W'
    || 'c2JEOTJiMmxrSURBNmJTNTRLVDgvTUN4NU9paHRQVDF1ZFd4c1AzWnZhV1FnTURwdExua3BQejh3TEhacGMybGliR1U2YlNFOWJuVnNiQ3hqYUdsc1pISmxi'
    || 'anB0SmladkxtcHplSE1vSW1ScGRpSXNlM04wZVd4bE9udG1iMjUwVTJsNlpUb3hNaXhzYVc1bFNHVnBaMmgwT2pFdU5peHRhVzVYYVdSMGFEb3hPREFzYldG'
    || 'NFYybGtkR2c2TWpnd2ZTeGphR2xzWkhKbGJqcGJieTVxYzNnb0ltUnBkaUlzZTNOMGVXeGxPbnRtYjI1MFYyVnBaMmgwT2pZd01DeHRZWEpuYVc1Q2IzUjBi'
    || 'MjA2TW4wc1kyaHBiR1J5Wlc0NmJTNWxkaTUzYUgwcExHOHVhbk40Y3lnaVpHbDJJaXg3WTJocGJHUnlaVzQ2VzI4dWFuTjRjeWdpYzNCaGJpSXNlM04wZVd4'
    || 'bE9udGpiMnh2Y2pvaWRtRnlLQzB0WkdsdEtTSjlMR05vYVd4a2NtVnVPbHR0TG1WMkxuTnZkWEpqWlQwOVBTSmpiMjUyWlhKemFXOXVJajhpUTI5dWRtVnlk'
    || 'R1ZrSWpvaVVtVXRZMmhsWTJ0bFpDSXNJaUFpWFgwcExHMHVaWFl1WkdGMFpWMTlLU3h2TG1wemVITW9JbVJwZGlJc2UyTm9hV3hrY21WdU9sdHZMbXB6ZUNn'
    || 'aWMzQmhiaUlzZTNOMGVXeGxPbnRqYjJ4dmNqb2lkbUZ5S0MwdFpHbHRLU0o5TEdOb2FXeGtjbVZ1T2lKUGRYUmpiMjFsSUNKOUtTeHRMbVYyTG05MWRHTnZi'
    || 'V1V1Y21Wd2JHRmpaU2d2WHk5bkxDSWdJaWxkZlNrc2JTNWxkaTVrWVhseklUMXVkV3hzSmladExtVjJMbVJoZVhNK01DWW1ieTVxYzNoektDSmthWFlpTEh0'
    || 'amFHbHNaSEpsYmpwYmJ5NXFjM2dvSW5Od1lXNGlMSHR6ZEhsc1pUcDdZMjlzYjNJNkluWmhjaWd0TFdScGJTa2lmU3hqYUdsc1pISmxiam9pUkdGNWN5QnZZ'
    || 'bk5sY25abFpDQWlmU2tzYlM1bGRpNWtZWGx6WFgwcExHMHVaWFl1YzNCbFpXUjFjQ0U5Ym5Wc2JDWW1iUzVsZGk1emNHVmxaSFZ3UGpBbUptOHVhbk40Y3ln'
    || 'aVpHbDJJaXg3WTJocGJHUnlaVzQ2VzI4dWFuTjRLQ0p6Y0dGdUlpeDdjM1I1YkdVNmUyTnZiRzl5T2lKMllYSW9MUzFrYVcwcEluMHNZMmhwYkdSeVpXNDZJ'
    || 'bE53WldWa2RYQWdZV05vYVdWMlpXUWdJbjBwTEcwdVpYWXVjM0JsWldSMWNDNTBiMFpwZUdWa0tERXBMQ0lsSWwxOUtTeHRMbVYyTG5KbGNYVnBjbVZrSVQx'
    || 'dWRXeHNKaVp0TG1WMkxuSmxjWFZwY21Wa1BqQW1KbTh1YW5ONGN5Z2laR2wySWl4N1kyaHBiR1J5Wlc0NlcyOHVhbk40S0NKemNHRnVJaXg3YzNSNWJHVTZl'
    || 'Mk52Ykc5eU9pSjJZWElvTFMxa2FXMHBJbjBzWTJocGJHUnlaVzQ2SWs1bFpXUmxaQ0FpZlNrc2JTNWxkaTV5WlhGMWFYSmxaQzUwYjBacGVHVmtLREVwTENJ'
    || 'bElsMTlLU3h0TG1WMkxtSmxabTl5WlVOeUlUMXVkV3hzSmladExtVjJMbUpsWm05eVpVTnlQakFtSm04dWFuTjRjeWdpWkdsMklpeDdZMmhwYkdSeVpXNDZX'
    || 'Mjh1YW5ONEtDSnpjR0Z1SWl4N2MzUjViR1U2ZTJOdmJHOXlPaUoyWVhJb0xTMWthVzBwSW4wc1kyaHBiR1J5Wlc0NklrSmxabTl5WlNBaWZTa3NWU2h0TG1W'
    || 'MkxtSmxabTl5WlVOeUtTd2lJR055TDJSaGVTSmRmU2tzYlM1bGRpNWhablJsY2tOeUlUMXVkV3hzSmladExtVjJMbUZtZEdWeVEzSStNQ1ltYnk1cWMzaHpL'
    || 'Q0prYVhZaUxIdGphR2xzWkhKbGJqcGJieTVxYzNnb0luTndZVzRpTEh0emRIbHNaVHA3WTI5c2IzSTZJblpoY2lndExXUnBiU2tpZlN4amFHbHNaSEpsYmpv'
    || 'aVFXWjBaWElnSW4wcExGVW9iUzVsZGk1aFpuUmxja055S1N3aUlHTnlMMlJoZVNKZGZTa3NiUzVsZGk1a1pXeDBZVU55SVQxdWRXeHNKaVp0TG1WMkxtUmxi'
    || 'SFJoUTNJaFBUMHdKaVp2TG1wemVITW9JbVJwZGlJc2UyTm9hV3hrY21WdU9sdHZMbXB6ZUNnaWMzQmhiaUlzZTNOMGVXeGxPbnRqYjJ4dmNqb2lkbUZ5S0Mw'
    || 'dFpHbHRLU0o5TEdOb2FXeGtjbVZ1T2lKRVpXeDBZU0FpZlNrc2J5NXFjM2h6S0NKemNHRnVJaXg3YzNSNWJHVTZlMk52Ykc5eU9tMHVaWFl1WkdWc2RHRkRj'
    || 'and3UHlKMllYSW9MUzFuYjI5a0tTSTZJblpoY2lndExXSmhaQ2tpZlN4amFHbHNaSEpsYmpwYmJTNWxkaTVrWld4MFlVTnlQakEvSWlzaU9pSWlMRlVvVFdG'
    || 'MGFDNXliM1Z1WkNodExtVjJMbVJsYkhSaFEzSXFNVEF3S1M4eE1EQXBMQ0lnWTNJdlpHRjVJbDE5S1YxOUtTeHRMbVYyTG1KbFptOXlaVk5sWXlFOWJuVnNi'
    || 'Q1ltYlM1bGRpNWlaV1p2Y21WVFpXTStNQ1ltYnk1cWMzaHpLQ0prYVhZaUxIdGphR2xzWkhKbGJqcGJieTVxYzNnb0luTndZVzRpTEh0emRIbHNaVHA3WTI5'
    || 'c2IzSTZJblpoY2lndExXUnBiU2tpZlN4amFHbHNaSEpsYmpvaVUyVmpMM0YxWlhKNUlDSjlLU3h0TG1WMkxtSmxabTl5WlZObFl5NTBiMFpwZUdWa0tESXBM'
    || 'Q0lnNG9hU0lDSXNLRzB1WlhZdVlXWjBaWEpUWldNL1B6QXBMblJ2Um1sNFpXUW9NaWxkZlNsZGZTbDlLVjE5S1N3aFlTNXNaVzVuZEdnbUptOHVhbk40S0NK'
    || 'd0lpeDdZMnhoYzNOT1lXMWxPaUp0ZFhSbFpDSXNjM1I1YkdVNmUyWnZiblJUYVhwbE9qRXlMRzFoY21kcGJsUnZjRG8wZlN4amFHbHNaSEpsYmpvaVRtOGdk'
    || 'MlZsYTJ4NUlISmxMV05vWldOcklHaGhjeUJ5ZFc0Z2VXVjBJT0tBbENCbmFYWmxJR2wwSUdFZ2QyVmxheTRpZlNsZGZTa3NieTVxYzNnb0ltUnBkaUlzZTNO'
    || 'MGVXeGxPbnRrYVhOd2JHRjVPaUptYkdWNElpeG5ZWEE2TVRJc2JXRnlaMmx1Vkc5d09qUXNabTl1ZEZOcGVtVTZNVEVzWTI5c2IzSTZJblpoY2lndExXUnBi'
    || 'U2tpZlN4amFHbHNaSEpsYmpwUFltcGxZM1F1Wlc1MGNtbGxjeWhzYVNrdWJXRndLQ2hiUWl4TFhTazlQbTh1YW5ONGN5Z2ljM0JoYmlJc2UyTm9hV3hrY21W'
    || 'dU9sdHZMbXB6ZUNnaWMzQmhiaUlzZTNOMGVXeGxPbnRrYVhOd2JHRjVPaUpwYm14cGJtVXRZbXh2WTJzaUxIZHBaSFJvT2pnc2FHVnBaMmgwT2pnc1ltOXla'
    || 'R1Z5VW1Ga2FYVnpPaUkxTUNVaUxHSmhZMnRuY205MWJtUTZVMlZiUWwwL1B5SjJZWElvTFMxa2FXMHBJaXgyWlhKMGFXTmhiRUZzYVdkdU9pSnRhV1JrYkdV'
    || 'aUxHMWhjbWRwYmxKcFoyaDBPak45ZlNrc1FpNXlaWEJzWVdObEtDOWZMMmNzSWlBaUtTNTBiMHh2ZDJWeVEyRnpaU2dwWFgwc1Fpa3BmU2xkZlNsOVpuVnVZ'
    || 'M1JwYjI0Z1pXUW9lM0E2ZFgwcGUyTnZibk4wSUdNOVEyVW9kU3dpWjJWdU1pSXBMR0U5UTJVb2RTd2laV052Ym05dGFXTnpJaWxiTUYwL1AzdDlMRzA5UVNo'
    || 'aExsSkZVVlZKVWtWRVgxTlFSVVZFVlZCZlVFTlVLU3hGUFVFb1lTNUhSVTR5WDFKQlZFVmZUVlZNVkVsUVRFbEZVaWtzVkQxakxtWnBiSFJsY2loUlBUNXhZ'
    || 'eTVwYm1Oc2RXUmxjeWhUZEhKcGJtY29VUzVXUlZKRVNVTlVLU2twTEhnOVl5NW1hV3gwWlhJb1VUMCtVM1J5YVc1bktGRXVWa1ZTUkVsRFZDazlQVDBpUVZa'
    || 'UFNVUWlLU3hxUFZRdWNtVmtkV05sS0NoUkxGSXBQVDVSSzBFb1VpNURVa1ZFU1ZSVFgxQkZVbDlFUVZrcExEQXBMRk05VkM1eVpXUjFZMlVvS0ZFc1VpazlQ'
    || 'bEVyUVNoU0xsZFBVbE5VWDBOQlUwVmZSVmhVVWtGZlExSkZSRWxVVTE5UVJWSmZSRUZaS1N3d0tUdHlaWFIxY200Z2J5NXFjM2dvVEdVc2UzUnBkR3hsT2lK'
    || 'WGFHRjBJSFJvYVhNZ1ptOTFibVFpTEhkcFpHVTZJVEFzYUdsdWREcGdSMlZ1TWlCamIzTjBjeUJ0YjNKbElIQmxjaUJ6WldOdmJtUWdkR2hoYmlCSFpXNHhM'
    || 'aUJVYUdWelpTQjNZWEpsYUc5MWMyVnpJR0Z5WlNCMGFHVWdiMjVsY3lCM2FHOXpaUW9nSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdiV1ZoYzNWeVpXUWdkMjl5YTJ4'
    || 'dllXUWdjMmhoY0dVZ2MzVm5aMlZ6ZEhNZ2RHaGxlU0IzYVd4c0lHWnBibWx6YUNCbGJtOTFaMmdnWm1GemRHVnlJSFJ2SUdOdmRtVnlDaUFnSUNBZ0lDQWdJ'
    || 'Q0FnSUNBZ0lDQjBhR0YwTGlCT2IzUm9hVzVuSUdobGNtVWdhWE1nWVNCd2NtOXFaV04wWldRZ2MyRjJhVzVuSU9LQWxDQjBhR1VnY0dsc2IzUWdhWE1nZDJo'
    || 'aGRDQndjbTlrZFdObGN5QmhDaUFnSUNBZ0lDQWdJQ0FnSUNBZ0lDQnVkVzFpWlhJZ2VXOTFJR05oYmlCeGRXOTBaUzVnTEdOb2FXeGtjbVZ1T204dWFuTjRj'
    || 'eWhKWlN4N2NHRnVaV3c2ZFM1d1lXNWxiSE11WjJWdU1peGphR2xzWkhKbGJqcGJieTVxYzNoektDSmthWFlpTEh0amJHRnpjMDVoYldVNkluTjBZWFF0Y205'
    || 'M0lpeGphR2xzWkhKbGJqcGJieTVxYzNnb2VtVXNlMnhoWW1Wc09pSlhiM0owYUNCamIyNTJaWEowYVc1bklpeDJZV3gxWlRwVUxteGxibWQwYUN4MGIyNWxP'
    || 'bFF1YkdWdVozUm9QeUpuYjI5a0lqcDJiMmxrSURBc2MzVmlPbUJ2WmlBa2UyTXViR1Z1WjNSb2ZTQjNZWEpsYUc5MWMyVnpJR2x1SUhSb1pTQm1iR1ZsZEdC'
    || 'OUtTeHZMbXB6ZUNoNlpTeDdiR0ZpWld3NklsZHZkV3hrSUdOdmMzUWdlVzkxSUcxdmJtVjVJaXgyWVd4MVpUcDRMbXhsYm1kMGFDeDBiMjVsT25ndWJHVnVa'
    || 'M1JvUHlKaVlXUWlPaUpuYjI5a0lpeHpkV0k2SWtGV1QwbEVJT0tBbENCdGIzTjBiSGtnYVdSc1pTd2diM0lnZEc5dklHeHBkSFJzWlNCelkyRnVJR0Z1WkNC'
    || 'RVRVd2dkMjl5YXlKOUtTeHZMbXB6ZUNoNlpTeDdiR0ZpWld3NklrTnlaV1JwZEhNdlpHRjVJR0YwSUhOMFlXdGxJaXgyWVd4MVpUcFZLRTFoZEdndWNtOTFi'
    || 'bVFvYWlveE1Da3ZNVEFwTEhOMVlqb2lZM1Z5Y21WdWRDQnpjR1Z1WkNCdmJpQjBhR1VnZDJGeVpXaHZkWE5sY3lCM2IzSjBhQ0JqYjI1MlpYSjBhVzVuSW4w'
    || 'cExHOHVhbk40S0hwbExIdHNZV0psYkRvaVRYVnpkQ0JtYVc1cGMyZ2dabUZ6ZEdWeUlHSjVJaXgyWVd4MVpUcHRQMkFrZTIxOUpXQTZJdUtBbENJc2MzVmlP'
    || 'a1UvWUdKeVpXRnJMV1YyWlc0Z1lYUWdkR2hsSUNSN1JYMTRJRWRsYmpJZ2NtRjBaV0E2SW5KaGRHVWdkVzV5WlhOdmJIWmxaQ0o5S1YxOUtTeHZMbXB6ZUhN'
    || 'b1RISXNlM1JwZEd4bE9pSlNaV0ZrSUhSb1pTQmtiM2R1YzJsa1pTQmlaV1p2Y21VZ2NISmxjM05wYm1jZ1lXNTVkR2hwYm1jaUxHTm9hV3hrY21WdU9sc2lT'
    || 'V1lnUjJWdU1pQmtaV3hwZG1WeWN5QnVieUJ6Y0dWbFpIVndMQ0IwYUdWelpTQjNZWEpsYUc5MWMyVnpJR0ZrWkNCK0lpeFZLRTFoZEdndWNtOTFibVFvVXlv'
    || 'eE1EQXBMekV3TUNrc0lpQmpjbVZrYVhSekwyUmhlU0RpZ0pRZ2RHaGxJSEpoZEdVZ2NISmxiV2wxYlNCdmJpQmpkWEp5Wlc1MElITndaVzVrTGlKZGZTbGRm'
    || 'U2w5S1gxbWRXNWpkR2x2YmlCMFpDaDdjRHAxZlNsN1kyOXVjM1FnWXoxRFpTaDFMQ0psWTI5dWIyMXBZM01pS1Zzd1hUOC9lMzA3Y21WMGRYSnVJRzh1YW5O'
    || 'NEtFeGxMSHQwYVhSc1pUb2lWR2hsSUdGeWFYUm9iV1YwYVdNZ1pYWmxjbmtnZG1WeVpHbGpkQ0JwY3lCcWRXUm5aV1FnWVdkaGFXNXpkQ0lzZDJsa1pUb2hN'
    || 'Q3hvYVc1ME9pSlBibVVnY205M0xDQmhibVFnWlhabGNubDBhR2x1WnlCbGJITmxJRzl1SUhSb2FYTWdjR0ZuWlNCa1pYSnBkbVZ6SUdaeWIyMGdhWFF1SWl4'
    || 'amFHbHNaSEpsYmpwdkxtcHplSE1vU1dVc2UzQmhibVZzT25VdWNHRnVaV3h6TG1WamIyNXZiV2xqY3l4amFHbHNaSEpsYmpwYmJ5NXFjM2h6S0NKa2FYWWlM'
    || 'SHRqYkdGemMwNWhiV1U2SW5OMFlYUXRjbTkzSWl4amFHbHNaSEpsYmpwYmJ5NXFjM2dvZW1Vc2UyeGhZbVZzT2lKRGJHOTFaQ0lzZG1Gc2RXVTZVM1J5YVc1'
    || 'bktHTXVRMHhQVlVRL1B5TGlnSlFpS1N4emRXSTZVM1J5YVc1bktHTXVVa1ZIU1U5T1B6OGlJaWw5S1N4dkxtcHplQ2g2WlN4N2JHRmlaV3c2SWtkbGJqSWdj'
    || 'bUYwWlNJc2RtRnNkV1U2WUNSN1FTaGpMa2RGVGpKZlVrRlVSVjlOVlV4VVNWQk1TVVZTS1gxNFlDeHpkV0k2SW1OeVpXUnBkSE1nY0dWeUlHaHZkWElzSUha'
    || 'bGNuTjFjeUJIWlc0eElHRjBJSFJvWlNCellXMWxJSE5wZW1VaWZTa3NieTVxYzNnb2VtVXNlMnhoWW1Wc09pSkNjbVZoYXkxbGRtVnVJSE53WldWa2RYQWlM'
    || 'SFpoYkhWbE9tQWtlMEVvWXk1U1JWRlZTVkpGUkY5VFVFVkZSRlZRWDFCRFZDbDlKV0FzYzNWaU9pSXhJQzBnTVM5dGRXeDBhWEJzYVdWeUxDQnpieUIwYUds'
    || 'eklHbHpJR0Z5YVhSb2JXVjBhV01nYm05MElHRnVJR1Z6ZEdsdFlYUmxJbjBwWFgwcExHOHVhbk40Y3loRmJpeDdZMmhwYkdSeVpXNDZXMU4wY21sdVp5aGpM'
    || 'a2hQVjE5VVQxOVNSVUZFWDBsVVB6OGlJaWtzSWlCVGIzVnlZMlVnYjJZZ2RHaGxJRzExYkhScGNHeHBaWEk2SWl3aUlDSXNVM1J5YVc1bktHTXVUVlZNVkVs'
    || 'UVRFbEZVbDlUVDFWU1EwVS9QeUoxYm10dWIzZHVJaWtzSWk0Z1ZHaGxJSEIxWW14cGMyaGxaQ0J5WVhSbGN5QnNhWFpsSUdsdUlIUm9aU0JUYm05M1pteGhh'
    || 'MlVnVTJWeWRtbGpaU0JEYjI1emRXMXdkR2x2YmlCVVlXSnNaU0J5WVhSb1pYSWdkR2hoYmlCaGJubDNhR1Z5WlNCeGRXVnllV0ZpYkdVc0lITnZJR2xtSUhs'
    || 'dmRYSWdZMjl1ZEhKaFkzUmxaQ0JtYVdkMWNtVWdaR2xtWm1WeWN5d2djMlYwSUZkSVIwVk9YMUpCVkVWZlRWVk1WRWxRVEVsRlVpQmhibVFnY21VdGNuVnVJ'
    || 'T0tBbENCbGRtVnllU0IyWlhKa2FXTjBJSEpsTFdSbGNtbDJaWE1nWm5KdmJTQnBkQzRpWFgwcFhYMHBmU2w5Wm5WdVkzUnBiMjRnYm1Rb2UzSTZkWDBwZTJO'
    || 'dmJuTjBJR005VTNSeWFXNW5LSFV1VmtWU1JFbERWQ2tzWVQxQmNsdGpYU3h0UFc4dWFuTjRjeWdpYzNCaGJpSXNlM04wZVd4bE9udGthWE53YkdGNU9pSm1i'
    || 'R1Y0SWl4aGJHbG5ia2wwWlcxek9pSmpaVzUwWlhJaUxHZGhjRG80TEhkcFpIUm9PaUl4TURBbElpeG1iMjUwVTJsNlpUb3hNMzBzWTJocGJHUnlaVzQ2VzI4'
    || 'dWFuTjRLQ0p6Y0dGdUlpeDdjM1I1YkdVNmUyWnNaWGc2SWpBZ01DQXhNekJ3ZUNJc1ptOXVkRmRsYVdkb2REbzJNREFzYjNabGNtWnNiM2M2SW1ocFpHUmxi'
    || 'aUlzZEdWNGRFOTJaWEptYkc5M09pSmxiR3hwY0hOcGN5SXNkMmhwZEdWVGNHRmpaVG9pYm05M2NtRndJbjBzWTJocGJHUnlaVzQ2VTNSeWFXNW5LSFV1VjBG'
    || 'U1JVaFBWVk5GWDA1QlRVVXBmU2tzYnk1cWMzZ29Jbk53WVc0aUxIdHpkSGxzWlRwN1pteGxlRG9pTUNBd0lEWXdjSGdpTEdOdmJHOXlPaUoyWVhJb0xTMXRk'
    || 'WFJsWkNraWZTeGphR2xzWkhKbGJqcFRkSEpwYm1jb2RTNVhTRjlUU1ZwRktYMHBMRzh1YW5ONEtFVjBMSHQwYjI1bE9tRXNZMmhwYkdSeVpXNDZZMzBwTEc4'
    || 'dWFuTjRjeWdpYzNCaGJpSXNlM04wZVd4bE9udG1iR1Y0T2lJd0lEQWdPREJ3ZUNJc2RHVjRkRUZzYVdkdU9pSnlhV2RvZENJc1ptOXVkRlpoY21saGJuUk9k'
    || 'VzFsY21sak9pSjBZV0oxYkdGeUxXNTFiWE1pZlN4amFHbHNaSEpsYmpwYlZTaE5ZWFJvTG5KdmRXNWtLRUVvZFM1RFVrVkVTVlJUWDFCRlVsOUVRVmtwS2pF'
    || 'd01Da3ZNVEF3S1N3aUlHTnlMMlFpWFgwcExHOHVhbk40S0NKemNHRnVJaXg3YzNSNWJHVTZlMlpzWlhnNklqQWdNQ0EyTUhCNElpeDBaWGgwUVd4cFoyNDZJ'
    || 'bkpwWjJoMElpeG1iMjUwVm1GeWFXRnVkRTUxYldWeWFXTTZJblJoWW5Wc1lYSXRiblZ0Y3lJc1kyOXNiM0k2SW5aaGNpZ3RMVzExZEdWa0tTSjlMR05vYVd4'
    || 'a2NtVnVPa2x5S0hVdVZWUkpURWxUUVZSSlQwNHBmU2xkZlNrN2NtVjBkWEp1SUc4dWFuTjRjeWhhWXl4N2MzVnRiV0Z5ZVRwdExHTm9hV3hrY21WdU9sdHZM'
    || 'bXB6ZUhNb0ltUnBkaUlzZTNOMGVXeGxPbnRrYVhOd2JHRjVPaUpuY21sa0lpeG5jbWxrVkdWdGNHeGhkR1ZEYjJ4MWJXNXpPaUl4Wm5JZ01XWnlJaXhuWVhB'
    || 'NklqUndlQ0F4Tm5CNElpeG1iMjUwVTJsNlpUb3hNaXhzYVc1bFNHVnBaMmgwT2pFdU55eHdZV1JrYVc1bk9pSTBjSGdnTUNBMGNIZ2dNalJ3ZUNKOUxHTm9h'
    || 'V3hrY21WdU9sdHZMbXB6ZUhNb0ltUnBkaUlzZTJOb2FXeGtjbVZ1T2x0dkxtcHplQ2dpYzNCaGJpSXNlM04wZVd4bE9udGpiMnh2Y2pvaWRtRnlLQzB0Wkds'
    || 'dEtTSjlMR05vYVd4a2NtVnVPaUpWZEdsc2FYTmhkR2x2YmlBaWZTa3NTWElvZFM1VlZFbE1TVk5CVkVsUFRpbGRmU2tzYnk1cWMzaHpLQ0prYVhZaUxIdGph'
    || 'R2xzWkhKbGJqcGJieTVxYzNnb0luTndZVzRpTEh0emRIbHNaVHA3WTI5c2IzSTZJblpoY2lndExXUnBiU2tpZlN4amFHbHNaSEpsYmpvaVUyTmhiaTlFVFV3'
    || 'Z2MyaGhjbVVnSW4wcExFbHlLSFV1UmtGV1QxVlNRVUpNUlY5VFNFRlNSU2xkZlNrc2J5NXFjM2h6S0NKa2FYWWlMSHRqYUdsc1pISmxianBiYnk1cWMzZ29J'
    || 'bk53WVc0aUxIdHpkSGxzWlRwN1kyOXNiM0k2SW5aaGNpZ3RMV1JwYlNraWZTeGphR2xzWkhKbGJqb2lRM0psWkdsMGN5QjFjMlZrSUNKOUtTeFZLRTFoZEdn'
    || 'dWNtOTFibVFvUVNoMUxrTlNSVVJKVkZOZlZWTkZSQ2twS1YxOUtTeHZMbXB6ZUhNb0ltUnBkaUlzZTJOb2FXeGtjbVZ1T2x0dkxtcHplQ2dpYzNCaGJpSXNl'
    || 'M04wZVd4bE9udGpiMnh2Y2pvaWRtRnlLQzB0WkdsdEtTSjlMR05vYVd4a2NtVnVPaUpEY21Wa2FYUnpMMlJoZVNBaWZTa3NWU2hOWVhSb0xuSnZkVzVrS0VF'
    || 'b2RTNURVa1ZFU1ZSVFgxQkZVbDlFUVZrcEtqRXdNQ2t2TVRBd0tWMTlLU3h2TG1wemVITW9JbVJwZGlJc2UyTm9hV3hrY21WdU9sdHZMbXB6ZUNnaWMzQmhi'
    || 'aUlzZTNOMGVXeGxPbnRqYjJ4dmNqb2lkbUZ5S0MwdFpHbHRLU0o5TEdOb2FXeGtjbVZ1T2lKUmRXVnlhV1Z6SUNKOUtTeFZLRUVvZFM1UlZVVlNXVjlEVDFW'
    || 'T1ZDa3BYWDBwTEc4dWFuTjRjeWdpWkdsMklpeDdZMmhwYkdSeVpXNDZXMjh1YW5ONEtDSnpjR0Z1SWl4N2MzUjViR1U2ZTJOdmJHOXlPaUoyWVhJb0xTMWth'
    || 'VzBwSW4wc1kyaHBiR1J5Wlc0NklrZGxibVZ5WVhScGIyNGdJbjBwTEZOMGNtbHVaeWgxTGtkRlRrVlNRVlJKVDA0cGZId2k0b0NVSWwxOUtTeEJLSFV1VVZW'
    || 'RlZVVkVYMU5GUTA5T1JGTXBQakFtSm04dWFuTjRjeWdpWkdsMklpeDdZMmhwYkdSeVpXNDZXMjh1YW5ONEtDSnpjR0Z1SWl4N2MzUjViR1U2ZTJOdmJHOXlP'
    || 'aUoyWVhJb0xTMWthVzBwSW4wc1kyaHBiR1J5Wlc0NklsRjFaWFZsWkNBaWZTa3NWU2hOWVhSb0xuSnZkVzVrS0VFb2RTNVJWVVZWUlVSZlUwVkRUMDVFVXlr'
    || 'cEtTd2ljeUpkZlNrc1FTaDFMbE5RU1V4TVgwZENLVDR3SmladkxtcHplSE1vSW1ScGRpSXNlMk5vYVd4a2NtVnVPbHR2TG1wemVDZ2ljM0JoYmlJc2UzTjBl'
    || 'V3hsT250amIyeHZjam9pZG1GeUtDMHRaR2x0S1NKOUxHTm9hV3hrY21WdU9pSlRjR2xzYkNBaWZTa3NWU2hOWVhSb0xuSnZkVzVrS0VFb2RTNVRVRWxNVEY5'
    || 'SFFpa3FNVEFwTHpFd0tTd2lJRWRDSWwxOUtTeHZMbXB6ZUhNb0ltUnBkaUlzZTJOb2FXeGtjbVZ1T2x0dkxtcHplQ2dpYzNCaGJpSXNlM04wZVd4bE9udGpi'
    || 'Mnh2Y2pvaWRtRnlLQzB0WkdsdEtTSjlMR05vYVd4a2NtVnVPaUpDY21WaGF5MWxkbVZ1SUNKOUtTeEJLSFV1VWtWUlZVbFNSVVJmVTFCRlJVUlZVRjlRUTFR'
    || 'cExDSWxJbDE5S1N4QktIVXVWMDlTVTFSZlEwRlRSVjlGV0ZSU1FWOURVa1ZFU1ZSVFgxQkZVbDlFUVZrcFBqQW1KbTh1YW5ONGN5Z2laR2wySWl4N1kyaHBi'
    || 'R1J5Wlc0NlcyOHVhbk40S0NKemNHRnVJaXg3YzNSNWJHVTZlMk52Ykc5eU9pSjJZWElvTFMxa2FXMHBJbjBzWTJocGJHUnlaVzQ2SWtsbUlHNXZJSE53WldW'
    || 'a2RYQWdJbjBwTEc4dWFuTjRjeWdpYzNCaGJpSXNlM04wZVd4bE9udGpiMnh2Y2pvaWRtRnlLQzB0WW1Ga0tTSjlMR05vYVd4a2NtVnVPbHNpS3lJc1ZTaE5Z'
    || 'WFJvTG5KdmRXNWtLRUVvZFM1WFQxSlRWRjlEUVZORlgwVllWRkpCWDBOU1JVUkpWRk5mVUVWU1gwUkJXU2txTVRBd0tTOHhNREFwTENJZ1kzSXZaR0Y1SWwx'
    || 'OUtWMTlLVjE5S1N4MUxsZElXU1ltYnk1cWMzZ29JbVJwZGlJc2UzTjBlV3hsT250bWIyNTBVMmw2WlRveE1peHNhVzVsU0dWcFoyaDBPakV1Tml4d1lXUmth'
    || 'VzVuT2lJeWNIZ2dNQ0EwY0hnZ01qUndlQ0lzWTI5c2IzSTZJblpoY2lndExXMTFkR1ZrS1NKOUxHTm9hV3hrY21WdU9sTjBjbWx1WnloMUxsZElXU2w5S1Yx'
    || 'OUtYMW1kVzVqZEdsdmJpQnlaQ2g3Y0RwMWZTbDdZMjl1YzNRZ1l6MURaU2gxTENKblpXNHlJaWs3Y21WMGRYSnVJRzh1YW5ONEtFeGxMSHQwYVhSc1pUb2lS'
    || 'MlZ1TWlCMlpYSmthV04wSUhCbGNpQjNZWEpsYUc5MWMyVWlMSGRwWkdVNklUQXNhR2x1ZERwZ1ZYUnBiR2x6WVhScGIyNGdhWE1nY1hWbGNua2djMlZqYjI1'
    || 'a2N5QnZkbVZ5SUdKcGJHeGxaQ0J6WldOdmJtUnpJT0tBbENCb2IzY2diWFZqYUNCdlppQjNhR0YwSUhsdmRRb2dJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ2NHRjVJ'
    || 'R1p2Y2lCcGN5QmhZM1IxWVd4c2VTQmxlR1ZqZFhScGJtY3VJRVpoZG05MWNtRmliR1VnYzJoaGNtVWdhWE1nZEdobElIQnZjblJwYjI0Z2IyWUtJQ0FnSUNB'
    || 'Z0lDQWdJQ0FnSUNBZ0lHVjRaV04xZEdsdmJpQjBhVzFsSUhOd1pXNTBJRzl1SUhSb1pTQnpZMkZ1TFdobFlYWjVJR0Z1WkNCRVRVd2dkMjl5YXlCSFpXNHlJ'
    || 'R2x6SUdSdlkzVnRaVzUwWldRS0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnSUhSdklHbHRjSEp2ZG1VdUlFTnNhV05ySUdFZ2NtOTNJSFJ2SUhObFpTQjBhR1VnWm5W'
    || 'c2JDQmtaWFJoYVd3Z1lXNWtJSEpoZEdsdmJtRnNaUzVnTEdOb2FXeGtjbVZ1T204dWFuTjRjeWhKWlN4N2NHRnVaV3c2ZFM1d1lXNWxiSE11WjJWdU1peGph'
    || 'R2xzWkhKbGJqcGJieTVxYzNoektDSmthWFlpTEh0emRIbHNaVHA3WkdsemNHeGhlVG9pWm14bGVDSXNaMkZ3T2pnc2NHRmtaR2x1WnpvaU1DQXdJRFp3ZUNJ'
    || 'c1ptOXVkRk5wZW1VNk1URXNZMjlzYjNJNkluWmhjaWd0TFdScGJTa2lMR0p2Y21SbGNrSnZkSFJ2YlRvaU1YQjRJSE52Ykdsa0lIWmhjaWd0TFd4cGJtVXBJ'
    || 'bjBzWTJocGJHUnlaVzQ2VzI4dWFuTjRLQ0p6Y0dGdUlpeDdjM1I1YkdVNmUyWnNaWGc2SWpBZ01DQXhNekJ3ZUNJc2NHRmtaR2x1WjB4bFpuUTZNakI5TEdO'
    || 'b2FXeGtjbVZ1T2lKWFlYSmxhRzkxYzJVaWZTa3NieTVxYzNnb0luTndZVzRpTEh0emRIbHNaVHA3Wm14bGVEb2lNQ0F3SURZd2NIZ2lmU3hqYUdsc1pISmxi'
    || 'am9pVTJsNlpTSjlLU3h2TG1wemVDZ2ljM0JoYmlJc2UzTjBlV3hsT250bWJHVjRPaUl3SURBZ09EQndlQ0o5TEdOb2FXeGtjbVZ1T2lKV1pYSmthV04wSW4w'
    || 'cExHOHVhbk40S0NKemNHRnVJaXg3YzNSNWJHVTZlMlpzWlhnNklqQWdNQ0E0TUhCNElpeDBaWGgwUVd4cFoyNDZJbkpwWjJoMEluMHNZMmhwYkdSeVpXNDZJ'
    || 'a055WldScGRITXZaR0Y1SW4wcExHOHVhbk40S0NKemNHRnVJaXg3YzNSNWJHVTZlMlpzWlhnNklqQWdNQ0EyTUhCNElpeDBaWGgwUVd4cFoyNDZJbkpwWjJo'
    || 'MEluMHNZMmhwYkdSeVpXNDZJbFYwYVd3aWZTbGRmU2tzWXk1dFlYQW9LR0VzYlNrOVBtOHVhbk40S0c1a0xIdHlPbUY5TEcwcEtTeHZMbXB6ZUNoRmJpeDdZ'
    || 'MmhwYkdSeVpXNDZJbFJvY21WemFHOXNaSE1nWVhKbElHcDFaR2RsYldWdWREc2dkR2hwYmlCbGRtbGtaVzVqWlNCd2NtOWtkV05sY3lCUVNVeFBWRjlQVGt4'
    || 'WklISmhkR2hsY2lCMGFHRnVJR0VnY21WamIyMXRaVzVrWVhScGIyNHVJRUZXVDBsRUlISnZkM01nWVhKbElHdGxjSFFnYjI0Z2NIVnljRzl6WlM0aWZTbGRm'
    || 'U2w5S1gxbWRXNWpkR2x2YmlCc1pDaDdjRHAxZlNsN1kyOXVjM1FnWXoxRFpTaDFMQ0p4WVhNaUtTeGhQV05iTUYwL1AzdDlMRzA5WXk1bWFXeDBaWElvUlQw'
    || 'K1UzUnlhVzVuS0VVdVVVRlRYMVpGVWtSSlExUXBQVDA5SWxKRlEwOU5UVVZPUkVWRUlpa3ViR1Z1WjNSb08zSmxkSFZ5YmlCdkxtcHplQ2hNWlN4N2RHbDBi'
    || 'R1U2SWxGMVpYSjVJRUZqWTJWc1pYSmhkR2x2YmlCd1pYSWdkMkZ5WldodmRYTmxJaXgzYVdSbE9pRXdMR2hwYm5RNllFTnZiblpsY25ScGJtY2dZU0IzWVhK'
    || 'bGFHOTFjMlVnZEc4Z1IyVnVNaUJrYjJWeklHNXZkQ0J6ZDJsMFkyZ2dVWFZsY25rZ1FXTmpaV3hsY21GMGFXOXVJRzl1TEFvZ0lDQWdJQ0FnSUNBZ0lDQWdJ'
    || 'Q0FnZEdodmRXZG9JR055WldGMGFXNW5JRzl1WlNCaGN5QkhaVzR5SUdSdlpYTXVJRlJvYVhNZ2FYTWdkR2hsSUhObGRIUnBibWNnWVNCamIyNTJaWEp6YVc5'
    || 'dUNpQWdJQ0FnSUNBZ0lDQWdJQ0FnSUNCc1pXRjJaWE1nWW1Wb2FXNWtJT0tBbENCaGJtUWdhWFFnYVhNZ2JtOTBJR0VnYzJGMmFXNW5PaUIwYUdVZ2IyWm1i'
    || 'RzloWkdWa0lIZHZjbXNnWW1sc2JITWdZWE1LSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJSE5sY0dGeVlYUmxJSE5sY25abGNteGxjM01nVVVGVElHTnlaV1JwZEhN'
    || 'dVlDeGphR2xzWkhKbGJqcHZMbXB6ZUhNb1NXVXNlM0JoYm1Wc09uVXVjR0Z1Wld4ekxuRmhjeXhqYUdsc1pISmxianBiYlQ0d0ppWnZMbXB6ZUNoNlpTeDdi'
    || 'R0ZpWld3NklsZGhjbVZvYjNWelpYTWdkMmwwYUNCbGJHbG5hV0pzWlNCM2IzSnJJR0Z1WkNCUlFWTWdiMlptSWl4MllXeDFaVHBWS0cwcGZTa3NieTVxYzNn'
    || 'b2VuUXNlM0p2ZDNNNll5eHRZWGc2TkRBc1kyOXNjenBiZTJ0bGVUb2lWMEZTUlVoUFZWTkZYMDVCVFVVaUxHeGhZbVZzT2lKWFlYSmxhRzkxYzJVaWZTeDdh'
    || 'MlY1T2lKWFNGOVRTVnBGSWl4c1lXSmxiRG9pVTJsNlpTSjlMSHRyWlhrNklsRkJVMTlGVGtGQ1RFVkVJaXhzWVdKbGJEb2lVVUZUSUc1dmR5SjlMSHRyWlhr'
    || 'NklsRkJVMTlXUlZKRVNVTlVJaXhzWVdKbGJEb2lWbVZ5WkdsamRDSXNjbVZ1WkdWeU9rVTlQbTh1YW5ONEtFVjBMSHQwYjI1bE9rRnlXMU4wY21sdVp5aEZL'
    || 'VjBzWTJocGJHUnlaVzQ2VTNSeWFXNW5LRVVwZlNsOUxIdHJaWGs2SWxGQlUxOUZURWxIU1VKTVJWOVRTRUZTUlNJc2JHRmlaV3c2SWtWc2FXZHBZbXhsSUhO'
    || 'b1lYSmxJaXhoYkdsbmJqb2ljbWxuYUhRaUxISmxibVJsY2pwRlBUNUZQVDF1ZFd4c1B5TGlnSlFpT21Ba2UwMWhkR2d1Y205MWJtUW9RU2hGS1NveFpUTXBM'
    || 'ekV3ZlNWZ2ZTeDdhMlY1T2lKUlFWTmZSVXhKUjBsQ1RFVmZVMFZEVDA1RVV5SXNiR0ZpWld3NklrVnNhV2RwWW14bElITWlMR0ZzYVdkdU9pSnlhV2RvZENJ'
    || 'c2NtVnVaR1Z5T2tVOVBrVTlQVzUxYkd3L0l1S0FsQ0k2VlNoTllYUm9Mbkp2ZFc1a0tFRW9SU2twS1gwc2UydGxlVG9pVVVGVFgxQlNUMUJQVTBWRVgxTkRR'
    || 'VXhGWDBaQlExUlBVaUlzYkdGaVpXdzZJbEJ5YjNCdmMyVmtJR1poWTNSdmNpSXNZV3hwWjI0NkluSnBaMmgwSWl4eVpXNWtaWEk2UlQwK1JUMDliblZzYkQ4'
    || 'aTRvQ1VJanBUZEhKcGJtY29SU2w5TEh0clpYazZJa05TUlVSSlZGTmZVRVZTWDBSQldTSXNiR0ZpWld3NklrTnlaV1JwZEhNdlpHRjVJaXhoYkdsbmJqb2lj'
    || 'bWxuYUhRaUxISmxibVJsY2pwRlBUNVZLRTFoZEdndWNtOTFibVFvUVNoRktTb3hNREFwTHpFd01DbDlMSHRyWlhrNklsRkJVMTlYU0ZraUxHeGhZbVZzT2lK'
    || 'WGFIa2lmVjE5S1N4dkxtcHplSE1vVEhJc2UzUnBkR3hsT2lKWGFHRjBJSFJvYVhNZ2JuVnRZbVZ5SUdsekxDQmhibVFnYVhNZ2JtOTBJaXhqYUdsc1pISmxi'
    || 'anBiVTNSeWFXNW5LR0V1VVVGVFgxUklVa1ZUU0U5TVJGOUpVMTlLVlVSSFJVMUZUbFEvUHlJaUtTd2lJRVZzYVdkcFlteGxJSFJwYldVZ2FYTWdaWGhsWTNW'
    || 'MGFXOXVJSFJwYldVZ1UyNXZkMlpzWVd0bElITmhlWE1nYVhRZ1kyOTFiR1FnYjJabWJHOWhaQ0RpZ0pRZ2FYUWdhWE1nYm05MElIUnBiV1VnYzJGMlpXUXNJ'
    || 'R0Z1WkNCdWIzUWdZM0psWkdsMGN5QnpZWFpsWkM0Z1VVRlRJSEoxYm5NZ2RHaGhkQ0IzYjNKcklHOXVJSE5sY0dGeVlYUmxiSGt0WW1sc2JHVmtJSE5sY25a'
    || 'bGNteGxjM01nWTI5dGNIVjBaU3dnYzI4Z2RHaGxJR2RoYVc0Z2FYTWdjMmh2Y25SbGNpQjNZV3hzTFdOc2IyTnJJRzl1SUhOallXNHRhR1ZoZG5rZ2NYVmxj'
    || 'bWxsY3l3Z1ltOTFaMmgwSUhkcGRHZ2dVVUZUSUdOeVpXUnBkSE11SUVsMElHVmhjbTV6SUdFZ2NHeGhZMlVnYVc0Z2RHaHBjeUJ6YjJ4MWRHbHZiaUJpWldO'
    || 'aGRYTmxJSFJvWVhRZ2MyRnRaU0IzWVd4c0xXTnNiMk5ySUhKbFpIVmpkR2x2YmlCcGN5QmxlR0ZqZEd4NUlIZG9ZWFFnZEdobElFZGxiaklnY21GMFpTQndj'
    || 'bVZ0YVhWdElHNWxaV1J6SUdsdUlHOXlaR1Z5SUhSdklIQmhlU0JtYjNJZ2FYUnpaV3htTGlKZGZTbGRmU2w5S1gxbWRXNWpkR2x2YmlCcFpDaDdjRHAxZlNs'
    || 'N1kyOXVjM1FnWXoxRFpTaDFMQ0poWkdGd2RHbDJaU0lwTEdFOVkxc3dYVDgvZTMwN2NtVjBkWEp1SUc4dWFuTjRLRXhsTEh0MGFYUnNaVG9pUVdSaGNIUnBk'
    || 'bVVnVjJGeVpXaHZkWE5sSUhabGNtUnBZM1FnY0dWeUlIZGhjbVZvYjNWelpTSXNkMmxrWlRvaE1DeG9hVzUwT21CQklHUnBabVpsY21WdWRDQmtaV05wYzJs'
    || 'dmJpQm1jbTl0SUVkbGJqSXNJSGRwZEdnZ1pHbG1abVZ5Wlc1MElHVnNhV2RwWW1sc2FYUjVMaUJCWkdGd2RHbDJaU0IwWVd0bGN3b2dJQ0FnSUNBZ0lDQWdJ'
    || 'Q0FnSUNBZ2MybDZaU3dnWTJ4MWMzUmxjaUJqYjNWdWRDd2dVWFZsY25rZ1FXTmpaV3hsY21GMGFXOXVJR0Z1WkNCemRYTndaVzVrSUhCdmJHbGplU0J2ZFhR'
    || 'Z2IyWWdlVzkxY2dvZ0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnYUdGdVpITWdZVzVrSUdKcGJHeHpJSEJsY2lCeGRXVnllUzVnTEdOb2FXeGtjbVZ1T204dWFuTjRj'
    || 'eWhKWlN4N2NHRnVaV3c2ZFM1d1lXNWxiSE11WVdSaGNIUnBkbVVzWTJocGJHUnlaVzQ2VzI4dWFuTjRLSHAwTEh0eWIzZHpPbU1zYldGNE9qUXdMR052YkhN'
    || 'NlczdHJaWGs2SWxkQlVrVklUMVZUUlY5T1FVMUZJaXhzWVdKbGJEb2lWMkZ5WldodmRYTmxJbjBzZTJ0bGVUb2lWMGhmVTBsYVJTSXNiR0ZpWld3NklsTnBl'
    || 'bVVpZlN4N2EyVjVPaUpXUlZKRVNVTlVJaXhzWVdKbGJEb2lWbVZ5WkdsamRDSXNjbVZ1WkdWeU9tMDlQbTh1YW5ONEtFVjBMSHQwYjI1bE9rRnlXMU4wY21s'
    || 'dVp5aHRLVjBzWTJocGJHUnlaVzQ2VTNSeWFXNW5LRzBwZlNsOUxIdHJaWGs2SWtOU1JVUkpWRk5mVUVWU1gwUkJXU0lzYkdGaVpXdzZJa055WldScGRITXZa'
    || 'R0Y1SWl4aGJHbG5iam9pY21sbmFIUWlMSEpsYm1SbGNqcHRQVDVWS0UxaGRHZ3VjbTkxYm1Rb1FTaHRLU294TURBcEx6RXdNQ2w5TEh0clpYazZJa1JCU1V4'
    || 'WlgwTldJaXhzWVdKbGJEb2lSR0Y1TFhSdkxXUmhlU0J6ZDJsdVp5SXNZV3hwWjI0NkluSnBaMmgwSWl4eVpXNWtaWEk2YlQwK1ZTaE5ZWFJvTG5KdmRXNWtL'
    || 'RUVvYlNrcU1UQXdLUzh4TURBcGZTeDdhMlY1T2lKTlFWaGZRMHhWVTFSRlVsTWlMR3hoWW1Wc09pSk5ZWGdnWTJ4MWMzUmxjbk1pTEdGc2FXZHVPaUp5YVdk'
    || 'b2RDSjlMSHRyWlhrNklsRlZSVlZGUkY5VFJVTlBUa1JUSWl4c1lXSmxiRG9pVVhWbGRXVmtJSE1pTEdGc2FXZHVPaUp5YVdkb2RDSXNjbVZ1WkdWeU9tMDlQ'
    || 'bFVvVFdGMGFDNXliM1Z1WkNoQktHMHBLU2w5TEh0clpYazZJbGRJV1NJc2JHRmlaV3c2SWxkb2VTSjlYWDBwTEc4dWFuTjRjeWhNY2l4N2RHbDBiR1U2SWxS'
    || 'M2J5QjBhR2x1WjNNZ2RHaHBjeUJqWVc1dWIzUWdkR1ZzYkNCNWIzVWlMR05vYVd4a2NtVnVPbHRUZEhKcGJtY29ZUzVGVEVsSFNVSkpURWxVV1Y5T1QxUkZQ'
    || 'ejhpSWlrc0lpQWlMRk4wY21sdVp5aGhMa05QVTFSZlRVOUVSVXhmVGs5VVJUOC9JaUlwWFgwcFhYMHBmU2w5Wm5WdVkzUnBiMjRnYjJRb2UzQTZkWDBwZTJO'
    || 'dmJuTjBJR005UTJVb2RTd2liM1YwWTI5dFpTSXBPM0psZEhWeWJpQnZMbXB6ZUNoTVpTeDdkR2wwYkdVNklsZG9ZWFFnZEdobElHTnZiblpsY25OcGIyNXpJ'
    || 'R0ZqZEhWaGJHeDVJR1JwWkNJc2QybGtaVG9oTUN4b2FXNTBPbUJGYlhCMGVTQjFiblJwYkNCemIyMWxkR2hwYm1jZ2FYTWdZMjl1ZG1WeWRHVmtMQ0IzYUds'
    || 'amFDQnBjeUIwYUdVZ1kyOXljbVZqZENCemRHRjBaU0J2YmlCaElHWnlaWE5vQ2lBZ0lDQWdJQ0FnSUNBZ0lDQWdJQ0JwYm5OMFlXeHNMaUJIYVhabElHRnVl'
    || 'U0JqYjI1MlpYSnphVzl1SUdGMElHeGxZWE4wSUhSb2NtVmxJR1JoZVhNZ1ltVm1iM0psSUhKbFlXUnBibWNnYVhRZzRvQ1VJSFJvWlFvZ0lDQWdJQ0FnSUNB'
    || 'Z0lDQWdJQ0FnY205M0lITmhlWE1nVkU5UFgwVkJVa3haSUhWdWRHbHNJSFJvWlc0dVlDeGphR2xzWkhKbGJqcHZMbXB6ZUhNb1NXVXNlM0JoYm1Wc09uVXVj'
    || 'R0Z1Wld4ekxtOTFkR052YldVc2QyaGxiazFwYzNOcGJtYzZZRTV2ZEdocGJtY2dhR0Z6SUdKbFpXNGdZMjl1ZG1WeWRHVmtJSGxsZEN3Z2MyOGdkR2hsY21V'
    || 'Z2FYTWdibThnWW1WbWIzSmxMV0Z1WkMxaFpuUmxjZ29nSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnSUNCMGJ5QnphRzkzTGlCUWNtVnpj'
    || 'eUIwYUdVZ2NHbHNiM1FnWVdOMGFXOXVMQ0IzWVdsMElIUm9jbVZsSUdSaGVYTXNJR052YldVZ1ltRmpheTVnTEdOb2FXeGtjbVZ1T2x0dkxtcHplQ2g2ZEN4'
    || 'N2NtOTNjenBqTEcxaGVEbzBNQ3hqYjJ4ek9sdDdhMlY1T2lKWFFWSkZTRTlWVTBWZlRrRk5SU0lzYkdGaVpXdzZJbGRoY21Wb2IzVnpaU0o5TEh0clpYazZJ'
    || 'azlWVkVOUFRVVWlMR3hoWW1Wc09pSlBkWFJqYjIxbElpeHlaVzVrWlhJNllUMCtieTVxYzNnb1JYUXNlM1J2Ym1VNmJHbGJVM1J5YVc1bktHRXBYU3hqYUds'
    || 'c1pISmxianBUZEhKcGJtY29ZU2w5S1gwc2UydGxlVG9pUkVGWlUxOVBRbE5GVWxaRlJDSXNiR0ZpWld3NklrUmhlWE1pTEdGc2FXZHVPaUp5YVdkb2RDSjlM'
    || 'SHRyWlhrNklrSkZSazlTUlY5RFVrVkVTVlJUWDFCRlVsOUVRVmtpTEd4aFltVnNPaUpDWldadmNtVWdZM0l2WkdGNUlpeGhiR2xuYmpvaWNtbG5hSFFpTEhK'
    || 'bGJtUmxjanBoUFQ1VktFMWhkR2d1Y205MWJtUW9RU2hoS1NveE1EQXBMekV3TUNsOUxIdHJaWGs2SWtGR1ZFVlNYME5TUlVSSlZGTmZVRVZTWDBSQldTSXNi'
    || 'R0ZpWld3NklrRm1kR1Z5SUdOeUwyUmhlU0lzWVd4cFoyNDZJbkpwWjJoMElpeHlaVzVrWlhJNllUMCtWU2hOWVhSb0xuSnZkVzVrS0VFb1lTa3FNVEF3S1M4'
    || 'eE1EQXBmU3g3YTJWNU9pSlBRbE5GVWxaRlJGOVRVRVZGUkZWUVgxQkRWQ0lzYkdGaVpXdzZJbE53WldWa2RYQWdZV05vYVdWMlpXUWlMR0ZzYVdkdU9pSnlh'
    || 'V2RvZENJc2NtVnVaR1Z5T21FOVBtRTlQVzUxYkd3L2J5NXFjM2dvUlhRc2UzUnZibVU2SW5kaGNtNGlMR05vYVd4a2NtVnVPaUp1YjNRZ2VXVjBJbjBwT21B'
    || 'a2UxVW9UV0YwYUM1eWIzVnVaQ2hCS0dFcEtqRXdLUzh4TUNsOUpXQjlMSHRyWlhrNklsSkZVVlZKVWtWRVgxTlFSVVZFVlZCZlVFTlVJaXhzWVdKbGJEb2lU'
    || 'bVZsWkdWa0lpeGhiR2xuYmpvaWNtbG5hSFFpTEhKbGJtUmxjanBoUFQ1Z0pIdFZLRUVvWVNrcGZTVmdmU3g3YTJWNU9pSlBRbE5GVWxaRlJGOUVSVXhVUVY5'
    || 'RFVrVkVTVlJUWDFCRlVsOUVRVmtpTEd4aFltVnNPaUpFWld4MFlTQmpjaTlrWVhraUxHRnNhV2R1T2lKeWFXZG9kQ0lzY21WdVpHVnlPbUU5UGxVb1RXRjBh'
    || 'QzV5YjNWdVpDaEJLR0VwS2pFd01Da3ZNVEF3S1gxZGZTa3NieTVxYzNoektFVnVMSHRqYUdsc1pISmxianBiVTNSeWFXNW5LQ2hqV3pCZFB6OTdmU2t1U0U5'
    || 'WFgxUlBYMUpGUVVSZlNWUS9QeUlpS1N3aUlFWnBaM1Z5WlhNZ1lYSmxJR0ZqWTI5MWJuUWdiV1YwWlhKcGJtY2diM1psY2lCaElIZHBibVJ2ZHlEaWdKUWdZ'
    || 'VzU1ZEdocGJtY2daV3h6WlNCMGFHRjBJR05vWVc1blpXUWdiMjRnZEdobElIZGhjbVZvYjNWelpTQnBiaUIwYUdVZ2MyRnRaU0J3WlhKcGIyUWdhWE1nYVc0'
    || 'Z2RHaGxJRzUxYldKbGNpNGlYWDBwWFgwcGZTbDlablZ1WTNScGIyNGdjMlFvZTNBNmRYMHBlMk52Ym5OMElHTTlRMlVvZFN3aWNtOXNiR0poWTJzaUtUdHla'
    || 'WFIxY200Z2J5NXFjM2dvVEdVc2UzUnBkR3hsT2lKRGIyNTJaWEp6YVc5dWN5QjBieUJ3ZFhRZ1ltRmpheUlzZDJsa1pUb2hNQ3hvYVc1ME9tQlVhR1VnYkds'
    || 'emRDQnViMkp2WkhrZ2NISnZaSFZqWlhNZ1ptOXlJSFJvWlcxelpXeDJaWE02SUhkaGNtVm9iM1Z6WlhNZ2QyaGxjbVVnZEdobElHTnZiblpsY25OcGIyNEtJ'
    || 'Q0FnSUNBZ0lDQWdJQ0FnSUNBZ0lHUnBaQ0J1YjNRZ2NHRjVJR1p2Y2lCMGFHVWdjbUYwWlNCd2NtVnRhWFZ0TG1Bc1kyaHBiR1J5Wlc0NmJ5NXFjM2dvU1dV'
    || 'c2UzQmhibVZzT25VdWNHRnVaV3h6TG5KdmJHeGlZV05yTEhkb1pXNU5hWE56YVc1bk9tQk9iM1JvYVc1bklIUnZJSEp2Ykd3Z1ltRmpheTRnUldsMGFHVnlJ'
    || 'RzV2SUdOdmJuWmxjbk5wYjI0Z2FHRnpJR0psWlc0Z2JXRmtaU0I1WlhRc0NpQWdJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJRzl5SUc1'
    || 'dmJtVWdiMllnZEdobGJTQnBjeUJqYjNOMGFXNW5JRzF2Y21VZ2RHaGhiaUJwZENCa2FXUWdZbVZtYjNKbExtQXNZMmhwYkdSeVpXNDZZeTVzWlc1bmRHZzlQ'
    || 'VDB3UDI4dWFuTjRLQ0p3SWl4N1kyeGhjM05PWVcxbE9pSnRkWFJsWkNJc1kyaHBiR1J5Wlc0NklrNXZJR052Ym5abGNuUmxaQ0IzWVhKbGFHOTFjMlVnYVhN'
    || 'Z1kzVnljbVZ1ZEd4NUlHTnZjM1JwYm1jZ2JXOXlaU0IwYUdGdUlHbDBjeUJpWVhObGJHbHVaUzRnVkdocGN5QnBjeUIwYUdVZ2MzUmhkR1VnZVc5MUlIZGhi'
    || 'blFzSUdGdVpDQjBhR1VnZDJWbGEyeDVJSGRoZEdOb0lIUmhjMnNnYTJWbGNITWdZMmhsWTJ0cGJtY2dhWFF1SW4wcE9tOHVhbk40S0hwMExIdHliM2R6T21N'
    || 'c1kyOXNjenBiZTJ0bGVUb2lWMEZTUlVoUFZWTkZYMDVCVFVVaUxHeGhZbVZzT2lKWFlYSmxhRzkxYzJVaWZTeDdhMlY1T2lKRVFWbFRYMDlDVTBWU1ZrVkVJ'
    || 'aXhzWVdKbGJEb2lSR0Y1Y3lJc1lXeHBaMjQ2SW5KcFoyaDBJbjBzZTJ0bGVUb2lRa1ZHVDFKRlgwTlNSVVJKVkZOZlVFVlNYMFJCV1NJc2JHRmlaV3c2SWtK'
    || 'bFptOXlaU0JqY2k5a1lYa2lMR0ZzYVdkdU9pSnlhV2RvZENJc2NtVnVaR1Z5T21FOVBsVW9UV0YwYUM1eWIzVnVaQ2hCS0dFcEtqRXdNQ2t2TVRBd0tYMHNl'
    || 'MnRsZVRvaVFVWlVSVkpmUTFKRlJFbFVVMTlRUlZKZlJFRlpJaXhzWVdKbGJEb2lRV1owWlhJZ1kzSXZaR0Y1SWl4aGJHbG5iam9pY21sbmFIUWlMSEpsYm1S'
    || 'bGNqcGhQVDVWS0UxaGRHZ3VjbTkxYm1Rb1FTaGhLU294TURBcEx6RXdNQ2w5TEh0clpYazZJa0ZPVGxWQlRFbFRSVVJmUkVWTVZFRmZRMUpGUkVsVVV5SXNi'
    || 'R0ZpWld3NklsQmxjaUI1WldGeUlpeGhiR2xuYmpvaWNtbG5hSFFpTEhKbGJtUmxjanBoUFQ1dkxtcHplSE1vSW5OMGNtOXVaeUlzZTJOb2FXeGtjbVZ1T2xz'
    || 'aUt5SXNWU2hOWVhSb0xuSnZkVzVrS0VFb1lTa3BLVjE5S1gwc2UydGxlVG9pVDBKVFJWSldSVVJmVTFCRlJVUlZVRjlRUTFRaUxHeGhZbVZzT2lKSGIzUWlM'
    || 'R0ZzYVdkdU9pSnlhV2RvZENJc2NtVnVaR1Z5T21FOVBtQWtlMVVvVFdGMGFDNXliM1Z1WkNoQktHRXBLakV3S1M4eE1DbDlKV0I5TEh0clpYazZJbEpGVVZW'
    || 'SlVrVkVYMU5RUlVWRVZWQmZVRU5VSWl4c1lXSmxiRG9pVG1WbFpHVmtJaXhoYkdsbmJqb2ljbWxuYUhRaUxISmxibVJsY2pwaFBUNWdKSHRWS0VFb1lTa3Bm'
    || 'U1ZnZlN4N2EyVjVPaUpYU0VGVVgxUlBYMFJQSWl4c1lXSmxiRG9pVjJoaGRDQjBieUJrYnlKOVhYMHBmU2w5S1gxbWRXNWpkR2x2YmlCMVpDaDdjRHAxZlNs'
    || 'N2NtVjBkWEp1SUc4dWFuTjRLRXhsTEh0MGFYUnNaVG9pVkdobElHSmxabTl5WlMxd2FXTjBkWEpsTENCallYQjBkWEpsWkNCaGRDQmlkV2xzWkNCMGFXMWxJ'
    || 'aXgzYVdSbE9pRXdMR2hwYm5RNllFTmhjSFIxY21Wa0lFSkZSazlTUlNCaGJua2dZMjl1ZG1WeWMybHZiaXdnYjI0Z2NIVnljRzl6WlM0Z1FTQmpiMjUyWlhK'
    || 'emFXOXVJSGRwZEdnZ2JtOGdZbUZ6Wld4cGJtVUtJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ0lHTmhibTV2ZENCaVpTQmxkbUZzZFdGMFpXUWdZV1owWlhKM1lYSmtj'
    || 'eXdnWVc1a0lDZHBkQ0JtWldWc2N5Qm1ZWE4wWlhJbklHbHpJSGRvWVhRZ1ptbHNiSE1nZEdobENpQWdJQ0FnSUNBZ0lDQWdJQ0FnSUNCbllYQXVZQ3hqYUds'
    || 'c1pISmxianB2TG1wemVITW9TV1VzZTNCaGJtVnNPblV1Y0dGdVpXeHpMbUpoYzJWc2FXNWxMR05vYVd4a2NtVnVPbHR2TG1wemVDaDZkQ3g3Y205M2N6cERa'
    || 'U2gxTENKaVlYTmxiR2x1WlNJcExHMWhlRG96TUN4amIyeHpPbHQ3YTJWNU9pSlhRVkpGU0U5VlUwVmZUa0ZOUlNJc2JHRmlaV3c2SWxkaGNtVm9iM1Z6WlNK'
    || 'OUxIdHJaWGs2SWtkRlRrVlNRVlJKVDA1ZlFrVkdUMUpGSWl4c1lXSmxiRG9pUjJWdUlHSmxabTl5WlNJc2NtVnVaR1Z5T21NOVBtOHVhbk40S0V4akxIdDJZ'
    || 'V3gxWlRwakxHNXZibVU2SWx4Y2RUSXdNVFFpZlNsOUxIdHJaWGs2SWxkSVgxUlpVRVZmUWtWR1QxSkZJaXhzWVdKbGJEb2lWSGx3WlNCaVpXWnZjbVVpZlN4'
    || 'N2EyVjVPaUpEVWtWRVNWUlRYMUJGVWw5RVFWa2lMR3hoWW1Wc09pSkRjbVZrYVhSekwyUmhlU0lzWVd4cFoyNDZJbkpwWjJoMElpeHlaVzVrWlhJNll6MCtW'
    || 'U2hOWVhSb0xuSnZkVzVrS0VFb1l5a3FNVEF3S1M4eE1EQXBmU3g3YTJWNU9pSlJWVVZTV1Y5RFQxVk9WQ0lzYkdGaVpXdzZJbEYxWlhKcFpYTWlMR0ZzYVdk'
    || 'dU9pSnlhV2RvZENJc2NtVnVaR1Z5T21NOVBsVW9RU2hqS1NsOUxIdHJaWGs2SWxORlEwOU9SRk5mVUVWU1gxRlZSVkpaSWl4c1lXSmxiRG9pVTJWakwzRjFa'
    || 'WEo1SWl4aGJHbG5iam9pY21sbmFIUWlMSEpsYm1SbGNqcGpQVDVWS0UxaGRHZ3VjbTkxYm1Rb1FTaGpLU294WlRNcEx6RmxNeWw5TEh0clpYazZJbFZVU1V4'
    || 'SlUwRlVTVTlPSWl4c1lXSmxiRG9pVlhScGJHbHpZWFJwYjI0aUxHRnNhV2R1T2lKeWFXZG9kQ0lzY21WdVpHVnlPbU05UGtseUtHTXBmU3g3YTJWNU9pSlhT'
    || 'VTVFVDFkZlJFRlpVeUlzYkdGaVpXdzZJbGRwYm1SdmR5SXNZV3hwWjI0NkluSnBaMmgwSW4wc2UydGxlVG9pUTBGUVZGVlNSVVJmUVZRaUxHeGhZbVZzT2lK'
    || 'RFlYQjBkWEpsWkNKOVhYMHBMRzh1YW5ONEtFVnVMSHRqYUdsc1pISmxiam9pVTJWamIyNWtjeUJ3WlhJZ2NYVmxjbmtnYVhNZ2RHaGxJRzFsZEhKcFl5QmhJ'
    || 'R2RsYm1WeVlYUnBiMjRnWTJoaGJtZGxJSE5vYjNWc1pDQmhZM1IxWVd4c2VTQnRiM1psTGlCRGNtVmthWFJ6SUhCbGNpQmtZWGtnYlc5MlpYTWdkMmwwYUNC'
    || 'b2IzY2diWFZqYUNCM2IzSnJJR0Z5Y21sMlpXUXNJSGRvYVdOb0lIUm9aU0JqYjI1MlpYSnphVzl1SUdSdlpYTWdibTkwSUdOdmJuUnliMnd1SW4wcFhYMHBm'
    || 'U2w5Wm5WdVkzUnBiMjRnWVdRb2UzQTZkWDBwZTNKbGRIVnliaUJ2TG1wemVDaE1aU3g3ZEdsMGJHVTZJbGRsWld0c2VTQnlaUzFqYUdWamF5Qm9hWE4wYjNK'
    || 'NUlpeDNhV1JsT2lFd0xHaHBiblE2WUZSQlUwdGZSMFZPTWw5WFFWUkRTQ0J5WlMxdFpXRnpkWEpsY3lCbGRtVnllU0JqYjI1MlpYSjBaV1FnZDJGeVpXaHZk'
    || 'WE5sSUdGbllXbHVjM1FnYVhSeklHSmhjMlZzYVc1bENpQWdJQ0FnSUNBZ0lDQWdJQ0FnSUNCdmJtTmxJR0VnZDJWbGF5NGdTWFFnYjI1c2VTQnlkVzV6SUdG'
    || 'MElGQlNUMFJWUTFSSlQwNGdkR2xsY2pzZ1ltVnNiM2NnZEdoaGRDQnBkQ0JsZUdsemRITWdZVzVrSUdsekNpQWdJQ0FnSUNBZ0lDQWdJQ0FnSUNCemRYTnda'
    || 'VzVrWldRdVlDeGphR2xzWkhKbGJqcHZMbXB6ZUNoSlpTeDdjR0Z1Wld3NmRTNXdZVzVsYkhNdWQyRjBZMmdzZDJobGJrMXBjM05wYm1jNklrNXZJR05vWldO'
    || 'cmN5QnlaV052Y21SbFpDQjVaWFF1SWl4amFHbHNaSEpsYmpwdkxtcHplQ2g2ZEN4N2NtOTNjenBEWlNoMUxDSjNZWFJqYUNJcExHMWhlRG8wTUN4amIyeHpP'
    || 'bHQ3YTJWNU9pSkRTRVZEUzBWRVgwRlVJaXhzWVdKbGJEb2lRMmhsWTJ0bFpDSjlMSHRyWlhrNklsZEJVa1ZJVDFWVFJWOU9RVTFGSWl4c1lXSmxiRG9pVjJG'
    || 'eVpXaHZkWE5sSW4wc2UydGxlVG9pUkVGWlUxOVBRbE5GVWxaRlJDSXNiR0ZpWld3NklrUmhlWE1pTEdGc2FXZHVPaUp5YVdkb2RDSjlMSHRyWlhrNklrOVZW'
    || 'RU5QVFVVaUxHeGhZbVZzT2lKUGRYUmpiMjFsSWl4eVpXNWtaWEk2WXowK2J5NXFjM2dvUlhRc2UzUnZibVU2YkdsYlUzUnlhVzVuS0dNcFhTeGphR2xzWkhK'
    || 'bGJqcFRkSEpwYm1jb1l5bDlLWDBzZTJ0bGVUb2lUMEpUUlZKV1JVUmZVMUJGUlVSVlVGOVFRMVFpTEd4aFltVnNPaUpIYjNRaUxHRnNhV2R1T2lKeWFXZG9k'
    || 'Q0lzY21WdVpHVnlPbU05UG1NOVBXNTFiR3cvSXVLQWxDSTZZQ1I3VlNoTllYUm9Mbkp2ZFc1a0tFRW9ZeWtxTVRBcEx6RXdLWDBsWUgwc2UydGxlVG9pVWtW'
    || 'UlZVbFNSVVJmVTFCRlJVUlZVRjlRUTFRaUxHeGhZbVZzT2lKT1pXVmtaV1FpTEdGc2FXZHVPaUp5YVdkb2RDSXNjbVZ1WkdWeU9tTTlQbUFrZTFVb1FTaGpL'
    || 'U2w5SldCOVhYMHBmU2w5S1gxbWRXNWpkR2x2YmlCalpDaDdjRHAxZlNsN1kyOXVjM1FnWXoxRFpTaDFMQ0ozYUY5a1pYUmhhV3dpS1Zzd1hUdHlaWFIxY200'
    || 'Z2J5NXFjM2dvVEdVc2UzUnBkR3hsT2lKVFpXeGxZM1JsWkNCM1lYSmxhRzkxYzJVaUxIZHBaR1U2SVRBc2FHbHVkRHBnVUdsamF5QjBhR1VnZDJGeVpXaHZk'
    || 'WE5sSUdsdUlIUm9aU0JqYjI1MGNtOXNJR0ZpYjNabElIUm9aU0JrWVhOb1ltOWhjbVF1SUVkbGJqSWdZVzVrSUVGa1lYQjBhWFpsQ2lBZ0lDQWdJQ0FnSUNB'
    || 'Z0lDQWdJQ0JoY21VZ2FXNWtaWEJsYm1SbGJuUWdaR1ZqYVhOcGIyNXpMQ0J6YnlCaWIzUm9JSFpsY21ScFkzUnpJR0Z5WlNCemFHOTNiaURpZ0pRZ1lTQjNZ'
    || 'WEpsYUc5MWMyVWdZMkZ1Q2lBZ0lDQWdJQ0FnSUNBZ0lDQWdJQ0JpWlNCaElITjBjbTl1WnlCQlpHRndkR2wyWlNCallYTmxJR0Z1WkNCaElIQnZiM0lnUjJW'
    || 'dU1pQnZibVV1WUN4amFHbHNaSEpsYmpwdkxtcHplQ2hKWlN4N2NHRnVaV3c2ZFM1d1lXNWxiSE11ZDJoZlpHVjBZV2xzTEdOb2FXeGtjbVZ1T21NL2J5NXFj'
    || 'M2h6S0c4dVJuSmhaMjFsYm5Rc2UyTm9hV3hrY21WdU9sdHZMbXB6ZUhNb0ltUnBkaUlzZTNOMGVXeGxPbnRrYVhOd2JHRjVPaUptYkdWNElpeG5ZWEE2TVRn'
    || 'c1pteGxlRmR5WVhBNkluZHlZWEFpTEdGc2FXZHVTWFJsYlhNNkltSmhjMlZzYVc1bElpeHRZWEpuYVc1Q2IzUjBiMjA2TVRCOUxHTm9hV3hrY21WdU9sdHZM'
    || 'bXB6ZUNnaWMzQmhiaUlzZTNOMGVXeGxPbnRtYjI1MFYyVnBaMmgwT2pZd01IMHNZMmhwYkdSeVpXNDZVM1J5YVc1bktHTXVWMEZTUlVoUFZWTkZYMDVCVFVV'
    || 'L1B5SWlLWDBwTEc4dWFuTjRLRVYwTEh0amFHbHNaSEpsYmpwVGRISnBibWNvWXk1WFNGOVRTVnBGUHo4aUlpbDlLU3h2TG1wemVDaEZkQ3g3WTJocGJHUnla'
    || 'VzQ2SWtkbGJpQWlLMU4wY21sdVp5aGpMa2RGVGtWU1FWUkpUMDQvUHlJaUtYMHBMRzh1YW5ONEtFVjBMSHRqYUdsc1pISmxianBUZEhKcGJtY29ZeTVYU0Y5'
    || 'VVdWQkZQejhpSWlsOUtWMTlLU3h2TG1wemVITW9JbVJwZGlJc2UzTjBlV3hsT250a2FYTndiR0Y1T2lKbWJHVjRJaXhuWVhBNk1qUXNabXhsZUZkeVlYQTZJ'
    || 'bmR5WVhBaWZTeGphR2xzWkhKbGJqcGJieTVxYzNnb2VtVXNlMnhoWW1Wc09pSkhaVzR5SUhabGNtUnBZM1FpTEhaaGJIVmxPbE4wY21sdVp5aGpMa2RGVGpK'
    || 'ZlZrVlNSRWxEVkQ4L0l1S0FsQ0lwZlNrc2J5NXFjM2dvZW1Vc2UyeGhZbVZzT2lKQlpHRndkR2wyWlNCMlpYSmthV04wSWl4MllXeDFaVHBUZEhKcGJtY29Z'
    || 'eTVCUkVGUVZFbFdSVjlXUlZKRVNVTlVQejhpNG9DVUlpbDlLU3h2TG1wemVDaDZaU3g3YkdGaVpXdzZJa055WldScGRITXZaR0Y1SWl4MllXeDFaVHBWS0dN'
    || 'dVExSkZSRWxVVTE5UVJWSmZSRUZaS1gwcExHOHVhbk40S0hwbExIdHNZV0psYkRvaVUzQmxaV1IxY0NCdVpXVmtaV1FnZEc4Z1luSmxZV3NnWlhabGJpSXNk'
    || 'bUZzZFdVNlZTaGpMbEpGVVZWSlVrVkVYMU5RUlVWRVZWQmZVRU5VS1NzaUpTSjlLU3h2TG1wemVDaDZaU3g3YkdGaVpXdzZJa052YzNRdlpHRjVJR2xtSUds'
    || 'MElHUnZaWE1nYm05MElITndaV1ZrSUhWd0lpeDJZV3gxWlRvaUt5SXJWU2hqTGxkUFVsTlVYME5CVTBWZlJWaFVVa0ZmUTFKRlJFbFVVMTlRUlZKZlJFRlpL'
    || 'WDBwTEc4dWFuTjRLSHBsTEh0c1lXSmxiRG9pVlhScGJHbHpZWFJwYjI0aUxIWmhiSFZsT2xVb1l5NVZWRWxNU1ZOQlZFbFBUaWw5S1N4dkxtcHplQ2g2WlN4'
    || 'N2JHRmlaV3c2SWtaaGRtOTFjbUZpYkdVZ2MyaGhjbVVpTEhaaGJIVmxPbFVvWXk1R1FWWlBWVkpCUWt4RlgxTklRVkpGS1gwcExHOHVhbk40S0hwbExIdHNZ'
    || 'V0psYkRvaVJHRjVMWFJ2TFdSaGVTQjJZWEpwWVhScGIyNGlMSFpoYkhWbE9sVW9ZeTVFUVVsTVdWOURWaWw5S1YxOUtTeGpMa2RGVGpKZlYwaFpQMjh1YW5O'
    || 'NEtFVnVMSHRqYUdsc1pISmxiam9pUjJWdU1qb2dJaXRUZEhKcGJtY29ZeTVIUlU0eVgxZElXU2w5S1RwdWRXeHNMR011UVVSQlVGUkpWa1ZmVjBoWlAyOHVh'
    || 'bk40S0VWdUxIdGphR2xzWkhKbGJqb2lRV1JoY0hScGRtVTZJQ0lyVTNSeWFXNW5LR011UVVSQlVGUkpWa1ZmVjBoWktYMHBPbTUxYkd3c1l5NUZURWxIU1VK'
    || 'SlRFbFVXVjlPVDFSRlAyOHVhbk40S0V4eUxIdGphR2xzWkhKbGJqcFRkSEpwYm1jb1l5NUZURWxIU1VKSlRFbFVXVjlPVDFSRktYMHBPbTUxYkd4ZGZTazZi'
    || 'blZzYkgwcGZTbDlablZ1WTNScGIyNGdaR1FvZTNBNmRYMHBlMk52Ym5OMElHTTlXM3RwWkRvaVoyVnVNaUlzYkdGaVpXdzZJa2RsYmpJaUxHUmxjMk02SWxk'
    || 'b2FXTm9JSGRoY21Wb2IzVnpaWE1nYzJodmRXeGtJRzF2ZG1Vc0lHRnVaQ0IzYUdsamFDQnRkWE4wSUc1dmRDSXNhV052YmpvaWIzWmxjblpwWlhjaUxIQmhi'
    || 'bVZzY3pwYkltZGxiaklpTENKbFkyOXViMjFwWTNNaUxDSjNhRjlrWlhSaGFXd2lYU3h5Wlc1a1pYSTZLQ2s5UG04dWFuTjRjeWh2TGtaeVlXZHRaVzUwTEh0'
    || 'amFHbHNaSEpsYmpwYmJ5NXFjM2dvWldRc2UzQTZkWDBwTEc4dWFuTjRLSFJrTEh0d09uVjlLU3h2TG1wemVDaEtZeXg3Y0RwMWZTa3NieTVxYzNnb1kyUXNl'
    || 'M0E2ZFgwcExHOHVhbk40S0hKa0xIdHdPblY5S1N4dkxtcHplQ2hKWXl4N2NHRnVaV3c2ZFM1d1lXNWxiSE11YzNCbGJtUXNkMmhoZERvaWQyOXlhMnh2WVdR'
    || 'Z2MzQmxibVFnWW5KbFlXdGtiM2R1SW4wcFhYMHBmU3g3YVdRNkluRmhjeUlzYkdGaVpXdzZJa0ZqWTJWc1pYSmhkR2x2YmlJc1pHVnpZem9pVkdobElITmxk'
    || 'SFJwYm1jZ1lTQkhaVzR5SUdOdmJuWmxjbk5wYjI0Z2JHVmhkbVZ6SUc5bVppSXNhV052YmpvaWMzQmhjbXNpTEhCaGJtVnNjenBiSW5GaGN5SmRMSEpsYm1S'
    || 'bGNqb29LVDArYnk1cWMzZ29iR1FzZTNBNmRYMHBmU3g3YVdRNkltRmtZWEIwYVhabElpeHNZV0psYkRvaVFXUmhjSFJwZG1VaUxHUmxjMk02SWtKMWNuTjBl'
    || 'U0JoYm1RZ2JXbDRaV1FnZDI5eWEyeHZZV1J6SWl4cFkyOXVPaUp6Y0dGeWF5SXNjR0Z1Wld4ek9sc2lZV1JoY0hScGRtVWlYU3h5Wlc1a1pYSTZLQ2s5UG04'
    || 'dWFuTjRLR2xrTEh0d09uVjlLWDBzZTJsa09pSndjbTl2WmlJc2JHRmlaV3c2SWxCeWIyOW1JaXhrWlhOak9pSkNaV1p2Y21Vc0lHRm1kR1Z5TENCaGJtUWdk'
    || 'MmhoZENCMGJ5QndkWFFnWW1GamF5SXNhV052YmpvaWJXOXVaWGtpTEhCaGJtVnNjenBiSW05MWRHTnZiV1VpTENKeWIyeHNZbUZqYXlJc0ltSmhjMlZzYVc1'
    || 'bElpd2lkMkYwWTJnaVhTeHlaVzVrWlhJNktDazlQbTh1YW5ONGN5aHZMa1p5WVdkdFpXNTBMSHRqYUdsc1pISmxianBiYnk1cWMzZ29ZbU1zZTNBNmRYMHBM'
    || 'Rzh1YW5ONEtHOWtMSHR3T25WOUtTeHZMbXB6ZUNoelpDeDdjRHAxZlNrc2J5NXFjM2dvZFdRc2UzQTZkWDBwWFgwcGZTeDdhV1E2SW5kaGRHTm9JaXhzWVdK'
    || 'bGJEb2lWMkYwWTJnaUxHUmxjMk02SWxkbFpXdHNlU0J5WlMxamFHVmpheUJvYVhOMGIzSjVJaXhwWTI5dU9pSjNZWEp1SWl4d1lXNWxiSE02V3lKM1lYUmph'
    || 'Q0pkTEhKbGJtUmxjam9vS1QwK2J5NXFjM2dvWVdRc2UzQTZkWDBwZlN4N2FXUTZJbUZqZEdsdmJuTWlMR3hoWW1Wc09pSlhhR0YwSUhSb2FYTWdZMkZ1SUdS'
    || 'dklpeGtaWE5qT2lKQlkzUnBiMjV6SUdGdVpDQm9hWE4wYjNKNUlpeHBZMjl1T2lKbWJHOTNJaXh3WVc1bGJITTZXeUpoWTNScGIyNXpJaXdpWVdOMGFXOXVY'
    || 'Mnh2WnlKZExISmxibVJsY2pvb0tUMCtieTVxYzNoektHOHVSbkpoWjIxbGJuUXNlMk5vYVd4a2NtVnVPbHR2TG1wemVDaE1aU3g3ZEdsMGJHVTZJa0YyWVds'
    || 'c1lXSnNaU0JoWTNScGIyNXpJaXgzYVdSbE9pRXdMR2hwYm5RNllFVmhZMmdnWVdOMGFXOXVJR2x6SUdFZ1kyaGhibWRsSUhSb2FYTWdjMjlzZFhScGIyNGdZ'
    || 'MkZ1SUcxaGEyVWdkRzhnZVc5MWNpQmhZMk52ZFc1MExpQlVhR1VLSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ0lHSjFkSFJ2Ym5NZ1lYSmxJR0psYkc5'
    || 'M0lIUm9aU0JrWVhOb1ltOWhjbVFnYVc0Z2RHaGxJRk4wY21WaGJXeHBkQ0JvYjNOMExtQXNZMmhwYkdSeVpXNDZieTVxYzNnb1NXVXNlM0JoYm1Wc09uVXVj'
    || 'R0Z1Wld4ekxtRmpkR2x2Ym5Nc2JtOTBRblZwYkhSQ2JHOWphenB2TG1wemVDaE5ZeXg3YzJWMGRHbHVaem9pVjBoSFJVNWZRVXhNVDFkZlFVTlVTVTlPVXlK'
    || 'OUtTeGphR2xzWkhKbGJqcHZMbXB6ZUNoQll5eDdZV04wYVc5dWN6cERaU2gxTENKaFkzUnBiMjV6SWlsOUtYMHBmU2tzYnk1cWMzZ29UR1VzZTNScGRHeGxP'
    || 'aUpTWldObGJuUWdjblZ1Y3lJc2QybGtaVG9oTUN4b2FXNTBPaUpVYUdVZ2JHRnpkQ0JoWTNScGIyNXpJR1Y0WldOMWRHVmtJRzl5SUhWdVpHOXVaU3dnZDJs'
    || 'MGFDQjBhVzFsYzNSaGJYQnpJR0Z1WkNCemRHRjBkWE11SWl4amFHbHNaSEpsYmpwdkxtcHplQ2hKWlN4N2NHRnVaV3c2ZFM1d1lXNWxiSE11WVdOMGFXOXVY'
    || 'Mnh2Wnl4M2FHVnVUV2x6YzJsdVp6b2lUbThnWVdOMGFXOXVJR3h2WnlCbGVHbHpkSE1nZVdWMElPS0FsQ0J1YjNSb2FXNW5JR2hoY3lCaVpXVnVJSEoxYmk0'
    || 'aUxHTm9hV3hrY21WdU9tOHVhbk40S0hwakxIdHNiMmM2UTJVb2RTd2lZV04wYVc5dVgyeHZaeUlwZlNsOUtYMHBYWDBwZlYwN2NtVjBkWEp1SUc4dWFuTjRL'
    || 'Q1JqTEh0d1lYbHNiMkZrT25Vc2MzVmlkR2wwYkdVNklsZGhjbVZvYjNWelpTQm5aVzVsY21GMGFXOXVJaXh6WldOMGFXOXVjenBqZlNsOVdHTW9kVDArYnk1'
    || 'cWMzZ29aR1FzZTNBNmRYMHBLWDBwS0NrN0NnPT0iCkFQUF9DU1NfQjY0ID0gIkxtRndjQzEyYVdWM0xXMWxiblY3Y0c5emFYUnBiMjQ2Y21Wc1lYUnBkbVU3'
    || 'Wm14bGVEcHViMjVsTzIxaGNtZHBiaTFzWldaME9tRjFkRzg3WTI5c2IzSTZkbUZ5S0MwdGJtRjJlU3dnSXpBNU1XWXpOaWw5TG1Gd2NDMTJhV1YzTFcxbGJu'
    || 'VStjM1Z0YldGeWVYdGthWE53YkdGNU9tWnNaWGc3WVd4cFoyNHRhWFJsYlhNNlkyVnVkR1Z5TzJwMWMzUnBabmt0WTI5dWRHVnVkRHBqWlc1MFpYSTdkMmxr'
    || 'ZEdnNk16WndlRHRvWldsbmFIUTZNelp3ZUR0d1lXUmthVzVuT2pBN1ltOXlaR1Z5T2pBN1ltOXlaR1Z5TFhKaFpHbDFjem8xY0hnN1kzVnljMjl5T25CdmFX'
    || 'NTBaWEk3YkdsemRDMXpkSGxzWlRwdWIyNWxmUzVoY0hBdGRtbGxkeTF0Wlc1MVBuTjFiVzFoY25rNk9pMTNaV0pyYVhRdFpHVjBZV2xzY3kxdFlYSnJaWEo3'
    || 'WkdsemNHeGhlVHB1YjI1bGZTNWhjSEF0ZG1sbGR5MXRaVzUxUG5OMWJXMWhjbms2YUc5MlpYSXNMbUZ3Y0MxMmFXVjNMVzFsYm5WYmIzQmxibDArYzNWdGJX'
    || 'RnllWHRpWVdOclozSnZkVzVrT25aaGNpZ3RMWE4xY21aaFkyVXRNaXdnSTJZelpqTm1OQ2w5TG1Gd2NDMTJhV1YzTFcxbGJuVStjM1Z0YldGeWVUcG1iMk4x'
    || 'Y3kxMmFYTnBZbXhsTEM1aGNIQXRkbWxsZHkxdmNIUnBiMjV6UG1FNlptOWpkWE10ZG1semFXSnNaWHR2ZFhSc2FXNWxPakp3ZUNCemIyeHBaQ0IyWVhJb0xT'
    || 'MWhZMk5sYm5Rc0lDTXdNRGcwWkRRcE8yOTFkR3hwYm1VdGIyWm1jMlYwT2pKd2VIMHVZWEJ3TFhacFpYY3RiM0IwYVc5dWMzdHdiM05wZEdsdmJqcGhZbk52'
    || 'YkhWMFpUdDZMV2x1WkdWNE9qTXdPM0pwWjJoME9qQTdkRzl3T21OaGJHTW9NVEF3SlNBcklEWndlQ2s3ZDJsa2RHZzZNVGMwY0hnN2JXRjRMWGRwWkhSb09t'
    || 'TmhiR01vTVRBd2RuY2dMU0F6TW5CNEtUdGthWE53YkdGNU9tZHlhV1E3WjJGd09qSndlRHR3WVdSa2FXNW5PalZ3ZUR0aWIzSmtaWEk2TVhCNElITnZiR2xr'
    || 'SUhaaGNpZ3RMV3hwYm1Vc0lDTmxNbVV5WlRZcE8ySnZjbVJsY2kxeVlXUnBkWE02Tm5CNE8ySmhZMnRuY205MWJtUTZJMlptWmp0aWIzZ3RjMmhoWkc5M09q'
    || 'QWdObkI0SURFNGNIZ2dJekE1TVdZek5qRm1mUzVoY0hBdGRtbGxkeTF2Y0hScGIyNXpQbUY3WkdsemNHeGhlVHBpYkc5amF6dHdZV1JrYVc1bk9qbHdlQ0F4'
    || 'TUhCNE8yTnZiRzl5T21sdWFHVnlhWFE3Wm05dWREcHBibWhsY21sME8yWnZiblF0YzJsNlpUb3hNM0I0TzJ4cGJtVXRhR1ZwWjJoME9qRXVOVHQwWlhoMExX'
    || 'UmxZMjl5WVhScGIyNDZibTl1WlR0aWIzSmtaWEl0Y21Ga2FYVnpPak53ZUgwdVlYQndMWFpwWlhjdGIzQjBhVzl1Y3o1aE9taHZkbVZ5ZTJKaFkydG5jbTkx'
    || 'Ym1RNmRtRnlLQzB0YzNWeVptRmpaUzB5TENBalpqTm1NMlkwS1gwNmNtOXZkSHN0TFdKbk9pQWpaamhtT0dZNE95MHRjM1Z5Wm1GalpUb2dJMlptWm1abVpq'
    || 'c3RMWE4xY21aaFkyVXRNam9nSTJZelpqTm1ORHN0TFhOMWNtWmhZMlV0TXpvZ0kyVmlaV0psWkRzdExXeHBibVU2SUNObE5XVTFaVGM3TFMxc2FXNWxMVEk2'
    || 'SUNOa05tUTJaRGs3TFMxMFpYaDBPaUFqTVRFeE1URXhPeTB0YlhWMFpXUTZJQ00yWWpaaU5tSTdMUzFrYVcwNklDTmhNMkV6WVRNN0xTMWhZMk5sYm5RNklD'
    || 'TXdNRGcwWkRRN0xTMXVZWFo1T2lBak1HRXlNelF5T3kwdGMydDVPaUFqTWpsaU5XVTRPeTB0WjI5dlpEb2dJekUyWVRNMFlUc3RMWGRoY200NklDTm1OVGxs'
    || 'TUdJN0xTMWlZV1E2SUNObE9EQXdNV003TFMxMmFXOXNaWFE2SUNNM1l6TmhaV1E3TFMxbmIyOWtMWGRoYzJnNklISm5ZbUVvTWpJc0lERTJNeXdnTnpRc0lD'
    || 'NHdPQ2s3TFMxM1lYSnVMWGRoYzJnNklISm5ZbUVvTWpRMUxDQXhOVGdzSURFeExDQXVNU2s3TFMxaVlXUXRkMkZ6YURvZ2NtZGlZU2d5TXpJc0lEQXNJREk0'
    || 'TENBdU1EY3BPeTB0WVdOalpXNTBMWGRoYzJnNklISm5ZbUVvTUN3Z01UTXlMQ0F5TVRJc0lDNHdOeWs3TFMxeVlXUnBkWE02SURFeWNIZzdMUzF5WVdScGRY'
    || 'TXRiR2M2SURFMmNIZzdMUzF5WVdScGRYTXRlR3c2SURJd2NIZzdMUzF6YUMxallYSmtPaUF3SURGd2VDQXpjSGdnY21kaVlTZ3dMQ0F3TENBd0xDQXVNRFlw'
    || 'TENBd0lESndlQ0F4TW5CNElISm5ZbUVvTUN3Z01Dd2dNQ3dnTGpBMEtUc3RMWE5vTFcxa09pQXdJREp3ZUNBNGNIZ2djbWRpWVNnd0xDQXdMQ0F3TENBdU1E'
    || 'Z3BMQ0F3SURod2VDQXlOSEI0SUhKblltRW9NQ3dnTUN3Z01Dd2dMakEyS1RzdExYTm9MV2h2ZG1WeU9pQXdJRFJ3ZUNBeE5uQjRJSEpuWW1Fb01Dd2dNQ3dn'
    || 'TUN3Z0xqRXBMQ0F3SURFeWNIZ2dNelp3ZUNCeVoySmhLREFzSURBc0lEQXNJQzR3TnlrN0xTMWxZWE5sT2lCamRXSnBZeTFpWlhwcFpYSW9Makl5TENBeExD'
    || 'QXVNellzSURFcE95MHRjMmxrWldKaGNpMTNPaUF5TXpad2VIMHFlMkp2ZUMxemFYcHBibWM2WW05eVpHVnlMV0p2ZUgxb2RHMXNMR0p2WkhsN2JXRnlaMmx1'
    || 'T2pBN2NHRmtaR2x1Wnpvd08ySmhZMnRuY205MWJtUTZkbUZ5S0MwdFltY3BPMk52Ykc5eU9uWmhjaWd0TFhSbGVIUXBPMlp2Ym5RdFptRnRhV3g1T2kxaGNI'
    || 'QnNaUzF6ZVhOMFpXMHNRbXhwYm10TllXTlRlWE4wWlcxR2IyNTBMRk5sWjI5bElGVkpMRWhsYkhabGRHbGpZU0JPWlhWbExFRnlhV0ZzTEhOaGJuTXRjMlZ5'
    || 'YVdZN1ptOXVkQzF6YVhwbE9qRTBjSGc3YkdsdVpTMW9aV2xuYUhRNk1TNDFPeTEzWldKcmFYUXRabTl1ZEMxemJXOXZkR2hwYm1jNllXNTBhV0ZzYVdGelpX'
    || 'UTdMVzF2ZWkxdmMzZ3RabTl1ZEMxemJXOXZkR2hwYm1jNlozSmhlWE5qWVd4bGZTNWhjSEI3WkdsemNHeGhlVHBuY21sa08yZHlhV1F0ZEdWdGNHeGhkR1V0'
    || 'WTI5c2RXMXVjenAyWVhJb0xTMXphV1JsWW1GeUxYY3BJRzFwYm0xaGVDZ3dMREZtY2lrN1oyRndPakE3YldsdUxXaGxhV2RvZERveE1EQWxmUzVoY0hBdExX'
    || 'NXZibUYyZTJkeWFXUXRkR1Z0Y0d4aGRHVXRZMjlzZFcxdWN6cHRhVzV0WVhnb01Dd3habklwZlM1emFXUmxlM0J2YzJsMGFXOXVPbk4wYVdOcmVUdDBiM0E2'
    || 'TUR0aGJHbG5iaTF6Wld4bU9uTjBZWEowTzNCaFpHUnBibWM2TWpCd2VDQXhOSEI0SURFNGNIZzdZbTl5WkdWeUxYSnBaMmgwT2pGd2VDQnpiMnhwWkNCMllY'
    || 'SW9MUzFzYVc1bEtUdGlZV05yWjNKdmRXNWtPblpoY2lndExYTjFjbVpoWTJVcE8yMXBiaTFvWldsbmFIUTZNVEF3ZG1oOUxuTnBaR1ZmWDJKeVlXNWtlMlJw'
    || 'YzNCc1lYazZabXhsZUR0aGJHbG5iaTFwZEdWdGN6cGpaVzUwWlhJN1oyRndPamx3ZUR0d1lXUmthVzVuT2pBZ05uQjRJREUyY0hoOUxuTnBaR1ZmWDJKeVlX'
    || 'NWtJSE4yWjN0bWJHVjRPbTV2Ym1WOUxuTnBaR1ZmWDNkdmNtUnRZWEpyZTJadmJuUXRjMmw2WlRveE0zQjRPMlp2Ym5RdGQyVnBaMmgwT2pjd01EdHNaWFIw'
    || 'WlhJdGMzQmhZMmx1WnpvdExqQXhaVzA3WTI5c2IzSTZkbUZ5S0MwdGJtRjJlU2s3YkdsdVpTMW9aV2xuYUhRNk1TNHhOWDB1YzJsa1pWOWZjM1ZpZTJadmJu'
    || 'UXRjMmw2WlRveE1YQjRPMlp2Ym5RdGQyVnBaMmgwT2pVd01EdGpiMnh2Y2pwMllYSW9MUzFrYVcwcE8yeGxkSFJsY2kxemNHRmphVzVuT2k0d01tVnRmUzV1'
    || 'WVhaN1pHbHpjR3hoZVRwbWJHVjRPMlpzWlhndFpHbHlaV04wYVc5dU9tTnZiSFZ0Ymp0bllYQTZNbkI0ZlM1dVlYWmZYMmwwWlcxN1pHbHpjR3hoZVRwbWJH'
    || 'VjRPMkZzYVdkdUxXbDBaVzF6T21ac1pYZ3RjM1JoY25RN1oyRndPamx3ZUR0d1lXUmthVzVuT2pod2VDQTVjSGc3WW05eVpHVnlMWEpoWkdsMWN6bzVjSGc3'
    || 'WW05eVpHVnlPakE3WW1GamEyZHliM1Z1WkRwdWIyNWxPM2RwWkhSb09qRXdNQ1U3ZEdWNGRDMWhiR2xuYmpwc1pXWjBPMk4xY25OdmNqcHdiMmx1ZEdWeU8y'
    || 'TnZiRzl5T25aaGNpZ3RMVzExZEdWa0tUdDBjbUZ1YzJsMGFXOXVPbUpoWTJ0bmNtOTFibVFnTGpFMGN5QjJZWElvTFMxbFlYTmxLU3hqYjJ4dmNpQXVNVFJ6'
    || 'SUhaaGNpZ3RMV1ZoYzJVcE8yWnZiblE2YVc1b1pYSnBkSDB1Ym1GMlgxOXBkR1Z0T21odmRtVnllMkpoWTJ0bmNtOTFibVE2ZG1GeUtDMHRjM1Z5Wm1GalpT'
    || 'MHlLVHRqYjJ4dmNqcDJZWElvTFMxMFpYaDBLWDB1Ym1GMlgxOXBkR1Z0SUhOMlozdG1iR1Y0T201dmJtVTdiV0Z5WjJsdUxYUnZjRG94Y0hoOUxtNWhkbDlm'
    || 'YkdGaVpXeDdabTl1ZEMxemFYcGxPakV5TGpWd2VEdG1iMjUwTFhkbGFXZG9kRG8yTURBN1pHbHpjR3hoZVRwaWJHOWphenRzYVc1bExXaGxhV2RvZERveExq'
    || 'TTFmUzV1WVhaZlgyUmxjMk43Wm05dWRDMXphWHBsT2pFeGNIZzdZMjlzYjNJNmRtRnlLQzB0WkdsdEtUdGthWE53YkdGNU9tSnNiMk5yTzJ4cGJtVXRhR1Zw'
    || 'WjJoME9qRXVNMzB1Ym1GMlgxOXBkR1Z0TFMxdmJudGlZV05yWjNKdmRXNWtPblpoY2lndExXRmpZMlZ1ZEMxM1lYTm9LVHRqYjJ4dmNqcDJZWElvTFMxaFky'
    || 'TmxiblFwZlM1dVlYWmZYMmwwWlcwdExXOXVJQzV1WVhaZlgyeGhZbVZzZTJOdmJHOXlPblpoY2lndExXRmpZMlZ1ZENsOUxtNWhkbDlmYVhSbGJTMHRiMjRn'
    || 'TG01aGRsOWZaR1Z6WTN0amIyeHZjanAyWVhJb0xTMWhZMk5sYm5RcE8yOXdZV05wZEhrNkxqZDlMbTVoZGw5ZlpHOTBlM2RwWkhSb09qWndlRHRvWldsbmFI'
    || 'UTZObkI0TzJKdmNtUmxjaTF5WVdScGRYTTZOVEFsTzIxaGNtZHBiam8xY0hnZ01DQXdJR0YxZEc4N1pteGxlRHB1YjI1bGZTNXVZWFpmWDJSdmRDMHRZbUZr'
    || 'ZTJKaFkydG5jbTkxYm1RNmRtRnlLQzB0WW1Ga0tYMHVibUYyWDE5a2IzUXRMWGRoY201N1ltRmphMmR5YjNWdVpEcDJZWElvTFMxM1lYSnVLWDB1Ym1GMlgx'
    || 'OWtiM1F0TFdsdVptOTdZbUZqYTJkeWIzVnVaRHAyWVhJb0xTMXphM2twZlM1dVlYWmZYMmR5YjNWd2UyMWhjbWRwYmpveE5YQjRJREFnTTNCNE8zQmhaR1Jw'
    || 'Ym1jNk1DQTVjSGc3Wm05dWRDMXphWHBsT2pFeGNIZzdabTl1ZEMxM1pXbG5hSFE2TnpBd08zUmxlSFF0ZEhKaGJuTm1iM0p0T25Wd2NHVnlZMkZ6WlR0c1pY'
    || 'UjBaWEl0YzNCaFkybHVaem91TURSbGJUdGpiMnh2Y2pwMllYSW9MUzF0ZFhSbFpDazdiR2x1WlMxb1pXbG5hSFE2TVM0emZTNXVZWFpmWDJkeWIzVndPbVpw'
    || 'Y25OMExXTm9hV3hrZTIxaGNtZHBiaTEwYjNBNk1YQjRmUzV1WVhaZlgybDBaVzB0TFhOMVludHdZV1JrYVc1bkxXeGxablE2TWpKd2VIMHVjMmxrWlY5Zlpt'
    || 'OXZkSHR0WVhKbmFXNHRkRzl3T2pFNGNIZzdjR0ZrWkdsdVp6b3hNWEI0SURod2VDQXdPMkp2Y21SbGNpMTBiM0E2TVhCNElITnZiR2xrSUhaaGNpZ3RMV3hw'
    || 'Ym1VcE8yWnZiblF0YzJsNlpUb3hNWEI0TzJOdmJHOXlPblpoY2lndExXUnBiU2s3YkdsdVpTMW9aV2xuYUhRNk1TNDBOWDB1YldGcGJudHdZV1JrYVc1bk9q'
    || 'SXljSGdnTWpad2VDQXpNSEI0TzIxcGJpMTNhV1IwYURvd2ZTNWhjSEJmWDJobFlXUjdaR2x6Y0d4aGVUcG1iR1Y0TzJGc2FXZHVMV2wwWlcxek9tWnNaWGd0'
    || 'YzNSaGNuUTdhblZ6ZEdsbWVTMWpiMjUwWlc1ME9uTndZV05sTFdKbGRIZGxaVzQ3WjJGd09qRTRjSGc3YldGeVoybHVMV0p2ZEhSdmJUb3hPSEI0TzJac1pY'
    || 'Z3RkM0poY0RwM2NtRndmUzVoY0hCZlgyaGxZV1ErS250dGFXNHRkMmxrZEdnNk1EdHRZWGd0ZDJsa2RHZzZNVEF3SlgwdVlYQndYMTlvWldGa2NtbG5hSFI3'
    || 'YldsdUxYZHBaSFJvT2pBN2JXRjRMWGRwWkhSb09qRXdNQ1U3WkdsemNHeGhlVHBtYkdWNE8yRnNhV2R1TFdsMFpXMXpPbVpzWlhndGMzUmhjblE3WjJGd09q'
    || 'RXdjSGc3Wm14bGVDMTNjbUZ3T25keVlYQjlMbUZ3Y0Y5ZmFHVmhaQ0JvTVh0dFlYSm5hVzQ2TUR0bWIyNTBMWE5wZW1VNk1qRndlRHRtYjI1MExYZGxhV2Rv'
    || 'ZERvM01EQTdiR1YwZEdWeUxYTndZV05wYm1jNkxTNHdNbVZ0TzJOdmJHOXlPblpoY2lndExXNWhkbmtwTzJ4cGJtVXRhR1ZwWjJoME9qRXVNbjB1WVhCd1gx'
    || 'OXpkV0o3YldGeVoybHVPalZ3ZUNBd0lEQTdabTl1ZEMxemFYcGxPakV5Y0hnN1kyOXNiM0k2ZG1GeUtDMHRiWFYwWldRcGZTNWhjSEJmWDNOMVlpQmpiMlJs'
    || 'ZTJKaFkydG5jbTkxYm1RNmRtRnlLQzB0YzNWeVptRmpaUzB5S1R0aWIzSmtaWEk2TVhCNElITnZiR2xrSUhaaGNpZ3RMV3hwYm1VcE8zQmhaR1JwYm1jNk1Y'
    || 'QjRJRFp3ZUR0aWIzSmtaWEl0Y21Ga2FYVnpPalZ3ZUR0bWIyNTBMWE5wZW1VNk1URndlRHRqYjJ4dmNqcDJZWElvTFMxdVlYWjVLWDB1Y0doaGMyVjdabXhs'
    || 'ZURwdWIyNWxPMlJwYzNCc1lYazZabXhsZUR0bWJHVjRMV1JwY21WamRHbHZianBqYjJ4MWJXNDdZV3hwWjI0dGFYUmxiWE02Wm14bGVDMWxibVE3WjJGd09q'
    || 'aHdlRHR0WVhndGQybGtkR2c2TVRBd0pYMHVjR2hoYzJWZlgzSmhhV3g3WkdsemNHeGhlVHBwYm14cGJtVXRabXhsZUR0aGJHbG5iaTFwZEdWdGN6cHpkSEps'
    || 'ZEdOb08ySnZjbVJsY2pveGNIZ2djMjlzYVdRZ2RtRnlLQzB0YkdsdVpTazdZbTl5WkdWeUxYSmhaR2wxY3pwMllYSW9MUzF5WVdScGRYTXBPMkpoWTJ0bmNt'
    || 'OTFibVE2ZG1GeUtDMHRjM1Z5Wm1GalpTazdiM1psY21ac2IzYzZhR2xrWkdWdU8yMWhlQzEzYVdSMGFEb3hNREFsZlM1d2FHRnpaVjlmWW5SdWV5MTNaV0py'
    || 'YVhRdFlYQndaV0Z5WVc1alpUcHViMjVsT3kxdGIzb3RZWEJ3WldGeVlXNWpaVHB1YjI1bE8yRndjR1ZoY21GdVkyVTZibTl1WlR0aVlXTnJaM0p2ZFc1a09t'
    || 'NXZibVU3WW05eVpHVnlPakE3WW05eVpHVnlMV3hsWm5RNk1YQjRJSE52Ykdsa0lIWmhjaWd0TFd4cGJtVXBPMlJwYzNCc1lYazZabXhsZUR0bWJHVjRMV1Jw'
    || 'Y21WamRHbHZianBqYjJ4MWJXNDdZV3hwWjI0dGFYUmxiWE02Wm14bGVDMXpkR0Z5ZER0bllYQTZNbkI0TzNCaFpHUnBibWM2TjNCNElERXljSGc3WTNWeWMy'
    || 'OXlPbkJ2YVc1MFpYSTdkR1Y0ZEMxaGJHbG5ianBzWldaME8yWnZiblE2YVc1b1pYSnBkRHRqYjJ4dmNqcDJZWElvTFMxdGRYUmxaQ2s3YldsdUxYZHBaSFJv'
    || 'T2pCOUxuQm9ZWE5sWDE5aWRHNDZabWx5YzNRdFkyaHBiR1I3WW05eVpHVnlMV3hsWm5RNk1IMHVjR2hoYzJWZlgySjBianBvYjNabGNudGlZV05yWjNKdmRX'
    || 'NWtPblpoY2lndExYTjFjbVpoWTJVdE1pbDlMbkJvWVhObFgxOWlkRzQ2Wm05amRYTXRkbWx6YVdKc1pYdHZkWFJzYVc1bE9qSndlQ0J6YjJ4cFpDQjJZWElv'
    || 'TFMxaFkyTmxiblFwTzI5MWRHeHBibVV0YjJabWMyVjBPaTB5Y0hoOUxuQm9ZWE5sWDE5c1lXSmxiSHRtYjI1MExYTnBlbVU2TVRGd2VEdG1iMjUwTFhkbGFX'
    || 'ZG9kRG8yTURBN2JHVjBkR1Z5TFhOd1lXTnBibWM2TGpBMFpXMDdkR1Y0ZEMxMGNtRnVjMlp2Y20wNmRYQndaWEpqWVhObE8zZG9hWFJsTFhOd1lXTmxPbTV2'
    || 'ZDNKaGNIMHVjR2hoYzJWZlgyWnBaM1Z5Wlh0bWIyNTBMWE5wZW1VNk1USndlRHRtYjI1MExYZGxhV2RvZERvMU1EQTdkMmhwZEdVdGMzQmhZMlU2Ym05eWJX'
    || 'RnNPMjkyWlhKbWJHOTNMWGR5WVhBNllXNTVkMmhsY21WOUxuQm9ZWE5sWDE5dGIyNWxlWHRtYjI1MExYTnBlbVU2TVRGd2VEdGpiMnh2Y2pwMllYSW9MUzF0'
    || 'ZFhSbFpDazdkMmhwZEdVdGMzQmhZMlU2Ym05M2NtRndmUzV3YUdGelpWOWZZblJ1TFMxamRYSnlaVzUwZTJKaFkydG5jbTkxYm1RNmRtRnlLQzB0WVdOalpX'
    || 'NTBMWGRoYzJncE8yTnZiRzl5T25aaGNpZ3RMVzVoZG5rcGZTNXdhR0Z6WlY5ZlluUnVMUzFqZFhKeVpXNTBJQzV3YUdGelpWOWZiR0ZpWld4N1kyOXNiM0k2'
    || 'ZG1GeUtDMHRZV05qWlc1MEtYMHVjR2hoYzJWZlgySjBiaTB0WTNWeWNtVnVkQ0F1Y0doaGMyVmZYMlpwWjNWeVpYdGpiMnh2Y2pwMllYSW9MUzEwWlhoMEtU'
    || 'dG1iMjUwTFhkbGFXZG9kRG8yTURCOUxuQm9ZWE5sWDE5aWRHNHRMV1J2Ym1VZ0xuQm9ZWE5sWDE5c1lXSmxiQ3d1Y0doaGMyVmZYMkowYmkwdFlXaGxZV1Fn'
    || 'TG5Cb1lYTmxYMTlzWVdKbGJDd3VjR2hoYzJWZlgySjBiaTB0WVdobFlXUWdMbkJvWVhObFgxOW1hV2QxY21WN1kyOXNiM0k2ZG1GeUtDMHRiWFYwWldRcGZT'
    || 'NXdhR0Z6WlY5ZlluUnVMbWx6TFc5d1pXNTdZbUZqYTJkeWIzVnVaRHAyWVhJb0xTMXpkWEptWVdObExUTXBmUzV3YUdGelpWOWZZblJ1TFMxamRYSnlaVzUw'
    || 'TG1sekxXOXdaVzU3WW1GamEyZHliM1Z1WkRwMllYSW9MUzFoWTJObGJuUXRkMkZ6YUNsOUxuQm9ZWE5sWDE5a1pYUmhhV3g3YldGNExYZHBaSFJvT2pRek1I'
    || 'QjRPM1JsZUhRdFlXeHBaMjQ2YkdWbWREdGlZV05yWjNKdmRXNWtPblpoY2lndExYTjFjbVpoWTJVdE1pazdZbTl5WkdWeU9qRndlQ0J6YjJ4cFpDQjJZWElv'
    || 'TFMxc2FXNWxLVHRpYjNKa1pYSXRjbUZrYVhWek9uWmhjaWd0TFhKaFpHbDFjeWs3Y0dGa1pHbHVaem94TUhCNElERXljSGg5TG5Cb1lYTmxYMTlrWlhSaGFX'
    || 'd2djSHR0WVhKbmFXNDZNQ0F3SURad2VEdG1iMjUwTFhOcGVtVTZNVEV1TlhCNE8yeHBibVV0YUdWcFoyaDBPakV1TlgwdWNHaGhjMlZmWDJSbGRHRnBiQ0J3'
    || 'T214aGMzUXRZMmhwYkdSN2JXRnlaMmx1TFdKdmRIUnZiVG93ZlM1d2FHRnpaVjlmWW14MWNtSjdZMjlzYjNJNmRtRnlLQzB0ZEdWNGRDbDlMbkJvWVhObFgx'
    || 'OWlZWE5wYzN0amIyeHZjanAyWVhJb0xTMXRkWFJsWkNsOUxuQm9ZWE5sWDE5aVlYTnBjeUJ6ZEhKdmJtZDdZMjlzYjNJNmRtRnlLQzB0ZEdWNGRDazdabTl1'
    || 'ZEMxM1pXbG5hSFE2TmpBd2ZTNXdhR0Z6WlY5ZmQyaGxjbVY3WTI5c2IzSTZkbUZ5S0MwdFlXTmpaVzUwS1R0bWIyNTBMWGRsYVdkb2REbzJNREI5TG5Cb1lY'
    || 'TmxYMTlvYjNkN1kyOXNiM0k2ZG1GeUtDMHRiWFYwWldRcGZTNXdhR0Z6WlY5ZmFHOTNJR052WkdWN1ltRmphMmR5YjNWdVpEcDJZWElvTFMxemRYSm1ZV05s'
    || 'S1R0aWIzSmtaWEk2TVhCNElITnZiR2xrSUhaaGNpZ3RMV3hwYm1VcE8zQmhaR1JwYm1jNk1YQjRJRFp3ZUR0aWIzSmtaWEl0Y21Ga2FYVnpPalZ3ZUR0bWIy'
    || 'NTBMWE5wZW1VNk1URndlRHRqYjJ4dmNqcDJZWElvTFMxdVlYWjVLVHQzYUdsMFpTMXpjR0ZqWlRwdWIzZHlZWEI5UUcxbFpHbGhLRzFoZUMxM2FXUjBhRG8z'
    || 'TWpCd2VDbDdMbUZ3Y0h0bmNtbGtMWFJsYlhCc1lYUmxMV052YkhWdGJuTTZiV2x1YldGNEtEQXNNV1p5S1gwdWMybGtaWHR3YjNOcGRHbHZianB6ZEdGMGFX'
    || 'TTdiV2x1TFdobGFXZG9kRG93TzNCaFpHUnBibWM2TVRKd2VEdGliM0prWlhJdGNtbG5hSFE2TUR0aWIzSmtaWEl0WW05MGRHOXRPakZ3ZUNCemIyeHBaQ0Iy'
    || 'WVhJb0xTMXNhVzVsS1gwdWMybGtaU0F1Ym1GMmUyWnNaWGd0WkdseVpXTjBhVzl1T25KdmR6dG1iR1Y0TFhkeVlYQTZkM0poY0gwdWMybGtaU0F1Ym1GMlgx'
    || 'OXBkR1Z0ZTNkcFpIUm9PbUYxZEc4N1pteGxlRG94SURFZ01UUXdjSGg5TG5OcFpHVWdMbTVoZGw5ZlozSnZkWEI3Wm14bGVDMWlZWE5wY3pveE1EQWxmUzV6'
    || 'YVdSbFgxOW1iMjkwZTJScGMzQnNZWGs2Ym05dVpYMHViV0ZwYm50d1lXUmthVzVuT2pFMmNIaDlMbUZ3Y0Y5ZmFHVmhaSHRtYkdWNExXUnBjbVZqZEdsdmJq'
    || 'cGpiMngxYlc1OUxuQm9ZWE5sZTJGc2FXZHVMV2wwWlcxek9tWnNaWGd0YzNSaGNuUTdkMmxrZEdnNk1UQXdKWDB1Y0doaGMyVmZYM0poYVd4N2QybGtkR2c2'
    || 'TVRBd0pYMHVjR2hoYzJWZlgySjBibnRtYkdWNE9qRWdNU0F3ZlgwdVozSnBaSHRrYVhOd2JHRjVPbWR5YVdRN1oyRndPakUwY0hnN1ozSnBaQzEwWlcxd2JH'
    || 'RjBaUzFqYjJ4MWJXNXpPbkpsY0dWaGRDaGhkWFJ2TFdacGRDeHRhVzV0WVhnb2JXbHVLRE16TUhCNExERXdNQ1VwTERGbWNpa3BPMkZzYVdkdUxXbDBaVzF6'
    || 'T25OMFlYSjBmUzVpWVc1dVpYSjdZbTl5WkdWeUxYSmhaR2wxY3pvd0lIWmhjaWd0TFhKaFpHbDFjeWtnZG1GeUtDMHRjbUZrYVhWektTQXdPM0JoWkdScGJt'
    || 'YzZPSEI0SURFemNIZzdiV0Z5WjJsdUxXSnZkSFJ2YlRveE1uQjRPMlp2Ym5RdGMybDZaVG94TWk0MWNIZzdabTl1ZEMxM1pXbG5hSFE2TlRBd08yeHBibVV0'
    || 'YUdWcFoyaDBPakV1TkRVN1ltOXlaR1Z5TFd4bFpuUTZNM0I0SUhOdmJHbGtJSFJ5WVc1emNHRnlaVzUwZlM1aVlXNXVaWEl0TFhOaGJYQnNaWHRpWVdOcloz'
    || 'SnZkVzVrT2lObU5UbGxNR0l3WlR0aWIzSmtaWEl0YkdWbWRDMWpiMnh2Y2pwMllYSW9MUzEzWVhKdUtUdGpiMnh2Y2pvak9HRTFOakF3TzJadmJuUXRkMlZw'
    || 'WjJoME9qWXdNSDB1WW1GdWJtVnlMUzFtWVdsc2UySmhZMnRuY205MWJtUTZJMlU0TURBeFl6QmtPMkp2Y21SbGNpMXNaV1owTFdOdmJHOXlPblpoY2lndExX'
    || 'SmhaQ2s3WTI5c2IzSTZJMkV6TURBeE5EdG1iMjUwTFhkbGFXZG9kRG8yTURCOUxtSmhibTVsY2kwdGFXNW1iM3RpWVdOclozSnZkVzVrT2lNd01EZzBaRFF3'
    || 'WkR0aWIzSmtaWEl0YkdWbWRDMWpiMnh2Y2pwMllYSW9MUzFoWTJObGJuUXBPMk52Ykc5eU9pTXdNRFZoT1RGOUxtTmhjbVI3WW1GamEyZHliM1Z1WkRwMllY'
    || 'SW9MUzF6ZFhKbVlXTmxLVHRpYjNKa1pYSTZNWEI0SUhOdmJHbGtJSFpoY2lndExXeHBibVVwTzJKdmNtUmxjaTF5WVdScGRYTTZkbUZ5S0MwdGNtRmthWFZ6'
    || 'S1R0d1lXUmthVzVuT2pFMmNIZ2dNVGh3ZUNBeE9IQjRPMkp2ZUMxemFHRmtiM2M2ZG1GeUtDMHRjMmd0WTJGeVpDazdkSEpoYm5OcGRHbHZianBpYjNndGMy'
    || 'aGhaRzkzSUM0eWN5QjJZWElvTFMxbFlYTmxLWDB1WTJGeVpEcG9iM1psY250aWIzZ3RjMmhoWkc5M09uWmhjaWd0TFhOb0xXMWtLWDB1WTJGeVpDMHRkMmxr'
    || 'Wlh0bmNtbGtMV052YkhWdGJqb3hJQzhnTFRGOUxtTmhjbVJmWDJobFlXUjdiV0Z5WjJsdUxXSnZkSFJ2YlRveE5IQjRmUzVqWVhKa1gxOW9aV0ZrSUdneWUy'
    || 'MWhjbWRwYmpvd08yWnZiblF0YzJsNlpUb3hNWEI0TzJadmJuUXRkMlZwWjJoME9qY3dNRHQwWlhoMExYUnlZVzV6Wm05eWJUcDFjSEJsY21OaGMyVTdiR1Yw'
    || 'ZEdWeUxYTndZV05wYm1jNkxqQTBaVzA3WTI5c2IzSTZkbUZ5S0MwdFpHbHRLWDB1WTJGeVpGOWZhR2x1ZEh0dFlYSm5hVzQ2Tm5CNElEQWdNRHRtYjI1MExY'
    || 'TnBlbVU2TVRKd2VEdGpiMnh2Y2pwMllYSW9MUzF0ZFhSbFpDazdiR2x1WlMxb1pXbG5hSFE2TVM0MWZTNXViM1JsZTIxaGNtZHBiam93SURBZ09YQjRPMlp2'
    || 'Ym5RdGMybDZaVG94TTNCNE8yeHBibVV0YUdWcFoyaDBPakV1Tmp0amIyeHZjanAyWVhJb0xTMXRkWFJsWkNsOUxtNXZkR1U2YkdGemRDMWphR2xzWkh0dFlY'
    || 'Sm5hVzR0WW05MGRHOXRPakI5TG5OMVludHRZWEpuYVc0Nk1UaHdlQ0F3SURsd2VEdG1iMjUwTFhOcGVtVTZNVEZ3ZUR0bWIyNTBMWGRsYVdkb2REbzNNREE3'
    || 'ZEdWNGRDMTBjbUZ1YzJadmNtMDZkWEJ3WlhKallYTmxPMnhsZEhSbGNpMXpjR0ZqYVc1bk9pNHdOR1Z0TzJOdmJHOXlPblpoY2lndExXUnBiU2w5TG5OMFlY'
    || 'UXRjbTkzZTJScGMzQnNZWGs2WjNKcFpEdG5ZWEE2TVRGd2VEdG5jbWxrTFhSbGJYQnNZWFJsTFdOdmJIVnRibk02Y21Wd1pXRjBLR0YxZEc4dFptbDBMRzFw'
    || 'Ym0xaGVDZ3hORGh3ZUN3eFpuSXBLWDB1YzNSaGRIdGlZV05yWjNKdmRXNWtPblpoY2lndExYTjFjbVpoWTJVcE8ySnZjbVJsY2pveGNIZ2djMjlzYVdRZ2Rt'
    || 'RnlLQzB0YkdsdVpTazdZbTl5WkdWeUxYSmhaR2wxY3pwMllYSW9MUzF5WVdScGRYTXBPM0JoWkdScGJtYzZNVE53ZUNBeE5YQjRJREUwY0hoOUxuTjBZWFJm'
    || 'WDJ4aFltVnNlMlp2Ym5RdGMybDZaVG94TVhCNE8yWnZiblF0ZDJWcFoyaDBPall3TUR0MFpYaDBMWFJ5WVc1elptOXliVHAxY0hCbGNtTmhjMlU3YkdWMGRH'
    || 'VnlMWE53WVdOcGJtYzZMakEwWlcwN1kyOXNiM0k2ZG1GeUtDMHRaR2x0S1gwdWMzUmhkRjlmZG1Gc2RXVjdabTl1ZEMxemFYcGxPak13Y0hnN1ptOXVkQzEz'
    || 'WldsbmFIUTZOekF3TzIxaGNtZHBiaTEwYjNBNk5IQjRPMnhwYm1VdGFHVnBaMmgwT2pFdU1EZzdiR1YwZEdWeUxYTndZV05wYm1jNkxTNHdNalZsYlR0bWIy'
    || 'NTBMWFpoY21saGJuUXRiblZ0WlhKcFl6cDBZV0oxYkdGeUxXNTFiWE03WTI5c2IzSTZkbUZ5S0MwdGJtRjJlU2w5TG5OMFlYUmZYM1Z1YVhSN1ptOXVkQzF6'
    || 'YVhwbE9qRTBjSGc3WTI5c2IzSTZkbUZ5S0MwdFpHbHRLVHR0WVhKbmFXNHRiR1ZtZERvemNIZzdabTl1ZEMxM1pXbG5hSFE2TlRBd08yeGxkSFJsY2kxemNH'
    || 'RmphVzVuT2pCOUxuTjBZWFJmWDNOMVludG1iMjUwTFhOcGVtVTZNVEV1TlhCNE8yTnZiRzl5T25aaGNpZ3RMVzExZEdWa0tUdHRZWEpuYVc0dGRHOXdPalJ3'
    || 'ZUR0c2FXNWxMV2hsYVdkb2REb3hMalI5TG5OMFlYUXRMV2R2YjJRZ0xuTjBZWFJmWDNaaGJIVmxlMk52Ykc5eU9uWmhjaWd0TFdkdmIyUXBmUzV6ZEdGMExT'
    || 'MTNZWEp1SUM1emRHRjBYMTkyWVd4MVpYdGpiMnh2Y2pvallqZzNNekJoZlM1emRHRjBMUzFpWVdRZ0xuTjBZWFJmWDNaaGJIVmxlMk52Ykc5eU9uWmhjaWd0'
    || 'TFdKaFpDbDlMbk4wWVhRdExXZHZiMlI3WW05eVpHVnlMV052Ykc5eU9pTXhObUV6TkdFMFpEdGlZV05yWjNKdmRXNWtPblpoY2lndExXZHZiMlF0ZDJGemFD'
    || 'bDlMbk4wWVhRdExYZGhjbTU3WW05eVpHVnlMV052Ykc5eU9pTm1OVGxsTUdJMU56dGlZV05yWjNKdmRXNWtPblpoY2lndExYZGhjbTR0ZDJGemFDbDlMbk4w'
    || 'WVhRdExXSmhaSHRpYjNKa1pYSXRZMjlzYjNJNkkyVTRNREF4WXpRM08ySmhZMnRuY205MWJtUTZkbUZ5S0MwdFltRmtMWGRoYzJncGZTNTBZV0pzWlMxM2Nt'
    || 'RndlMjkyWlhKbWJHOTNMWGc2WVhWMGJ6dHRZWEpuYVc0dGRHOXdPakV5Y0hnN1ltRmphMmR5YjNWdVpEcHNhVzVsWVhJdFozSmhaR2xsYm5Rb2RHOGdjbWxu'
    || 'YUhRc2RtRnlLQzB0YzNWeVptRmpaU2tzY21kaVlTZ3lOVFVzTWpVMUxESTFOU3d3S1NrZ2JHVm1kQ0F2SURJd2NIZ2dNVEF3SlNCdWJ5MXlaWEJsWVhRZ2JH'
    || 'OWpZV3dzYkdsdVpXRnlMV2R5WVdScFpXNTBLSFJ2SUd4bFpuUXNkbUZ5S0MwdGMzVnlabUZqWlNrc2NtZGlZU2d5TlRVc01qVTFMREkxTlN3d0tTa2djbWxu'
    || 'YUhRZ0x5QXlNSEI0SURFd01DVWdibTh0Y21Wd1pXRjBJR3h2WTJGc0xHeHBibVZoY2kxbmNtRmthV1Z1ZENoMGJ5QnlhV2RvZEN3ak1URXhNVEV4TVdFc0l6'
    || 'RXhNVEFwSUd4bFpuUWdMeUF4TVhCNElERXdNQ1VnYm04dGNtVndaV0YwSUhOamNtOXNiQ3hzYVc1bFlYSXRaM0poWkdsbGJuUW9kRzhnYkdWbWRDd2pNVEV4'
    || 'TVRFeE1XRXNJekV4TVRBcElISnBaMmgwSUM4Z01URndlQ0F4TURBbElHNXZMWEpsY0dWaGRDQnpZM0p2Ykd4OWRHRmliR1Y3ZDJsa2RHZzZNVEF3SlR0aWIz'
    || 'SmtaWEl0WTI5c2JHRndjMlU2WTI5c2JHRndjMlU3Wm05dWRDMXphWHBsT2pFeUxqVndlSDEwYUdWaFpDQjBhSHQwWlhoMExXRnNhV2R1T214bFpuUTdabTl1'
    || 'ZEMxemFYcGxPakV4Y0hnN1ptOXVkQzEzWldsbmFIUTZOekF3TzNSbGVIUXRkSEpoYm5ObWIzSnRPblZ3Y0dWeVkyRnpaVHRzWlhSMFpYSXRjM0JoWTJsdVp6'
    || 'b3VNRFJsYlR0amIyeHZjanAyWVhJb0xTMWthVzBwTzNCaFpHUnBibWM2TjNCNElERXdjSGc3WW05eVpHVnlMV0p2ZEhSdmJUb3hjSGdnYzI5c2FXUWdkbUZ5'
    || 'S0MwdGJHbHVaU2s3WW1GamEyZHliM1Z1WkRwMllYSW9MUzF6ZFhKbVlXTmxMVElwTzNkb2FYUmxMWE53WVdObE9tNXZkM0poY0R0d2IzTnBkR2x2YmpwemRH'
    || 'bGphM2s3ZEc5d09qQjlkR2hsWVdRZ2RHZzZabWx5YzNRdFkyaHBiR1I3WW05eVpHVnlMWFJ2Y0Mxc1pXWjBMWEpoWkdsMWN6bzNjSGg5ZEdobFlXUWdkR2c2'
    || 'YkdGemRDMWphR2xzWkh0aWIzSmtaWEl0ZEc5d0xYSnBaMmgwTFhKaFpHbDFjem8zY0hoOWRHSnZaSGtnZEdSN2NHRmtaR2x1WnpvNGNIZ2dNVEJ3ZUR0aWIz'
    || 'SmtaWEl0WW05MGRHOXRPakZ3ZUNCemIyeHBaQ0IyWVhJb0xTMXNhVzVsS1R0amIyeHZjanAyWVhJb0xTMTBaWGgwS1R0MlpYSjBhV05oYkMxaGJHbG5ianAw'
    || 'YjNCOWRHSnZaSGtnZEhJNmJHRnpkQzFqYUdsc1pDQjBaSHRpYjNKa1pYSXRZbTkwZEc5dE9qQjlkR0p2WkhrZ2RISTZhRzkyWlhJZ2RHUjdZbUZqYTJkeWIz'
    || 'VnVaRHAyWVhJb0xTMXpkWEptWVdObExUSXBmWFJrTG5Jc2RHZ3VjbnQwWlhoMExXRnNhV2R1T25KcFoyaDBPMlp2Ym5RdGRtRnlhV0Z1ZEMxdWRXMWxjbWxq'
    || 'T25SaFluVnNZWEl0Ym5WdGMzMHViblZzYkh0amIyeHZjanAyWVhJb0xTMWthVzBwTzJadmJuUXRjM1I1YkdVNmFYUmhiR2xqZlM1MFlXSnNaUzF0YjNKbGUy'
    || 'MWhjbWRwYmpvNWNIZ2dNQ0F3TzJadmJuUXRjMmw2WlRveE1TNDFjSGc3WTI5c2IzSTZkbUZ5S0MwdFpHbHRLWDB1WW1GeWMzdGthWE53YkdGNU9tWnNaWGc3'
    || 'Wm14bGVDMWthWEpsWTNScGIyNDZZMjlzZFcxdU8yZGhjRG80Y0hnN2JXRnlaMmx1TFhSdmNEbzBjSGg5TG1KaGNudGthWE53YkdGNU9tZHlhV1E3WjNKcFpD'
    || 'MTBaVzF3YkdGMFpTMWpiMngxYlc1ek9tMXBibTFoZUNneE5EQndlQ3d6TUNVcElERm1jaUEzT0hCNE8yRnNhV2R1TFdsMFpXMXpPbU5sYm5SbGNqdG5ZWEE2'
    || 'TVRGd2VEdG1iMjUwTFhOcGVtVTZNVEp3ZUgwdVltRnlYMTlzWVdKbGJIdGpiMnh2Y2pwMllYSW9MUzF0ZFhSbFpDazdabTl1ZEMxM1pXbG5hSFE2TlRBd08y'
    || 'eHBibVV0YUdWcFoyaDBPakV1TXp0dmRtVnlabXh2ZHkxM2NtRndPbUZ1ZVhkb1pYSmxPM2R2Y21RdFluSmxZV3M2WW5KbFlXc3RkMjl5WkR0a2FYTndiR0Y1'
    || 'T2kxM1pXSnJhWFF0WW05NE95MTNaV0pyYVhRdFltOTRMVzl5YVdWdWREcDJaWEowYVdOaGJEc3RkMlZpYTJsMExXeHBibVV0WTJ4aGJYQTZNanR2ZG1WeVpt'
    || 'eHZkenBvYVdSa1pXNTlMbUpoY2w5ZmRISmhZMnQ3WW1GamEyZHliM1Z1WkRwMllYSW9MUzF6ZFhKbVlXTmxMVE1wTzJKdmNtUmxjaTF5WVdScGRYTTZOWEI0'
    || 'TzJobGFXZG9kRG94T0hCNE8yOTJaWEptYkc5M09taHBaR1JsYm4wdVltRnlYMTltYVd4c2UyaGxhV2RvZERveE1EQWxPMkpoWTJ0bmNtOTFibVE2ZG1GeUtD'
    || 'MHRZV05qWlc1MEtUdGliM0prWlhJdGNtRmthWFZ6T2pWd2VIMHVZbUZ5WDE5bWFXeHNMUzFuYjI5a2UySmhZMnRuY205MWJtUTZkbUZ5S0MwdFoyOXZaQ2w5'
    || 'TG1KaGNsOWZabWxzYkMwdGQyRnlibnRpWVdOclozSnZkVzVrT25aaGNpZ3RMWGRoY200cGZTNWlZWEpmWDJacGJHd3RMV0poWkh0aVlXTnJaM0p2ZFc1a09u'
    || 'WmhjaWd0TFdKaFpDbDlMbUpoY2w5ZmRtRnNkV1Y3ZEdWNGRDMWhiR2xuYmpweWFXZG9kRHRtYjI1MExYWmhjbWxoYm5RdGJuVnRaWEpwWXpwMFlXSjFiR0Z5'
    || 'TFc1MWJYTTdZMjlzYjNJNmRtRnlLQzB0ZEdWNGRDazdabTl1ZEMxM1pXbG5hSFE2TmpBd2ZTNXRaWFJsY250d2IzTnBkR2x2YmpweVpXeGhkR2wyWlR0aVlX'
    || 'TnJaM0p2ZFc1a09uWmhjaWd0TFhOMWNtWmhZMlV0TXlrN1ltOXlaR1Z5TFhKaFpHbDFjem8xY0hnN2FHVnBaMmgwT2pJd2NIZzdiM1psY21ac2IzYzZhR2xr'
    || 'WkdWdU8yMXBiaTEzYVdSMGFEbzVObkI0ZlM1dFpYUmxjbDlmWm1sc2JIdG9aV2xuYUhRNk1UQXdKVHRpWVdOclozSnZkVzVrT25aaGNpZ3RMV0ZqWTJWdWRD'
    || 'bDlMbTFsZEdWeVgxOW1hV3hzTFMxbmIyOWtlMkpoWTJ0bmNtOTFibVE2ZG1GeUtDMHRaMjl2WkNsOUxtMWxkR1Z5WDE5bWFXeHNMUzEzWVhKdWUySmhZMnRu'
    || 'Y205MWJtUTZkbUZ5S0MwdGQyRnliaWw5TG0xbGRHVnlYMTltYVd4c0xTMWlZV1I3WW1GamEyZHliM1Z1WkRwMllYSW9MUzFpWVdRcGZTNXRaWFJsY2w5ZmRH'
    || 'VjRkSHR3YjNOcGRHbHZianBoWW5OdmJIVjBaVHQwYjNBNk1EdHlhV2RvZERvd08ySnZkSFJ2YlRvd08yeGxablE2TUR0a2FYTndiR0Y1T21ac1pYZzdZV3hw'
    || 'WjI0dGFYUmxiWE02WTJWdWRHVnlPMnAxYzNScFpua3RZMjl1ZEdWdWREcGpaVzUwWlhJN1ptOXVkQzF6YVhwbE9qRXhjSGc3Wm05dWRDMTNaV2xuYUhRNk56'
    || 'QXdPMk52Ykc5eU9uWmhjaWd0TFc1aGRua3BPMlp2Ym5RdGRtRnlhV0Z1ZEMxdWRXMWxjbWxqT25SaFluVnNZWEl0Ym5WdGMzMHViV1YwWlhJdGNtOTNlMlJw'
    || 'YzNCc1lYazZabXhsZUR0bWJHVjRMV1JwY21WamRHbHZianBqYjJ4MWJXNDdaMkZ3T2pad2VEdHRZWEpuYVc0Nk5IQjRJREFnTVRSd2VIMHViV1YwWlhJdGNt'
    || 'OTNYMTlvWldGa2UyUnBjM0JzWVhrNlpteGxlRHRoYkdsbmJpMXBkR1Z0Y3pwaVlYTmxiR2x1WlR0cWRYTjBhV1o1TFdOdmJuUmxiblE2YzNCaFkyVXRZbVYw'
    || 'ZDJWbGJqdG5ZWEE2TVRKd2VEdG1iMjUwTFhOcGVtVTZNVEp3ZUgwdWJXVjBaWEl0Y205M1gxOXNZV0psYkh0amIyeHZjanAyWVhJb0xTMXRkWFJsWkNrN1pt'
    || 'OXVkQzEzWldsbmFIUTZOVEF3ZlM1dFpYUmxjaTF5YjNkZlgzWmhiSFZsZTJOdmJHOXlPblpoY2lndExYUmxlSFFwTzJadmJuUXRkMlZwWjJoME9qWXdNRHRt'
    || 'YjI1MExYWmhjbWxoYm5RdGJuVnRaWEpwWXpwMFlXSjFiR0Z5TFc1MWJYTTdkMmhwZEdVdGMzQmhZMlU2Ym05M2NtRndmUzV0WlhSbGNpMXliM2RmWDI5bWUy'
    || 'TnZiRzl5T25aaGNpZ3RMVzExZEdWa0tUdG1iMjUwTFhkbGFXZG9kRG8wTURBN2JXRnlaMmx1TFd4bFpuUTZOM0I0TzJadmJuUXRjMmw2WlRveE1YQjRPMnhs'
    || 'ZEhSbGNpMXpjR0ZqYVc1bk9pNHdNV1Z0ZlM1dFpYUmxjaTF5YjNjZ0xtMWxkR1Z5ZTJobGFXZG9kRG94TUhCNE8ySnZjbVJsY2kxeVlXUnBkWE02TTNCNE8y'
    || 'MXBiaTEzYVdSMGFEb3dmUzV0WlhSbGNpMHRZMlZzYkh0b1pXbG5hSFE2TVRkd2VEdGliM0prWlhJdGNtRmthWFZ6T2pOd2VEdHRhVzR0ZDJsa2RHZzZOemh3'
    || 'ZUgwdWIzWnNlMlJwYzNCc1lYazZaM0pwWkR0bmNtbGtMWFJsYlhCc1lYUmxMV052YkhWdGJuTTZiV2x1YldGNEtEQXNNV1p5S1NCaGRYUnZPMmRoY0RveU1u'
    || 'QjRPMkZzYVdkdUxXbDBaVzF6T21ObGJuUmxjanR0WVhKbmFXNHRkRzl3T2pSd2VIMHViM1pzWDE5bWFXZDFjbVY3WkdsemNHeGhlVHBtYkdWNE8yWnNaWGd0'
    || 'WkdseVpXTjBhVzl1T21OdmJIVnRianRuWVhBNk1UWndlRHR0YVc0dGQybGtkR2c2TUgwdWIzWnNYMTl6YVdSbGUyMXBiaTEzYVdSMGFEb3dmUzV2ZG14Zlgy'
    || 'aGxZV1I3WkdsemNHeGhlVHBtYkdWNE8yRnNhV2R1TFdsMFpXMXpPbUpoYzJWc2FXNWxPMnAxYzNScFpua3RZMjl1ZEdWdWREcHpjR0ZqWlMxaVpYUjNaV1Z1'
    || 'TzJkaGNEb3hNbkI0TzJadmJuUXRjMmw2WlRveE1uQjRPMjFoY21kcGJpMWliM1IwYjIwNk5YQjRmUzV2ZG14ZlgyNWhiV1Y3WTI5c2IzSTZkbUZ5S0MwdGJY'
    || 'VjBaV1FwTzJadmJuUXRkMlZwWjJoME9qVXdNSDB1YjNac1gxOXVlMk52Ykc5eU9uWmhjaWd0TFc1aGRua3BPMlp2Ym5RdGQyVnBaMmgwT2pjd01EdG1iMjUw'
    || 'TFhaaGNtbGhiblF0Ym5WdFpYSnBZenAwWVdKMWJHRnlMVzUxYlhNN1ptOXVkQzF6YVhwbE9qRTFjSGg5TG05MmJGOWZkSEpoWTJ0N2FHVnBaMmgwT2pJeWNI'
    || 'ZzdZbUZqYTJkeWIzVnVaRHAyWVhJb0xTMXpkWEptWVdObExUTXBPMkp2Y21SbGNpMXlZV1JwZFhNNk0zQjRPMjkyWlhKbWJHOTNPbWhwWkdSbGJqdHRhVzR0'
    || 'ZDJsa2RHZzZNM0I0ZlM1dmRteGZYMkp2ZEdoN2FHVnBaMmgwT2pFd01DVTdZbUZqYTJkeWIzVnVaRHAyWVhJb0xTMWhZMk5sYm5RcE8ySnZjbVJsY2kxeVlX'
    || 'UnBkWE02TTNCNElEQWdNQ0F6Y0hoOUxtOTJiRjlmY21GMFpYdHRZWEpuYVc0dGRHOXdPalZ3ZUR0bWIyNTBMWE5wZW1VNk1URndlRHRqYjJ4dmNqcDJZWElv'
    || 'TFMxdGRYUmxaQ2s3Wm05dWRDMTJZWEpwWVc1MExXNTFiV1Z5YVdNNmRHRmlkV3hoY2kxdWRXMXpmUzV2ZG14ZlgyMXBaSHRtYkdWNE9tNXZibVU3ZEdWNGRD'
    || 'MWhiR2xuYmpweWFXZG9kRHR3WVdSa2FXNW5MV3hsWm5RNk1qQndlRHRpYjNKa1pYSXRiR1ZtZERveGNIZ2djMjlzYVdRZ2RtRnlLQzB0YkdsdVpTbDlMbTky'
    || 'YkY5ZmJXbGtMVzU3Wm05dWRDMXphWHBsT2pNd2NIZzdabTl1ZEMxM1pXbG5hSFE2TnpBd08yeHBibVV0YUdWcFoyaDBPakV1TURVN1kyOXNiM0k2ZG1GeUtD'
    || 'MHRZV05qWlc1MEtUdHNaWFIwWlhJdGMzQmhZMmx1WnpvdExqQXlOV1Z0TzJadmJuUXRkbUZ5YVdGdWRDMXVkVzFsY21sak9uUmhZblZzWVhJdGJuVnRjMzB1'
    || 'YjNac1gxOXRhV1F0YkdGaWUyWnZiblF0YzJsNlpUb3hNWEI0TzJOdmJHOXlPblpoY2lndExXMTFkR1ZrS1R0dFlYSm5hVzR0ZEc5d09qVndlRHRzYVc1bExX'
    || 'aGxhV2RvZERveExqTTFmVUJ0WldScFlTaHRZWGd0ZDJsa2RHZzZPVEF3Y0hncGV5NXZkbXg3WjNKcFpDMTBaVzF3YkdGMFpTMWpiMngxYlc1ek9tMXBibTFo'
    || 'ZUNnd0xERm1jaWw5TG05MmJGOWZiV2xrZTNSbGVIUXRZV3hwWjI0NmJHVm1kRHR3WVdSa2FXNW5PakV5Y0hnZ01DQXdPMkp2Y21SbGNpMXNaV1owT2pBN1lt'
    || 'OXlaR1Z5TFhSdmNEb3hjSGdnYzI5c2FXUWdkbUZ5S0MwdGJHbHVaU2w5ZlM1d2FXeHNlMlJwYzNCc1lYazZhVzVzYVc1bExXSnNiMk5yTzJadmJuUXRjMmw2'
    || 'WlRveE1YQjRPMlp2Ym5RdGQyVnBaMmgwT2pjd01EdHdZV1JrYVc1bk9qSndlQ0E0Y0hnN1ltOXlaR1Z5TFhKaFpHbDFjem81T1Rsd2VEdGliM0prWlhJNk1Y'
    || 'QjRJSE52Ykdsa0lIWmhjaWd0TFd4cGJtVXRNaWs3WTI5c2IzSTZkbUZ5S0MwdGJYVjBaV1FwTzJ4bGRIUmxjaTF6Y0dGamFXNW5PaTR3TW1WdE8zZG9hWFJs'
    || 'TFhOd1lXTmxPbTV2ZDNKaGNIMHVjR2xzYkMwdFoyOXZaSHRqYjJ4dmNqcDJZWElvTFMxbmIyOWtLVHRpYjNKa1pYSXRZMjlzYjNJNkl6RTJZVE0wWVRZMk8y'
    || 'SmhZMnRuY205MWJtUTZkbUZ5S0MwdFoyOXZaQzEzWVhOb0tYMHVjR2xzYkMwdGQyRnlibnRqYjJ4dmNqb2pZVGcyWVRBMU8ySnZjbVJsY2kxamIyeHZjam9q'
    || 'WmpVNVpUQmlOek03WW1GamEyZHliM1Z1WkRwMllYSW9MUzEzWVhKdUxYZGhjMmdwZlM1d2FXeHNMUzFpWVdSN1kyOXNiM0k2ZG1GeUtDMHRZbUZrS1R0aWIz'
    || 'SmtaWEl0WTI5c2IzSTZJMlU0TURBeFl6WXhPMkpoWTJ0bmNtOTFibVE2ZG1GeUtDMHRZbUZrTFhkaGMyZ3BmUzV3WVdseWUySnZjbVJsY2pveGNIZ2djMjlz'
    || 'YVdRZ2RtRnlLQzB0YkdsdVpTazdZbTl5WkdWeUxYSmhaR2wxY3pvNGNIZzdjR0ZrWkdsdVp6b3hNWEI0SURFemNIZ2dNVEp3ZUR0aVlXTnJaM0p2ZFc1a09u'
    || 'WmhjaWd0TFhOMWNtWmhZMlVwTzIxaGNtZHBiaTFpYjNSMGIyMDZNVEJ3ZUgwdWNHRnBjbDlmYUdWaFpIdGthWE53YkdGNU9tWnNaWGc3WVd4cFoyNHRhWFJs'
    || 'YlhNNlkyVnVkR1Z5TzJkaGNEb3hNSEI0TzJac1pYZ3RkM0poY0RwM2NtRndPMjFoY21kcGJpMWliM1IwYjIwNk9YQjRmUzV3WVdseVgxOXBaSE43Wm05dWRD'
    || 'MXphWHBsT2pFeExqVndlRHRqYjJ4dmNqcDJZWElvTFMxdGRYUmxaQ2s3Wm05dWRDMTNaV2xuYUhRNk5UQXdPMjkyWlhKbWJHOTNMWGR5WVhBNllXNTVkMmhs'
    || 'Y21WOUxuQmhhWEpmWDNaemUyTnZiRzl5T25aaGNpZ3RMV1JwYlNrN2NHRmtaR2x1Wnpvd0lETndlSDB1Y0dGcGNsOWZjbTkzYzN0a2FYTndiR0Y1T21ac1pY'
    || 'ZzdabXhsZUMxa2FYSmxZM1JwYjI0NlkyOXNkVzF1TzJkaGNEb3hjSGg5TG5CaGFYSmZYM0p2ZDN0a2FYTndiR0Y1T21keWFXUTdaM0pwWkMxMFpXMXdiR0Yw'
    || 'WlMxamIyeDFiVzV6T2pZeWNIZ2diV2x1YldGNEtEQXNNV1p5S1NBeE9IQjRJRzFwYm0xaGVDZ3dMREZtY2lrN1oyRndPamx3ZUR0aGJHbG5iaTFwZEdWdGN6'
    || 'cGlZWE5sYkdsdVpUdG1iMjUwTFhOcGVtVTZNVEp3ZUR0d1lXUmthVzVuT2pSd2VDQTJjSGc3WW05eVpHVnlMWEpoWkdsMWN6bzBjSGg5TG5CaGFYSmZYMnho'
    || 'WW1Wc2UyWnZiblF0YzJsNlpUb3hNWEI0TzJadmJuUXRkMlZwWjJoME9qWXdNRHQwWlhoMExYUnlZVzV6Wm05eWJUcDFjSEJsY21OaGMyVTdiR1YwZEdWeUxY'
    || 'TndZV05wYm1jNkxqQTBaVzA3WTI5c2IzSTZkbUZ5S0MwdFpHbHRLWDB1Y0dGcGNsOWZkbUZzZTI5MlpYSm1iRzkzTFhkeVlYQTZZVzU1ZDJobGNtVTdZMjlz'
    || 'YjNJNmRtRnlLQzB0ZEdWNGRDbDlMbkJoYVhKZlgyMWhjbXQ3ZEdWNGRDMWhiR2xuYmpwalpXNTBaWEk3Wm05dWRDMTNaV2xuYUhRNk56QXdPMlp2Ym5RdGRt'
    || 'RnlhV0Z1ZEMxdWRXMWxjbWxqT25SaFluVnNZWEl0Ym5WdGMzMHVjR0ZwY2w5ZmNtOTNMUzFrYVdabWUySmhZMnRuY205MWJtUTZkbUZ5S0MwdGQyRnliaTEz'
    || 'WVhOb0tYMHVjR0ZwY2w5ZmNtOTNMUzFrYVdabUlDNXdZV2x5WDE5dFlYSnJlMk52Ykc5eU9pTmhPRFpoTURWOUxuQmhhWEpmWDNKdmR5MHRjMkZ0WlNBdWNH'
    || 'RnBjbDlmYldGeWEzdGpiMnh2Y2pwMllYSW9MUzFrYVcwcGZTNXViM1JsYzN0dFlYSm5hVzQ2TUR0d1lXUmthVzVuTFd4bFpuUTZNVGx3ZUgwdWJtOTBaWE1n'
    || 'YkdsN2JXRnlaMmx1T2pBZ01DQXhNSEI0TzJ4cGJtVXRhR1ZwWjJoME9qRXVOanRqYjJ4dmNqcDJZWElvTFMxdGRYUmxaQ2s3Wm05dWRDMXphWHBsT2pFeUxq'
    || 'VndlSDB1Ym05MFpYTWdiR2tnYzNSeWIyNW5lMk52Ykc5eU9uWmhjaWd0TFhSbGVIUXBPMlp2Ym5RdGQyVnBaMmgwT2pZd01IMHVibTkwWlhNZ2JHazZiR0Z6'
    || 'ZEMxamFHbHNaSHR0WVhKbmFXNHRZbTkwZEc5dE9qQjlMbTV2ZEdWeklHTnZaR1Y3WW1GamEyZHliM1Z1WkRwMllYSW9MUzF6ZFhKbVlXTmxMVElwTzJKdmNt'
    || 'Umxjam94Y0hnZ2MyOXNhV1FnZG1GeUtDMHRiR2x1WlNrN2NHRmtaR2x1WnpveGNIZ2dOWEI0TzJKdmNtUmxjaTF5WVdScGRYTTZOSEI0TzJadmJuUXRjMmw2'
    || 'WlRveE1TNDFjSGc3WTI5c2IzSTZkbUZ5S0MwdGJtRjJlU2w5TG5CaGJtVnNMV1Z5Y205eWUySmhZMnRuY205MWJtUTZkbUZ5S0MwdFltRmtMWGRoYzJncE8y'
    || 'SnZjbVJsY2pveGNIZ2djMjlzYVdRZ2NtZGlZU2d5TXpJc01Dd3lPQ3d1TXpJcE8ySnZjbVJsY2kxeVlXUnBkWE02ZG1GeUtDMHRjbUZrYVhWektUdHdZV1Jr'
    || 'YVc1bk9qRXhjSGdnTVROd2VEdG1iMjUwTFhOcGVtVTZNVEl1TlhCNGZTNXdZVzVsYkMxbGNuSnZjaUJ6ZEhKdmJtZDdaR2x6Y0d4aGVUcGliRzlqYXp0amIy'
    || 'eHZjanAyWVhJb0xTMWlZV1FwTzIxaGNtZHBiaTFpYjNSMGIyMDZOWEI0ZlM1d1lXNWxiQzFsY25KdmNpQmpiMlJsZTJOdmJHOXlPaU00WmpBd01UUTdkMjl5'
    || 'WkMxaWNtVmhhenBpY21WaGF5MTNiM0prTzNkb2FYUmxMWE53WVdObE9uQnlaUzEzY21Gd08yWnZiblF0YzJsNlpUb3hNUzQxY0hoOUxuQmhibVZzTFdWdGNI'
    || 'UjVMQzV3WVc1bGJDMXRhWE56YVc1bmUyTnZiRzl5T25aaGNpZ3RMVzExZEdWa0tUdG1iMjUwTFhOcGVtVTZNVEl1TlhCNE8yMWhjbWRwYmpvd2ZTNXdZVzVs'
    || 'YkMxMGNuVnVZM3RpWVdOclozSnZkVzVrT25aaGNpZ3RMWGRoY200dGQyRnphQ2s3WW05eVpHVnlPakZ3ZUNCemIyeHBaQ0J5WjJKaEtESTBOU3d4TlRnc01U'
    || 'RXNMalFwTzJKdmNtUmxjaTF5WVdScGRYTTZOSEI0TzNCaFpHUnBibWM2T0hCNElERXhjSGc3YldGeVoybHVPakFnTUNBeE1YQjRPMlp2Ym5RdGMybDZaVG94'
    || 'TVM0MWNIZzdZMjlzYjNJNkl6aGhOVFl3TUR0c2FXNWxMV2hsYVdkb2REb3hMalY5TG1OaGRtVmhkSHRpWVdOclozSnZkVzVrT25aaGNpZ3RMWGRoY200dGQy'
    || 'RnphQ2s3WW05eVpHVnlPakZ3ZUNCemIyeHBaQ0J5WjJKaEtESTBOU3d4TlRnc01URXNMalFwTzJKdmNtUmxjaTF5WVdScGRYTTZkbUZ5S0MwdGNtRmthWFZ6'
    || 'S1R0d1lXUmthVzVuT2pFeGNIZ2dNVE53ZUR0dFlYSm5hVzQ2TVRKd2VDQXdJREE3Wm05dWRDMXphWHBsT2pFeUxqVndlSDB1WTJGMlpXRjBJSE4wY205dVoz'
    || 'dGthWE53YkdGNU9tSnNiMk5yTzJOdmJHOXlPaU00WVRVMk1EQTdiV0Z5WjJsdUxXSnZkSFJ2YlRvMWNIZzdabTl1ZEMxM1pXbG5hSFE2TnpBd2ZTNWpZWFps'
    || 'WVhRZ2NIdHRZWEpuYVc0Nk1EdGpiMnh2Y2pwMllYSW9MUzF0ZFhSbFpDazdiR2x1WlMxb1pXbG5hSFE2TVM0MmZTNXdZVzVsYkMxdWIzUmlkV2xzZEh0aVlX'
    || 'TnJaM0p2ZFc1a09uWmhjaWd0TFdGalkyVnVkQzEzWVhOb0tUdGliM0prWlhJNk1YQjRJSE52Ykdsa0lISm5ZbUVvTUN3eE16SXNNakV5TEM0ektUdGliM0pr'
    || 'WlhJdGNtRmthWFZ6T25aaGNpZ3RMWEpoWkdsMWN5azdjR0ZrWkdsdVp6b3hNbkI0SURFMGNIZzdabTl1ZEMxemFYcGxPakV5TGpWd2VIMHVjR0Z1Wld3dGJt'
    || 'OTBZblZwYkhRZ2MzUnliMjVuZTJScGMzQnNZWGs2WW14dlkyczdZMjlzYjNJNmRtRnlLQzB0WVdOalpXNTBLVHR0WVhKbmFXNHRZbTkwZEc5dE9qVndlSDB1'
    || 'Y0dGdVpXd3RibTkwWW5WcGJIUWdjSHR0WVhKbmFXNDZNRHRqYjJ4dmNqcDJZWElvTFMxdGRYUmxaQ2s3YkdsdVpTMW9aV2xuYUhRNk1TNDJmUzV3WVc1bGJD'
    || 'MXViM1JpZFdsc2RGOWZZV3gwZTIxaGNtZHBiaTEwYjNBNk9IQjRJV2x0Y0c5eWRHRnVkRHRtYjI1MExYTnBlbVU2TVRFdU5YQjRPMjl3WVdOcGRIazZMamw5'
    || 'TG01dmRIbGxkSHRpWVdOclozSnZkVzVrT25aaGNpZ3RMWE4xY21aaFkyVXRNaWs3WW05eVpHVnlPakZ3ZUNCemIyeHBaQ0IyWVhJb0xTMXNhVzVsS1R0aWIz'
    || 'SmtaWEl0Y21Ga2FYVnpPblpoY2lndExYSmhaR2wxY3lrN2NHRmtaR2x1WnpveE5YQjRJREUzY0hnZ01UWndlRHRtYjI1MExYTnBlbVU2TVRJdU5YQjRmUzV1'
    || 'YjNSNVpYUStjM1J5YjI1bmUyUnBjM0JzWVhrNllteHZZMnM3WTI5c2IzSTZkbUZ5S0MwdGJtRjJlU2s3Wm05dWRDMXphWHBsT2pFekxqVndlRHR0WVhKbmFX'
    || 'NHRZbTkwZEc5dE9qZHdlSDB1Ym05MGVXVjBJSEI3YldGeVoybHVPakE3WTI5c2IzSTZkbUZ5S0MwdGJYVjBaV1FwTzJ4cGJtVXRhR1ZwWjJoME9qRXVObjB1'
    || 'Ym05MGVXVjBJR052WkdWN1ltRmphMmR5YjNWdVpEcDJZWElvTFMxemRYSm1ZV05sS1R0aWIzSmtaWEk2TVhCNElITnZiR2xrSUhaaGNpZ3RMV3hwYm1VdE1p'
    || 'azdjR0ZrWkdsdVp6b3hjSGdnTlhCNE8ySnZjbVJsY2kxeVlXUnBkWE02TkhCNE8yWnZiblF0YzJsNlpUb3hNUzQxY0hnN1kyOXNiM0k2ZG1GeUtDMHRibUYy'
    || 'ZVNrN2QyaHBkR1V0YzNCaFkyVTZibTkzY21Gd2ZTNXViM1I1WlhSZlgzZG9ZWFI3YldGeVoybHVMWFJ2Y0RveE0zQjRJV2x0Y0c5eWRHRnVkRHRqYjJ4dmNq'
    || 'cDJZWElvTFMxMFpYaDBLU0ZwYlhCdmNuUmhiblE3Wm05dWRDMTNaV2xuYUhRNk5UQXdmUzV1YjNSNVpYUmZYM1JwWlhKemUyMWhjbWRwYmpvNWNIZ2dNQ0F3'
    || 'TzNCaFpHUnBibWM2TUR0c2FYTjBMWE4wZVd4bE9tNXZibVU3WkdsemNHeGhlVHBtYkdWNE8yWnNaWGd0WkdseVpXTjBhVzl1T21OdmJIVnRianRuWVhBNk9I'
    || 'QjRmUzV1YjNSNVpYUmZYM1JwWlhKeklHeHBlMlJwYzNCc1lYazZaM0pwWkR0bmNtbGtMWFJsYlhCc1lYUmxMV052YkhWdGJuTTZPVFp3ZUNCdGFXNXRZWGdv'
    || 'TUN3eFpuSXBPMmRoY0RveE1uQjRPMkZzYVdkdUxXbDBaVzF6T21KaGMyVnNhVzVsTzNCaFpHUnBibWN0YkdWbWREb3hNWEI0TzJKdmNtUmxjaTFzWldaME9q'
    || 'SndlQ0J6YjJ4cFpDQjJZWElvTFMxc2FXNWxMVElwZlM1dWIzUjVaWFJmWDNScFpYSjdabTl1ZEMxemFYcGxPakV4Y0hnN1ptOXVkQzEzWldsbmFIUTZOekF3'
    || 'TzJ4bGRIUmxjaTF6Y0dGamFXNW5PaTR3TkdWdE8zUmxlSFF0ZEhKaGJuTm1iM0p0T25Wd2NHVnlZMkZ6WlR0amIyeHZjanAyWVhJb0xTMWthVzBwZlM1dWIz'
    || 'UjVaWFJmWDNScFpYSXRaR1Z6WTN0amIyeHZjanAyWVhJb0xTMXRkWFJsWkNrN2JHbHVaUzFvWldsbmFIUTZNUzQxTzJadmJuUXRjMmw2WlRveE1uQjRmUzV1'
    || 'YjNSNVpYUmZYMlp2YjNSN2JXRnlaMmx1TFhSdmNEb3hNM0I0SVdsdGNHOXlkR0Z1ZER0d1lXUmthVzVuTFhSdmNEb3hNWEI0TzJKdmNtUmxjaTEwYjNBNk1Y'
    || 'QjRJSE52Ykdsa0lIWmhjaWd0TFd4cGJtVXBPMlp2Ym5RdGMybDZaVG94TVM0MWNIaDlMbVpoZEdGc2UySmhZMnRuY205MWJtUTZkbUZ5S0MwdFltRmtMWGRo'
    || 'YzJncE8ySnZjbVJsY2pveGNIZ2djMjlzYVdRZ2NtZGlZU2d5TXpJc01Dd3lPQ3d1TXpZcE8ySnZjbVJsY2kxeVlXUnBkWE02ZG1GeUtDMHRjbUZrYVhWekxX'
    || 'eG5LVHR3WVdSa2FXNW5Pakl3Y0hnZ01qSndlRHR0WVhKbmFXNDZNalJ3ZUgwdVptRjBZV3dnYURGN2JXRnlaMmx1T2pBZ01DQTVjSGc3Wm05dWRDMXphWHBs'
    || 'T2pFM2NIZzdZMjlzYjNJNmRtRnlLQzB0WW1Ga0tYMHVabUYwWVd3Z1kyOWtaWHRqYjJ4dmNqb2pPR1l3TURFME8zZG9hWFJsTFhOd1lXTmxPbkJ5WlMxM2Nt'
    || 'RndPMlp2Ym5RdGMybDZaVG94TW5CNGZTNWtiMjUxZEh0a2FYTndiR0Y1T21ac1pYZzdZV3hwWjI0dGFYUmxiWE02WTJWdWRHVnlPMmRoY0RveE9IQjRmUzVr'
    || 'YjI1MWRGOWZabWxuZTJac1pYZzZibTl1WlgwdVpHOXVkWFJmWDJ0bGVYdGthWE53YkdGNU9tWnNaWGc3Wm14bGVDMWthWEpsWTNScGIyNDZZMjlzZFcxdU8y'
    || 'ZGhjRG8zY0hnN2JXbHVMWGRwWkhSb09qQjlMbVJ2Ym5WMFgxOXliM2Q3WkdsemNHeGhlVHBtYkdWNE8yRnNhV2R1TFdsMFpXMXpPbU5sYm5SbGNqdG5ZWEE2'
    || 'T0hCNE8yWnZiblF0YzJsNlpUb3hNbkI0ZlM1a2IyNTFkRjlmYzNkN2QybGtkR2c2T1hCNE8yaGxhV2RvZERvNWNIZzdZbTl5WkdWeUxYSmhaR2wxY3pvemNI'
    || 'ZzdabXhsZURwdWIyNWxmUzVrYjI1MWRGOWZiR0ZpZTJOdmJHOXlPblpoY2lndExXMTFkR1ZrS1R0dmRtVnlabXh2ZHpwb2FXUmtaVzQ3ZEdWNGRDMXZkbVZ5'
    || 'Wm14dmR6cGxiR3hwY0hOcGN6dDNhR2wwWlMxemNHRmpaVHB1YjNkeVlYQjlMbVJ2Ym5WMFgxOTJZV3g3WTI5c2IzSTZkbUZ5S0MwdGRHVjRkQ2s3Wm05dWRD'
    || 'MTNaV2xuYUhRNk5qQXdPMlp2Ym5RdGRtRnlhV0Z1ZEMxdWRXMWxjbWxqT25SaFluVnNZWEl0Ym5WdGN6dHRZWEpuYVc0dGJHVm1kRHBoZFhSdmZTNWtiMjUx'
    || 'ZEY5ZlkyVnVkR1Z5ZTJadmJuUXRkbUZ5YVdGdWRDMXVkVzFsY21sak9uUmhZblZzWVhJdGJuVnRjMzB1YzNCaGNtdDdaR2x6Y0d4aGVUcGliRzlqYTMwdWMz'
    || 'QmhjbXRmWDJ4cGJtVjdabWxzYkRwdWIyNWxPM04wY205clpUcDJZWElvTFMxaFkyTmxiblFwTzNOMGNtOXJaUzEzYVdSMGFEb3lPM04wY205clpTMXNhVzVs'
    || 'WTJGd09uSnZkVzVrTzNOMGNtOXJaUzFzYVc1bGFtOXBianB5YjNWdVpIMHVjM0JoY210ZlgyRnlaV0Y3Wm1sc2JEcDJZWElvTFMxaFkyTmxiblF0ZDJGemFD'
    || 'azdjM1J5YjJ0bE9tNXZibVY5TG5Od1lYSnJYMTlrYjNSN1ptbHNiRHAyWVhJb0xTMWhZMk5sYm5RcGZTNW1iRzkzZTJScGMzQnNZWGs2Wm14bGVEdGhiR2xu'
    || 'YmkxcGRHVnRjenB6ZEhKbGRHTm9PMjFoY21kcGJpMTBiM0E2Tm5CNGZTNW1iRzkzWDE5aWIzaDdabXhsZURveElERWdNRHR0YVc0dGQybGtkR2c2TUR0MFpY'
    || 'aDBMV0ZzYVdkdU9tTmxiblJsY2p0aVlXTnJaM0p2ZFc1a09uWmhjaWd0TFhOMWNtWmhZMlVwTzJKdmNtUmxjam94Y0hnZ2MyOXNhV1FnZG1GeUtDMHRiR2x1'
    || 'WlMweUtUdGliM0prWlhJdGNtRmthWFZ6T2pFd2NIZzdjR0ZrWkdsdVp6b3hNWEI0SURFd2NIaDlMbVpzYjNkZlgySnZlQzB0YjI1N1ltRmphMmR5YjNWdVpE'
    || 'cDJZWElvTFMxaFkyTmxiblF0ZDJGemFDazdZbTl5WkdWeUxXTnZiRzl5T25aaGNpZ3RMV0ZqWTJWdWRDbDlMbVpzYjNkZlgyeGhZbnRtYjI1MExYTnBlbVU2'
    || 'TVRFdU5YQjRPMlp2Ym5RdGQyVnBaMmgwT2pZd01EdGpiMnh2Y2pwMllYSW9MUzF1WVhaNUtUdHNhVzVsTFdobGFXZG9kRG94TGpNN2IzWmxjbVpzYjNjdGQz'
    || 'SmhjRHBoYm5sM2FHVnlaWDB1Wm14dmQxOWZjM1ZpZTJadmJuUXRjMmw2WlRveE1YQjRPMk52Ykc5eU9uWmhjaWd0TFdScGJTazdiV0Z5WjJsdUxYUnZjRG96'
    || 'Y0hnN2JHbHVaUzFvWldsbmFIUTZNUzR6ZlM1bWJHOTNYMTlzYVc1cmUyWnNaWGc2TUNBd0lESTBjSGc3WVd4cFoyNHRjMlZzWmpwalpXNTBaWEk3YUdWcFoy'
    || 'aDBPakp3ZUR0aVlXTnJaM0p2ZFc1a09uWmhjaWd0TFd4cGJtVXRNaWs3WW05eVpHVnlMWEpoWkdsMWN6b3ljSGg5TG1ac2IzZGZYMnhwYm1zdExXOXVlMkpo'
    || 'WTJ0bmNtOTFibVF0YVcxaFoyVTZiR2x1WldGeUxXZHlZV1JwWlc1MEtEa3daR1ZuTEhaaGNpZ3RMWE5yZVNrZ01DQTBOU1VzZEhKaGJuTndZWEpsYm5RZ05E'
    || 'VWxJREV3TUNVcE8ySmhZMnRuY205MWJtUXRjMmw2WlRveE0zQjRJREp3ZUR0aVlXTnJaM0p2ZFc1a0xYSmxjR1ZoZERweVpYQmxZWFF0ZUR0aVlXTnJaM0p2'
    || 'ZFc1a0xXTnZiRzl5T25SeVlXNXpjR0Z5Wlc1MGZTNWhZM1JmWDNScFpYSjdiV0Z5WjJsdU9qRTJjSGdnTUNBeWNIZzdabTl1ZEMxemFYcGxPakV4Y0hnN1pt'
    || 'OXVkQzEzWldsbmFIUTZOekF3TzNSbGVIUXRkSEpoYm5ObWIzSnRPblZ3Y0dWeVkyRnpaVHRzWlhSMFpYSXRjM0JoWTJsdVp6b3VNRFJsYlR0amIyeHZjanAy'
    || 'WVhJb0xTMXRkWFJsWkNsOUxtRmpkRjlmZEdsbGNpMWtaWE5qZTIxaGNtZHBiam93SURBZ01UQndlRHRtYjI1MExYTnBlbVU2TVRKd2VEdGpiMnh2Y2pwMllY'
    || 'SW9MUzF0ZFhSbFpDazdiR2x1WlMxb1pXbG5hSFE2TVM0MWZTNWhZM1JmWDJkeWFXUjdaR2x6Y0d4aGVUcG5jbWxrTzJkaGNEb3hNSEI0TzJkeWFXUXRkR1Z0'
    || 'Y0d4aGRHVXRZMjlzZFcxdWN6cHlaWEJsWVhRb1lYVjBieTFtYVhRc2JXbHViV0Y0S0RJME1IQjRMREZtY2lrcE8yMWhjbWRwYmkxaWIzUjBiMjA2TVRSd2VI'
    || 'MHVZV04wWDE5allYSmtlMkpoWTJ0bmNtOTFibVE2ZG1GeUtDMHRjM1Z5Wm1GalpTMHlLVHRpYjNKa1pYSTZNWEI0SUhOdmJHbGtJSFpoY2lndExXeHBibVVw'
    || 'TzJKdmNtUmxjaTF5WVdScGRYTTZkbUZ5S0MwdGNtRmthWFZ6S1R0d1lXUmthVzVuT2pFeWNIZ2dNVFJ3ZUgwdVlXTjBYMTlqYjJSbGUyWnZiblF0YzJsNlpU'
    || 'b3hNWEI0TzJadmJuUXRkMlZwWjJoME9qY3dNRHQwWlhoMExYUnlZVzV6Wm05eWJUcDFjSEJsY21OaGMyVTdiR1YwZEdWeUxYTndZV05wYm1jNkxqQTBaVzA3'
    || 'WTI5c2IzSTZkbUZ5S0MwdFlXTmpaVzUwS1R0dFlYSm5hVzR0WW05MGRHOXRPak53ZUgwdVlXTjBYMTlzWVdKbGJIdG1iMjUwTFhOcGVtVTZNVE53ZUR0bWIy'
    || 'NTBMWGRsYVdkb2REbzJNREE3WTI5c2IzSTZkbUZ5S0MwdGJtRjJlU2s3YkdsdVpTMW9aV2xuYUhRNk1TNHpmUzVoWTNSZlgyVm1abVZqZEh0bWIyNTBMWE5w'
    || 'ZW1VNk1USndlRHRqYjJ4dmNqcDJZWElvTFMxdGRYUmxaQ2s3YldGeVoybHVMWFJ2Y0RvMGNIZzdiR2x1WlMxb1pXbG5hSFE2TVM0ME5YMHVZV04wWDE5dFpY'
    || 'UmhlMlJwYzNCc1lYazZabXhsZUR0bWJHVjRMWGR5WVhBNmQzSmhjRHRuWVhBNk5uQjRJREV5Y0hnN2JXRnlaMmx1TFhSdmNEbzRjSGc3Wm05dWRDMXphWHBs'
    || 'T2pFeGNIZzdZMjlzYjNJNmRtRnlLQzB0YlhWMFpXUXBmUzVoWTNSZlgzVnVaRzk3WTI5c2IzSTZkbUZ5S0MwdFoyOXZaQ2s3Wm05dWRDMTNaV2xuYUhRNk5q'
    || 'QXdmUzVoWTNSZlgyNXZkVzVrYjN0amIyeHZjanAyWVhJb0xTMWthVzBwZlM1aFkzUmZYM0oxYm5ON1ptOXVkQzF6YVhwbE9qRXhjSGc3WTI5c2IzSTZkbUZ5'
    || 'S0MwdGJYVjBaV1FwTzIxaGNtZHBiaTEwYjNBNk5uQjRPMlp2Ym5RdGQyVnBaMmgwT2pVd01IMHVZV04wWDE5bWIyOTBlMjFoY21kcGJqb3hOSEI0SURBZ01E'
    || 'dG1iMjUwTFhOcGVtVTZNVEp3ZUR0amIyeHZjanAyWVhJb0xTMXRkWFJsWkNrN2JHbHVaUzFvWldsbmFIUTZNUzQxTlR0aWIzSmtaWEl0ZEc5d09qRndlQ0J6'
    || 'YjJ4cFpDQjJZWElvTFMxc2FXNWxLVHR3WVdSa2FXNW5MWFJ2Y0RveE1uQjRmUzV5ZG50dmNHRmphWFI1T2pBN2RISmhibk5tYjNKdE9uUnlZVzV6YkdGMFpW'
    || 'a29OM0I0S1R0aGJtbHRZWFJwYjI0NmNuWnBiaUF1TlRKeklIWmhjaWd0TFdWaGMyVXBJR1p2Y25kaGNtUnpmVUJyWlhsbWNtRnRaWE1nY25acGJudDBiM3R2'
    || 'Y0dGamFYUjVPakU3ZEhKaGJuTm1iM0p0T201dmJtVjlmVUJ0WldScFlTaHdjbVZtWlhKekxYSmxaSFZqWldRdGJXOTBhVzl1T25KbFpIVmpaU2w3S250aGJt'
    || 'bHRZWFJwYjI0NmJtOXVaU0ZwYlhCdmNuUmhiblE3ZEhKaGJuTnBkR2x2YmpwdWIyNWxJV2x0Y0c5eWRHRnVkSDB1Y25aN2IzQmhZMmwwZVRveE8zUnlZVzV6'
    || 'Wm05eWJUcHViMjVsZlgwdVlYQndYMTlvWldGa2NtbG5hSFI3Wm14bGVEcHViMjVsTzJScGMzQnNZWGs2Wm14bGVEdG1iR1Y0TFdScGNtVmpkR2x2YmpwamIy'
    || 'eDFiVzQ3WVd4cFoyNHRhWFJsYlhNNlpteGxlQzFsYm1RN1oyRndPamh3ZUgwdWNHOWpMV05vYVhCN1pHbHpjR3hoZVRwcGJteHBibVV0Wm14bGVEdGhiR2xu'
    || 'YmkxcGRHVnRjenBpWVhObGJHbHVaVHRuWVhBNk4zQjRPM0JoWkdScGJtYzZObkI0SURFeGNIZzdZbTl5WkdWeUxYSmhaR2wxY3pwMllYSW9MUzF5WVdScGRY'
    || 'TXBPMkp2Y21SbGNqb3hjSGdnYzI5c2FXUWdkbUZ5S0MwdGJHbHVaU2s3WW1GamEyZHliM1Z1WkRwMllYSW9MUzF6ZFhKbVlXTmxLVHRtYjI1ME9tbHVhR1Z5'
    || 'YVhRN1kzVnljMjl5T25CdmFXNTBaWEk3ZDJocGRHVXRjM0JoWTJVNmJtOTNjbUZ3TzNSeVlXNXphWFJwYjI0NlltRmphMmR5YjNWdVpDQXVNVEp6SUdWaGMy'
    || 'VXNZbTl5WkdWeUxXTnZiRzl5SUM0eE1uTWdaV0Z6WlgwdWNHOWpMV05vYVhBNmFHOTJaWEo3WW1GamEyZHliM1Z1WkRwMllYSW9MUzF6ZFhKbVlXTmxMVElw'
    || 'TzJKdmNtUmxjaTFqYjJ4dmNqcDJZWElvTFMxc2FXNWxMVElwZlM1d2IyTXRZMmhwY0MwdGMzUmhkR2xqZTJOMWNuTnZjanBrWldaaGRXeDBmUzV3YjJNdFky'
    || 'aHBjQzB0YzNSaGRHbGpPbWh2ZG1WeWUySmhZMnRuY205MWJtUTZkbUZ5S0MwdGMzVnlabUZqWlNrN1ltOXlaR1Z5TFdOdmJHOXlPblpoY2lndExXeHBibVVw'
    || 'ZlM1d2IyTXRZMmhwY0RwbWIyTjFjeTEyYVhOcFlteGxlMjkxZEd4cGJtVTZNbkI0SUhOdmJHbGtJSFpoY2lndExXRmpZMlZ1ZENrN2IzVjBiR2x1WlMxdlpt'
    || 'WnpaWFE2TW5CNGZTNXdiMk10WTJocGNGOWZiblZ0ZTJadmJuUXRjMmw2WlRveE5YQjRPMlp2Ym5RdGQyVnBaMmgwT2pjd01EdG1iMjUwTFhaaGNtbGhiblF0'
    || 'Ym5WdFpYSnBZenAwWVdKMWJHRnlMVzUxYlhNN2JHVjBkR1Z5TFhOd1lXTnBibWM2TFM0d01XVnRmUzV3YjJNdFkyaHBjRjlmZDI5eVpIdG1iMjUwTFhOcGVt'
    || 'VTZNVEZ3ZUR0bWIyNTBMWGRsYVdkb2REbzJNREE3ZEdWNGRDMTBjbUZ1YzJadmNtMDZkWEJ3WlhKallYTmxPMnhsZEhSbGNpMXpjR0ZqYVc1bk9pNHdOR1Z0'
    || 'TzJOdmJHOXlPblpoY2lndExXMTFkR1ZrS1gwdWNHOWpMV05vYVhCZlgyWnNZV2Q3Wm05dWRDMXphWHBsT2pFeGNIZzdabTl1ZEMxM1pXbG5hSFE2TmpBd08z'
    || 'UmxlSFF0ZEhKaGJuTm1iM0p0T25Wd2NHVnlZMkZ6WlR0c1pYUjBaWEl0YzNCaFkybHVaem91TURSbGJUdHdZV1JrYVc1bkxXeGxablE2TjNCNE8yMWhjbWRw'
    || 'Ymkxc1pXWjBPakZ3ZUR0aWIzSmtaWEl0YkdWbWREb3hjSGdnYzI5c2FXUWdkbUZ5S0MwdGJHbHVaU2s3WTI5c2IzSTZkbUZ5S0MwdGJYVjBaV1FwZlM1d2Iy'
    || 'TXRZMmhwY0MwdFoyOXZaSHRpYjNKa1pYSXRZMjlzYjNJNkl6RTJZVE0wWVRVNU8ySmhZMnRuY205MWJtUTZkbUZ5S0MwdFoyOXZaQzEzWVhOb0tYMHVjRzlq'
    || 'TFdOb2FYQXRMV2R2YjJRZ0xuQnZZeTFqYUdsd1gxOXVkVzE3WTI5c2IzSTZkbUZ5S0MwdFoyOXZaQ2w5TG5Cdll5MWphR2x3TFMxM1lYSnVlMkp2Y21SbGNp'
    || 'MWpiMnh2Y2pvalpqVTVaVEJpTmpZN1ltRmphMmR5YjNWdVpEcDJZWElvTFMxM1lYSnVMWGRoYzJncGZTNXdiMk10WTJocGNDMHRkMkZ5YmlBdWNHOWpMV05v'
    || 'YVhCZlgyNTFiWHRqYjJ4dmNqb2pZVEUyTWpBM2ZTNXdiMk10WTJocGNDMHRZbUZrZTJKdmNtUmxjaTFqYjJ4dmNqb2paVGd3TURGak5UazdZbUZqYTJkeWIz'
    || 'VnVaRHAyWVhJb0xTMWlZV1F0ZDJGemFDbDlMbkJ2WXkxamFHbHdMUzFpWVdRZ0xuQnZZeTFqYUdsd1gxOXVkVzE3WTI5c2IzSTZkbUZ5S0MwdFltRmtLWDB1'
    || 'Y0c5akxXTm9hWEF0TFdsa2JHVWdMbkJ2WXkxamFHbHdYMTl1ZFcxN1kyOXNiM0k2ZG1GeUtDMHRiWFYwWldRcGZTNXVZWFpmWDJKaFpHZGxlMlpzWlhnNmJt'
    || 'OXVaVHR0WVhKbmFXNHRiR1ZtZERwaGRYUnZPM0JoWkdScGJtYzZNWEI0SURad2VEdGliM0prWlhJdGNtRmthWFZ6T2pJd2NIZzdabTl1ZEMxemFYcGxPakV4'
    || 'Y0hnN1ptOXVkQzEzWldsbmFIUTZOekF3TzJadmJuUXRkbUZ5YVdGdWRDMXVkVzFsY21sak9uUmhZblZzWVhJdGJuVnRjenRpYjNKa1pYSTZNWEI0SUhOdmJH'
    || 'bGtJSFpoY2lndExXeHBibVVwTzJKaFkydG5jbTkxYm1RNmRtRnlLQzB0YzNWeVptRmpaUzB5S1R0amIyeHZjanAyWVhJb0xTMXRkWFJsWkNsOUxtNWhkbDlm'
    || 'WW1Ga1oyVXRMV2R2YjJSN1kyOXNiM0k2ZG1GeUtDMHRaMjl2WkNrN1ltOXlaR1Z5TFdOdmJHOXlPaU14Tm1Fek5HRTFPVHRpWVdOclozSnZkVzVrT25aaGNp'
    || 'Z3RMV2R2YjJRdGQyRnphQ2w5TG01aGRsOWZZbUZrWjJVdExYZGhjbTU3WTI5c2IzSTZJMkV4TmpJd056dGliM0prWlhJdFkyOXNiM0k2STJZMU9XVXdZalky'
    || 'TzJKaFkydG5jbTkxYm1RNmRtRnlLQzB0ZDJGeWJpMTNZWE5vS1gwdWJtRjJYMTlpWVdSblpTMHRZbUZrZTJOdmJHOXlPblpoY2lndExXSmhaQ2s3WW05eVpH'
    || 'VnlMV052Ykc5eU9pTmxPREF3TVdNMU9UdGlZV05yWjNKdmRXNWtPblpoY2lndExXSmhaQzEzWVhOb0tYMHVibUYyWDE5aVlXUm5aUzB0YVdSc1pYdGpiMnh2'
    || 'Y2pwMllYSW9MUzF0ZFhSbFpDbDlMbTVoZGw5ZlltRmtaMlVyTG01aGRsOWZaRzkwZTIxaGNtZHBiaTFzWldaME9qWndlSDB1Y0c5amUyUnBjM0JzWVhrNlpt'
    || 'eGxlRHRtYkdWNExXUnBjbVZqZEdsdmJqcGpiMngxYlc0N1oyRndPakV5Y0hoOUxuQnZZMTlmZG1WeVpHbGpkSHRpYjNKa1pYSTZNbkI0SUhOdmJHbGtJSFpo'
    || 'Y2lndExXeHBibVVwTzJKdmNtUmxjaTF5WVdScGRYTTZkbUZ5S0MwdGNtRmthWFZ6S1R0aVlXTnJaM0p2ZFc1a09uWmhjaWd0TFhOMWNtWmhZMlVwTzNCaFpH'
    || 'UnBibWM2TVRWd2VDQXhOM0I0ZlM1d2IyTmZYM1psY21ScFkzUXRMV2R2YjJSN1ltOXlaR1Z5TFdOdmJHOXlPaU14Tm1Fek5HRTNNenRpWVdOclozSnZkVzVr'
    || 'T25aaGNpZ3RMV2R2YjJRdGQyRnphQ2w5TG5CdlkxOWZkbVZ5WkdsamRDMHRkMkZ5Ym50aWIzSmtaWEl0WTI5c2IzSTZJMlkxT1dVd1lqY3pPMkpoWTJ0bmNt'
    || 'OTFibVE2ZG1GeUtDMHRkMkZ5YmkxM1lYTm9LWDB1Y0c5algxOTJaWEprYVdOMExTMWlZV1I3WW05eVpHVnlMV052Ykc5eU9pTmxPREF3TVdNMU9UdGlZV05y'
    || 'WjNKdmRXNWtPblpoY2lndExXSmhaQzEzWVhOb0tYMHVjRzlqWDE5MlpYSmthV04wTFMxcFpHeGxlMkp2Y21SbGNpMWpiMnh2Y2pwMllYSW9MUzFzYVc1bExU'
    || 'SXBmUzV3YjJOZlgyaGxZV1JzYVc1bGUyWnZiblF0YzJsNlpUb3pNSEI0TzJadmJuUXRkMlZwWjJoME9qY3dNRHRzWlhSMFpYSXRjM0JoWTJsdVp6b3RMakF5'
    || 'TldWdE8yWnZiblF0ZG1GeWFXRnVkQzF1ZFcxbGNtbGpPblJoWW5Wc1lYSXRiblZ0Y3p0amIyeHZjanAyWVhJb0xTMXVZWFo1S1R0c2FXNWxMV2hsYVdkb2RE'
    || 'b3hMakY5TG5CdlkxOWZjbVZoWkh0dFlYSm5hVzQ2Tm5CNElEQWdNRHRtYjI1MExYTnBlbVU2TVRJdU5YQjRPMk52Ykc5eU9uWmhjaWd0TFcxMWRHVmtLVHRz'
    || 'YVc1bExXaGxhV2RvZERveExqVjlMbkJ2WTE5ZmRHRnNiSGw3WkdsemNHeGhlVHBtYkdWNE8yWnNaWGd0ZDNKaGNEcDNjbUZ3TzJkaGNEb3hOSEI0TzIxaGNt'
    || 'ZHBiaTEwYjNBNk1USndlSDB1Y0c5algxOTBhV05yZTJadmJuUXRjMmw2WlRveE1YQjRPMlp2Ym5RdGQyVnBaMmgwT2pZd01EdDBaWGgwTFhSeVlXNXpabTl5'
    || 'YlRwMWNIQmxjbU5oYzJVN2JHVjBkR1Z5TFhOd1lXTnBibWM2TGpBMFpXMDdZMjlzYjNJNmRtRnlLQzB0YlhWMFpXUXBmUzV3YjJOZlgzUnBZMnNnWW50bWIy'
    || 'NTBMWE5wZW1VNk1UTndlRHRtYjI1MExYZGxhV2RvZERvM01EQTdabTl1ZEMxMllYSnBZVzUwTFc1MWJXVnlhV002ZEdGaWRXeGhjaTF1ZFcxek8yMWhjbWRw'
    || 'YmkxeWFXZG9kRG96Y0hoOUxuQnZZMTlmZEdsamF5MHRiV1YwSUdKN1kyOXNiM0k2ZG1GeUtDMHRaMjl2WkNsOUxuQnZZMTlmZEdsamF5MHRibTkwYldWMElH'
    || 'SjdZMjlzYjNJNmRtRnlLQzB0WW1Ga0tYMHVjRzlqWDE5MGFXTnJMUzF3Wlc1a2FXNW5JR0o3WTI5c2IzSTZkbUZ5S0MwdGJYVjBaV1FwZlM1d2IyTmZYM1Jw'
    || 'WTJzdExXNWhJR0o3WTI5c2IzSTZkbUZ5S0MwdFpHbHRLWDB1Y0c5akxYSnZkM3RrYVhOd2JHRjVPbVpzWlhnN1oyRndPakV5Y0hnN2NHRmtaR2x1WnpveE5I'
    || 'QjRJREUyY0hnN1ltOXlaR1Z5T2pGd2VDQnpiMnhwWkNCMllYSW9MUzFzYVc1bEtUdGliM0prWlhJdGNtRmthWFZ6T25aaGNpZ3RMWEpoWkdsMWN5azdZbUZq'
    || 'YTJkeWIzVnVaRHAyWVhJb0xTMXpkWEptWVdObEtYMHVjRzlqTFhKdmR5MHRibTkwYldWMGUySmhZMnRuY205MWJtUTZkbUZ5S0MwdFltRmtMWGRoYzJncE8y'
    || 'SnZjbVJsY2kxamIyeHZjam9qWlRnd01ERmpNemg5TG5Cdll5MXliM2N0TFcxbGRIdGlZV05yWjNKdmRXNWtPblpoY2lndExYTjFjbVpoWTJVcGZTNXdiMk10'
    || 'Y205M0xTMXVZWHR2Y0dGamFYUjVPaTQzTW4wdWNHOWpMWEp2ZDE5ZmJXRnlhM3RtYkdWNE9tNXZibVU3ZDJsa2RHZzZNakp3ZUR0b1pXbG5hSFE2TWpKd2VE'
    || 'dGliM0prWlhJdGNtRmthWFZ6T2pVd0pUdGthWE53YkdGNU9tZHlhV1E3Y0d4aFkyVXRhWFJsYlhNNlkyVnVkR1Z5TzJadmJuUXRjMmw2WlRveE0zQjRPMlp2'
    || 'Ym5RdGQyVnBaMmgwT2pjd01EdHNhVzVsTFdobGFXZG9kRG94ZlM1d2IyTXRjbTkzTFMxdFpYUWdMbkJ2WXkxeWIzZGZYMjFoY210N1ltRmphMmR5YjNWdVpE'
    || 'cDJZWElvTFMxbmIyOWtMWGRoYzJncE8yTnZiRzl5T25aaGNpZ3RMV2R2YjJRcGZTNXdiMk10Y205M0xTMXViM1J0WlhRZ0xuQnZZeTF5YjNkZlgyMWhjbXQ3'
    || 'WW1GamEyZHliM1Z1WkRvalpUZ3dNREZqTWpFN1kyOXNiM0k2ZG1GeUtDMHRZbUZrS1gwdWNHOWpMWEp2ZHkwdGNHVnVaR2x1WnlBdWNHOWpMWEp2ZDE5ZmJX'
    || 'RnlhM3RpWVdOclozSnZkVzVrT25aaGNpZ3RMWE4xY21aaFkyVXRNeWs3WTI5c2IzSTZkbUZ5S0MwdGJYVjBaV1FwZlM1d2IyTXRjbTkzTFMxdVlTQXVjRzlq'
    || 'TFhKdmQxOWZiV0Z5YTN0aVlXTnJaM0p2ZFc1a09uUnlZVzV6Y0dGeVpXNTBPMk52Ykc5eU9uWmhjaWd0TFdScGJTazdZbTk0TFhOb1lXUnZkenBwYm5ObGRD'
    || 'QXdJREFnTUNBeGNIZ2dkbUZ5S0MwdGJHbHVaUzB5S1gwdWNHOWpMWEp2ZDE5ZlltOWtlWHR0YVc0dGQybGtkR2c2TUR0bWJHVjRPakY5TG5Cdll5MXliM2Rm'
    || 'WDNSdmNIdGthWE53YkdGNU9tWnNaWGc3WVd4cFoyNHRhWFJsYlhNNlltRnpaV3hwYm1VN1oyRndPakV3Y0hnN2FuVnpkR2xtZVMxamIyNTBaVzUwT25Od1lX'
    || 'TmxMV0psZEhkbFpXNTlMbkJ2WXkxeWIzZGZYMnhoWW1Wc2UyWnZiblF0YzJsNlpUb3hNeTQxY0hnN1ptOXVkQzEzWldsbmFIUTZOakF3TzJOdmJHOXlPblpo'
    || 'Y2lndExXNWhkbmtwTzJ4cGJtVXRhR1ZwWjJoME9qRXVNelY5TG5Cdll5MXliM2RmWDNOMFlYUmxlMlpzWlhnNmJtOXVaVHRtYjI1MExYTnBlbVU2TVRGd2VE'
    || 'dG1iMjUwTFhkbGFXZG9kRG8zTURBN2RHVjRkQzEwY21GdWMyWnZjbTA2ZFhCd1pYSmpZWE5sTzJ4bGRIUmxjaTF6Y0dGamFXNW5PaTR3TkdWdGZTNXdiMk10'
    || 'Y205M1gxOXpkR0YwWlMwdGJXVjBlMk52Ykc5eU9uWmhjaWd0TFdkdmIyUXBmUzV3YjJNdGNtOTNYMTl6ZEdGMFpTMHRibTkwYldWMGUyTnZiRzl5T25aaGNp'
    || 'Z3RMV0poWkNsOUxuQnZZeTF5YjNkZlgzTjBZWFJsTFMxd1pXNWthVzVuZTJOdmJHOXlPblpoY2lndExXMTFkR1ZrS1gwdWNHOWpMWEp2ZDE5ZmMzUmhkR1V0'
    || 'TFc1aGUyTnZiRzl5T25aaGNpZ3RMV1JwYlNsOUxuQnZZeTF5YjNkZlgzZG9lWHR0WVhKbmFXNDZOWEI0SURBZ01EdG1iMjUwTFhOcGVtVTZNVEp3ZUR0amIy'
    || 'eHZjanAyWVhJb0xTMXRkWFJsWkNrN2JHbHVaUzFvWldsbmFIUTZNUzQxZlM1d2IyTXRjbTkzWDE5dFlYUm9lMjFoY21kcGJqbzRjSGdnTUNBd2ZTNXdiMk10'
    || 'Y205M1gxOXRZWFJvSUdOdlpHVjdaR2x6Y0d4aGVUcHBibXhwYm1VdFlteHZZMnM3Y0dGa1pHbHVaem96Y0hnZ09IQjRPMkp2Y21SbGNpMXlZV1JwZFhNNk5Y'
    || 'QjRPMkpoWTJ0bmNtOTFibVE2ZG1GeUtDMHRjM1Z5Wm1GalpTMHlLVHRpYjNKa1pYSTZNWEI0SUhOdmJHbGtJSFpoY2lndExXeHBibVVwTzJadmJuUXRjMmw2'
    || 'WlRveE1uQjRPMlp2Ym5RdGRtRnlhV0Z1ZEMxdWRXMWxjbWxqT25SaFluVnNZWEl0Ym5WdGN6dGpiMnh2Y2pwMllYSW9MUzF1WVhaNUtYMHVjRzlqTFhKdmQx'
    || 'OWZiV0YwYUMwdGJtOXVaWHRtYjI1MExYTnBlbVU2TVRFdU5YQjRPMk52Ykc5eU9uWmhjaWd0TFdScGJTazdabTl1ZEMxemRIbHNaVHBwZEdGc2FXTjlMbkJ2'
    || 'WXkxeWIzZGZYM0JsYm1SN2JXRnlaMmx1T2pkd2VDQXdJREE3Wm05dWRDMXphWHBsT2pFeWNIZzdZMjlzYjNJNmRtRnlLQzB0ZEdWNGRDazdiR2x1WlMxb1pX'
    || 'bG5hSFE2TVM0MWZTNXdiMk10Y205M1gxOTNhR1Z1ZTIxaGNtZHBiam8wY0hnZ01DQXdPMlp2Ym5RdGMybDZaVG94TVhCNE8yTnZiRzl5T25aaGNpZ3RMVzEx'
    || 'ZEdWa0tUdG1iMjUwTFhkbGFXZG9kRG8yTURCOUxuQnZZeTF5YjNkZlgyMWxkR0Y3YldGeVoybHVPakV3Y0hnZ01DQXdPM0JoWkdScGJtY3RkRzl3T2psd2VE'
    || 'dGliM0prWlhJdGRHOXdPakZ3ZUNCemIyeHBaQ0IyWVhJb0xTMXNhVzVsS1R0a2FYTndiR0Y1T21keWFXUTdaMkZ3T2pod2VDQXlNSEI0TzJkeWFXUXRkR1Z0'
    || 'Y0d4aGRHVXRZMjlzZFcxdWN6b3habko5UUcxbFpHbGhLRzFwYmkxM2FXUjBhRG81TURCd2VDbDdMbkJ2WXkxeWIzZGZYMjFsZEdGN1ozSnBaQzEwWlcxd2JH'
    || 'RjBaUzFqYjJ4MWJXNXpPak5tY2lBeFpuSjlmUzV3YjJNdGNtOTNYMTl0WlhSaElHUjBlMlp2Ym5RdGMybDZaVG94TVhCNE8yWnZiblF0ZDJWcFoyaDBPall3'
    || 'TUR0MFpYaDBMWFJ5WVc1elptOXliVHAxY0hCbGNtTmhjMlU3YkdWMGRHVnlMWE53WVdOcGJtYzZMakEwWlcwN1kyOXNiM0k2ZG1GeUtDMHRaR2x0S1R0dFlY'
    || 'Sm5hVzR0WW05MGRHOXRPakp3ZUgwdWNHOWpMWEp2ZDE5ZmJXVjBZU0JrWkh0dFlYSm5hVzQ2TUR0bWIyNTBMWE5wZW1VNk1URXVOWEI0TzJOdmJHOXlPblpo'
    || 'Y2lndExXMTFkR1ZrS1R0c2FXNWxMV2hsYVdkb2REb3hMalY5TG5Cdll5MXliM2RmWDIxbGRHRWdaR1FnWTI5a1pYdG1iMjUwTFhOcGVtVTZNVEZ3ZUR0amIy'
    || 'eHZjanAyWVhJb0xTMXVZWFo1S1gwdWNHOWpYMTl1YjNSbGUyMWhjbWRwYmpveWNIZ2dNQ0F3TzNCaFpHUnBibWM2TVRCd2VDQXhNM0I0TzJKdmNtUmxjaTF5'
    || 'WVdScGRYTTZkbUZ5S0MwdGNtRmthWFZ6S1R0aVlXTnJaM0p2ZFc1a09uWmhjaWd0TFhOMWNtWmhZMlV0TWlrN1ltOXlaR1Z5T2pGd2VDQnpiMnhwWkNCMllY'
    || 'SW9MUzFzYVc1bEtUdG1iMjUwTFhOcGVtVTZNVEZ3ZUR0amIyeHZjanAyWVhJb0xTMXRkWFJsWkNrN2JHbHVaUzFvWldsbmFIUTZNUzQxTlgwdWNHOWpMV1Z0'
    || 'Y0hSNWUzQmhaR1JwYm1jNk1qQndlRHRpYjNKa1pYSXRjbUZrYVhWek9uWmhjaWd0TFhKaFpHbDFjeWs3WW05eVpHVnlPakZ3ZUNCa1lYTm9aV1FnZG1GeUtD'
    || 'MHRiR2x1WlMweUtUdGlZV05yWjNKdmRXNWtPblpoY2lndExYTjFjbVpoWTJVcGZTNXdiMk10Wlcxd2RIa2dhRE43YldGeVoybHVPakE3Wm05dWRDMXphWHBs'
    || 'T2pFMGNIZzdZMjlzYjNJNmRtRnlLQzB0Ym1GMmVTbDlMbkJ2WXkxbGJYQjBlU0J3ZTIxaGNtZHBiam8yY0hnZ01DQXhNSEI0TzJadmJuUXRjMmw2WlRveE1p'
    || 'NDFjSGc3WTI5c2IzSTZkbUZ5S0MwdGJYVjBaV1FwTzJ4cGJtVXRhR1ZwWjJoME9qRXVOWDB1Y0c5akxXVnRjSFI1SUdOdlpHVjdaR2x6Y0d4aGVUcGliRzlq'
    || 'YXp0d1lXUmthVzVuT2pod2VDQXhNSEI0TzJKdmNtUmxjaTF5WVdScGRYTTZObkI0TzJKaFkydG5jbTkxYm1RNmRtRnlLQzB0YzNWeVptRmpaUzB5S1R0aWIz'
    || 'SmtaWEk2TVhCNElITnZiR2xrSUhaaGNpZ3RMV3hwYm1VcE8yWnZiblF0YzJsNlpUb3hNWEI0TzJOdmJHOXlPblpoY2lndExYUmxlSFFwTzNkb2FYUmxMWE53'
    || 'WVdObE9uQnlaUzEzY21Gd08zZHZjbVF0WW5KbFlXczZZbkpsWVdzdGQyOXlaSDB1YVc1emNHVmpkSHRrYVhOd2JHRjVPbWR5YVdRN1ozSnBaQzEwWlcxd2JH'
    || 'RjBaUzFqYjJ4MWJXNXpPbTFwYm0xaGVDZ3dMREZtY2lrZ016QXdjSGc3WjJGd09qRTJjSGc3WVd4cFoyNHRhWFJsYlhNNmMzUmhjblI5TG1sdWMzQmxZM1Jm'
    || 'WDJ4cGMzUjdiV2x1TFhkcFpIUm9PakI5TG1sdWMzQmxZM1JmWDJSbGRHRnBiSHRpWVdOclozSnZkVzVrT25aaGNpZ3RMWE4xY21aaFkyVXRNaWs3WW05eVpH'
    || 'VnlPakZ3ZUNCemIyeHBaQ0IyWVhJb0xTMXNhVzVsS1R0aWIzSmtaWEl0Y21Ga2FYVnpPblpoY2lndExYSmhaR2wxY3lrN2NHRmtaR2x1WnpveE5IQjRJREUx'
    || 'Y0hnZ01UVndlSDB1YVc1emNHVmpkRjlmZEdsMGJHVjdiV0Z5WjJsdU9qQWdNQ0F4TUhCNE8yWnZiblF0YzJsNlpUb3hOSEI0TzJadmJuUXRkMlZwWjJoME9q'
    || 'WXdNRHRqYjJ4dmNqcDJZWElvTFMxMFpYaDBLVHR2ZG1WeVpteHZkeTEzY21Gd09tRnVlWGRvWlhKbGZTNXBibk53WldOMFgxOW1hV1ZzWkhON1pHbHpjR3ho'
    || 'ZVRwbmNtbGtPMmR5YVdRdGRHVnRjR3hoZEdVdFkyOXNkVzF1Y3pwaGRYUnZJRzFwYm0xaGVDZ3dMREZtY2lrN1oyRndPamR3ZUNBeE1uQjRPMjFoY21kcGJq'
    || 'b3dmUzVwYm5Od1pXTjBYMTltYVdWc1pITWdaSFI3Wm05dWRDMXphWHBsT2pFeGNIZzdabTl1ZEMxM1pXbG5hSFE2TmpBd08zUmxlSFF0ZEhKaGJuTm1iM0p0'
    || 'T25Wd2NHVnlZMkZ6WlR0c1pYUjBaWEl0YzNCaFkybHVaem91TURSbGJUdGpiMnh2Y2pwMllYSW9MUzFrYVcwcE8zZG9hWFJsTFhOd1lXTmxPbTV2ZDNKaGNI'
    || 'MHVhVzV6Y0dWamRGOWZabWxsYkdSeklHUmtlMjFoY21kcGJqb3dPMlp2Ym5RdGMybDZaVG94TWk0MWNIZzdZMjlzYjNJNmRtRnlLQzB0ZEdWNGRDazdabTl1'
    || 'ZEMxMllYSnBZVzUwTFc1MWJXVnlhV002ZEdGaWRXeGhjaTF1ZFcxek8yOTJaWEptYkc5M0xYZHlZWEE2WVc1NWQyaGxjbVY5TG1sdWMzQmxZM1JmWDI1dmRH'
    || 'VjdiV0Z5WjJsdU9qRXljSGdnTUNBd08yWnZiblF0YzJsNlpUb3hNUzQxY0hnN1kyOXNiM0k2ZG1GeUtDMHRiWFYwWldRcE8yeHBibVV0YUdWcFoyaDBPakV1'
    || 'TlgwdWRHRmliR1V0TFhCcFkyc2dkR0p2WkhrZ2RISjdZM1Z5YzI5eU9uQnZhVzUwWlhKOUxuUmhZbXhsTFMxd2FXTnJJSFJpYjJSNUlIUnlPbWh2ZG1WeWUy'
    || 'SmhZMnRuY205MWJtUTZkbUZ5S0MwdGMzVnlabUZqWlMweUtYMHVkR0ZpYkdVdExYQnBZMnNnZEdKdlpIa2dkSEl1ZEhJdExXOXVlMkpoWTJ0bmNtOTFibVE2'
    || 'ZG1GeUtDMHRZV05qWlc1MExYZGhjMmdwZlM1MFlXSnNaUzB0Y0dsamF5QjBZbTlrZVNCMGNqcG1iMk4xY3kxMmFYTnBZbXhsZTI5MWRHeHBibVU2TW5CNElI'
    || 'TnZiR2xrSUhaaGNpZ3RMV0ZqWTJWdWRDazdiM1YwYkdsdVpTMXZabVp6WlhRNkxUSndlSDB1YzJWblgxOWlZWEo3WkdsemNHeGhlVHBwYm14cGJtVXRabXhs'
    || 'ZUR0bllYQTZNbkI0TzNCaFpHUnBibWM2TW5CNE8yMWhjbWRwYmkxaWIzUjBiMjA2TVRKd2VEdGlZV05yWjNKdmRXNWtPblpoY2lndExYTjFjbVpoWTJVdE1p'
    || 'azdZbTl5WkdWeU9qRndlQ0J6YjJ4cFpDQjJZWElvTFMxc2FXNWxLVHRpYjNKa1pYSXRjbUZrYVhWek9qaHdlSDB1YzJWblgxOWlkRzU3TFhkbFltdHBkQzFo'
    || 'Y0hCbFlYSmhibU5sT201dmJtVTdMVzF2ZWkxaGNIQmxZWEpoYm1ObE9tNXZibVU3WVhCd1pXRnlZVzVqWlRwdWIyNWxPMkp2Y21SbGNqb3dPMkpoWTJ0bmNt'
    || 'OTFibVE2ZEhKaGJuTndZWEpsYm5RN1kzVnljMjl5T25CdmFXNTBaWEk3Y0dGa1pHbHVaem8xY0hnZ01URndlRHRpYjNKa1pYSXRjbUZrYVhWek9qWndlRHRt'
    || 'YjI1ME9tbHVhR1Z5YVhRN1ptOXVkQzF6YVhwbE9qRXljSGc3Wm05dWRDMTNaV2xuYUhRNk5UQXdPMk52Ykc5eU9uWmhjaWd0TFcxMWRHVmtLWDB1YzJWblgx'
    || 'OWlkRzR0TFc5dWUySmhZMnRuY205MWJtUTZkbUZ5S0MwdGMzVnlabUZqWlNrN1kyOXNiM0k2ZG1GeUtDMHRkR1Y0ZENrN1ltOTRMWE5vWVdSdmR6cDJZWElv'
    || 'TFMxemFDMWpZWEprS1gwdWMyVm5YMTlpZEc0NlptOWpkWE10ZG1semFXSnNaWHR2ZFhSc2FXNWxPakp3ZUNCemIyeHBaQ0IyWVhJb0xTMWhZMk5sYm5RcE8y'
    || 'OTFkR3hwYm1VdGIyWm1jMlYwT2pGd2VIMHVkSEpsYm1SN1ltRmphMmR5YjNWdVpEcDJZWElvTFMxemRYSm1ZV05sS1R0aWIzSmtaWEk2TVhCNElITnZiR2xr'
    || 'SUhaaGNpZ3RMV3hwYm1VcE8ySnZjbVJsY2kxeVlXUnBkWE02ZG1GeUtDMHRjbUZrYVhWektUdHdZV1JrYVc1bk9qRXpjSGdnTVRWd2VDQXhOSEI0TzJScGMz'
    || 'QnNZWGs2Wm14bGVEdGhiR2xuYmkxcGRHVnRjenBtYkdWNExXVnVaRHRxZFhOMGFXWjVMV052Ym5SbGJuUTZjM0JoWTJVdFltVjBkMlZsYmp0bllYQTZNVFJ3'
    || 'ZUgwdWRISmxibVJmWDJobFlXUjdiV2x1TFhkcFpIUm9PakI5TG5SeVpXNWtYMTl6Y0dGeWEzdGthWE53YkdGNU9tWnNaWGc3Wm14bGVDMWthWEpsWTNScGIy'
    || 'NDZZMjlzZFcxdU8yRnNhV2R1TFdsMFpXMXpPbVpzWlhndFpXNWtPMmRoY0RvemNIZzdabXhsZURwdWIyNWxmUzUwY21WdVpGOWZkMmx1ZTJadmJuUXRjMmw2'
    || 'WlRveE1YQjRPMnhsZEhSbGNpMXpjR0ZqYVc1bk9pNHdOR1Z0TzNSbGVIUXRkSEpoYm5ObWIzSnRPblZ3Y0dWeVkyRnpaVHRqYjJ4dmNqcDJZWElvTFMxa2FX'
    || 'MHBmUzUwY21WdVpGOWZibTl1Wlh0bWIyNTBMWE5wZW1VNk1URXVOWEI0TzJOdmJHOXlPblpoY2lndExXUnBiU2s3Wm05dWRDMXpkSGxzWlRwdWIzSnRZV3g5'
    || 'TG5SeVpXNWtMUzFuYjI5a0lDNXpkR0YwWDE5MllXeDFaWHRqYjJ4dmNqcDJZWElvTFMxbmIyOWtLWDB1ZEhKbGJtUXRMWGRoY200Z0xuTjBZWFJmWDNaaGJI'
    || 'VmxlMk52Ykc5eU9uWmhjaWd0TFhkaGNtNHBmUzUwY21WdVpDMHRZbUZrSUM1emRHRjBYMTkyWVd4MVpYdGpiMnh2Y2pwMllYSW9MUzFpWVdRcGZVQnRaV1Jw'
    || 'WVNodFlYZ3RkMmxrZEdnNk1URXdNSEI0S1hzdWFXNXpjR1ZqZEh0bmNtbGtMWFJsYlhCc1lYUmxMV052YkhWdGJuTTZiV2x1YldGNEtEQXNNV1p5S1gxOUxt'
    || 'OTJiRjlmYzNWaWUyWnZiblF0YzJsNlpUb3hNWEI0TzJ4cGJtVXRhR1ZwWjJoME9qRXVNelU3WTI5c2IzSTZkbUZ5S0MwdFpHbHRLVHR0WVhKbmFXNDZNbkI0'
    || 'SURBZ05uQjRPMjkyWlhKbWJHOTNMWGR5WVhBNllXNTVkMmhsY21VN1ptOXVkQzEyWVhKcFlXNTBMVzUxYldWeWFXTTZkR0ZpZFd4aGNpMXVkVzF6ZlM1d1lX'
    || 'NWxiQzFsY25KdmNpMHRZWFY0ZTIxaGNtZHBiaTEwYjNBNk1UQndlRHR3WVdSa2FXNW5Pamh3ZUNBeE1IQjRPMlp2Ym5RdGMybDZaVG94TW5CNGZTNXdZVzVs'
    || 'YkMxbGNuSnZjaTB0WVhWNElIQjdiV0Z5WjJsdU9qUndlQ0F3SURad2VIMHVjR0Z1Wld3dGRISjFibU10TFdGMWVDd3VjR0Z1Wld3dGJtOTBZblZwYkhRdExX'
    || 'RjFlSHR0WVhKbmFXNHRkRzl3T2pFd2NIZzdabTl1ZEMxemFYcGxPakV5Y0hoOUxtUmxabXhwYzNSN2JXRnlaMmx1TFhSdmNEb3ljSGg5TG1SbFpteHBjM1Jm'
    || 'WDJobFlXUjdabTl1ZEMxemFYcGxPakV4Y0hnN1ptOXVkQzEzWldsbmFIUTZOekF3TzNSbGVIUXRkSEpoYm5ObWIzSnRPblZ3Y0dWeVkyRnpaVHRzWlhSMFpY'
    || 'SXRjM0JoWTJsdVp6b3VNRFJsYlR0amIyeHZjanAyWVhJb0xTMWthVzBwTzNCaFpHUnBibWN0WW05MGRHOXRPamh3ZUR0dFlYSm5hVzR0WW05MGRHOXRPakV3'
    || 'Y0hnN1ltOXlaR1Z5TFdKdmRIUnZiVG94Y0hnZ2MyOXNhV1FnZG1GeUtDMHRiR2x1WlNsOUxtUmxabXhwYzNSZlgyZHlhV1I3WkdsemNHeGhlVHBuY21sa08y'
    || 'TnZiSFZ0YmkxbllYQTZNelJ3ZUgwdVpHVm1iR2x6ZEY5ZlozSnBaQzB0TVh0bmNtbGtMWFJsYlhCc1lYUmxMV052YkhWdGJuTTZNV1p5ZlM1a1pXWnNhWE4w'
    || 'WDE5bmNtbGtMUzB5ZTJkeWFXUXRkR1Z0Y0d4aGRHVXRZMjlzZFcxdWN6b3habklnTVdaeWZVQnRaV1JwWVNodFlYZ3RkMmxrZEdnNk9UQXdjSGdwZXk1a1pX'
    || 'WnNhWE4wWDE5bmNtbGtMUzB5ZTJkeWFXUXRkR1Z0Y0d4aGRHVXRZMjlzZFcxdWN6b3habko5ZlM1a1pXWnNhWE4wWDE5eWIzZDdaR2x6Y0d4aGVUcG5jbWxr'
    || 'TzJkeWFXUXRkR1Z0Y0d4aGRHVXRZMjlzZFcxdWN6b3habklnWVhWMGJ6dG5jbWxrTFhSbGJYQnNZWFJsTFdGeVpXRnpPaUpzWVdKbGJDQjJZV3gxWlNJZ0lt'
    || 'NXZkR1VnYm05MFpTSTdZV3hwWjI0dGFYUmxiWE02WW1GelpXeHBibVU3WTI5c2RXMXVMV2RoY0RveE5uQjRPM0JoWkdScGJtYzZOWEI0SURBN2JXbHVMV2hs'
    || 'YVdkb2REb3lOSEI0TzJKdmNtUmxjaTFpYjNSMGIyMDZNWEI0SUhOdmJHbGtJSFpoY2lndExXeHBibVV0YzI5bWRDd2djbWRpWVNneE55d3hOeXd4Tnl3dU1E'
    || 'VXBLWDB1WkdWbWJHbHpkRjlmY205M09teGhjM1F0WTJocGJHUjdZbTl5WkdWeUxXSnZkSFJ2YlRvd2ZTNWtaV1pzYVhOMFgxOXNZV0psYkh0bmNtbGtMV0Z5'
    || 'WldFNmJHRmlaV3c3Wm05dWRDMXphWHBsT2pFeUxqVndlRHRqYjJ4dmNqcDJZWElvTFMxdGRYUmxaQ2w5TG1SbFpteHBjM1JmWDNaaGJIVmxlMmR5YVdRdFlY'
    || 'SmxZVHAyWVd4MVpUdG1iMjUwTFhOcGVtVTZNVEl1TlhCNE8yWnZiblF0ZDJWcFoyaDBPall3TUR0amIyeHZjanAyWVhJb0xTMTBaWGgwS1R0MFpYaDBMV0Zz'
    || 'YVdkdU9uSnBaMmgwTzJadmJuUXRkbUZ5YVdGdWRDMXVkVzFsY21sak9uUmhZblZzWVhJdGJuVnRjMzB1WkdWbWJHbHpkRjlmZG1Gc2RXVXRMV2R2YjJSN1ky'
    || 'OXNiM0k2ZG1GeUtDMHRaMjl2WkNsOUxtUmxabXhwYzNSZlgzWmhiSFZsTFMxM1lYSnVlMk52Ykc5eU9pTmlPRGN6TUdGOUxtUmxabXhwYzNSZlgzWmhiSFZs'
    || 'TFMxaVlXUjdZMjlzYjNJNmRtRnlLQzB0WW1Ga0tYMHVaR1ZtYkdsemRGOWZibTkwWlh0bmNtbGtMV0Z5WldFNmJtOTBaVHRtYjI1MExYTnBlbVU2TVRGd2VE'
    || 'dGpiMnh2Y2pwMllYSW9MUzFrYVcwcE8yeHBibVV0YUdWcFoyaDBPakV1TkRVN2JXRnlaMmx1TFhSdmNEb3ljSGg5TG0xbGRHaHZaSHRtYjI1MExYTnBlbVU2'
    || 'TVRGd2VEdGpiMnh2Y2pwMllYSW9MUzFrYVcwcE8yeHBibVV0YUdWcFoyaDBPakV1TlR0dFlYSm5hVzR0ZEc5d09qaHdlSDB1YldWMGFHOWtJSE4wY205dVoz'
    || 'dGpiMnh2Y2pwMllYSW9MUzF0ZFhSbFpDazdabTl1ZEMxM1pXbG5hSFE2TnpBd2ZTNWpaV3hzTFMxdVlYdG1iMjUwTFhOcGVtVTZNVEZ3ZUR0bWIyNTBMWGRs'
    || 'YVdkb2REbzNNREE3YkdWMGRHVnlMWE53WVdOcGJtYzZMakF6WlcwN1kyOXNiM0k2ZG1GeUtDMHRiWFYwWldRcE8yTjFjbk52Y2pwb1pXeHdmUzVqWld4c0xT'
    || 'MXViMjVsZTJOdmJHOXlPblpoY2lndExXUnBiU2s3WTNWeWMyOXlPbWhsYkhCOUxtRmpkQzF6ZFcxdFlYSjVlMlJwYzNCc1lYazZabXhsZUR0aGJHbG5iaTFw'
    || 'ZEdWdGN6cGpaVzUwWlhJN1oyRndPakV3Y0hnN1pteGxlQzEzY21Gd09uZHlZWEE3Y0dGa1pHbHVaem94TUhCNElERTBjSGc3WW05eVpHVnlPakZ3ZUNCemIy'
    || 'eHBaQ0IyWVhJb0xTMXNhVzVsS1R0aWIzSmtaWEl0Y21Ga2FYVnpPblpoY2lndExYSmhaR2wxY3lrN1ltRmphMmR5YjNWdVpEcDJZWElvTFMxemRYSm1ZV05s'
    || 'TFRJcE8yTjFjbk52Y2pwd2IybHVkR1Z5TzJadmJuUXRjMmw2WlRveE1pNDFjSGc3WTI5c2IzSTZkbUZ5S0MwdGJYVjBaV1FwTzJ4cGJtVXRhR1ZwWjJoME9q'
    || 'RXVOSDB1WVdOMExYTjFiVzFoY25rNmFHOTJaWEo3WW1GamEyZHliM1Z1WkRwMllYSW9MUzF6ZFhKbVlXTmxLVHRpYjNKa1pYSXRZMjlzYjNJNmRtRnlLQzB0'
    || 'YkdsdVpTMHlLWDB1WVdOMExYTjFiVzFoY25rNlptOWpkWE10ZG1semFXSnNaWHR2ZFhSc2FXNWxPakp3ZUNCemIyeHBaQ0IyWVhJb0xTMWhZMk5sYm5RcE8y'
    || 'OTFkR3hwYm1VdGIyWm1jMlYwT2pKd2VIMHVZV04wTFhOMWJXMWhjbmxmWDJOdmRXNTBlMlp2Ym5RdGQyVnBaMmgwT2pjd01EdGpiMnh2Y2pwMllYSW9MUzF1'
    || 'WVhaNUtYMHVZV04wTFhOMWJXMWhjbmxmWDNScFpYSjdabTl1ZEMxemFYcGxPakV4Y0hnN1ptOXVkQzEzWldsbmFIUTZOakF3TzNSbGVIUXRkSEpoYm5ObWIz'
    || 'SnRPblZ3Y0dWeVkyRnpaVHRzWlhSMFpYSXRjM0JoWTJsdVp6b3VNRFJsYlR0d1lXUmthVzVuT2pGd2VDQTNjSGc3WW05eVpHVnlMWEpoWkdsMWN6bzBjSGc3'
    || 'WW1GamEyZHliM1Z1WkRwMllYSW9MUzF6ZFhKbVlXTmxLVHRpYjNKa1pYSTZNWEI0SUhOdmJHbGtJSFpoY2lndExXeHBibVVwTzJOdmJHOXlPblpoY2lndExX'
    || 'UnBiU2w5TG1GamRDMXpkVzF0WVhKNVgxOWphR1YyY205dWUyMWhjbWRwYmkxc1pXWjBPbUYxZEc4N1pteGxlRHB1YjI1bE8zUnlZVzV6YVhScGIyNDZkSEpo'
    || 'Ym5ObWIzSnRJQzR5Y3lCMllYSW9MUzFsWVhObEtUdGpiMnh2Y2pwMllYSW9MUzFrYVcwcGZTNWhZM1F0YzNWdGJXRnllVjlmWTJobGRuSnZiaTB0YjNCbGJu'
    || 'dDBjbUZ1YzJadmNtMDZjbTkwWVhSbEtERTRNR1JsWnlsOUxtUnlhV3hzTFhKdmQxOWZkRzluWjJ4bGV5MTNaV0pyYVhRdFlYQndaV0Z5WVc1alpUcHViMjVs'
    || 'T3kxdGIzb3RZWEJ3WldGeVlXNWpaVHB1YjI1bE8yRndjR1ZoY21GdVkyVTZibTl1WlR0aWIzSmtaWEk2TUR0aVlXTnJaM0p2ZFc1a09uUnlZVzV6Y0dGeVpX'
    || 'NTBPMk4xY25OdmNqcHdiMmx1ZEdWeU8yUnBjM0JzWVhrNlpteGxlRHRoYkdsbmJpMXBkR1Z0Y3pwalpXNTBaWEk3WjJGd09qaHdlRHQzYVdSMGFEb3hNREFs'
    || 'TzNCaFpHUnBibWM2T0hCNElERXdjSGc3ZEdWNGRDMWhiR2xuYmpwc1pXWjBPMlp2Ym5RNmFXNW9aWEpwZER0amIyeHZjanBwYm1obGNtbDBPMkp2Y21SbGNp'
    || 'MXlZV1JwZFhNNk5uQjRmUzVrY21sc2JDMXliM2RmWDNSdloyZHNaVHBvYjNabGNudGlZV05yWjNKdmRXNWtPblpoY2lndExYTjFjbVpoWTJVdE1pbDlMbVJ5'
    || 'YVd4c0xYSnZkMTlmZEc5bloyeGxPbVp2WTNWekxYWnBjMmxpYkdWN2IzVjBiR2x1WlRveWNIZ2djMjlzYVdRZ2RtRnlLQzB0WVdOalpXNTBLVHR2ZFhSc2FX'
    || 'NWxMVzltWm5ObGREb3RNbkI0ZlM1a2NtbHNiQzF5YjNkZlgyTm9aWFp5YjI1N1pteGxlRHB1YjI1bE8zUnlZVzV6YVhScGIyNDZkSEpoYm5ObWIzSnRJQzR4'
    || 'Tm5NZ2RtRnlLQzB0WldGelpTazdZMjlzYjNJNmRtRnlLQzB0WkdsdEtYMHVaSEpwYkd3dGNtOTNYMTlqYUdWMmNtOXVMUzF2Y0dWdWUzUnlZVzV6Wm05eWJU'
    || 'cHliM1JoZEdVb09UQmtaV2NwZlM1a2NtbHNiQzF5YjNkZlgyTm9hV3hrY21WdWUyOTJaWEptYkc5M09taHBaR1JsYmp0MGNtRnVjMmwwYVc5dU9tMWhlQzFv'
    || 'WldsbmFIUWdMakp6SUhaaGNpZ3RMV1ZoYzJVcE8zQmhaR1JwYm1jdGJHVm1kRG94T0hCNGZTNW9iM1psY2kxa1pYUmhhV3g3Y0c5emFYUnBiMjQ2Wm1sNFpX'
    || 'UTdlaTFwYm1SbGVEbzVNREE3Y0c5cGJuUmxjaTFsZG1WdWRITTZibTl1WlR0aVlXTnJaM0p2ZFc1a09uWmhjaWd0TFhOMWNtWmhZMlVwTzJKdmNtUmxjam94'
    || 'Y0hnZ2MyOXNhV1FnZG1GeUtDMHRiR2x1WlMweUtUdGliM0prWlhJdGNtRmthWFZ6T2pod2VEdHdZV1JrYVc1bk9qaHdlQ0F4TVhCNE8ySnZlQzF6YUdGa2Iz'
    || 'YzZkbUZ5S0MwdGMyZ3RiV1FwTzJadmJuUXRjMmw2WlRveE1uQjRPMk52Ykc5eU9uWmhjaWd0TFhSbGVIUXBPMnhwYm1VdGFHVnBaMmgwT2pFdU5EVTdiV0Y0'
    || 'TFhkcFpIUm9Pakk0TUhCNE8zZG9hWFJsTFhOd1lXTmxPbTV2Y20xaGJIMHVjMk5oYkdVdFltRnllMlJwYzNCc1lYazZabXhsZUR0M2FXUjBhRG94TURBbE8y'
    || 'aGxhV2RvZERveU1uQjRPMkp2Y21SbGNpMXlZV1JwZFhNNk5IQjRPMjkyWlhKbWJHOTNPbWhwWkdSbGJuMHVjMk5oYkdVdFltRnlYMTl6WldkN2JXbHVMWGRw'
    || 'WkhSb09qSndlRHR3YjNOcGRHbHZianB5Wld4aGRHbDJaWDB1YzJOaGJHVXRZbUZ5WDE5elpXYzZabWx5YzNRdFkyaHBiR1I3WW05eVpHVnlMWEpoWkdsMWN6'
    || 'bzBjSGdnTUNBd0lEUndlSDB1YzJOaGJHVXRZbUZ5WDE5elpXYzZiR0Z6ZEMxamFHbHNaSHRpYjNKa1pYSXRjbUZrYVhWek9qQWdOSEI0SURSd2VDQXdmUzV6'
    || 'WTJGc1pTMWlZWEpmWDJ4aFltVnNlM0J2YzJsMGFXOXVPbUZpYzI5c2RYUmxPM1J2Y0Rvd08zSnBaMmgwT2pBN1ltOTBkRzl0T2pBN2JHVm1kRG93TzJScGMz'
    || 'QnNZWGs2Wm14bGVEdGhiR2xuYmkxcGRHVnRjenBqWlc1MFpYSTdhblZ6ZEdsbWVTMWpiMjUwWlc1ME9tTmxiblJsY2p0bWIyNTBMWE5wZW1VNk1URndlRHRt'
    || 'YjI1MExYZGxhV2RvZERvMk1EQTdZMjlzYjNJNkkyWm1aanR2ZG1WeVpteHZkenBvYVdSa1pXNDdkR1Y0ZEMxdmRtVnlabXh2ZHpwbGJHeHBjSE5wY3p0M2FH'
    || 'bDBaUzF6Y0dGalpUcHViM2R5WVhBN2NHRmtaR2x1Wnpvd0lEUndlSDBLIgpTT0xVVElPTl9OQU1FID0gIldhcmVob3VzZSBHZW5lcmF0aW9uIOKAlCBHZW4y'
    || 'IGFuZCBBZGFwdGl2ZSIKR0xPQkFMX05BTUUgPSAiX19XSEdFTl9EQVRBX18iCkFQUF9PQkpFQ1QgPSAiV0hHRU5fQVBQIgoKaW1wb3J0IGpzb24KaW1wb3J0'
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
    || 'YXRpb24gdW5kZXIgdGhlIHdpZGdldApDT05UUk9MUyA9IFtdCiMgVHdvIGNvbnRyb2xzLCBib3RoIGNob3NlbiBzbyB0aGF0IHRoZWlyIERFRkFVTFRTIHJl'
    || 'cHJvZHVjZSBleGFjdGx5IHdoYXQgdGhpcyBwYWdlCiMgc2hvd2VkIGJlZm9yZSB0aGV5IGV4aXN0ZWQuIGBtaW5fY3JlZGl0c2AgZGVmYXVsdHMgdG8gMCwg'
    || 'd2hpY2ggZmlsdGVycyBub3RoaW5nOwojIGB3aGAgZGVmYXVsdHMgdG8gTm9uZSwgd2hpY2ggdGhlIGRyaWxsLWRvd24gcGFuZWxzIHJlc29sdmUgdG8gdGhl'
    || 'IHdhcmVob3VzZSB3aXRoCiMgdGhlIG1vc3QgY3JlZGl0cyBhdCBzdGFrZS4gQW55dGhpbmcgZWxzZSB3b3VsZCBtZWFuIGFkZGluZyBjb250cm9scyBzaWxl'
    || 'bnRseQojIGNoYW5nZWQgdGhlIGRlbGl2ZXJhYmxlLgpDT05UUk9MUyA9IFsKICAgICMgVGhlIGRyaWxsLWRvd24uIEEgdmVyZGljdCB0YWJsZSB3aXRoIDQw'
    || 'IHJvd3MgYW5zd2VycyAid2hpY2ggd2FyZWhvdXNlcyIsIGFuZAogICAgIyB0aGlzIGFuc3dlcnMgdGhlIHF1ZXN0aW9uIGEgcmVhZGVyIGhhcyBpbW1lZGlh'
    || 'dGVseSBhZnRlcndhcmRzIC0tICJzbyB3aGF0CiAgICAjIGFib3V0IFRISVMgb25lIiAtLSB3aGljaCBwcmV2aW91c2x5IHJlcXVpcmVkIGxlYXZpbmcgdGhl'
    || 'IGFwcCBhbmQgd3JpdGluZyBTUUwuCiAgICB7ImtleSI6ICJ3aCIsCiAgICAgImxhYmVsIjogIldhcmVob3VzZSIsCiAgICAgImtpbmQiOiAic2VsZWN0IiwK'
    || 'ICAgICAiZGVmYXVsdCI6IE5vbmUsCiAgICAgIm9wdGlvbnNfc3FsIjogKCJTRUxFQ1QgV0FSRUhPVVNFX05BTUUgRlJPTSB7dGd0fS5WX0dFTjJfVkVSRElD'
    || 'VCAiCiAgICAgICAgICAgICAgICAgICAgICJPUkRFUiBCWSBDUkVESVRTX1BFUl9EQVkgREVTQyIpLAogICAgICJoZWxwIjogIlBpY2sgb25lIHRvIHNlZSBp'
    || 'dHMgb3duIG51bWJlcnMsIGFuZCB0aGUgYmFyIGl0IGhhcyB0byBjbGVhci4ifSwKCiAgICAjIEEgZmxvb3IsIG5vdCBhIGNhcDogYW4gYWNjb3VudCB3aXRo'
    || 'IDgwIHdhcmVob3VzZXMgaGFzIGEgbG9uZyB0YWlsIHdob3NlCiAgICAjIHZlcmRpY3RzIGFyZSByZWFsIGJ1dCBpbW1hdGVyaWFsLCBhbmQgaGlkaW5nIHRo'
    || 'ZW0gaXMgYSByZWFkZXIncyBkZWNpc2lvbgogICAgIyByYXRoZXIgdGhhbiBvdXJzLiAwIHNob3dzIGV2ZXJ5dGhpbmcsIHdoaWNoIGlzIHRoZSBwcmV2aW91'
    || 'cyBiZWhhdmlvdXIuCiAgICB7ImtleSI6ICJtaW5fY3JlZGl0cyIsCiAgICAgImxhYmVsIjogIk1pbmltdW0gY3JlZGl0cy9kYXkiLAogICAgICJraW5kIjog'
    || 'InNsaWRlciIsCiAgICAgImRlZmF1bHQiOiAwLAogICAgICJtaW4iOiAwLAogICAgICJtYXgiOiAxMDAsCiAgICAgInN0ZXAiOiA1LAogICAgICJoZWxwIjog'
    || 'IkhpZGUgd2FyZWhvdXNlcyB0b28gc21hbGwgZm9yIGEgY29udmVyc2lvbiB0byBiZSB3b3J0aCB0aGUgcmlzay4ifSwKXQoKUEFORUxTID0gewogICAgIyBU'
    || 'aGUgc2hlbGwgcmVhZHMgTU9ERSBmcm9tIGhlcmUgZm9yIHRoZSBTQU1QTEUgYmFubmVyLiBSZXF1aXJlZCBpbiBldmVyeQogICAgIyBzb2x1dGlvbi4KICAg'
    || 'ICJjb250ZXh0IjogIlNFTEVDVCAqIEZST00ge3RndH0uVl9CVUlMRF9DT05URVhUIiwKCiAgICAjIE9uZSByb3cuIFRoZSByYXRlIHByZW1pdW0sIHdoZXJl'
    || 'IGl0IGNhbWUgZnJvbSwgYW5kIHRoZSBicmVhay1ldmVuIGJhciBldmVyeQogICAgIyB2ZXJkaWN0IGlzIGp1ZGdlZCBhZ2FpbnN0LgogICAgImVjb25vbWlj'
    || 'cyI6ICgKICAgICAgICAiU0VMRUNUIENMT1VELCBSRUdJT04sIEdFTjJfUkFURV9NVUxUSVBMSUVSLCBSRVFVSVJFRF9TUEVFRFVQX1BDVCwgIgogICAgICAg'
    || 'ICJNVUxUSVBMSUVSX1NPVVJDRSwgSE9XX1RPX1JFQURfSVQgRlJPTSB7dGd0fS5WX0dFTjJfRUNPTk9NSUNTIgogICAgKSwKCiAgICAjIFRoZSBkZWxpdmVy'
    || 'YWJsZS4gT3JkZXJlZCBzbyB0aGUgd2FyZWhvdXNlcyB3b3J0aCBjb252ZXJ0aW5nIGFyZSBhdCB0aGUgdG9wCiAgICAjIGFuZCB0aGUgb25lcyB0aGF0IHdv'
    || 'dWxkIGNvc3QgbW9uZXkgaWYgY29udmVydGVkIGFyZSB2aXNpYmxlIHJhdGhlciB0aGFuCiAgICAjIGZpbHRlcmVkIGF3YXkgLS0gYW4gQVZPSUQgcm93IGlz'
    || 'IGEgZmluZGluZywgbm90IG5vaXNlLgogICAgIwogICAgIyA6bWluX2NyZWRpdHMgaXMgYSBGTE9PUiB0aGUgcmVhZGVyIHNldHMsIGRlZmF1bHRpbmcgdG8g'
    || 'MCBzbyB0aGlzIGlzIHRoZSBzYW1lCiAgICAjIHF1ZXJ5IGl0IGFsd2F5cyB3YXMuIENPQUxFU0NFIGd1YXJkcyB0aGUgYmluZCByYXRoZXIgdGhhbiB0aGUg'
    || 'Y29sdW1uOiBhIE5VTEwKICAgICMgdGhyZXNob2xkIG11c3QgbWVhbiAibm8gZmxvb3IiLCBub3QgIm5vIHJvd3MiLgogICAgImdlbjIiOiAoCiAgICAgICAg'
    || 'IlNFTEVDVCBXQVJFSE9VU0VfTkFNRSwgV0hfU0laRSwgV0hfVFlQRSwgR0VORVJBVElPTiwgVkVSRElDVCwgIgogICAgICAgICJDUkVESVRTX1VTRUQsIENS'
    || 'RURJVFNfUEVSX0RBWSwgVVRJTElTQVRJT04sIEZBVk9VUkFCTEVfU0hBUkUsICIKICAgICAgICAiUVVFVUVEX1NFQ09ORFMsIFNQSUxMX0dCLCBRVUVSWV9D'
    || 'T1VOVCwgUkVRVUlSRURfU1BFRURVUF9QQ1QsICIKICAgICAgICAiV09SU1RfQ0FTRV9FWFRSQV9DUkVESVRTX1BFUl9EQVksIFdIWSwgIgogICAgICAgICMg'
    || 'UUFTIHJpZGVzIG9uIHRoaXMgdGFibGUgcmF0aGVyIHRoYW4gYSBzZXBhcmF0ZSBvbmUgYmVjYXVzZSBpdCBpcyBhCiAgICAgICAgIyBwcm9wZXJ0eSBvZiB0'
    || 'aGUgU0FNRSBkZWNpc2lvbjogY29udmVydGluZyB0byBHZW4yIGJ5IEFMVEVSIGxlYXZlcyBRQVMKICAgICAgICAjIG9mZiwgc28gYSByZWFkZXIgbG9va2lu'
    || 'ZyBhdCBhIGNvbnZlcnNpb24gdmVyZGljdCBoYXMgdG8gc2VlIGl0IGhlcmUuCiAgICAgICAgIlFBU19FTkFCTEVELCBRQVNfVkVSRElDVCwgUUFTX0VMSUdJ'
    || 'QkxFX1NIQVJFLCBRQVNfV0hZICIKICAgICAgICAiRlJPTSB7dGd0fS5WX0dFTjJfVkVSRElDVCAiCiAgICAgICAgIldIRVJFIENPQUxFU0NFKENSRURJVFNf'
    || 'UEVSX0RBWSwgMCkgPj0gQ09BTEVTQ0UoOm1pbl9jcmVkaXRzLCAwKSAiCiAgICAgICAgIk9SREVSIEJZIENBU0UgVkVSRElDVCBXSEVOICdTVFJPTkcnIFRI'
    || 'RU4gMSBXSEVOICdMSUtFTFknIFRIRU4gMiAiCiAgICAgICAgIldIRU4gJ1BJTE9UX09OTFknIFRIRU4gMyBXSEVOICdBVk9JRCcgVEhFTiA0IEVMU0UgNSBF'
    || 'TkQsICIKICAgICAgICAiQ1JFRElUU19QRVJfREFZIERFU0MiCiAgICApLAoKICAgICMgVEhFIERSSUxMLURPV04uIE9uZSB3YXJlaG91c2UsIGJvdGggZGVj'
    || 'aXNpb25zIHNpZGUgYnkgc2lkZSwgc28gdGhlIHF1ZXN0aW9uCiAgICAjICJzaG91bGQgSSBjb252ZXJ0IHRoaXMgb25lIiBpcyBhbnN3ZXJlZCB3aXRob3V0'
    || 'IGxlYXZpbmcgdGhlIHBhZ2UuCiAgICAjCiAgICAjIFRoZSBiaW5kIGlzIHdyYXBwZWQgaW4gQ09BTEVTQ0UgYWdhaW5zdCB0aGUgdG9wIHdhcmVob3VzZSBm'
    || 'b3IgdHdvIHJlYXNvbnM6CiAgICAjIHRoZSBhcHAncyBzZWxlY3Rib3ggYWx3YXlzIHN1cHBsaWVzIGEgbmFtZSwgYnV0IGdhdW50bGV0IHN0ZXAgMTAgYmlu'
    || 'ZHMgdGhlCiAgICAjIGRlY2xhcmVkIGRlZmF1bHQgb2YgTlVMTCwgYW5kIGA9IE5VTExgIHdvdWxkIG1ha2UgdGhlIHBhbmVsIHNpbGVudGx5IHJldHVybgog'
    || 'ICAgIyBub3RoaW5nIC0tIHNvIHRoZSBjaGVjayB3b3VsZCBwYXNzIHdoaWxlIHByb3ZpbmcgdGhlIHF1ZXJ5IG5ldmVyIHdvcmtlZC4gVGhpcwogICAgIyB3'
    || 'YXkgc3RlcCAxMCBleGVyY2lzZXMgdGhlIHJlYWwgcGF0aCBvbiB0aGUgYmlnZ2VzdCB3YXJlaG91c2UuCiAgICAid2hfZGV0YWlsIjogKAogICAgICAgICJX'
    || 'SVRIIHBpY2sgQVMgKFNFTEVDVCBDT0FMRVNDRSg6d2gsICgiCiAgICAgICAgIiAgU0VMRUNUIFdBUkVIT1VTRV9OQU1FIEZST00ge3RndH0uVl9HRU4yX1ZF'
    || 'UkRJQ1QgIgogICAgICAgICIgIE9SREVSIEJZIENSRURJVFNfUEVSX0RBWSBERVNDIExJTUlUIDEpKSBBUyBXQVJFSE9VU0VfTkFNRSkgIgogICAgICAgICJT'
    || 'RUxFQ1QgZy5XQVJFSE9VU0VfTkFNRSwgZy5XSF9TSVpFLCBnLldIX1RZUEUsIGcuR0VORVJBVElPTiwgIgogICAgICAgICJnLlZFUkRJQ1QgQVMgR0VOMl9W'
    || 'RVJESUNULCBnLlJFUVVJUkVEX1NQRUVEVVBfUENULCAiCiAgICAgICAgImcuV09SU1RfQ0FTRV9FWFRSQV9DUkVESVRTX1BFUl9EQVksIGcuQ1JFRElUU19Q'
    || 'RVJfREFZLCBnLkNSRURJVFNfVVNFRCwgIgogICAgICAgICJnLlVUSUxJU0FUSU9OLCBnLkZBVk9VUkFCTEVfU0hBUkUsIGcuUVVFVUVEX1NFQ09ORFMsIGcu'
    || 'U1BJTExfR0IsICIKICAgICAgICAiZy5RVUVSWV9DT1VOVCwgZy5XSFkgQVMgR0VOMl9XSFksICIKICAgICAgICAiYS5WRVJESUNUIEFTIEFEQVBUSVZFX1ZF'
    || 'UkRJQ1QsIGEuREFJTFlfQ1YsIGEuTUFYX0NMVVNURVJTLCAiCiAgICAgICAgImEuV0hZIEFTIEFEQVBUSVZFX1dIWSwgYS5FTElHSUJJTElUWV9OT1RFLCAi'
    || 'CiAgICAgICAgImcuUUFTX0VOQUJMRUQsIGcuUUFTX1NDQUxFX0ZBQ1RPUiwgZy5RQVNfVkVSRElDVCwgIgogICAgICAgICJnLlFBU19FTElHSUJMRV9RVUVS'
    || 'SUVTLCBnLlFBU19FTElHSUJMRV9TRUNPTkRTLCBnLlFBU19FTElHSUJMRV9TSEFSRSwgIgogICAgICAgICJnLlFBU19QUk9QT1NFRF9TQ0FMRV9GQUNUT1Is'
    || 'IGcuUUFTX1dIWSAiCiAgICAgICAgIkZST00gcGljayBwICIKICAgICAgICAiSk9JTiB7dGd0fS5WX0dFTjJfVkVSRElDVCBnIE9OIGcuV0FSRUhPVVNFX05B'
    || 'TUUgPSBwLldBUkVIT1VTRV9OQU1FICIKICAgICAgICAiTEVGVCBKT0lOIHt0Z3R9LlZfQURBUFRJVkVfVkVSRElDVCBhICIKICAgICAgICAiICBPTiBhLldB'
    || 'UkVIT1VTRV9OQU1FID0gcC5XQVJFSE9VU0VfTkFNRSIKICAgICksCgogICAgIyBUaGUgUUFTIGdhcCwgcmFua2VkLiBUaGlzIGV4aXN0cyBiZWNhdXNlIG9m'
    || 'IGEgc3BlY2lmaWMgYXN5bW1ldHJ5OiBTbm93Zmxha2UKICAgICMgdHVybnMgUXVlcnkgQWNjZWxlcmF0aW9uIE9OIGJ5IGRlZmF1bHQgZm9yIGEgd2FyZWhv'
    || 'dXNlIENSRUFURUQgYXMgR2VuMiBhbmQKICAgICMgbGVhdmVzIGl0IE9GRiB3aGVuIGFuIGV4aXN0aW5nIHdhcmVob3VzZSBpcyBBTFRFUmVkIHRvIEdlbjIu'
    || 'IEEgY2xpZW50IHdobwogICAgIyBjb252ZXJ0cyBhIGNvaG9ydCB0aGVyZWZvcmUgZW5kcyB1cCB3aXRoIHdhcmVob3VzZXMgY29uZmlndXJlZCBkaWZmZXJl'
    || 'bnRseQogICAgIyBmcm9tIG5ldyBHZW4yIG9uZXMsIGFuZCBub3RoaW5nIGluIHRoZSBjb252ZXJzaW9uIHNheXMgc28uCiAgICAjCiAgICAjIE9yZGVyZWQg'
    || 'c28gUkVDT01NRU5ERUQgc2l0cyBhdCB0aGUgdG9wIGFuZCBPTiBhdCB0aGUgYm90dG9tOiB0aGUgcmVhZGVyIHdhbnRzCiAgICAjIHRoZSBsaXN0IG9mIHRo'
    || 'aW5ncyBzdGlsbCB0byBkbywgbm90IGEgZmxlZXQgY2Vuc3VzLgogICAgInFhcyI6ICgKICAgICAgICAiU0VMRUNUIFdBUkVIT1VTRV9OQU1FLCBXSF9TSVpF'
    || 'LCBHRU5FUkFUSU9OLCBRQVNfRU5BQkxFRCwgUUFTX1NDQUxFX0ZBQ1RPUiwgIgogICAgICAgICJRQVNfVkVSRElDVCwgUUFTX0VMSUdJQkxFX1FVRVJJRVMs'
    || 'IFFBU19FTElHSUJMRV9TRUNPTkRTLCBRQVNfRUxJR0lCTEVfU0hBUkUsICIKICAgICAgICAiUUFTX1BST1BPU0VEX1NDQUxFX0ZBQ1RPUiwgQ1JFRElUU19Q'
    || 'RVJfREFZLCBRQVNfV0hZLCAiCiAgICAgICAgIlFBU19USFJFU0hPTERfSVNfSlVER0VNRU5UICIKICAgICAgICAiRlJPTSB7dGd0fS5WX0dFTjJfVkVSRElD'
    || 'VCAiCiAgICAgICAgIk9SREVSIEJZIENBU0UgUUFTX1ZFUkRJQ1QgV0hFTiAnUkVDT01NRU5ERUQnIFRIRU4gMSBXSEVOICdOT19FVklERU5DRScgVEhFTiAy'
    || 'ICIKICAgICAgICAiV0hFTiAnTk9UX1dPUlRIX0lUJyBUSEVOIDMgV0hFTiAnSU5FTElHSUJMRV9UWVBFJyBUSEVOIDQgRUxTRSA1IEVORCwgIgogICAgICAg'
    || 'ICJDT0FMRVNDRShRQVNfRUxJR0lCTEVfU0VDT05EUywgMCkgREVTQywgQ1JFRElUU19QRVJfREFZIERFU0MiCiAgICApLAoKICAgICMgQWRhcHRpdmUgaXMg'
    || 'YSBzZXBhcmF0ZSBkZWNpc2lvbiB3aXRoIGRpZmZlcmVudCBlbGlnaWJpbGl0eSwgc28gaXQgZ2V0cyBpdHMKICAgICMgb3duIHRhYmxlIHJhdGhlciB0aGFu'
    || 'IGFub3RoZXIgY29sdW1uIG9uIHRoZSBHZW4yIG9uZS4KICAgICJhZGFwdGl2ZSI6ICgKICAgICAgICAiU0VMRUNUIFdBUkVIT1VTRV9OQU1FLCBXSF9TSVpF'
    || 'LCBXSF9UWVBFLCBWRVJESUNULCBDUkVESVRTX1VTRUQsICIKICAgICAgICAiQ1JFRElUU19QRVJfREFZLCBEQUlMWV9DViwgTUFYX0NMVVNURVJTLCBRVUVV'
    || 'RURfU0VDT05EUywgVVRJTElTQVRJT04sICIKICAgICAgICAiV0hZLCBFTElHSUJJTElUWV9OT1RFLCBDT1NUX01PREVMX05PVEUgIgogICAgICAgICJGUk9N'
    || 'IHt0Z3R9LlZfQURBUFRJVkVfVkVSRElDVCAiCiAgICAgICAgIk9SREVSIEJZIENBU0UgVkVSRElDVCBXSEVOICdTVFJPTkcnIFRIRU4gMSBXSEVOICdMSUtF'
    || 'TFknIFRIRU4gMiAiCiAgICAgICAgIldIRU4gJ1BJTE9UX09OTFknIFRIRU4gMyBXSEVOICdLRUVQX1NUQU5EQVJEJyBUSEVOIDQgRUxTRSA1IEVORCwgIgog'
    || 'ICAgICAgICJDUkVESVRTX1BFUl9EQVkgREVTQyIKICAgICksCgogICAgIyBUaGUgYmVmb3JlLXBpY3R1cmUsIGNhcHR1cmVkIGF0IGJ1aWxkIHRpbWUuIEVt'
    || 'cHR5IG9mIGludGVyZXN0IHVudGlsIGEKICAgICMgY29udmVyc2lvbiBoYXBwZW5zLCBhbmQgc2hvd24gYW55d2F5IHNvIGEgcmVhZGVyIGNhbiBzZWUgdGhl'
    || 'IG1lYXN1cmVtZW50CiAgICAjIHdhcyBzZXQgdXAgaW4gYWR2YW5jZSByYXRoZXIgdGhhbiByZWNvbnN0cnVjdGVkIGFmdGVyd2FyZHMuCiAgICAiYmFzZWxp'
    || 'bmUiOiAoCiAgICAgICAgIlNFTEVDVCBXQVJFSE9VU0VfTkFNRSwgV0hfU0laRSwgR0VORVJBVElPTl9CRUZPUkUsIFdIX1RZUEVfQkVGT1JFLCAiCiAgICAg'
    || 'ICAgIldJTkRPV19EQVlTLCBDUkVESVRTX1VTRUQsIENSRURJVFNfUEVSX0RBWSwgUVVFUllfQ09VTlQsICIKICAgICAgICAiU0VDT05EU19QRVJfUVVFUlks'
    || 'IFVUSUxJU0FUSU9OLCBGQVZPVVJBQkxFX1NIQVJFLCBDQVBUVVJFRF9BVCwgTEFCRUwgIgogICAgICAgICJGUk9NIHt0Z3R9LkNPTlZFUlNJT05fQkFTRUxJ'
    || 'TkUgIgogICAgICAgICJPUkRFUiBCWSBDUkVESVRTX1BFUl9EQVkgREVTQyBMSU1JVCA1MCIKICAgICksCgogICAgIyBXaGF0IHRoZSBjb252ZXJzaW9ucyBh'
    || 'Y3R1YWxseSBkaWQuIFRoaXMgaXMgdGhlIHBhbmVsIHRoYXQgc2V0dGxlcyB0aGUKICAgICMgYXJndW1lbnQsIGFuZCBpdCBzdGF5cyBlbXB0eSB1bnRpbCBz'
    || 'b21lYm9keSBwcmVzc2VzIGEgYnV0dG9uIC0tIHdoaWNoIGlzCiAgICAjIHRoZSBjb3JyZWN0IHN0YXRlIGZvciBpdCB0byBiZSBpbiBvbiBhIGZyZXNoIGlu'
    || 'c3RhbGwuCiAgICAib3V0Y29tZSI6ICgKICAgICAgICAiU0VMRUNUIFdBUkVIT1VTRV9OQU1FLCBXSF9TSVpFLCBHRU5FUkFUSU9OX0JFRk9SRSwgQ0hBTkdF'
    || 'RF9TRVRUSU5HLCAiCiAgICAgICAgIkNIQU5HRURfQVQsIERBWVNfT0JTRVJWRUQsIE9VVENPTUUsICIKICAgICAgICAiQkVGT1JFX0NSRURJVFNfUEVSX0RB'
    || 'WSwgQUZURVJfQ1JFRElUU19QRVJfREFZLCAiCiAgICAgICAgIk9CU0VSVkVEX0RFTFRBX0NSRURJVFNfUEVSX0RBWSwgIgogICAgICAgICJCRUZPUkVfU0VD'
    || 'T05EU19QRVJfUVVFUlksIEFGVEVSX1NFQ09ORFNfUEVSX1FVRVJZLCAiCiAgICAgICAgIk9CU0VSVkVEX1NQRUVEVVBfUENULCBSRVFVSVJFRF9TUEVFRFVQ'
    || 'X1BDVCwgSE9XX1RPX1JFQURfSVQsIExBQkVMICIKICAgICAgICAiRlJPTSB7dGd0fS5WX0NPTlZFUlNJT05fT1VUQ09NRSAiCiAgICAgICAgIk9SREVSIEJZ'
    || 'IE9CU0VSVkVEX0RFTFRBX0NSRURJVFNfUEVSX0RBWSBERVNDIgogICAgKSwKCiAgICAjIFRoZSBsaXN0IG5vYm9keSBlbHNlIHByb2R1Y2VzOiBjb252ZXJz'
    || 'aW9ucyB0aGF0IGRpZCBub3QgcGF5IGZvciB0aGVtc2VsdmVzLgogICAgInJvbGxiYWNrIjogKAogICAgICAgICJTRUxFQ1QgV0FSRUhPVVNFX05BTUUsIENI'
    || 'QU5HRURfQVQsIERBWVNfT0JTRVJWRUQsICIKICAgICAgICAiQkVGT1JFX0NSRURJVFNfUEVSX0RBWSwgQUZURVJfQ1JFRElUU19QRVJfREFZLCAiCiAgICAg'
    || 'ICAgIk9CU0VSVkVEX0RFTFRBX0NSRURJVFNfUEVSX0RBWSwgQU5OVUFMSVNFRF9ERUxUQV9DUkVESVRTLCAiCiAgICAgICAgIk9CU0VSVkVEX1NQRUVEVVBf'
    || 'UENULCBSRVFVSVJFRF9TUEVFRFVQX1BDVCwgV0hBVF9UT19ETyAiCiAgICAgICAgIkZST00ge3RndH0uVl9ST0xMQkFDS19DQU5ESURBVEVTIgogICAgKSwK'
    || 'CiAgICAjIFdoZXJlIHRoZSBjcmVkaXRzIGFyZSwgc28gdGhlIHZlcmRpY3RzIGNhbiBiZSByZWFkIGFnYWluc3QgdGhlIHNpemUgb2YgdGhlCiAgICAjIGVz'
    || 'dGF0ZSByYXRoZXIgdGhhbiBpbiBpc29sYXRpb24uCiAgICAic3BlbmQiOiAoCiAgICAgICAgIlNFTEVDVCBXQVJFSE9VU0VfTkFNRSwgV0hfU0laRSwgR0VO'
    || 'RVJBVElPTiwgQ1JFRElUU19VU0VELCAiCiAgICAgICAgIkNSRURJVFNfUEVSX0RBWSwgQUNUSVZFX0RBWVMsIEJJTExFRF9TRUNPTkRTLCBRVUVSWV9TRUNP'
    || 'TkRTLCAiCiAgICAgICAgIlVUSUxJU0FUSU9OLCBTQ0FOTkVEX1RCICIKICAgICAgICAiRlJPTSB7dGd0fS5WX1dIX1dPUktMT0FEICIKICAgICAgICAiT1JE'
    || 'RVIgQlkgQ1JFRElUU19VU0VEIERFU0MgTElNSVQgMjUiCiAgICApLAoKICAgICMgVGhlIHdhdGNoIGhpc3RvcnksIHdoaWNoIGlzIHdoYXQgdHVybnMgYSBv'
    || 'bmUtb2ZmIGNvbnZlcnNpb24gaW50byBhIHByYWN0aWNlLgogICAgIndhdGNoIjogKAogICAgICAgICJTRUxFQ1QgQ0hFQ0tFRF9BVCwgV0FSRUhPVVNFX05B'
    || 'TUUsIERBWVNfT0JTRVJWRUQsIE9VVENPTUUsICIKICAgICAgICAiQkVGT1JFX0NSRURJVFNfUEVSX0RBWSwgQUZURVJfQ1JFRElUU19QRVJfREFZLCAiCiAg'
    || 'ICAgICAgIk9CU0VSVkVEX1NQRUVEVVBfUENULCBSRVFVSVJFRF9TUEVFRFVQX1BDVCAiCiAgICAgICAgIkZST00ge3RndH0uQ09OVkVSU0lPTl9XQVRDSF9M'
    || 'T0cgIgogICAgICAgICJPUkRFUiBCWSBDSEVDS0VEX0FUIERFU0MgTElNSVQgMTAwIgogICAgKSwKfQoKSEVJR0hUID0gMTkwMAoKIyDilIDilIAgU2hhcmVk'
    || 'IGFjdGlvbiBwYW5lbHMg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA'
    || '4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACiMgRXZlcnkg'
    || 'YnVpbGQgd2l0aCB0aGUgYWN0aW9uIGZyYW1ld29yayBjcmVhdGVzIFZfQUNUSU9OUyBhbmQgQUNUSU9OX0xPRzsgYnVpbGRzCiMgd2l0aG91dCBpdCBzaW1w'
    || 'bHkgcHJvZHVjZSBhICJkb2VzIG5vdCBleGlzdCIgZXJyb3IsIHdoaWNoIHRoZSBSZWFjdCBzaGVsbAojIHJlbmRlcnMgYXMgdGhlIHN0YW5kYXJkIG5vdC1i'
    || 'dWlsdCBzdGF0ZS4gQWRkZWQgaGVyZSByYXRoZXIgdGhhbiBpbiBldmVyeQojIHBhbmVscy5weSBzbyBhIG5ldyBzb2x1dGlvbiBnZXRzIHRoZW0gZm9yIGZy'
    || 'ZWUuClBBTkVMU1siYWN0aW9ucyJdID0gKAogICAgIlNFTEVDVCBDT0RFLCBMQUJFTCwgVElFUiwgRUZGRUNULCBFU1RfQ1JFRElUUywgU1RBVEVNRU5UUywg'
    || 'IgogICAgIlVORE9fU1RBVEVNRU5UUywgVElNRVNfUlVOLCBUSU1FU19VTkRPTkUgRlJPTSB7dGd0fS5WX0FDVElPTlMiCikKUEFORUxTWyJhY3Rpb25fbG9n'
    || 'Il0gPSAoCiAgICAiU0VMRUNUIENPREUsIFNUQVRVUywgU1RBVEVNRU5UU19SVU4sIFNUQVJURURfQVQsIEZJTklTSEVEX0FULCBFUlJPUiAiCiAgICAiRlJP'
    || 'TSB7dGd0fS5BQ1RJT05fTE9HIE9SREVSIEJZIFNUQVJURURfQVQgREVTQyBMSU1JVCAxMCIKKQoKIyDilIDilIAgU2hhcmVkIFBPQyBzdWNjZXNzIHBhbmVs'
    || 'cyDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi'
    || 'lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKIyBCb3RoIHZpZXdzIGFyZSBjcmVhdGVkIGJ5IGV2ZXJ5IGJ1'
    || 'aWxkLCBpbmNsdWRpbmcgYnVpbGRzIHdob3NlIHNvbHV0aW9uCiMgZGVjbGFyZWQgbm8gY3JpdGVyaWEgLS0gdGhvc2UgZ2V0IHRoZSBzaW5nbGUgIk5PIFNV'
    || 'Q0NFU1MgQ1JJVEVSSUEgREVDTEFSRUQiCiMgcm93IHJhdGhlciB0aGFuIGFuIGVtcHR5IHJlc3VsdCwgc28gdGhlIHRhYiBuZXZlciByZW5kZXJzIGJsYW5r'
    || 'IGFuZCBibGFuayBpcwojIG5ldmVyIG1pc3Rha2VuIGZvciB6ZXJvLgojCiMgUmVhZGluZyBWX1BPQ19TQ09SRUNBUkQgcmUtZXhlY3V0ZXMgdGhlIHRhcmdl'
    || 'dCBhbmQgYWN0dWFsIHNjYWxhcnMgaW5saW5lZCBpbnRvCiMgaXQsIHNvIHRoZXNlIHR3byBxdWVyaWVzIGFyZSBob3cgdGhlIG51bWJlcnMgc3RheSBsaXZl'
    || 'LiBUaGF0IGFsc28gbWVhbnMgdGhleQojIGFyZSB0aGUgbW9zdCBleHBlbnNpdmUgcGFuZWxzIGhlcmUsIGFuZCB0aGUgb25seSBvbmVzIHdob3NlIGNvc3Qg'
    || 'c2NhbGVzIHdpdGgKIyB0aGUgY3JpdGVyaWEgYSBzb2x1dGlvbiBkZWNsYXJlcy4KUEFORUxTWyJwb2Nfc2NvcmVjYXJkIl0gPSAoCiAgICAiU0VMRUNUIENP'
    || 'REUsIExBQkVMLCBXSFlfSVRfTUFUVEVSUywgVEFSR0VULCBBQ1RVQUwsIFVOSVRTLCBDT01QQVJFLCBCQVNJUywgIgogICAgIlRBUkdFVF9ERVJJVkFUSU9O'
    || 'LCBTVEFURSwgV0hZX05PVF9FVkFMVUFURUQsIFJFU09MVkVTX1dIRU4sIEFSSVRITUVUSUMsICIKICAgICJDT01QQVJBQklMSVRZIEZST00ge3RndH0uVl9Q'
    || 'T0NfU0NPUkVDQVJEICIKICAgICMgTk9UX01FVCBmaXJzdC4gQSBzY29yZWNhcmQgc29ydGVkIGJ5IGNvZGUgYnVyaWVzIHRoZSBvbmUgcm93IHRoZSByZWFk'
    || 'ZXIKICAgICMgbW9zdCBuZWVkcywgYW5kIFBFTkRJTkcgc29ydGluZyBhYm92ZSBhIGZhaWx1cmUgcmVhZHMgYXMgcmVhc3N1cmFuY2UuCiAgICAiT1JERVIg'
    || 'QlkgQ0FTRSBTVEFURSBXSEVOICdOT1RfTUVUJyBUSEVOIDAgV0hFTiAnUEVORElORycgVEhFTiAxICIKICAgICJXSEVOICdNRVQnIFRIRU4gMiBFTFNFIDMg'
    || 'RU5ELCBDT0RFIgopClBBTkVMU1sicG9jX3ZlcmRpY3QiXSA9ICgKICAgICJTRUxFQ1QgTUVULCBOT1RfTUVULCBQRU5ESU5HLCBOQSwgU0NPUkVELCBIRUFE'
    || 'TElORSwgVkVSRElDVCwgUkVBRF9USElTICIKICAgICJGUk9NIHt0Z3R9LlZfUE9DX1ZFUkRJQ1QiCikKCgpkZWYgdGFyZ2V0X3NjaGVtYShzZXNzaW9uKSAt'
    || 'PiBzdHI6CiAgICAiIiJUaGUgc2NoZW1hIHRoaXMgU3RyZWFtbGl0IG9iamVjdCBsaXZlcyBpbi4KCiAgICBTdHJlYW1saXQgaW4gU25vd2ZsYWtlIHJ1bnMg'
    || 'd2l0aCB0aGUgYXBwJ3Mgb3duIGRhdGFiYXNlIGFuZCBzY2hlbWEgY3VycmVudCwKICAgIHNvIHRoaXMgaXMgcmVsaWFibGUgYW5kIG5lZWRzIG5vIGJ1aWxk'
    || 'LXRpbWUgc3Vic3RpdHV0aW9uLiBRdW90ZWQgaWRlbnRpZmllcnMKICAgIGNvbWUgYmFjayB3aXRoIHF1b3RlcyBhbHJlYWR5LCB3aGljaCBpcyB3aHkgdGhl'
    || 'eSBhcmUgc3RyaXBwZWQuCiAgICAiIiIKICAgIGNhY2hlZCA9IHN0LnNlc3Npb25fc3RhdGUuZ2V0KCJvbmVzaG90X3RhcmdldF9zY2hlbWEiKQogICAgaWYg'
    || 'Y2FjaGVkOgogICAgICAgIHJldHVybiBjYWNoZWQKICAgIHJvdyA9IHNlc3Npb24uc3FsKAogICAgICAgICJTRUxFQ1QgQ1VSUkVOVF9EQVRBQkFTRSgpIEFT'
    || 'IEQsIENVUlJFTlRfU0NIRU1BKCkgQVMgUyIpLmNvbGxlY3QoKVswXQogICAgZGIsIHNjID0gKHJvd1siRCJdIG9yICIiKS5zdHJpcCgnIicpLCAocm93WyJT'
    || 'Il0gb3IgIiIpLnN0cmlwKCciJykKICAgIHRhcmdldCA9IGRiICsgIi4iICsgc2MKICAgIHN0LnNlc3Npb25fc3RhdGVbIm9uZXNob3RfdGFyZ2V0X3NjaGVt'
    || 'YSJdID0gdGFyZ2V0CiAgICByZXR1cm4gdGFyZ2V0CgoKZGVmIGFwcF9uYXZpZ2F0aW9uKHNlc3Npb24sIHRhcmdldCk6CiAgICBjYWNoZV9rZXkgPSAib25l'
    || 'c2hvdF92aWV3ZXI6IiArIHRhcmdldCArICIuIiArIEFQUF9PQkpFQ1QKICAgIGlmIGNhY2hlX2tleSBub3QgaW4gc3Quc2Vzc2lvbl9zdGF0ZToKICAgICAg'
    || 'ICB0cnk6CiAgICAgICAgICAgIGlmIG5vdCByZS5mdWxsbWF0Y2gociJbQS1aYS16MC05X10rXC5bQS1aYS16MC05X10rIiwgdGFyZ2V0KSBvciBub3QgcmUu'
    || 'ZnVsbG1hdGNoKHIiW0EtWmEtejAtOV9dKyIsIEFQUF9PQkpFQ1QpOgogICAgICAgICAgICAgICAgcmV0dXJuIHt9CiAgICAgICAgICAgIGFjY291bnQgPSBz'
    || 'ZXNzaW9uLnNxbCgiU0VMRUNUIENVUlJFTlRfT1JHQU5JWkFUSU9OX05BTUUoKSBBUyBPUkcsIENVUlJFTlRfQUNDT1VOVF9OQU1FKCkgQVMgQUNDT1VOVCIp'
    || 'LmNvbGxlY3QoKVswXQogICAgICAgICAgICBhcHBzID0gc2Vzc2lvbi5zcWwoIlNIT1cgU1RSRUFNTElUUyBJTiBTQ0hFTUEgIiArIHRhcmdldCkuY29sbGVj'
    || 'dCgpCiAgICAgICAgICAgIGFwcCA9IG5leHQoKHJvdy5hc19kaWN0KCkgZm9yIHJvdyBpbiBhcHBzIGlmIHN0cihyb3cuYXNfZGljdCgpLmdldCgibmFtZSIs'
    || 'ICIiKSkudXBwZXIoKSA9PSBBUFBfT0JKRUNULnVwcGVyKCkpLCBOb25lKQogICAgICAgICAgICBwYXJ0cyA9IFtzdHIoYWNjb3VudFsiT1JHIl0pLmxvd2Vy'
    || 'KCksIHN0cihhY2NvdW50WyJBQ0NPVU5UIl0pLmxvd2VyKCksIHN0cigoYXBwIG9yIHt9KS5nZXQoInVybF9pZCIsICIiKSldCiAgICAgICAgICAgIGlmIG5v'
    || 'dCBhbGwocmUuZnVsbG1hdGNoKHIiW0EtWmEtejAtOV8tXSsiLCB2YWx1ZSkgZm9yIHZhbHVlIGluIHBhcnRzKToKICAgICAgICAgICAgICAgIHJldHVybiB7'
    || 'fQogICAgICAgICAgICBzdC5zZXNzaW9uX3N0YXRlW2NhY2hlX2tleV0gPSAiaHR0cHM6Ly9hcHAuc25vd2ZsYWtlLmNvbS9zdHJlYW1saXQvIiArIHBhcnRz'
    || 'WzBdICsgIi8iICsgcGFydHNbMV0gKyAiLyMvYXBwcy8iICsgcGFydHNbMl0KICAgICAgICAgICAgc3Quc2Vzc2lvbl9zdGF0ZVtjYWNoZV9rZXkgKyAiOmJ1'
    || 'aWxkZXIiXSA9ICJodHRwczovL2FwcC5zbm93Zmxha2UuY29tLyIgKyBwYXJ0c1swXSArICIvIiArIHBhcnRzWzFdICsgIi8jL3N0cmVhbWxpdC1hcHBzLyIg'
    || 'KyB0YXJnZXQgKyAiLiIgKyBBUFBfT0JKRUNUCiAgICAgICAgZXhjZXB0IEV4Y2VwdGlvbjoKICAgICAgICAgICAgcmV0dXJuIHt9CiAgICByZXR1cm4geyJ2'
    || 'aWV3ZXJfdXJsIjogc3Quc2Vzc2lvbl9zdGF0ZVtjYWNoZV9rZXldLCAiYnVpbGRlcl91cmwiOiBzdC5zZXNzaW9uX3N0YXRlLmdldChjYWNoZV9rZXkgKyAi'
    || 'OmJ1aWxkZXIiLCAiIil9CgoKZGVmIGludmFsaWRhdGVfcGFuZWxfY2FjaGUoKToKICAgIHN0LnNlc3Npb25fc3RhdGUucG9wKCJvbmVzaG90X3BhbmVsX2Nh'
    || 'Y2hlIiwgTm9uZSkKCgpkZWYgY2FjaGVkX3BhbmVsKHNlc3Npb24sIHNxbCwgYmluZHMsIHR0bD0zMCk6CiAgICBlbnRyaWVzID0gc3Quc2Vzc2lvbl9zdGF0'
    || 'ZS5zZXRkZWZhdWx0KCJvbmVzaG90X3BhbmVsX2NhY2hlIiwge30pCiAgICBrZXkgPSBqc29uLmR1bXBzKFtzcWwsIGJpbmRzXSwgc29ydF9rZXlzPVRydWUs'
    || 'IGRlZmF1bHQ9c3RyKQogICAgbm93ID0gbW9ub3RvbmljKCkKICAgIGVudHJ5ID0gZW50cmllcy5nZXQoa2V5KQogICAgaWYgZW50cnkgYW5kIG5vdyAtIGVu'
    || 'dHJ5WzBdIDwgdHRsOgogICAgICAgIHJldHVybiBjb3B5LmRlZXBjb3B5KGVudHJ5WzFdKQogICAgZnJhbWUgPSBzZXNzaW9uLnNxbChzcWwsIHBhcmFtcz1i'
    || 'aW5kcykgaWYgYmluZHMgZWxzZSBzZXNzaW9uLnNxbChzcWwpCiAgICByb3dzID0gW3Jvdy5hc19kaWN0KCkgZm9yIHJvdyBpbiBmcmFtZS5saW1pdChST1df'
    || 'Q0FQICsgMSkuY29sbGVjdCgpXQogICAgcGFuZWwgPSB7InJvd3MiOiBqc29uLmxvYWRzKGpzb24uZHVtcHMocm93c1s6Uk9XX0NBUF0sIGRlZmF1bHQ9c3Ry'
    || 'KSl9CiAgICBpZiBsZW4ocm93cykgPiBST1dfQ0FQOgogICAgICAgIHBhbmVsWyJ0cnVuY2F0ZWQiXSA9IFJPV19DQVAKICAgIGVudHJpZXNba2V5XSA9IChu'
    || 'b3csIHBhbmVsKQogICAgd2hpbGUgbGVuKGVudHJpZXMpID4gODA6CiAgICAgICAgZW50cmllcy5wb3AobmV4dChpdGVyKGVudHJpZXMpKSkKICAgIHJldHVy'
    || 'biBjb3B5LmRlZXBjb3B5KHBhbmVsKQoKCmRlZiByZXNvbHZlX3BhbmVsX3NxbChzcWw6IHN0ciwgcGFyYW1zOiBkaWN0KToKICAgICIiIihzcWxfd2l0aF9w'
    || 'b3NpdGlvbmFsX2JpbmRzLCBiaW5kcykgZm9yIG9uZSBwYW5lbC4KCiAgICBCSU5EUywgTk9UIElOVEVSUE9MQVRJT04uIEEgY29udHJvbCdzIHZhbHVlIGlz'
    || 'IGNob3NlbiBieSB3aG9ldmVyIGlzIGxvb2tpbmcgYXQKICAgIHRoZSBwYWdlLCBzbyBwYXN0aW5nIGl0IGludG8gdGhlIFNRTCB0ZXh0IHdvdWxkIGJlIGFu'
    || 'IGluamVjdGlvbiBob2xlIGluIGEgcXVlcnkKICAgIHRoYXQgcnVucyB3aXRoIHRoZSBhcHAgb3duZXIncyBwcml2aWxlZ2VzLiBFdmVyeSB2YWx1ZSBsZWF2'
    || 'ZXMgaGVyZSBhcyBhIGA/YC4KCiAgICBPTkxZIERFQ0xBUkVEIE5BTUVTIEFSRSBFTElHSUJMRS4gVGhlIHBhdHRlcm4gaXMgYnVpbHQgZnJvbSB0aGUga2V5'
    || 'cyBvZiBgcGFyYW1zYAogICAgcmF0aGVyIHRoYW4gZnJvbSBhIGdlbmVyaWMgYDpcXHcrYCwgd2hpY2ggaXMgd2hhdCBtYWtlcyBgOjpWQVJDSEFSYCBzYWZl'
    || 'OiB0aGUKICAgIHNlY29uZCBjb2xvbiBvZiBhIGNhc3QgY2Fubm90IGJlZ2luIGEgZGVjbGFyZWQgbmFtZSwgYW5kIHRoZSBuZWdhdGl2ZSBsb29rYmVoaW5k'
    || 'CiAgICByZWZ1c2VzIGl0IGEgc2Vjb25kIHRpbWUuIEFueXRoaW5nIGVsc2UgY29sb24tc2hhcGVkIGluIGEgcGFuZWwgLS0gYSBzdGFnZSBwYXRoLAogICAg'
    || 'YSBKU09OIHRyYXZlcnNhbCAtLSBpcyBsZWZ0IHVudG91Y2hlZCBiZWNhdXNlIGl0IHdhcyBuZXZlciBkZWNsYXJlZC4KCiAgICBMb25nZXN0IG5hbWUgZmly'
    || 'c3Qgc28gdGhhdCBkZWNsYXJpbmcgYm90aCBgbWV0cm9gIGFuZCBgbWV0cm9fY29kZWAgY2Fubm90IGhhdmUKICAgIHRoZSBzaG9ydGVyIG9uZSBlYXQgdGhl'
    || 'IGZyb250IG9mIHRoZSBsb25nZXIuCgogICAgVEhJUyBGVU5DVElPTiBJUyBEVVBMSUNBVEVEIGluIGhhcm5lc3MvYnVuZGxlLnB5LiBJdCBoYXMgdG8gYmU6'
    || 'IHRoaXMgZmlsZSBpcwogICAgc3RhbmRhbG9uZSBjb2RlIHRoYXQgcnVucyBpbnNpZGUgU25vd2ZsYWtlIGFuZCBjYW5ub3QgaW1wb3J0IHRoZSBoYXJuZXNz'
    || 'LCB3aGlsZQogICAgZ2F1bnRsZXQgc3RlcCAxMCBhbmQgdGhlIHJlbmRlciBjaGVjayBuZWVkIHRoZSBpZGVudGljYWwgc3Vic3RpdHV0aW9uIHRvIHRlc3QK'
    || 'ICAgIHdoYXQgdGhlIGFwcCB3aWxsIHJlYWxseSBydW4uIElmIHlvdSBjaGFuZ2Ugb25lLCBjaGFuZ2UgYm90aCAtLSB0aGUgcGFpciBpcwogICAgY292ZXJl'
    || 'ZCBieSBhIHRlc3QgaW4gYnVuZGxlLnB5IHRoYXQgY29tcGFyZXMgdGhlbS4KICAgICIiIgogICAgaWYgbm90IHBhcmFtczoKICAgICAgICByZXR1cm4gc3Fs'
    || 'LCBbXQogICAgbmFtZXMgPSBzb3J0ZWQocGFyYW1zLCBrZXk9bGVuLCByZXZlcnNlPVRydWUpCiAgICBwYXQgPSByZS5jb21waWxlKHIiKD88ITopOigiICsg'
    || 'InwiLmpvaW4ocmUuZXNjYXBlKG4pIGZvciBuIGluIG5hbWVzKSArIHIiKVxiIikKICAgIGJpbmRzID0gW10KCiAgICBkZWYgc3ViKG0pOgogICAgICAgIGJp'
    || 'bmRzLmFwcGVuZChwYXJhbXNbbS5ncm91cCgxKV0pCiAgICAgICAgcmV0dXJuICI/IgoKICAgIHJldHVybiBwYXQuc3ViKHN1Yiwgc3FsKSwgYmluZHMKCgpk'
    || 'ZWYgcnVuX3BhbmVscyhzZXNzaW9uLCB0Z3Q6IHN0ciwgcGFyYW1zOiBkaWN0ID0gTm9uZSkgLT4gZGljdDoKICAgICIiIlJ1biBldmVyeSBwYW5lbCwgb25l'
    || 'IGZhaWx1cmUgY29zdGluZyBvbmUgcGFuZWwuCgogICAgRmV0Y2hlcyBST1dfQ0FQICsgMSByb3dzIHNvIHRoYXQgaGl0dGluZyB0aGUgY2FwIGlzIERFVEVD'
    || 'VEFCTEUuIFNlbGVjdGluZwogICAgZXhhY3RseSBST1dfQ0FQIGlzIGluZGlzdGluZ3Vpc2hhYmxlIGZyb20gInRoZSBhbnN3ZXIgaGFwcGVuZWQgdG8gYmUg'
    || 'NTAwMCIsCiAgICBhbmQgYSBjYXJkIHRoYXQgY291bnRzIHJvd3MgY2xpZW50LXNpZGUgdG8gcHJvZHVjZSBhIGhlYWRsaW5lIC0tICI0MTIgdGFibGVzCiAg'
    || 'ICBhcmUgZWxpZ2libGUiIC0tIHdvdWxkIHRoZW4gcmVwb3J0IHRoZSBjYXAgYXMgaWYgaXQgd2VyZSB0aGUgdG90YWwuIFRoZSBleHRyYQogICAgcm93IGlz'
    || 'IGRyb3BwZWQgYmVmb3JlIHRoZSBwYXlsb2FkIGlzIGJ1aWx0OyBvbmx5IHRoZSBmbGFnIHN1cnZpdmVzLgoKICAgIGBwYXJhbXNgIGNhcnJpZXMgdGhlIGN1'
    || 'cnJlbnQgdmFsdWUgb2YgZXZlcnkgZGVjbGFyZWQgY29udHJvbC4gVGhpcyBydW5zIG9uIEVWRVJZCiAgICBTdHJlYW1saXQgcmVydW4sIHdoaWNoIGlzIHRo'
    || 'ZSB3aG9sZSByZWFzb24gYSBjb250cm9sIGNhbiBjaGFuZ2Ugd2hhdCB0aGUgUmVhY3QKICAgIHBhZ2Ugc2hvd3M6IHRoZSBpZnJhbWUgY2Fubm90IHJlLXF1'
    || 'ZXJ5LCBidXQgdGhlIGhvc3QgcmUtcXVlcmllcyBmb3IgaXQgYW5kIGhhbmRzCiAgICBkb3duIGEgZnJlc2ggcGF5bG9hZC4gQSBzb2x1dGlvbiB0aGF0IGRl'
    || 'Y2xhcmVzIG5vIGNvbnRyb2xzIHBhc3NlcyBhbiBlbXB0eSBkaWN0CiAgICBhbmQgdGFrZXMgdGhlIG5vLWJpbmRzIHBhdGggYmVsb3csIHNvIGl0cyBxdWVy'
    || 'eSBpcyB1bmNoYW5nZWQuCiAgICAiIiIKICAgIHBhcmFtcyA9IHBhcmFtcyBvciB7fQogICAgb3V0ID0ge30KICAgIGZvciBuYW1lLCBzcWwgaW4gUEFORUxT'
    || 'Lml0ZW1zKCk6CiAgICAgICAgdHJ5OgogICAgICAgICAgICBxLCBiaW5kcyA9IHJlc29sdmVfcGFuZWxfc3FsKHNxbC5yZXBsYWNlKCJ7dGd0fSIsIHRndCks'
    || 'IHBhcmFtcykKICAgICAgICAgICAgIyBUaGUgbm8tYmluZHMgY2FsbCBpcyBrZXB0IGRpc3RpbmN0IHJhdGhlciB0aGFuIGFsd2F5cyBwYXNzaW5nCiAgICAg'
    || 'ICAgICAgICMgcGFyYW1zPVtdOiBldmVyeSBleGlzdGluZyBwYW5lbCBnb2VzIGRvd24gdGhpcyBwYXRoIHVudG91Y2hlZCwgc28gdGhpcwogICAgICAgICAg'
    || 'ICAjIG1lY2hhbmlzbSBjYW5ub3QgcmVncmVzcyBhIHNvbHV0aW9uIHRoYXQgbmV2ZXIgb3B0ZWQgaW50byBpdC4KICAgICAgICAgICAgb3V0W25hbWVdID0g'
    || 'Y2FjaGVkX3BhbmVsKHNlc3Npb24sIHEsIGJpbmRzKQogICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZXhjOgogICAgICAgICAgICBvdXRbbmFtZV0gPSB7'
    || 'ImVycm9yIjogdHlwZShleGMpLl9fbmFtZV9fICsgIjogIiArIHN0cihleGMpWzo0MDBdfQogICAgcmV0dXJuIG91dAoKCmRlZiBidWlsZF9odG1sKHBheWxv'
    || 'YWQ6IGRpY3QpIC0+IHN0cjoKICAgIGpzID0gYmFzZTY0LmI2NGRlY29kZShBUFBfSlNfQjY0KS5kZWNvZGUoInV0Zi04IikKICAgIGNzcyA9IGJhc2U2NC5i'
    || 'NjRkZWNvZGUoQVBQX0NTU19CNjQpLmRlY29kZSgidXRmLTgiKQogICAgZGF0YSA9IGpzb24uZHVtcHMocGF5bG9hZCkKICAgICMgVGhlIG9ubHkgZXNjYXBl'
    || 'IHRoYXQgbWF0dGVycyB3aGVuIGlubGluaW5nIGludG8gPHNjcmlwdD46IHRoZSBzZXF1ZW5jZQogICAgIyA8L3NjcmlwdCB3b3VsZCBlbmQgdGhlIHRhZyBl'
    || 'YXJseS4gSXQgY2FuIGFwcGVhciBpbiBKUyBvbmx5IGluc2lkZSBhIHN0cmluZwogICAgIyBvciBhIGNvbW1lbnQsIHNvIG5ldXRyYWxpc2luZyBpdCBjYW5u'
    || 'b3QgY2hhbmdlIGJlaGF2aW91ci4KICAgIGpzID0ganMucmVwbGFjZSgiPC9zY3JpcHQiLCAiPFxcL3NjcmlwdCIpCiAgICBkYXRhID0gZGF0YS5yZXBsYWNl'
    || 'KCI8LyIsICI8XFwvIikKICAgIHJldHVybiAoCiAgICAgICAgIjwhZG9jdHlwZSBodG1sPjxodG1sPjxoZWFkPjxtZXRhIGNoYXJzZXQ9J3V0Zi04Jz48c3R5'
    || 'bGU+IiArIGNzcwogICAgICAgICsgIjwvc3R5bGU+PC9oZWFkPjxib2R5IGRhdGEtb25lc2hvdC1kYXNoYm9hcmQ+PGRpdiBpZD0ncm9vdCc+PC9kaXY+Igog'
    || 'ICAgICAgICsgIjxzY3JpcHQ+d2luZG93WyIgKyBqc29uLmR1bXBzKEdMT0JBTF9OQU1FKSArICJdID0gIiArIGRhdGEgKyAiOzwvc2NyaXB0PiIKICAgICAg'
    || 'ICArICI8c2NyaXB0PiIgKyBqcyArICI8L3NjcmlwdD48L2JvZHk+PC9odG1sPiIKICAgICkKCgpUSUVSX09SREVSID0gWyJTQU1QTEUiLCAiTElNSVRFRCIs'
    || 'ICJQUk9EVUNUSU9OIl0KVElFUl9CTFVSQiA9IHsKICAgICJTQU1QTEUiOiAgICAgIlNlZWRlZCBkYXRhLiBTYWZlIHRvIHJ1biByZXBlYXRlZGx5OyBwcm92'
    || 'ZXMgdGhlIHNoYXBlIHdpdGhvdXQgIgogICAgICAgICAgICAgICAgICAidG91Y2hpbmcgYW55dGhpbmcgcmVhbC4iLAogICAgIkxJTUlURUQiOiAgICAiWW91'
    || 'ciBkYXRhLCBkZWxpYmVyYXRlbHkgYm91bmRlZCDigJQgYSBzdWJzZXQsIGEgY2FwLCBvciBhIHNpbmdsZSAiCiAgICAgICAgICAgICAgICAgICJvYmplY3Qu'
    || 'IE1lYW50IHRvIGJlIHJldmVyc2libGUuIiwKICAgICJQUk9EVUNUSU9OIjogIllvdXIgZGF0YSwgYXQgZnVsbCBzY29wZS4gUmVhZCB0aGUgdW5kbyBsaW5l'
    || 'IGJlZm9yZSB5b3UgcnVuIGl0LiIsCn0KCgpkZWYgZm10X2NyZWRpdHModikgLT4gc3RyOgogICAgIiIiMC4wMiwgbm90IDAuMDIwMDAwLgoKICAgIEVTVF9D'
    || 'UkVESVRTIGlzIE5VTUJFUigzOCw2KSBzbyB0aGF0IGZyYWN0aW9uYWwgY3JlZGl0cyBzdXJ2aXZlIHRoZSByb3VuZCB0cmlwLAogICAgYW5kIHN0cigpIG9u'
    || 'IGEgRGVjaW1hbCBrZWVwcyBldmVyeSB0cmFpbGluZyB6ZXJvLiBTaXggZGVjaW1hbCBwbGFjZXMgaW4gYQogICAgYnV0dG9uIGNhcHRpb24gcmVhZHMgYXMg'
    || 'YSBtYWNoaW5lIHRhbGtpbmcgdG8gaXRzZWxmLgogICAgIiIiCiAgICBpZiB2IGlzIE5vbmU6CiAgICAgICAgcmV0dXJuICJcdTIwMTQiCiAgICB0cnk6CiAg'
    || 'ICAgICAgcyA9IGYie2Zsb2F0KHYpOi4zZn0iLnJzdHJpcCgiMCIpLnJzdHJpcCgiLiIpCiAgICAgICAgcmV0dXJuIHMgb3IgIjAiCiAgICBleGNlcHQgKFR5'
    || 'cGVFcnJvciwgVmFsdWVFcnJvcik6CiAgICAgICAgcmV0dXJuIHN0cih2KQoKCmRlZiBsb2FkX3J1bGVfY29uZmlnKHNlc3Npb24sIHRndDogc3RyKToKICAg'
    || 'ICIiIigodGllciwgYWxsb3dfcmVhbCwgYWxsb3dfc2FtcGxlKSwgcm93cykgZm9yIGEgc29sdXRpb24gd2l0aCBhIHR1bmFibGUgcnVsZQogICAgc2V0LCBl'
    || 'bHNlICgoIiIsIEZhbHNlLCBGYWxzZSksIFtdKS4KCiAgICBXSFkgVEhJUyBSRUFEUyBUSUVSIEFORCBOT1QgTU9ERS4gSXQgdXNlZCB0byByZXR1cm4gTU9E'
    || 'RSwgYW5kIGNvbmZpZ19iYXIgZ2F0ZWQKICAgIG9uIGBtb2RlIGluICgiUE9DIiwgIlBST0RVQ1RJT04iKWAuIE1PREUgY2FuIG9ubHkgZXZlciBob2xkIERJ'
    || 'U0NPVkVSIG9yIFNBTVBMRQogICAgLS0gdGhvc2UgYXJlIHRoZSBvbmx5IHR3byB2YWx1ZXMgdGhlIHNldHRpbmdzIHRlbXBsYXRlIGRlZmluZXMsIGFuZAog'
    || 'ICAgMDBfc2V0dGluZ3NfYW5kX2Jsb2NrMCBkb2N1bWVudHMgdGhlbSBhcyBhIERBVEEgU09VUkNFIHN3aXRjaDogRElTQ09WRVIgcmVhZHMKICAgIHlvdXIg'
    || 'YWNjb3VudCwgU0FNUExFIHNlZWRzIGZpeHR1cmVzIGluc3RlYWQuICJQT0MiIHdhcyBuZXZlciBhIHJlYWNoYWJsZSB2YWx1ZSwKICAgIHNvIHRoZSBjb250'
    || 'cm9scyB3ZXJlIGRlYWQgaW4gZXZlcnkgc29sdXRpb24sIGluIGV2ZXJ5IG1vZGUsIGFuZAogICAgU0VUX1JVTEVfQ09ORklHIC8gUkVCVUlMRF9SRVNPTFVU'
    || 'SU9OIC8gUkVTRVRfUlVMRV9ERUZBVUxUUyBjb3VsZCBub3QgYmUgcmVhY2hlZAogICAgZnJvbSB0aGUgYXBwIGF0IGFsbC4KCiAgICBUaGUgZ2F0ZSB3YXMg'
    || 'd3JpdHRlbiBhZ2FpbnN0IGEgRElTQ09WRVIgLT4gUE9DIC0+IFBST0RVQ1RJT04gbWF0dXJpdHkgbGFkZGVyCiAgICB0aGF0IHdhcyBuZXZlciBpbXBsZW1l'
    || 'bnRlZC4gVGhlIGxhZGRlciB0aGF0IGRvZXMgZXhpc3QgaXMgVElFUgogICAgKFNBTVBMRSAvIExJTUlURUQgLyBQUk9EVUNUSU9OKSwgd2hpY2ggaXMgd2hh'
    || 'dCBnb3Zlcm5zIGhvdyBtdWNoIHJlYWwgZGF0YSB0aGUKICAgIGJ1aWxkIGlzIGFsbG93ZWQgdG8gdG91Y2guIFNvIHRoZSBnYXRlIG5vdyByZWFkcyBUSUVS'
    || 'LCBhbmQgcmV1c2VzIHRoZSBTQU1FIHR3bwogICAgYXV0aG9yaXNhdGlvbnMgcHJvbW90aW9uX2JhciByZWFkcyAtLSBBTExPV19BQ1RJT05TIGZvciBMSU1J'
    || 'VEVEIGFuZCBQUk9EVUNUSU9OLAogICAgQUxMT1dfU0FNUExFX0FDVElPTlMgZm9yIFNBTVBMRS4gVGhhdCBpcyBkZWxpYmVyYXRlOiBhIHRocmVzaG9sZCBj'
    || 'aGFuZ2UgY29zdHMgYQogICAgUkVCVUlMRF9SRVNPTFVUSU9OIGNhbGwsIHdoaWNoIGlzIGFuIGFjdGlvbiwgc28gaWYgdGhlIHR3byBzdXJmYWNlcyBkaXNh'
    || 'Z3JlZWQKICAgIGFib3V0IHdoYXQgaXMgbGl2ZSBvbmUgb2YgdGhlbSB3b3VsZCBiZSBseWluZy4KCiAgICBOTyBQRVItU09MVVRJT04gRkxBRywgQU5EIFRI'
    || 'QVQgSVMgVEhFIFdIT0xFIFNBRkVUWSBBUkdVTUVOVC4gVGhpcyBnYXRlcyBvbgogICAgd2hldGhlciBWX1JVTEVfQ09ORklHIGV4aXN0cywgZXhhY3RseSBh'
    || 'cyBsb2FkX2FjdGlvbnMoKSBnYXRlcyBvbiBWX0FDVElPTlMuCiAgICBUd2VudHktZml2ZSBvZiB0aGUgdHdlbnR5LXNldmVuIHNvbHV0aW9ucyBkbyBub3Qg'
    || 'ZGVmaW5lIHRoYXQgdmlldywgc28gZm9yIHRoZW0KICAgIHRoaXMgcmV0dXJucyAoKCIiLCBGYWxzZSwgRmFsc2UpLCBbXSkgb24gdGhlIGZpcnN0IGV4Y2Vw'
    || 'dGlvbiBhbmQgY29uZmlnX2JhcigpCiAgICBkcmF3cyBub3RoaW5nIC0tIG5vIG5ldyBzZXR0aW5nIHRvIHNldCB3cm9uZywgbm8gc2Vjb25kIGNvZGUgcGF0'
    || 'aCB0aHJvdWdoIHRoZQogICAgc2hlbGwsIGFuZCBubyB3YXkgZm9yIGEgc29sdXRpb24gdGhhdCBuZXZlciBvcHRlZCBpbiB0byBncm93IGEgY29udHJvbCBz'
    || 'dXJmYWNlCiAgICBieSBhY2NpZGVudC4KCiAgICBUaGUgZ2F0ZSBjb21lcyBiYWNrIHdpdGggdGhlIHJvd3MgYmVjYXVzZSB0aGUgY2FsbGVyIG5lZWRzIGJv'
    || 'dGggdG8gZGVjaWRlCiAgICBhbnl0aGluZywgYW5kIHJlYWRpbmcgaXQgdHdpY2UgaW52aXRlcyB0aGUgdHdvIHJlYWRzIHRvIGRpc2FncmVlIGFjcm9zcyBh'
    || 'IHJlcnVuLgogICAgIiIiCiAgICB0cnk6CiAgICAgICAgcm93cyA9IFtyLmFzX2RpY3QoKSBmb3IgciBpbiBzZXNzaW9uLnNxbCgKICAgICAgICAgICAgIlNF'
    || 'TEVDVCBSVUxFX0lELCBHUk9VUF9MQUJFTCwgUExBSU5fTEFCRUwsIFBMQUlOX0RFU0MsIElTX0FDVElWRSwgIgogICAgICAgICAgICAiSVNfTU9ESUZJRUQs'
    || 'IFRIUkVTSE9MRCwgVEhSRVNIT0xEX0VESVRBQkxFLCBMSU5LUywgU09MRV9MSU5LUyAiCiAgICAgICAgICAgICJGUk9NICIgKyB0Z3QgKyAiLlZfUlVMRV9D'
    || 'T05GSUcgT1JERVIgQlkgR1JPVVBfU0VRLCBSVUxFX1NFUSIpLmNvbGxlY3QoKV0KICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgcmV0dXJuICgiIiwg'
    || 'RmFsc2UsIEZhbHNlKSwgW10KICAgICMgUmVhZCBkZWZlbnNpdmVseSBhbmQgZmFpbCBDTE9TRUQgb24gZWFjaCBvbmUgaW5kZXBlbmRlbnRseS4gQSBydWxl'
    || 'IHNldCB3aG9zZQogICAgIyB0aWVyIG9yIGF1dGhvcmlzYXRpb24gY2Fubm90IGJlIGVzdGFibGlzaGVkIGlzIHRyZWF0ZWQgYXMgcmVhZC1vbmx5LCBiZWNh'
    || 'dXNlCiAgICAjIHRoZSBmYWlsdXJlIGRpcmVjdGlvbiBtYXR0ZXJzOiBndWVzc2luZyAibGl2ZSIgaGVyZSB3b3VsZCBhcm0gY29udHJvbHMgdGhhdAogICAg'
    || 'IyBjYWxsIGEgcmVidWlsZCBvbiBhIGJ1aWxkIHdlIGtub3cgbm90aGluZyBhYm91dC4KICAgIHRyeToKICAgICAgICB0aWVyID0gc3RyKHNlc3Npb24uc3Fs'
    || 'KAogICAgICAgICAgICAiU0VMRUNUIFRJRVIgRlJPTSAiICsgdGd0ICsgIi5WX0JVSUxEX0NPTlRFWFQiKS5jb2xsZWN0KClbMF1bMF0KICAgICAgICAgICAg'
    || 'b3IgIiIpLnVwcGVyKCkKICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgdGllciA9ICIiCiAgICB0cnk6CiAgICAgICAgYWxsb3dfcmVhbCA9IGJvb2wo'
    || 'c2Vzc2lvbi5zcWwoCiAgICAgICAgICAgICJTRUxFQ1QgQUNUSU9OU19FTkFCTEVEIEZST00gIiArIHRndCArICIuVl9CVUlMRF9DT05URVhUIikuY29sbGVj'
    || 'dCgpWzBdWzBdKQogICAgZXhjZXB0IEV4Y2VwdGlvbjoKICAgICAgICBhbGxvd19yZWFsID0gRmFsc2UKICAgIHRyeToKICAgICAgICBhbGxvd19zYW1wbGUg'
    || 'PSBib29sKHNlc3Npb24uc3FsKAogICAgICAgICAgICAiU0VMRUNUIENPQUxFU0NFKFNBTVBMRV9BQ1RJT05TX0VOQUJMRUQsIEZBTFNFKSBGUk9NICIgKyB0'
    || 'Z3QKICAgICAgICAgICAgKyAiLlZfQlVJTERfQ09OVEVYVCIpLmNvbGxlY3QoKVswXVswXSkKICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgYWxsb3df'
    || 'c2FtcGxlID0gRmFsc2UKICAgIHJldHVybiAodGllciwgYWxsb3dfcmVhbCwgYWxsb3dfc2FtcGxlKSwgcm93cwoKCmRlZiBjb25maWdfYmFyKHNlc3Npb24s'
    || 'IHRndDogc3RyKSAtPiBOb25lOgogICAgIiIiVGhlIHR1bmFibGUgcnVsZSBzZXQ6IHJlYWQtb25seSB1bnRpbCB0aGUgYnVpbGQgaXMgYXV0aG9yaXNlZCB0'
    || 'byBhY3QuCgogICAgU3RyZWFtbGl0IHJhdGhlciB0aGFuIFJlYWN0IGZvciB0aGUgc2FtZSBwaHlzaWNhbCByZWFzb24gcHJvbW90aW9uX2JhciBpcyAtLQog'
    || 'ICAgY29tcG9uZW50cy5odG1sIGlzIGEgc2FuZGJveGVkIGNyb3NzLW9yaWdpbiBpZnJhbWUgd2l0aCBubyBTbm93Zmxha2Ugc2Vzc2lvbiwKICAgIHNvIGEg'
    || 'UmVhY3Qgc2xpZGVyIGNhbm5vdCBjYWxsIGEgcHJvY2VkdXJlLiBUaGUgUmVhY3QgcGFnZSBzaG93cyB0aGUgcnVsZXMgYW5kCiAgICB3aGF0IGVhY2ggb25l'
    || 'IGNvbnRyaWJ1dGVzOyB0aGlzIGlzIHdoZXJlIHRoZXkgY2hhbmdlLgoKICAgIFdIWSBSRUFELU9OTFkgUkFUSEVSIFRIQU4gSElEREVOLiBXaGVuIHRoZSBi'
    || 'dWlsZCBpcyBub3QgYXV0aG9yaXNlZCB0byBydW4KICAgIGFjdGlvbnMsIHRoZSBydWxlIHNldCBpcyBzdGlsbCB0aGUgcGFydCB3b3J0aCBzZWVpbmcgLS0g'
    || 'dHVuYWJsZSBtYXRjaGluZyBpcyB0aGUKICAgIHByb2R1Y3QuIEhpZGluZyB0aGUgcGFuZWwgd291bGQgbWlzcmVwcmVzZW50IGl0LiBBcm1pbmcgaXQgd291'
    || 'bGQgYmUgd29yc2U6IGF0CiAgICBTQU1QTEUgdGllciBhIHJlYWRlciB3b3VsZCB0dW5lIHRocmVzaG9sZHMgYWdhaW5zdCBzZWVkZWQgcm93cyBhbmQgcmVh'
    || 'ZCB0aGUKICAgIHJlc3VsdCBhcyB0aGVpciBvd24gZGF0YS4gU28gdGhlIHZhbHVlcyBhbHdheXMgcmVuZGVyLCBsYWJlbGxlZCBhcyBhIHByZXNldCB3aGVu'
    || 'CiAgICB0aGV5IGNhbm5vdCBiZSBjaGFuZ2VkLCBhbmQgdGhlIGNvbnRyb2xzIGFycml2ZSB3aXRoIHRoZSBhdXRob3Jpc2F0aW9uIHRoYXQgbWFrZXMKICAg'
    || 'IHRoZW0gbWVhbiBzb21ldGhpbmcuCiAgICAiIiIKICAgICh0aWVyLCBhbGxvd19yZWFsLCBhbGxvd19zYW1wbGUpLCByb3dzID0gbG9hZF9ydWxlX2NvbmZp'
    || 'ZyhzZXNzaW9uLCB0Z3QpCiAgICBpZiBub3Qgcm93czoKICAgICAgICByZXR1cm4KCiAgICAjIFRoZSBTQU1FIHNwbGl0IHByb21vdGlvbl9iYXIgYXBwbGll'
    || 'cywgZm9yIHRoZSBzYW1lIHJlYXNvbjogU0FNUExFIHJ1bnMgYWdhaW5zdAogICAgIyBzZWVkZWQgcm93cyB0aGlzIHNjcmlwdCBjcmVhdGVkLCBldmVyeXRo'
    || 'aW5nIGVsc2UgdG91Y2hlcyB0aGUgY3VzdG9tZXIncyBvd24KICAgICMgb2JqZWN0cy4gQXBwbHlpbmcgYSB0aHJlc2hvbGQgY2FsbHMgUkVCVUlMRF9SRVNP'
    || 'TFVUSU9OLCBzbyBpdCBhbnN3ZXJzIHRvIHRoZQogICAgIyBhY3Rpb24gYXV0aG9yaXNhdGlvbnMgcmF0aGVyIHRoYW4gdG8gYSBzZWNvbmQsIHBhcmFsbGVs'
    || 'IG5vdGlvbiBvZiAibGl2ZSIuCiAgICBsaXZlID0gYWxsb3dfc2FtcGxlIGlmIHRpZXIgPT0gIlNBTVBMRSIgZWxzZSBhbGxvd19yZWFsCiAgICBzdC5jYXB0'
    || 'aW9uKCJNQVRDSElORyBSVUxFUyIgKyAoIiIgaWYgbGl2ZSBlbHNlICIgXHUwMGI3IFBSRVNFVCwgTk9UIFlFVCBUVU5BQkxFIikpCiAgICBpZiBub3QgbGl2'
    || 'ZToKICAgICAgICB3aHkgPSAoCiAgICAgICAgICAgICJBY3Rpb25zIGFyZSBzd2l0Y2hlZCBvZmYgZm9yIHRoaXMgYnVpbGQsIHNvIHRoZXNlIGFyZSB0aGUg'
    || 'cHJlc2V0IHJ1bGVzICIKICAgICAgICAgICAgImFzIHNoaXBwZWQuIFRoZXkgYXJlIHNob3duIGJlY2F1c2UgdGhlIHJ1bGUgc2V0IGlzIHRoZSBwYXJ0IHdv'
    || 'cnRoICIKICAgICAgICAgICAgInNlZWluZywgYW5kIHRoZXkgYXJlIG5vdCBlZGl0YWJsZSBiZWNhdXNlIGFwcGx5aW5nIGEgY2hhbmdlIGNhbGxzIGEgIgog'
    || 'ICAgICAgICAgICAicmVidWlsZC4iKQogICAgICAgIGlmIHRpZXIgPT0gIlNBTVBMRSI6CiAgICAgICAgICAgIHdoeSA9ICgKICAgICAgICAgICAgICAgICJU'
    || 'aGlzIGJ1aWxkIHJhbiBhdCBTQU1QTEUgdGllciwgc28gdGhlc2UgYXJlIHRoZSBwcmVzZXQgcnVsZXMgIgogICAgICAgICAgICAgICAgInJ1bm5pbmcgb3Zl'
    || 'ciB0aGUgYnVuZGxlZCBzYW1wbGUgcm93cy4gVGhleSBhcmUgc2hvd24gYmVjYXVzZSB0aGUgIgogICAgICAgICAgICAgICAgInJ1bGUgc2V0IGlzIHRoZSBw'
    || 'YXJ0IHdvcnRoIHNlZWluZywgYW5kIHRoZXkgYXJlIG5vdCBlZGl0YWJsZSAiCiAgICAgICAgICAgICAgICAiYmVjYXVzZSB0dW5pbmcgYSB0aHJlc2hvbGQg'
    || 'YWdhaW5zdCBzZWVkZWQgZGF0YSB3b3VsZCBwcm9kdWNlIGEgIgogICAgICAgICAgICAgICAgIm51bWJlciB0aGF0IGRlc2NyaWJlcyB0aGUgZml4dHVyZSBy'
    || 'YXRoZXIgdGhhbiB5b3VyIGFjY291bnQuIikKICAgICAgICBlbGlmIG5vdCB0aWVyOgogICAgICAgICAgICB3aHkgPSAoCiAgICAgICAgICAgICAgICAiVGhp'
    || 'cyBidWlsZCdzIHRpZXIgY291bGQgbm90IGJlIHJlYWQsIHNvIHRoZSBjb250cm9scyBzdGF5ICIKICAgICAgICAgICAgICAgICJyZWFkLW9ubHkgcmF0aGVy'
    || 'IHRoYW4gYXJtaW5nIGEgcmVidWlsZCBhZ2FpbnN0IGEgYnVpbGQgd2UgY2Fubm90ICIKICAgICAgICAgICAgICAgICJpZGVudGlmeS4gVGhlIHZhbHVlcyBi'
    || 'ZWxvdyBhcmUgdGhlIHJ1bGVzIGFzIHNoaXBwZWQuIikKICAgICAgICBzdC5jYXB0aW9uKHdoeSArICIgRW5hYmxlIGFjdGlvbnMgYW5kIHJlLXJ1biBhdCBM'
    || 'SU1JVEVEIG9yIFBST0RVQ1RJT04gdGllciAiCiAgICAgICAgICAgICAgICAgICAgICAgICAiYW5kIHRoZSBjb250cm9scyBiZWxvdyBiZWNvbWUgbGl2ZS4i'
    || 'KQoKICAgIGRpcnR5ID0gYW55KGJvb2woci5nZXQoIklTX01PRElGSUVEIikpIGZvciByIGluIHJvd3MpCiAgICBhdF9yaXNrID0gc3VtKGludChyLmdldCgi'
    || 'U09MRV9MSU5LUyIpIG9yIDApCiAgICAgICAgICAgICAgICAgIGZvciByIGluIHJvd3MgaWYgbm90IGJvb2woci5nZXQoIklTX0FDVElWRSIpKSkKICAgIGlm'
    || 'IGRpcnR5OgogICAgICAgIHN0LmNhcHRpb24oIkNIQU5HRUQgRlJPTSBERUZBVUxUUyBcdTAwYjcgcmVidWlsZCB0byBhcHBseSIpCiAgICBpZiBhdF9yaXNr'
    || 'OgogICAgICAgIHN0LmNhcHRpb24oIkVzdGltYXRlZCBpbXBhY3Q6IGFib3V0ICIgKyBmInthdF9yaXNrOix9IgogICAgICAgICAgICAgICAgICAgKyAiIGNv'
    || 'bm5lY3Rpb25zIHdvdWxkIGJlIHJlbW92ZWQsIGJlY2F1c2UgdGhleSBhcmUgaGVsZCBieSBhICIKICAgICAgICAgICAgICAgICAgICAgInJ1bGUgdGhhdCBp'
    || 'cyBjdXJyZW50bHkgc3dpdGNoZWQgb2ZmLiIpCgogICAgZ3JvdXAgPSBOb25lCiAgICBmb3IgciBpbiByb3dzOgogICAgICAgIGcgPSBzdHIoci5nZXQoIkdS'
    || 'T1VQX0xBQkVMIikgb3IgIiIpCiAgICAgICAgaWYgZyAhPSBncm91cDoKICAgICAgICAgICAgZ3JvdXAgPSBnCiAgICAgICAgICAgIHN0LmNhcHRpb24oZy51'
    || 'cHBlcigpKQogICAgICAgIHJpZCA9IHN0cihyLmdldCgiUlVMRV9JRCIpIG9yICIiKQogICAgICAgIGxhYmVsID0gc3RyKHIuZ2V0KCJQTEFJTl9MQUJFTCIp'
    || 'IG9yIHJpZCkKICAgICAgICBhY3RpdmUgPSBib29sKHIuZ2V0KCJJU19BQ1RJVkUiKSkKICAgICAgICB0aHIgPSByLmdldCgiVEhSRVNIT0xEIikKICAgICAg'
    || 'ICBlZGl0YWJsZSA9IGJvb2woci5nZXQoIlRIUkVTSE9MRF9FRElUQUJMRSIpKSBhbmQgdGhyIGlzIG5vdCBOb25lCiAgICAgICAgbGlua3MgPSBpbnQoci5n'
    || 'ZXQoIkxJTktTIikgb3IgMCkKICAgICAgICBzb2xlID0gaW50KHIuZ2V0KCJTT0xFX0xJTktTIikgb3IgMCkKCiAgICAgICAgYzEsIGMyLCBjMyA9IHN0LmNv'
    || 'bHVtbnMoWzMsIDIsIDJdKQogICAgICAgIHdpdGggYzE6CiAgICAgICAgICAgIGlmIGxpdmU6CiAgICAgICAgICAgICAgICBuZXdfYWN0aXZlID0gc3QudG9n'
    || 'Z2xlKGxhYmVsLCB2YWx1ZT1hY3RpdmUsIGtleT0icmFfIiArIHJpZCkKICAgICAgICAgICAgZWxzZToKICAgICAgICAgICAgICAgIHN0LmNhcHRpb24oKCJP'
    || 'TiAgIiBpZiBhY3RpdmUgZWxzZSAiT0ZGICIpICsgbGFiZWwpCiAgICAgICAgICAgICAgICBuZXdfYWN0aXZlID0gYWN0aXZlCiAgICAgICAgICAgIGlmIHIu'
    || 'Z2V0KCJQTEFJTl9ERVNDIik6CiAgICAgICAgICAgICAgICBzdC5jYXB0aW9uKHN0cihyWyJQTEFJTl9ERVNDIl0pKQogICAgICAgIHdpdGggYzI6CiAgICAg'
    || 'ICAgICAgIG5ld190aHIgPSB0aHIKICAgICAgICAgICAgaWYgZWRpdGFibGU6CiAgICAgICAgICAgICAgICBpZiBsaXZlOgogICAgICAgICAgICAgICAgICAg'
    || 'IG5ld190aHIgPSBzdC5zbGlkZXIoCiAgICAgICAgICAgICAgICAgICAgICAgICJIb3cgc2ltaWxhciBpcyBjbG9zZSBlbm91Z2giLCBtaW5fdmFsdWU9NTAs'
    || 'IG1heF92YWx1ZT0xMDAsCiAgICAgICAgICAgICAgICAgICAgICAgIHZhbHVlPWludChyb3VuZChmbG9hdCh0aHIpICogMTAwKSksIHN0ZXA9MSwga2V5PSJy'
    || 'dF8iICsgcmlkLAogICAgICAgICAgICAgICAgICAgICAgICBoZWxwPSJoaWdoZXIgaXMgc3RyaWN0ZXIgXHUyMDE0IGZld2VyLCBzYWZlciBtYXRjaGVzIikK'
    || 'ICAgICAgICAgICAgICAgICAgICBuZXdfdGhyID0gbmV3X3RociAvIDEwMC4wCiAgICAgICAgICAgICAgICBlbHNlOgogICAgICAgICAgICAgICAgICAgIHN0'
    || 'LmNhcHRpb24oInNpbWlsYXJpdHkgIiArIHN0cihpbnQocm91bmQoZmxvYXQodGhyKSAqIDEwMCkpKSArICIlIikKICAgICAgICB3aXRoIGMzOgogICAgICAg'
    || 'ICAgICBzdC5jYXB0aW9uKGYie2xpbmtzOix9IiArICIgY29ubmVjdGlvbnMgbWFkZSIpCiAgICAgICAgICAgIGlmIHNvbGU6CiAgICAgICAgICAgICAgICBz'
    || 'dC5jYXB0aW9uKGYie3NvbGU6LH0iICsgIiB3b3VsZCBiZSBsb3N0IHdpdGhvdXQgaXQiKQoKICAgICAgICAjIE9uZSBDQUxMIHBlciBjaGFuZ2VkIHJ1bGUs'
    || 'IGFuZCBvbmx5IG9uIGEgcmVhbCBjaGFuZ2UuIFdyaXRpbmcgb24gZXZlcnkKICAgICAgICAjIHJlcnVuIHdvdWxkIGlzc3VlIGEgcHJvY2VkdXJlIGNhbGwg'
    || 'cGVyIHJ1bGUgcGVyIHJlcGFpbnQsIHdoaWNoIGlzIGJvdGggYQogICAgICAgICMgY29zdCBhbmQgYSBmYWxzZSBhdWRpdCB0cmFpbCAtLSB0aGUgY29uZmln'
    || 'IGhpc3Rvcnkgd291bGQgcmVjb3JkIGVkaXRzCiAgICAgICAgIyBub2JvZHkgbWFkZS4KICAgICAgICBpZiBsaXZlIGFuZCAobmV3X2FjdGl2ZSAhPSBhY3Rp'
    || 'dmUgb3IKICAgICAgICAgICAgICAgICAgICAgKGVkaXRhYmxlIGFuZCBuZXdfdGhyIGlzIG5vdCBOb25lIGFuZCB0aHIgaXMgbm90IE5vbmUKICAgICAgICAg'
    || 'ICAgICAgICAgICAgIGFuZCBhYnMoZmxvYXQobmV3X3RocikgLSBmbG9hdCh0aHIpKSA+IDFlLTkpKToKICAgICAgICAgICAgdHJ5OgogICAgICAgICAgICAg'
    || 'ICAgc2Vzc2lvbi5zcWwoIkNBTEwgIiArIHRndCArICIuU0VUX1JVTEVfQ09ORklHKD8sID8sID8pIiwKICAgICAgICAgICAgICAgICAgICAgICAgICAgIHBh'
    || 'cmFtcz1bcmlkLCBib29sKG5ld19hY3RpdmUpLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBmbG9hdChuZXdfdGhyKSBpZiBuZXdfdGhy'
    || 'IGlzIG5vdCBOb25lIGVsc2UgTm9uZV0pLmNvbGxlY3QoKQogICAgICAgICAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGV4YzoKICAgICAgICAgICAgICAgIHN0'
    || 'LmVycm9yKCJDb3VsZCBub3Qgc2F2ZSAiICsgcmlkICsgIjogIiArIHN0cihleGMpLAogICAgICAgICAgICAgICAgICAgICAgICAgaWNvbj0iOm1hdGVyaWFs'
    || 'L2Vycm9yOiIpCiAgICAgICAgICAgIGVsc2U6CiAgICAgICAgICAgICAgICBpbnZhbGlkYXRlX3BhbmVsX2NhY2hlKCkKICAgICAgICAgICAgICAgIHN0LnJl'
    || 'cnVuKCkKCiAgICBpZiBub3QgbGl2ZToKICAgICAgICBzdC5kaXZpZGVyKCkKICAgICAgICByZXR1cm4KCiAgICBiMSwgYjIgPSBzdC5jb2x1bW5zKFsxLCAx'
    || 'XSkKICAgIHdpdGggYjE6CiAgICAgICAgaWYgc3QuYnV0dG9uKCJSZXN0b3JlIGRlZmF1bHRzIiwga2V5PSJjZmdfcmVzZXQiKToKICAgICAgICAgICAgdHJ5'
    || 'OgogICAgICAgICAgICAgICAgb3V0ID0gc2Vzc2lvbi5zcWwoIkNBTEwgIiArIHRndCArICIuUkVTRVRfUlVMRV9ERUZBVUxUUygpIikuY29sbGVjdCgpWzBd'
    || 'WzBdCiAgICAgICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZXhjOgogICAgICAgICAgICAgICAgb3V0ID0gIkZBSUxFRCB0byByZXN0b3JlIGRlZmF1bHRz'
    || 'OiAiICsgc3RyKGV4YykKICAgICAgICAgICAgc3Quc2Vzc2lvbl9zdGF0ZVsiY2ZnX3Jlc3VsdCJdID0gc3RyKG91dCkKICAgICAgICAgICAgaW52YWxpZGF0'
    || 'ZV9wYW5lbF9jYWNoZSgpCiAgICAgICAgICAgIHN0LnJlcnVuKCkKICAgIHdpdGggYjI6CiAgICAgICAgaWYgc3QuYnV0dG9uKCJSZWJ1aWxkIHJlY29yZHMi'
    || 'LCBrZXk9ImNmZ19yZWJ1aWxkIiwgdHlwZT0icHJpbWFyeSIpOgogICAgICAgICAgICB0cnk6CiAgICAgICAgICAgICAgICBvdXQgPSBzZXNzaW9uLnNxbCgi'
    || 'Q0FMTCAiICsgdGd0ICsgIi5SRUJVSUxEX1JFU09MVVRJT04oKSIpLmNvbGxlY3QoKVswXVswXQogICAgICAgICAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGV4'
    || 'YzoKICAgICAgICAgICAgICAgIG91dCA9ICJGQUlMRUQgdG8gcmVidWlsZDogIiArIHN0cihleGMpCiAgICAgICAgICAgIHN0LnNlc3Npb25fc3RhdGVbImNm'
    || 'Z19yZXN1bHQiXSA9IHN0cihvdXQpCiAgICAgICAgICAgIGludmFsaWRhdGVfcGFuZWxfY2FjaGUoKQogICAgICAgICAgICBzdC5yZXJ1bigpCgogICAgbXNn'
    || 'ID0gc3RyKHN0LnNlc3Npb25fc3RhdGUuZ2V0KCJjZmdfcmVzdWx0Iikgb3IgIiIpCiAgICBpZiBtc2c6CiAgICAgICAgaWYgbXNnLnN0YXJ0c3dpdGgoIkRP'
    || 'TkUiKSBvciBtc2cuc3RhcnRzd2l0aCgiUkVCVUlMVCIpIG9yIG1zZy5zdGFydHN3aXRoKCJSRVNUT1JFRCIpOgogICAgICAgICAgICBzdC5zdWNjZXNzKG1z'
    || 'ZywgaWNvbj0iOm1hdGVyaWFsL2NoZWNrOiIpCiAgICAgICAgZWxpZiBtc2cuc3RhcnRzd2l0aCgiUkVGVVNFRCIpOgogICAgICAgICAgICBzdC53YXJuaW5n'
    || 'KG1zZywgaWNvbj0iOm1hdGVyaWFsL2Jsb2NrOiIpCiAgICAgICAgZWxzZToKICAgICAgICAgICAgc3QuZXJyb3IobXNnLCBpY29uPSI6bWF0ZXJpYWwvZXJy'
    || 'b3I6IikKICAgIHN0LmRpdmlkZXIoKQoKCmRlZiBsb2FkX2FjdGlvbnMoc2Vzc2lvbiwgdGd0OiBzdHIpOgogICAgIiIiKChhbGxvd19yZWFsLCBhbGxvd19z'
    || 'YW1wbGUpLCByb3dzKS4gUmV0dXJucyAoKEZhbHNlLCBGYWxzZSksIFtdKSBmb3IgYW55CiAgICBidWlsZCB3aXRob3V0IHRoZSBmcmFtZXdvcmsuCgogICAg'
    || 'V3JhcHBlZCBiZWNhdXNlIGEgc2NoZW1hIGJ1aWx0IGJ5IGFuIG9sZGVyIGFydGlmYWN0IGhhcyBubyBWX0FDVElPTlMsIGFuZCB0aGUKICAgIGFwcCBtdXN0'
    || 'IHN0aWxsIHdvcmsgYWdhaW5zdCBpdCByYXRoZXIgdGhhbiBzaG93aW5nIGEgdHJhY2ViYWNrIHdoZXJlIHRoZQogICAgcHJvbW90aW9uIGJhciB3b3VsZCBi'
    || 'ZS4KICAgICIiIgogICAgdHJ5OgogICAgICAgIHJvd3MgPSBbci5hc19kaWN0KCkgZm9yIHIgaW4gc2Vzc2lvbi5zcWwoCiAgICAgICAgICAgICJTRUxFQ1Qg'
    || 'Q09ERSwgTEFCRUwsIFRJRVIsIEVGRkVDVCwgVU5ETywgRVNUX0NSRURJVFMsIEVTVF9CQVNJUywgIgogICAgICAgICAgICAiU1RBVEVNRU5UUywgVU5ET19T'
    || 'VEFURU1FTlRTLCBUSU1FU19SVU4sIFRJTUVTX1VORE9ORSwgTEFTVF9SVU5fQVQgRlJPTSAiICsgdGd0ICsgIi5WX0FDVElPTlMiKS5jb2xsZWN0KCldCiAg'
    || 'ICBleGNlcHQgRXhjZXB0aW9uOgogICAgICAgIHJldHVybiAoRmFsc2UsIEZhbHNlKSwgW10KICAgICMgVHdvIGF1dGhvcmlzYXRpb25zLCBub3Qgb25lLiBB'
    || 'TExPV19BQ1RJT05TIGdvdmVybnMgTElNSVRFRCBhbmQgUFJPRFVDVElPTiAtLQogICAgIyBhbnl0aGluZyB0aGF0IHJlYWRzIG9yIHdyaXRlcyByZWFsIGRh'
    || 'dGEuIEFMTE9XX1NBTVBMRV9BQ1RJT05TIGdvdmVybnMgU0FNUExFLAogICAgIyBhbmQgZGVmYXVsdHMgVFJVRSwgc28gYSBmcmVzaGx5IGluc3RhbGxlZCBh'
    || 'cHAgaGFzIHNvbWV0aGluZyB0aGF0IHdvcmtzLgogICAgIwogICAgIyBUaGlzIG1pcnJvcnMgUlVOX0FDVElPTiByYXRoZXIgdGhhbiBkZWNpZGluZyBhbnl0'
    || 'aGluZzogdGhlIHByb2NlZHVyZSBlbmZvcmNlcwogICAgIyB0aGUgc2FtZSBzcGxpdCBzZXJ2ZXItc2lkZSBhbmQgcmVmdXNlcyByZWdhcmRsZXNzIG9mIHdo'
    || 'YXQgdGhpcyByZXR1cm5zLiBJZiB0aGUKICAgICMgdHdvIGV2ZXIgZGlzYWdyZWUgdGhlIHByb2Mgd2lucywgd2hpY2ggaXMgdGhlIGNvcnJlY3QgZGlyZWN0'
    || 'aW9uIC0tIGEgZGlzYWJsZWQKICAgICMgYnV0dG9uIGlzIGEgbnVpc2FuY2UsIGEgYnV0dG9uIHRoYXQgYXBwZWFycyBsaXZlIGFuZCB0aGVuIHJlZnVzZXMg'
    || 'aXMgYSBsaWUuCiAgICAjIFNBTVBMRV9BQ1RJT05TX0VOQUJMRUQgaXMgcmVhZCBkZWZlbnNpdmVseSBiZWNhdXNlIGEgc2NoZW1hIGJ1aWx0IGJ5IGFuIG9s'
    || 'ZGVyCiAgICAjIGZpbGUgd2lsbCBub3QgaGF2ZSB0aGUgY29sdW1uLgogICAgdHJ5OgogICAgICAgIGVuYWJsZWQgPSBib29sKHNlc3Npb24uc3FsKAogICAg'
    || 'ICAgICAgICAiU0VMRUNUIEFDVElPTlNfRU5BQkxFRCBGUk9NICIgKyB0Z3QgKyAiLlZfQlVJTERfQ09OVEVYVCIKICAgICAgICApLmNvbGxlY3QoKVswXVsw'
    || 'XSkKICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgZW5hYmxlZCA9IEZhbHNlCiAgICB0cnk6CiAgICAgICAgc2FtcGxlX2VuYWJsZWQgPSBib29sKHNl'
    || 'c3Npb24uc3FsKAogICAgICAgICAgICAiU0VMRUNUIENPQUxFU0NFKFNBTVBMRV9BQ1RJT05TX0VOQUJMRUQsIEZBTFNFKSBGUk9NICIgKyB0Z3QgKyAiLlZf'
    || 'QlVJTERfQ09OVEVYVCIKICAgICAgICApLmNvbGxlY3QoKVswXVswXSkKICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgc2FtcGxlX2VuYWJsZWQgPSBG'
    || 'YWxzZQogICAgcmV0dXJuIChlbmFibGVkLCBzYW1wbGVfZW5hYmxlZCksIHJvd3MKCgpkZWYgbG9hZF9wcmVmaXgoc2Vzc2lvbiwgdGd0OiBzdHIpIC0+IHN0'
    || 'cjoKICAgICIiIlRoZSBwZXItc29sdXRpb24gc2V0dGluZyBwcmVmaXgsIG9yICcnIGlmIHRoaXMgYnVpbGQgcHJlZGF0ZXMgdGhlIGNvbHVtbi4KCiAgICBL'
    || 'ZXB0IHNlcGFyYXRlIGZyb20gbG9hZF9hY3Rpb25zIHJhdGhlciB0aGFuIHdpZGVuaW5nIGl0cyByZXR1cm4sIGJlY2F1c2UKICAgIGV2ZXJ5IGNhbGxlciBv'
    || 'ZiB0aGF0IHBhaXItb2YtdHVwbGVzIHNpZ25hdHVyZSB3b3VsZCBoYXZlIHRvIGNoYW5nZSBhbmQgbm9uZQogICAgb2YgdGhlbSB3YW50IHRoZSBwcmVmaXgu'
    || 'IFRoaXMgZXhpc3RzIHNvIHRoZSBhcHAgY2FuIHByaW50IHRoZSBsaW5lIHlvdSB3b3VsZAogICAgYWN0dWFsbHkgZWRpdCBpbnN0ZWFkIG9mIGEgc2V0dGlu'
    || 'ZyBuYW1lIHRoYXQgYXBwZWFycyBpbiBubyBmaWxlLgogICAgIiIiCiAgICB0cnk6CiAgICAgICAgcmV0dXJuIHN0cihzZXNzaW9uLnNxbCgKICAgICAgICAg'
    || 'ICAgIlNFTEVDVCBTRVRUSU5HX1BSRUZJWCBGUk9NICIgKyB0Z3QgKyAiLlZfQlVJTERfQ09OVEVYVCIKICAgICAgICApLmNvbGxlY3QoKVswXVswXSBvciAi'
    || 'IikKICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgcmV0dXJuICIiCgoKZGVmIGxvYWRfaGVhZGxpbmUoc2Vzc2lvbiwgdGd0OiBzdHIpOgogICAgIiIi'
    || 'VGhlIG9uZS1saW5lIG1vbnRobHkgcnVuIHJhdGUsIG9yIE5vbmUuCgogICAgV3JhcHBlZCBmb3IgdGhlIHNhbWUgcmVhc29uIGxvYWRfYWN0aW9ucyBpczog'
    || 'YSBzY2hlbWEgYnVpbHQgYnkgYW4gb2xkZXIKICAgIGFydGlmYWN0IGhhcyBubyBWX1JVTl9SQVRFX0hFQURMSU5FLCBhbmQgdGhlIGFwcCBtdXN0IHN0aWxs'
    || 'IHdvcmsgYWdhaW5zdCBpdAogICAgcmF0aGVyIHRoYW4gc2hvd2luZyBhIHRyYWNlYmFjayB3aGVyZSB0aGUgc3RhbmRpbmcgY29zdCB3b3VsZCBiZS4KCiAg'
    || 'ICBUaGlzIGlzIHRoZSBvbmx5IHN1cmZhY2UgdGhhdCBwcmludHMgaXQuIFRoZSB2aWV3IGhhcyBleGlzdGVkIGZvciBldmVyeQogICAgYnVpbGQgZm9yIGEg'
    || 'd2hpbGUgYW5kIHdhcyByZWFkIGJ5IG5vdGhpbmcgYnV0IHRoZSB0ZXN0IGhhcm5lc3MsIHNvIHRoZQogICAgc2VudGVuY2Ugd3JpdHRlbiBmb3IgdGhlIGFw'
    || 'cCB0byBwcmludCB3YXMgcHJpbnRlZCBieSBub2JvZHkuCiAgICAiIiIKICAgIHRyeToKICAgICAgICByb3dzID0gc2Vzc2lvbi5zcWwoCiAgICAgICAgICAg'
    || 'ICJTRUxFQ1QgSEVBRExJTkUsIEVTVF9DUkVESVRTX1BFUl9NT05USCBGUk9NICIgKyB0Z3QgKyAiLlZfUlVOX1JBVEVfSEVBRExJTkUiCiAgICAgICAgKS5j'
    || 'b2xsZWN0KCkKICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgcmV0dXJuIE5vbmUKICAgIGlmIG5vdCByb3dzOgogICAgICAgIHJldHVybiBOb25lCiAg'
    || 'ICByID0gcm93c1swXS5hc19kaWN0KCkKICAgIHJldHVybiAoc3RyKHIuZ2V0KCJIRUFETElORSIpIG9yICIiKSwgci5nZXQoIkVTVF9DUkVESVRTX1BFUl9N'
    || 'T05USCIpKQoKCmRlZiBsb2FkX2FjdGlvbl9wYXJhbXMoc2Vzc2lvbiwgdGd0OiBzdHIpOgogICAgIiIie2FjdGlvbl9jb2RlOiBbcGFyYW0gZGljdCwgLi4u'
    || 'XX0uIEVtcHR5IGRpY3QgZm9yIGFueSBidWlsZCB3aXRob3V0IHBhcmFtcy4KCiAgICBXcmFwcGVkIGZvciB0aGUgc2FtZSByZWFzb24gbG9hZF9hY3Rpb25z'
    || 'IGlzOiBhIHNjaGVtYSBidWlsdCBieSBhbiBvbGRlciBhcnRpZmFjdAogICAgaGFzIG5vIFZfQUNUSU9OX1BBUkFNUywgYW5kIHRoZSBhcHAgbXVzdCBrZWVw'
    || 'IHdvcmtpbmcgYWdhaW5zdCBpdCByYXRoZXIgdGhhbgogICAgc2hvd2luZyBhIHRyYWNlYmFjayB3aGVyZSB0aGUgcHJvbW90aW9uIGJhciB3b3VsZCBiZS4g'
    || 'QW4gZW1wdHkgcmVzdWx0IGlzIHRoZQogICAgbm9ybWFsIGNhc2UgLS0gbW9zdCBhY3Rpb25zIHRha2Ugbm8gcGFyYW1ldGVycyBhbmQgcmVuZGVyIGV4YWN0'
    || 'bHkgYXMgYmVmb3JlLgoKICAgIERlbGliZXJhdGVseSBOT1QgZm9sZGVkIGludG8gbG9hZF9hY3Rpb25zLiBUaGF0IGZ1bmN0aW9uJ3MgU0VMRUNUIGxpc3Qg'
    || 'aXMgaXRzCiAgICBjb21wYXRpYmlsaXR5IGNvbnRyYWN0IHdpdGggb2xkZXIgc2NoZW1hczsgYWRkaW5nIGEgY29sdW1uIHRvIGl0IHdvdWxkIG1ha2UgZXZl'
    || 'cnkKICAgIGJ1aWxkIHdpdGhvdXQgdGhhdCBjb2x1bW4gZmFsbCBpbnRvIHRoZSBleGNlcHQgYnJhbmNoIGFuZCBsb3NlIGl0cyB3aG9sZSBhY3Rpb24KICAg'
    || 'IGJhci4gQSBzZXBhcmF0ZSwgc2VwYXJhdGVseS13cmFwcGVkIHJlYWQgZGVncmFkZXMgdG8gIm5vIHBhcmFtZXRlcnMiIGluc3RlYWQuCiAgICAiIiIKICAg'
    || 'IHRyeToKICAgICAgICByb3dzID0gW3IuYXNfZGljdCgpIGZvciByIGluIHNlc3Npb24uc3FsKAogICAgICAgICAgICAiU0VMRUNUIENPREUsIE9SRElOQUws'
    || 'IFBBUkFNX05BTUUsIExBQkVMLCBLSU5ELCBPUFRJT05TX1NRTCwgT1BUSU9OUywgIgogICAgICAgICAgICAiTUlOX1ZBTFVFLCBNQVhfVkFMVUUsIEhFTFAg'
    || 'RlJPTSAiICsgdGd0ICsgIi5WX0FDVElPTl9QQVJBTVMgIgogICAgICAgICAgICAiT1JERVIgQlkgQ09ERSwgT1JESU5BTCIpLmNvbGxlY3QoKV0KICAgIGV4'
    || 'Y2VwdCBFeGNlcHRpb246CiAgICAgICAgcmV0dXJuIHt9CiAgICBvdXQgPSB7fQogICAgZm9yIHIgaW4gcm93czoKICAgICAgICBvdXQuc2V0ZGVmYXVsdChz'
    || 'dHIoci5nZXQoIkNPREUiKSBvciAiIiksIFtdKS5hcHBlbmQocikKICAgIHJldHVybiBvdXQKCgpkZWYgYWN0aW9uX3BhcmFtX29wdGlvbnMoc2Vzc2lvbiwg'
    || 'cCkgLT4gbGlzdDoKICAgICIiIlRoZSBjaG9pY2VzIHRvIE9GRkVSIGZvciBvbmUgcGFyYW1ldGVyLiBEaXNwbGF5IG9ubHkuCgogICAgVGhpcyBsaXN0IGlz'
    || 'IHdoYXQgdGhlIHdpZGdldCBzaG93czsgaXQgaXMgTk9UIHdoYXQgYXV0aG9yaXNlcyB0aGUgdmFsdWUuIFRoZQogICAgcHJvY2VkdXJlIHJlLXJ1bnMgdGhl'
    || 'IHJlZ2lzdHJ5J3Mgb3duIGFsbG93ZWRfc3FsIHdoZW4gaXQgdmFsaWRhdGVzLCBzbyBhIHN0YWxlIG9yCiAgICB0YW1wZXJlZCBsaXN0IGhlcmUgY2Fubm90'
    || 'IHdpZGVuIHdoYXQgYW4gYWN0aW9uIHdpbGwgYWNjZXB0IC0tIGl0IGNhbiBvbmx5IGZhaWwgdG8KICAgIG9mZmVyIHNvbWV0aGluZyB0aGUgcHJvY2VkdXJl'
    || 'IHdvdWxkIGhhdmUgcGVybWl0dGVkLiBUaGF0IGFzeW1tZXRyeSBpcyBkZWxpYmVyYXRlOgogICAgdGhlIGFwcCBpcyBhbGxvd2VkIHRvIGJlIHdyb25nIGlu'
    || 'IHRoZSBkaXJlY3Rpb24gb2Ygb2ZmZXJpbmcgdG9vIGxpdHRsZS4KICAgICIiIgogICAgb3B0cyA9IHAuZ2V0KCJPUFRJT05TIikKICAgIGlmIG9wdHM6CiAg'
    || 'ICAgICAgdHJ5OgogICAgICAgICAgICByZXR1cm4gW3N0cih2KSBmb3IgdiBpbiAoanNvbi5sb2FkcyhvcHRzKSBpZiBpc2luc3RhbmNlKG9wdHMsIHN0cikg'
    || 'ZWxzZSBvcHRzKV0KICAgICAgICBleGNlcHQgRXhjZXB0aW9uOgogICAgICAgICAgICBwYXNzCiAgICBzcWwgPSBzdHIocC5nZXQoIk9QVElPTlNfU1FMIikg'
    || 'b3IgIiIpLnN0cmlwKCkKICAgIGlmIG5vdCBzcWw6CiAgICAgICAgcmV0dXJuIFtdCiAgICB0cnk6CiAgICAgICAgcmV0dXJuIFtzdHIoclswXSkgZm9yIHIg'
    || 'aW4gc2Vzc2lvbi5zcWwoCiAgICAgICAgICAgICJTRUxFQ1QgQUxMT1dFRF9WQUxVRSBGUk9NICgiICsgc3FsICsgIikgTElNSVQgIiArIHN0cihST1dfQ0FQ'
    || 'KSkuY29sbGVjdCgpXQogICAgZXhjZXB0IEV4Y2VwdGlvbjoKICAgICAgICAjIEEgYnJva2VuIG9wdGlvbnMgcXVlcnkgbXVzdCBub3QgdGFrZSB0aGUgd2hv'
    || 'bGUgcHJvbW90aW9uIGJhciBkb3duIHdpdGggaXQuCiAgICAgICAgIyBSZXR1cm5pbmcgbm90aGluZyBsZWF2ZXMgdGhlIGZpZWxkIGVtcHR5LCB0aGUgUnVu'
    || 'IGJ1dHRvbiBkaXNhYmxlZCwgYW5kIHRoZQogICAgICAgICMgcmVzdCBvZiB0aGUgYWN0aW9ucyB1c2FibGUuCiAgICAgICAgcmV0dXJuIFtdCgoKZGVmIGFj'
    || 'dGlvbl9wYXJhbV92YWx1ZXMoc2Vzc2lvbiwgY29kZTogc3RyLCBwYXJhbXM6IGxpc3QpOgogICAgIiIiUmVuZGVyIG9uZSB3aWRnZXQgcGVyIHBhcmFtZXRl'
    || 'ciBhbmQgcmV0dXJuICh2YWx1ZXMgZGljdCwgYWxsX3N1cHBsaWVkKS4KCiAgICBQbGFjZWQgSU5TSURFIHRoZSBhcm1lZCBjb25maXJtYXRpb24gYmxvY2sg'
    || 'YnkgdGhlIGNhbGxlciwgbm90IG9uIHRoZSBhY3Rpb24gY2FyZC4KICAgIFR3byByZWFzb25zLiBUaGUgdmFsdWVzIG11c3Qgbm90IGJlIGFibGUgdG8gY2hh'
    || 'bmdlIGJldHdlZW4gYXJtaW5nIGFuZCBjb25maXJtaW5nCiAgICAtLSB0aGUgdHlwZWQgY29kZSBjb25maXJtcyBhIHNwZWNpZmljIGNoYW5nZSwgc28gdGhl'
    || 'IGNoYW5nZSBoYXMgdG8gYmUgc2V0dGxlZAogICAgYmVmb3JlIGl0IGlzIHR5cGVkLiBBbmQgaXQga2VlcHMgdGhlIHR5cGVkIGNvbmZpcm1hdGlvbiBhcyB0'
    || 'aGUgZ2VudWluZSBsYXN0IHN0ZXAKICAgIHJhdGhlciB0aGFuIG9uZSBmaWVsZCBhbW9uZyBzZXZlcmFsLgogICAgIiIiCiAgICB2YWxzID0ge30KICAgIG1p'
    || 'c3NpbmcgPSBGYWxzZQogICAgZm9yIHAgaW4gcGFyYW1zOgogICAgICAgIG5hbWUgPSBzdHIocC5nZXQoIlBBUkFNX05BTUUiKSBvciAiIikKICAgICAgICBs'
    || 'YWJlbCA9IHN0cihwLmdldCgiTEFCRUwiKSBvciBuYW1lKQogICAgICAgIGtpbmQgPSBzdHIocC5nZXQoIktJTkQiKSBvciAiSURFTlQiKS51cHBlcigpCiAg'
    || 'ICAgICAga2V5ID0gInBhcmFtXyIgKyBjb2RlICsgIl8iICsgbmFtZQogICAgICAgIGhlbHBfdHh0ID0gc3RyKHAuZ2V0KCJIRUxQIikgb3IgIiIpIG9yIE5v'
    || 'bmUKICAgICAgICBpZiBraW5kID09ICJOVU1CRVIiOgogICAgICAgICAgICBsbyA9IHAuZ2V0KCJNSU5fVkFMVUUiKQogICAgICAgICAgICBoaSA9IHAuZ2V0'
    || 'KCJNQVhfVkFMVUUiKQogICAgICAgICAgICB2ID0gc3QubnVtYmVyX2lucHV0KAogICAgICAgICAgICAgICAgbGFiZWwsIGtleT1rZXksIGhlbHA9aGVscF90'
    || 'eHQsCiAgICAgICAgICAgICAgICBtaW5fdmFsdWU9ZmxvYXQobG8pIGlmIGxvIGlzIG5vdCBOb25lIGVsc2UgTm9uZSwKICAgICAgICAgICAgICAgIG1heF92'
    || 'YWx1ZT1mbG9hdChoaSkgaWYgaGkgaXMgbm90IE5vbmUgZWxzZSBOb25lLAogICAgICAgICAgICAgICAgdmFsdWU9ZmxvYXQobG8pIGlmIGxvIGlzIG5vdCBO'
    || 'b25lIGVsc2UgMC4wLAogICAgICAgICAgICAgICAgc3RlcD0xLjApCiAgICAgICAgICAgICMgRW1pdCB3aG9sZSBudW1iZXJzIHdpdGhvdXQgYSB0cmFpbGlu'
    || 'ZyAuMDogQVJDSElWRV9GT1JfREFZUyA9IDkwLjAgaXMgbm90CiAgICAgICAgICAgICMgdmFsaWQgaW4gdGhlIERETCBjbGF1c2UgdGhpcyBsYW5kcyBpbi4K'
    || 'ICAgICAgICAgICAgdmFsc1tuYW1lXSA9IHN0cihpbnQodikpIGlmIGZsb2F0KHYpLmlzX2ludGVnZXIoKSBlbHNlIHN0cih2KQogICAgICAgICAgICBjb250'
    || 'aW51ZQogICAgICAgIGNob2ljZXMgPSBhY3Rpb25fcGFyYW1fb3B0aW9ucyhzZXNzaW9uLCBwKQogICAgICAgIGlmIGNob2ljZXM6CiAgICAgICAgICAgICMg'
    || 'aW5kZXg9Tm9uZSBzbyBub3RoaW5nIGlzIHByZS1zZWxlY3RlZC4gQSBwcmUtZmlsbGVkIHRhcmdldCBpcyBob3cgc29tZW9uZQogICAgICAgICAgICAjIHJ1'
    || 'bnMgYSBjaGFuZ2UgYWdhaW5zdCB3aGF0ZXZlciBoYXBwZW5lZCB0byBzb3J0IGZpcnN0LgogICAgICAgICAgICB2ID0gc3Quc2VsZWN0Ym94KGxhYmVsLCBj'
    || 'aG9pY2VzLCBpbmRleD1Ob25lLCBrZXk9a2V5LCBoZWxwPWhlbHBfdHh0LAogICAgICAgICAgICAgICAgICAgICAgICAgICAgIHBsYWNlaG9sZGVyPSJDaG9v'
    || 'c2UgIiArIGxhYmVsLmxvd2VyKCkpCiAgICAgICAgICAgIGlmIHYgaXMgTm9uZToKICAgICAgICAgICAgICAgIG1pc3NpbmcgPSBUcnVlCiAgICAgICAgICAg'
    || 'IGVsc2U6CiAgICAgICAgICAgICAgICB2YWxzW25hbWVdID0gc3RyKHYpCiAgICAgICAgZWxpZiBwLmdldCgiRlJFRUZPUk0iKToKICAgICAgICAgICAgIyBB'
    || 'IG5hbWUgYmVpbmcgQ1JFQVRFRCBjYW5ub3QgYmUgY2hlY2tlZCBhZ2FpbnN0IGEgbGlzdCBvZiB0aGluZ3MgdGhhdAogICAgICAgICAgICAjIGFscmVhZHkg'
    || 'ZXhpc3QsIHNvIHRoaXMgb25lIGlzIHR5cGVkLiBJdCBpcyBub3QgdW52YWxpZGF0ZWQ6IHRoZSBwcm9jZWR1cmUKICAgICAgICAgICAgIyBzdGlsbCBhcHBs'
    || 'aWVzIHRoZSBpZGVudGlmaWVyIHNoYXBlIGdhdGUsIHNvIGFueXRoaW5nIGNhcnJ5aW5nIGEgcXVvdGUsIGEKICAgICAgICAgICAgIyBzcGFjZSBvciBhIHN0'
    || 'YXRlbWVudCB0ZXJtaW5hdG9yIGlzIHJlZnVzZWQgc2VydmVyLXNpZGUuCiAgICAgICAgICAgIHYgPSBzdC50ZXh0X2lucHV0KGxhYmVsLCBrZXk9a2V5LCBo'
    || 'ZWxwPWhlbHBfdHh0KQogICAgICAgICAgICBpZiBub3Qgc3RyKHYgb3IgIiIpLnN0cmlwKCk6CiAgICAgICAgICAgICAgICBtaXNzaW5nID0gVHJ1ZQogICAg'
    || 'ICAgICAgICBlbHNlOgogICAgICAgICAgICAgICAgdmFsc1tuYW1lXSA9IHN0cih2KS5zdHJpcCgpCiAgICAgICAgZWxzZToKICAgICAgICAgICAgc3QuY2Fw'
    || 'dGlvbihsYWJlbCArICIg4oCUIG5vIHBlcm1pdHRlZCB2YWx1ZXMgYXJlIGF2YWlsYWJsZSBmb3IgdGhpcyBidWlsZCwgIgogICAgICAgICAgICAgICAgICAg'
    || 'ICAgICJzbyB0aGlzIGFjdGlvbiBjYW5ub3QgcnVuLiBOb3RoaW5nIGlzIHN3aXRjaGVkIG9mZjsgdGhlcmUgaXMgIgogICAgICAgICAgICAgICAgICAgICAg'
    || 'ICJzaW1wbHkgbm90aGluZyBpdCBjb3VsZCBsZWdhbGx5IGJlIHBvaW50ZWQgYXQuIikKICAgICAgICAgICAgbWlzc2luZyA9IFRydWUKICAgIHJldHVybiB2'
    || 'YWxzLCBub3QgbWlzc2luZwoKCmRlZiBwcm9tb3Rpb25fYmFyKHNlc3Npb24sIHRndDogc3RyKSAtPiBOb25lOgogICAgIiIiVGhlIG9uZSBwbGFjZSBpbiB0'
    || 'aGUgYXBwIHRoYXQgY2FuIGNoYW5nZSB0aGUgYWNjb3VudC4KCiAgICBOYXRpdmUgU3RyZWFtbGl0IHJhdGhlciB0aGFuIHBhcnQgb2YgdGhlIFJlYWN0IHBh'
    || 'Z2UsIGFuZCBub3QgYnkgcHJlZmVyZW5jZToKICAgIHRoZSBidW5kbGUgcnVucyBpbnNpZGUgY29tcG9uZW50cy5odG1sLCB3aGljaCBpcyBhIHNhbmRib3hl'
    || 'ZCBjcm9zcy1vcmlnaW4KICAgIGlmcmFtZSB3aXRoIG5vIFNub3dmbGFrZSBzZXNzaW9uLCBzbyBhIFJlYWN0IGJ1dHRvbiBwaHlzaWNhbGx5IGNhbm5vdCBl'
    || 'eGVjdXRlCiAgICBhbnl0aGluZy4gVGhlIGJpZGlyZWN0aW9uYWwgYWx0ZXJuYXRpdmUgKHN0LmNvbXBvbmVudHMudjIpIG5lZWRzIFN0cmVhbWxpdAogICAg'
    || 'MS41NyssIGFuZCB3YXJlaG91c2UgcnVudGltZXMgY2FwIGF0IDEuNTIuMi4gU28gdGhlIGRpc3BsYXkgaXMgUmVhY3QgYW5kIHRoZQogICAgY29udHJvbHMg'
    || 'YXJlIFN0cmVhbWxpdCwgc3R5bGVkIHRvIHNpdCB3aXRoIGl0LgoKICAgIERlbGliZXJhdGVseSB1c2VzIG5vIHN0Lm1hcmtkb3duOiB0aGUgaG9zdCBjaGVj'
    || 'ayB0cmVhdHMgc3RyYXkgbWFya2Rvd24gYXMKICAgIHBhZ2UgY29udGVudCBsZWFraW5nIG91dHNpZGUgdGhlIGNvbXBvbmVudCwgd2hpY2ggaXMgaG93IGEg'
    || 'c3BsaWNlZCBkb2NzdHJpbmcKICAgIG9uY2Ugc2hpcHBlZCB0aGUgd2hvbGUgYXBwIGFzIGEgdHJhY2ViYWNrLiBXaWRnZXRzIGFyZSBpbnRlbnRpb25hbCBh'
    || 'bmQKICAgIGV4ZW1wdDsgcHJvc2UgaXMgbm90LgogICAgIiIiCiAgICAoYWxsb3dfcmVhbCwgYWxsb3dfc2FtcGxlKSwgcm93cyA9IGxvYWRfYWN0aW9ucyhz'
    || 'ZXNzaW9uLCB0Z3QpCgogICAgIyBUaGUgc3RhbmRpbmcgY29zdCBwcmludHMgd2hldGhlciBvciBub3QgdGhpcyBidWlsZCByZWdpc3RlcmVkIGFueSBhY3Rp'
    || 'b25zLAogICAgIyBhbmQgQkVGT1JFIHRoZW0sIGJlY2F1c2UgaXQgaXMgdGhlIHJlY3VycmluZyBudW1iZXIuIEVhY2ggYnV0dG9uIGJlbG93CiAgICAjIGNv'
    || 'c3RzIHNvbWV0aGluZyBPTkNFOyB0aGlzIGlzIHdoYXQgdGhlIGJ1aWxkIGNvc3RzIGV2ZXJ5IG1vbnRoIGlmIG5vYm9keQogICAgIyB0b3VjaGVzIGl0IGFn'
    || 'YWluLiBEZWxpYmVyYXRlbHkgbm90IHN1bW1lZCB3aXRoIHRoZSBwZXItYWN0aW9uIGVzdGltYXRlcyAtLQogICAgIyBvbmUgaXMgUFJPSkVDVEVEIGFuZCB0'
    || 'aGUgb3RoZXIgaXMgbWVhc3VyZWQsIGFuZCBhZGRpbmcgdGhlbSB3b3VsZCBpbnZlbnQgYQogICAgIyBmaWd1cmUgdGhhdCBtZWFucyBub3RoaW5nLgogICAg'
    || 'aGwgPSBsb2FkX2hlYWRsaW5lKHNlc3Npb24sIHRndCkKICAgIGlmIGhsIGlzIG5vdCBOb25lIGFuZCBobFswXToKICAgICAgICBzdC5jYXB0aW9uKCJXSEFU'
    || 'IFRISVMgQ09TVFMgVE8gTEVBVkUgUlVOTklORyIpCiAgICAgICAgc3QuY2FwdGlvbihobFswXSkKCiAgICBpZiBub3Qgcm93czoKICAgICAgICByZXR1cm4K'
    || 'CiAgICBzdC5jYXB0aW9uKCJXSEFUIFRISVMgQ0FOIERPIE5FWFQiKQogICAgIyBPbmx5IHdhcm4gYWJvdXQgd2hhdCBpcyBhY3R1YWxseSBzd2l0Y2hlZCBv'
    || 'ZmYuIEFubm91bmNpbmcgInRoZXNlIGFyZSBzd2l0Y2hlZAogICAgIyBvZmYiIG92ZXIgYSBsaXN0IGNvbnRhaW5pbmcgbGl2ZSBTQU1QTEUgYnV0dG9ucyBp'
    || 'cyB3b3JzZSB0aGFuIHNpbGVuY2U6IHRoZQogICAgIyByZWFkZXIgYmVsaWV2ZXMgaXQgYW5kIHN0b3BzIHRyeWluZy4KICAgIGlmIG5vdCBhbGxvd19yZWFs'
    || 'IGFuZCBub3QgYWxsb3dfc2FtcGxlOgogICAgICAgIHBmeCA9IGxvYWRfcHJlZml4KHNlc3Npb24sIHRndCkKICAgICAgICAjIE5hbWUgdGhlIGxpbmUsIG5v'
    || 'dCB0aGUgc2V0dGluZy4gInJlLXJ1biB3aXRoIEFMTE9XX0FDVElPTlMgPSBUUlVFIiBzZW50CiAgICAgICAgIyB0aGUgcmVhZGVyIGxvb2tpbmcgZm9yIGEg'
    || 'c2V0dGluZyB0aGF0IGFwcGVhcnMgaW4gbm8gZmlsZSB1bmRlciB0aGF0CiAgICAgICAgIyBuYW1lLCB3aGljaCBpcyBob3cgYSBwdXNoLWJ1dHRvbiBkZXBs'
    || 'b3ltZW50IGNhbWUgdG8gbG9vayBsaWtlIGl0IG5lZWRlZAogICAgICAgICMgYSB0ZXJtaW5hbCBzZXNzaW9uIGFuZCBzb21lIGd1ZXNzd29yay4KICAgICAg'
    || 'ICBhcm0gPSAoIlNFVCAiICsgcGZ4ICsgIl9BTExPV19BQ1RJT05TID0gVFJVRTsiKSBpZiBwZnggZWxzZSAiQUxMT1dfQUNUSU9OUyA9IFRSVUUiCiAgICAg'
    || 'ICAgc3QuaW5mbygKICAgICAgICAgICAgIlRoZXNlIGFyZSBzd2l0Y2hlZCBvZmYuIFRoaXMgYnVpbGQgd2FzIGNyZWF0ZWQgd2l0aCAiCiAgICAgICAgICAg'
    || 'ICJBTExPV19BQ1RJT05TID0gRkFMU0UsIHNvIHRoZSBidXR0b25zIGJlbG93IGFyZSBpbmVydCBhbmQgdGhlICIKICAgICAgICAgICAgInByb2NlZHVyZSBi'
    || 'ZWhpbmQgdGhlbSByZWZ1c2VzLiBFdmVyeXRoaW5nIGVhY2ggb25lIHdvdWxkIGRvLCBhbmQgIgogICAgICAgICAgICAid2hhdCBpdCB3b3VsZCBjb3N0LCBp'
    || 'cyBsaXN0ZWQgYW55d2F5IOKAlCB0byBhcm0gdGhlbSwgY2hhbmdlIHRoZSAiCiAgICAgICAgICAgICJsaW5lIG5lYXIgdGhlIHRvcCBvZiB0aGUgc2NyaXB0'
    || 'IHlvdSBhbHJlYWR5IHJhbiB0byAiCiAgICAgICAgICAgICsgYXJtICsgIiBhbmQgcnVuIHRoYXQgZmlsZSBhZ2Fpbi4gVGhlcmUgaXMgbm90aGluZyBlbHNl'
    || 'IHRvIHR5cGU6ICIKICAgICAgICAgICAgInRoZSBmaWxlIGlzIHRoZSBvbmx5IHBsYWNlIHRoaXMgaXMgc3dpdGNoZWQgb24sIGFuZCBydW5uaW5nIGl0IGlz'
    || 'ICIKICAgICAgICAgICAgInRoZSB3aG9sZSBwcm9jZWR1cmUuIiwKICAgICAgICAgICAgaWNvbj0iOm1hdGVyaWFsL2xvY2s6IikKCiAgICBieV90aWVyID0g'
    || 'e30KICAgIGZvciByIGluIHJvd3M6CiAgICAgICAgYnlfdGllci5zZXRkZWZhdWx0KHN0cihyLmdldCgiVElFUiIpIG9yICJQUk9EVUNUSU9OIikudXBwZXIo'
    || 'KSwgW10pLmFwcGVuZChyKQoKICAgIGZvciB0aWVyIGluIFRJRVJfT1JERVI6CiAgICAgICAgZ3JvdXAgPSBieV90aWVyLmdldCh0aWVyLCBbXSkKICAgICAg'
    || 'ICBpZiBub3QgZ3JvdXA6CiAgICAgICAgICAgIGNvbnRpbnVlCiAgICAgICAgIyBTQU1QTEUgcnVucyBvbiBzZWVkZWQgZGF0YSB0aGlzIHNjcmlwdCBjcmVh'
    || 'dGVkLCBzbyBpdCBhbnN3ZXJzIHRvCiAgICAgICAgIyBBTExPV19TQU1QTEVfQUNUSU9OUy4gRXZlcnl0aGluZyBlbHNlIHRvdWNoZXMgdGhlIGN1c3RvbWVy'
    || 'J3Mgb3duIG9iamVjdHMKICAgICAgICAjIGFuZCBhbnN3ZXJzIHRvIEFMTE9XX0FDVElPTlMuIFVua25vd24gdGllcnMgdGFrZSB0aGUgc3RyaWN0ZXIgZ2F0'
    || 'ZS4KICAgICAgICB0aWVyX2VuYWJsZWQgPSBhbGxvd19zYW1wbGUgaWYgdGllciA9PSAiU0FNUExFIiBlbHNlIGFsbG93X3JlYWwKICAgICAgICBzdC5jYXB0'
    || 'aW9uKHRpZXIgKyAiIOKAlCAiICsgVElFUl9CTFVSQi5nZXQodGllciwgIiIpCiAgICAgICAgICAgICAgICAgICArICgiIiBpZiB0aWVyX2VuYWJsZWQgZWxz'
    || 'ZQogICAgICAgICAgICAgICAgICAgICAgIiAgwrcgIHN3aXRjaGVkIG9mZiBpbiB0aGUgZmlsZSIpKQogICAgICAgIGNvbHMgPSBzdC5jb2x1bW5zKGxlbihn'
    || 'cm91cCkpCiAgICAgICAgZm9yIGNvbCwgciBpbiB6aXAoY29scywgZ3JvdXApOgogICAgICAgICAgICB3aXRoIGNvbDoKICAgICAgICAgICAgICAgIGNvZGUg'
    || 'PSBzdHIoci5nZXQoIkNPREUiKSBvciAiIikKICAgICAgICAgICAgICAgIGVzdCA9IHIuZ2V0KCJFU1RfQ1JFRElUUyIpCiAgICAgICAgICAgICAgICAjIFRo'
    || 'cmVlIGxpbmVzIGFuZCBhIGJ1dHRvbiwgbm90IGZpdmUgbGluZXMgYW5kIGEgYnV0dG9uLiBUaGUKICAgICAgICAgICAgICAgICMgZXN0aW1hdGUgYW5kIGl0'
    || 'cyBiYXNpcyBzdGlsbCB0cmF2ZWwgV0lUSCB0aGUgY29udHJvbCAtLSBhIGJ1dHRvbgogICAgICAgICAgICAgICAgIyB0aGF0IGNoYW5nZXMgcHJvZHVjdGlv'
    || 'biB3aXRob3V0IHNheWluZyB3aGF0IGl0IGNvc3RzIGlzIHRoZSB0aGluZwogICAgICAgICAgICAgICAgIyB0aGlzIHJlcG8gZXhpc3RzIHRvIGF2b2lkIC0t'
    || 'IGJ1dCBgYmFzaXNgIGFuZCBgdW5kb2AgYmVsb25nIGluIHRoZQogICAgICAgICAgICAgICAgIyB0b29sdGlwLiBSZW5kZXJlZCBhcyBjb2x1bW5zIG9mIGJv'
    || 'ZHkgdGV4dCB0aGV5IHdlcmUgZm91ciBsaW5lcyBvZgogICAgICAgICAgICAgICAgIyBwcm9zZSBlYWNoLCBhbmQgdGhlIHJlYWRlciBzdG9wcGVkIGJlZm9y'
    || 'ZSB0aGUgYnV0dG9uLgogICAgICAgICAgICAgICAgc3QuY2FwdGlvbigiKioiICsgc3RyKHIuZ2V0KCJMQUJFTCIpIG9yIGNvZGUpICsgIioqIikKICAgICAg'
    || 'ICAgICAgICAgIHN0LmNhcHRpb24oIn4iICsgZm10X2NyZWRpdHMoZXN0KSArICIgY3JlZGl0cyDCtyAiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICsg'
    || 'c3RyKHIuZ2V0KCJTVEFURU1FTlRTIikgb3IgMCkgKyAiIHN0YXRlbWVudChzKSIKICAgICAgICAgICAgICAgICAgICAgICAgICAgKyAoIiDCtyBydW4gIiAr'
    || 'IHN0cihyWyJUSU1FU19SVU4iXSkgKyAieCBhbHJlYWR5IgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICBpZiByLmdldCgiVElNRVNfUlVOIikgZWxz'
    || 'ZSAiIikpCiAgICAgICAgICAgICAgICBzdC5jYXB0aW9uKHN0cihyLmdldCgiRUZGRUNUIikgb3IgIm5vdCBzdGF0ZWQiKSkKICAgICAgICAgICAgICAgIGlm'
    || 'IHN0LmJ1dHRvbigiUnVuICIgKyBjb2RlLCBrZXk9ImFybV8iICsgY29kZSwgZGlzYWJsZWQ9bm90IHRpZXJfZW5hYmxlZCwKICAgICAgICAgICAgICAgICAg'
    || 'ICAgICAgICAgICB1c2VfY29udGFpbmVyX3dpZHRoPVRydWUsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgaGVscD0iRXN0aW1hdGUgYmFzaXM6ICIg'
    || 'KyBzdHIoci5nZXQoIkVTVF9CQVNJUyIpIG9yICJub3Qgc3RhdGVkIikKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICsgIlxuXG5UbyB1bmRv'
    || 'OiAiICsgc3RyKHIuZ2V0KCJVTkRPIikgb3IgIm5vdCBzdGF0ZWQiKSk6CiAgICAgICAgICAgICAgICAgICAgc3Quc2Vzc2lvbl9zdGF0ZVsiYXJtZWQiXSA9'
    || 'IGNvZGUKICAgICAgICAgICAgICAgICAgICBzdC5zZXNzaW9uX3N0YXRlLnBvcCgicmVzdWx0XyIgKyBjb2RlLCBOb25lKQogICAgICAgICAgICAgICAgIyBV'
    || 'bmRvIGFwcGVhcnMgb25seSBvbmNlIHRoZSBhY3Rpb24gaGFzIGFjdHVhbGx5IGNvbXBsZXRlZCwgYmVjYXVzZQogICAgICAgICAgICAgICAgIyBVTkRPX0FD'
    || 'VElPTiByZWZ1c2VzIG90aGVyd2lzZSBhbmQgYSBidXR0b24gd2hvc2Ugb25seSBvdXRjb21lIGlzIGEKICAgICAgICAgICAgICAgICMgcmVmdXNhbCB0ZWFj'
    || 'aGVzIHRoZSByZWFkZXIgdG8gZGlzdHJ1c3QgYWxsIG9mIHRoZW0uIEFuIGFjdGlvbiB3aXRoCiAgICAgICAgICAgICAgICAjIG5vIHJldmVyc2Ugc3RhdGVt'
    || 'ZW50cyBuZXZlciBzaG93cyBvbmUgYXQgYWxsIC0tIHNheWluZyAibm90CiAgICAgICAgICAgICAgICAjIHJldmVyc2libGUiIHBsYWlubHkgYmVhdHMgb2Zm'
    || 'ZXJpbmcgYSBjb250cm9sIHRoYXQgY2Fubm90IHdvcmsuCiAgICAgICAgICAgICAgICBpZiByLmdldCgiVU5ET19TVEFURU1FTlRTIikgYW5kIHIuZ2V0KCJU'
    || 'SU1FU19SVU4iKToKICAgICAgICAgICAgICAgICAgICBpZiBzdC5idXR0b24oIlVuZG8gIiArIGNvZGUsIGtleT0idW5kb2FybV8iICsgY29kZSwKICAgICAg'
    || 'ICAgICAgICAgICAgICAgICAgICAgICAgICAgZGlzYWJsZWQ9bm90IHRpZXJfZW5hYmxlZCwgdXNlX2NvbnRhaW5lcl93aWR0aD1UcnVlLAogICAgICAgICAg'
    || 'ICAgICAgICAgICAgICAgICAgICAgICBoZWxwPSJSdW5zICIgKyBzdHIoclsiVU5ET19TVEFURU1FTlRTIl0pCiAgICAgICAgICAgICAgICAgICAgICAgICAg'
    || 'ICAgICAgICAgICAgKyAiIHJldmVyc2Ugc3RhdGVtZW50KHMpLiAiICsgc3RyKHIuZ2V0KCJVTkRPIikgb3IgIiIpKToKICAgICAgICAgICAgICAgICAgICAg'
    || 'ICAgc3Quc2Vzc2lvbl9zdGF0ZVsiYXJtZWQiXSA9IGNvZGUKICAgICAgICAgICAgICAgICAgICAgICAgc3Quc2Vzc2lvbl9zdGF0ZVsiYXJtZWRfdW5kbyJd'
    || 'ID0gVHJ1ZQogICAgICAgICAgICAgICAgICAgICAgICBzdC5zZXNzaW9uX3N0YXRlLnBvcCgicmVzdWx0XyIgKyBjb2RlLCBOb25lKQogICAgICAgICAgICAg'
    || 'ICAgZWxpZiByLmdldCgiVElNRVNfUlVOIikgYW5kIG5vdCByLmdldCgiVU5ET19TVEFURU1FTlRTIik6CiAgICAgICAgICAgICAgICAgICAgc3QuY2FwdGlv'
    || 'bigiTm8gYXV0b21hdGljIHVuZG8g4oCUIHNlZSB0aGUgdW5kbyBub3RlIGluIHRoZSB0b29sdGlwLiIpCiAgICAgICAgICAgICAgICBpZiByLmdldCgiVElN'
    || 'RVNfVU5ET05FIik6CiAgICAgICAgICAgICAgICAgICAgc3QuY2FwdGlvbigiVW5kb25lICIgKyBzdHIoclsiVElNRVNfVU5ET05FIl0pICsgIngiKQoKICAg'
    || 'IGFybWVkID0gc3Quc2Vzc2lvbl9zdGF0ZS5nZXQoImFybWVkIikKICAgIHVuZG9pbmcgPSBib29sKHN0LnNlc3Npb25fc3RhdGUuZ2V0KCJhcm1lZF91bmRv'
    || 'IikpCiAgICAjIFJlc29sdmUgdGhlIEFSTUVEIGFjdGlvbidzIG93biB0aWVyLiBEZWxpYmVyYXRlbHkgbm90IGB0aWVyX2VuYWJsZWRgIGZyb20gdGhlCiAg'
    || 'ICAjIGxvb3AgYWJvdmU6IHRoYXQgdmFyaWFibGUgaG9sZHMgd2hpY2hldmVyIHRpZXIgaGFwcGVuZWQgdG8gYmUgcmVuZGVyZWQgbGFzdCwKICAgICMgc28g'
    || 'cmV1c2luZyBpdCBoZXJlIHdvdWxkIGdhdGUgdGhlIGNvbmZpcm1hdGlvbiBvbiBhbiB1bnJlbGF0ZWQgYWN0aW9uLiBEZWZhdWx0CiAgICAjIHRvIHRoZSBz'
    || 'dHJpY3RlciBmbGFnIHdoZW4gdGhlIGNvZGUgY2Fubm90IGJlIGZvdW5kLgogICAgYXJtZWRfdGllciA9ICJQUk9EVUNUSU9OIgogICAgZm9yIHIgaW4gcm93'
    || 'czoKICAgICAgICBpZiBzdHIoci5nZXQoIkNPREUiKSBvciAiIikgPT0gc3RyKGFybWVkIG9yICIiKToKICAgICAgICAgICAgYXJtZWRfdGllciA9IHN0cihy'
    || 'LmdldCgiVElFUiIpIG9yICJQUk9EVUNUSU9OIikudXBwZXIoKQogICAgICAgICAgICBicmVhawogICAgYXJtZWRfZW5hYmxlZCA9IGFsbG93X3NhbXBsZSBp'
    || 'ZiBhcm1lZF90aWVyID09ICJTQU1QTEUiIGVsc2UgYWxsb3dfcmVhbAogICAgaWYgYXJtZWQgYW5kIGFybWVkX2VuYWJsZWQ6CiAgICAgICAgc3QuY2FwdGlv'
    || 'bigoIkNPTkZJUk0gVU5ETyBPRiAiIGlmIHVuZG9pbmcgZWxzZSAiQ09ORklSTSAiKSArIGFybWVkKQogICAgICAgICMgUGFyYW1ldGVycyBhcmUgY2hvc2Vu'
    || 'IEhFUkUsIGJlZm9yZSB0aGUgY29kZSBpcyB0eXBlZCwgYW5kIG9ubHkgZm9yIGEgZm9yd2FyZAogICAgICAgICMgcnVuLiBBbiB1bmRvIHRha2VzIG5vbmUg'
    || 'YnkgZGVzaWduOiBSVU5fQUNUSU9OIHJlc29sdmVkIGFuZCBzbmFwc2hvdHRlZCB0aGUKICAgICAgICAjIHJldmVyc2Ugc3RhdGVtZW50cyB3aGVuIHRoZSBh'
    || 'Y3Rpb24gcmFuLCBzbyBVTkRPX0FDVElPTiByZXBsYXlzIHRoYXQgZXhhY3QKICAgICAgICAjIHRleHQuIE9mZmVyaW5nIHRoZSB2YWx1ZXMgYWdhaW4gd291'
    || 'bGQgaW52aXRlIHJldmVyc2luZyBhIGRpZmZlcmVudCB0YXJnZXQKICAgICAgICAjIHRoYW4gdGhlIG9uZSB0aGF0IHdhcyBjaGFuZ2VkLCB3aGljaCBpcyB3'
    || 'b3JzZSB0aGFuIGhhdmluZyBubyB1bmRvLgogICAgICAgIHB2YWxzLCBwcmVhZHkgPSB7fSwgVHJ1ZQogICAgICAgIGlmIG5vdCB1bmRvaW5nOgogICAgICAg'
    || 'ICAgICBhcGFyYW1zID0gbG9hZF9hY3Rpb25fcGFyYW1zKHNlc3Npb24sIHRndCkuZ2V0KGFybWVkLCBbXSkKICAgICAgICAgICAgaWYgYXBhcmFtczoKICAg'
    || 'ICAgICAgICAgICAgIHN0LmNhcHRpb24oIkNob29zZSB3aGF0IGl0IHJ1bnMgYWdhaW5zdC4gVGhlc2UgYXJlIHRoZSBvbmx5IHZhbHVlcyB0aGlzICIKICAg'
    || 'ICAgICAgICAgICAgICAgICAgICAgICAgImJ1aWxkIGRpc2NvdmVyZWQgZm9yIGl0LCBhbmQgdGhlIHByb2NlZHVyZSByZS1jaGVja3MgeW91ciAiCiAgICAg'
    || 'ICAgICAgICAgICAgICAgICAgICAgICJjaG9pY2UgYWdhaW5zdCB0aGF0IHNhbWUgbGlzdCBiZWZvcmUgaXQgcnVucyBhbnl0aGluZy4iKQogICAgICAgICAg'
    || 'ICAgICAgcHZhbHMsIHByZWFkeSA9IGFjdGlvbl9wYXJhbV92YWx1ZXMoc2Vzc2lvbiwgYXJtZWQsIGFwYXJhbXMpCiAgICAgICAgc3QuY2FwdGlvbigiVHlw'
    || 'ZSB0aGUgYWN0aW9uIGNvZGUgZXhhY3RseS4gVGhpcyBpcyB0aGUgbGFzdCBzdGVwIGJlZm9yZSBpdCBydW5zLiIKICAgICAgICAgICAgICAgICAgICsgKCIg'
    || 'VGhpcyBSRVZFUlNFUyB0aGUgYWN0aW9uOyByZXZlcnNpbmcgYSBtYXNraW5nIHBvbGljeSBleHBvc2VzICIKICAgICAgICAgICAgICAgICAgICAgICJ0aGUg'
    || 'Y29sdW1uIGFnYWluLCBzbyBpdCBpcyBhIGNoYW5nZSBsaWtlIGFueSBvdGhlci4iCiAgICAgICAgICAgICAgICAgICAgICBpZiB1bmRvaW5nIGVsc2UgIiIp'
    || 'KQogICAgICAgIHR5cGVkID0gc3QudGV4dF9pbnB1dCgiQ29uZmlybWF0aW9uIiwga2V5PSJjb25maXJtXyIgKyBhcm1lZCwKICAgICAgICAgICAgICAgICAg'
    || 'ICAgICAgICAgICAgbGFiZWxfdmlzaWJpbGl0eT0iY29sbGFwc2VkIiwgcGxhY2Vob2xkZXI9YXJtZWQpCiAgICAgICAgYzEsIGMyID0gc3QuY29sdW1ucyhb'
    || 'MSwgNF0pCiAgICAgICAgd2l0aCBjMToKICAgICAgICAgICAgIyBEaXNhYmxlZCB1bnRpbCBldmVyeSBwYXJhbWV0ZXIgaGFzIGEgdmFsdWUuIFRoZSBwcm9j'
    || 'ZWR1cmUgcmVmdXNlcyBhCiAgICAgICAgICAgICMgbWlzc2luZyBvbmUgYW55d2F5IC0tIHRoaXMgb25seSBhdm9pZHMgdGVhY2hpbmcgdGhlIHJlYWRlciB0'
    || 'aGF0IHRoZQogICAgICAgICAgICAjIGJ1dHRvbiBwcm9kdWNlcyByZWZ1c2Fscy4KICAgICAgICAgICAgZ28gPSBzdC5idXR0b24oIlJ1biBpdCIsIGtleT0i'
    || 'Z29fIiArIGFybWVkLCB0eXBlPSJwcmltYXJ5IiwKICAgICAgICAgICAgICAgICAgICAgICAgICAgZGlzYWJsZWQ9bm90IHByZWFkeSkKICAgICAgICB3aXRo'
    || 'IGMyOgogICAgICAgICAgICBpZiBzdC5idXR0b24oIkNhbmNlbCIsIGtleT0iY2FuY2VsXyIgKyBhcm1lZCk6CiAgICAgICAgICAgICAgICBzdC5zZXNzaW9u'
    || 'X3N0YXRlLnBvcCgiYXJtZWQiLCBOb25lKQogICAgICAgICAgICAgICAgc3Quc2Vzc2lvbl9zdGF0ZS5wb3AoImFybWVkX3VuZG8iLCBOb25lKQogICAgICAg'
    || 'ICAgICAgICAgZ28gPSBGYWxzZQogICAgICAgIGlmIGdvOgogICAgICAgICAgICAjIFRoZSB0eXBlZCB2YWx1ZSBpcyBwYXNzZWQgYXMgYSBCSU5ELCBuZXZl'
    || 'ciBjb25jYXRlbmF0ZWQuIEl0IGlzCiAgICAgICAgICAgICMgYXR0YWNrZXItY29udHJvbGxlZCB0ZXh0IGdvaW5nIGludG8gYSBwcm9jZWR1cmUgY2FsbCwg'
    || 'YW5kIHRoZQogICAgICAgICAgICAjIHByb2NlZHVyZSBjb21wYXJlcyBpdCB0byB0aGUgY29kZSByYXRoZXIgdGhhbiBleGVjdXRpbmcgaXQgLS0gYnV0CiAg'
    || 'ICAgICAgICAgICMgYmluZGluZyBpcyB3aGF0IG1ha2VzIHRoYXQgdHJ1ZSByZWdhcmRsZXNzIG9mIHdoYXQgd2FzIHR5cGVkLgogICAgICAgICAgICAjCiAg'
    || 'ICAgICAgICAgICMgVGhlIHBhcmFtZXRlciB2YWx1ZXMgYXJlIGJvdW5kIHRvbywgYXMgb25lIEpTT04gc3RyaW5nLiBUaGV5IGNhbm5vdCBiZQogICAgICAg'
    || 'ICAgICAjIGJvdW5kIGFzIGFuIE9CSkVDVCAtLSBhbmQgSlNPTiB0ZXh0IGlzIHdoYXQgVU5ET19TTkFQU0hPVCBhbHJlYWR5IHVzZXMsCiAgICAgICAgICAg'
    || 'ICMgZm9yIHRoZSBkb2N1bWVudGVkIHJlYXNvbiB0aGF0IGFuIEFSUkFZIGJpbmQgaXMgZnJhZ2lsZSB3aGlsZQogICAgICAgICAgICAjIFRPX0pTT04vUEFS'
    || 'U0VfSlNPTiByb3VuZC10cmlwcyBleGFjdGx5LiBCaW5kaW5nIGlzIG5vdCB3aGF0IG1ha2VzIHRoZW0KICAgICAgICAgICAgIyBzYWZlOiB0aGUgcHJvY2Vk'
    || 'dXJlIHZhbGlkYXRlcyBldmVyeSB2YWx1ZSBhZ2FpbnN0IHRoZSByZWdpc3RyeSdzIG93bgogICAgICAgICAgICAjIGFsbG93ZWQgbGlzdCBiZWZvcmUgaW50'
    || 'ZXJwb2xhdGluZyBhbnkgb2YgdGhlbS4gQmluZGluZyBqdXN0IG1lYW5zIHRoZQogICAgICAgICAgICAjIGNhbGwgaXRzZWxmIGNhbm5vdCBiZSBicm9rZW4g'
    || 'Ynkgd2hhdCB3YXMgY2hvc2VuLgogICAgICAgICAgICAjCiAgICAgICAgICAgICMgQW4gYWN0aW9uIHdpdGggbm8gcGFyYW1ldGVycyB0YWtlcyB0aGUgVFdP'
    || 'LUFSR1VNRU5UIHBhdGgsIHVuY2hhbmdlZCwgc28KICAgICAgICAgICAgIyBldmVyeSBleGlzdGluZyBzb2x1dGlvbiBjYWxscyBleGFjdGx5IHdoYXQgaXQg'
    || 'Y2FsbGVkIGJlZm9yZS4KICAgICAgICAgICAgaWYgcHZhbHM6CiAgICAgICAgICAgICAgICBwcm9jID0gIi5SVU5fQUNUSU9OKD8sID8sID8pIgogICAgICAg'
    || 'ICAgICAgICAgYXJncyA9IFthcm1lZCwgdHlwZWQsIGpzb24uZHVtcHMocHZhbHMpXQogICAgICAgICAgICBlbHNlOgogICAgICAgICAgICAgICAgcHJvYyA9'
    || 'ICIuVU5ET19BQ1RJT04oPywgPykiIGlmIHVuZG9pbmcgZWxzZSAiLlJVTl9BQ1RJT04oPywgPykiCiAgICAgICAgICAgICAgICBhcmdzID0gW2FybWVkLCB0'
    || 'eXBlZF0KICAgICAgICAgICAgdHJ5OgogICAgICAgICAgICAgICAgb3V0ID0gc2Vzc2lvbi5zcWwoIkNBTEwgIiArIHRndCArIHByb2MsCiAgICAgICAgICAg'
    || 'ICAgICAgICAgICAgICAgICAgICAgICBwYXJhbXM9YXJncykuY29sbGVjdCgpWzBdWzBdCiAgICAgICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZXhjOgog'
    || 'ICAgICAgICAgICAgICAgb3V0ID0gIkZBSUxFRCB0byBjYWxsICIgKyBwcm9jLnNwbGl0KCIoIilbMF0uc3RyaXAoIi4iKSArICI6ICIgKyBzdHIoZXhjKQog'
    || 'ICAgICAgICAgICBzdC5zZXNzaW9uX3N0YXRlWyJyZXN1bHRfIiArIGFybWVkXSA9IHN0cihvdXQpCiAgICAgICAgICAgIHN0LnNlc3Npb25fc3RhdGUucG9w'
    || 'KCJhcm1lZCIsIE5vbmUpCiAgICAgICAgICAgIHN0LnNlc3Npb25fc3RhdGUucG9wKCJhcm1lZF91bmRvIiwgTm9uZSkKICAgICAgICAgICAgaW52YWxpZGF0'
    || 'ZV9wYW5lbF9jYWNoZSgpCiAgICAgICAgICAgIHN0LnJlcnVuKCkKCiAgICBmb3IgayBpbiBbayBmb3IgayBpbiBzdC5zZXNzaW9uX3N0YXRlIGlmIHN0cihr'
    || 'KS5zdGFydHN3aXRoKCJyZXN1bHRfIildOgogICAgICAgIG1zZyA9IHN0cihzdC5zZXNzaW9uX3N0YXRlW2tdKQogICAgICAgIGlmIG1zZy5zdGFydHN3aXRo'
    || 'KCJET05FIikgb3IgbXNnLnN0YXJ0c3dpdGgoIlVORE9ORSIpOgogICAgICAgICAgICBzdC5zdWNjZXNzKG1zZywgaWNvbj0iOm1hdGVyaWFsL2NoZWNrOiIp'
    || 'CiAgICAgICAgZWxpZiBtc2cuc3RhcnRzd2l0aCgiUEFSVElBTExZIFVORE9ORSIpOgogICAgICAgICAgICAjIE5vdCBhbiBlcnJvciBhbmQgbm90IGEgc3Vj'
    || 'Y2Vzczogc29tZSBvZiB0aGUgYWNjb3VudCBjYW1lIGJhY2sgYW5kIHNvbWUKICAgICAgICAgICAgIyBkaWQgbm90LCBhbmQgdGhlIHJlYWRlciBoYXMgdG8g'
    || 'a25vdyB3aGljaCB3aXRob3V0IGd1ZXNzaW5nLgogICAgICAgICAgICBzdC53YXJuaW5nKG1zZywgaWNvbj0iOm1hdGVyaWFsL3dhcm5pbmc6IikKICAgICAg'
    || 'ICBlbGlmIG1zZy5zdGFydHN3aXRoKCJSRUZVU0VEIik6CiAgICAgICAgICAgIHN0Lndhcm5pbmcobXNnLCBpY29uPSI6bWF0ZXJpYWwvYmxvY2s6IikKICAg'
    || 'ICAgICBlbHNlOgogICAgICAgICAgICBzdC5lcnJvcihtc2csIGljb249IjptYXRlcmlhbC9lcnJvcjoiKQogICAgc3QuZGl2aWRlcigpCgoKZGVmIGxvYWRf'
    || 'YWdlbnQoc2Vzc2lvbiwgdGd0OiBzdHIpOgogICAgIiIiVGhlIGRlY2xhcmVkIGFnZW50LCBvciBOb25lLgoKICAgIEdhdGVzIG9uIHdoZXRoZXIgdGhlIHNv'
    || 'bHV0aW9uIGJ1aWx0IFZfQUdFTlRfQ0hBVCwgZXhhY3RseSBhcyBsb2FkX2FjdGlvbnMgZ2F0ZXMKICAgIG9uIFZfQUNUSU9OUyBhbmQgbG9hZF9ydWxlX2Nv'
    || 'bmZpZyBvbiBWX1JVTEVfQ09ORklHLiBTaXggc29sdXRpb25zIGFscmVhZHkgYnVpbGQKICAgIGFuIGFnZW50IHByb2NlZHVyZSB0aGF0IG5vdGhpbmcgY291'
    || 'bGQgcmVhY2ggLS0gQVNLX0dPVkVSTkFOQ0UsCiAgICBESUFHTk9TRV9GQUlMVVJFLCBFWFBMQUlOX1BSSVZBQ1lfQkxPQ0ssIEFTU0VTU19NSUdSQVRJT04g'
    || 'YW5kIGZyaWVuZHMgd2VyZQogICAgY2FsbGFibGUgb25seSBmcm9tIGEgd29ya3NoZWV0LiBEZWNsYXJpbmcgb25lIHZpZXcgbm93IHN1cmZhY2VzIGl0LgoK'
    || 'ICAgIEEgc29sdXRpb24gd2hvc2UgYWdlbnQgZGVwZW5kcyBvbiBDb3J0ZXggYmVpbmcgYXZhaWxhYmxlIG11c3QgY3JlYXRlIHRoaXMgdmlldwogICAgaW5z'
    || 'aWRlIHRoZSBzYW1lIGF2YWlsYWJpbGl0eSBjaGVjayB0aGF0IGNyZWF0ZXMgdGhlIHByb2NlZHVyZSwgc28gdGhhdCB0aGUgY2hhdAogICAgbmV2ZXIgYXBw'
    || 'ZWFycyBmb3IgYSBidWlsZCB3aGVyZSB0aGUgbW9kZWwgd2FzIHVucmVhY2hhYmxlLgogICAgIiIiCiAgICB0cnk6CiAgICAgICAgcm93cyA9IFtyLmFzX2Rp'
    || 'Y3QoKSBmb3IgciBpbiBzZXNzaW9uLnNxbCgKICAgICAgICAgICAgIlNFTEVDVCBBR0VOVF9MQUJFTCwgUFJPQ19OQU1FLCBQTEFDRUhPTERFUiwgQkxVUkIg'
    || 'IgogICAgICAgICAgICAiRlJPTSAiICsgdGd0ICsgIi5WX0FHRU5UX0NIQVQiKS5jb2xsZWN0KCldCiAgICBleGNlcHQgRXhjZXB0aW9uOgogICAgICAgIHJl'
    || 'dHVybiBOb25lCiAgICBpZiBub3Qgcm93czoKICAgICAgICByZXR1cm4gTm9uZQogICAgYSA9IHJvd3NbMF0KICAgICMgVGhlIHByb2NlZHVyZSBOQU1FIGNh'
    || 'bm5vdCBiZSBhIGJpbmQgLS0gaXQgaXMgYW4gaWRlbnRpZmllciwgc28gaXQgaGFzIHRvIGJlCiAgICAjIGNvbmNhdGVuYXRlZCBpbnRvIHRoZSBDQUxMLiBJ'
    || 'dCBjb21lcyBmcm9tIGEgdmlldyB0aGlzIGJ1aWxkIGNyZWF0ZWQgcmF0aGVyCiAgICAjIHRoYW4gZnJvbSBhbnl0aGluZyBhIHJlYWRlciB0eXBlZCwgYnV0'
    || 'IGl0IGlzIHZhbGlkYXRlZCBhbnl3YXk6IGEgdmlldyBpcyBhCiAgICAjIHRoaW5nIHNvbWVvbmUgY2FuIGxhdGVyIEFMVEVSLCBhbmQgdGhlIGNvc3Qgb2Yg'
    || 'YmVpbmcgd3JvbmcgaGVyZSBpcyBhcmJpdHJhcnkKICAgICMgU1FMIHJ1bm5pbmcgYXMgdGhlIGFwcCBvd25lci4gVGhlIHF1ZXN0aW9uIGl0c2VsZiBJUyBi'
    || 'b3VuZC4KICAgIHByb2MgPSBzdHIoYS5nZXQoIlBST0NfTkFNRSIpIG9yICIiKQogICAgaWYgbm90IHJlLmZ1bGxtYXRjaChyIltBLVphLXpfXVtBLVphLXow'
    || 'LTlfXSoiLCBwcm9jKToKICAgICAgICByZXR1cm4gTm9uZQogICAgYVsiUFJPQ19OQU1FIl0gPSBwcm9jCiAgICByZXR1cm4gYQoKCmRlZiBhZ2VudF9iYXIo'
    || 'c2Vzc2lvbiwgdGd0OiBzdHIpIC0+IE5vbmU6CiAgICAiIiJBc2sgdGhlIHNvbHV0aW9uJ3Mgb3duIGFnZW50IGEgcXVlc3Rpb24sIGluIHRoZSBhcHAuCgog'
    || 'ICAgQkVUV0VFTiB0aGUgcnVsZXMgYW5kIHRoZSBhY3Rpb25zLCB3aGljaCBpcyB0aGUgcmVhZGluZyBvcmRlciB0aGUgcGFnZSBhbHJlYWR5CiAgICBhcmd1'
    || 'ZXMgZm9yOiB0aGUgZGFzaGJvYXJkIHNheXMgd2hhdCBpcyB0cnVlLCBjb25maWdfYmFyIHR1bmVzIGhvdyBpdCB3YXMKICAgIGRlY2lkZWQsIHRoaXMgZXhw'
    || 'bGFpbnMgaXQgaW4gd29yZHMsIGFuZCBwcm9tb3Rpb25fYmFyIGFjdHMgb24gaXQuIEFuIGFuc3dlciBpcwogICAgbW9zdCB1c2VmdWwgaW1tZWRpYXRlbHkg'
    || 'YmVmb3JlIHRoZSBkZWNpc2lvbiBpdCBpbmZvcm1zLgoKICAgIHN0LmNoYXRfaW5wdXQgcmF0aGVyIHRoYW4gYSBSZWFjdCBjaGF0IGJveCBmb3IgdGhlIHVz'
    || 'dWFsIHJlYXNvbiAtLSB0aGUgYnVuZGxlCiAgICBydW5zIGluIGEgc2FuZGJveGVkIGlmcmFtZSB3aXRoIG5vIHNlc3Npb24gYW5kIGNhbm5vdCBjYWxsIGEg'
    || 'cHJvY2VkdXJlLgoKICAgIEhJU1RPUlkgSVMgUEVSIFNFU1NJT04gQU5EIE5PVCBQRVJTSVNURUQuIE5vdGhpbmcgaGVyZSB3cml0ZXMgdG8gdGhlIGFjY291'
    || 'bnQ6CiAgICBhIHF1ZXN0aW9uIGNvc3RzIGEgc21hbGwgYW1vdW50IG9mIENvcnRleCBjcmVkaXQgYW5kIHJldHVybnMgYSBzdHJpbmcuIFRoYXQgaXMKICAg'
    || 'IGFsc28gd2h5IHRoaXMgaXMgbm90IHRpZXItZ2F0ZWQgdGhlIHdheSBhbiBhY3Rpb24gaXMgLS0gdGhlcmUgaXMgbm90aGluZyB0bwogICAgdW5kbyAtLSBi'
    || 'dXQgdGhlIGNvc3QgaXMgc3RhdGVkIHJhdGhlciB0aGFuIGxlZnQgYXMgYSBzdXJwcmlzZS4KICAgICIiIgogICAgYSA9IGxvYWRfYWdlbnQoc2Vzc2lvbiwg'
    || 'dGd0KQogICAgaWYgbm90IGE6CiAgICAgICAgcmV0dXJuCgogICAgc3QuY2FwdGlvbihzdHIoYS5nZXQoIkFHRU5UX0xBQkVMIikgb3IgIkFTSyBUSEUgQUdF'
    || 'TlQiKS51cHBlcigpKQogICAgYmx1cmIgPSBzdHIoYS5nZXQoIkJMVVJCIikgb3IgIiIpCiAgICBpZiBibHVyYjoKICAgICAgICBzdC5jYXB0aW9uKGJsdXJi'
    || 'ICsgIiBFYWNoIHF1ZXN0aW9uIGNhbGxzIGEgQ29ydGV4IG1vZGVsLCBzbyBpdCBjb3N0cyBhICIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICJzbWFs'
    || 'bCBhbW91bnQgb2YgY3JlZGl0IGFuZCB0YWtlcyBhIGZldyBzZWNvbmRzLiIpCgogICAgaGlzdF9rZXkgPSAiYWdlbnRfaGlzdCIKICAgIGlmIGhpc3Rfa2V5'
    || 'IG5vdCBpbiBzdC5zZXNzaW9uX3N0YXRlOgogICAgICAgIHN0LnNlc3Npb25fc3RhdGVbaGlzdF9rZXldID0gW10KCiAgICBmb3IgcSwgYW5zIGluIHN0LnNl'
    || 'c3Npb25fc3RhdGVbaGlzdF9rZXldOgogICAgICAgIHdpdGggc3QuY2hhdF9tZXNzYWdlKCJ1c2VyIik6CiAgICAgICAgICAgIHN0LndyaXRlKHEpCiAgICAg'
    || 'ICAgd2l0aCBzdC5jaGF0X21lc3NhZ2UoImFzc2lzdGFudCIpOgogICAgICAgICAgICBzdC53cml0ZShhbnMpCgogICAgYXNrZWQgPSBzdC5jaGF0X2lucHV0'
    || 'KHN0cihhLmdldCgiUExBQ0VIT0xERVIiKSBvciAiQXNrIGEgcXVlc3Rpb24iKSwKICAgICAgICAgICAgICAgICAgICAgICAgICBrZXk9ImFnZW50X3EiKQog'
    || 'ICAgaWYgYXNrZWQ6CiAgICAgICAgd2l0aCBzdC5zcGlubmVyKCJBc2tpbmcgdGhlIGFnZW50Li4uIik6CiAgICAgICAgICAgIHRyeToKICAgICAgICAgICAg'
    || 'ICAgICMgVGhlIHF1ZXN0aW9uIGlzIEJPVU5ELiBDb25jYXRlbmF0aW5nIGl0IHdvdWxkIGxldCB3aGF0ZXZlcgogICAgICAgICAgICAgICAgIyBzb21lYm9k'
    || 'eSB0eXBlcyBlbmQgdXAgYXMgU1FMIHJ1bm5pbmcgd2l0aCB0aGUgYXBwIG93bmVyJ3MgcmlnaHRzLgogICAgICAgICAgICAgICAgb3V0ID0gc2Vzc2lvbi5z'
    || 'cWwoCiAgICAgICAgICAgICAgICAgICAgIkNBTEwgIiArIHRndCArICIuIiArIGFbIlBST0NfTkFNRSJdICsgIig/KSIsCiAgICAgICAgICAgICAgICAgICAg'
    || 'cGFyYW1zPVthc2tlZF0pLmNvbGxlY3QoKVswXVswXQogICAgICAgICAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGV4YzoKICAgICAgICAgICAgICAgICMgUmVw'
    || 'b3J0IHRoZSBmYWlsdXJlIGFzIHRoZSBhbnN3ZXIgcmF0aGVyIHRoYW4gc3dhbGxvd2luZyBpdC4gQQogICAgICAgICAgICAgICAgIyBjaGF0IHRoYXQgc2ls'
    || 'ZW50bHkgcmV0dXJucyBub3RoaW5nIHJlYWRzIGFzICJ0aGUgYWdlbnQgaGFkIG5vCiAgICAgICAgICAgICAgICAjIG9waW5pb24iLCB3aGljaCBpcyBhIGNs'
    || 'YWltIGFib3V0IHRoZSBxdWVzdGlvbiByYXRoZXIgdGhhbiBhYm91dAogICAgICAgICAgICAgICAgIyB0aGUgY2FsbCB0aGF0IGZhaWxlZC4KICAgICAgICAg'
    || 'ICAgICAgIG91dCA9ICgiVGhlIGFnZW50IGNvdWxkIG5vdCBhbnN3ZXI6ICIgKyB0eXBlKGV4YykuX19uYW1lX18gKyAiOiAiCiAgICAgICAgICAgICAgICAg'
    || 'ICAgICAgKyBzdHIoZXhjKVs6MzAwXSkKICAgICAgICBzdC5zZXNzaW9uX3N0YXRlW2hpc3Rfa2V5XS5hcHBlbmQoKGFza2VkLCBzdHIob3V0KSkpCiAgICAg'
    || 'ICAgc3QucmVydW4oKQogICAgc3QuZGl2aWRlcigpCgoKZGVmIGNvbnRyb2xfdmFsdWVzKHNlc3Npb24sIHRndDogc3RyKSAtPiBkaWN0OgogICAgIiIiUmVu'
    || 'ZGVyIHRoZSBkZWNsYXJlZCBjb250cm9scyBhbmQgcmV0dXJuIHtuYW1lOiBjdXJyZW50IHZhbHVlfS4KCiAgICBBQk9WRSBUSEUgREFTSEJPQVJELCB1bmxp'
    || 'a2UgY29uZmlnX2JhciBhbmQgcHJvbW90aW9uX2JhciwgYW5kIHRoZSBkaWZmZXJlbmNlIGlzCiAgICB0aGUgcG9pbnQuIFRoZXNlIGNvbnRyb2xzIGRlY2lk'
    || 'ZSBXSEFUIFRIRSBQQUdFIElTIEFCT1VUIC0tIHdoaWNoIG1ldHJvLCB3aGljaAogICAgd2luZG93LCB3aGljaCBtaW5pbXVtIHNjb3JlIC0tIHNvIHRoZXkg'
    || 'YmVsb25nIHdoZXJlIHlvdSB3b3VsZCBsb29rIGJlZm9yZQogICAgcmVhZGluZy4gY29uZmlnX2JhciB0dW5lcyB0aGUgcnVsZXMgYmVoaW5kIHRoZSBudW1i'
    || 'ZXJzIGFuZCBwcm9tb3Rpb25fYmFyIGFjdHMgb24KICAgIHRoZW0sIHdoaWNoIGlzIHdoeSBib3RoIG9mIHRob3NlIHNpdCB1bmRlcm5lYXRoLgoKICAgIFdp'
    || 'ZGdldHMsIG5vdCBSZWFjdCwgZm9yIHRoZSBzYW1lIHBoeXNpY2FsIHJlYXNvbiBldmVyeXRoaW5nIGVsc2UgaGVyZSBpczogdGhlCiAgICBidW5kbGUgcnVu'
    || 'cyBpbiBhIHNhbmRib3hlZCBpZnJhbWUgd2l0aCBubyBzZXNzaW9uLCBzbyBhIFJlYWN0IHNlbGVjdGJveCBjYW5ub3QKICAgIHJlLXF1ZXJ5LiBUaGlzIGlz'
    || 'IHdoZXJlIHRoZSBjaG9vc2luZyBoYXBwZW5zOyB0aGUgcGFnZSBiZWxvdyByZS1yZW5kZXJzIGZyb20gYQogICAgcGF5bG9hZCB0aGUgaG9zdCBmZXRjaGVz'
    || 'IGFnYWluIG9uIHRoZSByZXN1bHRpbmcgcmVydW4uCgogICAgU29sdXRpb25zIHRoYXQgZGVjbGFyZSBubyBjb250cm9scyBkcmF3IE5PVEhJTkcgLS0gbm8g'
    || 'aGVhZGVyLCBubyBleHBhbmRlciwgbm8KICAgIGVtcHR5IHJvdy4gU2FtZSBhcmd1bWVudCBhcyBsb2FkX3J1bGVfY29uZmlnIGdhdGluZyBvbiBWX1JVTEVf'
    || 'Q09ORklHOiBhIHNvbHV0aW9uCiAgICB0aGF0IG5ldmVyIG9wdGVkIGluIG11c3Qgbm90IGdyb3cgYSBjb250cm9sIHN1cmZhY2UgYnkgYWNjaWRlbnQuCgog'
    || 'ICAgQSBmYWlsZWQgb3B0aW9ucyBxdWVyeSBjb3N0cyB0aGF0IE9ORSBjb250cm9sIGl0cyBsaXN0IGFuZCBub3RoaW5nIGVsc2UsIGFuZCBpdAogICAgc2F5'
    || 'cyBzby4gRmFsbGluZyBiYWNrIHRvIGEgc2lsZW50IGVtcHR5IHNlbGVjdGJveCB3b3VsZCByZWFkIGFzICJ0aGVyZSBhcmUgbm8KICAgIG1ldHJvcyIsIGEg'
    || 'Y2xhaW0gYWJvdXQgdGhlIGN1c3RvbWVyJ3MgZGF0YSByYXRoZXIgdGhhbiBhYm91dCBvdXIgcXVlcnkuCiAgICAiIiIKICAgIGlmIG5vdCBDT05UUk9MUzoK'
    || 'ICAgICAgICByZXR1cm4ge30KICAgIHBhcmFtcyA9IHt9CiAgICBjb2xzID0gc3QuY29sdW1ucyhtaW4obGVuKENPTlRST0xTKSwgNCkpCiAgICBmb3IgaSwg'
    || 'c3BlYyBpbiBlbnVtZXJhdGUoQ09OVFJPTFMpOgogICAgICAgIGtleSA9IHN0cihzcGVjLmdldCgia2V5Iikgb3IgIiIpCiAgICAgICAgaWYgbm90IGtleToK'
    || 'ICAgICAgICAgICAgY29udGludWUKICAgICAgICBsYWJlbCA9IHN0cihzcGVjLmdldCgibGFiZWwiKSBvciBrZXkpCiAgICAgICAga2luZCA9IHN0cihzcGVj'
    || 'LmdldCgia2luZCIpIG9yICJ0ZXh0IikubG93ZXIoKQogICAgICAgIGRlZmF1bHQgPSBzcGVjLmdldCgiZGVmYXVsdCIpCiAgICAgICAgaGVscF90eHQgPSBz'
    || 'cGVjLmdldCgiaGVscCIpIG9yIE5vbmUKICAgICAgICB3a2V5ID0gImN0bF8iICsga2V5CiAgICAgICAgd2l0aCBjb2xzW2kgJSBsZW4oY29scyldOgogICAg'
    || 'ICAgICAgICBpZiBraW5kID09ICJzZWxlY3QiOgogICAgICAgICAgICAgICAgb3B0aW9ucyA9IHNwZWMuZ2V0KCJvcHRpb25zIikKICAgICAgICAgICAgICAg'
    || 'IGlmIG5vdCBvcHRpb25zIGFuZCBzcGVjLmdldCgib3B0aW9uc19zcWwiKToKICAgICAgICAgICAgICAgICAgICB0cnk6CiAgICAgICAgICAgICAgICAgICAg'
    || 'ICAgIG9wdGlvbnMgPSBbCiAgICAgICAgICAgICAgICAgICAgICAgICAgICByWzBdIGZvciByIGluIHNlc3Npb24uc3FsKAogICAgICAgICAgICAgICAgICAg'
    || 'ICAgICAgICAgICAgIHN0cihzcGVjWyJvcHRpb25zX3NxbCJdKS5yZXBsYWNlKCJ7dGd0fSIsIHRndCkKICAgICAgICAgICAgICAgICAgICAgICAgICAgICku'
    || 'bGltaXQoMTAwMCkuY29sbGVjdCgpXQogICAgICAgICAgICAgICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZXhjOgogICAgICAgICAgICAgICAgICAgICAg'
    || 'ICBzdC5jYXB0aW9uKGxhYmVsICsgIiBcdTAwYjcgY291bGQgbm90IGxvYWQgY2hvaWNlczogIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg'
    || 'ICsgdHlwZShleGMpLl9fbmFtZV9fKQogICAgICAgICAgICAgICAgICAgICAgICBvcHRpb25zID0gW10KICAgICAgICAgICAgICAgIG9wdGlvbnMgPSBbbyBm'
    || 'b3IgbyBpbiAob3B0aW9ucyBvciBbXSkgaWYgbyBpcyBub3QgTm9uZV0KICAgICAgICAgICAgICAgIGlmIG5vdCBvcHRpb25zOgogICAgICAgICAgICAgICAg'
    || 'ICAgICMgTm90aGluZyB0byBjaG9vc2UgZnJvbSBpcyBub3QgdGhlIHNhbWUgYXMgYW4gZW1wdHkgY2hvaWNlLgogICAgICAgICAgICAgICAgICAgICMgQmlu'
    || 'ZCB0aGUgZGVmYXVsdCBzbyB0aGUgcGFuZWwgc3RpbGwgcnVucyBhbmQgc3RpbGwgc2F5cyB3aGF0CiAgICAgICAgICAgICAgICAgICAgIyBpdCByYW4gd2l0'
    || 'aC4KICAgICAgICAgICAgICAgICAgICBwYXJhbXNba2V5XSA9IGRlZmF1bHQKICAgICAgICAgICAgICAgICAgICBzdC5jYXB0aW9uKGxhYmVsICsgIiBcdTAw'
    || 'Yjcgbm8gY2hvaWNlcyBhdmFpbGFibGUiKQogICAgICAgICAgICAgICAgICAgIGNvbnRpbnVlCiAgICAgICAgICAgICAgICBpZHggPSBvcHRpb25zLmluZGV4'
    || 'KGRlZmF1bHQpIGlmIGRlZmF1bHQgaW4gb3B0aW9ucyBlbHNlIDAKICAgICAgICAgICAgICAgIHBhcmFtc1trZXldID0gc3Quc2VsZWN0Ym94KGxhYmVsLCBv'
    || 'cHRpb25zLCBpbmRleD1pZHgsIGtleT13a2V5LAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgaGVscD1oZWxwX3R4dCkKICAg'
    || 'ICAgICAgICAgZWxpZiBraW5kID09ICJzbGlkZXIiOgogICAgICAgICAgICAgICAgbG8gPSBzcGVjLmdldCgibWluIiwgMCkKICAgICAgICAgICAgICAgIGhp'
    || 'ID0gc3BlYy5nZXQoIm1heCIsIDEwMCkKICAgICAgICAgICAgICAgIHBhcmFtc1trZXldID0gc3Quc2xpZGVyKAogICAgICAgICAgICAgICAgICAgIGxhYmVs'
    || 'LCBtaW5fdmFsdWU9bG8sIG1heF92YWx1ZT1oaSwKICAgICAgICAgICAgICAgICAgICB2YWx1ZT1kZWZhdWx0IGlmIGRlZmF1bHQgaXMgbm90IE5vbmUgZWxz'
    || 'ZSBsbywKICAgICAgICAgICAgICAgICAgICBzdGVwPXNwZWMuZ2V0KCJzdGVwIiwgMSksIGtleT13a2V5LCBoZWxwPWhlbHBfdHh0KQogICAgICAgICAgICBl'
    || 'bGlmIGtpbmQgPT0gIm51bWJlciI6CiAgICAgICAgICAgICAgICBwYXJhbXNba2V5XSA9IHN0Lm51bWJlcl9pbnB1dCgKICAgICAgICAgICAgICAgICAgICBs'
    || 'YWJlbCwgdmFsdWU9ZGVmYXVsdCBpZiBkZWZhdWx0IGlzIG5vdCBOb25lIGVsc2UgMCwKICAgICAgICAgICAgICAgICAgICBtaW5fdmFsdWU9c3BlYy5nZXQo'
    || 'Im1pbiIpLCBtYXhfdmFsdWU9c3BlYy5nZXQoIm1heCIpLAogICAgICAgICAgICAgICAgICAgIHN0ZXA9c3BlYy5nZXQoInN0ZXAiLCAxKSwga2V5PXdrZXks'
    || 'IGhlbHA9aGVscF90eHQpCiAgICAgICAgICAgIGVsc2U6CiAgICAgICAgICAgICAgICBwYXJhbXNba2V5XSA9IHN0LnRleHRfaW5wdXQoCiAgICAgICAgICAg'
    || 'ICAgICAgICAgbGFiZWwsIHZhbHVlPSIiIGlmIGRlZmF1bHQgaXMgTm9uZSBlbHNlIHN0cihkZWZhdWx0KSwKICAgICAgICAgICAgICAgICAgICBrZXk9d2tl'
    || 'eSwgaGVscD1oZWxwX3R4dCkKICAgIHJldHVybiBwYXJhbXMKCgpkZWYgbWFpbigpIC0+IE5vbmU6CiAgICB0cnk6CiAgICAgICAgc2Vzc2lvbiA9IGdldF9h'
    || 'Y3RpdmVfc2Vzc2lvbigpCiAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGV4YzoKICAgICAgICAjIE5vIHNlc3Npb24gbWVhbnMgdGhlIGFwcCBjYW5ub3QgcXVl'
    || 'cnkgYW55dGhpbmcuIFNheSB0aGF0IHBsYWlubHkKICAgICAgICAjIGluc3RlYWQgb2YgcmVuZGVyaW5nIGVtcHR5IHBhbmVscyB0aGF0IGxvb2sgbGlrZSBy'
    || 'ZWFsIHplcm9lcy4KICAgICAgICBjb21wb25lbnRzLmh0bWwoYnVpbGRfaHRtbCh7ImNvbnRleHQiOiB7fSwgInBhbmVscyI6IHt9LAogICAgICAgICAgICAg'
    || 'ICAgICAgICAgICAgICAgICAgICAgICAiZmF0YWwiOiAiTm8gYWN0aXZlIFNub3dmbGFrZSBzZXNzaW9uOiAiICsgc3RyKGV4Yyl9KSwKICAgICAgICAgICAg'
    || 'ICAgICAgICAgICAgaGVpZ2h0PTQwMCwgc2Nyb2xsaW5nPUZhbHNlKQogICAgICAgIHJldHVybgoKICAgIHRndCA9IHRhcmdldF9zY2hlbWEoc2Vzc2lvbikK'
    || 'ICAgIG5hdmlnYXRpb24gPSBhcHBfbmF2aWdhdGlvbihzZXNzaW9uLCB0Z3QpCiAgICAjIEJFRk9SRSBydW5fcGFuZWxzLCBiZWNhdXNlIHRoZWlyIHZhbHVl'
    || 'cyBhcmUgd2hhdCB0aGUgcGFuZWxzIGFyZSBmaWx0ZXJlZCBieS4KICAgIHBhcmFtcyA9IGNvbnRyb2xfdmFsdWVzKHNlc3Npb24sIHRndCkKICAgIHBhbmVs'
    || 'cyA9IHJ1bl9wYW5lbHMoc2Vzc2lvbiwgdGd0LCBwYXJhbXMpCiAgICBjdXN0b21pemF0aW9uLCBjdXN0b21fcGFuZWxzLCBjdXN0b21pemF0aW9uX2Vycm9y'
    || 'ID0gbG9hZF9jdXN0b21pemF0aW9uKHNlc3Npb24sIHRndCkKICAgIHBhbmVscy51cGRhdGUoY3VzdG9tX3BhbmVscykKICAgICMgVGhlIHNoZWxsJ3MgTU9E'
    || 'RSBiYW5uZXIgYW5kIGJ1aWxkIHByb3ZlbmFuY2UgY29tZSBmcm9tIHRoZSBgY29udGV4dGAgcGFuZWwuCiAgICAjIElmIGl0IGZhaWxlZCwgc2F5IHNvIHRo'
    || 'cm91Z2ggdGhlIG5vcm1hbCBjb250ZXh0IGZpZWxkcyByYXRoZXIgdGhhbiBsZWF2aW5nCiAgICAjIE1PREUgYmxhbmsgLS0gYSBwYWdlIHdpdGggbm8gbW9k'
    || 'ZSBiYWRnZSBpcyBhIHBhZ2UgdGhhdCBjb3VsZCBiZSBzaG93aW5nCiAgICAjIHNlZWRlZCBudW1iZXJzIHdpdGggbm90aGluZyB0byBzYXkgc28uCiAgICBj'
    || 'dHggPSB7fQogICAgZ290ID0gcGFuZWxzLmdldCgiY29udGV4dCIsIHt9KQogICAgaWYgInJvd3MiIGluIGdvdCBhbmQgZ290WyJyb3dzIl06CiAgICAgICAg'
    || 'Y3R4ID0gZ290WyJyb3dzIl1bMF0KICAgIGVsc2U6CiAgICAgICAgY3R4ID0geyJTT0xVVElPTiI6IFNPTFVUSU9OX05BTUUsICJCVUlMVF9JTiI6IHRndCwg'
    || 'Ik1PREUiOiAiVU5LTk9XTiJ9CgogICAgY29tcG9uZW50cy5odG1sKGJ1aWxkX2h0bWwoeyJjb250ZXh0IjogY3R4LCAicGFuZWxzIjogcGFuZWxzLAogICAg'
    || 'ICAgICAgICAgICAgICAgICAgICAgICAgICAgICJjdXN0b21pemF0aW9uIjogY3VzdG9taXphdGlvbiwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg'
    || 'ICAiY3VzdG9taXphdGlvbl9lcnJvciI6IGN1c3RvbWl6YXRpb25fZXJyb3IsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIm5hdmlnYXRpb24i'
    || 'OiBuYXZpZ2F0aW9ufSksCiAgICAgICAgICAgICAgICAgICAgaGVpZ2h0PTE5MDAsIHNjcm9sbGluZz1UcnVlKQoKICAgIGlmIHN0LmJ1dHRvbigiUmVmcmVz'
    || 'aCBkYXRhIiwga2V5PSJyZWZyZXNoX3BhbmVsX2RhdGEiKToKICAgICAgICBpbnZhbGlkYXRlX3BhbmVsX2NhY2hlKCkKICAgICAgICBpZiBoYXNhdHRyKHN0'
    || 'LCAicmVydW4iKToKICAgICAgICAgICAgc3QucmVydW4oKQogICAgICAgIGVsc2U6CiAgICAgICAgICAgIHN0LmV4cGVyaW1lbnRhbF9yZXJ1bigpCgogICAg'
    || 'IyBBRlRFUiB0aGUgZGFzaGJvYXJkIGFuZCBCRUZPUkUgdGhlIHByb21vdGlvbiBiYXIuIFRoZSBvcmRlciBpcyBhbiBhcmd1bWVudDoKICAgICMgdGhlIHJ1'
    || 'bGVzIGV4cGxhaW4gdGhlIG51bWJlcnMgaW1tZWRpYXRlbHkgYWJvdmUgdGhlbSwgYW5kIHRoZSBwcm9tb3Rpb24gYmFyCiAgICAjIGlzIHRoZSAid2hhdCBk'
    || 'byBJIGRvIGFib3V0IHRoaXMiIHRoYXQgc2hvdWxkIGNvbWUgbGFzdC4gQSByZWFkZXIgd2hvIGNoYW5nZXMKICAgICMgYSB0aHJlc2hvbGQgaGVyZSBpcyBz'
    || 'dGlsbCByZWFkaW5nIHRoZSBkYXNoYm9hcmQ7IGEgcmVhZGVyIGF0IHRoZSBwcm9tb3Rpb24KICAgICMgYmFyIGhhcyBmaW5pc2hlZC4gU29sdXRpb25zIHdp'
    || 'dGhvdXQgVl9SVUxFX0NPTkZJRyBkcmF3IG5vdGhpbmcgYXQgYWxsLgogICAgY29uZmlnX2JhcihzZXNzaW9uLCB0Z3QpCgogICAgIyBCRVRXRUVOIHRoZSBy'
    || 'dWxlcyBhbmQgdGhlIGFjdGlvbnMuIFRoZSBhZ2VudCBleHBsYWlucyB3aGF0IHRoZSBudW1iZXJzIG1lYW4KICAgICMgYW5kIGlzIG1vc3QgdXNlZnVsIGlt'
    || 'bWVkaWF0ZWx5IGJlZm9yZSB0aGUgZGVjaXNpb24gaXQgaW5mb3Jtczsgc29sdXRpb25zIHRoYXQKICAgICMgZGVjbGFyZSBubyBWX0FHRU5UX0NIQVQgZHJh'
    || 'dyBub3RoaW5nIGF0IGFsbC4KICAgIGFnZW50X2JhcihzZXNzaW9uLCB0Z3QpCgogICAgIyBBRlRFUiB0aGUgZGFzaGJvYXJkLCBub3QgYmVmb3JlLiBUaGUg'
    || 'cHJvbW90aW9uIGJhciBpcyB0aGUgYW5zd2VyIHRvICJ3aGF0IGRvCiAgICAjIEkgZG8gYWJvdXQgdGhpcz8iLCBhbmQgdGhhdCBxdWVzdGlvbiBvbmx5IG1h'
    || 'a2VzIHNlbnNlIG9uY2UgdGhlIG51bWJlcnMgYWJvdmUKICAgICMgaXQgaGF2ZSBiZWVuIHJlYWQuIFB1dHRpbmcgaXQgb24gdG9wIHdvdWxkIGFsc28gcHVz'
    || 'aCB0aGUgd2hvbGUgZGFzaGJvYXJkCiAgICAjIGJlbG93IHRoZSBmb2xkIG9uIGEgbGFwdG9wLgogICAgcHJvbW90aW9uX2JhcihzZXNzaW9uLCB0Z3QpCgoK'
    || 'bWFpbigpCg==';

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
    'CREATE OR REPLACE STREAMLIT ' || :tgt || '.WHGEN_APP '
 || 'ROOT_LOCATION = ''@' || :tgt || '.APP_STAGE'' MAIN_FILE = ''streamlit_app.py'' '
 || 'QUERY_WAREHOUSE = ' || :wh || ' COMMENT = ''Warehouse Generation — Gen2 and Adaptive — generated from account discovery''');

  -- The app runs on the app warehouse whenever someone opens it. Auto-suspend
  -- makes this small, but it is not zero and the operator should see it.
  cost_day    := :cost_day + 0.10;
  cost_detail := ARRAY_APPEND(:cost_detail,
    'Streamlit app on ' || :wh || ' ~0.10 credits/day. ASSUMES an XS warehouse, '
 || 'auto-suspend 60s, and roughly 20 page views/day. Heavier use scales this linearly.');
  dials       := ARRAY_APPEND(:dials,
    'Point WHGEN_APP_WAREHOUSE at an XS warehouse to cut app cost');
  -- Only claim the app exists when this snippet is present. The template used to
  -- print "OPEN THE APP" unconditionally, which told operators to open a
  -- Streamlit object that was never created for solutions built without a UI.
  -- Two independent reviewers caught it; it now lives with the code that
  -- actually creates the app.
  notes       := ARRAY_APPEND(:notes,
    'OPEN THE APP after building: Snowsight > Projects > Streamlit > WHGEN_APP');
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
                 || 'deterministic refusal from ' || 'WHGEN' || '_MIN_FILL_PCT = ' || :min_fill
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
   || 'columns. Set WHGEN_PROFILE = TRUE and re-run to close it.');
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
    override_asked := (SELECT TRY_CAST($WHGEN_OVERRIDE_REVIEW::VARCHAR AS BOOLEAN));
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
    || 'SOLUTION: Warehouse Generation — Gen2 and Adaptive' || CHR(10)
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
        || 'WHGEN_APPROVE is TRUE. To build anyway set WHGEN_OVERRIDE_REVIEW = TRUE; '
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
             || 'WHGEN_BUDGET_CREDITS = ' || :budget || '. Nothing was created.' AS statement
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
    approved := (SELECT TRY_CAST($WHGEN_APPROVE::VARCHAR AS BOOLEAN));
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
   || 'WHGEN_OVERRIDE_REVIEW = TRUE, so the build proceeded anyway. The verdict and '
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
       '# ' || 'Warehouse Generation — Gen2 and Adaptive' || ' — discovery packet' || CHR(10) || CHR(10)
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
      'solution', 'Warehouse Generation — Gen2 and Adaptive', 'run_id', :run_id, 'tier', :tier,
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
    IF (NOT $WHGEN_VERBOSE_OUTPUT::BOOLEAN) THEN
      res := (SELECT IFF(:hard_block <> '' OR (:review_verdict = 'DO_NOT_PROCEED' AND NOT :override_asked), 'BLOCKED', 'READY_TO_BUILD') AS STATUS,
        NULL::VARCHAR AS OPEN_APP_URL,
        :mode AS DATA_MODE,
        :tgt AS DESTINATION,
        :cost_once AS ESTIMATED_BUILD_CREDITS,
        :cost_day AS ESTIMATED_DAILY_CREDITS,
        IFF(:hard_block <> '', :hard_block, IFF(:review_verdict = 'DO_NOT_PROCEED' AND NOT :override_asked, TO_JSON(:review_findings), 'Review the cost and discovery packet, then set WHGEN_APPROVE = TRUE and rerun. Set WHGEN_VERBOSE_OUTPUT = TRUE for the full plan.')) AS NEXT_ACTION,
        :review_verdict AS REVIEW_STATUS,
        :review_findings AS REVIEW_FINDINGS,
        :pk_json AS DISCOVERY_PACKET);
      RETURN TABLE(res);
    END IF;
    res := (
      SELECT -1 AS step, 'WHAT THIS GIVES YOU' AS action,
             COALESCE(NULLIF(:headline, ''), 'Warehouse Generation — Gen2 and Adaptive') AS statement
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
                 'no ceiling set (WHGEN_BUDGET_CREDITS = 0)')
      UNION ALL SELECT 5, 'REVIEW',
             :review_verdict || ' (' || :review_status || ') · '
             || ARRAY_SIZE(:review_findings) || ' finding(s)'
      UNION ALL SELECT 6, 'WHY THE GATE IS CLOSED',
             CASE WHEN :gate_closed_by = 'DETERMINISTIC CHECK' THEN :hard_block
                  WHEN :gate_closed_by = 'REVIEW VERDICT'
                    THEN 'The review returned DO_NOT_PROCEED. Read the findings above. '
                      || 'To build anyway set WHGEN_OVERRIDE_REVIEW = TRUE.'
                  ELSE 'WHGEN_APPROVE is FALSE. Nothing was created.' END
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

  LET receipt_failures ARRAY := (SELECT COALESCE(ARRAY_AGG(OBJECT_CONSTRUCT('statement', VALUE:stmt, 'error', VALUE:error)), ARRAY_CONSTRUCT()) FROM TABLE(FLATTEN(INPUT => :log)) WHERE VALUE:status::STRING = 'FAILED');
  LET receipt_app_name STRING := 'WHGEN_APP';
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
        receipt_workspace_exists := (SELECT COUNT(*) = 1 FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "name" = 'ONESHOT_SOURCE' AND "comment" = 'oneshot-source:25_warehouse_generation');
      EXCEPTION WHEN OTHER THEN
        receipt_workspace_exists := FALSE;
      END;
    END IF;
  END IF;
  IF (NOT $WHGEN_VERBOSE_OUTPUT::BOOLEAN) THEN
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
