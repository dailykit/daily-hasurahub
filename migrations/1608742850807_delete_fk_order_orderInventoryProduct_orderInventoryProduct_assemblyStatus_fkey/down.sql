alter table "order"."orderInventoryProduct" add foreign key ("assemblyStatus") references "order"."assemblyEnum"("value") on update restrict on delete restrict;
