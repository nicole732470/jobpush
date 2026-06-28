\pset pager off

\echo '=== Suspect titles currently in review queue ==='
WITH suspect AS (
  SELECT q.normalized_title, q.example_title, q.active_posting_count, q.company_count,
         q.suggestion_reason,
         d.classification_status AS rule_status,
         d.decision_reason AS rule_reason
  FROM jobpush.job_title_review_queue q
  CROSS JOIN LATERAL jobpush.profile_title_rule_decision(q.normalized_title) d
  WHERE q.normalized_title ~ '(merchant|cleaner|leader|lead|一|丁|七|万|三|上|下|不|中|人|会|体|作|保|入|全|公|出|分|利|前|務|動|化|北|区|医|南|同|名|員|品|営|国|在|地|場|士|外|大|学|定|実|家|小|市|年|店|後|心|情|手|担|支|教|新|方|日|明|時|月|本|業|様|機|正|法|活|海|理|生|用|発|的|社|管|系|経|者|職|自|行|製|見|計|語|販|資|車|近|部|都|開|電|面|食品|高级|经理|工程|销售|运营|数据|软件|产品|研发|中国|日本|日本語|中文|香港|台湾|东京|大阪|北京|上海|深圳|广州|杭州|南京|成都|武汉|苏州|서울|한국|[ぁ-ゟァ-ヿ가-힣])'
)
SELECT rule_status, rule_reason, count(*) AS titles, sum(active_posting_count) AS active_postings
FROM suspect
GROUP BY 1,2
ORDER BY active_postings DESC NULLS LAST, titles DESC;

\echo '=== Suspect examples ==='
SELECT q.normalized_title, q.example_title, q.active_posting_count, q.company_count,
       d.classification_status AS rule_status, d.decision_reason AS rule_reason
FROM jobpush.job_title_review_queue q
CROSS JOIN LATERAL jobpush.profile_title_rule_decision(q.normalized_title) d
WHERE q.normalized_title ~ '(merchant|cleaner|leader|lead|一|丁|七|万|三|上|下|不|中|人|会|体|作|保|入|全|公|出|分|利|前|務|動|化|北|区|医|南|同|名|員|品|営|国|在|地|場|士|外|大|学|定|実|家|小|市|年|店|後|心|情|手|担|支|教|新|方|日|明|時|月|本|業|様|機|正|法|活|海|理|生|用|発|的|社|管|系|経|者|職|自|行|製|見|計|語|販|資|車|近|部|都|開|電|面|食品|高级|经理|工程|销售|运营|数据|软件|产品|研发|中国|日本|日本語|中文|香港|台湾|东京|大阪|北京|上海|深圳|广州|杭州|南京|成都|武汉|苏州|서울|한국|[ぁ-ゟァ-ヿ가-힣])'
ORDER BY q.active_posting_count DESC, q.company_count DESC, q.normalized_title
LIMIT 80;

\echo '=== Labels where current rule would decide non_target but label still review ==='
SELECT d.decision_reason, count(*) AS titles
FROM jobpush.job_title_labels label
CROSS JOIN LATERAL jobpush.profile_title_rule_decision(label.normalized_title) d
WHERE label.classification_status = 'review'
  AND COALESCE(label.rule_version, '') NOT LIKE 'manual%'
  AND d.classification_status = 'non_target'
GROUP BY 1
ORDER BY titles DESC;
