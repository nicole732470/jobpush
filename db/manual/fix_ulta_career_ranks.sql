UPDATE jobpush.career_sites site
SET candidate_rank = ranked.new_rank, updated_at = now()
FROM (
    SELECT site_id,
           ROW_NUMBER() OVER (
               ORDER BY CASE verification_status WHEN 'verified' THEN 0 ELSE 1 END,
                        candidate_score DESC NULLS LAST, site_id
           ) AS new_rank
    FROM jobpush.career_sites
    WHERE consolidation_key = 'ulta'
) ranked
WHERE site.site_id = ranked.site_id;
