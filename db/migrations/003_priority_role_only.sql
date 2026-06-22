BEGIN;

UPDATE jobpush.company_targets
SET priority_score = CASE WHEN target_role_match THEN 1 ELSE 0 END,
    priority_version = 'role-only-v1',
    updated_at = now();

COMMIT;
