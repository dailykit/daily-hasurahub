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
