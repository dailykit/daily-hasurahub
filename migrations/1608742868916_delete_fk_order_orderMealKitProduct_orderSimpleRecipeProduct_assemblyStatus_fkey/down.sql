alter table "order"."orderMealKitProduct" add foreign key ("assemblyStatus") references "order"."assemblyEnum"("value") on update restrict on delete restrict;
