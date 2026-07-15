BEGIN;

CREATE OR REPLACE FUNCTION jobpush.is_explicit_no_sponsorship(description TEXT)
RETURNS BOOLEAN LANGUAGE sql IMMUTABLE AS $$
  SELECT lower(COALESCE(description, '')) LIKE ANY (ARRAY[
    '%unable to sponsor%', '%unable to provide sponsorship%',
    '%cannot sponsor%', '%can not sponsor%', '%will not sponsor%',
    '%do not sponsor%', '%does not sponsor%', '%not able to sponsor%',
    '%no longer sponsor%', '%no sponsorship%', '%without sponsorship%',
    '%without visa sponsorship%', '%without employment sponsorship%',
    '%without work authorization sponsorship%',
    '%sponsorship is not available%', '%sponsorship not available%',
    '%sponsorship is not offered%', '%sponsorship not offered%',
    '%sponsorship is not provided%', '%sponsorship not provided%',
    '%visa sponsorship is unavailable%', '%visa sponsorship unavailable%'
  ])
$$;

COMMIT;
