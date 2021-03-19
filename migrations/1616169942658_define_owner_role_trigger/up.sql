CREATE OR REPLACE FUNCTION "settings".define_owner_role()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE

role_Id int;

BEGIN
    IF NEW."isOwner" = true AND NEW."keycloakId" is not null THEN
    
    select "id" into role_Id from "settings"."role" where "title" = 'admin';
    
    insert into "settings"."user_role" ("userId", "roleId") values (
    
    NEW."keycloakId", role_Id
    
    );
    END IF;
    RETURN NULL;
END;
$function$;

create trigger "defineOwnerRole"

after update of

"keycloakId" on

"settings"."user" for each row execute procedure "settings"."define_owner_role"();
