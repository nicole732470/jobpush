BEGIN;

CREATE OR REPLACE FUNCTION jobpush.is_product_role_title(title TEXT)
RETURNS BOOLEAN
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT COALESCE(title, '') ~*
        '(product manager|product owner|technical product manager|product engineer|'
        || 'solution(s)? engineer|systems? engineer|product management|product lead|'
        || 'head of product|product director|principal product manager|'
        || 'associate product manager|senior product manager|group product manager|'
        || 'vp[, ]+product|vice president[, ]+product|product program manager|'
        || 'technical program manager|\btpm\b)'
       AND COALESCE(title, '') !~*
        '(production supervisor|production manager|manufacturing production|'
        || 'food production|video production|media production)';
$$;

COMMIT;
