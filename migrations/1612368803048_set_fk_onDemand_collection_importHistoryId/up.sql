alter table "onDemand"."collection"
           add constraint "collection_importHistoryId_fkey"
           foreign key ("importHistoryId")
           references "imports"."importHistory"
           ("id") on update restrict on delete cascade;
