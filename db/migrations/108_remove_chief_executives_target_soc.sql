BEGIN;

UPDATE jobpush.target_soc_roles
SET active = FALSE,
    updated_at = now()
WHERE normalized_soc_code = '11101100'
   OR lower(representative_title) = 'chief executives';

COMMIT;

SELECT normalized_soc_code, representative_title, active, source, updated_at
FROM jobpush.target_soc_roles
WHERE normalized_soc_code = '11101100'
   OR lower(representative_title) = 'chief executives';
