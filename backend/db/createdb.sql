SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = off;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET escape_string_warning = off;


CREATE PROCEDURAL LANGUAGE plpgsql;

SET search_path = public, pg_catalog;

CREATE TYPE counters_detail AS (
	timet timestamp with time zone,
	value numeric
);

CREATE FUNCTION cleanup_partition(p_partid bigint, p_max_timestamp timestamptz) RETURNS boolean
    LANGUAGE plpgsql
    AS $_$
DECLARE
  v_cursor refcursor;
  v_record record;
  v_current_value numeric;
  v_start_range timestamptz;
  v_previous_timet timestamptz;
  v_counter integer;
  v_previous_cleanup timestamptz;
BEGIN
  -- We retrieve the previous clean date
  SELECT last_cleanup INTO v_previous_cleanup FROM services WHERE id=p_partid;
  -- Should not happen, the partition should exist.
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  -- We go across the whole table, and remove redundant values (counters where previous value equals current value)
  -- We only keep the first and last value of a range
  -- We only clean until p_max_timestamp
  OPEN v_cursor FOR EXECUTE 'SELECT timet,value FROM counters_detail_' || p_partid || ' WHERE timet >= ' || quote_literal(v_previous_cleanup) || ' AND timet <= ' || quote_literal(p_max_timestamp) || ' ORDER BY timet';
  LOOP
    FETCH v_cursor INTO v_record;
    EXIT WHEN NOT FOUND; -- We have fetched everything
    v_counter:=v_counter+1;

    IF v_current_value IS NULL THEN
      -- This is the firs iteration
      v_current_value:=v_record.value;
      v_start_range:=v_record.timet;
      v_counter:=1;
    ELSIF v_current_value <> v_record.value THEN
      -- We have a new value. We can cleanup previous range
      -- Are there any records to clean up ? We need to have at least 3 records,
      -- so it means counter=4 (we're on the next batch already)
      -- else, just skip the delete
      IF v_counter>= 4 THEN
        RAISE DEBUG 'DELETE BETWEEN % and % on partition %, counter=%',v_start_range,v_previous_timet,p_partid,v_counter;
        EXECUTE 'DELETE FROM counters_detail_'||p_partid||' WHERE timet > $1 AND timet < $2' USING v_start_range,v_previous_timet;
      END IF;
      -- We reset everything for new range
      v_start_range:=v_record.timet;
      v_current_value:=v_record.value;
      v_counter:=1;
    END IF;
    -- We record previous timet for the cleanup step
    v_previous_timet:=v_record.timet;
  END LOOP;
  CLOSE v_cursor;
  -- We store the new point to which we have cleaned up
  UPDATE services SET last_cleanup=p_max_timestamp WHERE id=p_partid;
  RETURN true;
END;
$_$;

CREATE FUNCTION create_partion_on_insert_service() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE 'CREATE TABLE counters_detail_'||NEW.id|| ' (timet timestamptz primary key, value numeric)';
  RETURN NEW;
EXCEPTION
  WHEN duplicate_table THEN
  -- We truncate the table. It shouldn't have existed
  EXECUTE 'TRUNCATE TABLE counters_detail_'||NEW.id;
  RETURN NEW;
END;
$$;

CREATE FUNCTION drop_partion_on_delete_service() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE 'DROP TABLE counters_detail_'||OLD.id;
  RETURN NULL;
EXCEPTION
  WHEN undefined_table THEN
  -- We dont't care if the partition has already disappeared
  RETURN NULL;
END;
$$;

CREATE FUNCTION get_first_timestamp_db() RETURNS timestamp with time zone
    LANGUAGE plpgsql
    AS $$
 DECLARE
   l_id integer;
   l_timestamp timestamptz;
   l_result timestamptz='infinity'::timestamptz;
 BEGIN
   FOR l_id IN SELECT id FROM services LOOP
EXECUTE 'SELECT min(timet) FROM counters_detail_'||l_id INTO l_timestamp;
     IF l_timestamp IS NOT NULL THEN
       IF l_timestamp < l_result THEN
         l_result := l_timestamp;
       END IF;
     END IF;
   END LOOP;
   RETURN l_result;
 END;
 $$;

CREATE FUNCTION get_last_timestamp_db() RETURNS timestamp with time zone
    LANGUAGE plpgsql
    AS $$
DECLARE
  l_id integer;
  l_timestamp timestamptz;
  l_result timestamptz='-infinity'::timestamptz;
BEGIN
  FOR l_id IN SELECT id FROM services LOOP
    EXECUTE 'SELECT max(timet) FROM counters_detail_'||l_id INTO l_timestamp;
    IF l_timestamp IS NOT NULL THEN
      IF l_timestamp > l_result THEN
        l_result := l_timestamp;
      END IF;
    END IF;
  END LOOP;
  RETURN l_result;
END;
$$;

CREATE FUNCTION get_last_value(i_hostname text, i_service text, i_label text) RETURNS counters_detail
    LANGUAGE plpgsql STABLE
    AS $$
 DECLARE
   l_id integer;
   l_query text;
   l_rvalue counters_detail;
 BEGIN
   SELECT INTO l_id id FROM services WHERE hostname=i_hostname AND service=i_service AND label=i_label;
   IF FOUND
   THEN
     l_query := 'SELECT timet, value FROM counters_detail_' || l_id || ' ORDER BY timet DESC LIMIT 1';
   ELSE
     l_query := 'SELECT NULL::timestamptz, NULL::numeric';
   END IF;
   EXECUTE l_query INTO l_rvalue;
   RETURN l_rvalue;
 END;
 $$;

CREATE FUNCTION get_sampled_service_data(id_service bigint, timet_begin timestamp with time zone, timet_end timestamp with time zone, sample_sec integer) RETURNS TABLE(timet timestamp with time zone, value numeric)
    LANGUAGE plpgsql
    AS $_$
 BEGIN
   IF (sample_sec > 0) THEN
     RETURN QUERY EXECUTE 'SELECT min(timet), max(value) FROM counters_detail_'||id_service||' WHERE timet >= $1 AND timet <= $2  group by (extract(epoch from timet)::float8/$3)::bigint*$3' USING timet_begin,timet_end,sample_sec;
   ELSE
     RETURN QUERY EXECUTE 'SELECT min(timet), max(value) FROM counters_detail_'||id_service||' WHERE timet >= $1 AND timet <= $2' USING timet_begin,timet_end;
   END IF;
   RETURN QUERY EXECUTE 'SELECT $1, value FROM counters_detail_'||id_service||' WHERE timet <= $1 ORDER BY timet DESC LIMIT 1' USING timet_begin; -- the closest record before the first one asked
   RETURN QUERY EXECUTE 'SELECT $1, value FROM counters_detail_'||id_service||' WHERE timet >= $1 ORDER BY timet DESC LIMIT 1' USING timet_end;-- the closest record after the last one asked

 END;
  $_$;

CREATE FUNCTION get_sampled_service_data(i_hostname text, i_service text, i_label text, timet_begin timestamp with time zone, timet_end timestamp with time zone, sample_sec integer) RETURNS TABLE(timet timestamp with time zone, value numeric)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_id_service bigint;
BEGIN
  -- Find the service id
  SELECT id INTO v_id_service FROM services
    WHERE hostname=i_hostname
    AND service=i_service
    AND label=i_label;
  IF NOT FOUND THEN
    RETURN;
  ELSE
    RETURN QUERY SELECT * FROM get_sampled_service_data(v_id_service,timet_begin,timet_end,sample_sec);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION insert_record(phostname text, ptimet bigint, pservice text, pservicestate text, plabel text, pvalue numeric, punit text) RETURNS boolean
    LANGUAGE plpgsql
    AS $_$

DECLARE
  vservice record;
  vid bigint;
  vstate text;
  vunit text;
  vlastm date;
  vlastcleanup timestamptz;
  vtimet timestamptz; -- the timestamp corresponding to the ptimet epoch
BEGIN
  -- Let's retrieve the service data, we'll need it
  SELECT id,state,unit,last_modified,last_cleanup
  INTO vservice
  FROM services
  WHERE hostname=phostname AND service=pservice AND label=plabel;
  IF NOT FOUND THEN
    -- The service doesn't exist. We create it now
    -- A trigger will take care of creating the counter_detail* table
    INSERT INTO services
    (hostname,service,state,label,unit)
    VALUES (phostname,pservice,pservicestate,plabel,punit);
    -- We do the select again
    SELECT id,state,unit,last_modified,last_cleanup
    INTO vservice
    FROM services
    WHERE hostname=phostname AND service=pservice AND label=plabel;
  END IF;
  vid:=vservice.id;
  vstate:=vservice.state;
  vunit:=vservice.unit;
  vlastm:=vservice.last_modified;
  vlastcleanup:=vservice.last_cleanup;
  vtimet:='epoch'::timestamptz + ptimet * '1 second'::interval;
  -- Is service's last modified date older than a day ? We have to update service table if it's the case.
  IF (vlastm + '1 day'::interval < CURRENT_DATE) THEN
    -- We need to update
    UPDATE services SET last_modified = CURRENT_DATE WHERE id=vid;
  END IF;
  -- Has the state changed ?
  IF (vstate <> pservicestate OR vstate IS NULL) THEN
    -- We need to update
    UPDATE services SET state = pservicestate WHERE id=vid;
  END IF;
  -- Has the partition been cleaned up recently ?
  -- We cleanup data older than a week (let it settle, be sure we have received everything)
  -- So as an arbitrary rule, we clean a counter if its cleanup is older than 10 days, and cleanup until
  -- 7 days ago
  IF vlastcleanup < now() - '10 days'::interval THEN
    PERFORM cleanup_partition(vid,now()- '7 days'::interval);
  END IF;

  -- Has the unit changed ? For now, we just ignore that. But we'll have to discuss about it
  -- TODO...
  -- We insert the counter. Maybe it already exists. In this case, we trap the error and update it instead
  BEGIN
    EXECUTE 'INSERT INTO counters_detail_'|| vid
            || ' (timet, value) VALUES ($1,$2)'
            USING vtimet,pvalue;
    EXCEPTION
      WHEN unique_violation THEN
      -- We tried to insert a row that already exists. Update it instead
      EXECUTE 'UPDATE counters_detail_'|| vid
              || ' SET value = $2 WHERE timet = $1'
              USING vtimet,pvalue;
  END; -- INSERT INTO counters_detail block
  RETURN true;
END;
$_$;

CREATE FUNCTION max_timet_id(p_id bigint) RETURNS timestamp with time zone
    LANGUAGE plpgsql
    AS $$
DECLARE
v_max timestamptz;
BEGIN
EXECUTE 'SELECT max(timet) FROM counters_detail_'||p_id INTO v_max;
RETURN v_max;
END
$$;

CREATE FUNCTION min_timet_id(p_id bigint) RETURNS timestamp with time zone
    LANGUAGE plpgsql
    AS $$
DECLARE
v_min timestamptz;
BEGIN
EXECUTE 'SELECT min(timet) FROM counters_detail_'||p_id INTO v_min;
RETURN v_min;
END
$$;

SET default_tablespace = '';
SET default_with_oids = false;

CREATE TABLE services (
    id bigint NOT NULL,
    hostname text,
    service text,
    label text,
    unit text,
    last_modified date DEFAULT (now())::date,
    creation_timestamp timestamp with time zone DEFAULT now(),
    last_cleanup timestamp with time zone DEFAULT now(),
    state text
);

CREATE SEQUENCE services_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;

ALTER SEQUENCE services_id_seq OWNED BY services.id;

ALTER TABLE services ALTER COLUMN id SET DEFAULT nextval('services_id_seq'::regclass);

CREATE UNIQUE INDEX idx_services_hostname_service_label ON services USING btree (hostname, service, label);

CREATE TRIGGER create_partion_on_insert_service
    BEFORE INSERT ON services
    FOR EACH ROW
    EXECUTE PROCEDURE create_partion_on_insert_service();

CREATE TRIGGER drop_partion_on_delete_service
    AFTER DELETE ON services
    FOR EACH ROW
    EXECUTE PROCEDURE drop_partion_on_delete_service();
