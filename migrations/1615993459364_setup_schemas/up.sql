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



CREATE SCHEMA brands;


CREATE SCHEMA content;


CREATE SCHEMA crm;


CREATE SCHEMA "deviceHub";


CREATE SCHEMA editor;


CREATE SCHEMA fulfilment;


CREATE SCHEMA imports;


CREATE SCHEMA ingredient;


CREATE SCHEMA insights;


CREATE SCHEMA instructions;


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


CREATE SCHEMA subscription;


CREATE SCHEMA website;

CREATE TYPE public.summary AS (pending jsonb,
                               underprocessing jsonb,
                               readytodispatch jsonb,
                               outfordelivery jsonb,
                               delivered jsonb,
                               rejectedcancelled jsonb);


CREATE or replace FUNCTION public.call(text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    res jsonb;
BEGIN
    EXECUTE $1 INTO res;
    RETURN res;
END;
$$;

CREATE OR REPLACE FUNCTION public.exec(text)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
    res boolean;
BEGIN
    EXECUTE $1 INTO res;
    RETURN res;
END;
$function$;


CREATE OR REPLACE FUNCTION public.defaultId(schema text, tab text, col text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
 declare
 idVal integer;
 queryname text;
 existsquery text;
 sequencename text;
BEGIN
sequencename = ('"' || schema || '"'|| '.' || '"' || tab || '_' || col || '_seq' || '"')::text;
execute ('CREATE SEQUENCE IF NOT EXISTS' || sequencename || 'minvalue 1000 OWNED BY "' || schema || '"."' || tab || '"."' || col || '"' );
select (

'select nextval('''

|| sequencename ||

''')') into queryname;

select call(queryname)::integer into idVal;

select ('select exists(select "' || col || '" from "' || schema || '"."' || tab || '" where "' || col || '" = ' || idVal || ')') into existsquery;

WHILE exec(existsquery) = true LOOP
      select call(queryname) into idVal;
      select ('select exists(select "' || col || '" from "' || schema || '"."' || tab || '" where "' || col || '" = ' || idVal || ')') into existsquery;
END LOOP;

return idVal;
END;
$function$;

CREATE FUNCTION brands."getSettings"(brandid integer) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    settings jsonb = '{}';
    setting record;
    brandValue jsonb;
    res jsonb;
BEGIN
    FOR setting IN SELECT * FROM brands."storeSetting" LOOP
        SELECT value FROM brands."brand_storeSetting" WHERE "storeSettingId" = setting.id AND "brandId" = brandId INTO brandValue;
        settings := settings || jsonb_build_object(setting.identifier, COALESCE(brandValue, setting.value));
    END LOOP;
    res := jsonb_build_object('brand', jsonb_build_object(
        'logo', settings->'Brand Logo'->>'url',
        'name', settings->'Brand Name'->>'name',
        'navLinks', settings->'Nav Links',
        'contact', settings->'Contact',
        'policyAvailability', settings->'Policy Availability'
    ), 'visual', jsonb_build_object(
        'color', settings->'Primary Color'->>'color',
        'slides', settings->'Slides',
        'appTitle', settings->'App Title'->>'title',
        'favicon', settings->'Favicon'->>'url'
    ), 'availability', jsonb_build_object(
        'store', settings->'Store Availability',
        'pickup', settings->'Pickup Availability',
        'delivery', settings->'Delivery Availability',
        'referral', settings->'Referral Availability',
        'location', settings->'Location',
        'payments', settings->'Store Live'
    ), 'rewardsSettings', jsonb_build_object(
        'isLoyaltyPointsAvailable', (settings->'Loyalty Points Availability'->>'isAvailable')::boolean,
        'isWalletAvailable', (settings->'Wallet Availability'->>'isAvailable')::boolean,
        'isCouponsAvailable', (settings->'Coupons Availability'->>'isAvailable')::boolean,
        'loyaltyPointsUsage', settings->'Loyalty Points Usage'
    ), 'appSettings', jsonb_build_object(
        'scripts', settings->'Scripts'->>'value'
    ));
    RETURN res;
END;
$$;


CREATE FUNCTION content.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;


CREATE FUNCTION crm."createBrandCustomer"(keycloakid text, brandid integer) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO crm."brand_customer"("keycloakId", "brandId") VALUES(keycloakId, brandId);
END;
$$;


CREATE FUNCTION crm."createCustomer2"(keycloakid text, brandid integer, email text, clientid text) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE
    customerId int;
BEGIN
    INSERT INTO crm.customer("keycloakId", "email", "sourceBrandId")
    VALUES(keycloakId, email, brandId)
    RETURNING id INTO customerId;
    RETURN customerId;
END;
$$;


CREATE FUNCTION crm."createCustomerWLR"() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO crm.wallet("keycloakId", "brandId") VALUES (NEW."keycloakId", NEW."brandId");
    INSERT INTO crm."loyaltyPoint"("keycloakId", "brandId") VALUES (NEW."keycloakId", NEW."brandId");
    INSERT INTO crm."customerReferral"("keycloakId", "brandId") VALUES(NEW."keycloakId", NEW."brandId");
    RETURN NULL;
END;
$$;


CREATE FUNCTION crm."deductLoyaltyPointsPostOrder"() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    cart record;
    amount numeric;
    loyaltyPointId int;
    setting record;
    temp record;
    rate numeric;
BEGIN
    IF NEW."keycloakId" IS NULL THEN
        RETURN NULL;
    END IF;
    SELECT * FROM "order"."cart" WHERE id = NEW."cartId" INTO cart;
    SELECT id FROM crm."loyaltyPoint" WHERE "keycloakId" = NEW."keycloakId" AND "brandId" = NEW."brandId" INTO loyaltyPointId;
    IF cart."loyaltyPointsUsed" > 0 THEN
        SELECT crm."getLoyaltyPointsConversionRate"(NEW."brandId") INTO rate;
        amount := ROUND((cart."loyaltyPointsUsed" * rate), 2);
        INSERT INTO crm."loyaltyPointTransaction"("loyaltyPointId", "points", "orderCartId", "type", "amountRedeemed")
        VALUES (loyaltyPointId, cart."loyaltyPointsUsed", cart.id, 'DEBIT', amount);
    END IF;
    RETURN NULL;
END
$$;


CREATE FUNCTION crm."deductWalletAmountPostOrder"() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    cart record;
    walletId int;
BEGIN
    IF NEW."keycloakId" IS NULL THEN
        RETURN NULL;
    END IF;
    SELECT * FROM "order"."cart" WHERE id = NEW."cartId" INTO cart;
    SELECT id FROM crm."wallet" WHERE "keycloakId" = NEW."keycloakId" AND "brandId" = NEW."brandId" INTO walletId;
    IF cart."walletAmountUsed" > 0 THEN
        INSERT INTO crm."walletTransaction"("walletId", "amount", "orderCartId", "type")
        VALUES (walletId, cart."walletAmountUsed", cart.id, 'DEBIT');
    END IF;
    RETURN NULL;
END
$$;


CREATE TABLE crm."customerData" ( id integer NOT NULL,
                                             data jsonb NOT NULL);


CREATE FUNCTION crm."getCustomer2"(keycloakid text, brandid integer, customeremail text, clientid text) RETURNS
SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $$
DECLARE
    customer record;
    brandCustomer record;
    newCustomerId int;
BEGIN
    SELECT * from crm.customer WHERE "keycloakId" = keycloakId INTO customer;
    IF customer IS NULL THEN
        SELECT crm."createCustomer2"(keycloakId, brandId, customerEmail, clientId) INTO newCustomerId;
    END IF;
    SELECT * FROM crm."brand_customer" WHERE "keycloakId" = keycloakId AND "brandId" = brandId INTO brandCustomer;
    IF brandCustomer is NULL THEN
        PERFORM crm."createBrandCustomer"(keycloakId, brandId);
    END IF;
    -- SELECT * FROM crm.customer WHERE "keycloakId" = keycloakId INTO customer;
    RETURN QUERY SELECT 1 AS id, jsonb_build_object('email', customeremail) AS data;
    -- RETURN jsonb_build_object('id', COALESCE(customer.id, newCustomerId), 'email', customeremail, 'isTest', false, 'keycloakId', keycloakid);
END;
$$;


CREATE FUNCTION crm."getLoyaltyPointsConversionRate"(brandid integer) RETURNS numeric LANGUAGE plpgsql AS $$
DECLARE
    setting record;
    temp record;
BEGIN
        SELECT * FROM brands."storeSetting" WHERE "type" = 'rewards' and "identifier" = 'Loyalty Points Usage' INTO setting;
        SELECT * FROM brands."brand_storeSetting" WHERE "brandId" = brandId AND "storeSettingId" = setting.id INTO temp;
        IF temp IS NOT NULL THEN
            setting := temp;
        END IF;
        RETURN ROUND((setting."value"->>'conversionRate')::numeric, 2);
    RETURN NULL;
END
$$;


CREATE TABLE crm.campaign ( id integer NOT NULL,
                                       type text NOT NULL,
                                                 "metaDetails" jsonb,
                                                 "conditionId" integer, "isRewardMulti" boolean DEFAULT false NOT NULL,
                                                                                                              "isActive" boolean DEFAULT false NOT NULL,
                                                                                                                                               priority integer DEFAULT 1 NOT NULL,
                                                                                                                                                                          created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                      updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                  "isArchived" boolean DEFAULT false NOT NULL);

COMMENT ON TABLE crm.campaign IS 'This table contains all the campaigns across the system.';

COMMENT ON COLUMN crm.campaign.id IS 'Auto generated id for the campaign table row.';

COMMENT ON COLUMN crm.campaign.type IS 'A campaign can be of many types, differentiating how they are implemented. This type here refers to that. The value in this should come from the campaignType table.';

COMMENT ON COLUMN crm.campaign."metaDetails" IS 'This jsonb value contains all the meta details like title, description and picture for this campaign.';

COMMENT ON COLUMN crm.campaign."conditionId" IS 'This represents the rule condition that would be checked for trueness before considering this campaign for implementation for rewards.';

COMMENT ON COLUMN crm.campaign."isRewardMulti" IS 'A campaign could have many rewards. If this is true, that means that all the valid rewards would be applied to the transaction. If false, it would pick the valid reward with highest priority.';

COMMENT ON COLUMN crm.campaign."isActive" IS 'Whether this campaign is active or not.';

COMMENT ON COLUMN crm.campaign."isArchived" IS 'Marks the deletion of campaign if user attempts to delete it.';


CREATE FUNCTION crm.iscampaignvalid(campaign crm.campaign) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    res json;
    temp int;
BEGIN
    SELECT COUNT(*) FROM crm."reward" WHERE "campaignId" = campaign."id" LIMIT 1 into temp;
    IF campaign."conditionId" IS NULL AND temp < 1
        THEN res := json_build_object('status', false, 'error', 'Campaign Condition Or Reward not provided');
    ELSEIF campaign."conditionId" IS NULL
        THEN res := json_build_object('status', false, 'error', 'Campaign Condition not provided');
    ELSEIF temp < 1
        THEN res := json_build_object('status', false, 'error', 'Reward not provided');
    ELSEIF campaign."metaDetails"->'image' IS NULL OR coalesce(TRIM(campaign."metaDetails"->>'image'), '')= ''
        THEN res := json_build_object('status', false, 'error', 'Image not provided');
    ELSEIF campaign."metaDetails"->'description' IS NULL OR coalesce(TRIM(campaign."metaDetails"->>'description'), '')= ''
        THEN res := json_build_object('status', false, 'error', 'Description not provided');
    ELSE
        res := json_build_object('status', true, 'error', '');
    END IF;
    RETURN res;
END
$$;


CREATE TABLE crm.coupon ( id integer NOT NULL,
                                     "isActive" boolean DEFAULT false NOT NULL,
                                                                      "metaDetails" jsonb,
                                                                      code text NOT NULL,
                                                                                "isRewardMulti" boolean DEFAULT false NOT NULL,
                                                                                                                      "visibleConditionId" integer, "isVoucher" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                      "isArchived" boolean DEFAULT false NOT NULL);

COMMENT ON TABLE crm.coupon IS 'This table contains all the coupons across the system.';

COMMENT ON COLUMN crm.coupon.id IS 'Auto generated id for the coupon table row.';

COMMENT ON COLUMN crm.coupon."isActive" IS 'Whether this coupon is active or not.';

COMMENT ON COLUMN crm.coupon."metaDetails" IS 'This jsonb value contains all the meta details like title, description and picture for this coupon.';

COMMENT ON COLUMN crm.coupon."isRewardMulti" IS 'A coupon could have many rewards. If this is true, that means that all the valid rewards would be applied to the transaction. If false, it would pick the valid reward with highest priority.';

COMMENT ON COLUMN crm.coupon."visibleConditionId" IS 'This represents the rule condition that would be checked for trueness before showing the coupon in the store. Please note that this condition doesn''t check if reward is valid or not but strictly just maintains the visibility of the coupon.';

COMMENT ON COLUMN crm.coupon."isArchived" IS 'Marks the deletion of coupon if user attempts to delete it.';


CREATE FUNCTION crm.iscouponvalid(coupon crm.coupon) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    res json;
    temp int;
BEGIN
    SELECT COUNT(*) FROM crm."reward" WHERE "couponId" = coupon."id" into temp;
    IF coupon."visibleConditionId" IS NULL AND temp < 1
        THEN res := json_build_object('status', false, 'error', 'Coupon Condition Or Reward not provided');
    ELSEIF coupon."visibleConditionId" IS NULL
        THEN res := json_build_object('status', false, 'error', 'Coupon Condition not provided');
    ELSEIF temp < 1
        THEN res := json_build_object('status', false, 'error', 'Reward not provided');
    ELSEIF coupon."metaDetails"->'image' IS NULL OR coalesce(TRIM(coupon."metaDetails"->>'image'), '')= ''
        THEN res := json_build_object('status', false, 'error', 'Image not provided');
    ELSEIF coupon."metaDetails"->'title' IS NULL OR coalesce(TRIM(coupon."metaDetails"->>'title'), '')= ''
        THEN res := json_build_object('status', false, 'error', 'Title not provided');
    ELSEIF coupon."metaDetails"->'description' IS NULL OR coalesce(TRIM(coupon."metaDetails"->>'description'), '')= ''
        THEN res := json_build_object('status', false, 'error', 'Description not provided');
    ELSE
        res := json_build_object('status', true, 'error', '');
    END IF;
    RETURN res;
END
$$;


CREATE FUNCTION crm."postOrderCouponRewards"() RETURNS trigger LANGUAGE plpgsql STABLE AS $$
DECLARE
    rec record;
    reward record;
    rewardIds int[];
    params jsonb;
BEGIN
    IF NEW."keycloakId" IS NULL THEN
        RETURN NULL;
    END IF;
    params := jsonb_build_object('keycloakId', NEW."keycloakId", 'orderId', NEW.id, 'cartId', NEW."cartId", 'brandId', NEW."brandId", 'campaignType', 'Post Order');
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


CREATE FUNCTION crm."processLoyaltyPointTransaction"() RETURNS trigger LANGUAGE plpgsql AS $$
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


CREATE FUNCTION crm."processRewardsForCustomer"(rewardids integer[], params jsonb) RETURNS void LANGUAGE plpgsql AS $$
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
                INSERT INTO crm."rewardHistory"("rewardId", "couponId", "keycloakId", "orderCartId", "orderId", "loyaltyPointTransactionId", "loyaltyPoints", "brandId")
                VALUES(reward.id, reward."couponId", params->>'keycloakId', (params->>'cartId')::int, (params->>'orderId')::int, returnedId, pointsToBeCredited, (params->>'brandId')::int);
            ELSE
                INSERT INTO crm."rewardHistory"("rewardId", "campaignId", "keycloakId", "orderCartId", "orderId", "loyaltyPointTransactionId", "loyaltyPoints", "brandId")
                VALUES(reward.id, reward."campaignId", params->>'keycloakId', (params->>'cartId')::int, (params->>'orderId')::int, returnedId, pointsToBeCredited, (params->>'brandId')::int);
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
                INSERT INTO crm."rewardHistory"("rewardId", "couponId", "keycloakId", "orderCartId", "orderId", "walletTransactionId", "walletAmount", "brandId")
                VALUES(reward.id, reward."couponId", params->>'keycloakId', (params->>'cartId')::int, (params->>'orderId')::int, returnedId, amountToBeCredited, (params->>'brandId')::int);
            ELSE
                INSERT INTO crm."rewardHistory"("rewardId", "campaignId", "keycloakId", "orderCartId", "orderId", "walletTransactionId", "walletAmount", "brandId")
                VALUES(reward.id, reward."campaignId", params->>'keycloakId', (params->>'cartId')::int, (params->>'orderId')::int, returnedId, amountToBeCredited, (params->>'brandId')::int);
            END IF;
        ELSIF reward."type" = 'Discount' THEN
            IF reward."couponId" IS NOT NULL THEN
                INSERT INTO crm."rewardHistory"("rewardId", "couponId", "keycloakId", "orderCartId", "orderId", "discount", "brandId")
                VALUES(reward.id, reward."couponId", params->>'keycloakId', (params->>'cartId')::int, (params->>'orderId')::int, (SELECT "couponDiscount" FROM crm."orderCart" WHERE id = (params->>'cartId')::int), (params->>'brandId')::int);
            END IF;
        ELSE
            CONTINUE;
        END IF;
    END LOOP;
END;
$$;


CREATE FUNCTION crm."processWalletTransaction"() RETURNS trigger LANGUAGE plpgsql AS $$
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


CREATE TABLE crm.fact ( id integer NOT NULL);


CREATE FUNCTION crm."referralStatus"(fact crm.fact,
                                     params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT crm."referralStatusFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION crm."referralStatusFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    referralStatus text ;
BEGIN
  SELECT "status" FROM crm."customerReferral" WHERE "keycloakId" = (params->>'keycloakId')::text INTO referralStatus;
  RETURN json_build_object('value', referralStatus, 'valueType','text','argument','keycloakId');
END;
$$;


CREATE FUNCTION crm."rewardsTriggerFunction"() RETURNS trigger LANGUAGE plpgsql AS $$
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
    IF NEW."keycloakId" IS NULL THEN
        RETURN NULL;
    END IF;
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


CREATE FUNCTION crm."setLoyaltyPointsUsedInCart"(cartid integer, points integer) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    UPDATE "order"."cart"
    SET "loyaltyPointsUsed" = points
    WHERE id = cartId;
END
$$;


CREATE TABLE public.response ( success boolean NOT NULL,
                                               message text NOT NULL);


CREATE FUNCTION crm."setReferralCode"(params jsonb) RETURNS
SETOF public.response LANGUAGE plpgsql STABLE AS $$
DECLARE
    rec record;
    kId text;
    code text;
    success boolean := true;
    message text := 'Referral code applied!';
BEGIN
    SELECT "referredByCode" FROM  crm."customerReferral" WHERE "referralCode" = (params->>'referralCode')::uuid AND "brandId" = (params->>'brandId')::int INTO code;
    IF code IS NOT NULL THEN
        -- case when code is already applied
        success := false;
        message := 'Referral code already applied!';
    ELSE
        IF params->>'input' LIKE '%@%' THEN
            SELECT "keycloakId" FROM crm.customer WHERE email = params->>'input' INTO kId;
            SELECT * FROM crm.brand_customer WHERE "keycloakId" = kId AND "brandId" = (params->>'brandId')::int INTO rec;
            IF rec IS NULL THEN
                success := false;
                message := 'Incorrect email!';
            END IF;
            IF kId IS NOT NULL THEN
                SELECT "referralCode" FROM crm."customerReferral" WHERE "keycloakId" = kId AND "brandId" = (params->>'brandId')::int INTO code;
                IF code IS NOT NULL AND code != params->>'referralCode' THEN
                    PERFORM "crm"."updateReferralCode"((params->>'referralCode')::uuid, code::uuid);
                ELSE
                    success := false;
                    message := 'Incorrect email!';
                END IF;
            ELSE
                success := false;
                message := 'Incorrect email!';
            END IF;
        ELSE
            SELECT "referralCode" FROM crm."customerReferral" WHERE "referralCode" = (params->>'input')::uuid AND "brandId" = (params->>'brandId')::int INTO code;
            IF code is NOT NULL AND code != params->>'referralCode' THEN
                PERFORM "crm"."updateReferralCode"((params->>'referralCode')::uuid, code::uuid);
            ELSE
                success := false;
                message := 'Incorrect referral code!';
            END IF;
        END IF;
    END IF;
    RETURN QUERY SELECT success AS success, message AS message;
END;
$$;


CREATE FUNCTION crm."setWalletAmountUsedInCart"(cartid integer, validamount numeric) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    UPDATE "order"."cart"
    SET "walletAmountUsed" = validAmount
    WHERE id = cartId;
END
$$;


CREATE FUNCTION crm.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;


CREATE FUNCTION crm."updateReferralCode"(referralcode uuid,
                                         referredbycode uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    UPDATE crm."customerReferral"
    SET "referredByCode" = referredByCode
    WHERE "referralCode" = referralCode;
END;
$$;


CREATE FUNCTION "deviceHub".set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;


CREATE TABLE editor."priorityFuncTable" ( id integer NOT NULL);


CREATE FUNCTION editor."HandlePriority4"(arg jsonb) RETURNS
SETOF editor."priorityFuncTable" LANGUAGE plpgsql STABLE AS $$
DECLARE
    currentdata jsonb;
    datalist jsonb :='[]';
    tablenameinput text;
    schemanameinput text;
    currentdataid int;
    currentdataposition numeric;
    columnToBeUpdated text;
BEGIN
    datalist := arg->>'data1';
    schemanameinput := arg->>'schemaname';
    tablenameinput := arg->>'tablename';
    columnToBeUpdated := COALESCE(arg->>'column', 'position');
IF arg IS NOT NULL THEN
    FOR currentdata IN SELECT * FROM jsonb_array_elements(datalist) LOOP
        currentdataid := currentdata->>'id';
        currentdataposition := currentdata->>columnToBeUpdated;
         PERFORM editor."updatePriorityFinal"(tablenameinput,schemanameinput, currentdataid, currentdataposition, columnToBeUpdated);
    END LOOP;
END IF;
RETURN QUERY
SELECT
  1 AS id;
END;
$$;


CREATE FUNCTION editor.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;


CREATE FUNCTION editor."updatePriorityFinal"(tablename text, schemaname text, id integer, pos numeric, col text) RETURNS record LANGUAGE plpgsql AS $$
DECLARE
    data record;
    querystring text := '';
BEGIN
  querystring := 'UPDATE '||'"'||schemaname||'"' || '.'||'"'||tablename||'"'||'set ' || col || ' ='|| pos ||'where "id" ='|| id ||' returning *';
    EXECUTE querystring into data ;
  RETURN data;
END;
$$;


CREATE TABLE fulfilment."mileRange" ( id integer NOT NULL,
                                                 "from" numeric, "to" numeric, "leadTime" integer, "prepTime" integer, "isActive" boolean DEFAULT true NOT NULL,
                                                                                                                                                       "timeSlotId" integer, zipcodes jsonb);


CREATE FUNCTION fulfilment."preOrderDeliveryValidity"(milerange fulfilment."mileRange",
                                                      "time" time without time zone) RETURNS boolean LANGUAGE plpgsql STABLE AS $$
DECLARE
    fromVal time;
    toVal time;
BEGIN
    SELECT "from" into fromVal FROM fulfilment."timeSlot" WHERE id = mileRange."timeSlotId";
    SELECT "to" into toVal FROM fulfilment."timeSlot" WHERE id = mileRange."timeSlotId";
    RETURN true;
END
$$;


CREATE TABLE fulfilment."timeSlot" ( id integer NOT NULL,
                                                "recurrenceId" integer, "isActive" boolean DEFAULT true NOT NULL,
                                                                                                        "from" time without time zone,
                                                                                                                                 "to" time without time zone,
                                                                                                                                                        "pickUpLeadTime" integer DEFAULT 120,
                                                                                                                                                                                         "pickUpPrepTime" integer DEFAULT 30);


CREATE FUNCTION fulfilment."preOrderPickupTimeFrom"(timeslot fulfilment."timeSlot") RETURNS time without time zone LANGUAGE plpgsql STABLE AS $$
  -- SELECT "from".timeslot AS fromtime, "pickupLeadTime".timeslot AS buffer, diff(fromtime, buffer) as "pickupFromTime"
  BEGIN
  return ("from".timeslot - "pickupLeadTime".timeslot);
  END
$$;


CREATE FUNCTION fulfilment."preOrderPickupValidity"(timeslot fulfilment."timeSlot",
                                                    "time" time without time zone) RETURNS boolean LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION fulfilment.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;


CREATE FUNCTION ingredient."MOFCost"(mofid integer) RETURNS numeric LANGUAGE plpgsql STABLE AS $$
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
    IF supplierItem.prices IS NULL OR supplierItem.prices->0->'unitPrice'->>'value' = ''
        THEN RETURN 0;
    ELSE
        RETURN (supplierItem.prices->0->'unitPrice'->>'value')::numeric/supplierItem."unitSize";
    END IF;
END
$$;


CREATE FUNCTION ingredient."MOFNutritionalInfo"(mofid integer) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE TABLE ingredient."ingredientSachet" ( id integer NOT NULL,
                                                        quantity numeric NOT NULL,
                                                                         "ingredientProcessingId" integer NOT NULL,
                                                                                                          "ingredientId" integer NOT NULL,
                                                                                                                                 "createdAt" timestamp with time zone DEFAULT now(),
                                                                                                                                                                              "updatedAt" timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                           tracking boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                         unit text NOT NULL,
                                                                                                                                                                                                                                                                   visibility boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                                                                   "liveMOF" integer, "isArchived" boolean DEFAULT false NOT NULL);


CREATE FUNCTION ingredient.cost(sachet ingredient."ingredientSachet") RETURNS numeric LANGUAGE plpgsql STABLE AS $$
DECLARE
    cost numeric;
BEGIN
    SELECT ingredient."sachetCost"(sachet.id) into cost;
    RETURN cost;
END
$$;


CREATE TABLE ingredient."modeOfFulfillment" ( id integer NOT NULL,
                                                         type text NOT NULL,
                                                                   "stationId" integer, "labelTemplateId" integer, "bulkItemId" integer, "isPublished" boolean DEFAULT false NOT NULL,
                                                                                                                                                                             "position" numeric, "ingredientSachetId" integer NOT NULL,
                                                                                                                                                                                                                              "packagingId" integer, "isLive" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                    accuracy integer, "sachetItemId" integer, "operationConfigId" integer, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                                                                                       updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                                                                                                                                   priority integer DEFAULT 1 NOT NULL);


CREATE FUNCTION ingredient."getMOFCost"(mof ingredient."modeOfFulfillment") RETURNS numeric LANGUAGE plpgsql STABLE AS $$
DECLARE
    cost numeric;
BEGIN
    SELECT ingredient."MOFCost"(mof.id) into cost;
    RETURN cost;
END
$$;


CREATE FUNCTION ingredient."getMOFNutritionalInfo"(mof ingredient."modeOfFulfillment") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    info jsonb;
BEGIN
    SELECT ingredient."MOFNutritionalInfo"(mof.id) into info;
    RETURN info;
END
$$;


CREATE TABLE ingredient.ingredient ( id integer NOT NULL,
                                                name text NOT NULL,
                                                          image text, "isPublished" boolean DEFAULT false NOT NULL,
                                                                                                          category text, "createdAt" date DEFAULT now(),
                                                                                                                                                  updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                              "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                 assets jsonb);


CREATE FUNCTION ingredient.image_validity(ing ingredient.ingredient) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT NOT(ing.image IS NULL)
$$;


CREATE FUNCTION ingredient.imagevalidity(image ingredient.ingredient) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT NOT(image.image IS NULL)
$$;


CREATE FUNCTION ingredient.isingredientvalid(ingredient ingredient.ingredient) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION ingredient.ismodevalid(mode ingredient."modeOfFulfillment") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION ingredient.issachetvalid(sachet ingredient."ingredientSachet") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE TABLE "simpleRecipe"."simpleRecipe" ( id integer NOT NULL,
                                                        author text, name jsonb NOT NULL,
                                                                                "cookingTime" text, utensils jsonb,
                                                                                                    description text, cuisine text, image text, show boolean DEFAULT true NOT NULL,
                                                                                                                                                                          assets jsonb,
                                                                                                                                                                          type text, "isPublished" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                         created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                     updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                 "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                                    "notIncluded" jsonb,
                                                                                                                                                                                                                                                                                                                                                    "showIngredients" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                           "showIngredientsQuantity" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                          "showProcedures" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                "isSubRecipe" boolean);


CREATE FUNCTION ingredient.issimplerecipevalid(recipe "simpleRecipe"."simpleRecipe") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION ingredient."nutritionalInfo"(sachet ingredient."ingredientSachet") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    info jsonb;
BEGIN
    SELECT ingredient."sachetNutritionalInfo"(sachet.id) into info;
    RETURN info;
END
$$;


CREATE FUNCTION ingredient."sachetCost"(sachetid integer) RETURNS numeric LANGUAGE plpgsql STABLE AS $$
DECLARE
    sachet record;
    mofId int;
    temp numeric;
BEGIN
    SELECT * FROM ingredient."ingredientSachet" WHERE id = sachetId INTO sachet;
    SELECT id FROM ingredient."modeOfFulfillment" WHERE "ingredientSachetId" = sachetId ORDER BY COALESCE(position, id) DESC LIMIT 1 INTO mofId;
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


CREATE FUNCTION ingredient."sachetNutritionalInfo"(sachet ingredient."ingredientSachet") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    info jsonb;
BEGIN
    SELECT "nutritionalInfo" FROM ingredient."ingredientProcessing" WHERE id = sachet."ingredientProcessingId" into info;
    RETURN info;
END
$$;


CREATE FUNCTION ingredient."sachetNutritionalInfo"(sachetid integer) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    info jsonb;
    sachet record;
    mofId int;
    per numeric;
BEGIN
    SELECT * FROM ingredient."ingredientSachet" WHERE id = sachetId INTO sachet;
    -- order by position and not id
    SELECT id FROM ingredient."modeOfFulfillment" WHERE "ingredientSachetId" = sachetId ORDER BY id DESC NULLS LAST LIMIT 1 INTO mofId;
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


CREATE FUNCTION ingredient.sachetvalidity(sachet ingredient."ingredientSachet") RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT NOT(sachet.unit IS NULL OR sachet.quantity <= 0)
$$;


CREATE FUNCTION ingredient."set_current_timestamp_updatedAt"() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updatedAt" = NOW();
  RETURN _new;
END;
$$;


CREATE FUNCTION ingredient.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;


CREATE FUNCTION ingredient.twiceq(sachet ingredient."ingredientSachet") RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT sachet.quantity*2
$$;


CREATE FUNCTION ingredient.validity(sachet ingredient."ingredientSachet") RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT NOT(sachet.unit IS NULL OR sachet.quantity <= 0)
$$;


CREATE FUNCTION insights.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;


CREATE FUNCTION inventory."customToCustomUnitConverter"(quantity numeric, unit_id integer, bulkdensity numeric DEFAULT 1,
                                                                                                                       unit_to_id integer DEFAULT NULL::integer) RETURNS
SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $$
DECLARE
from_custom_rule record;
to_custom_rule record;
result jsonb := '{"error": null, "result": null}'::jsonb;
proceed text := NULL;
from_in_standard jsonb;
BEGIN
  SELECT "inputUnitName" input_unit, "outputUnitName" output_unit, "conversionFactor" conversion_factor
    FROM master."unitConversion"
    WHERE id = unit_to_id
    into to_custom_rule;
  SELECT "inputUnitName" input_unit, "outputUnitName" output_unit, "conversionFactor" conversion_factor
    FROM master."unitConversion"
    WHERE id = unit_id
    into from_custom_rule;
  IF to_custom_rule IS NULL THEN
    proceed := 'to_unit';
  ELSEIF from_custom_rule IS NULL THEN
    proceed := 'from_unit';
  END IF;
  IF proceed IS NULL THEN
    SELECT data->'result'->'custom'->from_custom_rule.input_unit
      FROM inventory."unitVariationFunc"(quantity, from_custom_rule.input_unit, (-1)::numeric, to_custom_rule.output_unit::text, unit_id)
      INTO from_in_standard;
    SELECT data
      FROM inventory."standardToCustomUnitConverter"(
        (from_in_standard->'equivalentValue')::numeric,
        (from_in_standard->>'toUnitName')::text,
        (-1)::numeric,
        unit_to_id
      )
      INTO result;
    result := jsonb_build_object(
      'error',
      'null'::jsonb,
      'result',
      jsonb_build_object(
        'value',
        quantity,
        'toUnitName',
        to_custom_rule.input_unit,
        'fromUnitName',
        from_custom_rule.input_unit,
        'equivalentValue',
        (result->'result'->'equivalentValue')::numeric
      )
    );
  ELSEIF proceed = 'to_unit' THEN
    result :=
      format('{"error": "no custom unit is defined with the id: %s for argument to_unit, create a conversion rule in the master.\"unitConversion\" table."}', unit_to_id)::jsonb;
  ELSEIF proceed = 'from_unit' THEN
    result :=
      format('{"error": "no custom unit is defined with the id: %s for argument from_unit, create a conversion rule in the master.\"unitConversion\" table."}', unit_id)::jsonb;
  END IF;
  RETURN QUERY
  SELECT
    1 AS id,
    result as data;
END;
$$;


CREATE FUNCTION inventory."customToCustomUnitConverter"(quantity numeric, unit text, bulkdensity numeric DEFAULT 1,
                                                                                                                 unitto text DEFAULT NULL::text) RETURNS
SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $$
DECLARE
from_custom_rule record;
to_custom_rule record;
result jsonb := '{"error": null, "result": null}'::jsonb;
proceed text := NULL;
from_in_standard jsonb;
BEGIN
  SELECT "inputUnitName" input_unit, "outputUnitName" output_unit, "conversionFactor" conversion_factor
    FROM master."unitConversion"
    WHERE "inputUnitName" = unitTo
    into to_custom_rule;
  SELECT "inputUnitName" input_unit, "outputUnitName" output_unit, "conversionFactor" conversion_factor
    FROM master."unitConversion"
    WHERE "inputUnitName" = unit
    into from_custom_rule;
  IF to_custom_rule IS NULL THEN
    proceed := 'to_unit';
  ELSEIF from_custom_rule IS NULL THEN
    proceed := 'from_unit';
  END IF;
  IF proceed IS NULL THEN
    SELECT data->'result'->'custom'->unit
      FROM inventory."unitVariationFunc"('tablename', quantity, unit, -1, to_custom_rule.output_unit::text)
      INTO from_in_standard;
    SELECT data
      FROM inventory."standardToCustomUnitConverter"((from_in_standard->'equivalentValue')::numeric, (from_in_standard->>'toUnitName')::text, -1, unitTo)
      INTO result;
    result := jsonb_build_object(
      'error',
      'null'::jsonb,
      'result',
      jsonb_build_object(
        'value',
        quantity,
        'toUnitName',
        unitTo,
        'fromUnitName',
        unit,
        'equivalentValue',
        (result->'result'->'equivalentValue')::numeric
      )
    );
  ELSEIF proceed = 'to_unit' THEN
    result :=
      format('{"error": "no custom unit is defined with the name: %s, create a conversion rule in the master.\"unitConversion\" table."}', unitTo::text)::jsonb;
  ELSEIF proceed = 'from_unit' THEN
    result :=
      format('{"error": "no custom unit is defined with the name: %s, create a conversion rule in the master.\"unitConversion\" table."}', unit::text)::jsonb;
  END IF;
  RETURN QUERY
  SELECT
    1 AS id,
    result as data;
END;
$$;


CREATE FUNCTION inventory."customUnitVariationFunc"(quantity numeric, unit_id integer, tounit text DEFAULT NULL::text) RETURNS
SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $$
DECLARE
result jsonb;
custom_conversions jsonb;
standard_conversions jsonb;
custom_unit_definition record;
BEGIN
  SELECT "inputUnitName" input_unit, "outputUnitName" output_unit, "conversionFactor" conversion_factor
    FROM master."unitConversion"
    WHERE id = unit_id
    into custom_unit_definition;
  If custom_unit_definition IS NOT NULL THEN
    custom_conversions :=
        jsonb_build_object(
          custom_unit_definition.input_unit,
          jsonb_build_object(
            'value',
            quantity,
            'toUnitName',
            custom_unit_definition.output_unit,
            'fromUnitName',
            custom_unit_definition.input_unit,
            'equivalentValue',
            quantity * custom_unit_definition.conversion_factor
          )
        );
    SELECT data->'result'->'standard'
      FROM inventory."unitVariationFunc"(quantity * custom_unit_definition.conversion_factor, custom_unit_definition.output_unit, -1, toUnit)
      INTO standard_conversions;
  ELSE
    result :=
      format('{"error": "no custom unit is defined with the name: %s, create a conversion rule in the master.\"unitConversion\" table."}', custom_unit_definition.input_unit)::jsonb;
  END IF;
  result :=
    jsonb_build_object(
      'error',
      result->>'error',
      'result',
      jsonb_build_object(
        'custom',
        custom_conversions,
        'standard',
        standard_conversions
      )
    );
  RETURN QUERY
  SELECT
    1 as id,
    result as data;
END
$$;


CREATE FUNCTION inventory."customUnitVariationFunc"(quantity numeric, customunit text, tounit text DEFAULT NULL::text) RETURNS
SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $$
DECLARE
result jsonb;
custom_conversions jsonb;
standard_conversions jsonb;
custom_unit_definition record;
BEGIN
  SELECT "inputUnitName" input_unit, "outputUnitName" output_unit, "conversionFactor" conversion_factor
    FROM master."unitConversion"
    WHERE "inputUnitName" = customUnit
    into custom_unit_definition;
  If custom_unit_definition IS NOT NULL THEN
    custom_conversions :=
        jsonb_build_object(customUnit, jsonb_build_object(
            'value',
            quantity,
            'toUnitName',
            custom_unit_definition.output_unit,
            'fromUnitName',
            custom_unit_definition.input_unit,
            'equivalentValue',
            quantity * custom_unit_definition.conversion_factor
          )
        );
    SELECT data->'result'->'standard'
      FROM inventory."unitVariationFunc"('tablename', quantity * custom_unit_definition.conversion_factor, custom_unit_definition.output_unit, -1, toUnit)
      INTO standard_conversions;
  ELSE
    result :=
      format('{"error": "no custom unit is defined with the name: %s, create a conversion rule in the master.\"unitConversion\" table."}', customUnit)::jsonb;
  END IF;
  result :=
    jsonb_build_object(
      'error',
      result->>'error',
      'result',
      jsonb_build_object(
        'custom',
        custom_conversions,
        'standard',
        standard_conversions
      )
    );
  RETURN QUERY
  SELECT
    1 as id,
    result as data;
END
$$;


CREATE FUNCTION inventory.custom_to_custom_unit_converter(quantity numeric, from_unit text, from_bulk_density numeric, to_unit text, to_unit_bulk_density numeric, from_unit_id integer, to_unit_id integer) RETURNS
SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $$
DECLARE
from_custom_rule record;
to_custom_rule record;
result jsonb := '{"error": null, "result": null}'::jsonb;
proceed text := NULL;
from_in_standard jsonb;
BEGIN
  SELECT "inputUnitName" input_unit, "outputUnitName" output_unit, "conversionFactor" conversion_factor
    FROM master."unitConversion"
    WHERE id = to_unit_id
    into to_custom_rule;
  SELECT "inputUnitName" input_unit, "outputUnitName" output_unit, "conversionFactor" conversion_factor
    FROM master."unitConversion"
    WHERE id = from_unit_id
    into from_custom_rule;
  IF to_custom_rule IS NULL THEN
    proceed := 'to_unit';
  ELSEIF from_custom_rule IS NULL THEN
    proceed := 'from_unit';
  END IF;
  IF proceed IS NULL THEN
    SELECT data->'result'->'custom'->from_custom_rule.input_unit
      FROM inventory.custom_to_standard_unit_converter(
        quantity,
        from_custom_rule.input_unit,
        from_bulk_density,
        to_custom_rule.output_unit::text,
        to_unit_bulk_density,
        from_unit_id,
        '',
        '',
        0
      ) INTO from_in_standard;
    SELECT data
      FROM inventory.standard_to_custom_unit_converter(
        (from_in_standard->'equivalentValue')::numeric,
        (from_in_standard->>'toUnitName')::text,
        from_bulk_density,
        to_unit,
        to_unit_bulk_density,
        to_unit_id
      ) INTO result;
    result := jsonb_build_object(
      'error',
      'null'::jsonb,
      'result',
      jsonb_build_object(
        'value',
        quantity,
        'toUnitName',
        to_unit,
        'fromUnitName',
        from_unit,
        'equivalentValue',
        (result->'result'->'equivalentValue')::numeric
      )
    );
  ELSEIF proceed = 'to_unit' THEN
    result :=
      format(
        '{"error": "no custom unit is defined with the id: %s for argument to_unit, create a conversion rule in the master.\"unitConversion\" table."}',
        to_unit_id
      )::jsonb;
  ELSEIF proceed = 'from_unit' THEN
    result :=
      format(
        '{"error": "no custom unit is defined with the id: %s for argument from_unit, create a conversion rule in the master.\"unitConversion\" table."}',
        from_unit_id
      )::jsonb;
  END IF;
  RETURN QUERY
  SELECT
    1 AS id,
    result as data;
END;
$$;


CREATE FUNCTION inventory.custom_to_standard_unit_converter(quantity numeric, from_unit text, from_bulk_density numeric, to_unit text, to_unit_bulk_density numeric, unit_conversion_id integer, schemaname text, tablename text, entity_id integer) RETURNS
SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $$
DECLARE
result jsonb;
custom_conversions jsonb;
standard_conversions jsonb;
custom_unit_definition record;
BEGIN
  SELECT "inputUnitName" input_unit, "outputUnitName" output_unit, "conversionFactor" conversion_factor
    FROM master."unitConversion"
    WHERE id = unit_conversion_id
    into custom_unit_definition;
  If custom_unit_definition IS NOT NULL THEN
    custom_conversions :=
      jsonb_build_object(
        custom_unit_definition.input_unit,
        jsonb_build_object(
          'value',
          quantity,
          'toUnitName',
          custom_unit_definition.output_unit,
          'fromUnitName',
          custom_unit_definition.input_unit,
          'equivalentValue',
          quantity * custom_unit_definition.conversion_factor
        )
      );
    SELECT data->'result'
      FROM inventory.standard_to_standard_unit_converter(
        quantity * custom_unit_definition.conversion_factor,
        custom_unit_definition.output_unit,
        from_bulk_density,
        to_unit,
        to_unit_bulk_density,
        schemaname,
        tablename,
        entity_id,
        'all'
      ) INTO standard_conversions;
  ELSE
    result :=
      format(
        '{"error": "no custom unit is defined with the id: %s and name: %s, create a conversion rule in the master.\"unitConversion\" table."}',
        unit_conversion_id,
        from_unit
      )::jsonb;
  END IF;
  result :=
    jsonb_build_object(
      'error',
      result->>'error',
      'result',
      jsonb_build_object(
        'custom',
        custom_conversions,
        'others',
        standard_conversions
      )
    );
  RETURN QUERY
  SELECT
    1 as id,
    result as data;
END;
$$;


CREATE FUNCTION inventory."matchIngredientIngredient"(ingredients jsonb,
                                                      ingredientids integer[]) RETURNS
SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $$
DECLARE
ingredient_i record;
ingredient record;
result jsonb;
arr jsonb := '[]';
matched_ingredient jsonb;
BEGIN
  IF ingredientIds IS NOT NULL THEN
    FOR ingredient_i IN
      SELECT name, id FROM ingredient.ingredient
      WHERE name IS NOT NULL
      AND id = ANY(ingredientIds) LOOP
      SELECT * FROM jsonb_array_elements(ingredients) AS found_ingredient
      WHERE (found_ingredient ->> 'ingredientName')::text = ingredient_i.name
      into matched_ingredient;
      IF matched_ingredient IS NOT NULL THEN arr := arr || jsonb_build_object(
          'ingredient',
          matched_ingredient,
          'ingredientId',
          ingredient_i.id
        );
      END IF;
    END LOOP;
  ELSE
    FOR ingredient_i IN
      SELECT name, id FROM ingredient.ingredient
      WHERE name IS NOT NULL
    LOOP
      SELECT * FROM jsonb_array_elements(ingredients) AS found_ingredient
      WHERE (found_ingredient ->> 'ingredientName')::text = ingredient_i.name
      into matched_ingredient;
      IF matched_ingredient IS NOT NULL THEN arr := arr || jsonb_build_object(
          'ingredient',
          matched_ingredient,
          'ingredientId',
          ingredient_i.id
        );
      END IF;
    END LOOP;
  END IF;
result := jsonb_build_object('matchIngredientIngredient', arr);
RETURN QUERY
  SELECT
    1 AS id,
    result AS data;
END;
$$;


CREATE FUNCTION inventory."matchIngredientSachetItem"(ingredients jsonb,
                                                      supplieriteminputs integer[]) RETURNS
SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $$
DECLARE supplier_item record;
result jsonb;
arr jsonb := '[]';
matched_ingredient jsonb;
BEGIN IF supplierItemInputs IS NOT NULL THEN FOR supplier_item IN
SELECT "sachetItem".id sachet_id,
  "supplierItem".id,
  "supplierItem".name
FROM inventory."sachetItem"
  Inner JOIN inventory."bulkItem" ON "bulkItemId" = "bulkItem"."id"
  Inner JOIN inventory."supplierItem" ON "supplierItemId" = "supplierItem"."id"
WHERE "supplierItem".id = ANY (supplierItemInputs) LOOP
SELECT *
FROM jsonb_array_elements(ingredients) AS found_ingredient
WHERE (found_ingredient->>'ingredientName') = supplier_item.name INTO matched_ingredient;
IF matched_ingredient IS NOT NULL THEN arr := arr || jsonb_build_object(
  'ingredient',
  matched_ingredient,
  'supplierItemId',
  supplier_item.id,
  'sachetItemId',
  supplier_item.sachet_id
);
END IF;
END LOOP;
ELSE FOR supplier_item IN
SELECT "sachetItem".id sachet_id,
  "supplierItem".id,
  "supplierItem".name
FROM inventory."sachetItem"
  Inner JOIN inventory."bulkItem" ON "bulkItemId" = "bulkItem"."id"
  Inner JOIN inventory."supplierItem" ON "supplierItemId" = "supplierItem"."id" LOOP
SELECT *
FROM jsonb_array_elements(ingredients) AS found_ingredient
WHERE (found_ingredient->>'ingredientName') = supplier_item.name INTO matched_ingredient;
IF matched_ingredient IS NOT NULL THEN arr := arr || jsonb_build_object(
  'ingredient',
  matched_ingredient,
  'supplierItemId',
  supplier_item.id,
  'sachetItemId',
  supplier_item.sachet_id
);
END IF;
END LOOP;
END IF;
result := jsonb_build_object('ingredientSachetItemMatches', arr);
RETURN QUERY
SELECT 1 AS id,
  result as data;
END;
$$;


CREATE FUNCTION inventory."matchIngredientSupplierItem"(ingredients jsonb,
                                                        supplieriteminputs integer[]) RETURNS
SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $$
DECLARE supplier_item record;
ingredient record;
result jsonb;
arr jsonb := '[]';
matched_ingredient jsonb;
BEGIN IF supplierItemInputs IS NOT NULL THEN FOR supplier_item IN
SELECT "supplierItem".id,
  "supplierItem"."name"
FROM inventory."supplierItem"
WHERE "supplierItem".id = ANY (supplierItemInputs) LOOP
SELECT *
FROM jsonb_array_elements(ingredients) AS found_ingredient
WHERE (found_ingredient->>'ingredientName') = supplier_item.name INTO matched_ingredient;
IF matched_ingredient IS NOT NULL THEN arr := arr || jsonb_build_object(
  'ingredient',
  matched_ingredient,
  'supplierItemId',
  supplier_item.id
);
END IF;
END LOOP;
ELSE FOR supplier_item IN
SELECT "supplierItem".id,
  "supplierItem"."name"
FROM inventory."supplierItem" LOOP
SELECT *
FROM jsonb_array_elements(ingredients) AS found_ingredient
WHERE (found_ingredient->>'ingredientName') = supplier_item.name INTO matched_ingredient;
IF matched_ingredient IS NOT NULL THEN arr := arr || jsonb_build_object(
  'ingredient',
  matched_ingredient,
  'supplierItemId',
  supplier_item.id
);
END IF;
END LOOP;
END IF;
result := jsonb_build_object('ingredientSupplierItemMatches', arr);
RETURN QUERY
SELECT 1 AS id,
  result as data;
END;
$$;


CREATE FUNCTION inventory."matchSachetIngredientSachet"(sachets jsonb,
                                                        ingredientsachetids integer[]) RETURNS
SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $$
DECLARE sachet_ingredient record;
sachet record;
result jsonb;
arr jsonb := '[]';
matched_sachet jsonb;
BEGIN IF ingredientSachetIds IS NOT NULL THEN FOR sachet_ingredient IN
SELECT
  "ingredientSachet".id,
  quantity,
  "processingName",
  name
FROM
  ingredient."ingredientSachet"
  JOIN ingredient."ingredientProcessing" ON "ingredientProcessingId" = "ingredientProcessing".id
  JOIN ingredient.ingredient ON "ingredientSachet"."ingredientId" = ingredient.id
WHERE
  "ingredientSachet"."quantity" IS NOT NULL
  AND "ingredientProcessing"."processingName" IS NOT NULL
  AND "ingredientSachet".id = ANY (ingredientSachetIds) LOOP
SELECT
  *
FROM
  jsonb_array_elements(sachets) AS found_sachet
WHERE
  (found_sachet ->> 'quantity') :: int = sachet_ingredient."quantity"
  AND (found_sachet ->> 'processingName') = sachet_ingredient."processingName"
  AND (found_sachet ->> 'ingredientName') = sachet_ingredient.name INTO matched_sachet;
IF matched_sachet IS NOT NULL THEN arr := arr || jsonb_build_object(
    'sachet',
    matched_sachet,
    'ingredientSachetId',
    sachet_ingredient.id,
    'isProcessingExactMatch',
    true
  );
END IF;
END LOOP;
ELSE FOR sachet_ingredient IN
SELECT
  "ingredientSachet".id,
  quantity,
  "processingName",
  name
FROM
  ingredient."ingredientSachet"
  JOIN ingredient."ingredientProcessing" ON "ingredientProcessingId" = "ingredientProcessing".id
  JOIN ingredient.ingredient ON "ingredientSachet"."ingredientId" = ingredient.id
WHERE
  "ingredientSachet"."quantity" IS NOT NULL
  AND "ingredientProcessing"."processingName" IS NOT NULL LOOP
SELECT
  *
FROM
  jsonb_array_elements(sachets) AS found_sachet
WHERE
  (found_sachet ->> 'quantity') :: int = sachet_ingredient."quantity"
  AND (found_sachet ->> 'processingName') = sachet_ingredient."processingName"
  AND (found_sachet ->> 'ingredientName') = sachet_ingredient.name INTO matched_sachet;
IF matched_sachet IS NOT NULL THEN arr := arr || jsonb_build_object(
    'sachet',
    matched_sachet,
    'ingredientSachetId',
    sachet_ingredient.id,
    'isProcessingExactMatch',
    true
  );
END IF;
END LOOP;
END IF;
result := jsonb_build_object('sachetIngredientSachetMatches', arr);
RETURN QUERY
SELECT
  1 AS id,
  result as data;
END;
$$;


CREATE FUNCTION inventory."matchSachetSachetItem"(sachets jsonb,
                                                  sachetitemids integer[]) RETURNS
SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $$
DECLARE supplier_item record;
sachet record;
result jsonb;
arr jsonb := '[]';
matched_sachet jsonb;
BEGIN IF sachetItemIds IS NOT NULL THEN FOR supplier_item IN
SELECT "supplierItem".id,
  "supplierItem"."name",
  "processingName",
  "bulkItem".id "processingId",
  "sachetItem"."unitSize",
  "sachetItem"."unit",
  "sachetItem".id sachet_item_id
FROM inventory."supplierItem"
  LEFT JOIN inventory."bulkItem" ON "supplierItem"."id" = "bulkItem"."supplierItemId"
  LEFT JOIN inventory."sachetItem" ON "sachetItem"."bulkItemId" = "bulkItem"."id"
WHERE "sachetItem"."unitSize" IS NOT NULL
  AND "sachetItem".id = ANY (sachetItemIds) LOOP
SELECT *
FROM jsonb_array_elements(sachets) AS found_sachet
WHERE (found_sachet->>'quantity')::int = supplier_item."unitSize"
  AND (found_sachet->>'processingName') = supplier_item."processingName"
  AND (found_sachet->>'ingredientName') = supplier_item.name INTO matched_sachet;
IF matched_sachet IS NOT NULL THEN arr := arr || jsonb_build_object(
  'sachet',
  matched_sachet,
  'supplierItemId',
  supplier_item.id,
  'supplierItemUnit',
  supplier_item.unit,
  'matched_sachetId',
  supplier_item.sachet_item_id,
  'isProcessingExactMatch',
  true
);
END IF;
END LOOP;
ELSE FOR supplier_item IN
SELECT "supplierItem".id,
  "supplierItem"."name",
  "processingName",
  "bulkItem".id "processingId",
  "sachetItem"."unitSize",
  "sachetItem"."unit",
  "sachetItem"."id" sachet_item_id
FROM inventory."supplierItem"
  LEFT JOIN inventory."bulkItem" ON "supplierItem"."id" = "bulkItem"."supplierItemId"
  LEFT JOIN inventory."sachetItem" ON "sachetItem"."bulkItemId" = "bulkItem"."id"
WHERE "sachetItem"."unitSize" IS NOT NULL
  AND "processingName" IS NOT NULL LOOP
SELECT *
FROM jsonb_array_elements(sachets) AS found_sachet
WHERE (found_sachet->>'quantity')::int = supplier_item."unitSize"
  AND (found_sachet->>'processingName') = supplier_item."processingName"
  AND (found_sachet->>'ingredientName') = supplier_item.name INTO matched_sachet;
IF matched_sachet IS NOT NULL THEN arr := arr || jsonb_build_object(
  'sachet',
  matched_sachet,
  'supplierItemId',
  supplier_item.id,
  'supplierItemUnit',
  supplier_item.unit,
  'matched_sachetId',
  supplier_item.sachet_item_id,
  'isProcessingExactMatch',
  true
);
END IF;
END LOOP;
END IF;
result := jsonb_build_object('sachetSachetItemMatches', arr);
RETURN QUERY
SELECT 1 AS id,
  result as data;
END;
$$;


CREATE FUNCTION inventory."matchSachetSupplierItem"(sachets jsonb,
                                                    supplieriteminputs integer[]) RETURNS
SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $$
DECLARE supplier_item record;
sachet record;
result jsonb;
arr jsonb := '[]';
matched_sachet jsonb;
BEGIN IF supplierItemInputs IS NOT NULL THEN FOR supplier_item IN
SELECT "supplierItem".id,
  "supplierItem"."name",
  "supplierItem"."unitSize",
  "supplierItem".unit,
  "processingName"
FROM inventory."supplierItem"
  LEFT JOIN inventory."bulkItem" ON "bulkItemAsShippedId" = "bulkItem"."id"
WHERE "supplierItem".id = ANY (supplierItemInputs) LOOP
SELECT *
FROM jsonb_array_elements(sachets) AS found_sachet
WHERE (found_sachet->>'quantity')::int = supplier_item."unitSize"
  AND (found_sachet->>'processingName') = supplier_item."processingName"
  AND (found_sachet->>'ingredientName') = supplier_item.name INTO matched_sachet;
IF matched_sachet IS NOT NULL THEN arr := arr || jsonb_build_object(
  'sachet',
  matched_sachet,
  'supplierItemId',
  supplier_item.id,
  'isProcessingExactMatch',
  true
);
END IF;
END LOOP;
ELSE FOR supplier_item IN
SELECT "supplierItem".id,
  "supplierItem"."name",
  "supplierItem"."unitSize",
  "supplierItem".unit,
  "processingName"
FROM inventory."supplierItem"
  LEFT JOIN inventory."bulkItem" ON "bulkItemAsShippedId" = "bulkItem"."id"
WHERE "processingName" IS NOT NULL LOOP
SELECT *
FROM jsonb_array_elements(sachets) AS found_sachet
WHERE (found_sachet->>'quantity')::int = supplier_item."unitSize"
  AND (found_sachet->>'processingName') = supplier_item."processingName"
  AND (found_sachet->>'ingredientName') = supplier_item.name INTO matched_sachet;
IF matched_sachet IS NOT NULL THEN arr := arr || jsonb_build_object(
  'sachet',
  matched_sachet,
  'supplierItemId',
  supplier_item.id,
  'isProcessingExactMatch',
  true
);
END IF;
END LOOP;
END IF;
result := jsonb_build_object('sachetSupplierItemMatches', arr);
RETURN QUERY
SELECT 1 AS id,
  result as data;
END;
$$;


CREATE FUNCTION inventory."set_current_timestamp_updatedAt"() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updatedAt" = NOW();
  RETURN _new;
END;
$$;


CREATE FUNCTION inventory.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;


CREATE FUNCTION inventory."standardToCustomUnitConverter"(quantity numeric, unit text, bulkdensity numeric DEFAULT 1,
                                                                                                                   unit_to_id numeric DEFAULT NULL::numeric) RETURNS
SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $$
DECLARE
result jsonb := '{"error": null, "result": null}'::jsonb;
custom_rule record;
converted_standard jsonb;
BEGIN
  -- unit_to_id is the id of a custom rule in master."unitConversion"
  SELECT "inputUnitName" input_unit, "outputUnitName" output_unit, "conversionFactor" conversion_factor
    FROM master."unitConversion"
    WHERE id = unit_to_id
    into custom_rule;
  IF custom_rule IS NOT NULL THEN
    SELECT data FROM inventory."unitVariationFunc"(quantity, unit, (-1)::numeric, custom_rule.output_unit, -1) into converted_standard;
    result := jsonb_build_object(
      'error',
      'null'::jsonb,
      'result',
      jsonb_build_object(
        'fromUnitName',
        unit,
        'toUnitName',
        custom_rule.input_unit,
        'value',
        quantity,
        'equivalentValue',
        (converted_standard->'result'->'standard'->custom_rule.output_unit->>'equivalentValue')::numeric / custom_rule.conversion_factor
    ));
  ELSE
    -- costruct an error msg
    result :=
      format('{"error": "no custom unit is defined with the id: %s, create a conversion rule in the master.\"unitConversion\" table."}', unit_to_id)::jsonb;
  END IF;
  RETURN QUERY
  SELECT
    1 AS id,
    result as data;
END;
$$;


CREATE FUNCTION inventory.standard_to_all_converter(quantity numeric, from_unit text, from_bulk_density numeric, tablename text, entity_id integer, all_mode text DEFAULT 'all'::text) RETURNS
SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $_$ DECLARE definitions jsonb := $${"kg":{"name":{"abbr":"kg","singular":"Kilogram","plural":"Kilograms"},"base":"g","factor":1000},
                        "g":{"name":{"abbr":"g","singular":"Gram","plural":"Grams"},"base":"g","factor":1},
                        "mg":{"name":{"abbr":"mg","singular":"Miligram","plural":"MiliGrams"},"base":"g","factor":0.001},
                        "oz":{"name":{"abbr":"oz","singular":"Ounce","plural":"Ounces"},"base":"g","factor":28.3495},
                        "l":{"name":{"abbr":"l","singular":"Litre","plural":"Litres"},"base":"ml","factor":1000,"bulkDensity":1},
                        "ml":{"name":{"abbr":"ml","singular":"Millilitre","plural":"Millilitres"},"base":"ml","factor":1,"bulkDensity":1}
                        }$$; unit_key record; custom_unit_key record; from_definition jsonb; local_result jsonb; result_standard jsonb := '{}'::jsonb; result_custom jsonb := '{}'::jsonb; result jsonb := '{"error": null, "result": null}'::jsonb; converted_value numeric; BEGIN IF all_mode = 'standard'
OR all_mode = 'all' THEN from_definition := definitions -> from_unit;
FOR unit_key IN
SELECT key,
       value
FROM jsonb_each(definitions) LOOP -- unit_key is definition from definitions.
 IF unit_key.value -> 'bulkDensity' THEN -- to is volume
 IF from_definition -> 'bulkDensity' THEN -- from is volume too
 converted_value := quantity * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric; local_result := jsonb_build_object('fromUnitName', from_unit, 'toUnitName', unit_key.key, 'value', quantity, 'equivalentValue', converted_value); ELSE -- from is mass
 converted_value := quantity * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric / (unit_key.value->>'bulkDensity')::numeric; local_result := jsonb_build_object('fromUnitName', from_unit, 'toUnitName', unit_key.key, 'value', quantity, 'equivalentValue', converted_value); END IF; ELSE -- to is mass
 IF from_definition -> 'bulkDensity' THEN -- from is volume
 converted_value := quantity * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric * (from_unit_bulk_density)::numeric; local_result := jsonb_build_object('fromUnitName', from_unit, 'toUnitName', unit_key.key, 'value', quantity, 'equivalentValue', converted_value); ELSE -- from is mass too
 converted_value := quantity * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric; local_result := jsonb_build_object('fromUnitName', from_unit, 'toUnitName', unit_key.key, 'value', quantity, 'equivalentValue', converted_value); END IF; END IF; result_standard := result_standard || jsonb_build_object(unit_key.key, local_result); END LOOP; ELSEIF all_mode = 'custom'
OR all_mode = 'all' THEN
FOR custom_unit_key IN EXECUTE format($$SELECT
          "inputUnitName" input_unit,
          "outputUnitName" output_unit,
          "conversionFactor" conversion_factor,
          "unitConversionId" unit_conversion_id
        FROM %I
        INNER JOIN master."unitConversion"
        ON "unitConversionId" = "unitConversion".id
        WHERE "entityId" = (%s)::integer;$$, tablename, entity_id) LOOP
SELECT data
FROM inventory.standard_to_custom_unit_converter(quantity, from_unit, from_bulk_density, custom_unit_key.input_unit, (-1)::numeric, custom_unit_key.unit_conversion_id) INTO local_result; result_custom := result_custom || jsonb_build_object(custom_unit_key.input_unit, local_result); END LOOP; END IF; result := jsonb_build_object('result', jsonb_build_object('standard', result_standard, 'custom', result_custom), 'error', 'null'::jsonb); RETURN QUERY
SELECT 1 AS id,
       result as data; END; $_$;


CREATE FUNCTION inventory.standard_to_all_converter(quantity numeric, from_unit text, from_bulk_density numeric, schemaname text DEFAULT ''::text, tablename text DEFAULT ''::text, entity_id integer DEFAULT '-1'::integer, all_mode text DEFAULT 'all'::text) RETURNS
SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $_$ DECLARE definitions jsonb := $${"kg":{"name":{"abbr":"kg","singular":"Kilogram","plural":"Kilograms"},"base":"g","factor":1000},
                        "g":{"name":{"abbr":"g","singular":"Gram","plural":"Grams"},"base":"g","factor":1},
                        "mg":{"name":{"abbr":"mg","singular":"Miligram","plural":"MiliGrams"},"base":"g","factor":0.001},
                        "oz":{"name":{"abbr":"oz","singular":"Ounce","plural":"Ounces"},"base":"g","factor":28.3495},
                        "l":{"name":{"abbr":"l","singular":"Litre","plural":"Litres"},"base":"ml","factor":1000,"bulkDensity":1},
                        "ml":{"name":{"abbr":"ml","singular":"Millilitre","plural":"Millilitres"},"base":"ml","factor":1,"bulkDensity":1}
                        }$$; unit_key record; custom_unit_key record; from_definition jsonb; local_result jsonb; result_standard jsonb := '{}'::jsonb; result_custom jsonb := '{}'::jsonb; result jsonb := '{"error": null, "result": null}'::jsonb; converted_value numeric; BEGIN IF all_mode = 'standard'
OR all_mode = 'all' THEN from_definition := definitions -> from_unit;
FOR unit_key IN
SELECT key,
       value
FROM jsonb_each(definitions) LOOP -- unit_key is definition from definitions.
 IF unit_key.value -> 'bulkDensity' THEN -- to is volume
 IF from_definition -> 'bulkDensity' THEN -- from is volume too
 converted_value := quantity * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric; local_result := jsonb_build_object('fromUnitName', from_unit, 'toUnitName', unit_key.key, 'value', quantity, 'equivalentValue', converted_value); ELSE -- from is mass
 converted_value := quantity * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric / (unit_key.value->>'bulkDensity')::numeric; local_result := jsonb_build_object('fromUnitName', from_unit, 'toUnitName', unit_key.key, 'value', quantity, 'equivalentValue', converted_value); END IF; ELSE -- to is mass
 IF from_definition -> 'bulkDensity' THEN -- from is volume
 converted_value := quantity * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric * (from_unit_bulk_density)::numeric; local_result := jsonb_build_object('fromUnitName', from_unit, 'toUnitName', unit_key.key, 'value', quantity, 'equivalentValue', converted_value); ELSE -- from is mass too
 converted_value := quantity * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric; local_result := jsonb_build_object('fromUnitName', from_unit, 'toUnitName', unit_key.key, 'value', quantity, 'equivalentValue', converted_value); END IF; END IF; result_standard := result_standard || jsonb_build_object(unit_key.key, local_result); END LOOP; END IF; IF all_mode = 'custom'
OR all_mode = 'all' THEN
FOR custom_unit_key IN EXECUTE format($$SELECT
          "inputUnitName" input_unit,
          "outputUnitName" output_unit,
          "conversionFactor" conversion_factor,
          "unitConversionId" unit_conversion_id
        FROM %I.%I
        INNER JOIN master."unitConversion"
        ON "unitConversionId" = "unitConversion".id
        WHERE "entityId" = (%s)::integer;$$, schemaname, tablename, entity_id) LOOP
SELECT data
FROM inventory.standard_to_custom_unit_converter(quantity, from_unit, from_bulk_density, custom_unit_key.input_unit, (1)::numeric, custom_unit_key.unit_conversion_id) INTO local_result; result_custom := result_custom || jsonb_build_object(custom_unit_key.input_unit, local_result); END LOOP; END IF; result := jsonb_build_object('result', jsonb_build_object('standard', result_standard, 'custom', result_custom), 'error', 'null'::jsonb); RETURN QUERY
SELECT 1 AS id,
       result as data; END; $_$;


CREATE FUNCTION inventory.standard_to_custom_unit_converter(quantity numeric, from_unit text, from_bulk_density numeric, to_unit text, to_unit_bulk_density numeric, unit_conversion_id integer) RETURNS
SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $$
DECLARE
result jsonb := '{"error": null, "result": null}'::jsonb;
custom_rule record;
converted_standard jsonb;
BEGIN
  -- unit_to_id is the id of a custom rule in master."unitConversion"
  SELECT "inputUnitName" input_unit, "outputUnitName" output_unit, "conversionFactor" conversion_factor
    FROM master."unitConversion"
    WHERE id = unit_conversion_id
    into custom_rule;
  IF custom_rule IS NOT NULL THEN
    SELECT data FROM inventory.standard_to_standard_unit_converter(
      quantity,
      from_unit,
      from_bulk_density,
      custom_rule.output_unit,
      to_unit_bulk_density,
      '', -- schemaname
      '', -- tablename
      0 -- entity id
    ) into converted_standard;
    result := jsonb_build_object(
      'error',
      'null'::jsonb,
      'result',
      jsonb_build_object(
        'fromUnitName',
        from_unit,
        'toUnitName',
        custom_rule.input_unit,
        'value',
        quantity,
        'equivalentValue',
        (converted_standard->'result'->'standard'->custom_rule.output_unit->>'equivalentValue')::numeric / custom_rule.conversion_factor
    ));
  ELSE
    -- costruct an error msg
    result :=
      format(
        '{"error": "no custom unit is defined with the id: %s and name: %s, create a conversion rule in the master.\"unitConversion\" table."}',
        unit_conversion_id,
        to_unit
      )::jsonb;
  END IF;
  RETURN QUERY
  SELECT
    1 AS id,
    result as data;
END;
$$;


CREATE FUNCTION inventory.standard_to_standard_unit_converter(quantity numeric, from_unit text, from_bulk_density numeric, to_unit text, to_unit_bulk_density numeric, schemaname text, tablename text, entity_id integer, all_mode text DEFAULT 'all'::text) RETURNS
SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $_$ DECLARE definitions jsonb := $${"kg":{"name":{"abbr":"kg","singular":"Kilogram","plural":"Kilograms"},"base":"g","factor":1000},
                        "g":{"name":{"abbr":"g","singular":"Gram","plural":"Grams"},"base":"g","factor":1},
                        "mg":{"name":{"abbr":"mg","singular":"Miligram","plural":"MiliGrams"},"base":"g","factor":0.001},
                        "oz":{"name":{"abbr":"oz","singular":"Ounce","plural":"Ounces"},"base":"g","factor":28.3495},
                        "l":{"name":{"abbr":"l","singular":"Litre","plural":"Litres"},"base":"ml","factor":1000,"bulkDensity":1},
                        "ml":{"name":{"abbr":"ml","singular":"Millilitre","plural":"Millilitres"},"base":"ml","factor":1,"bulkDensity":1}
                        }$$; unit_key record; from_definition jsonb; to_definition jsonb; local_result jsonb; result_standard jsonb := '{}'::jsonb; result jsonb := '{"error": null, "result": null}'::jsonb; converted_value numeric; BEGIN -- 1. get the from definition of this unit;
 from_definition := definitions -> from_unit; -- gql forces the value of uni_to, passing '' should work.
 IF to_unit = ''
OR to_unit IS NULL THEN -- to_unit is '', convert to all (standard to custom)

SELECT data
from inventory.standard_to_all_converter(quantity, from_unit, from_bulk_density, schemaname, tablename, entity_id, all_mode) INTO result; ELSE to_definition := definitions -> to_unit; IF to_definition -> 'bulkDensity' THEN -- to is volume
 IF from_definition -> 'bulkDensity' THEN -- from is volume too
 -- ignore bulkDensity as they should be same in volume to volume of same entity.
 converted_value := quantity * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric; local_result := jsonb_build_object('fromUnitName', from_unit, 'toUnitName', to_definition->'name'->>'abbr', 'value', quantity, 'equivalentValue', converted_value); ELSE -- from is mass
 converted_value := quantity * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric / (to_unit_bulk_density)::numeric; local_result := jsonb_build_object('fromUnitName', from_unit, 'toUnitName', to_definition->'name'->>'abbr', 'value', quantity, 'equivalentValue', converted_value); END IF; ELSE -- to is mass
 IF from_definition -> 'bulkDensity' THEN -- from is volume
 converted_value := quantity * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric * (from_bulk_density)::numeric; local_result := jsonb_build_object('fromUnitName', from_unit, 'toUnitName', to_definition->'name'->>'abbr', 'value', quantity, 'equivalentValue', converted_value); ELSE -- from is mass too
 converted_value := quantity * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric; local_result := jsonb_build_object('fromUnitName', from_unit, 'toUnitName', to_definition->'name'->>'abbr', 'value', quantity, 'equivalentValue', converted_value); END IF; END IF; result_standard := result_standard || jsonb_build_object(to_definition->'name'->>'abbr', local_result); result := jsonb_build_object('result', jsonb_build_object('standard', result_standard), 'error', 'null'::jsonb); END IF; RETURN QUERY
SELECT 1 AS id,
       result as data; END; $_$;


CREATE FUNCTION inventory."unitVariationFunc"(quantity numeric, unit text DEFAULT NULL::text,
                                                                                  bulkdensity numeric DEFAULT 1,
                                                                                                              unitto text DEFAULT NULL::text,
                                                                                                                                  unit_id integer DEFAULT NULL::integer) RETURNS
SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $_$ DECLARE definitions jsonb := $${"kg":{"name":{"abbr":"kg","singular":"Kilogram","plural":"Kilograms"},"base":"g","factor":1000},
                        "g":{"name":{"abbr":"g","singular":"Gram","plural":"Grams"},"base":"g","factor":1},
                        "mg":{"name":{"abbr":"mg","singular":"Miligram","plural":"MiliGrams"},"base":"g","factor":0.001},
                        "oz":{"name":{"abbr":"oz","singular":"Ounce","plural":"Ounces"},"base":"g","factor":28.3495},
                        "l":{"name":{"abbr":"l","singular":"Litre","plural":"Litres"},"base":"ml","factor":1000,"bulkDensity":1},
                        "ml":{"name":{"abbr":"ml","singular":"Millilitre","plural":"Millilitres"},"base":"ml","factor":1,"bulkDensity":1}
                        }$$; known_units text[] := '{kg, g, mg, oz, l, ml}'; unit_key record; from_definition jsonb; to_definition jsonb; local_result jsonb; result_standard jsonb := '{}'::jsonb; result jsonb := '{"error": null, "result": null}'::jsonb; converted_value numeric; BEGIN IF unit = ANY(known_units) THEN -- 1. get the from definition of this unit;
 from_definition := definitions -> unit; -- gql forces the value of unitTo, passing '' should work.
 IF unitTo IS NULL
OR unitTo = '' THEN
FOR unit_key IN
SELECT key,
       value
FROM jsonb_each(definitions) LOOP -- unit_key is definition from definitions.
 IF unit_key.value -> 'bulkDensity' THEN -- to is volume
 IF from_definition -> 'bulkDensity' THEN -- from is volume too
 converted_value := quantity * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric; local_result := jsonb_build_object('fromUnitName', unit, 'toUnitName', unit_key.key, 'value', quantity, 'equivalentValue', converted_value); ELSE -- from is mass
 converted_value := quantity * (unit_key.value->>'bulkDensity')::numeric * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric; local_result := jsonb_build_object('fromUnitName', unit, 'toUnitName', unit_key.key, 'value', quantity, 'equivalentValue', converted_value); END IF; ELSE -- to is mass
 IF from_definition -> 'bulkDensity' THEN -- from is volume
 converted_value := quantity * (from_definition->>'bulkDensity')::numeric * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric; local_result := jsonb_build_object('fromUnitName', unit, 'toUnitName', unit_key.key, 'value', quantity, 'equivalentValue', converted_value); ELSE -- from is mass too
 converted_value := quantity * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric; local_result := jsonb_build_object('fromUnitName', unit, 'toUnitName', unit_key.key, 'value', quantity, 'equivalentValue', converted_value); END IF; END IF; result_standard := result_standard || jsonb_build_object(unit_key.key, local_result); END LOOP; ELSE -- unitTo is not null
 to_definition := definitions -> unitTo; IF to_definition -> 'bulkDensity' THEN -- to is volume
 IF from_definition -> 'bulkDensity' THEN -- from is volume too
 converted_value := quantity * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric; local_result := jsonb_build_object('fromUnitName', unit, 'toUnitName', to_definition->'name'->>'abbr', 'value', quantity, 'equivalentValue', converted_value); ELSE -- from is mass
 converted_value := quantity * (to_definition->>'bulkDensity')::numeric * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric; local_result := jsonb_build_object('fromUnitName', unit, 'toUnitName', to_definition->'name'->>'abbr', 'value', quantity, 'equivalentValue', converted_value); END IF; ELSE -- to is mass
 IF from_definition -> 'bulkDensity' THEN -- from is volume
 converted_value := quantity * (from_definition->>'bulkDensity')::numeric * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric; local_result := jsonb_build_object('fromUnitName', unit, 'toUnitName', to_definition->'name'->>'abbr', 'value', quantity, 'equivalentValue', converted_value); ELSE -- from is mass too
 converted_value := quantity * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric; local_result := jsonb_build_object('fromUnitName', unit, 'toUnitName', to_definition->'name'->>'abbr', 'value', quantity, 'equivalentValue', converted_value); END IF; END IF; result_standard := result_standard || jsonb_build_object(to_definition->'name'->>'abbr', local_result); END IF; result := jsonb_build_object('result', jsonb_build_object('standard', result_standard), 'error', 'null'::jsonb); ELSE -- @param unit is not in standard_definitions
 IF unit_id IS NULL THEN result := jsonb_build_object('error', 'unit_id must not be null'); ELSE -- check if customConversion is possible with @param unit
 -- inventory."customUnitVariationFunc" also does error handling for us :)
 -- @param unit_id should not be null here
 -- @param unitTo is a standard unit

SELECT data
from inventory."customUnitVariationFunc"(quantity,
                                         unit_id,
                                         unitTo) into result; END IF; END IF; RETURN QUERY
SELECT 1 AS id,
       result as data; END; $_$;


CREATE FUNCTION inventory."unitVariationFunc"(tablename text, quantity numeric, unit text, bulkdensity numeric DEFAULT 1,
                                                                                                                       unitto text DEFAULT NULL::text) RETURNS
SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $_$ DECLARE definitions jsonb := $${"kg":{"name":{"abbr":"kg","singular":"Kilogram","plural":"Kilograms"},"base":"g","factor":1000},
                        "g":{"name":{"abbr":"g","singular":"Gram","plural":"Grams"},"base":"g","factor":1},
                        "mg":{"name":{"abbr":"mg","singular":"Miligram","plural":"MiliGrams"},"base":"g","factor":0.001},
                        "oz":{"name":{"abbr":"oz","singular":"Ounce","plural":"Ounces"},"base":"g","factor":28.3495},
                        "l":{"name":{"abbr":"l","singular":"Litre","plural":"Litres"},"base":"ml","factor":1000,"bulkDensity":1},
                        "ml":{"name":{"abbr":"ml","singular":"Millilitre","plural":"Millilitres"},"base":"ml","factor":1,"bulkDensity":1}
                        }$$; known_units text[] := '{kg, g, mg, oz, l, ml}'; unit_key record; from_definition jsonb; to_definition jsonb; local_result jsonb; result_standard jsonb := '{}'::jsonb; result jsonb := '{"error": null, "result": null}'::jsonb; converted_value numeric; BEGIN IF unit = ANY(known_units) THEN -- 1. get the from definition of this unit;
 from_definition := definitions -> unit; -- gql forces the value of unitTo, passing "" should work.
 IF unitTo IS NULL
OR unitTo = '' THEN
FOR unit_key IN
SELECT key,
       value
FROM jsonb_each(definitions) LOOP -- unit_key is definition from definitions.
 IF unit_key.value -> 'bulkDensity' THEN -- to is volume
 IF from_definition -> 'bulkDensity' THEN -- from is volume too
 converted_value := quantity * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric; local_result := jsonb_build_object('fromUnitName', unit, 'toUnitName', unit_key.key, 'value', quantity, 'equivalentValue', converted_value); ELSE -- from is mass
 converted_value := quantity * (unit_key.value->>'bulkDensity')::numeric * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric; local_result := jsonb_build_object('fromUnitName', unit, 'toUnitName', unit_key.key, 'value', quantity, 'equivalentValue', converted_value); END IF; ELSE -- to is mass
 IF from_definition -> 'bulkDensity' THEN -- from is volume
 converted_value := quantity * (from_definition->>'bulkDensity')::numeric * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric; local_result := jsonb_build_object('fromUnitName', unit, 'toUnitName', unit_key.key, 'value', quantity, 'equivalentValue', converted_value); ELSE -- from is mass too
 converted_value := quantity * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric; local_result := jsonb_build_object('fromUnitName', unit, 'toUnitName', unit_key.key, 'value', quantity, 'equivalentValue', converted_value); END IF; END IF; result_standard := result_standard || jsonb_build_object(unit_key.key, local_result); END LOOP; ELSE -- unitTo is not null
 to_definition := definitions -> unitTo; IF to_definition -> 'bulkDensity' THEN -- to is volume
 IF from_definition -> 'bulkDensity' THEN -- from is volume too
 converted_value := quantity * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric; local_result := jsonb_build_object('fromUnitName', unit, 'toUnitName', to_definition->'name'->>'abbr', 'value', quantity, 'equivalentValue', converted_value); ELSE -- from is mass
 converted_value := quantity * (to_definition->>'bulkDensity')::numeric * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric; local_result := jsonb_build_object('fromUnitName', unit, 'toUnitName', to_definition->'name'->>'abbr', 'value', quantity, 'equivalentValue', converted_value); END IF; ELSE -- to is mass
 IF from_definition -> 'bulkDensity' THEN -- from is volume
 converted_value := quantity * (from_definition->>'bulkDensity')::numeric * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric; local_result := jsonb_build_object('fromUnitName', unit, 'toUnitName', to_definition->'name'->>'abbr', 'value', quantity, 'equivalentValue', converted_value); ELSE -- from is mass too
 converted_value := quantity * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric; local_result := jsonb_build_object('fromUnitName', unit, 'toUnitName', to_definition->'name'->>'abbr', 'value', quantity, 'equivalentValue', converted_value); END IF; END IF; result_standard := result_standard || jsonb_build_object(to_definition->'name'->>'abbr', local_result); END IF; -- TODO: is is_unit_to_custom == true -> handle standard to custom (probably another sql func)
 result := jsonb_build_object('result', jsonb_build_object('standard', result_standard), 'error', 'null'::jsonb); ELSE -- @param unit is not in standard_definitions
 -- check if customConversion is possible with @param unit
 -- inventory."customUnitVariationFunc" also does error handling for us :)

SELECT data
from inventory."customUnitVariationFunc"(quantity,
                                         unit,
                                         unitTo) into result; END IF; RETURN QUERY
SELECT 1 AS id,
       result as data; END; $_$;


CREATE TABLE inventory."supplierItem" ( id integer NOT NULL,
                                                   name text, "unitSize" integer, prices jsonb,
                                                                                  "supplierId" integer, unit text, "leadTime" jsonb,
                                                                                                                   certificates jsonb,
                                                                                                                   "bulkItemAsShippedId" integer, sku text, "importId" integer, "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                   "unitConversionId" integer, "sachetItemAsShippedId" integer);


CREATE FUNCTION inventory.unit_conversions_supplier_item(item inventory."supplierItem", from_unit text, from_unit_bulk_density numeric, quantity numeric, to_unit text, to_unit_bulk_density numeric) RETURNS
SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $_$ DECLARE local_quantity numeric; local_from_unit text; local_from_unit_bulk_density numeric; local_to_unit_bulk_density numeric; known_units text[] := '{kg, g, mg, oz, l, ml}'; result jsonb; custom_to_unit_conversion_id integer; custom_from_unit_conversion_id integer; BEGIN /* setup */ -- resolve quantity
 IF quantity IS NULL
OR quantity = -1 THEN local_quantity := item."unitSize"::numeric; ELSE local_quantity := quantity; END IF; -- resolve from_unit
 IF from_unit IS NULL
OR from_unit = '' THEN local_from_unit := item.unit; ELSE local_from_unit := from_unit; END IF; -- resolve from_unit_bulk_density
 IF from_unit_bulk_density IS NULL
OR from_unit_bulk_density = -1 THEN local_from_unit_bulk_density := item."bulkDensity"; ELSE local_from_unit_bulk_density := from_unit_bulk_density; END IF; -- resolve to_unit_bulk_density
 IF to_unit_bulk_density IS NULL
OR to_unit_bulk_density = -1 THEN local_to_unit_bulk_density := item."bulkDensity"; ELSE local_to_unit_bulk_density := to_unit_bulk_density; END IF; IF to_unit <> ALL(known_units)
AND to_unit != '' THEN EXECUTE format($$SELECT
        "unitConversionId" unit_conversion_id
      FROM %I.%I
      INNER JOIN master."unitConversion"
      ON "unitConversionId" = "unitConversion".id
      WHERE "entityId" = (%s)::integer
      AND "inputUnitName" = '%s';$$, 'inventory', -- schema name
 'supplierItem_unitConversion', -- tablename
 item.id, to_unit) INTO custom_to_unit_conversion_id; END IF; IF local_from_unit <> ALL(known_units) THEN EXECUTE format($$SELECT
        "unitConversionId" unit_conversion_id
      FROM %I.%I
      INNER JOIN master."unitConversion"
      ON "unitConversionId" = "unitConversion".id
      WHERE "entityId" = (%s)::integer
      AND "inputUnitName" = '%s';$$, 'inventory', -- schema name
 'supplierItem_unitConversion', -- tablename
 item.id, local_from_unit) INTO custom_from_unit_conversion_id; END IF; /* end setup */ IF local_from_unit = ANY(known_units) THEN -- local_from_unit is standard
 IF to_unit = ANY(known_units)
OR to_unit = ''
OR to_unit IS NULL THEN -- to_unit is also standard

SELECT data
FROM inventory.standard_to_standard_unit_converter(local_quantity, local_from_unit, local_from_unit_bulk_density, to_unit, local_to_unit_bulk_density, 'inventory', -- schema name
 'supplierItem_unitConversion', -- tablename
 item.id, 'all') INTO result; ELSE -- to_unit is custom and not ''
 -- convert from standard to custom

SELECT data
FROM inventory.standard_to_custom_unit_converter(local_quantity, local_from_unit, local_from_unit_bulk_density, to_unit, local_to_unit_bulk_density, custom_to_unit_conversion_id) INTO result; END IF; ELSE -- local_from_unit is custom
 IF to_unit = ANY(known_units)
OR to_unit = ''
OR to_unit IS NULL THEN -- to_unit is standard

SELECT data
FROM inventory.custom_to_standard_unit_converter(local_quantity, local_from_unit, local_from_unit_bulk_density, to_unit, local_to_unit_bulk_density, custom_from_unit_conversion_id, 'inventory', -- schema name
 'supplierItem_unitConversion', -- tablename
 item.id) INTO result; ELSE -- to_unit is also custom and not ''

SELECT data
FROM inventory.custom_to_custom_unit_converter(local_quantity, local_from_unit, local_from_unit_bulk_density, to_unit, local_to_unit_bulk_density, custom_from_unit_conversion_id, custom_to_unit_conversion_id) INTO result; END IF; END IF; RETURN QUERY
SELECT 1 as id,
       result as data; END; $_$;


CREATE FUNCTION notifications.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;


CREATE TABLE "onDemand".menu ( id integer NOT NULL,
                                          data jsonb);



CREATE FUNCTION "onDemand"."getMenuV2"(params jsonb) RETURNS
SETOF "onDemand".menu LANGUAGE plpgsql STABLE AS $$
DECLARE
    colId int;
    idArr int[];
    menu jsonb[] := '{}';
    object jsonb;
    isValid jsonb;
    category jsonb;
    productCategory record;
    rec record;
    cleanMenu jsonb[] := '{}'; -- without duplicates
    cleanCategory jsonb; -- without duplicates
    categoriesIncluded text[];
    productsIncluded int[];
    updatedProducts int[];
    productId int;
    pos int := 0;
BEGIN
    -- generating menu data from collections
    FOR colId IN SELECT "collectionId" FROM "onDemand"."brand_collection" WHERE "brandId" = (params->>'brandId')::int AND "isActive" = true LOOP
        SELECT "onDemand"."isCollectionValid"(colId, params) INTO isValid;
        IF (isValid->'status')::boolean = true THEN
            FOR productCategory IN SELECT * FROM "onDemand"."collection_productCategory" WHERE "collectionId" = colId ORDER BY position DESC NULLS LAST LOOP
                idArr := '{}'::int[];
                FOR rec IN SELECT * FROM "onDemand"."collection_productCategory_product" WHERE "collection_productCategoryId" = productCategory.id ORDER BY position DESC NULLS LAST LOOP
                    idArr := idArr || rec."productId";
                END LOOP;
                category := jsonb_build_object(
                    'name', productCategory."productCategoryName",
                    'products', idArr
                );
                menu := menu || category;
            END LOOP;
        ELSE
            CONTINUE;
        END IF;
    END LOOP;
    -- merge duplicate categories and remove duplicate products
    FOREACH category IN ARRAY(menu) LOOP
        pos := ARRAY_POSITION(categoriesIncluded, category->>'name');
        IF pos >= 0 THEN
            updatedProducts := '{}'::int[];
            productsIncluded := '{}'::int[];
            FOR productId IN SELECT * FROM JSONB_ARRAY_ELEMENTS(cleanMenu[pos]->'products') LOOP
                updatedProducts := updatedProducts || productId;
                productsIncluded := productsIncluded || productId; -- wil remove same products under same category in different collections
            END LOOP;
            FOR productId IN SELECT * FROM JSONB_ARRAY_ELEMENTS(category->'products') LOOP
                IF ARRAY_POSITION(productsIncluded, productId) >= 0 THEN
                    CONTINUE;
                ELSE
                   updatedProducts := updatedProducts || productId;
                   productsIncluded := productsIncluded || productId; -- will remove same products under same category in same collection
                END IF;
            END LOOP;
            cleanMenu[pos] := jsonb_build_object('name', category->>'name', 'products', updatedProducts);
        ELSE
            cleanMenu := cleanMenu || category;
            categoriesIncluded := categoriesIncluded || (category->>'name')::text;
        END IF;
    END LOOP;
    RETURN QUERY SELECT 1 AS id, jsonb_build_object('menu', cleanMenu) AS data;
END;
$$;



CREATE TABLE "onDemand"."collection_productCategory_product" ( "collection_productCategoryId" integer NOT NULL,
                                                                                                      id integer NOT NULL,
                                                                                                                 "position" numeric, "importHistoryId" integer, "productId" integer NOT NULL);




CREATE TABLE "onDemand"."storeData" ( id integer NOT NULL,
                                                 "brandId" integer, settings jsonb);


CREATE FUNCTION "onDemand"."getStoreData"(requestdomain text) RETURNS
SETOF "onDemand"."storeData" LANGUAGE plpgsql STABLE AS $$
DECLARE
    brandId int;
    settings jsonb;
BEGIN
    SELECT id FROM brands.brand WHERE "domain" = requestDomain INTO brandId;
    IF brandId IS NULL THEN
        SELECT id FROM brands.brand WHERE "isDefault" = true INTO brandId;
    END IF;
    SELECT brands."getSettings"(brandId) INTO settings;
    RETURN QUERY SELECT 1 AS id, brandId AS brandId, settings as settings;
END;
$$;


CREATE FUNCTION "onDemand"."isCollectionValid"(collectionid integer, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE TABLE "onDemand"."modifierCategoryOption" ( id integer NOT NULL,
                                                              name text NOT NULL,
                                                                        "originalName" text NOT NULL,
                                                                                            price numeric DEFAULT 0 NOT NULL,
                                                                                                                    discount numeric DEFAULT 0 NOT NULL,
                                                                                                                                               quantity integer DEFAULT 1 NOT NULL,
                                                                                                                                                                          image text, "isActive" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                      "isVisible" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                       "operationConfigId" integer, "modifierCategoryId" integer NOT NULL,
                                                                                                                                                                                                                                                                                                                 "sachetItemId" integer, "supplierItemId" integer, "ingredientSachetId" integer);


CREATE FUNCTION "onDemand"."modifierCategoryOptionCartItem"(option "onDemand"."modifierCategoryOption") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    counter int;
    items jsonb[] := '{}';
BEGIN
    counter := option.quantity;
    IF option."sachetItemId" IS NOT NULL THEN
        WHILE counter >= 1 LOOP
            items := items || jsonb_build_object('sachetItemId', option."sachetItemId", 'modifierOptionId', option.id);
            counter := counter - 1;
        END LOOP;
    ELSEIF option."supplierItemId" IS NOT NULL THEN
        WHILE counter >= 1 LOOP
            items := items || jsonb_build_object('supplierItemId', option."supplierItemId", 'modifierOptionId', option.id);
            counter := counter - 1;
        END LOOP;
    ELSEIF option."ingredientSachetId" IS NOT NULL THEN
        WHILE counter >= 1 LOOP
            items := items || jsonb_build_object('ingredientSachetId', option."ingredientSachetId", 'modifierOptionId', option.id);
            counter := counter - 1;
        END LOOP;
    ELSE
        items := items;
    END IF;
    RETURN jsonb_build_object('data', items);
END;
$$;


CREATE FUNCTION "onDemand"."numberOfCategories"(colid integer) RETURNS integer LANGUAGE plpgsql STABLE AS $$
DECLARE
    res int;
BEGIN
    SELECT COUNT(*) FROM "onDemand"."collection_productCategory" WHERE "collectionId" = colId INTO res;
    RETURN res;
END;
$$;


CREATE FUNCTION "onDemand"."numberOfProducts"(colid integer) RETURNS integer LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION "onDemand".set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;




CREATE TABLE "onDemand".collection ( id integer NOT NULL,
                                                name text, "startTime" time without time zone,
                                                                                         "endTime" time without time zone,
                                                                                                                     rrule jsonb,
                                                                                                                     created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                 updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                             "importHistoryId" integer);












CREATE TABLE "order".cart ( id integer NOT NULL,
                                       "paidPrice" numeric DEFAULT 0 NOT NULL,
                                                                     "customerId" integer NOT NULL,
                                                                                          "paymentStatus" text DEFAULT 'PENDING'::text NOT NULL,
                                                                                                                                       status text DEFAULT 'CART_PENDING'::text NOT NULL,
                                                                                                                                                                                "paymentMethodId" text, "transactionId" text, "stripeCustomerId" text, "fulfillmentInfo" jsonb,
                                                                                                                                                                                                                                                       tip numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                             address jsonb,
                                                                                                                                                                                                                                                                             "customerInfo" jsonb,
                                                                                                                                                                                                                                                                             source text DEFAULT 'a-la-carte'::text NOT NULL,
                                                                                                                                                                                                                                                                                                                    "subscriptionOccurenceId" integer, "walletAmountUsed" numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                            "isTest" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                           "brandId" integer DEFAULT 1 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                       "couponDiscount" numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          "loyaltyPointsUsed" integer DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                "paymentId" uuid,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                "paymentUpdatedAt" timestamp with time zone,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       "paymentRequestInfo" jsonb,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           "customerKeycloakId" text, "orderId" integer, amount numeric DEFAULT 0);


CREATE TABLE products."customizableProductComponent" ( id integer NOT NULL,
                                                                  created_at timestamp with time zone DEFAULT now(),
                                                                                                              updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                          "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                             options jsonb DEFAULT '[]'::jsonb NOT NULL,
                                                                                                                                                                                                                               "position" numeric, "productId" integer, "linkedProductId" integer);


CREATE VIEW products."customizableComponentOptions" AS
SELECT t.id AS "customizableComponentId",
       t."linkedProductId",
       ((option.value ->> 'optionId'::text))::integer AS "productOptionId",
       ((option.value ->> 'price'::text))::numeric AS price,
       ((option.value ->> 'discount'::text))::numeric AS discount,
       t."productId"
FROM products."customizableProductComponent" t,
     LATERAL jsonb_array_elements(t.options) option(value);


CREATE FUNCTION products."comboProductComponentCustomizableCartItem"(componentoption products."customizableComponentOptions") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    counter int;
    items jsonb[] := '{}';
    product record;
    option record;
BEGIN
    SELECT * FROM products.product WHERE id = componentOption."productId" INTO product;
    SELECT * FROM products."productOption" WHERE id = componentOption."productOptionId" INTO option;
    counter := option.quantity;
    IF option."simpleRecipeYieldId" IS NOT NULL THEN
        WHILE counter >= 1 LOOP
            items := items || json_build_object('simpleRecipeYieldId', option."simpleRecipeYieldId")::jsonb;
            counter := counter - 1;
        END LOOP;
    ELSEIF option."inventoryProductBundleId" IS NOT NULL THEN
        WHILE counter >= 1 LOOP
            items := items || json_build_object('inventoryProductBundleId', option."inventoryProductBundleId")::jsonb;
            counter := counter - 1;
        END LOOP;
    END IF;
    RETURN jsonb_build_object(
        'customizableProductComponentId', componentOption."customizableComponentId",
        'productOptionId', componentOption."productOptionId",
        'unitPrice', componentOption.price,
        'childs', json_build_object(
            'data', items
        )
    );
END;
$$;


CREATE TABLE "order"."order" ( id oid NOT NULL,
                                      "deliveryInfo" jsonb,
                                      created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                        tax double precision, discount numeric DEFAULT 0 NOT NULL,
                                                                                                                                         "itemTotal" numeric, "deliveryPrice" numeric, currency text DEFAULT 'usd'::text,
                                                                                                                                                                                                             updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                         tip numeric, "amountPaid" numeric, "fulfillmentType" text, "deliveryPartnershipId" integer, "cartId" integer, "isRejected" boolean, "isAccepted" boolean, "thirdPartyOrderId" integer, "readyByTimestamp" timestamp without time zone,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          "fulfillmentTimestamp" timestamp without time zone,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        "keycloakId" text, "brandId" integer);


CREATE TABLE products."comboProductComponent" (id integer NOT NULL,
                                                          label text NOT NULL,
                                                                     created_at timestamp with time zone DEFAULT now(),
                                                                                                                 updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                             "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                options jsonb DEFAULT '[]'::jsonb NOT NULL,
                                                                                                                                                                                                                                  "position" numeric, "productId" integer, "linkedProductId" integer);

CREATE TABLE products.product ( id integer NOT NULL,
                                           name text, "additionalText" text, description text, assets jsonb DEFAULT jsonb_build_object('images', '[]'::jsonb, 'videos', '[]'::jsonb) NOT NULL,
                                                                                                                                                                                     "isPublished" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                         "isPopupAllowed" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                               "defaultProductOptionId" integer, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                             updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                                                                         tags jsonb,
                                                                                                                                                                                                                                                                                                                                                                                         "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                            type text DEFAULT 'simple'::text NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                             price numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     discount numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                "importHistoryId" integer);

CREATE TABLE products."productOption" ( id integer NOT NULL,
                                                   "productId" integer NOT NULL,
                                                                       label text DEFAULT 'Basic'::text NOT NULL,
                                                                                                        "modifierId" integer, "operationConfigId" integer, "simpleRecipeYieldId" integer, "supplierItemId" integer, "sachetItemId" integer, "position" numeric, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                            updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                                        price numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                discount numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                           quantity integer DEFAULT 1 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                      type text, "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    "inventoryProductBundleId" integer);

CREATE TABLE rules.conditions ( id integer NOT NULL,
                                           condition jsonb NOT NULL,
                                                           app text);



CREATE TABLE settings."operationConfig" ( id integer NOT NULL,
                                                     "stationId" integer, "labelTemplateId" integer, created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                       updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                         "packagingId" integer);

CREATE TABLE "simpleRecipe"."simpleRecipeYield" ( id integer NOT NULL,
                                                             "simpleRecipeId" integer NOT NULL,
                                                                                      yield jsonb NOT NULL,
                                                                                                  "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                     quantity numeric, unit text, serving numeric);


CREATE TABLE subscription."subscriptionOccurence_addOn" ( id integer NOT NULL,
                                                                     "subscriptionOccurenceId" integer, "unitPrice" numeric NOT NULL,
                                                                                                                            "productCategory" text, "isAvailable" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                       "isVisible" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                        "isSingleSelect" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                               "subscriptionId" integer, "productOptionId" integer NOT NULL,
                                                                                                                                                                                                                                                                                                                   created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                     updated_at timestamp with time zone DEFAULT now() NOT NULL);



CREATE TABLE subscription."subscriptionOccurence" ( id integer NOT NULL,
                                                               "fulfillmentDate" date NOT NULL,
                                                                                      "cutoffTimeStamp" timestamp without time zone NOT NULL,
                                                                                                                                    "subscriptionId" integer NOT NULL,
                                                                                                                                                             "startTimeStamp" timestamp without time zone,
                                                                                                                                                                                                     assets jsonb,
                                                                                                                                                                                                     "subscriptionAutoSelectOption" text);
CREATE OR REPLACE FUNCTION products."productOptionCartItem"(option products."productOption") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    counter int;
    items jsonb[] := '{}';
    product products."product";
BEGIN
    SELECT * FROM products.product WHERE id = option."productId" INTO product;
    counter := option.quantity;
    IF option."simpleRecipeYieldId" IS NOT NULL THEN
        WHILE counter >= 1 LOOP
            items := items || json_build_object('simpleRecipeYieldId', option."simpleRecipeYieldId")::jsonb;
            counter := counter - 1;
        END LOOP;
    ELSEIF option."inventoryProductBundleId" IS NOT NULL THEN
        WHILE counter >= 1 LOOP
            items := items || json_build_object('inventoryProductBundleId', option."inventoryProductBundleId")::jsonb;
            counter := counter - 1;
        END LOOP;
    END IF;
    RETURN json_build_object(
        'productId', product.id,
        'unitPrice', product.price,
        'childs', jsonb_build_object(
            'data', json_build_array(
                json_build_object (
                    'productOptionId', option.id,
                    'unitPrice', option.price,
                    'childs', json_build_object(
                        'data', items
                    )
                )
            )
        )
    );
END;
$$;


CREATE OR REPLACE FUNCTION products.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;


CREATE OR REPLACE FUNCTION products."unpublishProduct"(producttype text, productid integer) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    query text;
BEGIN
    query := 'UPDATE products.' || '"' || productType || '"' || ' SET "isPublished" = false WHERE id = ' || productId;
    EXECUTE query;
END
$$;


CREATE or replace FUNCTION public.call(text) RETURNS jsonb LANGUAGE plpgsql AS $_$ DECLARE res jsonb; BEGIN EXECUTE $1 INTO res; RETURN res; END; $_$;


CREATE or replace FUNCTION public.image_validity(ing ingredient.ingredient) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT NOT(ing.image IS NULL)
$$;


CREATE or replace FUNCTION public.json_to_array(json) RETURNS text[] LANGUAGE sql IMMUTABLE AS $_$
SELECT coalesce(array_agg(x),
                CASE
                    WHEN $1 is null THEN null
                    ELSE ARRAY[]::text[]
                END)
FROM json_array_elements_text($1) t(x); $_$;


CREATE or replace FUNCTION public.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;


CREATE OR REPLACE FUNCTION rules."assertFact"(condition jsonb,
                                   params jsonb) RETURNS boolean LANGUAGE plpgsql STABLE AS $$
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


CREATE OR REPLACE FUNCTION rules."budgetFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    typeof text ;
    total numeric := 0;
    campaignRecord record;
    campIds integer array DEFAULT '{}';
    queryParams jsonb default '{}'::jsonb ;
    endDate timestamp without time zone;
    startDate timestamp without time zone ;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
    query text :='';
BEGIN
    IF params->'read'
        THEN RETURN jsonb_build_object('id', 'budget', 'fact', 'budget', 'title', 'Budget', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{ comboProducts { id title: name } }" }'::json, 'argument','couponId', 'operators', operators);
    END IF;
    query := query || 'SELECT ' || (params->>'type')::text || '(' || '"'|| (params->>'rewardType')::text || '"' || ')' || ' FROM crm."rewardHistory" WHERE ';
    IF (params->'perCustomer')::boolean = true THEN
        query := query || '"keycloakId" = ' || '''' || (params->>'keycloakId')::text|| '''' || ' AND ';
    END IF;
    IF params->>'coverage' = 'Only This' THEN
        IF params->>'couponId' IS NOT NULL THEN
            query := query || ' "couponId" = ' || (params->>'couponId')::text ||'AND';
        ELSIF params->>'campaignId' IS NOT NULL THEN
            query := query || ' "campaignId" = ' || (params->>'campaignId')::text||'AND';
        ELSE
            query := query;
        END IF;
     ELSEIF params->>'coverage'='Sign Up' OR params->>'coverage'='Post Order' OR params->>'coverage'='Referral' THEN
        FOR campaignRecord IN
            SELECT * FROM crm."campaign" WHERE "type" = (params->>'coverage')::text
        LOOP
            campIds := campIds || (campaignRecord."id")::int;
        END LOOP;
            query := query || ' "campaignId" IN ' || '(' || array_to_string(campIds, ',') || ')'  ||'AND';
    ELSEIF params->>'coverage' = 'coupons' THEN
        query := query || ' "couponId" IS NOT NULL AND';
    ELSEIF params->>'coverage' = 'campaigns' THEN
        query := query || ' "campaignId" IS NOT NULL AND';
    ELSE
        query := query;
    END IF;
    IF (params->>'duration')::interval IS NOT NULL THEN
        endDate := now()::timestamp without time zone;
        startDate := endDate - (params->>'duration')::interval;
        query := query || ' "created_at" > ' || '''' || startDate || '''' || 'AND "created_at" < ' || '''' || endDate::timestamp without time zone ||'''' ;
    ELSE
        query :=query;
    END IF;
    EXECUTE query INTO total;
    RETURN jsonb_build_object((params->>'type')::text, total, 'query', query);
END;
$$;


CREATE OR REPLACE FUNCTION rules."cartComboProduct"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartItem" record;
    productType text;
    productIdArray integer array DEFAULT '{}';
    productId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartComboProduct', 'fact', 'cartComboProduct', 'title', 'Cart Contains Combo Product', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{ products(where: {type: {_eq: \"combo\"}}) { id title: name } }" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartItem" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        Select "type" from "products"."product" where "id" = "cartItem"."productId" into productType;
            IF productType = 'combo'
             THEN SELECT "cartItem"."productId" INTO productId;
              productIdArray = productIdArray || productId;
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', productIdArray, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;


CREATE OR REPLACE FUNCTION rules."cartComboProductComponent"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartProduct" record;
    productType text;
    productIdArray integer array DEFAULT '{}';
    productId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartComboProduct', 'fact', 'cartComboProduct', 'title', 'Cart Contains Combo Product Component', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{  comboProductComponents { id } }" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartProduct" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        Select "type" from "products"."product" where "id" = "cartProduct"."productId" into productType;
            IF productType = 'combo'
             THEN SELECT "comboProductComponentId" from "order"."cartItem" where "parentCartItemId" = "cartProduct"."id" into productId;
              productIdArray = productIdArray || productId;
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', productIdArray, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;


CREATE OR REPLACE FUNCTION rules."cartCustomizableProduct"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartItem" record;
    productType text;
    productIdArray integer array DEFAULT '{}';
    productId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartCustomizableProduct', 'fact', 'cartCustomizableProduct', 'title', 'Cart Contains Customizable Product', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{ products(where: {type: {_eq: \"customizable\"}}) { id title: name } }" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartItem" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        Select "type" from "products"."product" where "id" = "cartItem"."productId" into productType;
            IF productType = 'customizable'
             THEN SELECT "cartItem"."productId" INTO productId;
              productIdArray = productIdArray || productId;
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', productIdArray, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;


CREATE OR REPLACE FUNCTION rules."cartCustomizableProductComponent"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartProduct" record;
    productType text;
    productIdArray integer array DEFAULT '{}';
    productId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartCustomizableProduct', 'fact', 'cartCustomizableProduct', 'title', 'Cart Contains Combo Product', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{  CustomizableProductComponents { id } }" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartProduct" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        Select "type" from "products"."product" where "id" = "cartProduct"."productId" into productType;
            IF productType = 'combo'
             THEN SELECT "CustomizableProductComponentId" from "order"."cartItem" where "parentCartItemId" = "cartProduct"."id" into productId;
              productIdArray = productIdArray || productId;
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', productIdArray, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;


CREATE OR REPLACE FUNCTION rules."cartInventoryProductOption"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartProduct" record;
    productOptionType text;
    productOptionIdArray integer array DEFAULT '{}';
    productOptionId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartInventoryProductOption', 'fact', 'cartInventoryProductOption', 'title', 'Cart Contains Inventory Product Option', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{  productOptions (where: {type: {_eq: \"inventory\"}}) { id } }" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartProduct" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        select "productOptionId" from "order"."cartItem" where "parentCartItemId" = "cartProduct"."id" into productOptionId;
            SELECT "type" from "products"."productOption" where "id" = productOptionId into productOptionType;
            IF productOptionType = 'inventory' then
              productOptionIdArray = productOptionIdArray || productOptionId;
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', productOptionIdArray, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;


CREATE OR REPLACE FUNCTION rules."cartItemTotal"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartItemTotal', 'fact', 'cartItemTotal', 'title', 'Cart Item Total', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        RETURN json_build_object('value', COALESCE((SELECT SUM("unitPrice") FROM "order"."cartItem" WHERE "cartId" = (params->>'cartId')::integer), 0), 'valueType','numeric','arguments','cartId');
    END IF;
END;
$$;


CREATE OR REPLACE FUNCTION rules."cartItemTotalFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    total numeric;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartItemTotal', 'fact', 'cartItemTotal', 'title', 'Cart Item Total', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
  total := COALESCE((SELECT SUM("unitPrice") INTO total FROM "order"."cartItem" WHERE id = (params->>'cartId')::integer), 0);
        RETURN json_build_object('value', total, 'valueType','numeric','arguments','cartId');
    END IF;
END;
$$;


CREATE OR REPLACE FUNCTION rules."cartMealKitProductOption"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartProduct" record;
    productOptionType text;
    productOptionIdArray integer array DEFAULT '{}';
    productOptionId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartMealKitProductOption', 'fact', 'cartMealKitProductOption', 'title', 'Cart Contains Meal Kit Product Option', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{  productOptions (where: {type: {_eq: \"mealKit\"}}) { id } }" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartProduct" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        select "productOptionId" from "order"."cartItem" where "parentCartItemId" = "cartProduct"."id" into productOptionId;
            SELECT "type" from "products"."productOption" where "id" = productOptionId into productOptionType;
            IF productOptionType = 'mealKit' then
              productOptionIdArray = productOptionIdArray || productOptionId;
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', productOptionIdArray, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;


CREATE OR REPLACE FUNCTION rules."cartReadyToEatProductOption"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartProduct" record;
    productOptionType text;
    productOptionIdArray integer array DEFAULT '{}';
    productOptionId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartReadyToEatProductOption', 'fact', 'cartReadyToEatProductOption', 'title', 'Cart Contains Ready to Eat Product Option', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{  productOptions (where: {type: {_eq: \"readyToEat\"}}) { id } }" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartProduct" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        select "productOptionId" from "order"."cartItem" where "parentCartItemId" = "cartProduct"."id" into productOptionId;
            SELECT "type" from "products"."productOption" where "id" = productOptionId into productOptionType;
            IF productOptionType = 'readyToEat' then
              productOptionIdArray = productOptionIdArray || productOptionId;
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', productOptionIdArray, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;


CREATE OR REPLACE FUNCTION rules."cartSimpleProduct"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartItem" record;
    productType text;
    productIdArray integer array DEFAULT '{}';
    productId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartSimpleProduct', 'fact', 'cartSimpleProduct', 'title', 'Cart Contains Simple Product', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{ products(where: {type: {_eq: \"simple\"}}) { id title: name } }" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartItem" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        Select "type" from "products"."product" where "id" = "cartItem"."productId" into productType;
            IF productType = 'simple'
             THEN SELECT "cartItem"."productId" INTO productId;
              productIdArray = productIdArray || productId;
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', productIdArray, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;


CREATE OR REPLACE FUNCTION rules."checkAllConditions"(conditionarray jsonb,
                                           params jsonb) RETURNS boolean LANGUAGE plpgsql STABLE AS $$
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


CREATE OR REPLACE FUNCTION rules."checkAnyConditions"(conditionarray jsonb,
                                           params jsonb) RETURNS boolean LANGUAGE plpgsql STABLE AS $$
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


CREATE OR REPLACE FUNCTION rules."getFactValue"(fact text, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN call('SELECT rules."' || fact || 'Func"' || '(' || '''' || params || '''' || ')');
END;
$$;


CREATE OR REPLACE FUNCTION rules."isConditionValid"(condition rules.conditions,
                                         params jsonb) RETURNS boolean LANGUAGE plpgsql STABLE AS $$
DECLARE
    res boolean;
    x int;
BEGIN
    IF params IS NULL THEN
        RETURN false;
    END IF;
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


CREATE OR REPLACE FUNCTION rules."isConditionValidFunc"(conditionid integer, params jsonb) RETURNS boolean LANGUAGE plpgsql STABLE AS $$
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


CREATE OR REPLACE FUNCTION rules."rruleHasDateFunc"(rrule _rrule.rruleset,
                                         d timestamp without time zone) RETURNS boolean LANGUAGE plpgsql STABLE AS $$
DECLARE
    res boolean;
BEGIN
  SELECT rrule @> d into res;
  RETURN res;
END;
$$;


CREATE OR REPLACE FUNCTION rules."runWithOperator"(
                                        operator text, vals jsonb) RETURNS boolean LANGUAGE plpgsql STABLE AS $$
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


CREATE OR REPLACE FUNCTION rules."totalNumberOfCartComboProduct"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartItem" record;
    productType text;
    productIdArray integer array DEFAULT '{}';
    productId integer;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'totalNumberOfComboProducts', 'fact', 'totalNumberOfComboProducts', 'title', 'Total Number Of Combo Products (with Quantity)', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartItem" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        Select "type" from "products"."product" where "id" = "cartItem"."productId" into productType;
            IF productType = 'combo'
             THEN SELECT "cartItem"."productId" INTO productId;
              productIdArray = productIdArray || productId;
            END IF;
        END LOOP;
        RETURN json_build_object('value', coalesce(array_length(productIdArray, 1), 0) , 'valueType','integer','argument','cartid');
    END IF;
END;
$$;


CREATE OR REPLACE FUNCTION rules."totalNumberOfCartCustomizableProduct"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartItem" record;
    productType text;
    productIdArray integer array DEFAULT '{}';
    productId integer;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'totalNumberOfCustomizableProducts', 'fact', 'totalNumberOfCustomizableProducts', 'title', 'Total Number Of Customizable Products (with Quantity)', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartItem" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        Select "type" from "products"."product" where "id" = "cartItem"."productId" into productType;
            IF productType = 'customizable'
             THEN SELECT "cartItem"."productId" INTO productId;
              productIdArray = productIdArray || productId;
            END IF;
        END LOOP;
        RETURN json_build_object('value', coalesce(array_length(productIdArray, 1), 0) , 'valueType','integer','argument','cartid');
    END IF;
END;
$$;


CREATE OR REPLACE FUNCTION rules."totalNumberOfCartInventoryProduct"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartProduct" record;
    productOptionType text;
    productOptionIdArray integer array DEFAULT '{}';
    productOptionId integer;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'totalNumberOfInventoryProducts', 'fact', 'totalNumberOfInventoryProducts', 'title', 'Total Number Of Ready To Eat Products (with Quantity)', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartProduct" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        select "productOptionId" from "order"."cartItem" where "parentCartItemId" = "cartProduct"."id" into productOptionId;
            SELECT "type" from "products"."productOption" where "id" = productOptionId into productOptionType;
            IF productOptionType = 'inventory' then
              productOptionIdArray = productOptionIdArray || productOptionId;
            END IF;
        END LOOP;
        RETURN json_build_object('value', coalesce(array_length(productIdArray, 1), 0) , 'valueType','integer','argument','cartid');
    END IF;
END;
$$;


CREATE OR REPLACE FUNCTION rules."totalNumberOfCartMealKitProduct"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartProduct" record;
    productOptionType text;
    productOptionIdArray integer array DEFAULT '{}';
    productOptionId integer;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'totalNumberOfMealKitProducts', 'fact', 'totalNumberOfMealKitProducts', 'title', 'Total Number Of Meal Kit Products (with Quantity)', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartProduct" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        select "productOptionId" from "order"."cartItem" where "parentCartItemId" = "cartProduct"."id" into productOptionId;
            SELECT "type" from "products"."productOption" where "id" = productOptionId into productOptionType;
            IF productOptionType = 'mealKit' then
              productOptionIdArray = productOptionIdArray || productOptionId;
            END IF;
        END LOOP;
        RETURN json_build_object('value', coalesce(array_length(productIdArray, 1), 0) , 'valueType','integer','argument','cartid');
    END IF;
END;
$$;


CREATE OR REPLACE FUNCTION rules."totalNumberOfCartReadyToEatProduct"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartProduct" record;
    productOptionType text;
    productOptionIdArray integer array DEFAULT '{}';
    productOptionId integer;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'totalNumberOfReadyToEatProducts', 'fact', 'totalNumberOfReadyToEatProducts', 'title', 'Total Number Of Ready To Eat Products (with Quantity)', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartProduct" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        select "productOptionId" from "order"."cartItem" where "parentCartItemId" = "cartProduct"."id" into productOptionId;
            SELECT "type" from "products"."productOption" where "id" = productOptionId into productOptionType;
            IF productOptionType = 'readyToEat' then
              productOptionIdArray = productOptionIdArray || productOptionId;
            END IF;
        END LOOP;
        RETURN json_build_object('value', coalesce(array_length(productIdArray, 1), 0) , 'valueType','integer','argument','cartid');
    END IF;
END;
$$;


CREATE OR REPLACE FUNCTION safety.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;


CREATE OR REPLACE FUNCTION settings."operationConfigName"(opconfig settings."operationConfig") RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE
    station text;
    template text;
BEGIN
    SELECT name FROM "deviceHub"."labelTemplate" WHERE id = opConfig."labelTemplateId" INTO template;
    SELECT name FROM settings."station" WHERE id = opConfig."stationId" INTO station;
    RETURN station || ' - ' || template;
END;
$$;


CREATE OR REPLACE FUNCTION settings.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;


CREATE OR REPLACE FUNCTION "simpleRecipe"."getRecipeRichResult"(recipe "simpleRecipe"."simpleRecipe") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    res jsonb := '{ "@context": "https://schema.org/", "@type": "Recipe" }';
    yield record;
    sachet record;
    ingredients text[];
    steps jsonb[];
    proc jsonb;
    step jsonb;
BEGIN
    res := res || jsonb_build_object('name', recipe.name, 'image', COALESCE(recipe.image, ''), 'keywords', recipe.name, 'recipeCuisine', recipe.cuisine);
    IF recipe.description IS NOT NULL THEN
        res := res || jsonb_build_object('description', recipe.description);
    END IF;
    IF recipe.author IS NOT NULL THEN
        res := res || jsonb_build_object('author', jsonb_build_object('@type', 'Person', 'name', recipe.author));
    END IF;
    IF recipe."cookingTime" IS NOT NULL THEN
        res := res || jsonb_build_object('cookTime', 'PT' || recipe."cookingTime" || 'M');
    END IF;
    IF recipe."showIngredients" = true THEN
        SELECT * FROM "simpleRecipe"."simpleRecipeYield" WHERE "simpleRecipeId" = recipe.id ORDER BY yield DESC LIMIT 1 INTO yield;
        IF yield IS NOT NULL THEN
            res := res || jsonb_build_object('recipeYield', yield.yield->>'serving');
            FOR sachet IN SELECT * FROM "simpleRecipe"."simpleRecipeYield_ingredientSachet" WHERE "recipeYieldId" = yield.id LOOP
                SELECT array_append(ingredients, sachet."slipName") INTO ingredients;
            END LOOP;
            res := res || jsonb_build_object('recipeIngredient', ingredients);
        END IF;
    END IF;
    IF recipe."showProcedures" = true AND recipe."procedures" IS NOT NULL THEN
        FOR proc IN SELECT * FROM jsonb_array_elements(recipe."procedures") LOOP
            FOR step IN SELECT * FROM jsonb_array_elements(proc->'steps') LOOP
                SELECT array_append(steps, jsonb_build_object('@type', 'HowToStep', 'name', step->>'title', 'text', step->>'description', 'image', step->'assets'->'images'->0->>'url')) INTO steps;
            END LOOP;
        END LOOP;
        res := res || jsonb_build_object('recipeInstructions', steps);
    END IF;
    return res;
END;
$$;


CREATE OR REPLACE FUNCTION "simpleRecipe".issimplerecipevalid(recipe "simpleRecipe"."simpleRecipe") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    ingredientsCount int;
    instructionSetsCount int;
BEGIN
    SELECT count(*) FROM "simpleRecipe"."simpleRecipe_ingredient_processing" WHERE "simpleRecipeId" = recipe.id AND "isArchived" = false INTO ingredientsCount;
    SELECT count(*) FROM "instructions"."instructionSet" WHERE "simpleRecipeId" = recipe.id INTO instructionSetsCount;
    IF recipe.utensils IS NULL OR jsonb_array_length(recipe.utensils) = 0
        THEN return json_build_object('status', false, 'error', 'Recipe should have untensils associated!');
    ELSEIF ingredientsCount = 0
        THEN return json_build_object('status', false, 'error', 'Recipe should have ingredients!');
    ELSEIF instructionSetsCount = 0
        THEN return json_build_object('status', false, 'error', 'Recipe should have cooking steps!');
    ELSEIF recipe.assets IS NULL OR JSONB_ARRAY_LENGTH(recipe.assets->'images') = 0
        THEN return json_build_object('status', false, 'error', 'At least one image should be provided!');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;


CREATE OR REPLACE FUNCTION "simpleRecipe".set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;



CREATE OR REPLACE FUNCTION "simpleRecipe"."yieldAllergens"(yield "simpleRecipe"."simpleRecipeYield") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    arr jsonb;
    temp jsonb;
    data jsonb := '[]';
    mode record;
BEGIN
    FOR mode IN SELECT * FROM ingredient."modeOfFulfillment" WHERE "ingredientSachetId" = ANY(SELECT "ingredientSachetId" FROM "simpleRecipe"."simpleRecipeYield_ingredientSachet" WHERE "recipeYieldId" = yield.id) LOOP
        IF mode."bulkItemId" IS NOT NULL THEN
            SELECT allergens FROM inventory."bulkItem" WHERE id = mode."bulkItemId" INTO arr;
            FOR temp IN SELECT * FROM jsonb_array_elements(arr) LOOP
                data := data || temp;
            END LOOP;
        ELSIF mode."sachetItemId" IS NOT NULL THEN
            SELECT allergens FROM inventory."bulkItem" WHERE id = (SELECT "bulkItemId" FROM inventory."sachetItem" WHERE id = mode."sachetItemId") INTO arr;
            FOR temp IN SELECT * FROM jsonb_array_elements(arr) LOOP
                data := data || temp;
            END LOOP;
        ELSE
            CONTINUE;
        END IF;
    END LOOP;
    RETURN data;
END;
$$;


CREATE OR REPLACE FUNCTION "simpleRecipe"."yieldCost"(yield "simpleRecipe"."simpleRecipeYield") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE OR REPLACE FUNCTION "simpleRecipe"."yieldNutritionalInfo"(yield "simpleRecipe"."simpleRecipeYield") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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

CREATE OR REPLACE FUNCTION subscription."addOnCartItem"(x subscription."subscriptionOccurence_addOn") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    item jsonb;
BEGIN
    SELECT products."productCartItemById"(x."productOptionId") INTO item;
    item:=item || jsonb_build_object('isAddOn', true);
    item:=item || jsonb_build_object('unitPrice', x."unitPrice");
    item:=item || jsonb_build_object('subscriptionOccurenceAddOnProductId', x.id);
    RETURN item;
END
$$;


CREATE OR REPLACE FUNCTION subscription."calculateIsValid"(occurence subscription."subscriptionOccurence") RETURNS boolean LANGUAGE plpgsql STABLE AS $$
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


CREATE OR REPLACE FUNCTION subscription."calculateIsVisible"(occurence subscription."subscriptionOccurence") RETURNS boolean LANGUAGE plpgsql STABLE AS $$
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


CREATE TABLE subscription."subscriptionOccurence_product" ( "subscriptionOccurenceId" integer, "addOnPrice" numeric DEFAULT 0,
                                                                                                                            "addOnLabel" text, "productCategory" text, "isAvailable" boolean DEFAULT true,
                                                                                                                                                                                                     "isVisible" boolean DEFAULT true,
                                                                                                                                                                                                                                 "isSingleSelect" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                                       "subscriptionId" integer, id integer NOT NULL,
                                                                                                                                                                                                                                                                                                            created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                                        updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                                                                                    "isAutoSelectable" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                            "productOptionId" integer NOT NULL);


CREATE OR REPLACE FUNCTION subscription."cartItem"(x subscription."subscriptionOccurence_product") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    item jsonb;
    productType text;
    subscriptionId int;
    itemCountId int;
    itemCount int;
    itemCountPrice numeric;
    unitPrice numeric;
BEGIN
    IF x."subscriptionOccurenceId" IS NOT NULL THEN
        SELECT "subscriptionId" INTO subscriptionId FROM subscription."subscriptionOccurence" WHERE id = x."subscriptionOccurenceId";
    ELSE
        subscriptionId := x."subscriptionId";
    END IF;
    SELECT "subscriptionItemCountId" INTO itemCountId FROM subscription.subscription WHERE id = subscriptionId;
    SELECT price, count INTO itemCountPrice, itemCount FROM subscription."subscriptionItemCount" WHERE id = itemCountId;
    SELECT products."productCartItemById"(x."productOptionId") INTO item;
    item:=item || jsonb_build_object('addOnLabel',x."addOnLabel", 'addOnPrice',x."addOnPrice");
    unitPrice := (itemCountPrice / itemCount) + COALESCE(x."addOnPrice", 0);
    item:=item || jsonb_build_object('isAddOn', false);
    item:=item || jsonb_build_object('unitPrice', unitPrice);
    item:=item || jsonb_build_object('subscriptionOccurenceProductId', x.id);
    RETURN item;
END
$$;


CREATE TABLE subscription."subscriptionOccurence_customer" ( "subscriptionOccurenceId" integer NOT NULL,
                                                                                               "keycloakId" text NOT NULL,
                                                                                                                 "cartId" integer, "isSkipped" boolean DEFAULT false NOT NULL,
                                                                                                                                                                     "isAuto" boolean, "brand_customerId" integer NOT NULL);


CREATE OR REPLACE FUNCTION subscription."isCartValid"(record subscription."subscriptionOccurence_customer") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    subscriptionId int;
    itemCountId int;
    itemCount int;
    addedProductsCount int := 0;
    pendingProductsCount int := 0;
    result jsonb := '{}';
BEGIN
    IF record."cartId" IS NULL THEN
        result := result || jsonb_build_object('hasCart', false);
    ELSIF record."cartId" IS NOT NULL THEN
        result := result || jsonb_build_object('hasCart', true);
    END IF;
    SELECT "subscriptionId" INTO subscriptionId FROM subscription."subscriptionOccurence" WHERE id = record."subscriptionOccurenceId";
    SELECT "subscriptionItemCountId" INTO itemCountId FROM subscription.subscription WHERE id = subscriptionId;
    SELECT count FROM subscription."subscriptionItemCount" WHERE id = itemCountId INTO itemCount;
    SELECT COALESCE(COUNT(*), 0) INTO addedProductsCount FROM "order"."cartItem" WHERE "cartId" = record."cartId" AND "isAddOn" = false AND "parentCartItemId" IS NULL;
    result := result || jsonb_build_object('addedProductsCount', addedProductsCount);
    pendingProductsCount := itemCount - addedProductsCount;
    result := result || jsonb_build_object('pendingProductsCount', pendingProductsCount);
    IF itemCount = addedProductsCount THEN
        result := result || jsonb_build_object('itemCountValid', true, 'itemCountValidComment', 'You' || '''' || 're all set!');
    ELSIF itemCount < addedProductsCount THEN
        result := result || jsonb_build_object('itemCountValid', false, 'itemCountValidComment', 'Your cart is overflowing!');
    ELSIF itemCount > addedProductsCount THEN
        result := result || jsonb_build_object('itemCountValid', false, 'itemCountValidComment', 'Add more products!');
    END IF;
    return result;
END;
$$;


CREATE TABLE subscription."subscriptionItemCount" ( id integer NOT NULL,
                                                               "subscriptionServingId" integer NOT NULL,
                                                                                               count integer NOT NULL,
                                                                                                             "metaDetails" jsonb,
                                                                                                             price numeric, "isActive" boolean DEFAULT false,
                                                                                                                                                       tax numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                             "isTaxIncluded" boolean DEFAULT false NOT NULL);


CREATE OR REPLACE FUNCTION subscription."isSubscriptionItemCountValid"(itemcount subscription."subscriptionItemCount") RETURNS boolean LANGUAGE plpgsql STABLE AS $$
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


CREATE TABLE subscription."subscriptionServing" ( id integer NOT NULL,
                                                             "subscriptionTitleId" integer NOT NULL,
                                                                                           "servingSize" integer NOT NULL,
                                                                                                                 "metaDetails" jsonb,
                                                                                                                 "defaultSubscriptionItemCountId" integer, "isActive" boolean DEFAULT false NOT NULL);


CREATE OR REPLACE FUNCTION subscription."isSubscriptionServingValid"(serving subscription."subscriptionServing") RETURNS boolean LANGUAGE plpgsql STABLE AS $$
DECLARE
    count int;
BEGIN
    SELECT * FROM subscription."subscriptionItemCount" where "subscriptionServingId" = serving.id AND "isActive" = true LIMIT 1 into count;
    IF count > 0 THEN
        return true;
    ELSE
        PERFORM subscription."toggleServingState"(serving.id, false);
        return false;
    END IF;
END;
$$;


CREATE TABLE subscription."subscriptionTitle" ( id integer NOT NULL,
                                                           title text NOT NULL,
                                                                      "metaDetails" jsonb,
                                                                      "defaultSubscriptionServingId" integer, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                          updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                      "isActive" boolean DEFAULT false NOT NULL);


CREATE OR REPLACE FUNCTION subscription."isSubscriptionTitleValid"(title subscription."subscriptionTitle") RETURNS boolean LANGUAGE plpgsql STABLE AS $$
DECLARE
    count int;
BEGIN
    SELECT * FROM subscription."subscriptionServing" where "subscriptionTitleId" = title.id AND "isActive" = true LIMIT 1 into count;
    IF count > 0 THEN
        return true;
    ELSE
        PERFORM subscription."toggleTitleState"(title.id, false);
        return false;
    END IF;
END;
$$;


CREATE OR REPLACE FUNCTION subscription.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;


CREATE OR REPLACE FUNCTION subscription."toggleServingState"(servingid integer, state boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    UPDATE subscription."subscriptionServing"
    SET "isActive" = state
    WHERE "id" = servingId;
END;
$$;


CREATE OR REPLACE FUNCTION subscription."toggleTitleState"(titleid integer, state boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    UPDATE subscription."subscriptionTitle"
    SET "isActive" = state
    WHERE "id" = titleId;
END;
$$;


CREATE OR REPLACE FUNCTION website.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;


CREATE TABLE brands.brand ( id integer NOT NULL,
                                       domain text, "isDefault" boolean DEFAULT false NOT NULL,
                                                                                      title text, "isPublished" boolean DEFAULT true NOT NULL,
                                                                                                                                     "onDemandRequested" boolean DEFAULT false NOT NULL,
                                                                                                                                                                               "subscriptionRequested" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                             "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                "parseurMailBoxId" integer, "importHistoryId" integer);

COMMENT ON TABLE brands.brand IS 'This table contains all the brands available in this instance.';

COMMENT ON COLUMN brands.brand.id IS 'Unique id of brand';

COMMENT ON COLUMN brands.brand.domain IS 'Domain at which this particular brand would be operating at.';

COMMENT ON COLUMN brands.brand."isDefault" IS 'This brand would be chosen incase any url is entered that does not correspond to any other brand';

COMMENT ON COLUMN brands.brand.title IS 'This is the title of the brand for internal purpose.';

COMMENT ON COLUMN brands.brand."isPublished" IS 'Whether the brand is published or not';

COMMENT ON COLUMN brands.brand."onDemandRequested" IS 'If this brand would be operating an ondemand store. If false, then opening /store link would redirect.';

COMMENT ON COLUMN brands.brand."subscriptionRequested" IS 'If this brand would be operating an subscription store. If false, then opening /subscription link would redirect.';

COMMENT ON COLUMN brands.brand."isArchived" IS 'if True, means that this brand is no longer active and user attempted to delete it.';

COMMENT ON COLUMN brands.brand."parseurMailBoxId" IS 'This is for parseur mailbox functionality.';


CREATE TABLE brands."brand_paymentPartnership" ( "brandId" integer NOT NULL,
                                                                   "paymentPartnershipId" integer NOT NULL,
                                                                                                  "isActive" boolean DEFAULT true NOT NULL);

COMMENT ON TABLE brands."brand_paymentPartnership" IS 'This is a many to many table for maintaining the different payment options available for each brand.';

COMMENT ON COLUMN brands."brand_paymentPartnership"."brandId" IS 'Id of the brand from the brand table.';

COMMENT ON COLUMN brands."brand_paymentPartnership"."paymentPartnershipId" IS 'id of the paymentPartnership from the dailycloak database table of paymentPartnership. This id represents which payment company and what are payment conditions to be used.';

COMMENT ON COLUMN brands."brand_paymentPartnership"."isActive" IS 'Whether this payment partnership is active or not.';


CREATE TABLE brands."brand_storeSetting" ( "brandId" integer NOT NULL,
                                                             "storeSettingId" integer NOT NULL,
                                                                                      value jsonb,
                                                                                                  "importHistoryId" integer);

COMMENT ON TABLE brands."brand_storeSetting" IS 'This is a many to many table maintaining Ondemand Store setting for available brands.';

COMMENT ON COLUMN brands."brand_storeSetting"."brandId" IS 'This is the brand id from brand table.';

COMMENT ON COLUMN brands."brand_storeSetting"."storeSettingId" IS 'This is the id from the list of settings available for ondemand.';

COMMENT ON COLUMN brands."brand_storeSetting".value IS 'This is the value of the particular setting for the particular brand.';


CREATE TABLE brands."brand_subscriptionStoreSetting" ( "brandId" integer NOT NULL,
                                                                         "subscriptionStoreSettingId" integer NOT NULL,
                                                                                                              value jsonb);

COMMENT ON TABLE brands."brand_subscriptionStoreSetting" IS 'This table maintains list of settings for subscription store for brands.';

COMMENT ON COLUMN brands."brand_subscriptionStoreSetting"."brandId" IS 'This is the brand id from the brand table.';

COMMENT ON COLUMN brands."brand_subscriptionStoreSetting"."subscriptionStoreSettingId" IS 'This is the id from the list of settings available for subscription store.';

COMMENT ON COLUMN brands."brand_subscriptionStoreSetting".value IS 'This is the value of the particular setting for the particular brand.';


CREATE TABLE brands."storeSetting" ( id integer NOT NULL,
                                                identifier text NOT NULL,
                                                                value jsonb NOT NULL,
                                                                            type text);

COMMENT ON TABLE brands."storeSetting" IS 'This lists all the available settings for ondemand store.';

COMMENT ON COLUMN brands."storeSetting".id IS 'This is autogenerated id of the setting representation available for ondemand.';

COMMENT ON COLUMN brands."storeSetting".identifier IS 'This is a unique identifier of the individual setting type.';

COMMENT ON COLUMN brands."storeSetting".value IS 'This is a jsonb data type storing default value for the setting. If no brand specific setting is available, then this setting value would be used.';

COMMENT ON COLUMN brands."storeSetting".type IS 'Type of setting to segment or categorize according to different use-cases.';



CREATE TABLE brands."subscriptionStoreSetting" ( id integer NOT NULL,
                                                            identifier text NOT NULL,
                                                                            value jsonb,
                                                                            type text);

COMMENT ON TABLE brands."subscriptionStoreSetting" IS 'This lists all the available settings for ondemand store.';

COMMENT ON COLUMN brands."subscriptionStoreSetting".id IS 'This is autogenerated id of the setting representation available for subscripton.';

COMMENT ON COLUMN brands."subscriptionStoreSetting".identifier IS 'This is a unique identifier of the individual setting type.';

COMMENT ON COLUMN brands."subscriptionStoreSetting".value IS 'This is a jsonb data type storing default value for the setting. If no brand specific setting is available, then this setting value would be used.';

COMMENT ON COLUMN brands."subscriptionStoreSetting".type IS 'Type of setting to segment or categorize according to different use-cases.';


CREATE TABLE content.identifier ( title text NOT NULL,
                                             "pageTitle" text NOT NULL);


CREATE TABLE content.page ( title text NOT NULL,
                                       description text);


CREATE TABLE content."subscriptionDivIds" ( id text NOT NULL,
                                                    "fileId" integer);


CREATE TABLE content.template ( id uuid NOT NULL);


CREATE TABLE crm.brand_customer ( id integer NOT NULL,
                                             "keycloakId" text NOT NULL,
                                                               "brandId" integer NOT NULL,
                                                                                 created_at timestamp with time zone DEFAULT now(),
                                                                                                                             updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                         "isSubscriber" boolean DEFAULT false,
                                                                                                                                                                                                        "subscriptionId" integer, "subscriptionAddressId" text, "subscriptionPaymentMethodId" text, "isAutoSelectOptOut" boolean DEFAULT false NOT NULL);

COMMENT ON TABLE crm.brand_customer IS 'This table maintains a list of all the customers who have signed into this particular brand atleast once.';

COMMENT ON COLUMN crm.brand_customer.id IS 'Auto-generated id.';

COMMENT ON COLUMN crm.brand_customer."keycloakId" IS 'This is the unique id of customer given by keycloak.';

COMMENT ON COLUMN crm.brand_customer."brandId" IS 'This is the brandId from brand table.';

COMMENT ON COLUMN crm.brand_customer."isSubscriber" IS 'If this customer has subscribed to any plan on subscription store for this particular brand.';

COMMENT ON COLUMN crm.brand_customer."subscriptionId" IS 'This is the id of the subscription plan chosen by this customer.';

COMMENT ON COLUMN crm.brand_customer."subscriptionAddressId" IS 'This is the id of address from Dailykey database at which this plan would be delivering the weekly box to.';

COMMENT ON COLUMN crm.brand_customer."subscriptionPaymentMethodId" IS 'This is the id of payment method from Dailykey database defining which particular payment method would be used for auto deduction of weekly amount.';


CREATE TABLE crm.brand_campaign ( "brandId" integer NOT NULL,
                                                    "campaignId" integer NOT NULL,
                                                                         "isActive" boolean DEFAULT true);

COMMENT ON TABLE crm.brand_campaign IS 'This is a many to many table maintaining relationship between brand and campaigns.';

COMMENT ON COLUMN crm.brand_campaign."brandId" IS 'This is the brandId from the brand table.';

COMMENT ON COLUMN crm.brand_campaign."campaignId" IS 'This is campaign id from campaign table.';

COMMENT ON COLUMN crm.brand_campaign."isActive" IS 'Whether this particular campaign is active or not for this brand.';


CREATE TABLE crm.brand_coupon ( "brandId" integer NOT NULL,
                                                  "couponId" integer NOT NULL,
                                                                     "isActive" boolean DEFAULT true NOT NULL);

COMMENT ON TABLE crm.brand_coupon IS 'This is a many to many table maintaining relationship between brand and coupons.';

COMMENT ON COLUMN crm.brand_coupon."brandId" IS 'This is the brandId from the brand table.';

COMMENT ON COLUMN crm.brand_coupon."couponId" IS 'This is coupon id from coupon table.';

COMMENT ON COLUMN crm.brand_coupon."isActive" IS 'Whether this particular coupon is active or not for this brand.';


CREATE TABLE crm."campaignType" ( id integer NOT NULL,
                                             value text NOT NULL);



CREATE TABLE crm.customer ( id integer NOT NULL,
                                       source text, email text NOT NULL,
                                                               "keycloakId" text NOT NULL,
                                                                                 "clientId" text, "isSubscriber" boolean DEFAULT false NOT NULL,
                                                                                                                                       "subscriptionId" integer, "subscriptionAddressId" uuid,
                                                                                                                                                                 "subscriptionPaymentMethodId" text, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                 updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                             "isTest" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                            "sourceBrandId" integer DEFAULT 1 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                              "isArchived" boolean DEFAULT false NOT NULL);

COMMENT ON TABLE crm.customer IS 'This lists records of all the unique customers across all the brands.';

COMMENT ON COLUMN crm.customer.id IS 'Auto-generated id of the customer';

COMMENT ON COLUMN crm.customer.source IS 'From which source this customer was first created. If subscription or ondemand.';

COMMENT ON COLUMN crm.customer.email IS 'Unique email of the customer.';

COMMENT ON COLUMN crm.customer."keycloakId" IS 'This is the unique id of customer given by keycloak.';

COMMENT ON COLUMN crm.customer."isSubscriber" IS 'If this customer has subscribed to any plan on subscription store for any of the brand.';

COMMENT ON COLUMN crm.customer."isTest" IS 'If true, all the carts for this customer would bypass the payment.';

COMMENT ON COLUMN crm.customer."sourceBrandId" IS 'From which brand was this customer first signed up in the system.';

COMMENT ON COLUMN crm.customer."isArchived" IS 'Marks the deletion of customer if user attempts to delete it';


CREATE TABLE crm."customerReferral" ( id integer NOT NULL,
                                                 "keycloakId" text NOT NULL,
                                                                   "referralCode" uuid DEFAULT public.gen_random_uuid() NOT NULL,
                                                                                                                        "referredByCode" uuid,
                                                                                                                        "referralStatus" text DEFAULT 'PENDING'::text NOT NULL,
                                                                                                                                                                      "referralCampaignId" integer, "signupCampaignId" integer, "signupStatus" text DEFAULT 'PENDING'::text NOT NULL,
                                                                                                                                                                                                                                                                            "brandId" integer DEFAULT 1 NOT NULL);

COMMENT ON TABLE crm."customerReferral" IS 'This table maintains a record of all the customer and brand''s referral codes.';

COMMENT ON COLUMN crm."customerReferral".id IS 'Auto-generated id for the row.';

COMMENT ON COLUMN crm."customerReferral"."keycloakId" IS 'This is the unique id of customer given by keycloak.';

COMMENT ON COLUMN crm."customerReferral"."referralCode" IS 'This is auto generated UUID code created for each customer to share with others for referral.';

COMMENT ON COLUMN crm."customerReferral"."referredByCode" IS 'This is the referral code that was used by the customer for signing up';

COMMENT ON COLUMN crm."customerReferral"."referralStatus" IS 'This denotes the status if the customer who referred was awarded something according to the referral campaign id.';

COMMENT ON COLUMN crm."customerReferral"."referralCampaignId" IS 'The id of the campaign to be used to award the referrer.';

COMMENT ON COLUMN crm."customerReferral"."signupCampaignId" IS 'The id of the campaign to be used to reward this customer who signed up.';

COMMENT ON COLUMN crm."customerReferral"."signupStatus" IS 'This denotes the status if the signed up customer was awarded something according to the  signup campaign id.';

COMMENT ON COLUMN crm."customerReferral"."brandId" IS 'This is the brandId from the brand table.';



CREATE TABLE crm."loyaltyPoint" ( id integer NOT NULL,
                                             "keycloakId" text NOT NULL,
                                                               points integer DEFAULT 0 NOT NULL,
                                                                                        "isActive" boolean DEFAULT true NOT NULL,
                                                                                                                        created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                          updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                            "brandId" integer DEFAULT 1 NOT NULL);

COMMENT ON TABLE crm."loyaltyPoint" IS 'This table maintains record of all the loyalty point references of all customers across all brands.';

COMMENT ON COLUMN crm."loyaltyPoint"."keycloakId" IS 'Customer keycloak Id referencing the customer for this row.';

COMMENT ON COLUMN crm."loyaltyPoint".points IS 'Available loyalty points for this customer across the referenced brand in the row.';

COMMENT ON COLUMN crm."loyaltyPoint"."isActive" IS 'If loyalty points for this customer is active.';

COMMENT ON COLUMN crm."loyaltyPoint"."brandId" IS 'Id of the brand for which this loyalty point is created and maintained.';


CREATE TABLE crm."loyaltyPointTransaction" ( id integer NOT NULL,
                                                        "loyaltyPointId" integer NOT NULL,
                                                                                 points integer NOT NULL,
                                                                                                "orderCartId" integer, type text, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                              updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                          "amountRedeemed" numeric, "customerReferralId" integer);

COMMENT ON TABLE crm."loyaltyPointTransaction" IS 'This table lists all the loyalty point transactions taking place.';


CREATE TABLE crm."orderCart_rewards" ( id integer NOT NULL,
                                                  "orderCartId" integer NOT NULL,
                                                                        "rewardId" integer NOT NULL);


CREATE TABLE crm.reward ( id integer NOT NULL,
                                     type text NOT NULL,
                                               "couponId" integer, "conditionId" integer, priority integer DEFAULT 1,
                                                                                                                   "campaignId" integer, "rewardValue" jsonb);


CREATE TABLE crm."rewardHistory" ( id integer NOT NULL,
                                              "rewardId" integer NOT NULL,
                                                                 created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                   updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                     "couponId" integer, "campaignId" integer, "keycloakId" text NOT NULL,
                                                                                                                                                                                                                                 "orderCartId" integer, "orderId" integer, discount numeric, "loyaltyPointTransactionId" integer, "loyaltyPoints" integer, "walletAmount" numeric, "walletTransactionId" integer, "brandId" integer DEFAULT 1 NOT NULL);


CREATE TABLE crm."rewardType" ( id integer NOT NULL,
                                           value text NOT NULL,
                                                      "useForCoupon" boolean NOT NULL,
                               handler text NOT NULL);


CREATE TABLE crm."rewardType_campaignType" ( "rewardTypeId" integer NOT NULL,
                                                                    "campaignTypeId" integer NOT NULL);




CREATE TABLE crm.wallet ( id integer NOT NULL,
                                     "keycloakId" text, amount numeric DEFAULT 0 NOT NULL,
                                                                                 "isActive" boolean DEFAULT true NOT NULL,
                                                                                                                 created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                             updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                         "brandId" integer DEFAULT 1 NOT NULL);


CREATE TABLE crm."walletTransaction" ( id integer NOT NULL,
                                                  "walletId" integer NOT NULL,
                                                                     amount numeric NOT NULL,
                                                                                    type text, created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                 updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                   "orderCartId" integer, "customerReferralId" integer);


CREATE TABLE "deviceHub".computer ( "printNodeId" integer NOT NULL,
                                                          name text, inet text, inet6 text, hostname text, jre text, created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                       updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                         state text, version text);


CREATE TABLE "deviceHub".config ( id integer NOT NULL,
                                             name text NOT NULL,
                                                       value jsonb NOT NULL);



CREATE TABLE "deviceHub"."labelTemplate" ( id integer NOT NULL,
                                                      name text NOT NULL);



CREATE TABLE "deviceHub".printer ( "printNodeId" integer NOT NULL,
                                                         "computerId" integer NOT NULL,
                                                                              name text NOT NULL,
                                                                                        description text, state text NOT NULL,
                                                                                                                     bins jsonb,
                                                                                                                     "collate" boolean, copies integer, color boolean, dpis jsonb,
                                                                                                                                                                       extent jsonb,
                                                                                                                                                                              medias jsonb,
                                                                                                                                                                              nup jsonb,
                                                                                                                                                                              papers jsonb,
                                                                                                                                                                              printrate jsonb,
                                                                                                                                                                              supports_custom_paper_size boolean, duplex boolean, "printerType" text);


CREATE TABLE "deviceHub"."printerType" ( type text NOT NULL);


CREATE TABLE "deviceHub".scale ( "deviceName" text NOT NULL,
                                                   "deviceNum" integer NOT NULL,
                                                                       "computerId" integer NOT NULL,
                                                                                            vendor text, "vendorId" integer, "productId" integer, port text, count integer, measurement jsonb,
                                                                                                                                                                            "ntpOffset" integer, "ageOfData" integer, "stationId" integer, active boolean DEFAULT true,
                                                                                                                                                                                                                                                                  id integer NOT NULL);



CREATE TABLE editor.block ( id integer NOT NULL,
                                       name text NOT NULL,
                                                 path text NOT NULL,
                                                           assets jsonb,
                                                           "fileId" integer NOT NULL,
                                                                            category text, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                       updated_at timestamp with time zone DEFAULT now());




CREATE TABLE editor."cssFileLinks" ( "guiFileId" integer NOT NULL,
                                                         "cssFileId" integer NOT NULL,
                                                                             "position" bigint, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                            updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                        id integer NOT NULL);


CREATE TABLE editor.file ( id integer NOT NULL,
                                      path text NOT NULL,
                                                created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                  updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                    "fileType" text, commits jsonb,
                                                                                                                                                                     "lastSaved" timestamp with time zone,
                                                                                                                                                                                                     "fileName" text, "isTemplate" boolean, "isBlock" boolean);


CREATE TABLE editor."jsFileLinks" ( "guiFileId" integer NOT NULL,
                                                        "jsFileId" integer NOT NULL,
                                                                           "position" integer, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                           updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                       id integer NOT NULL);


CREATE TABLE editor."linkedFiles" ( id integer NOT NULL,
                                               records jsonb);


CREATE TABLE editor.template ( id integer NOT NULL,
                                          name text NOT NULL,
                                                    route text NOT NULL,
                                                               type text, thumbnail text);


CREATE TABLE fulfilment.brand_recurrence ( "brandId" integer NOT NULL,
                                                             "recurrenceId" integer NOT NULL,
                                                                                    "isActive" boolean DEFAULT true NOT NULL);


CREATE TABLE fulfilment.charge ( id integer NOT NULL,
                                            "orderValueFrom" numeric NOT NULL,
                                                                     "orderValueUpto" numeric NOT NULL,
                                                                                              charge numeric NOT NULL,
                                                                                                             "mileRangeId" integer, "autoDeliverySelection" boolean DEFAULT true NOT NULL);


CREATE TABLE fulfilment."deliveryPreferenceByCharge" ( "chargeId" integer NOT NULL,
                                                                          "clauseId" integer NOT NULL,
                                                                                             "isActive" boolean DEFAULT true NOT NULL,
                                                                                                                             priority integer NOT NULL,
                                                                                                                                              created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                          updated_at timestamp with time zone DEFAULT now());


CREATE TABLE fulfilment."deliveryService" ( id integer NOT NULL,
                                                       "partnershipId" integer, "isThirdParty" boolean DEFAULT true NOT NULL,
                                                                                                                    "isActive" boolean DEFAULT false,
                                                                                                                                               "companyName" text NOT NULL,
                                                                                                                                                                  logo text);



CREATE TABLE fulfilment."fulfillmentType" ( value text NOT NULL,
                                                       "isActive" boolean DEFAULT true NOT NULL);



CREATE TABLE fulfilment.recurrence ( id integer NOT NULL,
                                                rrule text NOT NULL,
                                                           type text DEFAULT 'PREORDER_DELIVERY'::text NOT NULL,
                                                                                                       "isActive" boolean DEFAULT true NOT NULL,
                                                                                                                                       psql_rrule jsonb);



CREATE TABLE imports.import ( id integer NOT NULL,
                                         entity text NOT NULL,
                                                     file text NOT NULL,
                                                               "importType" text NOT NULL,
                                                                                 confirm boolean DEFAULT false NOT NULL,
                                                                                                               created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                           status text);


CREATE TABLE imports."importHistory" ( id integer NOT NULL,
                                                  "importId" integer, "importFrom" text);



CREATE TABLE ingredient."ingredientProcessing" ( id integer NOT NULL,
                                                            "processingName" text NOT NULL,
                                                                                  "ingredientId" integer NOT NULL,
                                                                                                         "nutritionalInfo" jsonb,
                                                                                                         cost jsonb,
                                                                                                         created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                     updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                 "isArchived" boolean DEFAULT false NOT NULL);


CREATE VIEW ingredient."ingredientProcessingView" AS
SELECT "ingredientProcessing".id,
       "ingredientProcessing"."processingName",
       "ingredientProcessing"."ingredientId",
       "ingredientProcessing"."nutritionalInfo",
       "ingredientProcessing".cost,
       "ingredientProcessing".created_at,
       "ingredientProcessing".updated_at,
       "ingredientProcessing"."isArchived",
       concat(
                  (SELECT ingredient.name
                   FROM ingredient.ingredient
                   WHERE (ingredient.id = "ingredientProcessing"."ingredientId")), ' - ', "ingredientProcessing"."processingName") AS "displayName"
FROM ingredient."ingredientProcessing";


CREATE TABLE ingredient."ingredientSacahet_recipeHubSachet" ( "ingredientSachetId" integer NOT NULL,
                                                                                           "recipeHubSachetId" uuid NOT NULL);


CREATE VIEW ingredient."ingredientSachetView" AS
SELECT "ingredientSachet".id,
       "ingredientSachet".quantity,
       "ingredientSachet"."ingredientProcessingId",
       "ingredientSachet"."ingredientId",
       "ingredientSachet"."createdAt",
       "ingredientSachet"."updatedAt",
       "ingredientSachet".tracking,
       "ingredientSachet".unit,
       "ingredientSachet".visibility,
       "ingredientSachet"."liveMOF",
       "ingredientSachet"."isArchived",
       concat(
                  (SELECT "ingredientProcessingView"."displayName"
                   FROM ingredient."ingredientProcessingView"
                   WHERE ("ingredientProcessingView".id = "ingredientSachet"."ingredientProcessingId")), ' - ', "ingredientSachet".quantity, "ingredientSachet".unit) AS "displayName"
FROM ingredient."ingredientSachet";




CREATE TABLE ingredient."modeOfFulfillmentEnum" ( value text NOT NULL,
                                                             description text);




CREATE TABLE insights.app_module_insight ( "appTitle" text NOT NULL,
                                                           "moduleTitle" text NOT NULL,
                                                                              "insightIdentifier" text NOT NULL);


CREATE TABLE insights.chart ( id integer NOT NULL,
                                         "layoutType" text DEFAULT 'HERO'::text,
                                                                   config jsonb,
                                                                   "insightIdentifier" text NOT NULL);



CREATE TABLE insights.date ( date date NOT NULL,
                                       day text);


CREATE TABLE insights.day ( "dayName" text NOT NULL,
                                           "dayNumber" integer);


CREATE TABLE insights.hour ( hour integer NOT NULL);


CREATE TABLE insights.insights ( query text NOT NULL,
                                            "availableOptions" jsonb NOT NULL,
                                                                     switches jsonb NOT NULL,
                                                                                    "isActive" boolean DEFAULT false,
                                                                                                               "defaultOptions" jsonb,
                                                                                                               identifier text NOT NULL,
                                                                                                                               description text, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                             updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                         filters jsonb,
                                                                                                                                                                                                                                         config jsonb,
                                                                                                                                                                                                                                         "schemaVariables" jsonb);

COMMENT ON COLUMN insights.insights.filters IS 'same as availableOptions, will be used to render individual options like date range in insights.';


CREATE TABLE insights.month ( number integer NOT NULL,
                                             name text NOT NULL);


CREATE VIEW insights.test AS
SELECT customer.id,
       customer.source,
       customer.email,
       customer."keycloakId",
       customer."clientId",
       customer."isSubscriber",
       customer."subscriptionId",
       customer."subscriptionAddressId",
       customer."subscriptionPaymentMethodId",
       customer.created_at,
       customer.updated_at,
       customer."isTest",
       customer."sourceBrandId",
       customer."isArchived"
FROM crm.customer;


CREATE VIEW insights.test1 AS
SELECT customer.source
FROM crm.customer;


CREATE VIEW insights.test2 AS
SELECT customer.source AS xyz
FROM crm.customer;


CREATE VIEW insights.test3 AS
SELECT count(customer.id) AS xyz
FROM crm.customer
GROUP BY customer.source;


CREATE VIEW insights.test4 AS
SELECT count(customer.id) AS xyz,
       customer.source
FROM crm.customer
GROUP BY customer.source;


CREATE VIEW insights.test5 AS
SELECT count(customer.id) AS count,
       customer.source
FROM crm.customer
GROUP BY customer.source;


CREATE TABLE instructions."instructionSet" ( id integer NOT NULL,
                                                        title text, "position" integer, "simpleRecipeId" integer, "productOptionId" integer);


CREATE TABLE instructions."instructionStep" ( id integer NOT NULL,
                                                         title text, description text, assets jsonb DEFAULT jsonb_build_object('images', '[]'::jsonb, 'videos', '[]'::jsonb) NOT NULL,
                                                                                                                                                                             "position" integer, "instructionSetId" integer NOT NULL,
                                                                                                                                                                                                                            "isVisible" boolean DEFAULT true NOT NULL);



CREATE TABLE inventory."bulkItemHistory" ( id integer NOT NULL,
                                                      "bulkItemId" integer NOT NULL,
                                                                           quantity numeric NOT NULL,
                                                                                            comment jsonb,
                                                                                                    "purchaseOrderItemId" integer, "bulkWorkOrderId" integer, status text NOT NULL,
                                                                                                                                                                          unit text, "orderSachetId" integer, "sachetWorkOrderId" integer, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                       updated_at timestamp with time zone DEFAULT now());



CREATE TABLE inventory."bulkItem" ( id integer NOT NULL,
                                               "processingName" text NOT NULL,
                                                                     "supplierItemId" integer NOT NULL,
                                                                                              labor jsonb,
                                                                                              "shelfLife" jsonb,
                                                                                              yield jsonb,
                                                                                              "nutritionInfo" jsonb,
                                                                                              sop jsonb,
                                                                                              allergens jsonb,
                                                                                              "parLevel" numeric, "maxLevel" numeric, "onHand" numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                 "storageCondition" jsonb,
                                                                                                                                                                 "createdAt" timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                              "updatedAt" timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                           "bulkDensity" numeric DEFAULT 1,
                                                                                                                                                                                                                                                                                         equipments jsonb,
                                                                                                                                                                                                                                                                                         unit text, committed numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                awaiting numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                           consumed numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                      "isAvailable" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                         "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                            image jsonb);


CREATE VIEW inventory."bulkItemView" AS
SELECT "bulkItem"."supplierItemId",
       "bulkItem"."processingName",

    (SELECT "supplierItem".name
     FROM inventory."supplierItem"
     WHERE ("supplierItem".id = "bulkItem"."supplierItemId")) AS "supplierItemName",

    (SELECT "supplierItem"."supplierId"
     FROM inventory."supplierItem"
     WHERE ("supplierItem".id = "bulkItem"."supplierItemId")) AS "supplierId",
       "bulkItem".id,
       "bulkItem"."bulkDensity"
FROM inventory."bulkItem";


CREATE TABLE inventory."bulkItem_unitConversion" ( id integer NOT NULL,
                                                              "entityId" integer NOT NULL,
                                                                                 "unitConversionId" integer NOT NULL);



CREATE TABLE inventory."bulkWorkOrder" ( id integer NOT NULL,
                                                    "inputBulkItemId" integer, "outputBulkItemId" integer, "outputQuantity" numeric DEFAULT 0 NOT NULL,
                                                                                                                                              "userId" integer, "scheduledOn" timestamp with time zone,
                                                                                                                                                                                                  "inputQuantity" numeric, status text DEFAULT 'UNPUBLISHED'::text,
                                                                                                                                                                                                                                               "stationId" integer, "inputQuantityUnit" text, "supplierItemId" integer, "isPublished" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                                            name text, "outputYield" numeric);



CREATE TABLE inventory."packagingHistory" ( id integer NOT NULL,
                                                       "packagingId" integer NOT NULL,
                                                                             quantity numeric NOT NULL,
                                                                                              "purchaseOrderItemId" integer NOT NULL,
                                                                                                                            status text DEFAULT 'PENDING'::text NOT NULL,
                                                                                                                                                                unit text, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                       updated_at timestamp with time zone DEFAULT now());



CREATE TABLE inventory."purchaseOrderItem" ( id integer NOT NULL,
                                                        "bulkItemId" integer, "supplierItemId" integer, "orderQuantity" numeric DEFAULT 0,
                                                                                                                                        status text DEFAULT 'UNPUBLISHED'::text NOT NULL,
                                                                                                                                                                                details jsonb,
                                                                                                                                                                                unit text, "supplierId" integer, price numeric, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                            updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                        "packagingId" integer, "mandiPurchaseOrderItemId" integer, type text DEFAULT 'PACKAGING'::text NOT NULL);



CREATE TABLE inventory."sachetItemHistory" ( id integer NOT NULL,
                                                        "sachetItemId" integer NOT NULL,
                                                                               "sachetWorkOrderId" integer, quantity numeric NOT NULL,
                                                                                                                             comment jsonb,
                                                                                                                                     status text NOT NULL,
                                                                                                                                                 "orderSachetId" integer, unit text, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                 updated_at timestamp with time zone DEFAULT now());

CREATE TABLE inventory."sachetItem" ( id integer NOT NULL,
                                                 "unitSize" numeric NOT NULL,
                                                                    "parLevel" numeric, "maxLevel" numeric, "onHand" numeric DEFAULT 0 NOT NULL,
                                                                                                                                       "isAvailable" boolean DEFAULT true NOT NULL,
                                                                                                                                                                          "bulkItemId" integer NOT NULL,
                                                                                                                                                                                               unit text NOT NULL,
                                                                                                                                                                                                         consumed numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                    awaiting numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                               committed numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                           "isArchived" boolean DEFAULT false NOT NULL);



CREATE VIEW inventory."sachetItemView" AS
SELECT "sachetItem".id,
       "sachetItem"."unitSize",
       "sachetItem"."bulkItemId",

    (SELECT "bulkItemView"."supplierItemName"
     FROM inventory."bulkItemView"
     WHERE ("bulkItemView".id = "sachetItem"."bulkItemId")) AS "supplierItemName",

    (SELECT "bulkItemView"."processingName"
     FROM inventory."bulkItemView"
     WHERE ("bulkItemView".id = "sachetItem"."bulkItemId")) AS "processingName",

    (SELECT "bulkItemView"."supplierId"
     FROM inventory."bulkItemView"
     WHERE ("bulkItemView".id = "sachetItem"."bulkItemId")) AS "supplierId",
       "sachetItem".unit,

    (SELECT "bulkItem"."bulkDensity"
     FROM inventory."bulkItem"
     WHERE ("bulkItem".id = "sachetItem"."bulkItemId")) AS "bulkDensity"
FROM inventory."sachetItem";


CREATE TABLE inventory."sachetWorkOrder" ( id integer NOT NULL,
                                                      "inputBulkItemId" integer, "outputSachetItemId" integer, "outputQuantity" numeric DEFAULT 0 NOT NULL,
                                                                                                                                                  "inputQuantity" numeric, "packagingId" integer, label jsonb,
                                                                                                                                                                                                  "stationId" integer, "userId" integer, "scheduledOn" timestamp with time zone,
                                                                                                                                                                                                                                                                           status text DEFAULT 'UNPUBLISHED'::text,
                                                                                                                                                                                                                                                                                               created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                           updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                                                                       name text, "supplierItemId" integer, "isPublished" boolean DEFAULT false NOT NULL);



CREATE TABLE inventory.supplier ( id integer NOT NULL,
                                             name text NOT NULL,
                                                       "contactPerson" jsonb,
                                                       address jsonb,
                                                       "shippingTerms" jsonb,
                                                       "paymentTerms" jsonb,
                                                       available boolean DEFAULT true NOT NULL,
                                                                                      "importId" integer, "mandiSupplierId" integer, logo jsonb);


CREATE VIEW inventory."supplierItemView" AS
SELECT "supplierItem"."supplierId",
       "supplierItem".name AS "supplierItemName",
       "supplierItem"."unitSize",
       "supplierItem".unit,

    (SELECT "bulkItemView"."processingName"
     FROM inventory."bulkItemView"
     WHERE ("bulkItemView".id = "supplierItem"."bulkItemAsShippedId")) AS "processingName",
       "supplierItem".id,

    (SELECT "bulkItem"."bulkDensity"
     FROM inventory."bulkItem"
     WHERE ("bulkItem".id = "supplierItem"."bulkItemAsShippedId")) AS "bulkDensity"
FROM inventory."supplierItem";



CREATE TABLE inventory."supplierItem_unitConversion" ( id integer NOT NULL,
                                                                  "entityId" integer NOT NULL,
                                                                                     "unitConversionId" integer NOT NULL);





CREATE TABLE inventory."unitConversionByBulkItem" ( "bulkItemId" integer NOT NULL,
                                                                         "unitConversionId" integer NOT NULL,
                                                                                                    "customConversionFactor" numeric NOT NULL,
                                                                                                                                     id integer NOT NULL);




CREATE TABLE master."accompanimentType" ( id integer NOT NULL,
                                                     name text NOT NULL);




CREATE TABLE master."allergenName" ( id integer NOT NULL,
                                                name text NOT NULL,
                                                          description text);




CREATE TABLE master."cuisineName" ( name text NOT NULL,
                                              id integer NOT NULL);




CREATE TABLE master."processingName" ( id integer NOT NULL,
                                                  name text NOT NULL,
                                                            description text);


CREATE TABLE master."productCategory" ( name text NOT NULL,
                                                  "imageUrl" text, "iconUrl" text, "metaDetails" jsonb,
                                                                                   "importHistoryId" integer);


CREATE TABLE master.unit ( id integer NOT NULL,
                                      name text NOT NULL);


CREATE TABLE master."unitConversion" ( id integer NOT NULL,
                                                  "inputUnitName" text NOT NULL,
                                                                       "outputUnitName" text NOT NULL,
                                                                                             "conversionFactor" numeric NOT NULL,
                                                                                                                        "bulkDensity" numeric, "isCanonical" boolean DEFAULT false);

COMMENT ON COLUMN master."unitConversion"."bulkDensity" IS 'kg/l';

COMMENT ON COLUMN master."unitConversion"."isCanonical" IS 'is standard?';


CREATE TABLE notifications."displayNotification" ( id uuid DEFAULT public.gen_random_uuid() NOT NULL,
                                                                                            "typeId" uuid NOT NULL,
                                                                                                          created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                            updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                              content jsonb NOT NULL,
                                                                                                                                                                                                                            seen boolean DEFAULT false NOT NULL);


CREATE TABLE notifications."emailConfig" ( id uuid DEFAULT public.gen_random_uuid() NOT NULL,
                                                                                    "typeId" uuid NOT NULL,
                                                                                                  template jsonb,
                                                                                                           email text NOT NULL,
                                                                                                                      "isActive" boolean DEFAULT true NOT NULL);


CREATE TABLE notifications."printConfig" ( id uuid DEFAULT public.gen_random_uuid() NOT NULL,
                                                                                    "printerPrintNodeId" integer, "typeId" uuid NOT NULL,
                                                                                                                                "isActive" boolean DEFAULT true NOT NULL,
                                                                                                                                                                created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                  updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                                                                    template jsonb NOT NULL);


CREATE TABLE notifications."smsConfig" ( id uuid DEFAULT public.gen_random_uuid() NOT NULL,
                                                                                  "typeId" uuid NOT NULL,
                                                                                                template jsonb,
                                                                                                         "phoneNo" text NOT NULL,
                                                                                                                        "isActive" boolean DEFAULT true NOT NULL);


CREATE TABLE notifications.type ( id uuid DEFAULT public.gen_random_uuid() NOT NULL,
                                                                           name text NOT NULL,
                                                                                     description text, app text NOT NULL,
                                                                                                                "table" text NOT NULL,
                                                                                                                             schema text NOT NULL,
                                                                                                                                         op text NOT NULL,
                                                                                                                                                 fields jsonb NOT NULL,
                                                                                                                                                              "isActive" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                               template jsonb NOT NULL,
                                                                                                                                                                                                              "isLocal" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                             "isGlobal" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                                             "playAudio" boolean DEFAULT false,
                                                                                                                                                                                                                                                                                                         "audioUrl" text, "webhookEnv" text DEFAULT 'WEBHOOK_DEFAULT_NOTIFICATION_HANDLER'::text,
                                                                                                                                                                                                                                                                                                                                                    "emailFrom" jsonb DEFAULT '{"name": "", "email": ""}'::jsonb);


CREATE TABLE "onDemand".brand_collection ( "brandId" integer NOT NULL,
                                                             "collectionId" integer NOT NULL,
                                                                                    "isActive" boolean DEFAULT true NOT NULL,
                                                                                                                    "importHistoryId" integer);


CREATE TABLE "onDemand".category ( name text NOT NULL,
                                             id integer NOT NULL);



CREATE VIEW "onDemand"."collectionDetails" AS
SELECT collection.id,
       collection.name,
       collection."startTime",
       collection."endTime",
       collection.rrule,
       "onDemand"."numberOfCategories"(collection.id) AS "categoriesCount",
       "onDemand"."numberOfProducts"(collection.id) AS "productsCount",
       collection.created_at,
       collection.updated_at
FROM "onDemand".collection;



CREATE TABLE "onDemand"."collection_productCategory" ( id integer NOT NULL,
                                                                  "collectionId" integer NOT NULL,
                                                                                         "productCategoryName" text NOT NULL,
                                                                                                                    "position" numeric, "importHistoryId" integer);


CREATE TABLE "onDemand".modifier ( id integer NOT NULL,
                                              name text NOT NULL,
                                                        "importHistoryId" integer);


CREATE TABLE "onDemand"."modifierCategory" ( id integer NOT NULL,
                                                        name text NOT NULL,
                                                                  type text DEFAULT 'single'::text NOT NULL,
                                                                                                   "isVisible" boolean DEFAULT true NOT NULL,
                                                                                                                                    "isRequired" boolean DEFAULT true NOT NULL,
                                                                                                                                                                      limits jsonb DEFAULT '{"max": null, "min": 1}'::jsonb,
                                                                                                                                                                                           "modifierTemplateId" integer NOT NULL);




CREATE TABLE "order"."cartItem" ( id integer NOT NULL,
                                             "cartId" integer, "parentCartItemId" integer, "isModifier" boolean DEFAULT false NOT NULL,
                                                                                                                              "productId" integer, "productOptionId" integer, "comboProductComponentId" integer, "customizableProductComponentId" integer, "simpleRecipeYieldId" integer, "sachetItemId" integer,
                                                                                                                                                                                                                                                                                                                                                      "unitPrice" numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                    "refundPrice" numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                    "stationId" integer, "labelTemplateId" integer, "packagingId" integer, "instructionCardTemplateId" integer, "status" text DEFAULT 'PENDING'::text NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              "position" numeric, created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    updated_at timestamp with time zone DEFAULT now() NOT NULL,


                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             accuracy numeric DEFAULT 5,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      "ingredientSachetId" integer, "isAddOn" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    "addOnLabel" text, "addOnPrice" numeric, "isAutoAdded" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 "inventoryProductBundleId" integer, "subscriptionOccurenceProductId" integer, "subscriptionOccurenceAddOnProductId" integer,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           "modifierOptionId" integer, "subRecipeYieldId" integer);


CREATE TABLE products."productOptionType" ( title text NOT NULL,
                                                       description text, "orderMode" text NOT NULL);


CREATE VIEW products."productOptionView" AS
SELECT "productOption".id,
       "productOption"."productId",
       "productOption".label,
       "productOption"."modifierId",
       "productOption"."operationConfigId",
       "productOption"."simpleRecipeYieldId",
       "productOption"."supplierItemId",
       "productOption"."sachetItemId",
       "productOption"."position",
       "productOption".created_at,
       "productOption".updated_at,
       "productOption".price,
       "productOption".discount,
       "productOption".quantity,
       "productOption".type,
       "productOption"."isArchived",
       "productOption"."inventoryProductBundleId",
       btrim(concat(
                        (SELECT product.name
                         FROM products.product
                         WHERE (product.id = "productOption"."productId")), ' - ', "productOption".label)) AS "displayName",

    (SELECT ((product.assets -> 'images'::text) -> 0)
     FROM products.product
     WHERE (product.id = "productOption"."productId")) AS "displayImage"
FROM products."productOption";


CREATE TABLE "simpleRecipe"."simpleRecipeComponent_productOptionType" ( "simpleRecipeComponentId" integer NOT NULL,
                                                                                                          "productOptionType" text NOT NULL,
                                                                                                                                   "orderMode" text NOT NULL);


CREATE VIEW "simpleRecipe"."simpleRecipeYieldView" AS
SELECT "simpleRecipeYield".id,
       "simpleRecipeYield"."simpleRecipeId",
       "simpleRecipeYield".yield,
       "simpleRecipeYield"."isArchived",
       (
            (SELECT "simpleRecipe".name
             FROM "simpleRecipe"."simpleRecipe"
             WHERE ("simpleRecipe".id = "simpleRecipeYield"."simpleRecipeId")))::text AS "displayName",
       (("simpleRecipeYield".yield -> 'serving'::text))::integer AS serving
FROM "simpleRecipe"."simpleRecipeYield";


CREATE TABLE "simpleRecipe"."simpleRecipeYield_ingredientSachet" ( "recipeYieldId" integer NOT NULL,
                                                                                           "ingredientSachetId" integer, "isVisible" boolean DEFAULT true NOT NULL,
                                                                                                                                                          "slipName" text, "isSachetValid" boolean, "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                       "simpleRecipeIngredientProcessingId" integer NOT NULL,
                                                                                                                                                                                                                                                                                    "subRecipeYieldId" integer);


CREATE TABLE "simpleRecipe"."simpleRecipe_productOptionType" ( "simpleRecipeId" integer NOT NULL,
                                                                                        "productOptionTypeTitle" text NOT NULL,
                                                                                                                      "orderMode" text NOT NULL);



CREATE TABLE "order"."orderMode" ( title text NOT NULL,
                                              description text, assets jsonb,
                                                                "validWhen" text);


CREATE TABLE "order"."orderStatusEnum" ( value text NOT NULL,
                                                    description text NOT NULL,
                                                                     index integer, title text);



CREATE TABLE "order"."thirdPartyOrder" ( source text NOT NULL,
                                                     "thirdPartyOrderId" text NOT NULL,
                                                                              "parsedData" jsonb DEFAULT '{}'::jsonb,
                                                                                                         id integer NOT NULL);



CREATE TABLE packaging.packaging ( id integer NOT NULL,
                                              name text NOT NULL,
                                                        "packagingSku" text, "supplierId" integer, "unitPrice" numeric, "parLevel" integer, "maxLevel" integer, "onHand" integer DEFAULT 0 NOT NULL,
                                                                                                                                                                                           "unitQuantity" numeric, "caseQuantity" numeric, "minOrderValue" numeric, "leadTime" jsonb,
                                                                                                                                                                                                                                                                    "isAvailable" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                        type text, awaiting numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                              committed numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                          consumed numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                     assets jsonb,
                                                                                                                                                                                                                                                                                                                                                                                                     "mandiPackagingId" integer, length numeric, width numeric, height numeric, gusset numeric, thickness numeric, "LWHUnit" text DEFAULT 'mm'::text,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          "loadCapacity" numeric, "loadVolume" numeric, "packagingSpecificationsId" integer NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            weight numeric);


CREATE TABLE packaging."packagingSpecifications" ( id integer NOT NULL,
                                                              "innerWaterResistant" boolean, "outerWaterResistant" boolean, "innerGreaseResistant" boolean, "outerGreaseResistant" boolean, microwaveable boolean, "maxTemperatureInFahrenheit" boolean, recyclable boolean, compostable boolean, recycled boolean, "fdaCompliant" boolean, compressibility boolean, opacity text, "mandiPackagingId" integer, "packagingMaterial" text);




CREATE TABLE products."inventoryProductBundle" ( id integer NOT NULL,
                                                            label text NOT NULL);


CREATE TABLE products."inventoryProductBundleSachet" ( id integer NOT NULL,
                                                                  "inventoryProductBundleId" integer NOT NULL,
                                                                                                     "supplierItemId" integer, "sachetItemId" integer, "bulkItemId" integer, "bulkItemQuantity" numeric);


CREATE TABLE products."productConfigTemplate" ( id integer NOT NULL,
                                                           template jsonb NOT NULL,
                                                                          "isDefault" boolean, "isMandatory" boolean);



CREATE TABLE products."productDataConfig" ( "productId" integer NOT NULL,
                                                                "productConfigTemplateId" integer NOT NULL,
                                                                                                  data jsonb NOT NULL);




CREATE TABLE products."productType" ( title text NOT NULL,
                                                 "displayName" text NOT NULL);


CREATE TABLE safety."safetyCheck" ( id integer NOT NULL,
                                               created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                 updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                   "isVisibleOnStore" boolean NOT NULL);


CREATE TABLE safety."safetyCheckPerUser" ( id integer NOT NULL,
                                                      "SafetyCheckId" integer NOT NULL,
                                                                              "userId" integer NOT NULL,
                                                                                               "usesMask" boolean NOT NULL,
                                                                                                                  "usesSanitizer" boolean NOT NULL,
                                                                                                                                          created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                            temperature numeric);



CREATE TABLE settings.app ( id integer NOT NULL,
                                       title text NOT NULL,
                                                  created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                    updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                      icon text, route text);


CREATE TABLE settings."appPermission" ( id integer NOT NULL,
                                                   "appId" integer NOT NULL,
                                                                   route text NOT NULL,
                                                                              title text NOT NULL,
                                                                                         "fallbackMessage" text);



CREATE TABLE settings."appSettings" ( id integer NOT NULL,
                                                 app text NOT NULL,
                                                          type text NOT NULL,
                                                                    identifier text NOT NULL,
                                                                                    value jsonb NOT NULL);




CREATE TABLE settings.app_module ( "appTitle" text NOT NULL,
                                                   "moduleTitle" text NOT NULL);



CREATE TABLE settings."organizationSettings" ( title text NOT NULL,
                                                          value text NOT NULL);


CREATE TABLE settings.role ( id integer NOT NULL,
                                        title text NOT NULL,
                                                   created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                     updated_at timestamp with time zone DEFAULT now() NOT NULL);


CREATE TABLE settings.role_app ( id integer NOT NULL,
                                            "roleId" integer NOT NULL,
                                                             "appId" integer NOT NULL,
                                                                             created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                               updated_at timestamp with time zone DEFAULT now() NOT NULL);


CREATE TABLE settings."role_appPermission" ( "appPermissionId" integer NOT NULL,
                                                                       "role_appId" integer NOT NULL,
                                                                                            value boolean NOT NULL);



CREATE TABLE settings.station ( id integer NOT NULL,
                                           name text NOT NULL,
                                                     "defaultLabelPrinterId" integer, "defaultKotPrinterId" integer, "defaultScaleId" integer, "isArchived" boolean DEFAULT false NOT NULL);



CREATE TABLE settings.station_kot_printer ( "stationId" integer NOT NULL,
                                                                "printNodeId" integer NOT NULL,
                                                                                      active boolean DEFAULT true NOT NULL);


CREATE TABLE settings.station_label_printer ( "stationId" integer NOT NULL,
                                                                  "printNodeId" integer NOT NULL,
                                                                                        active boolean DEFAULT true NOT NULL);


CREATE TABLE settings.station_user ( "userKeycloakId" text NOT NULL,
                                                           "stationId" integer NOT NULL,
                                                                               active boolean DEFAULT true NOT NULL);


CREATE TABLE settings."user" ( id integer NOT NULL,
                                          "firstName" text, "lastName" text, email text, "tempPassword" text, "phoneNo" text, "keycloakId" text);



CREATE TABLE settings.user_role ( id integer NOT NULL,
                                             "userId" text NOT NULL,
                                                           "roleId" integer NOT NULL,
                                                                            created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                              updated_at timestamp with time zone DEFAULT now() NOT NULL);



CREATE TABLE "simpleRecipe"."simpleRecipe_ingredient_processing" ( "processingId" integer, id integer NOT NULL,
                                                                                                      "simpleRecipeId" integer, "ingredientId" integer, "position" integer, "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                               "subRecipeId" integer);



CREATE TABLE subscription."brand_subscriptionTitle" ( "brandId" integer NOT NULL,
                                                                        "subscriptionTitleId" integer NOT NULL,
                                                                                                      "isActive" boolean DEFAULT true NOT NULL,
                                                                                                                                      "allowAutoSelectOptOut" boolean DEFAULT true NOT NULL);


CREATE TABLE subscription.subscription ( id integer NOT NULL,
                                                    "subscriptionItemCountId" integer NOT NULL,
                                                                                      rrule text NOT NULL,
                                                                                                 "metaDetails" jsonb,
                                                                                                 "cutOffTime" time without time zone,
                                                                                                                                "leadTime" jsonb,
                                                                                                                                "startTime" jsonb DEFAULT '{"unit": "days", "value": 28}'::jsonb,
                                                                                                                                                          "startDate" date, "endDate" date, "defaultSubscriptionAutoSelectOption" text, "reminderSettings" jsonb DEFAULT '{"template": "Subscription Reminder Email", "hoursBefore": [24]}'::jsonb);


CREATE TABLE subscription."subscriptionAutoSelectOption" ( "methodName" text NOT NULL,
                                                                             "displayName" text NOT NULL);



CREATE VIEW subscription."subscriptionOccurenceView" AS
SELECT (now() < "subscriptionOccurence"."cutoffTimeStamp") AS "isValid",
       "subscriptionOccurence".id,
       (now() > "subscriptionOccurence"."startTimeStamp") AS "isVisible"
FROM subscription."subscriptionOccurence";


CREATE TABLE subscription."subscriptionPickupOption" ( id integer NOT NULL,
                                                                  "time" jsonb DEFAULT '{"to": "", "from": ""}'::jsonb NOT NULL,
                                                                                                                       address jsonb DEFAULT '{"lat": "", "lng": "", "city": "", "label": "", "line1": "", "line2": "", "notes": "", "state": "", "country": "", "zipcode": ""}'::jsonb NOT NULL,
                                                                                                                                                                                                                                                                                        created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                                                                                                                                          updated_at timestamp with time zone DEFAULT now() NOT NULL);


CREATE TABLE subscription.subscription_zipcode ( "subscriptionId" integer NOT NULL,
                                                                          zipcode text NOT NULL,
                                                                                       "deliveryPrice" numeric DEFAULT 0 NOT NULL,
                                                                                                                         "isActive" boolean DEFAULT true,
                                                                                                                                                    "deliveryTime" jsonb DEFAULT '{"to": "", "from": ""}'::jsonb,
                                                                                                                                                                                 "subscriptionPickupOptionId" integer, "isDeliveryActive" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                               "isPickupActive" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                      "defaultAutoSelectFulfillmentMode" text DEFAULT 'DELIVERY'::text NOT NULL);


CREATE TABLE website.website ( id integer NOT NULL,
                                          "brandId" integer NOT NULL,
                                                            "faviconUrl" text, created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                 updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                   published boolean DEFAULT false NOT NULL);


CREATE TABLE website."websitePage" ( id integer NOT NULL,
                                                "websiteId" integer NOT NULL,
                                                                    route text NOT NULL,
                                                                               "internalPageName" text NOT NULL,
                                                                                                       published boolean DEFAULT false NOT NULL,
                                                                                                                                       "isArchived" boolean DEFAULT false NOT NULL);


CREATE TABLE website."websitePageModule" ( id integer NOT NULL,
                                                      "websitePageId" integer NOT NULL,
                                                                              "moduleType" text NOT NULL,
                                                                                                "fileId" integer, "internalModuleIdentifier" text, "templateId" integer, "position" numeric, "visibilityConditionId" integer, config jsonb,
                                                                                                                                                                                                                              config2 json,
                                                                                                                                                                                                                              config3 jsonb,
                                                                                                                                                                                                                              config4 text);


ALTER TABLE ONLY brands.brand
ALTER COLUMN id
SET DEFAULT defaultId('brands', 'brand', 'id');


ALTER TABLE ONLY brands."storeSetting"
ALTER COLUMN id
SET DEFAULT defaultId('brands', 'storeSetting', 'id');


ALTER TABLE ONLY brands."subscriptionStoreSetting"
ALTER COLUMN id
SET DEFAULT defaultId('brands', 'storeSetting', 'id');


ALTER TABLE ONLY crm.brand_customer
ALTER COLUMN id
SET DEFAULT defaultId('crm', 'brand_customer', 'id');


ALTER TABLE ONLY crm.campaign
ALTER COLUMN id
SET DEFAULT defaultId('crm', 'campaign', 'id');


ALTER TABLE ONLY crm."campaignType"
ALTER COLUMN id
SET DEFAULT defaultId('crm', 'campaignType', 'id');


ALTER TABLE ONLY crm.coupon
ALTER COLUMN id
SET DEFAULT defaultId('crm', 'coupon', 'id');


ALTER TABLE ONLY crm.customer
ALTER COLUMN id
SET DEFAULT defaultId('crm', 'customer', 'id');


ALTER TABLE ONLY crm."customerReferral"
ALTER COLUMN id
SET DEFAULT defaultId('crm', 'customerReferral', 'id');


ALTER TABLE ONLY crm.fact
ALTER COLUMN id
SET DEFAULT defaultId('crm', 'fact', 'id');


ALTER TABLE ONLY crm."loyaltyPoint"
ALTER COLUMN id
SET DEFAULT defaultId('crm', 'loyaltyPoint', 'id');


ALTER TABLE ONLY crm."loyaltyPointTransaction"
ALTER COLUMN id
SET DEFAULT defaultId('crm', 'loyaltyPointTransaction', 'id');


ALTER TABLE ONLY crm."orderCart_rewards"
ALTER COLUMN id
SET DEFAULT defaultId('crm', 'orderCart_rewards', 'id');


ALTER TABLE ONLY crm.reward
ALTER COLUMN id
SET DEFAULT defaultId('crm', 'reward', 'id');


ALTER TABLE ONLY crm."rewardHistory"
ALTER COLUMN id
SET DEFAULT defaultId('crm', 'rewardHistory', 'id');


ALTER TABLE ONLY crm."rewardType"
ALTER COLUMN id
SET DEFAULT defaultId('crm', 'rewardType', 'id');


ALTER TABLE ONLY crm.wallet
ALTER COLUMN id
SET DEFAULT defaultId('crm', 'wallet', 'id');


ALTER TABLE ONLY crm."walletTransaction"
ALTER COLUMN id
SET DEFAULT defaultId('crm', 'walletTransaction', 'id');


ALTER TABLE ONLY "deviceHub".config
ALTER COLUMN id
SET DEFAULT defaultId('deviceHub', 'config', 'id');


ALTER TABLE ONLY "deviceHub"."labelTemplate"
ALTER COLUMN id
SET DEFAULT defaultId('deviceHub', 'labelTemplate', 'id');


ALTER TABLE ONLY "deviceHub".scale
ALTER COLUMN id
SET DEFAULT defaultId('deviceHub', 'scale', 'id');


ALTER TABLE ONLY editor.block
ALTER COLUMN id
SET DEFAULT defaultId('editor', 'block', 'id');


ALTER TABLE ONLY editor."cssFileLinks"
ALTER COLUMN id
SET DEFAULT defaultId('editor', 'cssFileLinks', 'id');


ALTER TABLE ONLY editor.file
ALTER COLUMN id
SET DEFAULT defaultId('editor', 'file', 'id');


ALTER TABLE ONLY editor."jsFileLinks"
ALTER COLUMN id
SET DEFAULT defaultId('editor', 'jsFileLinks', 'id');


ALTER TABLE ONLY editor.template
ALTER COLUMN id
SET DEFAULT defaultId('editor', 'template', 'id');


ALTER TABLE ONLY fulfilment.charge
ALTER COLUMN id
SET DEFAULT defaultId('fulfilment', 'charge', 'id');


ALTER TABLE ONLY fulfilment."deliveryService"
ALTER COLUMN id
SET DEFAULT defaultId('fulfilment', 'deliveryService', 'id');


ALTER TABLE ONLY fulfilment."mileRange"
ALTER COLUMN id
SET DEFAULT defaultId('fulfilment', 'mileRange', 'id');


ALTER TABLE ONLY fulfilment.recurrence
ALTER COLUMN id
SET DEFAULT defaultId('fulfilment', 'recurrence', 'id');


ALTER TABLE ONLY fulfilment."timeSlot"
ALTER COLUMN id
SET DEFAULT defaultId('fulfilment', 'timeSlot', 'id');


ALTER TABLE ONLY imports.import
ALTER COLUMN id
SET DEFAULT defaultId('imports', 'import', 'id');


ALTER TABLE ONLY imports."importHistory"
ALTER COLUMN id
SET DEFAULT defaultId('imports', 'importHistory', 'id');


ALTER TABLE ONLY ingredient.ingredient
ALTER COLUMN id
SET DEFAULT defaultId('ingredient', 'ingredient', 'id');


ALTER TABLE ONLY ingredient."ingredientProcessing"
ALTER COLUMN id
SET DEFAULT defaultId('ingredient', 'ingredientProcessing', 'id');


ALTER TABLE ONLY ingredient."ingredientSachet"
ALTER COLUMN id
SET DEFAULT defaultId('ingredient', 'ingredientSachet', 'id');


ALTER TABLE ONLY ingredient."modeOfFulfillment"
ALTER COLUMN id
SET DEFAULT defaultId('ingredient', 'modeOfFulfillment', 'id');


ALTER TABLE ONLY insights.chart
ALTER COLUMN id
SET DEFAULT defaultId('insights', 'chart', 'id');


ALTER TABLE ONLY instructions."instructionSet"
ALTER COLUMN id
SET DEFAULT defaultId('instructions', 'instructionSet', 'id');


ALTER TABLE ONLY instructions."instructionStep"
ALTER COLUMN id
SET DEFAULT defaultId('instructions', 'instructionStep', 'id');


ALTER TABLE ONLY inventory."bulkItem"
ALTER COLUMN id
SET DEFAULT defaultId('inventory', 'bulkItem', 'id');


ALTER TABLE ONLY inventory."bulkItemHistory"
ALTER COLUMN id
SET DEFAULT defaultId('inventory', 'bulkItemHistory', 'id');


ALTER TABLE ONLY inventory."bulkItem_unitConversion"
ALTER COLUMN id
SET DEFAULT defaultId('inventory', 'bulkItem_unitConversion', 'id');


ALTER TABLE ONLY inventory."bulkWorkOrder"
ALTER COLUMN id
SET DEFAULT defaultId('inventory', 'bulkWorkOrder', 'id');


ALTER TABLE ONLY inventory."packagingHistory"
ALTER COLUMN id
SET DEFAULT defaultId('inventory', 'packagingHistory', 'id');


ALTER TABLE ONLY inventory."purchaseOrderItem"
ALTER COLUMN id
SET DEFAULT defaultId('inventory', 'purchaseOrderItem', 'id');


ALTER TABLE ONLY inventory."sachetItem"
ALTER COLUMN id
SET DEFAULT defaultId('inventory', 'sachetItem', 'id');


ALTER TABLE ONLY inventory."sachetItemHistory"
ALTER COLUMN id
SET DEFAULT defaultId('inventory', 'sachetItemHistory', 'id');


ALTER TABLE ONLY inventory."sachetWorkOrder"
ALTER COLUMN id
SET DEFAULT defaultId('inventory', 'sachetWorkOrder', 'id');


ALTER TABLE ONLY inventory.supplier
ALTER COLUMN id
SET DEFAULT defaultId('inventory', 'supplier', 'id');


ALTER TABLE ONLY inventory."supplierItem"
ALTER COLUMN id
SET DEFAULT defaultId('inventory', 'supplierItem', 'id');


ALTER TABLE ONLY inventory."supplierItem_unitConversion"
ALTER COLUMN id
SET DEFAULT defaultId('inventory', 'supplierItem_unitConversion', 'id');


ALTER TABLE ONLY inventory."unitConversionByBulkItem"
ALTER COLUMN id
SET DEFAULT defaultId('inventory', 'unitConversionByBulkItem', 'id');


ALTER TABLE ONLY master."accompanimentType"
ALTER COLUMN id
SET DEFAULT defaultId('master', 'accompanimentType', 'id');


ALTER TABLE ONLY master."allergenName"
ALTER COLUMN id
SET DEFAULT defaultId('master', 'allergenName', 'id');


ALTER TABLE ONLY master."cuisineName"
ALTER COLUMN id
SET DEFAULT defaultId('master', 'cuisineName', 'id');


ALTER TABLE ONLY master."processingName"
ALTER COLUMN id
SET DEFAULT defaultId('master', 'processingName', 'id');


ALTER TABLE ONLY master.unit
ALTER COLUMN id
SET DEFAULT defaultId('master', 'unit', 'id');


ALTER TABLE ONLY master."unitConversion"
ALTER COLUMN id
SET DEFAULT defaultId('master', 'unitConversion', 'id');


ALTER TABLE ONLY "onDemand".category
ALTER COLUMN id
SET DEFAULT defaultId('onDemand', 'category', 'id');


ALTER TABLE ONLY "onDemand".collection
ALTER COLUMN id
SET DEFAULT defaultId('onDemand', 'collection', 'id');


ALTER TABLE ONLY "onDemand"."collection_productCategory"
ALTER COLUMN id
SET DEFAULT defaultId('onDemand', 'collection_productCategory', 'id');


ALTER TABLE ONLY "onDemand"."collection_productCategory_product"
ALTER COLUMN id
SET DEFAULT defaultId('onDemand', 'collection_productCategory_product', 'id');


ALTER TABLE ONLY "onDemand".menu
ALTER COLUMN id
SET DEFAULT defaultId('onDemand', 'menu', 'id');


ALTER TABLE ONLY "onDemand".modifier
ALTER COLUMN id
SET DEFAULT defaultId('onDemand', 'modifier', 'id');


ALTER TABLE ONLY "onDemand"."modifierCategory"
ALTER COLUMN id
SET DEFAULT defaultId('onDemand', 'modifierCategory', 'id');


ALTER TABLE ONLY "onDemand"."modifierCategoryOption"
ALTER COLUMN id
SET DEFAULT defaultId('onDemand', 'modifierCategoryOption', 'id');


ALTER TABLE ONLY "onDemand"."storeData"
ALTER COLUMN id
SET DEFAULT defaultId('onDemand', 'storeData', 'id');

ALTER TABLE ONLY "order".cart
ALTER COLUMN id
SET DEFAULT defaultId('order', 'cart', 'id');


ALTER TABLE ONLY "order"."cartItem"
ALTER COLUMN id
SET DEFAULT defaultId('order', 'cartItem', 'id');


ALTER TABLE ONLY "order"."order"
ALTER COLUMN id
SET DEFAULT defaultId('order', 'order', 'id');


ALTER TABLE ONLY "order"."thirdPartyOrder"
ALTER COLUMN id
SET DEFAULT defaultId('order', 'thirdPartyOrder', 'id');


ALTER TABLE ONLY packaging.packaging
ALTER COLUMN id
SET DEFAULT defaultId('packaging', 'packaging', 'id');


ALTER TABLE ONLY packaging."packagingSpecifications"
ALTER COLUMN id
SET DEFAULT defaultId('packaging', 'packagingSpecifications', 'id');


ALTER TABLE ONLY products."comboProductComponent"
ALTER COLUMN id
SET DEFAULT defaultId('products', 'comboProductComponent', 'id');


ALTER TABLE ONLY products."customizableProductComponent"
ALTER COLUMN id
SET DEFAULT defaultId('products', 'customizableProductComponent', 'id');


ALTER TABLE ONLY products."inventoryProductBundle"
ALTER COLUMN id
SET DEFAULT defaultId('products', 'inventoryProductBundle', 'id');


ALTER TABLE ONLY products."inventoryProductBundleSachet"
ALTER COLUMN id
SET DEFAULT defaultId('products', 'inventoryProductBundleSachet', 'id');


ALTER TABLE ONLY products.product
ALTER COLUMN id
SET DEFAULT defaultId('products', 'product', 'id');


ALTER TABLE ONLY products."productConfigTemplate"
ALTER COLUMN id
SET DEFAULT defaultId('products', 'productConfigTemplate', 'id');


ALTER TABLE ONLY products."productOption"
ALTER COLUMN id
SET DEFAULT defaultId('products', 'productOption', 'id');


ALTER TABLE ONLY rules.conditions
ALTER COLUMN id
SET DEFAULT defaultId('rules', 'conditions', 'id');


ALTER TABLE ONLY safety."safetyCheck"
ALTER COLUMN id
SET DEFAULT defaultId('safety', 'safetyCheck', 'id');


ALTER TABLE ONLY safety."safetyCheckPerUser"
ALTER COLUMN id
SET DEFAULT defaultId('safety', 'safetyCheckPerUser', 'id');


ALTER TABLE ONLY settings.app
ALTER COLUMN id
SET DEFAULT defaultId('settings', 'app', 'id');


ALTER TABLE ONLY settings."appPermission"
ALTER COLUMN id
SET DEFAULT defaultId('settings', 'appPermission', 'id');


ALTER TABLE ONLY settings."appSettings"
ALTER COLUMN id
SET DEFAULT defaultId('settings', 'appSettings', 'id');


ALTER TABLE ONLY settings."operationConfig"
ALTER COLUMN id
SET DEFAULT defaultId('settings', 'operationConfig', 'id');


ALTER TABLE ONLY settings.role
ALTER COLUMN id
SET DEFAULT defaultId('settings', 'role', 'id');


ALTER TABLE ONLY settings.role_app
ALTER COLUMN id
SET DEFAULT defaultId('settings', 'role_app', 'id');


ALTER TABLE ONLY settings.station
ALTER COLUMN id
SET DEFAULT defaultId('settings', 'station', 'id');


ALTER TABLE ONLY settings."user"
ALTER COLUMN id
SET DEFAULT defaultId('settings', 'user', 'id');


ALTER TABLE ONLY settings.user_role
ALTER COLUMN id
SET DEFAULT defaultId('settings', 'user_role', 'id');


ALTER TABLE ONLY "simpleRecipe"."simpleRecipe"
ALTER COLUMN id
SET DEFAULT defaultId('simpleRecipe', 'simpleRecipe', 'id');


ALTER TABLE ONLY "simpleRecipe"."simpleRecipeYield"
ALTER COLUMN id
SET DEFAULT defaultId('simpleRecipe', 'simpleRecipeYield', 'id');


ALTER TABLE ONLY "simpleRecipe"."simpleRecipe_ingredient_processing"
ALTER COLUMN id
SET DEFAULT defaultId('simpleRecipe', 'simpleRecipe_ingredient_processing', 'id');


ALTER TABLE ONLY subscription.subscription
ALTER COLUMN id
SET DEFAULT defaultId('subscription', 'subscription', 'id');


ALTER TABLE ONLY subscription."subscriptionItemCount"
ALTER COLUMN id
SET DEFAULT defaultId('subscription', 'subscriptionItemCount', 'id');


ALTER TABLE ONLY subscription."subscriptionOccurence"
ALTER COLUMN id
SET DEFAULT defaultId('subscription', 'subscriptionOccurence', 'id');


ALTER TABLE ONLY subscription."subscriptionOccurence_addOn"
ALTER COLUMN id
SET DEFAULT defaultId('subscription', 'subscriptionOccurence_addOn', 'id');


ALTER TABLE ONLY subscription."subscriptionOccurence_product"
ALTER COLUMN id
SET DEFAULT defaultId('subscription', 'subscriptionOccurence_product', 'id');


ALTER TABLE ONLY subscription."subscriptionPickupOption"
ALTER COLUMN id
SET DEFAULT defaultId('subscription', 'subscriptionPickupOption', 'id');


ALTER TABLE ONLY subscription."subscriptionServing"
ALTER COLUMN id
SET DEFAULT defaultId('subscription', 'subscriptionServing', 'id');


ALTER TABLE ONLY subscription."subscriptionTitle"
ALTER COLUMN id
SET DEFAULT defaultId('subscription', 'subscriptionTitle', 'id');


ALTER TABLE ONLY website.website
ALTER COLUMN id
SET DEFAULT defaultId('website', 'website', 'id');


ALTER TABLE ONLY website."websitePage"
ALTER COLUMN id
SET DEFAULT defaultId('website', 'websitePage', 'id');


ALTER TABLE ONLY website."websitePageModule"
ALTER COLUMN id
SET DEFAULT defaultId('website', 'websitePageModule', 'id');


ALTER TABLE ONLY brands."brand_paymentPartnership" ADD CONSTRAINT "brand_paymentPartnership_pkey" PRIMARY KEY ("brandId",
                                                                                                               "paymentPartnershipId");


ALTER TABLE ONLY brands.brand ADD CONSTRAINT brand_pkey PRIMARY KEY (id);


ALTER TABLE ONLY brands."brand_subscriptionStoreSetting" ADD CONSTRAINT "brand_subscriptionStoreSetting_pkey" PRIMARY KEY ("brandId",
                                                                                                                           "subscriptionStoreSettingId");


ALTER TABLE ONLY brands.brand ADD CONSTRAINT shop_domain_key UNIQUE (domain);


ALTER TABLE ONLY brands.brand ADD CONSTRAINT shop_id_key UNIQUE (id);


ALTER TABLE ONLY brands."brand_storeSetting" ADD CONSTRAINT "shop_storeSetting_pkey" PRIMARY KEY ("brandId",
                                                                                                  "storeSettingId");


ALTER TABLE ONLY brands."storeSetting" ADD CONSTRAINT "storeSetting_identifier_key" UNIQUE (identifier);


ALTER TABLE ONLY brands."storeSetting" ADD CONSTRAINT "storeSetting_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY brands."subscriptionStoreSetting" ADD CONSTRAINT "subscriptionStoreSetting_identifier_key" UNIQUE (identifier);


ALTER TABLE ONLY brands."subscriptionStoreSetting" ADD CONSTRAINT "subscriptionStoreSetting_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY content.identifier ADD CONSTRAINT identifier_pkey PRIMARY KEY (title);


ALTER TABLE ONLY content.page ADD CONSTRAINT page_pkey PRIMARY KEY (title);


ALTER TABLE ONLY content."subscriptionDivIds" ADD CONSTRAINT "subscriptionDivIds_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY content.template ADD CONSTRAINT template_pkey PRIMARY KEY (id);


ALTER TABLE ONLY crm.brand_customer ADD CONSTRAINT "brandCustomer_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY crm.brand_campaign ADD CONSTRAINT brand_campaign_pkey PRIMARY KEY ("brandId",
                                                                                    "campaignId");


ALTER TABLE ONLY crm.brand_coupon ADD CONSTRAINT brand_coupon_pkey PRIMARY KEY ("brandId",
                                                                                "couponId");


ALTER TABLE ONLY crm."campaignType" ADD CONSTRAINT "campaignType_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY crm."campaignType" ADD CONSTRAINT "campaignType_value_key" UNIQUE (value);


ALTER TABLE ONLY crm.campaign ADD CONSTRAINT campaign_pkey PRIMARY KEY (id);


ALTER TABLE ONLY crm.coupon ADD CONSTRAINT coupon_code_key UNIQUE (code);


ALTER TABLE ONLY crm.coupon ADD CONSTRAINT coupon_pkey PRIMARY KEY (id);


ALTER TABLE ONLY crm."customerData" ADD CONSTRAINT "customerData_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY crm."customerReferral" ADD CONSTRAINT "customerReferral_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY crm."customerReferral" ADD CONSTRAINT "customerReferral_referralCode_key" UNIQUE ("referralCode");


ALTER TABLE ONLY crm.customer ADD CONSTRAINT "customer_dailyKeyUserId_key" UNIQUE ("keycloakId");


ALTER TABLE ONLY crm.customer ADD CONSTRAINT customer_email_key UNIQUE (email);


ALTER TABLE ONLY crm.customer ADD CONSTRAINT customer_id_key UNIQUE (id);


ALTER TABLE ONLY crm.customer ADD CONSTRAINT customer_pkey PRIMARY KEY ("keycloakId");


ALTER TABLE ONLY crm.fact ADD CONSTRAINT fact_id_key UNIQUE (id);


ALTER TABLE ONLY crm."loyaltyPointTransaction" ADD CONSTRAINT "loyaltyPointTransaction_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY crm."loyaltyPoint" ADD CONSTRAINT "loyaltyPoint_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY crm."orderCart_rewards" ADD CONSTRAINT "orderCart_rewards_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY crm."rewardHistory" ADD CONSTRAINT "rewardHistory_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY crm."rewardType_campaignType" ADD CONSTRAINT "rewardType_campaignType_pkey" PRIMARY KEY ("rewardTypeId",
                                                                                                          "campaignTypeId");


ALTER TABLE ONLY crm."rewardType" ADD CONSTRAINT "rewardType_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY crm.reward ADD CONSTRAINT reward_pkey PRIMARY KEY (id);


ALTER TABLE ONLY crm."walletTransaction" ADD CONSTRAINT "walletTransaction_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY crm.wallet ADD CONSTRAINT wallet_pkey PRIMARY KEY (id);


ALTER TABLE ONLY "deviceHub".computer ADD CONSTRAINT computer_pkey PRIMARY KEY ("printNodeId");


ALTER TABLE ONLY "deviceHub".config ADD CONSTRAINT config_name_key UNIQUE (name);


ALTER TABLE ONLY "deviceHub".config ADD CONSTRAINT config_pkey PRIMARY KEY (id);


ALTER TABLE ONLY "deviceHub"."labelTemplate" ADD CONSTRAINT "labelTemplate_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY "deviceHub"."printerType" ADD CONSTRAINT "printerType_pkey" PRIMARY KEY (type);


ALTER TABLE ONLY "deviceHub".printer ADD CONSTRAINT printer_pkey PRIMARY KEY ("printNodeId");


ALTER TABLE ONLY "deviceHub".scale ADD CONSTRAINT scale_pkey PRIMARY KEY ("computerId",
                                                                          "deviceName",
                                                                          "deviceNum");


ALTER TABLE ONLY editor.block ADD CONSTRAINT "block_fileId_key" UNIQUE ("fileId");


ALTER TABLE ONLY editor.block ADD CONSTRAINT block_path_key UNIQUE (path);


ALTER TABLE ONLY editor.block ADD CONSTRAINT block_pkey PRIMARY KEY (id);


ALTER TABLE ONLY editor."cssFileLinks" ADD CONSTRAINT "cssFileLinks_id_key" UNIQUE (id);


ALTER TABLE ONLY editor."cssFileLinks" ADD CONSTRAINT "cssFileLinks_pkey" PRIMARY KEY ("guiFileId",
                                                                                       "cssFileId");


ALTER TABLE ONLY editor."jsFileLinks" ADD CONSTRAINT "jsFileLinks_id_key" UNIQUE (id);


ALTER TABLE ONLY editor."jsFileLinks" ADD CONSTRAINT "jsFileLinks_pkey" PRIMARY KEY ("guiFileId",
                                                                                     "jsFileId");


ALTER TABLE ONLY editor."linkedFiles" ADD CONSTRAINT "linkedFiles_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY editor."priorityFuncTable" ADD CONSTRAINT "priorityFuncTable_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY editor.file ADD CONSTRAINT template_path_key UNIQUE (path);


ALTER TABLE ONLY editor.file ADD CONSTRAINT template_pkey PRIMARY KEY (id);


ALTER TABLE ONLY editor.template ADD CONSTRAINT template_pkey1 PRIMARY KEY (id);


ALTER TABLE ONLY fulfilment.brand_recurrence ADD CONSTRAINT brand_recurrence_pkey PRIMARY KEY ("brandId",
                                                                                               "recurrenceId");


ALTER TABLE ONLY fulfilment.charge ADD CONSTRAINT charge_pkey PRIMARY KEY (id);


ALTER TABLE ONLY fulfilment."deliveryPreferenceByCharge" ADD CONSTRAINT "deliveryPreferenceByCharge_pkey" PRIMARY KEY ("clauseId",
                                                                                                                       "chargeId");


ALTER TABLE ONLY fulfilment."deliveryPreferenceByCharge" ADD CONSTRAINT "deliveryPreferenceByCharge_priority_key" UNIQUE (priority);


ALTER TABLE ONLY fulfilment."deliveryService" ADD CONSTRAINT "deliveryService_partnershipId_key" UNIQUE ("partnershipId");


ALTER TABLE ONLY fulfilment."deliveryService" ADD CONSTRAINT "deliveryService_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY fulfilment."fulfillmentType" ADD CONSTRAINT "fulfillmentType_pkey" PRIMARY KEY (value);


ALTER TABLE ONLY fulfilment."mileRange" ADD CONSTRAINT "mileRange_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY fulfilment.recurrence ADD CONSTRAINT recurrence_pkey PRIMARY KEY (id);


ALTER TABLE ONLY fulfilment."timeSlot" ADD CONSTRAINT "timeSlot_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY imports."importHistory" ADD CONSTRAINT "importHistory_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY imports.import ADD CONSTRAINT imports_pkey PRIMARY KEY (id);


ALTER TABLE ONLY ingredient."ingredientProcessing" ADD CONSTRAINT "ingredientProcessing_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY ingredient."ingredientSacahet_recipeHubSachet" ADD CONSTRAINT "ingredientSacahet_recipeHubSachet_pkey" PRIMARY KEY ("ingredientSachetId",
                                                                                                                                     "recipeHubSachetId");


ALTER TABLE ONLY ingredient."ingredientSachet" ADD CONSTRAINT "ingredientSachet_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY ingredient.ingredient ADD CONSTRAINT ingredient_pkey PRIMARY KEY (id);


ALTER TABLE ONLY ingredient."modeOfFulfillmentEnum" ADD CONSTRAINT "modeOfFulfillmentEnum_pkey" PRIMARY KEY (value);


ALTER TABLE ONLY ingredient."modeOfFulfillment" ADD CONSTRAINT "modeOfFulfillment_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY insights.app_module_insight ADD CONSTRAINT app_module_insight_pkey PRIMARY KEY ("appTitle",
                                                                                                 "moduleTitle",
                                                                                                 "insightIdentifier");


ALTER TABLE ONLY insights.chart ADD CONSTRAINT chart_pkey PRIMARY KEY (id);


ALTER TABLE ONLY insights.date ADD CONSTRAINT date_pkey PRIMARY KEY (date);


ALTER TABLE ONLY insights.day ADD CONSTRAINT "day_dayNumber_key" UNIQUE ("dayNumber");


ALTER TABLE ONLY insights.day ADD CONSTRAINT day_pkey PRIMARY KEY ("dayName");


ALTER TABLE ONLY insights.hour ADD CONSTRAINT hour_pkey PRIMARY KEY (hour);


ALTER TABLE ONLY insights.insights ADD CONSTRAINT insights_pkey PRIMARY KEY (identifier);


ALTER TABLE ONLY insights.insights ADD CONSTRAINT insights_title_key UNIQUE (identifier);


ALTER TABLE ONLY insights.month ADD CONSTRAINT month_name_key UNIQUE (name);


ALTER TABLE ONLY insights.month ADD CONSTRAINT month_pkey PRIMARY KEY (number);


ALTER TABLE ONLY instructions."instructionStep" ADD CONSTRAINT "instructionStep_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY instructions."instructionSet" ADD CONSTRAINT instruction_pkey PRIMARY KEY (id);


ALTER TABLE ONLY inventory."bulkItemHistory" ADD CONSTRAINT "bulkHistory_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY inventory."bulkItem" ADD CONSTRAINT "bulkInventoryItem_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY inventory."bulkItem_unitConversion" ADD CONSTRAINT "bulkItem_unitConversion_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY inventory."bulkWorkOrder" ADD CONSTRAINT "bulkWorkOrder_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY inventory."packagingHistory" ADD CONSTRAINT "packagingHistory_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY inventory."purchaseOrderItem" ADD CONSTRAINT "purchaseOrderItem_mandiPurchaseOrderItemId_key" UNIQUE ("mandiPurchaseOrderItemId");


ALTER TABLE ONLY inventory."purchaseOrderItem" ADD CONSTRAINT "purchaseOrder_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY inventory."sachetItemHistory" ADD CONSTRAINT "sachetHistory_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY inventory."sachetItem" ADD CONSTRAINT "sachetItem2_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY inventory."sachetWorkOrder" ADD CONSTRAINT "sachetWorkOrder_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY inventory."supplierItem" ADD CONSTRAINT "supplierItem_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY inventory."supplierItem_unitConversion" ADD CONSTRAINT "supplierItem_unitConversion_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY inventory.supplier ADD CONSTRAINT "supplier_mandiSupplierId_key" UNIQUE ("mandiSupplierId");


ALTER TABLE ONLY inventory.supplier ADD CONSTRAINT supplier_pkey PRIMARY KEY (id);


ALTER TABLE ONLY inventory."unitConversionByBulkItem" ADD CONSTRAINT "unitConversionByBulkItem_id_key" UNIQUE (id);


ALTER TABLE ONLY inventory."unitConversionByBulkItem" ADD CONSTRAINT "unitConversionByBulkItem_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY master."accompanimentType" ADD CONSTRAINT "accompanimentType_name_key" UNIQUE (name);


ALTER TABLE ONLY master."accompanimentType" ADD CONSTRAINT "accompanimentType_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY master."allergenName" ADD CONSTRAINT allergen_name_key UNIQUE (name);


ALTER TABLE ONLY master."allergenName" ADD CONSTRAINT allergen_pkey PRIMARY KEY (id);


ALTER TABLE ONLY master."cuisineName" ADD CONSTRAINT "cuisineName_id_key" UNIQUE (id);


ALTER TABLE ONLY master."cuisineName" ADD CONSTRAINT "cuisineName_name_key" UNIQUE (name);


ALTER TABLE ONLY master."cuisineName" ADD CONSTRAINT "cuisineName_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY master."processingName" ADD CONSTRAINT processing_name_key UNIQUE (name);


ALTER TABLE ONLY master."processingName" ADD CONSTRAINT processing_pkey PRIMARY KEY (id);


ALTER TABLE ONLY master."productCategory" ADD CONSTRAINT "productCategory_pkey" PRIMARY KEY (name);


ALTER TABLE ONLY master."unitConversion" ADD CONSTRAINT "unitConversion_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY master.unit ADD CONSTRAINT unit_name_key UNIQUE (name);


ALTER TABLE ONLY master.unit ADD CONSTRAINT unit_pkey PRIMARY KEY (id);


ALTER TABLE ONLY notifications."emailConfig" ADD CONSTRAINT "emailConfig_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY notifications."displayNotification" ADD CONSTRAINT notification_pkey PRIMARY KEY (id);


ALTER TABLE ONLY notifications."printConfig" ADD CONSTRAINT "printConfig_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY notifications."smsConfig" ADD CONSTRAINT "smsConfig_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY notifications.type ADD CONSTRAINT type_name_key UNIQUE (name);


ALTER TABLE ONLY notifications.type ADD CONSTRAINT type_pkey PRIMARY KEY (id);


ALTER TABLE ONLY "onDemand".category ADD CONSTRAINT category_id_key UNIQUE (id);


ALTER TABLE ONLY "onDemand".category ADD CONSTRAINT category_name_key UNIQUE (name);


ALTER TABLE ONLY "onDemand".category ADD CONSTRAINT category_pkey PRIMARY KEY (id);


ALTER TABLE ONLY "onDemand".collection ADD CONSTRAINT collection_pkey PRIMARY KEY (id);


ALTER TABLE ONLY "onDemand"."collection_productCategory" ADD CONSTRAINT "collection_productCategory_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY "onDemand"."collection_productCategory_product" ADD CONSTRAINT "collection_productCategory_product_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY "onDemand".menu ADD CONSTRAINT menu_pkey PRIMARY KEY (id);


ALTER TABLE ONLY "onDemand"."modifierCategoryOption" ADD CONSTRAINT "modifierCategoryOption_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY "onDemand"."modifierCategory" ADD CONSTRAINT "modifierCategory_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY "onDemand".modifier ADD CONSTRAINT modifier_name_key UNIQUE (name);


ALTER TABLE ONLY "onDemand".modifier ADD CONSTRAINT modifier_pkey PRIMARY KEY (id);


ALTER TABLE ONLY "onDemand".brand_collection ADD CONSTRAINT shop_collection_pkey PRIMARY KEY ("brandId",
                                                                                              "collectionId");


ALTER TABLE ONLY "onDemand"."storeData" ADD CONSTRAINT "storeData_pkey" PRIMARY KEY (id);



ALTER TABLE ONLY "order".cart ADD CONSTRAINT "cart_orderId_key" UNIQUE ("orderId");


ALTER TABLE ONLY "order"."cartItem" ADD CONSTRAINT "orderCartItem_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY "order".cart ADD CONSTRAINT "orderCart_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY "order"."orderMode" ADD CONSTRAINT "orderModes_pkey" PRIMARY KEY (title);


ALTER TABLE ONLY "order"."orderStatusEnum" ADD CONSTRAINT "orderStatusEnum_pkey" PRIMARY KEY (value);


ALTER TABLE ONLY "order"."order" ADD CONSTRAINT "order_cartId_key" UNIQUE ("cartId");


ALTER TABLE ONLY "order"."order" ADD CONSTRAINT order_pkey PRIMARY KEY (id);


ALTER TABLE ONLY "order"."order" ADD CONSTRAINT "order_thirdPartyOrderId_key" UNIQUE ("thirdPartyOrderId");


ALTER TABLE ONLY "order"."thirdPartyOrder" ADD CONSTRAINT "thirdPartyOrder_id_key" UNIQUE (id);


ALTER TABLE ONLY "order"."thirdPartyOrder" ADD CONSTRAINT "thirdPartyOrder_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY packaging."packagingSpecifications" ADD CONSTRAINT "packagingSpecifications_mandiPackagingId_key" UNIQUE ("mandiPackagingId");


ALTER TABLE ONLY packaging."packagingSpecifications" ADD CONSTRAINT "packagingSpecifications_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY packaging.packaging ADD CONSTRAINT "packaging_mandiPackagingId_key" UNIQUE ("mandiPackagingId");


ALTER TABLE ONLY packaging.packaging ADD CONSTRAINT packaging_pkey PRIMARY KEY (id);


ALTER TABLE ONLY products."comboProductComponent" ADD CONSTRAINT "comboProductComponents_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY products."customizableProductComponent" ADD CONSTRAINT "customizableProductOptions_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY products."inventoryProductBundleSachet" ADD CONSTRAINT "inventoryProductBundleSachet_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY products."inventoryProductBundle" ADD CONSTRAINT "inventoryProductBundle_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY products."productConfigTemplate" ADD CONSTRAINT "productConfigTemplate_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY products."productDataConfig" ADD CONSTRAINT "productDataConfig_pkey" PRIMARY KEY ("productId",
                                                                                                   "productConfigTemplateId");


ALTER TABLE ONLY products."productOptionType" ADD CONSTRAINT "productOptionType_pkey" PRIMARY KEY (title);


ALTER TABLE ONLY products."productOption" ADD CONSTRAINT "productOption_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY products."productType" ADD CONSTRAINT "productType_pkey" PRIMARY KEY (title);


ALTER TABLE ONLY products.product ADD CONSTRAINT product_pkey PRIMARY KEY (id);


ALTER TABLE ONLY public.response ADD CONSTRAINT response_pkey PRIMARY KEY (success,
                                                                           message);


ALTER TABLE ONLY rules.conditions ADD CONSTRAINT conditions_pkey PRIMARY KEY (id);


ALTER TABLE ONLY safety."safetyCheckPerUser" ADD CONSTRAINT "safetyCheckByUser_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY safety."safetyCheck" ADD CONSTRAINT "safetyCheck_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY settings."appPermission" ADD CONSTRAINT "appPermission_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY settings."appSettings" ADD CONSTRAINT "appSettings_identifier_key" UNIQUE (identifier);


ALTER TABLE ONLY settings."appSettings" ADD CONSTRAINT "appSettings_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY settings.app_module ADD CONSTRAINT app_module_pkey PRIMARY KEY ("appTitle",
                                                                                 "moduleTitle");


ALTER TABLE ONLY settings.app ADD CONSTRAINT apps_pkey PRIMARY KEY (id);


ALTER TABLE ONLY settings.app ADD CONSTRAINT apps_title_key UNIQUE (title);


ALTER TABLE ONLY settings."operationConfig" ADD CONSTRAINT "operationConfig_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY settings."organizationSettings" ADD CONSTRAINT "organizationSettings_pkey" PRIMARY KEY (title);


ALTER TABLE ONLY settings."role_appPermission" ADD CONSTRAINT "role_appPermission_pkey" PRIMARY KEY ("appPermissionId",
                                                                                                     "role_appId");


ALTER TABLE ONLY settings.role_app ADD CONSTRAINT role_app_id_key UNIQUE (id);


ALTER TABLE ONLY settings.role_app ADD CONSTRAINT role_app_pkey PRIMARY KEY ("roleId",
                                                                             "appId");


ALTER TABLE ONLY settings.role ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


ALTER TABLE ONLY settings.role ADD CONSTRAINT roles_role_key UNIQUE (title);


ALTER TABLE ONLY settings.station_kot_printer ADD CONSTRAINT station_kot_printer_pkey PRIMARY KEY ("stationId",
                                                                                                   "printNodeId");


ALTER TABLE ONLY settings.station ADD CONSTRAINT station_pkey PRIMARY KEY (id);


ALTER TABLE ONLY settings.station_label_printer ADD CONSTRAINT station_printer_pkey PRIMARY KEY ("stationId",
                                                                                                 "printNodeId");


ALTER TABLE ONLY settings.station_user ADD CONSTRAINT station_user_pkey PRIMARY KEY ("userKeycloakId",
                                                                                     "stationId");


ALTER TABLE ONLY settings."user" ADD CONSTRAINT "user_keycloakId_key" UNIQUE ("keycloakId");


ALTER TABLE ONLY settings."user" ADD CONSTRAINT user_pkey PRIMARY KEY (id);


ALTER TABLE ONLY settings.user_role ADD CONSTRAINT user_role_pkey PRIMARY KEY ("userId",
                                                                               "roleId");


ALTER TABLE ONLY "simpleRecipe"."simpleRecipeYield" ADD CONSTRAINT "recipeServing_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY "simpleRecipe"."simpleRecipeComponent_productOptionType" ADD CONSTRAINT "simpleRecipeComponent_productOptionType_pkey" PRIMARY KEY ("simpleRecipeComponentId",
                                                                                                                                                     "productOptionType");


ALTER TABLE ONLY "simpleRecipe"."simpleRecipeYield_ingredientSachet" ADD CONSTRAINT "simpleRecipeYield_ingredientSachet_pkey" PRIMARY KEY ("recipeYieldId",
                                                                                                                                           "simpleRecipeIngredientProcessingId");


ALTER TABLE ONLY "simpleRecipe"."simpleRecipe_ingredient_processing" ADD CONSTRAINT "simpleRecipe_ingredient_processing_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY "simpleRecipe"."simpleRecipe" ADD CONSTRAINT "simpleRecipe_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY "simpleRecipe"."simpleRecipe_productOptionType" ADD CONSTRAINT "simpleRecipe_productOptionType_pkey" PRIMARY KEY ("simpleRecipeId",
                                                                                                                                   "productOptionTypeTitle");


ALTER TABLE ONLY subscription."brand_subscriptionTitle" ADD CONSTRAINT "shop_subscriptionTitle_pkey" PRIMARY KEY ("brandId",
                                                                                                                  "subscriptionTitleId");


ALTER TABLE ONLY subscription."subscriptionAutoSelectOption" ADD CONSTRAINT "subscriptionAutoSelectOption_pkey" PRIMARY KEY ("methodName");


ALTER TABLE ONLY subscription."subscriptionItemCount" ADD CONSTRAINT "subscriptionItemCount_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY subscription."subscriptionOccurence_addOn" ADD CONSTRAINT "subscriptionOccurence_addOn_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY subscription."subscriptionOccurence_customer" ADD CONSTRAINT "subscriptionOccurence_customer_orderCartId_key" UNIQUE ("cartId");


ALTER TABLE ONLY subscription."subscriptionOccurence_customer" ADD CONSTRAINT "subscriptionOccurence_customer_pkey" PRIMARY KEY ("subscriptionOccurenceId",
                                                                                                                                 "keycloakId",
                                                                                                                                 "brand_customerId");


ALTER TABLE ONLY subscription."subscriptionOccurence" ADD CONSTRAINT "subscriptionOccurence_id_key" UNIQUE (id);


ALTER TABLE ONLY subscription."subscriptionOccurence" ADD CONSTRAINT "subscriptionOccurence_pkey" PRIMARY KEY ("subscriptionId",
                                                                                                               "fulfillmentDate");


ALTER TABLE ONLY subscription."subscriptionOccurence_product" ADD CONSTRAINT "subscriptionOccurence_product_id_key" UNIQUE (id);


ALTER TABLE ONLY subscription."subscriptionOccurence_product" ADD CONSTRAINT "subscriptionOccurence_product_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY subscription."subscriptionPickupOption" ADD CONSTRAINT "subscriptionPickupOption_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY subscription."subscriptionServing" ADD CONSTRAINT "subscriptionServing_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY subscription."subscriptionTitle" ADD CONSTRAINT "subscriptionTitle_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY subscription."subscriptionTitle" ADD CONSTRAINT "subscriptionTitle_title_key" UNIQUE (title);


ALTER TABLE ONLY subscription.subscription ADD CONSTRAINT subscription_pkey PRIMARY KEY (id);


ALTER TABLE ONLY subscription.subscription_zipcode ADD CONSTRAINT subscription_zipcode_pkey PRIMARY KEY ("subscriptionId",
                                                                                                         zipcode);


ALTER TABLE ONLY website."websitePageModule" ADD CONSTRAINT "websitePageModule_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY website."websitePage" ADD CONSTRAINT "websitePage_pkey" PRIMARY KEY (id);


ALTER TABLE ONLY website.website ADD CONSTRAINT "website_brandId_key" UNIQUE ("brandId");


ALTER TABLE ONLY website.website ADD CONSTRAINT website_pkey PRIMARY KEY (id);


CREATE TRIGGER "customerWLRTrigger" AFTER
INSERT ON crm.brand_customer
FOR EACH ROW EXECUTE FUNCTION crm."createCustomerWLR"();


CREATE TRIGGER "loyaltyPointTransaction" AFTER
INSERT ON crm."loyaltyPointTransaction"
FOR EACH ROW EXECUTE FUNCTION crm."processLoyaltyPointTransaction"();


CREATE TRIGGER "rewardsTrigger" AFTER
INSERT ON crm.brand_customer
FOR EACH ROW EXECUTE FUNCTION crm."rewardsTriggerFunction"();


CREATE TRIGGER "rewardsTrigger" AFTER
UPDATE OF "referredByCode" ON crm."customerReferral"
FOR EACH ROW EXECUTE FUNCTION crm."rewardsTriggerFunction"();


CREATE TRIGGER "set_crm_brandCustomer_updated_at"
BEFORE
UPDATE ON crm.brand_customer
FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_crm_brandCustomer_updated_at" ON crm.brand_customer IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER set_crm_campaign_updated_at
BEFORE
UPDATE ON crm.campaign
FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();

COMMENT ON TRIGGER set_crm_campaign_updated_at ON crm.campaign IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER set_crm_customer_updated_at
BEFORE
UPDATE ON crm.customer
FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();

COMMENT ON TRIGGER set_crm_customer_updated_at ON crm.customer IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER "set_crm_loyaltyPointTransaction_updated_at"
BEFORE
UPDATE ON crm."loyaltyPointTransaction"
FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_crm_loyaltyPointTransaction_updated_at" ON crm."loyaltyPointTransaction" IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER "set_crm_loyaltyPoint_updated_at"
BEFORE
UPDATE ON crm."loyaltyPoint"
FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_crm_loyaltyPoint_updated_at" ON crm."loyaltyPoint" IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER "set_crm_rewardHistory_updated_at"
BEFORE
UPDATE ON crm."rewardHistory"
FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_crm_rewardHistory_updated_at" ON crm."rewardHistory" IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER "set_crm_walletTransaction_updated_at"
BEFORE
UPDATE ON crm."walletTransaction"
FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_crm_walletTransaction_updated_at" ON crm."walletTransaction" IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER set_crm_wallet_updated_at
BEFORE
UPDATE ON crm.wallet
FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();

COMMENT ON TRIGGER set_crm_wallet_updated_at ON crm.wallet IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER "walletTransaction" AFTER
INSERT ON crm."walletTransaction"
FOR EACH ROW EXECUTE FUNCTION crm."processWalletTransaction"();


CREATE TRIGGER "set_deviceHub_computer_updated_at"
BEFORE
UPDATE ON "deviceHub".computer
FOR EACH ROW EXECUTE FUNCTION "deviceHub".set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_deviceHub_computer_updated_at" ON "deviceHub".computer IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER set_editor_block_updated_at
BEFORE
UPDATE ON editor.block
FOR EACH ROW EXECUTE FUNCTION editor.set_current_timestamp_updated_at();

COMMENT ON TRIGGER set_editor_block_updated_at ON editor.block IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER "set_editor_cssFileLinks_updated_at"
BEFORE
UPDATE ON editor."cssFileLinks"
FOR EACH ROW EXECUTE FUNCTION editor.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_editor_cssFileLinks_updated_at" ON editor."cssFileLinks" IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER "set_editor_jsFileLinks_updated_at"
BEFORE
UPDATE ON editor."jsFileLinks"
FOR EACH ROW EXECUTE FUNCTION editor.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_editor_jsFileLinks_updated_at" ON editor."jsFileLinks" IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER set_editor_template_updated_at
BEFORE
UPDATE ON editor.file
FOR EACH ROW EXECUTE FUNCTION editor.set_current_timestamp_updated_at();

COMMENT ON TRIGGER set_editor_template_updated_at ON editor.file IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER "set_fulfilment_deliveryPreferenceByCharge_updated_at"
BEFORE
UPDATE ON fulfilment."deliveryPreferenceByCharge"
FOR EACH ROW EXECUTE FUNCTION fulfilment.set_current_timestamp_updated_at();


CREATE TRIGGER "set_ingredient_ingredientProcessing_updated_at"
BEFORE
UPDATE ON ingredient."ingredientProcessing"
FOR EACH ROW EXECUTE FUNCTION ingredient.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_ingredient_ingredientProcessing_updated_at" ON ingredient."ingredientProcessing" IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER "set_ingredient_ingredientSachet_updatedAt"
BEFORE
UPDATE ON ingredient."ingredientSachet"
FOR EACH ROW EXECUTE FUNCTION ingredient."set_current_timestamp_updatedAt"();

COMMENT ON TRIGGER "set_ingredient_ingredientSachet_updatedAt" ON ingredient."ingredientSachet" IS 'trigger to set value of column "updatedAt" to current timestamp on row update';


CREATE TRIGGER set_ingredient_ingredient_updated_at
BEFORE
UPDATE ON ingredient.ingredient
FOR EACH ROW EXECUTE FUNCTION ingredient.set_current_timestamp_updated_at();

COMMENT ON TRIGGER set_ingredient_ingredient_updated_at ON ingredient.ingredient IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER "set_ingredient_modeOfFulfillment_updated_at"
BEFORE
UPDATE ON ingredient."modeOfFulfillment"
FOR EACH ROW EXECUTE FUNCTION ingredient.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_ingredient_modeOfFulfillment_updated_at" ON ingredient."modeOfFulfillment" IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER set_insights_insights_updated_at
BEFORE
UPDATE ON insights.insights
FOR EACH ROW EXECUTE FUNCTION insights.set_current_timestamp_updated_at();

COMMENT ON TRIGGER set_insights_insights_updated_at ON insights.insights IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER "set_inventory_bulkItemHistory_updated_at"
BEFORE
UPDATE ON inventory."bulkItemHistory"
FOR EACH ROW EXECUTE FUNCTION inventory.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_inventory_bulkItemHistory_updated_at" ON inventory."bulkItemHistory" IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER "set_inventory_bulkItem_updatedAt"
BEFORE
UPDATE ON inventory."bulkItem"
FOR EACH ROW EXECUTE FUNCTION inventory."set_current_timestamp_updatedAt"();

COMMENT ON TRIGGER "set_inventory_bulkItem_updatedAt" ON inventory."bulkItem" IS 'trigger to set value of column "updatedAt" to current timestamp on row update';


CREATE TRIGGER "set_inventory_packagingHistory_updated_at"
BEFORE
UPDATE ON inventory."packagingHistory"
FOR EACH ROW EXECUTE FUNCTION inventory.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_inventory_packagingHistory_updated_at" ON inventory."packagingHistory" IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER "set_inventory_purchaseOrderItem_updated_at"
BEFORE
UPDATE ON inventory."purchaseOrderItem"
FOR EACH ROW EXECUTE FUNCTION inventory.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_inventory_purchaseOrderItem_updated_at" ON inventory."purchaseOrderItem" IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER "set_inventory_sachetItemHistory_updated_at"
BEFORE
UPDATE ON inventory."sachetItemHistory"
FOR EACH ROW EXECUTE FUNCTION inventory.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_inventory_sachetItemHistory_updated_at" ON inventory."sachetItemHistory" IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER "set_inventory_sachetWorkOrder_updated_at"
BEFORE
UPDATE ON inventory."sachetWorkOrder"
FOR EACH ROW EXECUTE FUNCTION inventory.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_inventory_sachetWorkOrder_updated_at" ON inventory."sachetWorkOrder" IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER set_notifications_notification_updated_at
BEFORE
UPDATE ON notifications."displayNotification"
FOR EACH ROW EXECUTE FUNCTION notifications.set_current_timestamp_updated_at();

COMMENT ON TRIGGER set_notifications_notification_updated_at ON notifications."displayNotification" IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER "set_notifications_printConfig_updated_at"
BEFORE
UPDATE ON notifications."printConfig"
FOR EACH ROW EXECUTE FUNCTION notifications.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_notifications_printConfig_updated_at" ON notifications."printConfig" IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER "set_onDemand_collection_updated_at"
BEFORE
UPDATE ON "onDemand".collection
FOR EACH ROW EXECUTE FUNCTION "onDemand".set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_onDemand_collection_updated_at" ON "onDemand".collection IS 'trigger to set value of column "updated_at" to current timestamp on row update';


CREATE TRIGGER "deductLoyaltyPointsPostOrder" AFTER
INSERT ON "order"."order"
FOR EACH ROW EXECUTE FUNCTION crm."deductLoyaltyPointsPostOrder"();


CREATE TRIGGER "deductWalletAmountPostOrder" AFTER
INSERT ON "order"."order"
FOR EACH ROW EXECUTE FUNCTION crm."deductWalletAmountPostOrder"();





CREATE TRIGGER "postOrderCouponRewards" AFTER
INSERT ON "order"."order"
FOR EACH ROW EXECUTE FUNCTION crm."postOrderCouponRewards"();


CREATE TRIGGER "rewardsTrigger" AFTER
INSERT ON "order"."order"
FOR EACH ROW EXECUTE FUNCTION crm."rewardsTriggerFunction"();

CREATE FUNCTION "order"."addOnTotal"(cart "order".cart) RETURNS numeric LANGUAGE plpgsql STABLE AS $$
DECLARE
   total numeric := 0;
   product "order"."cartItem";
BEGIN
    IF cart."source" = 'a-la-carte' THEN
        RETURN 0;
    ELSE
        FOR product IN SELECT * FROM "order"."cartItem" WHERE "cartId" = cart.id LOOP
            total := total + COALESCE(product."addOnPrice", 0);
            IF product."isAddOn" = true THEN
                total := total + product."unitPrice";
            END IF;
        END LOOP;
        RETURN total;
    END IF;
END
$$;


CREATE FUNCTION "order"."cartBillingDetails"(cart "order".cart) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    item jsonb := '{}';
    itemTotal numeric;
    addOnTotal numeric;
    deliveryPrice numeric;
    subTotal numeric;
    tax numeric;
    taxPercent numeric;
    isTaxIncluded boolean;
    totalPrice numeric;
BEGIN
    SELECT "order"."isTaxIncluded"(cart.*) INTO isTaxIncluded;
    SELECT "order"."itemTotal"(cart.*) INTO itemTotal;
    SELECT "order"."addOnTotal"(cart.*) INTO addOnTotal;
    SELECT "order"."deliveryPrice"(cart.*) INTO deliveryPrice;
    SELECT "order"."subTotal"(cart.*) INTO subTotal;
    SELECT "order".tax(cart.*) INTO tax;
    SELECT "order"."taxPercent"(cart.*) INTO taxPercent;
    SELECT "order"."totalPrice"(cart.*) INTO totalPrice;
    item:=item || jsonb_build_object('isTaxIncluded', isTaxIncluded);
    item:=item || jsonb_build_object('itemTotal', jsonb_build_object('value', itemTotal, 'description', 'Includes your base price and add on price.', 'label','Item Total', 'comment', CONCAT('Includes add on total of ', '{{',COALESCE(addOnTotal,0),'}}')));
    item:=item || jsonb_build_object('deliveryPrice', jsonb_build_object('value', deliveryPrice, 'description', '', 'label','Delivery Fee', 'comment', ''));
    IF isTaxIncluded = false THEN
        item:=item || jsonb_build_object('subTotal', jsonb_build_object('value', subTotal, 'description', '', 'label','Sub Total', 'comment', ''));
        item:=item || jsonb_build_object('tax', jsonb_build_object('value', tax, 'description', '', 'label','Tax', 'comment', CONCAT('Your tax is calculated at ', taxPercent,'%')));
        item:=item || jsonb_build_object('totalPrice', jsonb_build_object('value', totalPrice, 'description', '', 'label','Total Price', 'comment', ''));
    ELSE
        item:=item || jsonb_build_object('totalPrice', jsonb_build_object('value', totalPrice, 'description', '', 'label','Total Price', 'comment', CONCAT('Tax inclusive of ', '{{',tax,'}}', ' at ', taxPercent, '%')));
    END IF;
    RETURN item;
END
$$;




CREATE FUNCTION "order"."clearFulfillmentInfo"(cartid integer) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    UPDATE "order"."cart"
    SET "fulfillmentInfo" = NULL
    WHERE id = cartId;
END
$$;


CREATE FUNCTION "order"."createSachets"() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    inventorySachet "products"."inventoryProductBundleSachet";
    sachet "simpleRecipe"."simpleRecipeYield_ingredientSachet";
BEGIN
    IF NEW."simpleRecipeYieldId" IS NOT NULL THEN
        FOR sachet IN SELECT * FROM "simpleRecipe"."simpleRecipeYield_ingredientSachet" WHERE "recipeYieldId" = NEW."simpleRecipeYieldId" LOOP
            IF sachet."ingredientSachetId" IS NOT NULL THEN
                INSERT INTO "order"."cartItem"("parentCartItemId","ingredientSachetId","cartId") VALUES (NEW.id, sachet."ingredientSachetId", NEW."cartId");
            ELSEIF sachet."subRecipeYieldId" IS NOT NULL THEN
                INSERT INTO "order"."cartItem"("parentCartItemId","subRecipeYieldId","cartId") VALUES (NEW.id, sachet."subRecipeYieldId", NEW."cartId");
            END IF;
        END LOOP;
    ELSEIF NEW."inventoryProductBundleId" IS NOT NULL THEN
        FOR inventorySachet IN SELECT * FROM "products"."inventoryProductBundleSachet" WHERE "inventoryProductBundleId" = NEW."inventoryProductBundleId" LOOP
            IF inventorySachet."sachetItemId" IS NOT NULL THEN
                INSERT INTO "order"."cartItem"("parentCartItemId","sachetItemId", "cartId") VALUES (NEW.id, inventorySachet."sachetItemId", NEW."cartId");
            END IF;
        END LOOP;
    ELSEIF NEW."subRecipeYieldId" IS NOT NULL THEN
        FOR sachet IN SELECT * FROM "simpleRecipe"."simpleRecipeYield_ingredientSachet" WHERE "recipeYieldId" = NEW."subRecipeYieldId" LOOP
            IF sachet."ingredientSachetId" IS NOT NULL THEN
                INSERT INTO "order"."cartItem"("parentCartItemId","ingredientSachetId","cartId") VALUES (NEW.id, sachet."ingredientSachetId", NEW."cartId");
            ELSEIF sachet."subRecipeYieldId" IS NOT NULL THEN
                INSERT INTO "order"."cartItem"("parentCartItemId","subRecipeYieldId","cartId") VALUES (NEW.id, sachet."subRecipeYieldId", NEW."cartId");
            END IF;
        END LOOP;
    END IF;
    RETURN null;
END;
$$;


CREATE FUNCTION "order"."deliveryPrice"(cart "order".cart) RETURNS numeric LANGUAGE plpgsql STABLE AS $$
DECLARE
    value numeric;
    total numeric;
    rangeId int;
    subscriptionId int;
    price numeric:=0;
BEGIN
    IF cart."fulfillmentInfo"::json->>'type' LIKE '%PICKUP' OR cart."fulfillmentInfo" IS NULL
        THEN RETURN 0;
    END IF;
    IF cart."source" = 'a-la-carte' THEN
        SELECT "order"."itemTotal"(cart) into total;
        SELECT cart."fulfillmentInfo"::json#>'{"slot","mileRangeId"}' as int into rangeId;
        SELECT charge from "fulfilment"."charge" WHERE charge."mileRangeId" = rangeId AND total >= charge."orderValueFrom" AND total < charge."orderValueUpto" into value;
        IF value IS NOT NULL
            THEN RETURN value;
        END IF;
        SELECT MAX(charge) from "fulfilment"."charge" WHERE charge."mileRangeId" = rangeId into value;
        IF value IS NULL
            THEN RETURN 0;
        ELSE
            RETURN value;
        END IF;
    ELSE
        SELECT "subscriptionId"
        FROM crm."brand_customer"
        WHERE "brandId" = cart."brandId"
        AND "keycloakId" = cart."customerKeycloakId"
        INTO subscriptionId;
        SELECT "deliveryPrice"
        FROM subscription."subscription_zipcode"
        WHERE "subscriptionId" = subscriptionId
        AND zipcode = cart.address->>'zipcode'
        INTO price;
        RETURN COALESCE(price, 0);
    END IF;
    RETURN 0;
END
$$;


CREATE FUNCTION "order".discount(cart "order".cart) RETURNS numeric LANGUAGE plpgsql STABLE AS $$
DECLARE
   totalPrice numeric;
   itemTotal numeric;
   deliveryPrice numeric;
   rewardIds int[];
   rewardId int;
   reward record;
   discount numeric := 0;
BEGIN
    SELECT "order"."itemTotal"(cart.*) into itemTotal;
    SELECT "order"."deliveryPrice"(cart.*) into deliveryPrice;
    totalPrice := ROUND(itemTotal + deliveryPrice, 2);
    rewardIds := ARRAY(SELECT "rewardId" FROM crm."orderCart_rewards" WHERE "orderCartId" = cart.id);
    FOREACH rewardId IN ARRAY rewardIds LOOP
        SELECT * FROM crm.reward WHERE id = rewardId INTO reward;
        IF reward."type" = 'Discount'
            THEN
            IF  reward."rewardValue"->>'type' = 'conditional'
                THEN
                discount := totalPrice * ((reward."rewardValue"->'value'->>'percentage')::numeric / 100);
                IF discount >  (reward."rewardValue"->'value'->>'max')::numeric
                    THEN discount := (reward."rewardValue"->'value'->>'max')::numeric;
                END IF;
            ELSIF reward."rewardValue"->>'type' = 'absolute' THEN
                discount := (reward."rewardValue"->>'value')::numeric;
            ELSE
                discount := 0;
            END IF;
        END IF;
    END LOOP;
    IF discount > totalPrice THEN
        discount := totalPrice;
    END IF;
    RETURN ROUND(discount, 2);
END;
$$;


CREATE FUNCTION "order"."handleProductOption"() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    cart "order"."cart";
    productOption products."productOption";
    mode text;
    validFor text;
    counter int := 0;
    sachet "simpleRecipe"."simpleRecipeYield_ingredientSachet";
BEGIN
    IF NEW."productOptionId" IS NULL THEN
        RETURN NULL;
    END IF;
    SELECT * from "order"."cart" WHERE id = NEW.cartId INTO cart;
    IF cart."paymentStatus" = 'SUCCEEDED' THEN
        SELECT * INTO productOption FROM products."productOption" WHERE id = NEW."productOptionId";
        SELECT "orderMode" INTO mode FROM products."productOptionType" WHERE title = productOption."type";
        SELECT "validWhen" INTO validFor FROM "order"."orderMode" WHERE title = mode;
        IF validFor = 'recipe' THEN
            counter := productOption.quantity;
            WHILE counter >= 1 LOOP
                INSERT INTO "order"."cartItem"("parentCartItemId","simpleRecipeYieldId") VALUES (NEW.id, productOption."simpleRecipeYieldId") RETURNING id;
                FOR sachet IN SELECT * FROM "simpleRecipe"."simpleRecipeYield_ingredientSachet" WHERE "recipeYieldId" = productOption."simpleRecipeYieldId" LOOP
                    INSERT INTO "order"."cartItem"("parentCartItemId","ingredientSachetId") VALUES (id, sachet."ingredientSachetId");
                END LOOP;
                counter := counter - 1;
            END LOOP;
        ELSIF validFor = 'sachetItem' THEN
            counter := productOption.quantity;
            WHILE counter >= 1 LOOP
                INSERT INTO "order"."cartItem"("parentCartItemId","sachetItemId") VALUES (NEW.id, productOption."sachetItemId") RETURNING id;
                counter := counter - 1;
            END LOOP;
        END IF;
    END IF;
    RETURN NULL;
END;
$$;


CREATE FUNCTION "order"."isCartValid"(cart "order".cart) RETURNS jsonb LANGUAGE plpgsql STABLE AS $_$ DECLARE totalPrice numeric := 0; res jsonb; productsCount int := 0; BEGIN
SELECT "order"."totalPrice"(cart.*) INTO totalPrice;
SELECT count(*) INTO productsCount
FROM "order"."cartItem"
WHERE "cartId" = cart.id; IF productsCount = 0 THEN res := json_build_object('status', false, 'error', 'No items in cart!'); ELSIF cart."customerInfo" IS NULL
    OR cart."customerInfo"->>'customerFirstName' IS NULL THEN res := json_build_object('status', false, 'error', 'Basic customer details missing!'); ELSIF cart."fulfillmentInfo" IS NULL THEN res := json_build_object('status', false, 'error', 'No fulfillment mode selected!'); ELSIF cart."fulfillmentInfo" IS NOT NULL
    AND cart.status = 'PENDING' THEN
    SELECT "order"."validateFulfillmentInfo"(cart."fulfillmentInfo",
                                             cart."brandId") INTO res; IF (res->>'status')::boolean = false THEN
    PERFORM "order"."clearFulfillmentInfo"(cart.id); END IF; ELSIF cart."address" IS NULL
    AND cart."fulfillmentInfo"::json->>'type' LIKE '%DELIVERY' THEN res := json_build_object('status', false, 'error', 'No address selected for delivery!'); ELSIF totalPrice > 0
    AND totalPrice <= 0.5 THEN res := json_build_object('status', false, 'error', 'Transaction amount should be greater than $0.5!'); ELSE res := jsonb_build_object('status', true, 'error', ''); END IF; RETURN res; END $_$;
CREATE FUNCTION "order"."isTaxIncluded"(cart "order".cart) RETURNS boolean LANGUAGE plpgsql STABLE AS $$
DECLARE
    subscriptionId int;
    itemCountId int;
    taxIncluded boolean;
BEGIN
    IF cart."subscriptionOccurenceId" IS NOT NULL THEN
        SELECT "subscriptionId" INTO subscriptionId FROM subscription."subscriptionOccurence" WHERE id = cart."subscriptionOccurenceId";
        SELECT "subscriptionItemCountId" INTO itemCountId FROM subscription.subscription WHERE id = subscriptionId;
        SELECT "isTaxIncluded" INTO taxIncluded FROM subscription."subscriptionItemCount" WHERE id = itemCountId;
        RETURN taxIncluded;
    END IF;
    RETURN false;
END;
$$;
CREATE FUNCTION "order"."itemTotal"(cart "order".cart) RETURNS numeric LANGUAGE plpgsql STABLE AS $$
DECLARE
   total numeric;
BEGIN
    SELECT SUM("unitPrice") INTO total FROM "order"."cartItem" WHERE "cartId" = cart."id";
    RETURN COALESCE(total, 0);
END;
$$;
CREATE FUNCTION "order"."loyaltyPointsUsable"(cart "order".cart) RETURNS integer LANGUAGE plpgsql STABLE AS $$
DECLARE
   setting record;
   temp record;
   itemTotal numeric;
   deliveryPrice numeric;
   tax numeric;
   discount numeric;
   totalPrice numeric;
   amount numeric;
   rate numeric;
   pointsUsable int := 0;
   balance int;
BEGIN
    SELECT * FROM brands."storeSetting" WHERE "identifier" = 'Loyalty Points Usage' AND "type" = 'rewards' INTO setting;
    SELECT * FROM brands."brand_storeSetting" WHERE "storeSettingId" = setting.id AND "brandId" = ordercart."brandId" INTO temp;
    IF temp IS NOT NULL THEN
        setting := temp;
    END IF;
    IF setting IS NULL THEN
        RETURN pointsUsable;
    END IF;
    SELECT "order"."itemTotal"(cart.*) into itemTotal;
    SELECT "order"."deliveryPrice"(cart.*) into deliveryPrice;
    SELECT "order".tax(cart.*) into tax;
    SELECT "order".discount(cart.*) into discount;
    totalPrice := ROUND(itemTotal + deliveryPrice + cart.tip  + tax - cart."walletAmountUsed" - discount, 2);
    amount := ROUND(totalPrice * ((setting.value->>'percentage')::float / 100));
    IF amount > (setting.value->>'max')::int THEN
        amount := (setting.value->>'max')::int;
    END IF;
    SELECT crm."getLoyaltyPointsConversionRate"(cart."brandId") INTO rate;
    pointsUsable = ROUND(amount / rate);
    SELECT points FROM crm."loyaltyPoint" WHERE "keycloakId" = cart."customerKeycloakId" AND "brandId" = cart."brandId" INTO balance;
    IF pointsUsable > balance THEN
        pointsUsable := balance;
    END IF;
    -- if usable changes after cart update, then update used points
    IF cart."loyaltyPointsUsed" > pointsUsable THEN
        PERFORM crm."setLoyaltyPointsUsedInCart"(cart.id, pointsUsable);
    END IF;
    RETURN pointsUsable;
END;
$$;
CREATE FUNCTION "order"."onPaymentSuccess"() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    cart "order"."cart";
    tax numeric := 0;
    itemTotal numeric := 0;
    deliveryPrice numeric := 0;
    totalPrice numeric := 0;
BEGIN
    IF NEW."paymentStatus" = 'SUCCEEDED' THEN
        SELECT * from "order"."cart" WHERE id = NEW.id INTO cart;
        SELECT "order"."itemTotal"(cart.*) INTO itemTotal;
        SELECT "order"."tax"(cart.*) INTO tax;
        SELECT "order"."deliveryPrice"(cart.*) INTO deliveryPrice;
        SELECT "order"."totalPrice"(cart.*) INTO totalPrice;
        INSERT INTO "order"."order"("cartId", "tip", "tax","itemTotal","deliveryPrice", "fulfillmentType","amountPaid", "keycloakId", "brandId")
            VALUES (NEW.id, NEW.tip,tax, itemTotal,deliveryPrice, NEW."fulfillmentInfo"->'type'::text,totalPrice, NEW."customerKeycloakId", NEW."brandId");
        UPDATE "order"."cart" SET "orderId" = (SELECT id FROM "order"."order" WHERE "cartId" = NEW.id) WHERE id = NEW.id;
    END IF;
    RETURN NULL;
END;
$$;
CREATE FUNCTION "order".ordersummary(order_row "order"."order") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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
CREATE FUNCTION "order".set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;
CREATE FUNCTION "order"."subTotal"(cart "order".cart) RETURNS numeric LANGUAGE plpgsql STABLE AS $$
DECLARE
    amount numeric := 0;
    discount numeric := 0;
    itemTotal numeric;
    deliveryPrice numeric;
BEGIN
    SELECT "order"."itemTotal"(cart.*) into itemTotal;
    SELECT "order"."deliveryPrice"(cart.*) into deliveryPrice;
    SELECT "order".discount(cart.*) into discount;
    amount := itemTotal + deliveryPrice + cart.tip - discount;
    RETURN amount;
END
$$;
CREATE FUNCTION "order".tax(cart "order".cart) RETURNS numeric LANGUAGE plpgsql STABLE AS $$
DECLARE
   taxAmount numeric := 0;
   amount numeric := 0;
   tax numeric;
   isTaxIncluded boolean;
BEGIN
    SELECT "order"."isTaxIncluded"(cart.*) INTO isTaxIncluded;
    SELECT "order"."subTotal"(cart.*) into amount;
    SELECT "order"."taxPercent"(cart.*) into tax;
    IF isTaxIncluded = true THEN
        RETURN ROUND((tax * amount)/(100 + tax), 2);
    END IF;
    RETURN ROUND(amount * (tax / 100), 2);
END;
$$;
CREATE FUNCTION "order"."taxPercent"(cart "order".cart) RETURNS numeric LANGUAGE plpgsql STABLE AS $$
DECLARE
    taxPercent numeric := 0;
    percentage jsonb;
    subscriptionId int;
    itemCountId int;
BEGIN
    IF cart."subscriptionOccurenceId" IS NOT NULL THEN
        SELECT "subscriptionId" INTO subscriptionId FROM subscription."subscriptionOccurence" WHERE id = cart."subscriptionOccurenceId";
        SELECT "subscriptionItemCountId" INTO itemCountId FROM subscription.subscription WHERE id = subscriptionId;
        SELECT "tax" INTO taxPercent FROM subscription."subscriptionItemCount" WHERE id = itemCountId;
        RETURN taxPercent;
    ELSEIF cart."subscriptionOccurenceId" IS NULL THEN
        SELECT value FROM brands."brand_storeSetting" WHERE "brandId" = cart."brandId" AND "storeSettingId" = (SELECT id FROM brands."storeSetting" WHERE identifier = 'Tax Percentage') INTO percentage;
        RETURN (percentage->>'value')::numeric;
    ELSE
        RETURN 2.5;
    END IF;
END;
$$;
CREATE FUNCTION "order"."totalPrice"(cart "order".cart) RETURNS numeric LANGUAGE plpgsql STABLE AS $$
DECLARE
   totalPrice numeric;
   tax numeric;
   rate numeric;
   loyaltyPointsAmount numeric := 0;
   subTotal numeric;
   isTaxIncluded boolean;
BEGIN
    SELECT "order"."subTotal"(cart.*) INTO subTotal;
    SELECT "order".tax(cart.*) into tax;
    SELECT "order"."isTaxIncluded"(cart.*) INTO isTaxIncluded;
    IF cart."loyaltyPointsUsed" > 0 THEN
        SELECT cart."getLoyaltyPointsConversionRate"(cart."brandId") INTO rate;
        loyaltyPointsAmount := ROUND(rate * cart."loyaltyPointsUsed", 2);
    END IF;
    IF isTaxIncluded = true THEN
        totalPrice := ROUND(subTotal - COALESCE(cart."walletAmountUsed", 0) - loyaltyPointsAmount, 2);
    ELSE
        totalPrice := ROUND(subTotal - COALESCE(cart."walletAmountUsed", 0) - loyaltyPointsAmount  + tax, 2);
    END IF;
    RETURN totalPrice;
END
$$;
CREATE FUNCTION "order"."validateFulfillmentInfo"(f jsonb,
                                                  brandidparam integer) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    res jsonb;
    recurrence record;
    timeslot record;
    slotFrom time;
    slotUpto time;
    slotDate timestamp;
    isValid boolean;
    err text := '';
BEGIN
    IF (f->'slot'->>'from')::timestamp > NOW()::timestamp THEN
        IF f->>'type' = 'ONDEMAND_DELIVERY' THEN
            -- FOR recurrence IN SELECT * FROM fulfilment.recurrence WHERE "type" = 'ONDEMAND_DELIVERY' LOOP
            --     IF recurrence.psql_rrule::_rrule.rruleset @> NOW()::TIMESTAMP WITHOUT TIME ZONE THEN
            --         FOR timeslot IN SELECT * FROM fulfilment."timeSlot" WHERE "recurrenceId" = recurrence.id LOOP
            --             IF timeslot."from" < CURRENT_TIME AND timeslot."to" > CURRENT_TIME THEN
            --                 res := json_build_object('status', true, 'error', 'Valid date and time!');
            --             ELSE
            --                 res := json_build_object('status', false, 'error', 'Invalid time!');
            --             END IF;
            --         END LOOP;
            --     ELSE
            --         res := json_build_object('status', false, 'error', 'Invalid date!');
            --     END IF;
            -- END LOOP;
            SELECT * FROM fulfilment."timeSlot" WHERE id = (SELECT "timeSlotId" FROM fulfilment."mileRange" WHERE id = (f->'slot'->>'mileRangeId')::int AND "isActive" = true) AND "isActive" = true INTO timeslot;
            IF timeslot."from" < CURRENT_TIME AND timeslot."to" > CURRENT_TIME THEN
                SELECT * FROM fulfilment.recurrence WHERE id = timeslot."recurrenceId" AND "isActive" = true INTO recurrence;
                IF recurrence IS NOT NULL AND recurrence.psql_rrule::_rrule.rruleset @> NOW()::TIMESTAMP WITHOUT TIME ZONE THEN
                    res := json_build_object('status', true, 'error', 'Valid date and time!');
                ELSE
                    res := json_build_object('status', false, 'error', 'Invalid date!');
                END IF;
            ELSE
                res := json_build_object('status', false, 'error', 'Invalid time!');
            END IF;
        ELSIF f->>'type' = 'PREORDER_DELIVERY' THEN
            slotFrom := substring(f->'slot'->>'from', 12, 8)::time;
            slotUpto := substring(f->'slot'->>'to', 12, 8)::time;
            slotDate := substring(f->'slot'->>'from', 0, 11)::timestamp;
                SELECT * FROM fulfilment."timeSlot" WHERE id = (SELECT "timeSlotId" FROM fulfilment."mileRange" WHERE id = (f->'slot'->>'mileRangeId')::int AND "isActive" = true) AND "isActive" = true INTO timeslot;
                IF timeslot."from" < slotFrom AND timeslot."to" > slotFrom THEN -- lead time is already included in the slot (front-end)
                    SELECT * FROM fulfilment.recurrence WHERE id = timeslot."recurrenceId" AND "isActive" = true INTO recurrence;
                    IF recurrence IS NOT NULL AND recurrence.psql_rrule::_rrule.rruleset @> slotDate THEN
                        res := json_build_object('status', true, 'error', 'Valid date and time!');
                    ELSE
                        res := json_build_object('status', false, 'error', 'Invalid date!');
                    END IF;
                ELSE
                    res := json_build_object('status', false, 'error', 'Invalid time!');
                END IF;
        ELSIF f->>'type' = 'ONDEMAND_PICKUP' THEN
            slotFrom := substring(f->'slot'->>'from', 12, 8)::time;
            slotUpto := substring(f->'slot'->>'to', 12, 8)::time;
            slotDate := substring(f->'slot'->>'from', 0, 11)::timestamp;
            isValid := false;
            FOR recurrence IN SELECT * FROM fulfilment.recurrence WHERE "type" = 'ONDEMAND_PICKUP' AND "isActive" = true AND id IN (SELECT "recurrenceId" FROM fulfilment.brand_recurrence WHERE "brandId" = brandIdParam) LOOP
                IF recurrence.psql_rrule::_rrule.rruleset @> NOW()::TIMESTAMP WITHOUT TIME ZONE THEN
                    FOR timeslot IN SELECT * FROM fulfilment."timeSlot" WHERE "recurrenceId" = recurrence.id AND "isActive" = true LOOP
                        IF timeslot."from" < slotFrom AND timeslot."to" > slotFrom THEN
                            isValid := true;
                            EXIT;
                        END IF;
                    END LOOP;
                    IF isValid = false THEN
                        err := 'No time slot available!';
                    END IF;
                END IF;
            END LOOP;
            res := json_build_object('status', isValid, 'error', err);
        ELSE
            slotFrom := substring(f->'slot'->>'from', 12, 8)::time;
            slotUpto := substring(f->'slot'->>'to', 12, 8)::time;
            slotDate := substring(f->'slot'->>'from', 0, 11)::timestamp;
            isValid := false;
            FOR recurrence IN SELECT * FROM fulfilment.recurrence WHERE "type" = 'PREORDER_PICKUP' AND "isActive" = true AND id IN (SELECT "recurrenceId" FROM fulfilment.brand_recurrence WHERE "brandId" = brandIdParam) LOOP
                IF recurrence.psql_rrule::_rrule.rruleset @> slotDate THEN
                    FOR timeslot IN SELECT * FROM fulfilment."timeSlot" WHERE "recurrenceId" = recurrence.id AND "isActive" = true LOOP
                        IF timeslot."from" < slotFrom AND timeslot."to" > slotFrom THEN
                            isValid := true;
                            EXIT;
                        END IF;
                    END LOOP;
                    IF isValid = false THEN
                        err := 'No time slot available!';
                    END IF;
                END IF;
            END LOOP;
            res := json_build_object('status', isValid, 'error', err);
        END IF;
    ELSE
        res := jsonb_build_object('status', false, 'error', 'Slot expired!');
    END IF;
    res := res || jsonb_build_object('type', 'fulfillment');
    RETURN res;
END
$$;
CREATE FUNCTION "order"."walletAmountUsable"(cart "order".cart) RETURNS numeric LANGUAGE plpgsql STABLE AS $$
DECLARE
   setting record;
   temp record;
   itemTotal numeric;
   deliveryPrice numeric;
   tax numeric;
   discount numeric;
   totalPrice numeric;
   rate numeric;
   pointsAmount numeric := 0;
   amountUsable numeric := 0;
   balance numeric;
BEGIN
    SELECT * FROM brands."storeSetting" WHERE "identifier" = 'Loyalty Points Usage' AND "type" = 'rewards' INTO setting;
    SELECT * FROM brands."brand_storeSetting" WHERE "storeSettingId" = setting.id AND "brandId" = ordercart."brandId" INTO temp;
    IF temp IS NOT NULL THEN
        setting := temp;
    END IF;
    SELECT "order"."itemTotal"(cart.*) into itemTotal;
    SELECT "order"."deliveryPrice"(cart.*) into deliveryPrice;
    SELECT "order".tax(cart.*) into tax;
    SELECT "order".discount(cart.*) into discount;
    totalPrice := ROUND(itemTotal + deliveryPrice + cart.tip  + tax - discount, 2);
    amountUsable := totalPrice;
    -- if loyalty points are used
    IF cart."loyaltyPointsUsed" > 0 THEN
        SELECT crm."getLoyaltyPointsConversionRate"(cart."brandId") INTO rate;
        pointsAmount := rate * ordercart."loyaltyPointsUsed";
        amountUsable := amountUsable - pointsAmount;
    END IF;
    SELECT amount FROM crm."wallet" WHERE "keycloakId" = cart."customerKeycloakId" AND "brandId" = ordercart."brandId" INTO balance;
    IF amountUsable > balance THEN
        amountUsable := balance;
    END IF;
    -- if usable changes after cart update, then update used amount
    IF cart."walletAmountUsed" > amountUsable THEN
        PERFORM crm."setWalletAmountUsedInCart"(cart.id, amountUsable);
    END IF;
    RETURN amountUsable;
END;
$$;
CREATE VIEW products."comboComponentOptions" AS
SELECT t.id AS "comboComponentId",
       t."linkedProductId",
       ((option.value ->> 'optionId'::text))::integer AS "productOptionId",
       ((option.value ->> 'price'::text))::numeric AS price,
       ((option.value ->> 'discount'::text))::numeric AS discount,
       t."productId"
FROM products."comboProductComponent" t,
     LATERAL jsonb_array_elements(t.options) option(value);
CREATE FUNCTION products."comboProductComponentOptionCartItem"(componentoption products."comboComponentOptions") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    counter int;
    items jsonb[] := '{}';
    product record;
    option record;
BEGIN
    SELECT * FROM products.product WHERE id = componentOption."productId" INTO product;
    SELECT * FROM products."productOption" WHERE id = componentOption."productOptionId" INTO option;
    counter := option.quantity;
    IF option."simpleRecipeYieldId" IS NOT NULL THEN
        WHILE counter >= 1 LOOP
            items := items || json_build_object('simpleRecipeYieldId', option."simpleRecipeYieldId")::jsonb;
            counter := counter - 1;
        END LOOP;
    ELSEIF option."inventoryProductBundleId" IS NOT NULL THEN
        WHILE counter >= 1 LOOP
            items := items || json_build_object('inventoryProductBundleId', option."inventoryProductBundleId")::jsonb;
            counter := counter - 1;
        END LOOP;
    END IF;
    RETURN jsonb_build_object(
        'comboProductComponentId', componentOption."comboComponentId",
        'productOptionId', componentOption."productOptionId",
        'unitPrice', componentOption.price,
        'childs', json_build_object(
            'data', items
        )
    );
END;
$$;
CREATE FUNCTION products."customizableProductComponentOptionCartItem"(componentoption products."customizableComponentOptions") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    counter int;
    items jsonb[] := '{}';
    product record;
    option record;
BEGIN
    SELECT * FROM products.product WHERE id = componentOption."productId" INTO product;
    SELECT * FROM products."productOption" WHERE id = componentOption."productOptionId" INTO option;
    counter := option.quantity;
    IF option."simpleRecipeYieldId" IS NOT NULL THEN
        WHILE counter >= 1 LOOP
            items := items || json_build_object('simpleRecipeYieldId', option."simpleRecipeYieldId")::jsonb;
            counter := counter - 1;
        END LOOP;
    ELSEIF option."inventoryProductBundleId" IS NOT NULL THEN
        WHILE counter >= 1 LOOP
            items := items || json_build_object('inventoryProductBundleId', option."inventoryProductBundleId")::jsonb;
            counter := counter - 1;
        END LOOP;
    END IF;
    RETURN jsonb_build_object(
            'productId', product.id,
            'unitPrice', product.price,
            'childs', jsonb_build_object(
                'data', json_build_array(
                    json_build_object (
                        'customizableProductComponentId', componentOption."customizableComponentId",
                        'productOptionId', componentOption."productOptionId",
                        'unitPrice', componentOption.price,
                        'childs', json_build_object(
                            'data', items
                        )
                    )
                )
            )
        );
END;
$$;
CREATE OR REPLACE VIEW "order"."cartItemView" AS WITH RECURSIVE parent AS
    (SELECT "cartItem".id,
            "cartItem"."cartId",
            "cartItem"."parentCartItemId",
            "cartItem"."isModifier",
            "cartItem"."productId",
            "cartItem"."productOptionId",
            "cartItem"."comboProductComponentId",
            "cartItem"."customizableProductComponentId",
            "cartItem"."simpleRecipeYieldId",
            "cartItem"."sachetItemId",
            "cartItem"."subRecipeYieldId",
            "cartItem"."unitPrice",
            "cartItem"."refundPrice",
            "cartItem"."stationId",
            "cartItem"."labelTemplateId",
            "cartItem"."packagingId",
            "cartItem"."instructionCardTemplateId",
            "cartItem"."position",
            "cartItem".created_at,
            "cartItem".updated_at,
            "cartItem".accuracy,
            "cartItem"."ingredientSachetId",
            "cartItem"."isAddOn",
            "cartItem"."addOnLabel",
            "cartItem"."addOnPrice",
            "cartItem"."isAutoAdded",
            "cartItem"."inventoryProductBundleId",
            "cartItem"."subscriptionOccurenceProductId",
            "cartItem"."subscriptionOccurenceAddOnProductId",
            "cartItem".id AS "rootCartItemId",
            ("cartItem".id)::character varying(1000) AS path,
            1 AS level,

         (SELECT count("cartItem_1".id) AS count
          FROM "order"."cartItem" "cartItem_1"
          WHERE ("cartItem".id = "cartItem_1"."parentCartItemId")) AS count,
            CASE
                WHEN ("cartItem"."productOptionId" IS NOT NULL) THEN
                         (SELECT "productOption".type
                          FROM products."productOption"
                          WHERE ("productOption".id = "cartItem"."productOptionId"))
                ELSE NULL::text
            END AS "productOptionType",
            "cartItem".status
     FROM "order"."cartItem"
     WHERE ("cartItem"."productId" IS NOT NULL)
     UNION SELECT c.id,
                  COALESCE(c."cartId", p."cartId") AS "cartId",
                  c."parentCartItemId",
                  c."isModifier",
                  p."productId",
                  COALESCE(c."productOptionId", p."productOptionId") AS "productOptionId",
                  COALESCE(c."comboProductComponentId", p."comboProductComponentId") AS "comboProductComponentId",
                  COALESCE(c."customizableProductComponentId", p."customizableProductComponentId") AS "customizableProductComponentId",
                  COALESCE(c."simpleRecipeYieldId", p."simpleRecipeYieldId") AS "simpleRecipeYieldId",
                  COALESCE(c."sachetItemId", p."sachetItemId") AS "sachetItemId",
                  COALESCE(c."subRecipeYieldId", p."subRecipeYieldId") AS "subRecipeYieldId",
                  c."unitPrice",
                  c."refundPrice",
                  c."stationId",
                  c."labelTemplateId",
                  c."packagingId",
                  c."instructionCardTemplateId",
                  c."position",
                  c.created_at,
                  c.updated_at,
                  c.accuracy,
                  c."ingredientSachetId",
                  c."isAddOn",
                  c."addOnLabel",
                  c."addOnPrice",
                  c."isAutoAdded",
                  c."inventoryProductBundleId",
                  c."subscriptionOccurenceProductId",
                  c."subscriptionOccurenceAddOnProductId",
                  p."rootCartItemId",
                  ((((p.path)::text || '->'::text) || c.id))::character varying(1000) AS path,
                  (p.level + 1) AS level,

         (SELECT count("cartItem".id) AS count
          FROM "order"."cartItem"
          WHERE ("cartItem"."parentCartItemId" = c.id)) AS count,
                  CASE
                      WHEN (c."productOptionId" IS NOT NULL) THEN
                               (SELECT "productOption".type
                                FROM products."productOption"
                                WHERE ("productOption".id = c."productOptionId"))
                      WHEN (p."productOptionId" IS NOT NULL) THEN
                               (SELECT "productOption".type
                                FROM products."productOption"
                                WHERE ("productOption".id = p."productOptionId"))
                      ELSE NULL::text
                  END AS "productOptionType",
                  c.status
     FROM ("order"."cartItem" c
           JOIN parent p ON ((p.id = c."parentCartItemId"))))
SELECT parent.id,
       parent."cartId",
       parent."parentCartItemId",
       parent."isModifier",
       parent."productId",
       parent."productOptionId",
       parent."comboProductComponentId",
       parent."customizableProductComponentId",
       parent."simpleRecipeYieldId",
       parent."sachetItemId",
       parent."unitPrice",
       parent."refundPrice",
       parent."stationId",
       parent."labelTemplateId",
       parent."packagingId",
       parent."instructionCardTemplateId",
       parent."position",
       parent.created_at,
       parent.updated_at,
       parent.accuracy,
       parent."ingredientSachetId",
       parent."isAddOn",
       parent."addOnLabel",
       parent."addOnPrice",
       parent."isAutoAdded",
       parent."inventoryProductBundleId",
       parent."subscriptionOccurenceProductId",
       parent."subscriptionOccurenceAddOnProductId",
       parent."rootCartItemId",
       parent.path,
       parent.level,
       parent.count,
       CASE
           WHEN (parent.level = 1) THEN 'productItem'::text
           WHEN ((parent.level = 2)
                 AND (parent.count > 0)) THEN 'productItemComponent'::text
           WHEN ((parent.level = 2)
                 AND (parent.count = 0)) THEN 'orderItem'::text
           WHEN (parent.level = 3) THEN 'orderItem'::text
           WHEN (parent.level = 4) THEN 'orderItemSachet'::text
           WHEN (parent.level > 4) THEN 'orderItemSachetComponent'::text
           ELSE NULL::text
       END AS "levelType",
       btrim(COALESCE(concat(
                                 (SELECT product.name
                                  FROM products.product
                                  WHERE (product.id = parent."productId")),
                                 (SELECT (' -> '::text || "productOptionView"."displayName")
                                  FROM products."productOptionView"
                                  WHERE ("productOptionView".id = parent."productOptionId")),
                                 (SELECT (' -> '::text || "comboProductComponent".label)
                                  FROM products."comboProductComponent"
                                  WHERE ("comboProductComponent".id = parent."comboProductComponentId")),
                                 (SELECT (' -> '::text || "simpleRecipeYieldView"."displayName")
                                  FROM "simpleRecipe"."simpleRecipeYieldView"
                                  WHERE ("simpleRecipeYieldView".id = parent."simpleRecipeYieldId")), CASE
                                                                                                          WHEN (parent."inventoryProductBundleId" IS NOT NULL) THEN
                                                                                                                   (SELECT (' -> '::text || "productOptionView"."displayName")
                                                                                                                    FROM products."productOptionView"
                                                                                                                    WHERE ("productOptionView".id =
                                                                                                                               (SELECT "cartItem"."productOptionId"
                                                                                                                                FROM "order"."cartItem"
                                                                                                                                WHERE ("cartItem".id = parent."parentCartItemId"))))
                                                                                                          ELSE ''::text
                                                                                                      END,
                                 (SELECT (' -> '::text || "ingredientSachetView"."displayName")
                                  FROM ingredient."ingredientSachetView"
                                  WHERE ("ingredientSachetView".id = parent."ingredientSachetId")),
                                 (SELECT (' -> '::text || "sachetItemView"."supplierItemName")
                                  FROM inventory."sachetItemView"
                                  WHERE ("sachetItemView".id = parent."sachetItemId"))), 'N/A'::text)) AS "displayName",
       COALESCE(
                    (SELECT "ingredientProcessing"."processingName"
                     FROM ingredient."ingredientProcessing"
                     WHERE ("ingredientProcessing".id =
                                (SELECT "ingredientSachet"."ingredientProcessingId"
                                 FROM ingredient."ingredientSachet"
                                 WHERE ("ingredientSachet".id = parent."ingredientSachetId")))),
                    (SELECT "sachetItemView"."processingName"
                     FROM inventory."sachetItemView"
                     WHERE ("sachetItemView".id = parent."sachetItemId")), 'N/A'::text) AS "processingName",
       COALESCE(
                    (SELECT "modeOfFulfillment"."operationConfigId"
                     FROM ingredient."modeOfFulfillment"
                     WHERE ("modeOfFulfillment".id =
                                (SELECT "ingredientSachet"."liveMOF"
                                 FROM ingredient."ingredientSachet"
                                 WHERE ("ingredientSachet".id = "modeOfFulfillment"."ingredientSachetId")))),
                    (SELECT "productOption"."operationConfigId"
                     FROM products."productOption"
                     WHERE ("productOption".id = parent."productOptionId")), NULL::integer) AS "operationConfigId",
       COALESCE(
                    (SELECT "ingredientSachet".unit
                     FROM ingredient."ingredientSachet"
                     WHERE ("ingredientSachet".id = parent."ingredientSachetId")),
                    (SELECT "sachetItemView".unit
                     FROM inventory."sachetItemView"
                     WHERE ("sachetItemView".id = parent."sachetItemId")),
                    (SELECT "simpleRecipeYield".unit
                     FROM "simpleRecipe"."simpleRecipeYield"
                     WHERE ("simpleRecipeYield".id = parent."subRecipeYieldId")), NULL::text) AS "displayUnit",
       COALESCE(
                    (SELECT "ingredientSachet".quantity
                     FROM ingredient."ingredientSachet"
                     WHERE ("ingredientSachet".id = parent."ingredientSachetId")),
                    (SELECT "sachetItemView"."unitSize"
                     FROM inventory."sachetItemView"
                     WHERE ("sachetItemView".id = parent."sachetItemId")),
                    (SELECT "simpleRecipeYield".quantity
                     FROM "simpleRecipe"."simpleRecipeYield"
                     WHERE ("simpleRecipeYield".id = parent."subRecipeYieldId")), NULL::numeric) AS "displayUnitQuantity",
       CASE
           WHEN (parent."subRecipeYieldId" IS NOT NULL) THEN 'subRecipeYield'::text
           WHEN (parent."ingredientSachetId" IS NOT NULL) THEN 'ingredientSachet'::text
           WHEN (parent."sachetItemId" IS NOT NULL) THEN 'sachetItem'::text
           WHEN (parent."simpleRecipeYieldId" IS NOT NULL) THEN 'simpleRecipeYield'::text
           WHEN (parent."inventoryProductBundleId" IS NOT NULL) THEN 'inventoryProductBundle'::text
           WHEN (parent."productOptionId" IS NOT NULL) THEN 'productComponent'::text
           WHEN (parent."productId" IS NOT NULL) THEN 'product'::text
           ELSE NULL::text
       END AS "cartItemType",
       CASE
           WHEN (parent."productId" IS NOT NULL) THEN
                    (SELECT ((product.assets -> 'images'::text) -> 0)
                     FROM products.product
                     WHERE (product.id = parent."productId"))
           WHEN (parent."productOptionId" IS NOT NULL) THEN
                    (SELECT "productOptionView"."displayImage"
                     FROM products."productOptionView"
                     WHERE ("productOptionView".id = parent."productOptionId"))
           WHEN (parent."simpleRecipeYieldId" IS NOT NULL) THEN
                    (SELECT "productOptionView"."displayImage"
                     FROM products."productOptionView"
                     WHERE ("productOptionView".id =
                                (SELECT "cartItem"."productOptionId"
                                 FROM "order"."cartItem"
                                 WHERE ("cartItem".id = parent."parentCartItemId"))))
           ELSE NULL::jsonb
       END AS "displayImage",
       CASE
           WHEN (parent."sachetItemId" IS NOT NULL) THEN
                    (SELECT "sachetItemView"."bulkDensity"
                     FROM inventory."sachetItemView"
                     WHERE ("sachetItemView".id = parent."sachetItemId"))
           ELSE NULL::numeric
       END AS "displayBulkDensity",
       parent."productOptionType",
       COALESCE(
                    (SELECT "simpleRecipeComponent_productOptionType"."orderMode"
                     FROM "simpleRecipe"."simpleRecipeComponent_productOptionType"
                     WHERE (("simpleRecipeComponent_productOptionType"."productOptionType" = parent."productOptionType")
                            AND ("simpleRecipeComponent_productOptionType"."simpleRecipeComponentId" =
                                     (SELECT "simpleRecipeYield_ingredientSachet"."simpleRecipeIngredientProcessingId"
                                      FROM "simpleRecipe"."simpleRecipeYield_ingredientSachet"
                                      WHERE (("simpleRecipeYield_ingredientSachet"."recipeYieldId" = parent."simpleRecipeYieldId")
                                             AND (("simpleRecipeYield_ingredientSachet"."ingredientSachetId" = parent."ingredientSachetId")
                                                  OR ("simpleRecipeYield_ingredientSachet"."subRecipeYieldId" = parent."subRecipeYieldId")))
                                      LIMIT 1)))
                     LIMIT 1),
                    (SELECT "simpleRecipe_productOptionType"."orderMode"
                     FROM "simpleRecipe"."simpleRecipe_productOptionType"
                     WHERE ("simpleRecipe_productOptionType"."simpleRecipeId" =
                                (SELECT "simpleRecipeYield"."simpleRecipeId"
                                 FROM "simpleRecipe"."simpleRecipeYield"
                                 WHERE ("simpleRecipeYield".id = parent."simpleRecipeYieldId")))),
                    (SELECT "productOptionType"."orderMode"
                     FROM products."productOptionType"
                     WHERE ("productOptionType".title = parent."productOptionType")), 'undefined'::text) AS "orderMode",
       parent."subRecipeYieldId",
       COALESCE(
                    (SELECT "simpleRecipeYield".serving
                     FROM "simpleRecipe"."simpleRecipeYield"
                     WHERE ("simpleRecipeYield".id = parent."subRecipeYieldId")),
                    (SELECT "simpleRecipeYield".serving
                     FROM "simpleRecipe"."simpleRecipeYield"
                     WHERE ("simpleRecipeYield".id = parent."simpleRecipeYieldId")), NULL::numeric) AS "displayServing",
       CASE
           WHEN (parent."ingredientSachetId" IS NOT NULL) THEN
                    (SELECT "ingredientSachet"."ingredientId"
                     FROM ingredient."ingredientSachet"
                     WHERE ("ingredientSachet".id = parent."ingredientSachetId"))
           ELSE NULL::integer
       END AS "ingredientId",
       CASE
           WHEN (parent."ingredientSachetId" IS NOT NULL) THEN
                    (SELECT "ingredientSachet"."ingredientProcessingId"
                     FROM ingredient."ingredientSachet"
                     WHERE ("ingredientSachet".id = parent."ingredientSachetId"))
           ELSE NULL::integer
       END AS "ingredientProcessingId",
       CASE
           WHEN (parent."sachetItemId" IS NOT NULL) THEN
                    (SELECT "sachetItem"."bulkItemId"
                     FROM inventory."sachetItem"
                     WHERE ("sachetItem".id = parent."sachetItemId"))
           ELSE NULL::integer
       END AS "bulkItemId",
       CASE
           WHEN (parent."sachetItemId" IS NOT NULL) THEN
                    (SELECT "bulkItem"."supplierItemId"
                     FROM inventory."bulkItem"
                     WHERE ("bulkItem".id =
                                (SELECT "sachetItem"."bulkItemId"
                                 FROM inventory."sachetItem"
                                 WHERE ("sachetItem".id = parent."sachetItemId"))))
           ELSE NULL::integer
       END AS "supplierItemId",
       parent.status
FROM parent;
CREATE VIEW "order"."ordersAggregate" AS
SELECT "orderStatusEnum".title,
       "orderStatusEnum".value,
       "orderStatusEnum".index,

    (SELECT COALESCE(sum("order"."amountPaid"), (0)::numeric) AS "coalesce"
     FROM ("order"."order"
           JOIN "order".cart ON (("order"."cartId" = cart.id)))
     WHERE ((("order"."isRejected" IS NULL)
             OR ("order"."isRejected" = false))
            AND (cart.status = "orderStatusEnum".value))) AS "totalOrderSum",

    (SELECT COALESCE(avg("order"."amountPaid"), (0)::numeric) AS "coalesce"
     FROM ("order"."order"
           JOIN "order".cart ON (("order"."cartId" = cart.id)))
     WHERE ((("order"."isRejected" IS NULL)
             OR ("order"."isRejected" = false))
            AND (cart.status = "orderStatusEnum".value))) AS "totalOrderAverage",

    (SELECT count(*) AS count
     FROM ("order"."order"
           JOIN "order".cart ON (("order"."cartId" = cart.id)))
     WHERE ((("order"."isRejected" IS NULL)
             OR ("order"."isRejected" = false))
            AND (cart.status = "orderStatusEnum".value))) AS "totalOrders"
FROM "order"."orderStatusEnum"
ORDER BY "orderStatusEnum".index;
CREATE TRIGGER handle_create_sachets AFTER
INSERT ON "order"."cartItem"
FOR EACH ROW EXECUTE FUNCTION "order"."createSachets"();
CREATE TRIGGER "onPaymentSuccess" AFTER
UPDATE OF "paymentStatus" ON "order".cart
FOR EACH ROW EXECUTE FUNCTION "order"."onPaymentSuccess"();

CREATE OR REPLACE FUNCTION "order".on_cart_item_status_change() RETURNS trigger LANGUAGE plpgsql AS $function$
DECLARE
    totalReady integer := 0;
    totalPacked integer := 0;
    totalItems integer := 0;
BEGIN
    IF NEW.status = OLD.status THEN
        RETURN NULL;
    END IF;

    -- mark children packed if parent ready/packed
    IF NEW.status = 'READY' OR NEW.status = 'PACKED' THEN
        UPDATE "order"."cartItem" SET status = 'PACKED' WHERE "parentCartItemId" = NEW.id;
    END IF;

    IF NEW.status = 'READY_FOR_PACKING' OR NEW.status = 'READY' THEN
        IF NEW."parentCartItemId" IS NULL THEN
            UPDATE "order"."cartItem" SET status = 'PACKED' WHERE id = NEW.id; -- product
        ELSEIF (SELECT "parentCartItemId" FROM "order"."cartItem" WHERE id = NEW."parentCartItemId") IS NULL THEN
            UPDATE "order"."cartItem" SET status = 'PACKED' WHERE id = NEW.id; -- productComponent
        END IF;
    END IF;

    IF NEW.status = 'READY' THEN
        SELECT COUNT(*) INTO totalReady FROM "order"."cartItem" WHERE "parentCartItemId" = NEW."parentCartItemId" AND status = 'READY';
        SELECT COUNT(*) INTO totalItems FROM "order"."cartItem" WHERE "parentCartItemId" = NEW."parentCartItemId";
        IF totalReady = totalItems THEN
            UPDATE "order"."cartItem" SET status = 'READY_FOR_PACKING' WHERE id = NEW."parentCartItemId";
        END IF;
    END IF;

    IF NEW.status = 'PACKED' THEN
        SELECT COUNT(*) INTO totalPacked FROM "order"."cartItem" WHERE "parentCartItemId" = NEW."parentCartItemId" AND status = 'PACKED';
        SELECT COUNT(*) INTO totalItems FROM "order"."cartItem" WHERE "parentCartItemId" = NEW."parentCartItemId";
        IF totalPacked = totalItems THEN
            UPDATE "order"."cartItem" SET status = 'READY' WHERE id = NEW."parentCartItemId" AND status = 'PENDING';
        END IF;
    END IF;

    -- check order item status
    IF (SELECT status FROM "order".cart WHERE id = NEW."cartId") = 'ORDER_PENDING' THEN
        UPDATE "order".cart SET status = 'ORDER_UNDER_PROCESSING' WHERE id = NEW."cartId";
    END IF;

    IF NEW."parentCartItemId" IS NOT NULL THEN
        RETURN NULL;
    END IF;

    SELECT COUNT(*) INTO totalReady FROM "order"."cartItem" WHERE "parentCartItemId" IS NULL AND "cartId" = NEW."cartId" AND status = 'READY';
    SELECT COUNT(*) INTO totalPacked FROM "order"."cartItem" WHERE "parentCartItemId" IS NULL AND "cartId" = NEW."cartId" AND status = 'PACKED';
    SELECT COUNT(*) INTO totalItems FROM "order"."cartItem" WHERE "parentCartItemId" IS NULL AND "cartId" = NEW."cartId";

    IF totalReady = totalItems THEN
        UPDATE "order".cart SET status = 'ORDER_READY_TO_ASSEMBLE' WHERE id = NEW."cartId";
    ELSEIF totalPacked = totalItems THEN
        UPDATE "order".cart SET status = 'ORDER_READY_TO_DISPATCH' WHERE id = NEW."cartId";
    END IF;

    RETURN NULL;
END;
$function$;

CREATE TRIGGER "on_cart_item_status_change" AFTER
UPDATE of status ON "order"."cartItem"
FOR EACH ROW EXECUTE procedure "order".on_cart_item_status_change();
CREATE OR REPLACE FUNCTION "order".on_cart_status_change() RETURNS trigger LANGUAGE plpgsql AS $function$
DECLARE
    item "order"."cartItem";
    packedCount integer := 0;
    readyCount integer := 0;
BEGIN
    IF OLD.status = NEW.status THEN
        RETURN NULL;
    END IF;

    IF NEW.status = 'ORDER_READY_TO_ASSEMBLE' THEN
        FOR item IN SELECT * FROM "order"."cartItem" WHERE "parentCartItemId" IS NULL AND "cartId" = NEW.id LOOP
            UPDATE "order"."cartItem" SET status = 'READY' WHERE id = item.id;
        END LOOP;
    ELSEIF NEW.status = 'ORDER_READY_FOR_DISPATCH' THEN
        FOR item IN SELECT * FROM "order"."cartItem" WHERE "parentCartItemId" IS NULL AND "cartId" = NEW.id LOOP
            UPDATE "order"."cartItem" SET status = 'PACKED' WHERE id = item.id;
        END LOOP;
    ELSEIF NEW.status = 'ORDER_OUT_FOR_DELIVERY' OR NEW.status = 'ORDER_DELIVERED' THEN
        FOR item IN SELECT * FROM "order"."cartItem" WHERE "parentCartItemId" IS NULL AND "cartId" = NEW.id LOOP
            UPDATE "order"."cartItem" SET status = 'PACKED' WHERE id = item.id;
        END LOOP;
    END IF;

    RETURN NULL;
END;
$function$;

CREATE TRIGGER "on_cart_status_change" AFTER
UPDATE of status ON "order"."cart"
FOR EACH ROW EXECUTE procedure "order".on_cart_status_change();
CREATE TRIGGER "set_order_orderCartItem_updated_at"
BEFORE
UPDATE ON "order"."cartItem"
FOR EACH ROW EXECUTE FUNCTION "order".set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_order_orderCartItem_updated_at" ON "order"."cartItem" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_order_orderCart_updated_at"
BEFORE
UPDATE ON "order".cart
FOR EACH ROW EXECUTE FUNCTION "order".set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_order_orderCart_updated_at" ON "order".cart IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_order_order_updated_at
BEFORE
UPDATE ON "order"."order"
FOR EACH ROW EXECUTE FUNCTION "order".set_current_timestamp_updated_at(); COMMENT ON TRIGGER set_order_order_updated_at ON "order"."order" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_products_comboProductComponent_updated_at"
BEFORE
UPDATE ON products."comboProductComponent"
FOR EACH ROW EXECUTE FUNCTION products.set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_products_comboProductComponent_updated_at" ON products."comboProductComponent" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_products_customizableProductOption_updated_at"
BEFORE
UPDATE ON products."customizableProductComponent"
FOR EACH ROW EXECUTE FUNCTION products.set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_products_customizableProductOption_updated_at" ON products."customizableProductComponent" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_products_productOption_updated_at"
BEFORE
UPDATE ON products."productOption"
FOR EACH ROW EXECUTE FUNCTION products.set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_products_productOption_updated_at" ON products."productOption" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_products_product_updated_at
BEFORE
UPDATE ON products.product
FOR EACH ROW EXECUTE FUNCTION products.set_current_timestamp_updated_at(); COMMENT ON TRIGGER set_products_product_updated_at ON products.product IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_safety_safetyCheck_updated_at"
BEFORE
UPDATE ON safety."safetyCheck"
FOR EACH ROW EXECUTE FUNCTION safety.set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_safety_safetyCheck_updated_at" ON safety."safetyCheck" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_settings_apps_updated_at
BEFORE
UPDATE ON settings.app
FOR EACH ROW EXECUTE FUNCTION settings.set_current_timestamp_updated_at(); COMMENT ON TRIGGER set_settings_apps_updated_at ON settings.app IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_settings_operationConfig_updated_at"
BEFORE
UPDATE ON settings."operationConfig"
FOR EACH ROW EXECUTE FUNCTION settings.set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_settings_operationConfig_updated_at" ON settings."operationConfig" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_settings_role_app_updated_at
BEFORE
UPDATE ON settings.role_app
FOR EACH ROW EXECUTE FUNCTION settings.set_current_timestamp_updated_at(); COMMENT ON TRIGGER set_settings_role_app_updated_at ON settings.role_app IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_settings_roles_updated_at
BEFORE
UPDATE ON settings.role
FOR EACH ROW EXECUTE FUNCTION settings.set_current_timestamp_updated_at(); COMMENT ON TRIGGER set_settings_roles_updated_at ON settings.role IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_settings_user_role_updated_at
BEFORE
UPDATE ON settings.user_role
FOR EACH ROW EXECUTE FUNCTION settings.set_current_timestamp_updated_at(); COMMENT ON TRIGGER set_settings_user_role_updated_at ON settings.user_role IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_simpleRecipe_simpleRecipe_updated_at"
BEFORE
UPDATE ON "simpleRecipe"."simpleRecipe"
FOR EACH ROW EXECUTE FUNCTION "simpleRecipe".set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_simpleRecipe_simpleRecipe_updated_at" ON "simpleRecipe"."simpleRecipe" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_subscription_subscriptionOccurence_addOn_updated_at"
BEFORE
UPDATE ON subscription."subscriptionOccurence_addOn"
FOR EACH ROW EXECUTE FUNCTION subscription.set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_subscription_subscriptionOccurence_addOn_updated_at" ON subscription."subscriptionOccurence_addOn" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_subscription_subscriptionOccurence_product_updated_at"
BEFORE
UPDATE ON subscription."subscriptionOccurence_product"
FOR EACH ROW EXECUTE FUNCTION subscription.set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_subscription_subscriptionOccurence_product_updated_at" ON subscription."subscriptionOccurence_product" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_subscription_subscriptionPickupOption_updated_at"
BEFORE
UPDATE ON subscription."subscriptionPickupOption"
FOR EACH ROW EXECUTE FUNCTION subscription.set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_subscription_subscriptionPickupOption_updated_at" ON subscription."subscriptionPickupOption" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_subscription_subscriptionTitle_updated_at"
BEFORE
UPDATE ON subscription."subscriptionTitle"
FOR EACH ROW EXECUTE FUNCTION subscription.set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_subscription_subscriptionTitle_updated_at" ON subscription."subscriptionTitle" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_website_website_updated_at
BEFORE
UPDATE ON website.website
FOR EACH ROW EXECUTE FUNCTION website.set_current_timestamp_updated_at(); COMMENT ON TRIGGER set_website_website_updated_at ON website.website IS 'trigger to set value of column "updated_at" to current timestamp on row update';
ALTER TABLE ONLY brands.brand ADD CONSTRAINT "brand_importHistoryId_fkey"
FOREIGN KEY ("importHistoryId") REFERENCES imports."importHistory"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY brands."brand_paymentPartnership" ADD CONSTRAINT "brand_paymentPartnership_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY brands."brand_storeSetting" ADD CONSTRAINT "brand_storeSetting_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY brands."brand_storeSetting" ADD CONSTRAINT "brand_storeSetting_importHistoryId_fkey"
FOREIGN KEY ("importHistoryId") REFERENCES imports."importHistory"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY brands."brand_storeSetting" ADD CONSTRAINT "brand_storeSetting_storeSettingId_fkey"
FOREIGN KEY ("storeSettingId") REFERENCES brands."storeSetting"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY brands."brand_subscriptionStoreSetting" ADD CONSTRAINT "brand_subscriptionStoreSetting_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY brands."brand_subscriptionStoreSetting" ADD CONSTRAINT "brand_subscriptionStoreSetting_subscriptionStoreSettingId_fk"
FOREIGN KEY ("subscriptionStoreSettingId") REFERENCES brands."subscriptionStoreSetting"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY content.identifier ADD CONSTRAINT "identifier_pageTitle_fkey"
FOREIGN KEY ("pageTitle") REFERENCES content.page(title) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY content."subscriptionDivIds" ADD CONSTRAINT "subscriptionDivIds_fileId_fkey"
FOREIGN KEY ("fileId") REFERENCES editor.file(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.brand_customer ADD CONSTRAINT "brandCustomer_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.brand_customer ADD CONSTRAINT "brandCustomer_keycloakId_fkey"
FOREIGN KEY ("keycloakId") REFERENCES crm.customer("keycloakId") ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY crm.brand_campaign ADD CONSTRAINT "brand_campaign_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.brand_campaign ADD CONSTRAINT "brand_campaign_campaignId_fkey"
FOREIGN KEY ("campaignId") REFERENCES crm.campaign(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.brand_coupon ADD CONSTRAINT "brand_coupon_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.brand_coupon ADD CONSTRAINT "brand_coupon_couponId_fkey"
FOREIGN KEY ("couponId") REFERENCES crm.coupon(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.brand_customer ADD CONSTRAINT "brand_customer_subscriptionId_fkey"
FOREIGN KEY ("subscriptionId") REFERENCES subscription.subscription(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.campaign ADD CONSTRAINT "campaign_conditionId_fkey"
FOREIGN KEY ("conditionId") REFERENCES rules.conditions(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.campaign ADD CONSTRAINT campaign_type_fkey
FOREIGN KEY (type) REFERENCES crm."campaignType"(value) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.coupon ADD CONSTRAINT "coupon_visibleConditionId_fkey"
FOREIGN KEY ("visibleConditionId") REFERENCES rules.conditions(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."customerReferral" ADD CONSTRAINT "customerReferral_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."customerReferral" ADD CONSTRAINT "customerReferral_campaignId_fkey"
FOREIGN KEY ("referralCampaignId") REFERENCES crm.campaign(id);
ALTER TABLE ONLY crm."customerReferral" ADD CONSTRAINT "customerReferral_keycloakId_fkey"
FOREIGN KEY ("keycloakId") REFERENCES crm.customer("keycloakId") ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."customerReferral" ADD CONSTRAINT "customerReferral_referredByCode_fkey"
FOREIGN KEY ("referredByCode") REFERENCES crm."customerReferral"("referralCode") ON
UPDATE RESTRICT ON
DELETE
SET NULL;
ALTER TABLE ONLY crm.customer ADD CONSTRAINT "customer_subscriptionId_fkey"
FOREIGN KEY ("subscriptionId") REFERENCES subscription.subscription(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."loyaltyPointTransaction" ADD CONSTRAINT "loyaltyPointTransaction_customerReferralId_fkey"
FOREIGN KEY ("customerReferralId") REFERENCES crm."customerReferral"(id) ON
DELETE
SET NULL;
ALTER TABLE ONLY crm."loyaltyPointTransaction" ADD CONSTRAINT "loyaltyPointTransaction_loyaltyPointId_fkey"
FOREIGN KEY ("loyaltyPointId") REFERENCES crm."loyaltyPoint"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."loyaltyPointTransaction" ADD CONSTRAINT "loyaltyPointTransaction_orderCartId_fkey"
FOREIGN KEY ("orderCartId") REFERENCES "order".cart(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY crm."loyaltyPoint" ADD CONSTRAINT "loyaltyPoint_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."loyaltyPoint" ADD CONSTRAINT "loyaltyPoint_keycloakId_fkey"
FOREIGN KEY ("keycloakId") REFERENCES crm.customer("keycloakId") ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."orderCart_rewards" ADD CONSTRAINT "orderCart_rewards_orderCartId_fkey"
FOREIGN KEY ("orderCartId") REFERENCES "order".cart(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY crm."orderCart_rewards" ADD CONSTRAINT "orderCart_rewards_rewardId_fkey"
FOREIGN KEY ("rewardId") REFERENCES crm.reward(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory" ADD CONSTRAINT "rewardHistory_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory" ADD CONSTRAINT "rewardHistory_campaignId_fkey"
FOREIGN KEY ("campaignId") REFERENCES crm.campaign(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory" ADD CONSTRAINT "rewardHistory_couponId_fkey"
FOREIGN KEY ("couponId") REFERENCES crm.coupon(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory" ADD CONSTRAINT "rewardHistory_keycloakId_fkey"
FOREIGN KEY ("keycloakId") REFERENCES crm.customer("keycloakId") ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory" ADD CONSTRAINT "rewardHistory_loyaltyPointTransactionId_fkey"
FOREIGN KEY ("loyaltyPointTransactionId") REFERENCES crm."loyaltyPointTransaction"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory" ADD CONSTRAINT "rewardHistory_orderCartId_fkey"
FOREIGN KEY ("orderCartId") REFERENCES "order".cart(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory" ADD CONSTRAINT "rewardHistory_orderId_fkey"
FOREIGN KEY ("orderId") REFERENCES "order"."order"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY crm."rewardHistory" ADD CONSTRAINT "rewardHistory_rewardId_fkey"
FOREIGN KEY ("rewardId") REFERENCES crm.reward(id) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory" ADD CONSTRAINT "rewardHistory_walletTransactionId_fkey"
FOREIGN KEY ("walletTransactionId") REFERENCES crm."walletTransaction"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardType_campaignType" ADD CONSTRAINT "rewardType_campaignType_campaignTypeId_fkey"
FOREIGN KEY ("campaignTypeId") REFERENCES crm."campaignType"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardType_campaignType" ADD CONSTRAINT "rewardType_campaignType_rewardTypeId_fkey"
FOREIGN KEY ("rewardTypeId") REFERENCES crm."rewardType"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.reward ADD CONSTRAINT "reward_campaignId_fkey"
FOREIGN KEY ("campaignId") REFERENCES crm.campaign(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.reward ADD CONSTRAINT "reward_conditionId_fkey"
FOREIGN KEY ("conditionId") REFERENCES rules.conditions(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.reward ADD CONSTRAINT "reward_couponId_fkey"
FOREIGN KEY ("couponId") REFERENCES crm.coupon(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."walletTransaction" ADD CONSTRAINT "walletTransaction_customerReferralId_fkey"
FOREIGN KEY ("customerReferralId") REFERENCES crm."customerReferral"(id);
ALTER TABLE ONLY crm."walletTransaction" ADD CONSTRAINT "walletTransaction_orderCartId_fkey"
FOREIGN KEY ("orderCartId") REFERENCES "order".cart(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY crm."walletTransaction" ADD CONSTRAINT "walletTransaction_walletId_fkey"
FOREIGN KEY ("walletId") REFERENCES crm.wallet(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.wallet ADD CONSTRAINT "wallet_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.wallet ADD CONSTRAINT "wallet_keycloakId_fkey"
FOREIGN KEY ("keycloakId") REFERENCES crm.customer("keycloakId") ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "deviceHub".printer ADD CONSTRAINT "printer_computerId_fkey"
FOREIGN KEY ("computerId") REFERENCES "deviceHub".computer("printNodeId") ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY "deviceHub".printer ADD CONSTRAINT "printer_printerType_fkey"
FOREIGN KEY ("printerType") REFERENCES "deviceHub"."printerType"(type) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "deviceHub".scale ADD CONSTRAINT "scale_computerId_fkey"
FOREIGN KEY ("computerId") REFERENCES "deviceHub".computer("printNodeId") ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "deviceHub".scale ADD CONSTRAINT "scale_stationId_fkey"
FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY editor."cssFileLinks" ADD CONSTRAINT "cssFileLinks_cssFileId_fkey"
FOREIGN KEY ("cssFileId") REFERENCES editor.file(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY editor."cssFileLinks" ADD CONSTRAINT "cssFileLinks_guiFileId_fkey"
FOREIGN KEY ("guiFileId") REFERENCES editor.file(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY editor."jsFileLinks" ADD CONSTRAINT "jsFileLinks_guiFileId_fkey"
FOREIGN KEY ("guiFileId") REFERENCES editor.file(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY editor."jsFileLinks" ADD CONSTRAINT "jsFileLinks_jsFileId_fkey"
FOREIGN KEY ("jsFileId") REFERENCES editor.file(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY fulfilment.brand_recurrence ADD CONSTRAINT "brand_recurrence_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY fulfilment.brand_recurrence ADD CONSTRAINT "brand_recurrence_recurrenceId_fkey"
FOREIGN KEY ("recurrenceId") REFERENCES fulfilment.recurrence(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY fulfilment.charge ADD CONSTRAINT "charge_mileRangeId_fkey"
FOREIGN KEY ("mileRangeId") REFERENCES fulfilment."mileRange"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY fulfilment."deliveryPreferenceByCharge" ADD CONSTRAINT "deliveryPreferenceByCharge_chargeId_fkey"
FOREIGN KEY ("chargeId") REFERENCES fulfilment.charge(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY fulfilment."deliveryPreferenceByCharge" ADD CONSTRAINT "deliveryPreferenceByCharge_clauseId_fkey"
FOREIGN KEY ("clauseId") REFERENCES fulfilment."deliveryService"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY fulfilment."mileRange" ADD CONSTRAINT "mileRange_timeSlotId_fkey"
FOREIGN KEY ("timeSlotId") REFERENCES fulfilment."timeSlot"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY fulfilment.recurrence ADD CONSTRAINT recurrence_type_fkey
FOREIGN KEY (type) REFERENCES fulfilment."fulfillmentType"(value) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY fulfilment."timeSlot" ADD CONSTRAINT "timeSlot_recurrenceId_fkey"
FOREIGN KEY ("recurrenceId") REFERENCES fulfilment.recurrence(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY imports."importHistory" ADD CONSTRAINT "importHistory_importId_fkey"
FOREIGN KEY ("importId") REFERENCES imports.import(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY ingredient."ingredientProcessing" ADD CONSTRAINT "ingredientProcessing_ingredientId_fkey"
FOREIGN KEY ("ingredientId") REFERENCES ingredient.ingredient(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY ingredient."ingredientProcessing" ADD CONSTRAINT "ingredientProcessing_processingName_fkey"
FOREIGN KEY ("processingName") REFERENCES master."processingName"(name) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY ingredient."ingredientSacahet_recipeHubSachet" ADD CONSTRAINT "ingredientSacahet_recipeHubSachet_ingredientSachetId_fkey"
FOREIGN KEY ("ingredientSachetId") REFERENCES ingredient."ingredientSachet"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY ingredient."ingredientSachet" ADD CONSTRAINT "ingredientSachet_ingredientId_fkey"
FOREIGN KEY ("ingredientId") REFERENCES ingredient.ingredient(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY ingredient."ingredientSachet" ADD CONSTRAINT "ingredientSachet_ingredientProcessingId_fkey"
FOREIGN KEY ("ingredientProcessingId") REFERENCES ingredient."ingredientProcessing"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY ingredient."ingredientSachet" ADD CONSTRAINT "ingredientSachet_liveMOF_fkey"
FOREIGN KEY ("liveMOF") REFERENCES ingredient."modeOfFulfillment"(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY ingredient."ingredientSachet" ADD CONSTRAINT "ingredientSachet_unit_fkey"
FOREIGN KEY (unit) REFERENCES master.unit(name) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY ingredient."modeOfFulfillment" ADD CONSTRAINT "modeOfFulfillment_bulkItemId_fkey"
FOREIGN KEY ("bulkItemId") REFERENCES inventory."bulkItem"(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY ingredient."modeOfFulfillment" ADD CONSTRAINT "modeOfFulfillment_ingredientSachetId_fkey"
FOREIGN KEY ("ingredientSachetId") REFERENCES ingredient."ingredientSachet"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY ingredient."modeOfFulfillment" ADD CONSTRAINT "modeOfFulfillment_labelTemplateId_fkey"
FOREIGN KEY ("labelTemplateId") REFERENCES "deviceHub"."labelTemplate"(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY ingredient."modeOfFulfillment" ADD CONSTRAINT "modeOfFulfillment_operationalConfigId_fkey"
FOREIGN KEY ("operationConfigId") REFERENCES settings."operationConfig"(id) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY ingredient."modeOfFulfillment" ADD CONSTRAINT "modeOfFulfillment_packagingId_fkey"
FOREIGN KEY ("packagingId") REFERENCES packaging.packaging(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY ingredient."modeOfFulfillment" ADD CONSTRAINT "modeOfFulfillment_sachetItemId_fkey"
FOREIGN KEY ("sachetItemId") REFERENCES inventory."sachetItem"(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY ingredient."modeOfFulfillment" ADD CONSTRAINT "modeOfFulfillment_stationId_fkey"
FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY ingredient."modeOfFulfillment" ADD CONSTRAINT "modeOfFulfillment_type_fkey"
FOREIGN KEY (type) REFERENCES ingredient."modeOfFulfillmentEnum"(value) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY insights.app_module_insight ADD CONSTRAINT "app_module_insight_insightIdentifier_fkey"
FOREIGN KEY ("insightIdentifier") REFERENCES insights.insights(identifier) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY insights.chart ADD CONSTRAINT "chart_insisghtsTitle_fkey"
FOREIGN KEY ("insightIdentifier") REFERENCES insights.insights(identifier) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY insights.date ADD CONSTRAINT date_day_fkey
FOREIGN KEY (day) REFERENCES insights.day("dayName") ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY instructions."instructionStep" ADD CONSTRAINT "instructionStep_instructionSetId_fkey"
FOREIGN KEY ("instructionSetId") REFERENCES instructions."instructionSet"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY instructions."instructionSet" ADD CONSTRAINT "instruction_simpleRecipeId_fkey"
FOREIGN KEY ("simpleRecipeId") REFERENCES "simpleRecipe"."simpleRecipe"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY inventory."bulkItemHistory" ADD CONSTRAINT "bulkItemHistory_bulkItemId_fkey"
FOREIGN KEY ("bulkItemId") REFERENCES inventory."bulkItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItemHistory" ADD CONSTRAINT "bulkItemHistory_purchaseOrderItemId_fkey"
FOREIGN KEY ("purchaseOrderItemId") REFERENCES inventory."purchaseOrderItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItemHistory" ADD CONSTRAINT "bulkItemHistory_sachetWorkOrderId_fkey"
FOREIGN KEY ("sachetWorkOrderId") REFERENCES inventory."sachetWorkOrder"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItemHistory" ADD CONSTRAINT "bulkItemHistory_unit_fkey"
FOREIGN KEY (unit) REFERENCES master.unit(name) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItemHistory" ADD CONSTRAINT "bulkItemHistory_workOrderId_fkey"
FOREIGN KEY ("bulkWorkOrderId") REFERENCES inventory."bulkWorkOrder"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItem" ADD CONSTRAINT "bulkItem_processingName_fkey"
FOREIGN KEY ("processingName") REFERENCES master."processingName"(name) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItem" ADD CONSTRAINT "bulkItem_supplierItemId_fkey"
FOREIGN KEY ("supplierItemId") REFERENCES inventory."supplierItem"(id) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItem_unitConversion" ADD CONSTRAINT "bulkItem_unitConversion_bulkItemId_fkey"
FOREIGN KEY ("entityId") REFERENCES inventory."bulkItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItem_unitConversion" ADD CONSTRAINT "bulkItem_unitConversion_unitConversionId_fkey"
FOREIGN KEY ("unitConversionId") REFERENCES master."unitConversion"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItem" ADD CONSTRAINT "bulkItem_unit_fkey"
FOREIGN KEY (unit) REFERENCES master.unit(name) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkWorkOrder" ADD CONSTRAINT "bulkWorkOrder_inputBulkItemId_fkey"
FOREIGN KEY ("inputBulkItemId") REFERENCES inventory."bulkItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkWorkOrder" ADD CONSTRAINT "bulkWorkOrder_inputQuantityUnit_fkey"
FOREIGN KEY ("inputQuantityUnit") REFERENCES master.unit(name) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkWorkOrder" ADD CONSTRAINT "bulkWorkOrder_outputBulkItemId_fkey"
FOREIGN KEY ("outputBulkItemId") REFERENCES inventory."bulkItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkWorkOrder" ADD CONSTRAINT "bulkWorkOrder_stationId_fkey"
FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON
UPDATE RESTRICT ON
DELETE
SET NULL;
ALTER TABLE ONLY inventory."bulkWorkOrder" ADD CONSTRAINT "bulkWorkOrder_supplierItemId_fkey"
FOREIGN KEY ("supplierItemId") REFERENCES inventory."supplierItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkWorkOrder" ADD CONSTRAINT "bulkWorkOrder_userId_fkey"
FOREIGN KEY ("userId") REFERENCES settings."user"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."packagingHistory" ADD CONSTRAINT "packagingHistory_packagingId_fkey"
FOREIGN KEY ("packagingId") REFERENCES packaging.packaging(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."packagingHistory" ADD CONSTRAINT "packagingHistory_purchaseOrderItemId_fkey"
FOREIGN KEY ("purchaseOrderItemId") REFERENCES inventory."purchaseOrderItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."purchaseOrderItem" ADD CONSTRAINT "purchaseOrderItem_bulkItemId_fkey"
FOREIGN KEY ("bulkItemId") REFERENCES inventory."bulkItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."purchaseOrderItem" ADD CONSTRAINT "purchaseOrderItem_packagingId_fkey"
FOREIGN KEY ("packagingId") REFERENCES packaging.packaging(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."purchaseOrderItem" ADD CONSTRAINT "purchaseOrderItem_supplierItemId_fkey"
FOREIGN KEY ("supplierItemId") REFERENCES inventory."supplierItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."purchaseOrderItem" ADD CONSTRAINT "purchaseOrderItem_supplier_fkey"
FOREIGN KEY ("supplierId") REFERENCES inventory.supplier(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."purchaseOrderItem" ADD CONSTRAINT "purchaseOrderItem_unit_fkey"
FOREIGN KEY (unit) REFERENCES master.unit(name) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetItem" ADD CONSTRAINT "sachetItem2_bulkItemId_fkey"
FOREIGN KEY ("bulkItemId") REFERENCES inventory."bulkItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetItem" ADD CONSTRAINT "sachetItem2_unit_fkey"
FOREIGN KEY (unit) REFERENCES master.unit(name) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetItemHistory" ADD CONSTRAINT "sachetItemHistory_sachetItemId_fkey"
FOREIGN KEY ("sachetItemId") REFERENCES inventory."sachetItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetItemHistory" ADD CONSTRAINT "sachetItemHistory_sachetWorkOrderId_fkey"
FOREIGN KEY ("sachetWorkOrderId") REFERENCES inventory."sachetWorkOrder"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetItemHistory" ADD CONSTRAINT "sachetItemHistory_unit_fkey"
FOREIGN KEY (unit) REFERENCES master.unit(name) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetWorkOrder" ADD CONSTRAINT "sachetWorkOrder_inputBulkItemId_fkey"
FOREIGN KEY ("inputBulkItemId") REFERENCES inventory."bulkItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetWorkOrder" ADD CONSTRAINT "sachetWorkOrder_outputSachetItemId_fkey"
FOREIGN KEY ("outputSachetItemId") REFERENCES inventory."sachetItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetWorkOrder" ADD CONSTRAINT "sachetWorkOrder_packagingId_fkey"
FOREIGN KEY ("packagingId") REFERENCES packaging.packaging(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetWorkOrder" ADD CONSTRAINT "sachetWorkOrder_stationId_fkey"
FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON
UPDATE RESTRICT ON
DELETE
SET NULL;
ALTER TABLE ONLY inventory."sachetWorkOrder" ADD CONSTRAINT "sachetWorkOrder_supplierItemId_fkey"
FOREIGN KEY ("supplierItemId") REFERENCES inventory."supplierItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetWorkOrder" ADD CONSTRAINT "sachetWorkOrder_userId_fkey"
FOREIGN KEY ("userId") REFERENCES settings."user"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."supplierItem" ADD CONSTRAINT "supplierItem_importId_fkey"
FOREIGN KEY ("importId") REFERENCES imports."importHistory"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY inventory."supplierItem" ADD CONSTRAINT "supplierItem_supplierId_fkey"
FOREIGN KEY ("supplierId") REFERENCES inventory.supplier(id) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."supplierItem_unitConversion" ADD CONSTRAINT "supplierItem_unitConversion_entityId_fkey"
FOREIGN KEY ("entityId") REFERENCES inventory."supplierItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."supplierItem_unitConversion" ADD CONSTRAINT "supplierItem_unitConversion_unitConversionId_fkey"
FOREIGN KEY ("unitConversionId") REFERENCES master."unitConversion"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."supplierItem" ADD CONSTRAINT "supplierItem_unit_fkey"
FOREIGN KEY (unit) REFERENCES master.unit(name) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory.supplier ADD CONSTRAINT "supplier_importId_fkey"
FOREIGN KEY ("importId") REFERENCES imports."importHistory"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY inventory."unitConversionByBulkItem" ADD CONSTRAINT "unitConversionByBulkItem_bulkItemId_fkey"
FOREIGN KEY ("bulkItemId") REFERENCES inventory."bulkItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."unitConversionByBulkItem" ADD CONSTRAINT "unitConversionByBulkItem_unitConversionId_fkey"
FOREIGN KEY ("unitConversionId") REFERENCES master."unitConversion"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY master."productCategory" ADD CONSTRAINT "productCategory_importHistoryId_fkey"
FOREIGN KEY ("importHistoryId") REFERENCES imports."importHistory"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY master."unitConversion" ADD CONSTRAINT "unitConversion_inputUnit_fkey"
FOREIGN KEY ("inputUnitName") REFERENCES master.unit(name) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY master."unitConversion" ADD CONSTRAINT "unitConversion_outputUnit_fkey"
FOREIGN KEY ("outputUnitName") REFERENCES master.unit(name) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY notifications."emailConfig" ADD CONSTRAINT "emailConfig_typeId_fkey"
FOREIGN KEY ("typeId") REFERENCES notifications.type(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY notifications."displayNotification" ADD CONSTRAINT "notification_typeId_fkey"
FOREIGN KEY ("typeId") REFERENCES notifications.type(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY notifications."printConfig" ADD CONSTRAINT "printConfig_printerPrintNodeId_fkey"
FOREIGN KEY ("printerPrintNodeId") REFERENCES "deviceHub".printer("printNodeId") ON
DELETE
SET NULL;
ALTER TABLE ONLY notifications."printConfig" ADD CONSTRAINT "printConfig_typeId_fkey"
FOREIGN KEY ("typeId") REFERENCES notifications.type(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY notifications."smsConfig" ADD CONSTRAINT "smsConfig_typeId_fkey"
FOREIGN KEY ("typeId") REFERENCES notifications.type(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "onDemand".brand_collection ADD CONSTRAINT "brand_collection_collectionId_fkey"
FOREIGN KEY ("collectionId") REFERENCES "onDemand".collection(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY "onDemand".brand_collection ADD CONSTRAINT "brand_collection_importHistoryId_fkey"
FOREIGN KEY ("importHistoryId") REFERENCES imports."importHistory"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY "onDemand".collection ADD CONSTRAINT "collection_importHistoryId_fkey"
FOREIGN KEY ("importHistoryId") REFERENCES imports."importHistory"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY "onDemand"."collection_productCategory" ADD CONSTRAINT "collection_productCategory_collectionId_fkey"
FOREIGN KEY ("collectionId") REFERENCES "onDemand".collection(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY "onDemand"."collection_productCategory" ADD CONSTRAINT "collection_productCategory_importHistoryId_fkey"
FOREIGN KEY ("importHistoryId") REFERENCES imports."importHistory"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY "onDemand"."collection_productCategory" ADD CONSTRAINT "collection_productCategory_productCategoryName_fkey"
FOREIGN KEY ("productCategoryName") REFERENCES master."productCategory"(name) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY "onDemand"."collection_productCategory_product" ADD CONSTRAINT "collection_productCategory_product_collection_productCategor"
FOREIGN KEY ("collection_productCategoryId") REFERENCES "onDemand"."collection_productCategory"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY "onDemand"."collection_productCategory_product" ADD CONSTRAINT "collection_productCategory_product_importHistoryId_fkey"
FOREIGN KEY ("importHistoryId") REFERENCES imports."importHistory"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY "onDemand"."collection_productCategory_product" ADD CONSTRAINT "collection_productCategory_product_productId_fkey"
FOREIGN KEY ("productId") REFERENCES products.product(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY "onDemand"."modifierCategoryOption" ADD CONSTRAINT "modifierCategoryOption_ingredientSachetId_fkey"
FOREIGN KEY ("ingredientSachetId") REFERENCES ingredient."ingredientSachet"(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY "onDemand"."modifierCategoryOption" ADD CONSTRAINT "modifierCategoryOption_modifierCategoryId_fkey"
FOREIGN KEY ("modifierCategoryId") REFERENCES "onDemand"."modifierCategory"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY "onDemand"."modifierCategoryOption" ADD CONSTRAINT "modifierCategoryOption_sachetItemId_fkey"
FOREIGN KEY ("sachetItemId") REFERENCES inventory."sachetItem"(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY "onDemand"."modifierCategoryOption" ADD CONSTRAINT "modifierCategoryOption_supplierItemId_fkey"
FOREIGN KEY ("supplierItemId") REFERENCES inventory."supplierItem"(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY "onDemand"."modifierCategory" ADD CONSTRAINT "modifierCategory_modifierTemplateId_fkey"
FOREIGN KEY ("modifierTemplateId") REFERENCES "onDemand".modifier(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY "onDemand".modifier ADD CONSTRAINT "modifier_importHistoryId_fkey"
FOREIGN KEY ("importHistoryId") REFERENCES imports."importHistory"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY "onDemand".brand_collection ADD CONSTRAINT "shop_collection_shopId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "order"."cartItem" ADD CONSTRAINT "cartItem_cartId_fkey"
FOREIGN KEY ("cartId") REFERENCES "order".cart(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY "order"."cartItem" ADD CONSTRAINT "cartItem_comboProductComponentId_fkey"
FOREIGN KEY ("comboProductComponentId") REFERENCES products."comboProductComponent"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "order"."cartItem" ADD CONSTRAINT "cartItem_customizableProductComponentId_fkey"
FOREIGN KEY ("customizableProductComponentId") REFERENCES products."customizableProductComponent"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "order"."cartItem" ADD CONSTRAINT "cartItem_ingredientSachetId_fkey"
FOREIGN KEY ("ingredientSachetId") REFERENCES ingredient."ingredientSachet"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "order"."cartItem" ADD CONSTRAINT "cartItem_labelTemplateId_fkey"
FOREIGN KEY ("labelTemplateId") REFERENCES "deviceHub"."labelTemplate"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "order"."cartItem" ADD CONSTRAINT "cartItem_parentCartItemId_fkey"
FOREIGN KEY ("parentCartItemId") REFERENCES "order"."cartItem"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY "order"."cartItem" ADD CONSTRAINT "cartItem_productId_fkey"
FOREIGN KEY ("productId") REFERENCES products.product(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "order"."cartItem" ADD CONSTRAINT "cartItem_productOptionId_fkey"
FOREIGN KEY ("productOptionId") REFERENCES products."productOption"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "order"."cartItem" ADD CONSTRAINT "cartItem_sachetItemId_fkey"
FOREIGN KEY ("sachetItemId") REFERENCES inventory."sachetItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "order"."cartItem" ADD CONSTRAINT "cartItem_simpleRecipeYieldId_fkey"
FOREIGN KEY ("simpleRecipeYieldId") REFERENCES "simpleRecipe"."simpleRecipeYield"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "order"."cartItem" ADD CONSTRAINT "cartItem_subscriptionOccurenceProductId_fkey"
FOREIGN KEY ("subscriptionOccurenceProductId") REFERENCES subscription."subscriptionOccurence_product"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "order".cart ADD CONSTRAINT "cart_orderId_fkey"
FOREIGN KEY ("orderId") REFERENCES "order"."order"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY "order"."order" ADD CONSTRAINT "order_cartId_fkey"
FOREIGN KEY ("cartId") REFERENCES "order".cart(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY "order"."order" ADD CONSTRAINT "order_deliveryPartnershipId_fkey"
FOREIGN KEY ("deliveryPartnershipId") REFERENCES fulfilment."deliveryService"("partnershipId") ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "order"."order" ADD CONSTRAINT "order_thirdPartyOrderId_fkey"
FOREIGN KEY ("thirdPartyOrderId") REFERENCES "order"."thirdPartyOrder"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY packaging.packaging ADD CONSTRAINT "packaging_packagingSpecificationsId_fkey"
FOREIGN KEY ("packagingSpecificationsId") REFERENCES packaging."packagingSpecifications"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY packaging.packaging ADD CONSTRAINT "packaging_supplierId_fkey"
FOREIGN KEY ("supplierId") REFERENCES inventory.supplier(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY products."comboProductComponent" ADD CONSTRAINT "comboProductComponent_linkedProductId_fkey"
FOREIGN KEY ("linkedProductId") REFERENCES products.product(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY products."comboProductComponent" ADD CONSTRAINT "comboProductComponent_productId_fkey"
FOREIGN KEY ("productId") REFERENCES products.product(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY products."customizableProductComponent" ADD CONSTRAINT "customizableProductOption_linkedProductId_fkey"
FOREIGN KEY ("linkedProductId") REFERENCES products.product(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY products."customizableProductComponent" ADD CONSTRAINT "customizableProductOption_productId_fkey"
FOREIGN KEY ("productId") REFERENCES products.product(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY products."inventoryProductBundleSachet" ADD CONSTRAINT "inventoryProductBundleSachet_inventoryProductBundleId_fkey"
FOREIGN KEY ("inventoryProductBundleId") REFERENCES products."inventoryProductBundle"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY products."productOptionType" ADD CONSTRAINT "productOptionType_orderMode_fkey"
FOREIGN KEY ("orderMode") REFERENCES "order"."orderMode"(title) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY products."productOption" ADD CONSTRAINT "productOption_modifierId_fkey"
FOREIGN KEY ("modifierId") REFERENCES "onDemand".modifier(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY products."productOption" ADD CONSTRAINT "productOption_operationConfigId_fkey"
FOREIGN KEY ("operationConfigId") REFERENCES settings."operationConfig"(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY products."productOption" ADD CONSTRAINT "productOption_productId_fkey"
FOREIGN KEY ("productId") REFERENCES products.product(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY products."productOption" ADD CONSTRAINT "productOption_sachetItemId_fkey"
FOREIGN KEY ("sachetItemId") REFERENCES inventory."sachetItem"(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY products."productOption" ADD CONSTRAINT "productOption_simpleRecipeYieldId_fkey"
FOREIGN KEY ("simpleRecipeYieldId") REFERENCES "simpleRecipe"."simpleRecipeYield"(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY products."productOption" ADD CONSTRAINT "productOption_supplierItemId_fkey"
FOREIGN KEY ("supplierItemId") REFERENCES inventory."supplierItem"(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY safety."safetyCheckPerUser" ADD CONSTRAINT "safetyCheckByUser_SafetyCheckId_fkey"
FOREIGN KEY ("SafetyCheckId") REFERENCES safety."safetyCheck"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY safety."safetyCheckPerUser" ADD CONSTRAINT "safetyCheckByUser_userId_fkey"
FOREIGN KEY ("userId") REFERENCES settings."user"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings."appPermission" ADD CONSTRAINT "appPermission_appId_fkey"
FOREIGN KEY ("appId") REFERENCES settings.app(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings.app_module ADD CONSTRAINT "app_module_appTitle_fkey"
FOREIGN KEY ("appTitle") REFERENCES settings.app(title) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings."operationConfig" ADD CONSTRAINT "operationConfig_labelTemplateId_fkey"
FOREIGN KEY ("labelTemplateId") REFERENCES "deviceHub"."labelTemplate"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings."operationConfig" ADD CONSTRAINT "operationConfig_packagingId_fkey"
FOREIGN KEY ("packagingId") REFERENCES packaging.packaging(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings."operationConfig" ADD CONSTRAINT "operationConfig_stationId_fkey"
FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings."role_appPermission" ADD CONSTRAINT "role_appPermission_appPermissionId_fkey"
FOREIGN KEY ("appPermissionId") REFERENCES settings."appPermission"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings."role_appPermission" ADD CONSTRAINT "role_appPermission_role_appId_fkey"
FOREIGN KEY ("role_appId") REFERENCES settings.role_app(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings.role_app ADD CONSTRAINT "role_app_appId_fkey"
FOREIGN KEY ("appId") REFERENCES settings.app(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings.role_app ADD CONSTRAINT "role_app_roleId_fkey"
FOREIGN KEY ("roleId") REFERENCES settings.role(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings.station ADD CONSTRAINT "station_defaultKotPrinterId_fkey"
FOREIGN KEY ("defaultKotPrinterId") REFERENCES "deviceHub".printer("printNodeId") ON
UPDATE RESTRICT ON
DELETE
SET NULL;
ALTER TABLE ONLY settings.station ADD CONSTRAINT "station_defaultLabelPrinterId_fkey"
FOREIGN KEY ("defaultLabelPrinterId") REFERENCES "deviceHub".printer("printNodeId") ON
UPDATE RESTRICT ON
DELETE
SET NULL;
ALTER TABLE ONLY settings.station_kot_printer ADD CONSTRAINT "station_kot_printer_printNodeId_fkey"
FOREIGN KEY ("printNodeId") REFERENCES "deviceHub".printer("printNodeId") ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY settings.station_kot_printer ADD CONSTRAINT "station_kot_printer_stationId_fkey"
FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings.station_label_printer ADD CONSTRAINT "station_label_printer_printNodeId_fkey"
FOREIGN KEY ("printNodeId") REFERENCES "deviceHub".printer("printNodeId") ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY settings.station_label_printer ADD CONSTRAINT "station_printer_stationId_fkey"
FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY settings.station_user ADD CONSTRAINT "station_user_stationId_fkey"
FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY settings.station_user ADD CONSTRAINT "station_user_userKeycloakId_fkey"
FOREIGN KEY ("userKeycloakId") REFERENCES settings."user"("keycloakId") ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings.user_role ADD CONSTRAINT "user_role_roleId_fkey"
FOREIGN KEY ("roleId") REFERENCES settings.role(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings.user_role ADD CONSTRAINT "user_role_userId_fkey"
FOREIGN KEY ("userId") REFERENCES settings."user"("keycloakId") ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipeYield_ingredientSachet" ADD CONSTRAINT "simpleRecipeYield_ingredientSachet_ingredientSachetId_fkey"
FOREIGN KEY ("ingredientSachetId") REFERENCES ingredient."ingredientSachet"(id) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipeYield_ingredientSachet" ADD CONSTRAINT "simpleRecipeYield_ingredientSachet_recipeYieldId_fkey"
FOREIGN KEY ("recipeYieldId") REFERENCES "simpleRecipe"."simpleRecipeYield"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipeYield_ingredientSachet" ADD CONSTRAINT "simpleRecipeYield_ingredientSachet_simpleRecipeIngredientPro"
FOREIGN KEY ("simpleRecipeIngredientProcessingId") REFERENCES "simpleRecipe"."simpleRecipe_ingredient_processing"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipeYield" ADD CONSTRAINT "simpleRecipeYield_simpleRecipeId_fkey"
FOREIGN KEY ("simpleRecipeId") REFERENCES "simpleRecipe"."simpleRecipe"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipe" ADD CONSTRAINT "simpleRecipe_cuisine_fkey"
FOREIGN KEY (cuisine) REFERENCES master."cuisineName"(name) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipe_ingredient_processing" ADD CONSTRAINT "simpleRecipe_ingredient_processing_ingredientId_fkey"
FOREIGN KEY ("ingredientId") REFERENCES ingredient.ingredient(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipe_ingredient_processing" ADD CONSTRAINT "simpleRecipe_ingredient_processing_processingId_fkey"
FOREIGN KEY ("processingId") REFERENCES ingredient."ingredientProcessing"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipe_ingredient_processing" ADD CONSTRAINT "simpleRecipe_ingredient_processing_simpleRecipeId_fkey"
FOREIGN KEY ("simpleRecipeId") REFERENCES "simpleRecipe"."simpleRecipe"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY subscription."brand_subscriptionTitle" ADD CONSTRAINT "brand_subscriptionTitle_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY subscription."subscriptionItemCount" ADD CONSTRAINT "subscriptionItemCount_subscriptionServingId_fkey"
FOREIGN KEY ("subscriptionServingId") REFERENCES subscription."subscriptionServing"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY subscription."subscriptionOccurence_addOn" ADD CONSTRAINT "subscriptionOccurence_addOn_productOptionId_fkey"
FOREIGN KEY ("productOptionId") REFERENCES products."productOption"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY subscription."subscriptionOccurence_customer" ADD CONSTRAINT "subscriptionOccurence_customer_brand_customerId_fkey"
FOREIGN KEY ("brand_customerId") REFERENCES crm.brand_customer(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY subscription."subscriptionOccurence_customer" ADD CONSTRAINT "subscriptionOccurence_customer_keycloakId_fkey"
FOREIGN KEY ("keycloakId") REFERENCES crm.customer("keycloakId") ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY subscription."subscriptionOccurence_customer" ADD CONSTRAINT "subscriptionOccurence_customer_orderCartId_fkey"
FOREIGN KEY ("cartId") REFERENCES "order".cart(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY subscription."subscriptionOccurence_customer" ADD CONSTRAINT "subscriptionOccurence_customer_subscriptionOccurenceId_fkey"
FOREIGN KEY ("subscriptionOccurenceId") REFERENCES subscription."subscriptionOccurence"(id) ON
UPDATE
SET NULL ON
DELETE
SET NULL;
ALTER TABLE ONLY subscription."subscriptionOccurence_product" ADD CONSTRAINT "subscriptionOccurence_product_productCategory_fkey"
FOREIGN KEY ("productCategory") REFERENCES master."productCategory"(name) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY subscription."subscriptionOccurence_product" ADD CONSTRAINT "subscriptionOccurence_product_productOptionId_fkey"
FOREIGN KEY ("productOptionId") REFERENCES products."productOption"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY subscription."subscriptionOccurence_product" ADD CONSTRAINT "subscriptionOccurence_product_subscriptionId_fkey"
FOREIGN KEY ("subscriptionId") REFERENCES subscription.subscription(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY subscription."subscriptionOccurence_product" ADD CONSTRAINT "subscriptionOccurence_product_subscriptionOccurenceId_fkey"
FOREIGN KEY ("subscriptionOccurenceId") REFERENCES subscription."subscriptionOccurence"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY subscription."subscriptionOccurence" ADD CONSTRAINT "subscriptionOccurence_subscriptionId_fkey"
FOREIGN KEY ("subscriptionId") REFERENCES subscription.subscription(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY subscription."subscriptionServing" ADD CONSTRAINT "subscriptionServing_defaultSubscriptionItemCountId_fkey"
FOREIGN KEY ("defaultSubscriptionItemCountId") REFERENCES subscription."subscriptionItemCount"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY subscription."subscriptionServing" ADD CONSTRAINT "subscriptionServing_subscriptionTitleId_fkey"
FOREIGN KEY ("subscriptionTitleId") REFERENCES subscription."subscriptionTitle"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY subscription."subscriptionTitle" ADD CONSTRAINT "subscriptionTitle_defaultSubscriptionServingId_fkey"
FOREIGN KEY ("defaultSubscriptionServingId") REFERENCES subscription."subscriptionServing"(id) ON
UPDATE
SET NULL ON
DELETE
SET NULL;
ALTER TABLE ONLY subscription.subscription ADD CONSTRAINT "subscription_subscriptionItemCountId_fkey"
FOREIGN KEY ("subscriptionItemCountId") REFERENCES subscription."subscriptionItemCount"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY subscription.subscription_zipcode ADD CONSTRAINT "subscription_zipcode_subscriptionId_fkey"
FOREIGN KEY ("subscriptionId") REFERENCES subscription.subscription(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY subscription.subscription_zipcode ADD CONSTRAINT "subscription_zipcode_subscriptionPickupOptionId_fkey"
FOREIGN KEY ("subscriptionPickupOptionId") REFERENCES subscription."subscriptionPickupOption"(id) ON
UPDATE RESTRICT ON
DELETE
SET NULL;
ALTER TABLE ONLY website."websitePageModule" ADD CONSTRAINT "websitePageModule_fileId_fkey"
FOREIGN KEY ("fileId") REFERENCES editor.file(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY website."websitePageModule" ADD CONSTRAINT "websitePageModule_templateId_fkey"
FOREIGN KEY ("templateId") REFERENCES editor.template(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY website."websitePageModule" ADD CONSTRAINT "websitePageModule_websitePageId_fkey"
FOREIGN KEY ("websitePageId") REFERENCES website."websitePage"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY website."websitePage" ADD CONSTRAINT "websitePage_websiteId_fkey"
FOREIGN KEY ("websiteId") REFERENCES website.website(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY website.website ADD CONSTRAINT "website_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;

CREATE OR REPLACE FUNCTION products."isProductValid"(product products.product)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    component record;
    isValid boolean := true;
    message text := '';
    counter int := 0;
BEGIN   
    RETURN jsonb_build_object('status', isValid, 'error', message);
END
$function$;

CREATE OR REPLACE FUNCTION products."productCartItemById"(optionid integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    counter int;
    items jsonb[] := '{}';
    option products."productOption";
    product products."product";
BEGIN
    SELECT * INTO option FROM products."productOption" WHERE id = optionId;
    SELECT * FROM products.product WHERE id = option."productId" INTO product;
    
    counter := option.quantity;
    
    IF option."simpleRecipeYieldId" IS NOT NULL THEN 
        WHILE counter >= 1 LOOP
            items := items || json_build_object('simpleRecipeYieldId', option."simpleRecipeYieldId")::jsonb;
            counter := counter - 1;
        END LOOP;
    ELSEIF option."inventoryProductBundleId" IS NOT NULL THEN
        WHILE counter >= 1 LOOP
            items := items || json_build_object('inventoryProductBundleId', option."inventoryProductBundleId")::jsonb;
            counter := counter - 1;
        END LOOP;
    END IF;
    
    RETURN json_build_object(
        'productId', product.id,
        'childs', jsonb_build_object(
            'data', json_build_array(
                json_build_object (
                    'productOptionId', option.id,
                    'unitPrice', 0,
                    'childs', json_build_object(
                        'data', items
                    )
                )
            )
        )
    );
END
$function$;
