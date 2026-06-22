BEGIN;

ALTER TABLE jobpush.company_targets
    RENAME COLUMN priority_score TO role_match_score;

ALTER TABLE jobpush.company_targets
    DROP CONSTRAINT IF EXISTS company_targets_priority_score_check;

ALTER TABLE jobpush.company_targets
    ADD CONSTRAINT company_targets_role_match_score_check
    CHECK (role_match_score >= 0);

ALTER TABLE jobpush.company_targets
    ADD COLUMN priority_score INTEGER NOT NULL DEFAULT 0;

UPDATE jobpush.company_targets
SET priority_score = role_match_score;

ALTER TABLE jobpush.company_targets
    ADD CONSTRAINT company_targets_priority_score_check
    CHECK (priority_score >= 0);

DROP INDEX IF EXISTS jobpush.idx_jobpush_targets_priority;
CREATE INDEX idx_jobpush_targets_priority
    ON jobpush.company_targets(priority_score DESC, last_decision_date DESC NULLS LAST);

DROP INDEX IF EXISTS jobpush.idx_jobpush_targets_status;
CREATE INDEX idx_jobpush_targets_status
    ON jobpush.company_targets(crawl_status, priority_score DESC);

COMMIT;
