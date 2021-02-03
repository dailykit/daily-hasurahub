alter table "onDemand"."brand_collection"
           add constraint "brand_collection_importHistoryId_fkey"
           foreign key ("importHistoryId")
           references "imports"."importHistory"
           ("id") on update restrict on delete cascade;
