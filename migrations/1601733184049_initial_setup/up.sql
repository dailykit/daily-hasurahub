CREATE SCHEMA brands;
CREATE SCHEMA content;
CREATE SCHEMA crm;
CREATE SCHEMA "deviceHub";
CREATE SCHEMA fulfilment;
CREATE SCHEMA imports;
CREATE SCHEMA ingredient;
CREATE SCHEMA insights;
CREATE SCHEMA inventory;
CREATE SCHEMA master;
CREATE SCHEMA notifications;
CREATE SCHEMA "onDemand";
CREATE SCHEMA "onlineStore";
CREATE SCHEMA "order";
CREATE SCHEMA packaging;
CREATE SCHEMA products;
CREATE SCHEMA rules;
CREATE SCHEMA safety;
CREATE SCHEMA settings;
CREATE SCHEMA "simpleRecipe";
CREATE SCHEMA staff;
CREATE SCHEMA subscription;

DROP SCHEMA IF EXISTS _rrule CASCADE;

DROP CAST IF EXISTS (_rrule.RRULE AS TEXT);
DROP CAST IF EXISTS (TEXT AS _rrule.RRULE);

CREATE SCHEMA _rrule;

CREATE TYPE _rrule.FREQ AS ENUM (
  'YEARLY',
  'MONTHLY',
  'WEEKLY',
  'DAILY'
);

CREATE TYPE _rrule.DAY AS ENUM (
  'MO',
  'TU',
  'WE',
  'TH',
  'FR',
  'SA',
  'SU'
);


CREATE TABLE _rrule.RRULE (
  "freq" _rrule.FREQ NOT NULL,
  "interval" INTEGER DEFAULT 1 NOT NULL CHECK(0 < "interval"),
  "count" INTEGER,
  "until" TIMESTAMP,
  "bysecond" INTEGER[] CHECK (0 <= ALL("bysecond") AND 60 > ALL("bysecond")),
  "byminute" INTEGER[] CHECK (0 <= ALL("byminute") AND 60 > ALL("byminute")),
  "byhour" INTEGER[] CHECK (0 <= ALL("byhour") AND 24 > ALL("byhour")),
  "byday" _rrule.DAY[],
  "bymonthday" INTEGER[] CHECK (31 >= ALL("bymonthday") AND 0 <> ALL("bymonthday") AND -31 <= ALL("bymonthday")),
  "byyearday" INTEGER[] CHECK (366 >= ALL("byyearday") AND 0 <> ALL("byyearday") AND -366 <= ALL("byyearday")),
  "byweekno" INTEGER[] CHECK (53 >= ALL("byweekno") AND 0 <> ALL("byweekno") AND -53 <= ALL("byweekno")),
  "bymonth" INTEGER[] CHECK (0 < ALL("bymonth") AND 12 >= ALL("bymonth")),
  "bysetpos" INTEGER[] CHECK(366 >= ALL("bysetpos") AND 0 <> ALL("bysetpos") AND -366 <= ALL("bysetpos")),
  "wkst" _rrule.DAY,

  CONSTRAINT freq_yearly_if_byweekno CHECK("freq" = 'YEARLY' OR "byweekno" IS NULL)
);


CREATE TABLE _rrule.RRULESET (
  "dtstart" TIMESTAMP NOT NULL,
  "dtend" TIMESTAMP,
  "rrule" _rrule.RRULE,
  "exrule" _rrule.RRULE,
  "rdate" TIMESTAMP[],
  "exdate" TIMESTAMP[]
);


CREATE TYPE _rrule.exploded_interval AS (
  "months" INTEGER,
  "days" INTEGER,
  "seconds" INTEGER
);CREATE OR REPLACE FUNCTION _rrule.explode_interval(INTERVAL)
RETURNS _rrule.EXPLODED_INTERVAL AS $$
  SELECT
    (
      EXTRACT(YEAR FROM $1) * 12 + EXTRACT(MONTH FROM $1),
      EXTRACT(DAY FROM $1),
      EXTRACT(HOUR FROM $1) * 3600 + EXTRACT(MINUTE FROM $1) * 60 + EXTRACT(SECOND FROM $1)
    )::_rrule.EXPLODED_INTERVAL;

$$ LANGUAGE SQL IMMUTABLE STRICT;


CREATE OR REPLACE FUNCTION _rrule.factor(INTEGER, INTEGER)
RETURNS INTEGER AS $$
  SELECT
    CASE
      WHEN ($1 = 0 AND $2 = 0) THEN NULL
      WHEN ($1 = 0 OR $2 = 0) THEN 0
      WHEN ($1 % $2 <> 0) THEN 0
      ELSE $1 / $2
    END;

$$ LANGUAGE SQL IMMUTABLE STRICT;


CREATE OR REPLACE FUNCTION _rrule.interval_contains(INTERVAL, INTERVAL)
RETURNS BOOLEAN AS $$
  -- Any fields that have 0 must have zero in each.

  WITH factors AS (
    SELECT
      _rrule.factor(a.months, b.months) AS months,
      _rrule.factor(a.days, b.days) AS days,
      _rrule.factor(a.seconds, b.seconds) AS seconds
    FROM _rrule.explode_interval($2) a, _rrule.explode_interval($1) b
  )
  SELECT
    COALESCE(months <> 0, TRUE)
      AND
    COALESCE(days <> 0, TRUE)
      AND
    COALESCE(seconds <> 0, TRUE)
      AND
    COALESCE(months = days, TRUE)
      AND
    COALESCE(months = seconds, TRUE)
  FROM factors;

$$ LANGUAGE SQL IMMUTABLE STRICT;CREATE OR REPLACE FUNCTION _rrule.parse_line (input TEXT, marker TEXT)
RETURNS SETOF TEXT AS $$
  -- Clear spaces at the front of the lines
  WITH A4 as (SELECT regexp_replace(input, '^\s*',  '', 'ng') "r"),
  -- Clear all lines except the ones starting with marker
  A5 as (SELECT regexp_replace(A4."r", '^(?!' || marker || ').*?$',  '', 'ng') "r" FROM A4),
  -- Replace carriage returns with blank space.
  A10 as (SELECT regexp_replace(A5."r", E'[\\n\\r]+',  '', 'g') "r" FROM A5),
  -- Remove marker prefix.
  A15 as (SELECT regexp_replace(A10."r", marker || ':(.*)$', '\1') "r" FROM A10),
  -- Trim
  A17 as (SELECT trim(A15."r") "r" FROM A15),
  -- Split each key-value pair into a row in a table
  A20 as (SELECT regexp_split_to_table(A17."r", ';') "r" FROM A17)
  -- Split each key value pair into an array, e.g. {'FREQ', 'DAILY'}
  SELECT "r" AS "y"
  FROM A20
  WHERE "r" != '';
$$ LANGUAGE SQL IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION _rrule.timestamp_to_day("ts" TIMESTAMP) RETURNS _rrule.DAY AS $$
  SELECT CAST(CASE to_char("ts", 'DY')
    WHEN 'MON' THEN 'MO'
    WHEN 'TUE' THEN 'TU'
    WHEN 'WED' THEN 'WE'
    WHEN 'THU' THEN 'TH'
    WHEN 'FRI' THEN 'FR'
    WHEN 'SAT' THEN 'SA'
    WHEN 'SUN' THEN 'SU'
  END as _rrule.DAY);
$$ LANGUAGE SQL IMMUTABLE;

CREATE CAST (TIMESTAMP AS _rrule.DAY)
  WITH FUNCTION _rrule.timestamp_to_day(TIMESTAMP)
  AS IMPLICIT;CREATE OR REPLACE FUNCTION _rrule.enum_index_of(anyenum)
RETURNS INTEGER AS $$
    SELECT row_number FROM (
        SELECT (row_number() OVER ())::INTEGER, "value"
        FROM unnest(enum_range($1)) "value"
    ) x
    WHERE "value" = $1;
$$ LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION _rrule.enum_index_of(anyenum) IS 'Given an ENUM value, return it''s index.';
CREATE OR REPLACE FUNCTION _rrule.integer_array (TEXT)
RETURNS integer[] AS $$
  SELECT ('{' || $1 || '}')::integer[];
$$ LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION _rrule.integer_array (text) IS 'Coerce a text string into an array of integers';



CREATE OR REPLACE FUNCTION _rrule.day_array (TEXT)
RETURNS _rrule.DAY[] AS $$
  SELECT ('{' || $1 || '}')::_rrule.DAY[];
$$ LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION _rrule.day_array (text) IS 'Coerce a text string into an array of "rrule"."day"';



CREATE OR REPLACE FUNCTION _rrule.array_join(ANYARRAY, "delimiter" TEXT)
RETURNS TEXT AS $$
  SELECT string_agg(x::text, "delimiter")
  FROM unnest($1) x;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION _rrule.explode(_rrule.RRULE)
RETURNS SETOF _rrule.RRULE AS 'SELECT $1' LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION _rrule.explode (_rrule.RRULE) IS 'Helper function to allow SELECT * FROM explode(rrule)';
CREATE OR REPLACE FUNCTION _rrule.compare_equal(_rrule.RRULE, _rrule.RRULE)
RETURNS BOOLEAN AS $$
  SELECT count(*) = 1 FROM (
    SELECT * FROM _rrule.explode($1) UNION SELECT * FROM _rrule.explode($2)
  ) AS x;
$$ LANGUAGE SQL IMMUTABLE STRICT;



CREATE OR REPLACE FUNCTION _rrule.compare_not_equal(_rrule.RRULE, _rrule.RRULE)
RETURNS BOOLEAN AS $$
  SELECT count(*) = 2 FROM (
    SELECT * FROM _rrule.explode($1) UNION SELECT * FROM _rrule.explode($2)
  ) AS x;
$$ LANGUAGE SQL IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION _rrule.build_interval("interval" INTEGER, "freq" _rrule.FREQ)
RETURNS INTERVAL AS $$
  -- Transform ical time interval enums into Postgres intervals, e.g.
  -- "WEEKLY" becomes "WEEKS".
  SELECT ("interval" || ' ' || regexp_replace(regexp_replace("freq"::TEXT, 'LY', 'S'), 'IS', 'YS'))::INTERVAL;
$$ LANGUAGE SQL IMMUTABLE STRICT;


CREATE OR REPLACE FUNCTION _rrule.build_interval(_rrule.RRULE)
RETURNS INTERVAL AS $$
  SELECT _rrule.build_interval(COALESCE($1."interval", 1), $1."freq");
$$ LANGUAGE SQL IMMUTABLE STRICT;
-- rrule containment.
-- intervals must be compatible.
-- wkst must match
-- all other fields must have $2's value(s) in $1.
CREATE OR REPLACE FUNCTION _rrule.contains(_rrule.RRULE, _rrule.RRULE)
RETURNS BOOLEAN AS $$
  SELECT _rrule.interval_contains(
    _rrule.build_interval($1),
    _rrule.build_interval($2)
  ) AND COALESCE($1."wkst" = $2."wkst", true);
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION _rrule.contained_by(_rrule.RRULE, _rrule.RRULE)
RETURNS BOOLEAN AS $$
  SELECT _rrule.contains($2, $1);
$$ LANGUAGE SQL IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION _rrule.until("rrule" _rrule.RRULE, "dtstart" TIMESTAMP)
RETURNS TIMESTAMP AS $$
  SELECT min("until")
  FROM (
    SELECT "rrule"."until"
    UNION
    SELECT "dtstart" + _rrule.build_interval("rrule"."interval", "rrule"."freq") * COALESCE("rrule"."count", CASE WHEN "rrule"."until" IS NOT NULL THEN NULL ELSE 1 END) AS "until"
  ) "until" GROUP BY ();

$$ LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION _rrule.until(_rrule.RRULE, TIMESTAMP) IS 'The calculated "until"" timestamp for the given rrule+dtstart';

-- For example, a YEARLY rule that repeats on first and third month have 2 start values.

CREATE OR REPLACE FUNCTION _rrule.all_starts(
  "rrule" _rrule.RRULE,
  "dtstart" TIMESTAMP
) RETURNS SETOF TIMESTAMP AS $$
DECLARE
  months int[];
  hour int := EXTRACT(HOUR FROM "dtstart")::integer;
  minute int := EXTRACT(MINUTE FROM "dtstart")::integer;
  second double precision := EXTRACT(SECOND FROM "dtstart");
  day int := EXTRACT(DAY FROM "dtstart")::integer;
  month int := EXTRACT(MONTH FROM "dtstart")::integer;
  year int := EXTRACT(YEAR FROM "dtstart")::integer;
  year_start timestamp := make_timestamp(year, 1, 1, hour, minute, second);
  year_end timestamp := make_timestamp(year, 12, 31, hour, minute, second);
  interv INTERVAL := _rrule.build_interval("rrule");
BEGIN
  RETURN QUERY WITH
  "year" as (SELECT EXTRACT(YEAR FROM "dtstart")::integer AS "year"),
  A10 as (
    SELECT
      make_timestamp(
        "year"."year",
        COALESCE("bymonth", month),
        COALESCE("bymonthday", day),
        COALESCE("byhour", hour),
        COALESCE("byminute", minute),
        COALESCE("bysecond", second)
      ) as "ts"
    FROM "year"
    LEFT OUTER JOIN unnest(("rrule")."bymonth") AS "bymonth" ON (true)
    LEFT OUTER JOIN unnest(("rrule")."bymonthday") as "bymonthday" ON (true)
    LEFT OUTER JOIN unnest(("rrule")."byhour") AS "byhour" ON (true)
    LEFT OUTER JOIN unnest(("rrule")."byminute") AS "byminute" ON (true)
    LEFT OUTER JOIN unnest(("rrule")."bysecond") AS "bysecond" ON (true)
  ),
  A11 as (
    SELECT DISTINCT "ts"
    FROM A10
    UNION
    SELECT "ts" FROM (
      SELECT "ts"
      FROM generate_series("dtstart", year_end, INTERVAL '1 day') "ts"
      WHERE (
        "ts"::_rrule.DAY = ANY("rrule"."byday")
      )
      AND "ts" <= ("dtstart" + INTERVAL '7 days')
    ) as "ts"
    UNION
    SELECT "ts" FROM (
      SELECT "ts"
      FROM generate_series("dtstart", year_end, INTERVAL '1 day') "ts"
      WHERE (
        EXTRACT(DAY FROM "ts") = ANY("rrule"."bymonthday")
      )
      AND "ts" <= ("dtstart" + INTERVAL '2 months')
    ) as "ts"
    UNION
    SELECT "ts" FROM (
      SELECT "ts"
      FROM generate_series("dtstart", "dtstart" + INTERVAL '1 year', INTERVAL '1 month') "ts"
      WHERE (
        EXTRACT(MONTH FROM "ts") = ANY("rrule"."bymonth")
      )
    ) as "ts"
  )
  SELECT DISTINCT "ts"
  FROM A11
  WHERE (
    "rrule"."byday" IS NULL OR "ts"::_rrule.DAY = ANY("rrule"."byday")
  )
  AND (
    "rrule"."bymonth" IS NULL OR EXTRACT(MONTH FROM "ts") = ANY("rrule"."bymonth")
  )
  AND (
    "rrule"."bymonthday" IS NULL OR EXTRACT(DAY FROM "ts") = ANY("rrule"."bymonthday")
  )
  ORDER BY "ts";

END;
$$ LANGUAGE plpgsql STRICT IMMUTABLE;
CREATE OR REPLACE FUNCTION _rrule.validate_rrule (result _rrule.RRULE)
RETURNS void AS $$
BEGIN
  -- FREQ is required
  IF result."freq" IS NULL THEN
    RAISE EXCEPTION 'FREQ cannot be null';
  END IF;

  -- FREQ=YEARLY required if BYWEEKNO is provided
  IF result."byweekno" IS NOT NULL AND result."freq" != 'YEARLY' THEN
    RAISE EXCEPTION 'FREQ must be YEARLY if BYWEEKNO is provided.';
  END IF;

  -- Limits on FREQ if byyearday is selected
  IF (result."freq" <> 'YEARLY' AND result."byyearday" IS NOT NULL) THEN
    RAISE EXCEPTION 'BYYEARDAY is only valid when FREQ is YEARLY.';
  END IF;

  IF (result."freq" = 'WEEKLY' AND result."bymonthday" IS NOT NULL) THEN
    RAISE EXCEPTION 'BYMONTHDAY is not valid when FREQ is WEEKLY.';
  END IF;

  -- BY[something-else] is required if BYSETPOS is set.
  IF (result."bysetpos" IS NOT NULL AND result."bymonth" IS NULL AND result."byweekno" IS NULL AND result."byyearday" IS NULL AND result."bymonthday" IS NULL AND result."byday" IS NULL AND result."byhour" IS NULL AND result."byminute" IS NULL AND result."bysecond" IS NULL) THEN
    RAISE EXCEPTION 'BYSETPOS requires at least one other BY*';
  END IF;

  IF result."freq" = 'DAILY' AND result."byday" IS NOT NULL THEN
    RAISE EXCEPTION 'BYDAY is not valid when FREQ is DAILY.';
  END IF;

  IF result."until" IS NOT NULL AND result."count" IS NOT NULL THEN
    RAISE EXCEPTION 'UNTIL and COUNT MUST NOT occur in the same recurrence.';
  END IF;

  IF result."interval" IS NOT NULL THEN
    IF (NOT result."interval" > 0) THEN
      RAISE EXCEPTION 'INTERVAL must be a non-zero integer.';
    END IF;
  END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;CREATE OR REPLACE FUNCTION _rrule.rrule (TEXT)
RETURNS _rrule.RRULE AS $$
DECLARE
  result _rrule.RRULE;
BEGIN
  WITH "tokens" AS (
    WITH A20 as (SELECT _rrule.parse_line($1::text, 'RRULE') "r"),
    -- Split each key value pair into an array, e.g. {'FREQ', 'DAILY'}
    A30 as (SELECT regexp_split_to_array("r", '=') AS "y" FROM A20)
    SELECT "y"[1] AS "key", "y"[2] AS "val" FROM A30
  ),
  candidate AS (
    SELECT
      (SELECT "val"::_rrule.FREQ FROM "tokens" WHERE "key" = 'FREQ') AS "freq",
      (SELECT "val"::INTEGER FROM "tokens" WHERE "key" = 'INTERVAL') AS "interval",
      (SELECT "val"::INTEGER FROM "tokens" WHERE "key" = 'COUNT') AS "count",
      (SELECT "val"::TIMESTAMP FROM "tokens" WHERE "key" = 'UNTIL') AS "until",
      (SELECT _rrule.integer_array("val") FROM "tokens" WHERE "key" = 'BYSECOND') AS "bysecond",
      (SELECT _rrule.integer_array("val") FROM "tokens" WHERE "key" = 'BYMINUTE') AS "byminute",
      (SELECT _rrule.integer_array("val") FROM "tokens" WHERE "key" = 'BYHOUR') AS "byhour",
      (SELECT _rrule.day_array("val") FROM "tokens" WHERE "key" = 'BYDAY') AS "byday",
      (SELECT _rrule.integer_array("val") FROM "tokens" WHERE "key" = 'BYMONTHDAY') AS "bymonthday",
      (SELECT _rrule.integer_array("val") FROM "tokens" WHERE "key" = 'BYYEARDAY') AS "byyearday",
      (SELECT _rrule.integer_array("val") FROM "tokens" WHERE "key" = 'BYWEEKNO') AS "byweekno",
      (SELECT _rrule.integer_array("val") FROM "tokens" WHERE "key" = 'BYMONTH') AS "bymonth",
      (SELECT _rrule.integer_array("val") FROM "tokens" WHERE "key" = 'BYSETPOS') AS "bysetpos",
      (SELECT "val"::_rrule.DAY FROM "tokens" WHERE "key" = 'WKST') AS "wkst"
  )
  SELECT
    "freq",
    -- Default value for INTERVAL
    COALESCE("interval", 1) AS "interval",
    "count",
    "until",
    "bysecond",
    "byminute",
    "byhour",
    "byday",
    "bymonthday",
    "byyearday",
    "byweekno",
    "bymonth",
    "bysetpos",
    -- DEFAULT value for wkst
    COALESCE("wkst", 'MO') AS "wkst"
  INTO result
  FROM candidate;

  PERFORM _rrule.validate_rrule(result);

  RETURN result;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;


CREATE OR REPLACE FUNCTION _rrule.text(_rrule.RRULE)
RETURNS TEXT AS $$
  SELECT regexp_replace(
    'RRULE:'
    || COALESCE('FREQ=' || $1."freq" || ';', '')
    || CASE WHEN $1."interval" = 1 THEN '' ELSE COALESCE('INTERVAL=' || $1."interval" || ';', '') END
    || COALESCE('COUNT=' || $1."count" || ';', '')
    || COALESCE('UNTIL=' || $1."until" || ';', '')
    || COALESCE('BYSECOND=' || _rrule.array_join($1."bysecond", ',') || ';', '')
    || COALESCE('BYMINUTE=' || _rrule.array_join($1."byminute", ',') || ';', '')
    || COALESCE('BYHOUR=' || _rrule.array_join($1."byhour", ',') || ';', '')
    || COALESCE('BYDAY=' || _rrule.array_join($1."byday", ',') || ';', '')
    || COALESCE('BYMONTHDAY=' || _rrule.array_join($1."bymonthday", ',') || ';', '')
    || COALESCE('BYYEARDAY=' || _rrule.array_join($1."byyearday", ',') || ';', '')
    || COALESCE('BYWEEKNO=' || _rrule.array_join($1."byweekno", ',') || ';', '')
    || COALESCE('BYMONTH=' || _rrule.array_join($1."bymonth", ',') || ';', '')
    || COALESCE('BYSETPOS=' || _rrule.array_join($1."bysetpos", ',') || ';', '')
    || CASE WHEN $1."wkst" = 'MO' THEN '' ELSE COALESCE('WKST=' || $1."wkst" || ';', '') END
  , ';$', '');
$$ LANGUAGE SQL IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION _rrule.rruleset (TEXT)
RETURNS _rrule.RRULESET AS $$
  WITH "dtstart-line" AS (SELECT _rrule.parse_line($1::text, 'DTSTART') as "x"),
  "dtend-line" AS (SELECT _rrule.parse_line($1::text, 'DTEND') as "x"),
  "exrule-line" AS (SELECT _rrule.parse_line($1::text, 'EXRULE') as "x")
  SELECT
    (SELECT "x"::timestamp FROM "dtstart-line" LIMIT 1) AS "dtstart",
    (SELECT "x"::timestamp FROM "dtend-line" LIMIT 1) AS "dtend",
    (SELECT _rrule.rrule($1::text) "rrule") as "rrule",
    (SELECT _rrule.rrule("x"::text) "rrule" FROM "exrule-line") as "exrule",
    NULL::TIMESTAMP[] "rdate",
    NULL::TIMESTAMP[] "exdate";
$$ LANGUAGE SQL IMMUTABLE STRICT;

-- All of the function(rrule, ...) forms also accept a text argument, which will
-- be parsed using the RFC-compliant parser.

CREATE OR REPLACE FUNCTION _rrule.is_finite("rrule" _rrule.RRULE)
RETURNS BOOLEAN AS $$
  SELECT "rrule"."count" IS NOT NULL OR "rrule"."until" IS NOT NULL;
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION _rrule.is_finite("rrule" TEXT)
RETURNS BOOLEAN AS $$
  SELECT _rrule.is_finite(_rrule.rrule("rrule"));
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION _rrule.is_finite("rruleset" _rrule.RRULESET)
RETURNS BOOLEAN AS $$
  SELECT _rrule.is_finite("rruleset"."rrule")
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION _rrule.is_finite("rruleset_array" _rrule.RRULESET[])
RETURNS BOOLEAN AS $$
DECLARE
  item _rrule.RRULESET;
BEGIN
  FOREACH item IN ARRAY "rruleset_array" LOOP
    IF (SELECT _rrule.is_finite(item)) THEN
      RETURN true;
    END IF;
  END LOOP;
  RETURN false;
END;
$$ LANGUAGE plpgsql STRICT IMMUTABLE;



CREATE OR REPLACE FUNCTION _rrule.occurrences(
  "rrule" _rrule.RRULE,
  "dtstart" TIMESTAMP
)
RETURNS SETOF TIMESTAMP AS $$
  WITH "starts" AS (
    SELECT "start"
    FROM _rrule.all_starts($1, $2) "start"
  ),
  "params" AS (
    SELECT
      "until",
      "interval"
    FROM _rrule.until($1, $2) "until"
    FULL OUTER JOIN _rrule.build_interval($1) "interval" ON (true)
  ),
  "generated" AS (
    SELECT generate_series("start", "until", "interval") "occurrence"
    FROM "params"
    FULL OUTER JOIN "starts" ON (true)
  ),
  "ordered" AS (
    SELECT DISTINCT "occurrence"
    FROM "generated"
    WHERE "occurrence" >= "dtstart"
    ORDER BY "occurrence"
  ),
  "tagged" AS (
    SELECT
      row_number() OVER (),
      "occurrence"
    FROM "ordered"
  )
  SELECT "occurrence"
  FROM "tagged"
  WHERE "row_number" <= "rrule"."count"
  OR "rrule"."count" IS NULL
  ORDER BY "occurrence";
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION _rrule.occurrences("rrule" _rrule.RRULE, "dtstart" TIMESTAMP, "between" TSRANGE)
RETURNS SETOF TIMESTAMP AS $$
  SELECT "occurrence"
  FROM _rrule.occurrences("rrule", "dtstart") "occurrence"
  WHERE "occurrence" <@ "between";
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION _rrule.occurrences("rrule" TEXT, "dtstart" TIMESTAMP, "between" TSRANGE)
RETURNS SETOF TIMESTAMP AS $$
  SELECT "occurrence"
  FROM _rrule.occurrences(_rrule.rrule("rrule"), "dtstart") "occurrence"
  WHERE "occurrence" <@ "between";
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION _rrule.occurrences(
  "rruleset" _rrule.RRULESET,
  "tsrange" TSRANGE
)
RETURNS SETOF TIMESTAMP AS $$
  WITH "rrules" AS (
    SELECT
      "rruleset"."dtstart",
      "rruleset"."dtend",
      "rruleset"."rrule"
  ),
  "rdates" AS (
    SELECT _rrule.occurrences("rrule", "dtstart", "tsrange") AS "occurrence"
    FROM "rrules"
    UNION
    SELECT unnest("rruleset"."rdate") AS "occurrence"
  ),
  "exrules" AS (
    SELECT
      "rruleset"."dtstart",
      "rruleset"."dtend",
      "rruleset"."exrule"
  ),
  "exdates" AS (
    SELECT _rrule.occurrences("exrule", "dtstart", "tsrange") AS "occurrence"
    FROM "exrules"
    UNION
    SELECT unnest("rruleset"."exdate") AS "occurrence"
  )
  SELECT "occurrence" FROM "rdates"
  EXCEPT
  SELECT "occurrence" FROM "exdates"
  ORDER BY "occurrence";
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION _rrule.occurrences("rruleset" _rrule.RRULESET)
RETURNS SETOF TIMESTAMP AS $$
  SELECT _rrule.occurrences("rruleset", '(,)'::TSRANGE);
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION _rrule.occurrences(
  "rruleset_array" _rrule.RRULESET[],
  "tsrange" TSRANGE
  -- TODO: add a default limit and then use that limit from `first` and `last`
)
RETURNS SETOF TIMESTAMP AS $$
DECLARE
  i int;
  lim int;
  q text := '';
BEGIN
  lim := array_length("rruleset_array", 1);

  IF lim IS NULL THEN
    q := 'VALUES (NULL::TIMESTAMP) LIMIT 0;';
  ELSE
    FOR i IN 1..lim
    LOOP
      q := q || $q$SELECT _rrule.occurrences('$q$ || "rruleset_array"[i] ||$q$'::_rrule.RRULESET, '$q$ || "tsrange" ||$q$'::TSRANGE)$q$;
      IF i != lim THEN
        q := q || ' UNION ';
      END IF;
    END LOOP;
    q := q || ' ORDER BY occurrences ASC';
  END IF;

  RETURN QUERY EXECUTE q;
END;
$$ LANGUAGE plpgsql STRICT IMMUTABLE;CREATE OR REPLACE FUNCTION _rrule.first("rrule" _rrule.RRULE, "dtstart" TIMESTAMP)
RETURNS TIMESTAMP AS $$
BEGIN
  RETURN (SELECT "ts"
  FROM _rrule.all_starts("rrule", "dtstart") "ts"
  WHERE "ts" >= "dtstart"
  ORDER BY "ts" ASC
  LIMIT 1);
END;
$$ LANGUAGE plpgsql STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION _rrule.first("rrule" TEXT, "dtstart" TIMESTAMP)
RETURNS TIMESTAMP AS $$
  SELECT _rrule.first(_rrule.rrule("rrule"), "dtstart");
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION _rrule.first("rruleset" _rrule.RRULESET)
RETURNS TIMESTAMP AS $$
  SELECT occurrence
  FROM _rrule.occurrences("rruleset") occurrence
  ORDER BY occurrence ASC LIMIT 1;
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION _rrule.first("rruleset_array" _rrule.RRULESET[])
RETURNS TIMESTAMP AS $$
  SELECT occurrence
  FROM _rrule.occurrences("rruleset_array", '(,)'::TSRANGE) occurrence
  ORDER BY occurrence ASC LIMIT 1;
$$ LANGUAGE SQL STRICT IMMUTABLE;


CREATE OR REPLACE FUNCTION _rrule.last("rrule" _rrule.RRULE, "dtstart" TIMESTAMP)
RETURNS TIMESTAMP AS $$
  SELECT occurrence
  FROM _rrule.occurrences("rrule", "dtstart") occurrence
  ORDER BY occurrence DESC LIMIT 1;
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION _rrule.last("rrule" TEXT, "dtstart" TIMESTAMP)
RETURNS TIMESTAMP AS $$
  SELECT _rrule.last(_rrule.rrule("rrule"), "dtstart");
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION _rrule.last("rruleset" _rrule.RRULESET)
RETURNS TIMESTAMP AS $$
  SELECT occurrence
  FROM _rrule.occurrences("rruleset") occurrence
  ORDER BY occurrence DESC LIMIT 1;
$$ LANGUAGE SQL STRICT IMMUTABLE;

-- TODO: Ensure to check whether the range is finite. If not, we should return null
-- or something meaningful.
CREATE OR REPLACE FUNCTION _rrule.last("rruleset_array" _rrule.RRULESET[])
RETURNS SETOF TIMESTAMP AS $$
BEGIN
  IF (SELECT _rrule.is_finite("rruleset_array")) THEN
    RETURN QUERY SELECT occurrence
    FROM _rrule.occurrences("rruleset_array", '(,)'::TSRANGE) occurrence
    ORDER BY occurrence DESC LIMIT 1;
  ELSE
    RETURN QUERY SELECT NULL::TIMESTAMP;
  END IF;
END;
$$ LANGUAGE plpgsql STRICT IMMUTABLE;


CREATE OR REPLACE FUNCTION _rrule.before(
  "rrule" _rrule.RRULE,
  "dtstart" TIMESTAMP,
  "when" TIMESTAMP
)
RETURNS SETOF TIMESTAMP AS $$
  SELECT *
  FROM _rrule.occurrences("rrule", "dtstart", tsrange(NULL, "when", '[]'));
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION _rrule.before("rrule" TEXT, "dtstart" TIMESTAMP, "when" TIMESTAMP)
RETURNS SETOF TIMESTAMP AS $$
  SELECT _rrule.before(_rrule.rrule("rrule"), "dtstart", "when");
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION _rrule.before("rruleset" _rrule.RRULESET, "when" TIMESTAMP)
RETURNS SETOF TIMESTAMP AS $$
  SELECT *
  FROM _rrule.occurrences("rruleset", tsrange(NULL, "when", '[]'));
$$ LANGUAGE SQL STRICT IMMUTABLE;

-- TODO: test
CREATE OR REPLACE FUNCTION _rrule.before("rruleset_array" _rrule.RRULESET[], "when" TIMESTAMP)
RETURNS SETOF TIMESTAMP AS $$
  SELECT *
  FROM _rrule.occurrences("rruleset_array", tsrange(NULL, "when", '[]'));
$$ LANGUAGE SQL STRICT IMMUTABLE;



CREATE OR REPLACE FUNCTION _rrule.after(
  "rrule" _rrule.RRULE,
  "dtstart" TIMESTAMP,
  "when" TIMESTAMP
)
RETURNS SETOF TIMESTAMP AS $$
  SELECT *
  FROM _rrule.occurrences("rrule", "dtstart", tsrange("when", NULL));
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION _rrule.after(
  "rrule" TEXT,
  "dtstart" TIMESTAMP,
  "when" TIMESTAMP
)
RETURNS SETOF TIMESTAMP AS $$
  SELECT _rrule.after(_rrule.rrule("rrule"), "dtstart", "when");
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION _rrule.after("rruleset" _rrule.RRULESET, "when" TIMESTAMP)
RETURNS SETOF TIMESTAMP AS $$
  SELECT *
  FROM _rrule.occurrences("rruleset", tsrange("when", NULL));
$$ LANGUAGE SQL STRICT IMMUTABLE;

-- TODO: test
CREATE OR REPLACE FUNCTION _rrule.after("rruleset_array" _rrule.RRULESET[], "when" TIMESTAMP)
RETURNS SETOF TIMESTAMP AS $$
  SELECT *
  FROM _rrule.occurrences("rruleset_array", tsrange("when", NULL));
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION _rrule.contains_timestamp(_rrule.RRULESET, TIMESTAMP)
RETURNS BOOLEAN AS $$
DECLARE
  inSet boolean;
BEGIN
  -- TODO: Not sure what how this is finding a timestamp that is contained
  -- by the rruleset.
  SELECT COUNT(*) > 0
  INTO inSet
  FROM _rrule.after($1, $2 - INTERVAL '1 month') "ts"
  WHERE "ts"::date = $2::date;

  RETURN inSet;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION _rrule.jsonb_to_rrule("input" jsonb)
RETURNS _rrule.RRULE AS $$
DECLARE
  result _rrule.RRULE;
BEGIN
  IF (SELECT count(*) = 0 FROM jsonb_object_keys("input") WHERE "input"::TEXT <> 'null') THEN
    RETURN NULL;
  END IF;

  SELECT
    "freq",
    -- Default value for INTERVAL
    COALESCE("interval", 1) AS "interval",
    "count",
    "until",
    "bysecond",
    "byminute",
    "byhour",
    "byday",
    "bymonthday",
    "byyearday",
    "byweekno",
    "bymonth",
    "bysetpos",
    -- DEFAULT value for wkst
    COALESCE("wkst", 'MO') AS "wkst"
  INTO result
  FROM jsonb_to_record("input") as x(
    "freq" _rrule.FREQ,
    "interval" integer,
    "count" INTEGER,
    "until" text,
    "bysecond" integer[],
    "byminute" integer[],
    "byhour" integer[],
    "byday" text[],
    "bymonthday" integer[],
    "byyearday" integer[],
    "byweekno" integer[],
    "bymonth" integer[],
    "bysetpos" integer[],
    "wkst" _rrule.DAY
  );

  PERFORM _rrule.validate_rrule(result);

  RETURN result;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION _rrule.jsonb_to_rruleset("input" jsonb)
RETURNS _rrule.RRULESET AS $$
DECLARE
  result _rrule.RRULESET;
BEGIN
  SELECT
    "dtstart"::TIMESTAMP,
    "dtend"::TIMESTAMP,
    _rrule.jsonb_to_rrule("rrule") "rrule",
    _rrule.jsonb_to_rrule("exrule") "exrule",
    "rdate"::TIMESTAMP[],
    "exdate"::TIMESTAMP[]
  INTO result
  FROM jsonb_to_record("input") as x(
    "dtstart" text,
    "dtend" text,
    "rrule" jsonb,
    "exrule" jsonb,
    "rdate" text[],
    "exdate" text[]
  );

  -- TODO: validate rruleset

  RETURN result;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION _rrule.jsonb_to_rruleset_array("input" jsonb)
RETURNS _rrule.RRULESET[] AS $$
DECLARE
  item jsonb;
  out _rrule.RRULESET[] := '{}'::_rrule.RRULESET[];
BEGIN
  FOR item IN SELECT * FROM jsonb_array_elements("input")
  LOOP
    out := (SELECT out || _rrule.jsonb_to_rruleset(item));
  END LOOP;

  RETURN out;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION _rrule.rrule_to_jsonb("input" _rrule.RRULE)
RETURNS jsonb AS $$
BEGIN
  RETURN jsonb_strip_nulls(jsonb_build_object(
    'freq', "input"."freq",
    'interval', "input"."interval",
    'count', "input"."count",
    'until', "input"."until",
    'bysecond', "input"."bysecond",
    'byminute', "input"."byminute",
    'byhour', "input"."byhour",
    'byday', "input"."byday",
    'bymonthday', "input"."bymonthday",
    'byyearday', "input"."byyearday",
    'byweekno', "input"."byweekno",
    'bymonth', "input"."bymonth",
    'bysetpos', "input"."bysetpos",
    'wkst', "input"."wkst"
  ));
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION _rrule.rruleset_to_jsonb("input" _rrule.RRULESET)
RETURNS jsonb AS $$
DECLARE
  rrule jsonb;
  exrule jsonb;
BEGIN
  SELECT _rrule.rrule_to_jsonb("input"."rrule")
  INTO rrule;

  SELECT _rrule.rrule_to_jsonb("input"."exrule")
  INTO exrule;

  RETURN jsonb_strip_nulls(jsonb_build_object(
    'dtstart', "input"."dtstart",
    'dtend', "input"."dtend",
    'rrule', rrule,
    'exrule', exrule,
    'rdate', "input"."rdate",
    'exdate', "input"."exdate"
  ));
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION _rrule.rruleset_array_to_jsonb("input" _rrule.RRULESET[])
RETURNS jsonb AS $$
DECLARE
  item _rrule.RRULESET;
  out jsonb := '[]'::jsonb;
BEGIN
  FOREACH item IN ARRAY "input" LOOP
    out := (SELECT out || _rrule.rruleset_to_jsonb(item));
  END LOOP;

  RETURN out;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION _rrule.rruleset_array_contains_timestamp(_rrule.RRULESET[], TIMESTAMP)
RETURNS BOOLEAN AS $$
DECLARE
  item _rrule.RRULESET;
BEGIN
  FOREACH item IN ARRAY $1
  LOOP
    IF (SELECT _rrule.contains_timestamp(item, $2)) THEN
      RETURN true;
    END IF;
  END LOOP;

  RETURN false;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION _rrule.rruleset_has_after_timestamp(_rrule.RRULESET, TIMESTAMP)
RETURNS BOOLEAN AS $$
  SELECT count(*) > 0 FROM _rrule.after($1, $2) LIMIT 1;
$$ LANGUAGE SQL IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION _rrule.rruleset_has_before_timestamp(_rrule.RRULESET, TIMESTAMP)
RETURNS BOOLEAN AS $$
  SELECT count(*) > 0 FROM _rrule.before($1, $2) LIMIT 1;
$$ LANGUAGE SQL IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION _rrule.rruleset_array_has_after_timestamp(_rrule.RRULESET[], TIMESTAMP)
RETURNS BOOLEAN AS $$
DECLARE
  item _rrule.RRULESET;
BEGIN
  FOREACH item IN ARRAY $1
  LOOP
    IF (SELECT count(*) > 0 FROM _rrule.after(item, $2) LIMIT 1) THEN
      RETURN true;
    END IF;
  END LOOP;

  RETURN false;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION _rrule.rruleset_array_has_before_timestamp(_rrule.RRULESET[], TIMESTAMP)
RETURNS BOOLEAN AS $$
DECLARE
  item _rrule.RRULESET;
BEGIN
  FOREACH item IN ARRAY $1
  LOOP
    IF (SELECT count(*) > 0 FROM _rrule.before(item, $2) LIMIT 1) THEN
      RETURN true;
    END IF;
  END LOOP;

  RETURN false;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OPERATOR = (
  LEFTARG = _rrule.RRULE,
  RIGHTARG = _rrule.RRULE,
  PROCEDURE = _rrule.compare_equal,
  NEGATOR = <>,
  COMMUTATOR = =
);

CREATE OPERATOR <> (
  LEFTARG = _rrule.RRULE,
  RIGHTARG = _rrule.RRULE,
  PROCEDURE = _rrule.compare_not_equal,
  NEGATOR = =,
  COMMUTATOR = <>
);

CREATE OPERATOR @> (
  LEFTARG = _rrule.RRULE,
  RIGHTARG = _rrule.RRULE,
  PROCEDURE = _rrule.contains,
  COMMUTATOR = <@
);

CREATE OPERATOR <@ (
  LEFTARG = _rrule.RRULE,
  RIGHTARG = _rrule.RRULE,
  PROCEDURE = _rrule.contained_by,
  COMMUTATOR = @>
);

CREATE OPERATOR @> (
  LEFTARG = _rrule.RRULESET,
  RIGHTARG = TIMESTAMP,
  PROCEDURE = _rrule.contains_timestamp
);

CREATE OPERATOR @> (
  LEFTARG = _rrule.RRULESET[],
  RIGHTARG = TIMESTAMP,
  PROCEDURE = _rrule.rruleset_array_contains_timestamp
);


CREATE OPERATOR > (
  LEFTARG = _rrule.RRULESET[],
  RIGHTARG = TIMESTAMP,
  PROCEDURE = _rrule.rruleset_array_has_after_timestamp
);

CREATE OPERATOR < (
  LEFTARG = _rrule.RRULESET[],
  RIGHTARG = TIMESTAMP,
  PROCEDURE = _rrule.rruleset_array_has_before_timestamp
);

CREATE OPERATOR > (
  LEFTARG = _rrule.RRULESET,
  RIGHTARG = TIMESTAMP,
  PROCEDURE = _rrule.rruleset_has_after_timestamp
);

CREATE OPERATOR < (
  LEFTARG = _rrule.RRULESET,
  RIGHTARG = TIMESTAMP,
  PROCEDURE = _rrule.rruleset_has_before_timestamp
);

CREATE CAST (TEXT AS _rrule.RRULE)
  WITH FUNCTION _rrule.rrule(TEXT)
  AS IMPLICIT;


CREATE CAST (TEXT AS _rrule.RRULESET)
  WITH FUNCTION _rrule.rruleset(TEXT)
  AS IMPLICIT;


CREATE CAST (jsonb AS _rrule.RRULE)
  WITH FUNCTION _rrule.jsonb_to_rrule(jsonb)
  AS IMPLICIT;


CREATE CAST (_rrule.RRULE AS jsonb)
  WITH FUNCTION _rrule.rrule_to_jsonb(_rrule.RRULE)
  AS IMPLICIT;


CREATE FUNCTION crm."checkProductTypeInOrderCart"(producttype text, cartinfo jsonb) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    products jsonb[];
    product jsonb;
    foundCount numeric = 0;
BEGIN
    FOR product IN SELECT jsonb_extract_path(cartinfo, 'products') LOOP
    	IF product->'type'::text = producttype THEN
    	    foundCount = foundCount + 1;
    	END IF;
    END LOOP;
    IF foundCount > 0 THEN
	    RETURN true;
	ELSE
	    RETURN false;
    END IF;
END
$$;
CREATE FUNCTION crm."checkProductTypeInOrderCartNew"(producttype text, cartinfo jsonb) RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    products jsonb;
    product jsonb;
    foundCount numeric = 0;
    retText text = null;
BEGIN
    FOR product IN SELECT jsonb_extract_path(cartinfo, 'products') LOOP
        retText = retText || product->>'type';
    END LOOP;
    RETURN retText;
END
$$;
CREATE FUNCTION crm."checkProductTypeInOrderCartNewq"(producttype text, cartinfo jsonb) RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    products jsonb[];
    product jsonb;
    foundCount numeric = 0;
    retText text;
BEGIN
    FOR product IN SELECT jsonb_extract_path(cartinfo, 'products') LOOP
        retText = retText || CAST(product->'type' AS text);
    END LOOP;
    RETURN retText;
END
$$;
CREATE FUNCTION crm."createCustomerWLR"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO crm.wallet("keycloakId", "brandId") VALUES (NEW."keycloakId", NEW."brandId");
    INSERT INTO crm."loyaltyPoint"("keycloakId", "brandId") VALUES (NEW."keycloakId", NEW."brandId");
    INSERT INTO crm."customerReferral"("keycloakId", "brandId") VALUES(NEW."keycloakId", NEW."brandId");
    RETURN NULL;
END;
$$;
CREATE FUNCTION crm."customerOrderSince"("keycloakId" text) RETURNS interval
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
time interval;
BEGIN
   SELECT age(create_at) FROM "order"."order" WHERE "order"."keycloakId" = "keycloakId" ORDER BY created_at DESC LIMIT 1;
END
$$;
CREATE TABLE crm."orderCart" (
    id integer NOT NULL,
    "cartInfo" jsonb NOT NULL,
    "customerId" integer,
    "paymentMethodId" text,
    "paymentStatus" text DEFAULT 'PENDING'::text NOT NULL,
    status text DEFAULT 'PENDING'::text NOT NULL,
    "transactionId" text,
    "orderId" integer,
    created_at timestamp with time zone DEFAULT now(),
    "stripeCustomerId" text,
    "fulfillmentInfo" jsonb,
    tip numeric DEFAULT 0 NOT NULL,
    address jsonb,
    amount numeric,
    "transactionRemark" jsonb,
    "customerInfo" jsonb,
    "customerKeycloakId" text,
    "chargeId" integer,
    "cartSource" text,
    "subscriptionOccurenceId" integer,
    updated_at timestamp with time zone DEFAULT now(),
    "walletAmount" numeric DEFAULT 0,
    "isTest" boolean DEFAULT false NOT NULL,
    "brandId" integer DEFAULT 1 NOT NULL,
    "couponDiscount" numeric DEFAULT 0 NOT NULL
);
CREATE FUNCTION crm.deliveryprice(ordercart crm."orderCart") RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    value numeric;
    total numeric;
    rangeId int;
BEGIN
    SELECT crm.itemtotal(ordercart) into total;
    IF ordercart."fulfillmentInfo"::json->>'type' LIKE '%PICKUP' OR ordercart."fulfillmentInfo" IS NULL
        THEN RETURN 0;
    END IF;
    SELECT ordercart."fulfillmentInfo"::json#>'{"slot","mileRangeId"}' as int into rangeId;
    SELECT charge from "fulfilment"."charge" WHERE charge."mileRangeId" = rangeId AND total >= charge."orderValueFrom" AND total < charge."orderValueUpto" into value;
    IF value IS NOT NULL
        THEN RETURN value;
    END IF;
    SELECT MAX(charge) from "fulfilment"."charge" WHERE charge."mileRangeId" = rangeId into value;
    IF value IS NULL
        THEN RETURN 0;
    END IF;
    RETURN value;
END
$$;
CREATE FUNCTION crm.discount(ordercart crm."orderCart") RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   totalPrice numeric;
   itemTotal numeric;
   deliveryPrice numeric;
   rewardIds int[];
   rewardId int;
   reward record;
   discount numeric := 0;
BEGIN
    SELECT crm.itemtotal(ordercart.*) into itemTotal;
    SELECT crm.deliveryprice(ordercart.*) into deliveryPrice;
    totalPrice := ROUND(itemTotal + deliveryPrice, 2);
    rewardIds := ARRAY(SELECT "rewardId" FROM crm."orderCart_rewards" WHERE "orderCartId" = ordercart.id);
    FOREACH rewardId IN ARRAY rewardIds LOOP
        SELECT * FROM crm.reward WHERE id = rewardId INTO reward;
        IF reward."type" = 'Discount'
            THEN
            IF  reward."rewardValue"->>'type' = 'conditional'
                THEN 
                discount := totalPrice * ((reward."rewardValue"->'value'->'percentage')::numeric / 100);
                IF discount >  (reward."rewardValue"->'value'->'max')::numeric
                    THEN discount := (reward."rewardValue"->'value'->'max')::numeric;
                END IF;
            ELSE
                discount := (reward."rewardValue"->'value')::numeric;
            END IF;
        END IF;
    END LOOP;
    RETURN ROUND(discount, 2);
END;
$$;
CREATE FUNCTION crm.iscartvalid(ordercart crm."orderCart") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    IF JSONB_ARRAY_LENGTH(ordercart."cartInfo"->'products') = 0
        THEN RETURN json_build_object('status', false, 'error', 'No items in cart!');
    ELSIF ordercart."customerInfo" IS NULL OR ordercart."customerInfo"->>'customerFirstName' IS NULL 
        THEN RETURN json_build_object('status', false, 'error', 'Basic customer details missing!');
    ELSIF ordercart."paymentMethodId" IS NULL OR ordercart."stripeCustomerId" IS NULL
        THEN RETURN json_build_object('status', false, 'error', 'No payment method selected!');
    ELSIF ordercart."fulfillmentInfo" IS NULL
        THEN RETURN json_build_object('status', false, 'error', 'No fulfillment mode selected!');
    ELSIF ordercart."address" IS NULL AND ordercart."fulfillmentInfo"::json->>'type' LIKE '%DELIVERY' 
        THEN RETURN json_build_object('status', false, 'error', 'No address selected for delivery!');
    ELSE
        RETURN json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE FUNCTION crm.itemtotal(ordercart crm."orderCart") RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   total numeric := 0;
BEGIN
    -- FOR product IN SELECT * FROM json_array_elements(ordercart."cartInfo"->'products')
    -- LOOP
    --     IF product->'type' = 'comboProducts'
    --         THEN FOR subproduct IN product->'products' LOOP
    --             total := total + subproduct->'product'->'price'
    --         END LOOP;
    --     ELSE
    --         total := total + product->'price'
    --     END IF;
	   -- RAISE NOTICE 'Total: %', total;
    -- END LOOP;
    RETURN ordercart."cartInfo"->'total';
END
$$;
CREATE FUNCTION crm."lastActiveDate"(keycloakid text) RETURNS timestamp without time zone
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
orderDate timestamp ;
BEGIN
  SELECT created_at FROM "order"."order" WHERE "order"."keycloakId" = keycloakId ORDER BY created_at DESC LIMIT 1 into orderDate;
  IF orderDate IS NULL 
  THEN SELECT created_at FROM "crm"."customer" WHERE "keycloakId" = keycloakId into orderDate;
  END IF;
  return orderDate;
END
$$;
CREATE FUNCTION crm."lastCustomerOrderSince"("keycloakId" text) RETURNS timestamp without time zone
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
orderDate timestamp ;
BEGIN
   SELECT created_at FROM "order"."order" WHERE "order"."keycloakId" = "keycloakId" ORDER BY created_at DESC LIMIT 1 into orderDate;
   IF orderDate IS NULL 
   THEN SELECT created_at FROM "crm"."customer" WHERE "keycloakId" = "keycloakId" into orderDate;
   END IF;
   return orderDate;
END
$$;
CREATE TABLE crm.fact (
    id integer NOT NULL
);
CREATE FUNCTION crm."loyaltyPoints"(fact crm.fact, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT crm."loyaltyPointsFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION crm."loyaltyPointsFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    loyaltyPoints integer ;
BEGIN
  SELECT "points" FROM crm."loyaltyPoint" WHERE "keycloakId" = (params->>'keycloakId')::text INTO loyaltyPoints;
  RETURN json_build_object('value', loyaltyPoints, 'valueType','integer','argument','keycloakId');
END;
$$;
CREATE FUNCTION crm."orderAmount"(fact crm.fact, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT crm."orderAmountFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION crm."orderAmountFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    orderAmount numeric;
BEGIN
  SELECT "amountPaid" FROM "order"."order" WHERE id = (params->'orderId')::integer INTO orderAmount;
  RETURN json_build_object('value', orderAmount, 'valueType','numeric','arguments','orderId');
END;
$$;
CREATE FUNCTION crm."postOrderCouponRewards"() RETURNS trigger
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    rec record;
    reward record;
    rewardIds int[];
    params jsonb;
BEGIN
    params := jsonb_build_object('keycloakId', NEW."keycloakId", 'orderId', NEW.id, 'cartId', NEW."cartId", 'campaignType', 'Post Order');
    FOR rec IN SELECT * FROM crm."orderCart_rewards" WHERE "orderCartId" = NEW."cartId" LOOP
        -- SELECT * FROM crm.reward WHERE id = rec."rewardId" INTO reward;
        -- IF reward."type" = 'Loyalty Point Credit' OR reward."type" = 'Wallet Amount Credit' THEN
        --     rewardIds := rewardIds || reward.id;
        -- END IF;
        rewardIds := rewardIds || rec."rewardId";
    END LOOP;
    IF array_length(rewardIds, 1) > 0 THEN
        PERFORM crm."processRewardsForCustomer"(rewardIds, params);
    END IF;
    RETURN NULL;
END;
$$;
CREATE FUNCTION crm."processLoyaltyPointTransaction"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW."type" = 'CREDIT'
        THEN
        UPDATE crm."loyaltyPoint"
        SET points = points + NEW.points
        WHERE id = NEW."loyaltyPointId";
    ELSE
        UPDATE crm."loyaltyPoint"
        SET points = points - NEW.points
        WHERE id = NEW."loyaltyPointId";
    END IF;
    RETURN NULL;
END;
$$;
CREATE FUNCTION crm."processRewardsForCustomer"(rewardids integer[], params jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    reward record;
    loyaltyPointId int;
    walletId int;
    pointsToBeCredited int;
    amountToBeCredited numeric;
    cartAmount numeric;
    returnedId int;
BEGIN
    FOR reward IN SELECT * FROM crm.reward WHERE id = ANY(rewardIds) LOOP
        IF reward."type" = 'Loyalty Point Credit' THEN 
            SELECT id FROM crm."loyaltyPoint" WHERE "keycloakId" = params->>'keycloakId' INTO loyaltyPointId;
            IF reward."rewardValue"->>'type' = 'absolute' THEN
                SELECT (reward."rewardValue"->>'value')::int INTO pointsToBeCredited;
            ELSIF reward."rewardValue"->>'type' = 'conditional' AND params->>'campaignType' = 'Post Order' THEN
                SELECT "amount" FROM crm."orderCart" WHERE id = (params->'cartId')::int INTO cartAmount;
                pointsToBeCredited := ROUND(cartAmount * ((reward."rewardValue"->'value'->'percentage')::numeric / 100));
                IF pointsToBeCredited > (reward."rewardValue"->'value'->'max')::numeric THEN
                    pointsToBeCredited := (reward."rewardValue"->'value'->'max')::numeric;
                END IF;
            ELSE
                CONTINUE;
            END IF;
            INSERT INTO crm."loyaltyPointTransaction" ("loyaltyPointId", "points", "type")VALUES(loyaltyPointId, pointsToBeCredited, 'CREDIT') RETURNING id INTO returnedId;
            IF reward."couponId" IS NOT NULL THEN
                INSERT INTO crm."rewardHistory"("rewardId", "couponId", "keycloakId", "orderCartId", "orderId", "loyaltyPointTransactionId", "loyaltyPoints")
                VALUES(reward.id, reward."couponId", params->>'keycloakId', (params->>'cartId')::int, (params->>'orderId')::int, returnedId, pointsToBeCredited);
            ELSE
                INSERT INTO crm."rewardHistory"("rewardId", "campaignId", "keycloakId", "orderCartId", "orderId", "loyaltyPointTransactionId", "loyaltyPoints")
                VALUES(reward.id, reward."campaignId", params->>'keycloakId', (params->>'cartId')::int, (params->>'orderId')::int, returnedId, pointsToBeCredited);
            END IF;
        ELSIF reward."type" = 'Wallet Amount Credit' THEN
            SELECT id FROM crm."wallet" WHERE "keycloakId" = params->>'keycloakId' INTO walletId;
            IF reward."rewardValue"->>'type' = 'absolute' THEN 
                SELECT (reward."rewardValue"->>'value')::int INTO amountToBeCredited;
            ELSIF reward."rewardValue"->>'type' = 'conditional' AND params->>'campaignType' = 'Post Order' THEN
                SELECT "amount" FROM crm."orderCart" WHERE id = (params->'cartId')::int INTO cartAmount;
                amountToBeCredited := ROUND(cartAmount * ((reward."rewardValue"->'value'->'percentage')::numeric / 100), 2);
                IF amountToBeCredited > (reward."rewardValue"->'value'->'max')::numeric THEN
                    amountToBeCredited := (reward."rewardValue"->'value'->'max')::numeric;
                END IF;
            ELSE
                CONTINUE;
            END IF;
            INSERT INTO crm."walletTransaction" ("walletId", "amount", "type") VALUES(walletId, amountToBeCredited, 'CREDIT') RETURNING id INTO returnedId;
            IF reward."couponId" IS NOT NULL THEN
                INSERT INTO crm."rewardHistory"("rewardId", "couponId", "keycloakId", "orderCartId", "orderId", "walletTransactionId", "walletAmount")
                VALUES(reward.id, reward."couponId", params->>'keycloakId', (params->>'cartId')::int, (params->>'orderId')::int, returnedId, amountToBeCredited);
            ELSE
                INSERT INTO crm."rewardHistory"("rewardId", "campaignId", "keycloakId", "orderCartId", "orderId", "walletTransactionId", "walletAmount")
                VALUES(reward.id, reward."campaignId", params->>'keycloakId', (params->>'cartId')::int, (params->>'orderId')::int, returnedId, amountToBeCredited);
            END IF;
        ELSIF reward."type" = 'Discount' THEN
            IF reward."couponId" IS NOT NULL THEN
                INSERT INTO crm."rewardHistory"("rewardId", "couponId", "keycloakId", "orderCartId", "orderId", "discount")
                VALUES(reward.id, reward."couponId", params->>'keycloakId', (params->>'cartId')::int, (params->>'orderId')::int, (SELECT "couponDiscount" FROM crm."orderCart" WHERE id = (params->>'cartId')::int));
            END IF;
        ELSE
            CONTINUE;
        END IF; 
    END LOOP;
END;
$$;
CREATE FUNCTION crm."processWalletTransaction"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW."type" = 'CREDIT'
        THEN
        UPDATE crm."wallet"
        SET amount = amount + NEW.amount
        WHERE id = NEW."walletId";
    ELSE
        UPDATE crm."wallet"
        SET amount = amount - NEW.amount
        WHERE id = NEW."walletId";
    END IF;
    RETURN NULL;
END;
$$;
CREATE FUNCTION crm."referralStatus"(fact crm.fact, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT crm."referralStatusFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION crm."referralStatusFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    referralStatus text ;
BEGIN
  SELECT "status" FROM crm."customerReferral" WHERE "keycloakId" = (params->>'keycloakId')::text INTO referralStatus;
  RETURN json_build_object('value', referralStatus, 'valueType','text','argument','keycloakId');
END;
$$;
CREATE FUNCTION crm."rewardsTriggerFunction"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    params jsonb;
    rewardsParams jsonb;
    campaign record;
    condition record;
    campaignType text;
    keycloakId text;
    campaignValidity boolean := false;
    rewardValidity boolean;
    finalRewardValidity boolean := true;
    reward record;
    rewardIds int[] DEFAULT '{}';
    cartId int;
    referral record;
    postOrderRewardGiven boolean := false;
BEGIN
    IF TG_TABLE_NAME = 'brandCustomer' THEN
        params := jsonb_build_object('keycloakId', NEW."keycloakId", 'brandId', NEW."brandId");
        keycloakId := NEW."keycloakId";
    ELSIF TG_TABLE_NAME = 'customerReferral' THEN
        params := jsonb_build_object('keycloakId', NEW."keycloakId", 'brandId', NEW."brandId");
        SELECT "keycloakId" FROM crm."customerReferral" WHERE "referralCode" = NEW."referredByCode" INTO keycloakId;
    ELSIF TG_TABLE_NAME = 'order' THEN
        params := jsonb_build_object('keycloakId', NEW."keycloakId", 'orderId', NEW.id::int, 'cartId', NEW."cartId", 'brandId', NEW."brandId");
        keycloakId := NEW."keycloakId";
    ELSE 
        RETURN NULL;
    END IF;
    FOR campaign IN SELECT * FROM crm."campaign" WHERE id IN (SELECT "campaignId" FROM crm."brand_campaign" WHERE "brandId" = (params->'brandId')::int AND "isActive" = true) ORDER BY priority DESC, updated_at DESC LOOP
        SELECT * FROM crm."customerReferral" WHERE "keycloakId" = params->>'keycloakId' AND "brandId" = (params->>'brandId')::int INTO referral;
        IF campaign."type" = 'Sign Up' AND referral."signupStatus" = 'COMPLETED' THEN
            CONTINUE;
        END IF;
        IF campaign."type" = 'Referral' AND (referral."referralStatus" = 'COMPLETED' OR referral."referredByCode" IS NULL) THEN
            CONTINUE;
        END IF;
        IF campaign."type" = 'Post Order' AND (params->>'cartId' IS NULL OR postOrderRewardGiven = true) THEN
            CONTINUE;
        END IF;
        SELECT rules."isConditionValidFunc"(campaign."conditionId", params) INTO campaignValidity;
        IF campaignValidity = false THEN
            CONTINUE;
        END IF;
        IF campaign."isRewardMulti" = true THEN
            FOR reward IN SELECT * FROM crm.reward WHERE "campaignId" = campaign.id LOOP
                SELECT rules."isConditionValidFunc"(reward."conditionId", params) INTO rewardValidity;
                IF rewardValidity = true THEN
                    rewardIds := rewardIds || reward.id;
                END IF;
                finalRewardValidity := finalRewardValidity AND rewardValidity;
            END LOOP;
        ELSE
            SELECT * FROM crm.reward WHERE "campaignId" = campaign.id ORDER BY priority DESC LIMIT 1 INTO reward;
            SELECT rules."isConditionValidFunc"(reward."conditionId", params) INTO rewardValidity;
            IF rewardValidity = true THEN
                rewardIds := rewardIds || reward.id;
            END IF;
            finalRewardValidity := finalRewardValidity AND rewardValidity;
        END IF;
        IF finalRewardValidity = true AND array_length(rewardIds, 1) > 0 THEN
            rewardsParams := params || jsonb_build_object('campaignType', campaign."type", 'keycloakId', keycloakId);
            PERFORM crm."processRewardsForCustomer"(rewardIds, rewardsParams);
            IF campaign."type" = 'Sign Up' THEN
                UPDATE crm."customerReferral"
                SET "signupCampaignId" = campaign.id, "signupStatus" = 'COMPLETED'
                WHERE "keycloakId" = params->>'keycloakId' AND "brandId" = (params->>'brandId')::int;
            ELSIF campaign."type" = 'Referral' THEN
                UPDATE crm."customerReferral"
                SET "referralCampaignId" = campaign.id, "referralStatus" = 'COMPLETED'
                WHERE "keycloakId" = params->>'keycloakId' AND "brandId" = (params->>'brandId')::int;
            ELSIF campaign."type" = 'Post Order' THEN
                postOrderRewardGiven := true;
            ELSE
                CONTINUE;
            END IF;
        END IF;
    END LOOP;
    RETURN NULL;
END;
$$;
CREATE FUNCTION crm.set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;
CREATE FUNCTION crm.tax(ordercart crm."orderCart") RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   taxAmount numeric := 0;
   tax numeric;
   discount numeric := 0;
   itemTotal numeric;
   deliveryPrice numeric;
BEGIN
    SELECT crm.itemtotal(ordercart.*) into itemTotal;
    SELECT crm.deliveryprice(ordercart.*) into deliveryPrice;
    SELECT crm.taxpercent(ordercart.*) into tax;
    SELECT crm.discount(ordercart.*) into discount;
    taxAmount := ROUND((itemTotal + deliveryPrice + ordercart.tip - discount) * (tax / 100), 2);
    RETURN taxAmount;
END
$$;
CREATE FUNCTION crm.taxpercent(ordercart crm."orderCart") RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   tax numeric := 0;
BEGIN
    RETURN 2.5;
END
$$;
CREATE FUNCTION crm.totalprice(ordercart crm."orderCart") RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   totalPrice numeric;
   tax numeric;
   itemTotal numeric;
   deliveryPrice numeric;
   discount numeric;
BEGIN
    SELECT crm.itemtotal(ordercart.*) into itemTotal;
    SELECT crm.deliveryprice(ordercart.*) into deliveryPrice;
    SELECT crm.tax(ordercart.*) into tax;
    SELECT crm.discount(ordercart.*) into discount;
    totalPrice := ROUND(itemTotal + deliveryPrice + ordercart.tip - COALESCE(ordercart."walletAmount", 0) + tax - discount, 2);
    RETURN totalPrice;
END
$$;
CREATE FUNCTION "deviceHub".set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;
CREATE TABLE fulfilment."mileRange" (
    id integer NOT NULL,
    "from" numeric,
    "to" numeric,
    "leadTime" integer,
    "prepTime" integer,
    "isActive" boolean DEFAULT true NOT NULL,
    "timeSlotId" integer,
    zipcodes jsonb
);
CREATE FUNCTION fulfilment."preOrderDeliveryValidity"(milerange fulfilment."mileRange", "time" time without time zone) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    fromVal time;
    toVal time;
BEGIN
    SELECT "from" into fromVal FROM fulfilment."timeSlot" WHERE id = mileRange."timeSlotId";
    SELECT "to" into toVal FROM fulfilment."timeSlot" WHERE id = mileRange."timeSlotId";
    RETURN true;
END
$$;
CREATE TABLE fulfilment."timeSlot" (
    id integer NOT NULL,
    "recurrenceId" integer,
    "isActive" boolean DEFAULT true NOT NULL,
    "from" time without time zone,
    "to" time without time zone,
    "pickUpLeadTime" integer DEFAULT 120,
    "pickUpPrepTime" integer DEFAULT 30
);
CREATE FUNCTION fulfilment."preOrderPickupTimeFrom"(timeslot fulfilment."timeSlot") RETURNS time without time zone
    LANGUAGE plpgsql STABLE
    AS $$
  -- SELECT "from".timeslot AS fromtime, "pickupLeadTime".timeslot AS buffer, diff(fromtime, buffer) as "pickupFromTime"
  BEGIN
  return ("from".timeslot - "pickupLeadTime".timeslot);
  END
$$;
CREATE FUNCTION fulfilment."preOrderPickupValidity"(timeslot fulfilment."timeSlot", "time" time without time zone) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    -- IF JSONB_ARRAY_LENGTH(ordercart."cartInfo"->'products') = 0
    --     THEN RETURN json_build_object('status', false, 'error', 'No items in cart!');
    -- ELSIF ordercart."paymentMethodId" IS NULL OR ordercart."stripeCustomerId" IS NULL
    --     THEN RETURN json_build_object('status', false, 'error', 'No payment method selected!');
    -- ELSIF ordercart."address" IS NULL
    --     THEN RETURN json_build_object('status', false, 'error', 'No address selected!');
    -- ELSE
        RETURN true;
    -- END IF;
END
$$;
CREATE FUNCTION fulfilment.set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;
CREATE FUNCTION ingredient."MOFCost"(mofid integer) RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    mof record;
    bulkItemId int;
    supplierItemId int;
    supplierItem record;
    costs jsonb;
BEGIN
    SELECT * FROM ingredient."modeOfFulfillment" WHERE id = mofId into mof;
    IF mof."bulkItemId" IS NOT NULL
        THEN SELECT mof."bulkItemId" into bulkItemId;
    ELSE
        SELECT bulkItemId FROM inventory."sachetItem" WHERE id = mof."sachetItemId" into bulkItemId;
    END IF;
    SELECT "supplierItemId" FROM inventory."bulkItem" WHERE id = bulkItemId into supplierItemId;
    SELECT * FROM inventory."supplierItem" WHERE id = supplierItemId into supplierItem;
    IF supplierItem.prices IS NULL
        THEN RETURN 0;
    ELSE
        RETURN (supplierItem.prices->0->'unitPrice'->>'value')::numeric/supplierItem."unitSize";
    END IF;
END
$$;
CREATE FUNCTION ingredient."MOFNutritionalInfo"(mofid integer) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    info jsonb;
    mof record;
    bulkItemId int;
BEGIN
    SELECT * FROM ingredient."modeOfFulfillment" WHERE id = mofId into mof;
    IF mof."bulkItemId" IS NOT NULL
        THEN SELECT "nutritionInfo" FROM inventory."bulkItem" WHERE id = mof."bulkItemId" into info;
        RETURN info;
    ELSE
        SELECT bulkItemId FROM inventory."sachetItem" WHERE id = mof."sachetItemId" into bulkItemId;
        SELECT "nutritionInfo" FROM inventory."bulkItem" WHERE id = bulkItemId into info;
        RETURN info;
    END IF;
END
$$;
CREATE TABLE ingredient."ingredientSachet" (
    id integer NOT NULL,
    quantity numeric NOT NULL,
    "ingredientProcessingId" integer NOT NULL,
    "ingredientId" integer NOT NULL,
    "createdAt" timestamp with time zone DEFAULT now(),
    "updatedAt" timestamp with time zone DEFAULT now(),
    tracking boolean DEFAULT true NOT NULL,
    unit text NOT NULL,
    visibility boolean DEFAULT true NOT NULL,
    "liveMOF" integer
);
CREATE FUNCTION ingredient.cost(sachet ingredient."ingredientSachet") RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    cost numeric;
BEGIN
    SELECT ingredient."sachetCost"(sachet.id) into cost;
    RETURN cost;
END
$$;
CREATE TABLE ingredient."modeOfFulfillment" (
    id integer NOT NULL,
    type text NOT NULL,
    "stationId" integer,
    "labelTemplateId" integer,
    "bulkItemId" integer,
    "isPublished" boolean DEFAULT false NOT NULL,
    priority integer NOT NULL,
    "ingredientSachetId" integer NOT NULL,
    "packagingId" integer,
    "isLive" boolean DEFAULT false NOT NULL,
    accuracy integer,
    "sachetItemId" integer
);
CREATE FUNCTION ingredient."getMOFCost"(mof ingredient."modeOfFulfillment") RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    cost numeric;
BEGIN
    SELECT ingredient."MOFCost"(mof.id) into cost;
    RETURN cost;
END
$$;
CREATE FUNCTION ingredient."getMOFNutritionalInfo"(mof ingredient."modeOfFulfillment") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    info jsonb;
BEGIN
    SELECT ingredient."MOFNutritionalInfo"(mof.id) into info;
    RETURN info;
END
$$;
CREATE TABLE ingredient.ingredient (
    id integer NOT NULL,
    name text NOT NULL,
    image text,
    "isPublished" boolean DEFAULT false NOT NULL,
    category text,
    "createdAt" date DEFAULT now()
);
CREATE FUNCTION ingredient.image_validity(ing ingredient.ingredient) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT NOT(ing.image IS NULL)
$$;
CREATE FUNCTION ingredient.imagevalidity(image ingredient.ingredient) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
    SELECT NOT(image.image IS NULL)
$$;
CREATE FUNCTION ingredient.isingredientvalid(ingredient ingredient.ingredient) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    temp jsonb;
BEGIN
    SELECT * FROM ingredient."ingredientSachet" where "ingredientId" = ingredient.id LIMIT 1 into temp;
    IF temp IS NULL
        THEN return json_build_object('status', false, 'error', 'Not sachet present');
    ELSIF ingredient.category IS NULL
        THEN return json_build_object('status', false, 'error', 'Category not provided');
    ELSIF ingredient.image IS NULL OR LENGTH(ingredient.image) = 0
        THEN return json_build_object('status', true, 'error', 'Image not provided');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE FUNCTION ingredient.ismodevalid(mode ingredient."modeOfFulfillment") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  temp json;
  isSachetValid boolean;
BEGIN
    SELECT ingredient.isSachetValid("ingredientSachet".*) 
        FROM ingredient."ingredientSachet"
        WHERE "ingredientSachet".id = mode."ingredientSachetId" into temp;
    SELECT temp->'status' into isSachetValid;
    IF NOT isSachetValid
        THEN return json_build_object('status', false, 'error', 'Sachet is not valid');
    ELSIF mode."stationId" IS NULL
        THEN return json_build_object('status', false, 'error', 'Station is not provided');
    ELSIF mode."bulkItemId" IS NULL AND mode."sachetItemId" IS NULL
        THEN return json_build_object('status', false, 'error', 'Item is not provided');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE FUNCTION ingredient.issachetvalid(sachet ingredient."ingredientSachet") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  temp json;
  isIngredientValid boolean;
BEGIN
    SELECT ingredient.isIngredientValid(ingredient.*) FROM ingredient.ingredient where ingredient.id = sachet."ingredientId" into temp;
    SELECT temp->'status' into isIngredientValid;
    IF NOT isIngredientValid
        THEN return json_build_object('status', false, 'error', 'Ingredient is not valid');
    -- ELSIF sachet."defaultNutritionalValues" IS NULL
    --     THEN return json_build_object('status', true, 'error', 'Default nutritional values not provided');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE TABLE "simpleRecipe"."simpleRecipe" (
    id integer NOT NULL,
    author text,
    name jsonb NOT NULL,
    procedures jsonb,
    "cookingTime" text,
    utensils jsonb,
    description text,
    cuisine text,
    image text,
    show boolean DEFAULT true NOT NULL,
    assets jsonb,
    ingredients jsonb,
    type text,
    "isPublished" boolean DEFAULT false NOT NULL
);
CREATE FUNCTION ingredient.issimplerecipevalid(recipe "simpleRecipe"."simpleRecipe") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
BEGIN
    -- SELECT ingredient.isSachetValid("ingredientSachet".*) 
    --     FROM ingredient."ingredientSachet"
    --     WHERE "ingredientSachet".id = mode."ingredientSachetId" into temp;
    -- SELECT temp->'status' into isSachetValid;
    IF recipe.utensils IS NULL OR ARRAY_LENGTH(recipe.utensils) = 0
        THEN return json_build_object('status', false, 'error', 'Utensils not provided');
    ELSIF recipe.procedures IS NULL OR ARRAY_LENGTH(recipe.procedures) = 0
        THEN return json_build_object('status', false, 'error', 'Cooking steps are not provided');
    ELSIF recipe.ingredients IS NULL OR ARRAY_LENGTH(recipe.ingredients) = 0
        THEN return json_build_object('status', false, 'error', 'Ingrdients are not provided');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE FUNCTION ingredient."nutritionalInfo"(sachet ingredient."ingredientSachet") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    info jsonb;
BEGIN
    SELECT ingredient."sachetNutritionalInfo"(sachet.id) into info;
    RETURN info;
END
$$;
CREATE FUNCTION ingredient."sachetCost"(sachetid integer) RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    sachet record;
    mofId int;
    temp numeric;
BEGIN
    SELECT * FROM ingredient."ingredientSachet" WHERE id = sachetId INTO sachet;
    SELECT id FROM ingredient."modeOfFulfillment" WHERE "ingredientSachetId" = sachetId ORDER BY priority DESC LIMIT 1 INTO mofId;
    SELECT ingredient."MOFCost"(mofId) INTO temp;
    IF temp IS NULL OR temp = 0
        THEN SELECT "cost"->'value' FROM ingredient."ingredientProcessing" WHERE id = sachet."ingredientProcessingId" INTO temp;
    END IF;
    IF temp IS NULL
        THEN RETURN 0;
    ELSE
        RETURN temp*sachet.quantity;
    END IF;
END
$$;
CREATE FUNCTION ingredient."sachetNutritionalInfo"(sachet ingredient."ingredientSachet") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    info jsonb;
BEGIN
    SELECT "nutritionalInfo" FROM ingredient."ingredientProcessing" WHERE id = sachet."ingredientProcessingId" into info;
    RETURN info;
END
$$;
CREATE FUNCTION ingredient."sachetNutritionalInfo"(sachetid integer) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    info jsonb;
    sachet record;
    mofId int;
    per numeric;
BEGIN
    SELECT * FROM ingredient."ingredientSachet" WHERE id = sachetId INTO sachet;
    SELECT id FROM ingredient."modeOfFulfillment" WHERE "ingredientSachetId" = sachetId ORDER BY priority DESC LIMIT 1 INTO mofId;
    SELECT ingredient."MOFNutritionalInfo"(mofId) INTO info;
    IF info IS NULL
        THEN SELECT "nutritionalInfo" FROM ingredient."ingredientProcessing" WHERE id = sachet."ingredientProcessingId" INTO info;
    END IF;
    IF info IS NULL
        THEN RETURN info;
    ELSE
        SELECT COALESCE((info->>'per')::numeric, 1) into per;
        RETURN json_build_object(
            'per', per,
            'iron', COALESCE((info->>'iron')::numeric, 0) * (sachet.quantity)::numeric/per,
            'sodium', COALESCE((info->>'sodium')::numeric, 0) * (sachet.quantity)::numeric/per,
            'sugars', COALESCE((info->>'sugars')::numeric, 0) * (sachet.quantity)::numeric/per,
            'calcium', COALESCE((info->>'calcium')::numeric, 0) * (sachet.quantity)::numeric/per,
            'protein', COALESCE((info->>'protein')::numeric, 0) * (sachet.quantity)::numeric/per,
            'calories', COALESCE((info->>'calories')::numeric, 0) * (sachet.quantity)::numeric/per,
            'totalFat', COALESCE((info->>'totalFat')::numeric, 0) * (sachet.quantity)::numeric/per,
            'transFat', COALESCE((info->>'transFat')::numeric, 0) * (sachet.quantity)::numeric/per,
            'vitaminA', COALESCE((info->>'vitaminA')::numeric, 0) * (sachet.quantity)::numeric/per,
            'vitaminC', COALESCE((info->>'vitaminC')::numeric, 0) * (sachet.quantity)::numeric/per,
            'cholesterol', COALESCE((info->>'cholesterol')::numeric, 0) * (sachet.quantity)::numeric/per,
            'dietaryFibre', COALESCE((info->>'dietaryFibre')::numeric, 0) * (sachet.quantity)::numeric/per,
            'saturatedFat', COALESCE((info->>'saturatedFat')::numeric, 0) * (sachet.quantity)::numeric/per,
            'totalCarbohydrates', COALESCE((info->>'totalCarbohydrates')::numeric, 0) * (sachet.quantity)::numeric/per
        );
    END IF;
END
$$;
CREATE FUNCTION ingredient.sachetvalidity(sachet ingredient."ingredientSachet") RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT NOT(sachet.unit IS NULL OR sachet.quantity <= 0)
$$;
CREATE FUNCTION ingredient."set_current_timestamp_updatedAt"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updatedAt" = NOW();
  RETURN _new;
END;
$$;
CREATE FUNCTION ingredient.twiceq(sachet ingredient."ingredientSachet") RETURNS numeric
    LANGUAGE sql STABLE
    AS $$
  SELECT sachet.quantity*2
$$;
CREATE FUNCTION ingredient.validity(sachet ingredient."ingredientSachet") RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT NOT(sachet.unit IS NULL OR sachet.quantity <= 0)
$$;
CREATE FUNCTION insights.set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;
CREATE FUNCTION inventory."set_current_timestamp_updatedAt"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updatedAt" = NOW();
  RETURN _new;
END;
$$;
CREATE FUNCTION inventory.set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;
CREATE FUNCTION notifications.set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;
CREATE TABLE "onDemand".menu (
    id integer NOT NULL,
    data jsonb
);
CREATE FUNCTION "onDemand"."getMenu"(params jsonb) RETURNS SETOF "onDemand".menu
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    colId int;
    menu jsonb[];
    cleanMenu jsonb[] DEFAULT '{}';
    r jsonb;
    collection jsonb;
    isValid jsonb;
    category jsonb;
    productCategory record;
    product record;
    oldObject jsonb;
    newObject jsonb;
    exists boolean := false;
    index int;
    i int;
    arr int[];
BEGIN
    FOR colId IN SELECT "collectionId" FROM "onDemand"."brand_collection" WHERE "brandId" = (params->>'brandId')::int AND "isActive" = true LOOP
        SELECT "onDemand"."isCollectionValid"(colId, params) INTO isValid;
        -- RETURN QUERY SELECT 1 AS id, jsonb_build_object('menu', isValid) AS data;
        IF (isValid->'status')::boolean = true THEN
            FOR productCategory IN SELECT * FROM "onDemand"."collection_productCategory" WHERE "collectionId" = colId LOOP
                category := jsonb_build_object(
                    'name', productCategory."productCategoryName", 
                    'inventoryProducts', '{}',
                    'simpleRecipeProducts', '{}',
                    'customizableProducts', '{}',
                    'comboProducts', '{}'
                );
                FOR product IN SELECT * FROM "onDemand"."collection_productCategory_product" WHERE "collection_productCategoryId" = productCategory.id LOOP
                    IF product."simpleRecipeProductId" IS NOT NULL THEN
                        category := category || jsonb_build_object('simpleRecipeProducts', (REPLACE(REPLACE(category->>'simpleRecipeProducts', ']', '}'), '[', '{'))::int[] || product."simpleRecipeProductId");
                    ELSIF product."inventoryProductId" IS NOT NULL THEN
                        category := category || jsonb_build_object('inventoryProducts', (REPLACE(REPLACE(category->>'inventoryProducts', ']', '}'), '[', '{'))::int[] || product."inventoryProductId");
                    ELSIF product."customizableProductId" IS NOT NULL THEN
                        category := category || jsonb_build_object('customizableProducts', (REPLACE(REPLACE(category->>'customizableProducts', ']', '}'), '[', '{'))::int[] || product."customizableProductId");
                    ELSIF product."comboProductId" IS NOT NULL THEN
                        category := category || jsonb_build_object('comboProducts', (REPLACE(REPLACE(category->>'comboProducts', ']', '}'), '[', '{'))::int[] || product."comboProductId"); 
                    ELSE
                        CONTINUE;
                    END IF;
                    -- RETURN QUERY SELECT 1 AS id, jsonb_build_object('menu', product.id) AS data;
                END LOOP;
                -- RETURN QUERY SELECT category->>'name' AS name, category->'comboProducts' AS "comboProducts",  category->'customizableProducts' AS "customizableProducts", category->'simpleRecipeProducts' AS "simpleRecipeProducts", category->'inventoryProducts' AS "inventoryProducts";
                menu := menu || category;
            END LOOP;
        ELSE
            CONTINUE;
        END IF;
    END LOOP;
    -- RETURN;
    FOREACH oldObject IN ARRAY(menu) LOOP
        exists := false;
        i := NULL;
        IF array_length(cleanMenu, 1) IS NOT NULL THEN
            FOR index IN 0..array_length(cleanMenu, 1) LOOP
                IF cleanMenu[index]->>'name' = oldObject->>'name' THEN
                    exists := true;
                    i := index; 
                    EXIT;
                ELSE
                    CONTINUE;
                END IF;
            END LOOP;
        END IF;
        IF exists = true THEN
            cleanMenu[i] := jsonb_build_object(
                'name', cleanMenu[i]->>'name',
                'simpleRecipeProducts', (REPLACE(REPLACE(cleanMenu[i]->>'simpleRecipeProducts', ']', '}'), '[', '{'))::int[] || (REPLACE(REPLACE(oldObject->>'simpleRecipeProducts', ']', '}'), '[', '{'))::int[],
                'inventoryProducts', (REPLACE(REPLACE(cleanMenu[i]->>'inventoryProducts', ']', '}'), '[', '{'))::int[] || (REPLACE(REPLACE(oldObject->>'inventoryProducts', ']', '}'), '[', '{'))::int[],
                'customizableProducts', (REPLACE(REPLACE(cleanMenu[i]->>'customizableProducts', ']', '}'), '[', '{'))::int[] || (REPLACE(REPLACE(oldObject->>'customizableProducts', ']', '}'), '[', '{'))::int[],
                'comboProducts', (REPLACE(REPLACE(cleanMenu[i]->>'comboProducts', ']', '}'), '[', '{'))::int[] || (REPLACE(REPLACE(oldObject->>'comboProducts', ']', '}'), '[', '{'))::int[]
            );
            -- RETURN QUERY SELECT 1 AS id, jsonb_build_object('menu', cleanMenu[i]) AS data;
        ELSE
            cleanMenu := cleanMenu || oldObject;
        END IF;
    END LOOP;
    IF array_length(cleanMenu, 1) IS NOT NULL THEN
        FOR index IN 0..array_length(cleanMenu, 1) LOOP
            IF cleanMenu[index]->>'simpleRecipeProducts' = '{}' THEN
                cleanMenu[index] := cleanMenu[index] || jsonb_build_object('simpleRecipeProducts', (cleanMenu[index]->>'simpleRecipeProducts')::int[]);
            END IF;
            IF cleanMenu[index]->>'inventoryProducts' = '{}' THEN
                cleanMenu[index] := cleanMenu[index] || jsonb_build_object('inventoryProducts', (cleanMenu[index]->>'inventoryProducts')::int[]);
            END IF;
            IF cleanMenu[index]->>'customizableProducts' = '{}' THEN
                cleanMenu[index] := cleanMenu[index] || jsonb_build_object('customizableProducts', (cleanMenu[index]->>'customizableProducts')::int[]);
            END IF;
            IF cleanMenu[index]->>'comboProducts' = '{}' THEN
                cleanMenu[index] := cleanMenu[index] || jsonb_build_object('comboProducts', (cleanMenu[index]->>'comboProducts')::int[]);
            END IF;
        END LOOP;
    END IF;
    RETURN QUERY SELECT 1 AS id, jsonb_build_object('menu', cleanMenu) AS data;
END;
$$;
CREATE TABLE "onDemand"."collection_productCategory_product" (
    "collection_productCategoryId" integer NOT NULL,
    "simpleRecipeProductId" integer,
    "inventoryProductId" integer,
    "comboProductId" integer,
    "customizableProductId" integer,
    id integer NOT NULL
);
CREATE FUNCTION "onDemand"."getProductDetails"(rec "onDemand"."collection_productCategory_product") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    product record;
    productName text;
    productType text;
    productImage text;
BEGIN
    IF rec."simpleRecipeProductId" IS NOT NULL THEN
        SELECT * FROM products."simpleRecipeProduct" WHERE id = rec."simpleRecipeProductId" INTO product;
        productName := product.name;
        productType := 'simpleRecipeProduct';
        productImage := 'https://images.unsplash.com/photo-1575808142341-e39853744dbd?ixlib=rb-1.2.1&ixid=eyJhcHBfaWQiOjEyMDd9&auto=format&fit=crop&w=842&q=80';
    ELSIF rec."inventoryProductId" IS NOT NULL THEN
        SELECT * FROM products."inventoryProduct" WHERE id = rec."inventoryProductId" INTO product;
        productName := product.name;
        productType := 'inventoryProduct';
        productImage := 'https://images.unsplash.com/photo-1575808142341-e39853744dbd?ixlib=rb-1.2.1&ixid=eyJhcHBfaWQiOjEyMDd9&auto=format&fit=crop&w=842&q=80';
    ELSEIF rec."customizableProductId" IS NOT NULL THEN
        SELECT * FROM products."customizableProduct" WHERE id = rec."customizableProductId" INTO product;
        productName := product.name;
        productType := 'customizableProduct';
        productImage := 'https://images.unsplash.com/photo-1575808142341-e39853744dbd?ixlib=rb-1.2.1&ixid=eyJhcHBfaWQiOjEyMDd9&auto=format&fit=crop&w=842&q=80';
    ELSE
        SELECT * FROM products."comboProduct" WHERE id = rec."comboProductId" INTO product;
        productName := product.name;
        productType := 'comboProduct';
        productImage := 'https://images.unsplash.com/photo-1575808142341-e39853744dbd?ixlib=rb-1.2.1&ixid=eyJhcHBfaWQiOjEyMDd9&auto=format&fit=crop&w=842&q=80';
    END IF;
    RETURN jsonb_build_object(
        'name', productName,
        'type', productType,
        'image', productImage
    );
END
$$;
CREATE FUNCTION "onDemand"."isCollectionValid"(collectionid integer, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    res jsonb;
    collection record;
    isValid boolean := false;
BEGIN
    IF params->>'date' IS NOT NULL THEN
        SELECT * FROM "onDemand"."collection" WHERE id = collectionId INTO collection;
        IF collection."rrule" IS NOT NULL THEN
            SELECT rules."rruleHasDateFunc"(collection."rrule"::_rrule.rruleset, (params->>'date')::timestamp) INTO isValid;
        ELSE
            isValid := true;
        END IF;
    END IF;
    res := jsonb_build_object('status', isValid);
    return res;
END;
$$;
CREATE FUNCTION "onDemand"."numberOfCategories"(colid integer) RETURNS integer
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    res int;
BEGIN
    SELECT COUNT(*) FROM "onDemand"."collection_productCategory" WHERE "collectionId" = colId INTO res;
    RETURN res;
END;
$$;
CREATE FUNCTION "onDemand"."numberOfProducts"(colid integer) RETURNS integer
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    arr int[] := '{}';
    res int;
    rec record;
BEGIN
    FOR rec IN SELECT id FROM "onDemand"."collection_productCategory" WHERE "collectionId" = colId LOOP
        arr := arr || rec.id;
    END LOOP;
    SELECT COUNT(*) FROM "onDemand"."collection_productCategory_product" WHERE "collection_productCategoryId" = ANY(arr) INTO res;
    return res;
END;
$$;
CREATE FUNCTION "onlineStore"."SRPCartItem"("productId" integer, "optionId" integer) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    product jsonb;
    option jsonb;
BEGIN
    SELECT json_build_object(
                'id', id,
                'name', "name",
                'image', "assets"->'images'->0
        ) FROM "onlineStore"."simpleRecipeProduct" WHERE id = "productId" into product;
    SELECT json_build_object(
            'id', id,
            'type', "type",
            'price', CAST ("price"->0->>'value' AS numeric),
            'discount', CAST ("price"->0->>'discount' AS numeric)
        ) FROM "onlineStore"."simpleRecipeProductOption" WHERE id = "optionId" AND "simpleRecipeProductId" = "productId" into option;
    IF option is NULL
        THEN  RETURN json_build_object('error', 'Incorrect option ID', 'id', "optionId");
    ELSE
        RETURN json_build_object(
        'id', product->>'id',
        'name', product->>'name',
        'type', 'simpleRecipeProduct',
        'image', product->>'image',
        'option', option,
        'discount', option->'discount',
        'quantity', 1,
        'unitPrice', option->'price',
        'cartItemId', gen_random_uuid(),
        'totalPrice', option->'price',
        'specialInstructions', ''
    );
    END IF;
END
$$;
CREATE TABLE "onDemand".collection (
    id integer NOT NULL,
    name text,
    "startTime" time without time zone,
    "endTime" time without time zone,
    rrule jsonb
);
CREATE FUNCTION "onlineStore"."isCollectionValid"(rec "onDemand".collection, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    res jsonb;
    isValid boolean := false;
BEGIN
    IF params->>'date' IS NOT NULL THEN
        IF rec.rrule IS NOT NULL THEN
            SELECT rules."rruleHasDateFunc"(rec.rrule::_rrule.rruleset, (params->>'date')::timestamp) INTO isValid;
        ELSE
            isValid := true;
        END IF;
    END IF;
    res := jsonb_build_object('status', isValid);
    return res;
END;
$$;
CREATE FUNCTION "onlineStore"."isCollectionValid"(collectionid integer, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    res jsonb;
    collection record;
    isValid boolean := false;
BEGIN
    IF params->>'date' IS NOT NULL THEN
        SELECT * FROM "onlineStore"."collection" WHERE id = collectionId INTO collection;
        IF collection."rrule" IS NOT NULL THEN
            SELECT rules."rruleHasDateFunc"(collection."rrule"::_rrule.rruleset, (params->>'date')::timestamp) INTO isValid;
        ELSE
            isValid := true;
        END IF;
    END IF;
    res := jsonb_build_object('status', isValid);
    return res;
END;
$$;
CREATE FUNCTION "onlineStore"."isCollectionValid"(collection jsonb, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    res jsonb;
    isValid boolean := false;
BEGIN
    IF params->>'date' IS NOT NULL THEN
        IF collection->'rrule' IS NOT NULL THEN
            SELECT rules."rruleHasDateFunc"(collection->'rrule'::_rrule.rruleset, (params->>'date')::timestamp) INTO isValid;
        ELSE
            isValid := true;
        END IF;
    END IF;
    res := jsonb_build_object('status', isValid);
    return res;
END;
$$;
CREATE TABLE "onlineStore"."menuCollection" (
    id integer NOT NULL,
    name text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    availability jsonb,
    "sortOrder" integer,
    categories jsonb,
    store jsonb,
    "isPublished" boolean DEFAULT false NOT NULL
);
CREATE FUNCTION "onlineStore".ismenucollectionvalid(collection "onlineStore"."menuCollection") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    -- temp json;
    -- isSachetValid boolean;
BEGIN
    IF jsonb_array_length(collection.categories) = 0
        THEN return json_build_object('status', false, 'error', 'No categories provided');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE TABLE "onlineStore"."rmkCollection" (
    id integer NOT NULL,
    name text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    availability text NOT NULL,
    "sortOrder" integer,
    categories jsonb NOT NULL,
    store jsonb NOT NULL,
    "isPublished" boolean DEFAULT false NOT NULL
);
CREATE FUNCTION "onlineStore".isrmkcollectionvalid(collection "onlineStore"."rmkCollection") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    -- temp json;
    -- isSachetValid boolean;
BEGIN
    IF jsonb_array_length(collection.categories) = 0
        THEN return json_build_object('status', false, 'error', 'No categories provided');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE TABLE "order"."orderSachet" (
    id integer NOT NULL,
    "ingredientName" text NOT NULL,
    quantity numeric NOT NULL,
    unit text NOT NULL,
    "labelTemplateId" text,
    "processingName" text NOT NULL,
    "bulkItemId" integer,
    "sachetItemId" integer,
    "ingredientSachetId" integer NOT NULL,
    "packingStationId" integer,
    status text NOT NULL,
    "isLabelled" boolean DEFAULT false NOT NULL,
    "isPortioned" boolean DEFAULT false NOT NULL,
    "packagingId" integer,
    "orderMealKitProductId" integer,
    "isAssembled" boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    "orderReadyToEatProductId" integer,
    accuracy integer
);
CREATE PROCEDURE "order"."checkOrderAssemblyStatus"(sachet "order"."orderSachet")
    LANGUAGE plpgsql
    AS $$
DECLARE
    sachetItem record;
    assembledCount numeric = 0;
    pendingCount numeric = 0;
BEGIN
    IF sachet."orderMealKitProductId" IS NOT NULL
    THEN
        FOR sachetItem IN SELECT * FROM "order"."orderSachet" WHERE "orderMealKitProductId" = sachet."orderMealKitProductId" LOOP
            IF sachetItem."isAssembled" = false THEN
                pendingCount = pendingCount + 1;
            ELSE
                assembledCount = assembledCount + 1;
            END IF;
        END LOOP;
    END IF;
    UPDATE "order"."orderMealKitProduct"
    SET "order"."assemblyStatus" = 'READY'
    WHERE id = sachet."orderMealKitProductId";
END
$$;
CREATE FUNCTION "order".check_main_order_status_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    productOrder record;
    assemblyStatusPendingCount numeric = 0;
    isAssembledFalseCount numeric = 0;
BEGIN
    FOR productOrder IN SELECT * FROM "order"."orderMealKitProduct" WHERE "orderId" = NEW."orderId" LOOP
        IF productOrder."assemblyStatus" != 'COMPLETED' THEN
            assemblyStatusPendingCount = assemblyStatusPendingCount + 1;
        END IF;
        IF productOrder."isAssembled" = false THEN
            isAssembledFalseCount = isAssembledFalseCount + 1;
        END IF;
    END LOOP;
    FOR productOrder IN SELECT * FROM "order"."orderInventoryProduct" WHERE "orderId" = NEW."orderId" LOOP
        IF productOrder."assemblyStatus" != 'COMPLETED' THEN
            assemblyStatusPendingCount = assemblyStatusPendingCount + 1;
        END IF;
        IF productOrder."isAssembled" = false THEN
            isAssembledFalseCount = isAssembledFalseCount + 1;
        END IF;
    END LOOP;
    FOR productOrder IN SELECT * FROM "order"."orderReadyToEatProduct" WHERE "orderId" = NEW."orderId" LOOP
        IF productOrder."assemblyStatus" != 'COMPLETED' THEN
            assemblyStatusPendingCount = assemblyStatusPendingCount + 1;
        END IF;
        IF productOrder."isAssembled" = false THEN
            isAssembledFalseCount = isAssembledFalseCount + 1;
        END IF;
    END LOOP;
    IF assemblyStatusPendingCount > 0 THEN
        UPDATE "order"."order"
        SET "orderStatus" = 'UNDER_PROCESSING'
        WHERE id = NEW."orderId";
    ELSIF ((assemblyStatusPendingCount = 0) AND (isAssembledFalseCount > 0)) THEN
        UPDATE "order"."order"
        SET "orderStatus" = 'READY_TO_ASSEMBLE'
        WHERE id = NEW."orderId";
    ELSIF ((assemblyStatusPendingCount = 0) AND (isAssembledFalseCount = 0)) THEN
        UPDATE "order"."order"
        SET "orderStatus" = 'READY_TO_DISPATCH'
        WHERE id = NEW."orderId";
    END IF;
    RETURN NULL;
END;
$$;
CREATE FUNCTION "order".check_order_status_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    sachetItem record;
    packedCount numeric = 0;
    pendingCount numeric = 0;
    assemblePending numeric = 0;
    assembleDone numeric = 0;
BEGIN
    IF NEW."orderMealKitProductId" IS NOT NULL
    THEN
        FOR sachetItem IN SELECT * FROM "order"."orderSachet" WHERE "orderMealKitProductId" = NEW."orderMealKitProductId" LOOP
            IF sachetItem.status = 'PENDING' THEN
                pendingCount = pendingCount + 1;
            ELSE
                packedCount = packedCount + 1;
            END IF;
            IF sachetItem."isAssembled" = false THEN
                assemblePending = assemblePending + 1;
            ELSE
                assembleDone = assembleDone + 1;
            END IF;
        END LOOP;
    END IF;
    IF pendingCount > 0 THEN
        UPDATE "order"."orderMealKitProduct"
        SET "assemblyStatus" = 'PENDING'
        WHERE id = NEW."orderMealKitProductId";
    ELSIF ((pendingCount = 0) AND (assemblePending > 0)) THEN
        UPDATE "order"."orderMealKitProduct"
        SET "assemblyStatus" = 'READY'
        WHERE id = NEW."orderMealKitProductId";
    ELSIF ((pendingCount = 0) AND (assemblePending = 0)) THEN
        UPDATE "order"."orderMealKitProduct"
        SET "assemblyStatus" = 'COMPLETED'
        WHERE id = NEW."orderMealKitProductId";
    END IF;
    RETURN NULL;
END;
$$;
CREATE FUNCTION "order"."isOrderReadyForAssembly"(sachet "order"."orderSachet") RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    sachetItem record;
    packedCount numeric = 0;
    pendingCount numeric = 0;
BEGIN
    IF sachet."orderMealKitProductId" IS NOT NULL
    THEN
        FOR sachetItem IN SELECT * FROM "order"."orderSachet" WHERE "orderMealKitProductId" = sachet."orderMealKitProductId" LOOP
            IF sachetItem.status = 'PENDING' THEN
                pendingCount = pendingCount + 1;
            ELSE
                packedCount = packedCount + 1;
            END IF;
        END LOOP;
        IF pendingCount > 0 THEN
            RETURN false;
        ELSE
            RETURN true;
        END IF;
    ELSE
        RETURN false;
    END IF;
END
$$;
CREATE FUNCTION "order"."orderAssemblyStatus"(sachet "order"."orderSachet") RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    sachetItem record;
    assembledCount numeric = 0;
    pendingCount numeric = 0;
BEGIN
    IF sachet."orderMealKitProductId" IS NOT NULL
    THEN
        FOR sachetItem IN SELECT * FROM "order"."orderSachet" WHERE "orderMealKitProductId" = sachet."orderMealKitProductId" LOOP
            IF sachetItem."isAssembled" = false THEN
                pendingCount = pendingCount + 1;
            ELSE
                assembledCount = assembledCount + 1;
            END IF;
        END LOOP;
        IF pendingCount > 0 THEN
            RETURN false;
        ELSE
            RETURN true;
        END IF;
    ELSE
        RETURN false;
    END IF;
END
$$;
CREATE FUNCTION "order"."orderSachet"(sachet "order"."orderSachet") RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    sachetItem record;
    packedCount numeric = 0;
    pendingCount numeric = 0;
BEGIN
    IF sachet."orderMealKitProductId" IS NOT NULL
    THEN
        FOR sachetItem IN SELECT * FROM "order"."orderSachet" WHERE "orderMealKitProductId" = sachet."orderMealKitProductId" LOOP
            IF sachetItem.status = 'PENDING' THEN
                pendingCount = pendingCount + 1;
            ELSE
                packedCount = packedCount + 1;
            END IF;
        END LOOP;
        IF pendingCount > 0 THEN
            RETURN false;
        ELSE
            RETURN true;
        END IF;
    ELSE
        RETURN false;
    END IF;
END
$$;
CREATE TABLE "order"."order" (
    id oid NOT NULL,
    "orderStatus" text NOT NULL,
    "paymentStatus" text NOT NULL,
    "deliveryInfo" jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    "transactionId" text,
    tax double precision,
    discount numeric DEFAULT 0 NOT NULL,
    "itemTotal" numeric,
    "deliveryPrice" numeric,
    currency text DEFAULT 'usd'::text,
    updated_at timestamp with time zone DEFAULT now(),
    tip numeric,
    "amountPaid" numeric,
    "fulfillmentType" text,
    "deliveryPartnershipId" integer,
    "fulfillmentTimestamp" timestamp without time zone,
    "readyByTimestamp" timestamp without time zone,
    source text,
    "keycloakId" text,
    "cartId" integer,
    "brandId" integer DEFAULT 1 NOT NULL
);
CREATE FUNCTION "order".ordersummary(order_row "order"."order") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    counts jsonb;
    amounts jsonb;
BEGIN
    SELECT json_object_agg(each."orderStatus", each."count") FROM (
        SELECT "orderStatus", COUNT (*) FROM "order"."order" GROUP BY "orderStatus"
    ) AS each into counts;
    SELECT json_object_agg(each."orderStatus", each."total") FROM (
        SELECT "orderStatus", SUM ("itemTotal") as total FROM "order"."order" GROUP BY "orderStatus"
    ) AS each into amounts;
	RETURN json_build_object('count', counts, 'amount', amounts);
END
$$;
CREATE FUNCTION "order".set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;
CREATE FUNCTION "order".update_mealkit_sachet_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    sachet record;
BEGIN
    IF OLD."assemblyStatus" != NEW."assemblyStatus" AND NEW."assemblyStatus" = 'COMPLETED' THEN
    	FOR sachet IN SELECT * FROM "order"."orderSachet" WHERE "orderMealKitProductId" = NEW.id LOOP
        	UPDATE "order"."orderSachet" SET
            status = 'PACKED', "isLabelled" = true, "isPortioned" = true, "isAssembled" = true
            WHERE id = sachet.id;
        END LOOP;
    END IF;
    RETURN NULL;
END;
$$;
CREATE FUNCTION "order".update_order_products_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    orderItem record;
    sachetItem record;
    updatedStatus text;
    oldStatus text;
BEGIN
    updatedStatus = NEW."orderStatus";
    oldStatus = OLD."orderStatus";
    IF oldStatus != 'READY_TO_ASSEMBLE' AND updatedStatus = 'READY_TO_ASSEMBLE' THEN
        FOR orderItem IN SELECT * FROM "order"."orderInventoryProduct" WHERE "orderId" = NEW.id LOOP
            IF orderItem."assemblyStatus" != 'COMPLETED' THEN
                UPDATE "order"."orderInventoryProduct" SET "assemblyStatus" = 'COMPLETED' WHERE id = orderItem.id;
            END IF;
        END LOOP;
        FOR orderItem IN SELECT * FROM "order"."orderReadyToEatProduct" WHERE "orderId" = NEW.id LOOP
            IF orderItem."assemblyStatus" != 'COMPLETED' THEN
                UPDATE "order"."orderReadyToEatProduct" SET "assemblyStatus" = 'COMPLETED' WHERE id = orderItem.id;
            END IF;
        END LOOP;
        FOR orderItem IN SELECT * FROM "order"."orderMealKitProduct" WHERE "orderId" = NEW.id LOOP
            IF orderItem."assemblyStatus" != 'COMPLETED' THEN
                UPDATE "order"."orderMealKitProduct" SET "assemblyStatus" = 'COMPLETED' WHERE id = orderItem.id;
            END IF;
        END LOOP;
    END IF;
    IF oldStatus != 'READY_TO_DISPATCH' AND updatedStatus = 'READY_TO_DISPATCH' THEN
        FOR orderItem IN SELECT * FROM "order"."orderInventoryProduct" WHERE "orderId" = NEW.id LOOP
            IF orderItem."isAssembled" = false THEN
                UPDATE "order"."orderInventoryProduct" SET "isAssembled" = true WHERE id = orderItem.id;
            END IF;
        END LOOP;
        FOR orderItem IN SELECT * FROM "order"."orderReadyToEatProduct" WHERE "orderId" = NEW.id LOOP
            IF orderItem."isAssembled" = false THEN
                UPDATE "order"."orderReadyToEatProduct" SET "isAssembled" = true WHERE id = orderItem.id;
            END IF;
        END LOOP;
        FOR orderItem IN SELECT * FROM "order"."orderMealKitProduct" WHERE "orderId" = NEW.id LOOP
            IF orderItem."isAssembled" = false THEN
                UPDATE "order"."orderMealKitProduct" SET "isAssembled" = true WHERE id = orderItem.id;
            END IF;
        END LOOP;
    END IF;
    RETURN NULL;
END;
$$;
CREATE FUNCTION "order".update_readytoeat_sachet_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    sachet record;
BEGIN
    IF OLD."assemblyStatus" != NEW."assemblyStatus" AND NEW."assemblyStatus" = 'COMPLETED' THEN
    	FOR sachet IN SELECT * FROM "order"."orderSachet" WHERE "orderReadyToEatProductId" = NEW.id LOOP
        	UPDATE "order"."orderSachet" SET
            status = 'PACKED', "isLabelled" = true, "isPortioned" = true, "isAssembled" = true
            WHERE id = sachet.id;
        END LOOP;
    END IF;
    RETURN NULL;
END;
$$;
CREATE TABLE products."customizableProductOption" (
    id integer NOT NULL,
    "simpleRecipeProductId" integer,
    "inventoryProductId" integer,
    "customizableProductId" integer NOT NULL
);
CREATE FUNCTION products."customizableProductOptionFullName"(option products."customizableProductOption") RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    productName text;
    optionName text;
BEGIN
    SELECT name FROM "products"."customizableProduct" WHERE id = option."customizableProductId" INTO productName;
    IF option."simpleRecipeProductId" IS NOT NULL
        THEN SELECT name FROM "products"."simpleRecipeProduct" WHERE id = option."simpleRecipeProductId" INTO optionName;
    ELSE
        SELECT name FROM "products"."inventoryProduct" WHERE id = option."inventoryProductId" INTO optionName;
    END IF;
    RETURN productName || ' - ' || optionName;
END;
$$;
CREATE TABLE products."comboProduct" (
    id integer NOT NULL,
    tags jsonb,
    description text,
    "isPublished" boolean DEFAULT false NOT NULL,
    "productSku" uuid,
    "isPopupAllowed" boolean DEFAULT true NOT NULL,
    assets jsonb,
    name text
);
CREATE FUNCTION products."defaultComboProductCartItem"(product products."comboProduct") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    component record;
    components jsonb[];
    subProduct jsonb;
    unitPrice numeric = 0;
BEGIN
    FOR component IN SELECT * FROM "products"."comboProductComponent" WHERE "comboProductId" = product.id LOOP
	    IF component."simpleRecipeProductId" is NOT NULL
        THEN
            SELECT "products"."defaultSimpleRecipeProductCartItem"("simpleRecipeProduct".*) FROM "products"."simpleRecipeProduct" WHERE "simpleRecipeProduct".id = CAST(component."simpleRecipeProductId" AS int) into subProduct;
            components = components || jsonb_build_object(
                'id', subProduct->'id',
                'name', subProduct->>'name',
                'type', 'simpleRecipeProduct',
                'image', subProduct->>'image',
                'option', subProduct->'option',
                'discount', subProduct->'discount',
                'quantity', 1,
                'unitPrice', subProduct->'unitPrice',
                'totalPrice', subProduct->'totalPrice',
                'comboProductComponentId', component.id,
                'comboProductComponentLabel', component.label);
            unitPrice = unitPrice + CAST(subProduct->>'unitPrice' AS numeric);
        ELSIF component."inventoryProductId" is NOT NULL
        THEN
            SELECT "products"."defaultInventoryProductCartItem"("inventoryProduct".*) FROM "products"."inventoryProduct" WHERE "inventoryProduct".id = CAST(component."inventoryProductId" AS int) into subProduct;
            components = components || jsonb_build_object(
                'id', subProduct->'id',
                'name', subProduct->>'name',
                'type', 'inventoryProduct',
                'image', subProduct->>'image',
                'option', subProduct->'option',
                'discount', subProduct->'discount',
                'quantity', 1,
                'unitPrice', subProduct->'unitPrice',
                'totalPrice', subProduct->'totalPrice',
                'comboProductComponentId', component.id,
                'comboProductComponentLabel', component.label);
                unitPrice = unitPrice + CAST(subProduct->>'unitPrice' AS numeric);
        ELSE
            SELECT "products"."defaultCustomizableProductCartItem"("customizableProduct".*) FROM "products"."customizableProduct" WHERE "customizableProduct".id = CAST(component."customizableProductId" AS int) into subProduct;
            components = components || jsonb_build_object(
                'id', subProduct->'id',
                'name', subProduct->>'name',
                'type', subProduct->>'type',
                'image', subProduct->>'image',
                'option', subProduct->'option',
                'discount', subProduct->'discount',
                'quantity', 1,
                'unitPrice', subProduct->'unitPrice',
                'totalPrice', subProduct->'totalPrice',
                'comboProductComponentId', component.id,
                'comboProductComponentLabel', component.label,
                 'customizableProductId',  subProduct->>'customizableProductId',
                'customizableProductOptionId', subProduct->>'customizableProductOptionId');
                unitPrice = unitPrice + CAST(subProduct->>'unitPrice' AS numeric);
        END IF;
    END LOOP;
    RETURN json_build_object(
    'id', product.id,
    'name', product.name,
    'type', 'comboProduct',
    'components', components,
    'cartItemId', gen_random_uuid(),
    'specialInstructions', '',
    'unitPrice', unitPrice,
    'totalPrice', unitPrice,
    'discount', 0,
    'quantity', 1);
END
$$;
CREATE TABLE products."customizableProduct" (
    id integer NOT NULL,
    name text NOT NULL,
    tags jsonb,
    description text,
    "default" integer,
    "isPublished" boolean DEFAULT false NOT NULL,
    "productSku" uuid,
    "isPopupAllowed" boolean DEFAULT true NOT NULL,
    assets jsonb
);
CREATE FUNCTION products."defaultCustomizableProductCartItem"(product products."customizableProduct") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    product jsonb;
    subProduct jsonb;
    option jsonb;
    productType text;
BEGIN
    SELECT json_build_object(
        'id', "id",
        'simpleRecipeProductId', "simpleRecipeProductId"::int,
        'inventoryProductId', "inventoryProductId"::int
    ) FROM "products"."customizableProductOption" WHERE id = product."default" into option;
    IF option->>'simpleRecipeProductId' is NOT NULL
        THEN
            SELECT 'simpleRecipeProduct' into productType;
            SELECT "products"."defaultSimpleRecipeProductCartItem"("simpleRecipeProduct".*) FROM "products"."simpleRecipeProduct" WHERE "simpleRecipeProduct".id = CAST(option->>'simpleRecipeProductId' AS int) into subProduct;
    ELSE
        SELECT 'inventoryProduct' into productType;
        SELECT "products"."defaultInventoryProductCartItem"("inventoryProduct".*) FROM "products"."inventoryProduct" WHERE "inventoryProduct".id = CAST(option->>'inventoryProductId' AS int) into subProduct;
    END IF;
    RETURN json_build_object(
    'id', subProduct->'id',
    'name', concat('[',product.name,'] ',subProduct->>'name'),
    'type', productType,
    'image', subProduct->>'image',
    'option', subProduct->'option',
    'discount', subProduct->'discount',
    'quantity', 1,
    'unitPrice', subProduct->'unitPrice',
    'cartItemId', gen_random_uuid(),
    'totalPrice', subProduct->'totalPrice',
    'specialInstructions', '',
    'customizableProductId', product."id",
    'customizableProductOptionId', CAST(option->>'id' AS int)
);
END
$$;
CREATE TABLE products."inventoryProduct" (
    id integer NOT NULL,
    "supplierItemId" integer,
    "sachetItemId" integer,
    accompaniments jsonb,
    name text,
    tags jsonb,
    description text,
    assets jsonb,
    "isPublished" boolean DEFAULT false NOT NULL,
    "nameAsSupplier" boolean DEFAULT true,
    "productSku" uuid,
    "default" integer,
    "isPopupAllowed" boolean DEFAULT true NOT NULL
);
CREATE FUNCTION products."defaultInventoryProductCartItem"(product products."inventoryProduct") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    option jsonb;
BEGIN
    SELECT json_build_object(
        'id', id,
        'price', CAST ("price"->0->>'value' AS numeric),
        'label', label,
        'discount', CAST ("price"->0->>'discount' AS numeric)
    ) FROM "products"."inventoryProductOption" WHERE id = product."default" into option;
    RETURN json_build_object(
        'id', product.id,
        'name', product.name,
        'type', 'inventoryProduct',
        'image', product."assets"->'images'->0,
        'option', option,
        'discount', option->'discount',
        'quantity', 1,
        'unitPrice', option->'price',
        'cartItemId', gen_random_uuid(),
        'totalPrice', option->'price',
        'specialInstructions', ''
    );
END
$$;
CREATE TABLE products."simpleRecipeProduct" (
    id integer NOT NULL,
    "simpleRecipeId" integer,
    name text NOT NULL,
    accompaniments jsonb,
    tags jsonb,
    description text,
    assets jsonb,
    "default" integer,
    "isPublished" boolean DEFAULT false NOT NULL,
    "productSku" uuid,
    "isPopupAllowed" boolean DEFAULT true NOT NULL
);
CREATE FUNCTION products."defaultSimpleRecipeProductCartItem"(product products."simpleRecipeProduct") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    option jsonb;
    yieldId int;
    yieldObj jsonb;
BEGIN
    SELECT json_build_object(
        'id', id,
        'type', "type",
        'price', CAST ("price"->0->>'value' AS numeric),
        'discount', CAST ("price"->0->>'discount' AS numeric)
    ) FROM "products"."simpleRecipeProductOption" WHERE id = product."default" into option;
    SELECT "simpleRecipeYieldId" FROM "products"."simpleRecipeProductOption" WHERE id = product."default" into yieldId;
    SELECT yield FROM "simpleRecipe"."simpleRecipeYield" WHERE id = yieldId into yieldObj;
    SELECT option || jsonb_build_object('serving', yieldObj->>'serving') into option;
    RETURN json_build_object(
        'id', product.id,
        'name', product.name,
        'type', 'simpleRecipeProduct',
        'image', product."assets"->'images'->0,
        'option', option,
        'discount', option->'discount',
        'quantity', 1,
        'unitPrice', option->'price',
        'cartItemId', gen_random_uuid(),
        'totalPrice', option->'price',
        'specialInstructions', ''
    );
END
$$;
CREATE FUNCTION products."getProductDetails"(inputid integer) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    productCategoryRecord record;
    product record;
    productName text;
    productType text;
    productImage text;
BEGIN
    SELECT * FROM "onDemand"."collection_productCategory_product" WHERE id = inputId INTO productCategoryRecord;
    IF productCategoryRecord."simpleRecipeProductId" IS NOT NULL THEN
        SELECT * FROM products."simpleRecipeProduct" WHERE id = productCategoryRecord."simpleRecipeProductId" INTO product;
        productName := product.name;
        productType := 'simpleRecipeProduct';
        productImage := 'asasd';
    ELSIF productCategoryRecord."inventoryProductId" IS NOT NULL THEN
        SELECT * FROM products."inventoryProduct" WHERE id = productCategoryRecord."inventoryProductId" INTO product;
        productName := product.name;
        productType := 'inventoryProduct';
        productImage := 'asasd';
    ELSEIF productCategoryRecord."customizableProductId" IS NOT NULL THEN
        SELECT * FROM products."customizableProduct" WHERE id = productCategoryRecord."customizableProductId" INTO product;
        productName := product.name;
        productType := 'customizableProduct';
        productImage := 'asasd';
    ELSE
        SELECT * FROM products."comboProduct" WHERE id = productCategoryRecord."comboProductId" INTO product;
        productName := product.name;
        productType := 'comboProduct';
        productImage := 'asasd';
    END IF;
    RETURN jsonb_build_object(
        'name', productName,
        'type', productType,
        'image', productImage
    );
END
$$;
CREATE TABLE products."inventoryProductOption" (
    id integer NOT NULL,
    quantity integer NOT NULL,
    label text,
    "inventoryProductId" integer NOT NULL,
    price jsonb NOT NULL,
    "modifierId" integer,
    "assemblyStationId" integer,
    "labelTemplateId" integer,
    "packagingId" integer,
    "instructionCardTemplateId" integer
);
CREATE FUNCTION products."inventoryProductOptionFullName"(option products."inventoryProductOption") RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    productName text;
BEGIN
    SELECT name FROM "products"."inventoryProduct" WHERE id = option."inventoryProductId" INTO productName;
    RETURN productName || ' - ' || option.label;
END;
$$;
CREATE FUNCTION products."isSimpleRecipeProductValid"(product products."simpleRecipeProduct") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    temp json;
    isRecipeValid boolean;
BEGIN
    IF product."simpleRecipeId" IS NULL
        THEN return json_build_object('status', false, 'error', 'Recipe not provided');
    END IF;
    SELECT "simpleRecipe".isSimpleRecipeValid("simpleRecipe".*) FROM "simpleRecipe"."simpleRecipe" where "simpleRecipe".id = product."simpleRecipeId" into temp;
    SELECT temp->'status' into isRecipeValid;
    IF NOT isRecipeValid
        THEN return json_build_object('status', false, 'error', 'Recipe is invalid');
    ELSIF product."default" IS NULL
        THEN return json_build_object('status', false, 'error', 'Default option not provided');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE FUNCTION products.iscomboproductvalid(product products."comboProduct") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    temp int;
BEGIN
    SELECT COUNT(*) FROM "products"."comboProductComponent" where "comboProductComponent"."comboProductId" = product.id into temp;
    IF temp < 2
        THEN return json_build_object('status', false, 'error', 'Atleast 2 options required');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE FUNCTION products.iscustomizableproductvalid(product products."customizableProduct") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    temp json;
BEGIN
    SELECT id FROM "products"."customizableProductOption" where "customizableProductOption"."customizableProductId" = product.id LIMIT 1 into temp;
    IF temp IS NULL
        THEN return json_build_object('status', false, 'error', 'No options provided');
    ELSIF product."default" IS NULL
        THEN return json_build_object('status', false, 'error', 'Default option not provided');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE FUNCTION products.isinventoryproductvalid(product products."inventoryProduct") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
BEGIN
    IF product."supplierItemId" IS NULL AND product."sachetItemId" IS NULL
        THEN return json_build_object('status', false, 'error', 'Item not provided');
    ELSIF product."default" IS NULL
        THEN return json_build_object('status', false, 'error', 'Default option not provided');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE FUNCTION products."simpleRecipeProductCartItem"(product products."simpleRecipeProduct", "optionId" integer) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    option jsonb;
BEGIN
     SELECT json_build_object(
            'id', id,
            'type', "type",
            'price', CAST ("price"->0->>'value' AS numeric),
            'discount', CAST ("price"->0->>'discount' AS numeric)
        ) FROM "products"."simpleRecipeProductOption" WHERE id = "optionId" into option;
    RETURN json_build_object(
        'id', product.id,
        'name', product.name,
        'type', 'simpleRecipeProduct',
        'image', product."assets"->'images'->0,
        'option', option,
        'discount', option->'discount',
        'quantity', 1,
        'unitPrice', option->'price',
        'cartItemId', gen_random_uuid(),
        'totalPrice', option->'price',
        'specialInstructions', ''
    );
END
$$;
CREATE FUNCTION products."simpleRecipeProductCartItemById"("productId" integer, "optionId" integer) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    option jsonb;
    product products."simpleRecipeProduct";
BEGIN
    SELECT * FROM products."simpleRecipeProduct" WHERE id = "productId" INTO product ;
    SELECT json_build_object(
        'id', id,
        'type', "type",
        'price', CAST ("price"->0->>'value' AS numeric),
        'discount', CAST ("price"->0->>'discount' AS numeric)
    ) FROM "products"."simpleRecipeProductOption" WHERE id = "optionId" into option;
    RETURN json_build_object(
        'id', product.id,
        'name', product.name,
        'type', 'simpleRecipeProduct',
        'image', product."assets"->'images'->0,
        'option', option,
        'discount', option->'discount',
        'quantity', 1,
        'unitPrice', option->'price',
        'cartItemId', gen_random_uuid(),
        'totalPrice', option->'price',
        'specialInstructions', ''
    );
END
$$;
CREATE TABLE products."simpleRecipeProductOption" (
    id integer NOT NULL,
    "simpleRecipeYieldId" integer NOT NULL,
    "simpleRecipeProductId" integer NOT NULL,
    type text NOT NULL,
    price jsonb NOT NULL,
    "isActive" boolean DEFAULT false NOT NULL,
    "modifierId" integer,
    "assemblyStationId" integer,
    "labelTemplateId" integer,
    "packagingId" integer,
    "instructionCardTemplateId" integer
);
CREATE FUNCTION products."simpleRecipeProductOptionFullName"(option products."simpleRecipeProductOption") RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    productName text;
    res text;
    serving text;
BEGIN
    SELECT name FROM "products"."simpleRecipeProduct" WHERE id = option."simpleRecipeProductId" INTO productName;
    IF option."type" = 'readyToEat'
        THEN res := productName || ' - ' || 'Ready to Eat';
    ELSE
        res := productName || ' - ' || 'Meal Kit';
    END IF;
    SELECT yield->>'serving' FROM "simpleRecipe"."simpleRecipeYield" WHERE id = option."simpleRecipeYieldId" INTO serving;
    RETURN res || ' (' || serving || ' servings)';
END;
$$;
CREATE FUNCTION rules."assertFact"(condition jsonb, params jsonb) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    x jsonb;
    factValue jsonb;
    values jsonb;
    res boolean;
BEGIN
    x := condition || params;
   SELECT rules."getFactValue"(condition->>'fact', x) INTO factValue;
   SELECT jsonb_build_object('condition', condition->'value', 'fact', factValue->'value') INTO values;
   SELECT rules."runWithOperator"(condition->>'operator', values) INTO res;
   RETURN res;
END;
$$;
CREATE FUNCTION rules."budgetFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    recordData record;
    resArray int array DEFAULT '{}';
    res int;
    endDate timestamp := current_timestamp;
    startDate timestamp := endDate - (params->>'duration')::interval;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN jsonb_build_object('id', 'budget', 'fact', 'budget', 'title', 'Budget', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{ comboProducts { id title: name } }" }'::json, 'argument','couponId', 'operators', operators);
    END IF;
    IF (params->>'Per Customer')::boolean = true THEN
    FOR recordData IN 
        EXECUTE 'SELECT * FROM crm."rewardHistory" WHERE $1 IS NOT NULL AND "keycloakId" = $2'
        USING (params->>'Reward Type')::text, (params->>'keycloakId')::text
    LOOP
        resArray = resArray || recordData."id";
    END LOOP;
        RETURN jsonb_build_object('value', resArray);
    ELSE
        EXECUTE 'SELECT id FROM crm."rewardHistory" WHERE $1 IS NOT NULL'
        INTO res
        USING params->'Reward Type';
        RETURN jsonb_build_object('value', res);
    END IF;
END;
$_$;
CREATE FUNCTION rules."budgetFunc2"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    recordData record;
    resArray int array DEFAULT '{}';
    res int;
    endDate timestamp := current_timestamp;
    startDate timestamp := endDate - (params->>'duration')::interval;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
        SELECT "id" FROM crm."rewardHistory" WHERE (params->>'Reward Type')::text IS NOT NULL AND "keycloakId" = (params->>'keycloakId')::text
        INTO res;
        resArray = resArray || res;
        -- USING (params->>'Reward Type')::text, (params->>'keycloakId')::text;
        RETURN jsonb_build_object('value', resArray);
END;
$$;
CREATE FUNCTION rules."budgetTestFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    queryParams jsonb not null default '{}'::jsonb ;
    endDate timestamp := current_timestamp;
    startDate timestamp := endDate - (params->>'duration')::interval;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN jsonb_build_object('id', 'budget', 'fact', 'budget', 'title', 'Budget', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{ comboProducts { id title: name } }" }'::json, 'argument','couponId', 'operators', operators);
    END IF;
    IF params->>'rewardType' = 'discount'
        THEN queryParams :=  queryParams || '{"columnName": "(params->>''rewardType'')"}';
         queryParams :=  queryParams || '{"columnName2": "loyaltyPoints"}';
        RETURN jsonb_build_object('value', queryParams);
    END IF;
END;
$$;
CREATE TABLE rules.facts (
    id integer NOT NULL,
    query text
);
CREATE FUNCTION rules."cartComboProduct"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartComboProductFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."cartComboProductFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    products jsonb;
    product jsonb;
    productIdArray integer array DEFAULT '{}';
    productId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartComboProduct', 'fact', 'cartComboProduct', 'title', 'Cart Contains Combo Product', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{ comboProducts { id title: name } }" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        SELECT "cartInfo"->'products' FROM  crm."orderCart" WHERE "id" = (params->>'cartId')::integer INTO products;
        FOR product IN SELECT  * FROM jsonb_array_elements(products) LOOP
            IF product->>'type' = 'comboProduct'
             THEN SELECT (product->>'id')::integer INTO productId;
              productIdArray = productIdArray || productId;
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', productIdArray, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."cartCustomProduct"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartCustomProductFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."cartCustomProductFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    products jsonb;
    componentsArr jsonb;
    product jsonb;
    component jsonb;
    productIdArray integer array DEFAULT '{}';
    productId integer;
     operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartCustomProduct', 'fact', 'cartCustomProduct', 'title', 'Cart contains Customizable Product', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{ customizableProducts { id title: name } }" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        SELECT "cartInfo"->'products' FROM  crm."orderCart" WHERE "id" = (params->>'cartId')::integer INTO products;
        FOR product IN SELECT  * FROM jsonb_array_elements(products) LOOP
            IF product->>'type' = 'comboProduct'
              THEN SELECT product->'components' INTO componentsArr;
                FOR component IN SELECT * FROM jsonb_array_elements(componentsArr) LOOP
                     IF component->>'customizableProductId' IS NOT NULL
                        THEN SELECT (component->>'id')::integer INTO productId;
                        productIdArray = productIdArray || productId;
                    END IF;
                END LOOP;
            END IF;
            IF product->>'customizableProductId' IS NOT NULL
              THEN SELECT (product->>'id')::integer INTO productId;
              productIdArray = productIdArray || productId;
            END IF;
        END LOOP;
        RETURN json_build_object('value', productIdArray, 'valueType','array','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."cartCustomProductOption"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartCustomProductOptionFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."cartCustomProductOptionFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    products jsonb;
    componentsArr jsonb;
    product jsonb;
    component jsonb;
    optionIdArray integer array DEFAULT '{}';
    optionId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartCustomProductOption', 'fact', 'cartCustomProductOption', 'title', 'Cart contains Customizable Product Option ID', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{ customizableProductOptions { id title: fullName } }" }'::json, 'argument','cartId', 'operators', operators);
    ELSE
        SELECT "cartInfo"->'products' FROM  crm."orderCart" WHERE "id" = (params->>'cartId')::integer INTO products;
        FOR product IN SELECT  * FROM jsonb_array_elements(products) LOOP
            IF product->>'type' = 'comboProduct'
              THEN SELECT product->'components' INTO componentsArr;
                FOR component IN SELECT * FROM jsonb_array_elements(componentsArr) LOOP
                     IF component->>'customizableProductId' IS NOT NULL
                        THEN SELECT (component->'option'->>'id')::integer INTO optionId;
                        optionIdArray = optionIdArray || optionId;
                    END IF;
                END LOOP;
            END IF;
            IF product->>'customizableProductId' IS NOT NULL
              THEN SELECT (product->'option'->>'id')::integer INTO optionId;
              optionIdArray = optionIdArray || optionId;
            END IF;
        END LOOP;
        RETURN json_build_object('value', optionIdArray, 'valueType','array','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."cartInvProduct"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartInvProductFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."cartInvProductFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    products jsonb;
    componentsArr jsonb;
    product jsonb;
    component jsonb;
    productIdArray integer array DEFAULT '{}';
    productId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN jsonb_build_object('id', 'cartInvProduct', 'fact', 'cartInvProduct', 'title', 'Cart contains Inventory Product', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{ inventoryProducts { id title: name } }" }'::json, 'argument','cartId', 'operators', operators);
    ELSE
        SELECT "cartInfo"->'products' FROM  crm."orderCart" WHERE "id" = (params->>'cartId')::integer INTO products;
        FOR product IN SELECT  * FROM jsonb_array_elements(products) LOOP
            IF product->>'type' = 'comboProduct'
              THEN SELECT product->'components' INTO componentsArr;
                FOR component IN SELECT * FROM jsonb_array_elements(componentsArr) LOOP
                    IF component->>'type' IS NOT NULL AND component->>'type' = 'inventoryProduct'
                        THEN SELECT (component->>'id')::integer INTO productId;
                        productIdArray = productIdArray || productId;
                    END IF;
                END LOOP;
            END IF;
            IF product->>'type' IS NOT NULL AND product->>'type' = 'inventoryProduct'
              THEN SELECT (product->>'id')::integer INTO productId;
              productIdArray = productIdArray || productId;
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', productIdArray, 'valueType','array','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."cartInvProductOption"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartInvProductOptionFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."cartInvProductOptionFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    products jsonb;
    componentsArr jsonb;
    product jsonb;
    component jsonb;
    optionIdArray integer array DEFAULT '{}';
    optionId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartInvProductOption', 'fact', 'cartInvProductOption', 'title', 'Cart contains Inventory Product OptionId', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{ inventoryProductOptions { id title: fullName } }" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        SELECT "cartInfo"->'products' FROM  crm."orderCart" WHERE "id" = (params->>'cartId')::integer INTO products;
        FOR product IN SELECT  * FROM jsonb_array_elements(products) LOOP
            IF product->>'type' = 'comboProduct'
              THEN SELECT product->'components' INTO componentsArr;
                FOR component IN SELECT * FROM jsonb_array_elements(componentsArr) LOOP
                    IF component->>'type' IS NOT NULL AND component->>'type' = 'inventoryProduct'
                        THEN SELECT (component->'option'->>'id')::integer INTO optionId;
                        optionIdArray = optionIdArray || optionId;
                    END IF;
                END LOOP;
            END IF;
            IF product->>'type' IS NOT NULL AND product->>'type' = 'inventoryProduct'
              THEN SELECT (product->'option'->>'id')::integer INTO optionId;
              optionIdArray = optionIdArray || optionId;
            END IF;
        END LOOP;
        RETURN json_build_object('value', optionIdArray, 'valueType','array','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."cartItemTotal"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartItemTotalFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."cartItemTotalFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    total numeric;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartItemTotal', 'fact', 'cartItemTotal', 'title', 'Cart Item Total', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        SELECT ROUND(("cartInfo"->'total')::numeric, 2) FROM crm."orderCart" WHERE id = (params->>'cartId')::integer INTO total;
        RETURN json_build_object('value', total, 'valueType','numeric','arguments','cartId');
    END IF;
END;
$$;
CREATE FUNCTION rules."cartMealkitProduct"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartMealkitProductFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."cartMealkitProductFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    products jsonb;
    componentsArr jsonb;
    product jsonb;
    component jsonb;
    productIdArray integer array DEFAULT '{}';
    productId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartMealkitProduct', 'fact', 'cartMealkitProduct', 'title', 'Cart contains Meal Kit Product', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{simpleRecipeProducts {id title: name}}" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        SELECT "cartInfo"->'products' FROM  crm."orderCart" WHERE "id" = (params->>'cartId')::integer INTO products;
        FOR product IN SELECT  * FROM jsonb_array_elements(products) LOOP
            IF product->>'type' = 'comboProduct'
              THEN SELECT product->'components' INTO componentsArr;
                FOR component IN SELECT * FROM jsonb_array_elements(componentsArr) LOOP
                    IF component->'option'->>'type' IS NOT NULL AND component->>'type' = 'simpleRecipeProduct' AND component->'option'->>'type' = 'mealKit'
                        THEN SELECT (component->>'id')::integer INTO productId;
                        productIdArray = productIdArray || productId;
                    END IF;
                END LOOP;
            END IF;
            IF product->>'type' = 'simpleRecipeProduct' AND  product->'option'->>'type' = 'mealKit'
              THEN SELECT (product->>'id')::integer INTO productId;
              productIdArray = productIdArray || productId;
            END IF;
        END LOOP;
        RETURN json_build_object('value', productIdArray, 'valueType','integer','argument','cartId');
    END IF;
END;
$$;
CREATE FUNCTION rules."cartMealkitProductOption"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartMealkitProductOptionFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."cartMealkitProductOptionFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    products jsonb;
    componentsArr jsonb;
    product jsonb;
    component jsonb;
    optionIdArray integer array DEFAULT '{}';
    optionId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartMealkitProductOption',  'fact', 'cartMealkitProductOption', 'title', 'Cart contains Meal Kit Product OptionId', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{ simpleRecipeProductOptions { id title: fullName } }" }'::json, 'argument','cartId', 'operators', operators);
    ELSE
        SELECT "cartInfo"->'products' FROM  crm."orderCart" WHERE "id" = (params->>'cartId')::integer INTO products;
        FOR product IN SELECT  * FROM jsonb_array_elements(products) LOOP
            IF product->>'type' = 'comboProduct'
              THEN SELECT product->'components' INTO componentsArr;
                FOR component IN SELECT * FROM jsonb_array_elements(componentsArr) LOOP
                    IF component->'option'->>'type' IS NOT NULL AND component->>'type' = 'simpleRecipeProduct' AND component->'option'->>'type' = 'mealKit'
                        THEN SELECT (component->'option'->>'id')::integer INTO optionId;
                        optionIdArray = optionIdArray || optionId;
                    END IF;
                END LOOP;
            END IF;
            IF product->>'type' = 'simpleRecipeProduct' AND  product->'option'->>'type' = 'mealKit'
              THEN SELECT (product->'option'->>'id')::integer INTO optionId;
              optionIdArray = optionIdArray || optionId;
            END IF;
        END LOOP;
        RETURN json_build_object('value', optionIdArray, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."cartReadyToEatProduct"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartReadyToEatProductFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."cartReadyToEatProductFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    products jsonb;
    componentsArr jsonb;
    product jsonb;
    component jsonb;
    productIdArray integer array DEFAULT '{}';
    productId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartReadyToEatProduct', 'fact', 'cartReadyToEatProduct', 'title', 'Cart contains Ready To Eat Product', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{ simpleRecipeProducts { id title: name } }" }'::json, 'argument','cartId', 'operators', operators);
    ELSE
        SELECT "cartInfo"->'products' FROM  crm."orderCart" WHERE "id" = (params->>'cartId')::integer INTO products;
        FOR product IN SELECT  * FROM jsonb_array_elements(products) LOOP
            IF product->>'type' = 'comboProduct'
              THEN SELECT product->'components' INTO componentsArr;
                FOR component IN SELECT * FROM jsonb_array_elements(componentsArr) LOOP
                    IF component->'option'->>'type' IS NOT NULL AND component->>'type' = 'simpleRecipeProduct' AND component->'option'->>'type' = 'readyToEat'
                        THEN SELECT (component->>'id')::integer INTO productId;
                        productIdArray = productIdArray || productId;
                    END IF;
                END LOOP;
            END IF;
            IF product->>'type' = 'simpleRecipeProduct' AND  product->'option'->>'type' = 'readyToEat'
              THEN SELECT (product->>'id')::integer INTO productId;
              productIdArray = productIdArray || productId;
            END IF;
        END LOOP;
        RETURN json_build_object('value', productIdArray, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."cartReadyToEatProductOption"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartReadyToEatProductOptionFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."cartReadyToEatProductOptionFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    products jsonb;
    componentsArr jsonb;
    product jsonb;
    component jsonb;
    optionIdArray integer array DEFAULT '{}';
    optionId integer;
    operators text[] := ARRAY['in', 'notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartReadyToEatProductOption', 'fact', 'cartReadyToEatProductOption', 'title', 'Cart contains Ready To Eat Product Option ID', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{ simpleRecipeProductOptions { id title: fullName } }" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        SELECT "cartInfo"->'products' FROM  crm."orderCart" WHERE "id" = (params->>'cartId')::integer INTO products;
        FOR product IN SELECT  * FROM jsonb_array_elements(products) LOOP
            IF product->>'type' = 'comboProduct'
              THEN SELECT product->'components' INTO componentsArr;
                FOR component IN SELECT * FROM jsonb_array_elements(componentsArr) LOOP
                    IF component->'option'->>'type' IS NOT NULL AND component->>'type' = 'simpleRecipeProduct' AND component->'option'->>'type' = 'readyToEat'
                        THEN SELECT (component->'option'->>'id')::integer INTO optionId;
                        optionIdArray = optionIdArray || optionId;
                    END IF;
                END LOOP;
            END IF;
            IF product->>'type' = 'simpleRecipeProduct' AND  product->'option'->>'type' = 'readyToEat'
              THEN SELECT (product->'option'->>'id')::integer INTO optionId;
              optionIdArray = optionIdArray || optionId;
            END IF;
        END LOOP;
        RETURN json_build_object('value', optionIdArray, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."checkAllConditions"(conditionarray jsonb, params jsonb) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    condition jsonb;
    res1 boolean := true;
    res2 boolean := true;
    res3 boolean := true;
    tmp boolean := true;
BEGIN
   FOR condition IN SELECT  * FROM jsonb_array_elements(conditionArray) LOOP
       IF condition->'all' IS NOT NULL
          THEN SELECT rules."checkAllConditions"(condition->'all', params) INTO res2;
      ELSIF condition->'any' IS NOT NULL
          THEN SELECT rules."checkAnyConditions"(condition->'any', params) INTO res2;
      ELSE
          SELECT rules."assertFact"(condition::jsonb, params) INTO tmp;
          SELECT res3 AND tmp INTO res3;
      END IF;
   END LOOP;
  RETURN res1 AND res2 AND res3;
END;
$$;
CREATE FUNCTION rules."checkAnyConditions"(conditionarray jsonb, params jsonb) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    condition jsonb;
    res1 boolean := false;
    res2 boolean := false;
    res3 boolean := false;
    tmp boolean := false;
BEGIN
   FOR condition IN SELECT * FROM jsonb_array_elements(conditionArray) LOOP
       IF condition->'all' IS NOT NULL
          THEN SELECT rules."checkAllConditions"(condition->'all', params) INTO res2;
      ELSIF condition->'any' IS NOT NULL
          THEN SELECT rules."checkAnyConditions"(condition->'any', params) INTO res2;
      ELSE
          SELECT rules."assertFact"(condition::jsonb, params) INTO tmp;
          SELECT res3 OR tmp INTO res3;
      END IF;
   END LOOP;
  RETURN res1 OR res2 OR res3;
END;
$$;
CREATE FUNCTION rules."couponCountWithDuration"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."couponCountWithDurationFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."couponCountWithDurationFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    cart record;
    dateArray timestamp[];
    dateArr timestamp;
    usedCouponArray text[];
    usedCoupon text;
    orderCount integer := 0;
    endDate timestamp := current_timestamp;
    startDate timestamp := endDate - (params->>'duration')::interval;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'couponCountWithDuration','fact', 'couponCountWithDuration', 'title', 'Coupon Count With Duration', 'value', '{ "type" : "int", "duration" : true}'::json,'argument','cartId', 'operators', operators);
    ELSE
        SELECT * from crm."orderCart" WHERE id = (params->>'cartId')::integer INTO cart;
        dateArray := ARRAY(SELECT "created_at" FROM crm."orderCart" WHERE "customerKeycloakId" = cart."customerKeycloakId" AND "status" = 'ORDER_PLACED' AND "couponCode" = cart."couponCode");
        FOREACH dateArr IN ARRAY dateArray 
        LOOP 
            IF dateArr > startDate AND dateArr < endDate  
                THEN orderCount := orderCount + 1;
            END IF;
        END LOOP;
        RETURN json_build_object('value',orderCount,'valueType','integer','argument','cartId');
    END IF;
END;
$$;
CREATE FUNCTION rules."createdAt"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."createdAtFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."createdAtFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    dateOfSignup timestamp;
    operators text[] := ARRAY['rruleHasDate'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'createdAt', 'fact', 'createdAt', 'title', 'Customer Signup On', 'value', '{ "type" : "rrule"}'::json,'argument','keycloakId', 'operators', operators);
    ELSE
        SELECT created_at FROM crm."customer" WHERE "keycloakId" = (params->>'keycloakId')::text INTO dateOfSignup;
        RETURN json_build_object('value', dateOfSignup, 'valueType','timestamp','argument','keycloakId');
    END IF;
END;
$$;
CREATE FUNCTION rules."customerEmail"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."customerEmailFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."customerEmailFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    customerEmail text;
    operators text[] := ARRAY['contains', 'doesNotContain', 'equal', 'notEqual'];
BEGIN
    IF params->'read'
        THEN RETURN jsonb_build_object('id', 'customerEmail', 'fact', 'customerEmail', 'title', 'Customer Email', 'value', '{ "type" : "text" }'::json,'argument','keycloakId', 'operators', operators);
    ELSE
        SELECT email FROM crm."customer" WHERE "keycloakId" = (params->>'keycloakId')::text INTO customerEmail;
        RETURN jsonb_build_object('value', customerEmail, 'valueType','text','argument','keycloakId');
    END IF;
END;
$$;
CREATE FUNCTION rules."customerReferralCode"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."customerReferralCodeFunc"(jsonb) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."customerReferralCodeFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    customerReferralCode uuid ;
    operators text[] := ARRAY['equal', 'notEqual'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'customerReferralCode', 'fact', 'customerReferralCode', 'title', 'Customer Referral Code', 'value', '{ "type" : "text"}'::json,'argument','keycloakId', 'operators', operators);
    ELSE
        SELECT "referralCode" FROM crm."customerReferral" WHERE "keycloakId" = (params->>'keycloakId')::text INTO customerReferralCode;
        RETURN json_build_object('value', customerReferralCode, 'valueType','uuid','argument','keycloakId');
    END IF;
END;
$$;
CREATE FUNCTION rules."customerReferredByCode"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."customerReferredByCodeFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."customerReferredByCodeFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    customerReferredByCode uuid ;
    operators text[] := ARRAY['contains', 'doesNotContain'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'customerReferredByCode', 'fact', 'customerReferredByCode', 'title', 'Customer Referred By Code', 'value', '{ "type" : "text" }'::json, 'argument','keycloakId', 'operators', operators);
    ELSE
        SELECT "referredByCode" FROM crm."customerReferral" WHERE "keycloakId" = (params->>'keycloakId')::text INTO customerReferredByCode;
        RETURN json_build_object('value', customerReferredByCode, 'valueType','uuid','argument','keycloakId');
    END IF;
END;
$$;
CREATE FUNCTION rules."customerSource"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."customerSourceFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."customerSourceFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    cSource text;
    operators text[] := ARRAY['equal', 'notEqual'];
    value json;
    list json[] := ARRAY[ '{ "id" : "subscription", "value": "subscription", "title" : "Subscription Store"}'::json, '{"id" : "a-la-carte", "value": "a-la-carte", "title" : "A-la-carte Store"}'::json ];
BEGIN
    IF params->'read'
        THEN 
        SELECT json_build_object(
            'type', 'select',
            'select', 'value',
            'single', true,
            'datapoint', 'list',
            'list', list
        ) INTO value;
        RETURN json_build_object('id', 'customerSource', 'fact', 'customerSource', 'title', 'Customer Source', 'value', value, 'argument','keycloakId', 'operators', operators);
    ELSE
        SELECT source FROM crm."customer" WHERE "keycloakId" = (params->>'keycloakId')::text INTO cSource;
        RETURN json_build_object('value', cSource, 'valueType','text','argument','keycloakId');
    END IF;
END;
$$;
CREATE FUNCTION rules."discountReward"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."discountRewardFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."discountRewardFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    recordData record;
    totalDiscount numeric :=0 ;
    endDate timestamp := current_timestamp;
    startDate timestamp := endDate - (params->>'duration')::interval;
     operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN jsonb_build_object('id', 'discountReward', 'fact', 'discountReward', 'title', 'Discount Reward', 'value', '{ "type" : "int", "duration" : true}'::json, 'argument','couponId', 'operators', operators);
    ELSE
        FOR recordData IN
            SELECT * FROM crm."rewardHistory" WHERE "couponId" = (params->>'couponId')::int OR "campaignId" = (params->>'campaignId')::int
        LOOP
            IF recordData."created_at" > startDate AND recordData."created_at" < endDate  
                THEN totalDiscount := totalDiscount + recordData."discount";
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', totalDiscount, 'valueType','numeric','argument','couponId');
    END IF;
END;
$$;
CREATE FUNCTION rules."getFactValue"(fact text, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN call('SELECT rules."' || fact || 'Func"' || '(' || '''' || params || '''' || ')');
END;
$$;
CREATE FUNCTION rules."hasAtleastOrderedOnce"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    res jsonb;
BEGIN
    SELECT rules."hasAtleastOrderedOnceFunc"(params) INTO res;
    RETURN res;
END
$$;
CREATE FUNCTION rules."hasAtleastOrderedOnceFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    num int;
    operators text[] := ARRAY['equal', 'notEqual'];
BEGIN
     IF params->'read'
        THEN RETURN json_build_object('fact', 'hasAtleastOrderedOnce', 'title', 'Has Atleast Ordered Once', 'valueType','boolean','argument','keycloakId', 'operators', operators);
    ELSE
        SELECT count(*) FROM crm."orderCart" WHERE "customerKeycloakId" = (params->>'keycloakId')::text AND "orderId" IS NOT NULL INTO num;
        IF num =0
            THEN RETURN json_build_object('value', false, 'valueType', 'boolean', 'argument', 'keycloakId', 'message', 'you have not ordered yet', 'count' , num );
        ELSE
            RETURN json_build_object('value', true, 'valueType', 'boolean', 'argument', 'keycloakId', 'message', 'you have atleast ordered once!', 'count' , num);
        END IF;
    END IF;
END
$$;
CREATE TABLE rules.conditions (
    id integer NOT NULL,
    condition jsonb NOT NULL,
    app text
);
CREATE FUNCTION rules."isConditionValid"(condition rules.conditions, params jsonb) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    res boolean;
    x int;
BEGIN
    SELECT id FROM crm.reward WHERE "conditionId" = condition.id INTO x;
    IF x IS NOT NULL THEN
        params := params || jsonb_build_object('rewardId', x);
    END IF;
    IF x IS NULL THEN
        SELECT id FROM crm.campaign WHERE "conditionId" = condition.id INTO x;
        IF x IS NOT NULL THEN
            params := params || jsonb_build_object('campaignId', x);
        END IF;
    END IF;
    IF x IS NULL THEN
        SELECT id FROM crm.coupon WHERE "visibleConditionId" = condition.id INTO x;
        IF x IS NOT NULL THEN
            params := params || jsonb_build_object('couponId', x);
        END IF;
    END IF;
    SELECT rules."isConditionValidFunc"(condition.id, params) INTO res;
    RETURN res;
END;
$$;
CREATE FUNCTION rules."isConditionValidFunc"(conditionid integer, params jsonb) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    res boolean;
    condition record;
BEGIN
    SELECT * FROM rules.conditions WHERE id = conditionId INTO condition;
    IF condition.condition->'all' IS NOT NULL
        THEN SELECT rules."checkAllConditions"(condition.condition->'all', params) INTO res;
    ELSIF condition.condition->'any' IS NOT NULL
        THEN SELECT rules."checkAnyConditions"(condition.condition->'any', params) INTO res;
    ELSE
        SELECT false INTO res;
    END IF;
    RETURN res;
END;
$$;
CREATE FUNCTION rules."loyaltyPoints"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."loyaltyPointsFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."loyaltyPointsFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    cLoyaltyPoints int ;
     operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN jsonb_build_object('id', 'loyaltyPoints', 'fact', 'loyaltyPoints', 'title', 'Loyalty Points', 'value', '{ "type" : "int"}'::json, 'argument','keycloakId', 'operators', operators);
    ELSE
        SELECT points FROM crm."loyaltyPoint" WHERE "keycloakId" = (params->>'keycloakId')::text INTO cLoyaltyPoints;
        RETURN jsonb_build_object('value', cLoyaltyPoints, 'valueType','int','argument','keycloakId');
    END IF;
END;
$$;
CREATE FUNCTION rules."loyaltyPointsReward"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."loyaltyPointsRewardFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."loyaltyPointsRewardFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    recordData record;
    endDate timestamp := current_timestamp;
    startDate timestamp := endDate - (params->>'duration')::interval;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
    totalLoyaltyPoints int :=0 ;
BEGIN
    IF params->'read'
        THEN RETURN jsonb_build_object('id', 'loyaltyPointsReward', 'fact', 'loyaltyPointsReward', 'title', 'Loyalty Points Reward', 'value', '{ "type" : "int", "duration" : true}'::json, 'argument','couponId', 'operators', operators);
    ELSE
        FOR recordData IN
            SELECT * FROM crm."rewardHistory" WHERE "couponId" = (params->>'couponId')::int OR "campaignId" = (params->>'campaignId')::int
        LOOP
            IF recordData."created_at" > startDate AND recordData."created_at" < endDate  
                THEN totalLoyaltyPoints := totalLoyaltyPoints + recordData."loyaltyPoints";
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', totalLoyaltyPoints, 'valueType','numeric','argument','couponId');
    END IF;
END;
$$;
CREATE FUNCTION rules."numOfOrders"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."numOfOrdersFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."numOfOrdersFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    orderCount integer;
    operators text[] := ARRAY['greaterThan', 'greaterThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'numOfOrders', 'fact', 'numOfOrders', 'title', 'Number Of Orders', 'value', '{ "type" : "int" }'::json ,'argument','keycloakId', 'operators', operators);
    ELSE
        SELECT count(*) FROM crm."orderCart" WHERE "customerKeycloakId" = (params->>'keycloakId')::text  AND "orderId" IS NOT NULL INTO orderCount;
        RETURN json_build_object('value', orderCount, 'valueType','integer','argument','keycloakId');
    END IF;
END;
$$;
CREATE FUNCTION rules."numberOfComboProducts"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."numberOfComboProductsFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."numberOfComboProductsFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    products jsonb;
    product jsonb;
    quant integer :=0;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'numberOfComboProducts', 'fact', 'numberOfComboProducts', 'title', 'Number Of Combo Products', 'value', '{ "type" : "int" }'::json ,'argument','cartId', 'operators', operators);
    ELSE
        SELECT "cartInfo"->'products' FROM  crm."orderCart" WHERE "id" = (params->>'cartId')::integer INTO products;
        FOR product IN SELECT  * FROM jsonb_array_elements(products) LOOP
            IF product->>'type' = 'comboProduct'
              THEN quant := quant + 1;
            END IF;
        END LOOP;
        RETURN json_build_object('value', quant, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."numberOfCustomizableProducts"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."numberOfCustomizableProductsFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."numberOfCustomizableProductsFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    products jsonb;
    componentsArr jsonb;
    product jsonb;
    component jsonb;
    quant integer :=0;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'numberOfCustomizableProducts', 'fact', 'numberOfCustomizableProducts', 'title', 'Number Of Customizable Products', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        SELECT "cartInfo"->'products' FROM  crm."orderCart" WHERE "id" = (params->>'cartId')::integer INTO products;
        FOR product IN SELECT  * FROM jsonb_array_elements(products) LOOP
            IF product->>'type' = 'comboProduct'
              THEN SELECT product->'components' INTO componentsArr;
                FOR component IN SELECT * FROM jsonb_array_elements(componentsArr) LOOP
                    IF component->>'customizableProductId' IS NOT NULL
                    THEN  quant := quant +1;
                    END IF;
                END LOOP;
            END IF;
            IF product->>'customizableProductId' IS NOT NULL
              THEN  quant := quant +1;
            END IF;
        END LOOP;
        RETURN json_build_object('value', quant, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."numberOfDiscountReward"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."numberOfDiscountRewardFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."numberOfDiscountRewardFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    recordData record;
    totalDiscountCount int :=0 ;
    endDate timestamp := current_timestamp;
    startDate timestamp := endDate - (params->>'duration')::interval;
     operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN jsonb_build_object('id', 'discountReward', 'fact', 'discountReward', 'title', 'Number Of Times Discount Rewarded', 'value', '{ "type" : "int"}'::json, 'argument','couponId', 'operators', operators);
    ELSE
        FOR recordData IN
            SELECT * FROM crm."rewardHistory" WHERE "couponId" = (params->>'couponId')::int OR "campaignId" = (params->>'campaignId')::int
        LOOP
            IF recordData."created_at" > startDate AND recordData."created_at" < endDate  
                THEN totalDiscountCount := totalDiscountCount + 1;
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', totalDiscountCount, 'valueType','int','argument','couponId');
    END IF;
END;
$$;
CREATE FUNCTION rules."numberOfInventoryProducts"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."numberOfInventoryProductsFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."numberOfInventoryProductsFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    products jsonb;
    componentsArr jsonb;
    product jsonb;
    component jsonb;
    quant integer :=0;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'numberOfInventoryProducts', 'fact', 'numberOfInventoryProducts', 'title', 'Number Of Inventory Products', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        SELECT "cartInfo"->'products' FROM  crm."orderCart" WHERE "id" = (params->>'cartId')::integer INTO products;
        FOR product IN SELECT  * FROM jsonb_array_elements(products) LOOP
            IF product->>'type' = 'comboProduct'
              THEN SELECT product->'components' INTO componentsArr;
                FOR component IN SELECT * FROM jsonb_array_elements(componentsArr) LOOP
                    IF component->>'type' IS NOT NULL AND component->>'type' = 'inventoryProduct'
                    THEN quant := quant+1;
                    END IF;
                END LOOP;
            END IF;
            IF product->>'type' IS NOT NULL AND product->>'type' = 'inventoryProduct'
              THEN quant := quant+1;
            END IF;
        END LOOP;
        RETURN json_build_object('value', quant, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."numberOfLoyaltyPointsReward"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."numberOfLoyaltyPointsRewardFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."numberOfLoyaltyPointsRewardFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    recordData record;
    endDate timestamp := current_timestamp;
    startDate timestamp := endDate - (params->>'duration')::interval;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
    totalLoyaltyPointsCount int :=0 ;
BEGIN
    IF params->'read'
        THEN RETURN jsonb_build_object('id', 'loyaltyPointsReward', 'fact', 'loyaltyPointsReward', 'title', 'Number Of Times Loyalty Points Rewarded', 'value', '{ "type" : "int"}'::json, 'argument','couponId', 'operators', operators);
    ELSE
        FOR recordData IN
            SELECT * FROM crm."rewardHistory" WHERE "couponId" = (params->>'couponId')::int OR "campaignId" = (params->>'campaignId')::int
        LOOP
            IF recordData."created_at" > startDate AND recordData."created_at" < endDate  
                THEN totalLoyaltyPointsCount := totalLoyaltyPointsCount + 1;
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', totalLoyaltyPointsCount, 'valueType','int','argument','couponId');
    END IF;
END;
$$;
CREATE FUNCTION rules."numberOfMealkitProducts"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."numberOfMealkitProductsFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."numberOfMealkitProductsFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    products jsonb;
    componentsArr jsonb;
    product jsonb;
    component jsonb;
    quant integer :=0;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'numberOfMealkitProducts', 'fact', 'numberOfMealkitProducts', 'title', 'Number Of Meal Kit Products', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        SELECT "cartInfo"->'products' FROM  crm."orderCart" WHERE "id" = (params->>'cartId')::integer INTO products;
        FOR product IN SELECT  * FROM jsonb_array_elements(products) LOOP
            IF product->>'type' = 'comboProduct'
              THEN SELECT product->'components' INTO componentsArr;
                FOR component IN SELECT * FROM jsonb_array_elements(componentsArr) LOOP
                    IF component->'option'->>'type' IS NOT NULL AND component->'option'->>'type' = 'mealKit'
                    THEN  quant := quant +1;
                    END IF;
                END LOOP;
            END IF;
            IF product->'option'->>'type' IS NOT NULL AND product->'option'->>'type' = 'mealKit'
              THEN  quant := quant +1;
            END IF;
        END LOOP;
        RETURN json_build_object('value', quant, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."numberOfReadyToEatProducts"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."numberOfReadyToEatProductsFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."numberOfReadyToEatProductsFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    products jsonb;
    componentsArr jsonb;
    product jsonb;
    component jsonb;
    quant integer :=0;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'numberOfReadyToEatProducts', 'fact', 'numberOfReadyToEatProducts', 'title', 'Number Of Ready To Eat Products', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        SELECT "cartInfo"->'products' FROM  crm."orderCart" WHERE "id" = (params->>'cartId')::integer INTO products;
        FOR product IN SELECT  * FROM jsonb_array_elements(products) LOOP
            IF product->>'type' = 'comboProduct'
              THEN SELECT product->'components' INTO componentsArr;
                FOR component IN SELECT * FROM jsonb_array_elements(componentsArr) LOOP
                    IF component->'option'->>'type' IS NOT NULL AND component->'option'->>'type' = 'readyToEat'
                    THEN quant := quant+1;
                    END IF;
                END LOOP;
            END IF;
            IF product->'option'->>'type' IS NOT NULL AND product->'option'->>'type' = 'readyToEat'
              THEN quant := quant+1;
            END IF;
        END LOOP;
        RETURN json_build_object('value', quant, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."numberOfWalletAmountReward"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."numberOfWalletAmountRewardFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."numberOfWalletAmountRewardFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    recordData record;
    totalWalletAmountCount int :=0 ;
    endDate timestamp := current_timestamp;
    startDate timestamp := endDate - (params->>'duration')::interval;
     operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN jsonb_build_object('id', 'numberOfWalletAmountReward', 'fact', 'numberOfWalletAmountReward', 'title', 'Number Of Times Wallet Amount Rewarded', 'value', '{ "type" : "int"}'::json, 'argument','couponId', 'operators', operators);
    ELSE
        FOR recordData IN
            SELECT * FROM crm."rewardHistory" WHERE "couponId" = (params->>'couponId')::int OR "campaignId" = (params->>'campaignId')::int
        LOOP
            IF recordData."created_at" > startDate AND recordData."created_at" < endDate  
                THEN totalWalletAmountCount := totalWalletAmountCount + 1;
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', totalWalletAmountCount, 'valueType','int','argument','couponId');
    END IF;
END;
$$;
CREATE FUNCTION rules."orderAmount"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."orderAmountFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."orderAmountFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    orderAmount numeric;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'orderAmount', 'fact', 'orderAmount', 'title', 'Order Amount', 'value', '{ "type" : "int" }'::json,'argument','orderId', 'operators', operators);
    ELSE
        SELECT "amountPaid" FROM "order"."order" WHERE id = (params->>'orderId')::integer INTO orderAmount;
        RETURN json_build_object('value', orderAmount, 'valueType','numeric','arguments','orderId');
    END IF;
END;
$$;
CREATE FUNCTION rules."orderCountWithDuration"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."orderCountWithDurationFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."orderCountWithDurationFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    dateArray timestamp[];
    dateArr timestamp;
    orderCount integer := 0;
    enddate timestamp := current_timestamp;
    startdate timestamp := enddate - (params->>'duration')::interval;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'orderCountWithDuration', 'fact', 'orderCountWithDuration', 'title', 'Order Count With Duration', 'value', '{ "type" : "int", "duration" : true }'::json ,'argument','keycloakId', 'operators', operators);
    ELSE
          dateArray := ARRAY(SELECT "created_at" FROM crm."orderCart" WHERE "customerKeycloakId" = (params->>'keycloakId')::text AND "orderId" IS NOT NULL);
          FOREACH dateArr IN ARRAY dateArray
          LOOP 
              IF dateArr > startdate AND dateArr < enddate 
                THEN orderCount := orderCount + 1;
              END IF;
          END LOOP;
          RETURN json_build_object('value',orderCount,'valueType','integer','argument','keycloakId');
    END IF;
END;
$$;
CREATE FUNCTION rules."referralStatus"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."referralStatusFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."referralStatusFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    referralStatus text ;
     operators text[] := ARRAY['equal', 'notEqual'];
BEGIN
IF params->'read'
        THEN RETURN json_build_object('id', 'referralStatus', 'fact', 'referralStatus', 'title', 'Customer Referral Status', 'value', '{ "type" : "text" }'::josn,'argument','keycloakId', 'operators', operators);
    ELSE
          SELECT "status" FROM crm."customerReferral" WHERE "keycloakId" = (params->>'keycloakId')::text INTO referralStatus;
          RETURN json_build_object('value', referralStatus, 'valueType','text','argument','keycloakId');
    END IF;
END;
$$;
CREATE FUNCTION rules."rruleHasDateFunc"(rrule _rrule.rruleset, d timestamp without time zone) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    res boolean;
BEGIN
  SELECT rrule @> d into res;
  RETURN res;
END;
$$;
CREATE FUNCTION rules."runWithOperator"(operator text, vals jsonb) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    res boolean := false;
BEGIN
    -- IF vals->>'fact' IS NOT NULL THEN
        IF operator = 'rruleHasDate'
            THEN SELECT rules."rruleHasDateFunc"((vals->'condition')::text::jsonb::_rrule.rruleset, (vals->'fact')::text::timestamp) INTO res;
        ELSIF operator = 'equal'
            THEN SELECT (vals->'fact')::text = (vals->'condition')::text INTO res;
        ELSIF operator = 'notEqual'
            THEN SELECT (vals->'fact')::text != (vals->'condition')::text INTO res;
        ELSIF operator = 'greaterThan'
            THEN SELECT (vals->>'fact')::numeric > (vals->>'condition')::numeric INTO res;
        ELSIF operator = 'greaterThanInclusive'
            THEN SELECT (vals->>'fact')::numeric >= (vals->>'condition')::numeric INTO res;
        ELSIF operator = 'lessThan'
            THEN SELECT (vals->>'fact')::numeric < (vals->>'condition')::numeric INTO res;
        ELSIF operator = 'lessThanInclusive'
            THEN SELECT (vals->>'fact')::numeric <= (vals->>'condition')::numeric INTO res;
        ELSIF operator = 'contains'
            THEN SELECT vals->>'fact' LIKE CONCAT('%', vals->>'condition', '%') INTO res;
        ELSIF operator = 'doesNotContain'
            THEN SELECT vals->>'fact' NOT LIKE CONCAT('%', vals->>'condition', '%') INTO res;
        ELSIF operator = 'in'
            THEN SELECT vals->>'condition' = ANY(ARRAY(SELECT jsonb_array_elements_text(vals->'fact'))) INTO res;
        ELSIF operator = 'notIn'
            THEN SELECT vals->>'condition' != ALL(ARRAY(SELECT jsonb_array_elements_text(vals->'fact'))) INTO res;
        ELSE
            SELECT false INTO res;
        END IF;
    -- END IF;
    RETURN res;
END;
$$;
CREATE FUNCTION rules."totalLoyaltyPointsFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    recordData record;
    endDate timestamp := current_timestamp;
    startDate timestamp := endDate - (params->>'duration')::interval;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
    totalLoyaltyPoints int :=0 ;
BEGIN
    IF params->'read'
        THEN RETURN jsonb_build_object('id', 'loyaltyPoints', 'fact', 'loyaltyPoints', 'title', 'Loyalty Points', 'value', '{ "type" : "int"}'::json, 'argument','couponId', 'operators', operators);
    ELSE
        FOR recordData IN
            SELECT * FROM crm."rewardHistory" WHERE "couponId" = (params->>'couponId')::int OR "campaignId" = (params->>'campaignId')::int
        LOOP
            IF recordData."created_at" > startDate AND recordData."created_at" < endDate  
                THEN totalLoyaltyPoints := totalLoyaltyPoints + recordData."loyaltyPoints";
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', totalLoyaltyPoints, 'valueType','numeric','argument','couponId');
    END IF;
END;
$$;
CREATE FUNCTION rules."totalNumberOfComboProducts"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."totalNumberOfComboProductsFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."totalNumberOfComboProductsFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    products jsonb;
    product jsonb;
    quant integer :=0;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'totalNumberOfComboProducts', 'fact', 'totalNumberOfComboProducts', 'title', 'Total Number Of Combo Products (with Quantity)', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        SELECT "cartInfo"->'products' FROM  crm."orderCart" WHERE "id" = (params->>'cartId')::integer INTO products;
        FOR product IN SELECT  * FROM jsonb_array_elements(products) LOOP
            IF product->>'type' = 'comboProduct'
              THEN SELECT quant + (product->>'quantity')::int INTO quant;
            END IF;
        END LOOP;
        RETURN json_build_object('value', quant, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."totalNumberOfCustomizableProducts"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."totalNumberOfCustomizableProductsFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."totalNumberOfCustomizableProductsFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    products jsonb;
    componentsArr jsonb;
    product jsonb;
    component jsonb;
    quant integer :=0;
     operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'totalNumberOfCustomizableProducts', 'fact', 'totalNumberOfCustomizableProducts', 'title', ' Total Number Of Customizable Products (with Quantity)', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        SELECT "cartInfo"->'products' FROM  crm."orderCart" WHERE "id" = (params->>'cartId')::integer INTO products;
        FOR product IN SELECT  * FROM jsonb_array_elements(products) LOOP
            IF product->>'type' = 'comboProduct'
              THEN SELECT product->'components' INTO componentsArr;
                FOR component IN SELECT * FROM jsonb_array_elements(componentsArr) LOOP
                    IF component->>'customizableProductId' IS NOT NULL
                    THEN SELECT quant + (component->>'quantity')::int INTO quant;
                    END IF;
                END LOOP;
            END IF;
            IF product->>'customizableProductId' IS NOT NULL
              THEN SELECT quant + (product->>'quantity')::int INTO quant;
            END IF;
        END LOOP;
        RETURN json_build_object('value', quant, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."totalNumberOfInventoryProducts"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."totalNumberOfInventoryProductsFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."totalNumberOfInventoryProductsFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    products jsonb;
    componentsArr jsonb;
    product jsonb;
    component jsonb;
    quant integer :=0;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'totalNumberOfInventroyProducts', 'fact', 'totalNumberOfInventoryProducts', 'title', 'Total Number Of Inventory Products (with Quantity)', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        SELECT "cartInfo"->'products' FROM  crm."orderCart" WHERE "id" = (params->>'cartId')::integer INTO products;
        FOR product IN SELECT  * FROM jsonb_array_elements(products) LOOP
            IF product->>'type' = 'comboProduct'
              THEN SELECT product->'components' INTO componentsArr;
                FOR component IN SELECT * FROM jsonb_array_elements(componentsArr) LOOP
                    IF component->>'type' IS NOT NULL AND component->>'type' = 'inventoryProduct'
                    THEN SELECT quant + (component->>'quantity')::int INTO quant;
                    END IF;
                END LOOP;
            END IF;
            IF product->>'type' IS NOT NULL AND product->>'type' = 'inventoryProduct'
              THEN SELECT quant + (product->>'quantity')::int INTO quant;
            END IF;
        END LOOP;
        RETURN json_build_object('value', quant, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."totalNumberOfMealkitProducts"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."totalNumberOfMealkitProductsFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."totalNumberOfMealkitProductsFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    products jsonb;
    componentsArr jsonb;
    product jsonb;
    component jsonb;
    quant integer :=0;
     operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'totalNumberOfMealkitProducts', 'fact', 'totalNumberOfMealkitProducts', 'title', 'Total Number Of Meal Kit Products (with Quantity)', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        SELECT "cartInfo"->'products' FROM  crm."orderCart" WHERE "id" = (params->>'cartId')::integer INTO products;
        FOR product IN SELECT  * FROM jsonb_array_elements(products) LOOP
            IF product->>'type' = 'comboProduct'
              THEN SELECT product->'components' INTO componentsArr;
                FOR component IN SELECT * FROM jsonb_array_elements(componentsArr) LOOP
                    IF component->'option'->>'type' IS NOT NULL AND component->'option'->>'type' = 'mealKit'
                    THEN SELECT quant + (component->>'quantity')::int INTO quant;
                    END IF;
                END LOOP;
            END IF;
            IF product->'option'->>'type' IS NOT NULL AND product->'option'->>'type' = 'mealKit'
              THEN SELECT quant + (product->>'quantity')::int INTO quant;
            END IF;
        END LOOP;
        RETURN json_build_object('value', quant, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."totalNumberOfReadyToEatProducts"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."totalNumberOfReadyToEatProductsFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."totalNumberOfReadyToEatProductsFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    products jsonb;
    componentsArr jsonb;
    product jsonb;
    component jsonb;
    quant integer :=0;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'totalNumberOfReadyToEatProducts', 'fact', 'totalNumberOfReadyToEatProducts', 'title', 'Total Number Of Ready To Eat Products (with Quantity)', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        SELECT "cartInfo"->'products' FROM  crm."orderCart" WHERE "id" = (params->>'cartId')::integer INTO products;
        FOR product IN SELECT  * FROM jsonb_array_elements(products) LOOP
            IF product->>'type' = 'comboProduct'
              THEN SELECT product->'components' INTO componentsArr;
                FOR component IN SELECT * FROM jsonb_array_elements(componentsArr) LOOP
                    IF component->'option'->>'type' IS NOT NULL AND component->'option'->>'type' = 'readyToEat'
                    THEN SELECT quant + (component->>'quantity')::int INTO quant;
                    END IF;
                END LOOP;
            END IF;
            IF product->'option'->>'type' IS NOT NULL AND product->'option'->>'type' = 'readyToEat'
              THEN SELECT quant + (product->>'quantity')::int INTO quant;
            END IF;
        END LOOP;
        RETURN json_build_object('value', quant, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."walletAmountReward"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."walletAmountRewardFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."walletAmountRewardFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    recordData record;
    totalWalletAmount numeric :=0 ;
    endDate timestamp := current_timestamp;
    startDate timestamp := endDate - (params->>'duration')::interval;
     operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN jsonb_build_object('id', 'walletAmountReward', 'fact', 'walletAmountReward', 'title', 'Wallet Amount Reward', 'value', '{ "type" : "int", "duration" : true}'::json, 'argument','couponId', 'operators', operators);
    ELSE
        FOR recordData IN
            SELECT * FROM crm."rewardHistory" WHERE "couponId" = (params->>'couponId')::int OR "campaignId" = (params->>'campaignId')::int
        LOOP
            IF recordData."created_at" > startDate AND recordData."created_at" < endDate  
                THEN totalWalletAmount := totalWalletAmount + recordData."walletAmount";
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', totalWalletAmount, 'valueType','numeric','argument','couponId');
    END IF;
END;
$$;
CREATE FUNCTION safety.set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;
CREATE FUNCTION settings.set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;
CREATE FUNCTION "simpleRecipe".issimplerecipevalid(recipe "simpleRecipe"."simpleRecipe") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
BEGIN
    IF recipe.utensils IS NULL OR jsonb_array_length(recipe.utensils) = 0
        THEN return json_build_object('status', false, 'error', 'Utensils not provided');
    ELSIF recipe.procedures IS NULL OR jsonb_array_length(recipe.procedures) = 0
        THEN return json_build_object('status', false, 'error', 'Cooking steps are not provided');
    ELSIF recipe.ingredients IS NULL OR jsonb_array_length(recipe.ingredients) = 0
        THEN return json_build_object('status', false, 'error', 'Ingredients are not provided');
    ELSEIF recipe.image IS NULL OR LENGTH(recipe.image) = 0
        THEN return json_build_object('status', false, 'error', 'Image is not provided');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE TABLE "simpleRecipe"."simpleRecipeYield" (
    id integer NOT NULL,
    "simpleRecipeId" integer NOT NULL,
    yield jsonb NOT NULL
);
CREATE FUNCTION "simpleRecipe"."yieldCost"(yield "simpleRecipe"."simpleRecipeYield") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    bridge record;
    cost numeric;
    finalCost numeric := 0;
BEGIN
    FOR bridge IN SELECT "ingredientSachetId" FROM "simpleRecipe"."simpleRecipeYield_ingredientSachet" WHERE "recipeYieldId" = yield.id LOOP
        SELECT ingredient."sachetCost"(bridge."ingredientSachetId") into cost;
        IF cost IS NOT NULL
            THEN finalCost = finalCost + cost;
        END IF;
    END LOOP;
    RETURN finalCost;
END
$$;
CREATE FUNCTION "simpleRecipe"."yieldNutritionalInfo"(yield "simpleRecipe"."simpleRecipeYield") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    bridge record;
    info jsonb;
    infoArr jsonb[];
    finalInfo jsonb;
BEGIN
    FOR bridge IN SELECT "ingredientSachetId" FROM "simpleRecipe"."simpleRecipeYield_ingredientSachet" WHERE "recipeYieldId" = yield.id LOOP
        SELECT ingredient."sachetNutritionalInfo"(bridge."ingredientSachetId") into info;
        IF info IS NOT NULL
            THEN SELECT jsonb_build_object(
                        'per', (info->>'per')::numeric,
                        'iron', COALESCE(CAST(finalInfo->>'iron'AS decimal) + CAST(info->>'iron' AS decimal), 0),
                        'sodium', COALESCE(CAST(finalInfo->>'sodium' AS decimal) + CAST(info->>'sodium' AS decimal), 0),
                        'sugars', COALESCE(CAST(finalInfo->>'sugars' AS decimal) + CAST(info->>'sugars' AS decimal), 0),
                        'calcium', COALESCE(CAST(finalInfo->>'calcium' AS decimal) + CAST(info->>'calcium' AS decimal), 0),
                        'protein', COALESCE(CAST(finalInfo->>'protein' AS decimal) + CAST(info->>'protein' AS decimal), 0),
                        'calories', COALESCE(CAST(finalInfo->>'calories' AS decimal) + CAST(info->>'calories' AS decimal), 0),
                        'totalFat', COALESCE(CAST(finalInfo->>'totalFat' AS decimal) + CAST(info->>'totalFat' AS decimal), 0),
                        'transFat', COALESCE(CAST(finalInfo->>'transFat' AS decimal) + CAST(info->>'transFat' AS decimal), 0),
                        'vitaminA', COALESCE(CAST(finalInfo->>'vitaminA' AS decimal) + CAST(info->>'vitaminA' AS decimal), 0),
                        'vitaminC', COALESCE(CAST(finalInfo->>'vitaminC' AS decimal) + CAST(info->>'vitaminC' AS decimal), 0),
                        'cholesterol', COALESCE(CAST(finalInfo->>'cholesterol' AS decimal) + CAST(info->>'cholesterol' AS decimal), 0),
                        'dietaryFibre', COALESCE(CAST(finalInfo->>'dietaryFibre' AS decimal) + CAST(info->>'dietaryFibre' AS decimal), 0),
                        'saturatedFat', COALESCE(CAST(finalInfo->>'saturatedFat' AS decimal) + CAST(info->>'saturatedFat' AS decimal), 0),
                        'totalCarbohydrates', COALESCE(CAST(finalInfo->>'totalCarbohydrates' AS decimal) + CAST(info->>'totalCarbohydrates' AS decimal), 0)
                    ) into finalInfo;
        END IF;
    END LOOP;
    RETURN finalInfo;
END
$$;
CREATE TABLE subscription."subscriptionOccurence" (
    id integer NOT NULL,
    "fulfillmentDate" date NOT NULL,
    "cutoffTimeStamp" timestamp without time zone NOT NULL,
    "subscriptionId" integer NOT NULL,
    "startTimeStamp" timestamp without time zone,
    assets jsonb
);
CREATE FUNCTION subscription."calculateIsValid"(occurence subscription."subscriptionOccurence") RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    currentTime timestamp;
    cutoffTime timestamp;
BEGIN
    SELECT NOW() into currentTime;
    SELECT occurence."cutoffTimeStamp" into cutoffTime;
RETURN
    currentTime < cutoffTime;
END
$$;
CREATE FUNCTION subscription."calculateIsVisible"(occurence subscription."subscriptionOccurence") RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    currentTime timestamp;
    startTime timestamp;
BEGIN
    SELECT NOW() into currentTime ;
    SELECT occurence."startTimeStamp" into startTime;
RETURN
    currentTime > startTime;
END
$$;
CREATE TABLE subscription."subscriptionOccurence_product" (
    "subscriptionOccurenceId" integer,
    "productSku" uuid,
    "simpleRecipeProductOptionId" integer NOT NULL,
    "simpleRecipeProductId" integer NOT NULL,
    "addonPrice" numeric,
    "addonLabel" text,
    "productCategory" text,
    "isAvailable" boolean DEFAULT true,
    "isVisible" boolean DEFAULT true,
    "isSingleSelect" boolean DEFAULT true NOT NULL,
    "subscriptionId" integer,
    id integer NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
CREATE FUNCTION subscription."cartItem"(x subscription."subscriptionOccurence_product") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    item jsonb;
    productId int;
    optionId int;
BEGIN
    SELECT x."simpleRecipeProductId" into productId;
    SELECT x."simpleRecipeProductOptionId" into optionId;
    SELECT products."simpleRecipeProductCartItemById"(productId, optionId) into item;
    RETURN item;
END
$$;
CREATE TABLE subscription."subscriptionItemCount" (
    id integer NOT NULL,
    "subscriptionServingId" integer NOT NULL,
    count integer NOT NULL,
    "metaDetails" jsonb,
    price numeric,
    "isActive" boolean DEFAULT false
);
CREATE FUNCTION subscription."isSubscriptionItemCountValid"(itemcount subscription."subscriptionItemCount") RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    count int;
BEGIN
    SELECT * FROM subscription.subscription where "subscriptionItemCountId" = itemCount.id LIMIT 1 into count;
    IF count > 0 THEN
        return true;
    ELSE
        return false;
    END IF;
END;
$$;
CREATE TABLE subscription."subscriptionServing" (
    id integer NOT NULL,
    "subscriptionTitleId" integer NOT NULL,
    "servingSize" integer NOT NULL,
    "metaDetails" jsonb,
    "defaultSubscriptionItemCountId" integer,
    "isActive" boolean DEFAULT false NOT NULL
);
CREATE FUNCTION subscription."isSubscriptionServingValid"(serving subscription."subscriptionServing") RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    count int;
BEGIN
    SELECT * FROM subscription."subscriptionItemCount" where "subscriptionServingId" = serving.id AND "isActive" = true LIMIT 1 into count;
    IF count > 0 THEN
        return true;
    ELSE
        return false;
    END IF;
END;
$$;
CREATE TABLE subscription."subscriptionTitle" (
    id integer NOT NULL,
    title text NOT NULL,
    "metaDetails" jsonb,
    "defaultSubscriptionServingId" integer,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    "isActive" boolean DEFAULT false NOT NULL
);
CREATE FUNCTION subscription."isSubscriptionTitleValid"(title subscription."subscriptionTitle") RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    count int;
BEGIN
    SELECT * FROM subscription."subscriptionServing" where "subscriptionTitleId" = title.id AND "isActive" = true LIMIT 1 into count;
    IF count > 0 THEN
        return true;
    ELSE
        return false;
    END IF;
END;
$$;
CREATE FUNCTION subscription.set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;
CREATE TABLE brands.brand (
    id integer NOT NULL,
    domain text,
    "isDefault" boolean DEFAULT false NOT NULL,
    title text,
    "isPublished" boolean DEFAULT true NOT NULL,
    "onDemandRequested" boolean DEFAULT false NOT NULL,
    "subscriptionRequested" boolean DEFAULT false NOT NULL
);
CREATE TABLE brands."brand_storeSetting" (
    "brandId" integer NOT NULL,
    "storeSettingId" integer NOT NULL,
    value jsonb
);
CREATE TABLE brands."brand_subscriptionStoreSetting" (
    "brandId" integer NOT NULL,
    "subscriptionStoreSettingId" integer NOT NULL,
    value jsonb
);
CREATE SEQUENCE brands.shop_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE brands.shop_id_seq OWNED BY brands.brand.id;
CREATE TABLE brands."storeSetting" (
    id integer NOT NULL,
    identifier text NOT NULL,
    value jsonb,
    type text
);
CREATE SEQUENCE brands."storeSetting_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE brands."storeSetting_id_seq" OWNED BY brands."storeSetting".id;
CREATE TABLE brands."subscriptionStoreSetting" (
    id integer NOT NULL,
    identifier text NOT NULL,
    value jsonb,
    type text
);
CREATE SEQUENCE brands."subscriptionStoreSetting_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE brands."subscriptionStoreSetting_id_seq" OWNED BY brands."subscriptionStoreSetting".id;
CREATE TABLE content.faqs (
    id integer NOT NULL,
    page text NOT NULL,
    identifier text NOT NULL,
    "isVisible" boolean DEFAULT false NOT NULL,
    heading text,
    "subHeading" text,
    "metaDetails" jsonb
);
CREATE SEQUENCE content.faqs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE content.faqs_id_seq OWNED BY content.faqs.id;
CREATE TABLE content."informationBlock" (
    id integer NOT NULL,
    title text,
    description text,
    thumbnail text,
    "faqsId" integer,
    "informationGridId" integer
);
CREATE SEQUENCE content."informationBlock_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE content."informationBlock_id_seq" OWNED BY content."informationBlock".id;
CREATE TABLE content."informationGrid" (
    id integer NOT NULL,
    page text NOT NULL,
    "isVisible" boolean DEFAULT false NOT NULL,
    heading text,
    "subHeading" text,
    "metaDetails" jsonb,
    identifier text NOT NULL,
    "columnsCount" integer DEFAULT 3,
    "blockOrientation" text DEFAULT 'row'::text
);
CREATE SEQUENCE content."informationGrid_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE content."informationGrid_id_seq" OWNED BY content."informationGrid".id;
CREATE TABLE crm.brand_customer (
    id integer NOT NULL,
    "keycloakId" text NOT NULL,
    "brandId" integer NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
CREATE SEQUENCE crm."brandCustomer_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE crm."brandCustomer_id_seq" OWNED BY crm.brand_customer.id;
CREATE TABLE crm.brand_campaign (
    "brandId" integer NOT NULL,
    "campaignId" integer NOT NULL,
    "isActive" boolean DEFAULT true
);
CREATE TABLE crm.brand_coupon (
    "brandId" integer NOT NULL,
    "couponId" integer NOT NULL,
    "isActive" boolean DEFAULT true NOT NULL
);
CREATE TABLE crm.campaign (
    id integer NOT NULL,
    type text NOT NULL,
    "metaDetails" jsonb,
    "conditionId" integer,
    "isRewardMulti" boolean DEFAULT false NOT NULL,
    "isActive" boolean DEFAULT false NOT NULL,
    priority integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
CREATE TABLE crm."campaignType" (
    id integer NOT NULL,
    value text NOT NULL
);
CREATE SEQUENCE crm."campaignType_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE crm."campaignType_id_seq" OWNED BY crm."campaignType".id;
CREATE SEQUENCE crm.campaign_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE crm.campaign_id_seq OWNED BY crm.campaign.id;
CREATE TABLE crm.coupon (
    id integer NOT NULL,
    "isActive" boolean DEFAULT false NOT NULL,
    "metaDetails" jsonb,
    code text NOT NULL,
    "isRewardMulti" boolean DEFAULT false NOT NULL,
    "visibleConditionId" integer,
    "isVoucher" boolean DEFAULT false NOT NULL
);
CREATE SEQUENCE crm.coupon_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE crm.coupon_id_seq OWNED BY crm.coupon.id;
CREATE TABLE crm.customer (
    id integer NOT NULL,
    source text NOT NULL,
    email text NOT NULL,
    "keycloakId" text NOT NULL,
    "clientId" text,
    "isSubscriber" boolean DEFAULT false NOT NULL,
    "subscriptionId" integer,
    "subscriptionAddressId" uuid,
    "subscriptionPaymentMethodId" text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    "isTest" boolean DEFAULT false NOT NULL,
    "sourceBrandId" integer DEFAULT 1 NOT NULL
);
CREATE TABLE crm."customerReferral" (
    id integer NOT NULL,
    "keycloakId" text NOT NULL,
    "referralCode" uuid DEFAULT public.gen_random_uuid() NOT NULL,
    "referredByCode" uuid,
    "referralStatus" text DEFAULT 'PENDING'::text NOT NULL,
    "referralCampaignId" integer,
    "signupCampaignId" integer,
    "signupStatus" text DEFAULT 'PENDING'::text NOT NULL,
    "brandId" integer DEFAULT 1 NOT NULL
);
CREATE SEQUENCE crm."customerReferral_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE crm."customerReferral_id_seq" OWNED BY crm."customerReferral".id;
CREATE VIEW crm."customerView" AS
 SELECT customer.id,
    crm."lastActiveDate"(customer."keycloakId") AS lastactivedate,
    age(crm."lastActiveDate"(customer."keycloakId")) AS inactivesince,
    date_part('hour'::text, customer.created_at) AS signuphour,
    date_part('month'::text, customer.created_at) AS signupmonth
   FROM crm.customer;
CREATE SEQUENCE crm.customer_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE crm.customer_id_seq OWNED BY crm.customer.id;
CREATE TABLE crm.customer_voucher (
    "keycloakId" text NOT NULL,
    "couponId" integer NOT NULL,
    "isUsed" boolean DEFAULT false NOT NULL,
    id integer NOT NULL
);
CREATE SEQUENCE crm.customer_voucher_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE crm.customer_voucher_id_seq OWNED BY crm.customer_voucher.id;
CREATE SEQUENCE crm.fact_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE crm.fact_id_seq OWNED BY crm.fact.id;
CREATE TABLE crm."loyaltyPoint" (
    id integer NOT NULL,
    "keycloakId" text NOT NULL,
    points integer DEFAULT 0 NOT NULL,
    "isActive" boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    "brandId" integer DEFAULT 1 NOT NULL
);
CREATE TABLE crm."loyaltyPointTransaction" (
    id integer NOT NULL,
    "loyaltyPointId" integer NOT NULL,
    points integer NOT NULL,
    "orderCartId" integer,
    type text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    "amountRedeemed" numeric,
    "customerReferralId" integer
);
CREATE SEQUENCE crm."loyaltyPointTransaction_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE crm."loyaltyPointTransaction_id_seq" OWNED BY crm."loyaltyPointTransaction".id;
CREATE SEQUENCE crm."loyaltyPoint_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE crm."loyaltyPoint_id_seq" OWNED BY crm."loyaltyPoint".id;
CREATE SEQUENCE crm."orderCart_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE crm."orderCart_id_seq" OWNED BY crm."orderCart".id;
CREATE TABLE crm."orderCart_rewards" (
    id integer NOT NULL,
    "orderCartId" integer NOT NULL,
    "rewardId" integer NOT NULL
);
CREATE SEQUENCE crm."orderCart_rewards_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE crm."orderCart_rewards_id_seq" OWNED BY crm."orderCart_rewards".id;
CREATE TABLE crm.reward (
    id integer NOT NULL,
    type text NOT NULL,
    "couponId" integer,
    "conditionId" integer,
    priority integer DEFAULT 1,
    "campaignId" integer,
    "rewardValue" jsonb
);
CREATE TABLE crm."rewardHistory" (
    id integer NOT NULL,
    "rewardId" integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    "couponId" integer,
    "campaignId" integer,
    "keycloakId" text NOT NULL,
    "orderCartId" integer,
    "orderId" integer,
    discount numeric,
    "loyaltyPointTransactionId" integer,
    "loyaltyPoints" integer,
    "walletAmount" numeric,
    "walletTransactionId" integer
);
CREATE SEQUENCE crm."rewardHistory_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE crm."rewardHistory_id_seq" OWNED BY crm."rewardHistory".id;
CREATE TABLE crm."rewardType" (
    id integer NOT NULL,
    value text NOT NULL,
    "useForCoupon" boolean NOT NULL,
    handler text NOT NULL
);
CREATE TABLE crm."rewardType_campaignType" (
    "rewardTypeId" integer NOT NULL,
    "campaignTypeId" integer NOT NULL
);
CREATE SEQUENCE crm."rewardType_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE crm."rewardType_id_seq" OWNED BY crm."rewardType".id;
CREATE SEQUENCE crm.reward_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE crm.reward_id_seq OWNED BY crm.reward.id;
CREATE TABLE crm."rmkOrder" (
    id uuid NOT NULL,
    "rmkCartId" uuid NOT NULL,
    "orderCartId" integer NOT NULL,
    "keycloakCustomerId" text
);
CREATE TABLE crm.session (
    id integer NOT NULL,
    "keycloakId" text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE SEQUENCE crm.session_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE crm.session_id_seq OWNED BY crm.session.id;
CREATE TABLE crm.wallet (
    id integer NOT NULL,
    "keycloakId" text,
    amount numeric DEFAULT 0 NOT NULL,
    "isActive" boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    "brandId" integer DEFAULT 1 NOT NULL
);
CREATE TABLE crm."walletTransaction" (
    id integer NOT NULL,
    "walletId" integer NOT NULL,
    amount numeric NOT NULL,
    type text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    "orderCartId" integer,
    "customerReferralId" integer
);
CREATE SEQUENCE crm."walletTransaction_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE crm."walletTransaction_id_seq" OWNED BY crm."walletTransaction".id;
CREATE SEQUENCE crm.wallet_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE crm.wallet_id_seq OWNED BY crm.wallet.id;
CREATE TABLE "deviceHub".computer (
    "printNodeId" integer NOT NULL,
    name text,
    inet text,
    inet6 text,
    hostname text,
    jre text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    state text,
    version text
);
CREATE TABLE "deviceHub".config (
    id integer NOT NULL,
    name text NOT NULL,
    value jsonb NOT NULL
);
CREATE SEQUENCE "deviceHub".config_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "deviceHub".config_id_seq OWNED BY "deviceHub".config.id;
CREATE TABLE "deviceHub"."labelTemplate" (
    id integer NOT NULL,
    name text NOT NULL
);
CREATE SEQUENCE "deviceHub"."labelTemplate_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "deviceHub"."labelTemplate_id_seq" OWNED BY "deviceHub"."labelTemplate".id;
CREATE TABLE "deviceHub".printer (
    "printNodeId" integer NOT NULL,
    "computerId" integer NOT NULL,
    name text NOT NULL,
    description text,
    state text NOT NULL,
    bins jsonb,
    "collate" boolean,
    copies integer,
    color boolean,
    dpis jsonb,
    extent jsonb,
    medias jsonb,
    nup jsonb,
    papers jsonb,
    printrate jsonb,
    supports_custom_paper_size boolean,
    duplex boolean,
    "printerType" text
);
CREATE TABLE "deviceHub"."printerType" (
    type text NOT NULL
);
CREATE TABLE "deviceHub".scale (
    "deviceName" text NOT NULL,
    "deviceNum" integer NOT NULL,
    "computerId" integer NOT NULL,
    vendor text,
    "vendorId" integer,
    "productId" integer,
    port text,
    count integer,
    measurement jsonb,
    "ntpOffset" integer,
    "ageOfData" integer,
    "stationId" integer,
    active boolean DEFAULT true,
    id integer NOT NULL
);
CREATE SEQUENCE "deviceHub".scale_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "deviceHub".scale_id_seq OWNED BY "deviceHub".scale.id;
CREATE TABLE fulfilment.brand_recurrence (
    "brandId" integer NOT NULL,
    "recurrenceId" integer NOT NULL,
    "isActive" boolean DEFAULT true NOT NULL
);
CREATE TABLE fulfilment.charge (
    id integer NOT NULL,
    "orderValueFrom" numeric NOT NULL,
    "orderValueUpto" numeric NOT NULL,
    charge numeric NOT NULL,
    "mileRangeId" integer,
    "autoDeliverySelection" boolean DEFAULT true NOT NULL
);
CREATE SEQUENCE fulfilment.charge_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE fulfilment.charge_id_seq OWNED BY fulfilment.charge.id;
CREATE TABLE fulfilment."deliveryPreferenceByCharge" (
    "chargeId" integer NOT NULL,
    "clauseId" integer NOT NULL,
    "isActive" boolean DEFAULT true NOT NULL,
    priority integer NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
CREATE TABLE fulfilment."deliveryService" (
    id integer NOT NULL,
    "partnershipId" integer,
    "isThirdParty" boolean DEFAULT true NOT NULL,
    "isActive" boolean DEFAULT false,
    "companyName" text NOT NULL,
    logo text
);
CREATE SEQUENCE fulfilment."deliveryService_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE fulfilment."deliveryService_id_seq" OWNED BY fulfilment."deliveryService".id;
CREATE TABLE fulfilment."fulfillmentType" (
    value text NOT NULL,
    "isActive" boolean DEFAULT true NOT NULL
);
CREATE SEQUENCE fulfilment."mileRange_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE fulfilment."mileRange_id_seq" OWNED BY fulfilment."mileRange".id;
CREATE TABLE fulfilment.recurrence (
    id integer NOT NULL,
    rrule text NOT NULL,
    type text DEFAULT 'PREORDER_DELIVERY'::text NOT NULL,
    "isActive" boolean DEFAULT true NOT NULL
);
CREATE SEQUENCE fulfilment.recurrence_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE fulfilment.recurrence_id_seq OWNED BY fulfilment.recurrence.id;
CREATE SEQUENCE fulfilment."timeSlot_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE fulfilment."timeSlot_id_seq" OWNED BY fulfilment."timeSlot".id;
CREATE TABLE imports.import (
    id integer NOT NULL,
    entity text NOT NULL,
    file text NOT NULL,
    "importType" text NOT NULL,
    confirm boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    status text
);
CREATE TABLE imports."importHistory" (
    id integer NOT NULL,
    "importId" integer NOT NULL
);
CREATE SEQUENCE imports."importHistory_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE imports."importHistory_id_seq" OWNED BY imports."importHistory".id;
CREATE SEQUENCE imports.imports_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE imports.imports_id_seq OWNED BY imports.import.id;
CREATE TABLE ingredient."ingredientProcessing" (
    id integer NOT NULL,
    "processingName" text NOT NULL,
    "ingredientId" integer NOT NULL,
    "nutritionalInfo" jsonb,
    cost jsonb
);
CREATE SEQUENCE ingredient."ingredientProcessing_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE ingredient."ingredientProcessing_id_seq" OWNED BY ingredient."ingredientProcessing".id;
CREATE SEQUENCE ingredient."ingredientSachet_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE ingredient."ingredientSachet_id_seq" OWNED BY ingredient."ingredientSachet".id;
CREATE SEQUENCE ingredient.ingredient_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE ingredient.ingredient_id_seq OWNED BY ingredient.ingredient.id;
CREATE TABLE ingredient."modeOfFulfillmentEnum" (
    value text NOT NULL,
    description text
);
CREATE SEQUENCE ingredient."modeOfFulfillment_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE ingredient."modeOfFulfillment_id_seq" OWNED BY ingredient."modeOfFulfillment".id;
CREATE TABLE insights.chart (
    id integer NOT NULL,
    "layoutType" text DEFAULT 'HERO'::text,
    config jsonb,
    "insisghtsTitle" text NOT NULL
);
CREATE TABLE insights."chartOption" (
    id integer NOT NULL,
    "chartId" integer NOT NULL,
    "propertyLabel" text NOT NULL,
    "defaultValue" text NOT NULL
);
CREATE SEQUENCE insights."chartOption_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE insights."chartOption_id_seq" OWNED BY insights."chartOption".id;
CREATE SEQUENCE insights.chart_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE insights.chart_id_seq OWNED BY insights.chart.id;
CREATE TABLE insights.date (
    date date NOT NULL,
    day text
);
CREATE TABLE insights.day (
    "dayName" text NOT NULL
);
CREATE TABLE insights.hour (
    hour integer NOT NULL
);
CREATE TABLE insights.insights (
    query text NOT NULL,
    "availableOptions" jsonb NOT NULL,
    switches jsonb NOT NULL,
    "isActive" boolean DEFAULT false,
    "defaultOptions" jsonb,
    title text NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    filters jsonb
);
COMMENT ON COLUMN insights.insights.filters IS 'same as availableOptions, will be used to render individual options like date range in insights.';
CREATE TABLE "order"."orderInventoryProduct" (
    id integer NOT NULL,
    "orderId" integer NOT NULL,
    "inventoryProductId" integer NOT NULL,
    "assemblyStationId" integer,
    "assemblyStatus" text NOT NULL,
    "inventoryProductOptionId" integer NOT NULL,
    "comboProductId" integer,
    "comboProductComponentId" integer,
    "customizableProductId" integer,
    "customizableProductOptionId" integer,
    quantity integer,
    price numeric,
    created_at timestamp with time zone DEFAULT now(),
    "customerInstruction" text,
    status text DEFAULT 'PENDING'::text,
    "packagingId" integer,
    "instructionCardTemplateId" integer,
    "isAssembled" boolean DEFAULT false NOT NULL,
    "labelTemplateId" integer
);
CREATE VIEW insights.inventory_product_transaction AS
 SELECT count("orderInventoryProduct"."orderId") AS count,
    "orderInventoryProduct"."inventoryProductId"
   FROM "order"."orderInventoryProduct"
  GROUP BY "orderInventoryProduct"."inventoryProductId";
CREATE TABLE "order"."orderMealKitProduct" (
    id integer NOT NULL,
    "orderId" integer NOT NULL,
    "simpleRecipeId" integer NOT NULL,
    "assemblyStationId" integer,
    "assemblyStatus" text NOT NULL,
    "simpleRecipeProductId" integer NOT NULL,
    "comboProductId" integer,
    "comboProductComponentId" integer,
    "customizableProductId" integer,
    "customizableProductOptionId" integer,
    "simpleRecipeProductOptionId" integer NOT NULL,
    price numeric,
    created_at timestamp with time zone DEFAULT now(),
    "customerInstruction" text,
    "labelTemplateId" integer,
    "packagingId" integer,
    "instructionCardTemplateId" integer,
    "isAssembled" boolean DEFAULT false NOT NULL,
    quantity integer DEFAULT 1 NOT NULL
);
CREATE VIEW insights.mealkit_product_transaction AS
 SELECT "orderMealKitProduct"."orderId",
    count("orderMealKitProduct".id) AS count
   FROM "order"."orderMealKitProduct"
  GROUP BY "orderMealKitProduct"."orderId";
CREATE TABLE insights.month (
    number integer NOT NULL,
    name text NOT NULL
);
CREATE TABLE "order"."orderReadyToEatProduct" (
    id integer NOT NULL,
    "orderId" integer NOT NULL,
    "simpleRecipeProductId" integer NOT NULL,
    "simpleRecipeId" integer NOT NULL,
    "simpleRecipeProductOptionId" integer NOT NULL,
    "comboProductId" integer,
    "comboProductComponentId" integer,
    "customizableProductId" integer,
    "customizableProductOptionId" integer,
    "assemblyStationId" integer,
    "assemblyStatus" text DEFAULT 'PENDING'::text NOT NULL,
    price numeric,
    created_at timestamp with time zone DEFAULT now(),
    "customerInstruction" text,
    status text DEFAULT 'PENDING'::text,
    "labelTemplateId" integer,
    "packagingId" integer,
    "instructionCardTemplateId" integer,
    "isAssembled" boolean DEFAULT false NOT NULL,
    quantity integer DEFAULT 1 NOT NULL
);
CREATE VIEW insights.ready_to_eat_product_transaction AS
 SELECT "orderReadyToEatProduct"."orderId",
    count("orderReadyToEatProduct".id) AS count
   FROM "order"."orderReadyToEatProduct"
  GROUP BY "orderReadyToEatProduct"."orderId";
CREATE VIEW insights.simple_recipe_sale_meal_kit AS
 SELECT "orderMealKitProduct"."simpleRecipeId",
    count("orderMealKitProduct"."simpleRecipeId") AS count
   FROM "order"."orderMealKitProduct"
  GROUP BY "orderMealKitProduct"."simpleRecipeId";
CREATE VIEW insights.simple_recipe_sale_ready_to_eat AS
 SELECT "orderReadyToEatProduct"."simpleRecipeId",
    count("orderReadyToEatProduct"."simpleRecipeId") AS count
   FROM "order"."orderReadyToEatProduct"
  GROUP BY "orderReadyToEatProduct"."simpleRecipeId";
CREATE TABLE inventory."bulkItemHistory" (
    id integer NOT NULL,
    "bulkItemId" integer NOT NULL,
    quantity numeric NOT NULL,
    comment jsonb,
    "purchaseOrderItemId" integer,
    "bulkWorkOrderId" integer,
    status text NOT NULL,
    unit text,
    "orderSachetId" integer,
    "sachetWorkOrderId" integer,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
CREATE SEQUENCE inventory."bulkHistory_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inventory."bulkHistory_id_seq" OWNED BY inventory."bulkItemHistory".id;
CREATE TABLE inventory."bulkItem" (
    id integer NOT NULL,
    "processingName" text NOT NULL,
    "supplierItemId" integer NOT NULL,
    labor jsonb,
    "shelfLife" jsonb,
    yield jsonb,
    "nutritionInfo" jsonb,
    sop jsonb,
    allergens jsonb,
    "parLevel" numeric,
    "maxLevel" numeric,
    "onHand" numeric DEFAULT 0 NOT NULL,
    "storageCondition" jsonb,
    "createdAt" timestamp with time zone DEFAULT now(),
    "updatedAt" timestamp with time zone DEFAULT now(),
    image text,
    "bulkDensity" numeric DEFAULT 1,
    equipments jsonb,
    unit text,
    committed numeric DEFAULT 0 NOT NULL,
    awaiting numeric DEFAULT 0 NOT NULL,
    consumed numeric DEFAULT 0 NOT NULL,
    "isAvailable" boolean DEFAULT true NOT NULL
);
CREATE SEQUENCE inventory."bulkInventoryItem_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inventory."bulkInventoryItem_id_seq" OWNED BY inventory."bulkItem".id;
CREATE TABLE inventory."bulkWorkOrder" (
    id integer NOT NULL,
    "inputBulkItemId" integer,
    "outputBulkItemId" integer,
    "outputQuantity" numeric DEFAULT 0 NOT NULL,
    "userId" integer,
    "scheduledOn" timestamp with time zone,
    "inputQuantity" numeric,
    status text DEFAULT 'UNPUBLISHED'::text,
    "stationId" integer,
    "inputQuantityUnit" text,
    "supplierItemId" integer,
    "isPublished" boolean DEFAULT false NOT NULL,
    name text,
    "outputYield" numeric
);
CREATE SEQUENCE inventory."bulkWorkOrder_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inventory."bulkWorkOrder_id_seq" OWNED BY inventory."bulkWorkOrder".id;
CREATE TABLE inventory."packagingHistory" (
    id integer NOT NULL,
    "packagingId" integer NOT NULL,
    quantity numeric NOT NULL,
    "purchaseOrderItemId" integer NOT NULL,
    status text DEFAULT 'PENDING'::text NOT NULL,
    unit text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
CREATE SEQUENCE inventory."packagingHistory_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inventory."packagingHistory_id_seq" OWNED BY inventory."packagingHistory".id;
CREATE TABLE inventory."purchaseOrderItem" (
    id integer NOT NULL,
    "bulkItemId" integer,
    "supplierItemId" integer,
    "orderQuantity" numeric DEFAULT 0,
    status text DEFAULT 'PENDING'::text NOT NULL,
    details jsonb,
    unit text,
    "supplierId" integer,
    price numeric,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    "packagingId" integer,
    "mandiPurchaseOrderItemId" integer,
    type text DEFAULT 'PACKAGING'::text NOT NULL
);
CREATE SEQUENCE inventory."purchaseOrder_bulkItemId_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inventory."purchaseOrder_bulkItemId_seq" OWNED BY inventory."purchaseOrderItem"."bulkItemId";
CREATE SEQUENCE inventory."purchaseOrder_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inventory."purchaseOrder_id_seq" OWNED BY inventory."purchaseOrderItem".id;
CREATE TABLE inventory."sachetItemHistory" (
    id integer NOT NULL,
    "sachetItemId" integer NOT NULL,
    "sachetWorkOrderId" integer,
    quantity numeric NOT NULL,
    comment jsonb,
    status text NOT NULL,
    "orderSachetId" integer,
    unit text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
CREATE SEQUENCE inventory."sachetHistory_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inventory."sachetHistory_id_seq" OWNED BY inventory."sachetItemHistory".id;
CREATE TABLE inventory."sachetItem" (
    id integer NOT NULL,
    "unitSize" numeric NOT NULL,
    "parLevel" numeric,
    "maxLevel" numeric,
    "onHand" numeric DEFAULT 0 NOT NULL,
    "isAvailable" boolean DEFAULT true NOT NULL,
    "bulkItemId" integer NOT NULL,
    unit text NOT NULL,
    consumed numeric DEFAULT 0 NOT NULL,
    awaiting numeric DEFAULT 0 NOT NULL,
    committed numeric DEFAULT 0 NOT NULL
);
CREATE SEQUENCE inventory."sachetItem2_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inventory."sachetItem2_id_seq" OWNED BY inventory."sachetItem".id;
CREATE TABLE inventory."sachetWorkOrder" (
    id integer NOT NULL,
    "inputBulkItemId" integer,
    "outputSachetItemId" integer,
    "outputQuantity" numeric DEFAULT 0 NOT NULL,
    "inputQuantity" numeric,
    "packagingId" integer,
    label jsonb,
    "stationId" integer,
    "userId" integer,
    "scheduledOn" timestamp with time zone,
    status text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    name text,
    "supplierItemId" integer,
    "isPublished" boolean DEFAULT false NOT NULL
);
CREATE SEQUENCE inventory."sachetWorkOrder_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inventory."sachetWorkOrder_id_seq" OWNED BY inventory."sachetWorkOrder".id;
CREATE TABLE inventory.supplier (
    id integer NOT NULL,
    name text NOT NULL,
    "contactPerson" jsonb,
    address jsonb,
    "shippingTerms" jsonb,
    "paymentTerms" jsonb,
    available boolean DEFAULT true NOT NULL,
    logo text,
    "importId" integer,
    "mandiSupplierId" integer
);
CREATE TABLE inventory."supplierItem" (
    id integer NOT NULL,
    name text,
    "unitSize" integer,
    prices jsonb,
    "supplierId" integer,
    unit text,
    "leadTime" jsonb,
    certificates jsonb,
    "bulkItemAsShippedId" integer,
    sku text,
    "importId" integer
);
CREATE SEQUENCE inventory."supplierItem_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inventory."supplierItem_id_seq" OWNED BY inventory."supplierItem".id;
CREATE SEQUENCE inventory.supplier_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inventory.supplier_id_seq OWNED BY inventory.supplier.id;
CREATE TABLE inventory."unitConversionByBulkItem" (
    "bulkItemId" integer NOT NULL,
    "unitConversionId" integer NOT NULL,
    "customConversionFactor" numeric NOT NULL,
    id integer NOT NULL
);
CREATE SEQUENCE inventory."unitConversionByBulkItem_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inventory."unitConversionByBulkItem_id_seq" OWNED BY inventory."unitConversionByBulkItem".id;
CREATE TABLE master."accompanimentType" (
    id integer NOT NULL,
    name text NOT NULL
);
CREATE SEQUENCE master."accompanimentType_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE master."accompanimentType_id_seq" OWNED BY master."accompanimentType".id;
CREATE TABLE master."allergenName" (
    id integer NOT NULL,
    name text NOT NULL,
    description text
);
CREATE SEQUENCE master.allergen_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE master.allergen_id_seq OWNED BY master."allergenName".id;
CREATE TABLE master."cuisineName" (
    name text NOT NULL,
    id integer NOT NULL
);
CREATE SEQUENCE master."cuisineName_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE master."cuisineName_id_seq" OWNED BY master."cuisineName".id;
CREATE TABLE master."processingName" (
    id integer NOT NULL,
    name text NOT NULL,
    description text
);
CREATE SEQUENCE master.processing_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE master.processing_id_seq OWNED BY master."processingName".id;
CREATE TABLE master."productCategory" (
    name text NOT NULL,
    "imageUrl" text,
    "iconUrl" text,
    "metaDetails" jsonb
);
CREATE TABLE master.unit (
    id integer NOT NULL,
    name text NOT NULL
);
CREATE TABLE master."unitConversion" (
    id integer NOT NULL,
    "inputUnitName" text NOT NULL,
    "outputUnitName" text NOT NULL,
    "defaultConversionFactor" jsonb
);
CREATE SEQUENCE master."unitConversion_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE master."unitConversion_id_seq" OWNED BY master."unitConversion".id;
CREATE SEQUENCE master.unit_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE master.unit_id_seq OWNED BY master.unit.id;
CREATE TABLE notifications."displayNotification" (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    "typeId" uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    content jsonb NOT NULL,
    seen boolean DEFAULT false NOT NULL
);
CREATE TABLE notifications."emailConfig" (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    "typeId" uuid NOT NULL,
    template jsonb,
    email text NOT NULL,
    "isActive" boolean DEFAULT true NOT NULL
);
CREATE TABLE notifications."printConfig" (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    "printerPrintNodeId" integer NOT NULL,
    "typeId" uuid NOT NULL,
    "isActive" boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    template jsonb NOT NULL
);
CREATE TABLE notifications."smsConfig" (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    "typeId" uuid NOT NULL,
    template jsonb,
    "phoneNo" text NOT NULL,
    "isActive" boolean DEFAULT true NOT NULL
);
CREATE TABLE notifications.type (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    name text NOT NULL,
    description text,
    app text NOT NULL,
    "table" text NOT NULL,
    schema text NOT NULL,
    op text NOT NULL,
    fields jsonb NOT NULL,
    "isActive" boolean DEFAULT false NOT NULL,
    template jsonb NOT NULL,
    "isLocal" boolean DEFAULT true NOT NULL,
    "isGlobal" boolean DEFAULT true NOT NULL,
    "playAudio" boolean DEFAULT false,
    "audioUrl" text,
    "webhookEnv" text DEFAULT 'WEBHOOK_DEFAULT_NOTIFICATION_HANDLER'::text,
    "emailFrom" jsonb DEFAULT '{"name": "", "email": ""}'::jsonb
);
CREATE TABLE "onDemand".brand_collection (
    "brandId" integer NOT NULL,
    "collectionId" integer NOT NULL,
    "isActive" boolean DEFAULT true NOT NULL
);
CREATE TABLE "onDemand".category (
    name text NOT NULL,
    id integer NOT NULL
);
CREATE SEQUENCE "onDemand".category_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "onDemand".category_id_seq OWNED BY "onDemand".category.id;
CREATE VIEW "onDemand"."collectionDetails" AS
 SELECT collection.id,
    collection.name,
    collection."startTime",
    collection."endTime",
    collection.rrule,
    "onDemand"."numberOfCategories"(collection.id) AS "categoriesCount",
    "onDemand"."numberOfProducts"(collection.id) AS "productsCount"
   FROM "onDemand".collection;
CREATE SEQUENCE "onDemand".collection_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "onDemand".collection_id_seq OWNED BY "onDemand".collection.id;
CREATE TABLE "onDemand"."collection_productCategory" (
    id integer NOT NULL,
    "collectionId" integer NOT NULL,
    "productCategoryName" text NOT NULL
);
CREATE SEQUENCE "onDemand"."collection_productCategory_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "onDemand"."collection_productCategory_id_seq" OWNED BY "onDemand"."collection_productCategory".id;
CREATE SEQUENCE "onDemand"."collection_productCategory_product_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "onDemand"."collection_productCategory_product_id_seq" OWNED BY "onDemand"."collection_productCategory_product".id;
CREATE TABLE "onDemand"."menuData" (
    name text NOT NULL,
    "comboProducts" jsonb,
    "customizableProducts" jsonb,
    "simpleRecipeProducts" jsonb,
    "inventoryProducts" jsonb
);
CREATE SEQUENCE "onDemand".menu_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "onDemand".menu_id_seq OWNED BY "onDemand".menu.id;
CREATE TABLE "onDemand".modifier (
    id integer NOT NULL,
    data jsonb NOT NULL,
    name text NOT NULL
);
CREATE SEQUENCE "onDemand".modifier_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "onDemand".modifier_id_seq OWNED BY "onDemand".modifier.id;
CREATE SEQUENCE "onlineStore"."menuCollection_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "onlineStore"."menuCollection_id_seq" OWNED BY "onlineStore"."menuCollection".id;
CREATE TABLE "onlineStore"."productSku" (
    sku uuid NOT NULL
);
CREATE SEQUENCE "onlineStore"."rmkCollection_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "onlineStore"."rmkCollection_id_seq" OWNED BY "onlineStore"."rmkCollection".id;
CREATE TABLE "order"."assemblyEnum" (
    value text NOT NULL,
    description text NOT NULL
);
CREATE SEQUENCE "order"."orderInventoryProduct_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "order"."orderInventoryProduct_id_seq" OWNED BY "order"."orderInventoryProduct".id;
CREATE SEQUENCE "order"."orderItem_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "order"."orderItem_id_seq" OWNED BY "order"."orderMealKitProduct".id;
CREATE SEQUENCE "order"."orderMealKitProductDetail_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "order"."orderMealKitProductDetail_id_seq" OWNED BY "order"."orderSachet".id;
CREATE TABLE "order"."orderPaymentStatusEnum" (
    value text NOT NULL,
    description text NOT NULL
);
CREATE SEQUENCE "order"."orderReadyToEatProduct_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "order"."orderReadyToEatProduct_id_seq" OWNED BY "order"."orderReadyToEatProduct".id;
CREATE TABLE "order"."orderSachetStatusEnum" (
    value text NOT NULL,
    description text NOT NULL
);
CREATE TABLE "order"."orderStatusEnum" (
    value text NOT NULL,
    description text NOT NULL,
    index integer
);
CREATE SEQUENCE "order".order_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "order".order_id_seq OWNED BY "order"."order".id;
CREATE TABLE packaging.packaging (
    id integer NOT NULL,
    name text NOT NULL,
    "packagingSku" text,
    "supplierId" integer,
    "unitPrice" numeric,
    "parLevel" integer,
    "maxLevel" integer,
    "onHand" integer DEFAULT 0 NOT NULL,
    "unitQuantity" numeric,
    "caseQuantity" numeric,
    "minOrderValue" numeric,
    "leadTime" jsonb,
    "isAvailable" boolean DEFAULT false NOT NULL,
    type text,
    awaiting numeric DEFAULT 0 NOT NULL,
    committed numeric DEFAULT 0 NOT NULL,
    consumed numeric DEFAULT 0 NOT NULL,
    assets jsonb,
    "mandiPackagingId" integer,
    length numeric,
    width numeric,
    height numeric,
    gusset numeric,
    thickness numeric,
    "LWHUnit" text DEFAULT 'mm'::text,
    "loadCapacity" numeric,
    "loadVolume" numeric,
    "packagingSpecificationsId" integer NOT NULL,
    weight numeric
);
CREATE TABLE packaging."packagingSpecifications" (
    id integer NOT NULL,
    "innerWaterResistant" boolean,
    "outerWaterResistant" boolean,
    "innerGreaseResistant" boolean,
    "outerGreaseResistant" boolean,
    microwaveable boolean,
    "maxTemperatureInFahrenheit" boolean,
    recyclable boolean,
    compostable boolean,
    recycled boolean,
    "fdaCompliant" boolean,
    compressibility boolean,
    opacity text,
    "mandiPackagingId" integer,
    "packagingMaterial" text
);
CREATE SEQUENCE packaging."packagingSpecifications_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE packaging."packagingSpecifications_id_seq" OWNED BY packaging."packagingSpecifications".id;
CREATE SEQUENCE packaging.packaging_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE packaging.packaging_id_seq OWNED BY packaging.packaging.id;
CREATE TABLE products."comboProductComponent" (
    id integer NOT NULL,
    "simpleRecipeProductId" integer,
    "inventoryProductId" integer,
    "customizableProductId" integer,
    label text NOT NULL,
    "comboProductId" integer NOT NULL,
    discount numeric
);
CREATE SEQUENCE products."comboProductComponents_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE products."comboProductComponents_id_seq" OWNED BY products."comboProductComponent".id;
CREATE SEQUENCE products."customizableProductOptions_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE products."customizableProductOptions_id_seq" OWNED BY products."customizableProductOption".id;
CREATE SEQUENCE products."inventoryProductOption_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE products."inventoryProductOption_id_seq" OWNED BY products."inventoryProductOption".id;
CREATE SEQUENCE products."inventoryProduct_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE products."inventoryProduct_id_seq" OWNED BY products."inventoryProduct".id;
CREATE SEQUENCE products."recipeProduct_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE products."recipeProduct_id_seq" OWNED BY products."comboProduct".id;
CREATE SEQUENCE products."simpleRecipeProductVariant_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE products."simpleRecipeProductVariant_id_seq" OWNED BY products."simpleRecipeProductOption".id;
CREATE SEQUENCE products."simpleRecipeProduct_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE products."simpleRecipeProduct_id_seq" OWNED BY products."simpleRecipeProduct".id;
CREATE SEQUENCE products."smartProduct_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE products."smartProduct_id_seq" OWNED BY products."customizableProduct".id;
CREATE SEQUENCE rules.conditions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE rules.conditions_id_seq OWNED BY rules.conditions.id;
CREATE SEQUENCE rules.fact_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE rules.fact_id_seq OWNED BY rules.facts.id;
CREATE TABLE safety."safetyCheck" (
    id integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    "isVisibleOnStore" boolean NOT NULL
);
CREATE TABLE safety."safetyCheckPerUser" (
    id integer NOT NULL,
    "SafetyCheckId" integer NOT NULL,
    "userId" integer NOT NULL,
    "usesMask" boolean NOT NULL,
    "usesSanitizer" boolean NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    temperature numeric
);
CREATE SEQUENCE safety."safetyCheckByUser_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE safety."safetyCheckByUser_id_seq" OWNED BY safety."safetyCheckPerUser".id;
CREATE SEQUENCE safety."safetyCheck_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE safety."safetyCheck_id_seq" OWNED BY safety."safetyCheck".id;
CREATE TABLE settings.app (
    id integer NOT NULL,
    title text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE settings."appPermission" (
    id integer NOT NULL,
    "appId" integer NOT NULL,
    route text NOT NULL,
    title text NOT NULL,
    "fallbackMessage" text
);
CREATE SEQUENCE settings."appPermission_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE settings."appPermission_id_seq" OWNED BY settings."appPermission".id;
CREATE TABLE settings."appSettings" (
    id integer NOT NULL,
    app text NOT NULL,
    type text NOT NULL,
    identifier text NOT NULL,
    value jsonb NOT NULL
);
CREATE SEQUENCE settings."appSettings_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE settings."appSettings_id_seq" OWNED BY settings."appSettings".id;
CREATE SEQUENCE settings.apps_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE settings.apps_id_seq OWNED BY settings.app.id;
CREATE TABLE settings."operationConfig" (
    id integer NOT NULL,
    "stationId" integer,
    "labelTemplateId" integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE SEQUENCE settings."operationConfig_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE settings."operationConfig_id_seq" OWNED BY settings."operationConfig".id;
CREATE TABLE settings.role (
    id integer NOT NULL,
    title text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE settings.role_app (
    id integer NOT NULL,
    "roleId" integer NOT NULL,
    "appId" integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE settings."role_appPermission" (
    "appPermissionId" integer NOT NULL,
    "role_appId" integer NOT NULL,
    value boolean NOT NULL
);
CREATE SEQUENCE settings.role_app_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE settings.role_app_id_seq OWNED BY settings.role_app.id;
CREATE SEQUENCE settings.roles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE settings.roles_id_seq OWNED BY settings.role.id;
CREATE TABLE settings.station (
    id integer NOT NULL,
    name text NOT NULL,
    "defaultLabelPrinterId" integer,
    "defaultKotPrinterId" integer,
    "defaultScaleId" integer
);
CREATE SEQUENCE settings.station_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE settings.station_id_seq OWNED BY settings.station.id;
CREATE TABLE settings.station_kot_printer (
    "stationId" integer NOT NULL,
    "printNodeId" integer NOT NULL,
    active boolean DEFAULT true NOT NULL
);
CREATE TABLE settings.station_label_printer (
    "stationId" integer NOT NULL,
    "printNodeId" integer NOT NULL,
    active boolean DEFAULT true NOT NULL
);
CREATE TABLE settings.station_user (
    "userKeycloakId" text NOT NULL,
    "stationId" integer NOT NULL,
    active boolean DEFAULT true NOT NULL
);
CREATE TABLE settings."user" (
    id integer NOT NULL,
    "firstName" text,
    "lastName" text,
    email text,
    "tempPassword" text,
    "phoneNo" text,
    "keycloakId" text
);
CREATE SEQUENCE settings.user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE settings.user_id_seq OWNED BY settings."user".id;
CREATE TABLE settings.user_role (
    id integer NOT NULL,
    "userId" text NOT NULL,
    "roleId" integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE SEQUENCE settings.user_role_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE settings.user_role_id_seq OWNED BY settings.user_role.id;
CREATE SEQUENCE "simpleRecipe"."recipeServing_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "simpleRecipe"."recipeServing_id_seq" OWNED BY "simpleRecipe"."simpleRecipeYield".id;
CREATE TABLE "simpleRecipe"."simpleRecipeYield_ingredientSachet" (
    "recipeYieldId" integer NOT NULL,
    "ingredientSachetId" integer NOT NULL,
    "isVisible" boolean DEFAULT true NOT NULL,
    "slipName" text,
    "isSachetValid" boolean
);
CREATE SEQUENCE "simpleRecipe"."simpleRecipe_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "simpleRecipe"."simpleRecipe_id_seq" OWNED BY "simpleRecipe"."simpleRecipe".id;
CREATE TABLE subscription."brand_subscriptionTitle" (
    "brandId" integer NOT NULL,
    "subscriptionTitleId" integer NOT NULL,
    "isActive" boolean DEFAULT true NOT NULL
);
CREATE TABLE subscription.subscription (
    id integer NOT NULL,
    "subscriptionItemCountId" integer NOT NULL,
    rrule text NOT NULL,
    "metaDetails" jsonb,
    "cutOffTime" time without time zone,
    "leadTime" jsonb,
    "startTime" jsonb DEFAULT '{"unit": "days", "value": 28}'::jsonb,
    "startDate" date,
    "endDate" date
);
CREATE SEQUENCE subscription."subscriptionItemCount_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE subscription."subscriptionItemCount_id_seq" OWNED BY subscription."subscriptionItemCount".id;
CREATE TABLE subscription."subscriptionOccurence_customer" (
    "subscriptionOccurenceId" integer NOT NULL,
    "keycloakId" text NOT NULL,
    "orderCartId" integer,
    "isSkipped" boolean DEFAULT false NOT NULL,
    "isAuto" boolean DEFAULT true NOT NULL
);
CREATE SEQUENCE subscription."subscriptionOccurence_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE subscription."subscriptionOccurence_id_seq" OWNED BY subscription."subscriptionOccurence".id;
CREATE SEQUENCE subscription."subscriptionOccurence_product_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE subscription."subscriptionOccurence_product_id_seq" OWNED BY subscription."subscriptionOccurence_product".id;
CREATE SEQUENCE subscription."subscriptionServing_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE subscription."subscriptionServing_id_seq" OWNED BY subscription."subscriptionServing".id;
CREATE SEQUENCE subscription."subscriptionTitle_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE subscription."subscriptionTitle_id_seq" OWNED BY subscription."subscriptionTitle".id;
CREATE SEQUENCE subscription.subscription_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE subscription.subscription_id_seq OWNED BY subscription.subscription.id;
CREATE TABLE subscription.subscription_zipcode (
    "subscriptionId" integer NOT NULL,
    zipcode text NOT NULL,
    "deliveryPrice" numeric DEFAULT 0 NOT NULL,
    "isActive" boolean DEFAULT true
);
ALTER TABLE ONLY brands.brand ALTER COLUMN id SET DEFAULT nextval('brands.shop_id_seq'::regclass);
ALTER TABLE ONLY brands."storeSetting" ALTER COLUMN id SET DEFAULT nextval('brands."storeSetting_id_seq"'::regclass);
ALTER TABLE ONLY brands."subscriptionStoreSetting" ALTER COLUMN id SET DEFAULT nextval('brands."subscriptionStoreSetting_id_seq"'::regclass);
ALTER TABLE ONLY content.faqs ALTER COLUMN id SET DEFAULT nextval('content.faqs_id_seq'::regclass);
ALTER TABLE ONLY content."informationBlock" ALTER COLUMN id SET DEFAULT nextval('content."informationBlock_id_seq"'::regclass);
ALTER TABLE ONLY content."informationGrid" ALTER COLUMN id SET DEFAULT nextval('content."informationGrid_id_seq"'::regclass);
ALTER TABLE ONLY crm.brand_customer ALTER COLUMN id SET DEFAULT nextval('crm."brandCustomer_id_seq"'::regclass);
ALTER TABLE ONLY crm.campaign ALTER COLUMN id SET DEFAULT nextval('crm.campaign_id_seq'::regclass);
ALTER TABLE ONLY crm."campaignType" ALTER COLUMN id SET DEFAULT nextval('crm."campaignType_id_seq"'::regclass);
ALTER TABLE ONLY crm.coupon ALTER COLUMN id SET DEFAULT nextval('crm.coupon_id_seq'::regclass);
ALTER TABLE ONLY crm.customer ALTER COLUMN id SET DEFAULT nextval('crm.customer_id_seq'::regclass);
ALTER TABLE ONLY crm."customerReferral" ALTER COLUMN id SET DEFAULT nextval('crm."customerReferral_id_seq"'::regclass);
ALTER TABLE ONLY crm.customer_voucher ALTER COLUMN id SET DEFAULT nextval('crm.customer_voucher_id_seq'::regclass);
ALTER TABLE ONLY crm.fact ALTER COLUMN id SET DEFAULT nextval('crm.fact_id_seq'::regclass);
ALTER TABLE ONLY crm."loyaltyPoint" ALTER COLUMN id SET DEFAULT nextval('crm."loyaltyPoint_id_seq"'::regclass);
ALTER TABLE ONLY crm."loyaltyPointTransaction" ALTER COLUMN id SET DEFAULT nextval('crm."loyaltyPointTransaction_id_seq"'::regclass);
ALTER TABLE ONLY crm."orderCart" ALTER COLUMN id SET DEFAULT nextval('crm."orderCart_id_seq"'::regclass);
ALTER TABLE ONLY crm."orderCart_rewards" ALTER COLUMN id SET DEFAULT nextval('crm."orderCart_rewards_id_seq"'::regclass);
ALTER TABLE ONLY crm.reward ALTER COLUMN id SET DEFAULT nextval('crm.reward_id_seq'::regclass);
ALTER TABLE ONLY crm."rewardHistory" ALTER COLUMN id SET DEFAULT nextval('crm."rewardHistory_id_seq"'::regclass);
ALTER TABLE ONLY crm."rewardType" ALTER COLUMN id SET DEFAULT nextval('crm."rewardType_id_seq"'::regclass);
ALTER TABLE ONLY crm.session ALTER COLUMN id SET DEFAULT nextval('crm.session_id_seq'::regclass);
ALTER TABLE ONLY crm.wallet ALTER COLUMN id SET DEFAULT nextval('crm.wallet_id_seq'::regclass);
ALTER TABLE ONLY crm."walletTransaction" ALTER COLUMN id SET DEFAULT nextval('crm."walletTransaction_id_seq"'::regclass);
ALTER TABLE ONLY "deviceHub".config ALTER COLUMN id SET DEFAULT nextval('"deviceHub".config_id_seq'::regclass);
ALTER TABLE ONLY "deviceHub"."labelTemplate" ALTER COLUMN id SET DEFAULT nextval('"deviceHub"."labelTemplate_id_seq"'::regclass);
ALTER TABLE ONLY "deviceHub".scale ALTER COLUMN id SET DEFAULT nextval('"deviceHub".scale_id_seq'::regclass);
ALTER TABLE ONLY fulfilment.charge ALTER COLUMN id SET DEFAULT nextval('fulfilment.charge_id_seq'::regclass);
ALTER TABLE ONLY fulfilment."deliveryService" ALTER COLUMN id SET DEFAULT nextval('fulfilment."deliveryService_id_seq"'::regclass);
ALTER TABLE ONLY fulfilment."mileRange" ALTER COLUMN id SET DEFAULT nextval('fulfilment."mileRange_id_seq"'::regclass);
ALTER TABLE ONLY fulfilment.recurrence ALTER COLUMN id SET DEFAULT nextval('fulfilment.recurrence_id_seq'::regclass);
ALTER TABLE ONLY fulfilment."timeSlot" ALTER COLUMN id SET DEFAULT nextval('fulfilment."timeSlot_id_seq"'::regclass);
ALTER TABLE ONLY imports.import ALTER COLUMN id SET DEFAULT nextval('imports.imports_id_seq'::regclass);
ALTER TABLE ONLY imports."importHistory" ALTER COLUMN id SET DEFAULT nextval('imports."importHistory_id_seq"'::regclass);
ALTER TABLE ONLY ingredient.ingredient ALTER COLUMN id SET DEFAULT nextval('ingredient.ingredient_id_seq'::regclass);
ALTER TABLE ONLY ingredient."ingredientProcessing" ALTER COLUMN id SET DEFAULT nextval('ingredient."ingredientProcessing_id_seq"'::regclass);
ALTER TABLE ONLY ingredient."ingredientSachet" ALTER COLUMN id SET DEFAULT nextval('ingredient."ingredientSachet_id_seq"'::regclass);
ALTER TABLE ONLY ingredient."modeOfFulfillment" ALTER COLUMN id SET DEFAULT nextval('ingredient."modeOfFulfillment_id_seq"'::regclass);
ALTER TABLE ONLY insights.chart ALTER COLUMN id SET DEFAULT nextval('insights.chart_id_seq'::regclass);
ALTER TABLE ONLY insights."chartOption" ALTER COLUMN id SET DEFAULT nextval('insights."chartOption_id_seq"'::regclass);
ALTER TABLE ONLY inventory."bulkItem" ALTER COLUMN id SET DEFAULT nextval('inventory."bulkInventoryItem_id_seq"'::regclass);
ALTER TABLE ONLY inventory."bulkItemHistory" ALTER COLUMN id SET DEFAULT nextval('inventory."bulkHistory_id_seq"'::regclass);
ALTER TABLE ONLY inventory."bulkWorkOrder" ALTER COLUMN id SET DEFAULT nextval('inventory."bulkWorkOrder_id_seq"'::regclass);
ALTER TABLE ONLY inventory."packagingHistory" ALTER COLUMN id SET DEFAULT nextval('inventory."packagingHistory_id_seq"'::regclass);
ALTER TABLE ONLY inventory."purchaseOrderItem" ALTER COLUMN id SET DEFAULT nextval('inventory."purchaseOrder_id_seq"'::regclass);
ALTER TABLE ONLY inventory."sachetItem" ALTER COLUMN id SET DEFAULT nextval('inventory."sachetItem2_id_seq"'::regclass);
ALTER TABLE ONLY inventory."sachetItemHistory" ALTER COLUMN id SET DEFAULT nextval('inventory."sachetHistory_id_seq"'::regclass);
ALTER TABLE ONLY inventory."sachetWorkOrder" ALTER COLUMN id SET DEFAULT nextval('inventory."sachetWorkOrder_id_seq"'::regclass);
ALTER TABLE ONLY inventory.supplier ALTER COLUMN id SET DEFAULT nextval('inventory.supplier_id_seq'::regclass);
ALTER TABLE ONLY inventory."supplierItem" ALTER COLUMN id SET DEFAULT nextval('inventory."supplierItem_id_seq"'::regclass);
ALTER TABLE ONLY inventory."unitConversionByBulkItem" ALTER COLUMN id SET DEFAULT nextval('inventory."unitConversionByBulkItem_id_seq"'::regclass);
ALTER TABLE ONLY master."accompanimentType" ALTER COLUMN id SET DEFAULT nextval('master."accompanimentType_id_seq"'::regclass);
ALTER TABLE ONLY master."allergenName" ALTER COLUMN id SET DEFAULT nextval('master.allergen_id_seq'::regclass);
ALTER TABLE ONLY master."cuisineName" ALTER COLUMN id SET DEFAULT nextval('master."cuisineName_id_seq"'::regclass);
ALTER TABLE ONLY master."processingName" ALTER COLUMN id SET DEFAULT nextval('master.processing_id_seq'::regclass);
ALTER TABLE ONLY master.unit ALTER COLUMN id SET DEFAULT nextval('master.unit_id_seq'::regclass);
ALTER TABLE ONLY master."unitConversion" ALTER COLUMN id SET DEFAULT nextval('master."unitConversion_id_seq"'::regclass);
ALTER TABLE ONLY "onDemand".category ALTER COLUMN id SET DEFAULT nextval('"onDemand".category_id_seq'::regclass);
ALTER TABLE ONLY "onDemand".collection ALTER COLUMN id SET DEFAULT nextval('"onDemand".collection_id_seq'::regclass);
ALTER TABLE ONLY "onDemand"."collection_productCategory" ALTER COLUMN id SET DEFAULT nextval('"onDemand"."collection_productCategory_id_seq"'::regclass);
ALTER TABLE ONLY "onDemand"."collection_productCategory_product" ALTER COLUMN id SET DEFAULT nextval('"onDemand"."collection_productCategory_product_id_seq"'::regclass);
ALTER TABLE ONLY "onDemand".menu ALTER COLUMN id SET DEFAULT nextval('"onDemand".menu_id_seq'::regclass);
ALTER TABLE ONLY "onDemand".modifier ALTER COLUMN id SET DEFAULT nextval('"onDemand".modifier_id_seq'::regclass);
ALTER TABLE ONLY "onlineStore"."menuCollection" ALTER COLUMN id SET DEFAULT nextval('"onlineStore"."menuCollection_id_seq"'::regclass);
ALTER TABLE ONLY "onlineStore"."rmkCollection" ALTER COLUMN id SET DEFAULT nextval('"onlineStore"."rmkCollection_id_seq"'::regclass);
ALTER TABLE ONLY "order"."order" ALTER COLUMN id SET DEFAULT nextval('"order".order_id_seq'::regclass);
ALTER TABLE ONLY "order"."orderInventoryProduct" ALTER COLUMN id SET DEFAULT nextval('"order"."orderInventoryProduct_id_seq"'::regclass);
ALTER TABLE ONLY "order"."orderMealKitProduct" ALTER COLUMN id SET DEFAULT nextval('"order"."orderItem_id_seq"'::regclass);
ALTER TABLE ONLY "order"."orderReadyToEatProduct" ALTER COLUMN id SET DEFAULT nextval('"order"."orderReadyToEatProduct_id_seq"'::regclass);
ALTER TABLE ONLY "order"."orderSachet" ALTER COLUMN id SET DEFAULT nextval('"order"."orderMealKitProductDetail_id_seq"'::regclass);
ALTER TABLE ONLY packaging.packaging ALTER COLUMN id SET DEFAULT nextval('packaging.packaging_id_seq'::regclass);
ALTER TABLE ONLY packaging."packagingSpecifications" ALTER COLUMN id SET DEFAULT nextval('packaging."packagingSpecifications_id_seq"'::regclass);
ALTER TABLE ONLY products."comboProduct" ALTER COLUMN id SET DEFAULT nextval('products."recipeProduct_id_seq"'::regclass);
ALTER TABLE ONLY products."comboProductComponent" ALTER COLUMN id SET DEFAULT nextval('products."comboProductComponents_id_seq"'::regclass);
ALTER TABLE ONLY products."customizableProduct" ALTER COLUMN id SET DEFAULT nextval('products."smartProduct_id_seq"'::regclass);
ALTER TABLE ONLY products."customizableProductOption" ALTER COLUMN id SET DEFAULT nextval('products."customizableProductOptions_id_seq"'::regclass);
ALTER TABLE ONLY products."inventoryProduct" ALTER COLUMN id SET DEFAULT nextval('products."inventoryProduct_id_seq"'::regclass);
ALTER TABLE ONLY products."inventoryProductOption" ALTER COLUMN id SET DEFAULT nextval('products."inventoryProductOption_id_seq"'::regclass);
ALTER TABLE ONLY products."simpleRecipeProduct" ALTER COLUMN id SET DEFAULT nextval('products."simpleRecipeProduct_id_seq"'::regclass);
ALTER TABLE ONLY products."simpleRecipeProductOption" ALTER COLUMN id SET DEFAULT nextval('products."simpleRecipeProductVariant_id_seq"'::regclass);
ALTER TABLE ONLY rules.conditions ALTER COLUMN id SET DEFAULT nextval('rules.conditions_id_seq'::regclass);
ALTER TABLE ONLY rules.facts ALTER COLUMN id SET DEFAULT nextval('rules.fact_id_seq'::regclass);
ALTER TABLE ONLY safety."safetyCheck" ALTER COLUMN id SET DEFAULT nextval('safety."safetyCheck_id_seq"'::regclass);
ALTER TABLE ONLY safety."safetyCheckPerUser" ALTER COLUMN id SET DEFAULT nextval('safety."safetyCheckByUser_id_seq"'::regclass);
ALTER TABLE ONLY settings.app ALTER COLUMN id SET DEFAULT nextval('settings.apps_id_seq'::regclass);
ALTER TABLE ONLY settings."appPermission" ALTER COLUMN id SET DEFAULT nextval('settings."appPermission_id_seq"'::regclass);
ALTER TABLE ONLY settings."appSettings" ALTER COLUMN id SET DEFAULT nextval('settings."appSettings_id_seq"'::regclass);
ALTER TABLE ONLY settings."operationConfig" ALTER COLUMN id SET DEFAULT nextval('settings."operationConfig_id_seq"'::regclass);
ALTER TABLE ONLY settings.role ALTER COLUMN id SET DEFAULT nextval('settings.roles_id_seq'::regclass);
ALTER TABLE ONLY settings.role_app ALTER COLUMN id SET DEFAULT nextval('settings.role_app_id_seq'::regclass);
ALTER TABLE ONLY settings.station ALTER COLUMN id SET DEFAULT nextval('settings.station_id_seq'::regclass);
ALTER TABLE ONLY settings."user" ALTER COLUMN id SET DEFAULT nextval('settings.user_id_seq'::regclass);
ALTER TABLE ONLY settings.user_role ALTER COLUMN id SET DEFAULT nextval('settings.user_role_id_seq'::regclass);
ALTER TABLE ONLY "simpleRecipe"."simpleRecipe" ALTER COLUMN id SET DEFAULT nextval('"simpleRecipe"."simpleRecipe_id_seq"'::regclass);
ALTER TABLE ONLY "simpleRecipe"."simpleRecipeYield" ALTER COLUMN id SET DEFAULT nextval('"simpleRecipe"."recipeServing_id_seq"'::regclass);
ALTER TABLE ONLY subscription.subscription ALTER COLUMN id SET DEFAULT nextval('subscription.subscription_id_seq'::regclass);
ALTER TABLE ONLY subscription."subscriptionItemCount" ALTER COLUMN id SET DEFAULT nextval('subscription."subscriptionItemCount_id_seq"'::regclass);
ALTER TABLE ONLY subscription."subscriptionOccurence" ALTER COLUMN id SET DEFAULT nextval('subscription."subscriptionOccurence_id_seq"'::regclass);
ALTER TABLE ONLY subscription."subscriptionOccurence_product" ALTER COLUMN id SET DEFAULT nextval('subscription."subscriptionOccurence_product_id_seq"'::regclass);
ALTER TABLE ONLY subscription."subscriptionServing" ALTER COLUMN id SET DEFAULT nextval('subscription."subscriptionServing_id_seq"'::regclass);
ALTER TABLE ONLY subscription."subscriptionTitle" ALTER COLUMN id SET DEFAULT nextval('subscription."subscriptionTitle_id_seq"'::regclass);
ALTER TABLE ONLY brands.brand
    ADD CONSTRAINT brand_pkey PRIMARY KEY (id);
ALTER TABLE ONLY brands."brand_subscriptionStoreSetting"
    ADD CONSTRAINT "brand_subscriptionStoreSetting_pkey" PRIMARY KEY ("brandId", "subscriptionStoreSettingId");
ALTER TABLE ONLY brands.brand
    ADD CONSTRAINT shop_domain_key UNIQUE (domain);
ALTER TABLE ONLY brands.brand
    ADD CONSTRAINT shop_id_key UNIQUE (id);
ALTER TABLE ONLY brands."brand_storeSetting"
    ADD CONSTRAINT "shop_storeSetting_pkey" PRIMARY KEY ("brandId", "storeSettingId");
ALTER TABLE ONLY brands."storeSetting"
    ADD CONSTRAINT "storeSetting_identifier_key" UNIQUE (identifier);
ALTER TABLE ONLY brands."storeSetting"
    ADD CONSTRAINT "storeSetting_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY brands."subscriptionStoreSetting"
    ADD CONSTRAINT "subscriptionStoreSetting_identifier_key" UNIQUE (identifier);
ALTER TABLE ONLY brands."subscriptionStoreSetting"
    ADD CONSTRAINT "subscriptionStoreSetting_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY content.faqs
    ADD CONSTRAINT faqs_id_key UNIQUE (id);
ALTER TABLE ONLY content.faqs
    ADD CONSTRAINT faqs_pkey PRIMARY KEY (page, identifier);
ALTER TABLE ONLY content."informationBlock"
    ADD CONSTRAINT "informationBlock_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY content."informationGrid"
    ADD CONSTRAINT "informationGrid_id_key" UNIQUE (id);
ALTER TABLE ONLY content."informationGrid"
    ADD CONSTRAINT "informationGrid_pkey" PRIMARY KEY (identifier, page);
ALTER TABLE ONLY crm.brand_customer
    ADD CONSTRAINT "brandCustomer_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY crm.brand_campaign
    ADD CONSTRAINT brand_campaign_pkey PRIMARY KEY ("brandId", "campaignId");
ALTER TABLE ONLY crm.brand_coupon
    ADD CONSTRAINT brand_coupon_pkey PRIMARY KEY ("brandId", "couponId");
ALTER TABLE ONLY crm."campaignType"
    ADD CONSTRAINT "campaignType_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY crm."campaignType"
    ADD CONSTRAINT "campaignType_value_key" UNIQUE (value);
ALTER TABLE ONLY crm.campaign
    ADD CONSTRAINT campaign_pkey PRIMARY KEY (id);
ALTER TABLE ONLY crm.coupon
    ADD CONSTRAINT coupon_code_key UNIQUE (code);
ALTER TABLE ONLY crm.coupon
    ADD CONSTRAINT coupon_pkey PRIMARY KEY (id);
ALTER TABLE ONLY crm."customerReferral"
    ADD CONSTRAINT "customerReferral_keycloakId_key" UNIQUE ("keycloakId");
ALTER TABLE ONLY crm."customerReferral"
    ADD CONSTRAINT "customerReferral_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY crm."customerReferral"
    ADD CONSTRAINT "customerReferral_referralCode_key" UNIQUE ("referralCode");
ALTER TABLE ONLY crm.customer
    ADD CONSTRAINT "customer_dailyKeyUserId_key" UNIQUE ("keycloakId");
ALTER TABLE ONLY crm.customer
    ADD CONSTRAINT customer_email_key UNIQUE (email);
ALTER TABLE ONLY crm.customer
    ADD CONSTRAINT customer_id_key UNIQUE (id);
ALTER TABLE ONLY crm.customer
    ADD CONSTRAINT customer_pkey PRIMARY KEY ("keycloakId");
ALTER TABLE ONLY crm.customer_voucher
    ADD CONSTRAINT customer_voucher_pkey PRIMARY KEY (id);
ALTER TABLE ONLY crm.fact
    ADD CONSTRAINT fact_id_key UNIQUE (id);
ALTER TABLE ONLY crm."loyaltyPointTransaction"
    ADD CONSTRAINT "loyaltyPointTransaction_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY crm."loyaltyPoint"
    ADD CONSTRAINT "loyaltyPoint_keycloakId_key" UNIQUE ("keycloakId");
ALTER TABLE ONLY crm."loyaltyPoint"
    ADD CONSTRAINT "loyaltyPoint_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY crm."orderCart"
    ADD CONSTRAINT "orderCart_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY crm."orderCart_rewards"
    ADD CONSTRAINT "orderCart_rewards_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY crm."rewardHistory"
    ADD CONSTRAINT "rewardHistory_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY crm."rewardType_campaignType"
    ADD CONSTRAINT "rewardType_campaignType_pkey" PRIMARY KEY ("rewardTypeId", "campaignTypeId");
ALTER TABLE ONLY crm."rewardType"
    ADD CONSTRAINT "rewardType_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY crm.reward
    ADD CONSTRAINT reward_pkey PRIMARY KEY (id);
ALTER TABLE ONLY crm."rmkOrder"
    ADD CONSTRAINT "rmkOrder_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY crm.session
    ADD CONSTRAINT session_pkey PRIMARY KEY (id);
ALTER TABLE ONLY crm."walletTransaction"
    ADD CONSTRAINT "walletTransaction_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY crm.wallet
    ADD CONSTRAINT wallet_pkey PRIMARY KEY (id);
ALTER TABLE ONLY "deviceHub".computer
    ADD CONSTRAINT computer_pkey PRIMARY KEY ("printNodeId");
ALTER TABLE ONLY "deviceHub".config
    ADD CONSTRAINT config_name_key UNIQUE (name);
ALTER TABLE ONLY "deviceHub".config
    ADD CONSTRAINT config_pkey PRIMARY KEY (id);
ALTER TABLE ONLY "deviceHub"."labelTemplate"
    ADD CONSTRAINT "labelTemplate_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "deviceHub"."printerType"
    ADD CONSTRAINT "printerType_pkey" PRIMARY KEY (type);
ALTER TABLE ONLY "deviceHub".printer
    ADD CONSTRAINT printer_pkey PRIMARY KEY ("printNodeId");
ALTER TABLE ONLY "deviceHub".scale
    ADD CONSTRAINT scale_pkey PRIMARY KEY ("computerId", "deviceName", "deviceNum");
ALTER TABLE ONLY fulfilment.brand_recurrence
    ADD CONSTRAINT brand_recurrence_pkey PRIMARY KEY ("brandId", "recurrenceId");
ALTER TABLE ONLY fulfilment.charge
    ADD CONSTRAINT charge_pkey PRIMARY KEY (id);
ALTER TABLE ONLY fulfilment."deliveryPreferenceByCharge"
    ADD CONSTRAINT "deliveryPreferenceByCharge_pkey" PRIMARY KEY ("clauseId", "chargeId");
ALTER TABLE ONLY fulfilment."deliveryPreferenceByCharge"
    ADD CONSTRAINT "deliveryPreferenceByCharge_priority_key" UNIQUE (priority);
ALTER TABLE ONLY fulfilment."deliveryService"
    ADD CONSTRAINT "deliveryService_partnershipId_key" UNIQUE ("partnershipId");
ALTER TABLE ONLY fulfilment."deliveryService"
    ADD CONSTRAINT "deliveryService_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY fulfilment."fulfillmentType"
    ADD CONSTRAINT "fulfillmentType_pkey" PRIMARY KEY (value);
ALTER TABLE ONLY fulfilment."mileRange"
    ADD CONSTRAINT "mileRange_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY fulfilment.recurrence
    ADD CONSTRAINT recurrence_pkey PRIMARY KEY (id);
ALTER TABLE ONLY fulfilment."timeSlot"
    ADD CONSTRAINT "timeSlot_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY imports."importHistory"
    ADD CONSTRAINT "importHistory_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY imports.import
    ADD CONSTRAINT imports_pkey PRIMARY KEY (id);
ALTER TABLE ONLY ingredient."ingredientProcessing"
    ADD CONSTRAINT "ingredientProcessing_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY ingredient."ingredientSachet"
    ADD CONSTRAINT "ingredientSachet_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY ingredient.ingredient
    ADD CONSTRAINT ingredient_name_key UNIQUE (name);
ALTER TABLE ONLY ingredient.ingredient
    ADD CONSTRAINT ingredient_pkey PRIMARY KEY (id);
ALTER TABLE ONLY ingredient."modeOfFulfillmentEnum"
    ADD CONSTRAINT "modeOfFulfillmentEnum_pkey" PRIMARY KEY (value);
ALTER TABLE ONLY ingredient."modeOfFulfillment"
    ADD CONSTRAINT "modeOfFulfillment_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY insights."chartOption"
    ADD CONSTRAINT "chartOption_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY insights.chart
    ADD CONSTRAINT chart_pkey PRIMARY KEY (id);
ALTER TABLE ONLY insights.date
    ADD CONSTRAINT date_pkey PRIMARY KEY (date);
ALTER TABLE ONLY insights.day
    ADD CONSTRAINT day_pkey PRIMARY KEY ("dayName");
ALTER TABLE ONLY insights.hour
    ADD CONSTRAINT hour_pkey PRIMARY KEY (hour);
ALTER TABLE ONLY insights.insights
    ADD CONSTRAINT insights_pkey PRIMARY KEY (title);
ALTER TABLE ONLY insights.insights
    ADD CONSTRAINT insights_title_key UNIQUE (title);
ALTER TABLE ONLY insights.month
    ADD CONSTRAINT month_name_key UNIQUE (name);
ALTER TABLE ONLY insights.month
    ADD CONSTRAINT month_pkey PRIMARY KEY (number);
ALTER TABLE ONLY inventory."bulkItemHistory"
    ADD CONSTRAINT "bulkHistory_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY inventory."bulkItem"
    ADD CONSTRAINT "bulkInventoryItem_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY inventory."bulkWorkOrder"
    ADD CONSTRAINT "bulkWorkOrder_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY inventory."packagingHistory"
    ADD CONSTRAINT "packagingHistory_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY inventory."purchaseOrderItem"
    ADD CONSTRAINT "purchaseOrderItem_mandiPurchaseOrderItemId_key" UNIQUE ("mandiPurchaseOrderItemId");
ALTER TABLE ONLY inventory."purchaseOrderItem"
    ADD CONSTRAINT "purchaseOrder_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY inventory."sachetItemHistory"
    ADD CONSTRAINT "sachetHistory_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY inventory."sachetItem"
    ADD CONSTRAINT "sachetItem2_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY inventory."sachetWorkOrder"
    ADD CONSTRAINT "sachetWorkOrder_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY inventory."supplierItem"
    ADD CONSTRAINT "supplierItem_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY inventory.supplier
    ADD CONSTRAINT "supplier_mandiSupplierId_key" UNIQUE ("mandiSupplierId");
ALTER TABLE ONLY inventory.supplier
    ADD CONSTRAINT supplier_pkey PRIMARY KEY (id);
ALTER TABLE ONLY inventory."unitConversionByBulkItem"
    ADD CONSTRAINT "unitConversionByBulkItem_id_key" UNIQUE (id);
ALTER TABLE ONLY inventory."unitConversionByBulkItem"
    ADD CONSTRAINT "unitConversionByBulkItem_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY master."accompanimentType"
    ADD CONSTRAINT "accompanimentType_name_key" UNIQUE (name);
ALTER TABLE ONLY master."accompanimentType"
    ADD CONSTRAINT "accompanimentType_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY master."allergenName"
    ADD CONSTRAINT allergen_name_key UNIQUE (name);
ALTER TABLE ONLY master."allergenName"
    ADD CONSTRAINT allergen_pkey PRIMARY KEY (id);
ALTER TABLE ONLY master."cuisineName"
    ADD CONSTRAINT "cuisineName_id_key" UNIQUE (id);
ALTER TABLE ONLY master."cuisineName"
    ADD CONSTRAINT "cuisineName_name_key" UNIQUE (name);
ALTER TABLE ONLY master."cuisineName"
    ADD CONSTRAINT "cuisineName_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY master."processingName"
    ADD CONSTRAINT processing_name_key UNIQUE (name);
ALTER TABLE ONLY master."processingName"
    ADD CONSTRAINT processing_pkey PRIMARY KEY (id);
ALTER TABLE ONLY master."productCategory"
    ADD CONSTRAINT "productCategory_pkey" PRIMARY KEY (name);
ALTER TABLE ONLY master."unitConversion"
    ADD CONSTRAINT "unitConversion_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY master.unit
    ADD CONSTRAINT unit_name_key UNIQUE (name);
ALTER TABLE ONLY master.unit
    ADD CONSTRAINT unit_pkey PRIMARY KEY (id);
ALTER TABLE ONLY notifications."emailConfig"
    ADD CONSTRAINT "emailConfig_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY notifications."displayNotification"
    ADD CONSTRAINT notification_pkey PRIMARY KEY (id);
ALTER TABLE ONLY notifications."printConfig"
    ADD CONSTRAINT "printConfig_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY notifications."smsConfig"
    ADD CONSTRAINT "smsConfig_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY notifications.type
    ADD CONSTRAINT type_name_key UNIQUE (name);
ALTER TABLE ONLY notifications.type
    ADD CONSTRAINT type_pkey PRIMARY KEY (id);
ALTER TABLE ONLY "onDemand".category
    ADD CONSTRAINT category_id_key UNIQUE (id);
ALTER TABLE ONLY "onDemand".category
    ADD CONSTRAINT category_name_key UNIQUE (name);
ALTER TABLE ONLY "onDemand".category
    ADD CONSTRAINT category_pkey PRIMARY KEY (id);
ALTER TABLE ONLY "onDemand".collection
    ADD CONSTRAINT collection_pkey PRIMARY KEY (id);
ALTER TABLE ONLY "onDemand"."collection_productCategory"
    ADD CONSTRAINT "collection_productCategory_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "onDemand"."collection_productCategory_product"
    ADD CONSTRAINT "collection_productCategory_product_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "onDemand"."menuData"
    ADD CONSTRAINT "menuData_pkey" PRIMARY KEY (name);
ALTER TABLE ONLY "onDemand".menu
    ADD CONSTRAINT menu_pkey PRIMARY KEY (id);
ALTER TABLE ONLY "onDemand".modifier
    ADD CONSTRAINT modifier_data_key UNIQUE (data);
ALTER TABLE ONLY "onDemand".modifier
    ADD CONSTRAINT modifier_name_key UNIQUE (name);
ALTER TABLE ONLY "onDemand".modifier
    ADD CONSTRAINT modifier_pkey PRIMARY KEY (id);
ALTER TABLE ONLY "onDemand".brand_collection
    ADD CONSTRAINT shop_collection_pkey PRIMARY KEY ("brandId", "collectionId");
ALTER TABLE ONLY "onlineStore"."menuCollection"
    ADD CONSTRAINT "menuCollection_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "onlineStore"."productSku"
    ADD CONSTRAINT "productSku_sku_key" UNIQUE (sku);
ALTER TABLE ONLY "onlineStore"."rmkCollection"
    ADD CONSTRAINT "rmkCollection_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "order"."assemblyEnum"
    ADD CONSTRAINT "assemblyEnum_pkey" PRIMARY KEY (value);
ALTER TABLE ONLY "order"."orderInventoryProduct"
    ADD CONSTRAINT "orderInventoryProduct_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "order"."orderMealKitProduct"
    ADD CONSTRAINT "orderItem_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "order"."orderSachet"
    ADD CONSTRAINT "orderMealKitProductDetail_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "order"."orderPaymentStatusEnum"
    ADD CONSTRAINT "orderPaymentStatusEnum_pkey" PRIMARY KEY (value);
ALTER TABLE ONLY "order"."orderReadyToEatProduct"
    ADD CONSTRAINT "orderReadyToEatProduct_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "order"."orderSachetStatusEnum"
    ADD CONSTRAINT "orderSachetStatusEnum_pkey" PRIMARY KEY (value);
ALTER TABLE ONLY "order"."orderStatusEnum"
    ADD CONSTRAINT "orderStatusEnum_pkey" PRIMARY KEY (value);
ALTER TABLE ONLY "order"."order"
    ADD CONSTRAINT order_pkey PRIMARY KEY (id);
ALTER TABLE ONLY packaging."packagingSpecifications"
    ADD CONSTRAINT "packagingSpecifications_mandiPackagingId_key" UNIQUE ("mandiPackagingId");
ALTER TABLE ONLY packaging."packagingSpecifications"
    ADD CONSTRAINT "packagingSpecifications_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY packaging.packaging
    ADD CONSTRAINT "packaging_mandiPackagingId_key" UNIQUE ("mandiPackagingId");
ALTER TABLE ONLY packaging.packaging
    ADD CONSTRAINT packaging_pkey PRIMARY KEY (id);
ALTER TABLE ONLY products."comboProductComponent"
    ADD CONSTRAINT "comboProductComponents_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY products."customizableProductOption"
    ADD CONSTRAINT "customizableProductOptions_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY products."inventoryProductOption"
    ADD CONSTRAINT "inventoryProductOption_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY products."inventoryProduct"
    ADD CONSTRAINT "inventoryProduct_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY products."comboProduct"
    ADD CONSTRAINT "recipeProduct_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY products."simpleRecipeProductOption"
    ADD CONSTRAINT "simpleRecipeProductVariant_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY products."simpleRecipeProduct"
    ADD CONSTRAINT "simpleRecipeProduct_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY products."customizableProduct"
    ADD CONSTRAINT "smartProduct_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY rules.conditions
    ADD CONSTRAINT conditions_pkey PRIMARY KEY (id);
ALTER TABLE ONLY rules.facts
    ADD CONSTRAINT fact_pkey PRIMARY KEY (id);
ALTER TABLE ONLY safety."safetyCheckPerUser"
    ADD CONSTRAINT "safetyCheckByUser_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY safety."safetyCheck"
    ADD CONSTRAINT "safetyCheck_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY settings."appPermission"
    ADD CONSTRAINT "appPermission_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY settings."appSettings"
    ADD CONSTRAINT "appSettings_identifier_key" UNIQUE (identifier);
ALTER TABLE ONLY settings."appSettings"
    ADD CONSTRAINT "appSettings_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY settings.app
    ADD CONSTRAINT apps_pkey PRIMARY KEY (id);
ALTER TABLE ONLY settings.app
    ADD CONSTRAINT apps_title_key UNIQUE (title);
ALTER TABLE ONLY settings."operationConfig"
    ADD CONSTRAINT "operationConfig_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY settings."role_appPermission"
    ADD CONSTRAINT "role_appPermission_pkey" PRIMARY KEY ("appPermissionId", "role_appId");
ALTER TABLE ONLY settings.role_app
    ADD CONSTRAINT role_app_id_key UNIQUE (id);
ALTER TABLE ONLY settings.role_app
    ADD CONSTRAINT role_app_pkey PRIMARY KEY ("roleId", "appId");
ALTER TABLE ONLY settings.role
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);
ALTER TABLE ONLY settings.role
    ADD CONSTRAINT roles_role_key UNIQUE (title);
ALTER TABLE ONLY settings.station_kot_printer
    ADD CONSTRAINT station_kot_printer_pkey PRIMARY KEY ("stationId", "printNodeId");
ALTER TABLE ONLY settings.station
    ADD CONSTRAINT station_pkey PRIMARY KEY (id);
ALTER TABLE ONLY settings.station_label_printer
    ADD CONSTRAINT station_printer_pkey PRIMARY KEY ("stationId", "printNodeId");
ALTER TABLE ONLY settings.station_user
    ADD CONSTRAINT station_user_pkey PRIMARY KEY ("userKeycloakId", "stationId");
ALTER TABLE ONLY settings."user"
    ADD CONSTRAINT "user_keycloakId_key" UNIQUE ("keycloakId");
ALTER TABLE ONLY settings."user"
    ADD CONSTRAINT user_pkey PRIMARY KEY (id);
ALTER TABLE ONLY settings.user_role
    ADD CONSTRAINT user_role_pkey PRIMARY KEY ("userId", "roleId");
ALTER TABLE ONLY "simpleRecipe"."simpleRecipeYield"
    ADD CONSTRAINT "recipeServing_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "simpleRecipe"."simpleRecipeYield_ingredientSachet"
    ADD CONSTRAINT "recipeYield_ingredientSachet_pkey" PRIMARY KEY ("recipeYieldId", "ingredientSachetId");
ALTER TABLE ONLY "simpleRecipe"."simpleRecipe"
    ADD CONSTRAINT "simpleRecipe_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY subscription."brand_subscriptionTitle"
    ADD CONSTRAINT "shop_subscriptionTitle_pkey" PRIMARY KEY ("brandId", "subscriptionTitleId");
ALTER TABLE ONLY subscription."subscriptionItemCount"
    ADD CONSTRAINT "subscriptionItemCount_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY subscription."subscriptionOccurence_customer"
    ADD CONSTRAINT "subscriptionOccurence_customer_pkey" PRIMARY KEY ("subscriptionOccurenceId", "keycloakId");
ALTER TABLE ONLY subscription."subscriptionOccurence"
    ADD CONSTRAINT "subscriptionOccurence_id_key" UNIQUE (id);
ALTER TABLE ONLY subscription."subscriptionOccurence"
    ADD CONSTRAINT "subscriptionOccurence_pkey" PRIMARY KEY ("subscriptionId", "fulfillmentDate");
ALTER TABLE ONLY subscription."subscriptionOccurence_product"
    ADD CONSTRAINT "subscriptionOccurence_product_id_key" UNIQUE (id);
ALTER TABLE ONLY subscription."subscriptionOccurence_product"
    ADD CONSTRAINT "subscriptionOccurence_product_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY subscription."subscriptionServing"
    ADD CONSTRAINT "subscriptionServing_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY subscription."subscriptionTitle"
    ADD CONSTRAINT "subscriptionTitle_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY subscription."subscriptionTitle"
    ADD CONSTRAINT "subscriptionTitle_title_key" UNIQUE (title);
ALTER TABLE ONLY subscription.subscription
    ADD CONSTRAINT subscription_pkey PRIMARY KEY (id);
ALTER TABLE ONLY subscription.subscription_zipcode
    ADD CONSTRAINT subscription_zipcode_pkey PRIMARY KEY ("subscriptionId", zipcode);
CREATE TRIGGER "customerWLRTrigger" AFTER INSERT ON crm.brand_customer FOR EACH ROW EXECUTE FUNCTION crm."createCustomerWLR"();
CREATE TRIGGER "loyaltyPointTransaction" AFTER INSERT ON crm."loyaltyPointTransaction" FOR EACH ROW EXECUTE FUNCTION crm."processLoyaltyPointTransaction"();
CREATE TRIGGER "rewardsTrigger" AFTER INSERT ON crm.brand_customer FOR EACH ROW EXECUTE FUNCTION crm."rewardsTriggerFunction"();
CREATE TRIGGER "rewardsTrigger" AFTER UPDATE OF "referredByCode" ON crm."customerReferral" FOR EACH ROW EXECUTE FUNCTION crm."rewardsTriggerFunction"();
CREATE TRIGGER "set_crm_brandCustomer_updated_at" BEFORE UPDATE ON crm.brand_customer FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();
COMMENT ON TRIGGER "set_crm_brandCustomer_updated_at" ON crm.brand_customer IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_crm_campaign_updated_at BEFORE UPDATE ON crm.campaign FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();
COMMENT ON TRIGGER set_crm_campaign_updated_at ON crm.campaign IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_crm_customer_updated_at BEFORE UPDATE ON crm.customer FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();
COMMENT ON TRIGGER set_crm_customer_updated_at ON crm.customer IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_crm_loyaltyPointTransaction_updated_at" BEFORE UPDATE ON crm."loyaltyPointTransaction" FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();
COMMENT ON TRIGGER "set_crm_loyaltyPointTransaction_updated_at" ON crm."loyaltyPointTransaction" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_crm_loyaltyPoint_updated_at" BEFORE UPDATE ON crm."loyaltyPoint" FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();
COMMENT ON TRIGGER "set_crm_loyaltyPoint_updated_at" ON crm."loyaltyPoint" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_crm_orderCart_updated_at" BEFORE UPDATE ON crm."orderCart" FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();
COMMENT ON TRIGGER "set_crm_orderCart_updated_at" ON crm."orderCart" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_crm_rewardHistory_updated_at" BEFORE UPDATE ON crm."rewardHistory" FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();
COMMENT ON TRIGGER "set_crm_rewardHistory_updated_at" ON crm."rewardHistory" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_crm_walletTransaction_updated_at" BEFORE UPDATE ON crm."walletTransaction" FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();
COMMENT ON TRIGGER "set_crm_walletTransaction_updated_at" ON crm."walletTransaction" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_crm_wallet_updated_at BEFORE UPDATE ON crm.wallet FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();
COMMENT ON TRIGGER set_crm_wallet_updated_at ON crm.wallet IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "walletTransaction" AFTER INSERT ON crm."walletTransaction" FOR EACH ROW EXECUTE FUNCTION crm."processWalletTransaction"();
CREATE TRIGGER "set_deviceHub_computer_updated_at" BEFORE UPDATE ON "deviceHub".computer FOR EACH ROW EXECUTE FUNCTION "deviceHub".set_current_timestamp_updated_at();
COMMENT ON TRIGGER "set_deviceHub_computer_updated_at" ON "deviceHub".computer IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_fulfilment_deliveryPreferenceByCharge_updated_at" BEFORE UPDATE ON fulfilment."deliveryPreferenceByCharge" FOR EACH ROW EXECUTE FUNCTION fulfilment.set_current_timestamp_updated_at();
COMMENT ON TRIGGER "set_fulfilment_deliveryPreferenceByCharge_updated_at" ON fulfilment."deliveryPreferenceByCharge" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_ingredient_ingredientSachet_updatedAt" BEFORE UPDATE ON ingredient."ingredientSachet" FOR EACH ROW EXECUTE FUNCTION ingredient."set_current_timestamp_updatedAt"();
COMMENT ON TRIGGER "set_ingredient_ingredientSachet_updatedAt" ON ingredient."ingredientSachet" IS 'trigger to set value of column "updatedAt" to current timestamp on row update';
CREATE TRIGGER set_insights_insights_updated_at BEFORE UPDATE ON insights.insights FOR EACH ROW EXECUTE FUNCTION insights.set_current_timestamp_updated_at();
COMMENT ON TRIGGER set_insights_insights_updated_at ON insights.insights IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_inventory_bulkItemHistory_updated_at" BEFORE UPDATE ON inventory."bulkItemHistory" FOR EACH ROW EXECUTE FUNCTION inventory.set_current_timestamp_updated_at();
COMMENT ON TRIGGER "set_inventory_bulkItemHistory_updated_at" ON inventory."bulkItemHistory" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_inventory_bulkItem_updatedAt" BEFORE UPDATE ON inventory."bulkItem" FOR EACH ROW EXECUTE FUNCTION inventory."set_current_timestamp_updatedAt"();
COMMENT ON TRIGGER "set_inventory_bulkItem_updatedAt" ON inventory."bulkItem" IS 'trigger to set value of column "updatedAt" to current timestamp on row update';
CREATE TRIGGER "set_inventory_packagingHistory_updated_at" BEFORE UPDATE ON inventory."packagingHistory" FOR EACH ROW EXECUTE FUNCTION inventory.set_current_timestamp_updated_at();
COMMENT ON TRIGGER "set_inventory_packagingHistory_updated_at" ON inventory."packagingHistory" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_inventory_purchaseOrderItem_updated_at" BEFORE UPDATE ON inventory."purchaseOrderItem" FOR EACH ROW EXECUTE FUNCTION inventory.set_current_timestamp_updated_at();
COMMENT ON TRIGGER "set_inventory_purchaseOrderItem_updated_at" ON inventory."purchaseOrderItem" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_inventory_sachetItemHistory_updated_at" BEFORE UPDATE ON inventory."sachetItemHistory" FOR EACH ROW EXECUTE FUNCTION inventory.set_current_timestamp_updated_at();
COMMENT ON TRIGGER "set_inventory_sachetItemHistory_updated_at" ON inventory."sachetItemHistory" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_inventory_sachetWorkOrder_updated_at" BEFORE UPDATE ON inventory."sachetWorkOrder" FOR EACH ROW EXECUTE FUNCTION inventory.set_current_timestamp_updated_at();
COMMENT ON TRIGGER "set_inventory_sachetWorkOrder_updated_at" ON inventory."sachetWorkOrder" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_notifications_notification_updated_at BEFORE UPDATE ON notifications."displayNotification" FOR EACH ROW EXECUTE FUNCTION notifications.set_current_timestamp_updated_at();
COMMENT ON TRIGGER set_notifications_notification_updated_at ON notifications."displayNotification" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_notifications_printConfig_updated_at" BEFORE UPDATE ON notifications."printConfig" FOR EACH ROW EXECUTE FUNCTION notifications.set_current_timestamp_updated_at();
COMMENT ON TRIGGER "set_notifications_printConfig_updated_at" ON notifications."printConfig" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER orderassemblystatustrigger AFTER UPDATE OF "assemblyStatus", "isAssembled" ON "order"."orderInventoryProduct" FOR EACH ROW EXECUTE FUNCTION "order".check_main_order_status_trigger();
CREATE TRIGGER orderassemblystatustrigger AFTER UPDATE OF "assemblyStatus", "isAssembled" ON "order"."orderMealKitProduct" FOR EACH ROW EXECUTE FUNCTION "order".check_main_order_status_trigger();
CREATE TRIGGER orderassemblystatustrigger AFTER UPDATE OF "assemblyStatus", "isAssembled" ON "order"."orderReadyToEatProduct" FOR EACH ROW EXECUTE FUNCTION "order".check_main_order_status_trigger();
CREATE TRIGGER ordersachetstatustrigger AFTER UPDATE OF status, "isAssembled" ON "order"."orderSachet" FOR EACH ROW EXECUTE FUNCTION "order".check_order_status_trigger();
CREATE TRIGGER "postOrderCouponRewards" AFTER INSERT ON "order"."order" FOR EACH ROW EXECUTE FUNCTION crm."postOrderCouponRewards"();
CREATE TRIGGER "rewardsTrigger" AFTER INSERT ON "order"."order" FOR EACH ROW EXECUTE FUNCTION crm."rewardsTriggerFunction"();
CREATE TRIGGER set_order_order_updated_at BEFORE UPDATE ON "order"."order" FOR EACH ROW EXECUTE FUNCTION "order".set_current_timestamp_updated_at();
COMMENT ON TRIGGER set_order_order_updated_at ON "order"."order" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER update_mealk_sachet_status AFTER UPDATE ON "order"."orderMealKitProduct" FOR EACH ROW EXECUTE FUNCTION "order".update_mealkit_sachet_status();
CREATE TRIGGER update_readytoeat_sachet_status AFTER UPDATE ON "order"."orderReadyToEatProduct" FOR EACH ROW EXECUTE FUNCTION "order".update_readytoeat_sachet_status();
CREATE TRIGGER updateorderproductsstatus AFTER UPDATE OF "orderStatus" ON "order"."order" FOR EACH ROW EXECUTE FUNCTION "order".update_order_products_status();
CREATE TRIGGER "set_safety_safetyCheck_updated_at" BEFORE UPDATE ON safety."safetyCheck" FOR EACH ROW EXECUTE FUNCTION safety.set_current_timestamp_updated_at();
COMMENT ON TRIGGER "set_safety_safetyCheck_updated_at" ON safety."safetyCheck" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_settings_apps_updated_at BEFORE UPDATE ON settings.app FOR EACH ROW EXECUTE FUNCTION settings.set_current_timestamp_updated_at();
COMMENT ON TRIGGER set_settings_apps_updated_at ON settings.app IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_settings_operationConfig_updated_at" BEFORE UPDATE ON settings."operationConfig" FOR EACH ROW EXECUTE FUNCTION settings.set_current_timestamp_updated_at();
COMMENT ON TRIGGER "set_settings_operationConfig_updated_at" ON settings."operationConfig" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_settings_role_app_updated_at BEFORE UPDATE ON settings.role_app FOR EACH ROW EXECUTE FUNCTION settings.set_current_timestamp_updated_at();
COMMENT ON TRIGGER set_settings_role_app_updated_at ON settings.role_app IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_settings_roles_updated_at BEFORE UPDATE ON settings.role FOR EACH ROW EXECUTE FUNCTION settings.set_current_timestamp_updated_at();
COMMENT ON TRIGGER set_settings_roles_updated_at ON settings.role IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_settings_user_role_updated_at BEFORE UPDATE ON settings.user_role FOR EACH ROW EXECUTE FUNCTION settings.set_current_timestamp_updated_at();
COMMENT ON TRIGGER set_settings_user_role_updated_at ON settings.user_role IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_subscription_subscriptionOccurence_product_updated_at" BEFORE UPDATE ON subscription."subscriptionOccurence_product" FOR EACH ROW EXECUTE FUNCTION subscription.set_current_timestamp_updated_at();
COMMENT ON TRIGGER "set_subscription_subscriptionOccurence_product_updated_at" ON subscription."subscriptionOccurence_product" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_subscription_subscriptionTitle_updated_at" BEFORE UPDATE ON subscription."subscriptionTitle" FOR EACH ROW EXECUTE FUNCTION subscription.set_current_timestamp_updated_at();
COMMENT ON TRIGGER "set_subscription_subscriptionTitle_updated_at" ON subscription."subscriptionTitle" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
ALTER TABLE ONLY brands."brand_storeSetting"
    ADD CONSTRAINT "brand_storeSetting_brandId_fkey" FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY brands."brand_storeSetting"
    ADD CONSTRAINT "brand_storeSetting_storeSettingId_fkey" FOREIGN KEY ("storeSettingId") REFERENCES brands."storeSetting"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY brands."brand_subscriptionStoreSetting"
    ADD CONSTRAINT "brand_subscriptionStoreSetting_brandId_fkey" FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY brands."brand_subscriptionStoreSetting"
    ADD CONSTRAINT "brand_subscriptionStoreSetting_subscriptionStoreSettingId_fk" FOREIGN KEY ("subscriptionStoreSettingId") REFERENCES brands."subscriptionStoreSetting"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY content."informationBlock"
    ADD CONSTRAINT "informationBlock_faqsId_fkey" FOREIGN KEY ("faqsId") REFERENCES content.faqs(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY content."informationBlock"
    ADD CONSTRAINT "informationBlock_informationGridId_fkey" FOREIGN KEY ("informationGridId") REFERENCES content."informationGrid"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY crm.brand_customer
    ADD CONSTRAINT "brandCustomer_brandId_fkey" FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY crm.brand_customer
    ADD CONSTRAINT "brandCustomer_keycloakId_fkey" FOREIGN KEY ("keycloakId") REFERENCES crm.customer("keycloakId") ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY crm.brand_campaign
    ADD CONSTRAINT "brand_campaign_brandId_fkey" FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm.brand_campaign
    ADD CONSTRAINT "brand_campaign_campaignId_fkey" FOREIGN KEY ("campaignId") REFERENCES crm.campaign(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm.brand_coupon
    ADD CONSTRAINT "brand_coupon_brandId_fkey" FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm.brand_coupon
    ADD CONSTRAINT "brand_coupon_couponId_fkey" FOREIGN KEY ("couponId") REFERENCES crm.coupon(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm.campaign
    ADD CONSTRAINT "campaign_conditionId_fkey" FOREIGN KEY ("conditionId") REFERENCES rules.conditions(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm.campaign
    ADD CONSTRAINT campaign_type_fkey FOREIGN KEY (type) REFERENCES crm."campaignType"(value) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm.coupon
    ADD CONSTRAINT "coupon_visibleConditionId_fkey" FOREIGN KEY ("visibleConditionId") REFERENCES rules.conditions(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."customerReferral"
    ADD CONSTRAINT "customerReferral_brandId_fkey" FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY crm."customerReferral"
    ADD CONSTRAINT "customerReferral_campaignId_fkey" FOREIGN KEY ("referralCampaignId") REFERENCES crm.campaign(id);
ALTER TABLE ONLY crm."customerReferral"
    ADD CONSTRAINT "customerReferral_keycloakId_fkey" FOREIGN KEY ("keycloakId") REFERENCES crm.customer("keycloakId") ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."customerReferral"
    ADD CONSTRAINT "customerReferral_referredByCode_fkey" FOREIGN KEY ("referredByCode") REFERENCES crm."customerReferral"("referralCode") ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm.customer
    ADD CONSTRAINT "customer_subscriptionId_fkey" FOREIGN KEY ("subscriptionId") REFERENCES subscription.subscription(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm.customer_voucher
    ADD CONSTRAINT "customer_voucher_couponId_fkey" FOREIGN KEY ("couponId") REFERENCES crm.coupon(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm.customer_voucher
    ADD CONSTRAINT "customer_voucher_keycloakId_fkey" FOREIGN KEY ("keycloakId") REFERENCES crm.customer("keycloakId") ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."loyaltyPointTransaction"
    ADD CONSTRAINT "loyaltyPointTransaction_customerReferralId_fkey" FOREIGN KEY ("customerReferralId") REFERENCES crm."customerReferral"(id);
ALTER TABLE ONLY crm."loyaltyPointTransaction"
    ADD CONSTRAINT "loyaltyPointTransaction_loyaltyPointId_fkey" FOREIGN KEY ("loyaltyPointId") REFERENCES crm."loyaltyPoint"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."loyaltyPointTransaction"
    ADD CONSTRAINT "loyaltyPointTransaction_orderCartId_fkey" FOREIGN KEY ("orderCartId") REFERENCES crm."orderCart"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."loyaltyPoint"
    ADD CONSTRAINT "loyaltyPoint_brandId_fkey" FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY crm."loyaltyPoint"
    ADD CONSTRAINT "loyaltyPoint_keycloakId_fkey" FOREIGN KEY ("keycloakId") REFERENCES crm.customer("keycloakId") ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."orderCart"
    ADD CONSTRAINT "orderCart_brandId_fkey" FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY crm."orderCart"
    ADD CONSTRAINT "orderCart_chargeId_fkey" FOREIGN KEY ("chargeId") REFERENCES fulfilment.charge(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."orderCart"
    ADD CONSTRAINT "orderCart_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES crm.customer(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."orderCart"
    ADD CONSTRAINT "orderCart_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "order"."order"(id) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY crm."orderCart_rewards"
    ADD CONSTRAINT "orderCart_rewards_orderCartId_fkey" FOREIGN KEY ("orderCartId") REFERENCES crm."orderCart"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."orderCart_rewards"
    ADD CONSTRAINT "orderCart_rewards_rewardId_fkey" FOREIGN KEY ("rewardId") REFERENCES crm.reward(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."orderCart"
    ADD CONSTRAINT "orderCart_subscriptionOccurenceId_fkey" FOREIGN KEY ("subscriptionOccurenceId") REFERENCES subscription."subscriptionOccurence"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory"
    ADD CONSTRAINT "rewardHistory_campaignId_fkey" FOREIGN KEY ("campaignId") REFERENCES crm.campaign(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory"
    ADD CONSTRAINT "rewardHistory_couponId_fkey" FOREIGN KEY ("couponId") REFERENCES crm.coupon(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory"
    ADD CONSTRAINT "rewardHistory_keycloakId_fkey" FOREIGN KEY ("keycloakId") REFERENCES crm.customer("keycloakId") ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory"
    ADD CONSTRAINT "rewardHistory_loyaltyPointTransactionId_fkey" FOREIGN KEY ("loyaltyPointTransactionId") REFERENCES crm."loyaltyPointTransaction"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory"
    ADD CONSTRAINT "rewardHistory_orderCartId_fkey" FOREIGN KEY ("orderCartId") REFERENCES crm."orderCart"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory"
    ADD CONSTRAINT "rewardHistory_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "order"."order"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory"
    ADD CONSTRAINT "rewardHistory_rewardId_fkey" FOREIGN KEY ("rewardId") REFERENCES crm.reward(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory"
    ADD CONSTRAINT "rewardHistory_walletTransactionId_fkey" FOREIGN KEY ("walletTransactionId") REFERENCES crm."walletTransaction"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardType_campaignType"
    ADD CONSTRAINT "rewardType_campaignType_campaignTypeId_fkey" FOREIGN KEY ("campaignTypeId") REFERENCES crm."campaignType"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardType_campaignType"
    ADD CONSTRAINT "rewardType_campaignType_rewardTypeId_fkey" FOREIGN KEY ("rewardTypeId") REFERENCES crm."rewardType"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm.reward
    ADD CONSTRAINT "reward_campaignId_fkey" FOREIGN KEY ("campaignId") REFERENCES crm.campaign(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm.reward
    ADD CONSTRAINT "reward_conditionId_fkey" FOREIGN KEY ("conditionId") REFERENCES rules.conditions(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm.reward
    ADD CONSTRAINT "reward_couponId_fkey" FOREIGN KEY ("couponId") REFERENCES crm.coupon(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."rmkOrder"
    ADD CONSTRAINT "rmkOrder_orderCartId_fkey" FOREIGN KEY ("orderCartId") REFERENCES crm."orderCart"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."walletTransaction"
    ADD CONSTRAINT "walletTransaction_customerReferralId_fkey" FOREIGN KEY ("customerReferralId") REFERENCES crm."customerReferral"(id);
ALTER TABLE ONLY crm."walletTransaction"
    ADD CONSTRAINT "walletTransaction_orderCartId_fkey" FOREIGN KEY ("orderCartId") REFERENCES crm."orderCart"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."walletTransaction"
    ADD CONSTRAINT "walletTransaction_walletId_fkey" FOREIGN KEY ("walletId") REFERENCES crm.wallet(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm.wallet
    ADD CONSTRAINT "wallet_brandId_fkey" FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY crm.wallet
    ADD CONSTRAINT "wallet_keycloakId_fkey" FOREIGN KEY ("keycloakId") REFERENCES crm.customer("keycloakId") ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "deviceHub".printer
    ADD CONSTRAINT "printer_computerId_fkey" FOREIGN KEY ("computerId") REFERENCES "deviceHub".computer("printNodeId") ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "deviceHub".printer
    ADD CONSTRAINT "printer_printerType_fkey" FOREIGN KEY ("printerType") REFERENCES "deviceHub"."printerType"(type) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "deviceHub".scale
    ADD CONSTRAINT "scale_computerId_fkey" FOREIGN KEY ("computerId") REFERENCES "deviceHub".computer("printNodeId") ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "deviceHub".scale
    ADD CONSTRAINT "scale_stationId_fkey" FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY fulfilment.brand_recurrence
    ADD CONSTRAINT "brand_recurrence_brandId_fkey" FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY fulfilment.brand_recurrence
    ADD CONSTRAINT "brand_recurrence_recurrenceId_fkey" FOREIGN KEY ("recurrenceId") REFERENCES fulfilment.recurrence(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY fulfilment.charge
    ADD CONSTRAINT "charge_mileRangeId_fkey" FOREIGN KEY ("mileRangeId") REFERENCES fulfilment."mileRange"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY fulfilment."deliveryPreferenceByCharge"
    ADD CONSTRAINT "deliveryPreferenceByCharge_chargeId_fkey" FOREIGN KEY ("chargeId") REFERENCES fulfilment.charge(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY fulfilment."deliveryPreferenceByCharge"
    ADD CONSTRAINT "deliveryPreferenceByCharge_clauseId_fkey" FOREIGN KEY ("clauseId") REFERENCES fulfilment."deliveryService"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY fulfilment."mileRange"
    ADD CONSTRAINT "mileRange_timeSlotId_fkey" FOREIGN KEY ("timeSlotId") REFERENCES fulfilment."timeSlot"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY fulfilment.recurrence
    ADD CONSTRAINT recurrence_type_fkey FOREIGN KEY (type) REFERENCES fulfilment."fulfillmentType"(value) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY fulfilment."timeSlot"
    ADD CONSTRAINT "timeSlot_recurrenceId_fkey" FOREIGN KEY ("recurrenceId") REFERENCES fulfilment.recurrence(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY imports."importHistory"
    ADD CONSTRAINT "importHistory_importId_fkey" FOREIGN KEY ("importId") REFERENCES imports.import(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY ingredient."ingredientProcessing"
    ADD CONSTRAINT "ingredientProcessing_ingredientId_fkey" FOREIGN KEY ("ingredientId") REFERENCES ingredient.ingredient(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY ingredient."ingredientProcessing"
    ADD CONSTRAINT "ingredientProcessing_processingName_fkey" FOREIGN KEY ("processingName") REFERENCES master."processingName"(name) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY ingredient."ingredientSachet"
    ADD CONSTRAINT "ingredientSachet_ingredientId_fkey" FOREIGN KEY ("ingredientId") REFERENCES ingredient.ingredient(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY ingredient."ingredientSachet"
    ADD CONSTRAINT "ingredientSachet_ingredientProcessingId_fkey" FOREIGN KEY ("ingredientProcessingId") REFERENCES ingredient."ingredientProcessing"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY ingredient."ingredientSachet"
    ADD CONSTRAINT "ingredientSachet_liveMOF_fkey" FOREIGN KEY ("liveMOF") REFERENCES ingredient."modeOfFulfillment"(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE ONLY ingredient."ingredientSachet"
    ADD CONSTRAINT "ingredientSachet_unit_fkey" FOREIGN KEY (unit) REFERENCES master.unit(name) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY ingredient."modeOfFulfillment"
    ADD CONSTRAINT "modeOfFulfillment_bulkItemId_fkey" FOREIGN KEY ("bulkItemId") REFERENCES inventory."bulkItem"(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE ONLY ingredient."modeOfFulfillment"
    ADD CONSTRAINT "modeOfFulfillment_ingredientSachetId_fkey" FOREIGN KEY ("ingredientSachetId") REFERENCES ingredient."ingredientSachet"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY ingredient."modeOfFulfillment"
    ADD CONSTRAINT "modeOfFulfillment_labelTemplateId_fkey" FOREIGN KEY ("labelTemplateId") REFERENCES "deviceHub"."labelTemplate"(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE ONLY ingredient."modeOfFulfillment"
    ADD CONSTRAINT "modeOfFulfillment_packagingId_fkey" FOREIGN KEY ("packagingId") REFERENCES packaging.packaging(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE ONLY ingredient."modeOfFulfillment"
    ADD CONSTRAINT "modeOfFulfillment_sachetItemId_fkey" FOREIGN KEY ("sachetItemId") REFERENCES inventory."sachetItem"(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE ONLY ingredient."modeOfFulfillment"
    ADD CONSTRAINT "modeOfFulfillment_stationId_fkey" FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE ONLY ingredient."modeOfFulfillment"
    ADD CONSTRAINT "modeOfFulfillment_type_fkey" FOREIGN KEY (type) REFERENCES ingredient."modeOfFulfillmentEnum"(value) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY insights."chartOption"
    ADD CONSTRAINT "chartOption_chartId_fkey" FOREIGN KEY ("chartId") REFERENCES insights.chart(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY insights.chart
    ADD CONSTRAINT "chart_insisghtsTitle_fkey" FOREIGN KEY ("insisghtsTitle") REFERENCES insights.insights(title) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY insights.date
    ADD CONSTRAINT date_day_fkey FOREIGN KEY (day) REFERENCES insights.day("dayName") ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItemHistory"
    ADD CONSTRAINT "bulkItemHistory_bulkItemId_fkey" FOREIGN KEY ("bulkItemId") REFERENCES inventory."bulkItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItemHistory"
    ADD CONSTRAINT "bulkItemHistory_orderSachetId_fkey" FOREIGN KEY ("orderSachetId") REFERENCES "order"."orderSachet"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItemHistory"
    ADD CONSTRAINT "bulkItemHistory_purchaseOrderItemId_fkey" FOREIGN KEY ("purchaseOrderItemId") REFERENCES inventory."purchaseOrderItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItemHistory"
    ADD CONSTRAINT "bulkItemHistory_sachetWorkOrderId_fkey" FOREIGN KEY ("sachetWorkOrderId") REFERENCES inventory."sachetWorkOrder"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItemHistory"
    ADD CONSTRAINT "bulkItemHistory_unit_fkey" FOREIGN KEY (unit) REFERENCES master.unit(name) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItemHistory"
    ADD CONSTRAINT "bulkItemHistory_workOrderId_fkey" FOREIGN KEY ("bulkWorkOrderId") REFERENCES inventory."bulkWorkOrder"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItem"
    ADD CONSTRAINT "bulkItem_processingName_fkey" FOREIGN KEY ("processingName") REFERENCES master."processingName"(name) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItem"
    ADD CONSTRAINT "bulkItem_supplierItemId_fkey" FOREIGN KEY ("supplierItemId") REFERENCES inventory."supplierItem"(id) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItem"
    ADD CONSTRAINT "bulkItem_unit_fkey" FOREIGN KEY (unit) REFERENCES master.unit(name) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkWorkOrder"
    ADD CONSTRAINT "bulkWorkOrder_inputBulkItemId_fkey" FOREIGN KEY ("inputBulkItemId") REFERENCES inventory."bulkItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkWorkOrder"
    ADD CONSTRAINT "bulkWorkOrder_inputQuantityUnit_fkey" FOREIGN KEY ("inputQuantityUnit") REFERENCES master.unit(name) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkWorkOrder"
    ADD CONSTRAINT "bulkWorkOrder_outputBulkItemId_fkey" FOREIGN KEY ("outputBulkItemId") REFERENCES inventory."bulkItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkWorkOrder"
    ADD CONSTRAINT "bulkWorkOrder_stationId_fkey" FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON UPDATE RESTRICT ON DELETE SET NULL;
ALTER TABLE ONLY inventory."bulkWorkOrder"
    ADD CONSTRAINT "bulkWorkOrder_supplierItemId_fkey" FOREIGN KEY ("supplierItemId") REFERENCES inventory."supplierItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkWorkOrder"
    ADD CONSTRAINT "bulkWorkOrder_userId_fkey" FOREIGN KEY ("userId") REFERENCES settings."user"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."packagingHistory"
    ADD CONSTRAINT "packagingHistory_packagingId_fkey" FOREIGN KEY ("packagingId") REFERENCES packaging.packaging(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."packagingHistory"
    ADD CONSTRAINT "packagingHistory_purchaseOrderItemId_fkey" FOREIGN KEY ("purchaseOrderItemId") REFERENCES inventory."purchaseOrderItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."purchaseOrderItem"
    ADD CONSTRAINT "purchaseOrderItem_bulkItemId_fkey" FOREIGN KEY ("bulkItemId") REFERENCES inventory."bulkItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."purchaseOrderItem"
    ADD CONSTRAINT "purchaseOrderItem_packagingId_fkey" FOREIGN KEY ("packagingId") REFERENCES packaging.packaging(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."purchaseOrderItem"
    ADD CONSTRAINT "purchaseOrderItem_supplierItemId_fkey" FOREIGN KEY ("supplierItemId") REFERENCES inventory."supplierItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."purchaseOrderItem"
    ADD CONSTRAINT "purchaseOrderItem_supplier_fkey" FOREIGN KEY ("supplierId") REFERENCES inventory.supplier(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."purchaseOrderItem"
    ADD CONSTRAINT "purchaseOrderItem_unit_fkey" FOREIGN KEY (unit) REFERENCES master.unit(name) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetItem"
    ADD CONSTRAINT "sachetItem2_bulkItemId_fkey" FOREIGN KEY ("bulkItemId") REFERENCES inventory."bulkItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetItem"
    ADD CONSTRAINT "sachetItem2_unit_fkey" FOREIGN KEY (unit) REFERENCES master.unit(name) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetItemHistory"
    ADD CONSTRAINT "sachetItemHistory_orderSachetId_fkey" FOREIGN KEY ("orderSachetId") REFERENCES "order"."orderSachet"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetItemHistory"
    ADD CONSTRAINT "sachetItemHistory_sachetItemId_fkey" FOREIGN KEY ("sachetItemId") REFERENCES inventory."sachetItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetItemHistory"
    ADD CONSTRAINT "sachetItemHistory_sachetWorkOrderId_fkey" FOREIGN KEY ("sachetWorkOrderId") REFERENCES inventory."sachetWorkOrder"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetItemHistory"
    ADD CONSTRAINT "sachetItemHistory_unit_fkey" FOREIGN KEY (unit) REFERENCES master.unit(name) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetWorkOrder"
    ADD CONSTRAINT "sachetWorkOrder_inputBulkItemId_fkey" FOREIGN KEY ("inputBulkItemId") REFERENCES inventory."bulkItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetWorkOrder"
    ADD CONSTRAINT "sachetWorkOrder_outputSachetItemId_fkey" FOREIGN KEY ("outputSachetItemId") REFERENCES inventory."sachetItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetWorkOrder"
    ADD CONSTRAINT "sachetWorkOrder_packagingId_fkey" FOREIGN KEY ("packagingId") REFERENCES packaging.packaging(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetWorkOrder"
    ADD CONSTRAINT "sachetWorkOrder_stationId_fkey" FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON UPDATE RESTRICT ON DELETE SET NULL;
ALTER TABLE ONLY inventory."sachetWorkOrder"
    ADD CONSTRAINT "sachetWorkOrder_supplierItemId_fkey" FOREIGN KEY ("supplierItemId") REFERENCES inventory."supplierItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetWorkOrder"
    ADD CONSTRAINT "sachetWorkOrder_userId_fkey" FOREIGN KEY ("userId") REFERENCES settings."user"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."supplierItem"
    ADD CONSTRAINT "supplierItem_importId_fkey" FOREIGN KEY ("importId") REFERENCES imports."importHistory"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY inventory."supplierItem"
    ADD CONSTRAINT "supplierItem_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES inventory.supplier(id) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."supplierItem"
    ADD CONSTRAINT "supplierItem_unit_fkey" FOREIGN KEY (unit) REFERENCES master.unit(name) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory.supplier
    ADD CONSTRAINT "supplier_importId_fkey" FOREIGN KEY ("importId") REFERENCES imports."importHistory"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY inventory."unitConversionByBulkItem"
    ADD CONSTRAINT "unitConversionByBulkItem_bulkItemId_fkey" FOREIGN KEY ("bulkItemId") REFERENCES inventory."bulkItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."unitConversionByBulkItem"
    ADD CONSTRAINT "unitConversionByBulkItem_unitConversionId_fkey" FOREIGN KEY ("unitConversionId") REFERENCES master."unitConversion"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY master."unitConversion"
    ADD CONSTRAINT "unitConversion_inputUnit_fkey" FOREIGN KEY ("inputUnitName") REFERENCES master.unit(name) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY master."unitConversion"
    ADD CONSTRAINT "unitConversion_outputUnit_fkey" FOREIGN KEY ("outputUnitName") REFERENCES master.unit(name) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY notifications."emailConfig"
    ADD CONSTRAINT "emailConfig_typeId_fkey" FOREIGN KEY ("typeId") REFERENCES notifications.type(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY notifications."displayNotification"
    ADD CONSTRAINT "notification_typeId_fkey" FOREIGN KEY ("typeId") REFERENCES notifications.type(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY notifications."printConfig"
    ADD CONSTRAINT "printConfig_printerPrintNodeId_fkey" FOREIGN KEY ("printerPrintNodeId") REFERENCES "deviceHub".printer("printNodeId") ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY notifications."printConfig"
    ADD CONSTRAINT "printConfig_typeId_fkey" FOREIGN KEY ("typeId") REFERENCES notifications.type(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY notifications."smsConfig"
    ADD CONSTRAINT "smsConfig_typeId_fkey" FOREIGN KEY ("typeId") REFERENCES notifications.type(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "onDemand".brand_collection
    ADD CONSTRAINT "brand_collection_collectionId_fkey" FOREIGN KEY ("collectionId") REFERENCES "onDemand".collection(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY "onDemand"."collection_productCategory"
    ADD CONSTRAINT "collection_productCategory_collectionId_fkey" FOREIGN KEY ("collectionId") REFERENCES "onDemand".collection(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY "onDemand"."collection_productCategory"
    ADD CONSTRAINT "collection_productCategory_productCategoryName_fkey" FOREIGN KEY ("productCategoryName") REFERENCES master."productCategory"(name) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY "onDemand"."collection_productCategory_product"
    ADD CONSTRAINT "collection_productCategory_product_collection_productCategor" FOREIGN KEY ("collection_productCategoryId") REFERENCES "onDemand"."collection_productCategory"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY "onDemand"."collection_productCategory_product"
    ADD CONSTRAINT "collection_productCategory_product_comboProductId_fkey" FOREIGN KEY ("comboProductId") REFERENCES products."comboProduct"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY "onDemand"."collection_productCategory_product"
    ADD CONSTRAINT "collection_productCategory_product_customizableProductId_fke" FOREIGN KEY ("customizableProductId") REFERENCES products."customizableProduct"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY "onDemand"."collection_productCategory_product"
    ADD CONSTRAINT "collection_productCategory_product_inventoryProductId_fkey" FOREIGN KEY ("inventoryProductId") REFERENCES products."inventoryProduct"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY "onDemand"."collection_productCategory_product"
    ADD CONSTRAINT "collection_productCategory_product_simpleRecipeProductId_fke" FOREIGN KEY ("simpleRecipeProductId") REFERENCES products."simpleRecipeProduct"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY "onDemand".brand_collection
    ADD CONSTRAINT "shop_collection_shopId_fkey" FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderInventoryProduct"
    ADD CONSTRAINT "orderInventoryProduct_assemblyStationId_fkey" FOREIGN KEY ("assemblyStationId") REFERENCES settings.station(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderInventoryProduct"
    ADD CONSTRAINT "orderInventoryProduct_assemblyStatus_fkey" FOREIGN KEY ("assemblyStatus") REFERENCES "order"."assemblyEnum"(value) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderInventoryProduct"
    ADD CONSTRAINT "orderInventoryProduct_comboProductComponentId_fkey" FOREIGN KEY ("comboProductComponentId") REFERENCES products."comboProductComponent"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderInventoryProduct"
    ADD CONSTRAINT "orderInventoryProduct_comboProductId_fkey" FOREIGN KEY ("comboProductId") REFERENCES products."comboProduct"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderInventoryProduct"
    ADD CONSTRAINT "orderInventoryProduct_customizableProductId_fkey" FOREIGN KEY ("customizableProductId") REFERENCES products."customizableProduct"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderInventoryProduct"
    ADD CONSTRAINT "orderInventoryProduct_customizableProductOptionId_fkey" FOREIGN KEY ("customizableProductOptionId") REFERENCES products."customizableProductOption"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderInventoryProduct"
    ADD CONSTRAINT "orderInventoryProduct_inventoryProductId_fkey" FOREIGN KEY ("inventoryProductId") REFERENCES products."inventoryProduct"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderInventoryProduct"
    ADD CONSTRAINT "orderInventoryProduct_inventoryProductOptionId_fkey" FOREIGN KEY ("inventoryProductOptionId") REFERENCES products."inventoryProductOption"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderInventoryProduct"
    ADD CONSTRAINT "orderInventoryProduct_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "order"."order"(id) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY "order"."orderInventoryProduct"
    ADD CONSTRAINT "orderInventoryProduct_packagingId_fkey" FOREIGN KEY ("packagingId") REFERENCES packaging.packaging(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderSachet"
    ADD CONSTRAINT "orderMealKitProductDetail_bulkItemId_fkey" FOREIGN KEY ("bulkItemId") REFERENCES inventory."bulkItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderSachet"
    ADD CONSTRAINT "orderMealKitProductDetail_ingredientSachetId_fkey" FOREIGN KEY ("ingredientSachetId") REFERENCES ingredient."ingredientSachet"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderMealKitProduct"
    ADD CONSTRAINT "orderMealKitProduct_comboProductComponentId_fkey" FOREIGN KEY ("comboProductComponentId") REFERENCES products."comboProductComponent"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderMealKitProduct"
    ADD CONSTRAINT "orderMealKitProduct_comboProductId_fkey" FOREIGN KEY ("comboProductId") REFERENCES products."comboProduct"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderMealKitProduct"
    ADD CONSTRAINT "orderMealKitProduct_customizableProductId_fkey" FOREIGN KEY ("customizableProductId") REFERENCES products."customizableProduct"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderMealKitProduct"
    ADD CONSTRAINT "orderMealKitProduct_customizableProductOptionId_fkey" FOREIGN KEY ("customizableProductOptionId") REFERENCES products."customizableProductOption"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderMealKitProduct"
    ADD CONSTRAINT "orderMealKitProduct_labelTemplateId_fkey" FOREIGN KEY ("labelTemplateId") REFERENCES "deviceHub"."labelTemplate"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderMealKitProduct"
    ADD CONSTRAINT "orderMealKitProduct_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "order"."order"(id) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY "order"."orderMealKitProduct"
    ADD CONSTRAINT "orderMealKitProduct_packagingId_fkey" FOREIGN KEY ("packagingId") REFERENCES packaging.packaging(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderMealKitProduct"
    ADD CONSTRAINT "orderMealKitProduct_simpleRecipeProductId_fkey" FOREIGN KEY ("simpleRecipeProductId") REFERENCES products."simpleRecipeProduct"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderMealKitProduct"
    ADD CONSTRAINT "orderMealKitProduct_simpleRecipeProductOptionId_fkey" FOREIGN KEY ("simpleRecipeProductOptionId") REFERENCES products."simpleRecipeProductOption"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderReadyToEatProduct"
    ADD CONSTRAINT "orderReadyToEatProduct_assemblyStationId_fkey" FOREIGN KEY ("assemblyStationId") REFERENCES settings.station(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderReadyToEatProduct"
    ADD CONSTRAINT "orderReadyToEatProduct_comboProductComponentId_fkey" FOREIGN KEY ("comboProductComponentId") REFERENCES products."comboProductComponent"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderReadyToEatProduct"
    ADD CONSTRAINT "orderReadyToEatProduct_comboProductId_fkey" FOREIGN KEY ("comboProductId") REFERENCES products."comboProduct"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderReadyToEatProduct"
    ADD CONSTRAINT "orderReadyToEatProduct_customizableProductId_fkey" FOREIGN KEY ("customizableProductId") REFERENCES products."customizableProduct"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderReadyToEatProduct"
    ADD CONSTRAINT "orderReadyToEatProduct_customizableProductOptionId_fkey" FOREIGN KEY ("customizableProductOptionId") REFERENCES products."customizableProductOption"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderReadyToEatProduct"
    ADD CONSTRAINT "orderReadyToEatProduct_labelTemplateId_fkey" FOREIGN KEY ("labelTemplateId") REFERENCES "deviceHub"."labelTemplate"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderReadyToEatProduct"
    ADD CONSTRAINT "orderReadyToEatProduct_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "order"."order"(id) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY "order"."orderReadyToEatProduct"
    ADD CONSTRAINT "orderReadyToEatProduct_packagingId_fkey" FOREIGN KEY ("packagingId") REFERENCES packaging.packaging(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderReadyToEatProduct"
    ADD CONSTRAINT "orderReadyToEatProduct_simpleRecipeId_fkey" FOREIGN KEY ("simpleRecipeId") REFERENCES "simpleRecipe"."simpleRecipe"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderReadyToEatProduct"
    ADD CONSTRAINT "orderReadyToEatProduct_simpleRecipeProductId_fkey" FOREIGN KEY ("simpleRecipeProductId") REFERENCES products."simpleRecipeProduct"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderReadyToEatProduct"
    ADD CONSTRAINT "orderReadyToEatProduct_simpleRecipeProductOptionId_fkey" FOREIGN KEY ("simpleRecipeProductOptionId") REFERENCES products."simpleRecipeProductOption"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderSachet"
    ADD CONSTRAINT "orderSachet_orderMealKitProductId_fkey" FOREIGN KEY ("orderMealKitProductId") REFERENCES "order"."orderMealKitProduct"(id) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY "order"."orderSachet"
    ADD CONSTRAINT "orderSachet_packagingId_fkey" FOREIGN KEY ("packagingId") REFERENCES packaging.packaging(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderSachet"
    ADD CONSTRAINT "orderSachet_packingStationId_fkey" FOREIGN KEY ("packingStationId") REFERENCES settings.station(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderSachet"
    ADD CONSTRAINT "orderSachet_sachetItemId_fkey" FOREIGN KEY ("sachetItemId") REFERENCES inventory."sachetItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderSachet"
    ADD CONSTRAINT "orderSachet_status_fkey" FOREIGN KEY (status) REFERENCES "order"."orderSachetStatusEnum"(value) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderSachet"
    ADD CONSTRAINT "orderSachet_unit_fkey" FOREIGN KEY (unit) REFERENCES master.unit(name) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderMealKitProduct"
    ADD CONSTRAINT "orderSimpleRecipeProduct_assemblyStationId_fkey" FOREIGN KEY ("assemblyStationId") REFERENCES settings.station(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderMealKitProduct"
    ADD CONSTRAINT "orderSimpleRecipeProduct_assemblyStatus_fkey" FOREIGN KEY ("assemblyStatus") REFERENCES "order"."assemblyEnum"(value) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."order"
    ADD CONSTRAINT "order_brandId_fkey" FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."order"
    ADD CONSTRAINT "order_cartId_fkey" FOREIGN KEY ("cartId") REFERENCES crm."orderCart"(id) ON UPDATE CASCADE;
ALTER TABLE ONLY "order"."order"
    ADD CONSTRAINT "order_deliveryPartnershipId_fkey" FOREIGN KEY ("deliveryPartnershipId") REFERENCES fulfilment."deliveryService"("partnershipId") ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."order"
    ADD CONSTRAINT "order_keycloakId_fkey" FOREIGN KEY ("keycloakId") REFERENCES crm.customer("keycloakId") ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY packaging.packaging
    ADD CONSTRAINT "packaging_packagingSpecificationsId_fkey" FOREIGN KEY ("packagingSpecificationsId") REFERENCES packaging."packagingSpecifications"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY packaging.packaging
    ADD CONSTRAINT "packaging_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES inventory.supplier(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY products."comboProductComponent"
    ADD CONSTRAINT "comboProductComponent_comboProductId_fkey" FOREIGN KEY ("comboProductId") REFERENCES products."comboProduct"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY products."comboProductComponent"
    ADD CONSTRAINT "comboProductComponent_customizableProductId_fkey" FOREIGN KEY ("customizableProductId") REFERENCES products."customizableProduct"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY products."comboProductComponent"
    ADD CONSTRAINT "comboProductComponent_inventoryProductId_fkey" FOREIGN KEY ("inventoryProductId") REFERENCES products."inventoryProduct"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY products."comboProductComponent"
    ADD CONSTRAINT "comboProductComponent_simpleRecipeProductId_fkey" FOREIGN KEY ("simpleRecipeProductId") REFERENCES products."simpleRecipeProduct"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY products."comboProduct"
    ADD CONSTRAINT "comboProduct_productSku_fkey" FOREIGN KEY ("productSku") REFERENCES "onlineStore"."productSku"(sku) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY products."customizableProductOption"
    ADD CONSTRAINT "customizableProductOption_customizableProductId_fkey" FOREIGN KEY ("customizableProductId") REFERENCES products."customizableProduct"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY products."customizableProductOption"
    ADD CONSTRAINT "customizableProductOption_inventoryProductId_fkey" FOREIGN KEY ("inventoryProductId") REFERENCES products."inventoryProduct"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY products."customizableProductOption"
    ADD CONSTRAINT "customizableProductOption_simpleRecipeProductId_fkey" FOREIGN KEY ("simpleRecipeProductId") REFERENCES products."simpleRecipeProduct"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY products."customizableProduct"
    ADD CONSTRAINT "customizableProduct_default_fkey" FOREIGN KEY ("default") REFERENCES products."customizableProductOption"(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE ONLY products."customizableProduct"
    ADD CONSTRAINT "customizableProduct_productSku_fkey" FOREIGN KEY ("productSku") REFERENCES "onlineStore"."productSku"(sku) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY products."inventoryProductOption"
    ADD CONSTRAINT "inventoryProductOption_inventoryProductId_fkey" FOREIGN KEY ("inventoryProductId") REFERENCES products."inventoryProduct"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY products."inventoryProductOption"
    ADD CONSTRAINT "inventoryProductOption_labelTemplateId_fkey" FOREIGN KEY ("labelTemplateId") REFERENCES "deviceHub"."labelTemplate"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY products."inventoryProductOption"
    ADD CONSTRAINT "inventoryProductOption_modifierId_fkey" FOREIGN KEY ("modifierId") REFERENCES "onDemand".modifier(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE ONLY products."inventoryProductOption"
    ADD CONSTRAINT "inventoryProductOption_packagingId_fkey" FOREIGN KEY ("packagingId") REFERENCES packaging.packaging(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY products."inventoryProductOption"
    ADD CONSTRAINT "inventoryProductOption_packingStationId_fkey" FOREIGN KEY ("assemblyStationId") REFERENCES settings.station(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY products."inventoryProduct"
    ADD CONSTRAINT "inventoryProduct_default_fkey" FOREIGN KEY ("default") REFERENCES products."inventoryProductOption"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY products."inventoryProduct"
    ADD CONSTRAINT "inventoryProduct_productSku_fkey" FOREIGN KEY ("productSku") REFERENCES "onlineStore"."productSku"(sku) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY products."inventoryProduct"
    ADD CONSTRAINT "inventoryProduct_sachetItemId_fkey" FOREIGN KEY ("sachetItemId") REFERENCES inventory."sachetItem"(id) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY products."inventoryProduct"
    ADD CONSTRAINT "inventoryProduct_supplierItemId_fkey" FOREIGN KEY ("supplierItemId") REFERENCES inventory."supplierItem"(id) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY products."simpleRecipeProductOption"
    ADD CONSTRAINT "simpleRecipeProductOption_assemblyStationId_fkey" FOREIGN KEY ("assemblyStationId") REFERENCES settings.station(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY products."simpleRecipeProductOption"
    ADD CONSTRAINT "simpleRecipeProductOption_labelTemplateId_fkey" FOREIGN KEY ("labelTemplateId") REFERENCES "deviceHub"."labelTemplate"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY products."simpleRecipeProductOption"
    ADD CONSTRAINT "simpleRecipeProductOption_modifierId_fkey" FOREIGN KEY ("modifierId") REFERENCES "onDemand".modifier(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE ONLY products."simpleRecipeProductOption"
    ADD CONSTRAINT "simpleRecipeProductOption_packagingId_fkey" FOREIGN KEY ("packagingId") REFERENCES packaging.packaging(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY products."simpleRecipeProductOption"
    ADD CONSTRAINT "simpleRecipeProductOption_simpleRecipeProductId_fkey" FOREIGN KEY ("simpleRecipeProductId") REFERENCES products."simpleRecipeProduct"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY products."simpleRecipeProductOption"
    ADD CONSTRAINT "simpleRecipeProductOption_simpleRecipeYieldId_fkey" FOREIGN KEY ("simpleRecipeYieldId") REFERENCES "simpleRecipe"."simpleRecipeYield"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY products."simpleRecipeProduct"
    ADD CONSTRAINT "simpleRecipeProduct_default_fkey" FOREIGN KEY ("default") REFERENCES products."simpleRecipeProductOption"(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE ONLY products."simpleRecipeProduct"
    ADD CONSTRAINT "simpleRecipeProduct_productSku_fkey" FOREIGN KEY ("productSku") REFERENCES "onlineStore"."productSku"(sku) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY products."simpleRecipeProduct"
    ADD CONSTRAINT "simpleRecipeProduct_simpleRecipeId_fkey" FOREIGN KEY ("simpleRecipeId") REFERENCES "simpleRecipe"."simpleRecipe"(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE ONLY safety."safetyCheckPerUser"
    ADD CONSTRAINT "safetyCheckByUser_SafetyCheckId_fkey" FOREIGN KEY ("SafetyCheckId") REFERENCES safety."safetyCheck"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY safety."safetyCheckPerUser"
    ADD CONSTRAINT "safetyCheckByUser_userId_fkey" FOREIGN KEY ("userId") REFERENCES settings."user"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY settings."appPermission"
    ADD CONSTRAINT "appPermission_appId_fkey" FOREIGN KEY ("appId") REFERENCES settings.app(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY settings."operationConfig"
    ADD CONSTRAINT "operationConfig_labelTemplateId_fkey" FOREIGN KEY ("labelTemplateId") REFERENCES "deviceHub"."labelTemplate"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY settings."operationConfig"
    ADD CONSTRAINT "operationConfig_stationId_fkey" FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY settings."role_appPermission"
    ADD CONSTRAINT "role_appPermission_appPermissionId_fkey" FOREIGN KEY ("appPermissionId") REFERENCES settings."appPermission"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY settings."role_appPermission"
    ADD CONSTRAINT "role_appPermission_role_appId_fkey" FOREIGN KEY ("role_appId") REFERENCES settings.role_app(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY settings.role_app
    ADD CONSTRAINT "role_app_appId_fkey" FOREIGN KEY ("appId") REFERENCES settings.app(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY settings.role_app
    ADD CONSTRAINT "role_app_roleId_fkey" FOREIGN KEY ("roleId") REFERENCES settings.role(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY settings.station
    ADD CONSTRAINT "station_defaultKotPrinterId_fkey" FOREIGN KEY ("defaultKotPrinterId") REFERENCES "deviceHub".printer("printNodeId") ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY settings.station
    ADD CONSTRAINT "station_defaultLabelPrinterId_fkey" FOREIGN KEY ("defaultLabelPrinterId") REFERENCES "deviceHub".printer("printNodeId") ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY settings.station_kot_printer
    ADD CONSTRAINT "station_kot_printer_printNodeId_fkey" FOREIGN KEY ("printNodeId") REFERENCES "deviceHub".printer("printNodeId") ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY settings.station_kot_printer
    ADD CONSTRAINT "station_kot_printer_stationId_fkey" FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY settings.station_label_printer
    ADD CONSTRAINT "station_printer_printNodeId_fkey" FOREIGN KEY ("printNodeId") REFERENCES "deviceHub".printer("printNodeId") ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY settings.station_label_printer
    ADD CONSTRAINT "station_printer_stationId_fkey" FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY settings.station_user
    ADD CONSTRAINT "station_user_stationId_fkey" FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY settings.station_user
    ADD CONSTRAINT "station_user_userKeycloakId_fkey" FOREIGN KEY ("userKeycloakId") REFERENCES settings."user"("keycloakId") ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY settings.user_role
    ADD CONSTRAINT "user_role_roleId_fkey" FOREIGN KEY ("roleId") REFERENCES settings.role(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY settings.user_role
    ADD CONSTRAINT "user_role_userId_fkey" FOREIGN KEY ("userId") REFERENCES settings."user"("keycloakId") ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipeYield_ingredientSachet"
    ADD CONSTRAINT "simpleRecipeYield_ingredientSachet_ingredientSachetId_fkey" FOREIGN KEY ("ingredientSachetId") REFERENCES ingredient."ingredientSachet"(id) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipeYield_ingredientSachet"
    ADD CONSTRAINT "simpleRecipeYield_ingredientSachet_recipeYieldId_fkey" FOREIGN KEY ("recipeYieldId") REFERENCES "simpleRecipe"."simpleRecipeYield"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipeYield"
    ADD CONSTRAINT "simpleRecipeYield_simpleRecipeId_fkey" FOREIGN KEY ("simpleRecipeId") REFERENCES "simpleRecipe"."simpleRecipe"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipe"
    ADD CONSTRAINT "simpleRecipe_cuisine_fkey" FOREIGN KEY (cuisine) REFERENCES master."cuisineName"(name) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY subscription."brand_subscriptionTitle"
    ADD CONSTRAINT "brand_subscriptionTitle_brandId_fkey" FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY subscription."subscriptionItemCount"
    ADD CONSTRAINT "subscriptionItemCount_subscriptionServingId_fkey" FOREIGN KEY ("subscriptionServingId") REFERENCES subscription."subscriptionServing"(id) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY subscription."subscriptionOccurence_customer"
    ADD CONSTRAINT "subscriptionOccurence_customer_keycloakId_fkey" FOREIGN KEY ("keycloakId") REFERENCES crm.customer("keycloakId") ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY subscription."subscriptionOccurence_customer"
    ADD CONSTRAINT "subscriptionOccurence_customer_orderCartId_fkey" FOREIGN KEY ("orderCartId") REFERENCES crm."orderCart"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY subscription."subscriptionOccurence_customer"
    ADD CONSTRAINT "subscriptionOccurence_customer_subscriptionOccurenceId_fkey" FOREIGN KEY ("subscriptionOccurenceId") REFERENCES subscription."subscriptionOccurence"(id) ON UPDATE SET NULL ON DELETE SET NULL;
ALTER TABLE ONLY subscription."subscriptionOccurence_product"
    ADD CONSTRAINT "subscriptionOccurence_product_productCategory_fkey" FOREIGN KEY ("productCategory") REFERENCES master."productCategory"(name) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY subscription."subscriptionOccurence_product"
    ADD CONSTRAINT "subscriptionOccurence_product_productSku_fkey" FOREIGN KEY ("productSku") REFERENCES "onlineStore"."productSku"(sku) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY subscription."subscriptionOccurence_product"
    ADD CONSTRAINT "subscriptionOccurence_product_simpleRecipeProductId_fkey" FOREIGN KEY ("simpleRecipeProductId") REFERENCES products."simpleRecipeProduct"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY subscription."subscriptionOccurence_product"
    ADD CONSTRAINT "subscriptionOccurence_product_simpleRecipeProductOptionId_fkey" FOREIGN KEY ("simpleRecipeProductOptionId") REFERENCES products."simpleRecipeProductOption"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY subscription."subscriptionOccurence_product"
    ADD CONSTRAINT "subscriptionOccurence_product_subscriptionId_fkey" FOREIGN KEY ("subscriptionId") REFERENCES subscription.subscription(id) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY subscription."subscriptionOccurence_product"
    ADD CONSTRAINT "subscriptionOccurence_product_subscriptionOccurenceId_fkey" FOREIGN KEY ("subscriptionOccurenceId") REFERENCES subscription."subscriptionOccurence"(id) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY subscription."subscriptionOccurence"
    ADD CONSTRAINT "subscriptionOccurence_subscriptionId_fkey" FOREIGN KEY ("subscriptionId") REFERENCES subscription.subscription(id) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY subscription."subscriptionServing"
    ADD CONSTRAINT "subscriptionServing_defaultSubscriptionItemCountId_fkey" FOREIGN KEY ("defaultSubscriptionItemCountId") REFERENCES subscription."subscriptionItemCount"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY subscription."subscriptionServing"
    ADD CONSTRAINT "subscriptionServing_subscriptionTitleId_fkey" FOREIGN KEY ("subscriptionTitleId") REFERENCES subscription."subscriptionTitle"(id) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY subscription."subscriptionTitle"
    ADD CONSTRAINT "subscriptionTitle_defaultSubscriptionServingId_fkey" FOREIGN KEY ("defaultSubscriptionServingId") REFERENCES subscription."subscriptionServing"(id) ON UPDATE SET NULL ON DELETE SET NULL;
ALTER TABLE ONLY subscription.subscription
    ADD CONSTRAINT "subscription_subscriptionItemCountId_fkey" FOREIGN KEY ("subscriptionItemCountId") REFERENCES subscription."subscriptionItemCount"(id) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY subscription.subscription_zipcode
    ADD CONSTRAINT "subscription_zipcode_subscriptionId_fkey" FOREIGN KEY ("subscriptionId") REFERENCES subscription.subscription(id) ON UPDATE CASCADE ON DELETE CASCADE;
