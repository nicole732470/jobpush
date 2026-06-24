BEGIN;

CREATE OR REPLACE FUNCTION jobpush.apply_profile_title_boundary()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.classification_status = 'review'
       AND COALESCE(NEW.rule_version, '') NOT LIKE 'manual%'
       AND NEW.normalized_title ~
          '(^|[^a-z])(lead|staff|principal|director|executive director|vice president|vp|head|chief|distinguished|fellow)([^a-z]|$)'
    THEN
        NEW.classification_status := 'non_target';
        NEW.canonical_role := NULL;
        NEW.rule_version := 'profile-boundary-v1';
        NEW.decision_reason := 'profile_hard_seniority_exclusion: candidate_profile 2026-06-23';
        NEW.labeled_by := 'system:profile-boundary-v1';
        NEW.labeled_at := now();
        NEW.updated_at := now();
    ELSIF NEW.classification_status = 'review'
       AND COALESCE(NEW.rule_version, '') NOT LIKE 'manual%'
       AND NEW.normalized_title ~
          '(^|[^a-z])(machine learning|ml|mechanical|electrical|cad|eda|embedded|firmware|rf|antenna|phy|analog|mixed[- ]signal|circuit|asic|rtl|physical design|silicon|semiconductor|hardware architecture)([^a-z]|$)'
    THEN
        NEW.classification_status := 'non_target';
        NEW.canonical_role := NULL;
        NEW.rule_version := 'profile-boundary-v1';
        NEW.decision_reason := 'profile_hard_technical_exclusion: candidate_profile 2026-06-23';
        NEW.labeled_by := 'system:profile-boundary-v1';
        NEW.labeled_at := now();
        NEW.updated_at := now();
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_apply_profile_title_boundary
    ON jobpush.job_title_labels;
CREATE TRIGGER trg_apply_profile_title_boundary
BEFORE INSERT OR UPDATE OF normalized_title, classification_status, rule_version
ON jobpush.job_title_labels
FOR EACH ROW EXECUTE FUNCTION jobpush.apply_profile_title_boundary();

-- Publish only the explicit hard boundaries from Nicole's private candidate
-- profile. Exact human decisions, including an intentional manual `review`,
-- always win and are never overwritten here.
WITH proposed AS (
    SELECT
        label.normalized_title,
        label.classification_status AS previous_status,
        CASE
            WHEN label.normalized_title ~
                '(^|[^a-z])(lead|staff|principal|director|executive director|vice president|vp|head|chief|distinguished|fellow)([^a-z]|$)'
                THEN 'profile_hard_seniority_exclusion'
            WHEN label.normalized_title ~
                '(^|[^a-z])(machine learning|ml|mechanical|electrical|cad|eda|embedded|firmware|rf|antenna|phy|analog|mixed[- ]signal|circuit|asic|rtl|physical design|silicon|semiconductor|hardware architecture)([^a-z]|$)'
                THEN 'profile_hard_technical_exclusion'
        END AS reason
    FROM jobpush.job_title_labels label
    WHERE label.classification_status = 'review'
      AND COALESCE(label.rule_version, '') NOT LIKE 'manual%'
), changed AS (
    SELECT * FROM proposed WHERE reason IS NOT NULL
)
INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT normalized_title, previous_status, 'non_target', NULL,
       reason || ': candidate_profile 2026-06-23',
       'system:profile-boundary-v1'
FROM changed;

UPDATE jobpush.job_title_labels label
SET classification_status = 'non_target',
    canonical_role = NULL,
    rule_version = 'profile-boundary-v1',
    decision_reason = CASE
        WHEN label.normalized_title ~
            '(^|[^a-z])(lead|staff|principal|director|executive director|vice president|vp|head|chief|distinguished|fellow)([^a-z]|$)'
            THEN 'profile_hard_seniority_exclusion: candidate_profile 2026-06-23'
        ELSE 'profile_hard_technical_exclusion: candidate_profile 2026-06-23'
    END,
    labeled_by = 'system:profile-boundary-v1',
    labeled_at = now(),
    updated_at = now()
WHERE label.classification_status = 'review'
  AND COALESCE(label.rule_version, '') NOT LIKE 'manual%'
  AND (
      label.normalized_title ~
        '(^|[^a-z])(lead|staff|principal|director|executive director|vice president|vp|head|chief|distinguished|fellow)([^a-z]|$)'
      OR label.normalized_title ~
        '(^|[^a-z])(machine learning|ml|mechanical|electrical|cad|eda|embedded|firmware|rf|antenna|phy|analog|mixed[- ]signal|circuit|asic|rtl|physical design|silicon|semiconductor|hardware architecture)([^a-z]|$)'
  );

COMMIT;
