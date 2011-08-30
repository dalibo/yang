SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = off;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET escape_string_warning = off;
SET search_path = public, pg_catalog;
CREATE TYPE counters_detail AS (
	timet timestamp with time zone,
	value numeric
);
ALTER TYPE public.counters_detail OWNER TO postgres;
CREATE FUNCTION cleanup_partition(p_partid bigint) RETURNS boolean
    LANGUAGE plpgsql
    AS $_$            
DECLARE              
  v_cursor refcursor;                
  v_record record;                                                                                                                                                                                                                   
  v_current_value numeric;
  v_start_range timestamptz;                                                                                                                                  
  v_previous_timet timestamptz;                                                                                                                                                                        
  v_counter integer;                                                                                                                                                                                            
BEGIN                                                                                                                                                                                 
  
  
  OPEN v_cursor FOR EXECUTE 'SELECT timet,value FROM counters_detail_' || p_partid || ' ORDER BY timet';
  LOOP
    FETCH v_cursor INTO v_record;
    EXIT WHEN NOT FOUND; 
    v_counter:=v_counter+1;
    
    IF v_current_value IS NULL THEN
      
      v_current_value:=v_record.value;
      v_start_range:=v_record.timet;
      v_counter:=1;
    ELSIF v_current_value <> v_record.value THEN
      
      
      
      
      IF v_counter>= 4 THEN
        RAISE DEBUG 'DELETE BETWEEN % and % on partition %, counter=%',v_start_range,v_previous_timet,p_partid,v_counter;
        EXECUTE 'DELETE FROM counters_detail_'||p_partid||' WHERE timet > $1 AND timet < $2' USING v_start_range,v_previous_timet;
      END IF;
      
      v_start_range:=v_record.timet;
      v_current_value:=v_record.value;
      v_counter:=1;
    END IF;
    
    v_previous_timet:=v_record.timet;
  END LOOP;
  CLOSE v_cursor;
  RETURN true;
END;
$_$;
ALTER FUNCTION public.cleanup_partition(p_partid bigint) OWNER TO postgres;
CREATE FUNCTION cleanup_partition(p_partid bigint, p_max_timestamp timestamp with time zone) RETURNS boolean
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
  
  SELECT last_cleanup INTO v_previous_cleanup FROM services WHERE id=p_partid;
  
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  
  
  
  OPEN v_cursor FOR EXECUTE 'SELECT timet,value FROM counters_detail_' || p_partid || ' WHERE timet >= ' || quote_literal(v_previous_cleanup) || ' AND timet <= ' || quote_literal(p_max_timestamp) || ' ORDER BY timet';
  LOOP
    FETCH v_cursor INTO v_record;
    EXIT WHEN NOT FOUND; 
    v_counter:=v_counter+1;
    IF v_current_value IS NULL THEN
      
      v_current_value:=v_record.value;
      v_start_range:=v_record.timet;
      v_counter:=1;
    ELSIF v_current_value <> v_record.value THEN
      
      
      
      
      IF v_counter>= 4 THEN
        RAISE DEBUG 'DELETE BETWEEN % and % on partition %, counter=%',v_start_range,v_previous_timet,p_partid,v_counter;
        EXECUTE 'DELETE FROM counters_detail_'||p_partid||' WHERE timet > $1 AND timet < $2' USING v_start_range,v_previous_timet;
      END IF;
      
      v_start_range:=v_record.timet;
      v_current_value:=v_record.value;
      v_counter:=1;
    END IF;
    
    v_previous_timet:=v_record.timet;
  END LOOP;
  CLOSE v_cursor;
  
  UPDATE services SET last_cleanup=p_max_timestamp WHERE id=p_partid;
  RETURN true;
END;
$_$;
ALTER FUNCTION public.cleanup_partition(p_partid bigint, p_max_timestamp timestamp with time zone) OWNER TO postgres;
CREATE FUNCTION create_partion_on_insert_service() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE 'CREATE TABLE counters_detail_'||NEW.id|| ' (timet timestamptz primary key, value numeric)';
  RETURN NEW;
EXCEPTION
  WHEN duplicate_table THEN
  
  EXECUTE 'TRUNCATE TABLE counters_detail_'||NEW.id;
  RETURN NEW;
END;
$$;
ALTER FUNCTION public.create_partion_on_insert_service() OWNER TO postgres;
CREATE FUNCTION drop_partion_on_delete_service() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE 'DROP TABLE counters_detail_'||OLD.id;
  RETURN NULL;
EXCEPTION
  WHEN undefined_table THEN
  
  RETURN NULL;
END;
$$;
ALTER FUNCTION public.drop_partion_on_delete_service() OWNER TO postgres;
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
ALTER FUNCTION public.get_first_timestamp_db() OWNER TO postgres;
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
ALTER FUNCTION public.get_last_timestamp_db() OWNER TO postgres;
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
ALTER FUNCTION public.get_last_value(i_hostname text, i_service text, i_label text) OWNER TO postgres;
CREATE FUNCTION get_sampled_service_data(id_service bigint, timet_begin timestamp with time zone, timet_end timestamp with time zone, sample_sec integer) RETURNS TABLE(timet timestamp with time zone, value numeric)
    LANGUAGE plpgsql
    AS $_$
 BEGIN
   IF (sample_sec > 0) THEN
     RETURN QUERY EXECUTE 'SELECT min(timet), max(value) FROM counters_detail_'||id_service||' WHERE timet >= $1 AND timet <= $2  group by (extract(epoch from timet)::float8/$3)::bigint*$3' USING timet_begin,timet_end,sample_sec;
   ELSE
     RETURN QUERY EXECUTE 'SELECT min(timet), max(value) FROM counters_detail_'||id_service||' WHERE timet >= $1 AND timet <= $2' USING timet_begin,timet_end;
   END IF;
   RETURN QUERY EXECUTE 'SELECT $1, value FROM counters_detail_'||id_service||' WHERE timet <= $1 ORDER BY timet DESC LIMIT 1' USING timet_begin; 
   RETURN QUERY EXECUTE 'SELECT $1, value FROM counters_detail_'||id_service||' WHERE timet >= $1 ORDER BY timet DESC LIMIT 1' USING timet_end;
 END;
  $_$;
ALTER FUNCTION public.get_sampled_service_data(id_service bigint, timet_begin timestamp with time zone, timet_end timestamp with time zone, sample_sec integer) OWNER TO postgres;
CREATE FUNCTION get_sampled_service_data(i_hostname text, i_service text, i_label text, timet_begin timestamp with time zone, timet_end timestamp with time zone, sample_sec integer) RETURNS TABLE(timet timestamp with time zone, value numeric)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_id_service bigint;
BEGIN
  
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
ALTER FUNCTION public.get_sampled_service_data(i_hostname text, i_service text, i_label text, timet_begin timestamp with time zone, timet_end timestamp with time zone, sample_sec integer) OWNER TO postgres;
CREATE FUNCTION insert_record(phostname text, ptimet bigint, pservice text, pservicestate text, plabel text, pvalue numeric, pmin numeric, pmax numeric, pwarning numeric, pcritical numeric, punit text) RETURNS boolean
    LANGUAGE plpgsql
    AS $_$
DECLARE
  vservice record;
  vid bigint;
  vtimet timestamptz; 
BEGIN
  
  SELECT id,state,unit,last_modified,last_cleanup,min,max,warning,critical
  INTO vservice
  FROM services
  WHERE hostname=phostname AND service=pservice AND label=plabel;
  IF NOT FOUND THEN
    
    
    INSERT INTO services
    (hostname,service,state,label,unit,min,max,warning,critical)
    VALUES (phostname,pservice,pservicestate,plabel,punit,pmin,pmax,pwarning,pcritical);
    
    SELECT id,state,unit,last_modified,last_cleanup,min,max,warning,critical
    INTO vservice
    FROM services
    WHERE hostname=phostname AND service=pservice AND label=plabel;
  END IF;
  vid:=vservice.id;
  vtimet:='epoch'::timestamptz + ptimet * '1 second'::interval;
  
  
  
  IF (  vservice.last_modified + '1 day'::interval < CURRENT_DATE 
     OR vservice.state <> pservicestate 
     OR (vservice.min <> pmin OR (vservice.min IS NULL AND pmin IS NOT NULL)) 
     OR (vservice.max <> pmax OR (vservice.max IS NULL AND pmax IS NOT NULL))
     OR (vservice.warning <> pwarning OR (vservice.warning IS NULL AND pwarning IS NOT NULL))
     OR (vservice.critical <> pcritical OR (vservice.critical IS NULL AND pcritical IS NOT NULL))
     OR (vservice.unit <> punit OR (vservice.unit IS NULL AND punit IS NOT NULL))
     )
     THEN
    
    UPDATE services SET last_modified = CURRENT_DATE,
                        state = pservicestate,
                        min = pmin,
                        max = pmax,
                        warning = pwarning,
                        critical = pcritical,
                        unit = punit
    WHERE id=vid;
  END IF;
  
  
  
  
  IF vservice.last_cleanup < now() - '10 days'::interval THEN
    PERFORM cleanup_partition(vid,now()- '7 days'::interval);
  END IF;
  
  
  
  BEGIN
    EXECUTE 'INSERT INTO counters_detail_'|| vid
            || ' (timet, value) VALUES ($1,$2)'
            USING vtimet,pvalue;
    EXCEPTION
      WHEN unique_violation THEN
      
      EXECUTE 'UPDATE counters_detail_'|| vid
              || ' SET value = $2 WHERE timet = $1'
              USING vtimet,pvalue;
  END; 
  RETURN true;
END;
$_$;
ALTER FUNCTION public.insert_record(phostname text, ptimet bigint, pservice text, pservicestate text, plabel text, pvalue numeric, pmin numeric, pmax numeric, pwarning numeric, pcritical numeric, punit text) OWNER TO yang;
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
ALTER FUNCTION public.max_timet_id(p_id bigint) OWNER TO postgres;
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
ALTER FUNCTION public.min_timet_id(p_id bigint) OWNER TO postgres;

-- Function: get_sum_sampled_service_data(bigint[], timestamp with time zone, timestamp with time zone, integer)

-- DROP FUNCTION get_sum_sampled_service_data(bigint[], timestamp with time zone, timestamp with time zone, integer);

CREATE OR REPLACE FUNCTION get_sum_sampled_service_data(IN id_service bigint[], IN timet_begin timestamp with time zone, IN timet_end timestamp with time zone, IN sample_sec integer)
  RETURNS TABLE(timet timestamp with time zone, "value" numeric) AS
$BODY$
DECLARE
  i int;
  curs_detail refcursor;
  record_tmp record;
  record_detail record;
  curs_detail_lower timestamptz;
  curs_detail_upper timestamptz;
BEGIN
  -- This is a bit complicated: all the services won't have been collected with the exact same timets.
  -- So we generate timets at the specified interval, and for each of these timet, we retrieve the sum of all the
  -- services. It's the value just before the specified timet. We could do a query for each service, for each timet
  -- but performance would suck. So we use the content of the counters_detail_xxx tables, with a cursor, and a lag
  -- window function to be able to easily find the correct record and continue from there
  -- First, create the temp table to store our temp data.
  CREATE temp table tmp_data (timettmp timestamptz, valuetmp numeric);
  INSERT INTO tmp_data (timettmp) SELECT generate_series (timet_begin,timet_end,'1 second'::interval*sample_sec);
  CREATE INDEX tmp_indx_tmp_data ON tmp_data(timettmp);
  -- For each element of id_service, we'll have 2 cursors: one on tmp_data, and one on the counters_detail_xxx
  -- For the counters_detail_xxx, in order to restrict the data to analyze, we first determine possible boundaries
  FOR i in array_lower(id_service,1) .. array_upper(id_service,1) LOOP
    EXECUTE 'SELECT timet FROM counters_detail_'||id_service[i]|| ' WHERE timet<$1 ORDER BY timet ASC' INTO curs_detail_lower USING timet_begin;
    EXECUTE 'SELECT timet FROM counters_detail_'||id_service[i]|| ' WHERE timet>$1 ORDER BY timet DESC' INTO curs_detail_upper USING timet_end;
    IF timet_begin IS NULL THEN
      timet_begin:='-infinity'::timestamptz;
    END IF;
    IF timet_end IS NULL THEN
      timet_end:='infinity'::timestamptz;
    END IF;

    OPEN curs_detail SCROLL FOR EXECUTE 'SELECT timet,value FROM counters_detail_'||id_service[i]||' WHERE timet > $1 AND timet < $2 ORDER BY timet' USING timet_begin,timet_end;
    FOR record_tmp IN SELECT timettmp,valuetmp FROM tmp_data ORDER BY timettmp
    LOOP
      -- Look for an element in curs_detail with a matching timet
      LOOP
        FETCH NEXT FROM curs_detail INTO record_detail;
        IF record_detail IS NULL OR record_detail.timet>record_tmp.timettmp THEN -- We found
          EXIT;
        END IF;
      END LOOP;
      -- Move back one record. It's the previous one that is interesting
      FETCH PRIOR FROM curs_detail INTO record_detail;
      UPDATE tmp_data SET valuetmp = (coalesce(valuetmp,0))+coalesce(record_detail.value,0) WHERE timettmp=record_tmp.timettmp;
    END LOOP;

    CLOSE curs_detail;
  END LOOP;


  RETURN QUERY SELECT timettmp, valuetmp FROM tmp_data ORDER BY timettmp;

  DROP TABLE tmp_data;
  
  

END;
  $BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100
  ROWS 1000;
ALTER FUNCTION get_sum_sampled_service_data(bigint[], timestamp with time zone, timestamp with time zone, integer) OWNER TO yang;


SET default_tablespace = '';
SET default_with_oids = false;
CREATE TABLE services (
    id bigint NOT NULL,
    hostname text NOT NULL,
    service text NOT NULL,
    label text NOT NULL,
    unit text,
    last_modified date DEFAULT (now())::date NOT NULL,
    creation_timestamp timestamp with time zone DEFAULT now() NOT NULL,
    state text,
    last_cleanup timestamp with time zone DEFAULT now() NOT NULL,
    min numeric,
    max numeric,
    warning numeric,
    critical numeric
);
ALTER TABLE public.services OWNER TO yang;
CREATE SEQUENCE services_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER TABLE public.services_id_seq OWNER TO yang;
ALTER SEQUENCE services_id_seq OWNED BY services.id;
ALTER TABLE services ALTER COLUMN id SET DEFAULT nextval('services_id_seq'::regclass);
ALTER TABLE ONLY services
    ADD CONSTRAINT services_pkey PRIMARY KEY (id);
CREATE UNIQUE INDEX idx_services_hostname_service_label ON services USING btree (hostname, service, label);
CREATE TRIGGER create_partion_on_insert_service BEFORE INSERT ON services FOR EACH ROW EXECUTE PROCEDURE create_partion_on_insert_service();
CREATE TRIGGER drop_partion_on_delete_service AFTER DELETE ON services FOR EACH ROW EXECUTE PROCEDURE drop_partion_on_delete_service();
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;
REVOKE ALL ON FUNCTION insert_record(phostname text, ptimet bigint, pservice text, pservicestate text, plabel text, pvalue numeric, pmin numeric, pmax numeric, pwarning numeric, pcritical numeric, punit text) FROM PUBLIC;
REVOKE ALL ON FUNCTION insert_record(phostname text, ptimet bigint, pservice text, pservicestate text, plabel text, pvalue numeric, pmin numeric, pmax numeric, pwarning numeric, pcritical numeric, punit text) FROM yang;
GRANT ALL ON FUNCTION insert_record(phostname text, ptimet bigint, pservice text, pservicestate text, plabel text, pvalue numeric, pmin numeric, pmax numeric, pwarning numeric, pcritical numeric, punit text) TO yang;
GRANT ALL ON FUNCTION insert_record(phostname text, ptimet bigint, pservice text, pservicestate text, plabel text, pvalue numeric, pmin numeric, pmax numeric, pwarning numeric, pcritical numeric, punit text) TO PUBLIC;
REVOKE ALL ON TABLE services FROM PUBLIC;
REVOKE ALL ON TABLE services FROM yang;
GRANT ALL ON TABLE services TO yang;
GRANT SELECT ON TABLE services TO doku_yang;
