alter table public.child_profiles add constraint child_profiles_id_family_key unique (id,family_id);
alter table public.characters drop constraint characters_child_profile_id_fkey;
alter table public.characters add constraint characters_child_family_fkey
  foreign key (child_profile_id,family_id) references public.child_profiles(id,family_id);
create index characters_child_family_idx on public.characters(child_profile_id,family_id);
drop index public.characters_child_idx;
create index character_versions_character_family_idx on public.character_versions(character_id,family_id);
create index original_assets_version_family_idx on public.original_assets(version_id,family_id);
