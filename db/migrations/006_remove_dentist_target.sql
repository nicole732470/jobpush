BEGIN;

DELETE FROM jobpush.target_soc_roles
WHERE normalized_soc_code = '29102100';

COMMIT;
