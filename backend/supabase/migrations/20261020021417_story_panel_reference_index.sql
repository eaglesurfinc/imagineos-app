-- Cover both columns of the family-consistent story reference for FK cleanup.
create index story_panels_story_family_idx on public.story_panels(story_id,family_id);
