alter table "onDemand"."collection_productCategory"
           add constraint "collection_productCategory_importHistoryId_fkey"
           foreign key ("importHistoryId")
           references "imports"."importHistory"
           ("id") on update restrict on delete cascade;
