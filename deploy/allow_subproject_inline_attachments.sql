-- Allow inline images on sub-project descriptions and comments.
-- Keeps the existing task, sub-task, project, and forum types.
-- Safe to run more than once.

alter table public.inline_attachment
  drop constraint if exists inline_attachment_entity_type_check;

alter table public.inline_attachment
  add constraint inline_attachment_entity_type_check
  check (
    entity_type in (
      'task_description',
      'task_comment',
      'subtask_description',
      'subtask_comment',
      'project_description',
      'project_comment',
      'subproject_description',
      'subproject_comment',
      'forum_post_content'
    )
  );

notify pgrst, 'reload schema';
