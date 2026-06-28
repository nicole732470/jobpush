\pset pager off

DELETE FROM jobpush.career_sites
WHERE discovery_source = 'ats_url_guess'
  AND verification_status = 'unverified'
  AND source_key IN (
      'international', 'national', 'global', 'services', 'systems',
      'technology', 'technologies', 'solutions', 'consulting', 'corporate',
      'company', 'group', 'capital', 'health', 'medical', 'blue', 'green',
      'new', 'advanced', 'staging', 'test', 'demo', 'jobs', 'careers',
      'career', 'healthcare', 'careeronestop', 'obsglobal', 'trivago',
      'rover', 'str', 'glassdoor'
  )
RETURNING consolidation_key, source_type, source_key, site_url;

\echo '=== Remove unverified zero-job ATS guesses ==='

DELETE FROM jobpush.career_sites
WHERE discovery_source = 'ats_url_guess'
  AND verification_status = 'unverified'
  AND evidence_title ~ '\(0 jobs\)'
RETURNING consolidation_key, source_type, source_key, evidence_title, site_url;
