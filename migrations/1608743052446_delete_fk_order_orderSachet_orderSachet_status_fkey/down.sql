alter table "order"."orderSachet" add foreign key ("status") references "order"."orderSachetStatusEnum"("value") on update restrict on delete restrict;
