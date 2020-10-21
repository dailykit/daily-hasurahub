alter table "products"."simpleRecipeProductOption"
           add constraint "simpleRecipeProductOption_operationConfigId_fkey"
           foreign key ("operationConfigId")
           references "settings"."operationConfig"
           ("id") on update restrict on delete restrict;
