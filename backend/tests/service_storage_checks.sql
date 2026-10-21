-- Operator-only, read-only capacity/integrity snapshot. No content, identities,
-- paths or credentials. This does not set plan limits, expiry or delete objects.
select jsonb_build_object(
 'database_bytes',pg_database_size(current_database()),
 'original_records',(select count(*) from public.original_assets),
 'pending_originals',(select count(*) from public.original_assets where state='pending'),
 'original_bytes',(select coalesce(sum(byte_size),0) from public.original_assets),
 'stored_objects',(select count(*) from storage.objects where bucket_id='character-originals'),
 'stored_bytes',(select coalesce(sum(case when metadata->>'size' ~ '^[0-9]+$'
   then (metadata->>'size')::numeric else 0 end),0) from storage.objects where bucket_id='character-originals'),
 'ready_without_file',(select count(*) from public.original_assets a where a.state='ready' and not exists(
   select 1 from storage.objects o where o.bucket_id='character-originals' and o.name=a.object_path)),
 'files_without_record',(select count(*) from storage.objects o where o.bucket_id='character-originals' and not exists(
   select 1 from public.original_assets a where a.object_path=o.name)),
 'generation_enabled',(select enabled from imagineos_private.illustration_control where singleton),
 'unsettled_jobs',(select count(*) from imagineos_private.illustration_jobs where state in ('reserved','running','indeterminate'))
) as operational_snapshot;
