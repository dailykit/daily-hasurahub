alter table "products"."inventoryProductOption"
           add constraint "inventoryProductOption_operationConfigId_fkey"
           foreign key ("operationConfigId")
           references "settings"."operationConfig"
           ("id") on update restrict on delete restrict;
