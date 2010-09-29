--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = off;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET escape_string_warning = off;

--
-- Name: plpgsql; Type: PROCEDURAL LANGUAGE; Schema: -; Owner: postgres
--

CREATE PROCEDURAL LANGUAGE plpgsql;


ALTER PROCEDURAL LANGUAGE plpgsql OWNER TO postgres;

SET search_path = public, pg_catalog;

--
-- Name: create_partion_on_insert_service(); Type: FUNCTION; Schema: public; Owner: postgres
--

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


ALTER FUNCTION public.create_partion_on_insert_service() OWNER TO postgres;

--
-- Name: drop_partion_on_delete_service(); Type: FUNCTION; Schema: public; Owner: postgres
--

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


ALTER FUNCTION public.drop_partion_on_delete_service() OWNER TO postgres;

--
-- Name: get_first_timestamp_db(); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: get_last_timestamp_db(); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: get_last_value(text, text, text); Type: FUNCTION; Schema: public; Owner: nagios_perfdata
--

CREATE FUNCTION get_last_value(i_hostname text, i_service text, i_label text) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $$
declare
  l_id integer;
  l_query text;
begin
SELECT INTO l_id id FROM services WHERE hostname=i_hostname AND service=i_service AND label=i_label;
IF FOUND
THEN
  l_query := 'SELECT timet, value FROM counters_detail_' || l_id || ' ORDER BY timet DESC LIMIT 1';
ELSE
  l_query := 'SELECT NULL::timestamptz, NULL::numeric';
END IF;
RETURN QUERY EXECUTE l_query;
end;
$$;



--
-- Name: get_sampled_service_data(bigint, timestamp with time zone, timestamp with time zone, integer); Type: FUNCTION; Schema: public; Owner: postgres
--
CREATE OR REPLACE FUNCTION public.get_sampled_service_data(id_service bigint, timet_begin timestamp with time zone, timet_end timestamp with time zone, sample_sec integer)
  RETURNS TABLE(timet timestamp with time zone, value numeric)
  LANGUAGE plpgsql
 AS $function$
BEGIN
  IF (sample_sec > 0) THEN
    RETURN QUERY EXECUTE 'SELECT min(timet), max(value) FROM counters_detail_'||id_service||' WHERE timet >= $1 AND timet <= $2  group by (extract(epoch from timet)::float8/$3)::bigint*$3' USING timet_begin,timet_end,sample_sec;
  ELSE
    RETURN QUERY EXECUTE 'SELECT min(timet), max(value) FROM counters_detail_'||id_service||' WHERE timet >= $1 AND timet <= $2' USING timet_begin,timet_end;
  END IF;
END;
 $function$;

ALTER FUNCTION public.get_sampled_service_data(id_service bigint, timet_begin timestamp with time zone, timet_end timestamp with time zone, sample_sec integer) OWNER TO postgres;

--
-- Name: get_sampled_service_data(text, text, text, timestamp with time zone, timestamp with time zone, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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


ALTER FUNCTION public.get_sampled_service_data(i_hostname text, i_service text, i_label text, timet_begin timestamp with time zone, timet_end timestamp with time zone, sample_sec integer) OWNER TO postgres;

--
-- Name: insert_record(text, bigint, text, text, text, numeric, text); Type: FUNCTION; Schema: public; Owner: nagios_perfdata
--

CREATE OR REPLACE FUNCTION insert_record(phostname text, ptimet bigint, pservice text, pservicestate text, plabel text, pvalue numeric, punit text) RETURNS boolean LANGUAGE plpgsql AS
$code$
-- This function inserts a record into its detail table and inserts or updates into the service table too if required
DECLARE
  vservice record;
  vid bigint;
  vstate text;
  vunit text;
  vlastm date;
  vtimet timestamptz; -- the timestamp corresponding to the ptimet epoch
BEGIN
  -- Let's retrieve the service data, we'll need it
  SELECT id,state,unit,last_modified
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
    SELECT id,state,unit,last_modified
    INTO vservice
    FROM services
    WHERE hostname=phostname AND service=pservice AND label=plabel;
  END IF;
  vid:=vservice.id;
  vstate:=vservice.state;
  vunit:=vservice.unit;
  vlastm:=vservice.last_modified;
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
$code$;
--
-- Name: max_timet_id(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

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



--
-- Name: min_timet_id(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: services; Type: TABLE; Schema: public; Owner: nagios_perfdata; Tablespace: 
--

CREATE TABLE services (
    id bigint NOT NULL,
    hostname text,
    service text,
    state text,
    label text,
    unit text,
    last_modified date DEFAULT (now())::date,
    creation_timestamp timestamp with time zone DEFAULT now()
);



--
-- Name: services_id_seq; Type: SEQUENCE; Schema: public; Owner: nagios_perfdata
--

CREATE SEQUENCE services_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;


--
-- Name: idx_services_hostname_service_label; Type: INDEX; Schema: public; Owner: nagios_perfdata; Tablespace: 
--

CREATE UNIQUE INDEX idx_services_hostname_service_label ON services USING btree (hostname, service, label);


--
-- Name: create_partion_on_insert_service; Type: TRIGGER; Schema: public; Owner: nagios_perfdata
--

CREATE TRIGGER create_partion_on_insert_service
    BEFORE INSERT ON services
    FOR EACH ROW
    EXECUTE PROCEDURE create_partion_on_insert_service();


--
-- Name: drop_partion_on_delete_service; Type: TRIGGER; Schema: public; Owner: nagios_perfdata
--

CREATE TRIGGER drop_partion_on_delete_service
    AFTER DELETE ON services
    FOR EACH ROW
    EXECUTE PROCEDURE drop_partion_on_delete_service();


--
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- PostgreSQL database dump complete
--

