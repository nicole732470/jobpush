BEGIN;

-- Nicole profile update, 2026-06-28:
-- Add broad hard-avoid families discovered during title review:
-- producer/media, teacher/education, warehouse/logistics, aerospace/aviation,
-- and actor/dancer/performance roles.

INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    (
        'profile-title-rules-v2',
        '2026-06-28-draft-6',
        'non_target',
        NULL,
        'producer media content',
        '(^|[^a-z])(producer|content producer|video producer|creative producer|media producer|news producer|broadcast producer|podcast producer)([^a-z]|$)',
        'nicole_review_2026-06-28',
        'profile_avoid_producer_media_roles',
        24,
        TRUE
    ),
    (
        'profile-title-rules-v2',
        '2026-06-28-draft-6',
        'non_target',
        NULL,
        'teacher education classroom',
        '(^|[^a-z])(teacher|teaching assistant|classroom|educator|education coordinator|instructional aide|tutor|school counselor|curriculum specialist|professor|lecturer)([^a-z]|$)',
        'nicole_review_2026-06-28',
        'profile_avoid_teacher_education_roles',
        24,
        TRUE
    ),
    (
        'profile-title-rules-v2',
        '2026-06-28-draft-6',
        'non_target',
        NULL,
        'warehouse logistics fulfillment',
        '(^|[^a-z])(warehouse|fulfillment|material handler|order selector|picker|packer|forklift|inventory associate|shipping associate|receiving associate|dock worker|loader|sortation|distribution center)([^a-z]|$)',
        'nicole_review_2026-06-28',
        'profile_avoid_warehouse_logistics_roles',
        24,
        TRUE
    ),
    (
        'profile-title-rules-v2',
        '2026-06-28-draft-6',
        'non_target',
        NULL,
        'aerospace aviation aircraft',
        '(^|[^a-z])(aerospace|aeronautical|aviation|aircraft|airframe|flight engineer|flight test|avionics|propulsion|spacecraft|satellite systems|mission systems)([^a-z]|$)',
        'nicole_review_2026-06-28',
        'profile_avoid_aerospace_aviation_roles',
        24,
        TRUE
    ),
    (
        'profile-title-rules-v2',
        '2026-06-28-draft-6',
        'non_target',
        NULL,
        'actor dancer performance',
        '(^|[^a-z])(actor|actress|dancer|performer|performing artist|choreographer|dance instructor|brand ambassador|promotional model|model actor)([^a-z]|$)',
        'nicole_review_2026-06-28',
        'profile_avoid_performance_roles',
        24,
        TRUE
    )
ON CONFLICT (rule_version, rule_type, lower(term), regex_pattern) DO UPDATE SET
    profile_version = EXCLUDED.profile_version,
    canonical_role = EXCLUDED.canonical_role,
    source = EXCLUDED.source,
    decision_reason = EXCLUDED.decision_reason,
    priority = EXCLUDED.priority,
    active = TRUE;

WITH proposed AS (
    SELECT label.normalized_title,
           label.classification_status AS previous_status,
           decision.classification_status AS new_status,
           decision.canonical_role,
           decision.decision_reason
    FROM jobpush.job_title_labels label
    CROSS JOIN LATERAL jobpush.profile_title_rule_decision(label.normalized_title) decision
    WHERE COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
      AND decision.classification_status = 'non_target'
      AND decision.decision_reason IN (
          'profile_avoid_producer_media_roles',
          'profile_avoid_teacher_education_roles',
          'profile_avoid_warehouse_logistics_roles',
          'profile_avoid_aerospace_aviation_roles',
          'profile_avoid_performance_roles'
      )
      AND (label.classification_status IS DISTINCT FROM 'non_target'
           OR label.rule_version IS DISTINCT FROM 'profile-title-rules-v2'
           OR label.canonical_role IS NOT NULL
           OR label.decision_reason IS DISTINCT FROM decision.decision_reason || ': candidate_profile 2026-06-28')
)
INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT normalized_title, previous_status, new_status, canonical_role,
       decision_reason || ': candidate_profile 2026-06-28',
       'system:profile-title-rules-v2'
FROM proposed;

WITH proposed AS (
    SELECT label.normalized_title,
           decision.classification_status AS new_status,
           decision.canonical_role,
           decision.decision_reason
    FROM jobpush.job_title_labels label
    CROSS JOIN LATERAL jobpush.profile_title_rule_decision(label.normalized_title) decision
    WHERE COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
      AND decision.classification_status = 'non_target'
      AND decision.decision_reason IN (
          'profile_avoid_producer_media_roles',
          'profile_avoid_teacher_education_roles',
          'profile_avoid_warehouse_logistics_roles',
          'profile_avoid_aerospace_aviation_roles',
          'profile_avoid_performance_roles'
      )
)
UPDATE jobpush.job_title_labels label
SET classification_status = proposed.new_status,
    canonical_role = proposed.canonical_role,
    rule_version = 'profile-title-rules-v2',
    decision_reason = proposed.decision_reason || ': candidate_profile 2026-06-28',
    labeled_by = 'system:profile-title-rules-v2',
    labeled_at = now(),
    updated_at = now()
FROM proposed
WHERE label.normalized_title = proposed.normalized_title
  AND COALESCE(label.rule_version, '') NOT LIKE 'manual%%';

UPDATE jobpush.job_title_ml_classifications ml
SET applied = FALSE
WHERE lower(ml.normalized_title) ~ '(^|[^a-z])(producer|teacher|teaching assistant|educator|warehouse|fulfillment|material handler|order selector|picker|packer|forklift|aerospace|aeronautical|aviation|aircraft|airframe|flight engineer|avionics|actor|actress|dancer|performer|choreographer)([^a-z]|$)';

COMMIT;
