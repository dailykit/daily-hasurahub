alter table "ingredient"."modeOfFulfillment"
           add constraint "modeOfFulfillment_operationConfigId_fkey"
           foreign key ("operationConfigId")
           references "settings"."operationConfig"
           ("id") on update restrict on delete restrict;
