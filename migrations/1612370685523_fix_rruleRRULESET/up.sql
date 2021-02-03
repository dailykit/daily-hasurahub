CREATE CAST (jsonb AS _rrule.RRULESET)
  WITH FUNCTION _rrule.jsonb_to_rruleset(jsonb)
  AS IMPLICIT;
