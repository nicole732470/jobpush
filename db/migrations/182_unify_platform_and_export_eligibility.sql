BEGIN;

CREATE OR REPLACE FUNCTION jobpush.is_explicit_no_sponsorship(description TEXT)
RETURNS BOOLEAN LANGUAGE sql IMMUTABLE AS $$
  SELECT COALESCE(description, '') ~* '((unable|cannot|can not|will not|do not|does not|not able to|no longer).{0,80}(sponsor|sponsorship)|(no|without).{0,50}(visa|employment|work authorization).{0,50}sponsorship|(visa|employment|work authorization).{0,50}sponsorship.{0,40}(not available|unavailable|not provided)|must.{0,80}(authorized|eligible).{0,100}without.{0,50}sponsorship|not.{0,30}eligible.{0,50}(visa )?sponsorship|sponsorship.{0,40}(is )?not (available|offered|provided))'
$$;

COMMIT;
